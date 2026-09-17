--[[
	WAR EMPIRE — Studio command-bar setup script
	Paste into Studio Command Bar and press Enter (once per place).

	Creates:
	- Workspace/Map (ground)
	- Workspace/Bases (6 plots) tagged WE_BasePlot
	- Upgrade slot Parts per structure tagged WE_UpgradeSlot
	- Workspace/Territories (7) tagged WE_Territory
	- Workspace/VehicleSpawns, NPCSpawns, EventSpawns
	- Tutorial markers (WE_TutorialMarker) for claim/CC/income/barracks/jeep/outpost
	- NPC placeholders + capture zones

	Safe to re-run: clears previous WarEmpireSetup folders first.
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local TAG_BASE = "WE_BasePlot"
local TAG_SLOT = "WE_UpgradeSlot"
local TAG_TERRITORY = "WE_Territory"
local TAG_CAPTURE = "WE_CaptureZone"
local TAG_VEHICLE = "WE_VehicleSpawn"
local TAG_NPC = "WE_NPCSpawn"
local TAG_EVENT = "WE_EventSpawn"
local TAG_TUTORIAL = "WE_TutorialMarker"

local STRUCTURES = {
	"CommandCenter",
	"Barracks",
	"VehicleDepot",
	"WeaponsFacility",
	"Helipad",
	"Airfield",
	"DefensiveWalls",
	"Watchtowers",
	"Radar",
	"ResearchLab",
	"MissileDefense",
	"PowerStation",
	"Warehouse",
	"SpecialForcesFacility",
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
	{ Id = "CentralPlaza", Pos = Vector3.new(0, 1, 0), Color = Color3.fromRGB(200, 200, 80), Radius = 40 },
	{ Id = "NorthRidge", Pos = Vector3.new(0, 1, -350), Color = Color3.fromRGB(80, 160, 220), Radius = 35 },
	{ Id = "SouthDocks", Pos = Vector3.new(0, 1, 350), Color = Color3.fromRGB(70, 140, 180), Radius = 35 },
	{ Id = "EastArmory", Pos = Vector3.new(350, 1, 0), Color = Color3.fromRGB(200, 80, 80), Radius = 30 },
	{ Id = "WestDepot", Pos = Vector3.new(-350, 1, 0), Color = Color3.fromRGB(100, 180, 100), Radius = 30 },
	{ Id = "OilFields", Pos = Vector3.new(250, 1, 250), Color = Color3.fromRGB(180, 140, 60), Radius = 40 },
	{ Id = "RadarHill", Pos = Vector3.new(-250, 1, -250), Color = Color3.fromRGB(160, 100, 200), Radius = 35 },
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

-- Root
local root = ensureFolder("WarEmpireSetup", Workspace)

-- Map ground
local map = ensureFolder("Map", root)
local ground = part({
	Name = "Ground",
	Size = Vector3.new(900, 1, 900),
	Position = Vector3.new(0, 0, 0),
	Color = Color3.fromRGB(45, 55, 40),
	Material = Enum.Material.Grass,
	Parent = map,
})

-- Bases
local bases = ensureFolder("Bases", root)
for plotId, pos in ipairs(PLOT_POSITIONS) do
	local plotFolder = Instance.new("Folder")
	plotFolder.Name = "Plot" .. plotId
	plotFolder.Parent = bases

	local pad = part({
		Name = "PlotPad",
		Size = Vector3.new(80, 1, 80),
		Position = pos,
		Color = Color3.fromRGB(55, 60, 65),
		Material = Enum.Material.Concrete,
		Parent = plotFolder,
	})
	pad:SetAttribute("PlotId", plotId)
	CollectionService:AddTag(pad, TAG_BASE)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlayerSpawn"
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Position = pos + Vector3.new(0, 2, 30)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = plotFolder

	local label = Instance.new("BillboardGui")
	label.Size = UDim2.fromOffset(120, 40)
	label.StudsOffset = Vector3.new(0, 8, 0)
	label.AlwaysOnTop = true
	label.Parent = pad
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = "Base Plot " .. plotId
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextScaled = true
	text.Font = Enum.Font.GothamBold
	text.Parent = label

	-- Upgrade slots in a grid on the pad
	local cols = 4
	for i, structureId in ipairs(STRUCTURES) do
		local col = (i - 1) % cols
		local row = math.floor((i - 1) / cols)
		local offset = Vector3.new(-24 + col * 16, 2, -24 + row * 16)
		local slot = part({
			Name = structureId,
			Size = Vector3.new(6, 2, 6),
			Position = pos + offset,
			Color = Color3.fromRGB(40, 50, 45),
			Transparency = 0.5,
			Material = Enum.Material.Metal,
			Parent = plotFolder,
		})
		slot:SetAttribute("PlotId", plotId)
		slot:SetAttribute("StructureId", structureId)
		slot:SetAttribute("BaseSize", Vector3.new(6, 2, 6))
		CollectionService:AddTag(slot, TAG_SLOT)

		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(100, 24)
		bb.StudsOffset = Vector3.new(0, 3, 0)
		bb.Parent = slot
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Text = structureId
		t.TextColor3 = Color3.fromRGB(200, 210, 200)
		t.TextScaled = true
		t.Font = Enum.Font.Gotham
		t.Parent = bb
	end
end

-- Territories + capture zones
local territories = ensureFolder("Territories", root)
for _, def in ipairs(TERRITORIES) do
	local diameter = (def.Radius or 30) * 2
	local marker = part({
		Name = def.Id,
		Size = Vector3.new(diameter, 2, diameter),
		Position = def.Pos,
		Color = def.Color,
		Transparency = 0.35,
		Material = Enum.Material.Neon,
		Parent = territories,
	})
	marker:SetAttribute("TerritoryId", def.Id)
	marker:SetAttribute("Radius", def.Radius or 30)
	marker:SetAttribute("OwnerType", "Neutral")
	marker:SetAttribute("OwnerUserId", 0)
	marker:SetAttribute("CaptureProgress", 0)
	CollectionService:AddTag(marker, TAG_TERRITORY)
	-- Dedicated capture zone (same pad; TerritoryService prefers WE_CaptureZone)
	CollectionService:AddTag(marker, TAG_CAPTURE)

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(160, 36)
	bb.StudsOffset = Vector3.new(0, 6, 0)
	bb.AlwaysOnTop = true
	bb.Parent = marker
	local t = Instance.new("TextLabel")
	t.Name = "TerritoryLabel"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = def.Id .. " [NEUTRAL]"
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextScaled = true
	t.Font = Enum.Font.GothamBold
	t.Parent = bb

	-- Soft cylinder ring hint (non-colliding)
	local ring = part({
		Name = def.Id .. "_Ring",
		Size = Vector3.new(diameter + 4, 0.4, diameter + 4),
		Position = def.Pos + Vector3.new(0, 0.2, 0),
		Color = def.Color,
		Transparency = 0.75,
		CanCollide = false,
		Material = Enum.Material.SmoothPlastic,
		Parent = territories,
	})
	ring:SetAttribute("TerritoryId", def.Id)
end

-- Spawns
local function makeSpawnFolder(name, tag, count, center, color)
	local folder = ensureFolder(name, root)
	for i = 1, count do
		local angle = (i / count) * math.pi * 2
		local pos = center + Vector3.new(math.cos(angle) * 80, 1, math.sin(angle) * 80)
		local p = part({
			Name = name .. i,
			Size = Vector3.new(8, 1, 8),
			Position = pos,
			Color = color,
			Parent = folder,
		})
		CollectionService:AddTag(p, tag)
	end
end

makeSpawnFolder("VehicleSpawns", TAG_VEHICLE, 6, Vector3.new(0, 0, 0), Color3.fromRGB(80, 100, 120))
makeSpawnFolder("NPCSpawns", TAG_NPC, 8, Vector3.new(100, 0, 100), Color3.fromRGB(120, 80, 80))
makeSpawnFolder("EventSpawns", TAG_EVENT, 4, Vector3.new(-100, 0, -100), Color3.fromRGB(120, 100, 60))


-- Lightweight NPC placeholders near spawn pads (CombatService also spawns at runtime)
local TAG_NPC_ENTITY = "WE_NPC"
local npcFolder = ensureFolder("NPCPlaceholders", root)
for i, spawnPart in ipairs(CollectionService:GetTagged(TAG_NPC)) do
	if i > 4 then break end -- keep Studio light; runtime pool handles the rest
	local model = Instance.new("Model")
	model.Name = "HostileInfantry_" .. i
	model:SetAttribute("NPCId", "studio_npc_" .. i)
	model:SetAttribute("NPCType", "Infantry")
	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(2, 2, 1)
	rootPart.Color = Color3.fromRGB(140, 55, 55)
	rootPart.Anchored = true
	rootPart.CanCollide = true
	rootPart.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
	rootPart.Parent = model
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.Color = Color3.fromRGB(160, 70, 70)
	head.Anchored = true
	head.CanCollide = false
	head.CFrame = rootPart.CFrame + Vector3.new(0, 1.6, 0)
	head.Parent = model
	local hum = Instance.new("Humanoid")
	hum.MaxHealth = 80
	hum.Health = 80
	hum.Parent = model
	model.PrimaryPart = rootPart
	model.Parent = npcFolder
	CollectionService:AddTag(model, TAG_NPC_ENTITY)
end


-- Tutorial markers (best-effort waypoints for TutorialController)
local tutorialFolder = ensureFolder("TutorialMarkers", root)
local function tutorialMarker(name, pos, color, stepId)
	local p = part({
		Name = name,
		Size = Vector3.new(6, 1, 6),
		Position = pos,
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
		Parent = tutorialFolder,
	})
	p:SetAttribute("TutorialStepId", stepId or name)
	CollectionService:AddTag(p, TAG_TUTORIAL)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(140, 28)
	bb.StudsOffset = Vector3.new(0, 4, 0)
	bb.AlwaysOnTop = true
	bb.Parent = p
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = "TUT: " .. name
	t.TextColor3 = Color3.new(1, 1, 0.8)
	t.TextScaled = true
	t.Font = Enum.Font.GothamBold
	t.Parent = bb
	return p
end

local plot1 = PLOT_POSITIONS[1]
tutorialMarker("Tutorial_ClaimBase", plot1 + Vector3.new(0, 2, 28), Color3.fromRGB(230, 200, 80), "ClaimBase")
tutorialMarker("Tutorial_CommandCenter", plot1 + Vector3.new(-24, 3, -24), Color3.fromRGB(80, 200, 120), "CommandCenter")
tutorialMarker("Tutorial_Income", plot1 + Vector3.new(0, 3, 0), Color3.fromRGB(80, 200, 160), "Income")
tutorialMarker("Tutorial_Barracks", plot1 + Vector3.new(-8, 3, -24), Color3.fromRGB(100, 180, 220), "Barracks")
-- Jeep: near first vehicle spawn if present
local jeepPos = Vector3.new(80, 2, 0)
local vSpawns = CollectionService:GetTagged(TAG_VEHICLE)
if #vSpawns > 0 and vSpawns[1]:IsA("BasePart") then
	jeepPos = vSpawns[1].Position + Vector3.new(0, 2, 0)
end
tutorialMarker("Tutorial_Jeep", jeepPos, Color3.fromRGB(120, 140, 200), "Jeep")
-- Outpost: CentralPlaza
tutorialMarker("Tutorial_Outpost", Vector3.new(0, 3, 0), Color3.fromRGB(200, 120, 80), "Outpost")

print("[WAR EMPIRE] StudioSetup complete: 6 bases, 7 territories+capture zones, tutorial markers, spawn pads under Workspace.WarEmpireSetup")
