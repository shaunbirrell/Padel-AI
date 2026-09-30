"""claude-bud JOB 38: real-code tests in the Luau CLI for the army attack orders (the real ArmyOrdersConfig, ArmySendRules,
ArmyRoute and ArmyPlan on recording stubs; stand-ins: run_kit_detail_test.PRELUDE).

1. FAIRNESS (ArmySendRules, the owner's DECIDED rules): every block reason in order (self, offline, ally, PvP off, shield,
   new player, novice, the 10-min army protection, the 5-min send cooldown, one active SEND, no soldiers, too weak
   < 0.25) and the allowed texts (risky / good odds / much stronger: half loot > 4); loot 5 % and 2.5 %.
2. ROUTE (ArmyRoute): legs <= LegStuds; a failed leg retries sideways and gives "no_route" after RouteRetries; the lead
   point never moves faster than MarchSpeed.
3. ATTACK AUTO-CLEAR (ArmyPlan): SEEK the nearest group -> MARCH (the lead point walks the route at <= MarchSpeed and
   WAITS while the block is more than LeadMaxGap behind) -> FIGHT until the group is gone -> chain -> nothing left ->
   RETURN -> FOLLOW. ATTACK again keeps the plan; RECALL marches back.
4. SEND: the verdict gate; the march; arrival sets the sender cooldown (300 s) and the victim protection (600 s) on the
   profiles; siege priority turret -> guard -> gate, a defending player first; the breach; the ATM hold (6 s, restarted
   by a hit) -> the army raid at 5 % (2.5 % bully); RETURN. The victim leaving mid-siege: return, cooldown 150 s. A wiped
   army ends the plan. The dead sender's damage option (OwnerAway) only on a SEND; no refill while a SEND is out; the
   defender's red marker.
5. NO TELEPORT: ArmyPlan / ArmyRoute contain no PivotTo / CFrame writes to units / TeleportService.
Run: LUAU=path/to/luau(.exe) python tools/sim/run_army_orders_test.py   (exit 1 on any failure)"""
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_kit_detail_test import PRELUDE  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SH = ROOT / "src/ReplicatedStorage/Shared"
SV = ROOT / "src/ServerScriptService/Server"
MODS = {
    "Configs/ArmyOrdersConfig": SH / "Configs/ArmyOrdersConfig.luau",
    "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
    "Configs/RaidConfig": SH / "Configs/RaidConfig.luau",
    "Modules/ArmySendRules": SV / "Modules/ArmySendRules.luau",
    "Configs/GameConfig": None,
    "Modules/ArmyRoute": SV / "Modules/ArmyRoute.luau",
    "Modules/ArmyPlan": SV / "Modules/ArmyPlan.luau",
}

