# Code Bot Roblox v132 (2026-09-30): STORE-PROPS. The owner's 80 Creator Store picks (docs/PROP-ASSETS.md) load live;
# 62 are wired by Shared/Configs/StorePropsConfig + Services/StorePropsService: world dressing for the JOB 31 sites /
# named areas and the JOB 33 rebirth zone upgrade visuals. Owner-first + kill switch. Claude's files untouched
# (RebirthZoneBuilder / RebirthZoneService / WorldSites / WorldKits). Fast travel stays REMOVED. PreferMesh stays OFF.
import re as _re132
from pathlib import Path as _P132


def _cb132(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


def _rd132(p):
    q = _P132(p)
    return q.read_text(encoding="utf-8") if q.is_file() else ""


def _code132(p):
    return "\n".join(l.split("--", 1)[0] for l in _rd132(p).splitlines())


_S132 = "src/ServerScriptService/Server/"
for _f in (_S132 + "Services/DataService.luau", _S132 + "Services/BaseService.luau", _S132 + "EarlyRemotes.server.luau"):
    pass  # v133 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v133.py: #_cb132('SetAttribute("WE_Build", 132)' in _rd132(_f), "CODEBOT v132: WE_Build=132 " + _f.rsplit("/", 1)[-1])
# v133 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v133.py: #_cb132("WE_Build=132" in _rd132(_S132 + "Services/DataService.luau"), "CODEBOT v132: DataService profile-loaded log says WE_Build=132")

_CFG132 = _rd132("src/ReplicatedStorage/Shared/Configs/StorePropsConfig.luau")
_SVC132 = _code132(_S132 + "Services/StorePropsService.luau")
_BOOT132 = _rd132(_S132 + "Bootstrap.server.luau")
_cb132(_CFG132 != "" and _SVC132 != "", "CODEBOT v132: StorePropsConfig + StorePropsService exist (DO NOT REMOVE)")
_cb132("DO NOT REMOVE" in _CFG132, "CODEBOT v132: StorePropsConfig carries the do-not-remove note")
_cb132("\tEnabled = true, -- KILL SWITCH" in _CFG132, "CODEBOT v132: StorePropsConfig.Enabled kill switch present")
_cb132("\tOwnerFirst = true," in _CFG132, "CODEBOT v132: store props ship owner-first")
_cb132('LiveAttribute = "WE_StorePropsOff"' in _CFG132 and "Cfg.LiveAttribute" in _SVC132, "CODEBOT v132: live kill attribute wired")
_ids132 = set(_re132.findall(r"^\t\t\[(\d+)\] = \{ Name = ", _CFG132, _re132.M))
_picks132 = set(_rd132("/workspace/props/picks_ids.txt").split())
_cb132(len(_ids132) == 80 and (not _picks132 or _picks132 == _ids132), "CODEBOT v132: all 80 picked ids listed in StorePropsConfig.Assets")
_rows132 = _re132.findall(r"\{ Id = (\d+), (?:At|L0) = ", _CFG132)
_cb132(len(set(_rows132)) >= 60, "CODEBOT v132: >= 60 distinct store ids are wired (world rows + zone rows)")
_cb132(all(r in _ids132 for r in _rows132), "CODEBOT v132: every row id is a listed asset")
for _rej in ("2473378608", "3117530492", "2580028799"):
    _cb132(_rej not in _rows132, f"CODEBOT v132: rejected id {_rej} is never placed")
for _z in ("WestYard", "StrategicYard", "WestStrip", "DroneBay", "EastYard", "EastStrip", "WestFlank"):
    _cb132(f"\t\t{_z} = {{" in _CFG132, f"CODEBOT v132: rebirth zone {_z} has store rows")
_cb132("ZoneKeepParts = { EastYard = true }" in _CFG132, "CODEBOT v132: Elite Barracks keeps its Part build (store barracks is a plain block)")
for _must in ("LuaSourceContainer", "Humanoid", "Anchored = true", "CanTouch = false", "Shadows = false", "MaxLightsPerModel",
              "ModelStreamingMode", "WE_Cluster", "MaxWorldParts", "MaxPlotParts", "MaxZoneServerParts", "BaseClearStuds",
              "RoadPad", "CheckLayout", "InsertService.LoadAsset", "task.defer"):
    _cb132(_must in _SVC132, f"CODEBOT v132: StorePropsService uses {_must}")
_cb132("RemoteEvent" not in _SVC132.replace('"RemoteEvent"', ""), "CODEBOT v132: StorePropsService has no remotes")
_cb132('safeInit("StorePropsService", StorePropsService, deps)' in _BOOT132
       and _BOOT132.find('safeInit("StorePropsService"') > _BOOT132.find('safeInit("RebirthZoneService"'),
       "CODEBOT v132: Bootstrap inits StorePropsService after RebirthZoneService")
_cb132(_P132("docs/PROP-ASSETS.md").is_file() and "80 / 80 load" in _rd132("docs/PROP-ASSETS.md"),
       "CODEBOT v132: docs/PROP-ASSETS.md lists every id + load status")
_cb132("StorePropsConfig" in _rd132("CLAUDE.md") and "DO NOT REMOVE" in _rd132("CLAUDE.md"),
       "CODEBOT v132: CLAUDE.md says store props live in StorePropsConfig and must not be removed")
# Claude's rebirth / site files are not touched by this job (read-only use)
_cb132("StoreProps" not in _rd132(_S132 + "Modules/RebirthZoneBuilder.luau")
       and "StoreProps" not in _rd132(_S132 + "Services/RebirthZoneService.luau")
       and "StoreProps" not in _rd132(_S132 + "Modules/WorldKits.luau"),
       "CODEBOT v132: RebirthZoneBuilder / RebirthZoneService / WorldKits untouched")
# QualityGovernor still watches the folders the copies live in
_QC132 = _rd132("src/ReplicatedStorage/Shared/Configs/QualityConfig.luau")
_cb132('"WorldFill"' in _QC132 and '"WE_RebirthZones"' in _QC132, "CODEBOT v132: QualityGovernor watches WorldFill + WE_RebirthZones (store copies culled with hysteresis)")

# Fast travel still OFF + PreferMesh OFF
_CTL132 = _code132("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/MapController.luau")
_MC132 = _rd132("src/ReplicatedStorage/Shared/Configs/MapConfig.luau")
_cb132("\tFastTravelEnabled = false,\n" in _MC132 and "RequestFastTravel" not in _CTL132 and '"TRAVEL"' not in _CTL132,
       "CODEBOT v132: still no fast travel")
_cb132("PreferMeshWhenAssetIdSet = false" in _rd132("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau"),
       "CODEBOT v132: PreferMesh stays OFF")
_cb132("WE_Building" not in _SVC132, "CODEBOT v132: StorePropsService never touches WE_Building*")
