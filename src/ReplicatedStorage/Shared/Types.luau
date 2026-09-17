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
	Gold: number,
	Level: number,
	XP: number,
	Prestige: number,
	Soldiers: number,
	Vehicles: { [string]: boolean },
	Weapons: { [string]: boolean },
	EquippedWeapon: string?,
	Territories: { [string]: boolean },
	BaseUpgrades: BaseUpgrades,
	BasePlotId: number?,
	TutorialStep: number,
	TutorialComplete: boolean,
	DailyLogin: DailyLogin,
	Settings: PlayerSettings,
	Stats: PlayerStats,
	Achievements: { [string]: boolean },
	BattlePass: BattlePassProgress,
	ClanId: string?,
	FirstJoinUnix: number,
	LastJoinUnix: number,
}

export type EconomyUpdatePayload = {
	Cash: number,
	Gold: number,
}

export type XPUpdatePayload = {
	Level: number,
	XP: number,
	XPToNext: number,
}

export type BaseStatePayload = {
	PlotId: number?,
	Upgrades: BaseUpgrades,
	PassiveIncomePerTick: number,
}

export type PlayerStatePayload = {
	Cash: number,
	Gold: number,
	Level: number,
	XP: number,
	XPToNext: number,
	Prestige: number,
	Soldiers: number,
	Base: BaseStatePayload,
	TutorialComplete: boolean,
	Vehicles: { [string]: boolean },
	Weapons: { [string]: boolean },
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
