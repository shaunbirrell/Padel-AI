# Code Bot v89 (2026-09-28): the wc7 winners as owner-only store bodies (capital ships + the 4-engine airlifter). Runs
# inside tools/BuyPathStatic.py (its globals). Helper names start with _cb89_. Supersedes the frozen v42 Destroyer /
# Cruiser "W1 CFG drop" pins (retired in this commit) and the v88 capital-ship NoFamilyFallback pins.
_cb89_vac = "src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau"
_cb89_src = read(_cb89_vac) or ""
def _cb89_table(name):
    i = _cb89_src.find(f"local {name} = {{\n")
    j = _cb89_src.find("\n}\n", i)
    return _cb89_src[i:j] if i >= 0 and j > i else ""
_cb89_map = {
    "BODY_DESTROYER": ("6860896505", "180", "0.2", "2.5", ("Destroyer",)),
    "BODY_CRUISER": ("6860896505", "180", "0.22", "2.8", ("Cruiser",)),
    "BODY_MISSILE_CRUISER": ("104820847233642", "0", "18", "4.3", ("MissileCruiser",)),
    "BODY_BATTLESHIP": ("12442299148", "0", "2.0", "4.0", ("Battleship",)),
    "BODY_AIRLIFTER": ("10649792198", "-90", "2.1", None, ("CargoPlane", "AWACSPlane", "TankerPlane")),
}
for _cb89_tb, (_cb89_id, _cb89_yaw, _cb89_s, _cb89_w, _cb89_keys) in _cb89_map.items():
    _cb89_body = _cb89_table(_cb89_tb)
    _cb89_need = [f"\tModelAssetId = {_cb89_id},\n", '\tRollout = "Body",\n', '\tFit = "Kit",\n', f"\tYaw = {_cb89_yaw},\n", "\tHideKit = true,\n",
                  f"\tBodyScale = {_cb89_s},\n", "\t\tDriverSeat = Vector3.new(", '\tBodyAnchor = "DriverSeat",\n', "\tBodyMaterial = Enum.Material.Metal,\n", "\tStripDecals = true,"]
    if _cb89_w:
        _cb89_need += [f"\tBodyWaterline = {_cb89_w},\n", "\tBodyColor = Color3.fromRGB(58, 62, 68),", "\t\tTurretF = Vector3.new(", "\t\tBarrelF = Vector3.new(", "\t\tTurretA = Vector3.new("]
    else:
        _cb89_need += ["\tBodyColor = Color3.fromRGB(70, 74, 80),", '\tBodyFloor = "Collide",\n']
    _cb89_miss = [n for n in _cb89_need if n not in _cb89_body]
    if _cb89_miss:
        bad(f"CODEBOT v89: {_cb89_tb} ({_cb89_id}) owner-only fitted body, yaw / scale / recolour / seats / mounts — missing {_cb89_miss}")
    else:
        ok(f"CODEBOT v89: {_cb89_tb} ({_cb89_id}) owner-only fitted body, Yaw {_cb89_yaw}, scale {_cb89_s}, dark recolour, seats / mounts")
    for _cb89_k in _cb89_keys:
        must_contain(_cb89_vac, f"\t\t{_cb89_k} = bodyRef({_cb89_tb}, \"v89 owner pick {_cb89_id} ", f"CODEBOT v89: Vehicles.{_cb89_k} wears {_cb89_tb} ({_cb89_id}), owner-only")
must_not_contain(_cb89_vac, "ModelAssetId = 17033079003", "CODEBOT v89: the airliner 17033079003 is replaced by the airlifter 10649792198")
must_contain(_cb89_vac, '\t\tStrikeJet = bodyRef(BODY_STRIKE_JET, "v88 owner pick 3553891209 ', "CODEBOT v89: StrikeJet stays on 3553891209")
if "\tBodyMaxScale = 18," in _cb89_table("BODY_MISSILE_CRUISER") and _cb89_src.count("BodyMaxScale = ") == 1:
    ok("CODEBOT v89: only the missile destroyer raises the scale cap (BodyMaxScale 18)")
else:
    bad("CODEBOT v89: only the missile destroyer raises the scale cap (BodyMaxScale 18)")
# no capital ship keeps the Part kit or the v88 exclusion
import re as _cb89_re
for _cb89_k in ("Destroyer", "Cruiser", "MissileCruiser", "Battleship"):
    if _cb89_re.search(r"\n\t\t" + _cb89_k + r" = \{ ModelAssetId = 0,", _cb89_src):
        bad(f"CODEBOT v89: Vehicles.{_cb89_k} still on the Part kit")
    else:
        ok(f"CODEBOT v89: Vehicles.{_cb89_k} is off the Part kit (own body)")
