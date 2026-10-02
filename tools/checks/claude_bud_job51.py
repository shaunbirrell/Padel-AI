# claude-bud JOB 51 (2026-10-01, P0): ONE shared hostility / protection rule (Server/Modules/Hostility, bound by
# CombatService) used by EVERY NPC target pick; /guarddebug logs; pinned + tools/sim/run_plaza_guards_test.py.
import os as _j51_os
import re as _j51_re
import subprocess as _j51_sp
import sys as _j51_sys
from pathlib import Path as _J51P

if "ok" not in globals():
    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        print("FAIL " + msg)


def _j51(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J51: " + msg)


def _j51_src(p):
    q = _J51P(p)
    return q.read_text(encoding="utf-8").replace("\r\n", "\n") if q.is_file() else ""


_CC = _j51_src("src/ReplicatedStorage/Shared/Configs/CombatConfig.luau")
_blk = _CC.split("SharedHostility = {")[1].split("\n}")[0] if "SharedHostility = {" in _CC else ""
_j51("Enabled = true," in _blk and "OwnerFirst = false, -- PUBLIC (Code Bot v220: everything public, Shaun 2026-10-02 07:51); was NEW-OWNER-FIRST" in _blk, "CombatConfig.SharedHostility present, public since codebot_v220 (was owner-first)")
_N = _j51_src("src/ServerScriptService/Server/Services/CombatService/CombatNPC.luau")
_calls = _j51_re.findall(r"(?<!function )CombatNPC\.NearestPlayer\(([^\n]*)\)", _N)
_j51(len(_calls) >= 3 and all(c.rstrip().endswith("rec") for c in _calls), "every NPC target pick calls NearestPlayer with its record (%d calls)" % len(_calls))
# replacement for the retired BuyPathStatic squadfair v3 pin: a stance NPC still targets the nearest player first
_j51("\tlocal target, dist = CombatNPC.NearestPlayer(rec.Root.Position, rec.Def.AggroRange, nil, rec)\n\tif target and g and provoked then\n\t\tg.LastContact = now -- contact keeps a provoked group fighting" in _N,
     "squadfair v3 (replacement): a stance NPC targets the nearest player (through the shared rule), contact keeps a provoked group fighting")
_np = _N.split("function CombatNPC.NearestPlayer")[1].split("\nend\n")[0] if "function CombatNPC.NearestPlayer" in _N else ""
_j51("local mayTarget = B.mayTarget" in _np and "okRule and okFilter" in _np, "NearestPlayer applies THE shared rule (B.mayTarget) to every candidate")
_j51("if not (tState and now < tState.InvulnerableUntil) and rng:NextNumber() < chance then" in _N,
     "the NPC damage path still honours InvulnerableUntil and the hit roll (no forced damage, no FX-only hits)")
_H = _j51_src("src/ServerScriptService/Server/Modules/Hostility.luau")
_j51("InvulnerableUntil" not in _H and "d.IsNoviceShielded(player)" in _H and "d.PvPBlock(attacker, victim)" in _H,
     "Hostility holds no copy of a reason: every answer comes from a bound CombatService function")
_I = _j51_src("src/ServerScriptService/Server/Services/CombatService/init.luau")
_j51("Hostility.Bind({" in _I and "mayTarget = CombatService.NpcMayTarget" in _I and "PvPBlock = pvpBlock," in _I, "CombatService binds the existing reasons and hands the rule to CombatNPC")
_CP = _j51_src("src/ServerScriptService/Server/Services/CheckpointGuardService.luau")
_j51("pcall(cs.ProtectedReason, p)" in _CP, "CheckpointGuardService.Protected calls the shared rule (no copy)")
_AD = _j51_src("src/ServerScriptService/Server/Services/AdminService.luau")
_j51('cmd == "guarddebug"' in _AD and '"[GuardTarget]' in _N and '"[GuardShot]' in _N and '"[NpcHit]' in _I, "/guarddebug + the [GuardTarget] / [GuardShot] / [NpcHit] logs")
_e = dict(_j51_os.environ)
if "LUAU" not in _e and _e.get("LUAU_COMPILE"):
    _c = _e["LUAU_COMPILE"].replace("luau-compile", "luau")
    if _j51_os.path.isfile(_c):
        _e["LUAU"] = _c
if _e.get("LUAU"):
    _r = _j51_sp.run([_j51_sys.executable, "tools/sim/run_plaza_guards_test.py"], capture_output=True, text=True, env=_e)
    _j51(_r.returncode == 0 and "PLAZA GUARDS TEST: 0 failed" in _r.stdout, "run_plaza_guards_test.py (mechanism reproduced, fix, cases table, OFF == OLD)")
else:
    print("SKIP CLAUDE-BUD J51: Luau CLI tests (set LUAU)")
