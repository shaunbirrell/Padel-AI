--!strict
--[[
	v115 (Code Bot Roblox, 2026-09-29, docs/ARMY-FOLLOW-ROOTCAUSE-3.md): no more "wheel" (v114 sent a unit whose slot
	had swung round the anchor on an arc round the OUTSIDE: that arc was the orbit / the U round the player). Slots now
	sit on his breadcrumb trail (FormationController), so a unit only ever walks to its own slot (+ its slot's own
	velocity lead). Catch-up has hysteresis (CatchUpStartStuds on / CatchUpEndStuds off). Every Reposition (the only
	PivotTo) is a loud warn with its distance to its slot and to him, the reason and the previous state.

	v114 (Code Bot Roblox, 2026-09-29, docs/ARMY-FOLLOW-ROOTCAUSE-2.md): SoldierController — the ONE writer of an army
	soldier's movement. Every Humanoid:MoveTo on a squad unit (WE_SquadUnit, Workspace.WarEmpireSquads) goes through
	SoldierController.Move / Stop (ArmyFollow.Command, the v113 API that SquadOrdersService's HOLD / ATTACK / RETREAT
	code calls, forwards here), and the only PivotTo is SoldierController.Reposition (the emergency fallback: under the
	map, extremely far for seconds, stuck for StuckRepositionSeconds far away and out of his view).

	Drive(unit, ctx) is one FOLLOW tick for one unit (ArmyController, every Follow3.UpdateSeconds):
	  * state InPosition (within ArriveStuds while he stands, left only past LeaveStuds) / Following / CatchingUp /
	    StuckRecovery; InPosition issues ONE stop, then nothing.
	  * MoveTo only when the goal moved ReissueStuds (or RefreshSeconds passed); while he moves the goal is its slot +
	    his smoothed lead, so a unit in its slot keeps walking instead of stop-start.
	  * WalkSpeed = his pace + CatchUpPerStud per stud from its OWN slot, capped, rate-limited per tick.
	  * Yaw: walking = AutoRotate (faces travel, the face gyro has no torque); in its slot = the gyro, whose target
	    starts at the unit's CURRENT yaw and turns toward the heading at FaceTurnDegPerSec (no snap).
	  * Stuck: progress < StuckProgressStuds over StuckReissueSeconds while its goal is beyond the deadzone ->
	    1) re-issue + jump, 2) a path, 3) a reachable point beside it, 4) reposition (far + out of view only).
]]

local Workspace = game:GetService("Workspace")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArmyConfig = require(Shared.Configs.ArmyConfig)

local SoldierController = {}
SoldierController.Stats = { Moves = 0, Stops = 0, Repositions = 0, Paths = 0, Stuck = 0 }

local deps: { [string]: any } = {}
local pathBudget = { At = 0, N = 0 }
local logAt: { [string]: number } = {}

local function cfg(): { [string]: any }
	local c = (ArmyConfig :: any).Follow3
	return if typeof(c) == "table" then c else {}
end

local function num(key: string, default: number): number
	local v = cfg()[key]
	return if typeof(v) == "number" then v else default
end

function SoldierController.Bind(d: { [string]: any })
	deps = d
end

