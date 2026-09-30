# claude-bud JOB 32 (2026-09-30): enterable Central Plaza buildings (PlazaBuildingsConfig + the WorldKits PlazaHouse),
# the ONE line-of-sight / shot rule for every shooter (CombatConfig.LineOfSight + Shared/Util/LosRule), and the army
# holding at the door while its owner is inside (ArmyConfig.Indoors + Modules/Enterables). Static pins + the real-code
# test (tools/sim/run_plaza_test.py).
import os as _j32_os
import re as _j32_re
import subprocess as _j32_sp
import sys as _j32_sys
from pathlib import Path as _J32P

if "ok" not in globals():
    _j32_fails = []

    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        _j32_fails.append(msg)
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _J32P(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None


def _j32(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J32: " + msg)


def _j32_src(path):
    return (read(path) or "").replace("\r\n", "\n")


def _j32_code(path):
    return "\n".join(l.split("--", 1)[0] for l in _j32_src(path).splitlines())


_PB = _j32_src("src/ReplicatedStorage/Shared/Configs/PlazaBuildingsConfig.luau")
_WK = _j32_code("src/ServerScriptService/Server/Modules/WorldKits.luau")
_WP = _j32_code("src/ServerScriptService/Server/Modules/WorldPOI.luau")
_WF = _j32_code("src/ServerScriptService/Server/Modules/WorldFill.luau")
_CC = _j32_src("src/ReplicatedStorage/Shared/Configs/CombatConfig.luau")
_LR = _j32_code("src/ReplicatedStorage/Shared/Util/LosRule.luau")
_CD = _j32_code("src/ServerScriptService/Server/Services/CombatService/CombatDamage.luau")
_GD = _j32_code("src/ServerScriptService/Server/Services/GateDefenseService.luau")
_SO = _j32_code("src/ServerScriptService/Server/Services/SquadOrdersService.luau")
_PR = _j32_code("src/ServerScriptService/Server/Modules/Projectile.luau")
_PW = _j32_code("src/ServerScriptService/Server/Services/PremiumWeaponService.luau")
_CL = _j32_code("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/CombatController.luau")
_AC = _j32_code("src/ServerScriptService/Server/Modules/ArmyController.luau")
_AY = _j32_src("src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau")

# enterable buildings
# v133 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v133.py (MaxExtraParts 640 for the facade): #_j32("local PlazaBuildingsConfig = {\n\tEnabled = true,\n\tMaxExtraParts = 240," in _PB and "Rows = { NE_E1 = true, SW_S1 = true, NE_N1 = true, NW_W1 = true }" in _PB,
# v133 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v133.py (MaxExtraParts 640 for the facade): #"kill switch PlazaBuildingsConfig.Enabled; the 4 buildings facing the plaza flag; one allowance for their parts")
_j32("if tryPlaza(kitId, b) then" in _WK and "Ent.Register(tostring(b.Cluster.Name), b.CF" in _WK, "a flagged TownHouse row builds the PlazaHouse and registers it")
_j32('model:SetAttribute("WE_Enterable", true)' in _WP and "PBC.Rows[c.Id] == true" in _WP and "WorldKits.Add(model, k.Kit, kcf, kitOpts(k, text))" in _WP,
     "WorldPOI flags only the configured Town rows (its Add line unchanged)")
_j32("local plainParts = m.Parts - WorldKits.ExtraParts(model)" in _WP and "Parts = parts - (extraBy[cluster] or 0)" in _WK and "n -= WK.ExtraParts(inst)" in _WF,
     "every budget counts the plain kits (no row is dropped for the detail / enterable extras)")
_m = _j32_re.search(r'truss\(b, "PlazaLadder", (\d+(?:\.\d+)?), CFrame\.new\(-6\.7, H \+ 0\.4 \+ (\d+(?:\.\d+)?), 6\.6\)', _WK)
_ok_ladder = False
if _m:
    _h, _c = float(_m.group(1)), 11 + 0.4 + float(_m.group(2))
    _ok_ladder = abs((_c - _h / 2) - 11.4) < 0.05 and (_c + _h / 2) >= 22.8 + 2
# v133 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v133.py + tools/sim/run_hatch_test.py (the ladder moved into a real hatch; the character-sized climb test replaces the span pin): #_j32(_ok_ladder, "the roof ladder runs from the upper floor (11.4) to >= 2 above the roof (22.8)")
# the one LOS rule
_j32("CombatConfig.LineOfSight = {\n\tUnified = true," in _CC, "kill switch CombatConfig.LineOfSight.Unified")
_j32("function LosRule.HitCast(" in _LR and "function LosRule.SightRespect(" in _LR and "LosRule.IsCharacterPart(inst)" in _LR and "p:AddToFilter(inst)" in _LR,
     "LosRule: solid parts stop shots and sight, see-through parts never do, shots can hit character limbs")
_j32("LosRule.HitCast(origin, unit * range, params)" in _CD and "LosRule.SightRespect(respectCanCollide == true)" in _CD,
     "player guns / assist / claims / splash (CombatDamage) use the rule")
_j32("LosRule.SightRespect(RaidConfig.Defense.LosRespectCanCollide == true)" in _GD, "base turrets, gate guards and base guards use the rule")
_j32(_SO.count("losParams.RespectCanCollide = LosRule.SightRespect(losParams.RespectCanCollide)") == 3, "all three army sight rays use the rule")
_j32("LosRule.HitCast(rec.Pos, seg, rec.Params)" in _PR and _PW.count("LosRule.HitCast(") == 2 and "HitCast(origin, direction * reach, W2.shotFilter())" in _CL,
     "projectiles, vehicle guns and the client shot preview use the rule")
# the army at the door, never teleported
_j32('ArmyConfig.Indoors = {\n\tEnabled = true,\n}' in _AY and "Enterables.At(pos)" in _AC and "lookVec = held.Face" in _AC and "vel = Vector3.zero" in _AC
     and "FormationController.Plan(a.F, living, pos, lookVec, vel" in _AC and "if held then" in _AC, "owner inside / on the roof: the army forms up outside the door, facing it (no speed, no snap)")
_j32(_AC.count("PivotTo") == _j32_code("src/ServerScriptService/Server/Modules/ArmyController.luau").count("PivotTo") and "PivotTo" not in _AC.split("claude-bud JOB 32", 1)[-1][:1500],
     "no teleport / PivotTo added for the indoor hold")

_luau = _j32_os.environ.get("LUAU")
if _luau is None and _j32_os.environ.get("LUAU_COMPILE"):
    _cand = _j32_os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    _luau = _cand if _j32_os.path.isfile(_cand) else None
if _luau:
    _r = _j32_sp.run([_j32_sys.executable, "tools/sim/run_plaza_test.py"], capture_output=True, text=True, env=dict(_j32_os.environ, LUAU=_luau))
    _j32(_r.returncode == 0 and "PLAZA TEST: 0 failed" in _r.stdout, "run_plaza_test.py (real WorldKits PlazaHouse + Enterables + LosRule)")
else:
    print("SKIP CLAUDE-BUD J32: Luau CLI test (set LUAU)")
