--!strict
--[[
	Airfield installation (HollowBuildingBuilder, StructureVisualConfig.Installations). 58 x 34 behind the
	runway (BaseLayoutConfig Roads: Runway + HangarApron); +Z faces the runway. The runway itself is layout
	ground, so this is the hangar side of the airfield.
	L1 walk-in hangar (open sliding doors) with one jet + hangar terminal (Garage), windsock
	L2 control tower   L3 fuel truck, tool carts   L4 second jet   L5 floodlights, gold header trim
]]

return function(ictx: any, api: any)
	local col = ictx.Colors
	local lv = ictx.Level
	local y0 = ictx.Y0
	local hullGrey = Color3.fromRGB(128, 134, 138)
	local wallCol = Color3.fromRGB(150, 150, 140)
	local roofCol = Color3.fromRGB(92, 96, 90)

	-- Hangar shell: 40 wide x 28 deep, 15 to the eaves, gable roof ridge front-to-back
	local hx, hW, hD, H, t = -2, 40, 28, 15, 0.8
	local hw, hd = hW * 0.5, hD * 0.5
	local doorW, doorH = 32, 13
	api.box("HangarBack", Vector3.new(hW, H, t), Vector3.new(hx, y0 + H * 0.5, -hd + t * 0.5), wallCol, Enum.Material.CorrodedMetal)
	for _, side in ipairs({ -1, 1 }) do
		api.box("HangarSide", Vector3.new(t, H, hD), Vector3.new(hx + side * (hw - t * 0.5), y0 + H * 0.5, 0), wallCol, Enum.Material.CorrodedMetal)
		local pier = (hW - doorW) * 0.5
		api.box("HangarPier", Vector3.new(pier, doorH, t), Vector3.new(hx + side * (hw - pier * 0.5), y0 + doorH * 0.5, hd - t * 0.5), wallCol, Enum.Material.CorrodedMetal)
		-- sliding door leaves parked open outside the piers
		api.box("HangarDoorLeaf", Vector3.new(doorW * 0.25, doorH - 0.2, 0.4), Vector3.new(hx + side * (hw + doorW * 0.125 - 0.2), y0 + (doorH - 0.2) * 0.5, hd + 0.3), col.Metal, Enum.Material.DiamondPlate)
		api.box("DoorLeafStripe", Vector3.new(doorW * 0.25, 0.5, 0.42), Vector3.new(hx + side * (hw + doorW * 0.125 - 0.2), y0 + 1.2, hd + 0.3), col.Accent, Enum.Material.SmoothPlastic, false)
	end
	api.box("HangarHeader", Vector3.new(hW, H - doorH, t), Vector3.new(hx, y0 + doorH + (H - doorH) * 0.5, hd - t * 0.5), wallCol, Enum.Material.CorrodedMetal)
	local sign = api.box("HangarSign", Vector3.new(12, 1.4, 0.2), Vector3.new(hx, y0 + doorH + 1, hd + 0.12), col.Dark, Enum.Material.Metal, false)
	api.surfaceText(sign, Enum.NormalId.Back, { "HANGAR 01" }, col.Accent, col.Dark, Enum.Font.GothamBlack)
	-- Gable roof: two panels meeting at a ridge over the centre line, stepped gable infill front + back
	local pitch = math.rad(12)
	local rise = hw * math.tan(pitch)
	for _, side in ipairs({ -1, 1 }) do
		api.part("HangarRoof", Vector3.new(hw / math.cos(pitch) + 0.8, 0.6, hD + 1.2), CFrame.new(hx + side * hw * 0.5, y0 + H + rise * 0.5 + 0.3, 0) * CFrame.Angles(0, 0, -side * pitch), roofCol, Enum.Material.Metal)
	end
	for _, gz in ipairs({ hd - t * 0.5, -hd + t * 0.5 }) do
		for k = 1, 3 do
			local w = hW * (1 - k / 3.4)
			api.box("GableInfill", Vector3.new(w, rise / 3, t), Vector3.new(hx, y0 + H + (k - 0.5) * rise / 3, gz), wallCol, Enum.Material.CorrodedMetal)
		end
	end
	-- Hangar lights
	for i = -1, 1 do
		local lamp = api.box("HangarLight", Vector3.new(6, 0.25, 1), Vector3.new(hx + i * 12, y0 + H - 0.4, 0), col.Light, Enum.Material.Neon, false)
		api.light(lamp, 26, 1.1, col.Light)
	end
	api.box("TaxiLine", Vector3.new(0.5, 0.05, hD - 2), Vector3.new(hx, y0 + 0.03, 0.5), col.Accent, Enum.Material.SmoothPlastic, false)

	-- Generic jet mock-up (no real-world type or markings), nose toward the doors (+Z)
	local function jet(cx: number, cz: number)
		local f = CFrame.new(cx, y0 + 2.4, cz)
		api.part("JetFuselage", Vector3.new(15, 2.2, 2.2), f * CFrame.Angles(0, math.rad(90), 0), hullGrey, Enum.Material.Metal).Shape = Enum.PartType.Cylinder
		local nose = api.part("JetNose", Vector3.new(2.2, 2.2, 2.2), f * CFrame.new(0, 0, 7.5), hullGrey, Enum.Material.Metal)
		nose.Shape = Enum.PartType.Ball
		local canopy = api.part("JetCanopy", Vector3.new(1.6, 1.4, 3.4), f * CFrame.new(0, 1.1, 4.6), Color3.fromRGB(40, 60, 80), Enum.Material.Glass, false)
		canopy.Transparency = 0.2
		api.part("JetWing", Vector3.new(12, 0.3, 4.4), f * CFrame.new(0, -0.3, -0.5), hullGrey, Enum.Material.Metal)
		api.part("JetTailplane", Vector3.new(5.2, 0.25, 2), f * CFrame.new(0, 0, -6.3), hullGrey, Enum.Material.Metal, false)
		api.part("JetFin", Vector3.new(0.3, 3.2, 2.6), f * CFrame.new(0, 2.4, -6), hullGrey, Enum.Material.Metal, false)
		api.part("JetExhaust", Vector3.new(0.8, 1.6, 1.6), f * CFrame.new(0, 0, -7.9) * CFrame.Angles(0, math.rad(90), 0), col.Dark, Enum.Material.Metal, false).Shape = Enum.PartType.Cylinder
		for _, g in ipairs({ { 0, 5 }, { -2.2, -1 }, { 2.2, -1 } }) do
			api.part("JetGear", Vector3.new(0.3, 1.3, 0.3), f * CFrame.new(g[1], -1.65, g[2]), col.Dark, Enum.Material.Metal, false)
		end
		api.part("JetRoundel", Vector3.new(1.6, 0.05, 1.6), f * CFrame.new(-4.2, -0.12, -0.5), col.Flag, Enum.Material.SmoothPlastic, false)
		api.part("JetRoundel", Vector3.new(1.6, 0.05, 1.6), f * CFrame.new(4.2, -0.12, -0.5), col.Flag, Enum.Material.SmoothPlastic, false)
	end
	if lv >= 4 then
		jet(hx - 9.5, 0)
		jet(hx + 9.5, -1.5)
	else
		jet(hx, 0)
	end

	-- Hangar terminal on the back wall (right of centre) → Garage (aircraft need the Airfield)
	api.terminal("HangarTerminal", Vector3.new(hx + 14, y0, -hd + t + 0.6), 0, "Garage", "Open hangar", "Hangar · Aircraft", { "HANGAR", "AIRCRAFT" })

	-- Windsock
	api.box("WindsockPole", Vector3.new(0.35, 8, 0.35), Vector3.new(-27, y0 + 4, -15), col.Metal, Enum.Material.Metal, false)
	api.part("Windsock", Vector3.new(0.9, 0.9, 3), CFrame.new(-27, y0 + 7.6, -13.4) * CFrame.Angles(math.rad(8), 0, 0), Color3.fromRGB(230, 120, 40), Enum.Material.Fabric, false)

	-- Control tower (L2+) at the runway corner
	if lv >= 2 then
		local tx, tz, th = 23.5, 9, 18
		api.box("TowerShaft", Vector3.new(4, th, 4), Vector3.new(tx, y0 + th * 0.5, tz), wallCol, Enum.Material.Concrete)
		api.box("TowerDeck", Vector3.new(7, 0.5, 7), Vector3.new(tx, y0 + th + 0.25, tz), col.Metal, Enum.Material.Metal)
		local cab = api.box("TowerCab", Vector3.new(6.2, 3.4, 6.2), Vector3.new(tx, y0 + th + 2.2, tz), col.Glass, Enum.Material.Glass)
		cab.Transparency = 0.35
		api.box("TowerCabRoof", Vector3.new(7.2, 0.5, 7.2), Vector3.new(tx, y0 + th + 4.15, tz), col.Trim, Enum.Material.Metal)
		api.box("TowerMast", Vector3.new(0.3, 4, 0.3), Vector3.new(tx + 2.5, y0 + th + 6.4, tz - 2.5), col.Metal, Enum.Material.Metal, false)
		local beacon = api.ball("TowerBeacon", 0.7, Vector3.new(tx + 2.5, y0 + th + 8.6, tz - 2.5), Color3.fromRGB(255, 50, 40), Enum.Material.Neon, false)
		api.light(beacon, 10, 1.5, Color3.fromRGB(255, 60, 40))
		api.box("TowerDoor", Vector3.new(1.8, 3, 0.15), Vector3.new(tx, y0 + 1.5, tz + 2.08), col.Metal, Enum.Material.Metal, false)
	end

	-- Fuel truck + tool carts (L3+)
	if lv >= 3 then
		local fx, fz = 23.5, -7
		api.box("FuelTruckCab", Vector3.new(2.6, 2.6, 2.8), Vector3.new(fx, y0 + 1.9, fz + 4.4), col.Locker, Enum.Material.Metal)
		api.part("FuelTruckTank", Vector3.new(6.4, 2.6, 2.6), CFrame.new(fx, y0 + 2.2, fz) * CFrame.Angles(0, math.rad(90), 0), col.Locker, Enum.Material.Metal).Shape = Enum.PartType.Cylinder
		api.box("FuelTruckChassis", Vector3.new(2.4, 0.5, 9.4), Vector3.new(fx, y0 + 0.75, fz + 1.2), col.Dark, Enum.Material.Metal, false)
		for _, wz in ipairs({ fz + 4.6, fz - 0.6, fz - 2.6 }) do
			for _, side in ipairs({ -1, 1 }) do
				api.part("FuelTruckWheel", Vector3.new(0.5, 1.3, 1.3), CFrame.new(fx + side * 1.2, y0 + 0.65, wz), col.Dark, Enum.Material.Fabric, false).Shape = Enum.PartType.Cylinder
			end
		end
		for i = 0, 1 do
			local cx = hx - hw + 3 + i * 3
			api.box("ToolCart", Vector3.new(2, 2.2, 1.2), Vector3.new(cx, y0 + 1.1, -hd + 2.2), Color3.fromRGB(150, 40, 36), Enum.Material.Metal)
		end
		for i = 0, 2 do
			api.part("FuelDrum", Vector3.new(1.5, 1.1, 1.1), CFrame.new(hx + hw - 2, y0 + 0.75, -hd + 2.2 + i * 1.3) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(110, 58, 40), Enum.Material.Metal).Shape = Enum.PartType.Cylinder
		end
	end

	-- L5: floodlights on the hangar corners + gold header trim
	if lv >= 5 then
		api.box("GoldTrim", Vector3.new(hW, 0.35, 0.35), Vector3.new(hx, y0 + H + 0.2, hd + 0.2), col.Gold, Enum.Material.Metal, false)
		for _, side in ipairs({ -1, 1 }) do
			local lens = api.box("FloodLamp", Vector3.new(1.6, 0.9, 0.5), Vector3.new(hx + side * (hw - 1.5), y0 + H - 0.6, hd + 0.5), col.Light, Enum.Material.Neon, false)
			api.light(lens, 30, 1.4, col.Light)
		end
	end
end
