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
	Army fix (ArmyConfig.Follow / Recover / Gate): a FOLLOW unit aims at its slot where the player will be at the next
	think (Follow.Lead) and walks at the player's pace, faster while it is behind with a walkable line (Follow.CatchUp).
	A unit is never removed for distance, a failed walk or a wall: one that is far behind, stuck, fallen or inside
	another player's plot is moved back (recoverUnit: one Model:PivotTo of the same unit, same id) to a clear spot
	behind the player. destroyUnit runs only on the lifecycle paths: Humanoid.Died, the SyncArmy not-living cull, the
	trim to the desired count, OrdersConfig.Enabled = false and PlayerRemoving. The player's own FOLLOW units open his
	friendly gate while he is alive and near it (AnyUnitNear, read by GateDefenseService); never on Hold / Attack /
	Retreat, never while he is dead or away. Near a hostile (Follow.ThreatStuds; with ThreatStandingFor live
	for the player only while he stands) FOLLOW units follow as at e506c9c (no lead, UnitWalkSpeed).
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
local ArmyConfig = require(Shared.Configs.ArmyConfig) -- army fix: Follow (lead + catch-up), Recover
local BaseConfig = require(Shared.Configs.BaseConfig) -- army fix: plot squares (Recover)
local WorldLabel = require(Shared.Util.WorldLabel)
local PlotFrame = require(Shared.Util.PlotFrame) -- army fix: plot centres (Recover)
local FormationController = require(Shared.Util.FormationController) -- claude-bud JOB 24: the sticky squad target

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)

local SquadOrdersService = {}
-- v90 (Code Bot): the army despawn fix (Follow / Recover / Gate blocks) is live only for owners with
-- ArmyConfig.LiveFor("Fix", userId); set per owner at the top of his think pass (a module field: this chunk is near the
-- 200-register limit). False = v85 FollowPace (Rollout.Army) / 4d26673 behaviour.
SquadOrdersService._FixLive = false
-- v91 (Code Bot): the FOLLOW movement overhaul (Modules/ArmyFollow, ArmyConfig.Follow2). _AFOn is set per owner in the
-- think pass (module fields, not locals: this chunk is near the register limit). While it is on, the v85 FollowPace and
-- the v90 Fix follow / recover paths are off for that owner (ArmyFollow replaces them); shooting stays here.
SquadOrdersService._AF = require(script.Parent.Parent.Modules.ArmyFollow)
-- v114 (Code Bot Roblox): ArmyConfig.Follow3 — ONE FOLLOW controller per army (ArmyController), every soldier MoveTo /
-- PivotTo in SoldierController; in FOLLOW the escort code below only shoots and aims (escortAimOnly)
SquadOrdersService._AC = require(script.Parent.Parent.Modules.ArmyController)
SquadOrdersService._SC = require(script.Parent.Parent.Modules.SoldierController)
local escortAimOnly = false -- v114: set around escortUnit for a Follow3 owner: shoot / face only, never walk
SquadOrdersService._AFOn = false

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
	CrumbPos: Vector3?, -- army fix (Follow.KeepTrailPoint): where that trail point is (kept after it leaves the trail)
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
	Speed: number, -- army fix: the WalkSpeed last written (written only on a change)
	Goal: Vector3?, -- army fix: where its move this think went (nil: it stands); the stuck check
	ProgPos: Vector3?, -- army fix: its root at the last think while it walked to a goal further than StuckGoalStuds
	ProgDir: Vector3?, -- ...and the flat direction to that goal then
	ProgSum: number, -- ...studs made toward its goals since ProgSince
	ProgSince: number,
	FarSince: number?, -- army fix: since when it is more than Recover.FollowFarStuds from its owner
	RecoverAt: number, -- army fix: its last recover or failed search (Recover.CooldownSeconds)
	DeferSince: number?, -- army fix: since when its first clear spot is too near another player
	PlotId: number?, -- army fix: the foreign plot square it stands in (Recover plot trigger), nil outside any
	PlotSince: number, -- ...since when
	StopHeld: boolean, -- army fix: it stands where the owner's stop left it (Follow.Lead.StopHoldStuds) until he moves
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
	Lead: Vector3, -- army fix: the owner's flat velocity x Follow.Lead.Seconds this pass (capped; zero after a jump)
	OwnerSpeed: number, -- army fix: his flat speed over the last pass (0 after a jump on foot)
	PaceAvg: number, -- ship: his speed smoothed over passes (Follow.CatchUp.PaceSmooth)
	PaceSpeed: number, -- ship: the pace follow units walk at; it moves only in Follow.CatchUp.PaceStep steps
	LastPos: Vector3?, -- ...his root at the last pass
	LastAt: number, -- ...and when
	Seated: boolean, -- army fix: he sits (a vehicle seat) this pass
	FastAt: number?, -- army fix: the last pass he drove faster than Recover.VehicleDeferSpeed (until he stops)
	SlowSince: number?, -- ...since when he moves slower than VehicleStopSpeed after that
	RegroupAt: number?, -- ...when that drive ended (stop or exit): far units regroup for RegroupWindowSeconds
	WaterAt: number, -- army fix: the pass his on-water test was made (lazily, only when a unit would recover)
	OnWater: boolean,
	RecoverWinAt: number, -- army fix: the per-owner recover budget window (Recover.PerOwnerPerSecond)
	RecoverWinN: number,
	RecoverLogAt: number, -- army fix: the last server log line for this owner (Recover.LogSeconds)
	RecoverLogN: number, -- ...recovers since
	PrevSpeed: number, -- army fix: his measured flat speed the pass before (Follow.Lead.DropOnSlowdown)
	Engaged: boolean, -- army fix: a hostile is within Follow.ThreatStuds of him this pass (e506c9c follow pacing)
	OwnerPlot: number?, -- army fix: the plot square he stands in (Recover plot trigger)
	OwnerPlotLeft: number?, -- ...the one he last left
	OwnerPlotLeftAt: number, -- ...and when
	LandPos: { Vector3 }, -- army fix: the last LAND_RING recover landing spots of this army (units never land on one another)
	LandAt: { number }, -- ...and when
	LandI: number,
	ReformWinAt: number, -- army fix: the per-owner re-form window (Recover.ReformPerMinute)
	ReformWinN: number,
	WalkAt: number, -- army fix: the last pass he moved at 2 studs/s or more (Follow.Lead.StopHoldSeconds)
	OwnerVel: Vector3, -- army fix: his flat velocity over the last pass (Follow.ThreatApproachOnly)
	Slowing: boolean, -- army fix: this pass he moved at under Lead.DropOnSlowdown x the pass before (he is stopping)
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
local reformAt: { [number]: number } = {} -- army fix: owner -> until when a queued re-form SyncArmy covers him
-- army fix: the recover probes (RespectCanCollide, squads + characters + the owner's vehicle ignored); the ignore list is
-- refilled once per owner per pass, and only when one of his units needs a spot
local recoverParams = RaycastParams.new()
recoverParams.FilterType = Enum.RaycastFilterType.Exclude
recoverParams.RespectCanCollide = true
local recoverIgnore: { Instance } = {}
local recoverFor: Player? = nil -- ...whose pass the list was filled for
local recoverForAt = -math.huge
-- army fix: recover landings remembered per army (SquadState.LandPos / LandAt; ArmyConfig.Recover.LandRing)
local LAND_RING = math.clamp(math.floor(tonumber(((ArmyConfig :: any).Recover or {}).LandRing) or 8), 1, 32)
local thinkErrAt: { [number]: number } = {} -- army fix (ArmyConfig.Loop): owner -> his last think-error log line
local recoverErrAt: { [number]: number } = {} -- army fix (ArmyConfig.Loop): owner -> his last recover-error log line
local threatScanStuds = 0 -- army fix (Follow.ThreatStuds): > 0 only during the FOLLOW escort pick (nearestHostile)
local threatNearRoot: BasePart? = nil -- ...the nearest hostile it found within that range (cleared right after)
local waterParts: { BasePart } = {} -- army fix: the WE_Water surfaces (Constants.Tags.Water), re-read at most every 10 s
local waterReadAt = -math.huge

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

-- army fix (ArmyConfig.Follow.KeepTrailPoint): with no walkable trail point, a unit that was on the trail keeps
-- walking to the last point it had (the player walked there, and it was walkable from about here) instead of straight
-- at its blocked slot. Dropped once reached (ReachStuds), when it lies within StopGap of the player (a cut-off unit
-- still stops behind him), when the slot opens up, and on a recover. No rays.
local function keptTrailPoint(unit: SquadUnit, from: Vector3, playerPos: Vector3, gap: number, cfg: { [string]: any }): Vector3?
	local p = unit.CrumbPos
	if p == nil then
		return nil
	end
	local f = (ArmyConfig :: any).Follow
	if not SquadOrdersService._FixLive or typeof(f) ~= "table" or f.KeepTrailPoint ~= true or flatDist(p, from) <= cfgNum(cfg, "ReachStuds", 2.5) or flatDist(p, playerPos) < gap then
		unit.CrumbPos = nil
		return nil
	end
	return p
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
	5-11 on the trail, up to 2 x MaxCrumbs more on a scan.
	army fix: with nothing walkable, the last trail point it had (keptTrailPoint) comes before the blocked slot.
	army fix: the second result says whether the goal was found walkable (false: a blocked straight line; the unit then
	walks at its owner's pace, never the catch-up run). ]]
local function followGoal(unit: SquadUnit, playerCf: CFrame, offset: Vector3, slotPos: Vector3, trail: Trail?, probe: Probe?, cfg: { [string]: any }?, now: number): (Vector3, boolean)
	if trail == nil or probe == nil or cfg == nil then
		unit.Crumb = nil
		return slotPos, true
	end
	local from = unit.Root.Position
	if flatDist(from, slotPos) <= (OrdersConfig.FollowArriveStuds or 2) or bodyClear(from, slotPos, probe) then
		unit.Crumb = nil
		unit.CrumbPos = nil
		return slotPos, true
	end
	local hug = wallHugPoint(playerCf, offset, probe, cfg)
	if hug and (flatDist(from, hug) <= (OrdersConfig.FollowArriveStuds or 2) or bodyClear(from, hug, probe)) then
		unit.Crumb = nil
		unit.CrumbPos = nil
		return hug, true
	end
	-- the slot is in the open but a wall end or a crate is in the unit's way: the same depth, SqueezeStuds nearer
	-- the player's centre line (never within MinSide of it)
	local minSide = cfgNum(cfg, "MinSide", 3)
	if hug == nil and math.abs(offset.X) > minSide then
		local x = math.max(minSide, math.abs(offset.X) - cfgNum(cfg, "SqueezeStuds", 2))
		local squeezed = (playerCf * CFrame.new(if offset.X < 0 then -x else x, 0, offset.Z)).Position
		if bodyClear(from, squeezed, probe) then
			unit.Crumb = nil
			unit.CrumbPos = nil
			return squeezed, true
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
		return keptTrailPoint(unit, from, playerPos, gap, cfg) or hug or slotPos, false
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
			return keptTrailPoint(unit, from, playerPos, gap, cfg) or hug or slotPos, false
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
			return keptTrailPoint(unit, from, playerPos, gap, cfg) or hug or slotPos, false
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
	unit.CrumbPos = pts[k]
	return pts[k], true
end

-- army fix: a unit's WalkSpeed, written only when it changes (no property write per think)
local function setSpeed(unit: SquadUnit, speed: number)
	if math.abs(unit.Speed - speed) > 0.05 then
		unit.Speed = speed
		unit.Humanoid.WalkSpeed = speed
	end
end

-- army fix: a block of ArmyConfig.Follow (Lead / CatchUp) when it is on, else nil
local function followCfg(key: string): { [string]: any }?
	if not SquadOrdersService._FixLive then
		return nil -- v90: Rollout.Fix not live for this owner
	end
	local f = (ArmyConfig :: any).Follow
	local b = if typeof(f) == "table" then f[key] else nil
	if typeof(b) == "table" and b.Enabled == true then
		return b
	end
	return nil
end

-- ...and with Follow.ThreatApproachOnly only while he stands or walks toward that hostile (walking away: normal follow)
local function threatApproachOnly(): boolean
	local f = (ArmyConfig :: any).Follow
	return typeof(f) == "table" and f.ThreatApproachOnly == true
end

-- Follow.ThreatKeepCatchUp keeps the catch-up run near a hostile too (only the lead is dropped); the standing-only rule
-- is ArmyConfig.ThreatStandingFor(userId)
local function threatFlag(key: string): boolean
	local f = (ArmyConfig :: any).Follow
	return typeof(f) == "table" and f[key] == true
end

-- army fix (Follow.ThreatStuds): FOLLOW units follow as at e506c9c (no lead, UnitWalkSpeed) while a hostile the escort
-- would pick is within this of the owner; 0 = off
local function threatStuds(): number
	if not SquadOrdersService._FixLive then
		return 0 -- v90: Rollout.Fix not live for this owner
	end
	local f = (ArmyConfig :: any).Follow
	local t = if typeof(f) == "table" then tonumber(f.ThreatStuds) else nil
	return if t and t > 0 then t else 0
end

-- army fix (Follow.EscortWalkInFormation): while the owner walks on foot, FOLLOW escort units keep the formation (their
-- led slot, catch-up allowed) and shoot from it, closing in only inside Follow.EscortWalkLeash of him; they stand to
-- fight, walk back at the escort leash or side-step only while he stands
local function escortWalkInFormation(st: SquadState): boolean
	local f = (ArmyConfig :: any).Follow
	return SquadOrdersService._FixLive and typeof(f) == "table" and f.EscortWalkInFormation == true and st.OwnerSpeed >= 1 and not st.Seated
end

-- ...and the walking leash (studs from him) inside which such a unit closes in toward its target instead (0 = never)
local function escortWalkLeash(): number
	local f = (ArmyConfig :: any).Follow
	local v = if typeof(f) == "table" then tonumber(f.EscortWalkLeash) else nil
	return if v and v > 0 then v else 0
end

local function recoverCfg(): { [string]: any }?
	local rc = (ArmyConfig :: any).Recover
	if SquadOrdersService._FixLive and typeof(rc) == "table" and rc.Enabled == true then
		return rc
	end
	return nil
end

--[[ army fix (Follow.CatchUp): a FOLLOW unit walks at its owner's pace (his flat speed over the last pass, never below
	UnitWalkSpeed, so it falls back to UnitWalkSpeed while he stands) and runs SpeedMult x that pace (at most MaxSpeed)
	only while it is more than StartStuds behind: its goal is further than StartStuds + the lead distance (the lead
	alone never starts a run, so a unit in its slot walks at his pace) and its line to the goal is walkable (a unit
	whose line is blocked never runs). CatchUp off, or engaged (st.Engaged: a hostile near him, Follow.ThreatStuds): UnitWalkSpeed,
	as at e506c9c. ]]
local function followSpeed(st: SquadState, unit: SquadUnit, toGoal: number, walkable: boolean)
	if not SquadOrdersService._FixLive then
		return -- v90: not a Fix-live owner: the speed stays with v85 FollowPace / UnitWalkSpeed (4d26673)
	end
	local base = OrdersConfig.UnitWalkSpeed or 14
	local cu = followCfg("CatchUp")
	if cu == nil or (st.Engaged and not threatFlag("ThreatKeepCatchUp")) then
		setSpeed(unit, base)
		return
	end
	local maxSpeed = math.max(base, cfgNum(cu, "MaxSpeed", 28))
	local pace = math.clamp(st.PaceSpeed, base, maxSpeed) -- ship: the smoothed, stepped pace (updateOwnerMotion)
	if walkable and toGoal - st.Lead.Magnitude > cfgNum(cu, "StartStuds", 6) then
		pace = math.min(maxSpeed, pace * cfgNum(cu, "SpeedMult", 1.5))
	end
	setSpeed(unit, pace)
end

-- army fix (Follow.Lead.StopHoldStuds): when the owner stops, a unit whose goal lies behind it (along his facing) and
-- within this many studs overshot on the last lead: it stands, facing his way, instead of turning back toward the
-- camera. 0 when the lead is off.
local function stopHoldStuds(): number
	local lc = followCfg("Lead")
	if lc == nil then
		return 0
	end
	return cfgNum(lc, "MaxStuds", 4) + cfgNum(lc, "StopHoldStuds", 2)
end

-- ...only for a unit that stops within this many seconds of his last walking pass (a unit walking back to its slot
-- later, e.g. after he turned round on the spot, still does)
local function stopHoldSeconds(): number
	local lc = followCfg("Lead")
	return if lc then cfgNum(lc, "StopHoldSeconds", 1.5) else 0
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
		CrumbPos = nil,
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
		Speed = humanoid.WalkSpeed,
		Goal = nil,
		ProgPos = nil,
		ProgDir = nil,
		ProgSum = 0,
		ProgSince = 0,
		FarSince = nil,
		RecoverAt = -math.huge,
		DeferSince = nil,
		PlotId = nil,
		PlotSince = 0,
		StopHeld = false,
	}
	-- v99: every unit, every order, from its first frame: the ArmyNPCs collision group (never collides with another
	-- soldier, still with the world and players), no trip / ragdoll states, server network ownership kept
	SquadOrdersService._AF.PrepUnit(unit)

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
		-- claude-bud JOB 5d: his last field soldier just died: one army prompt (MonetizationConfig.Placement)
		task.defer(function()
			local stNow = squadByUser[owner.UserId]
			if stNow == nil then
				return
			end
			for _, u in ipairs(stNow.Units) do
				if u.Alive then
					return
				end
			end
			local okM, ms = pcall(function(): any
				return require(script.Parent.MonetizationService)
			end)
			if okM and ms and ms.OfferMoment then
				pcall(ms.OfferMoment, owner, "army")
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

-- ── army lane A0 (ArmyConfig Rollout.Escort / Escort / ShotFx; SPEC-ARMY-FINAL §7.1-7.2) ─────────────────────────
local ArmyCfg = ArmyConfig -- army lane A0 (the same module, required once at the top by the army fix)
-- One hostile list per think pass (Escort.NpcSnapshot, every army): CombatService.LiveNPCSnapshot refills it in place
-- at the start of the pass; nearestHostile reads it instead of a CollectionService:GetTagged per unit. Outside a pass
-- (or with the switch off / no CombatService) it scans the tag as before.
local hostileSnap: { Model } = {}
local hostileSnapValid = false
-- the FOLLOW escort of the owner being thought this pass: live (Rollout.Escort) and its leash (EscortLeash, or
-- Escort.DefendLeash while a defend / focus-fire target exists). Set per player in the think loop.
local escortLive = false
local escortLeash = CombatFairnessConfig.EscortLeash
-- v85 FollowPace (ArmyConfig.FollowPace, Rollout.Army): the owner being thought this pass, on foot in FOLLOW. Live =
-- his army matches his speed, leads his motion, keeps walking with him and is put back beside him as a last resort.
-- One table (this chunk is near the 200-register limit); TpAt: unit -> os.clock() of its next allowed recovery.
local followCtx = {
	Live = false,
	Moving = false,
	Speed = 16,
	Lead = Vector3.zero,
	TpAt = setmetatable({}, { __mode = "k" }) :: any,
	Ray = RaycastParams.new(),
}
followCtx.Ray.FilterType = Enum.RaycastFilterType.Exclude
followCtx.Ray.RespectCanCollide = true

-- v85 FollowPace: is the pace live for this owner this pass (FOLLOW is checked by the caller)? Fills followCtx.
function SquadOrdersService._PaceBegin(player: Player, proot: BasePart): boolean
	followCtx.Live = false
	followCtx.Moving = false
	followCtx.Lead = Vector3.zero
	local c = (ArmyCfg :: any).FollowPace
	if SquadOrdersService._FixLive then
		return false -- v90: the army fix (Rollout.Fix) drives this owner's pace, lead and recover instead
	end
	if typeof(c) ~= "table" or c.Enabled ~= true or not ArmyCfg.LiveFor("Army", player.UserId) then
		return false
	end
	local char = proot.Parent
	local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
	if hum == nil or hum.Health <= 0 or hum.SeatPart ~= nil then
		return false -- seated (vehicles) or dead: today's rules
	end
	local v = proot.AssemblyLinearVelocity
	local flatV = Vector3.new(v.X, 0, v.Z)
	followCtx.Live = true
	followCtx.Speed = math.clamp(hum.WalkSpeed, 0, 60)
	followCtx.Moving = flatV.Magnitude > (tonumber(c.MovingStuds) or 3)
	if followCtx.Moving then
		local lead = flatV * (tonumber(c.LeadSeconds) or 0.5)
		local maxLead = tonumber(c.MaxLeadStuds) or 12
		if lead.Magnitude > maxLead then
			lead = lead.Unit * maxLead
		end
		followCtx.Lead = lead
	end
	return true
end

-- v85 FollowPace: a unit's WalkSpeed for this pass. `gap` = studs from where it should be. Not live (other players,
-- other orders, the owner seated) = OrdersConfig.UnitWalkSpeed, as before. Written on change only.
function SquadOrdersService._PaceSpeed(unit: SquadUnit, gap: number)
	local base = OrdersConfig.UnitWalkSpeed or 14
	local want = base
	if followCtx.Live then
		local c = (ArmyCfg :: any).FollowPace
		want = math.max(base, followCtx.Speed * (tonumber(c.MatchMult) or 1))
		if gap > (tonumber(c.SprintStartStuds) or 20) then
			want *= tonumber(c.SprintMult) or 1.8
		elseif gap > (tonumber(c.CatchUpStartStuds) or 6) then
			want *= tonumber(c.CatchUpMult) or 1.4
		end
		want = math.min(want, tonumber(c.MaxSpeed) or 40)
	end
	want = math.floor(want * 2 + 0.5) / 2
	if unit.Humanoid.WalkSpeed ~= want then
		unit.Humanoid.WalkSpeed = want
	end
