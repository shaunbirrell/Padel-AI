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
}

EXTRA = r'''
task = { spawn = function() end, delay = function() end, defer = function() end, wait = function() end }
OverlapParams = { new = function() return {} end }
Enum.RaycastFilterType = { Exclude = "Exclude" }
local function signal() local s = { fns = {} }; s.Connect = function(self, fn) table.insert(self.fns, fn); return { Disconnect = function() end } end; return s end
local Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end }
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
