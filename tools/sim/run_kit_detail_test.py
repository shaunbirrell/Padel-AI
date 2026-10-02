"""claude-bud JOB 31: runs the REAL WorldKits module (Modules/WorldKits.luau: plain and detailed builders, Add, Footprint,
the detail allowance) in the Luau CLI, with stand-ins for the Roblox pieces it touches: Instance.new (a property
table), a full CFrame (3x3 rotation + position), Vector3, services. WorldTerrain / WorldLabel / Lighting are inert.
Checks, for every kit WorldDetailConfig details:
  * the detailed build makes exactly WorldKits.DetailSpecs parts, and Add still returns the PLAIN count;
  * road-side kits (Wreck, SandbagLine / Arc / Nest, Jersey) keep every collidable part at local z >= -0.05;
  * nothing sinks below the floor (lowest point >= -0.05 in the kit frame);
  * the detailed footprint stays within 2.5 studs of the plain one on X and Z;
  * with the allowance spent (MaxExtraParts 0) Add builds the plain kit; with Enabled = false too.
Run: LUAU=path/to/luau(.exe) python tools/sim/run_kit_detail_test.py   (exit 1 on any failure)"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SH = ROOT / "src/ReplicatedStorage/Shared"
MODS = {
    "Configs/WorldConfig": SH / "Configs/WorldConfig.luau",
    "Configs/WorldDetailConfig": SH / "Configs/WorldDetailConfig.luau",
    "Modules/WorldKits": ROOT / "src/ServerScriptService/Server/Modules/WorldKits.luau",
}

PRELUDE = r'''
local V = {}
local function vec(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0, __v = true }, V) end
V.__add = function(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V.__sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V.__mul = function(a, b) if type(a) == "number" then return vec(a * b.X, a * b.Y, a * b.Z) elseif type(b) == "number" then return vec(a.X * b, a.Y * b, a.Z * b) end return vec(a.X * b.X, a.Y * b.Y, a.Z * b.Z) end
V.__div = function(a, b) return vec(a.X / b, a.Y / b, a.Z / b) end
V.__unm = function(a) return vec(-a.X, -a.Y, -a.Z) end
V.__index = function(t, k)
  if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
  if k == "Unit" then local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z); return vec(t.X / m, t.Y / m, t.Z / m) end
  if k == "Dot" then return function(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end end
  if k == "Lerp" then return function(a, b, t2) return a + (b - a) * t2 end end
  return nil
end
Vector3 = { new = vec, zero = vec(0, 0, 0), one = vec(1, 1, 1), xAxis = vec(1, 0, 0), yAxis = vec(0, 1, 0), zAxis = vec(0, 0, 1) }

-- CFrame: rotation matrix rows r[1..3][1..3] and position p
local CF = {}
local function cfm(p, r) return setmetatable({ p = p, r = r, __cf = true }, CF) end
local I = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
local function mm(a, b)
  local o = { {}, {}, {} }
  for i = 1, 3 do for j = 1, 3 do o[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j] end end
  return o
end
local function mv(a, v) return vec(a[1][1] * v.X + a[1][2] * v.Y + a[1][3] * v.Z, a[2][1] * v.X + a[2][2] * v.Y + a[2][3] * v.Z, a[3][1] * v.X + a[3][2] * v.Y + a[3][3] * v.Z) end
local function tr(a) return { { a[1][1], a[2][1], a[3][1] }, { a[1][2], a[2][2], a[3][2] }, { a[1][3], a[2][3], a[3][3] } } end
CF.__mul = function(a, b)
  if rawget(b, "__cf") then return cfm(a.p + mv(a.r, b.p), mm(a.r, b.r)) end
  return a.p + mv(a.r, b)
end
CF.__add = function(a, v) return cfm(a.p + v, a.r) end
CF.__sub = function(a, v) return cfm(a.p - v, a.r) end
CF.__index = function(t, k)
  if k == "Position" then return t.p end
  if k == "X" then return t.p.X elseif k == "Y" then return t.p.Y elseif k == "Z" then return t.p.Z end
  if k == "RightVector" then return vec(t.r[1][1], t.r[2][1], t.r[3][1]) end
  if k == "UpVector" then return vec(t.r[1][2], t.r[2][2], t.r[3][2]) end
  if k == "LookVector" then return vec(-t.r[1][3], -t.r[2][3], -t.r[3][3]) end
  if k == "Rotation" then return cfm(vec(0, 0, 0), t.r) end
  if k == "Inverse" then return function(s) local ri = tr(s.r); return cfm(-mv(ri, s.p), ri) end end
  if k == "ToObjectSpace" then return function(s, o) local ri = tr(s.r); return cfm(mv(ri, o.p - s.p), mm(ri, o.r)) end end
  if k == "PointToWorldSpace" then return function(s, v) return s.p + mv(s.r, v) end end
  if k == "PointToObjectSpace" then return function(s, v) return mv(tr(s.r), v - s.p) end end
  if k == "VectorToWorldSpace" then return function(s, v) return mv(s.r, v) end end
  return nil
end
local function rx(a) local c, s = math.cos(a), math.sin(a); return { { 1, 0, 0 }, { 0, c, -s }, { 0, s, c } } end
local function ry(a) local c, s = math.cos(a), math.sin(a); return { { c, 0, s }, { 0, 1, 0 }, { -s, 0, c } } end
local function rz(a) local c, s = math.cos(a), math.sin(a); return { { c, -s, 0 }, { s, c, 0 }, { 0, 0, 1 } } end
CFrame = {
  new = function(x, y, z, a, b, c, d, e, f, g, h, i)
    if type(x) == "table" then return cfm(vec(x.X, x.Y, x.Z), I) end
    if a ~= nil then return cfm(vec(x, y, z), { { a, b, c }, { d, e, f }, { g, h, i } }) end
    return cfm(vec(x or 0, y or 0, z or 0), I)
  end,
  Angles = function(a, b, c) return cfm(vec(0, 0, 0), mm(mm(rx(a), ry(b)), rz(c))) end,
  identity = cfm(vec(0, 0, 0), I),
}
CFrame.fromEulerAnglesXYZ = CFrame.Angles

local any
any = setmetatable({}, { __index = function() return any end, __call = function() return any end, __eq = function() return true end })
Color3 = { new = function() return any end, fromRGB = function() return any end, fromHSV = function() return any end }
Enum = setmetatable({}, { __index = function(_, e) return setmetatable({}, { __index = function(_, n) return e .. "." .. n end }) end })
UDim2 = any; UDim = any; NumberRange = any; ColorSequence = any; NumberSequence = any
Vector2 = { new = function(x, y) return { X = x, Y = y } end }

-- Instance stand-in: a property bag
local INST = {}
INST.__index = function(t, k)
  local own = rawget(t, "__props")[k]
  if type(own) == "function" then return own end -- a test's per-object override
  if k == "SetAttribute" then return function(s, n, v) s.__attr[n] = v end end
  if k == "GetAttribute" then return function(s, n) return s.__attr[n] end end
  if k == "Destroy" then return function(s) rawset(s, "__destroyed", true); s.Parent = nil end end
  if k == "IsA" then return function(s, c) return s.ClassName == c or (c == "BasePart" and (s.ClassName == "Part" or s.ClassName == "TrussPart")) or (c == "Instance") end end
  if k == "GetChildren" then return function(s) return table.clone(rawget(s, "__kids") or {}) end end
  if k == "GetDescendants" then return function(s)
    local out = {}
    local function walk(o) for _, c in ipairs(rawget(o, "__kids") or {}) do table.insert(out, c); walk(c) end end
    walk(s)
    return out
  end end
  if k == "FindFirstChild" or k == "FindFirstChildOfClass" then return function() return nil end end
  local props = rawget(t, "__props")
  if k == "Position" and props.Position == nil and props.CFrame ~= nil then return props.CFrame.Position end
  return props[k]
end
INST.__newindex = function(t, k, v)
  local props = rawget(t, "__props")
  if k == "Parent" then
    local old = props.Parent
    if type(old) == "table" and rawget(old, "__kids") then
      local kids = rawget(old, "__kids")
      for i = #kids, 1, -1 do if kids[i] == t then table.remove(kids, i) end end
    end
    if type(v) == "table" and rawget(v, "__props") then
      local kids = rawget(v, "__kids")
      if kids == nil then kids = {}; rawset(v, "__kids", kids) end
      table.insert(kids, t)
    end
  end
  props[k] = v
end
Instance = { new = function(cls) return setmetatable({ ClassName = cls, __attr = {}, __props = {} }, INST) end }

local rawtypeof = typeof
typeof = function(v)
  if type(v) == "table" then
    if rawget(v, "__v") then return "Vector3" end
    if rawget(v, "__cf") then return "CFrame" end
    if getmetatable(v) == INST then return "Instance" end
  end
  return rawtypeof(v)
end

local SOURCES, CACHE = {}, {}
local function node(path) return setmetatable({ __path = path }, { __index = function(t, k)
  local p = rawget(t, "__path")
  if k == "Parent" then local q = p:match("^(.*)/[^/]+$") or ""; return node(q) end
  if k == "WaitForChild" or k == "FindFirstChild" then return function(s, n) return node(p == "" and n or (p .. "/" .. n)) end end
  return node(p == "" and k or (p .. "/" .. k))
end }) end
local shared = setmetatable({}, { __index = function(_, k)
  if k == "WaitForChild" or k == "FindFirstChild" then return function(_, n) return node(n) end end
  return node(k) end })
local RS = setmetatable({}, { __index = function(_, k)
  if k == "Shared" then return shared end
  if k == "WaitForChild" or k == "FindFirstChild" then return function(_, n) if n == "Shared" then return shared end return any end end
  return any end })
game = { GetService = function(_, n) if n == "ReplicatedStorage" then return RS end return any end }
workspace = any
local realRequire = require
require = function(n)
  if type(n) == "table" and rawget(n, "__path") then
    local p = rawget(n, "__path")
    if CACHE[p] == nil then
      local f = SOURCES[p]
      CACHE[p] = if f == nil then any else f(node(p))
    end
    return CACHE[p]
  end
  return realRequire(n)
end
warn = function() end
'''

TEST = r'''
local WK = require(node("Modules/WorldKits"))
local DC = require(node("Configs/WorldDetailConfig"))
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local ROAD = { Wreck = true, SandbagLine = true, SandbagArc = true, SandbagNest = true, Jersey = true }
local cases = {
  { "Wreck", { Variant = "tank" }, WK.DetailSpecs.Wreck.tank },
  { "Wreck", { Variant = "truck" }, WK.DetailSpecs.Wreck.truck },
  { "Wreck", { Variant = "gun" }, WK.DetailSpecs.Wreck.gun },
  { "SandbagLine", { Length = 15 }, WK.DetailSpecs.SandbagLine * 3 },
  { "SandbagArc", {}, WK.DetailSpecs.SandbagArc },
  { "SandbagNest", {}, WK.DetailSpecs.SandbagNest },
  { "Jersey", {}, WK.DetailSpecs.Jersey },
  { "Watchtower", {}, WK.DetailSpecs.Watchtower },
  { "Bunker", {}, WK.DetailSpecs.Bunker },
  { "Tent", {}, WK.DetailSpecs.Tent },
}
local frame = CFrame.new(0, 0.5, 0)
local function build(kit, opts)
  local cluster = Instance.new("Model")
  local made = {}
  local realPart = WK.Part
  local n = WK.Add(cluster, kit, frame, opts)
  return n
end
-- measure the detailed parts: wrap WorldKits.Part to record what it makes
local record = nil
local realPart = WK.Part
WK.Part = function(ps, parent) local p = realPart(ps, parent); if record then table.insert(record, p) end; return p end
for _, c in ipairs(cases) do
  local kit, opts, want = c[1], c[2], c[3]
  local plain = WK.Footprint(kit, opts)
  record = {}
  local ret = WK.Add(Instance.new("Model"), kit, frame, opts)
  local parts = {}
  for _, p in ipairs(record) do if not rawget(p, "__destroyed") then table.insert(parts, p) end end
  record = nil
  if kit == "Watchtower" then want -= 1 end -- the ladder is a TrussPart (truss(), not WorldKits.Part)
  local label = kit .. (opts.Variant and ("/" .. opts.Variant) or "")
  check(#parts == want, label .. " detailed parts " .. #parts .. " = DetailSpecs " .. want)
  check(plain ~= nil and ret == plain.Parts, label .. " Add returns the plain count " .. tostring(ret) .. " (plain " .. tostring(plain and plain.Parts) .. ")")
  local x0, x1, z0, z1, y0, cz0 = math.huge, -math.huge, math.huge, -math.huge, math.huge, math.huge
  for _, p in ipairs(parts) do
    local rel = frame:ToObjectSpace(p.CFrame)
    local s = p.Size
    local r, u, l = rel.RightVector * s.X * 0.5, rel.UpVector * s.Y * 0.5, rel.LookVector * s.Z * 0.5
    local hx = math.abs(r.X) + math.abs(u.X) + math.abs(l.X)
    local hy = math.abs(r.Y) + math.abs(u.Y) + math.abs(l.Y)
    local hz = math.abs(r.Z) + math.abs(u.Z) + math.abs(l.Z)
    local cp = rel.Position
    x0, x1, z0, z1 = math.min(x0, cp.X - hx), math.max(x1, cp.X + hx), math.min(z0, cp.Z - hz), math.max(z1, cp.Z + hz)
    y0 = math.min(y0, cp.Y - hy)
    if p.CanCollide then cz0 = math.min(cz0, cp.Z - hz) end
  end
  if ROAD[kit] then check(cz0 >= -0.005, label .. " collidables at z >= 0 (min " .. string.format("%.2f", cz0) .. ")") end
  check(y0 >= -0.005, label .. " nothing below the floor (min y " .. string.format("%.2f", y0) .. ")")
  if plain then
    local slack = 2.5
    check(x0 >= plain.X0 - slack and x1 <= plain.X1 + slack and z0 >= plain.Z0 - slack and z1 <= plain.Z1 + slack,
      label .. string.format(" footprint x %.1f..%.1f z %.1f..%.1f within plain x %.1f..%.1f z %.1f..%.1f +-%.1f", x0, x1, z0, z1, plain.X0, plain.X1, plain.Z0, plain.Z1, slack))
  end
end
-- claude-bud JOB 37: the real road checkpoint (its own share: WorldDetailConfig.KitCaps.Checkpoint)
do
  local realSign = WK.Sign
  WK.Sign = function() return nil end -- the world sign budget needs the live workspace
  local plain = WK.Footprint("Checkpoint", {}) -- first (it builds the plain kit once to measure it)
  record = {}
  local cluster = Instance.new("Model")
  local ret = WK.Add(cluster, "Checkpoint", frame, {})
  local parts = {}
  for _, p in ipairs(record) do if not rawget(p, "__destroyed") then table.insert(parts, p) end end
  record = nil
  check(#parts == WK.DetailSpecs.Checkpoint - 1, "Checkpoint detailed parts " .. #parts .. " (+ the tower's TrussPart ladder) = DetailSpecs " .. WK.DetailSpecs.Checkpoint)
  check(WK.DetailSpecs.Checkpoint <= 110, "Checkpoint <= 110 parts (" .. WK.DetailSpecs.Checkpoint .. ")")
  check(plain ~= nil and ret == plain.Parts, "Checkpoint Add returns the plain count " .. tostring(ret))
  local x0, x1, z0, z1, laneBad, armCollide, booth, bigShadow = math.huge, -math.huge, math.huge, -math.huge, {}, 0, nil, 0
  for _, p in ipairs(parts) do
    local rel = frame:ToObjectSpace(p.CFrame)
    local s = p.Size
    local r, u, l = rel.RightVector * s.X * 0.5, rel.UpVector * s.Y * 0.5, rel.LookVector * s.Z * 0.5
    local hx = math.abs(r.X) + math.abs(u.X) + math.abs(l.X)
    local hz = math.abs(r.Z) + math.abs(u.Z) + math.abs(l.Z)
    local cp = rel.Position
    x0, x1, z0, z1 = math.min(x0, cp.X - hx), math.max(x1, cp.X + hx), math.min(z0, cp.Z - hz), math.max(z1, cp.Z + hz)
    local edge = math.abs(cp.X) - hx
    if edge < 13.2 then table.insert(laneBad, string.format("%s %.2f", p.Name, edge)) end
    if p.Name == "CheckpointArm" and p.CanCollide then armCollide += 1 end
    if p.Name == "CheckpointBooth" then booth = p end
    if math.max(s.X, s.Y, s.Z) < 4 and p.CastShadow then bigShadow += 1 end
  end
  check(#laneBad == 0, "Checkpoint: every part >= 13.2 studs from the road line (lane clear) " .. table.concat(laneBad, ", "))
  check(x1 - x0 <= 64 and z1 - z0 <= 64, string.format("Checkpoint span %.1f x %.1f <= 64 (WorldKits.Finish)", x1 - x0, z1 - z0))
  check(armCollide == 0, "Checkpoint: the boom arm never collides")
  check(booth ~= nil and booth.Size.X == 4 and booth.Size.Y == 7 and math.abs(booth.Size.Z - 4.4) < 1e-6 and booth.CanCollide
    and math.abs(frame:ToObjectSpace(booth.CFrame).Position.X - 17.5) < 1e-6, "Checkpoint: CheckpointBooth name / size / place kept (anchor clearances)")
  check(bigShadow == 0, "Checkpoint: every small part CastShadow = false")
  local posts, lights, shadowLights = 0, 0, 0
  for _, d in ipairs(booth and booth:GetChildren() or {}) do if d.ClassName == "Attachment" then posts += 1 end end
  for _, p in ipairs(parts) do for _, d in ipairs(p:GetChildren()) do
    if d.ClassName == "SpotLight" or d.ClassName == "PointLight" then lights += 1; if d.Shadows ~= false then shadowLights += 1 end end
  end end
  check(posts == 5, "Checkpoint: 5 guard posts on the booth (" .. posts .. ")")
  check(lights == 1 and shadowLights == 0, "Checkpoint: one light (the searchlight), Shadows = false (" .. lights .. ")")
  DC.Kits.Checkpoint = false
  record = {}
  WK.Add(Instance.new("Model"), "Checkpoint", frame, {})
  check(#record == plain.Parts, "Kits.Checkpoint = false: today's plain kit exactly (" .. #record .. " parts)")
  DC.Kits.Checkpoint = true
  record = nil
  WK.Sign = realSign
end
-- the allowance: spent -> plain; off -> plain
DC.MaxExtraParts = WK.DetailStats.Extra
record = {}
WK.Add(Instance.new("Model"), "Wreck", frame, { Variant = "tank" })
local live = 0
for _, p in ipairs(record) do if not rawget(p, "__destroyed") then live += 1 end end
check(live == 5, "allowance spent: the tank builds plain (" .. live .. " live parts)")
DC.MaxExtraParts = 900; DC.Enabled = false
record = {}
WK.Add(Instance.new("Model"), "Watchtower", frame, {})
check(#record == 7 or #record == 8, "Enabled = false: the watchtower builds plain (" .. #record .. " parts incl. ladder)")
record = nil
print(string.format("KIT DETAIL TEST: %d failed (extra so far %d)", fails, WK.DetailStats.Extra))
if fails > 0 then error("failed") end
'''

if __name__ == "__main__":
    chunks = [PRELUDE]
    for key, path in MODS.items():
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
    chunks.append(TEST)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    luau = os.environ.get("LUAU", "luau")
    r = subprocess.run([luau, path], capture_output=True, text=True)
    out = r.stdout.strip()
    if os.environ.get("VERBOSE"):
        print(out)
    else:
        print("\n".join(l for l in out.splitlines() if l.startswith("FAIL") or l.startswith("KIT DETAIL")) or out)
    if r.returncode != 0:
        print(r.stderr.strip()[-2000:])
        sys.exit(1)
