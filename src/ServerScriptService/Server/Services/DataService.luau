--!strict
--[[
	DataStore load/save with retries, autosave, PlayerRemoving, BindToClose,
	session lock, and versioned migrations. Never trusts client payloads.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Types = require(Shared.Types)
local DevConfig = require(Shared.Configs.DevConfig)
local AdminConfig = require(Shared.Configs.AdminConfig)

local ProfileSchema = require(script.Parent.Parent.Modules.ProfileSchema)
local SessionLock = require(script.Parent.Parent.Modules.SessionLock)

type PlayerProfile = Types.PlayerProfile

local DataService = {}

local profiles: { [number]: PlayerProfile } = {}
local dirty: { [number]: boolean } = {}
local loading: { [number]: boolean } = {}
local dataStore: DataStore? = nil

local AnalyticsService: any = nil
local onProfileLoadedCallbacks: { (Player, PlayerProfile) -> () } = {}

local function getDataStore(): DataStore?
	if dataStore then
		return dataStore
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Constants.DataStoreName)
	end)
	if ok then
		dataStore = result
		return dataStore
	end
	warn("[DataService] DataStore unavailable (enable Studio API services for persistence):", result)
	return nil
end

local function keyFor(userId: number): string
	return "player_" .. tostring(userId)
end

local function retryAsync(label: string, fn: () -> any): (boolean, any)
	local lastErr = nil
	for attempt = 1, Constants.DataStoreRetries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		warn(string.format("[DataService] %s attempt %d failed: %s", label, attempt, tostring(result)))
		task.wait(Constants.DataStoreRetryDelay * attempt)
	end
	return false, lastErr
end

function DataService.SetAnalytics(svc: any)
	AnalyticsService = svc
end

function DataService.OnProfileLoaded(cb: (Player, PlayerProfile) -> ())
	table.insert(onProfileLoadedCallbacks, cb)
	-- If profiles already loaded (init-order safety), fire immediately
	for _, player in ipairs(Players:GetPlayers()) do
		local profile = profiles[player.UserId]
		if profile then
			task.spawn(cb, player, profile)
		end
	end
end

local function fireProfileLoaded(player: Player, profile: PlayerProfile)
	for _, cb in ipairs(onProfileLoadedCallbacks) do
		task.spawn(cb, player, profile)
	end
end

function DataService.GetProfile(player: Player): PlayerProfile?
	return profiles[player.UserId]
end

function DataService.MarkDirty(player: Player)
	if profiles[player.UserId] then
		dirty[player.UserId] = true
	end
end

function DataService.WaitForProfile(player: Player, timeout: number?): PlayerProfile?
	local t = timeout or 15
	local start = os.clock()
	while os.clock() - start < t do
		local p = profiles[player.UserId]
		if p then
			return p
		end
		if not player.Parent then
			return nil
		end
		task.wait(0.1)
	end
	return profiles[player.UserId]
end

local function applyStudioDevFlags(profile: PlayerProfile)
	if not RunService:IsStudio() then
		return
	end
	if DevConfig.StudioBoostCash then
		profile.Cash = math.max(profile.Cash, DevConfig.StudioBoostCashAmount)
	end
	if DevConfig.SkipTutorial then
		profile.TutorialComplete = true
	end
	if DevConfig.UnlockAllVehicles then
		local VehicleConfig = require(Shared.Configs.VehicleConfig)
		for id in pairs(VehicleConfig.Vehicles) do
			profile.Vehicles[id] = true
		end
	end
	if DevConfig.UnlockAllWeapons then
		local WeaponConfig = require(Shared.Configs.WeaponConfig)
		for id in pairs(WeaponConfig.Weapons) do
			profile.Weapons[id] = true
		end
	end
end

-- v60/v59: AdminPlaytestCash — shaunie6 only; instant LoadProfile + merge floors.
local ADMIN_PLAYTEST_USER_ID = 470626172
local function applyAdminPlaytestCash(userId: number, profile: PlayerProfile): boolean
	if userId ~= ADMIN_PLAYTEST_USER_ID then
		return false
	end
	local target = math.floor(tonumber(AdminConfig.AdminPlaytestCash) or 50_000_000)
	local have = math.floor(tonumber(profile.Cash) or 0)
	if have < target then
		profile.Cash = target
		return true
	end
	return false
end

