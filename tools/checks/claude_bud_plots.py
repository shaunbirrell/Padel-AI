# claude-bud JOB 21 (2026-09-29): more base plots (10). No hard-coded 6s; every count from BaseConfig.MaxPlots; plots
# never overlap each other, the Town, POIs, captures or water; every plot has a gate pad, a road and a dock channel that
# reaches water crossing no road or POI; saved plot ids still validate; the full-server safety net.
import math as _p_math

_p_bc = read("src/ReplicatedStorage/Shared/Configs/BaseConfig.luau") or ""
_p_wc = read("src/ReplicatedStorage/Shared/Configs/WaterConfig.luau") or ""
_p_wo = read("src/ReplicatedStorage/Shared/Configs/WorldConfig.luau") or ""
_p_tc = read("src/ReplicatedStorage/Shared/Configs/TerritoryConfig.luau") or ""
_p_fc = read("src/ReplicatedStorage/Shared/Configs/WorldFillConfig.luau") or ""

_p_max = int(re.search(r"^\tMaxPlots = (\d+),", _p_bc, re.M).group(1))
_i = _p_bc.index("PlotPositions = {")
_p_pos = [(float(x), float(z)) for x, z in re.findall(r"Vector3\.new\((-?\d+), 0\.5, (-?\d+)\)", _p_bc[_i:_p_bc.index("} :: { Vector3 },", _i)])]
(ok if _p_max >= 10 and len(_p_pos) == _p_max else bad)(f"CLAUDE-BUD J21: MaxPlots {_p_max} (>= 10) = #PlotPositions {len(_p_pos)}")

# ── no hard-coded 6s: every count follows MaxPlots ──
_gc = read("src/ReplicatedStorage/Shared/Configs/GameConfig.luau") or ""
for _k in ("MaxPlayersPerServer", "BasePlotCount"):
    _m = re.search(r"\b" + _k + r" = (\d+)", _gc)
    (ok if _m and int(_m.group(1)) == _p_max else bad)(f"CLAUDE-BUD J21: GameConfig.{_k} = MaxPlots ({_m.group(1) if _m else '?'})")
_cm = re.search(r"Constants\.MaxBasePlots = (\d+)", read("src/ReplicatedStorage/Shared/Constants.luau") or "")
(ok if _cm and int(_cm.group(1)) == _p_max else bad)(f"CLAUDE-BUD J21: Constants.MaxBasePlots = MaxPlots ({_cm.group(1) if _cm else '?'})")
_ms = read("src/ServerScriptService/Server/Modules/MapSetup.luau") or ""
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", "local PLOT_POSITIONS: { Vector3 } = table.clone(BaseConfig.PlotPositions :: { Vector3 })", "CLAUDE-BUD J21: MapSetup builds from BaseConfig.PlotPositions (no second list)")
(ok if "Vector3.new(-PLOT_RING, 0.5, -PLOT_RING * 0.5)" not in _ms else bad)("CLAUDE-BUD J21: the old 6-entry MapSetup plot list is gone")
must_contain("src/ServerScriptService/Server/Modules/MapSetup.luau", 'table.insert(rows, string.format("P%d:%g,%g", i, p.X, p.Z))', "CLAUDE-BUD J21: the map layout stamp includes the plots (a 6-plot saved map is rebuilt)")
_six = []
for _f in ("src/ServerScriptService/Server/Services/BaseService.luau", "src/ReplicatedStorage/Shared/Util/PlotFrame.luau",
           "src/StarterPlayer/StarterPlayerScripts/Client/Modules/ProducerLabels.luau", "src/StarterPlayer/StarterPlayerScripts/Client/Modules/NextPadChevrons.luau",
           "src/ServerScriptService/Server/Services/GateDefenseService.luau", "src/ServerScriptService/Server/Services/SquadOrdersService.luau",
           "src/ServerScriptService/Server/Modules/ArmyFollow.luau", "src/ServerScriptService/Server/Modules/BaseGuards.luau",
           "src/ServerScriptService/Server/Modules/NightLights.luau", "src/ServerScriptService/Server/Services/TerritoryService/init.luau",
           "src/ReplicatedStorage/Shared/Configs/TerritoryConfig.luau", "src/ServerScriptService/Server/Modules/Waterways.luau"):
    _t = read(_f) or ""
    for _m in re.finditer(r"for \w+ = 1, 6 do|MaxPlots = 6|#\w*[Pp]lot\w* == 6|[Pp]lots? ?= ?6\b", _t):
        _six.append(f"{_f.split('/')[-1]}: {_m.group(0)}")
