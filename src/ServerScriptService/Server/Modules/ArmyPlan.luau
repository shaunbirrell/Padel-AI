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

local ArmyPlan = {}

local C = ArmyOrdersConfig
local T = C.Text

export type Group = { Kind: string, GroupId: string?, Hum: any, Root: BasePart, Name: string, Player: Player? }
export type Plan = {
	Kind: string, -- "Clear" | "Send" | "Return"
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
}

local deps: { [string]: any } = {}
local plans: { [number]: Plan } = {}
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
	plan.Dest = dest
	plan.Route = nil
	plan.RouteIdx = 1
	plan.Routing = true
	plan.RoutedAt = clock()
	local g = plan.Gen
	local st = plan.Squad
	local c = blockCentre(st)
	local start = if c then c else plan.Lead
	local standoff = standoffOf(st)
	task.spawn(function()
		local route, why = ArmyRoute.Plan(start, dest)
		local cur = plans[plan.Uid]
		if cur ~= plan or plan.Gen ~= g then
			return
		end
		plan.Routing = false
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
	return { Kind = plan.Kind, Phase = plan.Phase, Text = plan.Status, Target = if plan.Kind == "Send" then plan.VictimName elseif plan.Group then plan.Group.Name else nil, Lost = plan.LostCount }
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
	}
	plans[player.UserId] = p
	return p
end

local function finish(plan: Plan, st: any?)
	if plans[plan.Uid] ~= plan then
		return
	end
	plans[plan.Uid] = nil
	local sqs = deps.SquadOrdersService
	if st then
		st.Order = "Follow"
		st._acTarget = nil
	end
	local thenOrder = plan.ThenOrder
	if thenOrder ~= nil and thenOrder ~= "Follow" and thenOrder ~= "Attack" and sqs and sqs.SetOrder then
		pcall(sqs.SetOrder, plan.Owner, thenOrder) -- Hold / Retreat now (the plan is gone: a normal order)
	elseif sqs and sqs.Push then
		pcall(sqs.Push, plan.Owner)
	end
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
	notify(plan.Owner, string.format(T.NoRoute, if plan.Kind == "Send" then plan.VictimName .. "'s base" else "there"), "Warn")
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
	return p ~= nil and p.Kind == "Send"
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
	local p = plans[owner.UserId]
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

-- ── ATTACK auto-clear ────────────────────────────────────────────────────────────────────────────────────────────
function ArmyPlan.StartClear(player: Player, st: any): boolean
	if not live(player.UserId) or st == nil then
		return false
	end
	local r = ownerRoot(player)
	local _, centre = livingUnits(st)
	if r == nil or centre == nil then
		return false
	end
	local p = newPlan(player, "Clear", r.Position)
	p.Squad = st
	p.SeekFrom = "owner"
	setStatus(p, T.Seeking)
	dbg(player, "ArmyPlan", "CLEAR start", true)
	return true
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
		st.Order = "Attack"
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
	st.Order = "Attack"
	local dest = ((gateCf :: CFrame) * CFrame.new(0, 0, C.Send.StandoffStuds)).Position
	setDest(p, dest)
	local eta = flatDist(p.Lead, dest) * 1.3 / C.MarchSpeed
	notify(sender, string.format(T.Left, victim.Name .. "'s base"), "Info")
	notify(victim, string.format(T.Incoming, sender.Name, Rules.Clock(eta)), "Warn")
	dbg(sender, "ArmyPlan", string.format("SEND -> %s plot %d eta %.0fs units %d bully %s", victim.Name, plotId, eta, #living, tostring(v.Bully)), true)
	local _ = f
	return true, v.Text
end

-- ── the per-think step (SquadOrdersService calls it after its own target picks, before the units think) ─────────
local function pickWith(pick: any, player: Player, st: any, proot: BasePart?, opts: { [string]: any }): any
	local ok = pcall(pick, player, st, proot, opts)
	return if ok then st._acTarget else nil
end

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
	local ownerPos = if proot then proot.Position else centre
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
		local beyond = proot ~= nil and flatDist(centre, proot.Position) > C.SeekLeash
		if alive <= 0 or now - plan.FightSince >= C.FightGiveUpSeconds then
			plan.Chain += 1
			st._acTarget = nil
			setStatus(plan, string.format(T.Cleared, plan.Kills))
			dbg(player, "ArmyPlan", string.format("CLEARED %s (kills %d) chain %d/%d", g.Name, plan.Kills, plan.Chain, C.MaxChain), true)
			if plan.Chain >= C.MaxChain or beyond or proot == nil then
				toReturn(plan, if beyond then "past the leash" else "chain done")
			else
				plan.Group = nil
				plan.Phase = "Seek"
				plan.SeekFrom = "army" -- (the next route starts at the block itself: setDest)
			end
		end
	end
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
		local t = pickWith(pick, player, st, proot, { Centre = centre, Reach = 120, LeashFrom = centre, Leash = C.Siege.ReachStuds + 40 })
		st._acTarget = if t and t.Kind == "Player" then t else nil
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
	if t and t.Kind == "Player" then
		pickT = t
	else
		for _, kind in ipairs(C.Siege.Priority) do
			if kind == "Turret" then
				for _, tu in ipairs(info.Turrets) do
					if pickT == nil and not tu.Offline and tu.Hp > 0 and tu.Part and flatDist(tu.Part.Position, centre) <= C.Siege.ReachStuds then
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
	dbg(player, "ArmySiege", string.format("target %s gate %d%% turrets %d units %d/%d breached %s", if pickT then pickT.Kind else "none", gatePct, turretsUp, #living, plan.Total, tostring(info.Breached)))
	if not plan.Breached then
		setStatus(plan, string.format(T.Sieging, string.format("gate %d%% guns %d", gatePct, turretsUp)))
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
	st.Order = "Attack" -- a plan fights through the steered ATTACK (attackAimOnly); the lead point moves the block
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
	else
		thinkClear(plan, player, st, proot, pick, c, t)
	end
	if plans[player.UserId] == plan and (plan.Phase == "March" or plan.Phase == "Loot" or plan.Phase == "Return") then
		advance(plan, c, dt)
		dbg(player, "ArmyMarch", string.format("lead %.0f studs/s gap %.1f lost %d", plan.LeadVel.Magnitude, flatDist(plan.Lead, c), plan.LostCount))
	end
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
	local send = d.RemoteSetup and d.RemoteSetup.Get(Constants.RemoteNames.RequestArmySend)
	if send and send:IsA("RemoteEvent") then
		(send :: RemoteEvent).OnServerEvent:Connect(function(player: Player, plotId: any)
			if not require(script.Parent.RemoteGate).Check(player, "RequestArmySend", plotId) then
				return
			end
			if d.RateLimitService and not d.RateLimitService.Allow(player, "army_send", ordersRate(), ordersBurst()) then
				return
			end
			local id = math.floor(tonumber(plotId) or 0)
			if id <= 0 or not live(player.UserId) or sqs == nil or sqs.StateOf == nil then
				return
			end
			local st = sqs.StateOf(player)
			if st == nil then
				notify(player, "No soldiers to send", "Warn")
				return
			end
			local ok, text = ArmyPlan.StartSend(player, id, st)
			if not ok then
				notify(player, text, "Warn")
				pushVerdict(player, id, ArmyPlan.CheckSend(player, id))
			elseif sqs.Push then
				pcall(sqs.Push, player)
			end
		end)
	end
	Players.PlayerRemoving:Connect(function(p: Player)
		plans[p.UserId] = nil
	end)
	print("[WAR EMPIRE] ArmyPlan Init")
end

return ArmyPlan
