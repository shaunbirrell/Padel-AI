--!strict
--[[
	v114 (Code Bot Roblox, 2026-09-29, docs/ARMY-FOLLOW-ROOTCAUSE-2.md): FormationController — the army formation's pure
	maths. No instances, no services: Server/Modules/ArmyController steps it every Follow3.UpdateSeconds, the client
	RigAnimator reads the same grid for the escort figures, tools/checks/codebot_v114_army.py runs it in the Luau CLI.

	  * Anchor: an exponential follow (AnchorLagSeconds) of his position + a capped lead from his SMOOTHED velocity:
	    no raw-pose jumps, no raw-velocity lead.
	  * Heading: his movement direction while he moves (his facing instead when he walks backwards / strafes: the two
	    disagree by more than FacingAgreeDeg), his facing while he stands (only past StandAlignDeg held
	    StandAlignSeconds). A turn starts only past HeadingDeadbandDeg held HeadingHoldSeconds (ReverseHoldSeconds past
	    ReverseDeg) and runs at HeadingTurnDegPerSec at most, until within 3 degrees: hysteresis, never a flip.
	  * Grid ("Flank"): one row per unit, odd slot index on his left, even on his right; the unit LateralStuds out, its
	    escort figures ColSpacing further out in the same row; rows RowSpacing deep from FrontBack (negative = ahead).
	    Nothing within LateralStuds of the anchor; no two cells closer than min(ColSpacing, RowSpacing).
	  * Assignment: PERMANENT. A unit keeps its slot index for life; a new unit takes its preferred index (its
	    SquadSlot) when free, else the lowest free one; a gone unit frees its index. Survivors are never renumbered and
	    no distance is ever used.
	  * World slot = AnchorCFrame:PointToWorldSpace(Vector3.new(lat, 0, back)).
]]

local FormationController = {}

export type Anchor = {
	Pos: Vector3?,
	Vel: Vector3,
	Dir: Vector3?,
	Moving: boolean,
	Turning: boolean,
	TurnSince: number?,
}

export type Assignment = {
	ByUnit: { [any]: number },
	Taken: { [number]: any },
}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function unitOr(v: Vector3, fallback: Vector3): Vector3
	return if v.Magnitude > 1e-4 then v.Unit else fallback
end

local function n(cfg: any, key: string, default: number): number
	local v = if typeof(cfg) == "table" then cfg[key] else nil
	return if typeof(v) == "number" then v else default
end
FormationController.Num = n

-- signed angle (radians) from a to b about +Y (flat unit vectors)
function FormationController.Angle(a: Vector3, b: Vector3): number
	local x = math.atan2(a.X, a.Z)
	local y = math.atan2(b.X, b.Z)
	return (y - x + math.pi) % (2 * math.pi) - math.pi
end

-- `cur` turned toward `want` by at most maxRad
function FormationController.Turn(cur: Vector3, want: Vector3, maxRad: number): Vector3
	local d = FormationController.Angle(cur, want)
	if math.abs(d) <= maxRad then
		return want
	end
	local r = math.atan2(cur.X, cur.Z) + (if d > 0 then maxRad else -maxRad)
	return Vector3.new(math.sin(r), 0, math.cos(r))
end

-- heading <-> yaw degrees (the WE_FormYaw attribute the client reads)
function FormationController.YawDeg(dir: Vector3): number
	return math.deg(math.atan2(dir.X, dir.Z))
end
function FormationController.DirFromYaw(deg: number): Vector3
	local r = math.rad(deg)
	return Vector3.new(math.sin(r), 0, math.cos(r))
end

function FormationController.NewAnchor(): Anchor
	return { Pos = nil, Vel = Vector3.zero, Dir = nil, Moving = false, Turning = false, TurnSince = nil }
end

function FormationController.NewAssignment(): Assignment
	return { ByUnit = {}, Taken = {} }
end

--[[ One anchor step. ownerPos / ownerLook: his root position and LookVector; vel: his measured flat velocity over this
	step; snap: a teleport / respawn (no lag, heading = his facing). cfg: ArmyConfig.Follow3. ]]
