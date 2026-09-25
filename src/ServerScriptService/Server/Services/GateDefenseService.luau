--!strict
--[[
	Gate door defense — 2 GateGuards patrol + shoot enemies; L4+ AutoGun nests.
	Reads GatePost parts from WE_PerimeterWalls (does NOT edit StructureKitBuilder).
	Design Bot GATE_DEFENSE_WIRE: Guard 16134469614, AutoGun 4923345827, sandbag dress.
	Aggro covers MoneyCollector ATM approach (raid deterrent). No exotic persist.

	v69 (RaidConfig.Defense, spec §1.9): allies = owner + same clan (IsAlly); guards / AutoGuns posted INSIDE the
	gate and engaging any non-ally inside the walls (raider at the ATM first); guards are killable (weapon hits
	route through the GateBarrier hook) and respawn one at a time; the gate opens for the owner and clan-mates;
	Research TurretDamage multiplies guard + AutoGun damage; a missile strike (MissileStrikeService →
	SetDefensesDown) takes everything down until profile.Raid.DefensesDownUntil (os.time — the rest of this file
	uses os.clock).

	v71 (HUD v70 spec §4.2 / §5): no guard name cards and no auto-gun name cards (the client draws an HP bar after
	damage); the AutoGun marker ring and muzzle are painted, not neon; the gate shows ONE thin stud-scaled HP bar
	centred over the opening, only while damaged, breached, struck or raided; the owner gets one "BASE UNDER
	ATTACK!" Warn per plot per minute instead of a toast on every hit.
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
local RaidConfig = require(Shared.Configs.RaidConfig)
local HudConfig = require(Shared.Configs.HudConfig)
local WorldLabelConfig = require(Shared.Configs.WorldLabelConfig)

local GateDefenseService = {}

local BaseService: any = nil
local DataService: any = nil
local VisualAssetService: any = nil
local ClanService: any = nil
local ResearchService: any = nil
local EconomyService: any = nil
local NotificationService: any = nil

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
	Offline: boolean, -- v69: missile strike (defenses down)
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
	CollectorModel: Instance?, -- v69: ignored by line of sight (raider hiding behind the ATM body)
	GateHealth: number,
	GateMaxHealth: number,
	GateBreached: boolean,
	GateBarriers: { BasePart },
	GateRebuildAt: number?,
	LastRegenAt: number,
	-- v69
	DownUntil: number?, -- os.time: missile strike took the defenses down until then
	LastDownLabelAt: number,
	GateOpen: boolean, -- friendly gate: leaves open for the owner / clan-mates
	GateAllyAt: number, -- os.clock an ally was last at the gate
	PadCenter: Vector3?, -- plot pad (WE_BasePlot) centre, for "inside the walls"
	PadHalf: number,
}

local defenses: { [number]: PlotDefense } = {}
-- v69: one sync per plot at a time. Guard/AutoGun spawns can yield (catalog LoadAsset); two overlapping syncs
-- (walls purchase + plot-ready) used to both spawn into the same folder → duplicate / orphaned guards.
local syncBusy: { [number]: boolean } = {}
local syncAgain: { [number]: boolean } = {}
local victimHitAt: { [number]: number } = {}
local graceFrom: { [number]: number } = {} -- UserId → os.clock of the last character spawn / save load (spawn grace)
-- F6 novice shield: CombatService.IsNoviceShielded, handed in by CombatService.Init through SetShieldCheck (this
-- service takes no CombatService dep and never requires it). nil = nobody is shielded.
local shieldCheck: ((Player) -> boolean)? = nil
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

-- v69: the plot's own ATM (MoneyCollector folder, or the tagged part) — guard / AutoGun line of sight ignores it,
-- otherwise a raider standing on the far side of the 6×8×4 ATM body is invisible to every post.
local function findCollectorModel(plotId: number): Instance?
	for _, inst in ipairs(CollectionService:GetTagged(TAG_COLLECTOR)) do
		if inst:IsA("BasePart") and inst:GetAttribute("PlotId") == plotId then
			local parent = inst.Parent
			if parent and parent.Name == "MoneyCollector" and (parent:IsA("Folder") or parent:IsA("Model")) then
				return parent
			end
			return inst
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

-- v69 F4: set below (needs spawnGuardModel); a dead guard respawns alone, never through SyncPlot
local respawnGuard: (plotId: number, slot: number, ownerUserId: number, def: PlotDefense, dead: GuardUnit) -> ()

local function spawnGuardModel(ownerUserId: number, slot: number, at: CFrame, stats: any, parent: Folder, plotId: number): GuardUnit
	local model = Instance.new("Model")
	-- streaming2 S4 (F10): a gate guard (root, welded kit, Humanoid) reaches a client whole or not at all. Set before
	-- the model is parented (it is filled first, parented below). No effect with streaming off.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
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
	-- v33: clear rifle prop (receiver + barrel + mag + stock) so guards read as armed
	weldPart("Rifle", Vector3.new(0.32, 0.28, 2.6), CFrame.new(1.2, 0.2, -0.9), Color3.fromRGB(28, 28, 30), Enum.Material.Metal, nil)
	weldPart("RifleStock", Vector3.new(0.28, 0.35, 0.7), CFrame.new(1.2, 0.15, 0.55), Color3.fromRGB(55, 45, 30), Enum.Material.Wood, nil)
	weldPart("RifleMag", Vector3.new(0.22, 0.55, 0.35), CFrame.new(1.2, -0.15, -0.35), Color3.fromRGB(40, 40, 42), Enum.Material.Metal, nil)
	weldPart("RifleBarrel", Vector3.new(0.16, 0.16, 0.9), CFrame.new(1.2, 0.22, -2.15), Color3.fromRGB(50, 50, 55), Enum.Material.Metal, nil)
	weldPart("RifleSight", Vector3.new(0.12, 0.22, 0.35), CFrame.new(1.2, 0.45, -0.5), Color3.fromRGB(35, 35, 38), Enum.Material.Metal, nil)

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

	-- v71: no "GATE GUARD" name card (spec §5: it drew through walls at 90 studs); the client shows an HP bar
	-- after damage.

	-- v69 F3: guards are killable. CombatService forwards a raycast hit on any GateBarrier-attributed part to
	-- ApplyDamage, which routes GateGuardPart hits to this humanoid. No WE_GateBarrier tag (that is the gate).
	local function markHittable(d: Instance)
		if d:IsA("BasePart") then
			d:SetAttribute("GateBarrier", true)
			d:SetAttribute("GateGuardPart", true)
			d:SetAttribute("PlotId", plotId)
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		markHittable(d)
	end
	model.DescendantAdded:Connect(markHittable) -- catalog character visual parts added below

	model.PrimaryPart = root
	-- Do NOT tag WE_NPC — CombatNPC would aggro owner
	model:SetAttribute("PlotId", plotId)
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
		task.delay(0.35, function()
			if model.Parent then
				model:Destroy()
			end
		end)
		-- v69 F4: respawn only this slot (a whole-plot SyncPlot used to reset a breached gate to full HP and
		-- respawn the other guard too)
		local def = defenses[plotId]
		if def and def.OwnerUserId == ownerUserId then
			task.delay(GateDefenseConfig.GuardRespawnSeconds or 12, respawnGuard, plotId, slot, ownerUserId, def, unit)
		end
	end)

	return unit