EXTRA = r'''
NOW = 1000
local pending = {}
task = { spawn = function(fn, ...) fn(...) end, wait = function(s) NOW += (s or 0) end, delay = function() end, defer = function(fn, ...) fn(...) end }
Vector2 = { new = function(x, y) return { X = x, Y = y, Magnitude = math.sqrt(x * x + y * y) } end }
CFrame.lookAt = function(at, target) return CFrame.new(at.X, at.Y, at.Z) end
local function signal() local s = { fns = {} }; s.Connect = function(self, fn) table.insert(self.fns, fn); return { Disconnect = function() end } end; return s end
PLAYERS = {}
local Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return PLAYERS end,
  GetPlayerByUserId = function(_, id) for _, p in ipairs(PLAYERS) do if p.UserId == id then return p end end return nil end }
local RunService = { IsStudio = function() return false end }
local prevGame = game
game = { GetService = function(_, n)
  if n == "Players" then return Players elseif n == "RunService" then return RunService end
  return prevGame:GetService(n) end }

UNIX = 50000
os = setmetatable({ time = function() return UNIX end, clock = function() return NOW end }, { __index = os })
function mkPlayer(uid, name, at)
  local root = { Position = at, IsA = function(_, c) return c == "BasePart" end }
  local hum = { Health = 100 }
  local char = { FindFirstChild = function(_, n) if n == "HumanoidRootPart" then return root end end, FindFirstChildOfClass = function() return hum end }
  local p = { UserId = uid, Name = name, DisplayName = name, Parent = true, Character = char, _root = root, _hum = hum }
  p.IsA = function(_, c) return c == "Player" end
  return p
end
function mkUnits(n, at)
  local units = {}
  for i = 1, n do
    table.insert(units, { Alive = true, Humanoid = { Health = 150 }, Root = { Position = at + Vector3.new(i, 0, 0), Parent = true } })
  end
  return units
end
LOG = { notify = {}, push = 0, raids = {}, setorder = {} }
PROFILES = {}
OWNERS = {}
SIEGE = nil
GROUPS = {}
PICK = nil
DEPS = {
  DataService = { GetProfile = function(p) return PROFILES[p.UserId] end, MarkDirty = function() end },
  NotificationService = { Notify = function(p, t) table.insert(LOG.notify, { p = p, t = t }) end },
  SquadOrdersService = { Push = function() LOG.push += 1 end, UnitPower = function() return 5, 150, 20 end, SetOrder = function(p, o) table.insert(LOG.setorder, o) end },
  BaseService = { GetOwnerUserId = function(plot) return OWNERS[plot] end },
  GateDefenseService = {
    SiegeInfo = function() return SIEGE end,
    GetGateCFrame = function(plot) return CFrame.new(400, 0, 0) end,
    IsAlly = function() return false end,
  },
  CombatService = {
    GroupNPCs = function(gid) local out = {}; for i = 1, (GROUPS[gid] or 0) do table.insert(out, { Position = Vector3.new(200, 0, 0) }) end; return out end,
    NPCGroupOf = function(id) return "Garrison.RidgeCamp" end,
    IsNoviceShielded = function(p) return p.Novice == true end,
    UnitMayHitPlayer = function() return true end,
  },
  MoneyCollectorService = {
    CanArmyRaid = function() return true end,
    ArmyRaid = function(s, v, frac) table.insert(LOG.raids, frac); return 1234 end,
  },
}
'''

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local AOC = require(node("Configs/ArmyOrdersConfig"))
local R = require(node("Modules/ArmySendRules"))
local Route = require(node("Modules/ArmyRoute"))
local AP = require(node("Modules/ArmyPlan"))

-- ── 1. fairness ──
local base = { Self = false, VictimOnline = true, VictimHasBase = true, Ally = false, PvpOff = false, ShieldLeft = 0, NewPlayerLeft = 0,
  Novice = false, ProtectLeft = 0, CooldownLeft = 0, ActiveSend = false, Units = 5, ArmyPower = 1000, DefencePower = 1000 }
local function with(over) local f = table.clone(base); for k, v in pairs(over) do f[k] = v end; return R.Verdict(f) end
local cases = { { { Self = true }, "Self" }, { { VictimOnline = false }, "Offline" }, { { Ally = true }, "Ally" }, { { PvpOff = true }, "PvpOff" },
  { { ShieldLeft = 492 }, "Shielded" }, { { NewPlayerLeft = 300 }, "NewPlayer" }, { { Novice = true }, "Novice" }, { { ProtectLeft = 300 }, "Protected" },
  { { CooldownLeft = 120 }, "Cooldown" }, { { ActiveSend = true }, "Active" }, { { Units = 0 }, "NoArmy" }, { { ArmyPower = 200 }, "TooWeak" } }
for _, c in ipairs(cases) do
  local v = with(c[1])
  check(v.Ok == false and v.Reason == c[2], "blocked: " .. c[2] .. " (" .. v.Text .. ")")
