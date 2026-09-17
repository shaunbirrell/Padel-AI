--!strict
--[[
	WAR EMPIRE — Server Bootstrap
	Wires remotes + services. Request/action remotes only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
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
local TutorialService = require(Services.TutorialService)

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
	TutorialService = TutorialService,
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
MonetizationService.Init(deps) -- GamePass cache on join
TutorialService.Init(deps) -- tutorial step on join + upgrade hook

-- Now load profiles (fires OnProfileLoaded for joiners)
DataService.Init()

AdminService.Init(deps)
CombatService.Init(deps)
VehicleService.Init(deps)
TerritoryService.Init(deps)
MissionService.Init(deps)
PrestigeService.Init(deps)
ClanService.Init(deps)

if DevConfig.VerboseLogging then
	print("[WAR EMPIRE] Services initialized. Plots:", Constants.MaxBasePlots)
end

print("[WAR EMPIRE] Server Bootstrap ready.")
