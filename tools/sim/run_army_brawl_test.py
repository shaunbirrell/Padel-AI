"""claude-bud JOB 43: army vs army brawl.

1. ROOT CAUSE (static trace of the code BEFORE the fix, git af3a858.. the commit before JOB 43 = HEAD of origin when this
   ran): SquadOrdersService.nearestHostile skips every model with OwnerUserId (army soldiers carry it), pickSquadTarget's
   candidate kinds are NPC / Player / Guard only, pickDefendTarget's are Player only -> an enemy soldier is never a
   target and the list empties when the enemy player dies. The same trace on the working tree: "Unit" candidates exist
   in both picks, behind ArmyBrawl.LiveFor, and the shot path routes "Unit" to CombatService.ApplyUnitUnitHit.
2. CANDIDATES (the REAL Modules/ArmyBrawl with a stub of THE shared rule ArmyHostility): own squad never; a clan ally,
   a protected (novice / new-player) owner, PvP off -> none; dead / rootless units never; out of reach never; nearest
   first; capped at MaxCandidates; an owner who left -> skipped. After the enemy PLAYER dies his soldiers are still
   candidates (the brawl continues).
Run: LUAU=path/to/luau(.exe) python tools/sim/run_army_brawl_test.py   (exit 1 on any failure; VERBOSE=1 prints all)"""
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
SQ = "src/ServerScriptService/Server/Services/SquadOrdersService.luau"


def trace(src: str):
    nh = src.split("local function nearestHostile")[1].split("\nend\n")[0] if "local function nearestHostile" in src else ""
    pst = src.split("local function pickSquadTarget")[1].split("\nend\n")[0] if "local function pickSquadTarget" in src else ""
    pdt = src.split("local function pickDefendTarget")[1].split("\nend\n")[0] if "local function pickDefendTarget" in src else ""
    kinds = sorted(set(re.findall(r'consider\([^)]*"(\w+)"', pst)) | ({"NPC"} if 'consider(attackCands.Hum[i], attackCands.Root[i], "NPC")' in pst else set()))
    dkinds = sorted(set(re.findall(r'Kind = "(\w+)"', pdt)))
    return {
        "skipsOwnedModels": 'not inst:GetAttribute("OwnerUserId")' in nh,
        "attackKinds": kinds,
        "defendKinds": dkinds,
        "unitShot": 'if kind == "Unit" then' in src and "CombatService.ApplyUnitUnitHit" in src,
    }


