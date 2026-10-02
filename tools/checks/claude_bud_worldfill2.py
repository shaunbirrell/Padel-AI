# claude-bud JOB 18 (2026-09-29): WorldFill 2 (WorldFillConfig.Fill2 + WorldFill.Build2 + the new WorldKits kits).
# No overlap with plots / runways / the plaza and capture zones / spawn, part budget, everything anchored, no scripts,
# small props shadowless, every placement re-checked against the shared occupancy, the empty-cell grid covers the map.
import math as _f2_math

_f2_cfg = "src/ReplicatedStorage/Shared/Configs/WorldFillConfig.luau"
_f2_wf = "src/ServerScriptService/Server/Modules/WorldFill.luau"
_f2_wk = "src/ServerScriptService/Server/Modules/WorldKits.luau"
_f2_c = read(_f2_cfg) or ""
_f2_k = read(_f2_wk) or ""
_f2_bc = read("src/ReplicatedStorage/Shared/Configs/BaseConfig.luau") or ""
_f2_tc = read("src/ReplicatedStorage/Shared/Configs/TerritoryConfig.luau") or ""

# kit part counts from WorldKits.Specs (the builders' exact counts)
_f2_parts = {m.group(1): int(m.group(2)) for m in re.finditer(r"^\t(\w+) = spec\((\d+), ", _f2_k, re.M)}
for _kit in ("CropField", "Silo", "Pylon", "CivCar", "Awning", "Planter", "Bin", "Statue", "RoofTank", "ACUnit", "Antenna", "NameSign"):
    (ok if _kit in _f2_parts and _f2_parts[_kit] <= 8 else bad)(f"CLAUDE-BUD J18: kit {_kit} registered, <= 8 parts ({_f2_parts.get(_kit)})")
    must_contain(_f2_wk, f"Builders.{_kit} = function(b: B)", f"CLAUDE-BUD J18: kit {_kit} has a builder")

# themes: items (kit, x, z, opts) per theme
_f2_i = _f2_c.find("\tFill2 = {")
_f2_block = _f2_c[_f2_i:]
_f2_themes = {}
_th_i = _f2_block.find("Themes = {")
_th_j = _f2_block.find("} :: { [string]: { FillItem } },", _th_i)
_cur = None
for _ln in _f2_block[_th_i:_th_j].splitlines():
    _m = re.match(r"^\t\t\t(\w+) = \{$", _ln)
    if _m:
        _cur = _m.group(1)
        _f2_themes[_cur] = []
        continue
    _m = re.search(r'Kit = "(\w+)", X = (-?[\d.]+), Z = (-?[\d.]+)', _ln)
    if _m and _cur:
        _rad = re.search(r"Radius = ([\d.]+)", _ln)
        _f2_themes[_cur].append((_m.group(1), float(_m.group(2)), float(_m.group(3)), float(_rad.group(1)) if _rad else 6.0))
(ok if len(_f2_themes) >= 12 else bad)(f"CLAUDE-BUD J18: themes {sorted(_f2_themes)}")
for _need in ("Farm", "Oil", "Comms", "Ruins", "TankYard", "Palms", "Rocks", "Wadi", "Checkpoint", "Market", "PortYard", "Garrison", "Square"):
    (ok if _f2_themes.get(_need) else bad)(f"CLAUDE-BUD J18: theme {_need} has items")


def _f2_theme_parts(name):
    return sum(_f2_parts.get(k, 0) for k, _, _, _ in _f2_themes.get(name, []) if k != "Rock")


def _f2_theme_reach(name):
    return max((_f2_math.hypot(x, z) + r for _, x, z, r in _f2_themes.get(name, [])), default=0)


