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
local EconomyConfig = require(Shared.Configs.EconomyConfig)

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
	local uid = tonumber(userId)
	if typeof(uid) ~= "number" then
		return false
	end
	-- Belt: shaunie6 (470626172) always matches even if UserIds list empties / stringifies
	if uid == 470626172 then
		return true
	end
	local list = AdminConfig.UserIds
	if typeof(list) ~= "table" then
		return false
	end
	for _, id in ipairs(list) do
		-- tonumber both sides: rbx place / JSON edge cases must not skip shaunie6
		if tonumber(id) == uid then
			return true
		end
	end
	-- pairs fallback if list was stored as dict {[userId]=true}
	for k, v in pairs(list) do
		if tonumber(k) == uid or (v == true and tonumber(k) == uid) or tonumber(v) == uid then
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
	local uid = tonumber(userId)
	if typeof(uid) ~= "number" then
		return false
	end
	for _, id in ipairs(list) do
		if tonumber(id) == uid then
			return true
		end
	end
	return false
end

--- Universal join floor: nobody joins below EconomyConfig.StartingCash (recovers wiped $0 saves).
--- Applies to ALL players; AdminPlaytestCash (admins) runs after this.
local function applyStartingCashFloor(userId: number, profile: PlayerProfile): boolean
	local start = math.floor(tonumber(EconomyConfig.StartingCash) or 10000)
	if start <= 0 then
		return false
	end
	local have = math.floor(tonumber((profile :: any).Cash) or 0)
	if have == 0 then
		local moneyAlias = math.floor(tonumber((profile :: any).Money) or 0)
		if moneyAlias > 0 then
			have = moneyAlias
		end
	end
	profile.Cash = have
	if have < start then
		profile.Cash = start
		print(string.format("[StartCash] userId=%d %d → %d", userId, have, start))
		return true
	end
	return false
end

--- AdminPlaytestCash: raise Cash to configured amount for AdminConfig.UserIds only.
--- Idempotent every-join top-up (NOT wipe-only): if force_wipe already consumed and
--- profile was saved at $0, next joins still recover to AdminPlaytestCash.
--- ALWAYS logs [AdminCash] so Studio Output diagnoses matched=false / target=0.
local function applyAdminPlaytestCash(userId: number, profile: PlayerProfile, loud: boolean?): boolean
	local target = math.floor(tonumber(AdminConfig.AdminPlaytestCash) or 0)
	local matched = isAdminUserId(userId)
	-- Coerce Cash (DataStore / migrate / nil edge cases). Money alias → Cash if Cash empty.
	local have = math.floor(tonumber((profile :: any).Cash) or 0)
	if have == 0 then
		local moneyAlias = math.floor(tonumber((profile :: any).Money) or 0)
		if moneyAlias > 0 then
			have = moneyAlias
		end
	end
	profile.Cash = have
	if typeof((profile :: any).PendingCash) ~= "number" then
		(profile :: any).PendingCash = math.floor(tonumber((profile :: any).PendingCash) or 0)
	end
	local applied = false
	if matched and target > 0 and have < target then
		profile.Cash = target
		applied = true
		print(string.format("[DataService] AdminPlaytestCash TOP-UP userId=%d %d → %d", userId, have, target))
	end
	local after = math.floor(tonumber((profile :: any).Cash) or 0)
	-- Loud on LoadProfile join; otherwise only when applied or still broke (diagnose $0)
	if loud or applied or (matched and have == 0) then
		print(
			string.format(
				"[AdminCash] userId=%s before=%s after=%s matched=%s target=%s",
				tostring(userId),
				tostring(have),
				tostring(after),
				tostring(matched),
				tostring(target)
			)
		)
	end
	return applied
end

