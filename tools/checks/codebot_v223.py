# Code Bot Roblox v223 (2026-10-02): cherry-pick claude-bud 958cb67 (Shaun item 3 turret+wall looks)
# + 60a9ded (Shaun item 4 drivable Synty vehicles). Both NEW-OWNER-FIRST.
# PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; no price / Id / save-key change.
from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

BUILD = 223
PREV = "36f81b9"  # v222 tip (place 220)
OWN = ("958cb67", "60a9ded")  # claude-bud source commits (cherry-picked)
ROOT = Path.cwd()
C = "src/ReplicatedStorage/Shared/Configs/"
S = "src/ServerScriptService/Server/"
CL = "src/StarterPlayer/StarterPlayerScripts/Client/"


def _v223_rd(rel: str) -> str:
    p = ROOT / rel
    return p.read_text(encoding="utf-8").replace("\r\n", "\n") if p.is_file() else ""


def _v223_ck(cond: bool, label: str) -> None:
    tag = "CODEBOT v223: " + label
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(tag)  # type: ignore[name-defined]
    else:
        print(("PASS " if cond else "FAIL ") + tag)
        if not cond:
            globals()["_V223_FAILED"] = True


# ---- WE_Build ----
for _v223_rel in (S + "Services/BaseService.luau", S + "Services/DataService.luau", S + "EarlyRemotes.server.luau"):
    _v223_m = re.search(r'SetAttribute\("WE_Build",\s*(\d+)', _v223_rd(_v223_rel))
    _v223_ck(_v223_m is not None and int(_v223_m.group(1)) >= BUILD, "WE_Build >= %d %s" % (BUILD, _v223_rel.rsplit("/", 1)[-1]))
_v223_ck("WE_Build=223" in _v223_rd(S + "Services/DataService.luau"), "DataService profile-loaded log says WE_Build=223")

# ---- item 3: one turret tier table + TierText OwnerFirst ----
_v223_eg = _v223_rd(C + "EndgameConfig.luau")
_v223_ck("TurretTiers = {" in _v223_eg and 'Names = { "Mk I", "Mk II", "Mk III", "Mk IV", "Mk V" }' in _v223_eg, "EndgameConfig.Defence.TurretTiers Mk I-V")
_v223_tt = _v223_eg[_v223_eg.find("TierText = {"): _v223_eg.find("TierText = {") + 220] if "TierText = {" in _v223_eg else ""
_v223_ck("Enabled = true" in _v223_tt and "OwnerFirst = true, -- NEW-OWNER-FIRST (claude-bud item 3)" in _v223_tt, "TierText Enabled + NEW-OWNER-FIRST")
_v223_ck("function EndgameConfig.TurretTier(" in _v223_eg and "function EndgameConfig.TierTextLive(" in _v223_eg, "TurretTier + TierTextLive helpers")
_v223_gds = _v223_rd(S + "Services/GateDefenseService.luau")
_v223_ck("TurretTier" in _v223_gds and ("EndgameConfig" in _v223_gds), "GateDefenseService reads central TurretTier")
_v223_ck("TierTextLive" in _v223_rd(CL + "Controllers/BaseController.luau") or "TierText" in _v223_rd(CL + "Controllers/BaseController.luau"), "BaseController uses TierText")

# ---- item 4: SyntyVehicleConfig OwnerFirst ----
_v223_sy = _v223_rd(C + "SyntyVehicleConfig.luau")
_v223_ck(_v223_sy != "", "SyntyVehicleConfig.luau present")
_v223_ck("OwnerFirst = true, -- NEW-OWNER-FIRST (claude-bud item 4)" in _v223_sy, "SyntyVehicleConfig NEW-OWNER-FIRST")
_v223_ck("PackId = 119390702773907" in _v223_sy, "Synty pack id audited")
for _v223_v in ("ArmoredTruck", "ArmedJeep", "ScoutCar"):
    _v223_ck(_v223_v + " =" in _v223_sy or _v223_v + " =" in _v223_sy.replace(" ", ""), "Synty row %s" % _v223_v)
_v223_ck("TryAttachSyntyVehicleVisual" in _v223_rd(S + "Services/VisualAssetService.luau"), "VisualAssetService.TryAttachSyntyVehicleVisual")
_v223_ck("TryAttachSyntyVehicleVisual" in _v223_rd(S + "Services/VehicleService.luau"), "VehicleService calls Synty dress path")

# ---- PreferMesh / WE_Building* / no price change vs v222 tip ----
_v223_ck("PreferMeshWhenAssetIdSet = false" in _v223_rd(C + "StructureVisualConfig.luau"), "PreferMeshWhenAssetIdSet stays false")

_v223_r = subprocess.run(["git", "diff", "-U0", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
_v223_bad = []
if _v223_r.returncode == 0:
    for _v223_l in _v223_r.stdout.split("\n"):
        if not (_v223_l.startswith("+") or _v223_l.startswith("-")) or _v223_l.startswith("+++") or _v223_l.startswith("---"):
            continue
        if "WE_Building" in _v223_l and "WE_Build" not in _v223_l:
            _v223_bad.append(_v223_l)
        if re.search(r"^\+.*\b(Price|Robux)\s*=", _v223_l) or re.search(r"^\+.*\bId\s*=\s*\d{6,}", _v223_l):
            if "ZoneBuildings" not in _v223_l and "Pack" not in _v223_l and "Parts" not in _v223_l and "PackId" not in _v223_l:
                _v223_bad.append(_v223_l)
_v223_ck(not _v223_bad, "src diff vs v222 tip: no WE_Building* / price / product Id changes %s" % _v223_bad[:3])

# ---- claude checks present ----
_v223_ck((ROOT / "tools/checks/claude_bud_tier_looks.py").is_file(), "claude_bud_tier_looks.py present")
_v223_ck((ROOT / "tools/checks/claude_bud_synty_vehicles.py").is_file(), "claude_bud_synty_vehicles.py present")

if __name__ == "__main__" and "ok" not in globals():
    raise SystemExit(1 if globals().get("_V223_FAILED") else 0)
