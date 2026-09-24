--!strict
--[[ Deep vehicle roster (~95): Ground / Air / Naval unlock ladder.
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

		-- ═══ DEPTH PASS 3 — toward 85–100 ═══
		-- Ground
		DispatchCar = V("DispatchCar", "Dispatch Car", "Ground", "Common", 2, 180, 60, 3, 10, 4500, "WheeledLight", { Struct = D(1), Scale = 0.8 }),
		CargoVan = V("CargoVan", "Cargo Van", "Ground", "Common", 3, 320, 46, 5, 20, 9000, "WheeledTruck", { Struct = D(1), Scale = 0.85 }),
		TroopTransport = V("TroopTransport", "Troop Transport", "Ground", "Uncommon", 6, 450, 44, 8, 28, 26000, "WheeledTruck", { Struct = D(2), Scale = 1.05 }),
		RecoveryTruck = V("RecoveryTruck", "Recovery Truck", "Ground", "Uncommon", 8, 560, 34, 3, 45, 42000, "WheeledTruck", { Struct = D(3), Scale = 1.1 }),
		EscortTruck = V("EscortTruck", "Escort Truck", "Ground", "Uncommon", 7, 500, 42, 5, 38, 36000, "WheeledTruck", { Struct = D(2) }),
		AmphibiousAPC = V("AmphibiousAPC", "Amphibious APC", "Ground", "Rare", 11, 920, 34, 8, 58, 75000, "WheeledAPC", { Struct = D(3), Scale = 1.08 }),
		FlameCarrier = V("FlameCarrier", "Flame Carrier", "Ground", "Rare", 13, 1000, 30, 3, 68, 115000, "TrackedIFV", { Struct = D(4), Scale = 1.0 }),
		HowitzerTruck = V("HowitzerTruck", "Howitzer Truck", "Ground", "Rare", 14, 980, 28, 3, 60, 145000, "TrackedArtillery", { Struct = D(4), Scale = 1.05 }),
		LightScoutTank = V("LightScoutTank", "Light Scout Tank", "Ground", "Rare", 11, 1050, 36, 3, 72, 78000, "TrackedMBT", { Struct = D(3), Scale = 0.88 }),
		SiegeMortar = V("SiegeMortar", "Siege Mortar", "Ground", "Epic", 18, 1250, 20, 2, 80, 260000, "TrackedArtillery", { Struct = D(5), Scale = 1.2 }),
		MobileSAM = V("MobileSAM", "Mobile SAM", "Ground", "Epic", 17, 1100, 28, 3, 75, 230000, "TrackedSPAAG", { Struct = D(5), Scale = 1.1 }),
		FortressTank = V(
			"FortressTank",
			"Fortress Tank",
			"Ground",
			"Legendary",
			23,
			3600,
			18,
			4,
			200,
			520000,
			"TrackedMBT",
			{ Struct = D(5), Scale = 1.6, Prestige = 7 }
		),
		RailgunCarrier = V(
			"RailgunCarrier",
			"Railgun Carrier",
			"Ground",
			"Legendary",
			24,
			2800,
			22,
			3,
			160,
			580000,
			"TrackedArtillery",
			{ Struct = D(5), Scale = 1.35, Prestige = 12, RebirthFlag = "EmpireElite" }
		),

		-- Air
		UtilityHeli = V("UtilityHeli", "Utility Helicopter", "Air", "Uncommon", 10, 650, 58, 3, 16, 85000, "HeliLight", { Struct = H(1), Scale = 0.9 }),
		MedevacHeli = V("MedevacHeli", "Medevac Helicopter", "Air", "Rare", 13, 750, 56, 5, 20, 130000, "HeliTransport", { Struct = H(2), Scale = 0.95 }),
		EscortHeli = V("EscortHeli", "Escort Helicopter", "Air", "Rare", 15, 850, 64, 3, 28, 175000, "HeliAttack", { Struct = H(2) }),
		NightAttackHeli = V("NightAttackHeli", "Night Attack Helicopter", "Air", "Epic", 19, 980, 68, 2, 36, 270000, "HeliAttack", { Struct = H(3), Scale = 1.08 }),
		VTOLTransport = V("VTOLTransport", "VTOL Transport", "Air", "Epic", 21, 1500, 70, 8, 42, 340000, "HeliTransport", { Struct = H(4), Scale = 1.2 }),
		ReconPlane = V("ReconPlane", "Recon Plane", "Air", "Rare", 14, 500, 110, 1, 15, 160000, "JetFighter", { Struct = A(1), Scale = 0.85 }),
		LightFighter = V("LightFighter", "Light Fighter", "Air", "Rare", 17, 620, 115, 1, 20, 240000, "JetFighter", { Struct = A(2), Scale = 0.92 }),
		TankerPlane = V("TankerPlane", "Tanker Plane", "Air", "Epic", 19, 1700, 88, 3, 38, 300000, "JetTransport", { Struct = A(3), Scale = 1.25 }),
		StealthStrike = V(
			"StealthStrike",
			"Stealth Strike Jet",
			"Air",
			"Legendary",
			23,
			780,
			125,
			1,
			30,
			500000,
			"JetStrike",
			{ Struct = A(4), Scale = 1.05, Prestige = 5 }
		),
		StrategicBomber = V(
			"StrategicBomber",
			"Strategic Bomber",
			"Air",
			"Legendary",
			26,
			2200,
			80,
			5,
			60,
			680000,
			"JetBomber",
			{ Struct = A(5), Scale = 1.55, Prestige = 10, RebirthFlag = "StrikeWing" }
		),

		-- Naval
		CoastCutter = V("CoastCutter", "Coast Cutter", "Naval", "Common", 5, 400, 45, 5, 20, 20000, "NavalPatrol", { Struct = N(1), Scale = 0.85 }),
		TorpedoBoat = V("TorpedoBoat", "Torpedo Boat", "Naval", "Uncommon", 9, 480, 58, 3, 28, 48000, "NavalPatrol", { Struct = N(1), Scale = 0.88 }),
		HospitalShip = V("HospitalShip", "Hospital Ship", "Naval", "Rare", 11, 1100, 30, 10, 35, 90000, "NavalLanding", { Struct = N(2), Scale = 1.2 }),
		SupplyShip = V("SupplyShip", "Supply Ship", "Naval", "Rare", 13, 1300, 28, 6, 45, 120000, "NavalLanding", { Struct = N(3), Scale = 1.15 }),
		CoastalMonitor = V("CoastalMonitor", "Coastal Monitor", "Naval", "Rare", 14, 1500, 26, 5, 80, 150000, "NavalGun", { Struct = N(3), Scale = 1.1 }),
		AmphibAssault = V("AmphibAssault", "Amphib Assault Ship", "Naval", "Epic", 17, 1800, 30, 12, 70, 250000, "NavalLanding", { Struct = N(4), Scale = 1.3 }),
		AttackSub = V(
			"AttackSub",
			"Attack Sub",
			"Naval",
			"Legendary",
			21,
			1600,
			38,
			4,
			100,
			360000,
			"NavalSub",
			{ Struct = N(4), Scale = 1.1, Prestige = 4 }
		),
		MissileCruiser = V(
			"MissileCruiser",
			"Missile Cruiser",
			"Naval",
			"Legendary",
			22,
			3000,
			34,
			8,
			150,
			480000,
			"NavalCapital",
			{ Struct = N(5), Scale = 1.25, Prestige = 8 }
		),
		FleetCarrier = V(
			"FleetCarrier",
			"Fleet Carrier",
			"Naval",
			"Legendary",
			26,
			4500,
			28,
			14,
			180,
			720000,
			"NavalCapital",
			{ Struct = N(5), Scale = 1.7, Prestige = 15, RebirthFlag = "EmpireFleet" }
		),
	} :: { [string]: VehicleDef },

	Categories = { "Ground", "Air", "Naval" } :: { VehicleCategory },
	Rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary" },
	StarterVehicle = "MilitaryJeep",
	SpawnCooldownSeconds = 15,
	UseMeshKitsWhenAssetIdNonZero = true,

	--[[ v70 driving (spec: scratchpad vehicles/spec.md). The driver's client runs these laws
		(VehicleDriveClient) and writes the WE_DriveLV / WE_DriveAO movers; VehicleService runs the idle
		laws, the Car/Boat fallback copy and the 5 Hz checks. Speeds in studs/s, rates in studs/s²,
		angles in degrees unless the name says Rad, turn rates in rad/s.
		Per-vehicle values (WE_MaxSpeed, WE_Accel, WE_TurnRate, ...) are model attributes set at spawn. ]]
	Drive = {
		ProtocolVersion = 1, -- WE_ProtocolVersion; a client with a different version refuses to drive
		HelloTimeoutSeconds = 2.5, -- no VehicleDriveInput Hello this long after sitting → Car/Boat "Fallback"
		IdleDespawnSeconds = 300, -- nobody sat in it this long → destroyed (no message)
		MaxResearchSpeedBonus = 1.5, -- ResearchService.GetBonus(player, "VehicleSpeed") clamp
		MaxResearchArmorBonus = 3, -- VehicleArmor bonus clamp (stored as WE_ArmorMult only)
		IdleHz = 10, -- server idle law rate (parked / abandoned / correcting)
		LostBelowY = -30, -- chassis below this → destroyed, "Vehicle lost"
		LostMargin = 40, -- |X| or |Z| beyond Validation.WorldHalfExtent + this → destroyed
		StabilisedNoticeSeconds = 20, -- "Vehicle stabilised" at most this often
		SeatMassAllowance = 20, -- mover force F = (AssemblyMass + this x def.Seats) x ForcePerMass

		-- Server-verified drive (judge fix): if the client-simulated car does not move while the driver pushes,
		-- the server takes ownership of every assembly and drives it (Car/Boat). Aircraft: diagnostics only.
		Watchdog = {
			Enabled = true,
			PushThrottle = 0.5, -- above this = the driver is pushing: |throttle| (Car/Boat), lift up (Heli), throttle up (Plane)
			Seconds = 1.2, -- pushing this long ...
			MinMoveStuds = 1.5, -- ... with less movement than this under Client authority → trip
			ProvenStuds = 3, -- moved this far from the sit point under Client authority → watchdog disarms for this sit
			BlockedSeconds = 3, -- after a trip: pushing this long in server drive with no movement → "BLOCKED" log
			OwnerProbeHz = 1, -- GetNetworkOwner probe rate ...
			OwnerProbeSeconds = 6, -- ... for this long after each hand-off
			SessionTrips = 2, -- server-proven trips before this player's later Car/Boat sits start in server drive
			StreamHz = 10, -- client "In" input stream while any axis is non-zero
			StreamStaleSeconds = 0.5, -- older stream input → use the seat floats
			StreamRate = 15, -- RateLimitService key "vehicle_drive_stream"
			StreamBurst = 10,
		},
		Debug = {
			UserIds = { 470626172 }, -- on-device NO DRIVE line + WE_Diag attribute + periodic server log
			All = false,
			NoDriveSeconds = 1.0, -- throttle held this long ...
			NoDriveSpeed = 1.0, -- ... with speed below this → show the line
			ShowSeconds = 6, -- keep it up this long after the condition clears
			ServerLogSeconds = 5, -- debug users: one server diag line this often while seated and pushing
		},
		-- Mobile P1-7 (VehicleDriveClient reads these over its DEFAULTS, key by key): the EXIT hold pill in every vehicle
		-- on touch, and the airborne jump lock (Heli/Plane above LockAGL: local JumpHeight 0, the touch jump hides)
		Exit = {
			HoldSeconds = 0.5, -- the EXIT pill fires after this long held
			LockAGL = 8, -- studs above the ground → jump locked ...
			UnlockAGL = 7, -- ... and unlocked again below this (hysteresis)
			RequestGapSeconds = 0.3, -- at most one {K="Exit"} per this long
			StuckSeconds = 1.5, -- F4c: pushing this long under Client authority at speed < StuckSpeed → one Stuck report
			StuckSpeed = 1.0,
		},
		-- Mobile P1-8: the client-side owner nameplate (never AlwaysOnTop; MaxDistance is capped at 40 in code)
		Nameplate = { MaxDistance = 36, WidthStuds = 2, HeightStuds = 0.4, HeightPx = 20, MinText = 14, MaxText = 20 },

		-- Speed resync (every mode): actual forward speed this far below the commanded speed for
		-- Seconds straight → commanded = actual + gap (a vehicle pushed into a wall never winds up).
		Resync = { Gap = 10, CarGap = 6, Seconds = 0.3, GraceSeconds = 1 },

		Modes = {
			Car = {
				WheeledMinSpeed = 40, -- WE_MaxSpeed = max(def.Speed, 40) (40-68)
				TrackedMinSpeed = 18, -- tracked: clamp(def.Speed, 18, 36)
				TrackedMaxSpeed = 36,
				Wheeled = { Accel = 28, Brake = 60, Coast = 10, TurnRate = 2.4, MinTurnFactor = 0.35, Grip = 8 },
				Tracked = { Accel = 16, Brake = 40, Coast = 10, TurnRate = 1.5, MinTurnFactor = 0.7, Grip = 12 },
				ReverseFrac = 0.45, -- reverse max = 0.45 x Max
				ReverseAccelFrac = 0.7, -- reverse accel = Accel x 0.7
				TurnSpeedRef = 12, -- full turn rate from this speed up
				YawResyncRad = 0.6, -- collision spun the car this far off → take the real heading
				FlipUpY = 0.3, -- UpVector.Y below this ...
				FlipSeconds = 2, -- ... this long → hop
				HopSeconds = 0.5,
				HopSpeed = 15,
				-- Physics wheels roll free on hinges. Yawing a fixed-axle car makes every wheel slip sideways,
				-- which wheel friction resists with mu x load x |wheel Z|; the AlignOrientation must beat it or the
				-- car cannot turn. Low friction (weight 100 = the wheel's value wins over the ground's) keeps the
				-- AO at >= 2x that torque for every kit; the law's Grip term supplies the sideways grip instead.
				WheelFriction = 0.2,
				WheelFrictionWeight = 100,
				-- movers (server-built)
				ForcePerMass = 250,
				TorqueScale = 4,
				Responsiveness = 25,
				MaxAngularVelocity = 8,
			},
			Heli = {
				Accel = 22,
				Drag = 20,
				BackFrac = 0.4,
				StrafeFrac = 0.5,
				ClimbRate = 24,
				SinkRate = 20,
				AccelV = 30,
				TurnRate = 1.6,
				YawAccel = 5,
				MaxPitchTilt = 14,
				MaxRollTilt = 12,
				BankPerYawRate = 6, -- degrees of roll per rad/s of yaw rate
				TiltRate = 25,
				AltHoldGain = 1.5,
				AltHoldMax = 6,
				LandAGL = 0.8,
				MaxAltitude = 450, -- world Y
				IdleSink = 8, -- idle (no pilot): sink at this speed until IdleLandAGL
				IdleLandAGL = 1,
				ForcePerMass = 600,
				TorqueScale = 3,
				Responsiveness = 12,
				MaxAngularVelocity = 3,
			},
			Plane = {
				Thrust = 20,
				Drag = 6,
				GroundDrag = 10,
				Brake = 30,
				GravityAlong = 25, -- x sin(pitch)
				OverspeedFrac = 1.15,
				ThrottleRateUp = 0.6,
				ThrottleRateDown = 0.8,
				MaxPitchUp = 30,
				MaxPitchDown = 35,
				PitchRate = 40,
				MaxBank = 55,
				BankRate = 90,
				TurnRate = 0.9, -- at full bank
				TaxiTurnRate = 0.8,
				StallNoseDown = -20,
				StallSinkMax = 35,
				StallClearMargin = 3, -- stall clears at StallSpeed + this
				ClimbOutPitch = 15,
				ClimbOutAGL = 45,
				AutoTakeoff = true,
				AutoTakeoffLever = 0.9,
				AutoTakeoffSpeedFrac = 1.1, -- x TakeoffSpeed
				LiftoffPitch = 6,
				RolledOffAGL = 3,
				LandAGL = 1.5,
				MaxAltitude = 600,
				AirStartHeight = 120,
				AirStartSpeedFrac = 1.3, -- x TakeoffSpeed
				TakeoffFrac = 0.45, -- WE_TakeoffSpeed = clamp(0.45 x def.Speed, 40, 60) (not research-scaled)
				TakeoffMin = 40,
				TakeoffMax = 60,
				StallFrac = 0.8, -- WE_StallSpeed = 0.8 x TakeoffSpeed
				IdleGlideAGL = 2, -- idle (no pilot) above this: glide
				IdleGlideMinSpeed = 25,
				IdleGlideDecel = 6,
				IdleGlideSink = 18,
				IdleGlidePitch = -8,
				ForcePerMass = 600,
				TorqueScale = 3,
				Responsiveness = 15,
				MaxAngularVelocity = 2.5,
			},
			Boat = {
				Accel = 14,
				Brake = 18,
				Coast = 6,
				ReverseFrac = 0.35,
				ReverseAccelFrac = 0.7,
				TurnRate = 1.1,
				MinTurnFactor = 0.25,
				TurnSpeedRef = 8,
				Drift = 3,
				Draft = 0.15, -- WE_RideOffset = Clearance - Draft
				BobAmp = 0.15, -- bob only goes up: rideY + BobAmp x 0.5 x (1 + sin)
				BobHz = 0.35,
				HeightGain = 4,
				MaxVy = 10,
				BowUpDeg = 4,
				TurnLeanDeg = 6,
				BobPitchDeg = 1.2,
				BobRollDeg = 1.5,
				BobRollHz = 0.4,
				ShoreBrake = 50,
				ShoreMargin = 3,
				AgroundSpeed = 8, -- pushed aground: head back to the last water position at this speed
				IdleHeightGain = 2,
				IdleMaxVy = 6,
				IdleDecel = 6,
				ForcePerMass = 500,
				TorqueScale = 2,
				Responsiveness = 8,
				MaxAngularVelocity = 1.5,
			},
		},

		-- Server checks while the driver's client owns the physics (5 Hz)
		Validation = {
			SpeedTolerance = 1.25, -- cap = WE_MaxSpeed x 1.25 + slack
			SpeedSlack = 12,
			AirSpeedSlack = 30,
			SpeedSamplesToFlag = 2,
			TeleportSlack = 20,
			HardTeleport = 150, -- more than this beyond the teleport allowance counts toward a recall
			MaxLagWindow = 1.5, -- teleport allowance grows with time since the last valid sample up to this
		WindowSeconds = 1, -- plus a ~1 s displacement window: TeleportSlack is granted once per window, not per sample
			MaxGroundUpSpeed = 60,
			GroundMaxY = 150,
			AirAltitudeSlack = 25,
			WorldHalfExtent = 3560,
			OffWaterGrace = 1.5,
			OffWaterMargin = -3, -- boats: 3 studs of slack outside a water part's edge
			BoatMaxAboveWater = 8,
			SampleHz = 5,
			CorrectionHold = 1.5,
			RecallViolations = 3,
			RecallWindow = 60,
		},

		World = { SoftBound = 3300 }, -- client: past this, no outward speed + "TURN BACK"

		Water = {
			RefreshSeconds = 2, -- WE_Water part list refresh
			QueryBelow = 8, -- a point counts as over a water part from top - 8 ...
			QueryAbove = 20, -- ... to top + 20
			ConnectGap = 2, -- basins link when rectangles come this close ...
			ConnectTopDelta = 1.5, -- ... and their tops differ by at most this
			SpawnMargin = 1, -- boat spawn: every hull point this far inside a water part
			GridStep = 4, -- dock basin spawn scan
			-- land probe ray starts this far above the water top (Waterways C4: at +30 the oil-rig decks at y 28 and
			-- their markers counted as land and blocked the canal under each rig; +6 still sees the sea-gate leaves
			-- and boom (top 6.0), kerbs (2.0), pontoons (2.1) and the leg / pier footings (2.5))
			LandProbeHeight = 6,
		},

		Spawn = {
			Clearance = 0.3, -- chassis Y = surface + Clearance(footprint) + this
			MaxStepUp = 4, -- a surface ray hit this far above the expected top = something in the way
			CarPadRadius = 700,
			PlotFallback = { X = 0, Z = 45 }, -- plot-local (spots and headings below turn with the plot pad's CFrame)
			-- from the Helipad site: on the deck clear of the parked-heli model, then the apron toward the gate
			HelipadSpots = { { X = -4, Z = 6 }, { X = 8, Z = 8 }, { X = 0, Z = 38 } },
			HelipadDeckHeight = 1.2, -- above the plot pad top when no ray hits
			HeliHeadingRad = math.pi, -- nose toward the base (plot-local +Z)
			RunwayRoad = "Runway", -- BaseLayoutConfig.Roads entry
			RunwayInset = 12, -- start this far in from the runway end nearer the plot edge
			RunwayHeight = 0.12, -- runway top above the plot pad top when no ray hits
			NavalPadGap = 4,
			OffsetStep = 4, -- extra room between side-by-side spots
			-- Mobile P1-9: SPAWN is not a teleport or a combat escape
			FrontDistance = 14, -- "in front of the player" = this + the footprint radius ahead of the root part
			OwnPlotMargin = 0, -- inside your own plot = on the plot pad's rectangle grown by this (studs)
			AutoSitRadius = 30, -- auto-sit (and the root-part move onto the seat) only within this of the vehicle's footprint
			-- ... except inside your own plot: the garage flow keeps seating you on your own car pad / helipad / runway /
			-- dock basin (139-279 studs from the base spawn, up to ~500 from a plot corner); nothing further than this
			AutoSitHomeRadius = 520,
			DamageLockSeconds = 5, -- SPAWN refused this long after the player's character took damage
		},
	},
}

return VehicleConfig