end

local function partKitAutoGun(at: CFrame, parent: Instance): (Model, BasePart)
	-- v35: obvious HMG tripod + long barrel + muzzle tip (readable at gate flanks)
	local model = Instance.new("Model")
	-- streaming2 S4 (F10): the AutoGun reaches a client whole or not at all; set before it is parented (below)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.Name = "GateAutoGun_Fallback"
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(2.4, 0.45, 2.4)
	base.CFrame = at
	base.Anchored = true
	base.CanCollide = false
	base.Color = Color3.fromRGB(64, 69, 71)
	base.Material = Enum.Material.Metal
	base.Parent = model
	-- Tripod legs
	for i, ang in ipairs({ 0, 120, 240 }) do
		local leg = Instance.new("Part")
		leg.Name = "TripodLeg" .. i
		leg.Size = Vector3.new(0.25, 2.2, 0.25)
		leg.CFrame = at * CFrame.Angles(0, math.rad(ang), 0) * CFrame.new(0.9, 0.9, 0) * CFrame.Angles(0, 0, math.rad(25))
		leg.Anchored = true
		leg.CanCollide = false
		leg.Color = Color3.fromRGB(50, 52, 48)
		leg.Material = Enum.Material.Metal
		leg.Parent = model
	end
	local yaw = Instance.new("Part")
	yaw.Name = "Yaw"
	yaw.Size = Vector3.new(1.4, 0.7, 1.4)
	yaw.CFrame = at * CFrame.new(0, 1.35, 0)
	yaw.Anchored = true
	yaw.CanCollide = false
	yaw.Color = Color3.fromRGB(55, 58, 60)
	yaw.Material = Enum.Material.Metal
	yaw.Parent = model
	-- Gun shield plate
	local shield = Instance.new("Part")
	shield.Name = "Shield"
	shield.Size = Vector3.new(2.2, 1.4, 0.18)
	shield.CFrame = yaw.CFrame * CFrame.new(0, 0.5, -0.7)
	shield.Anchored = true
	shield.CanCollide = false
	shield.Color = Color3.fromRGB(70, 75, 68)
	shield.Material = Enum.Material.Metal
	shield.Parent = model
	local barrel = Instance.new("Part")
	barrel.Name = "Barrel"
	barrel.Shape = Enum.PartType.Cylinder
	barrel.Size = Vector3.new(4.2, 0.35, 0.35)
	barrel.CFrame = yaw.CFrame * CFrame.new(0, 0.35, -2.2) * CFrame.Angles(0, 0, math.rad(90))
	barrel.Anchored = true
	barrel.CanCollide = false
	barrel.Color = Color3.fromRGB(35, 37, 40)
	barrel.Material = Enum.Material.Metal
	barrel.Parent = model
	local muzzle = Instance.new("Part")
	muzzle.Name = "MuzzleTip"
	muzzle.Shape = Enum.PartType.Ball
	muzzle.Size = Vector3.new(0.55, 0.55, 0.55)
	muzzle.CFrame = yaw.CFrame * CFrame.new(0, 0.35, -4.3)
	muzzle.Anchored = true
	muzzle.CanCollide = false
	muzzle.Color = Color3.fromRGB(255, 160, 40)
	muzzle.Material = Enum.Material.SmoothPlastic -- v71: painted, not neon (not a light source)
	muzzle.Parent = model
	model.PrimaryPart = yaw
	model.Parent = parent
	return model, yaw
end

local function attachTurretVisualMarker(model: Model, at: CFrame)
	-- Painted ring under the nest so upgraded AutoGuns read even before the catalog mesh loads.
	-- v71: SmoothPlastic, no floating name card over the gun (spec §5 neon + label clean-up).
	if model:FindFirstChild("WE_TurretMarker") then
		return
	end
	local ring = Instance.new("Part")
	ring.Name = "WE_TurretMarker"
	ring.Size = Vector3.new(3.2, 0.18, 3.2)
	ring.CFrame = at * CFrame.new(0, 0.15, 0)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Color = Color3.fromRGB(200, 80, 40)
	ring.Material = Enum.Material.SmoothPlastic
	ring.Parent = model
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
		-- streaming2 S4 (F10): the catalog AutoGun is Atomic too, set before it is parented. No effect with streaming off.
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
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
	attachTurretVisualMarker(model, at)

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
		Offline = false,
	}
end

--[[ v69 F1: allies = the owner, or a player in the owner's clan (same non-empty ClanService clan id; the owner
	must be online). Nation colour no longer matters (it is userId % 8, never chosen: 1 in 8 random players used
	to be ignored by your guards and unable to damage your gate). Used by raids and strikes too. ]]
function GateDefenseService.IsAlly(ownerUserId: number, player: Player): boolean
	if player.UserId == ownerUserId then
		return true
	end
	if not (ClanService and ClanService.GetClanId) then
		return false
	end
	local owner = Players:GetPlayerByUserId(ownerUserId)
	if not owner then
		return false
	end
	local okA, a = pcall(ClanService.GetClanId, owner)
	local okB, b = pcall(ClanService.GetClanId, player)
	return okA and okB and typeof(a) == "string" and a ~= "" and a == b
end

local function isEnemyPlayer(ownerUserId: number, player: Player): boolean
	return not GateDefenseService.IsAlly(ownerUserId, player)
end

-- v69 F6: Research "TurretDamage" of the owner multiplies guard + AutoGun damage (read at fire time)
local function researchMult(ownerUserId: number): number
	if not (ResearchService and ResearchService.GetBonus) then
		return 1
	end
	local owner = Players:GetPlayerByUserId(ownerUserId)
	if not owner then
		return 1
	end
	local ok, v = pcall(ResearchService.GetBonus, owner, RaidConfig.Defense.ResearchStat)
	if not ok or typeof(v) ~= "number" or v ~= v then
		return 1
	end
	return math.clamp(v, 1, RaidConfig.Defense.MaxResearchMult)
end

local function isDown(def: PlotDefense): boolean
	return def.DownUntil ~= nil and os.time() < (def.DownUntil :: number)
end

local function insidePlot(def: PlotDefense, pos: Vector3): boolean
	local c = def.PadCenter
	if not c then
		return false
	end
	return math.abs(pos.X - c.X) <= def.PadHalf and math.abs(pos.Z - c.Z) <= def.PadHalf
end

-- Guards chase only to points inside the plot (never out through the gate)
local function clampInsidePlot(def: PlotDefense, pos: Vector3): Vector3
	local c = def.PadCenter
	if not c then
		return pos
	end
	local h = math.max(0, def.PadHalf - 4)
	return Vector3.new(math.clamp(pos.X, c.X - h, c.X + h), pos.Y, math.clamp(pos.Z, c.Z - h, c.Z + h))
