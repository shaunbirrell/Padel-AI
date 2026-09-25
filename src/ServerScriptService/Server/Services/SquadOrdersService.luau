--!strict
--[[
	Squad Orders — server-authoritative Follow / Attack / Hold / Retreat.
	Extends SoldierService counts + Combat MoveTo patterns. Not a second army economy.
	P1-4 (mobile plan): Follow is an escort — units shoot hostiles within CombatFairnessConfig.EscortEngageRadius of
	their player (line of sight required) while staying within EscortLeash of the player. Every unit hit tags the
	owner as creator (CombatDamage.TagCreator, unit flag), so squad kills credit the owner at UnitKillCashShare.
	v71 (HUD v70 spec §4.2 / §5): no per-unit "SQUAD" tags and no "Squad: X" toast per order — the order flashes
	for OrderBillboardSeconds as one owner-only stud-scaled WorldLabel over the nearest unit (flashOrderBillboard),
	and the Army popover shows the active order.
	Base identity lane C: Follow slots come from OrdersConfig.FollowSlots, two wings beside the player instead of rows
	straight behind (the old grid stood between the third-person camera and the player). A unit whose straight walk to
	its slot is blocked (door, narrow lane, stairs) walks the player's own trail (OrdersConfig.FollowPath) and fans back
	out once its slot is in sight. Helmets are domes (SpecialMesh Sphere on the same part: 0 extra parts).
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local OrdersConfig = require(Shared.Configs.OrdersConfig)
local CombatFairnessConfig = require(Shared.Configs.CombatFairnessConfig) -- P1-4 escort + kill credit
local WorldLabel = require(Shared.Util.WorldLabel)

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)
local CombatDamage = require(script.Parent.CombatService.CombatDamage) -- creator tags + line of sight

local SquadOrdersService = {}

local DataService: any = nil
local SoldierService: any = nil
local NotificationService: any = nil
local RateLimitService: any = nil
local RemoteSetup: any = nil
local AntiExploitService: any = nil
local VisualAssetService: any = nil
local BaseService: any = nil
local ResearchService: any = nil -- v69 research (deps.ResearchService)
local CombatService: any = nil -- F6 novice shield: an accepted order ends it (deps.CombatService; pcall'd)

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
	Crumb: number?, -- FollowPath: serial of the trail point this unit walks to while its slot is blocked
	CrumbScanAt: number, -- FollowPath: no full trail scan before this (a scan found nothing in sight)
	CrumbCheckAt: number, -- FollowPath: next check that the trail point is still in sight
}

-- FollowPath: the player's recent positions (newest last) with serials, so a unit keeps its place in the trail
type Trail = {
	Points: { Vector3 },
	Ids: { number },
	Serial: number,
}

type SquadState = {
	Order: OrderId,
	Units: { SquadUnit },
	DesiredCount: number,
	Mirror: boolean, -- lane C: wings swapped left <-> right (the player turned round; nobody crosses behind them)
}

local VALID: { [string]: boolean } = {
	Follow = true,
	Attack = true,
	Hold = true,
	Retreat = true,
}

local TAG_SQUAD = "WE_SquadUnit"
local squadByUser: { [number]: SquadState } = {}
local trailByUser: { [number]: Trail } = {}
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

local function researchMult(player: Player?, statId: string): number -- v69 research: ≥1, 1 when absent
	if player == nil or ResearchService == nil or ResearchService.GetBonus == nil then
		return 1
	end
	local ok, m = pcall(ResearchService.GetBonus, player, statId)
	if ok and typeof(m) == "number" and m == m and m >= 1 and m <= 5 then
		return m
	end
	return 1
end

local function researchAdd(player: Player?, statId: string): number -- v69 research: 0..10, 0 when absent
	if player == nil or ResearchService == nil or ResearchService.GetAdd == nil then
		return 0
	end
	local ok, a = pcall(ResearchService.GetAdd, player, statId)
	if ok and typeof(a) == "number" and a == a and a >= 0 and a <= 10 then
		return a
	end
	return 0
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
		MaxFieldUnits = (OrdersConfig.MaxFieldUnits or 5) + math.floor(researchAdd(player, "SquadSize")), -- v69 research
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

local function flatDist(a: Vector3, b: Vector3): number
	local d = a - b
	return Vector3.new(d.X, 0, d.Z).Magnitude
end

-- The old 3-wide grid, 6 / 9.5 / 13 studs straight behind the player (player-local: +X right, +Z behind)
local function gridOffset(slot: number): Vector3
	local spacing = OrdersConfig.FormationSpacing or 3.5
	local row = math.ceil(slot / 3)
	local col = ((slot - 1) % 3) - 1
	return Vector3.new(col * spacing, 0, 6 + (row - 1) * spacing)
end

local function followSlotList(): { any }?
	local slots = (OrdersConfig :: any).FollowSlots
	if typeof(slots) == "table" and #slots > 0 then
		return slots
	end
	return nil
end

-- Base identity lane C: slot n of OrdersConfig.FollowSlots (player-local studs: +X right, +Z BEHIND the player).
-- Slot #list+1.. (Squad Expansion research) repeats the list FollowRankStepZ further back per rank; an empty list
-- or a malformed entry falls back to the old grid.
local function formationOffset(slot: number): Vector3
	local slots = followSlotList()
	if slots then
		local n = #slots
		local s = slots[((slot - 1) % n) + 1]
		if typeof(s) == "table" and typeof(s.X) == "number" and typeof(s.Z) == "number" then
			local rank = math.floor((slot - 1) / n)
			local step = tonumber((OrdersConfig :: any).FollowRankStepZ) or 3.5
			return Vector3.new(s.X, 0, s.Z + rank * step)
		end
	end
	return gridOffset(slot)
end

-- The squad's current offset for a slot: FollowSlots mirrored left <-> right while st.Mirror is set
local function unitOffset(st: SquadState, slot: number): Vector3
	local off = formationOffset(slot)
	if st.Mirror then
		return Vector3.new(-off.X, off.Y, off.Z)
	end
	return off
end

-- Once per think pass (Follow): after the player turns round, the left wing is on the player's right. Swap the wings
-- when that is clearly shorter for the squad as a whole (FollowMirrorHysteresis studs per unit), so units walk to the
-- nearer side instead of all crossing behind the player. Distances only, no rays.
local function updateMirror(st: SquadState, playerCf: CFrame)
	if followSlotList() == nil then
		st.Mirror = false
		return
	end
	local keep, swap, n = 0, 0, 0
	for _, u in ipairs(st.Units) do
		if u.Alive and u.Root.Parent then
			local off = unitOffset(st, u.Slot)
			local at = u.Root.Position
			keep += flatDist(at, (playerCf * CFrame.new(off.X, 0, off.Z)).Position)
			swap += flatDist(at, (playerCf * CFrame.new(-off.X, 0, off.Z)).Position)
			n += 1
		end
	end
	if n > 0 and swap < keep - (tonumber((OrdersConfig :: any).FollowMirrorHysteresis) or 3) * n then
		st.Mirror = not st.Mirror
	end
end

-- ── FollowPath: walk the player's trail while the straight line to the slot is blocked ─────────────────────────
local function followPathCfg(): { [string]: any }?
	local cfg = (OrdersConfig :: any).FollowPath
	if typeof(cfg) == "table" and cfg.Enabled == true then
		return cfg
	end
	return nil
end

local function cfgNum(cfg: { [string]: any }, key: string, default: number): number
	local v = cfg[key]
	if typeof(v) == "number" and v == v then
		return v
	end
	return default
end

-- One trail point every CrumbSpacing studs the player moves on the ground (not mid-jump); a jump over ResetJump
-- (respawn, recall, fast vehicle) starts a new trail. Called once per think pass per player with a squad.
local function recordTrail(player: Player, root: BasePart, cfg: { [string]: any }): Trail
	local trail = trailByUser[player.UserId]
	if trail == nil then
		trail = { Points = {}, Ids = {}, Serial = 0 }
		trailByUser[player.UserId] = trail
	end
	local t = trail :: Trail
	local character = player.Character
	local hum = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if hum and hum.FloorMaterial == Enum.Material.Air then
		return t
	end
	local pos = root.Position
	local n = #t.Points
	if n > 0 then
		local d = (t.Points[n] - pos).Magnitude
		if d > cfgNum(cfg, "ResetJump", 40) then
			table.clear(t.Points)
			table.clear(t.Ids)
		elseif d < cfgNum(cfg, "CrumbSpacing", 3) then
			return t
		end
	end
	t.Serial += 1
	table.insert(t.Points, pos)
	table.insert(t.Ids, t.Serial)
	local maxN = math.max(2, math.floor(cfgNum(cfg, "MaxCrumbs", 12)))
	while #t.Points > maxN do
		table.remove(t.Points, 1)
		table.remove(t.Ids, 1)
	end
	return t
end

-- FollowPath probe: one RaycastParams per think pass (squads and every character ignored; only CanCollide geometry
-- blocks, a unit walks through the rest) + the ray height and the unit's half width from the config
type Probe = {
	Params: RaycastParams,
	Drop: number,
	Half: number,
}

local function buildProbe(cfg: { [string]: any }): Probe
	local ignore: { Instance } = { ensureFolder() }
	for _, p in ipairs(Players:GetPlayers()) do
		local character = p.Character
		if character then
			table.insert(ignore, character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	return { Params = params, Drop = cfgNum(cfg, "RayDrop", 1), Half = cfgNum(cfg, "RayHalfWidth", 0.9) }
end

-- Can a unit's body walk the straight line between two root positions and stand at the end? Two knee-to-waist rays
-- (RayDrop below the roots, so kerbs and pads never block) along its left and right edges (RayHalfWidth), each
-- RayHalfWidth past the end: a wall end that would catch a shoulder blocks, and so does a spot inside a wall.
local function bodyClear(from: Vector3, to: Vector3, probe: Probe): boolean
	local dir = to - from
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.5 then
		return true
	end
	local unitDir = flat.Unit
	local side = Vector3.new(-unitDir.Z, 0, unitDir.X) * probe.Half
	local reach = dir + unitDir * probe.Half
	local start = from - Vector3.new(0, probe.Drop, 0)
	return Workspace:Raycast(start + side, reach, probe.Params) == nil and Workspace:Raycast(start - side, reach, probe.Params) == nil
end

-- A slot inside, behind or too close to a wall beside the player (walking along a building, a wide lane): the spot
-- against that wall at the slot's own depth, WallGap short of it, when that still leaves MinSide studs between the
-- unit and the player's centre line. One lateral ray from the centre line, RayHalfWidth past the slot (the unit's
-- far shoulder). nil when the slot has room (something else cuts the unit off) or there is no room beside the player.
local function wallHugPoint(playerCf: CFrame, offset: Vector3, probe: Probe, cfg: { [string]: any }): Vector3?
	local ax = math.abs(offset.X)
	if ax < 0.5 then
		return nil
	end
	local origin = (playerCf * CFrame.new(0, 0, offset.Z)).Position - Vector3.new(0, probe.Drop, 0)
	local side = playerCf.RightVector * (if offset.X < 0 then -1 else 1)
	local hit = Workspace:Raycast(origin, side * (ax + probe.Half), probe.Params)
	if hit == nil then
		return nil
	end
	local x = math.min(ax, (hit.Position - origin).Magnitude - cfgNum(cfg, "WallGap", 1.5))
	if x < cfgNum(cfg, "MinSide", 3) then
		return nil
	end
	return (playerCf * CFrame.new(if offset.X < 0 then -x else x, 0, offset.Z)).Position
end

--[[ Where a Follow unit walks this think:
	1. its slot, when the unit is there or its body can walk straight to it;
	2. against the wall beside the player (wallHugPoint), when the slot is inside or behind that wall;
	2b. the slot squeezed SqueezeStuds nearer the player, when the slot is open but something is in the unit's way;
	3. the player's trail: the point it already walks to (the next one once within ReachStuds or once the next point
	   is walkable; at most 2 steps a think), or, with no place in the trail yet, the newest walkable point. Points
	   within StopGap of the player are skipped, so a cut-off unit stops behind the player instead of walking into
	   them. Every RescanSeconds it re-checks its point (it may have been pushed). Nothing walkable → the slot, as
	   before, and no new full scan for RescanSeconds.
	Rays per unit per think: 0 in its slot, 2 on the way to a slot it can reach, 5 against a wall or squeezed in,
	5-11 on the trail, up to 2 x MaxCrumbs more on a scan. ]]
