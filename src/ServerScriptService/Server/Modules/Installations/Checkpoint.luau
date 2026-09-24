--!strict
--[[
	Gate checkpoint installation for DefensiveWalls (HollowBuildingBuilder, StructureVisualConfig.Installations).
	20 x 10 beside the main road just inside the main gate. The perimeter walls themselves are still built by
	StructureKitBuilder.SyncPerimeterWalls — this is the visible "defences" post at the gate.
	L1 guard booth, raised boom barrier, jersey barriers, floodlight   L2 razor wire
	L3 tank traps, more barriers   L4 sandbagged gun nest   L5 second floodlight, gold booth trim
]]

return function(ictx: any, api: any)
	local col = ictx.Colors
	local lv = ictx.Level
	local y0 = ictx.Y0
	local concrete = Color3.fromRGB(170, 166, 154)

	-- L5 gold edge band around a roof (matches the walk-in buildings' gold parapet cap)
	local function goldEdge(cx: number, y: number, cz: number, w: number, d: number)
		api.box("GoldTrim", Vector3.new(w, 0.3, 0.3), Vector3.new(cx, y, cz + d * 0.5), col.Gold, Enum.Material.Metal, false)
		api.box("GoldTrim", Vector3.new(w, 0.3, 0.3), Vector3.new(cx, y, cz - d * 0.5), col.Gold, Enum.Material.Metal, false)
		api.box("GoldTrim", Vector3.new(0.3, 0.3, d), Vector3.new(cx + w * 0.5, y, cz), col.Gold, Enum.Material.Metal, false)
		api.box("GoldTrim", Vector3.new(0.3, 0.3, d), Vector3.new(cx - w * 0.5, y, cz), col.Gold, Enum.Material.Metal, false)
	end

	-- Guard booth by the road (+X side), door facing the road
	local bx, bz = 6.2, 0
	api.box("Booth", Vector3.new(4.4, 3.4, 4.4), Vector3.new(bx, y0 + 1.7, bz), col.Wall, Enum.Material.Concrete)
	for _, w in ipairs({ { 0, -2.25, 0 }, { -2.25, 0, 90 }, { 0, 2.25, 0 } }) do
		local win = api.part("BoothWindow", Vector3.new(2.6, 1.3, 0.12), CFrame.new(bx + w[1], y0 + 2.4, bz + w[2]) * CFrame.Angles(0, math.rad(w[3]), 0), col.Glass, Enum.Material.Glass, false)
		win.Transparency = 0.25
	end
	api.box("BoothDoor", Vector3.new(0.12, 2.8, 1.6), Vector3.new(bx + 2.25, y0 + 1.4, bz), col.Metal, Enum.Material.Metal, false)
	api.box("BoothRoof", Vector3.new(5.6, 0.4, 5.6), Vector3.new(bx, y0 + 3.6, bz), col.Trim, Enum.Material.Metal)
	if lv >= 5 then
		goldEdge(bx, y0 + 3.95, bz, 5.6, 5.6)
	end
	local sign = api.box("BoothSign", Vector3.new(4.6, 0.9, 0.15), Vector3.new(bx, y0 + 4.3, bz - 2.3), col.Dark, Enum.Material.Metal, false)
	api.surfaceText(sign, Enum.NormalId.Front, { "CHECKPOINT" }, col.Accent, col.Dark, Enum.Font.GothamBlack)

	-- Boom barrier post at the road edge, arm raised (decorative, never blocks the road)
	api.box("BoomPost", Vector3.new(0.8, 2.2, 0.8), Vector3.new(9.4, y0 + 1.1, 3), col.Accent, Enum.Material.SmoothPlastic)
	api.part("BoomArm", Vector3.new(0.3, 0.3, 7), CFrame.new(9.4, y0 + 2.2, 3) * CFrame.Angles(math.rad(70), 0, 0) * CFrame.new(0, 0, -3.3), Color3.fromRGB(235, 235, 225), Enum.Material.SmoothPlastic, false)

	-- Jersey barriers along the front edge
	local n = if lv >= 3 then 5 else 3
	for i = 0, n - 1 do
		local x = -9 + i * 3.6
		api.box("JerseyBase", Vector3.new(3.4, 0.9, 1.4), Vector3.new(x, y0 + 0.45, 3.6), concrete, Enum.Material.Concrete)
		api.box("JerseyTop", Vector3.new(3.4, 1.7, 0.6), Vector3.new(x, y0 + 1.75, 3.6), concrete, Enum.Material.Concrete)
		api.box("JerseyStripe", Vector3.new(0.5, 0.9, 0.62), Vector3.new(x - 1.4, y0 + 1.9, 3.6), col.Accent, Enum.Material.SmoothPlastic, false)
		if lv >= 2 then
			local coil = api.cylinder("RazorWire", Vector3.new(3.3, 0.9, 0.9), CFrame.new(x, y0 + 3.05, 3.6), col.Metal, Enum.Material.DiamondPlate, false)
			coil.Transparency = 0.35
		end
	end

	-- Floodlights
	local function flood(fx: number, fz: number)
		api.box("FloodPole", Vector3.new(0.3, 7, 0.3), Vector3.new(fx, y0 + 3.5, fz), col.Metal, Enum.Material.Metal, false)
		local lamp = api.box("FloodLamp", Vector3.new(1.4, 0.8, 0.5), Vector3.new(fx, y0 + 7, fz + 0.3), col.Light, Enum.Material.Neon, false)
		api.light(lamp, 22, 1.3, col.Light)
	end
	flood(-9.4, -3.5)
	if lv >= 5 then
		flood(2.5, -3.5)
	end

	-- Czech hedgehog tank traps (L3+)
	if lv >= 3 then
		for i = 0, 2 do
			local tx = -8 + i * 3.4
			local c = CFrame.new(tx, y0 + 1.25, 0.2)
			api.part("TankTrap", Vector3.new(0.4, 0.4, 3), c * CFrame.Angles(math.rad(45), 0, 0), col.Dark, Enum.Material.Metal)
			api.part("TankTrap", Vector3.new(0.4, 0.4, 3), c * CFrame.Angles(0, 0, math.rad(45)) * CFrame.Angles(0, math.rad(90), 0), col.Dark, Enum.Material.Metal)
			api.part("TankTrap", Vector3.new(0.4, 0.4, 3), c * CFrame.Angles(0, math.rad(45), math.rad(-45)), col.Dark, Enum.Material.Metal)
		end
	end

	-- Sandbagged gun nest (L4+)
	if lv >= 4 then
		api.sandbags(-4.6, 0.2, -2.8, y0)
		api.box("NestTripod", Vector3.new(0.4, 1.4, 0.4), Vector3.new(-2.2, y0 + 0.7, -1.8), col.Metal, Enum.Material.Metal, false)
		api.box("NestGun", Vector3.new(0.5, 0.5, 1.6), Vector3.new(-2.2, y0 + 1.6, -1.6), col.Dark, Enum.Material.Metal, false)
	end
end
