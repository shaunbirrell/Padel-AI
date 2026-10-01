--!strict
--[[ Code Bot JOB 67 remainder (2026-10-02): THE central config for the owned-asset upgrade (walls, base props; town /
	outposts / rebirth zones and Synty vehicles join it in later batches). Server: Services/Job67DressService.

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
	},
	PackTriangles = {
		Sandbags = 149263,
		Crates = 10914,
		Hesco = 17247,
		DesertHouse = 41976,
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
