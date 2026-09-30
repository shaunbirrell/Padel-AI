# Code Bot Roblox v142 (2026-09-30): owner launch 16:24 — JOB 36 shop overhaul (ShopOverhaulConfig.Live.OwnerFirst
# = false) and JOB 37 checkpoint guards (CheckpointGuardConfig.Live.OwnerFirst = false; mission objective, map rows,
# cleared bonus) for everyone. VIP stays 199 on the Creator Hub (owner has NOT approved 349): the overhaul Shop shows
# 199 (MonetizationConfig VIP.OverhaulRobuxPrice = 199). Guard keep-out: no guards within 130 studs of a base plot, a
# spawn or a vehicle spawn pad; Depot.CP_E / Armory.CP_W (~54 studs from Pool_Depot / Pool_Armory) build plain, so
# the 6 detailed (guarded) checkpoints are Town CP_N/E/S/W + Depot.CP_W + Armory.CP_E. Guards never target a player
# under the spawn / novice shield. Live state preserved: pass Ids, RPG hold, SpawnNPC cap fix, WeaponsLive, PG_* Ids,
# FastTravel removed, PreferMesh OFF, WE_Building* untouched.
import re as _re142
import subprocess as _sp142
from pathlib import Path as _P142


def _cb142(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


def _rd142(p):
    q = _P142(p)
    return q.read_text(encoding="utf-8") if q.is_file() else ""


_S142 = "src/ServerScriptService/Server/"
_C142 = "src/ReplicatedStorage/Shared/Configs/"
# v143 (Code Bot Roblox): the WE_Build=142 pins are superseded in tools/checks/codebot_v143.py (WE_Build=143).

# the two launches
_SOC = _rd142(_C142 + "ShopOverhaulConfig.luau")
_cb142("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = false, -- codebot_v142 launch" in _SOC, "CODEBOT v142: ShopOverhaulConfig.Live Enabled + OwnerFirst=false (everyone)")
_CGC = _rd142(_C142 + "CheckpointGuardConfig.luau")
_cb142("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = false, -- codebot_v142 launch" in _CGC, "CODEBOT v142: CheckpointGuardConfig.Live Enabled + OwnerFirst=false (everyone)")
_cb142("L.Enabled == true and L.OwnerFirst ~= true" in _CGC, "CODEBOT v142: LiveForAll -> the daily Checkpoint objective is offered")
_cb142("CheckpointGuardConfig) :: any).LiveForAll()" in _rd142(_S142 + "Services/MissionService.luau"), "CODEBOT v142: MissionService offers Checkpoint only via LiveForAll")

# VIP: the real price, one value; no other price changed
_MON = _rd142(_C142 + "MonetizationConfig.luau")
_cb142("\t\tVIP = {\n\t\t\tId = 1985475542,\n\t\t\tDisplayName = \"VIP\",\n\t\t\tRobuxPrice = 199," in _MON and "OverhaulRobuxPrice = 199," in _MON
       and "OverhaulRobuxPrice = 349" not in _MON, "CODEBOT v142: VIP 199 on the Creator Hub and 199 in the overhaul Shop (no 349)")
_cb142(_MON.count("OverhaulRobuxPrice") == 1, "CODEBOT v142: VIP display price is a single config value")
for _k, _id, _price in (("WarChest", 2002640637, 799), ("SuperSoldiers", 1998231741, 349), ("DoubleHP", 2002214665, 199)):
    m = _re142.search(rf"\t\t{_k}\s*=\s*\{{[^}}]*?Id\s*=\s*(\d+)", _MON, _re142.S)
    m2 = _re142.search(rf"\t\t{_k}\s*=\s*\{{[^}}]*?RobuxPrice\s*=\s*(\d+)", _MON, _re142.S)
    _cb142(m is not None and int(m.group(1)) == _id and m2 is not None and int(m2.group(1)) == _price,
           "CODEBOT v142: " + _k + " Id " + str(_id) + " R$ " + str(_price))
try:
    _diff = _sp142.run(["git", "diff", "758edeb", "--", _C142 + "MonetizationConfig.luau"], capture_output=True, text=True).stdout
    _chg = [l for l in _diff.splitlines() if l[:1] in "+-" and not l.startswith(("+++", "---")) and "RobuxPrice" in l]
    # v156 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v156.py (the config RobuxPrice is now only the display
    # fallback; v156 corrected StarterBundle 149->249 and ExtraSoldierSlot 99->79 to the real Creator Hub prices and pins every
    # config price to the audited Creator Hub price + every Id unchanged since v155):
    # _cb142(all("OverhaulRobuxPrice" in l for l in _chg), "CODEBOT v142: no RobuxPrice changed since v141 except the VIP display value")
    pass
except Exception:
    pass

# guards: keep-out + shared protection rule
_CGS = _rd142(_S142 + "Services/CheckpointGuardService.luau")
_cb142("KeepOutStuds = 130," in _CGC and "function CheckpointGuardService.KeepOutHit(" in _CGS and "function CheckpointGuardService.BuildKeepZones(" in _CGS
       and "keepZones = CheckpointGuardService.BuildKeepZones()" in _CGS, "CODEBOT v142: guard keep-out 130 studs (plots, spawns, vehicle pads)")
_cb142("return live(p.UserId) and not CheckpointGuardService.Protected(p)" in _CGS and '"IsSpawnInvulnerable", "IsNoviceShielded"' in _CGS,
       "CODEBOT v142: guards never target a spawn / novice shielded player")
_cb142("not (tState and now < tState.InvulnerableUntil)" in _rd142(_S142 + "Services/CombatService/CombatNPC.luau"),
       "CODEBOT v142: NPC shots still skip InvulnerableUntil (spawn + novice shield)")
_cb142(":TakeDamage(" not in _CGS and not _re142.search(r"\.Health\s*=[^=]", _CGS), "CODEBOT v142: guard service never writes Health / TakeDamage")
_IND = _rd142(_S142 + "Modules/POILayouts/Industry.luau")
_cb142(_IND.count('Kit = "Checkpoint", X = 0, Z = 0, NoDetail = true }') == 2
       and 'X = -1127, Z = 0, Yaw = -90, Street = true, Kits = { { Kit = "Checkpoint", X = 0, Z = 0, NoDetail = true }' in _IND
       and 'X = 1127, Z = 0, Yaw = 90, Street = true, Kits = { { Kit = "Checkpoint", X = 0, Z = 0, NoDetail = true }' in _IND,
       "CODEBOT v142: Depot.CP_E / Armory.CP_W build plain (no guards next to Pool_Depot / Pool_Armory)")
_cb142("NoDetail = if plainRebuild or (k :: any).NoDetail == true then true else nil" in _rd142(_S142 + "Modules/WorldPOI.luau")
       and "NoDetail: boolean?" in _rd142(_C142 + "WorldConfig.luau"), "CODEBOT v142: WorldPOI honours a row's NoDetail")

# live state preserved
_cb142("3972151362" in _rd142(_C142 + "HudConfig.luau"), "CODEBOT v142: RPG launcher hold stays 3972151362")
_CSV = _rd142(_S142 + "Services/CombatService/init.luau")
_cb142("counts.Regular >= cap" in _CSV and "aliveNPCCount()" not in _CSV, "CODEBOT v142: SpawnNPC regular-cap fix kept")
_cb142("WeaponsLive = true" in _rd142(_C142 + "AircraftWeaponConfig.luau"), "CODEBOT v142: aircraft weapons stay live")
_PG = [int(x) for x in _re142.findall(r"\t\tPG_\w+\s*=\s*\{[^}]*?Id\s*=\s*(\d+)", _MON, _re142.S)]
_cb142(len(_PG) >= 7 and all(x > 0 for x in _PG), "CODEBOT v142: PG_* premium gun pass Ids stay wired")
_cb142("PreferMeshWhenAssetIdSet = false" in _rd142(_C142 + "StructureVisualConfig.luau"), "CODEBOT v142: PreferMesh stays OFF")
_cb142("FastTravelEnabled = false" in _rd142(_C142 + "MapConfig.luau"), "CODEBOT v142: fast travel stays REMOVED")
try:
    _wb = _sp142.run(["git", "diff", "--name-only", "758edeb"], capture_output=True, text=True).stdout
    _cb142(not any("WE_Building" in l for l in _wb.splitlines()), "CODEBOT v142: no WE_Building* file touched")
except Exception:
    pass