local function logLine(key: string, msg: string)
	local now = os.clock()
	if now - (logAt[key] or -math.huge) >= num("LogSeconds", 5) then
		logAt[key] = now
		print("[SoldierController] " .. msg)
	end
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDist(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function setState(unit: any, state: string)
	if unit.MoveState ~= state or unit._afState ~= state then
		unit._afState = state
		unit.MoveState = state
		pcall(function()
			unit.Model:SetAttribute("WE_MoveState", state) -- debugging (only on change)
		end)
	end
end
SoldierController.SetState = setState

-- ── the only MoveTo on a soldier ──────────────────────────────────────────────────────────────────────────────────
function SoldierController.Move(unit: any, goal: Vector3, state: string?)
	if state then
		setState(unit, state)
	end
	SoldierController.Stats.Moves += 1
	unit._scLastMoveAt = os.clock()
	unit.Humanoid:MoveTo(goal)
end

-- stop where it stands (MoveTo its own position)
function SoldierController.Stop(unit: any, state: string?)
	if state then
		setState(unit, state)
	end
	SoldierController.Stats.Stops += 1
	unit.Humanoid:MoveTo(unit.Root.Position)
end

function SoldierController.SetSpeed(unit: any, s: number)
	local hum: Humanoid = unit.Humanoid
	unit._scSpeed = s
	if math.abs(hum.WalkSpeed - s) >= 0.5 then
		hum.WalkSpeed = s
		unit.Speed = s -- SquadOrdersService's WalkSpeed cache stays true
	end
end

-- ── yaw: one owner ────────────────────────────────────────────────────────────────────────────────────────────────
local function gyroOf(unit: any): BodyGyro?
	local g = unit.Root and unit.Root:FindFirstChild("NPCFaceGyro")
	return if g and g:IsA("BodyGyro") then g else nil
end

local function currentLook(unit: any): Vector3
	local l = flat(unit.Root.CFrame.LookVector)
	return if l.Magnitude > 1e-3 then l.Unit else Vector3.new(0, 0, -1)
end

-- walking: AutoRotate faces travel; the face gyro has no torque (the escort's aim cannot turn it sideways)
function SoldierController.YawTravel(unit: any)
	if unit._scYaw == "travel" then
		return
	end
	unit._scYaw = "travel"
	local g = gyroOf(unit)
	if g then
		if unit._scTorque == nil then
			unit._scTorque = g.MaxTorque
		end
		g.MaxTorque = Vector3.zero
	end
	pcall(function()
		unit.Humanoid.AutoRotate = true
	end)
end

-- in its slot: the gyro holds `dir`; its target STARTS at the unit's current yaw (no snap) and turns at
-- FaceTurnDegPerSec; right after a shot the escort's aim is kept (FaceAfterShotSeconds)
function SoldierController.YawHold(unit: any, dir: Vector3?, dt: number, now: number)
	local g = gyroOf(unit)
	if unit._scYaw ~= "hold" then
		unit._scYaw = "hold"
		pcall(function()
			unit.Humanoid.AutoRotate = false
		end)
		if g then
			if unit._scTorque == nil then
				unit._scTorque = if g.MaxTorque.Magnitude > 0 then g.MaxTorque else Vector3.new(0, 4e5, 0)
			end
			g.CFrame = CFrame.lookAt(Vector3.zero, currentLook(unit))
			g.MaxTorque = unit._scTorque
		end
	end
	if g == nil or dir == nil then
		return
	end
	if now - (tonumber(unit.LastFireAt) or -math.huge) < num("FaceAfterShotSeconds", 1.2) then
		return
	end
	local want = flat(dir :: Vector3)
	if want.Magnitude < 1e-3 then
		return
	end
	want = want.Unit
	local cur = flat(g.CFrame.LookVector)
	cur = if cur.Magnitude > 1e-3 then cur.Unit else currentLook(unit)
	local a = math.atan2(cur.X, cur.Z)
	local b = math.atan2(want.X, want.Z)
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	if math.abs(d) < math.rad(2) then
		return
	end
	local step = math.rad(num("FaceTurnDegPerSec", 240)) * math.max(dt, 0.05)
	local r = a + math.clamp(d, -step, step)
	g.CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(math.sin(r), 0, math.cos(r)))
end

-- another order (HOLD / ATTACK / RETREAT) takes the unit: the gyro gets its torque back aimed at the CURRENT yaw
function SoldierController.Release(unit: any)
	if not unit._scCtl and unit._scYaw == nil then
		return
	end
	unit._scCtl = false
	local g = gyroOf(unit)
	if g and unit.Root then
		g.CFrame = CFrame.lookAt(Vector3.zero, currentLook(unit))
		if unit._scTorque ~= nil then
			g.MaxTorque = unit._scTorque
		end
	end
	pcall(function()
		unit.Humanoid.AutoRotate = true
	end)
	unit._scYaw = nil
	SoldierController.Reset(unit)
end

-- fresh movement state (the slot assignment lives in ArmyController / FormationController and is NOT touched)
function SoldierController.Reset(unit: any)
	unit._scGoal = nil
	unit._scGoalAt = nil
	unit._scProgPos = nil
	unit._scProgAt = nil
	unit._scStage = 0
	unit._scFarSince = nil
	unit._scPath = nil
	unit._scAlt = nil
	unit._scBlocked = 0
	unit._scState = nil
end

function SoldierController.Acquire(unit: any, now: number)
	if not unit._scCtl or now - (unit._scTickAt or -math.huge) > 1.5 then
		SoldierController.Reset(unit)
		unit._scCtl = true
		unit._scYaw = nil
	end
	unit._scTickAt = now
end

-- ── the emergency reposition: the only PivotTo on a soldier ──────────────────────────────────────────────────────
function SoldierController.Reposition(unit: any, cf: CFrame, why: string, skipCooldown: boolean?): boolean
	local now = os.clock()
	if not skipCooldown and now < (unit._scRepAt or -math.huge) then
		return false
	end
	unit._scRepAt = now + num("RepositionCooldown", 5)
	-- v115: every reposition is loud (the owner's debug and the logs must show any teleport)
	local from: Vector3 = unit.Root.Position
	local dbg = unit._scDbg
	local toSlot = if dbg and dbg.Goal then flatDist(from, dbg.Goal) else -1
	local toOwner = if dbg and dbg.Owner then flatDist(from, dbg.Owner) else -1
	warn(string.format("[ArmyDebug] REPOSITION unit %s slot %s reason=%s prevState=%s distToSlot=%.1f distToPlayer=%.1f jump=%.1f owner=%s",
		tostring(unit.Id), tostring(unit._acIdx), why, tostring(unit._scState or unit.MoveState), toSlot, toOwner, flatDist(from, cf.Position), tostring(unit.OwnerUserId)))
	unit.Model:PivotTo(cf)
	unit.Root.AssemblyLinearVelocity = Vector3.zero
	unit.Root.AssemblyAngularVelocity = Vector3.zero
	SoldierController.Reset(unit)
	SoldierController.Move(unit, cf.Position, "StuckRecovery")
	unit._scGoal = cf.Position
	unit._scGoalAt = now
	SoldierController.Stats.Repositions += 1
	logLine("rep" .. tostring(unit.OwnerUserId) .. why, string.format("reposition unit %s (%s) owner %s", tostring(unit.Id), why, tostring(unit.OwnerUserId)))
	return true
end

-- ── paths (stuck stage 2 / a blocked line) ────────────────────────────────────────────────────────────────────────
local function requestPath(unit: any, from: Vector3, to: Vector3, now: number, force: boolean)
	if unit._scPathBusy or (not force and now < (unit._scPathNext or -math.huge)) then
		return
	end
	if now - pathBudget.At >= 1 then
		pathBudget.At = now
		pathBudget.N = 0
	end
	if pathBudget.N >= num("PathBudgetPerSecond", 8) then
		return
	end
	pathBudget.N += 1
	unit._scPathBusy = true
	unit._scPathNext = now + num("PathCooldown", 1.5)
	SoldierController.Stats.Paths += 1
	task.spawn(function()
		local ok, path = pcall(function()
			local p = PathfindingService:CreatePath({ AgentRadius = 1.5, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 6 })
			p:ComputeAsync(from, to)
			return p
		end)
		unit._scPathBusy = false
		if ok and path and path.Status == Enum.PathStatus.Success then
			local wps = path:GetWaypoints()
			unit._scPath = { Points = wps, I = math.min(2, #wps), Goal = to, At = os.clock() }
		else
			unit._scPath = nil
		end
	end)
end

local function clearLine(a: Vector3, b: Vector3): boolean
	local f = deps.ClearLine
	return if f then f(a, b) == true else true
end

-- the next waypoint of a kept path (passed ones skipped), or nil
local function pathPoint(unit: any, pos: Vector3, goal: Vector3, now: number): Vector3?
	local path = unit._scPath
	if path == nil then
		return nil
	end
	if now - (path.At or 0) > num("PathKeepSeconds", 2.5) and flatDist(path.Goal, goal) > num("PathKeepStuds", 10) then
		unit._scPath = nil
		return nil
	end
	local wp = path.Points[path.I]
	while wp do
		local nxt = path.Points[path.I + 1]
		if flatDist(pos, wp.Position) < 3 or (nxt ~= nil and flatDist(pos, nxt.Position) < flatDist(wp.Position, nxt.Position)) then
			path.I += 1
			wp = path.Points[path.I]
		else
			break
		end
	end
	if wp == nil then
		unit._scPath = nil
		return nil
	end
	if wp.Action == Enum.PathWaypointAction.Jump then
		unit.Humanoid.Jump = true
	end
	return wp.Position
end

--[[ One FOLLOW tick for one unit. ctx:
	Goal: Vector3 (its slot, world), Heading: Vector3 (formation heading, or the hold facing), Lead: Vector3,
	OwnerPos: Vector3, OwnerMoving: boolean, Pace: number (his speed), Dt: number, Now: number,
	AllowRecover: boolean (false while he drives fast / just left his base), NoPath: boolean (base hold: straight only),
	OwnerClear: number (0 = off), Spot: () -> CFrame? (the reposition spot), OutOfView: (Vector3) -> boolean ]]
function SoldierController.Drive(unit: any, ctx: { [string]: any })
	local now: number = ctx.Now
	local dt: number = ctx.Dt
	SoldierController.Acquire(unit, now)
	local pos: Vector3 = unit.Root.Position
	local ownerPos: Vector3 = ctx.OwnerPos
	local clear = tonumber(ctx.OwnerClear) or 0
	-- v115: his walking lane (OwnerAheadSeconds of his travel ahead of him, LaneHalfStuds each side). The rows he walks
	-- back into already part (FormationController.Part keeps each half's column order); a unit that is itself IN his
	-- lane and would have to cross in front of him to reach its goal steps out to its OWN side first and waits there
	-- until he is past (never across his path, never into him)
	local ov: Vector3 = flat(ctx.OwnerVel or Vector3.zero)
	local ospeed = ov.Magnitude
	local laneDir: Vector3? = if ospeed > num("MovingOnSpeed", 3) and cfg().YieldLane ~= false then ov / ospeed else nil
	local laneLen = math.min(ospeed * num("OwnerAheadSeconds", 1), num("OwnerAheadMaxStuds", 16))
	local laneHalf = num("LaneHalfStuds", 3.5)
	local yielding = false
	local mySide = 0
	if laneDir then
		local ld = laneDir :: Vector3
		local side = Vector3.new(-ld.Z, 0, ld.X)
		local me = flat(pos - ownerPos)
		local myAlong, myLat = me:Dot(ld), me:Dot(side)
		if myAlong > -1 and myAlong < laneLen and math.abs(myLat) < laneHalf + 1 then
			mySide = if myLat >= 0 then 1 else -1
		end
	end
	-- a point is never inside OwnerClear of him (pushed straight out from him); for a unit in his lane (above) a point
	-- across his path or in his lane is moved out to the unit's own side
	local function clearOf(p: Vector3): Vector3
		if clear <= 0 then
			return p
		end
		local off = flat(p - ownerPos)
		if laneDir and mySide ~= 0 then
			local ld = laneDir :: Vector3
			local side = Vector3.new(-ld.Z, 0, ld.X)
			local along = off:Dot(ld)
			local lat = off:Dot(side)
			if lat * mySide < laneHalf and along > -clear then
				p = Vector3.new(ownerPos.X, p.Y, ownerPos.Z) + ld * math.max(along, 0) + side * (mySide * laneHalf)
				off = flat(p - ownerPos)
				yielding = true
			end
		end
		if off.Magnitude >= clear then
			return p
		end
		local out = if off.Magnitude > 1e-3 then off.Unit else flat(pos - ownerPos)
		out = if out.Magnitude > 1e-3 then out.Unit else Vector3.new(1, 0, 0)
		return Vector3.new(ownerPos.X, p.Y, ownerPos.Z) + out * clear
	end
	local goal: Vector3 = clearOf(ctx.Goal)
	local d = flatDist(pos, goal)
	unit._scDbg = unit._scDbg or {}
	unit._scDbg.Goal = goal
	unit._scDbg.Owner = ownerPos
	unit._scDbg.D = d
	local moving = ctx.OwnerMoving == true

	-- 0) emergencies: under the map (always), extremely far for FarSeconds (not while he drives fast)
	local fph = Workspace.FallenPartsDestroyHeight
	if pos.Y < ownerPos.Y - num("VoidBelowOwner", 60) or pos.Y < fph + num("VoidMargin", 80) then
		local spot = ctx.Spot and ctx.Spot()
		if spot and SoldierController.Reposition(unit, spot, "void") then
			return
		end
	end
	if ctx.AllowRecover and d > num("FarStuds", 120) then
		unit._scFarSince = unit._scFarSince or now
		if ctx.Jumped or now - unit._scFarSince >= num("FarSeconds", 4) then
			local spot = ctx.Spot and ctx.Spot()
			if spot and SoldierController.Reposition(unit, spot, if ctx.Jumped then "owner-jump" else "far") then
				return
			end
		end
	else
		unit._scFarSince = nil
	end

	-- 1) state (arrival deadzone with hysteresis; InPosition only while he stands)
	local prev = unit._scState
	local state: string
	if not moving and ((prev == "InPosition" and d <= num("LeaveStuds", 4)) or d <= num("ArriveStuds", 2.5)) then
		state = "InPosition"
	elseif d > num("CatchUpStartStuds", 6) or (prev == "CatchingUp" and d > num("CatchUpEndStuds", 3)) then
		state = "CatchingUp" -- hysteresis: on past CatchUpStartStuds, off under CatchUpEndStuds
	else
		state = "Following"
	end
	unit._scState = state

	-- the walk target: its slot (+ its slot's lead while he moves), never inside OwnerClear of him
	local target = clearOf(goal + (if moving then (ctx.Lead or Vector3.zero) else Vector3.zero))
	local yieldTo: Vector3? = nil -- (reserved: a unit in his lane yields via clearOf above)

	-- 2) speed: his pace + per stud from its own slot, capped, rate-limited
	local base = tonumber(ctx.BaseSpeed) or 14
	local pace = math.max(if moving then (tonumber(ctx.Pace) or 0) else 0, 0)
	local want: number
	local arrive = num("ArriveStuds", 2.5)
	-- catching up (hysteresis above) raises WalkSpeed toward its OWN slot; in step it only trims
	local gain = if state == "CatchingUp" then num("CatchUpPerStud", 0.9) else num("TrimPerStud", 0.5)
	if moving then
		-- v115: signed along its row's heading (behind its slot: faster, ahead of it: slower; no deadband while he
		-- moves, so it holds its slot instead of trailing ArriveStuds behind it), + the sideways error
		local toGoal = flat(goal - pos)
		local heading: Vector3 = ctx.Heading or Vector3.new(0, 0, -1)
		local e = toGoal:Dot(heading)
		local lat = (toGoal - heading * e).Magnitude
		want = pace + gain * e + num("LateralPerStud", 0.5) * lat
	else
		want = base + num("CatchUpPerStud", 0.9) * math.max(0, d - arrive)
	end
	local cap = math.min(num("MaxSpeed", 40), math.max(pace * num("CatchUpMaxMult", 1.8), num("CatchUpMin", 30)))
	want = math.clamp(want, num("MinSpeed", 8), cap)
	local cur = tonumber(unit._scSpeed) or unit.Humanoid.WalkSpeed
	if yielding then
		-- he walks at it (an about-turn back down his path): it steps out of his lane at once, quickly
		want = math.max(want, num("YieldSpeed", 24))
	else
		want = math.clamp(want, cur - num("SpeedDownPerTick", 5), cur + num("SpeedUpPerTick", 6))
	end
	SoldierController.SetSpeed(unit, want)

	if state == "InPosition" then
		if prev ~= "InPosition" then
			SoldierController.Stop(unit, "InPosition")
			unit._scGoal = pos
			unit._scGoalAt = now
		end
		SoldierController.YawHold(unit, ctx.Heading, dt, now)
		unit._scProgPos = nil
		unit._scStage = 0
		unit._scPath = nil
		unit._scAlt = nil
		return
	end
	SoldierController.YawTravel(unit)

	-- 3) the walk target: computed above (target / yieldTo)

	-- 4) stuck: progress toward anything over time (formation walking moves > StuckProgressStuds: never stuck)
	local forceIssue = prev == "InPosition" or (yielding and not unit._scYielding) -- he set off / walks at it: at once
	unit._scYielding = yielding
	local pp: Vector3? = unit._scProgPos
	if pp == nil or flatDist(pos, pp) >= num("StuckProgressStuds", 1) or d <= arrive + 1 then
		unit._scProgPos = pos
		unit._scProgAt = now
		unit._scStage = 0
	else
		local since = now - (unit._scProgAt or now)
		local stage = unit._scStage or 0
		if since >= num("StuckRepositionSeconds", 10) and ctx.AllowRecover and d > num("StuckRepositionMinStuds", 20)
			and (ctx.OutOfView == nil or ctx.OutOfView(pos)) then
			local spot = ctx.Spot and ctx.Spot()
			if spot and SoldierController.Reposition(unit, spot, "stuck") then
				return
			end
		elseif since >= num("StuckAltSeconds", 7.5) and stage < 3 then
			unit._scStage = 3
			SoldierController.Stats.Stuck += 1
			local to = flat(target - pos)
			to = if to.Magnitude > 1e-3 then to.Unit else Vector3.new(0, 0, -1)
			local side = Vector3.new(-to.Z, 0, to.X) * num("StuckAltStuds", 6)
			for _, sgn in ipairs({ 1, -1 }) do
				local c = pos + side * sgn + to * 2
				if clearLine(pos, c) then
					unit._scAlt = { P = c, Until = now + num("StuckAltHoldSeconds", 2) }
					unit.Humanoid.Jump = true
					break
				end
			end
			forceIssue = true
		elseif since >= num("StuckPathSeconds", 5) and stage < 2 then
			unit._scStage = 2
			if not ctx.NoPath then
				requestPath(unit, pos, target, now, true)
			end
			forceIssue = true
		elseif since >= num("StuckReissueSeconds", 2.5) and stage < 1 then
			unit._scStage = 1
			unit.Humanoid.Jump = true
			forceIssue = true
		end
	end
	setState(unit, if (unit._scStage or 0) > 0 then "StuckRecovery" else state) -- one attribute write per change

	-- 5) where it walks this tick: the side point (stuck 3), a kept path, else straight
	local walkTo = yieldTo or target
	local alt = unit._scAlt
	if alt and not yielding then
		if now < alt.Until and flatDist(pos, alt.P) > 1.5 then
			walkTo = alt.P
		else
			unit._scAlt = nil
		end
	end
	-- never THROUGH him: when the straight line to its target passes within OwnerClear of him, walk round him first
	-- (a point on its own side of him, OwnerClear + 1.5 out); re-evaluated every tick, reissued only past ReissueStuds
	if clear > 0 and not yielding then -- (a yielding unit steps straight out to its own side of his lane)
		local seg = flat(walkTo - pos)
		local len = seg.Magnitude
		if len > 1e-3 then
			local dirS = seg / len
			local rel = flat(ownerPos - pos)
			local along = math.clamp(rel:Dot(dirS), 0, len)
			local closest = flat(pos) + dirS * along
			local off = closest - flat(ownerPos)
			if along > 0 and along < len and off.Magnitude < clear then
				local n = if off.Magnitude > 0.3 then off.Unit else Vector3.new(-dirS.Z, 0, dirS.X) * (if rel:Dot(Vector3.new(-dirS.Z, 0, dirS.X)) > 0 then -1 else 1)
				local via = Vector3.new(ownerPos.X, walkTo.Y, ownerPos.Z) + n * (clear + 1.5) + dirS * 2
				walkTo = via
			end
		end
	end
	if walkTo == target and not ctx.NoPath and not yielding then -- (a round-him / yield point is walked straight: short, in the open)
		if d > num("PathMinStuds", 8) and not clearLine(pos, target) then
			unit._scBlocked = (unit._scBlocked or 0) + 1
			if unit._scBlocked >= num("BlockedPathTicks", 2) and unit._scPath == nil then
				requestPath(unit, pos, target, now, false)
			end
		else
			unit._scBlocked = 0
			if unit._scPath and (unit._scStage or 0) < 2 then
				unit._scPath = nil -- it sees its goal again: straight (the path is dropped once, not toggled per think)
			end
		end
		local wp = pathPoint(unit, pos, target, now)
		if wp then
			walkTo = wp
		end
	end

	-- 6) MoveTo only when the goal moved ReissueStuds (or RefreshSeconds passed, or a stuck stage asks)
	local last: Vector3? = unit._scGoal
	if forceIssue or last == nil or flatDist(last :: Vector3, walkTo) >= num("ReissueStuds", 2.5) or now - (unit._scGoalAt or 0) >= num("RefreshSeconds", 6) then
		SoldierController.Move(unit, walkTo)
		unit._scGoal = walkTo
		unit._scGoalAt = now
	end
end

return SoldierController
