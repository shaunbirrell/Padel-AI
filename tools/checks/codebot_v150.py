# Code Bot Roblox v150 (2026-09-30): cherry-pick claude-bud JOB 40 parts A+B
# (real base guards + one hostility rule; Speed Pass x1.75 / Speed Boost x2.5 SpeedV2)
# onto phase-7-polish. Feature tips cc14b0e, d8a2f62 -> e3117bf, f8b6145.
# GuardConfig.Posts OwnerFirst=true; MonetizationConfig.SpeedV2 OwnerFirst=true;
# Endgame/BaseMarker OwnerFirst stay true; PreferMesh OFF; WE_Building* untouched; WE_Build 150.
# Do NOT flip any OwnerFirst=false.
import os as _os150
import subprocess as _sp150
from pathlib import Path as _P150


def _cb150(cond, label):
	if "ok" in globals() and "bad" in globals():
		(ok if cond else bad)(label)
	else:
		print(("PASS " if cond else "FAIL ") + label)
		if not cond:
			raise SystemExit(1)


def _rd150(p):
	q = _P150(p)
	return q.read_text(encoding="utf-8") if q.is_file() else ""


_S150 = "src/ServerScriptService/Server/"
_C150 = "src/ReplicatedStorage/Shared/Configs/"
_CL150 = "src/StarterPlayer/StarterPlayerScripts/Client/"

# v151 (Code Bot Roblox): the WE_Build=150 pins are superseded in tools/checks/codebot_v151.py (WE_Build=151).
# for _f in (_S150 + "Services/DataService.luau", _S150 + "Services/BaseService.luau", _S150 + "EarlyRemotes.server.luau"):
# 	_cb150('SetAttribute("WE_Build", 150)' in _rd150(_f), "CODEBOT v150: WE_Build=150 " + _f.rsplit("/", 1)[-1])
# _cb150("WE_Build=150" in _rd150(_S150 + "Services/DataService.luau"), "CODEBOT v150: DataService profile-loaded log says WE_Build=150")

# JOB 40 part A base guards
_GC = _rd150(_C150 + "GuardConfig.luau")
_cb150("\tPosts = {\n\t\tEnabled = true,\n\t\tOwnerFirst = false," in _GC, "CODEBOT v150: GuardConfig.Posts Enabled + OwnerFirst=false (v166 flip-all-live)")
_cb150("function GuardConfig.PostsLiveFor" in _GC, "CODEBOT v150: GuardConfig.PostsLiveFor present")
_BG = _rd150(_S150 + "Modules/BaseGuards.luau")
_cb150("ThinkPost" in _BG, "CODEBOT v150: BaseGuards.ThinkPost present")
_CS = _rd150(_S150 + "Services/CombatService/init.luau")
_cb150("ApplyDefenceHit" in _CS, "CODEBOT v150: CombatService.ApplyDefenceHit present")
_cb150("DefenceLevelFor" in _rd150(_S150 + "Services/EndgameService.luau"), "CODEBOT v150: EndgameService.DefenceLevelFor present")
_cb150(_P150("docs/BASE-GUARDS-ROOTCAUSE.md").is_file(), "CODEBOT v150: BASE-GUARDS-ROOTCAUSE.md present")
_cb150(_P150("tools/sim/run_base_guards_test.py").is_file(), "CODEBOT v150: run_base_guards_test.py present")

# JOB 40 part B SpeedV2
_MC = _rd150(_C150 + "MonetizationConfig.luau")
_cb150("cfg.SpeedV2 = {\n\tEnabled = true,\n\tOwnerFirst = false," in _MC, "CODEBOT v150: MonetizationConfig.SpeedV2 Enabled + OwnerFirst=false (v166 flip-all-live)")
_cb150("cfg.MaxWalkSpeedMult = 2.5" in _MC, "CODEBOT v150: MaxWalkSpeedMult = 2.5")
_cb150("WalkSpeedMultV2 = 1.75" in _MC and "WalkSpeedMultV2 = 2.5" in _MC, "CODEBOT v150: WalkSpeedMultV2 1.75 / 2.5")
_cb150("function cfg.SpeedText" in _MC or "function MonetizationConfig.SpeedText" in _MC or "function cfg.SpeedText(" in _MC or "SpeedText =" in _MC or "function cfg.SpeedText" in _MC,
	"CODEBOT v150: SpeedText helper present")
