# claude-bud (2026-09-28): the runway / hangar size cannot drift from BaseLayoutConfig. Owner's phone test: the live runway
# was still the old size after v90 (190 x 29 runway, 68 x 40 hangar). Root cause: a place saved with a pre-v90 map kept its
# 170 x 24 runway because Bootstrap only heals a same-MAP_GEN map; the fix stamps a layout signature (WE_LayoutSig).
# Runs inside tools/BuyPathStatic.py (its globals). Helpers start with _cbrw_.
_cbrw_blc = "src/ReplicatedStorage/Shared/Configs/BaseLayoutConfig.luau"
_cbrw_svc = "src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau"
_cbrw_vc = "src/ReplicatedStorage/Shared/Configs/VehicleConfig.luau"
_cbrw_ms = "src/ServerScriptService/Server/Modules/MapSetup.luau"
_cbrw_boot = "src/ServerScriptService/Server/Bootstrap.server.luau"
_cbrw_vs = "src/ServerScriptService/Server/Services/VehicleService.luau"
_cbrw_skb = "src/ServerScriptService/Server/Modules/StructureKitBuilder.luau"
_cbrw_af = "src/ServerScriptService/Server/Modules/Installations/Airfield.luau"

_CBRW_RUNWAY = (190, 29)  # owner decision v90 (2026-09-28)
_CBRW_HANGAR = (68, 40)

_cbrw_b = read(_cbrw_blc) or ""
_cbrw_s = read(_cbrw_svc) or ""


def _cbrw_road(name):
    m = re.search(r'\{ Name = "' + name + r'", X = (-?[\d.]+), Z = (-?[\d.]+), SizeX = ([\d.]+), SizeZ = ([\d.]+) \}', _cbrw_b)
    return tuple(float(v) for v in m.groups()) if m else None


def _cbrw_site(sid):
    m = re.search(r"\n\t\t" + sid + r" = \{ Site = \{ X = (-?[\d.]+), Z = (-?[\d.]+) \}, Yaw = (-?[\d.]+)", _cbrw_b)
    return tuple(float(v) for v in m.groups()) if m else None


def _cbrw_inst(sid):
    m = re.search(r"\n\t\t" + sid + r' = \{ Enabled = true, Module = "\w+", Width = ([\d.]+), Depth = ([\d.]+)', _cbrw_s)
    return (float(m.group(1)), float(m.group(2))) if m else None


def _cbrw_rect(x, z, sx, sz):
    return (x - sx / 2, x + sx / 2, z - sz / 2, z + sz / 2)


def _cbrw_overlap(a, b):
    return a[0] < b[1] and b[0] < a[1] and a[2] < b[3] and b[2] < a[3]


# 1. the config sizes (the single source) are the owner's
_cbrw_rw = _cbrw_road("Runway")
(ok if _cbrw_rw and (_cbrw_rw[2], _cbrw_rw[3]) == _CBRW_RUNWAY else bad)(
    f"CLAUDE-BUD runway: BaseLayoutConfig Runway is {_CBRW_RUNWAY[0]} x {_CBRW_RUNWAY[1]} (got {_cbrw_rw})")
_cbrw_hg = _cbrw_inst("Airfield")
(ok if _cbrw_hg == (float(_CBRW_HANGAR[0]), float(_CBRW_HANGAR[1])) else bad)(
    f"CLAUDE-BUD runway: hangar installation is {_CBRW_HANGAR[0]} x {_CBRW_HANGAR[1]} (got {_cbrw_hg})")

