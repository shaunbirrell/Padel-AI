--!strict
--[[
	Phase 4 — Vehicles & garage (server-authoritative).
	Validates ownership, level, structure requirements, cash, cooldown.
	Spawns placeholder chassis + VehicleSeat near plot / WE_VehicleSpawn.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Types = require(Shared.Types)
local VehicleConfig = require(Shared.Configs.VehicleConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)

type VehicleDef = VehicleConfig.VehicleDef

local VehicleService = {}

local DataService: any = nil
local EconomyService: any = nil
local AnalyticsService: any = nil
local RateLimitService: any = nil
local NotificationService: any = nil
local RemoteSetup: any = nil

local activeVehicles: { [number]: Model } = {}
local lastSpawnAt: { [number]: number } = {}
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

local function cooldownLeft(userId: number): number
	local last = lastSpawnAt[userId]
	if not last then
		return 0
	end
	local cd = VehicleConfig.SpawnCooldownSeconds or 15
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
		CooldownRemaining = cooldownLeft(player.UserId),
	}
	local remote = RemoteSetup.Get(Constants.RemoteNames.VehicleStateUpdate) :: RemoteEvent
	remote:FireClient(player, payload)
end

local function destroyActive(userId: number)
	local model = activeVehicles[userId]
	activeVehicles[userId] = nil
	if model and model.Parent then
		model:Destroy()
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

local function buildVehicleModel(def: VehicleDef, at: CFrame, ownerUserId: number): Model
	local model = Instance.new("Model")
	model.Name = def.DisplayName
	model:SetAttribute("VehicleId", def.Id)
	model:SetAttribute("OwnerUserId", ownerUserId)

	local scale = ({
		Common = 1.0,
		Uncommon = 1.1,
		Rare = 1.25,
		Epic = 1.4,
		Legendary = 1.55,
	})[def.Rarity] or 1.0

	local body = Instance.new("Part")
	body.Name = "Chassis"
	body.Size = Vector3.new(6 * scale, 2, 10 * scale)
	body.Color = Color3.fromRGB(55, 70, 50)
	body.Material = Enum.Material.Metal
	body.CFrame = at
	body.Anchored = false
	body.CanCollide = true
	body.Parent = model

	local cabin = Instance.new("Part")
	cabin.Name = "Cabin"
	cabin.Size = Vector3.new(4 * scale, 1.5, 4)
	cabin.Color = Color3.fromRGB(40, 50, 40)
	cabin.Material = Enum.Material.SmoothPlastic
	cabin.CFrame = at * CFrame.new(0, 1.75, -1)
	cabin.CanCollide = true
	cabin.Parent = model

	local weldCabin = Instance.new("WeldConstraint")
	weldCabin.Part0 = body
	weldCabin.Part1 = cabin
	weldCabin.Parent = body

	for _, offset in ipairs({
		Vector3.new(-2.5, -1.2, 3),
		Vector3.new(2.5, -1.2, 3),
		Vector3.new(-2.5, -1.2, -3),
		Vector3.new(2.5, -1.2, -3),
	}) do
		local wheel = Instance.new("Part")
		wheel.Name = "Wheel"
		wheel.Shape = Enum.PartType.Cylinder
		wheel.Size = Vector3.new(1.2, 2.2, 2.2)
		wheel.Color = Color3.fromRGB(25, 25, 25)
		wheel.CFrame = at * CFrame.new(offset) * CFrame.Angles(0, 0, math.rad(90))
		wheel.CanCollide = true
		wheel.Parent = model
		local w = Instance.new("WeldConstraint")
		w.Part0 = body
		w.Part1 = wheel
		w.Parent = body
	end

	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 1, 2)
	seat.Color = Color3.fromRGB(80, 90, 70)
	seat.CFrame = at * CFrame.new(0, 2.2, -1)
	seat.HeadsUpDisplay = false
	seat.MaxSpeed = def.Speed
	seat.Torque = 20
	seat.TurnSpeed = 2
	seat.Parent = model

	local weldSeat = Instance.new("WeldConstraint")
	weldSeat.Part0 = body
	weldSeat.Part1 = seat
	weldSeat.Parent = body

	local extra = math.max(0, (def.Seats or 1) - 1)
	for i = 1, math.min(extra, 3) do
		local ps = Instance.new("Seat")
		ps.Name = "PassengerSeat" .. i
		ps.Size = Vector3.new(1.5, 0.6, 1.5)
		ps.Color = Color3.fromRGB(70, 80, 60)
		ps.CFrame = at * CFrame.new((i - 2) * 1.6, 2.0, 1.5)
		ps.Parent = model
		local ww = Instance.new("WeldConstraint")
		ww.Part0 = body
		ww.Part1 = ps
		ww.Parent = body
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(140, 36)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = cabin
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 0.35
	label.BackgroundColor3 = Color3.fromRGB(20, 24, 20)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = def.DisplayName
	label.Parent = billboard

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
	if typeof(vehicleId) ~= "string" then
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
	if typeof(vehicleId) ~= "string" then
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
	if cooldownLeft(player.UserId) > 0 then
		return false, "Cooldown"
	end

	destroyActive(player.UserId)
	local model = buildVehicleModel(def, findSpawnCFrame(player), player.UserId)
	activeVehicles[player.UserId] = model
	lastSpawnAt[player.UserId] = now()

	if profile.Stats then
		profile.Stats.VehiclesSpawned = (profile.Stats.VehiclesSpawned or 0) + 1
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
