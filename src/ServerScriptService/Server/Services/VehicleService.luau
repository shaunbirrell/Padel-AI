--!strict
--[[
	Phase 4/7 — Vehicles & garage (server-authoritative).
	Validates ownership, level, structure, prestige/rebirth flags, cash, cooldown.
	Spawns Part kits by VehicleDef.KitFamily (scalable to 100+) near WE_VehicleSpawn / WE_NavalSpawn.
	Visual kits v2: multi-part silhouettes (cabin/wheels/turret/lights/exhaust; air rotors+disc; naval wake).
	Optional MeshAssetId reserved for future MeshPart swap (0 = Part kit).
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Types = require(Shared.Types)
local VehicleConfig = require(Shared.Configs.VehicleConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)

type VehicleDef = VehicleConfig.VehicleDef

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)
local VisualAssetService = require(script.Parent.VisualAssetService)

local VehicleService = {}

local DataService: any = nil
local EconomyService: any = nil
local AnalyticsService: any = nil
local RateLimitService: any = nil
local NotificationService: any = nil
local RemoteSetup: any = nil
local TerritoryService: any = nil
local MissionService: any = nil
local TutorialService: any = nil

local activeVehicles: { [number]: Model } = {}
local lastSpawnAt: { [number]: number } = {}
local airDriveConns: { [number]: RBXScriptConnection } = {}
local vehicleFolder: Folder? = nil

local function now(): number
	return os.clock()
end

local function ensureFolder(): Folder
	if vehicleFolder and vehicleFolder.Parent then
		return vehicleFolder
	end
	local existing = Workspace:FindFirstChild("WarEmpireVehicles")
	if existing and existing:IsA("Folder") then
		vehicleFolder = existing
		return vehicleFolder
	end
	local folder = Instance.new("Folder")
	folder.Name = "WarEmpireVehicles"
	folder.Parent = Workspace
	vehicleFolder = folder
	return folder
end

local function getDef(vehicleId: string): VehicleDef?
	return VehicleConfig.Vehicles[vehicleId]
end

local function cooldownLeft(userId: number, player: Player?): number
	local last = lastSpawnAt[userId]
	if not last then
		return 0
	end
	local cd = VehicleConfig.SpawnCooldownSeconds or 15
	if player and TerritoryService and TerritoryService.GetVehicleCooldownMult then
		cd = cd * math.max(0.1, TerritoryService.GetVehicleCooldownMult(player))
	end
	return math.max(0, cd - (now() - last))
end

local function pushState(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	local active = activeVehicles[player.UserId]
	local activeId: string? = nil
	if active and active.Parent then
		local id = active:GetAttribute("VehicleId")
		if typeof(id) == "string" then
			activeId = id
		end
	end
	local payload: Types.VehicleStatePayload = {
		Owned = profile.Vehicles,
		ActiveVehicleId = activeId,
		CooldownRemaining = cooldownLeft(player.UserId, player),
	}
	local remote = RemoteSetup.Get(Constants.RemoteNames.VehicleStateUpdate) :: RemoteEvent
	remote:FireClient(player, payload)
end

local function stopAirDrive(userId: number)
	local conn = airDriveConns[userId]
	if conn then
		conn:Disconnect()
		airDriveConns[userId] = nil
	end
end

local function destroyActive(userId: number)
	stopAirDrive(userId)
	local model = activeVehicles[userId]
	activeVehicles[userId] = nil
	if model then
		-- Ensure kit parts / welds / seats are fully cleaned
		if model.Parent then
			model:Destroy()
		else
			pcall(function()
				model:Destroy()
			end)
		end
	end
end

local function findSpawnCFrame(player: Player, category: string?): (CFrame, string)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local origin = if root then root.Position else Vector3.zero
	local best: CFrame? = nil
	local bestDist = math.huge
	local bestSource = "none"
	local preferNaval = category == "Naval"
	local tagList = if preferNaval
		then { Constants.Tags.NavalSpawn, Constants.Tags.VehicleSpawn }
		else { Constants.Tags.VehicleSpawn }

	for _, tag in ipairs(tagList) do
		for _, inst in ipairs(CollectionService:GetTagged(tag)) do
			if inst:IsA("BasePart") and inst.Parent then
				local d = (inst.Position - origin).Magnitude
				local yOff = if tag == Constants.Tags.NavalSpawn then 4 else 5
				-- Lift clear of pad / terrain so kits never spawn inside plinth
				local cf = inst.CFrame + Vector3.new(0, yOff + math.max(0, inst.Size.Y * 0.5), 0)
				if d < bestDist then
					bestDist = d
					best = cf
					bestSource = tag
				end
			end
		end
		-- Prefer nearest naval pad within 1400 studs; don't fall through to land pads if found
		if preferNaval and best and bestDist < 1400 then
			return best, bestSource
		end
		if (not preferNaval) and best and bestDist < 700 then
			return best, bestSource
		end
	end
	if best and bestDist < 1200 then
		return best, bestSource
	end

	local profile = DataService.GetProfile(player)
	if profile and profile.BasePlotId then
		for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.BasePlot)) do
			if inst:IsA("BasePart") and inst:GetAttribute("PlotId") == profile.BasePlotId then
				return inst.CFrame + Vector3.new(0, 6, 45), "BasePlot"
			end
		end
	end

	if root then
		return root.CFrame * CFrame.new(0, 4, -14), "PlayerFront"
	end
	return CFrame.new(0, 8, 0), "WorldOrigin"
end

