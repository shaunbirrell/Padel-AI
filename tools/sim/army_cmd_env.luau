-- Code Bot (army command bug, 2026-10-01): the shared stand-ins for tools/sim/run_army_command_test.py (appended after
-- run_kit_detail_test.PRELUDE). GUI instances get real signals (Activated, InputBegan, GetPropertyChangedSignal), a
-- FindFirstChild by name, AbsolutePosition / AbsoluteSize; task.spawn runs a coroutine (task.wait parks it for good:
-- a refresh loop runs once); UserInputService has real InputBegan / InputEnded signals the test fires.
warn = function(...) print("WARN", ...) end
NOW = 1000
UNIX = 50000
local ok_os = os
os = setmetatable({ time = function() return UNIX end, clock = function() return NOW end }, { __index = ok_os })
local function mksig()
  local s = { fns = {} }
  function s:Connect(fn) table.insert(self.fns, fn); local c = { Connected = true }; function c.Disconnect() c.Connected = false end; return c end
  function s:Once(fn) return self:Connect(fn) end
  function s:Fire(...) for _, f in ipairs(table.clone(self.fns)) do f(...) end end
  function s:Wait() return nil end
  return s
end
MKSIG = mksig
local SIGNALS = { Activated = true, InputBegan = true, InputEnded = true, InputChanged = true, MouseButton1Click = true, MouseButton1Down = true,
  TouchPinch = true, MouseWheelForward = true, MouseWheelBackward = true, MouseEnter = true, MouseLeave = true, Changed = true,
  AncestryChanged = true, ChildAdded = true, Destroying = true, FocusLost = true, AttributeChanged = true, Touched = true }
local GUI = { Frame = true, TextLabel = true, TextButton = true, ScrollingFrame = true, ImageLabel = true, ImageButton = true, TextBox = true, CanvasGroup = true }
ALL = {}
local newI = Instance.new
Instance.new = function(c) local i = newI(c); table.insert(ALL, i); return i end
local baseI = INST.__index
INST.__index = function(t, k)
  if SIGNALS[k] then
    local sg = rawget(t, "__sig"); if sg == nil then sg = {}; rawset(t, "__sig", sg) end
    if sg[k] == nil then sg[k] = mksig() end
    return sg[k]
  end
  if k == "GetPropertyChangedSignal" or k == "GetAttributeChangedSignal" then return function(s, p)
    local sg = rawget(s, "__sig"); if sg == nil then sg = {}; rawset(s, "__sig", sg) end
    local key = k .. ":" .. p
    if sg[key] == nil then sg[key] = mksig() end
    return sg[key]
  end end
  if k == "FindFirstChild" or k == "WaitForChild" then return function(s, n) for _, c in ipairs(rawget(s, "__kids") or {}) do if c.Name == n then return c end end return nil end end
  if k == "FindFirstChildOfClass" or k == "FindFirstChildWhichIsA" then return function(s, n) for _, c in ipairs(rawget(s, "__kids") or {}) do if c.ClassName == n then return c end end return nil end end
  if k == "FindFirstAncestorWhichIsA" or k == "FindFirstAncestorOfClass" then return function() return nil end end
  if k == "IsA" then return function(s, c) return s.ClassName == c or c == "Instance" or (c == "GuiObject" and GUI[s.ClassName] == true) or (c == "GuiButton" and (s.ClassName == "TextButton" or s.ClassName == "ImageButton")) or (c == "BasePart" and s.ClassName == "Part") end end
  if k == "IsDescendantOf" then return function() return true end end
  if k == "ClearAllChildren" then return function(s) for _, c in ipairs(rawget(s, "__kids") or {}) do c.Parent = nil end end end
  local v = baseI(t, k)
  if v == nil then
    if k == "AbsoluteSize" or k == "AbsolutePosition" then return Vector2.new(0, 0) end
    if k == "Name" then return rawget(t, "ClassName") end
    if k ~= "Parent" and k ~= "Visible" and k ~= "LayoutOrder" and k ~= "Text" and string.match(k, "^%u") then return ANY end
  end
  return v
