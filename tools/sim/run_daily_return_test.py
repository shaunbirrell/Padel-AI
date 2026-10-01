"""claude-bud JOB 49: reasons to come back, with the REAL MissionService / RetentionService / ProfileSchema / configs in the
Luau CLI on a FAKE UTC clock (stand-ins: run_kit_detail_test.PRELUDE; the services around them are recording stubs).

A. STREAK: days 1-7 in a row and 7 -> 1; two claims on one day pay once; a claim at 23:59:59 and one at 00:00:00 UTC;
   one missed day with Grace on (kept, the SAVED mark, used once per cycle) and off (reset); two missed days (reset);
   a second miss in the same cycle (reset); Day 7 income-scaled >= the floor (and the floor at no income); the strip's
   real countdown to the next UTC day; a save + ProfileSchema.Migrate round trip keeps the grace bookkeeping.
B. OFFLINE (RetentionService.ComputeOffline / the load payout): 4 min (nothing), 1 h, exactly the cap, 30 h (capped),
   negative / future gap, rejoin spam (paid once per load), Premium once, CapBoost off = today's cap, CapBoost on (test
   only) = 2x, the Welcome back payload; the maths at 3 income levels.
C. MISSIONS (MissionConfig.Core): 3 core missions of 3 different types, stable within the day, reset at ResetHourUtc,
   progress survives a rejoin, "Raid" counts, the raid mission is swapped when no raid is possible, the all-3 chest
   once, the free reroll once a day, the Robux reroll Id 0 never prompts.
OFF == OLD for every new block.
Run: LUAU=path/to/luau(.exe) python tools/sim/run_daily_return_test.py   (exit 1 on any failure; VERBOSE=1 prints all)"""
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
CFG = ["MissionConfig", "DailyRewardConfig", "AchievementConfig", "DailyOpsConfig", "AnalyticsConfig", "BankRaidConfig",
       "AdminConfig", "RetentionConfig", "EconomyConfig", "TutorialConfig", "TerritoryConfig", "MonetizationConfig",
       "BaseConfig", "BaseLayoutConfig", "BusinessConfig", "SoldierConfig", "CombatConfig", "CombatFairnessConfig",
       "GameConfig", "DevConfig", "WeaponConfig", "VehicleConfig", "SeasonConfig", "NationConfig", "CheckpointGuardConfig",
       "ShopOverhaulConfig", "RaidConfig", "MapConfig", "WorldConfig", "OpsConfig", "HudConfig", "ArmyOrdersConfig",
       "RivalConfig"]
MODS = {"Constants": SH / "Constants.luau", "Types": SH / "Types.luau", "Util/PlotFrame": SH / "Util/PlotFrame.luau",
        "Util/ConsoleLocator": SH / "Util/ConsoleLocator.luau",
        "Modules/ProfileSchema": SV / "Modules/ProfileSchema.luau", "Modules/RemoteGuard": SV / "Modules/RemoteGuard.luau",
        "Services/MissionService": SV / "Services/MissionService.luau",
        "Services/RetentionService": SV / "Services/RetentionService.luau"}
for c in CFG:
    p = SH / ("Configs/%s.luau" % c)
    if p.is_file():
        MODS["Configs/" + c] = p

