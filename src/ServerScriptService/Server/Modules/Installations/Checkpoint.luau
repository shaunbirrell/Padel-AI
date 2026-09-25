--!strict
--[[
	Gate checkpoint installation for DefensiveWalls (HollowBuildingBuilder, StructureVisualConfig.Installations).
	The perimeter walls themselves are still built by StructureKitBuilder.SyncPerimeterWalls — this is the visible
	"defences" post at the main gate.

	v73 (owner: "the checkpoint looks terrible at front of base"). Re-authored at player scale around the road:
	  site (-18, 146), local +X toward the main road (road edge local x = 11, centre 18), +Z toward the gate wall.
	  The foundation (kit Body, 6 x 6) is now the flag plinth: the base flag (nation flag later) is the first thing
	  a player sees at the gate. The guard booth stands at the road edge (7.4 tall, glass band at eye height), the
	  boom barrier sits on the spawn side of the booth with its arm raised over the road (never blocks a vehicle),
	  jersey barriers shield the booth from the gate, one angled floodlight lights the lane (SpotLight).
	L1 plinth + flag, booth, boom, 2 jersey barriers, floodlight   L2 2 more barriers   L3 tank traps by the wall
	L4 sandbagged gun nest at the flag   L5 second floodlight, gold booth edge + flag finial
	No razor-wire pipes, no tray: every prop off the plinth stands on the ground (y = 0).
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local StructureVisualConfig = require(Shared.Configs.StructureVisualConfig)
local LIGHTS = (StructureVisualConfig :: any).BuildingLights or {}

return function(ictx: any, api: any)
	local col = ictx.Colors
	local lv = ictx.Level
	local y0 = ictx.Y0 -- plinth top
	local concrete = Color3.fromRGB(176, 172, 160)
	local boothCol = Color3.fromRGB(206, 200, 182)
	local olive = Color3.fromRGB(74, 84, 60)
	local hazard = col.Accent
	local rust = Color3.fromRGB(104, 76, 56)

	-- Flag on the plinth (kit Body): the hero flag at the gate. The cloth (0.12 thick along X) is the nation-flag
	-- decal host (attribute WE_FlagHost; its Left / Right faces carry the decal).
	api.box("FlagPole", Vector3.new(0.4, 16, 0.4), Vector3.new(0, y0 + 8, 0), col.Metal, Enum.Material.Metal)
	local cloth = api.box("Flag", Vector3.new(0.12, 3.2, 5.4), Vector3.new(0, y0 + 14.2, 2.9), col.Flag, Enum.Material.Fabric, false)
	cloth:SetAttribute("WE_FlagHost", true)
	if lv >= 5 then
		api.ball("FlagTip", 0.9, Vector3.new(0, y0 + 16.4, 0), col.Gold, Enum.Material.SmoothPlastic, false)
	end

	-- Guard booth at the road edge (solid, not walk-in): concrete base, glass band at eye height, olive roof.
	-- x 7.2: the 7.4-wide roof ends at x 10.9, inside the main road's edge (local x 11 = world x -7)
	local bx, bz, bw = 7.2, -3.5, 6
	api.box("Booth", Vector3.new(bw, 3.6, bw), Vector3.new(bx, 1.8, bz), boothCol, Enum.Material.Concrete)
	local glass = api.box("BoothGlass", Vector3.new(bw - 0.2, 3.2, bw - 0.2), Vector3.new(bx, 5.2, bz), Color3.fromRGB(96, 124, 136), Enum.Material.Glass)
	glass.Transparency = 0.2
	for _, o in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		api.box("BoothPost", Vector3.new(0.35, 3.2, 0.35), Vector3.new(bx + o[1] * (bw * 0.5 - 0.05), 5.2, bz + o[2] * (bw * 0.5 - 0.05)), col.Dark, Enum.Material.Metal, false)
	end
	api.box("BoothRoof", Vector3.new(bw + 1.4, 0.6, bw + 1.4), Vector3.new(bx, 7.1, bz), olive, Enum.Material.Metal)
	if lv >= 5 then
		api.box("GoldTrim", Vector3.new(bw + 1.6, 0.18, bw + 1.6), Vector3.new(bx, 6.72, bz), col.Gold, Enum.Material.Metal, false)
	end
	api.box("BoothDoor", Vector3.new(0.12, 6.6, 2.4), Vector3.new(bx - bw * 0.5 - 0.06, 3.3, bz), col.Dark, Enum.Material.Metal, false)
	-- warm light inside the glass band: the booth reads as manned at night
	local boothLight = Instance.new("PointLight")
	boothLight.Range = math.min(10, LIGHTS.MaxRange or 10)
	boothLight.Brightness = 1.2 * (LIGHTS.BrightnessScale or 0.35)
	boothLight.Color = col.Light
	boothLight.Shadows = false
	boothLight.Parent = glass
	-- sign on the roof, facing into the compound (players heading for the gate read it)
	local sign = api.box("BoothSign", Vector3.new(5.4, 1.3, 0.25), Vector3.new(bx, 8.05, bz), col.Dark, Enum.Material.Metal, false)
	api.surfaceText(sign, Enum.NormalId.Front, { "CHECKPOINT" }, col.Accent, col.Dark, Enum.Font.GothamBlack)

	-- Boom barrier: cabinet at the road edge on the spawn side of the booth, arm across the road raised 80°
	-- (open: decorative, never blocks a vehicle; CanCollide off on the arm)
	local px, pz = 10.6, -7.6
	api.box("BoomPost", Vector3.new(0.9, 3.4, 0.9), Vector3.new(px, 1.7, pz), hazard, Enum.Material.SmoothPlastic)
	local pivot = Vector3.new(px, 3.4, pz)
	local a = math.rad(80)
	local dir = Vector3.new(math.cos(a), math.sin(a), 0)
	local armLen = 12.5
	local armCF = CFrame.lookAt(pivot, pivot + dir)
	api.part("BoomArm", Vector3.new(0.45, 0.45, armLen), armCF * CFrame.new(0, 0, -armLen * 0.5), Color3.fromRGB(236, 236, 228), Enum.Material.SmoothPlastic, false)
	for _, k in ipairs({ 0.35, 0.75 }) do
		api.part("BoomStripe", Vector3.new(0.5, 0.5, 1.6), armCF * CFrame.new(0, 0, -armLen * k), Color3.fromRGB(186, 44, 40), Enum.Material.SmoothPlastic, false)
	end

	-- Jersey barriers shielding the booth from the gate (L1: 2, L2+: 4), on the ground. 2 parts each (base + top).
	-- x <= 7.9: clear of the L4+ gate AutoGun nest (GateDefenseService, gate-local (-7, 0, -7.5) = here (11, 5) +- 2.75)
	local jx = { 6.2, 2.6, -1.0, -4.6 }
	for i = 1, (if lv >= 2 then 4 else 2) do
		local x = jx[i]
		api.box("JerseyBase", Vector3.new(3.4, 1.0, 1.5), Vector3.new(x, 0.5, 4.5), concrete, Enum.Material.Concrete)
		api.box("JerseyTop", Vector3.new(3.4, 1.8, 0.7), Vector3.new(x, 1.9, 4.5), concrete, Enum.Material.Concrete)
	end

	-- Floodlight: pole + angled housing + lens, aimed down at the lane (SpotLight, v70 light rules)
	local function flood(fx: number, fz: number)
		api.box("FloodPole", Vector3.new(0.4, 10, 0.4), Vector3.new(fx, 5, fz), col.Metal, Enum.Material.Metal, false)
		local head = CFrame.new(fx, 10.2, fz) * CFrame.Angles(0, 0, math.rad(-35))
		api.part("FloodHousing", Vector3.new(1.1, 1.0, 1.8), head, col.Dark, Enum.Material.Metal, false)
		local lens = api.part("FloodLens", Vector3.new(0.1, 0.8, 1.6), head * CFrame.new(0.6, 0, 0), LIGHTS.FixtureColor or col.Light, LIGHTS.FixtureMaterial or Enum.Material.SmoothPlastic, false)
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Right
		spot.Angle = 70
		spot.Range = math.min(30, LIGHTS.SpotMaxRange or 30)
		spot.Brightness = 2 * (LIGHTS.BrightnessScale or 0.35)
		spot.Color = col.Light
		spot.Shadows = false
		spot.Parent = lens
	end
	flood(4.2, -7.4)
	if lv >= 5 then
		flood(-2.8, 6.6)
	end

	-- Czech hedgehog tank traps between the barriers and the wall (L3+): thick rusty beams
	if lv >= 3 then
		for _, tx in ipairs({ 2.4, -3.6 }) do
			local c = CFrame.new(tx, 1.75, 7.2) -- beam ends on the ground; clear of the perimeter wall (6.3 thick at L5)
			api.part("TankTrap", Vector3.new(0.7, 0.7, 4.2), c * CFrame.Angles(math.rad(45), 0, 0), rust, Enum.Material.CorrodedMetal)
			api.part("TankTrap", Vector3.new(0.7, 0.7, 4.2), c * CFrame.Angles(0, 0, math.rad(45)) * CFrame.Angles(0, math.rad(90), 0), rust, Enum.Material.CorrodedMetal)
			api.part("TankTrap", Vector3.new(0.7, 0.7, 4.2), c * CFrame.Angles(0, math.rad(45), math.rad(-45)), rust, Enum.Material.CorrodedMetal)
		end
	end

	-- Sandbagged gun nest at the flag, facing the gate (L4+)
	if lv >= 4 then
		api.sandbags(-2.6, 2.6, 2.2, y0)
		api.box("NestTripod", Vector3.new(0.4, 1.4, 0.4), Vector3.new(1.3, y0 + 0.7, 1.0), col.Metal, Enum.Material.Metal, false)
		api.box("NestGun", Vector3.new(0.5, 0.5, 1.6), Vector3.new(1.3, y0 + 1.6, 1.3), col.Dark, Enum.Material.Metal, false)
	end
end
