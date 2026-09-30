"""claude-bud JOB 33: real-code tests in the Luau CLI for the rebirth overhaul (stand-ins: run_kit_detail_test.PRELUDE).

1. ZONES (the real Modules/RebirthZoneBuilder + WorldKits): every zone at level 0 / 1 / 2 / 3:
   * each level has more parts than the one before (it visibly grows);
   * every part stays inside its annex yard;
   * every cluster is <= 64 studs across (WorldKits.Finish refuses bigger);
   * the locked fence builds;
   * the part total of all 7 zones at level 3 stays within a budget.
2. NUKE (the real Services/NukeService): Charge() over time / capacity; Targets() never names a point within
   BaseClearStuds of any base and always offers the Central Plaza when it is clear.
3. ZONE SERVICE (the real Services/RebirthZoneService on stub services):
   * ArmyBonus = the +2 per rebirth perk + Elite Barracks;
   * the income per tick of built zones only;
   * missile reload cut and raid shield bonus by level;
   * Upgrade refuses a locked zone, spends "rebirthzone_<Id>" once per level, stops at level 3.
4. CONFIG (the real PrestigeConfig / RebirthConfig / WeaponConfig / VehicleConfig):
   * the unlock track is sorted (the Frigate R16 / Cruiser R18 order bug is fixed);
   * every granted id exists;
   * MinLevelFor pacing; NextRebirths; the richer GAIN column;
   * each rebirth gun's DPS is within +20 % of its base gun.
Run: LUAU=path/to/luau(.exe) python tools/sim/run_rebirth_test.py   (exit 1 on any failure)"""
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
    "Configs/WorldConfig": SH / "Configs/WorldConfig.luau",
    "Configs/WorldDetailConfig": SH / "Configs/WorldDetailConfig.luau",
    "Configs/PlazaBuildingsConfig": SH / "Configs/PlazaBuildingsConfig.luau",
    "Configs/RebirthConfig": SH / "Configs/RebirthConfig.luau",
    "Configs/RebirthZonesConfig": SH / "Configs/RebirthZonesConfig.luau",
    "Configs/PrestigeConfig": SH / "Configs/PrestigeConfig.luau",
    "Configs/WeaponConfig": SH / "Configs/WeaponConfig.luau",
    "Configs/VehicleConfig": SH / "Configs/VehicleConfig.luau",
    "Configs/NukeConfig": SH / "Configs/NukeConfig.luau",
    "Configs/TerritoryConfig": SH / "Configs/TerritoryConfig.luau",
    "Configs/BaseConfig": SH / "Configs/BaseConfig.luau",
    "Configs/BaseLayoutConfig": SH / "Configs/BaseLayoutConfig.luau",
    "Configs/WorldSitesConfig": SH / "Configs/WorldSitesConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
    "Util/PlotFrame": SH / "Util/PlotFrame.luau",
    "Modules/WorldKits": SV / "Modules/WorldKits.luau",
    "Modules/RebirthZoneBuilder": SV / "Modules/RebirthZoneBuilder.luau",
    "Services/NukeService": SV / "Services/NukeService.luau",
    "Services/RebirthZoneService": SV / "Services/RebirthZoneService.luau",
}

