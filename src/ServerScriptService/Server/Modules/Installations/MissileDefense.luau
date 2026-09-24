--!strict
--[[
	Missile Defense installation (HollowBuildingBuilder, StructureVisualConfig.Installations). 24 x 22 battery
	inside a sandbag berm (gap at the front for the kiosk path): launcher(s) on turntables, fire-control
	truck with a spinning radar, missile crates.
	L1 one 2-tube launcher   L2 fire-control truck   L3 4-tube launcher, blast walls
	L4 second launcher       L5 6-tube launchers, floodlights, gold stripe
]]

return function(ictx: any, api: any)
	local col = ictx.Colors
	local lv = ictx.Level
	local y0 = ictx.Y0
	local hw, hd = ictx.HalfW, ictx.HalfD
	local olive = col.Locker
	local tubeEnd = Color3.fromRGB(34, 36, 34)

	-- Sandbag berm around the battery, open at the front centre (x -3..3)
	api.sandbags(-hw + 1, -3, hd - 1, y0)
	api.sandbags(3, hw - 1, hd - 1, y0)
	api.sandbags(-hw + 1, hw - 1, -hd + 1, y0)
	for _, sx in ipairs({ -hw + 1, hw - 1 }) do
		local n = math.floor((ictx.D - 4) / 2.1)
		for i = 0, n - 1 do
			api.box("Sandbag", Vector3.new(1.5, 1.0, 2.0), Vector3.new(sx, y0 + 0.5, -hd + 2 + (i + 0.5) * ((ictx.D - 4) / n)), col.Sandbag, Enum.Material.Fabric)
		end
	end

	-- Launcher on a turntable: canister pack tilted 35° up toward the back (-Z)
	local function launcher(lx: number, lz: number, tubes: number)
		api.cylinder("Turntable", Vector3.new(1.2, 7, 7), CFrame.new(lx, y0 + 0.6, lz) * CFrame.Angles(0, 0, math.rad(90)), col.Dark, Enum.Material.Metal)
		api.box("LauncherPedestal", Vector3.new(2.4, 2.4, 2.4), Vector3.new(lx, y0 + 2.4, lz), col.Metal, Enum.Material.Metal)
		local cols = if tubes >= 6 then 3 else if tubes >= 4 then 2 else 1
		local rows = if tubes >= 2 then 2 else 1
		local packW, packH, packL = cols * 1.7 + 0.6, rows * 1.7 + 0.6, 8
		local pack = CFrame.new(lx, y0 + 3.6 + packH * 0.5, lz) * CFrame.Angles(math.rad(35), 0, 0)
		api.part("LauncherPack", Vector3.new(packW, packH, packL), pack, olive, Enum.Material.Metal)
		api.part("LauncherStripe", Vector3.new(packW + 0.05, 0.3, packL + 0.05), pack * CFrame.new(0, packH * 0.5 - 0.4, 0), if lv >= 5 then col.Gold else col.Accent, Enum.Material.SmoothPlastic, false)
		for c = 1, cols do
			for r = 1, rows do
				local ox = (c - (cols + 1) * 0.5) * 1.7
				local oy = (r - (rows + 1) * 0.5) * 1.7
				-- tube mouths on the raised (-Z) end
				api.cylinder("TubeMouth", Vector3.new(0.3, 1.3, 1.3), pack * CFrame.new(ox, oy, -packL * 0.5 - 0.1) * CFrame.Angles(0, math.rad(90), 0), tubeEnd, Enum.Material.Metal, false)
				api.cylinder("MissileTip", Vector3.new(0.5, 0.6, 0.6), pack * CFrame.new(ox, oy, -packL * 0.5 + 0.1) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(200, 60, 50), Enum.Material.SmoothPlastic, false)
			end
		end
	end
	local tubes = if lv >= 5 then 6 elseif lv >= 3 then 4 else 2
	if lv >= 4 then
		launcher(-5.5, -3, tubes)
		launcher(5.5, -3, tubes)
	else
		launcher(0, -3, tubes)
	end

	-- Fire-control truck with spinning radar (L2+)
	if lv >= 2 then
		local tx, tz = 6.5, 5.5
		api.box("TruckCab", Vector3.new(3, 2.6, 2.6), Vector3.new(tx - 3.4, y0 + 1.9, tz), olive, Enum.Material.Metal)
		local ws = api.box("TruckWindshield", Vector3.new(0.15, 1, 2.2), Vector3.new(tx - 4.95, y0 + 2.5, tz), col.Glass, Enum.Material.Glass, false)
		ws.Transparency = 0.3
		api.box("TruckBody", Vector3.new(5.6, 3, 2.8), Vector3.new(tx + 0.9, y0 + 2.1, tz), olive, Enum.Material.Metal)
		for _, wx in ipairs({ tx - 3.4, tx - 0.4, tx + 2.6 }) do
			for _, side in ipairs({ -1, 1 }) do
				api.cylinder("TruckWheel", Vector3.new(0.6, 1.4, 1.4), CFrame.new(wx, y0 + 0.7, tz + side * 1.35) * CFrame.Angles(0, math.rad(90), 0), tubeEnd, Enum.Material.Fabric, false)
			end
		end
		api.box("RadarMount", Vector3.new(0.5, 1.2, 0.5), Vector3.new(tx + 1.5, y0 + 4.2, tz), col.Metal, Enum.Material.Metal, false)
		local panel = api.part("FireControlRadar", Vector3.new(3.4, 1.8, 0.3), CFrame.new(tx + 1.5, y0 + 5.4, tz) * CFrame.Angles(math.rad(-15), 0, 0), col.Dark, Enum.Material.Metal, false)
		api.spin({ panel }, Vector3.new(tx + 1.5, 0, tz), 14)
	end

	-- Missile crates (grow with level)
	local crates = math.min(2 + lv, 6)
	for i = 0, crates - 1 do
		local cx = -hw + 3.2 + (i % 3) * 2.4
		local cz = 3 + math.floor(i / 3) * 1.6
		api.box("MissileCrate", Vector3.new(2.2, 1.1, 1.4), Vector3.new(cx, y0 + 0.55, cz), olive, Enum.Material.Wood)
		api.box("CrateStencil", Vector3.new(0.8, 0.3, 1.42), Vector3.new(cx, y0 + 0.6, cz), col.Accent, Enum.Material.SmoothPlastic, false)
	end

	-- Blast walls behind the launchers (L3+)
	if lv >= 3 then
		for _, bx in ipairs({ -6, 0, 6 }) do
			api.box("BlastWall", Vector3.new(5.6, 3.2, 0.9), Vector3.new(bx, y0 + 1.6, -hd + 3.2), col.Wall, Enum.Material.Concrete)
		end
	end

	-- Floodlights on poles (L5)
	if lv >= 5 then
		for _, fx in ipairs({ -hw + 2, hw - 2 }) do
			api.box("FloodPole", Vector3.new(0.3, 7, 0.3), Vector3.new(fx, y0 + 3.5, hd - 2.5), col.Metal, Enum.Material.Metal, false)
			local lens = api.box("FloodLamp", Vector3.new(1.4, 0.8, 0.5), Vector3.new(fx, y0 + 7, hd - 2.8), col.Light, Enum.Material.Neon, false)
			api.light(lens, 20, 1.2, col.Light)
		end
	end
end
