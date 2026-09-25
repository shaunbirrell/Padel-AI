--!strict
--[[
	Special Forces facility interior (HollowBuildingBuilder, config Interior = "SpecialForces"). Elite operators' HQ:
	dark, tactical, no clutter.

	Ground floor
	  West   ops-briefing area: a large wall screen on the west wall, rows of seats on a rubber mat facing it
	         (2 x 3, 2 x 4 from L2) and the ops-briefing podium terminal (Missions) in the front-west corner.
	  Centre sand table (terrain model with the objective pinned).
	  East   tactical gear wall (vests + helmets on a MOLLE board over a kit bench), the operator terminal (Army)
	         under the roster board, equipment cages in the back-east corner (second cage from L2).
	  Front  night-vision / comms bench between the east front window and the door (NVGs, radios in a charging
	         dock, shelf with a manpack from L2, comms monitor from L4); unit colours between the two windows.
	  Back   L1-L2 only: PT corner (mat, pull-up rig, climbing rope, plyo box) — the stairs take that strip at L3.
	Upper floor (two storeys from L3): a kill house of low plywood partitions — four rooms, walk-through, entry and
	  exit on its east side facing the stair landing — with pop-up targets (2 / 3 / 4 at L3 / L4 / L5), the kill-house
	  terminal (Army) beside the entry, a fast-rope / rappel frame over a crash mat (1 / 2 / 3 ropes) and operator
	  lockers with a bench in the back-east corner (a second bank from L4).

	Layout (building-local, +Z = front/door, door at X = 9): stairs run along the back wall from L3
	(X -13.7..5.5, Z -10.2..-5.7, foot at the west end), so nothing collidable sits at z < -4.7 west of x = 6 from L3
	and the strip in front of the stairs stays open. Tall items stay out of the window bands (front windows only on
	the ground floor; front + side windows upstairs) and the upper landing (x 2.9..8.5, z < -4.5) stays clear.
]]

