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
    "Configs/WeaponConfig": SH / "Configs/WeaponConfig.luau",
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
-- recursive FindFirstChild (DressUnit looks up Head / Left Arm / Torso inside the rig)
local baseIdx = INST.__index
INST.__index = function(t, k)
  if k == "GetBoundingBox" then return function() return CFrame.new(0, 2, 0), Vector3.new(6, 4, 12) end end
  if k == "FindFirstChildOfClass" then
    return function(s, cls) for _, c in ipairs(rawget(s, "__kids") or {}) do if c.ClassName == cls then return c end end return nil end
  end
  if k == "FindFirstChild" then
    return function(s, n, rec)
      local function f(o)
        for _, c in ipairs(rawget(o, "__kids") or {}) do
          if c.Name == n then return c end
          if rec then local r = f(c); if r then return r end end
        end
        return nil
      end
      return f(s)
    end
  end
  return baseIdx(t, k)
end
function mkPlayer(uid, pos)
  local root = { Position = pos, IsA = function(_, c) return c == "BasePart" end }
  local char = { FindFirstChild = function(_, n) if n == "HumanoidRootPart" then return root end return nil end, cattrs = {} }
  char.GetAttribute = function(self, k) return self.cattrs[k] end
  char.SetAttribute = function(self, k, v) self.cattrs[k] = v end
  local p = { UserId = uid, Parent = true, attrs = {}, Character = char, Root = root, DisplayName = "Player" .. uid }
  p.SetAttribute = function(self, k, v) self.attrs[k] = v end
  p.GetAttribute = function(self, k) return self.attrs[k] end
  return p
