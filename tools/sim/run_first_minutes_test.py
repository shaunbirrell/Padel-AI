"""claude-bud JOB 41 part A: the Guided first minutes, with the REAL TutorialConfig / TutorialService / GuidedService /
ProfileSchema (stand-ins: run_kit_detail_test.PRELUDE; services around them are recording stubs; a fake clock drives
task.delay / task.defer).

1. CHAIN: a new owner profile plays ClaimBase -> CommandCenter -> Income -> RecruitSoldiers -> FirstFight -> Outpost ->
   Reward -> Barracks at a SCRIPTED phone pace (the PACE table below: the seconds a new phone player spends reading,
   walking at WalkSpeed 16 on the thumbstick and tapping; a script, not a measurement). Prints each step time; first
   BUILD <= 20 s; Spawned -> Reward in 180-240 s.
2. RECRUIT MATHS: $10,000 start + $1,500 payout - $1,500 Command Center = $10,000 >= 3 x $500 -> top-up 0; the gap
   formula at low cash; the cap.
3. CAMP: 2 Recruits spawned through CombatService.SpawnNPC with a TargetFilter (him only), leashed, NoRespawn; a
   seeded fight (the real Recruit numbers, the real CombatFairnessConfig curve with the Recruit caps, the real
   StarterRifle / soldier damage; the hit rates of the player and his soldiers are the stated assumptions) over 200
   seeds: the player never dies and is never below 20 s of life; the camp dies.
4. CAPTURE is blocked (GuidedService.Blocking) while a Recruit lives, free after.
5. REWARD paid once (a resume on the Reward step pays nothing again); the banner + coin burst pushes.
6. REJOIN mid-fight resumes at FirstFight with a fresh camp; after MaxCampSpawns the step completes (never a soft-lock).
7. SKIP at every step: the camp is cleared at once and GuidedSkipped { step } is logged.
8. A RETURNING profile (first join 2 days ago / a building / tutorial done) never enters Guided.
9. OFF == OLD: Guided.Enabled = false or not live for the player -> OrderVersion 3, 7 steps, no camp, no Guided event.
10. FUNNEL: every FirstMinutes step logged once, in order, with a time.
(1-10 run with the JOB 48 Hook OFF: they prove OFF == today's v4 chain exactly.)
11. claude-bud JOB 48 THE HOOK (TutorialConfig.Guided.Hook): OrderVersion 5 (11 steps); the reward adds RewardSoldiers
   within the army cap (ArmyGrew); RAID A RIVAL BASE when a rival is allowed (GoalRaidShown -> RaidSent -> RaidWon ->
   the Barracks, NextGoal) with the fast-raid bonus paid once and only inside FastRaidSeconds (no countdown when the
   bonus is 0); the FALLBACK when no rival is allowed (the chip says "Clear hostiles", 2 hostile kills ->
   GoalFallbackWon, or the timeout -> the chain moves on: never a soft-lock); Barracks -> 4x4 -> Open Missions; a v4 save
   migrating to 5 (and back when the Hook goes off); funnel steps 12-16 once each after the unchanged 1-9;
   SessionMilestone at 60/120/180/300/600 s; FtueTimeToFight once; owner-first (another player stays on v4).
Run: LUAU=path/to/luau(.exe) python tools/sim/run_first_minutes_test.py   (exit 1 on any failure; VERBOSE=1 prints all)"""
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
CFG = ["TutorialConfig", "TerritoryConfig", "BaseConfig", "BaseLayoutConfig", "BusinessConfig", "RetentionConfig",
       "AdminConfig", "SoldierConfig", "CombatConfig", "CombatFairnessConfig", "GameConfig", "DevConfig", "WeaponConfig",
       "EconomyConfig", "VehicleConfig", "SeasonConfig", "NationConfig", "AnalyticsConfig", "CheckpointGuardConfig"]
MODS = {"Constants": SH / "Constants.luau", "Types": SH / "Types.luau", "Util/PlotFrame": SH / "Util/PlotFrame.luau",
        "Modules/ProfileSchema": SV / "Modules/ProfileSchema.luau",
        "Services/TutorialService": SV / "Services/TutorialService.luau",
        "Services/GuidedService": SV / "Services/GuidedService.luau"}
for c in CFG:
    MODS["Configs/" + c] = SH / ("Configs/%s.luau" % c)

