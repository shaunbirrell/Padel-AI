--!strict
--[[
	Part-kit silhouettes + palettes for base structures.
	STRUCTURE_SCALE_WIRE v21: TargetFootprint drives VisualAssetService ScaleTo.
	Part kits remain fallback; catalog mesh NEVER sized to host plinth.
]]

export type StructurePalette = {
	Plinth: Color3,
	Body: Color3,
	Accent: Color3,
	Roof: Color3,
	Kit: "hq" | "barracks" | "depot" | "lab" | "tower" | "pad" | "dock" | "wall" | "power" | "warehouse" | "special" | "airfield" | "helipad" | "hangar" | "armory" | "radar",
	TargetFootprint: Vector3?,
	MeshAssetId: number?,
	MeshAssetIdL3: number?,
}

local StructureVisualConfig = {
	GhostTransparency = 0.72,
	SolidTransparency = 0,
	PreferMeshWhenAssetIdSet = false, -- v44 P0 hotfix: Part kits only until visibility proven; re-enable design meshes later
	PreferMeshMinLevel = 1,
	BuildingDressGen = 29, -- v42 DressGen: Hangar≠Warehouse≠Depot, Missile≠Tower; kits stay visible

	--[[
		v67 base look: one military scheme. Palettes below are sand concrete / olive / dark metal with a
		muted per-type Accent used only on small details. The kit "Accent" footprint plate is a concrete
		foundation now (it was a Neon plate scaled to 1.4x the footprint: the glowing purple/green floors).
	]]
	FoundationColor = Color3.fromRGB(146, 142, 130),
	BaseLook = {
		PlotFloor = Color3.fromRGB(168, 162, 148), -- plot pad (was near-black navy)
		PlotEdge = Color3.fromRGB(86, 98, 64), -- painted olive edge (was a green Neon strip)
		Chevron = Color3.fromRGB(230, 196, 70), -- yellow floor paint (was white Neon)
		WallCap = Color3.fromRGB(132, 126, 110),
		Wire = Color3.fromRGB(58, 60, 56),
		GateStripe = Color3.fromRGB(214, 178, 64),
	},
	-- v68: no roof at all over bases (owner). If re-enabled, the barrier is invisible at this height.
	AntiAirCeilingEnabled = false,
	AntiAirCeilingHeight = 48,

	Palettes = {
		CommandCenter = {
			Plinth = Color3.fromRGB(72, 82, 58),
			Body = Color3.fromRGB(200, 186, 150),
			Accent = Color3.fromRGB(214, 178, 64),
			Roof = Color3.fromRGB(84, 86, 80),
			Kit = "hq",
			TargetFootprint = Vector3.new(36, 16, 28),
			MeshAssetId = 138331074285379,
		},
		Barracks = {
			Plinth = Color3.fromRGB(72, 82, 58),
			Body = Color3.fromRGB(176, 168, 136),
			Accent = Color3.fromRGB(120, 136, 86),
			Roof = Color3.fromRGB(86, 98, 64),
			Kit = "barracks",
			TargetFootprint = Vector3.new(28, 12, 16),
			MeshAssetId = 18798977801,
		},
		VehicleDepot = {
			Plinth = Color3.fromRGB(72, 82, 58),
			Body = Color3.fromRGB(150, 150, 140),
			Accent = Color3.fromRGB(98, 118, 130),
			Roof = Color3.fromRGB(84, 86, 80),
			Kit = "depot",
			TargetFootprint = Vector3.new(32, 14, 24),
			MeshAssetId = 12208876851, -- v42 arched depot ≠ Hangar
		},
		WeaponsFacility = {
			Plinth = Color3.fromRGB(72, 82, 58),
			Body = Color3.fromRGB(164, 150, 128),
			Accent = Color3.fromRGB(150, 82, 58),
			Roof = Color3.fromRGB(70, 72, 68),
			Kit = "armory",
			TargetFootprint = Vector3.new(28, 18, 18),
			MeshAssetId = 4120970784,
		},
		Helipad = {
			Plinth = Color3.fromRGB(72, 82, 58),
			Body = Color3.fromRGB(96, 98, 92),
			Accent = Color3.fromRGB(214, 178, 64),
			Roof = Color3.fromRGB(70, 72, 68),
			Kit = "helipad",
			TargetFootprint = Vector3.new(28, 4, 28),
			MeshAssetId = 14313845338,
		},
		Dock = {
			Plinth = Color3.fromRGB(72, 82, 58),
			Body = Color3.fromRGB(120, 112, 96),
			Accent = Color3.fromRGB(98, 118, 130),
			Roof = Color3.fromRGB(84, 86, 80),
			Kit = "dock",
			TargetFootprint = Vector3.new(44, 10, 28),
			MeshAssetId = 17701461178,
		},
		Airfield = {
			Plinth = Color3.fromRGB(72, 82, 58),
			Body = Color3.fromRGB(90, 92, 88),
			Accent = Color3.fromRGB(150, 150, 142),
			Roof = Color3.fromRGB(70, 72, 68),
			Kit = "airfield",
			TargetFootprint = Vector3.new(72, 1, 14),
			MeshAssetId = 0, -- COMPOSITE runway + Hangar 6015472062; REJECT 12370174722
		},
		DefensiveWalls = {
			Plinth = Color3.fromRGB(72, 82, 58),
			Body = Color3.fromRGB(178, 170, 148),
			Accent = Color3.fromRGB(132, 126, 110),
			Roof = Color3.fromRGB(84, 86, 80),
			Kit = "wall",
			TargetFootprint = Vector3.new(24, 8, 3),
			MeshAssetId = 0, -- v41: NO Wall* segment catalog dress (Part-kit walls only)
			MeshAssetIdL3 = 0, -- v41: Part-kit heavy walls
		},
		Watchtowers = {
			Plinth = Color3.fromRGB(72, 82, 58),
			Body = Color3.fromRGB(120, 100, 74),
			Accent = Color3.fromRGB(92, 76, 56),
			Roof = Color3.fromRGB(86, 98, 64),
			Kit = "tower",
			TargetFootprint = Vector3.new(10, 34, 10),
			MeshAssetId = 108525417345747,
		},
		Radar = {
			Plinth = Color3.fromRGB(72, 82, 58),
			Body = Color3.fromRGB(170, 172, 168),
			Accent = Color3.fromRGB(98, 118, 130),
			Roof = Color3.fromRGB(84, 86, 80),
			Kit = "radar",
			TargetFootprint = Vector3.new(14, 18, 14),
			MeshAssetId = 9559610195,
		},
		ResearchLab = {
			Plinth = Color3.fromRGB(72, 82, 58),
			Body = Color3.fromRGB(186, 184, 176),
			Accent = Color3.fromRGB(98, 130, 120),
			Roof = Color3.fromRGB(84, 86, 80),
			Kit = "lab",
			TargetFootprint = Vector3.new(22, 12, 16),
			MeshAssetId = 17725725,
		},
		MissileDefense = {
			Plinth = Color3.fromRGB(72, 82, 58),
			Body = Color3.fromRGB(106, 112, 86),
			Accent = Color3.fromRGB(150, 82, 58),
			Roof = Color3.fromRGB(70, 72, 68),
			Kit = "tower",
			TargetFootprint = Vector3.new(14, 10, 18), -- v42 launcher mass, not tower height
			MeshAssetId = 0, -- W1 CFG: real-world launcher mesh dropped (was 11962508154); Part kit "tower" (Missile Battery ≠ Watchtower)
		},
		PowerStation = {
			Plinth = Color3.fromRGB(72, 82, 58),
			Body = Color3.fromRGB(150, 150, 140),
			Accent = Color3.fromRGB(214, 178, 64),
			Roof = Color3.fromRGB(84, 86, 80),
			Kit = "power",
			TargetFootprint = Vector3.new(28, 16, 20),
			MeshAssetId = 14000967030,
		},
		Warehouse = {
			Plinth = Color3.fromRGB(72, 82, 58),
			Body = Color3.fromRGB(170, 150, 118),
			Accent = Color3.fromRGB(150, 120, 80),
			Roof = Color3.fromRGB(96, 90, 80),
			Kit = "warehouse",
			TargetFootprint = Vector3.new(38, 16, 24),
			MeshAssetId = 15942568272, -- v42 hangar shed ≠ Hangar
		},
		SpecialForcesFacility = {
			Plinth = Color3.fromRGB(72, 82, 58),
			Body = Color3.fromRGB(92, 96, 90),
			Accent = Color3.fromRGB(104, 112, 96),
			Roof = Color3.fromRGB(60, 62, 58),
			Kit = "special",
			TargetFootprint = Vector3.new(32, 16, 20),
			MeshAssetId = 18798977801,
		},
	} :: { [string]: StructurePalette },

	--[[
		v66: walk-in buildings (Modules/HollowBuildingBuilder). The kit Body becomes the foundation slab;
		walls/doorway/windows/interior are a Model rebuilt per level. The building sits BEHIND its pad and the
		doorway is shifted sideways so going inside never re-triggers the walk-over buy (pad hit box = ±8 studs).
		Local axes: +Z = building front (faces the plot spawn), X = across the facade.
	]]
	-- v68: lights made by walk-in shells, interiors and installations (HollowBuildingBuilder). Interiors were
	-- blinding: 6-8 Neon ceiling strips per room, each with a 20-stud full-brightness PointLight, under bloom.
	BuildingLights = {
		BrightnessScale = 0.35, -- multiplies every PointLight these builders create
		MaxRange = 16,
		FixtureMaterial = Enum.Material.SmoothPlastic, -- ceiling / entry / hangar fittings (was Neon)
		FixtureColor = Color3.fromRGB(232, 226, 208),
		SpotMaxRange = 30, -- floodlights / searchlights (outdoors)
	},

	-- v69: world lighting. Ambient lights every surface the sky can't reach — at (165,145,110) every interior wall
	-- glowed ~60 % white (the "blinding" rooms). OutdoorAmbient (outdoor shade) is unchanged.
	WorldLighting = {
		DayAmbient = Color3.fromRGB(78, 72, 62),
		EnvironmentDiffuseScale = 0.35,
	},

	-- v68: outdoor installations — a detailed model from Modules/Installations/<Module>.luau on a concrete
	-- foundation (the kit Body), rebuilt per level by HollowBuildingBuilder. Only with BaseLayoutConfig.
	-- Width/Depth = foundation footprint (building-local, +Z = the side facing the plot front).
	Installations = {
		PowerStation = { Enabled = true, Module = "PowerStation", Width = 30, Depth = 22 },
		Radar = { Enabled = true, Module = "Radar", Width = 24, Depth = 20 },
		MissileDefense = { Enabled = true, Module = "MissileDefense", Width = 24, Depth = 22 },
		Watchtowers = { Enabled = true, Module = "Watchtower", Width = 10, Depth = 10 },
		DefensiveWalls = { Enabled = true, Module = "Checkpoint", Width = 20, Depth = 10 },
		Airfield = { Enabled = true, Module = "Airfield", Width = 58, Depth = 34 },
	},

	-- v72 budget (phone): static soldier kits (gate guards, yard workers) without the 7 small detail parts
	-- (MapSetup.makeSoldierKit): 16 -> 9 parts each, -84 parts per base. true = the old detailed kit.
	StaticSoldierDetail = false,
	-- v72: walk-in building stairs stay step boxes. "Ramp" (one wedge per flight, -75 parts per base at L5) is a
	-- reserve cut only; nothing reads this key until that cut is needed.
	StairStyle = "Steps",

	HollowBuildings = {
		-- Shared by every walk-in building; per-building entries override (Colors merge key by key).
		Defaults = {
			WallThickness = 0.8,
			StoryHeight = 12,
			UpperStoryHeight = 10,
			DoorWidth = 6,
			DoorHeight = 8,
			WindowWidth = 4.5,
			WindowHeight = 3.2,
			WindowBottom = 4,
			FrontGap = 10, -- legacy (no BaseLayoutConfig): pad centre → front wall
			OffsetX = 6, -- legacy: footprint centre east of the pad
			AnnexLevel = 99, -- comms annex + mast + floodlights (Command Center)
			TwoStoryLevel = 99, -- second storey + interior stairs
			RoofAccessLevel = 99, -- truss ladder through a roof hatch + dish
			HelipadLevel = 99, -- rooftop helipad marking
			GoldCapLevel = 5, -- gold parapet cap + flag finial
			FlagLevel = 1,
			Colors = {
				Wall = Color3.fromRGB(214, 200, 168),
				Trim = Color3.fromRGB(78, 92, 62),
				Metal = Color3.fromRGB(70, 74, 72),
				Dark = Color3.fromRGB(28, 32, 30),
				Floor = Color3.fromRGB(150, 150, 142),
				Stair = Color3.fromRGB(128, 126, 118),
				Roof = Color3.fromRGB(112, 108, 96),
				Glass = Color3.fromRGB(140, 190, 215),
				Accent = Color3.fromRGB(230, 196, 70), -- signs, hazard paint
				Gold = Color3.fromRGB(240, 196, 64),
				Screen = Color3.fromRGB(90, 255, 140),
				Light = Color3.fromRGB(255, 236, 200),
				Locker = Color3.fromRGB(86, 100, 70),
				Rug = Color3.fromRGB(58, 74, 50),
				Sandbag = Color3.fromRGB(186, 164, 118),
				Flag = Color3.fromRGB(70, 110, 60),
			},
		},
		CommandCenter = {
			Enabled = true,
			Interior = "CommandCenter",
			Width = 26,
			Depth = 20,
			DoorX = 7,
			FrontWindowsX = { -8.5, -2 },
			BackWindowsX = { -6, 4 }, -- ground floor only while single-storey (stairs take the back wall)
			WestWindowsZ = { -7 },
			UpperWindowsX = { -8.5, -2, 7 },
			AnnexLevel = 2,
			AnnexWidth = 12,
			AnnexDepth = 14,
			AnnexHeight = 9,
			TwoStoryLevel = 3,
			RoofAccessLevel = 4,
			HelipadLevel = 5,
			SignText = "COMMAND CENTER",
			SignX = 0,
		},
		Barracks = {
			Enabled = true,
			Interior = "Barracks",
			Width = 32,
			Depth = 24,
			DoorX = 10,
			FrontWindowsX = { -11, -4, 3 },
			BackWindowsX = { -10, 0, 10 },
			WestWindowsZ = { -6, 6 },
			EastWindowsZ = { -6, 6 },
			UpperWindowsX = { -11, -4, 3, 10 },
			TwoStoryLevel = 3,
			SignText = "BARRACKS",
			Colors = { Wall = Color3.fromRGB(196, 184, 150) },
		},
		WeaponsFacility = {
			Enabled = true,
			Interior = "Armory",
			Width = 30,
			Depth = 22,
			DoorX = 9,
			FrontWindowsX = { -10, -3 },
			BackWindowsX = { -8, 8 },
			WestWindowsZ = { 0 },
			EastWindowsZ = { 0 },
			TwoStoryLevel = 4,
			SignText = "ARMORY",
			Colors = { Wall = Color3.fromRGB(184, 176, 156) },
		},
		SpecialForcesFacility = {
			Enabled = true,
			Interior = "SpecialForces",
			Width = 30,
			Depth = 22,
			DoorX = 9,
			FrontWindowsX = { -10, -3 },
			TwoStoryLevel = 3,
			SignText = "SPECIAL FORCES",
			Colors = { Wall = Color3.fromRGB(128, 128, 120), Trim = Color3.fromRGB(52, 56, 50) },
		},
		VehicleDepot = {
			Enabled = true,
			Interior = "VehicleDepot",
			Width = 36,
			Depth = 28,
			StoryHeight = 14,
			DoorStyle = "Garage",
			DoorX = 2,
			DoorWidth = 16,
			DoorHeight = 11,
			FrontWindowsX = { -13.5 },
			WestWindowsZ = { -6, 6 },
			EastWindowsZ = { -6, 6 },
			Skylights = true,
			SignText = "VEHICLE DEPOT",
			Colors = { Wall = Color3.fromRGB(172, 170, 160) },
		},
		Warehouse = {
			Enabled = true,
			Interior = "Warehouse",
			Width = 34,
			Depth = 26,
			StoryHeight = 14,
			DoorStyle = "Garage",
			DoorX = 3,
			DoorWidth = 12,
			DoorHeight = 10,
			FrontWindowsX = { -11.5 },
			Skylights = true,
			SignText = "WAREHOUSE",
			Colors = { Wall = Color3.fromRGB(190, 172, 140) },
		},
		ResearchLab = {
			Enabled = true,
			Interior = "ResearchLab",
			Width = 30,
			Depth = 22,
			DoorX = 9,
			FrontWindowsX = { -10, -3.5, 3 },
			BackWindowsX = { -8, 0, 8 },
			WestWindowsZ = { -5, 5 },
			EastWindowsZ = { -5, 5 },
			TwoStoryLevel = 3,
			SignText = "RESEARCH LAB",
			Colors = { Wall = Color3.fromRGB(206, 204, 196), Trim = Color3.fromRGB(88, 104, 112) },
		},
	},
}

return StructureVisualConfig
