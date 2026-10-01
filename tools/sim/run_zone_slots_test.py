"""claude-bud JOB 69 part A: every rebirth zone gets a slot on every plot, on the REAL RebirthZonesConfig.ResolveSlots
(+ PlotFrame, BaseConfig, WorldSitesConfig, TerritoryConfig, WaterConfig) with the world geometry from config:
  * the land edge (RebirthZoneService.OnLand: the WorldSitesConfig.Land box +-100, every corner);
  * the 6 world roads (RoadX / RoadZ at -800 / 0 / 800, 14 wide, over WaterConfig.RoadEnds) + the road corridor margin;
  * every plot pad (its own and the others, 320 x 320) and every plot's dock channel (plot-local X 108..148 out of the rear);
  * the public water rects (WaterConfig.Public), the world sites (WorldSitesConfig.Sites, R) and the outposts
    (TerritoryConfig, Radius).
Asserts: 10 plots x 7 zones = 70 pairs, 0 blocked (the Nuclear Silo on every plot); no two zones of a plot overlap;
OFF (alternates not allowed) reproduces today's gaps (the root cause).
Run: LUAU=path/to/luau(.exe) python tools/sim/run_zone_slots_test.py   (exit 1 on any failure; VERBOSE=1 prints the table)"""
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
local HALF = BC.PlotSize.X / 2
local ROAD_HALF = 7 + 5 -- the 14-wide strip + the shoulder (WaterConfig.RoadCull Corridor 12 from the centre line)

-- a plot-local box -> its world AABB (the plot yaw is a multiple of 90)
local function worldBox(plotId, b)
  local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
  for _, c in ipairs({ { b[1], b[3] }, { b[1], b[4] }, { b[2], b[3] }, { b[2], b[4] } }) do
    local w = PF.LocalToWorld(plotId, c[1], c[2])
    x0, x1, z0, z1 = math.min(x0, w.X), math.max(x1, w.X), math.min(z0, w.Z), math.max(z1, w.Z)
  end
  return { x0, x1, z0, z1 }
end
local function ov(a, b) return a[1] < b[2] and b[1] < a[2] and a[3] < b[4] and b[3] < a[4] end

-- the obstacles (world AABBs)
local OBST = {}
local function add(name, b) table.insert(OBST, { N = name, B = b }) end
for _, x in ipairs({ -800, 0, 800 }) do
  local e = WC.RoadEnds["RoadX" .. x]
  add("RoadX" .. x, { x - ROAD_HALF, x + ROAD_HALF, e.Min, e.Max })
end
for _, z in ipairs({ -800, 0, 800 }) do
  local e = WC.RoadEnds["RoadZ" .. z]
  add("RoadZ" .. z, { e.Min, e.Max, z - ROAD_HALF, z + ROAD_HALF })
end
for pid = 1, BC.MaxPlots do
  add("Plot" .. pid, worldBox(pid, { -HALF, HALF, -HALF, HALF }))
  add("Channel" .. pid, worldBox(pid, { 108, 148, -2400, -HALF })) -- the dock channel out of the rear (clipped by the land rule)
end
for _, r in ipairs(WC.Public) do add("Water " .. r.Name, { r.X0, r.X1, r.Z0, r.Z1 }) end
for _, st in ipairs(WS.Sites) do local R = (st.R or 46) + 6; add("Site " .. st.Id, { st.X - R, st.X + R, st.Z - R, st.Z + R }) end
for id, t in pairs(TC.Territories or {}) do
  if typeof(t.Position) == "Vector3" and t.Radius then local R = t.Radius + 6; add("Outpost " .. id, { t.Position.X - R, t.Position.X + R, t.Position.Z - R, t.Position.Z + R }) end
end
local L = WS.Land
local function onLand(b) return b[1] >= L.X0 - 100 and b[2] <= L.X1 + 100 and b[3] >= L.Z0 - 100 and b[4] <= L.Z1 + 100 end

local function freeFor(plotId)
  return function(zoneId, slot)
    local a = ZC.Annex[zoneId]
    local wb = worldBox(plotId, ZC.SlotBox(slot, a.W, a.D, 2))
    if not onLand(wb) then return false end
    for _, o in ipairs(OBST) do if ov(wb, o.B) then return false end end
    return true
  end
end

local zones = ZC.SlotOrder
check(#zones == 7, "7 zones claim slots (Nuclear Silo first): " .. table.concat(zones, ","))
local blocked, oldBlocked, pairsN = {}, {}, 0
local lines = {}
for pid = 1, BC.MaxPlots do
  local res = ZC.ResolveSlots(freeFor(pid), true)
  local old = ZC.ResolveSlots(freeFor(pid), false)
  local row = {}
  local boxes = {}
  for _, z in ipairs(zones) do
    pairsN += 1
    local s = res[z]
    if not s then table.insert(blocked, "P" .. pid .. "/" .. z) else
      table.insert(row, string.format("%s(%d,%d)", string.sub(z, 1, 5), s.X, s.Z))
      table.insert(boxes, ZC.SlotBox(s, ZC.Annex[z].W, ZC.Annex[z].D, 0))
    end
    if not old[z] then table.insert(oldBlocked, "P" .. pid .. "/" .. z) end
  end
  local clash = false
  for i = 1, #boxes do for j = i + 1, #boxes do if ov(boxes[i], boxes[j]) then clash = true end end end
  if clash then table.insert(blocked, "P" .. pid .. " overlap") end
  table.insert(lines, "P" .. pid .. ": " .. table.concat(row, " "))
end
print(table.concat(lines, "\n"))
check(pairsN == 70 and #blocked == 0, string.format("all %d plot x zone pairs get a slot, no overlaps (blocked: %s)", pairsN, if #blocked == 0 then "none" else table.concat(blocked, ", ")))
check(#oldBlocked > 0, string.format("OFF (own slot only) reproduces today's gaps: %d blocked (%s)", #oldBlocked, table.concat(oldBlocked, ", ")))
print(string.format("ZONE SLOTS LUA: %d failed", fails))
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
    if r.returncode != 0 or "ZONE SLOTS LUA: 0 failed" not in r.stdout:
        fails = 1
        out.append(r.stderr.strip()[-2500:])
    out.append("ZONE SLOTS TEST: %d failed" % fails)
    print("\n".join(out) if os.environ.get("VERBOSE") else "\n".join(l for l in out if l.startswith(("FAIL", "ZONE SLOTS TEST"))))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
