# claude-bud JOB 22 (2026-09-29): the army follow / formation root-cause fix (docs/ARMY-FOLLOW-ROOTCAUSE.md).
# Static: ONE module calls Humanoid:MoveTo on a soldier; no per-frame loops / root CFrame writes in the follow path;
# seats are never re-picked per think; collision groups set. Executed: Shared/Util/FormationMath in the Luau CLI with a
# simulated owner (straight, 90 slow, 180 fast, circle, sudden stop, strafe, backwards, zig-zag) and 5 / 8 / 20 / 50
# soldiers: bounded MoveTo rate, nothing issued at rest, no heading flip, capped turn rate, stable seat sides.
import os as _af_os
import subprocess as _af_sp
import tempfile as _af_tf

_af_a = "src/ServerScriptService/Server/Modules/ArmyFollow.luau"
_af_s = "src/ServerScriptService/Server/Services/SquadOrdersService.luau"
_af_fm = "src/ReplicatedStorage/Shared/Util/FormationMath.luau"
_af_cfg = "src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau"


def _af_code(path):
    t = read(path) or ""
    return "\n".join(l.split("--", 1)[0] for l in t.splitlines())


_A, _S = _af_code(_af_a), _af_code(_af_s)
# 1. exactly one mover
# v114 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v114_army.py (every soldier MoveTo is SoldierController.Move, the one PivotTo is SoldierController.Reposition): #(ok if _A.count("Humanoid:MoveTo(") == 1 and "unit.Humanoid:MoveTo(goal)" in _A else bad)(f"CLAUDE-BUD J22: ArmyFollow.Command is the only Humanoid:MoveTo in ArmyFollow ({_A.count('Humanoid:MoveTo(')})")
(ok if _A.count("Humanoid:MoveTo(") == 0 and "SoldierController.Move(unit, goal, state)" in _A else bad)(f"CLAUDE-BUD J22 (v114): ArmyFollow.Command forwards to SoldierController.Move ({_A.count('Humanoid:MoveTo(')} direct)")
(ok if _S.count("Humanoid:MoveTo(") == 0 and _S.count("SquadOrdersService._AF.Command(unit, ") >= 30 else bad)(f"CLAUDE-BUD J22: SquadOrdersService never moves a soldier itself ({_S.count('Humanoid:MoveTo(')} direct, {_S.count('SquadOrdersService._AF.Command(unit, ')} via Command)")
must_contain(_af_a, "function ArmyFollow.Command(unit: any, goal: Vector3, state: string?)", "CLAUDE-BUD J22: the one mover API (with its state)")
must_contain(_af_s, 'SquadOrdersService._AF.Release(unit, order) -- v99: HOLD / ATTACK / RETREAT drive it now', "CLAUDE-BUD J22: an order takes a unit with its state")
must_contain(_af_s, 'SquadOrdersService._AF.Release(unit, "Combat") -- claude-bud JOB 22', "CLAUDE-BUD J22: the escort fight takes a unit as Combat")
# the retired pins' replacements (squadfair ATTACK chase, recover re-issue)
must_contain(_af_s, "\t\tSquadOrdersService._AF.Command(unit, nroot.Position) -- no clear shot: keep closing in (NPC rule), until it gives up", "CLAUDE-BUD J22 (was squadfair): an ATTACK unit with nothing in sight closes in until the give-up")
must_contain(_af_s, "SquadOrdersService._AF.Command(unit, at.Position)", "CLAUDE-BUD J22 (was army fix): MoveTo re-issued after a recover")
(ok if "resetChase(unit)" in _S else bad)("CLAUDE-BUD J22 (was army fix): chase state reset after a recover")
# 2. no per-frame loops, no root CFrame writes while humanoid-driven
(ok if not re.search(r"Heartbeat|RenderStepped|\.Stepped", _A + _S) else bad)("CLAUDE-BUD J22: no per-frame loops in army code")
# v114 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v114_army.py (every soldier MoveTo is SoldierController.Move, the one PivotTo is SoldierController.Reposition): #(ok if not re.search(r"Root\.CFrame\s*=", _A) and _A.count("PivotTo(") == 2 else bad)(f"CLAUDE-BUD J22: follow never writes the root CFrame; PivotTo only for the regroup and the base-hold turn ({_A.count('PivotTo(')})")
(ok if not re.search(r"Root\.CFrame\s*=", _A) and _A.count("PivotTo(") == 0 else bad)(f"CLAUDE-BUD J22 (v114): ArmyFollow never PivotTos (regroup -> SoldierController.Reposition) ({_A.count('PivotTo(')})")
# 3. seats: never re-picked per think (no distance in the assignment; compaction only after the size changed)
_seat = (read(_af_a) or "")
_i = _seat.find("local function assignSeats(")
_j = _seat.find("ArmyFollow.AssignSeats = assignSeats", _i)
(ok if _i >= 0 and "Magnitude" not in _seat[_i:_j] and "Position" not in _seat[_i:_j] else bad)("CLAUDE-BUD J22: seat assignment never uses distance (no nearest re-pick)")
must_contain(_af_a, "\tif st._afSeatN ~= n then", "CLAUDE-BUD J22: seats compacted only after the army size changed")
must_contain(_af_a, "st._afFlip = nil -- seat sides never swap", "CLAUDE-BUD J22: row sides never swap mid-turn")
# 4. collision + ownership
must_contain(_af_a, "PhysicsService:CollisionGroupSetCollidable(ArmyFollow.Group, ArmyFollow.Group, false)", "CLAUDE-BUD J22: soldiers never collide with each other")
# v114 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v114_army.py (every soldier MoveTo is SoldierController.Move, the one PivotTo is SoldierController.Reposition): #must_contain(_af_a, "PhysicsService:CollisionGroupSetCollidable(ArmyFollow.Group, ArmyFollow.PlayerGroup, cfg().CollideWithPlayers == true)", "CLAUDE-BUD J22: soldiers never push players")
must_contain(_af_a, "PhysicsService:CollisionGroupSetCollidable(ArmyFollow.Group, ArmyFollow.PlayerGroup, cfg().CollideWithPlayers == true and not follow3On())", "CLAUDE-BUD J22 (v114): soldiers never push players")
must_contain(_af_cfg, "\t\tCollideWithPlayers = false,", "CLAUDE-BUD J22: CollideWithPlayers off")
must_contain("src/ServerScriptService/Server/Modules/BaseGuards.luau", "PS:CollisionGroupSetCollidable(GUARD_GROUP, GUARD_GROUP, false)", "CLAUDE-BUD J22: base guards never collide with each other")
must_contain(_af_s, "SetNetworkOwner(nil)", "CLAUDE-BUD J22: the server owns every soldier root (set at spawn)")
must_contain(_af_a, "hum:SetStateEnabled(Enum.HumanoidStateType.Seated, false)", "CLAUDE-BUD J22: a soldier never sits (no vehicle assembly / ownership change)")
# 5. one yaw owner, state machine, throttle, hysteresis
must_contain(_af_a, "gyro.MaxTorque = if moving then Vector3.zero else unit._afGyroTorque", "CLAUDE-BUD J22: moving = AutoRotate faces travel, the gyro has no torque")
must_contain(_af_a, "local state = FormationMath.State(prevState, flatDist(pos, goal), cfg())", "CLAUDE-BUD J22: the follow state machine")
must_contain(_af_a, "then FormationMath.ReissueDue(last, unit._afMoveAt, goal, now, cfg())", "CLAUDE-BUD J22: MoveTo only past the reissue distance / refresh time")
must_contain(_af_s, "local moving = SquadOrdersService._AF.OwnerMoving(st, st.OwnerSpeed) or st.Seated", "CLAUDE-BUD J22: move / stand switch with hysteresis")
must_contain(_af_s, "SquadOrdersService._AF.HomePoint(player, st, unit, playerRoot, now)", "CLAUDE-BUD J22: the escort fight uses the same formation slot")
must_contain(_af_cfg, "\t\tStable = true,", "CLAUDE-BUD J22: the stable controller is on (false = v99)")
must_contain(_af_cfg, '\t\t\tFormation = "Flank",', "CLAUDE-BUD J22: Flank stays the default formation")
_rc = read("src/ReplicatedStorage/Shared/Configs/RigConfig.luau") or ""
_wr = re.search(r"WalkRateMax = ([\d.]+)", _rc)
(ok if _wr and float(_wr.group(1)) * 14.5 >= 34 else bad)(f"CLAUDE-BUD J22: the Walk animation keeps up with the catch-up speed ({_wr.group(1) if _wr else '?'} x 14.5)")

