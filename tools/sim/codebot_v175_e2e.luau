-- Code Bot v175: TOP SUPPORTERS end to end (see run_codebot_v175_test.py). Appended to run_first_offer_test's PRELUDE.
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local SCEN = "@SCEN@"
local OLD = @OLD@ -- true = running against the v173 EngagementService (the evidence run)

-- instances with Parent / Name lookups (the WE_Leaderboards folder + its StringValues)
local CREATED = {}
Instance = { new = function(class)
  local o = inst(class, { Name = class })
  o.FindFirstChild = function(self, n) for _, c in ipairs(CREATED) do if c.Parent == self and c.Name == n then return c end end return nil end
  o.GetChildren = function(self) local t = {}; for _, c in ipairs(CREATED) do if c.Parent == self then table.insert(t, c) end end return t end
  o.Destroy = function(self) self.Parent = nil end
  table.insert(CREATED, o)
  return o
end }
local function rsFind(_, n)
  for _, c in ipairs(CREATED) do if c.Parent == RS and c.Name == n then return c end end
  if n == "WE_Leaderboards" then return nil end
  return node(n)
end
rawset(RS, "FindFirstChild", rsFind)

-- DataStoreService with Roblox's per-server request budgets (per minute, banked up to 3 minutes)
local RATES = { GetSortedAsync = { 5, 2 }, SetIncrementSortedAsync = { 30, 5 }, GetAsync = { 60, 10 }, UpdateAsync = { 60, 10 } }
if SCEN == "busy" then RATES.GetSortedAsync = { 2, 0.5 } end -- a server whose list budget is shared with a busy experience (experience-level limits)
local BUDGET, BUDGET_AT = {}, {}
local DS_LOG = { reads = {}, writes = {}, refused = 0 }
local function rate(kind) local r = RATES[kind] or { 60, 10 }; return r[1] + r[2] * #Players.PLAYERS end
local function budgetNow(kind)
  local b = BUDGET[kind]
  if b == nil then b = rate(kind); BUDGET_AT[kind] = NOW end
  b = math.min(3 * rate(kind), b + rate(kind) * (NOW - (BUDGET_AT[kind] or NOW)) / 60)
  BUDGET[kind], BUDGET_AT[kind] = b, NOW
  return b
