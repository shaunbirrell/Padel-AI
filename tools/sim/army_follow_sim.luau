--[[ v115 (Code Bot Roblox): the army-follow acceptance simulation (tools/checks/codebot_v115_army.py fills in the
	markers and runs this in the Luau CLI). It runs the REAL Shared/Util/FormationController.luau (trail, block layout,
	rows, plan) and the REAL Server/Modules/SoldierController.luau (Drive: states, speed, catch-up, MoveTo reissue,
	owner clearance, stuck, reposition) against mock humanoids that walk to their MoveTo point at their WalkSpeed with
	a turn rate and an acceleration. Not Roblox physics: no collisions (soldier/soldier and soldier/player are off in
	game too), no terrain, no network. ]]
local V = {}
local function vec(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, V) end
V.__add = function(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V.__sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V.__unm = function(a) return vec(-a.X, -a.Y, -a.Z) end
V.__mul = function(a, b) if type(a) == "number" then return vec(b.X * a, b.Y * a, b.Z * a) end return vec(a.X * b, a.Y * b, a.Z * b) end
V.__div = function(a, b) return vec(a.X / b, a.Y / b, a.Z / b) end
V.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
local M = {}
function M.Lerp(a, b, k) return a + (b - a) * k end
function M.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
V.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
	if k == "Unit" then local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z); if m < 1e-12 then return vec(0, 0, 0) end return vec(t.X / m, t.Y / m, t.Z / m) end
	return M[k]
end
Vector3 = { new = vec, zero = vec(0, 0, 0) }
local CF = {}
CF.__index = function(c, k)
	if k == "LookVector" then return c.Look end
	if k == "Position" then return c.P end
	return CF[k]
end
function CF.PointToWorldSpace(c, v)
	local l = c.Look
	local right = vec(-l.Z, 0, l.X)
	return c.P + right * v.X + vec(0, 1, 0) * v.Y - l * v.Z
end
function CF.PointToObjectSpace(c, w)
	local l = c.Look
	local right = vec(-l.Z, 0, l.X)
	local d = w - c.P
	return vec(d:Dot(right), d.Y, -d:Dot(l))
end
CFrame = { lookAt = function(p, t) local d = t - p; d = vec(d.X, 0, d.Z); local m = d.Magnitude; return setmetatable({ P = p, Look = if m > 1e-9 then d / m else vec(0, 0, -1) }, CF) end }
function typeof(v) return type(v) end
warn = function(...) print("WARNLOG", ...) end
task = { spawn = function() end }
Enum = { PathStatus = {}, PathWaypointAction = {} }

local FC = (function()
--@@FC@@
end)()
local CFG = --@@CFG@@
local ArmyConfig = { Follow3 = CFG }
local Workspace = { FallenPartsDestroyHeight = -500 }
local PathfindingService = {}
local SC = (function()
--@@SC@@
end)()

DEBUGNEAR = false
local TRACE = { --@@TRACE@@ }
local fails = 0
local function check(okv, label) print((okv and "PASS " or "FAIL ") .. label); if not okv then fails += 1 end end
local function flat(v) return vec(v.X, 0, v.Z) end
local function fd(a, b) local dx, dz = a.X - b.X, a.Z - b.Z; return math.sqrt(dx * dx + dz * dz) end

-- ── mock soldiers ─────────────────────────────────────────────────────────────────────────────────────────────────
local pivots = 0
local function mkUnit(i, p, esc)
	local u = { Id = "s" .. i, Slot = i, Alive = true, LastFireAt = -1e9, OwnerUserId = 1, Esc = esc, Vel = vec(0, 0, 0) }
	local gyro = { MaxTorque = vec(0, 4e5, 0), CFrame = CFrame.lookAt(vec(0, 0, 0), vec(0, 0, -1)) }
	function gyro:IsA(c) return c == "BodyGyro" end
	u.Root = { Position = p, CFrame = CFrame.lookAt(p, p + vec(0, 0, -1)), Parent = true }
	function u.Root:FindFirstChild(n) return if n == "NPCFaceGyro" then gyro else nil end
	u.Humanoid = { WalkSpeed = 14, AutoRotate = true, Jump = false, Target = nil }
	function u.Humanoid:MoveTo(g) u.Cmds = (u.Cmds or 0) + 1; self.Target = g end
	u.Model = {}
	function u.Model:SetAttribute() end
	function u.Model:PivotTo(cf) pivots += 1; u.Root.Position = cf.P end
	return u
