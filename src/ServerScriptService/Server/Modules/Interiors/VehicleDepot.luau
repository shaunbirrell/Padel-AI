--!strict
--[[
	Vehicle Depot interior (HollowBuildingBuilder). Big garage bay with service pits, tool racks,
	and a showroom podium. Terminals open Garage (fleet) and Shop (buy vehicles/gear).
	Layout (building-local, +Z = front/garage door): work bays west, office/terminals east.
]]

return function(ictx: any, api: any)
	local col = ictx.Colors
	local lv: number = ictx.Level
	local y1 = ictx.Y1
	local X0, X1, Z0, Z1 = ictx.InX0, ictx.InX1, ictx.InZ0, ictx.InZ1

	-- Centre taxi line from door toward back
	api.box("TaxiLine", Vector3.new(0.6, 0.05, (Z1 - Z0) - 4), Vector3.new(0, y1 + 0.03, (Z0 + Z1) * 0.5), col.Accent, Enum.Material.SmoothPlastic, false)

	-- West work bays: raised ramps + tool chests
	local bayZs = if lv >= 3 then { -6, 0, 6 } else { -4, 4 }
	for i, bz in ipairs(bayZs) do
		local bx = X0 + 6
		api.box("BayRamp", Vector3.new(10, 0.4, 4.5), Vector3.new(bx, y1 + 0.2, bz), col.Metal, Enum.Material.DiamondPlate)
		api.box("ToolChest", Vector3.new(2.4, 1.6, 1.2), Vector3.new(bx - 4.2, y1 + 0.8, bz + 2.2), col.Trim, Enum.Material.Metal)
		api.box("JackStand", Vector3.new(0.6, 1.8, 0.6), Vector3.new(bx + 2, y1 + 0.9, bz - 1.4), col.Dark, Enum.Material.Metal, false)
		local sign = api.box("BaySign", Vector3.new(0.15, 1.0, 2.4), Vector3.new(X0 + 0.5, y1 + 3.2, bz), col.Dark, Enum.Material.Metal, false)
		api.surfaceText(sign, Enum.NormalId.Right, { string.format("BAY %02d", i), "SERVICE" }, col.Accent, col.Dark, Enum.Font.GothamBold)
	end

	-- Showroom podium (front-centre, clear of door)
	local podX, podZ = 2, Z1 - 6
	api.box("Podium", Vector3.new(8, 0.5, 5), Vector3.new(podX, y1 + 0.25, podZ), col.Dark, Enum.Material.Metal)
	api.box("PodiumRing", Vector3.new(8.4, 0.15, 5.4), Vector3.new(podX, y1 + 0.55, podZ), col.Accent, Enum.Material.Neon, false)
	-- Simple hull silhouette as a placeholder vehicle
	api.box("Hull", Vector3.new(6.5, 1.6, 2.8), Vector3.new(podX, y1 + 1.5, podZ), Color3.fromRGB(70, 78, 68), Enum.Material.Metal)
	api.box("Cabin", Vector3.new(2.4, 1.2, 2.4), Vector3.new(podX - 1.2, y1 + 2.8, podZ), Color3.fromRGB(40, 50, 55), Enum.Material.Glass, false)
	api.box("Wheel", Vector3.new(0.8, 1.2, 1.2), Vector3.new(podX - 2.4, y1 + 0.9, podZ - 1.6), col.Dark, Enum.Material.Rubber, false)
	api.box("Wheel", Vector3.new(0.8, 1.2, 1.2), Vector3.new(podX - 2.4, y1 + 0.9, podZ + 1.6), col.Dark, Enum.Material.Rubber, false)
	api.box("Wheel", Vector3.new(0.8, 1.2, 1.2), Vector3.new(podX + 2.4, y1 + 0.9, podZ - 1.6), col.Dark, Enum.Material.Rubber, false)
	api.box("Wheel", Vector3.new(0.8, 1.2, 1.2), Vector3.new(podX + 2.4, y1 + 0.9, podZ + 1.6), col.Dark, Enum.Material.Rubber, false)

	-- East wall: office desk + terminals
	api.box("OfficeDesk", Vector3.new(3.2, 2.4, 5), Vector3.new(X1 - 2.2, y1 + 1.2, 1), col.Dark, Enum.Material.Metal)
	api.chair(Vector3.new(X1 - 4.2, y1, 1), Vector3.new(1, 0, 0))
	api.terminal("FleetTerminal", Vector3.new(X1 - 0.6, y1, 4.5), -90, "Garage", "Open garage", "Fleet · Garage", { "FLEET", "GARAGE" })
	api.terminal("PartsTerminal", Vector3.new(X1 - 0.6, y1, -3.5), -90, "Shop", "Buy parts", "Parts · Shop", { "PARTS COUNTER", "SHOP" })

	-- Parts shelves along back wall
	for i, sx in ipairs({ -10, -4, 4, 10 }) do
		api.box("PartsShelf", Vector3.new(4.5, 5.5, 1.2), Vector3.new(sx, y1 + 2.75, Z0 + 1.0), col.Metal, Enum.Material.Metal)
		if lv >= 2 then
			api.box("Crate", Vector3.new(1.6, 1.4, 1.4), Vector3.new(sx, y1 + 0.7, Z0 + 2.6), col.Trim, Enum.Material.Wood)
		end
	end

	-- Overhead bay lights
	for _, lz in ipairs({ -6, 0, 6 }) do
		local lamp = api.box("BayLight", Vector3.new(10, 0.25, 1), Vector3.new(-4, y1 + 12, lz), col.Light, Enum.Material.Neon, false)
		api.light(lamp, 28, 1.0, col.Light)
	end

	if lv >= 4 then
		local board = api.box("DutyBoard", Vector3.new(0.15, 3.2, 4), Vector3.new(X1 - 0.4, y1 + 5.5, 1), col.Dark, Enum.Material.Metal, false)
		api.surfaceText(board, Enum.NormalId.Left, { "DISPATCH", "READY", "IN BAY", "OUT" }, col.Screen, Color3.fromRGB(8, 20, 12), Enum.Font.Code)
	end
end