(ok if not _six else bad)(f"CLAUDE-BUD J21: no hard-coded 6-plot loops / counts {_six}")
must_contain("src/ReplicatedStorage/Shared/Configs/TerritoryConfig.luau", "for n = 1, BaseConfig.MaxPlots do", "CLAUDE-BUD J21: Starter_P rows follow MaxPlots")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "return n ~= nil and n == math.floor(n) and n >= 1 and n <= BaseConfig.MaxPlots", "CLAUDE-BUD J21: saved plot ids validate against MaxPlots (old ids 1..6 still load)")

# ── plot geometry (PlotFrame.PlotYaw: the dominant axis faces the map centre; front = plot-local +Z) ──
_half = 160.0


def _yaw(x, z):
    if abs(x) >= abs(z):
        return 90 if x < 0 else -90
    return 0 if z < 0 else 180


def _to_world(cx, cz, yaw, lx, lz):
    a = _p_math.radians(yaw)
    return cx + lx * _p_math.cos(a) + lz * _p_math.sin(a), cz - lx * _p_math.sin(a) + lz * _p_math.cos(a)


def _rect_gap(a, b):  # (x0, x1, z0, z1) boxes: separation (negative = overlap)
    return max(a[0] - b[1], b[0] - a[1], a[2] - b[3], b[2] - a[3])


_pads = [(x - _half, x + _half, z - _half, z + _half) for x, z in _p_pos]
_over = [(i + 1, j + 1, round(_rect_gap(_pads[i], _pads[j]))) for i in range(len(_pads)) for j in range(i + 1, len(_pads)) if _rect_gap(_pads[i], _pads[j]) < 60]
(ok if not _over else bad)(f"CLAUDE-BUD J21: plots never overlap (>= 60 studs between pads) {_over}")
_poi_rects = [tuple(float(v) for v in m) for m in re.findall(r"Rect = \{ X0 = (-?\d+), X1 = (-?\d+), Z0 = (-?\d+), Z1 = (-?\d+) \}", _p_wo)]
_poi_circ = [tuple(float(v) for v in m) for m in re.findall(r"Circle = \{ X = (-?\d+), Z = (-?\d+), R = (\d+) \}", _p_wo)]
_caps = [(float(x), float(z), float(r)) for x, z, r in re.findall(r"Position = Vector3\.new\((-?\d+), \d+, (-?\d+)\)[^\n]*\n\t*Radius = (\d+)", _p_tc)]
_water = [tuple(float(v) for v in m) for m in re.findall(r"X0 = (-?\d+), X1 = (-?\d+), Z0 = (-?\d+), Z1 = (-?\d+)", _p_wc[_p_wc.find("PublicRects") if "PublicRects" in _p_wc else 0:_p_wc.find("Channels = {")])]
(ok if len(_poi_rects) >= 8 and len(_poi_circ) >= 8 and len(_caps) >= 7 and len(_water) >= 10 else bad)(f"CLAUDE-BUD J21: read {len(_poi_rects)} POI rects, {len(_poi_circ)} POI circles, {len(_caps)} captures, {len(_water)} water rects")


def _circ_rect_dist(cx, cz, r):
    x0, x1, z0, z1 = r
    dx = max(x0 - cx, 0, cx - x1)
    dz = max(z0 - cz, 0, cz - z1)
    return _p_math.hypot(dx, dz)


for _n, (_x, _z) in enumerate(_p_pos, start=1):
    _pad = _pads[_n - 1]
    _hits = [("poi", r) for r in _poi_rects if _rect_gap(_pad, r) < 0]
    _hits += [("poi", c) for c in _poi_circ if _circ_rect_dist(c[0], c[1], _pad) < c[2]]
    _hits += [("capture", c) for c in _caps if _circ_rect_dist(c[0], c[1], _pad) < c[2]]
    _hits += [("water", w) for w in _water if _rect_gap(_pad, w) < 0]
    (ok if not _hits else bad)(f"CLAUDE-BUD J21: plot {_n} ({_x:.0f},{_z:.0f}) clear of the Town, POIs, captures and water {_hits}")

# ── every plot: a gate pad row, a road at its gate, a dock channel to water crossing no road / POI ──
_gates = {int(p): (float(x), float(z)) for p, x, z in re.findall(r'\{ Id = "Gate_P\d+", PlotId = (\d+), LocalX = (-?\d+), LocalZ = (\d+)', _p_wo)}
_chan = {int(p): float(u) for p, u in re.findall(r"\{ PlotId = (\d+), Until = (-?\d+) \}", _p_wc)}
_fill_roads = [tuple(float(v) for v in m) for m in re.findall(r'\{ Name = "Fill_Road\w+", X0 = (-?\d+), Z0 = (-?\d+), X1 = (-?\d+), Z1 = (-?\d+) \}', _p_fc)]
_world_roads = [("X", -800.0), ("X", 0.0), ("X", 800.0), ("Z", -800.0), ("Z", 0.0), ("Z", 800.0)]


