"""Code Bot v163 (owner phone bug: SEND to a player base -> "ARMY: SIEGE gate 100% guns 0", the army stood against
the wall at night and never shot). The full base siege in the Studio-free sim: real ArmyPlan / ArmyRoute /
ArmyController / SoldierController / FormationController / ArmyState / ArmyCommand / ArmySendRules, a walled plot
(square half 160, the gate a 10-stud opening in its west wall, local +Z = outside), the victim standing in his yard.

The shots: a stand-in of SquadOrdersService.attackAimOnly's rule for a Player / Guard / Structure target (pinned to
the real code in tools/checks/codebot_v163.py): fire band = OrdersConfig.AttackRange x 0.85 (3-D), a shot needs a
clear ray from the unit's eye (the walls block it; the gate leaves only where the ray crosses the opening), 1 shot /
s per unit; a ray at a player that hits a gate leaf shoots the gate (ShootGates). Damage lands through a stand-in of
GateDefenseService.applyDamageFrom (GateHitMaxDistance 120; breach at 0). Nothing forces damage.

  python3 tools/sim/run_army_siege_test.py            the fixed code: gate HP falls from shots, breaks, army goes in, loots
  ARMY_SRC=<dir> python3 tools/sim/run_army_siege_test.py --raw   any source tree's metrics (the before proof)
"""
import os, subprocess, sys, tempfile
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from run_kit_detail_test import PRELUDE
import run_army_march_test as M
from army_cmd_mods import army_cmd_mods

LUAU = os.environ.get("LUAU", os.path.expanduser("~/.local/bin/luau"))
PROOF = HERE.parents[1] / "docs/proof/army-siege"

