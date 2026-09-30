--!strict
--[[
	claude-bud JOB 39 (2026-09-30): ENDGAME PROGRESSION, the server side (EndgameConfig, owner-first).
	Phase 1:
	  * the Rebirth price scale: BaseService.PurchaseUpgrade asks EndgameService.ScaledCost for every structure /
	    business buy. WE_BaseCostScale (player attribute, display only) tells the client's price labels; nil = 1.
	  * EMPIRE LEVEL: profile.Endgame.EmpireLevel (0..30), kept through both rebirth paths (PrestigeService never
	    touches profile.Endgame). EconomyService.cashMultFor multiplies by EmpireMultFor (non-exempt reasons only).
	  * the plaza stations: publishes each live station's frame (ReplicatedStorage.WE_PlazaStations) from the
	    Enterables registry (a plaza house) or a store prop's forecourt; the client builds them for live players only.
	Phase 2:
	  * BASE TIER 1..5 (bought at the HQ console = the player's own Command Center console): gate HP, soldier cap,
	    AutoGun nests, the gate rebuild time, and the look (BaseTierBuilder, rebuilt by the 5 s sweep).
	  * the DEFENCE tree (Plating / Guns / Gate / Vault x 10, bought at the Engineering Bureau): read by
	    GateDefenseService (GateHpMult / RebuildCut / TurretHpMult / TurretDmgMult / ExtraNests) and
	    MoneyCollectorService.VaultMult. Every helper returns the old number while its part is not live for the OWNER.
	  * the instant REBUILD (the HQ console): a breached gate / shot-down AutoGuns at once for 30 s of income (>= 25k).
	ONE purchase path (Purchase(player, kind, id)): the flag, the requirement, the price from config (never from the
	client), the station / console reach, not hurt in the last HurtLockSeconds, then ONE SpendCash("endgame_" .. key),
	the change, save, push. Remotes: RequestEndgameBuy (kind, id?) and RequestEndgameState () through RemoteGate +
	RateLimitService; the state goes back as FeaturePush "EndgameState".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local EndgameConfig = require(Shared.Configs.EndgameConfig)
local PlazaServicesConfig = require(Shared.Configs.PlazaServicesConfig)
local PrestigeConfig = require(Shared.Configs.PrestigeConfig)
local ResearchConfig = require(Shared.Configs.ResearchConfig)

local EndgameService = {}

local deps: { [string]: any } = {}
local hurtAt: { [number]: number? } = {}
local stationCF: { [string]: any } = {} -- station kind -> the station frame (CFrame)
local profileOwner: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any -- profile -> UserId
local clock: () -> number = os.clock

local DEF_NAMES = { Plating = "Turret Plating", Guns = "Turret Guns", Gate = "Gate & Walls", Vault = "Vault Plating" }

local function getProfile(player: Player): any
	local ds = deps.DataService
	return if ds and ds.GetProfile then ds.GetProfile(player) else nil
end

local function profileOf(userId: number): any
	local p = Players:GetPlayerByUserId(userId)
	return if p then getProfile(p) else nil
end

local function notify(player: Player, text: string, kind: string?)
	local ns = deps.NotificationService
	if player.Parent and ns and ns.Notify then
		pcall(ns.Notify, player, text, kind or "Info", 4)
	end
end

local function nonNeg(v: any): number
	local n = tonumber(v) or 0
	if n ~= n then
		return 0
	end
	return math.max(0, math.floor(n))
end

local function maxMult(): number
	return tonumber((ResearchConfig :: any).MaxMult) or 3
end

-- profile.Endgame, created on demand (ProfileSchema sanitises it on load)
function EndgameService.Data(profile: any): any
	if typeof(profile.Endgame) ~= "table" then
		profile.Endgame = { EmpireLevel = 0 }
	end
	return profile.Endgame
end

function EndgameService.EmpireLevel(profile: any): number
	local e = if typeof(profile) == "table" then profile.Endgame else nil
	if typeof(e) ~= "table" then
		return 0
	end
	return math.min(nonNeg(e.EmpireLevel), EndgameConfig.Empire.MaxLevel)
end

function EndgameService.Tier(profile: any): number
	local e = if typeof(profile) == "table" then profile.Endgame else nil
	if typeof(e) ~= "table" then
		return 0
	end
	return math.min(nonNeg(e.BaseTier), #EndgameConfig.BaseTier.Tiers)
end

function EndgameService.DefenceLevel(profile: any, track: string): number
	local e = if typeof(profile) == "table" then profile.Endgame else nil
	local d = if typeof(e) == "table" and typeof(e.Defence) == "table" then e.Defence else nil
	if d == nil then
		return 0
	end
	return math.min(nonNeg(d[track]), EndgameConfig.Defence.MaxLevel)
end

-- §2.1 the price factor for this player now (1 while the Rebirth part is not live for him)
function EndgameService.CostScale(userId: number, profile: any): number
	if typeof(profile) ~= "table" or not EndgameConfig.LiveFor(userId, "Rebirth") then
		return 1
	end
	return EndgameConfig.RebirthCostScale(nonNeg(profile.Prestige))
end

-- the price BaseService charges for a structure / business level (raw cost when the part is off)
function EndgameService.ScaledCost(player: Player, profile: any, structureId: string, cost: number): number
	return EndgameConfig.ScaleStructureCost(structureId, cost, EndgameService.CostScale(player.UserId, profile))
end

-- the Empire cash factor (EconomyService.cashMultFor, non-exempt reasons); 1 while the part is not live
function EndgameService.EmpireMultFor(player: Player, profile: any): number
	if not EndgameConfig.LiveFor(player.UserId, "EmpireLevel") then
		return 1
	end
	return EndgameConfig.EmpireMult(EndgameService.EmpireLevel(profile))
end

-- ── phase 2 effects (by the base OWNER's UserId; the old number while the part is not live) ─────────────────────
local function tierOf(userId: number): number
	if not EndgameConfig.LiveFor(userId, "BaseTier") then
		return 0
	end
	return EndgameService.Tier(profileOf(userId))
end

local function defOf(userId: number, track: string): number
	if not EndgameConfig.LiveFor(userId, "Defence") then
		return 0
	end
	return EndgameService.DefenceLevel(profileOf(userId), track)
end

-- gate HP: Base Tier (+10 % at T1 / T2 / T4) and Gate & Walls (+12 % a level), capped at MaxMult
function EndgameService.GateHpMult(userId: number): number
	local pct = EndgameConfig.TierEffects(tierOf(userId)).GateHpPct + defOf(userId, "Gate") * EndgameConfig.Defence.GatePct
	return math.min(1 + pct / 100, maxMult())
end

-- the gate rebuild seconds: base + Base Tier 3 (-10) - Gate & Walls (3 a level), never under MinRebuildSeconds
function EndgameService.RebuildCut(userId: number, base: number): number
	local tierS = EndgameConfig.TierEffects(tierOf(userId)).RebuildSeconds
	local gate = defOf(userId, "Gate")
	if tierS == 0 and gate == 0 then
		return base
	end
	return math.max(EndgameConfig.BaseTier.MinRebuildSeconds, base + tierS - gate * EndgameConfig.Defence.GateRebuildPerLevel)
end

function EndgameService.TurretHpMult(userId: number): number
	return math.min(1 + defOf(userId, "Plating") * EndgameConfig.Defence.PlatingPct / 100, maxMult())
end

-- turret damage: the research bonus x Turret Guns, the total capped at MaxMult (the research bonus alone when off)
function EndgameService.TurretDmgMult(userId: number, research: number): number
	local g = defOf(userId, "Guns")
	if g == 0 then
		return research
	end
	return math.min(research * (1 + g * EndgameConfig.Defence.GunsPct / 100), maxMult())
end

function EndgameService.ExtraNests(userId: number): number
	return EndgameConfig.TierEffects(tierOf(userId)).Nests
end

-- the Base Tier soldiers for SoldierService's cap (0 until the owner's profile is known / the part is live)
function EndgameService.SoldierCapBonus(profile: any): number
	local uid = profileOwner[profile]
	if uid == nil or not EndgameConfig.LiveFor(uid, "BaseTier") then
		return 0
	end
	return EndgameConfig.TierEffects(EndgameService.Tier(profile)).SoldierCap
end

-- the victim's Vault Plating: army raids x (1 - 0.05 L), ATM raids x (1 - 0.03 L)
function EndgameService.VaultMult(userId: number, army: boolean): number
	local L = defOf(userId, "Vault")
	local per = if army then EndgameConfig.Defence.VaultArmyPerLevel else EndgameConfig.Defence.VaultAtmPerLevel
	return math.max(0, 1 - per * L)
end

local function setAttr(player: Player, name: string, value: any)
	if player:GetAttribute(name) ~= value then
		player:SetAttribute(name, value)
	end
end

-- display attributes: WE_EndgameLive (the client builds stations / panels), WE_EmpireLevel, WE_BaseCostScale,
-- WE_PlotId (the HQ console the client puts its prompt on), WE_BaseTier
function EndgameService.SyncAttributes(player: Player)
	local profile = getProfile(player)
	if profile == nil then
		return
	end
	profileOwner[profile] = player.UserId
	local anyLive = EndgameConfig.AnyLiveFor(player.UserId)
	setAttr(player, "WE_EndgameLive", if anyLive then true else nil)
	local empire = if EndgameConfig.LiveFor(player.UserId, "EmpireLevel") then EndgameService.EmpireLevel(profile) else 0
	setAttr(player, "WE_EmpireLevel", if empire > 0 then empire else nil)
	local scale = EndgameService.CostScale(player.UserId, profile)
	setAttr(player, "WE_BaseCostScale", if scale > 1 then scale else nil)
	setAttr(player, "WE_PlotId", if anyLive then tonumber(profile.BasePlotId) else nil)
	local tier = tierOf(player.UserId)
	setAttr(player, "WE_BaseTier", if tier > 0 then tier else nil)
end

-- the station frame for a station kind, or nil until the world registered it
function EndgameService.StationFrame(kind: string): CFrame?
	return stationCF[kind]
end

-- the NPC's world position for a station kind
function EndgameService.StationPoint(kind: string): Vector3?
	local cf = stationCF[kind]
	local st = PlazaServicesConfig.Stations[kind]
	if cf == nil or st == nil then
		return nil
	end
	return (cf * CFrame.new(st.NpcAt)).Position
end

-- (true) when the player stands within BuyRange of the station's NPC
function EndgameService.AtStation(player: Player, kind: string): boolean
	local p = EndgameService.StationPoint(kind)
	local c = player.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	if p == nil or r == nil or not r:IsA("BasePart") then
		return false
	end
	return (r.Position - p).Magnitude <= EndgameConfig.Station.BuyRange
end

-- at the player's own Command Center console (the HQ console): BaseService's console rule
function EndgameService.AtHQ(player: Player): boolean
	local bs = deps.BaseService
	if bs == nil or bs.IsAtConsole == nil then
		return false
	end
	local ok, at = pcall(bs.IsAtConsole, player, "CommandCenter")
	return ok and at == true
end

function EndgameService.RecentlyHurt(player: Player): boolean
	local t = hurtAt[player.UserId]
	return t ~= nil and clock() - t < EndgameConfig.Station.HurtLockSeconds
end

local function short(n: number): string
	if n >= 1e9 then
		return string.format("%.2fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e3 then
		return string.format("%.0fK", n / 1e3)
	end
	return tostring(math.floor(n))
end

local function incomePerSec(player: Player): number
	return tonumber(player:GetAttribute("WE_IncomePerSec")) or 0
end

function EndgameService.RebuildPrice(player: Player): number
	local D = EndgameConfig.Defence
	return EndgameConfig.IncomeMinutesPrice(D.InstantRebuildMin, D.InstantRebuildSeconds / 60, incomePerSec(player))
end

local function plotId(profile: any): number?
	return tonumber(profile.BasePlotId)
end

local function needsRebuild(profile: any): boolean
	local gd = deps.GateDefenseService
	local pid = plotId(profile)
	if gd == nil or gd.NeedsRebuild == nil or pid == nil then
		return false
	end
	local ok, v = pcall(gd.NeedsRebuild, pid)
	return ok and v == true
end

-- the next Base Tier's row (nil at max): { Tier, Name, Cost, Need (text or nil) }
function EndgameService.NextTier(profile: any): { [string]: any }?
	local t = EndgameService.Tier(profile) + 1
	local row: any = EndgameConfig.BaseTier.Tiers[t]
	if row == nil then
		return nil
	end
	local T = EndgameConfig.Text
	local need: string? = nil
	if nonNeg(profile.Prestige) < (tonumber(row.NeedRebirths) or 0) then
		need = string.format(T.NeedRebirths, row.NeedRebirths)
	elseif row.NeedCC and nonNeg(typeof(profile.BaseUpgrades) == "table" and profile.BaseUpgrades.CommandCenter or 0) < row.NeedCC then
		need = string.format(T.NeedCC, row.NeedCC)
	end
	return { Tier = t, Name = row.Name, Cost = row.Cost, Need = need }
end

-- the next level of a Defence track (nil at max): { Level, Cost, Need }
function EndgameService.NextDefence(profile: any, track: string): { [string]: any }?
	local L = EndgameService.DefenceLevel(profile, track) + 1
	local cost = EndgameConfig.DefenceCost(L)
	if cost == nil then
		return nil
	end
	local needT = EndgameConfig.DefenceNeedTier(L)
	local need = if EndgameService.Tier(profile) < needT then string.format(EndgameConfig.Text.NeedTier, needT) else nil
	return { Level = L, Cost = cost, Need = need }
end

local function defEffect(track: string, L: number): string
	local D = EndgameConfig.Defence
	if track == "Plating" then
		return string.format("+%d%% turret HP", D.PlatingPct * L)
	elseif track == "Guns" then
		return string.format("+%d%% turret damage", D.GunsPct * L)
	elseif track == "Gate" then
		return string.format("+%d%% gate HP, -%d s rebuild", D.GatePct * L, D.GateRebuildPerLevel * L)
	end
	return string.format("-%d%% raid loot", math.floor(D.VaultAtmPerLevel * L * 100 + 0.5))
end

-- what the client's panels show (display only; Purchase re-checks everything)
function EndgameService.State(player: Player): { [string]: any }
	local profile = getProfile(player)
	local uid = player.UserId
	local out: { [string]: any } = { Live = EndgameConfig.AnyLiveFor(uid) }
	if profile == nil then
		return out
	end
	if EndgameConfig.LiveFor(uid, "EmpireLevel") then
		local L = EndgameService.EmpireLevel(profile)
		out.Empire = {
			Level = L,
			Max = EndgameConfig.Empire.MaxLevel,
			Pct = math.floor((EndgameConfig.EmpireMult(L) - 1) * 100 + 0.5),
			NextCost = EndgameConfig.EmpireCost(L + 1),
			NextPct = EndgameConfig.Empire.CashPctPerLevel,
			Milestone = EndgameConfig.Empire.Milestones[L + 1],
		}
	end
	if EndgameConfig.LiveFor(uid, "Rebirth") then
		local p = nonNeg(profile.Prestige)
		out.Rebirth = {
			Scale = EndgameConfig.RebirthCostScale(p),
			NextScale = EndgameConfig.RebirthCostScale(p + 1),
			NextBase = EndgameConfig.LifeCost(EndgameConfig.RebirthCostScale(p + 1)),
			Next = PrestigeConfig.NextRebirths(p, 1, nil)[1],
		}
	end
	if EndgameConfig.LiveFor(uid, "BaseTier") then
		local t = EndgameService.Tier(profile)
		out.Tier = { Level = t, Max = #EndgameConfig.BaseTier.Tiers, Name = if t > 0 then (EndgameConfig.BaseTier.Tiers :: any)[t].Name else nil, Next = EndgameService.NextTier(profile) }
	end
	if EndgameConfig.LiveFor(uid, "Defence") then
		local rows = {}
		for _, track in ipairs(EndgameConfig.Defence.Tracks) do
			local L = EndgameService.DefenceLevel(profile, track)
			local nx = EndgameService.NextDefence(profile, track)
			table.insert(rows, {
				Id = track,
				Name = DEF_NAMES[track] or track,
				Level = L,
				Max = EndgameConfig.Defence.MaxLevel,
				Now = if L > 0 then defEffect(track, L) else "none yet",
				Next = if nx then defEffect(track, nx.Level) else nil,
				NextCost = if nx then nx.Cost else nil,
				Need = if nx then nx.Need else nil,
			})
		end
		out.Defence = rows
		out.Rebuild = { Need = needsRebuild(profile), Price = EndgameService.RebuildPrice(player) }
	end
	local points: { [string]: any } = {}
	for kind, st in pairs(PlazaServicesConfig.Stations) do
		local pt = EndgameService.StationPoint(kind)
		if pt and EndgameConfig.LiveFor(uid, st.Part) then
			points[kind] = { X = pt.X, Y = pt.Y, Z = pt.Z }
		end
	end
	out.Stations = points
	return out
end

function EndgameService.Push(player: Player)
	local rs = deps.RemoteSetup
	local ev = rs and rs.Get(Constants.RemoteNames.FeaturePush)
	if ev and ev:IsA("RemoteEvent") then
		(ev :: RemoteEvent):FireClient(player, "EndgameState", EndgameService.State(player))
	end
end

type Plan = { Key: string, Price: number, Apply: (profile: any) -> string, Log: string }

--[[ What a purchase would do: (plan) or (nil, why). Every rule the client might skip is checked here: the part is
	live, the place (station / HQ console), not hurt, the requirement, the level cap. The price is config's. ]]
function EndgameService._Plan(player: Player, profile: any, kind: string, id: string?): (Plan?, string?)
	local T = EndgameConfig.Text
	local uid = player.UserId
	if kind == "Empire" then
		if not EndgameConfig.LiveFor(uid, "EmpireLevel") then
			return nil, T.NotLive
		end
		if not EndgameService.AtStation(player, "Command") then
			return nil, T.NotHere
		end
		if EndgameService.RecentlyHurt(player) then
			return nil, T.Hurt
		end
		local L = EndgameService.EmpireLevel(profile)
		local price = EndgameConfig.EmpireCost(L + 1)
		if price == nil then
			return nil, T.Max
		end
		return {
			Key = "empire",
			Price = price,
			Log = string.format("Command empire ok L=%d price=%d mult=%.2f", L + 1, price, EndgameConfig.EmpireMult(L + 1)),
			Apply = function(p: any): string
				EndgameService.Data(p).EmpireLevel = L + 1
				return string.format(T.EmpireBought, L + 1, math.floor((EndgameConfig.EmpireMult(L + 1) - 1) * 100 + 0.5))
			end,
		}
	elseif kind == "Tier" then
		if not EndgameConfig.LiveFor(uid, "BaseTier") then
			return nil, T.NotLive
		end
		if not EndgameService.AtHQ(player) then
			return nil, T.NotAtHQ
		end
		if EndgameService.RecentlyHurt(player) then
			return nil, T.Hurt
		end
		local nx = EndgameService.NextTier(profile)
		if nx == nil then
			return nil, "Base Tier maxed"
		end
		if nx.Need then
			return nil, nx.Need
		end
		return {
			Key = "tier",
			Price = nx.Cost,
			Log = string.format("HQ tier ok T=%d price=%d", nx.Tier, nx.Cost),
			Apply = function(p: any): string
				EndgameService.Data(p).BaseTier = nx.Tier
				return string.format(T.TierBought, nx.Tier, string.upper(nx.Name))
			end,
		}
	elseif kind == "Defence" then
		local track = id
		if not EndgameConfig.LiveFor(uid, "Defence") then
			return nil, T.NotLive
		end
		if typeof(track) ~= "string" or DEF_NAMES[track] == nil then
			return nil, "Unknown"
		end
		if not EndgameService.AtStation(player, "Engineers") then
			return nil, "Go to the Engineering Bureau"
		end
		if EndgameService.RecentlyHurt(player) then
			return nil, T.Hurt
		end
		local tr: string = track
		local nx = EndgameService.NextDefence(profile, tr)
		if nx == nil then
			return nil, DEF_NAMES[tr] .. " maxed"
		end
		if nx.Need then
			return nil, nx.Need
		end
		return {
			Key = "defence",
			Price = nx.Cost,
			Log = string.format("Engineers %s ok L=%d price=%d", tr, nx.Level, nx.Cost),
			Apply = function(p: any): string
				local e = EndgameService.Data(p)
				if typeof(e.Defence) ~= "table" then
					e.Defence = {}
				end
				e.Defence[tr] = nx.Level
				return string.format(T.DefenceBought, DEF_NAMES[tr], nx.Level)
			end,
		}
	elseif kind == "Rebuild" then
		if not EndgameConfig.LiveFor(uid, "Defence") then
			return nil, T.NotLive
		end
		if not EndgameService.AtHQ(player) then
			return nil, T.NotAtHQ
		end
		if not needsRebuild(profile) then
			return nil, T.NothingDown
		end
		local price = EndgameService.RebuildPrice(player)
		local pid = plotId(profile)
		return {
			Key = "rebuild",
			Price = price,
			Log = string.format("HQ rebuild ok price=%d", price),
			Apply = function(_p: any): string
				local gd = deps.GateDefenseService
				if gd and gd.InstantRebuild and pid then
					pcall(gd.InstantRebuild, pid)
				end
				return T.Rebuilt
			end,
		}
	end
	return nil, "Unknown"
end

--[[ THE one purchase path. kind: "Empire" | "Tier" | "Defence" (id = the track) | "Rebuild". The client sends only
	kind / id. Returns (ok, message). ]]
function EndgameService.Purchase(player: Player, kind: string, id: string?): (boolean, string)
	local profile = getProfile(player)
	if profile == nil then
		return false, "Loading"
	end
	local plan, why = EndgameService._Plan(player, profile, kind, id)
	if plan == nil then
		return false, why or "Unknown"
	end
	local eco = deps.EconomyService
	if eco == nil or eco.SpendCash == nil then
		return false, "Not ready"
	end
	local price = plan.Price
	local cash = nonNeg(profile.Cash)
	if cash < price then
		return false, string.format(EndgameConfig.Text.Short, short(price - cash))
	end
	local key = plan.Key
	local ok, err = eco.SpendCash(player, price, "endgame_" .. key)
	if not ok then
		return false, tostring(err or "SpendFailed")
	end
	profile = getProfile(player) or profile
	local msg = plan.Apply(profile)
	if deps.DataService and deps.DataService.MarkDirty then
		deps.DataService.MarkDirty(player)
	end
	print("[Station] " .. plan.Log)
	pcall(EndgameService.SyncAttributes, player)
	local bss = deps.BaseSignService
	if bss and bss.Refresh then
		pcall(bss.Refresh, profile.BasePlotId)
	end
	if key == "tier" or key == "defence" then
		-- the gate HP / turret HP / nests follow at once; the look follows on the next sweep (or now)
		local gd = deps.GateDefenseService
		local pid = plotId(profile)
		if gd and gd.SyncPlot and pid then
			task.defer(function()
				pcall(gd.SyncPlot, pid)
				task.wait(0.5)
				pcall(EndgameService.SyncBaseTier, player)
			end)
		end
		local ss = deps.SoldierService
		if key == "tier" and ss and ss.PushState then
			pcall(ss.PushState, player)
		end
	end
	return true, msg
end

-- ── the Base Tier look (server-built, shared: everyone sees a base's tier) ────────────────────────────────────────
local function basesFolder(): Instance?
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	return setup and setup:FindFirstChild("Bases")
end

local function plotContext(pid: number, plotFolder: Instance): any?
	local pad = plotFolder:FindFirstChild("PlotPad")
	if pad == nil or not pad:IsA("BasePart") then
		return nil
	end
	local okL, BaseLayout = pcall(function(): any
		return require(script.Parent.Parent.Modules.BaseLayout)
	end)
	if not okL or BaseLayout == nil then
		return nil
	end
	local groundY = pad.Position.Y + pad.Size.Y * 0.5
	local ground = BaseLayout.PlotCFrame(pad.Position) * CFrame.new(0, pad.Size.Y * 0.5, 0)
	local wallTop = groundY + 10
	local walls = plotFolder:FindFirstChild("WE_PerimeterWalls")
	if walls then
		for _, w in ipairs(walls:GetChildren()) do
			if w:IsA("BasePart") then
				wallTop = math.max(wallTop, w.Position.Y + w.Size.Y * 0.5)
			end
		end
	end
	local hq: any = nil
	for _, c in ipairs(plotFolder:GetChildren()) do
		if c:GetAttribute("StructureId") == "CommandCenter" and c:GetAttribute("WE_Console") ~= true then
			for _, b in ipairs(c:GetChildren()) do
				if b:IsA("Model") and b:GetAttribute("StructureId") == "CommandCenter" then
					local cf, size = b:GetBoundingBox()
					hq = { CFrame = cf, Size = size }
				end
			end
		end
	end
	local gd = deps.GateDefenseService
	local posts = {}
	local rawPosts = if gd and gd._Posts then gd._Posts[pid] else nil
	for _, p in ipairs(rawPosts or {}) do
		if p.Parent then
			table.insert(posts, { CFrame = p.CFrame, Size = p.Size })
		end
	end
	local gate = if gd and gd.GetGateCFrame then gd.GetGateCFrame(pid) else nil
	return {
		Ground = ground,
		PadCentre = pad.Position,
		HalfX = pad.Size.X * 0.5 - 1.5,
		HalfZ = pad.Size.Z * 0.5 - 1.5,
		WallTop = wallTop,
		GroundY = groundY,
		Posts = posts,
		Gate = gate,
		Nests = (if gd and gd._Nests then gd._Nests[pid] else nil) or {},
		HQ = hq,
	}
end

-- build / rebuild / drop one player's WE_BaseTier model (the key: tier, HQ level, walls, nests)
function EndgameService.SyncBaseTier(player: Player)
	local profile = getProfile(player)
	local pid = if profile then plotId(profile) else nil
	local bases = basesFolder()
	if profile == nil or pid == nil or bases == nil then
		return
	end
	local plotFolder = bases:FindFirstChild("Plot" .. tostring(pid))
	if plotFolder == nil then
		return
	end
	local existing = plotFolder:FindFirstChild("WE_BaseTier")
	local tier = tierOf(player.UserId)
	if tier <= 0 then
		if existing then
			existing:Destroy()
		end
		return
	end
	local ctx = plotContext(pid :: number, plotFolder)
	if ctx == nil then
		return
	end
	-- the key: the owner, the tier, the Command Center level (its building is rebuilt on a level change), the walls
	local cc = if typeof(profile.BaseUpgrades) == "table" then tonumber(profile.BaseUpgrades.CommandCenter) or 0 else 0
	local key = string.format("%d|%d|%d|%s|%.1f|%d|%d", player.UserId, tier, cc, tostring(ctx.HQ ~= nil), ctx.WallTop, #ctx.Nests, #ctx.Posts)
	if existing and existing:GetAttribute("WE_TierKey") == key then
		return
	end
	local okB, BTB = pcall(function(): any
		return require(script.Parent.Parent.Modules.BaseTierBuilder)
	end)
	if not okB or BTB == nil then
		return
	end
	local model, parts, lights = BTB.Build(ctx, tier)
	model:SetAttribute("WE_TierKey", key)
	model:SetAttribute("OwnerUserId", player.UserId)
	if existing then
		existing:Destroy()
	end
	model.Parent = plotFolder
	print(string.format("[BaseTier] plot=%d tier=%d parts=%d lights=%d", pid, tier, parts, lights))
end

-- drop a WE_BaseTier model whose owner no longer holds that plot (the plot is free for the next player)
local function sweepOrphans()
	local bases = basesFolder()
	if bases == nil then
		return
	end
	for _, f in ipairs(bases:GetChildren()) do
		local m = f:FindFirstChild("WE_BaseTier")
		if m then
			local uid = tonumber(m:GetAttribute("OwnerUserId"))
			local owner = if uid then Players:GetPlayerByUserId(uid) else nil
			local prof = if owner then getProfile(owner) else nil
			if prof == nil or ("Plot" .. tostring(prof.BasePlotId)) ~= f.Name then
				m:Destroy()
			end
		end
	end
end

local function watchCharacter(player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid", 10)
	if hum == nil or not hum:IsA("Humanoid") then
		return
	end
	local last = hum.Health
	hum.HealthChanged:Connect(function(h: number)
		if h < last then
			hurtAt[player.UserId] = clock()
		end
		last = h
	end)
end

-- a store prop's forecourt: ForecourtStuds out of the box face nearest the plaza, local -Z pointing away from it
local function forecourtFrame(model: Model, toward: Vector3, out: number): CFrame
	local cf, size = model:GetBoundingBox()
	local best: CFrame? = nil
	local bestD = math.huge
	for _, dir in ipairs({ Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis }) do
		local wdir = cf:VectorToWorldSpace(dir)
		local flat = Vector3.new(wdir.X, 0, wdir.Z)
		if flat.Magnitude > 0.5 then
			flat = flat.Unit
			local half = math.abs(dir.X) * size.X * 0.5 + math.abs(dir.Z) * size.Z * 0.5
			local p = cf.Position + flat * (half + out)
			local ground = Vector3.new(p.X, cf.Position.Y - size.Y * 0.5, p.Z)
			local d = (Vector3.new(toward.X, 0, toward.Z) - Vector3.new(p.X, 0, p.Z)).Magnitude
			if d < bestD then
				bestD = d
				best = CFrame.lookAt(ground, ground + flat)
			end
		end
	end
	return best or cf
end

-- publish the live stations' frames once their buildings exist (the world builds at start; store props later)
local function publishStations()
	local folder = ReplicatedStorage:FindFirstChild(PlazaServicesConfig.FolderName)
	if folder == nil then
		local f = Instance.new("Folder")
		f.Name = PlazaServicesConfig.FolderName
		f.Parent = ReplicatedStorage
		folder = f
	end
	local okE, Ent = pcall(function(): any
		return require(script.Parent.Parent.Modules.Enterables)
	end)
	if not okE or Ent == nil then
		return
	end
	local function house(row: string): CFrame?
		for _, e in ipairs(Ent.List()) do
			if e.Id == row then
				return e.CF
			end
		end
		return nil
	end
	local function publish(kind: string, cf: CFrame, how: string)
		stationCF[kind] = cf
		local v = Instance.new("CFrameValue")
		v.Name = kind
		v.Value = cf
		v.Parent = folder
		print(string.format("[Station] %s published at %s (%s)", kind, tostring(cf.Position), how))
	end
	local tries = 90
	for i = 1, tries do
		local missing = false
		for kind, st in pairs(PlazaServicesConfig.Stations) do
			if (EndgameConfig.Parts :: any)[st.Part] == true and stationCF[kind] == nil then
				if st.Row then
					local cf = house(st.Row)
					if cf then
						publish(kind, cf, st.Row)
					else
						missing = true
					end
				elseif st.StoreProp then
					local wf = Workspace:FindFirstChild("WorldFill")
					local sp = wf and wf:FindFirstChild("StoreProps")
					local prop = sp and sp:FindFirstChild("Store_" .. tostring(st.StoreProp))
					local toward = house("NE_N1") or CFrame.new()
					if prop and prop:IsA("Model") then
						publish(kind, forecourtFrame(prop, toward.Position, st.ForecourtStuds or 7), "store prop " .. tostring(st.StoreProp))
					elseif i == tries or (i >= 30 and house(st.FallbackRow) ~= nil) then
						local hcf = house(st.FallbackRow)
						if hcf then
							publish(kind, hcf * CFrame.new(st.FallbackOffset), "fallback beside " .. st.FallbackRow)
						else
							missing = true
						end
					else
						missing = true
					end
				end
			end
		end
		if not missing then
			return
		end
		task.wait(2)
	end
	warn("[Station] some plaza stations never found their building (PlazaBuildingsConfig rows / store props)")
end

-- test hooks
function EndgameService._SetStation(kind: string, cf: CFrame?)
	stationCF[kind] = cf
end
function EndgameService._SetClock(fn: () -> number)
	clock = fn
end
function EndgameService._Hurt(uid: number, t: number?)
	hurtAt[uid] = t
end
function EndgameService._Own(profile: any, uid: number)
	profileOwner[profile] = uid
end

function EndgameService.Init(d: { [string]: any })
	deps = d
	if EndgameConfig.Live.Enabled ~= true then
		return
	end
	task.spawn(publishStations)
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(c: Model)
			task.spawn(watchCharacter, player, c)
		end)
		if player.Character then
			task.spawn(watchCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(p: Player)
		hurtAt[p.UserId] = nil
	end)
	if d.DataService and d.DataService.OnProfileLoaded then
		d.DataService.OnProfileLoaded(function(player: Player)
			pcall(EndgameService.SyncAttributes, player)
		end)
	end
	-- the rebirth count / live state / the base look change rarely: a slow sweep (1 per 5 s) keeps them right
	task.spawn(function()
		while true do
			task.wait(5)
			for _, p in ipairs(Players:GetPlayers()) do
				pcall(EndgameService.SyncAttributes, p)
				pcall(EndgameService.SyncBaseTier, p)
			end
			pcall(sweepOrphans)
		end
	end)
	local rs = d.RemoteSetup
	local buy = rs and rs.Get(Constants.RemoteNames.RequestEndgameBuy)
	if buy and buy:IsA("RemoteEvent") then
		(buy :: RemoteEvent).OnServerEvent:Connect(function(player: Player, kind: any, id: any)
			if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestEndgameBuy", kind, id) then
				return
			end
			if d.RateLimitService and not d.RateLimitService.Allow(player, "endgame_buy", EndgameConfig.Station.RatePerSec, EndgameConfig.Station.Burst) then
				return
			end
			if typeof(kind) ~= "string" or not EndgameConfig.AnyLiveFor(player.UserId) then
				return
			end
			local ok, msg = EndgameService.Purchase(player, kind, if typeof(id) == "string" then id else nil)
			notify(player, msg, if ok then "Success" else "Warn")
			EndgameService.Push(player)
		end)
	end
	local ask = rs and rs.Get(Constants.RemoteNames.RequestEndgameState)
	if ask and ask:IsA("RemoteEvent") then
		(ask :: RemoteEvent).OnServerEvent:Connect(function(player: Player)
			if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestEndgameState") then
				return
			end
			if d.RateLimitService and not d.RateLimitService.Allow(player, "endgame_state", 2, 4) then
				return
			end
			if EndgameConfig.AnyLiveFor(player.UserId) then
				EndgameService.Push(player)
			end
		end)
	end
	print("[WAR EMPIRE] EndgameService Init")
end

return EndgameService
