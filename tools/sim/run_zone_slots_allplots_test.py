"""Code Bot (Shaun's phone test, 2026-10-02: "I was given a base that doesn't have all 7 rebirth zones").
Every plot index 1..BaseConfig.MaxPlots gets all 7 rebirth zones (incl. the Nuclear Silo) for the owner, on the REAL
RebirthZonesConfig.ResolveSlots, against the FULL world model the live check (RebirthZoneService.checkSlotAt /
checkApronAt) meets. JOB 69's run_zone_slots_test.py left out three things the live part-overlap check DOES see, so it
passed 70/70 while the live server put ZONE BOARDS on plots 7, 8 and 10:
  * WorldConfig.POIs (Port, Oil Field, Quarry, Ruins, Airstrip, Fort Ironclad, Ridge Camp ...): their kits are
    WE_Cluster "poi:*", which is NOT in RebirthZonesConfig.ClearableSources -> "blocked by" in the live check;
  * WorldFillConfig.Roads (the gate spur roads P1..P10, 14 wide, not clusters) and WorldFillConfig.Bridges;
  * every plot's gate apron (WorldConfig.Hygiene.GateApron) and land garage pad (WorldConfig.Spawns.Garage), the NPC /
    event anchors (WorldConfig.Spawns.NPC / Event) and the Empire Bank ring.
On top of the JOB 69 model: the land edge, the 6 world roads, every plot pad + dock channel, public water, the world
sites and every outpost (incl. the Home Outposts).
Asserts, per plot index (each one on its own line): 7 of 7 zones placed, the Nuclear Silo placed, no two zones of the
plot overlap, no zone overlaps ANOTHER plot's zones (the live check ignores WE_RebirthZones, so it cannot see them),
every slot within MaxSlotStuds of the plot centre. The OLD candidate list (JOB 69's 24 AnnexAlt) is replayed too: it
must reproduce the gaps (the proven root cause).
Run: LUAU=path/to/luau python3 tools/sim/run_zone_slots_allplots_test.py   (exit 1 on any failure; VERBOSE=1 table)"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_kit_detail_test import PRELUDE  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SH = ROOT / "src/ReplicatedStorage/Shared"
MODS = {
    "Configs/RebirthZonesConfig": SH / "Configs/RebirthZonesConfig.luau",
    "Configs/BaseConfig": SH / "Configs/BaseConfig.luau",
    "Configs/BaseLayoutConfig": SH / "Configs/BaseLayoutConfig.luau",
    "Configs/BusinessConfig": SH / "Configs/BusinessConfig.luau",
    "Configs/WorldSitesConfig": SH / "Configs/WorldSitesConfig.luau",
    "Configs/TerritoryConfig": SH / "Configs/TerritoryConfig.luau",
    "Configs/WaterConfig": SH / "Configs/WaterConfig.luau",
    "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
    "Configs/EconomyConfig": SH / "Configs/EconomyConfig.luau",
    "Configs/WorldConfig": SH / "Configs/WorldConfig.luau",
    "Configs/WorldFillConfig": SH / "Configs/WorldFillConfig.luau",
    "Configs/BankRaidConfig": SH / "Configs/BankRaidConfig.luau",
    "Util/PlotFrame": SH / "Util/PlotFrame.luau",
}

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local ZC = require(node("Configs/RebirthZonesConfig"))
local BC = require(node("Configs/BaseConfig"))
local PF = require(node("Util/PlotFrame"))
local WS = require(node("Configs/WorldSitesConfig"))
local TC = require(node("Configs/TerritoryConfig"))
local WC = require(node("Configs/WaterConfig"))
local WCfg = require(node("Configs/WorldConfig"))
local WF = require(node("Configs/WorldFillConfig"))
local Bank = require(node("Configs/BankRaidConfig"))
local HALF = BC.PlotSize.X / 2
local ROAD_HALF = 7 + 5
local MAX_SLOT_STUDS = 520 -- a zone further than this from the plot centre is not "on the base"

local function worldBox(plotId, b)
  local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
  for _, c in ipairs({ { b[1], b[3] }, { b[1], b[4] }, { b[2], b[3] }, { b[2], b[4] } }) do
    local w = PF.LocalToWorld(plotId, c[1], c[2])
    x0, x1, z0, z1 = math.min(x0, w.X), math.max(x1, w.X), math.min(z0, w.Z), math.max(z1, w.Z)
  end
  return { x0, x1, z0, z1 }
end
local function ov(a, b) return a[1] < b[2] and b[1] < a[2] and a[3] < b[4] and b[3] < a[4] end
local function ovCircle(b, x, z, r)
  local cx, cz = math.clamp(x, b[1], b[2]), math.clamp(z, b[3], b[4])
  return (cx - x) ^ 2 + (cz - z) ^ 2 < r * r
end

local OBST = {} -- { N, B } boxes or { N, C = { x, z, r } } circles
local function add(name, b) table.insert(OBST, { N = name, B = b }) end
local function addC(name, x, z, r) table.insert(OBST, { N = name, C = { x, z, r } }) end
-- the JOB 69 model
for _, x in ipairs({ -800, 0, 800 }) do local e = WC.RoadEnds["RoadX" .. x]; add("RoadX" .. x, { x - ROAD_HALF, x + ROAD_HALF, e.Min, e.Max }) end
for _, z in ipairs({ -800, 0, 800 }) do local e = WC.RoadEnds["RoadZ" .. z]; add("RoadZ" .. z, { e.Min, e.Max, z - ROAD_HALF, z + ROAD_HALF }) end
for pid = 1, BC.MaxPlots do
  add("Plot" .. pid, worldBox(pid, { -HALF, HALF, -HALF, HALF }))
  add("Channel" .. pid, worldBox(pid, { 108, 148, -2400, -HALF }))
end
for _, r in ipairs(WC.Public) do add("Water " .. r.Name, { r.X0, r.X1, r.Z0, r.Z1 }) end
for _, st in ipairs(WS.Sites) do addC("Site " .. st.Id, st.X, st.Z, (st.R or 46) + 6) end
for id, t in pairs(TC.Territories or {}) do
  if typeof(t.Position) == "Vector3" and t.Radius then addC("Outpost " .. id, t.Position.X, t.Position.Z, t.Radius + 6) end
end
-- what JOB 69 left out (the live check sees all of it)
for _, p in ipairs(WCfg.POIs) do
  if p.Enabled ~= false then
    if p.Rect then add("POI " .. p.Id, { p.Rect.X0, p.Rect.X1, p.Rect.Z0, p.Rect.Z1 })
    elseif p.Circle then addC("POI " .. p.Id, p.Circle.X, p.Circle.Z, p.Circle.R) end
  end
end
for _, r in ipairs(WF.Roads) do
  add("Fill " .. r.Name, { math.min(r.X0, r.X1) - ROAD_HALF, math.max(r.X0, r.X1) + ROAD_HALF, math.min(r.Z0, r.Z1) - ROAD_HALF, math.max(r.Z0, r.Z1) + ROAD_HALF })
end
for _, b in ipairs(WF.Bridges) do local hw = WF.Bridge.Width / 2 + 4; add("Fill " .. b.Name, { b.X - hw, b.X + hw, b.Z0 - WF.Bridge.RampLen, b.Z1 + WF.Bridge.RampLen }) end
local GA = WCfg.Hygiene.GateApron
for pid = 1, BC.MaxPlots do add("GateApron P" .. pid, worldBox(pid, { GA.X0 - 6, GA.X1 + 6, GA.Z0, GA.Z1 + 6 })) end
local ph = WCfg.Spawns.PadSize.X * 0.5 + 6
for _, g in ipairs(WCfg.Spawns.Garage) do
  local x, z
  if g.PlotId then local w = PF.LocalToWorld(g.PlotId, g.LocalX, g.LocalZ); x, z = w.X, w.Z else x, z = g.X, g.Z end
  add("Garage " .. g.Id, { x - ph, x + ph, z - ph, z + ph })
end
for _, k in ipairs({ "NPC", "Event" }) do
  for _, a in ipairs(WCfg.Spawns[k] or {}) do if a.X then addC(k .. " " .. a.Id, a.X, a.Z, 14) end end
end
addC("EmpireBank", Bank.Position.X, Bank.Position.Z, (Bank.GuardRingRadius or 18) + 12)

local L = WS.Land
local function onLand(b) return b[1] >= L.X0 - 100 and b[2] <= L.X1 + 100 and b[3] >= L.Z0 - 100 and b[4] <= L.Z1 + 100 end
local function blocker(wb)
  if not onLand(wb) then return "off the land" end
  for _, o in ipairs(OBST) do
    if (o.B and ov(wb, o.B)) or (o.C and ovCircle(wb, o.C[1], o.C[2], o.C[3])) then return o.N end
  end
  return nil
end
local function freeFor(plotId)
  return function(zoneId, slot)
    local a = ZC.Annex[zoneId]
    return blocker(worldBox(plotId, ZC.SlotBox(slot, a.W, a.D, 2))) == nil
  end
end

local zones = ZC.SlotOrder
check(#zones == 7, "7 zones claim slots (Nuclear Silo first): " .. table.concat(zones, ","))
check(BC.MaxPlots == 10 and #BC.PlotPositions == BC.MaxPlots, "every plot index 1.." .. BC.MaxPlots .. " is covered (BaseConfig.MaxPlots = #PlotPositions)")

-- replay the OLD JOB 69 list (its first 24 AnnexAlt rows) = the live v218 result
local newAlt = ZC.AnnexAlt
local oldAlt = {}
for i = 1, math.min(24, #newAlt) do oldAlt[i] = newAlt[i] end
ZC.AnnexAlt = oldAlt
local oldGaps = {}
for pid = 1, BC.MaxPlots do
  local res = ZC.ResolveSlots(freeFor(pid), true)
  for _, z in ipairs(zones) do if not res[z] then table.insert(oldGaps, "P" .. pid .. "/" .. z) end end
end
ZC.AnnexAlt = newAlt
print("v218 (24 fallbacks) vs the full world: " .. #oldGaps .. " gaps: " .. table.concat(oldGaps, ", "))
check(#oldGaps > 0, "the v218 fallback list reproduces the live gaps (root cause): " .. #oldGaps)

local allBoxes = {}
for pid = 1, BC.MaxPlots do
  local res = ZC.ResolveSlots(freeFor(pid), true)
  local placed, row, boxes, far = 0, {}, {}, {}
  for _, z in ipairs(zones) do
    local s = res[z]
    if s then
      placed += 1
      local a = ZC.Annex[z]
      local lb = ZC.SlotBox(s, a.W, a.D, 0)
      table.insert(boxes, lb)
      table.insert(allBoxes, { P = pid, Z = z, B = worldBox(pid, lb) })
      table.insert(row, string.format("%s(%d,%d,%d)", string.sub(z, 1, 5), s.X, s.Z, s.Yaw))
      if math.sqrt(s.X * s.X + s.Z * s.Z) > MAX_SLOT_STUDS then table.insert(far, z) end
    else
      table.insert(row, string.sub(z, 1, 5) .. "(BOARD)")
    end
  end
  local clash = false
  for i = 1, #boxes do for j = i + 1, #boxes do if ov(boxes[i], boxes[j]) then clash = true end end end
  if os.getenv and false then end
  print("P" .. pid .. ": " .. table.concat(row, " "))
  check(placed == 7, string.format("plot %d: %d of 7 zones get an annex slot", pid, placed))
  check(res.StrategicYard ~= false and res.StrategicYard ~= nil, string.format("plot %d: the Nuclear Silo is placed", pid))
  check(not clash, string.format("plot %d: no two zones overlap", pid))
  check(#far == 0, string.format("plot %d: every zone within %d studs of the plot centre (%s)", pid, MAX_SLOT_STUDS, table.concat(far, ",")))
end
local cross = {}
for i = 1, #allBoxes do for j = i + 1, #allBoxes do
  local a, b = allBoxes[i], allBoxes[j]
  if a.P ~= b.P and ov(a.B, b.B) then table.insert(cross, "P" .. a.P .. "/" .. a.Z .. " x P" .. b.P .. "/" .. b.Z) end
end end
check(#cross == 0, "no zone overlaps another plot's zone: " .. (if #cross == 0 then "none" else table.concat(cross, ", ")))
print(string.format("ZONE SLOTS ALLPLOTS LUA: %d failed", fails))
if fails > 0 then error("failed") end
'''


def main():
    chunks = [PRELUDE]
    for key, path in MODS.items():
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
    chunks.append(TEST)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True, timeout=120)
    out = r.stdout.strip().splitlines()
    fails = 0
    if r.returncode != 0 or "ZONE SLOTS ALLPLOTS LUA: 0 failed" not in r.stdout:
        fails = 1
        out.append(r.stderr.strip()[-2500:])
    out.append("ZONE SLOTS ALLPLOTS TEST: %d failed" % fails)
    print("\n".join(out) if os.environ.get("VERBOSE") else "\n".join(l for l in out if l.startswith(("FAIL", "ZONE SLOTS"))))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
