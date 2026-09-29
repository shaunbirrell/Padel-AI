# Code Bot Roblox v118 (2026-09-29): JOB 24b army PvP / warnings / codes / analytics / crown ship pins.
# Merged Claude 458f2ed (ArmyCombat.Enabled, codes WAREMPIRE/ATTACK, analytics, crown explainer). WE_Build 118.
# WE_Build=118 pins retired — superseded in tools/checks/codebot_v119.py
from pathlib import Path as _P118

if "must_contain" not in globals():
    def must_contain(path, needle, label):
        text = _P118(path).read_text(encoding="utf-8") if _P118(path).is_file() else ""
        if needle in text:
            print("PASS " + label)
        else:
            print("FAIL " + label)
            raise SystemExit(1)

_cb118_S = "src/ServerScriptService/Server/"
for _f in (
    _cb118_S + "Services/DataService.luau",
    _cb118_S + "Services/BaseService.luau",
    _cb118_S + "EarlyRemotes.server.luau",
):
    pass  # v119 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v119.py: #must_contain(_f, 'SetAttribute("WE_Build", 118)', "CODEBOT v118: WE_Build=118 " + _f.rsplit("/", 1)[-1])
# v119 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v119.py: #must_contain(_cb118_S + "Services/DataService.luau", "WE_Build=118", "CODEBOT v118: DataService profile-loaded log says WE_Build=118")
must_contain("src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau", "ArmyCombat", "CODEBOT v118: ArmyConfig.ArmyCombat present")
must_contain("src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau", "\tArmyCombat = {\n\t\tEnabled = true,", "CODEBOT v118: ArmyCombat.Enabled = true (kill switch)")
must_contain(_cb118_S + "Configs/CodesConfig.luau", "WAREMPIRE", "CODEBOT v118: code WAREMPIRE present")
must_contain(_cb118_S + "Configs/CodesConfig.luau", "ATTACK", "CODEBOT v118: code ATTACK present")
must_contain(_cb118_S + "Services/CombatService/init.luau", "ApplyUnitPlayerHit", "CODEBOT v118: CombatService.ApplyUnitPlayerHit present")
must_contain(_cb118_S + "Services/SquadOrdersService.luau", "ArmyCombat", "CODEBOT v118: SquadOrdersService uses ArmyCombat")
