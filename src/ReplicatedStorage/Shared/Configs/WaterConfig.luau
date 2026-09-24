--!strict
--[[
	v70 waterways: every WE_Water surface on the map. One source of truth for MapSetup (plot water, sea gates, naval
	pads, road ends, rig piers), Modules/Waterways (public water + banks, sea-gate proximity loop, dressing cull),
	MapDressing / DesertFlora (keep props out of the water), TerritoryCapture (naval outposts) and the vehicles drive
	(reads the tagged parts, not this file).

	Units: world studs. +Y up. Ground top 0.5, plot pad top 1.0.
	Public rects are axis-aligned XZ boxes { X0 < X1, Z0 < Z1 }. The water parts TILE the network: neighbours share an
	edge and never overlap (coplanar transparent top faces z-fight). Every water part's TOP face is at SurfaceY; boats read
	the top face as the water level (Constants.Tags.Water contract).

	Plot water (DockWater, SeaGateWater) is plot-local (BaseLayoutConfig frame: +Z = plot front / main gate, -Z = rear)
	and is built TURNED WITH THE PLOT: CFrame = BaseLayout.PlotLocalCFrame(pos, x, y, z) (exact quarter turn), size in
	plot-local terms. Its world AABB is still axis-aligned and tiles with the channel. Turning it gives the vehicles'
	basin spawn (yawOf(DockWater.CFrame)) a bow that points at the sea gate on every plot.
	Only DockWater carries WE_PlotId (the vehicles' plotBasin picks the first WE_Water with WE_PlotId == plotId);
	SeaGateWater carries WE_GatePlotId instead.
]]

export type Rect = { Name: string, X0: number, X1: number, Z0: number, Z1: number, Bank: number? }
export type Channel = { PlotId: number, Until: number } -- from the plot's sea gate straight out (plot rear) to world coord Until
export type NavalOutpost = { Presence: string, DeckMinY: number?, Water: { string } }
export type NavalPad = { Name: string, X: number, Z: number }
export type RoadEnd = { Min: number, Max: number }
export type GateLeaf = { Name: string, Bottom: number, Height: number, Thickness: number, Transparency: number? }

local WaterConfig = {
	Enabled = true,

	-- Water level. Every WE_Water part spans BottomY..SurfaceY (the bottom face is hidden in the ground / plot pad).
	-- 1.5 = 1.0 above the desert floor and 0.5 above plot pads, so a boat hull (draft 0.15) clears the submerged pad
	-- edge where a channel meets a dock.
	SurfaceY = 1.5,
	BottomY = 0.3,

	Look = {
		Color = Color3.fromRGB(46, 112, 140),
		Material = Enum.Material.Glass,
		Transparency = 0.2,
		Reflectance = 0.1,
	},
	-- Sand bank: one slab per public water rect, the rect grown by Bank (default BankWidth) on every side, top at
	-- BankTop + i * 0.004 (i = rect index, so overlapping banks never z-fight). Non-collide, CanQuery off.
	BankWidth = 6,
	SeaBankWidth = 24,
	BankTop = 0.58,
	BankColor = Color3.fromRGB(226, 205, 160),
	BankMaterial = Enum.Material.Sand,

	-- Public water (no plot attribute). Order matters only for the bank height offset.
	Public = {
		-- Sea band (south). Was one WaterPlane x +-3240 z 1490..2210 at top 0.7; notched around Fort Sandhold's south
		-- wall (z 1521..1527), which used to stand in the sea. Every piece <= 2000 studs per axis (BasePart size cap
		-- 2048 incl. the bank). Sea_E1 is the largest part = "the sea" for the vehicles' _IsConnectedToSea.
		{ Name = "Sea_W", X0 = -3240, X1 = -1530, Z0 = 1490, Z1 = 2210, Bank = 24 },
		{ Name = "Sea_FortNotch", X0 = -1530, X1 = -1370, Z0 = 1530, Z1 = 2210, Bank = 24 },
		{ Name = "Sea_E1", X0 = -1370, X1 = 600, Z0 = 1490, Z1 = 2210, Bank = 24 },
		{ Name = "Sea_E2", X0 = 600, X1 = 2400, Z0 = 1490, Z1 = 2210, Bank = 24 },
		{ Name = "Sea_E3", X0 = 2400, X1 = 3240, Z0 = 1490, Z1 = 2210, Bank = 24 },
		-- Ring canal: 80 wide, centre lines x = +-1800 and z = -1800, joined to the sea. Oil-rig lagoons 180 x 180
		-- (half 90 > the 67.9 effective capture radius, so everything in range of a rig is water, deck or pier).
		{ Name = "Ring_NW", X0 = -1840, X1 = 0, Z0 = -1840, Z1 = -1760 },
		{ Name = "Ring_NE", X0 = 0, X1 = 1840, Z0 = -1840, Z1 = -1760 },
		{ Name = "Ring_E1", X0 = 1760, X1 = 1840, Z0 = -1760, Z1 = -840 },
		{ Name = "Lagoon_Alpha", X0 = 1710, X1 = 1890, Z0 = -840, Z1 = -660 },
		{ Name = "Ring_E2", X0 = 1760, X1 = 1840, Z0 = -660, Z1 = 400 },
		{ Name = "Ring_E3", X0 = 1760, X1 = 1840, Z0 = 400, Z1 = 1490 },
		{ Name = "Ring_W1", X0 = -1840, X1 = -1760, Z0 = -1760, Z1 = -400 },
		{ Name = "Ring_W2", X0 = -1840, X1 = -1760, Z0 = -400, Z1 = 660 },
		{ Name = "Lagoon_Bravo", X0 = -1890, X1 = -1710, Z0 = 660, Z1 = 840 },
		{ Name = "Ring_W3", X0 = -1840, X1 = -1760, Z0 = 840, Z1 = 1490 },
		-- South Docks: harbour on the sea + two slips either side of the marker (the marker stands on the mole).
		{ Name = "Harbour_SouthDocks", X0 = -240, X1 = 240, Z0 = 1364, Z1 = 1490 },
		{ Name = "Slip_SouthDocks_W", X0 = -108, X1 = -64, Z0 = 1240, Z1 = 1364 },
		{ Name = "Slip_SouthDocks_E", X0 = 64, X1 = 108, Z0 = 1240, Z1 = 1364 },
	} :: { Rect },

	-- Dock channels: public water from each plot's sea gate (pad edge) straight out of the plot's rear to world
	-- coordinate Until (x for plots facing +-X, z for plots facing +-Z). Only built when BaseLayout.FacesMapCentre().
	-- At PlotSize 320 they resolve to (x0, x1, z0, z1):
	--   P1 (-1760, -960, -548, -508)  P2 (-1760, -960, 252, 292)   P3 (108, 148, -1760, -960)
	--   P4 (-148, -108, 960, 1364)    P5 (960, 1760, -292, -252)   P6 (960, 1760, 508, 548)
	ChannelWidth = 40, -- = SeaGate.X1 - SeaGate.X0
	Channels = {
		{ PlotId = 1, Until = -1760 }, -- west into Ring_W1
		{ PlotId = 2, Until = -1760 }, -- west into Ring_W2
		{ PlotId = 3, Until = -1760 }, -- north into Ring_NE
		{ PlotId = 4, Until = 1364 }, -- south into Harbour_SouthDocks
		{ PlotId = 5, Until = 1760 }, -- east into Ring_E2
		{ PlotId = 6, Until = 1760 }, -- east into Ring_E3
	} :: { Channel },

	-- Sea gate (plot-local, BaseLayoutConfig frame). Built by MapSetup in LayoutGround as folder "SeaGate_Dock" with
	-- GateId = "Dock" and WE_GateMode = "Proximity": StructureKitBuilder.SyncRearGates only ARMS it (Dock L1+) or
	-- closes it; Waterways' sea-gate loop opens an armed gate while a boat driven by the plot owner or an ally is near,
	-- and closes it CloseDelay s after the last one leaves. So the Dock never leaves a walk-in back door in the walls.
	SeaGate = {
		X0 = 108, -- opening = gate water = channel width (inside the corner tower at x 151.5..162.5)
		X1 = 148,
		WallZ = -158.5, -- perimeter wall centre line (StructureKitBuilder halfZ = 160 - 1.5)
		PadEdgeZ = -160,
		BasinRearZ = -147, -- DockBasin rear edge (128, -112, 50 x 70)
		PostWidth = 1.6,
		PostDepth = 3.4,
		PostHeight = 30, -- above pad top
		LintelBottom = 28.9, -- above pad top; lintel is CanCollide = false (a land probe must never see it)
		-- Closed: two collidable leaves across the opening, 12 tall in total (not jumpable from the ground, a kerb or a
		-- pontoon). The low boom's top (y 6.0 = 4.5 above the water) is what a boat land probe starting at SurfaceY + 6
		-- sees (that origin is inside GateLeaf2). Open: both slide WEST (plot-local -X) by their width + 0.3 into the
		-- rear wall line (WE_GateLeaf = -1, the rear-gate slide) and stop colliding. A slide east would hit the corner tower.
		Leaves = {
			{ Name = "GateLeaf1", Bottom = 0, Height = 5, Thickness = 1.2 }, -- yellow/black DiamondPlate boom
			{ Name = "GateLeaf2", Bottom = 5, Height = 7, Thickness = 0.6, Transparency = 0.35 }, -- chain-link screen
		} :: { GateLeaf },
		LeafSlide = -1,
		OpenRadius = 40, -- horizontal studs from the gate centre to an allied boat's chassis (v70: 60 → 40: a boat idling at the basin spawn (46.5 away) no longer holds the gate open for enemies on foot; a returning boat still gets ~40 studs of warning)
		OpenHeight = 20,
		CloseDelay = 2,
		LoopSeconds = 0.25,
		GapWidth = 43.2, -- WE_WallGap marker: opening + both posts; SyncPerimeterWalls leaves this span open
		GapDepth = 8,
		Label = "SEA GATE",
		Guards = { { X = 98, Z = -150 } }, -- one guard prop on the west quay, facing the gate water (+X)
	},

	-- Territories that boats can take. Presence rules (TerritoryCapture):
	--   "BoatOrDeck": only the DRIVER of a Naval vehicle, or a player on foot with HumanoidRootPart.Y >= DeckMinY, counts.
	--   "Any": the normal rule (anyone alive in range), boats included.
	NavalOutposts = {
		CoastalOilAlpha = { Presence = "BoatOrDeck", DeckMinY = 24, Water = { "Lagoon_Alpha" } },
		CoastalOilBravo = { Presence = "BoatOrDeck", DeckMinY = 24, Water = { "Lagoon_Bravo" } },
		SouthDocks = { Presence = "Any", Water = { "Harbour_SouthDocks", "Slip_SouthDocks_W", "Slip_SouthDocks_E" } },
	} :: { [string]: NavalOutpost },

	-- Oil-rig ramp = pier to the inner bank: MapSetup buildOilDeckRamp with the sign fixed and the direction snapped
	-- to the X axis toward the map centre (Alpha steps x 1765 -> 1684, Bravo mirrored; approach pad on land).
	RigPierAxisAligned = true,
	-- Concrete footing round each rig leg at the waterline (6 x 2 x 6, y 0.5..2.5): a boat land probe that starts inside
	-- the 28-tall leg would miss the leg; the footing's top (2.5) is seen as land by any probe origin above 2.5.
	RigLegFooting = Vector3.new(6, 2, 6),
	-- Submerged rubble footing under the pier's low end (steps 5-10 and the shelf have bottoms 8.7..14.2, lower than a
	-- capital ship's collidable bridge, up to 13.1 above the water): rig-local Near..Far studs along the pier axis,
	-- +-HalfWidth across, y 0.5..2.5, collidable Concrete. Boats brake before it instead of ramming the steps.
	RigPierFooting = { Near = 57, Far = 90, HalfWidth = 11, Height = 2 },

	-- WE_NavalSpawn pontoons (collidable 18 x 1.2 x 18, top 2.1 = 0.6 above the water; also WE_VehicleSpawn so the
	-- garage prompt shows). Built by MapSetup (today's pad code, reading this list). Boats spawn BESIDE them (vehicles
	-- spec). The last three are new ring landings at road ends.
	NavalPadSize = 18,
	NavalPads = {
		{ Name = "NavalPad_1", X = -420, Z = 1580 },
		{ Name = "NavalPad_2", X = -240, Z = 1620 },
		{ Name = "NavalPad_3", X = -80, Z = 1640 },
		{ Name = "NavalPad_4", X = 80, Z = 1640 },
		{ Name = "NavalPad_5", X = 240, Z = 1620 },
		{ Name = "NavalPad_6", X = 420, Z = 1580 },
		{ Name = "NavalPad_7", X = 0, Z = 1720 },
		{ Name = "NavalPad_8", X = -560, Z = 1680 },
		{ Name = "NavalPad_9", X = 560, Z = 1680 },
		{ Name = "NavalPad_RingN", X = 0, Z = -1769 },
		{ Name = "NavalPad_RingE", X = 1769, Z = 0 },
		{ Name = "NavalPad_RingW", X = -1769, Z = 0 },
	} :: { NavalPad },

	-- World roads stop RoadEndSetback studs before the first water (no bridges; every land outpost is inside the ring).
	-- Key = MapSetup road part name; Min/Max = extent along the road (z for RoadX<x>, x for RoadZ<z>). Each road is
	-- built as two parts split at 0 (<name>_A: Min..0, <name>_B: 0..Max) so no part exceeds 2000 studs.
	RoadEndSetback = 8,
	RoadEnds = {
		["RoadX-800"] = { Min = -1752, Max = 1482 },
		["RoadX0"] = { Min = -1752, Max = 1356 }, -- south end at the South Docks harbour
		["RoadX800"] = { Min = -1752, Max = 1482 },
		["RoadZ-800"] = { Min = -1752, Max = 1702 }, -- east end at Lagoon_Alpha
		["RoadZ0"] = { Min = -1752, Max = 1752 },
		["RoadZ800"] = { Min = -1702, Max = 1752 }, -- west end at Lagoon_Bravo
	} :: { [string]: RoadEnd },
	-- Jersey barrier across each road end (collidable, yellow/black stripe)
	RoadEndBarrier = { Width = 18, Height = 2.4, Depth = 1.6 },
}

return WaterConfig