EXTRA = r'''
CLOCK = 1800000000 - (1800000000 % 86400) + 12 * 3600 -- a UTC noon
local realOs = os
os = { time = function(t) if t ~= nil then return realOs.time(t) end return CLOCK end, date = realOs.date, clock = function() return CLOCK end, difftime = realOs.difftime }
local queue = {}
task = {
  delay = function(s, fn, ...) local a = table.pack(...); table.insert(queue, { at = CLOCK + (s or 0), fn = function() fn(table.unpack(a, 1, a.n)) end }) end,
  defer = function(fn, ...) local a = table.pack(...); table.insert(queue, { at = CLOCK, fn = function() fn(table.unpack(a, 1, a.n)) end }) end,
  spawn = function(fn, ...) fn(...) end,
  wait = function(s) CLOCK += (s or 0) end,
}
function runTo(t)
  local guard = 0
  while guard < 10000 do
    guard += 1
    table.sort(queue, function(a, b) return a.at < b.at end)
    local e = queue[1]
    if e == nil or e.at > t then break end
    table.remove(queue, 1)
    CLOCK = math.max(CLOCK, e.at)
    e.fn()
  end
  CLOCK = math.max(CLOCK, t)
end
local function signal() local s = { fns = {} }; s.Connect = function(self, fn) table.insert(self.fns, fn); return { Disconnect = function() end } end; s.Fire = function(self, ...) for _, f in ipairs(self.fns) do f(...) end end; return s end
local function mkPlayer(uid, name) local p = { UserId = uid, Name = name, Parent = true, CharacterAdded = signal(), Character = nil, MembershipType = "None", __attr = {} }
  p.SetAttribute = function(self, k, v) self.__attr[k] = v end; p.GetAttribute = function(self, k) return self.__attr[k] end; return p end
OWNER = mkPlayer(470626172, "shaunie6")
OTHER = mkPlayer(1234, "rookie99")
BYUID = { [OWNER.UserId] = OWNER, [OTHER.UserId] = OTHER }
local Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return { OWNER, OTHER } end,
  GetPlayerByUserId = function(_, uid) return BYUID[uid] end }
local RunService = { IsStudio = function() return false end }
local DSS = { GetDataStore = function() return { UpdateAsync = function() end } end }
local prevGame = game
game = { GetService = function(_, n)
  if n == "Players" then return Players elseif n == "RunService" then return RunService elseif n == "DataStoreService" then return DSS end
  return prevGame:GetService(n) end }
Enum.MembershipType = { Premium = "Premium", None = "None" }

LOG = { push = {}, cash = {}, gold = {}, xp = {}, ev = {}, notify = {}, pending = {} }
PROFILES = {}
local loaded = {}
local remote = { IsA = function(_, c) return c == "RemoteEvent" end, OnServerEvent = signal(),
  FireClient = function(_, p, a, b) table.insert(LOG.push, { p = p, kind = if type(a) == "string" then a else "State", data = if type(a) == "string" then b else a }) end }
PER_MIN = 0 -- the stub income per minute (MonetizationService.PassivePerMin)
DEPS = {
  RemoteSetup = { Get = function() return remote end },
  DataService = { GetProfile = function(p) return PROFILES[p.UserId] end, MarkDirty = function() end,
    OnProfileLoaded = function(cb) table.insert(loaded, cb) end },
  NotificationService = { Notify = function(p, msg) table.insert(LOG.notify, msg) end },
  RateLimitService = { Allow = function() return true end },
  EconomyService = {
    AddCash = function(p, n, why) table.insert(LOG.cash, { n = n, why = why }); PROFILES[p.UserId].Cash += n; return true end,
    AddGold = function(p, n, why) table.insert(LOG.gold, { n = n, why = why }) end,
    AccruePendingCash = function(p, n, why) table.insert(LOG.pending, { n = n, why = why }); PROFILES[p.UserId].PendingCash = (PROFILES[p.UserId].PendingCash or 0) + n; return true end,
    GetCashMult = function() return 1 end,
  },
  XPService = { AddXP = function(p, n, why) table.insert(LOG.xp, { n = n, why = why }) end },
  AnalyticsService = { Log = function(ev, uid, props) table.insert(LOG.ev, { ev = ev, uid = uid, props = props }) end, Onboard = function() end },
  BaseService = { ComputePassiveIncomePerTick = function() return PER_MIN / 60 * 5 end, GetUpgradeChangedEvent = function() return { Event = signal() } end },
}
-- MonetizationService.PassivePerMin stand-in (the real one reads BaseService / EconomyService the same way)
SOURCES["Services/MonetizationService"] = function(script) return { PassivePerMin = function() return PER_MIN end } end
function boot()
  for k in pairs(CACHE) do if k:match("^Services/") then CACHE[k] = nil end end
  loaded = {}
  table.clear(queue)
  local MS = require(node("Services/MissionService"))
  local RS = require(node("Services/RetentionService"))
  MS.Init(DEPS)
  RS.Init(DEPS)
  return MS, RS
end
function newProfile(p, extra)
  local PS = require(node("Modules/ProfileSchema"))
  local pr = PS.CreateDefault()
  pr.FirstJoinUnix = CLOCK - 3 * 86400
  pr.Cash = 10000
  pr.Level = 10
  pr.TutorialComplete = true
  for k, v in pairs(extra or {}) do pr[k] = v end
  PROFILES[p.UserId] = pr
  return pr
end
function clearLog() for k in pairs(LOG) do LOG[k] = {} end end
function evCount(name) local n = 0; for _, e in ipairs(LOG.ev) do if e.ev == name then n += 1 end end; return n end
function lastEv(name) local r = nil; for _, e in ipairs(LOG.ev) do if e.ev == name then r = e.props end end; return r end
function cashBy(why) local n = 0; for _, c in ipairs(LOG.cash) do if c.why == why then n += c.n end end; return n end
function day(n) CLOCK += n * 86400 end
'''

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local DR = require(node("Configs/DailyRewardConfig"))
local PS = require(node("Modules/ProfileSchema"))
local MS, RS = boot()

