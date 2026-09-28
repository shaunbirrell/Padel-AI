# v90 (Code Bot): Claude's harbour pins (handoff/wip/05), moved out of the frozen BuyPathStatic.py.

# ── fb4 harbour (owner 2026-09-28: the default boat "looks terrible", the dock building "should look like a legit dock
# building"): the Naval Dock's Part kit comes from DockKitConfig (quay, brick warehouse, moored patrol boat, crane, control
# tower, containers, launch) as "Styled" kit parts that keep their own look; BaseService only shows them by level.
# Fix round 2 adds: styledPart / buildStyledDockKit body pins, one-line row count, solid load-bearing pieces, nothing
# floats (low pieces rest on the quay or the pad), the moored boat's wheelhouse at player scale.
# Fix round 3 adds: solid pieces stay off the land lanes (Dock gate, sea-gate guard / berm / lane, helipad), the boarding
# ramp's walk space is clear, the pad sweep (UpgradePadService.hardenPad) leaves Styled pieces' CanQuery alone, the
# Styled branch compares Transparency with a tolerance, and the showroom spin loop scans the slots twice a second.
HB_CFG = "src/ReplicatedStorage/Shared/Configs/DockKitConfig.luau"
HB_SKB = "src/ServerScriptService/Server/Modules/StructureKitBuilder.luau"
HB_BS = "src/ServerScriptService/Server/Services/BaseService.luau"
HB_UPS = "src/ServerScriptService/Server/Services/UpgradePadService.luau"


class _HbV:
    """Vector3 stand-in for DockKitConfig's V(x, y, z) literals and constants"""
    def __init__(self, x, y, z):
        self.X, self.Y, self.Z = float(x), float(y), float(z)


def _hb_call_arg(s: str, key: str) -> str | None:
    """the text of `key = V(...)` (balanced parentheses) in one config row, or None"""
    i = s.find(key + " = V(")
    if i < 0:
        return None
    j = i + len(key) + 3
    depth = 0
    for k in range(j, len(s)):
        if s[k] == "(":
            depth += 1
        elif s[k] == ")":
            depth -= 1
            if depth == 0:
                return s[j:k + 1]
    return None


def _hb_pieces() -> list[dict] | None:
    """every DockKitConfig piece row: name, shape, size, pos (or from / to), rot, minlevel, collide, material; the numeric
    constants above the rows (roof pitch, jib ends) are evaluated like the Luau does (math.* only)"""
    body = read(HB_CFG)
    if body is None:
        return None
    import math as _hbmath
    import types as _hbtypes
    _hbm = _hbtypes.SimpleNamespace(deg=_hbmath.degrees, rad=_hbmath.radians, atan=_hbmath.atan, atan2=_hbmath.atan2,
                                    sqrt=_hbmath.sqrt, cos=_hbmath.cos, sin=_hbmath.sin, abs=abs, max=max, min=min,
                                    floor=_hbmath.floor, pi=_hbmath.pi)
    env = {"_m": _hbm, "V": _HbV}
    for m in re.finditer(r"^local (\w+) = ([^\n]+?)(?:\s+--[^\n]*)?$", body, re.M):
        try:
            env[m.group(1)] = eval(m.group(2).replace("math.", "_m."), {"__builtins__": {}}, env)
        except Exception:
            pass

    def vec(s, key):
        a = _hb_call_arg(s, key)
        if a is None:
            m = re.search(key + r" = (\w+)[,}]", s)
            v = env.get(m.group(1)) if m else None
            return (v.X, v.Y, v.Z) if isinstance(v, _HbV) else None
        try:
            v = eval(a.replace("math.", "_m."), {"__builtins__": {}}, env)
            return (v.X, v.Y, v.Z)
        except Exception:
            return None

    rows = []
    for line in body.splitlines():
        s = line.strip()
        if not s.startswith("{ Name = "):
            continue
        r = {"line": s, "name": re.search(r'Name = "([^"]+)"', s).group(1)}
        m = re.search(r'Shape = "(\w+)"', s)
        r["shape"] = m.group(1) if m else "Block"
        m = re.search(r"MinLevel = (\d+)", s)
        r["min"] = int(m.group(1)) if m else None
        r["collide"] = "Collide = true" in s
        m = re.search(r"Material = M\.(\w+)", s)
        r["mat"] = m.group(1) if m else None
        r["size"], r["pos"], r["rot"] = vec(s, "Size"), vec(s, "Pos"), vec(s, "Rot") or (0.0, 0.0, 0.0)
        f, t = vec(s, "From"), vec(s, "To")
        r["beam"] = (f + t) if f and t else None
        rows.append(r)
    return rows


