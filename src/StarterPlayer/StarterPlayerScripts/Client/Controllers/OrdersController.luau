--!strict
--[[
	Squad Orders walkie — Follow / Attack / Hold / Retreat.
	Shows when soldiers > 0 or Army panel is open. Does not own HUD dock.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)
local OrdersConfig = require(Shared.Configs.OrdersConfig)

local NotificationController = require(script.Parent.NotificationController)

local OrdersController = {}

local player = Players.LocalPlayer
local isTouch = UserInputService.TouchEnabled
local screenGui: ScreenGui? = nil
local panel: Frame? = nil
local statusLabel: TextLabel? = nil
local orderButtons: { [string]: TextButton } = {}
local currentOrder = "Follow"
local soldierCount = 0
local fieldUnits = 0
local armyForced = false
local visible = false

local ORDER_DEFS = {
	{ Id = "Follow", Label = "FOLLOW" },
	{ Id = "Attack", Label = "ATTACK" },
	{ Id = "Hold", Label = "HOLD" },
	{ Id = "Retreat", Label = "RETREAT" },
}

local function shouldShow(): boolean
	if not OrdersConfig.Enabled then
		return false
	end
	if armyForced then
		return true
	end
	return soldierCount >= (OrdersConfig.MinSoldiersToShow or 1)
end

local function refreshVisible()
	local show = shouldShow()
	visible = show
	if panel then
		panel.Visible = show
	end
end

local function refreshStatus()
	if statusLabel then
		statusLabel.Text = string.format("%s · %d field · army %d", currentOrder:upper(), fieldUnits, soldierCount)
	end
	for id, btn in pairs(orderButtons) do
		local active = id == currentOrder
		btn.BackgroundColor3 = if active then Constants.Colors.Olive else Constants.Colors.Gunmetal
		btn.TextColor3 = if active then Constants.Colors.GoldBright else Constants.Colors.Text
	end
end

local function fireOrder(orderId: string)
	local flags = OrdersConfig.Orders
	if typeof(flags) == "table" and (flags :: any)[orderId] == false then
		NotificationController.Show("Order disabled", "Warn", 2)
		return
	end
	Remotes.GetEvent(Constants.RemoteNames.RequestSquadOrder):FireServer(orderId)
	currentOrder = orderId
	refreshStatus()
end

function OrdersController.SetArmyOpen(isOpen: boolean)
	armyForced = isOpen == true
	refreshVisible()
end

function OrdersController.Init()
	if not OrdersConfig.Enabled then
		print("[WAR EMPIRE] OrdersController disabled")
		return
	end

	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireOrders"
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = player:WaitForChild("PlayerGui")
	UIUtil.PrepareScreen(screen, true)
	screen.DisplayOrder = 52 -- below HUD dock (55) / Army modal (60); above world
	screenGui = screen

	local walkie = OrdersConfig.Walkie or {}
	local frame = Instance.new("Frame")
	frame.Name = "Walkie"
	frame.AnchorPoint = Vector2.new(0, 1)
	frame.Position = if isTouch then (walkie.PositionTouch or UDim2.new(0, 16, 1, -220)) else (walkie.PositionDesktop or UDim2.new(0, 16, 1, -110))
	frame.Size = walkie.Size or UDim2.fromOffset(200, 168)
	frame.BackgroundColor3 = Constants.Colors.Gunmetal
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = screen
	UIUtil.Corner(frame, 10)
	UIUtil.Stroke(frame, Constants.Colors.Olive, 1.5)
	panel = frame

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(10, 6)
	title.Size = UDim2.new(1, -20, 0, 20)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 14
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Constants.Colors.Gold
	title.Text = "📡 ORDERS"
	title.Parent = frame

	statusLabel = Instance.new("TextLabel")
	statusLabel.BackgroundTransparency = 1
	statusLabel.Position = UDim2.fromOffset(10, 26)
	statusLabel.Size = UDim2.new(1, -20, 0, 16)
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextSize = 11
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextColor3 = Constants.Colors.Muted
	statusLabel.Text = "…"
	statusLabel.Parent = frame

	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromOffset(8, 46)
	grid.Size = UDim2.new(1, -16, 1, -54)
	grid.Parent = frame

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.5, -4, 0.5, -4)
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	for i, def in ipairs(ORDER_DEFS) do
		local btn = Instance.new("TextButton")
		btn.Name = "Order_" .. def.Id
		btn.LayoutOrder = i
		btn.BackgroundColor3 = Constants.Colors.Gunmetal
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 12
		btn.TextColor3 = Constants.Colors.Text
		btn.Text = def.Label
		btn.BorderSizePixel = 0
		btn.AutoButtonColor = true
		UIUtil.Corner(btn, 8)
		UIUtil.Stroke(btn, Constants.Colors.Olive, 1)
		UIUtil.EnsureMinTouch(btn, 44)
		btn.Parent = grid
		btn.Activated:Connect(function()
			fireOrder(def.Id)
		end)
		orderButtons[def.Id] = btn
	end

	Remotes.GetEvent(Constants.RemoteNames.SquadOrderStateUpdate).OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		if typeof(payload.Order) == "string" then
			currentOrder = payload.Order
		end
		soldierCount = tonumber(payload.Soldiers) or soldierCount
		fieldUnits = tonumber(payload.FieldUnits) or 0
		if payload.ShowPanel == false and not armyForced then
			soldierCount = 0
		end
		refreshStatus()
		refreshVisible()
	end)

	Remotes.GetEvent(Constants.RemoteNames.SoldierStateUpdate).OnClientEvent:Connect(function(payload)
		if typeof(payload) == "table" and typeof(payload.Soldiers) == "number" then
			soldierCount = payload.Soldiers
			refreshStatus()
			refreshVisible()
		end
	end)

	refreshStatus()
	refreshVisible()
	print("[WAR EMPIRE] OrdersController ready (walkie Follow/Attack/Hold/Retreat)")
end

return OrdersController
