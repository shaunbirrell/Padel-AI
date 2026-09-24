--!strict
--[[
	Research Lab interior (HollowBuildingBuilder). Four research terminals open the Research panel
	(ResearchController) on their own tab via the prompt attribute WE_OpenTab.

	Ground floor (30 x 22, door X 6..12 on the front wall, console at (12.5, 7)):
	  • Lobby: door runner only; the main aisle Z -4.5..-1.0 runs the width of the room and stays empty
	    (from L3 it leads to the foot of the stairs at the west end).
	  • Weapons bay (east): Weapons terminal between the east windows under a BALLISTICS sign, a ballistics bench
	    (rifle in a test vise, two chronograph units, gel block) firing into a steel bullet trap with an angled
	    deflector plate in the back-east corner. Ammo crates from L2, a rack of prototype rifles from L4.
	  • Bio-armor clean room (front-west): glass partitions on metal kick plates with a hazard-striped door and a
	    BIO-ARMOR LAB sign; armour mannequin on a plinth, laminar-flow bench, sample fridge, Soldiers terminal.
	  • Prototype test stand (front-middle): plinth with a hazard ring and stanchions, a rail-cannon turret that
	    turns slowly (client spinner), TEST IN PROGRESS sign; a quad-rotor drone hangs above it from L4.
	  • Back strip (L1-L2 only; the stairs take it from L3): server racks between the back windows, cryo freezer,
	    data desk.
	Upper floor (L3+):
	  • Server room (back-east): an L of racks with LEDs under a cable tray; the stair landing stays clear.
	  • Engineering wall (east): Vehicles and Defenses terminals under amber signs, a drafting table.
	  • Director's office (front-west) behind glass: desk, chair, bookshelf, plant; L5 adds a gold plaque and a
	    hologram globe.
	  • Analyst pool (middle): two back-to-back desk pairs with monitors, a whiteboard on the west wall.

	Lights: no ceiling fittings added here (the shell has them). At most two dim accents per level. Neon only for
	LEDs and the L5 globe. Screens are dark with green / amber text. Everything is deterministic.
]]