end

-- walker (a Humanoid on flat ground): its velocity moves toward (MoveTo direction x WalkSpeed) with at most ACCEL
-- studs/s^2 (a vector limit: reversing decelerates along the line, as a humanoid does, rather than looping round);
-- it never steps past its MoveTo point and stops there. Its FACING (AutoRotate) turns toward its travel at TURN deg/s.
local TURN, ACCEL = math.rad(720), 80
local function walk(u, dt)
	local g = u.Humanoid.Target
	local want = vec(0, 0, 0)
	if g then
		local off = flat(g - u.Root.Position)
		if off.Magnitude < 0.3 then
			u.Humanoid.Target = nil
		else
			want = off.Unit * math.min(u.Humanoid.WalkSpeed, off.Magnitude / dt)
		end
	end
	local dv = want - u.Vel
	local lim = ACCEL * dt
	if dv.Magnitude > lim then dv = dv.Unit * lim end
	u.Vel = u.Vel + dv
	local np = u.Root.Position + u.Vel * dt
	u.Root.Position = np
	local sp = u.Vel.Magnitude
	local face = u.Root.CFrame.LookVector
	if sp > 0.5 then face = FC.Turn(flat(face).Unit, u.Vel.Unit, TURN * dt) end
	u.Root.CFrame = CFrame.lookAt(np, np + face)
end

-- ── owner paths: segments { T = seconds, V = studs/s, R = turn deg/s (+ = left) } ─────────────────────────────────
local function seg(T, Vs, R) return { T = T, V = Vs, R = R or 0 } end
local SCEN = {}
local function add(name, segs, esc, n) table.insert(SCEN, { Name = name, Segs = segs, Esc = esc, N = n }) end
local E5 = { 3, 3, 0, 0, 0 } -- 5 units (MaxFieldUnits), 6 escorts: 11 figures
local E8 = { 3, 3, 3, 3, 0, 0, 0, 0 } -- the max army: 8 units (5 + 3 Squad Expansion), 12 escorts (MaxPerArmy): 20 figures
local circ = 16 / 20 -- radius 20 at 16 studs/s
add("straight", { seg(30, 16) }, E5)
add("left90", { seg(5, 16), seg(0.3, 16, 300), seg(8, 16), seg(4, 0) }, E5)
add("right90", { seg(5, 16), seg(0.3, 16, -300), seg(8, 16), seg(4, 0) }, E5)
add("circle", { seg(3, 16), seg(2 * math.pi / circ * 2, 16, math.deg(circ)), seg(4, 0) }, E5)
local r8 = 16 / 18
add("figure8", { seg(2, 16), seg(2 * math.pi / r8, 16, math.deg(r8)), seg(2 * math.pi / r8, 16, -math.deg(r8)), seg(2 * math.pi / r8, 16, math.deg(r8)), seg(2 * math.pi / r8, 16, -math.deg(r8)), seg(4, 0) }, E5)
local zz = { seg(3, 16) }
for k = 1, 12 do table.insert(zz, seg(0.15, 16, if k % 2 == 1 then 400 else -400)); table.insert(zz, seg(0.6, 16)) end
table.insert(zz, seg(4, 0))
add("rapidLR", zz, E5)
add("u180", { seg(6, 16), seg(0.15, 16, 1200), seg(10, 16), seg(4, 0) }, E5) -- a humanoid reverses in ~0.15 s
add("stop", { seg(6, 16), seg(8, 0) }, E5)
local ss = {}
for _ = 1, 6 do table.insert(ss, seg(2, 16)); table.insert(ss, seg(1.5, 0)) end
add("startStop", ss, E5)
add("maxArmy", { seg(4, 16), seg(0.3, 16, 300), seg(4, 16), seg(2 * math.pi / circ, 16, math.deg(circ)), seg(0.15, 16, 1200), seg(5, 16), seg(4, 0) }, E8)

