--!strict
--[[
	Optional free Creator Store Model asset IDs for InsertService / AssetService.
	Part kits remain the authoritative fallback (always). Never use paid / MT-branded assets.

	Studio PERF: when DevConfig.StudioSkipWorldDressing and not StudioForceDress,
	VisualAssetService skips catalog inserts (8GB laptop). Live servers may load.

	IDs researched as Free / Get Model on Creator Store (economy IsForSale=false Price=nil).
	Never paid / never MT-branded. AssetId=0 means skip insert (Part kit only).
	Verify in Studio; enable Game Settings → Security → Allow Loading Third Party Assets
	(and AllowInsertFreeAssets where required) for third-party models.
]]

export type AssetRef = {
	ModelAssetId: number?, -- InsertService / AssetService:LoadAssetAsync catalog Model
	MeshId: number?, -- optional SpecialMesh / MeshPart MeshId (0 = unused)
	Note: string?,
}

local VisualAssetConfig = {
	Enabled = true,
	StripScripts = true,
	MaxLoadAttempts = 48,
	VehicleVisualScale = 1.0,
	CharacterVisualScale = 1.0,
	BuildingVisualScale = 1.0,
	PropVisualScale = 1.0,

	Vehicles = {
		-- Free Jeep family
		MilitaryJeep = { ModelAssetId = 125916936788670, Note = "Military Car (prefer); fallback 59524622" } :: AssetRef,
		ArmedJeep = { ModelAssetId = 125916936788670, Note = "Military Car reuse" } :: AssetRef,
		UtilityQuad = { ModelAssetId = 125916936788670, Note = "Military Car reuse (scaled)" } :: AssetRef,
		ScoutCar = { ModelAssetId = 125916936788670, Note = "Military Car reuse" } :: AssetRef,
		ReconBuggy = { ModelAssetId = 125916936788670, Note = "Military Car reuse" } :: AssetRef,
		-- Free tank family
		LightTank = { ModelAssetId = 26007709, Note = "Free tank (Creator Store)" } :: AssetRef,
		MediumTank = { ModelAssetId = 26007709, Note = "Tank reuse" } :: AssetRef,
		BattleTank = { ModelAssetId = 19297043, Note = "Mammoth MBT" } :: AssetRef,
		HeavyTank = { ModelAssetId = 19297043, Note = "Mammoth heavy" } :: AssetRef,
		SuperHeavyTank = { ModelAssetId = 19297043, Note = "Mammoth super heavy" } :: AssetRef,
		TankDestroyer = { ModelAssetId = 19297043, Note = "Mammoth TD" } :: AssetRef,
		AssaultGun = { ModelAssetId = 19297043, Note = "Mammoth AG" } :: AssetRef,
		-- Free heli family
		TransportHeli = { ModelAssetId = 9753309, Note = "Transport heli" } :: AssetRef,
		AttackHelicopter = { ModelAssetId = 295607934, Note = "Gunship heli" } :: AssetRef,
		LightTransportHeli = { ModelAssetId = 5935419, Note = "Light/utility heli" } :: AssetRef,
		NightAttackHeli = { ModelAssetId = 295607934, Note = "Gunship heli" } :: AssetRef,
		LightScoutHeli = { ModelAssetId = 5935419, Note = "Light/utility heli" } :: AssetRef,
		GunshipHeli = { ModelAssetId = 295607934, Note = "Gunship heli" } :: AssetRef,
		HeavyLiftHeli = { ModelAssetId = 9753309, Note = "Transport heli heavy-lift" } :: AssetRef,
		RescueHeli = { ModelAssetId = 5935419, Note = "Light/utility heli" } :: AssetRef,
		StealthHeli = { ModelAssetId = 295607934, Note = "Gunship/stealth heli" } :: AssetRef,
		-- Classic free pack (trucks / APC fallback)
		_FallbackWheeled = { ModelAssetId = 28912351, Note = "Military Vehicle Meshes pack (free)" } :: AssetRef,
		PatrolTruck = { ModelAssetId = 105503568352704, Note = "Military truck prefer" } :: AssetRef,
		ArmoredTruck = { ModelAssetId = 105503568352704, Note = "Military truck prefer" } :: AssetRef,
		APC = { ModelAssetId = 17835143223, Note = "APC prefer" } :: AssetRef,
		-- Free jet family (classic + named free fighter)
		_FallbackJet = { ModelAssetId = 4865838, Note = "Classic free fighter jet" } :: AssetRef,
		FighterJet = { ModelAssetId = 4865838, Note = "Classic free fighter jet" } :: AssetRef,
		InterceptorJet = { ModelAssetId = 4865838, Note = "Fighter reuse" } :: AssetRef,
		TrainerJet = { ModelAssetId = 4865838, Note = "Fighter reuse" } :: AssetRef,
		ReconPlane = { ModelAssetId = 4865838, Note = "Fighter reuse" } :: AssetRef,
		LightFighter = { ModelAssetId = 4865838, Note = "Fighter reuse" } :: AssetRef,
		StrikeJet = { ModelAssetId = 5507592781, Note = "Strike/CAS jet" } :: AssetRef,
		CASJet = { ModelAssetId = 5507592781, Note = "Strike/CAS jet" } :: AssetRef,
		StealthStrikeJet = { ModelAssetId = 5507592781, Note = "Strike/CAS jet" } :: AssetRef,
		StrikeBomber = { ModelAssetId = 3319732457, Note = "Bomber/cargo/AWACS family" } :: AssetRef,
		CargoPlane = { ModelAssetId = 3319732457, Note = "Bomber/cargo/AWACS family" } :: AssetRef,
		AWACSPlane = { ModelAssetId = 3319732457, Note = "Bomber/cargo/AWACS family" } :: AssetRef,
		TankerPlane = { ModelAssetId = 3319732457, Note = "Bomber/cargo/AWACS family" } :: AssetRef,
		-- Free naval family
		_FallbackNaval = { ModelAssetId = 15786579439, Note = "Free Boat (Creator Store)" } :: AssetRef,
		PatrolBoat = { ModelAssetId = 15786579439, Note = "Free Boat" } :: AssetRef,
		FastAttackCraft = { ModelAssetId = 15786579439, Note = "Boat reuse" } :: AssetRef,
		RiverBoat = { ModelAssetId = 15786579439, Note = "Boat reuse" } :: AssetRef,
		CoastCutter = { ModelAssetId = 15786579439, Note = "Boat reuse" } :: AssetRef,
		TorpedoBoat = { ModelAssetId = 15786579439, Note = "Boat reuse" } :: AssetRef,
		Gunboat = { ModelAssetId = 15786579439, Note = "Boat reuse" } :: AssetRef,
		MissileBoat = { ModelAssetId = 15786579439, Note = "Boat reuse" } :: AssetRef,
		MineLayer = { ModelAssetId = 15786579439, Note = "Boat reuse" } :: AssetRef,
		CoastalMonitor = { ModelAssetId = 15786579439, Note = "Boat reuse" } :: AssetRef,
		LandingCraft = { ModelAssetId = 13195201090, Note = "Build a Boat Template (free)" } :: AssetRef,
		AssaultLanding = { ModelAssetId = 13195201090, Note = "Boat template reuse" } :: AssetRef,
		HoverTransport = { ModelAssetId = 13195201090, Note = "Boat template reuse" } :: AssetRef,
		HospitalShip = { ModelAssetId = 13195201090, Note = "Boat template reuse" } :: AssetRef,
		SupplyShip = { ModelAssetId = 13195201090, Note = "Boat template reuse" } :: AssetRef,
		AmphibAssault = { ModelAssetId = 13195201090, Note = "Boat template reuse" } :: AssetRef,
		Corvette = { ModelAssetId = 13195201090, Note = "Boat template reuse (capital)" } :: AssetRef,
		Destroyer = { ModelAssetId = 13195201090, Note = "Boat template reuse" } :: AssetRef,
		Frigate = { ModelAssetId = 13195201090, Note = "Boat template reuse" } :: AssetRef,
		CarrierEscort = { ModelAssetId = 13195201090, Note = "Boat template reuse" } :: AssetRef,
		Battleship = { ModelAssetId = 13195201090, Note = "Boat template reuse" } :: AssetRef,
		AircraftCarrier = { ModelAssetId = 13195201090, Note = "Boat template reuse" } :: AssetRef,
		SubSurfaceRunner = { ModelAssetId = 15786579439, Note = "Boat reuse (surface stub)" } :: AssetRef,
		AttackSub = { ModelAssetId = 15786579439, Note = "Boat reuse (surface stub)" } :: AssetRef,
		-- Explicit aliases for depth-pass IDs (KitFamilyFallback also covers these)
		SupplyTruck = { ModelAssetId = 107381977457431, Note = "Military supply truck prefer" } :: AssetRef,
		FuelTanker = { ModelAssetId = 28912351, Note = "Mesh pack truck" } :: AssetRef,
		EngineeringTruck = { ModelAssetId = 28912351, Note = "Mesh pack truck" } :: AssetRef,
		FlatbedHauler = { ModelAssetId = 28912351, Note = "Mesh pack truck" } :: AssetRef,
		AmmoCarrier = { ModelAssetId = 28912351, Note = "Mesh pack truck" } :: AssetRef,
		MissileTruck = { ModelAssetId = 28912351, Note = "Mesh pack truck" } :: AssetRef,
		AntiAirTruck = { ModelAssetId = 28912351, Note = "Mesh pack truck" } :: AssetRef,
		RadarTruck = { ModelAssetId = 28912351, Note = "Mesh pack truck" } :: AssetRef,
		CargoVan = { ModelAssetId = 28912351, Note = "Mesh pack truck" } :: AssetRef,
		TroopTransport = { ModelAssetId = 28912351, Note = "Mesh pack truck" } :: AssetRef,
		RecoveryTruck = { ModelAssetId = 28912351, Note = "Mesh pack truck" } :: AssetRef,
		EscortTruck = { ModelAssetId = 28912351, Note = "Mesh pack truck" } :: AssetRef,
		InfantryCarrier = { ModelAssetId = 28912351, Note = "APC/mesh pack" } :: AssetRef,
		CommandVehicle = { ModelAssetId = 28912351, Note = "APC/mesh pack" } :: AssetRef,
		WheeledIFV = { ModelAssetId = 28912351, Note = "APC/mesh pack" } :: AssetRef,
		AmphibiousAPC = { ModelAssetId = 28912351, Note = "APC/mesh pack" } :: AssetRef,
		CombatIFV = { ModelAssetId = 26007709, Note = "Tank family IFV" } :: AssetRef,
		AssaultIFV = { ModelAssetId = 26007709, Note = "Tank family IFV" } :: AssetRef,
		BridgeLayer = { ModelAssetId = 26007709, Note = "Tracked reuse" } :: AssetRef,
		MineClearer = { ModelAssetId = 26007709, Note = "Tracked reuse" } :: AssetRef,
		FlameCarrier = { ModelAssetId = 26007709, Note = "Tracked reuse" } :: AssetRef,
		SPAAG = { ModelAssetId = 26007709, Note = "Tank SPAAG reuse" } :: AssetRef,
		MobileSAM = { ModelAssetId = 26007709, Note = "Tank SAM reuse" } :: AssetRef,
		MortarCarrier = { ModelAssetId = 26007709, Note = "Artillery reuse" } :: AssetRef,
		MobileArtillery = { ModelAssetId = 26007709, Note = "Artillery reuse" } :: AssetRef,
		RocketArtillery = { ModelAssetId = 26007709, Note = "Artillery reuse" } :: AssetRef,
		HowitzerTruck = { ModelAssetId = 26007709, Note = "Artillery reuse" } :: AssetRef,
		SiegeMortar = { ModelAssetId = 26007709, Note = "Artillery reuse" } :: AssetRef,
		LightScoutTank = { ModelAssetId = 26007709, Note = "Light tank reuse" } :: AssetRef,
		FortressTank = { ModelAssetId = 19297043, Note = "Mammoth fortress" } :: AssetRef,
		RailgunCarrier = { ModelAssetId = 19297043, Note = "Mammoth railgun" } :: AssetRef,
		DispatchCar = { ModelAssetId = 125916936788670, Note = "Military Car reuse" } :: AssetRef,
		UtilityHeli = { ModelAssetId = 5935419, Note = "Light/utility heli" } :: AssetRef,
		MedevacHeli = { ModelAssetId = 5935419, Note = "Light/utility heli" } :: AssetRef,
		EscortHeli = { ModelAssetId = 295607934, Note = "Gunship escort" } :: AssetRef,
		VTOLTransport = { ModelAssetId = 9753309, Note = "Transport heli VTOL" } :: AssetRef,
		HeavyBomber = { ModelAssetId = 3319732457, Note = "Bomber/cargo/AWACS family" } :: AssetRef,
		StealthStrike = { ModelAssetId = 5507592781, Note = "Strike/CAS jet" } :: AssetRef,
		-- Depth-pass capital / bomber IDs previously missing from catalog map
		Cruiser = { ModelAssetId = 13195201090, Note = "Boat template capital" } :: AssetRef,
		MissileCruiser = { ModelAssetId = 13195201090, Note = "Boat template capital" } :: AssetRef,
		FleetCarrier = { ModelAssetId = 13195201090, Note = "Boat template carrier" } :: AssetRef,
		StrategicBomber = { ModelAssetId = 3319732457, Note = "Bomber/cargo/AWACS family" } :: AssetRef,
	} :: { [string]: AssetRef },

	Characters = {
		-- Free Get Model / Roblox official — scripts stripped at insert. Part kits remain fallback.
		Soldier = { ModelAssetId = 3924234975, Note = "Official Roblox Soldier (Rthro)" } :: AssetRef,
		Infantry = { ModelAssetId = 3924234975, Note = "Soldier reuse (Infantry NPC)" } :: AssetRef,
		HeavyInfantry = { ModelAssetId = 91299598767068, Note = "Respawn Soldiers pack (free)" } :: AssetRef,
		Guard = { ModelAssetId = 91299598767068, Note = "Guard (Respawn Soldiers / alt 23231587)" } :: AssetRef,
		BankGuard = { ModelAssetId = 91299598767068, Note = "BankGuard (alt 23231587)" } :: AssetRef,
		OilRigGuard = { ModelAssetId = 91299598767068, Note = "OilRigGuard (alt 23231587)" } :: AssetRef,
		FortGuard = { ModelAssetId = 91299598767068, Note = "Respawn Soldiers pack (fort)" } :: AssetRef,
	} :: { [string]: AssetRef },

	Buildings = {
		-- Free Barracks / HQ / hangar / dock (Get Model). Part kits remain primary fallback.
		CommandCenter = { ModelAssetId = 138331074285379, Note = "Military Base free Get Model (HQ)" } :: AssetRef,
		Barracks = { ModelAssetId = 9424782, Note = "Barracks free Get Model (2009)" } :: AssetRef,
		VehicleDepot = { ModelAssetId = 12120702, Note = "Classic Warehouse free (depot)" } :: AssetRef,
		WeaponsFacility = { ModelAssetId = 4120970784, Note = "Weapons facility" } :: AssetRef,
		Warehouse = { ModelAssetId = 66269964, Note = "Warehouse" } :: AssetRef,
		Hangar = { ModelAssetId = 6015472062, Note = "Hangar overlay" } :: AssetRef,
		ResearchLab = { ModelAssetId = 17725725, Note = "Research lab" } :: AssetRef,
		SpecialForcesFacility = { ModelAssetId = 18798977801, Note = "Special forces facility" } :: AssetRef,
		Watchtowers = { ModelAssetId = 3330023556, Note = "Watchtower" } :: AssetRef,
		Radar = { ModelAssetId = 9559610195, Note = "Radar" } :: AssetRef,
		MissileDefense = { ModelAssetId = 108525417345747, Note = "Missile defense (fallback 16659447)" } :: AssetRef,
		DefensiveWalls = { ModelAssetId = 208197704, Note = "Defensive walls" } :: AssetRef,
		PowerStation = { ModelAssetId = 14000967030, Note = "Power station" } :: AssetRef,
		Bunker = { ModelAssetId = 16659447, Note = "Destructible Movil Bunker free" } :: AssetRef,
		Helipad = { ModelAssetId = 14313845338, Note = "Airport free Get Model (pad/hangar)" } :: AssetRef,
		Airfield = { ModelAssetId = 12370174722, Note = "Airport Model free Get Model" } :: AssetRef,
		Dock = { ModelAssetId = 17701461178, Note = "Shipping Containers free (dockside)" } :: AssetRef,
	} :: { [string]: AssetRef },

	JeepFallback = { ModelAssetId = 59524622, Note = "Classic free Jeep fallback only" } :: AssetRef,

	WarzoneProps = {
		Sandbags = { ModelAssetId = 3525056989, Note = "Warzone prop" } :: AssetRef,
		Crate = { ModelAssetId = 12651656400, Note = "Warzone prop" } :: AssetRef,
		Barrier = { ModelAssetId = 25733125, Note = "Warzone prop" } :: AssetRef,
		Cone = { ModelAssetId = 91071319, Note = "Warzone prop" } :: AssetRef,
		Drum = { ModelAssetId = 53591587, Note = "Warzone prop" } :: AssetRef,
		Pallet = { ModelAssetId = 976333542, Note = "Warzone prop" } :: AssetRef,
		CamoNet = { ModelAssetId = 16382915010, Note = "Warzone prop" } :: AssetRef,
		Fence = { ModelAssetId = 25623924, Note = "Warzone prop" } :: AssetRef,
		AmmoBox = { ModelAssetId = 1291725699, Note = "Warzone prop" } :: AssetRef,
		Tent = { ModelAssetId = 6883609157, Note = "Warzone prop" } :: AssetRef,
		Radio = { ModelAssetId = 19277831, Note = "Warzone prop" } :: AssetRef,
		Lamp = { ModelAssetId = 116763933, Note = "Warzone prop" } :: AssetRef,
	} :: { [string]: AssetRef },

	DesertProps = {
		Cactus = { ModelAssetId = 121029612, Note = "Free Cactus Get Model" } :: AssetRef,
		CactusBase = { ModelAssetId = 16354482789, Note = "CactusBase2 free Get Model" } :: AssetRef,
		DesertPlants = { ModelAssetId = 108556425657107, Note = "Realistic Desert Plants free pack" } :: AssetRef,
	} :: { [string]: AssetRef },

	KitFamilyFallback = {
		WheeledLight = "MilitaryJeep",
		WheeledTruck = "_FallbackWheeled",
		WheeledAPC = "APC",
		TrackedIFV = "LightTank",
		TrackedMBT = "BattleTank",
		TrackedSPAAG = "LightTank",
		TrackedArtillery = "LightTank",
		HeliTransport = "TransportHeli",
		HeliAttack = "AttackHelicopter",
		HeliLight = "TransportHeli",
		JetFighter = "_FallbackJet",
		JetStrike = "StrikeJet",
		JetBomber = "StrikeBomber",
		JetTransport = "CargoPlane",
		NavalPatrol = "_FallbackNaval",
		NavalGun = "_FallbackNaval",
		NavalLanding = "LandingCraft",
		NavalCapital = "LandingCraft",
		NavalSub = "_FallbackNaval",
	} :: { [string]: string },
}

return VisualAssetConfig
