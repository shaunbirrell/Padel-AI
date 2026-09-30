# Code Bot Roblox v141 (2026-09-30): ship claude-bud JOB 37 (real road checkpoint kit + killable checkpoint guards),
# cherry-pick of 332bd64 from origin/claude/desktop-bud. CheckpointGuardConfig.Live stays OwnerFirst=true as Claude
# shipped it. Live state preserved: v140 pass Ids, RPG hold 3972151362, SpawnNPC regular-cap fix, shop cash-row
# scroll fix, WeaponsLive=true, PG_* Ids, FastTravel removed, PreferMesh OFF, WE_Building* untouched.
import re as _re141
from pathlib import Path as _P141


def _cb141(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


def _rd141(p):
    q = _P141(p)
    return q.read_text(encoding="utf-8") if q.is_file() else ""


_S141 = "src/ServerScriptService/Server/"
_C141 = "src/ReplicatedStorage/Shared/Configs/"
for _f in (_S141 + "Services/DataService.luau", _S141 + "Services/BaseService.luau", _S141 + "EarlyRemotes.server.luau"):
    _cb141('SetAttribute("WE_Build", 141)' in _rd141(_f), "CODEBOT v141: WE_Build=141 " + _f.rsplit("/", 1)[-1])
_cb141("WE_Build=141" in _rd141(_S141 + "Services/DataService.luau"), "CODEBOT v141: DataService profile-loaded log says WE_Build=141")

# JOB 37 present + owner-first
_CGC = _rd141(_C141 + "CheckpointGuardConfig.luau")
_cb141("Enabled = true" in _CGC and "OwnerFirst = true" in _CGC, "CODEBOT v141: CheckpointGuardConfig.Live Enabled + OwnerFirst=true (as Claude shipped)")
_cb141(_P141(_S141 + "Services/CheckpointGuardService.luau").is_file(), "CODEBOT v141: CheckpointGuardService present")
_cb141("CheckpointGuardService" in _rd141(_S141 + "Bootstrap.server.luau"), "CODEBOT v141: Bootstrap inits CheckpointGuardService")
_CGS = _rd141(_S141 + "Services/CheckpointGuardService.luau")
_cb141(":TakeDamage(" not in _CGS and not _re141.search(r"\.Health\s*=[^=]", _CGS), "CODEBOT v141: guard service never writes Health / TakeDamage (combat via CombatService)")
_CNPC = _rd141(_S141 + "Services/CombatService/CombatNPC.luau")
_cb141("not (tState and now < tState.InvulnerableUntil)" in _CNPC,
       "CODEBOT v141: NPC shots (guards included) still skip spawn / novice shield (InvulnerableUntil)")
_cb141("checkpoint = true" in _rd141(_C141 + "MonetizationConfig.luau"), "CODEBOT v141: checkpoint bonus exempt from cash mults")

# live state preserved through the cherry-pick
_MON = _rd141(_C141 + "MonetizationConfig.luau")
for _k, _id in (("WarChest", 2002640637), ("SuperSoldiers", 1998231741), ("DoubleHP", 2002214665)):
    m = _re141.search(rf"\t\t{_k}\s*=\s*\{{[^}}]*?Id\s*=\s*(\d+)", _MON, _re141.S)
    _cb141(m is not None and int(m.group(1)) == _id, "CODEBOT v141: " + _k + " Id = " + str(_id) + " (v140)")
_cb141("3972151362" in _rd141(_C141 + "HudConfig.luau"), "CODEBOT v141: RPG launcher hold stays 3972151362")
_CSV = _rd141(_S141 + "Services/CombatService/init.luau")
_cb141("counts.Regular >= cap" in _CSV and "aliveNPCCount()" not in _CSV, "CODEBOT v141: SpawnNPC regular-cap fix kept")
_cb141("list.CanvasPosition = Vector2.new(0, rowCanvasY(list, row))" in _rd141("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau"),
       "CODEBOT v141: shop cash + still scrolls to the Cash Pack Mega row")
_cb141("WeaponsLive = true" in _rd141(_C141 + "AircraftWeaponConfig.luau"), "CODEBOT v141: aircraft weapons stay live")
_PG = [int(x) for x in _re141.findall(r"\t\tPG_\w+\s*=\s*\{[^}]*?Id\s*=\s*(\d+)", _MON, _re141.S)]
_cb141(len(_PG) >= 7 and all(x > 0 for x in _PG), "CODEBOT v141: PG_* premium gun pass Ids stay wired")
_cb141("PreferMeshWhenAssetIdSet = false" in _rd141(_C141 + "StructureVisualConfig.luau"), "CODEBOT v141: PreferMesh stays OFF")
_cb141("FastTravelEnabled = false" in _rd141(_C141 + "MapConfig.luau"), "CODEBOT v141: fast travel stays REMOVED")