-- claude-bud JOB 23 (docs/ARMY-FOLLOW-ROOTCAUSE-4.md): the turn-transition acceptance set A..J, judged WHILE turning
-- (tools/checks/claude_bud_armyj23.py runs it with J23 = true; the v115 list above is unchanged when J23 = false)
local J23 = false --@@J23@@
if J23 then
	SCEN = {}
	add("A_straight", { seg(20, 16), seg(3, 0) }, E5)
	add("B_gentle90", { seg(5, 16), seg(2, 16, 45), seg(6, 16), seg(3, 0) }, E5)
	add("C_sharp90", { seg(5, 16), seg(0.1, 16, 900), seg(8, 16), seg(3, 0) }, E5)
	-- D: he stands, then turns on the spot 90 L, back 90 R, 90 R, then 180 (a stationary rotation must move nothing)
	add("D_standTurns", { seg(4, 16), seg(3, 0), seg(0.5, 0, 180), seg(1, 0), seg(0.5, 0, -180), seg(1, 0), seg(0.5, 0, -180), seg(1, 0), seg(0.5, 0, 360), seg(2, 0) }, E5)
	add("E_spin", { seg(4, 16), seg(3, 0), seg(3, 0, 360), seg(2, 0, -720), seg(2, 0) }, E5)
	add("F_bigCircle", { seg(3, 16), seg(2 * math.pi / (16 / 60), 16, math.deg(16 / 60)), seg(3, 0) }, E5)
	add("G_tightCircle", { seg(3, 16), seg(2 * math.pi / (16 / 10), 16, math.deg(16 / 10)), seg(3, 0) }, E5)
	local zz2 = { seg(3, 16) }
	for k = 1, 12 do table.insert(zz2, seg(0.15, 16, if k % 2 == 1 then 400 else -400)); table.insert(zz2, seg(0.6, 16)) end
	table.insert(zz2, seg(4, 0))
	add("H_zigzag", zz2, E5)
	add("I_walkBack", { seg(6, 16), seg(0.15, 16, 1200), seg(8, 16), seg(3, 0) }, E5)
	add("J_maxArmy", { seg(4, 16), seg(0.3, 16, 300), seg(4, 16), seg(2 * math.pi / circ, 16, math.deg(circ)), seg(0.15, 16, 1200), seg(5, 16), seg(4, 0) }, E8)
end

-- claude-bud JOB 40 part B: a 40-stud/s owner (the x2.5 Speed Boost): a straight run, a 90-degree turn and a hairpin
-- (run_army_sim.py builds it with S40 = true; off = the lists above unchanged)
local S40 = false --@@S40@@
if S40 then
	SCEN = {}
	add("S40_straight", { seg(20, 40), seg(4, 0) }, E5)
	add("S40_right90", { seg(5, 40), seg(0.3, 40, -300), seg(8, 40), seg(4, 0) }, E5)
	add("S40_hairpin", { seg(6, 40), seg(0.15, 40, 1200), seg(8, 40), seg(4, 0) }, E5)
end

-- segment intersection (strict) for path crossings
local function cross(a1, a2, b1, b2)
	local function o(p, q, r) return (q.X - p.X) * (r.Z - p.Z) - (q.Z - p.Z) * (r.X - p.X) end
	local d1, d2 = o(b1, b2, a1), o(b1, b2, a2)
	local d3, d4 = o(a1, a2, b1), o(a1, a2, b2)
	return ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0))
end

