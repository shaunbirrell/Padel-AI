--!strict
--[[ v71 money (M2): vehicle weapon mounts (premium_vehicles.md §5; plan §2.2).
	Server: VehicleWeaponService (M6) validates RequestVehicleFire {M = mountId, D = direction} — nothing else is
	accepted — computes origin, spread, range, heat / magazine and clamps the aim to the arc; a shot more than
	ArcRejectDeg outside the arc is rejected (soft strike "vfire_arc"). Fx go out on VehicleWeaponFx, an
	UnreliableRemoteEvent, capped at FxMaxPerSecond per mount.
	Config only: nothing reads this file yet.

	Mount fields:
	  Damage / Rate (shots per s) / Range (studs) / SpreadDeg / Class (VehicleCombatConfig.DamageClasses)
	  VsInfantryMult  × against players and NPCs (the SiegeCannon is an anti-armor gun: 240 × 0.4 = 96 direct)
	  Splash / SplashMinMult  radius and edge multiplier (linear falloff)
	  Heat = { PerShot, CoolPerSec, LockoutSeconds }  or  Magazine = { Size, ReloadSeconds }
	  ShotsPerFire    projectiles per trigger (RocketPods fire a pair)
	  YawLimitDeg / ArcCenterYawDeg / PitchMinDeg / PitchMaxDeg  arc in the hull frame
	  MuzzleForward   studs from the mount pivot to the muzzle
	  FxKind          "MG" | "Cannon" | "Rocket"
	  SquadCrewMult   damage × when a squad unit crews it (nil = driver / pilot gun, squad never crews it) ]]

export type HeatDef = { PerShot: number, CoolPerSec: number, LockoutSeconds: number }
export type MagazineDef = { Size: number, ReloadSeconds: number }

export type MountDef = {
	DisplayName: string,
	Damage: number,
	Rate: number,
	Range: number,
	SpreadDeg: number,
	Class: string,
	VsInfantryMult: number,
	Splash: number?,
	SplashMinMult: number?,
	Heat: HeatDef?,
	Magazine: MagazineDef?,
	ShotsPerFire: number?,
	YawLimitDeg: number,
	ArcCenterYawDeg: number?,
	PitchMinDeg: number,
	PitchMaxDeg: number,
	MuzzleForward: number,
	FxKind: string,
	SquadCrewMult: number?,
}

local LIGHT_HEAT: HeatDef = { PerShot = 0.03, CoolPerSec = 0.30, LockoutSeconds = 2.5 }
local HEAVY_HEAT: HeatDef = { PerShot = 0.035, CoolPerSec = 0.28, LockoutSeconds = 3 }

