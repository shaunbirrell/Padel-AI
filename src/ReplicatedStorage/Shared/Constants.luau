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
	CaptureZone = "WE_CaptureZone",
	VehicleSpawn = "WE_VehicleSpawn",
	NavalSpawn = "WE_NavalSpawn",
	NPCSpawn = "WE_NPCSpawn",
	EventSpawn = "WE_EventSpawn",
	SupplyDrop = "WE_SupplyDrop",
	BankVault = "WE_BankVault",
	NPC = "WE_NPC",
	Vehicle = "WE_Vehicle",
	TutorialMarker = "WE_TutorialMarker",
	MoneyCollector = "WE_MoneyCollector",
	GateBarrier = "WE_GateBarrier",
	PlotOilPump = "WE_PlotOilPump",
	PremiumPad = "WE_PremiumPad",
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
	CombatStateUpdate = "CombatStateUpdate",
	CombatHitFeedback = "CombatHitFeedback",
	VehicleStateUpdate = "VehicleStateUpdate",
	TerritoryStateUpdate = "TerritoryStateUpdate",
	MissionStateUpdate = "MissionStateUpdate",
	-- Client → Server (request/action only — NEVER GiveCash/GiveXP/GiveWeapon)
	RequestPurchaseUpgrade = "RequestPurchaseUpgrade",
	RequestClaimDailyReward = "RequestClaimDailyReward",
	RequestSpawnVehicle = "RequestSpawnVehicle",
	RequestPurchaseVehicle = "RequestPurchaseVehicle",
	RequestDespawnVehicle = "RequestDespawnVehicle",
	RequestEquipWeapon = "RequestEquipWeapon",
	RequestPurchaseWeapon = "RequestPurchaseWeapon",
	RequestFire = "RequestFire",
	RequestReload = "RequestReload",
	RequestStartMission = "RequestStartMission",
	RequestClaimMission = "RequestClaimMission",
	RequestCaptureTerritory = "RequestCaptureTerritory",
	RequestAdminCommand = "RequestAdminCommand",
	RequestPurchaseDevProduct = "RequestPurchaseDevProduct",
	RequestPurchaseGamePass = "RequestPurchaseGamePass",
	RequestSkipTutorial = "RequestSkipTutorial",
	TutorialStateUpdate = "TutorialStateUpdate",
	-- Prestige / Clan / Battle Pass
	RequestPrestige = "RequestPrestige",
	PrestigeStateUpdate = "PrestigeStateUpdate",
	RequestCreateClan = "RequestCreateClan",
	RequestJoinClan = "RequestJoinClan",
	RequestLeaveClan = "RequestLeaveClan",
	ClanStateUpdate = "ClanStateUpdate",
	RequestClaimBattlePassReward = "RequestClaimBattlePassReward",
	BattlePassStateUpdate = "BattlePassStateUpdate",
	-- Soldiers / Season / Clan War
	RequestRecruitSoldiers = "RequestRecruitSoldiers",
	RequestDismissSoldiers = "RequestDismissSoldiers",
	SoldierStateUpdate = "SoldierStateUpdate",
	RequestSquadOrder = "RequestSquadOrder",
	SquadOrderStateUpdate = "SquadOrderStateUpdate",
	SeasonStateUpdate = "SeasonStateUpdate",
	RequestDeclareClanWar = "RequestDeclareClanWar",
	ClanWarStateUpdate = "ClanWarStateUpdate",
	RequestRedeemCode = "RequestRedeemCode",
	CodeStateUpdate = "CodeStateUpdate",
	NationColorUpdate = "NationColorUpdate",
	RequestClaimSpinner = "RequestClaimSpinner",
	SpinnerStateUpdate = "SpinnerStateUpdate",
	BankRaidStateUpdate = "BankRaidStateUpdate",
	-- Studio-only BUY smoke → client Output (Play Solo)
	StudioSmokeLog = "StudioSmokeLog",
	DeathShopOffer = "DeathShopOffer",
	StarterBundleOffer = "StarterBundleOffer",
	PromptPremiumPad = "PromptPremiumPad",
	GetPlayerState = "GetPlayerState",
}

Constants.DataStoreName = "WarEmpire_PlayerData_v1"
Constants.SessionStoreName = "WarEmpire_SessionLock_v1"
Constants.CURRENT_DATA_VERSION = 8

Constants.AutosaveIntervalSeconds = 60
-- Session lock: refresh often; steal if age >= TTL (rejoin after crash ~30–45s)
Constants.SessionLockTtlSeconds = 45
Constants.SessionLockRefreshSeconds = 15
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
	Health = Color3.fromRGB(200, 70, 70),
	Ammo = Color3.fromRGB(220, 200, 120),
	Text = Color3.fromRGB(235, 238, 242),
	Muted = Color3.fromRGB(150, 158, 170),
	-- Visual kits v2 UI
	Gunmetal = Color3.fromRGB(42, 48, 55),
	GunmetalLight = Color3.fromRGB(58, 66, 74),
	CategoryGround = Color3.fromRGB(90, 130, 80),
	CategoryAir = Color3.fromRGB(90, 160, 220),
	CategoryNaval = Color3.fromRGB(70, 180, 200),
	-- High-contrast (never pale yellow on sand/green)
	TextOnDark = Color3.fromRGB(245, 248, 252),
	TextDark = Color3.fromRGB(18, 20, 24),
	PlateDark = Color3.fromRGB(12, 14, 18),
	GoldBright = Color3.fromRGB(255, 210, 90),
	NeonAccent = Color3.fromRGB(80, 255, 160),
	Olive = Color3.fromRGB(72, 88, 58),
	Sand = Color3.fromRGB(196, 170, 120),
}

return Constants
