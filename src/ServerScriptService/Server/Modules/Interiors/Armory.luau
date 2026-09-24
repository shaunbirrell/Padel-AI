--!strict
--[[
	Armory interior (StructureId WeaponsFacility, HollowBuildingBuilder). Weapons storage and issue.

	Ground floor
	  back-east   caged arms-issue counter: steel counter with the Shop terminal set in as the service hatch,
	              bars above, rifle racks on the cage walls behind, sidearm cabinet under the back window
	  west wall   squad loadout bay: Army terminal between kit lockers, loadout board above it
	  front pier  gunsmith workbench (vice, rifle on the bench, tool board) west of the door
	  windows     olive ammo crates (yellow stencil stripe) kept low under the window bands
	  centre      rifle-cleaning table; back-west ammo pallets while single-storey
	  L2+ second cage rack, third locker, tools, more crates / pallet · L3+ pier rifle rack, grenade + rifle crates
	Upper floor (two storeys from L4)
	  west        ammo storage: wall shelving + a freestanding row (L5 adds a third row), pallet of crates
	  east        test-fire lane: baffle wall, shooting bench, target plate and angled steel backstop at the back
	              wall, range terminal (Missions) at the firing point

	Layout (building-local, +Z = front/door): 30 x 22, doorway X 9, console (12.5, 7). The back-west strip
	(X < 6, Z < -4.7) only holds low pallets while single-storey — the stairs take it from L4 and the ammo
	store moves upstairs. Tall pieces stay out of the window bands (front X -10/-3, back X -8/8, sides Z 0).
]]

