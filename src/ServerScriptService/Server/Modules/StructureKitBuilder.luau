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
local HollowBuildingBuilder = require(script.Parent.HollowBuildingBuilder)
local WorldLabel = require(Shared.Util.WorldLabel)

local StructureKitBuilder = {}

local KIT_GEN = 35 -- v70: perimeter walls leave WE_WallGap openings (sea gate) + wall-mesh placement rule (was 34: installation slab Body)

local PERIMETER_FOLDER = "WE_PerimeterWalls"
local CORNER_FOLDER = "WE_CornerTowers"
local CEILING_FOLDER = "WE_BaseCeiling"
local CEILING_UNLOCK_WALLS = 3 -- DefensiveWalls ≥ L3 unlocks anti-heli roof
local GATE_SIGN_COLOR = Color3.fromRGB(230, 210, 120)

--[[ v68: kit parts are placed in the structure's site frame. With BaseLayoutConfig the upgrade slot (plinth)
	is a console and WE_SiteCFrame says where the building stands; legacy pads have no attribute (site = pad). ]]
local function siteFrame(plinth: BasePart): CFrame
	local cf = plinth:GetAttribute("WE_SiteCFrame")
	if typeof(cf) == "CFrame" then
		return cf
	end
	return plinth.CFrame
end
StructureKitBuilder.SiteFrame = siteFrame

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
	-- v44 P0: Body/Roof (and most silhouette parts) spawn SOLID. Do NOT rely on later applyKitVisuals.
	-- DressHost stays near-invisible so catalog props can overlay. L0 ghosting is applied by applyKitVisuals.
	local solid = StructureVisualConfig.SolidTransparency
	if typeof(solid) ~= "number" then
		solid = 0
	end
	solid = math.min(solid, 0.05)
	local spawnT = if role == "DressHost" then 1 else solid
	local p = makePart({
		Name = role,
		Size = size,
		CFrame = siteFrame(plinth) * CFrame.new(localOffset),
		Color = color,
		Material = material or Enum.Material.Metal,
		Transparency = spawnT,
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

	-- v66: walk-in building — the kit is only the foundation slab (Body); BaseService.applyKitVisuals
	-- syncs the HollowBuildingBuilder model for the owned level.
	-- fb2: the Helipad is an installation too (Installations/Helipad.luau); its old part kit and the static
	-- parked helicopter mock-up are gone. A helicopter the player spawns from the garage lands on the pad
	-- (VehicleConfig HelipadSpots); helicopters unlock from player level 10.
	if HollowBuildingBuilder.IsHollow(structureId) then
		local size, offset = HollowBuildingBuilder.FoundationSpec(plinth, structureId)
		if size and offset then
			local body = kitPart(plinth, "Body", size, offset, HollowBuildingBuilder.FoundationColor(structureId) or pal.Plinth, Enum.Material.Concrete, nil)
			body.CanCollide = true
			plinth:SetAttribute("WE_HollowKit", true)
			plinth:SetAttribute("WE_KitGen", KIT_GEN)
			return
		end
	end

	-- v44: MissileDefense gets launcher bay (not watchtower) — always Body+Roof
	if structureId == "MissileDefense" then
		-- v45: forced large Body+Roof (never empty pad / tiny slab)
		kitPart(plinth, "Body", Vector3.new(18, 12, 18), Vector3.new(0, 6.5, 0), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(20, 1.4, 14), Vector3.new(0, 13.2, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(18.4, 0.3, 18.4), Vector3.new(0, 0.7, 0), pal.Accent, Enum.Material.SmoothPlastic, nil)
		-- Twin launcher tubes
		kitPart(plinth, "Detail", Vector3.new(2.2, 2.2, 12), Vector3.new(-4, 8.5, 2), Color3.fromRGB(60, 55, 50), Enum.Material.Metal, Enum.PartType.Cylinder)
		kitPart(plinth, "Detail", Vector3.new(2.2, 2.2, 12), Vector3.new(4, 8.5, 2), Color3.fromRGB(60, 55, 50), Enum.Material.Metal, Enum.PartType.Cylinder)
		kitPart(plinth, "Antenna", Vector3.new(0.4, 6, 0.4), Vector3.new(0, 16, -5), pal.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Detail", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 9.5, -7), pal.Accent, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		plinth:SetAttribute("WE_KitGen", KIT_GEN)
		return
	end

	if kit == "hq" then
		-- v34: compound-scale HQ (~TargetFootprint 36×16×28), not a player-sized cube
		kitPart(plinth, "Body", Vector3.new(28, 14, 22), Vector3.new(0, 7.5, 0), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(12, 10, 10), Vector3.new(-18, 5.5, 4), pal.Body, Enum.Material.Metal, nil) -- west wing
		kitPart(plinth, "Detail", Vector3.new(10, 8, 10), Vector3.new(16, 4.5, -2), pal.Roof, Enum.Material.Metal, nil) -- east annex
		kitPart(plinth, "Roof", Vector3.new(30, 1.4, 24), Vector3.new(0, 15, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Antenna", Vector3.new(0.45, 8, 0.45), Vector3.new(2.2, 19.5, 2.2), pal.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Antenna", Vector3.new(0.35, 6, 0.35), Vector3.new(-18, 12, 4), pal.Accent, Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(28, 0.28, 22), Vector3.new(0, 0.75, 0), pal.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Detail", Vector3.new(1.4, 1.4, 1.4), Vector3.new(-4, 10, -8), pal.Accent, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
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
					sg.MaxDistance = 40 -- v70: SurfaceGuis draw near-only (CLAUDE.md budget, <= 80)
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
		kitPart(plinth, "Accent", Vector3.new(30, 0.25, 16), Vector3.new(0, 0.75, 0), pal.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Door", Vector3.new(2.4, 3.6, 0.35), Vector3.new(0, 2.4, -8.2), Color3.fromRGB(35, 40, 32), Enum.Material.Metal, nil)
		for wi, wx in ipairs({ -10, -5, 5, 10 }) do
			kitPart(plinth, "Window", Vector3.new(2.0, 1.2, 0.22), Vector3.new(wx, 7.5, -8.1), Color3.fromRGB(70, 120, 140), Enum.Material.Glass, nil)
		end
		kitPart(plinth, "Detail", Vector3.new(0.9, 4.5, 0.9), Vector3.new(-14, 4, 4), pal.Accent, Enum.Material.SmoothPlastic, nil) -- flag pole
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
		kitPart(plinth, "Roof", Vector3.new(34, 1.2, 24), Vector3.new(0, 13.2, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(32, 0.28, 22), Vector3.new(0, 0.75, 0), pal.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Door", Vector3.new(10, 8, 0.4), Vector3.new(0, 4.5, -11.2), Color3.fromRGB(40, 50, 60), Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(1.2, 1.2, 1.2), Vector3.new(12, 8, 8), pal.Accent, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		-- Showroom podium: PlateDark cylinder + spinning display (v70: the Neon podium ring and the AlwaysOnTop
		-- rarity billboard were removed, HUD spec §5)
		local podium = kitPart(plinth, "Podium", Vector3.new(3.6, 0.55, 3.6), Vector3.new(0, 0.95, 4.2), Constants.Colors.PlateDark, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		-- Cylinder default axis X — stand upright
		if podium then
			local off = podium:GetAttribute("WE_LocalOffset")
			if typeof(off) == "Vector3" then
				podium.CFrame = siteFrame(plinth) * CFrame.new(off :: Vector3) * CFrame.Angles(0, 0, math.rad(90))
			end
		end
		local display = kitPart(plinth, "ShowroomMesh", Vector3.new(2.4, 1.1, 4.0), Vector3.new(0, 1.85, 4.2), Color3.fromRGB(70, 88, 62), Enum.Material.Metal, nil)
		if display then
			display:SetAttribute("WE_ShowroomSpin", true)
		end
	
		-- Tier 2: extra pedestal hosts + flag (densify showroom)
		for pi, ox in ipairs({ -4.2, 4.2 }) do
			local ped = kitPart(plinth, "Podium", Vector3.new(2.4, 0.4, 2.4), Vector3.new(ox, 0.9, 4.0), Color3.fromRGB(40, 48, 55), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
			if ped then
				ped.Name = "ShowroomPedestalHost" .. (pi + 1)
				local off = ped:GetAttribute("WE_LocalOffset")
				if typeof(off) == "Vector3" then
					ped.CFrame = siteFrame(plinth) * CFrame.new(off :: Vector3) * CFrame.Angles(0, 0, math.rad(90))
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
		kitPart(plinth, "Antenna", Vector3.new(0.4, 3.8, 0.4), Vector3.new(0, 6.1, 0), pal.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Accent", Vector3.new(5.7, 0.2, 5.7), Vector3.new(0, 0.7, 0), pal.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Window", Vector3.new(1.5, 1.2, 0.2), Vector3.new(0, 2.6, -2.6), Color3.fromRGB(80, 160, 200), Enum.Material.Glass, nil)
		kitPart(plinth, "Detail", Vector3.new(0.9, 0.9, 0.9), Vector3.new(2.0, 3.5, 2.0), pal.Accent, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	elseif kit == "tower" then
		-- v33: ≥28–32 stud sniper tower (walkable ladder + platform), not a stub
		kitPart(plinth, "Body", Vector3.new(10, 28, 10), Vector3.new(0, 14.5, 0), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(14, 0.6, 14), Vector3.new(0, 29.2, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(16, 0.45, 16), Vector3.new(0, 27.8, 0), pal.Roof, Enum.Material.Metal, nil) -- lookout deck
		kitPart(plinth, "Antenna", Vector3.new(0.4, 5.5, 0.4), Vector3.new(0, 32.5, 0), pal.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Accent", Vector3.new(10.4, 0.25, 10.4), Vector3.new(0, 0.7, 0), pal.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Window", Vector3.new(2.2, 1.4, 0.25), Vector3.new(0, 24, -5.1), Color3.fromRGB(90, 140, 180), Enum.Material.Glass, nil)
		kitPart(plinth, "Window", Vector3.new(2.2, 1.4, 0.25), Vector3.new(0, 18, -5.1), Color3.fromRGB(90, 140, 180), Enum.Material.Glass, nil)
		kitPart(plinth, "Door", Vector3.new(2.4, 3.6, 0.35), Vector3.new(0, 2.4, -5.15), Color3.fromRGB(40, 42, 36), Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(0.55, 26, 0.55), Vector3.new(5.2, 13.5, 5.2), Color3.fromRGB(55, 58, 48), Enum.Material.Metal, nil) -- ladder rail
	elseif kit == "dock" then
		-- v35: naval pier + bollards + crane silhouette + warehouse shed (readable Naval Dock)
		kitPart(plinth, "Body", Vector3.new(24, 1.4, 16), Vector3.new(0, 1.2, 0), pal.Body, Enum.Material.Concrete, nil)
		kitPart(plinth, "Pier", Vector3.new(44, 0.9, 10), Vector3.new(0, 1.5, 20), pal.Roof, Enum.Material.Wood, nil)
		kitPart(plinth, "Accent", Vector3.new(20, 0.16, 0.5), Vector3.new(0, 1.35, 0), pal.Accent, Enum.Material.SmoothPlastic, nil)
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
		kitPart(plinth, "Accent", Vector3.new(6.6, 0.14, 0.5), Vector3.new(0, 1.18, 0), pal.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Detail", Vector3.new(0.5, 0.14, 6.6), Vector3.new(0, 1.18, 0), pal.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Roof", Vector3.new(1.6, 0.3, 1.6), Vector3.new(0, 1.35, 0), pal.Roof, Enum.Material.Metal, nil)
	elseif kit == "airfield" then
		-- v33: readable runway + taxi + large hangar volume (mesh composite dresses on top)
		-- v37: centerline dashes + threshold chevrons + taxi edge lights
		kitPart(plinth, "Body", Vector3.new(72, 0.85, 14), Vector3.new(0, 0.95, 20), Color3.fromRGB(42, 44, 46), Enum.Material.Asphalt, nil)
		kitPart(plinth, "Accent", Vector3.new(64, 0.14, 0.55), Vector3.new(0, 1.42, 20), Color3.fromRGB(245, 245, 210), Enum.Material.SmoothPlastic, nil)
		-- v37: runway centerline dashed stripes (painted white; v70 no Neon)
		for i = -5, 5 do
			if i ~= 0 then
				kitPart(plinth, "Detail", Vector3.new(2.6, 0.1, 0.45), Vector3.new(i * 5.5, 1.42, 20), Color3.fromRGB(255, 255, 245), Enum.Material.SmoothPlastic, nil)
			end
		end
		-- v37: threshold chevrons at both runway ends (>>>> style)
		for _, side in ipairs({ -1, 1 }) do
			local baseX = side * 30
			for ci = 0, 3 do
				local ox = baseX - side * (ci * 2.2)
				kitPart(plinth, "Detail", Vector3.new(1.6, 0.11, 0.55), Vector3.new(ox, 1.43, 20 - 3.2), Color3.fromRGB(255, 255, 220), Enum.Material.SmoothPlastic, nil)
				kitPart(plinth, "Detail", Vector3.new(1.6, 0.11, 0.55), Vector3.new(ox, 1.43, 20 + 3.2), Color3.fromRGB(255, 255, 220), Enum.Material.SmoothPlastic, nil)
			end
		end
		-- runway edge lights / chevron dashes (kept)
		for i = -3, 3 do
			kitPart(plinth, "Detail", Vector3.new(3.2, 0.12, 0.7), Vector3.new(i * 9, 1.4, 20), Color3.fromRGB(255, 255, 230), Enum.Material.SmoothPlastic, nil)
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
		kitPart(plinth, "Accent", Vector3.new(40, 0.3, 28), Vector3.new(0, 0.7, 0), pal.Accent, Enum.Material.SmoothPlastic, nil)
	elseif kit == "armory" then
		-- v34: 3-story weapons inventory / armory (~28×18×18) + racks + ammo yard
		kitPart(plinth, "Body", Vector3.new(28, 18, 18), Vector3.new(0, 9.5, 0), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(30, 1.3, 20), Vector3.new(0, 19, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Door", Vector3.new(4.0, 5.5, 0.45), Vector3.new(0, 3.6, -9.2), Color3.fromRGB(40, 35, 32), Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(28, 0.3, 18), Vector3.new(0, 0.75, 0), pal.Accent, Enum.Material.SmoothPlastic, nil)
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
		kitPart(plinth, "Antenna", Vector3.new(0.4, 5, 0.4), Vector3.new(12, 21.5, 6), pal.Accent, Enum.Material.SmoothPlastic, nil)
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
		kitPart(plinth, "Accent", Vector3.new(7, 0.25, 7), Vector3.new(0, 0.7, 0), pal.Accent, Enum.Material.SmoothPlastic, nil)
	elseif kit == "wall" then
		-- Pad-local wall sample (perimeter is SyncPerimeterWalls). Tall so pad never reads as flat slab.
		kitPart(plinth, "Body", Vector3.new(24, 16, 3), Vector3.new(0, 8.5, 0), pal.Body, Enum.Material.Concrete, nil)
		kitPart(plinth, "Accent", Vector3.new(24.4, 0.35, 3.4), Vector3.new(0, 16.7, 0), pal.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Roof", Vector3.new(24, 0.5, 3.6), Vector3.new(0, 17.1, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(1.4, 2.2, 1.4), Vector3.new(-10, 15, 0), pal.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Detail", Vector3.new(1.4, 2.2, 1.4), Vector3.new(10, 15, 0), pal.Accent, Enum.Material.SmoothPlastic, nil)
	elseif kit == "power" then
		kitPart(plinth, "Body", Vector3.new(24, 14, 18), Vector3.new(0, 7.5, 0), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(4, 4, 4), Vector3.new(0, 16, 0), pal.Accent, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		kitPart(plinth, "Roof", Vector3.new(26, 0.8, 20), Vector3.new(0, 15, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(1.2, 6, 1.2), Vector3.new(8, 5, 6), Color3.fromRGB(60, 55, 40), Enum.Material.Metal, nil)
	elseif kit == "warehouse" then
		-- v33: large logistics bay volume + loading dock + crates (walkable footprint feel)
		-- v38: densify interior crate stacks at L1+ (Part props — CanCollide false)
		kitPart(plinth, "Body", Vector3.new(38, 16, 24), Vector3.new(0, 8.5, 0), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(40, 1.2, 26), Vector3.new(0, 17, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(38, 0.3, 24), Vector3.new(0, 0.75, 0), pal.Accent, Enum.Material.SmoothPlastic, nil)
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
		kitPart(plinth, "Accent", Vector3.new(28, 0.28, 16), Vector3.new(0, 0.75, 0), pal.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Door", Vector3.new(3.6, 5.0, 0.4), Vector3.new(0, 3.2, -8.2), Color3.fromRGB(25, 28, 32), Enum.Material.Metal, nil)
		-- Side annex (armory wing)
		kitPart(plinth, "Detail", Vector3.new(12, 10, 10), Vector3.new(-18, 5.5, 2), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(10, 8, 8), Vector3.new(16, 4.5, -2), Color3.fromRGB(40, 48, 55), Enum.Material.Metal, nil)
		-- Watch post / tower stub
		kitPart(plinth, "Antenna", Vector3.new(4, 18, 4), Vector3.new(12, 10, 10), Color3.fromRGB(38, 42, 48), Enum.Material.Metal, nil)
		kitPart(plinth, "Window", Vector3.new(2.2, 1.4, 0.25), Vector3.new(12, 16, 7.9), Color3.fromRGB(100, 160, 200), Enum.Material.Glass, nil)
		kitPart(plinth, "Antenna", Vector3.new(0.35, 6, 0.35), Vector3.new(12, 22, 10), pal.Accent, Enum.Material.SmoothPlastic, nil)
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
		kitPart(plinth, "Antenna", Vector3.new(0.35, 4.2, 0.35), Vector3.new(0, 7.2, 0), pal.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Accent", Vector3.new(5.9, 0.22, 5.9), Vector3.new(0, 0.7, 0), pal.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Detail", Vector3.new(1.0, 1.0, 1.0), Vector3.new(2.0, 3.5, -2.0), pal.Accent, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end
	plinth:SetAttribute("WE_KitGen", KIT_GEN)
end

--[[ Ensure plinth has kit children; rebuild if missing/incomplete. Returns role count. ]]
function StructureKitBuilder.EnsureKit(plinth: BasePart, structureId: string): number
	local hollow = HollowBuildingBuilder.IsHollow(structureId)
	local n = countKitRoles(plinth)
	local gen = tonumber(plinth:GetAttribute("WE_KitGen")) or 0
	local needsRebuild = gen < KIT_GEN

	-- Always require a Body part (visibility gate). Missing Body → rebuild.
	local hasBody = false
	local bodyTooSmall = false
	for _, child in ipairs(plinth:GetChildren()) do
		if child:IsA("BasePart") and child:GetAttribute("WE_KitRole") == "Body" then
			hasBody = true
			local s = child.Size
			-- Helipad/Dock/Airfield flat decks can be thin on Y but wide on XZ
			if math.max(s.X, s.Y, s.Z) < 8 then
				bodyTooSmall = true
			end
			break
		end
	end
	if not hasBody or bodyTooSmall then
		needsRebuild = true
	end

	-- Tier 2: rebuild HQ/Barracks/Depot if dress / showroom densify hosts missing
	local needsDress = false
	if not hollow and (structureId == "CommandCenter" or structureId == "Barracks" or structureId == "VehicleDepot" or structureId == "PowerStation" or structureId == "WeaponsFacility" or structureId == "SpecialForcesFacility" or structureId == "Dock" or structureId == "Airfield" or structureId == "Warehouse") then
		local hasDress = false
		for _, child in ipairs(plinth:GetChildren()) do
			if child:IsA("BasePart") then
				local nm = child.Name
				if string.sub(nm, 1, 12) == "WE_DressHost" or nm == "WE_CommandDesk" or nm == "ShowroomPedestalHost2" or nm == "ShowroomFlagHost" or child:GetAttribute("WE_KitRole") == "ParkedBoat" then
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

	-- v43 hard assert: EnsureKit path always leaves a Body part (even if mesh later fails)
	local bodyOk = false
	for _, child in ipairs(plinth:GetChildren()) do
		if child:IsA("BasePart") and child:GetAttribute("WE_KitRole") == "Body" then
			bodyOk = true
			break
		end
	end
	if not bodyOk then
		warn("[StructureKitBuilder] EnsureKit missing Body after build — forcing generic Body", structureId)
		local pal = paletteFor(structureId)
		kitPart(plinth, "Body", Vector3.new(16, 10, 16), Vector3.new(0, 5.5, 0), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(18, 1.2, 18), Vector3.new(0, 11.2, 0), pal.Roof, Enum.Material.Metal, nil)
		plinth:SetAttribute("WE_KitGen", KIT_GEN)
		n = countKitRoles(plinth)
	end

	-- v44/v45 P0: owned kits must be solid IMMEDIATELY (do not wait for applyKitVisuals)
	local solid = StructureVisualConfig.SolidTransparency
	if typeof(solid) ~= "number" then
		solid = 0
	end
	solid = 0 -- force fully opaque Body/Roof
	local flatKit = hollow or structureId == "Dock" or structureId == "Airfield" or structureId == "DefensiveWalls"
	for _, child in ipairs(plinth:GetChildren()) do
		if child:IsA("BasePart") then
			local role = child:GetAttribute("WE_KitRole")
			if role == "Body" or role == "Roof" then
				child.Transparency = 0
				child.Anchored = true
				if role == "Body" then
					child.CanCollide = true
					if not flatKit then
						local s = child.Size
						local nx = math.max(s.X, 14)
						local ny = math.max(s.Y, 10)
						local nz = math.max(s.Z, 14)
						if nx ~= s.X or ny ~= s.Y or nz ~= s.Z then
							child.Size = Vector3.new(nx, ny, nz)
							child:SetAttribute("WE_BaseSize", child.Size)
						end
					end
				end
				if child.Parent ~= plinth then
					child.Parent = plinth
				end
			elseif role == "Accent" or role == "Antenna" or role == "Detail" or role == "Door" or role == "Window" or role == "Pier" or role == "Crate" then
				child.Anchored = true
				if child.Transparency > 0.5 then
					child.Transparency = solid
				end
			end
		end
	end
	-- MissileDefense hard force large Body+Roof after any rebuild path (not for the v68 installation slab)
	if structureId == "MissileDefense" and not hollow then
		for _, child in ipairs(plinth:GetChildren()) do
			if child:IsA("BasePart") then
				local role = child:GetAttribute("WE_KitRole")
				if role == "Body" then
					local s = child.Size
					child.Size = Vector3.new(math.max(s.X, 18), math.max(s.Y, 12), math.max(s.Z, 18))
					child.Transparency = 0
					child.CanCollide = true
					child.Anchored = true
				elseif role == "Roof" then
					local s = child.Size
					child.Size = Vector3.new(math.max(s.X, 20), math.max(s.Y, 1.2), math.max(s.Z, 14))
					child.Transparency = 0
					child.Anchored = true
				end
			end
		end
	end

	if StructureVisualConfig.Palettes[structureId] == nil then
		warn("[StructureKitBuilder] profile/structure has kit build but no StructureVisualConfig.Palettes entry:", structureId)
	end

	return n
end

local function findPlotPad(plotId: number): BasePart?
	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.BasePlot)) do
		if inst:IsA("BasePart") and tonumber(inst:GetAttribute("PlotId")) == tonumber(plotId) then
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
			print("[StructureKitBuilder] SyncPerimeterWalls CLEARED (level=0) plot=", plotId)
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

	-- v70: openings in the ring. MapSetup puts a WE_WallGap marker (world-axis-aligned box, BaseLayout.PlotRect) under
	-- LayoutGround wherever the wall must stay open (the sea gate: its posts + collidable leaves close the span).
	local gaps: { BasePart } = {}
	do
		local layoutGround = plotFolder:FindFirstChild("LayoutGround")
		if layoutGround then
			for _, d in ipairs(layoutGround:GetDescendants()) do
				if d:IsA("BasePart") and d:GetAttribute("WE_WallGap") == true then
					table.insert(gaps, d)
				end
			end
		end
	end

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
		local look = (StructureVisualConfig :: any).BaseLook or {}
		-- v67: concrete cap + razor wire (was a lime Neon cap on bright olive walls)
		local cap = makePart({
			Name = name .. "_Cap",
			Size = Vector3.new(size.X + 0.4, capH, size.Z + 0.4),
			Position = Vector3.new(pos.X, pos.Y + height * 0.5 + capH * 0.5, pos.Z),
			Color = look.WallCap or pal.Accent,
			Material = Enum.Material.Concrete,
			Transparency = 0,
			CanCollide = false,
			Parent = folder,
		})
		cap:SetAttribute("WE_Perimeter", true)
		local along = math.max(size.X, size.Z)
		local wireYaw = if size.Z > size.X then math.pi * 0.5 else 0
		local wire = makePart({
			Name = name .. "_Wire",
			Size = Vector3.new(along, 0.9, 0.9),
			CFrame = CFrame.new(pos.X, pos.Y + height * 0.5 + capH + 0.45, pos.Z) * CFrame.Angles(0, wireYaw, 0),
			Color = look.Wire or Color3.fromRGB(58, 60, 56),
			Material = Enum.Material.DiamondPlate,
			Transparency = 0,
			CanCollide = false,
			Parent = folder,
			Shape = Enum.PartType.Cylinder,
		})
		wire:SetAttribute("WE_Perimeter", true)
		return w
	end

	-- v70: a wall with every WE_WallGap span that straddles its line cut out. No gap on the line → the exact same
	-- single wall as before. [J8] The LONGEST piece keeps the base name (it may host the L3+ wall mesh); pieces
	-- shorter than 26 are flagged WE_NoMesh (a 24-long mesh would hang over the opening).
	local function gappedWall(name: string, size: Vector3, pos: Vector3)
		local alongX = size.X >= size.Z
		local half = (if alongX then size.X else size.Z) * 0.5
		local c = if alongX then pos.X else pos.Z
		local wAcross = if alongX then pos.Z else pos.X
		local wHalfT = (if alongX then size.Z else size.X) * 0.5
		local segs: { { number } } = { { c - half, c + half } }
		local cut = false
		for _, g in ipairs(gaps) do
			-- world AABB half extents of the marker (robust to a turned marker; identity → Size * 0.5)
			local gp, gs = g.Position, g.Size
			local _, _, _, r00, r01, r02, _, _, _, r20, r21, r22 = g.CFrame:GetComponents()
			local ghx = (math.abs(r00) * gs.X + math.abs(r01) * gs.Y + math.abs(r02) * gs.Z) * 0.5
			local ghz = (math.abs(r20) * gs.X + math.abs(r21) * gs.Y + math.abs(r22) * gs.Z) * 0.5
			local gAlong = if alongX then gp.X else gp.Z
			local gHalf = if alongX then ghx else ghz
			local gAcross = if alongX then gp.Z else gp.X
			local gAcrossHalf = if alongX then ghz else ghx
			if math.abs(gAcross - wAcross) <= gAcrossHalf + wHalfT then -- the gap straddles this wall's line
				local g0, g1 = gAlong - gHalf, gAlong + gHalf
				local out: { { number } } = {}
				for _, s in ipairs(segs) do
					if g1 <= s[1] or g0 >= s[2] then
						table.insert(out, s)
					else
						cut = true
						if g0 - s[1] >= 1 then
							table.insert(out, { s[1], g0 })
						end
						if s[2] - g1 >= 1 then
							table.insert(out, { g1, s[2] })
						end
					end
				end
				segs = out
			end
		end
		if not cut then
			local w = wall(name, size, pos)
			if half * 2 < 26 then
				w:SetAttribute("WE_NoMesh", true)
			end
			return
		end
		table.sort(segs, function(a, b)
			return (a[2] - a[1]) > (b[2] - b[1])
		end)
		for i, s in ipairs(segs) do
			local len, mid = s[2] - s[1], (s[1] + s[2]) * 0.5
			local pieceName = if i == 1 then name else name .. "_" .. tostring(i)
			local w = wall(
				pieceName,
				if alongX then Vector3.new(len, size.Y, size.Z) else Vector3.new(size.X, size.Y, len),
				if alongX then Vector3.new(mid, pos.Y, pos.Z) else Vector3.new(pos.X, pos.Y, mid)
			)
			w:SetAttribute("WE_WallPiece", i)
			if len < 26 then
				w:SetAttribute("WE_NoMesh", true)
			end
			-- the cap overhangs its wall by 0.2 at each end; keep it out of the opening at a cut end
			local cutLo, cutHi = s[1] > c - half + 1e-6, s[2] < c + half - 1e-6
			local cap = folder:FindFirstChild(pieceName .. "_Cap")
			if cap and cap:IsA("BasePart") and (cutLo or cutHi) then
				local capLen = len + 0.4 - (if cutLo then 0.2 else 0) - (if cutHi then 0.2 else 0)
				local capMid = mid + (if cutLo then 0.1 else 0) - (if cutHi then 0.1 else 0)
				local cs, cp = cap.Size, cap.Position
				cap.Size = if alongX then Vector3.new(capLen, cs.Y, cs.Z) else Vector3.new(cs.X, cs.Y, capLen)
				cap.Position = if alongX then Vector3.new(capMid, cp.Y, cp.Z) else Vector3.new(cp.X, cp.Y, capMid)
			end
		end
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
		gappedWall("WallClosed", Vector3.new(halfX * 2, height, thickness), Vector3.new(cx, y, closedZ))
		gappedWall("WallE", Vector3.new(thickness, height, halfZ * 2), Vector3.new(cx + halfX, y, cz))
		gappedWall("WallW", Vector3.new(thickness, height, halfZ * 2), Vector3.new(cx - halfX, y, cz))
		local segLen, mid = gateFaceSegments(halfX)
		if segLen > 2 then
			gappedWall("WallGate_L", Vector3.new(segLen, height, thickness), Vector3.new(cx - mid, y, openZ))
			gappedWall("WallGate_R", Vector3.new(segLen, height, thickness), Vector3.new(cx + mid, y, openZ))
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
			Color = ((StructureVisualConfig :: any).BaseLook or {}).GateStripe or Color3.fromRGB(214, 178, 64),
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0,
			CanCollide = false,
			Parent = folder,
		}):SetAttribute("WE_GateVisual", true)
		-- v70 (HUD spec §5): painted on the arch's outer face (was a floating BillboardGui; the name is kept)
		WorldLabel.Surface(arch, if gateSign > 0 then Enum.NormalId.Back else Enum.NormalId.Front, "GATE · L" .. tostring(lv), { Name = "WE_GateSign", Color = GATE_SIGN_COLOR })
	else
		local closedX = cx - gateSign * halfX
		local openX = cx + gateSign * halfX
		gappedWall("WallClosed", Vector3.new(thickness, height, halfZ * 2), Vector3.new(closedX, y, cz))
		gappedWall("WallN", Vector3.new(halfX * 2, height, thickness), Vector3.new(cx, y, cz - halfZ))
		gappedWall("WallS", Vector3.new(halfX * 2, height, thickness), Vector3.new(cx, y, cz + halfZ))
		local segLen, mid = gateFaceSegments(halfZ)
		if segLen > 2 then
			gappedWall("WallGate_L", Vector3.new(thickness, height, segLen), Vector3.new(openX, y, cz - mid))
			gappedWall("WallGate_R", Vector3.new(thickness, height, segLen), Vector3.new(openX, y, cz + mid))
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
			Color = ((StructureVisualConfig :: any).BaseLook or {}).GateStripe or Color3.fromRGB(214, 178, 64),
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0,
			CanCollide = false,
			Parent = folder,
		}):SetAttribute("WE_GateVisual", true)
		WorldLabel.Surface(arch, if gateSign > 0 then Enum.NormalId.Right else Enum.NormalId.Left, "GATE · L" .. tostring(lv), { Name = "WE_GateSign", Color = GATE_SIGN_COLOR })
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
					-- [J8] wall bodies only: never a cap / wire, a short piece next to an opening (WE_NoMesh) or a wall
					-- running along Z (the 24x8x3 mesh takes the host's identity rotation, so it would sit across it)
					local nm = ch.Name
					if
						ch:IsA("BasePart")
						and ch:GetAttribute("WE_Perimeter") == true
						and not ch:GetAttribute("WE_GateVisual")
						and ch:GetAttribute("WE_NoMesh") ~= true
						and string.sub(nm, -4) ~= "_Cap"
						and string.sub(nm, -5) ~= "_Wire"
						and ch.Size.Z <= ch.Size.X
					then
						if vas.TryAttachBuildingVisual(ch, "DefensiveWalls", lv) then
							dressed += 1
						end
					end
				end
			end)
		end)
	end

	folder:SetAttribute("WE_PerimeterGen", KIT_GEN)
	folder:SetAttribute("WE_WallLevel", lv)
	folder:SetAttribute("WE_WallGaps", #gaps)
	print(string.format(
		"[StructureKitBuilder] SyncPerimeterWalls SPAWNED plot=%s level=%d height=%.1f thickness=%.1f KIT_GEN=%d parts=%d gaps=%d",
		tostring(plotId),
		lv,
		height,
		thickness,
		KIT_GEN,
		#folder:GetChildren(),
		#gaps
	))

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
	-- v68: no roof at all over bases (owner request) — AntiAirCeilingEnabled = false clears any ceiling
	if (StructureVisualConfig :: any).AntiAirCeilingEnabled == false or wallsLevel < CEILING_UNLOCK_WALLS then
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

	-- v67: the anti-heli roof is an invisible barrier high above every building. The visible slab, trims,
	-- posts, beams and rooftop pads made the whole base a dark warehouse and cut through two-storey buildings.
	local ceilingHeight = tonumber((StructureVisualConfig :: any).AntiAirCeilingHeight) or 48
	local roof = makePart({
		Name = "CeilingPlate",
		Size = Vector3.new(sizeX, 2, sizeZ),
		Position = Vector3.new(posX, padTop + ceilingHeight, posZ),
		Color = Color3.fromRGB(58, 68, 55),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 1,
		CanCollide = true,
		Parent = folder,
	})
	roof.CanTouch = false
	roof.CanQuery = false -- camera + weapon raycasts pass; helicopters still collide
	roof.CastShadow = false
	roof:SetAttribute("WE_BaseCeiling", true)
	roof:SetAttribute("PlotId", plotId)
	roof:SetAttribute("WE_CeilingLevel", lv)
	plotFolder:SetAttribute("WE_BaseCeiling", true)
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
	-- v68: guard tower = concrete shaft + glazed cabin + roof, searchlight facing out
	-- (was a solid 7-10 stud concrete pillar with a rail ring). Names/attributes kept for other systems.
	local padTop = pad.Position.Y + pad.Size.Y * 0.5
	local cabinW = towerW + 1.5
	local shaftH = towerH - 4
	for i, pos in ipairs(corners) do
		local body = makePart({
			Name = "CornerTower" .. i,
			Size = Vector3.new(towerW - 2.5, shaftH, towerW - 2.5),
			Position = Vector3.new(pos.X, padTop + shaftH * 0.5, pos.Z),
			Color = pal.Body,
			Material = Enum.Material.Concrete,
			Transparency = 0,
			CanCollide = true,
			Parent = folder,
		})
		body.CastShadow = true
		body:SetAttribute("WE_CornerTower", true)
		local floorY = padTop + shaftH
		makePart({
			Name = "TowerPlatform" .. i,
			Size = Vector3.new(cabinW, 0.5, cabinW),
			Position = Vector3.new(pos.X, floorY + 0.25, pos.Z),
			Color = pal.Roof,
			Material = Enum.Material.Metal,
			Transparency = 0,
			CanCollide = true,
			Parent = folder,
		})
		-- low concrete band + glass band on all four sides
		for _, side in ipairs({ Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }) do
			local alongX = side.Z ~= 0
			local len = cabinW
			local c = Vector3.new(pos.X + side.X * (cabinW * 0.5 - 0.2), 0, pos.Z + side.Z * (cabinW * 0.5 - 0.2))
			makePart({
				Name = "TowerCabinWall" .. i,
				Size = Vector3.new(if alongX then len else 0.4, 1.0, if alongX then 0.4 else len),
				Position = Vector3.new(c.X, floorY + 1.0, c.Z),
				Color = pal.Body,
				Material = Enum.Material.Concrete,
				Transparency = 0,
				CanCollide = true,
				Parent = folder,
			})
			local glass = makePart({
				Name = "TowerCabinGlass" .. i,
				Size = Vector3.new(if alongX then len else 0.2, 2.0, if alongX then 0.2 else len),
				Position = Vector3.new(c.X, floorY + 2.5, c.Z),
				Color = Color3.fromRGB(140, 180, 200),
				Material = Enum.Material.Glass,
				Transparency = 0.45,
				CanCollide = false,
				Parent = folder,
			})
			glass.CastShadow = false
		end
		makePart({
			Name = "TowerCap" .. i,
			Size = Vector3.new(cabinW + 1.2, 0.6, cabinW + 1.2),
			Position = Vector3.new(pos.X, floorY + 3.8, pos.Z),
			Color = pal.Roof,
			Material = Enum.Material.Metal,
			Transparency = 0,
			CanCollide = false,
			Parent = folder,
		})
		-- searchlight on the roof edge, pointing away from the plot centre
		local out = Vector3.new(pos.X - cx, 0, pos.Z - cz)
		out = if out.Magnitude > 0.1 then out.Unit else Vector3.new(0, 0, 1)
		local lampPos = Vector3.new(pos.X + out.X * (cabinW * 0.5 - 0.6), floorY + 4.6, pos.Z + out.Z * (cabinW * 0.5 - 0.6))
		local lamp = makePart({
			Name = "TowerSearchlight" .. i,
			Size = Vector3.new(1.2, 1, 1.2),
			Position = lampPos,
			Color = Color3.fromRGB(255, 236, 200),
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0,
			CanCollide = false,
			Parent = folder,
		})
		lamp.CFrame = CFrame.lookAt(lampPos, lampPos + out)
		local lights = (StructureVisualConfig :: any).BuildingLights or {}
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Angle = 45
		spot.Range = math.min(50, lights.SpotMaxRange or 50)
		spot.Brightness = 1.5 * (lights.BrightnessScale or 1)
		spot.Color = Color3.fromRGB(255, 236, 200)
		spot.Shadows = false
		spot.Parent = lamp
		-- v70 (HUD spec §5): no red beacon ball on the cabin roof
		-- v36: 1–2 static sniper silhouettes on tower platforms (presence; GateDefense handles combat)
		local deckY = floorY + 0.5
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
			-- v70 (HUD spec §5): no "SNIPER" cue billboard over the silhouette
		end
	end
end

--[[ v68: open / close the rear-zone gates (MapSetup LayoutGround.RearGate_<StructureId>) from the owner's
	upgrade levels. A gate opens once its structure is L1+: the leaves slide into the wall and stop colliding. ]]
local REAR_GATE_LABELS: { [string]: string } = { Airfield = "AIRFIELD", Helipad = "HELIPAD", Dock = "NAVAL DOCK" }

-- v70: lintel sign from the folder state: label (WE_GateLabel, else the rear-gate label) + OPEN, CLOSED (an armed
-- proximity gate waiting for a boat) or LOCKED.
local function refreshGateSign(gateFolder: Instance)
	local lintel = gateFolder:FindFirstChild("GateLintel")
	local sign = lintel and lintel:FindFirstChild("WE_GateSign")
	local text = sign and sign:FindFirstChild("Text")
	if not (text and text:IsA("TextLabel")) then
		return
	end
	local gid = gateFolder:GetAttribute("GateId")
	local gidText = if typeof(gid) == "string" then gid else "GATE"
	local label = gateFolder:GetAttribute("WE_GateLabel")
	local base = if typeof(label) == "string" then label else (REAR_GATE_LABELS[gidText] or string.upper(gidText))
	local suffix = " · LOCKED"
	if gateFolder:GetAttribute("WE_GateOpen") == true then
		suffix = " · OPEN"
	elseif gateFolder:GetAttribute("WE_GateMode") == "Proximity" and gateFolder:GetAttribute("WE_GateArmed") == true then
		suffix = " · CLOSED"
	end
	text.Text = base .. suffix
end

--[[ v70: open / close one gate folder (rear gate or sea gate). Every child leaf with a numeric WE_GateLeaf (slide
	sign) and a CFrame WE_ClosedCFrame slides along its OWN X by its width + 0.3 (into the wall line; identical to the
	old world-X slide on an unturned plot) and stops colliding; its BasePart children move with it. Idempotent:
	Waterways' sea-gate loop calls it only when the state changes. ]]
function StructureKitBuilder.SetGateOpen(gateFolder: Instance, open: boolean)
	for _, leaf in ipairs(gateFolder:GetChildren()) do
		local sx = leaf:GetAttribute("WE_GateLeaf")
		local closed = leaf:GetAttribute("WE_ClosedCFrame")
		if leaf:IsA("BasePart") and typeof(sx) == "number" and typeof(closed) == "CFrame" then
			local target = if open then closed * CFrame.new(sx * (leaf.Size.X + 0.3), 0, 0) else closed
			local shift = target.Position - leaf.Position
			leaf.CFrame = target
			leaf.CanCollide = not open
			for _, ch in ipairs(leaf:GetChildren()) do
				if ch:IsA("BasePart") then
					ch.CFrame = ch.CFrame + shift
				end
			end
		end
	end
	gateFolder:SetAttribute("WE_GateOpen", open)
	refreshGateSign(gateFolder)
end

function StructureKitBuilder.SyncRearGates(plotId: number, upgrades: { [string]: any }?)
	local plotFolder = StructureKitBuilder.FindPlotFolder(plotId)
	local ground = plotFolder and plotFolder:FindFirstChild("LayoutGround")
	if not ground then
		return
	end
	for _, gateFolder in ipairs(ground:GetChildren()) do
		local gid = gateFolder:GetAttribute("GateId")
		if typeof(gid) == "string" then
			local lv = if upgrades then (tonumber(upgrades[gid]) or 0) else 0
			if gateFolder:GetAttribute("WE_GateMode") == "Proximity" then
				-- v70 sea gate: the structure only ARMS it. Waterways' loop opens an armed gate while a boat driven by
				-- the owner or an ally is near and closes it after; unarmed = closed (never a walk-in back door).
				local armed = lv >= 1
				gateFolder:SetAttribute("WE_GateArmed", armed)
				if armed then
					refreshGateSign(gateFolder)
				else
					StructureKitBuilder.SetGateOpen(gateFolder, false)
				end
			else
				StructureKitBuilder.SetGateOpen(gateFolder, lv >= 1)
			end
		end
	end
end

function StructureKitBuilder.ClearPlotExtras(plotId: number)
	StructureKitBuilder.SyncPerimeterWalls(plotId, 0)
	StructureKitBuilder.SyncRearGates(plotId, nil)
	StructureKitBuilder.SyncCornerTowers(plotId, 0)
	StructureKitBuilder.SyncBaseCeiling(plotId, 0)
	-- E) clear stale WE_OwnedLevel on unowned pads so next claimer does not see MAX with no kits
	local want = tonumber(plotId)
	local plotFolder = StructureKitBuilder.FindPlotFolder(plotId)
	-- v66: an ownerless plot must not keep a walk-in building standing
	if plotFolder then
		HollowBuildingBuilder.ClearUnder(plotFolder)
	end
	if plotFolder and want ~= nil then
		for _, desc in ipairs(plotFolder:GetDescendants()) do
			if desc:IsA("BasePart") and desc:GetAttribute("StructureId") ~= nil then
				if tonumber(desc:GetAttribute("PlotId") :: any) == want then
					desc:SetAttribute("WE_OwnedLevel", 0)
				end
			end
		end
	end
end

return StructureKitBuilder
