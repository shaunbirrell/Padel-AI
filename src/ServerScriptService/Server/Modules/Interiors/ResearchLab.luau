--!strict
--[[
	Research Lab interior (HollowBuildingBuilder). Lab benches, sample cabinets, a central holotable,
	and upstairs (from TwoStoryLevel) an analysis loft. Terminals open Missions (field intel) and
	Rebirth (tech tree / prestige research).
]]

return function(ictx: any, api: any)
	local col = ictx.Colors
	local lv: number = ictx.Level
	local y1, y2 = ictx.Y1, ictx.Y2
	local X0, X1, Z0, Z1 = ictx.InX0, ictx.InX1, ictx.InZ0, ictx.InZ1
	local glass = Color3.fromRGB(140, 190, 210)
	local white = Color3.fromRGB(230, 232, 228)

	-- Central holotable
	api.box("HoloBase", Vector3.new(5.5, 2.4, 3.5), Vector3.new(0, y1 + 1.2, 1), col.Dark, Enum.Material.Metal)
	local holo = api.box("HoloTop", Vector3.new(5.8, 0.2, 3.8), Vector3.new(0, y1 + 2.5, 1), glass, Enum.Material.Glass, false)
	api.surfaceText(holo, Enum.NormalId.Top, { "R&D", "PROJECTS", "ACTIVE" }, col.Screen, Color3.fromRGB(8, 24, 30), Enum.Font.Code)
	api.box("HoloPillar", Vector3.new(0.6, 1.2, 0.6), Vector3.new(0, y1 + 3.2, 1), col.Accent, Enum.Material.Neon, false)

	-- West lab benches
	for i, bz in ipairs({ -5, 1, 7 }) do
		api.box("Bench", Vector3.new(4.5, 2.6, 2.2), Vector3.new(X0 + 3.2, y1 + 1.3, bz), white, Enum.Material.SmoothPlastic)
		api.box("BenchTop", Vector3.new(4.8, 0.2, 2.4), Vector3.new(X0 + 3.2, y1 + 2.7, bz), col.Metal, Enum.Material.Metal)
		local mon = api.box("Scope", Vector3.new(0.3, 1.4, 1.6), Vector3.new(X0 + 1.4, y1 + 3.6, bz), col.Dark, Enum.Material.Metal, false)
		api.surfaceText(mon, Enum.NormalId.Right, { "SAMPLE", string.format("%02d", i), "SCAN" }, col.Screen, Color3.fromRGB(8, 20, 12), Enum.Font.Code)
		api.chair(Vector3.new(X0 + 5.6, y1, bz), Vector3.new(-1, 0, 0))
	end

	-- East sample cabinets
	for _, cz in ipairs({ -6, -1, 4, 9 }) do
		api.box("Cabinet", Vector3.new(2.2, 5.5, 2.5), Vector3.new(X1 - 1.6, y1 + 2.75, cz), white, Enum.Material.SmoothPlastic)
		api.box("CabinetGlass", Vector3.new(0.15, 4.2, 2.1), Vector3.new(X1 - 2.75, y1 + 3.0, cz), glass, Enum.Material.Glass, false)
	end

	-- Terminals: intel + research tree
	api.terminal("IntelTerminal", Vector3.new(X1 - 0.6, y1, Z1 - 3), -90, "Missions", "Field intel", "Intel · Missions", { "FIELD INTEL", "MISSIONS" })
	api.terminal("TechTerminal", Vector3.new(X0 + 0.6, y1, Z1 - 3), 90, "Rebirth", "Research tree", "R&D · Rebirth", { "TECH TREE", "REBIRTH" })

	-- Whiteboard on back wall
	local board = api.box("Whiteboard", Vector3.new(8, 3.5, 0.15), Vector3.new(0, y1 + 5, Z0 + 0.5), Color3.fromRGB(240, 242, 235), Enum.Material.SmoothPlastic, false)
	api.surfaceText(board, Enum.NormalId.Front, { "HYPOTHESIS", "→  PROTOTYPE", "→  FIELD TEST", "→  DEPLOY" }, Color3.fromRGB(30, 40, 50), Color3.fromRGB(240, 242, 235), Enum.Font.Gotham)

	-- Overhead clean lights
	for _, lz in ipairs({ -5, 2, 8 }) do
		local lamp = api.box("LabLight", Vector3.new(10, 0.2, 1.2), Vector3.new(0, y1 + 10.5, lz), col.Light, Enum.Material.Neon, false)
		api.light(lamp, 22, 1.05, col.Light)
	end

	-- Upper loft from two-storey level
	if y2 and lv >= 3 then
		api.box("LoftDesk", Vector3.new(6, 2.4, 3), Vector3.new(-2, y2 + 1.2, 2), col.Dark, Enum.Material.Metal)
		api.chair(Vector3.new(-2, y2, 4.2), Vector3.new(0, 0, -1))
		api.terminal("AnalysisTerminal", Vector3.new(X1 - 0.6, y2, 2), -90, "Missions", "Run analysis", "Analysis loft", { "ANALYSIS", "MISSIONS" })
		local server = api.box("ServerRack", Vector3.new(2.2, 5, 3.5), Vector3.new(X0 + 1.5, y2 + 2.5, -4), col.Dark, Enum.Material.Metal)
		api.surfaceText(server, Enum.NormalId.Right, { "CLUSTER", "A1–A8", "ONLINE" }, col.Screen, Color3.fromRGB(8, 20, 12), Enum.Font.Code)
		if lv >= 5 then
			api.box("AccentStrip", Vector3.new(10, 0.15, 0.15), Vector3.new(0, y2 + 6.5, Z1 - 0.4), col.Accent, Enum.Material.Neon, false)
		end
	end
end
