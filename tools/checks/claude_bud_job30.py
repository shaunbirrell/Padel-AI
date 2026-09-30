# claude-bud JOB 30 (2026-09-30): the world map (MapConfig / MapController / MapService / MapAreas), tap-to-pin on the
# ONE objective marker, Missions moved to N. (Code Bot v127: fast travel REMOVED at owner request; see codebot_v127.py.) Static pins + the MapAreas test (the real module, Luau CLI).
import os as _j30_os
import subprocess as _j30_sp
import sys as _j30_sys
from pathlib import Path as _J30P

if "ok" not in globals():
    _j30_fails = []

    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        _j30_fails.append(msg)
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _J30P(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None


def _j30(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J30: " + msg)


def _j30_src(path):
    return (read(path) or "").replace("\r\n", "\n")


def _j30_code(path):
    return "\n".join(l.split("--", 1)[0] for l in _j30_src(path).splitlines())


_MC = _j30_src("src/ReplicatedStorage/Shared/Configs/MapConfig.luau")
_CTL = _j30_code("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/MapController.luau")
_SVC = _j30_code("src/ServerScriptService/Server/Services/MapService.luau")
_AR = _j30_code("src/ReplicatedStorage/Shared/Util/MapAreas.luau")
_OM = _j30_code("src/StarterPlayer/StarterPlayerScripts/Client/Modules/ObjectiveMarker.luau")
_HC = _j30_src("src/ReplicatedStorage/Shared/Configs/HudConfig.luau")
_UI = _j30_code("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/UIController.luau")
_BSS = _j30_code("src/ServerScriptService/Server/Services/BaseSignService.luau")

_OWN = "OwnerFirst = true, -- only UserId 470626172"
_j30("local MapConfig = {\n\tEnabled = true,\n\t" + _OWN in _MC and "\tFastTravelEnabled = false,\n" in _MC,
     "kill switch MapConfig.Enabled, owner-first; Code Bot v127: FastTravelEnabled = false (fast travel removed)")
_j30("RefreshSeconds = 0.5," in _MC and "PinArriveStuds = 15," in _MC, "markers at most 2x a second; pin arrives at 15 studs")
# keys: M = map, Missions -> N (hints come from the same config)
_j30("Missions = Enum.KeyCode.N," in _HC and "Map = Enum.KeyCode.M," in _HC and 'Id = "Map", Name = "DockMap", Label = "Map", Icon = "Map"' in _HC
     and 'Label = "Missions", Icon = "Clipboard", Accent = Color3.fromRGB(255, 150, 32), Fill = Color3.fromRGB(80, 42, 6), Key = Enum.KeyCode.N' in _HC,
     "MAP rail tile + M; Missions moved to N (tile hint and key)")
_j30('Id = "Map",' in _UI and 'dockPress("Map", MapController.Toggle, "Map")' in _UI and '{ Id = "Map", Controller = MapController }' in _UI,
     "the MAP tile opens the registered Modal panel (only while the map is live for the player)")
# the ONE tracker: pin = ObjectiveMarker.ShowWith { Pin = true }, no second Beam
_j30("Pin = true," in _CTL and "ArriveStuds = MapConfig.PinArriveStuds," in _CTL and "ObjectiveMarker.ShowWith(" in _CTL
     and 'Instance.new("Beam")' not in _CTL and "ObjectiveMarker.ClearPin()" in _CTL, "tap-to-pin reuses ObjectiveMarker (no second Beam / tracker); tap pin or CLEAR PIN removes it")
_j30("if pinned and not isPin then" in _OM and "function ObjectiveMarker.ClearPin()" in _OM and "c == nil or pinned or" in _OM
     and "endConsoleLine()" in _OM, "a manual pin beats mission / job targets; ShowWith still ends ConsoleWaypoint's line")
_j30("function ObjectiveMarker.Show(target: Target)" in _OM and "function ObjectiveMarker.Clear()" in _OM, "the frozen ObjectiveMarker API is unchanged")
# performance: nothing while closed, one loop while open, no scans
_j30("while open and loopToken == my do" in _CTL and "GetDescendants" not in _CTL and "RenderStepped" not in _CTL and "Heartbeat" not in _CTL,
     "one refresh loop only while open; no per-frame work, no tree scans")
_j30("if staticBuilt then" in _CTL, "the area layer is built once and cached")
# layout: the canvas (tap surface) on the right, never in the left 40 %
_j30("cv.AnchorPoint = Vector2.new(1, 0.5)" in _CTL and "cv.Size = UDim2.new(0.58, 0, 1, -12)" in _CTL, "the tap canvas sits on the right (thumbstick zone kept clear)")
# server feed + names
_j30('RemoteGate).Check(player, "RequestMapLive")' in _SVC, "map remote is gated (Code Bot v127: no fast-travel remote)")
_j30("sign.TitleFor(plotId)" in _SVC and "function BaseSignService.TitleFor(plotId: number): string?" in _BSS and "title = titleOf(owner)" in _BSS,
     "base names use the sign's own \"<Name>'s Empire\" string")
_j30("pairs(TerritoryConfig.Territories)" in _SVC and "ipairs(TerritoryConfig.Territories" not in _SVC + _AR + _CTL,
     "TerritoryConfig.Territories is walked as the Id-keyed table it is")
# Code Bot v127: the fast-travel rules pin is retired with fast travel itself (codebot_v127.py pins it OFF)
_j30("WorldConfig.POIs" in _AR and "OutpostDefenderConfig.Areas" in _AR, "areas are the real zones (POIs + outposts + garrisons)")

_luau = _j30_os.environ.get("LUAU")
if _luau is None and _j30_os.environ.get("LUAU_COMPILE"):
    _cand = _j30_os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    _luau = _cand if _j30_os.path.isfile(_cand) else None
if _luau:
    _r = _j30_sp.run([_j30_sys.executable, "tools/sim/run_map_test.py"], capture_output=True, text=True, env=dict(_j30_os.environ, LUAU=_luau))
    _j30(_r.returncode == 0 and ", 0 failed" in _r.stdout, "MapAreas test (every POI and outpost placed; tap lookup)")
else:
    print("SKIP CLAUDE-BUD J30: MapAreas test (no luau CLI: set LUAU)")
