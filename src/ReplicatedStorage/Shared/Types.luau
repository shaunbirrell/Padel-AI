--!strict
--[[
	Shared type aliases for WAR EMPIRE.
]]

export type Currency = "Cash" | "Gold"

export type StructureId =
	"CommandCenter"
	| "Barracks"
	| "VehicleDepot"
	| "WeaponsFacility"
	| "Helipad"
	| "Airfield"
	| "DefensiveWalls"
	| "Watchtowers"
	| "Radar"
	| "ResearchLab"
	| "MissileDefense"
	| "PowerStation"
	| "Warehouse"
	| "SpecialForcesFacility"

export type BaseUpgrades = { [string]: number }

export type PlayerSettings = {
	MusicVolume: number,
	SFXVolume: number,
	ShowDamageNumbers: boolean,
	AutoSprint: boolean,
}

export type PlayerStats = {
	TotalCashEarned: number,
	TotalGoldEarned: number,
	UpgradesPurchased: number,
	VehiclesSpawned: number,
	MissionsCompleted: number,
	TerritoriesCaptured: number,
	Kills: number,
	Deaths: number,
	PlayTimeSeconds: number,
}

export type DailyLogin = {
	LastClaimDay: number, -- YYYYMMDD or 0
	Streak: number,
	LastClaimUnix: number,
}

export type DailyMissionProgress = {
	DayKey: number, -- YYYYMMDD UTC
	Progress: { [string]: number },
	Claimed: { [string]: boolean },
	ActiveTimed: { [string]: number }, -- missionId -> endsAt unix
}

export type BattlePassProgress = {
	SeasonId: string,
	XP: number,
	Level: number,
	Premium: boolean,
	ClaimedFree: { [string]: boolean },
	ClaimedPremium: { [string]: boolean },
}

-- v71 money (M2): optional profile blocks (ProfileSchema default-fill + sanitise; no DataVersion bump).
-- Nothing reads them yet; the nuke / premium vehicle / rebirth / offer workflows will.
export type NukeInFlight = {
	Kind: string, -- "Nuke" | "TacticalNuke"
	LaunchId: string,
	At: number, -- os.time() at launch
}

export type NukeStats = {
	Bought: number,
	Launched: number,
	PlayerKills: number,
	NpcKills: number,
	BestKills: number,
}

export type SiloProgress = {
	ProgressSeconds: number, -- online seconds toward the next Tactical Nuke
}

export type RebirthProgress = {
	ZonesSeen: { [string]: boolean }, -- zoneId -> the unlock celebration played
	LastRebirthUnix: number,
}

export type OfferStats = {
	Shown: number,
	LastShownUnix: number,
	Clicked: number,
	Dismissed: number,
}

export type MonetizationStats = {
	FirstPurchaseUnix: number,
	LastPurchaseUnix: number,
	Purchases: number,
	RobuxSpent: number, -- analytics / segmentation only; never shown to players
}

export type PlayerProfile = {
	DataVersion: number,
	Cash: number,
	PendingCash: number,
	Gold: number,
	Level: number,
	XP: number,
	Prestige: number,
	RebirthUnlocks: { [string]: boolean },
	Soldiers: number,
	NationColorId: string?,
	RedeemedCodes: { [string]: boolean },
	LastSpinnerClaimUnix: number,
	Vehicles: { [string]: boolean },
	Weapons: { [string]: boolean },
	EquippedWeapon: string?,
	Territories: { [string]: boolean },
	BaseUpgrades: BaseUpgrades,
	BasePlotId: number?,
	TutorialStep: number,
	TutorialComplete: boolean,
	DailyLogin: DailyLogin,
	DailyMissions: DailyMissionProgress,
	Settings: PlayerSettings,
	Stats: PlayerStats,
	Achievements: { [string]: boolean },
	BattlePass: BattlePassProgress,
	ClanId: string?,
	FirstJoinUnix: number,
	LastJoinUnix: number,
	ProcessedReceipts: { [string]: boolean }?,
	Entitlements: { [string]: boolean }?,
	OutpostIncomeStacks: number?,
	StarterBundleOffered: boolean?,
	AutoCollectOffered: boolean?,
	DoubleCashOffered: boolean?,
	VIPOffered: boolean?,
	SpeedBoostOffered: boolean?,
	CashMegaOffered: boolean?,
	-- v71 money (M2)
	Nukes: number?, -- paid (Robux) nukes, granted only in ProcessReceipt
	TacticalNukes: number?, -- silo / gift / reward nukes
	NukeInFlight: NukeInFlight?,
	NukeGiftGranted: boolean?,
	NukeStats: NukeStats?,
	Silo: SiloProgress?,
	PremiumVehicleCamo: { [string]: string }?, -- vehicleId -> camo id
	PremiumTrials: { [string]: number }?, -- vehicleId -> os.time() of the last free test drive
	Rebirth: RebirthProgress?,
	Offers: { [string]: OfferStats }?, -- offer key -> cadence counters (Offer Director)
	Monetization: MonetizationStats?,
	AnnouncePurchases: boolean?, -- M8 purchase ticker opt-out (true = announce)
	VipSupplyAt: number?, -- M8 daily VIP supply: os.time() of the last claim
}

export type EconomyUpdatePayload = {
	Cash: number,
	Gold: number,
	PendingCash: number?,
}

