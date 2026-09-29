--!strict
--[[
	v115 (Code Bot Roblox, 2026-09-29, docs/ARMY-FOLLOW-ROOTCAUSE-3.md): FormationController — the army formation's pure
	maths. No instances, no services: Server/Modules/ArmyController steps it every Follow3.UpdateSeconds;
	tools/checks/codebot_v115_army.py runs this same file in the Luau CLI (the acceptance simulation).

	The FORMATION follows the player; soldiers follow slots.
	  * Trail (breadcrumbs): his position, lightly smoothed (TrailSmoothSeconds, takes the edge off a phone-joystick
	    zig-zag), dropped as a crumb every CrumbStuds he travels; kept for TrailKeepStuds. Nothing is added while he
	    stands, so the formation holds still and keeps its heading when he stops or spins on the spot.
	  * Rows: row r sits on the trail at a FIXED ARC LENGTH behind him (FirstRowStuds + r x RowSpacing, measured along
	    his path, not in a straight line), and faces the trail's tangent there (his MOVEMENT direction where he walked,
	    never his look vector). A row turns at most RowTurnDegPerSec, only past RowDeadbandDeg (hysteresis: it stops
	    turning within 1.5 deg), and only while he moves. So on a corner each row reaches the corner and turns there
	    like a marching column; on a circle the block follows the circle; on an about-turn the rows walk up his old
	    path, turn where he turned and follow him back — nothing ever swings round him.
	  * Block: columns across, rows back, nothing beside him. Columns = an even count (2 or 4 by default, ColumnsMax),
	    from the figure count (units + escorts), ColSpacing apart with an AisleStuds lane down the middle, filled centre-out (slot 1 inner left, 2 inner right,
	    3 outer left, 4 outer right; then the next rank). Each unit's escort figures stand in the cells DIRECTLY BEHIND
	    it (same column), so a rank is 1 + (its most escorts) rows deep. Even columns leave an aisle down his own trail.
	  * World slot = RowFrame(row):PointToWorldSpace(Vector3.new(x * RowSide(row), 0, 0)); the local offset (x, row) of a
	    slot index is constant (only a roster change: a unit / escort count added or gone, can move a cell).
	  * About-turn fold (his path doubles back: a row's path direction swings past FoldDeg from its heading): that row
	    reverses in place: heading exactly reversed and RowSide flips (x mirrored), so every cell keeps its world spot
	    and its side of his path; the rows then walk up his old path, turn where he turned (each row in turn, rank order
	    kept) and follow him back. No 180-degree sweep of the row, no side swap in front of him.
	  * Assignment: PERMANENT (FormationController.Assign, unchanged from v114). A unit keeps its slot index for life;
	    a new unit takes its preferred index (its SquadSlot) when free, else the lowest free one; a gone unit frees its
	    index. Survivors are never renumbered, no distance is ever used, no iteration order matters.
]]

local FormationController = {}

export type Assignment = {
	ByUnit: { [any]: number },
	Taken: { [number]: any },
}

export type Trail = {
	Pts: { Vector3 }, -- crumbs, oldest first
	Smooth: Vector3?, -- his smoothed position (crumbs are dropped from this)
	Head: Vector3?, -- his raw position this tick (arc lengths are measured from here)
	Seed: Vector3, -- direction of travel before the oldest crumb (the trail runs on straight back along it)
	Vel: Vector3, -- his smoothed flat velocity
	Moving: boolean,
	RowDir: { [number]: Vector3 }, -- per row: its current (rate-limited) heading
	RowTurn: { [number]: boolean }, -- per row: turning (hysteresis)
	RowFlip: { [number]: number }, -- per row: +1, or -1 after an about-turn fold (its sides keep their world side)
}

