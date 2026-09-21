--!strict
--[[ Upgrade menu UI → RequestPurchaseUpgrade remote.
	B toggles the panel (respects gameProcessed / chat).
	Primary buy path: WALK onto upgrade pads (WorldPromptController).
	Menu BUY buttons remain as an alternate purchase path.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local BaseConfig = require(Shared.Configs.BaseConfig)
local EconomyConfig = require(Shared.Configs.EconomyConfig)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)
local Types = require(Shared.Types)

local NotificationController = require(script.Parent.NotificationController)

local BaseController = {}

local player = Players.LocalPlayer
local upgrades: { [string]: number } = {}
local cash = 0
local menuOpen = false
local menuFailToastAt = 0
local screenGui: ScreenGui? = nil
local listFrame: ScrollingFrame? = nil
local toggleBtn: TextButton? = nil
local hintShown = false

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function refreshList()
	if not listFrame then
		return
	end
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local layout = listFrame:FindFirstChildOfClass("UIListLayout")
	if not layout then
		local l = Instance.new("UIListLayout")
		l.Padding = UDim.new(0, 6)
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.Parent = listFrame
	end

	for order, structureId in ipairs(BaseConfig.StructureOrder) do
		local def = BaseConfig.Structures[structureId]
		if def then
			local level = upgrades[structureId] or 0
			local nextLevel = level + 1
			local cost = if nextLevel <= def.MaxLevel then def.Costs[nextLevel] else nil

			local row = Instance.new("Frame")
			row.Name = structureId
			row.Size = UDim2.new(1, -8, 0, 60)
			row.BackgroundColor3 = Constants.Colors.Background
			row.BorderSizePixel = 0
			row.LayoutOrder = order
			row.Parent = listFrame
			corner(row, 6)

			-- Highlight first purchasable row (Command Center) when still L0
			if structureId == "CommandCenter" and level == 0 then
				local stroke = Instance.new("UIStroke")
				stroke.Color = Constants.Colors.Gold
				stroke.Thickness = 2
				stroke.Parent = row
			end

			local title = Instance.new("TextLabel")
			title.BackgroundTransparency = 1
			title.Position = UDim2.fromOffset(8, 4)
			title.Size = UDim2.new(1, -110, 0, 22)
			title.Font = Enum.Font.GothamBold
			title.TextSize = 14
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextColor3 = Constants.Colors.Text
			title.Text = string.format("%s  Lv%d/%d", def.DisplayName, level, def.MaxLevel)
			title.Parent = row

			local desc = Instance.new("TextLabel")
			desc.BackgroundTransparency = 1
			desc.Position = UDim2.fromOffset(8, 28)
			desc.Size = UDim2.new(1, -110, 0, 20)
			desc.Font = Enum.Font.Gotham
			desc.TextSize = 11
			desc.TextXAlignment = Enum.TextXAlignment.Left
			desc.TextColor3 = Constants.Colors.Muted
			desc.Text = def.Description
			desc.TextTruncate = Enum.TextTruncate.AtEnd
			desc.Parent = row

			local btn = Instance.new("TextButton")
			btn.AnchorPoint = Vector2.new(1, 0.5)
			btn.Position = UDim2.new(1, -8, 0.5, 0)
			btn.Size = UDim2.fromOffset(108, 44)
			btn.Font = Enum.Font.GothamBold
			btn.TextSize = 12
			btn.TextColor3 = Constants.Colors.Text
			btn.AutoButtonColor = true
			btn.BorderSizePixel = 0
			corner(btn, 6)

			if not cost then
				btn.Text = "MAX"
				btn.BackgroundColor3 = Color3.fromRGB(50, 55, 60)
				btn.Active = false
			else
				-- Clear BUY path — not instant on B; tap this button to purchase.
				local rates = EconomyConfig.PassiveIncome and EconomyConfig.PassiveIncome.PerLevelRates
				local rate = if typeof(rates) == "table" then (tonumber(rates[structureId]) or 0) else 0
				local incomeSuffix = if rate > 0 then (" +" .. tostring(rate) .. "/t") else ""
				-- Wider button when income shown
				if rate > 0 then
					btn.Size = UDim2.fromOffset(128, 44)
				end
				if level == 0 then
					btn.Text = "BUY $" .. tostring(cost) .. incomeSuffix
				else
					btn.Text = "UP $" .. tostring(cost) .. incomeSuffix
				end
				local canAfford = cash >= cost
				btn.BackgroundColor3 = if canAfford then Constants.Colors.Accent else Color3.fromRGB(70, 50, 50)
				btn.Active = true
				UIUtil.EnsureMinTouch(btn, 44)
				local function onMenuBuy()
					print(string.format("[WAR EMPIRE] Base menu BUY: %s cost=%s cash=%d rate=+%d/tick", structureId, tostring(cost), cash, rate))
					if cash < cost then
						local now = os.clock()
						if now - menuFailToastAt >= 0.9 then
							menuFailToastAt = now
							NotificationController.Show("Not enough cash — need $" .. tostring(cost), "Warn", 2.5)
						end
						print("[WAR EMPIRE] Base menu BUY soft-fail cash", structureId)
					else
						NotificationController.Show("Buying " .. def.DisplayName .. "…", "Info", 1.5)
					end
					Remotes.GetEvent(Constants.RemoteNames.RequestPurchaseUpgrade):FireServer({
						StructureId = structureId,
					} :: Types.PurchaseUpgradeRequest)
				end
				btn.Activated:Connect(onMenuBuy)
				btn.MouseButton1Click:Connect(onMenuBuy)
			end
			btn.Parent = row
		end
	end

	local l = listFrame:FindFirstChildOfClass("UIListLayout")
	if l then
		listFrame.CanvasSize = UDim2.fromOffset(0, l.AbsoluteContentSize.Y + 12)
	end
end

local function setOpen(open: boolean)
	menuOpen = open
	if screenGui then
		local panel = screenGui:FindFirstChild("UpgradePanel")
		if panel and panel:IsA("GuiObject") then
			panel.Visible = open
		end
	end
	if toggleBtn then
		local touch = UserInputService.TouchEnabled
		if open then
			toggleBtn.Text = "Close Base"
		else
			toggleBtn.Text = if touch then "BASE UPGRADES" else "Base Upgrades  [B]"
		end
		toggleBtn.Visible = true
	end
	if open then
		refreshList()
	end
end

local function flashToggle()
	if not toggleBtn then
		return
	end
	local btn = toggleBtn
	local baseColor = Constants.Colors.Accent
	btn.BackgroundColor3 = Constants.Colors.Gold
	local tw = TweenService:Create(
		btn,
		TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 5, true),
		{ BackgroundColor3 = baseColor }
	)
	tw:Play()
	task.delay(6, function()
		if toggleBtn == btn then
			tw:Cancel()
			btn.BackgroundColor3 = Constants.Colors.Accent
		end
	end)
