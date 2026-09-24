--!strict
--[[ v71 money (M2): premium Robux vehicles — lineup, camo palettes, free test drive, showroom and copy
	(premium_vehicles.md §1, §2, §6, §7; plan §2.2). Vehicle stats and kits live in VehicleConfig (M6 adds the
	Premium defs); HP / damage in VehicleCombatConfig; mounts in VehicleWeaponConfig.
	Config only: nothing reads this file yet and nothing is sold from it.

	Money rules:
	- Robux only: permanent game passes. Never Cash, codes, Battle Pass, spinner or rebirth grants. Work from
	  Level 1 with no Depot, kept through Rebirth. profile.Vehicles is never read for premium vehicles (J4).
	- Every product Id is 0: the pass rows (PassKey below) are added to MonetizationConfig.GamePasses by M1 with
	  Id = 0 and HideFromShop, created by the owner with Item for Sale OFF (J3), and turned on sale only in the
	  publish that makes the feature live. Asset ids here are 0 too (0 = built-in Part look / no sound).
	- A premium row is hidden while its pass Id is 0 in a live server, or while its Phase is not live.
	- Offers go through the Offer Director (OfferShow) only; there is no PremiumVehicleOffer remote (J30). ]]

export type LineupEntry = {
	VehicleId: string,
	PassKey: string, -- MonetizationConfig.GamePasses key (Id lives there; 0 until the owner creates it)
	DisplayName: string,
	RobuxPrice: number, -- fallback only; the Garage shows the live price (PriceCache, J28)
	Phase: number, -- 1 = ground (M6), 2 = helicopter (M6b), 3 = boat (M6b)
	DefaultCamo: string,
	Seats: number,
	SquadSeats: number?, -- seats the owner's field squad may take (M6b decides the heli / boat layout)
	FiringPorts: number?, -- squad seats that fire at NPCs
	Weapons: { string }, -- VehicleWeaponConfig.Mounts ids
	Tagline: string,
}

export type CamoDef = {
	DisplayName: string,
	Base: Color3,
	Panel: Color3,
	Patch1: Color3,
	Patch2: Color3,
	Trim: Color3,
	Glow: Color3,
}

local GOLD = Color3.fromRGB(255, 200, 70) -- premium pinstripes / rims / turret band (§2.1)

