# claude-bud JOB 36 (2026-09-30): the SHOP OVERHAUL, owner-first (ShopOverhaulConfig.Live): order + PERMANENT + BEST
# VALUE, scaling cash packs (ProcessReceipt), duplicates (Speed Pass / Army Expansion out; Speed Boost / Bigger Army
# sold), premium VIP (+50 %, daily crate, gold name), War Chest / Super Soldiers / Double HP (Id 0), docs/SHOP.md.
# Static pins + the real-code test (tools/sim/run_shop_test.py).
import os as _j36_os
import subprocess as _j36_sp
import sys as _j36_sys
from pathlib import Path as _J36P

if "ok" not in globals():
    _j36_fails = []

    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        _j36_fails.append(msg)
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _J36P(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None


def _j36(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J36: " + msg)


def _j36_src(path):
    return (read(path) or "").replace("\r\n", "\n")


def _j36_code(path):
    return "\n".join(l.split("--", 1)[0] for l in _j36_src(path).splitlines())


_SV = "src/ServerScriptService/Server/"
_CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
_SOC = _j36_src("src/ReplicatedStorage/Shared/Configs/ShopOverhaulConfig.luau")
_MCF = _j36_src("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau")
_MS = _j36_code(_SV + "Services/MonetizationService.luau")
_SOS = _j36_code(_SV + "Services/ShopOverhaulService.luau")
_SC = _j36_code(_CL + "Controllers/ShopController.luau")
_SQ = _j36_code(_SV + "Services/SquadOrdersService.luau")
_AR = _j36_code(_SV + "Services/ArmourService.luau")

_j36("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = false, -- codebot_v142 launch" in _SOC and "RetentionConfig.Live(ShopOverhaulConfig.Live, userId)" in _SOC,
     "one kill switch (ShopOverhaulConfig.Live; v142: OwnerFirst=false, everyone; superseded in codebot_v142.py)")
# new passes: real Creator Hub Ids (codebot_v140, universe 10767159222); no live Id or price changed
for _k, _id, _p in (("WarChest", 2002640637, 799), ("SuperSoldiers", 1998231741, 349), ("DoubleHP", 2002214665, 199)):
    _j36(("\t\t%s = {\n\t\t\tId = %d,\n" % (_k, _id)) in _MCF and ("RobuxPrice = %d," % _p) in _MCF, "%s: Id %d, R$ %d" % (_k, _id, _p))
_j36("\t\tVIP = {\n\t\t\tId = 1985475542,\n\t\t\tDisplayName = \"VIP\",\n\t\t\tRobuxPrice = 199," in _MCF and "OverhaulRobuxPrice = 199," in _MCF,
     "VIP: the Shop shows the real Creator Hub price 199 (v142: owner has not approved 349; superseded in codebot_v142.py)")
for _k, _id in (("CashSmall", 3713838744), ("CashMedium", 3713838815), ("CashLarge", 3713838888), ("CashMega", 3713838952)):
    _j36(("%s = { Id = %d," % (_k, _id)) in _MCF, "%s keeps its Id %d" % (_k, _id))
# cash packs in ProcessReceipt, before any mutation
_j36("cashGrant = nonNegInt(ShopOverhaulConfig.CashPackAmount(productKey :: string, perMin))" in _MS and "return math.max(p.Floor, math.floor(p.Minutes * rate))" in _SOC,
     "cash packs pay max(Floor, Minutes x passive $/min), computed in ProcessReceipt")
# War Chest implies
_j36("for _, implied in ipairs(impliedPasses(player, passKey)) do" in _MS and _MS.count("impliedPasses(player, passKey)") == 2
     and "Implies = { \"DoubleCash\", \"AutoCollect\", \"VIP\", \"BiggerArmy\" }," in _MCF, "War Chest counts as owning its four passes (join check + purchase)")
# VIP
_j36("bonus = tonumber(ShopOverhaulConfig.Vip.CashBonusMult) or bonus" in _MS and "CashBonusMult = 0.5," in _SOC, "VIP +50 % Cash while live")
_j36('deps.EconomyService.AddCash(player, amount, "vip_supply")' in _SOS and "vip_supply = true," in _MCF and "profile.VipSupplyAt = os.time()" in _SOS,
     "the daily VIP supply crate (saved VipSupplyAt, multiplier-exempt)")
_j36('player:SetAttribute("WE_VIPGold", if gold then true else nil)' in _MS and 'sender:GetAttribute("WE_VIPGold") == true' in _j36_code(_CL + "Controllers/FeatureController.luau"),
     "the premium VIP's gold chat name")
# duplicates
_j36("return deathSpeedProductOffer(victim, cfg, ShopOverhaulConfig.DeathOfferProduct)" in _MS and 'DeathOfferProduct = "SpeedBoost",' in _SOC, "the death offer sells Speed Boost while live")
_j36('ShopOverhaulConfig.ArmyWipedPass, "Army down! Bigger Army: +10 soldiers"' in _MS, "the army-wiped offer sells Bigger Army while live")
_j36('PurchaseStands.Retarget(top, "DevProduct", ShopOverhaulConfig.SpeedStandProduct)' in _SOS, "the base Speed stand sells Speed Boost for a live owner")
_j36("overhaul and ShopOverhaulConfig.HideWhenLive[key] == true" in _SC and "HideWhenLive = { ImpulseSpeed = true, ExtraSoldierSlot = true }" in _SOC,
     "Speed Pass and Army Expansion leave the Shop (owners keep them: SpeedMultFor / the army cap unchanged)")
# shop order / labels
_j36("r.Row.LayoutOrder = ShopOverhaulConfig.Rank(r.Row.Name) * 1000 + r.Row.LayoutOrder" in _SC and "passSub = ShopOverhaulConfig.PermanentPrefix" in _SC
     and "passTitle = ShopOverhaulConfig.BestValueLabel" in _SC, "Shop order, PERMANENT passes, BEST VALUE on 2x Cash")
# Code Bot v156: the pack rows read "Get $X cash right away" (cashPackText, still packCash's live amount)
_j36("r.Sub.Text = cashPackText(r.Key, def)" in _SC and "return \"Get $\" .. s .. \" cash right away\"" in _SC and "local n = math.floor(packCash(key, def))" in _SC and "local cashAmount = packCash(\"CashMega\", def)" in _SC,
     "Shop rows and the Mega offer show the live pack amount")
# perks
_j36("return math.clamp(tonumber(b.Mult) or 1, 1, 2) * superMult(player)" in _SQ and "* superMult(owner) + 0.5" in _SQ and "* superMult(player) + 0.5" in _SQ,
     "Super Soldiers: army damage (every site via armyBoostMult) and soldier HP x1.25")
_j36("local mx = math.floor(ArmourService.MaxHealthFor(tier) * hpMult + 0.5)" in _AR and 'player:GetAttribute("WE_PerkDoubleHP") == true' in _AR,
     "Double HP doubles the base MaxHealth (armour on top)")
_j36('player:SetAttribute("WE_PerkDoubleHP", if hp then true else nil)' in _SOS and "local hp = on and ownsPass(player, ShopOverhaulConfig.DoubleHP.PassKey)" in _SOS,
     "perk attributes are server-set from pass ownership while live")
_j36(_j36_src("docs/SHOP.md").count("| `") >= 40, "docs/SHOP.md lists every item (key, name, price, Id, grant, where)")

_luau = _j36_os.environ.get("LUAU")
if _luau is None and _j36_os.environ.get("LUAU_COMPILE"):
    _cand = _j36_os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    _luau = _cand if _j36_os.path.isfile(_cand) else None
if _luau:
    _r = _j36_sp.run([_j36_sys.executable, "tools/sim/run_shop_test.py"], capture_output=True, text=True, env=dict(_j36_os.environ, LUAU=_luau))
    _j36(_r.returncode == 0 and "SHOP TEST: 0 failed" in _r.stdout, "run_shop_test.py (real config / service / stands; receipt order)")
else:
    print("SKIP CLAUDE-BUD J36: Luau CLI test (set LUAU)")
