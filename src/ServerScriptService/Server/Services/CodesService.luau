--!strict
--[[
	Redeem codes — Code Bot v102 (live for all players, no owner gate).

	  Client: Remotes RedeemCode (RemoteFunction) :InvokeServer(code) -> { Result, Message }
	    Result = "Success" | "AlreadyUsed" | "Invalid" | "Expired" | "RateLimited" | "NotReady"
	  Codes live in Server/Configs/CodesConfig (server only; how to add a code is written at the top of that file).

	Server validation: a string of at most CodesConfig.MaxCodeLength characters; spaces are stripped and case is
	ignored; only letters, digits and _ can match. Rate limit: CodesConfig.TriesPerMinute tries per player per minute
	(token bucket, RateLimitService key "redeem_code"). Once per code per player: profile.RedeemedCodes[CODE] is set
	BEFORE any reward is paid (no double grant) and the profile is saved right after a success, so it persists.

	Rewards reuse the existing systems: Cash / Gold through EconomyService.AddCash / AddGold (reason "code" is in
	MonetizationConfig.CashMultExemptReasons, so $50,000 pays exactly $50,000), and CashBoostMinutes through the
	ONE timed boost (profile.CashBoost, applied by EconomyService.CashBoostMult to every non-exempt Cash earning).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)

local CodesConfig = require(script.Parent.Parent.Configs.CodesConfig)

local CodesService = {}

local DataService: any = nil
local EconomyService: any = nil
local NotificationService: any = nil
local RateLimitService: any = nil
local RemoteSetup: any = nil
local AnalyticsService: any = nil

export type RedeemResult = {
	Result: string,
	Message: string,
}

local MESSAGES = {
	Invalid = "That code doesn't exist. Check the spelling.",
	AlreadyUsed = "You've already redeemed this code.",
	Expired = "This code has expired.",
	RateLimited = "Too many tries. Wait a minute and try again.",
	NotReady = "Still loading your data. Try again in a moment.",
}

-- CODE (normalized) -> { Def, ExpiresUnix? }; built once from CodesConfig (keys are normalized, so the owner may
-- write them in any case)
type Entry = { Key: string, Def: any, ExpiresUnix: number? }
local lookup: { [string]: Entry } = {}

function CodesService.Normalize(raw: string): string
	return string.upper((string.gsub(raw, "%s+", "")))
end

-- "YYYY-MM-DD" = the END of that day (UTC); "YYYY-MM-DDTHH:MM:SSZ" = that exact UTC time. nil = bad / none.
function CodesService.ParseExpiry(s: any): number?
	if typeof(s) ~= "string" then
		return nil
	end
	local y, m, d = string.match(s, "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if y then
		local ok, dt = pcall(DateTime.fromUniversalTime, tonumber(y), tonumber(m), tonumber(d), 23, 59, 59)
		if ok and dt then
			return dt.UnixTimestamp
		end
		return nil
	end
	local ok, dt = pcall(DateTime.fromIsoDate, s)
	if ok and dt then
		return dt.UnixTimestamp
	end
	return nil
end

local function buildLookup()
	table.clear(lookup)
	for key, def in pairs(CodesConfig.Codes) do
		if typeof(key) ~= "string" or typeof(def) ~= "table" then
			warn("[CodesService] skipped a bad CodesConfig entry:", key)
			continue
		end
		local code = CodesService.Normalize(key)
		if code == "" or #code > CodesConfig.MaxCodeLength or not string.match(code, "^[%w_]+$") then
			warn("[CodesService] skipped CodesConfig code (letters/digits/_ only, <= MaxCodeLength):", key)
			continue
		end
		if lookup[code] then
			warn("[CodesService] duplicate CodesConfig code (case-insensitive), keeping the first:", key)
			continue
		end
		local expires: number? = nil
		if def.Expires ~= nil then
			expires = CodesService.ParseExpiry(def.Expires)
			if expires == nil then
				-- a typo in the date must not make a code live forever: treat it as expired
				warn("[CodesService] bad Expires for code " .. code .. " (use \"YYYY-MM-DD\"); code treated as expired")
				expires = 0
			end
		end
		lookup[code] = { Key = code, Def = def, ExpiresUnix = expires }
	end
end
buildLookup()

local function redeemedList(profile: any): { string }
	local list: { string } = {}
	if typeof(profile.RedeemedCodes) == "table" then
		for id in pairs(profile.RedeemedCodes) do
			table.insert(list, id)
		end
	end
	table.sort(list)
	return list
end

local function boostUntil(profile: any): number
	local b = profile.CashBoost
	if typeof(b) == "table" then
		return tonumber(b.Until) or 0
	end
	return 0
end

local function pushState(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	local untilUnix = boostUntil(profile)
	player:SetAttribute("WE_CashBoostUntil", if untilUnix > os.time() then untilUnix else nil)
	local remote = RemoteSetup.Get(Constants.RemoteNames.CodeStateUpdate) :: RemoteEvent
	remote:FireClient(player, {
		Redeemed = redeemedList(profile),
		CashBoostUntil = untilUnix,
	})
end

--[[ The ONE timed Cash boost (EconomyService.CashBoostMult reads it). Adds minutes on top of a running boost,
	capped at CodesConfig.CashBoostMaxMinutes from now. ]]
function CodesService.GrantCashBoost(player: Player, minutes: number, mult: number?): number
	local profile = DataService.GetProfile(player)
	if not profile or not (minutes > 0) then
		return 0
	end
	local now = os.time()
	local b = profile.CashBoost
	if typeof(b) ~= "table" then
		b = { Until = 0, Mult = 1 }
		profile.CashBoost = b
	end
	local m = math.clamp(mult or CodesConfig.CashBoostMult, 1, 10)
	local oldUntil = tonumber(b.Until) or 0
	local running = oldUntil > now
	local base = math.max(now, oldUntil)
	local untilUnix = math.min(base + math.floor(minutes * 60), now + CodesConfig.CashBoostMaxMinutes * 60)
	untilUnix = math.max(untilUnix, oldUntil) -- never shortens a running boost
	b.Mult = if running then math.max(m, tonumber(b.Mult) or 1) else m
	b.Until = untilUnix
	DataService.MarkDirty(player)
	player:SetAttribute("WE_CashBoostUntil", untilUnix)
	return untilUnix
end

local function commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s
	while true do
		local nxt, k = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
		out = nxt
		if k == 0 then
			break
		end
	end
	return out
end

local function rewardText(r: any): string
	local parts: { string } = {}
	local cash = math.floor(tonumber(r.Cash) or 0)
	if cash > 0 then
		table.insert(parts, "$" .. commas(cash))
	end
	local gold = math.floor(tonumber(r.Gold) or 0)
	if gold > 0 then
		table.insert(parts, string.format("%d Gold", gold))
	end
	local mins = math.floor(tonumber(r.CashBoostMinutes) or 0)
	if mins > 0 then
		table.insert(parts, string.format("%d min %gx Cash", mins, CodesConfig.CashBoostMult))
	end
	return table.concat(parts, " + ")
end

local function result(kind: string, message: string?): RedeemResult
	return { Result = kind, Message = message or MESSAGES[kind] or "Something went wrong." }
end

--[[ Validate + grant. Never trusts the client: any junk is "Invalid". Rate limiting is done by the remote. ]]
function CodesService.Redeem(player: Player, rawCode: any): RedeemResult
	if typeof(rawCode) ~= "string" or #rawCode == 0 or #rawCode > 64 then
		return result("Invalid")
	end
	local code = CodesService.Normalize(rawCode :: string)
	if code == "" or #code > CodesConfig.MaxCodeLength or not string.match(code, "^[%w_]+$") then
		return result("Invalid")
	end
	local entry = lookup[code]
	if not entry then
		return result("Invalid")
	end
	local profile = DataService.GetProfile(player)
	if not profile or (DataService.IsLoaded and not DataService.IsLoaded(player)) then
		return result("NotReady")
	end
	if typeof(profile.RedeemedCodes) ~= "table" then
		profile.RedeemedCodes = {}
	end
	if profile.RedeemedCodes[code] then
		return result("AlreadyUsed")
	end
	local def = entry.Def
	if def.Active ~= true or (entry.ExpiresUnix ~= nil and os.time() > entry.ExpiresUnix) then
		return result("Expired")
	end

	-- mark first (a yield inside a grant can never let the same code pay twice), then pay
	profile.RedeemedCodes[code] = os.time()
	DataService.MarkDirty(player)

	local r = if typeof(def.Rewards) == "table" then def.Rewards else {}
	local cash = math.floor(tonumber(r.Cash) or 0)
	local gold = math.floor(tonumber(r.Gold) or 0)
	local mins = tonumber(r.CashBoostMinutes) or 0
	if cash > 0 then
		EconomyService.AddCash(player, cash, "code")
	end
	if gold > 0 then
		EconomyService.AddGold(player, gold, "code")
	end
	if mins > 0 then
		CodesService.GrantCashBoost(player, mins, CodesConfig.CashBoostMult)
	end

	-- persist now (once per code per player, so this is a handful of saves per player, ever)
	task.spawn(function()
		pcall(DataService.SaveProfile, player, false)
	end)

	local what = rewardText(r)
	if NotificationService then
		pcall(NotificationService.Notify, player, "Code redeemed: " .. what, "Reward")
	end
	if AnalyticsService then
		pcall(AnalyticsService.Log, AnalyticsConfig.Events.CODE_REDEEM, player.UserId, {
			code = code,
			cash = cash,
			gold = gold,
			boostMinutes = mins,
		})
	end
	pushState(player)
	return result("Success", "Redeemed! You got " .. what .. ".")
end

function CodesService.Push(player: Player)
	pushState(player)
end

function CodesService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	NotificationService = deps.NotificationService
	RateLimitService = deps.RateLimitService
	RemoteSetup = deps.RemoteSetup
	AnalyticsService = deps.AnalyticsService

	local perMin = math.max(1, CodesConfig.TriesPerMinute)
	local fn = RemoteSetup.Get(Constants.RemoteNames.RedeemCode) :: RemoteFunction
	fn.OnServerInvoke = function(player: Player, code: any): RedeemResult
		if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RedeemCode", code) then -- claude-bud JOB 15: rate ceiling + argument schema
			return result("RateLimited")
		end
		-- 5 tries per minute: bucket of 5, refilled at 5 per 60 s
		if not RateLimitService.Allow(player, "redeem_code", perMin / 60, perMin) then
			return result("RateLimited")
		end
		local ok, res = pcall(CodesService.Redeem, player, code)
		if not ok then
			warn("[CodesService] redeem failed:", res)
			return result("NotReady", "Something went wrong. Try again.")
		end
		return res
	end

	DataService.OnProfileLoaded(function(player: Player, _profile: any)
		pushState(player)
	end)
	-- the boost attribute clears itself when a boost ends (display only; the grant check is always os.time())
	task.spawn(function()
		while true do
			task.wait(15)
			local now = os.time()
			for _, p in ipairs(Players:GetPlayers()) do
				local u = p:GetAttribute("WE_CashBoostUntil")
				if typeof(u) == "number" and u <= now then
					p:SetAttribute("WE_CashBoostUntil", nil)
				end
			end
		end
	end)
	local n = 0
	for _ in pairs(lookup) do
		n += 1
	end
	print(string.format("[CodesService] ready (%d codes, RedeemCode RemoteFunction, %d tries/min)", n, perMin))
end

return CodesService
