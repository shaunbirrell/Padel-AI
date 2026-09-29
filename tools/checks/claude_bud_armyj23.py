# claude-bud JOB 23 (2026-09-29): army formation turn transitions (docs/ARMY-FOLLOW-ROOTCAUSE-4.md).
# The block is ONE steered body (FormationController.SteerFrames, Follow3.Steer): position steered along his path with
# his velocity fed forward (accel / brake / speed caps), heading from his MOVEMENT only (never his look vector) with
# angular inertia and a turn-rate cap = SlotLateralSpeed / the block's radius, pivot = the block's own centre; soldiers
# on one continuous speed law toward their OWN slot (the Following / CatchingUp names are labels only).
# Static pins + the turn-transition acceptance set A..J (tools/sim/army_follow_sim.luau with J23 = true: the REAL
# FormationController / SoldierController / Follow3 in the Luau CLI, judged while turning).
import re as _j23_re
import sys as _j23_sys
from pathlib import Path as _J23P

if "ok" not in globals():
    _j23_fails = []

    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        _j23_fails.append(msg)
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _J23P(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None

_j23_FC = "src/ReplicatedStorage/Shared/Util/FormationController.luau"
_j23_SC = "src/ServerScriptService/Server/Modules/SoldierController.luau"
_j23_AC = "src/ServerScriptService/Server/Modules/ArmyController.luau"
_j23_CFG = "src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau"
_j23_DBG = "src/StarterPlayer/StarterPlayerScripts/Client/Modules/ArmyDebugClient.luau"


def _j23_code(path):
    return "\n".join(l.split("--", 1)[0] for l in (read(path) or "").splitlines())


def _j23_fn(src, head):
    i = src.find(head)
    if i < 0:
        return ""
    j = src.find("\nend\n", i)
    return src[i:j + 5] if j > 0 else src[i:]


def _j23_check(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J23 army: " + msg)


_fcj, _scj, _acj = (_j23_code(p) for p in (_j23_FC, _j23_SC, _j23_AC))
_cfgj = read(_j23_CFG) or ""
_i = _cfgj.find("\tFollow3 = {")
_f3j = _cfgj[_i:_cfgj.find("\n\t},", _i)] if _i >= 0 else ""

# 1. config: the steered block on, every tunable present, kill switches kept
_keysj = ["Steer", "FormGain", "FormAccel", "FormBrake", "FormMaxSpeed", "FormSpeedMult", "TurnSlowFactor", "BubbleStuds", "WaitAheadStuds",
          "SlotLateralSpeed", "TurnGain", "TurnAccelSeconds", "SettleTurnPerSec", "SteerLeadSeconds", "SteerLeadMaxStuds", "SpeedDeadzoneStuds",
          "SpeedGain", "SpeedLatGain", "SpeedMaxBonus", "SpeedMaxSlow", "SpeedSmoothSeconds", "SpikeErrStuds", "DebugPanelSeconds"]
_missj = [k for k in _keysj if not _j23_re.search(r"\n\t\t" + k + r" = ", _f3j)]
_j23_check(_f3j != "" and not _missj, f"Follow3 has every JOB 23 tunable (missing {_missj})")
_j23_check("\t\tSteer = true," in _f3j and "\t\tEnabled = true," in _f3j, "Follow3.Steer on (false = the v115 trail rows); Follow3.Enabled kill switch kept")

# 2. formation: one steered body, heading from movement only, rate cap from the radius, pivot = its centre
_sf = _j23_fn(_fcj, "function FormationController.SteerFrames(")
_j23_check(_sf != "", "FormationController.SteerFrames exists")
_j23_check("LookVector" not in _sf and "ownerLook" not in _sf, "the steered heading never reads his look vector (a spin on the spot moves nothing)")
_j23_check("F.Hd = if cfg.SteerHeadingPath == true then FormationController.Tangent(t, s, cfg) else unitOr(flat(t.Vel), F.Hd)" in _sf and "if t.Moving then" in _sf,
           "desired heading = his smoothed MOVEMENT direction, only while he moves (Moving hysteresis)")
_j23_check('local omax = n(cfg, "SlotLateralSpeed", 10) / rad' in _sf, "turn-rate cap = SlotLateralSpeed / the block's radius (bigger armies turn slower)")
_j23_check('n(cfg, "TurnAccelSeconds", 0.4)' in _sf and "F.W = math.clamp(F.W + math.clamp(wt - F.W, -aw, aw), -omax, omax)" in _sf, "angular inertia (turn rate eased in over TurnAccelSeconds)")
_j23_check("local p = F.C - F.H * (r * rs - half)" in _sf, "rows = the block's centre + its heading x a constant offset (the pivot is the block's own centre, not him)")
_j23_check('vmax = math.max(0, vmax - math.abs(F.W) * rad * n(cfg, "TurnSlowFactor", 1))' in _sf, "the block travels slower while it turns (no slot faster than FormMaxSpeed)")
_j23_check('n(cfg, "FormBrake", 60)' in _sf and 'n(cfg, "FormAccel", 24)' in _sf, "position: accel / brake limited (continuous velocity, no coasting into him)")
_j23_check("local gap = target - ff * dt - F.C" in _sf, "position lands on its steering point (no one-tick lead toward him)")
_j23_check('local bubble = rad + n(cfg, "BubbleStuds", 3)' in _sf and "waiting = true" in _sf, "never steers into him; waits (heading held) while he walks back through it")
_j23_check("PivotTo" not in _fcj and ":MoveTo(" not in _fcj, "FormationController still never moves a soldier")
_plan = _j23_fn(_fcj, "function FormationController.Plan(")
_j23_check("frames = FormationController.SteerFrames(army, units, ownerPos, cells, last, dt, snap, cfg)" in _plan and "FormationController.RowFrame(t, r, dt, cfg)" in _plan,
           "Plan: steered block when Follow3.Steer, the v115 rows otherwise")
_j23_check("SlotSpeed = sv.Magnitude" in _plan, "every plan carries its slot's speed (debug panel / spike log)")
_asg = _j23_fn(_fcj, "function FormationController.Assign(")
_j23_check(_asg != "" and "Magnitude" not in _asg and "Position" not in _asg, "slot assignment unchanged: permanent, no distance (S01 keeps Slot01)")

# 3. soldier: one continuous speed law toward its OWN slot, no gain step at the CatchingUp label, no teleport added
_dr = _j23_fn(_scj, "function SoldierController.Drive(")
_j23_check('want = sb + num("SpeedGain", 0.9) * dead(e) + num("SpeedLatGain", 0.6) * math.max(0, lat - dz)' in _dr, "WalkSpeed = base + gain x error past a deadzone (continuous)")
_j23_check('want = cur + (want - cur) * (1 - math.exp(-dt / math.max(0.05, num("SpeedSmoothSeconds", 0.3))))' in _dr, "WalkSpeed eased over time (no step)")
_j23_check("local target = clearOf(goal + leadV)" in _dr, "the walk target is always its own slot (+ its slot's lead)")
_j23_check(_scj.count("PivotTo(") == 1 and _scj.count(":MoveTo(") == 2, "no new teleport / MoveTo path (Reposition stays the only PivotTo)")
_j23_check("reaim" in _dr and "cfg().Steer == true" in _dr, "a soldier nearing its MoveTo point off its slot is re-aimed (<= 1 MoveTo per tick)")

# 4. debug: panel + spike log (server), compact labels + panel + corner trails (client), all debug-only
_j23_check('player:SetAttribute("WE_ArmyPanel", string.format(' in _acj and "[ArmyDebug] SPIKE" in (read(_j23_AC) or "") and "formationDebug(player, a, living, plans, proot, now)" in _acj,
           "server: formation panel attribute + SPIKE log (heading data), debug only")
_dbgj = _j23_code(_j23_DBG)
_j23_check("WE_ArmyPanel" in _dbgj and "trailStep(player" in _dbgj and "STATE_LETTER" in _dbgj and "b.TextSize = 14" in _dbgj,
           "client: compact labels, the formation panel (14 px), corner-slot trails")
_j23_check("p.CanQuery = false" in _dbgj and "p.CanTouch = false" in _dbgj and "ResetOnSpawn = false" in _dbgj, "client debug parts inert; the panel survives respawn")

# 5. the acceptance set A..J (run while turning; see the doc for the v115 numbers on the same set)
_j23_sys.path.insert(0, str(_J23P("tools/sim").resolve()))
try:
    import run_army_sim as _j23_sim
    _oj = _j23_sim.run(j23=True)
except Exception as _ej:  # noqa: BLE001
    _oj = "FAIL sim harness error: " + repr(_ej)
if _oj is None:
    print("SKIP CLAUDE-BUD J23 army sim: no Luau CLI (LUAU / luau next to LUAU_COMPILE / ~/.local/bin/luau)")
else:
    _mj = _j23_sim.metrics(_oj, "J23,")
    _j23_check(len(_mj) == 10, f"sim ran A..J ({sorted(_mj)})")
    _cap = 0.8 * 40
    for _n, _m in sorted(_mj.items()):
        _j23_check(_m["slotChanges"] == 0 and _m["teleports"] == 0, f"{_n}: 0 slot changes, 0 teleports ({_m['slotChanges']:.0f}, {_m['teleports']:.0f})")
        _j23_check(_m["maxSlotSpeed"] <= _cap, f"{_n}: max slot speed {_m['maxSlotSpeed']:.1f} <= {_cap:.0f} (what a soldier can run)")
        _j23_check(_m["standMove"] <= 0.05, f"{_n}: turning on the spot moves no slot ({_m['standMove']:.2f})")
        if _n[0] in "ABCDEFGH":
            _j23_check(_m["maxErrMoving"] <= 6 and _m["maxCatching"] <= 1 and _m["meanErrMoving"] <= 2.5,
                       f"{_n}: while moving max slot error {_m['maxErrMoving']:.1f} <= 6, mean {_m['meanErrMoving']:.1f} <= 2.5, CatchingUp {_m['maxCatching']:.0f} <= 1")
        if _n[0] in "ABCFH":
            _j23_check(_m["minOwnerSlot"] >= 5.5, f"{_n}: every slot >= 5.5 studs from him ({_m['minOwnerSlot']:.2f})")
    _i_ = _mj.get("I_walkBack")
    _j_ = _mj.get("J_maxArmy")
    _j23_check(_i_ is not None and _i_["maxErrMoving"] <= 8 and _i_["maxCatching"] <= 2, f"I walk-back: max slot error <= 8, CatchingUp <= 2 ({_i_ and _i_['maxErrMoving']}, {_i_ and _i_['maxCatching']})")
    _j23_check(_j_ is not None and _j_["maxErrMoving"] <= 12 and _j_["maxCatching"] <= 4, f"J max army: max slot error <= 12, CatchingUp <= 4 of 8 ({_j_ and _j_['maxErrMoving']}, {_j_ and _j_['maxCatching']})")