end
'''

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local EG = require(node("Configs/EndgameConfig"))
-- codebot_v166: Live.OwnerFirst=false (everyone); the owner-first paths below are still proved with OwnerFirst = true
local EG_LAUNCHED = EG.Live.OwnerFirst
EG.Live.OwnerFirst = true
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
local okNone = CT.BuildStation("Nope", CFrame.new(0, 0, 0)) == nil
check(okNone, "an unknown station builds nothing")

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
J55 = { refreshed = 0 } -- claude-bud JOB 55: a Defence buy refreshes in place (RefreshDefence), never the full SyncPlot (a global: the chunk is at the 200-local limit)
deps.GateDefenseService = { NeedsRebuild = function() return down end, InstantRebuild = function() rebuilt += 1; down = false; return true end, SyncPlot = function() synced += 1 end, RefreshDefence = function() J55.refreshed += 1 end }
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
-- claude-bud JOB 55: no turrets before Walls L4: Turret Plating is refused (and the row says why); with Walls L4 it sells
po.BaseUpgrades = po.BaseUpgrades or {}
po.BaseUpgrades.DefensiveWalls = 3
do
  local okW, msgW = ES.Purchase(owner, "Defence", "Plating")
  local rowW
  for _, r in ipairs(ES.State(owner).Defence or {}) do if r.Id == "Plating" then rowW = r end end
  check(not okW and msgW == string.format(EG.Text.NeedWalls, 4) and rowW and rowW.Need == msgW, "[DefFix] Walls L3: Turret Plating refused + the row says " .. tostring(msgW))
end
po.BaseUpgrades.DefensiveWalls = 4
J55.s0, J55.r0 = synced, J55.refreshed
-- claude-bud JOB 53: L3 -> L4 is a new visual tier: the toast says what changed on his base; L3 (same tier) does not
do
  local _, m3, m4
  for i = 1, 4 do _, m4 = ES.Purchase(owner, "Defence", "Plating"); if i == 3 then m3 = m4 end end
  check(string.find(tostring(m4), string.format(EG.Text.DefenceNewLook, EG.Text.DefenceLook.Plating[2]), 1, true) ~= nil and string.find(tostring(m3), "New on", 1, true) == nil,
    "[DefLook] Plating L4 toast: " .. tostring(m4) .. " | L3: " .. tostring(m3))
end
for _, tr in ipairs({ "Plating", "Guns", "Vault" }) do for _ = 1, 10 do ES.Purchase(owner, "Defence", tr) end end
check(po.Endgame.Defence.Gate == 10 and po.Endgame.Defence.Plating == 10 and po.Endgame.Defence.Guns == 10 and po.Endgame.Defence.Vault == 10 and synced > 0,
  "every track to L10 (the gate defences resync after each buy)")
check(J55.refreshed > J55.r0 and synced == J55.s0, string.format("[DefFix] Defence buys refresh the gate IN PLACE (%d RefreshDefence, %d extra SyncPlot): no mid-raid full repair", J55.refreshed - J55.r0, synced - J55.s0))
do
  local rows = {}
  for _, r in ipairs(ES.State(owner).Defence or {}) do rows[r.Id] = r end
  check(rows.Gate.Name == EG.Text.GateName and rows.Guns.Now == EG.DefenceText("Guns", 10, EG.TierTextLive and EG.TierTextLive(owner.UserId) or nil) and string.find(rows.Vault.Now, "ATM", 1, true) and string.find(rows.Vault.Now, "army", 1, true),
    "[DefFix] honest rows: " .. rows.Gate.Name .. " | " .. rows.Guns.Now .. " | " .. rows.Gate.Now .. " | " .. rows.Vault.Now)
end
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
local hasRebuild = false
for _, r in ipairs(rowsH) do if r.Kind == "Rebuild" then hasRebuild = true end end
check(#rowsE == 4 and rowsE[1].Kind == "Defence" and rowsH[1].Done == "MAX" and hasRebuild, "the list panel rows: 4 tracks; HQ = tier (MAX) + rebuild (+ the warheads)")

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

-- ── 4c. phase 3: Elite Training (the real service + config) ──
local ES3 = EG.EliteStats
check(math.abs(ES3("Infantry", 4).Hp - 1.32) < 1e-9 and math.abs(ES3("Infantry", 4).Dmg - 1.32) < 1e-9 and ES3("Infantry", 4).Scale == 1.28, "Mythic Infantry: +32 % HP and damage, scale 1.28")
check(math.abs(ES3("Heavy", 0).Hp - 1.2) < 1e-9 and ES3("Heavy", 0).Dmg == 1 and math.abs(ES3("SpecialForces", 2).Dmg - 1.16 * 1.1) < 1e-9, "Heavy +20 % HP; Special Forces x1.1 damage on top of the tier")
check(ES3("Infantry", 1).Scale == 1.05 and ES3("Infantry", 2).Scale == 1.10 and ES3("Infantry", 3).Scale == 1.18 and ES3("Infantry", 0).Scale == 1, "rig scale 1.05 / 1.10 / 1.18 / 1.28 per tier")
check(EG.SlotKind(3, 5) == "Infantry" and EG.SlotKind(5, 0) == "Heavy" and EG.SlotKind(10, 3) == "SpecialForces" and EG.SlotKind(10, 2) == "Heavy", "every 5th slot Heavy, every 10th Special Forces (SF Facility L3+)")
local prevTTK = nil
local ttkOk = true
for t = 0, 4 do
  local s = ES3("Infantry", t)
  local ttk = 100 / s.Dmg -- time to kill the same untrained target, relative to an untrained shooter (%)
  print(string.format("[EliteTest] tier=%d maxHP=x%.2f dmg=x%.2f TTK_vs_unit=%.0f%%", t, s.Hp, s.Dmg, ttk))
  if prevTTK and ttk >= prevTTK then ttkOk = false end
  prevTTK = ttk
end
check(ttkOk, "the time-to-kill drops with every tier (headless arithmetic; the Studio 2-player TTK is owed)")
ES._SetStation("Recruits", CFrame.new(-300, 5, 0))
owner.Root.Position = ES.StationPoint("Recruits")
po.Prestige = 12
po.Cash = 5e9
po.BaseUpgrades.SpecialForcesFacility = 3
for _ = 1, 3 do ES.Purchase(owner, "Elite", "Infantry") end
ok, msg = ES.Purchase(owner, "Elite", "Infantry")
check(po.Endgame.Elite.Infantry == 3 and not ok and msg == string.format(EG.Text.NeedRebirths, 30), "Infantry Veteran / Elite / Legendary; Mythic needs 30 rebirths")
check(spentLog[#spentLog].why == "endgame_elite" and spentLog[#spentLog].n == 30e6, "Legendary $30M as endgame_elite")
po.Prestige = 30
ok, msg = ES.Purchase(owner, "Elite", "Infantry")
check(ok and po.Endgame.Elite.Infantry == 4, "Mythic at R30 (" .. tostring(msg) .. ")")
check(ES.Purchase(owner, "Elite", "Robux") == false and ES.Purchase(owner, "Elite", "Infantry") == false, "an unknown type is refused; Mythic is the top")
-- a spawn: slot 1 Infantry Mythic (no death, no fee)
local e1 = ES.UnitElite(owner, 1)
check(e1 and e1.Kind == "Infantry" and e1.Tier == 4 and not e1.Untrained, "a Mythic Infantry spawns trained")
check(ES.UnitElite(other, 1) == nil, "not live: today's soldier (nil)")
-- it dies: its respawn pays the Mythic re-train fee ($100k) as endgame_retrain
local n0 = #spentLog
ES.NoteUnitDeath(470626172, "Infantry", 4)
local e2 = ES.UnitElite(owner, 1)
check(e2.Tier == 4 and #spentLog == n0 + 1 and spentLog[#spentLog].n == 100000 and spentLog[#spentLog].why == "endgame_retrain", "a dead Mythic's respawn pays $100,000 (endgame_retrain) and comes back Mythic")
-- broke: it comes back untrained
po.Cash = 10
ES.NoteUnitDeath(470626172, "Infantry", 4)
local e3 = ES.UnitElite(owner, 1)
local cnt, fee = ES.UntrainedNow(owner, po)
check(e3.Untrained and cnt == 1 and fee == 100000, "short of cash: it comes back untrained; RE-TRAIN 1 for $100,000")
po.Cash = 5e9
owner.Root.Position = ES.StationPoint("Recruits")
ok, msg = ES.Purchase(owner, "Retrain", "Now")
check(ok and select(1, ES.UntrainedNow(owner, po)) == 0 and spentLog[#spentLog].n == 100000, "RE-TRAIN at the Recruitment Office clears it (" .. tostring(msg) .. ")")
-- the Instant Army Refill: free re-trains for the dead, the untrained re-trained now
ES.NoteUnitDeath(470626172, "Infantry", 4)
ES.NoteUnitDeath(470626172, "Infantry", 4)
ES.GrantRefill(owner)
local n1 = #spentLog
local e4 = ES.UnitElite(owner, 1)
check(e4.Tier == 4 and #spentLog == n1 and po.Endgame.FreeRetrains == 1, "after the Instant Army Refill a respawn is free (FreeRetrains 2 -> 1), no Cash spent")
-- the look
local um = Instance.new("Model")
local hd = Instance.new("Part"); hd.Name = "Head"; hd.CFrame = CFrame.new(0, 5, 0); hd.Parent = um
local rig = Instance.new("Model"); rig.Name = "WE_Rig"; rig.Parent = um
local la = Instance.new("Part"); la.Name = "Left Arm"; la.CFrame = CFrame.new(-1.5, 3, 0); la.Parent = rig
local to = Instance.new("Part"); to.Name = "Torso"; to.CFrame = CFrame.new(0, 3, 0); to.Parent = rig
local hum = Instance.new("Humanoid"); hum.HipHeight = 2; hum.Parent = um
ES.DressUnit(um, hum, ES.EliteFor("Heavy", 3), 2)
local chev, trim, pads = 0, 0, 0
for _, d in ipairs(um:GetDescendants()) do
  if d.Name == "EliteChevron" then chev += 1 elseif d.Name == "EliteTrim" then trim += 1 elseif d.Name == "HeavyPad" then pads += 1 end
end
check(chev == 3 and trim == 1 and pads == 2 and um:GetAttribute("WE_EliteTier") == 3 and um:GetAttribute("WE_EliteScale") == 1.18 and math.abs(hum.HipHeight - 2.36) < 1e-9,
  "a Legendary Heavy: 3 chevrons, the gold trim, shoulder pads, scale 1.18, hip height 2.36")
ES.DressUnit(um, hum, ES.EliteFor("Infantry", 4), 2)
local star, chev2 = 0, 0
for _, d in ipairs(um:GetDescendants()) do
  if d.Name == "EliteStar" then star += 1 elseif d.Name == "EliteChevron" then chev2 += 1 end
end
check(star == 1 and chev2 == 0 and um:GetAttribute("WE_EliteDmg") == ES3("Infantry", 4).Dmg, "re-dressed Mythic: the star replaces the chevrons (old insignia removed), damage attribute x1.32")
local st3 = ES.State(owner)
check(#st3.Elite == 3 and st3.Retrain ~= nil and #CT.ListRows("Recruits", st3) >= 3, "State: 3 soldier types (+ the re-train row when due)")
-- the Recruitment Office
local rmod = CT.BuildStation("Recruits", CFrame.new(0, 0, 0))
local rp, rl, rg = 0, 0, 0
for _, d in ipairs(rmod:GetDescendants()) do
  if d.ClassName == "Part" then rp += 1 elseif d.ClassName == "PointLight" then rl += 1 elseif d.ClassName == "SurfaceGui" then rg += 1 end
end
check(rp == PSC.Stations.Recruits.Parts and rp <= PSC.MaxParts and rl == 1 and rg == 1, string.format("the Recruitment Office = %d parts (cap %d), 1 light, 1 sign", rp, PSC.MaxParts))

-- ── 4d. phase 4: Mastery / attachments / camos, the Vehicle Workshop, the Field Hospital ──
local WC = require(node("Configs/WeaponConfig"))
local AR = WC.Weapons.AssaultRifle
local g5 = EG.GunStats(AR, 5, {})
check(math.abs(g5.Damage - 22 * 1.15) < 1e-9 and math.abs(g5.FireRate - 9 * 1.10) < 1e-9 and math.abs(g5.Range - 140 * 1.20) < 1e-9 and g5.MagazineSize == 39 and math.abs(g5.ReloadTime - 2.0 * 0.75) < 1e-9,
  "[GunTest] weapon=AssaultRifle mastery=5 dmg=25.3 rps=9.9 range=168 mag=39 reload=1.50")
local g5a = EG.GunStats(AR, 5, { RedDot = true, Grip = true, ExtendedMag = true })
check(math.abs(g5a.Range - 140 * 1.30) < 1e-9 and math.abs(g5a.Spread - 2.0 * 0.85) < 1e-9 and g5a.MagazineSize == 47, "[GunTest] + Red-dot range=182, Grip spread x0.85, Extended Mag mag=47")
check(AR.Range < 150 and g5a.Range > 150, "range test: a 150-stud shot is past the AR's old range (140) and inside L5 + Red-dot (182)")
local g0 = EG.GunStats(AR, 0, {})
check(g0.Damage == AR.Damage and g0.Range == AR.Range and g0.MagazineSize == AR.MagazineSize, "[GunTest] mastery=0: the WeaponConfig numbers")
local prem, reb = nil, nil
for _, d in pairs(WC.Weapons) do if d.Premium == true then prem = d end; if d.RebirthOnly == true then reb = d end end
check(EG.MasteryBase(AR) == 1e6 and (reb == nil or EG.MasteryBase(reb) == 2e6) and (prem == nil or EG.MasteryBase(prem) == 3e6) and EG.MasteryCost(2e6, 5) == 32e6, "mastery price base: shop 1M, rebirth 2M, premium 3M (a rebirth gun L1-5 = $62M)")
-- the service
owner.attrs.WE_Weapons = "AssaultRifle,StarterRifle"
owner.attrs.WE_EquippedWeapon = "AssaultRifle"
ES._SetStation("Armory", CFrame.new(0, 5, 300))
owner.Root.Position = ES.StationPoint("Armory")
po.Cash = 5e9
po.Gold = 300
check(ES.PlayerGunDef(owner, AR) == AR, "no mastery yet: the WeaponConfig row itself")
ok, msg = ES.Purchase(owner, "Mastery", "SMG")
check(not ok and msg == "You don't own that gun", "mastery on a gun he does not own: refused")
for _ = 1, 5 do ES.Purchase(owner, "Mastery", "AssaultRifle") end
check(po.Endgame.Mastery.AssaultRifle == 5 and spentLog[#spentLog].why == "endgame_mastery" and spentLog[#spentLog].n == 16e6, "AR mastery 1-5 (L5 $16M as endgame_mastery)")
local d5 = ES.PlayerGunDef(owner, AR)
check(d5 ~= AR and d5.__eg == true and d5.Range == 168 and ES.PlayerGunDef(owner, AR) == d5 and ES.PlayerGunDef(owner, d5) == d5, "the player's AR: a cached copy (range 168), never applied twice")
check(ES.PlayerGunDef(other, AR) == AR, "another player / not live: the row itself")
ok, msg = ES.Purchase(owner, "Attach", "AssaultRifle:RedDot")
check(ok and ES.PlayerGunDef(owner, AR).Range == 182 and spentLog[#spentLog].n == 1e6, "Red-dot fitted: range 182 ($1M)")
ok, msg = ES.Purchase(owner, "Attach", "AssaultRifle:Suppressor")
check(not ok and msg == "Not available", "the Suppressor is not sold (no firing ping exists to hide)")
check(string.find(ES.GunModsString(owner) or "", "AssaultRifle=1.100,1.300,0.750,1.000", 1, true) ~= nil, "WE_GunMods for the client: " .. tostring(ES.GunModsString(owner)))
local goldSpent = {}
deps.EconomyService.SpendGold = function(p, n, why) local pr = profiles[p.UserId]; if (pr.Gold or 0) < n then return false end; pr.Gold -= n; table.insert(goldSpent, { n = n, why = why }); return true end
local cashBefore = po.Cash
ok, msg = ES.Purchase(owner, "Camo", "AssaultRifle:Tiger")
check(ok and po.Gold == 150 and goldSpent[1].why == "endgame_camo" and po.Cash == cashBefore and ES.CamoFor(owner, "AssaultRifle") == "Tiger", "Tiger camo: 150 Gold (no Cash), on the AR")
ok, msg = ES.Purchase(owner, "Camo", "AssaultRifle:Gold")
check(not ok and string.find(msg, "Gold") ~= nil, "Gold camo with 150 Gold: refused (" .. tostring(msg) .. ")")
ok, msg = ES.Purchase(owner, "EquipCamo", "AssaultRifle:None")
check(ok and ES.CamoFor(owner, "AssaultRifle") == nil, "camo off (free, anywhere)")
-- the Vehicle Workshop
local atDepot = false
deps.BaseService.IsAtConsole = function(p, id) return (id == "VehicleDepot" and atDepot) or (id == "CommandCenter" and atHQ), "ok" end
ok, msg = ES.Purchase(owner, "Workshop", "Air")
check(not ok, "Workshop away from the Vehicle Depot console: refused")
atDepot = true
for _ = 1, 5 do ES.Purchase(owner, "Workshop", "Air") end
local hpM, spM, wl = ES.WorkshopFor(470626172, "Air")
check(wl == 5 and math.abs(hpM - 1.30) < 1e-9 and math.abs(spM - 1.15) < 1e-9 and spentLog[#spentLog].n == EG.WorkshopCost(5), "Air workshop L5: +30 % HP, +15 % speed ($23.4M)")
check(ES.WorkshopFor(470626172, "Naval") == 1 and ES.WorkshopFor(9, "Air") == 1, "another class / not live: x1")
local vm = Instance.new("Model")
local body = Instance.new("Part"); body.Name = "Body"; body.Parent = vm; vm.PrimaryPart = body
ES.DressVehicle(vm, 5)
local plates, trim = 0, 0
for _, dd in ipairs(vm:GetDescendants()) do if dd.Name == "WorkshopPlate" then plates += 1 elseif dd.Name == "WorkshopNameplate" then trim += 1 end end
check(plates == 2 and trim == 1, "L5 vehicle: 2 flank plates (+ bolt rails) and the gold nameplate")
-- the Field Hospital
ES._SetStation("Hospital", CFrame.new(0, 5, -300))
owner.Root.Position = ES.StationPoint("Hospital")
owner.attrs.WE_IncomePerSec = 23700
for _ = 1, 3 do ES.Purchase(owner, "Medicine", "Next") end
check(po.Endgame.Medicine == 3 and ES.MedicineBonus(owner) == 30 and ES.MedicineBonus(other) == 0 and spentLog[#spentLog].n == 12e6, "Combat Medicine L3: +30 max HP ($12M); not live: 0")
ES.Purchase(owner, "MedKit", "One")
check(po.Endgame.MedKits == 1 and spentLog[#spentLog].n == 711000, "a Med Kit: max($25k, 30 s of income) = $711,000")
ES.Purchase(owner, "Revive", "One")
check(po.Endgame.Revive == 1 and spentLog[#spentLog].n == 4266000 and ES.Purchase(owner, "Revive", "One") == false, "the Field Surgeon: max($250k, 3 min) = $4,266,000; carry 1")
ok, msg = ES.Purchase(owner, "UseRevive", "One")
check(po.Endgame.Revive == 1 and msg == "Too late to revive", "revive with no death in the last 10 s: the token is kept")
local st4 = ES.State(owner)
check(st4.Armory and #st4.Armory.Guns == 2 and st4.Workshop and #st4.Workshop == 3 and st4.Hospital and st4.Hospital.Medicine == 3, "State: 2 guns, 3 workshop classes, the hospital row")
check(#CT.ListRows("Armory", st4) >= 2 + 4 + 4 and #CT.ListRows("Workshop", st4) == 3 and #CT.ListRows("Hospital", st4) == 4, "list rows: guns + 4 attachments + 4 camos; 3 classes; 4 hospital rows")
for _, kind in ipairs({ "Armory", "Hospital" }) do
  local sm = CT.BuildStation(kind, CFrame.new(0, 0, 0))
  local sp, sl, sg = 0, 0, 0
  for _, dd in ipairs(sm:GetDescendants()) do
    if dd.ClassName == "Part" then sp += 1 elseif dd.ClassName == "PointLight" then sl += 1 elseif dd.ClassName == "SurfaceGui" then sg += 1 end
  end
  check(sp == PSC.Stations[kind].Parts and sp <= PSC.MaxParts and sl == 1 and sg == 1, string.format("the %s station = %d parts (cap %d), 1 light, 1 sign", kind, sp, PSC.MaxParts))
end

-- ── 4e. phase 5: warheads, heist kits, Intel contracts, the Black Market, reward scaling, rebirth unlocks ──
local d1 = EG.DailyContracts(470626172, 20000)
local d1b = EG.DailyContracts(470626172, 20000)
local d2 = EG.DailyContracts(470626172, 20001)
local distinct = d1[1].Kind ~= d1[2].Kind and d1[2].Kind ~= d1[3].Kind and d1[1].Kind ~= d1[3].Kind
check(#d1 == 3 and distinct and d1[1].Kind == d1b[1].Kind and d1[3].Kind == d1b[3].Kind, "3 different daily contracts, the same all day (pure of UserId + UTC day)")
check(d1[1].Kind ~= d2[1].Kind or d1[2].Kind ~= d2[2].Kind or d1[3].Kind ~= d2[3].Kind, "the next day brings a different set")
check(EG.WeeklyHvt(2800).Kind ~= nil and EG.WeeklyHvt(2800) == EG.WeeklyHvt(2800), "the weekly High-Value Target is the same for everyone in a week")
-- rebirth unlocks (the endgame's own track)
po.Prestige = 24
ES.SyncUnlocks(owner)
check(not ES.HasUnlock(470626172, "HeavyWarhead"), "R24: no Heavy Warhead unlock")
po.Prestige = 40
ES.SyncUnlocks(owner)
check(ES.HasUnlock(470626172, "HeavyWarhead") and ES.HasUnlock(470626172, "LegendParade") and ES.HasUnlock(470626172, "BastionCrest") and not ES.HasUnlock(9, "HeavyWarhead"), "R40: Heavy Warhead, Mythic Training, Bastion Crest, Legend Parade unlocked (only for him)")
-- warheads at the HQ console
atHQ = true
po.Cash = 5e9
ok, msg = ES.Purchase(owner, "Warhead", "Tactical")
check(ok and spentLog[#spentLog].n == 5e6 and spentLog[#spentLog].why == "endgame_warhead", "Tactical Warhead $5M (endgame_warhead)")
ok, msg = ES.Purchase(owner, "Warhead", "Heavy")
local rm, dm, held = ES.HeavyWarheadMults(owner)
check(ok and held and rm == 1.3 and dm == 1.2 and spentLog[#spentLog].n == 25e6, "Heavy Warhead $25M: the next launch x1.3 radius, x1.2 damage")
check(ES.Purchase(owner, "Warhead", "Heavy") == false, "holds 1 Heavy")
ES.SpendHeavy(owner)
check(select(3, ES.HeavyWarheadMults(owner)) == false and ES.HeavyWarheadMults(other) == 1, "spent on a launch; not live = x1")
-- heist kits at the Fixer
ES._SetStation("Heist", CFrame.new(229.6, 1.6, -218.5))
owner.Root.Position = ES.StationPoint("Heist")
local h0, c0, cd0, g0 = ES.HeistRules(owner, 6, 20000, 300)
check(h0 == 6 and c0 == 20000 and cd0 == 300 and g0 == 0, "no kit: the bank's own vault (6 s, $15-35k, 5 min)")
for _ = 1, 3 do ES.Purchase(owner, "Heist", "Next") end
local h3, c3, cd3, g3 = ES.HeistRules(owner, 6, 20000, 300)
check(po.Endgame.HeistKit == 3 and h3 == 14 and g3 == 7 and cd3 == 1800 and c3 == 15 * 60 * 23700, "Vault Cracker: 14 s hold, +7 guards, 30-min cooldown, 15 min of income ($21.3M)")
check(ES.Purchase(owner, "Heist", "Next") == false and ES.HeistRules(other, 6, 20000, 300) == 6, "every kit owned; not live = the old vault")
-- the plaza bounty scale
deps.EconomyService.GetCashMult = function() return 2 end
check(math.abs(ES.BountyScale(owner, 15000) - (180 * 23700 / 2) / 15000) < 1e-6 and ES.BountyScale(other, 15000) == 1, "plaza bounty: 3 min of income / the cash multiplier (x142.2 of $15k at 23.7k/s, x2); not live = x1")
-- the Black Market
ES._SetStation("BlackMarket", CFrame.new(0, 5, 300))
owner.Root.Position = ES.StationPoint("BlackMarket")
local stock = ES.MarketStock()
local cashItem = stock.Cash[1]
local item1 = EG.BlackMarket.Items[cashItem]
local before = #spentLog
ok, msg = ES.Purchase(owner, "Market", cashItem)
check(ok and #spentLog == before + (if item1.Kind == "Camo" then 1 else 1) and spentLog[#spentLog].n == math.max(1e6, 20 * 60 * 23700) and spentLog[#spentLog].why == "endgame_market", "Black Market slot 1: max($1M, 20 min of income) = $28.4M (" .. cashItem .. ")")
check(ES.Purchase(owner, "Market", cashItem) == false, "one of each")
local notInStock = nil
for id in pairs(EG.BlackMarket.Items) do if table.find(stock.Cash, id) == nil and id ~= stock.Gold then notInStock = id end end
check(notInStock == nil or ES.Purchase(owner, "Market", notInStock) == false, "an item not in this week's stock is refused")
po.Gold = 1000
local gold0 = po.Gold
ok, msg = ES.Purchase(owner, "Market", stock.Gold)
check(ok and po.Gold == gold0 - stock.GoldPrice, "the Gold slot costs Gold only (" .. stock.Gold .. " " .. stock.GoldPrice .. " Gold)")
local anyKind = EG.BlackMarket.Items[cashItem].Kind
if anyKind == "Paint" then check(ES.PaintColor(470626172) ~= nil and ES.PaintColor(9) == nil, "the paint is on his vehicles (not live: none)")
elseif anyKind == "Banner" then check(ES.BannerColor(470626172) ~= nil, "the banner colour is on his base")
elseif anyKind == "Beret" then check(ES.BeretColor(470626172) ~= nil, "the beret colour is on his soldiers")
elseif anyKind == "Trophy" then check(ES.HasTrophy(470626172), "the trophy stands on his parade ground")
else check(po.Endgame.Camos[item1.Camo] == true, "the camo is owned") end
-- the Intel Office
ES._SetStation("Intel", CFrame.new(-300, 5, 300))
owner.Root.Position = ES.StationPoint("Intel")
local paid = {}
deps.EconomyService.AddCash = function(p, n, why) table.insert(paid, { n = n, why = why }); return true end
deps.EconomyService.AddGold = function(p, n, why) table.insert(paid, { n = n, why = why, gold = true }); return true end
local st5 = ES.State(owner)
local r1 = st5.Intel.Rows[1]
ok, msg = ES.Purchase(owner, "Claim", "D1")
check(not ok and string.find(msg, "0/") ~= nil, "a contract not done yet cannot be claimed (" .. tostring(msg) .. ")")
ES.NoteContract(owner, r1.Kind, r1.Need)
ok, msg = ES.Purchase(owner, "Claim", "D1")
check(ok and paid[1].n == math.max(50000, 8 * 60 * 23700) and paid[1].why == "endgame_reward", "contract done -> claimed: 8 min of income ($11.4M) as endgame_reward (never multiplied again)")
check(ES.Purchase(owner, "Claim", "D1") == false, "a contract pays once")
ES.NoteContract(other, r1.Kind, 5)
local hv = ES.State(owner).Intel.Hvt
ES.NoteContract(owner, hv.Kind, hv.Need)
ok, msg = ES.Purchase(owner, "Claim", "HVT")
check(ok and paid[#paid].gold == true and paid[#paid].n == 50 and paid[#paid - 1].n == 20 * 60 * 23700, "the weekly HVT: 20 min of income + 50 Gold")
-- raided-by + scouting
for i = 1, 7 do ES.NoteRaidedBy(owner, other) end
check(#ES.State(owner).Intel.RaidedBy == 5, "raided-by keeps the last 5")
profiles[9].BasePlotId = 4
BY_UID[9] = other
local prevGet = Players.GetPlayers
Players.GetPlayers = function() return { owner, other } end
ok, msg = ES.Purchase(owner, "Scout", "4")
local rep = ES.State(owner).Intel.Report
check(ok and rep and rep.Name ~= nil and spentLog[#spentLog].why == "endgame_scout" and spentLog[#spentLog].n == math.max(10000, 60 * 23700), "scouting an online base: 1 min of income ($1.42M), the report is stored")
check(ES.Purchase(owner, "Scout", "5") == false, "nobody on that plot: refused (offline bases are never scouted)")
-- Code Bot v171 (Shaun 2026-10-01: "the scout report I paid for did nothing"): the paid result is shown and kept
do
check(profiles[470626172].Endgame.ScoutReport == rep and rep.Price == spentLog[#spentLog].n, "v171 scout: the report is saved in profile.Endgame (survives a rejoin / server move), with its price")
local fired = {}
deps.RemoteSetup = { Get = function(name) return { IsA = function(_, c) return c == "RemoteEvent" end, FireClient = function(_, p, kind, data) table.insert(fired, { name = name, p = p, kind = kind, data = data }) end } end }
ES.PushScoutCard(owner)
check(#fired == 1 and fired[1].p == owner and fired[1].kind == "ScoutReport" and fired[1].data == rep, "v171 scout: the result card is pushed to HIM (FeaturePush \"ScoutReport\") right after the buy")
ES.PushScoutCard(owner)
check(#fired == 1, "v171 scout: the card is pushed once per buy")
for _, fn in ipairs(Players.PlayerRemoving.fns) do fn(owner) end
check(ES.State(owner).Intel.Report == rep, "v171 scout: after he leaves (this server forgets it) the State still has his report from the profile")
local rowsI = CT.ListRows("Intel", ES.State(owner))
check(rowsI[1] and rowsI[1].Kind == "ScoutView" and rowsI[1].Label == "VIEW" and rowsI[1].Price == 0 and string.find(rowsI[1].Name, "SCOUT REPORT", 1, true) == 1, "v171 scout: the report LEADS the Intel list (VIEW, never a purchase)")
local SLn = CT.ScoutLines({ Name = "Rival", Tier = 2, GateHp = 900, GateMax = 1200, Turrets = 3, Guards = 4, Defence = { Plating = 2 }, Verdict = "Even fight", At = os.time() })
check(SLn.Title == "SCOUT REPORT: RIVAL" and string.find(SLn.Line1, "900 / 1200 HP", 1, true) ~= nil and string.find(SLn.Line2, "3 turrets", 1, true) ~= nil and SLn.Line4 == "Your army: Even fight" and SLn.Line5 == "Scouted just now", "v171 scout: the card lines (tier, gate HP, turrets / guards, defences, your army's verdict)")
local SL0 = CT.ScoutLines({ Name = "X" })
check(SL0.Line1 == "Base tier 0 · gate unknown" and SL0.Line4 == "Your army: no verdict (no soldiers?)", "v171 scout: a sparse report still renders (no nil errors)")
local nSpent, cash0 = #spentLog, profiles[470626172].Cash
local realBuild = ES.BuildScoutReport
ES.BuildScoutReport = function() error("boom") end
ok, msg = ES.Purchase(owner, "Scout", "4")
ES.BuildScoutReport = realBuild
check(not ok and string.find(tostring(msg), "nothing charged", 1, true) ~= nil and #spentLog == nSpent and profiles[470626172].Cash == cash0, "v171 scout: a report that cannot be built charges NOTHING (" .. tostring(msg) .. ")")
end
Players.GetPlayers = prevGet
-- the new stations + the base extras
for _, kind in ipairs({ "Intel", "BlackMarket", "Heist" }) do
  local sm = CT.BuildStation(kind, CFrame.new(0, 0, 0))
  local sp, sl, sg = 0, 0, 0
  for _, dd in ipairs(sm:GetDescendants()) do
    if dd.ClassName == "Part" then sp += 1 elseif dd.ClassName == "PointLight" then sl += 1 elseif dd.ClassName == "SurfaceGui" then sg += 1 end
  end
  -- v157: the Black Market adds its own door sign (1 part, 1 SurfaceGui) while the Armory downstairs is not live
  local ex = if kind == "BlackMarket" and not EG.LiveFor(Players.LocalPlayer.UserId, "Mastery") then 1 else 0
  check(sp == PSC.Stations[kind].Parts + ex and sp <= PSC.MaxParts and sl <= 1 and sg == 1 + ex, string.format("the %s station = %d parts (cap %d), %d light, %d sign", kind, sp, PSC.MaxParts, sl, 1 + ex))
end
local ctxX = table.clone(ctx)
ctxX.Crest = true
ctxX.Trophy = true
local mx0 = BTB.Build(ctxX, 0)
local crest, trophy = 0, 0
for _, dd in ipairs(mx0:GetDescendants()) do
  if dd.ClassName == "Part" and string.sub(dd.Name, 1, 5) == "Crest" then crest += 1 elseif dd.ClassName == "Part" and string.sub(dd.Name, 1, 6) == "Trophy" then trophy += 1 end
end
check(crest == 3 and trophy > 0 and trophy <= 30, string.format("the Bastion Crest (3 parts) and the trophy cannon (%d parts, cap 30) even at tier 0", trophy))
-- Code Bot v171: the Recruit Pack's gold base trim (real geometry on HIS base; any tier)
do
-- a fresh builder with real colour values (the shared stub's Color3 is opaque)
local prevC3, prevBTB = Color3, CACHE["Modules/BaseTierBuilder"]
Color3 = { new = function(r, g, b) return { R = r, G = g, B = b } end, fromRGB = function(r, g, b) return { R = r / 255, G = g / 255, B = b / 255 } end, fromHSV = function() return { R = 0, G = 0, B = 0 } end }
CACHE["Modules/BaseTierBuilder"] = nil
local BTB = require(node("Modules/BaseTierBuilder"))
local function trimCount(model)
  local c = {}
  local okAll = true
  for _, ch in ipairs(model:GetChildren()) do
    if ch.Name == "RecruitTrim" then
      for _, dd in ipairs(ch:GetDescendants()) do
        if dd.ClassName == "Part" then
          c[dd.Name] = (c[dd.Name] or 0) + 1
          if dd.CanCollide ~= false or dd.CanQuery ~= false or dd.Material ~= Enum.Material.Metal then okAll = false end
          local col = dd.Color
          if not (col and col.R > 0.7 and col.G > 0.5 and col.B < 0.3) then okAll = false end
        end
      end
    end
  end
  return c, okAll
end
local ctxR = table.clone(ctx)
ctxR.Walls = {
  { CFrame = CFrame.new(0, 11.75, -158), Size = Vector3.new(317, 21.5, 2) }, { CFrame = CFrame.new(-158, 11.75, 0), Size = Vector3.new(2, 21.5, 317) },
  { CFrame = CFrame.new(158, 11.75, 0), Size = Vector3.new(2, 21.5, 317) }, { CFrame = CFrame.new(-84, 11.75, 158), Size = Vector3.new(149, 21.5, 2) },
  { CFrame = CFrame.new(84, 11.75, 158), Size = Vector3.new(149, 21.5, 2) },
}
ctxR.RecruitTrim = true
local rc0, rok0 = trimCount(BTB.Build(ctxR, 0))
check(rc0.RecruitWallBand == 5 and rc0.RecruitWallStripe == 5 and rc0.RecruitPostBand == 2 and rc0.RecruitPostFinial == 2 and rok0,
  "v171 recruit trim at tier 0: a gold Metal band + pinstripe on all 5 wall segments, a band + finial on both gate posts; all gold, no collision, no ray")
local mR3 = BTB.Build(ctxR, 3)
local rc3, rok3 = trimCount(mR3)
local goldFin = 0
for _, dd in ipairs(mR3:GetDescendants()) do if dd.Name == "GateRoofFinial" and dd.Color.G > 0.7 then goldFin += 1 end end
check(rc3.RecruitWallBand == 5 and rc3.RecruitPostFinial == nil and goldFin == 2 and rok3, "v171 recruit trim at tier 3: the wall bands, and the post roofs' own finials turn Recruit gold (no second ball)")
local ctxN = table.clone(ctxR); ctxN.RecruitTrim = nil
local rcN = trimCount(BTB.Build(ctxN, 3))
check(next(rcN) == nil, "v171 recruit trim: none without the pack")
local _, pR = BTB.Build(ctxR, 2)
local _, pN = BTB.Build(ctxN, 2)
check(pR - pN == 5 * 2 + 2, string.format("v171 recruit trim adds %d parts (12 = 5 walls x 2 + 2 post bands)", pR - pN))
CACHE["Configs/MonetizationConfig"] = { RecruitPackLiveFor = function(uid) return uid == 470626172 end }
check(ES.HasRecruitTrim(owner, { Entitlements = { RecruitPack = true } }) == true and ES.HasRecruitTrim(owner, { Entitlements = {} }) == false
  and ES.HasRecruitTrim(other, { Entitlements = { RecruitPack = true } }) == false and ES.HasRecruitTrim(owner, nil) == false,
  "v171 recruit trim: built from the SAVED entitlement (back on every join), only while the pack is live for him")
CACHE["Configs/MonetizationConfig"] = nil
Color3 = prevC3
CACHE["Modules/BaseTierBuilder"] = prevBTB
end
local st6 = ES.State(owner)
check(#CT.ListRows("Intel", st6) >= 4 and #CT.ListRows("BlackMarket", st6) >= 4 and #CT.ListRows("Heist", st6) == 1 and #CT.ListRows("HQ", st6) >= 3, "list rows: Intel, Black Market, Heist, the HQ warheads")

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

-- codebot_v166: launched: every endgame part is live for a non-owner
EG.Live.OwnerFirst = EG_LAUNCHED
check(EG_LAUNCHED == false, "codebot_v166: EndgameConfig.Live.OwnerFirst=false")
local egOff = {}
for part, on in pairs(EG.Parts) do if on == true and not EG.LiveFor(9, part) then table.insert(egOff, part) end end
check(#egOff == 0 and EG.AnyLiveFor(9) and EG.CamoLiveFor(9), "codebot_v166: every endgame part live for a non-owner (" .. table.concat(egOff, ",") .. ")")
check(ES.ScaledCost(other, { Prestige = 3, Endgame = {} }, "CommandCenter", 10000) == 16000, "codebot_v166: ScaledCost: a non-owner at R3 pays 1.6x too")
check(math.abs(ES.EmpireMultFor(other, { Endgame = { EmpireLevel = 10 } }) - 1.2) < 1e-9, "codebot_v166: EmpireMultFor: a non-owner at L10 = 1.20")
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
    sqs = (SV / "Services/SquadOrdersService.luau").read_text(encoding="utf-8")
    acs = (SV / "Modules/ArmyController.luau").read_text(encoding="utf-8")
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
        ("R *= rm" in (SV / "Services/NukeService.luau").read_text(encoding="utf-8") and "N.Damage * heavyDmg" in (SV / "Services/NukeService.luau").read_text(encoding="utf-8"), "the Heavy Warhead rides on the one ApplyRadiusDamage call (radius + damage)"),
        ("if prog >= heistNeed then" in (SV / "Services/BankRaidService.luau").read_text(encoding="utf-8") and "local cd = heistCd" in (SV / "Services/BankRaidService.luau").read_text(encoding="utf-8"), "the heist kit's hold / payout / cooldown in the bank's own raid loop"),
        (all("NoteContract" in (p).read_text(encoding="utf-8") for p in (SV / "Services/SiteActivityService.luau", SV / "Services/TerritoryService/init.luau", SV / "Services/CheckpointGuardService.luau", SV / "Services/MoneyCollectorService.luau", SV / "Modules/ArmyPlan.luau", SV / "Services/NukeService.luau")),
         "every contract event is fed from the game's own hook (garrison, outpost, checkpoint guard, defended raid, SEND win, warhead)"),
        ("local elite = if eg and eg.UnitElite then eg.UnitElite(owner, slot) else nil" in sqs and "armyDamageBase() * SquadOrdersService._UnitDmg(player, unit) * armyBoostMult(player), credit)" in sqs
         and "local base = armyDamageBase() * SquadOrdersService._UnitDmg(player, unit) * armyBoostMult(player)" in sqs, "Elite HP at spawn and Elite damage at BOTH unit damage sites (the one damage path)"),
        ("c = ArmyController.ScaledCfg(c, es)" in acs, "the formation spacing grows with the largest soldier in the block"),
        ("PivotTo" not in sqs.split("function SquadOrdersService._ReapplyElite")[1].split("function SquadOrdersService.Init")[0], "a re-train in place never moves a soldier"),
        ("Instance.new(\"Humanoid\")" not in btb and "Neon" not in btb, "BaseTierBuilder: no Humanoid, no Neon"),
        ("Endgame" not in bal, "structure income reads the raw Costs (BalanceConfig never sees the scale)"),
        ("profile.Endgame =" not in pres and "profile.Endgame" not in pres.replace("x.EndgameKeep", ""), "PrestigeService never clears profile.Endgame (kept on both paths)"),
        ("Endgame" not in mon, "no Robux path to the endgame (MonetizationService never grants it)"),
        (new.count("PivotTo") == 1 and "c:PivotTo(fell + Vector3.new(0, 3, 0))" in new and "FastTravel" not in new and "TeleportService" not in new,
         "no fast travel / teleport; the ONE PivotTo is the revive putting him back on the spot he fell"),
        ("TakeDamage" not in new and all(l.strip().startswith(("hh.Health = hh.MaxHealth", "h.Health = math.min(h.MaxHealth", "h.Health = h.MaxHealth * R.HpFraction")) for l in new.splitlines() if ".Health =" in l),
         "the only Health writes: the Hospital heal, the Med Kit, the revive and the army medic (soldiers)"),
        ("CombatService._GunDef(player, def) -- claude-bud JOB 39" in (SV / "Services/CombatService/init.luau").read_text(encoding="utf-8"), "RequestFire uses the player's gun row (mastery / attachments) for rate, range and damage"),
        ("HPMult = wsHp," in (SV / "Services/VehicleService.luau").read_text(encoding="utf-8"), "vehicle HP through VehicleHealth's HPMult (the Workshop)"),
        ("WeaponVisuals.ApplyCamo(mdl, character:GetAttribute(\"WE_GunCamo\"))" in (CL / "Modules/WeaponVisuals.luau").read_text(encoding="utf-8"), "the camo on every built gun (local and remote)"),
        ((CL / "Controllers/CombatController.luau").read_text(encoding="utf-8").count("W2.gunMod(") >= 5, "the client paces / reaches / reloads with the same multipliers"),
        ("mx = math.min(math.floor(mx * (b + med) / b + 0.5)" in (SV / "Services/ArmourService.luau").read_text(encoding="utf-8"), "Combat Medicine on the base HP before Double HP / armour, capped at 400"),
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
