--!strict
--[[
	Power Station installation (HollowBuildingBuilder, StructureVisualConfig.Installations). 30 x 22 fenced
	substation yard; the kiosk stands outside the front gate (+Z).
	L1 generator hall + transformer + fence   L2 second transformer + cable trays
	L3 transmission pylon                     L4 solar array           L5 roof fans, gold trim, beacon
]]

return function(ictx: any, api: any)
	local col = ictx.Colors
	local lv = ictx.Level
	local y0 = ictx.Y0
	local hw, hd = ictx.HalfW, ictx.HalfD
	local fenceCol = Color3.fromRGB(120, 124, 120)

	-- L5 gold edge band around a roof (matches the walk-in buildings' gold parapet cap)
	local function goldEdge(cx: number, y: number, cz: number, w: number, d: number)
		api.box("GoldTrim", Vector3.new(w, 0.3, 0.3), Vector3.new(cx, y, cz + d * 0.5), col.Gold, Enum.Material.Metal, false)
		api.box("GoldTrim", Vector3.new(w, 0.3, 0.3), Vector3.new(cx, y, cz - d * 0.5), col.Gold, Enum.Material.Metal, false)
		api.box("GoldTrim", Vector3.new(0.3, 0.3, d), Vector3.new(cx + w * 0.5, y, cz), col.Gold, Enum.Material.Metal, false)
		api.box("GoldTrim", Vector3.new(0.3, 0.3, d), Vector3.new(cx - w * 0.5, y, cz), col.Gold, Enum.Material.Metal, false)
	end

	-- A beam between two building-local points (not vertical)
	local function beam(name: string, a: Vector3, b: Vector3, thick: number, color: Color3)
		local mid = (a + b) * 0.5
		api.part(name, Vector3.new(thick, thick, (b - a).Magnitude), CFrame.lookAt(mid, b), color, Enum.Material.Metal, false)
	end

	-- Perimeter fence with a front gate opening (x -3.5..3.5)
	local fx0, fx1, fz0, fz1 = -hw + 0.5, hw - 0.5, -hd + 0.5, hd - 0.5
	local fenceH = 5
	local function fenceRun(ax: number, az: number, bx: number, bz: number)
		local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		if len < 0.5 then
			return
		end
		local mid = Vector3.new((ax + bx) * 0.5, y0 + fenceH * 0.5, (az + bz) * 0.5)
		local alongX = math.abs(bx - ax) > math.abs(bz - az)
		local size = if alongX then Vector3.new(len, fenceH, 0.12) else Vector3.new(0.12, fenceH, len)
		local mesh = api.box("FenceMesh", size, mid, fenceCol, Enum.Material.DiamondPlate)
		mesh.Transparency = 0.55
		local rail = if alongX then Vector3.new(len, 0.2, 0.2) else Vector3.new(0.2, 0.2, len)
		api.box("FenceRail", rail, Vector3.new(mid.X, y0 + fenceH, mid.Z), col.Metal, Enum.Material.Metal, false)
		local posts = math.max(1, math.floor(len / 3.5))
		for i = 0, posts do
			local t = i / posts
			api.box("FencePost", Vector3.new(0.3, fenceH + 0.4, 0.3), Vector3.new(ax + (bx - ax) * t, y0 + (fenceH + 0.4) * 0.5, az + (bz - az) * t), col.Metal, Enum.Material.Metal, false)
		end
	end
	fenceRun(fx0, fz0, fx1, fz0)
	fenceRun(fx0, fz0, fx0, fz1)
	fenceRun(fx1, fz0, fx1, fz1)
	fenceRun(fx0, fz1, -3.5, fz1)
	fenceRun(3.5, fz1, fx1, fz1)
	local warnSign = api.box("DangerSign", Vector3.new(3.2, 1.6, 0.1), Vector3.new(-7, y0 + 3, fz1 + 0.12), Color3.fromRGB(230, 196, 70), Enum.Material.SmoothPlastic, false)
	api.surfaceText(warnSign, Enum.NormalId.Back, { "⚡ DANGER", "HIGH VOLTAGE" }, Color3.fromRGB(20, 20, 20), Color3.fromRGB(230, 196, 70), Enum.Font.GothamBlack)

	-- Generator hall (back-left): solid block with a roll-up door, stacks, sign
	local hx, hz, hW, hD, hH = -8, -4, 12, 10, 8
	api.box("GenHall", Vector3.new(hW, hH, hD), Vector3.new(hx, y0 + hH * 0.5, hz), col.Wall, Enum.Material.Concrete)
	api.box("GenHallRoof", Vector3.new(hW + 0.6, 0.6, hD + 0.6), Vector3.new(hx, y0 + hH + 0.3, hz), col.Trim, Enum.Material.Metal)
	if lv >= 5 then
		goldEdge(hx, y0 + hH + 0.75, hz, hW + 0.6, hD + 0.6)
	end
	api.box("GenDoor", Vector3.new(5, 5.5, 0.2), Vector3.new(hx + 1, y0 + 2.75, hz + hD * 0.5 + 0.1), col.Metal, Enum.Material.DiamondPlate, false)
	api.box("GenDoorStripe", Vector3.new(5, 0.4, 0.22), Vector3.new(hx + 1, y0 + 5.7, hz + hD * 0.5 + 0.11), col.Accent, Enum.Material.SmoothPlastic, false)
	local sign = api.box("GenSign", Vector3.new(7, 1.3, 0.2), Vector3.new(hx, y0 + 7, hz + hD * 0.5 + 0.12), col.Dark, Enum.Material.Metal, false)
	api.surfaceText(sign, Enum.NormalId.Back, { "POWER STATION" }, col.Accent, col.Dark, Enum.Font.GothamBlack)
	for i, sx in ipairs({ hx - 3.5, hx + 3.5 }) do
		if i == 1 or lv >= 2 then
			api.cylinder("ExhaustStack", Vector3.new(5, 1.1, 1.1), CFrame.new(sx, y0 + hH + 2.5, hz - 2.5) * CFrame.Angles(0, 0, math.rad(90)), col.Dark, Enum.Material.Metal)
		end
	end
	api.box("GenVent", Vector3.new(3, 1, 2), Vector3.new(hx, y0 + hH + 1.1, hz + 1.5), col.Metal, Enum.Material.DiamondPlate)
	if lv >= 5 then
		for _, fx in ipairs({ hx - 3, hx + 3 }) do
			api.cylinder("RoofFan", Vector3.new(0.6, 3, 3), CFrame.new(fx, y0 + hH + 0.9, hz + 2.5) * CFrame.Angles(0, 0, math.rad(90)), col.Metal, Enum.Material.Metal)
		end
	end

	-- Transformers (right of the hall)
	local function transformer(tx: number, tz: number)
		api.box("Transformer", Vector3.new(4, 3.6, 3.4), Vector3.new(tx, y0 + 1.8, tz), col.Locker, Enum.Material.Metal)
		for i = -2, 2 do
			api.box("CoolingFin", Vector3.new(0.15, 2.8, 1.2), Vector3.new(tx + i * 0.7, y0 + 1.8, tz + 2.3), col.Metal, Enum.Material.Metal, false)
		end
		for i = -1, 1 do
			api.cylinder("Bushing", Vector3.new(1.4, 0.45, 0.45), CFrame.new(tx + i * 1.2, y0 + 4.3, tz - 0.6) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(150, 110, 70), Enum.Material.SmoothPlastic, false)
		end
		api.box("TransformerPlinth", Vector3.new(5, 0.4, 4.6), Vector3.new(tx, y0 + 0.2, tz + 0.5), col.Floor, Enum.Material.Concrete, false)
	end
	transformer(5, -5)
	if lv >= 2 then
		transformer(11, -5)
		api.box("CableTray", Vector3.new(14, 0.4, 0.8), Vector3.new(4, y0 + 0.2, -1.8), col.Dark, Enum.Material.Metal, false)
	end

	-- Transmission pylon (back-right corner) with insulators; beacon at L5
	if lv >= 3 then
		local px, pz, pH = 11, -8.5, 20
		for _, o in ipairs({ { -1.3, -1.3 }, { 1.3, -1.3 }, { -1.3, 1.3 }, { 1.3, 1.3 } }) do
			api.box("PylonLeg", Vector3.new(0.35, pH, 0.35), Vector3.new(px + o[1], y0 + pH * 0.5, pz + o[2]), col.Metal, Enum.Material.Metal)
		end
		for k = 0, 3 do
			local ya, yb = y0 + k * 4.5, y0 + (k + 1) * 4.5
			beam("PylonBrace", Vector3.new(px - 1.3, ya, pz + 1.3), Vector3.new(px + 1.3, yb, pz + 1.3), 0.2, col.Metal)
			beam("PylonBrace", Vector3.new(px + 1.3, ya, pz - 1.3), Vector3.new(px - 1.3, yb, pz - 1.3), 0.2, col.Metal)
			beam("PylonBrace", Vector3.new(px - 1.3, ya, pz - 1.3), Vector3.new(px - 1.3, yb, pz + 1.3), 0.2, col.Metal)
			beam("PylonBrace", Vector3.new(px + 1.3, ya, pz + 1.3), Vector3.new(px + 1.3, yb, pz - 1.3), 0.2, col.Metal)
		end
		for _, ay in ipairs({ pH - 1, pH - 5 }) do
			api.box("PylonArm", Vector3.new(9, 0.4, 0.4), Vector3.new(px - 1.5, y0 + ay, pz), col.Metal, Enum.Material.Metal, false)
			for _, ix in ipairs({ px - 5.5, px + 2.5 }) do
				api.cylinder("Insulator", Vector3.new(1.4, 0.5, 0.5), CFrame.new(ix, y0 + ay - 0.8, pz) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(150, 110, 70), Enum.Material.SmoothPlastic, false)
			end
		end
		if lv >= 5 then
			local b = api.ball("PylonBeacon", 0.8, Vector3.new(px, y0 + pH + 0.5, pz), Color3.fromRGB(255, 50, 40), Enum.Material.SmoothPlastic, false)
			api.light(b, 10, 1.5, Color3.fromRGB(255, 60, 40))
		end
	end

	-- Solar array (front-right) from L4: tilted panels on frames
	if lv >= 4 then
		for row = 0, 1 do
			for i = 0, 2 do
				local sx, sz = 5.6 + i * 3.4, 3.2 + row * 3.8
				api.box("SolarLeg", Vector3.new(0.25, 1.4, 0.25), Vector3.new(sx, y0 + 0.7, sz + 0.8), col.Metal, Enum.Material.Metal, false)
				api.part("SolarPanel", Vector3.new(3.2, 0.15, 2.4), CFrame.new(sx, y0 + 1.5, sz) * CFrame.Angles(math.rad(-25), 0, 0), Color3.fromRGB(30, 44, 70), Enum.Material.Glass)
			end
		end
	end

	-- Yard dressing: fuel tank + drums by the hall, yard lamp by the gate
	api.cylinder("FuelTank", Vector3.new(6, 2.6, 2.6), CFrame.new(-8, y0 + 1.5, 5), col.Locker, Enum.Material.Metal)
	api.box("FuelTankSaddle", Vector3.new(4.5, 0.6, 2), Vector3.new(-8, y0 + 0.3, 5), col.Dark, Enum.Material.Metal, false)
	for i = 0, 1 do
		api.cylinder("FuelDrum", Vector3.new(1.5, 1.1, 1.1), CFrame.new(-12.5 + i * 1.3, y0 + 0.75, 8.5) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(120, 60, 40), Enum.Material.Metal)
	end
	api.box("YardLampPole", Vector3.new(0.3, 7, 0.3), Vector3.new(4.5, y0 + 3.5, hd - 1.5), col.Metal, Enum.Material.Metal, false)
	local lamp = api.box("YardLamp", Vector3.new(1.4, 0.3, 0.8), Vector3.new(4.5, y0 + 7, hd - 2), col.Light, Enum.Material.SmoothPlastic, false)
	api.light(lamp, 18, 1.2, col.Light)
end
