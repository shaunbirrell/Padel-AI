--!strict
--[[
	Optional free Creator Store Model asset IDs for InsertService / AssetService.
	Part kits remain the authoritative fallback (always). Never use paid / MT-branded assets.

	Studio PERF: when DevConfig.StudioSkipWorldDressing and not StudioForceDress,
	VisualAssetService skips catalog inserts (8GB laptop). Live servers may load.

	IDs researched as Free / Get Model on Creator Store (economy IsForSale=false Price=nil).
	Never paid / never MT-branded. AssetId=0 means skip insert (Part kit only).
	Design P0 REJECT: JeepFallback 59524622; SWAT/police; blocky soldiers; 107381 as vehicle.
	Design P0 REJECT primary: 3924234975 plastic Rthro; 91299598767068 Respawn Soldiers pack.
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
	VehicleVisualScale = 1.0, -- Design clamp 0.85–1.2 (dress mesh only)
	CharacterVisualScale = 1.0,
	BuildingVisualScale = 1.0,
	PropVisualScale = 1.0,

	Vehicles = {
		-- Free Jeep family
		MilitaryJeep = { ModelAssetId = 125916936788670, Note = "Military Car dress-only (NO JeepFallback)" } :: AssetRef,
		ArmedJeep = { ModelAssetId = 122068883442022, Note = "Tan turreted Armed Jeep (DisplayName Armed Jeep; Design Bot P0)" } :: AssetRef,
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
		SupplyTruck = { ModelAssetId = 105503568352704, Note = "Military truck (same as PatrolTruck)" } :: AssetRef,
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
		InfantryCarrier = { ModelAssetId = 17835143223, Note = "APC prefer (Design P0)" } :: AssetRef,
		CommandVehicle = { ModelAssetId = 17835143223, Note = "APC prefer (Design P0)" } :: AssetRef,
		WheeledIFV = { ModelAssetId = 17835143223, Note = "APC prefer (Design P0)" } :: AssetRef,
		AmphibiousAPC = { ModelAssetId = 17835143223, Note = "APC prefer (Design P0)" } :: AssetRef,
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
		-- Design Bot 2026-09-20: realistic human mesh. REJECT plastic 3924234975 + Respawn 91299598767068.
		Soldier = { ModelAssetId = 100212659702941, Note = "Realistic soldier StarterCharacter (gas-mask/spec-ops)" } :: AssetRef,
		Infantry = { ModelAssetId = 9104381136, Note = "Layered clothing realistic soldier (helmet+MOLLE)" } :: AssetRef,
		Worker = { ModelAssetId = 9104381136, Note = "TrainingYard worker — realistic layered soldier (P0)" } :: AssetRef,
		WorkerFallback = { ModelAssetId = 16134469614, Note = "Worker fallback Rigged Soldier if Infantry insert fails" } :: AssetRef,
		HeavyInfantry = { ModelAssetId = 14776506955, Note = "Army of Soldiers Rthro swarm pack" } :: AssetRef,
		Guard = { ModelAssetId = 16134469614, Note = "Rigged Soldier NVG/balaclava" } :: AssetRef,
		BankGuard = { ModelAssetId = 16134469614, Note = "Rigged Soldier NVG/balaclava" } :: AssetRef,
		OilRigGuard = { ModelAssetId = 16134469614, Note = "Rigged Soldier NVG/balaclava" } :: AssetRef,
		FortGuard = { ModelAssetId = 16134469614, Note = "Rigged Soldier NVG/balaclava" } :: AssetRef,
	} :: { [string]: AssetRef },

	-- No plastic CharacterAlt — primary insert failure falls back to Part kit / olive drab.
	CharacterAlt = { ModelAssetId = 0, Note = "DISABLED — Design Bot rejected plastic Rthro alts" } :: AssetRef,

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
		DefensiveWalls = { ModelAssetId = 208197704, Note = "Defensive walls L1–2; L3+ uses 9703136850 via StructureVisualConfig" } :: AssetRef,
		DefensiveWallsL3 = { ModelAssetId = 9703136850, Note = "Heavy duty military wall (DefensiveWalls L3+)" } :: AssetRef,
		PowerStation = { ModelAssetId = 14000967030, Note = "Power station" } :: AssetRef,
		Bunker = { ModelAssetId = 16659447, Note = "Destructible Movil Bunker free" } :: AssetRef,
		Helipad = { ModelAssetId = 14313845338, Note = "Airport free Get Model (pad/hangar)" } :: AssetRef,
		Airfield = { ModelAssetId = 12370174722, Note = "Airport Model free Get Model" } :: AssetRef,
		Dock = { ModelAssetId = 17701461178, Note = "Shipping Containers free (dockside)" } :: AssetRef,
	} :: { [string]: AssetRef },

	-- JeepFallback 59524622 DELETED (Design P0 REJECT). Part kit physics if mesh fails.

	-- ATM / collect presentation (StripScripts on insert) — Design Bot prefer free IDs
	MoneyCollector = { ModelAssetId = 75368157644109, Note = "ATM hero prefer; fallback 175462478" } :: AssetRef,
	MoneyCollectorFallback = { ModelAssetId = 175462478, Note = "ATM fallback classic" } :: AssetRef,
	MoneyCollectorAlts = {
		{ ModelAssetId = 90362241548850, Note = "ATM alt A" } :: AssetRef,
		{ ModelAssetId = 76846072091295, Note = "ATM alt B" } :: AssetRef,
		{ ModelAssetId = 35409899, Note = "ATM alt C" } :: AssetRef,
	},
	MoneyBagFX = { ModelAssetId = 38451313, Note = "Collect cash burst VFX (StripScripts)" } :: AssetRef,
	VfxSparkles = { ModelAssetId = 4221608224, Note = "Collect/upgrade sparkles VFX" } :: AssetRef,
	CashCrate = { ModelAssetId = 16803204916, Note = "Cash crate alt overlay" } :: AssetRef,
	UpgradeFlag = { ModelAssetId = 1679839739, Note = "L5 structure flag pop" } :: AssetRef,
	FloodlightTower = { ModelAssetId = 107381977457431, Note = "Floodlight tower PROP (not vehicle)" } :: AssetRef,
	-- VehicleDepot showroom catalog (Part-kit podium remains fallback)
	ShowroomPodium = { ModelAssetId = 5267267960, Note = "Showroom podium mesh" } :: AssetRef,
	ShowroomPedestal = { ModelAssetId = 130578088310000, Note = "Showroom pedestal" } :: AssetRef,
	ShowroomRotator = { ModelAssetId = 5389482912, Note = "Showroom rotator / turntable" } :: AssetRef,
	-- Tutorial guidance
	TutorialArrow = { ModelAssetId = 1143305733, Note = "Tutorial arrow prefer; alt 6333395014" } :: AssetRef,
	TutorialArrowAlt = { ModelAssetId = 6333395014, Note = "Tutorial arrow alt" } :: AssetRef,
	TutorialBeam = { ModelAssetId = 88687072714005, Note = "Tutorial neon beam mesh/texture" } :: AssetRef,

	-- KEY LABELS fixed (IDs unchanged); legacy aliases kept for callers
	WarzoneProps = {
		Sandbag = { ModelAssetId = 3525056989, Note = "Warzone Sandbag" } :: AssetRef,
		SandbagBarrier = { ModelAssetId = 12651656400, Note = "Warzone SandbagBarrier" } :: AssetRef,
		SandbagWall = { ModelAssetId = 25733125, Note = "Warzone SandbagWall" } :: AssetRef,
		ConcreteBarrier = { ModelAssetId = 91071319, Note = "Warzone ConcreteBarrier" } :: AssetRef,
		Crate = { ModelAssetId = 53591587, Note = "Warzone Crate" } :: AssetRef,
		MilitaryCrate = { ModelAssetId = 976333542, Note = "Warzone MilitaryCrate" } :: AssetRef,
		AmmoBox = { ModelAssetId = 16382915010, Note = "Warzone AmmoBox" } :: AssetRef,
		OilBarrel = { ModelAssetId = 25623924, Note = "Warzone OilBarrel" } :: AssetRef,
		BarbedWire = { ModelAssetId = 1291725699, Note = "Warzone BarbedWire" } :: AssetRef,
		Tent = { ModelAssetId = 6883609157, Note = "Warzone Tent" } :: AssetRef,
		RadioAntenna = { ModelAssetId = 19277831, Note = "Warzone RadioAntenna" } :: AssetRef,
		Floodlight = { ModelAssetId = 116763933, Note = "Warzone Floodlight" } :: AssetRef,
		FloodlightTower = { ModelAssetId = 107381977457431, Note = "Floodlight tower prefer" } :: AssetRef,
		Flag = { ModelAssetId = 1679839739, Note = "L5 upgrade flag" } :: AssetRef,
		Lantern = { ModelAssetId = 10121519149, Note = "Stall lantern (StripScripts; mesh only)" } :: AssetRef,
		TentAlt = { ModelAssetId = 3133150032, Note = "Tent alt if primary Tent fails" } :: AssetRef,
		RadioAntennaAlt = { ModelAssetId = 42209845, Note = "HQ roof antenna alt" } :: AssetRef,
		FloodlightAlt = { ModelAssetId = 4893998573, Note = "Depot bay floodlight" } :: AssetRef,
		FuelCans = { ModelAssetId = 1160141839, Note = "Fuel cans + oil barrels pack" } :: AssetRef,
		FlagPole = { ModelAssetId = 1679839739, Note = "Depot/HQ flag pole" } :: AssetRef,
		FlagPoleHD = { ModelAssetId = 1454179642, Note = "HQ prestige flag pole" } :: AssetRef,
		-- Legacy key aliases (same IDs)
		Sandbags = { ModelAssetId = 3525056989, Note = "alias → Sandbag" } :: AssetRef,
		Barrier = { ModelAssetId = 25733125, Note = "alias → SandbagWall" } :: AssetRef,
		Cone = { ModelAssetId = 91071319, Note = "alias → ConcreteBarrier" } :: AssetRef,
		Drum = { ModelAssetId = 53591587, Note = "alias → Crate" } :: AssetRef,
		Pallet = { ModelAssetId = 976333542, Note = "alias → MilitaryCrate" } :: AssetRef,
		CamoNet = { ModelAssetId = 16382915010, Note = "alias → AmmoBox" } :: AssetRef,
		Fence = { ModelAssetId = 25623924, Note = "alias → OilBarrel" } :: AssetRef,
		Radio = { ModelAssetId = 19277831, Note = "alias → RadioAntenna" } :: AssetRef,
		Lamp = { ModelAssetId = 116763933, Note = "alias → Floodlight" } :: AssetRef,
	} :: { [string]: AssetRef },

	DesertProps = {
		Cactus = { ModelAssetId = 121029612, Note = "Free Cactus Get Model" } :: AssetRef,
		CactusBase = { ModelAssetId = 16354482789, Note = "CactusBase2 free Get Model" } :: AssetRef,
		DesertPlants = { ModelAssetId = 108556425657107, Note = "Realistic Desert Plants free pack" } :: AssetRef,
		Palm = { ModelAssetId = 96059329869678, Note = "Palm Trees Realistic pack (horizon)" } :: AssetRef,
		PalmAlt = { ModelAssetId = 105982075286356, Note = "Low Poly Palm alt if Palm insert fails" } :: AssetRef,
		-- MeshPart AssetType 40 — VisualAssetService MeshPart pipeline (not InsertService Model)
		DesertRock = { ModelAssetId = 0, MeshId = 6562523344, Note = "Low Poly Rocks MeshPart (MeshId pipeline)" } :: AssetRef,
	} :: { [string]: AssetRef },

	-- MapDressing keys (Decal / non-Model assets)
	MapDressing = {
		AsphaltDecal = { ModelAssetId = 0, MeshId = 10197707775, Note = "Asphalt road Decal Texture on road Parts" } :: AssetRef,
		ChevronArrow = { ModelAssetId = 0, Note = "Part-kit floor chevrons (no free Model)" } :: AssetRef,
		DesertRock = { ModelAssetId = 0, MeshId = 6562523344, Note = "alias → DesertProps.DesertRock MeshPart" } :: AssetRef,
		Palm = { ModelAssetId = 96059329869678, Note = "alias → DesertProps.Palm" } :: AssetRef,
		PalmAlt = { ModelAssetId = 105982075286356, Note = "alias → DesertProps.PalmAlt" } :: AssetRef,
		DesertPlants = { ModelAssetId = 108556425657107, Note = "alias → DesertProps.DesertPlants" } :: AssetRef,
		Cactus = { ModelAssetId = 121029612, Note = "alias → DesertProps.Cactus" } :: AssetRef,
	} :: { [string]: AssetRef },


	-- Tier 2: oil spectacle + map landmarks (REJECT Ultrapump 1837698074)
	IndustrialProps = {
		IndustrialPack = { ModelAssetId = 103734805361054, Note = "Realistic Industrial Props Pack (oil spectacle)" } :: AssetRef,
		RustyPipes = { ModelAssetId = 131322292868756, Note = "Rusty pipes runs to derrick silhouette" } :: AssetRef,
		OilBarrel = { ModelAssetId = 25623924, Note = "Oil barrel ring" } :: AssetRef,
		FuelCans = { ModelAssetId = 1160141839, Note = "Fuel cans cluster" } :: AssetRef,
		-- GasStation 5149705639 OPTIONAL heavy — not default
		-- Ultrapump 1837698074 REJECT
	} :: { [string]: AssetRef },

	Landmarks = {
		RadioTower = { ModelAssetId = 119021509, Note = "Map ridge radio tower POI" } :: AssetRef,
		Bunker = { ModelAssetId = 16659447, Note = "Desert approach bunker" } :: AssetRef,
		SpyBunker = { ModelAssetId = 55228082, Note = "Optional spy bunker POI" } :: AssetRef,
		SmallFort = { ModelAssetId = 67444725, Note = "Mid-map small fort landmark" } :: AssetRef,
	} :: { [string]: AssetRef },

	-- HQ / Barracks interior dress keys (hosts in StructureKitBuilder)
	StructureDress = {
		CommandCenter = { "RadioAntenna", "RadioAntennaAlt", "AmmoBox", "Crate", "MilitaryCrate", "Lantern", "Floodlight", "FuelCans" },
		Barracks = { "Crate", "MilitaryCrate", "AmmoBox", "Lantern", "Sandbag" },
		VehicleDepot = { "FloodlightAlt", "Floodlight", "FlagPole", "FuelCans" },
		PowerStation = { "FuelCans" },
	} :: { [string]: { string } },

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
