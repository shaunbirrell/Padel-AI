# Code Bot v88 (2026-09-28): the wc6 winners as owner-only store bodies (same system as v87). Runs inside
# tools/BuyPathStatic.py (its globals). Helper names start with _cb88_. Supersedes the frozen pins retired in this commit
# (v41 / v42 LandingCraft = 0, AIRLOOKS "along the kit only", AIR2 strike-jet family on the Part kit) and the v87 kit list.
_cb88_vac = "src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau"
_cb88_rig = "src/ServerScriptService/Server/Modules/AirBodyRig.luau"
_cb88_map = {
    "BODY_VTOL": ("80886282228822", ("VTOLTransport",)),
    "BODY_ATTACK_HELI": ("11240665977", ("AttackHelicopter",)),  # v91: Gunship / Escort / NightAttack -> heliRef (codebot_v91.py)
    "BODY_STEALTH_HELI": ("11240665977", ("StealthHeli",)),
    # v90 (Code Bot): StrikeJet / CASJet / StealthStrike / StealthStrikeJet moved to the jet 14589101870 (owner answer 1,
    # pinned in codebot_v90.py); the two v88 tables stay defined (unused) for an easy revert
    "BODY_STRIKE_JET": ("3553891209", ()),
    "BODY_STEALTH_STRIKE": ("7976374439", ()),
    "BODY_BARGE": ("12235335847", ("LandingCraft", "AssaultLanding")),
    "BODY_SUPPORT_SHIP": ("2625253037", ("HospitalShip", "SupplyShip")),
    "BODY_HOVER": ("3626114334", ("HoverTransport",)),
}
_cb88_src = read(_cb88_vac) or ""
def _cb88_table(name):
    i = _cb88_src.find(f"local {name} = {{\n")
    j = _cb88_src.find("\n}\n", i)
    return _cb88_src[i:j] if i >= 0 and j > i else ""
for _cb88_tb, (_cb88_id, _cb88_keys) in _cb88_map.items():
    _cb88_body = _cb88_table(_cb88_tb)
    _cb88_miss = [n for n in (f"\tModelAssetId = {_cb88_id},\n", '\tRollout = "Body",\n', '\tFit = "Kit",\n', "\tHideKit = true,\n", "\t\tDriverSeat = Vector3.new(", '\tBodyAnchor = "DriverSeat",\n', "\tStripDecals = true,") if n not in _cb88_body]
    if _cb88_miss:
        bad(f"CODEBOT v88: {_cb88_tb} ({_cb88_id}) is an owner-only fitted body — missing {_cb88_miss}")
    else:
        ok(f"CODEBOT v88: {_cb88_tb} ({_cb88_id}) is an owner-only fitted body (Rollout Body, Fit Kit, HideKit, seats, anchor)")
    for _cb88_k in _cb88_keys:
        must_contain(_cb88_vac, f"\t\t{_cb88_k} = bodyRef({_cb88_tb}, \"v88 owner pick {_cb88_id} ", f"CODEBOT v88: Vehicles.{_cb88_k} wears {_cb88_tb} ({_cb88_id}), owner-only")
must_not_contain(_cb88_vac, "ModelAssetId = 2475398012", "CODEBOT v88: the prop transport 2475398012 is gone everywhere")
must_not_contain(_cb88_vac, "ModelAssetId = 11839207737", "CODEBOT v88: the Little Bird look-alike 11839207737 is never wired (StealthHeli = the attack-heli body, near-black)")
must_contain(_cb88_vac, "\tBodyColor = Color3.fromRGB(20, 22, 26), -- near-black", "CODEBOT v88: StealthHeli is recoloured near-black")
for _cb88_need, _cb88_label in (
    ('\tOmitParts = { "Part" },', "the strike jet drops its 24 gear Parts"),
    ("\tBodyClearTexture = true,", "the strike jet's texture is cleared (dark recolour)"),
):
    if _cb88_need in _cb88_table("BODY_STRIKE_JET"):
        ok(f"CODEBOT v88: {_cb88_label}")
    else:
        bad(f"CODEBOT v88: {_cb88_label} — missing `{_cb88_need}` in BODY_STRIKE_JET")
if '"Meshes/bargepiece12_Cylinder.051", "Meshes/bargepiece12_Cube.130", "Meshes/bargepiece12_Cylinder.080"' in _cb88_table("BODY_BARGE"):
    ok("CODEBOT v88: the barge drops its hanging anchor and chain")
else:
    bad("CODEBOT v88: the barge drops its hanging anchor and chain — OmitParts missing in BODY_BARGE")
# v89: the airliner (and its BodyMaxScale 30) is replaced by the airlifter; the cap pins are in codebot_v89.py
_cb88_rp = _cb88_table("BODY_VTOL")
if _cb88_rp.count("Axis = \"Y\", Rps = 4 }") == 2:
    ok("CODEBOT v88: both VTOL proprotors spin about their own hubs")
else:
    bad("CODEBOT v88: both VTOL proprotors spin about their own hubs")
if '{ Parts = { "Blades" }, Hub = "Thing for Blades", Axis = "Y", Rps = 5 }' in _cb88_table("BODY_ATTACK_HELI"):
    ok("CODEBOT v88: the attack heli main rotor spins")
else:
    bad("CODEBOT v88: the attack heli main rotor spins")
# v89: the capital ships now wear their own wc7 bodies (codebot_v89.py), so the v88 NoFamilyFallback exclusion is gone
# carrier / amphib: the body moves across too, so the captain sits in the island bridge
for _cb88_tb in ("BODY_CARRIER", "BODY_AMPHIB"):
    if "\tBodyAnchorX = true," in _cb88_table(_cb88_tb):
        ok(f"CODEBOT v88: {_cb88_tb} anchors across the kit (island bridge)")
    else:
        bad(f"CODEBOT v88: {_cb88_tb} anchors across the kit (island bridge)")
if _cb88_src.count("\tBodyAnchorX = true,") == 2:
    ok("CODEBOT v88: only the carrier and amphib anchor across (every other body stays centred)")
else:
    bad("CODEBOT v88: only the carrier and amphib anchor across (every other body stays centred)")
must_contain(_cb88_rig, "\tlocal dx = if ref.BodyAnchorX == true then k.X - v.X else 0\n\treturn Vector3.new(dx, 0, k.Z - v.Z)", "CODEBOT v88: BodyAnchor moves the body along the kit, and across only with BodyAnchorX")
must_contain(_cb88_rig, "\tlocal cap = if typeof(ref.BodyMaxScale) == \"number\" then math.clamp(ref.BodyMaxScale, 4, 40) else 4\n\treturn math.clamp(raw, floor, cap)", "CODEBOT v88: ClampScale cap 4 unless BodyMaxScale (never over 40)")
