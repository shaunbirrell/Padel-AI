--!strict
--[[
	Warehouse interior (HollowBuildingBuilder): one tall single-storey storage hall (34 x 26, 14 tall), garage door
	X -3..9 on the front wall, upgrade console just inside at (14.5, 9).

	  • Loading bay (X -4..10, Z 6.2..12.2): kept completely clear, outlined in yellow floor paint + LOADING BAY.
	  • Pallet racking: olive uprights, yellow beams, wooden pallet decks at y1+4.2 and y1+8.2, a deterministic mix
	    of loads on every deck (olive ammo crates with yellow stencil bands, sand cartons, shrink-wrapped loads).
	      Rack A (L1+) along the west wall; aisle A in front of it stays clear.
	      Rack B (L2+) double-sided between aisle A and aisle B.
	      Rack D (L3+) against the back wall.
	  • Cross aisle Z -3.5..1 (X -7..10): clear at every level, edged in yellow.
	  • Floor block stacks of crates (back-middle, L1+); a supply-drop crate with its parachute bundle tops one at L5.
	  • Forklift (L1+) parked by the mouth of aisle A, forks toward the racks, empty pallet on the forks.
	  • Quartermaster cage (back-east): steel counter with a hatch where the Quartermaster terminal stands
	    (Shop → Supply), bar screen above the counter, bar wall along X = 10.3, sign; shelving with helmets and
	    stock, desk and chair inside. Hatched floor in front of the counter.
	  • Supply-run desk (front-west): Supply runs terminal (Missions) under a SUPPLY ROUTES board.
	  • Empty pallets stacked on the east wall; pallet jack (L3+); fuel drums on a spill pallet and a stretch-wrap
	    station with a turning load (L4+); gold WAR EMPIRE LOGISTICS sign over rack D (L5).

	No lights are added here (the shell's ceiling fittings and skylights light the hall). Neon only for the
	forklift beacon. Everything is deterministic; nothing rises above y 12.4 except the L5 wall sign.
]]

return function(ictx: any, api: any)
	local col = ictx.Colors
	local lv: number = ictx.Level
	local y1: number = ictx.Y1
	local X0: number, X1: number, Z0: number, Z1: number = ictx.InX0, ictx.InX1, ictx.InZ0, ictx.InZ1
	local M = Enum.Material
	local UP = CFrame.Angles(0, 0, math.pi * 0.5) -- cylinder axis (local X) → vertical
	local amber: Color3 = col.Accent
	local olive: Color3 = col.Trim
	local crateOlive: Color3 = col.Locker
	local sand: Color3 = col.Sandbag
	local wood = Color3.fromRGB(150, 112, 70)
	local woodDark = Color3.fromRGB(92, 66, 42)
	local wrapCol = Color3.fromRGB(206, 212, 208)
	local fuelCol = Color3.fromRGB(110, 52, 42)
	local tyre = Color3.fromRGB(24, 24, 24)

	local function cyl(name: string, length: number, dia: number, cf: CFrame, color: Color3, mat: Enum.Material, collide: boolean?): BasePart
		return api.cylinder(name, Vector3.new(length, dia, dia), cf, color, mat, collide)
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

	local function newGui(host: BasePart, face: Enum.NormalId, name: string): SurfaceGui
		local sg = Instance.new("SurfaceGui")
		sg.Name = name
		sg.Face = face
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 20
		sg.LightInfluence = 1
		sg.Parent = host
		return sg
	end

	-- n alternating bars across a face (vertical, or horizontal slats); b = nil leaves the gaps see-through.
	local function stripes(host: BasePart, face: Enum.NormalId, n: number, a: Color3, b: Color3?, horizontal: boolean)
		local sg = newGui(host, face, "WE_Stripes")
		for i = 0, n - 1 do
			local f = Instance.new("Frame")
			f.BorderSizePixel = 0
			if horizontal then
				f.Size = UDim2.fromScale(1, 1 / n)
				f.Position = UDim2.fromScale(0, i / n)
			else
				f.Size = UDim2.fromScale(1 / n, 1)
				f.Position = UDim2.fromScale(i / n, 0)
			end
			if i % 2 == 0 then
				f.BackgroundColor3 = a
			elseif b then
				f.BackgroundColor3 = b
			else
				f.BackgroundTransparency = 1
			end
			f.Parent = sg
		end
	end

	-- Bar screen: faint steel panel with painted vertical bars on both big faces (collidable, see-through).
	local function barScreen(host: BasePart, faces: { Enum.NormalId }, n: number)
		host.Transparency = 0.8
		host.CastShadow = false
		for _, face in ipairs(faces) do
			local sg = newGui(host, face, "WE_Bars")
			for i = 0, n - 1 do
				local f = Instance.new("Frame")
				f.BorderSizePixel = 0
				f.BackgroundColor3 = col.Metal
				f.Size = UDim2.fromScale(0.3 / n, 1)
				f.Position = UDim2.fromScale((i + 0.35) / n, 0)
				f.Parent = sg
			end
			for _, yy in ipairs({ 0, 0.5, 0.97 }) do
				local rail = Instance.new("Frame")
				rail.BorderSizePixel = 0
				rail.BackgroundColor3 = col.Metal
				rail.Size = UDim2.fromScale(1, 0.03)
				rail.Position = UDim2.fromScale(0, yy)
				rail.Parent = sg
			end
		end
	end

	-- Olive ammo crate stencil: two yellow bands + text.
	local function stencil(host: BasePart, face: Enum.NormalId, text: string)
		local sg = newGui(host, face, "WE_Stencil")
		for _, yy in ipairs({ 0.12, 0.8 }) do
			local band = Instance.new("Frame")
			band.BorderSizePixel = 0
			band.BackgroundColor3 = amber
			band.Size = UDim2.fromScale(1, 0.08)
			band.Position = UDim2.fromScale(0, yy)
			band.Parent = sg
		end
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(0.8, 0.36)
		t.Position = UDim2.fromScale(0.1, 0.32)
		t.Font = Enum.Font.GothamBlack
		t.Text = text
		t.TextScaled = true
		t.TextColor3 = amber
		t.Parent = sg
	end

	-- Two-part seat (upholstered base + back); (fx, fz) = the way the sitter faces.
	local function seat(x: number, y: number, z: number, fx: number, fz: number)
		api.box("Seat", Vector3.new(1.3, 1.5, 1.3), Vector3.new(x, y + 0.75, z), col.Dark, M.Fabric)
		local backSize = if math.abs(fx) > 0.5 then Vector3.new(0.3, 1.9, 1.3) else Vector3.new(1.3, 1.9, 0.3)
		api.box("SeatBack", backSize, Vector3.new(x - fx * 0.5, y + 2.45, z - fz * 0.5), col.Dark, M.Fabric, false)
	end

	------------------------------------------------------------------------------------------------
	-- Pallet racking
	------------------------------------------------------------------------------------------------
	local KINDS = { "ammo", "carton", "wrap", "carton", "ammo", "wrap", "carton", "ammo", "wrap", "carton", "ammo", "carton", "wrap", "ammo" }
	local loadNo = 0
	-- One pallet load standing on a deck at `base`; w = along the rack run, d = rack depth.
	local function load(pos: Vector3, base: number, w: number, d: number, maxH: number, alongX: boolean, face: Enum.NormalId, solid: boolean)
		loadNo += 1
		local kind = KINDS[(loadNo - 1) % #KINDS + 1]
		local function size(a: number, h: number, b: number): Vector3
			return if alongX then Vector3.new(a, h, b) else Vector3.new(b, h, a)
		end
		if kind == "ammo" then
			local h = math.min(2.2, maxH)
			local p = api.box("AmmoLoad", size(w - 0.3, h, d - 0.2), Vector3.new(pos.X, base + h * 0.5, pos.Z), crateOlive, M.Wood, solid)
			stencil(p, face, "AMMO")
		elseif kind == "carton" then
			local h = math.min(2.6, maxH)
			api.box("CartonLoad", size(w - 0.2, h, d - 0.1), Vector3.new(pos.X, base + h * 0.5, pos.Z), sand, M.Cardboard, solid)
		else
			local h = math.min(2.8, maxH)
			local p = api.box("WrappedLoad", size(w - 0.1, h, d - 0.05), Vector3.new(pos.X, base + h * 0.5, pos.Z), wrapCol, M.SmoothPlastic, solid)
			p.Transparency = 0.25
		end
	end

	--[[ Rack running along X (alongX) or Z, from a0 to a1, depth d0..d1, `bays` equal bays. `lines` = depth
		coordinates of the upright lines (the aisle faces; a wall rack has none at the wall). Decks and loads are
		walk-through (non-collidable) so beams and pallets never snag; only the uprights collide. ]]
	local function rack(alongX: boolean, a0: number, a1: number, d0: number, d1: number, bays: number, lines: { number }, face: Enum.NormalId)
		local function P(a: number, y: number, d: number): Vector3
			return if alongX then Vector3.new(a, y, d) else Vector3.new(d, y, a)
		end
		local function S(a: number, y: number, d: number): Vector3
			return if alongX then Vector3.new(a, y, d) else Vector3.new(d, y, a)
		end
		local span = (a1 - a0 - 0.4) / bays
		local dc = (d0 + d1) * 0.5
		local depth = d1 - d0
		for k = 0, bays do
			local a = a0 + 0.2 + k * span
			for _, ld in ipairs(lines) do
				api.box("RackUpright", S(0.4, 12, 0.4), P(a, y1 + 6, ld), olive, M.Metal)
			end
		end
		for _, deckY in ipairs({ 4.2, 8.2 }) do
			for _, ld in ipairs(lines) do
				api.box("RackBeam", S(a1 - a0, 0.5, 0.3), P((a0 + a1) * 0.5, y1 + deckY - 0.25, ld), amber, M.Metal, false)
			end
			local deck = api.box("PalletDeck", S(a1 - a0 - 0.1, 0.45, depth - 0.1), P((a0 + a1) * 0.5, y1 + deckY + 0.225, dc), wood, M.WoodPlanks, false)
			stripes(deck, face, bays * 6, woodDark, wood, false)
			local maxH = if deckY < 5 then 2.9 else 3.1
			for k = 0, bays - 1 do
				load(P(a0 + 0.2 + (k + 0.5) * span, 0, dc), y1 + deckY + 0.45, span - 0.4, depth - 0.2, maxH, alongX, face, false)
			end
		end
	end

	-- Rack A (west wall), aisle A X -14.35..-10.2 in front of it
	rack(false, -11.9, 3.7, X0 + 0.05, -14.35, 4, { -14.55 }, Enum.NormalId.Right)
	-- Rack B (double-sided), aisle B X -7.0..-4 east of it
	if lv >= 2 then
		rack(false, -11.9, 0, -10.2, -7.0, 3, { -10.0, -7.2 }, Enum.NormalId.Right)
	end
	-- Rack D (back wall)
	if lv >= 3 then
		rack(true, -2, 8, Z0 + 0.05, -10.35, 3, { -10.55 }, Enum.NormalId.Back)
	end
	if lv < 2 then
		-- L1: pallets staged on the floor where rack B goes in (solid; aisles A and B stay clear)
		for _, z in ipairs({ -9.4, -5.4 }) do
			api.box("FloorPallet", Vector3.new(3.0, 0.45, 3.0), Vector3.new(-8.6, y1 + 0.225, z), wood, M.WoodPlanks)
			load(Vector3.new(-8.6, 0, z), y1 + 0.45, 3.2, 3.1, 2.6, false, Enum.NormalId.Right, true)
		end
	end

	------------------------------------------------------------------------------------------------
	-- Floor block stacks (back-middle, between rack D and the cross aisle)
	------------------------------------------------------------------------------------------------
	local function crate(x: number, y: number, z: number, s: number, yawDeg: number, color: Color3, mat: Enum.Material, label: string?): BasePart
		local p = api.part("StackCrate", Vector3.new(s, s, s), CFrame.new(x, y + s * 0.5, z) * CFrame.Angles(0, math.rad(yawDeg), 0), color, mat)
		if label then
			stencil(p, Enum.NormalId.Back, label)
		end
		return p
	end
	crate(1.6, y1, -6.4, 2.4, 0, wood, M.WoodPlanks)
	crate(1.6, y1 + 2.4, -6.4, 2.4, 6, crateOlive, M.Wood, "SUPPLY")
	crate(4.6, y1, -6.0, 2.4, 3, crateOlive, M.Wood, "RATIONS")
	crate(4.6, y1 + 2.4, -6.0, 2.4, -7, wood, M.WoodPlanks)
	if lv >= 5 then
		crate(4.6, y1 + 4.8, -6.0, 2.2, 4, crateOlive, M.Wood, "AIRDROP")
		api.part("ParachuteBundle", Vector3.new(1.6, 0.7, 1.3), CFrame.new(4.6, y1 + 7.0 + 0.35, -6.0) * CFrame.Angles(0, math.rad(4), 0), sand, M.Fabric, false)
		local sign = api.box("LogisticsSign", Vector3.new(9.0, 1.2, 0.1), Vector3.new(3.0, y1 + 12.8, Z0 + 0.05), col.Dark, M.Metal, false)
		api.surfaceText(sign, Enum.NormalId.Back, { "WAR EMPIRE LOGISTICS" }, col.Gold, col.Dark, Enum.Font.GothamBlack)
	end

	------------------------------------------------------------------------------------------------
	-- Forklift by the mouth of aisle A (faces -Z; only the chassis and counterweight collide)
	------------------------------------------------------------------------------------------------
	do
		local fx = -10.0
		api.box("ForkliftChassis", Vector3.new(2.2, 1.2, 3.4), Vector3.new(fx, y1 + 0.95, 7.3), amber, M.Metal)
		api.box("ForkliftCounterweight", Vector3.new(2.2, 1.6, 0.9), Vector3.new(fx, y1 + 1.15, 9.35), col.Dark, M.Metal)
		cyl("ForkliftWheels", 2.8, 1.1, CFrame.new(fx, y1 + 0.55, 6.2), tyre, M.Fabric, false)
		cyl("ForkliftWheels", 2.8, 0.9, CFrame.new(fx, y1 + 0.45, 8.8), tyre, M.Fabric, false)
		api.box("ForkliftSeat", Vector3.new(1.3, 0.8, 1.1), Vector3.new(fx, y1 + 1.95, 8.2), col.Dark, M.Fabric, false)
		cyl("ForkliftSteering", 0.12, 0.9, CFrame.new(fx, y1 + 1.95, 6.9) * CFrame.Angles(math.rad(35), 0, 0) * UP, col.Dark, M.Metal, false)
		for _, px in ipairs({ -1, 1 }) do
			for _, pz in ipairs({ 6.2, 8.7 }) do
				api.box("ForkliftGuardPost", Vector3.new(0.18, 2.6, 0.18), Vector3.new(fx + px * 0.95, y1 + 2.85, pz), col.Dark, M.Metal, false)
			end
		end
		api.box("ForkliftGuardRoof", Vector3.new(2.1, 0.15, 2.8), Vector3.new(fx, y1 + 4.225, 7.45), col.Dark, M.Metal, false)
		for _, px in ipairs({ -1, 1 }) do
			api.box("ForkliftMast", Vector3.new(0.25, 5.6, 0.3), Vector3.new(fx + px * 0.75, y1 + 3.0, 5.45), col.Metal, M.Metal, false)
		end
		api.box("ForkliftCarriage", Vector3.new(1.9, 1.0, 0.2), Vector3.new(fx, y1 + 1.1, 5.2), col.Dark, M.Metal, false)
		for _, px in ipairs({ -1, 1 }) do
			api.box("ForkliftFork", Vector3.new(0.25, 0.12, 1.9), Vector3.new(fx + px * 0.5, y1 + 0.66, 4.15), col.Metal, M.Metal, false)
		end
		api.box("ForkliftPallet", Vector3.new(2.0, 0.4, 1.9), Vector3.new(fx, y1 + 0.92, 4.15), wood, M.WoodPlanks, false)
		api.ball("ForkliftBeacon", 0.3, Vector3.new(fx, y1 + 4.45, 8.4), amber, M.Neon, false)
	end

	------------------------------------------------------------------------------------------------
	-- Quartermaster cage (back-east): counter with a hatch, terminal in the hatch → Shop (Supply tab)
	------------------------------------------------------------------------------------------------
	local cageX = 10.3
	api.box("QMCounter", Vector3.new(11.9 - cageX, 3.3, 1.2), Vector3.new((cageX + 11.9) * 0.5, y1 + 1.65, -1.4), col.Metal, M.DiamondPlate)
	api.box("QMCounter", Vector3.new(X1 - 0.05 - 14.5, 3.3, 1.2), Vector3.new((14.5 + X1 - 0.05) * 0.5, y1 + 1.65, -1.4), col.Metal, M.DiamondPlate)
	local qm = api.terminal("QMTerminal", Vector3.new(13.2, y1, -1.4), 0, "Shop", "Requisition", "Quartermaster", { "QUARTERMASTER", "SUPPLY DROPS" })
	local qmPrompt = if qm then qm:FindFirstChild("WE_PanelPrompt") else nil
	if qmPrompt then
		qmPrompt:SetAttribute("WE_OpenTab", "Supply")
	end
	local screen = api.box("QMCageScreen", Vector3.new(X1 - 0.05 - cageX, 4.4, 0.1), Vector3.new((cageX + X1 - 0.05) * 0.5, 7.2, -1.4), col.Metal, M.Metal)
	barScreen(screen, { Enum.NormalId.Front, Enum.NormalId.Back }, 18)
	local side = api.box("QMCageSide", Vector3.new(0.1, 9.0, -2.0 - (Z0 + 0.05)), Vector3.new(cageX + 0.05, y1 + 4.5, (Z0 + 0.05 - 2.0) * 0.5), col.Metal, M.Metal)
	barScreen(side, { Enum.NormalId.Left, Enum.NormalId.Right }, 30)
	local qmSign = api.box("QMSign", Vector3.new(X1 - 0.05 - cageX, 1.4, 0.2), Vector3.new((cageX + X1 - 0.05) * 0.5, 10.1, -1.4), col.Dark, M.Metal, false)
	api.surfaceText(qmSign, Enum.NormalId.Back, { "QUARTERMASTER" }, amber, col.Dark, Enum.Font.GothamBlack)
	-- inside: stock shelving on the east wall (painted stock + two helmets), desk and chair
	local shelving = api.box("QMShelving", Vector3.new(1.0, 7.0, 7.6), Vector3.new(X1 - 0.55, y1 + 3.5, -7.8), col.Metal, M.Metal)
	do
		local sg = newGui(shelving, Enum.NormalId.Left, "WE_Stock")
		local bg = Instance.new("Frame")
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundColor3 = col.Dark
		bg.BorderSizePixel = 0
		bg.Parent = sg
		local stock = { sand, crateOlive, sand, col.Rug, wood, crateOlive }
		for r = 0, 3 do
			for i = 0, 4 do
				local k = r * 5 + i
				local h = 0.55 + (k * 3 % 4) * 0.08
				local box = Instance.new("Frame")
				box.BorderSizePixel = 0
				box.BackgroundColor3 = stock[(k * 5 + r) % #stock + 1]
				box.Size = UDim2.fromScale(0.16, h / 4)
				box.Position = UDim2.fromScale(0.02 + i * 0.196, (r + 0.94 - h) / 4)
				box.Parent = bg
			end
			local shelfLine = Instance.new("Frame")
			shelfLine.BorderSizePixel = 0
			shelfLine.BackgroundColor3 = col.Metal
			shelfLine.Size = UDim2.fromScale(1, 0.015)
			shelfLine.Position = UDim2.fromScale(0, (r + 0.94) / 4)
			shelfLine.Parent = bg
		end
	end
	for i = 0, 1 do
		api.ball("Helmet", 0.9, Vector3.new(X1 - 1.3, y1 + 3.5 + 0.45, -10.2 + i * 1.0), crateOlive, M.SmoothPlastic, false)
	end
	api.box("QMDesk", Vector3.new(2.2, 2.5, 1.0), Vector3.new(12.4, y1 + 1.25, -5.9), wood, M.Wood)
	api.box("QMDeskTop", Vector3.new(2.5, 0.2, 1.3), Vector3.new(12.4, y1 + 2.6, -5.9), woodDark, M.Wood)
	seat(12.4, y1, -7.35, 0, 1)

	------------------------------------------------------------------------------------------------
	-- Supply-run desk (front-west): terminal against the front wall → Missions, route board above it
	------------------------------------------------------------------------------------------------
	api.terminal("SupplyTerminal", Vector3.new(-6.6, y1, Z1 - 0.8), 180, "Missions", "Plan supply run", "Supply Runs", { "SUPPLY RUNS", "CONVOY OPS" })
	local board = api.box("RouteBoard", Vector3.new(4.0, 3.0, 0.1), Vector3.new(-6.6, 9.5, Z1 - 0.05), col.Dark, M.Metal, false)
	api.surfaceText(board, Enum.NormalId.Front, { "SUPPLY ROUTES", "DEPOT > FOB 1  CLEAR", "DEPOT > FOB 2  CLEAR", "CONVOY 3  EN ROUTE" }, amber, col.Dark, Enum.Font.Code)

	------------------------------------------------------------------------------------------------
	-- East wall between the cage and the console: empty pallets stacked on edge
	------------------------------------------------------------------------------------------------
	local pallets = api.box("EmptyPallets", Vector3.new(1.1, 2.3, 4.3), Vector3.new(X1 - 0.6, y1 + 1.15, 3.25), wood, M.WoodPlanks)
	stripes(pallets, Enum.NormalId.Left, 9, woodDark, wood, true)

	if lv >= 3 then
		-- pallet jack parked at the north end of rack B (out of aisle B and the cross aisle)
		api.box("PalletJack", Vector3.new(1.3, 0.25, 2.6), Vector3.new(-7.75, y1 + 0.125, 1.7), amber, M.Metal)
		api.part("PalletJackHandle", Vector3.new(0.12, 2.2, 0.12), CFrame.new(-7.75, y1 + 1.2, 3.2) * CFrame.Angles(math.rad(25), 0, 0), col.Dark, M.Metal, false)
	end

	if lv >= 4 then
		-- fuel drums on a spill pallet + stretch-wrap station (turntable and load turn on the client)
		api.box("SpillPallet", Vector3.new(2.9, 0.3, 2.9), Vector3.new(1.6, y1 + 0.15, 3.5), amber, M.Metal)
		for _, o in ipairs({ Vector3.new(-0.65, 0, -0.65), Vector3.new(0.65, 0, -0.65), Vector3.new(-0.65, 0, 0.65) }) do
			cyl("FuelDrum", 1.9, 1.25, CFrame.new(1.6 + o.X, y1 + 0.3 + 0.95, 3.5 + o.Z) * UP, fuelCol, M.Metal)
		end
		local turntable = cyl("WrapTurntable", 0.3, 3.0, CFrame.new(6.0, y1 + 0.15, 3.6) * UP, col.Metal, M.DiamondPlate, false)
		local wrapped = api.box("WrapLoad", Vector3.new(2.2, 2.4, 2.2), Vector3.new(6.0, y1 + 0.3 + 1.2, 3.6), wrapCol, M.SmoothPlastic, false)
		wrapped.Transparency = 0.25
		api.spin({ turntable, wrapped }, Vector3.new(6.0, y1, 3.6), 6)
		api.box("WrapMast", Vector3.new(0.4, 4.0, 0.4), Vector3.new(8.0, y1 + 2.0, 3.6), amber, M.Metal)
	end

	------------------------------------------------------------------------------------------------
	-- Floor markings (walk-over): loading bay outline + stencil, cross-aisle edges, hatching at the counter
	------------------------------------------------------------------------------------------------
	local function line(sx: number, sz: number, x: number, z: number)
		api.box("FloorLine", Vector3.new(sx, 0.04, sz), Vector3.new(x, y1 + 0.02, z), amber, M.SmoothPlastic, false)
	end
	line(0.3, 5.9, -3.85, 9.2)
	line(0.3, 5.9, 9.85, 9.2)
	line(14.0, 0.3, 3.0, 6.35)
	line(17.0, 0.3, 1.5, -3.35)
	line(17.0, 0.3, 1.5, 0.85)
	local bayText = api.box("FloorStencil", Vector3.new(7.0, 0.04, 1.8), Vector3.new(3.0, y1 + 0.03, 9.4), col.Floor, M.SmoothPlastic, false)
	bayText.Transparency = 1
	paint(bayText, Enum.NormalId.Top, { "LOADING BAY" }, amber)
	local hatch = api.box("CounterHatching", Vector3.new(X1 - 0.1 - cageX, 0.04, 1.6), Vector3.new((cageX + X1 - 0.1) * 0.5, y1 + 0.02, 0.05), amber, M.SmoothPlastic, false)
	stripes(hatch, Enum.NormalId.Top, 14, amber, col.Dark, false)
end
