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
	Direction: Vector3,
	Origin: Vector3?,
	TargetUserId: number?,
	TargetNpcId: string?,
	HitPosition: Vector3?,
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
