# claude-bud JOB 58 (2026-10-01): hangar + dock rebuild with real aircraft / boat bodies (approved store bodies through
# VisualAssetService.CloneDisplayBody; the Part build stays when no body). Executed inside tools/BuyPathStatic.py.
import os as _j58_os
import re as _j58_re
import subprocess as _j58_sp
import sys as _j58_sys
from pathlib import Path as _J58P

if "ok" not in globals():
    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        print("FAIL " + msg)


def _j58_src(p):
    q = _J58P(p)
    return q.read_text(encoding="utf-8").replace("\r\n", "\n") if q.is_file() else ""


_HC = _j58_src("src/ReplicatedStorage/Shared/Configs/HangarDockConfig.luau")
(ok if ("Enabled = true," in _HC and "OwnerFirst = true, -- NEW-OWNER-FIRST" in _HC) else bad)("CLAUDE-BUD J58: HangarDockConfig is owner-first")
(ok if (not _j58_re.search(r"\b\d{6,}\b", _HC)) else bad)("CLAUDE-BUD J58: no new asset ids (the showpieces reuse the vehicles' approved bodies by vehicle id)")
_V = _j58_src("src/ServerScriptService/Server/Services/VisualAssetService.luau")
_cd = _V.split("function VisualAssetService.CloneDisplayBody")[1].split("\nend\n")[0] if "function VisualAssetService.CloneDisplayBody" in _V else ""
(ok if ("VisualAssetService.BodyAllowed(ref, ownerUserId)" in _cd and "stripScripts(clone)" in _cd and "stripDress(clone)" in _cd and "d.Anchored = true" in _cd
    and "d.CanCollide = false" in _cd and "d.CanQuery = false" in _cd and "nParts > maxParts()" in _cd) else bad)(
    "CLAUDE-BUD J58: a display body is allowed like a driven body, stripped, anchored, never collides / takes shots, within the part cap")
_HS = _j58_src("src/ServerScriptService/Server/Services/HangarDockDisplayService.luau")
_po = _HS.split("local function placeOne")[1].split("\nend\n")[0] if "local function placeOne" in _HS else ""
(ok if (_po.index("m.Parent = parent") < _po.index("HangarDockDisplayService.HideNear(") and "if ok and model then" in _po) else bad)(
    "CLAUDE-BUD J58: the Part jet / boat pieces are hidden ONLY after a body is placed (no body = the Part build stays)")
_HSc = "\n".join(l.split("--", 1)[0] for l in _j58_re.sub(r"--\[\[.*?\]\]", "", _HS, flags=_j58_re.S).splitlines())
(ok if (not _j58_re.search(r"WE_Building|Store_|Character|Humanoid|Teleport", _HSc)) else bad)(
    "CLAUDE-BUD J58: showpieces only (never moves a player or unit, no protected / store-prop names)")
_BOOT = _j58_src("src/ServerScriptService/Server/Bootstrap.server.luau")
(ok if 'safeInit("HangarDockDisplayService", HangarDockDisplayService, deps)' in _BOOT else bad)("CLAUDE-BUD J58: HangarDockDisplayService is started")
_e = dict(_j58_os.environ)
if "LUAU" not in _e and _e.get("LUAU_COMPILE"):
    _c = _e["LUAU_COMPILE"].replace("luau-compile", "luau")
    if _j58_os.path.isfile(_c):
        _e["LUAU"] = _c
if _e.get("LUAU"):
    _r = _j58_sp.run([_j58_sys.executable, "tools/sim/run_hangar_dock_test.py"], capture_output=True, text=True, env=_e)
    (ok if (_r.returncode == 0 and "HANGAR DOCK TEST: 0 failed" in _r.stdout) else bad)(
        "CLAUDE-BUD J58: run_hangar_dock_test.py (frames, placed + hidden, resync, fallback keeps the Part build, owner-first)")