EXTRA = r'''
NOW, UNIX = 0, 1800000000
local queue = {}
task = {
  delay = function(s, fn, ...) local a = table.pack(...); table.insert(queue, { at = NOW + (s or 0), fn = function() fn(table.unpack(a, 1, a.n)) end }) end,
  defer = function(fn, ...) local a = table.pack(...); table.insert(queue, { at = NOW, fn = function() fn(table.unpack(a, 1, a.n)) end }) end,
  spawn = function(fn, ...) fn(...) end,
  wait = function(s) NOW += (s or 0) end,
}
function runTo(t)
  local guard = 0
  while guard < 10000 do
    guard += 1
    table.sort(queue, function(a, b) return a.at < b.at end)
    local e = queue[1]
    if e == nil or e.at > t then break end
    table.remove(queue, 1)
    NOW = math.max(NOW, e.at)
    e.fn()
  end
  NOW = math.max(NOW, t)
end
local function signal() local s = { fns = {} }; s.Connect = function(self, fn) table.insert(self.fns, fn); return { Disconnect = function() end } end; s.Fire = function(self, ...) for _, f in ipairs(self.fns) do f(...) end end; return s end
local function mkPlayer(uid, name) return { UserId = uid, Name = name, Parent = true, CharacterAdded = signal(), Character = nil } end
OWNER = mkPlayer(470626172, "shaunie6")
OTHER = mkPlayer(1234, "rookie99")
BYUID = { [OWNER.UserId] = OWNER, [OTHER.UserId] = OTHER }
local Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return { OWNER, OTHER } end,
  GetPlayerByUserId = function(_, uid) return BYUID[uid] end }
local RunService = { IsStudio = function() return false end }
local WorkspaceS = { Raycast = function() return nil end }
local Http = { GenerateGUID = function() return "sess-1" end }
local prevGame = game
game = { GetService = function(_, n)
  if n == "Players" then return Players elseif n == "RunService" then return RunService elseif n == "Workspace" then return WorkspaceS
  elseif n == "HttpService" then return Http end
  return prevGame:GetService(n) end }
RaycastParams = { new = function() return {} end }
CFrame.lookAt = CFrame.lookAt or function(p) return CFrame.new(p.X, p.Y, p.Z) end
Enum.RaycastFilterType = { Exclude = "Exclude" }
Enum.Material = setmetatable({}, { __index = function(_, k) return k end })

LOG = { push = {}, cash = {}, ev = {}, funnel = {}, notify = {}, spawned = {}, despawned = {} }
PROFILES = {}
local loaded = {}
local remote = { IsA = function(_, c) return c == "RemoteEvent" end, OnServerEvent = signal(),
  FireClient = function(_, p, a, b) table.insert(LOG.push, { p = p, kind = if type(a) == "string" then a else "Tutorial", data = if type(a) == "string" then b else a }) end }
local npcSeq = 0
DEATH = {}
local upgradeEvent = { Event = signal() }
DEPS = {
  RemoteSetup = { Get = function() return remote end },
  DataService = { GetProfile = function(p) return PROFILES[p.UserId] end, MarkDirty = function() end,
    OnProfileLoaded = function(cb) table.insert(loaded, cb) end },
  NotificationService = { Notify = function(p, msg) table.insert(LOG.notify, msg) end },
  RateLimitService = { Allow = function() return true end },
  EconomyService = { AddCash = function(p, n, why) table.insert(LOG.cash, { n = n, why = why }); PROFILES[p.UserId].Cash += n; return true end },
  CombatService = {
    SpawnNPC = function(tid, cf, opts) npcSeq += 1; local r = { Id = "npc" .. npcSeq, TypeId = tid, Opts = opts }; table.insert(LOG.spawned, r); return r end,
    DespawnNPC = function(id) table.insert(LOG.despawned, id); return true end,
    OnNPCDeath = function(fn) table.insert(DEATH, fn) end,
    EndNoviceShield = function() end,
  },
  AnalyticsService = {
    Log = function(ev, uid, props) table.insert(LOG.ev, { ev = ev, props = props, t = NOW }) end,
    GuidedFunnel = function(p, sid, idx, name, secs) table.insert(LOG.funnel, { sid = sid, idx = idx, name = name, t = NOW }) end,
    Onboard = function() end,
  },
  BaseService = { GetUpgradeChangedEvent = function() return upgradeEvent end },
  -- claude-bud JOB 48 stubs: the army (the recruit state + listeners), the rival verdicts, the plan status
  SoldierService = {
    listeners = {},
    OnArmyChanged = function(cb) table.insert(DEPS.SoldierService.listeners, cb) end,
    GrantFree = function(p, n, why)
      local pr = PROFILES[p.UserId]; local cap = SOLDIER_CAP or 5
      local add = math.clamp(n, 0, math.max(0, cap - (pr.Soldiers or 0)))
      pr.Soldiers = (pr.Soldiers or 0) + add
      table.insert(LOG.ev, { ev = "SOLDIER_GRANT", props = { amount = add, reason = why }, t = NOW })
      for _, cb in ipairs(DEPS.SoldierService.listeners) do cb(p) end
      return add
    end,
  },
  RivalService = { Candidates = function(p) local r = {}; for i = 1, (RIVALS or 0) do r[i] = { PlotId = 4 + i } end; return r, {} end },
  ArmyPlan = { Status = function() return PLAN_STATUS end },
}
function boot()
  for k in pairs(CACHE) do if k:match("^Services/") then CACHE[k] = nil end end
  loaded = {}
  -- claude-bud JOB 48: a boot is a fresh server: the old instance's timers and death listeners go with it
  table.clear(queue)
  table.clear(DEATH)
  local GS = require(node("Services/GuidedService"))
  GS._clock = function() return NOW end
  GS._unix = function() return UNIX end
  local TS = require(node("Services/TutorialService"))
  DEPS.GuidedService = GS
  DEPS.TutorialService = TS
  GS.Init(DEPS)
  TS.Init(DEPS)
  return TS, GS
end
function newProfile(p, extra)
  local PS = require(node("Modules/ProfileSchema"))
  local pr = PS.CreateDefault()
  pr.FirstJoinUnix = UNIX
  pr.BasePlotId = 3
  pr.Cash = 10000
  for k, v in pairs(extra or {}) do pr[k] = v end
  PROFILES[p.UserId] = pr
  return pr
end
function load(p) for _, cb in ipairs(loaded) do cb(p, PROFILES[p.UserId]) end; runTo(NOW) end
function upgrade(p, sid) upgradeEvent.Event:Fire(p.UserId, 3, sid, 1); runTo(NOW) end
function lastTut(p) for i = #LOG.push, 1, -1 do local e = LOG.push[i]; if e.kind == "Tutorial" and e.p == p then return e.data end end end
function killCamp(uid) for _, r in ipairs(LOG.spawned) do if not r.dead and r.Opts.GroupId == "Guided." .. uid then r.dead = true
  for _, fn in ipairs(DEATH) do fn({ Id = r.Id, TypeId = r.TypeId, GroupId = r.Opts.GroupId, ByUnit = false }) end end end; runTo(NOW) end
function clearLog() for k in pairs(LOG) do LOG[k] = {} end end
function evCount(name) local n = 0; for _, e in ipairs(LOG.ev) do if e.ev == name then n += 1 end end; return n end
'''

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local TC = require(node("Configs/TutorialConfig"))
local CC = require(node("Configs/CombatConfig"))
local CF = require(node("Configs/CombatFairnessConfig"))
local SC = require(node("Configs/SoldierConfig"))
local WC = require(node("Configs/WeaponConfig"))
local EC = require(node("Configs/EconomyConfig"))
local BC = require(node("Configs/BaseConfig"))
local PS = require(node("Modules/ProfileSchema"))
local G = TC.Guided