return function(ictx: any, api: any)
	local col = ictx.Colors
	local lv: number = ictx.Level
	local y1: number = ictx.Y1
	local X0: number, X1: number, Z0: number, Z1: number = ictx.InX0, ictx.InX1, ictx.InZ0, ictx.InZ1
	local doorX: number = ictx.DoorX
	local M = Enum.Material
	local N = Enum.NormalId
	local wood = Color3.fromRGB(118, 96, 68)
	local paper = col.Sandbag
	local screenBg = Color3.fromRGB(8, 20, 12)

	-- box placed by its bottom centre
	local function blk(name: string, sx: number, sy: number, sz: number, cx: number, yb: number, cz: number, color: Color3, mat: Enum.Material, collide: boolean?): Part
		return api.box(name, Vector3.new(sx, sy, sz), Vector3.new(cx, yb + sy * 0.5, cz), color, mat, collide)
	end

	-- painted stencil (yellow band + lettering) on one face — no extra parts
	local function stencil(host: BasePart, face: Enum.NormalId, text: string, stripe: boolean, top: number?, height: number?)
		local sg = Instance.new("SurfaceGui")
		sg.Name = "WE_Stencil"
		sg.Face = face
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 40
		sg.LightInfluence = 1
		sg.Parent = host
		if stripe then
			local band = Instance.new("Frame")
			band.Name = "Stripe"
			band.BackgroundColor3 = col.Accent
			band.BorderSizePixel = 0
			band.Position = UDim2.fromScale(0, 0.12)
			band.Size = UDim2.fromScale(1, 0.14)
			band.Parent = sg
		end
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Position = UDim2.fromScale(0.08, top or 0.4)
		lbl.Size = UDim2.fromScale(0.84, height or 0.4)
		lbl.Font = Enum.Font.GothamBlack
		lbl.Text = text
		lbl.TextColor3 = col.Accent
		lbl.TextScaled = true
		lbl.Parent = sg
	end

	-- olive ammo crate (bottom-centred), stencilled on the face toward the room; `band` adds a painted
	-- stripe round one end as a real part so it reads from every side
	local function crate(cx: number, yb: number, cz: number, sx: number, sy: number, sz: number, faces: { Enum.NormalId }, label: string, band: boolean): Part
		local c = blk("AmmoCrate", sx, sy, sz, cx, yb, cz, col.Trim, M.WoodPlanks)
		for _, f in ipairs(faces) do
			stencil(c, f, label, true)
		end
		if band then
			if sx >= sz then
				api.box("CrateStripe", Vector3.new(0.3, sy + 0.04, sz + 0.04), Vector3.new(cx + sx * 0.5 - 0.5, yb + sy * 0.5, cz), col.Accent, M.SmoothPlastic, false)
			else
				api.box("CrateStripe", Vector3.new(sx + 0.04, sy + 0.04, 0.3), Vector3.new(cx, yb + sy * 0.5, cz + sz * 0.5 - 0.5), col.Accent, M.SmoothPlastic, false)
			end
		end
		return c
	end

	-- wooden pallet with two crates (and one on top)
	local function pallet(cx: number, yb: number, cz: number, faces: { Enum.NormalId }, label: string, top: boolean)
		blk("Pallet", 4.2, 0.3, 2.6, cx, yb, cz, wood, M.WoodPlanks)
		crate(cx - 1.02, yb + 0.3, cz, 2.0, 1.3, 2.4, faces, label, false)
		crate(cx + 1.02, yb + 0.3, cz, 2.0, 1.3, 2.4, faces, label, false)
		if top then
			crate(cx, yb + 1.6, cz, 2.2, 1.2, 2.2, faces, label, true)
		end
	end

	-- wall rifle rack: steel backboard on the wall, stock tray, n rifles standing barrel-up
	-- wall: "E" | "W" | "B" | "F"; c = centre along the wall; yb = base height
	local function rack(wall: string, c: number, len: number, n: number, yb: number)
		local alongX = wall == "B" or wall == "F"
		local nx, nz, wx, wz = 0, 0, 0, 0
		if wall == "E" then
			nx, wx = -1, X1
		elseif wall == "W" then
			nx, wx = 1, X0
		elseif wall == "B" then
			nz, wz = 1, Z0
		else
			nz, wz = -1, Z1
		end
		local function at(d: number, t: number, y: number): Vector3
			if alongX then
				return Vector3.new(t, y, wz + nz * d)
			end
			return Vector3.new(wx + nx * d, y, t)
		end
		local function dims(depth: number, h: number, length: number): Vector3
			if alongX then
				return Vector3.new(length, h, depth)
			end
			return Vector3.new(depth, h, length)
		end
		api.box("RackBoard", dims(0.24, 5, len), at(0.12, c, yb + 2.5), col.Metal, M.Metal)
		api.box("RackTray", dims(0.6, 0.3, len), at(0.54, c, yb + 0.15), col.Dark, M.Metal)
		for i = 1, n do
			local t = c - len * 0.5 + len * (i - 0.5) / n
			api.box("Rifle", dims(0.5, 3.6, 0.18), at(0.55, t, yb + 0.3 + 1.8), col.Dark, M.Metal, false)
		end
	end

	-- ── Ground floor ─────────────────────────────────────────────────────────

	-- Door runner
	api.box("Runner", Vector3.new(3.4, 0.06, 5.6), Vector3.new(doorX, y1 + 0.03, Z1 - 3.0), col.Rug, M.Fabric, false)

	-- Caged arms-issue counter (back-east). Counter front z -4.4, bars at z -5.3, cage side at x 6.4.
	local cz = -5.0
	local barZ = -5.3
	local sideX = 6.4
	local hatchX = 9.5
	local yTop = y1 + 3.55
	local yHead = y1 + 9.2
	blk("IssueCounter", 2.05, 3.3, 1.2, 7.275, y1, cz, col.Dark, M.Metal)
	blk("IssueCounter", 3.5, 3.3, 1.2, 12.45, y1, cz, col.Dark, M.Metal)
	blk("CounterTop", 2.05, 0.25, 1.5, 7.275, y1 + 3.3, cz + 0.15, col.Metal, M.DiamondPlate)
	blk("CounterTop", 3.5, 0.25, 1.5, 12.45, y1 + 3.3, cz + 0.15, col.Metal, M.DiamondPlate)
	api.terminal("IssueTerminal", Vector3.new(hatchX, y1, cz), 0, "Shop", "Buy weapons", "Armory · Weapons", { "ARMS ISSUE", "WEAPONS · SHOP" })
	for _, px in ipairs({ sideX, 8.15, 10.85 }) do
		blk("CagePost", 0.3, yHead - yTop, 0.3, px, yTop, barZ, col.Metal, M.Metal)
	end
	for _, bx in ipairs({ 7.3, 11.65, 12.5, 13.35 }) do
		blk("CageBar", 0.12, yHead - yTop, 0.12, bx, yTop, barZ, col.Metal, M.Metal)
	end
	blk("CageHeader", X1 - 6.25, 0.3, 0.3, (6.25 + X1) * 0.5, yHead, barZ, col.Metal, M.Metal, false)
	-- cage side (floor to header), stops short of the back window band
	for _, bz in ipairs({ -6.3, -7.2, -8.1, -8.95 }) do
		blk("CageBar", 0.12, yHead - y1, 0.12, sideX, y1, bz, col.Metal, M.Metal)
	end
	blk("CageRail", 0.16, 0.2, 3.4, sideX, y1 + 3.35, -7.3, col.Metal, M.Metal)
	local issueSign = blk("IssueSign", 2.3, 1.1, 0.15, hatchX, yHead - 1.15, barZ, col.Dark, M.Metal, false)
	api.surfaceText(issueSign, N.Back, { "ARMS ISSUE" }, col.Accent, col.Dark, Enum.Font.GothamBlack)
	api.box("WaitLine", Vector3.new(X1 - 6.25, 0.04, 0.3), Vector3.new((6.25 + X1) * 0.5, y1 + 0.02, -3.6), col.Accent, M.SmoothPlastic, false)

	-- Behind the bars: rifle racks on the cage walls, sidearm cabinet under the back window
	rack("E", -7.7, 3.6, 5, y1 + 0.2)
	if lv >= 2 then
		rack("B", 12.0, 2.8, 4, y1 + 0.2)
	end
	local cabinet = blk("SidearmCabinet", 3.2, 3.0, 1.0, 8.5, y1, Z0 + 0.55, col.Locker, M.Metal)
	stencil(cabinet, N.Back, "SIDEARMS", false)
	if lv >= 3 then
		crate(9.8, y1, -7.5, 3.0, 1.1, 1.3, { N.Back }, "RIFLES", true)
	end

	-- Squad loadout bay (west wall): Army terminal between kit lockers, loadout board above it
	local bayZ = 5.6
	api.terminal("LoadoutTerminal", Vector3.new(X0 + 0.6, y1, bayZ), 90, "Army", "Equip squad", "Squad loadouts", { "SQUAD LOADOUTS", "EQUIP · ARMY" })
	local board = api.box("LoadoutBoard", Vector3.new(0.15, 2.6, 2.6), Vector3.new(X0 + 0.075, y1 + 6.9, bayZ), col.Dark, M.Metal, false)
	api.surfaceText(board, N.Right, { "SQUAD LOADOUTS", "ALPHA · RIFLES", "BRAVO · SUPPORT", "ARMORY LVL " .. tostring(lv) }, col.Screen, screenBg, Enum.Font.Code)
	local lockerZ = { 3.4, 7.7 }
	if lv >= 2 then
		table.insert(lockerZ, 9.1)
	end
	local squads = { "ALPHA", "BRAVO", "CHARLIE" }
	for i, lz in ipairs(lockerZ) do
		local locker = blk("KitLocker", 1.4, 7, 1.4, X0 + 0.7, y1, lz, col.Locker, M.Metal)
		stencil(locker, N.Right, squads[i], false, 0.1, 0.08)
	end

	-- Gunsmith workbench on the front pier west of the door
	local wbX = 2.15
	blk("WorkbenchBase", 4.6, 2.75, 1.6, wbX, y1, Z1 - 0.85, col.Dark, M.Metal)
	blk("Workbench", 4.9, 0.3, 1.9, wbX, y1 + 2.75, Z1 - 1.0, wood, M.WoodPlanks)
	local wbY = y1 + 3.05
	blk("ViceBase", 0.7, 0.3, 0.7, wbX - 1.8, wbY, Z1 - 1.5, col.Metal, M.Metal, false)
	blk("ViceJaw", 1.0, 0.5, 0.3, wbX - 1.8, wbY + 0.3, Z1 - 1.6, col.Dark, M.Metal, false)
	api.part("RifleOnBench", Vector3.new(2.8, 0.22, 0.45), CFrame.new(wbX + 0.4, wbY + 0.11, Z1 - 1.1) * CFrame.Angles(0, math.rad(12), 0), col.Dark, M.Metal, false)
	local toolBoard = blk("ToolBoard", 4.4, 3.0, 0.12, wbX, y1 + 3.5, Z1 - 0.06, col.Metal, M.Metal, false)
	api.light(toolBoard, 10, 0.5, col.Light)
	if lv >= 2 then
		blk("Tool", 0.22, 1.4, 0.08, wbX - 1.4, y1 + 4.3, Z1 - 0.16, col.Dark, M.Metal, false)
		blk("Tool", 1.3, 0.3, 0.08, wbX + 1.0, y1 + 5.6, Z1 - 0.16, col.Dark, M.Metal, false)
	end
	api.part("Stool", Vector3.new(1.9, 1.2, 1.2), CFrame.new(wbX + 0.2, y1 + 0.95, Z1 - 3.0) * CFrame.Angles(0, 0, math.rad(90)), col.Dark, M.Metal).Shape = Enum.PartType.Cylinder

	-- Ammo crates, kept low under the windows
	crate(-4.0, y1, Z1 - 0.75, 2.0, 1.3, 1.3, { N.Front }, "5.56 MM", false)
	crate(-1.85, y1, Z1 - 0.75, 2.0, 1.3, 1.3, { N.Front }, "5.56 MM", false)
	if lv >= 2 then
		crate(-2.9, y1 + 1.3, Z1 - 0.75, 2.0, 1.2, 1.3, { N.Front }, "7.62 MM", true)
		crate(-11.0, y1, Z1 - 0.75, 2.0, 1.3, 1.3, { N.Front }, "7.62 MM", false)
		crate(-8.85, y1, Z1 - 0.75, 2.0, 1.3, 1.3, { N.Front }, "7.62 MM", false)
	end
	crate(X1 - 0.7, y1, -1.0, 1.3, 1.3, 2.0, { N.Left }, "40 MM", false)
	crate(X1 - 0.7, y1, 1.1, 1.3, 1.3, 2.0, { N.Left }, "40 MM", false)
	if lv >= 3 then
		crate(X1 - 0.7, y1 + 1.3, 0.05, 1.3, 1.2, 2.0, { N.Left }, "GRENADES", false)
	end

	-- Back-west ammo store (single storey only — the stairs take this strip from L4)
	if not ictx.TwoStory then
		pallet(-9.2, y1, -8.6, { N.Back }, "7.62 MM", lv >= 2)
		if lv >= 2 then
			pallet(-2.6, y1, -8.6, { N.Back }, "5.56 MM", lv >= 3)
		end
	end

	-- Rifle-cleaning table in the middle (second rifle from L2); L3+ rifle rack on the pier between the windows
	blk("CleaningTable", 4.4, 2.8, 1.6, -5.0, y1, 0.8, col.Dark, M.Metal)
	blk("CleaningMat", 4.8, 0.2, 2.0, -5.0, y1 + 2.8, 0.8, col.Rug, M.Fabric)
	api.part("RifleLaid", Vector3.new(3.0, 0.22, 0.5), CFrame.new(-5.5, y1 + 3.11, 0.4) * CFrame.Angles(0, math.rad(6), 0), col.Dark, M.Metal, false)
	if lv >= 2 then
		api.part("RifleLaid", Vector3.new(3.0, 0.22, 0.5), CFrame.new(-4.4, y1 + 3.11, 1.3) * CFrame.Angles(0, math.rad(-8), 0), col.Dark, M.Metal, false)
	end
	if lv >= 3 then
		rack("F", -6.5, 2.2, 3, y1 + 0.2)
	end

	-- ── Upper floor (L4+): ammo storage + test-fire lane ────────────────────
	if ictx.TwoStory then
		local y2: number = ictx.Y2

		-- steel shelving row running along Z with crates / ammo cans on the shelves
		local function shelving(cx: number, z0: number, z1: number, faces: { Enum.NormalId }, loads: { { number } })
			local len = z1 - z0
			local mid = (z0 + z1) * 0.5
			for _, ez in ipairs({ z0 + 0.1, z1 - 0.1 }) do
				api.box("ShelfFrame", Vector3.new(1.3, 6.2, 0.2), Vector3.new(cx, y2 + 3.1, ez), col.Metal, M.Metal)
			end
			-- two shelves; the bottom tier stands on the floor between the frames (pallet-rack style)
			for _, sy in ipairs({ 2.3, 4.3 }) do
				api.box("Shelf", Vector3.new(1.3, 0.15, len - 0.4), Vector3.new(cx, y2 + sy, mid), col.Metal, M.DiamondPlate)
			end
			-- load = { tier 1..3 (1 = floor), z offset from the middle, length, height }
			for _, ld in ipairs(loads) do
				local sy = if ld[1] == 1 then 0 else 0.375 + (ld[1] - 1) * 2
				crate(cx, y2 + sy, mid + ld[2], 1.1, ld[4], ld[3], faces, if ld[1] == 2 then "5.56 MM" else "7.62 MM", false)
			end
		end

		-- Test-fire lane down the east side
		local laneX = (10.3 + X1) * 0.5
		local baffle = blk("LaneBaffle", 0.3, 3.0, 13.95, 10.15, y2, -3.175, col.Stair, M.Concrete)
		stencil(baffle, N.Left, "TEST-FIRE LANE  ·  EYES & EARS", true, 0.38, 0.3)
		api.box("LaneMat", Vector3.new(3.8, 0.05, 13.4), Vector3.new(laneX, y2 + 0.025, -3.4), col.Dark, M.Fabric, false)
		api.box("FiringLine", Vector3.new(3.85, 0.06, 0.3), Vector3.new(laneX, y2 + 0.03, 3.9), col.Accent, M.SmoothPlastic, false)
		blk("ShootingBench", 3.4, 2.6, 1.4, laneX, y2, 4.8, wood, M.WoodPlanks)
		api.box("RangeRifle", Vector3.new(0.45, 0.22, 2.8), Vector3.new(laneX - 0.3, y2 + 2.71, 4.4), col.Dark, M.Metal, false)
		api.part("Backstop", Vector3.new(3.8, 5.2, 0.3), CFrame.new(laneX, y2 + 2.45, -8.9) * CFrame.Angles(math.rad(-25), 0, 0), col.Metal, M.DiamondPlate)
		blk("TargetPost", 0.25, 2.3, 0.25, laneX, y2, -6.6, col.Metal, M.Metal, false)
		local target = api.box("TargetPlate", Vector3.new(1.8, 2.4, 0.15), Vector3.new(laneX, y2 + 3.5, -6.6), paper, M.SmoothPlastic, false)
		do
			local sg = Instance.new("SurfaceGui")
			sg.Name = "WE_Target"
			sg.Face = N.Back
			sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			sg.PixelsPerStud = 40
			sg.Parent = target
			for i, s in ipairs({ 0.86, 0.66, 0.46, 0.26, 0.1 }) do
				local ring = Instance.new("Frame")
				ring.AnchorPoint = Vector2.new(0.5, 0.5)
				ring.Position = UDim2.fromScale(0.5, 0.42)
				ring.Size = UDim2.fromScale(s, s)
				ring.SizeConstraint = Enum.SizeConstraint.RelativeXX
				ring.BackgroundColor3 = if i % 2 == 1 then col.Dark else paper
				ring.BorderSizePixel = 0
				ring.ZIndex = i
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0.5, 0)
				corner.Parent = ring
				ring.Parent = sg
			end
		end
		api.terminal("RangeTerminal", Vector3.new(X1 - 0.6, y2, 7.8), -90, "Missions", "Open missions", "Firing range · Missions", { "RANGE CONTROL", "DRILLS · MISSIONS" })

		-- Ammo storage on the west side: wall shelving + a freestanding row (third row at L5), pallets
		shelving(X0 + 0.65, 3.0, 9.6, { N.Right }, { { 1, -1.6, 2.4, 1.3 }, { 1, 1.4, 2.4, 1.3 }, { 2, 0, 1.8, 1.1 } })
		shelving(-8.5, -3.8, 3.4, { N.Left, N.Right }, { { 1, -1.6, 2.6, 1.3 }, { 2, 0.6, 2.0, 1.1 }, { 3, -1.4, 1.8, 1.0 } })
		if lv >= 5 then
			shelving(-3.5, -3.8, 3.4, { N.Left, N.Right }, { { 1, 0, 3.0, 1.3 }, { 2, -1.5, 2.0, 1.1 }, { 3, 0.8, 1.8, 1.0 } })
		end
		pallet(0.2, y2, 7.2, { N.Front, N.Left }, "7.62 MM", true)
	end
end
