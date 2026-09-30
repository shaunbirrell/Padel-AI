# Code Bot Roblox v131 (2026-09-30): ship claude-bud JOB 33 rebirth overhaul + JOB 34 achievements.
# FF-merge origin/claude/desktop-bud (f763276 + 50d19b8). Launch: RebirthConfig.Live.OwnerFirst=false,
# ZonesLive/WeaponsLive=true; AchievementConfig.Live.OwnerFirst=false. BadgeIds stay 0 (docs/BADGES.md —
# creating Creator Hub badges costs Robux; owner call). Fast travel stays REMOVED. PreferMesh stays OFF.
# WE_Building* untouched. MAP-REDESIGN kept.
import os as _os131
from pathlib import Path as _P131


def _cb131(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


def _rd131(p):
    q = _P131(p)
    return q.read_text(encoding="utf-8") if q.is_file() else ""


def _code131(p):
    return "\n".join(l.split("--", 1)[0] for l in _rd131(p).splitlines())


_S131 = "src/ServerScriptService/Server/"
for _f in (_S131 + "Services/DataService.luau", _S131 + "Services/BaseService.luau", _S131 + "EarlyRemotes.server.luau"):
    _cb131('SetAttribute("WE_Build", 131)' in _rd131(_f), "CODEBOT v131: WE_Build=131 " + _f.rsplit("/", 1)[-1])
_cb131("WE_Build=131" in _rd131(_S131 + "Services/DataService.luau"), "CODEBOT v131: DataService profile-loaded log says WE_Build=131")

_RC131 = _rd131("src/ReplicatedStorage/Shared/Configs/RebirthConfig.luau")
_cb131("\tZonesLive = true," in _RC131 and "\tWeaponsLive = true," in _RC131,
       "CODEBOT v131: Rebirth ZonesLive/WeaponsLive published for everyone")
_cb131("OwnerFirst = false, -- codebot_v131 launch: everyone (JOB 33 handoff)" in _RC131,
       "CODEBOT v131: RebirthConfig.Live.OwnerFirst=false (launched)")

_AC131 = _rd131("src/ReplicatedStorage/Shared/Configs/AchievementConfig.luau")
_cb131("OwnerFirst = false, -- codebot_v131 launch: everyone (JOB 34 handoff)" in _AC131,
       "CODEBOT v131: AchievementConfig.Live.OwnerFirst=false (launched)")

_cb131(_P131("src/ServerScriptService/Server/Services/RebirthZoneService.luau").is_file(),
       "CODEBOT v131: RebirthZoneService exists (JOB 33)")
_cb131(_P131("src/ServerScriptService/Server/Services/NukeService.luau").is_file(),
       "CODEBOT v131: NukeService exists (JOB 33)")
_cb131(_P131("src/ServerScriptService/Server/Services/AchievementService.luau").is_file(),
       "CODEBOT v131: AchievementService exists (JOB 34)")
_cb131(_P131("docs/BADGES.md").is_file(), "CODEBOT v131: docs/BADGES.md present (BadgeIds may stay 0)")

# Fast travel still OFF + PreferMesh OFF + MAP-REDESIGN kept
_CTL131 = _code131("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/MapController.luau")
_MC131 = _rd131("src/ReplicatedStorage/Shared/Configs/MapConfig.luau")
_cb131("\tFastTravelEnabled = false,\n" in _MC131 and "RequestFastTravel" not in _CTL131 and '"TRAVEL"' not in _CTL131,
       "CODEBOT v131: still no fast travel")
_cb131("PreferMeshWhenAssetIdSet = false" in _rd131("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau"),
       "CODEBOT v131: PreferMesh stays OFF")
_LL131 = _code131("src/ReplicatedStorage/Shared/Util/MapLabelLayout.luau")
_cb131(_P131("src/ReplicatedStorage/Shared/Util/MapLabelLayout.luau").is_file()
       and "function MapLabelLayout.TitleCase(" in _LL131,
       "CODEBOT v131: MAP-REDESIGN MapLabelLayout still present")
