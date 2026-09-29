# Code Bot Roblox v116 (2026-09-29): JOB 23 army formation Steer ship pins.
# Merged Claude 46fe085 (Follow3.Steer / one steered block). WE_Build 116.
from pathlib import Path as _P116

if "must_contain" not in globals():
    def must_contain(path, needle, label):
        text = _P116(path).read_text(encoding="utf-8") if _P116(path).is_file() else ""
        if needle in text:
            print("PASS " + label)
        else:
            print("FAIL " + label)
            raise SystemExit(1)

_cb116_S = "src/ServerScriptService/Server/"
for _f in (
    _cb116_S + "Services/DataService.luau",
    _cb116_S + "Services/BaseService.luau",
    _cb116_S + "EarlyRemotes.server.luau",
):
    must_contain(_f, 'SetAttribute("WE_Build", 116)', "CODEBOT v116: WE_Build=116 " + _f.rsplit("/", 1)[-1])
must_contain(_cb116_S + "Services/DataService.luau", "WE_Build=116", "CODEBOT v116: DataService profile-loaded log says WE_Build=116")
must_contain("src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau", "Steer", "CODEBOT v116: ArmyConfig Follow3.Steer present")
must_contain("src/ReplicatedStorage/Shared/Util/FormationController.luau", "SteerFrames", "CODEBOT v116: FormationController.SteerFrames present")