local function stampEconomyAttrs(player: Player, profile: PlayerProfile)
	local cash = math.floor(tonumber(profile.Cash) or 0)
	local gold = math.floor(tonumber(profile.Gold) or 0)
	local pending = math.floor(tonumber((profile :: any).PendingCash) or 0)
	pcall(function()
		player:SetAttribute("WE_Build", 64)
		player:SetAttribute("WE_Cash", cash)
		player:SetAttribute("WE_Gold", gold)
		player:SetAttribute("WE_PendingCash", pending)
	end)
	-- v60: leaderstats always — HUD reads this even if remotes dead
	pcall(function()
		local folder = player:FindFirstChild("leaderstats")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "leaderstats"
			folder.Parent = player
		end
		local cashVal = folder:FindFirstChild("Cash")
		if not cashVal then
			cashVal = Instance.new("IntValue")
			cashVal.Name = "Cash"
			cashVal.Parent = folder
		end
		if cashVal:IsA("IntValue") or cashVal:IsA("NumberValue") then
			(cashVal :: any).Value = cash
		end
		local goldVal = folder:FindFirstChild("Gold")
		if not goldVal then
			goldVal = Instance.new("IntValue")
			goldVal.Name = "Gold"
			goldVal.Parent = folder
		end
		if goldVal:IsA("IntValue") or goldVal:IsA("NumberValue") then
			(goldVal :: any).Value = gold
		end
	end)
end

local function tryPushEconomy(player: Player)
	-- Best-effort: EconomyService may not be Init'd yet; attrs alone unblock HUD
	pcall(function()
		local EconomyService = require(script.Parent.EconomyService)
		if EconomyService and EconomyService.Push then
			EconomyService.Push(player)
		end
	end)
end

local function mergeDsIntoLive(live: PlayerProfile, dsProfile: PlayerProfile, userId: number)
	-- Prefer max Cash/Gold; never drop below StartingCash / AdminPlaytest floor
	local EconomyConfig = require(Shared.Configs.EconomyConfig)
	local startCash = math.floor(tonumber(EconomyConfig.StartingCash) or 10000)
	live.Cash = math.max(
		math.floor(tonumber(live.Cash) or 0),
		math.floor(tonumber(dsProfile.Cash) or 0),
		startCash
	)
	live.Gold = math.max(
		math.floor(tonumber(live.Gold) or 0),
		math.floor(tonumber(dsProfile.Gold) or 0)
	)
	live.PendingCash = math.max(
		math.floor(tonumber((live :: any).PendingCash) or 0),
		math.floor(tonumber((dsProfile :: any).PendingCash) or 0)
	)
	-- Keep BaseUpgrades from DS when present (real progress)
	local dsUp = dsProfile.BaseUpgrades
	if typeof(dsUp) == "table" then
		local hasProgress = false
		for _, lv in pairs(dsUp) do
			if (tonumber(lv) or 0) > 0 then
				hasProgress = true
				break
			end
		end
		if hasProgress then
			live.BaseUpgrades = dsUp
		end
	end
	-- Prefer DS progression when it looks real (Level/XP/vehicles/etc.)
	if (tonumber(dsProfile.Level) or 1) > (tonumber(live.Level) or 1) then
		live.Level = dsProfile.Level
		live.XP = dsProfile.XP
	elseif (tonumber(dsProfile.Level) or 1) == (tonumber(live.Level) or 1) then
		live.XP = math.max(tonumber(live.XP) or 0, tonumber(dsProfile.XP) or 0)
	end
	if (tonumber(dsProfile.Prestige) or 0) > (tonumber(live.Prestige) or 0) then
		live.Prestige = dsProfile.Prestige
	end
	if typeof(dsProfile.Vehicles) == "table" then
		for id, owned in pairs(dsProfile.Vehicles) do
			if owned then
				live.Vehicles[id] = true
			end
		end
	end
	if typeof(dsProfile.Weapons) == "table" then
		for id, owned in pairs(dsProfile.Weapons) do
			if owned then
				live.Weapons[id] = true
			end
		end
	end
	if typeof(dsProfile.Soldiers) == "number" then
		live.Soldiers = math.max(tonumber(live.Soldiers) or 0, dsProfile.Soldiers)
	end
	if dsProfile.BasePlotId ~= nil and live.BasePlotId == nil then
		live.BasePlotId = dsProfile.BasePlotId
	end
	if dsProfile.TutorialComplete then
		live.TutorialComplete = true
		live.TutorialStep = dsProfile.TutorialStep
	end
	if typeof(dsProfile.Stats) == "table" and typeof(live.Stats) == "table" then
		live.Stats.UpgradesPurchased = math.max(
			tonumber(live.Stats.UpgradesPurchased) or 0,
			tonumber(dsProfile.Stats.UpgradesPurchased) or 0
		)
	end
	if typeof(dsProfile.FirstJoinUnix) == "number" and dsProfile.FirstJoinUnix > 0 then
		if live.FirstJoinUnix == 0 or live.FirstJoinUnix == nil or dsProfile.FirstJoinUnix < live.FirstJoinUnix then
			live.FirstJoinUnix = dsProfile.FirstJoinUnix
		end
	end
	applyAdminPlaytestCash(userId, live)
	-- Final floors
	live.Cash = math.max(math.floor(tonumber(live.Cash) or 0), startCash)
	if userId == ADMIN_PLAYTEST_USER_ID then
		local floor = math.floor(tonumber(AdminConfig.AdminPlaytestCash) or 50_000_000)
		live.Cash = math.max(live.Cash, floor)
	end