local VehicleWeaponConfig = {
	RemoteRate = 14, -- RateLimitService "veh_fire": 14/s, burst 20
	RemoteBurst = 20,
	FireIntervalSlack = 0.9, -- fire when now - LastFire >= FireIntervalSlack / Rate (lag tolerance)
	ArcRejectDeg = 25,
	FxMaxPerSecond = 10, -- VehicleWeaponFx per mount (UnreliableRemoteEvent)
	AimAttrHz = 10, -- model attribute WE_Aim_<mountId> = Vector2(yawDeg, pitchDeg)
	MountIdMaxLength = 32,
	LastHitAttrSeconds = 3, -- WE_LastHitVehicle / WE_LastHitAt window read by the killed_by offer
	FxRemote = "VehicleWeaponFx",

	Mounts = {
		-- Razorfang GT Interceptor: driver-fired
		TwinHoodMG = {
			DisplayName = "Twin Hood MGs",
			Damage = 12,
			Rate = 10,
			Range = 170,
			SpreadDeg = 1.6,
			Class = "SmallArms",
			VsInfantryMult = 1,
			Heat = LIGHT_HEAT,
			YawLimitDeg = 10,
			PitchMinDeg = -6,
			PitchMaxDeg = 12,
			MuzzleForward = 2.4,
			FxKind = "MG",
		},
		-- Bastion Gun Truck: roof turret (player gunner, or a squad unit at ×0.5)
		RoofHMG = {
			DisplayName = "Roof HMG",
			Damage = 18,
			Rate = 7,
			Range = 220,
			SpreadDeg = 1.4,
			Class = "SmallArms",
			VsInfantryMult = 1,
			Heat = HEAVY_HEAT,
			YawLimitDeg = 180,
			PitchMinDeg = -12,
			PitchMaxDeg = 50,
			MuzzleForward = 2.6,
			FxKind = "MG",
			SquadCrewMult = 0.5,
		},
		-- Warlord Siege Tank: driver-fired anti-armor cannon (Rate 0.3 = one shell every 3.33 s)
		SiegeCannon = {
			DisplayName = "Siege Cannon",
			Damage = 240,
			Rate = 0.3,
			Range = 320,
			SpreadDeg = 0.4,
			Class = "AntiVehicle",
			VsInfantryMult = 0.4,
			Splash = 9,
			SplashMinMult = 0.25,
			YawLimitDeg = 180,
			PitchMinDeg = -8,
			PitchMaxDeg = 20,
			MuzzleForward = 6.0,
			FxKind = "Cannon",
		},
		-- Warlord Siege Tank: commander hatch MG
		CommanderMG = {
			DisplayName = "Commander MG",
			Damage = 16,
			Rate = 7,
			Range = 200,
			SpreadDeg = 1.5,
			Class = "SmallArms",
			VsInfantryMult = 1,
			Heat = HEAVY_HEAT,
			YawLimitDeg = 180,
			PitchMinDeg = -12,
			PitchMaxDeg = 50,
			MuzzleForward = 1.8,
			FxKind = "MG",
			SquadCrewMult = 0.5,
		},
		-- Stormwing Gunship (M6b): pilot rocket pods, 110 × 2 per salvo
		RocketPods = {
			DisplayName = "Rocket Pods",
			Damage = 110,
			Rate = 1.0,
			Range = 260,
			SpreadDeg = 1.5,
			Class = "Explosive",
			VsInfantryMult = 0.5,
			Splash = 7,
			SplashMinMult = 0.3,
			Magazine = { Size = 8, ReloadSeconds = 6 },
			ShotsPerFire = 2,
			YawLimitDeg = 5,
			PitchMinDeg = -35,
			PitchMaxDeg = 5,
			MuzzleForward = 1.5,
			FxKind = "Rocket",
		},
		-- Stormwing Gunship (M6b): chin gun
		ChinGun = {
			DisplayName = "Chin Gun",
			Damage = 15,
			Rate = 9,
			Range = 210,
			SpreadDeg = 1.8,
			Class = "SmallArms",
			VsInfantryMult = 1,
			Heat = LIGHT_HEAT,
			YawLimitDeg = 100,
			PitchMinDeg = -60,
			PitchMaxDeg = 10,
			MuzzleForward = 1.2,
			FxKind = "MG",
			SquadCrewMult = 0.5,
		},
		-- Stormwing Gunship (M6b): door guns; the kit gives two seats with mirrored ArcCenterYawDeg (+90 / -90)
		DoorMG = {
			DisplayName = "Door MG",
			Damage = 16,
			Rate = 8,
			Range = 200,
			SpreadDeg = 1.6,
			Class = "SmallArms",
			VsInfantryMult = 1,
			Heat = HEAVY_HEAT,
			YawLimitDeg = 70,
			ArcCenterYawDeg = 90,
			PitchMinDeg = -70,
			PitchMaxDeg = 15,
			MuzzleForward = 1.4,
			FxKind = "MG",
			SquadCrewMult = 0.5,
		},
		-- Tidebreaker Assault Boat (M6b): bow twin MG
		BowTwinMG = {
			DisplayName = "Bow Twin MG",
			Damage = 14,
			Rate = 10,
			Range = 190,
			SpreadDeg = 1.8,
			Class = "SmallArms",
			VsInfantryMult = 1,
			Heat = LIGHT_HEAT,
			YawLimitDeg = 120,
			PitchMinDeg = -10,
			PitchMaxDeg = 35,
			MuzzleForward = 1.6,
			FxKind = "MG",
			SquadCrewMult = 0.5,
		},
		-- Cash ArmedJeep ("Armed 4x4"; free armed answer, plan §2.2): gunner-seat HMG. JEEP-2: the key stays "JeepHMG"
		-- (mount ids travel in RequestVehicleFire / WE_Aim_<mountId>); only the name players see changed.
		JeepHMG = {
			DisplayName = "4x4 HMG",
			Damage = 12,
			Rate = 6,
			Range = 180,
			SpreadDeg = 1.6,
			Class = "SmallArms",
			VsInfantryMult = 1,
			Heat = { PerShot = 0.04, CoolPerSec = 0.28, LockoutSeconds = 3 },
			YawLimitDeg = 180,
			PitchMinDeg = -12,
			PitchMaxDeg = 45,
			MuzzleForward = 2.0,
			FxKind = "MG",
			SquadCrewMult = 0.5,
		},
	} :: { [string]: MountDef },

	-- Cash vehicles with a mounted gun (premium vehicles list theirs in VehicleConfig Premium.Weapons, M6)
	CashVehicleMounts = {
		ArmedJeep = { "JeepHMG" },
	} :: { [string]: { string } },
}

return VehicleWeaponConfig