end
-- side-step (Escort.SideStep, live owners): per-unit state, weak-keyed (a unit's entry goes with the unit)
type StepState = {
	Blocked: number, -- shot checks in a row with the target in range and out of sight
	Target: BasePart?, -- the target those checks were about (another one starts over)
	ProbeAt: number, -- the last probe (Escort.SideStepMinGap)
	Ring: number, -- probes made (the probe distance alternates over Escort.SideStepStuds)
	Goal: Vector3?, -- the spot it walks to (nil: none)
	Until: number, -- ...until then (Escort.SideStepHoldSeconds)
}
local stepState: { [any]: StepState } = setmetatable({}, { __mode = "k" }) :: any
local stepParams = RaycastParams.new() -- walk-clearance ray of a probe (collidable geometry only)
stepParams.FilterType = Enum.RaycastFilterType.Exclude
stepParams.RespectCanCollide = true
local stepIgnore: { Instance } = {}
local missSide = 1 -- ShotFx: a miss tracer lands left / right of the target in turn
-- read-only counters (tests, the Studio command bar): SquadOrdersService._EscortStats()
local escortStats = { LivePasses = 0, DefendPasses = 0, Probes = 0, ProbeRays = 0, SideSteps = 0, Snapshots = 0 }

local function hostileScan(tag: string): { Instance }
	if hostileSnapValid then
		return hostileSnap :: any
	end
	return CollectionService:GetTagged(tag)
end

-- once at the start of a think pass: the NPC list every nearestHostile / escort pick of this pass reads
local function refillHostiles()
	hostileSnapValid = false
	local cs = CombatService
	local fill = if cs then cs.LiveNPCSnapshot else nil
	if ArmyCfg.Escort.NpcSnapshot ~= true or typeof(fill) ~= "function" then
		return
	end
	-- the list counts only when the fill kept its contract (returned the count); anything else = the tag scan, as before
	local ok, n = pcall(fill, hostileSnap)
	hostileSnapValid = ok and typeof(n) == "number"
	if hostileSnapValid then
		escortStats.Snapshots += 1
	else
		table.clear(hostileSnap)
	end
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
	local tScan = threatScanStuds -- army fix (Follow.ThreatStuds): 0 except during the FOLLOW escort pick
	local tDist = math.huge
	local tRoot: BasePart? = nil
	for _, inst in ipairs(hostileScan(npcTag)) do -- army lane A0: the pass's NPC list (was GetTagged per call)
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
				if d < bestDist or d < zoneDist or d <= lr or d <= tScan then
					local id = inst:GetAttribute("NPCId")
					if not (holds ~= nil and holds(id) == true) and not (mayHit ~= nil and mayHit(owner, id) == false) then
						if d <= tScan and d < tDist then -- army fix: the nearest hostile within ThreatStuds
							tDist = d
							tRoot = root
						end
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
	if tScan > 0 then
		threatNearRoot = tRoot -- army fix: read (and cleared) by the think loop right after the escort pick
	end
	return bestHum, bestRoot, bestDist, zoneHum, zoneRoot, zoneDist, heldA, heldB
end

--[[ army lane A0 (live owners, Rollout.Escort): the FOLLOW escort's pick for one pass, in place of nearestHostile. First
	the defend targets: NPCs aiming at the owner, or hit by the owner himself in the last Escort.FocusFireSeconds, within
	Escort.DefendRadius of him (CombatService.NPCThreat); the nearest of them is the primary. Else today's pick (the
	nearest hostile within EscortEngageRadius). The same filters as nearestHostile (a CombatService NPC; EscortIgnoreCalm;
	UnitMayHitNPC). escortCands holds the defend targets first (nearest first), then today's candidates, for pickShot's
	visible-target fallback. Returns (primary Humanoid, its root, a defend target exists). No table is made. ]]
