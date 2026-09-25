--!strict
--[[
	Watchtower installation (HollowBuildingBuilder, StructureVisualConfig.Installations; structure Watchtowers).
	10 x 10 by the main gate: four braced legs, a climbable ladder (TrussPart) on the compound side (-Z, where
	the kiosk is), a timber cabin with half-walls, a pitched roof and a searchlight facing the front wall.
	Height grows with level; L3 mounted gun; L5 gold ridge + flag.
	v70 (HUD spec §5): the searchlight goes through StructureVisualConfig.BuildingLights like every building light
	(BrightnessScale, SpotMaxRange), with a SmoothPlastic lens and no shadows.
	v73 (owner: "the watchtower doesn't fit the player"): the cabin is sized for a 7.5-stud avatar with 1 stud of
	head room (CabinClearHeight, was 3.6), the deck is 10 x 10 (was 8.4), the ladder always tops out above the
	deck, and the roof is CanCollide = false so heads, jumps and the Poppercam never catch on it.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local StructureVisualConfig = require(Shared.Configs.StructureVisualConfig)
local LIGHTS = (StructureVisualConfig :: any).BuildingLights or {}
local TOWER = ((StructureVisualConfig :: any).Installations or {}).Watchtowers or {}

return function(ictx: any, api: any)
	local col = ictx.Colors
	local lv = ictx.Level
	local y0 = ictx.Y0
	local timber = Color3.fromRGB(96, 78, 56)
	local roofCol = Color3.fromRGB(74, 84, 60)

	local function beam(name: string, a: Vector3, b: Vector3, thick: number, color: Color3)
		local mid = (a + b) * 0.5
		api.part(name, Vector3.new(thick, thick, (b - a).Magnitude), CFrame.lookAt(mid, b), color, Enum.Material.Wood, false)
	end

	local h = 10 + lv * 1.6 -- deck underside above the foundation
	local L = 4.2 -- leg offset (deck 10 x 10)
	local deckW = 10
	local clear: number = TOWER.CabinClearHeight or 8.5 -- deck top to roof underside (7.5-stud avatar + 1 stud)
	local wallH: number = TOWER.HalfWallHeight or 3.4
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

	-- Deck + timber half-walls (3.4 high; 3.2-stud gap over the ladder)
	local py = y0 + h
	api.box("TowerDeck", Vector3.new(deckW, 0.5, deckW), Vector3.new(0, py + 0.25, 0), timber, Enum.Material.WoodPlanks)
	local deck = py + 0.5
	local e = deckW * 0.5 - 0.2
	api.box("CabinWall", Vector3.new(deckW, wallH, 0.4), Vector3.new(0, deck + wallH * 0.5, e), timber, Enum.Material.WoodPlanks)
	api.box("CabinWall", Vector3.new(0.4, wallH, deckW - 0.8), Vector3.new(-e, deck + wallH * 0.5, 0), timber, Enum.Material.WoodPlanks)
	api.box("CabinWall", Vector3.new(0.4, wallH, deckW - 0.8), Vector3.new(e, deck + wallH * 0.5, 0), timber, Enum.Material.WoodPlanks)
	local gap = 1.6 -- half the ladder opening
	api.box("CabinWall", Vector3.new(e - gap, wallH, 0.4), Vector3.new(-(gap + e) * 0.5, deck + wallH * 0.5, -e), timber, Enum.Material.WoodPlanks)
	api.box("CabinWall", Vector3.new(e - gap, wallH, 0.4), Vector3.new((gap + e) * 0.5, deck + wallH * 0.5, -e), timber, Enum.Material.WoodPlanks)

	-- Ladder on the compound side, outside the deck edge. TrussPart heights are even, so round UP: the top is
	-- 0.3 .. 1.9 studs above the deck at every level (was up to 0.9 below it at L4)
	local ladderH = 2 * math.ceil((h + 0.5) / 2)
	api.truss("TowerLadder", ladderH, Vector3.new(0, y0, -deckW * 0.5 - 1), col.Metal)

	-- Cabin: corner posts + pitched roof. Roof is non-collidable (no head bumps, no Poppercam pop-under).
	local roofY = deck + clear
	for _, o in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		api.box("RoofPost", Vector3.new(0.4, clear, 0.4), Vector3.new(o[1] * e, deck + clear * 0.5, o[2] * e), timber, Enum.Material.Wood, false)
	end
	local rise, run, len = 2.4, deckW * 0.5 + 0.6, deckW + 1.2
	local r1 = api.wedge("TowerRoof", Vector3.new(len, rise, run), CFrame.new(0, roofY + rise * 0.5, run * 0.5) * CFrame.Angles(0, math.pi, 0), roofCol, Enum.Material.Metal, false)
	local r2 = api.wedge("TowerRoof", Vector3.new(len, rise, run), CFrame.new(0, roofY + rise * 0.5, -run * 0.5), roofCol, Enum.Material.Metal, false)
	r1.CanQuery = false
	r2.CanQuery = false
	api.box("TowerRidge", Vector3.new(len + 0.2, 0.35, 0.7), Vector3.new(0, roofY + rise, 0), if lv >= 5 then col.Gold else col.Metal, Enum.Material.Metal, false)
	if lv >= 5 then
		api.box("FlagPole", Vector3.new(0.25, 7, 0.25), Vector3.new(-e - 0.3, roofY + 3.5, -e - 0.3), col.Metal, Enum.Material.Metal, false)
		-- nation-flag decal host (WE_FlagHost): 0.12 thick along X, decals on the Left / Right faces
		local cloth = api.box("Flag", Vector3.new(0.12, 1.8, 3), Vector3.new(-e - 0.3, roofY + 6, -e - 0.3 + 1.6), col.Flag, Enum.Material.Fabric, false)
		cloth:SetAttribute("WE_FlagHost", true)
	end

	-- Searchlight on the front half-wall, facing the front wall (+Z): out of the walking area
	api.box("SearchlightMount", Vector3.new(0.5, 0.8, 0.5), Vector3.new(3.2, deck + wallH + 0.4, e), col.Metal, Enum.Material.Metal, false)
	api.cylinder("Searchlight", Vector3.new(1.4, 1.3, 1.3), CFrame.new(3.2, deck + wallH + 1.3, e) * CFrame.Angles(0, math.rad(90), 0), col.Dark, Enum.Material.Metal, false)
	local lens = api.cylinder("SearchlightLens", Vector3.new(0.1, 1.1, 1.1), CFrame.new(3.2, deck + wallH + 1.3, e + 0.72) * CFrame.Angles(0, math.rad(-90), 0), col.Light, Enum.Material.SmoothPlastic, false)
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Right -- lens local +X = building +Z
	spot.Angle = 40
	spot.Range = math.min(30, LIGHTS.SpotMaxRange or 30)
	spot.Brightness = 2 * (LIGHTS.BrightnessScale or 0.35) -- 0.7 at the v69 scale
	spot.Color = col.Light
	spot.Shadows = false
	spot.Parent = lens

	-- Mounted gun on the front half-wall (L3+)
	if lv >= 3 then
		api.box("GunMount", Vector3.new(0.4, 0.8, 0.4), Vector3.new(-3.2, deck + wallH + 0.4, e), col.Metal, Enum.Material.Metal, false)
		api.box("GunBody", Vector3.new(0.6, 0.6, 1.8), Vector3.new(-3.2, deck + wallH + 1.0, e + 0.2), col.Dark, Enum.Material.Metal, false)
		api.cylinder("GunBarrel", Vector3.new(2, 0.25, 0.25), CFrame.new(-3.2, deck + wallH + 1.05, e + 1.9) * CFrame.Angles(0, math.rad(90), 0), col.Dark, Enum.Material.Metal, false)
	end
end
