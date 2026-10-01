"""Code Bot v171: run the REAL client RivalController.build() in the Luau CLI on a Roblox-faithful GUI stand-in.

The stand-in matters for one rule the older static checks could not see: Roblox THROWS when a typed property
(AnchorPoint, Position, Size, colours, ...) is assigned nil ("Unable to assign property AnchorPoint. Vector2 expected,
got nil"). build() runs inside task.spawn, so such an error silently ends it. Used by run_codebot_v171_test.py.
run_controller(source_text) -> (ok, report dict, stdout)."""
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SH = ROOT / "src/ReplicatedStorage/Shared"

PRELUDE = r'''
local TYPED = { AnchorPoint = true, Position = true, Size = true, BackgroundColor3 = true, TextColor3 = true, Color = true,
  CornerRadius = true, Font = true, TextSize = true, Thickness = true, BackgroundTransparency = true, Transparency = true }
local function signal()
  local s = { fns = {} }
  function s:Connect(f) table.insert(self.fns, f); return { Disconnect = function() end } end
  function s:Fire(...) for _, f in ipairs(self.fns) do f(...) end end
  return s
end
local INST = {}
local function newInst(class)
  local o = { __class = class, __props = { Name = class, Visible = true }, __kids = {}, __sig = {} }
  return setmetatable(o, INST)
end
INST.__index = function(t, k)
  if k == "ClassName" then return rawget(t, "__class") end
  local props = rawget(t, "__props")
  if props[k] ~= nil then return props[k] end
  if k == "Parent" then return nil end
  if k == "IsA" then return function(s, c) return s.__class == c or c == "Instance" or (c == "GuiObject" and (s.__class == "Frame" or s.__class == "TextLabel" or s.__class == "TextButton")) end end
  if k == "GetChildren" then return function(s) return table.clone(rawget(s, "__kids")) end end
  if k == "FindFirstChild" then return function(s, n) for _, c in ipairs(rawget(s, "__kids")) do if c.Name == n then return c end end return nil end end
  if k == "FindFirstChildOfClass" then return function(s, n) for _, c in ipairs(rawget(s, "__kids")) do if c.__class == n then return c end end return nil end end
  if k == "WaitForChild" then return function(s, n) for _, c in ipairs(rawget(s, "__kids")) do if c.Name == n then return c end end return nil end end
  if k == "Destroy" then return function(s) s.Parent = nil end end
  if k == "GetPropertyChangedSignal" then return function(s, n) local sg = rawget(s, "__sig"); sg[n] = sg[n] or signal(); return sg[n] end end
  if k == "Activated" or k == "ChildAdded" or k == "ChildRemoved" then local sg = rawget(t, "__sig"); sg[k] = sg[k] or signal(); return sg[k] end
  if k == "AbsoluteSize" then return Vector2.new(1024, 413) end
  return nil
end
INST.__newindex = function(t, k, v)
  if v == nil and TYPED[k] then
    error(string.format("Unable to assign property %s. got nil", k), 2)
  end
  local props = rawget(t, "__props")
  if k == "Parent" then
    local old = props.Parent
    if old then local kids = rawget(old, "__kids"); for i, c in ipairs(kids) do if c == t then table.remove(kids, i) break end end end
    props.Parent = v
    if v then table.insert(rawget(v, "__kids"), t) end
    return
  end
  props[k] = v
end
Vector2 = { new = function(x, y) return { X = x, Y = y } end, zero = { X = 0, Y = 0 } }
UDim = { new = function(s, o) return { Scale = s, Offset = o } end }
UDim2 = {
  new = function(xs, xo, ys, yo) return { X = { Scale = xs, Offset = xo }, Y = { Scale = ys, Offset = yo } } end,
  fromOffset = function(x, y) return { X = { Scale = 0, Offset = x }, Y = { Scale = 0, Offset = y } } end,
  fromScale = function(x, y) return { X = { Scale = x, Offset = 0 }, Y = { Scale = y, Offset = 0 } } end,
}
Color3 = { fromRGB = function(r, g, b) return { R = r, G = g, B = b } end, new = function(r, g, b) return { R = r, G = g, B = b } end }
local enumAny = setmetatable({}, { __index = function(t, k) local e = setmetatable({}, { __index = function(_, n) return k .. "." .. n end }); rawset(t, k, e); return e end })
Enum = enumAny
Instance = { new = function(c) return newInst(c) end }
local PG = newInst("PlayerGui"); PG.Name = "PlayerGui"
local LP = newInst("Player"); LP.UserId = 470626172; PG.Parent = LP
WARNED = {}
warn = function(...) table.insert(WARNED, table.concat({ ... }, " ")) end
SPAWN_ERR = nil
task = {
  spawn = function(f, ...) local ok, e = pcall(f, ...); if not ok then SPAWN_ERR = tostring(e) end end,
  delay = function() end, defer = function(f, ...) f(...) end, wait = function() return 0 end,
}
workspace = { CurrentCamera = { ViewportSize = { X = 1024, Y = 471 } } }
local FLAG = signal()
local MODS = {}
local CACHE = {}
local function node(name) return setmetatable({ __mod = name }, { __index = function(t, k) return node(k) end }) end
local realRequire = require
require = function(n)
  local key = type(n) == "table" and rawget(n, "__mod") or n
  if CACHE[key] ~= nil then return CACHE[key] end
  local f = MODS[key]
  if f == nil then error("no module " .. tostring(key)) end
  local v = f(node(key))
  CACHE[key] = v
  return v
end
MODS["RetentionConfig"] = function() return { Live = function(b) return b.Enabled == true and b.OwnerFirst ~= true end } end
MODS["Constants"] = function() return { RemoteNames = setmetatable({}, { __index = function(_, k) return k end }) } end
BOUND = {}
FIRED = {}
MODS["Remotes"] = function() return { BindEvent = function(n, f) BOUND[n] = f end, FireServer = function(...) table.insert(FIRED, { ... }) end } end
MODS["HudLayout"] = function() return { GetFlag = function() return false end, FlagChanged = FLAG, PanelOpened = function() end, PanelClosed = function() end, RegisterPanel = function() end } end
local RS = { WaitForChild = function(_, n) return node(n) end }
game = { GetService = function(_, n) if n == "Players" then return { LocalPlayer = LP } elseif n == "ReplicatedStorage" then return RS end return {} end }
'''