local function followGoal(unit: SquadUnit, playerCf: CFrame, offset: Vector3, slotPos: Vector3, trail: Trail?, probe: Probe?, cfg: { [string]: any }?, now: number): Vector3
	if trail == nil or probe == nil or cfg == nil then
		unit.Crumb = nil
		return slotPos
	end
	local from = unit.Root.Position
	if flatDist(from, slotPos) <= (OrdersConfig.FollowArriveStuds or 2) or bodyClear(from, slotPos, probe) then
		unit.Crumb = nil
		return slotPos
	end
	local hug = wallHugPoint(playerCf, offset, probe, cfg)
	if hug and (flatDist(from, hug) <= (OrdersConfig.FollowArriveStuds or 2) or bodyClear(from, hug, probe)) then
		unit.Crumb = nil
		return hug
	end
	-- the slot is in the open but a wall end or a crate is in the unit's way: the same depth, SqueezeStuds nearer
	-- the player's centre line (never within MinSide of it)
	local minSide = cfgNum(cfg, "MinSide", 3)
	if hug == nil and math.abs(offset.X) > minSide then
		local x = math.max(minSide, math.abs(offset.X) - cfgNum(cfg, "SqueezeStuds", 2))
		local squeezed = (playerCf * CFrame.new(if offset.X < 0 then -x else x, 0, offset.Z)).Position
		if bodyClear(from, squeezed, probe) then
			unit.Crumb = nil
			return squeezed
		end
	end
	local pts, ids = trail.Points, trail.Ids
	local playerPos = playerCf.Position
	local gap = cfgNum(cfg, "StopGap", 4)
	local rescan = cfgNum(cfg, "RescanSeconds", 2)
	local last = #pts
	while last > 0 and flatDist(pts[last], playerPos) < gap do
		last -= 1
	end
	if last == 0 then
		unit.Crumb = nil
		return hug or slotPos
	end
	local idx: number? = nil
	local want = unit.Crumb
	if want then
		for i = 1, last do
			if ids[i] == want then
				idx = i
				break
			end
		end
	end
	local lost = want ~= nil and idx == nil -- evicted, or now within StopGap of the player: pick up the trail again
	if idx and now >= unit.CrumbCheckAt then
		unit.CrumbCheckAt = now + rescan
		if not bodyClear(from, pts[idx :: number], probe) then
			idx = nil
			lost = true
		end
	end
	if idx == nil then
		if not lost and now < unit.CrumbScanAt then
			return hug or slotPos
		end
		for i = last, 1, -1 do
			if bodyClear(from, pts[i], probe) then
				idx = i
				break
			end
		end
		if idx == nil then
			unit.Crumb = nil
			unit.CrumbScanAt = now + rescan
			return hug or slotPos
		end
		unit.CrumbCheckAt = now + rescan
	else
		local reach = cfgNum(cfg, "ReachStuds", 2.5)
		for _ = 1, 2 do
			local i = idx :: number
			if i >= last then
				break
			end
			if flatDist(pts[i], from) <= reach or bodyClear(from, pts[i + 1], probe) then
				idx = i + 1
			else
				break
			end
		end
	end
	local k = idx :: number
	unit.Crumb = ids[k]
	return pts[k]
