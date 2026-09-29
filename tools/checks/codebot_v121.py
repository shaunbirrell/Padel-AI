# Code Bot Roblox v121 (2026-09-30): merge Claude JOB 26 (stronger army + buyable player armour) +
# JOB 27 (city buildings popping — QualityGovernor bounding-box cull). WE_Build 121.
from pathlib import Path as _P121

if "must_contain" not in globals():
    def must_contain(path, needle, label):
        text = _P121(path).read_text(encoding="utf-8") if _P121(path).is_file() else ""
        if needle in text:
            print("PASS " + label)
        else:
            print("FAIL " + label)
            raise SystemExit(1)

_cb121_S = "src/ServerScriptService/Server/"
_cb121_C = "src/ReplicatedStorage/Shared/Configs/"
_cb121_CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
for _f in (
    _cb121_S + "Services/DataService.luau",
    _cb121_S + "Services/BaseService.luau",
    _cb121_S + "EarlyRemotes.server.luau",
):
    pass  # v122 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v122.py: #must_contain(_f, 'SetAttribute("WE_Build", 121)', "CODEBOT v121: WE_Build=121 " + _f.rsplit("/", 1)[-1])
# v122 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v122.py: #must_contain(_cb121_S + "Services/DataService.luau", "WE_Build=121", "CODEBOT v121: DataService profile-loaded log says WE_Build=121")

# JOB 26 — stronger army + buyable player armour
must_contain(_cb121_C + "ArmourConfig.luau", "\tEnabled = true,", "CODEBOT v121: ArmourConfig present and Enabled")
must_contain(_cb121_S + "Services/ArmourService.luau", "ArmourService", "CODEBOT v121: ArmourService present")
must_contain(_cb121_C + "ArmyConfig.luau", "\tStrongerArmy = {\n\t\tEnabled = true,", "CODEBOT v121: ArmyConfig.StrongerArmy Enabled")
must_contain(_cb121_CL + "Controllers/ArmourController.luau", "ArmourController", "CODEBOT v121: ArmourController present")

# JOB 27 — town building cull fix
must_contain(_cb121_C + "QualityConfig.luau", "\tCullTownBuildings = false,", "CODEBOT v121: QualityConfig.CullTownBuildings = false")
must_contain(_cb121_CL + "Modules/QualityGovernor.luau", "m:GetBoundingBox()", "CODEBOT v121: QualityGovernor bounding-box cull")
must_contain(_cb121_CL + "Modules/QualityGovernor.luau", "boxDist(focus, e.Min, e.Max)", "CODEBOT v121: QualityGovernor boxDist to AABB")

# standing rules
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "PreferMeshWhenAssetIdSet = false", "CODEBOT v121: PreferMesh stays OFF")
must_contain(_cb121_S + "Modules/HollowBuildingBuilder.luau", 'local MODEL_NAME = "WE_Building"', "CODEBOT v121: WE_Building untouched")
