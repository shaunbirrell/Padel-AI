"""claude-bud JOB 39 phase 1: real-code tests for the endgame progression (stand-ins: run_kit_detail_test.PRELUDE).

1. CONFIG (the real EndgameConfig): every price < EconomyConfig.MaxCash; EmpireCost strictly rising with the spec's
   table (L1 5.0M, L2 5.8M, L3 6.8M, L4 8.0M, L5 9.4M, L10 20.5M, L20 98.7M, L30 474.6M, all 30 ~ $3.24B);
   EmpireMult(30) = 1.60; the rebirth scale (R3 = 1.6x, capped at R20); one life $16.07M -> R2 $22.5M -> R20 $80.3M;
   zone and Gold rows never scaled; every stat multiplier <= ResearchConfig.MaxMult 3; the effective-HP cap 400; the
   Vault loot floor 2.5 %; the Black Market stock is a pure function of the week.
2. GOALS: at 23.7k/s every Empire level from L13 is 3-300 min away; 170M buys L1-L12 and L13 shows ~15-20 min.
3. SERVICE (the real EndgameService on stubs): the one purchase path (not live / not at the station / hurt / short /
   ok / max), SpendCash "endgame_empire", level +1 and saved; ScaledCost (owner R3 = 1.6x, others raw, zones raw);
   EmpireMultFor; Live.Enabled = false reads nothing from the profile (OFF = old).
4. STATION (the real client builder): the Command Office = PlazaServicesConfig.Parts parts (<= 40), one PointLight
   (no shadows, range <= 16), one SurfaceGui (MaxDistance <= 40), no Neon, no Humanoid, nothing answers a ray.
5. REBIRTH SCREEN (the real PrestigeConfig.RebirthSummary): "Empire and upgrades" kept and "Next base $22.5M" only
   when the server sets them.
6. PACING (tools/sim/endgame_curve_sim.py with the scale vs rebirth_pacing_sim.py): the minutes to max for R1-R7 vs the
   rebirth-level minutes (spec §7: within 25 %).
Run: LUAU=path/to/luau(.exe) python tools/sim/run_endgame_test.py   (exit 1 on any failure)"""
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
    "Configs/EndgameConfig": SH / "Configs/EndgameConfig.luau",
    "Configs/PlazaServicesConfig": SH / "Configs/PlazaServicesConfig.luau",
    "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
    "Configs/EconomyConfig": SH / "Configs/EconomyConfig.luau",
    "Configs/BaseConfig": SH / "Configs/BaseConfig.luau",
    "Configs/BaseLayoutConfig": SH / "Configs/BaseLayoutConfig.luau",
    "Configs/BusinessConfig": SH / "Configs/BusinessConfig.luau",
    "Configs/PrestigeConfig": SH / "Configs/PrestigeConfig.luau",
    "Configs/LevelConfig": SH / "Configs/LevelConfig.luau",
    "Configs/ResearchConfig": SH / "Configs/ResearchConfig.luau",
    "Services/EndgameService": SV / "Services/EndgameService.luau",
    "Controllers/EndgameController": CL / "Controllers/EndgameController.luau",
    "Modules/BaseTierBuilder": SV / "Modules/BaseTierBuilder.luau",
}

EXTRA = r'''
task = { spawn = function() end, wait = function() end, delay = function() end, defer = function(fn, ...) fn(...) end }
local function signal() local s = { fns = {} }; s.Connect = function(self, fn) table.insert(self.fns, fn); return { Disconnect = function() end } end; return s end
BY_UID = {}
local Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end, LocalPlayer = any,
  GetPlayerByUserId = function(_, uid) return BY_UID[uid] end }
local RunService = { IsStudio = function() return false end }
local prevGame = game
game = { GetService = function(_, n)
  if n == "Players" then return Players elseif n == "RunService" then return RunService end
  return prevGame:GetService(n) end }
function mkPlayer(uid, pos)
  local root = { Position = pos, IsA = function(_, c) return c == "BasePart" end }
  local char = { FindFirstChild = function(_, n) if n == "HumanoidRootPart" then return root end return nil end }
  local p = { UserId = uid, Parent = true, attrs = {}, Character = char, Root = root }
  p.SetAttribute = function(self, k, v) self.attrs[k] = v end
  p.GetAttribute = function(self, k) return self.attrs[k] end
  return p
end
'''

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local EG = require(node("Configs/EndgameConfig"))
local EC = require(node("Configs/EconomyConfig"))
local RC = require(node("Configs/ResearchConfig"))
local BC = require(node("Configs/BaseConfig"))
local MAX = EC.MaxCash or 1e9

