--!strict
--[[
	WAR EMPIRE — MapSetup (shared world build)
	Builds Workspace.WarEmpireSetup: map, plots, structure kits, territories,
	spawns, tutorial markers, NPC placeholders, lighting.
	Called from Bootstrap when WarEmpireSetup is missing (Play Solo / server start).
	Admin `resetmap` destroys WarEmpireSetup and re-runs.
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local TAG_BASE = "WE_BasePlot"
local TAG_SLOT = "WE_UpgradeSlot"
local TAG_TERRITORY = "WE_Territory"
local TAG_CAPTURE = "WE_CaptureZone"
local TAG_VEHICLE = "WE_VehicleSpawn"
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
	Helipad = 5000, Airfield = 8000, DefensiveWalls = 2000, Watchtowers = 2200,
	Radar = 4000, ResearchLab = 4500, MissileDefense = 6000, PowerStation = 3500,
	Warehouse = 3200, SpecialForcesFacility = 10000,
}

local PLOT_POSITIONS = {
	Vector3.new(-200, 0.5, -100),
	Vector3.new(-200, 0.5, 100),
	Vector3.new(0, 0.5, -200),
	Vector3.new(0, 0.5, 200),
	Vector3.new(200, 0.5, -100),
	Vector3.new(200, 0.5, 100),
}

local TERRITORIES = {
	{ Id = "CentralPlaza", Pos = Vector3.new(0, 1, 0), Color = Color3.fromRGB(180, 170, 50), Radius = 40 },
	{ Id = "NorthRidge", Pos = Vector3.new(0, 1, -350), Color = Color3.fromRGB(55, 120, 180), Radius = 35 },
	{ Id = "SouthDocks", Pos = Vector3.new(0, 1, 350), Color = Color3.fromRGB(45, 110, 150), Radius = 35 },
	{ Id = "EastArmory", Pos = Vector3.new(350, 1, 0), Color = Color3.fromRGB(170, 55, 55), Radius = 30 },
	{ Id = "WestDepot", Pos = Vector3.new(-350, 1, 0), Color = Color3.fromRGB(55, 140, 70), Radius = 30 },
	{ Id = "OilFields", Pos = Vector3.new(250, 1, 250), Color = Color3.fromRGB(150, 110, 40), Radius = 40 },
	{ Id = "RadarHill", Pos = Vector3.new(-250, 1, -250), Color = Color3.fromRGB(130, 70, 170), Radius = 35 },
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

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		(p :: any)[k] = v
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
		Transparency = 0.45,
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
	local bb = Instance.new("BillboardGui")
	bb.Name = "WE_PriceBillboard"
	bb.Size = UDim2.fromOffset(170, 60)
	bb.StudsOffset = Vector3.new(0, 5.2, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 200
	bb.Parent = parent

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(10, 12, 14)
	backdrop.BackgroundTransparency = 0.18
	backdrop.BorderSizePixel = 0
	backdrop.Parent = bb
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = backdrop
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Stroke"
	stroke.Color = accent
	stroke.Thickness = 1.5
	stroke.Transparency = 0.2
	stroke.Parent = backdrop

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = title .. "\nLv 0 → 1\n" .. costLine
	label.TextColor3 = Color3.fromRGB(235, 220, 140)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextStrokeTransparency = 0.55
	label.Parent = backdrop
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 5)
	pad.PaddingRight = UDim.new(0, 5)
	pad.PaddingTop = UDim.new(0, 3)
	pad.PaddingBottom = UDim.new(0, 3)
	pad.Parent = backdrop
	return bb
end

local function plainBillboard(parent, text, size, offsetY, textColor)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Label"
	bb.Size = UDim2.fromOffset(size.X, size.Y)
	bb.StudsOffset = Vector3.new(0, offsetY, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 240
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
		Transparency = 0.45,
		Material = Enum.Material.Concrete,
		CanCollide = true,
		Parent = plotFolder,
	})
	plinth:SetAttribute("PlotId", plotId)
	plinth:SetAttribute("StructureId", def.Id)
	plinth:SetAttribute("BaseSize", plinthSize)
	CollectionService:AddTag(plinth, TAG_SLOT)

	local kit = def.Kit
	if kit == "hq" then
		kitPart(plinth, "Body", Vector3.new(5.5, 3.2, 5.5), Vector3.new(0, 2.2, 0), def.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(6.2, 0.6, 6.2), Vector3.new(0, 4.1, 0), def.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Antenna", Vector3.new(0.35, 4.5, 0.35), Vector3.new(1.8, 6.5, 1.8), def.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Accent", Vector3.new(6.4, 0.25, 6.4), Vector3.new(0, 0.75, 0), def.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Detail", Vector3.new(1.2, 1.2, 1.2), Vector3.new(-2, 3.5, -2), def.Accent, Enum.Material.Neon, Enum.PartType.Ball)
	elseif kit == "barracks" then
		kitPart(plinth, "Body", Vector3.new(6.5, 2.4, 4.2), Vector3.new(0, 1.8, 0), def.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(7, 0.5, 4.8), Vector3.new(0, 3.2, 0), def.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(6.8, 0.2, 4.6), Vector3.new(0, 0.7, 0), def.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Detail", Vector3.new(0.8, 1.6, 0.8), Vector3.new(-2.8, 2.2, 0), def.Accent, Enum.Material.Neon, nil)
	elseif kit == "depot" then
		kitPart(plinth, "Body", Vector3.new(6.8, 2.0, 5.5), Vector3.new(0, 1.6, 0), def.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(7.2, 0.35, 6), Vector3.new(0, 2.8, 0), def.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(3, 0.3, 5.8), Vector3.new(0, 0.7, 0), def.Accent, Enum.Material.Neon, nil)
	elseif kit == "lab" then
		kitPart(plinth, "Body", Vector3.new(5, 3.0, 5), Vector3.new(0, 2.1, 0), def.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(5.4, 0.5, 5.4), Vector3.new(0, 3.8, 0), def.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Antenna", Vector3.new(0.4, 3.5, 0.4), Vector3.new(0, 5.8, 0), def.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Accent", Vector3.new(5.6, 0.2, 5.6), Vector3.new(0, 0.7, 0), def.Accent, Enum.Material.Neon, nil)
	elseif kit == "tower" then
		kitPart(plinth, "Body", Vector3.new(2.8, 5.5, 2.8), Vector3.new(0, 3.4, 0), def.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(3.6, 0.5, 3.6), Vector3.new(0, 6.4, 0), def.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Antenna", Vector3.new(0.3, 3.2, 0.3), Vector3.new(0, 8.2, 0), def.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Accent", Vector3.new(3.2, 0.25, 3.2), Vector3.new(0, 0.7, 0), def.Accent, Enum.Material.Neon, nil)
	elseif kit == "pad" then
		kitPart(plinth, "Body", Vector3.new(7.2, 0.4, 7.2), Vector3.new(0, 0.9, 0), def.Body, Enum.Material.Concrete, nil)
		kitPart(plinth, "Accent", Vector3.new(6.5, 0.15, 0.5), Vector3.new(0, 1.15, 0), def.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Detail", Vector3.new(0.5, 0.15, 6.5), Vector3.new(0, 1.15, 0), def.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Roof", Vector3.new(1.5, 0.3, 1.5), Vector3.new(0, 1.3, 0), def.Roof, Enum.Material.Metal, nil)
	elseif kit == "wall" then
		kitPart(plinth, "Body", Vector3.new(7.5, 2.8, 1.4), Vector3.new(0, 2.0, 0), def.Body, Enum.Material.Concrete, nil)
		kitPart(plinth, "Accent", Vector3.new(7.6, 0.25, 1.6), Vector3.new(0, 3.5, 0), def.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Roof", Vector3.new(7.5, 0.4, 1.8), Vector3.new(0, 3.7, 0), def.Roof, Enum.Material.Metal, nil)
	elseif kit == "power" then
		kitPart(plinth, "Body", Vector3.new(4.5, 3.5, 4.5), Vector3.new(0, 2.4, 0), def.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(2.2, 2.2, 2.2), Vector3.new(0, 4.5, 0), def.Accent, Enum.Material.Neon, Enum.PartType.Ball)
		kitPart(plinth, "Roof", Vector3.new(5, 0.4, 5), Vector3.new(0, 4.3, 0), def.Roof, Enum.Material.Metal, nil)
	elseif kit == "warehouse" then
		kitPart(plinth, "Body", Vector3.new(7, 2.6, 5.5), Vector3.new(0, 1.9, 0), def.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(7.4, 0.5, 6), Vector3.new(0, 3.4, 0), def.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(7.2, 0.2, 5.8), Vector3.new(0, 0.7, 0), def.Accent, Enum.Material.Neon, nil)
	else
		kitPart(plinth, "Body", Vector3.new(5.2, 3.4, 5.2), Vector3.new(0, 2.3, 0), def.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(4, 1.2, 4), Vector3.new(0, 4.5, 0), def.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Antenna", Vector3.new(0.35, 4, 0.35), Vector3.new(0, 7, 0), def.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Accent", Vector3.new(5.8, 0.25, 5.8), Vector3.new(0, 0.7, 0), def.Accent, Enum.Material.Neon, nil)
	end

	local cost = STARTER_COST[def.Id] or 0
	local title = if isCC then ("★ " .. def.Id) else def.Id
	priceBillboard(plinth, title, "$" .. tostring(cost), def.Accent)
	return plinth
end


local MapSetup = {}

function MapSetup.Run()
	-- Lighting
	Lighting.Ambient = Color3.fromRGB(78, 88, 70)
	Lighting.OutdoorAmbient = Color3.fromRGB(90, 100, 80)
	Lighting.Brightness = 2.1
	Lighting.ClockTime = 14.5
	Lighting.GeographicLatitude = 25
	Lighting.EnvironmentDiffuseScale = 0.55
	Lighting.EnvironmentSpecularScale = 0.35
	pcall(function()
		Lighting.GlobalShadows = true
	end)
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atm then
		atm = Instance.new("Atmosphere")
		atm.Parent = Lighting
	end
	atm.Density = 0.28
	atm.Offset = 0.1
	atm.Color = Color3.fromRGB(160, 170, 140)
	atm.Decay = Color3.fromRGB(100, 110, 90)
	atm.Glare = 0.15
	atm.Haze = 1.2

	local root = ensureFolder("WarEmpireSetup", Workspace)
	local map = ensureFolder("Map", root)
	part({
		Name = "Ground",
		Size = Vector3.new(900, 1, 900),
		Position = Vector3.new(0, 0, 0),
		Color = COL_GROUND,
		Material = Enum.Material.Grass,
		Parent = map,
	})
	for _, z in ipairs({ -200, 0, 200 }) do
		part({
			Name = "RoadZ" .. z,
			Size = Vector3.new(900, 0.15, 10),
			Position = Vector3.new(0, 0.55, z),
			Color = Color3.fromRGB(50, 52, 48),
			Material = Enum.Material.Asphalt,
			CanCollide = false,
			Parent = map,
		})
	end
	for _, x in ipairs({ -200, 0, 200 }) do
		part({
			Name = "RoadX" .. x,
			Size = Vector3.new(10, 0.15, 900),
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
			Size = Vector3.new(90, 1, 90),
			Position = pos,
			Color = COL_PAD,
			Material = Enum.Material.Concrete,
			Parent = plotFolder,
		})
		pad:SetAttribute("PlotId", plotId)
		CollectionService:AddTag(pad, TAG_BASE)
		neonEdge(pad, COL_PAD_EDGE, 0.45)

		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "PlayerSpawn"
		spawn.Size = Vector3.new(8, 1, 8)
		spawn.Position = pos + Vector3.new(0, 2, 34)
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.BrickColor = BrickColor.new("Dark green")
		spawn.Material = Enum.Material.Neon
		spawn.Parent = plotFolder

		plainBillboard(pad, "BASE " .. plotId .. "  ·  Walk pads to BUY  ·  E / B menu", Vector2.new(260, 42), 12, Color3.fromRGB(200, 230, 200))
		beacon(plotFolder, pos + Vector3.new(0, 0, -40), COL_PAD_EDGE, "PlotBeacon")

		local cols = 4
		for i, def in ipairs(STRUCTURES) do
			local col = (i - 1) % cols
			local row = math.floor((i - 1) / cols)
			local offset = Vector3.new(-28 + col * 18, 1.6, -28 + row * 18)
			buildStructureKit(plotFolder, plotId, pos, offset, def)
		end
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
			Size = Vector3.new(5, 3, 0.25),
			Position = def.Pos + Vector3.new(2.6, 12, 0),
			Color = def.Color,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Transparency = 0.15,
			Parent = territories,
		})
		flag:SetAttribute("TerritoryId", def.Id)
		flag:SetAttribute("WE_Flag", true)

		beacon(territories, def.Pos + Vector3.new(def.Radius * 0.6, 0, 0), def.Color, def.Id .. "_Beacon")
	end

	local function makeSpawnFolder(name, tag, count, center, color)
		local folder = ensureFolder(name, root)
		for i = 1, count do
			local angle = (i / count) * math.pi * 2
			local pos = center + Vector3.new(math.cos(angle) * 80, 1, math.sin(angle) * 80)
			local p = part({
				Name = name .. i,
				Size = Vector3.new(12, 1.2, 12),
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

	makeSpawnFolder("VehicleSpawns", TAG_VEHICLE, 6, Vector3.new(0, 0, 0), COL_VEHICLE)
	makeSpawnFolder("NPCSpawns", TAG_NPC, 8, Vector3.new(100, 0, 100), COL_NPC)
	makeSpawnFolder("EventSpawns", TAG_EVENT, 4, Vector3.new(-100, 0, -100), COL_EVENT)

	local npcFolder = ensureFolder("NPCPlaceholders", root)
	for i, spawnPart in ipairs(CollectionService:GetTagged(TAG_NPC)) do
		if i > 4 then
			break
		end
		local model = Instance.new("Model")
		model.Name = "HostileInfantry_" .. i
		model:SetAttribute("NPCId", "studio_npc_" .. i)
		model:SetAttribute("NPCType", "Infantry")

		local torso = part({
			Name = "HumanoidRootPart",
			Size = Vector3.new(2, 2.2, 1.2),
			Color = Color3.fromRGB(70, 45, 40),
			Material = Enum.Material.Fabric,
			Anchored = true,
			CanCollide = true,
			CFrame = spawnPart.CFrame + Vector3.new(0, 3.2, 0),
			Parent = model,
		})
		local head = part({
			Name = "Head",
			Size = Vector3.new(1.15, 1.15, 1.15),
			Color = Color3.fromRGB(95, 70, 55),
			Material = Enum.Material.SmoothPlastic,
			Anchored = true,
			CanCollide = false,
			CFrame = torso.CFrame + Vector3.new(0, 1.7, 0),
			Shape = Enum.PartType.Ball,
			Parent = model,
		})
		part({
			Name = "Helmet",
			Size = Vector3.new(1.25, 0.55, 1.25),
			Color = Color3.fromRGB(45, 55, 40),
			Material = Enum.Material.Metal,
			Anchored = true,
			CanCollide = false,
			CFrame = head.CFrame + Vector3.new(0, 0.35, 0),
			Parent = model,
		})
		part({
			Name = "Rifle",
			Size = Vector3.new(0.3, 0.3, 2.4),
			Color = Color3.fromRGB(35, 35, 35),
			Material = Enum.Material.Metal,
			Anchored = true,
			CanCollide = false,
			CFrame = torso.CFrame * CFrame.new(0.9, 0.2, -0.8),
			Parent = model,
		})
		local hum = Instance.new("Humanoid")
		hum.MaxHealth = 80
		hum.Health = 80
		hum.Parent = model
		model.PrimaryPart = torso
		model.Parent = npcFolder
		CollectionService:AddTag(model, TAG_NPC_ENTITY)
		plainBillboard(head, "HOSTILE", Vector2.new(90, 22), 1.5, Color3.fromRGB(255, 120, 100))
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
	tutorialMarker("Tutorial_ClaimBase", plot1 + Vector3.new(0, 2, 32), Color3.fromRGB(230, 200, 80), "ClaimBase")
	tutorialMarker("Tutorial_CommandCenter", plot1 + Vector3.new(-28, 3, -28), Color3.fromRGB(80, 200, 120), "CommandCenter")
	tutorialMarker("Tutorial_Income", plot1 + Vector3.new(0, 3, 0), Color3.fromRGB(80, 200, 160), "Income")
	tutorialMarker("Tutorial_Barracks", plot1 + Vector3.new(-10, 3, -28), Color3.fromRGB(100, 180, 220), "Barracks")
	local jeepPos = Vector3.new(80, 2, 0)
	local vSpawns = CollectionService:GetTagged(TAG_VEHICLE)
	if #vSpawns > 0 and vSpawns[1]:IsA("BasePart") then
		jeepPos = vSpawns[1].Position + Vector3.new(0, 2, 0)
	end
	tutorialMarker("Tutorial_Jeep", jeepPos, Color3.fromRGB(120, 140, 200), "Jeep")
	tutorialMarker("Tutorial_Outpost", Vector3.new(0, 3, 0), Color3.fromRGB(200, 120, 80), "Outpost")

	print("[WAR EMPIRE] MapSetup complete: structure kits, price billboards, flags, lighting under Workspace.WarEmpireSetup")
	print("[WAR EMPIRE] Walk onto upgrade pads to BUY (auto). E opens Base/Garage menus. Delete WarEmpireSetup + Play / admin resetmap to regenerate.")
end

return MapSetup