end

local function spawnUnit(owner: Player, slot: number, at: CFrame): SquadUnit?
	unitSerial += 1
	local id = string.format("squad_%d_%d", owner.UserId, unitSerial)

	local model = Instance.new("Model")
	-- streaming2 S4 (F10): a squad soldier (root, welded kit, Humanoid, catalog visual) reaches a client whole or not at
	-- all. Set before the model is parented (it is filled first, parented below). No effect with streaming off.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
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
	-- base identity lane C: a domed helmet (SpecialMesh Sphere on the same part: 0 extra parts), was a flat box cap
	local helmet = weldPart("Helmet", Vector3.new(1.3, 0.75, 1.35), CFrame.new(0, 1.91, 0.02), Color3.fromRGB(55, 70, 45), Enum.Material.Metal, nil)
	local dome = Instance.new("SpecialMesh")
	dome.MeshType = Enum.MeshType.Sphere
	dome.Parent = helmet
	weldPart("Vest", Vector3.new(2.1, 1.2, 1.15), CFrame.new(0, 0.15, 0), olive, Enum.Material.Fabric, nil)
	weldPart("LegL", Vector3.new(1, 2, 1), CFrame.new(-0.5, -2, 0), olive, Enum.Material.Fabric, nil)
	weldPart("LegR", Vector3.new(1, 2, 1), CFrame.new(0.5, -2, 0), olive, Enum.Material.Fabric, nil)
	weldPart("ArmL", Vector3.new(1, 2, 1), CFrame.new(-1.5, 0, 0), olive, Enum.Material.Fabric, nil)
	weldPart("ArmR", Vector3.new(1, 2, 1), CFrame.new(1.5, 0, 0), olive, Enum.Material.Fabric, nil)
	weldPart("Rifle", Vector3.new(0.26, 0.26, 2.4), CFrame.new(1.15, 0.15, -0.85), Color3.fromRGB(28, 28, 30), Enum.Material.Metal, nil)

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = math.floor((OrdersConfig.UnitHealth or 90) * researchMult(owner, "SoldierHealth") + 0.5) -- v69 research
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = OrdersConfig.UnitWalkSpeed or 14
	humanoid.AutoRotate = true
	humanoid.HipHeight = 2
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.NameOcclusion = Enum.NameOcclusion.OccludeAll
	humanoid.Parent = model

	-- v68/v71: no floating "SQUAD" tag per soldier (a wall of labels over the squad — owner report; spec §5).
	-- OrdersConfig.ShowUnitLabels stays false; the order echo is flashOrderBillboard's one owner-only label.

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
		Crumb = nil,
		CrumbScanAt = 0,
		CrumbCheckAt = 0,
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

