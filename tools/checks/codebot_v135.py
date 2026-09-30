# Code Bot Roblox v135 (2026-09-30): ship claude-bud JOB 35 premium guns armory
# (OwnerFirst=true, pass Ids still 0). PreferMesh OFF. WE_Building* untouched. Fast travel stays REMOVED.
from pathlib import Path as _P135


def _cb135(cond, label):
	if "ok" in globals() and "bad" in globals():
		(ok if cond else bad)(label)
	else:
		print(("PASS " if cond else "FAIL ") + label)
		if not cond:
			raise SystemExit(1)


def _rd135(p):
	q = _P135(p)
	return q.read_text(encoding="utf-8") if q.is_file() else ""


_S135 = "src/ServerScriptService/Server/"
# v136 (Code Bot Roblox): retired WE_Build pins, superseded in tools/checks/codebot_v136.py
for _f in (_S135 + "Services/DataService.luau", _S135 + "Services/BaseService.luau", _S135 + "EarlyRemotes.server.luau"):
	pass  # v136 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v136.py: #_cb135('SetAttribute("WE_Build", 135)' in _rd135(_f), "CODEBOT v135: WE_Build=135 " + _f.rsplit("/", 1)[-1])
# v136 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v136.py: #_cb135("WE_Build=135" in _rd135(_S135 + "Services/DataService.luau"), "CODEBOT v135: DataService profile-loaded log says WE_Build=135")

_PG = _rd135("src/ReplicatedStorage/Shared/Configs/PremiumGunsConfig.luau")
# v136 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v136.py (launched for everyone): #_cb135("OwnerFirst = true" in _PG and "Enabled = true" in _PG, "CODEBOT v135: PremiumGunsConfig Live Enabled + OwnerFirst=true")
_cb135("OwnerTestGrant = true" in _PG, "CODEBOT v135: OwnerTestGrant=true while pass Ids are 0")
_cb135(_P135(_S135 + "Services/PremiumGunService.luau").is_file(), "CODEBOT v135: PremiumGunService present")
_cb135(_P135("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ArmoryController.luau").is_file(), "CODEBOT v135: ArmoryController present")
_cb135(_P135("src/ReplicatedStorage/Shared/Util/GunMechanics.luau").is_file(), "CODEBOT v135: GunMechanics present")
_cb135(_P135("src/StarterPlayer/StarterPlayerScripts/Client/Modules/Scope.luau").is_file(), "CODEBOT v135: Scope module present")

_MC = _rd135("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau")
for _k in ("PG_Sovereign", "PG_Quake", "PG_Longshot", "PG_Havoc", "PG_Thunderhead", "PG_Tempest", "PG_ArmoryPass"):
	_cb135((_k + " = {") in _MC, "CODEBOT v135: MonetizationConfig has " + _k)

_cb135("PreferMeshWhenAssetIdSet = false" in _rd135("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau"), "CODEBOT v135: PreferMesh stays OFF")
_cb135("FastTravelEnabled = false" in _rd135("src/ReplicatedStorage/Shared/Configs/MapConfig.luau"), "CODEBOT v135: fast travel stays REMOVED")
_cb135("PreferMesh = true" not in _rd135("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau"), "CODEBOT v135: VisualAssetConfig PreferMesh not true")