end
check(with({ ShieldLeft = 492 }).Text == "🛡 Shielded 8:12", "shield text '🛡 Shielded 8:12'")
check(with({ VictimOnline = false }).Text == "Player left", "offline text 'Player left' (online only)")
local v1 = with({ ArmyPower = 820, DefencePower = 1240 })
check(v1.Ok and v1.Text == "Your army 820 vs defences 1,240: risky" and not v1.Bully, "allowed: " .. v1.Text)
local v2 = with({ ArmyPower = 5000, DefencePower = 1000 })
check(v2.Ok and v2.Bully and string.find(v2.Text, "much stronger: half loot", 1, true) ~= nil, "bully: " .. v2.Text)
check(math.abs(AOC.LootFraction(0.10, false) - 0.05) < 1e-9 and math.abs(AOC.LootFraction(0.10, true) - 0.025) < 1e-9, "loot 5 % (army) and 2.5 % (bully)")
check(R.ArmyPower(5, 150, 20) == 15000 and R.DefencePower(800, { { Hp = 140, Dps = 19.6 } }, { { Hp = 400, Dps = 10 } }) == 800 + 140 * 19.6 + 4000, "power = units x HP x DPS vs gate + guards + turrets")
check(AOC.Fairness.SendCooldownSeconds == 300 and AOC.Fairness.ProtectAfterSiegeSeconds == 600 and AOC.ArmyLootMult == 0.5 and AOC.Send.RequireOwnerAlive == false
  and AOC.Fairness.MinPowerRatio == 0.25 and AOC.Fairness.BullyRatio == 4, "the decided numbers: 5 min / 10 min / 5 % / dead sender keeps going / 0.25 / 4")
check(AOC.TurretHealth(3) == 0 and AOC.TurretHealth(4) == 400 and AOC.TurretHealth(5) == 550 and AOC.TurretHealth(9) == 700, "turret HP by walls level")

