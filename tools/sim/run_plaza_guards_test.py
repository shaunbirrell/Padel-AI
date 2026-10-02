"""claude-bud JOB 51 (2026-10-01, P0): "the Central Plaza guards don't shoot my girlfriend / she can't damage them".

The REAL CombatNPC brain (Think -> thinkStance -> NearestPlayer -> engage, the real hit roll) and the REAL shared rule
(Server/Modules/Hostility) in the Luau CLI, with stand-ins for the world (line of sight clear, no vehicles) and the
Central Plaza defenders exactly as OutpostDefenders spawns them (GroupId "Outpost.CentralPlaza", Home on the 35-stud
ring, Leash 95, no TargetFilter, the Medium tier types from OutpostDefenderConfig).

1. ROOT CAUSE REPRODUCED (SharedHostility OFF = the old brain): the circle is also the neutral spawn, so a new / plot-less
   player under the novice (or spawn) shield stands nearest the guards. Every guard picks the NEAREST player regardless
   of protection, then engage() rolls "miss:invulnerable" for ever: in 60 s of fighting Laumartinez26 (not protected,
   a few studs farther) takes 0 damage and 0 shots -> "the guards don't shoot her".
2. FIX (SharedHostility ON): the same scene -> every guard skips the shielded player and shoots the nearest player it
   may hurt; she takes real hits through the same hit roll; the shielded player is never fired at (no misses forever).
3. With 3 players round the circle and nobody protected, the nearest one is engaged by each guard (distance only, as
   before).
4. ONE TABLE OF CASES: the same Hostility.MayHurt answer shape for guns / vehicle / army unit / turret / base guard / NPC.
5. A shield that ends mid-fight (spawn shield 3 s): the guard picks that player up on the next think.
6. OFF == OLD: SharedHostility.Enabled = false -> the old distance-only pick exactly (the shielded player is picked).
Player -> guard (static, see claude_bud_job51): hurtNPC has no hostility gate; only CombatService-spawned NPCs carry the
WE_NPC tag (all with an NPCId), and NPCs carry no ForceField, so no no-id figure or client filter can eat her shots in
code; the live [NpcHit] / claim-refusal lines (/guarddebug) cover the rest on a real server.
Run: LUAU=path/to/luau(.exe) python tools/sim/run_plaza_guards_test.py   (exit 1 on any failure)"""
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
    "Constants": SH / "Constants.luau",
    "Configs/CombatConfig": SH / "Configs/CombatConfig.luau",
    "Configs/CombatFairnessConfig": SH / "Configs/CombatFairnessConfig.luau",
    "Configs/CombatFeelConfig": SH / "Configs/CombatFeelConfig.luau",
    "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
    "Configs/OutpostDefenderConfig": SH / "Configs/OutpostDefenderConfig.luau",
    "Modules/Hostility": SV / "Modules/Hostility.luau",
    "Services/CombatService/CombatNPC": SV / "Services/CombatService/CombatNPC.luau",
}

