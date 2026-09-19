--!strict
--[[
	WAR EMPIRE — MapSetup (shared world build)
	Builds Workspace.WarEmpireSetup: map, plots, structure kits, territories,
	spawns, tutorial markers, NPC placeholders, lighting, MapDressing world props.
	Called from Bootstrap when WarEmpireSetup is missing (Play Solo / server start).
	Admin `resetmap` destroys WarEmpireSetup and re-runs.
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local MapDressing = require(script.Parent:WaitForChild("MapDressing"))

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

local COL_GROUND = Color3.fromRGB(32, 44, 30)
local COL_PAD = Color3.fromRGB(38, 44, 48)
local COL_PAD_EDGE = Color3.fromRGB(70, 190, 110)
local COL_VEHICLE = Color3.fromRGB(48, 62, 78)
local COL_NPC = Color3.fromRGB(88, 42, 42)
local COL_EVENT = Color3.fromRGB(78, 64, 36)

local STRUCTURES = {
	{ Id = "CommandCenter", Kit = "hq", Plinth = Color3.fromRGB(36, 48, 40), Body = Color3.fromRGB(55, 78, 58), Accent = Color3.fromRGB(230, 190, 60), Roof = Color3.fromRGB(40, 55, 45) },
	{ Id = "Barracks", Kit = "barracks", Plinth = Color3.fromRGB(42, 46, 38), Body = Color3.fromRGB(70, 78, 55), Accent = Color3.fromRGB(90, 160, 80), Roof = Color3.fromRGB(50, 55, 42) },
	{ Id = "VehicleDepot", Kit = "depot", Plinth = Color3.fromRGB(40, 48, 55), Body = Color3.fromRGB(58, 72, 88), Accent = Color3.fromRGB(90, 160, 220), Roof = Color3.fromRGB(45, 55, 65) },
	{ Id = "WeaponsFacility", Kit = "lab", Plinth = Color3.fromRGB(48, 40, 38), Body = Color3.fromRGB(88, 58, 50), Accent = Color3.fromRGB(200, 90, 70), Roof = Color3.fromRGB(55, 42, 40) },
	{ Id = "Helipad", Kit = "pad", Plinth = Color3.fromRGB(45, 50, 48), Body = Color3.fromRGB(60, 70, 65), Accent = Color3.fromRGB(220, 200, 80), Roof = Color3.fromRGB(50, 55, 52) },
	{ Id = "Dock", Kit = "dock", Plinth = Color3.fromRGB(35, 48, 58), Body = Color3.fromRGB(50, 75, 95), Accent = Color3.fromRGB(70, 180, 220), Roof = Color3.fromRGB(40, 58, 70) },
	{ Id = "Airfield", Kit = "pad", Plinth = Color3.fromRGB(50, 52, 48), Body = Color3.fromRGB(70, 72, 68), Accent = Color3.fromRGB(180, 190, 100), Roof = Color3.fromRGB(55, 58, 52) },
	{ Id = "DefensiveWalls", Kit = "wall", Plinth = Color3.fromRGB(48, 48, 45), Body = Color3.fromRGB(85, 85, 78), Accent = Color3.fromRGB(120, 130, 110), Roof = Color3.fromRGB(60, 60, 55) },
	{ Id = "Watchtowers", Kit = "tower", Plinth = Color3.fromRGB(44, 46, 40), Body = Color3.fromRGB(72, 78, 60), Accent = Color3.fromRGB(200, 160, 70), Roof = Color3.fromRGB(50, 52, 44) },
	{ Id = "Radar", Kit = "tower", Plinth = Color3.fromRGB(40, 42, 55), Body = Color3.fromRGB(55, 60, 90), Accent = Color3.fromRGB(100, 200, 255), Roof = Color3.fromRGB(45, 48, 70) },
	{ Id = "ResearchLab", Kit = "lab", Plinth = Color3.fromRGB(38, 45, 55), Body = Color3.fromRGB(50, 70, 95), Accent = Color3.fromRGB(80, 180, 220), Roof = Color3.fromRGB(42, 55, 72) },
	{ Id = "MissileDefense", Kit = "tower", Plinth = Color3.fromRGB(48, 42, 40), Body = Color3.fromRGB(75, 55, 50), Accent = Color3.fromRGB(220, 100, 60), Roof = Color3.fromRGB(55, 45, 42) },
	{ Id = "PowerStation", Kit = "power", Plinth = Color3.fromRGB(50, 48, 35), Body = Color3.fromRGB(90, 85, 50), Accent = Color3.fromRGB(255, 210, 70), Roof = Color3.fromRGB(60, 55, 40) },
	{ Id = "Warehouse", Kit = "warehouse", Plinth = Color3.fromRGB(45, 42, 38), Body = Color3.fromRGB(95, 80, 60), Accent = Color3.fromRGB(180, 140, 80), Roof = Color3.fromRGB(55, 50, 42) },
	{ Id = "SpecialForcesFacility", Kit = "special", Plinth = Color3.fromRGB(35, 38, 42), Body = Color3.fromRGB(45, 55, 65), Accent = Color3.fromRGB(160, 80, 200), Roof = Color3.fromRGB(30, 35, 40) },
}

local STARTER_COST = {
	CommandCenter = 1500, Barracks = 2500, VehicleDepot = 3000, WeaponsFacility = 2800,
	Helipad = 5000, Dock = 4500, Airfield = 8000, DefensiveWalls = 2000, Watchtowers = 2200,
	Radar = 4000, ResearchLab = 4500, MissileDefense = 6000, PowerStation = 3500,
	Warehouse = 3200, SpecialForcesFacility = 10000,
}

-- Map scale: ground ~4800, plot ring ~800, pads ~200 (was 2600 / 450 / 140)
local GROUND_SIZE = 4800
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
	{ Id = "CentralPlaza", Pos = Vector3.new(0, 1, 0), Color = Color3.fromRGB(180, 170, 50), Radius = 70 },
	{ Id = "NorthRidge", Pos = Vector3.new(0, 1, -1300), Color = Color3.fromRGB(55, 120, 180), Radius = 60 },
	{ Id = "SouthDocks", Pos = Vector3.new(0, 1, 1300), Color = Color3.fromRGB(45, 110, 150), Radius = 60 },
	{ Id = "EastArmory", Pos = Vector3.new(1300, 1, 0), Color = Color3.fromRGB(170, 55, 55), Radius = 55 },
	{ Id = "WestDepot", Pos = Vector3.new(-1300, 1, 0), Color = Color3.fromRGB(55, 140, 70), Radius = 55 },
	{ Id = "OilFields", Pos = Vector3.new(950, 1, 950), Color = Color3.fromRGB(150, 110, 40), Radius = 65 },
	{ Id = "RadarHill", Pos = Vector3.new(-950, 1, -950), Color = Color3.fromRGB(130, 70, 170), Radius = 60 },
	-- Coastal oil decks (Y matches TerritoryConfig / OilRigConfig platform height)
	{ Id = "CoastalOilAlpha", Pos = Vector3.new(1800, 28, -750), Color = Color3.fromRGB(190, 145, 45), Radius = 48, OilRig = true },
	{ Id = "CoastalOilBravo", Pos = Vector3.new(-1800, 28, 750), Color = Color3.fromRGB(170, 125, 40), Radius = 48, OilRig = true },
	{ Id = "FortIronclad", Pos = Vector3.new(1450, 1, -1450), Color = Color3.fromRGB(140, 145, 155), Radius = 55, Fortress = true },
	{ Id = "FortSandhold", Pos = Vector3.new(-1450, 1, 1450), Color = Color3.fromRGB(190, 155, 90), Radius = 55, Fortress = true },
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
		Transparency = 0.32, -- visual kits v2: less washout
		Parent = parentPlinth,
	})
	if shape then
		p.Shape = shape
	end
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
	-- Visual kits v2: larger readable price cards
	local bb = Instance.new("BillboardGui")
	bb.Name = "WE_PriceBillboard"
	bb.Size = UDim2.fromOffset(200, 72)
	bb.StudsOffset = Vector3.new(0, 6.0, 0)
	bb.AlwaysOnTop = true -- only useful nearby (short MaxDistance)
	bb.MaxDistance = 48 -- mobile: price cards near-only (was 1000)
	bb.Parent = parent

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(8, 10, 12)
	backdrop.BackgroundTransparency = 0.08
	backdrop.BorderSizePixel = 0
	backdrop.Parent = bb
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = backdrop
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Stroke"
	stroke.Color = accent
	stroke.Thickness = 2
	stroke.Transparency = 0.1
	stroke.Parent = backdrop

	local titleLab = Instance.new("TextLabel")
	titleLab.Name = "Title"
	titleLab.Size = UDim2.new(1, -10, 0, 26)
	titleLab.Position = UDim2.fromOffset(5, 4)
	titleLab.BackgroundTransparency = 1
	titleLab.Text = title
	titleLab.TextColor3 = Color3.fromRGB(245, 245, 248)
	titleLab.TextScaled = true
	titleLab.Font = Enum.Font.GothamBold
	titleLab.TextStrokeTransparency = 0.4
	titleLab.Parent = backdrop

	local costLab = Instance.new("TextLabel")
	costLab.Name = "Cost"
	costLab.Size = UDim2.new(1, -10, 0, 34)
	costLab.Position = UDim2.fromOffset(5, 30)
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
	bb.AlwaysOnTop = true -- short range only
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
	priceBillboard(plinth, title, "Lv 0 → 1 / $" .. tostring(cost), def.Accent)
	return plinth
