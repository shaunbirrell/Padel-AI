--!strict
--[[
	Vehicle Depot interior (HollowBuildingBuilder) — the motor pool: one tall single-storey workshop hall.

	Ground floor (36 x 28, 14 tall, garage door X -6..10 on the front wall):
	  • Drive lane: two painted lane lines run from the garage door straight back into Bay 1 (x -2.5..6.5),
	    kept clear of everything solid so a vehicle could roll in.
	  • Bay 1 (L1): four-post vehicle lift carrying a generic six-wheel cargo truck (nose to the door).
	    Bay 2 (L3, west): utility jeep. Bay 3 (L5, east): fuel bowser trailer. Oil stains in the bays.
	  • Overhead bridge crane: runway rails on the side walls + bridge beam over the truck's bonnet
	    (below the ceiling lights); an engine hangs from the hook from L4.
	  • Front-west: motor-pool dispatch desk + dispatch terminal (Garage), status board, filing cabinet.
	  • East wall (between the windows): parts cabinet + requisition terminal (Shop); air compressor (L4).
	  • West wall: workbench + pegboard between the windows (L1), second bench + tool chest (L2).
	  • Back wall: tyre stack between bays 2 and 1, fuel drums in the back-east corner (on a spill pallet from L2).
	The upgrade console stands just inside the door on the east side (BaseLayoutConfig) — kept clear.
]]

