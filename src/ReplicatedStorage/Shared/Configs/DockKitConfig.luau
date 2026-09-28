--!strict
--[[
	fb4 harbour (owner 2026-09-28, phone screenshots of his base dock: "The default boat in the dock looks terrible, make
	it look like a real boat" and "The building beside the dock same thing should look like a legit dock building").

	The Naval Dock's Part kit (StructureKitBuilder kit "dock"): a paved quay along the basin with bollards and tyre
	fenders, a red-brick harbour warehouse (pitched roof with gables, roller doors), a grey patrol boat moored alongside
	(flared pointed bow, black boot-top, wheelhouse with a glass band, mast, bow gun, mooring lines), then a quay crane,
	lamp posts, cargo, a harbour control tower, stacked containers and a harbour launch as the Dock levels up.
	Enabled = false builds the old v35 / v37 kit (pier slab, grey shed, 5-block parked boat) exactly as before.

	Rules this kit keeps (CLAUDE.md):
	  - Own Part kit only: no catalog model, no mesh, 0 new load attempts (PreferMesh stays OFF for structure kits).
	  - No text, no SurfaceGui, no light, no Neon, no Humanoid, no markings on the boat (no numbers, flags or insignia).
	  - Parts: 86 pieces + the hidden Body and boat host = 88 per base (the old kit had 24: +64 per base at L5). The
	    biggest level-up (L1) shows 47 of them (57 instance changes with the Dock's gates and signs; target 60).
	    Nothing is created or destroyed on a purchase: every piece is built once with the kit and BaseService only
	    shows it (Transparency) and gives it its collision at its MinLevel (L5 also adds the usual WE_MaxSmoke).

	Kit frame (the Dock's site frame, BaseLayoutConfig.Structures.Dock: site (78, -112), Yaw 90), in studs:
	  X along the quay, + toward the sea gate (plot -Z);   Z across the quay, + toward the water (plot +X);
	  Y = the piece's CENTRE height above the plot pad top (the water surface is at +0.5, the basin kerb top at +1.0).
  What a piece stands on sets its bottom: on the quay (kit z 4 .. 23.8) the QuayDeck top at +0.4; landward of the
  quay (kit z < 4: the warehouse yard, the gable-end cargo, the containers) the bare pad top at 0. So a crate of
  height h on the pad has Y = h / 2 (a BuyPathStatic rule checks every low piece rests on one or the other).
	  Pos is the piece's centre; Rot = CFrame.Angles(X, Y, Z) in degrees; a piece with From / To is a beam (rope, jib):
	  a Size.X x Size.Y section stretched from From to To.
	  Shape: "Block" | "Wedge" (Roblox WedgePart: tall face at local +Z, slope down toward -Z) | "Cylinder" (axis along
	  local X) | "Ball".
	  Landmarks in this frame: basin water z >= 25 (kerb z 23.8 .. 25, x -35.6 .. 35.6); inner Dock gate x -52,
	  z 6 .. 22; helipad z <= -24; sea-gate guard (38, 20); sandbag berm (38, 2); sea gate lane x >= 35, z 30 .. 70.
	  Nothing in the kit reaches past kit z 33.5 (the moored strip): the open basin, where driven boats spawn (z >= 34)
	  and sail, has no kit part in it at any height. Every solid (Collide) piece stays inside kit x -48 .. 34 (the
	  QuayDeck's span: off the Dock gate lane, the sea-gate guard, the berm and the sea-gate lane land) and at kit
	  z >= -20 (off the helipad).

	MinLevel: the Dock level that shows the piece (0 = from the kit build: the quay is base infrastructure like the
	basin and its kerb). Collide = CanCollide + CanQuery (walkable quay, solid warehouse / hull / tower / containers;
	a solid hull is "land" to a driven boat's probe, like the kerb, and a spawn never overlaps it). Everything else is
	decor: CanCollide, CanQuery and CanTouch off. Shadow = CastShadow (the big volumes only).
]]

export type DockPiece = {
	Name: string,
	Shape: string?, -- default "Block"
	Size: Vector3,
	Pos: Vector3?, -- centre (Y above the pad top); nil for a From / To beam
	Rot: Vector3?, -- degrees, CFrame.Angles(X, Y, Z)
	From: Vector3?,
	To: Vector3?,
	Color: Color3,
	Material: Enum.Material,
	MinLevel: number,
	Collide: boolean?,
	Shadow: boolean?,
	Transparency: number?, -- when shown (default 0; 1 = always hidden)
}

local C = Color3.fromRGB
local M = Enum.Material
local V = Vector3.new

-- palette
local BRICK = C(150, 86, 66)
local ROOF = C(80, 96, 110)
local CONCRETE = C(156, 152, 142)
local TRIM = C(212, 204, 186)
local GLASS = C(58, 88, 112)
local DOOR = C(58, 78, 96)
local HULL = C(92, 102, 112) -- dark naval grey
local BOOT = C(34, 36, 38)
local CRANE = C(226, 176, 44)
local ROPE = C(196, 176, 130)
local DARK = C(40, 42, 44)

-- roof pitch: walls 10 high, ridge +4 at z = -5, eaves 0.8 past the walls (z 4.8 / -14.8)
local PITCH = math.deg(math.atan(4 / 9.8))
local ROOF_LEN = math.sqrt(9.8 * 9.8 + 4 * 4) + 0.3
local ROOF_DY = 0.225 * math.cos(math.rad(PITCH))
local ROOF_DZ = 0.225 * math.sin(math.rad(PITCH))

-- crane jib: from the cab, luffed up over the harbour launch's berth (L4). The tip stays over the moored strip
-- (kit z <= 33) and the hook hangs 15+ studs up, so nothing hangs in the open basin where driven boats sail. The crane
-- stands at the sea-gate end of the quay (x 22), clear of the car-sized lane along the quay in front of the warehouse.
local JIB_FROM = V(22, 11.8, 22.8)
local JIB_TIP = V(21, 20.6, 29.4)

local pieces: { DockPiece } = {
	-- ── L0 quay (base infrastructure, with the basin): paved apron from the Dock gate lane to the kerb ───────────
	{ Name = "QuayDeck", Size = V(82, 0.8, 19.8), Pos = V(-7, 0, 13.9), Color = CONCRETE, Material = M.Concrete, MinLevel = 0, Collide = true },
	{ Name = "QuayEdgeLine", Size = V(70.4, 0.06, 0.45), Pos = V(0, 0.43, 22.9), Color = C(226, 184, 52), Material = M.SmoothPlastic, MinLevel = 0 },
	{ Name = "Bollard", Shape = "Cylinder", Size = V(1.3, 1.1, 1.1), Pos = V(-26, 1.05, 22.6), Rot = V(0, 0, 90), Color = DARK, Material = M.Metal, MinLevel = 0 },
	{ Name = "Bollard", Shape = "Cylinder", Size = V(1.3, 1.1, 1.1), Pos = V(-12, 1.05, 22.6), Rot = V(0, 0, 90), Color = DARK, Material = M.Metal, MinLevel = 0 },
	{ Name = "Bollard", Shape = "Cylinder", Size = V(1.3, 1.1, 1.1), Pos = V(14, 1.05, 22.6), Rot = V(0, 0, 90), Color = DARK, Material = M.Metal, MinLevel = 0 },
	{ Name = "Bollard", Shape = "Cylinder", Size = V(1.3, 1.1, 1.1), Pos = V(28, 1.05, 22.6), Rot = V(0, 0, 90), Color = DARK, Material = M.Metal, MinLevel = 0 },

	-- ── L1 harbour warehouse: x -15 .. 13, z -14 .. 4 (front on the quay), walls 10, ridge 14 along X ──────────────
	{ Name = "WarehouseBlock", Size = V(28, 10, 18), Pos = V(-1, 5, -5), Color = BRICK, Material = M.Brick, MinLevel = 1, Collide = true, Shadow = true },
	{ Name = "WarehousePlinth", Size = V(28.3, 1.2, 18.3), Pos = V(-1, 0.6, -5), Color = C(118, 114, 106), Material = M.Concrete, MinLevel = 1 },
	{ Name = "WarehouseRoof", Size = V(29.6, 0.45, ROOF_LEN), Pos = V(-1, 12 + ROOF_DY, -0.1 + ROOF_DZ), Rot = V(PITCH, 0, 0), Color = ROOF, Material = M.Metal, MinLevel = 1, Collide = true, Shadow = true },
	{ Name = "WarehouseRoof", Size = V(29.6, 0.45, ROOF_LEN), Pos = V(-1, 12 + ROOF_DY, -9.9 - ROOF_DZ), Rot = V(-PITCH, 0, 0), Color = ROOF, Material = M.Metal, MinLevel = 1, Collide = true, Shadow = true },
	{ Name = "WarehouseRidge", Size = V(29.8, 0.5, 0.9), Pos = V(-1, 14.25, -5), Color = C(62, 70, 78), Material = M.Metal, MinLevel = 1 },
	{ Name = "WarehouseGable", Shape = "Wedge", Size = V(0.5, 4, 9), Pos = V(-14.75, 12, -0.5), Rot = V(0, 180, 0), Color = BRICK, Material = M.Brick, MinLevel = 1, Collide = true },
	{ Name = "WarehouseGable", Shape = "Wedge", Size = V(0.5, 4, 9), Pos = V(-14.75, 12, -9.5), Color = BRICK, Material = M.Brick, MinLevel = 1, Collide = true },
	{ Name = "WarehouseGable", Shape = "Wedge", Size = V(0.5, 4, 9), Pos = V(12.75, 12, -0.5), Rot = V(0, 180, 0), Color = BRICK, Material = M.Brick, MinLevel = 1, Collide = true },
	{ Name = "WarehouseGable", Shape = "Wedge", Size = V(0.5, 4, 9), Pos = V(12.75, 12, -9.5), Color = BRICK, Material = M.Brick, MinLevel = 1, Collide = true },
	-- quay front: two roller doors, a side door, a cream lintel band
	{ Name = "RollerDoor", Size = V(7, 7.6, 0.25), Pos = V(-8.5, 4.2, 4.12), Color = C(182, 186, 188), Material = M.Metal, MinLevel = 1 },
	{ Name = "RollerDoor", Size = V(7, 7.6, 0.25), Pos = V(2.5, 4.2, 4.12), Color = C(182, 186, 188), Material = M.Metal, MinLevel = 1 },
	{ Name = "WarehouseDoor", Size = V(2.4, 5.2, 0.2), Pos = V(9.5, 3, 4.1), Color = DOOR, Material = M.Metal, MinLevel = 1 },
	{ Name = "LintelBand", Size = V(28.1, 0.7, 0.3), Pos = V(-1, 8.6, 4.1), Color = TRIM, Material = M.Concrete, MinLevel = 1 },
	-- gable end toward the Dock gate (the first thing a player sees walking in): door, window, round vent
	{ Name = "WarehouseDoor", Size = V(0.2, 5.2, 2.4), Pos = V(-15.1, 2.6, -2), Color = DOOR, Material = M.Metal, MinLevel = 1 },
	{ Name = "WarehouseWindow", Size = V(0.2, 2.2, 5), Pos = V(-15.1, 6.2, -9), Color = GLASS, Material = M.Glass, MinLevel = 1 },
	{ Name = "GableVent", Shape = "Cylinder", Size = V(0.3, 2.2, 2.2), Pos = V(-15.05, 11.6, -5), Color = C(52, 58, 62), Material = M.Metal, MinLevel = 1 },
	{ Name = "WarehouseWindow", Size = V(22, 1.6, 0.2), Pos = V(-1, 7.4, -14.1), Color = GLASS, Material = M.Glass, MinLevel = 1 },
	{ Name = "WarehouseWindow", Size = V(0.2, 2.2, 5), Pos = V(13.1, 6.2, -5), Color = GLASS, Material = M.Glass, MinLevel = 1 },

	-- ── L1 moored patrol boat: bow toward the sea gate (+X), centreline z 29, beam 6, stern x -10, bow tip x 13 ─────
	-- black boot-top at the waterline, dark grey topsides, a raised forecastle with the bow gun, a flared pointed bow
	-- (two wedges lying flat, overhanging the waterline like a raked stem), a pale wheelhouse with a glass band. The
	-- wheelhouse is at player scale: 6 high over the deck (+2.4 .. +8.4), so a 5-stud avatar on deck stands below its
	-- roof, the window band (+6.3 .. +7.8) is at his eye line, and the mast rises from the roof.
	{ Name = "BoatBoot", Size = V(18.04, 0.9, 6.04), Pos = V(-1, 0.45, 29), Color = BOOT, Material = M.SmoothPlastic, MinLevel = 1, Collide = true },
	{ Name = "BoatHull", Size = V(13, 1.5, 6), Pos = V(-3.5, 1.65, 29), Color = HULL, Material = M.Metal, MinLevel = 1, Collide = true, Shadow = true },
	{ Name = "BoatForecastle", Size = V(5, 2.3, 6), Pos = V(5.5, 2.05, 29), Color = HULL, Material = M.Metal, MinLevel = 1, Collide = true, Shadow = true },
	{ Name = "BoatBow", Shape = "Wedge", Size = V(2.3, 5, 3), Pos = V(10.5, 2.05, 27.5), Rot = V(0, 0, -90), Color = HULL, Material = M.Metal, MinLevel = 1, Collide = true },
	{ Name = "BoatBow", Shape = "Wedge", Size = V(2.3, 5, 3), Pos = V(10.5, 2.05, 30.5), Rot = V(180, 0, -90), Color = HULL, Material = M.Metal, MinLevel = 1, Collide = true },
	-- raked forefoot: the black boot-top sweeps up under the bow overhang (flat top at the bow's underside, slope from
	-- the waterline at x 8 up to x 11.6), so from the side the bow rises out of the water instead of ending square
	{ Name = "BoatStem", Shape = "Wedge", Size = V(1.8, 0.9, 3.6), Pos = V(9.8, 0.45, 29), Rot = V(180, -90, 0), Color = BOOT, Material = M.SmoothPlastic, MinLevel = 1 },
	-- black rubbing strake round the hull just under the deck edge: a sheer line along the flat grey side and stern
	{ Name = "BoatStrake", Size = V(18.1, 0.2, 6.12), Pos = V(-1.03, 2.2, 29), Color = DARK, Material = M.Rubber, MinLevel = 1 },
	{ Name = "BoatDeck", Size = V(12.6, 0.12, 5.6), Pos = V(-3.7, 2.46, 29), Color = C(78, 84, 88), Material = M.DiamondPlate, MinLevel = 1 },
	-- the quay-side bulwark has a boarding gap (x -8.6 .. -6.4) where the gangway comes aboard
	{ Name = "BoatBulwark", Size = V(1.4, 0.7, 0.18), Pos = V(-9.3, 2.75, 26.09), Color = HULL, Material = M.Metal, MinLevel = 1 },
	{ Name = "BoatBulwark", Size = V(9.4, 0.7, 0.18), Pos = V(-1.7, 2.75, 26.09), Color = HULL, Material = M.Metal, MinLevel = 1 },
	{ Name = "BoatBulwark", Size = V(13, 0.7, 0.18), Pos = V(-3.5, 2.75, 31.91), Color = HULL, Material = M.Metal, MinLevel = 1 },
	{ Name = "BoatWheelhouse", Size = V(6, 6, 4.4), Pos = V(-1.5, 5.4, 29), Color = C(206, 210, 210), Material = M.Metal, MinLevel = 1, Collide = true, Shadow = true },
	{ Name = "BoatBridgeGlass", Size = V(6.12, 1.5, 4.52), Pos = V(-1.5, 7.05, 29), Color = C(40, 62, 82), Material = M.Glass, MinLevel = 1 },
	{ Name = "BoatWheelhouseRoof", Size = V(6.8, 0.3, 5), Pos = V(-1.3, 8.55, 29), Color = C(150, 156, 160), Material = M.Metal, MinLevel = 1 },
	{ Name = "BoatMast", Size = V(0.3, 4.2, 0.3), Pos = V(-2.5, 10.8, 29), Color = C(220, 220, 220), Material = M.Metal, MinLevel = 1 },
	{ Name = "BoatRadarBar", Size = V(0.25, 0.2, 2.4), Pos = V(-2.5, 11.9, 29), Color = DARK, Material = M.Metal, MinLevel = 1 },
	{ Name = "BoatMastLight", Shape = "Ball", Size = V(0.45, 0.45, 0.45), Pos = V(-2.5, 13.1, 29), Color = C(250, 248, 236), Material = M.SmoothPlastic, MinLevel = 1 },
	{ Name = "BoatBowRail", Size = V(0.12, 0.12, 1), From = V(3.2, 3.9, 26.25), To = V(12.2, 4.25, 28.8), Color = C(200, 204, 206), Material = M.Metal, MinLevel = 1 },
	{ Name = "BoatBowRail", Size = V(0.12, 0.12, 1), From = V(3.2, 3.9, 31.75), To = V(12.2, 4.25, 29.2), Color = C(200, 204, 206), Material = M.Metal, MinLevel = 1 },
	{ Name = "BoatGunMount", Shape = "Cylinder", Size = V(0.7, 1.4, 1.4), Pos = V(5.8, 3.55, 29), Rot = V(0, 0, 90), Color = C(110, 116, 122), Material = M.Metal, MinLevel = 1 },
	{ Name = "BoatGunBarrel", Shape = "Cylinder", Size = V(2.8, 0.3, 0.3), Pos = V(7.5, 3.95, 29), Color = C(58, 62, 66), Material = M.Metal, MinLevel = 1 },
	{ Name = "BoatExhaust", Size = V(1.2, 1.4, 1.6), Pos = V(-6, 3.1, 29), Color = C(60, 64, 68), Material = M.Metal, MinLevel = 1 },
	{ Name = "BoatLifeRing", Shape = "Cylinder", Size = V(0.15, 1.1, 1.1), Pos = V(-0.5, 4.3, 26.72), Rot = V(0, 90, 0), Color = C(230, 110, 40), Material = M.SmoothPlastic, MinLevel = 1 },
	-- three hanging fenders on the quay side (clear of the gangway, x -8.4 .. -6.6), a gangway from the quay onto the aft
	-- deck through the bulwark's boarding gap (walkable), two mooring lines
	{ Name = "BoatFender", Shape = "Cylinder", Size = V(1.5, 0.7, 0.7), Pos = V(-5.5, 1.6, 25.65), Rot = V(0, 0, 90), Color = C(40, 48, 60), Material = M.Rubber, MinLevel = 1 },
	{ Name = "BoatFender", Shape = "Cylinder", Size = V(1.5, 0.7, 0.7), Pos = V(-1, 1.6, 25.65), Rot = V(0, 0, 90), Color = C(40, 48, 60), Material = M.Rubber, MinLevel = 1 },
	{ Name = "BoatFender", Shape = "Cylinder", Size = V(1.5, 0.7, 0.7), Pos = V(4.5, 1.6, 25.65), Rot = V(0, 0, 90), Color = C(40, 48, 60), Material = M.Rubber, MinLevel = 1 },
	{ Name = "Gangway", Size = V(1.8, 0.2, 1), From = V(-7.5, 0.55, 21.6), To = V(-7.5, 2.55, 27.4), Color = C(120, 124, 126), Material = M.DiamondPlate, MinLevel = 1, Collide = true },
	{ Name = "MooringLine", Size = V(0.18, 0.18, 1), From = V(-9, 2.6, 26.4), To = V(-12, 1.55, 22.6), Color = ROPE, Material = M.Fabric, MinLevel = 1 },
	{ Name = "MooringLine", Size = V(0.18, 0.18, 1), From = V(7.5, 3.3, 26.4), To = V(14, 1.55, 22.6), Color = ROPE, Material = M.Fabric, MinLevel = 1 },

	-- ── L2 quay crane (sea-gate end of the quay, jib over the launch berth), lamp posts, cargo at the gable end ─────────
	-- (the crates and drums stand on the bare pad by the gable end, landward of the quay: bottom at 0)
	{ Name = "CranePedestal", Shape = "Cylinder", Size = V(9, 2.4, 2.4), Pos = V(22, 4.9, 21.5), Rot = V(0, 0, 90), Color = CRANE, Material = M.Metal, MinLevel = 2, Collide = true },
	{ Name = "CraneCab", Size = V(3.6, 3, 4.4), Pos = V(22, 10.9, 21), Color = CRANE, Material = M.Metal, MinLevel = 2, Shadow = true },
	{ Name = "CraneCounterweight", Size = V(3.2, 2.2, 2.2), Pos = V(22, 10.5, 17.9), Color = C(92, 94, 96), Material = M.Concrete, MinLevel = 2 },
	{ Name = "CraneJib", Size = V(0.9, 0.9, 1), From = JIB_FROM, To = JIB_TIP, Color = CRANE, Material = M.Metal, MinLevel = 2 },
	{ Name = "CraneCable", Size = V(0.12, 4.2, 0.12), Pos = V(JIB_TIP.X, JIB_TIP.Y - 2.1, JIB_TIP.Z), Color = DARK, Material = M.Metal, MinLevel = 2 },
	{ Name = "CraneHook", Size = V(0.9, 1, 0.9), Pos = V(JIB_TIP.X, JIB_TIP.Y - 4.7, JIB_TIP.Z), Color = C(40, 40, 40), Material = M.Metal, MinLevel = 2 },
	{ Name = "LampPost", Size = V(0.35, 9, 0.35), Pos = V(-31, 4.9, 22.2), Color = C(72, 76, 78), Material = M.Metal, MinLevel = 2 },
	{ Name = "LampHead", Size = V(0.7, 0.35, 1.8), Pos = V(-31, 9.4, 21.6), Color = C(230, 226, 206), Material = M.SmoothPlastic, MinLevel = 2 },
	{ Name = "LampPost", Size = V(0.35, 9, 0.35), Pos = V(4, 4.9, 21.8), Color = C(72, 76, 78), Material = M.Metal, MinLevel = 2 },
	{ Name = "LampHead", Size = V(0.7, 0.35, 1.8), Pos = V(4, 9.4, 21.2), Color = C(230, 226, 206), Material = M.SmoothPlastic, MinLevel = 2 },
	{ Name = "CargoCrate", Size = V(2.4, 2.4, 2.4), Pos = V(-17.5, 1.2, -8.4), Color = C(156, 120, 78), Material = M.WoodPlanks, MinLevel = 2, Collide = true },
	{ Name = "CargoCrate", Size = V(2, 2, 2), Pos = V(-17.4, 3.4, -8.2), Rot = V(0, 18, 0), Color = C(146, 112, 72), Material = M.WoodPlanks, MinLevel = 2, Collide = true },
	{ Name = "FuelDrum", Shape = "Cylinder", Size = V(2.2, 1.5, 1.5), Pos = V(-17.2, 1.1, -5), Rot = V(0, 0, 90), Color = C(52, 92, 62), Material = M.Metal, MinLevel = 2, Collide = true },
	{ Name = "FuelDrum", Shape = "Cylinder", Size = V(2.2, 1.5, 1.5), Pos = V(-17.6, 1.1, -11.6), Rot = V(0, 0, 90), Color = C(150, 58, 44), Material = M.Metal, MinLevel = 2, Collide = true },

	-- ── L3 harbour control tower by the sea gate end of the quay, stacked containers ───────────────────────────────
	-- (the tower stands on the quay: bottom at +0.4; the containers stand on the pad beside the helipad: bottom at 0)
	{ Name = "TowerShaft", Size = V(6, 13, 6), Pos = V(27, 6.9, 10), Color = TRIM, Material = M.Concrete, MinLevel = 3, Collide = true, Shadow = true },
	{ Name = "TowerCab", Size = V(7.6, 3.4, 7.6), Pos = V(27, 15.1, 10), Color = C(226, 228, 226), Material = M.Metal, MinLevel = 3, Collide = true, Shadow = true },
	{ Name = "TowerGlass", Size = V(7.72, 2, 7.72), Pos = V(27, 15.3, 10), Color = GLASS, Material = M.Glass, MinLevel = 3 },
	{ Name = "TowerRoof", Size = V(8.6, 0.45, 8.6), Pos = V(27, 17.03, 10), Color = C(66, 72, 78), Material = M.Metal, MinLevel = 3, Collide = true },
	{ Name = "TowerDoor", Size = V(2.4, 5, 0.2), Pos = V(27, 2.9, 13.1), Color = DOOR, Material = M.Metal, MinLevel = 3 },
	{ Name = "TowerWindow", Size = V(0.2, 6, 1.2), Pos = V(23.9, 7.5, 10), Color = GLASS, Material = M.Glass, MinLevel = 3 },
	{ Name = "TowerMast", Size = V(0.3, 5, 0.3), Pos = V(27, 19.75, 10), Color = C(210, 210, 210), Material = M.Metal, MinLevel = 3 },
	{ Name = "TowerRadar", Size = V(0.3, 0.25, 3.2), Pos = V(27, 21.4, 10), Color = DARK, Material = M.Metal, MinLevel = 3 },
	{ Name = "Container", Size = V(12, 5.2, 5), Pos = V(21, 2.6, 0.2), Color = C(156, 66, 46), Material = M.Metal, MinLevel = 3, Collide = true, Shadow = true },
	{ Name = "Container", Size = V(12, 5.2, 5), Pos = V(21, 2.6, -5.3), Color = C(46, 86, 136), Material = M.Metal, MinLevel = 3, Collide = true, Shadow = true },
	{ Name = "Container", Size = V(12, 5.2, 5), Pos = V(21.6, 7.8, -2.55), Color = C(72, 116, 76), Material = M.Metal, MinLevel = 3, Collide = true, Shadow = true },

	-- ── L4 harbour launch (rigid inflatable) moored under the crane, ahead of the patrol boat ─────────────────────
	{ Name = "LaunchHull", Size = V(7, 0.7, 2.6), Pos = V(21, 0.55, 27.6), Color = C(64, 68, 72), Material = M.Metal, MinLevel = 4, Collide = true },
	{ Name = "LaunchTube", Shape = "Cylinder", Size = V(7.4, 0.9, 0.9), Pos = V(21, 0.95, 26.4), Color = C(46, 50, 54), Material = M.Rubber, MinLevel = 4 },
	{ Name = "LaunchTube", Shape = "Cylinder", Size = V(7.4, 0.9, 0.9), Pos = V(21, 0.95, 28.8), Color = C(46, 50, 54), Material = M.Rubber, MinLevel = 4 },
	{ Name = "LaunchConsole", Size = V(0.9, 1, 1.1), Pos = V(21.5, 1.4, 27.6), Color = C(190, 192, 194), Material = M.Metal, MinLevel = 4 },
	{ Name = "LaunchMotor", Size = V(0.7, 1.4, 0.8), Pos = V(17.2, 1, 27.6), Color = C(30, 32, 34), Material = M.Metal, MinLevel = 4 },

	-- ── L5: gold band on the control cab + an amber beacon on its mast (painted, no light) ─────────────────────────
	{ Name = "TowerGoldBand", Size = V(7.75, 0.3, 7.75), Pos = V(27, 16.62, 10), Color = C(240, 196, 64), Material = M.Metal, MinLevel = 5 },
	{ Name = "TowerBeacon", Shape = "Ball", Size = V(0.8, 0.8, 0.8), Pos = V(27, 22.6, 10), Color = C(255, 176, 48), Material = M.SmoothPlastic, MinLevel = 5 },
	-- warehouse chimney on the landward roof slope. It MUST be named "Roof": BaseService hangs every structure's L5 smoke
	-- plume (WE_MaxSmoke) on the kit child called "Roof", as the old dock kit's shed roof had it.
	{ Name = "Roof", Size = V(1.6, 3.4, 1.6), Pos = V(8, 13.2, -10), Color = C(118, 68, 54), Material = M.Brick, MinLevel = 5 },
}

local DockKitConfig = {
	Enabled = true,
	PadTopY = 0.5, -- the site frame is at the pad centre; the pad is 1 stud thick
	-- StructureKitBuilder's required "Body" (EnsureKit): a concrete core at the warehouse footprint. From L1 it sits
	-- inside the 28 x 10 x 18 warehouse block (BaseService recolours and grows it with the level, up to 24.7 x 1.28 x
	-- 14.4 at L5), so it is hidden there. At L0, before the warehouse shows, it is the Dock's translucent footprint
	-- ghost like every unbought structure's Body (main's v35 dock shows a 24 x 1.4 x 16 ghost there too).
	Body = { Size = V(24, 0.8, 14), Pos = V(-1, 0.4, -5) },
	-- Hidden host inside the hull: StructureKitBuilder.EnsureKit counts a "WE_DressHost*" child as the Dock's dress (no
	-- rebuild loop); no WE_DressVehicle, so no catalog boat is ever hung on it.
	ParkedBoatHost = { Size = V(2.8, 1.2, 2), Pos = V(-1, 1.2, 29) },
	Pieces = pieces,
}

return DockKitConfig
