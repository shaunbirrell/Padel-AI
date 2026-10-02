--!strict
--[[
	Code Bot (army command bug, 2026-10-01; owner: "one server-authoritative, mutually exclusive army state"):
	THE army state of a squad (SquadOrdersService's st). ArmyState.Set is the ONLY writer of st.ArmyState AND of the
	movement mode st.Order the movers read (thinkUnit, ArmyController, ArmyPlan) - nothing else assigns st.Order.

	  Idle             no living units
	  Following        FOLLOW: the block walks behind its owner (ArmyController / ArmyFollow)
	  Holding          HOLD: every unit keeps its spot (HoldPos)
	  TravellingToBase SEND: the block walks an ArmyPlan route to the target's approach point (the plan's lead point)
	  Attacking        ATTACK: an ArmyPlan auto-clear marching on its target group (or the JOB 24 ATTACK, not live)
	  EngagingTarget   a plan fighting at its target (auto-clear FIGHT, a SEND siege / loot, an outpost's defenders)
	  Capturing        reserved: TerritoryCapture counts PLAYERS only (the army clears and holds; he captures)
	  Retreating       RETREAT: home (a far army marches back as a block first)
	  Recalling        RECALL (or FOLLOW while the army is away): the block marches back to him, then Following
	  Regrouping       reserved (Follow3 regroups inside Following)

	Set(player, st, new, source, opts):
	  * the movement mode: Following -> Follow, Holding -> Hold, Retreating -> Retreat (opts.Plan: the plan steers it,
	    Attack), Idle -> Follow, every other state -> Attack (the steered block follows the plan's lead point);
	  * a Set WITHOUT opts.Plan ends any running ArmyPlan first (hooks.CancelPlan: the plan is dropped, its pending
	    route result is ignored by its generation number): the previous state always terminates cleanly;
	  * leaving a state clears the squad targets (_acTarget / _defTarget); entering Holding stores each unit's spot;
	    hooks.OnChange (SquadOrdersService) resets the per-unit chase / aim / recover windows;
	  * replicates WE_ArmyState / WE_ArmyTarget on the Player (the Army UI highlight is the server's state) and pushes
	    SquadOrderStateUpdate (hooks.Push);
	  * logs "[ARMY STATE] <name> old -> new SOURCE=<source>" (ArmyLog: /armydebug or Studio only).
	Same state again = no-op (no reset), unless opts.Force (a legacy repeat order after its grace window).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ArmyLog = require(ReplicatedStorage:WaitForChild("Shared").Util.ArmyLog)

local ArmyState = {}

ArmyState.States = {
	Idle = true,
	Following = true,
	Holding = true,
	TravellingToBase = true,
	Attacking = true,
	EngagingTarget = true,
	Capturing = true,
	Retreating = true,
	Recalling = true,
	Regrouping = true,
} :: { [string]: boolean }

-- the plain order -> its state (RequestSquadOrder, the legacy path)
ArmyState.OfOrder = { Follow = "Following", Hold = "Holding", Attack = "Attacking", Retreat = "Retreating" } :: { [string]: string }

local MODE: { [string]: string } = {
	Idle = "Follow",
	Following = "Follow",
	Holding = "Hold",
	Retreating = "Retreat",
	Regrouping = "Follow",
}

-- the short UI words (status line / map card)
ArmyState.Label = {
	Idle = "IDLE",
	Following = "FOLLOWING",
	Holding = "HOLDING",
	TravellingToBase = "TRAVELLING",
	Attacking = "ATTACKING",
	EngagingTarget = "ENGAGING",
	Capturing = "CAPTURING",
	Retreating = "RETREATING",
	Recalling = "RECALLING",
	Regrouping = "REGROUPING",
} :: { [string]: string }

export type Hooks = {
	CancelPlan: ((player: Player, st: any, why: string) -> ())?,
	OnChange: ((player: Player, st: any, old: string, new: string, source: string) -> ())?,
	Push: ((player: Player) -> ())?,
}
local hooks: Hooks = {}
local clock: () -> number = os.clock

function ArmyState.Bind(h: Hooks)
	for k, v in pairs(h :: any) do
		(hooks :: any)[k] = v
	end
end

function ArmyState._SetClock(fn: () -> number)
	clock = fn
end

-- the state of a squad (a squad made before ArmyState: derived once from its order)
function ArmyState.Of(st: any): string
	if st == nil then
		return "Idle"
	end
	local s = st.ArmyState
	if typeof(s) == "string" and ArmyState.States[s] then
		return s
	end
	return ArmyState.OfOrder[tostring(st.Order)] or "Following"
end

-- the movement mode a state runs (the steered block for every plan state)
function ArmyState.ModeOf(state: string, plan: boolean?): string
	if state == "Retreating" and plan == true then
		return "Attack"
	end
	return MODE[state] or "Attack"
end

function ArmyState.Set(player: Player, st: any, new: string, source: string, opts: { [string]: any }?): boolean
	if st == nil then
		return false
	end
	if not ArmyState.States[new] then
		ArmyLog.Reject(player, "state " .. tostring(new), "UnknownState", "source=" .. tostring(source))
		return false
	end
	local o = opts or {}
	local plan = o.Plan == true
	local old = ArmyState.Of(st)
	-- a non-plan state ends the running plan first (FOLLOW / HOLD / ATTACK-not-live ... never leave a plan behind)
	if not plan and hooks.CancelPlan then
		hooks.CancelPlan(player, st, source)
	end
	local mode = ArmyState.ModeOf(new, plan)
	local same = old == new and st.Order == mode
	if same and o.Force ~= true then
		if o.Target ~= nil then
			st.ArmyTarget = o.Target
			pcall(function()
				player:SetAttribute("WE_ArmyTarget", tostring(o.Target))
			end)
		end
		return false
	end
	st.ArmyState = new
	st.ArmyStateAt = clock()
	st.ArmyStateSource = source
	st.ArmyTarget = o.Target
	st.Order = mode
	if not same then
		st._acTarget = nil
		st._defTarget = nil
	end
	for _, u in ipairs(st.Units or {}) do
		if new == "Holding" then
			if u.Alive and u.Root then
				u.HoldPos = u.Root.Position
			end
		else
			u.HoldPos = nil
		end
	end
	ArmyLog.Line(player, "ARMY STATE", string.format("%s %s -> %s SOURCE=%s mode=%s%s", tostring(player.Name), old, new, source, mode,
		if o.Target ~= nil then " target=" .. tostring(o.Target) else ""))
	if hooks.OnChange then
		local ok, err = pcall(hooks.OnChange :: any, player, st, old, new, source)
		if not ok then
			warn("[ARMY STATE] OnChange error: " .. tostring(err))
		end
	end
	pcall(function()
		player:SetAttribute("WE_ArmyState", new)
		player:SetAttribute("WE_ArmyTarget", if o.Target ~= nil then tostring(o.Target) else nil)
	end)
	if hooks.Push and o.NoPush ~= true then
		pcall(hooks.Push :: any, player)
	end
	return true
end

return ArmyState