local function unitReady(unit: SquadUnit, now: number): boolean
	return now - unit.LastFireAt >= 1 / math.max(OrdersConfig.AttackFireRate or 1.8, 0.1)
end

-- One unit shot (Attack and escort). `credit`: the owner is tagged as creator first (unit flag), so a kill credits
-- the owner. Attack shots credit only with CombatFairnessConfig.UnitKillCreditOnAttack: Attack units roam without a
-- leash or line of sight, so an idle owner hidden near respawning NPCs would farm cash (verifier sim: bank guards).
local function unitShoot(player: Player, unit: SquadUnit, th: Humanoid, now: number, credit: boolean): boolean
	if not unitReady(unit, now) then
		return false
	end
	unit.LastFireAt = now
	if credit then
		CombatDamage.TagCreator(th, player, true)
	end
	th:TakeDamage((OrdersConfig.AttackDamage or 8) * researchMult(player, "SoldierDamage")) -- v69 research
	return true
end

-- Escort line of sight: the unit's squad, the owner and the target itself never block
local function escortHasLos(player: Player, unit: SquadUnit, troot: BasePart): boolean
	if not CombatFairnessConfig.EscortRequireLos then
		return true
	end
	local ignore: { Instance } = { unit.Model, ensureFolder() }
	local targetModel = troot.Parent
	if targetModel then
		table.insert(ignore, targetModel)
	end
	if player.Character then
		table.insert(ignore, player.Character :: Instance)
	end
	local eye = unit.Root.Position + Vector3.new(0, CombatFairnessConfig.NpcEyeHeight, 0)
	return CombatDamage.LineOfSight(eye, troot.Position, ignore, nil, CombatFairnessConfig.NpcLosRespectCanCollide)