local function weldTo(body: BasePart, other: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = body
	w.Part1 = other
	w.Parent = body
end

local function addPart(
	model: Model,
	body: BasePart,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?,
	collide: boolean?
): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Metal
	p.CFrame = body.CFrame * offset
	p.Anchored = false
	p.CanCollide = if collide == nil then false else collide
	p.Massless = true
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	weldTo(body, p)
	return p
end

local function addWheels(model: Model, body: BasePart, scale: number, positions: { Vector3 }, radius: number?)
	local r = radius or 1.1
	for i, offset in ipairs(positions) do
		local wheel = Instance.new("Part")
		wheel.Name = "Wheel" .. i
		wheel.Shape = Enum.PartType.Cylinder
		wheel.Size = Vector3.new(r * 0.9, r * 1.8 * scale, r * 1.8 * scale)
		wheel.Color = Color3.fromRGB(22, 22, 24)
		wheel.Material = Enum.Material.SmoothPlastic
		wheel.CFrame = body.CFrame * CFrame.new(offset * scale) * CFrame.Angles(0, 0, math.rad(90))
		wheel.Anchored = false
		wheel.CanCollide = true
		wheel.Massless = true
		wheel.CustomPhysicalProperties = PhysicalProperties.new(0.3, 1.2, 0.1, 1, 1)
		wheel.Parent = model
		weldTo(body, wheel)
		-- Hub cap accent (visual kits v2)
		local hub = Instance.new("Part")
		hub.Name = "Hub" .. i
		hub.Shape = Enum.PartType.Cylinder
		hub.Size = Vector3.new(r * 0.35, r * 0.7 * scale, r * 0.7 * scale)
		hub.Color = Color3.fromRGB(90, 95, 100)
		hub.Material = Enum.Material.Metal
		hub.CFrame = wheel.CFrame
		hub.Anchored = false
		hub.CanCollide = false
		hub.Massless = true
		hub.Parent = model
		weldTo(body, hub)
	end
end

-- Visual kits v2 shared accents (keep part counts modest)
local function addHeadlights(model: Model, body: BasePart, s: number, zFront: number, y: number, spacing: number, col: Color3?)
	local c = col or Color3.fromRGB(255, 240, 180)
	addPart(model, body, "LightL", Vector3.new(0.45 * s, 0.35 * s, 0.35 * s), CFrame.new(-spacing * s, y * s, zFront * s), c, Enum.Material.Neon, nil, false)
	addPart(model, body, "LightR", Vector3.new(0.45 * s, 0.35 * s, 0.35 * s), CFrame.new(spacing * s, y * s, zFront * s), c, Enum.Material.Neon, nil, false)
end

local function addTaillights(model: Model, body: BasePart, s: number, zRear: number, y: number, spacing: number)
	local c = Color3.fromRGB(220, 50, 40)
	addPart(model, body, "TailL", Vector3.new(0.4 * s, 0.3 * s, 0.25 * s), CFrame.new(-spacing * s, y * s, zRear * s), c, Enum.Material.Neon, nil, false)
	addPart(model, body, "TailR", Vector3.new(0.4 * s, 0.3 * s, 0.25 * s), CFrame.new(spacing * s, y * s, zRear * s), c, Enum.Material.Neon, nil, false)
end

local function addExhaust(model: Model, body: BasePart, s: number, offset: CFrame, accent: Color3)
	addPart(model, body, "Exhaust", Vector3.new(0.35 * s, 0.35 * s, 1.4 * s), offset, Color3.fromRGB(35, 35, 38), Enum.Material.Metal, Enum.PartType.Cylinder, false)
	addPart(model, body, "ExhaustGlow", Vector3.new(0.28 * s, 0.28 * s, 0.35 * s), offset * CFrame.new(0, 0, 0.7 * s), accent, Enum.Material.Neon, Enum.PartType.Cylinder, false)
end

local function addRotorDisc(model: Model, body: BasePart, s: number, y: number, radius: number, accent: Color3)
	-- Thin neon disc under rotor (silhouette read at distance)
	local disc = addPart(
		model,
		body,
		"RotorDisc",
		Vector3.new(0.08 * s, radius * 2 * s, radius * 2 * s),
		CFrame.new(0, y * s, -0.3 * s) * CFrame.Angles(0, 0, math.rad(90)),
		accent,
		Enum.Material.Neon,
		Enum.PartType.Cylinder,
		false
	)
	disc.Transparency = 0.55
end

local function addWakeStrip(model: Model, body: BasePart, s: number, length: number, accent: Color3)
	addPart(model, body, "WakeNeon", Vector3.new(0.35 * s, 0.12 * s, length * s), CFrame.new(0, -0.7 * s, 0.5 * s), accent, Enum.Material.Neon, nil, false)
end

local function addSideRails(model: Model, body: BasePart, s: number, length: number, height: number, width: number, color: Color3)
	addPart(model, body, "RailL", Vector3.new(0.2 * s, 0.25 * s, length * s), CFrame.new(-width * s, height * s, 0), color, Enum.Material.Metal, nil, false)
	addPart(model, body, "RailR", Vector3.new(0.2 * s, 0.25 * s, length * s), CFrame.new(width * s, height * s, 0), color, Enum.Material.Metal, nil, false)
end

local function addLabel(parent: BasePart, text: string, y: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "VehicleLabel"
	billboard.Size = UDim2.fromOffset(150, 36)
	billboard.StudsOffset = Vector3.new(0, y, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 280
	billboard.Parent = parent
	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(12, 14, 16)
	backdrop.BackgroundTransparency = 0.25
	backdrop.BorderSizePixel = 0
	backdrop.Parent = billboard
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 5)
	c.Parent = backdrop
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(230, 190, 60)
	stroke.Thickness = 1
	stroke.Transparency = 0.35
	stroke.Parent = backdrop
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(235, 238, 242)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = text
	label.Parent = backdrop
end

local function buildVehicleModel(def: VehicleDef, at: CFrame, ownerUserId: number): Model
	local model = Instance.new("Model")
	model.Name = def.DisplayName
	model:SetAttribute("VehicleId", def.Id)
	model:SetAttribute("OwnerUserId", ownerUserId)

	local id = def.Id
	local family = def.KitFamily or "WheeledLight"
	local scale = if typeof(def.KitScale) == "number" then def.KitScale :: number else 1
	local olive = Color3.fromRGB(55, 70, 48)
	local oliveDark = Color3.fromRGB(40, 50, 38)
	local armor = Color3.fromRGB(62, 68, 55)
	local armorDark = Color3.fromRGB(45, 50, 42)
	local sand = Color3.fromRGB(110, 100, 70)
	local accent = Color3.fromRGB(230, 190, 60)
	local blueAcc = Color3.fromRGB(90, 160, 220)
	local redAcc = Color3.fromRGB(200, 80, 60)
	local sky = Color3.fromRGB(70, 90, 110)
	local rarity = def.Rarity or "Common"
	local accentCol = if rarity == "Legendary"
		then redAcc
		elseif rarity == "Epic" then accent
		elseif rarity == "Rare" then blueAcc
		else accent

	local body = Instance.new("Part")
	body.Name = "Chassis"
	body.Anchored = false
	body.CanCollide = true
	body.Material = Enum.Material.Metal
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.CFrame = at
	body.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.5, 0.2, 1, 1)
	body.Parent = model

	local seatOffset = CFrame.new(0, 2.0, -0.5)
	local labelY = 4.5
	local s = scale

	local function kitWheeledLight()
		local armed = id == "ArmedJeep"
		local scout = id == "ScoutCar" or id == "ReconBuggy"
		local quad = id == "UtilityQuad"
		body.Size = Vector3.new(5.2 * s, 1.6 * s, if quad then 6.5 * s else 8.5 * s)
		body.Color = if armed then Color3.fromRGB(48, 58, 42) elseif scout then Color3.fromRGB(70, 85, 55) else olive
		addPart(model, body, "Hood", Vector3.new(4.6 * s, 0.7 * s, 2.8 * s), CFrame.new(0, 0.9 * s, -2.4 * s), oliveDark, Enum.Material.Metal, nil, false)
		addPart(model, body, "Cabin", Vector3.new(4.4 * s, 1.4 * s, 2.8 * s), CFrame.new(0, 1.3 * s, 0.2 * s), oliveDark, Enum.Material.SmoothPlastic, nil, true)
		if not quad then
			addPart(model, body, "Bed", Vector3.new(4.4 * s, 0.9 * s, 2.6 * s), CFrame.new(0, 0.7 * s, 2.6 * s), olive, Enum.Material.Metal, nil, false)
		end
		addPart(model, body, "Bumper", Vector3.new(5.0 * s, 0.5 * s, 0.4 * s), CFrame.new(0, -0.3 * s, -4.0 * s), Color3.fromRGB(30, 30, 30), Enum.Material.Metal, nil, false)
		addPart(model, body, "AccentStrip", Vector3.new(4.8 * s, 0.12 * s, 0.35 * s), CFrame.new(0, 1.1 * s, -1.2 * s), if armed then redAcc else accentCol, Enum.Material.Neon, nil, false)
		if armed then
			addPart(model, body, "GunMount", Vector3.new(0.8 * s, 0.8 * s, 0.8 * s), CFrame.new(0, 2.2 * s, 0.4 * s), Color3.fromRGB(35, 35, 35), Enum.Material.Metal, nil, false)
			addPart(model, body, "Barrel", Vector3.new(0.25 * s, 0.25 * s, 2.4 * s), CFrame.new(0, 2.5 * s, -1.0 * s), Color3.fromRGB(40, 40, 40), Enum.Material.Metal, nil, false)
		end
		addWheels(model, body, s, {
			Vector3.new(-2.4, -0.9, 2.6),
			Vector3.new(2.4, -0.9, 2.6),
			Vector3.new(-2.4, -0.9, -2.6),
			Vector3.new(2.4, -0.9, -2.6),
		}, 1.05)
		addHeadlights(model, body, s, -4.1, 0.2, 1.8)
		addTaillights(model, body, s, if quad then 3.0 else 4.0, 0.15, 1.9)
		addExhaust(model, body, s, CFrame.new(1.8 * s, -0.2 * s, 3.2 * s) * CFrame.Angles(0, 0, math.rad(90)), accentCol)
		addSideRails(model, body, s, if quad then 4.5 else 5.5, 0.6, 2.5, oliveDark)
		seatOffset = CFrame.new(0, 1.9 * s, 0.1 * s)
		labelY = 4.2 * s
	end

	local function kitWheeledTruck()
		local supply = id == "SupplyTruck"
		local fuel = id == "FuelTanker"
		local missile = id == "MissileTruck" or id == "AntiAirTruck"
		local eng = id == "EngineeringTruck"
		body.Size = Vector3.new(6.2 * s, 2.4 * s, 11 * s)
		body.Color = if supply then sand elseif fuel then Color3.fromRGB(90, 95, 55) else armor
		addPart(model, body, "Cabin", Vector3.new(5.6 * s, 2.0 * s, 3.2 * s), CFrame.new(0, 1.6 * s, -3.2 * s), armorDark, Enum.Material.Metal, nil, true)
		addPart(model, body, "Cargo", Vector3.new(5.8 * s, 2.6 * s, 6.5 * s), CFrame.new(0, 1.4 * s, 2.0 * s), if supply then Color3.fromRGB(130, 115, 75) elseif fuel then Color3.fromRGB(70, 80, 45) else sand, Enum.Material.Metal, nil, true)
		addPart(model, body, "Accent", Vector3.new(5.9 * s, 0.15 * s, 0.4 * s), CFrame.new(0, 2.5 * s, -2.0 * s), accentCol, Enum.Material.Neon, nil, false)
		if supply then
			addPart(model, body, "Crate", Vector3.new(3.5 * s, 1.4 * s, 3.5 * s), CFrame.new(0, 3.0 * s, 2.0 * s), Color3.fromRGB(90, 75, 50), Enum.Material.Wood, nil, false)
		elseif fuel then
			addPart(model, body, "Tank", Vector3.new(4.5 * s, 2.2 * s, 5.5 * s), CFrame.new(0, 2.8 * s, 2.0 * s), Color3.fromRGB(80, 85, 50), Enum.Material.Metal, Enum.PartType.Cylinder, false)
		elseif missile then
			addPart(model, body, "Launcher", Vector3.new(4.0 * s, 1.2 * s, 5.0 * s), CFrame.new(0, 3.0 * s, 1.5 * s) * CFrame.Angles(math.rad(-20), 0, 0), Color3.fromRGB(50, 55, 45), Enum.Material.Metal, nil, false)
		elseif eng then
			addPart(model, body, "Crane", Vector3.new(0.5 * s, 4.0 * s, 0.5 * s), CFrame.new(1.5 * s, 4.0 * s, 1.0 * s), Color3.fromRGB(200, 160, 60), Enum.Material.Metal, nil, false)
		end
		addPart(model, body, "Bumper", Vector3.new(6.0 * s, 0.55 * s, 0.45 * s), CFrame.new(0, -0.6 * s, -5.2 * s), Color3.fromRGB(28, 28, 30), Enum.Material.Metal, nil, false)
		addWheels(model, body, 1.15 * s, {
			Vector3.new(-2.8, -1.2, 3.5),
			Vector3.new(2.8, -1.2, 3.5),
			Vector3.new(-2.8, -1.2, 0),
			Vector3.new(2.8, -1.2, 0),
			Vector3.new(-2.8, -1.2, -3.5),
			Vector3.new(2.8, -1.2, -3.5),
		}, 1.2)
		addHeadlights(model, body, s, -5.3, 0.4, 2.2)
		addTaillights(model, body, s, 5.2, 0.3, 2.4)
		addExhaust(model, body, s, CFrame.new(2.4 * s, -0.4 * s, 4.5 * s) * CFrame.Angles(0, 0, math.rad(90)), accentCol)
		seatOffset = CFrame.new(0, 2.4 * s, -3.0 * s)
		labelY = 5.5 * s
	end

	local function kitWheeledAPC()
		local carrier = id == "InfantryCarrier"
		local cmd = id == "CommandVehicle"
		body.Size = Vector3.new((if carrier then 7.2 else 6.5) * s, 2.6 * s, (if carrier then 12 else 10.5) * s)
		body.Color = armorDark
		addPart(model, body, "HullTop", Vector3.new(5.8 * s, 1.4 * s, 8.5 * s), CFrame.new(0, 1.8 * s, 0), armor, Enum.Material.Metal, nil, true)
		addPart(model, body, "Turret", Vector3.new(2.4 * s, 1.2 * s, 2.4 * s), CFrame.new(0, 3.0 * s, 0.5 * s), Color3.fromRGB(50, 55, 48), Enum.Material.Metal, nil, false)
		addPart(model, body, "Barrel", Vector3.new(0.35 * s, 0.35 * s, 3.2 * s), CFrame.new(0, 3.1 * s, -2.0 * s), Color3.fromRGB(35, 35, 35), Enum.Material.Metal, nil, false)
		addPart(model, body, "Accent", Vector3.new(6.0 * s, 0.12 * s, 0.35 * s), CFrame.new(0, 2.6 * s, -3 * s), accentCol, Enum.Material.Neon, nil, false)
		if cmd then
			addPart(model, body, "Dish", Vector3.new(2.2 * s, 0.3 * s, 2.2 * s), CFrame.new(0, 4.0 * s, 1.5 * s), Color3.fromRGB(80, 90, 100), Enum.Material.Metal, Enum.PartType.Cylinder, false)
		end
		addPart(model, body, "Bumper", Vector3.new(6.2 * s, 0.6 * s, 0.5 * s), CFrame.new(0, -0.7 * s, -5.0 * s), Color3.fromRGB(30, 32, 28), Enum.Material.Metal, nil, false)
		addWheels(model, body, 1.2 * s, {
			Vector3.new(-3.0, -1.3, 3.2),
			Vector3.new(3.0, -1.3, 3.2),
			Vector3.new(-3.0, -1.3, 0.5),
			Vector3.new(3.0, -1.3, 0.5),
			Vector3.new(-3.0, -1.3, -2.5),
			Vector3.new(3.0, -1.3, -2.5),
		}, 1.25)
		addHeadlights(model, body, s, -5.1, 0.2, 2.4)
		addTaillights(model, body, s, 4.8, 0.2, 2.5)
		addExhaust(model, body, s, CFrame.new(2.8 * s, 0.2 * s, 4.0 * s) * CFrame.Angles(0, 0, math.rad(90)), accentCol)
		seatOffset = CFrame.new(0, 2.2 * s, -2.5 * s)
		labelY = 5.8 * s
	end

	local function kitTracked(kind: string)
		local isSPAAG = kind == "SPAAG"
		local isArty = kind == "Artillery"
		local isIFV = kind == "IFV"
		body.Size = Vector3.new(6.5 * s, 2.2 * s, 9.5 * s)
		body.Color = if s >= 1.4 then Color3.fromRGB(45, 48, 40) else armor
		addPart(model, body, "TrackL", Vector3.new(1.2 * s, 1.6 * s, 9 * s), CFrame.new(-3.2 * s, -0.4 * s, 0), Color3.fromRGB(30, 32, 28), Enum.Material.Metal, nil, true)
		addPart(model, body, "TrackR", Vector3.new(1.2 * s, 1.6 * s, 9 * s), CFrame.new(3.2 * s, -0.4 * s, 0), Color3.fromRGB(30, 32, 28), Enum.Material.Metal, nil, true)
		if isSPAAG then
			addPart(model, body, "Turret", Vector3.new(3.2 * s, 1.4 * s, 3.2 * s), CFrame.new(0, 2.0 * s, 0), armorDark, Enum.Material.Metal, nil, true)
			addPart(model, body, "BarrelA", Vector3.new(0.3 * s, 0.3 * s, 4.5 * s), CFrame.new(-0.6 * s, 2.4 * s, -3.0 * s) * CFrame.Angles(math.rad(-35), 0, 0), Color3.fromRGB(35, 35, 35), Enum.Material.Metal, nil, false)
			addPart(model, body, "BarrelB", Vector3.new(0.3 * s, 0.3 * s, 4.5 * s), CFrame.new(0.6 * s, 2.4 * s, -3.0 * s) * CFrame.Angles(math.rad(-35), 0, 0), Color3.fromRGB(35, 35, 35), Enum.Material.Metal, nil, false)
		elseif isArty then
			local rocket = id == "RocketArtillery"
			addPart(model, body, "Turret", Vector3.new(3.4 * s, 1.5 * s, 3.8 * s), CFrame.new(0, 1.9 * s, 0.8 * s), armorDark, Enum.Material.Metal, nil, true)
			if rocket then
				addPart(model, body, "Pod", Vector3.new(3.0 * s, 1.8 * s, 4.5 * s), CFrame.new(0, 3.2 * s, 0.5 * s) * CFrame.Angles(math.rad(-25), 0, 0), Color3.fromRGB(55, 60, 50), Enum.Material.Metal, nil, false)
			else
				addPart(model, body, "Barrel", Vector3.new(0.5 * s, 0.5 * s, 7 * s), CFrame.new(0, 2.8 * s, -3.5 * s) * CFrame.Angles(math.rad(-15), 0, 0), Color3.fromRGB(35, 35, 35), Enum.Material.Metal, nil, false)
			end
		elseif isIFV then
			addPart(model, body, "HullTop", Vector3.new(5.5 * s, 1.2 * s, 7.5 * s), CFrame.new(0, 1.7 * s, 0), armor, Enum.Material.Metal, nil, true)
			addPart(model, body, "Turret", Vector3.new(2.8 * s, 1.3 * s, 3.0 * s), CFrame.new(0, 2.8 * s, 0.3 * s), armorDark, Enum.Material.Metal, nil, true)
			addPart(model, body, "Barrel", Vector3.new(0.35 * s, 0.35 * s, 4.2 * s), CFrame.new(0, 2.9 * s, -2.5 * s), Color3.fromRGB(35, 35, 35), Enum.Material.Metal, nil, false)
		else
			addPart(model, body, "Turret", Vector3.new(3.6 * s, 1.6 * s, 4.2 * s), CFrame.new(0, 2.0 * s, 0.3 * s), armorDark, Enum.Material.Metal, nil, true)
			addPart(model, body, "Barrel", Vector3.new(0.45 * s, 0.45 * s, 5.5 * s), CFrame.new(0, 2.1 * s, -4.2 * s), Color3.fromRGB(35, 35, 35), Enum.Material.Metal, nil, false)
		end
		addPart(model, body, "Accent", Vector3.new(3.2 * s, 0.12 * s, 0.3 * s), CFrame.new(0, 2.9 * s, 1.2 * s), accentCol, Enum.Material.Neon, nil, false)
		addPart(model, body, "Mantlet", Vector3.new(2.2 * s, 1.0 * s, 0.6 * s), CFrame.new(0, 2.1 * s, -1.6 * s), armorDark, Enum.Material.Metal, nil, false)
		addHeadlights(model, body, s, -4.6, 0.4, 2.2, Color3.fromRGB(255, 230, 160))
		addExhaust(model, body, s, CFrame.new(2.6 * s, 0.8 * s, 4.0 * s) * CFrame.Angles(0, 0, math.rad(90)), accentCol)
		for i, z in ipairs({ 3.2, 1.0, -1.2, -3.2 }) do
			addPart(model, body, "RoadL" .. i, Vector3.new(0.7 * s, 1.3 * s, 1.3 * s), CFrame.new(-3.2 * s, -1.0 * s, z * s) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(25, 25, 25), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, true)
			addPart(model, body, "RoadR" .. i, Vector3.new(0.7 * s, 1.3 * s, 1.3 * s), CFrame.new(3.2 * s, -1.0 * s, z * s) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(25, 25, 25), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, true)
		end
		seatOffset = CFrame.new(0, 2.6 * s, 0.2 * s)
		labelY = 5.5 * s
	end

	local function kitHeli(kind: string)
		local attack = kind == "Attack"
		local light = kind == "Light"
		local transport = kind == "Transport"
		local len = if transport then 12 elseif light then 8.5 else 10
		local wid = if transport then 4.5 elseif light then 2.8 else 3.2
		body.Size = Vector3.new(wid * s, 2.0 * s, len * s)
		body.Color = if id == "StealthHeli" then Color3.fromRGB(25, 30, 38) else sky
		addPart(model, body, "Cockpit", Vector3.new((wid - 0.6) * s, 1.6 * s, 3.2 * s), CFrame.new(0, 0.6 * s, -len * 0.32 * s), Color3.fromRGB(40, 55, 70), Enum.Material.Glass, nil, true)
		if transport then
			addPart(model, body, "Cabin", Vector3.new(4.0 * s, 2.0 * s, 5.5 * s), CFrame.new(0, 0.5 * s, 1.5 * s), sky, Enum.Material.Metal, nil, true)
		end
		addPart(model, body, "Tail", Vector3.new(1.0 * s, 1.0 * s, 5.5 * s), CFrame.new(0, 0.8 * s, len * 0.55 * s), body.Color, Enum.Material.Metal, nil, false)
		addPart(model, body, "TailFin", Vector3.new(0.3 * s, 2.4 * s, 1.6 * s), CFrame.new(0, 2.0 * s, len * 0.72 * s), Color3.fromRGB(50, 65, 80), Enum.Material.Metal, nil, false)
		local rotor = if transport then 16 elseif light then 11 else 14
		addPart(model, body, "RotorHub", Vector3.new(1.2 * s, 0.5 * s, 1.2 * s), CFrame.new(0, 2.0 * s, -0.3 * s), Color3.fromRGB(30, 30, 30), Enum.Material.Metal, nil, false)
		addPart(model, body, "RotorA", Vector3.new(rotor * s, 0.15 * s, 0.6 * s), CFrame.new(0, 2.35 * s, -0.3 * s), Color3.fromRGB(35, 35, 38), Enum.Material.Metal, nil, false)
		addPart(model, body, "RotorB", Vector3.new(0.6 * s, 0.15 * s, rotor * s), CFrame.new(0, 2.4 * s, -0.3 * s), Color3.fromRGB(35, 35, 38), Enum.Material.Metal, nil, false)
		addPart(model, body, "SkidL", Vector3.new(0.25 * s, 0.25 * s, 7 * s), CFrame.new(-wid * 0.5 * s, -1.3 * s, 0), Color3.fromRGB(40, 40, 40), Enum.Material.Metal, nil, true)
		addPart(model, body, "SkidR", Vector3.new(0.25 * s, 0.25 * s, 7 * s), CFrame.new(wid * 0.5 * s, -1.3 * s, 0), Color3.fromRGB(40, 40, 40), Enum.Material.Metal, nil, true)
		addPart(model, body, "SkidPadL", Vector3.new(0.9 * s, 0.2 * s, 1.2 * s), CFrame.new(-wid * 0.5 * s, -1.45 * s, 2 * s), Color3.fromRGB(50, 50, 55), Enum.Material.Metal, nil, true)
		addPart(model, body, "SkidPadR", Vector3.new(0.9 * s, 0.2 * s, 1.2 * s), CFrame.new(wid * 0.5 * s, -1.45 * s, 2 * s), Color3.fromRGB(50, 50, 55), Enum.Material.Metal, nil, true)
		addRotorDisc(model, body, s, 2.2, rotor * 0.48, accentCol)
		addPart(model, body, "Accent", Vector3.new((wid - 0.4) * s, 0.12 * s, 0.35 * s), CFrame.new(0, 1.2 * s, -1 * s), accentCol, Enum.Material.Neon, nil, false)
		addPart(model, body, "NavLight", Vector3.new(0.35 * s, 0.35 * s, 0.35 * s), CFrame.new(0, 1.6 * s, len * 0.4 * s), Color3.fromRGB(255, 60, 50), Enum.Material.Neon, Enum.PartType.Ball, false)
		if attack then
			addPart(model, body, "StubWingL", Vector3.new(3.5 * s, 0.25 * s, 1.2 * s), CFrame.new(-2.5 * s, 0, 0.5 * s), Color3.fromRGB(55, 70, 85), Enum.Material.Metal, nil, false)
			addPart(model, body, "StubWingR", Vector3.new(3.5 * s, 0.25 * s, 1.2 * s), CFrame.new(2.5 * s, 0, 0.5 * s), Color3.fromRGB(55, 70, 85), Enum.Material.Metal, nil, false)
		end
		seatOffset = CFrame.new(0, 1.2 * s, -2.8 * s)
		labelY = 5.5 * s
	end

	local function kitJet(kind: string)
		local bomber = kind == "Bomber"
		local cargo = kind == "Transport"
		local strike = kind == "Strike"
		local len = if cargo then 16 elseif bomber then 14 else 12
		local wid = if cargo then 3.5 elseif bomber then 2.8 else 2.4
		body.Size = Vector3.new(wid * s, 1.5 * s, len * s)
		body.Color = if cargo then Color3.fromRGB(100, 105, 95) elseif bomber then Color3.fromRGB(70, 75, 80) else Color3.fromRGB(90, 95, 100)
		addPart(model, body, "Nose", Vector3.new((wid - 0.8) * s, 1.0 * s, 3.5 * s), CFrame.new(0, 0.1 * s, -len * 0.48 * s), Color3.fromRGB(70, 75, 80), Enum.Material.Metal, nil, false)
		addPart(model, body, "Cockpit", Vector3.new(1.6 * s, 0.9 * s, 2.2 * s), CFrame.new(0, 0.9 * s, -len * 0.28 * s), Color3.fromRGB(40, 80, 120), Enum.Material.Glass, nil, false)
		local wingSpan = if cargo then 10 elseif bomber then 9 else 7
		addPart(model, body, "WingL", Vector3.new(wingSpan * s, 0.25 * s, 2.8 * s), CFrame.new(-wingSpan * 0.55 * s, 0, 0.5 * s), Color3.fromRGB(80, 85, 90), Enum.Material.Metal, nil, false)
		addPart(model, body, "WingR", Vector3.new(wingSpan * s, 0.25 * s, 2.8 * s), CFrame.new(wingSpan * 0.55 * s, 0, 0.5 * s), Color3.fromRGB(80, 85, 90), Enum.Material.Metal, nil, false)
		addPart(model, body, "TailFin", Vector3.new(0.25 * s, (if bomber then 3.2 else 2.8) * s, 2.0 * s), CFrame.new(0, 1.8 * s, len * 0.38 * s), Color3.fromRGB(85, 90, 95), Enum.Material.Metal, nil, false)
		if not cargo then
			addPart(model, body, "StabL", Vector3.new(2.5 * s, 0.2 * s, 1.2 * s), CFrame.new(-1.5 * s, 0.8 * s, len * 0.38 * s), Color3.fromRGB(80, 85, 90), Enum.Material.Metal, nil, false)
			addPart(model, body, "StabR", Vector3.new(2.5 * s, 0.2 * s, 1.2 * s), CFrame.new(1.5 * s, 0.8 * s, len * 0.38 * s), Color3.fromRGB(80, 85, 90), Enum.Material.Metal, nil, false)
		end
		if strike or kind == "Fighter" then
			addPart(model, body, "IntakeL", Vector3.new(0.9 * s, 0.9 * s, 2.5 * s), CFrame.new(-1.3 * s, -0.2 * s, 1.5 * s), Color3.fromRGB(50, 50, 55), Enum.Material.Metal, nil, false)
			addPart(model, body, "IntakeR", Vector3.new(0.9 * s, 0.9 * s, 2.5 * s), CFrame.new(1.3 * s, -0.2 * s, 1.5 * s), Color3.fromRGB(50, 50, 55), Enum.Material.Metal, nil, false)
		end
		if bomber then
			addPart(model, body, "Bay", Vector3.new((wid - 0.4) * s, 0.8 * s, 4 * s), CFrame.new(0, -0.6 * s, 0.5 * s), Color3.fromRGB(45, 48, 52), Enum.Material.Metal, nil, false)
		end
		addPart(model, body, "Accent", Vector3.new(2.0 * s, 0.1 * s, 0.3 * s), CFrame.new(0, 0.8 * s, -1 * s), accentCol, Enum.Material.Neon, nil, false)
		addPart(model, body, "EngineGlow", Vector3.new((wid - 0.6) * s, 0.7 * s, 0.5 * s), CFrame.new(0, 0, len * 0.42 * s), accentCol, Enum.Material.Neon, nil, false)
		addPart(model, body, "GearF", Vector3.new(0.3 * s, 0.8 * s, 0.3 * s), CFrame.new(0, -1.0 * s, -len * 0.3 * s), Color3.fromRGB(30, 30, 30), Enum.Material.Metal, nil, true)
		addPart(model, body, "WheelF", Vector3.new(0.5 * s, 0.9 * s, 0.9 * s), CFrame.new(0, -1.5 * s, -len * 0.3 * s) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(25, 25, 28), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, true)
		addPart(model, body, "GearL", Vector3.new(0.3 * s, 0.8 * s, 0.3 * s), CFrame.new(-1.5 * s, -1.0 * s, 1 * s), Color3.fromRGB(30, 30, 30), Enum.Material.Metal, nil, true)
		addPart(model, body, "GearR", Vector3.new(0.3 * s, 0.8 * s, 0.3 * s), CFrame.new(1.5 * s, -1.0 * s, 1 * s), Color3.fromRGB(30, 30, 30), Enum.Material.Metal, nil, true)
		addPart(model, body, "WingTipL", Vector3.new(0.3 * s, 0.3 * s, 0.3 * s), CFrame.new(-wingSpan * 0.95 * s, 0.1 * s, 0.5 * s), Color3.fromRGB(255, 60, 50), Enum.Material.Neon, Enum.PartType.Ball, false)
		addPart(model, body, "WingTipR", Vector3.new(0.3 * s, 0.3 * s, 0.3 * s), CFrame.new(wingSpan * 0.95 * s, 0.1 * s, 0.5 * s), Color3.fromRGB(60, 255, 90), Enum.Material.Neon, Enum.PartType.Ball, false)
		seatOffset = CFrame.new(0, 1.3 * s, -len * 0.26 * s)
		labelY = 4.8 * s
	end

	local function kitNaval(kind: string)
		if kind == "Landing" then
			body.Size = Vector3.new(8 * s, 2.0 * s, 16 * s)
			body.Color = Color3.fromRGB(55, 65, 55)
			addPart(model, body, "Deck", Vector3.new(7.2 * s, 0.5 * s, 13 * s), CFrame.new(0, 1.1 * s, 0.5 * s), Color3.fromRGB(70, 80, 65), Enum.Material.Metal, nil, true)
			addPart(model, body, "Ramp", Vector3.new(6.5 * s, 0.4 * s, 4 * s), CFrame.new(0, 0.6 * s, -7.5 * s) * CFrame.Angles(math.rad(-18), 0, 0), Color3.fromRGB(60, 70, 55), Enum.Material.Metal, nil, true)
			addPart(model, body, "Cabin", Vector3.new(3.5 * s, 2.2 * s, 3.0 * s), CFrame.new(0, 2.3 * s, 5.5 * s), Color3.fromRGB(50, 60, 50), Enum.Material.Metal, nil, true)
			addPart(model, body, "WallL", Vector3.new(0.4 * s, 1.6 * s, 12 * s), CFrame.new(-3.6 * s, 1.6 * s, 0), oliveDark, Enum.Material.Metal, nil, false)
			addPart(model, body, "WallR", Vector3.new(0.4 * s, 1.6 * s, 12 * s), CFrame.new(3.6 * s, 1.6 * s, 0), oliveDark, Enum.Material.Metal, nil, false)
			addPart(model, body, "Accent", Vector3.new(6.0 * s, 0.12 * s, 0.35 * s), CFrame.new(0, 1.6 * s, 4 * s), accentCol, Enum.Material.Neon, nil, false)
			addWakeStrip(model, body, s, 12, accentCol)
			addPart(model, body, "GunMount", Vector3.new(1.2 * s, 0.8 * s, 1.2 * s), CFrame.new(0, 2.6 * s, -2 * s), Color3.fromRGB(40, 45, 40), Enum.Material.Metal, nil, false)
			seatOffset = CFrame.new(0, 3.0 * s, 5.2 * s)
			labelY = 6.0 * s
		elseif kind == "Sub" then
			-- Surface stub: low dark hull (no underwater physics yet)
			body.Size = Vector3.new(5 * s, 2.2 * s, 18 * s)
			body.Color = Color3.fromRGB(30, 40, 48)
			addPart(model, body, "Sail", Vector3.new(1.8 * s, 2.8 * s, 4 * s), CFrame.new(0, 2.4 * s, -1 * s), Color3.fromRGB(35, 45, 55), Enum.Material.Metal, nil, true)
			addPart(model, body, "Bow", Vector3.new(3.5 * s, 1.6 * s, 4 * s), CFrame.new(0, 0.2 * s, -8 * s), Color3.fromRGB(28, 38, 45), Enum.Material.Metal, nil, false)
			addPart(model, body, "Accent", Vector3.new(4.0 * s, 0.12 * s, 0.3 * s), CFrame.new(0, 1.2 * s, 2 * s), accentCol, Enum.Material.Neon, nil, false)
			addWakeStrip(model, body, s, 14, accentCol)
			addPart(model, body, "Periscope", Vector3.new(0.25 * s, 2.2 * s, 0.25 * s), CFrame.new(0, 4.2 * s, -1 * s), Color3.fromRGB(50, 55, 60), Enum.Material.Metal, nil, false)
			seatOffset = CFrame.new(0, 3.5 * s, -1 * s)
			labelY = 6.5 * s
		elseif kind == "Capital" then
			body.Size = Vector3.new(8 * s, 2.4 * s, 28 * s)
			body.Color = Color3.fromRGB(40, 55, 70)
			addPart(model, body, "Deck", Vector3.new(7.2 * s, 0.5 * s, 24 * s), CFrame.new(0, 1.3 * s, 0), Color3.fromRGB(50, 65, 80), Enum.Material.Metal, nil, true)
			addPart(model, body, "Superstructure", Vector3.new(4.5 * s, 3.5 * s, 8 * s), CFrame.new(0, 3.2 * s, 2 * s), Color3.fromRGB(45, 60, 75), Enum.Material.Metal, nil, true)
			addPart(model, body, "Bridge", Vector3.new(3.5 * s, 2.0 * s, 3.5 * s), CFrame.new(0, 5.5 * s, 1 * s), Color3.fromRGB(55, 70, 85), Enum.Material.Metal, nil, true)
			addPart(model, body, "Bow", Vector3.new(5.5 * s, 1.6 * s, 5 * s), CFrame.new(0, 0.6 * s, -12 * s), Color3.fromRGB(45, 60, 75), Enum.Material.Metal, nil, false)
			addPart(model, body, "TurretF", Vector3.new(2.4 * s, 1.2 * s, 2.8 * s), CFrame.new(0, 2.4 * s, -6 * s), Color3.fromRGB(35, 45, 55), Enum.Material.Metal, nil, false)
			addPart(model, body, "BarrelF", Vector3.new(0.4 * s, 0.4 * s, 5 * s), CFrame.new(0, 2.6 * s, -9 * s), Color3.fromRGB(30, 30, 30), Enum.Material.Metal, nil, false)
			addPart(model, body, "TurretA", Vector3.new(2.2 * s, 1.1 * s, 2.5 * s), CFrame.new(0, 2.3 * s, 8 * s), Color3.fromRGB(35, 45, 55), Enum.Material.Metal, nil, false)
			addPart(model, body, "Stack", Vector3.new(1.8 * s, 3.5 * s, 1.8 * s), CFrame.new(0, 5.5 * s, 5 * s), Color3.fromRGB(50, 50, 55), Enum.Material.Metal, nil, false)
			addPart(model, body, "Accent", Vector3.new(6.5 * s, 0.15 * s, 0.4 * s), CFrame.new(0, 1.8 * s, -2 * s), accentCol, Enum.Material.Neon, nil, false)
			addWakeStrip(model, body, s, 22, accentCol)
			addPart(model, body, "Mast", Vector3.new(0.35 * s, 6 * s, 0.35 * s), CFrame.new(0, 8.5 * s, 2 * s), Color3.fromRGB(55, 60, 70), Enum.Material.Metal, nil, false)
			addPart(model, body, "RadarDish", Vector3.new(2.4 * s, 0.35 * s, 2.4 * s), CFrame.new(0, 11.5 * s, 2 * s), accentCol, Enum.Material.Neon, Enum.PartType.Cylinder, false)
			seatOffset = CFrame.new(0, 6.2 * s, 1 * s)
			labelY = 9.0 * s
		else
			-- Patrol / Gun
			local gun = kind == "Gun" or id == "Gunboat" or id == "MissileBoat"
			local hull = Color3.fromRGB(45, 70, 85)
			body.Size = Vector3.new((if gun then 6.5 else 5.5) * s, 1.8 * s, (if gun then 14 else 11) * s)
			body.Color = hull
			addPart(model, body, "Deck", Vector3.new((if gun then 5.8 else 4.8) * s, 0.4 * s, (if gun then 11 else 8.5) * s), CFrame.new(0, 1.0 * s, 0), Color3.fromRGB(55, 80, 95), Enum.Material.Metal, nil, true)
			addPart(model, body, "Cabin", Vector3.new(3.2 * s, 2.0 * s, 3.5 * s), CFrame.new(0, 2.2 * s, -1.5 * s), Color3.fromRGB(40, 60, 75), Enum.Material.Metal, nil, true)
			addPart(model, body, "Bow", Vector3.new((if gun then 4.5 else 3.8) * s, 1.2 * s, 3.0 * s), CFrame.new(0, 0.4 * s, (if gun then -6.5 else -5.2) * s), Color3.fromRGB(50, 75, 90), Enum.Material.Metal, nil, false)
			addPart(model, body, "Accent", Vector3.new(4.0 * s, 0.12 * s, 0.35 * s), CFrame.new(0, 1.5 * s, -2 * s), accentCol, Enum.Material.Neon, nil, false)
			addWakeStrip(model, body, s, if gun then 11 else 8, accentCol)
			addPart(model, body, "BridgeGlass", Vector3.new(2.8 * s, 0.9 * s, 0.3 * s), CFrame.new(0, 2.8 * s, -3.0 * s), Color3.fromRGB(60, 100, 130), Enum.Material.Glass, nil, false)
			if gun then
				addPart(model, body, "Turret", Vector3.new(2.0 * s, 1.0 * s, 2.0 * s), CFrame.new(0, 2.8 * s, 2.5 * s), Color3.fromRGB(35, 45, 50), Enum.Material.Metal, nil, false)
				addPart(model, body, "Barrel", Vector3.new(0.35 * s, 0.35 * s, 3.5 * s), CFrame.new(0, 3.0 * s, 0.5 * s), Color3.fromRGB(30, 30, 30), Enum.Material.Metal, nil, false)
				addPart(model, body, "GunShield", Vector3.new(1.6 * s, 1.0 * s, 0.25 * s), CFrame.new(0, 3.2 * s, 1.4 * s), Color3.fromRGB(40, 50, 55), Enum.Material.Metal, nil, false)
			end
			seatOffset = CFrame.new(0, 2.8 * s, -1.2 * s)
			labelY = 5.5 * s
		end
	end

	if family == "WheeledLight" then
		kitWheeledLight()
	elseif family == "WheeledTruck" then
		kitWheeledTruck()
	elseif family == "WheeledAPC" then
		kitWheeledAPC()
	elseif family == "TrackedIFV" then
		kitTracked("IFV")
	elseif family == "TrackedMBT" then
		kitTracked("MBT")
	elseif family == "TrackedSPAAG" then
		kitTracked("SPAAG")
	elseif family == "TrackedArtillery" then
		kitTracked("Artillery")
	elseif family == "HeliLight" then
		kitHeli("Light")
	elseif family == "HeliTransport" then
		kitHeli("Transport")
	elseif family == "HeliAttack" then
		kitHeli("Attack")
	elseif family == "JetFighter" then
		kitJet("Fighter")
	elseif family == "JetStrike" then
		kitJet("Strike")
	elseif family == "JetBomber" then
		kitJet("Bomber")
	elseif family == "JetTransport" then
		kitJet("Transport")
	elseif family == "NavalPatrol" then
		kitNaval("Patrol")
	elseif family == "NavalGun" then
		kitNaval("Gun")
	elseif family == "NavalLanding" then
		kitNaval("Landing")
	elseif family == "NavalCapital" then
		kitNaval("Capital")
	elseif family == "NavalSub" then
		kitNaval("Sub")
	else
		body.Size = Vector3.new(6 * s, 2 * s, 10 * s)
		body.Color = olive
		addPart(model, body, "Cabin", Vector3.new(4 * s, 1.5 * s, 4 * s), CFrame.new(0, 1.5 * s, -1 * s), oliveDark, Enum.Material.SmoothPlastic, nil, true)
		addWheels(model, body, s, {
			Vector3.new(-2.5, -1.2, 3),
			Vector3.new(2.5, -1.2, 3),
			Vector3.new(-2.5, -1.2, -3),
			Vector3.new(2.5, -1.2, -3),
		}, 1.1)
		seatOffset = CFrame.new(0, 2.0 * s, -1 * s)
	end

	local cat = def.Category or "Ground"
	local isAir = cat == "Air"
	local isNaval = cat == "Naval"
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 0.8, 2)
	seat.Color = Color3.fromRGB(70, 80, 60)
	seat.Material = Enum.Material.SmoothPlastic
	seat.CFrame = body.CFrame * seatOffset
	seat.Anchored = false
	seat.CanCollide = true
	seat.HeadsUpDisplay = false
	seat.Disabled = false
	seat.MaxSpeed = if isAir then math.min(def.Speed, 40) elseif isNaval then math.min(def.Speed, 55) else math.max(def.Speed, 45)
	seat.Torque = if isAir then 10 elseif isNaval then 22 else 55
	seat.TurnSpeed = if isAir then 1.6 elseif isNaval then 2.0 else 3.2
	seat.Disabled = false
	seat:SetAttribute("WE_DriverSeat", true)
	seat.Parent = model
	weldTo(body, seat)
	model:SetAttribute("WE_DriveMode", if isAir then "AirPlaceholder" elseif isNaval then "NavalSeat" else "VehicleSeat")
	model:SetAttribute("WE_Category", cat)
	model:SetAttribute("WE_KitFamily", family)
	if def.MeshAssetId and def.MeshAssetId ~= 0 then
		model:SetAttribute("MeshAssetId", def.MeshAssetId)
	end

	local extra = math.max(0, (def.Seats or 1) - 1)
	for i = 1, math.min(extra, 4) do
		local ps = Instance.new("Seat")
		ps.Name = "PassengerSeat" .. i
		ps.Size = Vector3.new(1.4, 0.5, 1.4)
		ps.Color = Color3.fromRGB(60, 70, 55)
		ps.CFrame = body.CFrame * CFrame.new((i % 2 == 0 and 1.4 or -1.4), seatOffset.Y, seatOffset.Z + 1.4 + math.floor((i - 1) / 2) * 1.5)
		ps.Anchored = false
		ps.CanCollide = true
		ps.Parent = model
		weldTo(body, ps)
	end

	addLabel(body, def.DisplayName, labelY)

	model.PrimaryPart = body
	-- Optional free Creator Store visual (non-colliding); Part kit stays authoritative
	pcall(function()
		VisualAssetService.TryAttachVehicleVisual(model, def.Id or "", family)
	end)
	CollectionService:AddTag(model, Constants.Tags.Vehicle)
	model.Parent = ensureFolder()
	return model
