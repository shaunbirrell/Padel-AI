--[[ claude-bud JOB 24 (docs/ARMY-ATTACK-ROOTCAUSE.md): the army ATTACK acceptance simulation. tools/sim/run_attack_sim.py
	fills the markers and runs it twice in the Luau CLI:
	  * MODE "old": the v116 ATTACK movement, re-implemented line for line from SquadOrdersService.attackUnit (no line
	    of sight blocks in this flat world): every 0.4 s think each soldier picks the hostile nearest ITSELF within
	    AttackAggroRange, walks (MoveTo every think, WalkSpeed = UnitWalkSpeed 14) to its own ring seat
	    (ArmyFollow.AttackPoint "ring", AttackRingMin 8 round the target) until it is inside the fire band (85 % of
	    AttackRange), then MoveTos its own position; with nothing in reach it walks to its "march" spot in rows in front
	    of the owner's LOOK vector. The formation controller has let go (ArmyController returns for a non-FOLLOW order).
	  * MODE "new": the REAL Shared/Util/FormationController (the steered block with army.Attack set: advance as a block,
	    deploy into the line, fold back) and the REAL Server/Modules/SoldierController (Drive), every 0.2 s, with the
	    sticky squad target (FormationController.PickTarget) and the leash, as ArmyController / SquadOrdersService do.
	FOLLOW before / after the attack is the real v116 follow in both modes. Mock humanoids as in army_follow_sim.luau
	(walk to the MoveTo point at WalkSpeed, 80 studs/s^2, 720 deg/s); no collisions (off in game too), no terrain. ]]
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

local MODE = "new" --@@MODE@@
DEBUGPAIR = false
local AGGRO, RANGE, WALK = 120, 55, 14 -- OrdersConfig.AttackAggroRange / AttackRange / UnitWalkSpeed
local BAND = RANGE * 0.85 -- the fire band
local LEASH = CFG.AttackLeashStuds or 140
local function flat(v) return vec(v.X, 0, v.Z) end
local function fd(a, b) local dx, dz = a.X - b.X, a.Z - b.Z; return math.sqrt(dx * dx + dz * dz) end

local pivots = 0
local function mkUnit(i, p, esc)
	local u = { Id = "s" .. i, Slot = i, Alive = true, LastFireAt = -1e9, OwnerUserId = 1, Esc = esc, Vel = vec(0, 0, 0), Moved = 0 }
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
	u.Moved += fd(np, u.Root.Position)
	u.Root.Position = np
	local face = u.Root.CFrame.LookVector
	if u.Vel.Magnitude > 0.5 then face = FC.Turn(flat(face).Unit, u.Vel.Unit, TURN * dt) end
	u.Root.CFrame = CFrame.lookAt(np, np + face)
end
local function cross(a1, a2, b1, b2)
	local function o(p, q, r) return (q.X - p.X) * (r.Z - p.Z) - (q.Z - p.Z) * (r.X - p.X) end
	local d1, d2 = o(b1, b2, a1), o(b1, b2, a2)
	local d3, d4 = o(a1, a2, b1), o(a1, a2, b2)
	return ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0))
end

-- ── scenarios: owner segments { T, V, R deg/s }, targets { P, V, DieAt }, orders { At, Order } ─────────────────────
local function seg(T, Vs, R) return { T = T, V = Vs, R = R or 0 } end
local E5 = { 3, 3, 0, 0, 0 }
local E8 = { 3, 3, 3, 3, 0, 0, 0, 0 }
local SCEN = {}
local function add(name, segs, targets, orders, esc, heading)
	table.insert(SCEN, { Name = name, Segs = segs, Targets = targets, Orders = orders, Esc = esc, Hdg = heading or 0 })
end
local function tg(x, z, vx, vz, dieAt, stopAt) return { P = vec(x, 3, z), V = vec(vx or 0, 0, vz or 0), DieAt = dieAt, StopAt = stopAt } end
add("stationary", { seg(20, 0) }, { tg(0, -80) }, { { At = 1, Order = "Attack" }, { At = 15, Order = "Follow" } }, E5)
add("movingTarget", { seg(22, 0) }, { tg(-40, -80, 8, 0, nil, 11) }, { { At = 1, Order = "Attack" }, { At = 17, Order = "Follow" } }, E5)
add("targetDies", { seg(20, 0) }, { tg(20, -75, 0, 0, 9) }, { { At = 1, Order = "Attack" } }, E5)
add("switchTargets", { seg(22, 0) }, { tg(0, -80, 0, 0, 9), tg(75, -45) }, { { At = 1, Order = "Attack" }, { At = 19, Order = "Follow" } }, E5)
add("cancel", { seg(16, 0) }, { tg(0, -80) }, { { At = 1, Order = "Attack" }, { At = 5, Order = "Follow" } }, E5)
add("maxArmy", { seg(20, 0) }, { tg(0, -80) }, { { At = 1, Order = "Attack" }, { At = 15, Order = "Follow" } }, E8)
-- he keeps walking (east, 16 studs/s) through the whole fight: past the leash the army leaves the target and follows him
add("ownerWalks", { seg(2, 0), seg(16, 16), seg(4, 0) }, { tg(0, -70) }, { { At = 1, Order = "Attack" } }, E5, math.rad(-90))

