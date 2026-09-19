--!strict
--[[
	Part-kit silhouettes + palettes for base structures (placeholders, no MeshIds).
	StudioSetup mirrors these colors; BaseService.UpdateVisuals scales detail by level.
]]

export type StructurePalette = {
	Plinth: Color3,
	Body: Color3,
	Accent: Color3,
	Roof: Color3,
	Kit: "hq" | "barracks" | "depot" | "lab" | "tower" | "pad" | "dock" | "wall" | "power" | "warehouse" | "special",
	-- Future Creator Store MeshPart (0 / nil = Part kit)
	MeshAssetId: number?,
}

local StructureVisualConfig = {
	-- Level 0 = ghost/placeholder; ≥1 solid + taller body
	GhostTransparency = 0.45,
	SolidTransparency = 0,
	-- When true and palette.MeshAssetId ~= 0, BaseService may swap kit for MeshPart (art pass).
	PreferMeshWhenAssetIdSet = true,

	Palettes = {
		CommandCenter = {
			Plinth = Color3.fromRGB(36, 48, 40),
			Body = Color3.fromRGB(55, 78, 58),
			Accent = Color3.fromRGB(230, 190, 60),
			Roof = Color3.fromRGB(40, 55, 45),
			Kit = "hq",
		},
		Barracks = {
			Plinth = Color3.fromRGB(42, 46, 38),
			Body = Color3.fromRGB(70, 78, 55),
			Accent = Color3.fromRGB(90, 160, 80),
			Roof = Color3.fromRGB(50, 55, 42),
			Kit = "barracks",
		},
		VehicleDepot = {
			Plinth = Color3.fromRGB(40, 48, 55),
			Body = Color3.fromRGB(58, 72, 88),
			Accent = Color3.fromRGB(90, 160, 220),
			Roof = Color3.fromRGB(45, 55, 65),
			Kit = "depot",
		},
		WeaponsFacility = {
			Plinth = Color3.fromRGB(48, 40, 38),
			Body = Color3.fromRGB(88, 58, 50),
			Accent = Color3.fromRGB(200, 90, 70),
			Roof = Color3.fromRGB(55, 42, 40),
			Kit = "lab",
		},
		Helipad = {
			Plinth = Color3.fromRGB(45, 50, 48),
			Body = Color3.fromRGB(60, 70, 65),
			Accent = Color3.fromRGB(220, 200, 80),
			Roof = Color3.fromRGB(50, 55, 52),
			Kit = "pad",
		},
		Dock = {
			Plinth = Color3.fromRGB(35, 48, 58),
			Body = Color3.fromRGB(50, 75, 95),
			Accent = Color3.fromRGB(70, 180, 220),
			Roof = Color3.fromRGB(40, 58, 70),
			Kit = "dock",
		},
		Airfield = {
			Plinth = Color3.fromRGB(50, 52, 48),
			Body = Color3.fromRGB(70, 72, 68),
			Accent = Color3.fromRGB(180, 190, 100),
			Roof = Color3.fromRGB(55, 58, 52),
			Kit = "pad",
		},
		DefensiveWalls = {
			Plinth = Color3.fromRGB(48, 48, 45),
			Body = Color3.fromRGB(85, 85, 78),
			Accent = Color3.fromRGB(120, 130, 110),
			Roof = Color3.fromRGB(60, 60, 55),
			Kit = "wall",
		},
		Watchtowers = {
			Plinth = Color3.fromRGB(44, 46, 40),
			Body = Color3.fromRGB(72, 78, 60),
			Accent = Color3.fromRGB(200, 160, 70),
			Roof = Color3.fromRGB(50, 52, 44),
			Kit = "tower",
		},
		Radar = {
			Plinth = Color3.fromRGB(40, 42, 55),
			Body = Color3.fromRGB(55, 60, 90),
			Accent = Color3.fromRGB(100, 200, 255),
			Roof = Color3.fromRGB(45, 48, 70),
			Kit = "tower",
		},
		ResearchLab = {
			Plinth = Color3.fromRGB(38, 45, 55),
			Body = Color3.fromRGB(50, 70, 95),
			Accent = Color3.fromRGB(80, 180, 220),
			Roof = Color3.fromRGB(42, 55, 72),
			Kit = "lab",
		},
		MissileDefense = {
			Plinth = Color3.fromRGB(48, 42, 40),
			Body = Color3.fromRGB(75, 55, 50),
			Accent = Color3.fromRGB(220, 100, 60),
			Roof = Color3.fromRGB(55, 45, 42),
			Kit = "tower",
		},
		PowerStation = {
			Plinth = Color3.fromRGB(50, 48, 35),
			Body = Color3.fromRGB(90, 85, 50),
			Accent = Color3.fromRGB(255, 210, 70),
			Roof = Color3.fromRGB(60, 55, 40),
			Kit = "power",
		},
		Warehouse = {
			Plinth = Color3.fromRGB(45, 42, 38),
			Body = Color3.fromRGB(95, 80, 60),
			Accent = Color3.fromRGB(180, 140, 80),
			Roof = Color3.fromRGB(55, 50, 42),
			Kit = "warehouse",
		},
		SpecialForcesFacility = {
			Plinth = Color3.fromRGB(35, 38, 42),
			Body = Color3.fromRGB(45, 55, 65),
			Accent = Color3.fromRGB(160, 80, 200),
			Roof = Color3.fromRGB(30, 35, 40),
			Kit = "special",
		},
	} :: { [string]: StructurePalette },
}

return StructureVisualConfig
