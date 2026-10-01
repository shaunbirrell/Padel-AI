# claude-bud JOB 54 (2026-10-01): night lighting on the bases (helipad / dock floods, the lit gate sign, a beacon, glow
# markers) + the night exposure. Executed inside tools/BuyPathStatic.py (ok / bad).
import os as _j54_os
import re as _j54_re
import subprocess as _j54_sp
import sys as _j54_sys
from pathlib import Path as _J54P

if "ok" not in globals():
    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        print("FAIL " + msg)


def _j54_src(p):
    q = _J54P(p)
    return q.read_text(encoding="utf-8").replace("\r\n", "\n") if q.is_file() else ""


_LC = _j54_src("src/ReplicatedStorage/Shared/Configs/LightingConfig.luau")
_n2 = _LC.split("Night2 = {")[1].split("\n\t},")[0] if "Night2 = {" in _LC else ""
(ok if ("Enabled = true," in _n2 and "OwnerFirst = true, -- NEW-OWNER-FIRST" in _n2 and "PerBaseLights = 4," in _n2) else bad)(
    "CLAUDE-BUD J54: LightingConfig.Night2 is owner-first, 4 more night lights per base")
_m = _j54_re.search(r"MaxLights = (\d+)", _LC)
(ok if (_m and int(_m.group(1)) <= 120) else bad)("CLAUDE-BUD J54: MaxLights stays <= 120")
_NL = _j54_src("src/ServerScriptService/Server/Modules/NightLights.luau")
_bp = _NL.split("local function buildPlot2")[1].split("\nend\n")[0] if "local function buildPlot2" in _NL else ""
(ok if ("Instance.new(\"PointLight\")" not in _bp and "Instance.new(\"SpotLight\")" not in _bp and _bp.count("addLight(") == 2 and _bp.count("post(f,") == 2) else bad)(
    "CLAUDE-BUD J54: every new light goes through addLight (the MaxLights counter, Shadows off, the WE_LowOff halving, the night tag)")
(ok if "Enum.Material.Neon" not in _bp else bad)("CLAUDE-BUD J54: no always-on Neon (glow parts flip at night only)")
_sp = _NL.split("function NightLights.SyncPlot")[1].split("\nend\n")[0] if "function NightLights.SyncPlot" in _NL else ""
(ok if ("n2Live(ownerUserId)" in _sp and "cur.Owner == ownerUserId and cur.Gate == gateCf" in _sp) else bad)(
    "CLAUDE-BUD J54: per-plot extras are owner-first by the plot owner and never rebuilt for the same owner + gate")
_G = _j54_src("src/ServerScriptService/Server/Services/GateDefenseService.luau")
(ok if ("NL.SyncPlot, plotId, ownerUserId, gateCf" in _G and "ClearPlot(plotId)" in _G.split("local function clearDefense")[1].split("\nend\n")[0]) else bad)(
    "CLAUDE-BUD J54: the plot sync builds the extras (claim / rejoin / restart) and the owner leaving clears them")
_QG = _j54_src("src/StarterPlayer/StarterPlayerScripts/Client/Modules/QualityGovernor.luau")
(ok if "nl.DescendantAdded:Connect" in _QG and "WE_LowAddHook" in _QG else bad)(
    "CLAUDE-BUD J54: low quality also keeps late-arriving night lights halved (a claim after low mode)")
_NE = _j54_src("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/NightExposureController.luau")
(ok if ("RC.Live(LC.Night2, player.UserId)" in _NE and "RenderStepped" not in _NE and "Heartbeat" not in _NE and "task.wait(math.max(1" in _NE) else bad)(
    "CLAUDE-BUD J54: the night exposure is owner-first, throttled (no per-frame work)")
_BS = _j54_src("src/StarterPlayer/StarterPlayerScripts/Client/Bootstrap.client.luau")
(ok if 'safeInit("NightExposureController"' in _BS else bad)("CLAUDE-BUD J54: NightExposureController is started by the client bootstrap")
_e = dict(_j54_os.environ)
if "LUAU" not in _e and _e.get("LUAU_COMPILE"):
    _c = _e["LUAU_COMPILE"].replace("luau-compile", "luau")
    if _j54_os.path.isfile(_c):
        _e["LUAU"] = _c
if _e.get("LUAU"):
    _r = _j54_sp.run([_j54_sys.executable, "tools/sim/run_night_lights_test.py"], capture_output=True, text=True, env=_e)
    (ok if (_r.returncode == 0 and "NIGHT LIGHTS TEST: 0 failed" in _r.stdout) else bad)(
        "CLAUDE-BUD J54: run_night_lights_test.py (per-base 7 <= 40, total <= 120, halving, owner-first, no churn, rebuild, exposure)")
