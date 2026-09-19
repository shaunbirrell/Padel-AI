--[[
	WAR EMPIRE — Studio command-bar setup script
	Paste into Studio Command Bar and press Enter (once per place).

	Creates:
	- Workspace/WarEmpireSetup/Map (Grass ground)
	- Bases (6 plots) tagged WE_BasePlot + upgrade slots WE_UpgradeSlot
	- Territories (7) tagged WE_Territory + WE_CaptureZone
	- VehicleSpawns / NPCSpawns / EventSpawns
	- Tutorial markers (WE_TutorialMarker)
	- NPC placeholders + neon accent edges / readable BillboardGuis

	Safe to re-run: clears previous WarEmpireSetup folder first.
	Client WorldPromptController attaches ProximityPrompts to these tags at runtime.
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

-- Darker military palette
local COL_GROUND = Color3.fromRGB(34, 48, 32)
local COL_PAD = Color3.fromRGB(42, 48, 52)
local COL_PAD_EDGE = Color3.fromRGB(60, 200, 110)
local COL_SLOT = Color3.fromRGB(28, 34, 32)
local COL_SLOT_EDGE = Color3.fromRGB(80, 220, 140)
local COL_VEHICLE = Color3.fromRGB(48, 62, 78)
local COL_NPC = Color3.fromRGB(88, 42, 42)
local COL_EVENT = Color3.fromRGB(78, 64, 36)

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

local function neonEdge(parentPart: BasePart, color: Color3, thickness: number?)
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

local function billboard(parent: Instance, text: string, size: Vector2, offsetY: number, textColor: Color3?)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Label"
	bb.Size = UDim2.fromOffset(size.X, size.Y)
	bb.StudsOffset = Vector3.new(0, offsetY, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 220
	bb.Parent = parent

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(12, 14, 16)
	backdrop.BackgroundTransparency = 0.25
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

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = backdrop

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

local function beacon(parent: Instance, pos: Vector3, color: Color3, name: string)
	local pole = part({
		Name = name or "Beacon",
		Size = Vector3.new(0.6, 10, 0.6),
		Position = pos + Vector3.new(0, 5, 0),
		Color = color,
		Material = Enum.Material.Metal,
		CanCollide = false,
		Parent = parent,
	})
	local tip = part({
		Name = (name or "Beacon") .. "_Tip",
		Size = Vector3.new(1.4, 1.4, 1.4),
		Position = pos + Vector3.new(0, 11, 0),
		Color = color,
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Ball,
		CanCollide = false,
		Parent = parent,
	})
	return pole, tip
end

-- Root
local root = ensureFolder("WarEmpireSetup", Workspace)

-- Map ground
local map = ensureFolder("Map", root)
part({
	Name = "Ground",
	Size = Vector3.new(900, 1, 900),
	Position = Vector3.new(0, 0, 0),
	Color = COL_GROUND,
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
		Color = COL_PAD,
		Material = Enum.Material.Concrete,
		Parent = plotFolder,
	})
	pad:SetAttribute("PlotId", plotId)
	CollectionService:AddTag(pad, TAG_BASE)
	neonEdge(pad, COL_PAD_EDGE, 0.4)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlayerSpawn"
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Position = pos + Vector3.new(0, 2, 30)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.BrickColor = BrickColor.new("Dark green")
	spawn.Material = Enum.Material.Neon
	spawn.Parent = plotFolder

	billboard(pad, "BASE PLOT " .. plotId .. "  ·  Press E / B", Vector2.new(200, 40), 10, Color3.fromRGB(200, 230, 200))
	beacon(plotFolder, pos + Vector3.new(0, 0, -36), COL_PAD_EDGE, "PlotBeacon")

	-- Upgrade slots in a grid on the pad
	local cols = 4
	for i, structureId in ipairs(STRUCTURES) do
		local col = (i - 1) % cols
		local row = math.floor((i - 1) / cols)
		local offset = Vector3.new(-24 + col * 16, 2, -24 + row * 16)
		local isCC = structureId == "CommandCenter"
		local slot = part({
			Name = structureId,
			Size = Vector3.new(6, 2, 6),
			Position = pos + offset,
			Color = if isCC then Color3.fromRGB(36, 55, 42) else COL_SLOT,
			Transparency = 0.25,
			Material = Enum.Material.Metal,
			Parent = plotFolder,
		})
		slot:SetAttribute("PlotId", plotId)
		slot:SetAttribute("StructureId", structureId)
		slot:SetAttribute("BaseSize", Vector3.new(6, 2, 6))
		CollectionService:AddTag(slot, TAG_SLOT)

		-- Thin neon rim on slot top
		local rim = part({
			Name = structureId .. "_Rim",
			Size = Vector3.new(6.4, 0.25, 6.4),
			Position = pos + offset + Vector3.new(0, 1.2, 0),
			Color = if isCC then Color3.fromRGB(230, 190, 60) else COL_SLOT_EDGE,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Transparency = 0.2,
			Parent = plotFolder,
		})
		rim:SetAttribute("WE_Decor", true)

		billboard(
			slot,
			if isCC then "★ " .. structureId .. " (start here)" else structureId,
			Vector2.new(140, 28),
			3.5,
			if isCC then Color3.fromRGB(255, 220, 120) else Color3.fromRGB(190, 205, 190)
		)
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
		Transparency = 0.4,
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

	billboard(marker, def.Id .. "  [NEUTRAL]  ·  Stand to capture", Vector2.new(220, 40), 8, Color3.new(1, 1, 1))

	-- Soft cylinder ring hint (non-colliding)
	local ring = part({
		Name = def.Id .. "_Ring",
		Size = Vector3.new(diameter + 6, 0.35, diameter + 6),
		Position = def.Pos + Vector3.new(0, 0.25, 0),
		Color = def.Color,
		Transparency = 0.7,
		CanCollide = false,
		Material = Enum.Material.SmoothPlastic,
		Parent = territories,
	})
	ring:SetAttribute("TerritoryId", def.Id)

	beacon(territories, def.Pos, def.Color, def.Id .. "_Beacon")
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
			Material = Enum.Material.Concrete,
			Parent = folder,
		})
		CollectionService:AddTag(p, tag)
		neonEdge(p, color:Lerp(Color3.new(1, 1, 1), 0.35), 0.3)
		local label = if tag == TAG_VEHICLE then "GARAGE PAD · E / G" elseif tag == TAG_NPC then "NPC SPAWN" else "EVENT"
		billboard(p, label, Vector2.new(150, 28), 4, Color3.fromRGB(220, 230, 240))
		if tag == TAG_VEHICLE then
			beacon(folder, pos, Color3.fromRGB(90, 160, 220), name .. i .. "_Beacon")
		end
	end
end

makeSpawnFolder("VehicleSpawns", TAG_VEHICLE, 6, Vector3.new(0, 0, 0), COL_VEHICLE)
makeSpawnFolder("NPCSpawns", TAG_NPC, 8, Vector3.new(100, 0, 100), COL_NPC)
makeSpawnFolder("EventSpawns", TAG_EVENT, 4, Vector3.new(-100, 0, -100), COL_EVENT)

-- Lightweight NPC placeholders near spawn pads (CombatService also spawns at runtime)
local TAG_NPC_ENTITY = "WE_NPC"
local npcFolder = ensureFolder("NPCPlaceholders", root)
for i, spawnPart in ipairs(CollectionService:GetTagged(TAG_NPC)) do
	if i > 4 then
		break
	end
	local model = Instance.new("Model")
	model.Name = "HostileInfantry_" .. i
	model:SetAttribute("NPCId", "studio_npc_" .. i)
	model:SetAttribute("NPCType", "Infantry")
	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(2, 2, 1)
	rootPart.Color = Color3.fromRGB(110, 40, 40)
	rootPart.Material = Enum.Material.Metal
	rootPart.Anchored = true
	rootPart.CanCollide = true
	rootPart.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
	rootPart.Parent = model
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.Color = Color3.fromRGB(130, 55, 55)
	head.Material = Enum.Material.SmoothPlastic
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

-- Tutorial markers
local tutorialFolder = ensureFolder("TutorialMarkers", root)
local function tutorialMarker(name, pos, color, stepId)
	local p = part({
		Name = name,
		Size = Vector3.new(6, 1, 6),
		Position = pos,
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
		CanCollide = false,
		Parent = tutorialFolder,
	})
	p:SetAttribute("TutorialStepId", stepId or name)
	CollectionService:AddTag(p, TAG_TUTORIAL)
	billboard(p, "TUT · " .. name, Vector2.new(180, 32), 5, Color3.fromRGB(255, 245, 180))
	beacon(tutorialFolder, pos, color, name .. "_Beacon")
	return p
end

local plot1 = PLOT_POSITIONS[1]
tutorialMarker("Tutorial_ClaimBase", plot1 + Vector3.new(0, 2, 28), Color3.fromRGB(230, 200, 80), "ClaimBase")
tutorialMarker("Tutorial_CommandCenter", plot1 + Vector3.new(-24, 3, -24), Color3.fromRGB(80, 200, 120), "CommandCenter")
tutorialMarker("Tutorial_Income", plot1 + Vector3.new(0, 3, 0), Color3.fromRGB(80, 200, 160), "Income")
tutorialMarker("Tutorial_Barracks", plot1 + Vector3.new(-8, 3, -24), Color3.fromRGB(100, 180, 220), "Barracks")
local jeepPos = Vector3.new(80, 2, 0)
local vSpawns = CollectionService:GetTagged(TAG_VEHICLE)
if #vSpawns > 0 and vSpawns[1]:IsA("BasePart") then
	jeepPos = vSpawns[1].Position + Vector3.new(0, 2, 0)
end
tutorialMarker("Tutorial_Jeep", jeepPos, Color3.fromRGB(120, 140, 200), "Jeep")
tutorialMarker("Tutorial_Outpost", Vector3.new(0, 3, 0), Color3.fromRGB(200, 120, 80), "Outpost")

print("[WAR EMPIRE] StudioSetup complete: polished placeholders, beacons, billboards under Workspace.WarEmpireSetup")
print("[WAR EMPIRE] Tip: Lighting → Ambient ~ (80,90,70), Brightness 2, ClockTime 14 for clearer military look.")