end

local function meetsStructureReq(profile: any, def: VehicleDef): (boolean, string?)
	local req = def.RequiresStructure
	if not req then
		return true, nil
	end
	local level = 0
	if profile.BaseUpgrades then
		level = profile.BaseUpgrades[req.StructureId] or 0
	end
	if level < req.Level then
		return false, "MissingStructure"
	end
	return true, nil
end

local function meetsPrestigeReq(profile: any, def: VehicleDef): (boolean, string?)
	local needP = def.RequiresPrestige
	if typeof(needP) == "number" and needP > 0 then
		if (profile.Prestige or 0) < needP then
			return false, "PrestigeTooLow"
		end
	end
	local flag = def.RequiresRebirthFlag
	if typeof(flag) == "string" and flag ~= "" then
		local unlocks = profile.RebirthUnlocks
		if typeof(unlocks) ~= "table" or unlocks[flag] ~= true then
			return false, "MissingRebirthUnlock"
		end
	end
	return true, nil
end


local function startAirPlaceholderDrive(userId: number, model: Model, def: VehicleDef)
	stopAirDrive(userId)
	local body = model.PrimaryPart
	local seat = model:FindFirstChild("DriverSeat")
	if not (body and body:IsA("BasePart") and seat and seat:IsA("VehicleSeat")) then
		return
	end
	-- Lightweight placeholder flight: throttle → forward, steer → yaw, slight hover
	local attachment = body:FindFirstChild("WE_AirAttach") :: Attachment?
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "WE_AirAttach"
		attachment.Parent = body
	end
	local lv = body:FindFirstChild("WE_AirVelocity") :: LinearVelocity?
	if not lv then
		lv = Instance.new("LinearVelocity")
		lv.Name = "WE_AirVelocity"
		lv.Attachment0 = attachment
		lv.RelativeTo = Enum.ActuatorRelativeTo.World
		lv.MaxForce = 1e6
		lv.VectorVelocity = Vector3.zero
		lv.Parent = body
	end
	local av = body:FindFirstChild("WE_AirAngular") :: AngularVelocity?
	if not av then
		av = Instance.new("AngularVelocity")
		av.Name = "WE_AirAngular"
		av.Attachment0 = attachment
		av.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
		av.MaxTorque = 1e5
		av.AngularVelocity = Vector3.zero
		av.Parent = body
	end

	local cruise = def.Speed
	local hoverY = body.Position.Y
	airDriveConns[userId] = RunService.Heartbeat:Connect(function(_dt)
		if not model.Parent or not body.Parent then
			stopAirDrive(userId)
			return
		end
		local occupied = seat.Occupant ~= nil
		if not occupied then
			lv.VectorVelocity = Vector3.zero
			av.AngularVelocity = Vector3.zero
			return
		end
		local throttle = seat.ThrottleFloat
		local steer = seat.SteerFloat
		-- Hold altitude near spawn hover band; throttle climbs/dives a bit
		local targetY = hoverY + throttle * 12
		local yCorr = math.clamp((targetY - body.Position.Y) * 2.5, -40, 40)
		local look = body.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.05 then
			flat = Vector3.new(0, 0, -1)
		else
			flat = flat.Unit
		end
		local speed = cruise * math.clamp(math.abs(throttle) + 0.15, 0.15, 1)
		if throttle < 0 then
			speed *= 0.55
		end
		local forwardSign = if throttle >= 0 then 1 else -0.4
		local vel = flat * (speed * forwardSign) + Vector3.new(0, yCorr, 0)
		lv.VectorVelocity = vel
		av.AngularVelocity = Vector3.new(0, -steer * 1.8, 0)
	end)
