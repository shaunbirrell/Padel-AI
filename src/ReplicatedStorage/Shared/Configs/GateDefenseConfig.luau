--!strict
--[[
	Gate door defense — Design Bot GATE_DEFENSE_WIRE.
	Tied to DefensiveWalls level. Recreated on join from walls level (no exotic persist).

	Design silhouette:
	  Walls L1–L3 = Design L0 (2 Guards patrol ±6)
	  Walls L4–L5 = Design L1 (Machine Gun Nest AutoGuns + keep Guards manned nest)
	  Design L2 elevated tower IDs are NOT used on door flanks.
]]

export type LevelStats = {
	GuardHealth: number,
	GuardDamage: number,
	GuardFireRate: number,
	GuardWalkSpeed: number,
	AggroRange: number,
	ShootRange: number,
	UseTurrets: boolean,
	TurretDamage: number,
	TurretFireRate: number,
	TurretRange: number,
	WeaponLabel: string,
	DesignTier: string, -- "L0" | "L1"
}

local GateDefenseConfig = {
	Enabled = true,
	MinWallsLevel = 1,
	GuardsPerGate = 2,
	VisualKind = "GateGuard", -- Characters.GateGuard / Guard → 16134469614

	-- Design Bot placement (gate local space)
	GuardFlankX = 6,
	GuardForwardZ = 2,
	PatrolHalfSpanStuds = 6, -- ±6 along gate line
	AutoGunFlankX = 7,
	AutoGunForwardZ = 1,
	AutoGunYawDeg = 15,

	-- Catalog ScaleTo longest-axis targets (studs)
	AutoGunLongAxisStuds = 5.5, -- 4–6
	SandbagNestDiameterStuds = 8,

	-- Walls level when AutoGuns appear (Design L1)
	AutoGunMinWallsLevel = 4,

	-- Combat — cover gate → MoneyCollector ATM approach (plot ~200 pad)
	DefaultAggroRange = 95,
	ProtectCollectorRadius = 42,
	RequireLineOfSight = true,
	LosMaxDistance = 110,
	DamageCooldownGlobal = 0.08,
	GuardRespawnSeconds = 12,
	PatrolIdleSeconds = 1.4,

	Levels = {
		[1] = {
			GuardHealth = 140,
			GuardDamage = 14,
			GuardFireRate = 1.4,
			GuardWalkSpeed = 11,
			AggroRange = 95,
			ShootRange = 70,
			UseTurrets = false,
			TurretDamage = 0,
			TurretFireRate = 0,
			TurretRange = 0,
			WeaponLabel = "Rifle",
			DesignTier = "L0",
		},
		[2] = {
			GuardHealth = 190,
			GuardDamage = 18,
			GuardFireRate = 2.0,
			GuardWalkSpeed = 12,
			AggroRange = 100,
			ShootRange = 75,
			UseTurrets = false,
			TurretDamage = 0,
			TurretFireRate = 0,
			TurretRange = 0,
			WeaponLabel = "Rifle+",
			DesignTier = "L0",
		},
		[3] = {
			GuardHealth = 230,
			GuardDamage = 16,
			GuardFireRate = 4.0,
			GuardWalkSpeed = 13,
			AggroRange = 105,
			ShootRange = 68,
			UseTurrets = false,
			TurretDamage = 0,
			TurretFireRate = 0,
			TurretRange = 0,
			WeaponLabel = "SMG",
			DesignTier = "L0",
		},
		[4] = {
			GuardHealth = 260,
			GuardDamage = 18,
			GuardFireRate = 4.5,
			GuardWalkSpeed = 13,
			AggroRange = 110,
			ShootRange = 72,
			UseTurrets = true,
			TurretDamage = 22,
			TurretFireRate = 6.0,
			TurretRange = 100,
			WeaponLabel = "SMG+HMG",
			DesignTier = "L1",
		},
		[5] = {
			GuardHealth = 300,
			GuardDamage = 20,
			GuardFireRate = 5.0,
			GuardWalkSpeed = 14,
			AggroRange = 120,
			ShootRange = 78,
			UseTurrets = true,
			TurretDamage = 28,
			TurretFireRate = 8.0,
			TurretRange = 115,
			WeaponLabel = "AutoGuns",
			DesignTier = "L1",
		},
	} :: { [number]: LevelStats },

	-- Siegeable gate barrier (HP). Spawned by GateDefenseService — does not edit StructureKitBuilder ScaleTo.
	GateMaxHealthByWallsLevel = {
		[1] = 800,
		[2] = 1200,
		[3] = 1800,
		[4] = 2600,
		[5] = 3600,
	},
	GateRegenPerSecond = 1.5, -- slow regen while intact / after rebuild
	GateRebuildSeconds = 50,
	GateRepairCashCost = 750, -- owner Collect repair while breached
	GateBreachToast = "⚠ BREACHED — gate open! Repair or wait rebuild",
	GateRepairedToast = "Gate repaired",
	-- v38: owner feedback when guards/AutoGuns land a hit on an enemy player
	GateHitOwnerToast = "DEF HIT · %s (−%d HP)",
	GateHitOwnerToastCooldown = 1.2,
	GateBarrierThickness = 1.6,
	GateBarrierHeight = 9,
	GateClearStuds = 10, -- match StructureKitBuilder GATE_CLEAR
	GateDamageTag = "WE_GateBarrier",
	GateDamageToolAttribute = "WE_Weapon", -- tool/tag validation
	AllowTroopGateDamage = true,

}

function GateDefenseConfig.GetLevelStats(wallsLevel: number): LevelStats?
	local lv = math.clamp(math.floor(wallsLevel), 0, 5)
	if lv < (GateDefenseConfig.MinWallsLevel or 1) then
		return nil
	end
	return GateDefenseConfig.Levels[lv] or GateDefenseConfig.Levels[5]
end

return GateDefenseConfig
