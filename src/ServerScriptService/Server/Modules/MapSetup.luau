--!strict
--[[
	WAR EMPIRE — MapSetup (shared world build)
	Builds Workspace.WarEmpireSetup: map, plots, structure kits, territories,
	spawns, tutorial markers, NPC placeholders, desert lighting, MapDressing + DesertFlora.
	Called from Bootstrap when WarEmpireSetup is missing (Play Solo / server start).
	Admin `resetmap` destroys WarEmpireSetup and re-runs.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local MapDressing = require(script.Parent:WaitForChild("MapDressing"))
local DesertFlora = require(script.Parent:WaitForChild("DesertFlora"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedConfigs = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Configs")
local DevConfig = require(SharedConfigs:WaitForChild("DevConfig"))
local EconomyConfig = require(SharedConfigs:WaitForChild("EconomyConfig"))
local MonetizationConfig = require(SharedConfigs:WaitForChild("MonetizationConfig"))

local TAG_BASE = "WE_BasePlot"
local TAG_SLOT = "WE_UpgradeSlot"
local TAG_TERRITORY = "WE_Territory"
local TAG_CAPTURE = "WE_CaptureZone"
local TAG_VEHICLE = "WE_VehicleSpawn"
local TAG_NAVAL = "WE_NavalSpawn"
local TAG_NPC = "WE_NPCSpawn"
local TAG_EVENT = "WE_EventSpawn"
local TAG_TUTORIAL = "WE_TutorialMarker"
local TAG_NPC_ENTITY = "WE_NPC"
local TAG_COLLECTOR = "WE_MoneyCollector"
local TAG_PREMIUM = "WE_PremiumPad"

local COL_GROUND = Color3.fromRGB(210, 185, 130) -- pale sandy-yellow desert floor
local COL_PAD = Color3.fromRGB(38, 44, 48)
local COL_PAD_EDGE = Color3.fromRGB(70, 190, 110)
local COL_VEHICLE = Color3.fromRGB(48, 62, 78)
local COL_NPC = Color3.fromRGB(88, 42, 42)
local COL_EVENT = Color3.fromRGB(78, 64, 36)

local STRUCTURES = {
	{ Id = "CommandCenter", Kit = "hq", Plinth = Color3.fromRGB(36, 48, 40), Body = Color3.fromRGB(55, 78, 58), Accent = Color3.fromRGB(230, 190, 60), Roof = Color3.fromRGB(40, 55, 45) },
	{ Id = "Barracks", Kit = "barracks", Plinth = Color3.fromRGB(150, 120, 80), Body = Color3.fromRGB(175, 145, 100), Accent = Color3.fromRGB(210, 170, 80), Roof = Color3.fromRGB(130, 100, 70) },
	{ Id = "VehicleDepot", Kit = "depot", Plinth = Color3.fromRGB(40, 48, 55), Body = Color3.fromRGB(58, 72, 88), Accent = Color3.fromRGB(90, 160, 220), Roof = Color3.fromRGB(45, 55, 65) },
	{ Id = "WeaponsFacility", Kit = "armory", Plinth = Color3.fromRGB(48, 40, 38), Body = Color3.fromRGB(88, 58, 50), Accent = Color3.fromRGB(200, 90, 70), Roof = Color3.fromRGB(55, 42, 40) },
	{ Id = "Helipad", Kit = "helipad", Plinth = Color3.fromRGB(45, 50, 48), Body = Color3.fromRGB(60, 70, 65), Accent = Color3.fromRGB(220, 200, 80), Roof = Color3.fromRGB(50, 55, 52) },
	{ Id = "Dock", Kit = "dock", Plinth = Color3.fromRGB(35, 48, 58), Body = Color3.fromRGB(50, 75, 95), Accent = Color3.fromRGB(70, 180, 220), Roof = Color3.fromRGB(40, 58, 70) },
	{ Id = "Airfield", Kit = "airfield", Plinth = Color3.fromRGB(50, 52, 48), Body = Color3.fromRGB(70, 72, 68), Accent = Color3.fromRGB(180, 190, 100), Roof = Color3.fromRGB(55, 58, 52) },
	{ Id = "DefensiveWalls", Kit = "wall", Plinth = Color3.fromRGB(48, 48, 45), Body = Color3.fromRGB(85, 85, 78), Accent = Color3.fromRGB(120, 130, 110), Roof = Color3.fromRGB(60, 60, 55) },
	{ Id = "Watchtowers", Kit = "tower", Plinth = Color3.fromRGB(44, 46, 40), Body = Color3.fromRGB(72, 78, 60), Accent = Color3.fromRGB(200, 160, 70), Roof = Color3.fromRGB(50, 52, 44) },
	{ Id = "Radar", Kit = "radar", Plinth = Color3.fromRGB(40, 42, 55), Body = Color3.fromRGB(55, 60, 90), Accent = Color3.fromRGB(100, 200, 255), Roof = Color3.fromRGB(45, 48, 70) },
	{ Id = "ResearchLab", Kit = "lab", Plinth = Color3.fromRGB(38, 45, 55), Body = Color3.fromRGB(50, 70, 95), Accent = Color3.fromRGB(80, 180, 220), Roof = Color3.fromRGB(42, 55, 72) },
	{ Id = "MissileDefense", Kit = "tower", Plinth = Color3.fromRGB(48, 42, 40), Body = Color3.fromRGB(75, 55, 50), Accent = Color3.fromRGB(220, 100, 60), Roof = Color3.fromRGB(55, 45, 42) },
	{ Id = "PowerStation", Kit = "power", Plinth = Color3.fromRGB(50, 48, 35), Body = Color3.fromRGB(90, 85, 50), Accent = Color3.fromRGB(255, 210, 70), Roof = Color3.fromRGB(60, 55, 40) },
	{ Id = "Warehouse", Kit = "warehouse", Plinth = Color3.fromRGB(140, 115, 75), Body = Color3.fromRGB(165, 135, 90), Accent = Color3.fromRGB(200, 160, 90), Roof = Color3.fromRGB(120, 95, 65) },
	{ Id = "SpecialForcesFacility", Kit = "special", Plinth = Color3.fromRGB(35, 38, 42), Body = Color3.fromRGB(45, 55, 65), Accent = Color3.fromRGB(160, 80, 200), Roof = Color3.fromRGB(30, 35, 40) },
}

local STARTER_COST = {
	CommandCenter = 1500, Barracks = 2500, VehicleDepot = 3000, WeaponsFacility = 2800,
	Helipad = 5000, Dock = 4500, Airfield = 8000, DefensiveWalls = 2000, Watchtowers = 2200,
	Radar = 4000, ResearchLab = 4500, MissileDefense = 6000, PowerStation = 3500,
	Warehouse = 3200, SpecialForcesFacility = 10000,
}

-- Map scale: ground ≥6000 continuous floor, plot ring ~800, pads ~200
-- Top of Ground sits ~Y=0.5 so plot pads (Y=0.5) sit flush.
local GROUND_SIZE = 7200
local GROUND_THICKNESS = 8
local GROUND_TOP_Y = 0.5
local SAFETY_FLOOR_SIZE = 10000
local SAFETY_FLOOR_Y = -28
local PLOT_PAD_SIZE = 200
local PLOT_RING = 800
local STRUCT_COLS = 4
local STRUCT_GAP = 42 -- studs between upgrade pad centers (was 30)
local STRUCT_ORIGIN = Vector3.new(-63, 1.6, -63) -- CommandCenter grid origin on each plot

local PLOT_POSITIONS = {
	Vector3.new(-PLOT_RING, 0.5, -PLOT_RING * 0.5), -- Plot1 SW
	Vector3.new(-PLOT_RING, 0.5, PLOT_RING * 0.5), -- Plot2 NW
	Vector3.new(0, 0.5, -PLOT_RING), -- Plot3 S
	Vector3.new(0, 0.5, PLOT_RING), -- Plot4 N
	Vector3.new(PLOT_RING, 0.5, -PLOT_RING * 0.5), -- Plot5 SE
	Vector3.new(PLOT_RING, 0.5, PLOT_RING * 0.5), -- Plot6 NE
}

local TERRITORIES = {
	{ Id = "CentralPlaza", DisplayName = "Central Plaza", Pos = Vector3.new(0, 1, 0), Color = Color3.fromRGB(180, 170, 50), Radius = 70 },
	{ Id = "NorthRidge", DisplayName = "North Ridge", Pos = Vector3.new(0, 1, -1300), Color = Color3.fromRGB(55, 120, 180), Radius = 60 },
	{ Id = "SouthDocks", DisplayName = "South Docks", Pos = Vector3.new(0, 1, 1300), Color = Color3.fromRGB(45, 110, 150), Radius = 60 },
	{ Id = "EastArmory", DisplayName = "East Armory", Pos = Vector3.new(1300, 1, 0), Color = Color3.fromRGB(170, 55, 55), Radius = 55 },
	{ Id = "WestDepot", DisplayName = "West Depot", Pos = Vector3.new(-1300, 1, 0), Color = Color3.fromRGB(55, 140, 70), Radius = 55 },
	{ Id = "OilFields", DisplayName = "Oil Fields", Pos = Vector3.new(950, 1, 950), Color = Color3.fromRGB(150, 110, 40), Radius = 65 },
	{ Id = "RadarHill", DisplayName = "Radar Hill", Pos = Vector3.new(-950, 1, -950), Color = Color3.fromRGB(130, 70, 170), Radius = 60 },
	-- Coastal oil decks (Y matches TerritoryConfig / OilRigConfig platform height)
	{ Id = "CoastalOilAlpha", DisplayName = "Coastal Oil Alpha", Pos = Vector3.new(1800, 28, -750), Color = Color3.fromRGB(190, 145, 45), Radius = 48, OilRig = true },
	{ Id = "CoastalOilBravo", DisplayName = "Coastal Oil Bravo", Pos = Vector3.new(-1800, 28, 750), Color = Color3.fromRGB(170, 125, 40), Radius = 48, OilRig = true },
	{ Id = "FortIronclad", DisplayName = "Fort Ironclad", Pos = Vector3.new(1450, 1, -1450), Color = Color3.fromRGB(140, 145, 155), Radius = 55, Fortress = true },
	{ Id = "FortSandhold", DisplayName = "Fort Sandhold", Pos = Vector3.new(-1450, 1, 1450), Color = Color3.fromRGB(190, 155, 90), Radius = 55, Fortress = true },
}

local function ensureFolder(name, parent)
	local existing = parent:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function part(props: { [string]: any })
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth

	-- Explicit safe assignment (avoid (p :: any)[k] = v strict/runtime quirks)
	if props.Name ~= nil then
		p.Name = props.Name
	end
	if props.Size ~= nil then
		p.Size = props.Size
	end
	if props.CFrame ~= nil then
		p.CFrame = props.CFrame
	elseif props.Position ~= nil then
		p.Position = props.Position
	end
	if props.Color ~= nil then
		p.Color = props.Color
	end
	if props.Material ~= nil then
		p.Material = props.Material
	end
	if props.Transparency ~= nil then
		p.Transparency = props.Transparency
	end
	if props.CanCollide ~= nil then
		p.CanCollide = props.CanCollide
	end
	if props.Anchored ~= nil then
		p.Anchored = props.Anchored
	end
	if props.Shape ~= nil then
		p.Shape = props.Shape
	end
	if props.Parent ~= nil then
		p.Parent = props.Parent
	end
	-- Deco/kits: shadows off by default (huge Studio GPU win). Opt-in via CastShadow=true.
	if props.CastShadow ~= nil then
		p.CastShadow = props.CastShadow
	else
		p.CastShadow = false
	end

	return p
end

local function kitPart(parentPlinth, role, size, localOffset, color, material, shape)
	local p = part({
		Name = role,
		Size = size,
		CFrame = parentPlinth.CFrame * CFrame.new(localOffset),
		Color = color,
		Material = material or Enum.Material.Metal,
		CanCollide = false,
		Transparency = 1, -- hidden until BaseService.applyKitVisuals (L0 faint / L1+ solid)
		Parent = parentPlinth,
	})
	if shape then
		p.Shape = shape
	end
	p.CanTouch = false -- never steal walk-buy Touched from plinth
	p.CanQuery = false
	p.CastShadow = false
	p:SetAttribute("WE_KitRole", role)
	p:SetAttribute("WE_BaseSize", size)
	p:SetAttribute("WE_LocalOffset", localOffset)
	p:SetAttribute("WE_Decor", true)
	return p
end

local function neonEdge(parentPart, color, thickness)
	local t = thickness or 0.35
	local s = parentPart.Size
	local edges = {
		{ Vector3.new(s.X + t, t, t), Vector3.new(0, s.Y * 0.5, s.Z * 0.5) },
		{ Vector3.new(s.X + t, t, t), Vector3.new(0, s.Y * 0.5, -s.Z * 0.5) },
		{ Vector3.new(t, t, s.Z + t), Vector3.new(s.X * 0.5, s.Y * 0.5, 0) },
		{ Vector3.new(t, t, s.Z + t), Vector3.new(-s.X * 0.5, s.Y * 0.5, 0) },
	}
	for i, e in ipairs(edges) do
		local edge = part({
			Name = "Edge" .. i,
			Size = e[1],
			CFrame = parentPart.CFrame * CFrame.new(e[2]),
			Color = color,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Transparency = 0.15,
			Parent = parentPart.Parent,
		})
		edge:SetAttribute("WE_Decor", true)
	end
end

local function priceBillboard(parent, title, costLine, accent)
	-- v50: compact mobile price cards (was oversized Title+Cost overflow)
	local bb = Instance.new("BillboardGui")
	bb.Name = "WE_PriceBillboard"
	bb.Size = UDim2.fromOffset(118, 40)
	bb.StudsOffset = Vector3.new(0, 4.5, 0)
	bb.AlwaysOnTop = false -- P0: never stack over ATM AlwaysOnTop
	bb.MaxDistance = 36 -- mobile: price cards near-only
	bb.Parent = parent

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(8, 10, 12)
	backdrop.BackgroundTransparency = 0.08
	backdrop.BorderSizePixel = 0
	backdrop.Parent = bb
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = backdrop
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Stroke"
	stroke.Color = accent
	stroke.Thickness = 1.5
	stroke.Transparency = 0.1
	stroke.Parent = backdrop

	local titleLab = Instance.new("TextLabel")
	titleLab.Name = "Title"
	titleLab.Size = UDim2.new(1, -8, 0, 16)
	titleLab.Position = UDim2.fromOffset(4, 2)
	titleLab.BackgroundTransparency = 1
	titleLab.Text = title
	titleLab.TextColor3 = Color3.fromRGB(245, 245, 248)
	titleLab.TextScaled = true
	titleLab.Font = Enum.Font.GothamBold
	titleLab.TextStrokeTransparency = 0.4
	titleLab.Parent = backdrop

	local costLab = Instance.new("TextLabel")
	costLab.Name = "Cost"
	costLab.Size = UDim2.new(1, -8, 0, 18)
	costLab.Position = UDim2.fromOffset(4, 18)
	costLab.BackgroundTransparency = 1
	costLab.Text = "Lv 0 → 1\n" .. costLine
	costLab.TextColor3 = Color3.fromRGB(255, 215, 110)
	costLab.TextScaled = true
	costLab.Font = Enum.Font.GothamBold
	costLab.TextStrokeTransparency = 0.35
	costLab.Parent = backdrop
	return bb
end

local function plainBillboard(parent, text, size, offsetY, textColor)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Label"
	bb.Size = UDim2.fromOffset(size.X, size.Y)
	bb.StudsOffset = Vector3.new(0, offsetY, 0)
	bb.AlwaysOnTop = false -- P0: only ATM may AlwaysOnTop when nearest
	bb.MaxDistance = 70 -- base/zone labels near-only (was 950)
	bb.Parent = parent

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(12, 14, 16)
	backdrop.BackgroundTransparency = 0.22
	backdrop.BorderSizePixel = 0
	backdrop.Parent = bb
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = backdrop
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(70, 90, 70)
	stroke.Thickness = 1
	stroke.Transparency = 0.3
	stroke.Parent = backdrop

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = textColor or Color3.fromRGB(235, 240, 235)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextStrokeTransparency = 0.6
	label.Parent = backdrop
	return bb
end

local function beacon(parent, pos, color, name)
	part({
		Name = name or "Beacon",
		Size = Vector3.new(0.55, 12, 0.55),
		Position = pos + Vector3.new(0, 6, 0),
		Color = Color3.fromRGB(40, 45, 42),
		Material = Enum.Material.Metal,
		CanCollide = false,
		Parent = parent,
	})
	part({
		Name = (name or "Beacon") .. "_Tip",
		Size = Vector3.new(1.6, 1.6, 1.6),
		Position = pos + Vector3.new(0, 13, 0),
		Color = color,
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Ball,
		CanCollide = false,
		Parent = parent,
	})
	part({
		Name = (name or "Beacon") .. "_Glow",
		Size = Vector3.new(3.2, 0.4, 3.2),
		Position = pos + Vector3.new(0, 0.3, 0),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.55,
		CanCollide = false,
		Parent = parent,
	})
end

local function buildStructureKit(plotFolder, plotId, pos, offset, def)
	local isCC = def.Id == "CommandCenter"
	local plinthSize = Vector3.new(8, 1.2, 8)
	local plinth = part({
		Name = def.Id,
		Size = plinthSize,
		Position = pos + offset,
		Color = def.Plinth,
		Transparency = 0.32,
		Material = Enum.Material.Concrete,
		CanCollide = true,
		Parent = plotFolder,
	})
	plinth.CanTouch = true -- walk-over buy (Touched + Heartbeat)
	plinth:SetAttribute("PlotId", plotId)
	plinth:SetAttribute("StructureId", def.Id)
	plinth:SetAttribute("BaseSize", plinthSize)
	CollectionService:AddTag(plinth, TAG_SLOT)

	local kit = def.Kit
	-- Visual kits v2: distinct silhouettes, neon accents, doors/windows (modest part count)
	if kit == "hq" then
		kitPart(plinth, "Body", Vector3.new(5.5, 3.4, 5.5), Vector3.new(0, 2.3, 0), def.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(6.4, 0.55, 6.4), Vector3.new(0, 4.3, 0), def.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Antenna", Vector3.new(0.35, 4.8, 0.35), Vector3.new(1.8, 6.8, 1.8), def.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Accent", Vector3.new(6.6, 0.22, 6.6), Vector3.new(0, 0.72, 0), def.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Detail", Vector3.new(1.1, 1.1, 1.1), Vector3.new(-2, 3.6, -2), def.Accent, Enum.Material.Neon, Enum.PartType.Ball)
		kitPart(plinth, "Door", Vector3.new(1.6, 2.2, 0.25), Vector3.new(0, 1.7, -2.85), Color3.fromRGB(30, 35, 32), Enum.Material.Metal, nil)
		kitPart(plinth, "Window", Vector3.new(1.4, 1.0, 0.2), Vector3.new(2.0, 2.6, -2.8), Color3.fromRGB(70, 120, 150), Enum.Material.Glass, nil)
	elseif kit == "barracks" then
		kitPart(plinth, "Body", Vector3.new(6.6, 2.6, 4.4), Vector3.new(0, 1.9, 0), def.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(7.1, 0.5, 5.0), Vector3.new(0, 3.35, 0), def.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(6.9, 0.18, 4.7), Vector3.new(0, 0.7, 0), def.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Door", Vector3.new(1.4, 2.0, 0.25), Vector3.new(0, 1.6, -2.3), Color3.fromRGB(35, 40, 32), Enum.Material.Metal, nil)
		kitPart(plinth, "Window", Vector3.new(1.2, 0.9, 0.2), Vector3.new(-2.2, 2.3, -2.25), Color3.fromRGB(70, 120, 140), Enum.Material.Glass, nil)
		kitPart(plinth, "Detail", Vector3.new(0.7, 1.8, 0.7), Vector3.new(-3.0, 2.3, 1.5), def.Accent, Enum.Material.Neon, nil)
	elseif kit == "depot" then
		kitPart(plinth, "Body", Vector3.new(6.9, 2.2, 5.6), Vector3.new(0, 1.7, 0), def.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(7.3, 0.4, 6.1), Vector3.new(0, 2.95, 0), def.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(3.2, 0.28, 5.9), Vector3.new(0, 0.72, 0), def.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Door", Vector3.new(2.8, 2.0, 0.3), Vector3.new(0, 1.6, -2.9), Color3.fromRGB(40, 50, 60), Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(1.0, 1.0, 1.0), Vector3.new(2.8, 2.4, 2.0), def.Accent, Enum.Material.Neon, Enum.PartType.Ball)
	elseif kit == "lab" then
		kitPart(plinth, "Body", Vector3.new(5.1, 3.2, 5.1), Vector3.new(0, 2.2, 0), def.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(5.5, 0.5, 5.5), Vector3.new(0, 4.0, 0), def.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Antenna", Vector3.new(0.4, 3.8, 0.4), Vector3.new(0, 6.1, 0), def.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Accent", Vector3.new(5.7, 0.2, 5.7), Vector3.new(0, 0.7, 0), def.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Window", Vector3.new(1.5, 1.2, 0.2), Vector3.new(0, 2.6, -2.6), Color3.fromRGB(80, 160, 200), Enum.Material.Glass, nil)
		kitPart(plinth, "Detail", Vector3.new(0.9, 0.9, 0.9), Vector3.new(2.0, 3.5, 2.0), def.Accent, Enum.Material.Neon, Enum.PartType.Ball)
	elseif kit == "tower" then
		kitPart(plinth, "Body", Vector3.new(2.9, 5.8, 2.9), Vector3.new(0, 3.5, 0), def.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(3.8, 0.5, 3.8), Vector3.new(0, 6.6, 0), def.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Antenna", Vector3.new(0.3, 3.5, 0.3), Vector3.new(0, 8.5, 0), def.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Accent", Vector3.new(3.3, 0.22, 3.3), Vector3.new(0, 0.7, 0), def.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Window", Vector3.new(1.0, 0.8, 0.2), Vector3.new(0, 4.5, -1.5), Color3.fromRGB(90, 140, 180), Enum.Material.Glass, nil)
		kitPart(plinth, "Detail", Vector3.new(0.7, 0.7, 0.7), Vector3.new(0, 7.0, 0), def.Accent, Enum.Material.Neon, Enum.PartType.Ball)
	elseif kit == "dock" then
		kitPart(plinth, "Body", Vector3.new(7.5, 0.55, 7.5), Vector3.new(0, 0.9, 0), def.Body, Enum.Material.Concrete, nil)
		kitPart(plinth, "Pier", Vector3.new(8.8, 0.4, 2.4), Vector3.new(0, 1.15, 3.3), def.Roof, Enum.Material.Wood, nil)
		kitPart(plinth, "Accent", Vector3.new(7.2, 0.14, 0.4), Vector3.new(0, 1.25, 0), def.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Detail", Vector3.new(1.2, 2.8, 0.4), Vector3.new(3.3, 2.1, 2.6), def.Accent, Enum.Material.Metal, nil)
		kitPart(plinth, "Door", Vector3.new(1.8, 0.3, 1.2), Vector3.new(0, 1.35, 4.2), Color3.fromRGB(40, 55, 70), Enum.Material.Metal, nil)
	elseif kit == "pad" then
		kitPart(plinth, "Body", Vector3.new(7.3, 0.45, 7.3), Vector3.new(0, 0.92, 0), def.Body, Enum.Material.Concrete, nil)
		kitPart(plinth, "Accent", Vector3.new(6.6, 0.14, 0.5), Vector3.new(0, 1.18, 0), def.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Detail", Vector3.new(0.5, 0.14, 6.6), Vector3.new(0, 1.18, 0), def.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Roof", Vector3.new(1.6, 0.3, 1.6), Vector3.new(0, 1.35, 0), def.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Window", Vector3.new(0.5, 0.5, 0.5), Vector3.new(2.8, 1.4, 2.8), def.Accent, Enum.Material.Neon, Enum.PartType.Ball)
	elseif kit == "wall" then
		kitPart(plinth, "Body", Vector3.new(7.5, 3.0, 1.5), Vector3.new(0, 2.1, 0), def.Body, Enum.Material.Concrete, nil)
		kitPart(plinth, "Accent", Vector3.new(7.7, 0.25, 1.7), Vector3.new(0, 3.7, 0), def.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Roof", Vector3.new(7.5, 0.4, 1.9), Vector3.new(0, 3.9, 0), def.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(0.8, 1.2, 0.8), Vector3.new(-3.2, 3.2, 0), def.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Detail", Vector3.new(0.8, 1.2, 0.8), Vector3.new(3.2, 3.2, 0), def.Accent, Enum.Material.Neon, nil)
	elseif kit == "power" then
		kitPart(plinth, "Body", Vector3.new(4.6, 3.6, 4.6), Vector3.new(0, 2.5, 0), def.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(2.3, 2.3, 2.3), Vector3.new(0, 4.7, 0), def.Accent, Enum.Material.Neon, Enum.PartType.Ball)
		kitPart(plinth, "Roof", Vector3.new(5.1, 0.4, 5.1), Vector3.new(0, 4.4, 0), def.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(0.6, 2.5, 0.6), Vector3.new(2.0, 2.8, 2.0), Color3.fromRGB(60, 55, 40), Enum.Material.Metal, nil)
	elseif kit == "warehouse" then
		kitPart(plinth, "Body", Vector3.new(7.1, 2.8, 5.6), Vector3.new(0, 2.0, 0), def.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(7.5, 0.5, 6.1), Vector3.new(0, 3.55, 0), def.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(7.3, 0.2, 5.9), Vector3.new(0, 0.7, 0), def.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Door", Vector3.new(2.6, 2.2, 0.3), Vector3.new(0, 1.7, -2.95), Color3.fromRGB(50, 45, 38), Enum.Material.Metal, nil)
	else
		kitPart(plinth, "Body", Vector3.new(5.3, 3.5, 5.3), Vector3.new(0, 2.4, 0), def.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(4.2, 1.2, 4.2), Vector3.new(0, 4.6, 0), def.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Antenna", Vector3.new(0.35, 4.2, 0.35), Vector3.new(0, 7.2, 0), def.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Accent", Vector3.new(5.9, 0.22, 5.9), Vector3.new(0, 0.7, 0), def.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Detail", Vector3.new(1.0, 1.0, 1.0), Vector3.new(2.0, 3.5, -2.0), def.Accent, Enum.Material.Neon, Enum.PartType.Ball)
	end

	local cost = STARTER_COST[def.Id] or 0
	-- Prefer readable DisplayName; client refreshSlotBillboard rewrites when attached
	local displayNames = {
		CommandCenter = "Command Center",
		Barracks = "Barracks",
		VehicleDepot = "Vehicle Depot",
		WeaponsFacility = "Weapons Facility",
		Helipad = "Helipad",
		Dock = "Naval Dock",
		Airfield = "Airfield",
		DefensiveWalls = "Defensive Walls",
		Watchtowers = "Watchtowers",
		Radar = "Radar Station",
		ResearchLab = "Research Lab",
		MissileDefense = "Missile Defense",
		PowerStation = "Power Station",
		Warehouse = "Warehouse",
		SpecialForcesFacility = "Special Forces",
	}
	local nice = displayNames[def.Id] or def.Id
	local title = if isCC then ("★ " .. nice) else nice
	local rates = EconomyConfig.PassiveIncome and EconomyConfig.PassiveIncome.PerLevelRates
	local rate = if typeof(rates) == "table" then (tonumber(rates[def.Id]) or 0) else 0
	local incomeBit = if rate > 0 then (" · +$" .. tostring(rate) .. "/tick") else ""
	priceBillboard(plinth, title, "Lv 0 → 1 / $" .. tostring(cost) .. incomeBit, def.Accent)
	-- Optional free Creator Store building visual (skipped when StudioSkipWorldDressing)
	pcall(function()
		local vas = require(script.Parent.Parent.Services.VisualAssetService)
		vas.TryAttachBuildingVisual(plinth, def.Id)
	end)
	return plinth
end



-- Desert camo infantry Part kit — vest / helmet / shemagh accents, clearer rifle
local function makeSoldierKit(parentFolder, name, cf, bodyColor, labelText, labelColor, health, npcType, npcId)
	-- Visual props for Training Yard / static kits. R15-ready catalog overlay via VisualAssetConfig;
	-- Part-kit military placeholder (R6-ish ~5 stud) when mesh IDs missing / StudioSkipWorldDressing.
	-- Live combat NPCs use CombatService.SpawnNPC (BankGuard etc.).
	local model = Instance.new("Model")
	model.Name = name
	if npcId then
		model:SetAttribute("NPCId", npcId)
	end
	if npcType then
		model:SetAttribute("NPCType", npcType)
	end
	local desertBase = Color3.fromRGB(145, 125, 85)
	local camo = desertBase:Lerp(bodyColor, 0.45)
	local camoDark = Color3.fromRGB(
		math.clamp(math.floor(camo.R * 255) - 28, 20, 255),
		math.clamp(math.floor(camo.G * 255) - 22, 20, 255),
		math.clamp(math.floor(camo.B * 255) - 18, 20, 255)
	)
	-- v34: role Part-dress differentiation when mesh IDs reuse / insert fails
	local helmCol = camoDark
	local vestCol = camoDark
	local accentCol = labelColor or Color3.fromRGB(200, 140, 60)
	local role = if typeof(npcType) == "string" then npcType else ""
	if role == "Worker" then
		helmCol = Color3.fromRGB(95, 85, 55) -- soft tan helmet
		vestCol = Color3.fromRGB(80, 95, 60)
		accentCol = Color3.fromRGB(160, 200, 90)
	elseif role == "Infantry" then
		helmCol = Color3.fromRGB(45, 70, 40) -- olive steel
		vestCol = Color3.fromRGB(55, 75, 45)
		accentCol = Color3.fromRGB(180, 220, 120)
	elseif role == "HeavyInfantry" or role == "Heavy" then
		helmCol = Color3.fromRGB(35, 38, 42) -- dark armor helm
		vestCol = Color3.fromRGB(40, 45, 50)
		accentCol = Color3.fromRGB(230, 160, 50)
	elseif role == "Guard" or role == "GateGuard" or role == "BankGuard" then
		helmCol = Color3.fromRGB(30, 40, 55) -- navy / NVG
		vestCol = Color3.fromRGB(40, 50, 65)
		accentCol = Color3.fromRGB(90, 140, 220)
	end
	-- R6 torso = 2×2×1; lift so feet sit on ground (cf is approx mid-body)
	local torso = part({
		Name = "HumanoidRootPart",
		Size = Vector3.new(2, 2, 1),
		Color = camo,
		Material = Enum.Material.Fabric,
		Anchored = true,
		CanCollide = true,
		CFrame = cf,
		Parent = model,
	})
	local head = part({
		Name = "Head",
		Size = Vector3.new(1.05, 1.05, 1.05),
		Color = Color3.fromRGB(110, 85, 62),
		Material = Enum.Material.SmoothPlastic,
		Anchored = true,
		CanCollide = false,
		CFrame = torso.CFrame * CFrame.new(0, 1.55, 0),
		Shape = Enum.PartType.Ball,
		Parent = model,
	})
	part({
		Name = "Helmet",
		Size = Vector3.new(1.2, 0.5, 1.2),
		Color = helmCol,
		Material = Enum.Material.Metal,
		Anchored = true,
		CanCollide = false,
		CFrame = head.CFrame * CFrame.new(0, 0.38, 0),
		Parent = model,
	})
	part({
		Name = "Shemagh",
		Size = Vector3.new(1.25, 0.45, 1.15),
		Color = Color3.fromRGB(200, 185, 150),
		Material = Enum.Material.Fabric,
		Anchored = true,
		CanCollide = false,
		CFrame = head.CFrame * CFrame.new(0, -0.32, 0.05),
		Parent = model,
	})
	part({
		Name = "Vest",
		Size = Vector3.new(2.1, 1.2, 1.15),
		Color = vestCol,
		Material = Enum.Material.Leather,
		Anchored = true,
		CanCollide = false,
		CFrame = torso.CFrame * CFrame.new(0, 0.15, 0),
		Parent = model,
	})
	part({
		Name = "VestPouch",
		Size = Vector3.new(1.5, 0.45, 0.3),
		Color = Color3.fromRGB(90, 80, 55),
		Material = Enum.Material.Fabric,
		Anchored = true,
		CanCollide = false,
		CFrame = torso.CFrame * CFrame.new(0, 0.05, -0.6),
		Parent = model,
	})
	-- R6 arms 1×2×1
	part({
		Name = "ArmL",
		Size = Vector3.new(1, 2, 1),
		Color = camo,
		Material = Enum.Material.Fabric,
		Anchored = true,
		CanCollide = false,
		CFrame = torso.CFrame * CFrame.new(-1.5, 0, 0),
		Parent = model,
	})
	part({
		Name = "ArmR",
		Size = Vector3.new(1, 2, 1),
		Color = camo,
		Material = Enum.Material.Fabric,
		Anchored = true,
		CanCollide = false,
		CFrame = torso.CFrame * CFrame.new(1.5, 0, 0),
		Parent = model,
	})
	-- R6 legs 1×2×1
	part({
		Name = "LegL",
		Size = Vector3.new(1, 2, 1),
		Color = camo,
		Material = Enum.Material.Fabric,
		Anchored = true,
		CanCollide = false,
		CFrame = torso.CFrame * CFrame.new(-0.5, -2, 0),
		Parent = model,
	})
	part({
		Name = "LegR",
		Size = Vector3.new(1, 2, 1),
		Color = camo,
		Material = Enum.Material.Fabric,
		Anchored = true,
		CanCollide = false,
		CFrame = torso.CFrame * CFrame.new(0.5, -2, 0),
		Parent = model,
	})
	part({
		Name = "BootL",
		Size = Vector3.new(1.05, 0.35, 1.15),
		Color = Color3.fromRGB(35, 32, 28),
		Material = Enum.Material.SmoothPlastic,
		Anchored = true,
		CanCollide = false,
		CFrame = torso.CFrame * CFrame.new(-0.5, -3.1, 0.1),
		Parent = model,
	})
	part({
		Name = "BootR",
		Size = Vector3.new(1.05, 0.35, 1.15),
		Color = Color3.fromRGB(35, 32, 28),
		Material = Enum.Material.SmoothPlastic,
		Anchored = true,
		CanCollide = false,
		CFrame = torso.CFrame * CFrame.new(0.5, -3.1, 0.1),
		Parent = model,
	})
	part({
		Name = "RifleStock",
		Size = Vector3.new(0.3, 0.4, 0.9),
		Color = Color3.fromRGB(55, 48, 38),
		Material = Enum.Material.Wood,
		Anchored = true,
		CanCollide = false,
		CFrame = torso.CFrame * CFrame.new(1.15, 0.15, 0.35),
		Parent = model,
	})
	part({
		Name = "Rifle",
		Size = Vector3.new(0.25, 0.25, 2.4),
		Color = Color3.fromRGB(32, 34, 36),
		Material = Enum.Material.Metal,
		Anchored = true,
		CanCollide = false,
		CFrame = torso.CFrame * CFrame.new(1.15, 0.2, -0.95),
		Parent = model,
	})
	part({
		Name = "RifleBarrel",
		Size = Vector3.new(0.14, 0.14, 0.9),
		Color = Color3.fromRGB(25, 25, 28),
		Material = Enum.Material.Metal,
		Anchored = true,
		CanCollide = false,
		CFrame = torso.CFrame * CFrame.new(1.15, 0.22, -2.25),
		Parent = model,
	})
	part({
		Name = "Accent",
		Size = Vector3.new(1.6, 0.1, 0.28),
		Color = accentCol,
		Material = Enum.Material.Metal,
		Anchored = true,
		CanCollide = false,
		CFrame = torso.CFrame * CFrame.new(0, 0.85, -0.5),
		Parent = model,
	})
	if role == "HeavyInfantry" or role == "Heavy" then
		part({
			Name = "Pack",
			Size = Vector3.new(1.4, 1.5, 0.7),
			Color = Color3.fromRGB(40, 42, 38),
			Material = Enum.Material.Metal,
			Anchored = true,
			CanCollide = false,
			CFrame = torso.CFrame * CFrame.new(0, 0.4, 0.85),
			Parent = model,
		})
	end
	local hum = Instance.new("Humanoid")
	hum.MaxHealth = health or 100
	hum.Health = health or 100
	-- Single nametag only via Billboard — kill default Humanoid nameplate
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.NameOcclusion = Enum.NameOcclusion.OccludeAll
	hum.Parent = model
	model.PrimaryPart = torso
	-- Optional free Soldier catalog visual (skipped when StudioSkipWorldDressing)
	pcall(function()
		local vas = require(script.Parent.Parent.Services.VisualAssetService)
		local kind = if typeof(npcType) == "string" and npcType ~= "" then npcType else "Soldier"
		vas.TryAttachCharacterVisual(model, kind)
	end)
	model.Parent = parentFolder
	CollectionService:AddTag(model, TAG_NPC_ENTITY)
	if labelText then
		-- One clean label on head (not also on torso)
		local bb = plainBillboard(head, labelText, Vector2.new(120, 24), 2.2, labelColor or Color3.fromRGB(255, 200, 140))
		bb.Name = "NPCLabel"
		bb.AlwaysOnTop = false
		bb.MaxDistance = 18
		bb.StudsOffset = Vector3.new(0, 2.4, 0)
	end
	return model
end


-- Continuous floor + safety catch + perimeter mountain ring (mobile-friendly part count)
local function groundCenterY(): number
	return GROUND_TOP_Y - GROUND_THICKNESS * 0.5
end

local function buildSafetyUnderfloor(mapFolder: Folder)
	part({
		Name = "SafetyCatch",
		Size = Vector3.new(SAFETY_FLOOR_SIZE, 4, SAFETY_FLOOR_SIZE),
		Position = Vector3.new(0, SAFETY_FLOOR_Y, 0),
		Color = Color3.fromRGB(18, 22, 18),
		Material = Enum.Material.Slate,
		Transparency = 0.92,
		CanCollide = true,
		Anchored = true,
		Parent = mapFolder,
	})
end

local function buildEdgeBerms(mapFolder: Folder)
	-- Soft inner berm just inside Ground edge (keeps stroll-off from feeling like cliff)
	local half = GROUND_SIZE * 0.5 - 40
	local bermH = 18
	local bermT = 28
	local bermY = GROUND_TOP_Y + bermH * 0.5
	local sides = {
		{ Name = "EdgeBermN", Size = Vector3.new(GROUND_SIZE - 80, bermH, bermT), Pos = Vector3.new(0, bermY, -half) },
		{ Name = "EdgeBermS", Size = Vector3.new(GROUND_SIZE - 80, bermH, bermT), Pos = Vector3.new(0, bermY, half) },
		{ Name = "EdgeBermE", Size = Vector3.new(bermT, bermH, GROUND_SIZE - 80), Pos = Vector3.new(half, bermY, 0) },
		{ Name = "EdgeBermW", Size = Vector3.new(bermT, bermH, GROUND_SIZE - 80), Pos = Vector3.new(-half, bermY, 0) },
	}
	for _, s in ipairs(sides) do
		part({
			Name = s.Name,
			Size = s.Size,
			Position = s.Pos,
			Color = Color3.fromRGB(185, 155, 105),
			Material = Enum.Material.Sand,
			CanCollide = true,
			Anchored = true,
			Parent = mapFolder,
		})
	end
end


local function buildInvisibleWalls(mapFolder: Folder)
	-- Tall invisible perimeter so players cannot walk off Ground into void/water
	local half = GROUND_SIZE * 0.5 - 8
	local wallH = 80
	local wallT = 12
	local wallY = GROUND_TOP_Y + wallH * 0.5
	local sides = {
		{ Name = "VoidWallN", Size = Vector3.new(GROUND_SIZE, wallH, wallT), Pos = Vector3.new(0, wallY, -half) },
		{ Name = "VoidWallS", Size = Vector3.new(GROUND_SIZE, wallH, wallT), Pos = Vector3.new(0, wallY, half) },
		{ Name = "VoidWallE", Size = Vector3.new(wallT, wallH, GROUND_SIZE), Pos = Vector3.new(half, wallY, 0) },
		{ Name = "VoidWallW", Size = Vector3.new(wallT, wallH, GROUND_SIZE), Pos = Vector3.new(-half, wallY, 0) },
	}
	for _, s in ipairs(sides) do
		part({
			Name = s.Name,
			Size = s.Size,
			Position = s.Pos,
			Color = Color3.fromRGB(40, 50, 40),
			Material = Enum.Material.SmoothPlastic,
			Transparency = 1,
			CanCollide = true,
			Anchored = true,
			Parent = mapFolder,
		})
	end
end

local function buildMountainRing(root: Folder)
	--[[
		Desert mesa / butte rim — terracotta / sienna / reddish-brown layered Part kits.
		Flat-topped sedimentary striations; varied heights; foothills + collide berm.
		Keeps continuous floor / CanCollide perimeter from void-fall fix (4021025).
	]]
	local folder = Instance.new("Folder")
	folder.Name = "MountainRing"
	folder.Parent = root

	local mesaColors = {
		Color3.fromRGB(168, 95, 58), -- terracotta
		Color3.fromRGB(145, 78, 48), -- burnt sienna
		Color3.fromRGB(185, 110, 70), -- warm sandstone
		Color3.fromRGB(130, 72, 48), -- deep clay
		Color3.fromRGB(175, 105, 65), -- mesa orange
		Color3.fromRGB(155, 88, 55), -- red rock
	}
	local strataLight = Color3.fromRGB(200, 145, 100)
	local strataDark = Color3.fromRGB(110, 62, 40)
	local sandFoothill = Color3.fromRGB(195, 160, 110)

	local half = GROUND_SIZE * 0.5
	local ringR = half + 90
	-- PERF: 12–16 segments (was 24). Studio laptops struggle with mesa*strata*cap parts.
	local configured = tonumber(DevConfig.MountainRingSegments) or 14
	local segCount = math.clamp(math.floor(configured), 12, 24)
	local segArc = (math.pi * 2) / segCount
	local segLen = ringR * segArc * 1.12

	for i = 1, segCount do
		local angle = (i - 0.5) * segArc
		local cx = math.cos(angle) * ringR
		local cz = math.sin(angle) * ringR
		local hSeed = ((i * 17 + 31) % 80) + 40
		local height = hSeed
		if i % 7 == 0 then
			height = math.min(125, height + 32)
		elseif i % 5 == 0 then
			height = math.max(42, height - 16)
		end
		-- Flat-topped mesa: slightly shorter + wider top silhouette
		local depth = 58 + (i % 5) * 9
		local yaw = -angle + math.pi * 0.5
		local col = mesaColors[((i - 1) % #mesaColors) + 1]
		local mat = Enum.Material.Sandstone
		if i % 3 == 0 then
			mat = Enum.Material.Rock
			col = col:Lerp(strataDark, 0.25)
		elseif i % 4 == 0 then
			mat = Enum.Material.Slate
			col = col:Lerp(Color3.fromRGB(140, 95, 70), 0.3)
		end
		local ridge = part({
			Name = "Mesa_" .. i,
			Size = Vector3.new(segLen, height, depth),
			CFrame = CFrame.new(cx, GROUND_TOP_Y + height * 0.5 - 2, cz) * CFrame.Angles(0, yaw, 0),
			Color = col,
			Material = mat,
			CanCollide = true,
			Anchored = true,
			Parent = folder,
		})
		ridge:SetAttribute("WE_Mountain", true)
		-- Sedimentary striation bands (visual only) — every 3rd segment (perf)
		if i % 3 == 0 then
			local bandH = math.clamp(height * 0.12, 4, 10)
			part({
				Name = "Strata_" .. i,
				Size = Vector3.new(segLen * 1.02, bandH, depth * 0.98),
				CFrame = CFrame.new(cx, GROUND_TOP_Y + height * 0.38, cz) * CFrame.Angles(0, yaw, 0),
				Color = if i % 4 == 0 then strataLight else strataDark,
				Material = Enum.Material.Sandstone,
				CanCollide = false,
				Anchored = true,
				Transparency = 0.08,
				Parent = folder,
			}):SetAttribute("WE_Mountain", true)
		end
		-- Flat mesa cap (butte top) — every 3rd segment (perf)
		if i % 3 == 0 then
			local tipH = 6 + (i % 5) * 2
			part({
				Name = "MesaCap_" .. i,
				Size = Vector3.new(segLen * 0.72, tipH, depth * 0.7),
				CFrame = CFrame.new(cx, GROUND_TOP_Y + height + tipH * 0.25 - 2, cz) * CFrame.Angles(0, yaw, 0),
				Color = col:Lerp(strataLight, 0.35),
				Material = Enum.Material.Sandstone,
				CanCollide = false,
				Anchored = true,
				Parent = folder,
			}):SetAttribute("WE_Mountain", true)
		end
		-- Inner foothill shelf (sand) — collide continuity from berm (sparser)
		if i % 4 == 0 then
			local footH = 12 + (i % 4) * 3
			local footR = half + 35
			local fx = math.cos(angle) * footR
			local fz = math.sin(angle) * footR
			part({
				Name = "Foothill_" .. i,
				Size = Vector3.new(segLen * 0.9, footH, 38),
				CFrame = CFrame.new(fx, GROUND_TOP_Y + footH * 0.5 - 1, fz) * CFrame.Angles(0, yaw, 0),
				Color = sandFoothill,
				Material = Enum.Material.Sand,
				CanCollide = true,
				Anchored = true,
				Parent = folder,
			}):SetAttribute("WE_Mountain", true)
		end
	end

	-- Mid-ground rocky outcrops just inside the ring (sandy floor props)
	for oi = 1, 4 do
		local ang = (oi / 12) * math.pi * 2 + 0.2
		local orad = half - 220 - (oi % 4) * 40
		local ox = math.cos(ang) * orad
		local oz = math.sin(ang) * orad
		local oh = 10 + (oi % 5) * 4
		part({
			Name = "Outcrop_" .. oi,
			Size = Vector3.new(28 + (oi % 3) * 8, oh, 22 + (oi % 2) * 6),
			Position = Vector3.new(ox, GROUND_TOP_Y + oh * 0.5 - 1, oz),
			Color = mesaColors[((oi - 1) % #mesaColors) + 1],
			Material = Enum.Material.Sandstone,
			CanCollide = true,
			Anchored = true,
			Parent = folder,
		}):SetAttribute("WE_Mountain", true)
	end

	-- Corner massifs (extra bulk — flat-topped buttes)
	-- Cardinal buttes only (was 8 incl. diagonals) — Studio collide/GPU win
	local massifs = {
		{ 0, -1, "N" },
		{ 0, 1, "S" },
		{ 1, 0, "E" },
		{ -1, 0, "W" },
	}
	for mi, m in ipairs(massifs) do
		local mx = m[1] * (half + 120)
		local mz = m[2] * (half + 120)
		local mh = 75 + (mi % 4) * 14
		part({
			Name = "Butte_" .. m[3],
			Size = Vector3.new(150, mh, 150),
			Position = Vector3.new(mx, GROUND_TOP_Y + mh * 0.5 - 4, mz),
			Color = mesaColors[((mi - 1) % #mesaColors) + 1],
			Material = Enum.Material.Sandstone,
			CanCollide = true,
			Anchored = true,
			Parent = folder,
		}):SetAttribute("WE_Mountain", true)
		-- Flat caps omitted for perf (mesa segments already have caps)
	end

	print("[WAR EMPIRE] MapSetup: MountainRing mesas=" .. tostring(segCount) .. " + buttes/outcrops (desert terracotta)")
end

local function buildVisualFillPatches(mapFolder: Folder)
	-- Low-cost ground patches between plot ring and mid-map so dead space doesn't look empty
	local patches = {
		Vector3.new(400, GROUND_TOP_Y + 0.08, 200),
		Vector3.new(-350, GROUND_TOP_Y + 0.08, -250),
		Vector3.new(600, GROUND_TOP_Y + 0.08, -100),
		Vector3.new(-400, GROUND_TOP_Y + 0.08, -550),
	}
	for i, pos in ipairs(patches) do
		local w = 80 + (i % 4) * 25
		local d = 55 + (i % 3) * 20
		part({
			Name = "FillPatch_" .. i,
			Size = Vector3.new(w, 0.2, d),
			Position = pos,
			Color = if i % 2 == 0 then Color3.fromRGB(220, 195, 140) else Color3.fromRGB(195, 165, 115),
			Material = if i % 2 == 0 then Enum.Material.Sand else Enum.Material.Sandstone,
			CanCollide = false,
			Anchored = true,
			Transparency = 0.05,
			Parent = mapFolder,
		})
	end
end

local function buildOilDeckRamp(parent: Folder, territoryId: string, deckPos: Vector3, towardCenter: Vector3)
	--[[
		Stepped collide stairs from elevated oil deck (~Y=28) down to ground.
		towardCenter = horizontal direction from deck toward map center (inland).
	]]
	local dir = Vector3.new(towardCenter.X, 0, towardCenter.Z)
	if dir.Magnitude < 0.1 then
		dir = Vector3.new(if deckPos.X >= 0 then -1 else 1, 0, 0)
	end
	dir = dir.Unit
	local deckTopY = deckPos.Y
	local steps = 10
	local rise = (deckTopY - GROUND_TOP_Y) / steps
	local run = 9
	local stepW = 22
	local stepT = 7.5
	-- Start just outside the 48-stud deck toward inland
	local edge = Vector3.new(deckPos.X, 0, deckPos.Z) - dir * 26
	for s = 1, steps do
		local y = deckTopY - rise * s + 0.6
		local horiz = edge - dir * (run * s)
		local pos = Vector3.new(horiz.X, y, horiz.Z)
		part({
			Name = territoryId .. "_RampStep" .. s,
			Size = Vector3.new(stepW, 1.3, stepT),
			CFrame = CFrame.lookAt(pos, pos + dir),
			Color = Color3.fromRGB(75, 78, 82),
			Material = Enum.Material.Metal,
			CanCollide = true,
			Anchored = true,
			Parent = parent,
		})
	end
	local midHoriz = edge - dir * (run * 5)
	part({
		Name = territoryId .. "_RampShelf",
		Size = Vector3.new(28, 1.4, 14),
		Position = Vector3.new(midHoriz.X, deckTopY - rise * 5, midHoriz.Z),
		Color = Color3.fromRGB(70, 74, 78),
		Material = Enum.Material.Metal,
		CanCollide = true,
		Anchored = true,
		Parent = parent,
	})
	local approach = edge - dir * (run * steps + 10)
	part({
		Name = territoryId .. "_RampApproach",
		Size = Vector3.new(30, 1, 18),
		Position = Vector3.new(approach.X, GROUND_TOP_Y + 0.45, approach.Z),
		Color = Color3.fromRGB(55, 60, 55),
		Material = Enum.Material.Concrete,
		CanCollide = true,
		Anchored = true,
		Parent = parent,
	})
end


local MapSetup = {}

-- Exported for Bootstrap ground heal / verify
MapSetup.GROUND_SIZE = GROUND_SIZE
MapSetup.GROUND_THICKNESS = GROUND_THICKNESS
MapSetup.GROUND_TOP_Y = GROUND_TOP_Y
MapSetup.SAFETY_FLOOR_SIZE = SAFETY_FLOOR_SIZE
MapSetup.SAFETY_FLOOR_Y = SAFETY_FLOOR_Y

local function buildPadSupportShelves(setup: Folder)
	--[[
		Collide shelves under elevated upgrade pads / decks so players never
		treat CanCollide=false kit deco as floor. Fills air gap pad→Ground.
	]]
	local map = setup:FindFirstChild("Map")
	if not map then
		return
	end
	local folder = map:FindFirstChild("PadSupports")
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "PadSupports"
	folder.Parent = map

	local CollectionService = game:GetService("CollectionService")
	local TAG = TAG_SLOT
	local count = 0
	for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(setup) then
			local topY = inst.Position.Y + inst.Size.Y * 0.5
			local gap = topY - GROUND_TOP_Y
			if gap > 2.5 then
				local shelfH = math.clamp(gap - 0.5, 1, 40)
				local shelfY = GROUND_TOP_Y + shelfH * 0.5
				part({
					Name = "PadShelf_" .. tostring(count),
					Size = Vector3.new(math.max(inst.Size.X + 4, 12), shelfH, math.max(inst.Size.Z + 4, 12)),
					Position = Vector3.new(inst.Position.X, shelfY, inst.Position.Z),
					Color = Color3.fromRGB(90, 85, 70),
					Material = Enum.Material.Concrete,
					CanCollide = true,
					Anchored = true,
					Parent = folder,
				})
				count += 1
			end
		end
	end
	-- Also sweep StructureId parts under Bases (tag may lag)
	local bases = setup:FindFirstChild("Bases")
	if bases then
		for _, desc in ipairs(bases:GetDescendants()) do
			if desc:IsA("BasePart") then
				local sid = desc:GetAttribute("StructureId")
				if typeof(sid) == "string" then
					local topY = desc.Position.Y + desc.Size.Y * 0.5
					local gap = topY - GROUND_TOP_Y
					if gap > 2.5 then
						-- Skip if already covered by a nearby shelf
						local covered = false
						for _, child in ipairs(folder:GetChildren()) do
							if child:IsA("BasePart") then
								local dx = child.Position.X - desc.Position.X
								local dz = child.Position.Z - desc.Position.Z
								if dx * dx + dz * dz < 25 then
									covered = true
									break
								end
							end
						end
						if not covered then
							local shelfH = math.clamp(gap - 0.5, 1, 40)
							local shelfY = GROUND_TOP_Y + shelfH * 0.5
							part({
								Name = "PadShelf_" .. tostring(count),
								Size = Vector3.new(math.max(desc.Size.X + 4, 12), shelfH, math.max(desc.Size.Z + 4, 12)),
								Position = Vector3.new(desc.Position.X, shelfY, desc.Position.Z),
								Color = Color3.fromRGB(90, 85, 70),
								Material = Enum.Material.Concrete,
								CanCollide = true,
								Anchored = true,
								Parent = folder,
							})
							count += 1
						end
					end
				end
			end
		end
	end
	if count > 0 then
		print("[WAR EMPIRE] MapSetup: PadSupports shelves=" .. tostring(count) .. " (collide fillers under elevated pads)")
	end
end

function MapSetup.EnsureGroundHealthy(setup: Instance): boolean
	--[[
		Soft-heal existing WarEmpireSetup Ground / SafetyCatch.
		Returns true if healthy (or repaired in place), false if caller should rebuild.
	]]
	local map = setup:FindFirstChild("Map")
	if not map then
		return false
	end
	local ground = map:FindFirstChild("Ground")
	if not (ground and ground:IsA("BasePart")) then
		return false
	end
	local repaired = false
	-- Always force full-size collide Ground every Play (bulletproof void floor)
	if ground.Size.X < GROUND_SIZE - 1 or ground.Size.Z < GROUND_SIZE - 1 or ground.Size.Y < GROUND_THICKNESS - 0.5
		or ground.CanCollide ~= true
	then
		ground.Size = Vector3.new(GROUND_SIZE, GROUND_THICKNESS, GROUND_SIZE)
		ground.Position = Vector3.new(0, groundCenterY(), 0)
		repaired = true
	end
	-- Even when size OK, re-assert collide / anchor every start
	ground.Size = Vector3.new(GROUND_SIZE, GROUND_THICKNESS, GROUND_SIZE)
	ground.Position = Vector3.new(0, groundCenterY(), 0)
	if ground.CanCollide ~= true then
		ground.CanCollide = true
		repaired = true
	end
	if ground.Anchored ~= true then
		ground.Anchored = true
		repaired = true
	end
	ground.Color = COL_GROUND
	ground.Material = Enum.Material.Sand

	local catch = map:FindFirstChild("SafetyCatch")
	if not (catch and catch:IsA("BasePart")) then
		buildSafetyUnderfloor(map :: Folder)
		repaired = true
	else
		catch.Size = Vector3.new(SAFETY_FLOOR_SIZE, 4, SAFETY_FLOOR_SIZE)
		catch.Position = Vector3.new(0, SAFETY_FLOOR_Y, 0)
		catch.CanCollide = true
		catch.Anchored = true
		catch.Transparency = 0.92
	end

	if not setup:FindFirstChild("MountainRing") then
		buildMountainRing(setup :: Folder)
		repaired = true
	end
	if not map:FindFirstChild("EdgeBermN") then
		buildEdgeBerms(map :: Folder)
		repaired = true
	end
	if not map:FindFirstChild("VoidWallN") then
		buildInvisibleWalls(map :: Folder)
		repaired = true
	end

	buildPadSupportShelves(setup :: Folder)

	print(string.format(
		"[WAR EMPIRE] Ground heal: ok size=%.0fx%.0fx%.0f CanCollide=%s repaired=%s",
		ground.Size.X,
		ground.Size.Y,
		ground.Size.Z,
		tostring(ground.CanCollide),
		tostring(repaired)
	))
	return true
end




function MapSetup.ForceRebuildGround(setup: Instance): boolean
	--[[
		Hard rebuild: destroy Map.Ground + SafetyCatch and recreate them.
		Use every Play when soft-heal is not enough (stale holes / void gaps).
		Does NOT rebuild the whole WarEmpireSetup — only the collide floor layers.
	]]
	local map = setup:FindFirstChild("Map")
	if not map then
		return false
	end
	local oldGround = map:FindFirstChild("Ground")
	if oldGround then
		oldGround:Destroy()
	end
	local oldCatch = map:FindFirstChild("SafetyCatch")
	if oldCatch then
		oldCatch:Destroy()
	end

	local ground = part({
		Name = "Ground",
		Size = Vector3.new(GROUND_SIZE, GROUND_THICKNESS, GROUND_SIZE),
		Position = Vector3.new(0, groundCenterY(), 0),
		Color = COL_GROUND,
		Material = Enum.Material.Sand,
		CanCollide = true,
		Anchored = true,
		Parent = map,
	})
	ground.CanCollide = true
	ground.Anchored = true
	buildSafetyUnderfloor(map :: Folder)
	-- Refresh berms + invisible void walls every force rebuild
	for _, name in ipairs({ "EdgeBermN", "EdgeBermS", "EdgeBermE", "EdgeBermW", "VoidWallN", "VoidWallS", "VoidWallE", "VoidWallW" }) do
		local oldP = map:FindFirstChild(name)
		if oldP then
			oldP:Destroy()
		end
	end
	buildEdgeBerms(map :: Folder)
	buildInvisibleWalls(map :: Folder)
	if not setup:FindFirstChild("MountainRing") then
		buildMountainRing(setup :: Folder)
	end
	buildPadSupportShelves(setup :: Folder)

	print(string.format(
		"[WAR EMPIRE] Ground FORCE-REBUILT: size=%.0fx%.0fx%.0f CanCollide=%s Anchored=%s",
		ground.Size.X,
		ground.Size.Y,
		ground.Size.Z,
		tostring(ground.CanCollide),
		tostring(ground.Anchored)
	))
	return ground.CanCollide == true and ground.Size.X >= GROUND_SIZE - 1 and ground.Size.Y >= GROUND_THICKNESS - 0.5
end



local function paintPlotFloorChevrons(plotFolder: Folder, plotOrigin: Vector3)
	--[[
		Permanent white >>>> chevrons on plot floor guiding spawn → CommandCenter → next pads.
		Visual-only (CanCollide false). Competitor pattern from QUALITY_GAP.
	]]
	local folder = Instance.new("Folder")
	folder.Name = "PlotFloorChevrons"
	folder.Parent = plotFolder

	local function chevronAt(worldPos: Vector3, yawRad: number, idx: number)
		-- Wedge-ish arrow: wide rear + tip (two parts read as >>>)
		local cf = CFrame.new(worldPos) * CFrame.Angles(0, yawRad, 0)
		part({
			Name = "ChevronBody" .. idx,
			Size = Vector3.new(3.2, 0.12, 2.2),
			CFrame = cf,
			Color = Color3.fromRGB(245, 245, 250),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Transparency = 0.15,
			Parent = folder,
		})
		part({
			Name = "ChevronTip" .. idx,
			Size = Vector3.new(1.6, 0.14, 1.6),
			CFrame = cf * CFrame.new(0, 0.02, -1.4) * CFrame.Angles(0, math.rad(45), 0),
			Color = Color3.fromRGB(255, 255, 255),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Transparency = 0.05,
			Parent = folder,
		})
	end

	local function paintPath(from: Vector3, to: Vector3, count: number, startIdx: number): number
		local delta = to - from
		local flat = Vector3.new(delta.X, 0, delta.Z)
		if flat.Magnitude < 4 then
			return startIdx
		end
		-- Face along path (Roblox look = -Z); atan2(x,z) matches CFrame.Angles Y
		local yaw = math.atan2(flat.X, flat.Z)
		local idx = startIdx
		for i = 1, count do
			local alpha = i / (count + 1)
			local pos = from:Lerp(to, alpha) + Vector3.new(0, 0.55, 0)
			chevronAt(pos, yaw, idx)
			idx += 1
		end
		return idx
	end

	-- Path nodes: PlayerSpawn → CC → Barracks → Depot → Weapons → ATM/premium cluster
	local spawnPos = plotOrigin + Vector3.new(0, 0.5, 55)
	local nodes = {
		spawnPos,
	}
	for i, def in ipairs(STRUCTURES) do
		if i > 5 then
			break
		end
		local col = (i - 1) % STRUCT_COLS
		local row = math.floor((i - 1) / STRUCT_COLS)
		local offset = STRUCT_ORIGIN + Vector3.new(col * STRUCT_GAP, 0, row * STRUCT_GAP)
		table.insert(nodes, plotOrigin + offset + Vector3.new(0, 0.5, 0))
	end
	-- Guide toward MoneyCollector + premium Robux pads (unpaid ATM cluster)
	local atmCluster = plotOrigin + Vector3.new(28, 0.5, 8)
	table.insert(nodes, atmCluster)

	local idx = 1
	for i = 1, #nodes - 1 do
		local steps = if i == 1 then 5 elseif i == #nodes - 1 then 4 else 3
		idx = paintPath(nodes[i], nodes[i + 1], steps, idx)
	end
end



local function dressPlotPadSandbags(plotFolder: Folder, plotOrigin: Vector3)
	--[[
		v33: cheap MapDressing-style sandbag berms + extra chevrons near early BUY pads.
		Visual-only; does not tag WE_UpgradeSlot.
	]]
	local folder = Instance.new("Folder")
	folder.Name = "PlotPadDressing"
	folder.Parent = plotFolder

	local function sandbag(at: Vector3, yaw: number, idx: number)
		local cf = CFrame.new(at) * CFrame.Angles(0, yaw, 0)
		part({
			Name = "PadSandbag" .. idx,
			Size = Vector3.new(4.2, 1.1, 1.4),
			CFrame = cf,
			Color = Color3.fromRGB(130, 115, 80),
			Material = Enum.Material.Sand,
			CanCollide = false,
			Transparency = 0,
			Parent = folder,
		})
		part({
			Name = "PadSandbagTop" .. idx,
			Size = Vector3.new(3.4, 0.7, 1.1),
			CFrame = cf * CFrame.new(0, 0.85, 0),
			Color = Color3.fromRGB(145, 125, 88),
			Material = Enum.Material.Sand,
			CanCollide = false,
			Transparency = 0,
			Parent = folder,
		})
	end

	local function miniChevron(at: Vector3, yaw: number, idx: number)
		local cf = CFrame.new(at) * CFrame.Angles(0, yaw, 0)
		part({
			Name = "PadChevron" .. idx,
			Size = Vector3.new(2.4, 0.1, 1.6),
			CFrame = cf,
			Color = Color3.fromRGB(245, 245, 250),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Transparency = 0.2,
			Parent = folder,
		})
	end

	local idx = 1
	-- First 6 structure pads get flanking sandbags + approach chevron
	for i, def in ipairs(STRUCTURES) do
		if i > 6 then
			break
		end
		local col = (i - 1) % STRUCT_COLS
		local row = math.floor((i - 1) / STRUCT_COLS)
		local offset = STRUCT_ORIGIN + Vector3.new(col * STRUCT_GAP, 0, row * STRUCT_GAP)
		local padPos = plotOrigin + offset
		sandbag(padPos + Vector3.new(-7, 0.7, 4), math.rad(15), idx)
		idx += 1
		sandbag(padPos + Vector3.new(7, 0.7, 4), math.rad(-15), idx)
		idx += 1
		miniChevron(padPos + Vector3.new(0, 0.55, 9), math.rad(180), idx)
		idx += 1
	end
	-- ATM approach berm
	local atm = plotOrigin + Vector3.new(28, 0.7, 8)
	sandbag(atm + Vector3.new(-6, 0, 6), 0, idx)
	idx += 1
	sandbag(atm + Vector3.new(6, 0, 6), 0, idx)
end



local function premiumOfferIdLive(kind: string, key: string): boolean
	-- Hide pads until Creator Dashboard Id exists (GoldenPumpjack Id=0 → no pad)
	if kind == "GamePass" then
		local def = MonetizationConfig.GamePasses[key]
		return def ~= nil and typeof(def.Id) == "number" and def.Id ~= 0
	elseif kind == "DevProduct" then
		local def = MonetizationConfig.DevProducts[key]
		return def ~= nil and typeof(def.Id) == "number" and def.Id ~= 0
	end
	return false
end

local function buildPremiumPads(folder: Folder, plotId: number, atmPos: Vector3)
	-- Competitor ATM-cluster: red AutoCollect / 2x Cash, yellow Speed; GoldenPump only if Id≠0
	local offers = {
		{ Key = "AutoCollect", Kind = "GamePass", Label = "AUTO COLLECT", Color = Color3.fromRGB(220, 50, 50), Offset = Vector3.new(-10, 0.55, 14) },
		{ Key = "VIP", Kind = "GamePass", Label = "VIP", Color = Color3.fromRGB(180, 60, 220), Offset = Vector3.new(-18, 0.55, 8) },
		{ Key = "DoubleCash", Kind = "GamePass", Label = "2x CASH", Color = Color3.fromRGB(255, 70, 40), Offset = Vector3.new(0, 0.55, 16) },
		{ Key = "SpeedBoost", Kind = "DevProduct", Label = "SPEED BOOST", Color = Color3.fromRGB(255, 210, 40), Offset = Vector3.new(10, 0.55, 14) },
		{ Key = "GoldenPumpjack", Kind = "DevProduct", Label = "GOLDEN PUMP", Color = Color3.fromRGB(255, 180, 40), Offset = Vector3.new(0, 0.55, 22) },
	}
	for _, offer in ipairs(offers) do
		if not premiumOfferIdLive(offer.Kind, offer.Key) then
			continue
		end
		local pad = part({
			Name = "PremiumPad_" .. offer.Key,
			Size = Vector3.new(7, 0.45, 7),
			Position = atmPos + offer.Offset,
			Color = offer.Color,
			Material = Enum.Material.Neon,
			CanCollide = true,
			Parent = folder,
		})
		pad:SetAttribute("PlotId", plotId)
		pad:SetAttribute("OfferKey", offer.Key)
		pad:SetAttribute("OfferKind", offer.Kind)
		CollectionService:AddTag(pad, TAG_PREMIUM)
		local glow = Instance.new("PointLight")
		glow.Color = offer.Color
		glow.Brightness = 1.4
		glow.Range = 14
		glow.Parent = pad
		local bb = plainBillboard(pad, offer.Label .. "  ·  R$", Vector2.new(160, 32), 3.2, offer.Color)
		if bb then
			bb.Name = "WE_PremiumBillboard"
			bb.AlwaysOnTop = false
			bb.MaxDistance = 36
		end
	end
end

local function buildMoneyCollector(plotFolder: Folder, plotId: number, pos: Vector3)
	-- ATM-like Part kit: matte grey body + green digit screen (MoneyCollectorService billboard refreshes $)
	local folder = Instance.new("Folder")
	folder.Name = "MoneyCollector"
	folder.Parent = plotFolder
	local body = part({
		Name = "CollectorBody",
		Size = Vector3.new(6, 8, 4),
		Position = pos + Vector3.new(28, 4.5, 8),
		Color = Color3.fromRGB(70, 78, 72),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = true,
		Parent = folder,
	})
	body:SetAttribute("PlotId", plotId)
	body:SetAttribute("WE_LimeLandmark", true)
	CollectionService:AddTag(body, TAG_COLLECTOR)
	part({
		Name = "CollectorBase",
		Size = Vector3.new(7.5, 0.6, 5.5),
		Position = pos + Vector3.new(28, 0.8, 8),
		Color = Color3.fromRGB(70, 74, 78),
		Material = Enum.Material.Concrete,
		CanCollide = true,
		Parent = folder,
	})
	local screen = part({
		Name = "CollectorScreen",
		Size = Vector3.new(4.2, 2.8, 0.35),
		Position = pos + Vector3.new(28, 5.2, 8 - 2.15),
		Color = Color3.fromRGB(40, 160, 70),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = folder,
	})
	-- Green digit SurfaceGui (live $ filled by MoneyCollectorService billboard on body too)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "WE_ATMScreen"
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(240, 160)
	sg.LightInfluence = 0
	sg.Parent = screen
	local digits = Instance.new("TextLabel")
	digits.Name = "Digits"
	digits.Size = UDim2.fromScale(1, 1)
	digits.BackgroundColor3 = Color3.fromRGB(8, 40, 18)
	digits.BackgroundTransparency = 0.15
	digits.Font = Enum.Font.Code
	digits.TextScaled = true
	digits.TextColor3 = Color3.fromRGB(70, 255, 120)
	digits.Text = "$0"
	digits.Parent = sg
	local light = Instance.new("PointLight")
	light.Name = "ATMGlow"
	light.Color = Color3.fromRGB(120, 255, 90)
	light.Brightness = 1.15
	light.Range = 20
	light.Parent = body
	do
		local bb = plainBillboard(body, "COLLECT · Touch ATM", Vector2.new(200, 36), 6.5, Color3.fromRGB(90, 240, 130))
		if bb then
			bb.Name = "WE_CollectBillboard"
			bb.AlwaysOnTop = true -- P0: ATM primary when nearest
			bb.MaxDistance = 28
		end
	end
	-- Lime Collect circle on ground (touch radius visual)
	local collectCircle = part({
		Name = "CollectCircle",
		Size = Vector3.new(14, 0.25, 14),
		Position = pos + Vector3.new(28, 0.55, 8),
		Color = Color3.fromRGB(90, 255, 110),
		Material = Enum.Material.Neon,
		Transparency = 0.55,
		CanCollide = false,
		Shape = Enum.PartType.Cylinder,
		Parent = folder,
	})
	-- Cylinder default axis is X — rotate to lie flat on ground
	collectCircle.CFrame = CFrame.new(pos + Vector3.new(28, 0.55, 8)) * CFrame.Angles(0, 0, math.rad(90))
	collectCircle:SetAttribute("PlotId", plotId)
	local ring = part({
		Name = "CollectRing",
		Size = Vector3.new(15.5, 0.2, 15.5),
		Color = Color3.fromRGB(60, 220, 90),
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
		Shape = Enum.PartType.Cylinder,
		Parent = folder,
	})
	ring.CFrame = CFrame.new(pos + Vector3.new(28, 0.45, 8)) * CFrame.Angles(0, 0, math.rad(90))

	-- Optional ATM catalog mesh dress (Part kit remains authoritative)
	task.defer(function()
		pcall(function()
			local vas = require(script.Parent.Parent.Services.VisualAssetService)
			if vas and vas.TryAttachCollectorVisual then
				vas.TryAttachCollectorVisual(body)
			end
		end)
	end)
	-- ATM-cluster premium Robux pads (AutoCollect / 2x / Speed / GoldenPump)
	buildPremiumPads(folder, plotId, pos + Vector3.new(28, 0, 8))
end

function MapSetup.Run()
	-- Normal gravity so characters fall onto terrain (not float/void)
	Workspace.Gravity = 196.2

	-- Lighting / sky / atmosphere — bright midday desert (inspiration only)
	Lighting.Ambient = Color3.fromRGB(165, 145, 110)
	Lighting.OutdoorAmbient = Color3.fromRGB(185, 165, 130)
	Lighting.Brightness = 3.15
	Lighting.ClockTime = 12.5 -- intense midday sun
	Lighting.GeographicLatitude = 22
	Lighting.EnvironmentDiffuseScale = 0.55
	Lighting.EnvironmentSpecularScale = 0.42
	Lighting.FogColor = Color3.fromRGB(210, 195, 160)
	Lighting.FogStart = 1200
	Lighting.FogEnd = 5200
	pcall(function()
		Lighting.GlobalShadows = true
	end)

	local sky = Lighting:FindFirstChildOfClass("Sky")
	if not sky then
		sky = Instance.new("Sky")
		sky.Parent = Lighting
	end
	sky.Name = "WE_Sky"
	sky.CelestialBodiesShown = true
	sky.StarCount = 2500
	sky.SunAngularSize = 18 -- larger desert sun
	sky.MoonAngularSize = 9

	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atm then
		atm = Instance.new("Atmosphere")
		atm.Parent = Lighting
	end
	atm.Density = 0.14
	atm.Offset = 0.08
	atm.Color = Color3.fromRGB(200, 185, 150) -- warm haze near horizon
	atm.Decay = Color3.fromRGB(95, 130, 190) -- deep blue sky fade
	atm.Glare = 0.32
	atm.Haze = 1.15 -- low haze, high contrast

	-- Cancel prior day/night loop on resetmap; gentle cycle biased to bright desert day
	local dayMarker = Lighting:FindFirstChild("WE_DayNightMarker")
	if dayMarker then
		dayMarker:Destroy()
	end
	dayMarker = Instance.new("Folder")
	dayMarker.Name = "WE_DayNightMarker"
	dayMarker.Parent = Lighting
	task.spawn(function()
		local STEP = 0.03
		local WAIT = 1.5
		local dayAmb = Color3.fromRGB(165, 145, 110)
		local dayOut = Color3.fromRGB(185, 165, 130)
		local dayFog = Color3.fromRGB(210, 195, 160)
		local nightAmb = Color3.fromRGB(40, 45, 70)
		local nightOut = Color3.fromRGB(50, 55, 85)
		local nightFog = Color3.fromRGB(55, 60, 90)
		while dayMarker.Parent do
			local t = (Lighting.ClockTime + STEP) % 24
			Lighting.ClockTime = t
			local night = 0
			if t < 5 or t > 20 then
				night = 1
			elseif t < 7 then
				night = 1 - (t - 5) / 2
			elseif t > 18 then
				night = (t - 18) / 2
			end
			Lighting.Brightness = 3.2 - night * 2.1
			Lighting.Ambient = dayAmb:Lerp(nightAmb, night)
			Lighting.OutdoorAmbient = dayOut:Lerp(nightOut, night)
			Lighting.FogColor = dayFog:Lerp(nightFog, night)
			Lighting.FogStart = 1200 - night * 250
			Lighting.FogEnd = 5200 - night * 800
			atm.Density = 0.13 + night * 0.14
			atm.Haze = 1.1 + night * 1.0
			atm.Color = Color3.fromRGB(200, 185, 150):Lerp(Color3.fromRGB(70, 80, 120), night)
			atm.Decay = Color3.fromRGB(95, 130, 190):Lerp(Color3.fromRGB(40, 50, 90), night)
			atm.Glare = 0.32 - night * 0.2
			task.wait(WAIT)
		end
	end)

	local root = ensureFolder("WarEmpireSetup", Workspace)
	local map = ensureFolder("Map", root)
	-- Continuous collide floor: thick, large, explicit CanCollide — never reads as sky
	part({
		Name = "Ground",
		Size = Vector3.new(GROUND_SIZE, GROUND_THICKNESS, GROUND_SIZE),
		Position = Vector3.new(0, groundCenterY(), 0),
		Color = COL_GROUND,
		Material = Enum.Material.Sand,
		CanCollide = true,
		Anchored = true,
		Parent = map,
	})
	buildSafetyUnderfloor(map)
	buildEdgeBerms(map)
	buildInvisibleWalls(map)
	buildVisualFillPatches(map)
	buildMountainRing(root)
	-- Road grid scaled to plot ring (optional visual guide)
	for _, z in ipairs({ -PLOT_RING, 0, PLOT_RING }) do
		part({
			Name = "RoadZ" .. z,
			Size = Vector3.new(GROUND_SIZE, 0.15, 14),
			Position = Vector3.new(0, GROUND_TOP_Y + 0.05, z),
			Color = Color3.fromRGB(50, 52, 48),
			Material = Enum.Material.Asphalt,
			CanCollide = false,
			Parent = map,
		})
	end
	for _, x in ipairs({ -PLOT_RING, 0, PLOT_RING }) do
		part({
			Name = "RoadX" .. x,
			Size = Vector3.new(14, 0.15, GROUND_SIZE),
			Position = Vector3.new(x, GROUND_TOP_Y + 0.05, 0),
			Color = Color3.fromRGB(50, 52, 48),
			Material = Enum.Material.Asphalt,
			CanCollide = false,
			Parent = map,
		})
	end
	-- Asphalt Decal texture on road strips (MapDressing.AsphaltDecal)
	task.defer(function()
		pcall(function()
			local vas = require(script.Parent.Parent.Services.VisualAssetService)
			if not (vas and vas.ApplyAsphaltDecal) then
				return
			end
			for _, ch in ipairs(map:GetChildren()) do
				if ch:IsA("BasePart") and (string.sub(ch.Name, 1, 5) == "RoadZ" or string.sub(ch.Name, 1, 5) == "RoadX") then
					vas.ApplyAsphaltDecal(ch)
				end
			end
		end)
	end)

		-- Yellow centerline dashes (asphalt polish — competitor desert roads)
	for _, z in ipairs({ -PLOT_RING, 0, PLOT_RING }) do
		for i = -8, 8 do
			if i ~= 0 then
				part({
					Name = "RoadDashZ" .. z .. "_" .. i,
					Size = Vector3.new(8, 0.12, 1.2),
					Position = Vector3.new(i * 90, GROUND_TOP_Y + 0.12, z),
					Color = Color3.fromRGB(240, 210, 60),
					Material = Enum.Material.Neon,
					CanCollide = false,
					Transparency = 0.25,
					Parent = map,
				})
			end
		end
	end
	for _, x in ipairs({ -PLOT_RING, PLOT_RING }) do
		for i = -8, 8 do
			if i ~= 0 then
				part({
					Name = "RoadDashX" .. x .. "_" .. i,
					Size = Vector3.new(1.2, 0.12, 8),
					Position = Vector3.new(x, GROUND_TOP_Y + 0.12, i * 90),
					Color = Color3.fromRGB(240, 210, 60),
					Material = Enum.Material.Neon,
					CanCollide = false,
					Transparency = 0.25,
					Parent = map,
				})
			end
		end
	end

	local bases = ensureFolder("Bases", root)
	for plotId, pos in ipairs(PLOT_POSITIONS) do
		local plotFolder = Instance.new("Folder")
		plotFolder.Name = "Plot" .. plotId
		plotFolder.Parent = bases

		local pad = part({
			Name = "PlotPad",
			Size = Vector3.new(PLOT_PAD_SIZE, 1, PLOT_PAD_SIZE),
			Position = pos,
			Color = COL_PAD,
			Material = Enum.Material.Concrete,
			Parent = plotFolder,
		})
		pad:SetAttribute("PlotId", plotId)
		CollectionService:AddTag(pad, TAG_BASE)
		neonEdge(pad, COL_PAD_EDGE, 0.55)

		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "PlayerSpawn"
		spawn.Size = Vector3.new(10, 1, 10)
		spawn.Position = pos + Vector3.new(0, 2, 55)
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.BrickColor = BrickColor.new("Dark green")
		spawn.Material = Enum.Material.Neon
		spawn.Parent = plotFolder

		plainBillboard(pad, "BASE " .. plotId .. "  ·  Walk pads to BUY  ·  E / B menu", Vector2.new(280, 44), 16, Color3.fromRGB(200, 230, 200))
		beacon(plotFolder, pos + Vector3.new(0, 0, -62), COL_PAD_EDGE, "PlotBeacon")

		for i, def in ipairs(STRUCTURES) do
			local col = (i - 1) % STRUCT_COLS
			local row = math.floor((i - 1) / STRUCT_COLS)
			local offset = STRUCT_ORIGIN + Vector3.new(col * STRUCT_GAP, 0, row * STRUCT_GAP)
			buildStructureKit(plotFolder, plotId, pos, offset, def)
		end

		paintPlotFloorChevrons(plotFolder, pos)
		dressPlotPadSandbags(plotFolder, pos)

		-- Training Yard targets (soldiers "train" → server cash; visual only)
		local yardFolder = Instance.new("Folder")
		yardFolder.Name = "TrainingYard"
		yardFolder.Parent = plotFolder
		for ti = 1, 3 do
			local tpos = pos + Vector3.new(-50 + ti * 18, 3.5, 48)
			local target = part({
				Name = "TrainingTarget" .. ti,
				Size = Vector3.new(4, 6, 0.6),
				Position = tpos,
				Color = Color3.fromRGB(200, 60, 60),
				Material = Enum.Material.Metal,
				CanCollide = true,
				Parent = yardFolder,
			})
			target:SetAttribute("PlotId", plotId)
			target:SetAttribute("WE_TrainingTarget", true)
			part({
				Name = "TargetStand" .. ti,
				Size = Vector3.new(1, 4, 1),
				Position = tpos + Vector3.new(0, -5, 0),
				Color = Color3.fromRGB(70, 70, 70),
				Material = Enum.Material.Metal,
				CanCollide = true,
				Parent = yardFolder,
			})
			part({
				Name = "TargetBullseye" .. ti,
				Size = Vector3.new(1.6, 1.6, 0.35),
				Position = tpos + Vector3.new(0, 0.5, -0.2),
				Color = Color3.fromRGB(240, 220, 60),
				Material = Enum.Material.Neon,
				CanCollide = false,
				Parent = yardFolder,
			})
		end
		-- Training workers (visual only — income is SoldierService tick)
		for wi = 1, 2 do
			local wpos = pos + Vector3.new(-40 + wi * 20, 2.6, 42)
			-- P0: dress as Worker→Infantry mesh (force catalog even in StudioSkipWorldDressing)
			local worker = makeSoldierKit(
				yardFolder,
				"TrainingWorker" .. wi,
				CFrame.new(wpos) * CFrame.Angles(0, math.rad(180), 0),
				Color3.fromRGB(70, 85, 55),
				"TRAINING",
				Color3.fromRGB(140, 150, 130), -- muted
				50,
				"Worker",
				nil
			)
			if worker then
				local head = worker:FindFirstChild("Head")
				if head then
					local bb = head:FindFirstChild("NPCLabel") or head:FindFirstChildWhichIsA("BillboardGui")
					if bb and bb:IsA("BillboardGui") then
						bb.Name = "WE_WorkerTag"
						bb.AlwaysOnTop = false
						bb.MaxDistance = 18
						bb.StudsOffset = Vector3.new(0, 2.4, 0)
						bb.Size = UDim2.fromOffset(90, 18)
					end
				end
			end
		end
		-- Target ring + base plate polish
		part({
			Name = "YardPad",
			Size = Vector3.new(55, 0.6, 18),
			Position = pos + Vector3.new(-14, 0.4, 48),
			Color = Color3.fromRGB(48, 52, 42),
			Material = Enum.Material.Concrete,
			CanCollide = true,
			Parent = yardFolder,
		})
		do
			local yp = yardFolder:FindFirstChild("YardPad")
			if yp and yp:IsA("BasePart") then
				local ebb = Instance.new("BillboardGui")
				ebb.Name = "WE_TrainingEarnBillboard"
				ebb.Size = UDim2.fromOffset(140, 28)
				ebb.StudsOffset = Vector3.new(0, 3.2, 0)
				ebb.AlwaysOnTop = false
				ebb.MaxDistance = 22
				ebb.Parent = yp
				local el = Instance.new("TextLabel")
				el.Size = UDim2.fromScale(1, 1)
				el.BackgroundTransparency = 0.35
				el.BackgroundColor3 = Color3.fromRGB(20, 28, 18)
				el.BorderSizePixel = 0
				el.Font = Enum.Font.GothamBold
				el.TextSize = 14
				el.TextColor3 = Color3.fromRGB(160, 220, 120)
				el.Text = "+$/tick"
				el.Parent = ebb
			end
		end
		-- Design Bot quality wire: 2–3 SquadStall kits (Tent + crates + sandbags + Infantry)
		do
			local stallFolder = Instance.new("Folder")
			stallFolder.Name = "SquadStalls"
			stallFolder.Parent = yardFolder
			local stallOffsets = {
				Vector3.new(-36, 0, 36),
				Vector3.new(-18, 0, 36),
				Vector3.new(0, 0, 36),
			}
			for si, soff in ipairs(stallOffsets) do
				local sOrigin = pos + soff
				local stall = Instance.new("Folder")
				stall.Name = "SquadStall" .. si
				stall.Parent = stallFolder
				-- Floor plate
				part({
					Name = "StallFloor",
					Size = Vector3.new(12, 0.4, 10),
					Position = sOrigin + Vector3.new(0, 0.35, 0),
					Color = Color3.fromRGB(70, 68, 52),
					Material = Enum.Material.WoodPlanks,
					CanCollide = true,
					Parent = stall,
				})
				-- Tent host (catalog Tent via TryAttachPropVisual)
				local tentHost = part({
					Name = "TentHost",
					Size = Vector3.new(8, 4, 6),
					Position = sOrigin + Vector3.new(0, 2.4, -1),
					Color = Color3.fromRGB(90, 100, 70),
					Material = Enum.Material.Fabric,
					CanCollide = false,
					Transparency = 0.35,
					Parent = stall,
				})
				-- Crate stack hosts
				local crateA = part({
					Name = "CrateHostA",
					Size = Vector3.new(2.2, 2.0, 2.2),
					Position = sOrigin + Vector3.new(4.5, 1.2, 2),
					Color = Color3.fromRGB(95, 80, 55),
					Material = Enum.Material.Wood,
					CanCollide = true,
					Parent = stall,
				})
				local crateB = part({
					Name = "CrateHostB",
					Size = Vector3.new(2.0, 1.8, 2.0),
					Position = sOrigin + Vector3.new(4.5, 3.0, 2),
					Color = Color3.fromRGB(85, 70, 48),
					Material = Enum.Material.Wood,
					CanCollide = true,
					Parent = stall,
				})
				local milCrate = part({
					Name = "MilCrateHost",
					Size = Vector3.new(2.4, 1.6, 1.8),
					Position = sOrigin + Vector3.new(-4.2, 1.0, 2.2),
					Color = Color3.fromRGB(55, 70, 50),
					Material = Enum.Material.Metal,
					CanCollide = true,
					Parent = stall,
				})
				-- Sandbags
				local sandHost = part({
					Name = "SandbagHost",
					Size = Vector3.new(6, 1.1, 1.3),
					Position = sOrigin + Vector3.new(0, 0.75, 4.2),
					Color = Color3.fromRGB(130, 115, 80),
					Material = Enum.Material.Sand,
					CanCollide = true,
					Parent = stall,
				})
				-- Lantern host
				local lanternHost = part({
					Name = "LanternHost",
					Size = Vector3.new(0.6, 1.2, 0.6),
					Position = sOrigin + Vector3.new(-3.5, 2.2, -2.5),
					Color = Color3.fromRGB(180, 140, 60),
					Material = Enum.Material.Metal,
					CanCollide = false,
					Parent = stall,
				})
				local lanternLight = Instance.new("PointLight")
				lanternLight.Color = Color3.fromRGB(255, 200, 120)
				lanternLight.Brightness = 0.8
				lanternLight.Range = 14
				lanternLight.Parent = lanternHost
				-- v34: stall roles use distinct VisualAssetConfig Character IDs + Part dress
				local stallRoles = {
					{ Kind = "Infantry", Label = "INFANTRY", Body = Color3.fromRGB(70, 85, 55), Accent = Color3.fromRGB(180, 220, 120) },
					{ Kind = "HeavyInfantry", Label = "HEAVY", Body = Color3.fromRGB(50, 55, 48), Accent = Color3.fromRGB(230, 160, 50) },
					{ Kind = "Guard", Label = "GUARD", Body = Color3.fromRGB(45, 55, 70), Accent = Color3.fromRGB(90, 140, 220) },
				}
				local roleDef = stallRoles[((si - 1) % #stallRoles) + 1]
				local soldierCf = CFrame.new(sOrigin + Vector3.new(-1.5, 2.6, 1.5)) * CFrame.Angles(0, math.rad(160 + si * 8), 0)
				makeSoldierKit(
					stall,
					"Stall" .. roleDef.Kind .. si,
					soldierCf,
					roleDef.Body,
					roleDef.Label,
					roleDef.Accent,
					80,
					roleDef.Kind,
					nil
				)
				-- Optional crouch: Humanoid Sit as lightweight proxy (full crouch AnimationId TBD)
				pcall(function()
					local m = stall:FindFirstChild("Stall" .. roleDef.Kind .. si)
					if m and m:IsA("Model") then
						local hum = m:FindFirstChildOfClass("Humanoid")
						if hum then
							hum.Sit = false
							hum.WalkSpeed = 0
							-- Note: T-pose/catalog pose OK — crouch AnimationId not wired this pass
							m:SetAttribute("WE_PoseNote", "TPose_CrouchAnimPending")
						end
					end
				end)
				-- Catalog prop dress (pcall — Part kits remain if InsertService fails)
				task.defer(function()
					pcall(function()
						local vas = require(script.Parent.Parent.Services.VisualAssetService)
						if not vas or not vas.TryAttachPropVisual then
							return
						end
						vas.TryAttachPropVisual(tentHost, "Tent")
						vas.TryAttachPropVisual(crateA, "Crate")
						vas.TryAttachPropVisual(crateB, "MilitaryCrate")
						vas.TryAttachPropVisual(milCrate, "MilitaryCrate")
						vas.TryAttachPropVisual(sandHost, "Sandbag")
						vas.TryAttachPropVisual(lanternHost, "Lantern")
					end)
				end)
			end
		end

		local yardAnchor = part({
			Name = "YardAnchor",
			Size = Vector3.new(1, 1, 1),
			Position = pos + Vector3.new(-14, 8, 48),
			Transparency = 1,
			CanCollide = false,
			Parent = yardFolder,
		})
		plainBillboard(
			yardAnchor,
			"TRAINING YARD · Workers earn cash",
			Vector2.new(280, 40),
			8,
			Color3.fromRGB(255, 200, 120)
		)
		local earnAnchor = part({
			Name = "YardEarnAnchor",
			Size = Vector3.new(1, 1, 1),
			Position = pos + Vector3.new(-14, 6, 42),
			Transparency = 1,
			CanCollide = false,
			Parent = yardFolder,
		})
		-- Light beams worker → target (visual income feedback)
		for wi = 1, 2 do
			local worker = yardFolder:FindFirstChild("TrainingWorker" .. wi)
			local target = yardFolder:FindFirstChild("TrainingTarget" .. wi)
			if worker and target and worker:IsA("Model") and target:IsA("BasePart") then
				local root = worker.PrimaryPart or worker:FindFirstChildWhichIsA("BasePart")
				if root and root:IsA("BasePart") then
					local a0 = Instance.new("Attachment")
					a0.Name = "WE_TrainBeam0"
					a0.Position = Vector3.new(0, 1.2, 0)
					a0.Parent = root
					local a1 = Instance.new("Attachment")
					a1.Name = "WE_TrainBeam1"
					a1.Parent = target
					local beam = Instance.new("Beam")
					beam.Name = "WE_TrainBeam"
					beam.Attachment0 = a0
					beam.Attachment1 = a1
					beam.Color = ColorSequence.new(Color3.fromRGB(255, 200, 80))
					beam.Width0 = 0.15
					beam.Width1 = 0.05
					beam.FaceCamera = true
					beam.LightEmission = 0.4
					beam.Transparency = NumberSequence.new(0.35)
					beam.Parent = root
				end
			end
		end
		-- Design densify: 8–12 realistic warzone props per plot (always-on Part kits; pcall catalog)
		do
			local okDress, errDress = pcall(function()
				local wz = Instance.new("Folder")
				wz.Name = "PlotWarzone"
				wz.Parent = plotFolder
				local count = 12
				for i = 1, count do
					local ang = (i / count) * math.pi * 2
					local rad = 58 + (i % 3) * 10
					local o = pos + Vector3.new(math.cos(ang) * rad, 0.6, math.sin(ang) * rad)
					if i % 3 == 0 then
						-- sandbag berm (Metal/Sand — no neon)
						part({
							Name = "WZ_Sandbag" .. i,
							Size = Vector3.new(6, 1.2, 1.4),
							Position = o,
							Color = Color3.fromRGB(130, 115, 80),
							Material = Enum.Material.Sand,
							CanCollide = true,
							Parent = wz,
						})
						part({
							Name = "WZ_SandbagTop" .. i,
							Size = Vector3.new(5.2, 0.9, 1.1),
							Position = o + Vector3.new(0, 1.0, 0),
							Color = Color3.fromRGB(120, 105, 75),
							Material = Enum.Material.Sand,
							CanCollide = true,
							Parent = wz,
						})
					elseif i % 3 == 1 then
						part({
							Name = "WZ_Crate" .. i,
							Size = Vector3.new(2.2, 2.0, 2.2),
							Position = o + Vector3.new(0, 1.0, 0),
							Color = Color3.fromRGB(95, 80, 55),
							Material = Enum.Material.Wood,
							CanCollide = true,
							Parent = wz,
						})
						part({
							Name = "WZ_Drum" .. i,
							Size = Vector3.new(1.4, 2.2, 1.4),
							Position = o + Vector3.new(3, 1.1, 1),
							Color = Color3.fromRGB(55, 70, 50),
							Material = Enum.Material.Metal,
							Shape = Enum.PartType.Cylinder,
							CanCollide = true,
							Parent = wz,
						})
					else
						part({
							Name = "WZ_Barrier" .. i,
							Size = Vector3.new(5, 1.4, 0.7),
							Position = o + Vector3.new(0, 0.7, 0),
							Color = Color3.fromRGB(110, 105, 90),
							Material = Enum.Material.Concrete,
							CanCollide = true,
							Parent = wz,
						})
					end
				end
				-- Optional catalog floodlight tower / flag (never clears pads on fail)
								pcall(function()
						local vas = require(script.Parent.Parent.Services.VisualAssetService)
						if not (vas and vas.TryAttachPropVisual) then
							return
						end
						-- WZ densify catalog: sandbags / crates / desert flora hosts
						for _, ch in ipairs(wz:GetChildren()) do
							if ch:IsA("BasePart") then
								if string.find(ch.Name, "Sandbag", 1, true) then
									vas.TryAttachPropVisual(ch, "Sandbag")
								elseif string.find(ch.Name, "Crate", 1, true) then
									vas.TryAttachPropVisual(ch, "Crate")
								elseif string.find(ch.Name, "Drum", 1, true) then
									vas.TryAttachPropVisual(ch, "OilBarrel")
								elseif string.find(ch.Name, "Barrier", 1, true) then
									vas.TryAttachPropVisual(ch, "ConcreteBarrier")
								end
							end
						end
						local host = wz:FindFirstChildWhichIsA("BasePart")
						if host then
							vas.TryAttachPropVisual(host, "FloodlightTower")
						end
					end)
			end)
			if not okDress then
				warn("[MapSetup] PlotWarzone densify failed (pads intact):", errDress)
			end
		end
		buildMoneyCollector(plotFolder, plotId, pos)
	end

	local territories = ensureFolder("Territories", root)
	for _, def in ipairs(TERRITORIES) do
		local diameter = (def.Radius or 30) * 2
		local marker = part({
			Name = def.Id,
			Size = Vector3.new(diameter, 1.5, diameter),
			Position = def.Pos,
			Color = def.Color,
			Transparency = 0.45,
			Material = Enum.Material.Neon,
			Parent = territories,
		})
		marker:SetAttribute("TerritoryId", def.Id)
		marker:SetAttribute("Radius", def.Radius or 30)
		marker:SetAttribute("OwnerType", "Neutral")
		marker:SetAttribute("OwnerUserId", 0)
		marker:SetAttribute("CaptureProgress", 0)
		CollectionService:AddTag(marker, TAG_TERRITORY)
		CollectionService:AddTag(marker, TAG_CAPTURE)

		do
			local zoneName = def.DisplayName or def.Id
			local bb = plainBillboard(marker, zoneName .. "  [NEUTRAL]  ·  Stand to capture", Vector2.new(280, 48), 12, Color3.new(1, 1, 1))
			if typeof(bb) == "Instance" and bb:IsA("BillboardGui") then
				bb.MaxDistance = 220 -- named capture zones readable from farther
				bb.StudsOffset = Vector3.new(0, 14, 0)
			end
		end

		part({
			Name = def.Id .. "_Ring",
			Size = Vector3.new(diameter + 8, 0.4, diameter + 8),
			Position = def.Pos + Vector3.new(0, 0.2, 0),
			Color = def.Color,
			Transparency = 0.65,
			CanCollide = false,
			Material = Enum.Material.SmoothPlastic,
			Parent = territories,
		}):SetAttribute("TerritoryId", def.Id)

		part({
			Name = def.Id .. "_FlagPole",
			Size = Vector3.new(0.4, 14, 0.4),
			Position = def.Pos + Vector3.new(0, 7, 0),
			Color = Color3.fromRGB(55, 55, 55),
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = territories,
		})
		local flag = part({
			Name = def.Id .. "_Flag",
			Size = Vector3.new(5.5, 3.2, 0.22),
			Position = def.Pos + Vector3.new(2.8, 12.2, 0),
			Color = def.Color,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Transparency = 0.08,
			Parent = territories,
		})
		flag:SetAttribute("TerritoryId", def.Id)
		flag:SetAttribute("WE_Flag", true)
		part({
			Name = def.Id .. "_FlagStripe",
			Size = Vector3.new(5.5, 0.45, 0.28),
			Position = def.Pos + Vector3.new(2.8, 12.2, 0),
			Color = Color3.fromRGB(245, 245, 245),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Transparency = 0.15,
			Parent = territories,
		})
		part({
			Name = def.Id .. "_Finial",
			Size = Vector3.new(0.7, 0.7, 0.7),
			Position = def.Pos + Vector3.new(0, 14.4, 0),
			Color = Color3.fromRGB(230, 190, 60),
			Material = Enum.Material.Neon,
			Shape = Enum.PartType.Ball,
			CanCollide = false,
			Parent = territories,
		})

		beacon(territories, def.Pos + Vector3.new(def.Radius * 0.6, 0, 0), def.Color, def.Id .. "_Beacon")

		-- Coastal oil platform deck + legs + harder NPC guards
		if def.OilRig then
			local deckY = def.Pos.Y
			local deck = part({
				Name = def.Id .. "_Deck",
				Size = Vector3.new(48, 2.5, 48),
				Position = Vector3.new(def.Pos.X, deckY - 1.2, def.Pos.Z),
				Color = Color3.fromRGB(90, 95, 100),
				Material = Enum.Material.Metal,
				Parent = territories,
			})
			deck:SetAttribute("TerritoryId", def.Id)
			-- Support legs
			local legOff = 18
			for _, ox in ipairs({ -legOff, legOff }) do
				for _, oz in ipairs({ -legOff, legOff }) do
					part({
						Name = def.Id .. "_Leg",
						Size = Vector3.new(3, deckY, 3),
						Position = Vector3.new(def.Pos.X + ox, deckY / 2, def.Pos.Z + oz),
						Color = Color3.fromRGB(60, 65, 70),
						Material = Enum.Material.Metal,
						Parent = territories,
					})
				end
			end
			-- Derrick + crane tip + neon rim (visual kits v2)
			part({
				Name = def.Id .. "_Derrick",
				Size = Vector3.new(4, 22, 4),
				Position = Vector3.new(def.Pos.X + 14, deckY + 11, def.Pos.Z + 14),
				Color = Color3.fromRGB(180, 140, 50),
				Material = Enum.Material.Metal,
				CanCollide = false,
				Parent = territories,
			})
			part({
				Name = def.Id .. "_CraneArm",
				Size = Vector3.new(14, 1.2, 1.2),
				Position = Vector3.new(def.Pos.X + 7, deckY + 20, def.Pos.Z + 14),
				Color = Color3.fromRGB(160, 120, 45),
				Material = Enum.Material.Metal,
				CanCollide = false,
				Parent = territories,
			})
			part({
				Name = def.Id .. "_HelipadMark",
				Size = Vector3.new(10, 0.3, 10),
				Position = Vector3.new(def.Pos.X - 12, deckY + 0.2, def.Pos.Z - 12),
				Color = Color3.fromRGB(40, 45, 50),
				Material = Enum.Material.Metal,
				CanCollide = false,
				Parent = territories,
			})
			part({
				Name = def.Id .. "_NeonRim",
				Size = Vector3.new(46, 0.35, 0.5),
				Position = Vector3.new(def.Pos.X, deckY + 0.3, def.Pos.Z + 23),
				Color = Color3.fromRGB(255, 180, 60),
				Material = Enum.Material.Neon,
				CanCollide = false,
				Parent = territories,
			})
			plainBillboard(deck, def.Id .. "  ·  OIL PLATFORM  ·  Hard guards", Vector2.new(300, 44), 14, Color3.fromRGB(255, 210, 120))
			-- Stairs from deck down to ground (prevent 28-stud death plunge)
			local inland = Vector3.new(-def.Pos.X, 0, -def.Pos.Z)
			buildOilDeckRamp(territories, def.Id, def.Pos, inland)
		end

		-- Fortress walls / keep (named forts with higher stipend)
		if def.Fortress then
			local wallH = 8
			local wallT = 2.2
			local span = (def.Radius or 48) * 1.35
			local wallDefs = {
				{ Vector3.new(span * 2, wallH, wallT), Vector3.new(0, wallH / 2, span) },
				{ Vector3.new(span * 2, wallH, wallT), Vector3.new(0, wallH / 2, -span) },
				{ Vector3.new(wallT, wallH, span * 2), Vector3.new(span, wallH / 2, 0) },
				{ Vector3.new(wallT, wallH, span * 2), Vector3.new(-span, wallH / 2, 0) },
			}
			for wi, wd in ipairs(wallDefs) do
				part({
					Name = def.Id .. "_Wall" .. wi,
					Size = wd[1],
					Position = def.Pos + wd[2],
					Color = Color3.fromRGB(95, 90, 75),
					Material = Enum.Material.Concrete,
					Parent = territories,
				})
			end
			local keep = part({
				Name = def.Id .. "_Keep",
				Size = Vector3.new(14, 16, 14),
				Position = def.Pos + Vector3.new(0, 8, 0),
				Color = def.Color,
				Material = Enum.Material.Brick,
				Parent = territories,
			})
			keep:SetAttribute("TerritoryId", def.Id)
			part({
				Name = def.Id .. "_KeepRoof",
				Size = Vector3.new(16, 1.5, 16),
				Position = def.Pos + Vector3.new(0, 16.5, 0),
				Color = Color3.fromRGB(70, 65, 55),
				Material = Enum.Material.Metal,
				CanCollide = false,
				Parent = territories,
			})
			-- Corner towers + gate neon
			for _, corner in ipairs({
				Vector3.new(span, 0, span),
				Vector3.new(span, 0, -span),
				Vector3.new(-span, 0, span),
				Vector3.new(-span, 0, -span),
			}) do
				part({
					Name = def.Id .. "_Tower",
					Size = Vector3.new(5, 12, 5),
					Position = def.Pos + corner + Vector3.new(0, 6, 0),
					Color = Color3.fromRGB(85, 80, 65),
					Material = Enum.Material.Brick,
					Parent = territories,
				})
			end
			part({
				Name = def.Id .. "_GateNeon",
				Size = Vector3.new(8, 0.4, 0.5),
				Position = def.Pos + Vector3.new(0, 1.5, span),
				Color = def.Color,
				Material = Enum.Material.Neon,
				CanCollide = false,
				Parent = territories,
			})
			plainBillboard(keep, def.Id .. "  ·  FORTRESS  ·  High stipend", Vector2.new(300, 44), 12, Color3.fromRGB(230, 210, 160))
		end
	end

	local function makeSpawnFolder(name, tag, count, center, color, ringRadius)
		local folder = ensureFolder(name, root)
		local ring = ringRadius or 200
		for i = 1, count do
			local angle = (i / count) * math.pi * 2
			local pos = center + Vector3.new(math.cos(angle) * ring, 1, math.sin(angle) * ring)
			local padSize = if tag == TAG_VEHICLE then 20 else 14
			local p = part({
				Name = name .. i,
				Size = Vector3.new(padSize, 1.2, padSize),
				Position = pos,
				Color = color,
				Material = Enum.Material.Concrete,
				Parent = folder,
			})
			CollectionService:AddTag(p, tag)
			neonEdge(p, color:Lerp(Color3.new(1, 1, 1), 0.35), 0.35)
			if tag == TAG_VEHICLE then
				part({
					Name = "HMark",
					Size = Vector3.new(6, 0.2, 1),
					Position = pos + Vector3.new(0, 0.7, 0),
					Color = Color3.fromRGB(200, 220, 255),
					Material = Enum.Material.Neon,
					CanCollide = false,
					Parent = folder,
				})
				part({
					Name = "HMark2",
					Size = Vector3.new(1, 0.2, 6),
					Position = pos + Vector3.new(0, 0.7, 0),
					Color = Color3.fromRGB(200, 220, 255),
					Material = Enum.Material.Neon,
					CanCollide = false,
					Parent = folder,
				})
				beacon(folder, pos, Color3.fromRGB(90, 160, 220), name .. i .. "_Beacon")
				plainBillboard(p, "GARAGE PAD · E / G", Vector2.new(170, 32), 5, Color3.fromRGB(200, 220, 255))
			elseif tag == TAG_NPC then
				plainBillboard(p, "NPC SPAWN", Vector2.new(140, 28), 4, Color3.fromRGB(255, 180, 180))
			else
				plainBillboard(p, "EVENT ZONE", Vector2.new(140, 28), 4, Color3.fromRGB(255, 220, 160))
			end
		end
	end

	-- Rings scaled for ~4800 ground: garage pads spread; more pads for large roster testing
	makeSpawnFolder("VehicleSpawns", TAG_VEHICLE, 10, Vector3.new(0, 0, 0), COL_VEHICLE, 650)
	makeSpawnFolder("NPCSpawns", TAG_NPC, 10, Vector3.new(480, 0, 480), COL_NPC, 550)
	makeSpawnFolder("EventSpawns", TAG_EVENT, 6, Vector3.new(-480, 0, -480), COL_EVENT, 500)

	-- Coastal water band (south of SouthDocks on ~4800 map) + naval spawn pads
	do
		local waterFolder = ensureFolder("CoastalWater", root)
		local water = part({
			Name = "WaterPlane",
			Size = Vector3.new(GROUND_SIZE * 0.9, 1, 720),
			Position = Vector3.new(0, 0.2, 1850),
			Color = Color3.fromRGB(45, 120, 145),
			Material = Enum.Material.Glass,
			Transparency = 0.32,
			CanCollide = false,
			Parent = waterFolder,
		})
		water.Name = "WaterPlane"
		-- Shallow collide strip so boats have something under them
		part({
			Name = "HarborShelf",
			Size = Vector3.new(GROUND_SIZE * 0.75, 1, 120),
			Position = Vector3.new(0, 0.4, 1520),
			Color = Color3.fromRGB(55, 95, 105),
			Material = Enum.Material.Sandstone,
			Transparency = 0.12,
			CanCollide = true,
			Parent = waterFolder,
		})
		local navalFolder = ensureFolder("NavalSpawns", root)
		local navalPositions = {
			Vector3.new(-420, 1.5, 1580),
			Vector3.new(-240, 1.5, 1620),
			Vector3.new(-80, 1.5, 1640),
			Vector3.new(80, 1.5, 1640),
			Vector3.new(240, 1.5, 1620),
			Vector3.new(420, 1.5, 1580),
			Vector3.new(0, 1.5, 1720),
			Vector3.new(-560, 1.5, 1680),
			Vector3.new(560, 1.5, 1680),
		}
		for i, npos in ipairs(navalPositions) do
			local np = part({
				Name = "NavalPad_" .. i,
				Size = Vector3.new(18, 1.2, 18),
				Position = npos,
				Color = Color3.fromRGB(40, 70, 95),
				Material = Enum.Material.Concrete,
				CanCollide = true,
				Parent = navalFolder,
			})
			CollectionService:AddTag(np, TAG_NAVAL)
			CollectionService:AddTag(np, TAG_VEHICLE) -- garage prompt also works
			beacon(navalFolder, npos, Color3.fromRGB(70, 180, 220), "NavalBeacon" .. i)
			plainBillboard(np, "NAVAL PAD · E / G", Vector2.new(170, 32), 5, Color3.fromRGB(160, 220, 255))
		end
	end

	local npcFolder = ensureFolder("NPCPlaceholders", root)
	for i, spawnPart in ipairs(CollectionService:GetTagged(TAG_NPC)) do
		if i > 4 then
			break
		end
		makeSoldierKit(
			npcFolder,
			"HostileInfantry_" .. i,
			spawnPart.CFrame + Vector3.new(0, 3.2, 0),
			Color3.fromRGB(140, 55, 55),
			"HOSTILE",
			Color3.fromRGB(255, 120, 100),
			80,
			"Infantry",
			"studio_npc_" .. i
		)
	end


	-- Oil rig guards (harder NPC placeholders — visual kits v2 infantry)
	for _, def in ipairs(TERRITORIES) do
		if def.OilRig then
			for gi = 1, 4 do
				local angle = (gi / 4) * math.pi * 2
				local gpos = def.Pos + Vector3.new(math.cos(angle) * 16, 2.6, math.sin(angle) * 16)
				makeSoldierKit(
					npcFolder,
					def.Id .. "_Guard_" .. gi,
					CFrame.new(gpos),
					Color3.fromRGB(110, 70, 35),
					"OIL GUARD",
					Color3.fromRGB(255, 180, 80),
					200,
					"OilRigGuard",
					def.Id .. "_guard_" .. gi
				)
			end
		end
	end

	-- Fort guards
	for _, def in ipairs(TERRITORIES) do
		if def.Fortress then
			for gi = 1, 4 do
				local angle = (gi / 4) * math.pi * 2
				local gpos = def.Pos + Vector3.new(math.cos(angle) * 22, 2.6, math.sin(angle) * 22)
				makeSoldierKit(
					npcFolder,
					def.Id .. "_Guard_" .. gi,
					CFrame.new(gpos),
					Color3.fromRGB(100, 95, 70),
					"FORT GUARD",
					Color3.fromRGB(220, 200, 140),
					170,
					"FortGuard",
					def.Id .. "_guard_" .. gi
				)
			end
		end
	end

	-- Empire Bank (raid stub) — high-value vault + BankGuard NPCs
	local bankFolder = ensureFolder("EmpireBank", root)
	local bankPos = Vector3.new(220, 1, -220) -- matches BankRaidConfig.Position -- matches BankRaidConfig.Position
	local bankPad = part({
		Name = "BankPlaza",
		Size = Vector3.new(36, 1.2, 36),
		Position = bankPos,
		Color = Color3.fromRGB(45, 50, 70),
		Material = Enum.Material.Concrete,
		Parent = bankFolder,
	})
	neonEdge(bankPad, Color3.fromRGB(90, 120, 200), 0.4)
	part({
		Name = "BankBuilding",
		Size = Vector3.new(22, 14, 18),
		Position = bankPos + Vector3.new(0, 7.5, -4),
		Color = Color3.fromRGB(55, 62, 85),
		Material = Enum.Material.Metal,
		Parent = bankFolder,
	})
	part({
		Name = "BankRoof",
		Size = Vector3.new(24, 1.2, 20),
		Position = bankPos + Vector3.new(0, 15, -4),
		Color = Color3.fromRGB(40, 45, 60),
		Material = Enum.Material.Metal,
		Parent = bankFolder,
	})
	-- Columns + entrance neon (visual kits v2)
	for _, ox in ipairs({ -8, -2.5, 2.5, 8 }) do
		part({
			Name = "BankColumn",
			Size = Vector3.new(1.4, 12, 1.4),
			Position = bankPos + Vector3.new(ox, 6.5, 5.5),
			Color = Color3.fromRGB(70, 78, 100),
			Material = Enum.Material.Marble,
			Parent = bankFolder,
		})
	end
	part({
		Name = "BankDoor",
		Size = Vector3.new(4.5, 6, 0.4),
		Position = bankPos + Vector3.new(0, 3.5, 5.2),
		Color = Color3.fromRGB(30, 35, 50),
		Material = Enum.Material.Metal,
		Parent = bankFolder,
	})
	part({
		Name = "BankSign",
		Size = Vector3.new(10, 1.2, 0.4),
		Position = bankPos + Vector3.new(0, 12.5, 5.2),
		Color = Color3.fromRGB(230, 190, 60),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = bankFolder,
	})
	local vault = part({
		Name = "VaultPad",
		Size = Vector3.new(10, 1.4, 10),
		Position = bankPos + Vector3.new(0, 1.2, 8),
		Color = Color3.fromRGB(200, 170, 60),
		Material = Enum.Material.Neon,
		Parent = bankFolder,
	})
	part({
		Name = "VaultRing",
		Size = Vector3.new(12, 0.35, 12),
		Position = bankPos + Vector3.new(0, 1.9, 8),
		Color = Color3.fromRGB(90, 140, 220),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Transparency = 0.35,
		Parent = bankFolder,
	})
	vault:SetAttribute("BankId", "EmpireBank")
	CollectionService:AddTag(vault, "WE_BankVault")
	plainBillboard(vault, "EMPIRE BANK · Stand to RAID cash", Vector2.new(280, 40), 8, Color3.fromRGB(255, 220, 120))
	beacon(bankFolder, bankPos + Vector3.new(14, 0, 14), Color3.fromRGB(90, 130, 220), "BankBeacon")
	-- Bank guards spawned live via CombatService.SpawnNPC("BankGuard", cf) in BankRaidService
	-- (static makeSoldierKit props removed — they were Anchored stick figures with double nametags)

	local tutorialFolder = ensureFolder("TutorialMarkers", root)
	local function tutorialMarker(name, pos, color, stepId)
		-- Hidden by default; TutorialController reveals only the active step (no billboard spam)
		local p = part({
			Name = name,
			Size = Vector3.new(7, 1.2, 7),
			Position = pos,
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = 1,
			CanCollide = false,
			Parent = tutorialFolder,
		})
		p:SetAttribute("TutorialStepId", stepId or name)
		CollectionService:AddTag(p, TAG_TUTORIAL)
		local bb = plainBillboard(p, "TUT · " .. name:gsub("Tutorial_", ""), Vector2.new(200, 34), 6, Color3.fromRGB(255, 245, 180))
		if typeof(bb) == "Instance" and bb:IsA("BillboardGui") then
			bb.Enabled = false
		end
		-- No beacon / ring clutter — waypoint beam is enough
		return p
	end

	local plot1 = PLOT_POSITIONS[1]
	-- Offsets track Plot1 spawn / structure grid (STRUCT_ORIGIN + gaps)
	local mClaim = tutorialMarker("Tutorial_ClaimBase", plot1 + Vector3.new(0, 2, 52), Color3.fromRGB(230, 200, 80), "ClaimBase")
	local mCC = tutorialMarker("Tutorial_CommandCenter", plot1 + STRUCT_ORIGIN + Vector3.new(0, 1.4, 0), Color3.fromRGB(80, 200, 120), "CommandCenter")
	local mRecruit = tutorialMarker("Tutorial_Recruit", plot1 + Vector3.new(-14, 3, 42), Color3.fromRGB(180, 220, 100), "RecruitSoldiers")
	tutorialMarker("Tutorial_Income", plot1 + Vector3.new(28, 3, 8), Color3.fromRGB(80, 200, 160), "Income")
	-- Click dropper sits near ATM (ManualDropper CollectorOffset ≈ -5.5, 0, 4 from collector body)
	tutorialMarker("Tutorial_Dropper", plot1 + Vector3.new(28 - 5.5, 2.5, 8 + 4), Color3.fromRGB(70, 220, 100), "ClickDropper")
	-- Pads first / beams first 3 beats: dress arrow meshes on early markers
	task.defer(function()
		pcall(function()
			local vas = require(script.Parent.Parent.Services.VisualAssetService)
			if vas and vas.TryAttachTutorialArrow then
				for _, m in ipairs({ mClaim, mCC, mRecruit }) do
					if m then
						vas.TryAttachTutorialArrow(m)
					end
				end
			end
		end)
	end)
	tutorialMarker("Tutorial_Barracks", plot1 + STRUCT_ORIGIN + Vector3.new(STRUCT_GAP, 1.4, 0), Color3.fromRGB(100, 180, 220), "Barracks")
	local jeepPos = Vector3.new(200, 2, 0)
	local vSpawns = CollectionService:GetTagged(TAG_VEHICLE)
	if #vSpawns > 0 and vSpawns[1]:IsA("BasePart") then
		jeepPos = vSpawns[1].Position + Vector3.new(0, 2, 0)
	end
	tutorialMarker("Tutorial_Jeep", jeepPos, Color3.fromRGB(120, 140, 200), "Jeep")
	tutorialMarker("Tutorial_Outpost", Vector3.new(0, 3, 0), Color3.fromRGB(200, 120, 80), "Outpost")

	-- Neon Accent guide beams: collector → CommandCenter → VehicleDepot (Plot1 landmark path)
	do
		local okNeon, errNeon = pcall(function()
			local neon = Color3.fromRGB(80, 255, 160)
			local collectorPos = plot1 + Vector3.new(28, 5, 8)
			local ccPos = plot1 + STRUCT_ORIGIN + Vector3.new(0, 4, 0)
			local depotIdx = 3 -- STRUCTURES[3] = VehicleDepot
			local depotCol = (depotIdx - 1) % STRUCT_COLS
			local depotRow = math.floor((depotIdx - 1) / STRUCT_COLS)
			local depotPos = plot1 + STRUCT_ORIGIN + Vector3.new(depotCol * STRUCT_GAP, 4, depotRow * STRUCT_GAP)
			local function neonBeam(fromPos: Vector3, toPos: Vector3, name: string)
				local a0p = part({
					Name = name .. "_A0",
					Size = Vector3.new(0.4, 0.4, 0.4),
					Position = fromPos,
					Color = neon,
					Material = Enum.Material.Neon,
					Transparency = 1,
					CanCollide = false,
					Parent = tutorialFolder,
				})
				local a1p = part({
					Name = name .. "_A1",
					Size = Vector3.new(0.4, 0.4, 0.4),
					Position = toPos,
					Color = neon,
					Material = Enum.Material.Neon,
					Transparency = 1,
					CanCollide = false,
					Parent = tutorialFolder,
				})
				local att0 = Instance.new("Attachment")
				att0.Parent = a0p
				local att1 = Instance.new("Attachment")
				att1.Parent = a1p
				local beam = Instance.new("Beam")
				beam.Name = name
				beam.Attachment0 = att0
				beam.Attachment1 = att1
				beam:SetAttribute("WE_TutorialBeamAsset", 88687072714005)
				beam.FaceCamera = true
				beam.Width0 = 0.35
				beam.Width1 = 0.35
				beam.Color = ColorSequence.new(neon)
				beam.Transparency = NumberSequence.new(0.35)
				beam.LightEmission = 0.9
				beam.Parent = a0p
			end
			neonBeam(collectorPos, ccPos, "WE_NeonPath_CollectorToCC")
			neonBeam(ccPos, depotPos, "WE_NeonPath_CCToDepot")
		end)
		if not okNeon then
			warn("[WAR EMPIRE] MapSetup neon/tutorial path failed (pads already built):", errNeon)
		end
	end

	-- Military world dressing (visual only). Does not tag WE_UpgradeSlot / buy pads.
	-- PERF: skip MapDressing entirely in Studio unless ForceDress (attribute or DevConfig).
	-- Stagger after first frame so Play Solo is usable in seconds on laptop CPUs.
	task.defer(function()
		task.wait() -- yield past first frame
		local forceAttr = root:GetAttribute("ForceDress") == true
			or (Workspace:GetAttribute("ForceDress") == true)
		local forceDress = forceAttr or (DevConfig.StudioForceDress == true)
		local inStudio = RunService:IsStudio()
		local skipDress = inStudio and (DevConfig.StudioSkipWorldDressing ~= false) and not forceDress
		-- Live / non-Studio: Full warzone dressing. Studio ForceDress uses DevConfig quality.
		local quality = if (not inStudio) then "Full" else tostring(DevConfig.WorldDressQuality or "Low")

		print("[WAR EMPIRE] PERF note: deco kits use CastShadow=false. Studio Rendering → disable shadows / lower quality if still slow.")
		if skipDress then
			print("[WAR EMPIRE] PERF: MapDressing SKIPPED in Studio (StudioSkipWorldDressing). Set Workspace.WarEmpireSetup.ForceDress=true or DevConfig.StudioForceDress=true then resetmap to load dressing.")
		else
			task.wait(0.05)
			local okDress, errDress = pcall(function()
				MapDressing.Dress(root, { Quality = quality })
			end)
			if not okDress then
				warn("[WAR EMPIRE] MapDressing failed:", errDress)
			end
		end

		task.wait(0.1)
		-- Live: Full flora (align MapDressing live Full). Studio: sparse unless StudioSparseFlora=false.
		local wantFullFlora = (not inStudio)
			or (inStudio and DevConfig.StudioSparseFlora == false)
		local sparseFlora = not wantFullFlora
		local okFlora, errFlora = pcall(function()
			DesertFlora.Dress(root, { Sparse = sparseFlora })
		end)
		if not okFlora then
			warn("[WAR EMPIRE] DesertFlora failed:", errFlora)
		end
	end)

	-- Guarantee at least one Neutral Duration=0 spawn near origin
	local hasNeutralSpawn = false
	for _, inst in ipairs(root:GetDescendants()) do
		if inst:IsA("SpawnLocation") and inst.Neutral and inst.Duration == 0 then
			hasNeutralSpawn = true
			break
		end
	end
	if not hasNeutralSpawn then
		local fallbackSpawn = Instance.new("SpawnLocation")
		fallbackSpawn.Name = "NeutralSpawn"
		fallbackSpawn.Size = Vector3.new(12, 1, 12)
		fallbackSpawn.Position = Vector3.new(0, 5, 0)
		fallbackSpawn.Anchored = true
		fallbackSpawn.CanCollide = true
		fallbackSpawn.Neutral = true
		fallbackSpawn.Duration = 0
		fallbackSpawn.BrickColor = BrickColor.new("Bright green")
		fallbackSpawn.Material = Enum.Material.Neon
		fallbackSpawn.Parent = root
		print("[WAR EMPIRE] MapSetup: added fallback NeutralSpawn at (0,5,0)")
	end

		buildPadSupportShelves(root)

	-- Tier 2: near-plot oil spectacle (IndustrialPack + pipes + barrel ring). REJECT Ultrapump.
	do
		local okOil, errOil = pcall(function()
			local oilFolder = Instance.new("Folder")
			oilFolder.Name = "OilSpectacle"
			oilFolder.Parent = root
			local pads = {
				Vector3.new(-520, 0.5, -180),
				Vector3.new(520, 0.5, 180),
				Vector3.new(-200, 0.5, 620),
			}
			for oi, opos in ipairs(pads) do
				local pad = part({
					Name = "OilPad" .. oi,
					Size = Vector3.new(28, 0.6, 28),
					Position = opos,
					Color = Color3.fromRGB(42, 44, 40),
					Material = Enum.Material.Asphalt,
					CanCollide = true,
					Parent = oilFolder,
				})
				plainBillboard(pad, "OIL FIELD", Vector2.new(160, 32), 12, Color3.fromRGB(255, 180, 60))
				-- Amber landmark light
				local light = Instance.new("PointLight")
				light.Color = Color3.fromRGB(255, 160, 40)
				light.Brightness = 1.2
				light.Range = 40
				light.Parent = pad
				-- Walking-beam silhouette (Part kit derrick)
				local tower = part({
					Name = "DerrickTower" .. oi,
					Size = Vector3.new(1.2, 18, 1.2),
					Position = opos + Vector3.new(0, 9.5, 0),
					Color = Color3.fromRGB(70, 72, 68),
					Material = Enum.Material.Metal,
					CanCollide = false,
					Parent = oilFolder,
				})
				local beam = part({
					Name = "WalkingBeam" .. oi,
					Size = Vector3.new(14, 0.7, 0.7),
					Position = opos + Vector3.new(0, 17, 0),
					Color = Color3.fromRGB(90, 70, 50),
					Material = Enum.Material.Metal,
					CanCollide = false,
					Parent = oilFolder,
				})
				beam:SetAttribute("WE_OilBeam", true)
				-- Barrel ring
				for bi = 1, 8 do
					local ang = (bi / 8) * math.pi * 2
					local bpos = opos + Vector3.new(math.cos(ang) * 9, 1.1, math.sin(ang) * 9)
					part({
						Name = "OilBarrel" .. oi .. "_" .. bi,
						Size = Vector3.new(1.6, 2.2, 1.6),
						Position = bpos,
						Color = Color3.fromRGB(45, 70, 45),
						Material = Enum.Material.Metal,
						Shape = Enum.PartType.Cylinder,
						CanCollide = true,
						Parent = oilFolder,
					})
				end
				-- Catalog dress (IndustrialPack / RustyPipes / OilBarrel)
				task.defer(function()
					pcall(function()
						local vas = require(script.Parent.Parent.Services.VisualAssetService)
						if not vas then
							return
						end
						vas.TryAttachPropVisual(tower, "IndustrialPack")
						vas.TryAttachPropVisual(beam, "RustyPipes")
						for _, ch in ipairs(oilFolder:GetChildren()) do
							if ch:IsA("BasePart") and string.find(ch.Name, "OilBarrel" .. oi, 1, true) then
								vas.TryAttachPropVisual(ch, "OilBarrel")
							end
						end
					end)
				end)
			end
			-- Slow walking-beam sway
			task.spawn(function()
				local t0 = os.clock()
				while oilFolder.Parent do
					local t = os.clock() - t0
					for _, ch in ipairs(oilFolder:GetChildren()) do
						if ch:IsA("BasePart") and ch:GetAttribute("WE_OilBeam") then
							ch.CFrame = CFrame.new(ch.Position) * CFrame.Angles(0, 0, math.rad(math.sin(t * 0.7) * 12))
						end
					end
					task.wait(0.1)
				end
			end)
		end)
		if not okOil then
			warn("[MapSetup] OilSpectacle failed:", errOil)
		end
	end

	-- Tier 2: warzone landmarks (RadioTower / SmallFort / Bunker)
	do
		local okLm, errLm = pcall(function()
			local lm = Instance.new("Folder")
			lm.Name = "WarzoneLandmarks"
			lm.Parent = root
			local spots = {
				{ Name = "RadioTower", Key = "RadioTower", Pos = Vector3.new(0, 0.5, -1400), Size = Vector3.new(4, 28, 4) },
				{ Name = "SmallFort", Key = "SmallFort", Pos = Vector3.new(1100, 0.5, -1100), Size = Vector3.new(18, 10, 18) },
				{ Name = "BunkerApproach", Key = "Bunker", Pos = Vector3.new(-1100, 0.5, 900), Size = Vector3.new(14, 6, 14) },
			}
			for _, s in ipairs(spots) do
				local host = part({
					Name = s.Name .. "Host",
					Size = s.Size,
					Position = s.Pos + Vector3.new(0, s.Size.Y * 0.5, 0),
					Color = Color3.fromRGB(80, 78, 70),
					Material = Enum.Material.Concrete,
					CanCollide = true,
					Transparency = 0.25,
					Parent = lm,
				})
				plainBillboard(host, string.upper(s.Name), Vector2.new(180, 32), 14, Color3.fromRGB(220, 200, 140))
				task.defer(function()
					pcall(function()
						local vas = require(script.Parent.Parent.Services.VisualAssetService)
						if vas and vas.TryAttachPropVisual then
							vas.TryAttachPropVisual(host, s.Key)
						end
					end)
				end)
			end
		end)
		if not okLm then
			warn("[MapSetup] WarzoneLandmarks failed:", errLm)
		end
	end


	print("[WAR EMPIRE] MapSetup complete: desert ground=" .. tostring(GROUND_SIZE) .. "x" .. tostring(GROUND_THICKNESS) .. " topY=" .. tostring(GROUND_TOP_Y) .. " mesas=" .. tostring(DevConfig.MountainRingSegments or 14) .. " (dressing deferred/Studio-skip)")
	print("[WAR EMPIRE] MapSetup confirmation: Gravity=" .. tostring(Workspace.Gravity) .. " WarEmpireSetup children=" .. tostring(#root:GetChildren()))
	print("[WAR EMPIRE] Walk onto upgrade pads to BUY (auto). E opens Base/Garage menus. Delete WarEmpireSetup + Play / admin resetmap to regenerate.")
end

return MapSetup
