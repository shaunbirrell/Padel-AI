# claude-bud JOB 17 (2026-09-29): night readable on phones (LightingConfig + WorldAtmosphere + NightLights +
# QualityGovernor). Midnight ambient ~ (90, 95, 120), a Brightness floor, the moonlit ColorCorrection, night ~40 % of
# the cycle, <= ~120 lights with Shadows off and Range 40-60, glow only at night, low quality halves the lights.
_n_cfg = "src/ReplicatedStorage/Shared/Configs/LightingConfig.luau"
_n_wa = "src/ServerScriptService/Server/Modules/WorldAtmosphere.luau"
_n_nl = "src/ServerScriptService/Server/Modules/NightLights.luau"
_n_qg = "src/StarterPlayer/StarterPlayerScripts/Client/Modules/QualityGovernor.luau"
_n_c = read(_n_cfg) or ""
_n_l = read(_n_nl) or ""


def _n_rgb(key):
    m = re.search(r"\t\t" + key + r" = Color3\.fromRGB\((\d+), (\d+), (\d+)\)", _n_c)
    return tuple(int(x) for x in m.groups()) if m else None


def _n_num(block, key):
    i = _n_c.find("\t" + block + " = {")
    if i < 0:
        return None
    m = re.search(r"\b" + key + r" = (-?[\d.]+)", _n_c[i:i + 1500])
    return float(m.group(1)) if m else None


must_contain(_n_cfg, "\tEnabled = true,", "CLAUDE-BUD J17: live for all (no owner gate)")
must_not_contain(_n_cfg, "IsPlaytestOwner", "CLAUDE-BUD J17: no owner gate")
_oa = _n_rgb("OutdoorAmbient")
(ok if _oa and all(abs(a - b) <= 15 for a, b in zip(_oa, (90, 95, 120))) else bad)(f"CLAUDE-BUD J17: midnight OutdoorAmbient ~ (90, 95, 120): {_oa}")
_am = _n_rgb("Ambient")
(ok if _am and min(_am) >= 70 else bad)(f"CLAUDE-BUD J17: midnight Ambient raised (>= 70 each): {_am}")
_br = _n_num("Night", "Brightness")
(ok if _br is not None and _br >= 1.8 else bad)(f"CLAUDE-BUD J17: night Brightness floor >= 1.8 ({_br})")
_ccb, _ccc = _n_num("ColorCorrection", "Brightness"), _n_num("ColorCorrection", "Contrast")
(ok if _ccb == 0.05 and _ccc == 0.1 else bad)(f"CLAUDE-BUD J17: moonlit colour correction Brightness +0.05, Contrast +0.1 ({_ccb}, {_ccc})")
_tint = _n_rgb("Tint")
(ok if _tint and _tint[2] >= _tint[0] and _tint[2] > 240 else bad)(f"CLAUDE-BUD J17: slight blue tint {_tint}")
# night share of the cycle: full night + half of each ramp
_ne, _de, _ds, _ns = (_n_num("Cycle", k) for k in ("NightEnd", "DawnEnd", "DuskStart", "NightStart"))
if None not in (_ne, _de, _ds, _ns):
    _share = ((24 - _ns) + _ne + (_de - _ne) / 2 + (_ns - _ds) / 2) / 24
    (ok if 0.35 <= _share <= 0.45 else bad)(f"CLAUDE-BUD J17: night ~40 % of the cycle ({_share:.1%})")
else:
    bad("CLAUDE-BUD J17: Cycle hours missing")
must_contain(_n_wa, "n = LightingConfig.Night -- claude-bud JOB 17: moody but readable (no black phones)", "CLAUDE-BUD J17: the day loop uses the new night")
must_contain(_n_wa, '{ "C", "CCTint", "TintColor" },', "CLAUDE-BUD J17: the colour correction is written by the day loop (only on change)")
must_contain(_n_wa, 'e.Name = name', "CLAUDE-BUD J17: one WE_NightCC effect")