def _seg_dist(px, pz, x0, z0, x1, z1):
    vx, vz = x1 - x0, z1 - z0
    L2 = vx * vx + vz * vz
    t = 0 if L2 == 0 else max(0, min(1, ((px - x0) * vx + (pz - z0) * vz) / L2))
    return _p_math.hypot(px - (x0 + t * vx), pz - (z0 + t * vz))


for _n, (_x, _z) in enumerate(_p_pos, start=1):
    _y = _yaw(_x, _z)
    (ok if _n in _gates else bad)(f"CLAUDE-BUD J21: plot {_n} has a gate pad row (WorldConfig.Spawns.Garage Gate_P{_n})")
    _gx, _gz = _to_world(_x, _z, _y, 0, 160)  # the main gate (front edge centre)
    _near = min([abs(_gx - v) if a == "X" else abs(_gz - v) for a, v in _world_roads]
                + [_seg_dist(_gx, _gz, *r) for r in _fill_roads])
    _on = any((a == "X" and abs(_x - v) <= _half) or (a == "Z" and abs(_z - v) <= _half) for a, v in _world_roads)
    (ok if _near <= 80 or _on else bad)(f"CLAUDE-BUD J21: plot {_n} gate ({_gx:.0f},{_gz:.0f}) has a road (nearest {_near:.0f} studs; on a world road: {_on})")
    if _n not in _chan:
        bad(f"CLAUDE-BUD J21: plot {_n} has a dock channel (WaterConfig.Channels)")
        continue
    # the channel: sea-gate opening plot-local x 108..148 from the rear edge (z -160) straight out to Until
    ax, az = _to_world(_x, _z, _y, 108, -160)
    bx, bz = _to_world(_x, _z, _y, 148, -160)
    if _y in (0, 180):
        ch = (min(ax, bx), max(ax, bx), min(az, _chan[_n]), max(az, _chan[_n]))
    else:
        ch = (min(ax, _chan[_n]), max(ax, _chan[_n]), min(az, bz), max(az, bz))
    _reach = any(_rect_gap(ch, w) <= 1 for w in _water)
    _road = [(a, v) for a, v in _world_roads if (a == "X" and ch[0] - 12 < v < ch[1] + 12) or (a == "Z" and ch[2] - 12 < v < ch[3] + 12)]
    # the road that runs through its own plot (under the pad) does not count: only crossings outside the pad
    _road = [(a, v) for a, v in _road if not ((a == "X" and _pads[_n - 1][0] <= v <= _pads[_n - 1][1] and ch[2] >= _pads[_n - 1][2] - 1 and ch[3] <= _pads[_n - 1][3] + 1)
                                            or (a == "Z" and _pads[_n - 1][2] <= v <= _pads[_n - 1][3] and ch[0] >= _pads[_n - 1][0] - 1 and ch[1] <= _pads[_n - 1][1] + 1))]
    # a POI that holds public water itself (the Port round the South Docks harbour) is a harbour: a channel may enter it
    _poi = [r for r in _poi_rects if _rect_gap(ch, r) < 0 and not any(_rect_gap(r, w) < 0 for w in _water)] + [c for c in _poi_circ if _circ_rect_dist(c[0], c[1], ch) < c[2]]
    (ok if _reach and not _road and not _poi else bad)(f"CLAUDE-BUD J21: plot {_n} dock channel {tuple(round(v) for v in ch)} reaches water {_reach}, crosses no road {_road} / POI {_poi}")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'if structureId == "Dock" and not BaseService._PlotHasChannel(ownPlot) then', "CLAUDE-BUD J21: a plot without a channel never sells a Dock (none today)")

# ── the full-server safety net ──
must_contain("src/ReplicatedStorage/Shared/Configs/BaseConfig.luau", "\tFullServerTeleport = true,", "CLAUDE-BUD J21: full-server teleport on")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'pcall(NotificationService.Notify, player, "Server full - moving you to another server", "Warn", 6)', "CLAUDE-BUD J21: the player is told")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "TeleportService:TeleportAsync(game.PlaceId, { player })", "CLAUDE-BUD J21: moved to another public server (never left baseless)")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", "BaseService._MoveToAnotherServer(player)", "CLAUDE-BUD J21: the safety net runs when no plot frees up")
_lp = read("docs/LIVE_PLACE.md") or ""
(ok if f"- **Max Players = {_p_max}**" in _lp else bad)(f"CLAUDE-BUD J21: docs/LIVE_PLACE.md Max Players = {_p_max}")