EXTRA = r'''
-- the walled plot: centre (700, 0, 0), half 160; the gate opening in the west wall (x = 540), |z| <= 5
PLOTC = Vector3.new(700, 0, 0); HALF = 160; GATEX = 540; GATEW = 5; WALLH = 30
GATE = CFrame.lookAt(Vector3.new(GATEX, 0, 0), Vector3.new(GATEX + 1, 0, 0)) -- LookVector +X: local +Z = -X = outside
GATEPART = { Position = Vector3.new(GATEX, 4, 0), Parent = true, Name = "GateBarrier_1" }
SIEGE = { GatePart = GATEPART, GateHp = 2500, GateMax = 2500, Breached = false, Turrets = {}, CollectorPos = Vector3.new(700, 3, 40),
  PadCenter = PLOTC, PadHalf = HALF, GuardPower = {}, TurretPower = {} }
OWNERS[9] = 77
DEPS.GateDefenseService.GetGateCFrame = function(plot) return GATE end
DEPS.GateDefenseService.SiegeInfo = function() return SIEGE end
DEPS.MoneyCollectorService = { CanArmyRaid = function() return true end, ArmyRaid = function() LOOTED = 4321; return 4321 end }
-- does the segment a->b cross a wall (the plot square's sides, WALLH tall, the gate opening open once breached /
-- a gate leaf there while it stands)? returns "wall" / "gate" / nil
-- the walled plots: { C, Half, GateX (its west-wall gate x, the only opening) }; BYPLOT = a second base beside the route
PLOTS = { { C = PLOTC, Half = HALF, Gate = true } }
if BYSTANDER and not AGGRESSOR then table.insert(PLOTS, { C = Vector3.new(380, 0, 200), Half = 100, Gate = false }) end
-- the real GateDefenseService.WalledPlotAt: a plot whose standing walls enclose pos
DEPS.GateDefenseService.WalledPlotAt = function(pos)
  for i, pl in ipairs(PLOTS) do
    if math.abs(pos.X - pl.C.X) <= pl.Half and math.abs(pos.Z - pl.C.Z) <= pl.Half then
      if pl.Gate and SIEGE.Breached then return nil end
      return i
    end
  end
  return nil
end
function segHit(a, b)
  for _, pl in ipairs(PLOTS) do
    local cx, cz, h = pl.C.X, pl.C.Z, pl.Half
    local function side(fixed, axis, lo, hi)
      local da = if axis == "x" then a.X - fixed else a.Z - fixed
      local db = if axis == "x" then b.X - fixed else b.Z - fixed
      if da * db > 0 or da == db then return nil end
      local t = da / (da - db)
      local p = a + (b - a) * t
      local other = if axis == "x" then p.Z else p.X
      if other < lo or other > hi or p.Y > WALLH then return nil end
      if pl.Gate and axis == "x" and fixed == cx - h and math.abs(p.Z - cz) <= GATEW then
        if SIEGE.Breached then return nil end
        if p.Y <= 9 then return "gate" end
        return "wall"
      end
      return "wall"
    end
    local r = side(cx - h, "x", cz - h, cz + h) or side(cx + h, "x", cz - h, cz + h) or side(cz - h, "z", cx - h, cx + h) or side(cz + h, "z", cx - h, cx + h)
    if r then return r end
  end
  return nil
end
SHOTS = { fired = 0, hitGate = 0, noLos = 0, outOfBand = 0, gateDmg = 0, playerHits = 0 }
function applyGate(fromPos, amount)
  if SIEGE.Breached then return false end
  if (fromPos - GATEPART.Position).Magnitude > 120 then return false end
  SIEGE.GateHp = math.max(0, SIEGE.GateHp - amount); SHOTS.gateDmg += amount
  if SIEGE.GateHp <= 0 then SIEGE.Breached = true; BREACHED_AT = NOW end
  return true
end
-- the attackAimOnly stand-in (Player / Guard / Structure): band, eye ray, ShootGates, 1 shot / s
function shootPass(st, now)
  local tgt = st._acTarget
  for _, u in ipairs(st.Units) do
    if tgt and tgt.Root and (now - (u.LastFireAt or -math.huge)) >= 1 then
      local eye = u.Root.Position + Vector3.new(0, 1.5, 0)
      local d = (tgt.Root.Position - u.Root.Position).Magnitude
      if d > 55 * 0.85 then SHOTS.outOfBand += 1
      else
        local hit = segHit(eye, tgt.Root.Position)
        if tgt.Kind == "Structure" and hit == "gate" then hit = nil end -- the gate leaf IS the target
        if hit == nil then
          u.LastFireAt = now; SHOTS.fired += 1
          if tgt.Kind == "Structure" then if applyGate(u.Root.Position, 20) then SHOTS.hitGate += 1 end
          else
            SHOTS.playerHits += 1
            if tgt.Hum then tgt.Hum.Health -= 20 end
            if tgt.Hum and tgt.Hum.Health <= 0 and tgt.Player then
              -- he dies and respawns at the town spawn, far away (out of the siege reach)
              tgt.Player._root.Position = Vector3.new(0, 3, 2000); tgt.Hum.Health = 100; KILLS = (KILLS or 0) + 1
            end
          end
        elseif hit == "gate" and tgt.Kind == "Player" then
          u.LastFireAt = now; SHOTS.fired += 1
          if applyGate(u.Root.Position, 20) then SHOTS.hitGate += 1 end
        else
          SHOTS.noLos += 1; u.LastFireAt = now - 0.0 -- losBlockedFor: the next check waits 1 / fire rate
        end
      end
    end
  end
end
'''

