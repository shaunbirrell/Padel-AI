--!strict
--[[
	Default player profile + migrations.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local EconomyConfig = require(Shared.Configs.EconomyConfig)
local SoldierConfig = require(Shared.Configs.SoldierConfig)
local VehicleConfig = require(Shared.Configs.VehicleConfig)
local WeaponConfig = require(Shared.Configs.WeaponConfig)
local SeasonConfig = require(Shared.Configs.SeasonConfig)
local BaseConfig = require(Shared.Configs.BaseConfig)
local Types = require(Shared:WaitForChild("Types"))

type PlayerProfile = Types.PlayerProfile

local ProfileSchema = {}

local function emptyUpgrades(): { [string]: number }
	local upgrades: { [string]: number } = {}
	for id in pairs(BaseConfig.Structures) do
		upgrades[id] = 0
	end
	return upgrades
end

local function emptyDailyMissions(): Types.DailyMissionProgress
	return {
		DayKey = 0,
		Progress = {},
		Claimed = {},
		ActiveTimed = {},
	}
end

-- v71 money (M2) ─────────────────────────────────────────────────────────────────────────────────────────────
-- New profile blocks for the nuke, premium vehicles, rebirth expansion, the Offer Director and purchase accounting.
-- Default-filled and sanitised on every Migrate (idempotent), with no DataVersion bump, the same way as v69
-- Research / Raid. Nothing reads them yet. PrestigeService.DoPrestige resets only the fields it names, so rebirth
-- keeps all of these.
local NUKE_KINDS: { [string]: boolean } = { Nuke = true, TacticalNuke = true }
local NUKE_STAT_KEYS = { "Bought", "Launched", "PlayerKills", "NpcKills", "BestKills" }
local OFFER_STAT_KEYS = { "Shown", "LastShownUnix", "Clicked", "Dismissed" }
local MONETIZATION_KEYS = { "FirstPurchaseUnix", "LastPurchaseUnix", "Purchases", "RobuxSpent" }
local MAX_COUNTER = 1e15 -- keeps junk like 1e308 out of the save; far above any real count / os.time()

-- Whole number >= 0; junk (nil, strings, NaN, inf, negatives) becomes 0.
local function nonNegInt(value: any): number
	local n = tonumber(value)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return 0
	end
	return math.clamp(math.floor(n), 0, MAX_COUNTER)
end

local function sanitizeCounters(t: any, keys: { string }): { [string]: number }
	local out: { [string]: number } = if typeof(t) == "table" then t else {}
	for _, k in ipairs(keys) do
		local v = out[k]
		local clean = nonNegInt(v)
		if v ~= clean then
			out[k] = clean
		end
	end
	return out
end

local function defaultNukeStats()
	return { Bought = 0, Launched = 0, PlayerKills = 0, NpcKills = 0, BestKills = 0 }
end

local function defaultMonetization()
	return { FirstPurchaseUnix = 0, LastPurchaseUnix = 0, Purchases = 0, RobuxSpent = 0 }
end

local function ensureMoneyFields(profile: any)
	-- Nuke inventory (paid Nukes are granted only in ProcessReceipt) and the launch refund marker
	profile.Nukes = nonNegInt(profile.Nukes)
	profile.TacticalNukes = nonNegInt(profile.TacticalNukes)
	local inFlight = profile.NukeInFlight
	if inFlight ~= nil then
		if
			typeof(inFlight) ~= "table"
			or typeof(inFlight.Kind) ~= "string"
			or NUKE_KINDS[inFlight.Kind] ~= true
		then
			profile.NukeInFlight = nil
		else
			if typeof(inFlight.LaunchId) ~= "string" then
				inFlight.LaunchId = tostring(inFlight.LaunchId or "")
			end
			local at = nonNegInt(inFlight.At)
			if inFlight.At ~= at then
				inFlight.At = at
			end
		end
	end
	if typeof(profile.NukeGiftGranted) ~= "boolean" then
		profile.NukeGiftGranted = false
	end
	profile.NukeStats = sanitizeCounters(profile.NukeStats, NUKE_STAT_KEYS)
	profile.Silo = sanitizeCounters(profile.Silo, { "ProgressSeconds" })

	-- Premium vehicles: chosen camo per vehicle, last free test drive per vehicle
	local camo = if typeof(profile.PremiumVehicleCamo) == "table" then profile.PremiumVehicleCamo else {}
	for k, v in pairs(camo) do
		if typeof(k) ~= "string" or typeof(v) ~= "string" then
			camo[k] = nil
		end
	end
	profile.PremiumVehicleCamo = camo
	local trials = if typeof(profile.PremiumTrials) == "table" then profile.PremiumTrials else {}
	for k, v in pairs(trials) do
		if typeof(k) ~= "string" then
			trials[k] = nil
		else
			local clean = nonNegInt(v)
			if v ~= clean then
				trials[k] = clean
			end
		end
	end
	profile.PremiumTrials = trials

	-- Rebirth expansion (the Expansion Permit / Rebirth Skip counters were cut, J12; F7 replaced the Rebirth Skip
	-- idea with the keep-base token profile.KeepBaseRebirths, sanitised in ensureFeatureFields below)
	local rebirth = if typeof(profile.Rebirth) == "table" then profile.Rebirth else {}
	local seen = if typeof(rebirth.ZonesSeen) == "table" then rebirth.ZonesSeen else {}
	for k, v in pairs(seen) do
		if typeof(k) ~= "string" or v ~= true then
			seen[k] = nil
		end
	end
	rebirth.ZonesSeen = seen
	local lastRebirth = nonNegInt(rebirth.LastRebirthUnix)
	if rebirth.LastRebirthUnix ~= lastRebirth then
		rebirth.LastRebirthUnix = lastRebirth
	end
	profile.Rebirth = rebirth

	-- Offer Director cadence (offer key -> counters) and purchase accounting (analytics only)
	local offers = if typeof(profile.Offers) == "table" then profile.Offers else {}
	for k, v in pairs(offers) do
		if typeof(k) ~= "string" or typeof(v) ~= "table" then
			offers[k] = nil
		else
			sanitizeCounters(v, OFFER_STAT_KEYS)
		end
	end
	profile.Offers = offers
	profile.Monetization = sanitizeCounters(profile.Monetization, MONETIZATION_KEYS)

	-- M8: purchase ticker opt-out (default on) and the daily VIP supply stamp
	if typeof(profile.AnnouncePurchases) ~= "boolean" then
		profile.AnnouncePurchases = true
	end
	profile.VipSupplyAt = nonNegInt(profile.VipSupplyAt)
end

-- Owner's 11 features (lane K1) ─────────────────────────────────────────────────────────────────────────────
-- Tutorial step order of this build. A profile's TutorialOrderVersion says which order its TutorialStep index was
-- saved in (missing = 1, the pre-F6 order); TutorialService migrates old indexes (TutorialConfig.LegacyOrderV1) and
-- then stamps the current version. New profiles take TutorialConfig.OrderVersion (2 once the F6 order ships; 1 until
-- then, so a profile made before that build is still migrated). A config error falls back to 1 (never blocks a load).
local function currentTutorialOrderVersion(): number
	local ok, cfg = pcall(function()
		return require(Shared.Configs.TutorialConfig) :: any
	end)
	local v = if ok and typeof(cfg) == "table" then tonumber(cfg.OrderVersion) else nil
	if v == nil or v ~= v or v < 1 or v == math.huge then
		return 1
	end
	return math.floor(v)
end
local TUTORIAL_ORDER_VERSION = currentTutorialOrderVersion()

-- Default-fill + sanitise the F6 / F7 / F10 fields (idempotent, no DataVersion bump). raw* are the values the saved
-- data had BEFORE the v0 default fill in Migrate, so "missing" keeps its own meaning for very old saves.
--   KeepBaseRebirths      whole number >= 0 (F7 keep-base tokens; added only by ProcessReceipt, spent by PrestigeService)
--   TutorialOrderVersion  whole number >= 1; missing = 1
--   NoviceShieldDone      boolean; missing = TutorialComplete (a player who finished the tutorial never gets it)
--   StarterOutpostTaken   boolean; missing = false (F10 first Home Outpost capture)
local function ensureFeatureFields(profile: any, rawTutorialOrder: any, rawShieldDone: any)
	profile.KeepBaseRebirths = nonNegInt(profile.KeepBaseRebirths)
	profile.SoldierRefills = nonNegInt(profile.SoldierRefills) -- claude-bud JOB 5c (ProcessReceipt only; SoldierService spends)
	profile.AirstrikeCharges = nonNegInt(profile.AirstrikeCharges) -- claude-bud JOB 5c (ProcessReceipt only; PlazaAirstrike spends)
	profile.PremiumBonusDay = nonNegInt(profile.PremiumBonusDay) -- claude-bud JOB 5e: UTC yyyymmdd of the last Premium bonus
	if profile.WelcomeShown ~= true then
		profile.WelcomeShown = nil -- claude-bud JOB 7: the first-join welcome line was shown
	end
	if profile.FirstAttackDone ~= true then
		profile.FirstAttackDone = nil -- claude-bud JOB 7: he has ordered ATTACK once (the hint is done)
	end
	-- claude-bud JOB 13: invite bookkeeping (who invited this account, the inviter's daily count)
	profile.ReferredBy = if typeof(profile.ReferredBy) == "number" and profile.ReferredBy > 0 then math.floor(profile.ReferredBy) else nil
	profile.InviteDay = nonNegInt(profile.InviteDay)
	profile.InviteCount = nonNegInt(profile.InviteCount)
	-- v104 (Code Bot): friends-bonus daily cap + comeback once-per-absence bookkeeping
	profile.FriendsDay = nonNegInt(profile.FriendsDay)
	profile.FriendsPaid = nonNegInt(profile.FriendsPaid)
	profile.ComebackPaidFor = nonNegInt(profile.ComebackPaidFor)
	profile.ComebackPaidAt = nonNegInt(profile.ComebackPaidAt)
	-- claude-bud JOB 29: retention bookkeeping (os.time() seconds; 0 / nil = never)
	profile.LastSeenUnix = nonNegInt(profile.LastSeenUnix)
	profile.PrevSeenUnix = nil -- session-only (DataService sets it on load)
	profile.OfflineCapFullAt = nonNegInt(profile.OfflineCapFullAt)
	profile.LastRaidedAt = nonNegInt(profile.LastRaidedAt)
	profile.ArmyBoostUntil = nonNegInt(profile.ArmyBoostUntil)
	profile.StarterPayoutDone = if profile.StarterPayoutDone == true then true else nil
	-- claude-bud JOB 33: rebirth zones (zoneId -> level 0..3), the silo, the life's play time
	if typeof(profile.RebirthZones) == "table" then
		local z = {}
		for id, lv in pairs(profile.RebirthZones) do
			if typeof(id) == "string" and #id <= 24 then
				z[id] = math.clamp(nonNegInt(lv), 0, 3)
			end
		end
		profile.RebirthZones = z
	else
		profile.RebirthZones = nil
	end
	if typeof(profile.NukeSilo) == "table" then
		profile.NukeSilo = { Ready = math.clamp(nonNegInt(profile.NukeSilo.Ready), 0, 10), ChargeFrom = nonNegInt(profile.NukeSilo.ChargeFrom) }
	else
		profile.NukeSilo = nil
	end
	profile.NukeLastLaunch = nonNegInt(profile.NukeLastLaunch)
	profile.LifePlaySeconds = nonNegInt(profile.LifePlaySeconds)
	profile.RebirthReadyLogged = if profile.RebirthReadyLogged == true then true else nil
	-- claude-bud JOB 34: when each achievement was earned (id -> os.time()) + the one-time quiet backfill flag
	if typeof(profile.AchievementsAt) == "table" then
		local at = {}
		for id, t in pairs(profile.AchievementsAt) do
			if typeof(id) == "string" and #id <= 32 then
				at[id] = nonNegInt(t)
			end
		end
		profile.AchievementsAt = at
	else
		profile.AchievementsAt = nil
	end
	profile.AchievementsSeeded = if profile.AchievementsSeeded == true then true else nil
	if typeof(profile.NotifOptIn) == "table" then
		local n = profile.NotifOptIn
		local r = if n.Result == "accepted" or n.Result == "declined" or n.Result == "unavailable" then n.Result else nil
		profile.NotifOptIn = { Result = r, PromptedAt = nonNegInt(n.PromptedAt), DeclinedAt = nonNegInt(n.DeclinedAt) }
	else
		profile.NotifOptIn = nil
	end
	-- claude-bud BOARDS: the notice boards' own counters (validated kills, the week, the biggest army)
	if typeof(profile.LB) ~= "table" then
		profile.LB = nil
	else
		local lb = profile.LB
		lb.Week = if typeof(lb.Week) == "string" and #lb.Week <= 8 then lb.Week else nil
		lb.Kills = nonNegInt(lb.Kills)
		lb.KillsW = nonNegInt(lb.KillsW)
		lb.PlazaBase = nonNegInt(lb.PlazaBase)
		lb.ArmyMax = nonNegInt(lb.ArmyMax)
		lb.Seeded = if lb.Seeded == true then true else nil
	end
	if typeof(profile.Settings) == "table" and profile.Settings.SupporterBoardOptOut ~= true then
		profile.Settings.SupporterBoardOptOut = nil
	end
	if profile.GroupRewardClaimed ~= true then
		profile.GroupRewardClaimed = nil -- claude-bud JOB 5e: true once the group reward was paid
	end
	if rawTutorialOrder == nil then
		profile.TutorialOrderVersion = 1
	else
		local order = nonNegInt(rawTutorialOrder)
		profile.TutorialOrderVersion = if order >= 1 then order else 1
	end
	if typeof(rawShieldDone) == "boolean" then
		profile.NoviceShieldDone = rawShieldDone
	else
		profile.NoviceShieldDone = profile.TutorialComplete == true
	end
	if typeof(profile.StarterOutpostTaken) ~= "boolean" then
		profile.StarterOutpostTaken = false
	end
end

-- Nations (cosmetic country, nations spec section 2) ────────────────────────────────────────────────────────
-- Default-fill + sanitise on every load (idempotent, no DataVersion bump: the ensureFeatureFields precedent).
--   NationId           nil = never picked (the picker asks again), NationConfig.NeutralId ("No flag", stored as a
--                      value so it is never asked again), or an id NationConfig.Get accepts. Anything else (unknown,
--                      denied, switched off in OwnerReview, not a string) becomes nil, so that player re-picks free.
--   NationSetAt        whole number >= 0: os.time() of the last accepted change (0 = never)
--   NationFreeUntil    whole number >= 0: end of the free re-pick window (0 = not started)
--   NationFreeChanges  whole number >= 0: changes made inside the free window
--   NationPrompts      whole number 0..99: LATER count (the join picker stops at NationConfig.MaxJoinPrompts)
-- NationColorId (the legacy 8-colour banner id, v4) is never touched here.
-- NationConfig is loaded in a pcall (the TutorialConfig precedent above): a broken config edit must never block a
-- profile load. Without it, a saved string id of 1..8 bytes is kept as it is (nothing is lost) and anything else
-- becomes nil.
local MAX_NATION_PROMPTS = 99
local nationCfgOk, nationCfg = pcall(function()
	return require(Shared.Configs.NationConfig) :: any
end)
local NationConfig: any = if nationCfgOk and typeof(nationCfg) == "table" and typeof(nationCfg.Get) == "function"
	then nationCfg
	else nil

local function ensureNationFields(profile: any)
	local id = profile.NationId
	if NationConfig ~= nil then
		if id ~= NationConfig.NeutralId and NationConfig.Get(id) == nil then
			profile.NationId = nil
		end
	elseif typeof(id) ~= "string" or #id < 1 or #id > 8 then
		profile.NationId = nil
	end
	profile.NationSetAt = nonNegInt(profile.NationSetAt)
	profile.NationFreeUntil = nonNegInt(profile.NationFreeUntil)
	profile.NationFreeChanges = nonNegInt(profile.NationFreeChanges)
	profile.NationPrompts = math.min(nonNegInt(profile.NationPrompts), MAX_NATION_PROMPTS)
end

-- W3 step 2 Phase B Jobs (OpsService, lane O) ─────────────────────────────────────────────────────────────
-- profile.Ops, accessed as (profile :: any).Ops like Raid (no Types edit, no DataVersion bump). Default-filled and
-- sanitised on every load (idempotent). Limits from OpsConfig.Profile (loaded in a pcall like NationConfig above: a
-- broken config never blocks a load; the fallbacks are the same numbers).
--   Cd       { [siteId] = os.time() until }: string "<POI>.<Site>" keys, finite numbers only, expired dropped,
--            at most now + MaxCdAhead, at most MaxCdKeys keys (the latest-ending kept)
--   DayKey   whole number >= 0 (the UTC day Runs counts)
--   Runs     { [payRow] = whole number >= 0 } (string keys, at most MaxCdKeys)
--   Seen     bit flags 0 .. SeenMax
--   Total, BestBag  whole numbers >= 0
local opsCfgOk, opsCfg = pcall(function()
	return require(Shared.Configs.OpsConfig) :: any
end)
local OPS_PROFILE: any = if opsCfgOk and typeof(opsCfg) == "table" and typeof(opsCfg.Profile) == "table"
	then opsCfg.Profile
	else { MaxCdKeys = 32, MaxCdAhead = 86400, SeenMax = 1048576 }

local function ensureOpsFields(profile: any, nowUnix: number)
	local ops = profile.Ops
	if typeof(ops) ~= "table" then
		ops = {}
		profile.Ops = ops
	end
	local maxKeys = math.max(1, nonNegInt(OPS_PROFILE.MaxCdKeys))
	local cd: { [string]: number } = {}
	local kept: { { K: string, V: number } } = {}
	if typeof(ops.Cd) == "table" then
		local cap = nowUnix + nonNegInt(OPS_PROFILE.MaxCdAhead)
		for k, v in pairs(ops.Cd) do
			local n = tonumber(v)
			if typeof(k) == "string" and string.match(k, "^[%w_]+%.[%w_]+$") ~= nil and typeof(v) == "number"
				and n ~= nil and n == n and n > nowUnix and n < math.huge
			then
				table.insert(kept, { K = k, V = math.floor(math.min(n, cap)) })
			end
		end
	end
	table.sort(kept, function(a, b)
		if a.V ~= b.V then
			return a.V > b.V
		end
		return a.K < b.K
	end)
	for i, e in ipairs(kept) do
		if i > maxKeys then
			break
		end
		cd[e.K] = e.V
	end
	ops.Cd = cd
	ops.DayKey = nonNegInt(ops.DayKey)
	local runs: { [string]: number } = {}
	local nRuns = 0
	if typeof(ops.Runs) == "table" then
		local keys: { string } = {}
		for k in pairs(ops.Runs) do
			if typeof(k) == "string" and #k <= 32 then
				table.insert(keys, k)
			end
		end
		table.sort(keys)
		for _, k in ipairs(keys) do
			if nRuns >= maxKeys then
				break
			end
			runs[k] = nonNegInt(ops.Runs[k])
			nRuns += 1
		end
	end
	ops.Runs = runs
	ops.Seen = math.min(nonNegInt(ops.Seen), nonNegInt(OPS_PROFILE.SeenMax))
	ops.Total = nonNegInt(ops.Total)
	ops.BestBag = nonNegInt(ops.BestBag)
end

-- XP rebalance (spec_xp.md §3.3, §7) ─────────────────────────────────────────────────────────────────────────────
-- XPBalanceConfig (the file the owner edits to turn the backfill on) and ResearchConfig are loaded in a pcall, like
-- NationConfig and OpsConfig above: a broken config edit must never block a profile load. XPBalanceConfig must also
-- pass validXPBalanceConfig below, the ONE check for it: XPService takes its config from ProfileSchema.XPBalance(),
-- so the two modules always agree (both run X1, or both are OFF). OFF is the safe direction: new saves get no
-- BuildXP block, nothing is snapshotted, purchases pay no XP, and an existing block is kept exactly as it is (an
-- unpaid Owed is never zeroed). The first load on a server whose configs work then snapshots a save that has no block
-- yet, so what such a save bought in the broken window is counted by that snapshot and paid once (at Prestige > 0 the
-- snapshot counts base levels only). A save that already has a block, and a Prestige > 0 save's vehicles / weapons /
-- research, are not paid for purchases made while broken: an accepted loss (XP-X1-10), never a double pay.
local function finiteNumber(v: any): boolean
	return typeof(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- v4: the fixed ceiling a stored BuildXP.Owed is clamped to at load. A constant, never derived from the configs, so a
-- retune (A / P / Cap) can never lower a stored snapshot for good; far above any real snapshot (the pool is 56,073).
-- XPService.grantBackfill caps the payment at the pool when it pays.
local BUILDXP_OWED_MAX = 10000000

-- Every field ProfileSchema and XPService use, plus smoke tests of the three functions they call. Returns nil when
-- the config is usable, else what is wrong (for the warning).
local function validXPBalanceConfig(cfg: any): string?
	if typeof(cfg) ~= "table" then
		return "did not load"
	end
	local b, f = cfg.Build, cfg.Backfill
	if typeof(cfg.Enabled) ~= "boolean" then
		return "Enabled"
	elseif typeof(b) ~= "table" or typeof(b.Enabled) ~= "boolean" or not finiteNumber(b.A) or not finiteNumber(b.P)
		or not finiteNumber(b.Cap) or typeof(b.ReasonPrefixes) ~= "table" or typeof(b.Reason) ~= "string"
		or not finiteNumber(b.RebirthRebuildMult)
	then
		return "Build"
	elseif typeof(f) ~= "table" or typeof(f.Enabled) ~= "boolean" or typeof(f.Reason) ~= "string" or typeof(f.Toast) ~= "string" then
		return "Backfill"
	elseif typeof(cfg.NoBattlePassMirror) ~= "table" then
		return "NoBattlePassMirror"
	elseif typeof(cfg.BuildXPFormula) ~= "function" or typeof(cfg.BuildXP) ~= "function" or typeof(cfg.IsBuildReason) ~= "function" then
		return "functions"
	end
	for _, prefix in ipairs(b.ReasonPrefixes) do
		if typeof(prefix) ~= "string" or prefix == "" then
			return "Build.ReasonPrefixes"
		end
	end
	local okF, formulaXP = pcall(cfg.BuildXPFormula, 5000)
	local okB, buildXP = pcall(cfg.BuildXP, 5000)
	local okU, upgradePays = pcall(cfg.IsBuildReason, "upgrade_x")
	local okR, recruitPays = pcall(cfg.IsBuildReason, "recruit_soldiers")
	local okT, toast = pcall(string.format, f.Toast, 5)
	if not (okF and finiteNumber(formulaXP) and formulaXP >= 0 and okB and finiteNumber(buildXP) and buildXP >= 0) then
		return "smoke test: BuildXPFormula / BuildXP(5000)"
	elseif not (okU and upgradePays == true and okR and recruitPays == false) then
		return "smoke test: IsBuildReason (upgrade_ pays, recruit_soldiers does not)"
	elseif not (okT and typeof(toast) == "string") then
		return "smoke test: Backfill.Toast"
	end
	return nil
end

local xpCfgOk, xpCfg = pcall(function()
	return require(Shared.Configs.XPBalanceConfig) :: any
end)
local xpCfgProblem: string? = if xpCfgOk then validXPBalanceConfig(xpCfg) else "did not load: " .. tostring(xpCfg)
local XPBalanceConfig: any = if xpCfgProblem == nil then xpCfg else nil
local researchCfgOk, researchCfg = pcall(function()
	return require(Shared.Configs.ResearchConfig) :: any
end)
local ResearchConfig: any = if researchCfgOk and typeof(researchCfg) == "table" and typeof(researchCfg.Upgrades) == "table"
		and typeof(researchCfg.LevelOf) == "function"
	then researchCfg
	else nil

--[[ H2: the XPBalanceConfig that passed validXPBalanceConfig, or nil and what is wrong with it. XPService takes its
	config ONLY from here (it never requires XPBalanceConfig itself), so X1 runs in both modules or in neither. ]]
function ProfileSchema.XPBalance(): (any?, string?)
	return XPBalanceConfig, xpCfgProblem
end

-- Purchase XP (and so the snapshot) is on: both switches, and the config loaded.
local function buildXPOn(): boolean
	return XPBalanceConfig ~= nil and XPBalanceConfig.Enabled == true and XPBalanceConfig.Build.Enabled == true
end

-- Build XP (the bare formula, whatever the switches say) of every cash structure / business level (levels clamped
-- to #Costs), and, when countItems, of every cash vehicle and weapon the save owns and every research level.
-- `own == nil` sums the whole live catalogue instead (the G5 cap: 56,073 base; rebirth-gated vehicles and weapons
-- are not in it). Callers check that both configs loaded and call it in a pcall.
local function buildXPOf(own: any?, countItems: boolean): number
	local formula = XPBalanceConfig.BuildXPFormula
	local sum = 0
	local upgrades = if own ~= nil then own.BaseUpgrades else nil
	for id, def in pairs(BaseConfig.Structures) do
		if def.Currency ~= "Gold" then
			local costs = def.Costs
			local lv = #costs
			if own ~= nil then
				lv = if typeof(upgrades) == "table" then math.clamp(nonNegInt(upgrades[id]), 0, #costs) else 0
			end
			for l = 1, lv do
				sum += formula(costs[l])
			end
		end
	end
	if not countItems then
		return sum
	end
	for id, def in pairs(VehicleConfig.Vehicles :: any) do
		local cost = tonumber(def.CostCash) or 0
		if cost > 0 then
			if own == nil then
				if (tonumber(def.RequiresPrestige) or 0) <= 0 and def.RequiresRebirthFlag == nil then
					sum += formula(cost)
				end
			elseif typeof(own.Vehicles) == "table" and own.Vehicles[id] == true then
				sum += formula(cost)
			end
		end
	end
	for id, def in pairs(WeaponConfig.Weapons :: any) do
		local cost = tonumber(def.CostCash) or 0
		if cost > 0 then
			if own == nil then
				if (tonumber(def.RequiresPrestige) or 0) <= 0 then
					sum += formula(cost)
				end
			elseif typeof(own.Weapons) == "table" and own.Weapons[id] == true then
				sum += formula(cost)
			end
		end
	end
	for id, def in pairs(ResearchConfig.Upgrades) do
		local lv = if own == nil then #def.Costs else math.min(ResearchConfig.LevelOf(own.Research, id), #def.Costs)
		for l = 1, lv do
			sum += formula(def.Costs[l])
		end
	end
	return sum
end

--[[ G5: the backfill cap, the build XP of the whole live catalogue (56,073 base at this build). Computed from the
	configs with the bare formula, so it holds even while purchase XP is switched off. nil when XPBalanceConfig or
	ResearchConfig did not load (XPService.Push then keeps the Owed and pays nothing). ]]
function ProfileSchema.BuildXPPool(): number?
	if XPBalanceConfig == nil or ResearchConfig == nil then
		return nil
	end
	local ok, pool = pcall(buildXPOf, nil, true)
	if ok and typeof(pool) == "number" and pool == pool and pool >= 0 and pool < math.huge then
		return pool
	end
	return nil
end

-- v4: part of the one config check. A formula that pays nothing for the whole catalogue (Cap 0, A 0 ...) is a broken
-- config, not a retune: X1 is OFF in both modules (XPBalance() returns nil) and every stored Owed is kept. (No pool at
-- all, ResearchConfig broken: purchase XP runs, nothing is snapshotted and the backfill waits.)
if XPBalanceConfig ~= nil then
	local pool = ProfileSchema.BuildXPPool()
	if pool ~= nil and pool <= 0 then
		xpCfgProblem = "BuildXPPool() is 0 (the formula pays nothing: Build.A / P / Cap)"
		XPBalanceConfig = nil
	end
end

--[[ One-time snapshot (lead decision XP-L1: snapshot while the backfill is OFF). A save with no BuildXP block
	predates the rebalance: store, once, the build XP of what it owns in BuildXP.Owed, capped at the pool, and give it
	the block, whether or not the backfill switch is on. The block is what lets OnSpend pay its later purchases live,
	so an existing player earns purchase XP from ship day; the snapshot never grows, and the backfill switch only
	decides when XPService.Push pays it (once, quietly, one toast). Prestige > 0: base levels only (vehicles, weapons
	and research survive a rebirth, so they were bought in an earlier life).
	H1: every block is stamped with the life it belongs to, AtPrestige = the save's Prestige when it was written.
	XPService pays Owed only while the save is still in that life; after a rebirth (on any server, new or old) the
	snapshot is dropped unpaid, as it would have been had the switch shipped ON (the grant is reset by the rebirth).
	Runs inside Migrate, before DataService stores the profile, so no purchase can land between the snapshot and the
	block. Idempotent: a save that has the block is only sanitised (Owed a whole number up to BUILDXP_OWED_MAX; never
	re-capped from the current configs, so a retune cannot lower it for good). With purchase XP off (or its config
	broken) an old save gets no block and is snapshotted on its first load with it on. Never throws (a profile load
	must not fail here). ]]
local function ensureBuildXPFields(profile: any)
	local bx = profile.BuildXP
	if typeof(bx) == "table" then
		bx.Owed = math.min(nonNegInt(bx.Owed), BUILDXP_OWED_MAX) -- sanitised only: never re-capped by the current configs
		return
	end
	if bx ~= nil then
		profile.BuildXP = { Owed = 0, AtPrestige = nonNegInt(profile.Prestige) } -- junk (never written by this code): repair, pay nothing
		return
	end
	if not buildXPOn() then
		return -- decided on the first load with purchase XP on
	end
	local pool = ProfileSchema.BuildXPPool()
	local ok, owed = pcall(buildXPOf, profile, nonNegInt(profile.Prestige) == 0)
	if pool == nil or not ok or typeof(owed) ~= "number" or owed ~= owed then
		return -- could not count it: no block yet, so its buys pay nothing live and a later load snapshots them, once
	end
	profile.BuildXP = { Owed = math.min(nonNegInt(owed), pool), AtPrestige = nonNegInt(profile.Prestige) }
end

-- Code Bot v102: redeem codes (idempotent; no DataVersion bump, like ensureFeatureFields).
--   RedeemedCodes  { [CODE] = os.time() of the redeem | true (pre-v102 saves) }: string keys up to 32 chars only,
--                  junk values dropped; a code stays redeemed forever (once per player, across rebirths)
--   CashBoost      { Until = os.time() end (0 = none), Mult >= 1 }: the timed Cash boost codes grant
local function ensureCodesFields(profile: any)
	local rc = profile.RedeemedCodes
	local clean: { [string]: any } = {}
	if typeof(rc) == "table" then
		for k, v in pairs(rc) do
			if typeof(k) == "string" and #k > 0 and #k <= 32 then
				if v == true then
					clean[k] = true
				elseif typeof(v) == "number" and v == v and v > 0 and v < MAX_COUNTER then
					clean[k] = math.floor(v)
				end
			end
		end
	end
	profile.RedeemedCodes = clean
	local b = profile.CashBoost
	local untilUnix = if typeof(b) == "table" then nonNegInt(b.Until) else 0
	local mult = if typeof(b) == "table" then tonumber(b.Mult) else nil
	if mult == nil or mult ~= mult or mult < 1 or mult > 10 then
		mult = 1
	end
	profile.CashBoost = { Until = untilUnix, Mult = mult }
end

function ProfileSchema.CreateDefault(): PlayerProfile
	local now = os.time()
	return {
		DataVersion = Constants.CURRENT_DATA_VERSION,
		Cash = EconomyConfig.StartingCash,
		PendingCash = 0,
		Gold = EconomyConfig.StartingGold,
		Level = 1,
		XP = 0,
		-- XP rebalance: a new save owns nothing, so its snapshot is 0 (life 0). nil while purchase XP is off or its
		-- config is broken: the save is then snapshotted on its first load with purchase XP on, like an old save
		BuildXP = if buildXPOn() then { Owed = 0, AtPrestige = 0 } else nil,
		Prestige = 0,
		RebirthUnlocks = {},
		Soldiers = SoldierConfig.StartingSoldiers,
		NationColorId = nil,
		RedeemedCodes = {}, -- Code Bot v102: CODE -> os.time() of the redeem (older saves: true); see ensureCodesFields
		CashBoost = { Until = 0, Mult = 1 }, -- Code Bot v102: timed Cash boost from codes (EconomyService.CashBoostMult)
		LastSpinnerClaimUnix = 0,
		Vehicles = {
			[VehicleConfig.StarterVehicle] = true,
		},
		Weapons = {
			[WeaponConfig.DefaultWeapon] = true,
		},
		EquippedWeapon = WeaponConfig.DefaultWeapon,
		Territories = {},
		BaseUpgrades = emptyUpgrades(),
		BasePlotId = nil,
		TutorialStep = 0,
		TutorialComplete = false,
		DailyLogin = {
			LastClaimDay = 0,
			Streak = 0,
			LastClaimUnix = 0,
		},
		DailyMissions = emptyDailyMissions(),
		Settings = {
			MusicVolume = 0.7,
			SFXVolume = 0.8,
			ShowDamageNumbers = true,
			AutoSprint = true,
		},
		Stats = {
			TotalCashEarned = 0,
			TotalGoldEarned = 0,
			UpgradesPurchased = 0,
			VehiclesSpawned = 0,
			MissionsCompleted = 0,
			TerritoriesCaptured = 0,
			Kills = 0,
			Deaths = 0,
			PlayTimeSeconds = 0,
		},
		Achievements = {},
		BattlePass = {
			SeasonId = SeasonConfig.CurrentSeasonId,
			XP = 0,
			Level = 0,
			Premium = false,
			ClaimedFree = {},
			ClaimedPremium = {},
		},
		ClanId = nil,
		FirstJoinUnix = now,
		LastJoinUnix = now,
		ProcessedReceipts = {},
		Entitlements = {},
		OutpostIncomeStacks = 0,
		StarterBundleOffered = false,
		AutoCollectOffered = false,
		DoubleCashOffered = false,
		VIPOffered = false,
		SpeedBoostOffered = false,
		CashMegaOffered = false,
		-- v69: Research Lab upgrades (UpgradeId → level) and raid / missile-strike timers (os.time seconds)
		Research = {},
		Raid = { ShieldUntil = 0, StrikeCooldownUntil = 0, DefensesDownUntil = 0 },
		-- W3 step 2 Phase B Jobs: see ensureOpsFields (Migrate fills the same defaults into older saves)
		Ops = { Cd = {}, DayKey = 0, Runs = {}, Seen = 0, Total = 0, BestBag = 0 },
		-- v71 money (M2): see ensureMoneyFields (Migrate fills the same defaults into older saves)
		Nukes = 0,
		TacticalNukes = 0,
		NukeInFlight = nil,
		NukeGiftGranted = false,
		NukeStats = defaultNukeStats(),
		Silo = { ProgressSeconds = 0 },
		PremiumVehicleCamo = {},
		PremiumTrials = {},
		Rebirth = { ZonesSeen = {}, LastRebirthUnix = 0 },
		Offers = {},
		Monetization = defaultMonetization(),
		AnnouncePurchases = true,
		VipSupplyAt = 0,
		-- Owner's 11 features: see ensureFeatureFields (Migrate fills the same keys into older saves)
		KeepBaseRebirths = 0,
		TutorialOrderVersion = TUTORIAL_ORDER_VERSION,
		NoviceShieldDone = false,
		StarterOutpostTaken = false,
		-- Nations: see ensureNationFields (Migrate fills the same keys into older saves). NationId nil = never picked.
		NationId = nil,
		NationSetAt = 0,
		NationFreeUntil = 0,
		NationFreeChanges = 0,
		NationPrompts = 0,
	}
end

--[[
	Migrate older profiles to CURRENT_DATA_VERSION.
	Add new migration steps as DataVersion increments.
]]
function ProfileSchema.Migrate(data: any): PlayerProfile
	if typeof(data) ~= "table" then
		return ProfileSchema.CreateDefault()
	end

	local profile = data :: PlayerProfile
	local version = tonumber(profile.DataVersion) or 0
	-- read before the v0 default fill below (see ensureFeatureFields)
	local rawTutorialOrder = (data :: any).TutorialOrderVersion
	local rawShieldDone = (data :: any).NoviceShieldDone
	local rawBuildXP = (data :: any).BuildXP -- XP rebalance: the v0 default fill must not mark an old save as new

	-- v0 / missing → fill defaults then set version
	if version < 1 then
		local defaults = ProfileSchema.CreateDefault()
		for key, value in pairs(defaults) do
			if profile[key] == nil then
				(profile :: any)[key] = value
			end
		end
		;(profile :: any).BuildXP = rawBuildXP
		-- Ensure nested tables
		if typeof(profile.BaseUpgrades) ~= "table" then
			profile.BaseUpgrades = emptyUpgrades()
		else
			for id in pairs(BaseConfig.Structures) do
				if profile.BaseUpgrades[id] == nil then
					profile.BaseUpgrades[id] = 0
				end
			end
		end
		if typeof(profile.Vehicles) ~= "table" then
			profile.Vehicles = { [VehicleConfig.StarterVehicle] = true }
		elseif not profile.Vehicles[VehicleConfig.StarterVehicle] then
			profile.Vehicles[VehicleConfig.StarterVehicle] = true
		end
		if typeof(profile.Weapons) ~= "table" then
			profile.Weapons = { [WeaponConfig.DefaultWeapon] = true }
		elseif not profile.Weapons[WeaponConfig.DefaultWeapon] then
			profile.Weapons[WeaponConfig.DefaultWeapon] = true
		end
		profile.DataVersion = 1
		version = 1
	end

	-- v1 → v2: DailyMissions progress table
	if version < 2 then
		if typeof((profile :: any).DailyMissions) ~= "table" then
			(profile :: any).DailyMissions = emptyDailyMissions()
		else
			local dm = (profile :: any).DailyMissions
			if typeof(dm.Progress) ~= "table" then
				dm.Progress = {}
			end
			if typeof(dm.Claimed) ~= "table" then
				dm.Claimed = {}
			end
			if typeof(dm.ActiveTimed) ~= "table" then
				dm.ActiveTimed = {}
			end
			if typeof(dm.DayKey) ~= "number" then
				dm.DayKey = 0
			end
		end
		if typeof(profile.Achievements) ~= "table" then
			profile.Achievements = {}
		end
		if typeof(profile.Territories) ~= "table" then
			profile.Territories = {}
		end
		profile.DataVersion = 2
		version = 2
	end


	-- v2 → v3: ensure clan / season / battle pass / soldier / war-adjacent fields for older saves
	if version < 3 then
		if typeof(profile.Prestige) ~= "number" then
			profile.Prestige = 0
		end
		if typeof(profile.Soldiers) ~= "number" then
			profile.Soldiers = SoldierConfig.StartingSoldiers or 0
		end
		if profile.ClanId ~= nil and typeof(profile.ClanId) ~= "string" then
			profile.ClanId = nil
		end
		if typeof(profile.BattlePass) ~= "table" then
			profile.BattlePass = {
				SeasonId = SeasonConfig.CurrentSeasonId,
				XP = 0,
				Level = 0,
				Premium = false,
				ClaimedFree = {},
				ClaimedPremium = {},
			}
		else
			local bp = profile.BattlePass
			if typeof(bp.SeasonId) ~= "string" then
				bp.SeasonId = SeasonConfig.CurrentSeasonId
			end
			if typeof(bp.XP) ~= "number" then
				bp.XP = 0
			end
			if typeof(bp.Level) ~= "number" then
				bp.Level = 0
			end
			if typeof(bp.Premium) ~= "boolean" then
				bp.Premium = false
			end
			if typeof(bp.ClaimedFree) ~= "table" then
				bp.ClaimedFree = {}
			end
			if typeof(bp.ClaimedPremium) ~= "table" then
				bp.ClaimedPremium = {}
			end
		end
		if typeof(profile.Stats) == "table" then
			if typeof(profile.Stats.TerritoriesCaptured) ~= "number" then
				profile.Stats.TerritoriesCaptured = 0
			end
			if typeof(profile.Stats.Kills) ~= "number" then
				profile.Stats.Kills = 0
			end
			if typeof(profile.Stats.Deaths) ~= "number" then
				profile.Stats.Deaths = 0
			end
		end
		if typeof(profile.Territories) ~= "table" then
			profile.Territories = {}
		end
		if typeof(profile.Achievements) ~= "table" then
			profile.Achievements = {}
		end
		profile.DataVersion = 3
		version = 3
	end

	-- v3 → v4: nation color + redeemed codes (MT-inspired systems)
	if version < 4 then
		if profile.NationColorId ~= nil and typeof(profile.NationColorId) ~= "string" then
			profile.NationColorId = nil
		end
		if typeof(profile.RedeemedCodes) ~= "table" then
			profile.RedeemedCodes = {}
		end
		profile.DataVersion = 4
		version = 4
	end

	-- v4 → v5: free supply spinner cooldown stamp
	if version < 5 then
		if typeof((profile :: any).LastSpinnerClaimUnix) ~= "number" then
			(profile :: any).LastSpinnerClaimUnix = 0
		end
		profile.DataVersion = 5
		version = 5
	end


	-- v5 → v6: rebirth unlock flags (prestige track)
	if version < 6 then
		if typeof((profile :: any).RebirthUnlocks) ~= "table" then
			(profile :: any).RebirthUnlocks = {}
		end
		profile.DataVersion = 6
		version = 6
	end


	-- v6 → v7: Money Collector pending cash + entitlements flags
	if version < 7 then
		if typeof((profile :: any).PendingCash) ~= "number" then
			(profile :: any).PendingCash = 0
		end
		if typeof((profile :: any).Entitlements) ~= "table" then
			(profile :: any).Entitlements = {}
		end
		profile.DataVersion = 7
		version = 7
	end


	-- v7 → v8: permanent outpost income buff stacks
	if version < 8 then
		if typeof((profile :: any).OutpostIncomeStacks) ~= "number" then
			(profile :: any).OutpostIncomeStacks = 0
		end
		profile.DataVersion = 8
		version = 8
	end

	if typeof((profile :: any).ProcessedReceipts) ~= "table" then
		(profile :: any).ProcessedReceipts = {}
	end
	do
		local cashN = tonumber((profile :: any).Cash)
		profile.Cash = if typeof(cashN) == "number" then math.floor(cashN) else EconomyConfig.StartingCash
		local goldN = tonumber((profile :: any).Gold)
		profile.Gold = if typeof(goldN) == "number" then math.floor(goldN) else EconomyConfig.StartingGold
	end
	if typeof((profile :: any).PendingCash) ~= "number" then
		local pendN = tonumber((profile :: any).PendingCash)
		;(profile :: any).PendingCash = if typeof(pendN) == "number" then math.floor(pendN) else 0
	end
	if typeof((profile :: any).Entitlements) ~= "table" then
		(profile :: any).Entitlements = {}
	end
	if typeof((profile :: any).OutpostIncomeStacks) ~= "number" then
		(profile :: any).OutpostIncomeStacks = 0
	end
	if (profile :: any).StarterBundleOffered == nil then
		(profile :: any).StarterBundleOffered = false
	end
	if (profile :: any).AutoCollectOffered == nil then
		(profile :: any).AutoCollectOffered = false
	end
	if (profile :: any).DoubleCashOffered == nil then
		(profile :: any).DoubleCashOffered = false
	end
	if (profile :: any).VIPOffered == nil then
		(profile :: any).VIPOffered = false
	end
	if (profile :: any).SpeedBoostOffered == nil then
		(profile :: any).SpeedBoostOffered = false
	end
	if (profile :: any).CashMegaOffered == nil then
		(profile :: any).CashMegaOffered = false
	end
	-- v69: Research levels + raid / strike timers (idempotent; no DataVersion bump needed for new tables)
	if typeof((profile :: any).Research) ~= "table" then
		(profile :: any).Research = {}
	end
	do
		local raid = (profile :: any).Raid
		if typeof(raid) ~= "table" then
			raid = {}
			;(profile :: any).Raid = raid
		end
		-- claude-bud JOB 38: the SEND cooldown (sender) and the army protection (victim base), os.time()
		for _, k in ipairs({ "ShieldUntil", "StrikeCooldownUntil", "DefensesDownUntil", "ArmySendCooldownUntil", "ArmyProtectUntil" }) do
			if typeof(raid[k]) ~= "number" then
				raid[k] = 0
			end
		end
	end
	-- v71 money (M2): nuke / premium vehicle / rebirth / offer / accounting blocks (idempotent; no version bump)
	ensureMoneyFields(profile)
	-- Owner's 11 features: keep-base tokens, tutorial order version, novice shield, Home Outpost (idempotent)
	ensureFeatureFields(profile, rawTutorialOrder, rawShieldDone)
	-- Nations: chosen country + change timers (idempotent; NationColorId untouched)
	ensureNationFields(profile)
	-- W3 step 2 Phase B Jobs: cooldowns / today's runs / seen tips (idempotent; no version bump)
	ensureOpsFields(profile, os.time())
	-- XP rebalance: one-time build-XP backfill snapshot for saves that predate it (idempotent; no version bump)
	ensureBuildXPFields(profile)
	-- Code Bot v102: redeemed codes + the timed Cash boost (idempotent; no version bump)
	ensureCodesFields(profile)

	-- v64: always ensure nested tables (corrupt DS / partial migrate must not nil-index on buy)
	if typeof(profile.BaseUpgrades) ~= "table" then
		profile.BaseUpgrades = emptyUpgrades()
	else
		for id in pairs(BaseConfig.Structures) do
			if profile.BaseUpgrades[id] == nil then
				profile.BaseUpgrades[id] = 0
			end
		end
	end
	if typeof(profile.Stats) ~= "table" then
		profile.Stats = {
			TotalCashEarned = 0,
			TotalGoldEarned = 0,
			UpgradesPurchased = 0,
			VehiclesSpawned = 0,
			MissionsCompleted = 0,
			TerritoriesCaptured = 0,
			Kills = 0,
			Deaths = 0,
			PlayTimeSeconds = 0,
		}
	else
		if typeof(profile.Stats.UpgradesPurchased) ~= "number" then
			profile.Stats.UpgradesPurchased = math.floor(tonumber(profile.Stats.UpgradesPurchased) or 0)
		end
	end

	profile.DataVersion = Constants.CURRENT_DATA_VERSION
	return profile
end

function ProfileSchema.DeepCopy(profile: PlayerProfile): PlayerProfile
	-- Simple recursive copy sufficient for our schema
	local function copy(v: any): any
		if typeof(v) ~= "table" then
			return v
		end
		local t = {}
		for k, val in pairs(v) do
			t[k] = copy(val)
		end
		return t
	end
	return copy(profile) :: PlayerProfile
end

return ProfileSchema
