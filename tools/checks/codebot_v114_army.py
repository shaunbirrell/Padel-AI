# v114 (Code Bot Roblox, 2026-09-29): army follow root cause 2 (docs/ARMY-FOLLOW-ROOTCAUSE-2.md).
# Static: every soldier MoveTo is in SoldierController, the one PivotTo is SoldierController.Reposition (emergency),
# collision groups (ArmyNPCs x ArmyNPCs / players = false), permanent slot assignment (no distance), Follow3 keys,
# the FOLLOW escort only aims. Executed (Luau CLI when found): FormationController over 100+ simulated owner moves /
# turns: persistent assignment, no two cells within 4 studs, nothing within 5 of the anchor, heading rate-limited,
# no flip walking backwards, deadband ignores small zig-zags.
import os as _v114_os
import re as _v114_re
import subprocess as _v114_sp
import tempfile as _v114_tf
from pathlib import Path as _V114P

if "ok" not in globals():
    _v114_fails = []

    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        _v114_fails.append(msg)
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _V114P(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None

_v114_SC = "src/ServerScriptService/Server/Modules/SoldierController.luau"
_v114_AC = "src/ServerScriptService/Server/Modules/ArmyController.luau"
_v114_AF = "src/ServerScriptService/Server/Modules/ArmyFollow.luau"
_v114_SOS = "src/ServerScriptService/Server/Services/SquadOrdersService.luau"
_v114_FC = "src/ReplicatedStorage/Shared/Util/FormationController.luau"
_v114_CFG = "src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau"
_v114_RA = "src/StarterPlayer/StarterPlayerScripts/Client/Modules/RigAnimator.luau"


def _v114_code(path):
    t = read(path) or ""
    out = []
    for l in t.splitlines():
        out.append(l.split("--", 1)[0])
    return "\n".join(out)


def _v114_fn(src, head):
    i = src.find(head)
    if i < 0:
        return ""
    j = src.find("\nend\n", i)
    return src[i:j + 5] if j > 0 else src[i:]


def _v114_check(cond, msg):
    (ok if cond else bad)("CODEBOT v114 army: " + msg)


_sc, _ac, _af, _sos, _fc = (_v114_code(p) for p in (_v114_SC, _v114_AC, _v114_AF, _v114_SOS, _v114_FC))
_v114_check(bool(_sc) and bool(_ac) and bool(_fc), "SoldierController / ArmyController / FormationController present")

# 1. MoveTo only in SoldierController
_v114_check(_sc.count(":MoveTo(") == 2 and "unit.Humanoid:MoveTo(goal)" in _sc and "unit.Humanoid:MoveTo(unit.Root.Position)" in _sc,
            f"SoldierController.Move / Stop are the only MoveTo ({_sc.count(':MoveTo(')})")
for _n, _t in (("ArmyFollow", _af), ("ArmyController", _ac), ("SquadOrdersService", _sos), ("FormationController", _fc)):
    _v114_check(_t.count(":MoveTo(") == 0, f"{_n} never calls Humanoid:MoveTo itself ({_t.count(':MoveTo(')})")
_v114_check("SoldierController.Move(unit, goal, state)" in _fn if (_fn := _v114_fn(_af, "function ArmyFollow.Command(")) else False,
            "ArmyFollow.Command (the v113 API HOLD / ATTACK / RETREAT use) forwards to SoldierController.Move")
# every other file that touches squad units never moves one
for _p in sorted(_V114P("src").rglob("*.luau")):
    _rel = _p.as_posix()
    if _rel in (_v114_SC,):
        continue
    _txt = _p.read_text(encoding="utf-8")
    if any(k in _txt for k in ("WarEmpireSquads", "WE_SquadUnit", "SquadOrdersService._AF", "unit.Humanoid")) and _rel.endswith(("SquadOrdersService.luau", "ArmyFollow.luau", "ArmyController.luau")):
        _c = _v114_code(_rel)
        if _v114_re.search(r"\bunit\.Humanoid:MoveTo\(|\bu\.Humanoid:MoveTo\(", _c):
            bad(f"CODEBOT v114 army: {_rel} moves a squad unit directly")

# 2. PivotTo / CFrame writes: only SoldierController.Reposition (emergency); spawn creation excluded
_rep = _v114_fn(_sc, "function SoldierController.Reposition(")
_v114_check(_sc.count("PivotTo(") == 1 and "unit.Model:PivotTo(cf)" in _rep, "the one PivotTo on a soldier is SoldierController.Reposition")
for _n, _t in (("ArmyFollow", _af), ("ArmyController", _ac), ("FormationController", _fc)):
    _v114_check("PivotTo(" not in _t and "SetPrimaryPartCFrame" not in _t and not _v114_re.search(r"Root\.CFrame\s*=", _t) and "AssemblyLinearVelocity =" not in _t,
                f"{_n}: no PivotTo / root CFrame / velocity writes")
_sos_nospawn = _sos.replace(_v114_fn(_sos, "local function spawnUnit("), "")
_v114_check("PivotTo(" not in _sos_nospawn and "SetPrimaryPartCFrame" not in _sos_nospawn and not _v114_re.search(r"\broot\.CFrame\s*=|Root\.CFrame\s*=", _sos_nospawn),
            "SquadOrdersService: no PivotTo / root CFrame writes outside spawnUnit (recover / pace-recover -> SoldierController.Reposition)")
_v114_check(not _v114_re.search(r"Heartbeat|RenderStepped|\.Stepped", _sc + _ac + _fc), "no per-frame loops in the controllers")
_drive = _v114_fn(_sc, "function SoldierController.Drive(")
_v114_check("Reposition(unit, spot, \"stuck\")" in _drive and "StuckRepositionSeconds" in _drive and "OutOfView" in _drive and "FarSeconds" in _drive,
            "Drive repositions only as the emergency (void / far for seconds / stuck 10 s far + out of view)")
_v114_check(all(k in _drive for k in ("StuckReissueSeconds", "StuckPathSeconds", "StuckAltSeconds", "StuckProgressStuds")),
            "staged stuck: re-issue -> path -> side point -> reposition, by progress over time")

# 3. collision groups
_afr = read(_v114_AF) or ""
_v114_check("PhysicsService:CollisionGroupSetCollidable(ArmyFollow.Group, ArmyFollow.Group, false)" in _afr, "ArmyNPCs x ArmyNPCs = false")
_v114_check("PhysicsService:CollisionGroupSetCollidable(ArmyFollow.Group, ArmyFollow.PlayerGroup, cfg().CollideWithPlayers == true and not follow3On())" in _afr,
            "ArmyNPCs x WE_PlayerChars (players) = false under Follow3")
_v114_check('PhysicsService:CollisionGroupSetCollidable(ArmyFollow.Group, "Default", true)' in _afr, "ArmyNPCs still collide with Default (world / floor / walls)")
_v114_check("if playersHooked or not (stableOn() or follow3On()) then" in _afr and "char.DescendantAdded:Connect(function(d)" in _afr,
            "every player character part (late ones too) joins WE_PlayerChars")
_v114_check("unit.Model.DescendantAdded:Connect(function(d)" in _afr and "d.CollisionGroup = ArmyFollow.Group" in _afr, "every soldier part (late rig parts / accessories) joins ArmyNPCs")
_v114_check("d.CollisionGroup ~= group then" in _ac and "AuditSeconds" in _ac, "ArmyController re-audits every unit part's group")

# 4. permanent assignment, no nearest re-pick, no side flip
_asg = _v114_fn(_fc, "function FormationController.Assign(")
_v114_check(_asg != "" and not any(k in _asg for k in ("Magnitude", "Position", "Dist", "Dot(")), "slot assignment never uses distance (no nearest-soldier re-pick)")
_v114_check("s.ByUnit[u] == nil then" in _asg and "s.Taken[pref] == nil" in _asg and "while s.Taken[idx] ~= nil do" in _asg, "a slot is assigned once per unit (fill holes only)")
_v114_check("_afFlip" not in _ac + _sc + _fc and "compactSeats" not in _ac + _sc + _fc, "no row side flipping / seat compaction in the Follow3 controller")
_v114_check("FormationController.Assign(a.Assign, living)" in _ac and "a.Assign.ByUnit[u]" in _ac, "ArmyController places units by their permanent index")

# 5. one controller in FOLLOW: the escort only aims
_tu = _v114_fn(_sos, "local function thinkUnit(")
_i3, _iaf = _tu.find("SquadOrdersService._AC.LiveFor(player.UserId)"), _tu.find("SquadOrdersService._AF.Unit(player, st, unit, playerRoot, now)")
_v114_check(0 <= _i3 < _iaf and "escortAimOnly = true" in _tu[_i3:_iaf] and "return" in _tu[_i3:_iaf], "Follow3 FOLLOW: the SOS think only shoots / aims (then returns; no ArmyFollow.Unit, no escort walk)")
_eu = _v114_fn(_sos, "local function escortUnit(")
_ia, _iw = _eu.find("if escortAimOnly then"), _eu.find("if walkForm then\n")
_v114_check(0 <= _ia < _iw and "SquadOrdersService._AF.Command" not in _eu[_ia:_iw], "escortUnit aim-only returns before any walk")
_v114_check("if escortAimOnly then" in _v114_fn(_sos, "local function stepBlocked("), "no side-step planning in Follow3 FOLLOW")
_v114_check("SquadOrdersService._AC.Start({" in _sos, "SquadOrdersService starts the ArmyController tick")
_v114_check(":Destroy(" not in _ac + _sc + _fc and ":Clone(" not in _ac + _sc + _fc, "controllers never destroy / clone a soldier")

# 6. config keys
_cfg = read(_v114_CFG) or ""
_f3i = _cfg.find("\tFollow3 = {")
_f3 = _cfg[_f3i:_cfg.find("\n\t},", _f3i)] if _f3i >= 0 else ""
_keys = ["Enabled", "Rollout", "UpdateSeconds", "VelSmoothSeconds", "AnchorLagSeconds", "AnchorLeadSeconds", "AnchorLeadMaxStuds",
         "MovingOnSpeed", "MovingOffSpeed", "HeadingTurnDegPerSec", "HeadingDeadbandDeg", "HeadingHoldSeconds", "FacingAgreeDeg",
         "ReverseDeg", "ReverseHoldSeconds", "StandAlignDeg", "StandAlignSeconds", "Formation", "LateralStuds", "ColSpacing", "RowSpacing",
         "FrontBack", "OwnerClearStuds", "EscortLayout", "ArriveStuds", "LeaveStuds", "ReissueStuds", "RefreshSeconds", "MoveLeadSeconds",
         "MoveLeadMaxStuds", "CatchUpPerStud", "CatchUpMaxMult", "CatchUpMin", "MaxSpeed", "MinSpeed", "SpeedUpPerTick", "SpeedDownPerTick",
         "FaceTurnDegPerSec", "FaceAfterShotSeconds", "StuckProgressStuds", "StuckReissueSeconds", "StuckPathSeconds", "StuckAltSeconds",
         "StuckRepositionSeconds", "StuckRepositionMinStuds", "FarStuds", "FarSeconds", "OwnerJumpSpeed", "RepositionBehindStuds", "AuditSeconds"]
_miss = [k for k in _keys if not _v114_re.search(r"\n\t\t" + k + r" = ", _f3)]
_v114_check(_f3 != "" and not _miss, f"ArmyConfig.Follow3 has every tunable (missing {_miss})")
_v114_check("\t\tEnabled = true," in _f3 and '\t\tRollout = "all",' in _f3 and '\t\tFormation = "Flank",' in _f3, "Follow3 live for all, Flank default (Enabled = false = v113)")


def _v114_n(k, d):
    m = _v114_re.search(r"\n\t\t" + k + r" = (-?[\d.]+)", _f3)
    return float(m.group(1)) if m else d


_v114_check(90 <= _v114_n("HeadingTurnDegPerSec", 0) <= 120 and 15 <= _v114_n("HeadingDeadbandDeg", 0) <= 20, "heading 90-120 deg/s, deadband 15-20 deg")
_v114_check(5 <= _v114_n("ColSpacing", 0) <= 6 and 5 <= _v114_n("RowSpacing", 0) <= 6 and _v114_n("LateralStuds", 0) >= 5 and _v114_n("OwnerClearStuds", 0) >= 5,
            "grid 5-6 studs, nothing within 5 studs of him")
_v114_check(0.15 <= _v114_n("UpdateSeconds", 0) <= 0.25 and 2 <= _v114_n("ReissueStuds", 0) <= 3 and 2 <= _v114_n("ArriveStuds", 0) <= 3 < _v114_n("LeaveStuds", 0),
            "tick 0.15-0.25 s, reissue 2-3 studs, arrival 2-3 studs with hysteresis")
_v114_check(_v114_n("FarStuds", 0) >= 120 and _v114_n("StuckRepositionSeconds", 0) >= 8, "reposition only >= 120 studs / >= 8 s stuck")
_ra = read(_v114_RA) or ""
_v114_check('host:GetAttribute("WE_FormYaw")' in _ra and "L.Joint.C0 = CFrame.new(lo) * ROOT_ROT" in _ra, "client escorts laid out in the formation row (no rigid file swinging with unit yaw)")
_v114_check("PreferMesh = true" not in (read("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau") or ""), "PreferMesh stays OFF")
for _rel in ("src/ServerScriptService/Server/Services/DataService.luau", "src/ServerScriptService/Server/Services/BaseService.luau", "src/ServerScriptService/Server/EarlyRemotes.server.luau"):
    _v114_check('SetAttribute("WE_Build", 114)' in (read(_rel) or ""), "WE_Build=114 " + _rel.rsplit("/", 1)[-1])
_v114_check("WE_Build=114" in (read("src/ServerScriptService/Server/Services/DataService.luau") or ""), "DataService log WE_Build=114")

# 7. FormationController executed in the Luau CLI
_luau = _v114_os.environ.get("LUAU")
if not _luau:
    for _cand in ([_v114_os.path.join(_v114_os.path.dirname(_v114_os.environ["LUAU_COMPILE"]), "luau")] if _v114_os.environ.get("LUAU_COMPILE") else []) + [_v114_os.path.expanduser("~/.local/bin/luau")]:
        if _v114_os.path.exists(_cand):
            _luau = _cand
            break
if _luau:
    _vals = {}
    for _k in _keys:
        _m = _v114_re.search(r"\n\t\t" + _k + r" = (-?[\d.]+|true|false|\"\w+\")", _f3)
        if _m:
            _vals[_k] = _m.group(1)
    _cfg_lua = "{ " + ", ".join(f"{k} = {v}" for k, v in _vals.items()) + " }"
    _code = r'''
local V = {}
local function vec(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, V) end
V.__add = function(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V.__sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V.__unm = function(a) return vec(-a.X, -a.Y, -a.Z) end
V.__mul = function(a, b) if type(a) == "number" then return vec(b.X * a, b.Y * a, b.Z * a) end return vec(a.X * b, a.Y * b, a.Z * b) end
V.__div = function(a, b) return vec(a.X / b, a.Y / b, a.Z / b) end
local M = {}
function M.Lerp(a, b, k) return a + (b - a) * k end
function M.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
V.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
	if k == "Unit" then local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z); return vec(t.X / m, t.Y / m, t.Z / m) end
	return M[k]
end
Vector3 = { new = vec, zero = vec(0, 0, 0) }
local CF = {}
CF.__index = CF
function CF.PointToWorldSpace(c, v)
	local l = c.Look
	local right = vec(-l.Z, 0, l.X)
	return c.P + right * v.X + vec(0, 1, 0) * v.Y - l * v.Z
end
CFrame = { lookAt = function(p, t) local d = t - p; d = vec(d.X, 0, d.Z); return setmetatable({ P = p, Look = d.Unit }, CF) end }
function typeof(v) return type(v) end
local FC = (function()
''' + (read(_v114_FC) or "") + r'''
end)()
local CFG = ''' + _cfg_lua + r'''
local fails = 0
local function check(okv, label) print((okv and "PASS " or "FAIL ") .. label); if not okv then fails += 1 end end
local function flat(v) return vec(v.X, 0, v.Z) end

-- units: tables with Slot (SquadSlot)
local units = {}
for i = 1, 8 do units[i] = { Slot = i, Id = "u" .. i } end
local asg = FC.NewAssignment()
FC.Assign(asg, units)
local first = {}
for _, u in ipairs(units) do first[u] = asg.ByUnit[u] end
local a = FC.NewAnchor()
local dt, t = 0.2, 0
local pos, look = vec(0, 0, 0), vec(0, 0, -1)
local rate = math.rad(CFG.HeadingTurnDegPerSec) * dt + 1e-6
local maxStep, minGap, minOwner, persistOk, flips = 0, math.huge, math.huge, true, 0
local recruit = { Slot = 3, Id = "r" }
-- owner script: 100+ steps of walking, turning, sprinting, circling, stopping, zig-zags, backing up
local function ownerAt(step)
	if step <= 20 then return vec(0, 0, -16), vec(0, 0, -1) end -- north, 16 studs/s
	if step <= 35 then local r = math.rad((step - 20) * 6); local d = vec(math.sin(-r), 0, -math.cos(r)); return d * 20, d end -- sweeping turn, sprint
	if step <= 50 then local d = vec(-1, 0, 0); return d * 16, d end
	if step <= 60 then return vec(0, 0, 0), vec(-1, 0, 0) end -- stop
	if step <= 75 then local d = vec(1, 0, 0); return d * 18, d end -- about-turn and run
	if step <= 90 then local z = if step % 2 == 0 then 0.17 else -0.17; local d = vec(1, 0, z).Unit; return d * 16, d end -- +-10 deg zig-zag
	if step <= 105 then return vec(-12, 0, 0), vec(1, 0, 0) end -- walking backwards (facing +X, moving -X)
	local r = math.rad((step - 105) * 12); local d = vec(math.cos(r), 0, math.sin(r)); return d * 14, d -- circle
end
local zigDir, backDir = nil, nil
local zigMax, backMax = 0, 0
for step = 1, 130 do
	local v, lk = ownerAt(step)
	pos = pos + v * dt
	t += dt
	local before = a.Dir
	FC.Step(a, pos, lk, v, dt, t, false, CFG)
	if before then
		local d = math.abs(FC.Angle(before, a.Dir))
		maxStep = math.max(maxStep, d)
		if d > math.rad(150) then flips += 1 end
	end
	if step == 80 then zigDir = a.Dir end
	if step > 80 and step <= 90 and zigDir then zigMax = math.max(zigMax, math.abs(FC.Angle(zigDir, a.Dir))) end
	if step == 91 then backDir = a.Dir end
	if step > 91 and step <= 105 and backDir then backMax = math.max(backMax, math.abs(FC.Angle(backDir, a.Dir))) end
	-- roster: unit 3 dies at step 40, a recruit (SquadSlot 3) arrives at step 60
	if step == 40 then table.remove(units, 3) end
	if step == 60 then table.insert(units, recruit) end
	FC.Assign(asg, units)
	for _, u in ipairs(units) do
		if u ~= recruit and asg.ByUnit[u] ~= first[u] then persistOk = false end
	end
	-- every cell (units + 3 escorts each) apart; nothing near the anchor
	local cells = {}
	for _, u in ipairs(units) do
		for e = 0, 3 do
			local lat, back = FC.SlotLocal(asg.ByUnit[u], CFG, e)
			table.insert(cells, FC.SlotWorld(a, lat, back, 0))
		end
	end
	for i = 1, #cells do
		minOwner = math.min(minOwner, (flat(cells[i]) - flat(a.Pos)).Magnitude)
		for j = i + 1, #cells do
			minGap = math.min(minGap, (flat(cells[i]) - flat(cells[j])).Magnitude)
		end
	end
end
check(persistOk, "survivors keep their slot index across 130 owner moves / turns and a death + a recruit")
check(asg.ByUnit[recruit] == 3, "the recruit fills the dead unit's hole (index " .. tostring(asg.ByUnit[recruit]) .. ")")
check(minGap >= 4, string.format("no two formation cells within 4 studs (min %.2f)", minGap))
check(minOwner >= 5, string.format("nothing within 5 studs of the anchor (min %.2f)", minOwner))
check(maxStep <= rate, string.format("heading turn per tick <= %.1f deg (max %.1f)", math.deg(rate), math.deg(maxStep)))
check(flips == 0, "no heading flip")
check(zigMax < math.rad(1), string.format("+-10 deg zig-zags inside the deadband do not rotate it (%.1f deg)", math.deg(zigMax)))
check(backMax < math.rad(5), string.format("walking backwards does not flip it (%.1f deg)", math.deg(backMax)))
-- the grid itself: unit rows beside / behind him
local lat1, back1 = FC.SlotLocal(1, CFG)
local lat2 = FC.SlotLocal(2, CFG)
check(lat1 < 0 and lat2 > 0 and math.abs(lat1) >= 5 and back1 <= 0, "slot 1 on his left, slot 2 on his right, front row beside him")
-- anchor smoothing: a raw 3-stud jitter of his position moves the anchor < 1.5 studs in one tick
local a2 = FC.NewAnchor()
FC.Step(a2, vec(0, 0, 0), vec(0, 0, -1), vec(0, 0, 0), 0.2, 0, false, CFG)
for i = 1, 10 do FC.Step(a2, vec(0, 0, 0), vec(0, 0, -1), vec(0, 0, 0), 0.2, i * 0.2, false, CFG) end
local p0 = a2.Pos
FC.Step(a2, vec(3, 0, 0), vec(0, 0, -1), vec(0, 0, 0), 0.2, 3, false, CFG)
check((a2.Pos - p0).Magnitude < 1.6 and (a2.Pos - p0).Magnitude > 0, string.format("the anchor follows a raw jump smoothly (%.2f of 3 studs in one tick)", (a2.Pos - p0).Magnitude))
'''
    # 8. SoldierController.Drive + FormationController together (mock humanoids walking at WalkSpeed, 20 Hz physics)
    _sc_src = (read(_v114_SC) or "")
    _sc_body = _sc_src[_sc_src.find("local SoldierController = {}"):]
    _code += r"""
do
	local CFM = {}
	CFM.__index = function(c, k) if k == "LookVector" then return c.Look end if k == "Position" then return c.P end return CF[k] end
	CFrame.lookAt = function(p, t) local d = t - p; d = vec(d.X, 0, d.Z); return setmetatable({ P = p, Look = d.Unit }, CFM) end
	local ArmyConfig = { Follow3 = CFG }
	local Workspace = { FallenPartsDestroyHeight = -500 }
	local PathfindingService = {}
	local SC = (function()
""" + _sc_body.replace("return SoldierController", "return SoldierController", 1) + r"""
	end)()
	local pivots, moves = 0, 0
	local function mkUnit(i, p)
		local u = { Id = "s" .. i, Slot = i, Alive = true, LastFireAt = -1e9, OwnerUserId = 1 }
		local gyro = { MaxTorque = vec(0, 4e5, 0), CFrame = CFrame.lookAt(vec(0,0,0), vec(0,0,-1)) }
		function gyro:IsA(c) return c == "BodyGyro" end
		u.Root = { Position = p, CFrame = CFrame.lookAt(p, p + vec(0,0,-1)), Parent = true }
		function u.Root:FindFirstChild(n) return if n == "NPCFaceGyro" then gyro else nil end
		u.Humanoid = { WalkSpeed = 14, AutoRotate = true, Jump = false, Target = nil }
		function u.Humanoid:MoveTo(g) moves += 1; u.Cmds = (u.Cmds or 0) + 1; self.Target = g end
		u.Model = {}
		function u.Model:SetAttribute() end
		function u.Model:PivotTo(cf) pivots += 1 end
		return u
	end
	local N = 8
	local units, asg, a = {}, FC.NewAssignment(), FC.NewAnchor()
	for i = 1, N do
		local lat, back = FC.SlotLocal(i, CFG)
		units[i] = mkUnit(i, vec(lat, 0, back))
	end
	FC.Assign(asg, units)
	local pos, t, dt, tick = vec(0, 0, 0), 0, 0.05, 0.2
	local nextTick = 0
	local restMoves, maxSettle, minGapMove, ownerMin, snaps = 0, 0, math.huge, math.huge, 0
	local ownerMinAt = ""
	local minGapAll = math.huge
	local function ownerVel(tt)
		if tt < 6 then return vec(0, 0, -16), vec(0, 0, -1) end
		if tt < 9 then local r = math.rad((tt - 6) * 30); local d = vec(-math.sin(r), 0, -math.cos(r)); return d * 16, d end
		if tt < 14 then return vec(0, 0, 0), vec(-1, 0, 0) end
		if tt < 18 then return vec(16, 0, 0), vec(1, 0, 0) end
		return vec(0, 0, 0), vec(1, 0, 0)
	end
	local lastPos = pos
	while t < 24 do
		local v, lk = ownerVel(t)
		pos = pos + v * dt
		if t >= nextTick - 1e-9 then
			local vm = (pos - lastPos) / tick
			lastPos = pos
			FC.Step(a, pos, lk, vec(vm.X, 0, vm.Z), tick, t, false, CFG)
			local lead = FC.MoveLead(a, CFG)
			for _, u in ipairs(units) do
				local lat, back = FC.SlotLocal(asg.ByUnit[u], CFG)
				SC.Drive(u, { Goal = FC.SlotWorld(a, lat, back, 0), Heading = a.Dir, Lead = lead, OwnerPos = pos, OwnerMoving = a.Moving,
					Pace = a.Vel.Magnitude, BaseSpeed = 14, Dt = tick, Now = t, AllowRecover = true, OwnerClear = CFG.OwnerClearStuds, Pivot = a.Pos,
					Spot = function() return CFrame.lookAt(pos, pos + vec(0,0,-1)) end, OutOfView = function() return true end })
				if (t > 12.5 and t < 14) or t > 21 then
					maxSettle = math.max(maxSettle, (flat(u.Root.Position) - flat(FC.SlotWorld(a, lat, back, 0))).Magnitude)
				end
			end
			nextTick += tick
		end
		for _, u in ipairs(units) do
			local g = u.Humanoid.Target
			if g then
				local off = flat(g - u.Root.Position)
				local m = off.Magnitude
				if m > 0.05 then
					local step = math.min(m, u.Humanoid.WalkSpeed * dt)
					local np = u.Root.Position + off.Unit * step
					if (np - u.Root.Position).Magnitude > 6 then snaps += 1 end
					u.Root.Position = np
					u.Root.CFrame = CFrame.lookAt(np, np + off.Unit)
				else
					u.Humanoid.Target = nil
				end
			end
			local od = (flat(u.Root.Position) - flat(pos)).Magnitude
			if od < ownerMin then ownerMin = od; ownerMinAt = string.format("t=%.2f unit %s", t, u.Id) end
		end
		if t > 3 then
			for i = 1, N do for j = i + 1, N do
				local gg = (flat(units[i].Root.Position) - flat(units[j].Root.Position)).Magnitude
				minGapAll = math.min(minGapAll, gg)
				if t < 6 then minGapMove = math.min(minGapMove, gg) end
			end end
		end
		t += dt
	end
	local perSec = moves / N / 24
	check(pivots == 0, "drive sim: no PivotTo during normal movement (" .. pivots .. ")")
	check(snaps == 0, "drive sim: no unit jumps > 6 studs in one physics step")
	check(perSec <= 5.01, string.format("drive sim: MoveTo <= 5 per unit per second (%.2f)", perSec))
	check(maxSettle <= 4, string.format("drive sim: units settle in their own slot when he stops (max %.2f studs)", maxSettle))
	check(minGapMove >= 4, string.format("drive sim: units stay apart while marching (min %.2f studs)", minGapMove))
	check(minGapAll >= 1.5, string.format("drive sim: no two units on top of each other through turns / a U-turn / stops (min %.2f studs)", minGapAll))
	check(ownerMin >= 3, string.format("drive sim: nobody walks through him (min %.2f studs %s)", ownerMin, ownerMinAt))
	local restBefore = moves
	-- 4 more seconds standing: nothing issued
	for k = 1, 20 do
		t += tick
		FC.Step(a, pos, vec(1, 0, 0), vec(0, 0, 0), tick, t, false, CFG)
		for _, u in ipairs(units) do
			local lat, back = FC.SlotLocal(asg.ByUnit[u], CFG)
			SC.Drive(u, { Goal = FC.SlotWorld(a, lat, back, 0), Heading = a.Dir, Lead = vec(0,0,0), OwnerPos = pos, OwnerMoving = false,
				Pace = 0, BaseSpeed = 14, Dt = tick, Now = t, AllowRecover = true, OwnerClear = CFG.OwnerClearStuds })
		end
	end
	check(moves == restBefore, "drive sim: no MoveTo while he stands and they are in their slots (" .. (moves - restBefore) .. ")")
end
print("FAILS " .. fails)
"""
    with _v114_tf.NamedTemporaryFile("w", suffix=".luau", delete=False) as _fh:
        _fh.write(_code)
        _tmp = _fh.name
    try:
        _r = _v114_sp.run([_luau, _tmp], capture_output=True, text=True, timeout=60)
        _out = (_r.stdout or "") + (_r.stderr or "")
        for _line in _out.splitlines():
            if _line.startswith("PASS "):
                ok("CODEBOT v114 army sim: " + _line[5:])
            elif _line.startswith("FAIL "):
                bad("CODEBOT v114 army sim: " + _line[5:])
        if "FAILS 0" not in _out:
            bad("CODEBOT v114 army sim: FormationController simulation did not finish clean: " + _out[-400:])
    finally:
        _v114_os.unlink(_tmp)
else:
    ok("CODEBOT v114 army sim: skipped (no luau CLI found)")

if "_v114_fails" in globals() and __name__ == "__main__":
    import sys as _v114_sys
    print(("PASS" if not _v114_fails else "FAIL") + f" v114 army ({len(_v114_fails)} failing)")
    _v114_sys.exit(1 if _v114_fails else 0)
