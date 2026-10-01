# Code Bot Roblox v146 (2026-09-30): cherry-pick claude-bud JOB 39 phase 2 (Base Tier + Defence tree +
# Engineering Bureau + instant rebuild) owner-first onto phase-7-polish. Feature tip 9e15f27.
# EndgameConfig.Live OwnerFirst=true; Parts.BaseTier + Defence true; PreferMesh OFF; WE_Building* untouched; WE_Build 146.
# JOB 38 army SEND/ATTACK fix (v145) kept on phase-7 (bud was behind; cherry-pick only, no bud merge).
import os as _os146
import re as _re146
import subprocess as _sp146
from pathlib import Path as _P146


def _cb146(cond, label):
	if "ok" in globals() and "bad" in globals():
		(ok if cond else bad)(label)
	else:
		print(("PASS " if cond else "FAIL ") + label)
		if not cond:
			raise SystemExit(1)


def _rd146(p):
	q = _P146(p)
	return q.read_text(encoding="utf-8") if q.is_file() else ""


_S146 = "src/ServerScriptService/Server/"
_C146 = "src/ReplicatedStorage/Shared/Configs/"
_CL146 = "src/StarterPlayer/StarterPlayerScripts/Client/"
# v147 (Code Bot Roblox): the WE_Build=146 pins are superseded in tools/checks/codebot_v147.py (WE_Build=147).

# phase 2 feature presence
_EC = _rd146(_C146 + "EndgameConfig.luau")
_cb146("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = false," in _EC, "CODEBOT v146: EndgameConfig.Live Enabled + OwnerFirst=false (v166 flip-all-live)")
_cb146("\t\tBaseTier = true," in _EC and "\t\tDefence = true," in _EC, "CODEBOT v146: Parts.BaseTier + Defence true (phase 2)")
_cb146(_P146(_S146 + "Modules/BaseTierBuilder.luau").is_file(), "CODEBOT v146: BaseTierBuilder present")
_cb146(_P146(_S146 + "Services/EndgameService.luau").is_file(), "CODEBOT v146: EndgameService present")
_cb146(_P146(_CL146 + "Controllers/EndgameController.luau").is_file(), "CODEBOT v146: EndgameController present")
_ES = _rd146(_S146 + "Services/EndgameService.luau")
_cb146("endgame_" in _ES and "function EndgameService.Purchase" in _ES, "CODEBOT v146: EndgameService.Purchase path present")
_GD = _rd146(_S146 + "Services/GateDefenseService.luau")
_cb146("GateHpMult" in _GD or "RebuildSeconds" in _GD, "CODEBOT v146: GateDefenseService hooks for tier/defence")
_cb146("VaultMult" in _rd146(_S146 + "Services/MoneyCollectorService.luau"), "CODEBOT v146: MoneyCollectorService.VaultMult")

# JOB 38 army fix must still be on phase-7 (do not regress)
_AP = _rd146(_S146 + "Modules/ArmyPlan.luau")
_cb146("local start = if c then c else plan.Lead" in _AP and "ArmyRoute.PointAlong(start, route, standoff)" in _AP,
	"CODEBOT v146: JOB 38 army routes still start at the block (v145 kept)")

# live state kept
_AOC = _rd146(_C146 + "ArmyOrdersConfig.luau")
_cb146("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = false," in _AOC, "CODEBOT v146: ArmyOrdersConfig OwnerFirst=false (v166 flip-all-live)")
_cb146("OwnerFirst = false, -- codebot_v142 launch" in _rd146(_C146 + "ShopOverhaulConfig.luau"), "CODEBOT v146: ShopOverhaul stays OwnerFirst=false")
_cb146("OwnerFirst = false, -- codebot_v142 launch" in _rd146(_C146 + "CheckpointGuardConfig.luau"), "CODEBOT v146: CheckpointGuard stays OwnerFirst=false")
_cb146("PreferMeshWhenAssetIdSet = false" in _rd146(_C146 + "StructureVisualConfig.luau"), "CODEBOT v146: PreferMesh stays OFF")
_cb146("FastTravelEnabled = false" in _rd146(_C146 + "MapConfig.luau"), "CODEBOT v146: fast travel stays REMOVED")

# VIP 199 still (not 349); WeaponsLive stays true
_MC = _rd146(_C146 + "MonetizationConfig.luau")
_cb146("		VIP = {" in _MC and "RobuxPrice = 199," in _MC.split("VIP = {", 1)[1][:400], "CODEBOT v146: VIP RobuxPrice stays 199")
_RC = _rd146(_C146 + "RebirthConfig.luau")
_cb146("WeaponsLive = true" in _RC or "WeaponsLive = true," in _RC, "CODEBOT v146: WeaponsLive stays true")

try:
	_wb = _sp146.run(["git", "diff", "--name-only", "af3a858"], capture_output=True, text=True).stdout
	_cb146(not any("WE_Building" in l for l in _wb.splitlines()), "CODEBOT v146: no WE_Building* file touched since v145 tip")
	# claude-bud JOB 40 part B: retired the whole-file MonetizationConfig guard (it now carries the speed helper);
	# replacement: WeaponConfig / RebirthConfig untouched, and no Robux price / Id line changed in MonetizationConfig
	_cb146(not any(l in (_C146 + "WeaponConfig.luau", _C146 + "RebirthConfig.luau") for l in _wb.splitlines()),
		"CODEBOT v146: RPG hold / WeaponsLive configs untouched since v145 tip (claude-bud JOB 40 replacement)")
	import re as _re146
	_md146 = _sp146.run(["git", "diff", "-U0", "af3a858", "--", _C146 + "MonetizationConfig.luau"], capture_output=True, text=True).stdout
	# v156 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v156.py (the config RobuxPrice is now only the display
	# fallback; v156 corrected StarterBundle 149->249 and ExtraSoldierSlot 99->79 to the real Creator Hub prices and pins every
	# config price to the audited Creator Hub price + every Id unchanged since v155):
	# _cb146(not any(_re146.search(r"\bRobuxPrice\s*=|(^|[\s{,])Id\s*=\s*\d", l) for l in _md146.splitlines() if l[:1] in "+-" and not l.startswith(("+++", "---"))),
	# 	"CODEBOT v146: no Robux price / Id line changed in MonetizationConfig since v145 tip (claude-bud JOB 40 replacement)")
	pass
except Exception:
	pass

# endgame sim when LUAU is available
_luau = _os146.environ.get("LUAU") or str(_P146.home() / ".local/bin/luau")
if _P146(_luau).is_file():
	_r = _sp146.run(["python3", "tools/sim/run_endgame_test.py"], capture_output=True, text=True, env=dict(_os146.environ, LUAU=_luau))
	_cb146(_r.returncode == 0, "CODEBOT v146: run_endgame_test 0 failed")
