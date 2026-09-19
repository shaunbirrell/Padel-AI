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
local SoldierConfig = require(Shared.Configs.SoldierConfig)

local NotificationController = require(script.Parent.NotificationController)

local ArmyController = {}

local player = Players.LocalPlayer
local isTouch = UserInputService.TouchEnabled
local open = false
local screenGui: ScreenGui? = nil
local statusLabel: TextLabel? = nil
local capFill: Frame? = nil
local capLabel: TextLabel? = nil
local armyState: any = nil
local requestingState = false
local refreshLabels: () -> ()

local function synthesizeFromPlayerState(state: any)
	if typeof(state) ~= "table" then
		return
	end
	local barracks = 0
	if typeof(state.Base) == "table" and typeof(state.Base.Upgrades) == "table" then
		barracks = tonumber(state.Base.Upgrades.Barracks) or 0
	end
	local count = tonumber(state.Soldiers) or 0
	local baseCap = SoldierConfig.MaxSoldiersBase or 50
	local per = SoldierConfig.SoldiersPerBarracksLevel or 5
	local cap = baseCap + barracks * per
	local cost = SoldierConfig.RecruitCostCash or 500
	local room = math.max(0, cap - count)
	local tickSec = (SoldierConfig.TrainingIncome and SoldierConfig.TrainingIncome.TickSeconds) or 5
	local perSoldier = (SoldierConfig.TrainingIncome and SoldierConfig.TrainingIncome.CashPerSoldierPerTick) or 0
	local minN = (SoldierConfig.TrainingIncome and SoldierConfig.TrainingIncome.MinSoldiersForIncome) or 1
	local training = if count >= minN then math.floor(count * perSoldier) else 0
	armyState = {
		Soldiers = count,
		MaxSoldiers = cap,
		BarracksLevel = barracks,
		RecruitCostCash = cost,
		RecruitBatchSize = SoldierConfig.RecruitBatchSize or 1,
		DismissRefundMult = SoldierConfig.DismissRefundMult or 0.25,
		SlotsFree = room,
		FillCost = cost * room,
		TrainingIncomePerTick = training,
		TrainingTickSeconds = tickSec,
		TrainingIncomePerSec = if tickSec > 0 then training / tickSec else 0,
	}
end

local function ensureArmyState()
	if typeof(armyState) == "table" or requestingState then
		return
	end
	requestingState = true
	task.spawn(function()
		local okInvoke, state = pcall(function()
			return Remotes.GetFunction(Constants.RemoteNames.GetPlayerState):InvokeServer()
		end)
		requestingState = false
		if okInvoke and typeof(state) == "table" then
			synthesizeFromPlayerState(state)
			refreshLabels()
		end
	end)
end

refreshLabels = function()
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
	if isOpen then
		ensureArmyState()
		refreshLabels()
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
	UIUtil.EnsureMinTouch(toggle, 44)
	toggle.Activated:Connect(function()
		setOpen(not open)
	end)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = if isTouch then UDim2.new(0.92, 0, 0.7, 0) else UDim2.fromOffset(380, 380)
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
	close.Activated:Connect(function()
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
		b.Active = true
		b.AutoButtonColor = true
		UIUtil.Corner(b, 6)
		UIUtil.Stroke(b, Constants.Colors.Gold, 1.25)
		b.Parent = panel
		UIUtil.EnsureMinTouch(b, 44)
		b.Activated:Connect(cb)
		return b
	end

	local recruit1 = makeBtn("RECRUIT x1 $500", 16, 174, 168, function()
		Remotes.GetEvent(Constants.RemoteNames.RequestRecruitSoldiers):FireServer(1)
	end, true)
	local recruit5 = makeBtn("RECRUIT x5", 192, 174, 168, function()
		Remotes.GetEvent(Constants.RemoteNames.RequestRecruitSoldiers):FireServer(5)
	end, true)
	makeBtn("FILL CAP", 16, 228, 168, function()
		ensureArmyState()
		local free = if typeof(armyState) == "table" then tonumber(armyState.SlotsFree) or 0 else 0
		if free > 0 then
			Remotes.GetEvent(Constants.RemoteNames.RequestRecruitSoldiers):FireServer(math.min(free, 50))
		else
			NotificationController.Show("Army full or no slots — upgrade Barracks (B)", "Warn", 3)
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

	Remotes.GetEvent(Constants.RemoteNames.PlayerStateUpdate).OnClientEvent:Connect(function(state)
		if typeof(armyState) ~= "table" then
			synthesizeFromPlayerState(state)
			refreshLabels()
		elseif typeof(state) == "table" and typeof(state.Soldiers) == "number" then
			-- Keep count fresh if SoldierStateUpdate was missed mid-session
			armyState.Soldiers = state.Soldiers
			local cap = tonumber(armyState.MaxSoldiers) or 0
			armyState.SlotsFree = math.max(0, cap - state.Soldiers)
			refreshLabels()
		end
	end)

	task.defer(ensureArmyState)
	print("[WAR EMPIRE] ArmyController ready (Activated recruit + state hydrate)")

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
