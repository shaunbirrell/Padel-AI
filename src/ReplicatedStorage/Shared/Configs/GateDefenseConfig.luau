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
	AutoGunYawDeg = 15, -- idle toe-in toward the approach centre line (inside and outside posts)

	-- Owner phone feedback 2026-09-27 ("The turrets should be outside the gate"): each AutoGun nest (gun, painted
	-- marker ring, sandbags) stands OUTSIDE the main gate, one each side of the approach, its back to the wall, facing
	-- out (toed in by AutoGunYawDeg). Gate-local: nest centre AutoGunOutsideFlankX from the gate centre along the wall
	-- (the opening is 10 wide, ±5; a 30° approach of the widest car body passes between the nests) and
	-- AutoGunOutsideWallGap studs out from the wall's OUTER face (the wall is 3.5-6.3 thick by level: read from the
	-- built wall, never assumed). The guards stay INSIDE (RaidConfig.Defense.GuardPostInsideStuds): they are the only
	-- defense that chases an intruder to the ATM, and a closed gate would lock them out. false = the v69 posts
	-- AutoGunInsideStuds inside the gate (rollback).
	AutoGunOutside = true,
	AutoGunOutsideFlankX = 16,
	AutoGunOutsideWallGap = 4.5, -- the sandbags behind a gun stay clear of the wall even at their full 2.2-stud length
	-- Fix 2 (review): an OUTSIDE gun engages and hits out to min(Levels[n].TurretRange, AutoGunOutsideMaxRange) from
	-- the gun. Posts stand about 7.7 studs out and 16 to the side, so at 100 the guns reach about 106 studs out on the
	-- approach centre line. A player's gun damages the gate only from within GateHitMaxDistance of the barrier part's
	-- centre (GateDefenseService.ApplyDamage; the Starter Rifle ray itself reaches 124 = Range 120 + HitPositionSlopStuds
	-- 4, so 120 is the real limit). A raider with the default loadout therefore keeps a band about 106-120 studs out
	-- (about 13.5 studs on the centre line, wider off the axis) to siege the gate without being shot, at L4 and L5
	-- alike. Uncapped, L5 (115) left almost nothing. Keep it <= GateHitMaxDistance - 20. Inside posts (rollback) keep
	-- TurretRange. The hit chance falls to TurretHitChanceFar at this reach.
	AutoGunOutsideMaxRange = 100,
	-- A player's (non-aircraft) hit on the gate barrier counts only when their root is within this many studs of the
	-- barrier part's centre (was a literal 120 in ApplyDamage). Aircraft weapons may extend it (AircraftWeaponConfig.HitReach).
	GateHitMaxDistance = 120,
	-- Target pick: the first enemy the gun can SEE, at most this many line-of-sight rays per gun per think (5 Hz);
	-- nobody in sight = no turn, no shot. Order: enemies on the gun's side of the wall first (outside posts: outside
	-- the plot), each side in priority order (raider at the ATM, anyone near the ATM, the nearest). All rays but the
	-- last go to the top of that list; the last ray probes the rest in turn and stays on an enemy it can see, so
	-- enemies the gun cannot see never use up every ray (a clan crowding the ATM or hiding behind cover).
	TurretLosChecksPerThink = 3,
	-- Every AutoGun shot, hit or miss, sends one tracer + shot sound through the W2 WeaponFx path (CombatFx.Bullet:
	-- UnreliableRemoteEvent, per-shooter and per-recipient token buckets). A gun fires at most once per think (5 Hz),
	-- so two guns add <= 10 events/s to a player near the gate. A miss lands MissOffsetMin..Max studs beside the
	-- target so it reads on a phone. false = silent guns (v69).
	TurretShotFx = true,
	TurretShotFxMuzzleStuds = 2.5, -- tracer starts this far along the aim from the gun's aim part (about the barrel tip)
	TurretShotFxMissOffsetMin = 2,
	TurretShotFxMissOffsetMax = 4,
	-- CLAUDE.md combat fairness: an AutoGun shot needs line of sight AND rolls a hit chance (every shot used to hit):
	-- TurretHitChanceNear at or inside TurretHitNearStuds, falling linearly to TurretHitChanceFar at the gun's reach
	-- (the level's TurretRange, capped by AutoGunOutsideMaxRange for outside posts; the CombatFairnessConfig NPC curve,
	-- 0.75 → 0.30). A miss still spends the shot.
	TurretHitNearStuds = 20,
	TurretHitChanceNear = 0.75,
	TurretHitChanceFar = 0.30,

	-- Catalog ScaleTo longest-axis targets (studs)
	AutoGunLongAxisStuds = 5.5, -- 4–6
	SandbagNestDiameterStuds = 8,

	-- Walls level when AutoGuns appear (Design L1)
	AutoGunMinWallsLevel = 4,

	-- Combat — cover gate → MoneyCollector ATM approach (plot ~200 pad)
	DefaultAggroRange = 95,
	ProtectCollectorRadius = 42,
	RequireLineOfSight = true,
	-- A line-of-sight ray is this long at most; a target farther away is NOT in sight (ownerfb/gate fix 1: the ray used
	-- to be cut here and read as clear, so at L5 a target 110-115 studs out behind cover was shot through it). Keep it
	-- >= every Levels[n].TurretRange, AggroRange and ShootRange.
	LosMaxDistance = 125,
	DamageCooldownGlobal = 0.08,
	-- Guards and AutoGuns ignore a player whose save has not loaded yet, and for this many seconds after each
	-- character spawn and after the save loads. Every PlayerSpawn pad sits at somebody's gate: a new player used
	-- to be shot there before BaseService could move them to their own plot. Respawns are moved home at once.
	-- The grace ends early for a player holding an ATM raid or hitting the gate / a guard.
	SpawnGraceSeconds = 4,
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
	-- v71 (HUD v70 spec §4.2): one owner Warn when the base is fought over — the defenses hit an enemy, or an enemy
	-- hits the gate / a guard — at most once per BaseUnderAttackCooldown per plot. The client shows it in the Alert
	-- slot (HudConfig.Toast.Reroute "^BASE UNDER ATTACK"). Was a per-hit "DEF HIT · name (−HP)" toast every 1.2 s.
	BaseUnderAttackToast = "BASE UNDER ATTACK!",
	BaseUnderAttackCooldown = 60,
	-- gate HP bar (one stud-scaled bar centred over the gate; shown only while damaged, breached, down or raided)
	GateBar = { Studs = Vector2.new(6, 1.1), MaxDistance = 40, HeightAbove = 1.2 },
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
