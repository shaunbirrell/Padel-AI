--!strict
--[[
	Barracks interior (HollowBuildingBuilder). Where the player's soldiers live and are recruited.

	Ground floor: an open squad bay on the west side — two columns of steel bunks (heads to the west wall and to
	the bay's east edge, open foot posts) with numbered footlockers at their feet, wall lockers between the bunks
	and a runner down the centre aisle (4 bunks at L1, 6 from L2). East side: the recruitment desk facing the door
	(Army terminal, recruiter's chair, flag from L2), a "new recruits" bench by the doorway, the duty-roster /
	training terminal on the east wall under the roster board (Missions), and a mess table with benches in the
	back-east corner (rifle rack from L2).
	Upper floor (two storeys from L3): a second bunk room (2 bunks, 3 from L4) with a locker, the PT corner, kit
	shelves on the front wall, a washroom behind partitions in the back-east corner, and the officer's office in
	the front-east corner behind a half-height partition (desk whose top opens the Army panel, armchair, sector
	map; filing cabinet + flag from L4, rug from L5). L4/L5 also restencil the bay plate (gold at L5).

	Layout (building-local, +Z = front/door, door at X = 10): stairs run along the back wall from L3
	(X -15.2..5, Z -11.2..-5.7), so the bay stops at z = 0 and a cross aisle leads to the stair foot. At L1–L2
	that strip is the PT corner with a kit shelf and crates (it moves upstairs at L3). Tall items stay out of the
	window bands (4.4..7.6 above the floor, 1.2 studs in front of each pane); walkways are >= 2.8 studs.
]]

return function(ictx: any, api: any)
	local col = ictx.Colors
	local lv: number = ictx.Level
	local y1 = ictx.Y1
	local X0, X1, Z0, Z1 = ictx.InX0, ictx.InX1, ictx.InZ0, ictx.InZ1

	local pillowCol = Color3.fromRGB(206, 200, 182)
	local boardBg = Color3.fromRGB(18, 24, 20)

	local KIT_LINES = { "KIT", "[#] [#]", "-------", "[#][#][#]", "-------", "[#] [#]", "-------" }
	local BUNK_L = 5.2 -- along X
	local BUNK_W = 2.5 -- along Z

	-- Steel bunk bed running along X from xHead (dir = +1 → foot toward +X, -1 → toward -X): solid head frame,
	-- open foot posts (you can see the made-up bunks from the aisle), footlocker at the foot.
	local bunkNo = 0
	local function bunk(xHead: number, z: number, dir: number, y: number)
		bunkNo += 1
		local xFoot = xHead + dir * BUNK_L
		api.box("BunkHead", Vector3.new(0.3, 6.2, BUNK_W), Vector3.new(xHead + dir * 0.15, y + 3.1, z), col.Metal, Enum.Material.Metal)
		for _, s in ipairs({ -1, 1 }) do
			api.box("BunkPost", Vector3.new(0.3, 6.2, 0.3), Vector3.new(xFoot - dir * 0.15, y + 3.1, z + s * (BUNK_W * 0.5 - 0.15)), col.Metal, Enum.Material.Metal, false)
		end
		local mx = xHead + dir * (0.3 + (BUNK_L - 0.3) * 0.5)
		for _, dy in ipairs({ 1.3, 4.4 }) do
			api.box("BunkMattress", Vector3.new(BUNK_L - 0.3, 0.6, BUNK_W - 0.1), Vector3.new(mx, y + dy, z), col.Rug, Enum.Material.Fabric)
		end
		api.box("BunkPillow", Vector3.new(0.9, 0.25, BUNK_W - 0.7), Vector3.new(xHead + dir * 0.85, y + 4.4 + 0.43, z), pillowCol, Enum.Material.Fabric, false)
		local fl = api.box("Footlocker", Vector3.new(1.0, 1.0, 2.1), Vector3.new(xFoot + dir * 0.6, y + 0.5, z), col.Trim, Enum.Material.Wood)
		api.surfaceText(fl, if dir > 0 then Enum.NormalId.Right else Enum.NormalId.Left, { string.format("B-%02d", bunkNo) }, col.Accent, col.Trim, Enum.Font.Code)
	end

	-- Tall wall locker; its door (vents + name tag) faces faceDir (+1 → +X, -1 → -X)
	local function locker(x: number, z: number, faceDir: number, y: number)
		local l = api.box("GearLocker", Vector3.new(1.4, 7, 1.2), Vector3.new(x, y + 3.5, z), col.Locker, Enum.Material.Metal)
		api.surfaceText(l, if faceDir > 0 then Enum.NormalId.Right else Enum.NormalId.Left, { "=====", "=====", "", "", "", "", "", "", "", "", "SQD 1" }, col.Dark, col.Locker, Enum.Font.Code)
	end

	-- ── Ground floor: squad bay ──────────────────────────────────────────────
	local westHead = X0 + 1.0 -- 1 stud off the west wall (clear of the window panes)
	local eastHead = 1.4
	local rows = { 8.9, 5.1 }
	if lv >= 2 then
		table.insert(rows, 1.3)
	end
	for _, z in ipairs(rows) do
		bunk(westHead, z, 1, y1)
		bunk(eastHead, z, -1, y1)
	end
	for i = 1, #rows - 1 do
		local lz = (rows[i] + rows[i + 1]) * 0.5
		locker(westHead + 0.7, lz, 1, y1)
		locker(eastHead - 0.7, lz, -1, y1)
	end
	-- centre-aisle runner (between the footlockers)
	local aisleX = ((westHead + BUNK_L + 1.1) + (eastHead - BUNK_L - 1.1)) * 0.5
	local lastRow = rows[#rows]
	local runZ0, runZ1 = lastRow - 2.4, 10.2
	api.box("AisleRunner", Vector3.new(2.4, 0.06, runZ1 - runZ0), Vector3.new(aisleX, y1 + 0.03, (runZ0 + runZ1) * 0.5), col.Rug, Enum.Material.Fabric, false)
	-- bay stencil on the west wall between the windows
	local bayPlate = api.box("BayPlate", Vector3.new(0.1, 1.4, 5.6), Vector3.new(X0 + 0.05, y1 + 8.6, 0), col.Dark, Enum.Material.Metal, false)
	api.surfaceText(
		bayPlate,
		Enum.NormalId.Right,
		{ if lv >= 4 then "1ST BATTALION · SQUAD BAY" else "1ST PLATOON · SQUAD BAY" },
		if lv >= 5 then col.Gold else col.Accent,
		col.Dark,
		Enum.Font.GothamBlack
	)

	-- ── Recruitment desk (faces the door) → Army ─────────────────────────────
	local deskZ = -1.2
	api.terminal("RecruitTerminal", Vector3.new(9.4, y1, deskZ), 0, "Army", "Recruit soldiers", "Recruitment", { "RECRUITMENT", "ENLIST · TRAIN" })
	local desk = api.box("RecruitDesk", Vector3.new(3.0, 2.6, 1.4), Vector3.new(6.4, y1 + 1.3, deskZ - 0.1), col.Locker, Enum.Material.Metal)
	api.surfaceText(desk, Enum.NormalId.Back, { "", "RECRUITMENT", "" }, if lv >= 5 then col.Gold else col.Accent, col.Locker, Enum.Font.GothamBlack)
	api.box("RecruitDeskTop", Vector3.new(3.3, 0.25, 1.7), Vector3.new(6.4, y1 + 2.72, deskZ - 0.1), col.Dark, Enum.Material.Metal)
	api.chair(Vector3.new(6.4, y1, deskZ - 2.0), Vector3.new(0, 0, 1))
	if lv >= 2 then
		api.box("FlagPole", Vector3.new(0.2, 7.4, 0.2), Vector3.new(3.8, y1 + 3.7, deskZ - 1.8), col.Metal, Enum.Material.Metal, false)
		-- fb2: flag cloths are 0.12 thick and tagged WE_FlagHost (the nation flag binds to their Front / Back faces)
		local cloth = api.box("FlagCloth", Vector3.new(2.6, 1.7, 0.12), Vector3.new(3.8 + 1.4, y1 + 6.4, deskZ - 1.8), col.Flag, Enum.Material.Fabric, false)
		cloth:SetAttribute("WE_FlagHost", true)
	end

	-- ── Duty roster / training terminal on the east wall → Missions ─────────
	local rosterZ = 1.4
	api.terminal("RosterTerminal", Vector3.new(X1 - 0.6, y1, rosterZ), -90, "Missions", "Check duty roster", "Duty Roster · Training", { "DUTY ROSTER", "TRAINING" })
	local board = api.box("RosterBoard", Vector3.new(0.12, 3.2, 5.4), Vector3.new(X1 - 0.06, y1 + 6.6, rosterZ - 0.5), col.Dark, Enum.Material.Metal, false)
	api.surfaceText(board, Enum.NormalId.Left, { "DUTY ROSTER", "0600  PT · DRILL", "0900  RANGE", "1400  PATROL", "2200  LIGHTS OUT" }, col.Screen, boardBg, Enum.Font.Code)

	-- ── Mess table + benches (back-east) ─────────────────────────────────────
	local messX, messZ = 10.5, -7.6
	api.box("MessTable", Vector3.new(6.0, 0.25, 2.2), Vector3.new(messX, y1 + 2.6, messZ), col.Trim, Enum.Material.WoodPlanks)
	api.box("MessTrestle", Vector3.new(4.8, 2.47, 0.4), Vector3.new(messX, y1 + 1.235, messZ), col.Metal, Enum.Material.Metal, false)
	for _, bz in ipairs({ -1.95, 1.95 }) do
		api.box("MessBench", Vector3.new(6.0, 0.3, 0.9), Vector3.new(messX, y1 + 1.55, messZ + bz), col.Trim, Enum.Material.WoodPlanks)
		api.box("MessBenchLeg", Vector3.new(4.6, 1.4, 0.2), Vector3.new(messX, y1 + 0.7, messZ + bz), col.Metal, Enum.Material.Metal, false)
	end

	-- Rifle rack on the east wall (back corner) from L2
	if lv >= 2 then
		api.box("RifleRack", Vector3.new(0.6, 4.2, 2.4), Vector3.new(X1 - 0.3, y1 + 2.1, Z0 + 1.6), col.Dark, Enum.Material.Metal)
		for i = 0, 1 do
			api.box("RackRifle", Vector3.new(0.25, 3.2, 0.25), Vector3.new(X1 - 0.75, y1 + 2.2, Z0 + 1.1 + i * 1.0), col.Metal, Enum.Material.Metal, false)
		end
	end

	-- Recruit intake: a storage bench along the bay edge, west of the doorway
	local bench = api.box("RecruitBench", Vector3.new(1.0, 1.6, 4.6), Vector3.new(eastHead + 0.75, y1 + 0.8, 6.9), col.Trim, Enum.Material.WoodPlanks)
	api.surfaceText(bench, Enum.NormalId.Right, { "NEW RECRUITS · WAIT HERE" }, col.Accent, col.Trim, Enum.Font.Code)

	-- PT corner + kit shelves along the back wall until the stairs go in (L1–L2)
	if not ictx.TwoStory then
		api.box("PTMat", Vector3.new(8.0, 0.1, 4.4), Vector3.new(-6.0, y1 + 0.05, -6.6), Color3.fromRGB(40, 44, 40), Enum.Material.SmoothPlastic, false)
		for _, px in ipairs({ -8.0, -4.0 }) do
			api.box("PullUpPost", Vector3.new(0.3, 7.0, 0.3), Vector3.new(px, y1 + 3.5, -8.2), col.Metal, Enum.Material.Metal)
		end
		api.box("PullUpBar", Vector3.new(3.7, 0.2, 0.2), Vector3.new(-6.0, y1 + 6.8, -8.2), col.Metal, Enum.Material.Metal, false)
		api.box("WeightBench", Vector3.new(3.4, 1.1, 1.2), Vector3.new(-6.0, y1 + 0.55, -5.4), col.Dark, Enum.Material.Fabric)
		local ks = api.box("KitShelf", Vector3.new(2.6, 7.0, 1.2), Vector3.new(X0 + 1.5, y1 + 3.5, Z0 + 0.6), col.Locker, Enum.Material.Metal)
		api.surfaceText(ks, Enum.NormalId.Back, KIT_LINES, col.Dark, col.Locker, Enum.Font.Code)
		api.box("SupplyCrate", Vector3.new(2.2, 1.6, 1.8), Vector3.new(4.0, y1 + 0.8, Z0 + 1.1), col.Trim, Enum.Material.WoodPlanks)
		api.box("SupplyCrate", Vector3.new(1.8, 1.4, 1.6), Vector3.new(4.0, y1 + 2.3, Z0 + 1.1), col.Trim, Enum.Material.WoodPlanks)
	end

	-- ── Upper floor (L3+) ───────────────────────────────────────────────────
	if ictx.TwoStory then
		local y2 = ictx.Y2
		bunk(westHead, 8.9, 1, y2)
		bunk(eastHead, 8.9, -1, y2)
		locker(westHead + 0.7, 7.0, 1, y2)
		if lv >= 4 then
			bunk(westHead, 5.1, 1, y2)
		end
		-- PT corner (moved up from the ground floor when the stairs went in)
		api.box("PTMat", Vector3.new(8.0, 0.1, 4.4), Vector3.new(-9.0, y2 + 0.05, -3.4), Color3.fromRGB(40, 44, 40), Enum.Material.SmoothPlastic, false)
		api.box("WeightBench", Vector3.new(1.2, 1.1, 3.4), Vector3.new(-9.0, y2 + 0.55, -3.4), col.Dark, Enum.Material.Fabric)

		-- Kit shelves on the front wall between the windows
		local ks = api.box("KitShelf", Vector3.new(2.4, 7.0, 1.2), Vector3.new(6.5, y2 + 3.5, Z1 - 0.6), col.Locker, Enum.Material.Metal)
		api.surfaceText(ks, Enum.NormalId.Front, KIT_LINES, col.Dark, col.Locker, Enum.Font.Code)

		-- Washroom behind a partition in the back-east corner
		api.box("WashPartition", Vector3.new(0.3, 7.0, 2.8), Vector3.new(9.0, y2 + 3.5, -8.8), col.Wall, Enum.Material.Concrete)
		local wp = api.box("WashPartition", Vector3.new(3.6, 7.0, 0.3), Vector3.new(X1 - 1.8, y2 + 3.5, -4.9), col.Wall, Enum.Material.Concrete)
		api.surfaceText(wp, Enum.NormalId.Back, { "WASHROOM" }, col.Dark, col.Wall, Enum.Font.GothamBlack)
		api.box("SinkCounter", Vector3.new(1.4, 2.8, 4.4), Vector3.new(X1 - 0.7, y2 + 1.4, -8.4), col.Metal, Enum.Material.Metal)
		local mirror = api.box("Mirror", Vector3.new(0.1, 1.8, 3.8), Vector3.new(X1 - 0.05, y2 + 4.6, -8.4), col.Glass, Enum.Material.Glass, false)
		mirror.Reflectance = 0.3

		-- Officer's desk (front-east corner); the desk top opens the Army panel
		local odX, odZ = 9.8, 6.0
		api.box("OfficerDesk", Vector3.new(1.4, 2.6, 3.6), Vector3.new(odX, y2 + 1.3, odZ), col.Trim, Enum.Material.Wood)
		local odTop = api.box("OfficerDeskTop", Vector3.new(1.8, 0.25, 4.0), Vector3.new(odX, y2 + 2.72, odZ), col.Dark, Enum.Material.Wood)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "WE_PanelPrompt"
		prompt.ActionText = "Review troops"
		prompt.ObjectText = "Officer's Desk"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12 -- mobile P1-19 (was 8)
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.F
		prompt:SetAttribute("WE_OpenPanel", "Army")
		prompt.Parent = odTop
		-- officer's armchair (upholstered base + high back), facing the room
		api.box("OfficerChair", Vector3.new(1.6, 1.8, 1.6), Vector3.new(odX + 1.9, y2 + 0.9, odZ), col.Dark, Enum.Material.Fabric)
		api.box("OfficerChairBack", Vector3.new(0.35, 2.2, 1.6), Vector3.new(odX + 2.55, y2 + 2.9, odZ), col.Dark, Enum.Material.Fabric, false)
		-- half-height wood partition closing the office off from the landing hall (open on its west end)
		local partX0 = 4.2
		local part = api.box("OfficePartition", Vector3.new(X1 - partX0, 3.0, 0.3), Vector3.new((X1 + partX0) * 0.5, y2 + 1.5, 1.4), col.Trim, Enum.Material.Wood)
		api.surfaceText(part, Enum.NormalId.Front, { "", "OFFICER COMMANDING", "" }, col.Accent, col.Trim, Enum.Font.GothamBlack)
		local map = api.box("MapBoard", Vector3.new(0.12, 3.4, 5.6), Vector3.new(X1 - 0.06, y2 + 5.0, odZ), col.Dark, Enum.Material.Metal, false)
		api.surfaceText(map, Enum.NormalId.Left, { "SECTOR MAP", "◆ HQ    ◇ OUTPOST", "ALL SQUADS READY" }, col.Accent, Color3.fromRGB(46, 58, 40), Enum.Font.GothamBold)
		if lv >= 4 then
			api.box("FilingCabinet", Vector3.new(1.4, 3.8, 1.3), Vector3.new(X1 - 0.8, y2 + 1.9, Z1 - 0.8), col.Metal, Enum.Material.Metal)
			-- flag in the office corner by the partition, cloth hanging toward the room (clear of the map)
			api.box("OfficerFlagPole", Vector3.new(0.2, 7.2, 0.2), Vector3.new(X1 - 1.6, y2 + 3.6, 2.2), col.Metal, Enum.Material.Metal, false)
			-- fb2: 0.12 thick + WE_FlagHost (nation flag on the Front / Back faces)
			local officerFlag = api.box("OfficerFlag", Vector3.new(2.4, 1.7, 0.12), Vector3.new(X1 - 1.6 - 1.3, y2 + 6.2, 2.2), col.Flag, Enum.Material.Fabric, false)
			officerFlag:SetAttribute("WE_FlagHost", true)
		end
		if lv >= 5 then
			api.box("OfficerRug", Vector3.new(5.0, 0.06, 6.0), Vector3.new(odX + 0.8, y2 + 0.03, odZ), col.Rug, Enum.Material.Fabric, false)
		end
	end
end
