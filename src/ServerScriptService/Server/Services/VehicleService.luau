--!strict
--[[
	Phase 4 — Vehicles & garage (server-authoritative).
	Validates ownership, level, structure requirements, cash, cooldown.
	Spawns multi-part vehicle kits + VehicleSeat near plot / WE_VehicleSpawn.
	Optional VehicleDef.MeshAssetId (non-zero) reserved for future MeshPart swap.
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

local function findSpawnCFrame(player: Player): CFrame
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local origin = if root then root.Position else Vector3.zero
	local best: CFrame? = nil
	local bestDist = math.huge

	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.VehicleSpawn)) do
		if inst:IsA("BasePart") then
			local d = (inst.Position - origin).Magnitude
			if d < bestDist then
				bestDist = d
				best = inst.CFrame + Vector3.new(0, 4, 0)
			end
		end
	end
	if best and bestDist < 250 then
		return best
	end

	local profile = DataService.GetProfile(player)
	if profile and profile.BasePlotId then
		for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.BasePlot)) do
			if inst:IsA("BasePart") and inst:GetAttribute("PlotId") == profile.BasePlotId then
				return inst.CFrame + Vector3.new(0, 5, 40)
			end
		end
	end

	if root then
		return root.CFrame * CFrame.new(0, 3, -12)
	end
	return CFrame.new(0, 5, 0)
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
		wheel.Massless = false
		wheel.Parent = model
		weldTo(body, wheel)
	end
end

