"""claude-bud JOB 42 part A: TIME-based cash packs on the REAL code: ShopOverhaulConfig (TimePacks, TimePackAmount,
TimePacksReady / Shown), MonetizationConfig (the five rows) and the REAL MonetizationService.ProcessReceipt with stubs
(run_first_offer_test's virtual clock / coroutine scheduler, so the income lookup can really yield).

AMOUNTS  the five packs at income 0 .. 1,000,000 $/min (+ NaN / negative / 1e13 -> the floor): $ and $ per R$ printed;
         the floor wins below Floor / Minutes, the minutes above; $ per R$ rises with the price in every row; minutes
         per R$ and floor $ per R$ rise with the price (the BEST VALUE 4h tag is honest). -> docs/proof/job42/amounts-sim.txt
RECEIPT  the income lookup runs BEFORE AddCash; leave / profile swap during the yield -> NotProcessedYet, nothing
         granted; the same PurchaseId twice -> once; the receipt-time income wins over the shown number; a running 2x
         CashBoost does not change the amount (ExcludeTimedBoosts); the reason is "devproduct". -> receipt-order.txt
GATING   OFF -> not shown and the old JOB 36 amounts; live but not Ready (Ids 0) -> not shown; live + Ready -> shown;
         an old-pack receipt keeps the JOB 36 formula while the time packs are live; no 1-day / 7-day pack. -> gating-sim.txt
Run: LUAU=path/to/luau(.exe) python tools/sim/run_time_packs_test.py   (VERBOSE=1 prints every line)"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_first_offer_test as FO  # noqa: E402

MODS = dict(FO.MODS)

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local MC = require(node("Shared/Configs/MonetizationConfig"))
local SO = require(node("Shared/Configs/ShopOverhaulConfig"))
local TP = SO.TimePacks
local ORDER_UP = { "Cash15m", "Cash30m", "Cash1h", "Cash2h", "Cash4h" }
local function commas(n) local s = tostring(math.floor(n)); return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")) end

print("== AMOUNTS ==")
-- the rows and the prices
local prices = {}
for _, k in ipairs(ORDER_UP) do prices[k] = MC.DevProducts[k].RobuxPrice end
check(prices.Cash15m == 25 and prices.Cash30m == 49 and prices.Cash1h == 89 and prices.Cash2h == 159 and prices.Cash4h == 279, "the five packs: 25 / 49 / 89 / 159 / 279 R$")
-- Code Bot v167: the real Creator Hub Ids are in the config (were 0 until v166); still repeatable
local SHIPPED = { Cash15m = 3715776339, Cash30m = 3715776410, Cash1h = 3715776466, Cash2h = 3715776582, Cash4h = 3715776616 }
local allShipped = true
for _, k in ipairs(ORDER_UP) do if MC.DevProducts[k].Id ~= SHIPPED[k] or MC.DevProducts[k].OneTime == true then allShipped = false end end
check(allShipped, "codebot_v167: every time pack carries its Creator Hub Id, repeatable (not OneTime)")
check(SO.TimePacksReady() == true and SO.TimePacksShown(1234) == true and SO.TimePacksShown(470626172) == true,
  "codebot_v167: the shipped config -> TimePacksReady, shown to everyone (the time rows replace the old cash rows)")
local long = false
for k, d in pairs(MC.DevProducts) do
  local s = k .. " " .. tostring(d.DisplayName)
  if string.find(s, "1d") or string.find(s, "24h") or string.find(s, "7d") or string.find(s, "Day") or string.find(s, "Week") then long = true end
end
for k, p in pairs(TP.Packs) do if p.Minutes >= 1440 or string.find(p.Title, "DAY") or string.find(p.Title, "WEEK") then long = true end end
check(not long, "no 1-day / 7-day pack anywhere (config rows or TimePacks)")
-- the table
local incomes = { 0, 100, 500, 1000, 5000, 25000, 100000, 1000000 }
local header = string.format("%-10s", "$/min")
for _, k in ipairs(ORDER_UP) do header ..= string.format(" | %-24s", k .. " (" .. prices[k] .. " R$)") end
print(header)
local rising = true
for _, inc in ipairs(incomes) do
  local line = string.format("%-10s", commas(inc))
  local last = -1
  for _, k in ipairs(ORDER_UP) do
    local amt = SO.TimePackAmount(k, inc)
    local per = amt / prices[k]
    line ..= string.format(" | $%-12s %7.0f $/R$", commas(amt), per)
    if per <= last then rising = false end
    last = per
    local p = TP.Packs[k]
    local cross = p.Floor / p.Minutes
    if inc < cross and amt ~= p.Floor then check(false, k .. " at $" .. inc .. "/min: the floor should win") end
    if inc > cross and amt ~= math.floor(p.Minutes * inc) then check(false, k .. " at $" .. inc .. "/min: the minutes should win") end
  end
  print(line)
end
check(rising, "$ per R$ rises with the price in every income row (a bigger pack is always the better deal)")
local okCross = true
for _, k in ipairs(ORDER_UP) do local p = TP.Packs[k]; print(string.format("crossover %s: Floor / Minutes = %.0f $/min", k, p.Floor / p.Minutes)) end
check(math.floor(TP.Packs.Cash15m.Floor / TP.Packs.Cash15m.Minutes) == 666 and math.floor(TP.Packs.Cash4h.Floor / TP.Packs.Cash4h.Minutes) == 833, "crossovers: 667 $/min (15m), 833 (30m .. 4h)")
local mPer, fPer, okM, okF = -1, -1, true, true
for _, k in ipairs(ORDER_UP) do
  local p = TP.Packs[k]
  local a, b = p.Minutes / prices[k], p.Floor / prices[k]
  if a <= mPer then okM = false end
  if b <= fPer then okF = false end
  mPer, fPer = a, b
  print(string.format("%s: %.2f min per R$, %.0f floor $ per R$", k, a, b))
end
check(okM and okF, "minutes per R$ AND floor $ per R$ rise with the price (BEST VALUE on 4h is honest)")
for _, bad in ipairs({ 0 / 0, -50, 1e13 }) do
  check(SO.TimePackAmount("Cash4h", bad) == TP.Packs.Cash4h.Floor, "income " .. tostring(bad) .. " -> the floor")
end
check(SO.TimePackAmount("CashSmall", 1000) == nil and SO.TimePackAmount("Cash4h", 1e11) <= 2 ^ 53, "nil for a non-time pack; capped at 2^53")
check(TP.BestValueKey == "Cash4h" and TP.Enabled == true and TP.OwnerFirst == false, "BEST VALUE on Cash4h; Enabled, codebot_v166: OwnerFirst=false (everyone, once all five Ids are set)")
local TP_LAUNCHED = TP.OwnerFirst

print("== RECEIPT ORDER ==")
local OWNER = 470626172
local ORDERLOG, INCOME, BOOST = {}, 100, 1
local function pm(t) return t * 1.5 / 5 * 60 end
local YIELD = 0
local function fresh(ids)
  CACHE["Server/Services/MonetizationService"] = nil
  CACHE["Server/Modules/OfferLedger"] = nil
  resetClock(); REMOTES = {}; CLIENT_HANDLERS = {}; Players.PLAYERS = {}; Players.PlayerRemoving = signal()
  for k, id in pairs(ids or {}) do MC.DevProducts[k].Id = id end
  local PROFILES = {}
  local cash = {}
  local DataService = { GetProfile = function(p) return PROFILES[p.UserId] end, MarkDirty = function() end, IsLoaded = function() return true end,
    OnProfileLoaded = function() end, WaitForProfile = function(p) return PROFILES[p.UserId] end, SaveProfile = function() return true end }
  local Economy = {
    AddCash = function(p, n, why) table.insert(ORDERLOG, "AddCash"); table.insert(cash, { N = n, Why = why }) end,
    AddGold = function() end,
    GetCashMult = function() return 1.5 * BOOST end, -- a permanent 1.5x (pass / rebirth) x the timed boost
    CashBoostMult = function(profile) return BOOST end,
  }
  local Base = { ComputePassiveIncomePerTick = function()
    table.insert(ORDERLOG, "income")
    if YIELD > 0 then task.wait(YIELD) end
    return INCOME -- $ per 5 s tick; PassivePerMin = INCOME x 1.5 / 5 x 60 = 18 x INCOME (exact) without a boost
  end }
  local MS = require(node("Server/Services/MonetizationService"))
  MS.Init({ DataService = DataService, AnalyticsService = { Log = function() end }, RemoteSetup = RemoteSetup, RateLimitService = { Allow = function() return true end },
    NotificationService = { Notify = function() end }, EconomyService = Economy, BattlePassService = any, BaseService = Base, SoldierService = nil })
  local p = newPlayer(OWNER)
  PROFILES[OWNER] = { Entitlements = {}, Stats = {}, ProcessedReceipts = {} }
  return MS, p, PROFILES, cash
end
local IDS = { Cash15m = 801, Cash30m = 802, Cash1h = 803, Cash2h = 804, Cash4h = 805 }
local function receipt(MS, id, pid)
  local out = nil
  task.spawn(function() out = MS.ProcessReceipt({ PlayerId = OWNER, ProductId = id, PurchaseId = pid, CurrencySpent = 279 }) end)
  runUntil(NOW + 5)
  return out
end
local function paid(cash) local n = 0; for _, c in ipairs(cash) do if c.Why == "devproduct" then n += c.N end end; return n end
local function reasons(cash) local r = {}; for _, c in ipairs(cash) do r[c.Why] = true end; return r end
do
  ORDERLOG = {}; YIELD = 1; INCOME = 100; BOOST = 1
  local MS, p, PR, cash = fresh(IDS)
  local d = receipt(MS, 805, "t-1")
  print("call order: " .. table.concat(ORDERLOG, " -> "))
  check(ORDERLOG[1] == "income" and ORDERLOG[#ORDERLOG] == "AddCash" and paid(cash) == SO.TimePackAmount("Cash4h", pm(100)) and paid(cash) == 432000,
    "the income lookup (yields 1 s) runs BEFORE AddCash; 4h at $1,800/min = $" .. commas(paid(cash)))
  check(reasons(cash).devproduct and #cash == 1, "granted once, with reason devproduct (never multiplied again)")
  local d2 = receipt(MS, 805, "t-1")
  check(paid(cash) == 432000, "the same PurchaseId twice -> granted once")
end
do
  ORDERLOG = {}; YIELD = 1
  local MS, p, PR, cash = fresh(IDS)
  task.delay(0.5, function() p.Parent = nil end)
  local d = receipt(MS, 805, "t-leave")
  check(paid(cash) == 0 and #cash == 0, "the player leaves during the yield -> NotProcessedYet, nothing granted")
end
do
  ORDERLOG = {}; YIELD = 1
  local MS, p, PR, cash = fresh(IDS)
  task.delay(0.5, function() PR[OWNER] = { Entitlements = {}, Stats = {}, ProcessedReceipts = {} } end)
  local d = receipt(MS, 805, "t-swap")
  check(paid(cash) == 0 and #cash == 0, "a profile swap during the yield -> NotProcessedYet, nothing granted")
end
do
  ORDERLOG = {}; YIELD = 0; INCOME = 100
  local MS, p, PR, cash = fresh(IDS)
  local shown = SO.TimePackAmount("Cash1h", pm(INCOME)) -- what the Shop showed at the prompt
  INCOME = 300 -- he built something before the receipt arrived
  receipt(MS, 803, "t-time")
  check(paid(cash) == SO.TimePackAmount("Cash1h", pm(300)) and paid(cash) ~= shown,
    "the receipt-time income wins ($" .. commas(paid(cash)) .. " at $5,400/min, not the shown $" .. commas(shown) .. ")")
end
do
  ORDERLOG = {}; YIELD = 0; INCOME = 100; BOOST = 2
  local MS, p, PR, cash = fresh(IDS)
  receipt(MS, 802, "t-boost")
  check(paid(cash) == SO.TimePackAmount("Cash30m", pm(100)), "a running 2x CashBoost does not change the amount (30m = $" .. commas(paid(cash)) .. ", ExcludeTimedBoosts)")
  BOOST = 1
end
do
  ORDERLOG = {}; YIELD = 0; INCOME = 0
  local MS, p, PR, cash = fresh(IDS)
  receipt(MS, 801, "t-floor")
  check(paid(cash) == 10000, "a new player (no income) gets the floor ($10,000 for 15m)")
end

print("== GATING ==")
do
  TP.OwnerFirst = true -- codebot_v166: launched; the owner-first gating is still proved with OwnerFirst = true
  local MS, p, PR, cash = fresh({ Cash15m = 0, Cash30m = 0, Cash1h = 0, Cash2h = 0, Cash4h = 0 })
  check(SO.TimePacksReady() == false and SO.TimePacksShown(OWNER) == false, "live but not Ready (Ids 0) -> not shown (the old rows stay)")
  MC.DevProducts.Cash15m.Id = 801; MC.DevProducts.Cash30m.Id = 802; MC.DevProducts.Cash1h.Id = 803; MC.DevProducts.Cash2h.Id = 804
  check(SO.TimePacksReady() == false, "four of five Ids -> still not Ready")
  MC.DevProducts.Cash4h.Id = 805
  check(SO.TimePacksReady() == true and SO.TimePacksShown(OWNER) == true and SO.TimePacksShown(1234) == false, "live + Ready -> shown for him; not live for another player -> not shown")
  TP.Enabled = false
  check(SO.TimePacksShown(OWNER) == false, "OFF (Enabled = false) -> not shown (today's Shop)")
  TP.Enabled = true
  INCOME = 100; YIELD = 0
  receipt(MS, 3713838952, "t-old")
  check(paid(cash) == SO.CashPackAmount("CashMega", pm(100)), "an old CashMega receipt keeps the JOB 36 formula while the time packs are live ($" .. commas(paid(cash)) .. ")")
  -- part B: the Mega toast slot sells the 4h pack while shown (same slot / budget); CashMega for a player it is not live for
  local sent = {}
  CLIENT_HANDLERS["CashMegaOffer"] = function(pl, payload) table.insert(sent, payload.ProductKey) end
  MS.ClaimSoftOfferSlot = function() return true end -- the budget itself is run_first_offer_test's subject
  runUntil(NOW + 200)
  MS.TrySoftOfferCashMega(p, "pending_collect", 50000)
  runUntil(NOW + 5)
  local q = newPlayer(1234)
  PR[1234] = { Entitlements = {}, Stats = {}, ProcessedReceipts = {} }
  runUntil(NOW + 200)
  MS.TrySoftOfferCashMega(q, "pending_collect", 50000)
  runUntil(NOW + 5)
  check(sent[1] == "Cash4h" and sent[2] == "CashMega", "the Mega offer slot sells Cash4h while shown, CashMega otherwise (" .. table.concat(sent, ",") .. ")")
  for k, id in pairs(IDS) do MC.DevProducts[k].Id = SHIPPED[k] end -- Code Bot v167: back to the shipped Ids
  TP.OwnerFirst = TP_LAUNCHED
end
-- codebot_v166: launched for everyone; still hidden for everyone until all five Ids are set (TimePacksReady)
do
  check(TP.OwnerFirst == false and SO.TimePacksLiveFor(1234) == true, "codebot_v166: TimePacks live for a non-owner (OwnerFirst=false)")
  local saved = {}
  for _, k in ipairs(TP.Order) do saved[k] = MC.DevProducts[k].Id; MC.DevProducts[k].Id = 0 end
  check(SO.TimePacksShown(1234) == false and SO.TimePacksShown(OWNER) == false, "codebot_v166: Ids 0 -> not shown to anyone (the old rows stay)")
  for i, k in ipairs(TP.Order) do MC.DevProducts[k].Id = 900 + i end
  check(SO.TimePacksShown(1234) == true, "codebot_v166: all five Ids set -> shown to a non-owner")
  for _, k in ipairs(TP.Order) do MC.DevProducts[k].Id = saved[k] end
end
check(SO.TimePacks.HideOldKeys.CashSmall and SO.TimePacks.HideOldKeys.CashMega and MC.DevProducts.CashSmall.Id == 3713838744 and MC.DevProducts.CashMega.RobuxPrice == 799,
  "the old four stay in config with their Ids / prices (only hidden from the Shop once live)")

print(string.format("TIME PACKS TEST: %d failed", fails))
if fails > 0 then error("failed") end
'''


def main():
    chunks = [FO.PRELUDE]
    for key, path in MODS.items():
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
    chunks.append(TEST)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True)
    out = (r.stdout + r.stderr).strip()
    print(out if os.environ.get("VERBOSE") else ("\n".join(l for l in out.splitlines() if l.startswith("FAIL") or l.startswith("TIME PACKS TEST")) or out))
    if r.returncode != 0 or "TIME PACKS TEST: 0 failed" not in out:
        sys.exit(1)


if __name__ == "__main__":
    main()
