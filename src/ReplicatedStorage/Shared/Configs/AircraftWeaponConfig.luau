--!strict
--[[ Aircraft weapons (owner request, part 2): only combat aircraft are armed.

	WHO IS ARMED (explicit per vehicle id; every VehicleConfig "Air" id is in exactly one of Aircraft / Unarmed):
	  attack / gunship helicopters  nose gun + rockets
	  fighters                      gun + homing missiles
	  strike jets (stealth jet too) bombs
	  bombers                       bomb drop (a stick of bombs per press)
	  transport, cargo, medevac, AWACS, tanker, scout, utility, rescue, trainer, recon: unarmed

	SWITCH: WeaponsLive = false ships the feature dark. LiveFor(userId) is true while WeaponsLive is true, or for the
	owner's playtest account (AdminConfig.IsPlaytestOwner, UserId 470626172) so the owner can test it on live.
	The SERVER evaluates it (AirWeaponService) and mirrors it on the Player as WE_AirWeaponsLive (display only).

	SERVER (AirWeaponService): RequestVehicleFire { M = mount id (a Weapons key in this aircraft's loadout),
	D = aim direction (unit Vector3), I = input class (optional, assist class only) } — nothing else is read (never a
	target id). Validated: rate limit, live for this player, seated in the DriverSeat of a live registered aircraft,
	the mount in its loadout, magazine / reload, fire interval, finite direction (clamped into ArcDeg around the
	nose). Guns are server hitscan (+ the aircraft assist class in AimAssistConfig.Aircraft, line of sight); rockets,
	missiles and bombs are server ordnance (AirOrdnance: kinematic, one ray per step, gravity for bombs; missiles
	home only on a target the server chose, in LockConeDeg / LockRange with line of sight). Damage goes through
	CombatService.ApplyHit / ApplyRadiusDamage and VehicleHealth.ApplyRadiusDamage; gates and gate guards through
	GateDefenseService.ApplyDamage (via ApplyHit). Clan allies, novice-shielded players (and their vehicles and
	bases), raid-shielded / new-player-protected bases and protected vehicles are never damaged.

	WEAPON FIELDS
	  Kind            "Gun" | "Rocket" | "Missile" | "Bomb"
	  Label           2-4 letters on the fire button (no key names, no real-world names)
	  Damage          per hit (gun) / per projectile (direct + splash centre)
	  Class           VehicleCombatConfig.DamageClasses key (vehicle damage maths live in VehicleHealth)
	  VsInfantryMult  x against players, NPCs and gate guards
	  Rate            triggers per second (the server fires when now - last >= FireIntervalSlack / Rate)
	  Range           gun: ray length; ordnance: Speed x MaxSeconds (for the gate reach check)
	  SpreadDeg       gun cone
	  ArcDeg          the aim is clamped into this cone around the aircraft's nose (ignored by bombs)
	  Magazine        { Size, ReloadSeconds } — auto reload when empty
	  ShotsPerFire    projectiles per trigger (rocket pair, bomb stick); ShotIntervalSeconds between them
	  Splash / SplashMinMult  radius and edge multiplier (linear falloff)
	  Speed / MaxSeconds / GravityFactor  ordnance kinematics (GravityFactor x Workspace.Gravity)
	  TurnRateDeg / LockRange / LockConeDeg / ProximityFuse  missiles
	  InheritVelocity / DropSpeed / MaxInheritSpeed  bombs: start velocity = aircraft velocity x InheritVelocity
	                  (magnitude capped) + DropSpeed down
	  Hook            VisualAssetConfig.VehicleWeapons key (v79 vehicle-gun hooks): its Mount kit part is the muzzle
	                  / bay, and its allow-list must hold every aircraft that carries this weapon
	  MuzzleForward / MuzzleDrop  studs from the mount part (along the nose / down); MirrorX alternates pods L / R ]]

local AdminConfig = require(script.Parent.AdminConfig)

export type Magazine = { Size: number, ReloadSeconds: number }
export type WeaponDef = {
	Kind: string,
	Label: string,
	Damage: number,
	Class: string,
	VsInfantryMult: number,
	Rate: number,
	Range: number,
	SpreadDeg: number?,
	ArcDeg: number,
	Magazine: Magazine,
	ShotsPerFire: number?,
	ShotIntervalSeconds: number?,
	Splash: number?,
	SplashMinMult: number?,
	Speed: number?,
	MaxSeconds: number?,
	GravityFactor: number?,
	TurnRateDeg: number?,
	LockRange: number?,
	LockConeDeg: number?,
	ProximityFuse: number?,
	InheritVelocity: number?,
	DropSpeed: number?,
	MaxInheritSpeed: number?,
	Hook: string,
	MuzzleForward: number?,
	MuzzleDrop: number?,
	MirrorX: boolean?,
}

local AircraftWeaponConfig = {
	WeaponsLive = true, -- v138 (Code Bot, owner 2026-09-30 14:44): aircraft weapons ON for everyone (was dark except the owner's playtest account via LiveFor)

	RemoteRate = 12, -- RateLimitService "air_fire": 12/s, burst 16 (client sends <= 10/s: gun Rate cap)
	RemoteBurst = 16,
	FireIntervalSlack = 0.9, -- lag tolerance on the fire interval
	MountIdMaxLength = 32,
	LiveAttribute = "WE_AirWeaponsLive", -- Player attribute (server-written, display only)
	AmmoAttributePrefix = "WE_AW_", -- aircraft Model: WE_AW_<mount> = rounds left, WE_AW_<mount>_Rl = reload s (0 = none)
	HitIdPrefix = "V_", -- HitOpts.WeaponId = "V_<mount>" (the M6 vehicle-gun id form)
	GateReachSlack = 60, -- gate / guard hits: attacker within the weapon's Range + this (GateDefenseService)

	Ordnance = { StepHz = 20, MaxLivePerPlayer = 10, MaxLiveServer = 48, SpawnForwardStuds = 2 },
	Splash = { LosLiftStuds = 1.5 }, -- gate / guard splash line of sight starts this far above the blast

	Weapons = {
		-- attack helicopters: chin gun (follows the aim inside 35° of the nose)
		HeliNoseGun = {
			Kind = "Gun",
			Label = "GUN",
			Damage = 15,
			Class = "SmallArms",
			VsInfantryMult = 1,
			Rate = 8,
			Range = 220,
			SpreadDeg = 1.5,
			ArcDeg = 35,
			Magazine = { Size = 120, ReloadSeconds = 5 },
			Hook = "AirNoseGun",
			MuzzleForward = 1.5,
			MuzzleDrop = 1.2,
		},
		-- attack helicopters: rocket pods, a pair per trigger
		HeliRockets = {
			Kind = "Rocket",
			Label = "RKT",
			Damage = 110,
			Class = "Explosive",
			VsInfantryMult = 0.5,
			Rate = 1,
			Range = 308,
			ArcDeg = 12,
			Magazine = { Size = 8, ReloadSeconds = 8 },
			ShotsPerFire = 2,
			ShotIntervalSeconds = 0,
			Splash = 8,
			SplashMinMult = 0.3,
			Speed = 220,
			MaxSeconds = 1.4,
			GravityFactor = 0,
			Hook = "AirRocketPods",
			MuzzleForward = 1,
			MirrorX = true,
		},
		-- gunship: the same pods, a bigger magazine
		GunshipRockets = {
			Kind = "Rocket",
			Label = "RKT",
			Damage = 110,
			Class = "Explosive",
			VsInfantryMult = 0.5,
			Rate = 1,
			Range = 308,
			ArcDeg = 12,
			Magazine = { Size = 12, ReloadSeconds = 9 },
			ShotsPerFire = 2,
			ShotIntervalSeconds = 0,
			Splash = 8,
			SplashMinMult = 0.3,
			Speed = 220,
			MaxSeconds = 1.4,
			GravityFactor = 0,
			Hook = "AirRocketPods",
			MuzzleForward = 1,
			MirrorX = true,
		},
		-- fighters: nose cannon (aim with the nose: 8° cone)
		JetCannon = {
			Kind = "Gun",
			Label = "GUN",
			Damage = 14,
			Class = "SmallArms",
			VsInfantryMult = 1,
			Rate = 10,
			Range = 260,
			SpreadDeg = 1.2,
			ArcDeg = 8,
			Magazine = { Size = 150, ReloadSeconds = 6 },
			Hook = "AirJetCannon",
			MuzzleForward = 1,
			MuzzleDrop = 0,
		},
		-- fighters: homing missiles (the server picks the lock; none in the cone = it flies straight)
		JetMissiles = {
			Kind = "Missile",
			Label = "MSL",
			Damage = 200,
			Class = "Missile",
			VsInfantryMult = 0.5,
			Rate = 0.67, -- one every 1.5 s
			Range = 600,
			ArcDeg = 10,
			Magazine = { Size = 4, ReloadSeconds = 10 },
			ShotsPerFire = 1,
			Splash = 6,
			SplashMinMult = 0.3,
			Speed = 240,
			MaxSeconds = 2.5,
			GravityFactor = 0,
			TurnRateDeg = 90,
			LockRange = 400,
			LockConeDeg = 30,
			ProximityFuse = 4,
			Hook = "AirMissileRails",
			MuzzleForward = 0.5,
			MirrorX = true,
		},
		-- strike jets (and the stealth jet): single bombs
		StrikeBombs = {
			Kind = "Bomb",
			Label = "BOMB",
			Damage = 260,
			Class = "AntiVehicle",
			VsInfantryMult = 0.6,
			Rate = 1,
			Range = 700,
			ArcDeg = 180,
			Magazine = { Size = 4, ReloadSeconds = 12 },
			ShotsPerFire = 1,
			Splash = 14,
			SplashMinMult = 0.3,
			MaxSeconds = 8,
			GravityFactor = 1,
			InheritVelocity = 1,
			DropSpeed = 10,
			MaxInheritSpeed = 140,
			Hook = "AirStrikeBombs",
			MuzzleDrop = 1.5,
		},
		-- bombers: a stick of 4 bombs per press
		BomberStick = {
			Kind = "Bomb",
			Label = "BOMB",
			Damage = 220,
			Class = "AntiVehicle",
			VsInfantryMult = 0.6,
			Rate = 0.34, -- one stick every ~3 s
			Range = 700,
			ArcDeg = 180,
			Magazine = { Size = 12, ReloadSeconds = 15 },
			ShotsPerFire = 4,
			ShotIntervalSeconds = 0.25,
			Splash = 16,
			SplashMinMult = 0.3,
			MaxSeconds = 8,
			GravityFactor = 1,
			InheritVelocity = 1,
			DropSpeed = 8,
			MaxInheritSpeed = 120,
			Hook = "AirBombBay",
			MuzzleDrop = 1,
		},
	} :: { [string]: WeaponDef },

	-- slot order = fire-button order: [1] sits next to the ▼ button (thumb side), [2] to its left
	Loadouts = {
		AttackHeli = { "HeliNoseGun", "HeliRockets" },
		Gunship = { "HeliNoseGun", "GunshipRockets" },
		Fighter = { "JetCannon", "JetMissiles" },
		Strike = { "StrikeBombs" },
		Bomber = { "BomberStick" },
	} :: { [string]: { string } },

	Aircraft = {
		GunshipHeli = "Gunship",
		AttackHelicopter = "AttackHeli",
		EscortHeli = "AttackHeli",
		NightAttackHeli = "AttackHeli",
		StealthHeli = "AttackHeli", -- HeliAttack kit: armed like the attack helicopters (ASSUMPTIONS)
		FighterJet = "Fighter",
		InterceptorJet = "Fighter",
		LightFighter = "Fighter",
		StrikeJet = "Strike",
		CASJet = "Strike",
		StealthStrike = "Strike", -- the stealth jet: a strike jet by role (bombs)
		StrikeBomber = "Bomber",
		HeavyBomber = "Bomber",
		StrategicBomber = "Bomber",
	} :: { [string]: string },

	-- never armed (listed so a new aircraft must be placed on purpose; a test checks every Air id is in one list)
	Unarmed = {
		-- claude-bud PREMIUM: the Robux-only aircraft carry VehicleConfig.Premium weapons (PremiumWeaponService), not these
		PremiumSkylance = true,
		PremiumStormwing = true,
		LightScoutHeli = true,
		UtilityHeli = true,
		RescueHeli = true,
		TransportHeli = true,
		LightTransportHeli = true,
		HeavyLiftHeli = true,
		MedevacHeli = true,
		VTOLTransport = true,
		CargoPlane = true,
		AWACSPlane = true,
		TankerPlane = true,
		TrainerJet = true, -- a trainer is not a fighter (ASSUMPTIONS)
		ReconPlane = true, -- recon, not a fighter (ASSUMPTIONS)
	} :: { [string]: boolean },

	-- client fire buttons (AirWeaponsClient). REAL px: the ScreenGui has no UIScale (like WarEmpireVehicleHUD).
	-- Placed LEFT of the ▼ button, bottom-aligned with it, GapPx apart: inside the vehicle / combat reserve, never
	-- within GapPx of the jump button, never over EXIT, outside the thumbstick zone.
	Ui = {
		ButtonPx = 64, -- >= 44 real (48+ preferred)
		TabletButtonPx = 72, -- short side >= 500
		GapPx = 16,
		LabelTextPx = 20,
		AmmoTextPx = 16,
		HintTextPx = 14,
		RefreshHz = 10,
		MaxRequestHz = 10, -- every fire button together: at most this many requests / s (never above a weapon's Rate);
		-- with the 10 Hz VehicleDriveInput stream a pilot stays <= 20 remote sends / s
		Keys = { -- shown only when PreferredInput is keyboard / gamepad
			Pc = { "LMB", "R" },
			Pad = { "Y", "X" },
		},
	},
}

function AircraftWeaponConfig.LiveFor(userId: any): boolean
	if AircraftWeaponConfig.WeaponsLive == true then
		return true
	end
	return AdminConfig.IsPlaytestOwner(userId) == true
end

-- the aircraft's mount ids in button order, or nil (unarmed / not an aircraft)
function AircraftWeaponConfig.LoadoutFor(vehicleId: any): { string }?
	if typeof(vehicleId) ~= "string" then
		return nil
	end
	local cls = AircraftWeaponConfig.Aircraft[vehicleId]
	if cls == nil then
		return nil
	end
	return AircraftWeaponConfig.Loadouts[cls]
end

function AircraftWeaponConfig.Weapon(mountId: any): WeaponDef?
	if typeof(mountId) ~= "string" then
		return nil
	end
	return AircraftWeaponConfig.Weapons[mountId]
end

-- GateDefenseService reach for a hit id ("V_<mount>" of an aircraft weapon): Range + GateReachSlack, else nil
function AircraftWeaponConfig.HitReach(hitId: any): number?
	if typeof(hitId) ~= "string" then
		return nil
	end
	local p = AircraftWeaponConfig.HitIdPrefix
	if string.sub(hitId, 1, #p) ~= p then
		return nil
	end
	local w = AircraftWeaponConfig.Weapons[string.sub(hitId, #p + 1)]
	if w == nil then
		return nil
	end
	return w.Range + AircraftWeaponConfig.GateReachSlack
end

return AircraftWeaponConfig