local function addLabel(parent: BasePart, text: string, y: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "VehicleLabel"
	billboard.Size = UDim2.fromOffset(150, 36)
	billboard.StudsOffset = Vector3.new(0, y, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 160
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
	local olive = Color3.fromRGB(55, 70, 48)
	local oliveDark = Color3.fromRGB(40, 50, 38)
	local armor = Color3.fromRGB(62, 68, 55)
	local armorDark = Color3.fromRGB(45, 50, 42)
	local sand = Color3.fromRGB(110, 100, 70)
	local accent = Color3.fromRGB(230, 190, 60)
	local blueAcc = Color3.fromRGB(90, 160, 220)
	local redAcc = Color3.fromRGB(200, 80, 60)
	local sky = Color3.fromRGB(70, 90, 110)

	local body = Instance.new("Part")
	body.Name = "Chassis"
	body.Anchored = false
	body.CanCollide = true
	body.Material = Enum.Material.Metal
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.CFrame = at
	body.Parent = model

	local seatOffset = CFrame.new(0, 2.0, -0.5)
	local labelY = 4.5

	if id == "MilitaryJeep" or id == "ArmedJeep" then
		local armed = id == "ArmedJeep"
		body.Size = Vector3.new(5.2, 1.6, 8.5)
		body.Color = if armed then Color3.fromRGB(48, 58, 42) else olive
		addPart(model, body, "Hood", Vector3.new(4.6, 0.7, 2.8), CFrame.new(0, 0.9, -2.6), oliveDark, Enum.Material.Metal, nil, false)
		addPart(model, body, "Cabin", Vector3.new(4.4, 1.4, 2.8), CFrame.new(0, 1.3, 0.2), oliveDark, Enum.Material.SmoothPlastic, nil, true)
		addPart(model, body, "Bed", Vector3.new(4.4, 0.9, 2.6), CFrame.new(0, 0.7, 2.6), olive, Enum.Material.Metal, nil, false)
		addPart(model, body, "Bumper", Vector3.new(5.0, 0.5, 0.4), CFrame.new(0, -0.3, -4.3), Color3.fromRGB(30, 30, 30), Enum.Material.Metal, nil, false)
		addPart(model, body, "AccentStrip", Vector3.new(4.8, 0.12, 0.35), CFrame.new(0, 1.1, -1.2), if armed then redAcc else accent, Enum.Material.Neon, nil, false)
		if armed then
			addPart(model, body, "GunMount", Vector3.new(0.8, 0.8, 0.8), CFrame.new(0, 2.2, 0.4), Color3.fromRGB(35, 35, 35), Enum.Material.Metal, nil, false)
			addPart(model, body, "Barrel", Vector3.new(0.25, 0.25, 2.4), CFrame.new(0, 2.5, -1.0), Color3.fromRGB(40, 40, 40), Enum.Material.Metal, nil, false)
		end
		addWheels(model, body, 1, {
			Vector3.new(-2.4, -0.9, 2.8),
			Vector3.new(2.4, -0.9, 2.8),
			Vector3.new(-2.4, -0.9, -2.8),
			Vector3.new(2.4, -0.9, -2.8),
		}, 1.05)
		seatOffset = CFrame.new(0, 1.9, 0.1)
		labelY = 4.2
	elseif id == "ArmoredTruck" then
		body.Size = Vector3.new(6.2, 2.4, 11)
		body.Color = armor
		addPart(model, body, "Cabin", Vector3.new(5.6, 2.0, 3.2), CFrame.new(0, 1.6, -3.2), armorDark, Enum.Material.Metal, nil, true)
		addPart(model, body, "Cargo", Vector3.new(5.8, 2.6, 6.5), CFrame.new(0, 1.4, 2.0), sand, Enum.Material.Metal, nil, true)
		addPart(model, body, "Accent", Vector3.new(5.9, 0.15, 0.4), CFrame.new(0, 2.5, -2.0), accent, Enum.Material.Neon, nil, false)
		addWheels(model, body, 1.15, {
			Vector3.new(-2.8, -1.2, 3.5),
			Vector3.new(2.8, -1.2, 3.5),
			Vector3.new(-2.8, -1.2, 0),
			Vector3.new(2.8, -1.2, 0),
			Vector3.new(-2.8, -1.2, -3.5),
			Vector3.new(2.8, -1.2, -3.5),
		}, 1.2)
		seatOffset = CFrame.new(0, 2.4, -3.0)
		labelY = 5.5
	elseif id == "APC" then
		body.Size = Vector3.new(6.5, 2.6, 10.5)
		body.Color = armorDark
		addPart(model, body, "HullTop", Vector3.new(5.8, 1.4, 8.5), CFrame.new(0, 1.8, 0), armor, Enum.Material.Metal, nil, true)
		addPart(model, body, "Turret", Vector3.new(2.4, 1.2, 2.4), CFrame.new(0, 3.0, 0.5), Color3.fromRGB(50, 55, 48), Enum.Material.Metal, nil, false)
		addPart(model, body, "Barrel", Vector3.new(0.35, 0.35, 3.2), CFrame.new(0, 3.1, -2.0), Color3.fromRGB(35, 35, 35), Enum.Material.Metal, nil, false)
		addPart(model, body, "Accent", Vector3.new(6.0, 0.12, 0.35), CFrame.new(0, 2.6, -3), blueAcc, Enum.Material.Neon, nil, false)
		addWheels(model, body, 1.2, {
			Vector3.new(-3.0, -1.3, 3.2),
			Vector3.new(3.0, -1.3, 3.2),
			Vector3.new(-3.0, -1.3, 0.5),
			Vector3.new(3.0, -1.3, 0.5),
			Vector3.new(-3.0, -1.3, -2.5),
			Vector3.new(3.0, -1.3, -2.5),
		}, 1.25)
		seatOffset = CFrame.new(0, 2.2, -2.5)
		labelY = 5.8
	elseif id == "LightTank" or id == "HeavyTank" then
		local heavy = id == "HeavyTank"
		local s = if heavy then 1.25 else 1.0
		body.Size = Vector3.new(6.5 * s, 2.2 * s, 9.5 * s)
		body.Color = if heavy then Color3.fromRGB(50, 55, 45) else armor
		addPart(model, body, "TrackL", Vector3.new(1.2 * s, 1.6 * s, 9 * s), CFrame.new(-3.2 * s, -0.4, 0), Color3.fromRGB(30, 32, 28), Enum.Material.Metal, nil, true)
		addPart(model, body, "TrackR", Vector3.new(1.2 * s, 1.6 * s, 9 * s), CFrame.new(3.2 * s, -0.4, 0), Color3.fromRGB(30, 32, 28), Enum.Material.Metal, nil, true)
		addPart(model, body, "Turret", Vector3.new(3.6 * s, 1.6 * s, 4.2 * s), CFrame.new(0, 2.0 * s, 0.3), armorDark, Enum.Material.Metal, nil, true)
		addPart(model, body, "Barrel", Vector3.new(0.45 * s, 0.45 * s, (if heavy then 6.5 else 5) * s), CFrame.new(0, 2.1 * s, -4.2 * s), Color3.fromRGB(35, 35, 35), Enum.Material.Metal, nil, false)
		addPart(model, body, "Accent", Vector3.new(3.2 * s, 0.12, 0.3), CFrame.new(0, 2.9 * s, 1.2), if heavy then redAcc else accent, Enum.Material.Neon, nil, false)
		-- Road wheels (visual)
		for i, z in ipairs({ 3.2, 1.0, -1.2, -3.2 }) do
			addPart(model, body, "RoadL" .. i, Vector3.new(0.7 * s, 1.3 * s, 1.3 * s), CFrame.new(-3.2 * s, -1.0 * s, z * s) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(25, 25, 25), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, true)
			addPart(model, body, "RoadR" .. i, Vector3.new(0.7 * s, 1.3 * s, 1.3 * s), CFrame.new(3.2 * s, -1.0 * s, z * s) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(25, 25, 25), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, true)
		end
		seatOffset = CFrame.new(0, 2.6 * s, 0.2)
		labelY = 5.5 * s
	elseif id == "AttackHelicopter" then
		body.Size = Vector3.new(3.2, 2.0, 10)
		body.Color = sky
		addPart(model, body, "Cockpit", Vector3.new(2.6, 1.6, 3.2), CFrame.new(0, 0.6, -3.2), Color3.fromRGB(40, 55, 70), Enum.Material.Glass, nil, true)
		addPart(model, body, "Tail", Vector3.new(1.0, 1.0, 6), CFrame.new(0, 0.8, 6.5), sky, Enum.Material.Metal, nil, false)
		addPart(model, body, "TailFin", Vector3.new(0.3, 2.4, 1.6), CFrame.new(0, 2.0, 9.0), Color3.fromRGB(50, 65, 80), Enum.Material.Metal, nil, false)
		addPart(model, body, "RotorHub", Vector3.new(1.2, 0.6, 1.2), CFrame.new(0, 2.0, -0.5), Color3.fromRGB(30, 30, 30), Enum.Material.Metal, nil, false)
		addPart(model, body, "RotorA", Vector3.new(14, 0.15, 0.6), CFrame.new(0, 2.35, -0.5), Color3.fromRGB(35, 35, 38), Enum.Material.Metal, nil, false)
		addPart(model, body, "RotorB", Vector3.new(0.6, 0.15, 14), CFrame.new(0, 2.4, -0.5), Color3.fromRGB(35, 35, 38), Enum.Material.Metal, nil, false)
		addPart(model, body, "SkidL", Vector3.new(0.25, 0.25, 7), CFrame.new(-1.6, -1.3, 0), Color3.fromRGB(40, 40, 40), Enum.Material.Metal, nil, true)
		addPart(model, body, "SkidR", Vector3.new(0.25, 0.25, 7), CFrame.new(1.6, -1.3, 0), Color3.fromRGB(40, 40, 40), Enum.Material.Metal, nil, true)
		addPart(model, body, "Accent", Vector3.new(2.8, 0.12, 0.35), CFrame.new(0, 1.2, -1), redAcc, Enum.Material.Neon, nil, false)
		addPart(model, body, "StubWingL", Vector3.new(3.5, 0.25, 1.2), CFrame.new(-2.5, 0, 0.5), Color3.fromRGB(55, 70, 85), Enum.Material.Metal, nil, false)
		addPart(model, body, "StubWingR", Vector3.new(3.5, 0.25, 1.2), CFrame.new(2.5, 0, 0.5), Color3.fromRGB(55, 70, 85), Enum.Material.Metal, nil, false)
		seatOffset = CFrame.new(0, 1.2, -2.8)
		labelY = 5.5
	elseif id == "FighterJet" then
		body.Size = Vector3.new(2.4, 1.4, 12)
		body.Color = Color3.fromRGB(90, 95, 100)
		addPart(model, body, "Nose", Vector3.new(1.4, 1.0, 3.5), CFrame.new(0, 0.1, -6.5), Color3.fromRGB(70, 75, 80), Enum.Material.Metal, nil, false)
		addPart(model, body, "Cockpit", Vector3.new(1.6, 0.9, 2.2), CFrame.new(0, 0.9, -3.5), Color3.fromRGB(40, 80, 120), Enum.Material.Glass, nil, false)
		addPart(model, body, "WingL", Vector3.new(7, 0.25, 2.8), CFrame.new(-4.0, 0, 0.5), Color3.fromRGB(80, 85, 90), Enum.Material.Metal, nil, false)
		addPart(model, body, "WingR", Vector3.new(7, 0.25, 2.8), CFrame.new(4.0, 0, 0.5), Color3.fromRGB(80, 85, 90), Enum.Material.Metal, nil, false)
		addPart(model, body, "TailFin", Vector3.new(0.25, 2.8, 2.0), CFrame.new(0, 1.8, 5.0), Color3.fromRGB(85, 90, 95), Enum.Material.Metal, nil, false)
		addPart(model, body, "StabL", Vector3.new(2.5, 0.2, 1.2), CFrame.new(-1.5, 0.8, 5.0), Color3.fromRGB(80, 85, 90), Enum.Material.Metal, nil, false)
		addPart(model, body, "StabR", Vector3.new(2.5, 0.2, 1.2), CFrame.new(1.5, 0.8, 5.0), Color3.fromRGB(80, 85, 90), Enum.Material.Metal, nil, false)
		addPart(model, body, "IntakeL", Vector3.new(0.9, 0.9, 2.5), CFrame.new(-1.3, -0.2, 1.5), Color3.fromRGB(50, 50, 55), Enum.Material.Metal, nil, false)
		addPart(model, body, "IntakeR", Vector3.new(0.9, 0.9, 2.5), CFrame.new(1.3, -0.2, 1.5), Color3.fromRGB(50, 50, 55), Enum.Material.Metal, nil, false)
		addPart(model, body, "Accent", Vector3.new(2.0, 0.1, 0.3), CFrame.new(0, 0.8, -1), accent, Enum.Material.Neon, nil, false)
		-- Landing gear dots
		addPart(model, body, "GearF", Vector3.new(0.3, 0.8, 0.3), CFrame.new(0, -1.0, -4), Color3.fromRGB(30, 30, 30), Enum.Material.Metal, nil, true)
		addPart(model, body, "GearL", Vector3.new(0.3, 0.8, 0.3), CFrame.new(-1.5, -1.0, 1), Color3.fromRGB(30, 30, 30), Enum.Material.Metal, nil, true)
		addPart(model, body, "GearR", Vector3.new(0.3, 0.8, 0.3), CFrame.new(1.5, -1.0, 1), Color3.fromRGB(30, 30, 30), Enum.Material.Metal, nil, true)
		seatOffset = CFrame.new(0, 1.3, -3.2)
		labelY = 4.8
	else
		-- Fallback generic
		body.Size = Vector3.new(6, 2, 10)
		body.Color = olive
		addPart(model, body, "Cabin", Vector3.new(4, 1.5, 4), CFrame.new(0, 1.5, -1), oliveDark, Enum.Material.SmoothPlastic, nil, true)
		addWheels(model, body, 1, {
			Vector3.new(-2.5, -1.2, 3),
			Vector3.new(2.5, -1.2, 3),
			Vector3.new(-2.5, -1.2, -3),
			Vector3.new(2.5, -1.2, -3),
		}, 1.1)
		seatOffset = CFrame.new(0, 2.0, -1)
	end

	local isAir = id == "AttackHelicopter" or id == "FighterJet"
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
	seat.MaxSpeed = if isAir then math.min(def.Speed, 40) else def.Speed
	seat.Torque = if isAir then 8 else 28
	seat.TurnSpeed = if isAir then 1.4 else 2.4
	seat.Parent = model
	weldTo(body, seat)
	model:SetAttribute("WE_DriveMode", if isAir then "AirPlaceholder" else "VehicleSeat")
	-- Reserved MeshAssetId hook (0 / nil = Part kit; art pass may swap later)
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
	if cooldownLeft(player.UserId, player) > 0 then
		return false, "Cooldown"
	end

	destroyActive(player.UserId)
	local model = buildVehicleModel(def, findSpawnCFrame(player), player.UserId)
	activeVehicles[player.UserId] = model
	lastSpawnAt[player.UserId] = now()
	local driveMode = model:GetAttribute("WE_DriveMode")
	if driveMode == "AirPlaceholder" then
		startAirPlaceholderDrive(player.UserId, model, def)
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
		AnalyticsService.Log(AnalyticsConfig.Events.VEHICLE_SPAWNED, player.UserId, { vehicle = vehicleId })
	end
	if NotificationService then
		NotificationService.Notify(player, "Deployed " .. def.DisplayName, "Info")
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
			return
		end
		local ok, err = VehicleService.RequestSpawn(player, vehicleId)
		if not ok and NotificationService and err then
			NotificationService.Notify(player, "Cannot spawn: " .. tostring(err), "Warn")
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
