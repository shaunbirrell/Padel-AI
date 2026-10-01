# claude-bud JOB 43 (2026-10-01): army vs army brawl (+ the Army Kills board check).
import os as _j43_os
import re as _j43_re
import subprocess as _j43_sp
import sys as _j43_sys
from pathlib import Path as _J43P

if "ok" not in globals():
    _j43_fails = []

    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        _j43_fails.append(msg)
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _J43P(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None


def _j43(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J43: " + msg)


def _j43_src(path):
    return (read(path) or "").replace("\r\n", "\n")


def _j43_code(path):
    s = _j43_re.sub(r"--\[\[.*?\]\]", "", _j43_src(path), flags=_j43_re.S)
    return "\n".join(l.split("--", 1)[0] for l in s.splitlines())


_SV = "src/ServerScriptService/Server/"
_CF = "src/ReplicatedStorage/Shared/Configs/"
_AC = _j43_src(_CF + "ArmyConfig.luau")
_j43("ArmyBrawl = {\n\t\tEnabled = true,\n\t\tOwnerFirst = true," in _AC, "ArmyConfig.ArmyBrawl Enabled + OwnerFirst = true (OFF = soldiers ignore enemy soldiers, as before)")
_SQ = _j43_code(_SV + "Services/SquadOrdersService.luau")
_pst = _SQ.split("local function pickSquadTarget")[1].split("\nend\n")[0]
_pdt = _SQ.split("local function pickDefendTarget")[1].split("\nend\n")[0]
_j43('consider(c.Hum, c.Root, "Unit", c.Owner, 0)' in _pst and "ArmyBrawl.LiveFor(player.UserId)" in _pst,
     "ATTACK / SEND pick: enemy soldiers are candidates (behind ArmyBrawl.LiveFor)")
_j43('Kind = "Unit"' in _pdt and "ArmyBrawl.Candidates(player, squadByUser" in _pdt, "FOLLOW / HOLD defend pick: the nearest enemy soldier when no player is in reach (the fight continues after he dies)")
_j43("CombatService.ArmyHostility" in _pst and "CombatService.ArmyHostility" in _pdt, "the ONE shared army rule decides who is a candidate (ArmyHostility)")
_CS = _j43_code(_SV + "Services/CombatService/init.luau")
_uu = _CS.split("function CombatService.ApplyUnitUnitHit")[1].split("\nend\n")[0] if "function CombatService.ApplyUnitUnitHit" in _CS else ""
_j43("CombatService.ArmyHostility(owner, victimOwner)" in _uu and "NS.allowsAttack(owner)" in _uu and "unitHitHandler" in _uu
     and "NoteArmyKill(owner)" in _uu and "XPService.AddXP, owner, xp" in _uu and "PairCreditPer10Min" in _uu,
     "ApplyUnitUnitHit: the rule re-checked per shot, a live unit only, kills -> ARMY KILLS + XP (pair-capped)")
_j43(_CS.index("local function logUnitHit(") < _CS.index("function CombatService.ApplyUnitUnitHit"), "ApplyUnitUnitHit is defined after the locals it uses")
_AB = _j43_code(_SV + "Modules/ArmyBrawl.luau")
_j43(not _j43_re.search(r"PivotTo|SetPrimaryPartCFrame|TakeDamage|Health\s*=|Teleport", _AB + _pst + _pdt),
     "no teleport / snap / raw damage in the brawl pick (CombatService deals the damage)")
_LB = _j43_src(_CF + "LeaderboardConfig.luau")
_j43("LeaderboardConfig.ArmyKillsBoardLive = true" in _LB, "the ARMY KILLS board is live for everyone (Code Bot v156; admins stay excluded at write and read)")

_luau = _j43_os.environ.get("LUAU")
if _luau is None and _j43_os.environ.get("LUAU_COMPILE"):
    _cand = _j43_os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    _luau = _cand if _j43_os.path.isfile(_cand) else None
if _luau:
    _r = _j43_sp.run([_j43_sys.executable, "tools/sim/run_army_brawl_test.py"], capture_output=True, text=True, env=dict(_j43_os.environ, LUAU=_luau))
    _j43(_r.returncode == 0 and "ARMY BRAWL TEST: 0 failed" in _r.stdout, "run_army_brawl_test.py (root-cause trace + the candidate rules)")
else:
    print("SKIP CLAUDE-BUD J43: Luau CLI tests (set LUAU)")
