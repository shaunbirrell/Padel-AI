# Code Bot Roblox v117 (2026-09-29): JOB 24 army ATTACK AttackSteer ship pins.
# Merged Claude 35099a3 (Follow3.AttackSteer / steered block ATTACK + Debug off by default). WE_Build 117.
from pathlib import Path as _P117

if "must_contain" not in globals():
    def must_contain(path, needle, label):
        text = _P117(path).read_text(encoding="utf-8") if _P117(path).is_file() else ""
        if needle in text:
            print("PASS " + label)
        else:
            print("FAIL " + label)
            raise SystemExit(1)

_cb117_S = "src/ServerScriptService/Server/"
for _f in (
    _cb117_S + "Services/DataService.luau",
    _cb117_S + "Services/BaseService.luau",
    _cb117_S + "EarlyRemotes.server.luau",
):
    must_contain(_f, 'SetAttribute("WE_Build", 117)', "CODEBOT v117: WE_Build=117 " + _f.rsplit("/", 1)[-1])
must_contain(_cb117_S + "Services/DataService.luau", "WE_Build=117", "CODEBOT v117: DataService profile-loaded log says WE_Build=117")
must_contain("src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau", "AttackSteer", "CODEBOT v117: ArmyConfig Follow3.AttackSteer present")
must_contain("src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau", "Debug = false", "CODEBOT v117: ArmyConfig Follow3.Debug = false by default")
must_contain(_cb117_S + "Services/SquadOrdersService.luau", "attackAimOnly", "CODEBOT v117: SquadOrdersService attackAimOnly present (JOB 24)")
