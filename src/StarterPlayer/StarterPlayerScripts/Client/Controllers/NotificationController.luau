--!strict
--[[ Toast stack with fade-in, type colors, and capped stacking.
	P0: high-contrast Success/Collect fills (Purchase SUCCESSFUL / Collected readability).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local NotificationConfig = require(Shared.Configs.NotificationConfig)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)

local AudioController = require(script.Parent.Parent.Modules.AudioController)

local NotificationController = {}

local player = Players.LocalPlayer
local stack: Frame? = nil

local TYPE_PREFIX = {
	Info = "ℹ ",
	Success = "✓ ",
	Collect = "$ ",
	Warn = "! ",
	Error = "✕ ",
	Reward = "★ ",
}

-- Marker for BuyPathStatic / QA: Purchase SUCCESSFUL toast uses Success type styling below
local HIGH_CONTRAST_SUCCESS = true

function NotificationController.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WarEmpireNotifications"
	gui.DisplayOrder = 70 -- above modal panels (60)
	gui.Parent = player:WaitForChild("PlayerGui")
	UIUtil.PrepareScreen(gui, false)

	local frame = Instance.new("Frame")
	frame.Name = "Stack"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 72)
	frame.Size = UDim2.fromOffset(380, 260)
	frame.BackgroundTransparency = 1
	frame.Active = false -- never block HUD / dock clicks
	frame.Parent = gui
	stack = frame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	Remotes.GetEvent(Constants.RemoteNames.Notification).OnClientEvent:Connect(function(payload: any)
		NotificationController.Show(payload.Message or "", payload.Type or "Info", payload.Duration)
	end)
end

function NotificationController.Show(message: string, notifType: string, duration: number?)
	if not stack then
		return
	end
	AudioController.PlayNotification()
	local typeDef = NotificationConfig.Types[notifType] or NotificationConfig.Types.Info
	local prefix = TYPE_PREFIX[notifType] or ""
	local isPunchy = HIGH_CONTRAST_SUCCESS and (notifType == "Success" or notifType == "Collect")

	local toast = Instance.new("Frame")
	toast.Name = "Toast"
	toast.Size = UDim2.fromOffset(if isPunchy then 360 else 340, if isPunchy then 52 else 44)
	-- High-contrast fill for Success/Collect (dark green plate + bright stroke)
	if isPunchy and typeof((typeDef :: any).Fill) == "Color3" then
		toast.BackgroundColor3 = (typeDef :: any).Fill
		toast.BackgroundTransparency = 0.05
	else
		toast.BackgroundColor3 = Constants.Colors.Panel
		toast.BackgroundTransparency = 0.05
	end
	toast.BorderSizePixel = 0
	toast.LayoutOrder = os.clock() * 1000
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = toast

	local stroke = Instance.new("UIStroke")
	stroke.Color = typeDef.Color
	stroke.Thickness = if isPunchy then 3 else 2
	stroke.Parent = toast

	local accent = Instance.new("Frame")
	accent.Size = UDim2.new(0, if isPunchy then 6 else 4, 1, 0)
	accent.BackgroundColor3 = typeDef.Color
	accent.BorderSizePixel = 0
	accent.Parent = toast
	local ac = Instance.new("UICorner")
	ac.CornerRadius = UDim.new(0, 8)
	ac.Parent = accent

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(16, 0)
	label.Size = UDim2.new(1, -24, 1, 0)
	label.Font = if isPunchy then Enum.Font.GothamBold else Enum.Font.GothamMedium
	label.TextSize = if isPunchy then 16 else 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = if isPunchy then Color3.fromRGB(230, 255, 235) else Constants.Colors.Text
	label.Text = prefix .. message
	label.TextTransparency = 1
	label.Parent = toast

	toast.BackgroundTransparency = 1
	stroke.Transparency = 1
	toast.Parent = stack

	-- Cap stack
	local kids = stack:GetChildren()
	local count = 0
	local oldest: Frame? = nil
	for _, k in ipairs(kids) do
		if k:IsA("Frame") and k.Name == "Toast" then
			count += 1
			if not oldest or k.LayoutOrder < oldest.LayoutOrder then
				oldest = k
			end
		end
	end
	if count > NotificationConfig.MaxStacked and oldest then
		oldest:Destroy()
	end

	local targetBg = if isPunchy then 0.02 else 0.05
	local fadeIn = TweenService:Create(toast, TweenInfo.new(0.18), { BackgroundTransparency = targetBg })
	local strokeIn = TweenService:Create(stroke, TweenInfo.new(0.18), { Transparency = 0 })
	local textIn = TweenService:Create(label, TweenInfo.new(0.18), { TextTransparency = 0 })
	fadeIn:Play()
	strokeIn:Play()
	textIn:Play()

	task.delay(duration or NotificationConfig.DefaultDuration, function()
		if not toast.Parent then
			return
		end
		local tw = TweenService:Create(toast, TweenInfo.new(0.28), { BackgroundTransparency = 1 })
		local tw2 = TweenService:Create(label, TweenInfo.new(0.28), { TextTransparency = 1 })
		local tw3 = TweenService:Create(stroke, TweenInfo.new(0.28), { Transparency = 1 })
		tw:Play()
		tw2:Play()
		tw3:Play()
		tw.Completed:Wait()
		toast:Destroy()
	end)
end

return NotificationController
