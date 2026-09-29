# claude-bud JOB 3 (2026-09-29): world fill (WorldFillConfig + Server/Modules/WorldFill). Recomputes every item's world
# position from the config and checks it against the keep-outs (plots, water, roads, POIs, captures, garage pads,
# events, the bank, the bounds), the part budget (Full / Low) and the per-kit caps. Runs inside tools/BuyPathStatic.py.
# Helpers start with _cbw_.
import math as _cbw_math

_cbw_cfg_p = "src/ReplicatedStorage/Shared/Configs/WorldFillConfig.luau"
_cbw_mod_p = "src/ServerScriptService/Server/Modules/WorldFill.luau"
_cbw_md_p = "src/ServerScriptService/Server/Modules/MapDressing.luau"
_cbw_c = read(_cbw_cfg_p) or ""

# kit: (size x, size z, parts) at the options used; Rock = Terrain (0 parts)
_CBW_KITS = {
    "Watchtower": (9, 9, 8), "SandbagNest": (8.8, 7.3, 6), "Bunker": (18, 11.5, 3), "Wreck": (14.9, 4.4, 5),
    "FuelTank": (12.4, 12.4, 3), "CrateStack": (5.2, 2.9, 1), "SandbagLine": (5, 1.7, 1), "WireFence": (16, 0.4, 1),
    "DrumGroup": (3.2, 3.0, 1), "RuinedHouse": (14, 11.4, 5), "Revetment": (16.1, 3.9, 3), "DeadTree": (2.05, 1.1, 1),
    "Joshua": (5.7, 5.7, 2), "SandbagArc": (7.1, 2.6, 2), "TankTrap": (4, 4, 2),
}


def _cbw_num(s, k, d=None):
    m = re.search(r"\b" + k + r" = (-?[\d.]+)", s)
    return float(m.group(1)) if m else d


def _cbw_item(line):
    kit = re.search(r'Kit = "(\w+)"', line).group(1)
    it = {"Kit": kit, "X": _cbw_num(line, "X", 0), "Z": _cbw_num(line, "Z", 0), "Tier": int(_cbw_num(line, "Tier", 1)),
          "Radius": _cbw_num(line, "Radius", 10), "Scale": _cbw_num(line, "Scale", 1), "Count": _cbw_num(line, "Count"),
          "Length": _cbw_num(line, "Length")}
    if kit == "Rock":
        it["r"], it["parts"] = it["Radius"], 0
        return it
    sx, sz, p = _CBW_KITS[kit]
    if kit in ("SandbagLine",):
        sx, p = it["Length"], min(8, _cbw_math.ceil(it["Length"] / 5))
    elif kit == "WireFence":
        sx, p = it["Length"], _cbw_math.ceil(it["Length"] / 16)
    elif kit in ("CrateStack", "DrumGroup"):
        p = int(it["Count"] or 3)
    elif kit == "FuelTank":
        sx, sz = sx * it["Scale"], sz * it["Scale"]
    it["r"], it["parts"] = _cbw_math.hypot(sx, sz) / 2, p
    return it


_cbw_templates = {}
for _name in ("Outpost", "PlazaPost"):
    _m = re.search(r"\t\t" + _name + r" = \{\n(.*?)\n\t\t\} :: \{ FillItem \}", _cbw_c, re.S)
    _cbw_templates[_name] = [_cbw_item(l) for l in (_m.group(1).split("\n") if _m else []) if "Kit = " in l]
_cbw_fields = [dict(Id=m[0], T=m[1], X=float(m[2]), Z=float(m[3]), Yaw=float(m[4])) for m in re.findall(
    r'\{ Id = "(\w+)", Template = "(\w+)", X = (-?[\d.]+), Z = (-?[\d.]+), Yaw = (-?[\d.]+) \}', _cbw_c)]
_cbw_roads = [tuple(float(v) for v in m) for m in re.findall(
    r'\{ Name = "Fill_Road\w+", X0 = (-?[\d.]+), Z0 = (-?[\d.]+), X1 = (-?[\d.]+), Z1 = (-?[\d.]+) \}', _cbw_c)]
_cbw_bridges = [(float(a), float(b), float(c)) for a, b, c in re.findall(
    r'\{ Name = "Fill_Bridge\w+", X = (-?[\d.]+), Z0 = (-?[\d.]+), Z1 = (-?[\d.]+) \}', _cbw_c)]

# world keep-outs (from the configs; see ASSUMPTIONS 2026-09-29 JOB 3)
_CBW_PLOTS = [(-800, -400), (-800, 400), (0, -800), (0, 800), (800, -400), (800, 400),
              (-980, -1300), (980, -1300), (-1000, 1280), (560, 1280)]  # claude-bud JOB 21: plots 7-10
