--!strict
--[[
	Warehouse interior (HollowBuildingBuilder). Pallet racks, crate stacks, loading dock strip,
	and an inventory office. Terminals open Shop (resupply) and Base (logistics upgrades).
]]

return function(ictx: any, api: any)
	local col = ictx.Colors
	local lv: number = ictx.Level
	local y1 = ictx.Y1
	local X0, X1, Z0, Z1 = ictx.InX0, ictx.InX1, ictx.InZ0, ictx.InZ1

	local wood = Color3.fromRGB(140, 110, 70)
	local crateCol = Color3.fromRGB(168, 140, 90)

	-- Centre aisle markings
	api.box("AisleLine", Vector3.new(0.4, 0.05, (Z1 - Z0) - 3), Vector3.new(0, y1 + 0.03, (Z0 + Z1) * 0.5), col.Accent, Enum.Material.SmoothPlastic, false)

	-- West + east pallet racks
	local rackZs = if lv >= 3 then { -7, -2, 3, 8 } else { -5, 2, 8 }
	for side = -1, 1, 2 do
		local rx = if side < 0 then X0 + 3.5 else X1 - 3.5
		for _, rz in ipairs(rackZs) do
			api.box("RackFrame", Vector3.new(5.5, 8, 0.35), Vector3.new(rx, y1 + 4, rz - 1.6), col.Metal, Enum.Material.Metal, false)
			api.box("RackFrame", Vector3.new(5.5, 8, 0.35), Vector3.new(rx, y1 + 4, rz + 1.6), col.Metal, Enum.Material.Metal, false)
			for _, hy in ipairs({ 1.5, 4.0, 6.5 }) do
				api.box("RackShelf", Vector3.new(5.2, 0.25, 3.2), Vector3.new(rx, y1 + hy, rz), col.Metal, Enum.Material.Metal)
				api.box("Pallet", Vector3.new(3.6, 0.35, 2.4), Vector3.new(rx, y1 + hy + 0.3, rz), wood, Enum.Material.Wood)
				api.box("Crate", Vector3.new(2.8, 1.6, 1.8), Vector3.new(rx, y1 + hy + 1.2, rz), crateCol, Enum.Material.Wood)
			end
		end
	end

	-- Front loading dock strip (inside, clear of garage door)
	api.box("DockPlate", Vector3.new(14, 0.3, 4), Vector3.new(3, y1 + 0.15, Z1 - 3.5), col.Metal, Enum.Material.DiamondPlate)
	api.box("DockBump", Vector3.new(14, 1.0, 0.6), Vector3.new(3, y1 + 0.5, Z1 - 1.4), col.Trim, Enum.Material.Rubber)
	local dockSign = api.box("DockSign", Vector3.new(6, 1.2, 0.15), Vector3.new(3, y1 + 5.5, Z1 - 0.5), col.Dark, Enum.Material.Metal, false)
	api.surfaceText(dockSign, Enum.NormalId.Front, { "LOADING DOCK", "BAY A" }, col.Accent, col.Dark, Enum.Font.GothamBlack)

	-- Inventory office (back-east)
	api.box("OfficeDesk", Vector3.new(3.5, 2.5, 4.5), Vector3.new(X1 - 2.5, y1 + 1.25, Z0 + 4), col.Dark, Enum.Material.Metal)
	api.chair(Vector3.new(X1 - 4.6, y1, Z0 + 4), Vector3.new(1, 0, 0))
	api.terminal("InventoryTerminal", Vector3.new(X1 - 0.6, y1, Z0 + 7.5), -90, "Shop", "Order supplies", "Inventory · Shop", { "INVENTORY", "SHOP" })
	api.terminal("LogisticsTerminal", Vector3.new(X1 - 0.6, y1, Z0 + 2), -90, "Base", "Plan logistics", "Logistics · Base", { "LOGISTICS", "BASE" })

	-- Loose crate stacks near door (visual clutter, walkable aisle kept)
	for i, cx in ipairs({ -8, -4 }) do
		api.box("LooseCrate", Vector3.new(2.2, 2.0, 2.2), Vector3.new(cx, y1 + 1.0, Z1 - 7), crateCol, Enum.Material.Wood)
		if lv >= 2 then
			api.box("LooseCrate", Vector3.new(2.0, 1.6, 2.0), Vector3.new(cx, y1 + 2.9, Z1 - 7), wood, Enum.Material.Wood)
		end
	end

	-- Overhead lights
	for _, lz in ipairs({ -6, 2, 8 }) do
		local lamp = api.box("WhLight", Vector3.new(12, 0.25, 1), Vector3.new(0, y1 + 12.5, lz), col.Light, Enum.Material.Neon, false)
		api.light(lamp, 26, 0.95, col.Light)
	end

	if lv >= 4 then
		local board = api.box("ManifestBoard", Vector3.new(0.15, 3.5, 4.5), Vector3.new(X0 + 0.4, y1 + 5, 2), col.Dark, Enum.Material.Metal, false)
		api.surfaceText(board, Enum.NormalId.Right, { "MANIFEST", "IN  ·  OUT", "AMMO ✓", "FUEL ✓", "RATS ✓" }, col.Screen, Color3.fromRGB(8, 20, 12), Enum.Font.Code)
	end
end