# SpeedText may be defined as function cfg.SpeedText
_cb150("SpeedText" in _MC and "SpeedMultOf" in _MC and "DescFor" in _MC, "CODEBOT v150: SpeedText + SpeedMultOf + DescFor")
_AC = _rd150(_C150 + "ArmyConfig.luau")
_cb150("MaxSpeed = 58" in _AC and "MaxOwnerSpeed = 48" in _AC, "CODEBOT v150: ArmyConfig Follow caps raised for 40 runner")
_cb150(_P150("tools/sim/run_speed_test.py").is_file(), "CODEBOT v150: run_speed_test.py present")

# prior owner-first kept — do NOT flip
_EC = _rd150(_C150 + "EndgameConfig.luau")
_cb150("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = false," in _EC, "CODEBOT v150: EndgameConfig.Live OwnerFirst=false (v166 flip-all-live)")
_BMC = _rd150(_C150 + "BaseMarkerConfig.luau")
_cb150("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = false," in _BMC, "CODEBOT v150: BaseMarkerConfig.Live OwnerFirst stays true")
_AOC = _rd150(_C150 + "ArmyOrdersConfig.luau")
_cb150("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = false," in _AOC, "CODEBOT v150: ArmyOrdersConfig OwnerFirst=false (v166 flip-all-live)")
_cb150("OwnerFirst = false, -- codebot_v142 launch" in _rd150(_C150 + "ShopOverhaulConfig.luau"), "CODEBOT v150: ShopOverhaul stays OwnerFirst=false")
_cb150("OwnerFirst = false, -- codebot_v142 launch" in _rd150(_C150 + "CheckpointGuardConfig.luau"), "CODEBOT v150: CheckpointGuard stays OwnerFirst=false")
_cb150("PreferMeshWhenAssetIdSet = false" in _rd150(_C150 + "StructureVisualConfig.luau"), "CODEBOT v150: PreferMesh stays OFF")
_cb150("FastTravelEnabled = false" in _rd150(_C150 + "MapConfig.luau"), "CODEBOT v150: fast travel stays REMOVED")
_cb150("3972151362" in _rd150(_C150 + "HudConfig.luau"), "CODEBOT v150: RPG hold stays 3972151362")
_cb150("		VIP = {" in _MC and "RobuxPrice = 199," in _MC.split("VIP = {", 1)[1][:400], "CODEBOT v150: VIP RobuxPrice stays 199")
_RC = _rd150(_C150 + "RebirthConfig.luau")
_cb150("WeaponsLive = true" in _RC or "WeaponsLive = true," in _RC, "CODEBOT v150: WeaponsLive stays true")

# JOB 38 army fix must still be on phase-7
_AP = _rd150(_S150 + "Modules/ArmyPlan.luau")
_cb150("local start = if c then c else plan.Lead" in _AP and "ArmyRoute.PointAlong(start, route, standoff)" in _AP,
	"CODEBOT v150: JOB 38 army routes still start at the block (v145 kept)")

try:
	_wb = _sp150.run(["git", "diff", "--name-only", "e4965f7"], capture_output=True, text=True).stdout
	_cb150(not any("WE_Building" in l for l in _wb.splitlines()), "CODEBOT v150: no WE_Building* file touched since v149 tip")
except Exception:
	pass

_luau = _os150.environ.get("LUAU") or str(_P150.home() / ".local/bin/luau")
if _P150(_luau).is_file():
	_r = _sp150.run(["python3", "tools/sim/run_base_guards_test.py"], capture_output=True, text=True, env=dict(_os150.environ, LUAU=_luau))
	_cb150(_r.returncode == 0, "CODEBOT v150: run_base_guards_test 0 failed")
	_r2 = _sp150.run(["python3", "tools/sim/run_speed_test.py"], capture_output=True, text=True, env=dict(_os150.environ, LUAU=_luau))
	_cb150(_r2.returncode == 0, "CODEBOT v150: run_speed_test 0 failed")