_CBW_WATER = [(-1760, -960, -548, -508), (-1760, -960, 252, 292), (108, 148, -1760, -960), (-148, -108, 960, 1364),
              (960, 1760, -292, -252), (960, 1760, 508, 548), (-3240, 3240, 1490, 2210), (-240, 240, 1364, 1490),
              (-872, -832, -1760, -1460), (1088, 1128, -1760, -1460), (-1148, -1108, 1440, 1490), (412, 452, 1440, 1490)]  # JOB 21 channels
_CBW_ROADS = [("X", -800, -1752, 1482), ("X", 0, -1752, 1356), ("X", 800, -1752, 1482),
              ("Z", -800, -1752, 1702), ("Z", 0, -1752, 1752), ("Z", 800, -1702, 1752)]
_CBW_POI_RECT = [(-330, 330, -330, 330), (-1500, -1110, -200, 200), (1110, 1500, -200, 200), (-280, 90, -1480, -1120),
                 (-330, 330, 1150, 1466), (830, 1230, 830, 1230), (1540, 1698, -880, -620), (-1698, -1540, 620, 880),
                 (240, 780, -1380, -1150)]
_CBW_POI_CIRC = [(-950, -950, 130), (1450, -1450, 230), (-1450, 1450, 200), (-540, -1320, 190), (-1380, -1380, 220),
                 (1420, -1060, 150), (1450, 1200, 160), (-540, 1140, 165), (-1300, 560, 125)]
_CBW_CLEAR = [(0, 0, 124), (0, -1300, 110), (0, 1300, 110), (1300, 0, 103), (-1300, 0, 103), (950, 950, 117),
              (-950, -950, 110), (1450, -1450, 103), (-1450, 1450, 103), (220, -220, 32),
              (-548, -438, 53), (-548, 362, 53), (38, -548, 53), (-38, 548, 53), (548, -362, 53), (548, 438, 53),
              (-942, -1048, 53), (1018, -1048, 53), (-1038, 1028, 53), (522, 1028, 53),  # JOB 21 home outposts
              (-150, 150, 20), (520, -1190, 20), (-520, 1080, 20), (-540, -1300, 20), (1100, 1100, 20), (250, 1250, 20)]
_CBW_PADS = [(-578, -338), (-578, 462), (-62, -578), (62, 578), (578, -462), (578, 338),
             (-1042, -1078), (918, -1078), (-938, 1058), (622, 1058),  # JOB 21 gate pads
             (-1180, 34), (1180, -34), (40, 170), (740, -1180)]


def _cbw_rect_dist(x, z, r):
    x0, x1, z0, z1 = r
    dx = max(x0 - x, 0, x - x1)
    dz = max(z0 - z, 0, z - z1)
    return _cbw_math.hypot(dx, dz)


def _cbw_line_dist(x, z, axis, at, lo, hi):
    if axis == "X":  # runs along Z at x = at
        return _cbw_math.hypot(x - at, max(lo - z, 0, z - hi))
    return _cbw_math.hypot(z - at, max(lo - x, 0, x - hi))


def _cbw_blocked(x, z, r):
    for px, pz in _CBW_PLOTS:
        if _cbw_rect_dist(x, z, (px - 160, px + 160, pz - 160, pz + 160)) < r + 40:
            return f"plot({px},{pz})"
    for w in _CBW_WATER:
        if _cbw_rect_dist(x, z, w) < r + 6:
            return f"water{w}"
    for rd in _CBW_ROADS:
        if _cbw_line_dist(x, z, *rd) < r + 13:
            return f"road{rd}"
    for x0, z0, x1, z1 in _cbw_roads:
        if _cbw_line_dist(x, z, "X", x0, min(z0, z1), max(z0, z1)) < r + 13 if x0 == x1 else _cbw_line_dist(x, z, "Z", z0, min(x0, x1), max(x0, x1)) < r + 13:
            return f"fillroad({x0},{z0})"
    for rc in _CBW_POI_RECT:
        if _cbw_rect_dist(x, z, rc) < r + 30:
            return f"poi{rc}"
    for cx, cz, cr in _CBW_POI_CIRC:
        if _cbw_math.hypot(x - cx, z - cz) < cr + 30 + r:
            return f"poi({cx},{cz})"
    for cx, cz, cr in _CBW_CLEAR:
        if _cbw_math.hypot(x - cx, z - cz) < cr + r:
            return f"clear({cx},{cz})"
    for px, pz in _CBW_PADS:
        if _cbw_rect_dist(x, z, (px - 10, px + 10, pz - 10, pz + 10)) < r + 16:
            return f"pad({px},{pz})"
    if abs(x) + r > 1740 or z - r < -1740 or z + r > 1460:
        return "bounds"
    return None


