"""JOB 70 acceptance (Code Bot's fail-closed guard + claude-bud's implementation proofs).

claude-bud (2026-10-02): every helper / global is prefixed _j70 (BuyPathStatic execs every tools/checks script in ONE
globals dict; the guard's plain `read` returned "" for a missing file and broke codebot_v102's `read(...) is None`).
It is compatible with BuyPathStatic's ``ok``/``bad`` harness, and also runs directly from the repository root.
"""
from __future__ import annotations

import os as _j70_os
import re as _j70_re
import subprocess as _j70_sp
import sys as _j70_sys
from pathlib import Path as _J70P

_j70_STANDALONE = "ok" not in globals()
_j70_FAILURES = [0]

if _j70_STANDALONE:
    def ok(message: str) -> None:
        print("PASS " + message)

    def bad(message: str) -> None:
        _j70_FAILURES[0] += 1
        print("FAIL " + message)

_j70_ROOT = _J70P.cwd() if (_J70P.cwd() / "CLAUDE.md").is_file() else _J70P(__file__).resolve().parents[2]


def _j70_read(relative: str) -> str:
    path = _j70_ROOT / relative
    return path.read_text(encoding="utf-8").replace("\r\n", "\n") if path.is_file() else ""


_j70_claude = _j70_read("CLAUDE.md")
_j70_handoff = _j70_read("LATEST-HANDOFF.md")
_j70_config = _j70_read("src/ReplicatedStorage/Shared/Configs/Job67DressConfig.luau")
_j70_service = _j70_read("src/ServerScriptService/Server/Services/Job67DressService.luau")

# The queue and handoff must record the owner's direct-to-public approval.
for _j70_needle in (
    "JOB 70, URGENT, ship LIVE FOR EVERYONE",
    "OwnerFirst=false",
    "no owner test step",
    "sandbags",
    "Hesco",
    "concrete blocks",
    "crates",
    "pallets",
    "barbed wire",
    "StreamingEnabled",
    "PreferMesh",
    "WE_Building*",
):
    (ok if _j70_needle in _j70_claude else bad)(f"CLAUDE JOB 70 queue contains {_j70_needle!r}")

for _j70_needle in (
    "## JOB 70 QUEUED",
    "OwnerFirst=false",
    "LIVE FOR EVERYONE",
    "claude_bud_job70.py",
    "front/gate",
    "left, right and rear",
):
    (ok if _j70_needle in _j70_handoff else bad)(f"LATEST-HANDOFF JOB 70 contains {_j70_needle!r}")

# One central collision contract must describe all six newly wired categories.
_j70_block = _j70_re.search(r"(?is)(?:PropCollision|Colliders?)\s*=\s*\{.*?(?=\n\s*\w+\s*=\s*\{|\n\s*\}\s*,?\n)", _j70_config)
_j70_coll = _j70_block.group(0) if _j70_block else ""
for _j70_pat, _j70_label in (
    (r"\b(?:Sandbag|Sandbags|Trench)\w*", "sandbag props"),
    (r"\bHesco\w*", "Hesco props"),
    (r"\b(?:Concrete|Blockade|Barrier)\w*", "concrete-block props"),
    (r"\b(?:Crate|Crates)\w*", "crate props"),
    (r"\bPallet\w*", "pallet props"),
    (r"\bBarbedWire\w*", "barbed-wire props"),
):
    (ok if _j70_re.search(_j70_pat, _j70_config, _j70_re.I) else bad)(f"JOB 70 config registers {_j70_label}")
for _j70_pat, _j70_label in (
    (r"(?:Hull|Shape)\s*=\s*[\"'](?:Box|Block)[\"']", "Box/Block hull shape"),
    (r"VisualCanCollide\s*=\s*false", "visual CanCollide=false"),
    (r"HullCanCollide\s*=\s*true", "hull CanCollide=true"),
):
    (ok if _j70_re.search(_j70_pat, _j70_coll) else bad)(f"JOB 70 central collision contract has {_j70_label}")
(ok if _j70_re.search(r"OwnerFirst\s*=\s*false", _j70_coll) else bad)("JOB 70 central collision contract is LIVE FOR EVERYONE (OwnerFirst = false)")

# The service must create the hull once per placed prop/visual segment and leave mesh visuals non-colliding.
_j70_helper = _j70_re.search(r"(?i)(?:local\s+function|function)\s+(?:create|make|build)[A-Za-z0-9_]*(?:Hull|Collider)[A-Za-z0-9_]*", _j70_service)
(ok if _j70_helper else bad)("JOB 70 service has one generic prop/wall hull helper")
for _j70_pat, _j70_label in (
    (r"Instance\.new\(\s*[\"']Part[\"']\s*\)", "Part hull"),
    (r"Enum\.PartType\.Block|Shape\s*=\s*[\"'](?:Box|Block)[\"']", "Box/Block shape"),
    (r"Transparency\s*=\s*1", "invisible hull"),
    (r"CanCollide\s*=\s*true", "solid hull"),
    (r"CanQuery\s*=\s*true", "queryable hull"),
    (r"CanCollide\s*=\s*false", "non-colliding visual"),
):
    (ok if _j70_re.search(_j70_pat, _j70_service) else bad)(f"JOB 70 service proves {_j70_label}")
for _j70_marker in ("function Job67DressService.Place", "function Job67DressService.FitLine", "function Job67DressService.SyncProps", "function Job67DressService.DressWalls"):
    (ok if _j70_marker in _j70_service else bad)(f"JOB 70 checks placement path {_j70_marker.split('.')[-1].split('(')[0]}")