# 6. the formation maths, executed
_af_luau = _af_os.environ.get("LUAU")
if not _af_luau and _af_os.environ.get("LUAU_COMPILE"):
    for _n in ("luau.exe", "luau"):
        _p = _af_os.path.join(_af_os.path.dirname(_af_os.environ["LUAU_COMPILE"]), _n)
        if _af_os.path.exists(_p):
            _af_luau = _p
if _af_luau:
    _fm = read(_af_fm) or ""
    _cfg_src = read(_af_cfg) or ""
    _keys = ["AnchorPosLagSeconds", "AnchorVelSmoothSeconds", "AnchorLeadSeconds", "AnchorLeadMaxStuds", "HeadingMoveSpeed", "HeadingTurnDegPerSec",
             "HeadingDeadzoneDeg", "ReverseDeg", "ReverseHoldSeconds", "StandAlignDeg", "StandAlignSeconds", "ArriveDeadzoneStuds",
             "LeaveDeadzoneStuds", "MoveReissueStuds", "MoveRefreshSeconds", "MovingOnSpeed", "MovingOffSpeed", "CatchUpStartStuds"]
    _vals = {}
    _f2 = _cfg_src[_cfg_src.find("\tFollow2 = {"):]
    for _k in _keys:
        _m = re.search(r"\b" + _k + r" = (-?[\d.]+)", _f2)
        if _m:
            _vals[_k] = _m.group(1)
    _cfg_lua = "{ " + ", ".join(f"{k} = {v}" for k, v in _vals.items()) + " }"
    _code = r'''
local V = {}
V.__index = V
local function vec(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, V) end
V.__add = function(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V.__sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V.__unm = function(a) return vec(-a.X, -a.Y, -a.Z) end
V.__mul = function(a, b) if type(a) == "number" then return vec(b.X * a, b.Y * a, b.Z * a) end return vec(a.X * b, a.Y * b, a.Z * b) end
V.__div = function(a, b) return vec(a.X / b, a.Y / b, a.Z / b) end
V.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
	if k == "Unit" then local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z); return vec(t.X / m, t.Y / m, t.Z / m) end
	return V[k]
end
function V.Lerp(a, b, k) return a + (b - a) * k end
function V.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
Vector3 = { new = vec, zero = vec(0, 0, 0) }
local FM = (function()
''' + _fm + r'''
end)()
local CFG = ''' + _cfg_lua + r'''
local fails = 0
local function check(ok, label) print((ok and "PASS " or "FAIL ") .. label); if not ok then fails += 1 end end

-- Flank seat offsets (ArmyConfig.Follow2.Tidy): row k: back = -1 + (k-1)*3, side +-(3.5 + (k-1)*2.6)
local function seat(rank)
	local row = math.ceil(rank / 2)
	local side = if rank % 2 == 1 then -1 else 1
	return side * (3.5 + (row - 1) * 2.6), -1 + (row - 1) * 3
end

-- one scenario: owner path fn(t) -> pos, look (flat); N soldiers; returns metrics
local function run(N, T, path)
	local a = FM.NewAnchor()
	local units = {}
	local p0, l0 = path(0)
	for i = 1, N do
		local lat, back = seat(i)
		local right = vec(-l0.Z, 0, l0.X)
		units[i] = { Pos = p0 + right * lat - l0 * back, Goal = nil, GoalAt = nil, State = nil, Cmds = 0, CmdsAtRest = 0 }
	end
	local dt, think, t, lastThink = 0.05, 0.4, 0, -1
	local lastPos, lastDir = p0, nil
	local maxTurn, flips, sideSwaps, minGap, restCmds = 0, 0, 0, math.huge, 0
	local restStart = nil
	while t <= T do
		local pos, look = path(t)
		if t - lastThink >= think - 1e-6 then
			local vel = (pos - lastPos) / think
			vel = vec(vel.X, 0, vel.Z)
			lastPos = pos
			lastThink = t
			local before = a.Dir
			FM.Step(a, pos, look, vel, think, t, false, CFG)
			if before then
				local d = math.abs(FM.Angle(before, a.Dir))
				maxTurn = math.max(maxTurn, d)
				if d > math.rad(150) then flips += 1 end
			end
			local ownerStill = vel.Magnitude < 0.5
			if ownerStill then restStart = restStart or t else restStart = nil end
			for i, u in ipairs(units) do
				local lat, back = seat(i)
				local slot = FM.SlotWorld(a, lat, back, 0, CFG)
				local dflat = (vec(slot.X, 0, slot.Z) - vec(u.Pos.X, 0, u.Pos.Z)).Magnitude
				local prev = u.State
				u.State = FM.State(prev, dflat, CFG)
				if u.State == "InPosition" then
					if prev ~= "InPosition" then u.Goal = u.Pos; u.GoalAt = t; u.Cmds += 1 end
				elseif FM.ReissueDue(u.Goal, u.GoalAt, slot, t, CFG) then
					u.Goal = slot; u.GoalAt = t; u.Cmds += 1
					if restStart and t - restStart > 3 then restCmds += 1 end
				end
				-- seat sides relative to the anchor heading (left seats stay left)
				local dir = a.Dir
				local right = vec(-dir.Z, 0, dir.X)
				local rel = (u.Pos - a.Pos):Dot(right)
				if restStart and t - restStart > 3 and ((i % 2 == 1 and rel > 0.5) or (i % 2 == 0 and rel < -0.5)) then sideSwaps += 1 end
			end
		end
		-- soldiers walk toward their goal (catch-up speed by distance, capped), stop inside the deadzone
		for _, u in ipairs(units) do
			if u.Goal then
				local off = vec(u.Goal.X - u.Pos.X, 0, u.Goal.Z - u.Pos.Z)
				local m = off.Magnitude
				local sp = math.min(34, 17 + math.max(0, m - 5) * 1.2)
				if m > 0.05 then u.Pos = u.Pos + off.Unit * math.min(m, sp * dt) end
			end
		end
		for i = 1, N do for j = i + 1, N do
			local g = (vec(units[i].Pos.X, 0, units[i].Pos.Z) - vec(units[j].Pos.X, 0, units[j].Pos.Z)).Magnitude
			if g < minGap then minGap = g end
		end end
		t += dt
	end
	local cmds = 0
	for _, u in ipairs(units) do cmds += u.Cmds end
	return { Rate = cmds / N / T, MaxTurnPerThink = math.deg(maxTurn), Flips = flips, SideSwaps = sideSwaps, MinGap = minGap, RestCmds = restCmds }
end

local speed = 16
local function straight(t) return vec(0, 0, -speed * t), vec(0, 0, -1) end
local function stopAfter(t) local tt = math.min(t, 3); return vec(0, 0, -speed * tt), vec(0, 0, -1) end
local function slow90(t)
	if t < 2 then return vec(0, 0, -speed * t), vec(0, 0, -1) end
	local a = math.min((t - 2) / 2, 1) * math.pi / 2 -- a 90 degree arc over 2 s
	local r = speed * 2 / math.pi * 2
	if t < 4 then return vec(r - r * math.cos(a) , 0, -speed * 2 - r * math.sin(a)), vec(math.sin(a), 0, -math.cos(a)) end
	return vec(r + speed * (t - 4), 0, -speed * 2 - r), vec(1, 0, 0)
end
local function fast180(t)
	if t < 2 then return vec(0, 0, -speed * t), vec(0, 0, -1) end
	return vec(0, 0, -speed * 2 + speed * (t - 2)), vec(0, 0, 1) -- an instant about-turn
end
local function backwards(t) return vec(0, 0, 8 * t), vec(0, 0, -1) end -- facing north, walking south (shift-lock)
local function strafe(t) return vec(-10 * t, 0, 0), vec(0, 0, -1) end -- facing north, strafing west
local function zigzag(t) local x = math.sin(t * 2) * 1.2; return vec(x, 0, -speed * t), vec(0, 0, -1) end -- small wobble
local function circle(t) local a = t * 0.5; local r = 30; return vec(r * math.sin(a), 0, -r * (1 - math.cos(a))), vec(math.cos(a), 0, -math.sin(a)) end

local maxTurnAllowed = CFG.HeadingTurnDegPerSec * 0.4 + 0.5
for _, N in ipairs({ 5, 8, 20, 50 }) do
	local s = run(N, 8, straight)
	check(s.Rate <= 1 / 0.4 + 0.2, string.format("N=%d straight walk: %.2f MoveTo / soldier / s (at most one per 0.4 s think, never per frame)", N, s.Rate))
	check(s.Flips == 0 and s.MinGap >= 2.5, string.format("N=%d straight: no flips, soldiers never bunch (min gap %.1f)", N, s.MinGap))
	local st = run(N, 9, stopAfter)
	check(st.RestCmds == 0, string.format("N=%d sudden stop: nothing issued once settled (%d)", N, st.RestCmds))
	check(st.SideSwaps == 0, string.format("N=%d sudden stop: every seat on its own side at rest (%d swaps)", N, st.SideSwaps))
end
local t90 = run(8, 8, slow90)
check(t90.MaxTurnPerThink <= maxTurnAllowed and t90.Flips == 0, string.format("slow 90 turn: formation turns <= %.0f deg per think (max %.1f)", maxTurnAllowed, t90.MaxTurnPerThink))
local t180 = run(8, 8, fast180)
check(t180.Flips == 0 and t180.MaxTurnPerThink <= maxTurnAllowed, string.format("fast 180: no instant flip (max %.1f deg per think)", t180.MaxTurnPerThink))
local tb = run(8, 3, backwards)
check(tb.Flips == 0 and tb.MaxTurnPerThink < 1, string.format("walking backwards: the formation keeps its facing (max %.1f)", tb.MaxTurnPerThink))
local ts = run(8, 4, strafe)
check(ts.MaxTurnPerThink < 1 and ts.Flips == 0, string.format("strafe: the formation keeps its facing (max %.1f)", ts.MaxTurnPerThink))
local tz = run(8, 6, zigzag)
check(tz.MaxTurnPerThink < 1, string.format("small zig-zag: ignored by the heading deadzone (max %.1f)", tz.MaxTurnPerThink))
local tc = run(8, 10, circle)
check(tc.Flips == 0 and tc.MinGap >= 2, string.format("circles: no flip, no bunching (min gap %.1f)", tc.MinGap))
-- the owner-moving switch has hysteresis
check(FM.Moving(false, 2, CFG) == false and FM.Moving(true, 2, CFG) == true and FM.Moving(true, 1, CFG) == false, "move / stand switch hysteresis")
check(FM.State("InPosition", 2.5, CFG) == "InPosition" and FM.State(nil, 2.5, CFG) ~= "InPosition", "arrival deadzone hysteresis (no jitter at rest)")
print(fails == 0 and "ALL PASS" or ("FAILS " .. fails))
'''
    with _af_tf.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as _f:
        _f.write(_code)
        _tmp = _f.name
    _r = _af_sp.run([_af_luau, _tmp], capture_output=True, text=True, timeout=120)
    _af_os.unlink(_tmp)
    _out = (_r.stdout + _r.stderr).strip()
    for _ln in _out.splitlines():
        if _ln.startswith("FAIL "):
            bad("CLAUDE-BUD J22 sim: " + _ln[5:])
    (ok if "ALL PASS" in _out else bad)("CLAUDE-BUD J22: formation simulated (5/8/20/50 soldiers; walk, stop, 90, 180, backwards, strafe, zig-zag, circles) " + ("ALL PASS" if "ALL PASS" in _out else _out.replace("\n", " | ")[-400:]))
