--!strict
--[[
	Optional free Creator Store Model / MeshPart asset IDs for InsertService / AssetService.
	Part kits remain the authoritative fallback (always). Never use paid / MT-branded assets.
	AssetId = 0 means skip the insert (Part kit only).

	Owner default D1 (roadmap §8): Game Settings → Security → "Allow Loading Third Party Assets" stays OFF.
	With it OFF, LoadAssetAsync only loads assets the game creator owns or was granted, so each third-party
	ID below fails once (VisualAssetService caches the failure) and the Part kit stays. None of these IDs is
	owned by Roblox (economy API, 2026-09-24).

	W1 CFG (roadmap §1.4, §2.2 item 5): these entries are set to 0 and fall back to the Part kit
	(vehicles first try their KitFamilyFallback body):
	  • paid, or no longer distributed on the Creator Store;
	  • a copy of a named real-world or franchise design (vehicle, ship, weapon, unit, brand or country);
	  • provenance not OK (the upload says it is from another game or is someone else's work).
	Every remaining ID with its owner, terms and why it is allowed: docs/ASSET_LICENSES.md.
	A new ID must be free, the uploader's own work, no real-world/franchise design and no brand text,
	and gets its row in docs/ASSET_LICENSES.md in the same commit.

	Studio PERF: when DevConfig.StudioSkipWorldDressing and not StudioForceDress,
	VisualAssetService skips catalog inserts (8GB laptop). Live servers may load.

	Design P0 REJECT: JeepFallback 59524622; SWAT/police; blocky soldiers; 107381 as vehicle.
	Design P0 REJECT primary: 3924234975 plastic Rthro; 91299598767068 Respawn Soldiers pack.
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
	BuildingVisualScale = 1.0, -- ScaleTo uses TargetFootprint; do NOT squash to plinth
	PropVisualScale = 1.0,

	Vehicles = {
		-- Free light 4x4 family
		MilitaryJeep = { ModelAssetId = 125916936788670, Note = "Military Car dress-only (NO JeepFallback)" } :: AssetRef,
		ArmedJeep = { ModelAssetId = 0, Note = "W1 CFG drop (real-world design) → WheeledLight family body, else Part kit" } :: AssetRef,
		UtilityQuad = { ModelAssetId = 125916936788670, Note = "Military Car reuse (scaled)" } :: AssetRef,
		ScoutCar = { ModelAssetId = 125916936788670, Note = "Military Car reuse" } :: AssetRef,
		ReconBuggy = { ModelAssetId = 125916936788670, Note = "Military Car reuse" } :: AssetRef,
		-- Free tank family
		LightTank = { ModelAssetId = 76055078503396, Note = "v41 IFV/tank mesh — DisplayName Light Tank" } :: AssetRef,
		MediumTank = { ModelAssetId = 26007709, Note = "Classic free tank — Medium only" } :: AssetRef,
		-- W1 CFG drop (franchise design): TrackedMBT family → BattleTank = 0 → Part kit
		BattleTank = { ModelAssetId = 0, Note = "W1 CFG drop (franchise design) — Part kit" } :: AssetRef,
		HeavyTank = { ModelAssetId = 0, Note = "W1 CFG drop (franchise design) — Part kit" } :: AssetRef,
		SuperHeavyTank = { ModelAssetId = 0, Note = "W1 CFG drop (franchise design) — Part kit" } :: AssetRef,
		TankDestroyer = { ModelAssetId = 0, Note = "W1 CFG drop (franchise design) — Part kit" } :: AssetRef,
		AssaultGun = { ModelAssetId = 0, Note = "W1 CFG drop (franchise design) — Part kit" } :: AssetRef,
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
		PatrolBoat = { ModelAssetId = 557152593, Note = "Navy Patrol Boat" } :: AssetRef,
		FastAttackCraft = { ModelAssetId = 0, Note = "W1 CFG drop (real-world design) → NavalPatrol family body, else Part kit" } :: AssetRef,
		RiverBoat = { ModelAssetId = 15786579439, Note = "Boat reuse" } :: AssetRef,
		CoastCutter = { ModelAssetId = 557152593, Note = "Navy Patrol Boat" } :: AssetRef,
		TorpedoBoat = { ModelAssetId = 0, Note = "W1 CFG drop (real-world design) → NavalPatrol family body, else Part kit" } :: AssetRef,
		Gunboat = { ModelAssetId = 557152593, Note = "Navy Patrol Boat" } :: AssetRef,
		MissileBoat = { ModelAssetId = 15786579439, Note = "Boat reuse" } :: AssetRef,
		MineLayer = { ModelAssetId = 15786579439, Note = "Boat reuse" } :: AssetRef,
		CoastalMonitor = { ModelAssetId = 15786579439, Note = "Boat reuse" } :: AssetRef,
		LandingCraft = { ModelAssetId = 0, Note = "Part-kit barge — REJECT 13195201090 template" } :: AssetRef,
		AssaultLanding = { ModelAssetId = 0, Note = "Part-kit — REJECT 13195201090" } :: AssetRef,
		HoverTransport = { ModelAssetId = 0, Note = "Part-kit capital stub — REJECT 13195201090" } :: AssetRef,
		HospitalShip = { ModelAssetId = 0, Note = "Part-kit capital stub — REJECT 13195201090" } :: AssetRef,
		SupplyShip = { ModelAssetId = 0, Note = "Part-kit capital stub — REJECT 13195201090" } :: AssetRef,
		AmphibAssault = { ModelAssetId = 0, Note = "Part-kit capital stub — REJECT 13195201090" } :: AssetRef,
		Corvette = { ModelAssetId = 12794395111, Note = "Frigate scaled" } :: AssetRef,
		Destroyer = { ModelAssetId = 0, Note = "W1 CFG drop (real-world ship) — NavalCapital → Part kit" } :: AssetRef,
		Frigate = { ModelAssetId = 12794395111, Note = "Multipurpose Frigate" } :: AssetRef,
		CarrierEscort = { ModelAssetId = 12794395111, Note = "Frigate escort" } :: AssetRef,
		Battleship = { ModelAssetId = 0, Note = "W1 CFG drop (real-world ship) — NavalCapital → Part kit" } :: AssetRef,
		AircraftCarrier = { ModelAssetId = 0, Note = "Part-kit capital — REJECT 13195201090" } :: AssetRef,
		SubSurfaceRunner = { ModelAssetId = 15786579439, Note = "Boat reuse (surface stub)" } :: AssetRef,
		AttackSub = { ModelAssetId = 15786579439, Note = "Boat reuse (surface stub)" } :: AssetRef,
		-- Explicit aliases for depth-pass IDs (KitFamilyFallback also covers these)
		SupplyTruck = { ModelAssetId = 105503568352704, Note = "Military truck (same as PatrolTruck)" } :: AssetRef,
		FuelTanker = { ModelAssetId = 0, Note = "W1 CFG drop (real-world truck) → WheeledTruck family body, else Part kit" } :: AssetRef,
		EngineeringTruck = { ModelAssetId = 0, Note = "W1 CFG drop (real-world truck) → WheeledTruck family body, else Part kit" } :: AssetRef,
		FlatbedHauler = { ModelAssetId = 0, Note = "W1 CFG drop (real-world truck) → WheeledTruck family body, else Part kit" } :: AssetRef,
		AmmoCarrier = { ModelAssetId = 81802040484766, Note = "Logistics Truck PBR" } :: AssetRef,
		MissileTruck = { ModelAssetId = 81802040484766, Note = "Logistics Truck PBR" } :: AssetRef,
		AntiAirTruck = { ModelAssetId = 28912351, Note = "Mesh pack truck" } :: AssetRef,
		RadarTruck = { ModelAssetId = 81802040484766, Note = "Logistics Truck PBR" } :: AssetRef,
		CargoVan = { ModelAssetId = 28912351, Note = "Mesh pack truck" } :: AssetRef,
		TroopTransport = { ModelAssetId = 4128346779, Note = "Army Truck mesh unique" } :: AssetRef,
		RecoveryTruck = { ModelAssetId = 28912351, Note = "Mesh pack truck" } :: AssetRef,
		EscortTruck = { ModelAssetId = 28912351, Note = "Mesh pack truck" } :: AssetRef,
		InfantryCarrier = { ModelAssetId = 17835143223, Note = "APC prefer (Design P0)" } :: AssetRef,
		CommandVehicle = { ModelAssetId = 17835143223, Note = "APC prefer (Design P0)" } :: AssetRef,
		WheeledIFV = { ModelAssetId = 17835143223, Note = "APC prefer (Design P0)" } :: AssetRef,
		AmphibiousAPC = { ModelAssetId = 17835143223, Note = "APC prefer (Design P0)" } :: AssetRef,
		CombatIFV = { ModelAssetId = 76055078503396, Note = "v41 Combat IFV" } :: AssetRef,
		AssaultIFV = { ModelAssetId = 76055078503396, Note = "v41 Assault IFV" } :: AssetRef,
		BridgeLayer = { ModelAssetId = 76055078503396, Note = "Engineer Track" } :: AssetRef,
		MineClearer = { ModelAssetId = 76055078503396, Note = "Engineer Track" } :: AssetRef,
		FlameCarrier = { ModelAssetId = 76055078503396, Note = "Engineer Track" } :: AssetRef,
		SPAAG = { ModelAssetId = 15618784436, Note = "AA Gun" } :: AssetRef,
		MobileSAM = { ModelAssetId = 0, Note = "W1 CFG drop (real-world system) → TrackedSPAAG family body, else Part kit" } :: AssetRef,
		MortarCarrier = { ModelAssetId = 10286064243, Note = "Howitzer" } :: AssetRef,
		MobileArtillery = { ModelAssetId = 10286064243, Note = "Howitzer" } :: AssetRef,
		RocketArtillery = { ModelAssetId = 0, Note = "W1 CFG drop (real-world system) → TrackedArtillery family body, else Part kit" } :: AssetRef,
		HowitzerTruck = { ModelAssetId = 10286064243, Note = "Howitzer" } :: AssetRef,
		SiegeMortar = { ModelAssetId = 10286064243, Note = "Howitzer" } :: AssetRef,
		LightScoutTank = { ModelAssetId = 76055078503396, Note = "v42 Scout Tank" } :: AssetRef,
		FortressTank = { ModelAssetId = 0, Note = "W1 CFG drop (franchise design) — Part kit" } :: AssetRef,
		RailgunCarrier = { ModelAssetId = 0, Note = "W1 CFG drop (franchise design) → TrackedArtillery family body, else Part kit" } :: AssetRef,
		DispatchCar = { ModelAssetId = 125916936788670, Note = "Military Car reuse" } :: AssetRef,
		UtilityHeli = { ModelAssetId = 5935419, Note = "Light/utility heli" } :: AssetRef,
		MedevacHeli = { ModelAssetId = 5935419, Note = "Light/utility heli" } :: AssetRef,
		EscortHeli = { ModelAssetId = 295607934, Note = "Gunship escort" } :: AssetRef,
		VTOLTransport = { ModelAssetId = 9753309, Note = "Transport heli VTOL" } :: AssetRef,
		HeavyBomber = { ModelAssetId = 3319732457, Note = "Bomber/cargo/AWACS family" } :: AssetRef,
		StealthStrike = { ModelAssetId = 5507592781, Note = "Strike/CAS jet" } :: AssetRef,
		-- Depth-pass capital / bomber IDs previously missing from catalog map
		Cruiser = { ModelAssetId = 0, Note = "W1 CFG drop (real-world ship) — NavalCapital → Part kit" } :: AssetRef,
		MissileCruiser = { ModelAssetId = 0, Note = "W1 CFG drop (real-world ship) — NavalCapital → Part kit" } :: AssetRef,
		FleetCarrier = { ModelAssetId = 0, Note = "Part-kit capital — REJECT 13195201090" } :: AssetRef,
		StrategicBomber = { ModelAssetId = 3319732457, Note = "Bomber/cargo/AWACS family" } :: AssetRef,
	} :: { [string]: AssetRef },

	Characters = {
		-- Design Bot 2026-09-20: realistic human mesh. REJECT plastic 3924234975 + Respawn 91299598767068.
		Soldier = { ModelAssetId = 100212659702941, Note = "Realistic soldier StarterCharacter (gas-mask/spec-ops)" } :: AssetRef,
		Infantry = { ModelAssetId = 9104381136, Note = "Layered clothing realistic soldier (helmet+MOLLE)" } :: AssetRef,
		Worker = { ModelAssetId = 16134469614, Note = "v41 distinct Worker (Rigged Soldier NVG)" } :: AssetRef,
		WorkerFallback = { ModelAssetId = 9104381136, Note = "Worker fallback Infantry mesh if Guard insert fails" } :: AssetRef,
		HeavyInfantry = { ModelAssetId = 14776506955, Note = "Army of Soldiers Rthro swarm pack" } :: AssetRef,
		Guard = { ModelAssetId = 16134469614, Note = "Rigged Soldier NVG/balaclava" } :: AssetRef,
		BankGuard = { ModelAssetId = 16134469614, Note = "Rigged Soldier NVG/balaclava" } :: AssetRef,
		OilRigGuard = { ModelAssetId = 16134469614, Note = "Rigged Soldier NVG/balaclava" } :: AssetRef,
		FortGuard = { ModelAssetId = 16134469614, Note = "Rigged Soldier NVG/balaclava" } :: AssetRef,
		GateGuard = { ModelAssetId = 16134469614, Note = "Gate patrol — Rigged Soldier NVG/balaclava" } :: AssetRef,
		-- W1 CFG drop (country / real-world weapon in the source): 0 → CharacterAlt (0) → Part kit
		SpecialForces = { ModelAssetId = 0, Note = "W1 CFG drop (real-world unit) — Part kit" } :: AssetRef,
		SpecialForcesAlt = { ModelAssetId = 0, Note = "W1 CFG drop (real-world weapon) — unused key" } :: AssetRef,
	} :: { [string]: AssetRef },

	-- No plastic CharacterAlt — primary insert failure falls back to Part kit / olive drab.
	CharacterAlt = { ModelAssetId = 0, Note = "DISABLED — Design Bot rejected plastic Rthro alts" } :: AssetRef,

	Buildings = {
		-- Free Barracks / HQ / hangar / dock (Get Model). Part kits remain primary fallback.
		CommandCenter = { ModelAssetId = 138331074285379, Note = "Military Base free Get Model (HQ)" } :: AssetRef,
		Barracks = { ModelAssetId = 18798977801, Note = "Barracks free Get Model (2009)" } :: AssetRef,
		VehicleDepot = { ModelAssetId = 12208876851, Note = "Arched depot/garage ≠ Hangar" } :: AssetRef,
		WeaponsFacility = { ModelAssetId = 4120970784, Note = "Weapons facility" } :: AssetRef,
		Warehouse = { ModelAssetId = 15942568272, Note = "Hangar shed multi-bay warehouse ≠ Hangar" } :: AssetRef,
		Hangar = { ModelAssetId = 6015472062, Note = "Aircraft bay hangar KEEP primary" } :: AssetRef,
		HangarAlt = { ModelAssetId = 12208876851, Note = "Hangar insert fallback" } :: AssetRef,
		BaseGate = { ModelAssetId = 85138026, Note = "Gate arch prop ONLY — DisplayName Base Gate" } :: AssetRef,
		ResearchLab = { ModelAssetId = 17725725, Note = "Research lab" } :: AssetRef,
		SpecialForcesFacility = { ModelAssetId = 18798977801, Note = "Special forces facility" } :: AssetRef,
		Watchtowers = { ModelAssetId = 108525417345747, Note = "Watchtower" } :: AssetRef,
		Radar = { ModelAssetId = 9559610195, Note = "Radar" } :: AssetRef,
		-- W1 CFG drop (real-world system). NOTE: ResolveBuildingAssetId then reads StructureVisualConfig.Palettes
		-- .MissileDefense.MeshAssetId — that file must be 0 too for a Part kit (see docs/ASSET_LICENSES.md).
		MissileDefense = { ModelAssetId = 0, Note = "W1 CFG drop (real-world system) — Part kit" } :: AssetRef,
		DefensiveWalls = { ModelAssetId = 0, Note = "v41: no Wall* segment catalog dress" } :: AssetRef,
		DefensiveWallsL3 = { ModelAssetId = 0, Note = "v41: Part-kit heavy walls" } :: AssetRef,
		PowerStation = { ModelAssetId = 14000967030, Note = "Power station" } :: AssetRef,
		Bunker = { ModelAssetId = 0, Note = "W1 CFG drop (off the Creator Store) — Part kit" } :: AssetRef,
		Helipad = { ModelAssetId = 14313845338, Note = "Airport free Get Model (pad/hangar)" } :: AssetRef,
		Airfield = { ModelAssetId = 0, Note = "COMPOSITE runway+Hangar 6015472062; REJECT 12370174722" } :: AssetRef,
		Dock = { ModelAssetId = 17701461178, Note = "Shipping Containers free (dockside)" } :: AssetRef,
		-- Anti-heli Base Ceiling: Part-kit only (no invented / paid roof IDs)
		BaseCeiling = { ModelAssetId = 0, Note = "Part-kit anti-heli roof — no free dedicated Model" } :: AssetRef,
	} :: { [string]: AssetRef },

	-- JeepFallback 59524622 DELETED (Design P0 REJECT). Part kit physics if mesh fails.

	-- Gate defense (Design Bot GATE_DEFENSE_WIRE 2026-09-20)
	GateDefense = {
		Guard = { ModelAssetId = 16134469614, Note = "Rigged Soldier — gate patrol" } :: AssetRef,
		AutoGun = { ModelAssetId = 4923345827, Note = "Machine Gun Nest tripod HMG — ScaleTo 4–6 stud" } :: AssetRef,
		-- L2 elevated ONLY (not door flanks):
		AutoGunElevated = { ModelAssetId = 0, Note = "W1 CFG drop (uploader not the author) — unused key" } :: AssetRef,
		AutoGunElevatedAlt = { ModelAssetId = 10354803684, Note = "Military turret — L2/corner only" } :: AssetRef,
		SandbagNest = { ModelAssetId = 8980890767, Note = "Circular sandbag ring under HMG" } :: AssetRef,
		Sandbags = { ModelAssetId = 3525056989, Note = "Realistic Sandbag scatter at posts" } :: AssetRef,
	},

	-- ATM / collect presentation (StripScripts on insert) — Design Bot prefer free IDs
	-- W1 CFG drop (paid): 0 is skipped, so TryAttachCollectorVisual tries the fallback, then the alts, then the Part kit
	MoneyCollector = { ModelAssetId = 0, Note = "W1 CFG drop (paid) → MoneyCollectorFallback 175462478" } :: AssetRef,
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
		Lantern = { ModelAssetId = 0, Note = "W1 CFG drop (extracted from another game) — Part kit host" } :: AssetRef,
		TentAlt = { ModelAssetId = 3133150032, Note = "Tent alt if primary Tent fails" } :: AssetRef,
		RadioAntennaAlt = { ModelAssetId = 42209845, Note = "HQ roof antenna alt" } :: AssetRef,
		FloodlightAlt = { ModelAssetId = 4893998573, Note = "Depot bay floodlight" } :: AssetRef,
		FuelCans = { ModelAssetId = 1160141839, Note = "Fuel cans + oil barrels pack" } :: AssetRef,
		FlagPole = { ModelAssetId = 1679839739, Note = "Depot/HQ flag pole" } :: AssetRef,
		FlagPoleHD = { ModelAssetId = 1454179642, Note = "HQ prestige flag pole" } :: AssetRef,
		-- Map densify P0/P1 (Design MAP_BUILD_OUT_WIRE 2026-09-21)
		JerseyBarrier = { ModelAssetId = 82454061017921, Note = "Concrete Jersey — road rhythm" } :: AssetRef,
		JerseyBarrierAlt = { ModelAssetId = 17156953177, Note = "Jersey mesh alt" } :: AssetRef,
		RoadBarriers = { ModelAssetId = 15912051001, Note = "Concrete Barriers pack — junctions" } :: AssetRef,
		Hesco = { ModelAssetId = 0, Note = "W1 CFG drop (brand name in the source) — Part kit host" } :: AssetRef,
		TankWreck = { ModelAssetId = 9171585794, Note = "Destroyed tank warzone fill" } :: AssetRef,
		RuinedBuilding = { ModelAssetId = 8176692221, Note = "Destroyed Building landmark fill" } :: AssetRef,
		RuinedWall = { ModelAssetId = 104053043839965, Note = "Mossy ruined wall" } :: AssetRef,
		FuelTanks = { ModelAssetId = 0, Note = "W1 CFG drop (country name in the source) — Part kit host" } :: AssetRef,
		AmmoShed = { ModelAssetId = 2652344972, Note = "Military ammo/supplies shed mesh" } :: AssetRef,
		SupplyShed = { ModelAssetId = 82560800252069, Note = "Vehicle/supply shed" } :: AssetRef,
		PortableLightTower = { ModelAssetId = 9701862157, Note = "Military portable light tower" } :: AssetRef,
		StreetLamp = { ModelAssetId = 123546710527428, Note = "StreetLamp_A road furniture" } :: AssetRef,
		StreetLampAlt = { ModelAssetId = 8180880144, Note = "Street lamp fallback" } :: AssetRef,
		MilitaryCratePack = { ModelAssetId = 16540055496, Note = "Military Crates pack variety" } :: AssetRef,
		-- Legacy key aliases (same IDs)
		Sandbags = { ModelAssetId = 3525056989, Note = "alias → Sandbag" } :: AssetRef,
		Barrier = { ModelAssetId = 25733125, Note = "alias → SandbagWall" } :: AssetRef,
		Cone = { ModelAssetId = 91071319, Note = "alias → ConcreteBarrier" } :: AssetRef,
		Drum = { ModelAssetId = 53591587, Note = "alias → Crate" } :: AssetRef,
		Pallet = { ModelAssetId = 976333542, Note = "alias → MilitaryCrate" } :: AssetRef,
		CamoNet = { ModelAssetId = 13668977092, Note = "Camouflage Netting — FIXED (was AmmoBox alias)" } :: AssetRef,
		CamoNetAlt = { ModelAssetId = 13437018139, Note = "Ghillie Net fallback" } :: AssetRef,
		Fence = { ModelAssetId = 25623924, Note = "alias → OilBarrel" } :: AssetRef,
		Radio = { ModelAssetId = 19277831, Note = "alias → RadioAntenna" } :: AssetRef,
		Lamp = { ModelAssetId = 116763933, Note = "alias → Floodlight" } :: AssetRef,
	} :: { [string]: AssetRef },

	DesertProps = {
		Cactus = { ModelAssetId = 0, Note = "W1 CFG drop (uploader not the author) — Part kit" } :: AssetRef,
		CactusBase = { ModelAssetId = 16354482789, Note = "CactusBase2 free Get Model" } :: AssetRef,
		DesertPlants = { ModelAssetId = 0, Note = "W1 CFG drop (paid) — Part kit" } :: AssetRef,
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
		DesertPlants = { ModelAssetId = 0, Note = "alias → DesertProps.DesertPlants (W1 CFG drop)" } :: AssetRef,
		Cactus = { ModelAssetId = 0, Note = "alias → DesertProps.Cactus (W1 CFG drop)" } :: AssetRef,
		JerseyBarrier = { ModelAssetId = 82454061017921, Note = "alias → WarzoneProps.JerseyBarrier" } :: AssetRef,
		JerseyBarrierAlt = { ModelAssetId = 17156953177, Note = "alias → WarzoneProps.JerseyBarrierAlt" } :: AssetRef,
		DesertMesa = { ModelAssetId = 12809476227, Note = "Desert Mountain mesa horizon" } :: AssetRef,
		Hesco = { ModelAssetId = 0, Note = "alias → WarzoneProps.Hesco (W1 CFG drop)" } :: AssetRef,
	} :: { [string]: AssetRef },


	-- Tier 2: oil spectacle + map landmarks (REJECT Ultrapump 1837698074)
	IndustrialProps = {
		IndustrialPack = { ModelAssetId = 0, Note = "W1 CFG drop (paid) — Part kit (oil spectacle)" } :: AssetRef,
		OilPumpjack = { ModelAssetId = 13525922265, Note = "Realistic Oil Pumpjack" } :: AssetRef,
		OilPumpjackAlt = { ModelAssetId = 15192621369, Note = "Oil Rig / Pumpjack alt" } :: AssetRef,
		RustyPipes = { ModelAssetId = 0, Note = "W1 CFG drop (paid) — Part kit" } :: AssetRef,
		OilBarrel = { ModelAssetId = 25623924, Note = "Oil barrel ring" } :: AssetRef,
		FuelCans = { ModelAssetId = 1160141839, Note = "Fuel cans cluster" } :: AssetRef,
		-- GasStation 5149705639 OPTIONAL heavy — not default
		-- Ultrapump 1837698074 REJECT
	} :: { [string]: AssetRef },

	Landmarks = {
		RadioTower = { ModelAssetId = 119021509, Note = "Map ridge radio tower POI" } :: AssetRef,
		Bunker = { ModelAssetId = 0, Note = "W1 CFG drop (off the Creator Store) — Part kit" } :: AssetRef,
		SpyBunker = { ModelAssetId = 55228082, Note = "Optional spy bunker POI" } :: AssetRef,
		SmallFort = { ModelAssetId = 67444725, Note = "Mid-map small fort landmark" } :: AssetRef,
		DesertMesa = { ModelAssetId = 12809476227, Note = "alias → MapDressing.DesertMesa horizon" } :: AssetRef,
		-- P2 registered (dress deferred if perf risk)
		DesertHouse = { ModelAssetId = 9136197032, Note = "Adobe desert house (P2)" } :: AssetRef,
		Pier = { ModelAssetId = 11138299907, Note = "Boat Dock pier accent (P2)" } :: AssetRef,
		PierAlt = { ModelAssetId = 0, Note = "W1 CFG drop (paid) — Part kit" } :: AssetRef,
		CheckpointBridge = { ModelAssetId = 867696371, Note = "WW2 bridge checkpoint landmark (P2)" } :: AssetRef,
	} :: { [string]: AssetRef },

	-- HQ / Barracks interior dress keys (hosts in StructureKitBuilder)
	StructureDress = {
		CommandCenter = { "RadioAntenna", "RadioAntennaAlt", "AmmoBox", "Crate", "MilitaryCrate", "Lantern", "Floodlight", "FuelCans" },
		Barracks = { "Crate", "MilitaryCrate", "AmmoBox", "Lantern", "Sandbag" },
		WeaponsFacility = { "AmmoBox", "MilitaryCrate", "Lantern", "Sandbag" },
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