end
ANY = any
local amt = getmetatable(any)
local function anyop() return any end
amt.__newindex = function() end; amt.__add = anyop; amt.__sub = anyop; amt.__mul = anyop; amt.__div = anyop; amt.__unm = anyop
amt.__concat = function() return "any" end; amt.__lt = function() return false end; amt.__le = function() return false end
amt.__len = function() return 0 end; amt.__iter = function() return function() return nil end end; amt.__tostring = function() return "any" end
local V2 = {}
V2.__index = function(t, k) if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y) end return nil end
V2.__add = function(a, b) return Vector2.new(a.X + b.X, a.Y + b.Y) end
V2.__sub = function(a, b) return Vector2.new(a.X - b.X, a.Y - b.Y) end
V2.__mul = function(a, b) if type(a) == "number" then return Vector2.new(a * b.X, a * b.Y) elseif type(b) == "number" then return Vector2.new(a.X * b, a.Y * b) end return Vector2.new(a.X * b.X, a.Y * b.Y) end
V2.__div = function(a, b) if type(b) == "number" then return Vector2.new(a.X / b, a.Y / b) end return Vector2.new(a.X / b.X, a.Y / b.Y) end
Vector2 = { new = function(x, y) return setmetatable({ X = x or 0, Y = y or 0 }, V2) end }
Vector2.zero = Vector2.new(0, 0)
Vector2.one = Vector2.new(1, 1)
UDim2 = { new = function(a, b, c, d) return { X = { Scale = a or 0, Offset = b or 0 }, Y = { Scale = c or 0, Offset = d or 0 } } end,
  fromOffset = function(x, y) return { X = { Scale = 0, Offset = x or 0 }, Y = { Scale = 0, Offset = y or 0 } } end,
  fromScale = function(x, y) return { X = { Scale = x or 0, Offset = 0 }, Y = { Scale = y or 0, Offset = 0 } } end }
UDim = { new = function(a, b) return { Scale = a, Offset = b } end }
-- coroutine tasks: task.wait parks the thread for good (a loop runs once); task.delay never fires
task = {
  spawn = function(fn, ...) local co = coroutine.create(fn); local ok, err = coroutine.resume(co, ...); if not ok then print("TASK ERROR", err) end return co end,
  defer = function(fn, ...) local co = coroutine.create(fn); local ok, err = coroutine.resume(co, ...); if not ok then print("TASK ERROR", err) end return co end,
  delay = function() end,
  wait = function(s) if coroutine.isyieldable() then coroutine.yield() end return s or 0 end,
  cancel = function() end,
}
-- a sync spawn for server code that must finish now (ArmyPlan routes in the sim): the test swaps it in
SYNC_TASK = { spawn = function(fn, ...) fn(...) end, wait = function(s) NOW += (s or 0) end, delay = function() end, defer = function(fn, ...) fn(...) end, cancel = function() end }

-- the one Players / RunService / UserInputService for client and server code in the same VM
UIS = { TouchEnabled = true, KeyboardEnabled = false, MouseEnabled = false, GamepadEnabled = false, InputBegan = mksig(), InputEnded = mksig(), InputChanged = mksig(),
  LastInputTypeChanged = mksig(), TouchStarted = mksig(), TouchEnded = mksig(), GetLastInputType = function() return "Enum.UserInputType.Touch" end,
  GetMouseLocation = function() return Vector2.new(0, 0) end }
PLAYERS = {}
PlayersSvc = { PlayerAdded = mksig(), PlayerRemoving = mksig(), LocalPlayer = nil, GetPlayers = function() return PLAYERS end,
  GetPlayerByUserId = function(_, id) for _, p in ipairs(PLAYERS) do if p.UserId == id then return p end end return nil end,
  GetPlayerFromCharacter = function() return nil end }
RunSvc = { IsStudio = function() return false end, IsServer = function() return true end, IsClient = function() return true end, Heartbeat = mksig(), RenderStepped = mksig(), Stepped = mksig() }
WorkspaceSvc = { FallenPartsDestroyHeight = -500, Raycast = function() return nil end, CurrentCamera = any }
game = { GetService = function(_, n)
  if n == "ReplicatedStorage" then return RS_ elseif n == "Players" then return PlayersSvc elseif n == "RunService" then return RunSvc
  elseif n == "UserInputService" then return UIS elseif n == "Workspace" then return WorkspaceSvc end
  return any end, PlaceId = 1 }
workspace = WorkspaceSvc