local results = {}
for _, sc in ipairs(SCEN) do
	pivots = 0
	local N = #sc.Esc
	local owner = vec(0, 3, 0)
	local hdg = sc.Hdg
	local function dirOf(h) return vec(-math.sin(h), 0, -math.cos(h)) end
	local army = FC.NewArmy()
	local units = {}
	for i = 1, N do
		local off = FC.SpawnOffset(i, CFG)
		local look = dirOf(hdg)
		local right = vec(-look.Z, 0, look.X)
		units[i] = mkUnit(i, owner + right * off.X - look * off.Z, sc.Esc[i])
	end
	FC.Assign(army.Assign, units)
	local first = {}
	for _, u in ipairs(units) do first[u] = army.Assign.ByUnit[u] end
	local escOf = function(u) return u.Esc end
	local targets = {}
	for i, t0 in ipairs(sc.Targets) do targets[i] = { Key = i, P = t0.P, V = t0.V, DieAt = t0.DieAt, StopAt = t0.StopAt, Alive = true } end
	local dt, tick = 1 / 30, CFG.UpdateSeconds
	local total = 0
	for _, s in ipairs(sc.Segs) do total += math.max(1, math.floor(s.T / dt + 0.5)) * dt end
	local t, segI, segT = 0, 1, 0
	local nextTick, nextThink = 0, 0
	local lastOwner, lastTickAt = owner, nil
	local order, orderI = "Follow", 1
	local curTarget = nil
	local ownerVelNow = vec(0, 0, 0)
	local plans = nil
	local attackStart, attackEnd = nil, nil
	local m = { slotChanges = 0, teleports = 0, minPair = math.huge, clumpTicks = 0, ticks = 0, inBand = 0, bandN = 0, deployT = -1,
		settledMove = 0, settledT = 0, errMax = 0, errSum = 0, errN = 0, reformT = -1, minOwner = math.huge, crossings = 0, maxWS = 0,
		movesAtk = 0, atkT = 0, engagedEnd = nil }
	local prevPos = {}
	local prevAttack = false
	local movesAtStart = 0
	local movesAtEnd = nil
	while t < total + 1e-9 do
		-- orders
		local o = sc.Orders[orderI]
		if o and t >= o.At - 1e-9 then
			order = o.Order
			orderI += 1
			if order == "Attack" then
				attackStart = t
				for _, u in ipairs(units) do movesAtStart += (u.Cmds or 0) end
			elseif attackStart and attackEnd == nil then
				attackEnd = t
				movesAtEnd = 0
				for _, u in ipairs(units) do movesAtEnd += (u.Cmds or 0) end
			end
		end
		-- owner and targets
		local s = sc.Segs[segI]
		if s then
			local steps = math.max(1, math.floor(s.T / dt + 0.5))
			hdg += math.rad(s.R * s.T) / steps
			ownerVelNow = dirOf(hdg) * s.V
			owner = owner + ownerVelNow * dt
			segT += 1
			if segT >= steps then segI += 1; segT = 0 end
		end
		for _, tt in ipairs(targets) do
			if tt.Alive and tt.DieAt and t >= tt.DieAt then tt.Alive = false end
			if tt.Alive and not (tt.StopAt and t >= tt.StopAt) then tt.P = tt.P + tt.V * dt end
		end
		local attacking = order == "Attack"
		-- the squad target (new) / "is anything in reach" (old): alive targets
		local centre = vec(0, 0, 0)
		for _, u in ipairs(units) do centre = centre + flat(u.Root.Position) end
		centre = centre / N
		-- controller tick
		local oldAttack = MODE == "old" and attacking
		if not oldAttack and t >= nextTick - 1e-9 then
			local tdt = if lastTickAt then t - lastTickAt else tick
			local vel = if lastTickAt then flat(owner - lastOwner) / tdt else vec(0, 0, 0)
			local snap = lastTickAt == nil
			lastOwner, lastTickAt = owner, t
			army.Attack = nil
			if attacking then
				local cands = {}
				for _, tt in ipairs(targets) do
					if tt.Alive and fd(tt.P, owner) <= LEASH then table.insert(cands, { Key = tt.Key, Pos = tt.P }) end
				end
				local fromC = if army.Form then army.Form.C else centre
				curTarget = FC.PickTarget(curTarget, cands, fromC, CFG)
				if curTarget then army.Attack = { Pos = targets[curTarget].P } end
			else
				curTarget = nil
			end
			FC.Assign(army.Assign, units)
			for _, u in ipairs(units) do if army.Assign.ByUnit[u] ~= first[u] then m.slotChanges += 1 end end
			plans = FC.Plan(army, units, owner, dirOf(hdg), vel, tdt, snap, escOf, CFG, ownerVelNow)
			local moving = FC.BlockMoving(army, CFG)
			for _, u in ipairs(units) do
				local p = plans[u]
				SC.Drive(u, { Goal = p.Goal, Heading = p.Heading, Lead = p.Lead, OwnerPos = owner, OwnerMoving = moving, Pace = p.Pace,
					BaseSpeed = WALK, Dt = tdt, Now = t, AllowRecover = true, OwnerClear = CFG.OwnerClearStuds, OwnerVel = ownerVelNow,
					Spot = function() return CFrame.lookAt(p.Goal, p.Goal + p.Heading) end, OutOfView = function() return true end })
				m.maxWS = math.max(m.maxWS, u.Humanoid.WalkSpeed)
				if attacking and u.Humanoid.WalkSpeed > (m.maxWSAtk or 0) then
					m.maxWSAtk = u.Humanoid.WalkSpeed
					m.maxWSAt = string.format("t=%.2f %s pace=%.1f dep=%.2f d=%.1f", t, u.Id, p.Pace, army.Form and army.Form.Deploy or -1, fd(u.Root.Position, p.Goal))
				end
			end
			-- slot error once deployed (new)
			if attacking and army.Form and (army.Form.Deploy or 0) >= 0.999 then
				for _, u in ipairs(units) do
					local d = fd(u.Root.Position, plans[u].Goal)
					m.errMax = math.max(m.errMax, d); m.errSum += d; m.errN += 1
				end
			end
			nextTick += tick
		elseif oldAttack and t >= nextThink - 1e-9 then
			-- v116 SquadOrdersService.attackUnit movement (per unit, every ThinkInterval 0.4 s); Release: the Follow3
			-- controller let go (its state is reset when FOLLOW takes the unit back)
			lastTickAt = nil -- (FOLLOW restarts fresh afterwards: ArmyController's snap on a state change)
			local look = dirOf(hdg)
			local right = vec(-look.Z, 0, look.X)
			for k, u in ipairs(units) do
				SC.Release(u)
				u.Humanoid.WalkSpeed = WALK -- _PaceSpeed(unit, 0) outside FOLLOW
				local best, bd = nil, AGGRO
				for _, tt in ipairs(targets) do
					if tt.Alive then
						local d = fd(tt.P, u.Root.Position)
						if d < bd then best, bd = tt, d end
					end
				end
				if best == nil then
					-- ArmyFollow.AttackPoint "march": MarchPerRow 5, MarchSpacing 3.5, MarchAhead 10, in front of his LOOK
					local perRow = 5
					local row = (k - 1) // perRow
					local col = (k - 1) % perRow
					local inRow = math.min(perRow, N - row * perRow)
					local lateral = (col - (inRow - 1) * 0.5) * 3.5
					SC.Move(u, owner + look * (10 + row * 3.5) + right * lateral)
				else
					-- ArmyFollow.AttackPoint "ring" round the target, facing = target - owner
					local f = flat(best.P - owner); f = if f.Magnitude > 1e-3 then f.Unit else vec(0, 0, -1)
					local rr = vec(-f.Z, 0, f.X)
					local r = math.max(8, N * 3.5 / (2 * math.pi))
					local a = (k - 1) * 2 * math.pi / N
					local ringAt = best.P + (-f * math.cos(a) + rr * math.sin(a)) * r
					if bd > BAND then SC.Move(u, ringAt) else SC.Move(u, u.Root.Position) end
				end
			end
			nextThink = t + 0.4
			nextTick = t
		end
		-- metrics during the attack order
		if attacking and t > (attackStart or 0) + 0.5 then
			m.ticks += 1
			local alive = nil
			if MODE == "new" then
				alive = if curTarget then targets[curTarget] else nil
			else
				for _, tt in ipairs(targets) do if tt.Alive then alive = tt; break end end
			end
			for i = 1, N do
				for j = i + 1, N do
					local d = fd(units[i].Root.Position, units[j].Root.Position)
					m.minPair = math.min(m.minPair, d)
					if d < 2.5 then
						m.clumpTicks += 1
						if DEBUGPAIR and MODE == "new" then
							local pi, pj = plans and plans[units[i]], plans and plans[units[j]]
							print(string.format("PAIR %s t=%.2f %s %s d=%.2f goalsD=%.2f dep=%.2f vi=(%.1f,%.1f) vj=(%.1f,%.1f) sti=%s stj=%s", sc.Name, t, units[i].Id, units[j].Id, d,
								if pi and pj then fd(pi.Goal, pj.Goal) else -1, army.Form and army.Form.Deploy or -1, units[i].Vel.X, units[i].Vel.Z, units[j].Vel.X, units[j].Vel.Z,
								tostring(units[i]._scState), tostring(units[j]._scState)))
						end
					end
				end
			end
			if alive then
				local allIn, allStill = true, true
				for _, u in ipairs(units) do
					local d = fd(u.Root.Position, alive.P)
					m.bandN += 1
					if d <= BAND then m.inBand += 1 else allIn = false end
					if u.Vel.Magnitude > 2 then allStill = false end
				end
				if m.settleKey ~= alive then m.settleKey = alive; m.settleFrom = nil; for _, u in ipairs(units) do u._mv0 = nil end end
				if allIn and allStill and m.settleFrom == nil then
					if m.deployT < 0 then m.deployT = t - attackStart end
					m.settleFrom = t
				end
				if m.settleFrom and (alive.V.Magnitude == 0 or (alive.StopAt and t >= alive.StopAt)) then
					m.settledT += dt
					for _, u in ipairs(units) do
						m.settledMove += u.Moved - (u._mv0 or u.Moved)
						u._mv0 = u.Moved
					end
				end
			elseif m.engagedEnd == nil and m.deployT >= 0 then
				m.engagedEnd = t -- the target is down / out of reach and nothing else: the army should reform
			end
		end
		-- reform: all within 3 studs of their FOLLOW slots after the attack ended (cancel / target gone)
		local reformFrom = attackEnd or m.engagedEnd
		if reformFrom and m.reformT < 0 and plans and not oldAttack and army.Attack == nil and (army.Form == nil or (army.Form.Deploy or 0) <= 0) then
			local ok = true
			for _, u in ipairs(units) do if fd(u.Root.Position, plans[u].Goal) > 3 then ok = false end end
			if ok then m.reformT = t - reformFrom end
		end
		-- physics
		for _, u in ipairs(units) do
			local before = u.Root.Position
			walk(u, dt)
			if fd(u.Root.Position, before) > 6 then m.teleports += 1 end
		end
		for i = 1, N do
			m.minOwner = math.min(m.minOwner, fd(units[i].Root.Position, owner))
			for j = i + 1, N do
				if prevPos[units[i]] and prevPos[units[j]] and cross(prevPos[units[i]], units[i].Root.Position, prevPos[units[j]], units[j].Root.Position) then m.crossings += 1 end
			end
		end
		for _, u in ipairs(units) do prevPos[u] = u.Root.Position end
		t += dt
	end
	m.teleports += pivots
	local moves = 0
	for _, u in ipairs(units) do moves += (u.Cmds or 0) end
	if movesAtEnd then moves = movesAtEnd end
	local atkDur = (attackEnd or total) - (attackStart or 0)
	m.movesPerSec = (moves - movesAtStart) / N / math.max(0.1, atkDur)
	print("WSAT," .. MODE .. "," .. sc.Name .. "," .. tostring(m.maxWSAtk) .. " " .. tostring(m.maxWSAt))
	print(string.format("ATTACK,%s,%s,deployT=%.2f,inBand=%.2f,minPair=%.2f,clumpTicks=%d,settledRun=%.2f,slotErrMax=%.2f,slotErrMean=%.2f,reformT=%.2f,minOwner=%.2f,crossings=%d,teleports=%d,slotChanges=%d,maxWalkSpeed=%.1f,movesPerSec=%.2f",
		MODE, sc.Name, m.deployT, if m.bandN > 0 then m.inBand / m.bandN else 0, m.minPair, m.clumpTicks,
		if m.settledT > 0 then m.settledMove / N / m.settledT else 0, m.errMax, if m.errN > 0 then m.errSum / m.errN else 0,
		m.reformT, m.minOwner, m.crossings, m.teleports, m.slotChanges, m.maxWS, m.movesPerSec))
end
