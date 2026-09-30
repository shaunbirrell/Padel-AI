"""claude-bud JOB 40 part A: real-code tests for the base post guards + the one hostility rule (stand-ins: PRELUDE).

1. STATE MACHINE (the real GuardConfig.PostNext): IDLE -> ALERT (a hostile) -> ATTACK (after ReactionSeconds 0.5);
   ALERT -> RETURN (lost 3 s); ATTACK -> RETURN (no hostile 8 s); any -> RETURN past the leash (45); RETURN -> IDLE at
   the post; RETURN -> ALERT (a hostile near the post); DEAD; DEAD -> IDLE (respawned).
2. HOSTILITY (the real BaseGuards on a CombatService stand-in that answers like UnitMayHitPlayer / ArmyHostility /
   PvPBlockReason do in CombatService/init.luau): the table case -> today's JOB 20 rule vs the one rule:
   owner, clan ally, friend-not-clan, spawn-grace, novice victim, PvP off, owner shielded, enemy unit, own unit,
   an ally's unit, a shielded owner vs a unit. The only intended differences: a friend who is not in the clan (now
   hostile) and a novice / PvP-off / owner-shielded case (now never shot).
3. BUDGETS (the real GuardConfig): the per-target damage cap (30 / 12 for new players), MaxShootersPerBase 6, the pair
   limit.
Run: LUAU=path/to/luau(.exe) python tools/sim/run_base_guards_test.py"""
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
    "Configs/GuardConfig": SH / "Configs/GuardConfig.luau",
    "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
    "Configs/EconomyConfig": SH / "Configs/EconomyConfig.luau",
    "Modules/BaseGuards": SV / "Modules/BaseGuards.luau",
}

EXTRA = r'''
task = { spawn = function() end, wait = function() end, delay = function() end }
local function signal() local s = {}; s.Connect = function() return { Disconnect = function() end } end; return s end
BY_UID, ALL = {}, {}
local Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return ALL end, GetPlayerByUserId = function(_, uid) return BY_UID[uid] end }
local RunService = { IsStudio = function() return false end }
TAGGED = {}
local CollectionService = { GetTagged = function() return TAGGED end, HasTag = function() return false end }
local prevGame = game
game = { GetService = function(_, n)
  if n == "Players" then return Players elseif n == "RunService" then return RunService elseif n == "CollectionService" then return CollectionService elseif n == "PathfindingService" then return any end
  return prevGame:GetService(n) end, PrivateServerId = "", PrivateServerOwnerId = 0 }
Random = { new = function() return { NextNumber = function() return 0 end } end }
function mkP(uid, pos, clan)
  local root = { Position = pos, IsA = function(_, c) return c == "BasePart" end }
  local hum = { Health = 100, IsA = function(_, c) return c == "Humanoid" end }
  local char = { FindFirstChildOfClass = function() return hum end, FindFirstChild = function(_, n) if n == "HumanoidRootPart" then return root end return nil end }
  root.Parent = char
  local p = { UserId = uid, Name = "P" .. uid, DisplayName = "P" .. uid, Character = char, Clan = clan, attrs = {} }
  p.GetAttribute = function(self, k) return self.attrs[k] end
  BY_UID[uid] = p
  table.insert(ALL, p)
  return p
end
'''

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local GC = require(node("Configs/GuardConfig"))
local N = GC.PostNext

-- ── 1. the state machine ──
check(N("IDLE", { Target = false }) == "IDLE" and N("IDLE", { Target = true }) == "ALERT", "IDLE -> ALERT on a hostile")
check(N("ALERT", { Target = true, Since = 0.2 }) == "ALERT" and N("ALERT", { Target = true, Since = 0.5 }) == "ATTACK", "ALERT -> ATTACK after ReactionSeconds 0.5")
check(N("ALERT", { Target = false, LostFor = 2.9 }) == "ALERT" and N("ALERT", { Target = false, LostFor = 3 }) == "RETURN", "ALERT -> RETURN after 3 s lost")
check(N("ATTACK", { Target = false, LostFor = 7.9 }) == "ATTACK" and N("ATTACK", { Target = false, LostFor = 8 }) == "RETURN", "ATTACK -> RETURN after 8 s with no hostile")
check(N("ATTACK", { Target = true, FromPost = 46 }) == "RETURN" and N("ATTACK", { Target = true, FromPost = 44 }) == "ATTACK", "past the 45-stud leash -> RETURN")
check(N("RETURN", { Target = false, AtPost = true }) == "IDLE" and N("RETURN", { Target = false, AtPost = false, FromPost = 20 }) == "RETURN", "RETURN -> IDLE at the post")
check(N("RETURN", { Target = true, FromPost = 10 }) == "ALERT" and N("RETURN", { Target = true, FromPost = 42 }) == "RETURN", "RETURN -> ALERT only well inside the leash")
check(N("ATTACK", { Dead = true }) == "DEAD" and N("DEAD", { Dead = false }) == "IDLE", "DEAD; a respawn starts IDLE")