local results = {}
for _, sc in ipairs(SCEN) do
	pivots = 0
	local N = #sc.Esc
	local owner = vec(0, 3, 0)
	local hdg = 0 -- radians; dir = (-sin, 0, -cos): 0 = north (-Z), + = left (counter-clockwise from above)
	local function dirOf(h) return vec(-math.sin(h), 0, -math.cos(h)) end
	local army = FC.NewArmy()
	local units = {}
	for i = 1, N do
		local off = FC.SpawnOffset(i, CFG)
		units[i] = mkUnit(i, owner + vec(off.X, 0, off.Z), sc.Esc[i])
	end
	FC.Assign(army.Assign, units)
	local first = {}
	for _, u in ipairs(units) do first[u] = army.Assign.ByUnit[u] end
	local escOf = function(u) return u.Esc end
	local dt, tick = 1 / 30, CFG.UpdateSeconds
	local t, nextTick, segI, segT = 0, 0, 1, 0
	local total = 0
	for _, s in ipairs(sc.Segs) do total += math.max(1, math.floor(s.T / (1 / 30) + 0.5)) / 30 end
	local lastOwner, lastTickAt = owner, nil
	local m = { slotChanges = 0, teleports = 0, rmsSum = 0, rmsN = 0, rmsMax = 0, widthRatio = 0, rankViol = 0, rankYield = 0, crossings = 0,
		minOwner = math.huge, minOwnerSlot = math.huge, slotAhead = 0, orbit = 0, soldierAhead = 0, maxSlotSpeed = 0, moves = 0, repos = 0,
		maxTurnDeg = 0 }
	local prevGoal = {}
	local prevPos = {}
	local plans, frames = nil, nil
	local cap = 0.8 * CFG.MaxSpeed -- a slot never outruns 80% of a soldier's top speed (headroom to catch up)
	local reverseAt = nil
	local prevRowDir = {}
	local trace = TRACE[sc.Name] == true
	local moving = false
	ownerVelNow = vec(0, 0, 0)
	while t < total + 1e-9 do
		-- owner kinematics
		local s = sc.Segs[segI]
		if s then
			-- exact: a segment lasts round(T / dt) steps and turns exactly R x T degrees in total
			local steps = math.max(1, math.floor(s.T / dt + 0.5))
			hdg += math.rad(s.R * s.T) / steps
			local v = dirOf(hdg) * s.V
			ownerVelNow = v
			owner = owner + v * dt
			moving = s.V > 0
			if s.R >= 1000 and reverseAt == nil then reverseAt = t end
			segT += 1
			if segT >= steps then segI += 1; segT = 0 end
		end
		-- controller tick (ArmyController: plan -> SoldierController.Drive)
		if t >= nextTick - 1e-9 then
			local tdt = if lastTickAt then t - lastTickAt else tick
			local vel = if lastTickAt then flat(owner - lastOwner) / tdt else vec(0, 0, 0)
			local snap = lastTickAt == nil
			lastOwner, lastTickAt = owner, t
			FC.Assign(army.Assign, units)
			for _, u in ipairs(units) do if army.Assign.ByUnit[u] ~= first[u] then m.slotChanges += 1 end end
			local look = dirOf(hdg)
			plans, frames = FC.Plan(army, units, owner, look, vel, tdt, snap, escOf, CFG, ownerVelNow)
			for r, cfm in pairs(frames) do
				-- the row's effective lateral axis (its right x its side: an about-turn fold mirrors both, a no-op in the world)
				local look = cfm.LookVector * FC.RowSide(army.Trail, r)
				local pd = prevRowDir[r]
				if pd and not snap then m.maxTurnDeg = math.max(m.maxTurnDeg, math.deg(math.abs(FC.Angle(pd, look))) / tdt) end
				prevRowDir[r] = look
			end
			for _, u in ipairs(units) do
				local p = plans[u]
				SC.Drive(u, { Goal = p.Goal, Heading = p.Heading, Lead = p.Lead, OwnerPos = owner, OwnerMoving = army.Trail.Moving, Pace = p.Pace,
					BaseSpeed = 14, Dt = tdt, Now = t, AllowRecover = true, OwnerClear = CFG.OwnerClearStuds, OwnerVel = ownerVelNow, -- his root's AssemblyLinearVelocity in game
					Spot = function() return CFrame.lookAt(p.Goal, p.Goal + p.Heading) end, OutOfView = function() return true end })
				if u._scYielding then u._simYieldUntil = t + 1 end -- (it stepped out of his lane: its way back counts too)
			end
			-- claude-bud JOB 23: slot error / CatchingUp / slot speed per tick (while he moves = while turning in B..J), and on
			-- the spot: how far any slot moves while he turns in place (D, E)
			if J23 and t > 1.5 then
				local mx, sum, nC, mxV = 0, 0, 0, 0
				for _, u in ipairs(units) do
					local p = plans[u]
					local d = fd(u.Root.Position, p.Goal)
					mx = math.max(mx, d); sum += d
					if u._scState == "CatchingUp" then nC += 1 end
					local pg = u._j23Prev
					if pg then mxV = math.max(mxV, fd(p.Goal, pg) / tdt) end
					u._j23Prev = p.Goal
				end
				if moving then
					m.jErrMove = math.max(m.jErrMove or 0, mx); m.jSum = (m.jSum or 0) + sum / #units; m.jN = (m.jN or 0) + 1
					m.jCatch = math.max(m.jCatch or 0, nC)
				else
					m.jErrStand = math.max(m.jErrStand or 0, mx); m.jCatchStand = math.max(m.jCatchStand or 0, nC)
				end
				m.jSlotV = math.max(m.jSlotV or 0, mxV)
				local sg = sc.Segs[segI]
				if sg and sg.V == 0 and sg.R ~= 0 then
					m.jSpin = m.jSpin or {}
					for _, u in ipairs(units) do
						local p = plans[u]
						m.jSpin[u] = m.jSpin[u] or p.Goal
						m.jStandMove = math.max(m.jStandMove or 0, fd(p.Goal, m.jSpin[u]))
					end
				end
			end
			-- per-tick metrics (after a 1 s start-up)
			if t > 1 then
				local mv = army.Trail.Vel
				local mdir = if mv.Magnitude > 2 then mv.Unit else nil
				local err2, cnt = 0, 0
				local ranks = {}
				for _, u in ipairs(units) do
					local p = plans[u]
					local lp = frames[p.Row]:PointToObjectSpace(flat(u.Root.Position) + vec(0, frames[p.Row].P.Y, 0))
					local ex, ez = lp.X - p.X, lp.Z
					err2 += ex * ex + ez * ez
					cnt += 1
					ranks[p.Row] = ranks[p.Row] or {}
					table.insert(ranks[p.Row], { X = p.X, LX = lp.X, U = u })
					-- slot speed
					local pg = prevGoal[u]
					if pg then m.maxSlotSpeed = math.max(m.maxSlotSpeed, fd(p.Goal, pg) / tdt) end
					prevGoal[u] = p.Goal
					m.minOwnerSlot = math.min(m.minOwnerSlot, fd(p.Goal, owner))
					-- ahead of him (the far side, in front) while he moves
					if mdir and army.Trail.Moving then
						local rel = flat(p.Goal - owner)
						if rel:Dot(mdir) > 1 then
							m.slotAhead += 1
							-- orbit: in front AND off his own old trail (not the column walking back up his path)
							local near = math.huge
							for _, c in ipairs(army.Trail.Pts) do near = math.min(near, fd(c, p.Goal)) end
							if near > CFG.AisleStuds / 2 + (CFG.ColumnsMax / 2 - 1) * CFG.ColSpacing + CFG.PartMaxStuds + 1.5 then
								-- claude-bud JOB 23: a steered block (Follow3.Steer) that is WAITING for him to walk back through it
								-- is the block he walks into (held still, heading held), not a slot swinging round him
								if army.Form and army.Form.Waiting then m.orbitWait = (m.orbitWait or 0) + 1 else m.orbit += 1 end
								if DEBUGNEAR then print(string.format("ORBIT %s t=%.2f %s near=%.1f waiting=%s", sc.Name, t, u.Id, near, tostring(army.Form and army.Form.Waiting))) end
							end
						end
						if flat(u.Root.Position - owner):Dot(mdir) > 1 then m.soldierAhead += 1 end
					end
				end
				local rms = math.sqrt(err2 / math.max(1, cnt))
				if moving then m.rmsSum += rms; m.rmsN += 1 end
				m.rmsMax = math.max(m.rmsMax, rms)
				if t >= 3 then m.rmsMax3 = math.max(m.rmsMax3 or 0, rms) end -- claude-bud JOB 40: the worst after the first 3 s
				for _, list in pairs(ranks) do
					if #list >= 2 then
						local lo, hi, dlo, dhi = math.huge, -math.huge, math.huge, -math.huge
						for _, e in ipairs(list) do lo = math.min(lo, e.LX); hi = math.max(hi, e.LX); dlo = math.min(dlo, e.X); dhi = math.max(dhi, e.X) end
						m.widthRatio = math.max(m.widthRatio, (hi - lo) / math.max(1e-3, dhi - dlo))
						for i = 1, #list do for j = 1, #list do
							if list[i].X < list[j].X and list[i].LX > list[j].LX + 0.5 then if (list[i].U._simYieldUntil or 0) > t or (list[j].U._simYieldUntil or 0) > t then m.rankYield += 1 else m.rankViol += 1 end; if DEBUGNEAR then print(string.format("RANKX %s t=%.2f %s %s by %.2f turning=%s", sc.Name, t, list[i].U.Id, list[j].U.Id, list[i].LX - list[j].LX, tostring(army.Trail.RowTurn[plans[list[i].U].Row]))) end end
						end end
					end
				end
				-- depth order: a unit of a later rank stands behind (in that rank's frame) every unit of the rank ahead
				for _, u in ipairs(units) do
					for _, o in ipairs(units) do
						local pu, po = plans[u], plans[o]
						-- (only between rows walking the same way: in an about-turn fold the rows pass back down his path)
						if po.Row > pu.Row and FC.Tangent(army.Trail, FC.RowArc(pu.Row, CFG), CFG):Dot(FC.Tangent(army.Trail, FC.RowArc(po.Row, CFG), CFG)) > 0.5 then
							local lo = frames[pu.Row]:PointToObjectSpace(flat(o.Root.Position) + vec(0, frames[pu.Row].P.Y, 0))
							if lo.Z < -1 then m.rankViol += 1; if DEBUGNEAR then print(string.format("RANKZ %s t=%.2f %s ahead of %s by %.1f", sc.Name, t, o.Id, u.Id, -lo.Z)) end end
						end
					end
				end
			end
			if DEBUGNEAR and ((sc.Name == "u180" and t > 6 and t < 8.6) or (sc.Name == "maxArmy" and t > 15.6 and t < 17.2)) then
				local f0 = frames[0]
				local ia, ib = if sc.Name == "u180" then 1 else 2, if sc.Name == "u180" then 3 else 4
				local l1 = f0:PointToObjectSpace(units[ia].Root.Position)
				local l3 = f0:PointToObjectSpace(units[ib].Root.Position)
				print(string.format("DBG t=%.2f side=%d look=(%.2f,%.2f) s1=(%.1f,%.1f) s3=(%.1f,%.1f) g1x=%.1f g3x=%.1f st1=%s st3=%s y1=%s y3=%s", t, FC.RowSide(army.Trail, 0), f0.LookVector.X, f0.LookVector.Z, l1.X, l1.Z, l3.X, l3.Z, plans[units[ia]].X, plans[units[ib]].X, tostring(units[ia]._scState), tostring(units[ib]._scState), tostring(units[ia]._scYielding), tostring(units[ib]._scYielding)))
			end
			if trace then
				local parts = { string.format("TRACE,%s,%.2f,%.2f,%.2f", sc.Name, t, owner.X, owner.Z) }
				for _, u in ipairs(units) do
					local p = plans[u]
					table.insert(parts, string.format("%.2f,%.2f,%.2f,%.2f", u.Root.Position.X, u.Root.Position.Z, p.Goal.X, p.Goal.Z))
				end
				print(table.concat(parts, ","))
			end
			nextTick += tick
		end
		-- physics
		for _, u in ipairs(units) do
			local before = u.Root.Position
			walk(u, dt)
			if fd(u.Root.Position, before) > 6 then m.teleports += 1 end
		end
		if t > 1 then
			for i = 1, N do
				local a = units[i]
				local od = fd(a.Root.Position, owner)
				if od < 3 and DEBUGNEAR then
					local rel = flat(a.Root.Position - owner)
					local lv = if ownerVelNow.Magnitude > 0 then ownerVelNow.Unit else vec(0,0,-1)
					print(string.format("NEAR %s t=%.2f %s d=%.2f along=%.2f lat=%.2f yield=%s state=%s goalRel=(%.1f,%.1f)", sc.Name, t, a.Id, od, rel:Dot(lv), rel:Dot(vec(-lv.Z,0,lv.X)), tostring(a._scYielding), tostring(a._scState),
						plans[a].Goal.X - owner.X, plans[a].Goal.Z - owner.Z))
				end
				if od < m.minOwner then
					m.minOwner = od
					local rel = flat(a.Root.Position - owner)
					m.minOwnerAt = string.format("t=%.2f %s rel=(%.1f,%.1f) goal=(%.1f,%.1f) tgt=%s ws=%.1f", t, a.Id, rel.X, rel.Z, plans[a].Goal.X - owner.X, plans[a].Goal.Z - owner.Z,
						if a.Humanoid.Target then string.format("(%.1f,%.1f)", a.Humanoid.Target.X - owner.X, a.Humanoid.Target.Z - owner.Z) else "nil", a.Humanoid.WalkSpeed)
				end
				for j = i + 1, N do
					local b = units[j]
					if prevPos[a] and prevPos[b] and cross(prevPos[a], a.Root.Position, prevPos[b], b.Root.Position) then m.crossings += 1; if DEBUGNEAR then print(string.format("CROSS %s t=%.2f %s %s", sc.Name, t, a.Id, b.Id)) end end
				end
			end
		end
		for _, u in ipairs(units) do prevPos[u] = u.Root.Position end
		t += dt
	end
	m.teleports += pivots
	for _, u in ipairs(units) do m.moves += (u.Cmds or 0) end
	m.movesPerSec = m.moves / N / total
	m.rmsMean = if m.rmsN > 0 then m.rmsSum / m.rmsN else 0
	-- settled: final RMS (he stood >= 3 s at the end of every path but straight)
	local err2 = 0
	for _, u in ipairs(units) do local p = plans[u]; local d = fd(u.Root.Position, p.Goal); err2 += d * d end
	m.finalRms = math.sqrt(err2 / N)
	m.cap = cap
	results[sc.Name] = m
	print("MINOWNER," .. sc.Name .. "," .. tostring(m.minOwnerAt))
	if J23 then
		print(string.format("J23,%s,maxErrMoving=%.2f,meanErrMoving=%.2f,maxCatching=%d,of=%d,maxErrStanding=%.2f,maxCatchingStanding=%d,maxSlotSpeed=%.1f,standMove=%.2f,slotChanges=%d,teleports=%d,minOwner=%.2f,minOwnerSlot=%.2f",
			sc.Name, m.jErrMove or 0, if (m.jN or 0) > 0 then m.jSum / m.jN else 0, m.jCatch or 0, N, m.jErrStand or 0, m.jCatchStand or 0, m.jSlotV or 0,
			m.jStandMove or 0, m.slotChanges, m.teleports, m.minOwner, m.minOwnerSlot))
	end
	print(string.format("METRIC,%s,slotChanges=%d,teleports=%d,rmsMean=%.2f,rmsMax=%.2f,finalRms=%.2f,widthRatio=%.2f,rankViol=%d,rankYield=%d,crossings=%d,minOwner=%.2f,minOwnerSlot=%.2f,slotAhead=%d,soldierAhead=%d,orbit=%d,maxSlotSpeed=%.1f,cap=%.1f,movesPerSec=%.2f,maxRowTurn=%.0f,rmsMax3=%.2f",
		sc.Name, m.slotChanges, m.teleports, m.rmsMean, m.rmsMax, m.finalRms, m.widthRatio, m.rankViol, m.rankYield, m.crossings, m.minOwner, m.minOwnerSlot,
		m.slotAhead, m.soldierAhead, m.orbit, m.maxSlotSpeed, cap, m.movesPerSec, m.maxTurnDeg, m.rmsMax3 or 0))
end

-- ── thresholds ────────────────────────────────────────────────────────────────────────────────────────────────────
-- (claude-bud JOB 23: the A..J set has its own thresholds in tools/checks/claude_bud_armyj23.py)
for _, sc in ipairs(if J23 then {} else SCEN) do
	local m = results[sc.Name]
	local nm = sc.Name
	local rev = nm == "u180" or nm == "maxArmy" -- an about-turn: the rows walk back up his old path past him (by design)
	check(m.slotChanges == 0, nm .. ": 0 slot changes (" .. m.slotChanges .. ")")
	check(m.teleports == 0, nm .. ": 0 teleports / PivotTo (" .. m.teleports .. ")")
	-- startStop / rapidLR: every start or reversal of direction costs the block ~one update tick + humanoid acceleration of
	-- lag (the slots move at once, the soldiers answer on the next 0.2 s tick), so the mean error while moving is higher
	-- there by design; the geometry checks (width, rank, crossings, orbit) still apply unchanged
	local lag = nm == "startStop" or nm == "rapidLR"
	local rmsCap = if rev then 3.5 elseif lag then 3.25 else 2.5
	check(m.rmsMean <= rmsCap, string.format("%s: mean formation RMS error while moving <= %.2f (%.2f)", nm, rmsCap, m.rmsMean))
	if not rev then
		check(m.rankYield == 0, string.format("%s: no rank swap even while stepping out of his lane (%d)", nm, m.rankYield))
	end
	check(m.rmsMax <= (if rev then 12 else 6), string.format("%s: worst-tick formation RMS error <= %d (%.2f)", nm, if rev then 12 else 6, m.rmsMax))
	check(m.finalRms <= 3, string.format("%s: settled in its own slots at the end (RMS %.2f <= 3; in-slot hysteresis LeaveStuds %d)", nm, m.finalRms, CFG.LeaveStuds))
	check(m.widthRatio <= 1.5, string.format("%s: no rank wider than 1.5x its design width (%.2f)", nm, m.widthRatio))
	check(m.rankViol == 0, nm .. ": rank order kept across and along the block (" .. m.rankViol .. " violations)")
	check(m.crossings == 0, nm .. ": no two soldier paths cross (" .. m.crossings .. ")")
	local minO = if rev then 2 else 3 -- an about-turn straight back into his block: they step aside (2 = two bodies not touching)
	check(m.minOwner >= minO, string.format("%s: no soldier within %d studs of him - nobody runs through him (min %.2f)", nm, minO, m.minOwner))
	check(m.orbit == 0, nm .. ": no slot in front of him off his own path - no orbit / no wings (" .. m.orbit .. ")")
	if not rev then
		check(m.slotAhead == 0, nm .. ": no slot ahead of him during turns (" .. m.slotAhead .. ")")
		check(m.minOwnerSlot >= CFG.FirstRowStuds - 1.5, string.format("%s: every slot stays >= %.1f studs from him (min %.2f)", nm, CFG.FirstRowStuds - 1.5, m.minOwnerSlot))
	end
	check(m.maxSlotSpeed <= m.cap, string.format("%s: slots never move faster than a soldier can run (max %.1f <= %.1f)", nm, m.maxSlotSpeed, m.cap))
	check(m.movesPerSec <= 1 / CFG.UpdateSeconds + 0.1, string.format("%s: MoveTo <= 5 per soldier per second (%.2f)", nm, m.movesPerSec))
	check(m.maxTurnDeg <= CFG.RowTurnDegPerSec + 1, string.format("%s: rows turn <= %d deg/s (%.0f)", nm, CFG.RowTurnDegPerSec, m.maxTurnDeg))
end
print("FAILS " .. fails)
