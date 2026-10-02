# Code Bot Roblox v127 (2026-09-30): ship claude-bud JOB 30 (world map + named areas + tap-to-pin on the ONE
# ObjectiveMarker) WITHOUT fast travel. Owner (Shaun): "no fast travel, only tap-to-pin so players can see where they
# want to go". Fast travel is removed end to end: no MapConfig block (FastTravelEnabled = false), no RequestFastTravel
# remote / handler / rate entry, no TRAVEL button, no hint or tutorial copy. Claude must NOT re-add it.
import re as _re127
from pathlib import Path as _P127


def _cb127(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


def _rd127(p):
    q = _P127(p)
    return q.read_text(encoding="utf-8") if q.is_file() else ""


def _code127(p):
    return "\n".join(l.split("--", 1)[0] for l in _rd127(p).splitlines())


_S127 = "src/ServerScriptService/Server/"
for _f in (_S127 + "Services/DataService.luau", _S127 + "Services/BaseService.luau", _S127 + "EarlyRemotes.server.luau"):
    pass  # v128 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v128.py: #_cb127('SetAttribute("WE_Build", 127)' in _rd127(_f), "CODEBOT v127: WE_Build=127 " + _f.rsplit("/", 1)[-1])
# v128 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v128.py: #_cb127("WE_Build=127" in _rd127(_S127 + "Services/DataService.luau"), "CODEBOT v127: DataService profile-loaded log says WE_Build=127")

# ── fast travel is OFF (owner request) ──────────────────────────────────────────────────────────────────────────
_MC127 = _rd127("src/ReplicatedStorage/Shared/Configs/MapConfig.luau")
_cb127("\tFastTravelEnabled = false,\n" in _MC127 and "FastTravel = {" not in _MC127 and "CooldownSeconds" not in _MC127,
       "CODEBOT v127: MapConfig.FastTravelEnabled = false and no FastTravel block / cooldown")
_cb127("FastTravelEnabled = true" not in _MC127, "CODEBOT v127: fast travel never switched on")

# no fast-travel remote anywhere in code (name, handler, gate, rate entry)
_FT_CODE = _re127.compile(r"FastTravel|RequestFastTravel|fast_travel|FAST_TRAVEL|TravelIn|lastTravelAt")
_hits = []
for _p in _P127("src").rglob("*.luau"):
    _c = _code127(str(_p))
    for _m in _FT_CODE.finditer(_c):
        if _m.group(0) == "FastTravel" and "FastTravelEnabled" in _c[_m.start():_m.start() + 20]:
            continue
        _hits.append(str(_p) + ":" + _m.group(0))
_cb127(not _hits, "CODEBOT v127: no fast-travel remote / handler / state in src " + (", ".join(sorted(set(_hits))[:6]) if _hits else ""))

_SVC127 = _code127(_S127 + "Services/MapService.luau")
_cb127("OnServerInvoke" in _SVC127 and _SVC127.count("OnServerInvoke") == 1 and "RequestMapLive" in _SVC127,
       "CODEBOT v127: MapService has exactly one handler (RequestMapLive, read-only)")
_cb127("StreamPrefetch" not in _SVC127 and "TeleportToPlot" not in _SVC127 and "PivotTo" not in _SVC127 and ":Place(" not in _SVC127,
       "CODEBOT v127: MapService never moves a player (no teleport path)")

_CTL127 = _code127("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/MapController.luau")
_cb127('"TRAVEL"' not in _CTL127 and "travelB" not in _CTL127 and "travelBtn" not in _CTL127 and "InvokeServer(target)" not in _CTL127,
       "CODEBOT v127: the map UI has no TRAVEL button")
_cb127('button(row, "Go", "GO"' in _CTL127 and 'button(row, "ClearPin", "CLEAR PIN"' in _CTL127,
       "CODEBOT v127: GO + CLEAR PIN stay (tap-to-pin kept)")
_cb127("Pin = true," in _CTL127 and "ObjectiveMarker.ShowWith(" in _CTL127 and 'Instance.new("Beam")' not in _CTL127,
       "CODEBOT v127: tap-to-pin uses the ONE yellow tracker (ObjectiveMarker), no second Beam")

# no player-facing copy mentions fast travel (hints, tips, tutorial, map text)
_copy_hits = []
for _p in list(_P127("src").rglob("*.luau")):
    _t = _rd127(str(_p))
    for _line in _t.splitlines():
        _code_part = _line.split("--", 1)[0]
        if _re127.search(r'"[^"]*(fast[ -]?travel|teleport to (your )?(base|outpost))[^"]*"', _code_part, _re127.I):
            _copy_hits.append(str(_p))
_cb127(not _copy_hits, "CODEBOT v127: no hint / tutorial / UI string mentions fast travel " + ", ".join(sorted(set(_copy_hits))[:4]))

_cb127('RequestFastTravel' not in _code127("src/ReplicatedStorage/Shared/Constants.luau")
       and 'RequestFastTravel' not in _code127(_S127 + "Modules/RemoteSetup.luau")
       and 'RequestFastTravel' not in _code127("src/ReplicatedStorage/Shared/Configs/SecurityConfig.luau"),
       "CODEBOT v127: RequestFastTravel is not created, named or schema'd")