# identity fields: never on a plot (+ its gate spawn / apron margin), the Central Plaza or another capture zone
_f2_plots = [(float(a), float(b)) for a, b in re.findall(r"Vector3\.new\((-?\d+), 0\.5, (-?\d+)\)", _f2_bc)]
_f2_half = 160 + 60  # PlotSize 320 / 2 + spawn / gate apron margin
_f2_caps = [(float(x), float(z), float(r)) for x, z, r in re.findall(r"Position = Vector3\.new\((-?\d+), \d+, (-?\d+)\)[^\n]*\n\t*Radius = (\d+)", _f2_tc)]
(ok if len(_f2_plots) >= 6 and len(_f2_caps) >= 7 else bad)(f"CLAUDE-BUD J18: read {len(_f2_plots)} plots, {len(_f2_caps)} capture zones")
_f2_ids = re.findall(r'\{ Id = "(\w+)", Theme = "(\w+)", X = (-?[\d.]+), Z = (-?[\d.]+)', _f2_block)
(ok if len(_f2_ids) >= 10 else bad)(f"CLAUDE-BUD J18: identity fields for the towns ({len(_f2_ids)})")
for _id, _th, _x, _z in _f2_ids:
    _x, _z = float(_x), float(_z)
    _reach = _f2_theme_reach(_th) + 40  # + the sign
    _plot_hit = [p for p in _f2_plots if abs(_x - p[0]) < _f2_half + _reach and abs(_z - p[1]) < _f2_half + _reach]
    _cap_hit = [c for c in _f2_caps if _f2_math.hypot(_x - c[0], _z - c[1]) < c[2] + _reach]
    (ok if not _plot_hit and not _cap_hit else bad)(f"CLAUDE-BUD J18: identity {_id} ({_th}) clear of plots / runways / spawn and capture zones {_plot_hit or ''}{_cap_hit or ''}")
for _town in ("Town", "Port", "Depot", "Armory"):
    (ok if re.search(r'AllowPOI = "' + _town + '"', _f2_block) else bad)(f"CLAUDE-BUD J18: {_town} has its own identity")
must_contain(_f2_cfg, 'Theme = "Market", X = 42, Z = -190', "CLAUDE-BUD J18: Crossroads Town = a market town")
must_not_contain(_f2_cfg, "Coca", "CLAUDE-BUD J18: no real brands on signs")

# every placement goes through the shared occupancy (plots, aprons, runways, pads, captures, anchors, roads, water, POIs)
must_contain(_f2_wf, "local why = if occ and wd then wd.Blocked(occ, wx, wz, r, { Spacing = WorldFillConfig.ItemSpacing, AllowPOI = allowPOI }) else nil", "CLAUDE-BUD J18: kits re-checked against the occupancy")
must_contain(_f2_wf, "local why = if occ and wd then wd.Blocked(occ, wx, wz, r, { AllowPOI = allowPOI }) else nil", "CLAUDE-BUD J18: rocks re-checked against the occupancy")
must_contain(_f2_wf, "if wd.Blocked(occ, cx, cz, C.PatchRadius * 0.5) == nil and emptyAt(occ, wd, cx, cz) then", "CLAUDE-BUD J18: a countryside patch only on a clear, empty cell")
must_contain(_f2_wf, 'if fill2.Parts + 5 <= fill2.Limit and wd.Blocked(occ, x, z, 5, { RoadClear = 8, RoadR = 0 }) == nil then', "CLAUDE-BUD J18: pylons re-checked (never on a plot / in the road lane)")
must_contain(_f2_wf, 'local ok = why == nil or string.sub(why, 1, 4) == "poi:" or string.sub(why, 1, 7) == "anchor:" or string.sub(why, 1, 10) == "structure:"', "CLAUDE-BUD J18: tracks skip water / plots / aprons / pads / captures")
must_contain(_f2_wf, 'local p = plain("Fill2_Track" .. i, Vector3.new(T.Width, 0.12, T.Piece + 1)', "CLAUDE-BUD J18: tracks are flat (drivable)")