TEST = r'''
local AP = require(node("Modules/ArmyPlan"))
local AC = require(node("Modules/ArmyController"))
local Route = require(node("Modules/ArmyRoute"))
local okAS, AS = pcall(require, node("Modules/ArmyState"))
local AL = require(node("Util/ArmyLog"))
AL.ForceOn = true
warn = function(...) print("WARN", ...) end
Route._SetComputer(function(a, b)
  -- PathfindingService stand-in: walls block; through the gate once breached (via a point outside then inside it)
  local pts = {}
  local function leg(p, q) local d = q - p; local n = math.max(1, math.ceil(Vector3.new(d.X, 0, d.Z).Magnitude / 8)); for i = 1, n do local r = p + d * (i / n); table.insert(pts, Vector3.new(r.X, 0, r.Z)) end end
  local aIn = math.abs(a.X - PLOTC.X) <= HALF and math.abs(a.Z) <= HALF
  local bIn = math.abs(b.X - PLOTC.X) <= HALF and math.abs(b.Z) <= HALF
  if aIn ~= bIn then
    if not SIEGE.Breached then return nil end
    local o, i = Vector3.new(GATEX - 20, 0, 0), Vector3.new(GATEX + 20, 0, 0)
    if aIn then leg(a, i); leg(i, o); leg(o, b) else leg(a, o); leg(o, i); leg(i, b) end
    return pts
  end
  leg(a, b); return pts end)
local owner = mkPlayer(470626172, "shaunie6", Vector3.new(200, 3, 0))
local victim = mkPlayer(77, "Chaplin606", Vector3.new(620, 3, 12)) -- standing in his yard, behind the wall
PLAYERS = { owner, victim }
local bystander = mkPlayer(88, "Hicktonn94", Vector3.new(380, 3, 106)) -- in HIS yard, just behind his wall (z=100), 106 studs off the route
if BYSTANDER then table.insert(PLAYERS, bystander); PROFILES[88] = { Raid = {}, FirstJoinUnix = 1 } end
PROFILES[owner.UserId] = { Raid = {}, FirstJoinUnix = 1 }
PROFILES[victim.UserId] = { Raid = {}, FirstJoinUnix = 1 }
local st = { Units = {}, Order = "Follow" }
for i = 1, NUNITS do table.insert(st.Units, mkUnit(i, Vector3.new(190 - (i // 6) * 4, 0, (i % 6) * 4 - 10))) end
for _, u in ipairs(st.Units) do u.Model:SetAttribute("WE_Escorts", 0) end
local realSpawn = task.spawn
task.spawn = function() end
AC.Start({ Squads = function() return { [owner.UserId] = st } end, CharacterRoot = function(p) return p._root end, UnitWalkSpeed = function() return 14 end })
task.spawn = realSpawn
AP.Init(DEPS)
AP._SetClock(function() return NOW end)
-- the one target pick's stand-in (pickSquadTarget: players first, THE hostility rule says the victim may be hit)
local pick = function(player, s, proot, opts)
  s._acTarget = nil
  local best, bd = nil, math.huge
  for _, pl in ipairs(PLAYERS) do
    if pl ~= player then
      local r = pl._root
      local d = opts and opts.Centre and Vector3.new(r.Position.X - opts.Centre.X, 0, r.Position.Z - opts.Centre.Z).Magnitude or math.huge
      if d <= (opts.Reach or 0) and d < bd then best, bd = pl, d end
    end
  end
  if best then s._acTarget = { Kind = "Player", Player = best, Hum = best._hum, Root = best._root } end
end
-- AGGRESSOR: the bystander stands in the open and has been shooting his soldiers (he must be answered)
DEPS.CombatService.RecentlyHurtBy = function(v, a, secs) return AGGRESSOR and a == bystander end
local function centre() local s, n = Vector3.zero, 0; for _, u in ipairs(st.Units) do s += u.Root.Position; n += 1 end; return s / n end
local DT = 0.05
local acc, acc2 = 0, 0
local inside, wallHits = 0, 0
local function run(secs, each)
  local stop = NOW + secs
  while NOW < stop do
    NOW += DT; acc += DT; acc2 += DT
    local before = {}
    for i, u in ipairs(st.Units) do before[i] = u.Root.Position end
    stepUnits(st.Units, DT)
    -- the walls are solid: a soldier walking into one stops there (the real Humanoid collides)
    for i, u in ipairs(st.Units) do if segHit(before[i] + Vector3.new(0, 1, 0), u.Root.Position + Vector3.new(0, 1, 0)) then u.Root.Position = before[i]; wallHits += 1 end end
    if acc >= 0.2 - 1e-9 then acc = 0; AC._StepArmy(owner, st, NOW) end
    if acc2 >= 0.4 - 1e-9 then
      acc2 = 0
      if AP.Owns(owner.UserId) then AP.Think(owner, st, owner._root, pick, NOW) end
      shootPass(st, NOW)
      if each then each() end
    end
  end
end
run(4)
local ok, txt = AP.StartSend(owner, 9, st)
print("S_SEND", ok, txt)
local marchStall, maxStill, stillSince, lastC = 0, 0, nil, nil
local samples, gateSeries, statusLast, targetKinds = 0, {}, "", {}
local enteredAt = nil
run(SECS, function()
  samples += 1
  local p = AP._Plans()[owner.UserId]
  local t = st._acTarget
  if p and (p.Phase == "Siege" or p.Phase == "Loot") then targetKinds[(t and t.Kind) or "none"] = (targetKinds[(t and t.Kind) or "none"] or 0) + 1 end
  if p and p.Phase == "March" then
    local cc = centre()
    if lastC and Vector3.new(cc.X - lastC.X, 0, cc.Z - lastC.Z).Magnitude < 0.5 then stillSince = stillSince or NOW; maxStill = math.max(maxStill, NOW - stillSince) else stillSince = nil end
    lastC = cc
  end
  if samples % 10 == 0 then table.insert(gateSeries, tostring(math.floor(100 * SIEGE.GateHp / SIEGE.GateMax))) end
  if p then statusLast = p.Phase .. ": " .. tostring(p.Status) end
  local c = centre()
  if math.abs(c.X - PLOTC.X) < HALF - 5 and math.abs(c.Z) < HALF - 5 and enteredAt == nil then enteredAt = NOW end
end)
local kinds = {}
for k, n in pairs(targetKinds) do table.insert(kinds, k .. "=" .. n) end
table.sort(kinds)
local c = centre()
print("S_GATE_SERIES " .. table.concat(gateSeries, ","))
print("S_GATE_END " .. math.floor(100 * SIEGE.GateHp / SIEGE.GateMax))
print("S_BREACHED " .. tostring(SIEGE.Breached))
print("S_ENTERED " .. tostring(enteredAt ~= nil))
print("S_LOOTED " .. tostring(LOOTED or 0))
print("S_KILLS " .. tostring(KILLS or 0))
print("S_TARGETS " .. table.concat(kinds, ","))
print(string.format("S_SHOTS fired=%d gatehits=%d nolos=%d outofband=%d", SHOTS.fired, SHOTS.hitGate, SHOTS.noLos, SHOTS.outOfBand))
print(string.format("S_CENTRE %.0f,%.0f", c.X, c.Z))
print("S_TELEPORTS " .. TELEPORTS)
do
  local outside, xs = 0, {}
  for _, u in ipairs(st.Units) do if u.Humanoid.Health > 0 then if u.Root.Position.X < PLOTC.X - HALF then outside += 1 end; table.insert(xs, string.format("%.0f,%.0f", u.Root.Position.X, u.Root.Position.Z)) end end
  print("S_UNITS_OUTSIDE " .. outside)
  print("S_UNIT_POS " .. table.concat(xs, " "))
end
print(string.format("S_MARCH_MAXSTILL %.1f", maxStill))
local pEnd = AP._Plans()[owner.UserId]
print("S_PHASE_END " .. (if pEnd then pEnd.Phase else "none"))
print("S_STATUS " .. statusLast)
for _, n in ipairs(LOG.notify) do print("notify", n.p, n.t) end
'''