end

local function hasLos(fromPos: Vector3, toPos: Vector3, ignore: { Instance }): boolean
	if not GateDefenseConfig.RequireLineOfSight then
		return true
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	-- v69: non-collidable decor (wire, trims, signs, lamp shades) no longer blocks the shot
	params.RespectCanCollide = RaidConfig.Defense.LosRespectCanCollide
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


-- v71: one "BASE UNDER ATTACK!" owner Warn per plot per BaseUnderAttackCooldown (spec §4.2)
local lastAttackAlertAt: { [number]: number } = {}
local barCheckAt: { [number]: number } = {}

local function alertBaseUnderAttack(plotId: number?, ownerUserId: number?, attacker: Player?)
	if not NotificationService or typeof(plotId) ~= "number" or typeof(ownerUserId) ~= "number" then
		return
	end
	local owner = Players:GetPlayerByUserId(ownerUserId)
	if not owner or owner == attacker then
		return
	end
	local now = os.clock()
	local cd = GateDefenseConfig.BaseUnderAttackCooldown or 60
	if now - (lastAttackAlertAt[plotId] or -math.huge) < cd then
		return
	end
	lastAttackAlertAt[plotId] = now
	NotificationService.Notify(owner, GateDefenseConfig.BaseUnderAttackToast or "BASE UNDER ATTACK!", "Warn", 4)
end

