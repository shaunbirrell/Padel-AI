# claude-bud JOB 52 (2026-10-01): ATTACK at range (ArmyOrdersConfig.AttackRange, owner-first), one set of radii for the
# whole order, flat distances, the nothing-in-range card (PIN / SEND by server id), capped ARMY KILLS credit.
import os as _j52_os
import re as _j52_re
import subprocess as _j52_sp
import sys as _j52_sys
from pathlib import Path as _J52P

if "ok" not in globals():
    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        print("FAIL " + msg)


def _j52(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J52: " + msg)


def _src(p):
    q = _J52P(p)
    return q.read_text(encoding="utf-8").replace("\r\n", "\n") if q.is_file() else ""


_AOC = _src("src/ReplicatedStorage/Shared/Configs/ArmyOrdersConfig.luau")
_ar = _AOC.split("AttackRange = {")[1].split("\n\t},\n")[0] if "AttackRange = {" in _AOC else ""
_m = _j52_re.search(r"SeekStuds = (\d+)", _ar)
_j52("Enabled = true," in _ar and "OwnerFirst = true, -- NEW-OWNER-FIRST" in _ar and _m and 300 <= int(_m.group(1)) <= 500,
     "AttackRange owner-first with 300 <= SeekStuds <= 500 (%s)" % (_m.group(1) if _m else "?"))
_AP = _src("src/ServerScriptService/Server/Modules/ArmyPlan.luau")
_j52("local seekR, leashR, chainR = C.AttackRadii(player.UserId)" in _AP and "C.SeekRadius" not in _AP.split("local function thinkClear")[1].split("\nend\n")[0]
     and "Leash = leashR" in _AP, "the running ATTACK plan uses ONE set of radii (seek / chain / leash) for seek, march answer and fight")
_j52("Reach = seek, LeashFrom = from, Leash = leash" in _AP and "pickWith(pick, player, st, ownerRoot(player), { Centre = from, Reach = far" in _AP,
     "the probe and the nearest-beyond scan go through the ONE pick (pickWith -> pickSquadTarget)")
_j52(not _j52_re.search(r"PivotTo|\.CFrame\s*=", _AP.split("function ArmyPlan.NearestBeyond")[1].split("function ArmyPlan.CreditsArmyKill")[0]) if "function ArmyPlan.NearestBeyond" in _AP else False,
     "no PivotTo / CFrame writes in the new ATTACK code")
_cr = _AP.split("function ArmyPlan.CreditsArmyKill")[1].split("\nend\n")[0] if "function ArmyPlan.CreditsArmyKill" in _AP else ""
_j52('plan.Kind == "Clear"' in _cr and "KillCreditPerHour" in _cr and "3600" in _cr, "ARMY KILLS credit: only HIS ordered ATTACK target group, capped per rolling hour (no AFK farm)")
_NC = _src("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ArmyNearestController.luau")
_j52("RequestArmySend, target)" in _NC and not _j52_re.search(r"FireServer\([^)]*Vector3", _NC), "the client sends only the server's id (\"N:<npcId>\"), never a position")
_AT = _src("src/ServerScriptService/Server/Modules/ArmyTargets.luau")
_j52('elseif kind == "N" then' in _AT and "npcLookup(id)" in _AT, "ArmyTargets resolves \"N:<npcId>\" on the server")
_e = dict(_j52_os.environ)
if "LUAU" not in _e and _e.get("LUAU_COMPILE"):
    _c = _e["LUAU_COMPILE"].replace("luau-compile", "luau")
    if _j52_os.path.isfile(_c):
        _e["LUAU"] = _c
if _e.get("LUAU"):
    _r = _j52_sp.run([_j52_sys.executable, "tools/sim/run_army_command_test.py"], capture_output=True, text=True, env=_e)
    _j52(_r.returncode == 0 and "ARMY COMMAND TEST: 0 failed" in _r.stdout and "JOB 52 ON: an enemy 380 studs away" in _r.stdout,
         "run_army_command_test.py (OFF = the bug at 260 / 380; ON = marches + fights; 450 = the distance card; height)")
    _j52_sp.run(["git", "checkout", "-q", "--", "docs/proof/army-command"])
else:
    print("SKIP CLAUDE-BUD J52: Luau CLI tests (set LUAU)")
