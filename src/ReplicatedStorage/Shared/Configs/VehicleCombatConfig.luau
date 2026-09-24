--!strict
--[[ v71 money (M2): vehicle HP, damage classes, destruction, regen, seat rules (premium_vehicles.md §3–§5).
	Server: VehicleHealth (W2 / M4: Server/Modules/VehicleHealth.luau) and CombatService.ApplyHit; VehicleWeaponService
	(M6). Client: VehicleCombatClient reads Ui (HP bars) for display only.

	dealt = raw × Class.Mult × WeaponMult × (1 − min(Armor / (Armor + ArmorK), MaxArmorReduction) × Class.ArmorFactor)
	MaxHP = def.Health × clamp(WE_ArmorMult, ArmorMultClamp) × GlobalHPMult (× Tank Factory bonus for ground
	vehicles, premium included — J9).

	Judge rulings applied (money/plan.md §1):
	- J8: Nuke class — any non-immune vehicle inside the nuke CoreRadius is destroyed (NukeConfig.Vehicles).
	- J9: the Tank Factory HP bonus applies to every ground vehicle the owner deploys, premium included.
	- J10: free drivers keep firing their rifle (SeatFire.DriverCanUseInfantryWeapons = true); fix the self-hit ray
	  instead. The owner may flip this (§2.7 D5).
	- J23: M7c adds HeavyRocketLauncher (AntiVehicle ×2) and AntiMaterielRifle (SmallArms ×1.5) to InfantryWeapons. ]]

export type DamageClass = {
	Mult: number,
	ArmorFactor: number,
	CoreDestroys: boolean?,
}

export type InfantryWeaponClass = {
	Class: string,
	Mult: number,
}

local VehicleCombatConfig = {
	Health = {
		GlobalHPMult = 1, -- one tuning knob for every vehicle's MaxHP
		ArmorK = 200,
		MaxArmorReduction = 0.6,
		ArmorMultClamp = { 1, 1.5 }, -- research VehicleArmor (WE_ArmorMult) range
		SpawnProtectSeconds = 5,
		AttrHz = 10, -- WE_HP / WE_MaxHP / WE_Destroyed writes (display only, never read back)
	},

	DamageClasses = {
		SmallArms = { Mult = 0.5, ArmorFactor = 1 }, -- rifles, SMG, pistol, shotgun pellets, vehicle MGs
		Explosive = { Mult = 1.5, ArmorFactor = 0.5 }, -- Grenade, rocket pods
		AntiVehicle = { Mult = 1, ArmorFactor = 0 }, -- RocketLauncher, siege cannon
		Missile = { Mult = 1, ArmorFactor = 0 }, -- Command Center strikes
		Nuke = { Mult = 1, ArmorFactor = 0, CoreDestroys = true }, -- J8
		NPC = { Mult = 0.5, ArmorFactor = 1 }, -- hostile NPC rifles at an enclosed seat
	} :: { [string]: DamageClass },

	-- Infantry WeaponConfig ids → class and WeaponMult (every other weapon: SmallArms × 1)
	InfantryWeapons = {
		RocketLauncher = { Class = "AntiVehicle", Mult = 2.0 },
		Grenade = { Class = "Explosive", Mult = 1 },
		Sniper = { Class = "SmallArms", Mult = 0.6 },
		-- M7c (J23): HeavyRocketLauncher = { Class = "AntiVehicle", Mult = 2.0 },
		--            AntiMaterielRifle = { Class = "SmallArms", Mult = 1.5 },
	} :: { [string]: InfantryWeaponClass },
	DefaultInfantryClass = "SmallArms",

	Destroy = {
		OccupantDamage = 35, -- every ejected occupant (not lethal from full health)
		DebrisSeconds = 3,
		RepairSeconds = { Default = 45, Premium = 20 }, -- redeploy lock for that vehicle id
		Reward = {
			CashPerHP = 0.08,
			CashMax = 500,
			XPPerHP = 0.02,
			XPMax = 120,
			PairCooldownSeconds = 300, -- same killer/victim pair: no bounty (alt farming)
			KillerWindowSeconds = 10, -- last attacker within this window gets the bounty
			CashReason = "vehicle_kill",
			XPReason = "vehicle_kill",
		},
	},

	Regen = {
		DelayAfterDamageSeconds = 12,
		PremiumPctPerSec = 0.015, -- premium "Field repair": anywhere
		OwnPlotPctPerSec = 0.02, -- Cash vehicles: only inside the owner's plot
		TickSeconds = 1,
	},

	RookieProtection = { BelowLevel = 5, VehicleWeaponMult = 0.5 },

	SeatFire = {
		DriverCanUseInfantryWeapons = true, -- J10 (owner decision D5)
		-- Passengers may fire their own guns from these open families; enclosed families (APC, tracked, heli, jet,
		-- sub, capital ship) may not.
		OpenFamilies = {
			WheeledLight = true,
			WheeledTruck = true,
			NavalPatrol = true,
			NavalGun = true,
			NavalLanding = true,
		} :: { [string]: boolean },
	},

	-- Who may sit where (enforced on Occupant change). Squad units count as the owner's. (D6)
	SeatPolicy = { Driver = "Owner", Gunner = "OwnerOrClan", Passenger = "Anyone" },

	-- Free 90 s test drives (PremiumVehicleConfig.Trial): no damage to or from players / vehicles, no bounty, and
	-- NPC kills carry no creator tag (no rewards).
	Trial = { DealsPlayerDamage = false, DealsVehicleDamage = false, TakesDamage = false, Bounty = false, KillRewards = false },

	-- W2 client HP bars (VehicleCombatClient; display only). Sizes are REAL px (the bar's ScreenGui has no UIScale).
	--   HudBar   occupant bar: touch = HudLayout top stack order TouchStackOrder (right above the SPD pill, 25);
	--            desktop = AnchorPoint (1, 1) at (1, -DesktopRight, 1, -DesktopBottom), just above the SPD pill.
	--            Flashes red below LowFrac; gold frame on premium vehicles.
	--   OverBar  over-vehicle BillboardGui on the Chassis: stud-scaled, never AlwaysOnTop, MaxDistance <= 40, no text;
	--            ShowSeconds after that vehicle's WE_HP drops, and on your own parked vehicle while HP < MaxHP;
	--            never on the vehicle you sit in; at most MaxShown at once (the most recent win).
	Ui = {
		HudBar = { Width = 230, Height = 10, TouchStackOrder = 24, DesktopRight = 14, DesktopBottom = 50, LowFrac = 0.25 },
		OverBar = { WidthStuds = 4, HeightStuds = 0.35, ShowSeconds = 5, MaxDistance = 40, MaxShown = 3 },
		RefreshHz = 10,
	},
}

-- armorReduction × ArmorFactor for one hit (pure; used by VehicleHealth and the Garage stat bars)
function VehicleCombatConfig.ArmorReduction(armor: number): number
	local h = VehicleCombatConfig.Health
	local a = math.max(0, tonumber(armor) or 0)
	return math.min(a / (a + h.ArmorK), h.MaxArmorReduction)
end

function VehicleCombatConfig.DamageMult(className: string, armor: number, weaponMult: number?): number
	local c = VehicleCombatConfig.DamageClasses[className] or VehicleCombatConfig.DamageClasses.SmallArms
	return c.Mult * (weaponMult or 1) * (1 - VehicleCombatConfig.ArmorReduction(armor) * c.ArmorFactor)
end

return VehicleCombatConfig
