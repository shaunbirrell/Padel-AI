--!strict
--[[
	claude-bud JOB 22 (2026-09-29): the army formation's pure maths (docs/ARMY-FOLLOW-ROOTCAUSE.md). No instances, no
	services: ArmyFollow calls it every think, tools/checks/claude_bud_armyfollow.py simulates it in the Luau CLI.
	  * Anchor: position follows the owner with a small lag; velocity is smoothed; the lead comes from the SMOOTHED
	    velocity (capped). Heading follows his FACING (a walking character faces where it walks; backing up or strafing
	    with shift-lock keeps his facing, so the formation never flips) at a capped turn rate; turns under a deadzone are
	    ignored; an about-turn past ReverseDeg turns the formation only after it held for ReverseHoldSeconds, never 180°
	    at once. Standing, the heading re-aims to his facing only after he turned past StandAlignDeg for
	    StandAlignSeconds.
	  * State: InPosition (within ArriveDeadzone, left only past LeaveDeadzone: hysteresis) / Following / CatchingUp.
	  * Reissue: a new MoveTo only when the target moved MoveReissueStuds or MoveRefreshSeconds passed.
	Vectors are flat (Y ignored); headings are unit vectors on XZ.
]]

local FormationMath = {}

export type Anchor = {
	Pos: Vector3?,
	Vel: Vector3,
	Dir: Vector3?,
	RevSince: number?,
	StandSince: number?,
}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function unitOr(v: Vector3, fallback: Vector3): Vector3
	return if v.Magnitude > 1e-4 then v.Unit else fallback
end

-- signed angle (radians) from a to b about +Y (both flat unit vectors)
function FormationMath.Angle(a: Vector3, b: Vector3): number
	local x = math.atan2(a.X, a.Z)
	local y = math.atan2(b.X, b.Z)
	return (y - x + math.pi) % (2 * math.pi) - math.pi
end

function FormationMath.Turn(cur: Vector3, want: Vector3, maxRad: number): Vector3
	local d = FormationMath.Angle(cur, want)
	if math.abs(d) <= maxRad then
		return want
	end
	local r = math.atan2(cur.X, cur.Z) + (if d > 0 then maxRad else -maxRad)
	return Vector3.new(math.sin(r), 0, math.cos(r))
end

function FormationMath.NewAnchor(): Anchor
	return { Pos = nil, Vel = Vector3.zero, Dir = nil, RevSince = nil, StandSince = nil }
end

--[[ One step. ownerPos / ownerLook: his root position and LookVector; vel: his measured flat velocity this step;
	snap: a teleport / respawn / vehicle (no lag). cfg: ArmyConfig.Follow2 (Anchor* / Heading* / Reverse* / Stand*). ]]
