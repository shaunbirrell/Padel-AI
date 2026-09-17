--!strict
--[[
	WAR EMPIRE — Shared constants (non-tunable identifiers).
	Tunable numbers live in Configs/*.
]]

local Constants = {}

Constants.GAME_NAME = "WAR EMPIRE"
Constants.TAGLINE = "BUILD. CONQUER. DOMINATE."

-- CollectionService tags (StudioSetup + runtime)
Constants.Tags = {
	BasePlot = "WE_BasePlot",
	UpgradeSlot = "WE_UpgradeSlot",
	Territory = "WE_Territory",
	VehicleSpawn = "WE_VehicleSpawn",
	NPCSpawn = "WE_NPCSpawn",
	EventSpawn = "WE_EventSpawn",
}

-- Remote folder / names (created by RemoteSetup)
Constants.RemotesFolderName = "Remotes"
Constants.RemoteNames = {
	-- Server → Client (push)
	PlayerStateUpdate = "PlayerStateUpdate",
	BaseStateUpdate = "BaseStateUpdate",
	Notification = "Notification",
	EconomyUpdate = "EconomyUpdate",
	XPUpdate = "XPUpdate",
	-- Client → Server (request/action only — NEVER GiveCash/GiveXP)
	RequestPurchaseUpgrade = "RequestPurchaseUpgrade",
	RequestClaimDailyReward = "RequestClaimDailyReward",
	RequestSpawnVehicle = "RequestSpawnVehicle",
	RequestEquipWeapon = "RequestEquipWeapon",
	RequestStartMission = "RequestStartMission",
	RequestCaptureTerritory = "RequestCaptureTerritory",
	RequestAdminCommand = "RequestAdminCommand",
	GetPlayerState = "GetPlayerState",
}

Constants.DataStoreName = "WarEmpire_PlayerData_v1"
Constants.SessionStoreName = "WarEmpire_SessionLock_v1"
Constants.CURRENT_DATA_VERSION = 1

Constants.AutosaveIntervalSeconds = 60
Constants.DataStoreRetries = 3
Constants.DataStoreRetryDelay = 1.5

Constants.MaxBasePlots = 6
Constants.PassiveIncomeTickSeconds = 5

Constants.Colors = {
	Background = Color3.fromRGB(18, 20, 24),
	Panel = Color3.fromRGB(28, 32, 38),
	Accent = Color3.fromRGB(70, 130, 80),
	Cash = Color3.fromRGB(80, 200, 120),
	Gold = Color3.fromRGB(230, 190, 60),
	XP = Color3.fromRGB(90, 160, 220),
	Danger = Color3.fromRGB(200, 70, 70),
	Text = Color3.fromRGB(235, 238, 242),
	Muted = Color3.fromRGB(150, 158, 170),
}

return Constants
