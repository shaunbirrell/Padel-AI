--!strict
--[[
	Gate door defense — 2 GateGuards patrol + shoot enemies; L4+ AutoGun nests.
	Reads GatePost parts from WE_PerimeterWalls (does NOT edit StructureKitBuilder).
	Design Bot GATE_DEFENSE_WIRE: Guard 16134469614, AutoGun 4923345827, sandbag dress.
	Aggro covers MoneyCollector ATM approach (raid deterrent). No exotic persist.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local InsertService = game:GetService("InsertService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local GateDefenseConfig = require(Shared.Configs.GateDefenseConfig)
local VisualAssetConfig = require(Shared.Configs.VisualAssetConfig)

local GateDefenseService = {}

local BaseService: any = nil
local DataService: any = nil
local VisualAssetService: any = nil
local NationColorService: any = nil

local PERIMETER_FOLDER = "WE_PerimeterWalls"
local DEFENSE_FOLDER = "WE_GateDefense"
local TAG_COLLECTOR = Constants.Tags.MoneyCollector

type GuardUnit = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Slot: number, -- 1 left, 2 right
	LastFireAt: number,
	WaypointIndex: number,
	IdleUntil: number,
	Alive: boolean,
	PostCf: CFrame,
}

type TurretUnit = {
	Model: Model,
	YawPart: BasePart,
	Slot: number,
	LastFireAt: number,
}

type PlotDefense = {
	PlotId: number,
	OwnerUserId: number,
	WallsLevel: number,
	Folder: Folder,
	Guards: { GuardUnit },
	Turrets: { TurretUnit },
	GateCf: CFrame,
	CollectorPos: Vector3?,
}

local defenses: { [number]: PlotDefense } = {}
local victimHitAt: { [number]: number } = {}
local catalogCache: { [number]: Model } = {}
local catalogFailed: { [number]: boolean } = {}

local function nowClock(): number
	return os.clock()
end

local function stripScripts(root: Instance)
	if VisualAssetConfig.StripScripts == false then
		return
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BaseScript") or d:IsA("ModuleScript") then
			d:Destroy()
		end
	end
	for _, c in ipairs(root:GetChildren()) do
		if c:IsA("BaseScript") or c:IsA("ModuleScript") then
			c:Destroy()
		end
	end
end

local function loadCatalogModel(assetId: number): Model?
	if assetId <= 0 or catalogFailed[assetId] then
		return nil
	end
	if catalogCache[assetId] then
		return catalogCache[assetId]
	end
	local ok, result = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok or typeof(result) ~= "Instance" then
		catalogFailed[assetId] = true
		return nil
	end
	local container = result :: Instance
	stripScripts(container)
	local model: Model? = nil
	if container:IsA("Model") then
		model = container
	else
		for _, c in ipairs(container:GetChildren()) do
			if c:IsA("Model") then
				model = c
				break
			end
		end
	end
	if not model then
		catalogFailed[assetId] = true
		pcall(function()
			container:Destroy()
		end)
		return nil
	end
	stripScripts(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.Massless = true
		end
	end
	model.Parent = nil
	catalogCache[assetId] = model
	if container ~= model then
		pcall(function()
			container:Destroy()
		end)
	end
	return model
end

local function scaleModelLongAxis(model: Model, targetStuds: number)
	local ok, size = pcall(function()
		return model:GetExtentsSize()
	end)
	if not ok or typeof(size) ~= "Vector3" then
		return
	end
	local longest = math.max(size.X, size.Y, size.Z)
	if longest < 0.05 then
		return
	end
	local factor = targetStuds / longest
	factor = math.clamp(factor, 0.05, 40)
	pcall(function()
		model:ScaleTo(factor)
	end)
end

local function findPlotFolder(plotId: number): Folder?
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	local bases = setup and setup:FindFirstChild("Bases")
	if not bases then
		return nil
	end
	local f = bases:FindFirstChild("Plot" .. tostring(plotId))
	if f and f:IsA("Folder") then
		return f
	end
	return nil
end

local function gatherGatePosts(plotFolder: Folder): { BasePart }
	local posts: { BasePart } = {}
	local peri = plotFolder:FindFirstChild(PERIMETER_FOLDER)
	local root = if peri then peri else plotFolder
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "GatePost" then
			table.insert(posts, d)
		end
	end
	return posts
end

local function computeGateCFrame(plotFolder: Folder, posts: { BasePart }): CFrame?
	if #posts < 2 then
		if #posts == 1 then
			local spawn = plotFolder:FindFirstChild("PlayerSpawn")
			local look = if spawn and spawn:IsA("BasePart")
				then (spawn.Position - posts[1].Position) * Vector3.new(1, 0, 1)
				else posts[1].CFrame.LookVector * Vector3.new(1, 0, 1)
			if look.Magnitude < 0.05 then
				look = Vector3.new(0, 0, 1)
			end
			local mid = posts[1].Position
			local y = mid.Y - posts[1].Size.Y * 0.5 + 3
			return CFrame.lookAt(Vector3.new(mid.X, y, mid.Z), Vector3.new(mid.X, y, mid.Z) + look.Unit)
		end
		return nil
	end
	local a, b = posts[1], posts[2]
	local mid = (a.Position + b.Position) * 0.5
	local along = (b.Position - a.Position) * Vector3.new(1, 0, 1)
	local spawn = plotFolder:FindFirstChild("PlayerSpawn")
	local outward: Vector3
	if spawn and spawn:IsA("BasePart") then
		outward = (spawn.Position - mid) * Vector3.new(1, 0, 1)
	else
		-- perpendicular to gate line
		outward = Vector3.new(-along.Z, 0, along.X)
	end
	if outward.Magnitude < 0.05 then
		outward = Vector3.new(0, 0, 1)
	end
	local y = math.min(a.Position.Y - a.Size.Y * 0.5, b.Position.Y - b.Size.Y * 0.5) + 3
	local origin = Vector3.new(mid.X, y, mid.Z)
	return CFrame.lookAt(origin, origin + outward.Unit)
end

local function findCollectorPos(plotId: number): Vector3?
	for _, inst in ipairs(CollectionService:GetTagged(TAG_COLLECTOR)) do
		if inst:IsA("BasePart") and inst:GetAttribute("PlotId") == plotId then
			return inst.Position
		end
	end
	local plotFolder = findPlotFolder(plotId)
	if plotFolder then
		local mc = plotFolder:FindFirstChild("MoneyCollector")
		if mc then
			local body = mc:FindFirstChild("CollectorBody")
			if body and body:IsA("BasePart") then
				return body.Position
			end
		end
	end
	return nil
end

local function clearDefense(plotId: number)
	local def = defenses[plotId]
	if not def then
		return
	end
	for _, g in ipairs(def.Guards) do
		g.Alive = false
		if g.Model and g.Model.Parent then
			g.Model:Destroy()
		end
	end
	for _, t in ipairs(def.Turrets) do
		if t.Model and t.Model.Parent then
			t.Model:Destroy()
		end
	end
	if def.Folder and def.Folder.Parent then
		def.Folder:Destroy()
	end
	defenses[plotId] = nil
end

local function ensureDefenseFolder(plotFolder: Folder): Folder
	local existing = plotFolder:FindFirstChild(DEFENSE_FOLDER)
	if existing and existing:IsA("Folder") then
		existing:ClearAllChildren()
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = DEFENSE_FOLDER
	f.Parent = plotFolder
	return f
end

local function faceYaw(root: BasePart, lookAt: Vector3)
	local flat = Vector3.new(lookAt.X, root.Position.Y, lookAt.Z)
	if (flat - root.Position).Magnitude < 0.05 then
		return
	end
	local look = CFrame.lookAt(root.Position, flat)
	local gyro = root:FindFirstChild("NPCFaceGyro")
	if gyro and gyro:IsA("BodyGyro") then
		gyro.CFrame = look
	end
end

local function spawnGuardModel(ownerUserId: number, slot: number, at: CFrame, stats: any, parent: Folder): GuardUnit?
	local model = Instance.new("Model")
	model.Name = "GateGuard_" .. tostring(slot)
	model:SetAttribute("GateGuard", true)
	model:SetAttribute("OwnerUserId", ownerUserId)
	model:SetAttribute("FriendlyGate", true)
	model:SetAttribute("PlotDefense", true)

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = at
	root.Anchored = false
	root.CanCollide = true
	root.Color = Color3.fromRGB(70, 75, 55)
	root.Material = Enum.Material.Fabric
	root.Parent = model

	local function weldPart(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = at * offset
		p.Anchored = false
		p.CanCollide = false
		p.Massless = true
		p.Color = color
		p.Material = material
		if shape then
			p.Shape = shape
		end
		p.Parent = model
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = p
		w.Parent = root
		return p
	end

	local olive = Color3.fromRGB(70, 75, 55)
	local skin = Color3.fromRGB(190, 160, 120)
	local head = weldPart("Head", Vector3.new(1.05, 1.05, 1.05), CFrame.new(0, 1.55, 0), skin, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Face = Enum.NormalId.Front
	face.Texture = "rbxasset://textures/face.png"
	face.Parent = head
	weldPart("Helmet", Vector3.new(1.2, 0.5, 1.2), CFrame.new(0, 1.95, 0), Color3.fromRGB(45, 50, 40), Enum.Material.Metal, nil)
	weldPart("Vest", Vector3.new(2.1, 1.2, 1.15), CFrame.new(0, 0.15, 0), olive, Enum.Material.Fabric, nil)
	weldPart("LegL", Vector3.new(1, 2, 1), CFrame.new(-0.5, -2, 0), olive, Enum.Material.Fabric, nil)
	weldPart("LegR", Vector3.new(1, 2, 1), CFrame.new(0.5, -2, 0), olive, Enum.Material.Fabric, nil)
	weldPart("ArmL", Vector3.new(1, 2, 1), CFrame.new(-1.5, 0, 0), olive, Enum.Material.Fabric, nil)
	weldPart("ArmR", Vector3.new(1, 2, 1), CFrame.new(1.5, 0, 0), olive, Enum.Material.Fabric, nil)
	weldPart("Rifle", Vector3.new(0.26, 0.26, 2.4), CFrame.new(1.15, 0.15, -0.85), Color3.fromRGB(28, 28, 30), Enum.Material.Metal, nil)

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = stats.GuardHealth
	humanoid.Health = stats.GuardHealth
	humanoid.WalkSpeed = stats.GuardWalkSpeed
	humanoid.AutoRotate = true
	humanoid.HipHeight = 2
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.NameOcclusion = Enum.NameOcclusion.OccludeAll
	humanoid.Parent = model

	local bb = Instance.new("BillboardGui")
	bb.Name = "GateGuardLabel"
	bb.Size = UDim2.fromOffset(110, 22)
	bb.StudsOffset = Vector3.new(0, 3.4, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 70
	bb.Parent = root
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundColor3 = Color3.fromRGB(25, 30, 22)
	lbl.BackgroundTransparency = 0.3
	lbl.Text = "GATE GUARD"
	lbl.TextColor3 = Color3.fromRGB(190, 220, 150)
	lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBold
	lbl.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = lbl

	model.PrimaryPart = root
	-- Do NOT tag WE_NPC — CombatNPC would aggro owner
	model.Parent = parent
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	if VisualAssetService and VisualAssetService.TryAttachCharacterVisual then
		pcall(function()
			VisualAssetService.TryAttachCharacterVisual(model, GateDefenseConfig.VisualKind or "GateGuard")
		end)
	end

	local gyro = Instance.new("BodyGyro")
	gyro.Name = "NPCFaceGyro"
	gyro.MaxTorque = Vector3.new(0, 4e5, 0)
	gyro.P = 5000
	gyro.D = 500
	gyro.CFrame = at
	gyro.Parent = root

	local unit: GuardUnit = {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Slot = slot,
		LastFireAt = 0,
		WaypointIndex = 1,
		IdleUntil = 0,
		Alive = true,
		PostCf = at,
	}

	humanoid.Died:Connect(function()
		if not unit.Alive then
			return
		end
		unit.Alive = false
		local plotId = model:GetAttribute("PlotId")
		task.delay(0.35, function()
			if model.Parent then
				model:Destroy()
			end
		end)
		task.delay(GateDefenseConfig.GuardRespawnSeconds or 12, function()
			if typeof(plotId) == "number" then
				local def = defenses[plotId :: number]
				if def and def.OwnerUserId == ownerUserId then
					GateDefenseService.SyncPlot(plotId :: number)
				end
			end
		end)
	end)

	model:SetAttribute("PlotId", parent:GetAttribute("PlotId"))
	return unit
end

local function partKitAutoGun(at: CFrame, parent: Instance): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "GateAutoGun_Fallback"
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(2, 0.4, 2)
	base.CFrame = at
	base.Anchored = true
	base.CanCollide = false
	base.Color = Color3.fromRGB(64, 69, 71)
	base.Material = Enum.Material.Metal
	base.Parent = model
	local yaw = Instance.new("Part")
	yaw.Name = "Yaw"
	yaw.Size = Vector3.new(1.2, 0.6, 1.2)
	yaw.CFrame = at * CFrame.new(0, 0.5, 0)
	yaw.Anchored = true
	yaw.CanCollide = false
	yaw.Color = Color3.fromRGB(55, 58, 60)
	yaw.Material = Enum.Material.Metal
	yaw.Parent = model
	local barrel = Instance.new("Part")
	barrel.Name = "Barrel"
	barrel.Shape = Enum.PartType.Cylinder
	barrel.Size = Vector3.new(3, 0.3, 0.3)
	barrel.CFrame = yaw.CFrame * CFrame.new(0, 0.15, -1.4) * CFrame.Angles(0, 0, math.rad(90))
	barrel.Anchored = true
	barrel.CanCollide = false
	barrel.Color = Color3.fromRGB(40, 42, 44)
	barrel.Material = Enum.Material.Metal
	barrel.Parent = model
	model.PrimaryPart = yaw
	model.Parent = parent
	return model, yaw
end

local function spawnAutoGun(slot: number, at: CFrame, parent: Folder): TurretUnit?
	local gd = (VisualAssetConfig :: any).GateDefense
	local assetId = 4923345827
	if gd and gd.AutoGun and typeof(gd.AutoGun.ModelAssetId) == "number" then
		assetId = gd.AutoGun.ModelAssetId
	end
	local template = loadCatalogModel(assetId)
	local model: Model
	local yawPart: BasePart
	if template then
		model = template:Clone()
		stripScripts(model)
		scaleModelLongAxis(model, GateDefenseConfig.AutoGunLongAxisStuds or 5.5)
		model.Name = "GateAutoGun_" .. tostring(slot)
		if not model.PrimaryPart then
			local pp = model:FindFirstChildWhichIsA("BasePart", true)
			if pp and pp:IsA("BasePart") then
				model.PrimaryPart = pp
			end
		end
		model:PivotTo(at)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
			end
		end
		model.Parent = parent
		yawPart = model.PrimaryPart :: BasePart
		local named = model:FindFirstChild("Barrel", true) or model:FindFirstChild("Yaw", true)
		if named and named:IsA("BasePart") then
			yawPart = named
		end
	else
		model, yawPart = partKitAutoGun(at, parent)
		model.Name = "GateAutoGun_" .. tostring(slot)
	end

	model:SetAttribute("GateAutoGun", true)
	model:SetAttribute("FriendlyGate", true)

	-- Sandbag nest dress under gun
	if gd and gd.SandbagNest and typeof(gd.SandbagNest.ModelAssetId) == "number" then
		local nestT = loadCatalogModel(gd.SandbagNest.ModelAssetId)
		if nestT then
			local nest = nestT:Clone()
			stripScripts(nest)
			scaleModelLongAxis(nest, GateDefenseConfig.SandbagNestDiameterStuds or 8)
			nest.Name = "SandbagNest_" .. tostring(slot)
			nest:PivotTo(at * CFrame.new(0, -0.2, 0))
			for _, d in ipairs(nest:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
				end
			end
			nest.Parent = parent
		end
	end

	-- Scatter sandbags
	local bagId = if gd and gd.Sandbags then gd.Sandbags.ModelAssetId else 3525056989
	if typeof(bagId) == "number" and bagId > 0 then
		local bagT = loadCatalogModel(bagId)
		if bagT then
			for i = 1, 3 do
				local bag = bagT:Clone()
				stripScripts(bag)
				scaleModelLongAxis(bag, 2.2)
				local ox = (i - 2) * 1.4
				bag:PivotTo(at * CFrame.new(ox, -0.1, 1.6 + (i % 2) * 0.4))
				for _, d in ipairs(bag:GetDescendants()) do
					if d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = false
					end
				end
				bag.Name = "Sandbag_" .. tostring(slot) .. "_" .. tostring(i)
				bag.Parent = parent
			end
		end
	end

	return {
		Model = model,
		YawPart = yawPart,
		Slot = slot,
		LastFireAt = 0,
	}
end

local function sameNation(a: number, b: number): boolean
	if not NationColorService or not NationColorService.GetColorId then
		return false
	end
	local ca = NationColorService.GetColorId(a)
	local cb = NationColorService.GetColorId(b)
	if typeof(ca) ~= "string" or typeof(cb) ~= "string" then
		return false
	end
	return ca == cb
end

local function isEnemyPlayer(ownerUserId: number, player: Player): boolean
	if player.UserId == ownerUserId then
		return false
	end
	if sameNation(ownerUserId, player.UserId) then
		return false
	end
	return true
end

local function hasLos(fromPos: Vector3, toPos: Vector3, ignore: { Instance }): boolean
	if not GateDefenseConfig.RequireLineOfSight then
		return true
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local dir = toPos - fromPos
	local maxD = GateDefenseConfig.LosMaxDistance or 110
	if dir.Magnitude > maxD then
		dir = dir.Unit * maxD
	end
	local hit = Workspace:Raycast(fromPos + Vector3.new(0, 1.5, 0), dir, params)
	if not hit then
		return true
	end
	-- Hit character of target is OK — we ray toward root; if we hit something else first, blocked
	local inst = hit.Instance
	for _, ig in ipairs(ignore) do
		if inst:IsDescendantOf(ig) or inst == ig then
			return true
		end
	end
	-- Allow hitting the target character: ignore list should include target model when calling
	return false
end

local function rateLimitVictim(userId: number): boolean
	local t = nowClock()
	local last = victimHitAt[userId] or 0
	local cd = GateDefenseConfig.DamageCooldownGlobal or 0.08
	if t - last < cd then
		return false
	end
	victimHitAt[userId] = t
	return true
end

local function nearestEnemy(def: PlotDefense, fromPos: Vector3, aggro: number, shootRange: number): (Player?, Humanoid?, BasePart?, number)
	local bestPlr: Player? = nil
	local bestHum: Humanoid? = nil
	local bestRoot: BasePart? = nil
	local bestDist = aggro
	local collectorPos = def.CollectorPos
	local protectR = GateDefenseConfig.ProtectCollectorRadius or 42

	for _, player in ipairs(Players:GetPlayers()) do
		if isEnemyPlayer(def.OwnerUserId, player) then
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if hum and root and root:IsA("BasePart") and hum.Health > 0 then
				local dGate = (root.Position - fromPos).Magnitude
				local nearATM = false
				if collectorPos then
					nearATM = (root.Position - collectorPos).Magnitude <= protectR
				end
				local inAggro = dGate <= aggro or nearATM
				if inAggro and dGate < bestDist + (if nearATM then 30 else 0) then
					-- Prefer closest to shooter; ATM proximity still qualifies
					local score = if nearATM then math.min(dGate, protectR) else dGate
					if score < bestDist or (nearATM and bestPlr == nil) then
						bestDist = dGate
						bestPlr = player
						bestHum = hum
						bestRoot = root
					end
				end
			end
		end
	end
	return bestPlr, bestHum, bestRoot, bestDist
end

local function dealDamage(player: Player, hum: Humanoid, amount: number, sourceModel: Model)
	if amount <= 0 or hum.Health <= 0 then
		return
	end
	if not rateLimitVictim(player.UserId) then
		return
	end
	-- Never friendly-fire owner's soldiers / squad
	local char = player.Character
	if char and (char:GetAttribute("FriendlySquad") or char:GetAttribute("OwnerUserId") == sourceModel:GetAttribute("OwnerUserId")) then
		return
	end
	hum:TakeDamage(amount)
end

function GateDefenseService.SyncPlot(plotId: number)
	if not GateDefenseConfig.Enabled then
		clearDefense(plotId)
		return
	end
	local ownerUserId = if BaseService and BaseService.GetOwnerUserId then BaseService.GetOwnerUserId(plotId) else nil
	if not ownerUserId then
		clearDefense(plotId)
		return
	end
	local owner = Players:GetPlayerByUserId(ownerUserId)
	local wallsLevel = 0
	if owner and DataService then
		local profile = DataService.GetProfile(owner)
		if profile and profile.BaseUpgrades then
			wallsLevel = tonumber(profile.BaseUpgrades.DefensiveWalls) or 0
		end
	end
	local stats = GateDefenseConfig.GetLevelStats(wallsLevel)
	if not stats then
		clearDefense(plotId)
		return
	end

	local plotFolder = findPlotFolder(plotId)
	if not plotFolder then
		return
	end
	local posts = gatherGatePosts(plotFolder)
	local gateCf = computeGateCFrame(plotFolder, posts)
	if not gateCf then
		-- Walls folder may lag a frame after perimeter wall sync
		return
	end

	clearDefense(plotId)
	local folder = ensureDefenseFolder(plotFolder)
	folder:SetAttribute("PlotId", plotId)
	folder:SetAttribute("OwnerUserId", ownerUserId)
	folder:SetAttribute("WallsLevel", wallsLevel)

	local flankX = GateDefenseConfig.GuardFlankX or 6
	local fwdZ = GateDefenseConfig.GuardForwardZ or 2
	local guards: { GuardUnit } = {}
	for slot, sx in ipairs({ -flankX, flankX }) do
		local at = gateCf * CFrame.new(sx, 0, fwdZ)
		local g = spawnGuardModel(ownerUserId, slot, at, stats, folder)
		if g then
			g.Model:SetAttribute("PlotId", plotId)
			g.Model:SetAttribute("OwnerUserId", ownerUserId)
			table.insert(guards, g)
		end
	end

	local turrets: { TurretUnit } = {}
	local useTurrets = stats.UseTurrets == true and wallsLevel >= (GateDefenseConfig.AutoGunMinWallsLevel or 4)
	if useTurrets then
		local gx = GateDefenseConfig.AutoGunFlankX or 7
		local gz = GateDefenseConfig.AutoGunForwardZ or 1
		local yawDeg = GateDefenseConfig.AutoGunYawDeg or 15
		for slot, sx in ipairs({ -gx, gx }) do
			local yaw = if sx < 0 then yawDeg else -yawDeg
			local at = gateCf * CFrame.new(sx, 0, gz) * CFrame.Angles(0, math.rad(yaw), 0)
			local t = spawnAutoGun(slot, at, folder)
			if t then
				table.insert(turrets, t)
			end
		end
	end

	defenses[plotId] = {
		PlotId = plotId,
		OwnerUserId = ownerUserId,
		WallsLevel = wallsLevel,
		Folder = folder,
		Guards = guards,
		Turrets = turrets,
		GateCf = gateCf,
		CollectorPos = findCollectorPos(plotId),
	}

	if RunService:IsStudio() then
		print(string.format(
			"[GateDefense] plot=%d walls=%d guards=%d turrets=%d tier=%s",
			plotId,
			wallsLevel,
			#guards,
			#turrets,
			tostring(stats.DesignTier)
		))
	end
end

function GateDefenseService.ClearPlot(plotId: number)
	clearDefense(plotId)
end

local function thinkGuard(def: PlotDefense, g: GuardUnit, stats: any, tnow: number)
	if not g.Alive or g.Humanoid.Health <= 0 or not g.Root.Parent then
		return
	end
	local aggro = stats.AggroRange or GateDefenseConfig.DefaultAggroRange or 95
	local range = stats.ShootRange or 70
	local plr, hum, troot, dist = nearestEnemy(def, g.Root.Position, aggro, range)
	if plr and hum and troot then
		faceYaw(g.Root, troot.Position)
		local ignore = { g.Model, def.Folder, plr.Character :: Instance }
		if dist > range * 0.85 then
			g.Humanoid:MoveTo(troot.Position)
		else
			g.Humanoid:MoveTo(g.Root.Position)
			local interval = 1 / math.max(stats.GuardFireRate or 1.4, 0.1)
			if tnow - g.LastFireAt >= interval and dist <= range then
				if hasLos(g.Root.Position, troot.Position, ignore) then
					g.LastFireAt = tnow
					dealDamage(plr, hum, stats.GuardDamage or 14, g.Model)
				end
			end
		end
		return
	end

	-- Patrol ±PatrolHalfSpanStuds along gate line
	local half = GateDefenseConfig.PatrolHalfSpanStuds or 6
	local idle = GateDefenseConfig.PatrolIdleSeconds or 1.4
	local waypoints = {
		(def.GateCf * CFrame.new(-half, 0, GateDefenseConfig.GuardForwardZ or 2)).Position,
		(def.GateCf * CFrame.new(half, 0, GateDefenseConfig.GuardForwardZ or 2)).Position,
	}
	-- Prefer near own post
	if g.Slot == 1 then
		waypoints = {
			(def.GateCf * CFrame.new(-(GateDefenseConfig.GuardFlankX or 6), 0, GateDefenseConfig.GuardForwardZ or 2)).Position,
			(def.GateCf * CFrame.new(-(GateDefenseConfig.GuardFlankX or 6) + half * 0.5, 0, GateDefenseConfig.GuardForwardZ or 2)).Position,
		}
	else
		waypoints = {
			(def.GateCf * CFrame.new((GateDefenseConfig.GuardFlankX or 6), 0, GateDefenseConfig.GuardForwardZ or 2)).Position,
			(def.GateCf * CFrame.new((GateDefenseConfig.GuardFlankX or 6) - half * 0.5, 0, GateDefenseConfig.GuardForwardZ or 2)).Position,
		}
	end
	if tnow < g.IdleUntil then
		g.Humanoid:MoveTo(g.Root.Position)
		return
	end
	local idx = ((g.WaypointIndex - 1) % #waypoints) + 1
	local dest = waypoints[idx]
	local d = (g.Root.Position - dest).Magnitude
	if d < (GateDefenseConfig.PatrolReachStuds or 2) then
		g.WaypointIndex = idx + 1
		g.IdleUntil = tnow + idle
		g.Humanoid:MoveTo(g.Root.Position)
	else
		g.Humanoid:MoveTo(dest)
		faceYaw(g.Root, dest)
	end
end

local function thinkTurret(def: PlotDefense, t: TurretUnit, stats: any, tnow: number)
	if not t.Model.Parent or not t.YawPart.Parent then
		return
	end
	local aggro = stats.TurretRange or 100
	local fromPos = t.YawPart.Position
	local plr, hum, troot, dist = nearestEnemy(def, fromPos, aggro, aggro)
	if not (plr and hum and troot) then
		return
	end
	local flat = Vector3.new(troot.Position.X, t.YawPart.Position.Y, troot.Position.Z)
	if (flat - t.YawPart.Position).Magnitude > 0.05 then
		local look = CFrame.lookAt(t.YawPart.Position, flat)
		-- Rotate whole model toward target when PrimaryPart is yaw
		if t.Model.PrimaryPart then
			local offset = t.Model.PrimaryPart.CFrame:ToObjectSpace(t.YawPart.CFrame)
			t.Model:PivotTo(look * offset:Inverse())
		else
			t.YawPart.CFrame = look
		end
	end
	local interval = 1 / math.max(stats.TurretFireRate or 6, 0.1)
	if tnow - t.LastFireAt >= interval and dist <= aggro then
		local ignore = { t.Model, def.Folder, plr.Character :: Instance }
		if hasLos(fromPos, troot.Position, ignore) then
			t.LastFireAt = tnow
			dealDamage(plr, hum, stats.TurretDamage or 22, t.Model)
		end
	end
end

function GateDefenseService.Init(deps: { [string]: any })
	BaseService = deps.BaseService
	DataService = deps.DataService
	VisualAssetService = deps.VisualAssetService
	NationColorService = deps.NationColorService

	if not GateDefenseConfig.Enabled then
		return
	end

	-- Sync on walls upgrade
	if BaseService and BaseService.GetUpgradeChangedEvent then
		BaseService.GetUpgradeChangedEvent().Event:Connect(function(_userId: number, plotId: number?, structureId: string?, _level: number?)
			if structureId == "DefensiveWalls" and typeof(plotId) == "number" then
				task.defer(function()
					task.wait(0.15) -- allow perimeter wall sync to rebuild GatePosts
					GateDefenseService.SyncPlot(plotId :: number)
				end)
			end
		end)
	end

	if DataService and DataService.OnProfileLoaded then
		DataService.OnProfileLoaded(function(player: Player, profile: any)
			task.defer(function()
				task.wait(1.2)
				if not player.Parent then
					return
				end
				local plotId = profile and profile.BasePlotId
				if typeof(plotId) == "number" then
					GateDefenseService.SyncPlot(plotId)
				end
			end)
			task.delay(3.5, function()
				if player.Parent and profile and typeof(profile.BasePlotId) == "number" then
					GateDefenseService.SyncPlot(profile.BasePlotId)
				end
			end)
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		if BaseService and BaseService.GetOwnerUserId then
			-- Clear any plot this owner held
			for plotId, def in pairs(defenses) do
				if def.OwnerUserId == player.UserId then
					clearDefense(plotId)
				end
			end
		end
		victimHitAt[player.UserId] = nil
	end)

	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < 0.2 then
			return
		end
		accum = 0
		local tnow = nowClock()
		for plotId, def in pairs(defenses) do
			local stats = GateDefenseConfig.GetLevelStats(def.WallsLevel)
			if stats then
				if not def.CollectorPos then
					def.CollectorPos = findCollectorPos(plotId)
				end
				for _, g in ipairs(def.Guards) do
					thinkGuard(def, g, stats, tnow)
				end
				for _, tur in ipairs(def.Turrets) do
					thinkTurret(def, tur, stats, tnow)
				end
			end
		end
	end)

	print("[WAR EMPIRE] GateDefenseService ready (walls≥1 → 2 GateGuards; walls≥4 → AutoGun nests)")
end

return GateDefenseService