function FormationMath.Step(a: Anchor, ownerPos: Vector3, ownerLook: Vector3, vel: Vector3, dt: number, now: number, snap: boolean, cfg: any)
	dt = math.clamp(dt, 0, 1)
	local lag = math.max(1e-3, tonumber(cfg.AnchorPosLagSeconds) or 0.25)
	local vs = math.max(1e-3, tonumber(cfg.AnchorVelSmoothSeconds) or 0.5)
	if a.Pos == nil or snap then
		a.Pos = ownerPos
		a.Vel = flat(vel)
	else
		local k = math.clamp(dt / lag, 0, 1)
		a.Pos = (a.Pos :: Vector3):Lerp(ownerPos, k)
		a.Vel = a.Vel:Lerp(flat(vel), math.clamp(dt / vs, 0, 1))
	end
	local look = unitOr(flat(ownerLook), Vector3.new(0, 0, -1))
	local speed = a.Vel.Magnitude
	local moving = speed >= (tonumber(cfg.HeadingMoveSpeed) or 3)
	if a.Dir == nil or snap then
		a.Dir = look
		a.RevSince, a.StandSince = nil, nil
		return
	end
	local cur = a.Dir :: Vector3
	local rate = math.rad(tonumber(cfg.HeadingTurnDegPerSec) or 90) * dt
	if moving then
		a.StandSince = nil
		local want = look -- his facing, never his raw velocity (walking back / strafing does not flip the formation)
		local ang = math.abs(FormationMath.Angle(cur, want))
		if ang < math.rad(tonumber(cfg.HeadingDeadzoneDeg) or 20) then
			a.RevSince = nil
			return -- small turns ignored
		end
		if ang > math.rad(tonumber(cfg.ReverseDeg) or 120) then
			-- walking back / a hard strafe: hold the formation until it clearly is the new direction
			a.RevSince = a.RevSince or now
			if now - (a.RevSince :: number) < (tonumber(cfg.ReverseHoldSeconds) or 1.5) then
				return
			end
		else
			a.RevSince = nil
		end
		a.Dir = FormationMath.Turn(cur, want, rate)
	else
		a.RevSince = nil
		local ang = math.abs(FormationMath.Angle(cur, look))
		if ang > math.rad(tonumber(cfg.StandAlignDeg) or 60) then
			a.StandSince = a.StandSince or now
			if now - (a.StandSince :: number) >= (tonumber(cfg.StandAlignSeconds) or 1.2) then
				a.Dir = FormationMath.Turn(cur, look, rate)
			end
		elseif a.StandSince ~= nil then
			-- aligning: finish the turn once started, then settle
			a.Dir = FormationMath.Turn(cur, look, rate)
			if ang < math.rad(2) then
				a.StandSince = nil
			end
		end
	end
end

-- the anchor frame's world point of a seat offset (lat = +right, back = +behind), plus the smoothed lead (capped)
function FormationMath.SlotWorld(a: Anchor, lat: number, back: number, y: number, cfg: any): Vector3
	local dir = (a.Dir or Vector3.new(0, 0, -1)) :: Vector3
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local lead = a.Vel * (tonumber(cfg.AnchorLeadSeconds) or 0.4)
	local cap = tonumber(cfg.AnchorLeadMaxStuds) or 4
	if lead.Magnitude > cap then
		lead = lead.Unit * cap
	end
	local p = (a.Pos or Vector3.zero) :: Vector3
	local w = p + right * lat - dir * back + lead
	return Vector3.new(w.X, y, w.Z)
end

--[[ The follow state of one soldier from its flat distance to its slot. InPosition holds until LeaveDeadzone. ]]
function FormationMath.State(prev: string?, d: number, cfg: any): string
	local arrive = tonumber(cfg.ArriveDeadzoneStuds) or 1.5
	local leave = tonumber(cfg.LeaveDeadzoneStuds) or 3
	if prev == "InPosition" and d <= leave then
		return "InPosition"
	end
	if d <= arrive then
		return "InPosition"
	end
	if d > (tonumber(cfg.CatchUpStartStuds) or 5) then
		return "CatchingUp"
	end
	return "Following"
end

-- a new MoveTo is due: first one, the target moved past MoveReissueStuds, or MoveRefreshSeconds passed
function FormationMath.ReissueDue(lastGoal: Vector3?, lastAt: number?, goal: Vector3, now: number, cfg: any): boolean
	if lastGoal == nil or lastAt == nil then
		return true
	end
	local lg = lastGoal :: Vector3
	local moved = Vector3.new(goal.X - lg.X, 0, goal.Z - lg.Z).Magnitude
	return moved >= (tonumber(cfg.MoveReissueStuds) or 2.5) or now - (lastAt :: number) >= (tonumber(cfg.MoveRefreshSeconds) or 0.5)
end

-- the owner is "moving" (escort vs follow switch) with hysteresis
function FormationMath.Moving(wasMoving: boolean, speed: number, cfg: any): boolean
	if wasMoving then
		return speed >= (tonumber(cfg.MovingOffSpeed) or 1.2)
	end
	return speed >= (tonumber(cfg.MovingOnSpeed) or 2.5)
end

return FormationMath