--[[ Spawn grace (GateDefenseConfig.SpawnGraceSeconds). Every PlayerSpawn pad sits at somebody's gate, and a new
	player stands there until the save loads and BaseService moves them to their own plot. So guards and AutoGuns
	ignore a player whose save has not loaded (DataService.GetProfile is nil; such a player cannot fire either), and
	for SpawnGraceSeconds after each character spawn and after the save loads (the move home is deferred). A
	respawned raider is moved to their own plot at once. The grace ends early for anyone holding an ATM raid or
	hitting a gate / guard (ApplyDamage), so a player left on a gate pad (no plot: server over MaxPlots) cannot
	use it to attack.
	F6 (owner's 11 features): a player under the novice shield (CombatService) counts as in grace too, so guards and
	AutoGuns neither target nor damage them and the owner gets no "BASE UNDER ATTACK" for them; holding an ATM raid
	still ends it here first. ]]
local function inSpawnGrace(player: Player): boolean
	if DataService and DataService.GetProfile and DataService.GetProfile(player) == nil then
		return true
	end
	if player:GetAttribute("WE_RaidingPlot") ~= nil then
		return false
	end
	local check = shieldCheck
	if check ~= nil then
		local ok, shielded = pcall(check, player)
		if ok and shielded == true then
			return true
		end
	end
	local from = graceFrom[player.UserId]
	return from ~= nil and nowClock() - from < (GateDefenseConfig.SpawnGraceSeconds or 4)
end

local function startSpawnGrace(player: Player)
	graceFrom[player.UserId] = nowClock()
end

-- F6: CombatService.Init hands in CombatService.IsNoviceShielded (nil clears it)
function GateDefenseService.SetShieldCheck(fn: ((Player) -> boolean)?)
	shieldCheck = fn
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

--[[ v69 F2: target choice. In aggro: within `aggro` of the shooter, near the ATM, or (EngageIntrudersInsideWalls)
	anywhere inside the plot. Priority: the player holding a raid on this plot's ATM (WE_RaidingPlot), then anyone
	near the ATM, then the nearest. `maxReach` (AutoGuns — they cannot chase) skips targets beyond it. ]]
local function nearestEnemy(def: PlotDefense, fromPos: Vector3, aggro: number, maxReach: number?): (Player?, Humanoid?, BasePart?, number)
	local bestPlr: Player? = nil
	local bestHum: Humanoid? = nil
	local bestRoot: BasePart? = nil
	local bestDist = aggro
	local bestTier = math.huge
	local collectorPos = def.CollectorPos
	local protectR = GateDefenseConfig.ProtectCollectorRadius or 42
	local engageInside = RaidConfig.Defense.EngageIntrudersInsideWalls

	for _, player in ipairs(Players:GetPlayers()) do
		if isEnemyPlayer(def.OwnerUserId, player) and not inSpawnGrace(player) then
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if hum and root and root:IsA("BasePart") and hum.Health > 0 then
				local pos = root.Position
				local d = (pos - fromPos).Magnitude
				local nearATM = collectorPos ~= nil and (pos - (collectorPos :: Vector3)).Magnitude <= protectR
				local inAggro = d <= aggro or nearATM or (engageInside and insidePlot(def, pos))
				if inAggro and (maxReach == nil or d <= (maxReach :: number)) then
					local tier = if player:GetAttribute("WE_RaidingPlot") == def.PlotId then 0 elseif nearATM then 1 else 2
					if tier < bestTier or (tier == bestTier and d < bestDist) then
						bestTier = tier
						bestDist = d
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

local function dealDamage(player: Player, hum: Humanoid, amount: number, sourceModel: Model, plotId: number?)
	if amount <= 0 or hum.Health <= 0 then
		return
	end
	if inSpawnGrace(player) then
		return
	end
	if not rateLimitVictim(player.UserId) then
		return
	end
	-- Never friendly-fire owner's soldiers / squad
	-- (v69: only when the shooter has an owner — AutoGun models had none, so nil == nil skipped every hit)
	local char = player.Character
	local srcOwner = sourceModel:GetAttribute("OwnerUserId")
	if char and (char:GetAttribute("FriendlySquad") or (srcOwner ~= nil and char:GetAttribute("OwnerUserId") == srcOwner)) then
		return
	end
	hum:TakeDamage(amount)
	-- the defenses are engaging an intruder: tell the owner once a minute (not on every hit)
	local def = if plotId ~= nil then defenses[plotId] else nil
	alertBaseUnderAttack(plotId, if def then def.OwnerUserId else tonumber(sourceModel:GetAttribute("OwnerUserId")), player)
end


local function gateMaxHealthForWalls(wallsLevel: number): number
	local map = GateDefenseConfig.GateMaxHealthByWallsLevel
	if typeof(map) == "table" then
		local h = (map :: any)[math.clamp(math.floor(wallsLevel), 1, 5)]
		if typeof(h) == "number" then
			return h :: number
		end
	end
	return 800 + math.max(wallsLevel, 1) * 400
end

local function setGateBarrierOpen(parts: { BasePart }, open: boolean)
	for _, p in ipairs(parts) do
		if p and p.Parent then
			p.CanCollide = not open
			p.Transparency = if open then 0.55 else 0.15
			p:SetAttribute("GateBreached", open)
			if open then
				p.Color = Color3.fromRGB(90, 70, 55)
				p.Material = Enum.Material.Concrete
			else
				p.Color = Color3.fromRGB(55, 58, 62)
				p.Material = Enum.Material.Metal
			end
		end
	end
end

-- ── gate HP bar (v71, spec §5 "WE_GateHP ×2 → one thin bar centred on the gate") ───────────────────────────

-- an ATM raid hold is running on this plot (MoneyCollectorService stamps WE_RaidingPlot on the thief)
local function plotRaidActive(plotId: any): boolean
	if typeof(plotId) ~= "number" then
		return false
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl:GetAttribute("WE_RaidingPlot") == plotId then
			return true
		end
	end
	return false
end

local function gateBar(parts: { BasePart }): BillboardGui?
	for _, p in ipairs(parts) do
		local bb = p and p:FindFirstChild("WE_GateHP")
		if bb and bb:IsA("BillboardGui") then
			return bb
		end
	end
	return nil
end

-- One bar per gate: a BillboardGui on leaf 1 whose Adornee is an attachment at the middle of the opening.
-- Stud-scaled, never AlwaysOnTop, MaxDistance <= 40; a 14 px status line shows only when breached / down.
local function buildGateBar(leaf: BasePart, gateCf: CFrame, height: number, maxHp: number)
	local cfg = GateDefenseConfig.GateBar
	local studs: Vector2 = cfg.Studs
	local att = Instance.new("Attachment")
	att.Name = "WE_GateBarAnchor"
	att.Parent = leaf
	att.WorldPosition = (gateCf * CFrame.new(0, height - 0.5 + cfg.HeightAbove, 0)).Position
	local bb = Instance.new("BillboardGui")
	bb.Name = "WE_GateHP"
	bb.Adornee = att
	bb.Size = UDim2.fromScale(studs.X, studs.Y)
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.MaxDistance = math.min(cfg.MaxDistance, WorldLabelConfig.MaxDistance)
	bb.Enabled = false -- only while damaged / breached / down / raided (updateGateBillboard, updateDownBillboard)
	bb:SetAttribute("MaxHealth", maxHp)
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.fromScale(0.5, 1)
	track.Size = UDim2.new(1, 0, 0, 6)
	track.BackgroundColor3 = HudConfig.Colors.Ink
	track.BackgroundTransparency = 0.25
	track.BorderSizePixel = 0
	track.Parent = bb
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
	fill.BorderSizePixel = 0
	fill.Parent = track
	local lbl = Instance.new("TextLabel")
	lbl.Name = "Label"
	lbl.AnchorPoint = Vector2.new(0.5, 1)
	lbl.Position = UDim2.new(0.5, 0, 1, -8)
	lbl.Size = UDim2.new(1, 0, 0, 16)
	lbl.BackgroundTransparency = 1
	lbl.Font = HudConfig.WorldLabels.Default.Font
	lbl.TextSize = WorldLabelConfig.MinTextSize
	lbl.TextScaled = false
	lbl.TextStrokeColor3 = HudConfig.Colors.Ink
	lbl.TextStrokeTransparency = 0
	lbl.TextColor3 = Color3.fromRGB(255, 160, 80)
	lbl.Text = ""
	lbl.Visible = false
	lbl.Parent = bb
	bb.Parent = leaf
end

-- status: nil = normal (bar only), else the line above the bar ("BREACHED", "DEFENSES DOWN 4:59")
local function setGateBar(parts: { BasePart }, ratio: number, status: string?, statusColor: Color3?, show: boolean)
	local bb = gateBar(parts)
	if not bb then
		return
	end
	local fill = bb:FindFirstChild("Fill", true)
	if fill and fill:IsA("Frame") then
		local want = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
		if fill.Size ~= want then
			fill.Size = want
		end
	end
	local lbl = bb:FindFirstChild("Label")
	if lbl and lbl:IsA("TextLabel") then
		local vis = status ~= nil
		if lbl.Visible ~= vis then
			lbl.Visible = vis
		end
		if status and lbl.Text ~= status then
			lbl.Text = status
		end
		if statusColor and lbl.TextColor3 ~= statusColor then
			lbl.TextColor3 = statusColor
		end
	end
	if bb.Enabled ~= show then
		bb.Enabled = show
	end
end

local function updateGateBillboard(parts: { BasePart }, health: number, maxHealth: number, breached: boolean)
	local plotId = parts[1] and parts[1]:GetAttribute("PlotId")
	if breached then
		setGateBar(parts, 0, "BREACHED", Color3.fromRGB(255, 160, 80), true)
	else
		local damaged = health < maxHealth - 0.5
		setGateBar(parts, health / math.max(maxHealth, 1), nil, nil, damaged or plotRaidActive(plotId))
	end
end

local function spawnGateBarriers(gateCf: CFrame, wallsLevel: number, parent: Folder, plotId: number, ownerUserId: number): ({ BasePart }, number)
	local clear = GateDefenseConfig.GateClearStuds or 10
	local thickness = GateDefenseConfig.GateBarrierThickness or 1.6
	local height = GateDefenseConfig.GateBarrierHeight or 9
	local maxHp = gateMaxHealthForWalls(wallsLevel)
	local parts: { BasePart } = {}
	local leafW = clear * 0.5 - 0.15
	for i, sx in ipairs({ -leafW * 0.5 - 0.1, leafW * 0.5 + 0.1 }) do
		local leaf = Instance.new("Part")
		leaf.Name = "GateBarrier_" .. tostring(i)
		leaf.Size = Vector3.new(leafW, height, thickness)
		leaf.CFrame = gateCf * CFrame.new(sx, height * 0.5 - 0.5, 0)
		leaf.Anchored = true
		leaf.CanCollide = true
		leaf.CanTouch = false
		leaf.CanQuery = true
		leaf.Color = Color3.fromRGB(55, 58, 62)
		leaf.Material = Enum.Material.Metal
		leaf.Transparency = 0.15
		leaf.CastShadow = true
		leaf:SetAttribute("PlotId", plotId)
		leaf:SetAttribute("OwnerUserId", ownerUserId)
		leaf:SetAttribute("GateBarrier", true)
		leaf:SetAttribute("GateHealth", maxHp)
		leaf:SetAttribute("GateMaxHealth", maxHp)
		leaf:SetAttribute("GateBreached", false)
		leaf.Parent = parent
		local tag = GateDefenseConfig.GateDamageTag or (Constants.Tags and Constants.Tags.GateBarrier) or "WE_GateBarrier"
		pcall(function()
			CollectionService:AddTag(leaf, tag)
		end)
		if i == 1 then
			buildGateBar(leaf, gateCf, height, maxHp) -- one bar for both leaves
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "GateRepairPrompt"
		prompt.ActionText = "Repair Gate"
		prompt.ObjectText = "$" .. tostring(GateDefenseConfig.GateRepairCashCost or 750)
		prompt.HoldDuration = 0.6
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false
		prompt.Parent = leaf
		table.insert(parts, leaf)
	end
	return parts, maxHp
end

local function rebuildGate(def: PlotDefense)
	def.GateBreached = false
	def.GateHealth = def.GateMaxHealth
	def.GateRebuildAt = nil
	def.GateOpen = false
	setGateBarrierOpen(def.GateBarriers, false)
	for _, p in ipairs(def.GateBarriers) do
		if p and p.Parent then
			p:SetAttribute("GateHealth", def.GateHealth)
			p:SetAttribute("GateBreached", false)
			p:SetAttribute("GateOpen", false)
			local prompt = p:FindFirstChild("GateRepairPrompt")
			if prompt and prompt:IsA("ProximityPrompt") then
				prompt.Enabled = false
			end
		end
	end
	updateGateBillboard(def.GateBarriers, def.GateHealth, def.GateMaxHealth, false)
end

local function breachGate(def: PlotDefense)
	if def.GateBreached then
		return
	end
	def.GateBreached = true
	def.GateHealth = 0
	def.GateRebuildAt = os.clock() + (GateDefenseConfig.GateRebuildSeconds or 50)
	def.GateOpen = false
	setGateBarrierOpen(def.GateBarriers, true)
	for _, p in ipairs(def.GateBarriers) do
		if p and p.Parent then
			p:SetAttribute("GateHealth", 0)
			p:SetAttribute("GateBreached", true)
			p:SetAttribute("GateOpen", false)
			local prompt = p:FindFirstChild("GateRepairPrompt")
			if prompt and prompt:IsA("ProximityPrompt") then
				prompt.Enabled = true
			end
		end
	end
	updateGateBillboard(def.GateBarriers, 0, def.GateMaxHealth, true)
	local owner = Players:GetPlayerByUserId(def.OwnerUserId)
	if owner and NotificationService then
		NotificationService.Notify(owner, GateDefenseConfig.GateBreachToast or "Gate breached!", "Warn")
	end
end

--[[ v69 F3 order: (1) sane amount + attacker alive and close to the hit part, (2) a defense on that plot and the
	attacker is not an ally, (3) a guard part → that guard's humanoid takes the damage, (4) else the gate barrier
	(still false while breached or down). Called by CombatService for any hit on a GateBarrier-attributed part. ]]
function GateDefenseService.ApplyDamage(attacker: Player, hitPart: BasePart, amount: number, _weaponId: string?): boolean
	if typeof(amount) ~= "number" or amount ~= amount or amount <= 0 or amount == math.huge then
		return false
	end
	if not hitPart or hitPart:GetAttribute("GateBarrier") ~= true then
		return false
	end
	local isGuardPart = hitPart:GetAttribute("GateGuardPart") == true
	local char = attacker.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local hum = (char :: Model):FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return false
	end
	local maxDist = if isGuardPart then RaidConfig.Defense.GuardHitMaxDistance else 120
	if (root.Position - hitPart.Position).Magnitude > maxDist then
		return false
	end
	local plotId = hitPart:GetAttribute("PlotId")
	if typeof(plotId) ~= "number" then
		return false
	end
	local def = defenses[plotId :: number]
	if not def then
		return false
	end
	if GateDefenseService.IsAlly(def.OwnerUserId, attacker) then
		return false
	end
	graceFrom[attacker.UserId] = nil -- attacking the defenses ends the spawn grace

	if isGuardPart then
		for _, g in ipairs(def.Guards) do
			if hitPart == g.Root or hitPart:IsDescendantOf(g.Model) then
				if g.Alive and g.Humanoid.Health > 0 then
					g.Humanoid:TakeDamage(amount)
					alertBaseUnderAttack(def.PlotId, def.OwnerUserId, attacker)
					return true
				end
				return false
			end
		end
		return false
	end

	if def.GateBreached or isDown(def) then
		return false
	end
	def.GateHealth = math.max(0, def.GateHealth - amount)
	for _, p in ipairs(def.GateBarriers) do
		if p and p.Parent then
			p:SetAttribute("GateHealth", def.GateHealth)
		end
	end
	updateGateBillboard(def.GateBarriers, def.GateHealth, def.GateMaxHealth, false)
	alertBaseUnderAttack(def.PlotId, def.OwnerUserId, attacker)
	if def.GateHealth <= 0 then
		breachGate(def)
	end
	return true
end

function GateDefenseService.TryRepair(player: Player, plotId: number): boolean
	local def = defenses[plotId]
	if not def then
		return false
	end
	if player.UserId ~= def.OwnerUserId then
		return false
	end
	if isDown(def) then
		if NotificationService then
			local left = (def.DownUntil :: number) - os.time()
			NotificationService.Notify(player, "Defenses down — back in " .. RaidConfig.FormatTime(left), "Warn")
		end
		return false
	end
	if not def.GateBreached then
		return false
	end
	local cost = GateDefenseConfig.GateRepairCashCost or 750
	if EconomyService and EconomyService.SpendCash then
		local ok = EconomyService.SpendCash(player, cost, "gate_repair")
		if not ok then
			if NotificationService then
				NotificationService.Notify(player, "Need $" .. tostring(cost) .. " to repair gate", "Warn")
			end
			return false
		end
	end
	rebuildGate(def)
	if NotificationService then
		NotificationService.Notify(player, GateDefenseConfig.GateRepairedToast or "Gate repaired", "Success")
	end
	return true
end

-- ── v69 F5: friendly gate ───────────────────────────────────────────────────

local function setFriendlyGateOpen(def: PlotDefense, open: boolean)
	def.GateOpen = open
	for _, p in ipairs(def.GateBarriers) do
		if p and p.Parent then
			p.CanCollide = not open
			p.Transparency = if open then 0.8 else 0.15
			p:SetAttribute("GateOpen", open)
		end
	end
end

-- Intact barrier: open while the owner / a clan-mate stands at the gate, close GateCloseDelay s after they leave.
local function updateFriendlyGate(def: PlotDefense, tnow: number)
	if def.GateBreached or isDown(def) then
		return
	end
	local D = RaidConfig.Defense
	local gatePos = def.GateCf.Position
	local allyNear = false
	for _, player in ipairs(Players:GetPlayers()) do
		if GateDefenseService.IsAlly(def.OwnerUserId, player) then
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local delta = root.Position - gatePos
				if Vector3.new(delta.X, 0, delta.Z).Magnitude <= D.GateOpenRadius and math.abs(delta.Y) <= D.GateOpenHeight then
					allyNear = true
					break
				end
			end
		end
	end
	if allyNear then
		def.GateAllyAt = tnow
		if not def.GateOpen then
			setFriendlyGateOpen(def, true)
		end
	elseif def.GateOpen and tnow - def.GateAllyAt >= D.GateCloseDelay - 1e-6 then
		setFriendlyGateOpen(def, false)
	end
end

-- ── v69 F7: defenses down (missile strike) ─────────────────────────────────

local function updateDownBillboard(def: PlotDefense)
	local left = math.max(0, (def.DownUntil or 0) - os.time())
	setGateBar(def.GateBarriers, 0, "DEFENSES DOWN " .. RaidConfig.FormatTime(left), Color3.fromRGB(255, 110, 90), true)
end

local RUBBLE: { { number } } = {
	{ -3.2, 0.6, 2.2 },
	{ 2.6, -0.8, 1.8 },
	{ -0.6, 1.9, 1.5 },
	{ 4.1, 1.2, 1.3 },
	{ -4.6, -1.5, 1.6 },
}

-- Guards blown up, AutoGuns offline, gate barrier blown open + rubble/fire (all inside WE_GateDefense;
-- WE_PerimeterWalls is never touched). `blast` = visual-only server explosions on the live guards.
local function applyDefensesDown(def: PlotDefense, untilUnix: number, blast: boolean)
	def.DownUntil = untilUnix
	def.LastDownLabelAt = nowClock()
	for _, g in ipairs(def.Guards) do
		if g.Alive and blast and g.Root.Parent then
			local ex = Instance.new("Explosion")
			ex.Position = g.Root.Position
			ex.BlastRadius = 6
			ex.BlastPressure = 0
			ex.DestroyJointRadiusPercent = 0
			ex.ExplosionType = Enum.ExplosionType.NoCraters
			ex.Parent = Workspace
		end
		g.Alive = false
		if g.Model.Parent then
			g.Model:Destroy()
		end
	end
	for _, t in ipairs(def.Turrets) do
		t.Offline = true
		t.Model:SetAttribute("Offline", true)
		if t.YawPart.Parent and not t.YawPart:FindFirstChild("WE_StrikeSmoke") then
			local smoke = Instance.new("Smoke")
			smoke.Name = "WE_StrikeSmoke"
			smoke.Color = Color3.fromRGB(45, 45, 48)
			smoke.Opacity = 0.35
			smoke.RiseVelocity = 4
			smoke.Size = 2
			smoke.Parent = t.YawPart
		end
	end
	def.GateBreached = true
	def.GateHealth = 0
	def.GateRebuildAt = nil
	def.GateOpen = false
	for _, p in ipairs(def.GateBarriers) do
		if p and p.Parent then
			p.CanCollide = false
			p.CanQuery = false -- blown away: shots pass through
			p.Transparency = 1
			p:SetAttribute("GateHealth", 0)
			p:SetAttribute("GateBreached", true)
			p:SetAttribute("GateOpen", false)
			p:SetAttribute("DefensesDown", true)
			local prompt = p:FindFirstChild("GateRepairPrompt")
			if prompt and prompt:IsA("ProximityPrompt") then
				prompt.Enabled = false
			end
		end
	end
	if def.Folder.Parent and not def.Folder:FindFirstChild("StrikeRubble") then
		for i, o in ipairs(RUBBLE) do
			local size = o[3]
			local r = Instance.new("Part")
			r.Name = "StrikeRubble"
			r.Size = Vector3.new(size, size * 0.55, size * 0.8)
			r.CFrame = def.GateCf * CFrame.new(o[1], -3 + size * 0.25, o[2]) * CFrame.Angles(0.25 * i, 0.9 * i, 0.15 * i)
			r.Anchored = true
			r.CanCollide = false
			r.CanQuery = false
			r.CanTouch = false
			r.Color = Color3.fromRGB(38, 34, 30)
			r.Material = Enum.Material.Slate
			r.Parent = def.Folder
			if i == 1 then
				local fire = Instance.new("Fire")
				fire.Name = "WE_StrikeFire"
				fire.Size = 5
				fire.Heat = 6
				fire.Parent = r
			end
		end
	end
	updateDownBillboard(def)
end

--[[ Missile strike hit (MissileStrikeService is the only caller). untilUnix is os.time. False when this plot has no
	defense built yet — syncPlotNow applies the down state from profile.Raid.DefensesDownUntil when it builds. ]]
function GateDefenseService.SetDefensesDown(plotId: number, untilUnix: number): boolean
	if typeof(plotId) ~= "number" or typeof(untilUnix) ~= "number" or untilUnix ~= untilUnix then
		return false
	end
	local def = defenses[plotId]
	if not def or untilUnix <= os.time() then
		return false
	end
	applyDefensesDown(def, untilUnix, true)
	return true
end

function GateDefenseService.IsDefensesDown(plotId: number): (boolean, number)
	local def = defenses[plotId]
	if def and def.DownUntil ~= nil then
		local left = (def.DownUntil :: number) - os.time()
		if left > 0 then
			return true, left
		end
	end
	return false, 0
end

function GateDefenseService.HasDefenses(plotId: number): boolean
	return defenses[plotId] ~= nil
end

function GateDefenseService.GetGateCFrame(plotId: number): CFrame?
	local def = defenses[plotId]
	return if def then def.GateCf else nil
end

respawnGuard = function(plotId: number, slot: number, ownerUserId: number, def: PlotDefense, dead: GuardUnit)
	if defenses[plotId] ~= def or def.OwnerUserId ~= ownerUserId or isDown(def) or syncBusy[plotId] then
		return
	end
	local idx = table.find(def.Guards, dead)
	local stats = GateDefenseConfig.GetLevelStats(def.WallsLevel)
	if not idx or not stats or not def.Folder.Parent then
		return
	end
	local g = spawnGuardModel(ownerUserId, slot, dead.PostCf, stats, def.Folder, plotId)
	-- the spawn can yield (catalog visual): drop it if the plot was rebuilt / struck meanwhile
	if defenses[plotId] ~= def or isDown(def) or def.Guards[idx] ~= dead or not def.Folder.Parent then
		g.Alive = false
		if g.Model.Parent then
			g.Model:Destroy()
		end
		return
	end
	def.Guards[idx] = g
end

-- Owner's DefensiveWalls level from the loaded profile (0 when offline / not loaded)
local function ownerWallsLevel(ownerUserId: number): number
	local owner = Players:GetPlayerByUserId(ownerUserId)
	if owner and DataService then
		local profile = DataService.GetProfile(owner)
		if profile and profile.BaseUpgrades then
			return tonumber(profile.BaseUpgrades.DefensiveWalls) or 0
		end
	end
	return 0
end

-- Owner's strike timer (profile.Raid.DefensesDownUntil, os.time) when it is still running, else nil
local function ownerDownUntil(ownerUserId: number): number?
	local owner = Players:GetPlayerByUserId(ownerUserId)
	if not (owner and DataService) then
		return nil
	end
	local profile = DataService.GetProfile(owner)
	local raid = profile and (profile :: any).Raid
	local du = if typeof(raid) == "table" then tonumber(raid.DefensesDownUntil) else nil
	if du and du > os.time() then
		return du
	end
	return nil
end

-- Plot pad (WE_BasePlot) centre + half-size minus a margin: "inside the walls" for engage / chase limits
local function findPadBounds(plotId: number, plotFolder: Folder): (Vector3?, number)
	local pad: BasePart? = nil
	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.BasePlot)) do
		if inst:IsA("BasePart") and inst:GetAttribute("PlotId") == plotId then
			pad = inst
			break
		end
	end
	if not pad then
		local p = plotFolder:FindFirstChild("PlotPad")
		if p and p:IsA("BasePart") then
			pad = p
		end
	end
	if not pad then
		return nil, 0
	end
	return pad.Position, math.max(pad.Size.X, pad.Size.Z) * 0.5 - 2