def _hb_z_range(r: dict) -> tuple[float, float] | None:
    """kit-frame z extent of a piece (CFrame.Angles(X, Y, Z) = Rx * Ry * Rz; a beam: its two ends +- the section)"""
    import math as _hbm
    if r["beam"] is not None and r["size"]:
        h = max(r["size"][0], r["size"][1]) * 0.5
        return min(r["beam"][2], r["beam"][5]) - h, max(r["beam"][2], r["beam"][5]) + h
    if r["pos"] is None or r["size"] is None:
        return None
    ax, ay, az = (_hbm.radians(v) for v in r["rot"])
    cx, sx, cy, sy, cz, sz = _hbm.cos(ax), _hbm.sin(ax), _hbm.cos(ay), _hbm.sin(ay), _hbm.cos(az), _hbm.sin(az)
    # third row of Rx(ax) * Ry(ay) * Rz(az)
    row = (-cx * sy * cz + sx * sz, cx * sy * sz + sx * cz, cx * cy)
    ez = sum(abs(row[i]) * r["size"][i] * 0.5 for i in range(3))
    return r["pos"][2] - ez, r["pos"][2] + ez


def _hb_extent(r: dict, axis: int) -> tuple[float, float] | None:
    """kit-frame extent of a block piece along axis 0 / 1 / 2 (x / y / z), from its rotated box (CFrame.Angles(X, Y, Z) =
    Rx * Ry * Rz); None for a beam (From / To) or a row without Pos / Size"""
    import math as _hbm
    if r["beam"] is not None or r["pos"] is None or r["size"] is None:
        return None
    ax, ay, az = (_hbm.radians(v) for v in r["rot"])
    cx, sx, cy, sy, cz, sz = _hbm.cos(ax), _hbm.sin(ax), _hbm.cos(ay), _hbm.sin(ay), _hbm.cos(az), _hbm.sin(az)
    rows = ((cy * cz, -cy * sz, sy),
            (sx * sy * cz + cx * sz, -sx * sy * sz + cx * cz, -sx * cy),
            (-cx * sy * cz + sx * sz, cx * sy * sz + sx * cz, cx * cy))
    e = sum(abs(rows[axis][i]) * r["size"][i] * 0.5 for i in range(3))
    return r["pos"][axis] - e, r["pos"][axis] + e


def _hb_box(r: dict) -> list[tuple[float, float]] | None:
    """fix round 3: kit-frame axis-aligned box [(x0, x1), (y0, y1), (z0, z1)] of any piece: a block from its rotated box,
    a beam (From / To) from its two ends +- half its widest section"""
    if r["beam"] is not None:
        if not r["size"]:
            return None
        h = max(r["size"][0], r["size"][1]) * 0.5
        f, t = r["beam"][:3], r["beam"][3:]
        return [(min(f[i], t[i]) - h, max(f[i], t[i]) + h) for i in range(3)]
    ex = [_hb_extent(r, a) for a in range(3)]
    return ex if all(e is not None for e in ex) else None


