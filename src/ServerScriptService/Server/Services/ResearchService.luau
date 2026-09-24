--!strict
--[[
	v69 Research Lab upgrades (weapons, soldiers, vehicles, defenses) — server-authoritative.
	Tree, prices and gating live in Shared/Configs/ResearchConfig. Levels persist in profile.Research
	({ [upgradeId] = level }) and are PERMANENT (PrestigeService never resets them).

	Remotes:
	  RequestResearch     (client → server) FireServer("Buy", upgradeId) | FireServer("Sync")
	  ResearchStateUpdate (server → client) ResearchConfig.ResearchStatePayload

	Contract used by other services (safe to call before Init / without a profile / per shot):
	  ResearchService.GetBonus(player, statId) -> multiplier >= 1 (1 = no bonus)
	    statId ∈ WeaponDamage, WeaponFireRate, WeaponMagazine, WeaponReload, SoldierHealth, SoldierDamage,
	             VehicleSpeed, VehicleArmor, TurretDamage
	  ResearchService.GetAdd(player, statId) -> additive bonus >= 0 (SquadSize)
	Hooks: CombatService (Weapon*), SquadOrdersService (Soldier*, SquadSize), VehicleService (Vehicle*),
	GateDefenseService (TurretDamage).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ResearchConfig = require(Shared.Configs.ResearchConfig)

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)

type UpgradeDef = ResearchConfig.UpgradeDef
type ResearchLock = ResearchConfig.ResearchLock
type ResearchStatePayload = ResearchConfig.ResearchStatePayload

local ResearchService = {}

local DataService: any = nil
local EconomyService: any = nil
local NotificationService: any = nil
local RateLimitService: any = nil
local RemoteSetup: any = nil
local BaseService: any = nil
local CombatService: any = nil
local SquadOrdersService: any = nil
local VehicleService: any = nil
local AnalyticsService: any = nil

-- Structures whose level changes what the panel shows (lab gate + track requirements).
local WATCHED_STRUCTURES: { [string]: boolean } = {
	[ResearchConfig.StructureId] = true,
	Barracks = true,
	VehicleDepot = true,
	DefensiveWalls = true,
}

-- Lazy DataService: GetBonus may run (CombatService OnProfileLoaded / first shot) before ResearchService.Init.
local function getDataService(): any
	if DataService ~= nil then
		return DataService
	end
	local parent = script.Parent
	local mod = if parent then parent:FindFirstChild("DataService") else nil
	if mod == nil then
		return nil
	end
	local ok, ds = pcall(require, mod :: any)
	if ok and ds ~= nil then
		DataService = ds
		return ds
	end
	return nil
end

local function getProfile(player: Player): any
	local ds = getDataService()
	if ds == nil or ds.GetProfile == nil then
		return nil
	end
	local ok, profile = pcall(ds.GetProfile, player)
	if ok and typeof(profile) == "table" then
		return profile
	end
	return nil
end

local function researchOf(player: Player): any
	local profile = getProfile(player)
	if profile == nil then
		return nil
	end
	return profile.Research
end

local function structureLevel(profile: any, structureId: string): number
	local ups = profile.BaseUpgrades
	if typeof(ups) ~= "table" then
		return 0
	end
	local v = tonumber(ups[structureId])
	if v == nil or v ~= v then
		return 0
	end
	return math.floor(v)
end

--[[ Lock for a whole track (its building is missing), or nil when the track is open. ]]
local function trackLock(profile: any, trackId: string): ResearchLock?
	local track = ResearchConfig.Tracks[trackId]
	if track == nil then
		return { Code = "NeedStructure", Text = "Unavailable" }
	end
	local req = track.Requires
	if req == nil then
		return nil
	end
	if structureLevel(profile, req.StructureId) >= req.Level then
		return nil
	end
	return { Code = "NeedStructure", Text = req.Text }
end

local function roman(level: number): string
	return ResearchConfig.Roman[level] or tostring(level)
end

local function notify(player: Player, message: string, kind: string, duration: number?)
	if NotificationService and NotificationService.Notify then
		pcall(NotificationService.Notify, player, message, kind, duration)
	end
end

-- ── Public API ──────────────────────────────────────────────────────────────────────────────────────────

--[[ Multiplier >= 1 for a Kind "Mult" stat (1 = none). Never errors; cheap (called per shot). ]]
function ResearchService.GetBonus(player: Player, statId: string): number
	local m = ResearchConfig.MultFor(researchOf(player), statId)
	if typeof(m) == "number" and m == m and m >= 1 then
		return m
	end
	return 1
end

--[[ Additive bonus >= 0 for a Kind "Add" stat (SquadSize). ]]
function ResearchService.GetAdd(player: Player, statId: string): number
	local a = ResearchConfig.AddFor(researchOf(player), statId)
	if typeof(a) == "number" and a == a and a >= 0 then
		return a
	end
	return 0
end

--[[ Owned level of an upgrade (0 when absent). ]]
function ResearchService.GetLevel(player: Player, upgradeId: string): number
	return ResearchConfig.LevelOf(researchOf(player), upgradeId)
end

--[[ State for the panel (nil until the real save has loaded). Pure: fires nothing. ]]
function ResearchService.BuildState(player: Player): ResearchStatePayload?
	local profile = getProfile(player)
	if profile == nil then
		return nil
	end
	local research = profile.Research
	local labLevel = structureLevel(profile, ResearchConfig.StructureId)
	local levels: { [string]: number } = {}
	local costs: { [string]: number } = {}
	local locks: { [string]: ResearchLock } = {}
	local tracks: { [string]: ResearchLock } = {}
	for _, trackId in ipairs(ResearchConfig.TrackOrder) do
		local lock = trackLock(profile, trackId)
		if lock then
			tracks[trackId] = lock
		end
	end
	for id, def in pairs(ResearchConfig.Upgrades) do
		local lvl = ResearchConfig.LevelOf(research, id)
		levels[id] = lvl
		if lvl < def.MaxLevel then
			local c = def.Costs[lvl + 1]
			if typeof(c) == "number" and c > 0 then
				costs[id] = c
			end
		end
		local lock: ResearchLock? = nil
		if not def.Enabled then
			lock = { Code = "Disabled", Text = "Coming soon" }
		elseif lvl >= def.MaxLevel then
			lock = { Code = "Maxed", Text = "MAXED" }
		else
			local tl = trackLock(profile, def.Track)
			if tl then
				lock = { Code = "NeedStructure", Text = tl.Text }
			else
				local needLab = ResearchConfig.LabLevelFor(def, lvl + 1)
				if labLevel < needLab then
					lock = { Code = "NeedLab", Text = string.format("Needs Research Lab L%d", needLab) }
				end
			end
		end
		if lock then
			locks[id] = lock
		end
	end
	return {
		LabLevel = labLevel,
		Levels = levels,
		Costs = costs,
		Locks = locks,
		Tracks = tracks,
	}
end

--[[ Send the panel state to the player's client (no-op until the save has loaded). ]]
function ResearchService.Push(player: Player)
	if RemoteSetup == nil then
		return
	end
	local ok, err = pcall(function(): any
		local payload = ResearchService.BuildState(player)
		if payload == nil or player.Parent == nil then
			return nil
		end
		local remote = RemoteSetup.Get(Constants.RemoteNames.ResearchStateUpdate) :: RemoteEvent
		remote:FireClient(player, payload)
		return nil
	end)
	if not ok then
		warn("[ResearchService] Push failed:", err)
	end
end

--[[ Buy the next level of an upgrade. Server-authoritative: id validated, price from ResearchConfig,
	Lab + track gates re-checked, Cash via EconomyService.SpendCash. Returns (true) or (false, error). ]]
function ResearchService.Purchase(player: Player, upgradeId: any): (boolean, string?)
	-- 1-3: id / def / enabled
	if not RemoteGuard.IsIdString(upgradeId, 48) then
		return false, "InvalidUpgrade"
	end
	local id = upgradeId :: string
	local def = ResearchConfig.Upgrades[id]
	if def == nil or def.Id ~= id then
		return false, "UnknownUpgrade"
	end
	if not def.Enabled then
		return false, "Disabled"
	end
	-- 4: profile (nil until the real save has loaded)
	local profile = getProfile(player)
	if profile == nil then
		return false, "NoProfile"
	end
	if typeof(profile.Research) ~= "table" then
		profile.Research = {}
	end
	local research = profile.Research
	-- 5: maxed
	local cur = ResearchConfig.LevelOf(research, id)
	if cur >= def.MaxLevel then
		return false, "Maxed"
	end
	local target = cur + 1
	-- 6: track building
	local track = ResearchConfig.Tracks[def.Track]
	if track == nil then
		return false, "BadConfig"
	end
	local req = track.Requires
	if req ~= nil and structureLevel(profile, req.StructureId) < req.Level then
		return false, "TrackLocked"
	end
	-- 7: Research Lab level
	if structureLevel(profile, ResearchConfig.StructureId) < ResearchConfig.LabLevelFor(def, target) then
		return false, "LabLevelTooLow"
	end
	-- 8: price (server config only) — nothing yields between the checks above and the write below
	local cost = def.Costs[target]
	if typeof(cost) ~= "number" or cost ~= cost or cost <= 0 or cost == math.huge then
		return false, "BadConfig"
	end
	cost = math.floor(cost)
	if EconomyService == nil or EconomyService.SpendCash == nil then
		return false, "SpendFailed"
	end
	local spent, spendErr = EconomyService.SpendCash(player, cost, "research_" .. id)
	if not spent then
		return false, spendErr or "SpendFailed"
	end
	-- 9: write
	research[id] = target
	local ds = getDataService()
	if ds and ds.MarkDirty then
		pcall(ds.MarkDirty, player)
	end
	-- 10: live side effects
	if def.Stat == "SoldierHealth" or def.Stat == "SquadSize" then
		if SquadOrdersService and SquadOrdersService.ApplyResearch then
			local ok, err = pcall(SquadOrdersService.ApplyResearch, player)
			if not ok then
				warn("[ResearchService] SquadOrdersService.ApplyResearch failed:", err)
			end
		end
	elseif def.Stat == "WeaponMagazine" then
		if CombatService and CombatService.PushState then
			local ok, err = pcall(CombatService.PushState, player)
			if not ok then
				warn("[ResearchService] CombatService.PushState failed:", err)
			end
		end
	elseif def.Stat == "VehicleSpeed" or def.Stat == "VehicleArmor" then
		-- a vehicle that is already deployed picks up the new level (VehicleService hook for this workflow)
		if VehicleService and VehicleService.OnResearchChanged then
			local ok, err = pcall(VehicleService.OnResearchChanged, player)
			if not ok then
				warn("[ResearchService] VehicleService.OnResearchChanged failed:", err)
			end
		end
	end
	-- 11-13: feedback, analytics, state
	notify(
		player,
		string.format(
			"RESEARCH COMPLETE · %s %s — %s",
			def.DisplayName,
			roman(target),
			ResearchConfig.FormatEffect(def, target)
		),
		"Success",
		4
	)
	if AnalyticsService and AnalyticsService.Log then
		pcall(AnalyticsService.Log, "RESEARCH_PURCHASED", player.UserId, { upgrade = id, level = target, cost = cost })
	end
	ResearchService.Push(player)
	return true, nil
end

--[[ Player-facing refusal text (nil = stay silent). ]]
local function refusalText(player: Player, upgradeId: any, err: string?): string?
	local def = if typeof(upgradeId) == "string" then ResearchConfig.Upgrades[upgradeId] else nil
	if err == "NoProfile" then
		return "Your save is still loading — try again in a moment"
	end
	if def == nil or err == nil or err == "InvalidUpgrade" or err == "UnknownUpgrade" then
		return nil
	end
	local target = math.min(ResearchService.GetLevel(player, def.Id) + 1, def.MaxLevel)
	local name = string.format("%s %s", def.DisplayName, roman(target))
	if err == "InsufficientCash" or err == "CannotAfford" then
		local cost = def.Costs[target]
		return string.format("Not enough Cash — %s costs %s", name, ResearchConfig.FormatCash(tonumber(cost) or 0))
	elseif err == "LabLevelTooLow" then
		return string.format(
			"%s needs Research Lab L%d — upgrade the lab at its console",
			name,
			ResearchConfig.LabLevelFor(def, target)
		)
	elseif err == "TrackLocked" then
		local track = ResearchConfig.Tracks[def.Track]
		local req = if track then track.Requires else nil
		return if req then req.Text else "That research track is locked"
	elseif err == "Maxed" then
		return string.format("%s is fully researched", def.DisplayName)
	elseif err == "Disabled" then
		return string.format("%s — coming soon", def.DisplayName)
	end
	return string.format("Research failed: %s", tostring(err))
end

-- Init-time sanity: an upgrade with a malformed definition is switched off (card shows SOON) instead of
-- selling a broken level.
local function sanityCheck()
	local statSet: { [string]: boolean } = {}
	for _, s in ipairs(ResearchConfig.StatIds) do
		statSet[s] = true
	end
	for id, def in pairs(ResearchConfig.Upgrades) do
		local problem: string? = nil
		if def.Id ~= id then
			problem = "Id mismatch"
		elseif typeof(def.Costs) ~= "table" or #def.Costs ~= def.MaxLevel then
			problem = "#Costs ~= MaxLevel"
		elseif not statSet[def.Stat] then
			problem = "unknown Stat " .. tostring(def.Stat)
		elseif ResearchConfig.Tracks[def.Track] == nil then
			problem = "unknown Track " .. tostring(def.Track)
		elseif def.Kind ~= "Mult" and def.Kind ~= "Add" then
			problem = "unknown Kind " .. tostring(def.Kind)
		else
			local prev = 0
			for i = 1, def.MaxLevel do
				local c = def.Costs[i]
				if typeof(c) ~= "number" or c ~= c or c <= prev then
					problem = "costs not strictly increasing"
					break
				end
				prev = c
			end
		end
		if problem and def.Enabled then
			warn(string.format("[ResearchService] disabling %s: %s", id, problem))
			def.Enabled = false
		end
	end
end

function ResearchService.Init(deps: { [string]: any })
	DataService = deps.DataService or DataService
	EconomyService = deps.EconomyService
	NotificationService = deps.NotificationService
	RateLimitService = deps.RateLimitService
	RemoteSetup = deps.RemoteSetup
	BaseService = deps.BaseService
	CombatService = deps.CombatService
	SquadOrdersService = deps.SquadOrdersService
	VehicleService = deps.VehicleService
	AnalyticsService = deps.AnalyticsService

	sanityCheck()

	local remote = RemoteSetup.Get(Constants.RemoteNames.RequestResearch) :: RemoteEvent
	remote.OnServerEvent:Connect(function(player: Player, action: any, upgradeId: any)
		if action == "Buy" then
			if RateLimitService and not RateLimitService.Allow(player, "research_buy", ResearchConfig.BuyRate, ResearchConfig.BuyBurst) then
				if NotificationService and NotificationService.NotifyThrottled then
					pcall(
						NotificationService.NotifyThrottled,
						player,
						"Slow down — too many research taps",
						"Info",
						1.5,
						2,
						"research_tap"
					)
				end
				return
			end
			local ok, err = ResearchService.Purchase(player, upgradeId)
			if not ok then
				local msg = refusalText(player, upgradeId, err)
				if msg then
					notify(player, msg, "Warn")
				end
				-- a stale client re-syncs (no push without a loaded profile)
				ResearchService.Push(player)
			end
		elseif action == "Sync" then
			if RateLimitService and not RateLimitService.Allow(player, "research_sync", ResearchConfig.SyncRate, ResearchConfig.SyncBurst) then
				return
			end
			ResearchService.Push(player)
		end
		-- anything else: ignored silently
	end)

	if DataService and DataService.OnProfileLoaded then
		DataService.OnProfileLoaded(function(player: Player, _profile: any)
			ResearchService.Push(player)
			-- Re-push after client controllers bind (missed ResearchStateUpdate race)
			task.delay(1.5, function()
				if player.Parent then
					ResearchService.Push(player)
				end
			end)
		end)
	end

	if BaseService and BaseService.GetUpgradeChangedEvent then
		local ok, ev = pcall(BaseService.GetUpgradeChangedEvent)
		if ok and ev then
			ev.Event:Connect(function(userId: any, _plotId: any, structureId: any, _level: any)
				if typeof(structureId) ~= "string" or not WATCHED_STRUCTURES[structureId] then
					return
				end
				if typeof(userId) ~= "number" then
					return
				end
				local player = Players:GetPlayerByUserId(userId)
				if player then
					ResearchService.Push(player)
				end
			end)
		end
	end

	local nUpgrades, nTracks = 0, 0
	for _ in pairs(ResearchConfig.Upgrades) do
		nUpgrades += 1
	end
	for _ in pairs(ResearchConfig.Tracks) do
		nTracks += 1
	end
	print(string.format("[WAR EMPIRE] ResearchService ready (%d upgrades, %d tracks)", nUpgrades, nTracks))
end

return ResearchService
