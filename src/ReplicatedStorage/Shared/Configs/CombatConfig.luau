--!strict
--[[
	Combat tuning — health, kill rewards, NPC pool/AI.
	Weapon stats live in WeaponConfig; never trust client damage amounts.
]]

export type NPCTypeDef = {
	Id: string,
	DisplayName: string,
	Health: number,
	Damage: number,
	FireRate: number,
	Range: number,
	WalkSpeed: number,
	AggroRange: number,
	CashReward: number,
	XPReward: number,
	Color: Color3,
}

local CombatConfig = {
	PlayerMaxHealth = 100,
	SpawnInvulnerabilitySeconds = 3, -- mirrors GameConfig; CombatService uses this

	PlayerKill = {
		Cash = 150,
		XP = 40,
	},

	DefaultNPCKill = {
		Cash = 50,
		XP = 15,
	},

	MaxOriginDeltaStuds = 12,
	MaxAimDirectionError = 0.001,
	HitPositionSlopStuds = 4,

	FireRemoteRate = 20,
	FireRemoteBurst = 28,
	ReloadRemoteRate = 2,
	ReloadRemoteBurst = 3,
	EquipRemoteRate = 3,
	EquipRemoteBurst = 4,
	PurchaseWeaponRate = 2,
	PurchaseWeaponBurst = 3,

	MaxActiveNPCs = 12,
	NPCRespawnSeconds = 18,
	NPCThinkInterval = 0.35,
	NPCAlsoSpawnNearTerritories = true,
	MaxTerritoryNPCSpawns = 4,

	NPCTypes = {
		Infantry = {
			Id = "Infantry",
			DisplayName = "Hostile Infantry",
			Health = 80,
			Damage = 10,
			FireRate = 2.5,
			Range = 70,
			WalkSpeed = 12,
			AggroRange = 90,
			CashReward = 50,
			XPReward = 15,
			Color = Color3.fromRGB(140, 55, 55),
		},
		HeavyInfantry = {
			Id = "HeavyInfantry",
			DisplayName = "Heavy Infantry",
			Health = 140,
			Damage = 16,
			FireRate = 1.6,
			Range = 85,
			WalkSpeed = 10,
			AggroRange = 100,
			CashReward = 90,
			XPReward = 28,
			Color = Color3.fromRGB(90, 40, 40),
		},
	} :: { [string]: NPCTypeDef },

	DefaultNPCType = "Infantry",
}

return CombatConfig