def _hb_dock_kit_rules() -> None:
    rows = _hb_pieces()
    if not rows:
        bad("fb4 harbour: DockKitConfig.Pieces rows not found")
        return
    # budget: 86 pieces + the hidden Body core and boat host = 88 kit parts per base (the old kit had 24); cap 90
    if len(rows) <= 88:
        ok(f"fb4 harbour: {len(rows)} dock pieces (+ hidden Body and boat host) — within the 90-part kit budget")
    else:
        bad(f"fb4 harbour: {len(rows)} dock pieces > 88 (per-base part budget)")
    # every level shows at most 50 new parts (instance changes per purchase: target 60, gates and Body included)
    per = {}
    for r in rows:
        per[r["min"]] = per.get(r["min"], 0) + 1
    if all(r["min"] is not None and 0 <= r["min"] <= 5 for r in rows) and max(per.values()) <= 50:
        ok(f"fb4 harbour: pieces per Dock level {dict(sorted(per.items()))} (each level <= 50 new parts)")
    else:
        bad(f"fb4 harbour: a piece has no MinLevel 0..5 or a level shows > 50 parts: {per}")
    # phone budget rules: no Neon, no lights / text / guis in the kit rows
    neon = [r["name"] for r in rows if r["mat"] == "Neon"]
    if not neon and all(r["mat"] for r in rows):
        ok("fb4 harbour: no Neon piece and every piece names its material")
    else:
        bad(f"fb4 harbour: Neon / material-less pieces {neon}")
    # a material name Roblox does not have (e.g. "CorrugatedPlate") errors when the config is required: live Enum.Material names only
    real = {"Asphalt", "Basalt", "Brick", "Cardboard", "Carpet", "CeramicTiles", "ClayRoofTiles", "Cobblestone", "Concrete",
            "CorrodedMetal", "CrackedLava", "DiamondPlate", "Fabric", "Foil", "ForceField", "Glacier", "Glass", "Granite", "Grass",
            "Ground", "Ice", "LeafyGrass", "Leather", "Limestone", "Marble", "Metal", "Mud", "Neon", "Pavement", "Pebble", "Plaster",
            "Plastic", "Rock", "RoofShingles", "Rubber", "Salt", "Sand", "Sandstone", "Slate", "SmoothPlastic", "Snow", "Wood",
            "WoodPlanks"}
    unknown = sorted({r["mat"] for r in rows if r["mat"] and r["mat"] not in real})
    if not unknown:
        ok("fb4 harbour: every piece material is a real Enum.Material name")
    else:
        bad(f"fb4 harbour: unknown Enum.Material names {unknown} (the config would error on require)")
    # the moored boats float in the dock basin (kit z 25.4 .. 33, x -35 .. 35), clear of the sea gate lane (x >= 35)
    boats = [r for r in rows if r["name"].startswith(("Boat", "Launch"))]
    out = []
    for r in boats:
        if r["pos"] is None or r["size"] is None:
            continue
        x, _, z = r["pos"]
        if not (25.3 <= z <= 33 and -35 <= x <= 35):
            out.append(r["name"])
    if len(boats) >= 20 and not out:
        ok(f"fb4 harbour: {len(boats)} boat / launch pieces all inside the basin's west strip (z 25.3..33), clear of the gate lane")
    else:
        bad(f"fb4 harbour: boat pieces outside the basin strip {out} (or too few boat pieces: {len(boats)})")
    # colliding pieces: on land (z <= 23.8, the kerb) or a hull in the basin strip; none reaches the gate lane or the
    # basin's middle, where boats spawn (kit z >= 34)
    bad_c = []
    for r in rows:
        if not r["collide"]:
            continue
        zs = _hb_z_range(r)
        if zs is None or zs[1] > 33.5:
            bad_c.append(r["name"])
    if not bad_c:
        ok("fb4 harbour: no colliding dock piece reaches past kit z 33.5 (the basin's spawn water and the sea gate lane stay open)")
    else:
        bad(f"fb4 harbour: colliding pieces reach the open basin: {bad_c}")
    # decor too: nothing of the kit hangs over the open basin (kit z > 33.5), where driven boats spawn and sail and a
    # non-colliding piece (crane cable, hook) would visibly cut through a passing hull
    over = []
    for r in rows:
        zs = _hb_z_range(r)
        if zs is None or zs[1] > 33.5:
            over.append(r["name"])
    if not over:
        ok("fb4 harbour: no dock piece of any kind reaches past kit z 33.5 (nothing hangs over the open basin)")
    else:
        bad(f"fb4 harbour: pieces reach over the open basin (kit z > 33.5): {over}")
    # the crane's hanging parts over the water (past the kerb, z > 25) stay 14+ studs up: a boat passing under clears them
    low = []
    for r in rows:
        if not r["name"].startswith("Crane") or r["beam"] is not None:
            continue
        zs = _hb_z_range(r)
        if r["pos"] is None or r["size"] is None or zs is None:
            low.append(r["name"])
        elif zs[1] > 25 and r["pos"][1] - r["size"][1] * 0.5 < 14:
            low.append(r["name"])
    if not low:
        ok("fb4 harbour: the crane's cable and hook over the water hang 14+ studs above the pad")
    else:
        bad(f"fb4 harbour: crane parts hang low over the water (< 14 studs): {low}")
    # the L5 smoke plume: BaseService hangs WE_MaxSmoke on the kit child named "Roof" (the old kit's shed roof); the
    # harbour keeps exactly one "Roof" piece (the warehouse chimney), shown by L5, decor only
    roof = [r for r in rows if r["name"] == "Roof"]
    if len(roof) == 1 and roof[0]["min"] is not None and roof[0]["min"] <= 5 and not roof[0]["collide"]:
        ok("fb4 harbour: one \"Roof\" piece (warehouse chimney) hosts the Dock's L5 smoke plume, as on the old kit")
    else:
        bad(f"fb4 harbour: the Dock kit needs exactly one decor piece named \"Roof\" shown by L5 (L5 smoke host): {[r['line'] for r in roof]}")
    # the quay a player walks on: one colliding deck, top 0.4 over the pad, up to the kerb (z 23.8)
    deck = [r for r in rows if r["name"] == "QuayDeck"]
    if len(deck) == 1 and deck[0]["collide"] and deck[0]["min"] == 0 and deck[0]["pos"] and abs(deck[0]["pos"][1] + deck[0]["size"][1] * 0.5 - 0.4) < 1e-6 \
            and abs(deck[0]["pos"][2] + deck[0]["size"][2] * 0.5 - 23.8) < 1e-6:
        ok("fb4 harbour: the QuayDeck collides, is there from L0, top 0.4 over the pad, ends at the kerb (z 23.8)")
    else:
        bad(f"fb4 harbour: QuayDeck row changed: {deck[0]['line'] if deck else 'missing'}")
    # fix round 2: every row of the Pieces table is read. A row written across several lines (formatter style) is not a
    # "{ Name = ..." line, so it would skip every rule above: the table's `Name = "` count must equal the rows parsed
    body = read(HB_CFG) or ""
    ti = body.find("local pieces: { DockPiece } = {\n")
    tj = body.find("\n}\n", ti)
    names = len(re.findall(r'\bName = "', body[ti:tj])) if ti >= 0 and tj > ti else -1
    if names == len(rows):
        ok(f"fb4 harbour: all {names} rows of DockKitConfig.Pieces are one-line rows the rules above read")
    else:
        bad(f"fb4 harbour: DockKitConfig.Pieces has {names} `Name = \"` entries but {len(rows)} one-line rows (keep each piece on one line)")
    # the load-bearing pieces stay solid: the quay a player walks on, the warehouse, the moored hull (boot-top, hull,
    # forecastle, wheelhouse: a driven boat bumps it and a spawn never overlaps it) and the gangway onto its deck
    need = ("QuayDeck", "WarehouseBlock", "BoatBoot", "BoatHull", "BoatForecastle", "BoatWheelhouse", "Gangway")
    soft = [n for n in need if not any(r["name"] == n for r in rows) or any(r["name"] == n and not r["collide"] for r in rows)]
    if not soft:
        ok(f"fb4 harbour: the load-bearing pieces collide ({', '.join(need)})")
    else:
        bad(f"fb4 harbour: load-bearing pieces missing or not Collide = true: {soft}")
    # nothing floats: every low block piece (bottom under +1; not a beam, not the QuayDeck itself) rests on what is
    # under its centre - the QuayDeck top on the quay, the bare pad top (0) landward of the quay (kit z < the quay's
    # landward edge). Pieces over the basin (z > the kerb) float on the water; the basin rules above cover them.
    if deck and deck[0]["pos"] and deck[0]["size"]:
        (dx, dy, dz), (sx_, sy_, sz_) = deck[0]["pos"], deck[0]["size"]
        qx0, qx1, qz0, qz1, qtop = dx - sx_ * 0.5, dx + sx_ * 0.5, dz - sz_ * 0.5, dz + sz_ * 0.5, dy + sy_ * 0.5
        float_ = []
        n_rest = 0
        for r in rows:
            if r["name"] == "QuayDeck":
                continue
            ys = _hb_extent(r, 1)
            if ys is None or ys[0] >= 1:
                continue
            x, _, z = r["pos"]
            if z < qz0:
                want = 0.0
            elif z <= qz1 and qx0 <= x <= qx1:
                want = qtop
            else:
                continue
            n_rest += 1
            if abs(ys[0] - want) > 0.02:
                float_.append(f"{r['name']} bottom {ys[0]:+.2f} (on {'the pad 0' if want == 0 else f'the quay {qtop:+.2f}'})")
        if not float_ and n_rest >= 10:
            ok(f"fb4 harbour: {n_rest} low pieces rest on the quay (+{qtop:.2f}) or on the pad (0): nothing floats or sinks")
        else:
            bad(f"fb4 harbour: pieces float above / sink into what they stand on: {float_} (or too few low pieces: {n_rest})")
    else:
        bad("fb4 harbour: no QuayDeck row to check what the low pieces stand on")
    # the moored patrol boat at player scale: the wheelhouse stands on the hull's deck line and is >= 5.5 tall (a
    # 5-stud avatar on deck is under its roof); the roof sits on it and the mast on the roof
    def one(n):
        m = [r for r in rows if r["name"] == n]
        return _hb_extent(m[0], 1) if len(m) == 1 else None
    hull, wh, whr, mast, glass = (one(n) for n in ("BoatHull", "BoatWheelhouse", "BoatWheelhouseRoof", "BoatMast", "BoatBridgeGlass"))
    if hull and wh and whr and mast and glass and abs(wh[0] - hull[1]) <= 0.05 and wh[1] - wh[0] >= 5.5 \
            and abs(whr[0] - wh[1]) <= 0.05 and abs(mast[0] - whr[1]) <= 0.05 and glass[0] >= hull[1] + 3.5 and glass[1] <= wh[1]:
        ok(f"fb4 harbour: the moored boat's wheelhouse is at player scale ({wh[1] - wh[0]:.1f} tall over the deck, window band at "
           f"+{glass[0] - hull[1]:.1f} .. +{glass[1] - hull[1]:.1f}), roof on it, mast on the roof")
    else:
        bad(f"fb4 harbour: moored boat superstructure off scale or detached: hull {hull} wheelhouse {wh} roof {whr} mast {mast} glass {glass}")
    # fix round 3: solid pieces stay off the land lanes the Dock must leave open - kit x -48 .. 34 (the QuayDeck's span:
    # the inner Dock gate lane is at x <= -48, the sea-gate guard (38, 20), the sandbag berm (38, 2) and the sea-gate
    # lane land at x >= 35) and kit z >= -20 (the helipad is at z <= -24)
    lane = []
    n_solid = 0
    for r in rows:
        if not r["collide"]:
            continue
        n_solid += 1
        b = _hb_box(r)
        if b is None or b[0][0] < -48 - 1e-6 or b[0][1] > 34 + 1e-6 or b[2][0] < -20 - 1e-6:
            lane.append(f"{r['name']} x {b[0][0]:.1f}..{b[0][1]:.1f} z {b[2][0]:.1f}..{b[2][1]:.1f}" if b else r["name"])
    if not lane and n_solid >= 20:
        ok(f"fb4 harbour: all {n_solid} solid dock pieces stay inside kit x -48..34, z >= -20 (Dock gate lane, sea-gate guard / berm / lane and helipad stay open)")
    else:
        bad(f"fb4 harbour: solid dock pieces on a land lane (x outside -48..34 or z < -20): {lane} (or too few solid pieces: {n_solid})")
    # fix round 3: the boarding ramp's walk space is clear - over the Gangway's walking surface (its width, from the
    # surface + 0.05 up to + 5, quay end to deck end) no piece pokes through except what the ramp rests on (the quay,
    # the hull, its boot-top, strake and deck). A fender or bulwark there shows as clipping through the avatar's legs.
    gw = [r for r in rows if r["name"] == "Gangway"]
    if len(gw) == 1 and gw[0]["beam"] is not None and gw[0]["size"]:
        (fx, fy, fz, tx, ty, tz), (gwx, gwy, _) = gw[0]["beam"], gw[0]["size"]
        rest = ("Gangway", "QuayDeck", "BoatHull", "BoatBoot", "BoatStrake", "BoatDeck")
        hits = set()
        steps = 60
        for k in range(steps):
            u0, u1 = k / steps, (k + 1) / steps
            za, zb = fz + (tz - fz) * u0, fz + (tz - fz) * u1
            ya, yb = fy + (ty - fy) * u0 + gwy * 0.5, fy + (ty - fy) * u1 + gwy * 0.5
            xa, xb = min(fx, tx) - gwx * 0.5, max(fx, tx) + gwx * 0.5
            y0, y1 = min(ya, yb) + 0.05, max(ya, yb) + 5
            for r in rows:
                if r["name"] in rest:
                    continue
                b = _hb_box(r)
                if b is None:
                    continue
                if b[0][0] < xb and b[0][1] > xa and b[1][0] < y1 and b[1][1] > y0 and b[2][0] < max(za, zb) and b[2][1] > min(za, zb):
                    hits.add(r["name"])
        if not hits:
            ok("fb4 harbour: the gangway's walk space is clear (no fender, bulwark or rope pokes through the boarding ramp)")
        else:
            bad(f"fb4 harbour: pieces poke through the gangway's walk space: {sorted(hits)}")
    else:
        bad("fb4 harbour: no single Gangway beam row to check the boarding path")