def main():
    out = []
    fails = 0

    def check(ok, msg):
        nonlocal fails
        out.append(("ok    " if ok else "FAIL  ") + msg)
        if not ok:
            fails += 1

    before = subprocess.run(["git", "show", "origin/phase-7-polish:" + SQ], capture_output=True, text=True, encoding="utf-8").stdout
    after = (ROOT / SQ).read_text(encoding="utf-8")
    tb, ta = trace(before), trace(after)
    out.append("BEFORE (origin/phase-7-polish): nearestHostile skips OwnerUserId models=%s; ATTACK candidate kinds=%s; FOLLOW/HOLD defend kinds=%s"
               % (tb["skipsOwnedModels"], tb["attackKinds"], tb["defendKinds"]))
    out.append("AFTER  (working tree):          ATTACK candidate kinds=%s; FOLLOW/HOLD defend kinds=%s; Unit shot path=%s"
               % (ta["attackKinds"], ta["defendKinds"], ta["unitShot"]))
    if "ArmyBrawl" not in before:
        check(tb["skipsOwnedModels"] and "Unit" not in tb["attackKinds"] and tb["defendKinds"] == ["Player"],
              "ROOT CAUSE: before the fix an enemy soldier is never a candidate (NPCs skip OwnerUserId; ATTACK = NPC/Player/Guard; FOLLOW = Player)")
    else:
        out.append("note  origin already carries the fix: the BEFORE trace is the fix itself (root cause recorded in Modules/ArmyBrawl.luau)")
    check("Unit" in ta["attackKinds"] and "Unit" in ta["defendKinds"] and ta["unitShot"], "FIX: enemy soldiers are candidates in both picks and the shot routes to ApplyUnitUnitHit")

    lua = PRELUDE + r'''
local function signal() return { Connect = function() return { Disconnect = function() end } end } end
local P = {}
local function mk(uid, clan) local p = { UserId = uid, Name = "P" .. uid, Clan = clan, Protected = false }; P[uid] = p; return p end
local A, B, C, D = mk(1, "red"), mk(2, "blue"), mk(3, "red"), mk(4, "green")
local Players = { GetPlayerByUserId = function(_, uid) return P[uid] end, PlayerAdded = signal(), PlayerRemoving = signal() }
local RunService = { IsStudio = function() return true end }
local prevGame = game
game = { GetService = function(_, n) if n == "Players" then return Players elseif n == "RunService" then return RunService end return prevGame:GetService(n) end }
PVP = true
local function hostile(att, own) -- a stand-in with the SAME decisions as CombatService.ArmyHostility
  if not PVP then return false, "pvp_off" end
  if att == own then return false, "self" end
  if att.Clan ~= nil and att.Clan == own.Clan then return false, "ally" end
  if own.Protected then return false, "protected" end
  return true, "ok"
end
local function unit(x, z, alive) return { Alive = alive ~= false, Humanoid = { Health = if alive == false then 0 else 100 }, Root = { Position = Vector3.new(x, 0, z), Parent = true }, Model = {} } end
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local AB = require(node("Modules/ArmyBrawl"))
local squads = {
  [1] = { Units = { unit(0, 0), unit(2, 0) } }, -- A's own
  [2] = { Units = { unit(30, 0), unit(10, 0), unit(200, 0), unit(5, 0, false) } }, -- B (enemy): one far, one dead
  [3] = { Units = { unit(8, 0) } }, -- C: A's clan mate
  [4] = { Units = { unit(12, 0) } }, -- D: enemy
  [99] = { Units = { unit(1, 0) } }, -- an owner who left
}
local c = AB.Candidates(A, squads, Vector3.zero, 50, hostile, 8)
local owners, dists = {}, {}
for _, x in ipairs(c) do table.insert(owners, x.Owner.UserId); table.insert(dists, math.floor(x.Dist)) end
print("candidates: owners " .. table.concat(owners, ",") .. " dists " .. table.concat(dists, ","))
check(#c == 3 and owners[1] == 2 and owners[2] == 4 and owners[3] == 2 and dists[1] == 10 and dists[2] == 12 and dists[3] == 30,
  "enemy soldiers in reach, nearest first (B 10, D 12, B 30); own squad, clan mate, dead, far and departed owners never")
check(#AB.Candidates(A, squads, Vector3.zero, 50, hostile, 2) == 2, "capped at MaxCandidates")
D.Protected = true
local c2 = AB.Candidates(A, squads, Vector3.zero, 50, hostile, 8)
local hasD = false
for _, x in ipairs(c2) do if x.Owner == D then hasD = true end end
check(not hasD and #c2 == 2, "a protected (novice / new-player) owner's soldiers are never targeted")
D.Protected = false
PVP = false
check(#AB.Candidates(A, squads, Vector3.zero, 50, hostile, 8) == 0, "PvP off: no soldier is ever a target")
PVP = true
-- the enemy PLAYER died: his soldiers are still candidates (the squad table is independent of his character)
B.Character = nil
check(#AB.Candidates(A, squads, Vector3.zero, 50, hostile, 8) == 3, "after the enemy player dies his soldiers are still targets: the brawl goes on")
local AC = require(node("Configs/ArmyConfig"))
check(AC.ArmyBrawl.Enabled == true and AC.ArmyBrawl.OwnerFirst == true and AB.LiveFor(1) == true, "ArmyBrawl Enabled, owner-first (Studio: live for every test player)")
print(string.format("ARMY BRAWL LUA: %d failed", fails))
if fails > 0 then error("failed") end
'''
    srcs = {"Modules/ArmyBrawl": SV / "Modules/ArmyBrawl.luau", "Configs/ArmyConfig": SH / "Configs/ArmyConfig.luau",
            "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau", "Configs/AdminConfig": SH / "Configs/AdminConfig.luau"}
    chunks = [lua.split("\nlocal fails = 0")[0]]
    for k, p in srcs.items():
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (k, p.read_text(encoding="utf-8")))
    chunks.append("local fails = 0" + lua.split("\nlocal fails = 0", 1)[1])
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True)
    lo = r.stdout.strip()
    out.extend(lo.splitlines())
    if r.returncode != 0 or "ARMY BRAWL LUA: 0 failed" not in lo:
        fails += 1
        out.append(r.stderr.strip()[-1500:])
    out.append("ARMY BRAWL TEST: %d failed" % fails)
    text = "\n".join(out)
    print(text if os.environ.get("VERBOSE") else "\n".join(l for l in out if l.startswith(("FAIL", "ARMY BRAWL TEST", "BEFORE", "AFTER"))))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
