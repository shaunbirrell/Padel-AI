--!strict
--[[ Phase 6 — Missions UI + daily reward claim ]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)
local Types = require(Shared.Types)
local DailyRewardConfig = require(Shared.Configs.DailyRewardConfig)

local MissionController = {}

local player = Players.LocalPlayer
local menuOpen = false
local screenGui: ScreenGui? = nil
local listFrame: ScrollingFrame? = nil
local dailyBtn: TextButton? = nil
local dailyInfo: TextLabel? = nil
local state: Types.MissionStatePayload? = nil

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function refresh()
	if not listFrame then
		return
	end
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("Frame") or (child:IsA("TextLabel") and child.Name == "EmptyState") then
			child:Destroy()
		end
	end
	if not state then
		UIUtil.EmptyState(listFrame, "Loading missions… stand by for server sync.", 0)
		return
	end
	local layout = listFrame:FindFirstChildOfClass("UIListLayout")
	if not layout then
		local l = Instance.new("UIListLayout")
		l.Padding = UDim.new(0, 6)
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.Parent = listFrame
	end

	if #state.Daily == 0 then
		UIUtil.EmptyState(listFrame, "No daily missions right now — check back after UTC midnight refresh.", 0)
	end

	for i, mission in ipairs(state.Daily) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 72)
		row.BackgroundColor3 = Constants.Colors.Background
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.Parent = listFrame
		corner(row, 6)

		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Position = UDim2.fromOffset(8, 4)
		title.Size = UDim2.new(1, -100, 0, 20)
		title.Font = Enum.Font.GothamBold
		title.TextSize = 14
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextColor3 = Constants.Colors.Text
		title.Text = mission.DisplayName
		title.Parent = row

		local desc = Instance.new("TextLabel")
		desc.BackgroundTransparency = 1
		desc.Position = UDim2.fromOffset(8, 24)
		desc.Size = UDim2.new(1, -100, 0, 18)
		desc.Font = Enum.Font.Gotham
		desc.TextSize = 11
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextColor3 = Constants.Colors.Muted
		desc.Text = mission.Description
		desc.TextTruncate = Enum.TextTruncate.AtEnd
		desc.Parent = row

		local prog = Instance.new("TextLabel")
		prog.BackgroundTransparency = 1
		prog.Position = UDim2.fromOffset(8, 46)
		prog.Size = UDim2.new(1, -100, 0, 18)
		prog.Font = Enum.Font.GothamMedium
		prog.TextSize = 12
		prog.TextXAlignment = Enum.TextXAlignment.Left
		prog.TextColor3 = Constants.Colors.XP
		prog.Text = string.format("%d / %d  ·  $%d + %dXP", mission.Progress, mission.Target, mission.RewardCash, mission.RewardXP)
		prog.Parent = row

		local btn = Instance.new("TextButton")
		btn.AnchorPoint = Vector2.new(1, 0.5)
		btn.Position = UDim2.new(1, -8, 0.5, 0)
		btn.Size = UDim2.fromOffset(88, 44)
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 12
		btn.TextColor3 = Constants.Colors.Text
		btn.BorderSizePixel = 0
		corner(btn, 6)
		btn.Parent = row

		if mission.Claimed then
			btn.Text = "DONE"
			btn.BackgroundColor3 = Color3.fromRGB(50, 55, 60)
			btn.Active = false
		elseif mission.Complete then
			btn.Text = "CLAIM"
			btn.BackgroundColor3 = Constants.Colors.Accent
			btn.MouseButton1Click:Connect(function()
				Remotes.GetEvent(Constants.RemoteNames.RequestClaimMission):FireServer(mission.Id)
			end)
		else
			btn.Text = "…"
			btn.BackgroundColor3 = Color3.fromRGB(45, 50, 55)
			btn.Active = false
		end
	end

	if dailyInfo and state.DailyLogin then
		local d = state.DailyLogin
		local reward = DailyRewardConfig.Rewards[d.NextDay]
		local rewardText = if reward then string.format("$%d", reward.Cash) else ""
		if d.AlreadyClaimedToday then
			dailyInfo.Text = string.format("Daily streak: Day %d (claimed)", d.Streak)
			if dailyBtn then
				dailyBtn.Text = "CLAIMED"
				dailyBtn.BackgroundColor3 = Color3.fromRGB(50, 55, 60)
				dailyBtn.Active = false
			end
		else
			dailyInfo.Text = string.format("Claim Day %d reward %s", d.NextDay, rewardText)
			if dailyBtn then
				dailyBtn.Text = "CLAIM DAILY"
				dailyBtn.BackgroundColor3 = Constants.Colors.Gold
				dailyBtn.TextColor3 = Color3.fromRGB(30, 30, 20)
				dailyBtn.Active = true
			end
		end
	end
