# claude-bud JOB 47 (2026-10-01): the ghost label behind the INTEL OFFICE pill (base tags kept out of the top-bar row);
# TARGETS card + scout report fixed by Code Bot v171 (re-proved by run_targets_scout_test).
import os as _j47_os
import subprocess as _j47_sp
import sys as _j47_sys
from pathlib import Path as _J47P

if "ok" not in globals():
    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _J47P(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None


def _j47(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J47: " + msg)


_BMC = (read("src/ReplicatedStorage/Shared/Configs/BaseMarkerConfig.luau") or "").replace("\r\n", "\n")
_BMK = (read("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/BaseMarkerController.luau") or "").replace("\r\n", "\n")
_j47("function BaseMarkerConfig.InTopBar(y: number, h: number, topPx: number): boolean" in _BMC and "TopBarPadPx = " in _BMC,
     "BaseMarkerConfig.InTopBar: a tag reaching into the top-bar row hides (no ghost behind a HUD pill)")
_j47("not B.InTopBar(v.Y, h, topPx)" in _BMK and "GuiService:GetGuiInset().Y" in _BMK,
     "the marker step drops top-bar tags with the live inset before VisibleSet")
_luau = _j47_os.environ.get("LUAU")
if _luau is None and _j47_os.environ.get("LUAU_COMPILE"):
    _c = _j47_os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    _luau = _c if _j47_os.path.isfile(_c) else None
if _luau:
    _r = _j47_sp.run([_j47_sys.executable, "tools/sim/run_targets_scout_test.py"], capture_output=True, text=True, env=dict(_j47_os.environ, LUAU=_luau))
    _j47(_r.returncode == 0 and "TARGETS SCOUT TEST: 0 failed" in _r.stdout, "run_targets_scout_test.py (ghost at 956x440 / 1024x471 / desktop, TARGETS + scout proofs)")
else:
    print("SKIP CLAUDE-BUD J47: Luau CLI tests (set LUAU)")
