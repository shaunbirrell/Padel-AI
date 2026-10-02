# claude-bud JOB 24 (2026-09-29): army ATTACK mode + no debug visuals by default (docs/ARMY-ATTACK-ROOTCAUSE.md).
# ATTACK = the same steered block as FOLLOW (ArmyController): it advances on ONE sticky squad target, deploys into a
# line facing it at AttackStandoff (each unit's line cell by its permanent slot), folds back into the follow block when
# the target is down / out of the leash / the order changes. SquadOrdersService picks the target (server NPC roots) and
# its units only shoot and aim. Static pins + the attack acceptance sim (tools/sim/army_attack_sim.luau: the REAL
# FormationController / SoldierController; the v116 attack movement re-implemented as the "old" baseline).
import sys as _atk_sys
from pathlib import Path as _AtkP

if "ok" not in globals():
    _atk_fails = []

    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        _atk_fails.append(msg)
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _AtkP(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None

_atk_FC = "src/ReplicatedStorage/Shared/Util/FormationController.luau"
_atk_AC = "src/ServerScriptService/Server/Modules/ArmyController.luau"
_atk_SOS = "src/ServerScriptService/Server/Services/SquadOrdersService.luau"
_atk_CFG = "src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau"
_atk_DBG = "src/StarterPlayer/StarterPlayerScripts/Client/Modules/ArmyDebugClient.luau"


def _atk_code(path):
    return "\n".join(l.split("--", 1)[0] for l in (read(path) or "").splitlines())


def _atk_fn(src, head):
    i = src.find(head)
    if i < 0:
        return ""
    j = src.find("\nend\n", i)
    return src[i:j + 5] if j > 0 else src[i:]


def _atk_check(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J24 attack: " + msg)


_fca, _aca, _sosa = (_atk_code(p) for p in (_atk_FC, _atk_AC, _atk_SOS))
_cfga = read(_atk_CFG) or ""
_ia = _cfga.find("\tFollow3 = {")
_f3a = _cfga[_ia:_cfga.find("\n\t},", _ia)] if _ia >= 0 else ""

# 1. config: kill switch, tunables, debug off by default
for _k in ("AttackSteer = true,", "AttackStandoff = ", "AttackMaxSpeed = ", "AttackDeployStuds = ", "AttackDeploySeconds = ", "AttackSlideSpeed = ",
           "AttackLinePerRank = ", "AttackLineSpacing = ", "AttackAggroStuds = ", "AttackKeepExtraStuds = ", "AttackRetargetStuds = ", "AttackLeashStuds = "):
    _atk_check("\n\t\t" + _k in _f3a, "Follow3 has " + _k.rstrip(" =,"))
_atk_check("\n\t\tDebug = false," in _f3a and "470626172" in _f3a, "debug visuals OFF by default for everyone (Follow3.Debug = false); DebugUserIds kept for /armydebug")

# 2. the debug toggle: server gates on the attribute + DebugUserIds; client shows nothing without the attribute
_dfa = _atk_fn(_aca, "function ArmyController.DebugFor(")
_atk_check('player:GetAttribute("WE_ArmyDebug") == true' in _dfa and "isDebugUserId(player.UserId)" in _dfa, "server debug only after /armydebug by a DebugUserIds player")
_atk_check("if cfg().Debug == true and isDebugUser(p.UserId)" in _aca, "no automatic debug-on for the owner while Follow3.Debug is false")
_dbga = _atk_code(_atk_DBG)
_ena = _atk_fn(_dbga, "local function enabled(")
_atk_check('player:GetAttribute("WE_ArmyDebug") == true' in _ena, "client markers / labels / panel only while WE_ArmyDebug is on")
_atk_check('m:SetAttribute("WE_SlotPos", sp)' in _aca and 'player:SetAttribute("WE_ArmyPanel", nil)' in _aca, "slot positions / panel published only in debug (cleared when it goes off)")

# 3. formation: attack steering, line by permanent slot, sticky target, fold back on its own side
_sfa = _atk_fn(_fca, "function FormationController.SteerFrames(")
_atk_check('target = tp - F.Hd * n(cfg, "AttackStandoff", 36)' in _sfa, "ATTACK: the block steers to its own side of the target at AttackStandoff, facing it")
_atk_check('n(cfg, "AttackMaxSpeed", 16)' in _sfa and 'n(cfg, "AttackSlideSpeed", 8)' in _sfa, "ATTACK: a steady advance, slots slide into the line at a capped speed")
_atk_check("if atk == nil and F.AttackOn then" in _sfa and "t.Seed = -u" in _sfa, "attack over: re-forms on its own side of him (no sweep past him)")
_atk_check("LookVector" not in _sfa, "the steered block still never reads his look vector")
_lo = _atk_fn(_fca, "function FormationController.LineOffset(")
_atk_check(_lo != "" and "Magnitude" not in _lo and "Position" not in _lo, "line cell from the permanent slot index only (no distance, no nearest seat)")
_pt = _atk_fn(_fca, "function FormationController.PickTarget(")
_atk_check('n(cfg, "AttackRetargetStuds", 15)' in _pt and "return cur" in _pt, "sticky squad target (switch only for a clearly nearer one)")
_atk_check("function FormationController.BlockMoving(" in _fca, "soldiers walk while the block advances / deploys")
_atk_check("PivotTo" not in _fca + _aca and ":MoveTo(" not in _fca + _aca, "no teleport, no direct MoveTo in the controllers (SoldierController moves)")

# 4. ArmyController drives ATTACK; SquadOrdersService only aims / shoots in it
_atk_check("function ArmyController.AttackLive(" in _aca and 'local attackOn = state == "ATTACK" and ArmyController.AttackLive(player.UserId)' in _aca,
           "ArmyController drives ATTACK with the steered block (AttackSteer kill switch)")
_atk_check("a.F.Attack = if troot and troot.Parent then { Pos = troot.Position } else nil" in _aca, "the block's target = the squad target's server-side root")
_atk_check('if order == "Attack" and SquadOrdersService._AC.AttackLive(player.UserId) then\n\t\tattackAimOnly(player, st, unit, now)' in _sosa,
           "SquadOrdersService: an ATTACK unit only shoots / aims (no ring seats, no chase, no march in front of him)")
_aim = _atk_fn(_sosa, "local function attackAimOnly(")
_atk_check(_aim != "" and "_AF.Command(" not in _aim and "MoveTo" not in _aim and "pickShot(player, unit, tgt.Hum, tgt.Root, band, attackCands, CombatFairnessConfig.UnitAttackRequireLos == true)" in _aim,
           "attackAimOnly never walks; shots keep the line-of-sight rule")
_pst = _atk_fn(_sosa, "local function pickSquadTarget(")
_atk_check("FormationController.PickTargetTiered(" in _pst and "nearestHostile(centre, reach, false, player, attackCands, reach)" in _pst and "leash" in _pst,
           "one server-side squad target (nearestHostile's may-hit rules, leash to him)")
_atk_check("local function attackUnit(" in _sosa, "the v116 attackUnit kept for AttackSteer = false")

# 5. the attack acceptance sim (old = the v116 movement, new = the real controllers)
_atk_sys.path.insert(0, str(_AtkP("tools/sim").resolve()))
try:
    import run_attack_sim as _atk_sim
    _on = _atk_sim.run("new")
    _oo = _atk_sim.run("old")
except Exception as _ea:  # noqa: BLE001
    _on = _oo = "sim harness error: " + repr(_ea)
if _on is None:
    print("SKIP CLAUDE-BUD J24 attack sim: no Luau CLI")
else:
    _mn, _mo = _atk_sim.metrics(_on), _atk_sim.metrics(_oo)
    _names = ["stationary", "movingTarget", "targetDies", "switchTargets", "cancel", "maxArmy", "ownerWalks"]
    _atk_check(sorted(_mn) == sorted(_names) and sorted(_mo) == sorted(_names), f"sim ran all 7 attack tests in both modes ({sorted(_mn)})")
    for _n in _names:
        _m = _mn.get(_n)
        if _m is None:
            continue
        _atk_check(_m["teleports"] == 0 and _m["slotChanges"] == 0 and _m["crossings"] == 0, f"{_n}: 0 teleports, 0 slot changes, 0 path crossings")
        _atk_check(_m["minPair"] >= 2.0, f"{_n}: no clumping - soldiers never closer than 2 studs ({_m['minPair']:.2f}; v116 {_mo.get(_n, {}).get('minPair', -1):.2f})")
        _atk_check(_m["minOwner"] >= 3.0, f"{_n}: nobody runs through him (min {_m['minOwner']:.2f})")
        _atk_check(_m["slotErrMax"] <= 5.0, f"{_n}: deployed, every soldier within 5 studs of its line slot ({_m['slotErrMax']:.2f})")
        _atk_check(_m["settledRun"] <= 1.0, f"{_n}: deployed at a still target, soldiers stand and fire ({_m['settledRun']:.2f} studs/s moved)")
        _atk_check(_m["movesPerSec"] <= 5.1, f"{_n}: MoveTo <= 5 per soldier per second ({_m['movesPerSec']:.2f})")
        if _n != "cancel":
            _atk_check(_m["deployT"] >= 0 and _m["inBand"] >= 0.6, f"{_n}: deploys with the target in the fire band (deploy {_m['deployT']:.1f} s, in band {_m['inBand']:.2f})")
        if _n in ("targetDies", "cancel", "ownerWalks", "stationary", "switchTargets", "movingTarget", "maxArmy"):
            _atk_check(0 <= _m["reformT"] <= 5.0, f"{_n}: re-forms into the follow block within 5 s ({_m['reformT']:.2f} s)")
