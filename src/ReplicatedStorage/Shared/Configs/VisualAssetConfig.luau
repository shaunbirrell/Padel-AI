--!strict
--[[
	Optional free Creator Store Model asset IDs for InsertService / AssetService.
	Part kits remain the authoritative fallback (always). Never use paid / MT-branded assets.

	Studio PERF: when DevConfig.StudioSkipWorldDressing and not StudioForceDress,
	VisualAssetService skips catalog inserts (8GB laptop). Live servers may load.

	IDs researched as Free / Get Model on Creator Store (economy sale=false price=nil).
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
	MaxLoadAttempts = 36,
	VehicleVisualScale = 1.0,
	CharacterVisualScale = 1.0,
	BuildingVisualScale = 1.0,
	PropVisualScale = 1.0,

	Vehicles = {
		-- Free Jeep family
		MilitaryJeep = { ModelAssetId = 59524622, Note = "Free Jeep (Creator Store)" } :: AssetRef,
		ArmedJeep = { ModelAssetId = 59524622, Note = "Jeep reuse" } :: AssetRef,
		UtilityQuad = { ModelAssetId = 59524622, Note = "Jeep reuse (scaled by kit)" } :: AssetRef,
		ScoutCar = { ModelAssetId = 59524622, Note = "Jeep reuse" } :: AssetRef,
		ReconBuggy = { ModelAssetId = 59524622, Note = "Jeep reuse" } :: AssetRef,
		-- Free tank family
		LightTank = { ModelAssetId = 26007709, Note = "Free tank (Creator Store)" } :: AssetRef,
		MediumTank = { ModelAssetId = 26007709, Note = "Tank reuse" } :: AssetRef,
		BattleTank = { ModelAssetId = 1379706428, Note = "Panzer IV free port" } :: AssetRef,
		HeavyTank = { ModelAssetId = 1379706428, Note = "Panzer reuse" } :: AssetRef,
		SuperHeavyTank = { ModelAssetId = 1379706428, Note = "Panzer reuse" } :: AssetRef,
		TankDestroyer = { ModelAssetId = 1379706428, Note = "Panzer reuse" } :: AssetRef,
		AssaultGun = { ModelAssetId = 1379706428, Note = "Panzer reuse" } :: AssetRef,
		-- Free heli family
		TransportHeli = { ModelAssetId = 9337454, Note = "UH-60 free helicopter" } :: AssetRef,
		AttackHelicopter = { ModelAssetId = 9337454, Note = "UH-60 reuse" } :: AssetRef,
		LightTransportHeli = { ModelAssetId = 9337454, Note = "UH-60 reuse" } :: AssetRef,
		NightAttackHeli = { ModelAssetId = 9337454, Note = "UH-60 reuse" } :: AssetRef,
		LightScoutHeli = { ModelAssetId = 9337454, Note = "UH-60 reuse" } :: AssetRef,
		GunshipHeli = { ModelAssetId = 9337454, Note = "UH-60 reuse" } :: AssetRef,
		HeavyLiftHeli = { ModelAssetId = 9337454, Note = "UH-60 reuse" } :: AssetRef,
		RescueHeli = { ModelAssetId = 9337454, Note = "UH-60 reuse" } :: AssetRef,
		StealthHeli = { ModelAssetId = 9337454, Note = "UH-60 reuse" } :: AssetRef,
		-- Classic free pack (trucks / APC fallback)
		_FallbackWheeled = { ModelAssetId = 28912351, Note = "Military Vehicle Meshes pack (free)" } :: AssetRef,
		PatrolTruck = { ModelAssetId = 28912351, Note = "Mesh pack" } :: AssetRef,
		ArmoredTruck = { ModelAssetId = 28912351, Note = "Mesh pack" } :: AssetRef,
		APC = { ModelAssetId = 28912351, Note = "Mesh pack" } :: AssetRef,
		-- Free jet family (classic + named free fighter)
		_FallbackJet = { ModelAssetId = 4865838, Note = "Classic free fighter jet" } :: AssetRef,
		FighterJet = { ModelAssetId = 4865838, Note = "Classic free fighter jet" } :: AssetRef,
		InterceptorJet = { ModelAssetId = 4865838, Note = "Fighter reuse" } :: AssetRef,
		TrainerJet = { ModelAssetId = 4865838, Note = "Fighter reuse" } :: AssetRef,
		ReconPlane = { ModelAssetId = 4865838, Note = "Fighter reuse" } :: AssetRef,
		LightFighter = { ModelAssetId = 4865838, Note = "Fighter reuse" } :: AssetRef,
		StrikeJet = { ModelAssetId = 28574422, Note = "P-38 Lightning free Get Model" } :: AssetRef,
		CASJet = { ModelAssetId = 28574422, Note = "P-38 reuse" } :: AssetRef,
		StealthStrikeJet = { ModelAssetId = 28574422, Note = "P-38 reuse" } :: AssetRef,
		StrikeBomber = { ModelAssetId = 297267045, Note = "[USAF] Free Fighter jet" } :: AssetRef,
		CargoPlane = { ModelAssetId = 297267045, Note = "USAF free jet reuse (transport silhouette)" } :: AssetRef,
		AWACSPlane = { ModelAssetId = 297267045, Note = "USAF free jet reuse" } :: AssetRef,
		TankerPlane = { ModelAssetId = 297267045, Note = "USAF free jet reuse" } :: AssetRef,
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
		SupplyTruck = { ModelAssetId = 28912351, Note = "Mesh pack truck" } :: AssetRef,
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
		FortressTank = { ModelAssetId = 1379706428, Note = "Panzer reuse" } :: AssetRef,
		RailgunCarrier = { ModelAssetId = 1379706428, Note = "Panzer/arty reuse" } :: AssetRef,
		DispatchCar = { ModelAssetId = 59524622, Note = "Jeep reuse" } :: AssetRef,
		UtilityHeli = { ModelAssetId = 9337454, Note = "UH-60 reuse" } :: AssetRef,
		MedevacHeli = { ModelAssetId = 9337454, Note = "UH-60 reuse" } :: AssetRef,
		EscortHeli = { ModelAssetId = 9337454, Note = "UH-60 reuse" } :: AssetRef,
		VTOLTransport = { ModelAssetId = 9337454, Note = "UH-60 reuse" } :: AssetRef,
		HeavyBomber = { ModelAssetId = 297267045, Note = "USAF free jet reuse" } :: AssetRef,
		StealthStrike = { ModelAssetId = 28574422, Note = "P-38 reuse" } :: AssetRef,
	} :: { [string]: AssetRef },

	Characters = {
		-- Official Roblox Soldier NPC kit (free)
		Soldier = { ModelAssetId = 3924234975, Note = "Official Roblox Soldier (Rthro)" } :: AssetRef,
		Guard = { ModelAssetId = 3924234975, Note = "Soldier reuse for guards" } :: AssetRef,
		BankGuard = { ModelAssetId = 3924234975, Note = "Soldier reuse" } :: AssetRef,
		OilRigGuard = { ModelAssetId = 3924234975, Note = "Soldier reuse" } :: AssetRef,
		FortGuard = { ModelAssetId = 3924234975, Note = "Soldier reuse" } :: AssetRef,
	} :: { [string]: AssetRef },

	Buildings = {
		-- Free Barracks / Military Base (Get Model). Part kits remain primary fallback.
		CommandCenter = { ModelAssetId = 138331074285379, Note = "Military Base free Get Model" } :: AssetRef,
		Barracks = { ModelAssetId = 9424782, Note = "Barracks free Get Model (2009)" } :: AssetRef,
		VehicleDepot = { ModelAssetId = 9424782, Note = "Barracks reuse (depot)" } :: AssetRef,
		WeaponsFacility = { ModelAssetId = 9424782, Note = "Barracks reuse" } :: AssetRef,
		Warehouse = { ModelAssetId = 9424782, Note = "Barracks reuse" } :: AssetRef,
		ResearchLab = { ModelAssetId = 9424782, Note = "Barracks reuse" } :: AssetRef,
		SpecialForcesFacility = { ModelAssetId = 9424782, Note = "Barracks reuse" } :: AssetRef,
		Watchtowers = { ModelAssetId = 16659447, Note = "Free bunker/tower-ish model" } :: AssetRef,
		Radar = { ModelAssetId = 16659447, Note = "Bunker reuse" } :: AssetRef,
		MissileDefense = { ModelAssetId = 16659447, Note = "Bunker reuse" } :: AssetRef,
		DefensiveWalls = { ModelAssetId = 16659447, Note = "Bunker reuse" } :: AssetRef,
		PowerStation = { ModelAssetId = 16659447, Note = "Bunker reuse" } :: AssetRef,
		Helipad = { ModelAssetId = 0, Note = "Part kit primary (pad silhouette)" } :: AssetRef,
		Airfield = { ModelAssetId = 0, Note = "Part kit primary" } :: AssetRef,
		Dock = { ModelAssetId = 0, Note = "Part kit primary" } :: AssetRef,
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