end

local function syncPlotNow(plotId: number)
	if not GateDefenseConfig.Enabled then
		clearDefense(plotId)
		return
	end
	local ownerUserId = if BaseService and BaseService.GetOwnerUserId then BaseService.GetOwnerUserId(plotId) else nil
	if not ownerUserId then
		clearDefense(plotId)
		return
	end
	local wallsLevel = ownerWallsLevel(ownerUserId)
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

	-- v69 F7: a strike still running (rejoin / server hop / walls upgrade / plot-ready) → build it down
	local downUntil = ownerDownUntil(ownerUserId)

	-- v69 F2: posts INSIDE the gate. gateCf looks toward PlayerSpawn, so local -Z is inside (it used to be +Z:
	-- outside the wall, AutoGuns embedded in it at L4-5, no line of sight to the ATM).
	local flankX = GateDefenseConfig.GuardFlankX or 6
	local guardInside = RaidConfig.Defense.GuardPostInsideStuds
	local guards: { GuardUnit } = {}
	if downUntil == nil then
		for slot, sx in ipairs({ -flankX, flankX }) do
			local at = gateCf * CFrame.new(sx, 0, -guardInside)
			local g = spawnGuardModel(ownerUserId, slot, at, stats, folder, plotId)
			g.Model:SetAttribute("OwnerUserId", ownerUserId)
			table.insert(guards, g)
		end
	end

	local turrets: { TurretUnit } = {}
	local useTurrets = stats.UseTurrets == true and wallsLevel >= (GateDefenseConfig.AutoGunMinWallsLevel or 4)
	if useTurrets then
		local gx = GateDefenseConfig.AutoGunFlankX or 7
		local gunInside = RaidConfig.Defense.AutoGunInsideStuds
		local yawDeg = GateDefenseConfig.AutoGunYawDeg or 15
		for slot, sx in ipairs({ -gx, gx }) do
			local yaw = if sx < 0 then yawDeg else -yawDeg
			-- idle facing the gate (outward), toed in toward the gate centre; thinkTurret re-aims at targets
			local at = gateCf * CFrame.new(sx, 0, -gunInside) * CFrame.Angles(0, math.pi + math.rad(yaw), 0)
			local t = spawnAutoGun(slot, at, folder)
			if t then
				t.Model:SetAttribute("OwnerUserId", ownerUserId)
				t.Model:SetAttribute("PlotId", plotId)
				table.insert(turrets, t)
			end
		end
	end

	-- v69: owner left / plot changed hands while the spawns above yielded → drop this build
	local ownerNow = if BaseService and BaseService.GetOwnerUserId then BaseService.GetOwnerUserId(plotId) else nil
	if ownerNow ~= ownerUserId or folder.Parent == nil then
		for _, g in ipairs(guards) do
			g.Alive = false
		end
		if folder.Parent then
			folder:Destroy()
		end
		return
	end

	local barriers, maxHp = spawnGateBarriers(gateCf, wallsLevel, folder, plotId, ownerUserId)
	for _, leaf in ipairs(barriers) do
		local prompt = leaf:FindFirstChild("GateRepairPrompt")
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Triggered:Connect(function(who: Player)
				GateDefenseService.TryRepair(who, plotId)
			end)
		end
	end

	local padCenter, padHalf = findPadBounds(plotId, plotFolder)
	local def: PlotDefense = {
		PlotId = plotId,
		OwnerUserId = ownerUserId,
		WallsLevel = wallsLevel,
		Folder = folder,
		Guards = guards,
		Turrets = turrets,
		GateCf = gateCf,
		CollectorPos = findCollectorPos(plotId),
		CollectorModel = findCollectorModel(plotId),
		GateHealth = maxHp,
		GateMaxHealth = maxHp,
		GateBreached = false,
		GateBarriers = barriers,
		GateRebuildAt = nil,
		LastRegenAt = os.clock(),
		DownUntil = nil,
		LastDownLabelAt = 0,
		GateOpen = false,
		GateAllyAt = 0,
		PadCenter = padCenter,
		PadHalf = padHalf,
	}
	defenses[plotId] = def
	-- re-read: a strike that landed while the spawns above yielded found no def (SetDefensesDown → false)
	local downNow = ownerDownUntil(ownerUserId)
	if downNow ~= nil then
		applyDefensesDown(def, downNow, downUntil == nil)
	end

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

