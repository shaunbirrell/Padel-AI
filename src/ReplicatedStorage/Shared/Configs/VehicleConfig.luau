--!strict
--[[ Deep vehicle roster (~67): Ground / Air / Naval unlock ladder.
	KitFamily drives VehicleService Part kits (grows to 100 without rewrite).
	Generic military names only — no real brands, no MT names.
]]

export type VehicleCategory = "Ground" | "Air" | "Naval"

export type KitFamily =
	"WheeledLight"
	| "WheeledTruck"
	| "WheeledAPC"
	| "TrackedIFV"
	| "TrackedMBT"
	| "TrackedSPAAG"
	| "TrackedArtillery"
	| "HeliLight"
	| "HeliTransport"
	| "HeliAttack"
	| "JetFighter"
	| "JetStrike"
	| "JetBomber"
	| "JetTransport"
	| "NavalPatrol"
	| "NavalGun"
	| "NavalLanding"
	| "NavalCapital"
	| "NavalSub"

export type VehicleDef = {
	Id: string,
	DisplayName: string,
	Category: VehicleCategory,
	Rarity: string,
	UnlockLevel: number,
	Health: number,
	Speed: number,
	Seats: number,
	Armor: number,
	CostCash: number,
	KitFamily: KitFamily,
	KitScale: number?, -- visual scale mult (default 1)
	RequiresStructure: { StructureId: string, Level: number }?,
	RequiresPrestige: number?,
	RequiresRebirthFlag: string?,
	MeshAssetId: number?,
	TextureAssetId: number?,
}

local function V(
	id: string,
	name: string,
	cat: VehicleCategory,
	rarity: string,
	level: number,
	health: number,
	speed: number,
	seats: number,
	armor: number,
	cost: number,
	kit: KitFamily,
	opts: {
		Scale: number?,
		Struct: { StructureId: string, Level: number }?,
		Prestige: number?,
		RebirthFlag: string?,
	}?
): VehicleDef
	local scale: number? = nil
	local struct: { StructureId: string, Level: number }? = nil
	local prestige: number? = nil
	local rebirthFlag: string? = nil
	if opts then
		scale = opts.Scale
		struct = opts.Struct
		prestige = opts.Prestige
		rebirthFlag = opts.RebirthFlag
	end
	return {
		Id = id,
		DisplayName = name,
		Category = cat,
		Rarity = rarity,
		UnlockLevel = level,
		Health = health,
		Speed = speed,
		Seats = seats,
		Armor = armor,
		CostCash = cost,
		KitFamily = kit,
		KitScale = scale,
		RequiresStructure = struct,
		RequiresPrestige = prestige,
		RequiresRebirthFlag = rebirthFlag,
	}
end

local D = function(l: number): { StructureId: string, Level: number }
	return { StructureId = "VehicleDepot", Level = l }
end
local H = function(l: number): { StructureId: string, Level: number }
	return { StructureId = "Helipad", Level = l }
end
local A = function(l: number): { StructureId: string, Level: number }
	return { StructureId = "Airfield", Level = l }
end
local N = function(l: number): { StructureId: string, Level: number }
	return { StructureId = "Dock", Level = l }
end