local function escortPickLive(player: Player, proot: BasePart): (Humanoid?, BasePart?, boolean)
	local E = ArmyCfg.Escort
	local r = CombatFairnessConfig.EscortEngageRadius
	local dr = math.max(tonumber(E.DefendRadius) or r, r)
	local focus = tonumber(E.FocusFireSeconds) or 0
	local cs = CombatService
	local holds = if CombatFairnessConfig.EscortIgnoreCalm == true and cs then cs.NPCHoldsFire else nil
	if typeof(holds) ~= "function" then
		holds = nil
	end
	local mayHit = if cs then cs.UnitMayHitNPC else nil
	if typeof(mayHit) ~= "function" then
		mayHit = nil
	end
	local threat = if cs then cs.NPCThreat else nil
	if typeof(threat) ~= "function" then
		threat = nil
	end
	local from = proot.Position
	local cap = candCap()
	candReset(escortCands)
	local bestHum: Humanoid?, bestRoot: BasePart?, bestDist = nil, nil, r
	local defHum: Humanoid?, defRoot: BasePart?, defDist = nil, nil, math.huge
	local tScan = threatScanStuds -- army fix (Follow.ThreatStuds): the nearest pickable hostile out to it, same filters
	local tDist = math.huge
	local tRoot: BasePart? = nil
	for _, inst in ipairs(hostileScan(Constants.Tags.NPC)) do
		if
			inst:IsA("Model")
			and not inst:GetAttribute("FriendlySquad")
			and not inst:GetAttribute("OwnerUserId")
			and typeof(inst:GetAttribute("NPCId")) == "string"
		then
			local hum = inst:FindFirstChildOfClass("Humanoid")
			local root = inst:FindFirstChild("HumanoidRootPart")
			if hum and root and root:IsA("BasePart") and hum.Health > 0 then
				local d = (root.Position - from).Magnitude
				if d <= dr or d <= tScan then
					local id = inst:GetAttribute("NPCId")
					if not (holds ~= nil and holds(id) == true) and not (mayHit ~= nil and mayHit(player, id) == false) then
						if d <= tScan and d < tDist then -- army fix: the nearest hostile within ThreatStuds
							tDist = d
							tRoot = root
						end
						if d <= dr then
							local aiming, recent = false, false
							if threat ~= nil then
								aiming, recent = threat(id, player, focus)
							end
							if aiming == true or recent == true then
								if d < defDist then
									defDist = d
									defHum = hum
									defRoot = root
								end
								candInsert(escortCands, cap, hum, root, d - dr - 1) -- sorts before every other hostile
							elseif d <= r then
								if d < bestDist then
									bestDist = d
									bestHum = hum
									bestRoot = root
								end
								candInsert(escortCands, cap, hum, root, d)
							end
						end
					end
				end
			end
		end
	end
	if tScan > 0 then
		threatNearRoot = tRoot -- army fix: read (and cleared) by the think loop right after the escort pick
	end
	escortStats.LivePasses += 1
	if defHum ~= nil then
		escortStats.DefendPasses += 1
		return defHum, defRoot, true
	end
	return bestHum, bestRoot, false
end

-- army lane A0: the escort counters (a copy; tests and the Studio command bar)
function SquadOrdersService._EscortStats(): { [string]: number }
	return table.clone(escortStats)
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

--[[ army lane A0 (ArmyConfig.ShotFx, live owners, every order): after a unitShoot call, the tracer of the shot it fired
	(its LastFireAt moved past `firedAt`: a hit or a miss; nothing when the gun was not ready), from the unit's eye to
	the target (`hit`) or MissOffsetStuds beside it (a miss, sides in turn: no random numbers, so the hit rolls are
	untouched). CombatService.UnitShotFx samples it (one per army per PerArmyMinGap) and sends it as an NPC rifle shot. ]]
local function unitShotFx(player: Player, unit: SquadUnit, troot: BasePart, firedAt: number, hit: boolean)
	if unit.LastFireAt == firedAt then
		return -- no shot this call
	end
	local cfg = ArmyCfg.ShotFx
	if cfg.Enabled ~= true or not ArmyCfg.LiveFor("Escort", player.UserId) then
		return
	end
	local send = if CombatService then CombatService.UnitShotFx else nil
	if typeof(send) ~= "function" then
		return
	end
	local eye = unit.Root.Position + Vector3.new(0, CombatFairnessConfig.NpcEyeHeight, 0)
	local landed = troot.Position
	if not hit then
		missSide = -missSide
		local d = landed - eye
		local flat = Vector3.new(d.X, 0, d.Z)
		local side = if flat.Magnitude > 0.01 then Vector3.new(-flat.Z, 0, flat.X).Unit else Vector3.xAxis
		landed += side * (missSide * (tonumber(cfg.MissOffsetStuds) or 3))
	end
	pcall(send, player, eye, landed, if hit then "N" else "M")
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
	-- claude-bud (CombatConfig.GuardsFightBack): name the shooting unit for this one hit, so the NPC can fight back
	local setShooter = if CombatService then CombatService.SetUnitShooter else nil
	if typeof(setShooter) == "function" then
		setShooter(unit.Model)
	end
	local ok, dealt = pcall(apply, player, th, (OrdersConfig.AttackDamage or 8) * researchMult(player, "SoldierDamage"), credit) -- v69 research
	if typeof(setShooter) == "function" then
		setShooter(nil)
	end
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

-- army lane A0 (side-step probe): unitHasLos's ray (the same ignore list and rules, the one cached losParams) from any
-- eye point, e.g. a spot beside the unit
local function losFromEye(player: Player, unit: SquadUnit, eye: Vector3, troot: BasePart): boolean
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
	losParams.FilterDescendantsInstances = losIgnore
	local blocked = Workspace:Raycast(eye, delta, losParams) ~= nil
	table.clear(losIgnore)
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

-- ── army lane A0: side-step (ArmyConfig.Escort.SideStep; FOLLOW escort of a live owner) ───────────────────────────
local function stepOf(unit: SquadUnit): StepState
	local s = stepState[unit]
	if s == nil then
		s = { Blocked = 0, Target = nil, ProbeAt = -math.huge, Ring = 0, Goal = nil, Until = 0 }
		stepState[unit] = s
	end
	return s :: StepState
end

-- a shot went out: the blocked count starts over and a side-step walk ends (it sees from here)
local function stepSaw(unit: SquadUnit)
	local s = stepState[unit]
	if s then
		s.Blocked = 0
		s.Goal = nil
	end
end

-- army fix: the owner walks (Follow.EscortWalkInFormation): a side-step walk ends (the blocked count is kept)
local function stepEnd(unit: SquadUnit)
	local s = stepState[unit]
	if s then
		s.Goal = nil
	end
end

