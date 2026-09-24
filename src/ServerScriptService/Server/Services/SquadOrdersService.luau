--!strict
--[[
	Squad Orders — server-authoritative Follow / Attack / Hold / Retreat.
	Extends SoldierService counts + Combat MoveTo patterns. Not a second army economy.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local OrdersConfig = require(Shared.Configs.OrdersConfig)

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)

local SquadOrdersService = {}

local DataService: any = nil
local SoldierService: any = nil
local NotificationService: any = nil
local RateLimitService: any = nil
local RemoteSetup: any = nil
local AntiExploitService: any = nil
local VisualAssetService: any = nil
local BaseService: any = nil

export type OrderId = "Follow" | "Attack" | "Hold" | "Retreat"

type SquadUnit = {
	Id: string,
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	OwnerUserId: number,
	Slot: number,
	LastFireAt: number,
	HoldPos: Vector3?,
	Alive: boolean,
}

type SquadState = {
	Order: OrderId,
	Units: { SquadUnit },
	DesiredCount: number,
}

local VALID: { [string]: boolean } = {
	Follow = true,
	Attack = true,
	Hold = true,
	Retreat = true,
}

local TAG_SQUAD = "WE_SquadUnit"
local squadByUser: { [number]: SquadState } = {}
local unitSerial = 0
local squadFolder: Folder? = nil

local function ensureFolder(): Folder
	if squadFolder and squadFolder.Parent then
		return squadFolder :: Folder
	end
	local existing = Workspace:FindFirstChild("WarEmpireSquads")
	if existing and existing:IsA("Folder") then
		squadFolder = existing
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = "WarEmpireSquads"
	f.Parent = Workspace
	squadFolder = f
	return f
end

local function characterRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local hum = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if hum and root and root:IsA("BasePart") and hum.Health > 0 then
		return root
	end
	return nil
end

local function plotRetreatCFrame(player: Player): CFrame?
	local profile = DataService.GetProfile(player)
	if not profile then
		return nil
	end
	local plotId = tonumber(profile.BasePlotId)
	if not plotId then
		return nil
	end
	if BaseService and BaseService.GetPlotSpawnCFrame then
		return BaseService.GetPlotSpawnCFrame(plotId)
	end
	return nil
end

local function pushState(player: Player)
	if not RemoteSetup then
		return
	end
	local st = squadByUser[player.UserId]
	local remote = RemoteSetup.Get(Constants.RemoteNames.SquadOrderStateUpdate) :: RemoteEvent
	local soldiers = if SoldierService then SoldierService.GetCount(player) else 0
	local alive = 0
	if st then
		for _, u in ipairs(st.Units) do
			if u.Alive then
				alive += 1
			end
		end
	end
	local show = OrdersConfig.Enabled == true and soldiers >= (OrdersConfig.MinSoldiersToShow or 1)
	remote:FireClient(player, {
		Enabled = OrdersConfig.Enabled == true,
		Order = if st then st.Order else (OrdersConfig.DefaultOrder or "Follow"),
		Soldiers = soldiers,
		FieldUnits = alive,
		MaxFieldUnits = OrdersConfig.MaxFieldUnits or 5,
		ShowPanel = show,
	})
end

local function destroyUnit(unit: SquadUnit)
	unit.Alive = false
	if unit.Model and unit.Model.Parent then
		unit.Model:Destroy()
	end
end

local function clearSquad(userId: number)
	local st = squadByUser[userId]
	if not st then
		return
	end
	for _, u in ipairs(st.Units) do
		destroyUnit(u)
	end
	st.Units = {}
	st.DesiredCount = 0
end

local function formationOffset(slot: number): Vector3
	local spacing = OrdersConfig.FormationSpacing or 3.5
	local row = math.ceil(slot / 3)
	local col = ((slot - 1) % 3) - 1
	return Vector3.new(col * spacing, 0, 6 + (row - 1) * spacing)
end

local function spawnUnit(owner: Player, slot: number, at: CFrame): SquadUnit?
	unitSerial += 1
	local id = string.format("squad_%d_%d", owner.UserId, unitSerial)

	local model = Instance.new("Model")
	model.Name = (OrdersConfig.DisplayName or "Squad") .. tostring(slot)
	model:SetAttribute("SquadUnitId", id)
	model:SetAttribute("OwnerUserId", owner.UserId)
	model:SetAttribute("SquadSlot", slot)
	model:SetAttribute("FriendlySquad", true)

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = at
	root.Anchored = false
	root.CanCollide = true
	root.Color = OrdersConfig.UnitColor or Color3.fromRGB(70, 90, 55)
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

	local olive = OrdersConfig.UnitColor or Color3.fromRGB(70, 90, 55)
	local skin = Color3.fromRGB(190, 160, 120)
	local head = weldPart("Head", Vector3.new(1.05, 1.05, 1.05), CFrame.new(0, 1.55, 0), skin, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Face = Enum.NormalId.Front
	face.Texture = "rbxasset://textures/face.png"
	face.Parent = head
	weldPart("Helmet", Vector3.new(1.2, 0.5, 1.2), CFrame.new(0, 1.95, 0), Color3.fromRGB(55, 70, 45), Enum.Material.Metal, nil)
	weldPart("Vest", Vector3.new(2.1, 1.2, 1.15), CFrame.new(0, 0.15, 0), olive, Enum.Material.Fabric, nil)
	weldPart("LegL", Vector3.new(1, 2, 1), CFrame.new(-0.5, -2, 0), olive, Enum.Material.Fabric, nil)
	weldPart("LegR", Vector3.new(1, 2, 1), CFrame.new(0.5, -2, 0), olive, Enum.Material.Fabric, nil)
	weldPart("ArmL", Vector3.new(1, 2, 1), CFrame.new(-1.5, 0, 0), olive, Enum.Material.Fabric, nil)
	weldPart("ArmR", Vector3.new(1, 2, 1), CFrame.new(1.5, 0, 0), olive, Enum.Material.Fabric, nil)
	weldPart("Rifle", Vector3.new(0.26, 0.26, 2.4), CFrame.new(1.15, 0.15, -0.85), Color3.fromRGB(28, 28, 30), Enum.Material.Metal, nil)

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = OrdersConfig.UnitHealth or 90
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = OrdersConfig.UnitWalkSpeed or 14
	humanoid.AutoRotate = true
	humanoid.HipHeight = 2
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.NameOcclusion = Enum.NameOcclusion.OccludeAll
	humanoid.Parent = model

	-- v68: no floating "SQUAD" tag per soldier by default (a wall of labels over the squad — owner report).
	if (OrdersConfig :: any).ShowUnitLabels == true then
		local bb = Instance.new("BillboardGui")
		bb.Name = "SquadLabel"
		bb.Size = UDim2.fromOffset(100, 22)
		bb.StudsOffset = Vector3.new(0, 3.4, 0)
		bb.AlwaysOnTop = false
		bb.MaxDistance = 60
		bb.Parent = root
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundColor3 = Color3.fromRGB(28, 36, 28)
		lbl.BackgroundTransparency = 0.3
		lbl.Text = "SQUAD"
		lbl.TextColor3 = Color3.fromRGB(180, 220, 140)
		lbl.TextScaled = true
		lbl.Font = Enum.Font.GothamBold
		lbl.Parent = bb
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = lbl
	end

	model.PrimaryPart = root
	if VisualAssetService and VisualAssetService.TryAttachCharacterVisual then
		pcall(function()
			VisualAssetService.TryAttachCharacterVisual(model, OrdersConfig.VisualKind or "Infantry")
		end)
	end
	-- Friendly only — do NOT tag WE_NPC (CombatNPC would aggro players)
	CollectionService:AddTag(model, TAG_SQUAD)
	model.Parent = ensureFolder()
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	local gyro = Instance.new("BodyGyro")
	gyro.Name = "NPCFaceGyro"
	gyro.MaxTorque = Vector3.new(0, 4e5, 0)
	gyro.P = 5000
	gyro.D = 500
	gyro.CFrame = at
	gyro.Parent = root

	local unit: SquadUnit = {
		Id = id,
		Model = model,
		Humanoid = humanoid,
		Root = root,
		OwnerUserId = owner.UserId,
		Slot = slot,
		LastFireAt = 0,
		HoldPos = nil,
		Alive = true,
	}

	humanoid.Died:Connect(function()
		if not unit.Alive then
			return
		end
		unit.Alive = false
		task.delay(0.35, function()
			if unit.Model and unit.Model.Parent then
				unit.Model:Destroy()
			end
		end)
		task.delay(8, function()
			local plr = Players:GetPlayerByUserId(owner.UserId)
			if plr then
				SquadOrdersService.SyncArmy(plr)
			end
		end)
	end)

	return unit
end

local function nearestHostile(fromPos: Vector3, maxRange: number): (Humanoid?, BasePart?, number)
	local bestHum: Humanoid? = nil
	local bestRoot: BasePart? = nil
	local bestDist = maxRange
	local npcTag = Constants.Tags.NPC
	for _, inst in ipairs(CollectionService:GetTagged(npcTag)) do
		if inst:IsA("Model") and not inst:GetAttribute("FriendlySquad") and not inst:GetAttribute("OwnerUserId") then
			local hum = inst:FindFirstChildOfClass("Humanoid")
			local root = inst:FindFirstChild("HumanoidRootPart")
			if hum and root and root:IsA("BasePart") and hum.Health > 0 then
				local d = (root.Position - fromPos).Magnitude
				if d < bestDist then
					bestDist = d
					bestHum = hum
					bestRoot = root
				end
			end
		end
	end
	return bestHum, bestRoot, bestDist
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

local function thinkUnit(player: Player, st: SquadState, unit: SquadUnit, now: number)
	if not unit.Alive or unit.Humanoid.Health <= 0 or not unit.Root.Parent then
		return
	end
	local order = st.Order
	local playerRoot = characterRoot(player)

	if order == "Follow" then
		if not playerRoot then
			return
		end
		local offset = formationOffset(unit.Slot)
		local target = (playerRoot.CFrame * CFrame.new(offset)).Position
		local dist = (unit.Root.Position - playerRoot.Position).Magnitude
		local stop = OrdersConfig.FollowStopDistance or 6
		if dist > (OrdersConfig.FollowDistance or 10) then
			unit.Humanoid:MoveTo(target)
			faceYaw(unit.Root, playerRoot.Position)
		elseif dist > stop then
			unit.Humanoid:MoveTo(target)
		else
			unit.Humanoid:MoveTo(unit.Root.Position)
		end
		return
	end

	if order == "Hold" then
		if not unit.HoldPos then
			unit.HoldPos = unit.Root.Position
		end
		local leash = OrdersConfig.HoldLeashStuds or 14
		local holdPos = unit.HoldPos :: Vector3
		local dist = (unit.Root.Position - holdPos).Magnitude
		if dist > leash * 0.4 then
			unit.Humanoid:MoveTo(holdPos)
		else
			unit.Humanoid:MoveTo(unit.Root.Position)
		end
		return
	end

	if order == "Retreat" then
		local cf = plotRetreatCFrame(player)
		if cf then
			local dest = cf.Position
			local dist = (unit.Root.Position - dest).Magnitude
			if dist > 6 then
				unit.Humanoid:MoveTo(dest)
				faceYaw(unit.Root, dest)
			else
				unit.Humanoid:MoveTo(unit.Root.Position)
				unit.HoldPos = unit.Root.Position
			end
		elseif playerRoot then
			unit.Humanoid:MoveTo((playerRoot.CFrame * CFrame.new(0, 0, 8)).Position)
		end
		return
	end

	if order == "Attack" then
		local aggro = OrdersConfig.AttackAggroRange or 120
		local range = OrdersConfig.AttackRange or 55
		local th, troot, dist = nearestHostile(unit.Root.Position, aggro)
		if troot then
			faceYaw(unit.Root, troot.Position)
			if dist > range * 0.85 then
				unit.Humanoid:MoveTo(troot.Position)
			else
				unit.Humanoid:MoveTo(unit.Root.Position)
				if th and th.Health > 0 then
					local interval = 1 / math.max(OrdersConfig.AttackFireRate or 1.8, 0.1)
					if now - unit.LastFireAt >= interval and dist <= range then
						unit.LastFireAt = now
						th:TakeDamage(OrdersConfig.AttackDamage or 8)
					end
				end
			end
		elseif playerRoot then
			unit.Humanoid:MoveTo((playerRoot.CFrame * CFrame.new(0, 0, -12)).Position)
		end
		return
	end
end

function SquadOrdersService.SyncArmy(player: Player)
	if not OrdersConfig.Enabled then
		clearSquad(player.UserId)
		pushState(player)
		return
	end
	local soldiers = if SoldierService then SoldierService.GetCount(player) else 0
	local maxField = OrdersConfig.MaxFieldUnits or 5
	local per = OrdersConfig.UnitsPerSoldier or 1
	local desired = math.clamp(math.floor(soldiers * per), 0, maxField)
	if soldiers < (OrdersConfig.MinSoldiersToShow or 1) then
		desired = 0
	end

	local st = squadByUser[player.UserId]
	if not st then
		st = {
			Order = (OrdersConfig.DefaultOrder :: any) or "Follow",
			Units = {},
			DesiredCount = 0,
		}
		squadByUser[player.UserId] = st
	end
	st.DesiredCount = desired

	local living: { SquadUnit } = {}
	for _, u in ipairs(st.Units) do
		if u.Alive and u.Model.Parent and u.Humanoid.Health > 0 then
			table.insert(living, u)
		else
			destroyUnit(u)
		end
	end
	st.Units = living

	while #st.Units > desired do
		local u = table.remove(st.Units)
		if u then
			destroyUnit(u)
		end
	end

	local root = characterRoot(player)
	local baseCf: CFrame? = if root then root.CFrame else plotRetreatCFrame(player)
	if not baseCf then
		pushState(player)
		return
	end
	while #st.Units < desired do
		local slot = #st.Units + 1
		local offset = formationOffset(slot)
		local at = (baseCf :: CFrame) * CFrame.new(offset) + Vector3.new(0, 2, 0)
		local unit = spawnUnit(player, slot, at)
		if unit then
			table.insert(st.Units, unit)
		else
			break
		end
	end

	pushState(player)
end


local function flashOrderBillboard(player: Player, st: SquadState, order: OrderId)
	local labels = (OrdersConfig :: any).OrderLabels or {
		Follow = "FOLLOWING",
		Attack = "ATTACKING",
		Hold = "HOLDING",
		Retreat = "RETREATING",
	}
	local textLabel = labels[order] or string.upper(order)
	local root = characterRoot(player)
	local best: SquadUnit? = nil
	local bestDist = math.huge
	local origin = if root then root.Position else nil
	for _, u in ipairs(st.Units) do
		if u.Alive and u.Root and u.Root.Parent then
			local d = if origin then (u.Root.Position - origin).Magnitude else u.Slot
			if d < bestDist then
				bestDist = d
				best = u
			end
		end
	end
	if not best then
		return
	end
	local bb = best.Root:FindFirstChild("SquadLabel")
	if not (bb and bb:IsA("BillboardGui")) then
		return
	end
	local lbl = bb:FindFirstChildOfClass("TextLabel")
	if not lbl then
		return
	end
	local prev = lbl.Text
	local prevColor = lbl.TextColor3
	lbl.Text = textLabel
	lbl.TextColor3 = Color3.fromRGB(255, 230, 120)
	bb.StudsOffset = Vector3.new(0, 4.2, 0)
	bb.AlwaysOnTop = true
	local hold = tonumber((OrdersConfig :: any).OrderBillboardSeconds) or 2.8
	local token = tostring(os.clock())
	best.Root:SetAttribute("WE_OrderFlash", token)
	task.delay(hold, function()
		if not best or not best.Root or not best.Root.Parent then
			return
		end
		if best.Root:GetAttribute("WE_OrderFlash") ~= token then
			return
		end
		if lbl and lbl.Parent then
			lbl.Text = prev
			lbl.TextColor3 = prevColor
		end
		if bb and bb.Parent then
			bb.StudsOffset = Vector3.new(0, 3.4, 0)
			bb.AlwaysOnTop = false
		end
	end)
end

function SquadOrdersService.SetOrder(player: Player, orderRaw: any): (boolean, string?)
	if not OrdersConfig.Enabled then
		return false, "Disabled"
	end
	if typeof(orderRaw) ~= "string" then
		return false, "InvalidOrder"
	end
	local order = orderRaw :: string
	if not VALID[order] then
		return false, "InvalidOrder"
	end
	local flags = OrdersConfig.Orders
	if typeof(flags) == "table" and (flags :: any)[order] == false then
		return false, "OrderDisabled"
	end
	local soldiers = if SoldierService then SoldierService.GetCount(player) else 0
	if soldiers < (OrdersConfig.MinSoldiersToShow or 1) then
		return false, "NoSoldiers"
	end

	local st = squadByUser[player.UserId]
	if not st then
		SquadOrdersService.SyncArmy(player)
		st = squadByUser[player.UserId]
	end
	if not st then
		return false, "NoSquad"
	end

	st.Order = order :: OrderId
	if order == "Hold" then
		for _, u in ipairs(st.Units) do
			if u.Alive then
				u.HoldPos = u.Root.Position
			end
		end
	else
		for _, u in ipairs(st.Units) do
			u.HoldPos = nil
		end
	end

	pushState(player)
	flashOrderBillboard(player, st, order :: OrderId)
	if NotificationService then
		local labels = {
			Follow = "Squad: FOLLOW",
			Attack = "Squad: ATTACK nearest hostile",
			Hold = "Squad: HOLD position",
			Retreat = "Squad: RETREAT to plot",
		}
		NotificationService.Notify(player, labels[order] or ("Squad: " .. order), "Info")
	end
	return true, nil
end

function SquadOrdersService.Push(player: Player)
	pushState(player)
end

function SquadOrdersService.Init(deps: { [string]: any })
	DataService = deps.DataService
	SoldierService = deps.SoldierService
	NotificationService = deps.NotificationService
	RateLimitService = deps.RateLimitService
	RemoteSetup = deps.RemoteSetup
	AntiExploitService = deps.AntiExploitService
	VisualAssetService = deps.VisualAssetService
	BaseService = deps.BaseService

	if not OrdersConfig.Enabled then
		print("[WAR EMPIRE] SquadOrdersService disabled (OrdersConfig.Enabled=false)")
		return
	end

	ensureFolder()

	local orderRemote = RemoteSetup.Get(Constants.RemoteNames.RequestSquadOrder) :: RemoteEvent
	orderRemote.OnServerEvent:Connect(function(player: Player, orderId: any)
		local rate = OrdersConfig.OrderRatePerSec or 2
		local burst = OrdersConfig.OrderBurst or 4
		if not RateLimitService.Allow(player, "squad_order", rate, burst) then
			if AntiExploitService and AntiExploitService.Strike then
				AntiExploitService.Strike(player, "squad_order_rate")
			end
			return
		end
		if not RemoteGuard.RequireProfile(DataService, player) then
			return
		end
		local ok, err = SquadOrdersService.SetOrder(player, orderId)
		if not ok and NotificationService then
			local msg = "Order failed"
			if err == "NoSoldiers" then
				msg = "Recruit soldiers first (Army)"
			elseif err == "InvalidOrder" then
				msg = "Invalid squad order"
			end
			NotificationService.Notify(player, msg, "Warn")
		end
	end)

	DataService.OnProfileLoaded(function(player: Player, _profile: any)
		task.defer(function()
			if player.Parent then
				SquadOrdersService.SyncArmy(player)
			end
		end)
		task.delay(2, function()
			if player.Parent then
				SquadOrdersService.SyncArmy(player)
			end
		end)
		player.CharacterAdded:Connect(function()
			task.delay(1, function()
				if player.Parent then
					SquadOrdersService.SyncArmy(player)
				end
			end)
		end)
	end)

	-- Hook army count changes without touching SoldierService billboards
	if SoldierService and SoldierService.OnArmyChanged then
		SoldierService.OnArmyChanged(function(player: Player)
			SquadOrdersService.SyncArmy(player)
		end)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		clearSquad(player.UserId)
		squadByUser[player.UserId] = nil
	end)

	task.spawn(function()
		while true do
			local interval = OrdersConfig.ThinkInterval or 0.4
			task.wait(interval)
			local now = os.clock()
			for _, player in ipairs(Players:GetPlayers()) do
				local st = squadByUser[player.UserId]
				if st and #st.Units > 0 then
					for _, unit in ipairs(st.Units) do
						thinkUnit(player, st, unit, now)
					end
				end
			end
		end
	end)

	print("[WAR EMPIRE] SquadOrdersService ready (Follow/Attack/Hold/Retreat)")
end

return SquadOrdersService