# claude-bud: the hull really is made on every placement path, and nothing else clones a visual
def _j70_body(name: str) -> str:
    i = _j70_service.find("function Job67DressService." + name)
    if i < 0:
        return ""
    j = _j70_service.find("\nfunction ", i + 10)
    k = _j70_service.find("\nlocal function ", i + 10)
    ends = [x for x in (j, k) if x > 0]
    return _j70_service[i:min(ends) if ends else len(_j70_service)]


_j70_place, _j70_fit = _j70_body("Place"), _j70_body("FitLine")
_j70_walls, _j70_props = _j70_body("DressWalls"), _j70_body("SyncProps")
(ok if "createHull(m, key, m, parent)" in _j70_place else bad)("JOB 70 Place gives every placed model its Box hull")
(ok if "createHull(p, key, parent, parent)" in _j70_fit else bad)("JOB 70 FitLine gives every fitted wall / line segment its Box hull")
(ok if ("Clone(" not in _j70_walls and "Clone(" not in _j70_props and "Instance.new(\"Part\")" not in _j70_walls
        and "Instance.new(\"Part\")" not in _j70_props) else bad)(
    "JOB 70 DressWalls / SyncProps place visuals only through Place / FitLine (no un-hulled clone)")
_j70_san = _j70_re.search(r"local function sanitizePart\(.*?\nend", _j70_service, _j70_re.S)
(ok if (_j70_san and "p.CanCollide = false" in _j70_san.group(0)) else bad)("JOB 70 every visual mesh part is CanCollide = false (sanitizePart; no mesh collision)")
_j70_hull = _j70_re.search(r"local function createHull\(.*?\nend", _j70_service, _j70_re.S)
_j70_h = _j70_hull.group(0) if _j70_hull else ""
(ok if all(x in _j70_h for x in ("Enum.PartType.Block", "h.Anchored = true", "h.CanCollide = true", "h.CanQuery = true", "h.CanTouch = false", "h.Transparency = 1", "GetBoundingBox()", "MaxHullsPerFolder"))
 else bad)("JOB 70 createHull: one anchored invisible Block, solid + queryable, sized to the visual's bounds, capped per folder")
for _j70_bad in ("Heartbeat", "RenderStepped", "Stepped:Connect", "PreferMesh = true", "WE_Building"):
    (ok if _j70_bad not in _j70_service else bad)(f"JOB 70 service has no `{_j70_bad}` (phone-light, house rules)")

# All wall faces must resolve through one tier-style lookup.
for _j70_pat, _j70_label in ((r"Gate|Front", "front/gate"), (r"Sides|Left|Right", "left/right sides"), (r"Rear|Back", "rear")):
    (ok if _j70_re.search(_j70_pat, _j70_config, _j70_re.I) and _j70_re.search(_j70_pat, _j70_service, _j70_re.I) else bad)(f"JOB 70 wall face covered: {_j70_label}")
_j70_sic = _j70_re.search(r"(?i)(?:WallStyle|StyleFor|TierStyle|VisualStyle)\s*=", _j70_config)
_j70_sl = _j70_re.search(r"(?i)(?:WallStyleFor|StyleFor|TierStyle|Wall.*Style).*?(?:tier|level|face)", _j70_service)
(ok if _j70_sic else bad)("JOB 70 central wall-upgrade config owns the wall style")
(ok if _j70_sl else bad)("JOB 70 every wall side uses the central tier style resolver")
(ok if ("Cfg.WallStyleFor(level)" in _j70_walls and "hescoFaces" not in _j70_walls and "has(tier." not in _j70_walls) else bad)(
    "JOB 70 DressWalls dresses every face from Cfg.WallStyleFor (no per-face fallback left)")
for _j70_level in range(1, 6):
    (ok if _j70_re.search(rf"\[{_j70_level}\]\s*=\s*\{{", _j70_config) else bad)(f"JOB 70 preserves progressive wall tier L{_j70_level}")

for _j70_needle in ("StreamingEnabled", "PreferMesh", "WE_Building"):
    (ok if _j70_needle in _j70_claude and _j70_needle in _j70_handoff else bad)(f"JOB 70 guardrail recorded: {_j70_needle}")

# claude-bud: the REAL config in Luau (categories for every piece / placement, all faces every tier, the Hesco plan)
_j70_env = dict(_j70_os.environ)
if "LUAU" not in _j70_env and _j70_env.get("LUAU_COMPILE"):
    _j70_lu = _j70_env["LUAU_COMPILE"].replace("luau-compile", "luau")
    if _j70_os.path.isfile(_j70_lu):
        _j70_env["LUAU"] = _j70_lu
if _j70_env.get("LUAU"):
    _j70_r = _j70_sp.run([_j70_sys.executable, "tools/sim/run_job70_test.py"], capture_output=True, text=True, env=_j70_env, timeout=150, cwd=str(_j70_ROOT))
    (ok if (_j70_r.returncode == 0 and "JOB70 TEST: 0 failed" in _j70_r.stdout) else bad)(
        "JOB 70 run_job70_test.py (every piece + placement categorised, one style on all 4 sides L1-L5, Hesco plan fits)")
else:
    bad("JOB 70 run_job70_test.py needs LUAU / LUAU_COMPILE (fail closed)")

if _j70_STANDALONE:
    _j70_sys.exit(1 if _j70_FAILURES[0] else 0)
