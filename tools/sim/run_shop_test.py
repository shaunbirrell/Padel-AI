"""claude-bud JOB 36: real-code tests in the Luau CLI for the shop overhaul (stand-ins: run_kit_detail_test.PRELUDE).

1. ORDER (the real ShopOverhaulConfig.Rank on the real Shop row names): FREE -> War Chest -> 2x Cash -> VIP -> Auto
   Collect -> Starter Pack -> BP Premium -> Bigger Army -> Super Soldiers -> Double HP -> Speed Boost -> armory guns ->
   premium vehicles -> cash packs -> consumables.
2. CASH PACKS: max(Floor, Minutes x $/min) for S / M / L / Mega, floors for new players, NaN / negative safe; the pack
   Ids and prices unchanged.
3. VIP CRATE (the real ShopOverhaulService on stubs): paid once per SupplyEveryHours, ~10 min of income with a floor,
   reason "vip_supply" (multiplier-exempt), only while live and only for VIP owners.
4. PERKS: SyncPerks sets WE_PerkDoubleHP / WE_PerkSuperSoldiers from ownership only while live.
5. SPEED STAND (the real ShopOverhaulService + PurchaseStands.Retarget): a live owner's Speed stand sells Speed Boost
   (attributes, price chip, prompt), back to the config offer when he leaves.
6. CONFIG: the three new passes at their Creator Hub Ids (v140) with their prices; War Chest implies the four; VIP shown at the real
   Creator Hub price 199 (codebot_v142: OverhaulRobuxPrice = 199; the owner has not approved 349); vip_supply exempt.
7. RECEIPT ORDER (static, MonetizationService): the pack lookup comes before the first grant mutation and re-checks the
   player / profile after it.
8. RENDER (codebot_v140, run_shop_render_test.py): the real ShopController rows (cash packs render; the cash + scrolls
   to the Mega row; the new passes owner-first).
Run: LUAU=path/to/luau(.exe) python tools/sim/run_shop_test.py   (exit 1 on any failure)"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_kit_detail_test import PRELUDE  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SH = ROOT / "src/ReplicatedStorage/Shared"
SV = ROOT / "src/ServerScriptService/Server"
MODS = {
    "Constants": SH / "Constants.luau",
    "Configs/ShopOverhaulConfig": SH / "Configs/ShopOverhaulConfig.luau",
    "Configs/MonetizationConfig": SH / "Configs/MonetizationConfig.luau",
    "Util/LivePrices": SH / "Util/LivePrices.luau",  # Code Bot v156: the real Roblox price / name (config fallback here)
    "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
    "Modules/PurchaseStands": SV / "Modules/PurchaseStands.luau",
    "Services/ShopOverhaulService": SV / "Services/ShopOverhaulService.luau",
}

EXTRA = r'''
task = { spawn = function() end, wait = function() end, delay = function() end, defer = function(fn, ...) fn(...) end }
utf8 = { char = function() return "R$" end }
local function signal() local s = { fns = {} }; s.Connect = function(self, fn) table.insert(self.fns, fn); return { Disconnect = function() end } end; s.Fire = function(self, ...) for _, f in ipairs(self.fns) do f(...) end end; return s end
local Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end }
local RunService = { IsStudio = function() return false end }
TAGGED = {}
local CollectionService = { GetTagged = function() return TAGGED end, AddTag = function() end }
local prevGame = game
game = { GetService = function(_, n)
  if n == "Players" then return Players elseif n == "RunService" then return RunService elseif n == "CollectionService" then return CollectionService end
  return prevGame:GetService(n) end }
local baseIndex = INST.__index
INST.__index = function(t, k)
  if k == "FindFirstChild" then return function(s, n) for _, c in ipairs(rawget(s, "__kids") or {}) do if c.Name == n then return c end end return nil end end
  if k == "IsA" then return function(s, c) return s.ClassName == c or (c == "BasePart" and s.ClassName == "Part") or c == "Instance" end end
  return baseIndex(t, k)
end
function mkPlayer(uid)
  local p = { UserId = uid, Parent = true, attrs = {} }
  p.SetAttribute = function(self, k, v) self.attrs[k] = v end
  p.GetAttribute = function(self, k) return self.attrs[k] end
  return p
end
'''

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local SO = require(node("Configs/ShopOverhaulConfig"))
local MC = require(node("Configs/MonetizationConfig"))

-- ── 1. order ──
local shop = { "ShopRow_CashMega", "ShopRow_CashLarge", "ShopRow_CashMedium", "ShopRow_CashSmall", "ShopRow_GoldenPumpjack",
  "ShopRow_SoldierRefill", "ShopRow_PlazaAirstrike", "ShopRow_SpeedBoost", "ShopRow_StarterBundle", "ShopRow_PremiumPass",
  "ShopRow_Pass_AutoCollect", "ShopRow_Pass_DoubleXP", "ShopRow_Pass_DoubleCash", "ShopRow_Pass_ExtraGarageSlot",
  "ShopRow_Pass_PV_Razorfang", "ShopRow_Pass_VIP", "ShopRow_Pass_BiggerArmy", "ShopRow_Pass_SuperSoldiers", "ShopRow_Pass_DoubleHP",
  "ShopRow_Pass_WarChest", "ShopRow_Pass_PG_Sovereign", "ShopRow_Pass_PV_Leviathan", "ShopRow_SupplyCrate", "ShopRow_fr_daily", "ShopRow_fr_airdrop" }
local rows = {}
for i, n in ipairs(shop) do table.insert(rows, { Name = n, Order = SO.Rank(n) * 1000 + i }) end
table.sort(rows, function(a, b) return a.Order < b.Order end)
local names = {}
for _, r in ipairs(rows) do table.insert(names, (string.gsub(r.Name, "ShopRow_", ""))) end
local got = table.concat(names, " > ")
local want = "fr_daily > fr_airdrop > Pass_WarChest > Pass_DoubleCash > Pass_VIP > Pass_AutoCollect > StarterBundle > PremiumPass > Pass_BiggerArmy > Pass_SuperSoldiers > Pass_DoubleHP > SpeedBoost > Pass_DoubleXP > Pass_PG_Sovereign > Pass_PV_Razorfang > Pass_PV_Leviathan > Pass_ExtraGarageSlot > CashMega > CashLarge > CashMedium > CashSmall > GoldenPumpjack > SoldierRefill > PlazaAirstrike > SupplyCrate"
check(got == want, "shop order:\n        " .. got)

-- ── 2. cash packs ──
check(SO.CashPackAmount("CashSmall", 0) == 10000 and SO.CashPackAmount("CashMedium", 0) == 50000 and SO.CashPackAmount("CashLarge", 0) == 200000 and SO.CashPackAmount("CashMega", 0) == 2000000, "a new player gets the floors (old amounts)")
check(SO.CashPackAmount("CashSmall", 5000) == 25000 and SO.CashPackAmount("CashMedium", 5000) == 100000, "5,000 $/min: S = 5 min = $25,000, M = 20 min = $100,000")
check(SO.CashPackAmount("CashLarge", 5000) == 300000 and SO.CashPackAmount("CashMega", 5000) == 2000000, "5,000 $/min: L = 60 min = $300,000; Mega keeps its $2M floor")
check(SO.CashPackAmount("CashMega", 20000) == 3600000, "20,000 $/min: Mega = 180 min = $3.6M")
check(SO.CashPackAmount("CashSmall", 0 / 0) == 10000 and SO.CashPackAmount("CashSmall", -50) == 10000 and SO.CashPackAmount("CashSmall", math.huge) == 10000, "NaN / negative / inf rates = the floor")
check(SO.CashPackAmount("GoldSmall", 5000) == nil, "not a scaling pack -> nil")
for k, id in pairs({ CashSmall = 3713838744, CashMedium = 3713838815, CashLarge = 3713838888, CashMega = 3713838952 }) do
  check(MC.DevProducts[k].Id == id, k .. " Id unchanged")
end

-- ── 3. VIP crate ──
local S = require(node("Services/ShopOverhaulService"))
check(S.VipSupplyDue(0, 100000, 3000) == 30000, "first crate: 10 min x $3,000/min = $30,000")
check(S.VipSupplyDue(100000, 100000 + 19 * 3600, 3000) == 0, "not again within 20 h")
check(S.VipSupplyDue(100000, 100000 + 20 * 3600, 100) == 5000, "after 20 h again; the $5,000 floor")
local owner, other = mkPlayer(470626172), mkPlayer(9)
local profiles = { [470626172] = { VipSupplyAt = 0 }, [9] = { VipSupplyAt = 0 } }
local paid, dirty, vipOwned = {}, 0, { [470626172] = true, [9] = true }
S.Init({
  DataService = { GetProfile = function(p) return profiles[p.UserId] end, MarkDirty = function() dirty += 1 end, OnProfileLoaded = function() end },
  EconomyService = { AddCash = function(p, n, why) table.insert(paid, { p = p, n = n, why = why }) end },
  MonetizationService = {
    PassivePerMin = function() return 2000 end,
    PlayerOwnsEntitlement = function(p, k) return (k == "VIP" and vipOwned[p.UserId]) or (k == "DoubleHP" and p.UserId == 470626172) end,
    PlayerOwnsGamePass = function() return false end,
    OnPassOwned = function() end,
  },
  NotificationService = { Notify = function() end },
})
check(S.TryVipSupply(owner) == 20000 and #paid == 1 and paid[1].why == "vip_supply" and profiles[470626172].VipSupplyAt > 0, "live VIP owner: crate $20,000 paid as vip_supply")
check(S.TryVipSupply(owner) == 0 and #paid == 1, "the crate never pays twice in a day")
-- codebot_v142: launched for everyone; the owner-first rule is still proved with OwnerFirst = true for this one check
local launched = SO.Live.OwnerFirst
SO.Live.OwnerFirst = true
check(S.TryVipSupply(other) == 0, "owner-first rule: not live for another player -> no crate")
SO.Live.OwnerFirst = launched
check(launched == false and SO.LiveFor(9) and SO.LiveFor(12345), "codebot_v142: ShopOverhaulConfig live for everyone (OwnerFirst=false)")
check(S.TryVipSupply(other) == 20000, "codebot_v142: a non-owner VIP gets the crate too")
vipOwned[470626172] = false
profiles[470626172].VipSupplyAt = 0
check(S.TryVipSupply(owner) == 0, "no VIP: no crate")
check(MC.CashMultExemptReasons.vip_supply == true, "vip_supply is multiplier-exempt (the minutes already include them)")

-- ── 4. perks ──
S.SyncPerks(owner)
check(owner.attrs.WE_PerkDoubleHP == true and owner.attrs.WE_PerkSuperSoldiers == nil, "Double HP owner -> WE_PerkDoubleHP; no Super Soldiers")
S.SyncPerks(other)
check(other.attrs.WE_PerkDoubleHP == nil, "a non-owner without Double HP -> no perk attribute")

-- ── 5. speed stand ──
local function stand(plot)
  local top = Instance.new("Part")
  top:SetAttribute("PlotId", plot); top:SetAttribute("PadSlot", "Speed"); top:SetAttribute("OfferKind", "GamePass"); top:SetAttribute("OfferKey", "ImpulseSpeed")
  local bb = Instance.new("BillboardGui"); bb.Name = "WE_PremiumBillboard"; bb.Parent = top
  for _, n in ipairs({ "Title", "Benefit" }) do local l = Instance.new("TextLabel"); l.Name = n; l.Parent = bb end
  local chip = Instance.new("Frame"); chip.Name = "PriceChip"; chip.Parent = bb
  local pr = Instance.new("TextLabel"); pr.Name = "Price"; pr.Parent = chip
  local pp = Instance.new("ProximityPrompt"); pp.Name = "WE_BuyPrompt"; pp.Parent = top
  return top, pr, pp
end
local top, price, pp = stand(4)
local top2 = stand(5)
TAGGED = { top, top2 }
S.SyncSpeedStand(4, owner)
check(top:GetAttribute("OfferKind") == "DevProduct" and top:GetAttribute("OfferKey") == "SpeedBoost" and price.Text == "R$ 99" and pp.ActionText == "Buy - R$ 99", "live owner's Speed stand sells Speed Boost (R$ 99)")
check(top2:GetAttribute("OfferKey") == "ImpulseSpeed", "another plot's stand untouched")
S.SyncSpeedStand(4, nil)
check(top:GetAttribute("OfferKind") == "GamePass" and top:GetAttribute("OfferKey") == "ImpulseSpeed", "owner left: back to the config's first live offer (Speed Pass)")

-- ── 6. config ──
for k, v in pairs({ WarChest = { 2002640637, 799 }, SuperSoldiers = { 1998231741, 349 }, DoubleHP = { 2002214665, 199 } }) do
  local d = MC.GamePasses[k]
  check(d ~= nil and d.Id == v[1] and d.RobuxPrice == v[2] and d.OverhaulShop == true, k .. ": Id " .. v[1] .. ", R$ " .. v[2])
end
check(table.concat(MC.GamePasses.WarChest.Implies, ",") == "DoubleCash,AutoCollect,VIP,BiggerArmy", "War Chest implies 2x Cash, Auto Collect, VIP, Bigger Army")
check(MC.GamePasses.VIP.RobuxPrice == 199 and MC.GamePasses.VIP.OverhaulRobuxPrice == 199 and MC.GamePasses.VIP.Id == 1985475542, "codebot_v142: VIP shown at the real Creator Hub price 199 (owner has not approved 349)")
check(SO.Vip.CashBonusMult == 0.5 and MC.GamePasses.VIP.CashBonusMult == 0.25, "VIP +50 % while live (+25 % old path)")
check(SO.HideWhenLive.ImpulseSpeed and SO.HideWhenLive.ExtraSoldierSlot and SO.DeathOfferProduct == "SpeedBoost" and SO.ArmyWipedPass == "BiggerArmy", "duplicates: Speed Pass / Army Expansion out; Speed Boost / Bigger Army sold")
check(SO.SuperSoldiers.Mult == 1.25 and SO.DoubleHP.Mult == 2, "Super Soldiers x1.25, Double HP x2")

print(string.format("SHOP TEST: %d failed", fails))
if fails > 0 then error("failed") end
'''

fails = []
ms = (SV / "Services/MonetizationService.luau").read_text(encoding="utf-8").replace("\r\n", "\n")
pr = ms[ms.index("local function processReceipt"):]
a = pr.find("cashGrant = nonNegInt(ShopOverhaulConfig.CashPackAmount(productKey :: string, perMin))")
b = pr.find("EconomyService.AddCash(player, cashGrant, \"devproduct\")")
c = pr.find("local perMin = MonetizationService.PassivePerMin(player, profile, true)\n\t\tif not player.Parent or DataService.GetProfile(player) ~= profile then\n\t\t\treturn Enum.ProductPurchaseDecision.NotProcessedYet")
print(("ok    " if 0 < a < b and c > 0 else "FAIL  ") + "receipt: the pack lookup (may yield) comes before the first mutation and re-checks the player / profile")
if not (0 < a < b and c > 0):
    fails.append("receipt order")

chunks = [PRELUDE, EXTRA]
for key, path in MODS.items():
    chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
chunks.append(TEST)
with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
    f.write("\n".join(chunks))
    path = f.name
luau = os.environ.get("LUAU", "luau")
r = subprocess.run([luau, path], capture_output=True, text=True)
out = r.stdout.strip()
print(out if os.environ.get("VERBOSE") else ("\n".join(l for l in out.splitlines() if l.startswith("FAIL") or l.startswith("SHOP TEST") or l.startswith("  ")) or out))
if r.returncode != 0:
    print(r.stderr.strip()[-2500:])
    fails.append("shop test")

# codebot_v140: 8. RENDER - the real ShopController.Init builds List_Supply (owner + another player): every cash pack row
# renders, the JOB 36 passes are owner-first, and the cash "+" scrolls to the Mega row (tools/sim/run_shop_render_test.py)
import run_shop_render_test  # noqa: E402

if not (run_shop_render_test.run(470626172) & run_shop_render_test.run(9) & run_shop_render_test.run(9, "real")):  # Code Bot v167: + shipped Ids
    fails.append("shop render")
if fails:
    sys.exit(1)
