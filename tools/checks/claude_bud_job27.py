# claude-bud JOB 27 (2026-09-30): city buildings popping. Root cause: Client/Modules/QualityGovernor (the only client
# code that removes world models; StreamingEnabled OFF; no server rebuild loop). Static pins + the route replay model.
import re as _j27_re
import sys as _j27_sys
from pathlib import Path as _J27P

if "ok" not in globals():
    _j27_fails = []

    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        _j27_fails.append(msg)
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _J27P(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None


def _j27(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J27: " + msg)


def _j27_code(path):
    return "\n".join(l.split("--", 1)[0] for l in (read(path) or "").splitlines())


_QG = _j27_code("src/StarterPlayer/StarterPlayerScripts/Client/Modules/QualityGovernor.luau")
_QC = read("src/ReplicatedStorage/Shared/Configs/QualityConfig.luau") or ""
_j27("\tCullTownBuildings = false," in _QC and "BuildingMinStuds = " in _QC and "Tier2ShowStuds = " in _QC and "AnyHideStuds = " in _QC,
     "kill switch CullTownBuildings (false = buildings never culled); load / unload distances in config")
_j27("m:GetBoundingBox()" in _QG and "boxDist(focus, e.Min, e.Max)" in _QG and "GetPivot" not in _QG, "distance to the bounding box, never a pivot point")
_j27("math.max(sz.X, sz.Z) >= (tonumber(Q.BuildingMinStuds) or 14)" in _QG and "onBuilding(mn, mx)" in _QG, "buildings by size never culled, nor the small clusters on them")
_j27("elseif e.Hidden and d < showAt then" in _QG and "elseif not e.Hidden and d > hideAt then" in _QG, "separate LOAD / UNLOAD distances (nothing in between)")
_j27("pcall(cull :: any, Q)" in _QG and "Q.FastCullSeconds" in _QG and "Heartbeat:Connect(function()\n\t\tframes += 1" in (read("src/StarterPlayer/StarterPlayerScripts/Client/Modules/QualityGovernor.luau") or "").replace("\r\n", "\n"),
     "one central manager (0.4 s / 0.2 s fast); the only per-frame work is the FPS counter")
_j27(":Destroy()" not in _QG and ":Clone()" not in _QG, "no Destroy / Clone of world models (only re-parenting of small decor)")
_j27("[BUILDING DEBUG]" in (read("src/StarterPlayer/StarterPlayerScripts/Client/Modules/QualityGovernor.luau") or "") and "DebugLog = false," in _QC, "debug log available, off by default")
_j27('"StreamingEnabled": true' not in (read("default.project.json") or ""), "StreamingEnabled stays off (no second streaming system)")
try:
    _j27_sys.path.insert(0, str(_J27P("tools/sim").resolve()))
    import quality_cull_model as _qcm
    _rows = _qcm.table()
    _j27(all(r[3][0] == 0 for r in _rows), f"city route replay: no building ever missing within 200 studs at 16-140 studs/s (JOB 27: {[r[3][0] for r in _rows]})")
    _j27(all(r[1][0] > 0 for r in _rows[:2]), f"the replay reproduces the bug on the old rule (v116 {[round(r[1][0], 1) for r in _rows]} s)")
    _j27(all(r[3][1] >= 200 for r in _rows), f"small decoration still loads well ahead ({[round(r[3][1]) for r in _rows]} studs)")
except Exception as _e:  # noqa: BLE001
    bad("CLAUDE-BUD J27: model error " + repr(_e))
