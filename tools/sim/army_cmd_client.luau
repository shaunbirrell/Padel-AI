-- Code Bot (army command bug): the CLIENT half of Shaun's recording, on the REAL OrdersController + MapController
-- (tools/sim/run_army_command_test.py). Remotes.FireServer is recorded and handed to SERVER_REMOTE (the server half,
-- when the test loads it) exactly like a RemoteEvent.
REMOTE_LOG = {}
PIN_LOG = {}
TOASTS = {}
PUSH_HANDLERS = {}
SERVER_REMOTE = nil -- function(player, remoteName, ...) set by the server half
SOURCES["Constants"] = function() return { RemoteNames = setmetatable({}, { __index = function(_, k) return k end }), Tags = setmetatable({}, { __index = function(_, k) return k end }) } end
SOURCES["Remotes"] = function()
  local R = {}
  function R.FireServer(name, ...)
    table.insert(REMOTE_LOG, { name = name, args = { ... } })
    if SERVER_REMOTE then SERVER_REMOTE(PlayersSvc.LocalPlayer, name, ...) end
  end
  function R.BindEvent(name, fn) PUSH_HANDLERS[name] = PUSH_HANDLERS[name] or {}; table.insert(PUSH_HANDLERS[name], fn) end
  function R.TryGetFunction() return nil end
  function R.TryGet() return nil end
  return setmetatable(R, { __index = function() return any end })
end
SOURCES["Client/Modules/ObjectiveMarker"] = function()
  local O = { pinned = nil }
  function O.ShowWith(t, opts) table.insert(PIN_LOG, { t = t, opts = opts }); if opts and opts.Pin then O.pinned = t end end
  function O.Pinned() return O.pinned ~= nil end
  function O.Current() return O.pinned end
  function O.ClearPin() O.pinned = nil end
  return O
end
SOURCES["Client/Controllers/NotificationController"] = function()
  return setmetatable({ Show = function(t, k) table.insert(TOASTS, tostring(t)) end }, { __index = function() return any end })
end
SOURCES["Client/Modules/PanelShell"] = function()
  return setmetatable({ Text = function(n) return n end, TouchMinV = function() return 44 end,
    Attach = function() return { Sync = function() end, TapThrough = function() return false end } end,
    CloseButton = function(parent) local b = Instance.new("TextButton"); b.Parent = parent; return b end,
    Screen = function() return { Scale = 1 } end }, { __index = function() return any end })
end
SOURCES["Client/Modules/HudLayout"] = function()
  return setmetatable({ Scale = function() return 1 end, GetRect = function() return Vector2.new(0, 0), Vector2.new(0, 0) end,
    ContentSizeV = function() return Vector2.new(1280, 720) end, PrefersKeys = function() return false end, SetFlag = function() end,
    InputModeChanged = MKSIG(), LayoutChanged = MKSIG(), RegisterTopStack = function() end }, { __index = function() return any end })
end

function pushToClient(name, ...)
  for _, fn in ipairs(PUSH_HANDLERS[name] or {}) do fn(...) end
end
function findInst(name, cls)
  for _, i in ipairs(ALL) do if i.Name == name and (cls == nil or i.ClassName == cls) and rawget(i, "__destroyed") ~= true then return i end end
  return nil
end
function P(x, k) return rawget(x, "__props")[k] end
function press(btn) local sg = rawget(btn, "__sig"); if sg and sg.Activated then sg.Activated:Fire() end end

-- a tap on the map canvas at world (x, z): press + release within 12 px (MapController's own input path)
function tapWorld(x, z)
  local cv, ct = findInst("Canvas", "TextButton"), findInst("Content", "Frame")
  rawget(cv, "__props").AbsolutePosition = Vector2.new(0, 0); rawget(cv, "__props").AbsoluteSize = Vector2.new(800, 800)
  rawget(cv, "__props").Visible = true
  rawget(ct, "__props").AbsolutePosition = Vector2.new(0, 0); rawget(ct, "__props").AbsoluteSize = Vector2.new(800, 800)
  local E = require(node("Configs/MapConfig")).Extent
  local u, v = (x - E.X0) / (E.X1 - E.X0), (z - E.Z0) / (E.Z1 - E.Z0)
  local inp = { UserInputType = Enum.UserInputType.Touch, Position = { X = u * 800, Y = v * 800 } }
  -- Enum stand-in compares by string: MapController checks `t ~= Enum.UserInputType.Touch`
  cv.InputBegan:Fire(inp)
  UIS.InputEnded:Fire(inp)
end

function cardText()
  local out = {}
  for _, i in ipairs(ALL) do
    if i.ClassName == "TextLabel" and rawget(i, "__destroyed") ~= true then
      local par = P(i, "Parent")
      if par and par.Name == "Side" and type(P(i, "Text")) == "string" and P(i, "Text") ~= "" then table.insert(out, P(i, "Text")) end
    end
  end
  return table.concat(out, " | ")
end

function startClient(owner)
  PlayersSvc.LocalPlayer = owner
  local MC = require(node("Client/Controllers/MapController"))
  local OC = require(node("Client/Controllers/OrdersController"))
  local ok1, e1 = xpcall(MC.Init, debug.traceback)
  if not ok1 then print("MapController.Init error", e1) end
  local ok2, e2 = xpcall(OC.Init, debug.traceback)
  if not ok2 then print("OrdersController.Init error", e2) end
  return MC, OC, ok1 and ok2
end
