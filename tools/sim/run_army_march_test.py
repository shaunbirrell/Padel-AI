"""Code Bot v145 (owner: "Sending my army to a location they don't go and attack"): the REAL code path of an army
order from the server's SEND / ATTACK / RECALL entry points to the soldiers' feet, in the Luau CLI:
ArmyPlan (StartSend / StartClear / Recall / Think) + ArmyRoute + ArmyController.stepArmy (the steered block, PlanLead)
+ Shared/Util/FormationController + SoldierController.Drive + the real ArmyConfig.Follow3 / ArmyOrdersConfig, on mock
humanoids that walk to their MoveTo point at their WalkSpeed (no collisions, flat ground). Stand-ins: ArmyFollow's base
state (his 320-stud plot, the gate hold cells), the services, and PathfindingService: an end point inside a walled plot
with a closed gate returns no path (live-probed on synthetic walls in an Open Cloud Luau session on place 142).
Scenarios (each fails on v144): 1. SEND from inside his walled base (the army waits at his gate); 2. SEND with a leg end
of the straight line inside another walled plot; 3. SEND with 8 units + 12 escorts (a block deeper than LeadMaxGap);
4. RECALL while he stands inside his base; 5. ATTACK auto-clear from inside his base. Checked: the army reaches the
target (SIEGE / FIGHT), no "No route" toast, no teleport (PivotTo), never walks backwards, the block stays together.
Run: LUAU=path/to/luau python3 tools/sim/run_army_march_test.py   (exit 1 on any failure)"""
import os, subprocess, sys, tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/sim"))
from run_kit_detail_test import PRELUDE
SH = ROOT / "src/ReplicatedStorage/Shared"; SV = ROOT / "src/ServerScriptService/Server"
MODS = {
 "Configs/ArmyOrdersConfig": SH/"Configs/ArmyOrdersConfig.luau", "Configs/RetentionConfig": SH/"Configs/RetentionConfig.luau",
 "Configs/AdminConfig": SH/"Configs/AdminConfig.luau", "Configs/RaidConfig": SH/"Configs/RaidConfig.luau",
 "Configs/ArmyConfig": SH/"Configs/ArmyConfig.luau", "Util/FormationController": SH/"Util/FormationController.luau",
 "Modules/ArmySendRules": SV/"Modules/ArmySendRules.luau", "Modules/ArmyRoute": SV/"Modules/ArmyRoute.luau",
 "Modules/ArmyPlan": SV/"Modules/ArmyPlan.luau", "Modules/ArmyController": SV/"Modules/ArmyController.luau",
 "Modules/SoldierController": SV/"Modules/SoldierController.luau",
 "Configs/GameConfig": "return { PvPEnabled = true }",
 "Modules/Enterables": "return { At = function() return nil end }",
 "Modules/ArmyFollow": r'''
local AF = { Group = "ArmyNPCs" }
function AF.LiveFor() return true end
function AF.ClearLine() return true end
function AF.RefreshRayFilter() end
function AF.GroundAt(p) return p end
function AF.BaseState(st, player, pos, now)
  -- his own plot: a square of half 160 centred at HOMEPLOT (nil = no base in the sim)
  local inside = HOMEPLOT ~= nil and math.abs(pos.X - HOMEPLOT.X) <= 160 + (if st._afInBase then 10 else 6) and math.abs(pos.Z - HOMEPLOT.Z) <= 160 + (if st._afInBase then 10 else 6)
  st._afTidy = true; st._afOwnPlot = if HOMEPLOT then 1 else nil
  if st._afInBase and not inside then st._afLeftBaseAt = now end
  st._afInBase = inside
  return inside, if inside then 1 else nil
end
function AF.HoldSpot(plotId, idx) -- gate cells outside +X edge of the plot, facing out
  local side = if idx % 2 == 1 then -1 else 1
  local j = (idx - 1) // 2
  return Vector3.new(HOMEPLOT.X + 160 + 14 + (j // 4) * 4, 0, HOMEPLOT.Z + side * (12 + (j % 4) * 4)), Vector3.new(1, 0, 0)
end
function AF.InPlot(plotId, p, pad) return HOMEPLOT ~= nil and math.abs(p.X - HOMEPLOT.X) <= 160 + pad and math.abs(p.Z - HOMEPLOT.Z) <= 160 + pad end
function AF.HoldVia(plotId, upos, goal) return goal end
return AF
''',
}
from army_cmd_mods import army_cmd_mods  # Code Bot army command: ArmyState / ArmyTargets / ArmyCommand + configs
MODS = {**army_cmd_mods(), **MODS}
EXTRA = r'''
NOW = 1000
task = { spawn = function(fn, ...) fn(...) end, wait = function(s) NOW += (s or 0) end, delay = function() end, defer = function(fn, ...) fn(...) end }
Vector2 = { new = function(x, y) return { X = x, Y = y, Magnitude = math.sqrt(x * x + y * y) } end }
CFrame.lookAt = function(at, target)
  local d = target - at; local l = Vector3.new(d.X, d.Y, d.Z)
  local m = l.Magnitude; if m < 1e-9 then l = Vector3.new(0, 0, -1) else l = l / m end
  local up = Vector3.new(0, 1, 0)
  local rx, ry, rz = l.Y * up.Z - l.Z * up.Y, l.Z * up.X - l.X * up.Z, l.X * up.Y - l.Y * up.X -- look x up = right
  local rm = math.sqrt(rx * rx + ry * ry + rz * rz); if rm < 1e-9 then rx, ry, rz = 1, 0, 0 else rx, ry, rz = rx / rm, ry / rm, rz / rm end
  local ux, uy, uz = ry * (-l.Z) - rz * (-l.Y), rz * (-l.X) - rx * (-l.Z), rx * (-l.Y) - ry * (-l.X) -- right x back = up
  return CFrame.new(at.X, at.Y, at.Z, rx, ux, -l.X, ry, uy, -l.Y, rz, uz, -l.Z)
end
local function signal() local s = { fns = {} }; s.Connect = function(self, fn) table.insert(self.fns, fn); return { Disconnect = function() end } end; return s end
PLAYERS = {}
local Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return PLAYERS end,
  GetPlayerByUserId = function(_, id) for _, p in ipairs(PLAYERS) do if p.UserId == id then return p end end return nil end }
local RunService = { IsStudio = function() return false end }
local Workspace = { FallenPartsDestroyHeight = -500 }
local prevGame = game
game = { GetService = function(_, n)
  if n == "Players" then return Players elseif n == "RunService" then return RunService elseif n == "Workspace" then return Workspace end
  return prevGame:GetService(n) end }
UNIX = 50000
os = setmetatable({ time = function() return UNIX end, clock = function() return NOW end }, { __index = os })
function mkPlayer(uid, name, at)
  local root = { Position = at, IsA = function(_, c) return c == "BasePart" end, Parent = true, AssemblyLinearVelocity = Vector3.zero }
  root.CFrame = CFrame.lookAt(at, at + Vector3.new(1, 0, 0))
  local hum = { Health = 100, Sit = false }
  local char = { FindFirstChild = function(_, n) if n == "HumanoidRootPart" then return root end end, FindFirstChildOfClass = function() return hum end }
  root.Parent = char
  local attrs = {}
  local p = { UserId = uid, Name = name, DisplayName = name, Parent = true, Character = char, _root = root, _hum = hum,
    GetAttribute = function(_, k) return attrs[k] end, SetAttribute = function(_, k, v) attrs[k] = v end }
  p.IsA = function(_, c) return c == "Player" end
  return p
end
function mkUnit(i, at)
  local u = { Alive = true, Slot = i, Id = i }
  local root = { Position = at, Parent = true, AssemblyLinearVelocity = Vector3.zero, FindFirstChild = function() return nil end }
  root.CFrame = CFrame.lookAt(at, at + Vector3.new(1, 0, 0))
  local hum = { Health = 150, WalkSpeed = 14, AutoRotate = true, Jump = false }
  hum.MoveTo = function(_, p) u._target = p end
  local attrs = {}
  local model = { Parent = true, GetAttribute = function(_, k) return attrs[k] end, SetAttribute = function(_, k, v) attrs[k] = v end,
    GetDescendants = function() return {} end, PivotTo = function(_, cf) u.Root.Position = cf.Position; TELEPORTS += 1 end }
  root.Parent = model
  u.Root, u.Humanoid, u.Model = root, hum, model
  return u
end
TELEPORTS = 0
COMPUTE_FAIL = 0
function stepUnits(units, dt)
  for _, u in ipairs(units) do
    local t = u._target
    if t then
      local d = Vector3.new(t.X - u.Root.Position.X, 0, t.Z - u.Root.Position.Z)
      local m = d.Magnitude
      local s = u.Humanoid.WalkSpeed * dt
      if m > 1e-3 then
        local mv = if m <= s then d else d / m * s
        u.Root.Position = u.Root.Position + mv
        u.Root.CFrame = CFrame.lookAt(u.Root.Position, u.Root.Position + d)
      end
    end
  end
end
LOG = { notify = {} }
PROFILES = {}; OWNERS = {}
SIEGE = { GatePart = { Position = Vector3.new(600, 3, 0), Parent = true }, GateHp = 800, GateMax = 800, Breached = false, Turrets = {},
  CollectorPos = Vector3.new(560, 3, 0), GuardPower = {}, TurretPower = {} }
GATE = CFrame.new(600, 0, 0)
DEPS = {
  DataService = { GetProfile = function(p) return PROFILES[p.UserId] end, MarkDirty = function() end },
  NotificationService = { Notify = function(p, t) table.insert(LOG.notify, { p = p.Name, t = t }) end },
  SquadOrdersService = { Push = function() end, UnitPower = function() return 20, 150, 20 end, SetOrder = function() end },
  BaseService = { GetOwnerUserId = function(plot) return OWNERS[plot] end },
  GateDefenseService = { SiegeInfo = function() return SIEGE end, GetGateCFrame = function(plot) if plot == 1 and HOMEPLOT then local g = HOMEPLOT + Vector3.new(160, 0, 0); return CFrame.lookAt(g, g - Vector3.new(1, 0, 0)) end return GATE end, IsAlly = function() return false end },
  CombatService = { IsNoviceShielded = function() return false end, UnitMayHitPlayer = function() return true end,
    NPCGroupOf = function() return "Garrison.RidgeCamp" end,
    GroupNPCs = function() local out = {}; for i = 1, CAMPN do table.insert(out, { Position = CAMP }) end; return out end },
  MoneyCollectorService = { CanArmyRaid = function() return true end, ArmyRaid = function() return 0 end },
}
'''
TEST = r'''
local AP = require(node("Modules/ArmyPlan"))
local AC = require(node("Modules/ArmyController"))
local Route = require(node("Modules/ArmyRoute"))
-- a straight, open route on flat ground (waypoints at ground height, as PathfindingService returns them)
local function inSq(c, p) return c ~= nil and math.abs(p.X - c.X) < 160 and math.abs(p.Z - c.Z) < 160 end
Route._SetComputer(function(a, b)
  -- PathfindingService (live-probed on synthetic walls): an end point inside a walled plot with a closed gate = NoPath
  if inSq(HOMEPLOT, a) or inSq(HOMEPLOT, b) or inSq(MIDPLOT, a) or inSq(MIDPLOT, b) then COMPUTE_FAIL += 1; return nil end
  local out = {}; local d = b - a; local n = math.max(1, math.ceil(Vector3.new(d.X, 0, d.Z).Magnitude / 8))
  for i = 1, n do local p = a + d * (i / n); table.insert(out, Vector3.new(p.X, 0, p.Z)) end
  return out end)
local N = tonumber(NUNITS)
local owner = mkPlayer(470626172, "shaunie6", OWNERAT)
local victim = mkPlayer(77, "rival", Vector3.new(700, 3, 0))
PLAYERS = { owner, victim }
PROFILES[owner.UserId] = { Raid = {}, FirstJoinUnix = 1, BasePlotId = if HOMEPLOT then 1 else nil }
PROFILES[victim.UserId] = { Raid = {}, FirstJoinUnix = 1 }
OWNERS[9] = victim.UserId
local st = { Units = {}, Order = "Follow" }
for i = 1, N do table.insert(st.Units, mkUnit(i, OWNERAT + Vector3.new(-10 - (i // 4) * 4.5, 0, (i % 4) * 5 - 7.5))) end
for i, u in ipairs(st.Units) do u.Model:SetAttribute("WE_Escorts", if type(ESC) == "table" then (ESC[i] or 0) else ESC) end
local realSpawn = task.spawn
task.spawn = function() end
AC.Start({ Squads = function() return { [owner.UserId] = st } end, CharacterRoot = function(p) return p._root end, UnitWalkSpeed = function() return 14 end })
task.spawn = realSpawn
AP.Init(DEPS)
AP._SetClock(function() return NOW end)
local campT = if CAMP then { Kind = "NPC", Hum = { Health = 100, Parent = { GetAttribute = function() return "npc1" end, Name = "Camp" } }, Root = { Position = CAMP, Parent = true } } else nil
local pick = function(player, s, proot, opts)
  s._acTarget = nil
  if campT and CAMPN > 0 and opts and opts.Centre and (Vector3.new(CAMP.X - opts.Centre.X, 0, CAMP.Z - opts.Centre.Z)).Magnitude <= (opts.Reach or 0) then s._acTarget = campT end
end
local DT = 0.05
local t0 = NOW
local function centre()
  local s, n = Vector3.zero, 0
  for _, u in ipairs(st.Units) do s += u.Root.Position; n += 1 end
  return s / n
end
local acc, acc2 = 0, 0
local function run(secs, report)
  local stop = NOW + secs
  while NOW < stop do
    NOW += DT
    acc += DT; acc2 += DT
    stepUnits(st.Units, DT)
    if acc >= 0.2 - 1e-9 then acc = 0; AC._StepArmy(owner, st, NOW) end
    if acc2 >= 0.4 - 1e-9 then
      acc2 = 0
      if AP.Owns(owner.UserId) then AP.Think(owner, st, owner._root, pick, NOW) end
      if report then report() end
    end
  end
end
-- 1) FOLLOW warm-up: the army forms behind him
run(8)
local c0 = centre()
print(string.format("FOLLOW formed: centre (%.1f,%.1f) %.1f from him", c0.X, c0.Z, (Vector3.new(c0.X, 0, c0.Z) - Vector3.new(OWNERAT.X, 0, OWNERAT.Z)).Magnitude))
-- 2) SEND ARMY to plot 9 (gate at x=600)
local ok, txt
if CAMP then ok = AP.StartClear(owner, st); txt = "clear" else ok, txt = AP.StartSend(owner, 9, st) end
print("StartSend", ok, txt)
local plan = AP._Plans()[owner.UserId]
local k = 0
local lastPhase = ""
SPREAD, BACK = 0, 0
local marchT0 = NOW
local cStart = centre()
run(SECS, function()
  k += 1
  local cc = centre()
  local p0 = AP._Plans()[owner.UserId]
  if p0 and p0.Phase == "March" then
    if NOW - marchT0 > 8 then for _, u in ipairs(st.Units) do SPREAD = math.max(SPREAD, (Vector3.new(u.Root.Position.X - cc.X, 0, u.Root.Position.Z - cc.Z)).Magnitude) end end
    local goalP = if CAMP then CAMP else Vector3.new(600, 0, 34)
    local tow = (Vector3.new(goalP.X - cStart.X, 0, goalP.Z - cStart.Z)).Unit
    BACK = math.min(BACK, (cc - cStart):Dot(tow))
  end
  local p = AP._Plans()[owner.UserId]
  local c = centre()
  local ph = if p then p.Phase else "none"
  if k % 10 == 0 or ph ~= lastPhase then
    print(string.format("t=%5.1f phase=%-6s lead=(%.1f,%.1f) leadVel=%.1f routing=%s route=%s idx=%s centre=(%.1f,%.1f) gap=%.1f order=%s status=%s",
      NOW - t0, ph, p and p.Lead.X or 0, p and p.Lead.Z or 0, p and p.LeadVel.Magnitude or 0, tostring(p and p.Routing), tostring(p and p.Route and #p.Route), tostring(p and p.RouteIdx),
      c.X, c.Z, p and (Vector3.new(p.Lead.X - c.X, 0, p.Lead.Z - c.Z)).Magnitude or 0, st.Order, p and p.Status or ""))
  end
  lastPhase = ph
  if ph == "Fight" or ph == "Siege" then FIGHT = true end
end)
if RECALL then
  local cr = centre()
  print(string.format("METRICR outx=%.1f", cr.X))
  AP.Recall(owner, nil, st)
  print("RECALL issued; phase", (AP._Plans()[owner.UserId] or { Phase = "none" }).Phase)
  run(RECALL)
  local p = AP._Plans()[owner.UserId]
  local c = centre()
  print(string.format("METRICA planended=%s order=%s x=%.1f z=%.1f", tostring(p == nil), st.Order, c.X, c.Z))
  print(string.format("AFTER RECALL: plan=%s order=%s centre=(%.1f,%.1f) returnGate=%s", p and p.Phase or "ended", st.Order, c.X, c.Z, tostring(p and p.ReturnGate)))
end
local c1 = centre()
print(string.format("RESULT units=%d esc=%s centre moved %.1f studs toward the gate (x %.1f -> %.1f); phase=%s teleports=%d computeFails=%d", N, tostring(ESC), c1.X - c0.X, c0.X, c1.X,
  (AP._Plans()[owner.UserId] or { Phase = "none" }).Phase, TELEPORTS, COMPUTE_FAIL))
print("ORDER", st.Order)
print(string.format("COHERENCE max soldier distance from the block centre while marching %.1f; most backward %.1f studs", SPREAD, BACK))
for _, n in ipairs(LOG.notify) do print("notify", n.p, n.t) end
local pEnd = AP._Plans()[owner.UserId]
local noRoute = false
for _, n in ipairs(LOG.notify) do if n.p == "shaunie6" and string.find(n.t, "No route", 1, true) then noRoute = true end end
local home = false
for _, n in ipairs(LOG.notify) do if n.t == "Army home" then home = true end end
local toGate = (if pEnd and pEnd.Dest then pEnd.Dest else c1)
print(string.format("METRIC moved=%.1f phase=%s teleports=%d spread=%.1f back=%.1f noroute=%s home=%s order=%s fightreached=%s endx=%.1f endz=%.1f",
  c1.X - c0.X, if pEnd then pEnd.Phase else "none", TELEPORTS, SPREAD, BACK, tostring(noRoute), tostring(home), st.Order, tostring(FIGHT == true), c1.X, c1.Z))
'''
def run(n=12, esc=0, owner="Vector3.new(0, 3, 0)", home="nil", mid="nil", secs=60, recall=None, camp="nil", campn=3):
    chunks = [PRELUDE, EXTRA, f"NUNITS = {n}\nESC = {esc if not isinstance(esc,list) else '{'+','.join(map(str,esc))+'}'}\nOWNERAT = {owner}\nHOMEPLOT = {home}\nMIDPLOT = {mid}\nSECS = {secs}\nCAMP = {camp}\nCAMPN = {campn}\nRECALL = {recall or 'nil'}\n"]
    for key, path in MODS.items():
        body = path.read_text(encoding="utf-8") if isinstance(path, Path) else path
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, body))
    chunks.append(TEST)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False) as f:
        f.write("\n".join(chunks)); p = f.name
    r = subprocess.run([os.environ.get("LUAU", "luau"), p], capture_output=True, text=True, timeout=600)
    return r.stdout + r.stderr