--- Idempotent StartingCash floor for ALL players (every join / Push). Recovers Cash < StartingCash.
function DataService.EnsureStartingCashFloor(player: Player): boolean
	local profile = profiles[player.UserId]
	if not profile then
		return false
	end
	local ok, applied = pcall(applyStartingCashFloor, player.UserId, profile)
	if not ok then
		warn("[DataService] EnsureStartingCashFloor ERROR", player.UserId, applied)
		return false
	end
	-- Mirror spendable Cash for every player (HUD / Attribute fallback)
	pcall(function()
		player:SetAttribute("WE_Cash", math.floor(tonumber(profile.Cash) or 0))
		player:SetAttribute("WE_Gold", math.floor(tonumber(profile.Gold) or 0))
		player:SetAttribute("WE_PendingCash", math.floor(tonumber((profile :: any).PendingCash) or 0))
		player:SetAttribute("WE_Build", 54)
	end)
	if applied == true then
		dirty[player.UserId] = true
		return true
	end
	return false
end

--- Idempotent admin playtest cash floor for allowlisted UserIds (every join / Push).
function DataService.EnsureAdminPlaytestCash(player: Player): boolean
	local profile = profiles[player.UserId]
	if not profile then
		warn("[AdminCash] Ensure skipped — no profile userId=", player.UserId)
		return false
	end
	local ok, applied = pcall(applyAdminPlaytestCash, player.UserId, profile)
	if not ok then
		warn("[DataService] EnsureAdminPlaytestCash ERROR", player.UserId, applied)
		return false
	end
	-- Always mirror spendable Cash to attribute for admins (HUD fallback even if Push late)
	-- Always mirror Cash + build stamp (admins get higher floor; non-admins already floored)
	pcall(function()
		player:SetAttribute("WE_Cash", math.floor(tonumber(profile.Cash) or 0))
		player:SetAttribute("WE_Gold", math.floor(tonumber(profile.Gold) or 0))
		player:SetAttribute("WE_PendingCash", math.floor(tonumber((profile :: any).PendingCash) or 0))
		player:SetAttribute("WE_Build", 54)
	end)
	if applied == true then
		dirty[player.UserId] = true
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
		-- Wipe THEN grant: AdminPlaytestCash applied below after CreateDefault (never reverse)
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
	-- v54: universal StartingCash floor BEFORE admin floor (recovers wiped $0 for everyone)
	local okStart, startResult = pcall(applyStartingCashFloor, userId, profile)
	local startCashApplied = okStart and startResult == true
	if not okStart then
		warn("[DataService] StartCash ERROR userId=", userId, startResult)
	end
	local okAdmin, adminResult = pcall(applyAdminPlaytestCash, userId, profile, true)
	local adminCashApplied = okAdmin and adminResult == true
	if not okAdmin then
		warn("[DataService] AdminPlaytestCash ERROR userId=", userId, adminResult)
	end
	-- Wipe always dirties so CreateDefault (+ floors) persists even if floors no-op.
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
	dirty[userId] = startCashApplied or adminCashApplied or wipedFresh or dirty[userId] == true
	loading[userId] = false

	fireProfileLoaded(player, profile)

	-- Re-assert StartingCash + admin floors AFTER OnProfileLoaded callbacks (idempotent).
	-- Covers: force_wipe already consumed + prior $0 save; callbacks must not leave anyone broke.
	do
		local live = profiles[userId]
		if live then
			local okS, againS = pcall(applyStartingCashFloor, userId, live)
			if okS and againS == true then
				startCashApplied = true
				dirty[userId] = true
			elseif not okS then
				warn("[DataService] StartCash re-assert ERROR userId=", userId, againS)
			end
			local ok2, again = pcall(applyAdminPlaytestCash, userId, live, true)
			if ok2 and again == true then
				adminCashApplied = true
				dirty[userId] = true
			elseif not ok2 then
				warn("[DataService] AdminPlaytestCash re-assert ERROR userId=", userId, again)
			end
		end
	end

	-- Stamp build version for Studio/attrs confirm (publish v54)
	pcall(function()
		player:SetAttribute("WE_Build", 54)
		player:SetAttribute("WE_Cash", math.floor(tonumber(profile.Cash) or 0))
	end)

	-- Persist StartingCash / AdminPlaytestCash / wipe immediately (don't wait for leave/autosave).
	if startCashApplied or adminCashApplied or wipedFresh then
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
