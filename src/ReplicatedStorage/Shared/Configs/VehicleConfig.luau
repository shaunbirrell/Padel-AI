--!strict
--[[ Deep vehicle roster (~95): Ground / Air / Naval unlock ladder.
	KitFamily drives VehicleService Part kits (grows to 100 without rewrite).
	Generic military names only — no real brands, no MT names. JEEP-2 (roadmap §1.4): DisplayName is what players see
	("Field 4x4", "Armed 4x4"); the ids / keys ("MilitaryJeep", "ArmedJeep") stay, because saves and ownership key on them.
]]

-- World v2 air box (WorldConfig.Bounds.Air: { X, ZMin, ZMax, MaxY }): the ONE source for the aircraft turn-back law
-- (VehicleDriveClient) and the server validator's air bounds (VehicleService). nil when WorldConfig is missing or
-- malformed: then both sides keep the old numbers (SoftBound / WorldHalfExtent / MaxAltitude).
local AIR_BOX: { X: number, ZMin: number, ZMax: number, MaxY: number }? = nil
do
	local ok, box = pcall(function(): any
		local W: any = require(script.Parent.WorldConfig) -- a missing / broken WorldConfig errors inside the pcall
		return W.Bounds.Air
	end)
	if ok and typeof(box) == "table" then
		local x, z0, z1, y = box.X, box.ZMin, box.ZMax, box.MaxY
		if typeof(x) == "number" and typeof(z0) == "number" and typeof(z1) == "number" and typeof(y) == "number" then
			if x > 0 and z1 > z0 and y > 0 then
				AIR_BOX = { X = x, ZMin = z0, ZMax = z1, MaxY = y }
			end
		end
	end
end

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

--[[ claude-bud JOB 5a (2026-09-29): ROBUX-ONLY vehicles (the Premium* rows in Vehicles). Each clones the best cash
	vehicle of its role (same kit; LookId = its store body / colours) and is only slightly stronger (about +5 % HP and
	armour, +3 % speed; tools/checks/claude_bud_money.py compares). Bought ONLY with its own game pass
	(Premium.PassKey, MonetizationConfig.GamePasses): VehicleService.Purchase refuses cash for any def with Premium,
	RequestSpawn needs the pass and the rollout (MonetizationConfig.SkuLiveFor), pass owners skip the repair wait.
	CostCash 0 is never "free": the Premium check comes first. UnlockLevel 1, no prestige; the spawn structure at L1. ]]
local function P(d: VehicleDef, passKey: string, lookId: string): VehicleDef
	local x: any = d
	x.Premium = { PassKey = passKey }
	x.LookId = lookId
	return d
end

