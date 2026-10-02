# Code Bot Roblox v129 (2026-09-30) MAP-REDESIGN: the owner's phone screenshot showed ALL CAPS labels colliding, a flat
# brown square with beige circles and the map in the right half only. The world map is redesigned: the square map
# left of centre + a slim info card, sand terrain with roads / grid / compass / frame + corner brackets / vignette,
# one icon family set (UICorner + UIStroke), title-case pills placed by a real collision pass (Shared/Util/
# MapLabelLayout), 2 zoom levels (button, pinch, wheel; drag pans at zoom 2). Kept: tap-to-pin on the ONE yellow
# tracker, GO, CLEAR PIN, the legend (as icons), your arrow. Fast travel stays REMOVED. PreferMesh OFF.
import os as _os129
import subprocess as _sp129
import sys as _sys129
from pathlib import Path as _P129


def _cb129(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


def _rd129(p):
    q = _P129(p)
    return q.read_text(encoding="utf-8") if q.is_file() else ""


def _code129(p):
    return "\n".join(l.split("--", 1)[0] for l in _rd129(p).splitlines())


_S129 = "src/ServerScriptService/Server/"
for _f in (_S129 + "Services/DataService.luau", _S129 + "Services/BaseService.luau", _S129 + "EarlyRemotes.server.luau"):
    pass  # v130 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v130.py: #_cb129('SetAttribute("WE_Build", 129)' in _rd129(_f), "CODEBOT v129: WE_Build=129 " + _f.rsplit("/", 1)[-1])
# v130 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v130.py: #_cb129("WE_Build=129" in _rd129(_S129 + "Services/DataService.luau"), "CODEBOT v129: DataService profile-loaded log says WE_Build=129")

_CTL129 = _code129("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/MapController.luau")
_MC129 = _rd129("src/ReplicatedStorage/Shared/Configs/MapConfig.luau")
_LL129 = _code129("src/ReplicatedStorage/Shared/Util/MapLabelLayout.luau")

# layout: the square map + the slim card (fitLayout), never the v127 right-half canvas
_cb129("local function fitLayout()" in _CTL129 and "cv.Size = UDim2.fromOffset(sv, sv)" in _CTL129
       and "card.Position = UDim2.fromOffset(x0 + sv + GAP, y0)" in _CTL129 and "UDim2.new(0.58, 0, 1, -12)" not in _CTL129,
       "CODEBOT v129: the map is a square left of centre with the slim card beside it")
# terrain: sand gradient, roads, grid, compass, frame + corner brackets, vignette
_cb129("gradient(land, C.SandLight, C.SandDark, 90)" in _CTL129 and "WaterConfig.RoadEnds" in _CTL129 and '"GridX"' in _CTL129
       and '"Compass"' in _CTL129 and '"Bracket"' in _CTL129 and '"Vignette"' in _CTL129,
       "CODEBOT v129: styled terrain (sand gradient, roads, grid, compass, brackets, vignette)")
# icons: UICorner + UIStroke, colour by family, fixed sizes from MapConfig.Icon
_cb129("local function makeIcon(" in _CTL129 and "stroke(f, STROKE, 1.5, 0.1)" in _CTL129 and "Icon = { Area = 22, Site = 20," in _MC129
       and "KindGroup = {" in _MC129, "CODEBOT v129: one icon family set (UICorner + UIStroke, fixed sizes, colour by kind)")
_cb129('mark("Out"' not in _CTL129 and "badges[o.Id]" in _CTL129, "CODEBOT v129: outposts are owner badges on their area icon (no loose diamonds)")
# labels: title case, pills, the collision pass, priorities, zoom
_cb129("string.upper(" not in _CTL129 and "function MapLabelLayout.TitleCase(" in _LL129, "CODEBOT v129: no ALL CAPS map labels (title case)")
_cb129("MapLabelLayout.Build({" in _CTL129 and "local function pill(" in _CTL129 and "C.Pill, 0.32" in _CTL129
       and "t.TextStrokeTransparency = 0.35" in _CTL129, "CODEBOT v129: labels are dark pills with a text stroke, placed by MapLabelLayout")
_cb129("MapLabelLayout.Slots = { { 1, 0 }, { -1, 0 }, { 0, -1 }, { 0, 1 }," in _LL129 and "local function clamp(" in _LL129
       and "it.Priority <= input.MaxPriority" in _LL129 and "table.insert(hidden, it.Id)" in _LL129,
       "CODEBOT v129: 8 candidate slots, clamped in bounds, lower priority skipped when colliding")
_cb129("town = 1," in _MC129 and "depot = 3, site_depot = 3," in _MC129 and "ZoomLevels = { 1, 2 }," in _MC129 and "ZoomMaxPriority = { 2, 3 }," in _MC129,
       "CODEBOT v129: towns / sites > outposts > depots; zoom 2 shows more")
_cb129("MapLabelLayout.PlaceFocus(" in _CTL129 and "selectItem(best.Id)" in _CTL129, "CODEBOT v129: a tapped place shows its (hidden) label")
_cb129("cv.TouchPinch:Connect(" in _CTL129 and "cv.MouseWheelForward:Connect(" in _CTL129 and "zb.Size = UDim2.fromOffset(TAP, TAP)" in _CTL129,
       "CODEBOT v129: zoom by pinch, wheel or the 44 px + / - button")
# kept: tap-to-pin on the ONE tracker, GO / CLEAR PIN, the legend, the arrow; no fast travel
_cb129('button(row, "Go", "GO"' in _CTL129 and 'button(row, "ClearPin", "CLEAR PIN"' in _CTL129 and "ObjectiveMarker.ShowWith(" in _CTL129
       and "Pin = true," in _CTL129 and 'Instance.new("Beam")' not in _CTL129, "CODEBOT v129: tap-to-pin + GO + CLEAR PIN kept on the ONE tracker")
_cb129('"Legend"' in _CTL129 and 'mark("Me"' in _CTL129, "CODEBOT v129: legend (icons) + your arrow kept")
_cb129("\tFastTravelEnabled = false,\n" in _MC129 and "FastTravel" not in _CTL129.replace("FastTravelEnabled", "") and '"TRAVEL"' not in _CTL129,
       "CODEBOT v129: still no fast travel")
_cb129("GetDescendants" not in _CTL129 and "RenderStepped" not in _CTL129 and "Heartbeat" not in _CTL129,
       "CODEBOT v129: the map does no per-frame work or tree scans")
_cb129("PreferMeshWhenAssetIdSet = false" in _rd129("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau"), "CODEBOT v129: PreferMesh stays OFF")

# the offline render test: the REAL MapLabelLayout on the REAL POIs / sites / bases (no overlaps, all in bounds)
_luau129 = _os129.environ.get("LUAU")
if _luau129 is None and _os129.environ.get("LUAU_COMPILE"):
    _c129 = _os129.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    _luau129 = _c129 if _os129.path.isfile(_c129) else None
if _luau129:
    _r129 = _sp129.run([_sys129.executable, "tools/sim/run_map_layout_test.py"], capture_output=True, text=True,
                       env=dict(_os129.environ, LUAU=_luau129))
    _cb129(_r129.returncode == 0 and ", 0 failed" in _r129.stdout,
           "CODEBOT v129: map label layout test (no pill overlaps, none over an icon / control, all inside the map) "
           + (_r129.stdout.strip().splitlines()[-1] if _r129.stdout.strip() else _r129.stderr[-300:]))
else:
    print("SKIP CODEBOT v129: map label layout test (no luau CLI: set LUAU)")
