# Code Bot Roblox v137 (2026-09-30): wire the seven Creator Hub armory game passes.
# Prices stay in MonetizationConfig; the PG_* keys are intentionally outside RolloutKeys,
# so the live armory / Shop gold rows use the pass Id directly. PreferMesh OFF; no fast travel.
from pathlib import Path as _P137


def _cb137(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


def _rd137(p):
    q = _P137(p)
    return q.read_text(encoding="utf-8") if q.is_file() else ""


_S137 = "src/ServerScriptService/Server/"
_C137 = "src/ReplicatedStorage/Shared/Configs/"
for _f in (_S137 + "Services/DataService.luau", _S137 + "Services/BaseService.luau", _S137 + "EarlyRemotes.server.luau"):
    _cb137('SetAttribute("WE_Build", 137)' in _rd137(_f), "CODEBOT v137: WE_Build=137 " + _f.rsplit("/", 1)[-1])
_cb137("WE_Build=137" in _rd137(_S137 + "Services/DataService.luau"), "CODEBOT v137: DataService profile-loaded log says WE_Build=137")

_MON137 = _rd137(_C137 + "MonetizationConfig.luau")
_PASSES137 = {
    "PG_Sovereign": (2002154652, 99),
    "PG_Quake": (2003492417, 249),
    "PG_Longshot": (2003180431, 299),
    "PG_Havoc": (2002250646, 349),
    "PG_Thunderhead": (1999305818, 399),
    "PG_Tempest": (2002682646, 499),
    "PG_ArmoryPass": (2002868467, 1299),
}
for _k137, (_id137, _price137) in _PASSES137.items():
    _needle137 = "\t\t" + _k137 + " = {"
    _blk137 = _MON137.split(_needle137, 1)[1].split("\n\t\t},", 1)[0] if _needle137 in _MON137 else ""
    _cb137(("Id = %d," % _id137) in _blk137, "CODEBOT v137: %s Id=%d" % (_k137, _id137))
    _cb137(("RobuxPrice = %d," % _price137) in _blk137, "CODEBOT v137: %s price R$ %d unchanged" % (_k137, _price137))

_ROLLOUT137 = _MON137.split("\tRolloutKeys = ", 1)[1].split("\n", 1)[0] if "\tRolloutKeys = " in _MON137 else ""
for _k137 in _PASSES137:
    _cb137(_k137 not in _ROLLOUT137, "CODEBOT v137: %s stays outside RolloutKeys (live armory path)" % _k137)

_PG137 = _rd137(_C137 + "PremiumGunsConfig.luau")
_PGS137 = _rd137(_S137 + "Services/PremiumGunService.luau")
_SHOP137 = _rd137("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau")
_cb137("OwnerFirst = false" in _PG137, "CODEBOT v137: premium armory remains live for everyone")
_cb137("(tonumber(premiumPass.Id) or 0) ~= 0 and PremiumGunsConfig.LiveFor" in _SHOP137, "CODEBOT v137: Shop gold rows require a live pass Id")
_cb137('return "Buy", ROBUX .. " " .. tostring(price), PremiumGunService.BuyText(price)' in _PGS137, "CODEBOT v137: live armory cases show Buy and the configured price")
_cb137("PreferMeshWhenAssetIdSet = false" in _rd137(_C137 + "StructureVisualConfig.luau"), "CODEBOT v137: PreferMesh stays OFF")
_cb137("FastTravelEnabled = false" in _rd137(_C137 + "MapConfig.luau"), "CODEBOT v137: fast travel stays REMOVED")