function GateDefenseService.SyncPlot(plotId: number)
	if syncBusy[plotId] then
		syncAgain[plotId] = true -- coalesce: re-run once the running sync ends (picks up the latest level)
		return
	end
	syncBusy[plotId] = true
	repeat
		syncAgain[plotId] = nil
		xpcall(syncPlotNow, function(err)
			warn("[GateDefense] SyncPlot failed plot=", plotId, err)
		end, plotId)
	until not syncAgain[plotId]
	syncBusy[plotId] = nil
end

--[[ v69: idempotent — syncs only when the plot's defense does not match its owner + current walls level
	(missing, other owner, level changed, or folder lost to a map rebuild). Safe to call on every plot-ready. ]]
function GateDefenseService.EnsurePlot(plotId: number)
	if not GateDefenseConfig.Enabled then
		return
	end
	local ownerUserId = if BaseService and BaseService.GetOwnerUserId then BaseService.GetOwnerUserId(plotId) else nil
	local def = defenses[plotId]
	if ownerUserId == nil then
		if def then
			GateDefenseService.SyncPlot(plotId)
		end
		return
	end
	local wallsLevel = ownerWallsLevel(ownerUserId)
	local wantDefense = GateDefenseConfig.GetLevelStats(wallsLevel) ~= nil
	local inSync = if wantDefense
		then def ~= nil
			and def.OwnerUserId == ownerUserId
			and def.WallsLevel == wallsLevel
			and def.Folder.Parent ~= nil
		else def == nil
	if not inSync then
		GateDefenseService.SyncPlot(plotId)
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
	local plr, hum, troot, dist = nearestEnemy(def, g.Root.Position, aggro, nil)
	if plr and hum and troot then
		faceYaw(g.Root, troot.Position)
		local ignore: { Instance } = { g.Model, def.Folder, (plr.Character :: any) :: Instance }
		if def.CollectorModel then
			table.insert(ignore, def.CollectorModel :: Instance)
		end
		if dist > range * 0.85 then
			g.Humanoid:MoveTo(clampInsidePlot(def, troot.Position))
		else
			g.Humanoid:MoveTo(g.Root.Position)
			local interval = 1 / math.max(stats.GuardFireRate or 1.4, 0.1)
			if tnow - g.LastFireAt >= interval and dist <= range then
				if hasLos(g.Root.Position, troot.Position, ignore) then
					g.LastFireAt = tnow
					dealDamage(plr, hum, (stats.GuardDamage or 14) * researchMult(def.OwnerUserId), g.Model, def.PlotId)
				end
			end
		end
		return
	end

	-- Patrol near own post, along the gate line (v69: inside the gate)
	local half = GateDefenseConfig.PatrolHalfSpanStuds or 6
	local idle = GateDefenseConfig.PatrolIdleSeconds or 1.4
	local postZ = -RaidConfig.Defense.GuardPostInsideStuds
	local flankX = GateDefenseConfig.GuardFlankX or 6
	local sx = if g.Slot == 1 then -flankX else flankX
	local toward = if g.Slot == 1 then half * 0.5 else -half * 0.5
	local waypoints = {
		(def.GateCf * CFrame.new(sx, 0, postZ)).Position,
		(def.GateCf * CFrame.new(sx + toward, 0, postZ)).Position,
	}
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
	if t.Offline or not t.Model.Parent or not t.YawPart.Parent then
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
		local ignore: { Instance } = { t.Model, def.Folder, (plr.Character :: any) :: Instance }
		if def.CollectorModel then
			table.insert(ignore, def.CollectorModel :: Instance)
		end
		if hasLos(fromPos, troot.Position, ignore) then
			t.LastFireAt = tnow
			dealDamage(plr, hum, (stats.TurretDamage or 22) * researchMult(def.OwnerUserId), t.Model, def.PlotId)
		end
	end