end
local function spend(kind) budgetNow(kind); if BUDGET[kind] < 1 then DS_LOG.refused += 1; error("DataStore request dropped: budget " .. kind) end; BUDGET[kind] -= 1 end
local ORDERED = {}
local DSS = {
  GetRequestBudgetForRequestType = function(_, kind) return math.floor(budgetNow(tostring(kind))) end,
  GetOrderedDataStore = function(_, name)
    ORDERED[name] = ORDERED[name] or {}
    local t = ORDERED[name]
    return {
      SetAsync = function(_, k, v) spend("SetIncrementSortedAsync"); t[k] = v; table.insert(DS_LOG.writes, { At = NOW, Store = name, K = k, V = v }) end,
      RemoveAsync = function(_, k) t[k] = nil end,
      GetSortedAsync = function(_, asc, n)
        spend("GetSortedAsync")
        table.insert(DS_LOG.reads, { At = NOW, Store = name })
        local rows = {}
        for k, v in pairs(t) do table.insert(rows, { key = k, value = v }) end
        table.sort(rows, function(a, b) return a.value > b.value end)
        local page = {}
        for i = 1, math.min(n, #rows) do page[i] = rows[i] end
        return { GetCurrentPage = function() return page end }
      end,
    }
  end,
  GetDataStore = function() return { UpdateAsync = function(_, _, f) f(nil) end } end,
}
local Http = { JSONEncode = function(_, v) return v end, GenerateGUID = function() return "g" end }
local baseGet = game.GetService
game.GetService = function(self, n)
  if n == "DataStoreService" then return DSS end
  if n == "HttpService" then return Http end
  return baseGet(self, n)
end
Players.GetNameFromUserIdAsync = function(_, uid) return "U" .. uid end
Enum = setmetatable({ DataStoreRequestType = { GetSortedAsync = "GetSortedAsync", SetIncrementSortedAsync = "SetIncrementSortedAsync" }, InfoType = { GamePass = "GamePass" } }, { __index = function() return any end })

local OWNER, LAU = 470626172, 11718087109
local SPEED_ID = 3713839342
local PROFILES, LOADED = {}, {}
local function mkProfile() return { Cash = 1000, Prestige = 0, Level = 5, Stats = { Kills = 0 }, Entitlements = {}, ProcessedReceipts = {}, Settings = {},
  FirstJoinUnix = os.time() - 86400, PrevJoinUnix = os.time() - 3600,
  Monetization = { FirstPurchaseUnix = 0, LastPurchaseUnix = 0, Purchases = 0, RobuxSpent = 0 } } end
local DataService = {
  GetProfile = function(p) return PROFILES[p.UserId] end, MarkDirty = function() end, IsLoaded = function(p) return PROFILES[p.UserId] ~= nil end,
  OnProfileLoaded = function(cb) table.insert(LOADED, cb) end, WaitForProfile = function(p) return PROFILES[p.UserId] end, SaveProfile = function() return true end,
}
local CASHLOG = {}
local Economy = { AddCash = function(p, n, why) table.insert(CASHLOG, { U = p.UserId, N = n, Why = why }); local pr = PROFILES[p.UserId]; if pr then pr.Cash += n end; return true end,
  AddGold = function() end, GetCashMult = function() return 1 end, CashBoostMult = function() return 1 end }
local MC = require(node("Shared/Configs/MonetizationConfig"))
check(MC.DevProducts.SpeedBoost.Id == SPEED_ID and MC.DevProducts.SpeedBoost.RobuxPrice == 99, "Speed Boost is the developer product 3713839342 (99 R$)")
local AC = require(node("Shared/Configs/AdminConfig"))
local isAdmin = false
for _, id in ipairs(AC.UserIds) do if id == LAU then isAdmin = true end end
check(not isAdmin and not AC.IsPlaytestOwner(LAU), "Laumartinez26 (11718087109) is NOT an admin / playtest owner (AdminConfig.UserIds = " .. table.concat(AC.UserIds, ",") .. ")")

local MS = require(node("Server/Services/MonetizationService"))
MS.Init({ DataService = DataService, AnalyticsService = { Log = function() end }, RemoteSetup = RemoteSetup, RateLimitService = { Allow = function() return true end },
  NotificationService = { Notify = function() end }, EconomyService = Economy, BattlePassService = any, BaseService = { ComputePassiveIncomePerTick = function() return 10 end }, SoldierService = nil })
local ES = require(node("Server/Services/EngagementService"))
ES.Init({ DataService = DataService, EconomyService = Economy, NotificationService = { Notify = function() end }, MonetizationService = MS,
  RateLimitService = { Allow = function() return true end }, AnalyticsService = { Log = function() end } })

local function join(uid, friendsWith)
  local p = newPlayer(uid)
  p.Name = if uid == LAU then "Laumartinez26" elseif uid == OWNER then "shaunie6" else ("P" .. uid)
  p.DisplayName = p.Name
  p.CharacterAdded = signal()
  p.GetJoinData = function() return {} end
  p.IsFriendsWithAsync = function(_, other) return friendsWith == true end
  PROFILES[uid] = PROFILES[uid] or mkProfile()
  for _, cb in ipairs(LOADED) do cb(p, PROFILES[uid]) end
  return p
end
local function board(key)
  local f = rsFind(RS, "WE_Leaderboards")
  local sv = f and f:FindFirstChild(key)
  return sv and sv.Value
end
local function rowsHas(key, uid, v)
  local d = board(key)
  for _, r in ipairs(d and d.Rows or {}) do if r.U == uid and (v == nil or r.V == v) then return true end end
  return false
end
local function lastRead(store) local t = nil; for _, r in ipairs(DS_LOG.reads) do if r.Store == store then t = r.At end end; return t end

local friends = true
if SCEN == "payfail" then local real = Economy.AddCash; Economy.AddCash = function(p, n, why) if why == "friends_bonus" then error("AddCash blew up") end; return real(p, n, why) end end
local shaun = join(OWNER, friends)
runUntil(NOW + 2)
local lau = join(LAU, friends)
runUntil(NOW + 300) -- five minutes of play before the purchase
print(string.format("[before] t=%.0f supporters published=%s, last read of WE_LB2_Supporters at %s, friends bonus paid %d times",
  NOW, tostring(board("Supporters") ~= nil), tostring(lastRead("WE_LB2_Supporters")), #CASHLOG))

-- 15:55 Dublin: Laumartinez26 buys Speed Boost (the REAL ProcessReceipt)
local decision
task.spawn(function() decision = MS.ProcessReceipt({ PlayerId = LAU, ProductId = SPEED_ID, PurchaseId = "lau-speed-1555", CurrencySpent = 99 }) end)
runUntil(NOW + 1)
local pr = PROFILES[LAU]
print(string.format("[receipt] decision=%s RobuxSpent=%s Purchases=%s receipts=%s",
  tostring(decision), tostring(pr.Monetization.RobuxSpent), tostring(pr.Monetization.Purchases), tostring(pr.ProcessedReceipts["lau-speed-1555"])))
check(tostring(decision):find("PurchaseGranted") ~= nil or decision == any, "the receipt is granted")
check(pr.Monetization.RobuxSpent == 99, "ProcessReceipt adds CurrencySpent 99 to Monetization.RobuxSpent")
check((ORDERED["WE_LB2_Supporters"] or {})[tostring(LAU)] == 99, "the saved grant writes WE_LB2_Supporters[11718087109] = 99 at once (OnGranted)")
local tBuy = NOW
runUntil(NOW + 160) -- two shared-read periods (ReadSeconds 75)
print(string.format("[after] t=%.0f last read of WE_LB2_Supporters at %s (buy at %.0f), reads total %d, budget GetSorted %.1f",
  NOW, tostring(lastRead("WE_LB2_Supporters")), tBuy, #DS_LOG.reads, budgetNow("GetSortedAsync")))
check((lastRead("WE_LB2_Supporters") or -1) > tBuy, "the shared reader re-reads WE_LB2_Supporters after the purchase")
check(rowsHas("Supporters", LAU, 99), "the published TOP SUPPORTERS board shows Laumartinez26 · 99 within two read periods")
check(not rowsHas("Supporters", OWNER), "the owner / admin is never on TOP SUPPORTERS")

if SCEN == "friends" and not OLD then
  -- THIS WEEK tab: the 99 R$ counts this ISO week too
  check((ORDERED["WE_LB2_Supporters_W" .. require(node("Shared/Configs/LeaderboardConfig")).IsoWeek(os.time())] or {})[tostring(LAU)] == 99, "THIS WEEK: WE_LB2_Supporters_W<week>[11718087109] = 99")
  check(rowsHas("Supporters_W", LAU, 99), "the published THIS WEEK tab shows Laumartinez26 · 99")
  -- Roblox re-delivers the same receipt (e.g. after a slow ack): never counted twice
  local d2
  task.spawn(function() d2 = MS.ProcessReceipt({ PlayerId = LAU, ProductId = SPEED_ID, PurchaseId = "lau-speed-1555", CurrencySpent = 99 }) end)
  runUntil(NOW + 1)
  check(pr.Monetization.RobuxSpent == 99 and (ORDERED["WE_LB2_Supporters"] or {})[tostring(LAU)] == 99, "the same PurchaseId re-delivered: still 99 (deduped by ProcessedReceipts)")
  -- a second real purchase adds up (all-time and week)
  task.spawn(function() MS.ProcessReceipt({ PlayerId = LAU, ProductId = MC.DevProducts.CashSmall and MC.DevProducts.CashSmall.Id or SPEED_ID, PurchaseId = "lau-2", CurrencySpent = 35 }) end)
  runUntil(NOW + 1)
  check((ORDERED["WE_LB2_Supporters"] or {})[tostring(LAU)] == 134, "a second purchase (35 R$): all-time 134 at once (" .. tostring((ORDERED["WE_LB2_Supporters"] or {})[tostring(LAU)]) .. ")")
  -- the owner buys: never written, never shown
  task.spawn(function() MS.ProcessReceipt({ PlayerId = OWNER, ProductId = SPEED_ID, PurchaseId = "own-1", CurrencySpent = 99 }) end)
  runUntil(NOW + 100)
  check((ORDERED["WE_LB2_Supporters"] or {})[tostring(OWNER)] == nil and not rowsHas("Supporters", OWNER) and not rowsHas("Supporters_W", OWNER), "the owner's own purchase: never on either tab")

  -- JOIN BACKFILL: a saved purchase that never reached the board (the store lost / never got it) is written on join
  ORDERED["WE_LB2_Supporters"][tostring(LAU)] = nil
  for _, f in ipairs(Players.PlayerRemoving.fns) do f(lau) end -- leave (the leave flush writes it back) ...
  for i, q in ipairs(Players.PLAYERS) do if q == lau then table.remove(Players.PLAYERS, i) end end
  ORDERED["WE_LB2_Supporters"][tostring(LAU)] = nil -- ... and the store lost it anyway
  runUntil(NOW + 30)
  lau = join(LAU, true)
  runUntil(NOW + 1)
  check((ORDERED["WE_LB2_Supporters"] or {})[tostring(LAU)] == 134, "join backfill: the saved Monetization.RobuxSpent (134) is written on join, no invented value")

  -- PASS BACKFILL: a game pass owned on Roblox (website), never counted: credited ONCE at PriceInRobux, flag in LB.PassCredit
  local NEWB = 22000001
  local passKey, passDef
  for k, d in pairs(MC.GamePasses) do if type(d.Id) == "number" and d.Id ~= 0 and (passKey == nil or k < passKey) then passKey, passDef = k, d end end
  Marketplace.UserOwnsGamePassAsync = function(_, uid, id) return uid == NEWB and id == passDef.Id end
  Marketplace.GetProductInfo = function(_, id) return { PriceInRobux = (id == passDef.Id) and 149 or nil } end
  local nb = join(NEWB, false)
  MS.RefreshGamePassCache(nb)
  runUntil(NOW + 3)
  local np = PROFILES[NEWB]
  check(np.Monetization.RobuxSpent == 149 and np.LB and np.LB.PassCredit and np.LB.PassCredit[passKey] == true, "pass backfill: " .. passKey .. " owned, never counted -> +149 R$ once, LB.PassCredit." .. passKey .. " = true")
  check((ORDERED["WE_LB2_Supporters"] or {})[tostring(NEWB)] == 149, "pass backfill: written to ALL-TIME at once")
  local wkStore = ORDERED["WE_LB2_Supporters_W" .. require(node("Shared/Configs/LeaderboardConfig")).IsoWeek(os.time())] or {}
  check(wkStore[tostring(NEWB)] == nil, "pass backfill (bought at an unknown time): not added to THIS WEEK")
  -- rejoin: never again
  for _, f in ipairs(Players.PlayerRemoving.fns) do f(nb) end
  for i, q in ipairs(Players.PLAYERS) do if q == nb then table.remove(Players.PLAYERS, i) end end
  runUntil(NOW + 10)
  nb = join(NEWB, false); MS.RefreshGamePassCache(nb); runUntil(NOW + 3)
  check(np.Monetization.RobuxSpent == 149, "pass backfill: the next join never credits it again (" .. tostring(np.Monetization.RobuxSpent) .. ")")
  -- the owner's passes are never credited
  Marketplace.UserOwnsGamePassAsync = function() return true end
  MS.RefreshGamePassCache(shaun); runUntil(NOW + 3)
  check((ORDERED["WE_LB2_Supporters"] or {})[tostring(OWNER)] == nil, "the owner owning passes: never credited / written")
end

if SCEN == "busy" then
  -- a GetSortedAsync budget that allows ~3 reads per pass: does TOP SUPPORTERS still refresh after the purchase?
  print(string.format("[busy] reads in %.0f s: %d, Supporters reads after the buy: %s", NOW, #DS_LOG.reads, tostring(lastRead("WE_LB2_Supporters"))))
end

if SCEN == "payfail" then
  local before = #DS_LOG.reads
  runUntil(NOW + 200)
  check(#DS_LOG.reads > before, "a failing friends payout never stops the board loop (reads go on: " .. before .. " -> " .. #DS_LOG.reads .. ")")
end

print(string.format("V175 SUPPORTERS: %d failed", fails))
if fails > 0 then error("FAIL") end
