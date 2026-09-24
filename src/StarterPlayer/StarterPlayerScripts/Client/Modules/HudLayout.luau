--!strict
--[[
	HudLayout — the v70 HUD's shared layout brain (client only). Every HUD controller codes against this API;
	the numbers live in Shared/Configs/HudConfig.luau.

	GUARANTEES
	  * Works before anything registers: every getter answers from the camera / GuiService / a tiny probe gui.
	  * Never yields (the only yielding member is Signal:Wait(), on purpose).
	  * Degrades when ScreenInsets.TopbarSafeInsets / GuiService.TopbarInset / ScreenGui.ScreenInsets are
	    missing on an older client (spec risk #1): IgnoreGuiInset fallbacks + HudConfig.TopStrip.FallbackLeft.

	COORDINATES
	  "real" = device px. "v" = offsets under the HUD UIScale "MobileScale" (real = v × Scale()).
	  Rects returned here (ContentRect, Reserve, GetRect, TopStack placement) are in the SAME space as
	  GuiObject.AbsolutePosition, so compare them with AbsolutePosition/AbsoluteSize directly. TopbarRect() is
	  in screen px (GuiService.TopbarInset space).

	API (fixed contracts, spec §9)
	  ApplyScreen(screen, {DisplayOrder?, Insets? = "Core"|"Topbar"|"None"|"Device", Scale?}) -> UIScale?
	  Scale() -> number · IsTouch() -> boolean · ContentSizeV() -> Vector2
	  PrefersKeys() -> boolean · InputModeChanged (prefersKeys)   -- key hints / keyboard copy (CLAUDE.md §1)
	  SetFlag(name, on) · GetFlag(name) -> boolean · FlagChanged (name, on)
	  BindVisibility(obj, {ShowWhen?, HideWhen?}, extra?)
	  RegisterTopStack(name, obj, order, {Space? = "Hud"|"Screen"})
	  RegisterPanel(id, isOpen, close, {Fallback?, NonModal?}) · PanelOpened(id) · PanelClosed(id)
	  SetBadge(tileId, text?) · BadgeChanged (tileId, text?)
	  CashFloat(amount) · CashFloatRequested (amount)
	  SetRect(name, obj) · GetRect(name) -> (pos, size)
	  Reserve("CombatTouch"|"CombatDesktop"|"Combat") -> Rect
	  ActionLaneBottomV() -> number
	  Signals.CompassTapped
	EXTRAS
	  Init() · LayoutChanged · ContentRect() · ToPx(v) · ToV(px) · TopbarRect() · TopbarArea(screen)
	  UnbindVisibility(obj) · RefreshVisibility(obj?) · EvalRule(rule, extra?) · Flags()
	  UnregisterTopStack(name) · RelayoutTopStack() · TopStackMaxWidthV()
	  IsPanelOpen(id) · OpenPanelId() · CloseAllPanels() · HasPanel(id) · PanelSerial() · PanelChanged (id, open)
	  GetBadge(tileId) · Emit(signalName, ...) · AssertTouchTarget(obj, label?)
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HudConfig = require(Shared.Configs.HudConfig)
local UIUtil = require(Shared.Util.UIUtil)

local HudLayout = {}

export type Rule = { ShowWhen: { string }?, HideWhen: { string }? }
-- what BindVisibility / EvalRule accept: any table with HideWhen and/or ShowWhen (HudConfig.Rail, .Hotbar, ...)
export type RuleArg = Rule | { HideWhen: { string } } | { ShowWhen: { string } }
export type ScreenOpts = { DisplayOrder: number?, Insets: string?, Scale: boolean? }
export type StackOpts = { Space: string? }

local PROBE_NAME = "WE_HudProbe"
local FALLBACK_VIEWPORT = Vector2.new(1280, 720)
local FALLBACK_TOPBAR_H = 58

---------------------------------------------------------------------------------------------------------------
-- tiny signal (RBXScriptSignal-shaped: Connect / Once / Wait / ConnectParallel; conn:Disconnect())
-- Handlers run through task.spawn, so one failing handler never stops the others.
---------------------------------------------------------------------------------------------------------------

local function newSignal(): (any, (...any) -> ())
	local conns: { any } = {}
	local waiting: { thread } = {}
	local sig: any = {}
	local function connect(_self: any, fn: (...any) -> ()): any
		local c: any = { Connected = true, Fn = fn }
		c.Disconnect = function(_: any)
			if not c.Connected then
				return
			end
			c.Connected = false
			local i = table.find(conns, c)
			if i then
				table.remove(conns, i)
			end
		end
		table.insert(conns, c)
		return c
	end
	sig.Connect = connect
	sig.ConnectParallel = connect
	sig.Once = function(self: any, fn: (...any) -> ()): any
		local c: any = nil
		c = connect(self, function(...)
			if c then
				c:Disconnect()
			end
			fn(...)
		end)
		return c
	end
	sig.Wait = function(_self: any): ...any
		table.insert(waiting, coroutine.running())
		return coroutine.yield()
	end
	local function fire(...: any)
		for _, c in ipairs(table.clone(conns)) do
			if c.Connected then
				task.spawn(c.Fn, ...)
			end
		end
		if #waiting > 0 then
			local w = waiting
			waiting = {}
			for _, co in ipairs(w) do
				task.spawn(co, ...)
			end
		end
	end
	return sig, fire
end

local flagSig, fireFlag = newSignal()
local badgeSig, fireBadge = newSignal()
local cashSig, fireCash = newSignal()
local layoutSig, fireLayout = newSignal()
local panelSig, firePanel = newSignal()
local compassSig, fireCompass = newSignal()
local inputSig, fireInput = newSignal()

HudLayout.FlagChanged = flagSig :: RBXScriptSignal<string, boolean>
HudLayout.BadgeChanged = badgeSig :: RBXScriptSignal<string, string?>
HudLayout.CashFloatRequested = cashSig :: RBXScriptSignal<number>
HudLayout.LayoutChanged = layoutSig :: RBXScriptSignal<>
HudLayout.PanelChanged = panelSig :: RBXScriptSignal<string, boolean>
HudLayout.InputModeChanged = inputSig :: RBXScriptSignal<boolean>
HudLayout.Signals = {
	CompassTapped = compassSig :: RBXScriptSignal<>, -- CompassController fires (Emit), TerritoryController listens
}
local emitters: { [string]: (...any) -> () } = { CompassTapped = fireCompass }

local warned: { [string]: boolean } = {}
local function warnOnce(key: string, ...: any)
	if warned[key] then
		return
	end
	warned[key] = true
	warn("[HudLayout]", ...)
end

---------------------------------------------------------------------------------------------------------------
-- device, viewport, scale, content rect
---------------------------------------------------------------------------------------------------------------

local touchOverride: boolean? = nil

-- Same test as VehicleDriveClient / every controller (UserInputService.TouchEnabled) so the touch reserve,
-- the ▲▼ column and the touch combat buttons always agree.
function HudLayout.IsTouch(): boolean
	if touchOverride ~= nil then
		return touchOverride
	end
	return UserInputService.TouchEnabled == true
end

--[[
	Key hints and keyboard copy ("press K", "WASD", key caps, the Settings controls sheet) show ONLY when this is
	true: UserInputService.PreferredInput is KeyboardAndMouse or Gamepad (CLAUDE.md §1 "Copy by device": detect
	with PreferredInput, not TouchEnabled). IsTouch() stays the LAYOUT switch (tap-target sizes).
	Fallback when the property is missing (older clients, the headless harness): the last input type, then
	"has a keyboard and no touch screen". A phone therefore never gets key copy.
]]
local keyPrefOverride: boolean? = nil

local function readPreferredInput(): string?
	local ok, v = pcall(function(): any
		return (UserInputService :: any).PreferredInput
	end)
	if ok and typeof(v) == "EnumItem" then
		local name = (v :: EnumItem).Name
		if name == "KeyboardAndMouse" or name == "Gamepad" or name == "Touch" then
			return name
		end
	end
	return nil
end

local function lastInputPrefersKeys(): boolean?
	local ok, t = pcall(function(): any
		return UserInputService:GetLastInputType()
	end)
	if not ok or typeof(t) ~= "EnumItem" then
		return nil
	end
	local name = (t :: EnumItem).Name
	if name == "Touch" then
		return false
	end
	if name == "Keyboard" or string.sub(name, 1, 5) == "Mouse" or string.sub(name, 1, 7) == "Gamepad" then
		return true
	end
	return nil
end

function HudLayout.PrefersKeys(): boolean
	if keyPrefOverride ~= nil then
		return keyPrefOverride
	end
	local pref = readPreferredInput()
	if pref then
		return pref ~= "Touch"
	end
	local last = lastInputPrefersKeys()
	if last ~= nil then
		return last
	end
	local okT, touch = pcall(function(): boolean
		return UserInputService.TouchEnabled == true
	end)
	local okK, keys = pcall(function(): boolean
		return UserInputService.KeyboardEnabled == true or UserInputService.GamepadEnabled == true
	end)
	return (okK and keys == true) and not (okT and touch == true)
end

local lastKeyPref: boolean? = nil
local function checkInputMode()
	local now = HudLayout.PrefersKeys()
	if now ~= lastKeyPref then
		local first = lastKeyPref == nil
		lastKeyPref = now
		if not first then
			fireInput(now)
		end
	end
end

local function viewportSize(): Vector2
	local cam = Workspace.CurrentCamera
	if cam then
		local v = cam.ViewportSize
		if v.X > 1 and v.Y > 1 then
			return v
		end
	end
	return FALLBACK_VIEWPORT
end

local function scaleFor(vp: Vector2): number
	local sc = HudConfig.Scale
	return math.clamp(math.min(vp.X, vp.Y) / sc.BasePx, sc.Min, sc.Max)
end

--[[ S = clamp(min(vw, vh) / 800, 0.70, 1.15): 844x390 → 0.70, 956x440 → 0.70, 1280x720 → 0.90, 1920x1080 → 1.15 ]]
function HudLayout.Scale(): number
	return scaleFor(viewportSize())
end

function HudLayout.ToPx(v: number): number
	return v * HudLayout.Scale()
end

function HudLayout.ToV(px: number): number
	return px / HudLayout.Scale()
end

local function guiInset(): (Vector2, Vector2)
	local ok, tl, br = pcall(function()
		return GuiService:GetGuiInset()
	end)
	if ok and typeof(tl) == "Vector2" and typeof(br) == "Vector2" then
		return tl, br
	end
	return Vector2.new(0, FALLBACK_TOPBAR_H), Vector2.zero
end

local probe: ScreenGui? = nil
local probeConns: { RBXScriptConnection } = {}
local onLayoutChanged: () -> () -- forward

local function ensureProbe(): ScreenGui?
	local g = probe
	if g and g.Parent then
		return g
	end
	local lp = Players.LocalPlayer
	local pg = lp and lp:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil
	end
	local existing = pg:FindFirstChild(PROBE_NAME)
	local sg: ScreenGui
	if existing and existing:IsA("ScreenGui") then
		sg = existing
	else
		sg = Instance.new("ScreenGui")
		sg.Name = PROBE_NAME
		sg.ResetOnSpawn = false
		sg.DisplayOrder = -1
		sg.IgnoreGuiInset = false
		pcall(function()
			sg.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
		end)
		sg.Parent = pg
	end
	for _, c in ipairs(probeConns) do
		c:Disconnect()
	end
	table.clear(probeConns)
	table.insert(probeConns, sg:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		onLayoutChanged()
	end))
	table.insert(probeConns, sg:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
		onLayoutChanged()
	end))
	probe = sg
	return sg
end

-- the safe content rect (CoreUISafeInsets area) in AbsolutePosition space: x, y, w, h (real px)
local function contentRect(): (number, number, number, number)
	local g = ensureProbe()
	if g then
		local ok, pos, size = pcall(function()
			return g.AbsolutePosition, g.AbsoluteSize
		end)
		if ok and typeof(pos) == "Vector2" and typeof(size) == "Vector2" and size.X > 1 and size.Y > 1 then
			return pos.X, pos.Y, size.X, size.Y
		end
	end
	-- no PlayerGui yet: viewport minus the gui inset (no notch information)
	local vp = viewportSize()
	local tl, br = guiInset()
	return tl.X, tl.Y, math.max(1, vp.X - tl.X - br.X), math.max(1, vp.Y - tl.Y - br.Y)
end

function HudLayout.ContentRect(): Rect
	local x, y, w, h = contentRect()
	return Rect.new(x, y, x + w, y + h)
end

--[[ The content rect in v (844x390 → 1071x474). ]]
function HudLayout.ContentSizeV(): Vector2
	local _, _, w, h = contentRect()
	local s = HudLayout.Scale()
	return Vector2.new(w / s, h / s)
end

---------------------------------------------------------------------------------------------------------------
-- topbar row (TopStrip)
---------------------------------------------------------------------------------------------------------------

local function topbarInsetRect(): Rect?
	local ok, r = pcall(function()
		return (GuiService :: any).TopbarInset
	end)
	if ok and typeof(r) == "Rect" and r.Width > 0 and r.Height > 0 then
		return r
	end
	return nil
end

--[[ The free part of the Roblox topbar row in screen px: GuiService.TopbarInset, or (older clients) from
	safe-left + HudConfig.TopStrip.FallbackLeft to the content's right edge, GetGuiInset().Y tall. ]]
function HudLayout.TopbarRect(): Rect
	local r = topbarInsetRect()
	if r then
		return r
	end
	local cx, _, cw, _ = contentRect()
	local tl = guiInset()
	local h = if tl.Y >= 1 then tl.Y else FALLBACK_TOPBAR_H
	local left = cx + HudConfig.TopStrip.FallbackLeft
	return Rect.new(left, 0, math.max(left, cx + cw), h)
end

local topbarAreas: { [ScreenGui]: Frame } = setmetatable({} :: any, { __mode = "k" })

local function placeTopbarArea(screen: ScreenGui, f: Frame)
	if screen:GetAttribute("WE_HudInsets") == "Topbar" then
		-- native TopbarSafeInsets: the gui itself is the free topbar row and reflows with the unibar
		f.Position = UDim2.fromScale(0, 0)
		f.Size = UDim2.fromScale(1, 1)
		return
	end
	-- fallback (IgnoreGuiInset = true): place the row in this gui's local px. Abs X == screen X; the gui's
	-- top is the screen top, i.e. content top − the gui inset, whatever the AbsolutePosition convention.
	local r = HudLayout.TopbarRect()
	local _, cy = contentRect()
	local tl = guiInset()
	local origin = screen.AbsolutePosition
	local originX = origin.X
	local originY = origin.Y - (cy - tl.Y)
	f.Position = UDim2.fromOffset(r.Min.X - originX, r.Min.Y - originY)
	f.Size = UDim2.fromOffset(r.Width, r.Height)
end

--[[ A transparent Frame "TopbarArea" inside a TopStrip gui (ApplyScreen Insets = "Topbar") that always covers
	the free topbar row, native or fallback. Put the left group at (0, EdgePad, 0.5, YNudge) and the compass at
	(1, -EdgePad, 0.5, 0) inside it. Kept in place on LayoutChanged. ]]
function HudLayout.TopbarArea(screen: ScreenGui): Frame
	local found = screen:FindFirstChild("TopbarArea")
	local f: Frame
	if found and found:IsA("Frame") then
		f = found
	else
		f = Instance.new("Frame")
		f.Name = "TopbarArea"
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Active = false
		f.Parent = screen
	end
	topbarAreas[screen] = f
	placeTopbarArea(screen, f)
	return f
end

---------------------------------------------------------------------------------------------------------------
-- ScreenGui setup + the one shared UIScale
---------------------------------------------------------------------------------------------------------------

local trackedScales: { [UIScale]: boolean } = setmetatable({} :: any, { __mode = "k" })

local function setInsets(screen: ScreenGui, want: Enum.ScreenInsets): boolean
	local ok = pcall(function()
		screen.ScreenInsets = want
	end)
	return ok
end

local function enumInset(name: string): Enum.ScreenInsets?
	local ok, item = pcall(function()
		return (Enum.ScreenInsets :: any)[name]
	end)
	if ok and typeof(item) == "EnumItem" then
		return item :: Enum.ScreenInsets
	end
	return nil
end

-- returns the mode actually applied: "Core" | "Topbar" | "TopbarFallback" | "None" | "Device" | "Legacy"
local function applyInsets(screen: ScreenGui, insets: string): string
	if insets == "Topbar" then
		screen.IgnoreGuiInset = true
		local item = enumInset("TopbarSafeInsets")
		if item and setInsets(screen, item) then
			return "Topbar"
		end
		return "TopbarFallback"
	elseif insets == "None" or insets == "Device" then
		screen.IgnoreGuiInset = true
		local item = enumInset(if insets == "None" then "None" else "DeviceSafeInsets")
		if item and setInsets(screen, item) then
			return insets
		end
		return "Legacy"
	end
	if insets ~= "Core" then
		warnOnce("insets:" .. insets, "unknown Insets", insets, "- using Core")
	end
	screen.IgnoreGuiInset = false
	local item = enumInset("CoreUISafeInsets")
	if item and setInsets(screen, item) then
		return "Core"
	end
	return "Legacy" -- IgnoreGuiInset = false is the old-client equivalent
end

--[[
	The only way a HUD ScreenGui is set up. ResetOnSpawn = false, Sibling z, DisplayOrder (opts or
	HudConfig.DisplayOrder[screen.Name]), insets, and ONE UIScale "MobileScale" (reused if the gui has one)
	that HudLayout keeps at Scale(). Scale defaults to true except for Insets = "Topbar" (real px).
	The applied mode is stored in the attribute WE_HudInsets ("Core", "Topbar", "TopbarFallback", "None",
	"Device", "Legacy"). Returns the UIScale, or nil when Scale = false.
]]
function HudLayout.ApplyScreen(screen: ScreenGui, opts: ScreenOpts?): UIScale?
	local o: ScreenOpts = opts or {}
	local insets = o.Insets or "Core"
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local order = o.DisplayOrder or (HudConfig.DisplayOrder :: any)[screen.Name]
	if typeof(order) == "number" then
		screen.DisplayOrder = order
	end
	local mode = applyInsets(screen, insets)
	screen:SetAttribute("WE_HudInsets", mode)

	local wantScale = if o.Scale == nil then insets ~= "Topbar" else o.Scale == true
	local existing: UIScale? = nil
	for _, c in ipairs(screen:GetChildren()) do
		if c:IsA("UIScale") then
			if c.Name == "MobileScale" then
				existing = c
				break
			end
			if not existing then
				existing = c
			end
		end
	end
	if existing then
		UIUtil.ReleaseMobileScale(existing) -- stop UIUtil.AttachMobileScale's own tracker fighting ours
	end
	if not wantScale then
		if existing then
			trackedScales[existing] = nil
			existing:Destroy()
		end
		if topbarAreas[screen] then
			placeTopbarArea(screen, topbarAreas[screen])
		end
		return nil
	end
	local sc: UIScale = existing or Instance.new("UIScale")
	sc.Name = "MobileScale"
	sc.Scale = HudLayout.Scale()
	sc.Parent = screen
	trackedScales[sc] = true
	return sc
end

---------------------------------------------------------------------------------------------------------------
-- context flags + visibility
---------------------------------------------------------------------------------------------------------------

local flags: { [string]: boolean } = {}

type Binding = { Rule: Rule, Extra: (() -> boolean)? }
local bindings: { [GuiObject]: Binding } = setmetatable({} :: any, { __mode = "k" })

-- true / false, or nil when `extra` threw (keep the current visibility)
local function evalRule(rule: Rule, extra: (() -> boolean)?): boolean?
	local hide = rule.HideWhen
	if hide then
		for _, f in ipairs(hide) do
			if flags[f] then
				return false
			end
		end
	end
	local show = rule.ShowWhen
	if show and #show > 0 then
		local any = false
		for _, f in ipairs(show) do
			if flags[f] then
				any = true
				break
			end
		end
		if not any then
			return false
		end
	end
	if extra then
		local ok, res = pcall(extra)
		if not ok then
			warnOnce("extra:" .. tostring(extra), "BindVisibility extra() failed:", res)
			return nil
		end
		return res == true
	end
	return true
end

local function applyBinding(obj: GuiObject, b: Binding)
	local v = evalRule(b.Rule, b.Extra)
	if v == nil then
		return
	end
	local inst: Instance = obj
	if inst:IsA("GuiObject") then
		if inst.Visible ~= v then
			inst.Visible = v
		end
	elseif inst:IsA("LayerCollector") then
		if inst.Enabled ~= v then
			inst.Enabled = v
		end
	end
end

local function ruleMentions(rule: Rule, name: string): boolean
	if rule.HideWhen and table.find(rule.HideWhen, name) then
		return true
	end
	if rule.ShowWhen and table.find(rule.ShowWhen, name) then
		return true
	end
	return false
end

function HudLayout.GetFlag(name: string): boolean
	return flags[name] == true
end

--[[ Context flags (HudConfig.Context.Flags + OrdersOpen, Radar, or any name). Fires FlagChanged on change. ]]
function HudLayout.SetFlag(name: string, on: boolean)
	local v = on == true
	if (flags[name] == true) == v then
		return
	end
	flags[name] = v
	for obj, b in pairs(bindings) do
		if ruleMentions(b.Rule, name) then
			applyBinding(obj, b)
		end
	end
	fireFlag(name, v)
end

function HudLayout.Flags(): { [string]: boolean }
	return table.clone(flags)
end

--[[ true when the rule passes right now (all HideWhen flags off, any ShowWhen flag on, extra() true). ]]
function HudLayout.EvalRule(rule: RuleArg, extra: (() -> boolean)?): boolean
	return evalRule(rule :: any, extra) == true
end

--[[
	HudLayout owns obj.Visible from now on (a ScreenGui: .Enabled): visible = no HideWhen flag on AND (no
	ShowWhen, or any ShowWhen flag on) AND (extra == nil or extra()). Re-evaluated on every relevant SetFlag;
	call RefreshVisibility(obj) when whatever extra() reads changes. Rebinding replaces the old rule.
	HudConfig tables work as rules directly: BindVisibility(rail, HudConfig.Rail).
]]
function HudLayout.BindVisibility(obj: GuiObject, rule: RuleArg, extra: (() -> boolean)?)
	local r: Rule = rule :: any
	local b: Binding = { Rule = { ShowWhen = r.ShowWhen, HideWhen = r.HideWhen }, Extra = extra }
	bindings[obj] = b
	applyBinding(obj, b)
end

function HudLayout.UnbindVisibility(obj: GuiObject)
	bindings[obj] = nil
end

function HudLayout.RefreshVisibility(obj: GuiObject?)
	if obj then
		local b = bindings[obj]
		if b then
			applyBinding(obj, b)
		end
		return
	end
	for o, b in pairs(bindings) do
		applyBinding(o, b)
	end
end

---------------------------------------------------------------------------------------------------------------
-- top-centre stack
---------------------------------------------------------------------------------------------------------------

type StackItem = {
	Name: string,
	Obj: GuiObject,
	Order: number,
	Seq: number,
	Space: string,
	Conns: { RBXScriptConnection },
}
local stack: { [string]: StackItem } = {}
local stackSeq = 0
local stackQueued = false

local function firstUIScale(inst: Instance): number
	for _, c in ipairs(inst:GetChildren()) do
		if c:IsA("UIScale") then
			return c.Scale
		end
	end
	return 1
end

-- product of the UIScales that act on `from`'s children: from itself up to (and including) its LayerCollector
local function chainScale(from: Instance?): number
	local k = 1
	local p = from
	while p do
		k *= firstUIScale(p)
		if p:IsA("LayerCollector") then
			break
		end
		p = p.Parent
	end
	return k
end

local function shownOnScreen(obj: GuiObject): boolean
	if not obj.Visible then
		return false
	end
	local p = obj.Parent
	while p do
		if p:IsA("GuiObject") then
			if not p.Visible then
				return false
			end
		elseif p:IsA("LayerCollector") then
			return p.Enabled
		else
			return false
		end
		p = p.Parent
	end
	return false
end

--[[ Place every registered, visible item top-down in Order (ties: registration order). Synchronous. ]]
function HudLayout.RelayoutTopStack()
	stackQueued = false
	if next(stack) == nil then
		return
	end
	local items: { StackItem } = {}
	for _, it in pairs(stack) do
		if it.Obj.Parent then
			table.insert(items, it)
		end
	end
	table.sort(items, function(a: StackItem, b: StackItem): boolean
		if a.Order ~= b.Order then
			return a.Order < b.Order
		end
		return a.Seq < b.Seq
	end)
	local _, cy = contentRect()
	local s = HudLayout.Scale()
	local y = cy + HudConfig.TopStack.Top * s
	local gap = HudConfig.TopStack.Gap * s
	for _, it in ipairs(items) do
		local obj = it.Obj
		if shownOnScreen(obj) then
			local own = firstUIScale(obj)
			if own <= 0 then
				own = 1
			end
			local h = obj.AbsoluteSize.Y / own -- real px, ignoring the item's own pop-in UIScale
			local parent = obj.Parent
			local parentY = cy
			if parent and parent:IsA("GuiBase2d") then
				parentY = parent.AbsolutePosition.Y
			end
			local k = chainScale(parent)
			if k <= 0 then
				k = 1
			end
			local offset = (y + obj.AnchorPoint.Y * h - parentY) / k
			local pos = obj.Position
			if pos.Y.Scale ~= 0 or math.abs(pos.Y.Offset - offset) > 0.01 then
				obj.Position = UDim2.new(pos.X.Scale, pos.X.Offset, 0, offset)
			end
			y += h + gap
		end
	end
end

local function queueStack()
	if stackQueued then
		return
	end
	stackQueued = true
	task.defer(function()
		if stackQueued then
			HudLayout.RelayoutTopStack()
		end
	end)
end

function HudLayout.UnregisterTopStack(name: string)
	local it = stack[name]
	if not it then
		return
	end
	for _, c in ipairs(it.Conns) do
		c:Disconnect()
	end
	stack[name] = nil
	queueStack()
end

--[[
	Stack obj in the top-centre column under the topbar (HudConfig.TopStack: Top 8 v, Gap 6 v; Order from
	HudConfig.TopStack.Order — Alert 10, Progress 20, Objective 30, Toasts 40, Offer 50). HudLayout writes only
	obj.Position.Y (X stays yours: use (0.5, 0) + AnchorPoint X 0.5). Hidden items collapse. Re-runs when an
	item's Visible / AbsoluteSize / parent / its gui's Enabled change, and on LayoutChanged.
	opts.Space ("Hud" = inside a MobileScale gui, "Screen" = real px gui like WE_MissileAlert) is accepted for
	clarity; the math reads the parent chain's actual UIScales and AbsolutePosition, so either works.
	obj must not be inside a UIListLayout / UIGridLayout (the layout would own its Position).
]]
function HudLayout.RegisterTopStack(name: string, obj: GuiObject, order: number, opts: StackOpts?)
	HudLayout.UnregisterTopStack(name)
	stackSeq += 1
	local it: StackItem = {
		Name = name,
		Obj = obj,
		Order = order,
		Seq = stackSeq,
		Space = (opts and opts.Space) or "Hud",
		Conns = {},
	}
	stack[name] = it
	local gui: LayerCollector? = nil
	local guiConn: RBXScriptConnection? = nil
	local function watchGui()
		local g = obj:FindFirstAncestorWhichIsA("LayerCollector")
		if g == gui then
			return
		end
		if guiConn then
			guiConn:Disconnect()
			guiConn = nil
		end
		gui = g
		if g then
			guiConn = g:GetPropertyChangedSignal("Enabled"):Connect(queueStack)
		end
	end
	table.insert(it.Conns, obj:GetPropertyChangedSignal("Visible"):Connect(queueStack))
	table.insert(it.Conns, obj:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueStack))
	table.insert(it.Conns, obj.AncestryChanged:Connect(function()
		watchGui()
		queueStack()
	end))
	watchGui()
	-- disconnect the gui watcher together with the item
	table.insert(it.Conns, {
		Disconnect = function()
			if guiConn then
				guiConn:Disconnect()
				guiConn = nil
			end
		end,
	} :: any)
	HudLayout.RelayoutTopStack()
end

--[[ Widest an item in the stack may be, in v (HudConfig.TopStack.MaxWidthScale × content width). ]]
function HudLayout.TopStackMaxWidthV(): number
	local _, _, w = contentRect()
	return HudConfig.TopStack.MaxWidthScale * w / HudLayout.Scale()
end

---------------------------------------------------------------------------------------------------------------
-- panels (one open at a time → Modal flag)
---------------------------------------------------------------------------------------------------------------

type Panel = { IsOpen: () -> boolean, Close: () -> (), Fallback: boolean, NonModal: boolean }
-- NonModal (the Army popover, mobile plan P1-6): still one-open-at-a-time with the other panels, but it does NOT
-- raise the Modal flag, so FIRE / the hotbar / the prompt lane stay up while it is open
export type PanelOpts = { Fallback: boolean?, NonModal: boolean? }
local panels: { [string]: Panel } = {}
local openPanels: { [string]: boolean } = {}
local lastOpened: string? = nil
local closingOthers = false
local panelSerial = 0

-- should PanelOpened(other) / CloseAllPanels close `id`? A Fallback registration (UIController's stand-in for a
-- panel that did not register itself) counts only while the registry lists it open, so a stand-in filed under a
-- different id than the panel's own registration can never close the panel that just opened.
local function panelReportsOpen(id: string): boolean
	local p = panels[id]
	if p and p.Fallback and not openPanels[id] then
		return false
	end
	if p then
		local ok, r = pcall(p.IsOpen)
		if ok then
			return r == true
		end
	end
	return false
end

local function refreshModal()
	local modal = false
	for id in pairs(openPanels) do
		local p = panels[id]
		if not (p and p.NonModal) then
			modal = true
			break
		end
	end
	HudLayout.SetFlag("Modal", modal)
end

--[[ Register once in Init. isOpen: is the panel showing now; close: hide it (it should call PanelClosed).
	opts.Fallback (UIController only): a stand-in registration; a real RegisterPanel for the same id replaces it
	and it is never closed on isOpen() alone (see panelReportsOpen). ]]
function HudLayout.RegisterPanel(id: string, isOpen: () -> boolean, close: () -> (), opts: PanelOpts?)
	local fallback = opts ~= nil and opts.Fallback == true
	local cur = panels[id]
	if fallback and cur and not cur.Fallback then
		return -- the panel registered itself: keep that
	end
	local nonModal = if opts ~= nil and opts.NonModal ~= nil then opts.NonModal == true else (cur ~= nil and cur.NonModal)
	panels[id] = { IsOpen = isOpen, Close = close, Fallback = fallback, NonModal = nonModal }
	refreshModal()
end

--[[ Increments on every PanelOpened / PanelClosed call. UIController compares it around an opener to tell
	whether the panel reported itself (then it does nothing) or needs the fallback sync. ]]
function HudLayout.PanelSerial(): number
	return panelSerial
end

--[[ true once RegisterPanel(id, ...) ran (UIController registers the panels a controller did not register itself). ]]
function HudLayout.HasPanel(id: string): boolean
	return panels[id] ~= nil
end

--[[ Call from the panel's setOpen(true). Closes every other open panel (HudConfig.Context.ModalExclusive). ]]
function HudLayout.PanelOpened(id: string)
	panelSerial += 1
	local was = openPanels[id] == true
	openPanels[id] = true
	lastOpened = id
	if HudConfig.Context.ModalExclusive ~= false and not closingOthers then
		closingOthers = true
		for otherId, p in pairs(panels) do
			if otherId ~= id and (openPanels[otherId] or panelReportsOpen(otherId)) then
				local ok, err = pcall(function(): string?
					p.Close()
					return nil
				end)
				if not ok then
					warn("[HudLayout] closing panel", otherId, "failed:", err)
				end
				if openPanels[otherId] then
					openPanels[otherId] = nil
					firePanel(otherId, false)
				end
			end
		end
		closingOthers = false
	end
	refreshModal()
	if not was then
		firePanel(id, true)
	end
end

--[[ Call from the panel's setOpen(false) / close path. ]]
function HudLayout.PanelClosed(id: string)
	panelSerial += 1
	local was = openPanels[id] == true
	openPanels[id] = nil
	if lastOpened == id then
		lastOpened = next(openPanels)
	end
	refreshModal()
	if was then
		firePanel(id, false)
	end
end

function HudLayout.IsPanelOpen(id: string): boolean
	return openPanels[id] == true
end

function HudLayout.OpenPanelId(): string?
	if lastOpened and openPanels[lastOpened] then
		return lastOpened
	end
	return next(openPanels)
end

--[[ Close every open registered panel (Escape, tapping the dim, death...). ]]
function HudLayout.CloseAllPanels()
	for id, p in pairs(panels) do
		if openPanels[id] or panelReportsOpen(id) then
			local ok, err = pcall(function(): string?
				p.Close()
				return nil
			end)
			if not ok then
				warn("[HudLayout] closing panel", id, "failed:", err)
			end
			HudLayout.PanelClosed(id)
		end
	end
end

-- Safety net: a REGISTERED panel whose isOpen() says closed while the registry still lists it open (a close path
-- that forgot PanelClosed — e.g. the panel's own X button) would leave Modal on, and Modal hides the hotbar, the
-- prompt lane and BUY. Two sweeps in a row (~1 s) clear it.
local STALE_SWEEP_SECONDS = 0.5
local staleSweeps: { [string]: number } = {}
local function sweepStalePanels()
	local stale: { string } = {}
	for id in pairs(openPanels) do
		if panels[id] and not panelReportsOpen(id) then
			local n = (staleSweeps[id] or 0) + 1
			staleSweeps[id] = n
			if n >= 2 then
				table.insert(stale, id)
			end
		else
			staleSweeps[id] = nil
		end
	end
	for id in pairs(staleSweeps) do
		if not openPanels[id] then
			staleSweeps[id] = nil
		end
	end
	for _, id in ipairs(stale) do
		staleSweeps[id] = nil
		HudLayout.PanelClosed(id)
	end
end

---------------------------------------------------------------------------------------------------------------
-- rail badges, cash float, named rects, reserved regions, action lane
---------------------------------------------------------------------------------------------------------------

local badges: { [string]: string? } = {}

--[[ Rail tile badge: "!" (gold ready style), a count ("3"), or nil / "" / "0" to clear. HUDController draws
	it (BadgeChanged); anyone may set it, before or after the HUD exists (GetBadge replays the state). ]]
function HudLayout.SetBadge(tileId: string, text: string?)
	local t: string? = text
	if t == "" or t == "0" then
		t = nil
	end
	if badges[tileId] == t then
		return
	end
	badges[tileId] = t
	fireBadge(tileId, t)
end

function HudLayout.GetBadge(tileId: string): string?
	return badges[tileId]
end

--[[ "+$141" at the cash pill (negative = spend float). Merging / rate limits are HUDController's (HudConfig.CashFloat). ]]
function HudLayout.CashFloat(amount: number)
	if typeof(amount) ~= "number" or amount ~= amount or amount == 0 or math.abs(amount) == math.huge then
		return
	end
	fireCash(amount)
end

local rects: { [string]: GuiObject } = {}

--[[ Publish a HUD piece's rect under a name ("Rail", "CashPill", "Hotbar", "ActionLane", "Compass", "ArmyTile"...). ]]
function HudLayout.SetRect(name: string, obj: GuiObject)
	rects[name] = obj
end

--[[ (AbsolutePosition, AbsoluteSize) of the named piece; zeros when unknown or not parented. ]]
function HudLayout.GetRect(name: string): (Vector2, Vector2)
	local obj = rects[name]
	if obj and obj.Parent then
		return obj.AbsolutePosition, obj.AbsoluteSize
	end
	return Vector2.zero, Vector2.zero
end

--[[
	Reserved bottom-right rect in real px (AbsolutePosition space): "CombatTouch", "CombatDesktop", or "Combat"
	(= the one for this device). Width/Height v × Scale(), floored by MinWidthPx/MinHeightPx so it always holds
	VehicleDriveClient's ▲▼ column. 844x390: x ≥ 594, y ≥ 168. 1280x720: x ≥ 974, y ≥ 585.
]]
function HudLayout.Reserve(name: string): Rect
	local key = name
	if key == "Combat" then
		key = if HudLayout.IsTouch() then "CombatTouch" else "CombatDesktop"
	end
	local r = (HudConfig.Reserve :: any)[key]
	if type(r) ~= "table" or type(r.Width) ~= "number" or type(r.Height) ~= "number" then
		warnOnce("reserve:" .. name, "unknown reserve", name)
		return Rect.new(0, 0, 0, 0)
	end
	local cx, cy, cw, ch = contentRect()
	local s = HudLayout.Scale()
	local w = math.min(cw, math.max(r.Width * s, tonumber(r.MinWidthPx) or 0))
	local h = math.min(ch, math.max(r.Height * s, tonumber(r.MinHeightPx) or 0))
	return Rect.new(cx + cw - w, cy + ch - h, cx + cw, cy + ch)
end

--[[ Bottom edge of the action lane (prompt pills, BUY), in v above the content bottom: 100 touch / 86 desktop. ]]
function HudLayout.ActionLaneBottomV(): number
	local slot = if HudLayout.IsTouch() then HudConfig.Hotbar.Slot else HudConfig.Hotbar.SlotDesktop
	return HudConfig.Hotbar.Bottom + slot + HudConfig.Health.GapAboveHotbar + HudConfig.Health.Height + HudConfig.ActionLane.Gap
end

--[[ Fire one of HudLayout.Signals (e.g. Emit("CompassTapped") from CompassController). ]]
function HudLayout.Emit(signalName: string, ...: any)
	local f = emitters[signalName]
	if f then
		f(...)
	else
		warnOnce("emit:" .. signalName, "unknown signal", signalName)
	end
end

--[[ Studio + touch only: warn when a tappable renders under HudConfig.Scale.TouchMinPx real px. ]]
function HudLayout.AssertTouchTarget(obj: GuiObject, label: string?)
	if not (RunService:IsStudio() and HudLayout.IsTouch()) then
		return
	end
	task.defer(function()
		local sz = obj.AbsoluteSize
		local minPx = HudConfig.Scale.TouchMinPx
		if obj.Parent and (sz.X < minPx - 0.5 or sz.Y < minPx - 0.5) then
			warn(string.format("[HudLayout] touch target %s is %.0fx%.0f px (< %d)", label or obj:GetFullName(), sz.X, sz.Y, minPx))
		end
	end)
end

---------------------------------------------------------------------------------------------------------------
-- viewport / camera / topbar / character watchers
---------------------------------------------------------------------------------------------------------------

local layoutQueued = false

onLayoutChanged = function()
	local s = HudLayout.Scale()
	for sc in pairs(trackedScales) do
		if sc.Parent then
			if sc.Scale ~= s then
				sc.Scale = s
			end
		else
			trackedScales[sc] = nil
		end
	end
	for screen, f in pairs(topbarAreas) do
		if f.Parent == screen then
			placeTopbarArea(screen, f)
		else
			topbarAreas[screen] = nil
		end
	end
	queueStack()
	if not layoutQueued then
		layoutQueued = true
		task.defer(function()
			layoutQueued = false
			fireLayout()
		end)
	end
end

local camConn: RBXScriptConnection? = nil
local function bindCamera()
	if camConn then
		camConn:Disconnect()
		camConn = nil
	end
	local cam = Workspace.CurrentCamera
	if cam then
		camConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(onLayoutChanged)
	end
	onLayoutChanged()
end

local humConns: { RBXScriptConnection } = {}
local function clearHumanoid()
	for _, c in ipairs(humConns) do
		c:Disconnect()
	end
	table.clear(humConns)
end

local function drivingSeat(seat: Instance?): boolean
	return seat ~= nil and seat:IsA("VehicleSeat")
end

local function bindHumanoid(hum: Humanoid)
	HudLayout.SetFlag("Dead", hum.Health <= 0)
	HudLayout.SetFlag("Driving", drivingSeat(hum.SeatPart))
	table.insert(humConns, hum.Died:Connect(function()
		HudLayout.SetFlag("Dead", true)
		HudLayout.SetFlag("Driving", false)
	end))
	table.insert(humConns, hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
		HudLayout.SetFlag("Driving", drivingSeat(hum.SeatPart))
	end))
end

local function bindCharacter(char: Model)
	clearHumanoid()
	HudLayout.SetFlag("Dead", false)
	HudLayout.SetFlag("Driving", false)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		bindHumanoid(hum)
		return
	end
	local conn: RBXScriptConnection? = nil
	conn = char.ChildAdded:Connect(function(c: Instance)
		if c:IsA("Humanoid") then
			if conn then
				conn:Disconnect()
			end
			bindHumanoid(c)
		end
	end)
	if conn then
		table.insert(humConns, conn)
	end
end

local started = false
local playerBound = false

local function bindPlayer()
	if playerBound then
		return
	end
	local lp = Players.LocalPlayer
	if not lp then
		return
	end
	playerBound = true
	lp.CharacterAdded:Connect(bindCharacter)
	lp.CharacterRemoving:Connect(function()
		clearHumanoid()
		HudLayout.SetFlag("Driving", false)
	end)
	if lp.Character then
		bindCharacter(lp.Character)
	end
end

--[[ Idempotent; also runs on require. Safe to call from any controller's Init. Never yields. ]]
function HudLayout.Init()
	bindPlayer()
	if started then
		return
	end
	started = true
	local ok, err = pcall(function()
		Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
		bindCamera()
	end)
	if not ok then
		warnOnce("camera", "camera watch failed:", err)
	end
	pcall(function()
		GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(onLayoutChanged)
	end)
	-- key hints follow the device the player is using now (PreferredInput; LastInputType as the fallback)
	checkInputMode()
	pcall(function()
		UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(checkInputMode)
	end)
	pcall(function()
		UserInputService.LastInputTypeChanged:Connect(function()
			if readPreferredInput() == nil then
				checkInputMode()
			end
		end)
	end)
	pcall(function()
		local acc = 0
		RunService.Heartbeat:Connect(function(dt: number)
			acc += dt
			if acc >= STALE_SWEEP_SECONDS then
				acc = 0
				sweepStalePanels()
			end
		end)
	end)
end

-- test hook (headless harness): force the touch / desktop layout; nil = use the device
function HudLayout._SetTouchOverride(value: boolean?)
	touchOverride = value
	onLayoutChanged()
end

-- test hook (headless harness): force key hints on / off; nil = use the device
function HudLayout._SetKeyPrefOverride(value: boolean?)
	keyPrefOverride = value
	checkInputMode()
end

HudLayout.Init()

return HudLayout