# lights: budget, shadows, ranges
_ml = _n_num("MaxLights", "MaxLights") if False else (float(re.search(r"MaxLights = (\d+)", _n_c).group(1)) if re.search(r"MaxLights = (\d+)", _n_c) else None)
(ok if _ml is not None and _ml <= 120 else bad)(f"CLAUDE-BUD J17: at most ~120 lights ({_ml})")
must_contain(_n_nl, "if lightCount >= L.MaxLights then", "CLAUDE-BUD J17: the light budget is enforced at build")
must_contain(_n_nl, "light.Shadows = false", "CLAUDE-BUD J17: Shadows off on every light")
must_not_contain(_n_nl, "Shadows = true", "CLAUDE-BUD J17: never a shadow-casting light")
must_not_contain(_n_nl, "CanCollide = true", "CLAUDE-BUD J17: nothing collides (roads / plaza / plots stay clear)")
must_contain(_n_nl, "p.CastShadow = false", "CLAUDE-BUD J17: props cast no shadows")
for _k in ("Street", "PlazaRing", "TownSquare", "Base"):
    for _r in re.findall(r"(?:Range|GateRange|HangarRange) = (\d+)", _n_c[_n_c.find("\t" + _k + " = {"):_n_c.find("\t" + _k + " = {") + 900]):
        (ok if 40 <= int(_r) <= 60 else bad)(f"CLAUDE-BUD J17: {_k} light range {_r} in 40-60")
# static light count: town streets (2 per step outside the plaza skip) + ring + square + 3 per base + the flag
_th, _sp, _sk = _n_num("Street", "TownHalf"), _n_num("Street", "Spacing"), _n_num("Street", "SkipNearPlaza")
_ring = _n_num("PlazaRing", "Count")
if None not in (_th, _sp, _sk, _ring):
    _steps = [t for t in range(int(-_th), int(_th) + 1, int(_sp)) if abs(t) >= _sk]
    _est = 2 * len(_steps) + _ring + 3 + 3 * 6 + 1
    (ok if _est <= (_ml or 0) else bad)(f"CLAUDE-BUD J17: planned lights {int(_est)} <= MaxLights {_ml}")
must_contain(_n_nl, "light:SetAttribute(L.LowOffAttribute, true) -- the client's low-quality mode keeps every second light off", "CLAUDE-BUD J17: every second light marked for low quality")
must_contain(_n_qg, "if d:IsA(\"Light\") and d:GetAttribute(LC.LowOffAttribute) == true then", "CLAUDE-BUD J17: low quality halves the night lights (client)")
must_contain(_n_nl, "CollectionService:AddTag(p, L.GlowTag)", "CLAUDE-BUD J17: glow parts are Neon only at night (tagged)")
must_contain(_n_wa, "inst.Material = Enum.Material.Neon", "CLAUDE-BUD J17: the day loop flips the glow")
must_contain(_n_nl, "if r and r.Normal:Dot(front) > 0.9 then", "CLAUDE-BUD J17: windows sit on the real front walls (raycast)")
must_contain(_n_nl, "local a = math.rad(15 + k * (360 / P.Count)) -- never on the roads through the plaza (0 / 90 / 180 / 270)", "CLAUDE-BUD J17: plaza lamps off the roads")
_off = _n_num("Street", "Offset")
(ok if _off is not None and _off > 12 else bad)(f"CLAUDE-BUD J17: street posts outside the 12-stud road corridor ({_off})")
must_contain("src/ServerScriptService/Server/Modules/MapDressing.luau", 'local nl = getWorldModule("NightLights")', "CLAUDE-BUD J17: built with the world dressing (pcall)")
_mw = read("src/ReplicatedStorage/Shared/Configs/WindowsDummy.luau") if False else None
_wmax = _n_num("Windows", "MaxPerBuilding")
(ok if _wmax is not None and _wmax * 58 * 0.6 + 6 * 22 < 600 else bad)(f"CLAUDE-BUD J17: night Neon stays well inside the 986 hard cap (~{int((_wmax or 0) * 58 * 0.6 + 6 * 22)} glow parts)")
