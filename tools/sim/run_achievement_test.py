"""claude-bud JOB 34: real-code tests in the Luau CLI for achievements, chat shout-outs and badges (stand-ins:
run_kit_detail_test.PRELUDE; the services around AchievementService are recording stubs).

1. CONFIG (the real AchievementConfig): every brief achievement is there once; ids / orders / Stat-or-Event are
   sound; BadgeId = 0 everywhere (Code Bot fills them); the Command Center target = BaseConfig's max level; no key
   names / "click" / nation words in any chat line.
2. ORDINALS ("1st" ... "111th") and the dotted stat reader.
3. OWNER-FIRST (RunService:IsStudio = false): the owner is live, another player is not (the old path runs for him).
4. FIRST CHECK = QUIET BACKFILL: an old profile's reached achievements are granted with rewards, analytics
   backfill = true and one toast; no popup, no chat line.
5. EACH FIRES ONCE: re-checks grant nothing and pay nothing again.
6. A LIVE UNLOCK: popup to the earner, the reward, one chat line to EVERYONE (FireAllClients "AchShout" with the name,
   the text and Big), and the page state.
7. REJOIN: the profile goes through the real ProfileSchema.Migrate (a save/load round trip) into a FRESH service
   instance: nothing fires again; AchievementsAt / AchievementsSeeded survive.
8. EVENTS: the first NPC kill (Note "KillNPC"), a weekly crown with its board label, a player kill re-checking
   LB.Kills after the delay.
9. REBIRTH: a milestone (R5) shouts once with "5th"; a non-milestone rebirth (R6) still gets the big line
   (AnnounceEveryRebirth); never twice for the same rebirth.
10. RATE LIMIT: a player's lines inside CombineSeconds merge ("(+2 more)"); two players' lines go out at least
    GapSeconds apart; a full queue drops small lines and keeps big ones.
11. BADGES: BadgeId 0 = BadgeService never called; a non-zero id checks UserHasBadgeAsync, retries a failed
    AwardBadge, never awards a badge the player already has.
12. THE CLIENT line format (the real AchievementController.Format / Escape / RewardLine).
Run: LUAU=path/to/luau(.exe) python tools/sim/run_achievement_test.py   (exit 1 on any failure)"""
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
CL = ROOT / "src/StarterPlayer/StarterPlayerScripts/Client"
MODS = {
    "Constants": SH / "Constants.luau",
    "Types": SH / "Types.luau",
    "Configs/AchievementConfig": SH / "Configs/AchievementConfig.luau",
    "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
    "Configs/AnalyticsConfig": SH / "Configs/AnalyticsConfig.luau",
    "Configs/BaseConfig": SH / "Configs/BaseConfig.luau",
    "Configs/EconomyConfig": SH / "Configs/EconomyConfig.luau",
    "Configs/SoldierConfig": SH / "Configs/SoldierConfig.luau",
    "Configs/VehicleConfig": SH / "Configs/VehicleConfig.luau",
    "Configs/WeaponConfig": SH / "Configs/WeaponConfig.luau",
    "Configs/SeasonConfig": SH / "Configs/SeasonConfig.luau",
    "Configs/NationConfig": SH / "Configs/NationConfig.luau",
    "Modules/ProfileSchema": SV / "Modules/ProfileSchema.luau",
    "Services/AchievementService": SV / "Services/AchievementService.luau",
    "Client/AchievementController": CL / "Controllers/AchievementController.luau",
}