_cbw_full = len(_cbw_roads) + 7 * len(_cbw_bridges)
_cbw_low = _cbw_full
_cbw_bad = []
_cbw_items = 0
for _f in _cbw_fields:
    _a = _cbw_math.radians(_f["Yaw"])
    for _it in _cbw_templates.get(_f["T"], []):
        _x = _f["X"] + _it["X"] * _cbw_math.cos(_a) + _it["Z"] * _cbw_math.sin(_a)
        _z = _f["Z"] - _it["X"] * _cbw_math.sin(_a) + _it["Z"] * _cbw_math.cos(_a)
        _why = _cbw_blocked(_x, _z, _it["r"])
        _cbw_items += 1
        if _why:
            _cbw_bad.append(f"{_f['Id']}:{_it['Kit']}@({_x:.0f},{_z:.0f}) {_why}")
        _cbw_full += _it["parts"]
        if _it["Tier"] == 1:
            _cbw_low += _it["parts"]
        if _it["parts"] > 40:
            _cbw_bad.append(f"{_it['Kit']} has {_it['parts']} parts (> 40)")
for _bx, _bz0, _bz1 in _cbw_bridges:
    for _z in (_bz0 - 60 + 8, _bz1 + 60 - 8):
        _why = _cbw_blocked(_bx, _z, 8)
        if _why:
            _cbw_bad.append(f"bridge landing ({_bx},{_z}) {_why}")

(ok if len(_cbw_fields) >= 10 and all(_cbw_templates.values()) and len(_cbw_roads) == 12 and len(_cbw_bridges) == 2 else bad)(
    f"CLAUDE-BUD worldfill: config parsed ({len(_cbw_fields)} fields, {_cbw_items} items, {len(_cbw_roads)} roads, {len(_cbw_bridges)} bridges)")
(ok if not _cbw_bad else bad)(f"CLAUDE-BUD worldfill: every item clear of plots, water, roads, POIs, captures, pads, events, bounds ({_cbw_bad[:6]})")
_cbw_mf, _cbw_ml = _cbw_num(_cbw_c, "MaxPartsFull", 0), _cbw_num(_cbw_c, "MaxPartsLow", 0)
# world outside bases ~2,476 Full / ~1,679 Low (ASSUMPTIONS); budgets 2,900 / 1,900
(ok if _cbw_full <= _cbw_mf <= 2900 - 2476 and _cbw_low <= _cbw_ml <= 1900 - 1679 else bad)(
    f"CLAUDE-BUD worldfill: planned parts Full {_cbw_full} <= cap {_cbw_mf} <= 424, Low {_cbw_low} <= cap {_cbw_ml} <= 221")
# every kit ends in a road / bridge: both side-gate connectors of each side plot reach RoadZ0 (|z| <= 7)
(ok if sum(1 for r in _cbw_roads if r[0] == r[2] and min(abs(r[1]), abs(r[3])) <= 7) == 4 else bad)(
    "CLAUDE-BUD worldfill: the four side-base connectors reach RoadZ0 (to the plaza)")
_cbw_b = re.search(r"DeckBottomY = ([\d.]+)", _cbw_c)
(ok if _cbw_b and float(_cbw_b.group(1)) - 1.5 >= 18 else bad)("CLAUDE-BUD worldfill: bridges leave >= 18 studs over the water for boats")

must_contain(_cbw_cfg_p, "\tEnabled = true,\n\tFolderName = \"WorldFill\",", "CLAUDE-BUD worldfill: one Workspace folder, kill switch Enabled")
must_contain(_cbw_mod_p, "f.Parent = Workspace", "CLAUDE-BUD worldfill: the folder lives in Workspace")
must_contain(_cbw_mod_p, "if d:IsA(\"Script\") or d:IsA(\"LocalScript\") then\n\t\t\t\t\t\t\t\t\t\td:Destroy() -- never scripts in world props", "CLAUDE-BUD worldfill: no scripts in props")
must_contain(_cbw_mod_p, "local why = if occ and wd then wd.Blocked(occ, wx, wz, r, { Spacing = WorldFillConfig.ItemSpacing }) else nil", "CLAUDE-BUD worldfill: every kit re-checked at runtime (WorldDress.Blocked)")
must_contain(_cbw_mod_p, "if it.Tier == 1 or full then", "CLAUDE-BUD worldfill: Tier 2 only on Full quality (phones on Low)")
must_contain(_cbw_md_p, "local okR, errR = pcall(wfill.ReserveRoads, occ, wd)", "CLAUDE-BUD worldfill: roads reserved before the travel dressing")
must_contain(_cbw_md_p, "local okF, errF = pcall(wfill.Build, quality, occ, wd, wk)", "CLAUDE-BUD worldfill: props built after the dressing")
must_not_contain(_cbw_mod_p, "math.random", "CLAUDE-BUD worldfill: seeded WorldKits.Rng only")
must_not_contain(_cbw_mod_p, "PointLight", "CLAUDE-BUD worldfill: no new lights")
must_not_contain(_cbw_mod_p, "Enum.Material.Neon", "CLAUDE-BUD worldfill: no Neon")