TEST = r'''
local RC = require("RivalController")
RC.Init()
local g = PG:FindFirstChild("WE_RivalTargets")
local pill = g and g:FindFirstChild("TargetsPill")
local function off(u) return u and u.X and u.X.Offset or -1 end
local function offY(u) return u and u.Y and u.Y.Offset or -1 end
print("REPORT spawn_err=" .. tostring(SPAWN_ERR))
print("REPORT gui=" .. tostring(g ~= nil) .. " pill=" .. tostring(pill ~= nil))
if pill then
  print("REPORT visible=" .. tostring(pill.Visible) .. " w=" .. off(pill.Size) .. " h=" .. offY(pill.Size) .. " x=" .. off(pill.Position) .. " y=" .. offY(pill.Position))
  local t = pill:FindFirstChild("Title")
  print("REPORT title=" .. tostring(t and t.Text))
  local r = pill:FindFirstChild("Rival")
  print("REPORT rival=" .. tostring(r and r.Text))
  print("REPORT taps=" .. tostring(#(pill.Activated.fns)))
  print("REPORT cross=" .. tostring(pill:FindFirstChild("Crosshair") ~= nil))
end
-- a server push with one target
if BOUND.FeaturePush then
  BOUND.FeaturePush("RivalTargets", { Rows = { { PlotId = 3, Name = "Rival", Army = 8, Verdict = "easy", Loot = "$100k+", Dist = 500, Level = 12 } } })
  local r = pill and pill:FindFirstChild("Rival")
  print("REPORT pushed_rival=" .. tostring(r and r.Text))
end
'''


def run_controller(source_text: str):
    rc = (SH / "Configs/RivalConfig.luau").read_text(encoding="utf-8")
    chunks = [PRELUDE,
              "MODS['RivalConfig'] = function(script)\n" + rc + "\nend",
              "MODS['RivalController'] = function(script)\n" + source_text + "\nend",
              TEST]
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True)
    rep = {}
    for line in r.stdout.splitlines():
        if line.startswith("REPORT "):
            for kv in line[7:].split(" "):
                if "=" in kv:
                    k, v = kv.split("=", 1)
                    rep[k] = v
            if line.startswith("REPORT spawn_err="):
                rep["spawn_err"] = line[len("REPORT spawn_err="):]
            if line.startswith("REPORT title="):
                rep["title"] = line[len("REPORT title="):]
            if line.startswith("REPORT rival="):
                rep["rival"] = line[len("REPORT rival="):]
            if line.startswith("REPORT pushed_rival="):
                rep["pushed_rival"] = line[len("REPORT pushed_rival="):]
    return r.returncode == 0, rep, r.stdout + r.stderr