EXTRA = r'''
-- tasks run when the test says so (runTasks); task.wait advances the fake clock
NOW = 1000
local pending = {}
task = {
  spawn = function(fn, ...) local a = table.pack(...); table.insert(pending, function() fn(table.unpack(a, 1, a.n)) end) end,
  delay = function(_, fn, ...) local a = table.pack(...); table.insert(pending, function() fn(table.unpack(a, 1, a.n)) end) end,
  defer = function(fn, ...) local a = table.pack(...); table.insert(pending, function() fn(table.unpack(a, 1, a.n)) end) end,
  wait = function(s) NOW += (s or 0) end,
}
function runTasks() local guard = 0; while #pending > 0 and guard < 500 do guard += 1; local f = table.remove(pending, 1); f() end end
local function signal() local s = { fns = {} }; s.Connect = function(self, fn) table.insert(self.fns, fn); return { Disconnect = function() end } end; s.Fire = function(self, ...) for _, f in ipairs(self.fns) do f(...) end end; return s end
local function mkPlayer(uid, name) return { UserId = uid, Name = name, Parent = true } end
OWNER = mkPlayer(470626172, "shaunie6")
OTHER = mkPlayer(1234, "rookie99")
local Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return { OWNER, OTHER } end, LocalPlayer = OTHER }
local RunService = { IsStudio = function() return false end }
BADGE = { has = {}, awarded = {}, calls = 0, failNext = 0 }
local BadgeService = {
  UserHasBadgeAsync = function(_, uid, bid) BADGE.calls += 1; return BADGE.has[uid .. ":" .. bid] == true end,
  AwardBadge = function(_, uid, bid) BADGE.calls += 1; if BADGE.failNext > 0 then BADGE.failNext -= 1; error("HTTP 500") end
    BADGE.has[uid .. ":" .. bid] = true; table.insert(BADGE.awarded, uid .. ":" .. bid); return true end,
}
local prevGame = game
game = { GetService = function(_, n)
  if n == "Players" then return Players elseif n == "RunService" then return RunService elseif n == "BadgeService" then return BadgeService end
  return prevGame:GetService(n) end }
-- recording stand-ins for the services around AchievementService
LOG = { client = {}, all = {}, cash = {}, gold = {}, xp = {}, analytics = {}, notify = {} }
PROFILES = {}
local remote = { IsA = function(_, c) return c == "RemoteEvent" end, OnServerEvent = signal(),
  FireClient = function(_, p, kind, data) table.insert(LOG.client, { p = p, kind = kind, data = data }) end,
  FireAllClients = function(_, kind, data) table.insert(LOG.all, { kind = kind, data = data, at = NOW }) end }
DEPS = {
  RemoteSetup = { Get = function() return remote end },
  DataService = { GetProfile = function(p) return PROFILES[p.UserId] end, MarkDirty = function() end, OnProfileLoaded = function() end },
  EconomyService = { AddCash = function(p, n, why) table.insert(LOG.cash, { p = p, n = n, why = why }) end,
    AddGold = function(p, n, why) table.insert(LOG.gold, { p = p, n = n, why = why }) end },
  XPService = { AddXP = function(p, n, why) table.insert(LOG.xp, { p = p, n = n, why = why }) end },
  AnalyticsService = { Log = function(ev, uid, props) table.insert(LOG.analytics, { ev = ev, uid = uid, props = props }) end },
  NotificationService = { Notify = function(p, msg, kind) table.insert(LOG.notify, { p = p, msg = msg, kind = kind }) end },
  SoldierService = { OnArmyChanged = function(cb) ARMYCB = cb end },
}
function freshService()
  CACHE["Services/AchievementService"] = nil
  local AS = require(node("Services/AchievementService"))
  AS._SetClock(function() return NOW end)
  AS.Init(DEPS)
  return AS
end
function count(list, pred) local n = 0; for _, v in ipairs(list) do if pred(v) then n += 1 end end; return n end
function clearLog() for k in pairs(LOG) do LOG[k] = {} end end
'''

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local AC = require(node("Configs/AchievementConfig"))
local BC = require(node("Configs/BaseConfig"))
local PS = require(node("Modules/ProfileSchema"))

-- ── 1. config ──
local BRIEF = { "FirstKillNPC", "FirstPlayerKill", "PlayerKills10", "PlayerKills100", "Cash100k", "Cash1M", "Cash100M",
  "FirstUpgrade", "CommandCenterMax", "FirstOutpost", "PlazaCaptured", "Rebirth1", "Rebirth5", "Rebirth10", "Rebirth20",
  "FirstNuke", "Army50", "Streak7", "WeeklyCrown" }
for _, id in ipairs(BRIEF) do
  local d = AC.Achievements[id]
  check(d ~= nil and d.Shout ~= nil, "brief achievement " .. id .. " exists and has a chat line")