return function(ictx: any, api: any)
	local col = ictx.Colors
	local lv: number = ictx.Level
	local y1: number = ictx.Y1
	local X0, X1, Z0, Z1 = ictx.InX0, ictx.InX1, ictx.InZ0, ictx.InZ1
	local M = Enum.Material
	local UP = CFrame.Angles(0, 0, math.pi * 0.5) -- cylinder axis (local X) → vertical
	local ALONG_Z = CFrame.Angles(0, math.pi * 0.5, 0) -- cylinder axis (local X) → Z
	local oil = Color3.fromRGB(22, 24, 22)
	local tint = Color3.fromRGB(44, 58, 62)
	local paintWhite = Color3.fromRGB(226, 224, 212)

	local function cyl(name: string, length: number, dia: number, cf: CFrame, color: Color3, mat: Enum.Material, collide: boolean?): any
		local p = api.part(name, Vector3.new(length, dia, dia), cf, color, mat, collide)
		p.Shape = Enum.PartType.Cylinder
		return p
	end

	-- Stencilled text painted straight onto a surface: transparent background, lit like paint.
	local function paint(host: any, face: Enum.NormalId, lines: { string }, color: Color3)
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

	-- Floor paint (thin, walk-over)
	local function line(sx: number, sz: number, x: number, z: number, color: Color3)
		api.box("FloorPaint", Vector3.new(sx, 0.04, sz), Vector3.new(x, y1 + 0.02, z), color, M.SmoothPlastic, false)
	end
	local function floorStencil(x: number, z: number, w: number, lines: { string })
		local p = api.box("FloorStencil", Vector3.new(w, 0.04, 1.8), Vector3.new(x, y1 + 0.03, z), col.Floor, M.SmoothPlastic, false)
		p.Transparency = 1
		paint(p, Enum.NormalId.Top, lines, col.Accent)
	end
	local function stain(x: number, z: number, d: number)
		local p = cyl("OilStain", 0.03, d, CFrame.new(x, y1 + 0.016, z) * UP, oil, M.SmoothPlastic, false)
		p.Transparency = 0.25
	end

	------------------------------------------------------------------------------------------------
	-- Drive lane → Bay 1 (the lane lines continue into the bay), stop bar, stencils, oil
	------------------------------------------------------------------------------------------------
	local laneX0, laneX1 = -2.5, 6.5
	local laneLen = (Z1 - 0.1) - (Z0 + 0.4)
	for _, lx in ipairs({ laneX0, laneX1 }) do
		line(0.3, laneLen, lx, (Z1 - 0.1 + Z0 + 0.4) * 0.5, col.Accent)
	end
	line(laneX1 - laneX0 - 0.3, 0.35, (laneX0 + laneX1) * 0.5, 0.1, paintWhite)
	floorStencil(2, 1.6, 5.5, { "BAY 1" })
	stain(2.2, -3.0, 2.2)
	stain(3.8, 4.2, 1.3)

	------------------------------------------------------------------------------------------------
	-- Four-post vehicle lift (Bay 1) + six-wheel cargo truck on it
	------------------------------------------------------------------------------------------------
	local liftX = 2
	local runZ0, runZ1 = -11.8, -1.2
	local yb = y1 + 2.0 -- runway top = tyre contact
	for _, pz in ipairs({ runZ0 - 0.4, runZ1 + 0.4 }) do
		for _, sx in ipairs({ -1, 1 }) do
			api.box("LiftPost", Vector3.new(0.8, 8.4, 0.8), Vector3.new(liftX + sx * 3.2, y1 + 4.2, pz), col.Metal, M.Metal)
		end
		api.box("LiftBeam", Vector3.new(5.6, 0.6, 0.8), Vector3.new(liftX, yb - 0.3, pz), col.Dark, M.Metal)
	end
	for _, sx in ipairs({ -1, 1 }) do
		api.box("LiftRunway", Vector3.new(1.4, 0.4, runZ1 - runZ0), Vector3.new(liftX + sx * 1.75, yb - 0.2, (runZ0 + runZ1) * 0.5), col.Metal, M.DiamondPlate)
	end
	local ctrl = api.box("LiftControl", Vector3.new(0.3, 1.2, 0.8), Vector3.new(liftX + 3.75, y1 + 4.1, runZ1 + 0.4), col.Dark, M.Metal, false)
	paint(ctrl, Enum.NormalId.Right, { "▲", "▼" }, col.Accent)

	local function truck(cx: number, cz: number, base: number)
		for _, wz in ipairs({ 3.2, -1.9, -4.1 }) do
			for _, sx in ipairs({ -1, 1 }) do
				cyl("TruckTyre", 0.9, 2.2, CFrame.new(cx + sx * 1.75, base + 1.1, cz + wz), col.Dark, M.Fabric, false)
			end
		end
		api.box("TruckChassis", Vector3.new(2.6, 0.6, 9.8), Vector3.new(cx, base + 1.3, cz - 0.1), col.Dark, M.Metal)
		api.box("TruckCab", Vector3.new(4.0, 2.8, 2.4), Vector3.new(cx, base + 3.0, cz + 1.2), col.Trim, M.Metal)
		api.box("TruckCabWindows", Vector3.new(4.06, 0.9, 1.5), Vector3.new(cx, base + 3.8, cz + 1.3), tint, M.Glass, false)
		api.box("TruckWindshield", Vector3.new(3.4, 1.0, 0.1), Vector3.new(cx, base + 3.8, cz + 2.44), tint, M.Glass, false)
		api.box("TruckBonnet", Vector3.new(3.6, 1.5, 2.4), Vector3.new(cx, base + 2.35, cz + 3.6), col.Trim, M.Metal)
		api.box("TruckGrille", Vector3.new(2.2, 1.1, 0.1), Vector3.new(cx, base + 2.3, cz + 4.84), col.Dark, M.Metal, false)
		for _, sx in ipairs({ -1, 1 }) do
			api.box("TruckHeadlight", Vector3.new(0.55, 0.55, 0.1), Vector3.new(cx + sx * 1.45, base + 2.55, cz + 4.84), col.Light, M.Glass, false)
		end
		api.box("TruckBumper", Vector3.new(4.4, 0.5, 0.4), Vector3.new(cx, base + 1.35, cz + 5.0), col.Metal, M.Metal, false)
		api.box("TruckBed", Vector3.new(4.4, 0.8, 5.0), Vector3.new(cx, base + 2.0, cz - 2.6), col.Trim, M.Metal)
		local canvas = api.box("TruckCanvas", Vector3.new(4.3, 2.8, 4.8), Vector3.new(cx, base + 3.8, cz - 2.6), col.Rug, M.Fabric)
		paint(canvas, Enum.NormalId.Left, { "★" }, paintWhite)
		paint(canvas, Enum.NormalId.Right, { "★" }, paintWhite)
	end
	truck(liftX, -6.5, yb)

	------------------------------------------------------------------------------------------------
	-- Overhead bridge crane: wall runways, bridge over the truck bonnet, trolley + hook (engine from L4)
	------------------------------------------------------------------------------------------------
	local craneZ = -2.9
	local craneX = liftX
	for _, sx in ipairs({ -1, 1 }) do
		api.box("CraneRunway", Vector3.new(0.6, 0.6, Z1 - Z0), Vector3.new(sx * (X1 - 0.3), y1 + 11.7, 0), col.Metal, M.Metal, false)
	end
	local bridge = api.box("CraneBridge", Vector3.new(X1 - X0 - 0.2, 0.8, 1.0), Vector3.new(0, y1 + 12.4, craneZ), col.Metal, M.Metal, false)
	paint(bridge, Enum.NormalId.Back, { "SWL 5 T" }, col.Accent)
	api.box("CraneTrolley", Vector3.new(1.6, 0.7, 1.6), Vector3.new(craneX, y1 + 11.65, craneZ), col.Dark, M.Metal, false)
	local hookY = if lv >= 4 then y1 + 8.6 else y1 + 9.2
	api.box("CraneChain", Vector3.new(0.15, y1 + 11.3 - hookY, 0.15), Vector3.new(craneX, (y1 + 11.3 + hookY) * 0.5, craneZ), col.Metal, M.Metal, false)
	api.box("CraneHook", Vector3.new(0.7, 0.9, 0.5), Vector3.new(craneX, hookY - 0.45, craneZ), col.Accent, M.Metal, false)
	if lv >= 4 then
		-- engine swap in progress: the block hangs over the truck's open bonnet
		api.box("HoistedEngine", Vector3.new(2.0, 1.5, 1.8), Vector3.new(craneX, hookY - 1.65, craneZ), col.Dark, M.Metal, false)
	end

	------------------------------------------------------------------------------------------------
	-- Motor-pool dispatch (front-west): desk under the front window, chair, dispatch terminal → Garage
	------------------------------------------------------------------------------------------------
	local deskX = -13.3
	api.box("DispatchDesk", Vector3.new(5.0, 2.6, 1.6), Vector3.new(deskX, y1 + 1.3, Z1 - 0.8), col.Locker, M.Metal)
	api.box("DispatchDeskTop", Vector3.new(5.2, 0.2, 1.8), Vector3.new(deskX, y1 + 2.7, Z1 - 0.9), col.Metal, M.Metal)
	local mon = api.box("DispatchMonitor", Vector3.new(1.9, 1.2, 0.15), Vector3.new(deskX - 0.6, y1 + 3.4, Z1 - 1.0), col.Dark, M.Metal, false)
	api.surfaceText(mon, Enum.NormalId.Front, { "DISPATCH LOG", "TRK-01  LIFT 1", "FUEL  OK" }, col.Screen, Color3.fromRGB(8, 20, 12), Enum.Font.Code)
	api.chair(Vector3.new(deskX, y1, Z1 - 3.2), Vector3.new(0, 0, 1))
	api.terminal("DispatchTerminal", Vector3.new(-8.9, y1, Z1 - 0.6), 180, "Garage", "Open garage", "Motor Pool", { "MOTOR POOL", "DISPATCH" })
	api.box("FilingCabinet", Vector3.new(1.3, 4.0, 1.6), Vector3.new(X0 + 0.65, y1 + 2.0, 9.9), col.Locker, M.Metal)
	local board = api.box("StatusBoard", Vector3.new(0.12, 3.0, 3.8), Vector3.new(X0 + 0.06, y1 + 6.2, 10.9), col.Dark, M.Metal, false)
	api.surfaceText(board, Enum.NormalId.Right, {
		"VEHICLE STATUS",
		"TRK-01   ON LIFT",
		if lv >= 3 then "4X4-02   READY" else "BAY 2    ----",
		if lv >= 5 then "FUEL-03  FUELING" else "BAY 3    ----",
	}, col.Light, Color3.fromRGB(16, 22, 18), Enum.Font.Code)

	------------------------------------------------------------------------------------------------
	-- Parts & fuel counter (east wall, between the windows): requisition terminal → Shop, parts cabinet
	------------------------------------------------------------------------------------------------
	api.terminal("PartsTerminal", Vector3.new(X1 - 0.6, y1, -1.4), -90, "Shop", "Requisition", "Parts & Fuel", { "PARTS & FUEL", "REQUISITION" })
	api.box("PartsCabinet", Vector3.new(1.3, 7.0, 3.2), Vector3.new(X1 - 0.65, y1 + 3.5, 2.0), col.Metal, M.Metal)
	local bank = api.box("PartsDrawers", Vector3.new(0.2, 5.2, 3.0), Vector3.new(X1 - 1.4, y1 + 3.3, 2.0), col.Locker, M.Metal, false)
	paint(bank, Enum.NormalId.Left, { "FILTERS", "BELTS · HOSES", "PLUGS", "TRACK PINS" }, paintWhite)
	local partsSign = api.box("PartsSign", Vector3.new(0.12, 1.8, 6.4), Vector3.new(X1 - 0.06, y1 + 9.2, -0.4), col.Dark, M.Metal, false)
	api.surfaceText(partsSign, Enum.NormalId.Left, { "PARTS & FUEL", "REQUISITION" }, col.Accent, col.Dark, Enum.Font.GothamBlack)

	------------------------------------------------------------------------------------------------
	-- Workbenches along the west wall (pegboards only between / clear of the windows)
	------------------------------------------------------------------------------------------------
	local function bench(z: number, len: number)
		api.box("Workbench", Vector3.new(2.4, 2.4, len), Vector3.new(X0 + 1.2, y1 + 1.2, z), col.Locker, M.Metal)
		api.box("WorkbenchTop", Vector3.new(2.7, 0.25, len + 0.2), Vector3.new(X0 + 1.35, y1 + 2.525, z), col.Metal, M.DiamondPlate)
		api.box("Pegboard", Vector3.new(0.15, 4.0, len), Vector3.new(X0 + 0.075, y1 + 5.2, z), col.Dark, M.Metal, false)
	end
	bench(0, 6.0)
	api.box("BenchVice", Vector3.new(0.9, 0.6, 0.6), Vector3.new(X0 + 2.0, y1 + 2.95, 2.2), col.Metal, M.Metal, false)
	api.box("Wrench", Vector3.new(0.1, 1.8, 0.3), Vector3.new(X0 + 0.2, y1 + 5.6, -1.4), col.Metal, M.Metal, false)
	api.box("Hammer", Vector3.new(0.1, 0.4, 1.2), Vector3.new(X0 + 0.2, y1 + 6.4, 0.6), col.Metal, M.Metal, false)
	if lv >= 2 then
		bench(-11.1, 3.8)
		api.box("ToolChest", Vector3.new(1.3, 3.0, 2.0), Vector3.new(X0 + 0.65, y1 + 1.5, -4.6), col.Locker, M.Metal)
	end

	------------------------------------------------------------------------------------------------
	-- Tyre stack (between bays 2 and 1) and fuel drums (back-east corner)
	------------------------------------------------------------------------------------------------
	for k = 0, 2 do
		cyl("Tyre", 0.8, 2.2, CFrame.new(-3.9, y1 + 0.4 + k * 0.8, Z0 + 1.4) * UP, col.Dark, M.Fabric)
	end
	local drumBase = y1
	if lv >= 2 then
		api.box("SpillPallet", Vector3.new(3.6, 0.3, 3.8), Vector3.new(X1 - 1.8, y1 + 0.15, Z0 + 1.9), col.Dark, M.Metal)
		drumBase = y1 + 0.3
	end
	local drums = { { X1 - 2.7, Z0 + 0.95 }, { X1 - 0.9, Z0 + 0.95 } }
	if lv >= 2 then
		table.insert(drums, { X1 - 2.7, Z0 + 2.85 })
		table.insert(drums, { X1 - 0.9, Z0 + 2.85 })
	end
	for i, d in ipairs(drums) do
		cyl("FuelDrum", 2.8, 1.7, CFrame.new(d[1], drumBase + 1.4, d[2]) * UP, if i % 2 == 0 then col.Trim else col.Locker, M.Metal)
	end

	------------------------------------------------------------------------------------------------
	-- Wall signage
	------------------------------------------------------------------------------------------------
	local sign = api.box("MotorPoolSign", Vector3.new(12, 2.2, 0.15), Vector3.new(liftX, y1 + 10.6, Z0 + 0.075), col.Dark, M.Metal, false)
	api.surfaceText(sign, Enum.NormalId.Back, { "MOTOR POOL", "DEPOT LEVEL " .. tostring(lv) }, col.Accent, col.Dark, Enum.Font.GothamBlack)
	if lv >= 2 then
		local ns = api.box("FuelStoreSign", Vector3.new(3.6, 1.4, 0.12), Vector3.new(X1 - 1.8, y1 + 5.0, Z0 + 0.06), col.Dark, M.Metal, false)
		api.surfaceText(ns, Enum.NormalId.Back, { "FUEL STORE", "NO NAKED FLAMES" }, col.Accent, col.Dark, Enum.Font.GothamBold)
		api.box("Extinguisher", Vector3.new(0.6, 1.4, 0.5), Vector3.new(12.3, y1 + 2.2, Z1 - 0.25), Color3.fromRGB(140, 30, 26), M.SmoothPlastic, false)
	end

	------------------------------------------------------------------------------------------------
	-- L3: Bay 2 (west) — utility jeep
	------------------------------------------------------------------------------------------------
	if lv >= 3 then
		local bx0, bx1 = -12.4, -5.2
		for _, lx in ipairs({ bx0, bx1 }) do
			line(0.3, 12.2, lx, Z0 + 0.4 + 6.1, col.Accent)
		end
		floorStencil((bx0 + bx1) * 0.5, 0.8, 5, { "BAY 2" })
		stain(-8.2, -2.4, 1.8)

		local cx, cz = (bx0 + bx1) * 0.5, -6.8
		for _, wz in ipairs({ 2.3, -2.3 }) do
			for _, sx in ipairs({ -1, 1 }) do
				cyl("JeepTyre", 0.8, 2.0, CFrame.new(cx + sx * 1.7, y1 + 1.0, cz + wz), col.Dark, M.Fabric, false)
			end
		end
		api.box("JeepBody", Vector3.new(3.6, 1.1, 6.6), Vector3.new(cx, y1 + 1.45, cz), col.Locker, M.Metal)
		local hood = api.box("JeepBonnet", Vector3.new(3.4, 0.45, 2.2), Vector3.new(cx, y1 + 2.225, cz + 2.1), col.Locker, M.Metal, false)
		paint(hood, Enum.NormalId.Top, { "★" }, paintWhite)
		local ws = api.box("JeepWindshield", Vector3.new(3.4, 1.3, 0.12), Vector3.new(cx, y1 + 2.65, cz + 0.95), tint, M.Glass, false)
		ws.Transparency = 0.3
		api.box("JeepSeats", Vector3.new(3.0, 1.2, 1.0), Vector3.new(cx, y1 + 2.6, cz - 0.4), col.Dark, M.Fabric, false)
		api.box("JeepGrille", Vector3.new(2.0, 0.8, 0.1), Vector3.new(cx, y1 + 1.5, cz + 3.35), col.Dark, M.Metal, false)
		for _, sx in ipairs({ -1, 1 }) do
			api.box("JeepHeadlight", Vector3.new(0.45, 0.45, 0.1), Vector3.new(cx + sx * 1.35, y1 + 1.65, cz + 3.35), col.Light, M.Glass, false)
		end
		cyl("JeepSpare", 0.7, 1.7, CFrame.new(cx, y1 + 1.9, cz - 3.65) * ALONG_Z, col.Dark, M.Fabric, false)
		api.box("JeepAntenna", Vector3.new(0.1, 4.5, 0.1), Vector3.new(cx + 1.5, y1 + 4.25, cz - 3.0), col.Metal, M.Metal, false)
	end

	------------------------------------------------------------------------------------------------
	-- L4: air compressor (east wall, under the window), mechanic's creeper under the truck
	------------------------------------------------------------------------------------------------
	if lv >= 4 then
		cyl("CompressorTank", 2.6, 1.2, CFrame.new(X1 - 0.8, y1 + 0.9, 5.7) * ALONG_Z, col.Locker, M.Metal)
		api.box("CompressorMotor", Vector3.new(1.0, 0.8, 1.2), Vector3.new(X1 - 0.8, y1 + 1.9, 5.2), col.Dark, M.Metal)
		api.box("Creeper", Vector3.new(1.3, 0.3, 2.8), Vector3.new(liftX, y1 + 0.35, -7.5), col.Locker, M.Metal, false)
	end

	------------------------------------------------------------------------------------------------
	-- L5: Bay 3 (east) — fuel bowser trailer
	------------------------------------------------------------------------------------------------
	if lv >= 5 then
		local bx0, bx1 = 7.6, 13.4
		for _, lx in ipairs({ bx0, bx1 }) do
			line(0.3, 12.2, lx, Z0 + 0.4 + 6.1, col.Accent)
		end
		floorStencil((bx0 + bx1) * 0.5, 0.8, 5, { "BAY 3" })
		stain(10.9, -1.6, 1.6)

		local tx, tz = (bx0 + bx1) * 0.5, -7.0
		cyl("BowserTank", 7.0, 3.0, CFrame.new(tx, y1 + 2.9, tz) * ALONG_Z, col.Locker, M.Metal)
		api.box("BowserChassis", Vector3.new(2.4, 0.5, 7.2), Vector3.new(tx, y1 + 1.15, tz), col.Dark, M.Metal)
		for _, wz in ipairs({ -1.4, -3.3 }) do
			for _, sx in ipairs({ -1, 1 }) do
				cyl("BowserTyre", 0.8, 1.8, CFrame.new(tx + sx * 1.6, y1 + 0.9, tz + wz), col.Dark, M.Fabric, false)
			end
		end
		api.box("BowserDrawbar", Vector3.new(0.4, 0.4, 2.6), Vector3.new(tx, y1 + 1.0, tz + 4.9), col.Metal, M.Metal, false)
		local plac = api.box("BowserPlacard", Vector3.new(0.1, 1.2, 1.8), Vector3.new(tx - 1.55, y1 + 2.9, tz + 1.5), col.Accent, M.SmoothPlastic, false)
		api.surfaceText(plac, Enum.NormalId.Left, { "FUEL" }, col.Dark, col.Accent, Enum.Font.GothamBlack)
	end
end
