# Code Bot Roblox v139 (2026-09-30): ship claude-bud JOB 36 shop overhaul
# (OwnerFirst=true; WarChest/SuperSoldiers/DoubleHP Id 0). PreferMesh OFF. WE_Building* untouched.
# Fast travel stays REMOVED. Aircraft weapons stay live for everyone (v138). Premium guns stay live (v136/v137).
from pathlib import Path as _P139


def _cb139(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


def _rd139(p):
    q = _P139(p)
    return q.read_text(encoding="utf-8") if q.is_file() else ""


_S139 = "src/ServerScriptService/Server/"
_C139 = "src/ReplicatedStorage/Shared/Configs/"
for _f in (_S139 + "Services/DataService.luau", _S139 + "Services/BaseService.luau", _S139 + "EarlyRemotes.server.luau"):
    _cb139('SetAttribute("WE_Build", 139)' in _rd139(_f), "CODEBOT v139: WE_Build=139 " + _f.rsplit("/", 1)[-1])
_cb139("WE_Build=139" in _rd139(_S139 + "Services/DataService.luau"), "CODEBOT v139: DataService profile-loaded log says WE_Build=139")

_SOC = _rd139(_C139 + "ShopOverhaulConfig.luau")
_cb139("Enabled = true" in _SOC and "OwnerFirst = true" in _SOC, "CODEBOT v139: ShopOverhaulConfig Live Enabled + OwnerFirst=true")
_cb139(_P139(_S139 + "Services/ShopOverhaulService.luau").is_file(), "CODEBOT v139: ShopOverhaulService present")
_cb139(_P139("docs/SHOP.md").is_file(), "CODEBOT v139: docs/SHOP.md present")

_MON = _rd139(_C139 + "MonetizationConfig.luau")
for _k, _price in (("WarChest", 799), ("SuperSoldiers", 349), ("DoubleHP", 199)):
    _cb139((_k + " = {") in _MON, "CODEBOT v139: MonetizationConfig has " + _k)
    # Id 0 block nearby
    import re as _re139
    m = _re139.search(rf"{_k}\s*=\s*\{{[^}}]*?Id\s*=\s*(\d+)", _MON, _re139.S)
    _cb139(m is not None and m.group(1) == "0", "CODEBOT v139: " + _k + " Id = 0 (hidden until owner pastes)")
    m2 = _re139.search(rf"{_k}\s*=\s*\{{[^}}]*?RobuxPrice\s*=\s*(\d+)", _MON, _re139.S)
    _cb139(m2 is not None and int(m2.group(1)) == _price, "CODEBOT v139: " + _k + " RobuxPrice=" + str(_price))

_cb139("OverhaulRobuxPrice = 349" in _MON, "CODEBOT v139: VIP OverhaulRobuxPrice = 349")
_cb139("WeaponsLive = true" in _rd139(_C139 + "AircraftWeaponConfig.luau"), "CODEBOT v139: aircraft weapons stay live (v138)")
_cb139("OwnerFirst = false" in _rd139(_C139 + "PremiumGunsConfig.luau") and "Enabled = true" in _rd139(_C139 + "PremiumGunsConfig.luau"),
       "CODEBOT v139: PremiumGuns stay live for everyone (v136)")
_cb139("PreferMeshWhenAssetIdSet = false" in _rd139(_C139 + "StructureVisualConfig.luau"), "CODEBOT v139: PreferMesh stays OFF")
_cb139("FastTravelEnabled = false" in _rd139(_C139 + "MapConfig.luau"), "CODEBOT v139: fast travel stays REMOVED")