-- claude-bud JOB 48: sections 1-10 run with the Hook OFF (they are today's v4 chain: OFF == OLD)
local HOOK_ENABLED = G.Hook.Enabled
G.Hook.Enabled = false

-- ── 2. recruit maths ──
local ccCost = BC.Structures.CommandCenter.Costs[1]
local afterCC = EC.StartingCash + TC.FastStart.StarterPayout - ccCost
local TS, GS = boot()
check(afterCC >= G.RecruitCount * SC.RecruitCostCash and GS.RecruitGap(afterCC) == 0,
  string.format("recruit maths: $%d start + $%d payout - $%d HQ = $%d >= %d x $%d -> top-up 0", EC.StartingCash, TC.FastStart.StarterPayout, ccCost, afterCC, G.RecruitCount, SC.RecruitCostCash))
check(GS.RecruitGap(1200) == 300 and GS.RecruitGap(0) == 1500 and GS.RecruitGap(-1e9) == G.GuidedRecruitCashMax, "the top-up covers exactly the gap (1200 -> 300), capped at GuidedRecruitCashMax")

-- ── 3. the camp fight (seeded) ──
local R = CC.NPCTypes.Recruit
local function npcChance(d)
  local nearC, farC = math.min(CF.NpcNearHitChance, R.HitChanceNear), math.min(CF.NpcFarHitChance, R.HitChanceFar)
  if d <= CF.NpcNearStuds then return nearC end
  local t = math.clamp((d - CF.NpcNearStuds) / (R.Range - CF.NpcNearStuds), 0, 1)
  return math.max(CF.NpcMinHitChance, nearC + (farC - nearC) * t)
end
local PLAYER_HIT, SOLDIER_HIT, SOLDIER_RATE = 0.35, 0.4, 1.0 -- assumptions: a touch player with aim help, a soldier's
local rifle = WC.Weapons and WC.Weapons.StarterRifle or { Damage = 18, FireRate = 8 }
local worstLife, deaths, maxTtk = math.huge, 0, 0
local ttks = {}
for seed = 1, 200 do
  math.randomseed(seed)
  local hp, npc, t = 100, { R.Health, R.Health }, 0
  local dt = 0.1
  local nextNpc, nextMe, nextSol = { 0.5, 0.5 }, 0, { 0, 0, 0 }
  local dmgTaken = 0
  while (npc[1] > 0 or npc[2] > 0) and hp > 0 and t < 120 do
    t += dt
    for i = 1, 2 do
      if npc[i] > 0 and t >= nextNpc[i] then nextNpc[i] = t + 1 / R.FireRate; if math.random() < npcChance(30) then hp -= R.Damage; dmgTaken += R.Damage end end
    end
    local tgt = if npc[1] > 0 then 1 else 2
    if t >= nextMe then nextMe = t + 1 / rifle.FireRate; if math.random() < PLAYER_HIT then npc[tgt] -= rifle.Damage end end
    for s = 1, 3 do
      if t >= nextSol[s] then nextSol[s] = t + 1 / SOLDIER_RATE; if math.random() < SOLDIER_HIT then npc[tgt] = (npc[tgt] or 0) - SC.SoldierDamage end end
    end
  end
  if hp <= 0 then deaths += 1 end
  maxTtk = math.max(maxTtk, t)
  table.insert(ttks, t)
  -- time he could survive the camp's worst-case fire (both near, every shot at the cap)
  worstLife = 100 / (2 * R.Damage * R.FireRate * npcChance(0))
end
check(deaths == 0, "200 seeded fights (player + 3 soldiers vs 2 Recruits): the player never dies (camp cleared in <= " .. string.format("%.1f", maxTtk) .. " s)")
check(worstLife >= 20, string.format("even with every Recruit shot at its near cap he lives %.1f s (>= 20 s)", worstLife))

table.sort(ttks)
FIGHT_MEDIAN = ttks[math.floor(#ttks / 2)]

-- ── 1 + 10. the chain at a scripted phone pace ──
-- the pace DERIVED from the real layout (BaseLayoutConfig: the Command Center console, the ATM; TerritoryConfig.Starter:
-- the Home Outpost), WalkSpeed 16 with a 1.4 path / thumbstick factor, 4 s to read each banner, one passive tick to
-- wait at the ATM, the seeded fight's median, the real CaptureTimeSeconds
local BL = require(node("Configs/BaseLayoutConfig"))
local TER = require(node("Configs/TerritoryConfig"))
local function lay(id, field) for _, v in pairs(BL) do if type(v) == "table" and type(v[id]) == "table" and v[id][field] ~= nil then return v[id] end end end
local ccRow, atm = lay("CommandCenter", "Console"), lay("Collector", "X")
local cc = { X = ccRow.Site.X + ccRow.Console.X, Z = ccRow.Site.Z + ccRow.Console.Z }
local op = { X = TER.Starter.LocalX, Z = TER.Starter.LocalZ }
local function walk(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2) / 16 * 1.4 end
local READ = 4
local PACE = {
  build = READ + 4, -- FastStart stands him 7 studs from the console
  collect = READ + walk(cc, atm) + EC.PassiveIncome.TickSeconds,
  recruit = READ + 10, -- open Army, 3 recruit taps
  walkFight = READ + walk(atm, op) + FIGHT_MEDIAN,
  capture = TER.Starter.CaptureTimeSeconds + 2,
  rewardToNext = READ + walk(op, cc) + 4,
}
print(string.format("PACE (s): build %.0f, collect %.0f (walk %.0f), recruit %.0f, walk+fight %.0f (walk %.0f, fight median %.1f), capture %.0f",
  PACE.build, PACE.collect, walk(cc, atm), PACE.recruit, PACE.walkFight, walk(atm, op), FIGHT_MEDIAN, PACE.capture))
local pr = newProfile(OWNER)
clearLog()
load(OWNER)
check(pr.TutorialOrderVersion == 4 and lastTut(OWNER).Total == #TC.GuidedSteps and lastTut(OWNER).Id == "CommandCenter", "a new owner profile enters Guided (OrderVersion 4, 9 steps) and lands on the Command Center")
local T = {}
local t0 = NOW
NOW += PACE.build; upgrade(OWNER, "CommandCenter"); T.FirstBuild = NOW - t0
pr.Cash += TC.FastStart.StarterPayout - ccCost
check(lastTut(OWNER).Id == "Income", "BUILD -> Collect cash")
NOW += PACE.collect; TS.Notify(OWNER, "PassiveIncome"); runTo(NOW); T.Collected = NOW - t0
check(lastTut(OWNER).Id == "RecruitSoldiers" and pr.Guided.RecruitTopUp == 0 and #LOG.cash == 0, "Collect -> Recruit (no top-up needed: 0 paid)")
NOW += PACE.recruit; pr.Cash -= 3 * SC.RecruitCostCash; TS.Notify(OWNER, "RecruitSoldiers"); runTo(NOW); T.Recruited = NOW - t0
check(lastTut(OWNER).Id == "FirstFight" and #LOG.spawned == 2, "Recruit -> FIRST FIGHT: 2 camp NPCs spawned")
local sp = LOG.spawned[1]
check(sp.TypeId == "Recruit" and sp.Opts.NoRespawn == true and sp.Opts.Leash ~= nil and sp.Opts.TargetFilter(OWNER) == true and sp.Opts.TargetFilter(OTHER) == false,
  "the camp: Recruit type, NoRespawn, leashed, hostile only to HIM (TargetFilter)")
local hint = false
for _, e in ipairs(LOG.push) do if e.kind == "Hint" and e.data.Kind == "Attack" then hint = true end end
check(hint, "the first ATTACK hint shows at the fight (not after the tutorial)")
-- 4. capture blocked while they live
check(GS.Blocking("Starter_P3") == true and GS.Blocking("Starter_P4") == false, "capture of HIS Home Outpost is blocked while the camp stands (only his)")
NOW += PACE.walkFight; killCamp(OWNER.UserId); T.FirstKill = NOW - t0
check(GS.Blocking("Starter_P3") == false and pr.Guided.CampDone == true and lastTut(OWNER).Id == "Outpost", "both Recruits dead -> CampDone, capture free, step = Capture outpost")
NOW += PACE.capture; pr.StarterOutpostTaken = true; TS.Notify(OWNER, "CaptureTerritory", "Starter_P3"); runTo(NOW); T.Captured = NOW - t0
local paid = 0
for _, c in ipairs(LOG.cash) do if c.why == "onboarding" then paid += c.n end end
local banner, burst = false, false
for _, e in ipairs(LOG.push) do if e.kind == "GuidedReward" then banner = e.data.Title == G.RewardText end; if e.kind == "StarterPayout" then burst = true end end
check(paid == G.GuidedRewardCash and pr.Guided.RewardDone == true and banner and burst, "Capture -> REWARD: $" .. paid .. " once, BASE SECURED! banner + coin burst")
runTo(NOW + 3); T.Reward = NOW - t0
check(lastTut(OWNER).Id == "Barracks", "after the reward the next goal is up (the Barracks): never a blank screen")
NOW += PACE.rewardToNext; upgrade(OWNER, "Barracks"); T.NextBuilding = NOW - t0
print(string.format("STEP TIMES (s): FirstBuild %.0f, Collected %.0f, Recruited %.0f, FirstKill(camp cleared) %.0f, Captured %.0f, Reward %.0f, NextBuilding %.0f",
  T.FirstBuild, T.Collected, T.Recruited, T.FirstKill, T.Captured, T.Reward, T.NextBuilding))
check(T.FirstBuild <= 20, "first BUILD <= 20 s after spawn (" .. string.format("%.0f", T.FirstBuild) .. " s)")
check(T.Reward <= 240, "Spawned -> Reward inside 4 min at the derived pace (" .. string.format("%.0f", T.Reward) .. " s)")
print(string.format("NOTE  the derived pace reaches the Reward in %.0f s: %s the brief's 180-240 s estimate (reported, not padded)",
  T.Reward, if T.Reward < 180 then "FASTER than" else "inside"))
local order = {}
for _, f in ipairs(LOG.funnel) do table.insert(order, f.idx .. ":" .. f.name) end
local want = { "1:Spawned", "2:FirstBuild", "3:Collected", "4:Recruited", "5:FightStarted", "6:FirstKill", "7:Captured", "8:Reward", "9:NextBuilding" }
check(table.concat(order, ",") == table.concat(want, ","), "FirstMinutes funnel once each, in order: " .. table.concat(order, ","))
check(evCount("GUIDED_STEP") == 9 and pr.Guided.SessionId == "sess-1", "GuidedStepSeconds for every step; one funnel session per profile")
-- 5. reward once, across a save + Migrate + resume on the Reward step
local saved = PS.Migrate(PROFILES[OWNER.UserId])
check(saved.Guided.RewardDone == true and saved.Guided.CampDone == true and saved.TutorialOrderVersion == 4, "Guided flags survive a save + ProfileSchema.Migrate")

-- ── 6. rejoin mid-fight, then the never-soft-lock ──
local function toFight(p)
  local q = newProfile(p)
  TS, GS = boot(); clearLog(); load(p)
  upgrade(p, "CommandCenter"); TS.Notify(p, "PassiveIncome"); runTo(NOW + 1); TS.Notify(p, "RecruitSoldiers"); runTo(NOW + 1)
  return q
end
local q = toFight(OWNER)
check(q.Guided.CampSpawns == 1 and lastTut(OWNER).Id == "FirstFight", "at the fight: camp spawn 1")
for n = 2, G.Camp.MaxCampSpawns do
  PROFILES[OWNER.UserId] = PS.Migrate(PROFILES[OWNER.UserId])
  TS, GS = boot(); clearLog(); load(OWNER)
  check(lastTut(OWNER).Id == "FirstFight" and #LOG.spawned == 2 and PROFILES[OWNER.UserId].Guided.CampSpawns == n, "rejoin " .. (n - 1) .. ": resumes at FIRST FIGHT with a fresh camp (spawn " .. n .. ")")
end
PROFILES[OWNER.UserId] = PS.Migrate(PROFILES[OWNER.UserId])
TS, GS = boot(); clearLog(); load(OWNER); runTo(NOW + 1)
local friendly = false
for _, m in ipairs(LOG.notify) do if m == G.CampSkipText then friendly = true end end
check(lastTut(OWNER).Id == "Outpost" and #LOG.spawned == 0 and friendly, "after MaxCampSpawns the fight auto-completes with a friendly line (never a soft-lock)")

-- ── 7. skip at every step ──
for i, def in ipairs(TC.GuidedSteps) do
  if i >= 2 and i <= 7 then
    local p = newProfile(OWNER)
    TS, GS = boot(); clearLog(); load(OWNER)
    local chain = { function() upgrade(OWNER, "CommandCenter") end, function() TS.Notify(OWNER, "PassiveIncome"); runTo(NOW + 1) end,
      function() TS.Notify(OWNER, "RecruitSoldiers"); runTo(NOW + 1) end, function() killCamp(OWNER.UserId) end,
      function() p.StarterOutpostTaken = true; TS.Notify(OWNER, "CaptureTerritory", "Starter_P3"); runTo(NOW) end }
    for k = 1, i - 2 do chain[k]() end
    local at = lastTut(OWNER).Id
    local hadCamp = GS._Camp(OWNER) ~= nil
    TS.Complete(OWNER); runTo(NOW)
    local skipped = nil
    for _, e in ipairs(LOG.ev) do if e.ev == "GUIDED_SKIPPED" then skipped = e.props.step end end
    check(p.TutorialComplete == true and GS._Camp(OWNER) == nil and skipped == at and (not hadCamp or #LOG.despawned == 2),
      "skip at " .. tostring(at) .. ": done, camp cleared" .. (if hadCamp then " (2 despawned)" else "") .. ", GuidedSkipped{" .. tostring(skipped) .. "}")
  end
end

-- ── 8. returning profiles ──
local cases = { { "first join 2 days ago", { FirstJoinUnix = UNIX - 2 * 86400 } }, { "a building", { BaseUpgrades = { ManualDropper = 1 } } },
  { "tutorial done", { TutorialComplete = true } } }
for _, c in ipairs(cases) do
  local p = newProfile(OWNER, c[2])
  TS, GS = boot(); clearLog(); load(OWNER)
  check(p.TutorialOrderVersion ~= 4 and #LOG.spawned == 0 and evCount("GUIDED_STEP") == 0, "returning (" .. c[1] .. "): never enters Guided")
end

-- ── 9. OFF == OLD ──
local launched = G.OwnerFirst
G.OwnerFirst = true -- codebot_v166: launched; the owner-first rule is still proved with OwnerFirst = true
local p9 = newProfile(OTHER)
TS, GS = boot(); clearLog(); load(OTHER)
check(p9.TutorialOrderVersion == TC.OrderVersion and lastTut(OTHER).Total == #TC.Steps and #LOG.funnel == 0, "owner-first rule: not live for another player: OrderVersion " .. TC.OrderVersion .. ", 7 steps, no Guided event")
G.OwnerFirst = launched
check(launched == false and TC.GuidedLiveFor(OTHER.UserId), "codebot_v166: TutorialConfig.Guided live for everyone (OwnerFirst=false)")
local p9b = newProfile(OTHER)
TS, GS = boot(); clearLog(); load(OTHER)
check(p9b.TutorialOrderVersion == 4, "codebot_v166: a new non-owner profile enters Guided (OrderVersion 4, got " .. tostring(p9b.TutorialOrderVersion) .. ")")
G.Enabled = false
local p10 = newProfile(OWNER)
TS, GS = boot(); clearLog(); load(OWNER)
upgrade(OWNER, "CommandCenter"); TS.Notify(OWNER, "PassiveIncome"); runTo(NOW + 1); TS.Notify(OWNER, "RecruitSoldiers"); runTo(NOW + 1)
check(p10.TutorialOrderVersion == TC.OrderVersion and lastTut(OWNER).Id == "Barracks" and #LOG.spawned == 0 and #LOG.funnel == 0, "Guided.Enabled = false: today's order (Recruit -> Barracks), no camp, no funnel")
G.Enabled = true

-- ── 11. claude-bud JOB 48: THE HOOK ──
G.Hook.Enabled = HOOK_ENABLED
local Hk = G.Hook
check(Hk.Enabled == true and Hk.OwnerFirst == true, "Hook flags: Enabled = true, OwnerFirst = true (Code Bot flips it after the phone test)")
local function soldierRecruit(p, n) PROFILES[p.UserId].Soldiers = (PROFILES[p.UserId].Soldiers or 0) + n; for _, cb in ipairs(DEPS.SoldierService.listeners) do cb(p) end end
local function playToReward(p, extra)
  local q = newProfile(p, extra)
  q.Soldiers = 0 -- a fresh army: 3 recruited at the recruit step
  q.FirstJoinUnix = UNIX + NOW
  DEPS.SoldierService.listeners = {}
  TS, GS = boot(); clearLog()
  GS._unix = function() return UNIX + NOW end -- the Hook section: a unix clock that moves (the fast-raid window)
  load(p)
  local t0 = NOW
  NOW += PACE.build; upgrade(p, "CommandCenter")
  NOW += PACE.collect; TS.Notify(p, "PassiveIncome"); runTo(NOW)
  NOW += PACE.recruit; soldierRecruit(p, 3); TS.Notify(p, "RecruitSoldiers"); runTo(NOW)
  NOW += PACE.walkFight; killCamp(p.UserId)
  NOW += PACE.capture; q.StarterOutpostTaken = true; TS.Notify(p, "CaptureTerritory", "Starter_P3"); runTo(NOW)
  runTo(NOW + 3)
  return q, NOW - t0
end
SOLDIER_CAP, RIVALS, PLAN_STATUS = 5, 1, nil
local h, tReward = playToReward(OWNER)
check(h.TutorialOrderVersion == Hk.OrderVersion and #TC.HookSteps == 11, "a new owner profile plays the Hook order (OrderVersion 5, 11 steps)")
check(h.Guided.RewardSoldiers ~= nil and h.Guided.RewardSoldiers.Before == 3 and h.Guided.RewardSoldiers.After == 5,
  string.format("REWARD adds RewardSoldiers within the cap: soldiers %s -> %s (asked %d, cap %d)", tostring(h.Guided.RewardSoldiers and h.Guided.RewardSoldiers.Before), tostring(h.Guided.RewardSoldiers and h.Guided.RewardSoldiers.After), Hk.RewardSoldiers, SOLDIER_CAP))
check(lastTut(OWNER).Id == "RaidRival" and lastTut(OWNER).Title == "Raid a rival base", "after the reward the goal is RAID A RIVAL BASE (a rival is allowed)")
local goalPush = nil
for _, e in ipairs(LOG.push) do if e.kind == "GuidedGoal" then goalPush = e.data end end
check(goalPush ~= nil and goalPush.Goal == "Raid" and goalPush.FastRaidLeft == Hk.FastRaidSeconds - 3 and goalPush.Bonus == Hk.FastRaidBonus,
  "the TARGETS card is outlined (GuidedGoal Raid) with the REAL fast-raid window, counted from the reward 3 s earlier (" .. tostring(goalPush and goalPush.FastRaidLeft) .. " s, bonus $" .. tostring(goalPush and goalPush.Bonus) .. ")")
NOW += 20; GS.OnRaidSent(OWNER); runTo(NOW)
NOW += 90; local cashBefore = #LOG.cash; GS.OnRaidWon(OWNER); runTo(NOW)
local bonusPaid = 0
for i = cashBefore + 1, #LOG.cash do if LOG.cash[i].why == "onboarding" then bonusPaid += LOG.cash[i].n end end
check(bonusPaid == Hk.FastRaidBonus and h.Guided.FastRaidPaid == true, "a raid won 110 s after the reward pays the fast-raid bonus once ($" .. bonusPaid .. ")")
check(lastTut(OWNER).Id == "Barracks", "RaidWon -> the next goal (Barracks)")
GS.OnRaidWon(OWNER); runTo(NOW)
local again = 0
for _, c in ipairs(LOG.cash) do if c.why == "onboarding" and c.n == Hk.FastRaidBonus then again += 1 end end
check(again == 1, "a second raid win pays nothing again (the goal is closed)")
NOW += 30; upgrade(OWNER, "Barracks"); TS.Notify(OWNER, "SpawnVehicle"); runTo(NOW)
check(lastTut(OWNER).Id == "Missions" and lastTut(OWNER).CtaAction == "OpenMissions", "Barracks -> 4x4 -> Open Missions (the MISSIONS button)")
TS.Notify(OWNER, "MissionsOpened"); runTo(NOW)
check(h.TutorialComplete == true, "opening Missions finishes the chain")
local forder = {}
for _, f in ipairs(LOG.funnel) do table.insert(forder, f.idx .. ":" .. f.name) end
local wantH = { "1:Spawned", "2:FirstBuild", "3:Collected", "4:Recruited", "5:FightStarted", "6:FirstKill", "7:Captured", "12:ArmyGrew", "8:Reward",
  "13:GoalRaidShown", "14:RaidSent", "15:RaidWon", "16:NextGoal", "9:NextBuilding" }
check(table.concat(forder, ",") == table.concat(wantH, ","), "funnel: 1-9 unchanged + the Hook's 12-16 once each (ArmyGrew lands as the reward opens, before step 8 closes): " .. table.concat(forder, ","))
local seen = {}
local dup = false
for _, f in ipairs(LOG.funnel) do if seen[f.idx] then dup = true end; seen[f.idx] = true end
check(not dup, "every funnel step logged once")
check(evCount("FTUE_TIME_TO_FIGHT") == 1 and h.Guided.TimeToFight ~= nil, "FtueTimeToFight once (" .. tostring(h.Guided.TimeToFight) .. " s from spawn to the first kill)")
print(string.format("HOOK TIMES (s): FirstKill %d, Reward %.0f (army %d -> %d), raid sent +20 s, raid won +110 s after the reward",
  h.Guided.TimeToFight or -1, tReward, h.Guided.RewardSoldiers.Before, h.Guided.RewardSoldiers.After))
check((h.Guided.TimeToFight or 999) <= 120 and tReward <= 120, "first fight win AND army growth inside 2:00 at the derived pace (fight " .. tostring(h.Guided.TimeToFight) .. " s, reward + soldiers " .. string.format("%.0f", tReward) .. " s)")

-- the army cap: RewardSoldiers never goes above it
SOLDIER_CAP = 4
local hc = playToReward(OWNER)
check(hc.Soldiers == 4 and hc.Guided.RewardSoldiers.After == 4, "RewardSoldiers is clamped to the army cap (cap 4: 3 -> 4)")
SOLDIER_CAP = 3
local hc2 = playToReward(OWNER)
check(hc2.Soldiers == 3 and evCount("SOLDIER_GRANT") == 1, "at the cap no soldier is added (3 -> 3)")
SOLDIER_CAP = 5

-- fast raid outside the window: no bonus; bonus 0: no countdown
local hl = playToReward(OWNER)
NOW += Hk.FastRaidSeconds + 5; local c0 = #LOG.cash; GS.OnRaidWon(OWNER); runTo(NOW)
local late = 0
for i = c0 + 1, #LOG.cash do late += LOG.cash[i].n end
check(late == 0 and hl.Guided.FastRaidPaid ~= true and lastTut(OWNER).Id == "Barracks", "a raid won after FastRaidSeconds wins the goal but pays no bonus")
local bonusWas = Hk.FastRaidBonus
Hk.FastRaidBonus = 0
playToReward(OWNER)
local gp0 = nil
for _, e in ipairs(LOG.push) do if e.kind == "GuidedGoal" then gp0 = e.data end end
check(gp0 ~= nil and gp0.Goal == "Raid" and gp0.FastRaidLeft == nil, "FastRaidBonus = 0: the raid goal shows NO countdown (no fake timer)")
Hk.FastRaidBonus = bonusWas

-- the fallback: no rival allowed
RIVALS = 0
local hf = playToReward(OWNER)
check(hf.Guided.GoalMode == "Fallback" and lastTut(OWNER).Id == "RaidRival" and lastTut(OWNER).Title == Hk.FallbackTitle and lastTut(OWNER).Hint == Hk.FallbackHint,
  "no rival allowed -> FALLBACK goal: the chip says \"" .. tostring(lastTut(OWNER).Title) .. "\"")
check(evCount("GOAL_FALLBACK") == 1, "GoalFallback logged once")
local function hostileKill(p) for _, fn in ipairs(DEATH) do fn({ Id = "ops1", TypeId = "Militia", GroupId = "Town.Bank", Killer = p, ByUnit = false }) end; runTo(NOW) end
hostileKill(OTHER) -- someone else's kill does not count
hostileKill(OWNER)
check(lastTut(OWNER).Id == "RaidRival", "1 of 2 hostile kills: still on the goal")
hostileKill(OWNER)
check(lastTut(OWNER).Id == "Barracks", "2 hostile kills -> GoalFallbackWon -> the Barracks")
local fb = nil
for _, f in ipairs(LOG.funnel) do if f.idx == 15 then fb = f.name end end
check(fb == "GoalFallbackWon", "the fallback win is funnel step 15 named GoalFallbackWon")
-- the fallback timeout (never a soft-lock)
playToReward(OWNER)
runTo(NOW + Hk.FallbackMaxSeconds + 1)
check(lastTut(OWNER).Id == "Barracks", "nothing killed: after FallbackMaxSeconds the chain moves on to the Barracks (never a soft-lock)")
-- a rival appears while the fallback is up: the re-check switches the goal to the raid
playToReward(OWNER)
RIVALS = 2
runTo(NOW + Hk.RecheckSeconds + 1)
check(PROFILES[OWNER.UserId].Guided.GoalMode == "Raid" and lastTut(OWNER).Title == "Raid a rival base", "a rival becomes allowed: the re-check turns the fallback into the raid goal")
RIVALS = 1

-- v4 save -> 5 (Hook on) and 5 -> 4 (Hook off)
local v4 = newProfile(OWNER, { TutorialOrderVersion = 4, TutorialStep = 8 })
v4.Guided = { CampDone = true, RewardDone = true, Funnel = {} }
TS, GS = boot(); clearLog(); load(OWNER)
check(v4.TutorialOrderVersion == 5 and lastTut(OWNER).Id == "RaidRival", "a v4 save past the reward (on the Barracks) resumes on the new raid goal in order 5")
local v4b = newProfile(OWNER, { TutorialOrderVersion = 4, TutorialStep = 5 })
TS, GS = boot(); clearLog(); load(OWNER)
check(v4b.TutorialOrderVersion == 5 and lastTut(OWNER).Id == "FirstFight", "a v4 save mid-fight resumes at the FIRST FIGHT in order 5")
Hk.Enabled = false
local v5 = newProfile(OWNER, { TutorialOrderVersion = 5, TutorialStep = 9 })
TS, GS = boot(); clearLog(); load(OWNER)
check(v5.TutorialOrderVersion == 4 and lastTut(OWNER).Id == "Barracks", "Hook OFF: a v5 save on the Barracks goes back to order 4 on the Barracks")
local p0 = newProfile(OWNER)
TS, GS = boot(); clearLog(); load(OWNER)
check(p0.TutorialOrderVersion == 4 and lastTut(OWNER).Total == 9, "Hook OFF: a new profile plays today's v4 chain (9 steps)")
Hk.Enabled = true
-- owner-first: another player stays on 4
local po = newProfile(OTHER)
TS, GS = boot(); clearLog(); load(OTHER)
check(po.TutorialOrderVersion == 4, "owner-first: a new non-owner profile stays on order 4 (Hook not live for him)")

-- the owner's test-mode replay (Code Bot v163) plays the Hook order while the Hook is live for him
local vr = newProfile(OWNER, { TutorialComplete = true, TutorialStep = 10, FirstJoinUnix = UNIX - 30 * 86400 })
TS, GS = boot(); clearLog(); load(OWNER)
local okR = TS.ReplayGuided(OWNER); runTo(NOW + 1)
check(okR == true and vr.TutorialOrderVersion == Hk.OrderVersion and vr.GuidedReplay ~= nil, "the owner's REPLAY GUIDED (test mode) plays the Hook order 5")
TS.Complete(OWNER); runTo(NOW)

-- SessionMilestone once each per session
clearLog()
TS, GS = boot() -- Init schedules the milestones for every player in the server (OWNER live, OTHER not)
runTo(NOW + 601)
local secs = {}
for _, e in ipairs(LOG.ev) do if e.ev == "SESSION_MILESTONE" then table.insert(secs, e.props.sec) end end
check(table.concat(secs, ",") == "60,120,180,300,600", "SessionMilestone once each at 60/120/180/300/600 s, only for the player the Hook is live for (" .. table.concat(secs, ",") .. ")")

print(string.format("FIRST MINUTES TEST: %d failed", fails))
if fails > 0 then error("failed") end
'''

chunks = [PRELUDE, EXTRA]
for key, path in MODS.items():
    chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
chunks.append(TEST)
with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
    f.write("\n".join(chunks))
    path = f.name
r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True)
out = r.stdout.strip()
keep = ("FAIL", "FIRST MINUTES TEST", "STEP TIMES", "PACE", "NOTE", "HOOK TIMES")
print(out if os.environ.get("VERBOSE") else ("\n".join(l for l in out.splitlines() if l.startswith(keep)) or out))
if r.returncode != 0:
    print(r.stderr.strip()[-2500:])
    sys.exit(1)
