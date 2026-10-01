"""claude-bud JOB 46: the rebirth stations (all 7 zones), on the REAL RebirthZonesConfig, RebirthZoneDressing and
RebirthZoneService.Activity (stand-ins: run_kit_detail_test.PRELUDE; WorldKits is a recording stub; the services around
RebirthZoneService are recording stubs).

1. ROOT CAUSE (static, before the fix = origin/phase-7-polish): the only pre-purchase text was the prompt ObjectText
   ("<Name> $cost") and no client code reads a zone prompt; a bought zone had no activity (only the silo's NUKE).
2. CARD: for every zone and every level 0..3 the card's cost and gains equal the config (Cost, IncomePerTick /
   TickSeconds, Soldiers, MissileReloadCut, AutoCollectSeconds, RaidShieldBonus, SiloCapacity / SiloChargeMinutes) and it
   says what you can do there; the locked sign reads the name + the level-1 gain.
3. DRESSING: every built zone builds a gateway with its name + level, themed props and an activity kiosk panel, all
   Parts / kits (no WE_Building*, no Neon, no lights).
4. ACTIVITY: ship = Shipment.Minutes of the zone's own income, then a cooldown (saved); sweep = the ATM emptied now, then
   a cooldown, nothing on an empty ATM; drill / strike = a ZoneOpen push (Recruits / Missile); nuke = NukeService.OpenPanel;
   nothing before the zone is built.
Run: LUAU=path/to/luau(.exe) python tools/sim/run_rebirth_stations_test.py   (exit 1 on any failure; VERBOSE=1 prints all)"""
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
    "Configs/RebirthZonesConfig": SH / "Configs/RebirthZonesConfig.luau",
    "Configs/RebirthConfig": SH / "Configs/RebirthConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
    "Configs/EconomyConfig": SH / "Configs/EconomyConfig.luau",
    "Configs/WorldSitesConfig": SH / "Configs/WorldSitesConfig.luau",
    "Configs/BaseConfig": SH / "Configs/BaseConfig.luau",
    "Configs/BaseLayoutConfig": SH / "Configs/BaseLayoutConfig.luau",
    "Configs/BusinessConfig": SH / "Configs/BusinessConfig.luau",
    "Util/PlotFrame": SH / "Util/PlotFrame.luau",
    "Modules/RebirthZoneDressing": SV / "Modules/RebirthZoneDressing.luau",
    "Services/RebirthZoneService": SV / "Services/RebirthZoneService.luau",
    "Modules/ZoneRuns": SV / "Modules/ZoneRuns.luau",  # claude-bud JOB 50 A
    "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
}

EXTRA = r'''
task = { spawn = function() end, delay = function() end, defer = function() end, wait = function() end }
OverlapParams = { new = function() return {} end }
Enum.RaycastFilterType = { Exclude = "Exclude" }
local function signal() local s = { fns = {} }; s.Connect = function(self, fn) table.insert(self.fns, fn); return { Disconnect = function() end } end; return s end
BYUID = {}
local Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end, GetPlayerByUserId = function(_, uid) return BYUID[uid] end }
local RunService = { IsStudio = function() return true end }
local prevGame = game
game = { GetService = function(_, n)
  if n == "Players" then return Players elseif n == "RunService" then return RunService end
  return prevGame:GetService(n) end }
KITS = {}
PARTS = {}
SOURCES["Modules/WorldKits"] = function() return {
  NewCluster = function(name) local m = Instance.new("Model"); m.Name = name; return m end,
  Part = function(ps, parent) local p = Instance.new("Part"); p.Name = ps.Name; p.Size = ps.Size; p.CFrame = ps.CFrame; p.Material = ps.Material; p.Parent = parent; table.insert(PARTS, p); return p end,
  Add = function(cl, kitId) table.insert(KITS, kitId); return 1 end,
  Finish = function(cl, parent) cl.Parent = parent; return {} end,
} end
'''

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local ZC = require(node("Configs/RebirthZonesConfig"))
local RC = require(node("Configs/RebirthConfig"))
local EC = require(node("Configs/EconomyConfig"))
local TICK = EC.PassiveIncome.TickSeconds
local function commas(n) local s = tostring(math.floor(n + 0.5)); return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")) end

