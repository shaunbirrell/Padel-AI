--!strict
--[[
	Army popover (v70 "clean screen", spec §3.8) — squad ORDERS Follow / Attack / Hold / Retreat.

	  * Never auto-shown. The rail's Army tile (UIController → OrdersController.Toggle) and Y (HudConfig.Keys.Army,
	    was A = strafe-left) toggle it. It sits right of the Army tile (AnchorPoint 0,0.5 at tile right +
	    OrdersConfig.Walkie.GapFromTile, tile centre), clamped to the safe area.
	  * Contents: "ARMY 5/20" + ✕ (touch hit ≥ 44 px), a 2×2 order grid (hotkey order 1 ATTACK · 2 HOLD ·
	    3 FOLLOW · 4 RETREAT, the active order highlighted), "MANAGE ARMY ▸" → ArmyController.Open.
	  * A Modal panel (HudLayout id "Orders"): exclusive with the other panels; tapping outside closes it.
	  * While open: HudLayout flag "OrdersOpen" → 1-4 are order hotkeys (CombatController leaves them alone).
	  * T cycles the order at any time; with the popover closed a local Info toast "Squad: FOLLOW" confirms it
	    (the server's own "Squad: X" echo is dropped by HudConfig.Toast.Drop).
	Server-authoritative: this only fires RequestSquadOrder(orderId).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)
local OrdersConfig = require(Shared.Configs.OrdersConfig)
local HudConfig = require(Shared.Configs.HudConfig)

local HudLayout = require(script.Parent.Parent.Modules.HudLayout)
local HudIcons = require(script.Parent.Parent.Modules.HudIcons)
local PanelShell = require(script.Parent.Parent.Modules.PanelShell)
local AudioController = require(script.Parent.Parent.Modules.AudioController)

local NotificationController = require(script.Parent.NotificationController)
local ArmyController = require(script.Parent.ArmyController)

local OrdersController = {}

local PANEL_ID = "Orders"
local WALKIE = OrdersConfig.Walkie

local player = Players.LocalPlayer
local isTouch = UserInputService.TouchEnabled
local screenGui: ScreenGui? = nil
local panel: Frame? = nil
local titleLabel: TextLabel? = nil
local shell: PanelShell.Shell? = nil
local orderButtons: { [string]: TextButton } = {}
local currentOrder: string = OrdersConfig.DefaultOrder or "Follow"
local soldierCount = 0
local maxSoldiers = 0
local open = false

-- grid order = hotkey order (1-4)
local ORDER_DEFS = {
	{ Id = "Attack", Label = "ATTACK", Key = "1" },
	{ Id = "Hold", Label = "HOLD", Key = "2" },
	{ Id = "Follow", Label = "FOLLOW", Key = "3" },
	{ Id = "Retreat", Label = "RETREAT", Key = "4" },
}

-- 1-4 issue orders ONLY while the popover is open (HudLayout flag "OrdersOpen"); otherwise they draw weapons
local HOTKEY_ORDERS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.One] = "Attack",
	[Enum.KeyCode.Two] = "Hold",
	[Enum.KeyCode.Three] = "Follow",
	[Enum.KeyCode.Four] = "Retreat",
}

local HOTKEY_CYCLE = { "Attack", "Hold", "Follow", "Retreat" }
local CYCLE_KEY: Enum.KeyCode = HudConfig.Keys.OrdersCycle or Enum.KeyCode.T
local TOGGLE_KEY: Enum.KeyCode = HudConfig.Keys.Army or Enum.KeyCode.Y

local function labelOf(orderId: string): string
	for _, d in ipairs(ORDER_DEFS) do
		if d.Id == orderId then
			return d.Label
		end
	end
	return string.upper(orderId)
end

local function borderStroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color
	s.Thickness = thickness
	s.Parent = parent
	return s
end

