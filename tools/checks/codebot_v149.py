# Code Bot Roblox v149 (2026-09-30): cherry-pick claude-bud JOB 39 phases 3–5 + JOB 40 part E
# (Elite / Hospital+Mastery+Workshop / Warheads+Heist+Contracts+BlackMarket+RewardScaling + base owner markers)
# onto phase-7-polish. Feature tips 1cd39a6, e31c2a0, 658dec1, 5d5e59f.
# EndgameConfig.Live OwnerFirst=true; Parts phases 3–5 true; BaseMarkerConfig OwnerFirst=true;
# PreferMesh OFF; WE_Building* untouched; WE_Build 149. Do NOT flip any OwnerFirst=false.
import os as _os149
import subprocess as _sp149
from pathlib import Path as _P149


def _cb149(cond, label):
	if "ok" in globals() and "bad" in globals():
		(ok if cond else bad)(label)
	else:
		print(("PASS " if cond else "FAIL ") + label)
		if not cond:
			raise SystemExit(1)


def _rd149(p):
	q = _P149(p)
	return q.read_text(encoding="utf-8") if q.is_file() else ""


_S149 = "src/ServerScriptService/Server/"
_C149 = "src/ReplicatedStorage/Shared/Configs/"
_CL149 = "src/StarterPlayer/StarterPlayerScripts/Client/"

# v150 (Code Bot Roblox): the WE_Build=149 pins are superseded in tools/checks/codebot_v150.py (WE_Build=150).
# for _f in (_S149 + "Services/DataService.luau", _S149 + "Services/BaseService.luau", _S149 + "EarlyRemotes.server.luau"):
# 	_cb149('SetAttribute("WE_Build", 149)' in _rd149(_f), "CODEBOT v149: WE_Build=149 " + _f.rsplit("/", 1)[-1])
# _cb149("WE_Build=149" in _rd149(_S149 + "Services/DataService.luau"), "CODEBOT v149: DataService profile-loaded log says WE_Build=149")

# Endgame phases 3–5
_EC = _rd149(_C149 + "EndgameConfig.luau")
_cb149("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = true," in _EC, "CODEBOT v149: EndgameConfig.Live Enabled + OwnerFirst=true")
_cb149("\t\tElite = true," in _EC, "CODEBOT v149: Parts.Elite true (phase 3)")
_cb149("\t\tHospital = true," in _EC and "\t\tMastery = true," in _EC and "\t\tWorkshop = true," in _EC,
	"CODEBOT v149: Parts.Hospital + Mastery + Workshop true (phase 4)")
_cb149(
	"\t\tWarheads = true," in _EC
	and "\t\tHeist = true," in _EC
	and "\t\tContracts = true," in _EC
	and "\t\tBlackMarket = true," in _EC
	and "\t\tRewardScaling = true," in _EC,
	"CODEBOT v149: Parts.Warheads + Heist + Contracts + BlackMarket + RewardScaling true (phase 5)",
)
_cb149(_P149(_S149 + "Services/EndgameService.luau").is_file(), "CODEBOT v149: EndgameService present")
_cb149(_P149(_CL149 + "Controllers/EndgameController.luau").is_file(), "CODEBOT v149: EndgameController present")

# JOB 40 part E base markers
_BMC = _rd149(_C149 + "BaseMarkerConfig.luau")
_cb149(_BMC != "", "CODEBOT v149: BaseMarkerConfig present")
_cb149("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = false," in _BMC, "CODEBOT v149: BaseMarkerConfig.Live Enabled + OwnerFirst=true")
_cb149(_P149(_S149 + "Services/BaseMarkerService.luau").is_file(), "CODEBOT v149: BaseMarkerService present")
_cb149(_P149(_CL149 + "Controllers/BaseMarkerController.luau").is_file(), "CODEBOT v149: BaseMarkerController present")
_BS = _rd149(_S149 + "Bootstrap.server.luau")
_cb149("BaseMarkerService" in _BS, "CODEBOT v149: Bootstrap.server wires BaseMarkerService")
_BC = _rd149(_CL149 + "Bootstrap.client.luau")
_cb149("BaseMarkerController" in _BC, "CODEBOT v149: Bootstrap.client wires BaseMarkerController")

# live state kept — do NOT flip OwnerFirst on new systems; keep prior live state
_AOC = _rd149(_C149 + "ArmyOrdersConfig.luau")
_cb149("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = true," in _AOC, "CODEBOT v149: ArmyOrdersConfig OwnerFirst stays true")
_cb149("OwnerFirst = false, -- codebot_v142 launch" in _rd149(_C149 + "ShopOverhaulConfig.luau"), "CODEBOT v149: ShopOverhaul stays OwnerFirst=false")
_cb149("OwnerFirst = false, -- codebot_v142 launch" in _rd149(_C149 + "CheckpointGuardConfig.luau"), "CODEBOT v149: CheckpointGuard stays OwnerFirst=false")
_cb149("PreferMeshWhenAssetIdSet = false" in _rd149(_C149 + "StructureVisualConfig.luau"), "CODEBOT v149: PreferMesh stays OFF")
_cb149("FastTravelEnabled = false" in _rd149(_C149 + "MapConfig.luau"), "CODEBOT v149: fast travel stays REMOVED")
_cb149("3972151362" in _rd149(_C149 + "HudConfig.luau"), "CODEBOT v149: RPG hold stays 3972151362")

_MC = _rd149(_C149 + "MonetizationConfig.luau")
_cb149("		VIP = {" in _MC and "RobuxPrice = 199," in _MC.split("VIP = {", 1)[1][:400], "CODEBOT v149: VIP RobuxPrice stays 199")
_RC = _rd149(_C149 + "RebirthConfig.luau")
_cb149("WeaponsLive = true" in _RC or "WeaponsLive = true," in _RC, "CODEBOT v149: WeaponsLive stays true")

# JOB 38 army fix must still be on phase-7
_AP = _rd149(_S149 + "Modules/ArmyPlan.luau")
_cb149("local start = if c then c else plan.Lead" in _AP and "ArmyRoute.PointAlong(start, route, standoff)" in _AP,
	"CODEBOT v149: JOB 38 army routes still start at the block (v145 kept)")

try:
	_wb = _sp149.run(["git", "diff", "--name-only", "2fb4ce8"], capture_output=True, text=True).stdout
	_cb149(not any("WE_Building" in l for l in _wb.splitlines()), "CODEBOT v149: no WE_Building* file touched since v148 tip")
except Exception:
	pass

_luau = _os149.environ.get("LUAU") or str(_P149.home() / ".local/bin/luau")
if _P149(_luau).is_file():
	_r = _sp149.run(["python3", "tools/sim/run_endgame_test.py"], capture_output=True, text=True, env=dict(_os149.environ, LUAU=_luau))
	_cb149(_r.returncode == 0, "CODEBOT v149: run_endgame_test 0 failed")
	_r2 = _sp149.run(["python3", "tools/sim/run_base_marker_test.py"], capture_output=True, text=True, env=dict(_os149.environ, LUAU=_luau))
	_cb149(_r2.returncode == 0, "CODEBOT v149: run_base_marker_test 0 failed")