EXTRA = r'''
OverlapParams = { new = function() return {} end }
RaycastParams = { new = function() return {} end }
task = { spawn = function() end, wait = function() end, delay = function() end, defer = function() end }
local function signal() local s = { fns = {} }; s.Connect = function(self, fn) table.insert(self.fns, fn); return { Disconnect = function() end } end; s.Fire = function(self, ...) for _, f in ipairs(self.fns) do f(...) end end; return s end
local P = { UserId = 470626172, Name = "Owner", Parent = true, CharacterAdded = signal(), Character = nil }
P.SetAttribute = function(self, k, v) self["attr_" .. k] = v end
P.GetAttribute = function(self, k) return self["attr_" .. k] end
local Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return { P } end, GetPlayerByUserId = function(_, id) if id == P.UserId then return P end end }
local zonesRoot = Instance.new("Folder")
local WS = { GetPartBoundsInBox = function() return {} end, Raycast = function() return nil end,
  FindFirstChild = function(_, n) if n == "WE_RebirthZones" then return zonesRoot end return nil end, FindFirstChildOfClass = function() return nil end }
local RunService = { IsStudio = function() return true end }
local prevGame = game
game = { GetService = function(_, n)
  if n == "Players" then return Players elseif n == "Workspace" then return WS elseif n == "RunService" then return RunService end
  return prevGame:GetService(n) end }
PLAYER = P
'''

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
-- ── 1. zones ──
local WK = require(node("Modules/WorldKits"))
local B = require(node("Modules/RebirthZoneBuilder"))
local RC = require(node("Configs/RebirthConfig"))
local ZC = require(node("Configs/RebirthZonesConfig"))
local made = {}
local realPart = WK.Part
WK.Part = function(ps, parent) local p = realPart(ps, parent); table.insert(made, p); return p end
local finishFails = 0
local realFinish = WK.Finish
WK.Finish = function(cl, parent) local info = realFinish(cl, parent); if not info.Ok then finishFails += 1; print("  cluster refused: " .. tostring(info.Reason)) end; return info end
local total3 = 0
for _, zid in ipairs(RC.ZoneOrder) do
  local a = ZC.Annex[zid]
  local frame = CFrame.new(0, 0.5, 0)
  local prev = -1
  for L = 0, 3 do
    made = {}
    local folder = Instance.new("Folder")
    local console = B.Build(zid, L, frame, a.W, a.D, Color3.fromRGB(200, 150, 60), folder)
    local n = 0
    local outside = 0
    for _, p in ipairs(made) do
      if not rawget(p, "__destroyed") then
        n += 1
        local rel = frame:ToObjectSpace(p.CFrame)
        local c = rel.Position
        if math.abs(c.X) > a.W * 0.5 + 2 or math.abs(c.Z) > a.D * 0.5 + 2 then outside += 1 end
      end
    end
    check(n > prev, string.format("%s L%d: %d parts (more than L%d)", zid, L, n, L - 1))
    check(outside == 0, string.format("%s L%d: every part inside the %dx%d yard (%d outside)", zid, L, a.W, a.D, outside))
    check(console ~= nil, zid .. " L" .. L .. ": a console")
    prev = n
    if L == 3 then total3 += n end
  end
  made = {}
  B.Locked(zid, 3, CFrame.new(0, 0.5, 0), a.W, a.D, Instance.new("Folder"))
  check(#made >= 6, zid .. ": the locked fence + sign build (" .. #made .. " parts)")
end
check(finishFails == 0, "every zone cluster <= 64 studs (WorldKits.Finish refused " .. finishFails .. ")")
check(total3 <= 450, "all 7 zones at level 3: " .. total3 .. " parts (<= 450; the kits' TrussPart ladders not counted)")
WK.Part = realPart
WK.Finish = realFinish

-- ── 2. nuke ──
local NS = require(node("Services/NukeService"))
local r, f = NS.Charge(0, 0, 1000, 2, 600)
check(r == 0 and f == 1000, "charge: an idle silo starts charging")
r, f = NS.Charge(0, 1000, 1600, 2, 600)
check(r == 1 and f == 1600, "charge: one warhead after its time")
r, f = NS.Charge(0, 1000, 5000, 2, 600)
check(r == 2 and f == 0, "charge: stops at capacity")
r, f = NS.Charge(3, 0, 5000, 2, 600)
check(r == 2, "charge: never above capacity")
CACHE["Modules/WorldSites"] = { List = function() return { { Id = "CampViper", Name = "Camp Viper", Kind = "camp", X = -450, Z = -650, Y = 1 } } end }
local PF = require(node("Util/PlotFrame"))
local BC = require(node("Configs/BaseConfig"))
local targets = NS.Targets()
local near = 0
for _, t in ipairs(targets) do
  for plotId = 1, BC.MaxPlots do
    local pp = PF.PlotPosition(plotId)
    if math.sqrt((pp.X - t.Pos.X) ^ 2 + (pp.Z - t.Pos.Z) ^ 2) < ZC.Nuke.BaseClearStuds then near += 1 end
  end
end
check(#targets >= 3 and near == 0, string.format("%d nuke targets, none within %d of a base", #targets, ZC.Nuke.BaseClearStuds))
check(targets[1] ~= nil and targets[1].Id == "Plaza", "the Central Plaza is a target")

-- ── 3. zone service ──
local cash, spends = 1e9, {}
local profile = { Prestige = 5, RebirthZones = { WestYard = 2, EastYard = 1, EastStrip = 0, WestStrip = 3, WestFlank = 2 }, Level = 50 }
local deps = {
  DataService = { GetProfile = function() return profile end, MarkDirty = function() end, OnProfileLoaded = function(fn) fn(PLAYER, profile) end },
  EconomyService = { SpendCash = function(_, n, reason) if cash < n then return false end cash -= n; table.insert(spends, reason .. ":" .. n); return true end },
  BaseService = { GetOwnedPlotId = function() return 1 end, OnPlotReady = function() end },
  RateLimitService = { Allow = function() return true end },
}
local RZS = require(node("Services/RebirthZoneService"))
RZS.Init(deps)
check(RZS.ArmyBonus(profile) == 10 + 5, "army bonus = +2 x 5 rebirths (10) + Elite Barracks L1 (5): " .. RZS.ArmyBonus(profile))
check(RZS.FlatIncomePerTick(profile, PLAYER) == 350 + 50 + 300 + 0, "income per tick of built zones (TankFactory L2 350 + Barracks L1 50 + Battery L3 300; the L0 refinery 0; WestFlank is Rebirth 8): " .. RZS.FlatIncomePerTick(profile, PLAYER))
check(RZS.MissileReloadCut(PLAYER) == 270, "Artillery Battery L3 cuts the missile reload by 270 s")
check(RZS.RaidShieldBonus(profile) == 0, "the Bunker Complex (Rebirth 8) is not reached at Rebirth 5: no shield bonus")
local ok, why = RZS.Upgrade(PLAYER, "WestFlank")
check(ok == false and why == "Locked", "a zone not reached yet cannot be built")
profile.Prestige = 6 -- Refinery Row opens at Rebirth 6
ok = RZS.Upgrade(PLAYER, "EastStrip")
check(ok == true and profile.RebirthZones.EastStrip == 1 and spends[#spends] == "rebirthzone_EastStrip:150000", "Refinery L1 costs $150,000 (" .. tostring(spends[#spends]) .. ")")
RZS.Upgrade(PLAYER, "EastStrip"); RZS.Upgrade(PLAYER, "EastStrip")
ok, why = RZS.Upgrade(PLAYER, "EastStrip")
check(profile.RebirthZones.EastStrip == 3 and ok == false and why == "Max", "the refinery stops at level 3")
check(#spends == 3, "one spend per level (" .. #spends .. ")")
profile.Prestige = 8
check(RZS.RaidShieldBonus(profile) == 240, "Bunker Complex L2 at Rebirth 8: +240 s raid shield")

-- ── 4. config ──
local PC = require(node("Configs/PrestigeConfig"))
local WC = require(node("Configs/WeaponConfig"))
local VC = require(node("Configs/VehicleConfig"))
local sorted, missing = true, {}
for i, u in ipairs(PC.RebirthUnlocks) do
  if i > 1 and u.AtPrestige < PC.RebirthUnlocks[i - 1].AtPrestige then sorted = false end
  if u.Kind == "Weapon" and WC.Weapons[u.Id] == nil then table.insert(missing, u.Id) end
  if u.Kind == "Vehicle" and VC.Vehicles[u.Id] == nil then table.insert(missing, u.Id) end
end
check(sorted, "the unlock track is sorted by rebirth (Frigate R16 before Cruiser R18)")
check(#missing == 0, "every granted id exists (" .. table.concat(missing, ",") .. ")")
local gaps = {}
for rb = 1, 20 do
  local any = false
  for _, u in ipairs(PC.RebirthUnlocks) do if u.AtPrestige == rb then any = true end end
  for _, z in pairs(RC.Zones) do if z.Tier == rb then any = true end end
  if not any then table.insert(gaps, tostring(rb)) end
end
check(#gaps <= 2, "almost every rebirth 1-20 gives something (empty: " .. table.concat(gaps, ",") .. ")")
check(PC.MinLevelFor(0, true) == 40 and PC.MinLevelFor(3, true) == 52 and PC.MinLevelFor(40, true) == 90 and PC.MinLevelFor(5, false) == 40, "pacing: 40 / 52 / cap 90; off = 40")
local zn = { [4] = "Drone Bay", [5] = "East Yard" }
local n3 = PC.NextRebirths(3, 3, zn)
check(#n3 == 3 and string.sub(n3[1], 1, 2) == "R4" and string.find(n3[1], "Drone Bay") ~= nil, "next 3 rebirths: " .. table.concat(n3, " | "))
for _, line in ipairs(n3) do check(#line <= 30, "next-3 line fits 30 chars: " .. line) end
local sum = PC.RebirthSummary("Cash", { Built = 12, Prestige = 3, NextUnlock = "Drone", BusinessesOn = false, Zone = "Drone Bay", Soldiers = 2, StartCash = 65000, Gold = 80 })
local gainText = table.concat(sum.Gain, "|")
check(string.find(gainText, "New zone: Drone Bay") ~= nil and string.find(gainText, "+2 army soldiers") ~= nil, "GAIN shows the zone and the soldiers: " .. gainText)
check(sum.Reset[1] == "Cash back to $65,000", "RESET shows the new starting cash: " .. tostring(sum.Reset[1]))
local base = { VanguardCarbine = "AssaultRifle", TempestSMG = "SMG", WardenShotgun = "Shotgun", TalonSniper = "Sniper", HavocLauncher = "RocketLauncher" }
for id, b in pairs(base) do
  local d, bd = WC.Weapons[id], WC.Weapons[b]
  local ratio = (d.Damage * d.FireRate) / (bd.Damage * bd.FireRate)
  check(ratio > 1 and ratio <= 1.2, string.format("%s DPS x%.2f of %s (<= 1.20)", id, ratio, b))
  check(d.CostCash == 0 and d.UnlockLevel == 1, id .. " is never sold and usable at level 1")
end
print(string.format("REBIRTH TEST: %d failed", fails))
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
print(out if os.environ.get("VERBOSE") else ("\n".join(l for l in out.splitlines() if l.startswith("FAIL") or l.startswith("REBIRTH TEST") or l.startswith("  cluster")) or out))
if r.returncode != 0:
    print(r.stderr.strip()[-2500:])
    sys.exit(1)