# 2. geometry: the strip fits the plot, and the hangar / runway overlap no other base building
_cbrw_m = re.search(r"PlotSize = ([\d.]+)", _cbrw_b)
_cbrw_half = float(_cbrw_m.group(1)) / 2 if _cbrw_m else 0
if _cbrw_rw:
    _cbrw_rr = _cbrw_rect(*_cbrw_rw)
    (ok if _cbrw_half and -_cbrw_half <= _cbrw_rr[0] and _cbrw_rr[1] <= _cbrw_half and -_cbrw_half <= _cbrw_rr[2] and _cbrw_rr[3] <= _cbrw_half else bad)(
        f"CLAUDE-BUD runway: the strip {_cbrw_rr} stays inside the plot (half {_cbrw_half})")
    _cbrw_heli = _cbrw_road("HeliApron")
    (ok if _cbrw_heli and not _cbrw_overlap(_cbrw_rr, _cbrw_rect(*_cbrw_heli)) else bad)("CLAUDE-BUD runway: the strip never overlaps the HeliApron")
    _cbrw_hits = []
    _cbrw_hangar_rect = None
    for _sid in re.findall(r'\n\t\t(\w+) = \{ Enabled = true, Module = "\w+", Width = ', _cbrw_s):
        _site, _dim = _cbrw_site(_sid), _cbrw_inst(_sid)
        if not (_site and _dim):
            continue
        _w, _d = _dim if abs(_site[2]) % 180 == 0 else (_dim[1], _dim[0])
        _r = _cbrw_rect(_site[0], _site[1], _w, _d)
        if _sid == "Airfield":
            _cbrw_hangar_rect = _r
        if _cbrw_overlap(_cbrw_rr, _r):
            _cbrw_hits.append(("Runway", _sid))
    for _sid in re.findall(r'\n\t\t(\w+) = \{ Enabled = true, Module = "\w+", Width = ', _cbrw_s):
        _site, _dim = _cbrw_site(_sid), _cbrw_inst(_sid)
        if _sid == "Airfield" or not (_site and _dim and _cbrw_hangar_rect):
            continue
        _w, _d = _dim if abs(_site[2]) % 180 == 0 else (_dim[1], _dim[0])
        if _cbrw_overlap(_cbrw_hangar_rect, _cbrw_rect(_site[0], _site[1], _w, _d)):
            _cbrw_hits.append(("Hangar", _sid))
    (ok if _cbrw_hangar_rect and not _cbrw_hits else bad)(
        f"CLAUDE-BUD runway: runway and 68 x 40 hangar overlap no installation footprint (hangar {_cbrw_hangar_rect}, hits {_cbrw_hits})")

# 3. every live builder reads the config size (no second hard-coded runway)
must_contain(_cbrw_ms, "Size = Vector3.new(r.SizeX, 0.12, r.SizeZ),", "CLAUDE-BUD runway: MapSetup builds each layout road at its config size")
must_contain(_cbrw_ms, "local len = if alongX then r.SizeX else r.SizeZ", "CLAUDE-BUD runway: runway markings follow the config length")
must_contain(_cbrw_ms, "local n = math.floor(len / 14)", "CLAUDE-BUD runway: centreline dashes span the whole strip")
must_contain(_cbrw_ms, "local along = endSign * (len * 0.5 - 4)", "CLAUDE-BUD runway: threshold bars sit at the real ends")
must_contain(_cbrw_vc, 'RunwayRoad = "Runway", -- BaseLayoutConfig.Roads entry', "CLAUDE-BUD runway: jet spawn reads the Runway road")
must_contain(_cbrw_vs, "for _, r in ipairs(BaseLayoutConfig.Roads) do\n\t\tif r.Name == SpawnCfg.RunwayRoad then", "CLAUDE-BUD runway: VehicleService finds the runway in the config")
must_contain(_cbrw_vs, "local minX, maxX = road.X - road.SizeX * 0.5, road.X + road.SizeX * 0.5", "CLAUDE-BUD runway: jet spawn / take-off run uses the config ends")
must_contain(_cbrw_af, "local S = math.clamp((tonumber(ictx.W) or 58) / 58, 1, 1.3)", "CLAUDE-BUD runway: the hangar shell scales with the installation Width")
# the two old hard-coded strips (70 x 10 composite, 72 x 14 Part kit) must stay dead
must_contain(_cbrw_svc, "PreferMeshWhenAssetIdSet = false,", "CLAUDE-BUD runway: the 70 x 10 Airfield composite (VisualAssetService) stays off")
must_contain(_cbrw_skb, "\tif HollowBuildingBuilder.IsHollow(structureId) then\n\t\tlocal size, offset = HollowBuildingBuilder.FoundationSpec(plinth, structureId)", "CLAUDE-BUD runway: installations skip the 72 x 14 legacy airfield Part kit")

# 4. a saved map from another layout is rebuilt (the root cause)
must_contain(_cbrw_ms, "MapSetup.LAYOUT_SIG = layoutSignature()", "CLAUDE-BUD runway: MapSetup computes the layout signature")
must_contain(_cbrw_ms, 'root:SetAttribute("WE_LayoutSig", MapSetup.LAYOUT_SIG)', "CLAUDE-BUD runway: a built map is stamped with it")
must_contain(_cbrw_ms, 'string.format("R%s:%g,%g,%g,%g", tostring(r.Name), r.X, r.Z, r.SizeX, r.SizeZ)', "CLAUDE-BUD runway: the signature covers every road rectangle")
must_contain(_cbrw_ms, 'string.format("I%s:%g,%g", tostring(id), tonumber(c.Width) or 0, tonumber(c.Depth) or 0)', "CLAUDE-BUD runway: the signature covers installation footprints (hangar)")
must_contain(_cbrw_boot, 'return MapSetup.LAYOUT_SIG ~= nil and setup:GetAttribute("WE_LayoutSig") ~= MapSetup.LAYOUT_SIG', "CLAUDE-BUD runway: Bootstrap rebuilds a saved map from another layout")
