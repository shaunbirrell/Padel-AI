--!strict
--[[
	Code Bot (army command bug, 2026-10-01; owner recording: "ATTACK says No enemies near; SEND -> Crossroads -> GO and the
	army stays beside me"). THE command path of a live ArmyOrders owner (ArmyOrdersConfig.LiveFor: OwnerFirst = UserId
	470626172 + Studio). Every army button lands here, on the server:
	  RequestSquadOrder Follow / Hold / Attack / Retreat / Recall  -> SquadOrdersService.SetOrder -> ArmyCommand.Order
	  RequestArmySend <target id>  (the map's ArmySend GO / SEND ARMY) -> ArmyCommand.Send
	Each command is validated (a rejection is a warn with its reason + a toast, and the state is pushed again so the
	Army UI shows the real state), then ONE transition through ArmyState.Set; ArmyPlan carries the movement of the plan
	states. The previous state always ends first (ArmyState: a non-plan state cancels the plan; a new plan replaces the
	old one). Transitions:
	  FOLLOW   near him -> Following; army away (> RecallFarStuds) or a plan running -> Recalling (march back) -> Following
	  RECALL   as FOLLOW (the explicit button)
	  HOLD     -> Holding where every unit stands now (a travel / fight stops at once; nothing marches back first)
	  RETREAT  army far from home (> RetreatPlanStuds) -> Retreating as a block (plan) -> the plain RETREAT; else plain
	  ATTACK   ProbeClear from the army (him while it is beside him), radius SeekRadius: a target -> Attacking (an
	           auto-clear plan; away from him it holds where it ends); none -> "No enemies near", the state is unchanged
	           (FOLLOW stays FOLLOW, a travelling army keeps travelling). An ATTACK already running is kept.
	  SEND     ArmyTargets.Resolve -> a base: ArmyPlan.StartSend (the fairness verdict); an area / site:
	           ArmyPlan.StartTravel -> TravellingToBase (from ANY state: Following, Holding, already Travelling)
	Not live (every other player): SquadOrdersService's own order path (unchanged), through ArmyState.Set as well.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArmyOrdersConfig = require(Shared.Configs.ArmyOrdersConfig) :: any
local ArmyLog = require(Shared.Util.ArmyLog)
local ArmyState = require(script.Parent.ArmyState)
local ArmyTargets = require(script.Parent.ArmyTargets)

local ArmyCommand = {}

local deps: { [string]: any } = {}

function ArmyCommand.Bind(d: { [string]: any })
	for k, v in pairs(d) do
		deps[k] = v
	end
end

function ArmyCommand.Live(player: Player): boolean
	return ArmyOrdersConfig.LiveFor(player.UserId) == true and deps.Plan ~= nil
end

local function flatDist(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function notify(player: Player, text: string, kind: string?)
	local ns = deps.NotificationService
	if ns and ns.Notify then
		pcall(ns.Notify, player, text, kind or "Info", 4)
	end
end

local function push(player: Player)
	if deps.Push then
		pcall(deps.Push, player)
	end
end

local function ownerPos(player: Player): Vector3?
	local r = if deps.OwnerRoot then deps.OwnerRoot(player) else nil
	return if r then r.Position else nil
end

-- a rejection: logged (warn + reason), told (toast), and the real state pushed again (the UI never shows a guess)
local function reject(player: Player, what: string, reason: string, text: string?, detail: string?): (boolean, string)
	ArmyLog.Reject(player, what, reason, (detail or "") .. " state=" .. ArmyState.Of(deps.StateOf and deps.StateOf(player)))
	if text then
		notify(player, text, "Warn")
	end
	push(player)
	return false, reason
end

-- the army is away from him (or he is dead): measured from the block centre
local function armyAway(player: Player, st: any): (boolean, Vector3?)
	local c = deps.Plan.BlockCentre(st)
	local o = ownerPos(player)
	if c == nil then
		return false, nil
	end
	if o == nil then
		return true, c
	end
	return flatDist(c, o) > (tonumber(ArmyOrdersConfig.RecallFarStuds) or 60), c
end

local function hasUnits(st: any): boolean
	return st ~= nil and deps.Plan.BlockCentre(st) ~= nil
end

--[[ RequestSquadOrder for a live owner. Returns (ok, reason). SquadOrdersService has checked the order name, the
	OrdersConfig flags, the soldier count and that a squad exists. ]]
function ArmyCommand.Order(player: Player, st: any, order: string, source: string?): (boolean, string?)
	local src = source or "order " .. order
	local Plan = deps.Plan
	local cur = Plan.Current(player.UserId)
	local from = ArmyState.Of(st)
	ArmyLog.Line(player, "SERVER ARMY", string.format("%s command=%s state=%s plan=%s source=%s", player.Name, order, from, if cur then cur.Kind .. "/" .. cur.Phase else "none", src))
	if order == "Follow" or order == "Recall" then
		local away = armyAway(player, st)
		if cur ~= nil and cur.Phase == "Return" and cur.ThenOrder == nil then
			return true, nil -- already marching back to him
		end
		if (cur ~= nil or away) and hasUnits(st) then
			-- the block marches back to him first (Recalling), then FOLLOW (ArmyPlan.finish)
			if Plan.Recall(player, nil, st) then
				return true, nil
			end
		end
		ArmyState.Set(player, st, "Following", src)
		return true, nil
	end
	if order == "Hold" then
		ArmyState.Set(player, st, "Holding", src) -- (cancels a plan: the army stops where it stands)
		return true, nil
	end
	if order == "Retreat" then
		local home = if deps.HomePos then deps.HomePos(player) else nil
		local c = Plan.BlockCentre(st)
		if home and c and flatDist(c, home) > (tonumber(ArmyOrdersConfig.RetreatPlanStuds) or 120) and source ~= "ArmyPlan.finish" then
			if Plan.StartRetreat(player, st, home) then
				return true, nil
			end
		end
		ArmyState.Set(player, st, "Retreating", src)
		return true, nil
	end
	if order == "Attack" then
		if cur ~= nil and cur.Kind == "Clear" and cur.Phase ~= "Return" then
			return true, nil -- ATTACK again keeps the running auto-clear
		end
		if not hasUnits(st) then
			return reject(player, "ATTACK", "NoSoldiers", "No soldiers in the field")
		end
		local away, centre = armyAway(player, st)
		local seekFrom = if away or cur ~= nil then centre else ownerPos(player)
		if seekFrom == nil then
			return reject(player, "ATTACK", "NoOwner", "Respawn first")
		end
		local t = Plan.ProbeClear(player, st, deps.Pick, seekFrom :: Vector3)
		if t == nil then
			-- DECIDED: nothing to fight within SeekRadius: say so and keep the previous state (never a broken ATTACK)
			return reject(player, "ATTACK", "NoEnemiesNear", ArmyOrdersConfig.Text.NothingNear,
				string.format("from=%s radius=%d", ArmyLog.Vec(seekFrom), ArmyOrdersConfig.SeekRadius))
		end
		if not Plan.StartClear(player, st, if away or cur ~= nil then seekFrom else nil, t) then
			return reject(player, "ATTACK", "StartFailed", "Order failed")
		end
		return true, nil
	end
	return reject(player, "order " .. tostring(order), "InvalidOrder", "Invalid squad order")
end

--[[ RequestArmySend (the map's ArmySend GO, a base card's SEND ARMY, the Intel Office): the target id only. ]]
function ArmyCommand.Send(player: Player, raw: any): (boolean, string?)
	if not ArmyCommand.Live(player) then
		return reject(player, "SEND " .. tostring(raw), "NotLive", nil)
	end
	local target, why = ArmyTargets.Resolve(raw)
	if target == nil then
		return reject(player, "SEND " .. tostring(raw), why or "BadTarget", "Pick a base or a zone on the map")
	end
	local st = deps.StateOf and deps.StateOf(player)
	if st == nil and deps.SyncArmy then
		pcall(deps.SyncArmy, player)
		st = deps.StateOf(player)
	end
	if not hasUnits(st) then
		return reject(player, "SEND " .. target.Key, "NoSoldiers", "No soldiers to send")
	end
	local from = ArmyState.Of(st)
	ArmyLog.Line(player, "SERVER ARMY", string.format("%s command=Send target=%s (%s) kind=%s state=%s", player.Name, target.Key, target.Name, target.Kind, from))
	if target.Kind == "Base" then
		local ok, text = deps.Plan.StartSend(player, target.PlotId :: number, st)
		if not ok then
			reject(player, "SEND " .. target.Key, "Verdict", text, "verdict=" .. tostring(text))
			if deps.PushVerdict then
				pcall(deps.PushVerdict, player, target.PlotId)
			end
			return false, text
		end
		push(player)
		return true, nil
	end
	local ok, text = deps.Plan.StartTravel(player, target, st)
	if not ok then
		return reject(player, "SEND " .. target.Key, tostring(text), "Order failed")
	end
	push(player)
	return true, nil
end

return ArmyCommand
