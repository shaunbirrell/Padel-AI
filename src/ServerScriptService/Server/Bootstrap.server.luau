--!strict
--[[
	WAR EMPIRE — Server Bootstrap
	Wires remotes + services. Request/action remotes only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local DailyRewardConfig = require(Shared.Configs.DailyRewardConfig)
local DevConfig = require(Shared.Configs.DevConfig)

local ServerFolder = script.Parent
local Modules = ServerFolder:WaitForChild("Modules")
local Services = ServerFolder:WaitForChild("Services")

local RemoteSetup = require(Modules.RemoteSetup)
local DataService = require(Services.DataService)
local EconomyService = require(Services.EconomyService)
local BaseService = require(Services.BaseService)
local XPService = require(Services.XPService)
local RateLimitService = require(Services.RateLimitService)
local AnalyticsService = require(Services.AnalyticsService)
local AdminService = require(Services.AdminService)
local NotificationService = require(Services.NotificationService)
local AntiExploitService = require(Services.AntiExploitService)
local CombatService = require(Services.CombatService)
local VehicleService = require(Services.VehicleService)
local TerritoryService = require(Services.TerritoryService)
local MissionService = require(Services.MissionService)
local PrestigeService = require(Services.PrestigeService)
local ClanService = require(Services.ClanService)
local MonetizationService = require(Services.MonetizationService)

print("[WAR EMPIRE] Server Bootstrap starting...")

RemoteSetup.Init()

local deps: { [string]: any } = {
	RemoteSetup = RemoteSetup,
	DataService = DataService,
	EconomyService = EconomyService,
	BaseService = BaseService,
	XPService = XPService,
	RateLimitService = RateLimitService,
	AnalyticsService = AnalyticsService,
	AdminService = AdminService,
	NotificationService = NotificationService,
	AntiExploitService = AntiExploitService,
	CombatService = CombatService,
	VehicleService = VehicleService,
	TerritoryService = TerritoryService,
	MissionService = MissionService,
	PrestigeService = PrestigeService,
	ClanService = ClanService,
	MonetizationService = MonetizationService,
}

RateLimitService.Init()
AnalyticsService.Init()
DataService.SetAnalytics(AnalyticsService)

-- Init services that OnProfileLoaded depends on BEFORE DataService loads players
EconomyService.Init(deps)
XPService.Init(deps)
NotificationService.Init(deps)
AntiExploitService.Init(deps)
BaseService.Init(deps) -- registers OnProfileLoaded

-- Now load profiles (fires OnProfileLoaded for joiners)
DataService.Init()

AdminService.Init(deps)
CombatService.Init(deps)
VehicleService.Init(deps)
TerritoryService.Init(deps)
MissionService.Init(deps)
PrestigeService.Init(deps)
ClanService.Init(deps)
MonetizationService.Init(deps)

-- Daily reward claim (simple inline handler)
local function yyyymmdd(unix: number): number
	local t = os.date("!*t", unix)
	return t.year * 10000 + t.month * 100 + t.day
end

local claimRemote = RemoteSetup.Get(Constants.RemoteNames.RequestClaimDailyReward) :: RemoteEvent
claimRemote.OnServerEvent:Connect(function(player: Player)
	if not RateLimitService.Allow(player, "daily_reward", 1, 2) then
		return
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	local today = yyyymmdd(os.time())
	local daily = profile.DailyLogin
	if daily.LastClaimDay == today then
		NotificationService.Notify(player, "Daily reward already claimed.", "Warn")
		return
	end

	local yesterday = yyyymmdd(os.time() - 86400)
	if DailyRewardConfig.MissedDayResetsStreak and daily.LastClaimDay ~= 0 and daily.LastClaimDay ~= yesterday then
		daily.Streak = 0
	end

	daily.Streak = (daily.Streak % DailyRewardConfig.StreakResetsAfterDay) + 1
	daily.LastClaimDay = today
	daily.LastClaimUnix = os.time()

	local reward = DailyRewardConfig.Rewards[daily.Streak]
	if reward then
		if reward.Cash > 0 then
			EconomyService.AddCash(player, reward.Cash, "daily")
		end
		if reward.Gold > 0 then
			EconomyService.AddGold(player, reward.Gold, "daily")
		end
		if reward.XP > 0 then
			XPService.AddXP(player, reward.XP, "daily")
		end
		NotificationService.Notify(
			player,
			string.format("Day %d reward: $%d", daily.Streak, reward.Cash),
			"Reward"
		)
		AnalyticsService.Log("DAILY_REWARD_CLAIMED", player.UserId, { day = daily.Streak })
	end
	DataService.MarkDirty(player)
end)

if DevConfig.VerboseLogging then
	print("[WAR EMPIRE] Services initialized. Plots:", Constants.MaxBasePlots)
end

print("[WAR EMPIRE] Server Bootstrap ready.")
