--!strict
--[[
	OpsRewards — job pay, player cooldowns and the saved Ops block (W3 step 2 Phase B, lane O; contract §2.4, §4.5).
	SERVER ONLY. Nothing here trusts the client: R (base passive income per second before multipliers) comes from the
	player's own saved BaseUpgrades through TycoonMath, never from a remote.

	Pay = clamp(Floor, round(Minutes x 60 x R), Cap) x Private x Diminish x Event          (OpsConfig.Rewards)
	  R        = TycoonMath.BasePassivePerTick(profile.BaseUpgrades) / TycoonMath.TickSeconds()
	  Private  = Rewards.PrivateMult (0.5) when game.PrivateServerOwnerId ~= 0 (cash AND XP)
	  Diminish = Rewards.Diminish {1, 0.5, 0.25} by runs of this pay row today (UTC): 1..DimN, DimN+1..2 DimN, then
	  Event    = 1 (Vault Window is Phase C: Director.Events.Enabled = false)
	Cash goes through EconomyService.AddCash(player, pay, "ops") (wallet; "ops" is multiplier-exempt: OpsService stays
	off until MonetizationConfig.CashMultExemptReasons has it) and XP through XPService.AddXP(player, xp, "ops").

	profile.Ops (ProfileSchema default + sanitise; accessed as (profile :: any).Ops, no DataVersion bump):
	  Cd = { [siteId] = os.time() until } (per player per site, saved), DayKey (UTC day of Runs), Runs = { [payRow] = n },
	  Seen (bit flags), Total (lifetime job cash), BestBag (best single bag).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local OpsConfig = require(Shared.Configs.OpsConfig)
local TycoonMath = require(Shared.Util.TycoonMath)

local OpsRewards = {}

local R = OpsConfig.Rewards
local PROFILE = OpsConfig.Profile

local EconomyService: any = nil
local XPService: any = nil
local MissionService: any = nil
local DataService: any = nil
local AnalyticsService: any = nil

local listeners: { { Fn: (Player, string, string, number) -> () } } = {}
local privateOverride: boolean? = nil -- headless drivers only

function OpsRewards.Init(deps: { [string]: any })
	EconomyService = deps.EconomyService
	XPService = deps.XPService
	MissionService = deps.MissionService
	DataService = deps.DataService
	AnalyticsService = deps.AnalyticsService
end

-- whole number >= 0 (junk -> 0)
local function nonNeg(v: any): number
	local n = tonumber(v)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return 0
	end
	return math.max(0, math.floor(n))
end

function OpsRewards.FormatCash(n: number): string
	local s = string.format("%d", math.floor(math.abs(n) + 0.5))
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return out
end

function OpsRewards.DayKey(nowUnix: number): number
	return math.floor(nowUnix / 86400)
end

--[[ The player's Ops block, created with the ProfileSchema defaults when missing (a profile loaded before this build
	ran Migrate always has one; this is only a guard). Rolls Runs over at the UTC day change. nil = no profile. ]]
function OpsRewards.Block(profile: any, nowUnix: number?): any
	if typeof(profile) ~= "table" then
		return nil
	end
	local ops = profile.Ops
	if typeof(ops) ~= "table" then
		ops = { Cd = {}, DayKey = 0, Runs = {}, Seen = 0, Total = 0, BestBag = 0 }
		profile.Ops = ops
	end
	if typeof(ops.Cd) ~= "table" then
		ops.Cd = {}
	end
	if typeof(ops.Runs) ~= "table" then
		ops.Runs = {}
	end
	local day = OpsRewards.DayKey(nowUnix or os.time())
	if ops.DayKey ~= day then
		ops.DayKey = day
		ops.Runs = {}
	end
	return ops
end

-- base passive income per second before multipliers (never from the client)
function OpsRewards.PerSecond(profile: any): number
	local upgrades = if typeof(profile) == "table" and typeof(profile.BaseUpgrades) == "table" then profile.BaseUpgrades else nil
	local ok, perTick = pcall(TycoonMath.BasePassivePerTick, upgrades)
	local tick = TycoonMath.TickSeconds()
	if not ok or typeof(perTick) ~= "number" or perTick ~= perTick or not (tick > 0) then
		return 0
	end
	return math.max(0, perTick / tick)
end

function OpsRewards.SetPrivateOverride(v: boolean?)
	privateOverride = v
end

function OpsRewards.IsPrivate(): boolean
	if privateOverride ~= nil then
		return privateOverride
	end
	local ok, owner = pcall(function(): any
		return (game :: any).PrivateServerOwnerId
	end)
	return ok and typeof(owner) == "number" and owner ~= 0
end

function OpsRewards.PrivateMult(): number
	return if OpsRewards.IsPrivate() then R.PrivateMult else 1
end

-- the Diminish step for this pay row today (0-based runs already paid)
function OpsRewards.DiminishMult(ops: any, payRow: string): number
	local row = R.Rows[payRow]
	if row == nil or typeof(ops) ~= "table" then
		return 1
	end
	local runs = nonNeg(typeof(ops.Runs) == "table" and ops.Runs[payRow] or 0)
	local n = math.max(1, row.DimN)
	local steps = R.Diminish
	local idx = if runs < n then 1 elseif runs < 2 * n then 2 else 3
	return steps[math.min(idx, #steps)] or 1
end

--[[ What this player would be paid now for `site` (cash, xp): no side effects. Used for OpsState.Pay, the bag value
	at grab time and every completion. ]]
function OpsRewards.Quote(profile: any, site: OpsConfig.SiteDef, nowUnix: number?): (number, number)
	local row = R.Rows[site.Pay]
	if row == nil or typeof(profile) ~= "table" then
		return 0, 0
	end
	local ops = OpsRewards.Block(profile, nowUnix)
	local base = math.clamp(math.floor(row.Minutes * 60 * OpsRewards.PerSecond(profile) + 0.5), row.Floor, row.Cap)
	local priv = OpsRewards.PrivateMult()
	local cash = math.floor(base * priv * OpsRewards.DiminishMult(ops, site.Pay) + 0.5)
	local xp = math.floor(row.XP * priv + 0.5)
	return cash, xp
end

-- every cooldown / StudioCdDivisor in Studio
function OpsRewards.CdScale(): number
	if RunService:IsStudio() == true then
		return 1 / math.max(1, R.StudioCdDivisor)
	end
	return 1
end

function OpsRewards.Seconds(n: number): number
	return n * OpsRewards.CdScale()
end

-- seconds until this player may do this site again (0 = now)
function OpsRewards.CdLeft(profile: any, siteId: string, nowUnix: number): number
	local ops = OpsRewards.Block(profile, nowUnix)
	if ops == nil then
		return 0
	end
	local v = ops.Cd[siteId]
	if typeof(v) ~= "number" or v ~= v then
		return 0
	end
	return math.max(0, math.ceil(v - nowUnix))
end

function OpsRewards.SetCd(player: Player, profile: any, site: OpsConfig.SiteDef, nowUnix: number)
	local row = R.Rows[site.Pay]
	local ops = OpsRewards.Block(profile, nowUnix)
	if row == nil or ops == nil or row.PlayerCd <= 0 then
		return
	end
	ops.Cd[site.Id] = nowUnix + math.ceil(OpsRewards.Seconds(row.PlayerCd))
	if DataService and DataService.MarkDirty then
		DataService.MarkDirty(player)
	end
end

--[[ Listeners of OpsService.OnJobDone(fn): fn(player, siteId, kind, pay), each in its own pcall. ]]
function OpsRewards.OnJobDone(fn: (Player, string, string, number) -> ()): () -> ()
	local entry = { Fn = fn }
	table.insert(listeners, entry)
	return function()
		local i = table.find(listeners, entry)
		if i then
			table.remove(listeners, i)
		end
	end
end

--[[ Pay one player for one finished job (or one delivered bag): the wallet, XP, today's run count, the lifetime
	totals, mission progress (Kinds[kind].Track) and the OnJobDone listeners. `bag` = the cash came from a delivered
	bag (BestBag). Returns false (nothing paid, nothing counted) when AddCash refuses (no profile). ]]
function OpsRewards.Grant(player: Player, site: OpsConfig.SiteDef, cash: number, xp: number, bag: boolean?): boolean
	if EconomyService == nil or EconomyService.AddCash == nil then
		return false
	end
	cash = math.floor(cash + 0.5)
	if cash <= 0 then
		return false
	end
	if EconomyService.AddCash(player, cash, R.CashReason) ~= true then
		return false
	end
	if xp > 0 and XPService and XPService.AddXP then
		local ok, err = pcall(XPService.AddXP, player, xp, R.XPReason)
		if not ok then
			warn("[Ops] AddXP failed: " .. tostring(err))
		end
	end
	local profile = DataService and DataService.GetProfile(player)
	local ops = OpsRewards.Block(profile, os.time())
	if ops ~= nil then
		ops.Runs[site.Pay] = nonNeg(ops.Runs[site.Pay]) + 1
		ops.Total = math.min(nonNeg(ops.Total) + cash, 1e15)
		if bag == true and cash > nonNeg(ops.BestBag) then
			ops.BestBag = cash
		end
		DataService.MarkDirty(player)
	end
	local kind = OpsConfig.Kinds[site.Kind]
	if kind and MissionService and MissionService.TrackProgress then
		for _, t in ipairs(kind.Track) do
			local ok, err = pcall(MissionService.TrackProgress, player, t, 1)
			if not ok then
				warn("[Ops] TrackProgress " .. t .. " failed: " .. tostring(err))
			end
		end
	end
	for _, entry in ipairs(table.clone(listeners)) do
		local ok, err = pcall(entry.Fn :: any, player, site.Id, site.Kind, cash)
		if not ok then
			warn("[Ops] OnJobDone listener error: " .. tostring(err))
		end
	end
	return true
end

-- the Seen bit flags (OpsConfig.Profile.SeenBits)
function OpsRewards.HasSeen(profile: any, bit: number): boolean
	local ops = OpsRewards.Block(profile)
	return ops ~= nil and bit32.band(nonNeg(ops.Seen), bit) ~= 0
end

function OpsRewards.MarkSeen(player: Player, profile: any, bit: number)
	local ops = OpsRewards.Block(profile)
	if ops == nil then
		return
	end
	ops.Seen = math.clamp(bit32.bor(nonNeg(ops.Seen), bit), 0, PROFILE.SeenMax)
	if DataService and DataService.MarkDirty then
		DataService.MarkDirty(player)
	end
end

--[[ Legacy bank cooldown (lane F, profile.Raid.BankCooldownUntil): read ONCE at profile load as
	max(Raid.BankCooldownUntil, Ops.Cd["Town.Bank"]) into Ops.Cd; from then on only Ops is written. ]]
function OpsRewards.AdoptBankCooldown(profile: any, nowUnix: number)
	local ops = OpsRewards.Block(profile, nowUnix)
	if ops == nil then
		return
	end
	local raid = profile.Raid
	local legacy = if typeof(raid) == "table" then tonumber(raid.BankCooldownUntil) else nil
	if legacy == nil or legacy ~= legacy or legacy <= nowUnix then
		return
	end
	legacy = math.min(legacy, nowUnix + PROFILE.MaxCdAhead)
	local cur = tonumber(ops.Cd["Town.Bank"]) or 0
	if legacy > cur then
		ops.Cd["Town.Bank"] = math.floor(legacy)
	end
end

function OpsRewards.Log(event: string, userId: number?, props: { [string]: any }?)
	if AnalyticsService and AnalyticsService.Log then
		pcall(AnalyticsService.Log, event, userId, props)
	end
end

return OpsRewards
