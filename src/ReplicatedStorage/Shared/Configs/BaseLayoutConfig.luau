--!strict
--[[
	v68: player base layout (plot-local studs). One source of truth for MapSetup (plot build), the
	structure kits / walk-in buildings, consoles and the rear-zone gates.

	Axes: +Z = FRONT (main gate, spawn road), -Z = rear. X = across the plot.
	Yaw (degrees) is the direction a building's FRONT faces: 0 = +Z, 90 = +X, -90 = -X, 180 = -Z.

	Zones
	  Main compound  Z -60 .. front wall. Walk-in buildings face a central parade ground and road.
	  Rear zone      behind the inner wall (Z = -60): runway + hangar, helipads, dock basin.
	                 Each rear area sits behind its own inner gate, which opens when that structure is
	                 bought (Airfield / Helipad / Dock) and is guarded.

	Consoles: every structure is bought/upgraded at a console (the WE_UpgradeSlot part). Walk-in buildings
	have theirs inside, near the door (Console = building-local position). Outdoor installations have a
	kiosk (KioskOffset = plot-local position). Consoles are prompt/tap only — no walk-over buying.
]]

export type Vec2 = { X: number, Z: number }

export type StructureSite = {
	Site: Vec2, -- footprint centre (plot-local)
	Yaw: number, -- degrees, direction the front faces
	WalkIn: boolean, -- HollowBuildingBuilder building (Console is building-local) vs outdoor kit (kiosk)
	Console: Vec2?, -- walk-in: building-local position of the console (X across, Z toward the front)
	Kiosk: Vec2?, -- outdoor: plot-local kiosk position
	Gate: string?, -- rear-zone structures: inner gate id opened by buying this structure
}

local BaseLayoutConfig = {
	Enabled = true,
	PlotSize = 320, -- was 200; 6 plots on the 800-stud ring still clear roads/event spawns (see ASSUMPTIONS)
	SpawnOffset = { X = 0, Z = 136 },
	MainGateWidth = 14,

	InnerWall = {
		Z = -60,
		Height = 14,
		Thickness = 2.4,
		GateWidth = 16,
		Gates = {
			Airfield = { X = -100 },
			Helipad = { X = 40 },
			Dock = { X = 92 }, -- west of the basin, so the path runs along the kerb, not into the water
		} :: { [string]: { X: number } },
	},

	-- Roads (plot-local rectangles: centre + size) — asphalt with painted edges
	Roads = {
		{ Name = "MainRoad", X = 0, Z = 64, SizeX = 14, SizeZ = 184 }, -- gate → Command Center
		{ Name = "Avenue", X = 0, Z = 80, SizeX = 200, SizeZ = 12 }, -- west row ↔ east row
		{ Name = "Plaza", X = 0, Z = 8, SizeX = 60, SizeZ = 50 }, -- parade ground in front of CC
		{ Name = "Taxiway", X = -100, Z = -66, SizeX = 12, SizeZ = 12 }, -- airfield gate → runway
		{ Name = "Runway", X = -65, Z = -80, SizeX = 170, SizeZ = 24 }, -- under / beside the hangar kit's strip
		{ Name = "HeliApron", X = 40, Z = -86, SizeX = 12, SizeZ = 50 }, -- helipad gate → pad
	},

	Courtyard = {
		Collector = { X = -42, Z = 118 }, -- ATM / money collector (premium pads arranged around it)
		TrainingYard = { X = 46, Z = 30 },
		Flagpole = { X = 0, Z = 8 },
		DockBasin = { X = 128, Z = -112, SizeX = 50, SizeZ = 70 },
	},

	-- Sandbag berms / crates / barriers dressing the base edges (MapSetup PlotWarzone)
	WarzoneSpots = {
		{ X = -146, Z = 146 }, { X = 146, Z = 146 }, { X = -146, Z = 80 }, { X = 146, Z = 80 },
		{ X = -146, Z = 28 }, { X = 146, Z = 28 }, { X = -30, Z = -52 }, { X = 25, Z = -8 },
		{ X = -20, Z = -100 }, { X = 10, Z = -150 }, { X = -150, Z = -150 }, { X = 80, Z = -150 },
	} :: { Vec2 },

	Structures = {
		CommandCenter = { Site = { X = 0, Z = -38 }, Yaw = 0, WalkIn = true, Console = { X = 10.5, Z = 6 } },
		Barracks = { Site = { X = -110, Z = 110 }, Yaw = 90, WalkIn = true, Console = { X = 13.5, Z = 8 } },
		WeaponsFacility = { Site = { X = -110, Z = 55 }, Yaw = 90, WalkIn = true, Console = { X = 12.5, Z = 7 } },
		SpecialForcesFacility = { Site = { X = -110, Z = 0 }, Yaw = 90, WalkIn = true, Console = { X = 12.5, Z = 7 } },
		VehicleDepot = { Site = { X = 110, Z = 110 }, Yaw = -90, WalkIn = true, Console = { X = 15.5, Z = 10 } },
		Warehouse = { Site = { X = 110, Z = 55 }, Yaw = -90, WalkIn = true, Console = { X = 14.5, Z = 9 } },
		ResearchLab = { Site = { X = 110, Z = 0 }, Yaw = -90, WalkIn = true, Console = { X = 12.5, Z = 7 } },
		PowerStation = { Site = { X = -60, Z = -40 }, Yaw = 0, WalkIn = false, Kiosk = { X = -60, Z = -24 } },
		Radar = { Site = { X = 70, Z = -40 }, Yaw = 0, WalkIn = false, Kiosk = { X = 70, Z = -24 } },
		MissileDefense = { Site = { X = 132, Z = -40 }, Yaw = 0, WalkIn = false, Kiosk = { X = 132, Z = -24 } },
		DefensiveWalls = { Site = { X = -18, Z = 146 }, Yaw = 0, WalkIn = false, Kiosk = { X = -18, Z = 146 } },
		Watchtowers = { Site = { X = 18, Z = 146 }, Yaw = 0, WalkIn = false, Kiosk = { X = 18, Z = 146 } },
		-- Airfield kit: hangar at local -Z (south), its strip at local +Z → faces the gate / runway
		Airfield = { Site = { X = -100, Z = -100 }, Yaw = 0, WalkIn = false, Kiosk = { X = -86, Z = -52 }, Gate = "Airfield" },
		Helipad = { Site = { X = 40, Z = -125 }, Yaw = 0, WalkIn = false, Kiosk = { X = 54, Z = -52 }, Gate = "Helipad" },
		Dock = { Site = { X = 128, Z = -112 }, Yaw = 0, WalkIn = false, Kiosk = { X = 106, Z = -52 }, Gate = "Dock" },
	} :: { [string]: StructureSite },
}

return BaseLayoutConfig