function FormationController.Step(a: Anchor, ownerPos: Vector3, ownerLook: Vector3, vel: Vector3, dt: number, now: number, snap: boolean, cfg: any)
	dt = math.clamp(dt, 0, 1)
	local look = unitOr(flat(ownerLook), Vector3.new(0, 0, -1))
	if a.Pos == nil or snap then
		a.Pos = ownerPos
		a.Vel = flat(vel)
		a.Dir = look
		a.Turning = false
		a.TurnSince = nil
		a.Moving = a.Vel.Magnitude >= n(cfg, "MovingOnSpeed", 3)
		return
	end
	-- smoothed velocity, then the anchor follows (his position + the capped smoothed lead) exponentially
	a.Vel = a.Vel:Lerp(flat(vel), math.clamp(dt / math.max(1e-3, n(cfg, "VelSmoothSeconds", 0.4)), 0, 1))
	local lead = a.Vel * n(cfg, "AnchorLeadSeconds", 0.3)
	local cap = n(cfg, "AnchorLeadMaxStuds", 5)
	if lead.Magnitude > cap then
		lead = lead.Unit * cap
	end
	local target = ownerPos + lead
	local k = 1 - math.exp(-dt / math.max(1e-3, n(cfg, "AnchorLagSeconds", 0.3)))
	a.Pos = (a.Pos :: Vector3):Lerp(target, k)
	-- moving, with hysteresis
	local speed = a.Vel.Magnitude
	if a.Moving then
		a.Moving = speed >= n(cfg, "MovingOffSpeed", 1.5)
	else
		a.Moving = speed >= n(cfg, "MovingOnSpeed", 3)
	end
	local cur = (a.Dir or look) :: Vector3
	local want: Vector3
	local deadband: number
	local hold: number
	if a.Moving then
		local mv = a.Vel.Unit
		-- walking backwards / strafing (shift-lock): he still faces the old way: keep his facing (no flip)
		want = if math.abs(FormationController.Angle(look, mv)) <= math.rad(n(cfg, "FacingAgreeDeg", 75)) then mv else look
		deadband = n(cfg, "HeadingDeadbandDeg", 18)
		hold = n(cfg, "HeadingHoldSeconds", 0.3)
	else
		want = look
		deadband = n(cfg, "StandAlignDeg", 60)
		hold = n(cfg, "StandAlignSeconds", 1.2)
	end
	local ang = math.abs(FormationController.Angle(cur, want))
	if ang > math.rad(n(cfg, "ReverseDeg", 135)) then
		hold = math.max(hold, n(cfg, "ReverseHoldSeconds", 1.0))
	end
	if not a.Turning then
		if ang > math.rad(deadband) then
			a.TurnSince = a.TurnSince or now
			if now - (a.TurnSince :: number) >= hold then
				a.Turning = true
			end
		else
			a.TurnSince = nil
		end
	end
	if a.Turning then
		a.Dir = FormationController.Turn(cur, want, math.rad(n(cfg, "HeadingTurnDegPerSec", 100)) * dt)
		if math.abs(FormationController.Angle(a.Dir :: Vector3, want)) < math.rad(3) then
			a.Turning = false
			a.TurnSince = nil
		end
	else
		a.Dir = cur
	end
end

-- the anchor's frame (-Z = the formation heading, +X = its right)
function FormationController.AnchorCFrame(a: Anchor): CFrame
	local p = (a.Pos or Vector3.zero) :: Vector3
	local dir = (a.Dir or Vector3.new(0, 0, -1)) :: Vector3
	return CFrame.lookAt(p, p + dir)
end

-- slot index -> side (-1 = his left, +1 = his right) and row (0 = the front row)
function FormationController.SideRow(index: number): (number, number)
	local side = if index % 2 == 1 then -1 else 1
	return side, math.floor((index - 1) / 2)
end

-- slot index -> local offset (lat: +right, back: +behind) of the unit; escort e (1..) sits further out in its row
function FormationController.SlotLocal(index: number, cfg: any, escort: number?): (number, number)
	local side, row = FormationController.SideRow(math.max(1, index))
	local lat = side * (n(cfg, "LateralStuds", 6) + (escort or 0) * n(cfg, "ColSpacing", 5.5))
	local back = n(cfg, "FrontBack", -1.5) + row * n(cfg, "RowSpacing", 5.5)
	return lat, back
end

-- the world point of a local offset: AnchorCFrame:PointToWorldSpace (y replaced)
function FormationController.SlotWorld(a: Anchor, lat: number, back: number, y: number): Vector3
	local w = FormationController.AnchorCFrame(a):PointToWorldSpace(Vector3.new(lat, 0, back))
	return Vector3.new(w.X, y, w.Z)
end

-- the MoveTo lead while he moves (smoothed velocity x MoveLeadSeconds, capped): a unit in its slot keeps walking
function FormationController.MoveLead(a: Anchor, cfg: any): Vector3
	if not a.Moving then
		return Vector3.zero
	end
	local lead = a.Vel * n(cfg, "MoveLeadSeconds", 0.4)
	local cap = n(cfg, "MoveLeadMaxStuds", 6)
	if lead.Magnitude > cap then
		lead = lead.Unit * cap
	end
	return lead
end

--[[ PERMANENT assignment. `units` = the living units now. Gone units free their index; new units take their preferred
	index (unit.Slot) when free, else the lowest free one. Returns true when the roster changed. Never uses distance. ]]
function FormationController.Assign(s: Assignment, units: { any }): boolean
	local present: { [any]: boolean } = {}
	for _, u in ipairs(units) do
		present[u] = true
	end
	local changed = false
	for u, idx in pairs(s.ByUnit) do
		if not present[u] then
			s.ByUnit[u] = nil
			if s.Taken[idx] == u then
				s.Taken[idx] = nil
			end
			changed = true
		end
	end
	local fresh: { any } = {}
	for _, u in ipairs(units) do
		if s.ByUnit[u] == nil then
			table.insert(fresh, u)
		end
	end
	table.sort(fresh, function(x, y)
		return (tonumber(x.Slot) or 0) < (tonumber(y.Slot) or 0)
	end)
	for _, u in ipairs(fresh) do
		local pref = tonumber(u.Slot)
		local idx: number
		if pref and pref >= 1 and pref == math.floor(pref) and s.Taken[pref] == nil then
			idx = pref
		else
			idx = 1
			while s.Taken[idx] ~= nil do
				idx += 1
			end
		end
		s.ByUnit[u] = idx
		s.Taken[idx] = u
		changed = true
	end
	return changed
end

return FormationController
