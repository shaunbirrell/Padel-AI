"""v113: JOB 22 army follow root-cause fix live for all (Follow2.Stable=true)."""
from pathlib import Path as _P113

def _must113(cond, msg):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(msg)
        return cond
    print(("PASS" if cond else "FAIL") + " " + msg)
    return cond

_cfg113 = _P113("src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau").read_text()
_af113 = _P113("src/ServerScriptService/Server/Modules/ArmyFollow.luau").read_text()
_fm113p = _P113("src/ReplicatedStorage/Shared/Util/FormationMath.luau")
_fm113 = _fm113p.read_text() if _fm113p.is_file() else ""
_drop113 = _P113("src/ReplicatedStorage/Shared/Configs/ManualDropperConfig.luau").read_text()
_base113 = _P113("src/ReplicatedStorage/Shared/Configs/BaseConfig.luau").read_text()
_vis113 = _P113("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau").read_text()

_all113 = True
_all113 &= _must113("\t\tStable = true," in _cfg113, "v113 Follow2.Stable=true")
_all113 &= _must113(_fm113p.is_file() and "local FormationMath = {}" in _fm113, "v113 FormationMath present")
_all113 &= _must113("function ArmyFollow.Command(unit: any, goal: Vector3, state: string?)" in _af113, "v113 ArmyFollow.Command sole mover API")
# v114 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v114_army.py (every soldier MoveTo is SoldierController.Move, the one PivotTo is SoldierController.Reposition): #_all113 &= _must113(_af113.count("Humanoid:MoveTo(") == 1, "v113 ArmyFollow has exactly one Humanoid:MoveTo")
_all113 &= _must113(_af113.count("Humanoid:MoveTo(") == 0, "v113 (v114): ArmyFollow has no direct Humanoid:MoveTo (SoldierController.Move)")
_all113 &= _must113("\tEnabled = false," in _drop113, "v113 ManualDropper still off (v111)")
_all113 &= _must113("MaxPlots = 10," in _base113, "v113 MaxPlots=10 kept (JOB 21)")
_all113 &= _must113("PreferMesh = true" not in _vis113, "v113 PreferMesh stays OFF")
for _rel113 in (
    "src/ServerScriptService/Server/Services/DataService.luau",
    "src/ServerScriptService/Server/Services/BaseService.luau",
    "src/ServerScriptService/Server/EarlyRemotes.server.luau",
):
    _all113 &= _must113('SetAttribute("WE_Build", 182)' in _P113(_rel113).read_text(), "v113 WE_Build=113 " + _rel113.rsplit("/", 1)[-1])

if "ok" not in globals():
    import sys
    print(("PASS" if _all113 else "FAIL") + " v113 JOB 22 army follow + build 113")
    if __name__ == "__main__":
        sys.exit(0 if _all113 else 1)
