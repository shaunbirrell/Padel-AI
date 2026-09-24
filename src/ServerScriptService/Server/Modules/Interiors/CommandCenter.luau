--!strict
--[[
	Command Center interior (HollowBuildingBuilder). Ground floor: command desk with three monitors, map table
	(opens the Base Upgrades menu), intel terminal (Missions), Missile Command terminal (Missiles), lockers, radio
	rack, wall screen. Upper floor (two storeys): strategy table, war-council terminal (Rebirth), bunk, weapon
	rack. The upgrade console stands inside by the door (BaseLayoutConfig).

	Layout (building-local, +Z = front/door): stairs run along the back wall from L3, so the west desk starts
	at z -1 to leave the foot of the stairs open. The east wall carries the annex doorway from L2 (z -5..-1).
]]

return function(ictx: any, api: any)
	local col = ictx.Colors
	local y1, y2 = ictx.Y1, ictx.Y2
	local X0, X1, Z0, Z1 = ictx.InX0, ictx.InX1, ictx.InZ0, ictx.InZ1
	local doorX = ictx.DoorX

	-- Command desk + monitors along the west wall (z -1..5, clear of the stair foot)
	local deskX = X0 + 1.3
	local deskZ = 2
	api.box("Desk", Vector3.new(2.2, 2.8, 6), Vector3.new(deskX, y1 + 1.4, deskZ), col.Dark, Enum.Material.Metal)
	api.box("DeskTop", Vector3.new(2.8, 0.3, 6.2), Vector3.new(deskX + 0.2, y1 + 2.95, deskZ), col.Metal, Enum.Material.Metal)
	local screenLines = {
		{ "SITREP", "ALL SECTORS", "GREEN" },
		{ "RADAR", "◆  ◇  ◆", "SWEEP" },
		{ "INTEL", "OUTPOSTS", "CONTESTED" },
	}
	for i, mz in ipairs({ -2, 0, 2 }) do
		local mon = api.box("Monitor", Vector3.new(0.25, 1.6, 1.9), Vector3.new(deskX - 0.5, y1 + 3.9, deskZ + mz), col.Dark, Enum.Material.Metal, false)
		api.surfaceText(mon, Enum.NormalId.Right, screenLines[i], col.Screen, Color3.fromRGB(8, 20, 12), Enum.Font.Code)
	end
	api.chair(Vector3.new(deskX + 2.4, y1, deskZ - 1), Vector3.new(-1, 0, 0))
	api.chair(Vector3.new(deskX + 2.4, y1, deskZ + 1.4), Vector3.new(-1, 0, 0))

	-- Map table (centre) — its prompt opens the Base Upgrades menu
	local mapX = -0.4
	api.box("MapTableBase", Vector3.new(6, 2.6, 3.6), Vector3.new(mapX, y1 + 1.3, 1.5), col.Dark, Enum.Material.Metal)
	local mapTop = api.box("MapTable", Vector3.new(6.6, 0.25, 4.2), Vector3.new(mapX, y1 + 2.72, 1.5), col.Trim, Enum.Material.Metal)
	do
		local sg = Instance.new("SurfaceGui")
		sg.Name = "WE_MapSurface"
		sg.Face = Enum.NormalId.Top
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 40
		sg.LightInfluence = 0
		sg.Parent = mapTop
		local bg = Instance.new("Frame")
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundColor3 = Color3.fromRGB(60, 78, 52)
		bg.BorderSizePixel = 0
		bg.Parent = sg
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.fromScale(0.3, 0.3)
		grid.CellPadding = UDim2.fromScale(0.033, 0.033)
		grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
		grid.VerticalAlignment = Enum.VerticalAlignment.Center
		grid.Parent = bg
		local cells = { "N", "", "OIL", "", "HQ", "", "FORT", "", "S" }
		for i, label in ipairs(cells) do
			local cell = Instance.new("TextLabel")
			cell.LayoutOrder = i
			cell.BackgroundColor3 = if label == "HQ" then col.Accent else Color3.fromRGB(96, 120, 78)
			cell.BorderSizePixel = 0
			cell.Font = Enum.Font.GothamBold
			cell.Text = label
			cell.TextScaled = true
			cell.TextColor3 = if label == "HQ" then col.Dark else Color3.fromRGB(230, 235, 220)
			cell.Parent = bg
		end
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WE_PanelPrompt"
	prompt.ActionText = "Plan upgrades"
	prompt.ObjectText = "Base Upgrades"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt:SetAttribute("WE_OpenPanel", "Base")
	prompt.Parent = mapTop

	-- Intel terminal on the east wall (between the annex doorway and the console) → Missions
	api.terminal("IntelTerminal", Vector3.new(X1 - 0.6, y1, 1.6), -90, "Missions", "Open briefings", "Intel · Missions", { "INTEL", "MISSIONS" })

	-- Missile Command terminal on the west wall, between the command desk and the foot of the stairs → Missiles
	api.terminal("MissileTerminal", Vector3.new(X0 + 0.6, y1, -2.4), 90, "Missiles", "Missile Command", "Missile Command", { "MISSILE", "COMMAND" })

	-- Door runner (inside the front wall)
	api.box("Runner", Vector3.new(3.4, 0.06, 7), Vector3.new(doorX, y1 + 0.03, Z1 - 3.7), col.Rug, Enum.Material.Fabric, false)

	-- Lockers in the front-west corner
	for i = 0, 1 do
		local lz = Z1 - 1.0 - i * 1.7
		api.box("Locker", Vector3.new(1.4, 7, 1.6), Vector3.new(X0 + 0.7, y1 + 3.5, lz), col.Locker, Enum.Material.Metal)
		api.box("LockerSeam", Vector3.new(0.1, 6.4, 0.08), Vector3.new(X0 + 1.42, y1 + 3.5, lz), col.Dark, Enum.Material.Metal, false)
	end

	-- Radio rack in the back-east corner
	api.box("RadioRack", Vector3.new(2, 5, 1.4), Vector3.new(X1 - 1.2, y1 + 2.5, Z0 + 0.7), col.Dark, Enum.Material.Metal)
	for i = 0, 2 do
		api.box("RackLed", Vector3.new(0.3, 0.3, 0.1), Vector3.new(X1 - 1.6 + i * 0.4, y1 + 3.8, Z0 + 1.45), if i == 1 then col.Accent else col.Screen, Enum.Material.Neon, false)
	end

	-- Wall screen on the east wall, above the intel terminal and the console
	local wallScreen = api.box("WallScreen", Vector3.new(0.2, 4, 7), Vector3.new(X1 - 0.1, y1 + 6.9, 4.7), col.Dark, Enum.Material.Metal, false)
	api.surfaceText(wallScreen, Enum.NormalId.Left, { "WAR EMPIRE · HQ", "LEVEL " .. tostring(ictx.Level), "BUILD. CONQUER. DOMINATE." }, col.Accent, Color3.fromRGB(10, 14, 12), Enum.Font.GothamBold)

	-- Upper floor
	if ictx.TwoStory then
		api.box("StrategyTable", Vector3.new(7, 2.6, 3.2), Vector3.new(2, y2 + 1.3, 3), col.Dark, Enum.Material.Metal)
		api.box("StrategyTop", Vector3.new(7.4, 0.25, 3.6), Vector3.new(2, y2 + 2.72, 3), col.Trim, Enum.Material.Metal)
		for _, cx in ipairs({ -0.5, 2, 4.5 }) do
			api.chair(Vector3.new(cx, y2, 0.3), Vector3.new(0, 0, 1))
		end
		-- War council terminal against the front wall, between two windows → Rebirth / prestige
		api.terminal("CouncilTerminal", Vector3.new(2.5, y2, Z1 - 0.6), 180, "Rebirth", "Rebirth", "War Council · Rebirth", { "WAR COUNCIL", "REBIRTH" })

		-- Bunk against the west wall (between the west and front windows) + footlocker
		local bx = X0 + 1.2
		local bz = 4
		api.box("Bunk", Vector3.new(2.4, 0.5, 3), Vector3.new(bx, y2 + 1.2, bz), col.Locker, Enum.Material.Metal)
		api.box("Bunk", Vector3.new(2.4, 0.5, 3), Vector3.new(bx, y2 + 4.0, bz), col.Locker, Enum.Material.Metal)
		api.box("BunkPost", Vector3.new(0.3, 4.5, 0.3), Vector3.new(bx + 1.05, y2 + 2.25, bz + 1.35), col.Metal, Enum.Material.Metal, false)
		api.box("BunkPost", Vector3.new(0.3, 4.5, 0.3), Vector3.new(bx + 1.05, y2 + 2.25, bz - 1.35), col.Metal, Enum.Material.Metal, false)
		api.box("Mattress", Vector3.new(2.2, 0.3, 2.8), Vector3.new(bx, y2 + 1.6, bz), col.Rug, Enum.Material.Fabric, false)
		api.box("Mattress", Vector3.new(2.2, 0.3, 2.8), Vector3.new(bx, y2 + 4.4, bz), col.Rug, Enum.Material.Fabric, false)
		api.box("Footlocker", Vector3.new(1.4, 1.1, 2.4), Vector3.new(bx + 2.2, y2 + 0.55, bz), col.Locker, Enum.Material.Metal)

		-- Weapon rack on the east wall (south of the east window)
		api.box("WeaponRack", Vector3.new(0.6, 4, 4), Vector3.new(X1 - 0.4, y2 + 2, 4.5), col.Dark, Enum.Material.Metal)
		for i = 0, 3 do
			api.box("RackRifle", Vector3.new(0.3, 3.2, 0.3), Vector3.new(X1 - 0.9, y2 + 2.1, 3 + i * 1.0), col.Metal, Enum.Material.Metal, false)
		end
	end
end
