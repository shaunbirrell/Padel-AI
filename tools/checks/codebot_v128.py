# Code Bot Roblox v128 (2026-09-30): ship claude-bud JOB 31 (real prop detail + 8 sites + activities) onto
# phase-7-polish. Fast travel stays REMOVED (v127 owner request). PreferMesh stays OFF. WE_Building* untouched.
# JOB 31 activities/garrisons ship OwnerFirst (UserId 470626172 + Studio).
import re as _re128
from pathlib import Path as _P128


def _cb128(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


def _rd128(p):
    q = _P128(p)
    return q.read_text(encoding="utf-8") if q.is_file() else ""


def _code128(p):
    return "\n".join(l.split("--", 1)[0] for l in _rd128(p).splitlines())


_S128 = "src/ServerScriptService/Server/"
for _f in (_S128 + "Services/DataService.luau", _S128 + "Services/BaseService.luau", _S128 + "EarlyRemotes.server.luau"):
    _cb128('SetAttribute("WE_Build", 128)' in _rd128(_f), "CODEBOT v128: WE_Build=128 " + _f.rsplit("/", 1)[-1])
_cb128("WE_Build=128" in _rd128(_S128 + "Services/DataService.luau"), "CODEBOT v128: DataService profile-loaded log says WE_Build=128")

# ── fast travel is OFF (owner request; carried from v127) ───────────────────────────────────────────────────────
_MC128 = _rd128("src/ReplicatedStorage/Shared/Configs/MapConfig.luau")
_cb128("\tFastTravelEnabled = false,\n" in _MC128 and "FastTravel = {" not in _MC128 and "CooldownSeconds" not in _MC128,
       "CODEBOT v128: MapConfig.FastTravelEnabled = false and no FastTravel block / cooldown")
_cb128("FastTravelEnabled = true" not in _MC128, "CODEBOT v128: fast travel never switched on")
_cb128("SiteKindInfo = {" in _MC128 and 'camp = "Enemy camp"' in _MC128,
       "CODEBOT v128: MapConfig.SiteKindInfo from JOB 31 is present")

_FT_CODE = _re128.compile(r"FastTravel|RequestFastTravel|fast_travel|FAST_TRAVEL|TravelIn|lastTravelAt")
_hits = []
for _p in _P128("src").rglob("*.luau"):
    _c = _code128(str(_p))
    for _m in _FT_CODE.finditer(_c):
        if _m.group(0) == "FastTravel" and "FastTravelEnabled" in _c[_m.start():_m.start() + 20]:
            continue
        _hits.append(str(_p) + ":" + _m.group(0))
_cb128(not _hits, "CODEBOT v128: no fast-travel remote / handler / state in src " + (", ".join(sorted(set(_hits))[:6]) if _hits else ""))

_SVC128 = _code128(_S128 + "Services/MapService.luau")
_cb128("OnServerInvoke" in _SVC128 and _SVC128.count("OnServerInvoke") == 1 and "RequestMapLive" in _SVC128,
       "CODEBOT v128: MapService has exactly one handler (RequestMapLive, read-only)")
_cb128("StreamPrefetch" not in _SVC128 and "TeleportToPlot" not in _SVC128 and "PivotTo" not in _SVC128 and ":Place(" not in _SVC128,
       "CODEBOT v128: MapService never moves a player (no teleport path)")
_cb128("Sites" in _SVC128 and "WorldSites" in _SVC128, "CODEBOT v128: MapService live feed includes JOB 31 Sites")

_CTL128 = _code128("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/MapController.luau")
_cb128('"TRAVEL"' not in _CTL128 and "travelB" not in _CTL128 and "travelBtn" not in _CTL128 and "InvokeServer(target)" not in _CTL128,
       "CODEBOT v128: the map UI has no TRAVEL button")
_cb128('button(row, "Go", "GO"' in _CTL128 and 'button(row, "ClearPin", "CLEAR PIN"' in _CTL128,
       "CODEBOT v128: GO + CLEAR PIN stay (tap-to-pin kept)")
_cb128("Pin = true," in _CTL128 and "ObjectiveMarker.ShowWith(" in _CTL128 and 'Instance.new("Beam")' not in _CTL128,
       "CODEBOT v128: tap-to-pin uses the ONE yellow tracker (ObjectiveMarker), no second Beam")
_cb128("selectSite" in _CTL128 and "SiteActivityConfig" in _CTL128, "CODEBOT v128: MapController has JOB 31 site overlays")

_copy_hits = []
for _p in list(_P128("src").rglob("*.luau")):
    _t = _rd128(str(_p))
    for _line in _t.splitlines():
        _code_part = _line.split("--", 1)[0]
        if _re128.search(r'"[^"]*(fast[ -]?travel|teleport to (your )?(base|outpost))[^"]*"', _code_part, _re128.I):
            _copy_hits.append(str(_p))
_cb128(not _copy_hits, "CODEBOT v128: no hint / tutorial / UI string mentions fast travel " + ", ".join(sorted(set(_copy_hits))[:4]))

_cb128('RequestFastTravel' not in _code128("src/ReplicatedStorage/Shared/Constants.luau")
       and 'RequestFastTravel' not in _code128(_S128 + "Modules/RemoteSetup.luau")
       and 'RequestFastTravel' not in _code128("src/ReplicatedStorage/Shared/Configs/SecurityConfig.luau"),
       "CODEBOT v128: RequestFastTravel is not created, named or schema'd")
_cb128('RequestSiteActivity' in _code128("src/ReplicatedStorage/Shared/Constants.luau")
       and 'RequestSiteActivity' in _code128(_S128 + "Modules/RemoteSetup.luau")
       and 'RequestSiteActivity' in _code128("src/ReplicatedStorage/Shared/Configs/SecurityConfig.luau"),
       "CODEBOT v128: RequestSiteActivity is named, created and schema'd")

# PreferMesh OFF + JOB 31 OwnerFirst retained
_cb128("PreferMeshWhenAssetIdSet = false" in _rd128("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau"),
       "CODEBOT v128: PreferMesh stays OFF")
_AC128 = _rd128("src/ReplicatedStorage/Shared/Configs/SiteActivityConfig.luau")
_cb128("\tEnabled = true,\n\tOwnerFirst = true, -- only UserId 470626172" in _AC128,
       "CODEBOT v128: SiteActivityConfig OwnerFirst retained (JOB 31)")
_cb128("\tOwnerFirst = true, -- only UserId 470626172" in _MC128,
       "CODEBOT v128: MapConfig OwnerFirst retained")
_cb128("safeInit(\"SiteActivityService\"" in _rd128(_S128 + "Bootstrap.server.luau")
       and "SiteActivityService" in _rd128(_S128 + "Bootstrap.server.luau"),
       "CODEBOT v128: Bootstrap requires + inits SiteActivityService")
_cb128(_P128("src/ReplicatedStorage/Shared/Configs/WorldDetailConfig.luau").is_file()
       and _P128("src/ReplicatedStorage/Shared/Configs/WorldSitesConfig.luau").is_file()
       and _P128(_S128 + "Modules/WorldSites.luau").is_file()
       and _P128(_S128 + "Services/SiteActivityService.luau").is_file(),
       "CODEBOT v128: JOB 31 WorldDetail / WorldSites / SiteActivity files present")
