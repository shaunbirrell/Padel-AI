--!strict
--[[
	AirWeaponsClient — fire buttons for armed aircraft (owner request part 2). Numbers: AircraftWeaponConfig.

	  * Shown ONLY while the local player sits in the DriverSeat (WE_SeatRole "Driver") of an aircraft whose
	    VehicleId has a loadout (AircraftWeaponConfig.LoadoutFor) AND the server marked weapons live for this player
	    (Player attribute WE_AirWeaponsLive; the server decides, this module only reads it).
	  * One button per loadout mount, in its own ScreenGui "WarEmpireVehicleWeapons" (no UIScale: sizes are REAL px,
	    Ui.ButtonPx = 64, tablets 72). Button 1 sits LEFT of VehicleDriveClient's ▼ button, bottom-aligned with it,
	    Ui.GapPx apart; button 2 left of button 1. That row is inside the vehicle / combat reserve (bottom-right),
	    above the EXIT pill, at least GapPx from the Roblox jump button (moved up if it would come closer) and far
	    from the thumbstick zone (left 40 %). Without the ▲▼ column: the same row at the right edge.
	  * Hold to fire: a held button sends RequestVehicleFire { M = mount, D = aim, I = input class } at most at
	    min(weapon Rate, Ui.MaxRequestHz) (<= 10 / s). The aim is the camera's centre ray from the aircraft; the server
	    clamps it into the weapon's arc, checks everything and chooses any target. Nothing here decides a hit.
	  * Each button: a 2-4 letter label (GUN / RKT / MSL / BOMB) and the rounds left (aircraft attributes
	    WE_AW_<mount>, written by the server), or the reload countdown (WE_AW_<mount>_Rl). Repaints are coalesced
	    to Ui.RefreshHz (10 Hz); no per-frame work and no tree scans.
	  * Keyboard / gamepad (HudLayout.PrefersKeys, i.e. PreferredInput): the key shows under each button
	    (Ui.Keys) and the keys fire too (ContextActionService, only while active). Touch never sees key names.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local Constants = require(Shared.Constants)
local AircraftWeaponConfig = require(Shared.Configs.AircraftWeaponConfig)

local HudLayout: any = nil
do
	local ok, mod = pcall(function(): any
		return require(script.Parent.HudLayout)
	end)
	if ok then
		HudLayout = mod
	end
end

local CFG = AircraftWeaponConfig
local UI = CFG.Ui
local REFRESH = 1 / math.max(1, UI.RefreshHz)
local ACTIONS = { "WE_AirFireA", "WE_AirFireB" }
local GUI_NAME = "WarEmpireVehicleWeapons"

local AirWeaponsClient = {}

type Btn = { Button: TextButton, Label: TextLabel, Ammo: TextLabel, Hint: TextLabel }

local started = false
local gui: ScreenGui? = nil
local btns: { Btn } = {}
local active = false
local model: Model? = nil
local loadout: { string }? = nil
local held: { [number]: InputObject | boolean | nil } = {}
local looping: { [number]: boolean } = {}
local lastSent: { [number]: number } = {}
local lastAny = -math.huge -- every fire request together stays <= Ui.MaxRequestHz (10 / s; + the 10 Hz drive stream = 20)
local reloadAt: { [string]: number } = {} -- os.clock() when that mount's reload began (display countdown)
local seatConns: { RBXScriptConnection } = {}
local modelConns: { RBXScriptConnection } = {}
local layoutConns: { RBXScriptConnection } = {}
local refreshQueued = false
local aimParams: RaycastParams? = nil
local followLift: () -> ()
-- the Shared/Remotes helper (Remotes.TryGetEvent: bounded, never waits), handed in by VehicleController.Init
local getEvent: ((name: string) -> RemoteEvent?)? = nil

local function lp(): Player
	return Players.LocalPlayer
end

local function prefersKeys(): boolean
	if HudLayout and HudLayout.PrefersKeys then
		local ok, v = pcall(HudLayout.PrefersKeys)
		return ok and v == true
	end
	return false
end

local function disconnectAll(list: { RBXScriptConnection })
	for _, c in ipairs(list) do
		c:Disconnect()
	end
	table.clear(list)
end

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function newLabel(parent: Instance, name: string, size: number): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBold
	t.TextSize = size
	t.TextColor3 = Color3.fromRGB(245, 248, 252)
	t.TextStrokeTransparency = 0.5
	t.Active = false
	t.Parent = parent
	return t
end

-- ── input ─────────────────────────────────────────────────────────────────────────────────────────────────────

local function stillHeld(i: number): boolean
	local h = held[i]
	if h == nil or h == false then
		return false
	end
	if typeof(h) == "Instance" then
		local st = (h :: InputObject).UserInputState
		return st ~= Enum.UserInputState.End and st ~= Enum.UserInputState.Cancel
	end
	return true
end

local function inputClass(): string
	if not prefersKeys() then
		return "Touch"
	end
	local ok, t = pcall(function(): any
		return UserInputService:GetLastInputType()
	end)
	if ok and typeof(t) == "EnumItem" and string.sub((t :: EnumItem).Name, 1, 7) == "Gamepad" then
		return "Gamepad"
	end
	return "KeyboardAndMouse"
end

-- the camera's centre ray from the aircraft (server clamps it into the weapon arc)
local function aimDir(m: Model): Vector3
	local chassis = m.PrimaryPart
	local fwd = if chassis then chassis.CFrame.LookVector else Vector3.new(0, 0, -1)
	local cam = Workspace.CurrentCamera
	if chassis == nil or cam == nil then
		return fwd
	end
	local params: RaycastParams
	if aimParams then
		params = aimParams
	else
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		aimParams = params
	end
	local char = lp().Character
	params.FilterDescendantsInstances = if char then { m, char } else { m }
	local look = cam.CFrame.LookVector
	local from = cam.CFrame.Position
	local hit = Workspace:Raycast(from, look * 1000, params)
	local at = if hit then hit.Position else from + look * 1000
	local d = at - chassis.Position
	if d.Magnitude < 1 then
		return fwd
	end
	return d.Unit
end

local function ammoOf(mount: string): (number, number)
	local m = model
	local def = CFG.Weapon(mount)
	local size = if def then def.Magazine.Size else 0
	if m == nil then
		return size, 0
	end
	local a = m:GetAttribute(CFG.AmmoAttributePrefix .. mount)
	local r = m:GetAttribute(CFG.AmmoAttributePrefix .. mount .. "_Rl")
	return if typeof(a) == "number" then a else size, if typeof(r) == "number" then r else 0
end

local function tryFire(i: number)
	local m, lo = model, loadout
	if not active or m == nil or lo == nil then
		return
	end
	local mount = lo[i]
	if mount == nil then
		return
	end
	local ammo, rl = ammoOf(mount)
	if rl > 0 or ammo <= 0 then
		return
	end
	local ge = getEvent
	local remote = if ge then ge(Constants.RemoteNames.RequestVehicleFire) else nil
	if remote then
		lastSent[i] = os.clock()
		lastAny = lastSent[i]
		remote:FireServer({ M = mount, D = aimDir(m), I = inputClass() })
	end
end

local function interval(i: number): number
	local lo = loadout
	local def = if lo and lo[i] then CFG.Weapon(lo[i]) else nil
	local rate = if def then math.max(def.Rate, 0.05) else 1
	return math.max(1 / math.max(UI.MaxRequestHz, 1), 1 / rate)
end

local function press(i: number, io: InputObject | boolean)
	held[i] = io
	if looping[i] then
		return
	end
	looping[i] = true
	task.spawn(function()
		local gap = 1 / math.max(UI.MaxRequestHz, 1)
		while active and stillHeld(i) do
			local t = os.clock()
			if t - (lastSent[i] or -math.huge) >= interval(i) - 1e-3 and t - lastAny >= gap - 1e-3 then
				tryFire(i)
			end
			task.wait(gap * 0.5)
		end
		looping[i] = false
	end)
end

local function release(i: number)
	held[i] = nil
end

local function onAction(name: string, state: Enum.UserInputState, _io: InputObject): Enum.ContextActionResult?
	local i = table.find(ACTIONS, name)
	if i == nil or not active or (loadout :: any)[i] == nil then
		return Enum.ContextActionResult.Pass
	end
	if state == Enum.UserInputState.Begin then
		press(i, true)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		release(i)
	end
	return Enum.ContextActionResult.Pass
end

local function bindKeys()
	local hi = Enum.ContextActionPriority.High.Value
	pcall(function()
		ContextActionService:BindActionAtPriority(ACTIONS[1], onAction, false, hi, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonY)
		ContextActionService:BindActionAtPriority(ACTIONS[2], onAction, false, hi, Enum.KeyCode.R, Enum.KeyCode.ButtonX)
	end)
end

local function unbindKeys()
	for _, a in ipairs(ACTIONS) do
		pcall(function()
			ContextActionService:UnbindAction(a)
		end)
	end
end

-- ── gui ───────────────────────────────────────────────────────────────────────────────────────────────────────

local function makeButton(parent: Instance, i: number): Btn
	local b = Instance.new("TextButton")
	b.Name = "Fire" .. (if i == 1 then "A" else "B")
	b.Text = ""
	b.AutoButtonColor = false
	b.Active = true
	b.BackgroundColor3 = Color3.fromRGB(64, 38, 16) -- amber, not the EXIT pill's red
	b.BackgroundTransparency = 0.2
	b.BorderSizePixel = 0
	b.Size = UDim2.fromOffset(UI.ButtonPx, UI.ButtonPx)
	b.Visible = false
	b.Parent = parent
	corner(b, 14)
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(255, 170, 60)
	st.Thickness = 1.5
	st.Transparency = 0.2
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = b
	local label = newLabel(b, "Label", UI.LabelTextPx)
	label.Size = UDim2.new(1, 0, 0.55, 0)
	label.Position = UDim2.fromScale(0, 0.06)
	local ammo = newLabel(b, "Ammo", UI.AmmoTextPx)
	ammo.Size = UDim2.new(1, 0, 0.36, 0)
	ammo.Position = UDim2.fromScale(0, 0.58)
	ammo.TextColor3 = Color3.fromRGB(255, 226, 150)
	local hint = newLabel(parent, "Key" .. (if i == 1 then "A" else "B"), UI.HintTextPx)
	hint.Size = UDim2.fromOffset(UI.ButtonPx, UI.HintTextPx + 4)
	hint.Visible = false
	b.InputBegan:Connect(function(io: InputObject)
		local ut = io.UserInputType
		if ut == Enum.UserInputType.Touch or ut == Enum.UserInputType.MouseButton1 then
			press(i, io)
		end
	end)
	b.InputEnded:Connect(function(io: InputObject)
		if held[i] == io then
			release(i)
		end
	end)
	return { Button = b, Label = label, Ammo = ammo, Hint = hint }
end

local function ensureGui(): ScreenGui?
	if gui and gui.Parent then
		return gui
	end
	local pg = lp():FindFirstChildOfClass("PlayerGui")
	if pg == nil then
		return nil
	end
	local sg = Instance.new("ScreenGui")
	sg.Name = GUI_NAME
	sg.ResetOnSpawn = false
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.IgnoreGuiInset = false -- the same space as WarEmpireVehicleHUD (its ▲▼ column)
	sg.DisplayOrder = 56
	sg.Enabled = true
	btns = { makeButton(sg, 1), makeButton(sg, 2) }
	sg.Parent = pg
	gui = sg
	return sg
end

local function liftButton(name: string): GuiObject?
	local pg = lp():FindFirstChildOfClass("PlayerGui")
	local hud = pg and pg:FindFirstChild("WarEmpireVehicleHUD")
	local frame = hud and hud:FindFirstChild("WE_VehicleControls")
	if frame == nil or not frame:IsA("GuiObject") or not frame.Visible then
		return nil
	end
	local b = frame:FindFirstChild(name)
	if b and b:IsA("GuiObject") and b.Visible and b.AbsoluteSize.X > 0 then
		return b
	end
	return nil
end

local function jumpRect(): (Vector2?, Vector2?)
	local pg = lp():FindFirstChildOfClass("PlayerGui")
	local tg = pg and pg:FindFirstChild("TouchGui")
	local frame = tg and tg:FindFirstChild("TouchControlFrame")
	local jb = frame and frame:FindFirstChild("JumpButton")
	if jb and jb:IsA("GuiObject") and jb.AbsoluteSize.X > 0 then
		return jb.AbsolutePosition, jb.AbsoluteSize
	end
	return nil, nil
end

type Rect = { Pos: Vector2, Size: Vector2 }

-- pure layout (tests): top-left corners of buttons 1..n in this gui's space. Tried in order, the first row that keeps
-- GapPx clear of every `avoid` rect (the jump button, EXIT) and stays right of the thumbstick zone (x >= 40 %) wins:
--   1. left of the ▼ button, bottom-aligned with it (phones: ▲▼ above the jump button, EXIT left of the jump);
--   2. left of the EXIT pill, bottom-aligned with it (EXIT beside ▼: no jump button / "Left" layouts);
--   3. the first row moved up above whatever it touches.
-- No ▼ button (keyboard play): the bottom-right corner, where the column would be.
function AirWeaponsClient.Layout(n: number, viewport: Vector2, down: Rect?, exit: Rect?, avoid: { Rect }?): { Vector2 }
	local size = if math.min(viewport.X, viewport.Y) >= 500 then UI.TabletButtonPx else UI.ButtonPx
	local gap = UI.GapPx
	local blockers: { Rect } = {}
	for _, r: Rect in ipairs(avoid or {}) do
		table.insert(blockers, r)
	end
	if exit then
		table.insert(blockers, exit)
	end
	local function hits(x: number, y: number): Rect?
		local rowLeft = x - (n - 1) * (size + gap)
		for _, r: Rect in ipairs(blockers) do
			local rx0, ry0 = r.Pos.X - gap, r.Pos.Y - gap
			local rx1, ry1 = r.Pos.X + r.Size.X + gap, r.Pos.Y + r.Size.Y + gap
			if rowLeft < rx1 - 1e-6 and x + size > rx0 + 1e-6 and y < ry1 - 1e-6 and y + size > ry0 + 1e-6 then
				return r
			end
		end
		return nil
	end
	local cands: { Vector2 } = {}
	if down then
		table.insert(cands, Vector2.new(down.Pos.X - gap - size, down.Pos.Y + down.Size.Y - size))
	else
		table.insert(cands, Vector2.new(viewport.X - 24 - 60 - gap - size, viewport.Y - 106 - size))
	end
	if exit then
		table.insert(cands, Vector2.new(exit.Pos.X - gap - size, exit.Pos.Y + exit.Size.Y - size))
	end
	local minLeft = viewport.X * 0.4
	local pick: Vector2? = nil
	for _, c in ipairs(cands) do
		if c.X - (n - 1) * (size + gap) >= minLeft and hits(c.X, c.Y) == nil then
			pick = c
			break
		end
	end
	if pick == nil then
		local x, y = cands[1].X, cands[1].Y
		for _ = 1, 4 do
			local r = hits(x, y)
			if r == nil then
				break
			end
			y = r.Pos.Y - gap - size
		end
		pick = Vector2.new(x, y)
	end
	local p = pick :: Vector2
	local out: { Vector2 } = {}
	for i = 1, n do
		table.insert(out, Vector2.new(p.X - (i - 1) * (size + gap), p.Y))
	end
	return out
end

local function layout()
	local sg = gui
	local lo = loadout
	if sg == nil or lo == nil then
		return
	end
	local vp = sg.AbsoluteSize
	if vp.X < 1 then
		local cam = Workspace.CurrentCamera
		vp = if cam then cam.ViewportSize else Vector2.new(844, 390)
	end
	local origin = sg.AbsolutePosition
	local down = liftButton("LiftDown")
	local dRect = if down then { Pos = down.AbsolutePosition - origin, Size = down.AbsoluteSize } else nil
	local avoid: { Rect } = {}
	local jp, js = jumpRect()
	if jp and js then
		table.insert(avoid, { Pos = jp - origin, Size = js })
	elseif HudLayout and HudLayout.IsTouch and HudLayout.IsTouch() then
		-- no TouchGui jump button found (hidden TouchGui / not built yet): keep clear of where Roblox puts it
		local small = math.min(vp.X, vp.Y) <= 500
		local jsz = if small then 70 else 120
		table.insert(avoid, { Pos = Vector2.new(vp.X - (if small then 95 else 170), vp.Y - (if small then 90 else 210)), Size = Vector2.new(jsz, jsz) })
	end
	local exit = liftButton("Exit")
	local eRect = if exit then { Pos = exit.AbsolutePosition - origin, Size = exit.AbsoluteSize } else nil
	local pos = AirWeaponsClient.Layout(#lo, vp, dRect, eRect, avoid)
	local size = if math.min(vp.X, vp.Y) >= 500 then UI.TabletButtonPx else UI.ButtonPx
	for i, b in ipairs(btns) do
		local p = pos[i]
		if p then
			b.Button.Position = UDim2.fromOffset(p.X, p.Y)
			b.Button.Size = UDim2.fromOffset(size, size)
			b.Hint.Position = UDim2.fromOffset(p.X, p.Y - UI.HintTextPx - 6)
			b.Hint.Size = UDim2.fromOffset(size, UI.HintTextPx + 4)
		end
	end
end

local function paint()
	local lo = loadout
	local keys = prefersKeys()
	local padKeys = keys and inputClass() == "Gamepad"
	for i, b in ipairs(btns) do
		local mount = if active and lo then lo[i] else nil
		local def = if mount then CFG.Weapon(mount) else nil
		if mount == nil or def == nil then
			b.Button.Visible = false
			b.Hint.Visible = false
		else
			local ammo, rl = ammoOf(mount)
			b.Button.Visible = true
			b.Label.Text = def.Label
			if rl > 0 then
				local began = reloadAt[mount] or os.clock()
				reloadAt[mount] = began
				local left = math.max(0, math.ceil(rl - (os.clock() - began)))
				b.Ammo.Text = tostring(left) .. "s"
				b.Button.BackgroundTransparency = 0.55
			else
				reloadAt[mount] = nil
				b.Ammo.Text = tostring(math.max(0, math.floor(ammo)))
				b.Button.BackgroundTransparency = 0.2
			end
			local k = if padKeys then UI.Keys.Pad[i] else UI.Keys.Pc[i]
			b.Hint.Text = k or ""
			b.Hint.Visible = keys and k ~= nil
		end
	end
end

local function anyReloading(): boolean
	local lo = loadout
	if lo == nil then
		return false
	end
	for _, mount in ipairs(lo) do
		local _, rl = ammoOf(mount)
		if rl > 0 then
			return true
		end
	end
	return false
end

-- coalesced repaint at <= RefreshHz; keeps ticking only while a reload countdown shows
local function queueRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true
	task.delay(REFRESH, function()
		refreshQueued = false
		paint()
		if active and anyReloading() then
			queueRefresh()
		end
	end)
end

-- ── seat tracking ─────────────────────────────────────────────────────────────────────────────────────────────

-- lay out now and track the ▼ button's moves (bound once per seat, as soon as the button exists)
local liftBound = false
followLift = function()
	if not liftBound then
		local down = liftButton("LiftDown")
		if down then
			liftBound = true
			table.insert(layoutConns, down:GetPropertyChangedSignal("AbsolutePosition"):Connect(layout))
			table.insert(layoutConns, down:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
			table.insert(layoutConns, down:GetPropertyChangedSignal("Visible"):Connect(layout))
		end
	end
	layout()
end

local function deactivate()
	active = false
	model = nil
	loadout = nil
	table.clear(held)
	disconnectAll(modelConns)
	disconnectAll(layoutConns)
	liftBound = false
	unbindKeys()
	paint()
end

local function activate(m: Model, lo: { string })
	if active and model == m then
		return
	end
	deactivate()
	if ensureGui() == nil then
		return
	end
	active = true
	model = m
	loadout = lo
	table.insert(modelConns, m.AttributeChanged:Connect(function(attr: string)
		if string.sub(attr, 1, #CFG.AmmoAttributePrefix) == CFG.AmmoAttributePrefix then
			queueRefresh()
		end
	end))
	local cam = Workspace.CurrentCamera
	if cam then
		table.insert(layoutConns, cam:GetPropertyChangedSignal("ViewportSize"):Connect(layout))
	end
	bindKeys()
	followLift()
	paint()
	-- VehicleDriveClient builds / shows its ▲▼ column on the same seat change: follow it once it is there
	for _, d in ipairs({ 0.25, 1 }) do
		task.delay(d, function()
			if active and model == m then
				followLift()
			end
		end)
	end
end

local function evaluate()
	local char = lp().Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	local m = seat and seat.Parent
	local live = lp():GetAttribute(CFG.LiveAttribute) == true
	if seat and m and m:IsA("Model") and live and seat:GetAttribute("WE_SeatRole") == "Driver" then
		local lo = CFG.LoadoutFor(m:GetAttribute("VehicleId"))
		if lo then
			activate(m, lo)
			-- the ▲▼ column is laid out by VehicleDriveClient on the same seat change: follow it next frame
			task.defer(layout)
			return
		end
	end
	if active then
		deactivate()
	end
end

local function bindCharacter(char: Model)
	disconnectAll(seatConns)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum == nil then
		table.insert(seatConns, char.ChildAdded:Connect(function(c: Instance)
			if c:IsA("Humanoid") then
				bindCharacter(char)
			end
		end))
		return
	end
	table.insert(seatConns, hum:GetPropertyChangedSignal("SeatPart"):Connect(evaluate))
	evaluate()
end

function AirWeaponsClient.Init(tryGetEvent: ((name: string) -> RemoteEvent?)?)
	if tryGetEvent then
		getEvent = tryGetEvent
	end
	if started then
		return
	end
	started = true
	local player = lp()
	ensureGui()
	player:GetAttributeChangedSignal(CFG.LiveAttribute):Connect(evaluate)
	player.CharacterAdded:Connect(bindCharacter)
	player.CharacterRemoving:Connect(function()
		disconnectAll(seatConns)
		deactivate()
	end)
	if player.Character then
		bindCharacter(player.Character)
	end
end

-- tests / harness
function AirWeaponsClient._IsActive(): boolean
	return active
end
function AirWeaponsClient._Evaluate()
	evaluate()
end
function AirWeaponsClient._Relayout()
	layout()
	paint()
end

return AirWeaponsClient
