"""claude-bud JOB 37: real-code tests in the Luau CLI for the road checkpoint guards (the real CheckpointGuardService and
CheckpointGuardConfig on recording stubs; stand-ins: run_kit_detail_test.PRELUDE).

1. SITE: a tagged booth with WE_GuardPost1..5 -> 5 posts (the tower one Static), a stable id.
2. WAKE: only a LIVE player within WakeStuds wakes the group: 5 SpawnNPC calls with GroupId "CP.<id>", NoRespawn, the
   leash, Static on the tower post, and a TargetFilter that accepts live players only; a non-live player wakes nothing.
3. KILL CREDIT + CLEARED ONCE: the last guard down pays each live contributor (killer, army kill, a LastHitBy hit within
   AssistSeconds) the cleared XP + cash once, with one toast and the mission "Checkpoint" +1; a stale / non-live
   contributor gets nothing; a repeated death event pays nothing more.
4. RESPAWN: not before RespawnSeconds (180), then only near a live player, never while a player stands on a post; the
   new cycle can pay again, but the per-player cooldown (300 s) holds.
5. SLEEP: nobody live within SleepStuds -> every guard despawned (no NPC slot).
6. MAP / GO: MapList only for live players (hostile / cleared + seconds left); GoTargets skips a cleared checkpoint.
7. CONFIG: codebot_v142 launched for everyone (OwnerFirst = false); 1-6 still prove the owner-first rule (the test
   sets OwnerFirst = true for them); respawn 180, the cleared cash floor / cap / private-server half.
8. codebot_v142: everyone is targeted, except a player under the spawn / novice shield (CombatService
   IsSpawnInvulnerable / IsNoviceShielded); the keep-out (KeepOutStuds 130) from the real BaseConfig plots and
   WorldConfig vehicle pools: the six detailed booths pass, Depot.CP_E / Armory.CP_W / Hawk are kept out.
Run: LUAU=path/to/luau(.exe) python tools/sim/run_checkpoint_guards_test.py   (exit 1 on any failure)"""
import os
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
    "Configs/CheckpointGuardConfig": SH / "Configs/CheckpointGuardConfig.luau",
    "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
    "Services/CheckpointGuardService": SV / "Services/CheckpointGuardService.luau",
}

EXTRA = r'''
task = { spawn = function() end, wait = function() end, delay = function() end, defer = function() end }
Vector2 = { new = function(x, y) return { X = x, Y = y, Magnitude = math.sqrt(x * x + y * y) } end }
CFrame.lookAt = function(at, target) return CFrame.new(at.X, at.Y, at.Z) end
local function signal() local s = { fns = {} }; s.Connect = function(self, fn) table.insert(self.fns, fn); return { Disconnect = function() end } end; return s end
PLAYERS = {}
local Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return PLAYERS end,
  GetPlayerByUserId = function(_, id) for _, p in ipairs(PLAYERS) do if p.UserId == id then return p end end return nil end }
local RunService = { IsStudio = function() return false end }
TAGGED = {}
local CollectionService = { GetTagged = function() return TAGGED end }
local prevGame = game
game = { GetService = function(_, n)
  if n == "Players" then return Players elseif n == "RunService" then return RunService elseif n == "CollectionService" then return CollectionService end
  return prevGame:GetService(n) end, PrivateServerOwnerId = 0 }
local baseIndex = INST.__index
INST.__index = function(t, k)
  if k == "FindFirstChild" then return function(s, n) for _, c in ipairs(rawget(s, "__kids") or {}) do if c.Name == n then return c end end return nil end end
  if k == "IsA" then return function(s, c) return s.ClassName == c or (c == "BasePart" and s.ClassName == "Part") or c == "Instance" end end
  return baseIndex(t, k)
end
function mkPlayer(uid) local p = { UserId = uid, Name = "p" .. uid }; p.IsA = function(_, c) return c == "Player" end; return p end
local typeofReal = typeof
typeof = function(v) if type(v) == "table" and v.UserId and v.IsA then return "Instance" end return typeofReal(v) end
LOG = { spawns = {}, despawn = {}, cash = {}, xp = {}, notify = {}, track = {}, analytics = {} }
local nextId = 0
DEPS = {
  CombatService = {
    SpawnNPC = function(tid, cf, opts) nextId += 1; local rec = { Id = "npc" .. nextId, Alive = true, Model = Instance.new("Model"), Tid = tid, Opts = opts }; table.insert(LOG.spawns, rec); return rec end,
    DespawnNPC = function(id) table.insert(LOG.despawn, id); for _, r in ipairs(LOG.spawns) do if r.Id == id then r.Alive = false end end; return true end,
  },
  EconomyService = { AddCash = function(p, n, why) table.insert(LOG.cash, { p = p, n = n, why = why }) end },
  XPService = { AddXP = function(p, n, why) table.insert(LOG.xp, { p = p, n = n, why = why }) end },
  NotificationService = { Notify = function(p, msg) table.insert(LOG.notify, { p = p, msg = msg }) end },
  MissionService = { TrackProgress = function(p, t, n) table.insert(LOG.track, { p = p, t = t, n = n }) end },
  AnalyticsService = { Log = function(ev, uid, props) table.insert(LOG.analytics, { ev = ev, uid = uid, props = props }) end },
  MonetizationService = { PassivePerMin = function() return 3000 end },
  DataService = { GetProfile = function() return {} end },
}
'''

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local G = require(node("Configs/CheckpointGuardConfig"))
local S = require(node("Services/CheckpointGuardService"))
local LAUNCHED = G.Live.OwnerFirst -- codebot_v142: false (everyone); 1-6 prove the owner-first rule still works
G.Live.OwnerFirst = true
local NOW = 1000
S._SetClock(function() return NOW end)
S.Init(DEPS)