def metrics(out, tag="METRIC"):
    for line in out.splitlines():
        if line.startswith(tag + " "):
            return dict(kv.split("=", 1) for kv in line.split()[1:])
    return None


HOME = dict(home="Vector3.new(-200, 0, 0)", owner="Vector3.new(-200, 3, 0)")
SCENARIOS = [
    ("SEND from inside his walled base (army at his gate)", dict(n=8, **HOME), "siege"),
    ("SEND with a leg end inside another walled plot", dict(n=5, mid="Vector3.new(200, 0, 0)"), "siege"),
    ("SEND with 8 units + 12 escorts (deep block)", dict(n=8, esc=[3, 3, 3, 3, 0, 0, 0, 0]), "siege"),
    ("SEND in the open, 5 units (unchanged)", dict(n=5), "siege"),
    ("RECALL while he is inside his base", dict(n=8, secs=40, recall=90, **HOME), "recall"),
    ("ATTACK auto-clear from inside his base", dict(n=8, camp="Vector3.new(0, 3, 60)", secs=40, **HOME), "fight"),
]

if __name__ == "__main__":
    import json
    if len(sys.argv) > 1:
        print(run(**json.loads(sys.argv[1])))
        sys.exit(0)
    fails = 0

    def check(ok, msg):
        global fails
        print(("ok    " if ok else "FAIL  ") + msg)
        if not ok:
            fails += 1

    for name, kw, kind in SCENARIOS:
        out = run(**kw)
        m = metrics(out)
        if m is None:
            check(False, name + ": no result\n" + out[-2000:])
            continue
        common = m["teleports"] == "0" and m["noroute"] == "false" and float(m["back"]) > -2.5
        if kind == "siege":
            check(m["fightreached"] == "true" and common and float(m["spread"]) <= 16,
                  f"{name}: SIEGE reached {m['fightreached']}, moved {m['moved']} studs, no route toast {m['noroute']}, teleports {m['teleports']}, most backward {m['back']}, max spread {m['spread']}")
        elif kind == "fight":
            check(m["fightreached"] == "true" and common, f"{name}: FIGHT reached {m['fightreached']}, no route toast {m['noroute']}, teleports {m['teleports']}")
        else:
            r = metrics(out, "METRICR")
            a = metrics(out, "METRICA")
            ok = r is not None and a is not None and float(r["outx"]) > 250 and a["planended"] == "true" and a["order"] == "Follow" \
                and m["home"] == "true" and m["noroute"] == "false" and m["teleports"] == "0" and abs(float(a["x"]) - (-40 + 34)) < 45
            check(ok, f"{name}: out to x={r and r['outx']}, back home at x={a and a['x']} (his gate spot x=-6), plan ended {a and a['planended']}, FOLLOW {a and a['order']}")
    print(f"ARMY MARCH TEST: {fails} failed")
    sys.exit(1 if fails else 0)
