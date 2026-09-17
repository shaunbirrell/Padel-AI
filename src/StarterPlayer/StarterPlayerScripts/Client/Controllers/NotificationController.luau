--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local NotificationConfig = require(Shared.Configs.NotificationConfig)
local Remotes = require(Shared.Remotes)

local NotificationController = {}

local player = Players.LocalPlayer
local stack: Frame? = nil

function NotificationController.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WarEmpireNotifications"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Name = "Stack"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 100)
	frame.Size = UDim2.fromOffset(320, 200)
	frame.BackgroundTransparency = 1
	frame.Parent = gui
	stack = frame

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = frame

	Remotes.GetEvent(Constants.RemoteNames.Notification).OnClientEvent:Connect(function(payload: any)
		NotificationController.Show(payload.Message or "", payload.Type or "Info", payload.Duration)
	end)
end

function NotificationController.Show(message: string, notifType: string, duration: number?)
	if not stack then
		return
	end
	local typeDef = NotificationConfig.Types[notifType] or NotificationConfig.Types.Info
	local toast = Instance.new("TextLabel")
	toast.Size = UDim2.fromOffset(300, 36)
	toast.BackgroundColor3 = Constants.Colors.Panel
	toast.TextColor3 = Constants.Colors.Text
	toast.Font = Enum.Font.GothamMedium
	toast.TextSize = 14
	toast.Text = message
	toast.BorderSizePixel = 0
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = toast
	local stroke = Instance.new("UIStroke")
	stroke.Color = typeDef.Color
	stroke.Thickness = 2
	stroke.Parent = toast
	toast.Parent = stack

	local kids = stack:GetChildren()
	local count = 0
	for _, k in ipairs(kids) do
		if k:IsA("TextLabel") then
			count += 1
		end
	end
	if count > NotificationConfig.MaxStacked then
		for _, k in ipairs(kids) do
			if k:IsA("TextLabel") then
				k:Destroy()
				break
			end
		end
	end

	task.delay(duration or NotificationConfig.DefaultDuration, function()
		if toast.Parent then
			local tw = TweenService:Create(toast, TweenInfo.new(0.25), { BackgroundTransparency = 1, TextTransparency = 1 })
			tw:Play()
			tw.Completed:Wait()
			toast:Destroy()
		end
	end)
end

return NotificationController
