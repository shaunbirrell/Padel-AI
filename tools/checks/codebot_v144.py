# Code Bot Roblox v144 (2026-09-30): merge claude-bud JOB 39 phase 1 (rebirth scale + EMPIRE LEVEL +
# Command Office) owner-first onto phase-7-polish. NOT published (awaiting Studio §11 proof).
# EndgameConfig.Live OwnerFirst=true; PreferMesh OFF; WE_Building* untouched; WE_Build 144.
import re as _re144
import subprocess as _sp144
from pathlib import Path as _P144


def _cb144(cond, label):
	if "ok" in globals() and "bad" in globals():
		(ok if cond else bad)(label)
	else:
		print(("PASS " if cond else "FAIL ") + label)
		if not cond:
			raise SystemExit(1)


def _rd144(p):
	q = _P144(p)
	return q.read_text(encoding="utf-8") if q.is_file() else ""


_S144 = "src/ServerScriptService/Server/"
_C144 = "src/ReplicatedStorage/Shared/Configs/"
# v145 (Code Bot Roblox): the WE_Build=144 pins are superseded in tools/checks/codebot_v145.py (WE_Build=145).

_EC = _rd144(_C144 + "EndgameConfig.luau")
_cb144("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = false," in _EC, "CODEBOT v144: EndgameConfig.Live Enabled + OwnerFirst=false (v166 flip-all-live) (await Studio §11)")
_cb144(_P144(_S144 + "Services/EndgameService.luau").is_file(), "CODEBOT v144: EndgameService present")
_cb144(_P144("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/EndgameController.luau").is_file(), "CODEBOT v144: EndgameController present")
_cb144(_P144(_C144 + "PlazaServicesConfig.luau").is_file(), "CODEBOT v144: PlazaServicesConfig present")

# Live state kept from v143/v142
_AOC = _rd144(_C144 + "ArmyOrdersConfig.luau")
_cb144("OwnerFirst = false" in _AOC, "CODEBOT v144: ArmyOrdersConfig OwnerFirst=false (v166 flip-all-live)")
_SOC = _rd144(_C144 + "ShopOverhaulConfig.luau")
_cb144("OwnerFirst = false, -- codebot_v142 launch" in _SOC, "CODEBOT v144: ShopOverhaul stays OwnerFirst=false")
_CGC = _rd144(_C144 + "CheckpointGuardConfig.luau")
_cb144("OwnerFirst = false, -- codebot_v142 launch" in _CGC, "CODEBOT v144: CheckpointGuard stays OwnerFirst=false")
_cb144("PreferMeshWhenAssetIdSet = false" in _rd144(_C144 + "StructureVisualConfig.luau"), "CODEBOT v144: PreferMesh stays OFF")
_cb144("FastTravelEnabled = false" in _rd144(_C144 + "MapConfig.luau"), "CODEBOT v144: fast travel stays REMOVED")

try:
	_wb = _sp144.run(["git", "diff", "--name-only", "83eeb88"], capture_output=True, text=True).stdout
	_cb144(not any("WE_Building" in l for l in _wb.splitlines()), "CODEBOT v144: no WE_Building* file touched since v143 tip")
except Exception:
	pass
