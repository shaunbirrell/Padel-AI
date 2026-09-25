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
-- v67: true only when the profile content came from a successful DataStore read (existing save or a
-- confirmed new player). Only loaded profiles are ever written back, so a default / session-only profile
-- can never overwrite a real save.
local loaded: { [number]: boolean } = {}
-- v67: a leave-save still in flight; a same-server rejoin waits for it before reading the store.
local pendingSave: { [number]: boolean } = {}
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

--[[ v67: true when this player's profile was read from the DataStore and will be saved. False while the
	load is in flight and for a session-only profile (DataStore read failed). Receipts must wait for it. ]]
function DataService.IsLoaded(player: Player): boolean
	return loaded[player.UserId] == true
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
		player:SetAttribute("WE_Build", 76)
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

local function notifyPlayer(player: Player, text: string)
	task.defer(function()
		pcall(function()
			local NotificationService = require(script.Parent.NotificationService)
			if NotificationService and NotificationService.Notify then
				NotificationService.Notify(player, text, "Warn", 8)
			end
		end)
	end)
end

--[[
	v67: load the real save BEFORE the profile exists.

	v58–v65 handed out an instant default profile and merged ~15 fields of the save into it later, then
	saved the result — dropping everything else (entitlements, receipts, codes, battle pass, clan, daily,
	spinner, territories …) on every rejoin, writing the default over the save whenever the player left,
	autosave ran or GetAsync failed first, and lifting cash to StartingCash on each join. That instant
	profile only existed because this module failed to parse (v50–v65); a DataStore read takes well under
	a second. Now: GetProfile is nil until the read finishes; callers already handle nil ("still loading").
]]
function DataService.LoadProfile(player: Player): PlayerProfile?
	local userId = player.UserId
	if profiles[userId] then
		return profiles[userId]
	end
	if loading[userId] then
		return DataService.WaitForProfile(player, 20)
	end
	loading[userId] = true

	-- Same-server rejoin: let the previous session's leave-save land before reading.
	local waitStart = os.clock()
	while pendingSave[userId] and os.clock() - waitStart < 15 do
		task.wait(0.1)
	end

	local acquired, lockErr = SessionLock.TryAcquire(userId)
	if not acquired then
		warn("[DataService] Session lock failed (continuing — no kick) for", userId, lockErr)
		if AnalyticsService then
			AnalyticsService.Log("SESSION_LOCK_CONFLICT", userId, { err = tostring(lockErr), soft = true })
		end
	end

	local profile: PlayerProfile
	local persistent = true
	local ds = getDataStore()
	if not ds then
		-- Studio without API access: session-only profile (SaveProfile has nothing to write anyway).
		profile = ProfileSchema.CreateDefault()
	else
		local ok, raw = retryAsync("GetAsync", function()
			return ds:GetAsync(keyFor(userId))
		end)
		if ok then
			profile = if raw == nil then ProfileSchema.CreateDefault() else ProfileSchema.Migrate(raw)
		else
			-- Could not read the save. Let them play, but never write this default over the real data.
			warn("[DataService] GetAsync failed — session-only profile, saving disabled for", userId, raw)
			profile = ProfileSchema.CreateDefault()
			persistent = false
			notifyPlayer(player, "Your save could not be loaded. Progress this session will NOT be saved — rejoin to retry.")
		end
	end

	if not player.Parent then
		-- Left during the load: nothing was loaded, so nothing may be saved.
		loading[userId] = false
		SessionLock.Release(userId)
		return nil
	end

	profile.LastJoinUnix = os.time()
	if profile.FirstJoinUnix == 0 or profile.FirstJoinUnix == nil then
		profile.FirstJoinUnix = os.time()
	end
	applyStudioDevFlags(profile)
	applyAdminPlaytestCash(userId, profile)

	profiles[userId] = profile
	loaded[userId] = persistent
	dirty[userId] = persistent
	loading[userId] = false

	stampEconomyAttrs(player, profile)
	tryPushEconomy(player)
	fireProfileLoaded(player, profile)

	print(string.format(
		"[DataService] profile loaded userId=%d cash=%d persistent=%s WE_Build=76",
		userId,
		math.floor(tonumber(profile.Cash) or 0),
		tostring(persistent)
	))
	return profile
end


--[[ v67: never invents a profile. Returns the loaded profile, waits briefly for an in-flight load,
	or starts the load if none began (callers treat nil as "still loading"). ]]
function DataService.EnsureProfile(player: Player): PlayerProfile?
	local userId = player.UserId
	local existing = profiles[userId]
	if existing then
		return existing
	end
	if not player.Parent then
		return nil
	end
	if not loading[userId] then
		task.spawn(DataService.LoadProfile, player)
	end
	return DataService.WaitForProfile(player, 0.25)
end

--- Clear in-memory profile without saving (optional admin wipeprofile).
function DataService.ClearInMemoryProfile(userId: number)
	profiles[userId] = nil
	dirty[userId] = nil
	loading[userId] = nil
	loaded[userId] = nil
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

local function writeProfile(userId: number, profile: PlayerProfile, releaseLock: boolean?): boolean
	local ds = getDataStore()
	if not ds then
		if releaseLock then
			SessionLock.Release(userId)
		end
		return true -- nothing to persist (Studio without API access)
	end
	local snapshot = ProfileSchema.DeepCopy(profile)
	local ok, err = retryAsync("SetAsync", function()
		ds:SetAsync(keyFor(userId), snapshot)
	end)
	if ok then
		SessionLock.Refresh(userId)
	else
		warn("[DataService] Save failed for", userId, err)
	end
	if releaseLock then
		SessionLock.Release(userId)
	end
	return ok
end

function DataService.SaveProfile(player: Player, releaseLock: boolean?): boolean
	local userId = player.UserId
	local profile = profiles[userId]
	if not profile then
		return false
	end
	if not loaded[userId] then
		-- v67: session-only / not-yet-loaded profile — writing it would overwrite the real save.
		if releaseLock then
			SessionLock.Release(userId)
		end
		return false
	end
	local ok = writeProfile(userId, profile, releaseLock)
	if ok and profiles[userId] == profile then
		dirty[userId] = false
	end
	return ok
end

function DataService.UnloadProfile(player: Player)
	local userId = player.UserId
	local profile = profiles[userId]
	local wasLoaded = loaded[userId] == true
	-- Clear first so a same-server rejoin starts a fresh load instead of reusing this session's table.
	profiles[userId] = nil
	dirty[userId] = nil
	loading[userId] = nil
	loaded[userId] = nil
	if profile and wasLoaded then
		pendingSave[userId] = true
		writeProfile(userId, profile, true)
		pendingSave[userId] = nil
	else
		-- Never loaded (left mid-load / session-only): nothing to save; still release the lock.
		SessionLock.Release(userId)
	end
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
				if profiles[userId] and loaded[userId] then
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
