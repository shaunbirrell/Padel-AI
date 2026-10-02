--!strict
--[[ Code Bot JOB 67 remainder (2026-10-02): THE central config for the owned-asset upgrade (batch 1 walls + base props, batch 2
	outlying POI buildings, batch 3 Synty vehicle wrecks). Server: Services/Job67DressService.

	One upgrade source: the wall tier IS the saved DefensiveWalls level (BaseConfig.Structures.DefensiveWalls,
	profile.BaseUpgrades.DefensiveWalls; the buy UI and gameplay read the same number) -> Walls.Tiers[level]. The base
	prop tier is read from the same saved BaseUpgrades (the sum of the structure levels -> BaseProps.TierAt). No new save
	keys, no level changes, no prices.

	Owner-first: every block below is RetentionConfig.Live(block, <base owner>) (Enabled + OwnerFirst = only the
	playtest owner's base wears it; other players SEE his base). Flip OwnerFirst = false for the public; Enabled = false
	is the single switch back to today's look for that area.

	Assets (all on shaunie6; probed headlessly on the live place, Open Cloud Luau Execution, place v203:
	tools/probes/j67_packs_audit.luau, docs/we_check2_job67_b1.txt): 0 scripts in every pack below, 0 Humanoids.
	Mobile rules (applied by the service on every clone): anchored, CanCollide / CanTouch / CanQuery OFF (the Part walls
	and kits stay the colliders = Box collision), CastShadow off (Shadow = true only on the wall-sized Hesco),
	lights / sounds / FX / scripts / prompts / GUIs / ValueBases stripped. RenderFidelity cannot be written by a game
	script (Plugin capability, probed); every pack piece used here already ships with RenderFidelity = Automatic.
	Triangles: Creator Store totals (toolbox-service objectMeshSummary). A game script cannot read a mesh's triangle
	count (CreateEditableMeshAsync: "no permission" on non-forkable meshes, probed), so the budgets below count PIECES
	of the one mesh whose triangles are known exactly (the Hesco block is a 1-mesh model: 17,247), and the phone test
	carries the rest. ]]

local Job67DressConfig = {
	Enabled = true,
	OwnerFirst = true, -- NEW-OWNER-FIRST (Code Bot JOB 67 remainder): flip with the big public flip
	LogTag = "[Job67Dress]",

	-- the owned packs (InsertService, loaded once per server each, scripts stripped before anything is cloned)
	Packs = {
		Supplies = 70726960831586, -- Military Supplies Props Pack (NyrexBLX, PAID): 204 MeshParts, store triangles not published
		Sandbags = 71112106874796, -- Realistic Trench Sandbags Pack (Hyper_verse, PAID): 26 MeshParts, 149,263 tris (whole pack)
		Crates = 87282634781307, -- Realistic Textured Crates and Boxes (Hyper_verse, PAID): 25 MeshParts, 10,914 tris (whole pack)
		Hesco = 116015230898207, -- Modular Concrete Hesco Barrier PBR (proloxSimba, PAID): 1 MeshPart, 17,247 tris
		Synty = 119390702773907, -- Polygon Military Vehicles (syntystudio, PAID): batch 3
		DesertHouse = 16365964601, -- Desert house (RussianAndRobloxer, free): batch 2 hero building (41,976 tris)
		PrinzHouses = 10055885754, -- Desert Houses (PrinzAaron, free): 3 houses, 459 parts total, 18,440 tris, 0 scripts (batch 2)
		CagCamp = 9939040273, -- CAG Desert house Camp (Jhiyandrino, free): 1 house, 164 parts, 46,740 tris, 0 scripts (batch 2)
		ImpHouse = 15654066038, -- Desert House (ImParadoxial, free): 281 parts, 41,774 tris, 0 scripts (24 FX + 16 lights stripped)
	},
	PackTriangles = {
		Sandbags = 149263,
		Crates = 10914,
		Hesco = 17247,
		DesertHouse = 41976,
		PrinzHouses = 18440,
		CagCamp = 46740,
		ImpHouse = 41774,
	},

	-- pieces: Name = a descendant name in the pack (FindFirstChild(name, true)), or MeshId = a MeshPart's mesh id (pieces
	-- whose names repeat). Line = true: a 1-mesh, unrotated piece whose Size may be fitted to a wall run (LongAxis =
	-- its long side). Tris = exact triangles when known.
	Pieces = {
		HescoBlock = { Pack = "Hesco", MeshId = 80205291975128, Line = true, LongAxis = "X", Natural = Vector3.new(118.04, 54.13, 55.68), Tris = 17247, Shadow = true },
		SandbagLine = { Pack = "Supplies", Name = "SM_Sandbags_02a", Line = true, LongAxis = "Z", Natural = Vector3.new(5.92, 5.03, 18.06) },
		SandbagStack = { Pack = "Supplies", Name = "SM_Sandbags_Stack_01a" },
		SandbagStackLow = { Pack = "Supplies", Name = "SM_Sandbags_Stack_01b" },
		BarbedWire = { Pack = "Supplies", Name = "SM_Barbed_Wire_Stop_01a" },
		BarbedWireB = { Pack = "Supplies", Name = "SM_Barbed_Wire_Stop_02a" },
		Blockade = { Pack = "Supplies", Name = "SM_Concrete_Blockade_01a" },
		Barrier = { Pack = "Supplies", Name = "SM_Barrier_01a" },
		Drum = { Pack = "Supplies", Name = "SM_Container_Drum_01a" },
		GasBarrel = { Pack = "Supplies", Name = "SM_Gas_Barrel_01a" },
		GasBarrelB = { Pack = "Supplies", Name = "SM_Gas_Barrel_02A" },
		AmmoCrate = { Pack = "Supplies", Name = "SM_Crate_01a" },
		AmmoCrateB = { Pack = "Supplies", Name = "SM_Crate_01b" },
		LongCrate = { Pack = "Supplies", Name = "SM_Crate_01d" },
		AirDrop = { Pack = "Supplies", Name = "SM_AirDrop_Supply_01a" },
		WoodCrateBig = { Pack = "Supplies", Name = "SM_Wood_Crate_01f" },
		LargeCrate = { Pack = "Supplies", Name = "SM_Large_Crate_01a" },
		SupplyBox = { Pack = "Supplies", Name = "SM_Supply_Container_01a" },
		WeaponCase = { Pack = "Supplies", Name = "SM_Case_16a.290" },
		JerryCan = { Pack = "Supplies", Name = "SM_Jerry_Can_01a" },
		Generator = { Pack = "Supplies", Name = "SM_Military_Generator_01a.004" },
		SatComms = { Pack = "Supplies", Name = "SM_Comms_Sat_01a.002" },
		TexCrateA = { Pack = "Crates", MeshId = 130767509451750 }, -- 5.8 x 5.8 x 2.9
		TexCrateB = { Pack = "Crates", MeshId = 131225718062329 }, -- 4.5 x 2.8 x 3.0
		TexCrateC = { Pack = "Crates", MeshId = 92798021164687 }, -- 3.5 x 3.5 x 2.3
		TexCrateD = { Pack = "Crates", MeshId = 134481527402711 }, -- 4.6 x 3.1 x 2.7
		TrenchLine = { Pack = "Sandbags", MeshId = 73339338434094 }, -- 13.4 long trench sandbag run
		TrenchCurve = { Pack = "Sandbags", MeshId = 99053079683491 }, -- 11.7 long
		TrenchNest = { Pack = "Sandbags", MeshId = 108744101942786 }, -- 15.3 x 11.1 x 8.3 sandbag emplacement
	},

	--[[ Walls: decoration only, around the Part ring StructureKitBuilder.SyncPerimeterWalls builds (the Part walls stay
		the colliders, the shot / raycast blockers and the gate geometry). Faces: "Gate" = WallGate_L / _R, "Sides",
		"Rear" = WallClosed. Hesco faces: the Part wall + its cap turn invisible (still collide) and the Hesco block is
		fitted over it (height = the wall, run split into pieces <= HescoStretch x the block's natural length at that
		height). A face that would pass MaxHesco gets sandbags instead (whole faces only). Lines: Supplies sandbag runs
		along the wall's outer foot. GateClear: no dressing within this many studs of the gate centre on the gate face
		(the AutoGun nests, guards and the road stay clear). ]]
	Walls = {
		Enabled = true,
		OwnerFirst = true, -- NEW-OWNER-FIRST
		HescoStretch = 2.0,
		LineStretch = 1.3,
		GateClear = 32,
		Tiers = {
			[1] = { Name = "Sandbag Line", Hesco = {}, Lines = { "Gate" }, GateStacks = 2, CornerStacks = false, Wire = 0, Blockades = 0, Trench = false, MaxHesco = 0 },
			[2] = { Name = "Sandbag Wall", Hesco = {}, Lines = { "Gate", "Sides" }, GateStacks = 4, CornerStacks = true, Wire = 0, Blockades = 0, Trench = false, MaxHesco = 0 },
			[3] = { Name = "Hesco Gate", Hesco = { "Gate" }, Lines = { "Sides" }, GateStacks = 4, CornerStacks = true, Wire = 2, Blockades = 0, Trench = false, MaxHesco = 6 },
			[4] = { Name = "Hesco Wall", Hesco = { "Gate", "Sides" }, Lines = { "Rear" }, GateStacks = 4, CornerStacks = true, Wire = 4, Blockades = 2, Trench = false, MaxHesco = 12 },
			[5] = { Name = "Hesco Fortress", Hesco = { "Gate", "Sides", "Rear" }, Lines = { "Rear" }, GateStacks = 6, CornerStacks = true, Wire = 6, Blockades = 4, Trench = true, MaxHesco = 14 },
		},
	},

	--[[ Base props: model clusters on the owner's plot (plot-local X / Z, the BaseLayoutConfig frame) that grow with the
		base. Tier = the first TierAt the SUM of the saved structure levels reaches (0 levels = no props). Each cluster
		Kind lists its pieces per tier (cumulative: tier 3 = the tier 1 + 2 + 3 pieces). Spots: the JOB 57 BaseLife prop
		spots + BaseLayoutConfig.WarzoneSpots (both already clear of the buildings and StorePropsConfig.BaseKeepOut).
		ReplacesKits: the BaseLife part-kit rows this replaces (skipped while this is live for the owner); HideWarzone:
		the part-built PlotWarzone crates / sandbags / barriers on the owner's plot are hidden (restored on clear). ]]
	BaseProps = {
		Enabled = true,
		OwnerFirst = true, -- NEW-OWNER-FIRST
		TierAt = { 1, 10, 22, 38, 55 },
		HideWarzone = true,
		ReplacesKits = { CrateStack = true, DrumGroup = true, SandbagNest = true, SandbagLine = true, ContainerStack = true },
		MaxPieces = 140, -- per plot, every tier
		Kinds = {
			Ammo = {
				{ { "AmmoCrate", 0, 0, 0 }, { "TexCrateC", 4.2, 0.5, 15 } },
				{ { "AmmoCrateB", 0, 6.2, 0 }, { "TexCrateB", -4.6, 0.4, -10 } },
				{ { "WeaponCase", 5.4, 5.8, 90 }, { "TexCrateA", -5.2, 6.4, 0 } },
				{ { "AirDrop", -9.8, 2.2, 20 }, { "JerryCan", 2.4, -3.0, 0 } },
				{ { "LargeCrate", 10.4, 1.0, 0 }, { "SupplyBox", 9.6, 8.6, 90 } },
			},
			Fuel = {
				{ { "Drum", 0, 0, 0 }, { "GasBarrel", 3.4, 0.4, 0 } },
				{ { "GasBarrelB", -3.4, 0.2, 0 }, { "JerryCan", 1.6, 3.4, 30 } },
				{ { "Drum", 0, -3.6, 0 }, { "GasBarrel", 3.6, -3.4, 0 } },
				{ { "Generator", -7.0, -1.0, 90 } },
				{ { "GasBarrelB", 7.0, 0.4, 0 }, { "Drum", 7.2, -3.4, 0 } },
			},
			Crates = {
				{ { "TexCrateA", 0, 0, 0 }, { "TexCrateD", 4.6, 0.2, 10 } },
				{ { "WoodCrateBig", -6.2, 0.4, 0 }, { "TexCrateB", 1.6, 4.2, -15 } },
				{ { "LongCrate", 6.8, 4.6, 90 }, { "TexCrateC", -2.4, 4.6, 0 } },
				{ { "SupplyBox", -6.4, 6.4, 0 }, { "AmmoCrate", 0, -4.6, 0 } },
				{ { "AirDrop", 10.6, -0.6, 0 }, { "LargeCrate", -11.8, 0.4, 0 } },
			},
			Nest = {
				{ { "SandbagStackLow", 0, 0, 0 } },
				{ { "SandbagStack", 0, -7.4, 0 }, { "AmmoCrate", 5.2, -3.6, 0 } },
				{ { "TrenchCurve", -6.6, -3.0, 90 } },
				{ { "SatComms", 5.6, 4.0, 0 }, { "TexCrateC", -4.2, 4.6, 0 } },
				{ { "TrenchNest", 0, 9.6, 0 } },
			},
			Line = {
				{ { "SandbagLine", 0, 0, 0 } },
				{ { "SandbagLine", 0, 18.2, 0 } },
				{ { "SandbagStackLow", 0, -12.6, 0 } },
				{ { "SandbagLine", 0, -24.4, 0 }, { "Drum", 4.6, 0, 0 } },
				{ { "TrenchLine", -5.0, 9.0, 0 } },
			},
			Barrier = {
				{ { "Barrier", 0, 0, 0 } },
				{ { "Blockade", 6.4, 0, 0 } },
				{ { "BarbedWireB", -7.4, 0, 0 } },
				{ { "Blockade", -14.0, 0, 0 } },
				{ { "Barrier", 13.0, 0, 0 } },
			},
		},
		-- BaseLife (JOB 57) spots: same places, real models (Yaw = the cluster's turn, degrees)
		Spots = {
			{ X = -57, Z = 26, Yaw = 0, Kind = "Ammo" },
			{ X = -57, Z = 40, Yaw = 30, Kind = "Fuel" },
			{ X = 68, Z = 124, Yaw = 15, Kind = "Crates" },
			{ X = 54, Z = 124, Yaw = 0, Kind = "Fuel" },
			{ X = 50, Z = -10, Yaw = 0, Kind = "Nest" },
			{ X = 80, Z = 20, Yaw = -20, Kind = "Ammo" },
			{ X = -20, Z = -130, Yaw = 90, Kind = "Crates" },
			{ X = -140, Z = 0, Yaw = 0, Kind = "Line" },
			{ X = 140, Z = 0, Yaw = 0, Kind = "Line" },
		},
		-- BaseLayoutConfig.WarzoneSpots i % 3 (MapSetup PlotWarzone): 0 = sandbag berm, 1 = crate + drum, 2 = barrier
		WarzoneKinds = { [0] = "Nest", [1] = "Crates", [2] = "Barrier" },
	},

	-- credits (CC-BY needs a visible credit once shipped; the Creator Store models need none but are listed). Shipped =
	-- false: approved by Shaun for batch 2 but not in the game yet (Sketchfab downloads need a signed-in account /
	-- API token the box does not have; the CGTrader building is a 201 MB FBX with 4 UDIM 8k texture sets: needs a
	-- decimate + re-bake pass in Blender before a Roblox mesh import). docs/ASSET_LICENSES.md has the same rows.
	Credits = {
		{ Title = "Desert Houses", Author = "PrinzAaron", Source = "Roblox Creator Store 10055885754", License = "Roblox Creator Store", Shipped = true },
		{ Title = "CAG Desert house Camp", Author = "Jhiyandrino", Source = "Roblox Creator Store 9939040273", License = "Roblox Creator Store", Shipped = true },
		{ Title = "Desert House", Author = "ImParadoxial", Source = "Roblox Creator Store 15654066038", License = "Roblox Creator Store", Shipped = true },
		{ Title = "Desert house", Author = "RussianAndRobloxer", Source = "Roblox Creator Store 16365964601", License = "Roblox Creator Store", Shipped = true },
		{ Title = "Polygon Military Vehicles", Author = "Synty Studios (syntystudio)", Source = "Roblox Creator Store 119390702773907 (paid)", License = "Roblox Creator Store", Shipped = true },
		{ Title = "Low-poly desert building", Author = "Sketchfab b3179b5b68264806b85441eec1dd8da4", Source = "https://sketchfab.com/3d-models/b3179b5b68264806b85441eec1dd8da4", License = "CC-BY 4.0", Shipped = false },
		{ Title = "Desert house", Author = "Webster3D", Source = "https://sketchfab.com/3d-models/c50babb583374543b34f9cc2a122c243", License = "CC-BY 4.0", Shipped = false },
		{ Title = "House", Author = "123a9el", Source = "https://sketchfab.com/3d-models/29c8806ec8794150802a58e582ad44a2", License = "CC-BY 4.0", Shipped = false },
		{ Title = "Desert house 01", Author = "filthycent", Source = "https://sketchfab.com/3d-models/2f7b88bbcf1b454cad2c3e9dbc9dd18e", License = "CC-BY 4.0", Shipped = false },
		{ Title = "Shanty", Author = "yadrogames", Source = "https://sketchfab.com/3d-models/64f09376d1a44ffd8716d7cc5f28db9c", License = "CC-BY 4.0", Shipped = false },
		{ Title = "Fences pack", Author = "yadrogames", Source = "https://sketchfab.com/3d-models/0cbf546419cf499cbabfee3af0916215", License = "CC-BY 4.0", Shipped = false },
		{ Title = "Free Arab City Building A", Author = "CGTrader", Source = "CGTrader (Royalty Free)", License = "CGTrader Royalty Free", Shipped = false },
		{ Title = "Arabic Neoclassical Tall Residential (B04)", Author = "CGTrader", Source = "CGTrader (Royalty Free)", License = "CGTrader Royalty Free", Shipped = false },
	},

	-- Batch 2 (Code Bot JOB 67): detailed desert buildings over the Part TownBlock kits of the outlying places (the POI
	-- "block" clusters; never the Town's houses, a heist / landmark kit, a gutted cache shell or a metal shed; never
	-- the owner's hand-built hero models). WORLD dressing, so the owner gate is "a live player is in this server" (the JOB 40 ReplaceRows rule):
	-- once Shaun is in a server it is dressed for everyone there. Enabled = false = the kits come back on the next
	-- apply (ClearBuildings restores every hidden kit part). The kit parts go invisible AND stop colliding / being hit
	-- (Transparency 1, CanCollide / CanQuery off, their lights / guis off; restored exactly); the model takes over as
	-- the collider (its parts >= CollideMinStuds: CanCollide + CanQuery on, Box-shaped Parts; small parts and every
	-- detail stay non-colliding), fitted to the kit footprint (x Grow, ScaleMin floor so doors stay player-sized), its
	-- bottom on the kit floor. Anchors, jobs and NPC posts never move (the probe checks each one stays outside the
	-- model box). Models: anchored, scripts / lights / FX stripped, CastShadow only on parts >= ShadowMinStuds.
	-- Batch 3 (Code Bot JOB 67): Shaun's paid Synty Polygon Military Vehicles pack (119390702773907, 0 scripts) over the
	-- outlying places' Part vehicle wrecks (WorldKits "Wreck" truck / car / tank kits and the camp HeliWreck; never a
	-- gun-pit wreck). Same world rule and code path as Buildings (live once a player it is live for is in the server).
	-- Collide = "Kit": the Part wreck stays the collider / cover (invisible), the Synty wreck (1 MeshPart, its own
	-- SurfaceAppearance) is visual only, so cover, anchors and NPC posts are exactly as before. Boxes = each kit's
	-- footprint in its own frame (probed: tools/probes/j67_b3_harness.py builds the real kits).
	Wrecks = {
		Enabled = true,
		OwnerFirst = true, -- NEW-OWNER-FIRST
		Tag = "Wrecks",
		Collide = "Kit",
		Grow = 1.3, -- a wreck may read a little bigger than the old Part kit (the kit stays the collider)
		ScaleMin = 0.4,
		ScaleMax = 1.0,
		ShadowMinStuds = 8,
		MaxModels = 14,
		MaxPerPoi = 2,
		Boxes = {
			Wreck = { truck = { -7.9, 8.0, -1.1, 5.5 }, car = { -4.1, 4.0, 0.1, 5.4 }, tank = { -8.2, 5.2, -0.9, 7.4 } },
			HeliWreck = { default = { -6.1, 6.9, -12.0, 12.0 } },
		},
		-- Turn 90: the Synty wreck's long side (Z) along the kit's long side (X); the heli kit is long in Z
		Models = {
			TruckWreck = { Pack = "Synty", Name = "SM_Veh_Truck_01_Destroyed", Turn = 90 },
			TechnicalWreck = { Pack = "Synty", Name = "SM_Veh_Pickup_Technical_Destroyed_01", Turn = 90 },
			PickupWreck = { Pack = "Synty", Name = "SM_Veh_Pickup_Small_Destroyed_01", Turn = 90 },
			VanWreck = { Pack = "Synty", Name = "SM_Veh_Van_Destroyed_01", Turn = 90 },
			CarWreck = { Pack = "Synty", Name = "SM_Veh_Car_Medium_Destroyed_01", Turn = 90 },
			SmallCarWreck = { Pack = "Synty", Name = "SM_Veh_Car_Small_Destroyed_01", Turn = 90 },
			SUVWreck = { Pack = "Synty", Name = "SM_Veh_SUV_Destroyed_01", Turn = 90 },
			TankWreckA = { Pack = "Synty", Name = "SM_Veh_Tank_USA_Destroyed_01", Turn = 90 },
			TankWreckB = { Pack = "Synty", Name = "SM_Veh_Light_Tank_01_Destroyed", Turn = 90 },
			HeliWreck = { Pack = "Synty", Name = "SM_Veh_Helicopter_Attack_02_Destroyed", Turn = 0 },
		},
		Rows = {
			{ Poi = "Airstrip", Cluster = "N_Bowser", Kit = "Wreck", Model = "TruckWreck" },
			{ Poi = "FortI", Cluster = "Tank", Kit = "Wreck", Model = "TankWreckA" },
			{ Poi = "FortS", Cluster = "Tank", Kit = "Wreck", Model = "TankWreckB" },
			{ Poi = "Depot", Cluster = "N_Trucks", Kit = "Wreck", KitIndex = 1, Model = "TruckWreck" },
			{ Poi = "Depot", Cluster = "N_Trucks", Kit = "Wreck", KitIndex = 2, Model = "TechnicalWreck" },
			{ Poi = "OilField", Cluster = "YardCover2", Kit = "Wreck", Model = "TruckWreck" },
			{ Poi = "Ruins", Cluster = "Car_1", Kit = "Wreck", Model = "CarWreck" },
			{ Poi = "Ruins", Cluster = "Car_2", Kit = "Wreck", Model = "SmallCarWreck" },
			{ Poi = "Crash", Cluster = "Engine", Kit = "Wreck", Model = "SUVWreck" },
			{ Poi = "Crash", Cluster = "Recovery", Kit = "Wreck", Model = "TruckWreck" },
			{ Poi = "Quarry", Cluster = "Dump_1", Kit = "Wreck", Model = "VanWreck" },
			{ Poi = "Quarry", Cluster = "Dump_2", Kit = "Wreck", Model = "PickupWreck" },
			{ Poi = "RidgeCamp", Cluster = "Technical", Kit = "Wreck", Model = "TechnicalWreck" },
			{ Poi = "DuneCamp", Cluster = "Heli", Kit = "HeliWreck", Model = "HeliWreck" },
		},
	},
	Buildings = {
		Enabled = true,
		OwnerFirst = true, -- NEW-OWNER-FIRST
		Grow = 1.15, -- the model may stand this much past the kit footprint
		ScaleMin = 0.6, -- below this the doors get shorter than a player
		CollideMinStuds = 4,
		ScaleMax = 1.2,
		ShadowMinStuds = 8,
		MaxModels = 12,
		MaxPerPoi = 2,
		-- Turn = the model's yaw so its long side runs along the kit Width (local X); Parts = after stripping
		Models = {
			PrinzHouse1 = { Pack = "PrinzHouses", Name = "Desert House 1", Turn = 0, Parts = 93 },
			PrinzHouse2 = { Pack = "PrinzHouses", Name = "Desert House 2", Turn = 0, Parts = 170 },
			PrinzHouse3 = { Pack = "PrinzHouses", Name = "Desert House 3", Turn = 0, Parts = 210 },
			CagHouse = { Pack = "CagCamp", Name = "Model", Turn = 0, Parts = 164, Tris = 46740 },
			ImpHouse = { Pack = "ImpHouse", Name = "Desert House", Turn = 90, Parts = 257, Tris = 41774 },
			ArcadeHouse = { Pack = "DesertHouse", Name = "Desert house", Turn = 0, Parts = 312, Tris = 41976 },
		},
		-- Poi = WorldConfig.POIs Id, Cluster = the POILayouts cluster Id (its TownBlock kit)
		Rows = {
			{ Poi = "Port", Cluster = "E_Office", Model = "ImpHouse" }, -- 24 x 18, 3 storeys
			{ Poi = "Port", Cluster = "E_Block2", Model = "PrinzHouse1" }, -- 22 x 18 damaged
			{ Poi = "Depot", Cluster = "N_Barracks", Model = "PrinzHouse2" }, -- 30 x 14
			{ Poi = "Depot", Cluster = "S_Garrison", Model = "ArcadeHouse" }, -- 30 x 16
			{ Poi = "Armory", Cluster = "N_Barracks", Model = "PrinzHouse2" }, -- 28 x 14
			{ Poi = "Airstrip", Cluster = "S_Ops", Model = "PrinzHouse3" }, -- 26 x 16
			{ Poi = "Signal", Cluster = "W_Block", Model = "PrinzHouse1" }, -- 22 x 16 damaged
			{ Poi = "Ruins", Cluster = "R_2", Model = "PrinzHouse2" }, -- 24 x 18 damaged (not a cache shell)
			{ Poi = "Ruins", Cluster = "R_8", Model = "CagHouse" }, -- 22 x 18 (not a cache shell)
			{ Poi = "OilField", Cluster = "Shack_S", Model = "CagHouse" }, -- 20 x 14 damaged
		},
	},
}

-- the wall tier block for a saved DefensiveWalls level (pure; nil at 0)
function Job67DressConfig.WallTier(level: number): any
	local lv = math.clamp(math.floor(tonumber(level) or 0), 0, 5)
	if lv <= 0 then
		return nil
	end
	return Job67DressConfig.Walls.Tiers[lv]
end

-- the base prop tier (0..5) for the sum of the saved structure levels (pure)
function Job67DressConfig.PropTier(levelSum: number): number
	local t = 0
	for i, at in ipairs(Job67DressConfig.BaseProps.TierAt) do
		if (tonumber(levelSum) or 0) >= at then
			t = i
		end
	end
	return t
end

-- Hesco pieces for one wall run at a wall height (pure): the count and each piece's length
function Job67DressConfig.HescoSplit(runLength: number, wallHeight: number): (number, number)
	local p = Job67DressConfig.Pieces.HescoBlock
	local natural = p.Natural.X * (wallHeight / p.Natural.Y)
	local n = math.max(1, math.ceil(runLength / (natural * Job67DressConfig.Walls.HescoStretch) - 1e-6))
	return n, runLength / n
end

return Job67DressConfig
