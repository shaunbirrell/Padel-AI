# Code Bot Roblox v130 (2026-09-30): ship claude-bud JOB 32 enterable plaza buildings + one LosRule + army holds
# at the door. Cherry-pick e6a1b56 onto phase-7-polish. KEEP v129 MAP-REDESIGN (do not revert). Fast travel stays
# REMOVED. PreferMesh stays OFF. WE_Building* untouched.
import os as _os130
import subprocess as _sp130
import sys as _sys130
from pathlib import Path as _P130


def _cb130(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


def _rd130(p):
    q = _P130(p)
    return q.read_text(encoding="utf-8") if q.is_file() else ""


def _code130(p):
    return "\n".join(l.split("--", 1)[0] for l in _rd130(p).splitlines())


_S130 = "src/ServerScriptService/Server/"
for _f in (_S130 + "Services/DataService.luau", _S130 + "Services/BaseService.luau", _S130 + "EarlyRemotes.server.luau"):
    pass  # v132 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v132.py: #_cb130('SetAttribute("WE_Build", 131)' in _rd130(_f), "CODEBOT v130: WE_Build=131 " + _f.rsplit("/", 1)[-1])
# v132 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v132.py: #_cb130("WE_Build=131" in _rd130(_S130 + "Services/DataService.luau"), "CODEBOT v130: DataService profile-loaded log says WE_Build=131")

# JOB 32: plaza enterables + LosRule + army Indoors
_cb130(_P130("src/ReplicatedStorage/Shared/Configs/PlazaBuildingsConfig.luau").is_file()
       and "Enabled" in _rd130("src/ReplicatedStorage/Shared/Configs/PlazaBuildingsConfig.luau"),
       "CODEBOT v130: PlazaBuildingsConfig exists (JOB 32)")
_cb130(_P130("src/ReplicatedStorage/Shared/Util/LosRule.luau").is_file()
       and "function LosRule." in _rd130("src/ReplicatedStorage/Shared/Util/LosRule.luau"),
       "CODEBOT v130: LosRule exists (JOB 32)")
_cb130(_P130("src/ServerScriptService/Server/Modules/Enterables.luau").is_file()
       and "Enterables" in _rd130("src/ServerScriptService/Server/Modules/Enterables.luau"),
       "CODEBOT v130: Enterables module exists (JOB 32)")
_cb130("Indoors" in _rd130("src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau"),
       "CODEBOT v130: ArmyConfig.Indoors exists (JOB 32)")
_cb130("LineOfSight" in _rd130("src/ReplicatedStorage/Shared/Configs/CombatConfig.luau"),
       "CODEBOT v130: CombatConfig.LineOfSight exists (JOB 32)")

# Fast travel still OFF
_CTL130 = _code130("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/MapController.luau")
_MC130 = _rd130("src/ReplicatedStorage/Shared/Configs/MapConfig.luau")
_cb130("\tFastTravelEnabled = false,\n" in _MC130 and "FastTravel" not in _CTL130.replace("FastTravelEnabled", "")
       and '"TRAVEL"' not in _CTL130 and "RequestFastTravel" not in _CTL130,
       "CODEBOT v130: still no fast travel (MapConfig.FastTravelEnabled=false; no TRAVEL / RequestFastTravel)")
_cb130("PreferMeshWhenAssetIdSet = false" in _rd130("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau"),
       "CODEBOT v130: PreferMesh stays OFF")

# MAP-REDESIGN (v129) still present — do not revert
_LL130 = _code130("src/ReplicatedStorage/Shared/Util/MapLabelLayout.luau")
_cb130(_P130("src/ReplicatedStorage/Shared/Util/MapLabelLayout.luau").is_file()
       and "function MapLabelLayout.TitleCase(" in _LL130
       and "MapLabelLayout.Slots = { { 1, 0 }, { -1, 0 }, { 0, -1 }, { 0, 1 }," in _LL130,
       "CODEBOT v130: MAP-REDESIGN MapLabelLayout still present (v129 UI kept)")
_cb130("local function fitLayout()" in _CTL130 and "cv.Size = UDim2.fromOffset(sv, sv)" in _CTL130
       and "card.Position = UDim2.fromOffset(x0 + sv + GAP, y0)" in _CTL130
       and "UDim2.new(0.58, 0, 1, -12)" not in _CTL130,
       "CODEBOT v130: MAP-REDESIGN fitLayout square map + slim card still present (v129 UI kept)")