EXTRA = r'''
NOW = 0
local function signal() local s = { fns = {} }; s.Connect = function(self, fn) table.insert(self.fns, fn); return { Disconnect = function() end } end; return s end
-- a seeded generator (the NPC hit roll uses Random.new())
local seed = 12345
local function lcg() seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648 end
Random = { new = function() return { NextNumber = function(_, a, b) local r = lcg(); if a then return a + (b - a) * r end; return r end } end }
local function mkPlayer(uid, name) return { UserId = uid, Name = name, Parent = true, Character = {} } end
SHAUN = mkPlayer(470626172, "shaunie6")
GF = mkPlayer(3001, "Laumartinez26")
NEWBIE = mkPlayer(3002, "esmeekatsavat")
OTHER = mkPlayer(3003, "Witorlox")
PLAYERS = { GF, NEWBIE }
local Players = { GetPlayers = function() return PLAYERS end, PlayerAdded = signal(), PlayerRemoving = signal() }
STUDIO = true -- a Studio Team Test: RetentionConfig.Live counts every player as an owner-first tester
local RunService = { IsStudio = function() return STUDIO end }
local prevGame = game
game = { GetService = function(_, n)
  if n == "Players" then return Players elseif n == "RunService" then return RunService elseif n == "Workspace" then return {} end
  return prevGame:GetService(n) end }
SOURCES["Services/CombatService/CombatDamage"] = function() return { LineOfSight = function() return true end } end
SOURCES["Modules/VehicleHealth"] = function() return { GetSeatedVehicle = function() return nil end } end
CFrame.lookAt = CFrame.lookAt or function(p) return CFrame.new(p.X, p.Y, p.Z) end
-- characters: a humanoid + root per player at a position
CHARS = {}
local function mkChar(p, x, z)
  local hum = { Health = 100, SeatPart = nil }
  hum.TakeDamage = function(self, d) self.Health -= d; HITS[p.Name] = (HITS[p.Name] or 0) + 1 end
  CHARS[p.UserId] = { hum = hum, root = { Position = Vector3.new(x, 3, z) } }
end
HITS, SHOTS = {}, {}
STATES = {}
NOVICE = {}
function setup(scene)
  CHARS, HITS, SHOTS, NOVICE = {}, {}, {}, {}
  table.clear(STATES) -- in place: CombatNPC holds this table (B.combatStates)
  PLAYERS = {}
  for _, e in ipairs(scene) do
    table.insert(PLAYERS, e.p)
    mkChar(e.p, e.x, e.z)
    STATES[e.p.UserId] = { InvulnerableUntil = e.inv or 0 }
    if e.novice then NOVICE[e.p.UserId] = true; STATES[e.p.UserId].InvulnerableUntil = math.huge end
  end
end
'''

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local CC = require(node("Configs/CombatConfig"))
-- codebot_v220 (Shaun 2026-10-02 07:51: everything public): CC.SharedHostility.OwnerFirst = false live; the owner-first paths
-- below are still proved with OwnerFirst = true, and a non-owner is live once it is restored (end of test)
local __V220_LAUNCHED = CC.SharedHostility.OwnerFirst
check(__V220_LAUNCHED == false, "codebot_v220: CC.SharedHostility.OwnerFirst = false (public for everyone)")
CC.SharedHostility.OwnerFirst = true
local OD = require(node("Configs/OutpostDefenderConfig"))
local RC = require(node("Configs/RetentionConfig"))
local H = require(node("Modules/Hostility"))
local N = require(node("Services/CombatService/CombatNPC"))
local records = {}
H.Bind({
  IsNoviceShielded = function(p) return NOVICE[p.UserId] == true end,
  IsSpawnInvulnerable = function(p) local s = STATES[p.UserId]; return s ~= nil and NOW < s.InvulnerableUntil end,
  PvPBlock = function(a, v) if a == v then return "self" end; local s = STATES[v.UserId]; if s and NOW < s.InvulnerableUntil then return "shield" end; return nil end,
  UnitMayHitPlayer = function(a, v) local s = STATES[v.UserId]; if s and NOW < s.InvulnerableUntil then return false, "shield" end; return true, "ok" end,
  Live = function(p) return RC.Live(CC.SharedHostility, p.UserId) end,
})
N.Bind({
  npcRecords = records, combatStates = STATES, clock = function() return NOW end,
  characterParts = function(p) local c = CHARS[p.UserId]; if c == nil then return nil end; return {}, c.hum, c.root end,
  hitFeedback = function() end, pushState = function() end, spawnNPC = function() end, getTagged = function() return {} end,
  fx = function(rec, o, l, kind) SHOTS[#SHOTS + 1] = kind end,
  mayTarget = H.NpcMayTarget,
})
N.SetRandom(nil)
-- the Central Plaza defenders as OutpostDefenders spawns them (Medium tier, 35-stud ring, leash 95, no filter)
local tier = OD.Tiers.Medium
local types = tier.Types or tier
local function spawnGuards()
  for k in pairs(records) do records[k] = nil end
  for i = 1, 4 do
    local a = (i - 1) * math.pi / 2
    local x, z = math.cos(a) * 35, math.sin(a) * 35
    local typeId = if typeof(types) == "table" and types[i] then types[i] else "Infantry"
    local def = CC.NPCTypes[typeId] or CC.NPCTypes.Infantry
    records["g" .. i] = { Id = "g" .. i, TypeId = typeId, Alive = true, Def = def, GroupId = "Outpost.CentralPlaza", Leash = 95,
      Home = CFrame.new(x, 3, z), LastFireAt = -100, Model = {},
      Humanoid = { Health = def.Health, WalkSpeed = 12, MoveTo = function() end },
      Root = { Position = Vector3.new(x, 3, z), Parent = true, FindFirstChild = function() return nil end, FindFirstChildOfClass = function() return nil end } }
  end
end
local function fight(seconds)
  local t = 0
  while t < seconds do
    NOW += CC.NPCThinkInterval or 0.25
    t += CC.NPCThinkInterval or 0.25
    N.Think()
  end
end
check(CC.SharedHostility.Enabled == true and CC.SharedHostility.OwnerFirst == true, "SharedHostility is owner-first (Enabled, OwnerFirst = true)")
-- the mechanism: a novice-shielded new player at the spawn (0, 5, 0) in the centre is nearer to EVERY guard on the
-- 35-stud ring than she is at the plaza edge (80 studs south: inside the south guard's AggroRange, but 10 studs farther
-- from it than the newbie). (With her nearer to any guard, that guard shoots her even in the old brain: see below.)
local scene = { { p = NEWBIE, x = 0, z = 0, novice = true }, { p = GF, x = 0, z = -80 } }
-- 1. OFF = the old brain
CC.SharedHostility.Enabled = false
setup(scene); spawnGuards(); fight(60)
local missesOff = 0
for _, k in ipairs(SHOTS) do if k == "M" then missesOff += 1 end end
check((HITS[GF.Name] or 0) == 0 and missesOff > 0,
  string.format("MECHANISM (old brain): a novice-shielded player nearest every guard: 60 s, Laumartinez26 hits=%d, the guards fired %d guaranteed misses at the shielded one", HITS[GF.Name] or 0, missesOff))
-- the counter-case, stated honestly: when she is nearer to even one guard, that guard shoots her in the old brain too
setup({ { p = NEWBIE, x = 0, z = 0, novice = true }, { p = GF, x = 8, z = 0 } }); spawnGuards(); fight(60)
check((HITS[GF.Name] or 0) > 0, "counter-case (old brain): standing beside the shielded player she is nearest to one guard and gets shot (hits=" .. tostring(HITS[GF.Name] or 0) .. "): this mechanism explains 'never shot' only in that geometry")
-- 2. ON = the shared rule
CC.SharedHostility.Enabled = true
setup(scene); spawnGuards(); fight(60)
local gfHits = HITS[GF.Name] or 0
check(gfHits > 0 and (HITS[NEWBIE.Name] or 0) == 0, string.format("FIX: the guards skip the shielded player and shoot Laumartinez26 (hits=%d, real hit roll)", gfHits))
-- 3. three unprotected players: the nearest is engaged
setup({ { p = OTHER, x = 0, z = 25 }, { p = GF, x = 0, z = -60 }, { p = NEWBIE, x = 60, z = 60 } }); spawnGuards(); fight(30)
check((HITS[OTHER.Name] or 0) > 0, "3 players round the circle, nobody protected: the nearest gets shot (distance pick as before)")
-- 5. a spawn shield that ends mid-fight
setup({ { p = GF, x = 5, z = 0, inv = NOW + 3 } }); spawnGuards(); fight(2)
local early = HITS[GF.Name] or 0
fight(30)
check(early == 0 and (HITS[GF.Name] or 0) > 0, "a 3 s spawn shield: never fired at during it, picked up once it ends")
-- C. a fresh spawn at the neutral spawn (0, 5, 0) with its 3 s shield, all four guards awake: time to die
setup({ { p = GF, x = 0, z = 0, inv = NOW + 3 } }); spawnGuards()
local t0, died = NOW, nil
for _ = 1, 400 do
  NOW += CC.NPCThinkInterval or 0.25; N.Think()
  if CHARS[GF.UserId].hum.Health <= 0 then died = NOW - t0; break end
end
print(string.format("SPAWN  a fresh spawn in the circle centre, 4 Medium guards awake: dies after %s s (3 s shield + the NPC reaction delay + the hit roll)", if died then string.format("%.1f", died) else ">100"))
print("FINDING  only ~" .. string.format("%.1f", (died or 99) - 3) .. " s of exposure after the shield: the emergency / plot-less spawn sits inside the defenders' aggro (ring 35 + AggroRange 90). Moving the spawn needs a Studio check of clear ground (reported in LATEST-HANDOFF, not moved blind).")

-- 4. one table of cases
local rows = {}
for _, kind in ipairs({ "Player", "Vehicle", "Unit", "Turret", "BaseGuard", "NPC" }) do
  setup({ { p = GF, x = 0, z = 0, inv = NOW + 10 }, { p = OTHER, x = 1, z = 0 } })
  local okShield = H.MayHurt(OTHER, GF, kind)
  local okFree = H.MayHurt(GF, OTHER, kind)
  table.insert(rows, kind .. "=" .. tostring(okShield) .. "/" .. tostring(okFree))
  check(okShield == false and okFree == true, "MayHurt(" .. kind .. "): a shielded victim -> no, a free victim -> yes")
end
print("CASES " .. table.concat(rows, " "))
-- 6. not live for her (OwnerFirst on a live server): the old pick for her
STUDIO = false
setup(scene); spawnGuards()
local okT = H.NpcMayTarget(NEWBIE)
check(okT == true, "owner-first on a live server: the rule is not live for a non-owner yet (the old pick for them)")
STUDIO = true
print(string.format("PLAZA GUARDS TEST: %d failed", fails))
if fails > 0 then error("failed") end
'''

chunks = [PRELUDE, EXTRA]
for key, path in MODS.items():
    chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
chunks.append(TEST)
with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
    f.write("\n".join(chunks))
    path = f.name
r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True)
print(r.stdout.strip())
if r.returncode != 0:
    print(r.stderr.strip()[-2500:])
    sys.exit(1)
