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
	Water = "WE_Water", -- v69: water surface parts (top face = water level); boats may only move over these
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
Constants.RemotesFolderName = "WE_Remotes" -- v60: server-only; never Rojo empty Remotes
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
	PurchaseResult = "PurchaseResult", -- v62: server always replies Ok/Err after buy
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
	RequestAnalyticsEvent = "RequestAnalyticsEvent", -- claude-bud JOB 24 §10: a whitelisted UI event (AnalyticsService)
	BuildingTip = "BuildingTip", -- claude-bud JOB 24 §5: server -> client "NEW BUILDING" card { Id }
	RequestTipSetting = "RequestTipSetting", -- claude-bud JOB 24 §5: Settings -> TIPS on / off
	RequestTipsReplay = "RequestTipsReplay", -- claude-bud JOB 24 §5: Settings -> show my building tips again
	RequestBuyArmour = "RequestBuyArmour", -- claude-bud JOB 26: buy the next armour tier (ArmourService)
	RequestArmourLook = "RequestArmourLook", -- claude-bud JOB 26: hide / show the armour look
	RequestNotifOptInResult = "RequestNotifOptInResult", -- claude-bud JOB 29: the notification opt-in prompt result
	CodeStateUpdate = "CodeStateUpdate",
	-- Code Bot v102: RemoteFunction. Client -> server (code: string) -> { Result = "Success" | "AlreadyUsed" | "Invalid"
	-- | "Expired" | "RateLimited" | "NotReady", Message: string }. Server validates + rate-limits (CodesService).
	RedeemCode = "RedeemCode",
	RequestMapLive = "RequestMapLive", -- claude-bud JOB 30: RemoteFunction, the world map's live markers (MapService)
	NationColorUpdate = "NationColorUpdate",
	-- Nations (cosmetic country flag): client -> server Types.NationRequestPayload { Action = "pick" | "later", Id?,
	-- Source }. Replies go to that player only on NationColorUpdate. The server validates everything (rate limit,
	-- NationConfig.Get) and grants nothing but the cosmetic choice.
	RequestSetNation = "RequestSetNation",
	RequestClaimSpinner = "RequestClaimSpinner",
	SpinnerStateUpdate = "SpinnerStateUpdate",
	BankRaidStateUpdate = "BankRaidStateUpdate",
	-- Studio-only BUY smoke → client Output (Play Solo)
	StudioSmokeLog = "StudioSmokeLog",
	DeathShopOffer = "DeathShopOffer",
	StarterBundleOffer = "StarterBundleOffer",
	AutoCollectOffer = "AutoCollectOffer",
	DoubleCashOffer = "DoubleCashOffer",
	VIPOffer = "VIPOffer",
	SpeedBoostOffer = "SpeedBoostOffer",
	CashMegaOffer = "CashMegaOffer",
	AtmRaidStateUpdate = "AtmRaidStateUpdate",
	PromptPremiumPad = "PromptPremiumPad",
	-- v69: Research Lab upgrades, Command Center missile strikes, vehicle drive input
	RequestResearch = "RequestResearch",
	ResearchStateUpdate = "ResearchStateUpdate",
	RequestMissileStrike = "RequestMissileStrike",
	MissileStrikeStateUpdate = "MissileStrikeStateUpdate",
	MissileStrikeFx = "MissileStrikeFx",
	VehicleDriveInput = "VehicleDriveInput",
	-- v71 money (M2): created now, used by later workflows (nothing fires or listens to them yet).
	-- Nuke (M5; own Fx remote, J17)
	RequestNukeLaunch = "RequestNukeLaunch",
	RequestNukeState = "RequestNukeState",
	NukeStateUpdate = "NukeStateUpdate",
	NukeFx = "NukeFx",
	-- Premium / vehicle weapons (M6). VehicleWeaponFx is an UnreliableRemoteEvent (RemoteSetup UNRELIABLE list).
	RequestVehicleFire = "RequestVehicleFire",
	VehicleWeaponFx = "VehicleWeaponFx",
	RequestVehicleCamo = "RequestVehicleCamo",
	RequestPremiumTrial = "RequestPremiumTrial",
	-- Rebirth expansion (M7). Not "SupplyDrop": that name belongs to SupplyDropService.
	RebirthStateUpdate = "RebirthStateUpdate",
	RequestRebirthState = "RequestRebirthState",
	ArtilleryFx = "ArtilleryFx",
	DroneCrateFx = "DroneCrateFx",
	-- Offer Director (M3) and M8 (purchase ticker, shortfall chip)
	OfferShow = "OfferShow",
	OfferResult = "OfferResult",
	PurchaseAnnounce = "PurchaseAnnounce",
	ShortfallChip = "ShortfallChip",
	-- W2 Combat Core: WeaponFx is an UnreliableRemoteEvent (RemoteSetup UNRELIABLE list); RequestSetDrawn a RemoteEvent
	WeaponFx = "WeaponFx",
	RequestSetDrawn = "RequestSetDrawn",
	GetPlayerState = "GetPlayerState",
	-- W3 step 2 Phase B, Jobs ("Ops"; OpsConfig.Enabled gates every sender). Server -> client only: there is NO Ops
	-- client -> server remote (every job action is a server ProximityPrompt). Payload types: OpsConfig exports.
	OpsState = "OpsState", -- RemoteEvent, per player: OpsStatePayload (Full on join + every 60 s, deltas <= 2 Hz)
	OpsProgress = "OpsProgress", -- RemoteEvent, per player: OpsProgressPayload (4 Hz, only inside a job zone)
	OpsPing = "OpsPing", -- UnreliableRemoteEvent (RemoteSetup UNRELIABLE list): OpsPingPayload, every 10 s per carrier
	-- droppers v1b: UnreliableRemoteEvent (RemoteSetup UNRELIABLE list), server -> the grabber only, one packet per
	-- paid plate grab: (dropPoint: Vector3, amount: number, left: number, eta: number). Cosmetic: a lost packet loses
	-- the effect, never money. Nobody listens on the server (no OnServerEvent).
	DropperFx = "DropperFx",
	-- claude-bud JOB 4/5: server -> one client, (kind: string, data: table): feature cues (airdrop marker, plaza bounty,
	-- daily streak, offers). Owner-only features fire it only to players the feature is live for. No OnServerEvent.
	FeaturePush = "FeaturePush",
	-- claude-bud JOB 5c: client -> server, no args: use one Plaza Airstrike charge (the server checks everything)
	RequestPlazaAirstrike = "RequestPlazaAirstrike",
	-- claude-bud JOB 5e: client -> server, no args: claim the one-time group-join reward (the server checks the group)
	RequestGroupReward = "RequestGroupReward",
	-- claude-bud PREMIUM: client -> server (action "Fire" | "Missile", aim: Vector3); PremiumWeaponService checks all
	RequestPremiumWeapon = "RequestPremiumWeapon",
	RequestBoardSetting = "RequestBoardSetting", -- claude-bud BOARDS: client -> server, the Supporter board opt-out (boolean)
	-- claude-bud PREMIUM: UnreliableRemoteEvent (RemoteSetup UNRELIABLE list), server -> all clients: gun / missile / boom fx
	PremiumWeaponFx = "PremiumWeaponFx",
}

Constants.DataStoreName = "WarEmpire_PlayerData_v2" -- v55: intentional bump; fresh CreateDefault + StartingCash (kills stuck $0 v1 saves)
Constants.SessionStoreName = "WarEmpire_SessionLock_v1"
Constants.CURRENT_DATA_VERSION = 8

Constants.AutosaveIntervalSeconds = 60
-- Session lock: refresh often; steal if age >= TTL (rejoin after crash ~30–45s)
Constants.SessionLockTtlSeconds = 45
Constants.SessionLockRefreshSeconds = 15
Constants.DataStoreRetries = 3
Constants.DataStoreRetryDelay = 1.5

Constants.MaxBasePlots = 10 -- claude-bud JOB 21: = BaseConfig.MaxPlots (tools/checks/claude_bud_plots.py)
Constants.PassiveIncomeTickSeconds = 5

Constants.Colors = {
	Background = Color3.fromRGB(18, 20, 24),
	Panel = Color3.fromRGB(28, 32, 38),
	Accent = Color3.fromRGB(70, 130, 80),
	Cash = Color3.fromRGB(130, 255, 170), -- v36 high-contrast cash (not yellow)
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