if re.search(r"^\tEnabled = (true|false),$", read(HB_CFG) or "", re.M):
    ok("fb4 harbour: DockKitConfig.Enabled is a plain true / false (false = the v35 / v37 kit, the documented rollback)")
else:
    bad("fb4 harbour: DockKitConfig.Enabled line missing or not a plain `\tEnabled = true,` / `\tEnabled = false,`")
must_contain(HB_SKB, "local DockKitConfig = require(Shared.Configs.DockKitConfig)\n", "fb4 harbour: StructureKitBuilder reads DockKitConfig")
must_contain(HB_SKB, "\t\tif DockKitConfig.Enabled ~= false then\n\t\t\tbuildStyledDockKit(plinth, pal)\n\t\t\tplinth:SetAttribute(\"WE_KitGen\", KIT_GEN)\n\t\t\treturn\n\t\tend\n",
             "fb4 harbour: the dock kit branch builds the harbour first and keeps the v35 kit below as the rollback")
must_contain(HB_SKB, "\tp.Transparency = 1\n\tp.CanCollide = false\n\tp.CanTouch = false\n\tp.CanQuery = false\n\tp.CastShadow = false\n\tp:SetAttribute(\"WE_KitRole\", \"Styled\")\n",
             "fb4 harbour: a Styled piece is built hidden, not colliding, not queryable (BaseService shows it by level)")