end

function VehicleService.Owns(player: Player, vehicleId: string): boolean
	local profile = DataService.GetProfile(player)
	return profile ~= nil and profile.Vehicles[vehicleId] == true
end

function VehicleService.GrantVehicle(player: Player, vehicleId: string)
	local profile = DataService.GetProfile(player)
	if not profile or not getDef(vehicleId) then
		return
	end
	profile.Vehicles[vehicleId] = true
	DataService.MarkDirty(player)
	pushState(player)
end

function VehicleService.Purchase(player: Player, vehicleId: any): (boolean, string?)
	if not RemoteGuard.IsIdString(vehicleId, 48) then
		return false, "InvalidId"
	end
	local def = getDef(vehicleId)
	if not def then
		return false, "UnknownVehicle"
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end
	if profile.Vehicles[vehicleId] then
		return false, "AlreadyOwned"
	end
	if profile.Level < def.UnlockLevel then
		return false, "LevelTooLow"
	end
	local okStruct, structErr = meetsStructureReq(profile, def)
	if not okStruct then
		return false, structErr
	end
	local okPres, presErr = meetsPrestigeReq(profile, def)
	if not okPres then
		return false, presErr
	end
	local cost = def.CostCash or 0
	if cost > 0 then
		local ok, err = EconomyService.SpendCash(player, cost, "vehicle_" .. vehicleId)
		if not ok then
			return false, err or "SpendFailed"
		end
	end
	profile.Vehicles[vehicleId] = true
	DataService.MarkDirty(player)
	if AnalyticsService then
		AnalyticsService.Log(AnalyticsConfig.Events.VEHICLE_PURCHASED, player.UserId, {
			vehicle = vehicleId,
			cost = cost,
		})
	end
	if NotificationService then
		NotificationService.Notify(player, "Acquired " .. def.DisplayName, "Reward")
	end
	pushState(player)
	return true, nil