end

--[[ P1-4 escort (order Follow): `th` / `troot` is the hostile nearest the PLAYER within EscortEngageRadius (picked
	once per think pass). The unit closes in only as far as the leash allows, drifts back when it is beyond the leash,
	and shoots when the hostile is within AttackRange with a clear line. Returns false when there is nothing to fight
	(the caller then runs the plain follow move). ]]
local function escortUnit(player: Player, st: SquadState, unit: SquadUnit, playerRoot: BasePart, th: Humanoid?, troot: BasePart?, now: number): boolean
	if th == nil or troot == nil or th.Health <= 0 or troot.Parent == nil then
		return false
	end
	local leash = CombatFairnessConfig.EscortLeash
	local range = OrdersConfig.AttackRange or 55
	local playerPos = playerRoot.Position
	local unitPos = unit.Root.Position
	local dist = (troot.Position - unitPos).Magnitude
	local fromPlayer = (unitPos - playerPos).Magnitude
	faceYaw(unit.Root, troot.Position)
	if fromPlayer > leash then
		-- back to the formation slot next to the player (still shooting on the way when possible)
		unit.Humanoid:MoveTo((playerRoot.CFrame * CFrame.new(unitOffset(st, unit.Slot))).Position)
	elseif dist > range * 0.85 then
		-- close in, but never past 90 % of the leash from the player
		local off = troot.Position - playerPos
		local maxOff = leash * 0.9
		local goal = if off.Magnitude > maxOff then playerPos + off.Unit * maxOff else troot.Position
		unit.Humanoid:MoveTo(goal)
	else
		unit.Humanoid:MoveTo(unitPos)
	end
	if dist <= range and unitReady(unit, now) and escortHasLos(player, unit, troot) then
		unitShoot(player, unit, th, now, true)
	end
	return true
