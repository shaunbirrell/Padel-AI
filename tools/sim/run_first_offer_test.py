"""Code Bot v153: first-offer timing + the Starter Pack re-queue + the analytics keys, on the REAL server code.

Loads the real MonetizationService, OfferLedger, RemoteGate, MonetizationConfig, AnalyticsConfig, SecurityConfig and
Constants into plain Luau with a virtual clock (task.delay / task.spawn / task.wait / os.clock) and a mocked
DataService / RemoteSetup / Players / MarketplaceService. A mock client answers the StarterBundleOffer remote the way
NotificationController + ShopController now do (hold while driving / in active combat, drop after 60 s, answer
"shown" / "dropped" / "refused" on OfferResult with the AckId).

Scenarios (each prints ok / FAIL; exit 1 on any FAIL):
  OLD  FirstOffer off (= the v152 rules): quiet until the tutorial is done (or 900 s); the Starter Pack sent after the
       tutorial while the player drives is marked StarterBundleOffered at SEND, dropped unseen by the client, and
       never comes back (the root cause).
  A    new player, on foot, tutorial NOT done: nothing before 120 s; the Starter Pack at ~120 s; marked only on "shown".
  B    new player driving the 4x4 at 120 s + a short fight when he gets out: seated wait, sent, held, dropped at 60 s,
       re-queued 45 s later with the soft-offer slot refunded, deferred a few seconds for combat, then shown + marked.
  C    a client that always refuses: at most MaxSendsPerSession sends, >= RequeueSeconds apart; never marked.
  D    no answer at all: AckTimeoutSeconds then re-queued.
  E    Starter Pack already owned: the fallback cheap offer (Speed Boost 99 R$) once at ~120 s.
  F    politeness: after the shown Starter, a 2nd offer waits the 240 s cooldown; at most 3 a session.
  G    analytics: ProductPrompted gets productKey (DevProduct + GamePass), Custom maps OfferShown / OfferDropped /
       PassBought exist, the OfferResult schema accepts the client's call and rejects junk.
Run: LUAU=~/.local/bin/luau python3 tools/sim/run_first_offer_test.py   (VERBOSE=1 prints every line)"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SH = ROOT / "src/ReplicatedStorage/Shared"
SV = ROOT / "src/ServerScriptService/Server"
MODS = {
    "Shared/Constants": SH / "Constants.luau",
    "Shared/Configs/MonetizationConfig": SH / "Configs/MonetizationConfig.luau",
    "Shared/Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
    "Shared/Configs/ShopOverhaulConfig": SH / "Configs/ShopOverhaulConfig.luau",
    "Shared/Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
    "Shared/Configs/EconomyConfig": SH / "Configs/EconomyConfig.luau",
    "Shared/Configs/GameConfig": SH / "Configs/GameConfig.luau",
    "Shared/Configs/DevConfig": SH / "Configs/DevConfig.luau",
    "Shared/Configs/AnalyticsConfig": SH / "Configs/AnalyticsConfig.luau",
    "Shared/Configs/SecurityConfig": SH / "Configs/SecurityConfig.luau",
    "Server/Modules/RemoteGuard": SV / "Modules/RemoteGuard.luau",
    "Server/Modules/RemoteGate": SV / "Modules/RemoteGate.luau",
    "Server/Modules/OfferLedger": SV / "Modules/OfferLedger.luau",
    "Server/Services/MonetizationService": SV / "Services/MonetizationService.luau",
}

PRELUDE = r'''
-- ── virtual clock + task scheduler ──
local NOW = 0
local Q = {}
local qseq = 0
local function push(t, co, args) qseq += 1; table.insert(Q, { T = t, S = qseq, Co = co, Args = args }) end
local function resume(co, ...) local ok, err = coroutine.resume(co, ...); if not ok then error(debug.traceback(co, tostring(err))) end end
local task = {
  delay = function(sec, fn, ...) push(NOW + (tonumber(sec) or 0), coroutine.create(fn), table.pack(...)) end,
  defer = function(fn, ...) push(NOW, coroutine.create(fn), table.pack(...)) end,
  spawn = function(fn, ...) local co = if type(fn) == "thread" then fn else coroutine.create(fn); resume(co, ...) end,
  wait = function(sec) push(NOW + (tonumber(sec) or 0), coroutine.running(), table.pack()); return coroutine.yield() end,
}
local function runUntil(t)
  while true do
    table.sort(Q, function(a, b) if a.T ~= b.T then return a.T < b.T end return a.S < b.S end)
    local e = Q[1]
    if e == nil or e.T > t then break end
    table.remove(Q, 1)
    NOW = math.max(NOW, e.T)
    if coroutine.status(e.Co) == "suspended" then resume(e.Co, table.unpack(e.Args, 1, e.Args.n)) end
  end
  NOW = t
end
local function resetClock() NOW = 0; Q = {} end
local realOs = os
local os = setmetatable({
  clock = function() return NOW end,
  time = function(t) if t then return realOs.time(t) end return 1790000000 + math.floor(NOW) end,
}, { __index = realOs })

-- ── permissive "anything" object ──
local any
local ANY = {}
ANY.__index = function() return any end
ANY.__call = function() return any end
ANY.__newindex = function() end
any = setmetatable({}, ANY)
Enum = any
Color3 = { fromRGB = function(r, g, b) return { R = r, G = g, B = b } end, new = function(r, g, b) return { R = r, G = g, B = b } end }
Vector2 = { new = function(x, y) return { X = x, Y = y } end }
UDim2 = any
UDim = any
NumberSequence = any
ColorSequence = any
Vector3 = { new = function(x, y, z) return { X = x or 0, Y = y or 0, Z = z or 0 } end }
CFrame = any

-- ── instances ──
local INST = {}
INST.__index = function(t, k) return rawget(t, "__props")[k] end
INST.__newindex = function(t, k, v) rawget(t, "__props")[k] = v end
local function inst(class, props)
  local p = props or {}
  p.ClassName = class
  p.IsA = function(_, c) return c == class end
  return setmetatable({ __props = p }, INST)
end
local rawtypeof = typeof
local typeof = function(v)
  if type(v) == "table" and getmetatable(v) == INST then return "Instance" end
  return rawtypeof(v)
end

local function signal()
  local s = { fns = {} }
  s.Connect = function(_, fn) table.insert(s.fns, fn); return { Disconnect = function() end } end
  s.Fire = function(_, ...) for _, fn in ipairs(s.fns) do fn(...) end end
  return s
end

-- remotes
local REMOTES = {}
local CLIENT_HANDLERS = {} -- remote name -> fn(player, payload)
local function remote(name)
  local r = REMOTES[name]
  if r then return r end
  local ev = signal()
  r = inst("RemoteEvent", { Name = name, OnServerEvent = ev })
  r.FireClient = function(_, player, payload)
    local h = CLIENT_HANDLERS[name]
    if h then h(player, payload) end
  end
  REMOTES[name] = r
  return r
end
local RemoteSetup = { Get = function(name) return remote(name) end }

-- players
local Players = { PlayerRemoving = signal(), PlayerAdded = signal(), PlayerMembershipChanged = signal(), PLAYERS = {} }
Players.GetPlayers = function() return Players.PLAYERS end
Players.GetPlayerByUserId = function(_, uid) for _, p in ipairs(Players.PLAYERS) do if p.UserId == uid then return p end end return nil end
local function newPlayer(uid)
  local hum = inst("Humanoid", { SeatPart = nil, WalkSpeed = 16 })
  hum.GetPropertyChangedSignal = function() return signal() end
  hum.Seated = signal()
  local char = inst("Model", {})
  char.FindFirstChildOfClass = function(_, c) if c == "Humanoid" then return hum end return nil end
  local attrs = {}
  local p = inst("Player", { UserId = uid, Name = "P" .. uid, Parent = Players, Character = char, MembershipType = any })
  p.SetAttribute = function(_, k, v) attrs[k] = v end
  p.GetAttribute = function(_, k) return attrs[k] end
  p.Kick = function() end
  p.IsInGroup = function() return false end
  table.insert(Players.PLAYERS, p)
  return p, hum
end

local Marketplace = { PromptGamePassPurchaseFinished = signal() }
Marketplace.UserOwnsGamePassAsync = function() return false end
Marketplace.GetProductInfo = function() return {} end
local RunService = { IsStudio = function() return false end, Heartbeat = signal() }

-- ── require by path ──
local SOURCES, CACHE = {}, {}
local function node(path) return setmetatable({ __path = path }, { __index = function(t, k)
  local p = rawget(t, "__path")
  if k == "Parent" then local q = p:match("^(.*)/[^/]+$") or ""; return node(q) end
  if k == "WaitForChild" or k == "FindFirstChild" then return function(s, n) return node(p == "" and n or (p .. "/" .. n)) end end
  return node(p == "" and k or (p .. "/" .. k))
end }) end
local RS = { WaitForChild = function(_, n) return node(n) end, FindFirstChild = function(_, n) return node(n) end }
setmetatable(RS, { __index = function(_, k) return node(k) end })
game = { GetService = function(_, n)
  if n == "ReplicatedStorage" then return RS end
  if n == "Players" then return Players end
  if n == "MarketplaceService" then return Marketplace end
  if n == "RunService" then return RunService end
  return any
end }
workspace = any
local realRequire = require
require = function(n)
  if type(n) == "table" and rawget(n, "__path") then
    local p = rawget(n, "__path")
    if CACHE[p] == nil then
      local f = SOURCES[p]
      CACHE[p] = if f == nil then any else f(node(p))
    end
    return CACHE[p]
  end
  return realRequire(n)
end
local WARNS = {}
warn = function(...) local t = {}; for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end; table.insert(WARNS, table.concat(t, " ")) end
print_ = print
'''

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local function approx(a, b, tol) return a ~= nil and math.abs(a - b) <= tol end

local MC = require(node("Shared/Configs/MonetizationConfig"))
local AC = require(node("Shared/Configs/AnalyticsConfig"))
local SC = require(node("Shared/Configs/SecurityConfig"))
local FIRST = MC.FirstOffer

-- one fresh MonetizationService per scenario (module state is per require)
local LOGS = {}
local function freshService(firstEnabled)
  CACHE["Server/Services/MonetizationService"] = nil
  CACHE["Server/Modules/OfferLedger"] = nil
  resetClock()
  REMOTES = {}
  CLIENT_HANDLERS = {}
  Players.PLAYERS = {}
  Players.PlayerRemoving = signal()
  LOGS = {}
  FIRST.Enabled = firstEnabled
  local profiles, loaded = {}, {}
  local DataService = {
    GetProfile = function(p) return profiles[p.UserId] end,
    MarkDirty = function() end,
    IsLoaded = function() return true end,
    OnProfileLoaded = function(fn) table.insert(loaded, fn) end,
  }
  local Analytics = { Log = function(name, uid, props) table.insert(LOGS, { Name = name, Uid = uid, Props = props or {}, T = NOW }) end }
  local MS = require(node("Server/Services/MonetizationService"))
  MS.Init({ DataService = DataService, AnalyticsService = Analytics, RemoteSetup = RemoteSetup,
    RateLimitService = { Allow = function() return true end }, NotificationService = { Notify = function() end },
    EconomyService = any, BattlePassService = any, BaseService = nil, SoldierService = nil })
  local function join(uid, profile)
    local p, hum = newPlayer(uid)
    profiles[uid] = profile
    for _, fn in ipairs(loaded) do fn(p, profile) end
    return p, hum
  end
  return MS, join
end

local function newProfile(tutDone)
  return { TutorialComplete = tutDone, TutorialStep = if tutDone then 8 else 2, StarterBundleOffered = false,
    Entitlements = {}, Stats = { PlayTimeSeconds = 0 }, FirstJoinUnix = 1790000000, Level = 1, BaseUpgrades = {} }
end

--[[ the mock client: NotificationController + ShopController v153 rules for the Starter card.
     state() -> { driving = bool, combat = bool }; answer = "normal" | "refuse" | "silent" ]]
local function mockClient(player, state, answer, rec)
  CLIENT_HANDLERS["StarterBundleOffer"] = function(_, payload)
    table.insert(rec.sends, { T = NOW, AckId = payload.AckId, First = payload.First })
    if answer == "silent" then return end
    local ack = payload.AckId
    local function reply(result)
      if ack == nil then return end
      REMOTES["OfferResult"].OnServerEvent:Fire(player, "StarterBundle", result, ack)
    end
    if answer == "refuse" then reply("refused"); return end
    local queuedAt = NOW
    local function pump()
      local s = state()
      -- First offer: held for driving / active combat (and modal / dead / alert), NOT for the tutorial card
      if not s.driving and not s.combat then
        table.insert(rec.shown, NOW)
        reply("shown")
        return
      end
      if NOW > queuedAt + 60 then
        table.insert(rec.dropped, NOW)
        reply("dropped")
        return
      end
      task.delay(0.5, pump)
    end
    pump()
  end
  -- the fallback toast (Speed Boost) is one-shot on the old path: record it
  CLIENT_HANDLERS["SpeedBoostOffer"] = function(_, payload) table.insert(rec.fallback, { T = NOW, Key = payload.ProductKey, Reason = payload.Reason }) end
end
local function newRec() return { sends = {}, shown = {}, dropped = {}, fallback = {} } end

-- ═════════ OLD (FirstOffer off = the v152 rules) ═════════
do
  local MS, join = freshService(false)
  local prof = newProfile(false)
  local p = join(1001, prof)
  local rec = newRec()
  local driving = false
  mockClient(p, function() return { driving = driving, combat = false } end, "normal", rec)
  runUntil(120)
  check(MS.ClaimSoftOfferSlot(p) == false, "OLD: at 120 s with the tutorial not done, no offer slot (quiet until the tutorial or 900 s)")
  -- the tutorial ends at 170 s in the 4x4; the old after-tutorial send (TutorialService waited up to 300 s seated,
  -- then sent; the client then held it while driving and dropped it after 60 s)
  prof.TutorialComplete = true
  driving = true
  runUntil(173)
  CLIENT_HANDLERS["StarterBundleOffer"] = function(_, payload)
    table.insert(rec.sends, { T = NOW, AckId = payload.AckId })
    table.insert(rec.dropped, NOW + 60) -- the v152 client: held (Driving) and dropped after 60 s, no answer
  end
  local sent = MS.TrySoftOfferStarterBundle(p, "tutorial_complete")
  check(sent == true and prof.StarterBundleOffered == true and #rec.sends == 1 and rec.sends[1].AckId == nil,
    "OLD: sent at 173 s and StarterBundleOffered=true AT SEND (no AckId: the client never confirms)")
  runUntil(900)
  driving = false
  local again = MS.TrySoftOfferStarterBundle(p, "session")
  check(again == nil and #rec.shown == 0, "OLD: dropped unseen at 233 s, and the gate refuses it forever after (root cause)")
end

-- ═════════ A: new player on foot, tutorial NOT done ═════════
do
  local MS, join = freshService(true)
  local prof = newProfile(false)
  local p = join(2001, prof)
  local rec = newRec()
  mockClient(p, function() return { driving = false, combat = false } end, "normal", rec)
  MS.ScheduleFirstOffer(p, "first_offer", FIRST.AtPlaySeconds) -- what TutorialService does at load (every player now)
  runUntil(119)
  check(#rec.sends == 0, "A: nothing before 120 s of play")
  check(MS.ClaimSoftOfferSlot(p) == false, "A: no soft-offer slot before 120 s (quiet window)")
  runUntil(125)
  check(#rec.sends == 1 and approx(rec.sends[1].T, 120, 1.5) and rec.sends[1].First == true and rec.sends[1].AckId ~= nil,
    string.format("A: Starter Pack sent at %.1f s with the tutorial NOT done (First, AckId)", rec.sends[1] and rec.sends[1].T or -1))
  check(#rec.shown == 1 and prof.StarterBundleOffered == true, "A: shown at once on foot; StarterBundleOffered set by the 'shown' answer")
  local shownLog = nil
  for _, l in ipairs(LOGS) do if l.Name == "OFFER_SHOWN" then shownLog = l end end
  check(shownLog ~= nil and shownLog.Props.productKey == "StarterBundle", "A: OFFER_SHOWN logged with productKey=StarterBundle")
  runUntil(1200)
  check(#rec.sends == 1, "A: sent exactly once in 20 minutes")
end

-- ═════════ B: driving the 4x4 at 120 s, a short fight after getting out ═════════
do
  local MS, join = freshService(true)
  local prof = newProfile(false)
  local p, hum = join(3001, prof)
  local rec = newRec()
  local driving, combat = false, false
  mockClient(p, function() return { driving = driving, combat = combat } end, "normal", rec)
  MS.ScheduleFirstOffer(p, "first_offer", FIRST.AtPlaySeconds)
  runUntil(100); driving = true; hum.SeatPart = inst("VehicleSeat", {})
  runUntil(149)
  check(#rec.sends == 0, "B: seated at 120 s: the server waits (SeatedWaitSeconds " .. FIRST.SeatedWaitSeconds .. ")")
  runUntil(152)
  check(#rec.sends == 1 and approx(rec.sends[1].T, 150, 1.5), string.format("B: still seated at 150 s: sent anyway (%.1f s)", rec.sends[1] and rec.sends[1].T or -1))
  check(prof.StarterBundleOffered == false, "B: NOT marked at send")
  runUntil(215)
  check(#rec.dropped == 1 and #rec.shown == 0 and prof.StarterBundleOffered == false,
    string.format("B: the client held it (driving) and dropped it at %.1f s; still unmarked", rec.dropped[1] or -1))
  check(MS.SoftOfferSlotWait(p) == 0, "B: the dropped offer's soft-offer slot was refunded (no 240 s cooldown)")
  runUntil(250); driving = false; hum.SeatPart = nil
  runUntil(254); combat = true
  runUntil(259); combat = false
  runUntil(270)
  local s2 = rec.sends[2]
  check(s2 ~= nil and approx(s2.T, rec.dropped[1] + FIRST.RequeueSeconds, 1.5),
    string.format("B: re-queued %d s after the drop (sent again at %.1f s)", FIRST.RequeueSeconds, s2 and s2.T or -1))
  check(#rec.shown == 1 and rec.shown[1] >= 259 and rec.shown[1] <= 260.5 and prof.StarterBundleOffered == true,
    string.format("B: in a fight at the re-send: deferred a few seconds, shown at %.1f s when calm, then marked", rec.shown[1] or -1))
  runUntil(1800)
  check(#rec.sends == 2 and #rec.shown == 1, "B: nothing more after it was shown")
end

-- ═════════ C: a client that always refuses (spam guard) ═════════
do
  local MS, join = freshService(true)
  local prof = newProfile(false)
  local p = join(4001, prof)
  local rec = newRec()
  mockClient(p, function() return { driving = false, combat = false } end, "refuse", rec)
  MS.ScheduleFirstOffer(p, "first_offer", FIRST.AtPlaySeconds)
  runUntil(3600)
  local minGap = math.huge
  for i = 2, #rec.sends do minGap = math.min(minGap, rec.sends[i].T - rec.sends[i - 1].T) end
  check(#rec.sends == FIRST.MaxSendsPerSession, string.format("C: at most MaxSendsPerSession=%d sends a session (got %d)", FIRST.MaxSendsPerSession, #rec.sends))
  check(minGap >= FIRST.RequeueSeconds - 0.01, string.format("C: sends >= %d s apart (min %.1f)", FIRST.RequeueSeconds, minGap))
  check(prof.StarterBundleOffered == false, "C: never shown = never marked (next session tries again)")
end

-- ═════════ D: the client never answers ═════════
do
  local MS, join = freshService(true)
  local prof = newProfile(false)
  local p = join(5001, prof)
  local rec = newRec()
  mockClient(p, function() return { driving = false, combat = false } end, "silent", rec)
  MS.ScheduleFirstOffer(p, "first_offer", FIRST.AtPlaySeconds)
  runUntil(120 + FIRST.AckTimeoutSeconds + FIRST.RequeueSeconds + 3)
  check(#rec.sends == 2 and approx(rec.sends[2].T - rec.sends[1].T, FIRST.AckTimeoutSeconds + FIRST.RequeueSeconds, 1.5),
    "D: no answer: re-queued AckTimeoutSeconds + RequeueSeconds later")
  check(prof.StarterBundleOffered == false, "D: unanswered = unmarked")
end

-- ═════════ E: Starter Pack already owned → the best cheap offer ═════════
do
  local MS, join = freshService(true)
  local prof = newProfile(true)
  prof.Entitlements.StarterBundle = true
  prof.Entitlements.AutoCollect = true
  local p = join(6001, prof)
  local rec = newRec()
  mockClient(p, function() return { driving = false, combat = false } end, "normal", rec)
  MS.ScheduleFirstOffer(p, "first_offer", FIRST.AtPlaySeconds)
  runUntil(200)
  check(#rec.sends == 0 and #rec.fallback == 1 and rec.fallback[1].Key == "SpeedBoost" and approx(rec.fallback[1].T, 121.5, 2),
    string.format("E: owner of the Starter Pack: the 99 R$ Speed Boost offer instead, at %.1f s", rec.fallback[1] and rec.fallback[1].T or -1))
  MS.ScheduleFirstOffer(p, "first_offer", 0)
  runUntil(2000)
  check(#rec.fallback == 1, "E: the fallback is one-shot (SpeedBoostOffered)")
end

-- ═════════ F: politeness (cooldown + session max unchanged) ═════════
do
  local MS, join = freshService(true)
  local prof = newProfile(false)
  local p = join(7001, prof)
  local rec = newRec()
  mockClient(p, function() return { driving = false, combat = false } end, "normal", rec)
  MS.ScheduleFirstOffer(p, "first_offer", FIRST.AtPlaySeconds)
  runUntil(180)
  check(MS.ClaimSoftOfferSlot(p) == false, "F: 60 s after the shown Starter Pack, no 2nd offer (240 s cooldown)")
  runUntil(120 + MC.SoftOfferSessionCooldownSeconds + 1)
  check(MS.ClaimSoftOfferSlot(p) == true, "F: 2nd offer allowed after the 240 s cooldown")
  runUntil(120 + 2 * MC.SoftOfferSessionCooldownSeconds + 2)
  check(MS.ClaimSoftOfferSlot(p) == true, "F: 3rd after another 240 s")
  runUntil(120 + 4 * MC.SoftOfferSessionCooldownSeconds)
  check(MS.ClaimSoftOfferSlot(p) == false and MS.SoftOfferSlotWait(p) == nil, "F: never a 4th (SoftOfferSessionMax 3)")
end

-- ═════════ G: analytics keys + the OfferResult schema ═════════
do
  local MS, join = freshService(true)
  local p = join(8001, newProfile(true))
  runUntil(5)
  LOGS = {}
  REMOTES["RequestPurchaseDevProduct"].OnServerEvent:Fire(p, "StarterBundle", "starter_offer")
  REMOTES["RequestPurchaseGamePass"].OnServerEvent:Fire(p, "AutoCollect", "offer")
  local dp, gp
  for _, l in ipairs(LOGS) do
    if l.Name == "SHOP_PROMPT" and l.Props.kind == "DevProduct" then dp = l.Props end
    if l.Name == "SHOP_PROMPT" and l.Props.kind == "GamePass" then gp = l.Props end
  end
  local field = AC.Roblox.Custom.SHOP_PROMPT.Field
  check(dp ~= nil and dp[field] == "StarterBundle", "G: ProductPrompted (DevProduct) carries " .. tostring(field) .. "=StarterBundle")
  check(gp ~= nil and gp[field] == "AutoCollect", "G: ProductPrompted (GamePass) carries " .. tostring(field) .. "=AutoCollect")
  local C = AC.Roblox.Custom
  check(C.PASS_OWNED and C.PASS_OWNED.Name == "PassBought" and C.PASS_OWNED.Field == "productKey" and C.PASS_OWNED.Value == "price", "G: PASS_OWNED -> custom PassBought (value price, field productKey)")
  check(C.OFFER_SHOWN and C.OFFER_SHOWN.Field == "productKey" and C.OFFER_RESULT and C.OFFER_RESULT.Field == "productKey", "G: OfferShown / OfferDropped custom events")
  local src = SOURCES_TEXT_MS
  check(string.find(src, "PASS_OWNED, player.UserId, {\n\t\t\t\t\tkey = passKey,\n\t\t\t\t\tproductKey = passKey,", 1, true) ~= nil, "G: the PASS_OWNED log sends productKey")
  -- schema: the client's exact call passes, junk is rejected (enforced mode for the check)
  local Gate = require(node("Server/Modules/RemoteGate"))
  local rejected = {}
  Gate._log = function(...) table.insert(rejected, table.concat({ ... }, " ")) end
  local prevRollout = SC.RemoteGate.Rollout
  SC.RemoteGate.Rollout = "all"
  Gate._Reset()
  local okCall = Gate.Check(p, "OfferResult", "StarterBundle", "shown", 3)
  local badCall = Gate.Check(p, "OfferResult", string.rep("x", 40), "shown", 3)
  local badArgs = Gate.Check(p, "OfferResult", "StarterBundle", "shown", 3, "extra")
  SC.RemoteGate.Rollout = prevRollout
  check(okCall == true and badCall == false and badArgs == false, "G: OfferResult schema: the client's call passes, a 40-char key / extra args are rejected")
end

print(string.format("FIRST OFFER TEST: %d failed", fails))
if fails > 0 then error("failed") end
'''


def main():
    chunks = [PRELUDE]
    for key, path in MODS.items():
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
    ms = (SV / "Services/MonetizationService.luau").read_text(encoding="utf-8")
    chunks.append("SOURCES_TEXT_MS = %s" % ("[==========[" + ms + "]==========]"))
    chunks.append(TEST)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True)
    out = (r.stdout + r.stderr).strip()
    print(out if os.environ.get("VERBOSE") else ("\n".join(l for l in out.splitlines() if l.startswith("FAIL") or l.startswith("FIRST OFFER TEST")) or out))
    os.unlink(path)
    if r.returncode != 0 or "FIRST OFFER TEST: 0 failed" not in out:
        sys.exit(1)


if __name__ == "__main__":
    main()
