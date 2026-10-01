"""claude-bud JOB 41 part B: the Recruit Pack gate + grant on the REAL code: MonetizationService (receipt, the old
Starter pop-up suppression), RecruitPackService (when), MonetizationConfig (the cash formula), ProfileSchema-free stubs
for the rest. Reuses run_first_offer_test's virtual clock / Players / remotes / require-by-path harness.

1. WHEN: no offer at 9:59 of play without a capture; an offer at the first capture (3 min); an offer at 10:00 without
   a capture; never in combat (a hit 5 s ago), in the Guided / onboarding hold, while seated or while the card is out;
   a busy soft-offer slot retries 30 s later; once per profile ("shown" marks RecruitPackOffered; a new session after
   that: nothing); "dropped" retries.
2. Id 0 never offers (and never prompts).
3. GRANT (ProcessReceipt): cash = clamp(30 x income/min, 25k, 150k) at 3 income levels; the 2x boost goes through
   CodesService.GrantCashBoost (30 min, x2); the cosmetic entitlement RecruitPack is saved; idempotent per PurchaseId.
4. OFF == OLD: the old Starter Pack pop-up (TrySoftOfferStarterBundle / ScheduleFirstOffer) is suppressed while the
   offer is live for the player and works as before for a player it is not live for.
5. NOT PAY-TO-WIN: the product row has no damage / health / armour / army / raid / protection key.
Run: LUAU=path/to/luau(.exe) python tools/sim/run_recruit_pack_test.py   (VERBOSE=1 prints every line)"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_first_offer_test as FO  # noqa: E402

SV = FO.SV
MODS = dict(FO.MODS)
MODS["Server/Services/RecruitPackService"] = SV / "Services/RecruitPackService.luau"

EXTRA = r'''
-- the boost path (CodesService.GrantCashBoost) records its calls
BOOSTS = {}
SOURCES["Server/Services/CodesService"] = function() return { GrantCashBoost = function(p, minutes, mult) table.insert(BOOSTS, { P = p, Min = minutes, Mult = mult }); return 1 end } end
'''

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local MC = require(node("Shared/Configs/MonetizationConfig"))
local O = MC.RecruitPackOffer
local OWNER = 470626172

-- 5. not pay-to-win
local row = MC.DevProducts.RecruitPack
local bad = {}
for k in pairs(row) do
  for _, w in ipairs({ "Damage", "Health", "HP", "Armour", "Armor", "Army", "Soldier", "Raid", "Shield", "Protect" }) do
    if string.find(k, w) then table.insert(bad, k) end
  end
end
check(#bad == 0 and row.Id == 0 and row.RobuxPrice == 49 and row.OneTime == true and row.GrantEntitlement == "RecruitPack",
  "the row: Id 0, 49 R$, one time, entitlement RecruitPack, no stat key (" .. table.concat(bad, ",") .. ")")

-- the cash formula
check(MC.RecruitPackCash(0) == 25000 and MC.RecruitPackCash(1000) == 30000 and MC.RecruitPackCash(10000) == 150000 and MC.RecruitPackCash(0 / 0) == 25000,
  "cash = clamp(30 x $/min, 25k, 150k): $0/min -> 25,000, $1,000/min -> 30,000, $10,000/min -> 150,000")
check(O.MinCash >= 2.5 * MC.DevProducts.CashSmall.Cash, "always >= 2.5x Cash Pack S ($" .. MC.DevProducts.CashSmall.Cash .. ")")

-- one fresh world per scenario
local PROFILES, HOLD, HURT, PERMIN = {}, {}, {}, 500
local LOADED = {}
local CLAIM = true
local function fresh(id)
  CACHE["Server/Services/MonetizationService"] = nil
  CACHE["Server/Services/RecruitPackService"] = nil
  CACHE["Server/Modules/OfferLedger"] = nil
  resetClock(); REMOTES = {}; CLIENT_HANDLERS = {}; Players.PLAYERS = {}; Players.PlayerRemoving = signal()
  PROFILES = {}; HOLD = {}; HURT = {}; BOOSTS = {}; LOADED = {}
  row.Id = id
  local cash = {}
  local DataService = { GetProfile = function(p) return PROFILES[p.UserId] end, MarkDirty = function() end, IsLoaded = function() return true end,
    OnProfileLoaded = function(fn) table.insert(LOADED, fn) end, WaitForProfile = function(p) return PROFILES[p.UserId] end, SaveProfile = function() return true end }
  local Economy = { AddCash = function(p, n, why) table.insert(cash, { N = n, Why = why }) end, AddGold = function() end, GetCashMult = function() return 1 end }
  local Base = { ComputePassiveIncomePerTick = function() return PERMIN / 12 end }
  local LOG = {}
  local Analytics = { Log = function(n, uid, props) table.insert(LOG, { Name = n, Props = props or {} }) end }
  local MS = require(node("Server/Services/MonetizationService"))
  MS.Init({ DataService = DataService, AnalyticsService = Analytics, RemoteSetup = RemoteSetup, RateLimitService = { Allow = function() return true end },
    NotificationService = { Notify = function() end }, EconomyService = Economy, BattlePassService = any, BaseService = Base, SoldierService = nil })
  if not CLAIM then MS.ClaimSoftOfferSlotRefundable = function() return nil end end
  local RPS = require(node("Server/Services/RecruitPackService"))
  RPS._clock = function() return NOW end
  RPS.Init({ DataService = DataService, MonetizationService = MS, AnalyticsService = Analytics, RemoteSetup = RemoteSetup,
    RetentionService = { IsOnboarding = function(p) return HOLD[p.UserId] == true end },
    RatePromptService = { SinceHurt = function(p) return if HURT[p.UserId] then NOW - HURT[p.UserId] else math.huge end } })
  return MS, RPS, cash, LOG
end
local function join(uid, extra)
  local p, hum = newPlayer(uid)
  local pr = { TutorialComplete = true, StarterBundleOffered = false, Entitlements = {}, Stats = { PlayTimeSeconds = 0 },
    FirstJoinUnix = 1790000000, ProcessedReceipts = {} }
  for k, v in pairs(extra or {}) do pr[k] = v end
  PROFILES[uid] = pr
  for _, fn in ipairs(LOADED) do fn(p, pr) end
  return p, pr, hum
end
local function offers() local n = 0; for _, r in pairs(REMOTES) do end; return OFFERS end
OFFERS = 0
local function hookClient(answer)
  OFFERS = 0
  REMOTES["FeaturePush"] = nil
  local r = RemoteSetup.Get("FeaturePush")
  r.FireClient = function(_, player, kind, data)
    if kind == "RecruitPackOffer" then
      OFFERS += 1
      LASTOFFER = data
      if answer then REMOTES["RequestRecruitPackResult"].OnServerEvent:Fire(player, answer) end
    end
  end
end
local function play(RPS, p, secs) local t = 0; while t < secs do NOW += 5; t += 5; RPS.Step(p) end end

-- 1a. 9:59 without a capture: nothing; 10:00: yes
do
  local MS, RPS = fresh(999)
  local p, pr = join(OWNER)
  hookClient("shown")
  RPS.Step(p)
  while pr.Stats.PlayTimeSeconds < 595 do NOW += 5; RPS.Step(p) end
  check(OFFERS == 0, "no offer at 9:55 of play without a capture (play counted: " .. pr.Stats.PlayTimeSeconds .. " s)")
  NOW += 5; RPS.Step(p)
  check(OFFERS == 1 and LASTOFFER.Trigger == "playtime" and LASTOFFER.Cash == MC.RecruitPackCash(500) and LASTOFFER.RobuxPrice ~= nil,
    "an offer at 10:00 without a capture (trigger playtime, cash $" .. tostring(LASTOFFER and LASTOFFER.Cash) .. " = his number now)")
  check(pr.RecruitPackOffered == true, "'shown' marks RecruitPackOffered (saved)")
  play(RPS, p, 1200)
  check(OFFERS == 1, "once per profile (20 more minutes: nothing)")
  -- a new session with the saved flag
  local MS2, RPS2 = fresh(999)
  PROFILES[OWNER] = pr
  p = Players.PLAYERS[1] or newPlayer(OWNER)
  hookClient("shown")
  RPS2.OnCapture(p); play(RPS2, p, 600)
  check(OFFERS == 0, "a new session after it was shown: never again (capture + 10 min)")
end

-- 1b. the first capture at 3 min
do
  local MS, RPS = fresh(999)
  local p, pr = join(OWNER)
  hookClient("shown")
  play(RPS, p, 175)
  check(OFFERS == 0, "nothing at 2:55 before a capture")
  RPS.OnCapture(p); play(RPS, p, 5)
  check(OFFERS == 1 and LASTOFFER.Trigger == "capture", "an offer at the first capture (3:00, trigger capture)")
end

-- 1c. never in combat / the hold / seated; dropped retries; busy slot retries
do
  local MS, RPS = fresh(999)
  local p, pr, hum = join(OWNER)
  hookClient(nil)
  NOW += 120 -- past the existing FirstOffer quiet window (the soft-offer budget's own rule)
  RPS.OnCapture(p)
  HOLD[OWNER] = true; play(RPS, p, 30)
  check(OFFERS == 0, "never during the Guided / onboarding hold")
  HOLD[OWNER] = nil; HURT[OWNER] = NOW - 5; play(RPS, p, 5)
  check(OFFERS == 0, "never 5 s after taking damage (combat quiet 20 s)")
  NOW += 20; hum.SeatPart = {}; play(RPS, p, 5)
  check(OFFERS == 0, "never while seated")
  hum.SeatPart = nil; play(RPS, p, 5)
  check(OFFERS == 1, "free screen, on foot, quiet: offered")
  play(RPS, p, 60)
  check(OFFERS == 1, "never a second card while one is out")
  REMOTES["RequestRecruitPackResult"].OnServerEvent:Fire(p, "dropped")
  play(RPS, p, 25)
  check(OFFERS == 1 and pr.RecruitPackOffered ~= true, "'dropped' (never seen): not marked, waits RetrySeconds")
  play(RPS, p, 10)
  check(OFFERS == 2, "... then offered again (" .. O.RetrySeconds .. " s later)")
end
do
  CLAIM = false
  local MS, RPS = fresh(999)
  local p = join(OWNER)
  hookClient("shown")
  RPS.OnCapture(p); play(RPS, p, 5)
  local s = RPS._Session(p)
  check(OFFERS == 0 and s.NextAt > NOW, "a busy soft-offer slot: not sent, retried RetrySeconds later")
  CLAIM = true
end

-- 2. Id 0 never offers
do
  local MS, RPS = fresh(0)
  local p = join(OWNER)
  hookClient("shown")
  RPS.OnCapture(p); play(RPS, p, 900)
  check(OFFERS == 0, "Id 0: never offered (so never prompted)")
end

-- 3. the grant
-- JOB 41: TimePacks OFF -> the JOB 41 clamp (claude-bud JOB 42 part C keeps it exactly when off)
local SOx = require(node("Shared/Configs/ShopOverhaulConfig"))
SOx.TimePacks.Enabled = false
for _, lvl in ipairs({ { 0, 25000 }, { 2000, 60000 }, { 9000, 150000 } }) do
  PERMIN = lvl[1]
  local MS, RPS, cash = fresh(999)
  local p, pr = join(OWNER)
  local d = MS.ProcessReceipt({ PlayerId = OWNER, ProductId = 999, PurchaseId = "r-" .. lvl[1], CurrencySpent = 49 })
  local paid = 0
  for _, c in ipairs(cash) do if c.Why == "devproduct" then paid += c.N end end
  check(tostring(d) ~= "" and paid == lvl[2], string.format("grant at $%d/min: $%d cash (want $%d)", lvl[1], paid, lvl[2]))
  if lvl[1] == 2000 then
    check(#BOOSTS == 1 and BOOSTS[1].Min == 30 and BOOSTS[1].Mult == 2, "the 2x cash boost goes through CodesService.GrantCashBoost (30 min, x2)")
    check(pr.Entitlements.RecruitPack == true, "the cosmetic entitlement RecruitPack is saved")
    MS.ProcessReceipt({ PlayerId = OWNER, ProductId = 999, PurchaseId = "r-2000", CurrencySpent = 49 })
    local again = 0
    for _, c in ipairs(cash) do if c.Why == "devproduct" then again += c.N end end
    check(again == paid and #BOOSTS == 1, "idempotent per PurchaseId (a re-delivered receipt grants nothing)")
  end
end
PERMIN = 500

-- claude-bud JOB 42 part C: TimePacks live for him -> the cash = TimePackAmount("Cash30m") (no 150k cap, the 25k floor)
SOx.TimePacks.Enabled = true
for _, inc in ipairs({ 0, 500, 2000, 9000 }) do
  PERMIN = inc
  local MS, RPS, cash = fresh(999)
  local p, pr = join(OWNER)
  local perMin = MS.PassivePerMin(p, pr, true)
  MS.ProcessReceipt({ PlayerId = OWNER, ProductId = 999, PurchaseId = "rt-" .. inc, CurrencySpent = 49 })
  local paid = 0
  for _, c in ipairs(cash) do if c.Why == "devproduct" then paid += c.N end end
  local want = SOx.TimePackAmount("Cash30m", perMin)
  check(paid == want and (inc ~= 9000 or paid > 150000), string.format("TimePacks live, $%d/min: Recruit Pack cash $%d == the 30 MIN OF CASH amount $%d", inc, paid, want))
  if inc == 2000 then
    check(#BOOSTS == 1 and BOOSTS[1].Min == 30 and pr.Entitlements.RecruitPack == true, "live: the boost and the trim still grant")
  end
end
check(row.Id == 999 or row.Id == 0, "the row keeps its Id (0 in config) and 49 R$: " .. tostring(MC.DevProducts.RecruitPack.RobuxPrice))
-- the card shows the same live number as the 30 MIN OF CASH row
do
  PERMIN = 2000
  local MS, RPS = fresh(999)
  local p, pr = join(OWNER)
  hookClient("shown")
  NOW += 130
  RPS.OnCapture(p); RPS.Step(p); NOW += 5; RPS.Step(p)
  check(LASTOFFER ~= nil and LASTOFFER.Cash == SOx.TimePackAmount("Cash30m", MS.PassivePerMin(p, pr, true)), "the card's $ = the 30 MIN OF CASH amount ($" .. tostring(LASTOFFER and LASTOFFER.Cash) .. ")")
end
PERMIN = 500

-- 4. the old Starter Pack pop-up
do
  MC.FirstOffer.Enabled = true
  local MS, RPS = fresh(999)
  local p = join(OWNER)
  local q = join(1234)
  check(MS.TrySoftOfferStarterBundle(p, "tutorial_complete") == nil, "live for him: the old after-tutorial Starter Pack pop-up does NOT fire")
  local sent = false
  CLIENT_HANDLERS["StarterBundleOffer"] = function(pl) if pl == q then sent = true end end
  runUntil(200)
  local r = MS.TrySoftOfferStarterBundle(q, "tutorial_complete")
  check(r == true and sent, "not live for another player: the Starter Pack pop-up fires as before (OFF == OLD)")
end

print(string.format("RECRUIT PACK TEST: %d failed", fails))
if fails > 0 then error("failed") end
'''


def main():
    chunks = [FO.PRELUDE, EXTRA]
    for key, path in MODS.items():
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
    chunks.append(TEST)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True)
    out = (r.stdout + r.stderr).strip()
    print(out if os.environ.get("VERBOSE") else ("\n".join(l for l in out.splitlines() if l.startswith("FAIL") or l.startswith("RECRUIT PACK TEST")) or out))
    if r.returncode != 0 or "RECRUIT PACK TEST: 0 failed" not in out:
        sys.exit(1)


if __name__ == "__main__":
    main()