local function refresh()
	if titleLabel then
		titleLabel.Text = if maxSoldiers > 0
			then string.format("ARMY %d/%d", soldierCount, maxSoldiers)
			else string.format("ARMY %d", soldierCount)
	end
	for id, btn in pairs(orderButtons) do
		local active = id == currentOrder
		btn.BackgroundColor3 = if active then WALKIE.ActiveBg else WALKIE.CellBg
		local st = btn:FindFirstChildOfClass("UIStroke")
		if st then
			st.Thickness = if active then 2.5 else 1.5
			st.Transparency = if active then 0 else 0.35
		end
		local lab = btn:FindFirstChild("Label")
		if lab and lab:IsA("TextLabel") then
			lab.TextColor3 = if active then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(220, 226, 232)
		end
	end
end

local function fireOrder(orderId: string): boolean
	local flags = OrdersConfig.Orders
	if typeof(flags) == "table" and (flags :: any)[orderId] == false then
		NotificationController.Show("Order disabled", "Warn", 2)
		return false
	end
	-- RequestSquadOrder via the non-blocking helper (polls ≤ 3 s for the remote, never waits forever)
	task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestSquadOrder, orderId)
	currentOrder = orderId
	refresh()
	return true
end

local function cycleOrder()
	if soldierCount <= 0 then
		NotificationController.Show("No soldiers to take ORDERS yet — recruit in the Army panel", "Info", 2.5)
		return
	end
	local idx = table.find(HOTKEY_CYCLE, currentOrder) or 1
	local nextId = HOTKEY_CYCLE[(idx % #HOTKEY_CYCLE) + 1]
	if fireOrder(nextId) and not open then
		NotificationController.Show("Squad: " .. labelOf(nextId), "Info", WALKIE.HotkeyToastSeconds)
	end
end

-- The Army tile's rect (AbsolutePosition space). A UIGridLayout cell reports the rail's own origin until the
-- layout has run (and always in the headless HUD sim, which does not lay out grids): then derive the cell from
-- the rail's grid (vertical fill, FillDirectionMaxCells per column — HUDController.layoutRail).
local function armyTileRect(): (Vector2, Vector2)
	local pos, size = HudLayout.GetRect("ArmyTile")
	local railPos, railSize = HudLayout.GetRect("Rail")
	if size.X <= 0 or railSize.X <= 0 or (pos - railPos).Magnitude > 0.5 then
		return pos, size
	end
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local hud = pg and pg:FindFirstChild("WarEmpireHUD")
	local rail = hud and hud:FindFirstChild("Rail")
	local grid = rail and rail:FindFirstChildOfClass("UIGridLayout")
	if not (rail and grid) then
		return pos, size
	end
	local cells: { GuiObject } = {}
	for _, c in ipairs(rail:GetChildren()) do
		if c:IsA("GuiObject") and c.Visible then
			table.insert(cells, c)
		end
	end
	table.sort(cells, function(a: GuiObject, b: GuiObject): boolean
		return a.LayoutOrder < b.LayoutOrder
	end)
	local tileName = "DockArmy"
	for _, t in ipairs(HudConfig.Rail.Tiles) do
		if t.Id == "Army" then
			tileName = t.Name
		end
	end
	local idx: number? = nil
	for i, c in ipairs(cells) do
		if c.Name == tileName then
			idx = i
		end
	end
	if not idx or idx <= 1 then
		return pos, size
	end
	local perCol = if grid.FillDirectionMaxCells > 0 then grid.FillDirectionMaxCells else #cells
	local col = (idx - 1) // perCol
	local row = (idx - 1) % perCol
	local s = HudLayout.Scale()
	local dx = col * (grid.CellSize.X.Offset + grid.CellPadding.X.Offset) * s
	local dy = row * (grid.CellSize.Y.Offset + grid.CellPadding.Y.Offset) * s
	return railPos + Vector2.new(dx, dy), size
end

-- right of the Army rail tile, vertically centred on the tile, clamped to the safe area (v, gui-local)
local function place()
	local gui, p = screenGui, panel
	if not (gui and p) then
		return
	end
	local s = HudLayout.Scale()
	if s <= 0 then
		s = 1
	end
	local size = p.Size
	local w, h = size.X.Offset, size.Y.Offset
	local cv = HudLayout.ContentSizeV()
	local origin = gui.AbsolutePosition
	local tilePos, tileSize = armyTileRect()
	local x: number, y: number
	if tileSize.X > 0 and tileSize.Y > 0 then
		-- clear the WHOLE rail: on short phones (800x360, 667x375) it wraps to 2 columns and the Missions tile in
		-- column 2 would sit on the popover if it only cleared the Army tile's own column
		local right = tilePos.X + tileSize.X
		local railPos, railSize = HudLayout.GetRect("Rail")
		if railSize.X > 0 and railSize.Y > 0 then
			right = math.max(right, railPos.X + railSize.X)
		end
		x = (right - origin.X) / s + WALKIE.GapFromTile
		-- the tile square is tileSize.X tall (the rest of the cell is the label overhang)
		y = (tilePos.Y + tileSize.X / 2 - origin.Y) / s
	else
		local R = HudConfig.Rail
		x = R.Left + (if isTouch then R.Tile else R.TileDesktop) + WALKIE.GapFromTile
		y = cv.Y * R.CenterY
	end
	local m = WALKIE.EdgeMargin
	local over = PanelShell.TouchMinV() / 2 - WALKIE.Pad -- the corner ✕ hangs out by this much (up and right)
	x = math.clamp(x, m, math.max(m, cv.X - w - over - m))
	local yMin = h / 2 + over + m
	y = math.clamp(y, yMin, math.max(yMin, cv.Y - h / 2 - m))
	p.Position = UDim2.fromOffset(x, y)
end

local function setOpen(value: boolean)
	if value and not OrdersConfig.Enabled then
		return
	end
	open = value
	if value then
		place()
	end
	if panel then
		panel.Visible = value
	end
	HudLayout.SetFlag("OrdersOpen", value)
	refresh()
	local sh = shell
	if sh then
		sh.Sync(value)
	end
end

local function build(screen: ScreenGui)
	-- SizeTouch (216 × 244 v) on phones / tablets, Size (216 × 180 v) with a mouse
	local size = if isTouch then WALKIE.SizeTouch else WALKIE.Size
	local pad = WALKIE.Pad
	local gap = WALKIE.CellGap
	local cellH = if isTouch then math.max(WALKIE.MinTouchPx, PanelShell.TouchMinV()) else WALKIE.CellHeightDesktop
	local manageH = if isTouch then math.max(WALKIE.MinTouchPx, PanelShell.TouchMinV()) else WALKIE.ManageHeightDesktop

	local frame = Instance.new("Frame")
	frame.Name = "Walkie"
	frame.AnchorPoint = Vector2.new(0, 0.5)
	frame.Position = UDim2.fromOffset(HudConfig.Rail.Left + HudConfig.Rail.Tile + WALKIE.GapFromTile, 200)
	frame.Size = size
	frame.BackgroundColor3 = WALKIE.Bg
	frame.BackgroundTransparency = WALKIE.BgTransparency
	frame.BorderSizePixel = 0
	frame.Active = true
	frame.Visible = false
	frame.ZIndex = 2
	frame.Parent = screen
	UIUtil.Corner(frame, 14)
	borderStroke(frame, WALKIE.Accent, 2)
	-- hard cap: the popover never grows past PanelMaxWidth × PanelMaxHeight v
	local sizeCap = Instance.new("UISizeConstraint")
	sizeCap.MaxSize = Vector2.new(WALKIE.PanelMaxWidth, WALKIE.PanelMaxHeight)
	sizeCap.MinSize = Vector2.new(140, 120)
	sizeCap.Parent = frame
	panel = frame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(pad + 6, pad)
	title.Size = UDim2.new(1, -(pad * 2 + 6 + PanelShell.TouchMinV() / 2), 0, WALKIE.TitleHeight)
	title.Font = HudConfig.Fonts.Display
	title.TextSize = WALKIE.TitleSize
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Text = "ARMY"
	title.ZIndex = 3
	title.Parent = frame
	UIUtil.TextOutline(title, 1.5)
	titleLabel = title

	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromOffset(pad, pad + WALKIE.TitleHeight + gap)
	grid.Size = UDim2.new(1, -2 * pad, 0, 2 * cellH + gap)
	grid.ZIndex = 3
	grid.Parent = frame
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.5, -gap / 2, 0, cellH)
	layout.CellPadding = UDim2.fromOffset(gap, gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	for i, def in ipairs(ORDER_DEFS) do
		local btn = Instance.new("TextButton")
		btn.Name = "Order_" .. def.Id
		btn.LayoutOrder = i
		btn.BackgroundColor3 = WALKIE.CellBg
		btn.BorderSizePixel = 0
		btn.AutoButtonColor = true
		btn.Text = ""
		btn.Active = true
		btn.ZIndex = 3
		UIUtil.Corner(btn, 10)
		borderStroke(btn, WALKIE.Accent, 1.5)
		local lab = Instance.new("TextLabel")
		lab.Name = "Label"
		lab.BackgroundTransparency = 1
		lab.Size = UDim2.fromScale(1, 1)
		lab.Font = HudConfig.Fonts.Display
		lab.TextSize = WALKIE.CellTextSize
		lab.TextColor3 = Color3.fromRGB(220, 226, 232)
		lab.Text = def.Label
		lab.ZIndex = 4
		lab.Active = false
		lab.Parent = btn
		UIUtil.TextOutline(lab, 1.5)
		if not isTouch then
			-- desktop: the hotkey digit, top-left (like the hotbar)
			local key = Instance.new("TextLabel")
			key.Name = "Key"
			key.BackgroundTransparency = 1
			key.Position = UDim2.fromOffset(6, 2)
			key.Size = UDim2.fromOffset(16, WALKIE.CaptionSize)
			key.Font = HudConfig.Fonts.Body
			key.TextSize = WALKIE.CaptionSize
			key.TextColor3 = Color3.fromRGB(255, 255, 255)
			key.TextTransparency = 0.35
			key.TextXAlignment = Enum.TextXAlignment.Left
			key.Text = def.Key
			key.ZIndex = 4
			key.Active = false
			key.Parent = btn
		end
		btn.Parent = grid
		UIUtil.EnsureMinTouch(btn, if isTouch then WALKIE.MinTouchPx else 44)
		local orderId = def.Id
		btn.Activated:Connect(function()
			pcall(AudioController.PlayClick)
			fireOrder(orderId)
		end)
		orderButtons[def.Id] = btn
	end

	local manage = Instance.new("TextButton")
	manage.Name = "ManageArmy"
	manage.AnchorPoint = Vector2.new(0, 1)
	manage.Position = UDim2.new(0, pad, 1, -pad)
	manage.Size = UDim2.new(1, -2 * pad, 0, manageH)
	manage.BackgroundColor3 = WALKIE.ManageBg
	manage.BorderSizePixel = 0
	manage.AutoButtonColor = true
	manage.Text = ""
	manage.Active = true
	manage.ZIndex = 3
	manage.Parent = frame
	UIUtil.Corner(manage, 10)
	borderStroke(manage, WALKIE.Accent, 2)
	local mLab = Instance.new("TextLabel")
	mLab.Name = "Label"
	mLab.BackgroundTransparency = 1
	mLab.Position = UDim2.fromOffset(12, 0)
	mLab.Size = UDim2.new(1, -44, 1, 0)
	mLab.Font = HudConfig.Fonts.Display
	mLab.TextSize = WALKIE.CellTextSize
	mLab.TextColor3 = Color3.fromRGB(255, 255, 255)
	mLab.TextXAlignment = Enum.TextXAlignment.Left
	mLab.Text = "MANAGE ARMY"
	mLab.ZIndex = 4
	mLab.Active = false
	mLab.Parent = manage
	UIUtil.TextOutline(mLab, 1.5)
	HudIcons.Make("Chevron", manage, {
		Size = UDim2.fromOffset(20, 20),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		ZIndex = 4,
		Color = WALKIE.Accent,
		Fill = WALKIE.ManageBg,
	})
	manage.Activated:Connect(function()
		pcall(AudioController.PlayClick)
		setOpen(false)
		ArmyController.Open()
	end)

	-- ✕ on the popover's top-right corner: the full touch hit area hangs outside the popover (up and right),
	-- so it never covers the order grid
	local close = PanelShell.CloseButton(frame, function()
		pcall(AudioController.PlayClick)
		setOpen(false)
	end, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -pad, 0, pad),
		ZIndex = 6,
		Face = Color3.fromRGB(34, 38, 44),
	})
	local face = close:FindFirstChild("Face")
	if face and face:IsA("Frame") then
		face.Size = UDim2.fromOffset(WALKIE.CloseFace, WALKIE.CloseFace)
		local c = face:FindFirstChildOfClass("UICorner")
		if c then
			c.CornerRadius = UDim.new(0.5, 0)
		end
		local st = face:FindFirstChildOfClass("UIStroke")
		if st then
			st.Color = WALKIE.Accent
			st.Transparency = 0
			st.Thickness = 2
		end
	end