def run(src=None, n=24, secs=150, bystander=False, aggressor=False):
    root = Path(src) if src else HERE.parents[1]
    mods = {}
    for k, p in {**army_cmd_mods(), **M.MODS}.items():
        if isinstance(p, Path):
            alt = root / p.relative_to(HERE.parents[1])
            mods[k] = alt if alt.exists() else None
        else:
            mods[k] = p
    chunks = [PRELUDE, M.EXTRA, f"BYSTANDER = {'true' if bystander else 'false'}\nAGGRESSOR = {'true' if aggressor else 'false'}\n", EXTRA, f"NUNITS = {n}\nSECS = {secs}\nESC = 0\nHOMEPLOT = nil\nMIDPLOT = nil\n"]
    for k, p in mods.items():
        if p is None:
            continue
        body = p.read_text(encoding="utf-8") if isinstance(p, Path) else p
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (k, body))
    chunks.append(TEST)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False) as f:
        f.write("\n".join(chunks)); path = f.name
    r = subprocess.run([LUAU, path], capture_output=True, text=True, timeout=900)
    return r.stdout + r.stderr


def vals(out):
    d = {}
    for line in out.splitlines():
        if line.startswith("S_"):
            k, _, v = line.replace("\t", " ").partition(" ")
            d[k] = v.strip()
    return d


