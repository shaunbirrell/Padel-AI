# Code Bot Roblox v119 (2026-09-29): JOB 24c+25 building tips / outpost defenders / town cull / base signs ship pins.
# Merged Claude bf3ff7b (JOB 25 on 84b1667 JOB 24c). WE_Build 119.
from pathlib import Path as _P119

if "must_contain" not in globals():
    def must_contain(path, needle, label):
        text = _P119(path).read_text(encoding="utf-8") if _P119(path).is_file() else ""
        if needle in text:
            print("PASS " + label)
        else:
            print("FAIL " + label)
            raise SystemExit(1)

_cb119_S = "src/ServerScriptService/Server/"
for _f in (
    _cb119_S + "Services/DataService.luau",
    _cb119_S + "Services/BaseService.luau",
    _cb119_S + "EarlyRemotes.server.luau",
):
    pass  # v120 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v120.py: #must_contain(_f, 'SetAttribute("WE_Build", 119)', "CODEBOT v119: WE_Build=119 " + _f.rsplit("/", 1)[-1])
# v120 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v120.py: #must_contain(_cb119_S + "Services/DataService.luau", "WE_Build=119", "CODEBOT v119: DataService profile-loaded log says WE_Build=119")
must_contain("src/ServerScriptService/Server/Services/BaseSignService.luau", "BaseSignService", "CODEBOT v119: BaseSignService present")
must_contain("src/ReplicatedStorage/Shared/Configs/BaseSignConfig.luau", "\tEnabled = true,", "CODEBOT v119: BaseSignConfig.Enabled = true")
must_contain("src/ServerScriptService/Server/Modules/OutpostDefenders.luau", "OutpostDefenders", "CODEBOT v119: OutpostDefenders present")
must_contain("src/ReplicatedStorage/Shared/Configs/OutpostDefenderConfig.luau", "\tEnabled = true,", "CODEBOT v119: OutpostDefenderConfig.Enabled = true")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/BuildingTipController.luau", "BuildingTipController", "CODEBOT v119: BuildingTipController present")
must_contain("src/ReplicatedStorage/Shared/Configs/BuildingTutorialConfig.luau", "\tEnabled = true,", "CODEBOT v119: BuildingTutorialConfig.Enabled = true")
must_contain("src/ReplicatedStorage/Shared/Configs/QualityConfig.luau", "NeverHideKinds", "CODEBOT v119: QualityConfig NeverHideKinds (buildings never culled)")
must_contain("src/ReplicatedStorage/Shared/Configs/QualityConfig.luau", "LookAheadSeconds", "CODEBOT v119: QualityConfig LookAheadSeconds")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/QualityGovernor.luau", "LookAheadSeconds", "CODEBOT v119: QualityGovernor look-ahead")
