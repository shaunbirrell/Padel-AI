"""Code Bot MAP-REDESIGN (v129): runs the REAL Shared/Util/MapLabelLayout on the REAL map inputs in the Luau CLI:
MapAreas.List() (WorldConfig POIs + TerritoryConfig outposts), the JOB 31 WorldSitesConfig sites (their configured
points and kind radii), the 10 BaseConfig plots (plot 1 = yours) and the BankRaidConfig bank, with MapConfig.
Scenarios: phone (470 v map, 20 v text), small phone (420 v), desktop (640 v, 16 v text); zoom 1 and zoom 2 panned
to the centre and each quadrant. Asserts (per scenario):
  * no two label pills overlap; no pill covers an icon or a map control (close X, zoom, compass);
  * every pill lies inside the visible map window;
  * labels are title case, never ALL CAPS;
  * zoom 1 shows the key places (Crossroads Town, both forts, your base, >= 14 labels on the phone); zoom 2 shows
    every label in some view (the 420 v small phone may leave 1 tap-only).
With --json PATH it writes the phone layouts (zoom 1 + zoom 2 centre) for tools/sim/render_map_mock.py.
Run: LUAU=path/to/luau python3 tools/sim/run_map_layout_test.py [--json out.json]   (exit 1 on any failure)"""
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SH = ROOT / "src/ReplicatedStorage/Shared"
MODS = {
    "Configs/WorldConfig": SH / "Configs/WorldConfig.luau",
    "Configs/TerritoryConfig": SH / "Configs/TerritoryConfig.luau",
    "Configs/OutpostDefenderConfig": SH / "Configs/OutpostDefenderConfig.luau",
    "Configs/BaseConfig": SH / "Configs/BaseConfig.luau",
    "Configs/BaseLayoutConfig": SH / "Configs/BaseLayoutConfig.luau",
    "Configs/WorldSitesConfig": SH / "Configs/WorldSitesConfig.luau",
    "Configs/MapConfig": SH / "Configs/MapConfig.luau",
    "Configs/BankRaidConfig": SH / "Configs/BankRaidConfig.luau",
    "Util/PlotFrame": SH / "Util/PlotFrame.luau",
    "Util/MapAreas": SH / "Util/MapAreas.luau",
    "Util/MapLabelLayout": SH / "Util/MapLabelLayout.luau",
}
_src = (ROOT / "tools/sim/run_map_test.py").read_text(encoding="utf-8")
PRELUDE = re.search(r"PRELUDE = r'''(.*?)'''", _src, re.S).group(1)

