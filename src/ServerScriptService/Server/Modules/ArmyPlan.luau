--!strict
--[[
	claude-bud JOB 38 (2026-09-30): ARMY ORDER PLANS (ArmyOrdersConfig). Server only; one plan per owner.
	  * CLEAR (ATTACK, live owners): SEEK the nearest hostile group within SeekRadius of the owner (the ONE target pick:
	    SquadOrdersService pickSquadTarget with plan overrides, so the same hostility rule), MARCH to it, FIGHT it until
	    the group is gone (or out of reach / non-hostile), chain to the next within ChainRadius (MaxChain), then RETURN
	    and fold into FOLLOW.
	  * SEND (the map's SEND ARMY): the fairness verdict (ArmySendRules), MARCH to the victim's gate, SIEGE in
	    Siege.Priority order (turret -> guard -> gate -> inside guard -> ATM) with real shots through the existing damage
	    paths, the ATM hold (Raid.HoldSeconds, the lead unit not hit), the loot (MoneyCollectorService.ArmyRaid), RETURN.
	  * RECALL: any plan -> RETURN (march back, fold into FOLLOW).
	MOVEMENT: the plan owns a LEAD POINT. ArmyController steers the SAME formation block after it instead of the owner
	(ArmyController.PlanLead), so the block keeps Follow3's formation standard (rate-limited heading, SlotLateralSpeed,
	speed caps). The lead walks an ArmyRoute path at MarchSpeed and waits while the block is more than LeadMaxGap
	behind (the block goes at its slowest soldier's pace). During a plan NOTHING repositions a unit: ArmyController
	passes AllowRecover = false and NoReposition = true (SoldierController marks a unit that cannot follow LOST; this
	module reports it). No teleport, no PivotTo, no fast travel.
	The owner stays where he is; an owner-dead SEND keeps going while he is in the server (Send.RequireOwnerAlive).
Code Bot (army command bug, 2026-10-01): plans no longer write st.Order; every phase change goes through ArmyState.Set
(the one writer; opts.Plan = true) and the state the owner sees is the plan's: Attacking / EngagingTarget (CLEAR),
TravellingToBase / EngagingTarget (SEND to a base, TRAVEL to an area / site), Recalling (RETURN), Retreating (RETREAT).
New kinds: TRAVEL (StartTravel: the map's SEND to an area / site -> its ArmyTargets approach point -> clear the hostiles
there -> HOLD) and RETREAT (StartRetreat: a far army marches home as a block). ArmyPlan.Cancel ends a plan cleanly
(bound as ArmyState's CancelPlan: any non-plan state drops it). ProbeClear: the ATTACK target check before the order.
Code Bot v145 (owner phone test: "sending my army ... they don't go"): every route starts at the BLOCK (its centre), not
at the owner (from inside his walled base the closed gate gave NoPath: "No route" + HOLD); the lead is placed
ArmyController.Standoff studs along the route, and "the block is behind" is measured past that standoff (a block deeper
than LeadMaxGap never moved); RETURN goes to his gate spot while he is inside his base (or when he cannot be reached).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ArmyOrdersConfig = require(Shared.Configs.ArmyOrdersConfig)
local ArmyConfig = require(Shared.Configs.ArmyConfig)
local RaidConfig = require(Shared.Configs.RaidConfig)
local GameConfig = require(Shared.Configs.GameConfig)
local ArmyRoute = require(script.Parent.ArmyRoute)
local Rules = require(script.Parent.ArmySendRules)
local ArmyLog = require(Shared.Util.ArmyLog)
local ArmyState = require(script.Parent.ArmyState)
local ArmyTargets = require(script.Parent.ArmyTargets)
local ArmyCommand = require(script.Parent.ArmyCommand)

local ArmyPlan = {}

local C = ArmyOrdersConfig
local T = C.Text

export type Group = { Kind: string, GroupId: string?, Hum: any, Root: BasePart, Name: string, Player: Player? }
export type Plan = {
	Kind: string, -- "Clear" | "Send" | "Return" | "Travel" | "Retreat"
	Phase: string, -- "Seek" | "March" | "Fight" | "Siege" | "Loot" | "Return"
	Uid: number,
	Owner: Player,
	Gen: number,
	Lead: Vector3,
	LeadVel: Vector3,
	LeadLook: Vector3,
	LastAt: number,
	Dest: Vector3?,
	Route: { Vector3 }?,
	RouteIdx: number,
	Routing: boolean,
	RoutedAt: number,
	ProgPos: Vector3?,
	ProgAt: number,
	Group: Group?,
	GroupAlive: number,
	FightSince: number,
	Chain: number,
	Kills: number,
	SeekFrom: string, -- "owner" | "army"
	Bad: { [any]: boolean }, -- targets that had no route (skipped by the next seek)
	-- SEND
	Victim: Player?,
	VictimUid: number,
	VictimName: string,
	PlotId: number,
	Bully: boolean,
	SiegeAt: number?,
	Breached: boolean,
	Funnel: any?, -- v165: the broken gate a raid walks through (ArmyController.Funnel)
	NoLoot: string?,
	HoldUnit: any,
	HoldSince: number?,
	HoldHp: number,
	Looted: number,
	ThenOrder: string?,
	Total: number,
	Status: string,
	StatusAt: number,
	LostCount: number,
	Squad: any, -- Code Bot v145: the squad state (the block's centre / standoff for the route start and the gap)
	ReturnGate: boolean?, -- Code Bot v145: RETURN re-aimed at his gate spot (he is inside his walled base)
	Target: any, -- Code Bot (army command bug): TRAVEL's ArmyTargets target
	EngageSince: number?,
	ClearSince: number?,
	Anchor: Vector3?, -- CLEAR started away from him: the leash centre, and it HOLDS there when done (no march back)
	HoldWhenDone: boolean?,
	ThenState: string?, -- the state after finish (default Following)
	MoveLogAt: number?,
}

local deps: { [string]: any } = {}
local plans: { [number]: Plan } = {}
local probing: number? = nil -- Code Bot: ProbeClear's owner (AllowsNpcGroup lets the probe see what ATTACK would)
local logAt: { [string]: number } = {}
local clock: () -> number = os.clock
local gen = 0

local function live(uid: number): boolean
	return ArmyOrdersConfig.LiveFor(uid)
end

local function flatDist(a: Vector3, b: Vector3): number
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

local function debugOn(player: Player): boolean
	local ok, AC = pcall(function(): any
		return require(script.Parent.ArmyController)
	end)
	return ok and AC and AC.DebugFor and AC.DebugFor(player) == true
end

-- [ArmyPlan] / [ArmyRoute] / [ArmyMarch] / [ArmySiege] / [ArmyFair]: /armydebug owners only, rate-limited per tag
local function dbg(player: Player, tag: string, text: string, force: boolean?)
	if not debugOn(player) then
		return
	end
	local key = tostring(player.UserId) .. tag
	local now = clock()
	if not force and now - (logAt[key] or -math.huge) < C.DebugLogSeconds then
		return
	end
	logAt[key] = now
	print(string.format("[%s] %s %s", tag, player.Name, text))
end

local function notify(player: Player?, text: string, kind: string?)
	local ns = deps.NotificationService
	if player and player.Parent and ns and ns.Notify then
		pcall(ns.Notify, player, text, kind or "Info", 4)
	end
end

local function ownerRoot(player: Player): BasePart?
	local c = player.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if r and r:IsA("BasePart") and h and h.Health > 0 then
		return r
	end
	return nil
end

local function profileOf(p: Player): any
	return deps.DataService and deps.DataService.GetProfile(p)
end

local function raidOf(profile: any): any
	if typeof(profile.Raid) ~= "table" then
		profile.Raid = {}
	end
	return profile.Raid
end

local function livingUnits(st: any): ({ any }, Vector3?)
	local out = {}
	local sum, n = Vector3.zero, 0
	for _, u in ipairs(st.Units) do
		if u.Alive and u.Humanoid and u.Humanoid.Health > 0 and u.Root and u.Root.Parent then
			table.insert(out, u)
			sum += u.Root.Position
			n += 1
		end
	end
	return out, if n > 0 then sum / n else nil
end

-- ── the lead point and the route ─────────────────────────────────────────────────────────────────────────────────
-- Code Bot v145: how far behind the lead the steered block holds its centre by design (ArmyController.Standoff:
-- FirstRowStuds + half its depth, at least its radius + BubbleStuds; 0 before it formed / in the unit tests)
local function standoffOf(st: any): number
	if st == nil then
		return 0
	end
	local ok, v = pcall(function(): any
		local AC = require(script.Parent.ArmyController) :: any
		return AC.Standoff(st)
	end)
	return if ok and typeof(v) == "number" and v == v then math.max(0, v) else 0
end

-- the block's centre (its living units' mean), or nil
local function blockCentre(st: any): Vector3?
	if st == nil or typeof(st.Units) ~= "table" then
		return nil
	end
	local _, c = livingUnits(st)
	return c
end

--[[ Code Bot v145 (owner: "sending my army ... they don't go"): the route starts where the ARMY stands (its block
	centre, a reachable point), never at the owner: from inside his walled base (the army waits outside his gate) the
	closed gate barrier (CanCollide) gives PathfindingService NoPath and the SEND ended "No route" + HOLD before a step.
	Once routed, the lead point is placed Standoff studs along the route from the block, so the block's formation spot
	is where it already stands: nobody walks back, nobody is moved (the lead is a virtual point). ]]
local function setDest(plan: Plan, dest: Vector3)
	ArmyLog.Line(plan.Owner, "ARMY DESTINATION", string.format("%s old=%s new=%s source=ArmyPlan.%s/%s", plan.Owner.Name, ArmyLog.Vec(plan.Dest), ArmyLog.Vec(dest), plan.Kind, plan.Phase))
	plan.Dest = dest
	pcall(function()
		plan.Owner:SetAttribute("WE_ArmyDest", dest) -- the ARMY's destination (the map marks it; never his PIN)
	end)
	plan.Route = nil
	plan.RouteIdx = 1
	plan.Routing = true
	plan.RoutedAt = clock()
	local pa: any = plan
	local seq = (pa.RouteSeq or 0) + 1
	pa.RouteSeq = seq -- v165: a re-plan (the routing watchdog) supersedes a slow path request
	local g = plan.Gen
	local st = plan.Squad
	local c = blockCentre(st)
	local start = if c then c else plan.Lead
	local standoff = standoffOf(st)
	task.spawn(function()
		local route, why = ArmyRoute.Plan(start, dest)
		local cur = plans[plan.Uid]
		if cur ~= plan or plan.Gen ~= g or (plan :: any).RouteSeq ~= seq then
			return
		end
		plan.Routing = false
		ArmyLog.Line(plan.Owner, "ARMY PATH", string.format("%s start=%s dest=%s distance=%.0f status=%s waypoints=%d", plan.Owner.Name, ArmyLog.Vec(start), ArmyLog.Vec(dest),
			flatDist(start, dest), if route then "Success" else tostring(why), if route then #route else 0))
		if route then
			plan.Route = route
			if c then
				plan.Lead, plan.RouteIdx = ArmyRoute.PointAlong(start, route, standoff)
			end
			dbg(plan.Owner, "ArmyRoute", string.format("%d waypoints, %.0f studs, legs %d", #route, flatDist(start, dest), #ArmyRoute.Legs(start, dest)), true)
		else
			plan.Route = nil
			dbg(plan.Owner, "ArmyRoute", "no route: " .. tostring(why), true)
			ArmyPlan._NoRoute(plan)
		end
	end)
end

-- the lead walks its route while the block keeps up (the block goes at its slowest soldier's pace)
local function advance(plan: Plan, centre: Vector3, dt: number)
	local route = plan.Route
	if route == nil or plan.Routing then
		plan.LeadVel = Vector3.zero
		-- v165 (owner report: "MARCHING" but stopped): advance() returned here for ever while a path request never came
		-- back, so the stuck re-plan below never ran. A path still outstanding after RoutingTimeout is asked again.
		if plan.Routing and plan.Dest and clock() - plan.RoutedAt >= (C.RoutingTimeoutSeconds or 20) then
			ArmyLog.Line(plan.Owner, "ARMY MOVE", string.format("%s stalled: path request %.0fs old, re-plan", plan.Owner.Name, clock() - plan.RoutedAt))
			setDest(plan, plan.Dest :: Vector3)
		end
		return
	end
	-- Code Bot v145: "behind" = past the block's own formation spot (its centre sits Standoff behind the lead by design),
	-- not the raw distance: a block deeper than LeadMaxGap (8 units + escorts: 16+ studs) made the lead wait for ever
	local blockAt = centre
	local toLead = Vector3.new(plan.Lead.X - centre.X, 0, plan.Lead.Z - centre.Z)
	if toLead.Magnitude > 1e-3 then
		centre = centre + toLead.Unit * math.min(standoffOf(plan.Squad), toLead.Magnitude)
	end
	if flatDist(plan.Lead, centre) > C.LeadMaxGap then
		plan.LeadVel = Vector3.zero -- wait for the block
		local now0 = clock()
		local pm: any = plan
		if now0 - (pm.WaitLogAt or 0) >= 3 then
			pm.WaitLogAt = now0
			local tg = plan.Squad and plan.Squad._acTarget
			ArmyLog.Line(plan.Owner, "ARMY MOVE", string.format("%s lead waiting for the block: gap %.0f (max %d) block=%s engaging=%s",
				plan.Owner.Name, flatDist(plan.Lead, centre), C.LeadMaxGap, ArmyLog.Vec(blockAt),
				if tg then tostring(tg.Kind) .. ":" .. (if tg.Player then tg.Player.Name else "?") else "none"))
		end
	else
		local pos, idx, dir = ArmyRoute.Advance(plan.Lead, route, plan.RouteIdx, C.MarchSpeed, dt)
		plan.Lead, plan.RouteIdx = pos, idx
		plan.LeadVel = dir * C.MarchSpeed
		if dir.Magnitude > 0 then
			plan.LeadLook = dir
		end
	end
	-- no block progress for StuckSeconds while waiting: plan the leg again from the block (at most every RepathSeconds)
	local now = clock()
	centre = blockAt -- (progress: where the block itself is)
	if plan.ProgPos == nil or flatDist(plan.ProgPos :: Vector3, centre) > 4 then
		plan.ProgPos = centre
		plan.ProgAt = now
	elseif now - plan.ProgAt >= C.StuckSeconds and now - plan.RoutedAt >= C.RepathSeconds and plan.Dest then
		plan.ProgAt = now
		dbg(plan.Owner, "ArmyRoute", "blocked: re-plan from the block", true)
		setDest(plan, plan.Dest :: Vector3) -- (from the block; the lead is placed ahead of it, never back onto it)
	end
end

local function routeDone(plan: Plan): boolean
	return plan.Route ~= nil and not plan.Routing and plan.RouteIdx > #(plan.Route :: { Vector3 })
end

-- ── groups (what "clear it" means) ───────────────────────────────────────────────────────────────────────────────
local function groupOf(t: any): Group?
	if t == nil or t.Root == nil then
		return nil
	end
	if t.Kind == "NPC" then
		local model = t.Hum and t.Hum.Parent
		local npcId = model and model:GetAttribute("NPCId")
		local cs = deps.CombatService
		local gid = if typeof(npcId) == "string" and cs and cs.NPCGroupOf then cs.NPCGroupOf(npcId) else nil
		local name = if typeof(gid) == "string" then (string.match(gid, "([^%.]+)$") or gid) else (model and model.Name or "enemies")
		return { Kind = "NPC", GroupId = gid, Hum = t.Hum, Root = t.Root, Name = name }
	elseif t.Kind == "Player" then
		return { Kind = "Player", Hum = t.Hum, Root = t.Root, Name = if t.Player then t.Player.Name else "player", Player = t.Player }
	end
	return { Kind = t.Kind or "Guard", Hum = t.Hum, Root = t.Root, Name = "defenders" }
end

-- how many of the group are still up (0 = cleared); a player who became protected counts as gone
function ArmyPlan.GroupAlive(owner: Player, g: Group): number
	local cs = deps.CombatService
	if g.Kind == "NPC" and g.GroupId and cs and cs.GroupNPCs then
		local ok, list = pcall(cs.GroupNPCs, g.GroupId)
		return if ok and typeof(list) == "table" then #list else 0
	end
	if g.Kind == "Player" and g.Player and cs and cs.UnitMayHitPlayer then
		local ok, may = pcall(cs.UnitMayHitPlayer, owner, g.Player)
		if not (ok and may == true) then
			return 0
		end
	end
	local h = g.Hum
	return if h and h.Health > 0 and g.Root.Parent ~= nil then 1 else 0
end

local function groupPos(g: Group): Vector3
	local cs = deps.CombatService
	if g.Kind == "NPC" and g.GroupId and cs and cs.GroupNPCs then
		local ok, list = pcall(cs.GroupNPCs, g.GroupId)
		if ok and typeof(list) == "table" and list[1] then
			return list[1].Position
		end
	end
	return g.Root.Position
end

-- ── status (the walkie line + HUD strip) ─────────────────────────────────────────────────────────────────────────
local function setStatus(plan: Plan, text: string)
	local now = clock()
	if plan.Status ~= text or now - plan.StatusAt >= C.StatusSeconds then
		local changed = plan.Status ~= text
		plan.Status = text
		plan.StatusAt = now
		if changed and deps.SquadOrdersService and deps.SquadOrdersService.Push then
			pcall(deps.SquadOrdersService.Push, plan.Owner)
		end
	end
end

function ArmyPlan.Status(uid: number): { [string]: any }?
	local plan = plans[uid]
	if plan == nil then
		return nil
	end
	return { Kind = plan.Kind, Phase = plan.Phase, Text = plan.Status, Target = if plan.Kind == "Send" then plan.VictimName elseif plan.Kind == "Travel" and plan.Target then plan.Target.Name elseif plan.Group then plan.Group.Name else nil, Lost = plan.LostCount }
end

-- Code Bot (army command bug): the ArmyState a plan shows (one table, every kind / phase)
function ArmyPlan.StateFor(plan: Plan): string
	if plan.Phase == "Return" then
		return "Recalling"
	end
	if plan.Kind == "Retreat" then
		return "Retreating"
	end
	if plan.Kind == "Clear" then
		return if plan.Phase == "Fight" then "EngagingTarget" else "Attacking"
	end
	if plan.Kind == "Send" or plan.Kind == "Travel" then
		return if plan.Phase == "March" then "TravellingToBase" else "EngagingTarget"
	end
	return "Recalling"
end

local function targetName(plan: Plan): string?
	if plan.Kind == "Send" then
		return plan.VictimName .. "'s base"
	elseif plan.Kind == "Travel" and plan.Target then
		return plan.Target.Name
	elseif plan.Group then
		return plan.Group.Name
	end
	return nil
end

-- every phase change: the plan's state through THE one writer (a no-op while unchanged)
local function syncState(plan: Plan, st: any, source: string)
	if st == nil or plans[plan.Uid] ~= plan then
		return
	end
	ArmyState.Set(plan.Owner, st, ArmyPlan.StateFor(plan), source, { Plan = true, Target = targetName(plan) })
end

-- ── lifecycle ────────────────────────────────────────────────────────────────────────────────────────────────────
local function newPlan(player: Player, kind: string, lead: Vector3): Plan
	gen += 1
	local p: Plan = {
		Kind = kind, Phase = "Seek", Uid = player.UserId, Owner = player, Gen = gen,
		Lead = lead, LeadVel = Vector3.zero, LeadLook = Vector3.new(0, 0, -1), LastAt = clock(),
		Dest = nil, Route = nil, RouteIdx = 1, Routing = false, RoutedAt = -math.huge, ProgPos = nil, ProgAt = clock(),
		Group = nil, GroupAlive = 0, FightSince = clock(), Chain = 0, Kills = 0, SeekFrom = "owner", Bad = {},
		Victim = nil, VictimUid = 0, VictimName = "", PlotId = 0, Bully = false, SiegeAt = nil, Breached = false,
		NoLoot = nil, HoldUnit = nil, HoldSince = nil, HoldHp = 0, Looted = 0, ThenOrder = nil, Total = 0,
		Status = "", StatusAt = -math.huge, LostCount = 0, Squad = nil, ReturnGate = nil,
		Target = nil, EngageSince = nil, ClearSince = nil, Anchor = nil, HoldWhenDone = nil, ThenState = nil, MoveLogAt = nil,
	}
	local old = plans[player.UserId]
	if old then
		ArmyLog.Line(player, "ARMY MOVE", string.format("%s plan %s/%s replaced by %s", player.Name, old.Kind, old.Phase, kind))
	end
	plans[player.UserId] = p
	return p
end

local function finish(plan: Plan, st: any?)
	if plans[plan.Uid] ~= plan then
		return
	end
	plans[plan.Uid] = nil
	pcall(function()
		plan.Owner:SetAttribute("WE_ArmyDest", nil)
	end)
	local sqs = deps.SquadOrdersService
	if st then
		st._acTarget = nil
	end
	local thenOrder = plan.ThenOrder
	local done = false
	if thenOrder ~= nil and thenOrder ~= "Follow" and thenOrder ~= "Attack" and sqs and sqs.SetOrder then
		local okS, res = pcall(sqs.SetOrder, plan.Owner, thenOrder, "ArmyPlan.finish") -- Hold / Retreat now (the plan is gone: a normal order)
		done = okS and res == true
	end
	if not done and st then
		-- (one writer: Following, or the plan's ThenState - an ATTACK started away from him holds where it ended)
		ArmyState.Set(plan.Owner, st, plan.ThenState or "Following", "ArmyPlan.finish " .. plan.Kind)
	elseif not done and sqs and sqs.Push then
		pcall(sqs.Push, plan.Owner)
	end
	ArmyLog.Line(plan.Owner, "ARMY MOVE", string.format("%s plan %s ended -> %s", plan.Owner.Name, plan.Kind, tostring(thenOrder or plan.ThenState or "Following")))
	dbg(plan.Owner, "ArmyPlan", "done -> " .. tostring(plan.ThenOrder or "Follow"), true)
end

-- march back to the owner (or his base while he is dead), then FOLLOW
-- Code Bot v145: his gate spot (outside it, Send.StandoffStuds out), or nil
local function gateSpot(owner: Player): Vector3?
	local profile = profileOf(owner)
	local gd = deps.GateDefenseService
	local plotId = profile and profile.BasePlotId
	local cf = if typeof(plotId) == "number" and gd and gd.GetGateCFrame then gd.GetGateCFrame(plotId) else nil
	return if cf then ((cf :: CFrame) * CFrame.new(0, 0, C.Send.StandoffStuds)).Position else nil
end

-- he stands inside his own (walled) plot: the army comes home to his gate, as FOLLOW's base hold does
local function ownerInOwnPlot(owner: Player, pos: Vector3): boolean
	local profile = profileOf(owner)
	local plotId = profile and profile.BasePlotId
	if typeof(plotId) ~= "number" then
		return false
	end
	local ok, inside = pcall(function(): any
		local AF = require(script.Parent.ArmyFollow) :: any
		return AF.InPlot(plotId, pos, 6)
	end)
	return ok and inside == true
end

-- where RETURN walks to: him, or his gate spot while he is dead / inside his base
local function returnDest(plan: Plan): Vector3
	local r = ownerRoot(plan.Owner)
	if r and not ownerInOwnPlot(plan.Owner, r.Position) then
		plan.ReturnGate = nil
		return r.Position
	end
	local g = gateSpot(plan.Owner)
	if g then
		plan.ReturnGate = true
		return g
	end
	return if r then r.Position else plan.Lead
end

local function toReturn(plan: Plan, why: string?)
	plan.Phase = "Return"
	plan.Group = nil
	setDest(plan, returnDest(plan))
	syncState(plan, plan.Squad, "ArmyPlan.return " .. tostring(why or ""))
	dbg(plan.Owner, "ArmyPlan", "RETURN " .. tostring(why or ""), true)
end

function ArmyPlan._NoRoute(plan: Plan)
	if plan.Phase == "Return" and plan.ReturnGate ~= true then
		local g = gateSpot(plan.Owner)
		if g then
			plan.ReturnGate = true -- (he is somewhere the army cannot walk to: home to his gate instead)
			setDest(plan, g)
			return
		end
	end
	if plan.Kind == "Clear" and plan.Group then
		plan.Bad[plan.Group.Root] = true -- skip it; seek the next
		plan.Group = nil
		plan.Phase = "Seek"
		plan.SeekFrom = "army"
		return
	end
	notify(plan.Owner, string.format(T.NoRoute, targetName(plan) or "there"), "Warn")
	ArmyLog.Reject(plan.Owner, "route " .. plan.Kind, "NoRoute", "dest=" .. ArmyLog.Vec(plan.Dest))
	-- the army stops and holds where it is (no teleport fallback)
	plan.ThenOrder = "Hold"
	local sqs = deps.SquadOrdersService
	finish(plan, if sqs and sqs.StateOf then sqs.StateOf(plan.Owner) else nil)
end

function ArmyPlan.Owns(uid: number): boolean
	return plans[uid] ~= nil
end

-- a SEND army does not refill at its owner while it is out (it would spawn far behind the block)
function ArmyPlan.HoldsRefill(uid: number): boolean
	local p = plans[uid]
	return p ~= nil and (p.Kind == "Send" or p.Kind == "Travel") -- Code Bot: a TRAVEL army is out too
end

-- the lead point ArmyController steers the block after (nil = follow the owner as always)
function ArmyPlan.LeadFor(player: Player): { [string]: any }?
	local p = plans[player.UserId]
	if p == nil then
		return nil
	end
	local look = if p.LeadLook.Magnitude > 0 then p.LeadLook else Vector3.new(0, 0, -1)
	return {
		Root = {
			Position = p.Lead,
			CFrame = CFrame.lookAt(p.Lead, p.Lead + look),
			AssemblyLinearVelocity = p.LeadVel,
			Parent = nil,
		},
		Funnel = p.Funnel, -- v165: through the broken gate
	}
end

-- SEND damage keeps landing while the sender is dead but in the server (GateDefenseService.ApplyUnitDamage opts)
function ArmyPlan.DamageOpts(player: Player): { [string]: any }?
	local p = plans[player.UserId]
	if p and p.Kind == "Send" and C.Send.RequireOwnerAlive ~= true then
		return { OwnerAway = true }
	end
	return nil
end

-- an ordered auto-clear may engage grouped NPCs its owner is not standing next to (CombatService.SetUnitPlanCheck)
function ArmyPlan.AllowsNpcGroup(owner: Player, _groupId: string?): boolean
	if probing == owner.UserId then
		return true -- Code Bot: ProbeClear sees what the ATTACK order would
	end
	local p = plans[owner.UserId]
	if p ~= nil and p.Kind == "Travel" and p.Phase == "Engage" then
		return true -- Code Bot: the army sent to an area clears its defenders
	end
	return p ~= nil and p.Kind == "Clear" and p.Phase ~= "Return"
end

-- the defender's red map markers: armies marching on / sieging his base
function ArmyPlan.IncomingFor(uid: number): { any }?
	local out = nil
	for _, p in pairs(plans) do
		if p.Kind == "Send" and p.VictimUid == uid and (p.Phase == "March" or p.Phase == "Siege" or p.Phase == "Loot") then
			out = out or {}
			table.insert(out, { X = math.floor(p.Lead.X), Z = math.floor(p.Lead.Z), N = p.Owner.Name })
		end
	end
	return out
end

-- the one target pick with a plan's centre / reach / leash (SquadOrdersService pickSquadTarget)
local function pickWith(pick: any, player: Player, st: any, proot: BasePart?, opts: { [string]: any }): any
	local ok = pcall(pick, player, st, proot, opts)
	return if ok then st._acTarget else nil
end

--[[ Code Bot v165 (owner phone bug "ARMY: SIEGE gate 100% guns 0", the army stood against the wall). PROVEN
	(tools/sim/run_army_siege_test.py, docs/proof/army-siege/): the siege pick took ANY hostile within ReachStuds of the
	block - the victim standing in his yard, a guard inside - ahead of the gate (players first, then Siege.Priority).
	Behind the wall none of them can be seen: every unit's line of sight hit the wall (no shot; the gate fallback only
	fires when the ray hits a gate leaf), and the block steered AttackStandoff from that target - into the wall, away from
	the gate - for the whole SiegeMaxSeconds. Rule now: until the gate is breached, a player / guard / turret INSIDE the
	victim's walled plot is not a siege target (the gate is); after the breach they are, as before. ]]
local function behindWalls(info: any, pos: Vector3): boolean
	local c, h = info.PadCenter, tonumber(info.PadHalf)
	if typeof(c) ~= "Vector3" or h == nil then
		return false
	end
	return math.abs(pos.X - c.X) <= h and math.abs(pos.Z - c.Z) <= h
end

--[[ v165 (owner report 3: "ARMY: MARCHING ->" but the army stood still against another base's wall / around a player
	by a runway): on the march the pick took ANY hostile player within 120 studs as the target, and ArmyController
	steered the whole block at him. A player in his own yard behind his wall cannot be shot (every ray hits the wall), so
	the block pressed against that wall, the lead waited for it (gap > LeadMaxGap) and the status still said MARCHING.
	On the march only a player who has HURT him or his soldiers in the last MarchAnswerSeconds is answered, only within
	MarchAnswerStuds of the block, and never one behind the walls of a walled plot; anyone else is ignored. ]]
local function marchAnswer(pick: any, player: Player, st: any, proot: BasePart?, centre: Vector3, leash: number): any
	local t = pickWith(pick, player, st, proot, { Centre = centre, Reach = C.MarchAnswerStuds or 60, LeashFrom = centre, Leash = leash })
	-- (a "Unit" = an enemy army soldier, claude-bud JOB 43 brawl: answered under the same rule - his soldiers hurting
	-- ours count as him hurting us, CombatService.NoteArmyAggressor)
	if t == nil or (t.Kind ~= "Player" and t.Kind ~= "Unit") or t.Player == nil then
		return nil
	end
	local cs = deps.CombatService
	local okH, hurt = pcall(function()
		return cs ~= nil and cs.RecentlyHurtBy ~= nil and cs.RecentlyHurtBy(player, t.Player, C.MarchAnswerSeconds or 10)
	end)
	if not (okH and hurt) then
		return nil
	end
	local gd = deps.GateDefenseService
	local root = t.Root
	if gd and gd.WalledPlotAt and root then
		local okP, pid = pcall(gd.WalledPlotAt, root.Position)
		if okP and pid ~= nil then
			return nil
		end
	end
	return t
end

-- ── ATTACK auto-clear ────────────────────────────────────────────────────────────────────────────────────────────
function ArmyPlan.StartClear(player: Player, st: any, from: Vector3?, seed: any?): boolean
	if not live(player.UserId) or st == nil then
		return false
	end
	local r = ownerRoot(player)
	local _, centre = livingUnits(st)
	if (r == nil and from == nil) or centre == nil then
		return false
	end
	local p = newPlan(player, "Clear", if from then centre :: Vector3 else (r :: BasePart).Position)
	p.Squad = st
	p.SeekFrom = "owner"
	if from then
		-- Code Bot: an ATTACK away from him (the army holds / travels out there): the leash centre is the army, and
		-- once the fight is done it holds there (no 1,000-stud march back mid-map)
		p.Anchor = from
		p.HoldWhenDone = true
		p.SeekFrom = "army"
	end
	setStatus(p, T.Seeking)
	local g = groupOf(seed)
	if g then
		-- the target ProbeClear found: straight to MARCH (no second seek)
		p.Group = g
		p.GroupAlive = ArmyPlan.GroupAlive(player, g)
		p.Phase = "March"
		setDest(p, groupPos(g))
	end
	syncState(p, st, "ATTACK")
	ArmyLog.Line(player, "ARMY MOVE", string.format("%s ATTACK started target=%s from=%s", player.Name, if g then g.Kind .. " " .. g.Name else "seek", ArmyLog.Vec(from or (r and r.Position))))
	dbg(player, "ArmyPlan", "CLEAR start", true)
	return true
end

--[[ Code Bot (army command bug): what an ATTACK order would target, BEFORE the order is taken (the one target pick,
	the one hostility rule, the order's own radius SeekRadius from `from`). nil = "No enemies near" and the army keeps
	its state. The squad's current target is left as it was. ]]
function ArmyPlan.ProbeClear(player: Player, st: any, pick: any, from: Vector3): any
	if st == nil or pick == nil then
		return nil
	end
	local keep = st._acTarget
	probing = player.UserId
	local t = pickWith(pick, player, st, ownerRoot(player), { Centre = from, Reach = C.SeekRadius, LeashFrom = from, Leash = C.SeekLeash })
	probing = nil
	st._acTarget = keep
	ArmyLog.Line(player, "ARMY MOVE", string.format("%s ATTACK probe from=%s radius=%d -> %s", player.Name, ArmyLog.Vec(from), C.SeekRadius,
		if t then tostring(t.Kind) .. " at " .. ArmyLog.Vec(t.Root and t.Root.Position) else "none"))
	return t
end

-- Code Bot: end the plan cleanly (ArmyState.CancelPlan: any non-plan state). Its pending route result is dropped (the
-- plans[uid] ~= plan check in setDest); the squad target is cleared; nobody moves.
function ArmyPlan.Cancel(player: Player, st: any?, why: string?)
	local p = plans[player.UserId]
	if p == nil then
		return
	end
	plans[player.UserId] = nil
	pcall(function()
		player:SetAttribute("WE_ArmyDest", nil)
	end)
	if st then
		st._acTarget = nil
	end
	ArmyLog.Line(player, "ARMY MOVE", string.format("%s plan %s/%s cancelled by %s", player.Name, p.Kind, p.Phase, tostring(why)))
end

-- the army's block centre (or nil): ArmyCommand measures "the army is away" with it
function ArmyPlan.BlockCentre(st: any): Vector3?
	return blockCentre(st)
end

function ArmyPlan.Current(uid: number): Plan?
	return plans[uid]
end

-- RECALL (and any order during a plan): march back first; true = handled here
function ArmyPlan.Recall(player: Player, thenOrder: string?, st: any?): boolean
	local p = plans[player.UserId]
	if p then
		p.Squad = st or p.Squad
		p.ThenOrder = thenOrder
		if p.Kind == "Send" and p.SiegeAt == nil then
			notify(player, "Army recalled", "Info")
		end
		toReturn(p, "recall")
		return true
	end
	if not live(player.UserId) or st == nil then
		return false
	end
	local r = ownerRoot(player)
	local _, centre = livingUnits(st)
	if r and centre and flatDist(centre, r.Position) > 60 then
		local np = newPlan(player, "Return", centre)
		np.Squad = st
		np.ThenOrder = thenOrder
		toReturn(np, "recall (far)")
		return true
	end
	return false
end

-- ── SEND ─────────────────────────────────────────────────────────────────────────────────────────────────────────
-- the facts for a SEND from `sender` to `plotId` (the tests build them directly)
function ArmyPlan.Facts(sender: Player, plotId: number): (Rules.Facts, Player?)
	local bs = deps.BaseService
	local owner = if bs and bs.GetOwnerUserId then bs.GetOwnerUserId(plotId) else nil
	local victim = if typeof(owner) == "number" then Players:GetPlayerByUserId(owner) else nil
	local now = os.time()
	local sProfile = profileOf(sender)
	local vProfile = if victim then profileOf(victim) else nil
	local sqs = deps.SquadOrdersService
	local units, hp, dps = 0, 0, 0
	if sqs and sqs.UnitPower then
		local ok, u, h, d = pcall(sqs.UnitPower, sender)
		if ok then
			units, hp, dps = u or 0, h or 0, d or 0
		end
	end
	local defence = 0
	local gd = deps.GateDefenseService
	if gd and gd.SiegeInfo then
		local ok, info = pcall(gd.SiegeInfo, plotId)
		if ok and info then
			defence = Rules.DefencePower(info.GateHp, info.GuardPower, info.TurretPower)
		end
	end
	local newLeft = 0
	if vProfile then
		local R = RaidConfig.Raid
		if not RunService:IsStudio() or R.ProtectNewPlayersInStudio == true then
			local first = tonumber(vProfile.FirstJoinUnix) or 0
			if first > 0 then
				newLeft = math.max(0, (first + (R.NewPlayerProtectionSeconds or 600)) - now)
			end
		end
	end
	local cs = deps.CombatService
	local novice = victim ~= nil and cs ~= nil and cs.IsNoviceShielded ~= nil and cs.IsNoviceShielded(victim) == true
	local active = plans[sender.UserId]
	local f: Rules.Facts = {
		Self = owner == sender.UserId,
		VictimOnline = victim ~= nil,
		VictimHasBase = victim ~= nil,
		Ally = victim ~= nil and gd ~= nil and gd.IsAlly ~= nil and gd.IsAlly(owner, sender) == true,
		PvpOff = GameConfig.PvPEnabled ~= true,
		ShieldLeft = if vProfile then math.max(0, (tonumber(raidOf(vProfile).ShieldUntil) or 0) - now) else 0,
		NewPlayerLeft = newLeft,
		Novice = novice,
		ProtectLeft = if vProfile then math.max(0, (tonumber(raidOf(vProfile).ArmyProtectUntil) or 0) - now) else 0,
		CooldownLeft = if sProfile then math.max(0, (tonumber(raidOf(sProfile).ArmySendCooldownUntil) or 0) - now) else 0,
		ActiveSend = active ~= nil and active.Kind == "Send",
		Units = units,
		ArmyPower = Rules.ArmyPower(units, hp, dps),
		DefencePower = defence,
	}
	return f, victim
end

function ArmyPlan.CheckSend(sender: Player, plotId: number): Rules.Verdict
	if not live(sender.UserId) then
		return { Ok = false, Reason = "Off", Text = "Not available", Bully = false, Ratio = 0 }
	end
	local f = ArmyPlan.Facts(sender, plotId)
	local v = Rules.Verdict(f)
	dbg(sender, "ArmyFair", string.format("plot %d -> %s (%s) power %.0f vs %.0f", plotId, v.Reason, v.Text, f.ArmyPower, f.DefencePower), true)
	return v
end

function ArmyPlan.StartSend(sender: Player, plotId: number, st: any): (boolean, string)
	local v = ArmyPlan.CheckSend(sender, plotId)
	if not v.Ok then
		return false, v.Text
	end
	local f, victim = ArmyPlan.Facts(sender, plotId)
	local gd = deps.GateDefenseService
	local gateCf = if gd and gd.GetGateCFrame then gd.GetGateCFrame(plotId) else nil
	local living, centre = livingUnits(st)
	if victim == nil or gateCf == nil or centre == nil then
		return false, "No base to attack"
	end
	local r = ownerRoot(sender)
	local p = newPlan(sender, "Send", if r then r.Position else centre :: Vector3)
	p.Squad = st
	p.Victim, p.VictimUid, p.VictimName, p.PlotId, p.Bully = victim, victim.UserId, victim.Name, plotId, v.Bully
	p.Total = #living
	p.Phase = "March"
	local dest = ((gateCf :: CFrame) * CFrame.new(0, 0, C.Send.StandoffStuds)).Position
	setDest(p, dest)
	syncState(p, st, "SEND base " .. tostring(plotId))
	local eta = flatDist(p.Lead, dest) * 1.3 / C.MarchSpeed
	notify(sender, string.format(T.Left, victim.Name .. "'s base"), "Info")
	notify(victim, string.format(T.Incoming, sender.Name, Rules.Clock(eta)), "Warn")
	dbg(sender, "ArmyPlan", string.format("SEND -> %s plot %d eta %.0fs units %d bully %s", victim.Name, plotId, eta, #living, tostring(v.Bully)), true)
	ArmyLog.Line(sender, "ARMY MOVE", string.format("%s travel started -> plot %d dest=%s units=%d", sender.Name, plotId, ArmyLog.Vec(dest), #living))
	local _ = f
	return true, v.Text
end

local function travelCfg(): { [string]: any }
	local t = (C :: any).Travel
	return if typeof(t) == "table" then t else {}
end

--[[ Code Bot (army command bug, 2026-10-01): TRAVEL - the map's SEND to an area / site (ArmyTargets): the block walks
	its route to the target's approach point (the one nearest the army), clears the hostiles at the objective, then
	HOLDS there. The owner stays where he is; FOLLOW cannot pull it back (the block follows the plan's lead point; the
	FOLLOW movers only run for the Following state). ]]
function ArmyPlan.StartTravel(player: Player, target: any, st: any): (boolean, string)
	if not live(player.UserId) then
		return false, "Off"
	end
	local living, centre = livingUnits(st)
	if centre == nil or #living == 0 then
		return false, "NoSoldiers"
	end
	local dest = ArmyTargets.ApproachFor(target, centre)
	local p = newPlan(player, "Travel", centre :: Vector3)
	p.Squad = st
	p.Target = target
	p.Total = #living
	p.Phase = "March"
	setDest(p, dest)
	syncState(p, st, "SEND " .. tostring(target.Key))
	setStatus(p, string.format(T.Travelling, target.Name, math.floor(flatDist(centre :: Vector3, dest) * 0.28)))
	notify(player, string.format(T.Sent, target.Name), "Info")
	ArmyLog.Line(player, "ARMY MOVE", string.format("%s travel started -> %s (%s) approach=%s objective=%s distance=%.0f units=%d", player.Name, target.Key, target.Name,
		ArmyLog.Vec(dest), ArmyLog.Vec(target.Centre), flatDist(centre :: Vector3, dest), #living))
	return true, target.Name
end

-- Code Bot: RETREAT with the army far from home: it marches home as a block (his gate spot), then the plain RETREAT
function ArmyPlan.StartRetreat(player: Player, st: any, home: Vector3): boolean
	if not live(player.UserId) then
		return false
	end
	local _, centre = livingUnits(st)
	if centre == nil then
		return false
	end
	local g = gateSpot(player)
	local p = newPlan(player, "Retreat", centre :: Vector3)
	p.Squad = st
	p.Phase = "March"
	p.ThenOrder = "Retreat"
	setDest(p, g or home)
	syncState(p, st, "RETREAT (far)")
	setStatus(p, T.Retreating)
	return true
end

-- ── the per-think step (SquadOrdersService calls it after its own target picks, before the units think) ─────────

local function markLost(plan: Plan, living: { any }, centre: Vector3, now: number)
	local n = 0
	for _, u in ipairs(living) do
		if u._scLost == true then
			n += 1
		elseif flatDist(u.Root.Position, centre) > C.LostStuds then
			u._planFar = u._planFar or now
			if now - u._planFar >= C.LostSeconds then
				u._scLost = true -- reported, never moved
				n += 1
			end
		else
			u._planFar = nil
		end
	end
	if n ~= plan.LostCount then
		plan.LostCount = n
		dbg(plan.Owner, "ArmyRoute", string.format("LOST units %d (never moved)", n), true)
	end
end

local function thinkClear(plan: Plan, player: Player, st: any, proot: BasePart?, pick: any, centre: Vector3, now: number)
	local f3 = (ArmyConfig :: any).Follow3
	local ownerPos = if plan.Anchor then plan.Anchor :: Vector3 elseif proot then proot.Position else centre
	if plan.Phase == "Seek" then
		local from = if plan.SeekFrom == "owner" and proot then proot.Position else centre
		local radius = if plan.SeekFrom == "owner" then C.SeekRadius else C.ChainRadius
		local t = pickWith(pick, player, st, proot, { Centre = from, Reach = radius, LeashFrom = ownerPos, Leash = C.SeekLeash })
		if t and plan.Bad[t.Root] then
			t = nil
		end
		local g = groupOf(t)
		st._acTarget = nil
		if g == nil then
			if plan.Chain == 0 then
				notify(player, T.NothingNear, "Info")
			end
			if plan.HoldWhenDone then
				plan.ThenState = "Holding" -- Code Bot: an ATTACK away from him holds where it ended
				finish(plan, st)
				return
			end
			toReturn(plan, "nothing left")
			return
		end
		plan.Group = g
		plan.GroupAlive = ArmyPlan.GroupAlive(player, g)
		plan.Phase = "March"
		setDest(plan, groupPos(g))
		dbg(player, "ArmyPlan", string.format("SEEK -> %s %s alive %d chain %d/%d", g.Kind, g.Name, plan.GroupAlive, plan.Chain, C.MaxChain), true)
		return
	end
	local g = plan.Group
	if g == nil then
		plan.Phase = "Seek"
		return
	end
	local alive = ArmyPlan.GroupAlive(player, g)
	if plan.Phase == "March" then
		-- an enemy player shooting the army on the way is answered (players first); NPCs wait for the fight
		local t = pickWith(pick, player, st, proot, { Centre = centre, Reach = (tonumber(f3.AttackAggroStuds) or 120), LeashFrom = ownerPos, Leash = C.SeekLeash })
		st._acTarget = if t and t.Kind == "Player" then t else nil
		if alive <= 0 then
			plan.Phase = "Seek"
			plan.SeekFrom = "army"
			return
		end
		local gp = groupPos(g)
		setStatus(plan, string.format(T.Marching, g.Name, math.floor(flatDist(centre, gp) * 0.28)))
		if flatDist(centre, gp) <= C.ArriveStuds + (tonumber(f3.AttackStandoff) or 36) or routeDone(plan) then
			plan.Phase = "Fight"
			plan.FightSince = now
			plan.GroupAlive = alive
			plan.Route = nil
			plan.LeadVel = Vector3.zero
		end
		return
	end
	if plan.Phase == "Fight" then
		pickWith(pick, player, st, proot, { Centre = centre, Reach = (tonumber(f3.AttackAggroStuds) or 120) + (tonumber(f3.AttackKeepExtraStuds) or 20), LeashFrom = ownerPos, Leash = C.SeekLeash })
		if alive < plan.GroupAlive then
			plan.Kills += plan.GroupAlive - alive
			plan.GroupAlive = alive
			plan.FightSince = now
		end
		setStatus(plan, string.format(T.Fighting, alive))
		local beyond = (plan.Anchor ~= nil or proot ~= nil) and flatDist(centre, ownerPos) > C.SeekLeash
		if alive <= 0 or now - plan.FightSince >= C.FightGiveUpSeconds then
			plan.Chain += 1
			st._acTarget = nil
			setStatus(plan, string.format(T.Cleared, plan.Kills))
			dbg(player, "ArmyPlan", string.format("CLEARED %s (kills %d) chain %d/%d", g.Name, plan.Kills, plan.Chain, C.MaxChain), true)
			if plan.HoldWhenDone and (plan.Chain >= C.MaxChain or beyond) then
				plan.ThenState = "Holding"
				finish(plan, st)
			elseif plan.Chain >= C.MaxChain or beyond or (proot == nil and not plan.HoldWhenDone) then
				toReturn(plan, if beyond then "past the leash" else "chain done")
			else
				plan.Group = nil
				plan.Phase = "Seek"
				plan.SeekFrom = "army" -- (the next route starts at the block itself: setDest)
			end
		end
	end
end

--[[ v165 (proven in tools/sim/run_army_siege_test.py: after the breach half the block - every unit not straight in
	front of the 14-stud gate - pressed against the wall beside it, so the block centre never came in, the lead waited
	(gap > LeadMaxGap) and the ATM was never held). The funnel: a unit whose goal is on the other side of the walls walks
	to the gate mouth first, then through the lane, then on to its slot (ArmyController, plan.Funnel via LeadFor). ]]
local function gateFunnelOf(info: any): { [string]: any }?
	local c, h, gp = info.PadCenter, tonumber(info.PadHalf), info.GatePart
	if typeof(c) ~= "Vector3" or h == nil or gp == nil then
		return nil
	end
	local okG, g = pcall(function()
		return gp.Position
	end)
	if not okG or typeof(g) ~= "Vector3" then
		return nil
	end
	local d = Vector3.new(g.X - c.X, 0, g.Z - c.Z)
	local out = if math.abs(d.X) >= math.abs(d.Z) then Vector3.new(math.sign(d.X), 0, 0) else Vector3.new(0, 0, math.sign(d.Z))
	local okB, BL = pcall(function(): any
		return require(game:GetService("ReplicatedStorage").Shared.Configs.BaseLayoutConfig)
	end)
	local width = if okB and BL and tonumber(BL.MainGateWidth) then tonumber(BL.MainGateWidth) :: number else 14
	return { Gate = Vector3.new(g.X, 0, g.Z), Out = out, Lane = math.max(2, width * 0.5 - 2), Centre = c, Half = h }
end

local function structureTarget(part: BasePart, hp: number): any
	return { Kind = "Structure", Hum = { Health = hp, Parent = part }, Root = part }
end

local function thinkSend(plan: Plan, player: Player, st: any, proot: BasePart?, pick: any, living: { any }, centre: Vector3, now: number)
	local victim = plan.Victim
	local bs = deps.BaseService
	local stillOwner = victim ~= nil and victim.Parent ~= nil and bs and bs.GetOwnerUserId and bs.GetOwnerUserId(plan.PlotId) == plan.VictimUid
	if not stillOwner then
		-- the victim left: cancel, walk home, no loot, half the cooldown
		local sp = profileOf(player)
		if sp then
			raidOf(sp).ArmySendCooldownUntil = os.time() + C.Fairness.VictimLeftCooldownSeconds
			pcall(deps.DataService.MarkDirty, player)
		end
		notify(player, "Player left: your army is coming home", "Info")
		plan.Kind = "Return"
		toReturn(plan, "victim left")
		return
	end
	local vp = profileOf(victim :: Player)
	if plan.SiegeAt == nil and vp and (tonumber(raidOf(vp).ShieldUntil) or 0) > os.time() then
		notify(player, "Target shielded: your army turns back", "Info")
		plan.Kind = "Return"
		toReturn(plan, "shield came up")
		return
	end
	local gd = deps.GateDefenseService
	local okI, info = pcall(gd.SiegeInfo, plan.PlotId)
	if not okI or info == nil then
		plan.Kind = "Return"
		toReturn(plan, "no defences")
		return
	end
	if plan.Phase == "March" then
		st._acTarget = marchAnswer(pick, player, st, proot, centre, C.Siege.ReachStuds + 40)
		local dest = plan.Dest or centre
		setStatus(plan, string.format(T.Marching, plan.VictimName .. "'s base", math.floor(flatDist(centre, dest) * 0.28)))
		if routeDone(plan) and flatDist(centre, dest) <= C.ArriveStuds + standoffOf(st) then
			plan.Phase = "Siege"
			plan.SiegeAt = now
			plan.Route = nil
			plan.LeadVel = Vector3.zero
			-- the decided cooldown / protection start when the siege does (a SEND that reached a siege)
			local nowUnix = os.time()
			local sp = profileOf(player)
			if sp then
				raidOf(sp).ArmySendCooldownUntil = nowUnix + C.Fairness.SendCooldownSeconds
				pcall(deps.DataService.MarkDirty, player)
			end
			if vp then
				raidOf(vp).ArmyProtectUntil = nowUnix + C.Fairness.ProtectAfterSiegeSeconds
				pcall(deps.DataService.MarkDirty, victim)
			end
			notify(player, string.format(T.Arrived, plan.VictimName .. "'s base"), "Success")
		end
		return
	end
	if now - (plan.SiegeAt or now) >= C.Send.SiegeMaxSeconds then
		notify(player, "Siege over: your army is coming home", "Info")
		plan.Kind = "Return"
		toReturn(plan, "siege time")
		return
	end
	if info.Breached and not plan.Breached then
		plan.Breached = true
		notify(player, T.Breached, "Success")
		local ms = deps.MoneyCollectorService
		local okR, can, why = pcall(ms.CanArmyRaid, player, victim)
		if not (okR and can == true) then
			plan.NoLoot = tostring(why or "no loot")
		elseif info.CollectorPos then
			setDest(plan, info.CollectorPos)
			plan.Funnel = gateFunnelOf(info)
			-- Code Bot v165: the lead walks in through the broken gate (advance runs for Loot; in Siege it stood still,
			-- so after a breach the block never went in)
			plan.Phase = "Loot"
		end
	end
	if plan.NoLoot then
		notify(player, string.format(T.NoLoot, if plan.NoLoot == "Shielded" then "shield" else string.lower(plan.NoLoot :: string)), "Info")
		plan.Kind = "Return"
		toReturn(plan, "no loot")
		return
	end
	-- the siege target, in Siege.Priority order (a player shooting back always first: players first)
	local t = pickWith(pick, player, st, proot, { Centre = centre, Reach = C.Siege.ReachStuds, LeashFrom = centre, Leash = C.Siege.ReachStuds + 40 })
	local pickT: any = nil
	local shut = not info.Breached -- (the walls still stand: only what the block can see from outside counts)
	if t and shut and t.Root and behindWalls(info, t.Root.Position) then
		t = nil -- Code Bot v165: behind the walls: the gate first
	end
	if t and (t.Kind == "Player" or t.Kind == "Unit") then
		pickT = t -- (a defender's soldier in the open shooting back: claude-bud JOB 43 brawl, same tier as a player)
	else
		for _, kind in ipairs(C.Siege.Priority) do
			if kind == "Turret" then
				for _, tu in ipairs(info.Turrets) do
					if pickT == nil and not tu.Offline and tu.Hp > 0 and tu.Part and flatDist(tu.Part.Position, centre) <= C.Siege.ReachStuds
						and not (shut and behindWalls(info, tu.Part.Position)) then
						pickT = structureTarget(tu.Part, tu.Hp)
					end
				end
			elseif (kind == "Guard" or kind == "InsideGuard") and pickT == nil and t and t.Kind == "Guard" then
				if kind == "Guard" or plan.Breached then
					pickT = t
				end
			elseif kind == "Gate" and pickT == nil and not info.Breached and info.GatePart then
				pickT = structureTarget(info.GatePart, info.GateHp)
			end
		end
	end
	st._acTarget = pickT
	local turretsUp = 0
	for _, tu in ipairs(info.Turrets) do
		if not tu.Offline and tu.Hp > 0 then
			turretsUp += 1
		end
	end
	local gatePct = if info.GateMax > 0 then math.floor(100 * info.GateHp / info.GateMax) else 0
	-- Code Bot v165: how many of HIS soldiers fired in the last 2 s (the cooldown is spent on a shot, hit or miss)
	local firing = 0
	for _, u in ipairs(living) do
		if now - (tonumber(u.LastFireAt) or -math.huge) <= 2 then
			firing += 1
		end
	end
	dbg(player, "ArmySiege", string.format("target %s gate %d%% turrets %d units %d/%d firing %d breached %s", if pickT then pickT.Kind else "none", gatePct, turretsUp, #living, plan.Total, firing, tostring(info.Breached)))
	if ArmyLog.On(player) and now - (plan.MoveLogAt or -math.huge) >= 2 then
		plan.MoveLogAt = now
		ArmyLog.Line(player, "ARMY SIEGE", string.format("%s target=%s gate=%d%% enemy turrets=%d firing=%d/%d breached=%s", player.Name,
			if pickT then tostring(pickT.Kind) .. " at " .. ArmyLog.Vec(pickT.Root and pickT.Root.Position) else "none", gatePct, turretsUp, firing, #living, tostring(info.Breached)))
	end
	if not plan.Breached then
		setStatus(plan, string.format(T.Sieging, string.format("gate %d%% · firing %d · enemy guns %d", gatePct, firing, turretsUp)))
		return
	end
	-- breached: march to the ATM, hold it RaidConfig.Raid.HoldSeconds with the nearest unit, never hit
	if info.CollectorPos == nil then
		return
	end
	local atm: Vector3 = info.CollectorPos
	local holder, best = nil, math.huge
	for _, u in ipairs(living) do
		local d = flatDist(u.Root.Position, atm)
		if d < best then
			holder, best = u, d
		end
	end
	if holder == nil or best > C.Send.AtmHoldStuds then
		plan.HoldSince = nil
		setStatus(plan, string.format(T.Marching, "the ATM", math.floor(best * 0.28)))
		return
	end
	local R = RaidConfig.Raid
	local hp = holder.Humanoid.Health
	if plan.HoldUnit ~= holder or plan.HoldSince == nil or hp < plan.HoldHp - (R.DamageCancelHp or 0.5) then
		plan.HoldUnit = holder
		plan.HoldSince = now -- a hit on the holder restarts the hold (the DamageCancelHp rule)
	end
	plan.HoldHp = hp
	plan.Phase = "Loot"
	local left = (R.HoldSeconds or 6) - (now - (plan.HoldSince :: number))
	setStatus(plan, string.format(T.Looting, math.max(0, math.ceil(left))))
	if left <= 0 then
		local ms = deps.MoneyCollectorService
		local frac = ArmyOrdersConfig.LootFraction(R.StealFraction, plan.Bully)
		local okL, moved = pcall(ms.ArmyRaid, player, victim, frac)
		local n = if okL and typeof(moved) == "number" then moved else 0
		plan.Looted = n
		if n > 0 then
			notify(player, string.format(T.Looted, Rules.Commas(n)), "Success")
			pcall(function() -- claude-bud JOB 41: a raid win (RivalRaidWon when sent from TARGETS; the rate card's RaidWin)
				local RS = require(script.Parent.Parent.Services.RivalService) :: any
				RS.OnRaidWon(player, plan.PlotId, n)
				local RP = require(script.Parent.Parent.Services.RatePromptService) :: any
				RP.Trigger(player, "RaidWin")
			end)
			pcall(function() -- claude-bud JOB 48: the Guided "RAID A RIVAL BASE" goal is won (only while it is open)
				(require(script.Parent.Parent.Services.GuidedService) :: any).OnRaidWon(player)
			end)
			pcall(function() -- claude-bud JOB 39: the Intel Office's "win a SEND ARMY raid" contract
				(require(script.Parent.Parent.Services.EndgameService) :: any).NoteContract(player, "WinSend", 1)
			end)
		else
			notify(player, string.format(T.NoLoot, "empty"), "Info")
		end
		dbg(player, "ArmySiege", string.format("LOOT %d (fraction %.3f bully %s)", n, frac, tostring(plan.Bully)), true)
		plan.Kind = "Return"
		toReturn(plan, "looted")
	end
end

-- Code Bot (army command bug): TRAVEL's step: MARCH (players shooting the block are answered) -> arrived ->
-- ENGAGE the hostiles at the objective (the steered ATTACK deploy; the lead point stays at the approach point) -> HOLD
local function thinkTravel(plan: Plan, player: Player, st: any, proot: BasePart?, pick: any, centre: Vector3, now: number)
	local tg = plan.Target
	local cfg = travelCfg()
	if plan.Phase == "March" then
		st._acTarget = marchAnswer(pick, player, st, proot, centre, 160)
		local dest = plan.Dest or centre
		setStatus(plan, string.format(T.Travelling, tg.Name, math.floor(flatDist(centre, dest) * 0.28)))
		if routeDone(plan) and flatDist(centre, dest) <= C.ArriveStuds + standoffOf(st) then
			plan.Phase = "Engage"
			plan.EngageSince = now
			plan.ClearSince = nil
			plan.Route = nil
			plan.LeadVel = Vector3.zero
			ArmyLog.Line(player, "ARMY MOVE", string.format("%s arrived at %s (%s) block=%s", player.Name, tg.Key, tg.Name, ArmyLog.Vec(centre)))
			notify(player, string.format(T.Arrived, tg.Name), "Success")
		end
		return
	end
	-- ENGAGE: the hostiles within the objective's radius + EngageExtraStuds (the one pick, the one hostility rule)
	local reach = (tonumber(tg.Radius) or 60) + (tonumber(cfg.EngageExtraStuds) or 60)
	local t = pickWith(pick, player, st, proot, { Centre = tg.Centre, Reach = reach, LeashFrom = tg.Centre, Leash = reach + 60 })
	st._acTarget = t
	if t then
		plan.ClearSince = nil
		setStatus(plan, string.format(T.Engaging, tg.Name))
	else
		plan.ClearSince = plan.ClearSince or now
	end
	local clear = plan.ClearSince ~= nil and now - (plan.ClearSince :: number) >= (tonumber(cfg.ClearHoldSeconds) or 2)
	local tooLong = now - (plan.EngageSince or now) >= (tonumber(cfg.EngageMaxSeconds) or 120)
	if clear or tooLong then
		notify(player, string.format(if tg.Territory then T.CaptureHint else T.AreaClear, tg.Name), "Success")
		ArmyLog.Line(player, "ARMY MOVE", string.format("%s %s at %s: HOLD", player.Name, if clear then "clear" else "fight timed out", tg.Name))
		plan.ThenState = "Holding"
		finish(plan, st)
	end
end

function ArmyPlan.Think(player: Player, st: any, proot: BasePart?, pick: any, now: number?)
	local plan = plans[player.UserId]
	if plan == nil then
		return
	end
	local t = now or clock()
	local living, centre = livingUnits(st)
	if centre == nil then
		if plan.Kind == "Send" or plan.SiegeAt ~= nil then
			notify(player, T.Wiped, "Error")
		end
		finish(plan, st)
		return
	end
	local c = centre :: Vector3
	plan.Squad = st
	-- (a plan fights through the steered ATTACK (attackAimOnly) and the lead point moves the block: its state's mode is
	-- Attack; Code Bot: ArmyState.Set is the one writer of st.Order - a squad out of step is re-synced and logged)
	if st.Order ~= "Attack" then
		ArmyLog.Line(player, "ARMY STATE", string.format("%s plan %s/%s found mode %s: resync", player.Name, plan.Kind, plan.Phase, tostring(st.Order)))
		ArmyState.Set(player, st, ArmyPlan.StateFor(plan), "ArmyPlan.Think resync", { Plan = true, Target = targetName(plan), Force = true })
	end
	local dt = math.clamp(t - plan.LastAt, 0.05, 1)
	plan.LastAt = t
	markLost(plan, living, c, t)
	if plan.Phase == "Return" then
		st._acTarget = nil
		local r = ownerRoot(player)
		if r and plan.Dest and t - plan.RoutedAt >= C.RepathSeconds and not plan.Routing then
			local home = returnDest(plan)
			if flatDist(home, plan.Dest :: Vector3) > 40 then
				setDest(plan, home) -- he moved: follow him home (his gate while he is inside his base)
			end
		end
		advance(plan, c, dt)
		setStatus(plan, T.Returning)
		local dest = plan.Dest or c
		if (routeDone(plan) or plan.Route == nil and not plan.Routing) and flatDist(c, dest) <= C.ReturnDoneStuds + 10 + standoffOf(st) then
			if plan.Kind == "Send" or plan.Looted > 0 or plan.SiegeAt ~= nil then
				notify(player, T.Home, "Info")
			end
			finish(plan, st)
		end
		dbg(player, "ArmyMarch", string.format("lead %.0f studs/s gap %.1f lost %d", plan.LeadVel.Magnitude, flatDist(plan.Lead, c), plan.LostCount))
		return
	end
	if plan.Kind == "Send" then
		thinkSend(plan, player, st, proot, pick, living, c, t)
	elseif plan.Kind == "Travel" then
		thinkTravel(plan, player, st, proot, pick, c, t)
	elseif plan.Kind == "Retreat" then
		st._acTarget = nil
		setStatus(plan, T.Retreating)
		local dest = plan.Dest or c
		if routeDone(plan) and flatDist(c, dest) <= C.ReturnDoneStuds + 10 + standoffOf(st) then
			finish(plan, st) -- ThenOrder Retreat: the plain RETREAT walks the last bit home
			return
		end
	else
		thinkClear(plan, player, st, proot, pick, c, t)
	end
	if plans[player.UserId] == plan and (plan.Phase == "March" or plan.Phase == "Loot" or plan.Phase == "Return") then
		advance(plan, c, dt)
		dbg(player, "ArmyMarch", string.format("lead %.0f studs/s gap %.1f lost %d", plan.LeadVel.Magnitude, flatDist(plan.Lead, c), plan.LostCount))
		if ArmyLog.On(player) and t - (plan.MoveLogAt or -math.huge) >= 2 then
			plan.MoveLogAt = t
			ArmyLog.Line(player, "ARMY MOVE", string.format("%s %s/%s block=%s lead=%s to dest %.0f studs, lead %.0f studs/s, lost %d", player.Name, plan.Kind, plan.Phase,
				ArmyLog.Vec(c), ArmyLog.Vec(plan.Lead), flatDist(c, plan.Dest or c), plan.LeadVel.Magnitude, plan.LostCount))
		end
	end
	syncState(plan, st, "ArmyPlan " .. plan.Kind .. "/" .. plan.Phase)
end

-- test hooks
function ArmyPlan._Plans(): { [number]: Plan }
	return plans
end
function ArmyPlan._SetClock(fn: () -> number)
	clock = fn
end
function ArmyPlan._Reset()
	table.clear(plans)
end

local function pushVerdict(player: Player, plotId: number, v: Rules.Verdict)
	local rs = deps.RemoteSetup
	local ev = rs and rs.Get(Constants.RemoteNames.FeaturePush)
	if ev and ev:IsA("RemoteEvent") then
		(ev :: RemoteEvent):FireClient(player, "ArmySendVerdict", { PlotId = plotId, Ok = v.Ok, Text = v.Text })
	end
end

local function ordersRate(): number
	local ok, OC = pcall(function(): any
		return require(Shared.Configs.OrdersConfig)
	end)
	return if ok and OC then tonumber(OC.OrderRatePerSec) or 2 else 2
end

local function ordersBurst(): number
	local ok, OC = pcall(function(): any
		return require(Shared.Configs.OrdersConfig)
	end)
	return if ok and OC then tonumber(OC.OrderBurst) or 4 else 4
end

function ArmyPlan.Init(d: { [string]: any })
	deps = d
	local sqs = d.SquadOrdersService
	if sqs then
		sqs._Plan = ArmyPlan
	end
	local okA, AC = pcall(function(): any
		return require(script.Parent.ArmyController)
	end)
	if okA and AC then
		AC.PlanLead = ArmyPlan.LeadFor
	end
	local cs = d.CombatService
	if cs and cs.SetUnitPlanCheck then
		cs.SetUnitPlanCheck(ArmyPlan.AllowsNpcGroup)
	end
	local check = d.RemoteSetup and d.RemoteSetup.Get(Constants.RemoteNames.RequestArmySendCheck)
	if check and check:IsA("RemoteEvent") then
		(check :: RemoteEvent).OnServerEvent:Connect(function(player: Player, plotId: any)
			if not require(script.Parent.RemoteGate).Check(player, "RequestArmySendCheck", plotId) then
				return
			end
			if d.RateLimitService and not d.RateLimitService.Allow(player, "army_send_check", 2, 4) then
				return
			end
			local id = math.floor(tonumber(plotId) or 0)
			if id > 0 and live(player.UserId) then
				pushVerdict(player, id, ArmyPlan.CheckSend(player, id))
			end
		end)
	end
	-- Code Bot army command bug: THE send command. The target is a base plot id (a number / "B:<plot>"), a map area
	-- ("A:<areaId>") or a world site ("S:<siteId>"); ArmyCommand validates it and starts the one transition. Every
	-- refusal is logged with its reason (ArmyLog.Reject) - nothing is dropped silently any more.
	local send = d.RemoteSetup and d.RemoteSetup.Get(Constants.RemoteNames.RequestArmySend)
	if send and send:IsA("RemoteEvent") then
		(send :: RemoteEvent).OnServerEvent:Connect(function(player: Player, plotId: any)
			ArmyLog.Line(player, "SERVER ARMY", string.format("received player=%s command=Send target=%s", player.Name, tostring(plotId)))
			if not require(script.Parent.RemoteGate).Check(player, "RequestArmySend", plotId) then
				ArmyLog.Reject(player, "SEND " .. tostring(plotId), "BadPayload")
				return
			end
			if d.RateLimitService and not d.RateLimitService.Allow(player, "army_send", ordersRate(), ordersBurst()) then
				ArmyLog.Reject(player, "SEND " .. tostring(plotId), "RateLimited")
				return
			end
			ArmyCommand.Send(player, plotId)
		end)
	end
	ArmyState.Bind({
		CancelPlan = function(p: Player, st: any, why: string?)
			ArmyPlan.Cancel(p, st, why)
		end,
	})
	ArmyCommand.Bind({
		Plan = ArmyPlan,
		PushVerdict = function(p: Player, id: number)
			pushVerdict(p, id, ArmyPlan.CheckSend(p, id))
		end,
	})
	Players.PlayerRemoving:Connect(function(p: Player)
		plans[p.UserId] = nil
	end)
	print("[WAR EMPIRE] ArmyPlan Init")
end

return ArmyPlan
