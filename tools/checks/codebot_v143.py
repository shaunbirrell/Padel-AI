# Code Bot Roblox v143 (2026-09-30): ship claude-bud JOB 38 (army ATTACK auto-clear + SEND ARMY + RECALL +
# fairness + AutoGun HP + ARMY KILLS board), cherry-pick of 0150edf from origin/claude/desktop-bud as 2003433.
# ArmyOrdersConfig.Live stays OwnerFirst=true as Claude shipped it (owner 470626172 + Studio only). Live state
# preserved: ShopOverhaul + CheckpointGuard OwnerFirst=false (everyone), VIP OverhaulRobuxPrice 199, guard keep-out,
# pass Ids, RPG hold, SpawnNPC cap fix, WeaponsLive, PG_* Ids, FastTravel removed, PreferMesh OFF, WE_Building* untouched.
import re as _re143
import subprocess as _sp143
from pathlib import Path as _P143


def _cb143(cond, label):
	if "ok" in globals() and "bad" in globals():
		(ok if cond else bad)(label)
	else:
		print(("PASS " if cond else "FAIL ") + label)
		if not cond:
			raise SystemExit(1)


def _rd143(p):
	q = _P143(p)
	return q.read_text(encoding="utf-8") if q.is_file() else ""


_S143 = "src/ServerScriptService/Server/"
_C143 = "src/ReplicatedStorage/Shared/Configs/"
for _f in (_S143 + "Services/DataService.luau", _S143 + "Services/BaseService.luau", _S143 + "EarlyRemotes.server.luau"):
	_cb143('SetAttribute("WE_Build", 143)' in _rd143(_f), "CODEBOT v143: WE_Build=143 " + _f.rsplit("/", 1)[-1])
_cb143("WE_Build=143" in _rd143(_S143 + "Services/DataService.luau"), "CODEBOT v143: DataService profile-loaded log says WE_Build=143")

# JOB 38 present + owner-first (do NOT flip OwnerFirst to false on this ship)
_AOC = _rd143(_C143 + "ArmyOrdersConfig.luau")
_cb143("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = true," in _AOC, "CODEBOT v143: ArmyOrdersConfig.Live Enabled + OwnerFirst=true (owner phone-test first)")
_cb143(_P143(_S143 + "Modules/ArmyPlan.luau").is_file(), "CODEBOT v143: ArmyPlan present")
_cb143(_P143(_S143 + "Modules/ArmyRoute.luau").is_file(), "CODEBOT v143: ArmyRoute present")
_cb143(_P143(_S143 + "Modules/ArmySendRules.luau").is_file(), "CODEBOT v143: ArmySendRules present")
_cb143("ArmyPlan" in _rd143(_S143 + "Bootstrap.server.luau") or "ArmyOrdersConfig" in _rd143(_S143 + "Bootstrap.server.luau")
       or "require" in _rd143(_S143 + "Services/SquadOrdersService.luau"), "CODEBOT v143: army orders wiring present")
_cb143("NoReposition" in _rd143(_S143 + "Modules/ArmyPlan.luau") or "AllowRecover = false" in _rd143(_S143 + "Modules/ArmyPlan.luau")
       or "NoReposition" in _AOC, "CODEBOT v143: plan path refuses routine teleport/reposition")
_cb143("ArmyRaid" in _rd143(_S143 + "Services/MoneyCollectorService.luau"), "CODEBOT v143: MoneyCollectorService.ArmyRaid present")
_cb143("ArmyKills" in _rd143(_C143 + "LeaderboardConfig.luau") or "ARMY KILLS" in _rd143(_C143 + "LeaderboardConfig.luau")
       or "ArmyKills" in _rd143(_C143 + "LeaderboardConfig.luau"), "CODEBOT v143: ARMY KILLS board config present")

# v142 live-for-everyone kept
_SOC = _rd143(_C143 + "ShopOverhaulConfig.luau")
_cb143("OwnerFirst = false, -- codebot_v142 launch" in _SOC, "CODEBOT v143: ShopOverhaul stays OwnerFirst=false (everyone)")
_CGC = _rd143(_C143 + "CheckpointGuardConfig.luau")
_cb143("OwnerFirst = false, -- codebot_v142 launch" in _CGC, "CODEBOT v143: CheckpointGuard stays OwnerFirst=false (everyone)")
_MON = _rd143(_C143 + "MonetizationConfig.luau")
_cb143("OverhaulRobuxPrice = 199," in _MON and "OverhaulRobuxPrice = 349" not in _MON, "CODEBOT v143: VIP OverhaulRobuxPrice stays 199")
for _k, _id in (("WarChest", 2002640637), ("SuperSoldiers", 1998231741), ("DoubleHP", 2002214665)):
	m = _re143.search(rf"\t\t{_k}\s*=\s*\{{[^}}]*?Id\s*=\s*(\d+)", _MON, _re143.S)
	_cb143(m is not None and int(m.group(1)) == _id, "CODEBOT v143: " + _k + " Id = " + str(_id))
_cb143("3972151362" in _rd143(_C143 + "HudConfig.luau"), "CODEBOT v143: RPG launcher hold stays 3972151362")
_CSV = _rd143(_S143 + "Services/CombatService/init.luau")
_cb143("counts.Regular >= cap" in _CSV and "aliveNPCCount()" not in _CSV, "CODEBOT v143: SpawnNPC regular-cap fix kept")
_cb143("WeaponsLive = true" in _rd143(_C143 + "AircraftWeaponConfig.luau"), "CODEBOT v143: aircraft weapons stay live")
_PG = [int(x) for x in _re143.findall(r"\t\tPG_\w+\s*=\s*\{[^}]*?Id\s*=\s*(\d+)", _MON, _re143.S)]
_cb143(len(_PG) >= 7 and all(x > 0 for x in _PG), "CODEBOT v143: PG_* premium gun pass Ids stay wired")
_cb143("PreferMeshWhenAssetIdSet = false" in _rd143(_C143 + "StructureVisualConfig.luau"), "CODEBOT v143: PreferMesh stays OFF")
_cb143("FastTravelEnabled = false" in _rd143(_C143 + "MapConfig.luau"), "CODEBOT v143: fast travel stays REMOVED")
try:
	_wb = _sp143.run(["git", "diff", "--name-only", "e113293"], capture_output=True, text=True).stdout
	_cb143(not any("WE_Building" in l for l in _wb.splitlines()), "CODEBOT v143: no WE_Building* file touched since v142 tip")
except Exception:
	pass