export type Cell = { Row: number, X: number, Esc: number }

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDist(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
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

function FormationController.NewAssignment(): Assignment
	return { ByUnit = {}, Taken = {} }
end

function FormationController.NewTrail(): Trail
	return { Pts = {}, Smooth = nil, Head = nil, Seed = Vector3.new(0, 0, -1), Vel = Vector3.zero, Moving = false, RowDir = {}, RowTurn = {}, RowFlip = {} }
end

--[[ One trail step. ownerPos / ownerLook: his root position and LookVector; vel: his measured flat velocity over this
	step; snap: a teleport / respawn / FOLLOW (re)start (a fresh trail running straight back from him along his facing:
	the formation starts behind him). cfg: ArmyConfig.Follow3. ]]
function FormationController.TrailStep(t: Trail, ownerPos: Vector3, ownerLook: Vector3, vel: Vector3, dt: number, snap: boolean, cfg: any)
	dt = math.clamp(dt, 0, 1)
	if t.Smooth == nil or snap then
		t.Smooth = ownerPos
		t.Head = ownerPos
		t.Pts = { ownerPos }
		t.Seed = unitOr(flat(ownerLook), Vector3.new(0, 0, -1))
		t.Vel = Vector3.zero
		t.Moving = false
		t.RowDir = {}
		t.RowTurn = {}
		t.RowFlip = {}
		return
	end
	t.Head = ownerPos
	t.Vel = t.Vel:Lerp(flat(vel), math.clamp(dt / math.max(1e-3, n(cfg, "VelSmoothSeconds", 0.3)), 0, 1))
	local speed = t.Vel.Magnitude
	if t.Moving then
		t.Moving = speed >= n(cfg, "MovingOffSpeed", 1.5)
	else
		t.Moving = speed >= n(cfg, "MovingOnSpeed", 3)
	end
	local k = 1 - math.exp(-dt / math.max(1e-3, n(cfg, "TrailSmoothSeconds", 0.25)))
	t.Smooth = (t.Smooth :: Vector3):Lerp(ownerPos, k)
	local sm = t.Smooth :: Vector3
	local last = t.Pts[#t.Pts]
	if last == nil or flatDist(sm, last) >= n(cfg, "CrumbStuds", 1) then
		table.insert(t.Pts, sm)
	end
	-- keep TrailKeepStuds of path (the oldest crumb's direction becomes the straight run-on)
	local keep = n(cfg, "TrailKeepStuds", 90)
	local arc = flatDist(ownerPos, t.Pts[#t.Pts])
	local cut = 0
	for i = #t.Pts, 2, -1 do
		arc += flatDist(t.Pts[i], t.Pts[i - 1])
		if arc > keep then
			cut = i - 2
			break
		end
	end
	if cut > 0 then
		local a, b = t.Pts[cut], t.Pts[cut + 1]
		t.Seed = unitOr(flat(b - a), t.Seed)
		for _ = 1, cut do
			table.remove(t.Pts, 1)
		end
	end
end

-- the point on his path `s` studs (arc length) behind him; past the oldest crumb it runs on straight back
function FormationController.TrailPoint(t: Trail, s: number): Vector3
	local prev = (t.Head or t.Smooth or Vector3.zero) :: Vector3
	local rem = math.max(0, s)
	for i = #t.Pts, 1, -1 do
		local p = t.Pts[i]
		local seg = flatDist(prev, p)
		if seg >= rem and seg > 1e-6 then
			return prev:Lerp(p, rem / seg)
		end
		rem -= seg
		prev = p
	end
	return prev - t.Seed * rem
end

-- the direction of travel along his path at arc `s` (from TangentStuds further back to TangentStuds nearer him)
function FormationController.Tangent(t: Trail, s: number, cfg: any): Vector3
	local w = n(cfg, "TangentStuds", 3)
	local a = FormationController.TrailPoint(t, math.max(0, s - w))
	local b = FormationController.TrailPoint(t, s + w)
	return unitOr(flat(a - b), t.Seed)
end

-- +1, or -1 while row r is reversed after an about-turn fold (its slots' x is mirrored with it)
function FormationController.RowSide(t: Trail, row: number): number
	return t.RowFlip[row] or 1
end

-- the arc length of row r (0 = the front row)
function FormationController.RowArc(row: number, cfg: any): number
	return n(cfg, "FirstRowStuds", 7) + row * n(cfg, "RowSpacing", 4.5)
end

--[[ Row r's frame this tick (-Z = its heading, +X = its right). Call once per row per tick (it advances the row's
	rate-limited heading by dt): ArmyController steps rows 0..last every tick. ]]
function FormationController.RowFrame(t: Trail, row: number, dt: number, cfg: any): CFrame
	local s = FormationController.RowArc(row, cfg)
	local p = FormationController.TrailPoint(t, s)
	local want = FormationController.Tangent(t, s, cfg)
	local cur = t.RowDir[row]
	if cur == nil then
		cur = want
	elseif t.Moving then
		local ang = math.abs(FormationController.Angle(cur, want))
		if ang > math.rad(n(cfg, "FoldDeg", 120)) then
			-- an about-turn fold: the row reverses where it stands (about face): heading exactly reversed and its
			-- sides mirrored, so every cell keeps its world spot (no 180-degree sweep, no snake, no side swap)
			cur = -cur
			t.RowFlip[row] = -(t.RowFlip[row] or 1)
			ang = math.abs(FormationController.Angle(cur, want))
		end
		if not t.RowTurn[row] and ang > math.rad(n(cfg, "RowDeadbandDeg", 8)) then
			t.RowTurn[row] = true
		end
		if t.RowTurn[row] then
			cur = FormationController.Turn(cur, want, math.rad(n(cfg, "RowTurnDegPerSec", 110)) * math.clamp(dt, 0, 1))
			if math.abs(FormationController.Angle(cur, want)) < math.rad(1.5) then
				t.RowTurn[row] = false
			end
		end
	end
	t.RowDir[row] = cur
	return CFrame.lookAt(p, p + cur)
end

-- an even column count: ceil(sqrt(figures)) rounded up to even, 2..ColumnsMax (an aisle down his trail)
function FormationController.Columns(figures: number, cfg: any): number
	local c = math.ceil(math.sqrt(math.max(1, figures)))
	c += c % 2
	local cap = math.max(2, math.floor(n(cfg, "ColumnsMax", 4)))
	cap -= cap % 2
	return math.clamp(c, 2, cap)
end

-- slot j (0-based) inside a rank: centre-out, left first; the two inner columns AisleStuds apart (his lane)
function FormationController.ColumnX(j: number, cfg: any): number
	local k = j // 2
	local side = if j % 2 == 0 then -1 else 1
	return side * (n(cfg, "AisleStuds", 7) / 2 + k * n(cfg, "ColSpacing", 5))
end

--[[ Cells of the block: per unit (by its permanent index) its row and lateral x; its escorts stand in rows Row + 1 ..
	Row + Esc of the same column. escOf(unit) -> its escort figures (WE_Escorts). Only max / sum over the table: no
	iteration order matters. Returns cells, the last row used, the column count. ]]
function FormationController.Layout(s: Assignment, escOf: (any) -> number, cfg: any): ({ [any]: Cell }, number, number)
	local figures = 0
	local esc: { [any]: number } = {}
	for u, _ in pairs(s.ByUnit) do
		local e = math.max(0, math.floor(tonumber(escOf(u)) or 0))
		esc[u] = e
		figures += 1 + e
	end
	local cols = FormationController.Columns(figures, cfg)
	local depth: { [number]: number } = {}
	local maxRank = 0
	for u, idx in pairs(s.ByUnit) do
		local rank = (idx - 1) // cols
		depth[rank] = math.max(depth[rank] or 0, 1 + esc[u])
		maxRank = math.max(maxRank, rank)
	end
	local start: { [number]: number } = { [0] = 0 }
	for r = 1, maxRank do
		start[r] = start[r - 1] + (depth[r - 1] or 0)
	end
	local cells: { [any]: Cell } = {}
	local last = 0
	for u, idx in pairs(s.ByUnit) do
		local rank = (idx - 1) // cols
		local row = start[rank]
		cells[u] = { Row = row, X = FormationController.ColumnX((idx - 1) % cols, cfg), Esc = esc[u] }
		last = math.max(last, row + esc[u])
	end
	return cells, last, cols
end

-- a new unit's spawn offset (his frame: x = right, z = behind) before it has a trail cell: 4 columns, a full front rank
function FormationController.SpawnOffset(slot: number, cfg: any): Vector3
	local cols = math.max(2, math.floor(n(cfg, "ColumnsMax", 4)))
	local idx = math.max(1, math.floor(slot))
	local rank = (idx - 1) // cols
	local row = if rank == 0 then 0 else 4 + (rank - 1)
	return Vector3.new(FormationController.ColumnX((idx - 1) % cols, cfg), 0, FormationController.RowArc(row, cfg))
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

-- JOB 23: the steered block (Follow3.Steer). C = its centre (the pivot), V = its velocity, H = its heading, W = its
-- turn rate (rad/s, + = toward +atan2(X, Z)), Hd = the heading it steers to (his MOVEMENT direction, kept while he stands)
export type Form = {
	C: Vector3,
	V: Vector3,
	H: Vector3,
	W: number,
	Hd: Vector3,
	Turning: boolean,
	Radius: number, -- farthest slot from C
	Omega: number, -- the turn-rate cap now (SlotLateralSpeed / Radius)
	HalfDepth: number,
	Err: number, -- heading error (rad) this tick
	Target: Vector3?, -- its steering point last tick (on his trail)
	Waiting: boolean?, -- he walks back through it (an about-turn): it holds still and waits
	Deploy: number?, -- JOB 24 ATTACK: 0 = the follow block, 1 = the attack line (blended in between)
	AttackOn: boolean?, -- JOB 24: it had an ATTACK target last tick
}

export type Army = {
	Trail: Trail,
	Assign: Assignment,
	Prev: { [any]: Vector3 }, -- per unit: its slot last tick (its slot's velocity)
	SVel: { [any]: Vector3 },
	LayoutKey: string?,
	Form: Form?,
	Attack: { Pos: Vector3 }?, -- JOB 24: the squad's ATTACK target this tick (nil = follow him)
}

export type Plan = { Goal: Vector3, Heading: Vector3, Lead: Vector3, Pace: number, Row: number, X: number, Esc: number, Idx: number, SlotSpeed: number }

function FormationController.NewArmy(): Army
	return { Trail = FormationController.NewTrail(), Assign = FormationController.NewAssignment(), Prev = {}, SVel = {}, LayoutKey = nil, Form = nil, Attack = nil }
end

--[[ JOB 24 (claude-bud, docs/ARMY-ATTACK-ROOTCAUSE.md): a unit's cell in the ATTACK line, by its PERMANENT slot index:
	AttackLinePerRank abreast, centre-out (left, right, left ...) like the block's columns (so nobody changes sides),
	AttackLineSpacing apart; the next ranks behind, room for its escorts. Local to the block centre: x = right, z = back. ]]
function FormationController.LineOffset(idx: number, escMax: number, ranks: number, cfg: any): (number, number)
	local per = math.max(1, math.floor(n(cfg, "AttackLinePerRank", 6)))
	local sp = n(cfg, "AttackLineSpacing", 6)
	local i = math.max(1, math.floor(idx)) - 1
	local j = i % per
	local rank = i // per
	local side = if j % 2 == 0 then -1 else 1
	local depth = (1 + math.max(0, escMax)) * n(cfg, "RowSpacing", 4.5)
	return side * (sp / 2 + (j // 2) * sp), rank * depth - (math.max(1, ranks) - 1) * depth / 2
end

--[[ JOB 24: the squad's ATTACK target, sticky. `cur` = the current target key (or nil), `cands` = { { Key, Pos } } the
	hostiles it may hurt within reach. Keeps `cur` while it is still a candidate within AttackAggroStuds +
	AttackKeepExtraStuds of the army's centre `from`, unless another one is AttackRetargetStuds nearer; else the nearest.
	Never uses iteration order for a tie (the lower distance wins, then the first in `cands` order is irrelevant: exact
	ties keep `cur`). Returns the chosen key (or nil). ]]
function FormationController.PickTarget(cur: any, cands: { { Key: any, Pos: Vector3 } }, from: Vector3, cfg: any): any
	local best, bestD = nil, math.huge
	local curD = math.huge
	for _, c in ipairs(cands) do
		local d = flatDist(c.Pos, from)
		if c.Key == cur then
			curD = d
		end
		if d < bestD then
			best, bestD = c.Key, d
		end
	end
	if cur ~= nil and curD <= n(cfg, "AttackAggroStuds", 120) + n(cfg, "AttackKeepExtraStuds", 20) and bestD > curD - n(cfg, "AttackRetargetStuds", 15) then
		return cur
	end
	if best ~= nil and bestD <= n(cfg, "AttackAggroStuds", 120) then
		return best
	end
	return nil
end

local function rotY(v: Vector3, rad: number): Vector3
	local r = math.atan2(v.X, v.Z) + rad
	return Vector3.new(math.sin(r), 0, math.cos(r))
end

--[[ JOB 23 (claude-bud, docs/ARMY-FOLLOW-ROOTCAUSE-4.md): the block as ONE steered body. v115 put every row ON his
	breadcrumb trail, so a slot turned each of his corners at his full speed (its velocity swung 90 deg in one tick) and,
	on an about-turn, ran up his old path into the turn point and straight back (a hairpin: its velocity reversed in one
	tick, a whole rank fell 8-11 studs behind at once in the sim). Now the trail is only the GUIDE the body steers along:
	  * position: C (the block's centre, its pivot) steers to the point on his trail (his walked path) that puts the
	    block's nearest slot FirstRowStuds behind him, that point's velocity fed forward, FormGain per stud of gap, its
	    own velocity changing at most FormAccel per second and capped at FormMaxSpeed: continuous, so on a corner it keeps
	    going briefly and then comes round along his path (never across the corner into him); while he walks back into
	    his block it stops going his way and waits (sideways correction only) until he is through;
	  * heading: H turns toward Hd = his MOVEMENT direction where the block is on his path (the trail tangent; updated
	    only while he moves, MovingOn / MovingOff hysteresis; never his look vector, so a spin on the spot moves nothing)
	    past RowDeadbandDeg (a slow drift inside it), with angular inertia (TurnAccelSeconds) and a rate cap of
	    SlotLateralSpeed / the block's radius: no slot is swung sideways faster than SlotLateralSpeed, a bigger army
	    turns slower, the pivot is the block's own centre (not him);
	  * slots: C + H-rotated constant offsets (row frames below): every slot path is smooth and continuous.
	Returns the row frames (row r's centre, facing H). ]]
function FormationController.SteerFrames(army: Army, units: { any }, ownerPos: Vector3, cells: { [any]: Cell }, last: number, dt: number,
	snap: boolean, cfg: any): { [number]: CFrame }
	local t = army.Trail
	dt = math.clamp(dt, 0, 1)
	local rs = n(cfg, "RowSpacing", 4.5)
	local half = last * rs / 2
	local first = n(cfg, "FirstRowStuds", 7)
	-- the farthest slot from the pivot (escort cells included); max only, so no iteration order matters
	local rad = 4
	for _, c in pairs(cells) do
		for k = 0, c.Esc do
			local z = (c.Row + k) * rs - half
			rad = math.max(rad, math.sqrt(c.X * c.X + z * z))
		end
	end
	local me = flat(ownerPos)
	local f = army.Form
	if f == nil or snap then
		-- a fresh block: facing from where the army stands toward him (never his look vector), else the old heading;
		-- the fresh trail runs straight back from him along it
		local h = if f then f.H else Vector3.new(0, 0, -1)
		local sum, cnt = Vector3.zero, 0
		for _, u in ipairs(units) do
			local r = u.Root
			if r then
				sum += flat(r.Position)
				cnt += 1
			end
		end
		if cnt > 0 then
			local d = me - sum / cnt
			if d.Magnitude > 1 then
				h = d.Unit
			end
		end
		t.Seed = h
		f = { C = me - h * (first + half), V = Vector3.zero, H = h, W = 0, Hd = h, Turning = false, Radius = rad, Omega = 0, HalfDepth = half, Err = 0 }
		army.Form = f
	end
	local F = f :: Form
	local atk = army.Attack
	if atk == nil and F.AttackOn then
		-- JOB 24: the attack is over (target down / gone, order changed): it re-forms on ITS side of him, heading kept
		-- (his old path may lie on the far side of him: the block would sweep past him to reach it)
		local u = unitOr(F.C - me, -F.H)
		t.Pts = { ownerPos }
		t.Smooth = ownerPos
		t.Head = ownerPos
		t.Seed = -u
		F.Hd = F.H
	end
	F.AttackOn = atk ~= nil
	-- how far the block reaches out from C along a direction, as it is turned NOW (on a corner its width, not its depth,
	-- is what must stay behind him)
	local right = Vector3.new(-F.H.Z, 0, F.H.X)
	local function reach(dir: Vector3): number
		local r = 0
		for _, c in pairs(cells) do
			for k = 0, c.Esc do
				r = math.max(r, (right * c.X - F.H * ((c.Row + k) * rs - half)):Dot(dir))
			end
		end
		return r
	end
	local s = first + reach(F.Hd)
	-- desired heading: his movement direction there (the trail tangent), only while he moves
	if t.Moving then
		F.Hd = if cfg.SteerHeadingPath == true then FormationController.Tangent(t, s, cfg) else unitOr(flat(t.Vel), F.Hd)
		s = first + reach(F.Hd)
	end
	local target = flat(FormationController.TrailPoint(t, s))
	local mv = flat(t.Vel)
	if atk ~= nil then
		-- JOB 24 ATTACK: the same body steers to its own side of the target, AttackStandoff from it, facing it (the
		-- heading rate cap, accel / brake and the bubble round him all still apply: it advances as one block)
		local tp = flat(atk.Pos)
		F.Hd = unitOr(tp - F.C, F.H)
		target = tp - F.Hd * n(cfg, "AttackStandoff", 36)
	elseif t.Moving and mv.Magnitude > 1e-3 then
		-- clearance: no slot of the block (as turned now) may sit less than FirstRowStuds behind him along the way he
		-- walks NOW (a corner: the wide front row would otherwise cross his new path just behind him)
		local vd = mv.Unit
		local over = (target - me):Dot(vd) + reach(vd) + first
		if over > 0 then
			target -= vd * over
		end
	end
	-- and its centre never nearer him than its radius + BubbleStuds (no slot of it near him, whichever way it faces)
	local bubble = rad + n(cfg, "BubbleStuds", 3)
	local off = target - me
	if off.Magnitude < bubble then
		target = me + unitOr(off, -F.Hd) * bubble
	end
	local ff = Vector3.zero
	if F.Target ~= nil and (t.Moving or atk ~= nil) and dt > 1e-3 then
		ff = (target - (F.Target :: Vector3)) / dt
		if atk ~= nil and ff.Magnitude > n(cfg, "AttackFeedMax", 12) then
			ff = ff.Unit * n(cfg, "AttackFeedMax", 12) -- (a new target is a jump: steered to, not fed forward)
		end
	end
	F.Target = target
	-- (C moves by V x dt after this, so it aims at the target less this tick's own travel: it lands ON it, not a tick ahead)
	local gap = target - ff * dt - F.C
	local want = ff + gap * n(cfg, "FormGain", 2.5)
	local waiting = false
	if atk == nil and t.Moving and mv.Magnitude > 1e-3 then
		-- he walks back into / through his block (an about-turn, a hairpin of his path): it stops going his way and
		-- waits (sideways correction only) until he is past its centre; it never charges through him (on a corner, with
		-- the block beside him, it may back off out of his way)
		local vd = mv.Unit
		if (F.C - me):Dot(vd) > n(cfg, "WaitAheadStuds", 0) then
			waiting = true
			local along = want:Dot(vd)
			if along < 0 then
				want -= vd * along
			end
		end
	end
	local vmax = if atk ~= nil then n(cfg, "AttackMaxSpeed", 16) -- (ATTACK: the block advances at a steady jog)
		else math.max(n(cfg, "FormMaxSpeed", 22), t.Vel.Magnitude * n(cfg, "FormSpeedMult", 1.25))
	if (F.Deploy or 0) > 0 and (F.Deploy or 0) < 1 then
		vmax = math.min(vmax, n(cfg, "AttackMaxSpeed", 16)) -- (sliding into / out of the line: the block goes no faster)
	end
	-- while it turns its outer slots already move |W| x radius sideways: it travels that much slower, so no slot ever
	-- moves faster than FormMaxSpeed (what a soldier can hold, with catch-up headroom to spare)
	vmax = math.max(0, vmax - math.abs(F.W) * rad * n(cfg, "TurnSlowFactor", 1))
	if want.Magnitude > vmax then
		want = want.Unit * vmax
	end
	local dv = want - F.V
	-- speeding up / turning its course: FormAccel (it keeps going briefly on a reversal); slowing down along its course:
	-- FormBrake (it stops with him, and never coasts into his new path on a corner)
	local acc = math.max(n(cfg, "FormAccel", 24), vmax) * dt
	local vm = F.V.Magnitude
	if vm > 1e-3 then
		local vu = F.V / vm
		local a = dv:Dot(vu)
		local side = dv - vu * a
		a = if a < 0 then math.max(a, -math.max(n(cfg, "FormBrake", 60), vmax) * dt) else math.min(a, acc)
		if side.Magnitude > acc then
			side = side.Unit * acc
		end
		dv = vu * a + side
	elseif dv.Magnitude > acc then
		dv = dv.Unit * acc
	end
	F.V += dv
	if (atk ~= nil or not t.Moving) and gap.Magnitude < 0.05 and F.V.Magnitude < 0.5 then
		F.V = Vector3.zero
	end
	F.C += F.V * dt
	-- JOB 24: deploy into the attack line once the block has reached its spot (AttackDeployStuds; it folds back past
	-- twice that, or when the attack ends), blended over AttackDeploySeconds: every slot slides, nothing jumps
	local dep = F.Deploy or 0
	local near = atk ~= nil and gap.Magnitude < n(cfg, "AttackDeployStuds", 8) * (if dep > 0.5 then 2 else 1)
	-- the slide takes long enough that no slot slides faster than AttackSlideSpeed (the longest slide sets it; the
	-- smoothstep peaks at 1.5 x its mean speed)
	local slide = 0
	if near or dep > 0 then
		local per = math.max(1, math.floor(n(cfg, "AttackLinePerRank", 6)))
		local escMax, maxIdx = 0, 1
		for u, c in pairs(cells) do
			escMax = math.max(escMax, c.Esc)
			maxIdx = math.max(maxIdx, army.Assign.ByUnit[u] or 1)
		end
		for u, c in pairs(cells) do
			local lx, lz = FormationController.LineOffset(army.Assign.ByUnit[u] or 1, escMax, (maxIdx - 1) // per + 1, cfg)
			local dx, dz = lx - c.X, lz - (c.Row * rs - half)
			slide = math.max(slide, math.sqrt(dx * dx + dz * dz))
		end
	end
	local secs = math.max(n(cfg, "AttackDeploySeconds", 1.2), 1.5 * slide / math.max(1, n(cfg, "AttackSlideSpeed", 8)))
	F.Deploy = math.clamp(dep + (if near then 1 else -1) * dt / secs, 0, 1)
	-- heading: toward Hd with angular inertia, the rate capped so no slot swings sideways faster than SlotLateralSpeed
	local omax = n(cfg, "SlotLateralSpeed", 10) / rad
	local e = FormationController.Angle(F.H, F.Hd)
	if not F.Turning and math.abs(e) > math.rad(n(cfg, "RowDeadbandDeg", 8)) then
		F.Turning = true
	end
	if F.Turning then
		if math.abs(e) > math.rad(170) and math.abs(F.W) > 1e-3 then
			e = (if F.W > 0 then 1 else -1) * math.abs(e) -- an about-turn: keep coming round the way it already turns
		end
		-- (while he walks through it, it holds its heading: its aisle stays on his path; it comes round once he is past)
		local wt = if waiting then 0 else math.clamp(e * n(cfg, "TurnGain", 2.5), -omax, omax)
		local aw = omax / math.max(0.05, n(cfg, "TurnAccelSeconds", 0.4)) * dt
		F.W = math.clamp(F.W + math.clamp(wt - F.W, -aw, aw), -omax, omax)
		local step = F.W * dt
		if not waiting and (math.abs(e) < math.rad(1.5) or (e >= 0 and step >= e) or (e <= 0 and step <= e)) then
			F.H = rotY(F.H, e) -- lands on it (within 1.5 deg, or this step would pass it)
			F.W = 0
			F.Turning = false
		else
			F.H = rotY(F.H, step)
		end
	else
		F.W = 0
		if t.Moving or atk ~= nil then
			-- inside the deadband: a slow drift onto his heading (no jitter from a wobbling thumbstick, no standing tilt)
			F.H = rotY(F.H, e * (1 - math.exp(-dt * n(cfg, "SettleTurnPerSec", 0.8))))
		end
	end
	F.Radius, F.Omega, F.HalfDepth, F.Err, F.Waiting = rad, omax, half, e, waiting
	local frames: { [number]: CFrame } = {}
	for r = 0, last do
		local p = F.C - F.H * (r * rs - half)
		p = Vector3.new(p.X, ownerPos.Y, p.Z)
		frames[r] = CFrame.lookAt(p, p + F.H)
		t.RowDir[r] = F.H
	end
	return frames
end

--[[ One FOLLOW planning tick for an army (the whole chain ArmyController runs and the acceptance sim runs):
	trail step -> block layout -> every row's frame -> per unit: its slot (Goal), its row heading, its MoveTo lead (its
	OWN slot's smoothed velocity x MoveLeadSeconds, capped) and its pace (its slot's speed). `units` in any order;
	army.Assign must already hold them (FormationController.Assign). Returns plans, row frames, columns, the last row. ]]
-- how far the left (x < 0) / right (x > 0) half of row `frame` (its slot x values `xs`, sides already applied) moves
-- out so his walking lane (his travel ahead of him, LaneHalfStuds each side) runs clear between them: he walks back
-- into his own block (an about-turn) and the row parts like a door, each half keeping its column order; ramped in as
-- he comes (never a jump), gone once he is past the row
function FormationController.Part(frame: CFrame, xs: { number }, ownerPos: Vector3, ownerVel: Vector3, cfg: any): (number, number)
	local sp = flat(ownerVel).Magnitude
	if sp < n(cfg, "MovingOnSpeed", 3) or #xs == 0 then
		return 0, 0
	end
	local ld = flat(ownerVel) / sp
	local near = math.min(sp * n(cfg, "OwnerAheadSeconds", 1), n(cfg, "OwnerAheadMaxStuds", 16))
	local far = near + n(cfg, "PartRampStuds", 12)
	local along = flat(frame.Position - ownerPos):Dot(ld)
	if along <= -2 or along >= far then
		return 0, 0
	end
	local right = flat(frame:PointToWorldSpace(Vector3.new(1, 0, 0)) - frame.Position)
	if math.abs(right:Dot(ld)) > 0.75 then
		return 0, 0 -- he walks along this row, not through it
	end
	local hx = frame:PointToObjectSpace(Vector3.new(ownerPos.X, frame.Position.Y, ownerPos.Z)).X
	local half = n(cfg, "LaneHalfStuds", 3.5)
	local lo, hi = -math.huge, math.huge -- innermost left x, innermost right x
	for _, x in ipairs(xs) do
		if x < 0 then
			lo = math.max(lo, x)
		else
			hi = math.min(hi, x)
		end
	end
	local f = math.clamp((far - along) / math.max(1, far - near), 0, 1)
	local cap = n(cfg, "PartMaxStuds", 5)
	local dl = if lo > -math.huge then math.min(cap, math.max(0, lo - (hx - half))) else 0
	local dr = if hi < math.huge then math.min(cap, math.max(0, (hx + half) - hi)) else 0
	return dl * f, dr * f
end

-- JOB 24: the block itself is on the move (he walks, or an ATTACK block advances / deploys): soldiers walk (no
-- InPosition stop) while this is true
function FormationController.BlockMoving(army: Army, cfg: any): boolean
	if army.Trail.Moving then
		return true
	end
	local F = army.Form
	if F == nil or army.Attack == nil and (F.Deploy or 0) <= 0 then
		return false
	end
	local d = F.Deploy or 0
	return F.V.Magnitude > n(cfg, "MovingOffSpeed", 1.5) or (d > 0 and d < 1)
end

function FormationController.Plan(army: Army, units: { any }, ownerPos: Vector3, ownerLook: Vector3, vel: Vector3, dt: number, snap: boolean,
	escOf: (any) -> number, cfg: any, ownerVelNow: Vector3?): ({ [any]: Plan }, { [number]: CFrame }, number, number)
	local t = army.Trail
	FormationController.TrailStep(t, ownerPos, ownerLook, vel, dt, snap, cfg)
	local cells, last, cols = FormationController.Layout(army.Assign, escOf, cfg)
	local key = tostring(cols) .. ":" .. tostring(last)
	local relayout = army.LayoutKey ~= nil and army.LayoutKey ~= key
	army.LayoutKey = key
	local frames: { [number]: CFrame } = {}
	if typeof(cfg) == "table" and cfg.Steer == true then
		frames = FormationController.SteerFrames(army, units, ownerPos, cells, last, dt, snap, cfg) -- JOB 23: one steered block
	else
		for r = 0, last do
			frames[r] = FormationController.RowFrame(t, r, dt, cfg)
		end
	end
	-- the rows he walks back into (an about-turn) part to let him through (ownerVelNow: his root's velocity now)
	local partL: { [number]: number } = {}
	local partR: { [number]: number } = {}
	if ownerVelNow and t.Moving and army.Attack == nil then
		local xsByRow: { [number]: { number } } = {}
		for _, u in ipairs(units) do
			local c = cells[u]
			if c then
				xsByRow[c.Row] = xsByRow[c.Row] or {}
				table.insert(xsByRow[c.Row], c.X * FormationController.RowSide(t, c.Row))
			end
		end
		for r, xs in pairs(xsByRow) do
			partL[r], partR[r] = FormationController.Part(frames[r], xs, ownerPos, ownerVelNow :: Vector3, cfg)
		end
	end
	local plans: { [any]: Plan } = {}
	local steer = typeof(cfg) == "table" and cfg.Steer == true
	-- (JOB 23: a steered slot's walk point is further ahead, so a soldier never reaches it and stops between MoveTos)
	local leadS = if steer then n(cfg, "SteerLeadSeconds", 0.5) else n(cfg, "MoveLeadSeconds", 0.4)
	local leadCap = if steer then n(cfg, "SteerLeadMaxStuds", 6) else n(cfg, "MoveLeadMaxStuds", 5)
	local blend = math.clamp(n(cfg, "SlotVelBlend", 0.5), 0, 1)
	-- JOB 24: the attack line (blended by the block's Deploy): per unit its line cell by its permanent index
	local F = army.Form
	local dk = if steer and F ~= nil then (F.Deploy or 0) else 0
	dk = dk * dk * (3 - 2 * dk) -- (smoothstep: the slide starts and ends gently)
	local escMax, maxIdx = 0, 1
	if dk > 0 then
		for u, c in pairs(cells) do -- (max only: no iteration order matters)
			escMax = math.max(escMax, c.Esc)
			maxIdx = math.max(maxIdx, army.Assign.ByUnit[u] or 1)
		end
	end
	local ranks = (maxIdx - 1) // math.max(1, math.floor(n(cfg, "AttackLinePerRank", 6))) + 1
	for _, u in ipairs(units) do
		local c = cells[u]
		if c then
			local x = c.X * FormationController.RowSide(t, c.Row)
			x = if x < 0 then x - (partL[c.Row] or 0) else x + (partR[c.Row] or 0)
			local goal = frames[c.Row]:PointToWorldSpace(Vector3.new(x, 0, 0))
			if dk > 0 and F ~= nil then
				local lx, lz = FormationController.LineOffset(army.Assign.ByUnit[u] or 1, escMax, ranks, cfg)
				local bz = c.Row * n(cfg, "RowSpacing", 4.5) - (F.HalfDepth or 0)
				local ox, oz = x + (lx - x) * dk, bz + (lz - bz) * dk
				local p = F.C + Vector3.new(-F.H.Z, 0, F.H.X) * ox - F.H * oz
				goal = Vector3.new(p.X, goal.Y, p.Z)
			end
			local prev = army.Prev[u]
			local sv = Vector3.zero
			if prev ~= nil and not snap and not relayout and dt > 1e-3 then
				sv = flat(goal - prev) / dt
			end
			-- (JOB 23: a steered block's slots are already smooth, so its lead / pace use the slot's velocity NOW, no lag)
			local sm = if snap or relayout or steer then sv else (army.SVel[u] or sv):Lerp(sv, blend)
			army.Prev[u] = goal
			army.SVel[u] = sm
			local lead = Vector3.zero
			local pace = 0
			if t.Moving or steer then -- (a steered block may still be settling after he stops: its own velocity)
				lead = sm * leadS
				if lead.Magnitude > leadCap then
					lead = lead.Unit * leadCap
				end
				pace = sm.Magnitude
			end
			plans[u] = { Goal = goal, Heading = t.RowDir[c.Row] or t.Seed, Lead = lead, Pace = pace, Row = c.Row,
				X = c.X * FormationController.RowSide(t, c.Row), Esc = c.Esc, Idx = army.Assign.ByUnit[u], SlotSpeed = sv.Magnitude }
		end
	end
	for u, _ in pairs(army.Prev) do
		if cells[u] == nil then
			army.Prev[u] = nil
			army.SVel[u] = nil
		end
	end
	return plans, frames, cols, last
end

return FormationController