return function(ictx: any, api: any)
	local col = ictx.Colors
	local lv: number = ictx.Level
	local y1: number = ictx.Y1
	local X0: number, X1: number, Z0: number, Z1: number = ictx.InX0, ictx.InX1, ictx.InZ0, ictx.InZ1
	local M = Enum.Material
	local UP = CFrame.Angles(0, 0, math.pi * 0.5) -- cylinder axis (local X) → vertical
	local screenBg = Color3.fromRGB(8, 20, 12)
	local amber: Color3 = col.Accent
	local olive: Color3 = col.Locker
	local gunmetal = Color3.fromRGB(52, 58, 62)
	local labWhite = Color3.fromRGB(212, 216, 214)
	local woodCol = Color3.fromRGB(96, 70, 48)
	local ledPalette = { col.Screen, col.Screen, Color3.fromRGB(36, 56, 44), amber, col.Screen, Color3.fromRGB(36, 56, 44) }
	local bookPalette = {
		Color3.fromRGB(120, 40, 36),
		Color3.fromRGB(46, 70, 52),
		Color3.fromRGB(40, 52, 86),
		Color3.fromRGB(176, 150, 96),
		Color3.fromRGB(70, 60, 50),
		Color3.fromRGB(150, 110, 60),
	}

	local function cyl(name: string, length: number, dia: number, cf: CFrame, color: Color3, mat: Enum.Material, collide: boolean?): BasePart
		return api.cylinder(name, Vector3.new(length, dia, dia), cf, color, mat, collide)
	end

	local function glass(name: string, size: Vector3, pos: Vector3, collide: boolean): BasePart
		local g = api.box(name, size, pos, col.Glass, M.Glass, collide)
		g.Transparency = 0.55
		g.Reflectance = 0.04
		g.CastShadow = false
		return g
	end

	-- Stencilled text straight onto a surface (transparent background, lit like paint).
	local function paint(host: BasePart, face: Enum.NormalId, lines: { string }, color: Color3)
		api.surfaceText(host, face, lines, color, col.Dark, Enum.Font.GothamBlack)
		for _, g in ipairs(host:GetChildren()) do
			if g:IsA("SurfaceGui") and g.Face == face then
				g.LightInfluence = 1
				local fr = g:FindFirstChildOfClass("Frame")
				if fr then
					fr.BackgroundTransparency = 1
				end
			end
		end
	end

	-- Alternating bars across a face (hazard stripes).
	local function stripes(host: BasePart, face: Enum.NormalId, n: number, a: Color3, b: Color3)
		local sg = Instance.new("SurfaceGui")
		sg.Name = "WE_Stripes"
		sg.Face = face
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 20
		sg.LightInfluence = 1
		sg.MaxDistance = 40 -- v70: near-only (CLAUDE.md SurfaceGui budget)
		sg.Parent = host
		for i = 0, n - 1 do
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			f.Size = UDim2.fromScale(1 / n, 1)
			f.Position = UDim2.fromScale(i / n, 0)
			f.BackgroundColor3 = if i % 2 == 0 then a else b
			f.Parent = sg
		end
	end

	-- Rows of small coloured blocks painted on a face: book spines, drive-bay LEDs (GUI only, no parts).
	local function rows(host: BasePart, face: Enum.NormalId, nRows: number, perRow: number, palette: { Color3 }, bg: Color3, fill: number, glow: boolean)
		local sg = Instance.new("SurfaceGui")
		sg.Name = "WE_Rows"
		sg.Face = face
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 20
		sg.LightInfluence = if glow then 0 else 1
		sg.MaxDistance = 40 -- v70: near-only (CLAUDE.md SurfaceGui budget)
		sg.Parent = host
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = bg
		frame.BorderSizePixel = 0
		frame.Parent = sg
		for r = 0, nRows - 1 do
			for i = 0, perRow - 1 do
				local k = r * perRow + i
				local h = fill * (0.76 + (k * 7 % 4) * 0.08)
				local item = Instance.new("Frame")
				item.BorderSizePixel = 0
				item.BackgroundColor3 = palette[(k * 5 + r) % #palette + 1]
				item.Size = UDim2.fromScale(0.8 / perRow, h / nRows)
				item.Position = UDim2.fromScale((i + 0.1) / perRow, (r + 0.94 - h) / nRows)
				item.Parent = frame
			end
		end
	end

	-- Two-part seat (upholstered base + back); (fx, fz) = the way the sitter faces.
	local function seat(x: number, y: number, z: number, fx: number, fz: number)
		api.box("Seat", Vector3.new(1.3, 1.5, 1.3), Vector3.new(x, y + 0.75, z), col.Dark, M.Fabric)
		local backSize = if math.abs(fx) > 0.5 then Vector3.new(0.3, 1.9, 1.3) else Vector3.new(1.3, 1.9, 0.3)
		api.box("SeatBack", backSize, Vector3.new(x - fx * 0.5, y + 2.45, z - fz * 0.5), col.Dark, M.Fabric, false)
	end

	-- Research terminals open the Research panel on their own tab (prompt attribute WE_OpenTab).
	local function setTab(body: any, tab: string)
		local pr = if body then body:FindFirstChild("WE_PanelPrompt") else nil
		if pr then
			pr:SetAttribute("WE_OpenTab", tab)
		end
	end

	------------------------------------------------------------------------------------------------
	-- Lobby: runner from the door (the console stands just inside, east of it)
	------------------------------------------------------------------------------------------------
	api.box("Runner", Vector3.new(3.4, 0.06, 6.9), Vector3.new(ictx.DoorX, y1 + 0.03, Z1 - 3.5), col.Rug, M.Fabric, false)

	------------------------------------------------------------------------------------------------
	-- Weapons bay (east): terminal between the east windows, BALLISTICS sign above the window band
	------------------------------------------------------------------------------------------------
	setTab(api.terminal("WeaponsTerminal", Vector3.new(X1 - 0.6, y1, -0.5), -90, "Research", "Research weapons", "Weapons Research", { "WEAPONS R&D", "DAMAGE · RATE · MAGS" }), "Weapons")
	local bSign = api.box("BallisticsSign", Vector3.new(0.1, 1.2, 5.0), Vector3.new(X1 - 0.05, 8.8, -0.5), col.Dark, M.Metal, false)
	api.surfaceText(bSign, Enum.NormalId.Left, { "BALLISTICS" }, amber, col.Dark, Enum.Font.GothamBlack)

	-- Ballistics bench: rifle in a test vise → two chronograph units → gel block, aimed at the bullet trap
	local bx, bz = 9.0, -7.5
	api.box("BallisticsBench", Vector3.new(4.0, 2.9, 1.8), Vector3.new(bx, y1 + 1.45, bz), gunmetal, M.Metal)
	api.box("BenchTop", Vector3.new(4.2, 0.3, 2.0), Vector3.new(bx, y1 + 3.05, bz), col.Metal, M.DiamondPlate)
	local benchTop = y1 + 3.2
	api.box("TestVise", Vector3.new(0.7, 0.55, 0.7), Vector3.new(7.6, benchTop + 0.275, bz), col.Dark, M.Metal, false)
	api.box("TestRifle", Vector3.new(1.3, 0.4, 0.25), Vector3.new(7.75, benchTop + 0.75, bz), col.Dark, M.Metal, false)
	api.box("TestBarrel", Vector3.new(0.9, 0.14, 0.14), Vector3.new(8.85, benchTop + 0.82, bz), col.Metal, M.Metal, false)
	for i, gx in ipairs({ 9.7, 10.15 }) do
		local gate = api.box("ChronoGate", Vector3.new(0.12, 1.1, 1.0), Vector3.new(gx, benchTop + 0.55, bz), col.Dark, M.Metal, false)
		api.surfaceText(gate, Enum.NormalId.Right, { "V" .. tostring(i), if i == 1 then "912" else "907" }, col.Screen, screenBg, Enum.Font.Code)
	end
	local gel = api.box("GelBlock", Vector3.new(0.7, 0.6, 0.6), Vector3.new(10.65, benchTop + 0.3, bz), Color3.fromRGB(255, 140, 50), M.SmoothPlastic, false)
	gel.Transparency = 0.35

	-- Steel bullet trap (back-east corner) + angled deflector plate facing the bench
	local trapX0 = 12.6
	local trap = api.box("BulletTrap", Vector3.new(X1 - 0.05 - trapX0, 3.9, 3.85), Vector3.new((trapX0 + X1 - 0.05) * 0.5, y1 + 1.95, Z0 + 0.05 + 1.925), col.Dark, M.Metal)
	paint(trap, Enum.NormalId.Left, { "BULLET TRAP", "", "" }, amber)
	do
		local run, rise = 1.25, 2.5
		api.part(
			"TrapPlate",
			Vector3.new(math.sqrt(run * run + rise * rise), 0.2, 3.5),
			CFrame.new(trapX0 - run * 0.5, y1 + rise * 0.5 + 0.06, Z0 + 0.05 + 1.925) * CFrame.Angles(0, 0, math.atan2(rise, run)),
			col.Metal,
			M.DiamondPlate,
			false
		)
	end

	if lv >= 2 then
		local c1 = api.box("AmmoCrate", Vector3.new(1.25, 1.3, 1.6), Vector3.new(X1 - 0.675, y1 + 0.65, -5.3), olive, M.Wood)
		paint(c1, Enum.NormalId.Left, { "AMMO" }, amber)
		api.box("AmmoCrate", Vector3.new(1.1, 1.0, 1.3), Vector3.new(X1 - 0.65, y1 + 1.8, -5.35), olive, M.Wood)
	end
	if lv >= 4 then
		-- prototype rifles on a wall board between the terminal and the east window
		api.box("PrototypeRack", Vector3.new(0.2, 3.6, 1.7), Vector3.new(X1 - 0.1, y1 + 2.3, 1.75), col.Dark, M.Metal, false)
		for i = 0, 2 do
			api.box("PrototypeRifle", Vector3.new(0.25, 2.9, 0.22), Vector3.new(X1 - 0.35, y1 + 2.25, 1.2 + i * 0.55), if i == 1 then olive else gunmetal, M.Metal, false)
		end
	end

	------------------------------------------------------------------------------------------------
	-- Bio-armor clean room (front-west): X -14.15..-6.4, Z 1.5..10.15, glass on kick plates, door X -11.6..-8.0
	------------------------------------------------------------------------------------------------
	local crX0, crXE, crZ = X0 + 0.05, -6.4, 1.5
	local gapA, gapB = -11.6, -8.0
	local PH = 8.0 -- partition height (kick 0.8 + glass 6.8 + header 0.4)
	local function kickGlassAlongX(xa: number, xb: number)
		local cx = (xa + xb) * 0.5
		api.box("KickPlate", Vector3.new(xb - xa, 0.8, 0.25), Vector3.new(cx, y1 + 0.4, crZ), col.Metal, M.Metal)
		glass("GlassPartition", Vector3.new(xb - xa, PH - 1.2, 0.15), Vector3.new(cx, y1 + 0.8 + (PH - 1.2) * 0.5, crZ), true)
	end
	kickGlassAlongX(crX0, gapA)
	kickGlassAlongX(gapB, crXE - 0.15)
	do
		local za, zb = crZ + 0.15, Z1 - 0.05
		local cz = (za + zb) * 0.5
		api.box("KickPlate", Vector3.new(0.25, 0.8, zb - za), Vector3.new(crXE, y1 + 0.4, cz), col.Metal, M.Metal)
		glass("GlassPartition", Vector3.new(0.15, PH - 1.2, zb - za), Vector3.new(crXE, y1 + 0.8 + (PH - 1.2) * 0.5, cz), true)
		api.box("PartitionHeader", Vector3.new(0.3, 0.4, zb - za + 0.3), Vector3.new(crXE, y1 + PH - 0.2, cz - 0.15), col.Trim, M.Metal, false)
	end
	api.box("PartitionHeader", Vector3.new(crXE + 0.15 - crX0, 0.4, 0.3), Vector3.new((crX0 + crXE + 0.15) * 0.5, y1 + PH - 0.2, crZ), col.Trim, M.Metal, false)
	local bioSign = api.box("BioArmorSign", Vector3.new(gapB - gapA, 1.0, 0.2), Vector3.new((gapA + gapB) * 0.5, y1 + PH + 0.5, crZ), col.Dark, M.Metal, false)
	api.surfaceText(bioSign, Enum.NormalId.Front, { "BIO-ARMOR LAB" }, amber, col.Dark, Enum.Font.GothamBlack)
	local sill = api.box("HazardThreshold", Vector3.new(gapB - gapA, 0.05, 0.7), Vector3.new((gapA + gapB) * 0.5, y1 + 0.025, crZ), amber, M.SmoothPlastic, false)
	stripes(sill, Enum.NormalId.Top, 12, amber, col.Dark)

	-- Armour mannequin on a plinth, facing the lab (visible through the glass from the door)
	do
		local mx, mz = -10.4, 6.3
		cyl("MannequinPlinth", 0.5, 2.2, CFrame.new(mx, y1 + 0.25, mz) * UP, col.Metal, M.Metal, true)
		local base = y1 + 0.5
		api.box("MannequinLegs", Vector3.new(0.6, 2.6, 1.0), Vector3.new(mx, base + 1.3, mz), col.Dark, M.Fabric, false)
		api.box("MannequinTorso", Vector3.new(0.8, 1.9, 1.7), Vector3.new(mx, base + 3.55, mz), col.Rug, M.Fabric, false)
		api.box("PlateCarrier", Vector3.new(1.1, 1.4, 1.5), Vector3.new(mx, base + 3.45, mz), olive, M.Fabric, false)
		api.ball("ArmorHelmet", 1.15, Vector3.new(mx, base + 5.05, mz), olive, M.SmoothPlastic, false)
		local visor = api.box("HelmetVisor", Vector3.new(0.14, 0.38, 0.85), Vector3.new(mx + 0.52, base + 4.95, mz), amber, M.SmoothPlastic, false)
		visor.Transparency = 0.2
	end

	-- Laminar-flow bench against the east partition (clear of the front-window band)
	do
		local lx, lz = -7.3, 7.0
		api.box("LaminarCabinet", Vector3.new(1.3, 2.9, 3.2), Vector3.new(lx, y1 + 1.45, lz), labWhite, M.Metal)
		glass("LaminarSash", Vector3.new(1.3, 2.3, 3.0), Vector3.new(lx, y1 + 2.9 + 1.15, lz), false)
		local hood = api.box("LaminarHood", Vector3.new(1.3, 1.1, 3.2), Vector3.new(lx, y1 + 5.2 + 0.55, lz), labWhite, M.Metal, false)
		api.surfaceText(hood, Enum.NormalId.Left, { "LAMINAR FLOW" }, col.Screen, screenBg, Enum.Font.Code)
		api.light(hood, 8, 0.5, Color3.fromRGB(210, 232, 255)) -- accent 1/2 (ground floor)
	end

	-- Sample fridge in the front-west corner
	local fridge = api.box("SampleFridge", Vector3.new(1.5, 3.5, 1.5), Vector3.new(X0 + 0.8, y1 + 1.75, Z1 - 0.8), labWhite, M.Metal)
	api.surfaceText(fridge, Enum.NormalId.Right, { "BIO SAMPLES", "+4 C" }, col.Screen, screenBg, Enum.Font.Code)

	setTab(api.terminal("SoldierTerminal", Vector3.new(-7.3, y1, 3.6), -90, "Research", "Research soldiers", "Soldier Research", { "SOLDIER R&D", "ARMOR · TRAINING" }), "Soldiers")

	------------------------------------------------------------------------------------------------
	-- Prototype test stand (front-middle): plinth, hazard ring, stanchions, turning rail-cannon turret
	------------------------------------------------------------------------------------------------
	local sx, sz = -0.5, 5.0
	cyl("HazardRing", 0.06, 6.3, CFrame.new(sx, y1 + 0.03, sz) * UP, amber, M.SmoothPlastic, false)
	cyl("TestPlinth", 1.0, 5.5, CFrame.new(sx, y1 + 0.5, sz) * UP, col.Metal, M.Concrete, true)
	for _, ox in ipairs({ -1, 1 }) do
		for _, oz in ipairs({ -1, 1 }) do
			api.box("Stanchion", Vector3.new(0.25, 2.6, 0.25), Vector3.new(sx + ox * 2.45, y1 + 1.3, sz + oz * 2.45), amber, M.SmoothPlastic, false)
		end
	end
	do
		local pivot = Vector3.new(sx, y1 + 1.0, sz)
		local aim = CFrame.lookAt(pivot, pivot + Vector3.new(9.5, 0, 5)) -- muzzle (-Z) toward the doorway
		local gun: { BasePart } = {}
		table.insert(gun, cyl("TurretRing", 0.4, 3.6, aim * CFrame.new(0, 0.2, 0) * UP, gunmetal, M.Metal, false))
		table.insert(gun, api.part("TurretHousing", Vector3.new(2.2, 1.6, 2.4), aim * CFrame.new(0, 1.2, 0.4), gunmetal, M.Metal, false))
		table.insert(gun, api.part("TurretPlates", Vector3.new(2.6, 1.0, 1.8), aim * CFrame.new(0, 1.2, 0.3), olive, M.Metal, false))
		for _, s in ipairs({ -1, 1 }) do
			table.insert(gun, api.part("RailBarrel", Vector3.new(0.28, 0.34, 4.4), aim * CFrame.new(s * 0.34, 1.45, -2.3), gunmetal, M.Metal, false))
		end
		table.insert(gun, cyl("RailCoil", 0.8, 1.2, aim * CFrame.new(0, 1.45, -1.5) * CFrame.Angles(0, math.pi * 0.5, 0), amber, M.Metal, false))
		api.spin(gun, pivot, 3)
	end
	local testSign = api.box("TestSign", Vector3.new(0.15, 1.5, 2.0), Vector3.new(3.4, y1 + 0.75, 7.6), amber, M.SmoothPlastic, false)
	api.surfaceText(testSign, Enum.NormalId.Right, { "TEST IN", "PROGRESS" }, col.Dark, amber, Enum.Font.GothamBlack)

	if lv >= 4 then
		-- quad-rotor drone on two cables above the stand (clear of the ceiling lamps)
		local dxc, dzc, dy = sx, sz + 0.6, 9.3
		api.box("DroneArm", Vector3.new(3.0, 0.15, 0.2), Vector3.new(dxc, dy, dzc), gunmetal, M.Metal, false)
		api.box("DroneArm", Vector3.new(0.5, 0.5, 3.0), Vector3.new(dxc, dy - 0.15, dzc), olive, M.Metal, false)
		for _, o in ipairs({ Vector3.new(1.4, 0, 0), Vector3.new(-1.4, 0, 0), Vector3.new(0, 0, 1.4), Vector3.new(0, 0, -1.4) }) do
			cyl("DroneRotor", 0.06, 1.1, CFrame.new(dxc + o.X, dy + 0.15, dzc + o.Z) * UP, col.Dark, M.SmoothPlastic, false)
		end
		for _, s in ipairs({ -1, 1 }) do
			local top = 12.3
			api.box("DroneCable", Vector3.new(0.06, top - dy, 0.06), Vector3.new(dxc + s * 0.9, (top + dy) * 0.5, dzc), col.Metal, M.Metal, false)
		end
	end

	------------------------------------------------------------------------------------------------
	-- Back strip (single storey only): server racks between the back windows, cryo freezer, data desk
	------------------------------------------------------------------------------------------------
	if not ictx.TwoStory then
		for _, rx in ipairs({ -4.0, 4.0 }) do
			local rack = api.box("ServerRack", Vector3.new(2.4, 7.0, 1.4), Vector3.new(rx, y1 + 3.5, Z0 + 0.75), col.Dark, M.Metal)
			rows(rack, Enum.NormalId.Back, 12, 6, ledPalette, col.Dark, 0.25, true)
			api.box("RackLed", Vector3.new(0.2, 0.2, 0.1), Vector3.new(rx - 0.8, y1 + 6.5, Z0 + 1.5), col.Screen, M.Neon, false)
			api.box("RackLed", Vector3.new(0.2, 0.2, 0.1), Vector3.new(rx - 0.4, y1 + 6.5, Z0 + 1.5), amber, M.Neon, false)
		end
		local freezer = api.box("CryoFreezer", Vector3.new(2.8, 3.2, 1.3), Vector3.new(X0 + 1.5, y1 + 1.6, Z0 + 0.7), labWhite, M.Metal)
		api.surfaceText(freezer, Enum.NormalId.Back, { "CRYO STORE", "-80 C" }, col.Screen, screenBg, Enum.Font.Code)
		local ddx, ddz = -8.0, -7.0
		api.box("DataDesk", Vector3.new(2.8, 2.6, 1.1), Vector3.new(ddx, y1 + 1.3, ddz), gunmetal, M.Metal)
		api.box("DataDeskTop", Vector3.new(3.2, 0.2, 1.5), Vector3.new(ddx, y1 + 2.7, ddz), col.Metal, M.Metal)
		for i, off in ipairs({ -0.75, 0.75 }) do
			local mon = api.box("DataMonitor", Vector3.new(1.3, 0.9, 0.12), Vector3.new(ddx + off, y1 + 3.3, ddz - 0.35), col.Dark, M.Metal, false)
			api.surfaceText(mon, Enum.NormalId.Back, if i == 1 then { "TEST LOG", "RUN 14 OK" } else { "SAMPLES", "12 / 12" }, col.Screen, screenBg, Enum.Font.Code)
		end
		seat(ddx, y1, ddz + 1.5, 0, -1)
	end

	------------------------------------------------------------------------------------------------
	-- Upper floor (L3+)
	------------------------------------------------------------------------------------------------
	if ictx.TwoStory then
		local y2: number = ictx.Y2

		-- Server room (back-east): L of racks, LEDs, overhead cable tray. X 9..13, Z -9..-3 stays open.
		local eRack = api.box("ServerRack", Vector3.new(1.0, 7.0, 7.0), Vector3.new(X1 - 0.55, y2 + 3.5, -6.5), col.Dark, M.Metal)
		rows(eRack, Enum.NormalId.Left, 12, 12, ledPalette, col.Dark, 0.25, true)
		local bRack = api.box("ServerRack", Vector3.new(2.1, 7.0, 1.05), Vector3.new(12.05, y2 + 3.5, Z0 + 0.575), col.Dark, M.Metal)
		rows(bRack, Enum.NormalId.Back, 12, 4, ledPalette, col.Dark, 0.25, true)
		api.box("RackLed", Vector3.new(0.1, 0.2, 0.2), Vector3.new(X1 - 1.1, y2 + 6.3, -8.4), col.Screen, M.Neon, false)
		api.box("RackLed", Vector3.new(0.1, 0.2, 0.2), Vector3.new(X1 - 1.1, y2 + 6.3, -4.6), amber, M.Neon, false)
		api.box("CableTray", Vector3.new(1.0, 0.15, 7.4), Vector3.new(X1 - 0.6, y2 + 8.2, -6.4), col.Metal, M.Metal, false)

		-- Engineering & defense wall (east): two terminals under amber signs, drafting table
		setTab(api.terminal("VehicleTerminal", Vector3.new(X1 - 0.6, y2, 4.6), -90, "Research", "Research vehicles", "Vehicle Engineering", { "VEHICLE ENG.", "SPEED · ARMOR" }), "Vehicles")
		setTab(api.terminal("DefenseTerminal", Vector3.new(X1 - 0.6, y2, 8.2), -90, "Research", "Research defenses", "Defense Systems", { "DEFENSE SYSTEMS", "GUARDS · GUNS" }), "Defenses")
		local function engSign(z: number, text: string)
			local s = api.box("EngineeringSign", Vector3.new(0.1, 1.2, 3.2), Vector3.new(X1 - 0.05, 20.75, z), col.Dark, M.Metal, false)
			api.surfaceText(s, Enum.NormalId.Left, { text }, amber, col.Dark, Enum.Font.GothamBlack)
		end
		engSign(4.6, "VEHICLE ENGINEERING")
		engSign(8.2, "DEFENSE SYSTEMS")
		api.box("DraftingStand", Vector3.new(0.6, 2.3, 1.6), Vector3.new(7.5, y2 + 1.15, 2.25), gunmetal, M.Metal)
		local board = api.part("DraftingBoard", Vector3.new(3.0, 0.12, 2.3), CFrame.new(7.5, y2 + 2.55, 2.25) * CFrame.Angles(math.rad(20), 0, 0), labWhite, M.SmoothPlastic)
		api.surfaceText(
			board,
			Enum.NormalId.Top,
			{ "APC-7  SIDE ELEVATION", "[==][========][==]", "(O)    (O)    (O)", "SCALE 1:20" },
			Color3.fromRGB(215, 232, 255),
			Color3.fromRGB(30, 60, 104),
			Enum.Font.Code
		)

		-- Director's office (front-west) behind glass; door gap Z 4.4..7.8 in the east partition
		local oX0, oXE, oZS = X0 + 0.05, -6.4, 3.5
		local oGap0, oGap1 = 4.4, 7.8
		local GH = 7.6
		glass("OfficeGlass", Vector3.new(oXE - 0.15 - oX0, GH, 0.15), Vector3.new((oX0 + oXE - 0.15) * 0.5, y2 + GH * 0.5, oZS), true)
		glass("OfficeGlass", Vector3.new(0.15, GH, oGap0 - (oZS - 0.075)), Vector3.new(oXE, y2 + GH * 0.5, (oGap0 + oZS - 0.075) * 0.5), true)
		glass("OfficeGlass", Vector3.new(0.15, GH, Z1 - 0.05 - oGap1), Vector3.new(oXE, y2 + GH * 0.5, (Z1 - 0.05 + oGap1) * 0.5), true)
		api.box("OfficeHeader", Vector3.new(oXE + 0.15 - oX0, 0.4, 0.3), Vector3.new((oX0 + oXE + 0.15) * 0.5, y2 + GH + 0.2, oZS), col.Trim, M.Metal, false)
		api.box("OfficeHeader", Vector3.new(0.3, 0.4, Z1 - 0.05 - oZS), Vector3.new(oXE, y2 + GH + 0.2, (Z1 - 0.05 + oZS) * 0.5), col.Trim, M.Metal, false)
		api.box("DirectorDesk", Vector3.new(1.4, 2.5, 2.8), Vector3.new(-9.6, y2 + 1.25, 6.3), woodCol, M.Wood)
		api.box("DirectorDeskTop", Vector3.new(1.9, 0.2, 3.2), Vector3.new(-9.6, y2 + 2.6, 6.3), Color3.fromRGB(62, 44, 30), M.Wood)
		seat(-11.3, y2, 6.3, 1, 0)
		local shelf = api.box("Bookshelf", Vector3.new(0.8, 6.8, 4.0), Vector3.new(X0 + 0.45, y2 + 3.4, 6.0), woodCol, M.Wood)
		rows(shelf, Enum.NormalId.Right, 5, 11, bookPalette, Color3.fromRGB(40, 30, 22), 0.8, false)
		cyl("PlantPot", 1.0, 0.9, CFrame.new(-13.3, y2 + 0.5, 9.3) * UP, gunmetal, M.Metal, true)
		api.ball("Plant", 1.6, Vector3.new(-13.3, y2 + 1.7, 9.3), Color3.fromRGB(62, 104, 52), M.Grass, false)
		if lv >= 5 then
			local plaque = api.box("GoldPlaque", Vector3.new(0.12, 1.1, 3.4), Vector3.new(X0 + 0.06, y2 + 7.6, 6.0), col.Gold, M.Metal, false)
			api.surfaceText(plaque, Enum.NormalId.Right, { "WAR EMPIRE", "ADVANCED RESEARCH" }, col.Dark, col.Gold, Enum.Font.GothamBlack)
			cyl("HoloProjector", 0.15, 0.7, CFrame.new(-9.6, y2 + 2.775, 5.4) * UP, col.Dark, M.Metal, false)
			local globe = api.ball("HoloGlobe", 0.8, Vector3.new(-9.6, y2 + 3.35, 5.4), col.Screen, M.Neon, false)
			globe.Transparency = 0.4
			api.light(globe, 6, 0.4, col.Screen) -- accent 1/2 (upper floor)
		end

		-- Analyst pool (middle): two back-to-back desk pairs, >= 2.8 clear of the stair rail
		for i, cx in ipairs({ -3.1, 1.3 }) do
			local cz = 0.5
			api.box("AnalystDesk", Vector3.new(3.2, 0.2, 2.4), Vector3.new(cx, y2 + 2.6, cz), labWhite, M.SmoothPlastic)
			api.box("AnalystDeskPanel", Vector3.new(3.0, 2.5, 0.15), Vector3.new(cx, y2 + 1.25, cz), gunmetal, M.Metal)
			local mon = api.box("AnalystMonitors", Vector3.new(2.6, 0.95, 0.2), Vector3.new(cx, y2 + 3.175, cz), col.Dark, M.Metal, false)
			api.surfaceText(mon, Enum.NormalId.Front, if i == 1 then { "HIT DATA", "DMG +12%" } else { "SQUAD SIM", "HP 117 / 117" }, col.Screen, screenBg, Enum.Font.Code)
			api.surfaceText(mon, Enum.NormalId.Back, if i == 1 then { "RELOAD", "1.69 s" } else { "ENGINE", "RPM OK" }, amber, screenBg, Enum.Font.Code)
			seat(cx, y2, cz - 1.85, 0, 1)
			seat(cx, y2, cz + 1.85, 0, -1)
		end
		local wb = api.box("Whiteboard", Vector3.new(0.1, 2.6, 2.6), Vector3.new(X0 + 0.05, y2 + 3.6, -3.9), Color3.fromRGB(236, 238, 234), M.SmoothPlastic, false)
		api.surfaceText(wb, Enum.NormalId.Right, { "E = 0.5 m v^2", "F = m a", "ROF x 1.15", "MAG 30 > 42" }, Color3.fromRGB(34, 52, 110), Color3.fromRGB(236, 238, 234), Enum.Font.Code)
	end
end