end
local orders, n = {}, 0
for id, d in pairs(AC.Achievements) do
  n += 1
  check(d.Id == id, id .. ": Id matches its key")
  check(orders[d.Order] == nil, id .. ": page order " .. d.Order .. " is unique")
  orders[d.Order] = true
  check((d.Stat ~= nil and d.Target ~= nil) ~= (d.Event ~= nil), id .. ": exactly one of Stat+Target / Event")
  check(d.BadgeId == 0, id .. ": BadgeId 0 (Code Bot creates the badge)")
  check(d.RewardCash >= 0 and d.RewardGold >= 0 and d.RewardXP >= 0 and d.RewardCash <= 100000 and d.RewardGold <= 40, id .. ": a small reward")
  local s = string.lower(d.Shout or "")
  check(not (s:find("click") or s:find("press") or s:find("%[e%]") or s:find("tap ")), id .. ": no key / click words in the chat line")
end
check(n == 21, "21 achievements (19 from the brief, First Building = the original First Brick, + War Chest / Sergeant): " .. n)
check(AC.Achievements.CommandCenterMax.Target == BC.Structures.CommandCenter.MaxLevel, "Command Center target = BaseConfig max level " .. tostring(BC.Structures.CommandCenter.MaxLevel))
check(AC.Live.Enabled == true and AC.Live.OwnerFirst == true, "kill switch on, owner-first")

-- ── 2. helpers ──
local AS = freshService()
local ords = {}
for _, k in ipairs({ 1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 101, 111, 112 }) do table.insert(ords, AS.Ordinal(k)) end
check(table.concat(ords, " ") == "1st 2nd 3rd 4th 11th 12th 13th 21st 22nd 23rd 101st 111th 112th", "ordinals: " .. table.concat(ords, " "))
check(AS.StatValue({ Stats = { TotalCashEarned = 5 } }, "Stats.TotalCashEarned") == 5 and AS.StatValue({}, "LB.Kills") == 0 and AS.StatValue({ Level = 7 }, "Level") == 7, "dotted stat reader")

-- ── 3. owner-first ──
check(AS.LiveFor(OWNER.UserId) == true and AS.LiveFor(OTHER.UserId) == false, "owner live, other player not (not Studio)")
PROFILES[OTHER.UserId] = { Achievements = {}, Stats = { TotalCashEarned = 5e6 } }
check(AS.Check(OTHER) == false and next(PROFILES[OTHER.UserId].Achievements) == nil, "not live: Check returns false (MissionService's old path runs) and grants nothing")