return function(ictx: any, api: any)
	local col = ictx.Colors
	local lv: number = ictx.Level
	local y1: number = ictx.Y1
	local X0: number, X1: number, Z0: number, Z1: number = ictx.InX0, ictx.InX1, ictx.InZ0, ictx.InZ1
	local M = Enum.Material
	local N = Enum.NormalId
	local screenBg = Color3.fromRGB(8, 20, 12)

	local function B(name: string, sx: number, sy: number, sz: number, x: number, y: number, z: number, color: Color3, mat: Enum.Material, collide: boolean?): Part
		return api.box(name, Vector3.new(sx, sy, sz), Vector3.new(x, y, z), color, mat, collide)
	end

	-- ── Ops briefing (west wall) ─────────────────────────────────────────────
	local scrZ = 2.5
	B("BriefScreenFrame", 0.1, 5.6, 9.6, X0 + 0.05, y1 + 6.8, scrZ, col.Trim, M.Metal, false)
	local scr = B("BriefScreen", 0.15, 5, 9, X0 + 0.175, y1 + 6.8, scrZ, col.Dark, M.SmoothPlastic, false)
	api.light(scr, 10, 0.5, col.Screen)
	api.surfaceText(scr, N.Right, { "OPS BRIEFING · TIER " .. tostring(lv), "OBJ: RIDGE OUTPOST", "INFIL 0300 · NO COMMS" }, col.Screen, screenBg, Enum.Font.Code)

	-- Briefing podium in the front-west corner, beside the screen → Missions
	api.terminal("BriefingTerminal", Vector3.new(X0 + 0.6, y1, 8.6), 90, "Missions", "Mission briefing", "Ops Room", { "OPS ROOM", "MISSION BRIEFING" })

	-- Seats in two rows facing the screen, on a rubber mat
	B("BriefingMat", 7.4, 0.06, 8.6, -8.0, y1 + 0.03, scrZ, col.Rug, M.Fabric, false)
	local seatZ = if lv >= 2 then { -0.5, 1.5, 3.5, 5.5 } else { 0.5, 2.5, 4.5 }
	for _, rx in ipairs({ -9.4, -6.6 }) do
		for _, sz in ipairs(seatZ) do
			api.chair(Vector3.new(rx, y1, sz), Vector3.new(-1, 0, 0))
		end
	end

	-- ── Sand table (centre) ──────────────────────────────────────────────────
	local stX, stZ = 1.4, -0.4
	B("SandTableBase", 4.6, 2.6, 3.0, stX, y1 + 1.3, stZ, col.Dark, M.Metal)
	B("SandTable", 5.2, 0.3, 3.6, stX, y1 + 2.75, stZ, col.Sandbag, M.SmoothPlastic)
	B("SandRidge", 2.2, 0.5, 1.2, stX - 1.1, y1 + 3.15, stZ - 0.9, col.Rug, M.SmoothPlastic, false)
	B("SandObjective", 0.9, 0.4, 0.9, stX + 1.4, y1 + 3.1, stZ + 0.6, col.Dark, M.SmoothPlastic, false)
	B("SandPin", 0.2, 0.9, 0.2, stX + 1.4, y1 + 3.75, stZ + 0.6, col.Accent, M.SmoothPlastic, false)

	-- ── Tactical gear wall (east wall) ───────────────────────────────────────
	local gz = -3.5
	B("GearBoard", 0.15, 5.2, 6.4, X1 - 0.075, y1 + 4.2, gz, col.Dark, M.Metal, false)
	B("HelmetShelf", 0.9, 0.15, 6.2, X1 - 0.6, y1 + 5.5, gz, col.Metal, M.Metal, false)
	local kitZ = if lv >= 2 then { -5.8, -4.25, -2.7, -1.15 } else { -5.4, -3.5, -1.6 }
	for _, kz in ipairs(kitZ) do
		B("Vest", 0.45, 2.2, 1.4, X1 - 0.375, y1 + 3.6, kz, col.Locker, M.Fabric, false)
		B("Helmet", 0.85, 0.55, 0.85, X1 - 0.6, y1 + 5.85, kz, col.Sandbag, M.SmoothPlastic, false)
	end
	B("KitBench", 1.2, 1.0, 5.8, X1 - 0.6, y1 + 0.5, gz, col.Metal, M.Metal)

	-- ── Operator terminal (east wall) → Army, roster board above it ─────────
	local armyZ = 2.4
	api.terminal("OperatorTerminal", Vector3.new(X1 - 0.6, y1, armyZ), -90, "Army", "Command operators", "Special Forces", { "SF COMMAND", "OPERATORS" })
	local roster = B("RosterBoard", 0.12, 2.8, 4.2, X1 - 0.06, y1 + 6.4, armyZ, col.Dark, M.Metal, false)
	api.surfaceText(roster, N.Left, { "OPERATOR ROSTER", "TEAMS READY: " .. tostring(math.min(lv + 1, 6)), "STATUS: GREEN" }, col.Screen, screenBg, Enum.Font.Code)

	-- ── Equipment cages (back-east corner) ───────────────────────────────────
	local cz1 = Z0 + 3.2
	local cageH = 7
	local bounds: { number } = if lv >= 2 then { 6.4, 10.3, X1 } else { 10.3, X1 }
	local postX: { number } = {}
	for i, bx in ipairs(bounds) do
		local px = if i == 1 then bx + 0.15 elseif i == #bounds then bx - 0.15 else bx
		postX[i] = px
		B("CagePost", 0.3, cageH, 0.3, px, y1 + cageH * 0.5, cz1 - 0.15, col.Metal, M.Metal)
		if i < #bounds then
			local side = B("CageMesh", 0.1, cageH - 0.4, cz1 - Z0 - 0.3, px, y1 + 0.2 + (cageH - 0.4) * 0.5, (Z0 + cz1 - 0.3) * 0.5, col.Metal, M.Metal)
			side.Transparency = 0.5
		end
	end
	for i = 1, #bounds - 1 do
		local a, b = postX[i] + 0.15, postX[i + 1] - 0.15
		local front = B("CageMesh", b - a, cageH - 0.4, 0.1, (a + b) * 0.5, y1 + 0.2 + (cageH - 0.4) * 0.5, cz1 - 0.15, col.Metal, M.Metal)
		front.Transparency = 0.5
	end
	-- contents: ammo crates in the corner cage, kit bags in the second
	B("AmmoCrate", 2.4, 1.3, 1.6, 12.3, y1 + 0.65, Z0 + 1.2, col.Locker, M.Wood)
	B("AmmoCrate", 1.8, 1.0, 1.4, 12.3, y1 + 1.8, Z0 + 1.2, col.Locker, M.Wood)
	if lv >= 2 then
		B("KitBag", 2.6, 1.1, 1.3, 8.4, y1 + 0.55, Z0 + 1.1, col.Rug, M.Fabric)
	end

	-- ── Night-vision / comms bench (front wall, between the window and the door) ──
	local bx = 2.1
	local topY = y1 + 2.9
	B("CommsBench", 5.0, 2.7, 1.4, bx, y1 + 1.35, Z1 - 0.7, col.Dark, M.Metal)
	B("CommsBenchTop", 5.3, 0.2, 1.7, bx, y1 + 2.8, Z1 - 0.85, col.Metal, M.DiamondPlate)
	for i = 1, (if lv >= 2 then 2 else 1) do
		local nx = -0.1 + (i - 1) * 1.2
		B("NVGoggles", 0.9, 0.4, 0.5, nx, topY + 0.2, Z1 - 0.9, col.Dark, M.Metal, false)
		B("NVGLens", 0.7, 0.18, 0.06, nx, topY + 0.2, Z1 - 1.18, col.Screen, M.SmoothPlastic, false) -- v70: painted lens (no decorative Neon)
	end
	for _, rx in ipairs({ 2.15, 3.05 }) do
		B("Radio", 0.55, 1.1, 0.4, rx, topY + 0.55, Z1 - 0.7, col.Locker, M.SmoothPlastic, false)
	end
	local shelf = B("CommsShelf", 5.0, 0.4, 0.9, bx, y1 + 5.6, Z1 - 0.45, col.Metal, M.Metal, false)
	api.surfaceText(shelf, N.Front, { "COMMS · NVG" }, col.Accent, col.Dark, Enum.Font.GothamBlack)
	if lv >= 2 then
		B("ManpackRadio", 2.2, 0.9, 0.7, 1.2, y1 + 6.25, Z1 - 0.45, col.Locker, M.SmoothPlastic, false)
	end
	if lv >= 4 then
		local mon = B("CommsMonitor", 1.3, 1.0, 0.12, 4.0, topY + 0.5, Z1 - 0.3, col.Dark, M.Metal, false)
		api.surfaceText(mon, N.Front, { "NET 2", "SECURE" }, col.Screen, screenBg, Enum.Font.Code)
	end

	-- Unit colours between the two front windows
	-- fb2: 0.12 thick (back face still flush on the front wall) + WE_FlagHost; the nation flag binds to the Front face,
	-- which also carries the SPECIAL FORCES text
	local flag = B("UnitFlag", 1.8, 3.2, 0.12, -6.5, y1 + 6.0, Z1 - 0.06, col.Flag, M.Fabric, false)
	flag:SetAttribute("WE_FlagHost", true)
	api.surfaceText(flag, N.Front, if lv >= 5 then { "TIER ONE", "SPECIAL", "FORCES" } else { "SPECIAL", "FORCES" }, col.Sandbag, col.Flag, Enum.Font.GothamBlack)

	-- ── PT corner along the back wall (single storey only; the stairs take this strip from L3) ──
	if not ictx.TwoStory then
		B("PTMat", 10.5, 0.08, 4.4, -7.85, y1 + 0.04, -7.8, col.Rug, M.Fabric, false)
		for _, px in ipairs({ -12.2, -7.8 }) do
			B("PullUpPost", 0.35, 8, 0.35, px, y1 + 4, -9.4, col.Metal, M.Metal)
		end
		B("PullUpBar", 4.75, 0.25, 0.25, -10.0, y1 + 7.6, -9.4, col.Metal, M.Metal, false)
		B("RopeBracket", 1.2, 0.3, 1.2, -3.8, y1 + 11.75, -7.6, col.Metal, M.Metal, false)
		B("ClimbRope", 0.35, 10.8, 0.35, -3.8, y1 + 6.2, -7.6, col.Sandbag, M.Fabric, false)
		B("PlyoBox", 2.0, 1.6, 1.6, 0.4, y1 + 0.8, -8.6, col.Sandbag, M.Wood)
		B("Kettlebell", 0.7, 0.7, 0.7, 2.4, y1 + 0.35, -9.3, col.Dark, M.Metal)
		B("Kettlebell", 0.7, 0.7, 0.7, 3.3, y1 + 0.35, -9.3, col.Dark, M.Metal)
	end

	-- ── Upper floor (L3+) ────────────────────────────────────────────────────
	if ictx.TwoStory then
		local y2: number = ictx.Y2
		local wallH = 4.4

		-- Kill house: low plywood partitions from the west wall to x = KX, north edge NZ to the front wall.
		-- Rooms A (NE) → B (NW) → C (SW) → D (SE); entry and exit doors on the east side, 3 studs wide.
		local KX, SX, NZ, CZ = 1.5, -6.2, -3.8, 3.0
		local function partition(x0: number, x1: number, z0: number, z1: number)
			local sx = math.max(x1 - x0, 0.3)
			local sz = math.max(z1 - z0, 0.3)
			B("KillHouseWall", sx, wallH, sz, (x0 + x1) * 0.5, y2 + wallH * 0.5, (z0 + z1) * 0.5, col.Sandbag, M.WoodPlanks)
		end
		partition(X0, KX, NZ, NZ) -- north
		partition(KX, KX, NZ, -2.4) -- east: entry door z -2.4..0.6
		partition(KX, KX, 0.6, 5.4) -- exit door z 5.4..8.4
		partition(KX, KX, 8.4, Z1)
		partition(SX, SX, NZ, -0.2) -- spine: A→B door z -0.2..2.8
		partition(SX, SX, 2.8, 4.8) -- C→D door z 4.8..7.8
		partition(SX, SX, 7.8, Z1)
		partition(X0, -12.6, CZ, CZ) -- cross: B→C door x -12.6..-9.6
		partition(-9.6, SX, CZ, CZ)
		partition(SX, KX, CZ, CZ)

		-- Pop-up targets (dark = hostile, light = no-shoot), facing each room's entry
		local function target(x: number, z: number, alongX: boolean, c: Color3)
			local bs = if alongX then Vector3.new(0.1, 3.2, 1.1) else Vector3.new(1.1, 3.2, 0.1)
			local hs = if alongX then Vector3.new(0.1, 0.8, 0.7) else Vector3.new(0.7, 0.8, 0.1)
			api.box("Target", bs, Vector3.new(x, y2 + 1.6, z), c, M.Wood)
			api.box("TargetHead", hs, Vector3.new(x, y2 + 3.6, z), c, M.Wood, false)
		end
		target(-4.4, -2.6, true, col.Dark)
		target(-12.0, -2.4, true, col.Dark)
		if lv >= 4 then
			target(-7.6, 8.6, false, col.Floor)
		end
		if lv >= 5 then
			target(-0.2, 4.2, true, col.Dark)
		end

		-- Kill-house control terminal beside the entry → Army
		api.terminal("KillHouseTerminal", Vector3.new(KX + 0.8, y2, 3.0), 90, "Army", "Train operators", "Kill House", { "KILL HOUSE", "ROOM-CLEAR DRILL" })
		-- stack-up line on the floor outside the entry (small hazard stripe)
		B("StackLine", 0.25, 0.04, 3.0, KX + 1.3, y2 + 0.02, -0.9, col.Accent, M.SmoothPlastic, false)
		local khSign = B("KillHouseSign", 0.14, 1.1, 4.4, KX, y2 + wallH + 0.55, 3.0, col.Dark, M.Metal, false)
		api.surfaceText(khSign, N.Right, { "KILL HOUSE", "LIVE DRILL" }, col.Accent, col.Dark, Enum.Font.GothamBlack)
		api.light(khSign, 10, 0.6, Color3.fromRGB(255, 96, 64)) -- dim red "live" glow over the entry

		-- Fast-rope / rappel frame over a crash mat (front-east)
		local RX = 10.5
		B("RappelPost", 0.5, 8.3, 0.5, RX, y2 + 4.15, 4.8, col.Metal, M.Metal)
		B("RappelPost", 0.5, 8.3, 0.5, RX, y2 + 4.15, 9.6, col.Metal, M.Metal)
		B("RappelBeam", 0.5, 0.5, 5.3, RX, y2 + 8.55, 7.2, col.Metal, M.Metal)
		B("CrashMat", 4.2, 0.5, 4.2, RX, y2 + 0.25, 7.2, col.Rug, M.Fabric)
		local ropeZ = if lv >= 5 then { 6.0, 7.2, 8.4 } elseif lv >= 4 then { 6.4, 8.0 } else { 7.2 }
		for _, rz in ipairs(ropeZ) do
			B("Rope", 0.35, 7.8, 0.35, RX, y2 + 4.4, rz, col.Sandbag, M.Fabric, false)
		end
		local rSign = B("RappelSign", 0.1, 1.4, 4.0, X1 - 0.05, y2 + 6.2, 7.2, col.Dark, M.Metal, false)
		api.surfaceText(rSign, N.Left, { "FAST ROPE", "RAPPEL POINT" }, col.Accent, col.Dark, Enum.Font.GothamBlack)

		-- Operator lockers + bench (back-east corner, clear of the landing): a bank of three on the back wall,
		-- a bank of two on the east wall from L4 (one body per bank, dark seams between the doors)
		B("LockerBank", 4.8, 7, 1.6, 11.5, y2 + 3.5, Z0 + 0.8, col.Locker, M.Metal)
		for _, sx in ipairs({ 10.7, 12.3 }) do
			B("LockerSeam", 0.08, 6.6, 0.06, sx, y2 + 3.5, Z0 + 1.63, col.Dark, M.Metal, false)
		end
		if lv >= 4 then
			B("LockerBank", 1.6, 7, 3.0, X1 - 0.8, y2 + 3.5, -6.6, col.Locker, M.Metal)
			B("LockerSeam", 0.06, 6.6, 0.08, X1 - 1.63, y2 + 3.5, -6.6, col.Dark, M.Metal, false)
		end
		B("LockerBench", 2.8, 0.9, 1.0, 10.8, y2 + 0.45, -7.4, col.Trim, M.WoodPlanks)
	end
end
