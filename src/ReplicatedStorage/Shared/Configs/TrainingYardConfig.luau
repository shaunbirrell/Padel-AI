--!strict
--[[
	Training Yard (owner feedback 2026-09-27: "the soldier training area is terrible, very very bad"). One per base,
	built by TrainingYardBuilder (called from MapSetup's plot build), the same at every base level.

	The look: a 3-lane shooting range seen from behind the firing line (3 soldiers at the line with an ammo box each,
	rifles toward white targets with a red ring, a sand berm behind the targets, a rifle rack along the side), and
	beyond the berm a small obstacle course (2 log hurdles and a jump wall with a ladder) and a
	supply corner (a canvas tent, a crate stack, an ammo crate). The strip behind the firing line stays open, so the
	phone camera behind a player at the line sees down the lanes. No text, no lights, no Neon, no SurfaceGuis, no
	billboards.

	Coordinates: yard-local studs. X / Z are offsets from BaseLayoutConfig.Courtyard.TrainingYard (plot-local), +X is
	downrange (the targets), +Z toward the main gate. Y is the BOTTOM of a piece above the plot pad top (Y = PadTop is on
	the range floor). Yaw is degrees about +Y (CFrame.Angles(0, rad(Yaw), 0)); a figure faces its -Z, so Yaw = -90 faces
	downrange. Cylinders lie along their X axis.

	Parts (headless census, every level): 65 per yard with the Part look (HEAD 84), 76 when every Roblox mesh below has
	loaded (a mesh on a colliding host keeps the host as an invisible collider; a mesh on a non-colliding host replaces
	it; decor meshes have no host). Figures are makeSoldierKit statues (R-RIG turns them into Roblox's Soldier body).

	Meshes: Roblox-made Synty pieces (creator Roblox, User 1) from packs that already load live (0 new load attempts);
	the textured ones all share the one Dungeon pack atlas (the log is the live, texture-cleared DesertKit.Log),
	VisualAssetConfig.DesertKit keys through VisualAssetService.CloneKitMesh, deferred. A failed or skipped load keeps
	the Part look below (it is complete on its own). UseMeshes = false: Part look only, no CloneKitMesh call.
]]

export type Piece = {
	Name: string,
	Shape: string, -- "Block" | "Cylinder" | "Wedge"
	Size: Vector3,
	X: number,
	Y: number,
	Z: number,
	Yaw: number?,
	Color: Color3,
	Material: Enum.Material,
	Collide: boolean,
	Mesh: string?, -- VisualAssetConfig.DesertKit key: the piece becomes this mesh (fitted into the piece's box)
	MeshYaw: number?, -- degrees that turn the mesh onto the piece's axes (the Synty log is long along its Z)
	Target: boolean?, -- attribute WE_TrainingTarget (+ PlotId)
}

export type Figure = { Name: string, Kind: string, X: number, Z: number, Yaw: number, Body: Color3, Accent: Color3 }

export type Decor = { Mesh: string, X: number, Y: number, Z: number, Yaw: number, Tilt: number?, Scale: number }

local C = Color3.fromRGB
local M = Enum.Material

local LANES = { -7, 0, 7 } -- yard-local Z of the three lanes
local TARGET_X = 17
local BOARD_BOTTOM = 2.5 -- above the plot pad top (the range floor is 0.2 up)
local BOARD_H = 3.4
local RING_C = BOARD_BOTTOM + BOARD_H * 0.5 -- ring / bull centre height

local pieces: { Piece } = {
	-- range floor: packed earth (read by ProducerLabels / SoldierService as "YardPad"; keep the name)
	{ Name = "YardPad", Shape = "Block", Size = Vector3.new(36, 0.6, 22), X = 8, Y = -0.4, Z = 0, Color = C(139, 118, 88), Material = M.Ground, Collide = true },
	-- painted lines: the firing line and two lane dividers
	{ Name = "FiringLine", Shape = "Block", Size = Vector3.new(0.35, 0.06, 21.4), X = -5, Y = 0.2, Z = 0, Color = C(236, 234, 224), Material = M.SmoothPlastic, Collide = false },
	{ Name = "LaneLine1", Shape = "Block", Size = Vector3.new(21.5, 0.06, 0.25), X = 5.75, Y = 0.2, Z = -3.5, Color = C(236, 234, 224), Material = M.SmoothPlastic, Collide = false },
	{ Name = "LaneLine2", Shape = "Block", Size = Vector3.new(21.5, 0.06, 0.25), X = 5.75, Y = 0.2, Z = 3.5, Color = C(236, 234, 224), Material = M.SmoothPlastic, Collide = false },
	-- backstop berm behind the targets: two wedges back to back (a ridge along Z), 6 studs high
	{ Name = "BermFront", Shape = "Wedge", Size = Vector3.new(21.4, 6, 3.5), X = 19.75, Y = 0.2, Z = 0, Yaw = 90, Color = C(176, 150, 106), Material = M.Sand, Collide = true },
	{ Name = "BermBack", Shape = "Wedge", Size = Vector3.new(21.4, 6, 3.5), X = 23.25, Y = 0.2, Z = 0, Yaw = -90, Color = C(168, 142, 100), Material = M.Sand, Collide = true },
	-- obstacle course beyond the berm (runs +Z from the Research Lab walk): log, jump wall, log
	{ Name = "CourseLog1", Shape = "Cylinder", Size = Vector3.new(10, 1.6, 1.6), X = 33, Y = 0, Z = -10, Color = C(110, 84, 58), Material = M.Wood, Collide = true, Mesh = "Log", MeshYaw = 90 },
	{ Name = "CourseWall", Shape = "Block", Size = Vector3.new(10, 5, 0.8), X = 33, Y = 0, Z = -4.5, Color = C(126, 98, 66), Material = M.WoodPlanks, Collide = true },
	{ Name = "CourseLog2", Shape = "Cylinder", Size = Vector3.new(10, 1.6, 1.6), X = 33, Y = 0, Z = 1, Color = C(104, 80, 55), Material = M.Wood, Collide = true, Mesh = "Log", MeshYaw = 90 },
	-- supply corner beyond the berm, south of the course (out of the view down the lanes): canvas tent (two wedges,
	-- ridge along X), a crate stack and an ammo crate
	{ Name = "TentNorth", Shape = "Wedge", Size = Vector3.new(7, 4.2, 2.75), X = 31, Y = 0, Z = 7.875, Yaw = 0, Color = C(96, 108, 72), Material = M.Fabric, Collide = true },
	{ Name = "TentSouth", Shape = "Wedge", Size = Vector3.new(7, 4.2, 2.75), X = 31, Y = 0, Z = 10.625, Yaw = 180, Color = C(88, 100, 66), Material = M.Fabric, Collide = true },
	{ Name = "SupplyCrate1", Shape = "Block", Size = Vector3.new(2.5, 2.5, 2.5), X = 37, Y = 0, Z = 6.5, Color = C(120, 92, 58), Material = M.Wood, Collide = true, Mesh = "YardCrate" },
	{ Name = "SupplyCrate2", Shape = "Block", Size = Vector3.new(2.5, 2.5, 2.5), X = 37, Y = 0, Z = 9.1, Color = C(112, 86, 54), Material = M.Wood, Collide = true, Mesh = "YardCrate" },
	{ Name = "SupplyCrate3", Shape = "Block", Size = Vector3.new(2.5, 2.5, 2.5), X = 37, Y = 2.5, Z = 7.8, Yaw = 15, Color = C(124, 96, 60), Material = M.Wood, Collide = true, Mesh = "YardCrate" },
	{ Name = "AmmoCrate", Shape = "Block", Size = Vector3.new(1.9, 1.9, 1.9), X = 36.8, Y = 0, Z = 12.2, Yaw = 10, Color = C(70, 78, 58), Material = M.Metal, Collide = true, Mesh = "YardAmmoCrate" },
}

-- targets: board on two legs, red ring, black bull; the board faces the firing line (-X)
for i, z in ipairs(LANES) do
	table.insert(pieces, { Name = "TrainingTarget" .. i, Shape = "Block", Size = Vector3.new(0.3, BOARD_H, 3.2), X = TARGET_X, Y = BOARD_BOTTOM, Z = z, Color = C(236, 232, 218), Material = M.SmoothPlastic, Collide = true, Target = true })
	table.insert(pieces, { Name = "TargetStand" .. i, Shape = "Block", Size = Vector3.new(0.35, 2.7, 0.35), X = TARGET_X + 0.25, Y = 0.2, Z = z - 1.15, Color = C(92, 70, 48), Material = M.Wood, Collide = true })
	table.insert(pieces, { Name = "TargetLeg" .. i, Shape = "Block", Size = Vector3.new(0.35, 2.7, 0.35), X = TARGET_X + 0.25, Y = 0.2, Z = z + 1.15, Color = C(92, 70, 48), Material = M.Wood, Collide = true })
	table.insert(pieces, { Name = "TargetRing" .. i, Shape = "Cylinder", Size = Vector3.new(0.08, 2.6, 2.6), X = TARGET_X - 0.19, Y = RING_C - 1.3, Z = z, Color = C(190, 42, 36), Material = M.SmoothPlastic, Collide = false })
	-- a small ammo box at each firing point (beside the soldier's feet, low: the view down the lane stays open)
	table.insert(pieces, { Name = "AmmoBox" .. i, Shape = "Block", Size = Vector3.new(1.2, 1.2, 1.2), X = -6.2, Y = 0.2, Z = z + 1.7, Yaw = 8, Color = C(70, 78, 58), Material = M.Metal, Collide = true, Mesh = "YardAmmoCrate" })
	table.insert(pieces, { Name = "TargetBullseye" .. i, Shape = "Cylinder", Size = Vector3.new(0.08, 0.9, 0.9), X = TARGET_X - 0.25, Y = RING_C - 0.45, Z = z, Color = C(28, 28, 30), Material = M.SmoothPlastic, Collide = false })
end

local TrainingYardConfig = {
	UseMeshes = true, -- false: the Part look only (no CloneKitMesh call, no pack load from the yard)
	GroundY = 0.5, -- plot pad top in MapSetup's plot frame F
	PadTop = 0.2, -- the range floor's top above the plot pad top
	-- origin when BaseLayoutConfig is off (the legacy yard centre); otherwise Courtyard.TrainingYard
	LegacyOrigin = { X = -14, Z = 48 },

	Pieces = pieces,

	-- the soldiers at the firing line: makeSoldierKit statues (R-RIG: Roblox's Soldier, standing still, rifle forward),
	-- root 2.1 above the range floor like the old yard workers (feet on the floor)
	FigureRootY = 2.3,
	FigureHealth = 80,
	Figures = {
		{ Name = "YardShooter1", Kind = "Infantry", X = -7, Z = LANES[1], Yaw = -90, Body = C(70, 85, 55), Accent = C(180, 220, 120) },
		{ Name = "YardShooter2", Kind = "HeavyInfantry", X = -7, Z = LANES[2], Yaw = -90, Body = C(50, 55, 48), Accent = C(230, 160, 50) },
		{ Name = "YardShooter3", Kind = "Guard", X = -7, Z = LANES[3], Yaw = -90, Body = C(45, 55, 70), Accent = C(90, 140, 220) },
	} :: { Figure },

	-- mesh-only decor (no Part look; nothing is built when the mesh does not load). Y = the mesh CENTRE above the plot
	-- pad top; Tilt = degrees about the mesh's X after Yaw; Scale = one uniform factor on the piece's own size.
	Decor = {
		{ Mesh = "YardRack", X = -4.5, Y = 1.85, Z = -11.6, Yaw = 0, Scale = 0.85 }, -- rifle rack along the range's north edge
		{ Mesh = "YardLadder", X = 30.5, Y = 3.29, Z = -5.45, Yaw = 0, Tilt = 18, Scale = 0.42 }, -- leans on the jump wall
	} :: { Decor },
	MaxMeshesPerYard = 16, -- hard cap on CloneKitMesh pieces per yard (dressed pieces + decor; 11 configured)

	-- invisible anchors other code reads (TrainingYard folder): YardAnchor (fallback) over the range centre, and
	-- YardEarnAnchor: ManualDropperService puts the yard cash plate at it + ManualDropperConfig.YardOffset (6, 0, -4),
	-- so the plate lands at yard-local (-10, -13): on open ground at the corner of the Research Lab walk, off the range
	-- floor, 22 studs from the range centre (ProducerLabels shows the yard label within 24)
	YardAnchor = { X = 8, Y = 7.5, Z = 0 },
	YardEarnAnchor = { X = -16, Y = 5.5, Z = -9 },
}

return TrainingYardConfig
