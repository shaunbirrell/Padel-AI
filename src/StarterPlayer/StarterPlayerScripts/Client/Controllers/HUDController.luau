--!strict
--[[
	Programmatic HUD: Level+XP top-left, currency pill bottom-left,
	mobile action dock (large color-coded squares) bottom-right.
	Inspiration-only layout quality — WAR EMPIRE features/hotkeys kept.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local UIUtil = require(Shared.Util.UIUtil)

local HUDController = {}

local player = Players.LocalPlayer
local _gui: ScreenGui? = nil
local levelLabel: TextLabel? = nil
local xpBarFill: Frame? = nil
local xpText: TextLabel? = nil
local cashLabel: TextLabel? = nil
local goldLabel: TextLabel? = nil
local passiveLabel: TextLabel? = nil
local seasonLabel: TextLabel? = nil
local spinnerBtn: TextButton? = nil
local actionDock: Frame? = nil
local spinnerReady = false
local spinnerCooldown = 0
local lastPassive = 0
local lastTraining = 0

local function refreshPassiveHint()
	if not passiveLabel then
		return
	end
	if lastTraining > 0 then
		passiveLabel.Text = string.format("+%d$/tick · Train +%d$/tick", lastPassive, lastTraining)
	else
		passiveLabel.Text = string.format("+%d$/tick", lastPassive)
	end
end

local function makeCorner(parent: Instance, radius: number)
	UIUtil.Corner(parent, radius)
end

local function makeStroke(parent: Instance, gold: boolean?)
	if gold then
		UIUtil.GoldStroke(parent, 1.5)
	else
		UIUtil.Stroke(parent)
	end
end

function HUDController.Init()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireHUD"
	screen.Parent = player:WaitForChild("PlayerGui")
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.IgnoreGuiInset = false
	-- Above Base CTA (45) so dock tiles receive clicks; below modal panels (60+)
	screen.DisplayOrder = 55
	UIUtil.AttachMobileScale(screen, 800, 0.7, 1.15)
	_gui = screen

	local touch = UserInputService.TouchEnabled

	-- Top-left: Level + XP (compact)
	local left = Instance.new("Frame")
	left.Name = "LevelPanel"
	left.AnchorPoint = Vector2.new(0, 0)
	left.Position = UDim2.fromOffset(16, 16)
	left.Size = UDim2.fromOffset(220, 64)
	left.BackgroundColor3 = Constants.Colors.Panel
	left.BackgroundTransparency = 0.12
	left.BorderSizePixel = 0
	left.Parent = screen
	makeCorner(left, 10)
	makeStroke(left, true)

	local lvl = Instance.new("TextLabel")
	lvl.Name = "LevelLabel"
	lvl.BackgroundTransparency = 1
	lvl.Position = UDim2.fromOffset(10, 6)
	lvl.Size = UDim2.new(1, -20, 0, 22)
	lvl.Font = Enum.Font.GothamBold
	lvl.TextSize = 18
	lvl.TextXAlignment = Enum.TextXAlignment.Left
	lvl.TextColor3 = Constants.Colors.Text
	lvl.Text = "LVL 1"
	lvl.Parent = left
	levelLabel = lvl

	local xpBg = Instance.new("Frame")
	xpBg.Name = "XPBarBG"
	xpBg.Position = UDim2.fromOffset(10, 36)
	xpBg.Size = UDim2.new(1, -20, 0, 14)
	xpBg.BackgroundColor3 = Constants.Colors.Background
	xpBg.BorderSizePixel = 0
	xpBg.Parent = left
	makeCorner(xpBg, 4)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Constants.Colors.XP
	fill.BorderSizePixel = 0
	fill.Parent = xpBg
	makeCorner(fill, 4)
	xpBarFill = fill

	local xpLbl = Instance.new("TextLabel")
	xpLbl.Name = "XPText"
	xpLbl.BackgroundTransparency = 1
	xpLbl.Size = UDim2.fromScale(1, 1)
	xpLbl.Font = Enum.Font.Gotham
	xpLbl.TextSize = 11
	xpLbl.TextColor3 = Constants.Colors.Text
	xpLbl.Text = "0 / 100"
	xpLbl.Parent = xpBg
	xpText = xpLbl

	-- Bottom-left: currency pill (cash + gold) — thumb-friendly
	local pill = Instance.new("Frame")
	pill.Name = "CurrencyPill"
	pill.AnchorPoint = Vector2.new(0, 1)
	pill.Position = UDim2.new(0, 16, 1, if touch then -100 else -20)
	pill.Size = UDim2.fromOffset(200, 56)
	pill.BackgroundColor3 = Color3.fromRGB(22, 26, 32)
	pill.BackgroundTransparency = 0.08
	pill.BorderSizePixel = 0
	pill.ZIndex = 12
	pill.Parent = screen
	makeCorner(pill, 28)
	local pillStroke = UIUtil.Stroke(pill, Color3.fromRGB(255, 210, 90), 2)
	pillStroke.Transparency = 0.25

	local cash = Instance.new("TextLabel")
	cash.Name = "CashLabel"
	cash.BackgroundTransparency = 1
	cash.Position = UDim2.fromOffset(18, 4)
	cash.Size = UDim2.new(1, -28, 0, 26)
	cash.Font = Enum.Font.GothamBold
	cash.TextSize = 20
	cash.TextXAlignment = Enum.TextXAlignment.Left
	cash.TextColor3 = Constants.Colors.Cash
	cash.Text = "$5,000"
	cash.ZIndex = 13
	cash.Parent = pill
	cashLabel = cash

	local gold = Instance.new("TextLabel")
	gold.Name = "GoldLabel"
	gold.BackgroundTransparency = 1
	gold.Position = UDim2.fromOffset(18, 28)
	gold.Size = UDim2.new(1, -28, 0, 20)
	gold.Font = Enum.Font.GothamMedium
	gold.TextSize = 15
	gold.TextXAlignment = Enum.TextXAlignment.Left
	gold.TextColor3 = Constants.Colors.Gold
	gold.Text = "◆ 0"
	gold.ZIndex = 13
	gold.Parent = pill
	goldLabel = gold

	local passive = Instance.new("TextLabel")
	passive.Name = "PassiveHint"
	passive.AnchorPoint = Vector2.new(0, 1)
	passive.Position = UDim2.new(0, 16, 1, if touch then -160 else -80)
	passive.Size = UDim2.fromOffset(240, 18)
	passive.BackgroundTransparency = 1
	passive.Font = Enum.Font.Gotham
	passive.TextSize = 12
	passive.TextXAlignment = Enum.TextXAlignment.Left
	passive.TextColor3 = Constants.Colors.Muted
	passive.Text = ""
	passive.Parent = screen
	passiveLabel = passive

	local season = Instance.new("TextLabel")
	season.Name = "SeasonLabel"
	season.AnchorPoint = Vector2.new(0.5, 0)
	season.Position = UDim2.new(0.5, 0, 0, 12)
	season.Size = UDim2.fromOffset(280, 22)
	season.BackgroundColor3 = Constants.Colors.Panel
	season.BackgroundTransparency = 0.25
	season.BorderSizePixel = 0
	season.Font = Enum.Font.GothamBold
	season.TextSize = 12
	season.TextColor3 = Constants.Colors.Muted
	season.Text = ""
	season.Visible = false
	season.Parent = screen
	UIUtil.Corner(season, 6)
	seasonLabel = season

	-- Spinner chip beside currency pill
	local spin = Instance.new("TextButton")
	spin.Name = "SpinnerButton"
	spin.AnchorPoint = Vector2.new(0, 1)
	spin.Position = UDim2.new(0, 228, 1, if touch then -100 else -20)
	spin.Size = UDim2.fromOffset(72, 56)
	spin.BackgroundColor3 = Constants.Colors.Panel
	spin.Font = Enum.Font.GothamBold
	spin.TextSize = 11
	spin.TextColor3 = Constants.Colors.Text
	spin.Text = "SPIN"
	spin.BorderSizePixel = 0
	spin.ZIndex = 12
	spin.Parent = screen
	makeCorner(spin, 14)
	makeStroke(spin, true)
	UIUtil.EnsureMinTouch(spin, 56)
	spinnerBtn = spin
	spin.MouseButton1Click:Connect(function()
		if spinnerReady then
			Remotes.GetEvent(Constants.RemoteNames.RequestClaimSpinner):FireServer()
		end
	end)

	-- Bottom-right action dock (tiles bound by BindActionBar)
	local dock = Instance.new("Frame")
	dock.Name = "MobileActionBar"
	dock.AnchorPoint = Vector2.new(1, 1)
	dock.Position = UDim2.new(1, -16, 1, if touch then -24 else -20)
	dock.Size = UDim2.fromOffset(400, 80)
	dock.BackgroundTransparency = 1
	dock.ZIndex = 12
	dock.Parent = screen
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = dock
	actionDock = dock

	local function refreshSpinnerBtn()
		if not spinnerBtn then
			return
		end
		if spinnerReady then
			spinnerBtn.Text = "READY"
			spinnerBtn.BackgroundColor3 = Constants.Colors.Accent
			spinnerBtn.TextColor3 = Constants.Colors.Text
		else
			local mins = math.ceil(math.max(0, spinnerCooldown) / 60)
			spinnerBtn.Text = string.format("%dm", mins)
			spinnerBtn.BackgroundColor3 = Constants.Colors.Panel
			spinnerBtn.TextColor3 = Constants.Colors.Muted
		end
	end
	refreshSpinnerBtn()

	Remotes.GetEvent(Constants.RemoteNames.SpinnerStateUpdate).OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		spinnerReady = payload.Ready == true
		spinnerCooldown = tonumber(payload.CooldownRemaining) or 0
		refreshSpinnerBtn()
	end)

	local econToken = 0
	Remotes.GetEvent(Constants.RemoteNames.EconomyUpdate).OnClientEvent:Connect(function(payload: Types.EconomyUpdatePayload)
		econToken += 1
		local my = econToken
		local cashAmt, goldAmt = payload.Cash, payload.Gold
		task.defer(function()
			if my == econToken then
				HUDController.SetEconomy(cashAmt, goldAmt)
			end
		end)
	end)

	Remotes.GetEvent(Constants.RemoteNames.XPUpdate).OnClientEvent:Connect(function(payload: Types.XPUpdatePayload)
		HUDController.SetXP(payload.Level, payload.XP, payload.XPToNext)
	end)

	Remotes.GetEvent(Constants.RemoteNames.PlayerStateUpdate).OnClientEvent:Connect(function(state: Types.PlayerStatePayload)
		HUDController.ApplyState(state)
	end)

	Remotes.GetEvent(Constants.RemoteNames.BaseStateUpdate).OnClientEvent:Connect(function(base: Types.BaseStatePayload)
		if base.PassiveIncomePerTick then
			lastPassive = base.PassiveIncomePerTick
			refreshPassiveHint()
		end
	end)
	Remotes.GetEvent(Constants.RemoteNames.SoldierStateUpdate).OnClientEvent:Connect(function(payload)
		if typeof(payload) == "table" then
			lastTraining = tonumber(payload.TrainingIncomePerTick) or 0
			refreshPassiveHint()
		end
	end)

	Remotes.GetEvent(Constants.RemoteNames.SeasonStateUpdate).OnClientEvent:Connect(function(payload)
		if not seasonLabel or typeof(payload) ~= "table" then
			return
		end
		local active = payload.Active == true
		local name = tostring(payload.DisplayName or payload.SeasonId or "Season")
		if active then
			local xpB = tonumber(payload.XPBonusMult) or 1
			local cashB = tonumber(payload.CashBonusMult) or 1
			seasonLabel.Visible = true
			seasonLabel.TextColor3 = Constants.Colors.Cash
			seasonLabel.Text = string.format("%s  ·  XP×%.2f Cash×%.2f", name, xpB, cashB)
		else
			seasonLabel.Visible = true
			seasonLabel.TextColor3 = Constants.Colors.Muted
			seasonLabel.Text = name .. "  ·  ENDED"
		end
	end)

	task.spawn(function()
		local ok, state = pcall(function()
			return Remotes.GetFunction(Constants.RemoteNames.GetPlayerState):InvokeServer()
		end)
		if ok and state then
			HUDController.ApplyState(state :: Types.PlayerStatePayload)
		end
	end)
end

--[[
	Wire large color-coded action tiles after other controllers Init.
	actions: { { Name, Icon, Label, Color, OnClick }, ... }
]]
function HUDController.BindActionBar(actions: { { Name: string, Icon: string, Label: string, Color: Color3, OnClick: () -> () } })
	if not actionDock then
		warn("[HUDController] BindActionBar: actionDock nil — Init order broken?")
		return
	end
	actionDock.Active = false -- children buttons receive input; frame must not sink
	for _, child in ipairs(actionDock:GetChildren()) do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	-- Always ≥64px; touch gets larger hit targets
	local tileSize = if UserInputService.TouchEnabled then 76 else 68
	tileSize = math.max(tileSize, 64)
	actionDock.Size = UDim2.fromOffset(#actions * (tileSize + 10) + 8, tileSize + 8)
	actionDock.ZIndex = 30
	for i, def in ipairs(actions) do
		local btn = UIUtil.MakeActionTile(actionDock, {
			Name = def.Name,
			Icon = def.Icon,
			Label = def.Label,
			Color = def.Color,
			LayoutOrder = i,
			SizePx = tileSize,
		})
		btn.Active = true
		btn.ZIndex = 31
		-- Activated = mouse + touch + gamepad (MouseButton1Click alone misses some touch paths)
		btn.Activated:Connect(function()
			def.OnClick()
		end)
	end
	local order = if _gui then _gui.DisplayOrder else -1
	print(string.format("[HUDController] BindActionBar: %d tiles Active size=%d DisplayOrder=%d", #actions, tileSize, order))
end

local function formatCash(n: number): string
	local formatted = tostring(math.floor(n))
	formatted = formatted:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return "$" .. formatted
end

function HUDController.SetEconomy(cash: number, gold: number)
	if cashLabel then
		cashLabel.Text = formatCash(cash)
	end
	if goldLabel then
		goldLabel.Text = "◆ " .. tostring(math.floor(gold))
	end
end

function HUDController.SetXP(level: number, xp: number, xpToNext: number)
	if levelLabel then
		levelLabel.Text = "LVL " .. tostring(level)
	end
	local denom = if xpToNext > 0 and xpToNext < math.huge then xpToNext else 1
	local alpha = math.clamp(xp / denom, 0, 1)
	if xpBarFill then
		xpBarFill.Size = UDim2.fromScale(alpha, 1)
	end
	if xpText then
		if xpToNext == math.huge or xpToNext <= 0 then
			xpText.Text = "MAX"
		else
			xpText.Text = string.format("%d / %d", xp, xpToNext)
		end
	end
end

function HUDController.ApplyState(state: Types.PlayerStatePayload)
	HUDController.SetEconomy(state.Cash, state.Gold)
	HUDController.SetXP(state.Level, state.XP, state.XPToNext)
	if state.Base then
		lastPassive = state.Base.PassiveIncomePerTick or 0
	end
	if typeof(state.TrainingIncomePerTick) == "number" then
		lastTraining = state.TrainingIncomePerTick
	end
	refreshPassiveHint()
end

return HUDController