-- ── 1. site ──
local booth = Instance.new("Part")
booth.CFrame = CFrame.new(500, 3.5, 200)
for i, p in ipairs({ { 1, -3.5, -5.8 }, { -35.5, -3.5, -6.6 }, { -1.7, -3.5, -4.4 }, { -32.9, -3.5, 1.8 }, { 6.5, 10.5, 7 } }) do
  local a = Instance.new("Attachment"); a.Name = "WE_GuardPost" .. i
  a.WorldCFrame = CFrame.new(500 + p[1], 3.5 + p[2], 200 + p[3])
  if i == 5 then a:SetAttribute("WE_Static", true) end
  a.Parent = booth
end
booth.Parent = Instance.new("Folder")
local site = S.SiteFromBooth(booth)
check(site ~= nil and #site.Posts == 5 and site.Static[5] == true and site.Static[1] == false and site.Id == "CP_500_200", "site: 5 posts, the tower post Static, id " .. tostring(site and site.Id))
S._Sites()[site.Id] = site

-- ── 2. wake ──
local owner, other = mkPlayer(470626172), mkPlayer(9)
PLAYERS = { owner, other }
local here = Vector3.new(520, 3, 190)
check(S.Step(site, {}, { here }, NOW) == "asleep" and #LOG.spawns == 0, "a non-live player near: nothing wakes")
check(S.Step(site, { Vector3.new(900, 3, 200) }, {}, NOW) == "asleep", "a live player far away: asleep")
check(S.Step(site, { here }, { here }, NOW) == "wake" and #LOG.spawns == 5, "a live player within WakeStuds: 5 guards")
local r1 = LOG.spawns[1]
check(r1.Tid == "CheckpointGuard" and r1.Opts.GroupId == "CP." .. site.Id and r1.Opts.NoRespawn == true and r1.Opts.Leash == G.SiteRadius + G.LeashExtra, "SpawnNPC: CheckpointGuard, GroupId, NoRespawn, leash " .. tostring(r1.Opts.Leash))
check(LOG.spawns[5].Opts.Static == true and LOG.spawns[1].Opts.Static == false, "the tower guard is a Static post")
check(r1.Opts.TargetFilter(owner) == true and r1.Opts.TargetFilter(other) == false, "TargetFilter: live players only (owner-first)")

-- ── 3. kills + cleared once ──
local helper = mkPlayer(470626172) -- the owner's own hits are on LastHitBy too
LOG.spawns[1].LastHitBy = { [470626172] = NOW - 5, [9] = NOW - 2 }
for i = 1, 4 do
  LOG.spawns[i].Alive = false
  S._OnDeath({ Id = LOG.spawns[i].Id, GroupId = "CP." .. site.Id, Killer = owner, ByUnit = i == 3 })
end
check(#LOG.cash == 0, "4 of 5 down: no cleared bonus yet")
NOW += 10
LOG.spawns[5].Alive = false
S._OnDeath({ Id = LOG.spawns[5].Id, GroupId = "CP." .. site.Id, Killer = owner, ByUnit = false })
local want = G.ClearedCash(3000, false)
check(#LOG.cash == 1 and LOG.cash[1].p == owner and LOG.cash[1].n == want and LOG.cash[1].why == "checkpoint", "last guard down: the live contributor gets $" .. want)
check(#LOG.xp == 1 and LOG.xp[1].n == G.Cleared.XP, "... and " .. G.Cleared.XP .. " XP")
check(#LOG.notify == 1 and string.find(LOG.notify[1].msg, "Checkpoint cleared +$6,000 +250 XP", 1, true) ~= nil, "one toast: " .. tostring(LOG.notify[1] and LOG.notify[1].msg))
check(#LOG.track == 1 and LOG.track[1].t == "Checkpoint" and LOG.track[1].n == 1, "mission objective Checkpoint +1")
local kills = 0
for _, a in ipairs(LOG.analytics) do if a.ev == "checkpoint_guard_kill" then kills += 1 end end
check(kills == 5, "checkpoint_guard_kill per guard (army kills included): " .. kills)
check(site.Contrib[9] ~= nil and #LOG.cash == 1, "the non-live helper (uid 9) is a contributor but is never paid")
S._OnDeath({ Id = LOG.spawns[5].Id, GroupId = "CP." .. site.Id, Killer = owner })
check(#LOG.cash == 1, "a repeated death event pays nothing more")
check(site.Awake == false and site.ClearedAt == NOW, "the site is cleared (timer started)")

-- ── 4. respawn ──
NOW += 100
check(S.Step(site, { here }, { here }, NOW) == "asleep", "100 s later: no respawn (180)")
NOW += 81
local onPost = site.Posts[1].Position
check(S.Step(site, { here }, { here, onPost }, NOW) == "blocked", "a player standing on a post: no respawn on top of him")
check(S.Step(site, { here }, { here }, NOW) == "wake" and #LOG.spawns == 10 and site.Cycle == 2, "181 s later, near a live player: the group respawns (cycle 2)")
for i = 6, 10 do
  LOG.spawns[i].Alive = false
  S._OnDeath({ Id = LOG.spawns[i].Id, GroupId = "CP." .. site.Id, Killer = owner })
end
check(#LOG.cash == 1, "cleared again 191 s after the last bonus: the 300 s player cooldown holds")
NOW += 200
check(S.Step(site, { here }, { here }, NOW) == "wake", "respawned again")
for i = 11, 15 do
  LOG.spawns[i].Alive = false
  S._OnDeath({ Id = LOG.spawns[i].Id, GroupId = "CP." .. site.Id, Killer = owner })
end
check(#LOG.cash == 2, "after the cooldown a new cycle pays again")

-- ── 5. sleep ──
NOW += 200
S.Step(site, { here }, { here }, NOW)
local before = #LOG.despawn
check(S.Step(site, { Vector3.new(2000, 3, 2000) }, {}, NOW) == "sleep" and #LOG.despawn - before == 5, "nobody live near: all 5 despawned (no NPC slot)")

-- ── 6. map / go ──
check(S.MapList(other) == nil, "map rows only for live players")
local rows = S.MapList(owner)
check(#rows == 1 and rows[1].Up == true, "map: the checkpoint is hostile while guards are up / ready")
site.ClearedAt = NOW - 30
rows = S.MapList(owner)
check(rows[1].Up == false and rows[1].T == 150, "map: cleared with the respawn countdown (" .. tostring(rows[1].T) .. " s)")
check(#S.GoTargets() == 0, "GO skips a cleared checkpoint")
site.ClearedAt = nil
check(#S.GoTargets() == 1, "GO points at a checkpoint with guards up")

-- ── 7. config ──
G.Live.OwnerFirst = LAUNCHED
check(G.Live.Enabled == true and G.Live.OwnerFirst == false and G.RespawnSeconds == 180 and G.LiveForAll() and G.LiveFor(9) and G.LiveFor(12345), "codebot_v142: live for everyone (OwnerFirst=false), respawn 180 s")
check(G.ClearedCash(0, false) == 2500 and G.ClearedCash(1e6, false) == 25000 and G.ClearedCash(3000, true) == 3000, "cleared cash: floor $2,500, cap $25,000, private servers half")

-- ── 8. codebot_v142: everyone + the shared protection rule + keep-out ──
check(r1.Opts.TargetFilter(other) == true and r1.Opts.TargetFilter(owner) == true, "everyone live: a non-owner (uid 9) is a target")
local SHIELD = {}
DEPS.CombatService.IsSpawnInvulnerable = function(p) return SHIELD[p.UserId] == "spawn" end
DEPS.CombatService.IsNoviceShielded = function(p) return SHIELD[p.UserId] == "novice" end
SHIELD[9] = "spawn"
check(r1.Opts.TargetFilter(other) == false and S.Protected(other), "spawn shield: never targeted")
SHIELD[9] = "novice"
check(r1.Opts.TargetFilter(other) == false, "novice shield: never targeted")
SHIELD[9] = nil
check(r1.Opts.TargetFilter(other) == true and not S.Protected(other), "shield over: targeted again")
DEPS.CombatService.IsSpawnInvulnerable = function() error("boom") end
check(r1.Opts.TargetFilter(other) == true, "a failing shield check never breaks targeting")
check(G.KeepOutStuds == 130, "KeepOutStuds 130")
local ZONES = {}
for i, pz in ipairs(PLOTS) do table.insert(ZONES, { Name = "Plot" .. i, X = pz[1], Z = pz[2], Half = 160 }) end
for _, pz in ipairs(POOLS) do table.insert(ZONES, { Name = pz[1], X = pz[2], Z = pz[3], Half = 0 }) end
table.insert(ZONES, { Name = "EmergencySpawn", X = 0, Z = 0, Half = 0 })
for _, b in ipairs({ { "Town.CP_N", 0, -310 }, { "Town.CP_E", 310, 0 }, { "Town.CP_S", 0, 310 }, { "Town.CP_W", -310, 0 }, { "Depot.CP_W", -1483, 0 }, { "Armory.CP_E", 1483, 0 } }) do
  local hit, d = S.KeepOutHit(Vector3.new(b[2], 0, b[3]), ZONES)
  check(hit == nil, "keep-out: detailed " .. b[1] .. " is clear of every plot / spawn")
end
for _, b in ipairs({ { "Depot.CP_E", -1127, 0, "Pool_Depot" }, { "Armory.CP_W", 1127, 0, "Pool_Armory" }, { "Sites.Hawk", 17.5, -478, nil } }) do
  local hit, d = S.KeepOutHit(Vector3.new(b[2], 0, b[3]), ZONES)
  check(hit ~= nil and (b[4] == nil or hit == b[4]), "keep-out: " .. b[1] .. " would get no guards (" .. tostring(hit) .. ", " .. tostring(d and math.floor(d)) .. " studs)")
end
check(S.KeepOutHit(Vector3.new(-800, 0, -400 + 160 + 129), ZONES) ~= nil and S.KeepOutHit(Vector3.new(-800, 0, -400 + 160 + 131), { ZONES[1] }) == nil, "keep-out measures from the plot pad edge")
S._SetKeepZones(ZONES)

print(string.format("CHECKPOINT GUARDS TEST: %d failed", fails))
if fails > 0 then error("failed") end
'''

# codebot_v142: the real plot positions + vehicle pools (keep-out test 8)
import re as _re  # noqa: E402
_bc = (SH / "Configs/BaseConfig.luau").read_text(encoding="utf-8")
_plots = _re.findall(r"Vector3\.new\((-?\d+), 0\.5, (-?\d+)\)", _bc.split("PlotPositions = {", 1)[1].split("} :: { Vector3 }", 1)[0])
_wc = (SH / "Configs/WorldConfig.luau").read_text(encoding="utf-8")
_pools = _re.findall(r'\{ Id = "(Pool_\w+)", X = (-?\d+), Z = (-?\d+)', _wc)
assert len(_plots) == 10 and len(_pools) >= 4, (_plots, _pools)
# plot gate vehicle pads: plot-local (-62, 222) turned by PlotFrame.PlotYaw (faces the map centre)
def _gate(x, z):
    x, z = int(x), int(z)
    if abs(x) >= abs(z):
        return (x + 222, z + 62) if x < 0 else (x - 222, z - 62)
    return (x - 62, z + 222) if z < 0 else (x + 62, z - 222)
for _i, (_x, _z) in enumerate(_plots, 1):
    _gx, _gz = _gate(_x, _z)
    _pools.append(("Gate_P%d" % _i, str(_gx), str(_gz)))
DATA = "PLOTS = {%s}\nPOOLS = {%s}\n" % (", ".join("{%s, %s}" % p for p in _plots), ", ".join('{"%s", %s, %s}' % p for p in _pools))

chunks = [PRELUDE, EXTRA, DATA]
for key, path in MODS.items():
    chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
chunks.append(TEST)
with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
    f.write("\n".join(chunks))
    path = f.name
luau = os.environ.get("LUAU", "luau")
r = subprocess.run([luau, path], capture_output=True, text=True)
out = r.stdout.strip()
print(out if os.environ.get("VERBOSE") else ("\n".join(l for l in out.splitlines() if l.startswith("FAIL") or l.startswith("CHECKPOINT GUARDS")) or out))
if r.returncode != 0:
    print(r.stderr.strip()[-2500:])
    sys.exit(1)