end



-- Visual kits v2: shared infantry silhouette for MapSetup placeholders / workers
local function makeSoldierKit(parentFolder, name, cf, bodyColor, labelText, labelColor, health, npcType, npcId)
	local model = Instance.new("Model")
	model.Name = name
	if npcId then
		model:SetAttribute("NPCId", npcId)
	end
	if npcType then
		model:SetAttribute("NPCType", npcType)
	end
	local torso = part({
		Name = "HumanoidRootPart",
		Size = Vector3.new(2.05, 2.35, 1.2),
		Color = bodyColor,
		Material = Enum.Material.Fabric,
		Anchored = true,
		CanCollide = true,
		CFrame = cf,
		Parent = model,
	})
	local head = part({
		Name = "Head",
		Size = Vector3.new(1.1, 1.1, 1.1),
		Color = Color3.fromRGB(95, 72, 55),
		Material = Enum.Material.SmoothPlastic,
		Anchored = true,
		CanCollide = false,
		CFrame = torso.CFrame + Vector3.new(0, 1.7, 0),
		Shape = Enum.PartType.Ball,
		Parent = model,
	})
	part({
		Name = "Helmet",
		Size = Vector3.new(1.28, 0.5, 1.28),
		Color = Color3.fromRGB(
			math.clamp(math.floor(bodyColor.R * 255) - 25, 20, 255),
			math.clamp(math.floor(bodyColor.G * 255) - 15, 20, 255),
			math.clamp(math.floor(bodyColor.B * 255) - 10, 20, 255)
		),
		Material = Enum.Material.Metal,
		Anchored = true,
		CanCollide = false,
		CFrame = head.CFrame + Vector3.new(0, 0.4, 0),
		Parent = model,
	})
	part({
		Name = "Vest",
		Size = Vector3.new(2.15, 1.25, 1.35),
		Color = Color3.fromRGB(
			math.clamp(math.floor(bodyColor.R * 255) - 30, 20, 255),
			math.clamp(math.floor(bodyColor.G * 255) - 20, 20, 255),
			math.clamp(math.floor(bodyColor.B * 255) - 15, 20, 255)
		),
		Material = Enum.Material.Metal,
		Anchored = true,
		CanCollide = false,
		CFrame = torso.CFrame + Vector3.new(0, 0.25, 0),
		Parent = model,
	})
	part({
		Name = "LegL",
		Size = Vector3.new(0.65, 1.4, 0.65),
		Color = bodyColor,
		Material = Enum.Material.Fabric,
		Anchored = true,
		CanCollide = false,
		CFrame = torso.CFrame * CFrame.new(-0.45, -1.75, 0),
		Parent = model,
	})
	part({
		Name = "LegR",
		Size = Vector3.new(0.65, 1.4, 0.65),
		Color = bodyColor,
		Material = Enum.Material.Fabric,
		Anchored = true,
		CanCollide = false,
		CFrame = torso.CFrame * CFrame.new(0.45, -1.75, 0),
		Parent = model,
	})
	part({
		Name = "Rifle",
		Size = Vector3.new(0.26, 0.26, 2.3),
		Color = Color3.fromRGB(30, 30, 32),
		Material = Enum.Material.Metal,
		Anchored = true,
		CanCollide = false,
		CFrame = torso.CFrame * CFrame.new(0.95, 0.15, -0.75),
		Parent = model,
	})
	part({
		Name = "Accent",
		Size = Vector3.new(1.7, 0.12, 0.3),
		Color = labelColor or Color3.fromRGB(200, 80, 60),
		Material = Enum.Material.Neon,
		Anchored = true,
		CanCollide = false,
		CFrame = torso.CFrame * CFrame.new(0, 0.9, -0.55),
		Parent = model,
	})
	local hum = Instance.new("Humanoid")
	hum.MaxHealth = health or 100
	hum.Health = health or 100
	hum.Parent = model
	model.PrimaryPart = torso
	model.Parent = parentFolder
	CollectionService:AddTag(model, TAG_NPC_ENTITY)
	if labelText then
		plainBillboard(head, labelText, Vector2.new(110, 22), 2, labelColor or Color3.fromRGB(255, 180, 140))
	end
	return model