must_contain(HB_SKB, "\tstyledPart(plinth, { Name = \"WE_DressHost_ParkedBoat\", Size = cfg.ParkedBoatHost.Size, Pos = cfg.ParkedBoatHost.Pos, Color = Color3.fromRGB(60, 65, 55), Material = Enum.Material.Metal, MinLevel = 99, Transparency = 1 }, padTop)\n",
             "fb4 harbour: the hidden WE_DressHost_ParkedBoat stays (EnsureKit counts it as the Dock's dress: no rebuild loop)")
must_contain(HB_SKB, "\tkitPart(plinth, \"Body\", cfg.Body.Size, cfg.Body.Pos + lift, pal.Body, Enum.Material.Concrete, nil)\n",
             "fb4 harbour: the kit keeps a Body (EnsureKit visibility gate), a concrete core hidden inside the warehouse from L1")
# fix round 2: inside styledPart / buildStyledDockKit (function-scoped: kitPart has its own `p.Parent = plinth`)
_hb_skb = read(HB_SKB) or ""
_hb_si = _hb_skb.find("local function styledPart(plinth: BasePart, pc: any, padTop: number): BasePart\n")
_hb_sj = _hb_skb.find("\nend\n", _hb_si)
_hb_sp = _hb_skb[_hb_si:_hb_sj + 1] if _hb_si >= 0 and _hb_sj > _hb_si else ""
_hb_ki = _hb_skb.find("local function buildStyledDockKit(plinth: BasePart, pal: any): number\n")
_hb_kj = _hb_skb.find("\nend\n", _hb_ki)
_hb_kb = _hb_skb[_hb_ki:_hb_kj + 1] if _hb_ki >= 0 and _hb_kj > _hb_ki else ""
for _hb_need, _hb_why in (
        ("\tlocal lift = Vector3.new(0, padTop, 0)\n", "lifts every piece onto the pad top (Y in the config is above the pad top)"),
        ("\t\tlocal a: Vector3 = pc.From + lift\n\t\tlocal b: Vector3 = pc.To + lift\n", "lifts both ends of a beam (ropes, gangway, jib)"),
        ("\t\tlocalCF = CFrame.new((pc.Pos or Vector3.zero) + lift) * CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))\n",
         "places a block piece at its lifted centre with its CFrame.Angles(X, Y, Z) rotation"),
        ("\tp:SetAttribute(\"WE_MinLevel\", tonumber(pc.MinLevel) or 1)\n", "stores the level that shows the piece"),
        ("\tp:SetAttribute(\"WE_Collide\", pc.Collide == true)\n", "stores whether the shown piece is solid"),
        ("\tp:SetAttribute(\"WE_Shadow\", pc.Shadow == true)\n", "stores whether the shown piece casts a shadow"),
        ("\tp:SetAttribute(\"WE_BaseTransparency\", tonumber(pc.Transparency) or 0)\n", "stores the shown transparency"),
        ("\tp.Parent = plinth\n\treturn p\n", "parents the piece to the Dock plinth (else nothing is built)")):
    if _hb_need in _hb_sp:
        ok(f"fb4 harbour: styledPart {_hb_why}")
    else:
        bad(f"fb4 harbour: styledPart no longer {_hb_why} — missing `{_hb_need.strip()}`")
