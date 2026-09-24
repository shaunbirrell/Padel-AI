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
	-- Invisible anti-helicopter barrier height above the plot floor (clears the L5 Command Center flag).
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
			MeshAssetId = 11962508154, -- Missile Battery ≠ Watchtower
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