end

function VehicleService.Despawn(player: Player)
	destroyActive(player.UserId)
	pushState(player)
end

function VehicleService.RequestSpawn(player: Player, vehicleId: any): (boolean, string?)
	if not RemoteGuard.IsIdString(vehicleId, 48) then
		return false, "InvalidId"
	end
	local def = getDef(vehicleId)
	if not def then
		return false, "UnknownVehicle"
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end
	if not profile.Vehicles[vehicleId] then
		return false, "NotOwned"
	end
	if profile.Level < def.UnlockLevel then
		return false, "LevelTooLow"
	end
	local okStruct, structErr = meetsStructureReq(profile, def)
	if not okStruct then
		return false, structErr
	end
	local okPres, presErr = meetsPrestigeReq(profile, def)
	if not okPres then
		return false, presErr
	end
	if cooldownLeft(player.UserId, player) > 0 then
		return false, "Cooldown"
	end

	destroyActive(player.UserId)
	local at, source = findSpawnCFrame(player, def.Category)
	local buildOk, modelOrErr = pcall(function()
		return buildVehicleModel(def, at, player.UserId)
	end)
	if not buildOk or typeof(modelOrErr) ~= "Instance" then
		warn("[VehicleService] buildVehicleModel failed", vehicleId, modelOrErr)
		return false, "SpawnBuildFailed"
	end
	local model = modelOrErr :: Model
	if not model.PrimaryPart or not model:FindFirstChild("DriverSeat") then
		warn("[VehicleService] spawn kit incomplete", vehicleId, "PrimaryPart/DriverSeat missing")
		pcall(function()
			model:Destroy()
		end)
		return false, "SpawnKitIncomplete"
	end
	if not model.Parent then
		warn("[VehicleService] spawn model unparented", vehicleId)
		pcall(function()
			model:Destroy()
		end)
		return false, "SpawnOrphaned"
	end

	activeVehicles[player.UserId] = model
	lastSpawnAt[player.UserId] = now()
	local driveMode = model:GetAttribute("WE_DriveMode")
	if driveMode == "AirPlaceholder" then
		startAirPlaceholderDrive(player.UserId, model, def)
	end

	-- Driveability: network ownership + auto-sit DriverSeat so garage SPAWN is immediately usable
	do
		local chassis = model.PrimaryPart
		local seat = model:FindFirstChild("DriverSeat")
		if chassis and chassis:IsA("BasePart") then
			chassis.Anchored = false
			pcall(function()
				chassis:SetNetworkOwner(player)
			end)
		end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = false
			end
		end
		if seat and seat:IsA("VehicleSeat") then
			seat.Disabled = false
			seat.Anchored = false
			task.defer(function()
				if not player.Parent or not model.Parent then
					return
				end
				local character = player.Character
				local hum = character and character:FindFirstChildOfClass("Humanoid")
				if hum and seat.Parent and seat.Occupant == nil then
					pcall(function()
						seat:Sit(hum)
					end)
				end
				if chassis and chassis:IsA("BasePart") then
					pcall(function()
						chassis:SetNetworkOwner(player)
					end)
				end
			end)
		end
	end

	if profile.Stats then
		profile.Stats.VehiclesSpawned = (profile.Stats.VehiclesSpawned or 0) + 1
	end
	if MissionService and MissionService.TrackProgress then
		MissionService.TrackProgress(player, "SpawnVehicle", 1)
	end
	if TutorialService and TutorialService.Notify then
		TutorialService.Notify(player, "SpawnVehicle", vehicleId)
	end
	DataService.MarkDirty(player)

	if AnalyticsService then
		AnalyticsService.Log(AnalyticsConfig.Events.VEHICLE_SPAWNED, player.UserId, {
			vehicle = vehicleId,
			source = source,
		})
	end
	print(string.format(
		"[VehicleService] SPAWN ok %s → %s @ %s (%.0f,%.0f,%.0f)",
		player.Name,
		tostring(vehicleId),
		source,
		at.Position.X,
		at.Position.Y,
		at.Position.Z
	))
	if NotificationService then
		NotificationService.Notify(player, "Deployed " .. def.DisplayName, "Success")
	end
	pushState(player)
	return true, nil