-- 2. the card for every zone and level
for _, zoneId in ipairs(RC.ZoneOrder) do
  local z = ZC.Zones[zoneId]
  for lv = 0, ZC.MaxLevel do
    local c = ZC.CardFor(zoneId, lv, TICK)
    local nl = math.min(lv + 1, ZC.MaxLevel)
    local want = {}
    local function a(t) return t and t[math.min(nl, #t)] or 0 end
    if a(z.IncomePerTick) > 0 then table.insert(want, "+$" .. commas(a(z.IncomePerTick) / TICK) .. "/s income") end
    if a(z.Soldiers) > 0 then table.insert(want, "+" .. a(z.Soldiers) .. " soldiers") end
    if a(z.MissileReloadCut) > 0 then table.insert(want, "Missile reload -" .. a(z.MissileReloadCut) .. " s") end
    if a(z.AutoCollectSeconds) > 0 then table.insert(want, "Drones empty your ATM every " .. a(z.AutoCollectSeconds) .. " s") end
    if a(z.RaidShieldBonus) > 0 then table.insert(want, "+" .. a(z.RaidShieldBonus) .. " s raid shield") end
    if a(z.SiloCapacity) > 0 then table.insert(want, string.format("Holds %d nuke%s, %d min charge", a(z.SiloCapacity), if a(z.SiloCapacity) == 1 then "" else "s", a(z.SiloChargeMinutes))) end
    local costOk = if lv >= ZC.MaxLevel then c.Cost == nil else c.Cost == z.Cost[lv + 1]
    check(c ~= nil and c.Title == string.upper(z.Name) and costOk and table.concat(c.Gains, "|") == table.concat(want, "|") and #c.Do > 10,
      string.format("%s L%d card: %s | %s | %s | Here: %s", zoneId, lv, c.Title, if c.Cost then "$" .. commas(c.Cost) else "MAX", table.concat(c.Gains, " · "), c.Do))
  end
end

-- 3. the dressing of every zone
local DR = require(node("Modules/RebirthZoneDressing"))
for _, zoneId in ipairs(RC.ZoneOrder) do
  KITS, PARTS = {}, {}
  local folder = Instance.new("Folder")
  local panel = DR.Build(zoneId, 2, CFrame.new(0, 0, 0), 60, Color3.fromRGB(1, 2, 3), folder)
  local hasSign, bad = false, false
  for _, p in ipairs(PARTS) do
    if p.Name == "GateSign" then hasSign = true end
    if string.find(p.Name, "WE_Building") or p.Material == "Material.Neon" then bad = true end
    local z = p.CFrame.Position.Z
    if z < 30 then bad = true end -- never inside the yard (the store-prop rows' space)
  end
  check(panel ~= nil and panel.Name == "ZoneActivityPanel" and hasSign and #PARTS >= 20 and not bad,
    string.format("%s dressing: %d parts + %d kits (%s), gateway sign, activity kiosk; on the apron, no WE_Building* / Neon", zoneId, #PARTS, #KITS, table.concat(KITS, ",")))
end

-- 4. the activities
local S = require(node("Services/RebirthZoneService"))
local PROFILE = { Prestige = 10, RebirthZones = {} }
local LOG = { cash = {}, notes = {}, push = {}, nuke = 0, collect = 0 }
local PENDING = 0
local remote = { IsA = function(_, c) return c == "RemoteEvent" end, FireClient = function(_, p, k, d) table.insert(LOG.push, { k = k, d = d }) end }
S.Init({
  DataService = { GetProfile = function() return PROFILE end, MarkDirty = function() end, OnProfileLoaded = function() end },
  EconomyService = { AddCash = function(p, n, why) table.insert(LOG.cash, { n = n, why = why }) end, GetPendingCash = function() return PENDING end,
    CollectPendingCash = function() LOG.collect += 1; PENDING = 0 end },
  NotificationService = { Notify = function(p, t) table.insert(LOG.notes, t) end },
  RemoteSetup = { Get = function() return remote end },
  NukeService = { OpenPanel = function() LOG.nuke += 1 end },
})
local P = { UserId = 470626172, Name = "shaunie6" }
check(S.Activity(P, "WestYard", 1000) == false, "not built yet: no activity")
PROFILE.RebirthZones = { WestYard = 2, EastStrip = 1, DroneBay = 1, EastYard = 3, WestStrip = 1, StrategicYard = 1, WestFlank = 1 }
local ok1 = S.Activity(P, "WestYard", 1000)
local want = math.floor(ZC.Zones.WestYard.IncomePerTick[2] / TICK * 60 * ZC.Shipment.Minutes)
check(ok1 and #LOG.cash == 1 and LOG.cash[1].n == want and LOG.cash[1].why == "rebirthzone_ship", string.format("SHIP TANKS: +$%d = %d min of the L2 factory income", LOG.cash[1] and LOG.cash[1].n or -1, ZC.Shipment.Minutes))
check(not S.Activity(P, "WestYard", 1000 + 60) and #LOG.cash == 1, "a second shipment within the cooldown: refused (told when)")
check(S.Activity(P, "WestYard", 1000 + ZC.Shipment.CooldownMinutes * 60) and #LOG.cash == 2 and PROFILE.ZoneShipAt.WestYard == 1000 + ZC.Shipment.CooldownMinutes * 60, "after the cooldown it ships again (saved in profile.ZoneShipAt)")
check(not S.Activity(P, "DroneBay") and LOG.collect == 0, "LAUNCH SWEEP on an empty ATM: nothing")
PENDING = 5000
check(S.Activity(P, "DroneBay") and LOG.collect == 1, "LAUNCH SWEEP: the ATM is emptied now")
PENDING = 5000
check(not S.Activity(P, "DroneBay") and LOG.collect == 1, "a second sweep inside the cooldown: refused")
S.Activity(P, "EastYard"); S.Activity(P, "WestStrip")
check(#LOG.push == 2 and LOG.push[1].k == "ZoneOpen" and LOG.push[1].d.Panel == "Recruits" and LOG.push[2].d.Panel == "Missile", "DRILL opens Elite Training, CALL STRIKE opens the missile panel (ZoneOpen)")
S.Activity(P, "StrategicYard")
check(LOG.nuke == 1, "the silo's activity opens the NUKE panel")
check(S.Activity(P, "WestFlank", 5000) and S.Activity(P, "EastStrip", 5000), "SUPPLY RUN / FILL TANKER ship too")

-- ── 5. claude-bud JOB 50 A: the zone runs (the real ZoneRuns; a fake clock; prompts as recording stubs) ──
local ZR = require(node("Modules/ZoneRuns"))
check(ZC.Rebuild.Enabled == true and ZC.Rebuild.OwnerFirst == true, "Rebuild is owner-first (Enabled, OwnerFirst = true)")
local CLK, UNIX, DELAYS = 0, 100000, {}
ZR._clock = function() return CLK end
ZR._unix = function() return UNIX end
ZR._delay = function(sec, fn) table.insert(DELAYS, { at = CLK + sec, fn = fn }) end
local function runDelays() for _, d in ipairs(DELAYS) do if not d.done and d.at <= CLK then d.done = true; d.fn() end end end
Random = Random or { new = function(seed) local x = seed or 1; return { NextInteger = function(_, a, b) x = (x * 1103515245 + 12345) % 2147483648; return a + x % (b - a + 1) end } end }
local PROMPTS = {}
local realNew = Instance.new
Instance.new = function(cls)
  local o = realNew(cls)
  if cls == "ProximityPrompt" then local sig = signal(); o.Triggered = sig; table.insert(PROMPTS, o) end
  return o
end
local RP = { Prestige = 10, RebirthZones = { WestYard = 2, StrategicYard = 1, WestStrip = 1, DroneBay = 1, EastYard = 3, EastStrip = 1, WestFlank = 1 },
  NukeSilo = { Ready = 0, ChargeFrom = UNIX - 60 }, Raid = { StrikeCooldownUntil = UNIX + 600 } }
local RLOG = { cash = {}, notes = {}, push = {}, ev = {}, spawned = {}, despawned = {} }
local rremote = { IsA = function(_, c) return c == "RemoteEvent" end, FireClient = function(_, pl, k, d) table.insert(RLOG.push, { k = k, d = d }) end }
local npcN = 0
ZR.Bind({
  DataService = { GetProfile = function() return RP end, MarkDirty = function() end },
  EconomyService = { AddCash = function(pl, n, why) table.insert(RLOG.cash, { n = n, why = why }) end, GetPendingCash = function() return 0 end, CollectPendingCash = function() end },
  NotificationService = { Notify = function(pl, t) table.insert(RLOG.notes, t) end },
  RemoteSetup = { Get = function() return rremote end },
  AnalyticsService = { Log = function(ev, uid, props) table.insert(RLOG.ev, { ev = ev, props = props }) end },
  CombatService = { SpawnNPC = function(t, cf, o) npcN += 1; local r = { Id = "z" .. npcN, Opts = o }; table.insert(RLOG.spawned, r); return r end,
    DespawnNPC = function(id) table.insert(RLOG.despawned, id) end },
})
local FRAME = CFrame.new(0, 0, 0)
local W, D = 74, 60
local ROOT = Instance.new("Part")
local OWN = { UserId = 470626172, Name = "shaunie6", DisplayName = "Shaun", Character = { FindFirstChild = function() return ROOT end } }
local OTHER = { UserId = 9, Name = "rival", DisplayName = "Rival", Character = { FindFirstChild = function() return ROOT end } }
OWN.SetAttribute = function() end
BYUID[OWN.UserId] = OWN
SOURCES["Services/MonetizationService"] = function() return { PassivePerMin = function() return PERMIN or 0 end } end
local function stand(x, z) ROOT.CFrame = CFrame.new(x, 3, z) end
local function current() return PROMPTS[#PROMPTS] end
local TICK2 = TICK
local function fire(pl) local pr = current(); for _, fn in ipairs(pr.Triggered.fns) do fn(pl) end end
-- a clean PRODUCTION RUN (6 steps) in 18 s
stand(0, D / 2 + 8)
local okS = ZR.Start(OWN, "WestYard", 2, FRAME, W, D, Instance.new("Folder"))
check(okS and ZR.Active(OWN.UserId) ~= nil and current().ActionText == "PICK UP CRATE", "PRODUCTION RUN starts at the kiosk; only step 1 has a prompt (" .. tostring(current() and current().ActionText) .. ")")
fire(OTHER)
check(ZR.Active(OWN.UserId).Step == 1, "another player's trigger never counts")
stand(500, 500)
fire(OWN)
check(ZR.Active(OWN.UserId).Step == 1, "a trigger with him outside the annex never counts (no remote triggering)")
stand(0, D / 2 + 8)
local base = ZC.ShipmentCash("WestYard", 2, TICK2)
for i = 1, 6 do CLK += 3; fire(OWN) end
local paid = RLOG.cash[#RLOG.cash].n
local wantPay = ZC.RunCash("WestYard", 2, TICK2, 18, 60) + base
check(ZR.Active(OWN.UserId) == nil and paid == wantPay and RLOG.cash[#RLOG.cash].why == "rebirthzone_run",
  string.format("6 steps in 18 s: WIN, +$%d = RunCash (%d, speed x%.2f of ShipmentCash %d) + the first-clear bonus %d", paid, ZC.RunCash("WestYard", 2, TICK2, 18, 60), ZC.RunCash("WestYard", 2, TICK2, 18, 60) / base, base, base))
check(RP.ZoneBest.WestYard == 18 and RP.ZoneFirstClear.WestYard == true and RP.ZoneRunAt.WestYard == UNIX, "best 18 s, first clear, cooldown saved in the profile")
check(RLOG.ev[#RLOG.ev].ev == "ZONE_ACTIVITY" and RLOG.ev[#RLOG.ev].props.result == "win" and RLOG.ev[#RLOG.ev].props.payout == paid, "ZoneActivity logged (zone, result, seconds, payout)")
local okC = ZR.Start(OWN, "WestYard", 2, FRAME, W, D, Instance.new("Folder"))
check(okC == false, "inside the cooldown: refused (" .. tostring(RLOG.notes[#RLOG.notes]) .. ")")
UNIX += ZC.RunRules.CooldownMinutes * 60
-- the second run: no first-clear bonus, slower = less
ZR.Start(OWN, "WestYard", 2, FRAME, W, D, Instance.new("Folder"))
for i = 1, 6 do CLK += 8; fire(OWN) end
check(RLOG.cash[#RLOG.cash].n == ZC.RunCash("WestYard", 2, TICK2, 48, 60) and RLOG.cash[#RLOG.cash].n >= base and RP.ZoneBest.WestYard == 18,
  "a slower second run pays less (never below ShipmentCash), no second first-clear bonus, the best stays 18 s")
-- out of time
UNIX += ZC.RunRules.CooldownMinutes * 60
local nCash = #RLOG.cash
ZR.Start(OWN, "WestYard", 2, FRAME, W, D, Instance.new("Folder"))
CLK += 61; runDelays()
check(ZR.Active(OWN.UserId) == nil and #RLOG.cash == nCash and RLOG.ev[#RLOG.ev].props.result == "out of time", "the time limit passes: FAIL, nothing paid, the cooldown starts (no retry spam)")
-- the silo: LAUNCH PREP shortens the charge (the silo has no flat income: its pay is IncomeMinutes of his own income)
PERMIN = 3000
UNIX += ZC.RunRules.CooldownMinutes * 60
local from0 = RP.NukeSilo.ChargeFrom
ZR.Start(OWN, "StrategicYard", 1, FRAME, W, D, Instance.new("Folder"))
for i = 1, 3 do CLK += 2; fire(OWN) end
check(RP.NukeSilo.ChargeFrom == from0 - ZC.Runs.StrategicYard.ChargeCutMinutes * 60 and RLOG.cash[#RLOG.cash].n >= 3000 * ZC.RunRules.IncomeMinutes,
  "LAUNCH PREP: the warhead charge moves on by " .. ZC.Runs.StrategicYard.ChargeCutMinutes .. " min, and it pays $" .. tostring(RLOG.cash[#RLOG.cash].n) .. " (>= " .. ZC.RunRules.IncomeMinutes .. " min of his income)")
-- the artillery: RANGE PRACTICE cuts the missile reload
RP.Raid.StrikeCooldownUntil = UNIX + 600
local cd0 = RP.Raid.StrikeCooldownUntil
ZR.Start(OWN, "WestStrip", 1, FRAME, W, D, Instance.new("Folder"))
for i = 1, 6 do CLK += 2; fire(OWN) end
check(RP.Raid.StrikeCooldownUntil == cd0 - ZC.Runs.WestStrip.ReloadCutSeconds, "RANGE PRACTICE: the missile reload is cut by " .. ZC.Runs.WestStrip.ReloadCutSeconds .. " s")
-- the barracks: beat par -> the army boost
ZR.Start(OWN, "EastYard", 3, FRAME, W, D, Instance.new("Folder"))
for i = 1, 4 do CLK += 5; fire(OWN) end
check((RP.ArmyBoostUntil or 0) == UNIX + ZC.Runs.EastYard.BoostMinutes * 60, "DRILL COURSE in 20 s (par " .. ZC.Runs.EastYard.Par .. "): ARMY BOOST " .. ZC.Runs.EastYard.BoostMinutes .. " min")
-- the refinery: the valves in a shuffled order (the prompt names the next one)
ZR.Start(OWN, "EastStrip", 1, FRAME, W, D, Instance.new("Folder"))
local r = ZR.Active(OWN.UserId)
local order = table.concat(r.Order, ",")
for i = 1, 4 do CLK += 2; fire(OWN) end
check(ZR.Active(OWN.UserId) == nil and RLOG.ev[#RLOG.ev].props.result == "win", "PRESSURE VALVES in the shown order (" .. order .. "): win")
-- the bunker: an NPC wave (CombatService, him only)
ZR.Start(OWN, "WestFlank", 1, FRAME, W, D, Instance.new("Folder"))
local w = ZR.Active(OWN.UserId)
check(#w.NpcIds == 3 and RLOG.spawned[#RLOG.spawned].Opts.TargetFilter(OWN) == true and RLOG.spawned[#RLOG.spawned].Opts.TargetFilter(OTHER) == false,
  "HOLD THE LINE: 3 CombatService NPCs that target only him")
for _, id in ipairs(table.clone(w.NpcIds)) do CLK += 5; ZR.OnNPCDeath({ Id = id, GroupId = "ZoneRun." .. OWN.UserId }) end
check(ZR.Active(OWN.UserId) == nil and RP.BunkerBanner == 1, "all three down in time: WIN, bunker banner stage 1")
-- the drone hangar: RECON FLIGHT (instant): the nearest raidable rival marked (a pin + SEND card), the ATM swept
SOURCES["Services/RivalService"] = function() return { Candidates = function() return { { PlotId = 4, Name = "Rival", Loot = "$12k", Dist = 300 }, { PlotId = 2, Name = "Far", Dist = 900 } }, {} end } end
local nPush = #RLOG.push
local okR = ZR.Start(OWN, "DroneBay", 1, FRAME, W, D, Instance.new("Folder"))
local pushed = RLOG.push[#RLOG.push]
check(okR and #RLOG.push > nPush and pushed.k == "ArmyNearest" and pushed.d.Target == "B:4" and RP.ZoneRunAt.DroneBay == UNIX,
  "RECON FLIGHT: the nearest raidable rival (plot 4) is marked with PIN / SEND (\"B:4\", the JOB 38 path), cooldown saved")
-- the plaque text
local txt = ZR.PlaqueText("Shaun", 1, 18, true, "PRODUCTION RUN")
check(string.find(txt, "UNLOCKED BY SHAUN · REBIRTH 1", 1, true) ~= nil and string.find(txt, "BEST 0:18.0", 1, true) ~= nil and string.find(txt, "ZONE COMMANDER", 1, true) ~= nil,
  "the plaque: UNLOCKED BY SHAUN · REBIRTH 1 / PRODUCTION RUN BEST 0:18.0 / ZONE COMMANDER")
-- the reward formula at 3 incomes (rebirth 1 / 5 / 10 levels)
local lines = {}
for _, lv in ipairs({ 1, 2, 3 }) do table.insert(lines, string.format("L%d $%d..$%d", lv, ZC.ShipmentCash("WestYard", lv, TICK2), ZC.RunCash("WestYard", lv, TICK2, 0, 60))) end
print("MATHS production run (slowest..fastest): " .. table.concat(lines, ", "))
-- OFF == OLD: the kiosk's one tap when Rebuild is off (the service path is section 4 above, with no plot / frame)
ZC.Rebuild.Enabled = false
check(not ZC.RebuildLive(OWN.UserId, "Activities"), "Rebuild OFF: the runs are not live (the JOB 46 one-tap activities exactly)")
ZC.Rebuild.Enabled = true
Instance.new = realNew

-- ── 6. claude-bud JOB 50 B: the runs' props + the annex edge, per zone ──
local LIGHTS = 0
local rn = Instance.new
Instance.new = function(cls) local o = rn(cls); if cls == "PointLight" or cls == "SpotLight" or cls == "SurfaceLight" then LIGHTS += 1; o.Shadows = o.Shadows end; return o end
for _, zoneId in ipairs(RC.ZoneOrder) do
  PARTS, LIGHTS = {}, 0
  local folder = Instance.new("Folder")
  local n = DR.BuildRunProps(zoneId, CFrame.new(0, 0, 0), 74, 60, Color3.fromRGB(1, 2, 3), folder)
  local bad, inYard = false, false
  for _, p in ipairs(PARTS) do
    if string.find(p.Name, "WE_Building") or string.find(p.Name, "^Store_") or p.Material == "Material.Neon" then bad = true end
    local pos = p.CFrame.Position
    if math.abs(pos.X) < 36 and pos.Z > -29 and pos.Z < 29 then inYard = true end
  end
  check(#PARTS >= 6 and #PARTS <= 70 and LIGHTS == 0 and not bad and not inYard,
    string.format("%s run props + edge: %d parts (<= 70), %d lights (none: the JOB 46 rule), no Neon / WE_Building / Store_, nothing inside the yard", zoneId, #PARTS, LIGHTS))
end
Instance.new = rn

-- ── 7. claude-bud JOB 50 C: the run line, the gateway status, the ready toast, the map rows ──
check(ZC.RunLine("WestYard") == "Run: PRODUCTION RUN · 60 s · cash", "card run line: " .. tostring(ZC.RunLine("WestYard")))
check(ZC.RunLine("DroneBay") == "Run: RECON FLIGHT · marks a rival", "instant run has no time: " .. tostring(ZC.RunLine("DroneBay")))
check(ZC.RunLine("EastYard") == "Run: DRILL COURSE · 45 s · par 30 s: boost", "drill line: " .. tostring(ZC.RunLine("EastYard")))
for zoneId in pairs(ZC.Runs) do
  local line = ZC.RunLine(zoneId)
  check(line ~= nil and utf8.len(line) <= 42, string.format("%s run line fits the 500 px card at 20 px (%d <= 42 chars): %s", zoneId, line and utf8.len(line) or -1, tostring(line)))
end
check(ZC.CardFor("WestStrip", 1, TICK).Run == "Run: RANGE PRACTICE · 45 s · reload -120 s", "CardFor carries the run line")
check(select(1, ZC.RunStatus(0, false)) == "RUN READY" and select(2, ZC.RunStatus(0, false)) == true, "status: READY")
check(ZC.RunStatus(61, false) == "NEXT RUN 2 MIN" and ZC.RunStatus(1, false) == "NEXT RUN 1 MIN" and ZC.RunStatus(1200, false) == "NEXT RUN 20 MIN", "status: NEXT RUN n MIN (rounded up, never 0)")
check(ZC.RunStatus(0, true) == "RUN IN PROGRESS", "status: IN PROGRESS beats READY")
-- the plaque text (the real service; the TextLabel caught at creation)
local LABELS = {}
local rn7 = Instance.new
Instance.new = function(cls) local o = rn7(cls); if cls == "TextLabel" then table.insert(LABELS, o) end; return o end
local OWN7 = { UserId = 470626172, Name = "shaunie6", DisplayName = "Shaun" }
local PR7 = { Prestige = 10, RebirthZones = { WestYard = 2 }, ZoneBest = { WestYard = 18 }, ZoneRunAt = { WestYard = UNIX } }
S._BuildPlaque(OWN7, PR7, "WestYard", CFrame.new(0, 0, 0), 60, Instance.new("Folder"))
Instance.new = rn7
local lbl = LABELS[#LABELS]
check(lbl ~= nil and string.find(lbl.Text, "NEXT RUN 20 MIN", 1, true) ~= nil and string.find(lbl.Text, "PRODUCTION RUN BEST 0:18.0", 1, true) ~= nil,
  "the gateway plaque shows the run's cooldown: " .. tostring(lbl and string.gsub(lbl.Text, "\n", " / ")))
PR7.ZoneRunAt.WestYard = UNIX - ZC.RunRules.CooldownMinutes * 60
S._RefreshPlaque(OWN7, PR7, "WestYard")
check(string.find(lbl.Text, "RUN READY", 1, true) ~= nil, "after the cooldown: RUN READY")
ZC.Rebuild.Signs = false
S._RefreshPlaque(OWN7, PR7, "WestYard")
check(string.find(lbl.Text, "RUN", 1, true) == string.find(lbl.Text, "RUN BEST", 1, true) and string.find(lbl.Text, "READY", 1, true) == nil, "Signs OFF: the JOB 50 A plaque exactly (no status line)")
check(S.MapRows(OWN7) == nil, "Signs OFF: no zones on the map")
ZC.Rebuild.Signs = true
check(ZC.RunRules.StatusRefreshSeconds >= 10, "the status refresh is slow (>= 10 s; minutes on the sign, no per-second text churn)")
print(string.format("REBIRTH STATIONS LUA: %d failed", fails))
if fails > 0 then error("failed") end
'''


def main():
    out, fails = [], 0
    before = subprocess.run(["git", "grep", "-l", "WE_ZonePrompt", "origin/phase-7-polish", "--", "src/StarterPlayer"], capture_output=True, text=True).stdout.strip()
    bsvc = subprocess.run(["git", "show", "origin/phase-7-polish:src/ServerScriptService/Server/Services/RebirthZoneService.luau"], capture_output=True, text=True, encoding="utf-8").stdout
    if "RebirthZoneDressing" not in bsvc:
        ok = before == "" and "WE_ZoneActivity" not in bsvc
        out.append(("ok    " if ok else "FAIL  ") + "ROOT CAUSE: before the fix no client code read a zone prompt (only the ObjectText '<Name> $cost') and no zone had an activity but the silo")
        fails += 0 if ok else 1
    else:
        out.append("note  origin already carries the JOB 46 fix")
    chunks = [PRELUDE, EXTRA]
    for key, path in MODS.items():
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
    chunks.append(TEST)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True)
    out.extend(r.stdout.strip().splitlines())
    if r.returncode != 0 or "REBIRTH STATIONS LUA: 0 failed" not in r.stdout:
        fails += 1
        out.append(r.stderr.strip()[-2500:])
    out.append("REBIRTH STATIONS TEST: %d failed" % fails)
    print("\n".join(out) if os.environ.get("VERBOSE") else "\n".join(l for l in out if l.startswith(("FAIL", "REBIRTH STATIONS TEST"))))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