end

local MapSetup = {}

function MapSetup.Run()
	-- Normal gravity so characters fall onto terrain (not float/void)
	Workspace.Gravity = 196.2

	-- Lighting / sky / atmosphere — large map readable at distance + gentle day/night
	Lighting.Ambient = Color3.fromRGB(72, 82, 68)
	Lighting.OutdoorAmbient = Color3.fromRGB(88, 98, 82)
	Lighting.Brightness = 2.25
	Lighting.ClockTime = 15.0
	Lighting.GeographicLatitude = 28
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.32
	Lighting.FogColor = Color3.fromRGB(145, 158, 135)
	Lighting.FogStart = 800
	Lighting.FogEnd = 4400
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
	sky.StarCount = 3000
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 9

	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atm then
		atm = Instance.new("Atmosphere")
		atm.Parent = Lighting
	end
	atm.Density = 0.22
	atm.Offset = 0.12
	atm.Color = Color3.fromRGB(155, 168, 145)
	atm.Decay = Color3.fromRGB(95, 108, 88)
	atm.Glare = 0.18
	atm.Haze = 1.85

	-- Cancel prior day/night loop on resetmap, then start a gentle cycle (~20 min full day)
	local dayMarker = Lighting:FindFirstChild("WE_DayNightMarker")
	if dayMarker then
		dayMarker:Destroy()
	end
	dayMarker = Instance.new("Folder")
	dayMarker.Name = "WE_DayNightMarker"
	dayMarker.Parent = Lighting
	task.spawn(function()
		local STEP = 0.035 -- hours per tick
		local WAIT = 1.5
		while dayMarker.Parent do
			local t = (Lighting.ClockTime + STEP) % 24
			Lighting.ClockTime = t
			-- Night dip: cooler ambient + thicker haze; day stays readable on large map
			local night = 0
			if t < 5 or t > 20 then
				night = 1
			elseif t < 7 then
				night = 1 - (t - 5) / 2
			elseif t > 18 then
				night = (t - 18) / 2
			end
			Lighting.Brightness = 2.35 - night * 1.55
			Lighting.Ambient = Color3.fromRGB(72, 82, 68):Lerp(Color3.fromRGB(28, 34, 55), night)
			Lighting.OutdoorAmbient = Color3.fromRGB(88, 98, 82):Lerp(Color3.fromRGB(36, 42, 70), night)
			Lighting.FogColor = Color3.fromRGB(145, 158, 135):Lerp(Color3.fromRGB(40, 48, 72), night)
			Lighting.FogStart = 800 - night * 180
			Lighting.FogEnd = 4400 - night * 600
			atm.Density = 0.20 + night * 0.12
			atm.Haze = 1.7 + night * 0.9
			atm.Color = Color3.fromRGB(155, 168, 145):Lerp(Color3.fromRGB(70, 80, 120), night)
			atm.Glare = 0.18 - night * 0.1
			task.wait(WAIT)
		end
	end)

	local root = ensureFolder("WarEmpireSetup", Workspace)
	local map = ensureFolder("Map", root)
	part({
		Name = "Ground",
		Size = Vector3.new(GROUND_SIZE, 1, GROUND_SIZE),
		Position = Vector3.new(0, 0, 0),
		Color = COL_GROUND,
		Material = Enum.Material.Grass,
		Parent = map,
	})
	-- Road grid scaled to plot ring (optional visual guide)
	for _, z in ipairs({ -PLOT_RING, 0, PLOT_RING }) do
		part({
			Name = "RoadZ" .. z,
			Size = Vector3.new(GROUND_SIZE, 0.15, 14),
			Position = Vector3.new(0, 0.55, z),
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
			Position = Vector3.new(x, 0.55, 0),
			Color = Color3.fromRGB(50, 52, 48),
			Material = Enum.Material.Asphalt,
			CanCollide = false,
			Parent = map,
		})
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
			makeSoldierKit(
				yardFolder,
				"TrainingWorker" .. wi,
				CFrame.new(wpos) * CFrame.Angles(0, math.rad(180), 0),
				Color3.fromRGB(70, 85, 55),
				"WORKER",
				Color3.fromRGB(180, 220, 120),
				50,
				nil,
				nil
			)
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
		plainBillboard(
			part({
				Name = "YardAnchor",
				Size = Vector3.new(1, 1, 1),
				Position = pos + Vector3.new(-14, 8, 48),
				Transparency = 1,
				CanCollide = false,
				Parent = yardFolder,
			}),
			"TRAINING YARD · Soldiers earn cash",
			Vector2.new(280, 40),
			8,
			Color3.fromRGB(255, 200, 120)
		)
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

		plainBillboard(marker, def.Id .. "  [NEUTRAL]  ·  Stand to capture", Vector2.new(240, 42), 10, Color3.new(1, 1, 1))

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
			Color = Color3.fromRGB(35, 90, 130),
			Material = Enum.Material.Glass,
			Transparency = 0.35,
			CanCollide = false,
			Parent = waterFolder,
		})
		water.Name = "WaterPlane"
		-- Shallow collide strip so boats have something under them
		part({
			Name = "HarborShelf",
			Size = Vector3.new(GROUND_SIZE * 0.75, 1, 120),
			Position = Vector3.new(0, 0.4, 1520),
			Color = Color3.fromRGB(40, 70, 90),
			Material = Enum.Material.Slate,
			Transparency = 0.15,
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
	local bankPos = Vector3.new(420, 1, -420)
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
	for gi = 1, 5 do
		local angle = (gi / 5) * math.pi * 2
		local gpos = bankPos + Vector3.new(math.cos(angle) * 18, 2.6, math.sin(angle) * 18)
		makeSoldierKit(
			bankFolder,
			"BankGuard_" .. gi,
			CFrame.new(gpos),
			Color3.fromRGB(60, 70, 110),
			"BANK GUARD",
			Color3.fromRGB(140, 180, 255),
			160,
			"BankGuard",
			"bank_guard_" .. gi
		)
	end

	local tutorialFolder = ensureFolder("TutorialMarkers", root)
	local function tutorialMarker(name, pos, color, stepId)
		local p = part({
			Name = name,
			Size = Vector3.new(7, 1.2, 7),
			Position = pos,
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = 0.2,
			CanCollide = false,
			Parent = tutorialFolder,
		})
		p:SetAttribute("TutorialStepId", stepId or name)
		CollectionService:AddTag(p, TAG_TUTORIAL)
		plainBillboard(p, "TUT · " .. name:gsub("Tutorial_", ""), Vector2.new(200, 34), 6, Color3.fromRGB(255, 245, 180))
		beacon(tutorialFolder, pos, color, name .. "_Beacon")
		part({
			Name = name .. "_Ring",
			Size = Vector3.new(10, 0.25, 10),
			Position = pos + Vector3.new(0, -0.4, 0),
			Color = color,
			Transparency = 0.5,
			CanCollide = false,
			Material = Enum.Material.Neon,
			Parent = tutorialFolder,
		})
		return p
	end

	local plot1 = PLOT_POSITIONS[1]
	-- Offsets track Plot1 spawn / structure grid (STRUCT_ORIGIN + gaps)
	tutorialMarker("Tutorial_ClaimBase", plot1 + Vector3.new(0, 2, 52), Color3.fromRGB(230, 200, 80), "ClaimBase")
	tutorialMarker("Tutorial_CommandCenter", plot1 + STRUCT_ORIGIN + Vector3.new(0, 1.4, 0), Color3.fromRGB(80, 200, 120), "CommandCenter")
	tutorialMarker("Tutorial_Income", plot1 + Vector3.new(0, 3, 0), Color3.fromRGB(80, 200, 160), "Income")
	tutorialMarker("Tutorial_Barracks", plot1 + STRUCT_ORIGIN + Vector3.new(STRUCT_GAP, 1.4, 0), Color3.fromRGB(100, 180, 220), "Barracks")
	local jeepPos = Vector3.new(200, 2, 0)
	local vSpawns = CollectionService:GetTagged(TAG_VEHICLE)
	if #vSpawns > 0 and vSpawns[1]:IsA("BasePart") then
		jeepPos = vSpawns[1].Position + Vector3.new(0, 2, 0)
	end
	tutorialMarker("Tutorial_Jeep", jeepPos, Color3.fromRGB(120, 140, 200), "Jeep")
	tutorialMarker("Tutorial_Outpost", Vector3.new(0, 3, 0), Color3.fromRGB(200, 120, 80), "Outpost")

	-- Military world dressing (visual only — outposts/bunkers/hangars/depots/camps)
	-- Does not tag WE_UpgradeSlot / buy pads. Regenerate via resetmap or delete WarEmpireSetup.
	MapDressing.Dress(root)

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

	print("[WAR EMPIRE] MapSetup complete: ground=" .. tostring(GROUND_SIZE) .. " plotRing=" .. tostring(PLOT_RING) .. " naval/dock/training/oil/forts/bank + WorldDressing under Workspace.WarEmpireSetup")
	print("[WAR EMPIRE] MapSetup confirmation: Gravity=" .. tostring(Workspace.Gravity) .. " WarEmpireSetup children=" .. tostring(#root:GetChildren()))
	print("[WAR EMPIRE] Walk onto upgrade pads to BUY (auto). E opens Base/Garage menus. Delete WarEmpireSetup + Play / admin resetmap to regenerate.")
end

return MapSetup