end

function VehicleService.PushState(player: Player)
	pushState(player)
end

function VehicleService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	AnalyticsService = deps.AnalyticsService
	RateLimitService = deps.RateLimitService
	NotificationService = deps.NotificationService
	RemoteSetup = deps.RemoteSetup
	TerritoryService = deps.TerritoryService
	MissionService = deps.MissionService
	TutorialService = deps.TutorialService

	ensureFolder()

	local spawnRemote = RemoteSetup.Get(Constants.RemoteNames.RequestSpawnVehicle) :: RemoteEvent
	spawnRemote.OnServerEvent:Connect(function(player: Player, vehicleId: any)
		if not RateLimitService.Allow(player, "spawn_vehicle", 1, 2) then
			if NotificationService then
				NotificationService.Notify(player, "Spawn too fast — wait a moment", "Warn", 2)
			end
			return
		end
		print(string.format("[VehicleService] Remote SPAWN attempt %s → %s", player.Name, tostring(vehicleId)))
		local ok, err = VehicleService.RequestSpawn(player, vehicleId)
		print(string.format("[VehicleService] Remote SPAWN result %s → Ok=%s Err=%s", player.Name, tostring(ok), tostring(err)))
		if not ok and NotificationService and err then
			local msg = "Cannot spawn: " .. tostring(err)
			if err == "Cooldown" then
				msg = "Vehicle spawn cooling down"
			elseif err == "NotOwned" then
				msg = "Buy this vehicle first"
			elseif err == "SpawnBuildFailed" or err == "SpawnKitIncomplete" or err == "SpawnOrphaned" then
				msg = "Spawn failed — try again near a garage pad"
			end
			NotificationService.Notify(player, msg, "Warn")
		end
	end)

	local purchaseRemote = RemoteSetup.Get(Constants.RemoteNames.RequestPurchaseVehicle) :: RemoteEvent
	purchaseRemote.OnServerEvent:Connect(function(player: Player, vehicleId: any)
		if not RateLimitService.Allow(player, "buy_vehicle", 2, 3) then
			return
		end
		local ok, err = VehicleService.Purchase(player, vehicleId)
		if not ok and NotificationService and err then
			NotificationService.Notify(player, "Cannot buy vehicle: " .. tostring(err), "Warn")
		end
	end)

	local despawnRemote = RemoteSetup.Get(Constants.RemoteNames.RequestDespawnVehicle) :: RemoteEvent
	despawnRemote.OnServerEvent:Connect(function(player: Player)
		if not RateLimitService.Allow(player, "despawn_vehicle", 2, 3) then
			return
		end
		VehicleService.Despawn(player)
	end)

	DataService.OnProfileLoaded(function(player: Player, profile: any)
		local starter = VehicleConfig.StarterVehicle
		if not profile.Vehicles[starter] then
			profile.Vehicles[starter] = true
			DataService.MarkDirty(player)
		end
		pushState(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		destroyActive(player.UserId)
		lastSpawnAt[player.UserId] = nil
	end)
end

return VehicleService