if "\tfor _, pc in ipairs(cfg.Pieces) do\n\t\tstyledPart(plinth, pc, padTop)\n" in _hb_kb:
    ok("fb4 harbour: buildStyledDockKit builds every DockKitConfig.Pieces row")
else:
    bad("fb4 harbour: buildStyledDockKit no longer loops over cfg.Pieces with styledPart (the dock would be empty)")
must_contain(HB_BS, "\t\t\telseif role == \"Styled\" then\n",
             "fb4 harbour: BaseService.applyKitVisuals handles the Styled role")
must_contain(HB_BS, "\t\t\t\tlocal shown = lv >= (tonumber(child:GetAttribute(\"WE_MinLevel\")) or 1)\n\t\t\t\tlocal tr = if shown then (tonumber(child:GetAttribute(\"WE_BaseTransparency\")) or 0) else 1\n\t\t\t\tlocal collide = shown and tr < 1 and child:GetAttribute(\"WE_Collide\") == true\n",
             "fb4 harbour: a Styled part shows from its WE_MinLevel and collides only when shown")
_hb_bs = read(HB_BS) or ""
_hb_i = _hb_bs.find("\t\t\telseif role == \"Styled\" then\n")
_hb_j = _hb_bs.find("\t\t\telseif role == \"Detail\" or role == \"Pier\"", _hb_i)
_hb_branch = _hb_bs[_hb_i:_hb_j] if _hb_i >= 0 and _hb_j > _hb_i else ""
if _hb_branch and not any(w in _hb_branch for w in ("child.Color", "child.Material", "child.Size", "placeKitPart", "child.CFrame")):
    ok("fb4 harbour: the Styled branch never changes a piece's colour, material, size or place (the level only shows it)")
