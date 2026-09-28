--!strict
--[[
	Squad Orders — server-authoritative Follow / Attack / Hold / Retreat.
	Extends SoldierService counts + Combat MoveTo patterns. Not a second army economy.
	P1-4 (mobile plan): Follow is an escort — units shoot hostiles within CombatFairnessConfig.EscortEngageRadius of
	their player (line of sight required) while staying within EscortLeash of the player. An escort hit tags the owner
	as creator (unit flag), so escort kills credit the owner at UnitKillCashShare; an ATTACK hit does so only with
	CombatFairnessConfig.UnitKillCreditOnAttack (off: ATTACK kills pay nothing).
	v71 (HUD v70 spec §4.2 / §5): no per-unit "SQUAD" tags and no "Squad: X" toast per order — the order flashes
	for OrderBillboardSeconds as one owner-only stud-scaled WorldLabel over the nearest unit (flashOrderBillboard),
	and the Army popover shows the active order.
	Base identity lane C: Follow slots come from OrdersConfig.FollowSlots, two wings beside the player instead of rows
	straight behind (the old grid stood between the third-person camera and the player). A unit whose straight walk to
	its slot is blocked (door, narrow lane, stairs) walks the player's own trail (OrdersConfig.FollowPath) and fans back
	out once its slot is in sight. Helmets are domes (SpecialMesh Sphere on the same part: 0 extra parts).
	squadfair (CLAUDE.md combat fairness): every unit shot, ATTACK and escort, needs a line of sight (unitHasLos) and
	rolls a hit chance (unitHitChance, CombatFairnessConfig.Unit*; tests seed it with SetRandomForTests); a miss spends
	the fire cooldown. A hit goes through CombatService.ApplyUnitHit (the NPC damage path: creator tag, provoke, kill
	credit), so squad fire wakes passive bank guards and Ops garrisons, but only while the owner is near enough to be
	part of that fight (CombatService.UnitMayHitNPC). Units only target CombatService NPCs (a WE_NPC model with an
	NPCId): never a player, never a static statue. A unit whose nearest hostile is walled off shoots the nearest one
	in range it can see (pickShot, at most UnitLosRaysPerCheck rays); with nothing in sight an ATTACK unit closes in for
	at most UnitBlockedChaseSeconds (or walks at a hostile out of range until it stops getting nearer), then walks its
	owner's trail like FOLLOW, still shooting what it sees in range, until it gets a shot into that fight or the order is
	given again. A give-up holds for its own fight only (the hostiles within UnitGiveUpScopeStuds of where it happened):
	a hostile anywhere else in reach is still attacked, but the give-up does not restart the blocked timer, so a walled
	one elsewhere INSIDE the fire band is given up at its first check, with no new approach (on purpose: two spots are
	remembered, and a fresh approach there would let three walled spots take turns forever).
	A check that found nothing in sight is repeated at most once per shot cooldown (LosCheckAt). ATTACK units fire only
	inside 85 % of AttackRange, as before. The same order again within UnitRepeatOrderGraceSeconds changes nothing.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local OrdersConfig = require(Shared.Configs.OrdersConfig)
local RigConfig = require(Shared.Configs.RigConfig) -- R-RIG: escort figures per unit (army D14)
local CombatFairnessConfig = require(Shared.Configs.CombatFairnessConfig) -- P1-4 escort + kill credit
local WorldLabel = require(Shared.Util.WorldLabel)

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
	LosBlocked: boolean, -- squadfair: the last shot check found nothing in sight (an ATTACK unit closes in)
	LosCheckAt: number, -- squadfair: a check that found nothing in sight is not repeated before this (1 / AttackFireRate)
	BlockedSince: number?, -- squadfair: ATTACK: the first check of this spell with nothing in sight (the chase timeout)
	GiveUp: boolean, -- squadfair: ATTACK: its only fight in reach is one it gave up on: it walks its owner's trail
	GiveUpPos: Vector3?, -- squadfair 3.2: where the hostile of the last fight it gave up on stood (that fight = the
	-- hostiles within UnitGiveUpScopeStuds of it); kept until a shot into that fight or a new order
	GiveUpPos2: Vector3?, -- ...and of the fight before that one (two walled spots never take turns)
	ChaseBest: number?, -- squadfair: ATTACK: the nearest it has come to a target out of range during this approach
	ChaseAt: number, -- ...and when it last came UnitChaseProgressStuds nearer (the no-progress timeout)
	AimRoot: BasePart?, -- squadfair: the fallback hostile this unit last shot at (it faces it between shots)
	AimHum: Humanoid?, -- ...and its Humanoid (a dead one is let go)
	ChaseHum: Humanoid?, -- squadfair: ATTACK: the hostile it chases (the nearest); another one beyond the band = a fresh blocked spell
}

-- squadfair: up to `cap` hostiles, nearest first (the visible-target fallback). Refilled in place: no table per think.
type CandList = {
	Hum: { Humanoid },
	Root: { BasePart },
	Dist: { number },
	N: number,
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
	OrderAt: number?, -- squadfair: when the current order was last given (UnitRepeatOrderGraceSeconds)
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
local rng = Random.new() -- squadfair: the unit hit roll (tests seed it with SquadOrdersService.SetRandomForTests)
local escortCands: CandList = { Hum = {}, Root = {}, Dist = {}, N = 0 } -- squadfair: per player per pass (escort)
local attackCands: CandList = { Hum = {}, Root = {}, Dist = {}, N = 0 } -- squadfair: per ATTACK unit per think
-- squadfair: one RaycastParams for every unit line-of-sight ray, its ignore list refilled per ray (no RaycastParams
-- and no table per ray); the rules of CombatDamage.LineOfSight: Exclude, water ignored, NpcLosRespectCanCollide
local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
losParams.IgnoreWater = true
local losIgnore: { Instance } = {}
local npcBodyFolder: Instance? = nil -- squadfair: CombatService's NPC folder (CombatFairnessConfig.UnitLosIgnoreNPCBodies)
local hitErrLogAt = -math.huge -- squadfair: the last ApplyUnitHit error warning (UnitHitErrorLogSeconds)
local hitErrMuted = 0 -- ...and the errors not logged since

-- squadfair: the folder CombatService keeps every NPC model in (nil until the first NPC spawns); cached
local function npcBodies(): Instance?
	if npcBodyFolder and npcBodyFolder.Parent then
		return npcBodyFolder
	end
	npcBodyFolder = Workspace:FindFirstChild("WarEmpireNPCs")
	return npcBodyFolder
end

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
		LosBlocked = false,
		LosCheckAt = 0,
		BlockedSince = nil,
		GiveUp = false,
		GiveUpPos = nil,
		GiveUpPos2 = nil,
		ChaseBest = nil,
		ChaseAt = 0,
		AimRoot = nil,
		AimHum = nil,
		ChaseHum = nil,
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

-- squadfair: line-of-sight rays one unit may cast per check (UnitLosRaysPerCheck: the nearest hostile first, then the
-- next nearest ones in range)
local function losRayCap(): number
	return math.clamp(math.floor(tonumber(CombatFairnessConfig.UnitLosRaysPerCheck) or 1), 1, 4)
end

-- squadfair: a candidate list holds the nearest few hostiles (enough for losRayCap() rays after skipping the nearest
-- one and any out of the unit's range)
local function candCap(): number
	return 2 * losRayCap() + 1
end

local function candReset(list: CandList)
	table.clear(list.Hum)
	table.clear(list.Root)
	table.clear(list.Dist)
	list.N = 0
end

-- keep the `cap` nearest, sorted nearest first (insertion into a list of at most 9)
local function candInsert(list: CandList, cap: number, hum: Humanoid, root: BasePart, d: number)
	local n = list.N
	if n >= cap then
		if d >= list.Dist[n] then
			return
		end
		n -= 1 -- the furthest one drops out
	end
	local i = n + 1
	while i > 1 and list.Dist[i - 1] > d do
		list.Hum[i] = list.Hum[i - 1]
		list.Root[i] = list.Root[i - 1]
		list.Dist[i] = list.Dist[i - 1]
		i -= 1
	end
	list.Hum[i] = hum
	list.Root[i] = root
	list.Dist[i] = d
	list.N = n + 1
end

-- squadfair 3.2: is `pos` within `r` of spot `a` or spot `b` (a fight an ATTACK unit gave up on)?
local function nearSpot(pos: Vector3, a: Vector3?, b: Vector3?, r: number): boolean
	return (a ~= nil and (pos - a).Magnitude <= r) or (b ~= nil and (pos - b).Magnitude <= r)
end

--[[ The hostile nearest `fromPos` within `maxRange`. `skipCalm` (squadfair, FOLLOW escort with
	CombatFairnessConfig.EscortIgnoreCalm): leave out NPCs that hold fire now (CombatService.NPCHoldsFire: a Passive /
	passive-group NPC whose group is not provoked). `owner` (squadfair): leave out NPCs this owner's squad may not hurt
	(CombatService.UnitMayHitNPC false: a calm NPC whose owner is not near enough to be part of the fight; the pick only
	saves shots, CombatService.ApplyUnitHit enforces the rule). `list`: also the hostiles within `listRange`, nearest first
	(at most candCap()), for the visible-target fallback. squadfair 3.2 (ATTACK): a hostile within `avoidR` of `avoidA` or
	`avoidB` (the fights this unit gave up on) is never the first result; the nearest such one comes back as the second
	(its Humanoid, root and distance after the first three). It still goes into `list`. The last two results say
	whether any live hostile, however far from `fromPos`, still stands within `avoidR` of `avoidA` / `avoidB`. ]]
local function nearestHostile(fromPos: Vector3, maxRange: number, skipCalm: boolean?, owner: Player?, list: CandList?, listRange: number?, avoidA: Vector3?, avoidB: Vector3?, avoidR: number?): (Humanoid?, BasePart?, number, Humanoid?, BasePart?, number, boolean, boolean)
	local bestHum: Humanoid? = nil
	local bestRoot: BasePart? = nil
	local bestDist = maxRange
	local avoiding = avoidR ~= nil and (avoidA ~= nil or avoidB ~= nil)
	local zoneHum: Humanoid? = nil
	local zoneRoot: BasePart? = nil
	local zoneDist = if avoiding then maxRange else 0
	local heldA, heldB = false, false
	local npcTag = Constants.Tags.NPC
	local holds = if skipCalm == true and CombatService then CombatService.NPCHoldsFire else nil
	if typeof(holds) ~= "function" then
		holds = nil
	end
	local mayHit = if owner ~= nil and CombatService then CombatService.UnitMayHitNPC else nil
	if typeof(mayHit) ~= "function" then
		mayHit = nil
	end
	local lr = if list then (listRange or maxRange) else -1
	local cap = candCap()
	if list then
		candReset(list)
	end
	for _, inst in ipairs(CollectionService:GetTagged(npcTag)) do
		-- squadfair: a CombatService NPC only (it has an NPCId); a static WE_NPC statue takes no damage from any shot
		if
			inst:IsA("Model")
			and not inst:GetAttribute("FriendlySquad")
			and not inst:GetAttribute("OwnerUserId")
			and typeof(inst:GetAttribute("NPCId")) == "string"
		then
			local hum = inst:FindFirstChildOfClass("Humanoid")
			local root = inst:FindFirstChild("HumanoidRootPart")
			if hum and root and root:IsA("BasePart") and hum.Health > 0 then
				local p = root.Position
				local inA = avoidA ~= nil and avoidR ~= nil and (p - avoidA).Magnitude <= avoidR
				local inB = avoidB ~= nil and avoidR ~= nil and (p - avoidB).Magnitude <= avoidR
				heldA = heldA or inA
				heldB = heldB or inB
				local d = (p - fromPos).Magnitude
				if d < bestDist or d < zoneDist or d <= lr then
					local id = inst:GetAttribute("NPCId")
					if not (holds ~= nil and holds(id) == true) and not (mayHit ~= nil and mayHit(owner, id) == false) then
						if inA or inB then
							if d < zoneDist then
								zoneDist = d
								zoneHum = hum
								zoneRoot = root
							end
						elseif d < bestDist then
							bestDist = d
							bestHum = hum
							bestRoot = root
						end
						if list and d <= lr then
							candInsert(list, cap, hum, root, d)
						end
					end
				end
			end
		end
	end
	return bestHum, bestRoot, bestDist, zoneHum, zoneRoot, zoneDist, heldA, heldB
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

-- squadfair: the unit hit chance at `dist` studs: UnitNearHitChance up to UnitNearStuds, falling linearly to
-- UnitFarHitChance at OrdersConfig.AttackRange, never below UnitMinHitChance (the CombatNPC.HitChance curve, squad keys)
-- and never above UnitMaxHitChance (itself never above 0.99: a squad shot can always miss, whatever the config says)
local function unitHitChance(dist: number): number
	local C = CombatFairnessConfig
	local maxRange = OrdersConfig.AttackRange or 55
	local nearD = C.UnitNearStuds
	local chance: number
	if dist <= nearD or maxRange <= nearD then
		chance = C.UnitNearHitChance
	else
		local t = math.clamp((dist - nearD) / (maxRange - nearD), 0, 1)
		chance = C.UnitNearHitChance + (C.UnitFarHitChance - C.UnitNearHitChance) * t
	end
	local hi = math.min(tonumber(C.UnitMaxHitChance) or 0.95, 0.99)
	local lo = math.min(tonumber(C.UnitMinHitChance) or 0.05, hi)
	return math.clamp(chance, lo, hi)
end

-- Tests seed the unit hit roll; production never calls this and uses an unseeded Random (CombatNPC.SetRandom pattern)
function SquadOrdersService.SetRandomForTests(seedOrRandom: any)
	if typeof(seedOrRandom) == "Random" then
		rng = seedOrRandom
	elseif typeof(seedOrRandom) == "number" then
		rng = Random.new(seedOrRandom)
	else
		rng = Random.new()
	end
end

--[[ One unit shot (Attack and escort); the caller has checked the line of sight. The shot spends the fire cooldown,
	then rolls unitHitChance at the target's distance (squadfair: a miss spends it too). A hit goes through
	CombatService.ApplyUnitHit, the NPC damage path (provokes a Passive / grouped NPC; never a player). `credit`: the
	owner is tagged as creator (unit flag), so a kill credits the owner. Attack shots credit only with
	CombatFairnessConfig.UnitKillCreditOnAttack: Attack units roam without a leash, so an idle owner hidden near
	respawning NPCs would farm cash (verifier sim: bank guards). No CombatService = no damage. An ApplyUnitHit error
	deals nothing and is logged at most once per UnitHitErrorLogSeconds (the rest are counted). Returns true on a hit. ]]
local function unitShoot(player: Player, unit: SquadUnit, th: Humanoid, now: number, credit: boolean): boolean
	if not unitReady(unit, now) then
		return false
	end
	local model = th.Parent
	local troot = if model then model:FindFirstChild("HumanoidRootPart") else nil
	if troot == nil or not troot:IsA("BasePart") then
		return false
	end
	unit.LastFireAt = now -- a miss spends the cooldown like a hit
	if rng:NextNumber() >= unitHitChance((troot.Position - unit.Root.Position).Magnitude) then
		return false
	end
	local apply = if CombatService then CombatService.ApplyUnitHit else nil
	if typeof(apply) ~= "function" then
		return false
	end
	local ok, dealt = pcall(apply, player, th, (OrdersConfig.AttackDamage or 8) * researchMult(player, "SoldierDamage"), credit) -- v69 research
	if not ok then
		-- squadfair: never silent (every squad would deal 0 damage), never a log flood (one line per UnitHitErrorLogSeconds)
		if now - hitErrLogAt >= (tonumber(CombatFairnessConfig.UnitHitErrorLogSeconds) or 30) then
			warn(string.format("[WAR EMPIRE] SquadOrdersService: CombatService.ApplyUnitHit failed (%d more since the last warning): %s", hitErrMuted, tostring(dealt)))
			hitErrLogAt = now
			hitErrMuted = 0
		else
			hitErrMuted += 1
		end
		return false
	end
	return typeof(dealt) == "number" and dealt > 0
end

-- Unit line of sight (escort and, squadfair, ATTACK): a ray from the unit's eyes to the target root; the squads, the
-- owner and the target itself never block, nor (UnitLosIgnoreNPCBodies) another NPC's body: two hostiles standing
-- close must not hide each other from the squad (each blocked the ray to the other and the squad stopped shooting).
-- The rules of CombatDamage.LineOfSight with no target (nothing may be hit; Exclude, water ignored, non-collidable
-- decor per NpcLosRespectCanCollide), cast here with the one cached losParams and its reused ignore list (squadfair:
-- no RaycastParams and no table per ray)
local function unitHasLos(player: Player, unit: SquadUnit, troot: BasePart): boolean
	local eye = unit.Root.Position + Vector3.new(0, CombatFairnessConfig.NpcEyeHeight, 0)
	local delta = troot.Position - eye
	if delta.Magnitude < 1e-3 then
		return true
	end
	table.clear(losIgnore)
	table.insert(losIgnore, unit.Model)
	table.insert(losIgnore, ensureFolder())
	if CombatFairnessConfig.UnitLosIgnoreNPCBodies == true then
		local bodies = npcBodies()
		if bodies then
			table.insert(losIgnore, bodies)
		end
	end
	local targetModel = troot.Parent
	if targetModel then
		table.insert(losIgnore, targetModel)
	end
	if player.Character then
		table.insert(losIgnore, player.Character :: Instance)
	end
	losParams.RespectCanCollide = CombatFairnessConfig.NpcLosRespectCanCollide == true
	losParams.FilterDescendantsInstances = losIgnore -- the property takes a copy of the list
	local blocked = Workspace:Raycast(eye, delta, losParams) ~= nil
	table.clear(losIgnore) -- the Lua list holds no model between checks (the next ray's list replaces the property's)
	return not blocked
end

--[[ squadfair: the shot a ready unit takes now. The primary hostile `th` when it is within `range` of the unit and
	(with `requireLos`) in sight; else, with `requireLos`, the nearest hostile of `list` (not `th`) within `range` of the
	unit that it can see, nearest first, casting at most UnitLosRaysPerCheck rays in all. Returns (hostile, root, rays
	cast); no hostile = nothing to shoot now (rays 0: nothing was in range to check). ]]
local function pickShot(player: Player, unit: SquadUnit, th: Humanoid, troot: BasePart, range: number, list: CandList, requireLos: boolean): (Humanoid?, BasePart?, number)
	local from = unit.Root.Position
	local inRange = (troot.Position - from).Magnitude <= range
	if not requireLos then
		if inRange then
			return th, troot, 0
		end
		return nil, nil, 0
	end
	local cap = losRayCap()
	local rays = 0
	if inRange then
		rays = 1
		if unitHasLos(player, unit, troot) then
			return th, troot, rays
		end
	end
	for i = 1, list.N do
		if rays >= cap then
			break
		end
		local h, r = list.Hum[i], list.Root[i]
		if h ~= th and h.Health > 0 and r.Parent ~= nil and (r.Position - from).Magnitude <= range then
			rays += 1
			if unitHasLos(player, unit, r) then
				return h, r, rays
			end
		end
	end
	return nil, nil, rays
end

-- squadfair: a shot check is due: the gun is ready, and a check that found nothing in sight waits one shot cooldown
local function losCheckDue(unit: SquadUnit, now: number): boolean
	return unitReady(unit, now) and now >= unit.LosCheckAt
end

-- squadfair: a check cast rays and found nothing in sight: the next one waits 1 / AttackFireRate
local function losBlockedFor(unit: SquadUnit, now: number)
	unit.LosCheckAt = now + 1 / math.max(OrdersConfig.AttackFireRate or 1.8, 0.1)
	unit.LosBlocked = true
	unit.AimRoot = nil
	unit.AimHum = nil
end

-- squadfair: where a unit looks while it fights: the fallback hostile it last shot at, while that one stands, else `troot`
local function aimPoint(unit: SquadUnit, troot: BasePart): Vector3
	local a, h = unit.AimRoot, unit.AimHum
	if a ~= nil and a.Parent ~= nil and h ~= nil and h.Health > 0 then
		return a.Position
	end
	unit.AimRoot = nil
	unit.AimHum = nil
	return troot.Position
end

-- squadfair: an ATTACK unit's blocked-chase timers start over (a shot, no hostile in reach, a new order)
local function clearChase(unit: SquadUnit)
	unit.LosBlocked = false
	unit.BlockedSince = nil
	unit.ChaseBest = nil
	unit.ChaseAt = 0
	unit.ChaseHum = nil
end

-- squadfair: ...and the fights it gave up on are forgotten (a shot into one of them, a new order)
local function resetChase(unit: SquadUnit)
	clearChase(unit)
	unit.GiveUp = false
	unit.GiveUpPos = nil
	unit.GiveUpPos2 = nil
end

--[[ P1-4 escort (order Follow): `th` / `troot` is the hostile nearest the PLAYER within EscortEngageRadius (picked
	once per think pass). The unit closes in only as far as the leash allows, drifts back when it is beyond the leash,
	and shoots when the hostile is within AttackRange with a clear line. squadfair: when this unit cannot shoot it (out
	of range or walled off), it shoots the next hostile near the player (escortCands, nearest to the player first) that
	is within its range and in sight (pickShot), and closes in on that one instead of walking at the walled-off one
	(same leash). Returns false when there is nothing to fight (the caller then runs the plain follow move). ]]
local function escortUnit(player: Player, st: SquadState, unit: SquadUnit, playerRoot: BasePart, th: Humanoid?, troot: BasePart?, now: number): boolean
	if th == nil or troot == nil or th.Health <= 0 or troot.Parent == nil then
		unit.AimRoot = nil
		unit.AimHum = nil
		return false
	end
	local leash = CombatFairnessConfig.EscortLeash
	local range = OrdersConfig.AttackRange or 55
	local playerPos = playerRoot.Position
	local unitPos = unit.Root.Position
	local fromPlayer = (unitPos - playerPos).Magnitude
	-- squadfair: the shot first (the unit faces what it shoots), then the escort's walk as before
	if losCheckDue(unit, now) then
		local sh, sr, rays = pickShot(player, unit, th, troot, range, escortCands, CombatFairnessConfig.EscortRequireLos == true)
		if sh and sr then
			unit.LosBlocked = false
			unit.AimRoot = if sh ~= th then sr else nil
			unit.AimHum = if sh ~= th then sh else nil
			unitShoot(player, unit, sh, now, true)
		elseif rays > 0 then
			losBlockedFor(unit, now)
		end
	end
	local aimAt = aimPoint(unit, troot) -- the fallback hostile it shoots, else the one nearest the player
	local dist = (aimAt - unitPos).Magnitude
	faceYaw(unit.Root, aimAt)
	if fromPlayer > leash then
		-- back to the formation slot next to the player (still shooting on the way when possible)
		unit.Humanoid:MoveTo((playerRoot.CFrame * CFrame.new(unitOffset(st, unit.Slot))).Position)
	elseif dist > range * 0.85 then
		-- close in, but never past 90 % of the leash from the player
		local off = aimAt - playerPos
		local maxOff = leash * 0.9
		local goal = if off.Magnitude > maxOff then playerPos + off.Unit * maxOff else aimAt
		unit.Humanoid:MoveTo(goal)
	else
		unit.Humanoid:MoveTo(unitPos)
	end
	return true
end

-- The plain FOLLOW walk: the unit's slot beside the player, or the player's trail when the slot is cut off
-- (followGoal). squadfair: also an ATTACK unit that gave up a blocked chase (UnitBlockedChaseSeconds).
local function followMove(st: SquadState, unit: SquadUnit, playerRoot: BasePart, trail: Trail?, probe: Probe?, now: number)
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
end

-- squadfair 3.2: how far from where a unit gave up a hostile may stand and still belong to that fight
-- (UnitGiveUpScopeStuds; 0 or less = every hostile does: a give-up holds until a shot or a new order, the round-3 rule)
local function giveUpScope(): number
	local s = tonumber(CombatFairnessConfig.UnitGiveUpScopeStuds) or 30
	return if s > 0 then s else math.huge
end

-- squadfair 3.2: the unit gives up the fight around `at` (and keeps the one before it)
local function giveUpFight(unit: SquadUnit, at: Vector3)
	unit.GiveUpPos2 = unit.GiveUpPos
	unit.GiveUpPos = at
	unit.GiveUp = true
end

-- squadfair: has any unit of this squad given up a chase (it walks the owner's trail and needs the FollowPath probe)?
local function anyGaveUp(st: SquadState): boolean
	for _, u in ipairs(st.Units) do
		if u.GiveUp then
			return true
		end
	end
	return false
end

--[[ squadfair: one ATTACK unit's think. The hostile nearest the unit within AttackAggroRange that this squad may hurt
	(nearestHostile with the owner) is its target. When the gun is ready it shoots that one if it is within the fire
	band (85 % of AttackRange, as before) and in sight, else the nearest one in the band it can see (pickShot). It
	walks at its target while that is beyond the band, and keeps closing in while nothing is in sight
	(UnitChaseWithoutLos). It gives up after UnitBlockedChaseSeconds with nothing in sight, or with no
	UnitChaseProgressStuds gained on a target out of the band, and then walks its owner's trail like FOLLOW (still
	shooting what it can see in the band) until it gets a shot or the order is given again. The blocked timer counts
	only checks that had something in the band to look at: a check with nothing in the band (the unit is walking in),
	and another hostile beyond the band becoming its target (the old one down, gone, out of reach or no longer the
	nearest), start it over; a swap between hostiles in the band keeps it running (nothing in the band is in sight
	either way). squadfair 3.2: a give-up holds for the fight where it happened only (the hostiles within
	UnitGiveUpScopeStuds of the spot; the last two spots are kept): its target is the nearest hostile outside those
	fights, so another group, or the walled one once it walks out, is attacked as usual; only when nothing else is in
	reach does it stay given up. A shot into a fight it gave up on ends those give-ups; a new order ends them too; a
	given-up fight with no hostile left in it is forgotten. The give-up does NOT restart the blocked timer (round 3.3,
	deliberate): after a give-up, a new target beyond the band gets a fresh approach, but a walled one inside the band
	is given up at its first blocked check, with no approach, until the timer starts over (a shot, a check with nothing
	in the band, nothing in reach, a target beyond the band, a new order). Only two spots are remembered, so a fresh
	approach inside the band would let three or more walled spots take turns forever (reviewer S1 / S2). ]]
local function attackUnit(player: Player, st: SquadState, unit: SquadUnit, playerRoot: BasePart?, now: number, trail: Trail?, probe: Probe?)
	local aggro = OrdersConfig.AttackAggroRange or 120
	local band = (OrdersConfig.AttackRange or 55) * 0.85 -- HEAD's ATTACK fire band: it fires only once this close
	local scope = giveUpScope()
	-- squadfair 3.2: `nh` is the nearest hostile outside the fights this unit gave up on, `zh` the nearest inside one
	local nh, nroot, dist, zh, zroot, zdist, heldA, heldB = nearestHostile(unit.Root.Position, aggro, false, player, attackCands, band, unit.GiveUpPos, unit.GiveUpPos2, scope)
	-- a given-up fight with no hostile left in it (all down or gone) is forgotten: whoever comes there later is new
	if unit.GiveUpPos2 ~= nil and not heldB then
		unit.GiveUpPos2 = nil
	end
	if unit.GiveUpPos ~= nil and not heldA then
		unit.GiveUpPos = unit.GiveUpPos2
		unit.GiveUpPos2 = nil
	end
	-- only a fight it gave up on is in reach: that fight's nearest hostile stays its target and it stays given up
	local givenUp = nh == nil and zh ~= nil
	if givenUp then
		nh, nroot, dist = zh, zroot, zdist
	end
	if nh == nil or nroot == nil then
		candReset(attackCands)
		-- nothing in reach: the fights it gave up on are kept (no walk back to the same wall once it is in reach again)
		clearChase(unit)
		unit.GiveUp = false
		unit.AimRoot = nil
		unit.AimHum = nil
		if playerRoot then
			unit.Humanoid:MoveTo((playerRoot.CFrame * CFrame.new(0, 0, -12)).Position)
		end
		return
	end
	if unit.GiveUp and not givenUp then
		-- it leaves a given-up fight for a hostile elsewhere. Not a fresh start: beyond the band the ChaseHum change below
		-- restarts the blocked timer (a fresh approach), but inside the band the timer keeps running from the give-up, so
		-- a walled newcomer there is given up at its first blocked check, with no approach. Deliberate: a fresh approach
		-- here would let three walled spots take turns (only two are remembered)
		unit.ChaseHum = nil
	end
	unit.GiveUp = givenUp
	-- squadfair: another hostile is the nearest now (the one it chased is down, gone, out of reach or no longer the
	-- nearest): a fresh approach, and a fresh blocked spell when it stands beyond the band (no stale give-up timer
	-- from the old target). A swap between hostiles in the band keeps the blocked timer (3.2: nearest swaps along a
	-- wall must not keep a unit pressed on it)
	if unit.ChaseHum ~= nh then
		if dist > band then
			unit.BlockedSince = nil
		end
		unit.ChaseBest = nil
		unit.ChaseHum = nh
	end
	-- squadfair: a shot needs a clear line (UnitAttackRequireLos, the escort's ray); checked when the gun is ready
	if losCheckDue(unit, now) then
		-- `th`: the hostile it shoots now (the nearest one, or the nearest one in the band it can see)
		local th, troot, rays = pickShot(player, unit, nh, nroot, band, attackCands, CombatFairnessConfig.UnitAttackRequireLos == true)
		if th and troot then
			-- squadfair 3.2: a shot into a fight it gave up on ends those give-ups (from here nothing blocks that fight);
			-- a shot elsewhere keeps them (no walk back to the old wall)
			if nearSpot(troot.Position, unit.GiveUpPos, unit.GiveUpPos2, scope) then
				resetChase(unit)
			else
				clearChase(unit)
			end
			unit.ChaseHum = nh
			unit.AimRoot = if th ~= nh then troot else nil
			unit.AimHum = if th ~= nh then th else nil
			unitShoot(player, unit, th, now, CombatFairnessConfig.UnitKillCreditOnAttack == true) -- P1-4
		elseif rays > 0 then
			losBlockedFor(unit, now)
			if unit.BlockedSince == nil then
				unit.BlockedSince = now
			end
		else
			unit.BlockedSince = nil -- nothing in the band to check (it is walking in): no stale blocked timer
		end
	end
	candReset(attackCands) -- hold no reference to the NPCs between thinks
	local giveUpAfter = tonumber(CombatFairnessConfig.UnitBlockedChaseSeconds) or math.huge
	if not unit.GiveUp then
		local since = unit.BlockedSince
		if since ~= nil and now - since >= giveUpAfter then
			giveUpFight(unit, nroot.Position) -- nothing in sight for UnitBlockedChaseSeconds
		elseif dist > band then
			local best = unit.ChaseBest
			if best == nil or dist <= best - (tonumber(CombatFairnessConfig.UnitChaseProgressStuds) or 2) then
				unit.ChaseBest = dist
				unit.ChaseAt = now
			elseif now - unit.ChaseAt >= giveUpAfter then
				giveUpFight(unit, nroot.Position) -- no nearer in UnitBlockedChaseSeconds: something is in its way
			end
		else
			unit.ChaseBest = nil
		end
	end
	if unit.GiveUp then
		-- squadfair: no pressing on a wall; back to the owner's trail until a shot into that fight, a hostile elsewhere
		-- or a new order
		unit.AimRoot = nil
		unit.AimHum = nil
		if playerRoot then
			followMove(st, unit, playerRoot, trail, probe, now)
		else
			unit.Humanoid:MoveTo(unit.Root.Position)
		end
		return
	end
	local aimAt = aimPoint(unit, nroot)
	faceYaw(unit.Root, aimAt)
	if unit.AimRoot ~= nil then
		-- squadfair: it shoots a visible hostile (the fallback): it closes in on that one only, never on the walled-off one
		if (aimAt - unit.Root.Position).Magnitude > band then
			unit.Humanoid:MoveTo(aimAt)
		else
			unit.Humanoid:MoveTo(unit.Root.Position)
		end
	elseif dist > band then
		unit.Humanoid:MoveTo(nroot.Position)
	elseif unit.LosBlocked and CombatFairnessConfig.UnitChaseWithoutLos == true then
		unit.Humanoid:MoveTo(nroot.Position) -- no clear shot: keep closing in (NPC rule), until it gives up
	else
		unit.Humanoid:MoveTo(unit.Root.Position)
	end
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
		followMove(st, unit, playerRoot, trail, probe, now)
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
		attackUnit(player, st, unit, playerRoot, now, trail, probe)
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

	-- R-RIG (army D14): escort figures per unit (built only by clients, inside their own budget). Units in slot order
	-- share RigConfig.EscortsFor(soldiers, units, Barracks), front pair first; an unchanged value does not replicate
	-- again. Only with FollowSlots (wings): escorts stand ahead of wing units; the old centre grid would put them in
	-- front of the player's view.
	if RigConfig.Enabled == true then
		local profile = DataService and DataService.GetProfile(player)
		local upgrades = if profile then profile.BaseUpgrades else nil
		local barracks = if typeof(upgrades) == "table" then tonumber(upgrades.Barracks) or 0 else 0
		local escorts = if followSlotList() ~= nil then RigConfig.EscortsFor(soldiers, #st.Units, barracks) else 0
		for _, u in ipairs(st.Units) do
			local rank = 1
			for _, o in ipairs(st.Units) do
				if o.Slot < u.Slot then
					rank += 1
				end
			end
			u.Model:SetAttribute("WE_Escorts", RigConfig.EscortShare(escorts, #st.Units, rank))
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

	-- squadfair: the same order again soon after (a double tap, a spammed button) is not a new order: the blocked
	-- re-check wait, the chase timers and a give-up stay (UnitRepeatOrderGraceSeconds)
	local now = os.clock()
	local repeatOrder = order == st.Order
		and st.OrderAt ~= nil
		and now - (st.OrderAt :: number) < (tonumber(CombatFairnessConfig.UnitRepeatOrderGraceSeconds) or 0)
	st.OrderAt = now
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
	for _, u in ipairs(st.Units) do
		-- squadfair: a blocked line is never re-checked early (not even by a new order: at most one check per cooldown)
		u.LosCheckAt = math.max(u.LosCheckAt, now)
		if not repeatOrder then
			resetChase(u) -- a new order (or ATTACK again after the grace) starts with no stale chase / given-up state
			u.AimRoot = nil
			u.AimHum = nil
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
					-- P1-4 escort: one hostile pick per player per pass (nearest to the player); squadfair: plus the
					-- hostiles near the player for the visible-target fallback (escortCands), only ones this squad may hurt
					local escortHum: Humanoid?, escortRoot: BasePart? = nil, nil
					if st.Order == "Follow" and proot then
						local r = CombatFairnessConfig.EscortEngageRadius
						escortHum, escortRoot = nearestHostile(proot.Position, r, CombatFairnessConfig.EscortIgnoreCalm == true, player, escortCands, r)
						updateMirror(st, proot.CFrame)
					end
					-- lane C FollowPath (squadfair: also ATTACK once a unit has given up a chase: it walks the trail)
					if (st.Order == "Follow" or (st.Order == "Attack" and anyGaveUp(st))) and proot and pathCfg and probe == nil then
						probe = buildProbe(pathCfg)
					end
					for _, unit in ipairs(st.Units) do
						thinkUnit(player, st, unit, now, escortHum, escortRoot, trail, probe)
					end
					candReset(escortCands) -- hold no reference to the NPCs between passes
				end
			end
		end
	end)

	print("[WAR EMPIRE] SquadOrdersService ready (Follow = escort/Attack/Hold/Retreat)")
end

return SquadOrdersService
