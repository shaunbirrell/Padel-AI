--!strict
--[[ Army panel — recruit/dismiss soldiers (key A / ARMY button). Server-authoritative. ]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)

local ArmyController = {}

local player = Players.LocalPlayer
local open = false
local screenGui: ScreenGui? = nil
local statusLabel: TextLabel? = nil
local capFill: Frame? = nil
local capLabel: TextLabel? = nil
local armyState: any = nil

local function refreshLabels()
	if not statusLabel then
		return
	end
	if typeof(armyState) ~= "table" then
		statusLabel.Text = "No army data yet — wait for SoldierStateUpdate, or press A after join."
		return
	end
	local count = tonumber(armyState.Soldiers) or 0
	local cap = tonumber(armyState.MaxSoldiers) or 0
	local free = tonumber(armyState.SlotsFree) or math.max(0, cap - count)
	local cost = tonumber(armyState.RecruitCostCash) or 500
	local refundMult = tonumber(armyState.DismissRefundMult) or 0.25
	local barracks = tonumber(armyState.BarracksLevel) or 0
	if count == 0 and barracks == 0 then
		statusLabel.Text = string.format(
			"Army empty — buy Barracks (B) to raise cap.\nBase cap %d · Recruit $%d each\nTip: FILL CAP spends cash up to free slots.",
			cap,
			cost
		)
	else
		local trainTick = tonumber(armyState.TrainingIncomePerTick) or 0
		local trainSec = tonumber(armyState.TrainingIncomePerSec) or 0
		statusLabel.Text = string.format(
			"Soldiers: %d / %d  (%d free)\nBarracks Lv %d\nRecruit $%d each · Dismiss refund %d%%\nTraining Yard: +$%d/tick (~$%.1f/sec)",
			count,
			cap,
			free,
			barracks,
			cost,
			math.floor(refundMult * 100),
			trainTick,
			trainSec
		)
	end
	if capFill and cap > 0 then
		capFill.Size = UDim2.fromScale(math.clamp(count / cap, 0, 1), 1)
		capFill.BackgroundColor3 = if count >= cap then Constants.Colors.Danger else Constants.Colors.Accent
	end
	if capLabel then
		capLabel.Text = string.format("%d / %d", count, cap)
	end
end

local function setOpen(isOpen: boolean)
	open = isOpen
	if screenGui then
		local panel = screenGui:FindFirstChild("Panel")
		if panel and panel:IsA("GuiObject") then
			panel.Visible = isOpen
		end
	end
end