--[[ One probe (<= 4 rays): SideStepStuds[ring] to the unit's left and right (across its line to the target). A side is
	tried only when that spot stays within 90 % of the escort leash from the owner and within AttackRange of the target:
	one knee-height ray for walk clearance (collidable geometry), then one sight ray from the spot's eye to the target
	(the unit's own LOS rules). Returns the first spot that sees the target, or nil. ]]
local function stepProbe(player: Player, unit: SquadUnit, s: StepState, playerRoot: BasePart, troot: BasePart, now: number): Vector3?
	local E = ArmyCfg.Escort
	s.ProbeAt = now
	escortStats.Probes += 1
	local list = E.SideStepStuds
	local n = if typeof(list) == "table" then #list else 0
	if n == 0 then
		return nil
	end
	local off = tonumber(list[(s.Ring % n) + 1]) or 4
	s.Ring += 1
	local from = unit.Root.Position
	local d = troot.Position - from
	local flat = Vector3.new(d.X, 0, d.Z)
	if flat.Magnitude < 1 then
		return nil
	end
	local side = Vector3.new(-flat.Z, 0, flat.X).Unit
	local pc = followPathCfg()
	local drop = if pc then cfgNum(pc, "RayDrop", 1) else 1
	local half = if pc then cfgNum(pc, "RayHalfWidth", 0.9) else 0.9
	local maxOwner = escortLeash * 0.9
	local range = OrdersConfig.AttackRange or 55
	local eyeUp = Vector3.new(0, CombatFairnessConfig.NpcEyeHeight, 0)
	local found: Vector3? = nil
	local paramsSet = false
	for k = 1, 2 do
		local dir = if k == 1 then side else -side
		local spot = from + dir * off
		if flatDist(spot, playerRoot.Position) <= maxOwner and (troot.Position - spot).Magnitude <= range then
			if not paramsSet then
				paramsSet = true
				table.clear(stepIgnore)
				table.insert(stepIgnore, ensureFolder())
				if player.Character then
					table.insert(stepIgnore, player.Character :: Instance)
				end
				stepParams.FilterDescendantsInstances = stepIgnore
			end
			local clear = Workspace:Raycast(from - Vector3.new(0, drop, 0), dir * (off + half), stepParams) == nil
			escortStats.ProbeRays += if clear then 2 else 1
			if clear and losFromEye(player, unit, spot + eyeUp, troot) then
				found = spot
				break
			end
		end
	end
	table.clear(stepIgnore) -- no model held between probes (the property keeps its own copy)
	return found
end

-- a shot check found nothing in sight (the target in range): count it; after SideStepAfterBlocked in a row, probe (at
-- most once per SideStepMinGap, never while a side-step walk is on)
local function stepBlocked(player: Player, unit: SquadUnit, playerRoot: BasePart, troot: BasePart, now: number)
	if escortAimOnly then
		return -- v114 (Follow3): FOLLOW never side-steps (the formation owns the unit's position)
	end
	local E = ArmyCfg.Escort
	if E.SideStep ~= true then
		return
	end
	local s = stepOf(unit)
	if s.Target ~= troot then
		s.Target = troot
		s.Blocked = 0
		s.Goal = nil
	end
	s.Blocked += 1
	if s.Goal ~= nil or s.Blocked < (tonumber(E.SideStepAfterBlocked) or 2) or now - s.ProbeAt < (tonumber(E.SideStepMinGap) or 1.5) then
		return
	end
	local spot = stepProbe(player, unit, s, playerRoot, troot, now)
	if spot then
		escortStats.SideSteps += 1
		s.Goal = spot
		s.Until = now + (tonumber(E.SideStepHoldSeconds) or 3)
	end
end

-- this think's move while a side-step walk is on (the target is the same, the owner still within the leash of the spot
-- and of the unit, not timed out): walk to the spot facing the target, or stand on it. false = no side-step (it ends)
local function stepMove(unit: SquadUnit, playerRoot: BasePart, troot: BasePart, fromPlayer: number, now: number): boolean
	local s = stepState[unit]
	if s == nil or s.Goal == nil then
		return false
	end
	local goal = s.Goal :: Vector3
	if s.Target ~= troot or now >= s.Until or fromPlayer > escortLeash or flatDist(goal, playerRoot.Position) > escortLeash then
		s.Goal = nil
		return false
	end
	faceYaw(unit.Root, troot.Position)
	if flatDist(goal, unit.Root.Position) > 1.5 then
		SquadOrdersService._AF.Command(unit, goal)
	else
		SquadOrdersService._AF.Command(unit, unit.Root.Position)
	end
	return true
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
	local leash = escortLeash -- army lane A0: EscortLeash, or Escort.DefendLeash while a defend target exists (live)
	local range = OrdersConfig.AttackRange or 55
	local playerPos = playerRoot.Position
	local unitPos = unit.Root.Position
	local fromPlayer = (unitPos - playerPos).Magnitude
	local walkForm = escortWalkInFormation(st) -- army fix: he walks on foot (formation, shooting from it)
	-- squadfair: the shot first (the unit faces what it shoots), then the escort's walk as before
	if losCheckDue(unit, now) then
		local sh, sr, rays = pickShot(player, unit, th, troot, range, escortCands, CombatFairnessConfig.EscortRequireLos == true)
		if sh and sr then
			unit.LosBlocked = false
			unit.AimRoot = if sh ~= th then sr else nil
			unit.AimHum = if sh ~= th then sh else nil
			local firedAt = unit.LastFireAt -- army lane A0
			local hit = unitShoot(player, unit, sh, now, true)
			unitShotFx(player, unit, sr, firedAt, hit) -- army lane A0: the tracer (live owners)
			if escortLive then
				stepSaw(unit) -- army lane A0
			end
		elseif rays > 0 then
			losBlockedFor(unit, now)
			if escortLive and fromPlayer <= leash and not walkForm then
				stepBlocked(player, unit, playerRoot, troot, now) -- army lane A0: side-step after SideStepAfterBlocked (v114: a no-op in Follow3 FOLLOW)
			end
		end
	end
	if escortAimOnly then
		-- v114 (Follow3): FOLLOW = the formation; the escort shoots from its slot and only aims (the face gyro target;
		-- SoldierController gives the gyro torque only while the unit stands in its slot). No MoveTo, no side-step.
		faceYaw(unit.Root, aimPoint(unit, troot))
		return true
	end
	if walkForm then
		-- army fix (Follow.EscortWalkInFormation): he walks. No stand to fight and no side-step walk: beyond the
		-- walking leash (Follow.EscortWalkLeash, shorter than the phone camera's distance behind him) the unit goes
		-- back to the formation (the caller runs followMove: the led slot or his trail, catch-up allowed); inside it,
		-- it keeps his pace toward the target on his line to it, at most 90 % of that leash out. It shoots from
		-- either (the shot above).
		if escortLive then
			stepEnd(unit)
		end
		local wl = math.min(leash, escortWalkLeash())
		if wl <= 0 or fromPlayer > wl then
			return false
		end
		local aimW = aimPoint(unit, troot)
		faceYaw(unit.Root, aimW)
		local offW = aimW - playerPos
		local maxW = wl * 0.9
		local goalW = if offW.Magnitude > maxW then playerPos + offW.Unit * maxW else aimW
		followSpeed(st, unit, 0, false) -- his pace (a unit that falls beyond the walking leash catches up in followMove)
		unit.Goal = goalW
		SquadOrdersService._AF.Command(unit, goalW)
		return true
	end
	if followCtx.Live and followCtx.Moving then
		-- v85 FollowPace: the owner is walking: the escort shoots on the move from its slot (followMove), never stands
		faceYaw(unit.Root, aimPoint(unit, troot))
		return false
	end
	if escortLive and stepMove(unit, playerRoot, troot, fromPlayer, now) then
		followSpeed(st, unit, 0, false) -- army fix: a side-step walks at the owner's pace (never a catch-up run)
		unit.Goal = nil -- army fix: a side-step spot is not a follow goal (the stuck window starts over)
		return true -- army lane A0: walking to (or standing on) a side-step spot that sees the target
	end

	local aimAt = aimPoint(unit, troot) -- the fallback hostile it shoots, else the one nearest the player
	local dist = (aimAt - unitPos).Magnitude
	faceYaw(unit.Root, aimAt)
	if fromPlayer > leash then
		if SquadOrdersService._FixLive then
			-- back to the formation slot next to the player (still shooting on the way when possible); army fix: around
			-- where the player will be (Follow.Lead; st.Lead is zero when off or near a hostile)
			local goal = (playerRoot.CFrame * CFrame.new(unitOffset(st, unit.Slot))).Position + st.Lead
			followSpeed(st, unit, flatDist(goal, unitPos), false) -- the owner's pace: never a run into a wall
			unit.Goal = goal
			SquadOrdersService._AF.Command(unit, goal)
		else
			-- back to the formation slot next to the player (still shooting on the way when possible)
			SquadOrdersService._PaceSpeed(unit, fromPlayer) -- v85 FollowPace (base speed when not live)
			-- claude-bud JOB 22: back to the SAME formation slot ArmyFollow uses (never the old wing slots)
			local home = if SquadOrdersService._AF.StableOn() then SquadOrdersService._AF.HomePoint(player, st, unit, playerRoot, now) else (playerRoot.CFrame * CFrame.new(unitOffset(st, unit.Slot))).Position
			SquadOrdersService._AF.Command(unit, home)
		end
	elseif dist > range * 0.85 then
		-- close in, but never past 90 % of the leash from the player
		local off = aimAt - playerPos
		local maxOff = leash * 0.9
		local goal = if off.Magnitude > maxOff then playerPos + off.Unit * maxOff else aimAt
		followSpeed(st, unit, 0, false) -- army fix: the owner's pace
		unit.Goal = goal
		SquadOrdersService._AF.Command(unit, goal)
	else
		followSpeed(st, unit, 0, false)
		unit.Goal = nil
		SquadOrdersService._AF.Command(unit, unitPos)
	end
	return true
end

-- The plain FOLLOW walk: the unit's slot beside the player, or the player's trail when the slot is cut off
-- (followGoal). squadfair: also an ATTACK unit that gave up a blocked chase (UnitBlockedChaseSeconds).
local function followMove(st: SquadState, unit: SquadUnit, playerRoot: BasePart, trail: Trail?, probe: Probe?, now: number)
	local offset = unitOffset(st, unit.Slot)
	-- v90: the army fix (Rollout.Fix) replaces v85 FollowPace for a Fix-live owner; everyone else keeps v85 / 4d26673
	local target: Vector3
	if SquadOrdersService._FixLive then
		-- army fix (Follow.Lead): the slot around where the player will be at the next think (st.Lead is zero when off; an
		-- ATTACK give-up walks the unled slot, as before)
		local leadCf = if st.Order == "Follow" then playerRoot.CFrame + st.Lead else playerRoot.CFrame
		local slotPos = (leadCf * CFrame.new(offset)).Position
		if unit.StopHeld and st.Order == "Follow" and not (st.OwnerSpeed >= 1 and not (st.Slowing and not st.Engaged)) then
			-- army fix: held after he stopped (below), and its slot is still just behind it: it keeps standing, with no
			-- walkable-line probe (no rays per think while he stands)
			local lv = playerRoot.CFrame.LookVector
			local up = unit.Root.Position
			if flatDist(slotPos, up) <= stopHoldStuds() and (slotPos.X - up.X) * lv.X + (slotPos.Z - up.Z) * lv.Z < 0 then
				unit.Goal = nil
				SquadOrdersService._AF.Command(unit, up)
				faceYaw(unit.Root, up + lv * 8)
				return
			end
		end
		local walkable
		target, walkable = followGoal(unit, leadCf, offset, slotPos, trail, probe, followPathCfg(), now)
		local toGoal = flatDist(target, unit.Root.Position)
		if st.Order == "Follow" then
			followSpeed(st, unit, toGoal, walkable) -- army fix (Follow.CatchUp); an ATTACK give-up walks at its own speed
		end
		unit.Goal = target
	else
		-- v85 FollowPace: a live owner's slot is taken where he will be LeadSeconds ahead (never behind him)
		local pcf = if followCtx.Live then playerRoot.CFrame + followCtx.Lead else playerRoot.CFrame
		local slotPos = (pcf * CFrame.new(offset)).Position
		target = followGoal(unit, pcf, offset, slotPos, trail, probe, followPathCfg(), now)
		SquadOrdersService._PaceSpeed(unit, flatDist(unit.Root.Position, slotPos))
	end
	if followSlotList() == nil then
		-- old grid (FollowSlots empty): the original player-distance rules
		local dist = (unit.Root.Position - playerRoot.Position).Magnitude
		local stop = OrdersConfig.FollowStopDistance or 6
		if dist > (OrdersConfig.FollowDistance or 10) then
			SquadOrdersService._AF.Command(unit, target)
			faceYaw(unit.Root, playerRoot.Position)
		elseif dist > stop then
			SquadOrdersService._AF.Command(unit, target)
		else
			unit.Goal = nil
			SquadOrdersService._AF.Command(unit, unit.Root.Position)
		end
		return
	end
	-- Follow slots sit 5.7-15.5 studs from the player, so arrival is measured to the slot: a unit walks facing
	-- where it goes and, once in its slot, stands facing where the player faces (the old "face the player
	-- beyond 10 studs" rule would crab-walk the outer wings sideways)
	local toGoal = flatDist(target, unit.Root.Position)
	local arrive = OrdersConfig.FollowArriveStuds or 2
	local go: boolean
	if SquadOrdersService._FixLive then
		if st.OwnerSpeed >= 1 and not (st.Slowing and not st.Engaged) then
			unit.StopHeld = false
		elseif st.Order == "Follow" and toGoal > arrive and toGoal <= stopHoldStuds() and (unit.StopHeld or now - st.WalkAt <= stopHoldSeconds()) then
			-- army fix: he has just stopped and its goal is just behind it (the last lead carried it past its slot): it has
			-- arrived, and stays put until he moves again
			local lv = playerRoot.CFrame.LookVector
			local up = unit.Root.Position
			if (target.X - up.X) * lv.X + (target.Z - up.Z) * lv.Z < 0 then
				toGoal = 0
				unit.StopHeld = true
			end
		end
		go = toGoal > arrive
	else
		go = toGoal > arrive or (followCtx.Live and followCtx.Moving) -- v85 FollowPace
	end
	if go then
		SquadOrdersService._AF.Command(unit, target)
		if toGoal > 4 then
			faceYaw(unit.Root, target)
		end
	else
		unit.Goal = nil
		SquadOrdersService._AF.Command(unit, unit.Root.Position)
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
-- claude-bud (ATTACK fix, ArmyConfig.Follow2.Tidy): the ArmyFollow module when tidy formations are live for him
local function attackTidy(player: Player): any?
	local af = SquadOrdersService._AF
	if af and af.TidyLive and af.AttackPoint and af.TidyLive(player) then
		return af
	end
	return nil
end

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
			local af = attackTidy(player)
			if af then
				-- claude-bud (ATTACK fix): its own march spot by seat, never the one point 12 studs ahead of him
				SquadOrdersService._AF.Command(unit, af.AttackPoint(st, unit, playerRoot.Position, playerRoot.CFrame.LookVector, "march"))
			else
				SquadOrdersService._AF.Command(unit, (playerRoot.CFrame * CFrame.new(0, 0, -12)).Position)
			end
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
			local firedAt = unit.LastFireAt -- army lane A0
			local hit = unitShoot(player, unit, th, now, CombatFairnessConfig.UnitKillCreditOnAttack == true) -- P1-4
			unitShotFx(player, unit, troot, firedAt, hit) -- army lane A0: the tracer (live owners)
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
			SquadOrdersService._AF.Command(unit, unit.Root.Position)
		end
		return
	end
	local aimAt = aimPoint(unit, nroot)
	faceYaw(unit.Root, aimAt)
	-- claude-bud (ATTACK fix): chasing, each unit closes on its own ring seat round the target (no shared Vector3)
	local afA = attackTidy(player)
	if afA then
		local from = unit.Root.Position
		local center = if unit.AimRoot ~= nil then aimAt else nroot.Position
		local ringAt = afA.AttackPoint(st, unit, center, center - (if playerRoot then playerRoot.Position else from), "ring")
		if unit.AimRoot ~= nil then
			if (aimAt - from).Magnitude > band then
				SquadOrdersService._AF.Command(unit, ringAt)
			else
				SquadOrdersService._AF.Command(unit, from)
			end
		elseif dist > band or (unit.LosBlocked and CombatFairnessConfig.UnitChaseWithoutLos == true) then
			SquadOrdersService._AF.Command(unit, ringAt)
		else
			SquadOrdersService._AF.Command(unit, from)
		end
		return
	end
	if unit.AimRoot ~= nil then
		-- squadfair: it shoots a visible hostile (the fallback): it closes in on that one only, never on the walled-off one
		if (aimAt - unit.Root.Position).Magnitude > band then
			SquadOrdersService._AF.Command(unit, aimAt)
		else
			SquadOrdersService._AF.Command(unit, unit.Root.Position)
		end
	elseif dist > band then
		SquadOrdersService._AF.Command(unit, nroot.Position)
	elseif unit.LosBlocked and CombatFairnessConfig.UnitChaseWithoutLos == true then
		SquadOrdersService._AF.Command(unit, nroot.Position) -- no clear shot: keep closing in (NPC rule), until it gives up
	else
		SquadOrdersService._AF.Command(unit, unit.Root.Position)
	end
end

-- ── army fix: RECOVER (ArmyConfig.Recover, SPEC-ARMY-FINAL §6.5): never delete, reposition ──────────────────────────

-- the plot square (BaseConfig.PlotSize, flat) that holds `pos`, or nil
local function plotAt(pos: Vector3): number?
	local half = BaseConfig.PlotSize.X * 0.5
	for id = 1, BaseConfig.MaxPlots do
		local c = PlotFrame.PlotPosition(id)
		if c and math.abs(pos.X - c.X) <= half and math.abs(pos.Z - c.Z) <= half then
			return id
		end
	end
	return nil
end

local function plotOwnerId(plotId: number): number?
	if BaseService and BaseService.GetOwnerUserId then
		local uid = BaseService.GetOwnerUserId(plotId)
		if typeof(uid) == "number" then
			return uid
		end
	end
	return nil
end

local function ownPlotId(player: Player): number?
	if BaseService and BaseService.GetOwnedPlotId then
		local id = BaseService.GetOwnedPlotId(player)
		if typeof(id) == "number" then
			return id
		end
	end
	return nil
end

-- the WE_Water surfaces (Constants.Tags.Water), re-read at most every Recover.WaterRereadSeconds (10) and only while a
-- recover looks for a spot
local function waterList(now: number): { BasePart }
	local rcw = (ArmyConfig :: any).Recover
	if now - waterReadAt >= (if typeof(rcw) == "table" then tonumber(rcw.WaterRereadSeconds) or 10 else 10) then
		waterReadAt = now
		table.clear(waterParts)
		for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.Water)) do
			if inst:IsA("BasePart") then
				table.insert(waterParts, inst)
			end
		end
	end
	return waterParts
end

-- ground at height y under a WE_Water surface (the VehicleService rule: inside its footprint, below its top)
local function underWater(x: number, y: number, z: number, now: number): boolean
	for _, wp in ipairs(waterList(now)) do
		if wp.Parent then
			local lp = wp.CFrame:PointToObjectSpace(Vector3.new(x, y, z))
			if math.abs(lp.X) <= wp.Size.X * 0.5 and math.abs(lp.Z) <= wp.Size.Z * 0.5 and wp.Position.Y + wp.Size.Y * 0.5 > y - 0.5 then
				return true
			end
		end
	end
	return false
end

-- the vehicle model a seat belongs to (the ancestor with a VehicleId), else the seat's parent
local function seatVehicle(seat: Instance): Instance
	local m: Instance? = seat.Parent
	while m ~= nil and m ~= Workspace do
		if m:GetAttribute("VehicleId") ~= nil then
			return m
		end
		m = m.Parent
	end
	return seat.Parent or seat
end

local recoverProbeRec: Probe = { Params = recoverParams, Drop = 1, Half = 0.9 }

-- the recover probe for this owner this pass (FollowPath's ray rules): every squad, every character and the vehicle he
-- sits in are ignored; the ignore list is refilled at most once per owner per pass
local function recoverProbe(player: Player, playerRoot: BasePart, now: number): Probe
	if recoverFor ~= player or recoverForAt ~= now then
		recoverFor = player
		recoverForAt = now
		table.clear(recoverIgnore)
		table.insert(recoverIgnore, ensureFolder())
		for _, p in ipairs(Players:GetPlayers()) do
			local character = p.Character
			if character then
				table.insert(recoverIgnore, character)
			end
		end
		local hum = if playerRoot.Parent then playerRoot.Parent:FindFirstChildOfClass("Humanoid") else nil
		local seat = if hum then hum.SeatPart else nil
		if seat then
			table.insert(recoverIgnore, seatVehicle(seat))
		end
		recoverParams.FilterDescendantsInstances = recoverIgnore -- the property takes a copy of the list
		local cfg = followPathCfg()
		recoverProbeRec.Drop = if cfg then cfgNum(cfg, "RayDrop", 1) else 1
		recoverProbeRec.Half = if cfg then cfgNum(cfg, "RayHalfWidth", 0.9) else 0.9
	end
	return recoverProbeRec
end

-- the ground under a candidate spot: a ProbeDown ray from 1 stud above it must hit a solid part or terrain that is not
-- water (terrain water, a WE_Water part, or ground under a WE_Water surface); nil otherwise (air, void, water)
local function recoverGround(spot: Vector3, rc: { [string]: any }, probe: Probe, now: number): number?
	local hit = Workspace:Raycast(spot + Vector3.new(0, 1, 0), Vector3.new(0, -(cfgNum(rc, "ProbeDown", 12) + 1), 0), probe.Params)
	if hit == nil or hit.Material == Enum.Material.Water or CollectionService:HasTag(hit.Instance, Constants.Tags.Water) then
		return nil
	end
	local y = hit.Position.Y
	if underWater(spot.X, y, spot.Z, now) then
		return nil
	end
	return y
end

-- is the owner on water (swimming, a boat)? One ray, at most once per owner per pass, only when a unit would recover
local function ownerOnWater(player: Player, st: SquadState, playerRoot: BasePart, rc: { [string]: any }, now: number): boolean
	if st.WaterAt == now then
		return st.OnWater
	end
	st.WaterAt = now
	local wet = false
	local hum = if playerRoot.Parent then playerRoot.Parent:FindFirstChildOfClass("Humanoid") else nil
	if hum and hum.FloorMaterial == Enum.Material.Water then
		wet = true
	else
		local probe = recoverProbe(player, playerRoot, now)
		local p = playerRoot.Position
		local hit = Workspace:Raycast(p, Vector3.new(0, -(cfgNum(rc, "ProbeDown", 12) + 4), 0), probe.Params)
		if hit then
			wet = hit.Material == Enum.Material.Water or CollectionService:HasTag(hit.Instance, Constants.Tags.Water) or underWater(p.X, hit.Position.Y, p.Z, now)
		else
			wet = underWater(p.X, p.Y - 3, p.Z, now)
		end
	end
	st.OnWater = wet
	return wet
end

local function nearOtherPlayer(player: Player, pos: Vector3, r: number): boolean
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			local root = characterRoot(p)
			if root and (root.Position - pos).Magnitude <= r then
				return true
			end
		end
	end
	return false
end

-- a recover landing of this army within LandApartStuds of `spot` in the last LandApartSeconds, or one of its units
-- standing there now: units never land on one another (no pile-up, no physics fling). At most LAND_RING + MaxFieldUnits
-- distance checks, no allocation.
local function landingTaken(st: SquadState, unit: SquadUnit, spot: Vector3, rc: { [string]: any }, now: number): boolean
	local r = cfgNum(rc, "LandApartStuds", 3)
	local win = cfgNum(rc, "LandApartSeconds", 2)
	for i = 1, LAND_RING do
		if now - st.LandAt[i] <= win and flatDist(st.LandPos[i], spot) < r then
			return true
		end
	end
	for _, u in ipairs(st.Units) do
		if u ~= unit and u.Alive and u.Root.Parent ~= nil and flatDist(u.Root.Position, spot) < r then
			return true
		end
	end
	return false
end

local function noteLanding(st: SquadState, at: Vector3, now: number)
	local i = st.LandI % LAND_RING + 1
	st.LandI = i
	st.LandPos[i] = at
	st.LandAt[i] = now
end

-- one recover candidate: its stand CFrame (facing `look`) when clear, else nil; the second result is true when the
-- spot was clear but within NoPlayerWithin of another player. Clear: outside every plot but his own (inside his own
-- while he stands in it: never beyond his own wall and gate), not where
-- another unit of his landed or stands (landingTaken), ground under it (recoverGround), the FollowPath body probe from
-- his root reaches it AND one ray at root height does too (a closed gate barrier, or anything else with a raised
-- underside, blocks the knee band's view no more).
local function tryRecoverSpot(player: Player, st: SquadState, unit: SquadUnit, spot: Vector3, from: Vector3, ownPlot: number?, ownerHome: boolean, look: Vector3, rc: { [string]: any }, probe: Probe, now: number): (CFrame?, boolean)
	local pid = plotAt(spot)
	if pid ~= ownPlot and (pid ~= nil or ownerHome) then
		return nil, false -- never into another plot; while he is inside his own plot, never outside it
	end
	if landingTaken(st, unit, spot, rc, now) then
		return nil, false
	end
	local gy = recoverGround(spot, rc, probe, now)
	if gy == nil then
		return nil, false
	end
	local at = Vector3.new(spot.X, gy + cfgNum(rc, "StandHeight", 3.2), spot.Z)
	if not bodyClear(from, at, probe) or Workspace:Raycast(from, at - from, probe.Params) ~= nil then
		return nil, false
	end
	if nearOtherPlayer(player, at, cfgNum(rc, "NoPlayerWithin", 25)) then
		return nil, true
	end
	return CFrame.lookAt(at, at + look), false
end

--[[ where a recovered unit goes: the first CLEAR candidate (tryRecoverSpot) of
	1. its slot, when that is BehindStuds behind the owner's facing or out of his sight;
	2. the owner's trail points at least BehindStuds from him and not ahead of him (newest first, at most TrailMaxStuds
	   away, at most MaxTrailTries of them);
	3. BehindStuds (+ its slot depth) behind him along his facing, then back-right and back-left, then the same three
	   NearBehindStuds from him;
	4. BehindStuds left and right of him: with SideNeedsCover only when his head cannot see the spot, else the unit
	   waits (second result true) for a better one, at most MaxDeferSeconds.
	Every candidate but the slot is moved by the unit's own slot offset (SpreadScale x its side offset sideways, its
	slot depth further back), and landingTaken skips spots another unit of his took: units land apart. A spot
	BehindStuds away and not ahead of the player is outside a phone's landscape view (the camera stands about 12
	behind him): units run in and never pop up in front of him. At most MaxTries candidates (4 rays each). A clear spot
	too near another player defers the unit (second result true) until MaxDeferSeconds have passed, then such spots are
	skipped. ]]
local function recoverSpot(player: Player, st: SquadState, unit: SquadUnit, playerRoot: BasePart, rc: { [string]: any }, now: number): (CFrame?, boolean)
	local probe = recoverProbe(player, playerRoot, now)
	local ppos = playerRoot.Position
	local lv = playerRoot.CFrame.LookVector
	local look = Vector3.new(lv.X, 0, lv.Z)
	look = if look.Magnitude > 0.05 then look.Unit else Vector3.new(0, 0, -1)
	local right = Vector3.new(-look.Z, 0, look.X)
	local behind = cfgNum(rc, "BehindStuds", 24)
	local offset = unitOffset(st, unit.Slot)
	local own = right * (offset.X * cfgNum(rc, "SpreadScale", 0.7)) - look * math.max(offset.Z, 0)
	local waitOver = unit.DeferSince ~= nil and now - (unit.DeferSince :: number) >= cfgNum(rc, "MaxDeferSeconds", 10)
	local head = ppos + Vector3.new(0, 1.5, 0)
	local cands: { Vector3 } = {} -- (a recover is rare: this list is not a per-think allocation)
	local slotPos = (playerRoot.CFrame * CFrame.new(offset)).Position
	if (slotPos - ppos):Dot(look) <= -behind then
		table.insert(cands, slotPos)
	elseif Workspace:Raycast(head, slotPos - head, probe.Params) ~= nil then
		table.insert(cands, slotPos) -- out of his sight
	end
	local trail = trailByUser[player.UserId]
	if trail then
		local maxTrail = cfgNum(rc, "TrailMaxStuds", 60)
		local maxPts = math.max(0, math.floor(cfgNum(rc, "MaxTrailTries", 4)))
		local used = 0
		for i = #trail.Points, 1, -1 do
			if used >= maxPts then
				break
			end
			local pt = trail.Points[i]
			local fd = flatDist(pt, ppos)
			if fd >= behind and fd <= maxTrail and (pt - ppos):Dot(look) <= 0 then
				table.insert(cands, pt + own)
				used += 1
			end
		end
	end
	local diag = (look + right).Unit
	local diag2 = (look - right).Unit
	table.insert(cands, ppos - look * behind + own)
	table.insert(cands, ppos - diag2 * behind + own) -- back-right
	table.insert(cands, ppos - diag * behind + own) -- back-left
	local nearB = cfgNum(rc, "NearBehindStuds", 14)
	if nearB > 0 and nearB < behind then
		-- (the same three nearer in: a spot behind him in a walled yard or a street)
		table.insert(cands, ppos - look * nearB + own)
		table.insert(cands, ppos - diag2 * nearB + own)
		table.insert(cands, ppos - diag * nearB + own)
	end
	local firstSide = #cands + 1
	table.insert(cands, ppos - right * behind + own) -- left
	table.insert(cands, ppos + right * behind + own) -- right
	local sideCover = rc.SideNeedsCover == true
	local ownPlot = ownPlotId(player)
	local ownerHome = ownPlot ~= nil and plotAt(ppos) == ownPlot
	local tries = math.max(1, math.floor(cfgNum(rc, "MaxTries", 12)))
	local waiting = false
	for i, spot in ipairs(cands) do
		if i > tries then
			break
		end
		local cf, near = tryRecoverSpot(player, st, unit, spot, ppos, ownPlot, ownerHome, look, rc, probe, now)
		if cf then
			if i >= firstSide and sideCover and not waitOver then
				local at = (cf :: CFrame).Position
				if Workspace:Raycast(head, at - head, probe.Params) == nil then
					waiting = true -- beside him and in his view: wait for a spot behind him
					cf = nil
				end
			end
			if cf then
				return cf, false
			end
		elseif near and not waitOver then
			return nil, true
		end
	end
	return nil, waiting
end

-- the WE_ArmyRecover counter on the owner (tests, the Studio explorer) + at most one log line per owner per LogSeconds
local function noteRecover(player: Player, st: SquadState, why: string, rc: { [string]: any }, now: number)
	local n = player:GetAttribute("WE_ArmyRecover")
	player:SetAttribute("WE_ArmyRecover", (if typeof(n) == "number" then n else 0) + 1)
	st.RecoverLogN += 1
	if now - st.RecoverLogAt >= cfgNum(rc, "LogSeconds", 30) then
		print(string.format("[WAR EMPIRE] SquadOrdersService: moved %d unit(s) of %s back behind them since the last line (latest: %s)", st.RecoverLogN, player.Name, why))
		st.RecoverLogAt = now
		st.RecoverLogN = 0
	end
end

-- army fix (ArmyConfig.Loop): a recover search / move error is logged at most once per owner per Loop.ErrorLogSeconds
-- (the unit's CooldownSeconds alone would let one broken owner write a line a second)
local function recoverWarn(uid: number, now: number, what: string, err: any)
	local lp = (ArmyConfig :: any).Loop
	local every = if typeof(lp) == "table" then tonumber(lp.ErrorLogSeconds) or 30 else 30
	if now - (recoverErrAt[uid] or -math.huge) >= every then
		recoverErrAt[uid] = now
		warn(string.format("[WAR EMPIRE] SquadOrdersService: %s for %d: %s", what, uid, tostring(err)))
	end
end

--[[ RECOVER one FOLLOW unit, once per think before its move. Triggers: fallen (root below FallY), far (more than
	FollowFarStuds from the owner for FollowFarSeconds), regroup (a fast drive ended with it more than
	VehicleRegroupStuds away), stuck (less than ProgressStuds toward its goal in StuckSeconds while more than
	StuckMinOwnerStuds from him) and plot (more than PlotMinOwnerStuds from him inside a plot square another player
	owns, for PlotSeconds, while he has been out of it that long). Limits: nothing while he drives faster than
	VehicleDeferSpeed (the far timer runs on, so it goes as soon as he stops) or is on water; one try per unit per
	CooldownSeconds; at most PerOwnerPerSecond searches per owner (the rest wait a think). The move
	is ONE Model:PivotTo of the same unit: never Destroy, never SyncArmy. Chase / give-up / trail state is reset and a
	MoveTo re-issued. Returns true when it moved the unit this think. ]]
local function recoverUnit(player: Player, st: SquadState, unit: SquadUnit, playerRoot: BasePart, now: number): boolean
	local rc = recoverCfg()
	if rc == nil then
		return false
	end
	local pos = unit.Root.Position
	local ppos = playerRoot.Position
	local d = flatDist(pos, ppos)
	-- stuck: the studs it made since the last think along the direction to its goal then (trackGoal)
	local lp, dir = unit.ProgPos, unit.ProgDir
	local stuck = false
	if lp ~= nil and dir ~= nil then
		local moved = pos - lp
		unit.ProgSum += moved.X * dir.X + moved.Z * dir.Z
		if unit.ProgSum >= cfgNum(rc, "ProgressStuds", 2) then
			unit.ProgSince = now
			unit.ProgSum = 0
		else
			stuck = now - unit.ProgSince >= cfgNum(rc, "StuckSeconds", 4)
		end
	else
		unit.ProgSince = now
		unit.ProgSum = 0
	end
	if d > cfgNum(rc, "FollowFarStuds", 80) then
		if unit.FarSince == nil then
			unit.FarSince = now
		end
	else
		unit.FarSince = nil
	end
	-- plot: only a unit well away from him (PlotMinOwnerStuds) that has stood in that foreign plot for PlotSeconds
	-- while he has been out of it that long (a squad at his side at another plot's edge or gate is left alone)
	local plotMin = cfgNum(rc, "PlotMinOwnerStuds", 30)
	local plotSec = cfgNum(rc, "PlotSeconds", 4)
	local inForeign: number? = nil
	if d > plotMin then
		local pid = plotAt(pos)
		if pid ~= nil then
			local owner = plotOwnerId(pid)
			if owner ~= nil and owner ~= player.UserId then
				inForeign = pid
			end
		end
	end
	if inForeign == nil then
		unit.PlotId = nil
	elseif unit.PlotId ~= inForeign then
		unit.PlotId = inForeign
		unit.PlotSince = now
	end
	local why: string? = nil
	if pos.Y < cfgNum(rc, "FallY", -50) then
		why = "fallen"
	elseif unit.FarSince ~= nil and now - (unit.FarSince :: number) >= cfgNum(rc, "FollowFarSeconds", 4) then
		why = "far"
	elseif st.RegroupAt ~= nil and d > cfgNum(rc, "VehicleRegroupStuds", 150) then
		why = "regroup"
	elseif stuck and d > cfgNum(rc, "StuckMinOwnerStuds", 25) then
		why = "stuck" -- lane A (ArmyPath) asks for a path here first; RECOVER only when that fails or stalls
	elseif
		inForeign ~= nil
		and now - unit.PlotSince >= plotSec
		and st.OwnerPlot ~= inForeign
		and not (st.OwnerPlotLeft == inForeign and now - st.OwnerPlotLeftAt < plotSec)
	then
		why = "plot"
	end
	if why == nil then
		unit.DeferSince = nil
		return false
	end
	if st.Seated and st.OwnerSpeed > cfgNum(rc, "VehicleDeferSpeed", 20) then
		return false
	end
	local cooldown = cfgNum(rc, "CooldownSeconds", 8)
	if now - unit.RecoverAt < cooldown then
		return false
	end
	if now - st.RecoverWinAt >= 1 then
		st.RecoverWinAt = now
		st.RecoverWinN = 0
	end
	if st.RecoverWinN >= math.max(1, math.floor(cfgNum(rc, "PerOwnerPerSecond", 4))) then
		return false
	end
	if ownerOnWater(player, st, playerRoot, rc, now) then
		return false
	end
	st.RecoverWinN += 1 -- the budget counts searches (a failed or deferred one costs rays too), not only moves
	-- the search and the move are pcall'd: an error there must never stop the think loop (every army) for good
	local okS, cf, deferred = pcall(recoverSpot, player, st, unit, playerRoot, rc, now)
	if not okS then
		unit.RecoverAt = now
		recoverWarn(player.UserId, now, "recover search failed", cf)
		return false
	end
	if cf == nil then
		if deferred then
			if unit.DeferSince == nil then
				unit.DeferSince = now
			end
			unit.RecoverAt = now - cooldown + 1 -- a deferred unit looks again in 1 s
		else
			unit.DeferSince = nil
			-- no clear spot (e.g. every spot just taken by the others): it stays where it is and looks again after
			-- MissRetrySeconds (each search counts against PerOwnerPerSecond)
			unit.RecoverAt = now - cooldown + math.min(cooldown, cfgNum(rc, "MissRetrySeconds", 2))
		end
		return false
	end
	local at = cf :: CFrame
	unit.RecoverAt = now
	-- a fallen unit is compared in 3D (a spot straight above it under the map is a move); every other one flat
	local moveBy = if why == "fallen" then (at.Position - pos).Magnitude else flatDist(at.Position, pos)
	if moveBy < cfgNum(rc, "MinMoveStuds", 4) then
		-- army fix: the best clear spot is where it already stands (a stuck unit on a landing spot): no move, the
		-- stuck window starts over and it looks again after CooldownSeconds
		unit.DeferSince = nil
		unit.FarSince = nil
		unit.ProgSince = now
		unit.ProgSum = 0
		return false
	end
	local okM, errM = pcall(function()
		SquadOrdersService._SC.Reposition(unit, at, "recover", true) -- the same unit, moved: never Destroy, never a new model (v114: SoldierController)
		local gyro = unit.Root:FindFirstChild("NPCFaceGyro")
		if gyro and gyro:IsA("BodyGyro") then
			gyro.CFrame = at
		end
	end)
	if not okM then
		recoverWarn(player.UserId, now, "recover move failed", errM)
		return false
	end
	resetChase(unit)
	unit.AimRoot = nil
	unit.AimHum = nil
	unit.Crumb = nil
	unit.CrumbPos = nil
	unit.CrumbScanAt = 0
	unit.CrumbCheckAt = 0
	unit.FarSince = nil
	unit.DeferSince = nil
	unit.Goal = nil
	unit.ProgPos = nil
	unit.ProgDir = nil
	unit.ProgSum = 0
	unit.ProgSince = now
	unit.PlotId = nil
	SquadOrdersService._AF.Command(unit, at.Position)
	noteLanding(st, at.Position, now)
	noteRecover(player, st, why :: string, rc, now)
	return true
end

-- after the move: the goal it walks to now, for the next think's stuck check (no goal, or one within StuckGoalStuds:
-- it is not walking and the window starts over)
local function trackGoal(unit: SquadUnit, rc: { [string]: any }?)
	local g = unit.Goal
	if rc ~= nil and g ~= nil then
		local pos = unit.Root.Position
		local fx, fz = g.X - pos.X, g.Z - pos.Z
		local m = math.sqrt(fx * fx + fz * fz)
		if m > cfgNum(rc, "StuckGoalStuds", 4) then
			unit.ProgPos = pos
			unit.ProgDir = Vector3.new(fx / m, 0, fz / m)
			return
		end
	end
	unit.ProgPos = nil
	unit.ProgDir = nil
end

-- army fix (Recover.ReformRootless): SyncArmy (its not-living cull) re-forms a unit whose root or model left without
-- Humanoid.Died (it fell out of the world); one queued SyncArmy per owner per second, at most ReformPerMinute per owner
-- per minute, and only while he is alive with ground under him (SyncArmy spawns the new unit at him: one re-formed in
-- the air or over the void would fall again). One down ray, only when a unit needs it.
local function queueReform(player: Player, st: SquadState, now: number)
	local uid = player.UserId
	if (reformAt[uid] or -math.huge) > now then
		return
	end
	local rcv = (ArmyConfig :: any).Recover
	local rc: { [string]: any } = if typeof(rcv) == "table" then rcv else {}
	local root = characterRoot(player)
	if root == nil then
		return
	end
	local probe = recoverProbe(player, root, now)
	if recoverGround(root.Position - Vector3.new(0, 1, 0), rc, probe, now) == nil then
		return -- airborne, over the void or on water: wait
	end
	if now - st.ReformWinAt >= cfgNum(rc, "ReformWindowSeconds", 60) then
		st.ReformWinAt = now
		st.ReformWinN = 0
	end
	if st.ReformWinN >= math.max(1, math.floor(cfgNum(rc, "ReformPerMinute", 8))) then
		return
	end
	st.ReformWinN += 1
	local delaySec = math.max(0.1, cfgNum(rc, "ReformDelaySeconds", 1))
	reformAt[uid] = now + delaySec
	task.delay(delaySec, function()
		if player.Parent then
			SquadOrdersService.SyncArmy(player)
		end
	end)
end

-- army fix (ArmyConfig.Loop): the think loop caught an error for this owner: at most one warn per owner per
-- Loop.ErrorLogSeconds (the loop goes on for every other unit and army)
local function thinkError(player: Player, err: any, now: number)
	local lp = (ArmyConfig :: any).Loop
	local every = if typeof(lp) == "table" then tonumber(lp.ErrorLogSeconds) or 30 else 30
	local uid = player.UserId
	if now - (thinkErrAt[uid] or -math.huge) >= every then
		thinkErrAt[uid] = now
		warn(string.format("[SquadOrders] think error for %d (loop continues): %s", uid, tostring(err)))
	end
end

--[[ claude-bud JOB 24 (docs/ARMY-ATTACK-ROOTCAUSE.md): ATTACK with Follow3.AttackSteer (ArmyController.AttackLive).
	The ArmyController moves every unit (the steered block advances on the target, deploys into a line facing it at
	AttackStandoff, folds back into the follow block when the target is down or the order changes); here the squad
	gets ONE target and each unit only shoots and aims.
	  * pickSquadTarget (once per think pass): the hostiles this squad may hurt (nearestHostile's rules) within
	    AttackAggroStuds + AttackKeepExtraStuds of the army's centre and AttackLeashStuds of him; the current one kept
	    (FormationController.PickTarget: sticky, a switch only for one AttackRetargetStuds nearer), else the nearest.
	    Stored as st._acTarget (server-side NPC Humanoid + root; the client never names a target).
	  * attackAimOnly (per unit per think): when the gun is ready, the squad target if it is in its fire band and in
	    sight (squadfair: line of sight), else the nearest hostile in its band it can see (pickShot); it faces what it
	    shoots. It never walks: no ring seats, no chase, no MoveTo from here. ]]
local function pickSquadTarget(player: Player, st: SquadState, proot: BasePart)
	local f3 = (ArmyConfig :: any).Follow3
	local reach = (tonumber(f3.AttackAggroStuds) or 120) + (tonumber(f3.AttackKeepExtraStuds) or 20)
	local leash = tonumber(f3.AttackLeashStuds) or 140
	local sum, cnt = Vector3.zero, 0
	for _, u in ipairs(st.Units) do
		if u.Alive and u.Root.Parent then
			sum += Vector3.new(u.Root.Position.X, 0, u.Root.Position.Z)
			cnt += 1
		end
	end
	if cnt == 0 then
		(st :: any)._acTarget = nil
		return
	end
	local centre = sum / cnt
	nearestHostile(centre, reach, false, player, attackCands, reach)
	local cands: { { Key: any, Pos: Vector3 } } = {}
	local roots: { [any]: BasePart } = {}
	local function consider(h: Humanoid?, r: BasePart?)
		if h and r and h.Health > 0 and r.Parent ~= nil and not roots[h] and flatDist(r.Position, proot.Position) <= leash then
			roots[h] = r
			table.insert(cands, { Key = h, Pos = r.Position })
		end
	end
	for i = 1, attackCands.N do
		consider(attackCands.Hum[i], attackCands.Root[i])
	end
	local cur = (st :: any)._acTarget
	if cur and flatDist(cur.Root.Position, centre) <= reach then
		consider(cur.Hum, cur.Root) -- (the current one counts even when more than candCap() others are nearer)
	end
	candReset(attackCands) -- hold no reference to the NPCs between thinks
	local key = FormationController.PickTarget(if cur then cur.Hum else nil, cands, centre, f3)
	;(st :: any)._acTarget = if key and roots[key] then { Hum = key, Root = roots[key] } else nil
end

local function attackAimOnly(player: Player, st: SquadState, unit: SquadUnit, now: number)
	local tgt = (st :: any)._acTarget
	if tgt == nil or tgt.Root.Parent == nil or tgt.Hum.Health <= 0 then
		unit.AimRoot = nil
		unit.AimHum = nil
		return
	end
	local band = (OrdersConfig.AttackRange or 55) * 0.85 -- the fire band, as attackUnit
	if losCheckDue(unit, now) then
		nearestHostile(unit.Root.Position, band, false, player, attackCands, band) -- the in-band fallback candidates
		local th, troot, rays = pickShot(player, unit, tgt.Hum, tgt.Root, band, attackCands, CombatFairnessConfig.UnitAttackRequireLos == true)
		candReset(attackCands)
		if th and troot then
			unit.LosBlocked = false
			unit.AimRoot = if th ~= tgt.Hum then troot else nil
			unit.AimHum = if th ~= tgt.Hum then th else nil
			local firedAt = unit.LastFireAt
			local hit = unitShoot(player, unit, th, now, CombatFairnessConfig.UnitKillCreditOnAttack == true)
			unitShotFx(player, unit, troot, firedAt, hit)
		elseif rays > 0 then
			losBlockedFor(unit, now)
		end
	end
	faceYaw(unit.Root, aimPoint(unit, tgt.Root)) -- (the gyro; SoldierController leaves the aim alone after a shot)
end

local function reformRootless(uid: number): boolean
	local rc = (ArmyConfig :: any).Recover
	-- off with the Recover kill switch; v90: only for a Rollout.Fix owner
	-- v91: also for every ArmyFollow owner (a unit that lost its root is re-formed, never left as an invisible ghost)
	return (ArmyConfig.LiveFor("Fix", uid) or SquadOrdersService._AF.LiveFor(uid)) and typeof(rc) == "table" and rc.Enabled == true and rc.ReformRootless == true
end

local function thinkUnit(player: Player, st: SquadState, unit: SquadUnit, now: number, escortHum: Humanoid?, escortRoot: BasePart?, trail: Trail?, probe: Probe?)
	if unit.Alive and (unit.Model.Parent == nil or unit.Root.Parent ~= unit.Model) and reformRootless(player.UserId) then
		queueReform(player, st, now) -- army fix: it fell out of the world without dying
		return
	end
	if not unit.Alive or unit.Humanoid.Health <= 0 or not unit.Root.Parent then
		return
	end
	local order = st.Order
	local playerRoot = characterRoot(player)
	if order == "Attack" and SquadOrdersService._AC.AttackLive(player.UserId) then
		attackAimOnly(player, st, unit, now) -- claude-bud JOB 24: the ArmyController moves it; here it only shoots / aims
		return
	end
	if order ~= "Follow" then
		SquadOrdersService._AF.Release(unit, order) -- v99: HOLD / ATTACK / RETREAT drive it now (one controller per unit; JOB 22: its state)
		SquadOrdersService._PaceSpeed(unit, 0) -- v85 FollowPace: back to UnitWalkSpeed outside FOLLOW
	end

	if order == "Follow" then
		if not playerRoot then
			-- the owner is dead: units hold where they stand; army fix: the stuck window starts over once he is back
			unit.ProgPos = nil
			unit.ProgDir = nil
			return
		end
		if SquadOrdersService._AFOn and SquadOrdersService._AC.LiveFor(player.UserId) then
			-- v114 Follow3: ArmyController moves every FOLLOW unit (0.2 s tick); here the escort only shoots / aims
			escortAimOnly = true
			local okE, errE = pcall(escortUnit, player, st, unit, playerRoot, escortHum, escortRoot, now)
			escortAimOnly = false
			if not okE then
				error(errE)
			end
			return
		end
		if SquadOrdersService._AFOn then
			-- v91 ArmyFollow: the escort still shoots (and stands to fight only while he stands near a hostile outside his
			-- base); every walk, catch-up, regroup and the base wait line are ArmyFollow's
			local moving = SquadOrdersService._AF.OwnerMoving(st, st.OwnerSpeed) or st.Seated -- claude-bud JOB 22: hysteresis
			if not (st :: any)._afInBase then
				followCtx.Live = moving
				followCtx.Moving = moving
				local fought = escortUnit(player, st, unit, playerRoot, escortHum, escortRoot, now)
				followCtx.Live = false
				followCtx.Moving = false
				if fought and not moving then
					-- v99: the escort fight moved it (its own MoveTo): ArmyFollow lets go, and takes it back with fresh
					-- state (no stale goal / stuck window = no snap-back teleport right after the fight)
					SquadOrdersService._AF.Release(unit, "Combat") -- claude-bud JOB 22: the escort fight owns it (state Combat)
					return
				end
			end
			SquadOrdersService._AF.Unit(player, st, unit, playerRoot, now)
			return
		end
		if recoverUnit(player, st, unit, playerRoot, now) then -- army fix: far / stuck / fallen / plot / regroup
			return
		end
		if not escortUnit(player, st, unit, playerRoot, escortHum, escortRoot, now) then
			followMove(st, unit, playerRoot, trail, probe, now)
		end
		trackGoal(unit, recoverCfg()) -- army fix
		return
	end

	setSpeed(unit, OrdersConfig.UnitWalkSpeed or 14) -- army fix: every other order walks at the unit's own speed
	unit.ProgPos = nil
	unit.ProgDir = nil

	if order == "Hold" then
		if not unit.HoldPos then
			unit.HoldPos = unit.Root.Position
		end
		local leash = OrdersConfig.HoldLeashStuds or 14
		local holdPos = unit.HoldPos :: Vector3
		local dist = (unit.Root.Position - holdPos).Magnitude
		if dist > leash * 0.4 then
			SquadOrdersService._AF.Command(unit, holdPos)
		else
			SquadOrdersService._AF.Command(unit, unit.Root.Position)
		end
		return
	end

	if order == "Retreat" then
		local cf = plotRetreatCFrame(player)
		if cf then
			local dest = cf.Position
			local dist = (unit.Root.Position - dest).Magnitude
			if dist > 6 then
				SquadOrdersService._AF.Command(unit, dest)
				faceYaw(unit.Root, dest)
			else
				SquadOrdersService._AF.Command(unit, unit.Root.Position)
				unit.HoldPos = unit.Root.Position
			end
		elseif playerRoot then
			SquadOrdersService._AF.Command(unit, (playerRoot.CFrame * CFrame.new(0, 0, 8)).Position)
		end
		return
	end

	if order == "Attack" then
		attackUnit(player, st, unit, playerRoot, now, trail, probe)
		return
	end
end

--[[ army fix: once per pass per squad: the owner's flat velocity over the last pass (Follow.Lead; the CatchUp pace),
	the plot square he stands in (Recover plot trigger) and the end of a fast drive (Recover regroup: he stops below
	VehicleStopSpeed for VehicleStopSeconds, or gets out). No lead on a pass at under Lead.DropOnSlowdown x the pass
	before (he is stopping); the think loop clears it while a hostile is within Follow.ThreatStuds (st.Engaged). A
	jump faster than Lead.MaxOwnerSpeed on foot (teleport, respawn) gives no lead and pace 0; seated, the real speed is
	kept (the vehicle defer). No root (dead): no lead, pace 0, his last position kept. One Humanoid lookup, no rays. ]]
local function updateOwnerMotion(st: SquadState, root: BasePart?, now: number)
	local lead = Vector3.zero
	local speed = 0
	local seated = false
	local jumped = false
	local slowing = false
	if root then
		local hum = if root.Parent then root.Parent:FindFirstChildOfClass("Humanoid") else nil
		seated = hum ~= nil and (hum.Sit or hum.SeatPart ~= nil)
		local lp = st.LastPos
		local dt = now - st.LastAt
		if lp and dt > 0.05 and dt < 2 then
			local v = Vector3.new(root.Position.X - lp.X, 0, root.Position.Z - lp.Z) / dt
			speed = v.Magnitude
			local lc = followCfg("Lead")
			local maxOwner = if lc then cfgNum(lc, "MaxOwnerSpeed", 40) else 40
			if speed > maxOwner then
				if not seated then
					speed = 0 -- a jump, not a walk
				end
			elseif lc and speed >= st.PrevSpeed * cfgNum(lc, "DropOnSlowdown", 0.5) then
				-- (a pass at under DropOnSlowdown x the one before: he is stopping, no lead to overshoot on)
				lead = v * cfgNum(lc, "Seconds", 0.4)
				local cap = cfgNum(lc, "MaxStuds", 4)
				if lead.Magnitude > cap then
					lead = lead.Unit * cap
				end
			end
			slowing = lc ~= nil and speed <= maxOwner and speed < st.PrevSpeed * cfgNum(lc, "DropOnSlowdown", 0.5)
			st.PrevSpeed = v.Magnitude
			st.OwnerVel = v
			if speed >= 2 then
				st.WalkAt = now
			end
		end
		-- a jump on foot: he appeared more than FollowPath.ResetJump from where he last had a root (a teleport, a
		-- respawn at his plot, a fall rescue), however long that took
		local pc = followPathCfg()
		if lp and not seated and flatDist(root.Position, lp) > (if pc then cfgNum(pc, "ResetJump", 40) else 40) and (dt >= 2 or speed == 0) then
			jumped = true
		end
		st.LastPos = root.Position
		st.LastAt = now
	end
	st.Lead = lead
	st.Slowing = slowing
	st.OwnerSpeed = speed
	st.Seated = seated
	-- ship (Follow.CatchUp.PaceSmooth / PaceStep): the pace a follow unit walks at is his speed smoothed over a few passes
	-- and moved only in PaceStep steps. A client-owned character's replicated position jitters between network updates,
	-- and every Humanoid.WalkSpeed write replicates to every client (the FIX round-3 reviewers' OPENJIT: +-0.4 studs of
	-- jitter gave 20 writes/s per army). Below 1 stud/s (he stops) the pace drops at once; a change bigger than
	-- PaceJumpStuds passes at once too (no smoothing lag behind a real start or sprint: that made catch-up runs).
	local cuP = followCfg("CatchUp")
	local alpha = if cuP then math.clamp(cfgNum(cuP, "PaceSmooth", 1), 0.05, 1) else 1
	local step = if cuP then math.max(0, cfgNum(cuP, "PaceStep", 0)) else 0
	local jump = if cuP then math.max(0, cfgNum(cuP, "PaceJumpStuds", 0)) else 0
	st.PaceAvg = if speed < 1 or st.PaceAvg < 1 or math.abs(speed - st.PaceAvg) > jump then speed else st.PaceAvg + (speed - st.PaceAvg) * alpha
	if step <= 0 or st.PaceAvg < 1 or math.abs(st.PaceAvg - st.PaceSpeed) >= step then
		st.PaceSpeed = st.PaceAvg
	end
	local rc = recoverCfg()
	if rc == nil then
		st.FastAt = nil
		st.SlowSince = nil
		st.RegroupAt = nil
		return
	end
	if jumped then
		st.RegroupAt = now -- a teleport / respawn / fall rescue: far units regroup now (no FollowFarSeconds wait)
	end
	if root then
		local op = plotAt(root.Position)
		if op ~= st.OwnerPlot then
			if st.OwnerPlot ~= nil then
				st.OwnerPlotLeft = st.OwnerPlot
				st.OwnerPlotLeftAt = now
			end
			st.OwnerPlot = op
		end
	end
	if seated and speed > cfgNum(rc, "VehicleDeferSpeed", 20) then
		st.FastAt = now
		st.SlowSince = nil
		st.RegroupAt = nil
	elseif st.FastAt ~= nil then
		if not seated then
			st.RegroupAt = now -- he got out
			st.FastAt = nil
			st.SlowSince = nil
		elseif speed < cfgNum(rc, "VehicleStopSpeed", 6) then
			local since = st.SlowSince or now
			st.SlowSince = since
			if now - since >= cfgNum(rc, "VehicleStopSeconds", 1.5) then
				st.RegroupAt = now -- he stopped
				st.FastAt = nil
				st.SlowSince = nil
			end
		else
			st.SlowSince = nil
		end
	end
	local rg = st.RegroupAt
	if rg ~= nil and now - rg > cfgNum(rc, "RegroupWindowSeconds", 10) then
		st.RegroupAt = nil
	end
end


-- lane C: a new unit appears in its slot; when a wall stands between the player and that slot (e.g. recruiting
-- inside the Barracks), at the old grid spot behind the player, else on the player's trail, else in the slot as before
local function spawnCFrame(player: Player, st: SquadState, root: BasePart?, baseCf: CFrame, slot: number): CFrame
	local lift = Vector3.new(0, 2, 0)
	-- v114 (Follow3): a new unit spawns in its own formation cell (it does not walk across the formation to it)
	local off = if SquadOrdersService._AC.LiveFor(player.UserId) then SquadOrdersService._AC.SpawnOffset(slot) else unitOffset(st, slot)
	local slotCf = baseCf * CFrame.new(off) + lift
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

-- v85 FollowPace last resort: a live owner's unit more than TeleportStuds from him and out of his sight line (or more
-- than TeleportHardStuds either way) is put back in its slot beside him with the recruit spawn rules (spawnCFrame: never
-- inside a wall), at most once per TeleportCooldown s per unit. Called only while followCtx.Live (on foot, FOLLOW).
function SquadOrdersService._PaceRecover(player: Player, st: SquadState, unit: SquadUnit, proot: BasePart, now: number): boolean
	if not unit.Alive or unit.Humanoid.Health <= 0 or not unit.Root.Parent then
		return false
	end
	local c = (ArmyCfg :: any).FollowPace
	local d = flatDist(unit.Root.Position, proot.Position)
	if d <= (tonumber(c.TeleportStuds) or 70) then
		return false
	end
	local at = followCtx.TpAt[unit]
	if at ~= nil and now < at then
		return false
	end
	if d <= (tonumber(c.TeleportHardStuds) or 140) then
		local eye = proot.Position + Vector3.new(0, 1.5, 0)
		local tgt = unit.Root.Position + Vector3.new(0, 1.5, 0)
		local ignore: { Instance } = { ensureFolder() }
		if proot.Parent then
			table.insert(ignore, proot.Parent)
		end
		followCtx.Ray.FilterDescendantsInstances = ignore
		if Workspace:Raycast(eye, tgt - eye, followCtx.Ray) == nil then
			return false -- he can see it: it keeps jogging (CatchUp / Sprint speed) instead of popping
		end
	end
	followCtx.TpAt[unit] = now + (tonumber(c.TeleportCooldown) or 4)
	local cf = spawnCFrame(player, st, proot, proot.CFrame, unit.Slot)
	SquadOrdersService._SC.Reposition(unit, cf, "pace-recover", true) -- v114: the one emergency PivotTo (moves + MoveTo)
	unit.Crumb = nil
	return true
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
			Lead = Vector3.zero,
			OwnerSpeed = 0,
			PaceAvg = 0,
			PaceSpeed = 0,
			LastPos = nil,
			LastAt = 0,
			Seated = false,
			FastAt = nil,
			SlowSince = nil,
			RegroupAt = nil,
			WaterAt = -math.huge,
			OnWater = false,
			RecoverWinAt = -math.huge,
			RecoverWinN = 0,
			RecoverLogAt = -math.huge,
			RecoverLogN = 0,
			PrevSpeed = 0,
			Engaged = false,
			OwnerPlot = nil,
			OwnerPlotLeft = nil,
			OwnerPlotLeftAt = -math.huge,
			LandPos = table.create(LAND_RING, Vector3.zero),
			LandAt = table.create(LAND_RING, -math.huge),
			LandI = 0,
			ReformWinAt = -math.huge,
			ReformWinN = 0,
			WalkAt = -math.huge,
			OwnerVel = Vector3.zero,
			Slowing = false,
		}
		squadByUser[player.UserId] = st
	end
	st.DesiredCount = desired

	local living: { SquadUnit } = {}
	local rootless = reformRootless(player.UserId) -- army fix: a unit whose root left its model is not living (it is re-formed)
	for _, u in ipairs(st.Units) do
		if u.Alive and u.Model.Parent and (not rootless or u.Root.Parent == u.Model) and u.Humanoid.Health > 0 then
			table.insert(living, u)
		else
			-- v91: every removal is logged with its reason
			SquadOrdersService._AF.LogRemoval(u, if not u.Alive or u.Humanoid.Health <= 0 then "died" elseif not u.Model.Parent then "model gone" else "lost its root (fell out of the world)")
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
			SquadOrdersService._AF.LogRemoval(u, "fewer soldiers than units (trim)") -- v91
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
	-- claude-bud JOB 7: the first ATTACK ends the first-minutes hint (TutorialService saves it)
	do
		local okT, tut = pcall(function(): any
			return require(script.Parent.TutorialService)
		end)
		if okT and tut and tut.OnArmyOrder then
			pcall(tut.OnArmyOrder, player, order)
		end
	end
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
			u.FarSince = nil -- army fix: a new order starts the recover windows over
			u.PlotId = nil
			u.ProgPos = nil
			u.ProgDir = nil
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

-- army fix (ArmyConfig.Gate): may this owner's army open his gate at `pos`? Only while his squad FOLLOWS him (never
-- Hold / Attack / Retreat), he is alive and within `ownerStuds` (flat) of `pos`, and a living unit of his is within
-- `radius` (flat) and `height` of it. Ship: with `normal` (the barrier plane's normal, e.g. the gate CFrame's LookVector)
-- a unit counts only until it has crossed: while it is NOT more than `crossClear` studs past the plane on his side
-- (Gate.CrossClearStuds 0: only units still on the far side; units already through, or standing in their slots on his
-- side, never hold it open: a raider tailing him home or camping at the gate meets a shut gate). GateDefenseService
-- also caps how long units alone keep it open (Gate.UnitHoldSeconds after the last owner / ally player). At most
-- MaxFieldUnits distance checks, no allocation, no rays.
function SquadOrdersService.AnyUnitNear(userId: number, pos: Vector3, radius: number, height: number, ownerStuds: number?, normal: Vector3?, crossClear: number?): boolean
	local st = squadByUser[userId]
	if st == nil or st.Order ~= "Follow" then
		return false
	end
	local owner = Players:GetPlayerByUserId(userId)
	local oroot = if owner then characterRoot(owner) else nil
	if oroot == nil then
		return false -- he is dead or gone: his units never hold the gate
	end
	local near = ownerStuds or 40
	local op = oroot.Position
	local ox, oz = op.X - pos.X, op.Z - pos.Z
	if ox * ox + oz * oz > near * near then
		return false
	end
	-- ship (crossing rule): his side of the barrier plane; a unit past it on his side by more than crossClear has crossed
	local nx, nz, side = 0, 0, 0
	if normal ~= nil then
		local m = math.sqrt(normal.X * normal.X + normal.Z * normal.Z)
		if m > 1e-3 then
			nx, nz = normal.X / m, normal.Z / m
			local so = ox * nx + oz * nz
			side = if so >= 0 then 1 else -1
		end
	end
	local clear = crossClear or 0
	local r2 = radius * radius
	for _, u in ipairs(st.Units) do
		if u.Alive and u.Root.Parent == u.Model and u.Humanoid.Health > 0 then
			local p = u.Root.Position
			local dx, dz = p.X - pos.X, p.Z - pos.Z
			if dx * dx + dz * dz <= r2 and math.abs(p.Y - pos.Y) <= height and (side == 0 or (dx * nx + dz * nz) * side <= clear) then
				return true
			end
		end
	end
	return false
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
	SquadOrdersService._AF.EnsureGroup() -- v99: the ArmyNPCs collision group exists before the first unit spawns
	SquadOrdersService._AF.Bind({ -- v91 ArmyFollow
		Folder = ensureFolder,
		OwnPlotId = ownPlotId,
		UnitWalkSpeed = function()
			return OrdersConfig.UnitWalkSpeed or 14
		end,
	})
	SquadOrdersService._AC.Start({ -- v114 Follow3: the one FOLLOW controller (its own 0.2 s tick)
		Squads = function()
			return squadByUser
		end,
		CharacterRoot = characterRoot,
		UnitWalkSpeed = function()
			return OrdersConfig.UnitWalkSpeed or 14
		end,
	})

	local orderRemote = RemoteSetup.Get(Constants.RemoteNames.RequestSquadOrder) :: RemoteEvent
	orderRemote.OnServerEvent:Connect(function(player: Player, orderId: any)
		if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestSquadOrder", orderId) then -- claude-bud JOB 15: rate ceiling + argument schema
			return
		end
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
		reformAt[player.UserId] = nil -- army fix
		thinkErrAt[player.UserId] = nil -- army fix
		recoverErrAt[player.UserId] = nil -- army fix
		if recoverFor == player then -- army fix: the recover probe holds no Player / Character / vehicle after he leaves
			recoverFor = nil
			recoverForAt = -math.huge
			table.clear(recoverIgnore)
			recoverParams.FilterDescendantsInstances = {}
		end
	end)

	task.spawn(function()
		while true do
			local interval = OrdersConfig.ThinkInterval or 0.4
			task.wait(interval)
			local now = os.clock()
			refillHostiles() -- army lane A0: one NPC list for this pass
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
				SquadOrdersService._FixLive = st ~= nil and ArmyConfig.LiveFor("Fix", player.UserId) -- v90: Rollout.Fix
				SquadOrdersService._AFOn = st ~= nil and SquadOrdersService._AF.LiveFor(player.UserId) -- v91: ArmyConfig.Follow2
				if SquadOrdersService._AFOn then
					SquadOrdersService._FixLive = false -- v91: ArmyFollow replaces the v90 Fix follow / recover
				end
				if st and #st.Units > 0 then
					local okM, errM = pcall(updateOwnerMotion :: any, st, proot, now) -- army fix: Follow.Lead / CatchUp pace / Recover regroup
					if not okM then
						thinkError(player, errM, now)
					end
					-- P1-4 escort: one hostile pick per player per pass (nearest to the player); squadfair: plus the
					-- hostiles near the player for the visible-target fallback (escortCands), only ones this squad may hurt
					local escortHum: Humanoid?, escortRoot: BasePart? = nil, nil
					-- army fix (Follow.ThreatStuds): the FOLLOW escort pick's one scan (either pick below) also finds the
					-- nearest hostile out to ThreatStuds (the escort target and escortCands are unchanged); near it the
					-- army follows as at e506c9c
					local threat = if st.Order == "Follow" and proot then threatStuds() else 0
					threatScanStuds = threat
					-- v85 FollowPace: live only for a Rollout.Army owner on foot in FOLLOW
					if not (st.Order == "Follow" and proot and not SquadOrdersService._AFOn and SquadOrdersService._PaceBegin(player, proot)) then
						followCtx.Live = false
						followCtx.Moving = false
					end
					escortLive = false -- army lane A0: today's escort unless Rollout.Escort is live for this owner
					escortLeash = CombatFairnessConfig.EscortLeash
					if st.Order == "Follow" and proot then
						local r = CombatFairnessConfig.EscortEngageRadius
						if ArmyCfg.LiveFor("Escort", player.UserId) then
							local defending = false
							escortLive = true
							escortHum, escortRoot, defending = escortPickLive(player, proot)
							if defending then
								escortLeash = math.max(tonumber(ArmyCfg.Escort.DefendLeash) or escortLeash, escortLeash)
							end
						else
							escortHum, escortRoot = nearestHostile(proot.Position, r, CombatFairnessConfig.EscortIgnoreCalm == true, player, escortCands, r)
						end
						threatScanStuds = 0
						local trt = threatNearRoot
						threatNearRoot = nil -- hold no reference to the NPC between passes
						st.Engaged = threat > 0 and trt ~= nil and not (threatApproachOnly() and st.OwnerSpeed >= 1 and st.OwnerVel:Dot((trt :: BasePart).Position - proot.Position) < 0)
							and not (ArmyConfig.ThreatStandingFor(player.UserId) and st.OwnerSpeed >= 1)
						if st.Engaged then
							st.Lead = Vector3.zero -- e506c9c follow near a hostile: no lead (followSpeed: UnitWalkSpeed)
						end
						updateMirror(st, proot.CFrame)
					else
						st.Engaged = false
					end
					-- lane C FollowPath (squadfair: also ATTACK once a unit has given up a chase: it walks the trail)
					if (st.Order == "Follow" or (st.Order == "Attack" and anyGaveUp(st))) and proot and pathCfg and probe == nil then
						probe = buildProbe(pathCfg)
					end
					-- claude-bud JOB 24: the squad's ONE attack target (sticky), before any unit thinks
					if st.Order == "Attack" and proot and SquadOrdersService._AC.AttackLive(player.UserId) then
						local okP, errP = pcall(pickSquadTarget :: any, player, st, proot)
						if not okP then
							(st :: any)._acTarget = nil
							thinkError(player, errP, now)
						end
					else
						(st :: any)._acTarget = nil
					end
					for _, unit in ipairs(st.Units) do
						-- army fix (ArmyConfig.Loop): an error in one unit's think never stops the loop for every army
						local okT, errT = pcall(thinkUnit :: any, player, st, unit, now, escortHum, escortRoot, trail, probe)
						if not okT then
							thinkError(player, errT, now)
						end
					end
					if followCtx.Live and proot then
						for _, unit in ipairs(st.Units) do
							SquadOrdersService._PaceRecover(player, st, unit, proot, now) -- v85 FollowPace last resort
						end
					end
					followCtx.Live = false
					followCtx.Moving = false
					candReset(escortCands) -- hold no reference to the NPCs between passes
				end
				SquadOrdersService._FixLive = false
				SquadOrdersService._AFOn = false
			end
			SquadOrdersService._FixLive = false
			SquadOrdersService._AFOn = false
			hostileSnapValid = false -- army lane A0: the list is this pass's only (no NPC reference kept between passes)
			table.clear(hostileSnap)
		end
	end)

	print("[WAR EMPIRE] SquadOrdersService ready (Follow = escort/Attack/Hold/Retreat)")
end

return SquadOrdersService
