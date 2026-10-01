# claude-bud JOB 53 (2026-10-01): the Defence upgrades you can SEE (turret plating / guns, gate, vault tiers + the gate's
# damage states), from the SAVED profile.Endgame.Defence levels. Executed inside tools/BuyPathStatic.py (ok / bad).
import os as _j53_os
import re as _j53_re
import subprocess as _j53_sp
import sys as _j53_sys
from pathlib import Path as _J53P

if "ok" not in globals():
    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        print("FAIL " + msg)


def _j53_src(p):
    q = _J53P(p)
    return q.read_text(encoding="utf-8").replace("\r\n", "\n") if q.is_file() else ""


_EC = _j53_src("src/ReplicatedStorage/Shared/Configs/EndgameConfig.luau")
_dv = _EC.split("DefenceVisuals = {")[1].split("\n\t},")[0] if "DefenceVisuals = {" in _EC else ""
(ok if ("Enabled = true," in _dv and "OwnerFirst = true, -- NEW-OWNER-FIRST" in _dv and "TierAt = { 1, 4, 7, 10 }" in _dv) else bad)(
    "CLAUDE-BUD J53: EndgameConfig.DefenceVisuals is owner-first, tiers at L1 / 4 / 7 / 10")
_DV = _j53_src("src/ServerScriptService/Server/Modules/DefenceVisuals.luau")
_DVc = "\n".join(l.split("--", 1)[0] for l in _j53_re.sub(r"--\[\[.*?\]\]", "", _DV, flags=_j53_re.S).splitlines())
_pt = _DVc.split("local function part(")[1].split("\nend\n")[0] if "local function part(" in _DVc else ""
(ok if ("p.Anchored = true" in _pt and "p.CanCollide = false" in _pt and "p.CanQuery = false" in _pt and "p.CanTouch = false" in _pt) else bad)(
    "CLAUDE-BUD J53: every visual part is anchored, no-collide, no-query, no-touch (never blocks a shot, a raycast or a walk)")
(ok if (not _j53_re.search(r"Neon|PointLight|SpotLight|SurfaceLight|SurfaceGui|BillboardGui|WE_Building|Store_", _DVc)) else bad)(
    "CLAUDE-BUD J53: no Neon, no lights, no labels, no protected / store-prop names in DefenceVisuals")
(ok if "EndgameConfig.DefenceVisualsLive(ownerUserId)" in _DVc.split("function DefenceVisuals.Apply")[-1] else bad)(
    "CLAUDE-BUD J53: Apply builds nothing while the visuals are off for that base owner (OFF = the old base)")
_G = _j53_src("src/ServerScriptService/Server/Services/GateDefenseService.luau")
_sp = _G.split("local function syncPlotNow")[1].split("\nfunction GateDefenseService.SyncPlot")[0] if "local function syncPlotNow" in _G else ""
(ok if ("DefenceVisualsMod.Apply" in _sp and "eg.DefenceLevelFor(ownerUserId, tr)" in _sp and _sp.index("spawnGateBarriers(") < _sp.index("DefenceVisualsMod.Apply")) else bad)(
    "CLAUDE-BUD J53: syncPlotNow dresses the defences from the SAVED levels after the gate exists (rejoin / restart / resync)")
_ub = _G.split("local function updateGateBillboard")[1].split("\nend\n")[0] if "local function updateGateBillboard" in _G else ""
(ok if ("dv.GateDamage" in _ub and "DefenceVisualsLive(parts[1]:GetAttribute(\"OwnerUserId\"))" in _ub) else bad)(
    "CLAUDE-BUD J53: the gate damage states hang off the one HP funnel (updateGateBillboard), owner-first")
_so = _G.split("local function setGateBarrierOpen")[1].split("\nend\n")[0] if "local function setGateBarrierOpen" in _G else ""
(ok if ("Color3.fromRGB(55, 58, 62)" in _so and "Enum.Material.Metal" in _so and "WE_DefColor" in _so) else bad)(
    "CLAUDE-BUD J53: a rebuilt gate goes back to its tier look; without the attribute it is the old look exactly")
_ES = _j53_src("src/ServerScriptService/Server/Services/EndgameService.luau")
(ok if ("T.DefenceNewLook" in _ES and "EndgameConfig.DefenceVisualsLive(uid)" in _ES) else bad)(
    "CLAUDE-BUD J53: buying into a new visual tier says what changed on his base (owner-first)")
_e = dict(_j53_os.environ)
if "LUAU" not in _e and _e.get("LUAU_COMPILE"):
    _c = _e["LUAU_COMPILE"].replace("luau-compile", "luau")
    if _j53_os.path.isfile(_c):
        _e["LUAU"] = _c
if _e.get("LUAU"):
    _r = _j53_sp.run([_j53_sys.executable, "tools/sim/run_defence_visuals_test.py"], capture_output=True, text=True, env=_e)
    (ok if (_r.returncode == 0 and "DEFENCE VISUALS TEST: 0 failed" in _r.stdout) else bad)(
        "CLAUDE-BUD J53: run_defence_visuals_test.py (tiers, every piece clean + in budget, OFF, damage stages 0-1-2-0-3-0)")
