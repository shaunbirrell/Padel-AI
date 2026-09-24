--!strict
--[[
	Watchtower installation (HollowBuildingBuilder, StructureVisualConfig.Installations; structure Watchtowers).
	10 x 10 by the main gate: four braced legs, a climbable ladder (TrussPart) on the compound side (-Z, where
	the kiosk is), a sandbagged platform with a roof and a searchlight facing the front wall.
	Height grows with level; L3 mounted gun; L5 gold roof trim + flag.
	v70 (HUD spec §5): the searchlight goes through StructureVisualConfig.BuildingLights like every building light
	(BrightnessScale, SpotMaxRange), with a SmoothPlastic lens and no shadows.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local StructureVisualConfig = require(Shared.Configs.StructureVisualConfig)
local LIGHTS = (StructureVisualConfig :: any).BuildingLights or {}

return function(ictx: any, api: any)
	local col = ictx.Colors
	local lv = ictx.Level
	local y0 = ictx.Y0
	local timber = Color3.fromRGB(96, 78, 56)

	-- L5 gold edge band around a roof (matches the walk-in buildings' gold parapet cap)
	local function goldEdge(cx: number, y: number, cz: number, w: number, d: number)
		api.box("GoldTrim", Vector3.new(w, 0.3, 0.3), Vector3.new(cx, y, cz + d * 0.5), col.Gold, Enum.Material.Metal, false)
		api.box("GoldTrim", Vector3.new(w, 0.3, 0.3), Vector3.new(cx, y, cz - d * 0.5), col.Gold, Enum.Material.Metal, false)
		api.box("GoldTrim", Vector3.new(0.3, 0.3, d), Vector3.new(cx + w * 0.5, y, cz), col.Gold, Enum.Material.Metal, false)
		api.box("GoldTrim", Vector3.new(0.3, 0.3, d), Vector3.new(cx - w * 0.5, y, cz), col.Gold, Enum.Material.Metal, false)
	end

	local function beam(name: string, a: Vector3, b: Vector3, thick: number, color: Color3)
		local mid = (a + b) * 0.5
		api.part(name, Vector3.new(thick, thick, (b - a).Magnitude), CFrame.lookAt(mid, b), color, Enum.Material.Wood, false)
	end

	local h = 10 + lv * 1.6 -- platform height above the foundation
	local L = 3.4 -- leg offset
	for _, o in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		api.box("TowerLeg", Vector3.new(0.8, h, 0.8), Vector3.new(o[1] * L, y0 + h * 0.5, o[2] * L), timber, Enum.Material.Wood)
	end
	-- X braces on the three sides away from the ladder, a single rail on the ladder side
	for _, k in ipairs({ 0, 1 }) do
		local ya, yb = y0 + 1 + k * (h - 2) * 0.5, y0 + 1 + (k + 1) * (h - 2) * 0.5
		beam("TowerBrace", Vector3.new(-L, ya, L), Vector3.new(L, yb, L), 0.35, timber)
		beam("TowerBrace", Vector3.new(L, ya, L), Vector3.new(-L, yb, L), 0.35, timber)
		beam("TowerBrace", Vector3.new(-L, ya, -L), Vector3.new(-L, yb, L), 0.35, timber)
		beam("TowerBrace", Vector3.new(L, ya, L), Vector3.new(L, yb, -L), 0.35, timber)
	end

	-- Platform + sandbag parapet (gap over the ladder)
	local py = y0 + h
	api.box("TowerDeck", Vector3.new(8.4, 0.5, 8.4), Vector3.new(0, py + 0.25, 0), timber, Enum.Material.WoodPlanks)
	local deck = py + 0.5
	api.sandbags(-3.6, 3.6, 3.6, deck)
	for _, sx in ipairs({ -3.6, 3.6 }) do
		for i = 0, 2 do
			api.box("Sandbag", Vector3.new(1.5, 1.0, 2.0), Vector3.new(sx, deck + 0.5, -2.2 + i * 2.2), col.Sandbag, Enum.Material.Fabric)
		end
	end
	api.sandbags(-3.6, -1.4, -3.6, deck)
	api.sandbags(1.4, 3.6, -3.6, deck)

	-- Ladder on the compound side
	api.truss("TowerLadder", h + 0.5, Vector3.new(0, y0, -4.4), col.Metal)

	-- Roof on corner posts
	local roofY = deck + 3.6
	for _, o in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		api.box("RoofPost", Vector3.new(0.35, 3.6, 0.35), Vector3.new(o[1] * 3.9, deck + 1.8, o[2] * 3.9), timber, Enum.Material.Wood, false)
	end
	api.box("TowerRoof", Vector3.new(9.4, 0.4, 9.4), Vector3.new(0, roofY + 0.2, 0), col.Trim, Enum.Material.Metal)
	if lv >= 5 then
		goldEdge(0, roofY + 0.55, 0, 9.4, 9.4)
		api.box("FlagPole", Vector3.new(0.25, 5, 0.25), Vector3.new(-4.2, roofY + 2.9, -4.2), col.Metal, Enum.Material.Metal, false)
		api.box("Flag", Vector3.new(0.1, 1.8, 3), Vector3.new(-4.2, roofY + 4.4, -2.7), col.Flag, Enum.Material.Fabric, false)
	end

	-- Searchlight facing the front wall (+Z)
	api.box("SearchlightMount", Vector3.new(0.5, 1.2, 0.5), Vector3.new(2, deck + 1.6, 2.8), col.Metal, Enum.Material.Metal, false)
	api.cylinder("Searchlight", Vector3.new(1.4, 1.3, 1.3), CFrame.new(2, deck + 2.5, 2.8) * CFrame.Angles(0, math.rad(90), 0), col.Dark, Enum.Material.Metal, false)
	local lens = api.cylinder("SearchlightLens", Vector3.new(0.1, 1.1, 1.1), CFrame.new(2, deck + 2.5, 3.52) * CFrame.Angles(0, math.rad(-90), 0), col.Light, Enum.Material.SmoothPlastic, false)
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Right -- lens local +X = building +Z
	spot.Angle = 40
	spot.Range = math.min(30, LIGHTS.SpotMaxRange or 30)
	spot.Brightness = 2 * (LIGHTS.BrightnessScale or 0.35) -- 0.7 at the v69 scale
	spot.Color = col.Light
	spot.Shadows = false
	spot.Parent = lens

	-- Mounted gun (L3+)
	if lv >= 3 then
		api.box("GunMount", Vector3.new(0.4, 1, 0.4), Vector3.new(-1.8, deck + 1.5, 3), col.Metal, Enum.Material.Metal, false)
		api.box("GunBody", Vector3.new(0.6, 0.6, 1.8), Vector3.new(-1.8, deck + 2.2, 3.2), col.Dark, Enum.Material.Metal, false)
		api.cylinder("GunBarrel", Vector3.new(2, 0.25, 0.25), CFrame.new(-1.8, deck + 2.25, 4.9) * CFrame.Angles(0, math.rad(90), 0), col.Dark, Enum.Material.Metal, false)
	end
end