end

-- v60: instant playable profile — never block join on DataStore / session lock
function DataService.LoadProfile(player: Player): PlayerProfile?
	local userId = player.UserId
	if profiles[userId] then
		return profiles[userId]
	end
	if loading[userId] then
		local waited = DataService.WaitForProfile(player, 8)
		if waited then
			return waited
		end
		warn("[DataService] WaitForProfile timed out while loading; EnsureProfile for", userId)
		loading[userId] = false
		return DataService.EnsureProfile(player)
	end
	loading[userId] = true

	-- 1) Instant CreateDefault + AdminPlaytestCash so HUD/BUY work within ~1s
	local profile = ProfileSchema.CreateDefault()
	profile.LastJoinUnix = os.time()
	if profile.FirstJoinUnix == 0 or profile.FirstJoinUnix == nil then
		profile.FirstJoinUnix = os.time()
	end
	applyStudioDevFlags(profile)
	local adminCashApplied = applyAdminPlaytestCash(userId, profile)

	profiles[userId] = profile
	dirty[userId] = true
	loading[userId] = false

	stampEconomyAttrs(player, profile)
	tryPushEconomy(player)
	fireProfileLoaded(player, profile)

	print(string.format(
		"[DataService] instant profile userId=%d cash=%d WE_Build=64",
		userId,
		math.floor(tonumber(profile.Cash) or 0)
	))

	-- 2) Background: soft session lock + GetAsync merge (never Kick)
	task.spawn(function()
		local acquired, lockErr = SessionLock.TryAcquire(userId)
		if not acquired then
			warn("[DataService] Session lock failed (continuing — no kick) for", userId, lockErr)
			if AnalyticsService then
				AnalyticsService.Log("SESSION_LOCK_CONFLICT", userId, { err = tostring(lockErr), soft = true })
			end
		end

		local ds = getDataStore()
		if not ds then
			if adminCashApplied and player.Parent and profiles[userId] then
				DataService.SaveProfile(player, false)
			end
			return
		end

		local ok, raw = retryAsync("GetAsync", function()
			return ds:GetAsync(keyFor(userId))
		end)
		if not player.Parent then
			return
		end
		local live = profiles[userId]
		if not live then
			return
		end

		if ok and raw ~= nil then
			local dsProfile = ProfileSchema.Migrate(raw)
			mergeDsIntoLive(live, dsProfile, userId)
			dirty[userId] = true
			stampEconomyAttrs(player, live)
			tryPushEconomy(player)
			-- Light refresh: base upgrades/state from DS without re-firing OnProfileLoaded
			pcall(function()
				local BaseService = require(script.Parent.BaseService)
				if BaseService.PushState then
					BaseService.PushState(player)
				end
				if BaseService.RefreshAllVisuals then
					BaseService.RefreshAllVisuals(player)
				end
			end)
			print(string.format(
				"[DataService] DS merge userId=%d cash=%d",
				userId,
				math.floor(tonumber(live.Cash) or 0)
			))
		elseif not ok then
			warn("[DataService] Background GetAsync failed for", userId, raw)
		end

		-- Persist after instant grant / merge
		if player.Parent and profiles[userId] then
			DataService.SaveProfile(player, false)
		end
	end)

	return profile
end


