--!strict
--[[
	Part-kit builders for base structures (no MeshIds required).
	Used by BaseService to ENSURE visible kits exist on purchase / join rehydrate,
	even if MapSetup plinths are bare or kits were stripped.
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StructureVisualConfig = require(Shared.Configs.StructureVisualConfig)
local Constants = require(Shared.Constants)

local StructureKitBuilder = {}

local KIT_GEN = 26 -- v38: densify Warehouse interior crate props

local PERIMETER_FOLDER = "WE_PerimeterWalls"
local CORNER_FOLDER = "WE_CornerTowers"
local CEILING_FOLDER = "WE_BaseCeiling"
local CEILING_UNLOCK_WALLS = 3 -- DefensiveWalls ≥ L3 unlocks anti-heli roof

local function makePart(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Name = props.Name or "Part"
	if props.Size then
		p.Size = props.Size
	end
	if props.CFrame then
		p.CFrame = props.CFrame
	elseif props.Position then
		p.Position = props.Position
	end
	if props.Color then
		p.Color = props.Color
	end
	if props.Material then
		p.Material = props.Material
	end
	if props.Transparency ~= nil then
		p.Transparency = props.Transparency
	end
	if props.CanCollide ~= nil then
		p.CanCollide = props.CanCollide
	else
		p.CanCollide = false
	end
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	if props.Shape then
		p.Shape = props.Shape
	end
	p.Parent = props.Parent
	return p
end

local function kitPart(plinth: BasePart, role: string, size: Vector3, localOffset: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?)
	local p = makePart({
		Name = role,
		Size = size,
		CFrame = plinth.CFrame * CFrame.new(localOffset),
		Color = color,
		Material = material or Enum.Material.Metal,
		Transparency = 1, -- hidden until BaseService.applyKitVisuals (L0 ghost / L1+ solid)
		CanCollide = false,
		Parent = plinth,
		Shape = shape,
	})
	p:SetAttribute("WE_KitRole", role)
	p:SetAttribute("WE_BaseSize", size)
	p:SetAttribute("WE_LocalOffset", localOffset)
	p:SetAttribute("WE_Decor", true)
	return p
end

export type KitPalette = {
	Plinth: Color3,
	Body: Color3,
	Accent: Color3,
	Roof: Color3,
	Kit: string,
}

local function paletteFor(structureId: string): KitPalette
	local p = StructureVisualConfig.Palettes[structureId]
	if p then
		return p
	end
	return {
		Plinth = Color3.fromRGB(50, 55, 48),
		Body = Color3.fromRGB(70, 80, 65),
		Accent = Color3.fromRGB(200, 180, 80),
		Roof = Color3.fromRGB(45, 50, 42),
		Kit = "special",
	}
end

local function clearKitChildren(plinth: BasePart)
	for _, child in ipairs(plinth:GetChildren()) do
		if child:IsA("BasePart") and child:GetAttribute("WE_KitRole") ~= nil then
			child:Destroy()
		end
	end
end

local function countKitRoles(plinth: BasePart): number
	local n = 0
	for _, child in ipairs(plinth:GetChildren()) do
		if child:IsA("BasePart") and child:GetAttribute("WE_KitRole") ~= nil then
			n += 1
		end
	end
	return n
end

--[[ Build Part kit silhouette on plinth. Replaces any existing WE_KitRole children. ]]
function StructureKitBuilder.BuildKitOnPlinth(plinth: BasePart, structureId: string)
	local pal = paletteFor(structureId)
	local kit = pal.Kit
	clearKitChildren(plinth)

	if kit == "hq" then
		-- v34: compound-scale HQ (~TargetFootprint 36×16×28), not a player-sized cube
		kitPart(plinth, "Body", Vector3.new(28, 14, 22), Vector3.new(0, 7.5, 0), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(12, 10, 10), Vector3.new(-18, 5.5, 4), pal.Body, Enum.Material.Metal, nil) -- west wing
		kitPart(plinth, "Detail", Vector3.new(10, 8, 10), Vector3.new(16, 4.5, -2), pal.Roof, Enum.Material.Metal, nil) -- east annex
		kitPart(plinth, "Roof", Vector3.new(30, 1.4, 24), Vector3.new(0, 15, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Antenna", Vector3.new(0.45, 8, 0.45), Vector3.new(2.2, 19.5, 2.2), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Antenna", Vector3.new(0.35, 6, 0.35), Vector3.new(-18, 12, 4), pal.Accent, Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(28, 0.28, 22), Vector3.new(0, 0.75, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Detail", Vector3.new(1.4, 1.4, 1.4), Vector3.new(-4, 10, -8), pal.Accent, Enum.Material.Neon, Enum.PartType.Ball)
		kitPart(plinth, "Door", Vector3.new(3.2, 4.5, 0.4), Vector3.new(0, 3.0, -11.2), Color3.fromRGB(30, 35, 32), Enum.Material.Metal, nil)
		kitPart(plinth, "Window", Vector3.new(2.4, 1.6, 0.25), Vector3.new(6, 8, -11.1), Color3.fromRGB(70, 120, 150), Enum.Material.Glass, nil)
		kitPart(plinth, "Window", Vector3.new(2.4, 1.6, 0.25), Vector3.new(-6, 8, -11.1), Color3.fromRGB(70, 120, 150), Enum.Material.Glass, nil)
		kitPart(plinth, "Detail", Vector3.new(4, 1.2, 2), Vector3.new(0, 1.2, -14), Color3.fromRGB(55, 58, 50), Enum.Material.Concrete, nil) -- entry steps
		-- Tier 2 HQ interior / roof dress hosts (catalog via TryDressStructureInterior)
		do
			local hosts = {
				{ "WE_DressHost_Radio", Vector3.new(0.6, 2.2, 0.6), Vector3.new(-1.8, 5.2, 1.6), "RadioAntenna" },
				{ "WE_DressHost_RadioRoof", Vector3.new(0.5, 1.8, 0.5), Vector3.new(1.6, 5.4, -1.4), "RadioAntennaAlt" },
				{ "WE_DressHost_Ammo", Vector3.new(1.4, 1.0, 1.0), Vector3.new(-1.6, 1.4, 1.8), "AmmoBox" },
				{ "WE_DressHost_Crate", Vector3.new(1.6, 1.2, 1.6), Vector3.new(1.8, 1.5, 1.6), "Crate" },
				{ "WE_DressHost_MilCrate", Vector3.new(1.5, 1.1, 1.3), Vector3.new(1.8, 1.45, -1.5), "MilitaryCrate" },
				{ "WE_DressHost_Lantern", Vector3.new(0.5, 1.0, 0.5), Vector3.new(-2.0, 2.8, -1.8), "Lantern" },
				{ "WE_DressHost_Flood", Vector3.new(0.7, 1.4, 0.7), Vector3.new(-2.6, 4.2, -2.6), "Floodlight" },
				{ "WE_DressHost_Fuel", Vector3.new(1.2, 1.0, 1.2), Vector3.new(-2.2, 1.4, -0.2), "FuelCans" },
			}
			for _, h in ipairs(hosts) do
				local hp = kitPart(plinth, "DressHost", h[2], h[3], Color3.fromRGB(60, 65, 55), Enum.Material.Metal, nil)
				if hp then
					hp.Name = h[1]
					hp:SetAttribute("WE_DressProp", h[4])
					hp.Transparency = 0.85
					hp.CanCollide = false
				end
			end
			-- Gunmetal command desk fallback (no free desk Model — Part kit + SurfaceGui map)
			local desk = kitPart(plinth, "DressHost", Vector3.new(3.2, 1.1, 1.6), Vector3.new(0, 1.35, 0.4), Color3.fromRGB(55, 60, 58), Enum.Material.Metal, nil)
			if desk then
				desk.Name = "WE_CommandDesk"
				desk:SetAttribute("WE_GunmetalDesk", true)
				desk.CanCollide = false
				local top = kitPart(plinth, "DressHost", Vector3.new(3.4, 0.12, 1.8), Vector3.new(0, 1.95, 0.4), Color3.fromRGB(45, 50, 48), Enum.Material.Metal, nil)
				if top then
					top.Name = "WE_CommandDeskTop"
					top.CanCollide = false
					local sg = Instance.new("SurfaceGui")
					sg.Name = "WE_MapSurface"
					sg.Face = Enum.NormalId.Top
					sg.CanvasSize = Vector2.new(256, 128)
					sg.Parent = top
					local mapFrame = Instance.new("Frame")
					mapFrame.Name = "MapPanel"
					mapFrame.Size = UDim2.fromScale(1, 1)
					mapFrame.BackgroundColor3 = Color3.fromRGB(40, 55, 42)
					mapFrame.BorderSizePixel = 0
					mapFrame.Parent = sg
					local grid = Instance.new("TextLabel")
					grid.Size = UDim2.fromScale(1, 1)
					grid.BackgroundTransparency = 1
					grid.Text = "▌ TERRITORY MAP ▌\nN ◆ ◆ ◆\n◆ HQ ◆ ◆\n◆ ◆ ◆ S"
					grid.TextColor3 = Color3.fromRGB(120, 200, 90)
					grid.TextScaled = true
					grid.Font = Enum.Font.Code
					grid.Parent = mapFrame
				end
			end
		end
	elseif kit == "barracks" then
		-- v34: long troop housing silhouette (~28×12×16) + bunk windows + yard
		kitPart(plinth, "Body", Vector3.new(30, 12, 16), Vector3.new(0, 6.5, 0), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(32, 1.2, 18), Vector3.new(0, 13, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(30, 0.25, 16), Vector3.new(0, 0.75, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Door", Vector3.new(2.4, 3.6, 0.35), Vector3.new(0, 2.4, -8.2), Color3.fromRGB(35, 40, 32), Enum.Material.Metal, nil)
		for wi, wx in ipairs({ -10, -5, 5, 10 }) do
			kitPart(plinth, "Window", Vector3.new(2.0, 1.2, 0.22), Vector3.new(wx, 7.5, -8.1), Color3.fromRGB(70, 120, 140), Enum.Material.Glass, nil)
		end
		kitPart(plinth, "Detail", Vector3.new(0.9, 4.5, 0.9), Vector3.new(-14, 4, 4), pal.Accent, Enum.Material.Neon, nil) -- flag pole
		kitPart(plinth, "Detail", Vector3.new(2.4, 1.4, 0.2), Vector3.new(-14, 7.2, 4), Color3.fromRGB(40, 90, 50), Enum.Material.Fabric, nil) -- flag
		kitPart(plinth, "Detail", Vector3.new(14, 1.0, 3.5), Vector3.new(0, 1.1, 10), Color3.fromRGB(90, 85, 60), Enum.Material.Sand, nil) -- sandbag berm
		-- Tier 2 Barracks interior dress hosts
		do
			local hosts = {
				{ "WE_DressHost_Crate", Vector3.new(1.5, 1.1, 1.5), Vector3.new(2.4, 1.4, 1.4), "Crate" },
				{ "WE_DressHost_MilCrate", Vector3.new(1.4, 1.0, 1.2), Vector3.new(-2.4, 1.35, 1.4), "MilitaryCrate" },
				{ "WE_DressHost_Ammo", Vector3.new(1.2, 0.9, 0.9), Vector3.new(2.2, 1.3, -1.5), "AmmoBox" },
				{ "WE_DressHost_Lantern", Vector3.new(0.5, 1.0, 0.5), Vector3.new(-2.6, 2.4, -1.2), "Lantern" },
				{ "WE_DressHost_Sandbag", Vector3.new(2.4, 1.0, 1.2), Vector3.new(0, 1.2, 1.8), "Sandbag" },
			}
			for _, h in ipairs(hosts) do
				local hp = kitPart(plinth, "DressHost", h[2], h[3], Color3.fromRGB(60, 65, 55), Enum.Material.Metal, nil)
				if hp then
					hp.Name = h[1]
					hp:SetAttribute("WE_DressProp", h[4])
					hp.Transparency = 0.85
					hp.CanCollide = false
				end
			end
		end
	elseif kit == "depot" then
		kitPart(plinth, "Body", Vector3.new(32, 12, 22), Vector3.new(0, 6.5, 0), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(7.3, 0.4, 6.1), Vector3.new(0, 2.95, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(3.2, 0.28, 5.9), Vector3.new(0, 0.72, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Door", Vector3.new(2.8, 2.0, 0.3), Vector3.new(0, 1.6, -2.9), Color3.fromRGB(40, 50, 60), Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(1.0, 1.0, 1.0), Vector3.new(2.8, 2.4, 2.0), pal.Accent, Enum.Material.Neon, Enum.PartType.Ball)
		-- Showroom podium: PlateDark cylinder + GoldBright ring + rarity billboard host
		local podium = kitPart(plinth, "Podium", Vector3.new(3.6, 0.55, 3.6), Vector3.new(0, 0.95, 4.2), Constants.Colors.PlateDark, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		-- Cylinder default axis X — stand upright
		if podium then
			local off = podium:GetAttribute("WE_LocalOffset")
			if typeof(off) == "Vector3" then
				podium.CFrame = plinth.CFrame * CFrame.new(off :: Vector3) * CFrame.Angles(0, 0, math.rad(90))
			end
		end
		local ring = kitPart(plinth, "PodiumRing", Vector3.new(4.2, 0.18, 4.2), Vector3.new(0, 1.15, 4.2), Constants.Colors.GoldBright, Enum.Material.Neon, Enum.PartType.Cylinder)
		if ring then
			local off = ring:GetAttribute("WE_LocalOffset")
			if typeof(off) == "Vector3" then
				ring.CFrame = plinth.CFrame * CFrame.new(off :: Vector3) * CFrame.Angles(0, 0, math.rad(90))
			end
		end
		local display = kitPart(plinth, "ShowroomMesh", Vector3.new(2.4, 1.1, 4.0), Vector3.new(0, 1.85, 4.2), Color3.fromRGB(70, 88, 62), Enum.Material.Metal, nil)
		if display then
			display:SetAttribute("WE_ShowroomSpin", true)
			local bb = Instance.new("BillboardGui")
			bb.Name = "WE_RarityBillboard"
			bb.Size = UDim2.fromOffset(140, 28)
			bb.StudsOffset = Vector3.new(0, 2.4, 0)
			bb.AlwaysOnTop = true
			bb.MaxDistance = 80
			bb.Parent = display
			local lab = Instance.new("TextLabel")
			lab.Size = UDim2.fromScale(1, 1)
			lab.BackgroundColor3 = Constants.Colors.PlateDark
			lab.BackgroundTransparency = 0.15
			lab.BorderSizePixel = 0
			lab.Font = Enum.Font.GothamBold
			lab.TextScaled = true
			lab.TextColor3 = Constants.Colors.GoldBright
			lab.Text = "COMMON · JEEP"
			lab.Parent = bb
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 4)
			corner.Parent = lab
		end
	
		-- Tier 2: extra pedestal hosts + flag (densify showroom)
		for pi, ox in ipairs({ -4.2, 4.2 }) do
			local ped = kitPart(plinth, "Podium", Vector3.new(2.4, 0.4, 2.4), Vector3.new(ox, 0.9, 4.0), Color3.fromRGB(40, 48, 55), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
			if ped then
				ped.Name = "ShowroomPedestalHost" .. (pi + 1)
				local off = ped:GetAttribute("WE_LocalOffset")
				if typeof(off) == "Vector3" then
					ped.CFrame = plinth.CFrame * CFrame.new(off :: Vector3) * CFrame.Angles(0, 0, math.rad(90))
				end
				ped.Transparency = 0.55
			end
		end
		local flagHost = kitPart(plinth, "DressHost", Vector3.new(0.4, 4.5, 0.4), Vector3.new(-3.6, 3.2, -2.8), Color3.fromRGB(180, 180, 180), Enum.Material.Metal, nil)
		if flagHost then
			flagHost.Name = "ShowroomFlagHost"
			flagHost:SetAttribute("WE_DressProp", "FlagPole")
			flagHost.Transparency = 0.7
			flagHost.CanCollide = false
		end
		local floodHost = kitPart(plinth, "DressHost", Vector3.new(0.6, 1.2, 0.6), Vector3.new(3.4, 3.4, -2.6), Color3.fromRGB(200, 200, 180), Enum.Material.Metal, nil)
		if floodHost then
			floodHost.Name = "WE_DressHost_DepotFlood"
			floodHost:SetAttribute("WE_DressProp", "FloodlightAlt")
			floodHost.Transparency = 0.7
		end
		-- Second bay floodlight
		local floodHost2 = kitPart(plinth, "DressHost", Vector3.new(0.6, 1.2, 0.6), Vector3.new(-3.4, 3.4, -2.6), Color3.fromRGB(200, 200, 180), Enum.Material.Metal, nil)
		if floodHost2 then
			floodHost2.Name = "WE_DressHost_DepotFlood2"
			floodHost2:SetAttribute("WE_DressProp", "Floodlight")
			floodHost2.Transparency = 0.7
		end
		local fuelHost = kitPart(plinth, "DressHost", Vector3.new(1.3, 1.0, 1.3), Vector3.new(3.2, 1.3, 2.4), Color3.fromRGB(70, 65, 45), Enum.Material.Metal, nil)
		if fuelHost then
			fuelHost.Name = "WE_DressHost_DepotFuel"
			fuelHost:SetAttribute("WE_DressProp", "FuelCans")
			fuelHost.Transparency = 0.75
			fuelHost.CanCollide = false
		end
	elseif kit == "lab" then
		kitPart(plinth, "Body", Vector3.new(20, 10, 14), Vector3.new(0, 5.5, 0), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(5.5, 0.5, 5.5), Vector3.new(0, 4.0, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Antenna", Vector3.new(0.4, 3.8, 0.4), Vector3.new(0, 6.1, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Accent", Vector3.new(5.7, 0.2, 5.7), Vector3.new(0, 0.7, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Window", Vector3.new(1.5, 1.2, 0.2), Vector3.new(0, 2.6, -2.6), Color3.fromRGB(80, 160, 200), Enum.Material.Glass, nil)
		kitPart(plinth, "Detail", Vector3.new(0.9, 0.9, 0.9), Vector3.new(2.0, 3.5, 2.0), pal.Accent, Enum.Material.Neon, Enum.PartType.Ball)
	elseif kit == "tower" then
		-- v33: ≥28–32 stud sniper tower (walkable ladder + platform), not a stub
		kitPart(plinth, "Body", Vector3.new(10, 28, 10), Vector3.new(0, 14.5, 0), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(14, 0.6, 14), Vector3.new(0, 29.2, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(16, 0.45, 16), Vector3.new(0, 27.8, 0), pal.Roof, Enum.Material.Metal, nil) -- lookout deck
		kitPart(plinth, "Antenna", Vector3.new(0.4, 5.5, 0.4), Vector3.new(0, 32.5, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Accent", Vector3.new(10.4, 0.25, 10.4), Vector3.new(0, 0.7, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Window", Vector3.new(2.2, 1.4, 0.25), Vector3.new(0, 24, -5.1), Color3.fromRGB(90, 140, 180), Enum.Material.Glass, nil)
		kitPart(plinth, "Window", Vector3.new(2.2, 1.4, 0.25), Vector3.new(0, 18, -5.1), Color3.fromRGB(90, 140, 180), Enum.Material.Glass, nil)
		kitPart(plinth, "Door", Vector3.new(2.4, 3.6, 0.35), Vector3.new(0, 2.4, -5.15), Color3.fromRGB(40, 42, 36), Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(0.55, 26, 0.55), Vector3.new(5.2, 13.5, 5.2), Color3.fromRGB(55, 58, 48), Enum.Material.Metal, nil) -- ladder rail
	elseif kit == "dock" then
		-- v35: naval pier + bollards + crane silhouette + warehouse shed (readable Naval Dock)
		kitPart(plinth, "Body", Vector3.new(24, 1.4, 16), Vector3.new(0, 1.2, 0), pal.Body, Enum.Material.Concrete, nil)
		kitPart(plinth, "Pier", Vector3.new(44, 0.9, 10), Vector3.new(0, 1.5, 20), pal.Roof, Enum.Material.Wood, nil)
		kitPart(plinth, "Accent", Vector3.new(20, 0.16, 0.5), Vector3.new(0, 1.35, 0), pal.Accent, Enum.Material.Neon, nil)
		-- Bollards along pier
		for bi, bx in ipairs({ -16, -8, 0, 8, 16 }) do
			kitPart(plinth, "Detail", Vector3.new(1.1, 1.6, 1.1), Vector3.new(bx, 2.4, 24), Color3.fromRGB(50, 55, 60), Enum.Material.Metal, nil)
		end
		-- Crane mast + boom
		kitPart(plinth, "Antenna", Vector3.new(1.2, 16, 1.2), Vector3.new(-10, 9, 8), Color3.fromRGB(200, 140, 50), Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(18, 0.6, 0.6), Vector3.new(-1, 16.5, 8), Color3.fromRGB(210, 150, 55), Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(0.4, 4, 0.4), Vector3.new(7, 14, 8), Color3.fromRGB(80, 80, 75), Enum.Material.Metal, nil) -- cable
		-- Shore warehouse shed
		kitPart(plinth, "Roof", Vector3.new(14, 8, 10), Vector3.new(10, 5, -2), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Door", Vector3.new(6, 6, 0.4), Vector3.new(10, 3.5, 3.2), Color3.fromRGB(40, 55, 70), Enum.Material.Metal, nil)
		-- Tire fenders
		for _, fx in ipairs({ -12, 0, 12 }) do
			kitPart(plinth, "Detail", Vector3.new(1.8, 1.8, 0.6), Vector3.new(fx, 1.8, 25.2), Color3.fromRGB(35, 35, 35), Enum.Material.Rubber, Enum.PartType.Cylinder)
		end
		-- Shipping crate dress hosts
		do
			local hosts = {
				{ "WE_DressHost_Crate", Vector3.new(1.8, 1.4, 1.8), Vector3.new(6, 1.8, 12), "MilitaryCrate" },
				{ "WE_DressHost_Fuel", Vector3.new(1.2, 1.0, 1.2), Vector3.new(-6, 1.6, 10), "FuelCans" },
			}
			for _, h in ipairs(hosts) do
				local hp = kitPart(plinth, "DressHost", h[2], h[3], Color3.fromRGB(60, 65, 55), Enum.Material.Metal, nil)
				if hp then
					hp.Name = h[1]
					hp:SetAttribute("WE_DressProp", h[4])
					hp.Transparency = 0.85
					hp.CanCollide = false
				end
			end
		end
		-- v37: static naval boat Part-kit at pier end + DressHost for PatrolBoat mesh
		do
			local bx, bz = 0, 28
			kitPart(plinth, "ParkedBoat", Vector3.new(12, 2.2, 4.2), Vector3.new(bx, 2.4, bz), Color3.fromRGB(45, 55, 70), Enum.Material.Metal, nil) -- hull
			kitPart(plinth, "ParkedBoat", Vector3.new(3.5, 1.4, 3.2), Vector3.new(bx + 6.5, 2.6, bz), Color3.fromRGB(50, 60, 75), Enum.Material.Metal, nil) -- bow
			kitPart(plinth, "ParkedBoat", Vector3.new(4.5, 2.0, 3.0), Vector3.new(bx - 1, 4.0, bz), Color3.fromRGB(55, 62, 58), Enum.Material.Metal, nil) -- cabin
			kitPart(plinth, "ParkedBoat", Vector3.new(0.4, 2.5, 0.4), Vector3.new(bx - 2, 5.8, bz), Color3.fromRGB(70, 75, 70), Enum.Material.Metal, nil) -- mast
			kitPart(plinth, "ParkedBoat", Vector3.new(0.8, 0.35, 2.8), Vector3.new(bx + 2, 3.6, bz + 2.4), Color3.fromRGB(40, 48, 55), Enum.Material.Metal, nil) -- gunwale
			local host = kitPart(plinth, "DressHost", Vector3.new(2.8, 1.2, 2.0), Vector3.new(bx, 2.2, bz), Color3.fromRGB(60, 65, 55), Enum.Material.Metal, nil)
			if host then
				host.Name = "WE_DressHost_ParkedBoat"
				host:SetAttribute("WE_DressVehicle", "PatrolBoat")
				host:SetAttribute("WE_ParkedPresence", "Dock")
				host.Transparency = 0.9
				host.CanCollide = false
			end
		end
	elseif kit == "pad" then
		kitPart(plinth, "Body", Vector3.new(7.3, 0.45, 7.3), Vector3.new(0, 0.92, 0), pal.Body, Enum.Material.Concrete, nil)
		kitPart(plinth, "Accent", Vector3.new(6.6, 0.14, 0.5), Vector3.new(0, 1.18, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Detail", Vector3.new(0.5, 0.14, 6.6), Vector3.new(0, 1.18, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Roof", Vector3.new(1.6, 0.3, 1.6), Vector3.new(0, 1.35, 0), pal.Roof, Enum.Material.Metal, nil)
	elseif kit == "helipad" then
		-- v35: ~28 stud marked pad + circle ring + H + 4 floodlights + windsock (readable air ops)
		-- v37: static parked heli Part-kit silhouette + DressHost for VisualAssetConfig mesh
		kitPart(plinth, "Body", Vector3.new(28, 0.65, 28), Vector3.new(0, 0.95, 0), pal.Body, Enum.Material.Concrete, nil)
		kitPart(plinth, "Accent", Vector3.new(22, 0.12, 1.4), Vector3.new(0, 1.32, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Detail", Vector3.new(1.4, 0.12, 18), Vector3.new(0, 1.32, 0), pal.Accent, Enum.Material.Neon, nil)
		-- Circle ring (4 arcs as flat bars)
		for _, angOff in ipairs({ 0, 45, 90, 135 }) do
			local rad = math.rad(angOff)
			local ox = math.cos(rad) * 10
			local oz = math.sin(rad) * 10
			kitPart(plinth, "Detail", Vector3.new(8, 0.1, 0.7), Vector3.new(ox, 1.28, oz), Color3.fromRGB(245, 245, 200), Enum.Material.Neon, nil)
		end
		kitPart(plinth, "Roof", Vector3.new(4.2, 0.22, 0.7), Vector3.new(0, 1.38, 0), Color3.fromRGB(245, 245, 245), Enum.Material.SmoothPlastic, nil) -- H bar
		kitPart(plinth, "Detail", Vector3.new(0.7, 0.22, 4.2), Vector3.new(0, 1.38, 0), Color3.fromRGB(245, 245, 245), Enum.Material.SmoothPlastic, nil)
		-- Four corner floodlights
		for _, corner in ipairs({ Vector3.new(-11, 3.2, -11), Vector3.new(11, 3.2, -11), Vector3.new(-11, 3.2, 11), Vector3.new(11, 3.2, 11) }) do
			kitPart(plinth, "Antenna", Vector3.new(0.35, 5.0, 0.35), corner, pal.Accent, Enum.Material.Metal, nil)
			kitPart(plinth, "Window", Vector3.new(0.9, 0.9, 0.9), corner + Vector3.new(0, 2.6, 0), Color3.fromRGB(255, 245, 200), Enum.Material.Neon, Enum.PartType.Ball)
		end
		-- Windsock pole
		kitPart(plinth, "Antenna", Vector3.new(0.3, 6, 0.3), Vector3.new(12, 3.5, 0), Color3.fromRGB(70, 72, 68), Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(2.4, 0.9, 0.15), Vector3.new(13.2, 6.2, 0), Color3.fromRGB(220, 80, 50), Enum.Material.Fabric, nil)
		-- Ops hut
		kitPart(plinth, "Detail", Vector3.new(6, 3.5, 4), Vector3.new(-14, 2.2, 10), Color3.fromRGB(55, 60, 55), Enum.Material.Metal, nil)
		-- v37: parked transport heli silhouette (static; not flyable) offset on pad
		do
			local hx, hz = 4, -4
			kitPart(plinth, "ParkedHeli", Vector3.new(8.5, 2.4, 3.2), Vector3.new(hx, 2.6, hz), Color3.fromRGB(55, 70, 50), Enum.Material.Metal, nil) -- fuselage
			kitPart(plinth, "ParkedHeli", Vector3.new(2.2, 1.6, 2.4), Vector3.new(hx + 4.2, 2.8, hz), Color3.fromRGB(50, 62, 48), Enum.Material.Metal, nil) -- nose
			kitPart(plinth, "ParkedHeli", Vector3.new(0.35, 1.8, 0.35), Vector3.new(hx, 4.2, hz), Color3.fromRGB(40, 45, 40), Enum.Material.Metal, nil) -- mast
			kitPart(plinth, "ParkedHeli", Vector3.new(10, 0.12, 0.55), Vector3.new(hx, 5.1, hz), Color3.fromRGB(70, 75, 65), Enum.Material.Metal, nil) -- main rotor
			kitPart(plinth, "ParkedHeli", Vector3.new(0.55, 0.12, 3.5), Vector3.new(hx, 5.1, hz), Color3.fromRGB(70, 75, 65), Enum.Material.Metal, nil)
			kitPart(plinth, "ParkedHeli", Vector3.new(5.5, 0.15, 0.35), Vector3.new(hx - 5.5, 3.4, hz), Color3.fromRGB(45, 50, 42), Enum.Material.Metal, nil) -- tail boom
			kitPart(plinth, "ParkedHeli", Vector3.new(0.15, 1.4, 0.8), Vector3.new(hx - 8.2, 3.8, hz), Color3.fromRGB(60, 65, 55), Enum.Material.Metal, nil) -- tail rotor
			kitPart(plinth, "ParkedHeli", Vector3.new(0.25, 1.0, 4.5), Vector3.new(hx - 1.5, 1.55, hz), Color3.fromRGB(35, 38, 32), Enum.Material.Metal, nil) -- skid L
			kitPart(plinth, "ParkedHeli", Vector3.new(0.25, 1.0, 4.5), Vector3.new(hx + 1.5, 1.55, hz), Color3.fromRGB(35, 38, 32), Enum.Material.Metal, nil) -- skid R
			local host = kitPart(plinth, "DressHost", Vector3.new(2.5, 1.2, 2.5), Vector3.new(hx, 2.2, hz), Color3.fromRGB(60, 65, 55), Enum.Material.Metal, nil)
			if host then
				host.Name = "WE_DressHost_ParkedHeli"
				host:SetAttribute("WE_DressVehicle", "TransportHeli")
				host:SetAttribute("WE_ParkedPresence", "Helipad")
				host.Transparency = 0.9
				host.CanCollide = false
			end
		end
	elseif kit == "airfield" then
		-- v33: readable runway + taxi + large hangar volume (mesh composite dresses on top)
		-- v37: centerline dashes + threshold chevrons + taxi edge lights
		kitPart(plinth, "Body", Vector3.new(72, 0.85, 14), Vector3.new(0, 0.95, 20), Color3.fromRGB(42, 44, 46), Enum.Material.Asphalt, nil)
		kitPart(plinth, "Accent", Vector3.new(64, 0.14, 0.55), Vector3.new(0, 1.42, 20), Color3.fromRGB(245, 245, 210), Enum.Material.Neon, nil)
		-- v37: runway centerline dashed stripes (white Neon)
		for i = -5, 5 do
			if i ~= 0 then
				kitPart(plinth, "Detail", Vector3.new(2.6, 0.1, 0.45), Vector3.new(i * 5.5, 1.42, 20), Color3.fromRGB(255, 255, 245), Enum.Material.Neon, nil)
			end
		end
		-- v37: threshold chevrons at both runway ends (>>>> style)
		for _, side in ipairs({ -1, 1 }) do
			local baseX = side * 30
			for ci = 0, 3 do
				local ox = baseX - side * (ci * 2.2)
				kitPart(plinth, "Detail", Vector3.new(1.6, 0.11, 0.55), Vector3.new(ox, 1.43, 20 - 3.2), Color3.fromRGB(255, 255, 220), Enum.Material.Neon, nil)
				kitPart(plinth, "Detail", Vector3.new(1.6, 0.11, 0.55), Vector3.new(ox, 1.43, 20 + 3.2), Color3.fromRGB(255, 255, 220), Enum.Material.Neon, nil)
			end
		end
		-- runway edge lights / chevron dashes (kept)
		for i = -3, 3 do
			kitPart(plinth, "Detail", Vector3.new(3.2, 0.12, 0.7), Vector3.new(i * 9, 1.4, 20), Color3.fromRGB(255, 255, 230), Enum.Material.Neon, nil)
		end
		-- v37: taxi edge lights (amber balls along taxi apron)
		for _, tz in ipairs({ -12, -6, 0, 6 }) do
			for _, tx in ipairs({ -12, 12 }) do
				kitPart(plinth, "Window", Vector3.new(0.55, 0.55, 0.55), Vector3.new(tx, 1.55, tz), Color3.fromRGB(255, 190, 60), Enum.Material.Neon, Enum.PartType.Ball)
			end
		end
		kitPart(plinth, "Detail", Vector3.new(28, 0.6, 18), Vector3.new(0, 0.95, -6), Color3.fromRGB(55, 58, 55), Enum.Material.Concrete, nil) -- taxi
		kitPart(plinth, "Roof", Vector3.new(40, 18, 28), Vector3.new(0, 10, -24), pal.Roof, Enum.Material.Metal, nil) -- hangar shed
		kitPart(plinth, "Door", Vector3.new(0.55, 14, 22), Vector3.new(0, 8, -10), Color3.fromRGB(28, 30, 26), Enum.Material.Metal, nil)
		kitPart(plinth, "Antenna", Vector3.new(0.45, 10, 0.45), Vector3.new(24, 6, 20), pal.Accent, Enum.Material.Metal, nil) -- windsock pole
		kitPart(plinth, "Window", Vector3.new(1.4, 1.4, 1.4), Vector3.new(24, 11, 20), Color3.fromRGB(255, 180, 60), Enum.Material.Neon, Enum.PartType.Ball)
		kitPart(plinth, "Detail", Vector3.new(8, 1.2, 4), Vector3.new(-28, 1.4, 12), Color3.fromRGB(70, 72, 60), Enum.Material.Metal, nil) -- ops hut
	elseif kit == "hangar" then
		kitPart(plinth, "Body", Vector3.new(40, 18, 28), Vector3.new(0, 9.5, 0), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(42, 1.2, 30), Vector3.new(0, 19, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Door", Vector3.new(0.5, 14, 22), Vector3.new(0, 8, 14.2), Color3.fromRGB(30, 32, 28), Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(40, 0.3, 28), Vector3.new(0, 0.7, 0), pal.Accent, Enum.Material.Neon, nil)
	elseif kit == "armory" then
		-- v34: 3-story weapons inventory / armory (~28×18×18) + racks + ammo yard
		kitPart(plinth, "Body", Vector3.new(28, 18, 18), Vector3.new(0, 9.5, 0), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(30, 1.3, 20), Vector3.new(0, 19, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Door", Vector3.new(4.0, 5.5, 0.45), Vector3.new(0, 3.6, -9.2), Color3.fromRGB(40, 35, 32), Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(28, 0.3, 18), Vector3.new(0, 0.75, 0), pal.Accent, Enum.Material.Neon, nil)
		-- Floor rings read as stories
		kitPart(plinth, "Detail", Vector3.new(28.4, 0.25, 18.4), Vector3.new(0, 6.5, 0), Color3.fromRGB(55, 50, 42), Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(28.4, 0.25, 18.4), Vector3.new(0, 12.5, 0), Color3.fromRGB(55, 50, 42), Enum.Material.Metal, nil)
		-- Ammo crates + gun-rack silhouette
		kitPart(plinth, "Detail", Vector3.new(2.4, 1.6, 1.8), Vector3.new(-10, 1.3, -11.5), Color3.fromRGB(70, 65, 50), Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(2.2, 1.4, 1.6), Vector3.new(-7.2, 1.2, -11.5), Color3.fromRGB(75, 68, 52), Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(2.0, 1.2, 1.4), Vector3.new(-4.5, 1.1, -11.5), Color3.fromRGB(65, 60, 48), Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(0.35, 3.2, 6), Vector3.new(10, 2.2, -8), Color3.fromRGB(45, 48, 42), Enum.Material.Metal, nil) -- rack
		for ri = 0, 3 do
			kitPart(plinth, "Detail", Vector3.new(0.18, 0.18, 2.6), Vector3.new(9.4, 1.4 + ri * 0.7, -8), Color3.fromRGB(30, 32, 34), Enum.Material.Metal, nil)
		end
		kitPart(plinth, "Window", Vector3.new(2.6, 1.8, 0.25), Vector3.new(6, 10, -9.1), Color3.fromRGB(80, 120, 140), Enum.Material.Glass, nil)
		kitPart(plinth, "Window", Vector3.new(2.6, 1.8, 0.25), Vector3.new(-6, 10, -9.1), Color3.fromRGB(80, 120, 140), Enum.Material.Glass, nil)
		kitPart(plinth, "Antenna", Vector3.new(0.4, 5, 0.4), Vector3.new(12, 21.5, 6), pal.Accent, Enum.Material.Neon, nil)
		-- Dress hosts for catalog props
		do
			local hosts = {
				{ "WE_DressHost_Ammo", Vector3.new(1.4, 1.0, 1.0), Vector3.new(-10, 1.4, 6), "AmmoBox" },
				{ "WE_DressHost_Crate", Vector3.new(1.6, 1.2, 1.6), Vector3.new(-6, 1.5, 7), "MilitaryCrate" },
				{ "WE_DressHost_Lantern", Vector3.new(0.5, 1.0, 0.5), Vector3.new(10, 3.0, 6), "Lantern" },
				{ "WE_DressHost_Sandbag", Vector3.new(3.0, 1.0, 1.2), Vector3.new(0, 1.2, 10), "Sandbag" },
			}
			for _, h in ipairs(hosts) do
				local hp = kitPart(plinth, "DressHost", h[2], h[3], Color3.fromRGB(60, 65, 55), Enum.Material.Metal, nil)
				if hp then
					hp.Name = h[1]
					hp:SetAttribute("WE_DressProp", h[4])
					hp.Transparency = 0.85
					hp.CanCollide = false
				end
			end
		end
	elseif kit == "radar" then
		-- Dish / tower silhouette ≥20 studs (not a neon stick)
		kitPart(plinth, "Body", Vector3.new(6, 14, 6), Vector3.new(0, 7.5, 0), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(10, 1, 10), Vector3.new(0, 15, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Antenna", Vector3.new(0.6, 8, 0.6), Vector3.new(0, 19, 0), pal.Accent, Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(12, 1.2, 12), Vector3.new(0, 22, 0), pal.Accent, Enum.Material.Metal, Enum.PartType.Cylinder) -- dish
		kitPart(plinth, "Window", Vector3.new(3, 3, 3), Vector3.new(0, 22, 0), Color3.fromRGB(100, 200, 255), Enum.Material.Neon, Enum.PartType.Ball)
		kitPart(plinth, "Accent", Vector3.new(7, 0.25, 7), Vector3.new(0, 0.7, 0), pal.Accent, Enum.Material.Neon, nil)
	elseif kit == "wall" then
		-- Pad-local wall segment (perimeter walls are separate)
		kitPart(plinth, "Body", Vector3.new(24, 8, 3), Vector3.new(0, 4.5, 0), pal.Body, Enum.Material.Concrete, nil)
		kitPart(plinth, "Accent", Vector3.new(24.4, 0.35, 3.4), Vector3.new(0, 8.7, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Roof", Vector3.new(24, 0.5, 3.6), Vector3.new(0, 9.1, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(1.4, 2.2, 1.4), Vector3.new(-10, 7, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Detail", Vector3.new(1.4, 2.2, 1.4), Vector3.new(10, 7, 0), pal.Accent, Enum.Material.Neon, nil)
	elseif kit == "power" then
		kitPart(plinth, "Body", Vector3.new(24, 14, 18), Vector3.new(0, 7.5, 0), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(4, 4, 4), Vector3.new(0, 16, 0), pal.Accent, Enum.Material.Neon, Enum.PartType.Ball)
		kitPart(plinth, "Roof", Vector3.new(26, 0.8, 20), Vector3.new(0, 15, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(1.2, 6, 1.2), Vector3.new(8, 5, 6), Color3.fromRGB(60, 55, 40), Enum.Material.Metal, nil)
	elseif kit == "warehouse" then
		-- v33: large logistics bay volume + loading dock + crates (walkable footprint feel)
		-- v38: densify interior crate stacks at L1+ (Part props — CanCollide false)
		kitPart(plinth, "Body", Vector3.new(38, 16, 24), Vector3.new(0, 8.5, 0), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(40, 1.2, 26), Vector3.new(0, 17, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(38, 0.3, 24), Vector3.new(0, 0.75, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Door", Vector3.new(12, 12, 0.45), Vector3.new(0, 6.5, -12.2), Color3.fromRGB(50, 45, 38), Enum.Material.Metal, nil) -- roll door
		kitPart(plinth, "Detail", Vector3.new(16, 1.4, 8), Vector3.new(0, 1.3, -16), Color3.fromRGB(70, 72, 68), Enum.Material.Concrete, nil) -- loading dock
		kitPart(plinth, "Detail", Vector3.new(3.2, 2.4, 2.4), Vector3.new(-14, 1.8, -14), Color3.fromRGB(120, 95, 55), Enum.Material.Wood, nil)
		kitPart(plinth, "Detail", Vector3.new(3.0, 2.2, 2.2), Vector3.new(-10.5, 1.7, -14), Color3.fromRGB(110, 90, 50), Enum.Material.Wood, nil)
		kitPart(plinth, "Window", Vector3.new(3.5, 1.8, 0.25), Vector3.new(10, 10, -12.1), Color3.fromRGB(80, 120, 140), Enum.Material.Glass, nil)
		-- Interior crate rows (olive / wood / gunmetal stacks)
		do
			local crateColors = {
				Color3.fromRGB(120, 95, 55),
				Color3.fromRGB(95, 100, 70),
				Color3.fromRGB(70, 75, 80),
				Color3.fromRGB(110, 85, 45),
			}
			local positions = {
				Vector3.new(-12, 1.6, 6), Vector3.new(-8.5, 1.6, 6), Vector3.new(-5, 1.6, 6),
				Vector3.new(-12, 1.6, 9.5), Vector3.new(-8.5, 1.6, 9.5),
				Vector3.new(10, 1.5, 5), Vector3.new(13.5, 1.5, 5), Vector3.new(10, 1.5, 8.5),
				Vector3.new(-12, 3.6, 6), Vector3.new(-8.5, 3.6, 6), -- stacked
				Vector3.new(6, 1.4, -6), Vector3.new(9.5, 1.4, -6), Vector3.new(13, 1.4, -6),
				Vector3.new(-14, 1.5, 0), Vector3.new(-14, 1.5, 3.5),
			}
			for i, pos in ipairs(positions) do
				local col = crateColors[((i - 1) % #crateColors) + 1]
				local sz = if i % 3 == 0 then Vector3.new(2.8, 2.0, 2.4) elseif i % 2 == 0 then Vector3.new(2.4, 1.8, 2.2) else Vector3.new(3.0, 2.2, 2.6)
				kitPart(plinth, "Crate", sz, pos, col, Enum.Material.Wood, nil)
			end
			-- Dress hosts for catalog crate overlays
			local hosts = {
				{ "WE_DressHost_Crate", Vector3.new(1.6, 1.2, 1.6), Vector3.new(-6, 1.5, 8), "MilitaryCrate" },
				{ "WE_DressHost_MilCrate", Vector3.new(1.5, 1.1, 1.3), Vector3.new(8, 1.45, 7), "MilitaryCrate" },
				{ "WE_DressHost_Ammo", Vector3.new(1.4, 1.0, 1.0), Vector3.new(4, 1.3, -4), "AmmoBox" },
				{ "WE_DressHost_Fuel", Vector3.new(1.2, 1.0, 1.2), Vector3.new(-10, 1.3, -4), "FuelCans" },
				{ "WE_DressHost_Lantern", Vector3.new(0.5, 1.0, 0.5), Vector3.new(14, 4.0, 8), "Lantern" },
			}
			for _, h in ipairs(hosts) do
				local hp = kitPart(plinth, "DressHost", h[2], h[3], Color3.fromRGB(60, 65, 55), Enum.Material.Metal, nil)
				if hp then
					hp.Name = h[1]
					hp:SetAttribute("WE_DressProp", h[4])
					hp.Transparency = 0.85
					hp.CanCollide = false
				end
			end
		end
	elseif kit == "special" then
		-- v35: Special Forces compound (~28×16×18) — dark ops hall + range + watch post
		kitPart(plinth, "Body", Vector3.new(28, 14, 16), Vector3.new(0, 7.5, 0), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(30, 1.2, 18), Vector3.new(0, 15, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(28, 0.28, 16), Vector3.new(0, 0.75, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Door", Vector3.new(3.6, 5.0, 0.4), Vector3.new(0, 3.2, -8.2), Color3.fromRGB(25, 28, 32), Enum.Material.Metal, nil)
		-- Side annex (armory wing)
		kitPart(plinth, "Detail", Vector3.new(12, 10, 10), Vector3.new(-18, 5.5, 2), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(10, 8, 8), Vector3.new(16, 4.5, -2), Color3.fromRGB(40, 48, 55), Enum.Material.Metal, nil)
		-- Watch post / tower stub
		kitPart(plinth, "Antenna", Vector3.new(4, 18, 4), Vector3.new(12, 10, 10), Color3.fromRGB(38, 42, 48), Enum.Material.Metal, nil)
		kitPart(plinth, "Window", Vector3.new(2.2, 1.4, 0.25), Vector3.new(12, 16, 7.9), Color3.fromRGB(100, 160, 200), Enum.Material.Glass, nil)
		kitPart(plinth, "Antenna", Vector3.new(0.35, 6, 0.35), Vector3.new(12, 22, 10), pal.Accent, Enum.Material.Neon, nil)
		-- Training range silhouette (targets + berm)
		kitPart(plinth, "Detail", Vector3.new(16, 1.2, 3), Vector3.new(0, 1.2, 12), Color3.fromRGB(90, 85, 60), Enum.Material.Sand, nil)
		for _, tx in ipairs({ -6, 0, 6 }) do
			kitPart(plinth, "Detail", Vector3.new(0.8, 2.4, 0.3), Vector3.new(tx, 2.4, 13.5), Color3.fromRGB(180, 60, 50), Enum.Material.Metal, nil)
		end
		-- Windows + flag
		kitPart(plinth, "Window", Vector3.new(2.4, 1.6, 0.25), Vector3.new(-6, 8, -8.1), Color3.fromRGB(70, 100, 140), Enum.Material.Glass, nil)
		kitPart(plinth, "Window", Vector3.new(2.4, 1.6, 0.25), Vector3.new(6, 8, -8.1), Color3.fromRGB(70, 100, 140), Enum.Material.Glass, nil)
		kitPart(plinth, "Detail", Vector3.new(0.8, 5, 0.8), Vector3.new(-12, 4, 8), pal.Accent, Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(2.2, 1.3, 0.2), Vector3.new(-12, 7.2, 8), Color3.fromRGB(120, 50, 160), Enum.Material.Fabric, nil)
		-- Dress hosts
		do
			local hosts = {
				{ "WE_DressHost_Ammo", Vector3.new(1.4, 1.0, 1.0), Vector3.new(-10, 1.4, 6), "AmmoBox" },
				{ "WE_DressHost_Crate", Vector3.new(1.6, 1.2, 1.6), Vector3.new(-6, 1.5, 7), "MilitaryCrate" },
				{ "WE_DressHost_Sandbag", Vector3.new(3.0, 1.0, 1.2), Vector3.new(4, 1.2, 10), "Sandbag" },
				{ "WE_DressHost_Lantern", Vector3.new(0.5, 1.0, 0.5), Vector3.new(10, 3.0, 4), "Lantern" },
				{ "WE_DressHost_Flood", Vector3.new(0.7, 1.4, 0.7), Vector3.new(-14, 5.0, -6), "Floodlight" },
			}
			for _, h in ipairs(hosts) do
				local hp = kitPart(plinth, "DressHost", h[2], h[3], Color3.fromRGB(60, 65, 55), Enum.Material.Metal, nil)
				if hp then
					hp.Name = h[1]
					hp:SetAttribute("WE_DressProp", h[4])
					hp.Transparency = 0.85
					hp.CanCollide = false
				end
			end
		end
	else
		kitPart(plinth, "Body", Vector3.new(5.3, 3.5, 5.3), Vector3.new(0, 2.4, 0), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(4.2, 1.2, 4.2), Vector3.new(0, 4.6, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Antenna", Vector3.new(0.35, 4.2, 0.35), Vector3.new(0, 7.2, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Accent", Vector3.new(5.9, 0.22, 5.9), Vector3.new(0, 0.7, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Detail", Vector3.new(1.0, 1.0, 1.0), Vector3.new(2.0, 3.5, -2.0), pal.Accent, Enum.Material.Neon, Enum.PartType.Ball)
	end
	plinth:SetAttribute("WE_KitGen", KIT_GEN)
end

--[[ Ensure plinth has kit children; rebuild if missing/incomplete. Returns role count. ]]
function StructureKitBuilder.EnsureKit(plinth: BasePart, structureId: string): number
	local n = countKitRoles(plinth)
	local gen = tonumber(plinth:GetAttribute("WE_KitGen")) or 0
	local needsRebuild = gen < KIT_GEN

	-- Footprint too small (legacy pad-sized cubes) → rebuild
	if not needsRebuild then
		for _, child in ipairs(plinth:GetChildren()) do
			if child:IsA("BasePart") and child:GetAttribute("WE_KitRole") == "Body" then
				local s = child.Size
				if math.max(s.X, s.Y, s.Z) < 12 then
					needsRebuild = true
				end
				break
			end
		end
	end

	-- Tier 2: rebuild HQ/Barracks/Depot if dress / showroom densify hosts missing
	local needsDress = false
	if structureId == "CommandCenter" or structureId == "Barracks" or structureId == "VehicleDepot" or structureId == "PowerStation" or structureId == "WeaponsFacility" or structureId == "SpecialForcesFacility" or structureId == "Helipad" or structureId == "Dock" or structureId == "Airfield" or structureId == "Warehouse" then
		local hasDress = false
		for _, child in ipairs(plinth:GetChildren()) do
			if child:IsA("BasePart") then
				local nm = child.Name
				if string.sub(nm, 1, 12) == "WE_DressHost" or nm == "WE_CommandDesk" or nm == "ShowroomPedestalHost2" or nm == "ShowroomFlagHost" or child:GetAttribute("WE_KitRole") == "ParkedHeli" or child:GetAttribute("WE_KitRole") == "ParkedBoat" then
					hasDress = true
					break
				end
			end
		end
		needsDress = not hasDress
	end
	if n < 2 or needsDress or needsRebuild then
		-- Clear stale catalog dress so ScaleTo re-applies
		plinth:SetAttribute("WE_CatalogAssetId", nil)
		plinth:SetAttribute("WE_BuildingDressGen", nil)
		for _, ch in ipairs(plinth:GetChildren()) do
			if ch:IsA("Model") and (ch.Name == "WE_CatalogBuilding" or ch.Name == "WE_AirfieldComposite") then
				ch:Destroy()
			end
		end
		StructureKitBuilder.BuildKitOnPlinth(plinth, structureId)
		plinth:SetAttribute("WE_KitGen", KIT_GEN)
		n = countKitRoles(plinth)
	end
	return n
end

local function findPlotPad(plotId: number): BasePart?
	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.BasePlot)) do
		if inst:IsA("BasePart") and inst:GetAttribute("PlotId") == plotId then
			return inst
		end
	end
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	local bases = setup and setup:FindFirstChild("Bases")
	local plotFolder = bases and bases:FindFirstChild("Plot" .. tostring(plotId))
	if plotFolder then
		local pad = plotFolder:FindFirstChild("PlotPad")
		if pad and pad:IsA("BasePart") then
			return pad
		end
	end
	return nil
end

function StructureKitBuilder.FindPlotFolder(plotId: number): Folder?
	local pad = findPlotPad(plotId)
	if pad and pad.Parent and pad.Parent:IsA("Folder") then
		return pad.Parent
	end
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	local bases = setup and setup:FindFirstChild("Bases")
	local plotFolder = bases and bases:FindFirstChild("Plot" .. tostring(plotId))
	if plotFolder and plotFolder:IsA("Folder") then
		return plotFolder
	end
	return nil
end

--[[ Perimeter fortification around PlotPad.
	level 0 clears; 1+ builds a collide wall ring with a walkable gate facing PlayerSpawn.
	BUGFIX: prior WallS used span*2 which overlapped and sealed the gate on 200-stud pads.
]]
function StructureKitBuilder.SyncPerimeterWalls(plotId: number, level: number)
	local plotFolder = StructureKitBuilder.FindPlotFolder(plotId)
	local pad = findPlotPad(plotId)
	if not plotFolder or not pad then
		return
	end

	local existing = plotFolder:FindFirstChild(PERIMETER_FOLDER)
	if level <= 0 then
		if existing then
			existing:Destroy()
		end
		return
	end

	local folder: Folder
	if existing and existing:IsA("Folder") then
		existing:ClearAllChildren()
		folder = existing
	else
		if existing then
			existing:Destroy()
		end
		folder = Instance.new("Folder")
		folder.Name = PERIMETER_FOLDER
		folder.Parent = plotFolder
	end

	local pal = paletteFor("DefensiveWalls")
	local lv = math.clamp(level, 1, 5)
	local halfX = pad.Size.X * 0.5 - 1.5
	local halfZ = pad.Size.Z * 0.5 - 1.5
	-- v36: thicker/taller defensive walls at higher levels
	local thickness = 2.8 + lv * 0.7
	local height = 7.5 + lv * 2.8
	local y = pad.Position.Y + pad.Size.Y * 0.5 + height * 0.5
	local cx, cz = pad.Position.X, pad.Position.Z

	-- Clear walkable opening (8–12 studs). Posts/arch are visual-only outside this span.
	local GATE_CLEAR = 10
	local gateHalf = GATE_CLEAR * 0.5

	-- Gate faces PlayerSpawn (plot-local). Fallback: PlotForward attr, else pad LookVector / +Z.
	local gateAxis = "Z" -- gate on ±Z face; "X" = gate on ±X face
	local gateSign = 1
	local spawnPart = plotFolder:FindFirstChild("PlayerSpawn")
	local dx, dz = 0.0, 1.0
	if spawnPart and spawnPart:IsA("BasePart") then
		dx = spawnPart.Position.X - cx
		dz = spawnPart.Position.Z - cz
	else
		local attrFwd = plotFolder:GetAttribute("PlotForward")
		if typeof(attrFwd) == "Vector3" then
			dx = (attrFwd :: Vector3).X
			dz = (attrFwd :: Vector3).Z
		else
			local look = pad.CFrame.LookVector
			dx, dz = look.X, look.Z
			if math.abs(dx) < 0.05 and math.abs(dz) < 0.05 then
				dx, dz = 0, 1
			end
		end
	end
	if math.abs(dx) >= math.abs(dz) then
		gateAxis = "X"
		gateSign = if dx >= 0 then 1 else -1
	else
		gateAxis = "Z"
		gateSign = if dz >= 0 then 1 else -1
	end
	folder:SetAttribute("WE_GateAxis", gateAxis)
	folder:SetAttribute("WE_GateSign", gateSign)
	folder:SetAttribute("WE_GateClear", GATE_CLEAR)

	local function wall(name: string, size: Vector3, pos: Vector3)
		local w = makePart({
			Name = name,
			Size = size,
			Position = pos,
			Color = pal.Body,
			Material = Enum.Material.Concrete,
			Transparency = 0,
			CanCollide = true,
			Parent = folder,
		})
		w.CanTouch = false
		w.CanQuery = true
		w.CastShadow = true
		w:SetAttribute("WE_Perimeter", true)
		w:SetAttribute("PlotId", plotId)
		w:SetAttribute("WE_WallLevel", lv)
		local capH = 0.45 + lv * 0.08
		local cap = makePart({
			Name = name .. "_Cap",
			Size = Vector3.new(size.X + 0.4, capH, size.Z + 0.4),
			Position = Vector3.new(pos.X, pos.Y + height * 0.5 + capH * 0.5, pos.Z),
			Color = pal.Accent,
			Material = Enum.Material.Neon,
			Transparency = 0.05,
			CanCollide = false,
			Parent = folder,
		})
		cap:SetAttribute("WE_Perimeter", true)
		return w
	end

	-- Segment from outer corner to gate edge: length = alongHalf - gateHalf (NOT *2 — that sealed the gate).
	local function gateFaceSegments(alongHalf: number): (number, number)
		local segLen = math.max(alongHalf - gateHalf, 2)
		local mid = (alongHalf + gateHalf) * 0.5
		return segLen, mid
	end

	if gateAxis == "Z" then
		local closedZ = cz - gateSign * halfZ
		local openZ = cz + gateSign * halfZ
		wall("WallClosed", Vector3.new(halfX * 2, height, thickness), Vector3.new(cx, y, closedZ))
		wall("WallE", Vector3.new(thickness, height, halfZ * 2), Vector3.new(cx + halfX, y, cz))
		wall("WallW", Vector3.new(thickness, height, halfZ * 2), Vector3.new(cx - halfX, y, cz))
		local segLen, mid = gateFaceSegments(halfX)
		if segLen > 2 then
			wall("WallGate_L", Vector3.new(segLen, height, thickness), Vector3.new(cx - mid, y, openZ))
			wall("WallGate_R", Vector3.new(segLen, height, thickness), Vector3.new(cx + mid, y, openZ))
		end
		local postW = 2.2 + lv * 0.15
		local postH = height + 1.5
		local postY = pad.Position.Y + pad.Size.Y * 0.5 + postH * 0.5
		local postInset = gateHalf + postW * 0.5 -- outside clear opening
		for _, sx in ipairs({ -postInset, postInset }) do
			local post = makePart({
				Name = "GatePost",
				Size = Vector3.new(postW, postH, postW),
				Position = Vector3.new(cx + sx, postY, openZ),
				Color = pal.Roof,
				Material = Enum.Material.Metal,
				Transparency = 0,
				CanCollide = false,
				Parent = folder,
			})
			post:SetAttribute("WE_Perimeter", true)
			post:SetAttribute("WE_GateVisual", true)
			post.CastShadow = true
		end
		local archY = pad.Position.Y + pad.Size.Y * 0.5 + height + 0.9
		local arch = makePart({
			Name = "GateArch",
			Size = Vector3.new(GATE_CLEAR + postW * 2, 2.0 + lv * 0.25, thickness + 1.2),
			Position = Vector3.new(cx, archY, openZ),
			Color = pal.Roof,
			Material = Enum.Material.Metal,
			Transparency = 0,
			CanCollide = false,
			Parent = folder,
		})
		arch:SetAttribute("WE_Perimeter", true)
		arch:SetAttribute("WE_GateVisual", true)
		-- v36 military gate: chevron stripe + GATE sign
		makePart({
			Name = "GateChevron",
			Size = Vector3.new(GATE_CLEAR + postW, 0.35, thickness + 1.6),
			Position = Vector3.new(cx, archY + 0.9, openZ),
			Color = Color3.fromRGB(210, 170, 50),
			Material = Enum.Material.Neon,
			Transparency = 0.05,
			CanCollide = false,
			Parent = folder,
		}):SetAttribute("WE_GateVisual", true)
		do
			local bb = Instance.new("BillboardGui")
			bb.Name = "WE_GateSign"
			bb.Size = UDim2.fromOffset(120, 28)
			bb.StudsOffset = Vector3.new(0, 1.6, 0)
			bb.AlwaysOnTop = false
			bb.MaxDistance = 110
			bb.Parent = arch
			local lbl = Instance.new("TextLabel")
			lbl.Size = UDim2.fromScale(1, 1)
			lbl.BackgroundColor3 = Color3.fromRGB(24, 28, 18)
			lbl.BackgroundTransparency = 0.15
			lbl.Text = "GATE · L" .. tostring(lv)
			lbl.TextColor3 = Color3.fromRGB(230, 210, 120)
			lbl.TextStrokeTransparency = 0.3
			lbl.Font = Enum.Font.GothamBold
			lbl.TextScaled = true
			lbl.Parent = bb
		end
	else
		local closedX = cx - gateSign * halfX
		local openX = cx + gateSign * halfX
		wall("WallClosed", Vector3.new(thickness, height, halfZ * 2), Vector3.new(closedX, y, cz))
		wall("WallN", Vector3.new(halfX * 2, height, thickness), Vector3.new(cx, y, cz - halfZ))
		wall("WallS", Vector3.new(halfX * 2, height, thickness), Vector3.new(cx, y, cz + halfZ))
		local segLen, mid = gateFaceSegments(halfZ)
		if segLen > 2 then
			wall("WallGate_L", Vector3.new(thickness, height, segLen), Vector3.new(openX, y, cz - mid))
			wall("WallGate_R", Vector3.new(thickness, height, segLen), Vector3.new(openX, y, cz + mid))
		end
		local postW = 2.2 + lv * 0.15
		local postH = height + 1.5
		local postY = pad.Position.Y + pad.Size.Y * 0.5 + postH * 0.5
		local postInset = gateHalf + postW * 0.5
		for _, sz in ipairs({ -postInset, postInset }) do
			local post = makePart({
				Name = "GatePost",
				Size = Vector3.new(postW, postH, postW),
				Position = Vector3.new(openX, postY, cz + sz),
				Color = pal.Roof,
				Material = Enum.Material.Metal,
				Transparency = 0,
				CanCollide = false,
				Parent = folder,
			})
			post:SetAttribute("WE_Perimeter", true)
			post:SetAttribute("WE_GateVisual", true)
			post.CastShadow = true
		end
		local archY = pad.Position.Y + pad.Size.Y * 0.5 + height + 0.9
		local arch = makePart({
			Name = "GateArch",
			Size = Vector3.new(thickness + 1.2, 2.0 + lv * 0.25, GATE_CLEAR + postW * 2),
			Position = Vector3.new(openX, archY, cz),
			Color = pal.Roof,
			Material = Enum.Material.Metal,
			Transparency = 0,
			CanCollide = false,
			Parent = folder,
		})
		arch:SetAttribute("WE_Perimeter", true)
		arch:SetAttribute("WE_GateVisual", true)
		makePart({
			Name = "GateChevron",
			Size = Vector3.new(thickness + 1.6, 0.35, GATE_CLEAR + postW),
			Position = Vector3.new(openX, archY + 0.9, cz),
			Color = Color3.fromRGB(210, 170, 50),
			Material = Enum.Material.Neon,
			Transparency = 0.05,
			CanCollide = false,
			Parent = folder,
		}):SetAttribute("WE_GateVisual", true)
		do
			local bb = Instance.new("BillboardGui")
			bb.Name = "WE_GateSign"
			bb.Size = UDim2.fromOffset(120, 28)
			bb.StudsOffset = Vector3.new(0, 1.6, 0)
			bb.AlwaysOnTop = false
			bb.MaxDistance = 110
			bb.Parent = arch
			local lbl = Instance.new("TextLabel")
			lbl.Size = UDim2.fromScale(1, 1)
			lbl.BackgroundColor3 = Color3.fromRGB(24, 28, 18)
			lbl.BackgroundTransparency = 0.15
			lbl.Text = "GATE · L" .. tostring(lv)
			lbl.TextColor3 = Color3.fromRGB(230, 210, 120)
			lbl.TextStrokeTransparency = 0.3
			lbl.Font = Enum.Font.GothamBold
			lbl.TextScaled = true
			lbl.Parent = bb
		end
	end

	-- L3+ heavy wall catalog mesh on a few segments (Part kit remains authoritative)
	if lv >= 3 then
		task.defer(function()
			pcall(function()
				local vas = require(script.Parent.Parent.Services.VisualAssetService)
				local dressed = 0
				for _, ch in ipairs(folder:GetChildren()) do
					if dressed >= 4 then
						break
					end
					if ch:IsA("BasePart") and ch:GetAttribute("WE_Perimeter") == true and not ch:GetAttribute("WE_GateVisual") then
						if vas.TryAttachBuildingVisual(ch, "DefensiveWalls", lv) then
							dressed += 1
						end
					end
				end
			end)
		end)
	end

end


--[[ Base Ceiling — competitor anti-heli roof over plot core (ATM + main buildings).
	Unlock: DefensiveWalls ≥ L3 (wallsLevel). Gate-front spawn road stays open (no seal).
	Part-kit gunmetal/olive translucent collide plate. Optional mesh only if VisualAssetConfig.Buildings.BaseCeiling has a free ID.
]]
function StructureKitBuilder.SyncBaseCeiling(plotId: number, wallsLevel: number)
	local plotFolder = StructureKitBuilder.FindPlotFolder(plotId)
	local pad = findPlotPad(plotId)
	if not plotFolder or not pad then
		return
	end

	local existing = plotFolder:FindFirstChild(CEILING_FOLDER)
	if wallsLevel < CEILING_UNLOCK_WALLS then
		if existing then
			existing:Destroy()
		end
		plotFolder:SetAttribute("WE_BaseCeiling", false)
		return
	end

	local folder: Folder
	if existing and existing:IsA("Folder") then
		existing:ClearAllChildren()
		folder = existing
	else
		if existing then
			existing:Destroy()
		end
		folder = Instance.new("Folder")
		folder.Name = CEILING_FOLDER
		folder.Parent = plotFolder
	end

	local lv = math.clamp(wallsLevel, CEILING_UNLOCK_WALLS, 5)
	local halfX = pad.Size.X * 0.5
	local halfZ = pad.Size.Z * 0.5
	local cx, cz = pad.Position.X, pad.Position.Z
	local padTop = pad.Position.Y + pad.Size.Y * 0.5

	-- Reuse gate facing from perimeter attrs when present (keeps spawn road open)
	local peri = plotFolder:FindFirstChild(PERIMETER_FOLDER)
	local gateAxis = "Z"
	local gateSign = 1
	if peri then
		local ax = peri:GetAttribute("WE_GateAxis")
		local sg = peri:GetAttribute("WE_GateSign")
		if typeof(ax) == "string" and (ax == "X" or ax == "Z") then
			gateAxis = ax
		end
		if typeof(sg) == "number" then
			gateSign = if (sg :: number) >= 0 then 1 else -1
		end
	else
		local spawnPart = plotFolder:FindFirstChild("PlayerSpawn")
		local dx, dz = 0.0, 1.0
		if spawnPart and spawnPart:IsA("BasePart") then
			dx = spawnPart.Position.X - cx
			dz = spawnPart.Position.Z - cz
		else
			local look = pad.CFrame.LookVector
			dx, dz = look.X, look.Z
		end
		if math.abs(dx) >= math.abs(dz) then
			gateAxis = "X"
			gateSign = if dx >= 0 then 1 else -1
		else
			gateAxis = "Z"
			gateSign = if dz >= 0 then 1 else -1
		end
	end

	-- Cover core (~70% pad) but stop short of gate face so spawn road stays fly/walk open
	local GATE_FRONT_OPEN = 34 -- studs from gate-edge pad rim left uncovered
	local coverFrac = 0.72
	local roofThick = 1.85 + lv * 0.12 -- thicker slab + beams below (not a paper roof)
	-- Wall height formula mirrors SyncPerimeterWalls so roof sits above walls
	local wallH = 6.5 + lv * 2.2
	local roofY = padTop + wallH + 2.4 + roofThick * 0.5

	local sizeX: number
	local sizeZ: number
	local posX: number
	local posZ: number
	if gateAxis == "Z" then
		sizeX = halfX * 2 * coverFrac
		sizeZ = halfZ * 2 * coverFrac - GATE_FRONT_OPEN * 0.55
		sizeZ = math.max(sizeZ, halfZ * 0.85)
		posX = cx
		-- Shift toward CLOSED face (opposite gateSign)
		local closedEdge = cz - gateSign * halfZ
		local openEdge = cz + gateSign * halfZ
		-- Roof center: midway between closed edge and (open edge - GATE_FRONT_OPEN)
		local coveredOpen = openEdge - gateSign * GATE_FRONT_OPEN
		posZ = (closedEdge + coveredOpen) * 0.5
		-- Clamp size so roof does not spill past coveredOpen
		local span = math.abs(coveredOpen - closedEdge)
		sizeZ = math.min(sizeZ, span - 4)
		sizeZ = math.max(sizeZ, 40)
	else
		sizeZ = halfZ * 2 * coverFrac
		sizeX = halfX * 2 * coverFrac - GATE_FRONT_OPEN * 0.55
		sizeX = math.max(sizeX, halfX * 0.85)
		posZ = cz
		local closedEdge = cx - gateSign * halfX
		local openEdge = cx + gateSign * halfX
		local coveredOpen = openEdge - gateSign * GATE_FRONT_OPEN
		posX = (closedEdge + coveredOpen) * 0.5
		local span = math.abs(coveredOpen - closedEdge)
		sizeX = math.min(sizeX, span - 4)
		sizeX = math.max(sizeX, 40)
	end

	-- Gunmetal / olive translucent anti-heli plate
	local roofColor = Color3.fromRGB(58, 68, 55) -- olive gunmetal
	local accentColor = Color3.fromRGB(90, 100, 88)
	local roof = makePart({
		Name = "CeilingPlate",
		Size = Vector3.new(sizeX, roofThick, sizeZ),
		Position = Vector3.new(posX, roofY, posZ),
		Color = roofColor,
		Material = Enum.Material.Metal,
		Transparency = 0.18,
		CanCollide = true,
		Parent = folder,
	})
	roof.CanTouch = false
	roof.CanQuery = true
	roof.CastShadow = true
	roof:SetAttribute("WE_BaseCeiling", true)
	roof:SetAttribute("PlotId", plotId)
	roof:SetAttribute("WE_CeilingLevel", lv)

	-- Edge trim (visual only)
	local trimH = 0.55
	local trimY = roofY + roofThick * 0.5 + trimH * 0.5
	for _, edge in ipairs({
		{ Name = "TrimN", Size = Vector3.new(sizeX + 1.2, trimH, 1.0), Pos = Vector3.new(posX, trimY, posZ - sizeZ * 0.5) },
		{ Name = "TrimS", Size = Vector3.new(sizeX + 1.2, trimH, 1.0), Pos = Vector3.new(posX, trimY, posZ + sizeZ * 0.5) },
		{ Name = "TrimE", Size = Vector3.new(1.0, trimH, sizeZ + 1.2), Pos = Vector3.new(posX + sizeX * 0.5, trimY, posZ) },
		{ Name = "TrimW", Size = Vector3.new(1.0, trimH, sizeZ + 1.2), Pos = Vector3.new(posX - sizeX * 0.5, trimY, posZ) },
	}) do
		local t = makePart({
			Name = edge.Name,
			Size = edge.Size,
			Position = edge.Pos,
			Color = accentColor,
			Material = Enum.Material.Neon,
			Transparency = 0.35,
			CanCollide = false,
			Parent = folder,
		})
		t:SetAttribute("WE_BaseCeiling", true)
	end

	-- Support posts under closed-side corners (not gate side) — visual only
	local postH = roofY - padTop - roofThick * 0.5
	postH = math.max(postH, 8)
	local postY = padTop + postH * 0.5
	local insetX = sizeX * 0.42
	local insetZ = sizeZ * 0.42
	local posts = {
		Vector3.new(posX - insetX, postY, posZ - insetZ),
		Vector3.new(posX + insetX, postY, posZ - insetZ),
		Vector3.new(posX - insetX, postY, posZ + insetZ),
		Vector3.new(posX + insetX, postY, posZ + insetZ),
	}
	for i, ppos in ipairs(posts) do
		-- Skip posts near gate face
		local nearGate = false
		if gateAxis == "Z" then
			nearGate = (gateSign > 0 and ppos.Z > posZ + sizeZ * 0.15) or (gateSign < 0 and ppos.Z < posZ - sizeZ * 0.15)
		else
			nearGate = (gateSign > 0 and ppos.X > posX + sizeX * 0.15) or (gateSign < 0 and ppos.X < posX - sizeX * 0.15)
		end
		if not nearGate then
			local post = makePart({
				Name = "CeilingPost" .. i,
				Size = Vector3.new(1.4, postH, 1.4),
				Position = ppos,
				Color = Color3.fromRGB(48, 52, 46),
				Material = Enum.Material.Metal,
				Transparency = 0.05,
				CanCollide = false,
				Parent = folder,
			})
			post.CastShadow = true
			post:SetAttribute("WE_BaseCeiling", true)
		end
	end

	-- Cross beams + joists under plate so roof reads as structure (not a flat slab)
	do
		local beamColor = Color3.fromRGB(42, 48, 40)
		local beamY = roofY - roofThick * 0.5 - 0.55
		local beamThick = 0.9
		local beamDeep = 1.35
		-- Longitudinal beams (along longer roof axis)
		local longCount = 3
		for i = 1, longCount do
			local t = (i - 1) / math.max(1, longCount - 1) -- 0..1
			if sizeX >= sizeZ then
				-- beams run along X, spaced on Z
				local zOff = (t - 0.5) * sizeZ * 0.7
				local b = makePart({
					Name = "CeilingBeamLong" .. i,
					Size = Vector3.new(sizeX * 0.92, beamDeep, beamThick),
					Position = Vector3.new(posX, beamY, posZ + zOff),
					Color = beamColor,
					Material = Enum.Material.Metal,
					Transparency = 0.05,
					CanCollide = false,
					Parent = folder,
				})
				b.CastShadow = true
				b:SetAttribute("WE_BaseCeiling", true)
			else
				local xOff = (t - 0.5) * sizeX * 0.7
				local b = makePart({
					Name = "CeilingBeamLong" .. i,
					Size = Vector3.new(beamThick, beamDeep, sizeZ * 0.92),
					Position = Vector3.new(posX + xOff, beamY, posZ),
					Color = beamColor,
					Material = Enum.Material.Metal,
					Transparency = 0.05,
					CanCollide = false,
					Parent = folder,
				})
				b.CastShadow = true
				b:SetAttribute("WE_BaseCeiling", true)
			end
		end
		-- Cross joists
		local crossCount = 4
		for i = 1, crossCount do
			local t = (i - 0.5) / crossCount -- centered segments
			if sizeX >= sizeZ then
				local xOff = (t - 0.5) * sizeX * 0.85
				local b = makePart({
					Name = "CeilingJoist" .. i,
					Size = Vector3.new(beamThick * 0.85, beamDeep * 0.85, sizeZ * 0.88),
					Position = Vector3.new(posX + xOff, beamY - 0.15, posZ),
					Color = Color3.fromRGB(52, 58, 48),
					Material = Enum.Material.Metal,
					Transparency = 0.08,
					CanCollide = false,
					Parent = folder,
				})
				b:SetAttribute("WE_BaseCeiling", true)
			else
				local zOff = (t - 0.5) * sizeZ * 0.85
				local b = makePart({
					Name = "CeilingJoist" .. i,
					Size = Vector3.new(sizeX * 0.88, beamDeep * 0.85, beamThick * 0.85),
					Position = Vector3.new(posX, beamY - 0.15, posZ + zOff),
					Color = Color3.fromRGB(52, 58, 48),
					Material = Enum.Material.Metal,
					Transparency = 0.08,
					CanCollide = false,
					Parent = folder,
				})
				b:SetAttribute("WE_BaseCeiling", true)
			end
		end
		-- Corner diagonal braces (closed-side posts → plate)
		for i, ppos in ipairs(posts) do
			local nearGate = false
			if gateAxis == "Z" then
				nearGate = (gateSign > 0 and ppos.Z > posZ + sizeZ * 0.15) or (gateSign < 0 and ppos.Z < posZ - sizeZ * 0.15)
			else
				nearGate = (gateSign > 0 and ppos.X > posX + sizeX * 0.15) or (gateSign < 0 and ppos.X < posX - sizeX * 0.15)
			end
			if not nearGate then
				local mid = Vector3.new((ppos.X + posX) * 0.5, beamY - 1.2, (ppos.Z + posZ) * 0.5)
				local brace = makePart({
					Name = "CeilingBrace" .. i,
					Size = Vector3.new(0.7, 2.8, 0.7),
					Position = mid,
					Color = beamColor,
					Material = Enum.Material.Metal,
					Transparency = 0.1,
					CanCollide = false,
					Parent = folder,
				})
				brace:SetAttribute("WE_BaseCeiling", true)
			end
		end
	end

	folder:SetAttribute("WE_GateAxis", gateAxis)
	folder:SetAttribute("WE_GateSign", gateSign)
	folder:SetAttribute("WE_CeilingLevel", lv)
	plotFolder:SetAttribute("WE_BaseCeiling", true)

	-- Roof helipad dress (competitor-style vertical base): Part-kit H pad + optional Helipad catalog mesh
	local heliSize = math.clamp(math.min(sizeX, sizeZ) * 0.28, 18, 28)
	local heliY = roofY + roofThick * 0.5 + 0.35
	-- Place helipad toward CLOSED side (away from gate front)
	local heliX, heliZ = posX, posZ
	if gateAxis == "Z" then
		heliZ = posZ - gateSign * (sizeZ * 0.18)
	else
		heliX = posX - gateSign * (sizeX * 0.18)
	end
	local heliPad = makePart({
		Name = "RoofHelipad",
		Size = Vector3.new(heliSize, 0.55, heliSize),
		Position = Vector3.new(heliX, heliY, heliZ),
		Color = Color3.fromRGB(48, 52, 48),
		Material = Enum.Material.Concrete,
		Transparency = 0.05,
		CanCollide = true,
		Parent = folder,
	})
	heliPad.CastShadow = true
	heliPad:SetAttribute("WE_BaseCeiling", true)
	heliPad:SetAttribute("WE_RoofHelipad", true)
	-- Yellow H marking
	makePart({
		Name = "RoofHelipadH",
		Size = Vector3.new(heliSize * 0.12, 0.2, heliSize * 0.55),
		Position = Vector3.new(heliX, heliY + 0.4, heliZ),
		Color = Color3.fromRGB(230, 200, 60),
		Material = Enum.Material.Neon,
		Transparency = 0.1,
		CanCollide = false,
		Parent = folder,
	}):SetAttribute("WE_BaseCeiling", true)
	makePart({
		Name = "RoofHelipadHBar",
		Size = Vector3.new(heliSize * 0.42, 0.2, heliSize * 0.12),
		Position = Vector3.new(heliX, heliY + 0.4, heliZ),
		Color = Color3.fromRGB(230, 200, 60),
		Material = Enum.Material.Neon,
		Transparency = 0.1,
		CanCollide = false,
		Parent = folder,
	}):SetAttribute("WE_BaseCeiling", true)
	-- Ring
	makePart({
		Name = "RoofHelipadRing",
		Size = Vector3.new(heliSize * 0.92, 0.15, heliSize * 0.92),
		Position = Vector3.new(heliX, heliY + 0.28, heliZ),
		Color = Color3.fromRGB(200, 180, 50),
		Material = Enum.Material.Neon,
		Transparency = 0.45,
		CanCollide = false,
		Parent = folder,
	}):SetAttribute("WE_BaseCeiling", true)

	-- Roof barracks slots (1–2 small Barracks-style pads) — visual dress only; gate front stays open
	local barracksPads: { BasePart } = {}
	do
		local padSz = math.clamp(math.min(sizeX, sizeZ) * 0.14, 9, 14)
		local padY = roofY + roofThick * 0.5 + 0.38
		local bodyH = 3.6
		local spots: { Vector3 } = {}
		if gateAxis == "Z" then
			-- Flank left/right of roof; slight shift toward gate so they clear helipad (closed side)
			table.insert(spots, Vector3.new(posX - sizeX * 0.30, padY, posZ + gateSign * (sizeZ * 0.08)))
			table.insert(spots, Vector3.new(posX + sizeX * 0.30, padY, posZ + gateSign * (sizeZ * 0.08)))
		else
			table.insert(spots, Vector3.new(posX + gateSign * (sizeX * 0.08), padY, posZ - sizeZ * 0.30))
			table.insert(spots, Vector3.new(posX + gateSign * (sizeX * 0.08), padY, posZ + sizeZ * 0.30))
		end
		local nSlots = if lv >= 5 then 2 else 1
		for i = 1, math.min(nSlots, #spots) do
			local spos = spots[i]
			-- Skip if too close to helipad center
			local dx = spos.X - heliX
			local dz = spos.Z - heliZ
			if (dx * dx + dz * dz) < (heliSize * 0.55) ^ 2 then
				continue
			end
			local bPad = makePart({
				Name = "RoofBarracksPad" .. i,
				Size = Vector3.new(padSz, 0.5, padSz * 0.72),
				Position = spos,
				Color = Color3.fromRGB(62, 72, 58),
				Material = Enum.Material.Concrete,
				Transparency = 0.05,
				CanCollide = true,
				Parent = folder,
			})
			bPad.CastShadow = true
			bPad:SetAttribute("WE_BaseCeiling", true)
			bPad:SetAttribute("WE_RoofBarracks", true)
			bPad:SetAttribute("PlotId", plotId)
			-- Mini Barracks silhouette (Part-kit fallback)
			makePart({
				Name = "RoofBarracksBody" .. i,
				Size = Vector3.new(padSz * 0.78, bodyH, padSz * 0.48),
				Position = Vector3.new(spos.X, padY + 0.25 + bodyH * 0.5, spos.Z),
				Color = Color3.fromRGB(70, 82, 64),
				Material = Enum.Material.Metal,
				Transparency = 0.08,
				CanCollide = false,
				Parent = folder,
			}):SetAttribute("WE_BaseCeiling", true)
			makePart({
				Name = "RoofBarracksRoof" .. i,
				Size = Vector3.new(padSz * 0.86, 0.45, padSz * 0.55),
				Position = Vector3.new(spos.X, padY + 0.25 + bodyH + 0.3, spos.Z),
				Color = Color3.fromRGB(48, 54, 46),
				Material = Enum.Material.Metal,
				Transparency = 0.05,
				CanCollide = false,
				Parent = folder,
			}):SetAttribute("WE_BaseCeiling", true)
			makePart({
				Name = "RoofBarracksAccent" .. i,
				Size = Vector3.new(padSz * 0.35, 0.18, padSz * 0.22),
				Position = Vector3.new(spos.X, padY + 0.55, spos.Z),
				Color = Color3.fromRGB(200, 180, 70),
				Material = Enum.Material.Neon,
				Transparency = 0.25,
				CanCollide = false,
				Parent = folder,
			}):SetAttribute("WE_BaseCeiling", true)
			table.insert(barracksPads, bPad)
		end
		folder:SetAttribute("WE_RoofBarracksSlots", #barracksPads)
	end

	-- Optional catalog: BaseCeiling mesh + Helipad + Barracks dress on roof pads (existing free IDs only)
	task.defer(function()
		pcall(function()
			local vac = require(Shared.Configs.VisualAssetConfig)
			local vas = require(script.Parent.Parent.Services.VisualAssetService)
			local ref = vac.Buildings and vac.Buildings.BaseCeiling
			local aid = ref and tonumber(ref.ModelAssetId) or 0
			if aid and aid > 0 then
				vas.TryAttachBuildingVisual(roof, "BaseCeiling", lv)
			end
			-- Helipad 14313845338 already in VisualAssetConfig.Buildings — dress roof pad
			local heliRef = vac.Buildings and vac.Buildings.Helipad
			local heliAid = heliRef and tonumber(heliRef.ModelAssetId) or 0
			if heliAid and heliAid > 0 and heliPad.Parent then
				vas.TryAttachBuildingVisual(heliPad, "Helipad", 1)
			end
			-- Barracks 18798977801 — dress roof barracks pads when free catalog ID present
			local barRef = vac.Buildings and vac.Buildings.Barracks
			local barAid = barRef and tonumber(barRef.ModelAssetId) or 0
			if barAid and barAid > 0 then
				for _, bp in ipairs(barracksPads) do
					if bp.Parent then
						vas.TryAttachBuildingVisual(bp, "Barracks", 1)
					end
				end
			end
		end)
	end)
end

function StructureKitBuilder.SyncCornerTowers(plotId: number, level: number)
	local plotFolder = StructureKitBuilder.FindPlotFolder(plotId)
	local pad = findPlotPad(plotId)
	if not plotFolder or not pad then
		return
	end

	local existing = plotFolder:FindFirstChild(CORNER_FOLDER)
	if level <= 0 then
		if existing then
			existing:Destroy()
		end
		return
	end

	local folder: Folder
	if existing and existing:IsA("Folder") then
		existing:ClearAllChildren()
		folder = existing
	else
		if existing then
			existing:Destroy()
		end
		folder = Instance.new("Folder")
		folder.Name = CORNER_FOLDER
		folder.Parent = plotFolder
	end

	local pal = paletteFor("Watchtowers")
	local lv = math.clamp(level, 1, 5)
	local half = math.max(pad.Size.X, pad.Size.Z) * 0.5 - 3
	local towerW = 7 + lv * 0.5
	local towerH = 26 + lv * 2.8 -- v33: taller corner watchtowers (≥28–40)
	local y = pad.Position.Y + pad.Size.Y * 0.5 + towerH * 0.5
	local cx, cz = pad.Position.X, pad.Position.Z
	local corners = {
		Vector3.new(cx - half, y, cz - half),
		Vector3.new(cx + half, y, cz - half),
		Vector3.new(cx - half, y, cz + half),
		Vector3.new(cx + half, y, cz + half),
	}
	for i, pos in ipairs(corners) do
		local body = makePart({
			Name = "CornerTower" .. i,
			Size = Vector3.new(towerW, towerH, towerW),
			Position = pos,
			Color = pal.Body,
			Material = Enum.Material.Concrete,
			Transparency = 0,
			CanCollide = true,
			Parent = folder,
		})
		body.CastShadow = true
		body:SetAttribute("WE_CornerTower", true)
		makePart({
			Name = "TowerCap" .. i,
			Size = Vector3.new(towerW + 1.2, 0.6, towerW + 1.2),
			Position = Vector3.new(pos.X, pos.Y + towerH * 0.5 + 0.35, pos.Z),
			Color = pal.Roof,
			Material = Enum.Material.Metal,
			Transparency = 0,
			CanCollide = false,
			Parent = folder,
		})
		makePart({
			Name = "TowerPlatform" .. i,
			Size = Vector3.new(towerW + 3, 0.5, towerW + 3),
			Position = Vector3.new(pos.X, pos.Y + towerH * 0.5 - 1.2, pos.Z),
			Color = pal.Roof,
			Material = Enum.Material.Metal,
			Transparency = 0,
			CanCollide = false,
			Parent = folder,
		})
		-- Rail ring
		for _, off in ipairs({ Vector3.new(towerW * 0.7, 0, 0), Vector3.new(-towerW * 0.7, 0, 0), Vector3.new(0, 0, towerW * 0.7), Vector3.new(0, 0, -towerW * 0.7) }) do
			makePart({
				Name = "TowerRail" .. i,
				Size = Vector3.new(if math.abs(off.X) > 0 then 0.35 else towerW + 2.5, 1.6, if math.abs(off.Z) > 0 then 0.35 else towerW + 2.5),
				Position = Vector3.new(pos.X + off.X, pos.Y + towerH * 0.5 - 0.2, pos.Z + off.Z),
				Color = pal.Accent,
				Material = Enum.Material.Metal,
				Transparency = 0,
				CanCollide = false,
				Parent = folder,
			})
		end
		makePart({
			Name = "TowerBeacon" .. i,
			Size = Vector3.new(0.6, 2.2 + lv * 0.4, 0.6),
			Position = Vector3.new(pos.X, pos.Y + towerH * 0.5 + 2, pos.Z),
			Color = pal.Accent,
			Material = Enum.Material.Neon,
			Transparency = 0,
			CanCollide = false,
			Parent = folder,
		})
		-- v36: 1–2 static sniper silhouettes on tower platforms (presence; GateDefense handles combat)
		local deckY = pos.Y + towerH * 0.5 - 0.6
		local shooterCount = if lv >= 3 then 2 else 1
		for s = 1, shooterCount do
			local ox = if s == 1 then -1.4 else 1.4
			local torso = makePart({
				Name = "TowerShooter" .. i .. "_" .. s,
				Size = Vector3.new(1.1, 1.6, 0.7),
				Position = Vector3.new(pos.X + ox, deckY + 1.0, pos.Z),
				Color = Color3.fromRGB(45, 55, 40),
				Material = Enum.Material.SmoothPlastic,
				Transparency = 0,
				CanCollide = false,
				Parent = folder,
			})
			torso:SetAttribute("WE_TowerShooter", true)
			makePart({
				Name = "TowerShooterHead" .. i .. "_" .. s,
				Size = Vector3.new(0.7, 0.7, 0.7),
				Position = Vector3.new(pos.X + ox, deckY + 2.05, pos.Z),
				Color = Color3.fromRGB(55, 65, 50),
				Material = Enum.Material.SmoothPlastic,
				Transparency = 0,
				CanCollide = false,
				Parent = folder,
			})
			makePart({
				Name = "TowerRifle" .. i .. "_" .. s,
				Size = Vector3.new(0.2, 0.2, 2.2),
				Position = Vector3.new(pos.X + ox, deckY + 1.35, pos.Z - 1.3),
				Color = Color3.fromRGB(30, 30, 32),
				Material = Enum.Material.Metal,
				Transparency = 0,
				CanCollide = false,
				Parent = folder,
			})
			if s == 1 then
				local bb = Instance.new("BillboardGui")
				bb.Name = "WE_SniperCue"
				bb.Size = UDim2.fromOffset(100, 22)
				bb.StudsOffset = Vector3.new(0, 2.4, 0)
				bb.MaxDistance = 80
				bb.Parent = torso
				local lbl = Instance.new("TextLabel")
				lbl.Size = UDim2.fromScale(1, 1)
				lbl.BackgroundColor3 = Color3.fromRGB(18, 22, 14)
				lbl.BackgroundTransparency = 0.2
				lbl.Text = "SNIPER"
				lbl.TextColor3 = Color3.fromRGB(180, 220, 140)
				lbl.TextStrokeTransparency = 0.35
				lbl.Font = Enum.Font.GothamBold
				lbl.TextScaled = true
				lbl.Parent = bb
			end
		end
	end
end

function StructureKitBuilder.ClearPlotExtras(plotId: number)
	StructureKitBuilder.SyncPerimeterWalls(plotId, 0)
	StructureKitBuilder.SyncCornerTowers(plotId, 0)
	StructureKitBuilder.SyncBaseCeiling(plotId, 0)
end

return StructureKitBuilder