if __name__ == "__main__":
    if "--raw" in sys.argv:
        print(run(os.environ.get("ARMY_SRC"), bystander="--bystander" in sys.argv or "--aggressor" in sys.argv, aggressor="--aggressor" in sys.argv))
        sys.exit(0)
    fails = 0

    def check(ok, msg):
        global fails
        print(("ok    " if ok else "FAIL  ") + msg)
        if not ok:
            fails += 1
    PROOF.mkdir(parents=True, exist_ok=True)
    out = run(n=24)
    (PROOF / "after-siege-24.log").write_text(out)
    v = vals(out)
    series = [int(x) for x in v.get("S_GATE_SERIES", "").split(",") if x]
    check(v.get("S_SEND", "").startswith("true"), f"SEND accepted ({v.get('S_SEND')})")
    check(len(series) >= 3 and series[0] >= series[-1] and min(series) < 100, f"gate HP falls from real shots (every 4 s: {v.get('S_GATE_SERIES')})")
    check("Structure" in v.get("S_TARGETS", ""), f"the siege target is the gate while the walls stand ({v.get('S_TARGETS')})")
    check(v.get("S_BREACHED") == "true", "the gate breaks")
    check(v.get("S_ENTERED") == "true", f"the army goes in through the gate (block centre {v.get('S_CENTRE')})")
    check(v.get("S_LOOTED") == "4321", f"the raid loots per the JOB 38 hold rule ({v.get('S_LOOTED')})")
    check(v.get("S_TELEPORTS") == "0", "no teleport")
    shots = v.get("S_SHOTS", "")
    check("gatehits=0" not in shots, f"shots land on the gate ({shots})")
    out75 = run(n=75, secs=170)
    (PROOF / "after-siege-75.log").write_text(out75)
    v = vals(out75)
    check(v.get("S_BREACHED") == "true" and v.get("S_ENTERED") == "true" and v.get("S_TELEPORTS") == "0",
          f"75 soldiers: breach {v.get('S_BREACHED')}, in {v.get('S_ENTERED')}, loot {v.get('S_LOOTED')}, gate every 4 s {v.get('S_GATE_SERIES')}, {v.get('S_SHOTS')}")
    # the march past another base whose owner stands in his yard behind his wall (owner report 3: "MARCHING", stopped)
    outB = run(n=24, secs=150, bystander=True)
    (PROOF / "after-march-bystander.log").write_text(outB)
    v = vals(outB)
    check(float(v.get("S_MARCH_MAXSTILL", "999")) < 8 and v.get("S_BREACHED") == "true",
          f"marching past a base with a non-hostile-acting player inside: the block never stalls (longest stand-still {v.get('S_MARCH_MAXSTILL')} s), reaches the siege, breach {v.get('S_BREACHED')}")
    outA = run(n=24, secs=150, bystander=True, aggressor=True)
    (PROOF / "after-march-aggressor.log").write_text(outA)
    v = vals(outA)
    check("Player=" in v.get("S_TARGETS", "") and int(v.get("S_KILLS", "0")) >= 1,
          f"a player shooting his army on the march (in the open) IS answered: targets {v.get('S_TARGETS')}, kills {v.get('S_KILLS')}")
    print(f"ARMY SIEGE TEST: {fails} failed")
    sys.exit(1 if fails else 0)