-- ── 2. hostility: today's JOB 20 rule vs the one rule ──
local BG = require(node("Modules/BaseGuards"))
local pvpOn = true
local novice = {}
local rule = {
  UnitMayHitPlayer = function(owner, victim)
    if owner ~= victim and owner.Clan ~= nil and owner.Clan == victim.Clan then return false, "ally" end
    if not pvpOn then return false, "pvp_off" end
    if owner == victim then return false, "self" end
    if novice[owner.UserId] then return false, "owner_shielded" end
    if novice[victim.UserId] then return false, "protected" end
    return true, "ok"
  end,
  ArmyHostility = function(attacker, owner)
    if not pvpOn then return false, "pvp_off" end
    if attacker == owner then return false, "self" end
    if attacker.Clan ~= nil and attacker.Clan == owner.Clan then return false, "ally" end
    if novice[owner.UserId] then return false, "protected" end
    return true, "ok"
  end,
  PvPBlockReason = function(a, v)
    if not pvpOn then return "pvp_off" end
    if novice[a.UserId] then return "owner_shielded" end
    return nil
  end,
}
local friends = {}
BG.Bind({ CombatService = rule, EngagementService = { AreFriends = function(a, b) return friends[a .. ":" .. b] == true or friends[b .. ":" .. a] == true end } })
local grace = {}
-- GateDefenseService.inSpawnGrace: no profile, the NOVICE shield check, the 4 s respawn grace (as in the real code)
local H = { IsAlly = function(ownerId, p) return p.Clan ~= nil and BY_UID[ownerId].Clan == p.Clan end, InSpawnGrace = function(p) return grace[p.UserId] == true or novice[p.UserId] == true end }
local owner = mkP(470626172, Vector3.new(0, 0, 0), "A")
local ally = mkP(2, Vector3.new(0, 0, 0), "A")
local friend = mkP(3, Vector3.new(0, 0, 0), nil)
local stranger = mkP(4, Vector3.new(0, 0, 0), nil)
friends["470626172:3"] = true
local function old(p) return not (p.UserId == owner.UserId or H.IsAlly(owner.UserId, p) or friends[owner.UserId .. ":" .. p.UserId]) and not H.InSpawnGrace(p) end
local function new(p) return BG.PlayerHostileOneRule(owner.UserId, p, H) end
print(string.format("  %-28s %-8s %-8s", "case", "JOB 20", "one rule"))
local rows = {
  { "owner", owner }, { "clan ally", ally }, { "friend, not in the clan", friend }, { "stranger", stranger },
}
for _, r in ipairs(rows) do print(string.format("  %-28s %-8s %-8s", r[1], tostring(old(r[2])), tostring(new(r[2])))) end
check(not new(owner) and not new(ally) and new(stranger), "the one rule: never the owner or his clan; a stranger is hostile")
check(old(friend) == false and new(friend) == true, "ROOT CAUSE: JOB 20 spared a friend who is not in the clan (his army did not); now hostile, like the army")
grace[4] = true
check(not new(stranger) and not old(stranger), "a spawn-graced stranger is spared by both (the grace only throttles)")
grace[4] = nil
novice[4] = true
check(old(stranger) == false and new(stranger) == false, "a novice-shielded victim: spared by both (JOB 20 through its spawn-grace check, now the rule itself)")
novice[4] = nil
novice[470626172] = true
check(old(stranger) == true and new(stranger) == false and not BG.UnitHostileOneRule(470626172, 4), "ROOT CAUSE: a novice-shielded OWNER's base still shot under JOB 20; now it fires at nobody (like his army)")
novice[470626172] = nil
pvpOn = false
check(old(stranger) == true and new(stranger) == false and not BG.UnitHostileOneRule(470626172, 4), "ROOT CAUSE: with PvP off the base still shot under JOB 20; the one rule never shoots players or units")
pvpOn = true
check(BG.UnitHostileOneRule(470626172, 4) and not BG.UnitHostileOneRule(470626172, 2) and not BG.UnitHostileOneRule(470626172, 470626172), "units: an enemy's soldiers yes; an ally's / his own no")

-- ── 3. budgets ──
check(GC.CapDamage(0, 50, false) <= 30 and GC.CapDamage(0, 50, true) <= 12 and GC.CapDamage(30, 10, false) == 0, "the damage cap per target per second: 30 (12 for new players)")
check(GC.MaxShootersPerBase == 6 and GC.Posts.LeashStuds == 45 and GC.Posts.RespawnSeconds == 45 and GC.Posts.Health == 150 and GC.Posts.FireRate == 1.2 and GC.Posts.Damage == 10 and GC.Posts.Range == 90,
  "the post numbers: leash 45, respawn 45, HP 150, 1.2 shots/s, 10 dmg, range 90; 6 shooters a base")
local log = {}
local allowed = 0
for i = 1, 5 do if GC.AllowPair(log, 1, 2, i) then allowed += 1 end end
check(allowed == (GC.Rewards.PairMax or 3), "the kill-credit pair limit (" .. allowed .. " in a window)")

print(string.format("BASE GUARDS TEST: %d failed", fails))
if fails > 0 then error("failed") end
'''


def main():
    chunks = [PRELUDE, EXTRA]
    for key, path in MODS.items():
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
    chunks.append(TEST)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True)
    out = r.stdout.strip()
    print(out if os.environ.get("VERBOSE") else ("\n".join(l for l in out.splitlines() if l.startswith("FAIL") or l.startswith("BASE GUARDS TEST")) or out))
    if r.returncode != 0:
        print(r.stderr.strip()[-2000:])
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