-- ── 4. first check = quiet backfill ──
local owner = PS.CreateDefault()
owner.Stats.TotalCashEarned = 2500000
owner.Stats.UpgradesPurchased = 30
owner.Level = 100
owner.Prestige = 3
owner.LB = { Kills = 12 }
owner.Achievements = { FirstUpgrade = true } -- the old path already granted this one
PROFILES[OWNER.UserId] = owner
clearLog()
check(AS.Check(OWNER) == true, "live: Check handles it")
local A = owner.Achievements
local want = { "Cash10k", "Cash100k", "Cash1M", "Level10", "Rebirth1", "FirstPlayerKill", "PlayerKills10" }
local allIn = true
for _, id in ipairs(want) do if A[id] ~= true then allIn = false; print("  missing " .. id) end end
check(allIn, "backfill granted every reached achievement")
check(A.Cash100M == nil and A.Rebirth5 == nil and A.PlayerKills100 == nil and A.FirstKillNPC == nil, "backfill grants nothing unreached (and no event ones)")
check(owner.AchievementsSeeded == true and typeof(owner.AchievementsAt) == "table" and owner.AchievementsAt.Cash1M ~= nil, "seeded flag + unlock times saved")
check(count(LOG.client, function(e) return e.kind == "AchUnlocked" end) == 0, "backfill: no popups")
runTasks()
check(count(LOG.all, function(e) return e.kind == "AchShout" end) == 0, "backfill: no chat lines")
check(#LOG.notify == 1 and LOG.notify[1].msg:find("7 achievements unlocked") ~= nil, "backfill: one toast (" .. tostring(LOG.notify[1] and LOG.notify[1].msg) .. ")")
-- cash rewards among the 7: War Chest, Six Figures, Millionaire, Duelist, Hunter (Sergeant / Reborn pay gold only)
check(#LOG.cash == 5 and count(LOG.cash, function(e) return e.why == "achievement" end) == 5 and #LOG.gold == 6, "backfill rewards paid as \"achievement\" cash / gold: " .. #LOG.cash .. " / " .. #LOG.gold)
check(count(LOG.analytics, function(e) return e.ev == "ACHIEVEMENT_UNLOCKED" and e.props.backfill == true end) == 7, "analytics per unlock (backfill = true)")

-- ── 5. once ──
clearLog()
AS.Check(OWNER); AS.Check(OWNER); runTasks()
check(#LOG.cash == 0 and #LOG.gold == 0 and #LOG.analytics == 0 and #LOG.all == 0, "re-checks grant and pay nothing")

-- ── 6. a live unlock ──
clearLog()
owner.Stats.TotalCashEarned = 100000000
AS.Check(OWNER)
local pop = nil
for _, e in ipairs(LOG.client) do if e.kind == "AchUnlocked" then pop = e end end
check(pop ~= nil and pop.p == OWNER and pop.data.Title == "War Tycoon" and pop.data.Cash == 100000, "popup to the earner with the reward")
check(count(LOG.cash, function(e) return e.n == 100000 and e.why == "achievement" end) == 1, "reward paid once")
check(count(LOG.client, function(e) return e.kind == "AchState" end) == 1, "page state pushed")
runTasks()
local sh = LOG.all[1]
check(#LOG.all == 1 and sh.kind == "AchShout" and sh.data.Name == "shaunie6" and sh.data.Text == "has earned $100,000,000!" and sh.data.Big == true,
  "one chat line to EVERY player: " .. tostring(sh and sh.data.Name) .. " " .. tostring(sh and sh.data.Text))
check(count(LOG.analytics, function(e) return e.props.id == "Cash100M" and e.props.backfill == false end) == 1, "analytics for the live unlock")

-- ── 7. rejoin through the real ProfileSchema ──
local function deep(t) if type(t) ~= "table" then return t end local c = {} for k, v in pairs(t) do c[k] = deep(v) end return c end
local saved = deep(owner)
local loaded = PS.Migrate(saved)
check(loaded.Achievements.Cash100M == true and loaded.AchievementsSeeded == true and loaded.AchievementsAt.Cash100M == owner.AchievementsAt.Cash100M, "Achievements / AchievementsAt / AchievementsSeeded survive a save + Migrate")
PROFILES[OWNER.UserId] = loaded
local AS2 = freshService()
clearLog()
AS2.Check(OWNER); runTasks()
check(#LOG.cash == 0 and #LOG.all == 0 and #LOG.notify == 0 and count(LOG.client, function(e) return e.kind == "AchUnlocked" end) == 0, "after a rejoin nothing fires again (fresh service instance)")
local bad = PS.Migrate({ AchievementsAt = { Cash1M = -5, [7] = 3 }, AchievementsSeeded = "yes" })
check(bad.AchievementsAt.Cash1M == 0 and bad.AchievementsAt[7] == nil and bad.AchievementsSeeded == nil, "Migrate cleans bad achievement fields")
owner = loaded

-- ── 8. events ──
clearLog()
AS2.Note(OWNER, "KillNPC"); AS2.Note(OWNER, "KillNPC")
check(owner.Achievements.FirstKillNPC == true and count(LOG.client, function(e) return e.kind == "AchUnlocked" and e.data.Id == "FirstKillNPC" end) == 1, "first NPC kill fires once")
runTasks()
check(#LOG.all == 1 and LOG.all[1].data.Text == "drew first blood!" and LOG.all[1].data.Big == false, "first NPC kill chat line (small)")
clearLog(); NOW += 10
AS2.Note(OWNER, "Crown", { Label = "MOST KILLS" }); runTasks()
check(owner.Achievements.WeeklyCrown == true and #LOG.all == 1 and LOG.all[1].data.Text == "is #1 on MOST KILLS this week!" and LOG.all[1].data.Big, "weekly crown with its board label (big)")
clearLog(); NOW += 10
owner.LB.Kills = 100
AS2.Note(OWNER, "KillPlayer")
check(owner.Achievements.PlayerKills100 == nil, "a player kill waits for EngagementService's validated count")
runTasks()
check(owner.Achievements.PlayerKills100 == true, "then 100 validated player kills unlocks Warlord")

-- ── 9. rebirth ──
clearLog(); NOW += 10
owner.Prestige = 5
AS2.OnRebirth(OWNER); runTasks()
check(owner.Achievements.Rebirth5 == true and #LOG.all == 1 and LOG.all[1].data.Text == "just REBIRTHED for the 5th time!", "R5: milestone + one line: " .. tostring(LOG.all[1] and LOG.all[1].data.Text))
clearLog(); NOW += 10
AS2.OnRebirth(OWNER); runTasks()
check(#LOG.all == 0, "the same rebirth is never announced twice")
owner.Prestige = 6
AS2.OnRebirth(OWNER); runTasks()
check(#LOG.all == 1 and LOG.all[1].data.Text == "just REBIRTHED for the 6th time!" and LOG.all[1].data.Big, "R6 (no milestone): still the big line")

-- ── 10. rate limit ──
clearLog(); NOW += 10
AS2.Shout(OWNER, "a", false); AS2.Shout(OWNER, "b", false); AS2.Shout(OWNER, "c", true)
AS2.Shout(OTHER, "d", false)
runTasks()
check(#LOG.all == 2, "3 lines from one player merge into 1 (+ the other player's): " .. #LOG.all)
check(LOG.all[1].data.Text == "c (+2 more)" and LOG.all[1].data.Big == true, "merged line keeps the big text: " .. tostring(LOG.all[1] and LOG.all[1].data.Text))
check(LOG.all[2].at - LOG.all[1].at >= AC.Shout.GapSeconds, "lines go out >= GapSeconds apart (" .. tostring(LOG.all[2] and (LOG.all[2].at - LOG.all[1].at)) .. " s)")
local q = {}
for i = 1, AC.Shout.MaxQueue do AS2.Combine(q, { Uid = i, Name = "p", Text = "t", Big = false, Extra = 0, At = 0 }, 0) end
check(AS2.Combine(q, { Uid = 99, Name = "p", Text = "s", Big = false, Extra = 0, At = 0 }, 0) == "dropped", "full queue drops a small line")
check(AS2.Combine(q, { Uid = 98, Name = "p", Text = "B", Big = true, Extra = 0, At = 0 }, 0) == "queued" and #q == AC.Shout.MaxQueue and q[#q].Text == "B", "full queue keeps a big line (drops a small one)")
local q2 = { { Uid = 1, Name = "p", Text = "x", Big = false, Extra = 0, At = 0 } }
check(AS2.Combine(q2, { Uid = 1, Name = "p", Text = "y", Big = false, Extra = 0, At = 0 }, AC.Shout.CombineSeconds + 1) == "queued", "outside CombineSeconds the same player gets a new line")

-- ── 11. badges ──
check(BADGE.calls == 0, "BadgeId 0: BadgeService never called")
AC.Achievements.Army50.BadgeId = 555
AC.Achievements.Streak7.BadgeId = 777
BADGE.failNext = 1
owner.Soldiers = 50
clearLog()
ARMYCB(OWNER); runTasks()
check(owner.Achievements.Army50 == true and BADGE.has["470626172:555"] == true and #BADGE.awarded == 1, "badge awarded after one failed try (retried)")
BADGE.has["470626172:777"] = true
local before = #BADGE.awarded
owner.DailyLogin.Streak = 7
AS2.Check(OWNER); runTasks()
check(owner.Achievements.Streak7 == true and #BADGE.awarded == before, "UserHasBadgeAsync first: an owned badge is not awarded again")
AC.Achievements.Army50.BadgeId = 0; AC.Achievements.Streak7.BadgeId = 0

-- ── 12. client format ──
local C = require(node("Client/AchievementController"))
local line = C.Format("shaunie6", "just REBIRTHED for the 3rd time!", true)
check(line:find("[WAR EMPIRE]", 1, true) ~= nil and line:find("shaunie6", 1, true) ~= nil and line:find("<b>just REBIRTHED for the 3rd time!</b>", 1, true) ~= nil and line:find(AC.Chat.BigColor, 1, true) ~= nil, "chat line: " .. line)
check(C.Escape("<b>&\"") == "&lt;b&gt;&amp;&quot;", "rich text escaped")
check(C.RewardLine({ Cash = 100000, Gold = 15, XP = 500 }) == "+$100,000  +15 Gold  +500 XP" and C.RewardLine({ Gold = 5 }) == "+5 Gold", "popup reward line")

print(string.format("ACHIEVEMENT TEST: %d failed", fails))
if fails > 0 then error("failed") end
'''

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
print(out if os.environ.get("VERBOSE") else ("\n".join(l for l in out.splitlines() if l.startswith("FAIL") or l.startswith("ACHIEVEMENT TEST")) or out))
if r.returncode != 0:
    print(r.stderr.strip()[-2500:])
    sys.exit(1)