# anchored, no scripts, small props shadowless, low quality
must_contain(_f2_wf, "d.Anchored = true", "CLAUDE-BUD J18: every placed part anchored")
must_contain(_f2_wf, 'if d:IsA("Script") or d:IsA("LocalScript") then', "CLAUDE-BUD J18: never scripts in props")
must_contain(_f2_wf, "d.CastShadow = false -- small props cast no shadows", "CLAUDE-BUD J18: small props cast no shadows")
must_contain(_f2_wf, "w.Anchored = true", "CLAUDE-BUD J18: dunes anchored")
must_contain(_f2_wf, "	p.Anchored = true", "CLAUDE-BUD J18: plain parts anchored")
must_not_contain(_f2_wf, "ModelStreamingMode.Persistent", "CLAUDE-BUD J18: nothing Persistent (streams cleanly)")
must_contain("src/ReplicatedStorage/Shared/Configs/QualityConfig.luau", 'Folders = { "WorldFill", ', "CLAUDE-BUD J18: the client's low-quality culling covers the fill folder")
_hide = re.search(r"HideTier2BeyondStuds = (\d+)", read("src/ReplicatedStorage/Shared/Configs/QualityConfig.luau") or "")
(ok if _hide and int(_hide.group(1)) <= 200 else bad)(f"CLAUDE-BUD J18: low quality hides small (Tier 2) clutter beyond <= 200 studs ({_hide.group(1) if _hide else '?'})")

# part budget (upper bound): identity + every cell with the biggest theme + power lines + tracks + rooftops + dunes
_cap_full = float(re.search(r"MaxParts2Full = (\d+)", _f2_block).group(1))
_cap_low = float(re.search(r"MaxParts2Low = (\d+)", _f2_block).group(1))
_size = float(re.search(r"\bSize = (\d+), -- one patch", _f2_block).group(1))
_ext = float(re.search(r"\bExtent = (\d+),", _f2_block).group(1))
_cells = int(2 * _ext // _size) ** 2
_ident = sum(_f2_theme_parts(th) + 3 for _, th, _, _ in _f2_ids)
_mixmax = max(_f2_theme_parts(t) for t in _f2_themes)
_power = 4 * (int((1640 - 420) / 140) + 1) * (3 + 2)
_tracks = sum(int(_f2_math.hypot(float(a) - float(c), float(b) - float(d)) / 40) for a, b, c, d in re.findall(r"\{ X0 = (-?\d+), Z0 = (-?\d+), X1 = (-?\d+), Z1 = (-?\d+) \}", _f2_block[_f2_block.find("Tracks = {"):]))
_roof = 58 * 2 * 2
_dunes = 3 * 8 * 2
_bound = _ident + _cells * _mixmax + _power + _tracks + _roof + _dunes
(ok if _cap_full <= 15000 and _cap_low < _cap_full else bad)(f"CLAUDE-BUD J18: new-part caps Full {_cap_full:.0f} / Low {_cap_low:.0f} (owner cap ~15k)")
(ok if min(_bound, _cap_full) <= 15000 else bad)(f"CLAUDE-BUD J18: upper bound {_bound} parts (capped at {_cap_full:.0f} by the build guard)")
must_contain(_f2_wf, "if why ~= nil or fill2.Parts + planned > fill2.Limit then", "CLAUDE-BUD J18: the build guard stops at the cap")
# aerial read: the grid covers the play area with <= 300-stud cells
(ok if _size <= 300 and _ext >= 1600 else bad)(f"CLAUDE-BUD J18: empty-cell grid {_size:.0f} studs over +-{_ext:.0f} ({_cells} cells): no empty square > ~300 x 300 from the air")
must_contain(_f2_wf, "pcall(WorldFill.Build2, quality, occ, wd, wk) -- claude-bud JOB 18: WorldFill 2 (same folder, same occupancy)", "CLAUDE-BUD J18: one system (WorldFill runs Fill2)")