end

local function showFirstJoinHints()
	if hintShown then
		return
	end
	hintShown = true
	-- Session-once onboarding after MapSetup world is up
	task.delay(1.4, function()
		NotificationController.Show(
			"Walk to glowing pads to buy · B/G menus",
			"Info",
			6
		)
	end)
	task.delay(7.5, function()
		NotificationController.Show(
			"Prices float above pads · Base [B] · Garage [G] / E on pads",
			"Info",
			5
		)
	end)
	flashToggle()
end

function BaseController.Open()
	setOpen(true)
end

function BaseController.Close()
	setOpen(false)
end

function BaseController.Toggle()
	setOpen(not menuOpen)
end

function BaseController.IsOpen(): boolean
	return menuOpen
end

function BaseController.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WarEmpireBaseUI"
	-- Above default chat / touch controls so mobile Base CTA stays tappable
	gui.DisplayOrder = 58 -- above HUD dock (55); CTA parked left of dock so no click steal
	gui.Parent = player:WaitForChild("PlayerGui")
	UIUtil.PrepareScreen(gui, false)
	screenGui = gui

	local touch = UserInputService.TouchEnabled
	-- CRITICAL: do NOT park Base CTA over the right action dock (Shop/Rebirth/…).
	-- Mobile → bottom-LEFT above currency pill; desktop → bottom-center (dock is right-only).
	local btnW = if touch then 168 else 260
	local btnH = if touch then 52 else 56

	local btn = Instance.new("TextButton")
	btn.Name = "ToggleUpgrades"
	if touch then
		btn.AnchorPoint = Vector2.new(0, 1)
		btn.Position = UDim2.new(0, 16, 1, -176)
	else
		btn.AnchorPoint = Vector2.new(0.5, 1)
		btn.Position = UDim2.new(0.5, 0, 1, -28)
	end
	btn.Size = UDim2.fromOffset(btnW, btnH)
	btn.BackgroundColor3 = Constants.Colors.Accent
	btn.TextColor3 = Constants.Colors.Text
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = if touch then 15 else 18
	btn.Text = if touch then "BASE [B]" else "Base Upgrades  [B]"
	btn.BorderSizePixel = 0
	btn.ZIndex = 20
	btn.Visible = true
	btn.Active = true
	btn.AutoButtonColor = true
	corner(btn, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Constants.Colors.Gold
	stroke.Thickness = 2
	stroke.Parent = btn
	btn.Parent = gui
	toggleBtn = btn
	UIUtil.EnsureMinTouch(btn, 48)
	btn.Activated:Connect(function()
		print("[WAR EMPIRE] Base CTA toggled →", not menuOpen)
		setOpen(not menuOpen)
	end)

	if touch then
		task.defer(function()
			local inset = GuiService:GetGuiInset()
			local extra = math.clamp(inset.Y * 0.15, 0, 24)
			btn.Position = UDim2.new(0, 16, 1, -(176 + extra))
			btn.Visible = true
			btn.Active = true
		end)
	end

	local panel = Instance.new("Frame")
	panel.Name = "UpgradePanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.48)
	panel.Size = UDim2.fromOffset(440, 440)
	panel.BackgroundColor3 = Constants.Colors.Panel
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 10)
	do
		local ps = Instance.new("UIStroke")
		ps.Color = Constants.Colors.Gold
		ps.Thickness = 1.5
		ps.Transparency = 0.4
		ps.Parent = panel
	end

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(14, 10)
	title.Size = UDim2.new(1, -28, 0, 28)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 20
	title.TextColor3 = Constants.Colors.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "BASE UPGRADES"
	title.Parent = panel

	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromOffset(14, 36)
	sub.Size = UDim2.new(1, -28, 0, 18)
	sub.Font = Enum.Font.Gotham
	sub.TextSize = 12
	sub.TextColor3 = Constants.Colors.Muted
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Text = "Walk/tap BUY on pads · B menu · +$/tick shown"
	sub.Parent = panel

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.Position = UDim2.fromOffset(10, 58)
	scroll.Size = UDim2.new(1, -20, 1, -68)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.Parent = panel
	listFrame = scroll

	Remotes.GetEvent(Constants.RemoteNames.BaseStateUpdate).OnClientEvent:Connect(function(base: Types.BaseStatePayload)
		upgrades = base.Upgrades or upgrades
		if menuOpen then
			refreshList()
		end
	end)

	local function applyCash(n: any)
		local v = tonumber(n)
		if typeof(v) == "number" then
			cash = math.floor(v)
			if menuOpen then
				refreshList()
			end
		end
	end

	Remotes.GetEvent(Constants.RemoteNames.EconomyUpdate).OnClientEvent:Connect(function(payload: Types.EconomyUpdatePayload)
		applyCash(payload.Cash)
	end)

	player:GetAttributeChangedSignal("WE_Cash"):Connect(function()
		applyCash(player:GetAttribute("WE_Cash"))
	end)
	applyCash(player:GetAttribute("WE_Cash"))

	Remotes.GetEvent(Constants.RemoteNames.PlayerStateUpdate).OnClientEvent:Connect(function(state: Types.PlayerStatePayload)
		applyCash(state.Cash)
		if state.Base then
			upgrades = state.Base.Upgrades
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gp)
		-- Respect chat / processed UI (gp true while typing in chat).
		if gp then
			return
		end
		if input.KeyCode == Enum.KeyCode.B then
			setOpen(not menuOpen)
		end
	end)

	showFirstJoinHints()
	print("[WAR EMPIRE] BaseController ready (CTA clear of dock, BUY via Activated)")
end

return BaseController