end

function OrdersController.Toggle()
	-- the tap that just closed the popover through its tap-catcher lands on the Army tile too: stay closed
	local sh = shell
	if not open and sh and sh.TapThrough() then
		return
	end
	setOpen(not open)
end

function OrdersController.Open()
	setOpen(true)
end

function OrdersController.Close()
	setOpen(false)
end

function OrdersController.IsOpen(): boolean
	return open
end

--[[ v70: the Army popover no longer follows the Army panel (they are exclusive Modal panels). Kept for callers. ]]
function OrdersController.SetArmyOpen(_isOpen: boolean) end

function OrdersController.Init()
	if not OrdersConfig.Enabled then
		print("[WAR EMPIRE] OrdersController disabled")
		return
	end

	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireOrders"
	-- the one HUD scale + safe area (HudLayout.ApplyScreen); DisplayOrder 52: under the rail (55), which it sits beside
	PanelShell.Screen(screen, HudConfig.DisplayOrder.WarEmpireOrders)
	screen.Parent = player:WaitForChild("PlayerGui")
	screenGui = screen

	build(screen)
	shell = PanelShell.Attach({
		Id = PANEL_ID,
		Screen = screen,
		Panel = panel,
		IsOpen = function(): boolean
			return open
		end,
		Close = function()
			setOpen(false)
		end,
		Dim = false, -- a popover: invisible tap-catcher, no black dim
		TapCloses = true,
	})

	Remotes.BindEvent(Constants.RemoteNames.SquadOrderStateUpdate, function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		if typeof(payload.Order) == "string" then
			currentOrder = payload.Order
		end
		soldierCount = tonumber(payload.Soldiers) or soldierCount
		refresh()
	end)

	Remotes.BindEvent(Constants.RemoteNames.SoldierStateUpdate, function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		if typeof(payload.Soldiers) == "number" then
			soldierCount = payload.Soldiers
		end
		if typeof(payload.MaxSoldiers) == "number" then
			maxSoldiers = payload.MaxSoldiers
		end
		refresh()
	end)

	HudLayout.LayoutChanged:Connect(function()
		if open then
			place()
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
		if gp or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		local key = input.KeyCode
		if key == TOGGLE_KEY then
			setOpen(not open)
			return
		end
		if open then
			local mapped = HOTKEY_ORDERS[key]
			if mapped then
				fireOrder(mapped)
				return
			end
		end
		-- T (Enum.KeyCode.T) cycles Attack → Hold → Follow → Retreat
		if key == CYCLE_KEY then
			cycleOrder()
		end
	end)

	refresh()
	print("[WAR EMPIRE] OrdersController ready (Army popover: tile / Y, orders 1-4 / T)")
end

return OrdersController