-- ── 2. route ──
local legs = Route.Legs(Vector3.new(0, 0, 0), Vector3.new(1000, 0, 0))
check(#legs == 3, "1000 studs -> 3 legs of <= 400")
Route._SetComputer(function(a, b) return { a, b } end)
local r, why = Route.Plan(Vector3.new(0, 0, 0), Vector3.new(1000, 0, 0))
check(r ~= nil and #r == 6, "a routed plan (" .. tostring(r and #r) .. " waypoints)")
local tries = 0
Route._SetComputer(function() tries += 1; return nil end)
local r2, why2 = Route.Plan(Vector3.new(0, 0, 0), Vector3.new(100, 0, 0))
check(r2 == nil and why2 == "no_route" and tries == AOC.RouteRetries, "no route after " .. tries .. " tries (no teleport fallback)")
local p1, i1, d1 = Route.Advance(Vector3.new(0, 0, 0), { Vector3.new(10, 0, 0), Vector3.new(100, 0, 0) }, 1, 14, 0.5)
check(math.abs(p1.X - 7) < 1e-6 and i1 == 1, "Advance: 14 studs/s x 0.5 s = 7 studs")
Route._SetComputer(function(a, b) return { b } end)

-- ── 3. auto-clear ──
AP.Init(DEPS)
AP._SetClock(function() return NOW end)
local owner = mkPlayer(470626172, "shaunie6", Vector3.new(0, 3, 0))
local victim = mkPlayer(77, "rival", Vector3.new(400, 3, 0))
PLAYERS = { owner, victim }
PROFILES[owner.UserId] = { Raid = {}, FirstJoinUnix = 1 }
PROFILES[victim.UserId] = { Raid = {}, FirstJoinUnix = 1 }
local st = { Units = mkUnits(5, Vector3.new(0, 3, 0)), Order = "Attack" }
local campRoot = { Position = Vector3.new(200, 3, 0), Parent = true }
local camp = { Kind = "NPC", Hum = { Health = 100, Parent = { GetAttribute = function() return "npc1" end, Name = "Camp" } }, Root = campRoot }
GROUPS["Garrison.RidgeCamp"] = 3
local pickCalls = 0
local function pick(player, s, proot, opts) pickCalls += 1; s._acTarget = PICK; return PICK end
PICK = camp
check(AP.StartClear(owner, st), "ATTACK starts the auto-clear (live owner)")
AP.Think(owner, st, owner._root, pick, NOW)
local plan = AP._Plans()[owner.UserId]
check(plan.Phase == "March" and plan.Group and plan.Group.GroupId == "Garrison.RidgeCamp" and plan.Group.Name == "RidgeCamp", "SEEK -> the Ridge camp group, MARCH")
check(AP.AllowsNpcGroup(owner, "Garrison.RidgeCamp") == true and AP.DamageOpts(owner) == nil and not AP.HoldsRefill(owner.UserId), "clear: may engage the group away from him; no OwnerAway, refill allowed")
local maxSpeed, waited = 0, false
local lastT = NOW
for i = 1, 60 do
  NOW += 0.4
  local before = plan.Lead
  -- the block follows the lead, but lags a little (and one tick it falls far behind)
  local gap = if i == 5 then 30 else 6
  for _, u in ipairs(st.Units) do u.Root.Position = plan.Lead - Vector3.new(gap, 0, 0) end
  local t = NOW
  local lastAt = plan.LastAt
  AP.Think(owner, st, owner._root, pick, t)
  -- the plan's own dt (the stubbed task.wait of the route budget moves NOW while a route is planned)
  local dtUsed = math.clamp(t - lastAt, 0.05, 1)
  local d = plan.Lead - before
  local moved = math.sqrt(d.X * d.X + d.Z * d.Z) / dtUsed -- flat: the lead follows the ground height
  maxSpeed = math.max(maxSpeed, moved)
  if i == 5 and (plan.Lead - before).Magnitude < 1e-6 then waited = true end
  if plan.Phase ~= "March" then break end
end
check(maxSpeed <= AOC.MarchSpeed + 1e-6, string.format("the lead never exceeds MarchSpeed (max %.2f)", maxSpeed))
check(waited, "the lead WAITS while the block is more than LeadMaxGap behind (no catch-up hack)")
check(plan.Phase == "Fight", "arrived: FIGHT (" .. plan.Phase .. ")")
GROUPS["Garrison.RidgeCamp"] = 1
NOW += 0.4
AP.Think(owner, st, owner._root, pick, NOW)
check(plan.Kills == 2 and string.find(plan.Status, "FIGHTING 1 left", 1, true) ~= nil, "FIGHTING 1 left (" .. plan.Status .. ")")
GROUPS["Garrison.RidgeCamp"] = 0
PICK = nil
NOW += 0.4
AP.Think(owner, st, owner._root, pick, NOW)
check(plan.Chain == 1 and plan.Phase == "Seek", "CLEARED -> chain 1, SEEK again from the army")
NOW += 0.4
AP.Think(owner, st, owner._root, pick, NOW)
check(plan.Phase == "Return", "nothing left within ChainRadius: RETURN")
for i = 1, 80 do
  NOW += 0.4
  for _, u in ipairs(st.Units) do u.Root.Position = plan.Lead end
  AP.Think(owner, st, owner._root, pick, NOW)
  if AP._Plans()[owner.UserId] == nil then break end
end
check(AP._Plans()[owner.UserId] == nil and st.Order == "Follow", "back at him: the plan ends, FOLLOW")
PICK = camp
GROUPS["Garrison.RidgeCamp"] = 2
AP.StartClear(owner, st)
check(AP.Recall(owner, nil, st) and AP._Plans()[owner.UserId].Phase == "Return", "RECALL: the army marches back (no teleport)")
AP._Reset()

-- ── 4. SEND ──
OWNERS[9] = victim.UserId
SIEGE = { GatePart = { Position = Vector3.new(400, 3, 0), Parent = true }, GateHp = 800, GateMax = 800, Breached = false,
  Turrets = { { Part = { Position = Vector3.new(390, 3, 20), Parent = true }, Hp = 400, Max = 400, Offline = false } },
  CollectorPos = Vector3.new(430, 3, 0), GuardPower = { { Hp = 140, Dps = 19.6 } }, TurretPower = { { Hp = 400, Dps = 10 } } }
PROFILES[victim.UserId].Raid.ShieldUntil = UNIX + 100
local okS, txt = AP.StartSend(owner, 9, st)
check(not okS and string.find(txt, "Shielded", 1, true) ~= nil, "SEND to a shielded base: blocked (" .. txt .. ")")
PROFILES[victim.UserId].Raid.ShieldUntil = 0
OWNERS[10] = 12345
local okO, txtO = AP.StartSend(owner, 10, st)
check(not okO and txtO == "Player left", "SEND to an offline owner's plot: blocked (online only)")
victim.Novice = true
check(not AP.StartSend(owner, 9, st), "SEND to a novice-shielded player: blocked")
victim.Novice = false
okS, txt = AP.StartSend(owner, 9, st)
plan = AP._Plans()[owner.UserId]
check(okS and plan and plan.Kind == "Send" and plan.Phase == "March", "SEND: " .. tostring(txt))
local incoming = AP.IncomingFor(victim.UserId)
check(incoming ~= nil and #incoming == 1 and incoming[1].N == "shaunie6", "the defender's red map marker")
local warned = false
for _, n in ipairs(LOG.notify) do if n.p == victim and string.find(n.t, "ARMY is marching on your base, ETA", 1, true) then warned = true end end
check(warned, "the defender gets the ETA warning at once")
check(AP.HoldsRefill(owner.UserId) and AP.DamageOpts(owner) ~= nil and AP.DamageOpts(owner).OwnerAway == true, "SEND: no refill at the owner; the dead-sender damage option")
for i = 1, 200 do
  NOW += 0.4
  for _, u in ipairs(st.Units) do u.Root.Position = plan.Lead end
  AP.Think(owner, st, owner._root, pick, NOW)
  if plan.Phase ~= "March" then break end
end
check(plan.Phase == "Siege", "arrived: SIEGE")
check(PROFILES[owner.UserId].Raid.ArmySendCooldownUntil == UNIX + 300 and PROFILES[victim.UserId].Raid.ArmyProtectUntil == UNIX + 600, "sender cooldown 5 min + victim protection 10 min, saved on the profiles")
PICK = nil
NOW += 0.4
AP.Think(owner, st, owner._root, pick, NOW)
check(st._acTarget and st._acTarget.Kind == "Structure" and st._acTarget.Root == SIEGE.Turrets[1].Part, "siege priority 1: the turret")
SIEGE.Turrets[1].Offline = true
local guardT = { Kind = "Guard", Hum = { Health = 100 }, Root = { Position = Vector3.new(395, 3, 5), Parent = true } }
PICK = guardT
NOW += 0.4
AP.Think(owner, st, owner._root, pick, NOW)
check(st._acTarget == guardT, "then the gate guards")
PICK = nil
NOW += 0.4
AP.Think(owner, st, owner._root, pick, NOW)
check(st._acTarget and st._acTarget.Root == SIEGE.GatePart, "then the gate")
local defender = { Kind = "Player", Player = victim, Hum = victim._hum, Root = victim._root }
PICK = defender
NOW += 0.4
AP.Think(owner, st, owner._root, pick, NOW)
check(st._acTarget == defender, "a defending player always first")
PICK = nil
SIEGE.Breached = true
owner._hum.Health = 0 -- the sender dies: the siege goes on
NOW += 0.4
AP.Think(owner, st, nil, pick, NOW)
check(plan.Breached and AP._Plans()[owner.UserId] == plan, "breach: the siege goes on though the sender is dead")
for i = 1, 40 do
  NOW += 0.4
  for _, u in ipairs(st.Units) do u.Root.Position = SIEGE.CollectorPos end
  if i == 5 then st.Units[1].Humanoid.Health = 120; st.Units[2].Humanoid.Health = 120; st.Units[3].Humanoid.Health = 120; st.Units[4].Humanoid.Health = 120; st.Units[5].Humanoid.Health = 120 end
  AP.Think(owner, st, nil, pick, NOW)
  if #LOG.raids > 0 then break end
end
check(#LOG.raids == 1 and math.abs(LOG.raids[1] - 0.05) < 1e-9, "ATM held 6 s (a hit restarted it): the army raid takes 5 %")
check(plan.Phase == "Return" and plan.Looted == 1234, "looted -> RETURN")
AP._Reset()
-- the victim leaves mid-siege
owner._hum.Health = 100
PROFILES[owner.UserId].Raid.ArmySendCooldownUntil = 0
PROFILES[victim.UserId].Raid.ArmyProtectUntil = 0
AP.StartSend(owner, 9, st)
plan = AP._Plans()[owner.UserId]
OWNERS[9] = nil
NOW += 0.4
AP.Think(owner, st, owner._root, pick, NOW)
check(plan.Phase == "Return" and PROFILES[owner.UserId].Raid.ArmySendCooldownUntil == UNIX + 150, "victim left: return, no loot, cooldown 150 s")
AP._Reset()
-- wiped
OWNERS[9] = victim.UserId
PROFILES[owner.UserId].Raid.ArmySendCooldownUntil = 0
AP.StartSend(owner, 9, st)
for _, u in ipairs(st.Units) do u.Alive = false end
AP.Think(owner, st, owner._root, pick, NOW)
local wiped = false
for _, n in ipairs(LOG.notify) do if n.t == "Army wiped out" then wiped = true end end
check(AP._Plans()[owner.UserId] == nil and wiped, "a wiped army ends the plan ('Army wiped out')")
for _, u in ipairs(st.Units) do u.Alive = true end
-- the bully loot
AP._Reset()
PROFILES[owner.UserId].Raid.ArmySendCooldownUntil = 0
PROFILES[victim.UserId].Raid.ArmyProtectUntil = 0
SIEGE.Breached = false
DEPS.SquadOrdersService.UnitPower = function() return 5, 150, 200 end -- far stronger
AP.StartSend(owner, 9, st)
plan = AP._Plans()[owner.UserId]
check(plan.Bully == true, "a far stronger army: the bully verdict is kept for the siege (half loot)")

print(string.format("ARMY ORDERS TEST: %d failed", fails))
if fails > 0 then error("failed") end
'''

fails = []
for f in ("Modules/ArmyPlan.luau", "Modules/ArmyRoute.luau", "Modules/ArmySendRules.luau"):
    src = (SV / f).read_text(encoding="utf-8")
    code = re.sub(r"--\[\[.*?\]\]", "", src, flags=re.S)
    code = "\n".join(l.split("--", 1)[0] for l in code.splitlines())
    bad_hit = [w for w in ("PivotTo", "TeleportService", "Root.CFrame =", ":MoveTo(", "Humanoid.Health =", "TakeDamage") if w in code]
    print(("ok    " if not bad_hit else "FAIL  ") + f"{f}: no teleport / forced moves / forced damage {bad_hit}")
    if bad_hit:
        fails.append(f)

chunks = [PRELUDE, EXTRA]
for key, path in MODS.items():
    body = "return { PvPEnabled = true }" if path is None else path.read_text(encoding="utf-8")
    chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, body))
chunks.append(TEST)
with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
    f.write("\n".join(chunks))
    path = f.name
luau = os.environ.get("LUAU", "luau")
r = subprocess.run([luau, path], capture_output=True, text=True)
out = r.stdout.strip()
print(out if os.environ.get("VERBOSE") else ("\n".join(l for l in out.splitlines() if l.startswith("FAIL") or l.startswith("ARMY ORDERS")) or out))
if r.returncode != 0 or fails:
    print(r.stderr.strip()[-2500:])
    sys.exit(1)