local VehicleConfig = {
	Vehicles = {
		-- ═══ GROUND — early wheeled ═══
		MilitaryJeep = V("MilitaryJeep", "Military Jeep", "Ground", "Common", 1, 200, 55, 4, 10, 0, "WheeledLight", nil),
		UtilityQuad = V("UtilityQuad", "Utility Quad", "Ground", "Common", 2, 160, 58, 2, 8, 3500, "WheeledLight", { Struct = D(1), Scale = 0.75 }),
		ArmedJeep = V("ArmedJeep", "Armed Jeep", "Ground", "Common", 3, 250, 52, 4, 15, 8000, "WheeledLight", { Struct = D(1) }),
		ScoutCar = V("ScoutCar", "Scout Car", "Ground", "Common", 4, 280, 62, 3, 18, 12000, "WheeledLight", { Struct = D(1) }),
		PatrolTruck = V("PatrolTruck", "Patrol Truck", "Ground", "Common", 5, 380, 48, 5, 25, 16000, "WheeledTruck", { Struct = D(1), Scale = 0.9 }),
		ArmoredTruck = V("ArmoredTruck", "Armored Truck", "Ground", "Uncommon", 5, 500, 40, 6, 40, 20000, "WheeledTruck", { Struct = D(2) }),
		SupplyTruck = V("SupplyTruck", "Supply Truck", "Ground", "Uncommon", 6, 420, 42, 5, 30, 28000, "WheeledTruck", { Struct = D(2) }),
		ReconBuggy = V("ReconBuggy", "Recon Buggy", "Ground", "Uncommon", 6, 300, 68, 2, 20, 24000, "WheeledLight", { Struct = D(2), Scale = 0.85 }),
		FuelTanker = V("FuelTanker", "Fuel Tanker", "Ground", "Uncommon", 7, 480, 38, 3, 35, 35000, "WheeledTruck", { Struct = D(2), Scale = 1.1 }),
		EngineeringTruck = V("EngineeringTruck", "Engineering Truck", "Ground", "Uncommon", 8, 520, 36, 4, 42, 40000, "WheeledTruck", { Struct = D(3) }),
		-- mid IFV / APC
		APC = V("APC", "APC", "Ground", "Rare", 8, 800, 38, 8, 60, 45000, "WheeledAPC", { Struct = D(3) }),
		InfantryCarrier = V("InfantryCarrier", "Infantry Carrier", "Ground", "Rare", 9, 900, 36, 10, 55, 55000, "WheeledAPC", { Struct = D(3), Scale = 1.1 }),
		CombatIFV = V("CombatIFV", "Combat IFV", "Ground", "Rare", 10, 1000, 34, 7, 70, 70000, "TrackedIFV", { Struct = D(3) }),
		CommandVehicle = V("CommandVehicle", "Command Vehicle", "Ground", "Rare", 11, 850, 32, 6, 65, 80000, "WheeledAPC", { Struct = D(3), Scale = 1.05 }),
		MissileTruck = V("MissileTruck", "Missile Truck", "Ground", "Rare", 11, 700, 34, 3, 45, 85000, "WheeledTruck", { Struct = D(4), Scale = 1.05 }),
		AntiAirTruck = V("AntiAirTruck", "Anti-Air Truck", "Ground", "Rare", 12, 750, 36, 3, 50, 88000, "WheeledTruck", { Struct = D(4) }),
		-- tanks / SPAAG / arty
		LightTank = V("LightTank", "Light Tank", "Ground", "Rare", 12, 1200, 32, 3, 80, 90000, "TrackedMBT", { Struct = D(4), Scale = 0.95 }),
		SPAAG = V("SPAAG", "Mobile SPAAG", "Ground", "Rare", 13, 950, 30, 3, 65, 110000, "TrackedSPAAG", { Struct = D(4) }),
		MortarCarrier = V("MortarCarrier", "Mortar Carrier", "Ground", "Rare", 13, 900, 28, 3, 55, 105000, "TrackedArtillery", { Struct = D(4), Scale = 0.9 }),
		MediumTank = V("MediumTank", "Medium Tank", "Ground", "Epic", 14, 1600, 28, 3, 100, 130000, "TrackedMBT", { Struct = D(4), Scale = 1.12 }),
		AssaultIFV = V("AssaultIFV", "Assault IFV", "Ground", "Epic", 15, 1400, 33, 6, 90, 150000, "TrackedIFV", { Struct = D(5), Scale = 1.1 }),
		HeavyTank = V("HeavyTank", "Heavy Tank", "Ground", "Epic", 15, 2000, 25, 3, 120, 180000, "TrackedMBT", { Struct = D(5), Scale = 1.25 }),
		MobileArtillery = V("MobileArtillery", "Mobile Artillery", "Ground", "Epic", 16, 1100, 22, 2, 70, 220000, "TrackedArtillery", { Struct = D(5) }),
		BattleTank = V("BattleTank", "Battle Tank", "Ground", "Epic", 18, 2400, 26, 3, 140, 280000, "TrackedMBT", { Struct = D(5), Scale = 1.35 }),
		RocketArtillery = V("RocketArtillery", "Rocket Artillery", "Ground", "Epic", 19, 1300, 24, 2, 75, 300000, "TrackedArtillery", { Struct = D(5), Scale = 1.15 }),
		SuperHeavyTank = V(
			"SuperHeavyTank",
			"Super Heavy Tank",
			"Ground",
			"Legendary",
			22,
			3200,
			20,
			4,
			180,
			450000,
			"TrackedMBT",
			{ Struct = D(5), Scale = 1.5, Prestige = 5, RebirthFlag = "EmpireElite" }
		),

		-- ═══ AIR ═══
		LightScoutHeli = V("LightScoutHeli", "Scout Helicopter", "Air", "Rare", 10, 600, 65, 2, 18, 95000, "HeliLight", { Struct = H(1), Scale = 0.85 }),
		TransportHeli = V("TransportHeli", "Transport Helicopter", "Air", "Rare", 14, 1000, 55, 6, 30, 160000, "HeliTransport", { Struct = H(2) }),
		GunshipHeli = V("GunshipHeli", "Gunship Helicopter", "Air", "Epic", 16, 950, 62, 3, 32, 210000, "HeliAttack", { Struct = H(2), Scale = 1.05 }),
		AttackHelicopter = V("AttackHelicopter", "Attack Helicopter", "Air", "Epic", 18, 900, 70, 2, 35, 250000, "HeliAttack", { Struct = H(3) }),
		HeavyLiftHeli = V("HeavyLiftHeli", "Heavy Lift Helicopter", "Air", "Epic", 20, 1400, 48, 8, 40, 310000, "HeliTransport", { Struct = H(4), Scale = 1.25 }),
		StealthHeli = V(
			"StealthHeli",
			"Stealth Helicopter",
			"Air",
			"Legendary",
			24,
			1100,
			75,
			2,
			38,
			420000,
			"HeliAttack",
			{ Struct = H(5), Scale = 1.1, Prestige = 3 }
		),
		CargoPlane = V("CargoPlane", "Cargo Plane", "Air", "Epic", 18, 1600, 90, 6, 35, 290000, "JetTransport", { Struct = A(2), Scale = 1.3 }),
		StrikeJet = V("StrikeJet", "Strike Jet", "Air", "Epic", 19, 750, 105, 1, 28, 320000, "JetStrike", { Struct = A(2) }),
		FighterJet = V("FighterJet", "Fighter Jet", "Air", "Legendary", 20, 700, 120, 1, 25, 400000, "JetFighter", { Struct = A(3) }),
		InterceptorJet = V("InterceptorJet", "Interceptor Jet", "Air", "Legendary", 21, 680, 135, 1, 22, 440000, "JetFighter", { Struct = A(3), Scale = 1.05 }),
		StrikeBomber = V("StrikeBomber", "Strike Bomber", "Air", "Legendary", 22, 1200, 95, 2, 40, 480000, "JetBomber", { Struct = A(4), Scale = 1.2 }),
		HeavyBomber = V(
			"HeavyBomber",
			"Heavy Bomber",
			"Air",
			"Legendary",
			25,
			1800,
			85,
			4,
			55,
			600000,
			"JetBomber",
			{ Struct = A(5), Scale = 1.45, Prestige = 8, RebirthFlag = "StrikeWing" }
		),

		-- ═══ NAVAL ═══
		PatrolBoat = V("PatrolBoat", "Patrol Boat", "Naval", "Uncommon", 6, 450, 48, 4, 25, 25000, "NavalPatrol", { Struct = N(1) }),
		FastAttackCraft = V("FastAttackCraft", "Fast Attack Craft", "Naval", "Uncommon", 8, 500, 55, 3, 30, 42000, "NavalPatrol", { Struct = N(1), Scale = 0.9 }),
		Gunboat = V("Gunboat", "Gunboat", "Naval", "Rare", 10, 700, 42, 5, 45, 70000, "NavalGun", { Struct = N(2) }),
		MissileBoat = V("MissileBoat", "Missile Boat", "Naval", "Rare", 12, 750, 44, 4, 48, 95000, "NavalGun", { Struct = N(2), Scale = 1.05 }),
		LandingCraft = V("LandingCraft", "Landing Craft", "Naval", "Rare", 12, 900, 35, 8, 50, 95000, "NavalLanding", { Struct = N(3) }),
		AssaultLanding = V("AssaultLanding", "Assault Landing", "Naval", "Epic", 15, 1200, 32, 10, 65, 160000, "NavalLanding", { Struct = N(3), Scale = 1.15 }),
		Corvette = V("Corvette", "Corvette", "Naval", "Epic", 16, 1600, 40, 5, 85, 220000, "NavalCapital", { Struct = N(4), Scale = 0.75 }),
		Destroyer = V("Destroyer", "Destroyer", "Naval", "Legendary", 17, 2200, 38, 6, 110, 280000, "NavalCapital", { Struct = N(4) }),
		SubSurfaceRunner = V(
			"SubSurfaceRunner",
			"Sub Surface Runner",
			"Naval",
			"Epic",
			18,
			1400,
			36,
			4,
			90,
			260000,
			"NavalSub",
			{ Struct = N(4), Scale = 1.0 }
		),
		Cruiser = V(
			"Cruiser",
			"Cruiser",
			"Naval",
			"Legendary",
			20,
			2800,
			36,
			8,
			140,
			380000,
			"NavalCapital",
			{ Struct = N(5), Scale = 1.2, Prestige = 2 }
		),
		Battleship = V(
			"Battleship",
			"Battleship",
			"Naval",
			"Legendary",
			25,
			4000,
			30,
			10,
			200,
			650000,
			"NavalCapital",
			{ Struct = N(5), Scale = 1.55, Prestige = 10, RebirthFlag = "EmpireFleet" }
		),

		-- ═══ DEPTH PASS 2 — toward 60–80 ═══
		FlatbedHauler = V("FlatbedHauler", "Flatbed Hauler", "Ground", "Common", 4, 360, 44, 3, 22, 14000, "WheeledTruck", { Struct = D(1), Scale = 0.95 }),
		AmmoCarrier = V("AmmoCarrier", "Ammo Carrier", "Ground", "Uncommon", 7, 460, 40, 4, 38, 32000, "WheeledTruck", { Struct = D(2) }),
		WheeledIFV = V("WheeledIFV", "Wheeled IFV", "Ground", "Rare", 10, 950, 40, 6, 62, 65000, "WheeledAPC", { Struct = D(3), Scale = 1.05 }),
		TankDestroyer = V("TankDestroyer", "Tank Destroyer", "Ground", "Epic", 16, 1500, 30, 3, 95, 200000, "TrackedMBT", { Struct = D(5), Scale = 1.08 }),
		BridgeLayer = V("BridgeLayer", "Bridge Layer", "Ground", "Rare", 14, 1100, 26, 3, 70, 140000, "TrackedIFV", { Struct = D(4), Scale = 1.2 }),
		MineClearer = V("MineClearer", "Mine Clearer", "Ground", "Uncommon", 9, 700, 28, 2, 50, 60000, "TrackedIFV", { Struct = D(3), Scale = 0.95 }),
		RadarTruck = V("RadarTruck", "Radar Truck", "Ground", "Rare", 12, 650, 38, 3, 40, 92000, "WheeledTruck", { Struct = D(4) }),
		AssaultGun = V("AssaultGun", "Assault Gun", "Ground", "Epic", 17, 1800, 24, 3, 115, 240000, "TrackedMBT", { Struct = D(5), Scale = 1.18 }),
		LightTransportHeli = V("LightTransportHeli", "Light Transport Heli", "Air", "Rare", 12, 800, 58, 4, 22, 120000, "HeliTransport", { Struct = H(1), Scale = 0.9 }),
		RescueHeli = V("RescueHeli", "Rescue Helicopter", "Air", "Uncommon", 11, 700, 60, 4, 20, 100000, "HeliLight", { Struct = H(1) }),
		CASJet = V("CASJet", "Close Air Support Jet", "Air", "Epic", 20, 820, 100, 1, 30, 350000, "JetStrike", { Struct = A(3), Scale = 1.08 }),
		TrainerJet = V("TrainerJet", "Trainer Jet", "Air", "Rare", 15, 550, 95, 2, 18, 180000, "JetFighter", { Struct = A(1), Scale = 0.9 }),
		AWACSPlane = V("AWACSPlane", "AWACS Plane", "Air", "Legendary", 23, 1400, 80, 4, 45, 520000, "JetTransport", { Struct = A(4), Scale = 1.35, Prestige = 4 }),
		RiverBoat = V("RiverBoat", "River Boat", "Naval", "Common", 5, 350, 42, 4, 18, 18000, "NavalPatrol", { Struct = N(1), Scale = 0.8 }),
		MineLayer = V("MineLayer", "Mine Layer", "Naval", "Rare", 13, 1000, 32, 5, 55, 110000, "NavalGun", { Struct = N(3), Scale = 1.1 }),
		Frigate = V("Frigate", "Frigate", "Naval", "Epic", 18, 2000, 40, 6, 100, 300000, "NavalCapital", { Struct = N(4), Scale = 0.9 }),
		CarrierEscort = V("CarrierEscort", "Carrier Escort", "Naval", "Legendary", 22, 2600, 34, 8, 125, 420000, "NavalCapital", { Struct = N(5), Scale = 1.1, Prestige = 6 }),
		HoverTransport = V("HoverTransport", "Hover Transport", "Naval", "Epic", 16, 1100, 50, 8, 40, 190000, "NavalLanding", { Struct = N(3), Scale = 1.05 }),
	} :: { [string]: VehicleDef },

	Categories = { "Ground", "Air", "Naval" } :: { VehicleCategory },
	Rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary" },
	StarterVehicle = "MilitaryJeep",
	SpawnCooldownSeconds = 15,
	UseMeshKitsWhenAssetIdNonZero = true,
}

return VehicleConfig