else:
    bad("fb4 harbour: the Styled branch is missing or writes a piece's look / size / place")
# the four writes that show a piece at its level and give it its collision / query / shadow, each compare-first, inside
# the Styled branch (without the Transparency write every piece stays invisible: styledPart builds them at 1)
# (fix round 3: Transparency is float32, so it is compared with a tolerance; an exact ~= would rewrite a 0.3 piece on
# every sync)
for _hb_prop, _hb_val, _hb_why in (("Transparency", "tr", "shows the piece from its level (built at Transparency 1)"),
                                   ("CanCollide", "collide", "makes a shown solid piece walkable / solid"),
                                   ("CanQuery", "collide", "makes a shown solid piece queryable (spawn / land-probe / camera checks see it)"),
                                   ("CastShadow", "shadow", "gives the big volumes their shadow")):
    _hb_cmp = (f"math.abs(child.{_hb_prop} - {_hb_val}) > 1e-3 then -- Transparency is float32: compare with a tolerance"
               if _hb_prop == "Transparency" else f"child.{_hb_prop} ~= {_hb_val} then")
    _hb_w = f"\t\t\t\tif {_hb_cmp}\n\t\t\t\t\tchild.{_hb_prop} = {_hb_val}\n\t\t\t\tend\n"
    if _hb_w in _hb_branch:
        ok(f"fb4 harbour: the Styled branch writes {_hb_prop} compare-first ({_hb_why})")
    else:
        bad(f"fb4 harbour: the Styled branch lost its compare-first {_hb_prop} write ({_hb_why})")