-- ── A. STREAK ──
check(DR.Grace.OwnerFirst == false and DR.Day7Scale.OwnerFirst == false and DR.Calendar.OwnerFirst == false, "A flags: Grace / Day7Scale / Calendar live for everyone (codebot_v177: OwnerFirst=false)")
local pr = newProfile(OWNER)
clearLog()
local got = {}
for d = 1, 7 do
  local ok = MS.ClaimDailyLogin(OWNER, true)
  table.insert(got, string.format("%d:%s", pr.DailyLogin.Streak, if ok then "ok" else "no"))
  if d < 7 then day(1) end
end
check(table.concat(got, ",") == "1:ok,2:ok,3:ok,4:ok,5:ok,6:ok,7:ok", "days 1-7 in a row: " .. table.concat(got, ","))
local paid = cashBy("daily")
local want = 0
for d = 1, 7 do want += DR.Rewards[d].Cash end
check(paid == want, "PER_MIN 0 -> Day 7 pays the table floor: total $" .. paid .. " (want $" .. want .. ")")
day(1); MS.ClaimDailyLogin(OWNER, true)
check(pr.DailyLogin.Streak == 1 and pr.DailyLogin.Cycle == 2, "after Day 7 the next day is Day 1 of a new cycle (cycle " .. tostring(pr.DailyLogin.Cycle) .. ")")
local c0 = #LOG.cash
local again = MS.ClaimDailyLogin(OWNER, true)
check(again == false and #LOG.cash == c0, "two claims on one day pay once")
-- 23:59:59 then 00:00:00 UTC
local p2 = newProfile(OWNER)
CLOCK = CLOCK - (CLOCK % 86400) + 86399
MS.ClaimDailyLogin(OWNER, true)
CLOCK += 1
local okMid = MS.ClaimDailyLogin(OWNER, true)
check(okMid == true and p2.DailyLogin.Streak == 2, "a claim at 23:59:59 and one at 00:00:00 UTC: two days, streak 2")
CLOCK += 12 * 3600
-- grace on: one missed day keeps the streak, marked SAVED, once per cycle
local g = newProfile(OWNER)
MS.ClaimDailyLogin(OWNER, true); day(1); MS.ClaimDailyLogin(OWNER, true); day(1); MS.ClaimDailyLogin(OWNER, true) -- day 3
clearLog()
day(2) -- missed one day
MS.ClaimDailyLogin(OWNER, true)
check(g.DailyLogin.Streak == 4 and g.DailyLogin.GraceDay == 4 and g.DailyLogin.GraceUsedCycle == g.DailyLogin.Cycle and lastEv("STREAK_CLAIMED").grace == "yes",
  "Grace ON: one missed day keeps the streak (day 3 -> 4), the day is marked SAVED, StreakClaimed grace=yes")
local strip = nil
MS.Push(OWNER)
for _, e in ipairs(LOG.push) do if e.kind == "State" and type(e.data) == "table" and e.data.Streak7 then strip = e.data.Streak7 end end
check(strip ~= nil and strip.GraceDay == 4, "the strip carries the SAVED day (" .. tostring(strip and strip.GraceDay) .. ")")
check(strip ~= nil and strip.NextClaimUnix == DR.NextClaimUnix(CLOCK) and strip.ServerNow == CLOCK and strip.NextClaimUnix - strip.ServerNow == 86400 - (CLOCK % 86400),
  "the strip's countdown is the server's real time to the next UTC day (" .. tostring(strip and (strip.NextClaimUnix - strip.ServerNow)) .. " s)")
day(2) -- a second miss in the same cycle
MS.ClaimDailyLogin(OWNER, true)
check(g.DailyLogin.Streak == 1 and evCount("STREAK_RESET") == 1 and lastEv("STREAK_RESET").lastDay == 4, "a second miss in the same cycle resets to Day 1 (StreakReset lastDay 4)")
-- two missed days: reset even with grace
local g2 = newProfile(OWNER)
MS.ClaimDailyLogin(OWNER, true); day(1); MS.ClaimDailyLogin(OWNER, true)
day(3)
MS.ClaimDailyLogin(OWNER, true)
check(g2.DailyLogin.Streak == 1, "two missed days reset to Day 1 (grace allows 1)")
-- grace off == old hard reset
DR.Grace.Enabled = false
local g3 = newProfile(OWNER)
MS.ClaimDailyLogin(OWNER, true); day(1); MS.ClaimDailyLogin(OWNER, true)
day(2)
MS.ClaimDailyLogin(OWNER, true)
check(g3.DailyLogin.Streak == 1 and g3.DailyLogin.GraceDay == nil, "Grace OFF: one missed day resets (today's hard reset)")
DR.Grace.Enabled = true
-- codebot_v177: launched for everyone (OwnerFirst=false); the owner-first rule is still proved with OwnerFirst = true
local o4 = newProfile(OTHER)
MS.ClaimDailyLogin(OTHER, true); day(1); MS.ClaimDailyLogin(OTHER, true)
day(2)
MS.ClaimDailyLogin(OTHER, true)
check(o4.DailyLogin.Streak > 1, "codebot_v177: grace is live for another player (OwnerFirst=false, one missed day saved)")
DR.Grace.OwnerFirst = true
local o3 = newProfile(OTHER)
MS.ClaimDailyLogin(OTHER, true); day(1); MS.ClaimDailyLogin(OTHER, true)
day(2)
MS.ClaimDailyLogin(OTHER, true)
check(o3.DailyLogin.Streak == 1, "owner-first (OwnerFirst = true): grace is not live for another player (reset)")
DR.Grace.OwnerFirst = false
-- Day 7 income-scaled
PER_MIN = 900 -- $900 / min
local s7 = newProfile(OWNER)
for d = 1, 7 do MS.ClaimDailyLogin(OWNER, true); if d < 7 then day(1) end end
local d7 = LOG.cash[#LOG.cash].n
check(d7 == math.max(DR.Rewards[7].Cash, 900 * DR.Day7Scale.IncomeMinutes), string.format("Day 7 income-scaled: $900/min x %d min = $%d (floor $%d)", DR.Day7Scale.IncomeMinutes, d7, DR.Rewards[7].Cash))
DR.Day7Scale.Enabled = false
newProfile(OWNER)
for d = 1, 7 do MS.ClaimDailyLogin(OWNER, true); if d < 7 then day(1) end end
check(LOG.cash[#LOG.cash].n == DR.Rewards[7].Cash, "Day7Scale OFF: Day 7 pays the table exactly")
DR.Day7Scale.Enabled = true
PER_MIN = 0
-- the grace bookkeeping survives a save
local saved = PS.Migrate(g)
check(saved.DailyLogin.Cycle == g.DailyLogin.Cycle and saved.DailyLogin.GraceUsedCycle == g.DailyLogin.GraceUsedCycle, "the grace bookkeeping survives a save + ProfileSchema.Migrate")
-- Calendar off: no countdown, no SAVED mark
DR.Calendar.Enabled = false
clearLog(); MS.Push(OWNER)
local s0 = nil
for _, e in ipairs(LOG.push) do if e.kind == "State" and type(e.data) == "table" and e.data.Streak7 then s0 = e.data.Streak7 end end
check(s0 ~= nil and s0.NextClaimUnix == nil and s0.GraceDay == nil, "Calendar OFF: no countdown and no SAVED mark (the JOB 29 strip)")
DR.Calendar.Enabled = true

-- the first streak card of a new player: after the onboarding hold, at the latest at FirstCardSeconds (Calendar)
local function firstCardAt(calendarOn)
  DR.Calendar.Enabled = calendarOn
  local fp = newProfile(OWNER, { TutorialComplete = false, FirstJoinUnix = CLOCK })
  fp.DailyLogin = { LastClaimDay = 0, Streak = 0, LastClaimUnix = 0 }
  MS, RS = boot(); clearLog()
  OWNER:SetAttribute("WE_Onboarding", true) -- held for the whole Guided chain (never released here)
  local t0 = CLOCK
  for _, cb in ipairs(loaded) do cb(OWNER, fp) end
  runTo(CLOCK + 400)
  local at = nil
  for _, e in ipairs(LOG.push) do if e.kind == "Streak" and at == nil then at = e.at end end
  OWNER:SetAttribute("WE_Onboarding", nil)
  DR.Calendar.Enabled = true
  return fp.DailyLogin.LastClaimUnix - t0
end
local tOn, tOff = firstCardAt(true), firstCardAt(false)
check(tOn >= DR.Calendar.FirstCardSeconds - 1 and tOn <= DR.Calendar.FirstCardSeconds + 1, string.format("Calendar ON: a held new player's first streak claim + card at %d s (FirstCardSeconds %d; the client still waits out combat)", tOn, DR.Calendar.FirstCardSeconds))
check(tOff >= 97 and tOff <= 99, string.format("Calendar OFF: the JOB 29 timing (8 s + 90 s hold cap = %d s)", tOff))

-- ── B. OFFLINE ──
local EC = require(node("Configs/EconomyConfig"))
local O = EC.OfflineEarnings
check(O.Card.OwnerFirst == false and O.CapBoost.Enabled == false and O.CapBoost.OwnerFirst == true and O.CapBoost.CapMult == 2,
  "B flags: the Welcome back card is live for everyone (codebot_v177); the CapBoost sidegrade hook is DISABLED (Enabled = false, OwnerFirst = true)")
local MC = require(node("Configs/MonetizationConfig"))
local row = MC.DevProducts.OfflineCap2x
check(row ~= nil and row.Id == 0 and row.RobuxPrice == nil and row.HideFromShop == true and row.GrantEntitlement == "OfflineCap2x",
  "B: DevProducts.OfflineCap2x has Id 0, NO price, hidden (never prompted / never in the Shop)")
local function offlineLoad(p, gap, extra)
  local op = newProfile(p, extra)
  op.PrevSeenUnix = if gap == nil then nil else CLOCK - gap
  MS, RS = boot(); clearLog()
  for _, cb in ipairs(loaded) do cb(p, op) end
  runTo(CLOCK + 200)
  local paid = 0
  for _, e in ipairs(LOG.pending) do if e.why == "offline" then paid += e.n end end
  local card = nil
  for _, e in ipairs(LOG.push) do if e.kind == "WelcomeBack" then card = e.data end end
  return paid, card, op
end
PER_MIN = 600 -- $10/s
local perSec = PER_MIN / 60
local capS = O.CapSeconds
local function want(sec) return math.floor(perSec * math.min(sec, capS) * O.Share) end
local p1 = offlineLoad(OWNER, 4 * 60)
check(p1 == 0, "4 min away (< MinSeconds " .. O.MinSeconds .. " s): nothing")
local p2, c2 = offlineLoad(OWNER, 3600)
check(p2 == want(3600) and c2 ~= nil and c2.Cash == p2 and c2.Capped == false and c2.Collect == true and c2.CapHours == capS // 3600,
  "1 h away: $" .. p2 .. " into the ATM, card: Collect $" .. tostring(c2 and c2.Cash) .. ", not capped, cap " .. tostring(c2 and c2.CapHours) .. " h")
local p3, c3 = offlineLoad(OWNER, capS)
check(p3 == want(capS) and c3 and c3.Capped == true, "exactly the cap (" .. capS // 3600 .. " h): $" .. p3 .. ", capped")
local p4, c4 = offlineLoad(OWNER, 30 * 3600)
check(p4 == want(capS) and c4 and c4.Capped == true and c4.Seconds == capS, "30 h away: capped at " .. capS // 3600 .. " h ($" .. p4 .. ")")
check(offlineLoad(OWNER, -500) == 0, "a negative gap (future LastSeen): nothing")
check(offlineLoad(OWNER, nil) == 0, "first join (no LastSeen): nothing")
-- rejoin spam: one payout per load (PrevSeenUnix cleared), and a rejoin inside MinSeconds pays nothing
local paidA, _, opA = offlineLoad(OWNER, 3600)
for _, cb in ipairs(loaded) do cb(OWNER, opA) end
runTo(CLOCK + 200)
local paidB = 0
for _, e in ipairs(LOG.pending) do if e.why == "offline" then paidB += e.n end end
check(paidA > 0 and paidB == paidA and opA.PrevSeenUnix == nil, "the same load hook firing twice pays once (PrevSeenUnix is cleared after the first)")
check(offlineLoad(OWNER, 120) == 0, "a rejoin after 2 min (server hop / spam) pays nothing (MinSeconds)")
-- Premium applied once
OWNER.MembershipType = "Premium"
local pp = offlineLoad(OWNER, 3600)
OWNER.MembershipType = "None"
check(pp == math.floor(perSec * 3600 * O.Share * (1 + O.PremiumBonus)), "Premium: +" .. math.floor(O.PremiumBonus * 100) .. "% once ($" .. pp .. ")")
-- CapBoost: off = today's cap even with the entitlement; on (test only) = 2x
local pOff = offlineLoad(OWNER, 30 * 3600, { Entitlements = { OfflineCap2x = true } })
check(pOff == want(capS), "CapBoost OFF: the entitlement changes nothing (cap " .. capS // 3600 .. " h)")
O.CapBoost.Enabled = true
local pOn, cOn = offlineLoad(OWNER, 30 * 3600, { Entitlements = { OfflineCap2x = true } })
local pOnNo = offlineLoad(OWNER, 30 * 3600)
O.CapBoost.Enabled = false
check(pOn == math.floor(perSec * capS * 2 * O.Share) and cOn and cOn.CapHours == 2 * capS // 3600 and pOnNo == want(capS),
  "CapBoost ON (test only): 2x the cap TIME with the entitlement ($" .. pOn .. "), Share unchanged; without it the normal cap")
-- the card OFF == the JOB 29 card
O.Card.Enabled = false
local _, cOld = offlineLoad(OWNER, 3600)
O.Card.Enabled = true
check(cOld ~= nil and cOld.Collect == nil and cOld.CapHours == nil, "Card OFF: the JOB 29 payload exactly (no Collect / CapHours)")
check(evCount("OFFLINE_EARNED") == 1, "OfflineEarned logged once per payout")
-- the maths at 3 income levels (8 h cap x Share)
local lines = {}
for _, pm in ipairs({ 60, 1000, 20000 }) do
  table.insert(lines, string.format("$%d/min -> 1 h $%d, cap (%d h) $%d", pm, math.floor(pm / 60 * 3600 * O.Share), capS // 3600, math.floor(pm / 60 * capS * O.Share)))
end
print("MATHS offline: " .. table.concat(lines, " | "))
PER_MIN = 0

--@@B@@

--@@C@@

print(string.format("DAILY RETURN TEST: %d failed", fails))
if fails > 0 then error("failed") end
'''


def main():
    chunks = [PRELUDE, EXTRA]
    for key, path in MODS.items():
        src = path.read_text(encoding="utf-8")
        if key == "Services/MissionService":
            # the stand-in tree has no IsA on module nodes: the optional ActivityAnchors lookup is skipped (test copy only)
            src = src.replace('if m and m:IsA("ModuleScript") then', "if false then")
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, src))
    chunks.append(TEST)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True)
    out = r.stdout.strip()
    keep = ("FAIL", "DAILY RETURN TEST", "MATHS")
    print(out if os.environ.get("VERBOSE") else ("\n".join(l for l in out.splitlines() if l.startswith(keep)) or out))
    if r.returncode != 0:
        print(r.stderr.strip()[-2500:])
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