end

local function thinkUnit(player: Player, st: SquadState, unit: SquadUnit, now: number, escortHum: Humanoid?, escortRoot: BasePart?, trail: Trail?, probe: Probe?)
	if not unit.Alive or unit.Humanoid.Health <= 0 or not unit.Root.Parent then
		return
	end
	local order = st.Order
	local playerRoot = characterRoot(player)

	if order == "Follow" then
		if not playerRoot then
			return
		end
		if escortUnit(player, st, unit, playerRoot, escortHum, escortRoot, now) then
			return
		end
		local offset = unitOffset(st, unit.Slot)
		local slotPos = (playerRoot.CFrame * CFrame.new(offset)).Position
		local target = followGoal(unit, playerRoot.CFrame, offset, slotPos, trail, probe, followPathCfg(), now)
		if followSlotList() == nil then
			-- old grid (FollowSlots empty): the original player-distance rules
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
		-- Follow slots sit 5.7-15.5 studs from the player, so arrival is measured to the slot: a unit walks facing
		-- where it goes and, once in its slot, stands facing where the player faces (the old "face the player
		-- beyond 10 studs" rule would crab-walk the outer wings sideways)
		local toGoal = flatDist(target, unit.Root.Position)
		if toGoal > (OrdersConfig.FollowArriveStuds or 2) then
			unit.Humanoid:MoveTo(target)
			if toGoal > 4 then
				faceYaw(unit.Root, target)
			end
		else
			unit.Humanoid:MoveTo(unit.Root.Position)
			faceYaw(unit.Root, unit.Root.Position + playerRoot.CFrame.LookVector * 8)
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
				if th and th.Health > 0 and dist <= range then
					unitShoot(player, unit, th, now, CombatFairnessConfig.UnitKillCreditOnAttack == true) -- P1-4
				end
			end
		elseif playerRoot then
			unit.Humanoid:MoveTo((playerRoot.CFrame * CFrame.new(0, 0, -12)).Position)
		end
		return
	end
end

-- lane C: a new unit appears in its slot; when a wall stands between the player and that slot (e.g. recruiting
-- inside the Barracks), at the old grid spot behind the player, else on the player's trail, else in the slot as before
local function spawnCFrame(player: Player, st: SquadState, root: BasePart?, baseCf: CFrame, slot: number): CFrame
	local lift = Vector3.new(0, 2, 0)
	local slotCf = baseCf * CFrame.new(unitOffset(st, slot)) + lift
	local cfg = followPathCfg()
	if root == nil or cfg == nil then
		return slotCf
	end
	local probe = buildProbe(cfg)
	local from = root.Position
	if bodyClear(from, slotCf.Position - lift, probe) then
		return slotCf
	end
	local gridCf = baseCf * CFrame.new(gridOffset(slot)) + lift
	if bodyClear(from, gridCf.Position - lift, probe) then
		return gridCf
	end
	local trail = trailByUser[player.UserId]
	if trail then
		local reset = cfgNum(cfg, "ResetJump", 40)
		for i = #trail.Points, 1, -1 do
			local pt = trail.Points[i]
			local d = flatDist(pt, from)
			if d >= 3 and d <= reset and bodyClear(from, pt, probe) then
				return baseCf.Rotation + pt + lift
			end
		end
	end
	return slotCf
end

function SquadOrdersService.SyncArmy(player: Player)
	if not OrdersConfig.Enabled then
		clearSquad(player.UserId)
		pushState(player)
		return
	end
	local soldiers = if SoldierService then SoldierService.GetCount(player) else 0
	local maxField = (OrdersConfig.MaxFieldUnits or 5) + math.floor(researchAdd(player, "SquadSize")) -- v69 research
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
			Mirror = false,
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
		-- lane C: drop the outermost slot, so the wings beside the player stay filled
		local worst = #st.Units
		for i, u in ipairs(st.Units) do
			if u.Slot > st.Units[worst].Slot then
				worst = i
			end
		end
		local u = table.remove(st.Units, worst)
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
		-- lane C: the lowest free slot (was #Units + 1, which doubled up a slot after a unit died)
		local used: { [number]: boolean } = {}
		for _, u in ipairs(st.Units) do
			used[u.Slot] = true
		end
		local slot = 1
		while used[slot] do
			slot += 1
		end
		local at = spawnCFrame(player, st, root, baseCf :: CFrame, slot)
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
	-- one owner-only order echo over the nearest unit ("FOLLOWING"), replaced by the next order, gone after `hold`
	for _, u in ipairs(st.Units) do
		local old = u.Root and u.Root:FindFirstChild("WE_OrderFlash")
		if old then
			old:Destroy()
		end
	end
	local bb = WorldLabel.Create(best.Root, textLabel, {
		Name = "WE_OrderFlash",
		Color = Color3.fromRGB(255, 230, 120),
		Studs = Vector2.new(5, 1.4),
		Offset = Vector3.new(0, 4.2, 0),
		MaxDistance = 40,
		OwnerUserId = player.UserId,
	})
	local hold = tonumber((OrdersConfig :: any).OrderBillboardSeconds) or 2.8
	local token = tostring(os.clock())
	best.Root:SetAttribute("WE_OrderFlash", token)
	task.delay(hold, function()
		if best and best.Root and best.Root.Parent and best.Root:GetAttribute("WE_OrderFlash") ~= token then
			return -- a newer order owns the flash
		end
		if bb.Parent then
			bb:Destroy()
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
	-- the order echo is this flash + the Army popover (no "Squad: X" toast per order — spec §4.2)
	flashOrderBillboard(player, st, order :: OrderId)
	-- F6 (owner's 11 features): an accepted order ends the novice shield for good (EndOnSquadOrder)
	if CombatService and CombatService.EndNoviceShield then
		pcall(CombatService.EndNoviceShield, player, "order")
	end
	return true, nil
end

function SquadOrdersService.Push(player: Player)
	pushState(player)
end

function SquadOrdersService.ApplyResearch(player: Player) -- v69 research: rescale living units' HP, add units
	local st = squadByUser[player.UserId]
	if st then
		local maxHp = math.floor((OrdersConfig.UnitHealth or 90) * researchMult(player, "SoldierHealth") + 0.5)
		for _, u in ipairs(st.Units) do
			if u.Alive and u.Humanoid.Health > 0 then
				local ratio = u.Humanoid.Health / math.max(u.Humanoid.MaxHealth, 1)
				u.Humanoid.MaxHealth = maxHp
				u.Humanoid.Health = math.max(1, ratio * maxHp)
			end
		end
	end
	SquadOrdersService.SyncArmy(player)
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
	ResearchService = deps.ResearchService -- v69 research
	CombatService = deps.CombatService -- F6 novice shield (Init order does not matter: used only on an order)

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
		trailByUser[player.UserId] = nil
	end)

	task.spawn(function()
		while true do
			local interval = OrdersConfig.ThinkInterval or 0.4
			task.wait(interval)
			local now = os.clock()
			local pathCfg = followPathCfg()
			local probe: Probe? = nil -- lane C FollowPath: built once per pass, only when a squad follows
			for _, player in ipairs(Players:GetPlayers()) do
				local st = squadByUser[player.UserId]
				local proot = characterRoot(player)
				local trail: Trail? = nil
				if proot and pathCfg then
					-- every player, every order: a switch to Follow and a recruit spawned indoors both find a trail
					trail = recordTrail(player, proot, pathCfg)
				end
				if st and #st.Units > 0 then
					-- P1-4 escort: one hostile pick per player per pass (nearest to the player)
					local escortHum: Humanoid?, escortRoot: BasePart? = nil, nil
					if st.Order == "Follow" and proot then
						escortHum, escortRoot = nearestHostile(proot.Position, CombatFairnessConfig.EscortEngageRadius)
						updateMirror(st, proot.CFrame)
						if pathCfg and probe == nil then
							probe = buildProbe(pathCfg)
						end
					end
					for _, unit in ipairs(st.Units) do
						thinkUnit(player, st, unit, now, escortHum, escortRoot, trail, probe)
					end
				end
			end
		end
	end)

	print("[WAR EMPIRE] SquadOrdersService ready (Follow = escort/Attack/Hold/Retreat)")
end

return SquadOrdersService
