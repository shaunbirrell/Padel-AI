--!strict
--[[
	v68: player base layout (plot-local studs). One source of truth for MapSetup (plot build), the
	structure kits / walk-in buildings, consoles and the rear-zone gates.

	Axes (plot-local): +Z = FRONT (main gate, spawn road), -Z = rear. X = across the plot.
	v70: each plot has its own frame (BaseLayout.PlotCFrame). With FaceMapCentre the plot is turned (yaw snapped to 90)
	so its FRONT faces the map centre and the rear zone (runway, helipad, dock + sea gate) faces outward:
	P1/P2 yaw 90 (front +X), P3 yaw 0, P4 yaw 180, P5/P6 yaw -90. Everything below stays plot-local.
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
	FaceMapCentre = true, -- v70 waterways go-live: bases face the map centre so every Dock channel reaches the ring. Rollback = false (MapSetup MAP_GEN 71↔70 forces a map rebuild either way)
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
		-- v72 (read by MapSetup's gate signs once the v72 world lane lands; unused before): sign text inset from the
		-- sign board's edges, so "HELIPAD" / "AIRFIELD" read in full on a phone
		SignInsetStuds = 2.0,
	},

	-- Roads (plot-local rectangles: centre + size) — asphalt with painted edges
	Roads = {
		{ Name = "MainRoad", X = 0, Z = 64, SizeX = 14, SizeZ = 184 }, -- gate → Command Center
		{ Name = "Avenue", X = 0, Z = 80, SizeX = 200, SizeZ = 12 }, -- west row ↔ east row
		{ Name = "Plaza", X = 0, Z = 8, SizeX = 60, SizeZ = 50 }, -- parade ground in front of CC
		{ Name = "Taxiway", X = -100, Z = -66, SizeX = 12, SizeZ = 12 }, -- airfield gate → runway
		{ Name = "Runway", X = -65, Z = -80, SizeX = 170, SizeZ = 24 }, -- under / beside the hangar kit's strip
		{ Name = "HeliApron", X = 40, Z = -86, SizeX = 12, SizeZ = 50 }, -- helipad gate → pad
		{ Name = "HangarApron", X = -100, Z = -98.5, SizeX = 34, SizeZ = 13 }, -- runway → hangar doors
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
		-- Kiosks stand in front of their kits (a kiosk inside the wall sample / tower body could not be reached)
		DefensiveWalls = { Site = { X = -18, Z = 146 }, Yaw = 0, WalkIn = false, Kiosk = { X = -18, Z = 134 } },
		Watchtowers = { Site = { X = 18, Z = 146 }, Yaw = 0, WalkIn = false, Kiosk = { X = 18, Z = 134 } },
		-- Airfield: hangar installation (Installations/Airfield) behind the runway, doors facing it (+Z)
		Airfield = { Site = { X = -100, Z = -122 }, Yaw = 0, WalkIn = false, Kiosk = { X = -86, Z = -52 }, Gate = "Airfield" },
		Helipad = { Site = { X = 40, Z = -125 }, Yaw = 0, WalkIn = false, Kiosk = { X = 54, Z = -52 }, Gate = "Helipad" },
		-- v70: the dock kit stands on the basin's west shore (was centred IN the basin, where its collidable Body was an
		-- island in the boats' spawn water); pier along the kerb, parked boat moored in the basin's west edge
		Dock = { Site = { X = 78, Z = -112 }, Yaw = 90, WalkIn = false, Kiosk = { X = 106, Z = -52 }, Gate = "Dock" },
		-- v72 war businesses (BusinessConfig; built by BusinessService only while BusinessConfig.Enabled, looked up by
		-- id, so these lines are inert until then). 22 x 12 lines facing the plot centre (Yaw 180), kiosk 10 studs
		-- toward the gate. Prototype census: 0 overlaps at L5, kiosks >= 36.6 studs apart, farthest 8.2 s from the ATM.
		AmmoWorks = { Site = { X = -30, Z = 100 }, Yaw = 180, WalkIn = false, Kiosk = { X = -30, Z = 90 } },
		ArmsCrateLine = { Site = { X = -66, Z = 100 }, Yaw = 180, WalkIn = false, Kiosk = { X = -66, Z = 90 } },
		ArmorPlatePress = { Site = { X = 34, Z = 60 }, Yaw = 180, WalkIn = false, Kiosk = { X = 34, Z = 50 } },
		RocketAssembly = { Site = { X = 70, Z = 60 }, Yaw = 180, WalkIn = false, Kiosk = { X = 70, Z = 50 } },
	} :: { [string]: StructureSite },

	-- v72: the 9 static painted floor arrows (MapSetup.paintPlotFloorChevrons, 18 parts per plot) pointed back at the
	-- gate and never moved on after the Command Center; the per-player NEXT pointer replaces them. Read by MapSetup
	-- once the v72 world lane lands (unused before). true = keep the old arrows.
	FloorChevrons = false,
}

return BaseLayoutConfig
