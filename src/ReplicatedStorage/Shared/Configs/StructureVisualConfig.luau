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

	Palettes = {
		CommandCenter = {
			Plinth = Color3.fromRGB(36, 48, 40),
			Body = Color3.fromRGB(55, 78, 58),
			Accent = Color3.fromRGB(230, 190, 60),
			Roof = Color3.fromRGB(40, 55, 45),
			Kit = "hq",
			TargetFootprint = Vector3.new(36, 16, 28),
			MeshAssetId = 138331074285379,
		},
		Barracks = {
			Plinth = Color3.fromRGB(42, 46, 38),
			Body = Color3.fromRGB(70, 78, 55),
			Accent = Color3.fromRGB(90, 160, 80),
			Roof = Color3.fromRGB(50, 55, 42),
			Kit = "barracks",
			TargetFootprint = Vector3.new(28, 12, 16),
			MeshAssetId = 18798977801,
		},
		VehicleDepot = {
			Plinth = Color3.fromRGB(40, 48, 55),
			Body = Color3.fromRGB(58, 72, 88),
			Accent = Color3.fromRGB(90, 160, 220),
			Roof = Color3.fromRGB(45, 55, 65),
			Kit = "depot",
			TargetFootprint = Vector3.new(32, 14, 24),
			MeshAssetId = 12208876851, -- v42 arched depot ≠ Hangar
		},
		WeaponsFacility = {
			Plinth = Color3.fromRGB(48, 40, 38),
			Body = Color3.fromRGB(88, 58, 50),
			Accent = Color3.fromRGB(200, 90, 70),
			Roof = Color3.fromRGB(55, 42, 40),
			Kit = "armory",
			TargetFootprint = Vector3.new(28, 18, 18),
			MeshAssetId = 4120970784,
		},
		Helipad = {
			Plinth = Color3.fromRGB(45, 50, 48),
			Body = Color3.fromRGB(60, 70, 65),
			Accent = Color3.fromRGB(220, 200, 80),
			Roof = Color3.fromRGB(50, 55, 52),
			Kit = "helipad",
			TargetFootprint = Vector3.new(28, 4, 28),
			MeshAssetId = 14313845338,
		},
		Dock = {
			Plinth = Color3.fromRGB(35, 48, 58),
			Body = Color3.fromRGB(50, 75, 95),
			Accent = Color3.fromRGB(70, 180, 220),
			Roof = Color3.fromRGB(40, 58, 70),
			Kit = "dock",
			TargetFootprint = Vector3.new(44, 10, 28),
			MeshAssetId = 17701461178,
		},
		Airfield = {
			Plinth = Color3.fromRGB(50, 52, 48),
			Body = Color3.fromRGB(70, 72, 68),
			Accent = Color3.fromRGB(180, 190, 100),
			Roof = Color3.fromRGB(55, 58, 52),
			Kit = "airfield",
			TargetFootprint = Vector3.new(72, 1, 14),
			MeshAssetId = 0, -- COMPOSITE runway + Hangar 6015472062; REJECT 12370174722
		},
		DefensiveWalls = {
			Plinth = Color3.fromRGB(48, 48, 45),
			Body = Color3.fromRGB(120, 160, 55), -- v45 bright olive (impossible to miss)
			Accent = Color3.fromRGB(180, 255, 80), -- neon top cap
			Roof = Color3.fromRGB(60, 60, 55),
			Kit = "wall",
			TargetFootprint = Vector3.new(24, 8, 3),
			MeshAssetId = 0, -- v41: NO Wall* segment catalog dress (Part-kit walls only)
			MeshAssetIdL3 = 0, -- v41: Part-kit heavy walls
		},
		Watchtowers = {
			Plinth = Color3.fromRGB(44, 46, 40),
			Body = Color3.fromRGB(72, 78, 60),
			Accent = Color3.fromRGB(200, 160, 70),
			Roof = Color3.fromRGB(50, 52, 44),
			Kit = "tower",
			TargetFootprint = Vector3.new(10, 34, 10),
			MeshAssetId = 108525417345747,
		},
		Radar = {
			Plinth = Color3.fromRGB(40, 42, 55),
			Body = Color3.fromRGB(55, 60, 90),
			Accent = Color3.fromRGB(100, 200, 255),
			Roof = Color3.fromRGB(45, 48, 70),
			Kit = "radar",
			TargetFootprint = Vector3.new(14, 18, 14),
			MeshAssetId = 9559610195,
		},
		ResearchLab = {
			Plinth = Color3.fromRGB(38, 45, 55),
			Body = Color3.fromRGB(50, 70, 95),
			Accent = Color3.fromRGB(80, 180, 220),
			Roof = Color3.fromRGB(42, 55, 72),
			Kit = "lab",
			TargetFootprint = Vector3.new(22, 12, 16),
			MeshAssetId = 17725725,
		},
		MissileDefense = {
			Plinth = Color3.fromRGB(48, 42, 40),
			Body = Color3.fromRGB(75, 55, 50),
			Accent = Color3.fromRGB(220, 100, 60),
			Roof = Color3.fromRGB(55, 45, 42),
			Kit = "tower",
			TargetFootprint = Vector3.new(14, 10, 18), -- v42 launcher mass, not tower height
			MeshAssetId = 11962508154, -- Missile Battery ≠ Watchtower
		},
		PowerStation = {
			Plinth = Color3.fromRGB(50, 48, 35),
			Body = Color3.fromRGB(90, 85, 50),
			Accent = Color3.fromRGB(255, 210, 70),
			Roof = Color3.fromRGB(60, 55, 40),
			Kit = "power",
			TargetFootprint = Vector3.new(28, 16, 20),
			MeshAssetId = 14000967030,
		},
		Warehouse = {
			Plinth = Color3.fromRGB(45, 42, 38),
			Body = Color3.fromRGB(95, 80, 60),
			Accent = Color3.fromRGB(180, 140, 80),
			Roof = Color3.fromRGB(55, 50, 42),
			Kit = "warehouse",
			TargetFootprint = Vector3.new(38, 16, 24),
			MeshAssetId = 15942568272, -- v42 hangar shed ≠ Hangar
		},
		SpecialForcesFacility = {
			Plinth = Color3.fromRGB(35, 38, 42),
			Body = Color3.fromRGB(45, 55, 65),
			Accent = Color3.fromRGB(160, 80, 200),
			Roof = Color3.fromRGB(30, 35, 40),
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
	HollowBuildings = {
		CommandCenter = {
			Enabled = true,
			Width = 26,
			Depth = 20,
			WallThickness = 0.8,
			StoryHeight = 12,
			UpperStoryHeight = 10,
			FrontGap = 10, -- pad centre → front wall (pad hit box reaches 8)
			OffsetX = 6, -- footprint centre east of the pad; with DoorX = 7 the doorway is 13 studs from the pad
			DoorX = 7,
			DoorWidth = 6,
			DoorHeight = 8,
			WindowWidth = 4.5,
			WindowHeight = 3.2,
			WindowBottom = 4,
			FrontWindowsX = { -8.5, -2 },
			BackWindowsX = { -6, 4 }, -- ground floor only while single-storey (stairs take the back wall at L3+)
			WestWindowsZ = { -7 },
			UpperWindowsX = { -8.5, -2, 7 },
			AnnexLevel = 2, -- comms annex, roof mast, floodlights
			AnnexWidth = 12,
			AnnexDepth = 14,
			AnnexHeight = 9,
			TwoStoryLevel = 3, -- second storey + interior stairs
			RoofAccessLevel = 4, -- truss ladder through a roof hatch + satellite dish
			HelipadLevel = 5, -- rooftop helipad marking, gold parapet cap, tall flag
			SignText = "COMMAND CENTER",
			SignX = 0,
			Colors = {
				Wall = Color3.fromRGB(214, 200, 168),
				Trim = Color3.fromRGB(78, 92, 62),
				Metal = Color3.fromRGB(70, 74, 72),
				Dark = Color3.fromRGB(28, 32, 30),
				Floor = Color3.fromRGB(150, 150, 142),
				Stair = Color3.fromRGB(128, 126, 118),
				Roof = Color3.fromRGB(112, 108, 96),
				Glass = Color3.fromRGB(140, 190, 215),
				Accent = Color3.fromRGB(240, 196, 64),
				Screen = Color3.fromRGB(90, 255, 140),
				Light = Color3.fromRGB(255, 236, 200),
				Locker = Color3.fromRGB(86, 100, 70),
				Rug = Color3.fromRGB(58, 74, 50),
				Sandbag = Color3.fromRGB(186, 164, 118),
				Flag = Color3.fromRGB(70, 110, 60),
			},
		},
	},
}

return StructureVisualConfig