export type XPUpdatePayload = {
	Level: number,
	XP: number,
	XPToNext: number,
	HudGoal: string?,
	UnlockMessage: string?,
	LevelUp: boolean?, -- v37 celebration toast
}

export type BaseStatePayload = {
	PlotId: number?,
	Upgrades: BaseUpgrades,
	PassiveIncomePerTick: number,
}

export type PlayerStatePayload = {
	Cash: number,
	Gold: number,
	PendingCash: number?,
	Level: number,
	XP: number,
	XPToNext: number,
	Prestige: number,
	Soldiers: number,
	NationColorId: string?,
	TrainingIncomePerTick: number?,
	Base: BaseStatePayload,
	TutorialStep: number?,
	TutorialComplete: boolean,
	Vehicles: { [string]: boolean },
	Weapons: { [string]: boolean },
	EquippedWeapon: string?,
	DailyLogin: DailyLogin?,
	TerritoriesOwned: { [string]: boolean }?,
}

export type CombatStatePayload = {
	Health: number,
	MaxHealth: number,
	WeaponId: string?,
	Ammo: number,
	MagazineSize: number,
	Reloading: boolean,
	Alive: boolean,
}

export type CombatHitFeedbackPayload = {
	Kind: string, -- "Hit" | "Kill" | "Miss" | "Damaged" | "Death"
	Damage: number?,
	TargetName: string?,
	WeaponId: string?,
	IsHeadshot: boolean?,
	-- W2 additive (contracts §3.5; all optional, display only):
	Target: Instance?, -- Hit/Kill: victim character / NPC model / vehicle model (nil if streamed out)
	TargetKind: string?, -- "Player" | "NPC" | "Vehicle" | "Gate"
	Pos: Vector3?, -- Hit/Kill: world hit point (damage-number anchor)
	From: Vector3?, -- Damaged: attacker position (direction cue)
	Assist: boolean?, -- Hit/Kill: the server assist chose this target
	Splash: boolean?, -- aggregated area damage
}

export type VehicleStatePayload = {
	Owned: { [string]: boolean },
	ActiveVehicleId: string?,
	CooldownRemaining: number,
}

export type TerritoryEntryPayload = {
	Id: string,
	DisplayName: string,
	OwnerType: string,
	OwnerUserId: number,
	ClanId: string?,
	Progress: number, -- 0..1 capture progress toward CapturingUserId
	CapturingUserId: number,
	ProtectedUntil: number, -- unix
	BonusType: string,
	BonusValue: number,
	Contested: boolean,
}

export type TerritoryStatePayload = {
	Territories: { TerritoryEntryPayload },
	LocalCapture: {
		TerritoryId: string?,
		Progress: number,
		Capturing: boolean,
		Contested: boolean?,
		Protected: boolean?,
	}?,
	RadarReveal: boolean?,
	RadarRadius: number?,
}

export type MissionEntryPayload = {
	Id: string,
	DisplayName: string,
	Description: string,
	ObjectiveType: string,
	Progress: number,
	Target: number,
	Claimed: boolean,
	Complete: boolean,
	RewardCash: number,
	RewardXP: number,
	RewardGold: number,
}

export type MissionStatePayload = {
	DayKey: number,
	Daily: { MissionEntryPayload },
	DailyLogin: {
		Streak: number,
		CanClaim: boolean,
		NextDay: number,
		AlreadyClaimedToday: boolean,
	},
}

export type FireRequestPayload = {
	Direction: Vector3, -- camera-ray direction (after client aim help and recoil); finite, magnitude > 0.001
	Origin: Vector3?, -- the point on the camera ray closest to the head; server rule: <= MaxOriginDeltaStuds of the root
	TargetUserId: number?, -- the client ray's target: a HINT for the P0-7 lag tolerance only; never picks an assist target
	TargetNpcId: string?, -- same
	HitPosition: Vector3?, -- the client ray's end: telemetry only (the fire_hitpos_oor soft strike)
	Input: string?, -- W2: "Touch" | "Gamepad" | "KeyboardAndMouse" (<= 16 chars; anything else is ignored, no strike)
}

-- W2 (contracts §2.1): one WeaponFx UnreliableRemoteEvent table per event, sent with FireClient to each recipient.
export type WeaponFxPayload = {
	S: number, -- shooter UserId; 0 = NPC
	W: string, -- WeaponConfig id; "NPC" for NPC rifles
	O: Vector3, -- server-validated origin (NPC: its eye point)
	P: Vector3, -- where the shot landed (exact hit point, target torso, or O + dir x range on a miss); "L": equals O
	K: string, -- "P" player / "N" NPC / "V" vehicle / "G" gate / "W" scenery / "M" miss / "L" launch / "X" explosion
	R: boolean?, -- true on "L"/"X" (projectile events); nil for bullets
	I: number?, -- projectile serial: "L" and "X" of one projectile share it
	V: Vector3?, -- "L": initial velocity (client simulates O + V t + 1/2 g t^2, g = Gravity x GravityFactor)
	T: number?, -- "L": Projectile.MaxSeconds (the client removes the visual at T + 0.5 s if "X" never arrives)
	D: number?, -- "X": splash radius (explosion size + camera shake range)
}

export type PurchaseUpgradeRequest = {
	StructureId: string,
}

export type PurchaseUpgradeResult = {
	Ok: boolean,
	Error: string?,
	NewLevel: number?,
	Cash: number?,
	Gold: number?,
}

return {}