TEST = r'''
local MapAreas = require(node("Util/MapAreas"))
local L = require(node("Util/MapLabelLayout"))
local MapConfig = require(node("Configs/MapConfig"))
local WSC = require(node("Configs/WorldSitesConfig"))
local BaseConfig = require(node("Configs/BaseConfig"))
local Bank = require(node("Configs/BankRaidConfig"))
local fails, checks = 0, 0
local function check(ok, msg) checks += 1; if not ok then fails += 1; print("FAIL  " .. msg) end end
local sites = {}
for _, s in ipairs(WSC.Sites) do table.insert(sites, { Id = s.Id, N = s.Name, K = s.Kind, X = s.X, Z = s.Z, R = WSC.Kinds[s.Kind].R }) end
local bases = {}
for p, v in ipairs(BaseConfig.PlotPositions) do table.insert(bases, { P = p, X = v.X, Z = v.Z, Mine = p == 1 }) end
local bank = { X = Bank.Position.X, Z = Bank.Position.Z }
local TAP = { phone = 64, small = 64, desktop = 44 }
local function enc(v)
  local t = type(v)
  if t == "number" then return string.format("%.2f", v) elseif t == "string" then return string.format("%q", v)
  elseif t == "boolean" then return tostring(v) elseif v == nil then return "null" end
  if #v > 0 or next(v) == nil then local o = {} for _, x in ipairs(v) do table.insert(o, enc(x)) end return "[" .. table.concat(o, ",") .. "]" end
  local o = {} for k, x in pairs(v) do table.insert(o, string.format("%q", tostring(k)) .. ":" .. enc(x)) end return "{" .. table.concat(o, ",") .. "}"
end
local allIds, seenZoom2 = {}, {}
local function run(name, side, textV, zoom, fx, fy, dump)
  local size = side * zoom
  local ox, oy = -fx * (size - side), -fy * (size - side)
  local view = { X0 = -ox, Y0 = -oy, X1 = -ox + side, Y1 = -oy + side }
  local controls = L.ControlRects(side, TAP[name], MapConfig.CompassV, ox, oy)
  local out = L.Build({ Areas = MapAreas.List(), Sites = sites, Bases = bases, Bank = bank, Config = MapConfig, Size = size,
    View = view, TextV = textV, Measure = function(t) return L.EstimateWidth(t, textV) end, Controls = controls,
    MaxPriority = MapConfig.ZoomMaxPriority[zoom] })
  local tag = string.format("%s %dv zoom%d (%.1f,%.1f)", name, side, zoom, fx, fy)
  local labs = out.Labels
  for i = 1, #labs do
    local a = labs[i]
    check(a.X0 >= view.X0 and a.Y0 >= view.Y0 and a.X1 <= view.X1 and a.Y1 <= view.Y1, tag .. ": " .. a.Text .. " inside the map window")
    check(a.Text ~= string.upper(a.Text), tag .. ": " .. a.Text .. " is title case")
    for j = i + 1, #labs do check(not L.Overlaps(a, labs[j], 0), tag .. ": " .. a.Text .. " vs " .. labs[j].Text .. " no overlap") end
    for _, ic in ipairs(out.Icons) do
      local r = { X0 = ic.X - ic.S / 2, Y0 = ic.Y - ic.S / 2, X1 = ic.X + ic.S / 2, Y1 = ic.Y + ic.S / 2 }
      check(not L.Overlaps(a, r, 0), tag .. ": " .. a.Text .. " clear of icon " .. ic.Id)
    end
    for k, c in ipairs(controls) do check(not L.Overlaps(a, c, 0), tag .. ": " .. a.Text .. " clear of control " .. k) end
    if zoom == 2 then seenZoom2[name .. a.Id] = true end
  end
  for id in pairs(out.Items) do allIds[id] = true end
  print(string.format("LAYOUT %s: %d labels shown, %d hidden", tag, #labs, #out.Hidden))
  if dump then
    local areas = {}
    local E = MapConfig.Extent
    local function P(x, z) return (x - E.X0) / (E.X1 - E.X0) * size, (z - E.Z0) / (E.Z1 - E.Z0) * size end
    for _, a in ipairs(MapAreas.List()) do
      local cx, cy = P(a.X, a.Z)
      local row = { Id = a.Id, Kind = a.Kind, X = cx, Y = cy, R = a.R / (E.X1 - E.X0) * size, Territory = a.Territory or "" }
      if a.Rect then local x0, y0 = P(a.Rect.X0, a.Rect.Z0); local x1, y1 = P(a.Rect.X1, a.Rect.Z1); row.Rect = { x0, y0, x1, y1 } end
      table.insert(areas, row)
    end
    print("JSON " .. enc({ Areas = areas, Name = name, Side = side, Zoom = zoom, Size = size, Ox = ox, Oy = oy, TextV = textV, Labels = labs, Icons = out.Icons, Hidden = out.Hidden, Tap = TAP[name] }))
  end
  return out
end
-- { name, map side v, text v, zoom-1 minimum labels, zoom-2 labels allowed to stay tap-only }
for _, sc in ipairs({ { "phone", 470, 20, 14, 0 }, { "small", 420, 20, 10, 1 }, { "desktop", 640, 16, 20, 0 } }) do
  local o1 = run(sc[1], sc[2], sc[3], 1, 0, 0, sc[1] == "phone")
  local shown = {}
  for _, l in ipairs(o1.Labels) do shown[l.Id] = true end
  check(#o1.Labels >= sc[4], sc[1] .. " zoom 1 shows >= " .. sc[4] .. " labels (" .. #o1.Labels .. ")")
  for _, must in ipairs({ "A:Town", "A:FortI", "A:FortS", "B:1" }) do check(shown[must] == true, sc[1] .. " zoom 1 shows " .. must) end
  local best2 = 0
  for _, f in ipairs({ { 0.5, 0.5 }, { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 }, { 0.5, 0 }, { 0.5, 1 }, { 0, 0.5 }, { 1, 0.5 } }) do
    local o2 = run(sc[1], sc[2], sc[3], 2, f[1], f[2], sc[1] == "phone" and f[1] == 0.5 and f[2] == 0.5)
    best2 = math.max(best2, #o2.Labels)
  end
  local missed = {}
  for id in pairs(allIds) do if seenZoom2[sc[1] .. id] ~= true then table.insert(missed, id) end end
  check(#missed <= sc[5], sc[1] .. ": every label shows in some zoom-2 view (tap-only: " .. table.concat(missed, ",") .. ")")
  print(string.format("COVER %s: %d labels, zoom-2 tap-only: %s", sc[1], (function() local n = 0 for _ in pairs(allIds) do n += 1 end return n end)(), table.concat(missed, ",")))
end
check(L.TitleCase("FORT IRONCLAD approach") == "Fort Ironclad Approach", "TitleCase")
print(string.format("MAP LAYOUT TEST: %d checks, %d failed", checks, fails))
if fails > 0 then error("failed") end
'''

chunks = [PRELUDE]
for key, path in MODS.items():
    chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
chunks.append(TEST)
with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
    f.write("\n".join(chunks))
    path = f.name
luau = os.environ.get("LUAU", "luau")
r = subprocess.run([luau, path], capture_output=True, text=True)
lines = r.stdout.splitlines()
print("\n".join(l for l in lines if l.startswith(("FAIL", "LAYOUT", "COVER", "MAP LAYOUT"))))
if "--json" in sys.argv:
    dumps = [json.loads(l[5:]) for l in lines if l.startswith("JSON ")]
    Path(sys.argv[sys.argv.index("--json") + 1]).write_text(json.dumps(dumps, indent=1), encoding="utf-8")
if r.returncode != 0:
    print(r.stderr.strip()[-1500:])
    sys.exit(1)
