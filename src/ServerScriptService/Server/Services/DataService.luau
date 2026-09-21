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

local function forceWipeDoneKey(userId: number): string
	return "force_wipe_done_" .. tostring(userId)
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

local function isAdminUserId(userId: number): boolean
	for _, id in ipairs(AdminConfig.UserIds) do
		if id == userId then
			return true
		end
	end
	return false
end

local function isForceWipeUserId(userId: number): boolean
	local list = AdminConfig.ForceWipeUserIds
	if typeof(list) ~= "table" then
		return false
	end
	for _, id in ipairs(list) do
		if id == userId then
			return true
		end
	end
	return false
end

--- AdminPlaytestCash: raise Cash to configured amount for AdminConfig.UserIds only.
local function applyAdminPlaytestCash(userId: number, profile: PlayerProfile): boolean
	local target = tonumber(AdminConfig.AdminPlaytestCash)
	if typeof(target) ~= "number" or target == nil or target <= 0 then
		return false
	end
	if not isAdminUserId(userId) then
		return false
	end
	-- Coerce Cash (DataStore / migrate edge cases) so comparisons never throw.
	local have = math.floor(tonumber((profile :: any).Cash) or 0)
	profile.Cash = have
	if have < target then
		profile.Cash = target
		warn(string.format("[DataService] AdminPlaytestCash applied userId=%d %d → %d", userId, have, target))
		return true
	end
	return false
end

function DataService.LoadProfile(player: Player): PlayerProfile?
	local userId = player.UserId
	if profiles[userId] then
		return profiles[userId]
	end
	if loading[userId] then
		return DataService.WaitForProfile(player, 20)
	end
	loading[userId] = true

	local acquired, lockErr = SessionLock.TryAcquire(userId)
	if not acquired then
		warn("[DataService] Session lock failed for", userId, lockErr)
		if AnalyticsService then
			AnalyticsService.Log("SESSION_LOCK_CONFLICT", userId, { err = tostring(lockErr) })
		end
		-- Still allow play with default in Studio; kick in live if desired
		if not RunService:IsStudio() then
			loading[userId] = false
			player:Kick("Your data is loading in another server. Please rejoin in a moment.")
			return nil
		end
	end

	local profile: PlayerProfile
	local ds = getDataStore()
	local forceWipe = isForceWipeUserId(userId)
	local skipForceWipe = false
	if forceWipe and ds then
		-- Done key makes ForceWipeUserIds allowlist one-shot (list can stay populated).
		local doneOk, doneVal = pcall(function()
			return ds:GetAsync(forceWipeDoneKey(userId))
		end)
		if doneOk and doneVal then
			skipForceWipe = true
			warn("[DataService] FORCE WIPE skipped (already done) for", userId)
		end
	end
	if forceWipe and not skipForceWipe then
		-- One-shot playtest wipe: delete persisted profile BEFORE GetAsync, then fresh CreateDefault.
		-- Session lock already held via TryAcquire above; do not Release (would race rejoin).
		if ds then
			local wipeOk, wipeErr = pcall(function()
				ds:RemoveAsync(keyFor(userId))
			end)
			if not wipeOk then
				warn("[DataService] FORCE WIPE RemoveAsync failed for", userId, wipeErr)
			end
		else
			warn("[DataService] FORCE WIPE: DataStore unavailable — using CreateDefault only for", userId)
		end
		profile = ProfileSchema.CreateDefault()
		warn("[DataService] FORCE WIPE applied for", userId)
	elseif ds then
		local ok, raw = retryAsync("GetAsync", function()
			return ds:GetAsync(keyFor(userId))
		end)
		if ok and raw ~= nil then
			profile = ProfileSchema.Migrate(raw)
		else
			if not ok then
				warn("[DataService] Load failed, using defaults for", userId, raw)
			end
			profile = ProfileSchema.CreateDefault()
		end
	else
		profile = ProfileSchema.CreateDefault()
	end

	profile.LastJoinUnix = os.time()
	if profile.FirstJoinUnix == 0 or profile.FirstJoinUnix == nil then
		profile.FirstJoinUnix = os.time()
	end
	applyStudioDevFlags(profile)
	local adminCashApplied = applyAdminPlaytestCash(userId, profile)
	-- Wipe always dirties so CreateDefault (+ admin cash) persists even if admin cash no-ops.
	local wipedFresh = forceWipe and not skipForceWipe

	if wipedFresh and ds then
		local markOk, markErr = pcall(function()
			ds:SetAsync(forceWipeDoneKey(userId), { unix = os.time(), v = 1 })
		end)
		if not markOk then
			warn("[DataService] FORCE WIPE done-key SetAsync failed for", userId, markErr)
		end
	end

	profiles[userId] = profile
	dirty[userId] = adminCashApplied or wipedFresh or dirty[userId] == true
	loading[userId] = false

	fireProfileLoaded(player, profile)

	-- Persist AdminPlaytestCash / wipe immediately (don't wait for leave/autosave).
	if adminCashApplied or wipedFresh then
		task.defer(function()
			if player.Parent and profiles[userId] then
				DataService.SaveProfile(player, false)
			end
		end)
	end

	return profile
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

--- Clear in-memory profile without saving (admin wipe / force wipe path).
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

--- Remove force_wipe_done_USERID so ForceWipeUserIds can wipe again on next join.
function DataService.ClearForceWipeDone(userId: number): (boolean, string?)
	local ds = getDataStore()
	if not ds then
		return false, "DataStore unavailable"
	end
	local ok, err = pcall(function()
		ds:RemoveAsync(forceWipeDoneKey(userId))
	end)
	if not ok then
		return false, tostring(err)
	end
	return true, nil
end

function DataService.Init()
	Players.PlayerAdded:Connect(function(player)
		DataService.LoadProfile(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		DataService.UnloadProfile(player)
	end)

	-- Late joiners already in game
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(DataService.LoadProfile, player)
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
