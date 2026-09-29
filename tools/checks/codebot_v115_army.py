# v115 (Code Bot Roblox, 2026-09-29): army follow root cause 3 (docs/ARMY-FOLLOW-ROOTCAUSE-3.md).
# The FORMATION follows him (a breadcrumb-trail block BEHIND him, no side wings, no wheel / orbit), soldiers follow
# their permanent slots. Static pins + the acceptance simulation (tools/sim/army_follow_sim.luau, the real
# FormationController + SoldierController + ArmyConfig.Follow3 in the Luau CLI; 10 owner tests, thresholds inside).
import os as _v115_os
import re as _v115_re
import sys as _v115_sys
from pathlib import Path as _V115P

if "ok" not in globals():
    _v115_fails = []

    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        _v115_fails.append(msg)
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _V115P(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None

_v115_SC = "src/ServerScriptService/Server/Modules/SoldierController.luau"
_v115_AC = "src/ServerScriptService/Server/Modules/ArmyController.luau"
_v115_FC = "src/ReplicatedStorage/Shared/Util/FormationController.luau"
_v115_CFG = "src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau"
_v115_RA = "src/StarterPlayer/StarterPlayerScripts/Client/Modules/RigAnimator.luau"
_v115_DBG = "src/StarterPlayer/StarterPlayerScripts/Client/Modules/ArmyDebugClient.luau"
_v115_ADM = "src/ServerScriptService/Server/Services/AdminService.luau"
_v115_SOS = "src/ServerScriptService/Server/Services/SquadOrdersService.luau"
_v115_BOOT = "src/StarterPlayer/StarterPlayerScripts/Client/Bootstrap.client.luau"


def _v115_code(path):
    return "\n".join(l.split("--", 1)[0] for l in (read(path) or "").splitlines())


def _v115_fn(src, head):
    i = src.find(head)
    if i < 0:
        return ""
    j = src.find("\nend\n", i)
    return src[i:j + 5] if j > 0 else src[i:]


def _v115_check(cond, msg):
    (ok if cond else bad)("CODEBOT v115 army: " + msg)


_sc5, _ac5, _fc5 = (_v115_code(p) for p in (_v115_SC, _v115_AC, _v115_FC))
_raw_ac5, _raw_sc5 = read(_v115_AC) or "", read(_v115_SC) or ""

# 1. one writer: MoveTo / PivotTo only in SoldierController; no per-frame loops; no wheel / orbit
_v115_check(_sc5.count(":MoveTo(") == 2 and _sc5.count("PivotTo(") == 1, "SoldierController: the only MoveTo (Move / Stop) and the only PivotTo (Reposition)")
_v115_check(":MoveTo(" not in _ac5 + _fc5 and "PivotTo(" not in _ac5 + _fc5, "ArmyController / FormationController never move a soldier themselves")
_v115_check("ctx.Pivot" not in _sc5 and "WheelStepDeg" not in _sc5 and "Pivot =" not in _ac5, "no wheel: no unit runs round the outside of him (v114 orbit)")
_v115_check(not _v115_re.search(r"Heartbeat|RenderStepped|\.Stepped|TweenService|PathfindingService", _ac5 + _fc5), "controllers: no per-frame loops, no tweens, no pathfinding for formation moves")
_v115_check("CreatePath" in _sc5 and "StuckPathSeconds" in _sc5, "PathfindingService only as the stuck fallback (SoldierController)")
_v115_check(":Destroy(" not in _ac5 + _sc5 + _fc5 and ":Clone(" not in _ac5 + _sc5 + _fc5, "controllers never destroy / clone a soldier (no-despawn guarantees)")

# 2. formation: trail block behind him, persistent slots, no nearest-slot logic
for _k in ("function FormationController.NewTrail(", "function FormationController.TrailStep(", "function FormationController.RowFrame(",
           "function FormationController.Layout(", "function FormationController.Plan(", "function FormationController.Assign("):
    _v115_check(_k in _fc5, "FormationController has " + _k.split(".")[1].rstrip("("))
for _gone in ("SlotLocal", "SideRow", "NewAnchor", "SlotWorld", "MoveLead(", "LateralStuds", "FrontBack"):
    _v115_check(_gone not in _fc5 + _ac5, "v114 flank / anchor code gone: " + _gone)
_asg5 = _v115_fn(_fc5, "function FormationController.Assign(")
_v115_check(_asg5 != "" and not any(k in _asg5 for k in ("Magnitude", "Position", "Dist", "Dot(")) and not _v115_re.search(r"(?<!i)pairs\(units", _asg5), "slot assignment never uses distance or iteration order")
_v115_check(":PointToWorldSpace(Vector3.new(x, 0, 0))" in _fc5, "world slot = its row frame's PointToWorldSpace(constant local offset)")
_v115_check('m:SetAttribute("FormationSlot", idx)' in _ac5 and "SLOT CHANGE" in _raw_ac5 and "warn(" in _v115_fn(_ac5, "local function publish("),
            "FormationSlot attribute published; every slot change WARN-logged")
_v115_check("FormationController.Plan(a.F, living, pos, proot.CFrame.LookVector, vel, dt, snap, escOf, c, ownerVelNow)" in _ac5, "ArmyController drives the trail-block plan")
_v115_check("REPOSITION" in _raw_sc5 and "warn(" in _v115_fn(_sc5, "function SoldierController.Reposition("), "every reposition (PivotTo) is WARN-logged")
_v115_check("CatchUpStartStuds" in _sc5 and "CatchUpEndStuds" in _sc5, "catch-up toward its OWN slot with hysteresis")

# 3. collisions / network owner unchanged
_afr5 = read("src/ServerScriptService/Server/Modules/ArmyFollow.luau") or ""
_v115_check("PhysicsService:CollisionGroupSetCollidable(ArmyFollow.Group, ArmyFollow.Group, false)" in _afr5, "soldier x soldier collisions off")
_v115_check("SetNetworkOwner(nil)" in (read(_v115_SOS) or ""), "SetNetworkOwner(nil) kept")

# 4. config
_cfg5 = read(_v115_CFG) or ""
_i5 = _cfg5.find("\tFollow3 = {")
_f35 = _cfg5[_i5:_cfg5.find("\n\t},", _i5)] if _i5 >= 0 else ""
_keys5 = ["Enabled", "Rollout", "UpdateSeconds", "Formation", "VelSmoothSeconds", "MovingOnSpeed", "MovingOffSpeed", "TrailSmoothSeconds",
          "CrumbStuds", "TrailKeepStuds", "TangentStuds", "FirstRowStuds", "RowSpacing", "ColSpacing", "AisleStuds", "ColumnsMax",
          "RowTurnDegPerSec", "RowDeadbandDeg", "FoldDeg", "OwnerClearStuds", "EscortTrail", "Debug", "DebugUserIds", "DebugLogSeconds",
          "DebugPublishStuds", "ArriveStuds", "LeaveStuds", "ReissueStuds", "RefreshSeconds", "CatchUpStartStuds", "CatchUpEndStuds",
          "CatchUpPerStud", "MaxSpeed", "FarStuds", "StuckRepositionSeconds"]
_miss5 = [k for k in _keys5 if not _v115_re.search(r"\n\t\t" + k + r" = ", _f35)]
_v115_check(_f35 != "" and not _miss5, f"ArmyConfig.Follow3 has every v115 tunable (missing {_miss5})")
_v115_check("\t\tEnabled = true," in _f35 and '\t\tFormation = "TrailBlock",' in _f35, "Follow3 on, TrailBlock formation (Enabled = false = the v113 path, kill switch)")
_v115_check("\t\tDebug = true," in _f35 and "470626172" in _f35, "debug overlay on, default for the owner UserId only")

# 5. debug toggle, client markers, escorts
_adm5 = read(_v115_ADM) or ""
_v115_check('{ "WE_ArmyDebug", "/armydebug" }' in _adm5 and 'cmd == "armydebug"' in _adm5 and '"/armydebug"' in _adm5 and 'player:SetAttribute("WE_ArmyDebug", want)' in _adm5,
            "/armydebug (admin allowlist) toggles WE_ArmyDebug")
_dbg5 = _v115_code(_v115_DBG)
_v115_check(all(k in _dbg5 for k in ("p.Anchored = true", "p.CanCollide = false", "p.CanQuery = false", "p.CanTouch = false", "Enum.Material.Neon",
                                      '"S%02d / Slot %02d', "WE_SlotPos", "WE_ArmyDebug", "OwnerUserId")), "client slot markers (anchored neon, no collide / query / touch) + 'S07 / Slot 07' labels, his units only")
_v115_check('safeInit("ArmyDebugClient"' in (read(_v115_BOOT) or ""), "ArmyDebugClient started by the client Bootstrap")
_v115_check('m:SetAttribute("WE_SlotPos", sp)' in _ac5 and "if debugOn then" in _ac5 and "DebugLogSeconds" in _ac5, "server publishes WE_SlotPos + throttled per-soldier log only in debug")
_ra5 = _v115_code(_v115_RA)
_v115_check("escTrailStep(host" in _ra5 and "L.Index * spacing" in _ra5 and "WE_EscSide" not in _ra5, "client escorts follow their unit's own path behind it (no side wings; stable index)")
_v115_check("WE_EscSide" not in _ac5, "no WE_EscSide wings published")

# 6. build pins, never-touch
for _rel5 in ("src/ServerScriptService/Server/Services/DataService.luau", "src/ServerScriptService/Server/Services/BaseService.luau", "src/ServerScriptService/Server/EarlyRemotes.server.luau"):
    pass  # v116 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v116.py: #_v115_check('SetAttribute("WE_Build", 115)' in (read(_rel5) or ""), "WE_Build=115 " + _rel5.rsplit("/", 1)[-1])
# v116 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v116.py: #_v115_check("WE_Build=115" in (read("src/ServerScriptService/Server/Services/DataService.luau") or ""), "DataService log WE_Build=115")
_v115_check("PreferMesh = true" not in (read("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau") or ""), "PreferMesh stays OFF")

# 7. the acceptance simulation (10 owner tests; thresholds live in the sim; any FAIL line fails the build)
_v115_sys.path.insert(0, str(_V115P("tools/sim").resolve()))
try:
    import run_army_sim as _v115_sim
    _o5 = _v115_sim.run()
except Exception as _e5:  # noqa: BLE001
    _o5 = "FAIL sim harness error: " + repr(_e5)
if _o5 is None:
    print("SKIP CODEBOT v115 army sim: no Luau CLI (LUAU / ~/.local/bin/luau)")
else:
    _p5 = [l for l in _o5.splitlines() if l.startswith("PASS ")]
    _b5 = [l for l in _o5.splitlines() if l.startswith("FAIL ")]
    _m5 = _v115_sim.metrics(_o5)
    _v115_check(len(_m5) == 10, f"sim ran all 10 owner tests ({sorted(_m5)})")
    _v115_check(len(_p5) > 100 and not _b5 and "FAILS 0" in _o5, f"sim: every threshold met ({len(_p5)} pass, {len(_b5)} fail)")
    for _l5 in _b5:
        bad("CODEBOT v115 army sim: " + _l5[5:])
