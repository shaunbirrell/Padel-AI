--!strict
--[[
	Minimal season state — active season id, XP/Cash bonuses, end stub.
	Bonuses applied via GetXPMult / GetCashMult; never client-granted.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local SeasonConfig = require(Shared.Configs.SeasonConfig)

local SeasonService = {}

local DataService: any = nil
local NotificationService: any = nil
local RemoteSetup: any = nil
local AnalyticsService: any = nil

local endedOverride = SeasonConfig.Ended == true

local function isActive(): boolean
	if endedOverride then
		return false
	end
	local now = os.time()
	local startUnix = tonumber(SeasonConfig.StartUnix) or 0
	local endUnix = tonumber(SeasonConfig.EndUnix) or 0
	if startUnix > 0 and now < startUnix then
		return false
	end
	if endUnix > 0 and now > endUnix then
		return false
	end
	return true
end

local function pushState(player: Player)
	local remote = RemoteSetup.Get(Constants.RemoteNames.SeasonStateUpdate) :: RemoteEvent
	remote:FireClient(player, {
		SeasonId = SeasonConfig.CurrentSeasonId,
		DisplayName = SeasonConfig.DisplayName,
		Active = isActive(),
		Ended = not isActive(),
		XPBonusMult = if isActive() then (SeasonConfig.XPBonusMult or 1) else 1,
		CashBonusMult = if isActive() then (SeasonConfig.CashBonusMult or 1) else 1,
		StartUnix = SeasonConfig.StartUnix,
		EndUnix = SeasonConfig.EndUnix,
	})
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

--[[ Stub: mark season ended for this server (persist via config/DataStore later). ]]
function SeasonService.EndSeason(reason: string?)
	endedOverride = true
	if AnalyticsService and AnalyticsService.Log then
		AnalyticsService.Log("SEASON_END", 0, { seasonId = SeasonConfig.CurrentSeasonId, reason = reason or "stub" })
	end
	if NotificationService then
		NotificationService.NotifyAll("Season ended: " .. tostring(SeasonConfig.DisplayName), "Info")
	end
	-- Push to all online players
	local Players = game:GetService("Players")
	for _, player in ipairs(Players:GetPlayers()) do
		pushState(player)
	end
end

function SeasonService.Push(player: Player)
	pushState(player)
end

function SeasonService.Init(deps: { [string]: any })
	DataService = deps.DataService
	NotificationService = deps.NotificationService
	RemoteSetup = deps.RemoteSetup
	AnalyticsService = deps.AnalyticsService

	DataService.OnProfileLoaded(function(player: Player, _profile: any)
		pushState(player)
	end)
end

return SeasonService
