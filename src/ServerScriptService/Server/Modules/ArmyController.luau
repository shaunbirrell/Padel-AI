--!strict
--[[
	v115 (Code Bot Roblox, 2026-09-29, docs/ARMY-FOLLOW-ROOTCAUSE-3.md): ArmyController — ONE authoritative movement
	controller per army (ArmyConfig.Follow3; Enabled false / Rollout off = the v113 ArmyFollow path).

	  * THE FORMATION FOLLOWS HIM, SOLDIERS FOLLOW SLOTS. FormationController.Plan: a breadcrumb trail of his path; a
	    block of rows BEHIND him on that trail (row r at FirstRowStuds + r x RowSpacing of path behind him), each row
	    square to his path there (per-row heading from the trail tangent = his movement direction, rate-limited,
	    deadband, hysteresis, only while he moves). Columns across (2..ColumnsMax), escorts in the rows directly behind
	    their unit. No side wings, nothing rotates round him, nothing orbits him. When he stops: nothing re-forms.
	  * State machine per army: FOLLOW / HOLD / ATTACK / RETREAT (= the squad order). Only FOLLOW is driven here.
	  * Slots: FormationController.Assign — PERMANENT per unit (FormationSlot attribute), only a death / removal /
	    roster change touches it (WARN logged). No distance, no nearest-slot, no pairs() ordering.
	  * Per unit: SoldierController.Drive (MoveTo on a moved target / max interval only, catch-up toward its OWN slot,
	    arrival deadzone, stuck fallback path, the logged emergency reposition).
	  * His own base (Follow2.Tidy hold): units wait at their gate cells (ArmyFollow.HoldSpot), never cross his plot.
	  * Debug (Follow3.Debug + the player's WE_ArmyDebug attribute; default on for DebugUserIds; /armydebug toggles):
	    WE_SlotPos per unit (his client draws the slot markers + labels: ArmyDebugClient, visible to him only), a
	    throttled per-soldier state log, WARN on every slot change and on every reposition (SoldierController).
	  * Collision audit every AuditSeconds: every part of every unit carries the ArmyNPCs group.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArmyConfig = require(Shared.Configs.ArmyConfig)
local AdminConfig = require(Shared.Configs.AdminConfig)
local FormationController = require(Shared.Util.FormationController)
local SoldierController = require(script.Parent.SoldierController)
local ArmyFollow = require(script.Parent.ArmyFollow)
local Enterables = require(script.Parent.Enterables) -- claude-bud JOB 32: owner indoors -> the army waits at the door

local ArmyController = {}
ArmyController.Stats = { Ticks = 0, Errors = 0, AuditFixes = 0, SlotChanges = 0 }

local deps: { [string]: any } = {}
local started = false
local errAt: { [number]: number } = {}

local function cfg(): { [string]: any }
	local c = (ArmyConfig :: any).Follow3
	return if typeof(c) == "table" then c else {}
end

local function num(key: string, default: number): number
	local v = cfg()[key]
	return if typeof(v) == "number" then v else default
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDist(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Follow3 live for this owner (and the Follow2 module it builds on)
function ArmyController.LiveFor(userId: any): boolean
	local c = cfg()
	if c.Enabled ~= true or not ArmyFollow.LiveFor(userId) then
		return false
	end
	if c.Rollout == "all" then
		return true
	end
	if c.Rollout == "owner" then
		return AdminConfig.IsPlaytestOwner(userId) == true
	end
	return false
end

-- JOB 24 (claude-bud, docs/ARMY-ATTACK-ROOTCAUSE.md): ATTACK is driven here too, by the same steered block
-- (Follow3.Steer + Follow3.AttackSteer; false = the v116 SquadOrdersService.attackUnit movement)
-- claude-bud JOB 38: set by ArmyPlan.Init: (player) -> { Root = a stand-in root at the plan's lead point } | nil
ArmyController.PlanLead = nil :: ((Player) -> any)?

-- Code Bot v145: how far behind its leader (the owner, or an ArmyPlan lead point) the steered block holds its CENTRE by
-- design: FirstRowStuds + its half depth, and never nearer than its radius + BubbleStuds (FormationController.SteerFrames).
-- 0 before the block has formed. ArmyPlan measures "the block is behind" from here, not from the lead itself.
function ArmyController.Standoff(st: any): number
	local a = if typeof(st) == "table" then st._ac else nil
	local f = if typeof(a) == "table" and typeof(a.F) == "table" then a.F.Form else nil
	if typeof(f) ~= "table" then
		return 0
	end
	return math.max(num("FirstRowStuds", 7) + (tonumber(f.HalfDepth) or 0), (tonumber(f.Radius) or 0) + num("BubbleStuds", 3))
end

function ArmyController.AttackLive(userId: any): boolean
	local c = cfg()
	return ArmyController.LiveFor(userId) and c.Steer == true and c.AttackSteer == true
end

-- debug overlay / logs on for this player: his WE_ArmyDebug attribute (/armydebug toggles it; admin allowlist) --
-- JOB 24: off by default for EVERYONE (Follow3.Debug = false no longer switches it on by itself; with Debug true it
-- still defaults on for DebugUserIds). Otherwise only a DebugUserIds player who typed /armydebug sees it.
local function isDebugUserId(userId: number): boolean
	local ids = cfg().DebugUserIds
	if typeof(ids) == "table" then
		for _, id in ipairs(ids) do
			if id == userId then
				return true
			end
		end
	end
	return false
end

function ArmyController.DebugFor(player: Player): boolean
	return player:GetAttribute("WE_ArmyDebug") == true and (cfg().Debug == true or isDebugUserId(player.UserId))
end

local isDebugUser = isDebugUserId

local STATE_OF: { [string]: string } = { Follow = "FOLLOW", Hold = "HOLD", Attack = "ATTACK", Retreat = "RETREAT" }

local function army(st: any): any
	local a = st._ac
	if a == nil then
		a = {
			State = nil,
			F = FormationController.NewArmy(), -- trail + permanent assignment + per-slot velocity
			LastPos = nil,
			LastAt = nil,
			AuditAt = -math.huge,
			LayoutKey = nil,
			LogAt = -math.huge,
		}
		a.Assign = a.F.Assign
		st._ac = a
	end
	return a
end

-- the slot index of a unit (assigned permanently on first sight)
function ArmyController.SlotOf(st: any, unit: any): number
	local a = army(st)
	local idx = a.Assign.ByUnit[unit]
	if idx == nil then
		FormationController.Assign(a.Assign, st.Units)
		idx = a.Assign.ByUnit[unit]
	end
	return idx or tonumber(unit.Slot) or 1
end

-- spawn offset (owner frame: x = right, z = behind) of a new unit with SquadSlot `slot`: in the block behind him
function ArmyController.SpawnOffset(slot: number): Vector3
	return FormationController.SpawnOffset(slot, cfg())
end

-- escort figures a unit shows (the client draws them in the rows directly behind it)
local function escOf(u: any): number
	local m = u.Model
	if m == nil then
		return 0
	end
	return math.max(0, math.floor(tonumber(m:GetAttribute("WE_Escorts")) or 0))
end

local function unitName(u: any): string
	return string.format("S%02d", tonumber(u.Slot) or 0)
end

-- per unit, on change only (attributes replicate): FormationSlot / WE_FormSlot (its permanent slot), WE_FormYaw (its
-- row's heading, past YawPublishDeg), WE_FormRow / WE_FormX (its cell), and in debug WE_SlotPos (its world slot)
local function publish(player: Player, st: any, a: any, plans: { [any]: any }, debugOn: boolean)
	local yawStep = num("YawPublishDeg", 3)
	local posStep = num("DebugPublishStuds", 0.5)
	for _, u in ipairs(st.Units) do
		local m = u.Model
		if u.Alive and m and m.Parent then
			local idx = a.Assign.ByUnit[u]
			if idx and u._acIdx ~= idx then
				local old = u._acIdx
				u._acIdx = idx
				pcall(function()
					m:SetAttribute("FormationSlot", idx)
					m:SetAttribute("WE_FormSlot", idx)
				end)
				if old == nil then
					print(string.format("[ArmyDebug] SLOT ASSIGN %s %s -> slot %d (first assignment)", player.Name, unitName(u), idx))
				else
					ArmyController.Stats.SlotChanges += 1
					warn(string.format("[ArmyDebug] SLOT CHANGE %s %s %d -> %d reason=roster change (death / removal / new unit)",
						player.Name, unitName(u), old, idx))
				end
			end
			local p = plans[u]
			if p then
				local yaw = math.floor(FormationController.YawDeg(p.Heading) + 0.5)
				if u._acYaw == nil or math.abs(((yaw - u._acYaw + 180) % 360) - 180) >= yawStep then
					u._acYaw = yaw
					pcall(function()
						m:SetAttribute("WE_FormYaw", yaw)
					end)
				end
				if u._acRow ~= p.Row then
					u._acRow = p.Row
					pcall(function()
						m:SetAttribute("WE_FormRow", p.Row)
					end)
				end
				if debugOn then
					if u._acMode ~= u._scState then
						u._acMode = u._scState
						pcall(function()
							m:SetAttribute("WE_MoveState", u._scState)
						end)
					end
					local sp: Vector3 = p.Goal
					if u._acSlotPos == nil or flatDist(u._acSlotPos, sp) >= posStep then
						u._acSlotPos = sp
						pcall(function()
							m:SetAttribute("WE_SlotPos", sp)
						end)
					end
				end
			end
			if not debugOn and (u._acSlotPos ~= nil or u._acMode ~= nil) then
				u._acSlotPos = nil
				u._acMode = nil
				pcall(function()
					m:SetAttribute("WE_SlotPos", nil)
					m:SetAttribute("WE_MoveState", nil)
				end)
			end
		end
	end
end

-- every part of every unit in the ArmyNPCs group (late rig parts / accessories included)
local function audit(st: any, a: any, now: number)
	if now - a.AuditAt < num("AuditSeconds", 5) then
		return
	end
	a.AuditAt = now
	local group = ArmyFollow.Group
	for _, u in ipairs(st.Units) do
		if u.Model and u.Model.Parent then
			for _, d in ipairs(u.Model:GetDescendants()) do
				if d:IsA("BasePart") and d.CollisionGroup ~= group then
					d.CollisionGroup = group
					ArmyController.Stats.AuditFixes += 1
				end
			end
		end
	end
end

-- a unit position the owner cannot see: behind him (past his shoulder line) or with the view line blocked
local function outOfView(ownerRoot: BasePart, p: Vector3): boolean
	local look = flat(ownerRoot.CFrame.LookVector)
	local off = flat(p - ownerRoot.Position)
	if off.Magnitude > 1e-3 and look.Magnitude > 1e-3 and off.Unit:Dot(look.Unit) < -0.2 then
		return true
	end
	return not ArmyFollow.ClearLine(ownerRoot.Position + Vector3.new(0, 1.5, 0), p)
end

-- the emergency reposition spot: its own slot pushed RepositionBehindStuds further back along its row's heading
-- (behind the phone camera), then half that, then the slot; on the ground, with a clear line from him, never near him
local function repositionSpot(ownerRoot: BasePart, slot: Vector3, heading: Vector3): CFrame?
	local dir: Vector3 = if heading.Magnitude > 1e-3 then heading.Unit else Vector3.new(0, 0, -1)
	local y = ownerRoot.Position.Y
	slot = Vector3.new(slot.X, y, slot.Z)
	local behind = num("RepositionBehindStuds", 16)
	ArmyFollow.RefreshRayFilter(nil)
	for _, c in ipairs({ slot - dir * behind, slot - dir * behind * 0.5, slot }) do
		local g = ArmyFollow.GroundAt(c, y)
		if g and flatDist(g, ownerRoot.Position) >= num("RepositionMinOwnerStuds", 8) and math.abs(g.Y - y) < 14
			and ArmyFollow.ClearLine(ownerRoot.Position, g + Vector3.new(0, 1.8, 0)) then
			local p = g + Vector3.new(0, 3.2, 0)
			return CFrame.lookAt(p, p + dir)
		end
	end
	return nil
end

-- the throttled per-soldier debug line (DebugLogSeconds): id, slot, position, target, distance, WalkSpeed, mode,
-- time since its last MoveTo, catch-up, recovery stage, pathfinding, stuck timer
local function debugLog(player: Player, a: any, living: { any }, plans: { [any]: any }, ownerPos: Vector3, now: number)
	if now - a.LogAt < num("DebugLogSeconds", 2) then
		return
	end
	a.LogAt = now
	for _, u in ipairs(living) do
		local p = plans[u]
		local pos: Vector3 = u.Root.Position
		local goal: Vector3? = if p then p.Goal else nil
		local lastMove = u._scLastMoveAt
		print(string.format(
			"[ArmyDebug] %s %s slot=%s row=%s pos=(%.1f,%.1f) target=%s dist=%s toPlayer=%.1f ws=%.1f mode=%s sinceMoveTo=%s catchUp=%s recovery=%s path=%s stuck=%.1f",
			player.Name, unitName(u), tostring(a.Assign.ByUnit[u]), tostring(p and p.Row), pos.X, pos.Z,
			if goal then string.format("(%.1f,%.1f)", goal.X, goal.Z) else "-",
			if goal then string.format("%.1f", flatDist(pos, goal)) else "-", flatDist(pos, ownerPos),
			u.Humanoid.WalkSpeed, tostring(u._scState), if lastMove then string.format("%.1f", now - lastMove) else "-",
			tostring(u._scState == "CatchingUp"), tostring(u._scStage or 0), tostring(u._scPath ~= nil),
			if u._scState == "InPosition" then 0 else now - (u._scProgAt or now)))
	end
end

-- claude-bud JOB 23: the owner's formation panel (the WE_ArmyPanel player attribute his ArmyDebugClient shows, every
-- DebugPanelSeconds) and the SPIKE log (a soldier past SpikeErrStuds from its slot, or a slot faster than a soldier can
-- run), both only in debug. Player / desired / actual heading: his facing (display only) / his movement direction
-- (the formation steers to it) / the formation's own heading.
local function yawOf(v: Vector3?): string
	if v == nil or v.Magnitude < 1e-3 then
		return "-"
	end
	return string.format("%.0f", FormationController.YawDeg(v))
end

local function formationDebug(player: Player, a: any, living: { any }, plans: { [any]: any }, proot: BasePart, now: number)
	local f = a.F.Form
	local trail = a.F.Trail
	local mxE, sumE, nC, mxV, worst = 0, 0, 0, 0, nil
	for _, u in ipairs(living) do
		local p = plans[u]
		if p then
			local d = flatDist(u.Root.Position, p.Goal)
			sumE += d
			if d > mxE then
				mxE = d
				worst = u
			end
			if u._scState == "CatchingUp" then
				nC += 1
			end
			mxV = math.max(mxV, tonumber(p.SlotSpeed) or 0)
		end
	end
	local n = math.max(1, #living)
	local spd = if f then f.V.Magnitude else trail.Vel.Magnitude
	local turn = if f then math.deg(math.abs(f.W)) else 0
	local herr = if f then math.deg(math.abs(f.Err)) else 0
	local cap = math.min(num("MaxSpeed", 40), math.max(trail.Vel.Magnitude, 14) + num("SpeedMaxBonus", 14))
	if now - (a.PanelAt or -math.huge) >= num("DebugPanelSeconds", 0.5) then
		a.PanelAt = now
		pcall(function()
			player:SetAttribute("WE_ArmyPanel", string.format(
				"Formation %.1f  Turn %.0f/s\nHeading err %.0f\nPlayer %s  Want %s  Is %s\nMax slot speed %.1f\nSlot err avg %.1f  max %.1f\nCatching up %d/%d",
				spd, turn, herr, yawOf(flat(proot.CFrame.LookVector)), yawOf(if f then f.Hd else trail.Vel), yawOf(if f then f.H else nil),
				mxV, sumE / n, mxE, nC, #living))
		end)
	end
	if (mxE > num("SpikeErrStuds", 6) or mxV > cap) and now - (a.SpikeAt or -math.huge) >= 0.5 then
		a.SpikeAt = now
		print(string.format("[ArmyDebug] SPIKE %s maxErr=%.1f (%s) maxSlotV=%.1f cap=%.1f catching=%d/%d formSpd=%.1f turn=%.0f/s hdgErr=%.0f player=%s desired=%s actual=%s waiting=%s",
			player.Name, mxE, if worst then unitName(worst) else "-", mxV, cap, nC, #living, spd, turn, herr, yawOf(flat(proot.CFrame.LookVector)),
			yawOf(if f then f.Hd else trail.Vel), yawOf(if f then f.H else nil), tostring(f ~= nil and f.Waiting == true)))
	end
end

local function stepArmy(player: Player, st: any, now: number)
	local a = army(st)
	local state = STATE_OF[st.Order] or "FOLLOW"
	local living: { any } = {}
	for _, u in ipairs(st.Units) do
		if u.Alive and u.Humanoid and u.Humanoid.Health > 0 and u.Root and u.Root.Parent then
			table.insert(living, u)
		end
	end
	-- permanent slots (only a roster change touches the table; survivors never move)
	FormationController.Assign(a.Assign, living)
	-- a unit that left the roster (death / dismiss / despawn) frees its slot: logged, nobody else moves
	a.Known = a.Known or {}
	for u, idx in pairs(a.Known) do
		if a.Assign.ByUnit[u] == nil then
			a.Known[u] = nil
			u._acIdx = nil
			ArmyController.Stats.SlotChanges += 1
			warn(string.format("[ArmyDebug] SLOT CHANGE %s %s %d -> none reason=%s", player.Name, unitName(u), idx,
				if u.Alive == false then "death" else "removed"))
		end
	end
	for _, u in ipairs(living) do
		a.Known[u] = a.Assign.ByUnit[u]
	end
	audit(st, a, now)
	local prevState = a.State
	a.State = state
	local debugOn = ArmyController.DebugFor(player)
	-- JOB 24: ATTACK is steered here as well (the block advances on the squad target, deploys, folds back); the
	-- squad target is SquadOrdersService's (st._acTarget, server-side NPC roots only; it only shoots and aims)
	local attackOn = state == "ATTACK" and ArmyController.AttackLive(player.UserId)
	local wasDriven = a.Driven == true
	if state ~= "FOLLOW" and not attackOn then
		-- HOLD / RETREAT (and ATTACK with AttackSteer off): SquadOrdersService issues their goals (through
		-- SoldierController); nothing here
		a.LastPos = nil
		a.Driven = false
		a.F.Attack = nil
		publish(player, st, a, {}, false)
		return
	end
	local root: BasePart? = deps.CharacterRoot and deps.CharacterRoot(player)
	-- claude-bud JOB 38: an army plan (ArmyPlan: ATTACK auto-clear / SEND / RECALL) walks a LEAD POINT; the block follows
	-- it exactly as it follows him (the same Plan / steering / caps), even while he is dead. No recover / reposition.
	local planLead: any = if ArmyController.PlanLead ~= nil then ArmyController.PlanLead(player) else nil
	if planLead ~= nil then
		root = planLead.Root :: any
	end
	if root == nil then
		-- the owner is dead: stop once, wait
		for _, u in ipairs(living) do
			if u._acIdle ~= true then
				u._acIdle = true
				SoldierController.Stop(u, "Hold")
			end
		end
		a.LastPos = nil
		return
	end
	local proot = root :: BasePart
	local pos = proot.Position
	local dt = if a.LastAt then math.clamp(now - a.LastAt, 0.01, 1) else num("UpdateSeconds", 0.2)
	local vel = Vector3.zero
	local jumped = false
	local fresh = a.LastPos == nil -- first tick after a gap (respawn, order change): the trail restarts behind him
	local hum = proot.Parent and proot.Parent:FindFirstChildOfClass("Humanoid")
	local seated = hum ~= nil and (hum.Sit or hum.SeatPart ~= nil)
	if a.LastPos then
		vel = flat(pos - a.LastPos) / dt
		if not seated and vel.Magnitude > num("OwnerJumpSpeed", 80) then
			jumped = true -- a teleport / respawn: the trail restarts (no sweep across the map)
			vel = Vector3.zero
		end
	end
	a.LastPos = pos
	a.LastAt = now
	-- his root's velocity NOW (the lane his next second of walking sweeps: rows he walks back into part)
	local ownerVelNow = flat(proot.AssemblyLinearVelocity)
	if jumped or seated then
		ownerVelNow = vel
	end
	-- claude-bud JOB 32: inside / on top of an enterable building -> plan round the street point outside its door,
	-- facing the building (the block forms behind that point, out in the street); no speed, so nothing snaps or recovers
	local lookVec = proot.CFrame.LookVector
	local indoorCfg: any = (ArmyConfig :: any).Indoors
	local held = if typeof(indoorCfg) == "table" and indoorCfg.Enabled == true then Enterables.At(pos) else nil
	if held then
		pos = Vector3.new(held.Door.X, held.Door.Y + 3, held.Door.Z) -- street level (a root is ~3 above the ground)
		lookVec = held.Face
		vel = Vector3.zero
		ownerVelNow = Vector3.zero
		if a.HeldAt ~= held.Id then
			a.HeldAt = held.Id
			if debugOn then
				warn(string.format("[ArmyDebug] %s is inside %s: the army holds at its door", player.Name, held.Id))
			end
		end
	elseif a.HeldAt ~= nil then
		a.HeldAt = nil
	end
	-- (FOLLOW <-> ATTACK keeps the block: no restart; only a spell under HOLD / RETREAT restarts it behind him)
	local snap = jumped or fresh or prevState ~= "FOLLOW" and not (wasDriven and (prevState == "ATTACK" or prevState == "FOLLOW"))
	a.Driven = true
	local c = cfg()
	local tgt = if attackOn then st._acTarget else nil
	local troot: BasePart? = if tgt then tgt.Root else nil
	a.F.Attack = if troot and troot.Parent then { Pos = troot.Position } else nil
	local plans: any, _frames: any, cols: any, last: any
	if held then
		-- claude-bud JOB 32: held at a door: the block faces the building from the street
		plans, _frames, cols, last = FormationController.Plan(a.F, living, pos, lookVec, vel, dt, snap, escOf, c, ownerVelNow)
	else
		plans, _frames, cols, last = FormationController.Plan(a.F, living, pos, proot.CFrame.LookVector, vel, dt, snap, escOf, c, ownerVelNow)
	end
	local key = tostring(cols) .. "x" .. tostring(last + 1)
	if a.LayoutKey ~= nil and a.LayoutKey ~= key then
		warn(string.format("[ArmyDebug] LAYOUT CHANGE %s %s -> %s (columns x rows; roster / escort count changed)", player.Name, a.LayoutKey, key))
	end
	a.LayoutKey = key
	publish(player, st, a, plans, debugOn)
	local trail = a.F.Trail
	local inBase, plotId = ArmyFollow.BaseState(st, player, pos, now)
	local tidy = st._afTidy == true
	local ownPlot: number? = if tidy then st._afOwnPlot else nil
	local walkBack = tidy and not inBase and now - (st._afLeftBaseAt or -math.huge) < 8
	local speedSmooth = trail.Vel.Magnitude
	local drivingFast = seated and speedSmooth > num("VehicleDeferSpeed", 20)
	local base = tonumber((deps.UnitWalkSpeed or function()
		return 14
	end)()) or 14
	for _, u in ipairs(living) do
		u._acIdle = false
		local idx = a.Assign.ByUnit[u] or 1
		local p = plans[u]
		local goal: Vector3 = if p then p.Goal else pos
		local heading: Vector3 = if p then p.Heading else flat(proot.CFrame.LookVector)
		local moving = FormationController.BlockMoving(a.F, c) -- (his walk, or an ATTACK block advancing / deploying)
		-- its pace = its OWN slot's speed (a row rounding a corner outside moves faster than him, inside slower)
		local pace = if p then p.Pace else 0
		if seated then
			pace = math.max(16, math.min(math.max(pace, speedSmooth), num("CatchUpMin", 30)))
		end
		local lead = if p and (moving or c.Steer == true) then p.Lead else Vector3.zero
		local allow = not drivingFast and not walkBack and planLead == nil -- claude-bud JOB 38: never during a plan
		local noPath = false
		local clear = num("OwnerClearStuds", 5)
		local upos = u.Root.Position
		local vel0 = ownerVelNow
		if inBase and plotId and a.F.Attack == nil then
			-- his base: its gate cell (straight, never through his plot), standing facing out
			local cell, out = ArmyFollow.HoldSpot(plotId, idx)
			goal = Vector3.new(cell.X, pos.Y, cell.Z)
			heading = out
			moving = false
			lead = Vector3.zero
			clear = 0
			vel0 = Vector3.zero
			if not ArmyFollow.InPlot(plotId, upos, 0) then
				goal = ArmyFollow.HoldVia(plotId, upos, goal)
				noPath = true
				allow = false
			end
		elseif ownPlot and not ArmyFollow.InPlot(ownPlot, upos, 0) and ArmyFollow.InPlot(ownPlot, goal, 2) then
			-- a unit outside his plot never gets a goal inside it
			local cell = ArmyFollow.HoldSpot(ownPlot, idx)
			goal = Vector3.new(cell.X, pos.Y, cell.Z)
		end
		local g, h = goal, heading
		local okU, errU = pcall(SoldierController.Drive, u, {
			Goal = goal,
			Heading = heading,
			Lead = lead,
			OwnerPos = pos,
			OwnerVel = vel0,
			OwnerMoving = moving,
			Pace = pace,
			BaseSpeed = base,
			Dt = dt,
			Now = now,
			AllowRecover = allow,
			Jumped = jumped,
			NoPath = noPath,
			NoReposition = planLead ~= nil, -- claude-bud JOB 38: a plan's unit that cannot follow is marked LOST, never moved
			OwnerClear = clear,
			Spot = function()
				return repositionSpot(proot, g, h)
			end,
			OutOfView = function(q: Vector3): boolean
				return outOfView(proot, q)
			end,
		})
		if not okU then
			-- one unit's error never stops the rest of the army (logged by the caller's rate limit)
			ArmyController.Stats.Errors += 1
			if now - (errAt[-player.UserId] or -math.huge) > 30 then
				errAt[-player.UserId] = now
				warn("[ArmyController] unit tick error for " .. tostring(player.UserId) .. ": " .. tostring(errU))
			end
		end
	end
	if debugOn then
		debugLog(player, a, living, plans, pos, now)
		formationDebug(player, a, living, plans, proot, now)
		a.PanelOn = true
	elseif a.PanelOn then
		a.PanelOn = nil
		pcall(function()
			player:SetAttribute("WE_ArmyPanel", nil)
		end)
	end
end
ArmyController._StepArmy = stepArmy

-- deps: Squads() -> { [userId]: st }, CharacterRoot(player) -> BasePart?, UnitWalkSpeed() -> number
function ArmyController.Start(d: { [string]: any })
	deps = d
	SoldierController.Bind({ ClearLine = ArmyFollow.ClearLine })
	if started then
		return
	end
	started = true
	task.spawn(function()
		while true do
			task.wait(math.clamp(num("UpdateSeconds", 0.2), 0.1, 0.5))
			local now = os.clock()
			local squads = deps.Squads and deps.Squads() or {}
			for _, player in ipairs(Players:GetPlayers()) do
				local st = squads[player.UserId]
				if st and #st.Units > 0 and ArmyController.LiveFor(player.UserId) then
					local ok, err = pcall(stepArmy, player, st, now)
					ArmyController.Stats.Ticks += 1
					if not ok then
						ArmyController.Stats.Errors += 1
						if now - (errAt[player.UserId] or -math.huge) > 30 then
							errAt[player.UserId] = now
							warn("[ArmyController] tick error for " .. tostring(player.UserId) .. ": " .. tostring(err))
						end
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p: Player)
		errAt[p.UserId] = nil
		errAt[-p.UserId] = nil
	end)
	-- debug overlay default ON for Follow3.DebugUserIds (the owner); /armydebug (AdminService) toggles WE_ArmyDebug
	local function debugDefault(p: Player)
		if cfg().Debug == true and isDebugUser(p.UserId) and p:GetAttribute("WE_ArmyDebug") == nil then
			p:SetAttribute("WE_ArmyDebug", true)
		end
	end
	Players.PlayerAdded:Connect(debugDefault)
	for _, p in ipairs(Players:GetPlayers()) do
		debugDefault(p)
	end
	print("[ArmyController] v115 Follow3 TrailBlock controller started (" .. tostring(cfg().Enabled) .. ", " .. tostring(cfg().Rollout) .. ", debug " .. tostring(cfg().Debug) .. ")")
end

return ArmyController