--- v58: never leave a joined player without a profile (CreateDefault + AdminPlaytestCash + OnProfileLoaded).
function DataService.EnsureProfile(player: Player): PlayerProfile
	local userId = player.UserId
	local existing = profiles[userId]
	if existing then
		return existing
	end
	-- v63: never yield >0.25s on buy/pad path — instant CreateDefault if missing
	local waited = DataService.WaitForProfile(player, 0.25)
	if waited then
		return waited
	end
	if not player.Parent then
		-- Player left — still return a throwaway default so callers do not nil-crash
		return ProfileSchema.CreateDefault()
	end
	warn("[DataService] EnsureProfile CreateDefault fallback for", userId)
	loading[userId] = false
	local profile = ProfileSchema.CreateDefault()
	profile.LastJoinUnix = os.time()
	if profile.FirstJoinUnix == 0 or profile.FirstJoinUnix == nil then
		profile.FirstJoinUnix = os.time()
	end
	applyStudioDevFlags(profile)
	local adminCashApplied = applyAdminPlaytestCash(userId, profile)
	profiles[userId] = profile
	dirty[userId] = true
	loading[userId] = false
	stampEconomyAttrs(player, profile)
	tryPushEconomy(player)
	fireProfileLoaded(player, profile)
	if adminCashApplied then
		task.defer(function()
			if player.Parent and profiles[userId] then
				DataService.SaveProfile(player, false)
			end
		end)
	end
	return profile
end

--- Clear in-memory profile without saving (optional admin wipeprofile).
function DataService.ClearInMemoryProfile(userId: number)
	profiles[userId] = nil
	dirty[userId] = nil
	loading[userId] = nil
end

--- RemoveAsync player_USERID; does not touch session lock.
function DataService.RemovePersistedProfile(userId: number): (boolean, string?)
	local ds = getDataStore()
	if not ds then
		return false, "DataStore unavailable"
	end
	local ok, err = pcall(function()
		ds:RemoveAsync(keyFor(userId))
	end)
	if not ok then
		return false, tostring(err)
	end
	return true, nil
end

function DataService.SaveProfile(player: Player, releaseLock: boolean?): boolean
	local userId = player.UserId
	local profile = profiles[userId]
	if not profile then
		return false
	end

	local ds = getDataStore()
	if not ds then
		dirty[userId] = false
		if releaseLock then
			SessionLock.Release(userId)
		end
		return true -- nothing to persist
	end

	local snapshot = ProfileSchema.DeepCopy(profile)
	local ok, err = retryAsync("SetAsync", function()
		ds:SetAsync(keyFor(userId), snapshot)
	end)

	if ok then
		dirty[userId] = false
		SessionLock.Refresh(userId)
		if releaseLock then
			SessionLock.Release(userId)
		end
		return true
	end

	warn("[DataService] Save failed for", userId, err)
	if releaseLock then
		SessionLock.Release(userId)
	end
	return false
end

function DataService.UnloadProfile(player: Player)
	local userId = player.UserId
	if profiles[userId] then
		DataService.SaveProfile(player, true)
	else
		-- Still release if load was in-flight or profile missing (never soft-lock forever)
		SessionLock.Release(userId)
	end
	profiles[userId] = nil
	dirty[userId] = nil
	loading[userId] = nil
end

function DataService.Init()
	Players.PlayerAdded:Connect(function(player)
		local profile = DataService.LoadProfile(player)
		if not profile and player.Parent then
			DataService.EnsureProfile(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		DataService.UnloadProfile(player)
	end)

	-- Late joiners already in game
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			local profile = DataService.LoadProfile(player)
			if not profile and player.Parent then
				DataService.EnsureProfile(player)
			end
		end)
	end

	-- Session-lock heartbeat (must be < SessionLockTtlSeconds so live locks stay fresh)
	task.spawn(function()
		local refreshEvery = Constants.SessionLockRefreshSeconds
		while true do
			task.wait(refreshEvery)
			for _, player in ipairs(Players:GetPlayers()) do
				if profiles[player.UserId] then
					SessionLock.Refresh(player.UserId)
				end
			end
		end
	end)

	-- Autosave
	task.spawn(function()
		while true do
			task.wait(Constants.AutosaveIntervalSeconds)
			for _, player in ipairs(Players:GetPlayers()) do
				if dirty[player.UserId] and profiles[player.UserId] then
					DataService.SaveProfile(player, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		local players = Players:GetPlayers()
		local remaining = #players
		if remaining == 0 then
			return
		end
		for _, player in ipairs(players) do
			task.spawn(function()
				local userId = player.UserId
				if profiles[userId] then
					DataService.SaveProfile(player, true)
				else
					SessionLock.ForceReleaseIfStaleOrOurs(userId)
				end
				remaining -= 1
			end)
		end
		local deadline = os.clock() + 25
		while remaining > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
