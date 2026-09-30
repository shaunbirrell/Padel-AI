"""claude-bud JOB 30: runs the REAL Shared/Util/MapAreas (and the real WorldConfig / TerritoryConfig /
OutpostDefenderConfig / BaseConfig / BaseLayoutConfig / PlotFrame it requires) in the Luau CLI, with small stand-ins
for the Roblox globals it touches (Vector3, Color3, Enum, game, typeof, script.Parent requires).
Checks: every enabled POI is an area; every non-starter outpost is joined to exactly one area (or its own); the
Central Plaza is in Crossroads Town; the offshore rigs get their own area; garrison tiers are joined; MapAreas.At picks
the smallest containing area and nil on open ground.
Run: LUAU=path/to/luau(.exe) python tools/sim/run_map_test.py   (exit 1 on any failure)"""
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
    "Util/PlotFrame": SH / "Util/PlotFrame.luau",
    "Util/MapAreas": SH / "Util/MapAreas.luau",
}
# modules a config may require that the test does not need: a permissive stub
STUB_OK = True

PRELUDE = r'''
local V = {}
V.__index = V
local function vec(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V) end
V.__add = function(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V.__sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V.__mul = function(a, b) if type(a) == "number" then return vec(a * b.X, a * b.Y, a * b.Z) elseif type(b) == "number" then return vec(a.X * b, a.Y * b, a.Z * b) end return vec(a.X * b.X, a.Y * b.Y, a.Z * b.Z) end
V.__unm = function(a) return vec(-a.X, -a.Y, -a.Z) end
V.__index = function(t, k)
  if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
  if k == "Unit" then local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z); return vec(t.X / m, t.Y / m, t.Z / m) end
  return rawget(V, k)
end
Vector3 = { new = vec, zero = vec(0, 0, 0), one = vec(1, 1, 1), xAxis = vec(1,0,0), yAxis = vec(0,1,0), zAxis = vec(0,0,1) }
local any
any = setmetatable({}, { __index = function() return any end, __call = function() return any end })
Color3 = { new = function() return any end, fromRGB = function() return any end, fromHSV = function() return any end }
Enum = any
UDim2 = any
UDim = any
NumberRange = any
ColorSequence = any
NumberSequence = any
Vector2 = { new = function(x, y) return { X = x, Y = y } end }
-- a yaw-only CFrame (position + rotation about Y): enough for PlotFrame's CFrame.new(pos) * yaw and PointToWorldSpace
local CF = {}
CF.__index = CF
local function cf(px, py, pz, c, s) return setmetatable({ P = vec(px, py, pz), c = c or 1, s = s or 0 }, CF) end
CF.__mul = function(a, b)
  if getmetatable(b) == CF then
    local w = a:PointToWorldSpace(b.P)
    return cf(w.X, w.Y, w.Z, a.c * b.c - a.s * b.s, a.s * b.c + a.c * b.s)
  end
  return a:PointToWorldSpace(b)
end
function CF:PointToWorldSpace(v) return vec(self.P.X + self.c * v.X + self.s * v.Z, self.P.Y + v.Y, self.P.Z - self.s * v.X + self.c * v.Z) end
CFrame = {
  new = function(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
    if type(x) == "table" then return cf(x.X, x.Y, x.Z) end
    if r00 ~= nil then return cf(x, y, z, r00, r02) end
    return cf(x or 0, y or 0, z or 0)
  end,
  Angles = function(_, yaw, _) return cf(0, 0, 0, math.cos(yaw), math.sin(yaw)) end,
}
game = { GetService = function() return any end }
workspace = any
local rawtypeof = typeof
typeof = function(v) if getmetatable(v) == V then return "Vector3" end return rawtypeof(v) end
local SOURCES = {}
local CACHE = {}
local function node(path) return setmetatable({ __path = path }, { __index = function(t, k)
  local p = rawget(t, "__path")
  if k == "Parent" then local q = p:match("^(.*)/[^/]+$") or ""; return node(q) end
  return node(p == "" and k or (p .. "/" .. k))
end }) end
local realRequire = require
require = function(n)
  if type(n) == "table" and rawget(n, "__path") then
    local p = rawget(n, "__path")
    if CACHE[p] == nil then
      local f = SOURCES[p]
      if f == nil then CACHE[p] = any else CACHE[p] = f(node(p)) end
    end
    return CACHE[p]
  end
  return realRequire(n)
end
'''


def strip_types(src: str) -> str:
    # the CLI runs typed Luau as-is; only `--!strict` and `export type` blocks need no change
    return src


chunks = [PRELUDE]
for key, path in MODS.items():
    src = strip_types(path.read_text(encoding="utf-8"))
    chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, src))

TEST = r'''
local MapAreas = require(node("Util/MapAreas"))
local WorldConfig = require(node("Configs/WorldConfig"))
local TerritoryConfig = require(node("Configs/TerritoryConfig"))
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local list = MapAreas.List()
local byId = {}
for _, a in ipairs(list) do byId[a.Id] = a end
local pois = 0
for _, p in ipairs(WorldConfig.POIs) do if p.Enabled ~= false then pois += 1; check(byId[p.Id] ~= nil, "POI area " .. p.Id) end end
local joined, outposts = {}, 0
for id, d in pairs(TerritoryConfig.Territories) do
  if d.IsStarter ~= true then
    outposts += 1
    local n = 0
    for _, a in ipairs(list) do if a.Territory == id then n += 1 end end
    check(n == 1, "outpost " .. id .. " joined to exactly one area (" .. n .. ")")
  end
end
check(outposts >= 11, "all real outposts seen (" .. outposts .. ")")
check(byId.Town ~= nil and byId.Town.Territory == "CentralPlaza", "Central Plaza is in Crossroads Town")
check(byId.CoastalOilAlpha ~= nil and byId.CoastalOilAlpha.Kind == "rig", "offshore rig Alpha is its own area")
check(byId.Ruins ~= nil and byId.Ruins.Tier == "Medium" and byId.Oasis.Tier == "Hard", "garrison tiers joined")
local at = MapAreas.At(0, 0)
check(at ~= nil and at.Id == "Town", "At(0,0) = Town")
local q = MapAreas.At(-1380, -1380)
check(q ~= nil and q.Id == "Quarry", "At(Quarry centre) = Quarry")
check(MapAreas.At(600, 300) == nil, "At(open desert) = nil (a tap there pins)")
for _, a in ipairs(list) do check(a.R > 0 and a.X == a.X and a.Z == a.Z, "area " .. a.Id .. " geometry finite") end
print(string.format("MAP TEST: %d areas, %d failed", #list, fails))
if fails > 0 then error("failed") end
'''
chunks.append(TEST)
with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
    f.write("\n".join(chunks))
    path = f.name
luau = os.environ.get("LUAU", "luau")
r = subprocess.run([luau, path], capture_output=True, text=True)
out = r.stdout.strip()
print("\n".join(l for l in out.splitlines() if l.startswith("FAIL") or l.startswith("MAP TEST")) or out)
if r.returncode != 0:
    print(r.stderr.strip()[-1500:])
    sys.exit(1)