end

local function setOpen(open: boolean)
	menuOpen = open
	if screenGui then
		local panel = screenGui:FindFirstChild("Panel")
		if panel and panel:IsA("GuiObject") then
			panel.Visible = open
		end
	end
	if open then
		refresh()
	end
end

function MissionController.Init()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireMissions"
	screen.Parent = player:WaitForChild("PlayerGui")
	UIUtil.PrepareScreen(screen, false)
	screenGui = screen

	local toggle = Instance.new("TextButton")
	toggle.Name = "MissionsToggle"
	toggle.AnchorPoint = Vector2.new(0, 1)
	toggle.Position = UDim2.new(0, 16, 1, -16)
	toggle.Size = UDim2.fromOffset(110, 44)
	toggle.BackgroundColor3 = Constants.Colors.Panel
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 14
	toggle.TextColor3 = Constants.Colors.Text
	toggle.Text = "MISSIONS"
	toggle.BorderSizePixel = 0
	corner(toggle, 8)
	toggle.Parent = screen
	toggle.MouseButton1Click:Connect(function()
		setOpen(not menuOpen)
	end)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(420, 380)
	panel.BackgroundColor3 = Constants.Colors.Panel
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screen
	corner(panel, 10)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -80, 0, 28)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Constants.Colors.Text
	title.Text = "Daily Missions"
	title.Parent = panel

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 10)
	close.Size = UDim2.fromOffset(32, 28)
	close.BackgroundColor3 = Constants.Colors.Background
	close.Font = Enum.Font.GothamBold
	close.Text = "X"
	close.TextColor3 = Constants.Colors.Text
	close.BorderSizePixel = 0
	corner(close, 6)
	close.Parent = panel
	close.MouseButton1Click:Connect(function()
		setOpen(false)
	end)

	local dailyRow = Instance.new("Frame")
	dailyRow.Position = UDim2.fromOffset(12, 48)
	dailyRow.Size = UDim2.new(1, -24, 0, 44)
	dailyRow.BackgroundColor3 = Constants.Colors.Background
	dailyRow.BorderSizePixel = 0
	corner(dailyRow, 6)
	dailyRow.Parent = panel

	local info = Instance.new("TextLabel")
	info.BackgroundTransparency = 1
	info.Position = UDim2.fromOffset(10, 4)
	info.Size = UDim2.new(1, -120, 1, -8)
	info.Font = Enum.Font.Gotham
	info.TextSize = 13
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.TextColor3 = Constants.Colors.Text
	info.Text = "Daily reward"
	info.Parent = dailyRow
	dailyInfo = info

	local dBtn = Instance.new("TextButton")
	dBtn.AnchorPoint = Vector2.new(1, 0.5)
	dBtn.Position = UDim2.new(1, -8, 0.5, 0)
	dBtn.Size = UDim2.fromOffset(110, 44)
	dBtn.Font = Enum.Font.GothamBold
	dBtn.TextSize = 11
	dBtn.Text = "CLAIM DAILY"
	dBtn.TextColor3 = Color3.fromRGB(30, 30, 20)
	dBtn.BackgroundColor3 = Constants.Colors.Gold
	dBtn.BorderSizePixel = 0
	corner(dBtn, 6)
	dBtn.Parent = dailyRow
	dailyBtn = dBtn
	dBtn.MouseButton1Click:Connect(function()
		Remotes.GetEvent(Constants.RemoteNames.RequestClaimDailyReward):FireServer()
	end)

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(12, 100)
	list.Size = UDim2.new(1, -24, 1, -112)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel
	listFrame = list

	Remotes.GetEvent(Constants.RemoteNames.MissionStateUpdate).OnClientEvent:Connect(function(payload: Types.MissionStatePayload)
		state = payload
		if menuOpen then
			refresh()
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then
			return
		end
		if input.KeyCode == Enum.KeyCode.M then
			setOpen(not menuOpen)
		end
	end)
end

return MissionController
