# claude-bud JOB 40 (2026-09-30): part E (PRIORITY) the base owner markers; parts A-D follow in this file.
# Static pins + the real-code tests (tools/sim/run_base_marker_test.py, ...).
import os as _j40_os
import re as _j40_re
import subprocess as _j40_sp
import sys as _j40_sys
from pathlib import Path as _J40P

if "ok" not in globals():
    _j40_fails = []

    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        _j40_fails.append(msg)
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _J40P(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None


def _j40(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J40: " + msg)


def _j40_src(path):
    return (read(path) or "").replace("\r\n", "\n")


def _j40_code(path):
    s = _j40_re.sub(r"--\[\[.*?\]\]", "", _j40_src(path), flags=_j40_re.S)
    return "\n".join(l.split("--", 1)[0] for l in s.splitlines())


_SV = "src/ServerScriptService/Server/"
_CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
_CF = "src/ReplicatedStorage/Shared/Configs/"

# ── part E: the base owner markers ──
_BMC = _j40_src(_CF + "BaseMarkerConfig.luau")
_BMS = _j40_code(_SV + "Services/BaseMarkerService.luau")
_BMK = _j40_code(_CL + "Controllers/BaseMarkerController.luau")
_j40("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = true, -- only UserId 470626172" in _BMC and "RetentionConfig.Live(BaseMarkerConfig.Live, userId)" in _BMC,
     "E: one owner-first kill switch (BaseMarkerConfig.Live, by viewer)")
_j40("MaxDistance = 5000," in _BMC and "HeightStuds = 70," in _BMC and "HideInsideStuds = 60," in _BMC and "FadeInsideStuds = 90," in _BMC,
     "E: visible from anywhere (5000), 70 studs up, hidden inside 60 / full past 90 (the v123 sign takes over)")
_on_top = sorted(p.relative_to(_J40P("src")).as_posix() for p in _J40P("src").rglob("*.luau") if "AlwaysOnTop = true" in p.read_text(encoding="utf-8"))
_j40(_on_top == ["ReplicatedStorage/Shared/Configs/BaseMarkerConfig.luau", "StarterPlayer/StarterPlayerScripts/Client/Controllers/TerritoryController.luau",
                 "StarterPlayer/StarterPlayerScripts/Client/Modules/ArmyDebugClient.luau", "StarterPlayer/StarterPlayerScripts/Client/Modules/ConsoleWaypoint.luau",
                 "StarterPlayer/StarterPlayerScripts/Client/Modules/ObjectiveMarker.luau"]
     and "g.AlwaysOnTop = BaseMarkerConfig.AlwaysOnTop" in _BMK,
     "E: AlwaysOnTop only in the base marker (the ONE documented exception) + the existing objective / waypoint / debug / contested labels")
_j40("RenderStepped" not in _BMS and "Heartbeat" not in _BMS and "task.wait(BaseMarkerConfig.RefreshSeconds)" in _BMS,
     "E: the server publishes data only (5 s refresh + events), nothing per frame")
_j40("task.wait(1 / BaseMarkerConfig.UpdateHz)" in _BMK and "RenderStepped" not in _BMK and "UpdateHz = 10," in _BMC, "E: the client step is 10 Hz for all markers together")
_j40('require(Shared.Util.NationTexture)' in _BMK and "rbxassetid" not in _BMK, "E: flag images only from the nation art (NationTexture / NationFlagIds), no new ids")
_j40("if BaseMarkerConfig.Live.Enabled ~= true or not BaseMarkerConfig.LiveFor(player.UserId) then" in _BMK, "E: OFF / not live for the viewer = no marker")
_j40("ReplicatedStorage:WaitForChild(BaseMarkerConfig.FolderName, 120)" in _BMK and "FolderName = \"WE_BaseMarkers\"" in _BMC,
     "E: streaming-safe data (ReplicatedStorage), bounded wait")
_j40("one documented exception" in (_j40_src("CLAUDE.md")).lower() or "base owner marker" in _j40_src("CLAUDE.md").lower(), "E: the world-label exception is written in CLAUDE.md")

_luau = _j40_os.environ.get("LUAU")
if _luau is None and _j40_os.environ.get("LUAU_COMPILE"):
    _cand = _j40_os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    _luau = _cand if _j40_os.path.isfile(_cand) else None
if _luau:
    _r = _j40_sp.run([_j40_sys.executable, "tools/sim/run_base_marker_test.py"], capture_output=True, text=True, env=dict(_j40_os.environ, LUAU=_luau))
    _j40(_r.returncode == 0 and "BASE MARKER TEST: 0 failed" in _r.stdout, "E: run_base_marker_test.py (real config / data service)")
else:
    print("SKIP CLAUDE-BUD J40: Luau CLI tests (set LUAU)")
