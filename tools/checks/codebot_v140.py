# Code Bot Roblox v140 (2026-09-30): wire the JOB 36 game pass Ids created on the Creator Hub (universe 10767159222):
# War Chest 2002640637 (799 R$), Super Soldiers 1998231741 (349 R$), Double HP 2002214665 (199 R$). Verified via
# apis.roblox.com game-passes v1 (universe listing + product-info): on sale, prices match. ShopOverhaul stays
# OwnerFirst=true. VIP price unchanged. PreferMesh OFF. WE_Building* untouched. Fast travel stays REMOVED.
import re as _re140
from pathlib import Path as _P140


def _cb140(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


def _rd140(p):
    q = _P140(p)
    return q.read_text(encoding="utf-8") if q.is_file() else ""


_S140 = "src/ServerScriptService/Server/"
_C140 = "src/ReplicatedStorage/Shared/Configs/"
# v141 (Code Bot Roblox): the WE_Build=140 pins are superseded in tools/checks/codebot_v141.py (WE_Build=141).

_SOC = _rd140(_C140 + "ShopOverhaulConfig.luau")
_cb140("Enabled = true" in _SOC and "OwnerFirst = true" in _SOC, "CODEBOT v140: ShopOverhaulConfig stays Enabled + OwnerFirst=true")

_MON = _rd140(_C140 + "MonetizationConfig.luau")
for _k, _id, _price in (("WarChest", 2002640637, 799), ("SuperSoldiers", 1998231741, 349), ("DoubleHP", 2002214665, 199)):
    m = _re140.search(rf"\t\t{_k}\s*=\s*\{{[^}}]*?Id\s*=\s*(\d+)", _MON, _re140.S)
    _cb140(m is not None and int(m.group(1)) == _id, "CODEBOT v140: " + _k + " Id = " + str(_id))
    m2 = _re140.search(rf"\t\t{_k}\s*=\s*\{{[^}}]*?RobuxPrice\s*=\s*(\d+)", _MON, _re140.S)
    _cb140(m2 is not None and int(m2.group(1)) == _price, "CODEBOT v140: " + _k + " RobuxPrice=" + str(_price))
_cb140("\t\tVIP = {\n\t\t\tId = 1985475542,\n\t\t\tDisplayName = \"VIP\",\n\t\t\tRobuxPrice = 199," in _MON
       and "OverhaulRobuxPrice = 349," in _MON, "CODEBOT v140: VIP Id/price unchanged (199; overhaul 349)")
_cb140("2002640637" in _rd140("docs/SHOP.md") and "1998231741" in _rd140("docs/SHOP.md") and "2002214665" in _rd140("docs/SHOP.md"),
       "CODEBOT v140: docs/SHOP.md lists the three new pass Ids")
_cb140("WeaponsLive = true" in _rd140(_C140 + "AircraftWeaponConfig.luau"), "CODEBOT v140: aircraft weapons stay live")
_cb140("OwnerFirst = false" in _rd140(_C140 + "PremiumGunsConfig.luau") and "Enabled = true" in _rd140(_C140 + "PremiumGunsConfig.luau"),
       "CODEBOT v140: PremiumGuns stay live for everyone")
_cb140("PreferMeshWhenAssetIdSet = false" in _rd140(_C140 + "StructureVisualConfig.luau"), "CODEBOT v140: PreferMesh stays OFF")
_cb140("FastTravelEnabled = false" in _rd140(_C140 + "MapConfig.luau"), "CODEBOT v140: fast travel stays REMOVED")

# ── owner bugs on v139 (root-cause fixes, folded into v140) ──
_SCC = _rd140("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau")
_cb140("list.CanvasPosition = Vector2.new(0, rowCanvasY(list, row))" in _SCC and 'row:SetAttribute("WE_RowH", rowH)' in _SCC
       and "list.CanvasPosition = Vector2.new(0, 0)" not in _SCC,
       "CODEBOT v140: the cash + scrolls to the Cash Pack Mega row (packs sit after the passes in the JOB 36 order)")
_CSV = _rd140(_S140 + "Services/CombatService/init.luau")
_cb140("counts.Regular >= cap" in _CSV and "aliveNPCCount()" not in _CSV,
       "CODEBOT v140: regular NPC spawns count Regular (not OverCap defenders) against MaxActiveNPCs")
_SAS = _rd140(_S140 + "Services/SiteActivityService.luau")
_cb140("Too many enemies around" not in _SAS and "OverCap" not in _SAS,
       "CODEBOT v140: AreaBusy copy no longer claims enemies nearby; activity NPCs keep normal slots (JOB 31 rule)")
_cb140(_P140("tools/sim/run_shop_render_test.py").is_file(), "CODEBOT v140: the Shop render test exists")
_cb140("3972151362" in _rd140(_C140 + "HudConfig.luau"), "CODEBOT v140: RPG launcher hold = RifleHold 3972151362 (cherry 6c770b4)")
