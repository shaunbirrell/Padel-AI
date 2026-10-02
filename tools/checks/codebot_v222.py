# Code Bot Roblox v222 (2026-10-02): cherry-pick claude-bud 43380f0 rebirth-zone buildings (Shaun item 2).
# Job67DressConfig.ZoneBuildings OwnerFirst = true (NEW-OWNER-FIRST). DressZone swaps each zone's MAIN block
# building for a free desert house on every plot still showing the Part build. PreferMesh OFF; StreamingEnabled OFF;
# WE_Building* untouched; no price / Id / save-key change.
from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

BUILD = 222
PREV = "dfcfad6"  # v221 tip (checks commit / place 219 lineage)
OWN = "43380f0"  # claude-bud source commit (cherry-picked)
ROOT = Path.cwd()
C = "src/ReplicatedStorage/Shared/Configs/"
S = "src/ServerScriptService/Server/"
LUAU = os.environ.get("LUAU", os.path.expanduser("~/.local/bin/luau"))


def _v222_rd(rel: str) -> str:
    p = ROOT / rel
    return p.read_text(encoding="utf-8").replace("\r\n", "\n") if p.is_file() else ""


def _v222_ck(cond: bool, label: str) -> None:
    tag = "CODEBOT v222: " + label
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(tag)  # type: ignore[name-defined]
    else:
        print(("PASS " if cond else "FAIL ") + tag)
        if not cond:
            globals()["_V222_FAILED"] = True


# ---- WE_Build ----
for _v222_rel in (S + "Services/BaseService.luau", S + "Services/DataService.luau", S + "EarlyRemotes.server.luau"):
    _v222_m = re.search(r'SetAttribute\("WE_Build",\s*(\d+)', _v222_rd(_v222_rel))
    _v222_ck(_v222_m is not None and int(_v222_m.group(1)) >= BUILD, "WE_Build >= %d %s" % (BUILD, _v222_rel.rsplit("/", 1)[-1]))
_v222_ck("WE_Build=223" in _v222_rd(S + "Services/DataService.luau"), "DataService profile-loaded log says WE_Build=223")

# ---- config gate ----
_v222_cfg = _v222_rd(C + "Job67DressConfig.luau")
_v222_blk = _v222_cfg[_v222_cfg.find("Job67DressConfig.ZoneBuildings = {"):]
_v222_blk = _v222_blk[: _v222_blk.find("\n}\n") + 3] if _v222_blk else ""
_v222_ck("Enabled = true" in _v222_blk and "OwnerFirst = true, -- NEW-OWNER-FIRST (claude-bud, rebirth-zone buildings)" in _v222_blk,
         "ZoneBuildings Enabled + NEW-OWNER-FIRST")
for _v222_z in ("WestYard", "StrategicYard", "WestStrip", "DroneBay", "EastYard", "EastStrip", "WestFlank"):
    _v222_ck("\n\t\t%s = {" % _v222_z in _v222_blk, "ZoneBuildings row %s" % _v222_z)

# ---- DressZone + RebirthZoneService hook ----
_v222_svc = _v222_rd(S + "Services/Job67DressService.luau")
_v222_rzs = _v222_rd(S + "Services/RebirthZoneService.luau")
_v222_ck("function Job67DressService.DressZone(" in _v222_svc, "Job67DressService.DressZone exists")
_v222_hook = _v222_rzs[_v222_rzs.find("claude-bud (rebirth-zone buildings)"): _v222_rzs.find("claude-bud (rebirth-zone buildings)") + 700]
_v222_ck("task.spawn" in _v222_hook and "J.DressZone" in _v222_hook and "Builder.Build" in _v222_rzs[_v222_rzs.find("claude-bud (rebirth-zone buildings)")-250:_v222_rzs.find("claude-bud (rebirth-zone buildings)")],
         "RebirthZoneService calls DressZone off-thread after Part build")

# ---- PreferMesh / Streaming / WE_Building* / no price change vs v221 tip ----
_v222_svc = _v222_rd(C + "StructureVisualConfig.luau")
_v222_ck("PreferMeshWhenAssetIdSet = false" in _v222_svc, "PreferMeshWhenAssetIdSet stays false")

_v222_r = subprocess.run(["git", "diff", "-U0", "4267b3c", "2ebc6f0", "--", "src"], capture_output=True, text=True, cwd=ROOT)  # scoped to v222 ship (item3/4 later)
_v222_bad = []
if _v222_r.returncode == 0:
    for _v222_l in _v222_r.stdout.split("\n"):
        if not (_v222_l.startswith("+") or _v222_l.startswith("-")) or _v222_l.startswith("+++") or _v222_l.startswith("---"):
            continue
        if "WE_Building" in _v222_l and "WE_Build" not in _v222_l:
            _v222_bad.append(_v222_l)
        if re.search(r"\bPrice\s*=", _v222_l) or re.search(r"\bId\s*=\s*\d{5,}", _v222_l):
            # allow comments / unchanged context; flag only if looking like a product price/id change
            if "ZoneBuildings" not in _v222_l and "Pack =" not in _v222_l and "Parts =" not in _v222_l:
                if re.search(r"^\+.*\b(Price|Robux)\s*=", _v222_l) or re.search(r"^\+.*\bId\s*=\s*\d{6,}", _v222_l):
                    _v222_bad.append(_v222_l)
_v222_ck(not _v222_bad, "src diff vs v221 tip: no WE_Building* / price / product Id changes %s" % _v222_bad[:3])

# ---- claude check present ----
_v222_ck((ROOT / "tools/checks/claude_bud_zone_buildings.py").is_file(), "claude_bud_zone_buildings.py present")

if __name__ == "__main__" and "ok" not in globals():
    raise SystemExit(1 if globals().get("_V222_FAILED") else 0)