end

function GateDefenseService.Init(deps: { [string]: any })
	BaseService = deps.BaseService
	DataService = deps.DataService
	VisualAssetService = deps.VisualAssetService
	ClanService = deps.ClanService
	ResearchService = deps.ResearchService
	EconomyService = deps.EconomyService
	NotificationService = deps.NotificationService

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

	-- v69: spawn from the LOADED save whenever the owner's plot is (re)built — join (DataService v67 fires
	-- OnProfileLoaded only after the real save is read; BaseService then builds the walls/GatePosts and fires
	-- OnPlotReady), a freed plot handed out, prestige, map rebuild. Replaces the fixed 1.2 s / 3.5 s timers,
	-- which missed any save/walls that landed later and then never re-synced for the whole session.
	local hookedPlotReady = false
	if BaseService and BaseService.OnPlotReady then
		local okHook, errHook = pcall(BaseService.OnPlotReady, function(_player: Player, plotId: number)
			GateDefenseService.EnsurePlot(plotId)
		end)
		hookedPlotReady = okHook
		if not okHook then
			warn("[GateDefense] OnPlotReady hook failed:", errHook)
		end
	end
	-- Spawn grace clock: every character spawn, and the save load (the move to the player's own plot follows it)
	local function hookGrace(player: Player)
		player.CharacterAdded:Connect(function()
			startSpawnGrace(player)
		end)
		if player.Character then
			startSpawnGrace(player)
		end
	end
	Players.PlayerAdded:Connect(hookGrace)
	for _, player in ipairs(Players:GetPlayers()) do
		hookGrace(player)
	end

	if DataService and DataService.OnProfileLoaded then
		-- Belt: late ensure for the loaded owner's plot (no-op when already in sync); sole path if the hook failed
		DataService.OnProfileLoaded(function(player: Player, _profile: any)
			startSpawnGrace(player)
			for _, delaySec in ipairs(if hookedPlotReady then { 10 } else { 1.2, 3.5, 10 }) do
				task.delay(delaySec, function()
					local plotId = if player.Parent and BaseService and BaseService.GetOwnedPlotId
						then BaseService.GetOwnedPlotId(player)
						else nil
					if typeof(plotId) == "number" then
						GateDefenseService.EnsurePlot(plotId)
					end
				end)
			end
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
		graceFrom[player.UserId] = nil
	end)

	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < 0.2 then
			return
		end
		accum = 0
		local tnow = nowClock()
		local nowUnix = os.time()
		local restore: { number } = {}
		for plotId, def in pairs(defenses) do
			if def.DownUntil ~= nil then
				-- v69 F7: struck — no guards, AutoGuns offline, gate blown; count down, then rebuild fresh
				if nowUnix >= (def.DownUntil :: number) then
					table.insert(restore, plotId)
				elseif tnow - def.LastDownLabelAt >= 1 then
					def.LastDownLabelAt = tnow
					updateDownBillboard(def)
				end
				continue
			end
			local stats = GateDefenseConfig.GetLevelStats(def.WallsLevel)
			if stats then
				if not def.CollectorPos then
					def.CollectorPos = findCollectorPos(plotId)
				end
				if def.CollectorModel == nil or (def.CollectorModel :: Instance).Parent == nil then
					def.CollectorModel = findCollectorModel(plotId)
				end
				for _, g in ipairs(def.Guards) do
					thinkGuard(def, g, stats, tnow)
				end
				for _, tur in ipairs(def.Turrets) do
					thinkTurret(def, tur, stats, tnow)
				end
				-- Gate regen / auto-rebuild (guards keep shooting either way)
				if def.GateBreached then
					if def.GateRebuildAt and tnow >= def.GateRebuildAt then
						rebuildGate(def)
					end
				elseif def.GateHealth < def.GateMaxHealth then
					local regen = GateDefenseConfig.GateRegenPerSecond or 0
					if regen > 0 then
						local dtRegen = tnow - (def.LastRegenAt or tnow)
						def.LastRegenAt = tnow
						def.GateHealth = math.min(def.GateMaxHealth, def.GateHealth + regen * dtRegen)
						for _, bp in ipairs(def.GateBarriers) do
							if bp and bp.Parent then
								bp:SetAttribute("GateHealth", def.GateHealth)
							end
						end
						updateGateBillboard(def.GateBarriers, def.GateHealth, def.GateMaxHealth, false)
					end
				end
				-- v69 F5: the gate lets the owner and clan-mates through
				updateFriendlyGate(def, tnow)
				-- v71: the gate bar also shows while an ATM raid runs on this plot (≈1 Hz; writes only on change)
				if tnow - (barCheckAt[plotId] or 0) >= 1 then
					barCheckAt[plotId] = tnow
					updateGateBillboard(def.GateBarriers, def.GateHealth, def.GateMaxHealth, def.GateBreached)
				end
			end
		end
		-- (outside the pairs loop: SyncPlot replaces defenses[plotId] and can yield)
		for _, plotId in ipairs(restore) do
			local def = defenses[plotId]
			if def then
				def.DownUntil = nil
				local ownerUserId = def.OwnerUserId
				task.spawn(function()
					GateDefenseService.SyncPlot(plotId)
					local owner = Players:GetPlayerByUserId(ownerUserId)
					if owner and NotificationService then
						NotificationService.Notify(owner, RaidConfig.Text.DefensesBack, "Success")
					end
				end)
			end
		end
	end)

	print("[WAR EMPIRE] GateDefenseService ready (walls≥1 → GateGuards + siegeable GateBarrier HP; walls≥4 → AutoGun nests; allies = clan)")
end

return GateDefenseService
