--!strict
--[[
	Season state — active season id, XP/Cash bonuses, persisted end override.
	DataStore WarEmpire_Season_v1 with Studio in-memory fallback.
	Bonuses applied via GetXPMult / GetCashMult; never client-granted.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local SeasonConfig = require(Shared.Configs.SeasonConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)

local SeasonService = {}

local SEASON_STORE_NAME = "WarEmpire_Season_v1"
local STATE_KEY = "season_state_v1"

local DataService: any = nil
local NotificationService: any = nil
local RemoteSetup: any = nil
local AnalyticsService: any = nil

local endedOverride = SeasonConfig.Ended == true
local endedUnix = 0
local endedReason = ""
local persisted = false
local seasonStore: DataStore? = nil
local dataStoreAvailable = false
local loaded = false

local function getStore(): DataStore?
	if seasonStore then
		return seasonStore
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(SEASON_STORE_NAME)
	end)
	if ok then
		seasonStore = result
		dataStoreAvailable = true
		return seasonStore
	end
	dataStoreAvailable = false
	warn("[SeasonService] DataStore unavailable — session-only season end state.", result)
	return nil
end

local function configWindowActive(): boolean
	local now = os.time()
	local startUnix = tonumber(SeasonConfig.StartUnix) or 0
	local endUnix = tonumber(SeasonConfig.EndUnix) or 0
	if startUnix > 0 and now < startUnix then
		return false
	end
	if endUnix > 0 and now > endUnix then
		return false
	end
	return SeasonConfig.Ended ~= true
end

local function isActive(): boolean
	if endedOverride then
		return false
	end
	return configWindowActive()
end

local function persistState()
	local store = getStore()
	if not store then
		persisted = false
		return
	end
	local payload = {
		SeasonId = SeasonConfig.CurrentSeasonId,
		EndedOverride = endedOverride,
		EndedUnix = endedUnix,
		EndedReason = endedReason,
	}
	local ok, err = pcall(function()
		store:SetAsync(STATE_KEY, payload)
	end)
	if not ok then
		warn("[SeasonService] persist failed:", err)
		persisted = false
		return
	end
	persisted = true
end

local function loadState()
	if loaded then
		return
	end
	loaded = true
	local store = getStore()
	if not store then
		return
	end
	local ok, data = pcall(function()
		return store:GetAsync(STATE_KEY)
	end)
	if not ok or typeof(data) ~= "table" then
		return
	end
	-- Only apply override if it matches current season id (new seasons reset)
	if data.SeasonId == SeasonConfig.CurrentSeasonId and data.EndedOverride == true then
		endedOverride = true
		endedUnix = tonumber(data.EndedUnix) or 0
		endedReason = tostring(data.EndedReason or "persisted")
		persisted = true
	elseif data.SeasonId ~= SeasonConfig.CurrentSeasonId then
		-- New season config: clear stale end flag in store
		endedOverride = SeasonConfig.Ended == true
		endedUnix = 0
		endedReason = ""
		persistState()
	end
end

local function buildPayload(): { [string]: any }
	local active = isActive()
	return {
		SeasonId = SeasonConfig.CurrentSeasonId,
		DisplayName = SeasonConfig.DisplayName,
		Active = active,
		Ended = not active,
		XPBonusMult = if active then (SeasonConfig.XPBonusMult or 1) else 1,
		CashBonusMult = if active then (SeasonConfig.CashBonusMult or 1) else 1,
		StartUnix = SeasonConfig.StartUnix,
		EndUnix = SeasonConfig.EndUnix,
		EndedUnix = endedUnix,
		Persisted = persisted or dataStoreAvailable,
	}
end

local function pushState(player: Player)
	local remote = RemoteSetup.Get(Constants.RemoteNames.SeasonStateUpdate) :: RemoteEvent
	remote:FireClient(player, buildPayload())
end

local function pushAll()
	for _, player in ipairs(Players:GetPlayers()) do
		pushState(player)
	end
end

function SeasonService.GetSeasonId(): string
	return SeasonConfig.CurrentSeasonId
end

function SeasonService.IsActive(): boolean
	return isActive()
end

function SeasonService.GetXPMult(): number
	if not isActive() then
		return 1
	end
	return tonumber(SeasonConfig.XPBonusMult) or 1
end

function SeasonService.GetCashMult(): number
	if not isActive() then
		return 1
	end
	return tonumber(SeasonConfig.CashBonusMult) or 1
end

--[[ End season for this place: clears bonuses, persists across servers when API services on. ]]
function SeasonService.EndSeason(reason: string?)
	if endedOverride and not isActive() then
		-- Already ended
		pushAll()
		return
	end
	endedOverride = true
	endedUnix = os.time()
	endedReason = reason or "manual"
	persistState()

	local eventName = if AnalyticsConfig.Events.SEASON_END then AnalyticsConfig.Events.SEASON_END else "SEASON_END"
	if AnalyticsService and AnalyticsService.Log then
		AnalyticsService.Log(eventName, 0, {
			seasonId = SeasonConfig.CurrentSeasonId,
			reason = endedReason,
			persisted = persisted,
		})
	end
	if NotificationService then
		NotificationService.NotifyAll(
			string.format("Season ended: %s — bonuses cleared.", tostring(SeasonConfig.DisplayName)),
			"Info"
		)
	end
	pushAll()
end

--[[ Clear end override (admin / new season tooling). ]]
function SeasonService.ClearEndOverride(reason: string?)
	endedOverride = false
	endedUnix = 0
	endedReason = ""
	persistState()
	if AnalyticsService and AnalyticsService.Log then
		AnalyticsService.Log("SEASON_RESUME", 0, {
			seasonId = SeasonConfig.CurrentSeasonId,
			reason = reason or "clear",
		})
	end
	if NotificationService then
		NotificationService.NotifyAll("Season resumed: " .. tostring(SeasonConfig.DisplayName), "Success")
	end
	pushAll()
end

function SeasonService.Push(player: Player)
	pushState(player)
end

function SeasonService.Init(deps: { [string]: any })
	DataService = deps.DataService
	NotificationService = deps.NotificationService
	RemoteSetup = deps.RemoteSetup
	AnalyticsService = deps.AnalyticsService

	loadState()

	-- Auto-end when config EndUnix has passed (persist once)
	if not endedOverride then
		local endUnix = tonumber(SeasonConfig.EndUnix) or 0
		if endUnix > 0 and os.time() > endUnix then
			SeasonService.EndSeason("end_unix")
		end
	end

	DataService.OnProfileLoaded(function(player: Player, _profile: any)
		pushState(player)
	end)

	-- Periodic check for scheduled end
	task.spawn(function()
		while true do
			task.wait(30)
			if not endedOverride then
				local endUnix = tonumber(SeasonConfig.EndUnix) or 0
				if endUnix > 0 and os.time() > endUnix then
					SeasonService.EndSeason("end_unix_tick")
				end
			end
		end
	end)
end

return SeasonService