function ArmyController.Init()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireArmy"
	screen.Parent = player:WaitForChild("PlayerGui")
	UIUtil.PrepareScreen(screen, true)
	screen.DisplayOrder = 60 -- above HUD dock (55); panels must not open behind HUD
	screenGui = screen

	local inset = GuiService:GetGuiInset()
	local toggle = Instance.new("TextButton")
	toggle.Name = "ArmyToggle"
	toggle.AnchorPoint = Vector2.new(0, 1)
	toggle.Position = UDim2.new(0, 16, 1, -16 - inset.Y)
	toggle.Size = UDim2.fromOffset(88, 44)
	toggle.BackgroundColor3 = Constants.Colors.Gunmetal
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 13
	toggle.TextColor3 = Constants.Colors.Gold
	toggle.Text = "ARMY"
	toggle.BorderSizePixel = 0
	toggle.Visible = false -- docked in HUD MobileActionBar
	UIUtil.Corner(toggle, 8)
	UIUtil.Stroke(toggle, Constants.Colors.Gold, 1.5)
	toggle.Parent = screen
	toggle.MouseButton1Click:Connect(function()
		setOpen(not open)
	end)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(380, 380)
	panel.BackgroundColor3 = Constants.Colors.Panel
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screen
	UIUtil.Corner(panel, 10)
	UIUtil.Stroke(panel)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -80, 0, 28)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Constants.Colors.Text
	title.Text = "Army"
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
	UIUtil.Corner(close, 6)
	close.Parent = panel
	close.MouseButton1Click:Connect(function()
		setOpen(false)
	end)

	statusLabel = Instance.new("TextLabel")
	statusLabel.BackgroundTransparency = 1
	statusLabel.Position = UDim2.fromOffset(16, 48)
	statusLabel.Size = UDim2.new(1, -32, 0, 88)
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextSize = 14
	statusLabel.TextWrapped = true
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextYAlignment = Enum.TextYAlignment.Top
	statusLabel.TextColor3 = Constants.Colors.Muted
	statusLabel.Text = "..."
	statusLabel.Parent = panel

	-- Cap bar
	local capBg = Instance.new("Frame")
	capBg.Position = UDim2.fromOffset(16, 142)
	capBg.Size = UDim2.new(1, -32, 0, 16)
	capBg.BackgroundColor3 = Constants.Colors.Background
	capBg.BorderSizePixel = 0
	capBg.Parent = panel
	UIUtil.Corner(capBg, 4)

	capFill = Instance.new("Frame")
	capFill.Size = UDim2.fromScale(0, 1)
	capFill.BackgroundColor3 = Constants.Colors.Accent
	capFill.BorderSizePixel = 0
	capFill.Parent = capBg
	UIUtil.Corner(capFill, 4)

	capLabel = Instance.new("TextLabel")
	capLabel.BackgroundTransparency = 1
	capLabel.Size = UDim2.fromScale(1, 1)
	capLabel.Font = Enum.Font.GothamBold
	capLabel.TextSize = 11
	capLabel.TextColor3 = Constants.Colors.Text
	capLabel.Text = "0 / 0"
	capLabel.Parent = capBg

	local function makeBtn(label: string, x: number, y: number, w: number, cb: () -> (), goldAccent: boolean?)
		local b = Instance.new("TextButton")
		b.Position = UDim2.fromOffset(x, y)
		b.Size = UDim2.fromOffset(w, 44)
		b.BackgroundColor3 = Constants.Colors.Gunmetal
		b.Font = Enum.Font.GothamBold
		b.TextSize = 12
		b.TextColor3 = if goldAccent then Constants.Colors.Gold else Constants.Colors.Text
		b.Text = label
		b.BorderSizePixel = 0
		UIUtil.Corner(b, 6)
		UIUtil.Stroke(b, Constants.Colors.Gold, 1.25)
		b.Parent = panel
		b.MouseButton1Click:Connect(cb)
		return b
	end

	local recruit1 = makeBtn("RECRUIT x1 $500", 16, 174, 168, function()
		Remotes.GetEvent(Constants.RemoteNames.RequestRecruitSoldiers):FireServer(1)
	end, true)
	local recruit5 = makeBtn("RECRUIT x5", 192, 174, 168, function()
		Remotes.GetEvent(Constants.RemoteNames.RequestRecruitSoldiers):FireServer(5)
	end, true)
	makeBtn("FILL CAP", 16, 228, 168, function()
		local free = if typeof(armyState) == "table" then tonumber(armyState.SlotsFree) or 0 else 0
		if free > 0 then
			Remotes.GetEvent(Constants.RemoteNames.RequestRecruitSoldiers):FireServer(math.min(free, 50))
		end
	end)
	makeBtn("DISMISS x1", 192, 228, 168, function()
		Remotes.GetEvent(Constants.RemoteNames.RequestDismissSoldiers):FireServer(1)
	end)
	makeBtn("DISMISS x5", 16, 282, 168, function()
		Remotes.GetEvent(Constants.RemoteNames.RequestDismissSoldiers):FireServer(5)
	end)

	-- Keep recruit labels priced
	local prevRefresh = refreshLabels
	refreshLabels = function()
		prevRefresh()
		local cost = if typeof(armyState) == "table" then tonumber(armyState.RecruitCostCash) or 500 else 500
		if recruit1 then
			recruit1.Text = string.format("RECRUIT x1 $%d", cost)
		end
		if recruit5 then
			recruit5.Text = string.format("RECRUIT x5 $%d", cost * 5)
		end
	end

	local note = Instance.new("TextLabel")
	note.BackgroundTransparency = 1
	note.Position = UDim2.fromOffset(16, 336)
	note.Size = UDim2.new(1, -32, 0, 28)
	note.Font = Enum.Font.Gotham
	note.TextSize = 11
	note.TextWrapped = true
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.TextColor3 = Constants.Colors.Muted
	note.Text = "Training Yard pays cash/sec from owned soldiers. Barracks raises cap. Key A."
	note.Parent = panel

	Remotes.GetEvent(Constants.RemoteNames.SoldierStateUpdate).OnClientEvent:Connect(function(payload)
		armyState = payload
		refreshLabels()
	end)

	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then
			return
		end
		if input.KeyCode == Enum.KeyCode.A then
			setOpen(not open)
		end
	end)
end


function ArmyController.Toggle()
	setOpen(not open)
end

function ArmyController.Open()
	setOpen(true)
end

function ArmyController.Close()
	setOpen(false)
end

function ArmyController.IsOpen(): boolean
	return open
end

return ArmyController
