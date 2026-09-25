--!strict
--[[
	WAR EMPIRE — MapSetup (shared world build)
	Builds Workspace.WarEmpireSetup: map, plots, structure kits, territories,
	spawns, tutorial markers, MapDressing + DesertFlora.
	Called from Bootstrap when WarEmpireSetup is missing (Play Solo / server start).
	Admin `resetmap` destroys WarEmpireSetup and re-runs.
	World v2 W1 (gap/world_v2_spec.md §1.6 / §3.3–§3.5, roadmap §2.2 WORLD-A): WorldAtmosphere owns the lighting,
	WorldBounds builds the skyline / ground and air walls / seabed tint / far shore, WorldTerrain fills the canyon edge
	(each call guarded: a failure never stops the map build). The mesa Part ring, the ground fill patches, the 20 static
	soldier statues, the "OIL FIELD" pads and the grey landmark hosts are gone. Spawns come from WorldConfig.Spawns:
	10 painted garage pads (6 outside the front gates, the only ones with a "Garage" sign), invisible NPC / event
	anchors, no beacons, no Neon.
	W3 step 2 lane BK: the Empire Bank is a walk-in hall (buildEmpireBank: 17 parts, the open BankGate, the StateBanner,
	the Town.Bank.* activity anchors on BankPlaza).
	streaming2 S4 (spec streaming2 §1, F11 / F12 / F24): ModelStreamingMode Atomic, always set before the Model is
	parented, on the static soldier rigs (makeSoldierKit), the Empire Bank (one Model "EmpireBank") and one Model per
	capture zone (Territories.<Id>_Zone: the marker, _Ring, _FlagPole, _Flag and, off the Home Outposts, _FlagStripe
	and _Finial; fort walls / keep / towers and rig decks / legs / piers stay loose). Plots stay Folders. Inert while
	Workspace.StreamingEnabled is false (the default.project.json switch): the same parts, only grouped.
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
local MonetizationConfig = require(SharedConfigs:WaitForChild("MonetizationConfig"))
local StructureVisualConfig = require(SharedConfigs:WaitForChild("StructureVisualConfig"))
local BaseLayout = require(script.Parent:WaitForChild("BaseLayout"))
-- v70 waterways: plot water, sea gates, naval pads, road ends, rig piers (public water = Modules.Waterways)
local WaterConfig = require(SharedConfigs:WaitForChild("WaterConfig"))
-- v70 (HUD spec §5): every floating label goes through the shared helper (stud-scaled, 14-20 px, MaxDistance <= 40)
local WorldLabel = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("WorldLabel"))
-- World v2: spawn pads / anchors (Spawns) and the SafetyCatch look (Bounds.SafetyCatch)
local WorldConfig = require(SharedConfigs:WaitForChild("WorldConfig"))
-- F10 (owner's 11 features): the capture zones (incl. the Home Outposts) are TerritoryConfig's rows
-- (ReplicatedStorage.Shared ships with the place and replicates before any server script runs: no wait needed)
local TerritoryConfig = require(ReplicatedStorage.Shared.Configs.TerritoryConfig)

local TAG_BASE = "WE_BasePlot"
local TAG_SLOT = "WE_UpgradeSlot"
local TAG_TERRITORY = "WE_Territory"
local TAG_CAPTURE = "WE_CaptureZone"
local TAG_VEHICLE = "WE_VehicleSpawn"
local TAG_WATER = "WE_Water" -- v69: boats sail on WE_Water surfaces (Constants.Tags.Water)
local TAG_NAVAL = "WE_NavalSpawn"
local TAG_NPC = "WE_NPCSpawn"
local TAG_EVENT = "WE_EventSpawn"
local TAG_TUTORIAL = "WE_TutorialMarker"
local TAG_NPC_ENTITY = "WE_NPC"
local TAG_COLLECTOR = "WE_MoneyCollector"
local TAG_PREMIUM = "WE_PremiumPad"

local COL_GROUND = Color3.fromRGB(210, 185, 130) -- pale sandy-yellow desert floor
-- v67 base look: light concrete plot floor + painted olive edge (was near-black navy + green Neon)
local BASE_LOOK = (StructureVisualConfig :: any).BaseLook or {}
local COL_PAD = BASE_LOOK.PlotFloor or Color3.fromRGB(168, 162, 148)
local COL_PAD_EDGE = BASE_LOOK.PlotEdge or Color3.fromRGB(86, 98, 64)
local COL_CHEVRON = BASE_LOOK.Chevron or Color3.fromRGB(230, 196, 70)
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

-- Map scale: ground ≥6000 continuous floor, plot ring ~800, pads ~200
-- Top of Ground sits ~Y=0.5 so plot pads (Y=0.5) sit flush.
local GROUND_SIZE = 7200
local GROUND_THICKNESS = 8
local GROUND_TOP_Y = 0.5
local SAFETY_FLOOR_SIZE = 10000
local SAFETY_FLOOR_Y = -28
-- v70 (spec_final §12.1): Roblox caps a BasePart at 2048 studs per axis, so the 7200 floor, the 10000 safety catch
-- and the 7200 berms / void walls are TILED (shared edges, no overlap → no z-fight). Ground: 4 x 4 tiles of 1800.
local GROUND_TILES_PER_SIDE = 4 -- 7200 / 4 = 1800 per ground tile
local SAFETY_TILES_PER_SIDE = 5 -- 10000 / 5 = 2000 per safety-catch tile
local EDGE_PIECES = 4 -- EdgeBerm* (7120 / 4 = 1780) / VoidWall* (7200 / 4 = 1800) pieces per side
local PLOT_PAD_SIZE = BaseLayout.PlotSize(200) -- v68: BaseLayoutConfig.PlotSize (320) when the layout is on
local PLOT_RING = 800
local PLOT_SPAWN_CLEARANCE = 40 -- v68: vehicle / NPC / event spawn pads stay this far outside plot edges
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

-- World v2 (spec §3.4): each fort's wall toward its nearest road has a 16-wide gate (GateSide = the gated wall)
local FORT_GATE_WIDTH = 16

-- F10 (owner's 11 features, lane W): the capture zones come from TerritoryConfig.Territories (one source: position,
-- radius, colour, oil rig / fortress). MapSetup keeps only what is its own: the build order of the original eleven
-- (so their parts are made in the same order as before) and each fort's gate wall. Any other row (the Home Outposts
-- Starter_P1..P6 while TerritoryConfig.Starter.Enabled) is built after them, sorted by id.
local TERRITORY_BUILD_ORDER = {
	"CentralPlaza",
	"NorthRidge",
	"SouthDocks",
	"EastArmory",
	"WestDepot",
	"OilFields",
	"RadarHill",
	"CoastalOilAlpha", -- coastal oil decks (Y = the TerritoryConfig / OilRigConfig platform height)
	"CoastalOilBravo",
	"FortIronclad",
	"FortSandhold",
}
-- World v2 (spec §3.4): the fort wall facing the nearest road has the gate (1 = +Z wall, -1 = -Z wall)
local FORT_GATE_SIDE: { [string]: number } = {
	FortIronclad = 1, -- toward RoadZ-800
	FortSandhold = -1, -- toward RoadZ800
}

-- Ordered TerritoryConfig rows to build (every row exactly once)
local function territoryDefsInBuildOrder(): { TerritoryConfig.TerritoryDef }
	local rows = TerritoryConfig.Territories
	local out: { TerritoryConfig.TerritoryDef } = {}
	local seen: { [string]: boolean } = {}
	for _, id in ipairs(TERRITORY_BUILD_ORDER) do
		local def = rows[id]
		if def then
			table.insert(out, def)
			seen[id] = true
		end
	end
	local rest: { string } = {}
	for id in pairs(rows) do
		if not seen[id] then
			table.insert(rest, id)
		end
	end
	table.sort(rest)
	for _, id in ipairs(rest) do
		table.insert(out, rows[id])
	end
	return out
end

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

local function siteFrameOf(plinth: BasePart): CFrame
	local cf = plinth:GetAttribute("WE_SiteCFrame")
	if typeof(cf) == "CFrame" then
		return cf
	end
	return plinth.CFrame
end

local function kitPart(parentPlinth, role, size, localOffset, color, material, shape)
	local p = part({
		Name = role,
		Size = size,
		CFrame = siteFrameOf(parentPlinth) * CFrame.new(localOffset),
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

-- World v2 W1: the Neon kerb edge (neonEdge) is gone: nothing outside the bases glows; paintEdge below is the one edge

-- v67: painted kerb edge (no glow)
local function paintEdge(parentPart, color, thickness)
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
			Material = Enum.Material.Concrete,
			CanCollide = false,
			Parent = parentPart.Parent,
		})
		edge:SetAttribute("WE_Decor", true)
	end
end

-- v70 (HUD spec §5): no server price card on the consoles (the client draws the owner's own price tag); the old
-- always-on dark card per console is gone.

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

-- World v2 W1 (spec §5.2 row 2) / W3 step 2 lane BK: no beacon pole anywhere outside the bases (the bank's was the
-- last one; its roof StateBanner and the EMPIRE BANK sign mark it now), so the beacon helper is gone.

-- v68: terminal look for console-mode upgrade slots (screen + button); decoration only, not kit roles
local function dressConsole(plinth, title)
	local screen = part({
		Name = "ConsoleScreen",
		Size = Vector3.new(2.3, 1.3, 0.16),
		CFrame = plinth.CFrame * CFrame.new(0, BaseLayout.CONSOLE_SIZE.Y * 0.5 + 0.45, -0.25) * CFrame.Angles(math.rad(20), 0, 0),
		Color = Color3.fromRGB(14, 22, 16),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = plinth,
	})
	screen:SetAttribute("WE_Decor", true)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "WE_ConsoleScreen"
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 60
	sg.LightInfluence = 0
	sg.MaxDistance = 40 -- v70: SurfaceGuis draw near-only (CLAUDE.md budget, <= 80)
	sg.Parent = screen
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundColor3 = Color3.fromRGB(10, 26, 16)
	lbl.BorderSizePixel = 0
	lbl.Font = Enum.Font.GothamBold
	lbl.TextScaled = true
	lbl.TextColor3 = Color3.fromRGB(120, 255, 150)
	lbl.Text = string.upper(title) .. "\nBUILD / UPGRADE"
	lbl.Parent = sg
	local button = part({
		Name = "ConsoleButton",
		Size = Vector3.new(0.5, 0.2, 0.5),
		CFrame = plinth.CFrame * CFrame.new(0.8, BaseLayout.CONSOLE_SIZE.Y * 0.5 + 0.1, -0.35),
		Color = Color3.fromRGB(90, 255, 120),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = plinth,
	})
	button:SetAttribute("WE_Decor", true)
end

local function buildStructureKit(plotFolder, plotId, pos, offset, def)
	local plinthSize = Vector3.new(8, 1.2, 8)
	-- v68: with BaseLayoutConfig the upgrade slot is a console / kiosk and the kit or walk-in building
	-- stands at its site (WE_SiteCFrame). Buying happens at the console by prompt / tap only.
	local consoleCF = BaseLayout.ConsoleCFrame(pos, def.Id)
	local siteCF = BaseLayout.SiteCFrame(pos, def.Id)
	local isConsole = consoleCF ~= nil and siteCF ~= nil
	if isConsole then
		plinthSize = BaseLayout.CONSOLE_SIZE
	end
	local plinth = part({
		Name = def.Id,
		Size = plinthSize,
		-- legacy grid slot (layout off): plot-local offset through the plot frame (v70)
		Position = if isConsole then (consoleCF :: CFrame).Position else BaseLayout.PlotCFrame(pos):PointToWorldSpace(offset),
		Color = if isConsole then Color3.fromRGB(46, 50, 48) else def.Plinth,
		Transparency = if isConsole then 0 else 0.32,
		Material = if isConsole then Enum.Material.Metal else Enum.Material.Concrete,
		CanCollide = true,
		Parent = plotFolder,
	})
	if isConsole then
		plinth.CFrame = consoleCF :: CFrame
		plinth:SetAttribute("WE_Console", true)
		plinth:SetAttribute("WE_SiteCFrame", siteCF)
	end
	plinth.CanTouch = not isConsole -- legacy walk-over pads only
	plinth:SetAttribute("PlotId", plotId)
	plinth:SetAttribute("StructureId", def.Id)
	plinth:SetAttribute("BaseSize", plinthSize)
	CollectionService:AddTag(plinth, TAG_SLOT)

	local kit = def.Kit
	-- Visual kits v2: distinct silhouettes, painted accents (v70: no Neon), doors/windows (modest part count)
	if kit == "hq" then
		kitPart(plinth, "Body", Vector3.new(5.5, 3.4, 5.5), Vector3.new(0, 2.3, 0), def.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(6.4, 0.55, 6.4), Vector3.new(0, 4.3, 0), def.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Antenna", Vector3.new(0.35, 4.8, 0.35), Vector3.new(1.8, 6.8, 1.8), def.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Accent", Vector3.new(6.6, 0.22, 6.6), Vector3.new(0, 0.72, 0), def.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Detail", Vector3.new(1.1, 1.1, 1.1), Vector3.new(-2, 3.6, -2), def.Accent, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		kitPart(plinth, "Door", Vector3.new(1.6, 2.2, 0.25), Vector3.new(0, 1.7, -2.85), Color3.fromRGB(30, 35, 32), Enum.Material.Metal, nil)
		kitPart(plinth, "Window", Vector3.new(1.4, 1.0, 0.2), Vector3.new(2.0, 2.6, -2.8), Color3.fromRGB(70, 120, 150), Enum.Material.Glass, nil)
	elseif kit == "barracks" then
		kitPart(plinth, "Body", Vector3.new(6.6, 2.6, 4.4), Vector3.new(0, 1.9, 0), def.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(7.1, 0.5, 5.0), Vector3.new(0, 3.35, 0), def.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(6.9, 0.18, 4.7), Vector3.new(0, 0.7, 0), def.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Door", Vector3.new(1.4, 2.0, 0.25), Vector3.new(0, 1.6, -2.3), Color3.fromRGB(35, 40, 32), Enum.Material.Metal, nil)
		kitPart(plinth, "Window", Vector3.new(1.2, 0.9, 0.2), Vector3.new(-2.2, 2.3, -2.25), Color3.fromRGB(70, 120, 140), Enum.Material.Glass, nil)
		kitPart(plinth, "Detail", Vector3.new(0.7, 1.8, 0.7), Vector3.new(-3.0, 2.3, 1.5), def.Accent, Enum.Material.SmoothPlastic, nil)
	elseif kit == "depot" then
		kitPart(plinth, "Body", Vector3.new(6.9, 2.2, 5.6), Vector3.new(0, 1.7, 0), def.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(7.3, 0.4, 6.1), Vector3.new(0, 2.95, 0), def.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(3.2, 0.28, 5.9), Vector3.new(0, 0.72, 0), def.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Door", Vector3.new(2.8, 2.0, 0.3), Vector3.new(0, 1.6, -2.9), Color3.fromRGB(40, 50, 60), Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(1.0, 1.0, 1.0), Vector3.new(2.8, 2.4, 2.0), def.Accent, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	elseif kit == "lab" then
		kitPart(plinth, "Body", Vector3.new(5.1, 3.2, 5.1), Vector3.new(0, 2.2, 0), def.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(5.5, 0.5, 5.5), Vector3.new(0, 4.0, 0), def.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Antenna", Vector3.new(0.4, 3.8, 0.4), Vector3.new(0, 6.1, 0), def.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Accent", Vector3.new(5.7, 0.2, 5.7), Vector3.new(0, 0.7, 0), def.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Window", Vector3.new(1.5, 1.2, 0.2), Vector3.new(0, 2.6, -2.6), Color3.fromRGB(80, 160, 200), Enum.Material.Glass, nil)
		kitPart(plinth, "Detail", Vector3.new(0.9, 0.9, 0.9), Vector3.new(2.0, 3.5, 2.0), def.Accent, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	elseif kit == "tower" then
		kitPart(plinth, "Body", Vector3.new(2.9, 5.8, 2.9), Vector3.new(0, 3.5, 0), def.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(3.8, 0.5, 3.8), Vector3.new(0, 6.6, 0), def.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Antenna", Vector3.new(0.3, 3.5, 0.3), Vector3.new(0, 8.5, 0), def.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Accent", Vector3.new(3.3, 0.22, 3.3), Vector3.new(0, 0.7, 0), def.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Window", Vector3.new(1.0, 0.8, 0.2), Vector3.new(0, 4.5, -1.5), Color3.fromRGB(90, 140, 180), Enum.Material.Glass, nil)
		kitPart(plinth, "Detail", Vector3.new(0.7, 0.7, 0.7), Vector3.new(0, 7.0, 0), def.Accent, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	elseif kit == "dock" then
		kitPart(plinth, "Body", Vector3.new(7.5, 0.55, 7.5), Vector3.new(0, 0.9, 0), def.Body, Enum.Material.Concrete, nil)
		kitPart(plinth, "Pier", Vector3.new(8.8, 0.4, 2.4), Vector3.new(0, 1.15, 3.3), def.Roof, Enum.Material.Wood, nil)
		kitPart(plinth, "Accent", Vector3.new(7.2, 0.14, 0.4), Vector3.new(0, 1.25, 0), def.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Detail", Vector3.new(1.2, 2.8, 0.4), Vector3.new(3.3, 2.1, 2.6), def.Accent, Enum.Material.Metal, nil)
		kitPart(plinth, "Door", Vector3.new(1.8, 0.3, 1.2), Vector3.new(0, 1.35, 4.2), Color3.fromRGB(40, 55, 70), Enum.Material.Metal, nil)
	elseif kit == "pad" then
		kitPart(plinth, "Body", Vector3.new(7.3, 0.45, 7.3), Vector3.new(0, 0.92, 0), def.Body, Enum.Material.Concrete, nil)
		kitPart(plinth, "Accent", Vector3.new(6.6, 0.14, 0.5), Vector3.new(0, 1.18, 0), def.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Detail", Vector3.new(0.5, 0.14, 6.6), Vector3.new(0, 1.18, 0), def.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Roof", Vector3.new(1.6, 0.3, 1.6), Vector3.new(0, 1.35, 0), def.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Window", Vector3.new(0.5, 0.5, 0.5), Vector3.new(2.8, 1.4, 2.8), def.Accent, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	elseif kit == "wall" then
		kitPart(plinth, "Body", Vector3.new(7.5, 3.0, 1.5), Vector3.new(0, 2.1, 0), def.Body, Enum.Material.Concrete, nil)
		kitPart(plinth, "Accent", Vector3.new(7.7, 0.25, 1.7), Vector3.new(0, 3.7, 0), def.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Roof", Vector3.new(7.5, 0.4, 1.9), Vector3.new(0, 3.9, 0), def.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(0.8, 1.2, 0.8), Vector3.new(-3.2, 3.2, 0), def.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Detail", Vector3.new(0.8, 1.2, 0.8), Vector3.new(3.2, 3.2, 0), def.Accent, Enum.Material.SmoothPlastic, nil)
	elseif kit == "power" then
		kitPart(plinth, "Body", Vector3.new(4.6, 3.6, 4.6), Vector3.new(0, 2.5, 0), def.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(2.3, 2.3, 2.3), Vector3.new(0, 4.7, 0), def.Accent, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		kitPart(plinth, "Roof", Vector3.new(5.1, 0.4, 5.1), Vector3.new(0, 4.4, 0), def.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(0.6, 2.5, 0.6), Vector3.new(2.0, 2.8, 2.0), Color3.fromRGB(60, 55, 40), Enum.Material.Metal, nil)
	elseif kit == "warehouse" then
		kitPart(plinth, "Body", Vector3.new(7.1, 2.8, 5.6), Vector3.new(0, 2.0, 0), def.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(7.5, 0.5, 6.1), Vector3.new(0, 3.55, 0), def.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(7.3, 0.2, 5.9), Vector3.new(0, 0.7, 0), def.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Door", Vector3.new(2.6, 2.2, 0.3), Vector3.new(0, 1.7, -2.95), Color3.fromRGB(50, 45, 38), Enum.Material.Metal, nil)
	else
		kitPart(plinth, "Body", Vector3.new(5.3, 3.5, 5.3), Vector3.new(0, 2.4, 0), def.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(4.2, 1.2, 4.2), Vector3.new(0, 4.6, 0), def.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Antenna", Vector3.new(0.35, 4.2, 0.35), Vector3.new(0, 7.2, 0), def.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Accent", Vector3.new(5.9, 0.22, 5.9), Vector3.new(0, 0.7, 0), def.Accent, Enum.Material.SmoothPlastic, nil)
		kitPart(plinth, "Detail", Vector3.new(1.0, 1.0, 1.0), Vector3.new(2.0, 3.5, -2.0), def.Accent, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	end

	-- Readable DisplayName for the console screen (the client's owner-only price tag uses BaseConfig names)
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
	if isConsole then
		dressConsole(plinth, nice)
		-- v68: no catalog building mesh on a console (it would be placed at the console, not the site)
		return plinth
	end
	-- Optional catalog building visual — ALWAYS deferred (InsertService must never block pads/remotes)
	task.defer(function()
		pcall(function()
			local vas = require(script.Parent.Parent.Services.VisualAssetService)
			if vas and vas.TryAttachBuildingVisual then
				vas.TryAttachBuildingVisual(plinth, def.Id)
			end
		end)
	end)
	return plinth
end



-- Desert camo infantry Part kit — vest / helmet / shemagh accents, clearer rifle
local function makeSoldierKit(parentFolder, name, cf: CFrame, bodyColor, labelText: string?, labelColor, health, npcType, npcId)
	-- Visual props for Training Yard / static kits. R15-ready catalog overlay via VisualAssetConfig;
	-- Part-kit military placeholder (R6-ish ~5 stud) when mesh IDs missing / StudioSkipWorldDressing.
	-- Live combat NPCs use CombatService.SpawnNPC (BankGuard etc.).
	-- v72 budget: StructureVisualConfig.StaticSoldierDetail = false drops the 7 small detail parts (Shemagh, VestPouch,
	-- BootL/R, RifleStock, RifleBarrel, Accent): 9 parts per static soldier (Pack adds 1 for Heavy). No other code welds
	-- or looks up these names on a static kit.
	local detail = (StructureVisualConfig :: any).StaticSoldierDetail ~= false
	local model = Instance.new("Model")
	-- streaming2 S4 (F11): a static rig (parts, Humanoid, catalog visual) reaches a client whole or not at all. Set
	-- before the model is parented (it is filled first, parented below). No effect with streaming off.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
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
	-- R6 torso = 2×2×1. fb2: callers pass cf = floor top + 2.1 (the torso centre), but the legs hang 3 below the torso
	-- centre, so every static soldier stood 0.9-1.1 studs sunk into the floor. Lift the torso 0.9: the leg bottoms (and
	-- the boots, when StaticSoldierDetail is on) sit on the floor, and a catalog overlay pivoted to the HRP stands too.
	local torso = part({
		Name = "HumanoidRootPart",
		Size = Vector3.new(2, 2, 1),
		Color = camo,
		Material = Enum.Material.Fabric,
		Anchored = true,
		CanCollide = true,
		CFrame = cf * CFrame.new(0, 0.9, 0),
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
	-- fb2: domed steel helmet (was a flat 1.2 x 0.5 box cap). The SpecialMesh sphere fills the part's box, so the dome
	-- covers the top of the head with a small brim; a SpecialMesh is not a part (0 extra parts per soldier).
	local helmet = part({
		Name = "Helmet",
		Size = Vector3.new(1.3, 0.75, 1.35),
		Color = helmCol,
		Material = Enum.Material.Metal,
		Anchored = true,
		CanCollide = false,
		CFrame = head.CFrame * CFrame.new(0, 0.36, 0.02),
		Parent = model,
	})
	local dome = Instance.new("SpecialMesh")
	dome.MeshType = Enum.MeshType.Sphere
	dome.Parent = helmet
	if detail then
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
	end
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
	if detail then
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
	end
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
	if detail then
		part({
			Name = "BootL",
			Size = Vector3.new(1.05, 0.35, 1.15),
			Color = Color3.fromRGB(35, 32, 28),
			Material = Enum.Material.SmoothPlastic,
			Anchored = true,
			CanCollide = false,
			CFrame = torso.CFrame * CFrame.new(-0.5, -2.825, 0.1), -- fb2: boot bottom = leg bottom (was 0.275 lower)
			Parent = model,
		})
	end
	if detail then
		part({
			Name = "BootR",
			Size = Vector3.new(1.05, 0.35, 1.15),
			Color = Color3.fromRGB(35, 32, 28),
			Material = Enum.Material.SmoothPlastic,
			Anchored = true,
			CanCollide = false,
			CFrame = torso.CFrame * CFrame.new(0.5, -2.825, 0.1), -- fb2: boot bottom = leg bottom (was 0.275 lower)
			Parent = model,
		})
	end
	if detail then
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
	end
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
	if detail then
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
	end
	if detail then
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
	end
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

-- v70 (spec_final §12.1): tiled floor layers. Every tile is <= 2000 studs per axis; neighbours share edges exactly.
type TileSpec = { Name: string, At: Vector3, Size: Vector3 }
type TileLook = { Color: Color3, Material: Enum.Material, Transparency: number }

-- centres of n equal tiles of size t that together span n * t, centred on 0
local function tileCentres(n: number, t: number): { number }
	local out: { number } = {}
	for i = 1, n do
		table.insert(out, (i - 0.5) * t - n * t * 0.5)
	end
	return out
end

-- One shared heal path (MapSetup.Run, EnsureGroundHealthy, ForceRebuildGround): build every missing tile and
-- re-assert size / position / collide on the rest (a legacy untiled part with a tile's name is resized to that tile).
-- Returns (tile count, repaired).
local function healTileSet(mapFolder: Instance, specs: { TileSpec }, look: TileLook): (number, boolean)
	local repaired = false
	for _, t in ipairs(specs) do
		local existing = mapFolder:FindFirstChild(t.Name)
		if existing and existing:IsA("BasePart") then
			if existing.Size ~= t.Size or (existing.Position - t.At).Magnitude > 0.01 or existing.CanCollide ~= true or existing.Anchored ~= true then
				repaired = true
			end
			existing.Size = t.Size
			existing.CFrame = CFrame.new(t.At)
			existing.CanCollide = true
			existing.Anchored = true
			existing.Color = look.Color
			existing.Material = look.Material
			existing.Transparency = look.Transparency
		else
			if existing then
				existing:Destroy()
			end
			part({
				Name = t.Name,
				Size = t.Size,
				Position = t.At,
				Color = look.Color,
				Material = look.Material,
				Transparency = look.Transparency,
				CanCollide = true,
				Anchored = true,
				Parent = mapFolder,
			})
			repaired = true
		end
	end
	return #specs, repaired
end

-- destroy the part named `base` and every "<base>_..." piece
local function destroyNamed(mapFolder: Instance, base: string)
	for _, ch in ipairs(mapFolder:GetChildren()) do
		if ch.Name == base or string.sub(ch.Name, 1, #base + 1) == base .. "_" then
			ch:Destroy()
		end
	end
end

-- Ground: 4 x 4 tiles of 1800 x 8 x 1800, top at GROUND_TOP_Y. The tile centred at (-900, -900) keeps the name
-- "Ground" (Bootstrap and the heal checks read Map.Ground); the others are GroundTile_<i>_<j>.
local function groundTileSpecs(): { TileSpec }
	local out: { TileSpec } = {}
	local tile = GROUND_SIZE / GROUND_TILES_PER_SIDE
	local cs = tileCentres(GROUND_TILES_PER_SIDE, tile)
	for i, x in ipairs(cs) do
		for j, z in ipairs(cs) do
			local name = if x == -tile * 0.5 and z == -tile * 0.5 then "Ground" else ("GroundTile_" .. i .. "_" .. j)
			table.insert(out, { Name = name, At = Vector3.new(x, groundCenterY(), z), Size = Vector3.new(tile, GROUND_THICKNESS, tile) })
		end
	end
	return out
end

local function buildGroundTiles(mapFolder: Instance): (number, boolean)
	return healTileSet(mapFolder, groundTileSpecs(), { Color = COL_GROUND, Material = Enum.Material.Sand, Transparency = 0 })
end

-- number of ground tiles that exist, collide and have full tile size (Bootstrap health check)
local function countHealthyGroundTiles(mapFolder: Instance): number
	local n = 0
	for _, t in ipairs(groundTileSpecs()) do
		local p = mapFolder:FindFirstChild(t.Name)
		if p and p:IsA("BasePart") and p.CanCollide and p.Size.X >= t.Size.X - 1 and p.Size.Z >= t.Size.Z - 1 then
			n += 1
		end
	end
	return n
end

-- SafetyCatch: 5 x 5 tiles of 2000 (the centre one keeps the name SafetyCatch)
local function buildSafetyUnderfloor(mapFolder: Instance): (number, boolean)
	local specs: { TileSpec } = {}
	local tile = SAFETY_FLOOR_SIZE / SAFETY_TILES_PER_SIDE
	for i, x in ipairs(tileCentres(SAFETY_TILES_PER_SIDE, tile)) do
		for j, z in ipairs(tileCentres(SAFETY_TILES_PER_SIDE, tile)) do
			local name = if x == 0 and z == 0 then "SafetyCatch" else ("SafetyCatch_" .. i .. "_" .. j)
			table.insert(specs, { Name = name, At = Vector3.new(x, SAFETY_FLOOR_Y, z), Size = Vector3.new(tile, 4, tile) })
		end
	end
	-- World v2 (spec §1.4): opaque sand (was Slate, Transparency 0.92), so a ray that clears the skyline meets a
	-- sand-coloured plain instead of the void; an opaque floor is also cheaper to draw on phones
	local look = WorldConfig.Bounds.SafetyCatch
	return healTileSet(mapFolder, specs, { Color = look.Color, Material = look.Material, Transparency = look.Transparency })
end

-- one ring side = EDGE_PIECES pieces: <prefix><N|S|E|W> (first piece keeps the legacy name), then _2 .. _4
local function edgeRingSpecs(prefix: string, inset: number, length: number, height: number, thick: number, y: number): { TileSpec }
	local out: { TileSpec } = {}
	local half = GROUND_SIZE * 0.5 - inset
	local piece = length / EDGE_PIECES
	for _, side in ipairs({ "N", "S", "E", "W" }) do
		local alongX = side == "N" or side == "S"
		local sgn = if side == "N" or side == "W" then -1 else 1
		for k, c in ipairs(tileCentres(EDGE_PIECES, piece)) do
			table.insert(out, {
				Name = prefix .. side .. (if k == 1 then "" else ("_" .. k)),
				At = if alongX then Vector3.new(c, y, sgn * half) else Vector3.new(sgn * half, y, c),
				Size = if alongX then Vector3.new(piece, height, thick) else Vector3.new(thick, height, piece),
			})
		end
	end
	return out
end

local function buildEdgeBerms(mapFolder: Instance): (number, boolean)
	-- Soft inner berm just inside Ground edge (keeps stroll-off from feeling like cliff)
	local bermH = 18
	local specs = edgeRingSpecs("EdgeBerm", 40, GROUND_SIZE - 80, bermH, 28, GROUND_TOP_Y + bermH * 0.5)
	return healTileSet(mapFolder, specs, { Color = Color3.fromRGB(185, 155, 105), Material = Enum.Material.Sand, Transparency = 0 })
end


local function buildInvisibleWalls(mapFolder: Instance): (number, boolean)
	-- Tall invisible perimeter so players cannot walk off Ground into void/water
	local wallH = 80
	local specs = edgeRingSpecs("VoidWall", 8, GROUND_SIZE, wallH, 12, GROUND_TOP_Y + wallH * 0.5)
	return healTileSet(mapFolder, specs, { Color = Color3.fromRGB(40, 50, 40), Material = Enum.Material.SmoothPlastic, Transparency = 1 })
end

-- World v2 W1 (spec §1.6): buildMountainRing (the 14-mesa Part ring past the berm) and buildVisualFillPatches are
-- gone. The edge is WorldTerrain (Terrain canyon) + WorldBounds (skyline, walls, far shore); Phase 2 paints ground patches
-- as Terrain.

local function buildOilDeckRamp(parent: Folder, territoryId: string, deckPos: Vector3, towardCenter: Vector3)
	--[[
		Stepped collide stairs from elevated oil deck (~Y=28) down to ground.
		towardCenter = horizontal direction from deck toward map center (inland).
		v70: the stairs now really run toward towardCenter (they subtracted dir, so they ran out to sea); on the
		waterways map they are the rig's pier across the lagoon to the inner bank (spec_final §7.1).
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
	local edge = Vector3.new(deckPos.X, 0, deckPos.Z) + dir * 26
	for s = 1, steps do
		local y = deckTopY - rise * s + 0.6
		local horiz = edge + dir * (run * s)
		local stepAt = Vector3.new(horiz.X, y, horiz.Z)
		part({
			Name = territoryId .. "_RampStep" .. s,
			Size = Vector3.new(stepW, 1.3, stepT),
			CFrame = CFrame.lookAt(stepAt, stepAt + dir),
			Color = Color3.fromRGB(75, 78, 82),
			Material = Enum.Material.Metal,
			CanCollide = true,
			Anchored = true,
			Parent = parent,
		})
	end
	local midHoriz = edge + dir * (run * 5)
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
	local approach = edge + dir * (run * steps + 10)
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
-- v70: the ground is tiled (§12.1); Bootstrap checks the tiles, not one 7200 part
MapSetup.GROUND_TILE_SIZE = GROUND_SIZE / GROUND_TILES_PER_SIDE
MapSetup.GROUND_TILES = GROUND_TILES_PER_SIDE * GROUND_TILES_PER_SIDE
-- v70: stamped on WarEmpireSetup (WE_MapGen). Bootstrap rebuilds a saved / baked map whose stamp differs, so a place
-- saved with an older layout (unturned plots, one WaterPlane) never keeps it. The stamp also encodes
-- BaseLayoutConfig.FaceMapCentre (even = off, odd = on), so flipping the flag rebuilds a map baked with the other value.
-- World v2 W1: 70/71 → 80/81, so a saved map with the mesa ring, statues, beacons and old spawn rings is rebuilt.
-- F1 / F10 (owner's 11 features): 80/81 → 82/83 (the ATM pads follow MonetizationConfig.PremiumPads: no VIP pad), and
-- +10 while TerritoryConfig.Starter.Enabled (the 6 Home Outpost kits), so flipping that flag also rebuilds a baked map.
-- +10 keeps the FaceMapCentre parity (even = off, odd = on).
MapSetup.MAP_GEN = (if BaseLayout.FacesMapCentre() then 83 else 82) + (if TerritoryConfig.Starter.Enabled then 10 else 0)

-- v70: healthy ground tiles under setup.Map (Bootstrap "Ground AFTER heal" check)
function MapSetup.CountGroundTiles(setup: Instance): number
	local map = setup:FindFirstChild("Map")
	if not map then
		return 0
	end
	return countHealthyGroundTiles(map)
end

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
		-- v68: consoles stand on the plot floor; their height is not an air gap to fill
		if inst:IsA("BasePart") and inst:IsDescendantOf(setup) and inst:GetAttribute("WE_Console") ~= true then
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
				if typeof(sid) == "string" and desc:GetAttribute("WE_Console") ~= true then
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
		v70: re-asserts all 16 ground tiles, the 25 safety-catch tiles and every berm / void-wall piece (a legacy
		single 7200 Ground is resized to its tile and the missing tiles are built).
	]]
	local map = setup:FindFirstChild("Map")
	if not map then
		return false
	end
	local ground = map:FindFirstChild("Ground")
	if not (ground and ground:IsA("BasePart")) then
		return false
	end
	-- Always force full-size collide Ground every Play (bulletproof void floor)
	local tiles, repaired = buildGroundTiles(map)
	local _, catchRepaired = buildSafetyUnderfloor(map)
	repaired = repaired or catchRepaired

	-- World v2 W1: no Part mountain ring to heal any more (the edge is Terrain + WorldBounds, rebuilt by MapSetup.Run)
	local _, bermRepaired = buildEdgeBerms(map)
	local _, wallRepaired = buildInvisibleWalls(map)
	repaired = repaired or bermRepaired or wallRepaired

	buildPadSupportShelves(setup :: Folder)

	print(string.format(
		"[WAR EMPIRE] Ground heal: ok size=%.0fx%.0fx%.0f tiles=%d/%d CanCollide=%s repaired=%s",
		ground.Size.X,
		ground.Size.Y,
		ground.Size.Z,
		countHealthyGroundTiles(map),
		tiles,
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
		v70: every ground / safety-catch tile and every berm / void-wall piece.
	]]
	local map = setup:FindFirstChild("Map")
	if not map then
		return false
	end
	destroyNamed(map, "Ground")
	destroyNamed(map, "GroundTile")
	destroyNamed(map, "SafetyCatch")

	local tiles = buildGroundTiles(map)
	buildSafetyUnderfloor(map)
	-- Refresh berms + invisible void walls every force rebuild
	for _, name in ipairs({ "EdgeBermN", "EdgeBermS", "EdgeBermE", "EdgeBermW", "VoidWallN", "VoidWallS", "VoidWallE", "VoidWallW" }) do
		destroyNamed(map, name)
	end
	buildEdgeBerms(map)
	buildInvisibleWalls(map)
	buildPadSupportShelves(setup :: Folder)

	local healthy = countHealthyGroundTiles(map)
	local ground = map:FindFirstChild("Ground")
	local g = if ground and ground:IsA("BasePart") then ground else nil
	print(string.format(
		"[WAR EMPIRE] Ground FORCE-REBUILT: size=%.0fx%.0fx%.0f tiles=%d/%d CanCollide=%s Anchored=%s",
		if g then g.Size.X else 0,
		if g then g.Size.Y else 0,
		if g then g.Size.Z else 0,
		healthy,
		tiles,
		tostring(g ~= nil and g.CanCollide),
		tostring(g ~= nil and g.Anchored)
	))
	return healthy == tiles and g ~= nil and g.Size.Y >= GROUND_THICKNESS - 0.5
end



-- v68: layout ground work (BaseLayoutConfig): roads + plaza + runway markings, parade flagpole, dock basin,
-- and the inner wall with one guarded gate per rear-zone structure. Gate leaves are opened/closed by
-- StructureKitBuilder.SyncRearGates when the matching structure (Airfield / Helipad / Dock) is bought.
local REAR_GATE_LABELS = { Airfield = "AIRFIELD", Helipad = "HELIPAD", Dock = "NAVAL DOCK" }

-- v70 [J3/J4]: shared look + flags for every WE_Water part MapSetup builds (DockWater, SeaGateWater). Water parts never
-- collide, touch or take raycasts (the vehicles' water query is geometric over the tagged parts; combat rays reach the
-- real floor) and cast no shadow.
local function styleWaterPart(w: BasePart, waterId: string)
	w.Reflectance = WaterConfig.Look.Reflectance
	w.CanCollide = false
	w.CanTouch = false
	w.CanQuery = false
	w.CastShadow = false
	w:SetAttribute("WE_WaterId", waterId)
	CollectionService:AddTag(w, TAG_WATER)
end

local function buildLayoutGround(plotFolder: Folder, plotId: number, pos: Vector3)
	if not BaseLayout.Enabled() then
		return
	end
	local cfg = BaseLayout.Config()
	local look = (StructureVisualConfig :: any).BaseLook or {}
	-- v70: everything below is plot-local (BaseLayoutConfig frame) and placed through the plot frame F, so the whole
	-- layout turns with the plot when BaseLayoutConfig.FaceMapCentre is on (F = CFrame.new(pos) while it is off).
	local F = BaseLayout.PlotCFrame(pos)
	local padTop = 0.5 -- plot-local: the pad is 1 stud thick, centred on pos
	local function at(x: number, y: number, z: number): CFrame
		return F * CFrame.new(x, y, z)
	end
	local H = cfg.PlotSize * 0.5
	local folder = Instance.new("Folder")
	folder.Name = "LayoutGround"
	folder.Parent = plotFolder
	local asphalt = Color3.fromRGB(64, 66, 64)
	local paint = Color3.fromRGB(236, 232, 214)
	local yellow = look.Chevron or Color3.fromRGB(230, 196, 70)
	local steel = Color3.fromRGB(70, 74, 72)
	-- v70: the sea gate (and the channel behind it) exists only when the plots face the map centre
	local seaGate = BaseLayout.FacesMapCentre() and WaterConfig.Enabled == true
	local SG = WaterConfig.SeaGate
	local waterMidY = (WaterConfig.BottomY + WaterConfig.SurfaceY) * 0.5
	local waterH = WaterConfig.SurfaceY - WaterConfig.BottomY

	-- Roads, plaza, runway, taxiway, apron
	for _, r in ipairs(cfg.Roads) do
		local road = part({
			Name = "Road_" .. r.Name,
			Size = Vector3.new(r.SizeX, 0.12, r.SizeZ),
			CFrame = at(r.X, padTop + 0.06, r.Z),
			Color = asphalt,
			Material = Enum.Material.Asphalt,
			CanCollide = true,
			Parent = folder,
		})
		road:SetAttribute("WE_Decor", true)
		local alongX = r.SizeX >= r.SizeZ
		local len = if alongX then r.SizeX else r.SizeZ
		local markY = padTop + 0.13
		if r.Name == "Runway" then
			-- dashed white centreline + threshold bars at both ends
			local n = math.floor(len / 14)
			for i = 0, n - 1 do
				local t = -len * 0.5 + 7 + i * 14
				part({
					Name = "RunwayDash",
					Size = if alongX then Vector3.new(7, 0.02, 0.9) else Vector3.new(0.9, 0.02, 7),
					CFrame = at(r.X + (if alongX then t else 0), markY, r.Z + (if alongX then 0 else t)),
					Color = paint,
					Material = Enum.Material.SmoothPlastic,
					CanCollide = false,
					Parent = folder,
				})
			end
			for _, endSign in ipairs({ -1, 1 }) do
				for b = -3, 3 do
					local along = endSign * (len * 0.5 - 4)
					local across = b * 2.6
					part({
						Name = "RunwayThreshold",
						Size = if alongX then Vector3.new(6, 0.02, 1.2) else Vector3.new(1.2, 0.02, 6),
						CFrame = at(r.X + (if alongX then along else across), markY, r.Z + (if alongX then across else along)),
						Color = paint,
						Material = Enum.Material.SmoothPlastic,
						CanCollide = false,
						Parent = folder,
					})
				end
			end
		elseif r.Name == "Taxiway" or r.Name == "HeliApron" then
			part({
				Name = "TaxiLine",
				Size = if alongX then Vector3.new(len - 2, 0.02, 0.5) else Vector3.new(0.5, 0.02, len - 2),
				CFrame = at(r.X, markY, r.Z),
				Color = yellow,
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				Parent = folder,
			})
		else
			-- white edge lines on the compound roads
			for _, side in ipairs({ -1, 1 }) do
				local off = side * ((if alongX then r.SizeZ else r.SizeX) * 0.5 - 0.6)
				part({
					Name = "RoadEdge",
					Size = if alongX then Vector3.new(len - 1, 0.02, 0.35) else Vector3.new(0.35, 0.02, len - 1),
					CFrame = at(r.X + (if alongX then 0 else off), markY, r.Z + (if alongX then off else 0)),
					Color = paint,
					Material = Enum.Material.SmoothPlastic,
					CanCollide = false,
					Parent = folder,
				})
			end
		end
	end

	-- Parade-ground flagpole
	do
		local f = cfg.Courtyard.Flagpole
		part({ Name = "FlagBase", Size = Vector3.new(4, 1, 4), CFrame = at(f.X, padTop + 0.5, f.Z), Color = Color3.fromRGB(150, 146, 134), Material = Enum.Material.Concrete, CanCollide = true, Parent = folder })
		part({ Name = "FlagPole", Size = Vector3.new(0.5, 28, 0.5), CFrame = at(f.X, padTop + 15, f.Z), Color = steel, Material = Enum.Material.Metal, CanCollide = true, Parent = folder })
		-- fb2: flag cloths are 0.12 thick and tagged WE_FlagHost (the nation flag binds to their Left / Right faces)
		local paradeFlag = part({ Name = "ParadeFlag", Size = Vector3.new(0.12, 4.4, 7.5), CFrame = at(f.X, padTop + 25.8, f.Z - 3.9), Color = Color3.fromRGB(70, 110, 60), Material = Enum.Material.Fabric, CanCollide = false, Parent = folder })
		paradeFlag:SetAttribute("WE_FlagHost", true)
	end

	-- Dock basin: water surface + concrete kerb
	do
		local d = cfg.Courtyard.DockBasin
		-- v70 [J3/J4]: one water level for the whole map (WaterConfig.BottomY..SurfaceY = 0.3..1.5). The part is TURNED
		-- WITH THE PLOT (exact quarter turn, unchanged world AABB), so the vehicles' basin spawn heading (the part's yaw)
		-- points the bow at the sea gate. DockWater is the only plot water part with WE_PlotId.
		local water = part({
			Name = "DockWater",
			Size = Vector3.new(d.SizeX, waterH, d.SizeZ),
			CFrame = BaseLayout.PlotLocalCFrame(pos, d.X, waterMidY - pos.Y, d.Z),
			Color = WaterConfig.Look.Color,
			Material = WaterConfig.Look.Material,
			Transparency = WaterConfig.Look.Transparency,
			CanCollide = false,
			Parent = folder,
		})
		styleWaterPart(water, "DockWater")
		water:SetAttribute("WE_PlotId", plotId)
		-- kerbs: plot-local boxes { size, centre }
		local kx0, kx1 = d.X - d.SizeX * 0.5 - 1.2, d.X + d.SizeX * 0.5 + 1.2 -- 101.8 .. 154.2
		local rearZ = d.Z - d.SizeZ * 0.5 - 0.6
		local kerbs: { { Vector3 } } = {
			{ Vector3.new(d.SizeX + 2.4, 1, 1.2), Vector3.new(d.X, padTop + 0.5, d.Z + d.SizeZ * 0.5 + 0.6) },
		}
		if seaGate then
			-- v70 §4: the rear kerb opens onto the gate water (stubs either side) and two short kerbs line the gate water
			-- from the basin to the gate posts
			local sideZ0, sideZ1 = SG.WallZ + SG.PostDepth * 0.5, SG.BasinRearZ -- -156.8 .. -147
			table.insert(kerbs, { Vector3.new(SG.X0 - kx0, 1, 1.2), Vector3.new((kx0 + SG.X0) * 0.5, padTop + 0.5, rearZ) })
			table.insert(kerbs, { Vector3.new(kx1 - SG.X1, 1, 1.2), Vector3.new((SG.X1 + kx1) * 0.5, padTop + 0.5, rearZ) })
			table.insert(kerbs, { Vector3.new(1.2, 1, sideZ1 - sideZ0), Vector3.new(SG.X0 - 0.6, padTop + 0.5, (sideZ0 + sideZ1) * 0.5) })
			table.insert(kerbs, { Vector3.new(1.2, 1, sideZ1 - sideZ0), Vector3.new(SG.X1 + 0.6, padTop + 0.5, (sideZ0 + sideZ1) * 0.5) })
		else
			table.insert(kerbs, { Vector3.new(d.SizeX + 2.4, 1, 1.2), Vector3.new(d.X, padTop + 0.5, rearZ) })
		end
		table.insert(kerbs, { Vector3.new(1.2, 1, d.SizeZ), Vector3.new(d.X + d.SizeX * 0.5 + 0.6, padTop + 0.5, d.Z) })
		table.insert(kerbs, { Vector3.new(1.2, 1, d.SizeZ), Vector3.new(d.X - d.SizeX * 0.5 - 0.6, padTop + 0.5, d.Z) })
		for _, e in ipairs(kerbs) do
			part({ Name = "DockKerb", Size = e[1], CFrame = F * CFrame.new(e[2]), Color = Color3.fromRGB(150, 146, 134), Material = Enum.Material.Concrete, CanCollide = true, Parent = folder })
		end
	end

	-- Inner wall with guarded gates
	local iw = cfg.InnerWall
	local zc = iw.Z
	local wallCol = (StructureVisualConfig.Palettes.DefensiveWalls and StructureVisualConfig.Palettes.DefensiveWalls.Body) or Color3.fromRGB(178, 170, 148)
	local half = iw.GateWidth * 0.5
	local function wallSeg(a: number, b: number)
		if b - a < 0.5 then
			return
		end
		part({
			Name = "InnerWall",
			Size = Vector3.new(b - a, iw.Height, iw.Thickness),
			CFrame = at((a + b) * 0.5, padTop + iw.Height * 0.5, zc),
			Color = wallCol,
			Material = Enum.Material.Concrete,
			CanCollide = true,
			CastShadow = true,
			Parent = folder,
		})
		part({
			Name = "InnerWallCap",
			Size = Vector3.new(b - a + 0.3, 0.5, iw.Thickness + 0.3),
			CFrame = at((a + b) * 0.5, padTop + iw.Height + 0.25, zc),
			Color = look.WallCap or Color3.fromRGB(132, 126, 110),
			Material = Enum.Material.Concrete,
			CanCollide = false,
			Parent = folder,
		})
	end
	local gates = {}
	for id, g in pairs(iw.Gates) do
		table.insert(gates, { Id = id, X = g.X })
	end
	table.sort(gates, function(a, b)
		return a.X < b.X
	end)
	local cursor = -H
	for _, g in ipairs(gates) do
		wallSeg(cursor, g.X - half)
		cursor = g.X + half

		local gateFolder = Instance.new("Folder")
		gateFolder.Name = "RearGate_" .. g.Id
		gateFolder:SetAttribute("GateId", g.Id)
		gateFolder:SetAttribute("PlotId", plotId)
		gateFolder.Parent = folder
		local gx = g.X
		for _, sx in ipairs({ -1, 1 }) do
			-- v70: "RearGatePost" (was "GatePost"): GateDefenseService's no-perimeter fallback collects every descendant
			-- named GatePost under the plot and must only ever see the perimeter main-gate posts
			part({
				Name = "RearGatePost",
				Size = Vector3.new(1.6, iw.Height + 1.5, iw.Thickness + 1),
				CFrame = at(gx + sx * (half + 0.8), padTop + (iw.Height + 1.5) * 0.5, zc),
				Color = steel,
				Material = Enum.Material.Metal,
				CanCollide = true,
				Parent = gateFolder,
			})
		end
		local lintel = part({
			Name = "GateLintel",
			Size = Vector3.new(iw.GateWidth + 3.2, 2.2, iw.Thickness + 0.6),
			CFrame = at(gx, padTop + iw.Height + 0.6, zc),
			Color = Color3.fromRGB(40, 44, 42),
			Material = Enum.Material.Metal,
			CanCollide = true,
			Parent = gateFolder,
		})
		local sg = Instance.new("SurfaceGui")
		sg.Name = "WE_GateSign"
		sg.Face = Enum.NormalId.Back -- plot-local +Z: faces the main compound
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 40
		sg.LightInfluence = 0
		sg.MaxDistance = 80 -- v70: painted sign, near-only (CLAUDE.md SurfaceGui budget)
		sg.Parent = lintel
		local lbl = Instance.new("TextLabel")
		lbl.Name = "Text"
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundColor3 = Color3.fromRGB(20, 22, 20)
		lbl.BorderSizePixel = 0
		lbl.Font = Enum.Font.GothamBlack
		lbl.TextScaled = true
		lbl.TextColor3 = yellow
		lbl.Text = (REAR_GATE_LABELS[g.Id] or string.upper(g.Id)) .. " · LOCKED"
		lbl.Parent = sg
		-- v72 (phone HUD audit F4): inset the sign text so the gate name reads in full (TextScaled filled the whole
		-- board and clipped at the edges); InnerWall.SignInsetStuds x PixelsPerStud left/right, capped text size
		do
			local insetPx = math.floor(((BaseLayout.Config().InnerWall or {}).SignInsetStuds or 2.0) * sg.PixelsPerStud + 0.5)
			local signPad = Instance.new("UIPadding")
			signPad.PaddingLeft = UDim.new(0, insetPx)
			signPad.PaddingRight = UDim.new(0, insetPx)
			signPad.PaddingTop = UDim.new(0, 6)
			signPad.PaddingBottom = UDim.new(0, 6)
			signPad.Parent = lbl
			local signCap = Instance.new("UITextSizeConstraint")
			signCap.MaxTextSize = 64
			signCap.Parent = lbl
		end
		local leafH = iw.Height - 2
		for i, sx in ipairs({ -1, 1 }) do
			local leaf = part({
				Name = "GateLeaf" .. i,
				Size = Vector3.new(half - 0.1, leafH, 0.8),
				CFrame = at(gx + sx * half * 0.5, padTop + leafH * 0.5, zc),
				Color = Color3.fromRGB(78, 84, 80),
				Material = Enum.Material.DiamondPlate,
				CanCollide = true,
				Parent = gateFolder,
			})
			leaf:SetAttribute("WE_GateLeaf", sx)
			leaf:SetAttribute("WE_ClosedCFrame", leaf.CFrame)
			part({
				Name = "GateStripe",
				Size = Vector3.new(half - 0.1, 0.8, 0.9),
				CFrame = leaf.CFrame * CFrame.new(0, -leafH * 0.5 + 2.2, 0),
				Color = yellow,
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				Parent = leaf,
			})
		end
		-- Two guards with sandbags on the compound side
		for _, sx in ipairs({ -1, 1 }) do
			local gLocal = Vector3.new(gx + sx * (half + 3.6), padTop + 2.1, zc + iw.Thickness * 0.5 + 2.4)
			part({
				Name = "GuardSandbag",
				Size = Vector3.new(4.2, 1.3, 1.3),
				CFrame = at(gLocal.X, padTop + 0.65, gLocal.Z + 2.2),
				Color = Color3.fromRGB(186, 164, 118),
				Material = Enum.Material.Fabric,
				CanCollide = true,
				Parent = gateFolder,
			})
			-- v70 (HUD spec §5): no "GUARD" NPCLabel over the rear-gate guards
			makeSoldierKit(
				gateFolder,
				"GateGuard_" .. g.Id .. (if sx > 0 then "R" else "L"),
				F * CFrame.new(gLocal) * CFrame.Angles(0, math.rad(180), 0),
				Color3.fromRGB(62, 72, 52),
				nil,
				Color3.fromRGB(140, 150, 130),
				150,
				"Guard",
				nil
			)
		end
	end
	wallSeg(cursor, H)

	-- v70 [J1] sea gate (spec_final §4): on the rear perimeter line behind the dock basin, plot-local x SG.X0..SG.X1.
	-- Two collidable leaves (12 tall together) close it; StructureKitBuilder.SyncRearGates only ARMS it (Dock L1+) and
	-- Waterways' loop slides the leaves west into the wall line while a boat driven by the owner / a clan-mate is near.
	-- A WE_WallGap marker makes SyncPerimeterWalls leave the wall open across the gate.
	if seaGate then
		local gx = (SG.X0 + SG.X1) * 0.5
		local span = SG.X1 - SG.X0
		local gate = Instance.new("Folder")
		gate.Name = "SeaGate_Dock"
		gate:SetAttribute("GateId", "Dock")
		gate:SetAttribute("PlotId", plotId)
		gate:SetAttribute("WE_GateMode", "Proximity")
		gate:SetAttribute("WE_GateLabel", SG.Label)
		gate:SetAttribute("WE_GateArmed", false)
		gate:SetAttribute("WE_GateOpen", false)
		gate:SetAttribute("WE_GateCentre", F:PointToWorldSpace(Vector3.new(gx, 3, SG.WallZ)))
		gate.Parent = folder

		-- gate water: basin rear edge → pad edge, turned with the plot like DockWater. [J3] WE_GatePlotId, NOT WE_PlotId
		-- (the vehicles' plotBasin takes the first WE_Water part with WE_PlotId).
		local gateWater = part({
			Name = "SeaGateWater",
			Size = Vector3.new(span, waterH, SG.BasinRearZ - SG.PadEdgeZ),
			CFrame = BaseLayout.PlotLocalCFrame(pos, gx, waterMidY - pos.Y, (SG.PadEdgeZ + SG.BasinRearZ) * 0.5),
			Color = WaterConfig.Look.Color,
			Material = WaterConfig.Look.Material,
			Transparency = WaterConfig.Look.Transparency,
			CanCollide = false,
			Parent = gate,
		})
		styleWaterPart(gateWater, "SeaGateWater")
		gateWater:SetAttribute("WE_GatePlotId", plotId)

		for _, sx in ipairs({ -1, 1 }) do
			-- named differently from "GatePost" on purpose (GateDefenseService reads that name)
			part({
				Name = "SeaGatePost",
				Size = Vector3.new(SG.PostWidth, SG.PostHeight, SG.PostDepth),
				CFrame = at(gx + sx * (span + SG.PostWidth) * 0.5, padTop + SG.PostHeight * 0.5, SG.WallZ),
				Color = steel,
				Material = Enum.Material.Metal,
				CanCollide = true,
				Parent = gate,
			})
		end
		-- lintel: never collides or takes raycasts (a boat's land probe must never see it)
		local lintel = part({
			Name = "GateLintel",
			Size = Vector3.new(span + SG.PostWidth * 2, 2.2, SG.PostDepth + 0.4),
			CFrame = at(gx, padTop + SG.LintelBottom + 1.1, SG.WallZ),
			Color = Color3.fromRGB(40, 44, 42),
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = gate,
		})
		lintel.CanTouch = false
		lintel.CanQuery = false
		local sg = Instance.new("SurfaceGui")
		sg.Name = "WE_GateSign"
		sg.Face = Enum.NormalId.Back -- plot-local +Z: faces the basin
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 40
		sg.LightInfluence = 0
		sg.MaxDistance = 80 -- v70: painted sign, near-only (CLAUDE.md SurfaceGui budget)
		sg.Parent = lintel
		local lbl = Instance.new("TextLabel")
		lbl.Name = "Text"
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundColor3 = Color3.fromRGB(20, 22, 20)
		lbl.BorderSizePixel = 0
		lbl.Font = Enum.Font.GothamBlack
		lbl.TextScaled = true
		lbl.TextColor3 = yellow
		lbl.Text = SG.Label .. " · LOCKED"
		lbl.Parent = sg
		-- v72 (phone HUD audit F4): inset the sign text so the gate name reads in full (TextScaled filled the whole
		-- board and clipped at the edges); InnerWall.SignInsetStuds x PixelsPerStud left/right, capped text size
		do
			local insetPx = math.floor(((BaseLayout.Config().InnerWall or {}).SignInsetStuds or 2.0) * sg.PixelsPerStud + 0.5)
			local signPad = Instance.new("UIPadding")
			signPad.PaddingLeft = UDim.new(0, insetPx)
			signPad.PaddingRight = UDim.new(0, insetPx)
			signPad.PaddingTop = UDim.new(0, 6)
			signPad.PaddingBottom = UDim.new(0, 6)
			signPad.Parent = lbl
			local signCap = Instance.new("UITextSizeConstraint")
			signCap.MaxTextSize = 64
			signCap.Parent = lbl
		end

		-- leaves: WE_GateLeaf = LeafSlide (-1 = slide plot-local west into the wall line), WE_ClosedCFrame after placing
		for i, lf in ipairs(SG.Leaves) do
			local leaf = part({
				Name = lf.Name,
				Size = Vector3.new(span, lf.Height, lf.Thickness),
				CFrame = at(gx, padTop + lf.Bottom + lf.Height * 0.5, SG.WallZ),
				Color = if i == 1 then yellow else steel,
				Material = if i == 1 then Enum.Material.DiamondPlate else Enum.Material.Metal,
				Transparency = lf.Transparency or 0,
				CanCollide = true,
				Parent = gate,
			})
			leaf:SetAttribute("WE_GateLeaf", SG.LeafSlide)
			leaf:SetAttribute("WE_ClosedCFrame", leaf.CFrame)
			if i == 1 then
				-- black band on the yellow boom (a child part: SetGateOpen moves it with the leaf)
				part({
					Name = "GateStripe",
					Size = Vector3.new(span, 0.8, lf.Thickness + 0.1),
					CFrame = leaf.CFrame * CFrame.new(0, 1.3, 0),
					Color = Color3.fromRGB(28, 28, 26),
					Material = Enum.Material.SmoothPlastic,
					CanCollide = false,
					Parent = leaf,
				})
			end
		end

		-- wall gap marker: WORLD-axis-aligned box (BaseLayout.PlotRect; StructureKitBuilder's gappedWall reads world axes)
		local gapC, gapSX, gapSZ = BaseLayout.PlotRect(pos, gx, SG.WallZ, SG.GapWidth, SG.GapDepth)
		local gap = part({
			Name = "SeaGateWallGap",
			Size = Vector3.new(gapSX, 2, gapSZ),
			CFrame = CFrame.new(gapC.X, gapC.Y + padTop + 1, gapC.Z),
			Transparency = 1,
			CanCollide = false,
			Parent = gate,
		})
		gap.CanTouch = false
		gap.CanQuery = false
		gap:SetAttribute("WE_WallGap", true)

		-- one guard on the west quay facing the gate water (+X); no NPCLabel (HUD pass removes gate-guard labels)
		for gi, gd in ipairs(SG.Guards) do
			part({
				Name = "GuardSandbag",
				Size = Vector3.new(1.3, 1.3, 4.2),
				CFrame = at(gd.X + 3.5, padTop + 0.65, gd.Z),
				Color = Color3.fromRGB(186, 164, 118),
				Material = Enum.Material.Fabric,
				CanCollide = true,
				Parent = gate,
			})
			makeSoldierKit(
				gate,
				"GateGuard_Sea" .. (if gi > 1 then tostring(gi) else ""),
				F * CFrame.new(gd.X, padTop + 2.1, gd.Z) * CFrame.Angles(0, math.rad(-90), 0),
				Color3.fromRGB(62, 72, 52),
				nil,
				Color3.fromRGB(140, 150, 130),
				150,
				"Guard",
				nil
			)
		end
	end
end

-- v68: ATM cluster anchor offset (legacy (28, 8) → BaseLayoutConfig Courtyard.Collector)
local function collectorShift(): Vector3
	if BaseLayout.Enabled() then
		local c = BaseLayout.Config().Courtyard.Collector
		return Vector3.new(c.X - 28, 0, c.Z - 8)
	end
	return Vector3.zero
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
			Color = COL_CHEVRON,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Transparency = 0,
			Parent = folder,
		})
		part({
			Name = "ChevronTip" .. idx,
			Size = Vector3.new(1.6, 0.14, 1.6),
			CFrame = cf * CFrame.new(0, 0.02, -1.4) * CFrame.Angles(0, math.rad(45), 0),
			Color = COL_CHEVRON,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Transparency = 0,
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
	-- v70: nodes are plot-local, mapped through the plot frame (chevron yaws follow the world node deltas)
	local F = BaseLayout.PlotCFrame(plotOrigin)
	local spawnPos = F:PointToWorldSpace(Vector3.new(0, 0.5, 55))
	local nodes = {
		spawnPos,
	}
	if BaseLayout.Enabled() then
		-- v68: spawn → down the main road → Command Center doorway
		local cfg = BaseLayout.Config()
		local sp = cfg.SpawnOffset
		local cc = cfg.Structures.CommandCenter
		local dx, dz = BaseLayout.Rotate(7, 14, cc.Yaw)
		nodes = {
			F:PointToWorldSpace(Vector3.new(sp.X, 0.5, sp.Z - 8)),
			F:PointToWorldSpace(Vector3.new(0, 0.5, 60)),
			F:PointToWorldSpace(Vector3.new(cc.Site.X + dx, 0.5, cc.Site.Z + dz)),
		}
	end
	for i, def in ipairs(STRUCTURES) do
		if i > 5 or BaseLayout.Enabled() then
			break
		end
		local col = (i - 1) % STRUCT_COLS
		local row = math.floor((i - 1) / STRUCT_COLS)
		local offset = STRUCT_ORIGIN + Vector3.new(col * STRUCT_GAP, 0, row * STRUCT_GAP)
		table.insert(nodes, F:PointToWorldSpace(offset + Vector3.new(0, 0.5, 0)))
	end
	-- Guide toward MoneyCollector + premium Robux pads (unpaid ATM cluster)
	if not BaseLayout.Enabled() then
		local atmCluster = F:PointToWorldSpace(Vector3.new(28, 0.5, 8))
		table.insert(nodes, atmCluster)
	end

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
	-- v70: positions and yaws are plot-local, placed through the plot frame
	local F = BaseLayout.PlotCFrame(plotOrigin)

	local function sandbag(at: Vector3, yaw: number, idx: number)
		local cf = F * CFrame.new(at) * CFrame.Angles(0, yaw, 0)
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
		local cf = F * CFrame.new(at) * CFrame.Angles(0, yaw, 0)
		part({
			Name = "PadChevron" .. idx,
			Size = Vector3.new(2.4, 0.1, 1.6),
			CFrame = cf,
			Color = Color3.fromRGB(245, 245, 250),
			Material = Enum.Material.SmoothPlastic, -- v70: painted (no decorative Neon)
			CanCollide = false,
			Transparency = 0.2,
			Parent = folder,
		})
	end

	local idx = 1
	-- First 6 structure pads get flanking sandbags + approach chevron (legacy grid pads only; v68 consoles)
	for i, def in ipairs(STRUCTURES) do
		if i > 6 or BaseLayout.Enabled() then
			break
		end
		local col = (i - 1) % STRUCT_COLS
		local row = math.floor((i - 1) / STRUCT_COLS)
		local offset = STRUCT_ORIGIN + Vector3.new(col * STRUCT_GAP, 0, row * STRUCT_GAP)
		local padPos = offset -- plot-local
		sandbag(padPos + Vector3.new(-7, 0.7, 4), math.rad(15), idx)
		idx += 1
		sandbag(padPos + Vector3.new(7, 0.7, 4), math.rad(-15), idx)
		idx += 1
		miniChevron(padPos + Vector3.new(0, 0.55, 9), math.rad(180), idx)
		idx += 1
	end
	-- ATM approach berm
	local atm = collectorShift() + Vector3.new(28, 0.7, 8) -- plot-local
	sandbag(atm + Vector3.new(-6, 0, 6), 0, idx)
	idx += 1
	sandbag(atm + Vector3.new(6, 0, 6), 0, idx)
end



-- v70: F = plot frame, atmLocal = plot-local ATM cluster anchor (pads turn with the plot)
-- F1 (owner's 11 features, lane W): the pads are MonetizationConfig.PremiumPads.Slots, in order (red Auto Collect,
-- yellow 2x Cash, cyan Speed). A slot is built only while one of its offers has a live Id (LivePadOffer: the first
-- offer with Id ~= 0, e.g. the Speed slot sells the 99 R$ Speed Boost until the 5 R$ Speed Pass Id is pasted).
-- The server decides OWNED (PremiumPadService.alreadyOwns, incl. the slot's OwnedIfAny keys); the Shop client dims an
-- owned pad. VIP is a Shop row only and the Golden Pump pad stands at the pumps (PlotOilPumpService), so at most 3
-- pads and 3 labels sit at the ATM (CLAUDE.md: at most 3 labels on screen at a base). The pad keeps its Neon top
-- (it is the offer; census cap 18) and has no light. Each label is stud-scaled, MaxDistance PremiumPads.LabelMaxDistance,
-- never AlwaysOnTop, and tagged WorldLabelConfig.BaseLabelTag for the client LabelGovernor.
local function buildPremiumPads(folder: Folder, plotId: number, F: CFrame, atmLocal: Vector3)
	local labelRange = MonetizationConfig.PremiumPads.LabelMaxDistance
	for _, slot in ipairs(MonetizationConfig.PremiumPads.Slots) do
		local offer = MonetizationConfig.LivePadOffer(slot)
		if offer == nil then
			continue -- no live Id for this slot: no pad, no label, nothing to prompt
		end
		local pad = part({
			Name = "PremiumPad_" .. offer.Key,
			Size = Vector3.new(7, 0.45, 7),
			CFrame = F * CFrame.new(atmLocal + slot.Offset),
			Color = slot.Color,
			Material = Enum.Material.Neon,
			CanCollide = true,
			Parent = folder,
		})
		pad:SetAttribute("PlotId", plotId)
		pad:SetAttribute("OfferKind", offer.Kind)
		pad:SetAttribute("OfferKey", offer.Key)
		pad:SetAttribute("OwnedIfAny", table.concat(MonetizationConfig.PadOwnedKeys(slot), ","))
		pad:SetAttribute("PadSlot", slot.Id)
		CollectionService:AddTag(pad, TAG_PREMIUM)
		WorldLabel.Create(pad, slot.Label, {
			Name = "WE_PremiumBillboard",
			Sub = "R$",
			Color = slot.Color,
			MaxDistance = labelRange,
			Offset = Vector3.new(0, 5.5, 0),
			BaseLabel = true, -- CollectionService tag WorldLabelConfig.BaseLabelTag (the LabelGovernor's cap)
		})
	end
end

local function buildMoneyCollector(plotFolder: Folder, plotId: number, pos: Vector3)
	-- v68: the ATM cluster (body, screen, collect ring, premium pads) moves as a group to Courtyard.Collector
	-- v70: plot-local ATM anchor, every part placed through the plot frame F (turns with the plot)
	local F = BaseLayout.PlotCFrame(pos)
	local base = collectorShift()
	-- ATM-like Part kit: matte grey body + green digit screen (MoneyCollectorService billboard refreshes $)
	local folder = Instance.new("Folder")
	folder.Name = "MoneyCollector"
	folder.Parent = plotFolder
	local body = part({
		Name = "CollectorBody",
		Size = Vector3.new(6, 8, 4),
		CFrame = F * CFrame.new(base + Vector3.new(28, 4.5, 8)),
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
		CFrame = F * CFrame.new(base + Vector3.new(28, 0.8, 8)),
		Color = Color3.fromRGB(70, 74, 78),
		Material = Enum.Material.Concrete,
		CanCollide = true,
		Parent = folder,
	})
	local screen = part({
		Name = "CollectorScreen",
		Size = Vector3.new(4.2, 2.8, 0.35),
		CFrame = F * CFrame.new(base + Vector3.new(28, 5.2, 8 - 2.15)),
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
	sg.MaxDistance = 80 -- v70: near-only (CLAUDE.md SurfaceGui budget)
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
	-- v70 (HUD spec §5): no "COLLECT · Touch ATM" billboard (it was AlwaysOnTop); the ATM screen and the flat lime
	-- collect circle are the cue.
	-- Lime Collect circle on ground (touch radius visual). A cylinder's axis is its X: X is the thickness, Y/Z the
	-- diameter, turned 90° about Z so it lies flat (it was sized along X, which stood a 14-stud pole on end).
	local collectCircle = part({
		Name = "CollectCircle",
		Size = Vector3.new(0.25, 14, 14),
		CFrame = F * CFrame.new(base + Vector3.new(28, 0.55, 8)),
		Color = Color3.fromRGB(90, 255, 110),
		Material = Enum.Material.SmoothPlastic, -- v70: painted (no decorative Neon)
		Transparency = 0.55,
		CanCollide = false,
		Shape = Enum.PartType.Cylinder,
		Parent = folder,
	})
	collectCircle.CFrame = F * CFrame.new(base + Vector3.new(28, 0.55, 8)) * CFrame.Angles(0, 0, math.rad(90))
	collectCircle:SetAttribute("PlotId", plotId)
	local ring = part({
		Name = "CollectRing",
		Size = Vector3.new(0.2, 15.5, 15.5),
		Color = Color3.fromRGB(60, 220, 90),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.35,
		CanCollide = false,
		Shape = Enum.PartType.Cylinder,
		Parent = folder,
	})
	ring.CFrame = F * CFrame.new(base + Vector3.new(28, 0.45, 8)) * CFrame.Angles(0, 0, math.rad(90))

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
	buildPremiumPads(folder, plotId, F, base + Vector3.new(28, 0, 8))
end

-- Pre-World-v2 lighting (bright midday desert + the 1.5 s day loop). Kept only as the fallback when Modules.WorldAtmosphere
-- is missing or fails; the one-line look revert is WorldConfig.Atmosphere.Preset = "Classic".
local function applyClassicLighting()
	local worldLight = (StructureVisualConfig :: any).WorldLighting or {}
	Lighting.Ambient = worldLight.DayAmbient or Color3.fromRGB(165, 145, 110)
	Lighting.OutdoorAmbient = Color3.fromRGB(185, 165, 130)
	Lighting.Brightness = 3.15
	Lighting.ClockTime = 12.5 -- intense midday sun
	Lighting.GeographicLatitude = 22
	Lighting.EnvironmentDiffuseScale = worldLight.EnvironmentDiffuseScale or 0.55
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
		local dayAmb = ((StructureVisualConfig :: any).WorldLighting or {}).DayAmbient or Color3.fromRGB(165, 145, 110)
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
end

-- World v2 W1: run fn(module) on one of the Modules.World* modules. A missing module or an error is logged and never
-- stops the map build. Returns true when fn ran without error.
local function withWorldModule(name: string, fn: (any) -> ()): boolean
	local mod = script.Parent:FindFirstChild(name)
	if not (mod and mod:IsA("ModuleScript")) then
		warn("[WAR EMPIRE] MapSetup: Modules." .. name .. " missing — skipped (map continues)")
		return false
	end
	local ok, err = pcall(function()
		fn(require(mod) :: any)
	end)
	if not ok then
		warn("[WAR EMPIRE] MapSetup: " .. name .. " failed (map continues):", err)
	end
	return ok
end

-- ── Empire Bank (W3 step 2 lane BK; spec scratchpad w3s2 §1.1–§1.2, §5, §6; geometry w3s2/geo/bank.py) ──────────
--[[ A walk-in hall in the Town v2 style, facing south down Bank Street. 17 parts, the same count as the old block, so
	the busiest 512-stud circle does not move:
	  BankPlaza      36 x 1.2 x 36, top 1.6 (the hall floor); hosts the Town.Bank.* activity anchors (WorldConfig.Town.
	                 BankAnchors, stamped through ActivityAnchors.Stamp: 0 parts)
	  BankHall       the WorldKits TownBlock "hall" shell (7 parts): back wall, 2 side walls, 2 front piers round a 10-wide
	                 full-height opening, the roof slab, the upper window strip; 24 x 22, 2 storeys (x 208..232, z -236..-214)
	  BankColumnW/E  2 portico columns, both outside the sign's width, so neither hides the EMPIRE BANK sign
	  BankSign       the EMPIRE BANK board over the opening, painted here (WorldKits.Sign, inside the world sign budget,
	                 before MapDressing paints the POI boards); BankRaidService paints it only if it has no sign yet
	  BankGate       the bar gate in the opening, built OPEN until the jobs take it over (Phase B): an up-and-over
	                 door tipped flat under the roof slab (a raised upright slab sat between a follow camera outside and
	                 a raider on the vault, and a CanCollide-false part never pops the camera in), CanCollide false,
	                 WE_GateState "open", a runtime door (WE_RuntimeDoor: WorldHygiene Enforce leaves it alone);
	                 WE_ClosedCFrame / WE_OpenCFrame are its two positions
	  VaultDoor      the round vault door on the back wall (dressing)
	  VaultPad       the gold pad (12 x 12, no collision), tag WE_BankVault, centre (220, -224) inside the hall: 2 studs
	                 toward the door from the Town.Bank.Vault anchor (220, -226), so the legacy stand-on-vault raid
	                 (BankRaidConfig.VaultRadius 12 round this part) never reaches round the back wall, where no guard
	                 can see (the jobs' crack ring is the anchor's, r 8, inside the hall)
	  PlanterW/E     2 concrete planters on the plaza (cover for guards G1 / G2 and for raiders)
	  StateBanner    8 x 6 x 0.4 standing on the roof, no collision, no raycasts; green = open (Phase B recolours it)
	No beacon, no kerb, no light, no Neon and no billboard here (BankRaidService owns the one vault label). The hall
	parts come from the kit (PreferMesh never applies: TownBlock has no mesh overlay). BANK_POS is also
	BankRaidConfig.Position (a separate literal: BuyPathStatic pins both), and every coordinate below is absolute, like
	the anchors and the fallback guard posts. ]]
local BANK_POS = Vector3.new(220, 1, -220) -- the plaza centre = BankRaidConfig.Position
local BANK_FLOOR_Y = 1.6 -- the plaza top (the hall floor; the anchors' Y 1.1 above WorldConfig.Activity.FloorY 0.5)
local BANK_HALL_W, BANK_HALL_D, BANK_HALL_STOREYS = 24, 22, 2
local BANK_HALL_CENTRE_Z = -225 -- front (the opening) at z -214, back at z -236
local BANK_GATE_CEILING_GAP = 0.02 -- open: the gate lies flat this far under the roof slab (y 14.98..15.58, z -223.9..-214.9)
local BANK_VAULT_Z = -224 -- the vault pad centre (the Town.Bank.Vault anchor stays at -226; see the header)
local BANK_BANNER_OPEN = Color3.fromRGB(70, 170, 90) -- StateBanner "open" (OpsConfig.Ui.BannerColors.Open in Phase B)
local BANK_SIGN_TEXT = "EMPIRE BANK" -- = BankRaidConfig.Sign.Text

local function buildEmpireBank(root: Folder)
	-- streaming2 S4 (F24): the bank is ONE Atomic Model "EmpireBank" (was a Folder of 10 loose parts + the Default BankHall),
	-- so a client gets the plaza, hall, gate, vault pad, sign and banner together or none of them (17 parts, 36 studs
	-- across). Same name and the same children, so every lookup still works (BankRaidService's "EmpireBank" ancestor walk,
	-- OpsSites' door / banner search from BankPlaza's parent, the vault by its WE_BankVault tag, Hygiene's
	-- BillboardAllowAncestors). Atomic is set first; the model is built unparented and parented once whole (after the
	-- anchors, below), so every piece is an initial descendant. Inert while Workspace.StreamingEnabled is false.
	local oldBank = root:FindFirstChild("EmpireBank")
	if oldBank then
		oldBank:Destroy()
	end
	local bankModel = Instance.new("Model")
	bankModel.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	bankModel.Name = "EmpireBank"
	local plaza = part({
		Name = "BankPlaza",
		Size = Vector3.new(36, 1.2, 36),
		Position = BANK_POS,
		Color = Color3.fromRGB(168, 160, 144),
		Material = Enum.Material.Pavement,
		Parent = bankModel,
	})

	-- the hall shell (WorldKits TownBlock "hall": exactly 7 parts at 2 storeys, no Roof / Lantern); its front (local -Z)
	-- turns to face south (+Z)
	local roofTop = BANK_FLOOR_Y + BANK_HALL_STOREYS * 7 + 1.2 -- the kit's roof slab top (read back from the part below)
	local roofBottom = BANK_FLOOR_Y + BANK_HALL_STOREYS * 7 -- the roof slab's underside = the wall tops (read back too)
	withWorldModule("WorldKits", function(WorldKits: any)
		local hall = Instance.new("Model")
		hall.Name = "BankHall"
		local n = WorldKits.Add(hall, "TownBlock", CFrame.new(220, BANK_FLOOR_Y, BANK_HALL_CENTRE_Z) * CFrame.Angles(0, math.pi, 0), {
			Width = BANK_HALL_W,
			Depth = BANK_HALL_D,
			Storeys = BANK_HALL_STOREYS,
			Variant = "hall",
			Color = Color3.fromRGB(214, 206, 188), -- pale limestone walls (trim 20 % darker)
		})
		hall.Parent = bankModel
		local roof = hall:FindFirstChild("HallRoof")
		if roof and roof:IsA("BasePart") then
			roofTop = roof.Position.Y + roof.Size.Y * 0.5
			roofBottom = roof.Position.Y - roof.Size.Y * 0.5
		end
		if n ~= 7 then
			warn("[WAR EMPIRE] MapSetup: the Empire Bank hall has " .. tostring(n) .. " parts (want 7)")
		end
	end)

	-- portico columns (x 211.3..212.7 and 227.3..228.7, just in front of the piers): 1.3 outside the sign's x 214..226,
	-- so no view from Bank Street loses a corner of the sign behind one (the geometry draft's x 213 / 227 hid up to 8 %
	-- of it from the street's edges); guard posts G3 / G4 stay 1.5 clear of them
	for _, c in ipairs({ { Name = "BankColumnW", X = 212 }, { Name = "BankColumnE", X = 228 } }) do
		part({
			Name = c.Name,
			Size = Vector3.new(1.4, 14, 1.4),
			Position = Vector3.new(c.X, BANK_FLOOR_Y + 7, -212.5),
			Color = Color3.fromRGB(232, 228, 216),
			Material = Enum.Material.Marble,
			CanCollide = true,
			Parent = bankModel,
		})
	end

	-- EMPIRE BANK: a dark board (cream text reads on it) over the opening, x 214..226, y 13.6..15.4, its street face +Z
	local sign = part({
		Name = "BankSign",
		Size = Vector3.new(12, 1.8, 0.4),
		Position = Vector3.new(220, BANK_FLOOR_Y + 12.9, -213.6),
		Color = Color3.fromRGB(34, 38, 48),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = bankModel,
	})
	sign.CanQuery = false
	sign.CanTouch = false
	withWorldModule("WorldKits", function(WorldKits: any)
		if sign:FindFirstChildWhichIsA("SurfaceGui") == nil and WorldKits.Sign(sign, Enum.NormalId.Back, BANK_SIGN_TEXT) == nil then
			warn("[WAR EMPIRE] MapSetup: EMPIRE BANK sign not painted (world sign budget)")
		end
	end)

	-- the bar gate (10 x 9 x 0.6 in the opening, x 215..225): open until OpsService runs the heist (Phase B). Open is
	-- up-and-over: tipped flat (90 degrees about X) and lying just under the roof slab, its outer edge on the closed
	-- gate's street face, so nothing hangs in the opening between the camera and a raider inside
	local gateClosed = CFrame.new(220, BANK_FLOOR_Y + 4.5, -214.6)
	local gateOpen = CFrame.new(220, roofBottom - BANK_GATE_CEILING_GAP - 0.3, -214.9 - 4.5) * CFrame.Angles(math.rad(90), 0, 0)
	local gate = part({
		Name = "BankGate",
		Size = Vector3.new(10, 9, 0.6),
		CFrame = gateOpen,
		Color = Color3.fromRGB(52, 54, 52),
		Material = Enum.Material.DiamondPlate,
		CanCollide = false,
		Parent = bankModel,
	})
	gate.CanQuery = false
	gate.CanTouch = false
	local act = WorldConfig.Activity
	gate:SetAttribute(act.RuntimeDoorAttr, true) -- WE_RuntimeDoor
	gate:SetAttribute(act.GateStateAttr, "open") -- WE_GateState
	gate:SetAttribute("WE_ClosedCFrame", gateClosed)
	gate:SetAttribute("WE_OpenCFrame", gateOpen)

	-- the round vault door on the back wall (a disc 7.6 across, 1 thick, its face 1 stud into the hall)
	part({
		Name = "VaultDoor",
		Size = Vector3.new(1, 7.6, 7.6),
		CFrame = CFrame.new(220, BANK_FLOOR_Y + 4.2, -234.3) * CFrame.Angles(0, math.rad(90), 0),
		Shape = Enum.PartType.Cylinder,
		Color = Color3.fromRGB(150, 150, 142),
		Material = Enum.Material.DiamondPlate,
		CanCollide = true,
		Parent = bankModel,
	})

	-- the vault: a flat gold pad inside the hall (unrotated, so the label's world offset stays straight up). BANK_VAULT_Z
	-- keeps VaultRadius 12 inside the walls at the back and sides (a raider pressed against the back wall outside
	-- stands >= 12.5 from its centre) and lets it reach just out of the opening, in view of the front guards
	local vault = part({
		Name = "VaultPad",
		Size = Vector3.new(12, 0.12, 12),
		Position = Vector3.new(220, BANK_FLOOR_Y + 0.06, BANK_VAULT_Z),
		Color = Color3.fromRGB(214, 176, 72),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		Parent = bankModel,
	})
	vault.CanQuery = false
	vault.CanTouch = false
	vault:SetAttribute("BankId", "EmpireBank")
	CollectionService:AddTag(vault, "WE_BankVault")

	-- concrete planters on the plaza front (x 203..209 / 231..237, z -207..-205, 3 tall)
	for _, pl in ipairs({ { Name = "PlanterW", X = 206 }, { Name = "PlanterE", X = 234 } }) do
		part({
			Name = pl.Name,
			Size = Vector3.new(6, 3, 2),
			Position = Vector3.new(pl.X, BANK_FLOOR_Y + 1.5, -206),
			Color = Color3.fromRGB(148, 144, 132),
			Material = Enum.Material.Concrete,
			CanCollide = true,
			Parent = bankModel,
		})
	end

	-- the state banner standing on the roof, facing Bank Street
	local banner = part({
		Name = "StateBanner",
		Size = Vector3.new(8, 6, 0.4),
		Position = Vector3.new(226, roofTop + 3, -232),
		Color = BANK_BANNER_OPEN,
		Material = Enum.Material.Fabric,
		CanCollide = false,
		Parent = bankModel,
	})
	banner.CanQuery = false
	banner.CanTouch = false

	-- the Town.Bank.* anchors (Door, Vault, Loot, guard posts G1..G5, reinforcements R1 / R2) on the plaza: 0 parts.
	-- BankRaidService takes its guard posts from the G anchors (else BankRaidConfig.GuardPosts); OpsService reads all.
	local stamped = 0
	withWorldModule("ActivityAnchors", function(ActivityAnchors: any)
		for _, row in ipairs(WorldConfig.Town.BankAnchors) do
			if ActivityAnchors.Stamp(plaza, ActivityAnchors.FromRow(row)) ~= nil then
				stamped += 1
			end
		end
	end)
	bankModel.Parent = root -- streaming2 S4: parented whole
	local nParts = 0
	for _, d in ipairs(bankModel:GetDescendants()) do
		if d:IsA("BasePart") then
			nParts += 1
		end
	end
	print(string.format("[WAR EMPIRE] MapSetup: Empire Bank hall built (%d parts, %d Town.Bank anchors)", nParts, stamped))
end

function MapSetup.Run()
	-- Normal gravity so characters fall onto terrain (not float/void)
	Workspace.Gravity = 196.2

	-- World v2 (spec §2): WorldAtmosphere owns Lighting / Sky / Atmosphere and the day cycle (warm haze, no blue below
	-- the horizon, agent F's ambient, one step every 6 s). Idempotent: a second Run replaces the day loop.
	if not withWorldModule("WorldAtmosphere", function(m: any)
		m.Apply()
	end) then
		applyClassicLighting()
	end

	local root = ensureFolder("WarEmpireSetup", Workspace)
	local map = ensureFolder("Map", root)
	-- Continuous collide floor: thick, large, explicit CanCollide — never reads as sky
	-- v70 (§12.1): tiled (16 x 1800 ground, 25 x 2000 safety catch, 4 pieces per berm / void-wall side)
	buildGroundTiles(map)
	buildSafetyUnderfloor(map)
	buildEdgeBerms(map)
	buildInvisibleWalls(map)
	-- Road grid scaled to plot ring (optional visual guide)
	-- v70 (§6): with the waterways every road stops WaterConfig.RoadEndSetback studs before the first water (no
	-- bridges; every land outpost is inside the ring) and is built as two parts split at 0 (<name>_A: Min..0,
	-- <name>_B: 0..Max, each <= 1752 studs). Each end gets a collidable jersey barrier in Map.RoadEnds.
	local roadEndsFolder: Folder? = nil
	local function roadEndBarrier(name: string, alongX: boolean, across: number, at: number)
		local rb = WaterConfig.RoadEndBarrier
		if roadEndsFolder == nil then
			local f = Instance.new("Folder")
			f.Name = "RoadEnds"
			f.Parent = map
			roadEndsFolder = f
		end
		local centre = if alongX
			then Vector3.new(at, GROUND_TOP_Y + rb.Height * 0.5, across)
			else Vector3.new(across, GROUND_TOP_Y + rb.Height * 0.5, at)
		local barrier = part({
			Name = name,
			Size = if alongX then Vector3.new(rb.Depth, rb.Height, rb.Width) else Vector3.new(rb.Width, rb.Height, rb.Depth),
			Position = centre,
			Color = Color3.fromRGB(196, 192, 180),
			Material = Enum.Material.Concrete,
			CanCollide = true,
			Parent = roadEndsFolder,
		})
		part({
			Name = "Stripe",
			Size = if alongX then Vector3.new(rb.Depth + 0.1, 0.5, rb.Width) else Vector3.new(rb.Width, 0.5, rb.Depth + 0.1),
			Position = Vector3.new(centre.X, GROUND_TOP_Y + 1.6, centre.Z),
			Color = Color3.fromRGB(236, 190, 40),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = barrier,
		})
	end
	-- alongX: the road runs along X (RoadZ<z>, at z = across) or along Z (RoadX<x>, at x = across)
	local function worldRoad(name: string, alongX: boolean, across: number)
		local ends = if WaterConfig.Enabled == true then WaterConfig.RoadEnds[name] else nil
		local spans: { { Name: string, A: number, B: number } } = {}
		if ends and ends.Min < 0 and ends.Max > 0 then
			table.insert(spans, { Name = name .. "_A", A = ends.Min, B = 0 })
			table.insert(spans, { Name = name .. "_B", A = 0, B = ends.Max })
		elseif ends then
			table.insert(spans, { Name = name .. "_A", A = ends.Min, B = ends.Max })
		else
			-- no waterways: full length, still in pieces under the part-size cap
			local piece = GROUND_SIZE / EDGE_PIECES
			for k, c in ipairs(tileCentres(EDGE_PIECES, piece)) do
				table.insert(spans, { Name = name .. "_" .. k, A = c - piece * 0.5, B = c + piece * 0.5 })
			end
		end
		for _, sp in ipairs(spans) do
			local mid, len = (sp.A + sp.B) * 0.5, sp.B - sp.A
			part({
				Name = sp.Name,
				Size = if alongX then Vector3.new(len, 0.15, 14) else Vector3.new(14, 0.15, len),
				Position = if alongX
					then Vector3.new(mid, GROUND_TOP_Y + 0.05, across)
					else Vector3.new(across, GROUND_TOP_Y + 0.05, mid),
				Color = Color3.fromRGB(50, 52, 48),
				Material = Enum.Material.Asphalt,
				CanCollide = false,
				Parent = map,
			})
		end
		if ends then
			roadEndBarrier(name .. "_Min", alongX, across, ends.Min + WaterConfig.RoadEndBarrier.Depth * 0.5)
			roadEndBarrier(name .. "_Max", alongX, across, ends.Max - WaterConfig.RoadEndBarrier.Depth * 0.5)
		end
	end
	for _, z in ipairs({ -PLOT_RING, 0, PLOT_RING }) do
		worldRoad("RoadZ" .. z, true, z)
	end
	for _, x in ipairs({ -PLOT_RING, 0, PLOT_RING }) do
		worldRoad("RoadX" .. x, false, x)
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

	-- Yellow centre-line dashes. World v2 W1 (spec §7.1): 40 painted SmoothPlastic dashes (was 80 Neon), only on the
	-- approaches: a dash stays when it lies within DASH_APPROACH studs (3 dashes) along its road of a visible crossing
	-- (the town at 0,0 and the six ring crossings; the crossings at 0,±800 are under plots 3 / 4) and never under a plot
	-- pad (those were hidden under the pad anyway). Road markings: RoadDash* is exempt from the road-corridor rules.
	local DASH_APPROACH = 270
	local ROAD_LINES = { -PLOT_RING, 0, PLOT_RING }
	local function underPlotPad(x: number, z: number): boolean
		local half = PLOT_PAD_SIZE * 0.5 + 4
		for _, pp in ipairs(PLOT_POSITIONS) do
			if math.abs(x - pp.X) <= half and math.abs(z - pp.Z) <= half then
				return true
			end
		end
		return false
	end
	local function nearVisibleCrossing(alongX: boolean, across: number, at: number): boolean
		for _, c in ipairs(ROAD_LINES) do
			local cx = if alongX then c else across
			local cz = if alongX then across else c
			if not underPlotPad(cx, cz) and math.abs(at - c) <= DASH_APPROACH then
				return true
			end
		end
		return false
	end
	local function roadDash(name: string, alongX: boolean, across: number, at: number)
		local x = if alongX then at else across
		local z = if alongX then across else at
		if underPlotPad(x, z) or not nearVisibleCrossing(alongX, across, at) then
			return
		end
		part({
			Name = name,
			Size = if alongX then Vector3.new(8, 0.12, 1.2) else Vector3.new(1.2, 0.12, 8),
			Position = Vector3.new(x, GROUND_TOP_Y + 0.12, z),
			Color = Color3.fromRGB(240, 210, 60),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = map,
		})
	end
	for _, z in ipairs(ROAD_LINES) do
		for i = -8, 8 do
			if i ~= 0 then
				roadDash("RoadDashZ" .. z .. "_" .. i, true, z, i * 90)
			end
		end
	end
	for _, x in ipairs({ -PLOT_RING, PLOT_RING }) do
		for i = -8, 8 do
			if i ~= 0 then
				roadDash("RoadDashX" .. x .. "_" .. i, false, x, i * 90)
			end
		end
	end

	local bases = ensureFolder("Bases", root)
	for plotId, pos in ipairs(PLOT_POSITIONS) do
		-- v70: the plot frame. Everything on the plot is plot-local and placed through F, so the whole base turns to
		-- face the map centre when BaseLayoutConfig.FaceMapCentre is on (F = CFrame.new(pos) while it is off).
		local F = BaseLayout.PlotCFrame(pos)
		local plotFolder = Instance.new("Folder")
		plotFolder.Name = "Plot" .. plotId
		plotFolder:SetAttribute("PlotYaw", BaseLayout.PlotYaw(pos))
		plotFolder:SetAttribute("PlotForward", BaseLayout.PlotForward(pos))
		plotFolder.Parent = bases

		local pad = part({
			Name = "PlotPad",
			Size = Vector3.new(PLOT_PAD_SIZE, 1, PLOT_PAD_SIZE),
			CFrame = F, -- v70: the pad carries the plot yaw (services read pad.CFrame for plot-local ↔ world)
			Color = COL_PAD,
			Material = Enum.Material.Concrete,
			Parent = plotFolder,
		})
		pad:SetAttribute("PlotId", plotId)
		CollectionService:AddTag(pad, TAG_BASE)
		paintEdge(pad, COL_PAD_EDGE, 0.55)

		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "PlayerSpawn"
		spawn.Size = Vector3.new(10, 1, 10)
		do
			local sp = if BaseLayout.Enabled() then BaseLayout.Config().SpawnOffset else { X = 0, Z = 55 }
			spawn.CFrame = F * CFrame.new(sp.X, 2, sp.Z) -- main gate side, gate defence and spawn facing turn with it
		end
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.BrickColor = BrickColor.new("Dark green")
		spawn.Material = Enum.Material.SmoothPlastic -- v70 (HUD spec §5): painted spawn pad (was Neon)
		spawn.Parent = plotFolder

		-- v67: no giant "BASE n · Walk pads to BUY · E / B menu" label over the plot (HUD + pad cards explain buying)
		-- v70 (HUD spec §5): no plot beacon (neon tip + glow disc) at the rear of the plot either

		for i, def in ipairs(STRUCTURES) do
			local col = (i - 1) % STRUCT_COLS
			local row = math.floor((i - 1) / STRUCT_COLS)
			local offset = STRUCT_ORIGIN + Vector3.new(col * STRUCT_GAP, 0, row * STRUCT_GAP)
			buildStructureKit(plotFolder, plotId, pos, offset, def)
		end

		-- v72: static arrows off by default (they pointed back at the gate; the per-player NEXT pointer replaces them)
		if not BaseLayout.Enabled() or BaseLayout.Config().FloorChevrons ~= false then
			paintPlotFloorChevrons(plotFolder, pos)
		end
		dressPlotPadSandbags(plotFolder, pos)

		-- Training Yard targets (soldiers "train" → server cash; visual only)
		-- v68: the whole yard group (targets, workers, pad, stalls, anchors) moves to Courtyard.TrainingYard
		-- v70: yardShift and every offset below are plot-local (placed through F)
		local yardShift = Vector3.zero
		if BaseLayout.Enabled() then
			local ty = BaseLayout.Config().Courtyard.TrainingYard
			yardShift = Vector3.new(ty.X - -14, 0, ty.Z - 48)
		end
		local yardFolder = Instance.new("Folder")
		yardFolder.Name = "TrainingYard"
		yardFolder.Parent = plotFolder
		for ti = 1, 3 do
			local tLocal = yardShift + Vector3.new(-50 + ti * 18, 3.5, 48)
			local target = part({
				Name = "TrainingTarget" .. ti,
				Size = Vector3.new(4, 6, 0.6),
				CFrame = F * CFrame.new(tLocal),
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
				CFrame = F * CFrame.new(tLocal + Vector3.new(0, -5, 0)),
				Color = Color3.fromRGB(70, 70, 70),
				Material = Enum.Material.Metal,
				CanCollide = true,
				Parent = yardFolder,
			})
			part({
				Name = "TargetBullseye" .. ti,
				Size = Vector3.new(1.6, 1.6, 0.35),
				CFrame = F * CFrame.new(tLocal + Vector3.new(0, 0.5, -0.2)),
				Color = Color3.fromRGB(240, 220, 60),
				Material = Enum.Material.SmoothPlastic, -- v70: painted (no decorative Neon)
				CanCollide = false,
				Parent = yardFolder,
			})
		end
		-- Training workers (visual only — income is SoldierService tick). v70 (HUD spec §5): no name tag over them
		for wi = 1, 2 do
			-- fb2: y = YardPad top (0.7) + 2.1, so the lifted kit's feet stand on the yard pad (was 2.6: 0.2 lower)
			local wLocal = yardShift + Vector3.new(-40 + wi * 20, 2.8, 42)
			-- P0: dress as Worker→Infantry mesh (force catalog even in StudioSkipWorldDressing)
			makeSoldierKit(
				yardFolder,
				"TrainingWorker" .. wi,
				F * CFrame.new(wLocal) * CFrame.Angles(0, math.rad(180), 0),
				Color3.fromRGB(70, 85, 55),
				nil,
				Color3.fromRGB(140, 150, 130), -- muted
				50,
				"Worker",
				nil
			)
		end
		-- Target ring + base plate polish
		part({
			Name = "YardPad",
			Size = Vector3.new(55, 0.6, 18),
			CFrame = F * CFrame.new(yardShift + Vector3.new(-14, 0.4, 48)),
			Color = Color3.fromRGB(48, 52, 42),
			Material = Enum.Material.Concrete,
			CanCollide = true,
			Parent = yardFolder,
		})
		-- v70 (HUD spec §5): no "+$/tick" earn placeholder billboard on the yard pad
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
				local sOrigin = yardShift + soff -- plot-local
				local stall = Instance.new("Folder")
				stall.Name = "SquadStall" .. si
				stall.Parent = stallFolder
				-- Floor plate
				part({
					Name = "StallFloor",
					Size = Vector3.new(12, 0.4, 10),
					CFrame = F * CFrame.new(sOrigin + Vector3.new(0, 0.35, 0)),
					Color = Color3.fromRGB(70, 68, 52),
					Material = Enum.Material.WoodPlanks,
					CanCollide = true,
					Parent = stall,
				})
				-- Tent host (catalog Tent via TryAttachPropVisual)
				local tentHost = part({
					Name = "TentHost",
					Size = Vector3.new(8, 4, 6),
					CFrame = F * CFrame.new(sOrigin + Vector3.new(0, 2.4, -1)),
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
					CFrame = F * CFrame.new(sOrigin + Vector3.new(4.5, 1.2, 2)),
					Color = Color3.fromRGB(95, 80, 55),
					Material = Enum.Material.Wood,
					CanCollide = true,
					Parent = stall,
				})
				local crateB = part({
					Name = "CrateHostB",
					Size = Vector3.new(2.0, 1.8, 2.0),
					CFrame = F * CFrame.new(sOrigin + Vector3.new(4.5, 3.0, 2)),
					Color = Color3.fromRGB(85, 70, 48),
					Material = Enum.Material.Wood,
					CanCollide = true,
					Parent = stall,
				})
				local milCrate = part({
					Name = "MilCrateHost",
					Size = Vector3.new(2.4, 1.6, 1.8),
					CFrame = F * CFrame.new(sOrigin + Vector3.new(-4.2, 1.0, 2.2)),
					Color = Color3.fromRGB(55, 70, 50),
					Material = Enum.Material.Metal,
					CanCollide = true,
					Parent = stall,
				})
				-- Sandbags
				local sandHost = part({
					Name = "SandbagHost",
					Size = Vector3.new(6, 1.1, 1.3),
					CFrame = F * CFrame.new(sOrigin + Vector3.new(0, 0.75, 4.2)),
					Color = Color3.fromRGB(130, 115, 80),
					Material = Enum.Material.Sand,
					CanCollide = true,
					Parent = stall,
				})
				-- Lantern host (v70 light budget: the lantern carries no PointLight)
				local lanternHost = part({
					Name = "LanternHost",
					Size = Vector3.new(0.6, 1.2, 0.6),
					CFrame = F * CFrame.new(sOrigin + Vector3.new(-3.5, 2.2, -2.5)),
					Color = Color3.fromRGB(180, 140, 60),
					Material = Enum.Material.Metal,
					CanCollide = false,
					Parent = stall,
				})
				-- v34: stall roles use distinct VisualAssetConfig Character IDs + Part dress
				local stallRoles = {
					{ Kind = "Infantry", Label = "INFANTRY", Body = Color3.fromRGB(70, 85, 55), Accent = Color3.fromRGB(180, 220, 120) },
					{ Kind = "HeavyInfantry", Label = "HEAVY", Body = Color3.fromRGB(50, 55, 48), Accent = Color3.fromRGB(230, 160, 50) },
					{ Kind = "Guard", Label = "GUARD", Body = Color3.fromRGB(45, 55, 70), Accent = Color3.fromRGB(90, 140, 220) },
				}
				local roleDef = stallRoles[((si - 1) % #stallRoles) + 1]
				-- fb2: y = StallFloor top (0.55) + 2.15: feet within 0.05 of the stall floor and of the plaza road under stall 1
				local soldierCf = F * CFrame.new(sOrigin + Vector3.new(-1.5, 2.7, 1.5)) * CFrame.Angles(0, math.rad(160 + si * 8), 0)
				makeSoldierKit(
					stall,
					"Stall" .. roleDef.Kind .. si,
					soldierCf,
					roleDef.Body,
					nil,
					roleDef.Accent,
					80,
					roleDef.Kind,
					nil
				)
				-- v70 (HUD spec §5): the stall's role is a painted board on the sandbags facing the yard front (was a
				-- floating NPCLabel over the soldier)
				local stallSign = part({
					Name = "StallSign",
					Size = Vector3.new(4.4, 1.2, 0.2),
					CFrame = F * CFrame.new(sOrigin + Vector3.new(0, 1.9, 4.2)),
					Color = Color3.fromRGB(78, 64, 44),
					Material = Enum.Material.WoodPlanks,
					CanCollide = false,
					Parent = stall,
				})
				stallSign.CanQuery = false
				stallSign.CanTouch = false
				WorldLabel.Surface(stallSign, Enum.NormalId.Back, roleDef.Label, { Name = "WE_StallSign", Color = roleDef.Accent })
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

		-- Invisible anchors (ManualDropperService / SoldierService place the yard dropper and cash pops from them).
		-- v70 (HUD spec §5): no yard title billboard and no glowing worker → target beams (the last always-on
		-- glowing lines in a base).
		part({
			Name = "YardAnchor",
			Size = Vector3.new(1, 1, 1),
			CFrame = F * CFrame.new(yardShift + Vector3.new(-14, 8, 48)),
			Transparency = 1,
			CanCollide = false,
			Parent = yardFolder,
		})
		part({
			Name = "YardEarnAnchor",
			Size = Vector3.new(1, 1, 1),
			CFrame = F * CFrame.new(yardShift + Vector3.new(-14, 6, 42)),
			Transparency = 1,
			CanCollide = false,
			Parent = yardFolder,
		})
		-- Design densify: 8–12 realistic warzone props per plot (always-on Part kits; pcall catalog)
		do
			local okDress, errDress = pcall(function()
				local wz = Instance.new("Folder")
				wz.Name = "PlotWarzone"
				wz.Parent = plotFolder
				local count = 12
				-- v68: fixed spots along the walls / rear zone (the 58-78 stud ring lands on the new plaza)
				local spots = if BaseLayout.Enabled() then BaseLayout.Config().WarzoneSpots else nil
				if spots then
					count = #spots
				end
				for i = 1, count do
					local ang = (i / count) * math.pi * 2
					local rad = 58 + (i % 3) * 10
					-- v70: plot-local spot, placed through the plot frame F (props turn with the plot)
					local o = Vector3.new(math.cos(ang) * rad, 0.6, math.sin(ang) * rad)
					if spots then
						o = Vector3.new(spots[i].X, 0.6, spots[i].Z)
					end
					if i % 3 == 0 then
						-- sandbag berm (Metal/Sand — no neon)
						part({
							Name = "WZ_Sandbag" .. i,
							Size = Vector3.new(6, 1.2, 1.4),
							CFrame = F * CFrame.new(o),
							Color = Color3.fromRGB(130, 115, 80),
							Material = Enum.Material.Sand,
							CanCollide = true,
							Parent = wz,
						})
						part({
							Name = "WZ_SandbagTop" .. i,
							Size = Vector3.new(5.2, 0.9, 1.1),
							CFrame = F * CFrame.new(o + Vector3.new(0, 1.0, 0)),
							Color = Color3.fromRGB(120, 105, 75),
							Material = Enum.Material.Sand,
							CanCollide = true,
							Parent = wz,
						})
					elseif i % 3 == 1 then
						part({
							Name = "WZ_Crate" .. i,
							Size = Vector3.new(2.2, 2.0, 2.2),
							CFrame = F * CFrame.new(o + Vector3.new(0, 1.0, 0)),
							Color = Color3.fromRGB(95, 80, 55),
							Material = Enum.Material.Wood,
							CanCollide = true,
							Parent = wz,
						})
						part({
							Name = "WZ_Drum" .. i,
							Size = Vector3.new(1.4, 2.2, 1.4),
							CFrame = F * CFrame.new(o + Vector3.new(3, 1.1, 1)),
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
							CFrame = F * CFrame.new(o + Vector3.new(0, 0.7, 0)),
							Color = Color3.fromRGB(110, 105, 90),
							Material = Enum.Material.Concrete,
							CanCollide = true,
							Parent = wz,
						})
					end
				end
				-- Catalog densify InsertService — ALWAYS deferred (never block MapSetup.Run / remotes)
					task.defer(function()
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
			end)
			if not okDress then
				warn("[MapSetup] PlotWarzone densify failed (pads intact):", errDress)
			end
		end
		buildMoneyCollector(plotFolder, plotId, pos)
		buildLayoutGround(plotFolder, plotId, pos)
	end

	local territories = ensureFolder("Territories", root)
	for _, def in ipairs(territoryDefsInBuildOrder()) do
		local pos = def.Position
		local isOilRig = def.IsOilRig == true
		local isFort = def.IsFortress == true
		local gateSide = FORT_GATE_SIDE[def.Id]
		-- F10: a Home Outpost (TerritoryConfig.Starter row) is a 4-part kit: invisible marker (capture volume, tags,
		-- PlotId), ring, pole and flag. No stripe, no finial, no light (TerritoryService never adds one either).
		local isStarter = TerritoryConfig.IsStarterDef(def)
		local diameter = (def.Radius or 30) * 2
		-- streaming2 S4 (F12): the zone's marker, ring, pole and flag (and the stripe and finial off a Home Outpost) are
		-- one Atomic Model, so a client never has the marker without its <Id>_Flag sibling (TerritoryController's
		-- diamond lookup) or the flag without the marker. Siblings stay siblings: TerritoryService finds them from
		-- marker.Parent as before, the marker by its tags. Fort walls / keep / towers and rig decks / legs stay loose in
		-- Territories. Built unparented and parented once whole (below), so every piece is an initial descendant.
		-- Inert while Workspace.StreamingEnabled is false: the same parts, one level deeper.
		local zone = Instance.new("Model")
		zone.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		zone.Name = def.Id .. "_Zone"
		-- World v2 (spec §3.5): the capture marker keeps its Size (TerritoryCapture reads its half-diagonal) but is an
		-- invisible, non-colliding volume (it was a glowing 1.5-tall slab across five roads). The visible cue is the
		-- flat <Id>_Ring disc below; TerritoryService writes only the owner colour.
		local marker = part({
			Name = def.Id,
			Size = Vector3.new(diameter, 1.5, diameter),
			Position = pos,
			Color = def.Color,
			Transparency = 1,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = zone,
		})
		marker.CanQuery = false
		marker.CanTouch = false
		marker:SetAttribute("TerritoryId", def.Id)
		marker:SetAttribute("Radius", def.Radius or 30)
		marker:SetAttribute("OwnerType", "Neutral")
		marker:SetAttribute("OwnerUserId", 0)
		marker:SetAttribute("CaptureProgress", 0)
		if isStarter then
			-- F10: owner-only (TerritoryCapture counts only BaseService.GetOwnerUserId(PlotId)); clients read these to
			-- list / point at their OWN Home Outpost only
			marker:SetAttribute("PlotId", def.PlotId)
			marker:SetAttribute("IsStarter", true)
			marker:SetAttribute("OwnerOnly", def.OwnerOnly == true)
		end
		CollectionService:AddTag(marker, TAG_TERRITORY)
		CollectionService:AddTag(marker, TAG_CAPTURE)

		-- Zone name: the same stud-scaled label TerritoryService.ensureZoneLabel makes (it reuses WE_ZoneLabel), so the
		-- world never shows the old 220-stud "[NEUTRAL] · Stand to capture" card, even before the service starts
		WorldLabel.Create(marker, def.DisplayName or def.Id, {
			Name = "WE_ZoneLabel",
			Studs = Vector2.new(8, 1.6),
			Offset = Vector3.new(0, 16, 0),
			MaxDistance = 40,
		})

		-- Flat disc (spec §3.5): a Cylinder lying on its side, top at y 0.58 on the ground (on the deck top for a rig,
		-- sized to the 48-stud deck instead of overhanging the sea)
		local ringD = if isOilRig then math.min(diameter + 8, 46) else diameter + 8
		local ringTop = if isOilRig then pos.Y + 0.13 else GROUND_TOP_Y + 0.08
		local ring = part({
			Name = def.Id .. "_Ring",
			Size = Vector3.new(0.12, ringD, ringD),
			CFrame = CFrame.new(pos.X, ringTop - 0.06, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
			Color = def.Color,
			Transparency = 0.55,
			CanCollide = false,
			Material = Enum.Material.SmoothPlastic,
			Shape = Enum.PartType.Cylinder,
			Parent = zone,
		})
		ring.CanQuery = false
		ring.CanTouch = false
		ring:SetAttribute("TerritoryId", def.Id)

		part({
			Name = def.Id .. "_FlagPole",
			Size = Vector3.new(0.4, 14, 0.4),
			Position = pos + Vector3.new(0, 7, 0),
			Color = Color3.fromRGB(55, 55, 55),
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = zone,
		})
		local flag = part({
			Name = def.Id .. "_Flag",
			Size = Vector3.new(5.5, 3.2, 0.22),
			Position = pos + Vector3.new(2.8, 12.2, 0),
			Color = def.Color,
			Material = Enum.Material.SmoothPlastic, -- painted (TerritoryService keeps it SmoothPlastic)
			CanCollide = false,
			Transparency = 0.08,
			Parent = zone,
		})
		flag:SetAttribute("TerritoryId", def.Id)
		flag:SetAttribute("WE_Flag", true)
		if isStarter then
			zone.Parent = territories -- streaming2 S4: parented whole
			continue -- F10: the Home Outpost kit ends here (marker, ring, pole, flag: 4 parts, no light)
		end
		part({
			Name = def.Id .. "_FlagStripe",
			Size = Vector3.new(5.5, 0.45, 0.28),
			Position = pos + Vector3.new(2.8, 12.2, 0),
			Color = Color3.fromRGB(245, 245, 245),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Transparency = 0.15,
			Parent = zone,
		})
		part({
			Name = def.Id .. "_Finial",
			Size = Vector3.new(0.7, 0.7, 0.7),
			Position = pos + Vector3.new(0, 14.4, 0),
			Color = Color3.fromRGB(230, 190, 60),
			Material = Enum.Material.SmoothPlastic,
			Shape = Enum.PartType.Ball,
			CanCollide = false,
			Parent = zone,
		})
		zone.Parent = territories -- streaming2 S4: parented whole, before the loose fort / rig pieces

		-- World v2 W1: no beacon pole in the capture zone (the flag pole and the disc mark it)

		-- Coastal oil platform deck + legs + harder NPC guards
		if isOilRig then
			local deckY = pos.Y
			local deck = part({
				Name = def.Id .. "_Deck",
				Size = Vector3.new(48, 2.5, 48),
				Position = Vector3.new(pos.X, deckY - 1.2, pos.Z),
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
						Position = Vector3.new(pos.X + ox, deckY / 2, pos.Z + oz),
						Color = Color3.fromRGB(60, 65, 70),
						Material = Enum.Material.Metal,
						Parent = territories,
					})
				end
			end
			-- Derrick + crane tip + painted deck rim (visual kits v2; World v2: no Neon)
			part({
				Name = def.Id .. "_Derrick",
				Size = Vector3.new(4, 22, 4),
				Position = Vector3.new(pos.X + 14, deckY + 11, pos.Z + 14),
				Color = Color3.fromRGB(180, 140, 50),
				Material = Enum.Material.Metal,
				CanCollide = false,
				Parent = territories,
			})
			part({
				Name = def.Id .. "_CraneArm",
				Size = Vector3.new(14, 1.2, 1.2),
				Position = Vector3.new(pos.X + 7, deckY + 20, pos.Z + 14),
				Color = Color3.fromRGB(160, 120, 45),
				Material = Enum.Material.Metal,
				CanCollide = false,
				Parent = territories,
			})
			part({
				Name = def.Id .. "_HelipadMark",
				Size = Vector3.new(10, 0.3, 10),
				Position = Vector3.new(pos.X - 12, deckY + 0.2, pos.Z - 12),
				Color = Color3.fromRGB(40, 45, 50),
				Material = Enum.Material.Metal,
				CanCollide = false,
				Parent = territories,
			})
			part({
				Name = def.Id .. "_DeckRim",
				Size = Vector3.new(46, 0.35, 0.5),
				Position = Vector3.new(pos.X, deckY + 0.3, pos.Z + 23),
				Color = Color3.fromRGB(255, 180, 60),
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				Parent = territories,
			})
			-- World v2 W1: no "OIL PLATFORM · Hard guards" card (the zone label names the rig; CLAUDE.md: no debug labels)
			-- Stairs from deck down to ground (prevent 28-stud death plunge)
			-- v70 (§7.1): on the waterways map the stairs are the rig's pier across the lagoon, snapped to the X axis
			-- toward the map centre (Alpha steps x 1765 → 1684, approach pad on the inner bank; Bravo mirrored)
			local inland = if WaterConfig.RigPierAxisAligned == true
				then Vector3.new(-math.sign(pos.X), 0, 0)
				else Vector3.new(-pos.X, 0, -pos.Z)
			if inland.Magnitude < 0.1 then
				inland = Vector3.new(-pos.X, 0, -pos.Z)
			end
			buildOilDeckRamp(territories, def.Id, pos, inland)
			if WaterConfig.Enabled == true then
				-- Concrete footing round each leg at the waterline: a boat's land probe that starts inside a 28-tall leg
				-- misses the leg, but sees the footing top (2.5)
				local lf = WaterConfig.RigLegFooting
				for _, ox in ipairs({ -legOff, legOff }) do
					for _, oz in ipairs({ -legOff, legOff }) do
						part({
							Name = def.Id .. "_LegFooting",
							Size = lf,
							Position = Vector3.new(pos.X + ox, GROUND_TOP_Y + lf.Y * 0.5, pos.Z + oz),
							Color = Color3.fromRGB(120, 118, 110),
							Material = Enum.Material.Concrete,
							CanCollide = true,
							Parent = territories,
						})
					end
				end
				-- [J5] submerged rubble footing under the pier's low end (rig-local Near..Far along the pier, ±HalfWidth
				-- across, y 0.5..2.5): capital ships' collidable bridges (up to 13.1 above the water) would ram steps
				-- 5-10 and the shelf; every land probe sees this top first, so boats brake before it. Walkable.
				local pf = WaterConfig.RigPierFooting
				local dir = inland.Unit
				local mid = Vector3.new(pos.X, GROUND_TOP_Y + pf.Height * 0.5, pos.Z) + dir * ((pf.Near + pf.Far) * 0.5)
				part({
					Name = def.Id .. "_PierFooting",
					Size = Vector3.new(pf.HalfWidth * 2, pf.Height, pf.Far - pf.Near),
					CFrame = CFrame.lookAt(mid, mid + dir),
					Color = Color3.fromRGB(78, 76, 70),
					Material = Enum.Material.Concrete,
					Transparency = 0,
					CanCollide = true,
					Parent = territories,
				})
			end
		end

		-- Fortress walls / keep (named forts with higher stipend)
		if isFort then
			local wallH = 8
			local wallT = 2.2
			local span = (def.Radius or 48) * 1.35
			local wallDefs = {
				{ Vector3.new(span * 2, wallH, wallT), Vector3.new(0, wallH / 2, span) },
				{ Vector3.new(span * 2, wallH, wallT), Vector3.new(0, wallH / 2, -span) },
				{ Vector3.new(wallT, wallH, span * 2), Vector3.new(span, wallH / 2, 0) },
				{ Vector3.new(wallT, wallH, span * 2), Vector3.new(-span, wallH / 2, 0) },
			}
			-- World v2 (spec §3.4): the wall facing the fort's nearest road (GateSide: 1 = +Z wall, -1 = -Z wall) is two
			-- pieces with a FORT_GATE_WIDTH gap, so infantry and vehicles can drive in (the fort was a closed box)
			local gateWall = if gateSide == 1 then 1 elseif gateSide == -1 then 2 else nil
			for wi, wd in ipairs(wallDefs) do
				if wi == gateWall then
					local pieceLen = (span * 2 - FORT_GATE_WIDTH) * 0.5
					for k, sgn in ipairs({ -1, 1 }) do
						part({
							Name = def.Id .. "_Wall" .. wi .. (if k == 1 then "" else "b"),
							Size = Vector3.new(pieceLen, wallH, wallT),
							Position = pos + wd[2] + Vector3.new(sgn * (FORT_GATE_WIDTH * 0.5 + pieceLen * 0.5), 0, 0),
							Color = Color3.fromRGB(95, 90, 75),
							Material = Enum.Material.Concrete,
							Parent = territories,
						})
					end
				else
					part({
						Name = def.Id .. "_Wall" .. wi,
						Size = wd[1],
						Position = pos + wd[2],
						Color = Color3.fromRGB(95, 90, 75),
						Material = Enum.Material.Concrete,
						Parent = territories,
					})
				end
			end
			local keep = part({
				Name = def.Id .. "_Keep",
				Size = Vector3.new(14, 16, 14),
				Position = pos + Vector3.new(0, 8, 0),
				Color = def.Color,
				Material = Enum.Material.Brick,
				Parent = territories,
			})
			keep:SetAttribute("TerritoryId", def.Id)
			part({
				Name = def.Id .. "_KeepRoof",
				Size = Vector3.new(16, 1.5, 16),
				Position = pos + Vector3.new(0, 16.5, 0),
				Color = Color3.fromRGB(70, 65, 55),
				Material = Enum.Material.Metal,
				CanCollide = false,
				Parent = territories,
			})
			-- Corner towers + gate lintel
			for _, corner in ipairs({
				Vector3.new(span, 0, span),
				Vector3.new(span, 0, -span),
				Vector3.new(-span, 0, span),
				Vector3.new(-span, 0, -span),
			}) do
				part({
					Name = def.Id .. "_Tower",
					Size = Vector3.new(5, 12, 5),
					Position = pos + corner + Vector3.new(0, 6, 0),
					Color = Color3.fromRGB(85, 80, 65),
					Material = Enum.Material.Brick,
					Parent = territories,
				})
			end
			-- SmoothPlastic lintel over the gate (was a Neon strip on a wall with no gate); non-colliding, so it never
			-- snags a tall vehicle
			local gz = if gateSide == -1 then -span else span
			local lintel = part({
				Name = def.Id .. "_GateLintel",
				Size = Vector3.new(FORT_GATE_WIDTH + 2, 1, wallT + 0.4),
				Position = pos + Vector3.new(0, wallH - 0.5, gz),
				Color = def.Color,
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				Parent = territories,
			})
			lintel.CanQuery = false
			-- World v2 W1: no "FORTRESS · High stipend" card (the zone label names the fort; no debug labels)
		end
	end

	-- World v2 (spec §3.3): spawn pads and anchors come from WorldConfig.Spawns (the three makeSpawnFolder rings at
	-- 650 / 550 / 500 are gone: their pads sat on the roads, carried Neon edges, H marks and a beacon pole through the jeep).
	--   VehicleSpawns  10 garage pads (WE_VehicleSpawn): painted Concrete aprons + a painted kerb; the 6 gate pads carry a
	--                  1-post "Garage" sign (SurfaceGui, <= 80 studs) on the back edge, the 4 pool pads none (lane BK: the
	--                  world sign budget); no beacon, no billboard, no Neon. Gate_P1..P6 sit
	--                  62 studs outside each plot's front gate (plot-local, so they turn with the plot) and face the plot
	--                  forward; the pools face Yaw. VehicleService spawns on the pad heading (yawOf(pad.CFrame)).
	--   NPCSpawns      10 invisible anchors (WE_NPCSpawn) in the Quarry / Ridge / Dune camps (CombatNPC.GatherSpawns)
	--   EventSpawns    6 invisible anchors (WE_EventSpawn) (SupplyDropService lands the crate on the ground below)
	local spawnCfg = WorldConfig.Spawns
	-- v68: nothing spawns within PLOT_SPAWN_CLEARANCE of a plot pad (a config typo would put a pad inside a base)
	local function nearAnyPlot(p: Vector3, halfSize: number): boolean
		local half = PLOT_PAD_SIZE * 0.5 + PLOT_SPAWN_CLEARANCE + halfSize
		for _, pp in ipairs(PLOT_POSITIONS) do
			if math.abs(p.X - pp.X) < half and math.abs(p.Z - pp.Z) < half then
				return true
			end
		end
		return false
	end
	-- garage pads: top 0.9 (a 0.4 lip over the desert floor, not the old 1.1 step), padSize from config
	local GARAGE_Y = GROUND_TOP_Y + 0.4 - spawnCfg.PadSize.Y * 0.5
	local garageFolder = ensureFolder("VehicleSpawns", root)
	for _, def in ipairs(spawnCfg.Garage) do
		local cf: CFrame? = nil
		if def.PlotId ~= nil then
			local plotPos = PLOT_POSITIONS[def.PlotId]
			if plotPos then
				local at = BaseLayout.PlotPoint(plotPos, def.LocalX or 0, def.LocalZ or 0)
				-- face the plot forward (the pad's LookVector = the plot front, away from the gate)
				local fwd = BaseLayout.PlotForward(plotPos)
				local c = Vector3.new(at.X, GARAGE_Y, at.Z)
				cf = CFrame.lookAt(c, c + fwd)
			end
		elseif def.X ~= nil and def.Z ~= nil then
			cf = CFrame.new(def.X, GARAGE_Y, def.Z) * CFrame.Angles(0, math.rad(def.Yaw or 0), 0)
		end
		if cf == nil then
			warn("[WAR EMPIRE] MapSetup: garage pad " .. def.Id .. " has no position — skipped")
			continue
		end
		if nearAnyPlot(cf.Position, spawnCfg.PadSize.X * 0.5) then
			warn("[WAR EMPIRE] MapSetup: garage pad " .. def.Id .. " is within PLOT_SPAWN_CLEARANCE of a plot")
		end
		local pad = part({
			Name = def.Id,
			Size = spawnCfg.PadSize,
			CFrame = cf,
			Color = COL_VEHICLE,
			Material = Enum.Material.Concrete,
			CanCollide = true,
			Parent = garageFolder,
		})
		CollectionService:AddTag(pad, TAG_VEHICLE)
		paintEdge(pad, COL_VEHICLE:Lerp(Color3.new(1, 1, 1), 0.55), 0.35)
		-- W3 step 2 lane BK (spec w3s2 §1.10): only the 6 gate pads (PlotId rows) carry the "Garage" sign; the 4 pool
		-- pads have no sign post, board or label, so the world sign budget (WorldConfig.Budgets.SurfaceGuis 17) holds the
		-- 6 gate pads, the Town board, EMPIRE BANK and the 9 POI boards
		if def.PlotId == nil then
			continue
		end
		-- 1-post sign on the back edge, the painted face toward the pad front (readable as you walk up to the pad)
		local back = spawnCfg.PadSize.Z * 0.5 + 0.4
		local topY = spawnCfg.PadSize.Y * 0.5
		local post = part({
			Name = "SignPost",
			Size = Vector3.new(0.35, 4.2, 0.35),
			CFrame = cf * CFrame.new(0, topY + 2.1, back),
			Color = Color3.fromRGB(60, 62, 58),
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = garageFolder,
		})
		post.CanQuery = false
		post.CanTouch = false
		local board = part({
			Name = "GarageSign",
			Size = Vector3.new(4.4, 1.3, 0.2),
			CFrame = cf * CFrame.new(0, topY + 4.4, back),
			Color = Color3.fromRGB(40, 48, 58),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = garageFolder,
		})
		board.CanQuery = false
		board.CanTouch = false
		-- v70 (HUD spec §5, mobile P1-11): device-neutral text, no key names
		WorldLabel.Surface(board, Enum.NormalId.Front, "Garage", { Name = "WE_PadSign", Color = Color3.fromRGB(200, 220, 255), MaxDistance = 80 })
	end
	-- invisible anchors: server-only readers (CombatNPC / SupplyDropService); no physics, no raycast target
	local function anchorFolder(name: string, tag: string, list: { any }, color: Color3)
		local folder = ensureFolder(name, root)
		for _, a in ipairs(list) do
			local at = Vector3.new(a.X, 1, a.Z)
			if nearAnyPlot(at, spawnCfg.AnchorSize.X * 0.5) then
				warn("[WAR EMPIRE] MapSetup: " .. name .. "." .. a.Id .. " is within PLOT_SPAWN_CLEARANCE of a plot")
			end
			local p = part({
				Name = a.Id,
				Size = spawnCfg.AnchorSize,
				Position = at,
				Color = color,
				Material = Enum.Material.SmoothPlastic,
				Transparency = 1,
				CanCollide = false,
				Parent = folder,
			})
			p.CanQuery = false
			p.CanTouch = false
			CollectionService:AddTag(p, tag)
		end
	end
	anchorFolder("NPCSpawns", TAG_NPC, spawnCfg.NPC, COL_NPC)
	anchorFolder("EventSpawns", TAG_EVENT, spawnCfg.Event, COL_EVENT)

	-- v70 waterways (spec_final §5): Modules.Waterways builds root.CoastalWater (the sea, the ring canal round the map,
	-- rig lagoons, the South Docks harbour, dock channels, sand banks). The old single WaterPlane and the HarborShelf
	-- (a collidable sandbar standing above the old sea surface) are gone. Guarded: without the module the map still
	-- builds (no public water).
	do
		local wwModule = script.Parent:FindFirstChild("Waterways")
		if wwModule and wwModule:IsA("ModuleScript") then
			local okWw, errWw = pcall(function()
				local Waterways = require(wwModule) :: any
				Waterways.Build(root)
			end)
			if not okWw then
				warn("[WAR EMPIRE] MapSetup: Waterways.Build failed (map continues without public water):", errWw)
			end
		else
			warn("[WAR EMPIRE] MapSetup: Modules.Waterways missing — no public water built")
		end
	end

	-- World v2 (spec §1.1–§1.5): WorldBounds builds <root>.WE_Skyline (48 Persistent parts) and <root>.WE_Bounds (invisible
	-- ground / air walls, seabed tint, far-shore lighthouse + freighter). WorldTerrain fills the Terrain canyon edge round
	-- the ring canal and the Bay in the background (about 2,000 fills, yielding; skipped when Workspace.Terrain is already
	-- stamped with WorldConfig.Terrain.Gen). Each call is guarded: a failure never stops the map build.
	withWorldModule("WorldBounds", function(m: any)
		m.Build(root)
	end)
	task.spawn(function()
		withWorldModule("WorldTerrain", function(m: any)
			m.Build()
		end)
	end)

	-- Naval spawn pontoons (WaterConfig.NavalPads: the 9 sea pads + 3 ring landings at road ends). Tagged WE_NavalSpawn
	-- only: a pad in the water must never be picked as a ground-vehicle / jeep spawn.
	-- World v2 (spec §3.3): the deck + 1 painted trim part (a lighter inset, so the pontoon reads as a pad from a boat);
	-- no beacon pole in the water, no Neon edge and no floating billboard. No painted name either: the world's painted
	-- signs stay within WorldConfig.Budgets.SurfaceGuis (17: 6 gate-pad garage signs, the Town board, EMPIRE BANK and the
	-- 9 POI boards) and the SurfaceGui hard cap. Boats spawn from the Garage menu, so nobody has to find a pontoon.
	do
		local navalFolder = ensureFolder("NavalSpawns", root)
		local padSize = WaterConfig.NavalPadSize
		for _, np in ipairs(WaterConfig.NavalPads) do
			local padAt = Vector3.new(np.X, 1.5, np.Z)
			local pad = part({
				Name = np.Name,
				Size = Vector3.new(padSize, 1.2, padSize),
				Position = padAt,
				Color = Color3.fromRGB(40, 70, 95),
				Material = Enum.Material.Concrete,
				CanCollide = true,
				Parent = navalFolder,
			})
			CollectionService:AddTag(pad, TAG_NAVAL)
			local trim = part({
				Name = np.Name .. "_Trim",
				Size = Vector3.new(padSize - 3, 0.06, padSize - 3),
				Position = padAt + Vector3.new(0, 0.6 + 0.03, 0),
				Color = Color3.fromRGB(70, 112, 140),
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				Parent = navalFolder,
			})
			trim.CanQuery = false
			trim.CanTouch = false
		end
	end

	-- World v2 W1 (spec §1.6, §5 H6): the NPCPlaceholders block is gone: 20 static soldier statues (4 "HOSTILE" on the
	-- NPC pads, 4 per oil rig, 4 per fort) that never moved, carried a WE_NPC tag squads shot at, and stood on roads.
	-- Guards and hostiles are live CombatService NPCs (NPC anchors above, TerritoryConfig GuardNPCType).

	-- Empire Bank (W3 step 2 lane BK): the walk-in hall, its vault pad, open gate, state banner and Town.Bank.* anchors
	-- (buildEmpireBank above). Bank guards are live CombatService NPCs spawned by BankRaidService on the G anchors.
	buildEmpireBank(root)

	local tutorialFolder = ensureFolder("TutorialMarkers", root)
	local function tutorialMarker(name, pos, color, stepId)
		-- Hidden by default; TutorialController reveals only the active step (no billboard spam).
		-- v70 (HUD spec §5): an anchor only: no tutorial debug billboard and no Neon slab (the tutorial beam and the
		-- highlight are the cue).
		local p = part({
			Name = name,
			Size = Vector3.new(7, 1.2, 7),
			Position = pos,
			Color = color,
			Material = Enum.Material.SmoothPlastic,
			Transparency = 1,
			CanCollide = false,
			Parent = tutorialFolder,
		})
		p:SetAttribute("TutorialStepId", stepId or name)
		CollectionService:AddTag(p, TAG_TUTORIAL)
		-- No beacon / ring clutter — waypoint beam is enough
		return p
	end

	local plot1 = PLOT_POSITIONS[1]
	-- Offsets track Plot1 spawn / structure grid (STRUCT_ORIGIN + gaps); v68: layout consoles when enabled
	local function structureMarkerPos(structureId: string, gridOffset: Vector3): Vector3
		local cf = BaseLayout.ConsoleCFrame(plot1, structureId)
		if cf then
			return cf.Position + Vector3.new(0, 1.4, 0)
		end
		return BaseLayout.PlotPoint(plot1, gridOffset.X, gridOffset.Z, gridOffset.Y)
	end
	local yardAt = Vector3.new(-14, 3, 42)
	local claimAt = Vector3.new(0, 2, 52)
	if BaseLayout.Enabled() then
		local cfg = BaseLayout.Config()
		yardAt = Vector3.new(cfg.Courtyard.TrainingYard.X, 3, cfg.Courtyard.TrainingYard.Z - 6)
		claimAt = Vector3.new(cfg.SpawnOffset.X, 2, cfg.SpawnOffset.Z - 4)
	end
	local atmAt = collectorShift() + Vector3.new(28, 0, 8)
	-- v70: claimAt / yardAt / atmAt are plot-local; BaseLayout.PlotPoint turns them with Plot1 (y relative to the plot)
	local mClaim = tutorialMarker("Tutorial_ClaimBase", BaseLayout.PlotPoint(plot1, claimAt.X, claimAt.Z, claimAt.Y), Color3.fromRGB(230, 200, 80), "ClaimBase")
	local mCC = tutorialMarker("Tutorial_CommandCenter", structureMarkerPos("CommandCenter", STRUCT_ORIGIN + Vector3.new(0, 1.4, 0)), Color3.fromRGB(80, 200, 120), "CommandCenter")
	local mRecruit = tutorialMarker("Tutorial_Recruit", BaseLayout.PlotPoint(plot1, yardAt.X, yardAt.Z, yardAt.Y), Color3.fromRGB(180, 220, 100), "RecruitSoldiers")
	tutorialMarker("Tutorial_Income", BaseLayout.PlotPoint(plot1, atmAt.X, atmAt.Z, atmAt.Y + 3), Color3.fromRGB(80, 200, 160), "Income")
	-- Click dropper sits near ATM (ManualDropper CollectorOffset ≈ -5.5, 0, 4 from collector body)
	tutorialMarker("Tutorial_Dropper", BaseLayout.PlotPoint(plot1, atmAt.X - 5.5, atmAt.Z + 4, atmAt.Y + 2.5), Color3.fromRGB(70, 220, 100), "ClickDropper")
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
	tutorialMarker("Tutorial_Barracks", structureMarkerPos("Barracks", STRUCT_ORIGIN + Vector3.new(STRUCT_GAP, 1.4, 0)), Color3.fromRGB(100, 180, 220), "Barracks")
	local jeepPos = Vector3.new(200, 2, 0)
	-- World v2 (spec §3.3): the Gate_P1 pad (WorldConfig.Spawns.TutorialJeepPad); the tutorial beam itself resolves to
	-- the player's own plot (TutorialController). Fallback: the first garage pad on LAND (never a naval pontoon).
	local jeepPad = garageFolder:FindFirstChild(spawnCfg.TutorialJeepPad)
	if jeepPad and jeepPad:IsA("BasePart") then
		jeepPos = jeepPad.Position + Vector3.new(0, 2, 0)
	else
		for _, vs in ipairs(CollectionService:GetTagged(TAG_VEHICLE)) do
			if vs:IsA("BasePart") and not CollectionService:HasTag(vs, TAG_NAVAL) then
				jeepPos = vs.Position + Vector3.new(0, 2, 0)
				break
			end
		end
	end
	tutorialMarker("Tutorial_Jeep", jeepPos, Color3.fromRGB(120, 140, 200), "Jeep")
	tutorialMarker("Tutorial_Outpost", Vector3.new(0, 3, 0), Color3.fromRGB(200, 120, 80), "Outpost")

	-- v68: the always-on neon guide beams (collector → Command Center → Vehicle Depot) are gone: at the 320-stud
	-- layout they were long glowing lines cutting across the whole base. TutorialController draws one subtle
	-- guide to the current step only, while the tutorial runs.

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
		fallbackSpawn.Material = Enum.Material.SmoothPlastic -- World v2 W1: no Neon outside the bases
		fallbackSpawn.Parent = root
		print("[WAR EMPIRE] MapSetup: added fallback NeutralSpawn at (0,5,0)")
	end

	buildPadSupportShelves(root)

	-- World v2 W1 (spec §1.6): the OilSpectacle block (3 "OIL FIELD" pads with an amber light, derrick, walking beam and
	-- barrel ring near the plots, no mechanic) and the WarzoneLandmarks block (grey RadioTower / SmallFort /
	-- BunkerApproach host boxes with labels, one on RoadX0) are gone. Their derricks and kits return inside the Phase 2
	-- POIs (Oil Field, Signal Station).

	-- v70: stamp the layout generation last (a Run that threw part-way stays unstamped → Bootstrap rebuilds it)
	root:SetAttribute("WE_MapGen", MapSetup.MAP_GEN)

	print("[WAR EMPIRE] MapSetup complete: desert ground=" .. tostring(GROUND_SIZE) .. "x" .. tostring(GROUND_THICKNESS) .. " topY=" .. tostring(GROUND_TOP_Y) .. " (World v2 edge: WorldTerrain + WorldBounds; dressing deferred/Studio-skip)")
	print("[WAR EMPIRE] MapSetup confirmation: Gravity=" .. tostring(Workspace.Gravity) .. " WarEmpireSetup children=" .. tostring(#root:GetChildren()))
	print("[WAR EMPIRE] Walk onto upgrade pads to BUY (auto). E opens Base/Garage menus. Delete WarEmpireSetup + Play / admin resetmap to regenerate.")
end

return MapSetup
