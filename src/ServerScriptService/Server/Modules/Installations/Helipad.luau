--!strict
--[[
	Helipad installation (HollowBuildingBuilder, StructureVisualConfig.Installations.Helipad; structure Helipad).
	v73 (owner: "the default helicopter on the pad is horrific"). The kit Body is the 28 x 28 pad (foundation slab,
	asphalt colour). No parked mock-up: the player's own helicopter spawns on VehicleConfig HelipadSpots (-4, 6) /
	(8, 8) once one is unlocked, so nothing here stands on those spots.
	  L1 landing circle + H (flush paint, no collision), 4 perimeter light fittings, windsock, ops hut beside the pad
	  L2 lit floodlight      L3 fuel tank      L4 second floodlight (unlit: light budget)      L5 gold circle + hut beacon
	The markings are stacked 0.06 apart (ring top y0 + 0.10, inner disc y0 + 0.16, H y0 + 0.22) so no two top faces
	are coplanar (no flicker), and none of them collides or is queryable (vehicle spawn rays land on the slab).
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local StructureVisualConfig = require(Shared.Configs.StructureVisualConfig)
local LIGHTS = (StructureVisualConfig :: any).BuildingLights or {}

-- Solid booth: body, glass band, door on the hut's local +X face, roof. 4 parts. Returns (body, roof).
local function hut(api: any, name: string, pos: Vector3, size: Vector3, yawDeg: number, style: any): (BasePart, BasePart)
	local f = CFrame.new(pos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	local w, h, d = size.X, size.Y, size.Z
	local body = api.part(name, Vector3.new(w, h, d), f * CFrame.new(0, h * 0.5, 0), style.Wall, style.Material or Enum.Material.Concrete)
	local band = api.part(name .. "Glass", Vector3.new(w + 0.12, 1.8, d + 0.12), f * CFrame.new(0, h - 2.4, 0), style.Glass, Enum.Material.Glass, false)
	band.Transparency = 0.15
	band.CastShadow = false
	local doorH = math.min(h - 0.6, 6.6)
	api.part(name .. "Door", Vector3.new(0.14, doorH, 2.6), f * CFrame.new(w * 0.5 + 0.08, doorH * 0.5, -d * 0.2), style.Door, Enum.Material.Metal, false)
	local roof = api.part(name .. "Roof", Vector3.new(w + 1.6, 0.5, d + 1.6), f * CFrame.new(0, h + 0.25, 0), style.Roof, Enum.Material.Metal)
	return body, roof
end

-- Floodlight: pole + a head aimed at `aim` (installation-local), with a SpotLight (no shadows) when lit. 2 parts.
local function floodlight(api: any, pos: Vector3, aim: Vector3, height: number, lit: boolean, col: any): BasePart
	api.box("FloodPole", Vector3.new(0.35, height, 0.35), pos + Vector3.new(0, height * 0.5, 0), col.Metal, Enum.Material.Metal, false)
	local head = pos + Vector3.new(0, height + 0.3, 0)
	local lamp = api.part("FloodLamp", Vector3.new(1.6, 0.9, 0.7), CFrame.lookAt(head, aim), col.Light, Enum.Material.SmoothPlastic, false)
	if lit then
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Angle = 60
		spot.Range = math.min(28, LIGHTS.SpotMaxRange or 30)
		spot.Brightness = 2 * (LIGHTS.BrightnessScale or 0.35)
		spot.Color = col.Light
		spot.Shadows = false
		spot.Parent = lamp
	end
	return lamp
end

return function(ictx: any, api: any)
	local col = ictx.Colors
	local lv = ictx.Level
	local y0 = ictx.Y0 -- pad (foundation) top
	local ground = y0 - 0.4
	local hw = ictx.HalfW
	local paint = Color3.fromRGB(238, 238, 230)
	local ringCol = if lv >= 5 then col.Gold else Color3.fromRGB(226, 190, 60)

	-- Landing circle (outer disc + dark inner disc = a ring) and the H: flush paint, non-colliding
	local ring = api.cylinder("PadRing", Vector3.new(0.1, 21, 21), CFrame.new(0, y0 + 0.05, 0) * CFrame.Angles(0, 0, math.rad(90)), ringCol, Enum.Material.SmoothPlastic, false)
	ring.CastShadow = false
	local inner = api.cylinder("PadInner", Vector3.new(0.1, 19.2, 19.2), CFrame.new(0, y0 + 0.11, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(64, 66, 64), Enum.Material.SmoothPlastic, false)
	inner.CastShadow = false
	api.box("PadH", Vector3.new(1.2, 0.1, 8), Vector3.new(-2.4, y0 + 0.17, 0), paint, Enum.Material.SmoothPlastic, false)
	api.box("PadH", Vector3.new(1.2, 0.1, 8), Vector3.new(2.4, y0 + 0.17, 0), paint, Enum.Material.SmoothPlastic, false)
	api.box("PadH", Vector3.new(3.6, 0.1, 1.2), Vector3.new(0, y0 + 0.17, 0), paint, Enum.Material.SmoothPlastic, false)

	-- Perimeter light fittings at the corners (painted, no PointLight: light budget)
	for _, o in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		api.box("PadEdgeLight", Vector3.new(0.9, 0.35, 0.9), Vector3.new(o[1] * (hw - 1.2), y0 + 0.175, o[2] * (hw - 1.2)), Color3.fromRGB(255, 226, 150), Enum.Material.SmoothPlastic, false)
	end

	-- Windsock beside the pad edge
	api.box("WindsockPole", Vector3.new(0.3, 7, 0.3), Vector3.new(hw + 1.5, ground + 3.5, -hw + 3), col.Metal, Enum.Material.Metal)
	local sock = api.part("Windsock", Vector3.new(2.6, 0.9, 0.9), CFrame.new(hw + 2.9, ground + 6.5, -hw + 3), Color3.fromRGB(222, 96, 44), Enum.Material.Fabric, false)
	sock.Shape = Enum.PartType.Cylinder

	-- Ops hut beside the pad (player scale: 7.4 tall), door toward the pad
	local _, hutRoof = hut(api, "OpsHut", Vector3.new(-hw - 4.5, ground, -hw + 5), Vector3.new(6, 7.4, 5), 0, {
		Wall = Color3.fromRGB(150, 156, 140),
		Material = Enum.Material.Concrete,
		Glass = Color3.fromRGB(70, 100, 118),
		Door = col.Metal,
		Roof = Color3.fromRGB(62, 66, 62),
	})

	if lv >= 2 then
		-- front corners (toward the base), clear of the HelipadSpots' rotor discs
		floodlight(api, Vector3.new(-hw - 1.2, ground, hw + 1.2), Vector3.new(0, y0, 0), 9, true, col)
	end
	if lv >= 3 then
		-- fuel tank lying on the ground beside the hut (Part cylinder, axis along Z)
		local tank = api.part("FuelTank", Vector3.new(5, 2.6, 2.6), CFrame.new(-hw - 4.5, ground + 1.3, hw - 6) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(96, 104, 80), Enum.Material.Metal)
		tank.Shape = Enum.PartType.Cylinder
	end
	if lv >= 4 then
		floodlight(api, Vector3.new(hw + 1.2, ground, hw + 1.2), Vector3.new(0, y0, 0), 9, false, col) -- light budget: one lit fitting
	end
	if lv >= 5 then
		hutRoof.Color = col.Gold
		api.ball("HutBeacon", 0.9, Vector3.new(-hw - 4.5, ground + 7.9 + 0.45, -hw + 5), col.Gold, Enum.Material.SmoothPlastic, false)
	end
end