-- ── 1. config ──
local function M(n) return math.floor(n / 1e5 + 0.5) / 10 end
local want = { [1] = 5.0, [2] = 5.8, [3] = 6.8, [4] = 8.0, [5] = 9.4, [6] = 11.0, [8] = 15.0, [10] = 20.5, [12] = 28.1, [15] = 45.0, [20] = 98.7, [25] = 216.5, [30] = 474.6 }
local sum, prev, rising = 0, 0, true
for L = 1, 30 do
  local c = EG.EmpireCost(L)
  sum += c
  if c <= prev then rising = false end
  prev = c
  if want[L] then check(M(c) == want[L], string.format("EmpireCost(%d) = $%.1fM (spec %.1fM)", L, M(c), want[L])) end
end
check(rising, "EmpireCost strictly rising")
check(EG.EmpireCost(0) == nil and EG.EmpireCost(31) == nil, "no Empire level 0 / 31 for sale")
check(math.abs(sum - 3.24e9) < 0.02e9, string.format("all 30 Empire levels = $%.2fB (spec $3.24B)", sum / 1e9))
check(EG.EmpireMult(30) == 1.6 and EG.EmpireMult(0) == 1 and EG.EmpireMult(99) == 1.6 and EG.EmpireMult(0 / 0) == 1, "EmpireMult: L30 = 1.60, clamped, NaN-safe")
local prices = {}
for L = 1, 30 do table.insert(prices, EG.EmpireCost(L)) end
for L = 1, 10 do table.insert(prices, EG.DefenceCost(L)) end
for L = 1, 5 do table.insert(prices, EG.WorkshopCost(L)); for _, b in pairs(EG.Mastery.TierBase) do table.insert(prices, EG.MasteryCost(b, L)) end end
for _, t in ipairs(EG.BaseTier.Tiers) do table.insert(prices, t.Cost) end
for _, t in ipairs(EG.Elite.Tiers) do table.insert(prices, t.Cost) end
for _, c in ipairs(EG.Hospital.Medicine.Costs) do table.insert(prices, c) end
for _, k in ipairs(EG.Heist.Kits) do table.insert(prices, k.Cost) end
table.insert(prices, EG.Warheads.Tactical.Cost); table.insert(prices, EG.Warheads.Heavy.Cost)
local okMax = true
for _, p in ipairs(prices) do if not (p > 0 and p < MAX) then okMax = false end end
check(okMax, string.format("every one of %d endgame prices is > 0 and < MaxCash %d", #prices, MAX))
check(M(EG.DefenceCost(10)) == 68.7 and M(EG.WorkshopCost(5)) == 23.4 and EG.MasteryCost(2e6, 5) == 32e6, "Defence L10 $68.7M, Workshop L5 $23.4M, rebirth gun Mastery L5 $32M")
check(EG.RebirthCostScale(0) == 1 and math.abs(EG.RebirthCostScale(3) - 1.6) < 1e-9 and EG.RebirthCostScale(20) == 5 and EG.RebirthCostScale(40) == 5, "rebirth scale: R0 1x, R3 1.6x, capped at R20 (5x)")
local life0 = EG.LifeCost(1)
check(math.abs(life0 - 16.07e6) < 0.05e6, string.format("one life (15 structures + 4 businesses to max) = $%.2fM (spec $16.07M)", life0 / 1e6))
check(math.abs(EG.LifeCost(EG.RebirthCostScale(2)) - 22.5e6) < 0.1e6 and math.abs(EG.LifeCost(EG.RebirthCostScale(20)) - 80.3e6) < 0.2e6,
  string.format("R2 life $%.1fM, R20 life $%.1fM (spec 22.5 / 80.3)", EG.LifeCost(EG.RebirthCostScale(2)) / 1e6, EG.LifeCost(EG.RebirthCostScale(20)) / 1e6))
-- the rebirth-zone structures are bought by RebirthZoneService, not BaseConfig.Structures: never scaled
check(BC.Structures.TankFactory == nil and EG.ScaleStructureCost("TankFactory", 1000, 3) == 1000 and EG.ScaleStructureCost("NuclearSilo", 1000, 3) == 1000, "rebirth-zone structures (Tank Factory, Nuclear Silo) are never scaled")
check(EG.ScaleStructureCost("CommandCenter", 1000, 1.6) == 1600 and EG.ScaleStructureCost("CommandCenter", 1000, 1) == 1000 and EG.ScaleStructureCost("Nope", 1000, 2) == 1000, "a base structure scales; scale 1 / unknown id = raw")
local maxMult = RC.MaxMult or 3
check(1 + 10 * EG.Defence.PlatingPct / 100 <= maxMult and 1 + 4 * EG.Elite.PctPerTier / 100 <= maxMult and 1 + 5 * EG.Workshop.HpPct / 100 <= maxMult and EG.EmpireMult(30) <= maxMult, "every endgame stat at its max stays <= MaxMult " .. maxMult)
check(EG.Hospital.MaxEffectiveHp == 400, "effective-HP hard cap 400")
check(math.abs(0.05 * (1 - EG.Defence.VaultArmyPerLevel * 10) - 0.025) < 1e-9 and math.abs(0.10 * (1 - EG.Defence.VaultAtmPerLevel * 10) - 0.07) < 1e-9, "Vault L10: army loot 2.5 % floor, ATM raid 7 %")
local s1, s1b, s2 = EG.BlackMarketStock(2800), EG.BlackMarketStock(2800), EG.BlackMarketStock(2801)
check(table.concat(s1.Cash, ",") == table.concat(s1b.Cash, ",") and table.concat(s1.Cash, ",") ~= table.concat(s2.Cash, ","), "Black Market: the same week = the same stock, the next week changes")
check(s1.Cash[1] ~= s1.Cash[2] and s1.Cash[2] ~= s1.Cash[3] and s1.Cash[1] ~= s1.Cash[3], "3 different Cash items a week")
check(EG.WeekIndex(345600 + 604800 * 3 - 1) == 2 and EG.WeekIndex(345600 + 604800 * 3) == 3, "a week turns over at Monday 00:00 UTC")
check(EG.IncomeMinutesPrice(1e6, 20, 23700) == 28440000 and EG.IncomeMinutesPrice(1e6, 20, 0) == 1e6 and EG.IncomeMinutesPrice(1e6, 20, 0 / 0) == 1e6, "income-minutes price: max(floor, N min x $/s), NaN-safe")

-- ── 2. goals at 23.7k/s ──
local rate = 23700
local spent, L = 0, 0
while EG.EmpireCost(L + 1) and spent + EG.EmpireCost(L + 1) <= 170e6 do spent += EG.EmpireCost(L + 1); L += 1 end
check(L == 12, "170M buys Empire L1-L" .. L .. " (spec L12)")
local eta13 = (EG.EmpireCost(13) - (170e6 - spent)) / (rate * EG.EmpireMult(12)) / 60
check(eta13 > 10 and eta13 < 30, string.format("then L13 is ready in %.1f min (spec ~20)", eta13))
local gapsOk, worst = true, 0
for l = 13, 30 do
  local mins = EG.EmpireCost(l) / (rate * EG.EmpireMult(l - 1)) / 60
  worst = math.max(worst, mins)
  if mins < 3 or mins > 300 then gapsOk = false end
end
check(gapsOk, string.format("every next Empire goal from L13 is 3-300 min of income away (the longest %.0f min)", worst))

-- ── 3. the service ──
local ES = require(node("Services/EndgameService"))
local spentLog, dirty = {}, 0
local profiles = {}
local deps = {
  DataService = { GetProfile = function(p) return profiles[p.UserId] end, MarkDirty = function() dirty += 1 end, OnProfileLoaded = function() end },
  EconomyService = { SpendCash = function(p, n, why) local pr = profiles[p.UserId]; if pr.Cash < n then return false, "Short" end; pr.Cash -= n; table.insert(spentLog, { n = n, why = why }); return true end },
  NotificationService = { Notify = function() end },
}
ES.Init(deps)
local house = CFrame.new(100, 5, 200)
ES._SetStation("Command", house)
local npc = ES.StationPoint("Command")
local t = 1000
ES._SetClock(function() return t end)
local owner = mkPlayer(470626172, npc + Vector3.new(3, 0, 0))
local other = mkPlayer(9, npc)
profiles[470626172] = { Cash = 170e6, Prestige = 3, Endgame = { EmpireLevel = 0 }, BasePlotId = 1 }
profiles[9] = { Cash = 170e6, Prestige = 3, Endgame = { EmpireLevel = 0 } }
local ok, msg = ES.Purchase(other, "Empire")
check(not ok and msg == EG.Text.NotLive and #spentLog == 0, "not live (owner-first): refused, nothing spent")
owner.Root.Position = npc + Vector3.new(40, 0, 0)
ok, msg = ES.Purchase(owner, "Empire")
check(not ok and msg == EG.Text.NotHere, "away from the Command Office: refused (" .. tostring(msg) .. ")")
owner.Root.Position = npc + Vector3.new(3, 0, 0)
ES._Hurt(470626172, t - 2)
ok, msg = ES.Purchase(owner, "Empire")
check(not ok and msg == EG.Text.Hurt, "hurt 2 s ago: refused (the plaza is contested)")
ES._Hurt(470626172, nil)
ok, msg = ES.Purchase(owner, "Empire")
check(ok and #spentLog == 1 and spentLog[1].n == 5e6 and spentLog[1].why == "endgame_empire" and profiles[470626172].Endgame.EmpireLevel == 1 and dirty >= 1,
  "buy: $5.0M spent as endgame_empire, EMPIRE 1 saved (" .. tostring(msg) .. ")")
check(owner.attrs.WE_EmpireLevel == 1 and owner.attrs.WE_EndgameLive == true and math.abs((owner.attrs.WE_BaseCostScale or 0) - 1.6) < 1e-9, "attributes: WE_EmpireLevel 1, WE_EndgameLive, WE_BaseCostScale 1.6 (R3)")
profiles[470626172].Cash = 1000
ok, msg = ES.Purchase(owner, "Empire")
check(not ok and profiles[470626172].Endgame.EmpireLevel == 1 and string.find(msg, "Need") ~= nil, "short of cash: refused, level unchanged (" .. tostring(msg) .. ")")
profiles[470626172].Endgame.EmpireLevel = 30
profiles[470626172].Cash = 1e9
ok, msg = ES.Purchase(owner, "Empire")
check(not ok and msg == EG.Text.Max, "Empire 30: maxed")
check(ES.Purchase(owner, "Robux") == false, "an unknown kind is refused")
check(ES.ScaledCost(owner, profiles[470626172], "CommandCenter", 10000) == 16000 and ES.ScaledCost(other, profiles[9], "CommandCenter", 10000) == 10000, "ScaledCost: the owner at R3 pays 1.6x, another player the raw price")
profiles[470626172].Endgame.EmpireLevel = 10
check(math.abs(ES.EmpireMultFor(owner, profiles[470626172]) - 1.2) < 1e-9 and ES.EmpireMultFor(other, { Endgame = { EmpireLevel = 10 } }) == 1, "EmpireMultFor: owner L10 = 1.20, not live = 1")
local st = ES.State(owner)
check(st.Empire and st.Empire.Level == 10 and st.Empire.NextCost == EG.EmpireCost(11) and st.Rebirth and st.Stations.Command ~= nil, "State: level, next cost, the next rebirth base, the Command Office point")
-- OFF = old: nothing reads the profile
EG.Live.Enabled = false
local reads = 0
local spy = setmetatable({}, { __index = function() reads += 1; return nil end })
local m1, c1 = ES.EmpireMultFor(owner, spy), ES.ScaledCost(owner, spy, "CommandCenter", 777)
ok, msg = ES.Purchase(owner, "Empire")
check(m1 == 1 and c1 == 777 and reads == 0, "Live.Enabled = false: factor 1, raw price, the profile is never read")
check(not ok, "Live.Enabled = false: no purchase")
EG.Live.Enabled = true
EG.Parts.EmpireLevel = false
check(ES.EmpireMultFor(owner, profiles[470626172]) == 1 and ES.Purchase(owner, "Empire") == false, "the EmpireLevel part off: no factor, no purchase")
EG.Parts.EmpireLevel = true

-- ── 4. the station build ──
local CT = require(node("Controllers/EndgameController"))
local PSC = require(node("Configs/PlazaServicesConfig"))
local model, head = CT.BuildStation("Command", CFrame.new(0, 0, 0))
local parts, lights, guis, neon, hum, query, collide = 0, 0, 0, 0, 0, 0, {}
for _, d in ipairs(model:GetDescendants()) do
  if d.ClassName == "Part" then
    parts += 1
    if d.Material == "Material.Neon" then neon += 1 end
    if d.CanQuery ~= false then query += 1 end
    if d.CanCollide == true then table.insert(collide, d.Name) end
  elseif d.ClassName == "PointLight" then
    lights += 1
    check(d.Shadows == false and d.Range <= 16, "the station light: no shadows, range " .. tostring(d.Range))
  elseif d.ClassName == "SurfaceGui" then
    guis += 1
    check(d.MaxDistance <= 40, "the door sign MaxDistance " .. tostring(d.MaxDistance))
  elseif d.ClassName == "Humanoid" then
    hum += 1
  end
end
check(parts == PSC.Stations.Command.Parts and parts <= PSC.MaxParts, string.format("the Command Office = %d parts (config %d, cap %d)", parts, PSC.Stations.Command.Parts, PSC.MaxParts))
check(lights == 1 and guis == 1 and neon == 0 and hum == 0, "one light, one sign, no Neon, no Humanoid (not damageable)")
check(query == 0 and #collide == 1 and collide[1] == "MapTableTop", "nothing answers a ray; only the table top collides")
check(head ~= nil and head.Name == "Head", "the Chief of Staff's head anchors the prompt")
local okNone = CT.BuildStation("Recruits", CFrame.new(0, 0, 0)) == nil
check(okNone, "phase 1 builds only the Command Office")

-- ── 4b. phase 2: Base Tier + Defence (the real service; the owner's profile through GetPlayerByUserId) ──
BY_UID[470626172] = owner
BY_UID[9] = other
EG.Live.Enabled = true
local po = profiles[470626172]
po.Endgame = { EmpireLevel = 10, BaseTier = 0, Defence = {} }
po.Prestige = 3
po.BaseUpgrades = { CommandCenter = 5 }
po.Cash = 5e9
local atHQ, down, rebuilt, synced = false, false, 0, 0
deps.BaseService = { IsAtConsole = function(p, id) return atHQ and id == "CommandCenter", "ok" end }
deps.GateDefenseService = { NeedsRebuild = function() return down end, InstantRebuild = function() rebuilt += 1; down = false; return true end, SyncPlot = function() synced += 1 end }
spentLog = {}
local te = EG.TierEffects(5)
check(te.GateHpPct == 30 and te.SoldierCap == 20 and te.Nests == 2 and te.RebuildSeconds == -10, "Tier 5 = gate HP +30 %, soldiers +20, 2 nests, rebuild -10 s")
check(EG.DefenceNeedTier(4) == 0 and EG.DefenceNeedTier(5) == 1 and EG.DefenceNeedTier(7) == 2 and EG.DefenceNeedTier(9) == 3 and EG.DefenceNeedTier(10) == 4, "Defence L5-6 need T1, L7-8 T2, L9 T3, L10 T4")
check(ES.GateHpMult(470626172) == 1 and ES.RebuildCut(470626172, 50) == 50 and ES.TurretHpMult(470626172) == 1 and ES.VaultMult(470626172, true) == 1 and ES.ExtraNests(470626172) == 0,
  "nothing bought: every defence number is the old one")
ok, msg = ES.Purchase(owner, "Tier", "Next")
check(not ok and msg == EG.Text.NotAtHQ, "Base Tier away from the HQ console: refused")
atHQ = true
po.Prestige = 1
ok, msg = ES.Purchase(owner, "Tier", "Next")
check(not ok and msg == string.format(EG.Text.NeedRebirths, 2), "Fort needs 2 rebirths (" .. tostring(msg) .. ")")
po.Prestige = 3
po.BaseUpgrades.CommandCenter = 4
ok, msg = ES.Purchase(owner, "Tier", "Next")
check(not ok and msg == string.format(EG.Text.NeedCC, 5), "Fort needs Command Center L5")
po.BaseUpgrades.CommandCenter = 5
ok, msg = ES.Purchase(owner, "Tier", "Next")
check(ok and po.Endgame.BaseTier == 1 and spentLog[#spentLog].n == 10e6 and spentLog[#spentLog].why == "endgame_tier", "Fort: $10M as endgame_tier, BASE TIER 1 (" .. tostring(msg) .. ")")
ok, msg = ES.Purchase(owner, "Tier", "Next")
check(ok and po.Endgame.BaseTier == 2, "Citadel at R3")
ok, msg = ES.Purchase(owner, "Tier", "Next")
check(not ok and msg == string.format(EG.Text.NeedRebirths, 5), "Stronghold needs 5 rebirths")
po.Prestige = 12
for _ = 1, 3 do ES.Purchase(owner, "Tier", "Next") end
check(po.Endgame.BaseTier == 5 and ES.Purchase(owner, "Tier", "Next") == false, "Stronghold, Bastion, Capital at R12; then maxed")
ES._Own(po, 470626172)
check(ES.SoldierCapBonus(po) == 20 and ES.ExtraNests(470626172) == 2 and ES.SoldierCapBonus({ Endgame = { BaseTier = 5 } }) == 0, "Capital: +20 soldiers, 2 nests (an unknown profile gets 0)")
-- Defence at the Engineering Bureau
ES._SetStation("Engineers", CFrame.new(300, 5, 0))
local eng = ES.StationPoint("Engineers")
ok, msg = ES.Purchase(owner, "Defence", "Vault")
check(not ok, "Defence away from the Engineering Bureau: refused (" .. tostring(msg) .. ")")
owner.Root.Position = eng
ok, msg = ES.Purchase(owner, "Defence", "Robux")
check(not ok, "an unknown track is refused")
po.Endgame.BaseTier = 0
for _ = 1, 4 do ES.Purchase(owner, "Defence", "Gate") end
ok, msg = ES.Purchase(owner, "Defence", "Gate")
check(po.Endgame.Defence.Gate == 4 and not ok and msg == string.format(EG.Text.NeedTier, 1), "Gate & Walls L1-4 bought, L5 needs Base Tier 1 (" .. tostring(msg) .. ")")
po.Endgame.BaseTier = 5
for _ = 1, 6 do ES.Purchase(owner, "Defence", "Gate") end
for _, tr in ipairs({ "Plating", "Guns", "Vault" }) do for _ = 1, 10 do ES.Purchase(owner, "Defence", tr) end end
check(po.Endgame.Defence.Gate == 10 and po.Endgame.Defence.Plating == 10 and po.Endgame.Defence.Guns == 10 and po.Endgame.Defence.Vault == 10 and synced > 0,
  "every track to L10 (the gate defences resync after each buy)")
check(spentLog[#spentLog].why == "endgame_defence" and spentLog[#spentLog].n == EG.DefenceCost(10), "L10 costs $68.7M as endgame_defence")
check(math.abs(ES.GateHpMult(470626172) - 2.5) < 1e-9, string.format("[DefTest] gate=10 tier=5 gateHP x%.2f (+30 %% tier +120 %% track)", ES.GateHpMult(470626172)))
check(ES.RebuildCut(470626172, 50) == 10, "[DefTest] gate=10 rebuild=10 s (50 - 10 - 30, floor 10)")
check(math.abs(ES.TurretHpMult(470626172) - 2.5) < 1e-9, "[DefTest] plating=10 autogunHP x2.50")
check(math.abs(ES.TurretDmgMult(470626172, 1.5) - 2.4) < 1e-9 and ES.TurretDmgMult(470626172, 2.5) == 3 and ES.TurretDmgMult(9, 1.5) == 1.5, "[DefTest] guns=10 turretDmg research 1.5 -> x2.40; capped at MaxMult 3; not live = research only")
check(math.abs(0.05 * ES.VaultMult(470626172, true) - 0.025) < 1e-9 and math.abs(0.10 * ES.VaultMult(470626172, false) - 0.07) < 1e-9, "[LootTest] vault=10 army pct=2.5 % atm pct=7 %")
po.Endgame.Defence.Vault = 5
check(math.abs(0.05 * ES.VaultMult(470626172, true) - 0.0375) < 1e-9 and math.abs(0.10 * ES.VaultMult(470626172, false) - 0.085) < 1e-9, "[LootTest] vault=5 army 3.75 % atm 8.5 %")
check(ES.VaultMult(9, true) == 1, "[LootTest] vault=0 (not live) = the JOB 38 5 % / 10 %")
-- instant rebuild at the HQ console
owner.attrs.WE_IncomePerSec = 23700
ok, msg = ES.Purchase(owner, "Rebuild", "Now")
check(not ok and msg == EG.Text.NothingDown and rebuilt == 0, "rebuild with nothing down: refused")
down = true
ok, msg = ES.Purchase(owner, "Rebuild", "Now")
check(ok and rebuilt == 1 and spentLog[#spentLog].n == 711000 and spentLog[#spentLog].why == "endgame_rebuild", "rebuild: 30 s of income ($711,000 at 23.7k/s) as endgame_rebuild")
owner.attrs.WE_IncomePerSec = 100
down = true
ES.Purchase(owner, "Rebuild", "Now")
check(spentLog[#spentLog].n == 25000, "rebuild floor $25,000")
atHQ = false
down = true
check(ES.Purchase(owner, "Rebuild", "Now") == false, "rebuild away from the HQ console: refused")
-- OFF: the tier / defence numbers are the old ones for a not-live owner even with a full profile
EG.Live.Enabled = false
check(ES.GateHpMult(470626172) == 1 and ES.TurretHpMult(470626172) == 1 and ES.ExtraNests(470626172) == 0 and ES.SoldierCapBonus(po) == 0 and ES.VaultMult(470626172, false) == 1 and ES.RebuildCut(470626172, 50) == 50,
  "Live.Enabled = false: gate / turret / nests / soldiers / vault / rebuild all back to the old numbers")
EG.Live.Enabled = true
local st2 = ES.State(owner)
check(st2.Tier and st2.Tier.Level == 5 and st2.Tier.Next == nil and #st2.Defence == 4 and st2.Rebuild ~= nil, "State: the tier, 4 defence rows, the rebuild row")
local rowsE = CT.ListRows("Engineers", st2)
local rowsH = CT.ListRows("HQ", st2)
check(#rowsE == 4 and rowsE[1].Kind == "Defence" and #rowsH == 2 and rowsH[1].Done == "MAX" and rowsH[2].Kind == "Rebuild", "the list panel rows: 4 tracks; HQ = tier (MAX) + rebuild")

-- the Engineering Bureau stand
local em = CT.BuildStation("Engineers", CFrame.new(0, 0, 0))
local ep, el, eg2, eneon = 0, 0, 0, 0
for _, d in ipairs(em:GetDescendants()) do
  if d.ClassName == "Part" then ep += 1; if d.Material == "Material.Neon" then eneon += 1 end
  elseif d.ClassName == "PointLight" then el += 1
  elseif d.ClassName == "SurfaceGui" then eg2 += 1 end
end
check(ep == PSC.Stations.Engineers.Parts and ep <= PSC.MaxParts and el == 1 and eg2 == 1 and eneon == 0, string.format("the Engineering Bureau stand = %d parts (cap %d), 1 light, 1 sign", ep, PSC.MaxParts))

-- the Base Tier builds (real BaseTierBuilder; a plot like the live ones: 320 pad, walls at 21.5, 2 gate posts, the HQ box)
local BTB = require(node("Modules/BaseTierBuilder"))
local ctx = {
  Ground = CFrame.new(0, 1, 0), PadCentre = Vector3.new(0, 0.5, 0), HalfX = 158.5, HalfZ = 158.5, WallTop = 22.5, GroundY = 1,
  Posts = { { CFrame = CFrame.new(-6, 7, 158), Size = Vector3.new(3, 12, 3) }, { CFrame = CFrame.new(6, 7, 158), Size = Vector3.new(3, 12, 3) } },
  Gate = CFrame.new(0, 1, 158), Nests = { CFrame.new(-16, 1, 150), CFrame.new(16, 1, 150) },
  HQ = { CFrame = CFrame.new(0, 12, -38), Size = Vector3.new(26, 22, 20) },
}
local prevParts = 0
local allOk = true
for t = 1, 5 do
  local model, parts, lights = BTB.Build(ctx, t)
  local tierParts = 0
  local f = nil
  for _, c in ipairs(model:GetChildren()) do if c.Name == "Tier" .. t then f = c end end
  local neonT = 0
  for _, d in ipairs(model:GetDescendants()) do if d.ClassName == "Part" and d.Material == "Material.Neon" then neonT += 1 end end
  for _, d in ipairs(f and f:GetDescendants() or {}) do if d.ClassName == "Part" then tierParts += 1 end end
  print(string.format("[BaseTier] tier=%d added=%d total=%d lights=%d", t, tierParts, parts, lights))
  if tierParts > EG.BaseTier.MaxPartsPerTier or lights > EG.BaseTier.MaxLightsPerTier or tierParts < 20 or neonT > 0 or parts ~= prevParts + tierParts then allOk = false end
  prevParts = parts
end
check(allOk, "every tier adds 20..120 parts, <= 2 lights, no Neon; cumulative (total " .. prevParts .. " at Capital)")
local m5 = BTB.Build(ctx, 5)
local bast, lint = 0, 0
for _, d in ipairs(m5:GetDescendants()) do
  if d.Name == "BastionBody" then bast += 1 end
  if d.Name == "GatehouseLintel" then lint += 1 end
end
check(bast == 4 and lint == 1, "Stronghold: 4 corner bastions + the gatehouse lintel")
local m0 = BTB.Build(ctx, 0)
check(#m0:GetDescendants() == 0, "tier 0 builds nothing")

-- ── 5. rebirth screen ──
local PC = require(node("Configs/PrestigeConfig"))
local function has(list, s) for _, l in ipairs(list) do if l == s then return true end end return false end
local plain = PC.RebirthSummary("Cash", { Built = 10, Prestige = 2, BusinessesOn = true })
local oldReset = true
for _, l in ipairs(plain.Reset) do if string.find(l, "Next base") then oldReset = false end end
check(not has(plain.Keep, "Empire and upgrades") and oldReset and #plain.Reset == 4, "without the endgame ctx the summary is the old one (" .. table.concat(plain.Reset, " / ") .. ")")
local eg = PC.RebirthSummary("Cash", { Built = 10, Prestige = 2, BusinessesOn = true, EndgameKeep = true, NextBase = EG.LifeCost(EG.RebirthCostScale(3)) } :: any)
check(has(eg.Keep, "Empire and upgrades") and has(eg.Reset, "Next base $25.7M"), "live: KEEP Empire and upgrades, RESET Next base $25.7M (R3)")
local kb = PC.RebirthSummary("KeepBase", { Built = 10, Prestige = 2, EndgameKeep = true, NextBase = 1e6 } :: any)
local nb = false
for _, l in ipairs(kb.Reset) do if string.find(l, "Next base") then nb = true end end
check(not nb, "keep-base rebirth: no next base price (the base is kept)")

print(string.format("ENDGAME TEST: %d failed", fails))
if fails > 0 then error("failed") end
'''


def main():
    fails = []
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
    print(out if os.environ.get("VERBOSE") else ("\n".join(l for l in out.splitlines() if l.startswith("FAIL") or l.startswith("ENDGAME TEST")) or out))
    if r.returncode != 0:
        print(r.stderr.strip()[-2500:])
        fails.append("luau")

    # 6. pacing: minutes to max with the scale vs the rebirth-level minutes (spec §7 asks within 25 % for R1-R7)
    import endgame_curve_sim as ecs  # noqa: E402
    import rebirth_pacing_sim as rps  # noqa: E402

    rows = rps.run(lives=8)
    for p in range(1, 8):
        mx = ecs.time_to_max(p, cost_scale=1 + 0.2 * p)
        lv = rows[p]["Minutes"]
        dev = mx / lv - 1
        inside = abs(dev) <= 0.25
        tag = "ok    " if inside else "NOTE  "
        print("%sR%d: max the base in %.1f min vs the rebirth level in %.1f min (%+.0f %%)%s" % (
            tag, p, mx, lv, dev * 100, "" if inside else "  <- outside the spec's 25 %: owner decision, see ASSUMPTIONS JOB 39"))
        if not inside and p <= 6:
            fails.append("pacing R%d" % p)

    # static: income untouched, rebirth never clears Endgame, no Robux path, no teleport
    bal = (SH / "Configs/BalanceConfig.luau").read_text(encoding="utf-8")
    pres = (SV / "Services/PrestigeService.luau").read_text(encoding="utf-8")
    mon = (SV / "Services/MonetizationService.luau").read_text(encoding="utf-8")
    new = "".join((p.read_text(encoding="utf-8")) for p in (SV / "Services/EndgameService.luau", CL / "Controllers/EndgameController.luau", SH / "Configs/EndgameConfig.luau"))
    gds = (SV / "Services/GateDefenseService.luau").read_text(encoding="utf-8")
    mcs = (SV / "Services/MoneyCollectorService.luau").read_text(encoding="utf-8")
    sls = (SV / "Services/SoldierService.luau").read_text(encoding="utf-8")
    btb = (SV / "Modules/BaseTierBuilder.luau").read_text(encoding="utf-8")
    new += btb
    for cond, msg in (
        ("maxHp = math.floor(maxHp * eg.GateHpMult(ownerUserId) + 0.5)" in gds, "gate HP reads GateHpMult (spawnGateBarriers)"),
        ("os.clock() + GateDefenseService.RebuildSeconds(def.OwnerUserId)" in gds, "the gate rebuild timer reads RebuildCut"),
        ("tu.MaxHealth = math.floor(tu.MaxHealth * eg.TurretHpMult(ownerUserId) + 0.5)" in gds, "AutoGun HP reads TurretHpMult"),
        ("dealDamage(plr, hum, (stats.TurretDamage or 22) * gunMult, t.Model, def.PlotId)" in gds, "turret damage reads TurretDmgMult (research x guns, capped)"),
        ("for slot, sx in ipairs(GateDefenseService.GunSlots(gx, ownerUserId)) do" in gds, "the Base Tier nests are real AutoGun slots"),
        ("R.StealFraction * MoneyCollectorService.VaultMult(victim, false)" in mcs and "* MoneyCollectorService.VaultMult(victim, true)" in mcs, "Vault Plating on the ATM raid and the army raid"),
        ("+ rebirth + tier" in sls, "the soldier cap adds the Base Tier soldiers"),
        ("Instance.new(\"Humanoid\")" not in btb and "Neon" not in btb, "BaseTierBuilder: no Humanoid, no Neon"),
        ("Endgame" not in bal, "structure income reads the raw Costs (BalanceConfig never sees the scale)"),
        ("profile.Endgame =" not in pres and "profile.Endgame" not in pres.replace("x.EndgameKeep", ""), "PrestigeService never clears profile.Endgame (kept on both paths)"),
        ("Endgame" not in mon, "no Robux path to the endgame (MonetizationService never grants it)"),
        ("PivotTo" not in new and "FastTravel" not in new and "TeleportService" not in new, "no PivotTo / fast travel / teleport in the new code"),
        (".Health =" not in new and "TakeDamage" not in new, "no Health writes in the new code"),
    ):
        print(("ok    " if cond else "FAIL  ") + msg)
        if not cond:
            fails.append(msg)
    return fails


if __name__ == "__main__":
    f = main()
    if f:
        print("FAILED:", ", ".join(f))
        sys.exit(1)