local VehicleConfig = {
	Vehicles = {
		-- ═══ GROUND — early wheeled ═══
		MilitaryJeep = V("MilitaryJeep", "Field 4x4", "Ground", "Common", 1, 200, 55, 4, 10, 0, "WheeledLight", nil),
		UtilityQuad = V("UtilityQuad", "Utility Quad", "Ground", "Common", 2, 160, 58, 2, 8, 3500, "WheeledLight", { Struct = D(1), Scale = 0.75 }),
		ArmedJeep = V("ArmedJeep", "Armed 4x4", "Ground", "Common", 3, 250, 52, 4, 15, 8000, "WheeledLight", { Struct = D(1) }),
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
		-- claude-bud JOB 5a: Robux-only (see P above); base in the comment
		PremiumSkylance = P(V("PremiumSkylance", "Skylance Interceptor", "Air", "Premium", 1, 714, 139, 1, 23, 0, "JetFighter", { Struct = A(1), Scale = 1.05 }), "PV_Skylance", "InterceptorJet"),
		PremiumStormwing = P(V("PremiumStormwing", "Stormwing Gunship", "Air", "Premium", 1, 1155, 77, 2, 40, 0, "HeliAttack", { Struct = H(1), Scale = 1.1 }), "PV_Stormwing", "StealthHeli"),
		PremiumLeviathan = P(V("PremiumLeviathan", "Leviathan Dreadnought", "Naval", "Premium", 1, 4200, 31, 10, 210, 0, "NavalCapital", { Struct = N(1), Scale = 1.55 }), "PV_Leviathan", "Battleship"),
		PremiumTidebreaker = P(V("PremiumTidebreaker", "Tidebreaker Assault Boat", "Naval", "Premium", 1, 504, 60, 3, 29, 0, "NavalPatrol", { Struct = N(1), Scale = 0.88 }), "PV_Tidebreaker", "TorpedoBoat"),
		PremiumWarlord = P(V("PremiumWarlord", "Warlord Siege Tank", "Ground", "Premium", 1, 3780, 19, 4, 210, 0, "TrackedMBT", { Struct = D(1), Scale = 1.6 }), "PV_Warlord", "FortressTank"),
		PremiumRazorfang = P(V("PremiumRazorfang", "Razorfang GT Interceptor", "Ground", "Premium", 1, 315, 70, 2, 21, 0, "WheeledLight", { Struct = D(1), Scale = 0.85 }), "PV_Razorfang", "ReconBuggy"),
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
		--[[ vscale R2 (owner, phone: the cars looked tiny under the avatar; option B shows Roblox-size bodies over the
			unchanged Part kit, so a seated rider's torso starts inside the kit's Cabin / Cargo box). After a rider leaves
			ANY seat (jump / EXIT pill, ejectSeat, a wreck) the server puts the character on a clear spot beside the car:
			on that seat's side, outside the visible body (max(kit WE_HalfWidth, fitted WE_VisualHalfWidth) + Gap + the
			character's HalfWidth from the centreline), at the seat's Z; else the other side; else behind the body; else
			in front of it (those two only while the car moves toward that end slower than EndMaxSpeed); then the same
			four FarStep further out. A spot needs solid ground within StepUp above / MaxDrop below the car's
			wheel line (never water, never the void), an empty standing box (CanCollide parts; this car and characters
			are ignored) and a clear line from the seat. No clear spot = Roblox's own jump-out, as before. Car mode, plus
			(air2 fix2) a plane that wears a fitted body (BodyModes); boats, helicopters and Part-kit planes keep Roblox's
			exit. The plain Part kit (no body) uses its own width. ]]
		ExitSpot = {
			Enabled = true,
			Modes = { Car = true } :: { [string]: boolean },
			Gap = 1, -- studs between the (visible) body side and the character
			HalfWidth = 1, -- the standing character's half width / depth (R15 root part 2 x 2 x 1)
			StandHeight = 5.2, -- open-box height above the ground (a standing blocky R15)
			StepUp = 2.5, -- the ground under the spot may be at most this above the car's wheel line ...
			MaxDrop = 6, -- ... and at most this below it (no cliff, no void)
			FarStep = 3, -- second ring: the same four spots this much further out
			EndMaxSpeed = 3, -- studs/s: behind / in front only while the car moves toward that end slower than this
			MaxFromSeat = 12, -- a rider already this far from the seat (teleported, respawned) is left alone
			-- vscale R2.1: the line of sight to a spot starts inside the kit (chassis centre, above it at the rider's
			-- height, and the seat only when the kit can see it); a world part inside this probe box at the chassis
			-- centre means no move
			AnchorProbe = 0.5,
			NeighbourRange = 60, -- R2.1: other cars within this (chassis to chassis) keep the spot out of their body
			RoofFallback = true, -- R2.1: a seat inside / behind a world part and no clear spot: stand on the kit's roof
			-- R2.2: a spot where the rider's root part would come closer than RiderGap (flat) to another player's root
			-- part, or to a spot handed out in the last HoldSeconds, is taken: riders who leave together (a wreck) or
			-- one after another never land inside each other. Behind / in front also get a spot EndSideStep to either
			-- side (a full car in an alley: two root parts 2 wide + RiderGap).
			RiderGap = 0.25,
			HoldSeconds = 1,
			EndSideStep = 2.5,
			-- per seat: "Left" / "Right" = the car's own left / right (it faces -Z); a seat not listed exits on the side
			-- its centre is on (x < 0 = left; the kit's centred DriverSeat and the bodies' driver seats = left)
			Side = { DriverSeat = "Left" } :: { [string]: string },
			-- air2 fix2: these modes too, but only for a vehicle that wears a fitted body (WE_VisualHalfLength set): its seats
			-- sit inside that body, which never collides, so Roblox's own jump-out lands the rider on the hidden kit inside it
			-- (the owner's 44-stud jet: standing in the fuselage, head out of its top). Beside the wing tip instead; in the
			-- air (no ground within MaxDrop) nothing changes. A Part-kit plane keeps Roblox's own exit, as before.
			BodyModes = { Plane = true } :: { [string]: boolean },
		},
		--[[ vscale R2: passengers board by touch (the moved seats sit inside the kit's Cabin / Cargo, where touch-to-sit
			cannot reach them). One "Ride" ProximityPrompt per car (WE_RidePrompt, on the Chassis): the server enables it
			while a passenger seat is free (WE_Open); VehicleDriveClient hides it from the owner (who drives) and from
			anyone already seated. Triggered seats the player in the nearest free passenger seat after
			VehicleCombatConfig.SeatPolicy.Passenger, only with a clear line from the player to that seat (never through a
			wall or a closed gate). Range = Range + max(kit, fitted body) half length (from the centre). ]]
		Ride = {
			Enabled = true,
			Modes = { Car = true } :: { [string]: boolean },
			Range = 8,
			MaxRise = 6, -- the rider's root part at most this far above / below the Chassis centre (no boarding from a tower)
			HoldSeconds = 0.3, -- a short hold: works with a finger, no accidental boarding
			RequestRate = 2, -- RateLimitService "vehicle_ride" tokens/s
			RequestBurst = 2,
			-- air2 fix2: these modes too, but only for a vehicle that wears a fitted body (WE_VisualHalfLength set) and has a
			-- passenger seat: the body hides its seats inside it, where touch-to-sit cannot reach them (the Trainer Jet's back
			-- seat). A Part-kit plane keeps its visible seats (touch to sit), as before.
			BodyModes = { Plane = true } :: { [string]: boolean },
		},

		--[[ Rollover fix (owner, phone, 2026-09-24: "The quad falls over when driving super easy"). Built once per
			vehicle by VehicleService (createMovers), Car mode only, for the KitFamilies listed in Families:
			  * Ballast: one invisible part (no collide / query / touch) welded to the Chassis between the wheels,
			    BallastHeight of the way from the tyres' ground line up to the axles, weighing Ballast x (kit mass +
			    RiderMass). A seated rider joins the chassis assembly: on the bare quad he was 37 % of the mass, 3 studs
			    above the chassis centre (static stability factor 0.70-0.88 → 1.4-1.8 with ballast + wider track).
			  * WE_DriveAttach (where WE_DriveLV pushes) moves to that centre of mass (rider included), so the drive's
			    cornering / braking force no longer rolls or pitches the car.
			  * WE_UprightAO: roll / pitch only (primary axis = chassis up, yaw free). MaxTorque tops WE_DriveAO up to
			    UprightFrac x weight x min(half track, half wheelbase) — below gravity's own righting moment, so slopes,
			    ramps and landings still follow the ground; it cannot lift a car off its side (flip recovery does).
			  * TrackScale (by vehicle id): physics wheels further out. They are hidden under the fitted body; the Part
			    kit simply shows wider-set wheels.
			Families not listed (tracked, air, naval) get none of this. ]]
		Stability = {
			RiderMass = 14, -- a seated R15 character (~20 cubic studs of body at density 0.7), for sizing only
			RiderLift = 1.3, -- its centre of mass above the driver seat's top face (studs)
			BallastHeight = 0.5, -- 0 = the tyres' ground line, 1 = the axle line
			BallastDensityMax = 100, -- Roblox's CustomPhysicalProperties cap; a heavier ballast grows thicker instead
			DriveAtCoM = true,
			UprightResponsiveness = 12,
			UprightMaxAngularVelocity = 2.5,
			Families = {
				WheeledLight = { Ballast = 1.0, UprightFrac = 0.75 },
				WheeledTruck = { Ballast = 0.4, UprightFrac = 0.6 },
				WheeledAPC = { Ballast = 0.4, UprightFrac = 0.6 },
			} :: { [string]: { Ballast: number, UprightFrac: number } },
			TrackScale = { UtilityQuad = 1.2, ReconBuggy = 1.1, DispatchCar = 1.1 } :: { [string]: number },
			-- vscale R2.3 (review M1): for these families WE_DriveAttach.X also follows the centre of mass, with a
			-- RiderMass rider on every occupied seat (the driver seat when empty). A fitted body seats the driver off
			-- the centreline (Quad / Recon Buggy 1.62 left), and a drive force at x = 0 then turns the car.
			-- {} = the drive point at x = 0 as before (Y / Z at the centre of mass either way).
			DriveAtComXFamilies = { WheeledLight = true } :: { [string]: boolean },
		},

		-- Speed resync (every mode): actual forward speed this far below the commanded speed for
		-- Seconds straight → commanded = actual + gap (a vehicle pushed into a wall never winds up).
		Resync = { Gap = 10, CarGap = 6, Seconds = 0.3, GraceSeconds = 1 },

		Modes = {
			Car = {
				WheeledMinSpeed = 40, -- WE_MaxSpeed = max(def.Speed, 40) (40-68)
				TrackedMinSpeed = 18, -- tracked: clamp(def.Speed, 18, 36)
				TrackedMaxSpeed = 36,
				-- MaxLatAccel (rollover fix): speed-sensitive steering. The turn rate is capped at MaxLatAccel / speed
				-- (studs/s²; 120 = 0.61 g at Gravity 196.2), so full stick at top speed no longer asks for 0.7-1.1 g.
				-- Below 50 studs/s nothing changes (2.4 rad/s x 50 = 120).
				Wheeled = { Accel = 28, Brake = 60, Coast = 10, TurnRate = 2.4, MinTurnFactor = 0.35, Grip = 8, MaxLatAccel = 120 },
				Tracked = { Accel = 16, Brake = 40, Coast = 10, TurnRate = 1.5, MinTurnFactor = 0.7, Grip = 12, MaxLatAccel = 120 },
				ReverseFrac = 0.45, -- reverse max = 0.45 x Max
				ReverseAccelFrac = 0.7, -- reverse accel = Accel x 0.7
				TurnSpeedRef = 12, -- full turn rate from this speed up
				YawResyncRad = 0.6, -- collision spun the car this far off → take the real heading
				--[[ Flip recovery (rollover fix; replaces the old 0.5 s x 15 studs/s hop). Same maths on the driver's client
					(VehicleDriveClient Laws.FlipRecover), in server drive (carStep) and for an empty car (Car idle law).
					On its side or roof (UpY below FlipUpY) and slower than RecoverSpeed for FlipSeconds, with no other
					player within RecoverClearRadius of the car's footprint: X/Z held still, lifted at RecoverLiftSpeed to
					RecoverLift studs above where it lay while WE_DriveAO levels it (at most RecoverSpin rad/s), then lowered
					at RecoverLiftSpeed until it touches down. Ends when down, after RecoverMaxSeconds, or when it has moved
					more than RecoverMaxStuds from the start (then it just drops). RecoverCooldown seconds between tries and
					at most RecoverMaxPerMinute starts per minute. No remote, no teleport: only the movers' targets.
					While UpY is below FlipUpY the car also has no traction and no steering (the commanded speed brakes to 0):
					the old law drove a car on its side along the ground at full speed, so it never stopped to be righted. ]]
				FlipUpY = 0.5, -- UpVector.Y below this = tilted past 60° (a ballasted quad tips over by itself at ~61°) ...
				FlipSeconds = 1.5, -- ... and slower than RecoverSpeed this long → right it
				RecoverSpeed = 3,
				RecoverLift = 2.5,
				RecoverLiftSpeed = 6,
				RecoverDoneUpY = 0.9,
				RecoverMaxSeconds = 2.5,
				RecoverMaxStuds = 5,
				RecoverCooldown = 4,
				RecoverMaxPerMinute = 5,
				RecoverClearRadius = 4,
				RecoverSpin = 2.5,
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

		--[[ JEEP-2: World v2 air box. Box = WorldConfig.Bounds.Air (the air wall stands on its edges, 700 tall, NO roof).
			Client law (Heli + Plane, VehicleDriveClient Laws.Step): inside Band studs of a side edge while moving outward
			the stick is steered toward the box centre (+ a heading assist), and the outward speed is capped at
			(room - Buffer) x EdgeGain, so an aircraft stops Buffer studs inside the edge (and is pushed back in when it
			is past it). Ceiling = min(WE_MaxAltitude, Box.MaxY): climbing tapers over CeilBand to 0 at CeilBuffer below
			it; above it the aircraft sinks at up to CeilSink. The pilot sees the "Restricted airspace" line.
			Server (VehicleService validateSample, Heli + Plane): "bounds" only past the box edges + ValidatorSlack while
			still moving out (or past Validation.WorldHalfExtent), "altitude" only above the ceiling +
			Validation.AirAltitudeSlack — never inside the box. ]]
		AirBox = {
			Enabled = true, -- false = the old behaviour (SoftBound 3300, WorldHalfExtent, MaxAltitude) on both sides
			Box = AIR_BOX,
			Band = 160, -- studs inside a side edge where the turn-back starts (at least; planes add LeadSeconds x speed)
			LeadSeconds = 1.6, -- a plane at 200 studs/s starts turning 30 + 320 studs from the edge
			Buffer = 30, -- aircraft stop this far inside a side edge
			EdgeGain = 0.6, -- heli: outward speed cap = (room - Buffer) x this (per second); past Buffer it pushes back in
			PlaneEdgeGain = 1.5, -- plane: the same cap as a late backstop (never negative); the turn comes first
			PushFrac = 0.5, -- airborne heli past the Buffer: pushed back in at most this x its max speed per axis (0 on the ground)
			OutwardSpeed = 2, -- moving outward faster than this (studs/s) inside Band = the guard steers
			SteerGain = 2, -- stick override = heading error (rad) x this, clamped to [-1, 1]
			AssistYawRate = 0.8, -- rad/s heading assist at the edge (scaled by depth into Band)
			CeilBand = 100, -- climb tapers to 0 over this many studs below the ceiling
			CeilBuffer = 10, -- ... reaching 0 this far below it
			CeilGain = 1.0, -- climb cap = (ceiling - CeilBuffer - y) x this (per second)
			CeilSink = 20, -- above the ceiling: sink at up to this (studs/s)
			NoticeHoldSeconds = 1.5, -- the "Restricted airspace" line stays up this long after the guard lets go
			Notice = "Restricted airspace — turning back", -- device-neutral (no key names), in the vehicle hint slot
			ValidatorSlack = 60, -- server: "bounds" only this far past a side edge (the law stops at -Buffer) ...
			ValidatorOutwardSpeed = 8, -- ... and only while still moving out through it faster than this (studs/s)
		},

		-- W7 (mobile plan P2): where the SPD pill and the hint line sit. Touch: HudLayout's top-centre stack right under
		-- the Progress slot (HudConfig.TopStack.Order.Progress = 20, Objective = 30), so the capture bar can never cover
		-- them. Desktop / gamepad: the pill takes the ammo readout's slot (bottom-right; combat is hidden while seated).
		Hud = {
			PillStackOrder = 25,
			HintStackOrder = 26,
			DiagStackOrder = 27,
			StackWidthScale = 0.62, -- = HudConfig.TopStack.MaxWidthScale (hint / diag lines in the stack)
			DesktopPillInset = 14, -- desktop pill: this many px in from the bottom-right corner (the ammo slot)
		},

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
			-- streaming2 S3 (F8): when the seat is further than StreamingConfig.NearStuds (64) from the player, the
			-- server calls Player:RequestStreamAroundAsync at the spot on the seat where it will put the player, and
			-- waits for it before the move. This is the request timeout in seconds. The sit happens when the request
			-- returns or times out. Read only while Workspace.StreamingEnabled is true.
			AutoSitPrefetchTimeout = 3,
			DamageLockSeconds = 5, -- SPAWN refused this long after the player's character took damage
			-- the Drive prompt's MaxActivationDistance from the driver seat; vscale R2: a fitted body longer than the kit
			-- adds its overhang (WE_VisualHalfLength - WE_HalfLength), so "Drive" still shows at a Roblox-size tailgate.
			-- The spawn spot checks (Occupied, BoxFree, aroundOffsets, PlayerFront) use max(kit, fitted body) too.
			DrivePromptRange = 14,
			PlayerClear = 1.5, -- vscale R2: PlayerFront never puts the car (kit or fitted body) within this of the player's root part
			-- vscale R2.1: a pad's second ring (after the centre + 4 spots) sits footRadius + the biggest parked car's
			-- radius + 2 + this from the pad centre, so a Roblox-size van / pickup parked there never sends a smaller car
			-- to another player's pad
			RingMargin = 0.5,
			-- vscale R2.1: SPAWN tries spots clear of tall visible non-colliding decor first (flag poles, palms, reeds,
			-- lintels, the Garage sign: CanQuery false, so an index built from one Workspace pass, refreshed at most every
			-- RefreshSeconds and only when a SPAWN asks), then as before. Enabled = false: R2 behaviour.
			Decor = {
				Enabled = true,
				MinTop = 2.5, -- only decor whose top stands more than this over the spot's ground (not grass, kerbs, decals)
				Tolerance = 0.25, -- overlap depth (studs) that counts
				MaxTransparency = 0.9,
				MaxSize = 80, -- longer parts (ground sheets, zone discs) are not indexed
				Cell = 32,
				RefreshSeconds = 300,
			},
		},

		--[[ fb4 water rule (owner, phone, 2026-09-28: "I can drive on water which shouldn't happen"). Every WE_Water part
			spans BottomY 0.3 .. SurfaceY 1.5 over a desert floor at 0.5 and collides with nothing, so a car used to roll on
			the sand one stud under the see-through sheet. The SERVER decides (Modules/VehicleWaterGuard, called from
			VehicleService at Hz per vehicle: a flat-rectangle test of the chassis against the tagged WE_Water parts, no
			scans); the driver's client (VehicleDriveClient) mirrors it only for feel. Geometry: Shared/Util/WaterRule.
			  * In water = the chassis centre at least EnterDepth studs inside water (the four points EnterDepth away along
			    +-X / +-Z are water too, so seams between water parts count as water), with the wheel line (chassis Y -
			    WE_GroundClearance) at most WheelAbove over that water's surface: never on a pier, pontoon, kerb or rig
			    footing. A driven Car chassis held up to HoverMaxStuds over deep water with nothing solid under it (one ray,
			    only then; a kerb, pontoon, pier, deck or boat under it holds it up) counts as in the water too, and so does
			    one whose wheel line is more than WheelBelow under the surface (under the sand: nothing is down there). Out again =
			    the centre less than ExitDepth inside (a tenth of a stud of hysteresis: a car that ran along the beach less than
			    EnterDepth in, then into a canal mouth, is out again once it is back where it ran). The sand bank never counts.
			  * Car-mode vehicles BOG, one way. The WAY OUT is the outward normal of the bank it came over (found on the line
			    back to where it was at the last check before it went in, looked for up to EntrySearchStuds; a shallow
			    drift that finds no land on that line takes the bank nearest that last check). A move that would take it
			    deeper along that normal is not allowed: the throttle is cut and the drive law brakes at BogBrake studs/s²
			    down to BogAwaySpeed (0). A move that does not (backing out, or turned toward the bank) may go up to
			    max(BogExitMin, BogExitFrac x its max speed), reverse included. Forward needs the car to face the bank;
			    reverse is allowed along the bank and while it faces the bank by up to ReverseBand (the heading . the
			    normal; ~5°), so a turn while backing out never locks it. BackOutSteerLock: while it backs out (stick back)
			    a sideways thumb never turns its nose past along-the-bank toward it (reverse would stop there; it still
			    turns the other way). So it can never drive deeper (only back a little deeper, slowly, inside that band),
			    and never reach the far bank. The ENTRY (where riders go back to) is on
			    the land it came from, EntryPush studs past the bank.
			    With no bank known (never for a normal drive-in) it is BogSpeed both ways. Every rider sees Message once (at
			    most every MessageGapSeconds) and the driver's speed pill shows which way works: PillTag while backing out
			    works, PillTagForward once it faces the bank by more than ReverseBand (back to PillTag below half of that:
			    no flicker). No key names anywhere (phones).
			  * Crossing: a ground vehicle that comes out on another shore (the straight line from its entry to where it
			    came out runs over CrossDeepStuds of deep water in a row, tested every CrossStep studs, and is at least
			    CrossMinStuds long) sinks at once and its riders go back to the entry side. One that is out of the water at
			    two checks in a row on either side of it (a client that jumps the chassis across, or a lag burst round a
			    water notch) is put back where it was by the validator's correction: no sink, no message. A move the server
			    makes itself (the validator's correction) is never taken for such a jump. The entry is always on land, so
			    the crossing test from it always runs (only a point on a kerb, pontoon or pier is exempt).
			    One that went in on public (or its own) water and reaches another player's DockWater / SeaGateWater (it
			    slid along toward that base through an open sea gate) sinks at once.
			  * Still in water GraceSeconds after it stopped going deeper (the grace starts at the bog, and moves on while
			    it still goes deeper during the first BogSettleSeconds), or once BogSettleSeconds have passed still faster
			    than its exit cap x Validation.SpeedTolerance + Validation.SpeedSlack (or going deeper faster than
			    Validation.SpeedSlack) for FastSamples checks (a client that ignores the bog): every rider is put on dry land
			    (round the entry if it is within ReturnMaxStuds; else the R2.3 exit spot beside it; else the nearest bank
			    within ShoreSearchStuds with a clear line from the vehicle and never on another player's plot; else, with no
			    distance cap, the nearest clear dry spot inside PlayArea found on rings out to DitchShoreStuds, never on
			    another player's plot; a spot on the far side of the water from the entry is never used), facing away from
			    the water, and the vehicle sinks (collisions off, down at SinkSpeed for SinkSeconds) and is removed. No
			    charge, no repair lock: the normal spawn cooldown only, so the garage deploys it again. The owner then gets
			    SinkMessage ("" = none), only once the water line has gone (one message at a time).
			    Getting out keeps the grace: each time it is ProgressStuds shallower than ever before, at least
			    ProgressHoldSeconds are left, up to GraceMaxSeconds after the bog (a shallow drift backs out slowly).
			  * Amphibious ids wade instead: speed held at WadeSpeedFrac x their max speed in public water and in their own
			    plot's water, no entry; another player's DockWater / SeaGateWater is BogSpeed both ways with
			    ForeignGraceSeconds (riders go to a bank outside that plot first).
			  * Plane mode: wheels in water = no cap and no crossing test; the pill shows PlaneTag and the riders see
			    PlaneMessage. While the pilot is seated and it still rolls at PlaneLiftFrac x its lift-off speed
			    (WE_TakeoffSpeed) or more, or gains speed (a take-off run), it can still take off, so the grace waits (up to
			    PlaneLiftMaxSeconds after it touched the water: it never taxis along as a boat). GraceSeconds of braking,
			    rolling to a stop or standing = ditched: every rider goes to the spot beside it, else the nearest clear dry
			    spot (no distance cap: rings out to DitchShoreStuds inside PlayArea, never on another player's plot), the
			    plane sinks and goes back to the garage (no charge). A rider who taps EXIT while it sits on the water goes
			    ashore the same way. Heli and Boat modes: never (a heli that lands on water floats there until it lifts off).
			  * An empty vehicle in water sinks after the grace too. Land spawns (pads, plot fallback) never pick a spot
			    over water (VehicleService firstFreeLand / firstFreePlotLand).
			Enabled = false: the old behaviour (nothing is checked, nothing is capped). ]]
		WaterRule = {
			Enabled = true,
			Hz = 10, -- server checks per vehicle per second (the client mirror uses the same rate)
			EnterDepth = 2,
			ExitDepth = 1.9, -- out again when the centre is less than this far inside (just under EnterDepth: a beach run back
			-- out of a canal mouth is out; 0.1 stud is still far more than a resting car's jitter, so no flicker)
			WheelAbove = 0.3, -- water top 1.5 + 0.3: a DockKerb (top 2.0) or a pontoon (2.1) is not water
			WheelBelow = 8, -- the wheel line at most this far under the surface (deeper = something else, not this water)
			HoverMaxStuds = 160, -- a driven Car chassis up to this far over deep water with nothing under it is in the water (> Validation.GroundMaxY: any height a car may reach)
			BogSpeed = 8, -- studs/s both ways when there is no way out known (amphibious in another player's plot water)
			BogAwaySpeed = 0, -- studs/s deeper along the way out: throttle cut (a car can never carry on across)
			BogExitFrac = 0.45, -- not deeper (back out, or turned to the bank): up to this x max speed (the normal reverse) ...
			BogExitMin = 16, -- ... and never less than this, reverse included (slow tanks back out at 16 too)
			BogBrake = 250, -- studs/s² (the Car LV's ForcePerMass): 82 → 0 in 0.33 s
			EntryPush = 4, -- the entry: this far onto the land past the bank it came over ...
			EntrySearchStuds = 160, -- ... looked for this far back along its line (a 1° drift finds it)
			GraceSeconds = 3, -- from when it stopped going deeper
			ProgressStuds = 0.1, -- getting out: this much shallower than ever before ...
			ProgressHoldSeconds = 1, -- ... leaves at least this much grace ...
			GraceMaxSeconds = 10, -- ... until this long after the bog
			BogSettleSeconds = 1.5, -- the cheat check starts this long after the bog (covers ~1 s of phone ping)
			FastSamples = 2,
			ForeignGraceSeconds = 1,
			CrossMinStuds = 12, -- a line shorter than this is never a crossing
			CrossDeepStuds = 16, -- a crossing: this many studs of deep water in a row on the line (channels are 40 wide)
			CrossStep = 2,
			Message = "Vehicles can't drive in water",
			PlaneMessage = "Planes can't land on water", -- the same line for a plane (no key names)
			MessageGapSeconds = 8,
			PillTag = "BACK OUT", -- facing the water: backing out works
			PillTagForward = "DRIVE OUT", -- facing the bank (turned, or it went in backwards): driving out works
			ReverseBand = 0.09, -- reverse stays allowed while it faces the bank by up to this (heading . normal, ~5°)
			BackOutSteerLock = true, -- backing out: the thumb never turns the nose past along-the-bank (both Car laws)
			PlaneTag = "IN WATER",
			-- a plane on the water whose pilot can still take off: at PlaneLiftFrac x WE_TakeoffSpeed or more, or gaining
			-- more than PlaneGainStuds studs/s per check (a take-off run); its grace waits, up to PlaneLiftMaxSeconds
			-- after it touched the water (so it never taxis along as a boat)
			PlaneLiftFrac = 1,
			PlaneGainStuds = 0.5,
			PlaneLiftMaxSeconds = 3,
			-- after the sink, to the owner only, once the water line has gone (one message at a time; "" = none)
			SinkMessage = "Vehicle safe in garage",
			SinkMessageSeconds = 3,
			SinkSeconds = 1.2,
			SinkSpeed = 5,
			ReturnMaxStuds = 80,
			ShoreSearchStuds = 120,
			ShoreStep = 4,
			ShoreMargin = 2, -- a rider's spot stays this far from any water's edge
			-- nobody is ever left in the water: the last choice (and a ditched plane's first after the spot beside it) is
			-- the nearest clear dry spot on rings round the vehicle, ShoreStep apart up to ShoreSearchStuds, then
			-- DitchStep apart up to DitchShoreStuds (the whole map), about DitchArcStuds apart round each ring, at most
			-- DitchTries full spot checks, inside PlayArea (the dry land inside the ring canal and north of the sea:
			-- WorldConfig header; never the outer strip or the far shore) and never on another player's plot
			DitchShoreStuds = 2400,
			DitchStep = 12,
			DitchArcStuds = 24,
			DitchTries = 40,
			PlayArea = { X = 1760, ZMin = -1760, ZMax = 1490 },
			PlaceTries = 5, -- a rider still welded to the seat is retried every 0.1 s this many times
			Amphibious = { AmphibiousAPC = true } :: { [string]: boolean },
			-- v90 (owner 2026-09-28: "Bridge Layer should be able to cross water"): these ids wade like Amphibious ids, but only
			-- for the rollout named here ("owner" = the playtest owner's own vehicles, AdminConfig.IsPlaytestOwner; "all" =
			-- everyone; anything else = nobody). Server-authoritative (VehicleWaterGuard kindOf); the driver's client follows
			-- the server's WE_WaterState "Wade".
			AmphibiousRollout = { BridgeLayer = "owner" } :: { [string]: string },
			WadeSpeedFrac = 0.4,
		},
	},
}

return VehicleConfig