local PremiumVehicleConfig = {
	Enabled = true,

	Lineup = {
		{
			VehicleId = "PremiumRazorfang",
			PassKey = "PV_Razorfang",
			DisplayName = "Razorfang GT Interceptor",
			RobuxPrice = 199,
			Phase = 1,
			DefaultCamo = "Urban",
			Seats = 4,
			SquadSeats = 3,
			FiringPorts = 2,
			Weapons = { "TwinHoodMG" },
			Tagline = "Fastest armored car · twin hood MGs you fire while driving",
		},
		{
			VehicleId = "PremiumBastion",
			PassKey = "PV_Bastion",
			DisplayName = "Bastion Gun Truck",
			RobuxPrice = 399,
			Phase = 1,
			DefaultCamo = "Woodland",
			Seats = 10,
			SquadSeats = 9,
			FiringPorts = 8,
			Weapons = { "RoofHMG" },
			Tagline = "Carries up to 9 soldiers · roof machine gun", -- J22 (not "your whole squad")
		},
		{
			VehicleId = "PremiumWarlord",
			PassKey = "PV_Warlord",
			DisplayName = "Warlord Siege Tank",
			RobuxPrice = 799,
			Phase = 1,
			DefaultCamo = "Desert",
			Seats = 6,
			SquadSeats = 5,
			FiringPorts = 4,
			Weapons = { "SiegeCannon", "CommanderMG" },
			Tagline = "Heaviest armor · siege cannon",
		},
		{
			VehicleId = "PremiumStormwing",
			PassKey = "PV_Stormwing",
			DisplayName = "Stormwing Gunship",
			RobuxPrice = 999,
			Phase = 2, -- M6b, after helicopter flight is verified on a phone
			DefaultCamo = "Urban",
			Seats = 8,
			Weapons = { "RocketPods", "ChinGun", "DoorMG" },
			Tagline = "Rocket pods · door gunners · 8 seats",
		},
		{
			VehicleId = "PremiumTidebreaker",
			PassKey = "PV_Tidebreaker",
			DisplayName = "Tidebreaker Assault Boat",
			RobuxPrice = 299,
			Phase = 3, -- M6b, after waterways / boats
			DefaultCamo = "Urban",
			Seats = 6,
			Weapons = { "BowTwinMG" },
			Tagline = "Fast assault boat · bow twin MG",
		},
	} :: { LineupEntry },

	-- All three ground cars (saves 298 R$). J3: the description tells single-car owners to buy the others alone.
	Bundle = {
		PassKey = "PV_MotorPool",
		DisplayName = "Premium Motor Pool",
		RobuxPrice = 1099,
		VehicleIds = { "PremiumRazorfang", "PremiumBastion", "PremiumWarlord" },
		SavesRobux = 298,
		HideIfOwnsAny = { "PV_Razorfang", "PV_Bastion", "PV_Warlord" },
	},

	-- Camo palettes (§2.2): recolour only the Base / Panel / Patch1 / Patch2 / Trim / Glow paint roles
	CamoOrder = { "Desert", "Woodland", "Urban", "Arctic", "Obsidian" },
	Camos = {
		Desert = {
			DisplayName = "Desert",
			Base = Color3.fromRGB(176, 150, 105),
			Panel = Color3.fromRGB(140, 118, 82),
			Patch1 = Color3.fromRGB(120, 95, 62),
			Patch2 = Color3.fromRGB(196, 176, 132),
			Trim = GOLD,
			Glow = Color3.fromRGB(255, 190, 90),
		},
		Woodland = {
			DisplayName = "Woodland",
			Base = Color3.fromRGB(72, 88, 58),
			Panel = Color3.fromRGB(52, 64, 42),
			Patch1 = Color3.fromRGB(40, 48, 32),
			Patch2 = Color3.fromRGB(98, 86, 60),
			Trim = GOLD,
			Glow = Color3.fromRGB(120, 255, 140),
		},
		Urban = {
			DisplayName = "Urban",
			Base = Color3.fromRGB(120, 124, 130),
			Panel = Color3.fromRGB(84, 88, 94),
			Patch1 = Color3.fromRGB(58, 60, 66),
			Patch2 = Color3.fromRGB(160, 164, 170),
			Trim = GOLD,
			Glow = Color3.fromRGB(120, 190, 255),
		},
		Arctic = {
			DisplayName = "Arctic",
			Base = Color3.fromRGB(220, 224, 228),
			Panel = Color3.fromRGB(178, 184, 190),
			Patch1 = Color3.fromRGB(140, 146, 152),
			Patch2 = Color3.fromRGB(240, 242, 244),
			Trim = GOLD,
			Glow = Color3.fromRGB(170, 220, 255),
		},
		Obsidian = {
			DisplayName = "Obsidian Gold",
			Base = Color3.fromRGB(28, 30, 34),
			Panel = Color3.fromRGB(18, 19, 22),
			Patch1 = Color3.fromRGB(40, 42, 48),
			Patch2 = Color3.fromRGB(28, 30, 34),
			Trim = Color3.fromRGB(255, 200, 70),
			Glow = Color3.fromRGB(255, 200, 70),
		},
	} :: { [string]: CamoDef },
	-- Camo → the pass the owner also needs (VIP cross-sell); the others are free for owners
	CamoVIPOnly = { Obsidian = "VIP" } :: { [string]: string },

	-- Free test drive (§6.4): once per vehicle per 24 h, never within 10 s of taking damage; server-timed.
	Trial = {
		Seconds = 90,
		CooldownHours = 24,
		NoDamageInLastSeconds = 10,
		RequestCooldownSeconds = 3,
	},

	-- Offer Director triggers (M3/M6 register them; OfferShow → NotificationController.ShowOffer)
	Offers = {
		KilledByPriority = 85,
		KilledByWindowSeconds = 3, -- WE_LastHitVehicle within this window of the death
		SquadOverflowMinStowed = 2,
		MinSecondsIntoFirstSession = 180,
	},

	-- J7: optional showroom plinth on your own plot (M6b), plot-local, never auto-prompts on touch
	Showroom = { X = 40, Z = 146, YawDeg = -90, MaxDistance = 60 },

	Look = {
		MaxKitParts = 90, -- not counting physics wheels
		NameplateMaxDistance = 180,
		NameplateAlwaysOnTop = false,
		SpawnSparkleCount = 40,
		CharredColor = Color3.fromRGB(35, 32, 30),
		Gold = GOLD,
	},

	-- 0 = built-in look / no custom asset (owner may paste Creator Store ids later)
	Assets = { ChipIconId = 0, SpawnSoundId = 0 },

	Text = {
		Chip = "PREMIUM", -- J24: text, not a glyph that can fall back in FredokaOne
		SectionHeader = "PREMIUM GARAGE · Robux · permanent · kept through Rebirth",
		Permanent = "Permanent · kept through Rebirth",
		Fits = "Fits %d of your %d soldiers", -- J22: live count in the Garage
		TryFree = "TRY FREE 90s",
		TryIn = "TRY in %s",
		Buy = "BUY %d R$",
		Repairing = "%s is being repaired: ready in %ds",
		TrialEnd = "Keep the %s? %d R$",
		KilledBy = "Killed by a %s. Try it free or own it: %d R$",
		SquadOverflow = "%s seats up to %d soldiers",
		ObsidianNeedsVip = "Obsidian Gold needs VIP",
		NotOwned = "Get this vehicle in the Garage",
	},
}

function PremiumVehicleConfig.GetLineupEntry(vehicleId: string): LineupEntry?
	for _, e in ipairs(PremiumVehicleConfig.Lineup) do
		if e.VehicleId == vehicleId then
			return e
		end
	end
	return nil
end

return PremiumVehicleConfig