# fix round 3: UpgradePadService.hardenPad re-runs on every already-attached slot (its +1 s sweep, zero-pad rescans) and
# switches CanQuery off on every BasePart under the pad; it must skip the Styled Dock pieces, whose CanQuery BaseService
# sets with CanCollide (spawn clearance, the boat land probe and the camera need the solid harbour pieces queryable)
must_contain(HB_UPS, "\t\tif child:IsA(\"BasePart\") and child:GetAttribute(\"WE_KitRole\") ~= \"Styled\" then\n\t\t\tchild.CanTouch = false\n\t\t\tchild.CanQuery = false\n",
             "fb4 harbour: UpgradePadService.hardenPad leaves Styled Dock pieces' CanQuery alone (a pad re-harden sweep keeps the harbour solids queryable)")
# fix round 3: BaseService.ensureShowroomSpin no longer walks every upgrade slot's children on every server Heartbeat
# (the Dock plinth alone holds 88 kit parts): it re-scans for the spinning displays twice a second and each frame only
# turns the displays it found
must_contain(HB_BS, "\t\tsinceScan += dt\n\t\tif sinceScan >= 0.5 then\n\t\t\tsinceScan = 0\n\t\t\ttable.clear(spinParts)\n\t\t\tfor _, inst in ipairs(CollectionService:GetTagged(\"WE_UpgradeSlot\")) do\n",
             "fb4 harbour: the showroom spin loop scans the upgrade slots twice a second, not every Heartbeat")
must_contain(HB_BS, "\t\tfor _, child in ipairs(spinParts) do\n\t\t\tif child.Parent ~= nil and child.Transparency < 0.5 then\n\t\t\t\tchild.CFrame = child.CFrame * CFrame.Angles(0, math.rad(22) * dt, 0)\n",
             "fb4 harbour: each Heartbeat the showroom spin loop only turns the displays it found (22 deg/s, shown ones)")
_hb_dock_kit_rules()
# ── end fb4 harbour

