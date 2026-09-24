--!strict
--[[ Army panel — recruit/dismiss soldiers. Server-authoritative (RequestRecruitSoldiers / RequestDismissSoldiers).
	v70 "clean screen" (spec §3.8): opened from the Army popover's "MANAGE ARMY ▸" (OrdersController), the Army
	terminals (WE_OpenPanel "Army") and the tutorial. No key of its own any more (A was strafe-left; Y opens the
	Army popover). A registered Modal panel (HudLayout id "Army") with the black dim; HudLayout.ApplyScreen gives
	it the one HUD scale and the safe area, so its title no longer sits under the Roblox topbar. ]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)
local SoldierConfig = require(Shared.Configs.SoldierConfig)
local MonetizationConfig = require(Shared.Configs.MonetizationConfig)

local PanelShell = require(script.Parent.Parent.Modules.PanelShell)
local HudLayout = require(script.Parent.Parent.Modules.HudLayout)
local NotificationController = require(script.Parent.NotificationController)

local ArmyController = {}

local PANEL_ID = "Army"

local player = Players.LocalPlayer
local isTouch = UserInputService.TouchEnabled
local open = false
local screenGui: ScreenGui? = nil
local shell: PanelShell.Shell? = nil
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

-- one GetPlayerState read when no SoldierStateUpdate arrived yet; never blocks (TryGetFunction)
local function ensureArmyState()
	if typeof(armyState) == "table" or requestingState then
		return
	end
	local fn = Remotes.TryGetFunction(Constants.RemoteNames.GetPlayerState)
	if not fn then
		return
	end
	requestingState = true
	task.spawn(function()
		local okInvoke, state = pcall(function()
			return fn:InvokeServer()
		end)
		requestingState = false
		if okInvoke and typeof(state) == "table" then
			synthesizeFromPlayerState(state)
			refreshLabels()
		end
	end)
end

refreshLabels = function()
	local status = statusLabel
	if not status then
		return
	end
	if typeof(armyState) ~= "table" then
		status.Text = "No army data yet — it syncs a moment after you join."
		return
	end
	local count = tonumber(armyState.Soldiers) or 0
	local cap = tonumber(armyState.MaxSoldiers) or 0
	local free = tonumber(armyState.SlotsFree) or math.max(0, cap - count)
	local cost = tonumber(armyState.RecruitCostCash) or 500
	local refundMult = tonumber(armyState.DismissRefundMult) or 0.25
	local barracks = tonumber(armyState.BarracksLevel) or 0
	if count == 0 and barracks == 0 then
		status.Text = string.format(
			"Army empty — build the Barracks to raise the cap.\nBase cap %d · Recruit $%d each · FILL CAP recruits up to the free slots.",
			cap,
			cost
		)
	else
		local trainTick = tonumber(armyState.TrainingIncomePerTick) or 0
		local tickSec = tonumber(armyState.TrainingTickSeconds)
			or (SoldierConfig.TrainingIncome and SoldierConfig.TrainingIncome.TickSeconds)
			or 5
		local trainSec = tonumber(armyState.TrainingIncomePerSec) or (if tickSec > 0 then trainTick / tickSec else 0)
		status.Text = string.format(
			"Barracks Lv %d · %d free slots · Recruit $%d each · Dismiss refund %d%%\nTraining Yard: +$%d/tick (~$%.1f/sec)",
			barracks,
			free,
			cost,
			math.floor(refundMult * 100),
			trainTick,
			trainSec
		)
	end
	local fill = capFill
	if fill and cap > 0 then
		fill.Size = UDim2.fromScale(math.clamp(count / cap, 0, 1), 1)
		fill.BackgroundColor3 = if count >= cap then Constants.Colors.Danger else Constants.Colors.Accent
	end
	local capText = capLabel
	if capText then
		capText.Text = string.format("%d / %d soldiers", count, cap)
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
	local sh = shell
	if sh then
		sh.Sync(isOpen)
	end
	if isOpen then
		ensureArmyState()
		refreshLabels()
	end
end

function ArmyController.Init()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireArmy"
	-- v70: one HUD scale + the safe area (was IgnoreGuiInset = true: the title sat under the Roblox topbar)
	PanelShell.Screen(screen)
	screen.Parent = player:WaitForChild("PlayerGui")
	screenGui = screen

	local TAP = PanelShell.TouchMinV()
	local BTN_H = if isTouch then TAP else 52 -- desktop rows a little taller than the 44 v minimum
	local GAP = 8

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = if isTouch then UDim2.new(0.94, 0, 1, -16) else UDim2.fromOffset(580, 364)
	panel.BackgroundColor3 = Constants.Colors.Panel
	panel.BorderSizePixel = 0
	panel.Active = true
	panel.Visible = false
	panel.ZIndex = 1
	panel.Parent = screen
	UIUtil.Corner(panel, 12)
	UIUtil.Stroke(panel)
	-- touch: as wide as fits (≤ 860 v), as tall as the content (set once the body is built)
	local sizeCap = Instance.new("UISizeConstraint")
	sizeCap.MaxSize = if isTouch then Vector2.new(860, 560) else Vector2.new(580, 364)
	sizeCap.Parent = panel

	PanelShell.Title(panel, "Army")
	PanelShell.CloseButton(panel, function()
		setOpen(false)
	end)

	local headerH = TAP + 8
	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Position = UDim2.fromOffset(0, headerH)
	body.Size = UDim2.new(1, 0, 1, -headerH - 8)
	body.ScrollBarThickness = if isTouch then 6 else 4
	body.ScrollingDirection = Enum.ScrollingDirection.Y
	body.CanvasSize = UDim2.fromOffset(0, 0)
	body.Parent = panel

	local y = 0
	local textSize = PanelShell.Text(14)

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromOffset(16, y)
	status.Size = UDim2.new(1, -32, 0, textSize * 2 + 12)
	status.Font = Enum.Font.GothamMedium
	status.TextSize = textSize
	status.TextWrapped = true
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextYAlignment = Enum.TextYAlignment.Top
	status.TextColor3 = Constants.Colors.Muted
	status.Text = "..."
	status.Parent = body
	statusLabel = status
	y += textSize * 2 + 16

	-- Cap bar
	local capH = PanelShell.Text(16) + 8
	local capBg = Instance.new("Frame")
	capBg.Name = "CapBar"
	capBg.Position = UDim2.fromOffset(16, y)
	capBg.Size = UDim2.new(1, -32, 0, capH)
	capBg.BackgroundColor3 = Constants.Colors.Background
	capBg.BorderSizePixel = 0
	capBg.Parent = body
	UIUtil.Corner(capBg, 6)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Constants.Colors.Accent
	fill.BorderSizePixel = 0
	fill.Parent = capBg
	UIUtil.Corner(fill, 6)
	capFill = fill

	local capText = Instance.new("TextLabel")
	capText.BackgroundTransparency = 1
	capText.Size = UDim2.fromScale(1, 1)
	capText.Font = Enum.Font.GothamBold
	capText.TextSize = PanelShell.Text(14)
	capText.TextColor3 = Constants.Colors.Text
	capText.Text = "0 / 0 soldiers"
	capText.ZIndex = 2
	capText.Parent = capBg
	capLabel = capText
	y += capH + 12

	-- a row of equal-width buttons, TAP tall (≥ 44 real px on touch)
	local function buttonRow(defs: { { Label: string, OnClick: () -> (), Gold: boolean?, Robux: boolean? } }): { TextButton }
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Position = UDim2.fromOffset(16, y)
		row.Size = UDim2.new(1, -32, 0, BTN_H)
		row.Parent = body
		local lay = Instance.new("UIListLayout")
		lay.FillDirection = Enum.FillDirection.Horizontal
		lay.Padding = UDim.new(0, GAP)
		lay.SortOrder = Enum.SortOrder.LayoutOrder
		lay.Parent = row
		local n = #defs
		local out: { TextButton } = {}
		for i, d in ipairs(defs) do
			local b = Instance.new("TextButton")
			b.LayoutOrder = i
			b.Size = UDim2.new(1 / n, -GAP * (n - 1) / n, 1, 0)
			b.BackgroundColor3 = if d.Robux then Color3.fromRGB(40, 32, 12) else Constants.Colors.Gunmetal
			b.Font = Enum.Font.GothamBold
			b.TextSize = PanelShell.Text(13)
			b.TextWrapped = true
			b.TextColor3 = if d.Robux or d.Gold then Constants.Colors.Gold else Constants.Colors.Text
			b.Text = d.Label
			b.BorderSizePixel = 0
			b.Active = true
			b.AutoButtonColor = true
			UIUtil.Corner(b, 8)
			local st = Instance.new("UIStroke")
			st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			st.Color = if d.Robux then Color3.fromRGB(255, 200, 60) else Constants.Colors.Gold
			st.Thickness = if d.Robux then 2 else 1.25
			st.Parent = b
			b.Parent = row
			b.Activated:Connect(d.OnClick)
			table.insert(out, b)
		end
		y += BTN_H + GAP
		return out
	end

	-- v30 P2W visibility (Reaper-style): Commander Pack / Extra Slot at top — free recruits unchanged below
	local function promptArmyRobux(productKey: string)
		local def = MonetizationConfig.DevProducts[productKey]
		if not def or (tonumber(def.Id) or 0) == 0 then
			NotificationController.Show("Offer coming soon", "Info", 2)
			return
		end
		task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestPurchaseDevProduct, productKey)
		pcall(function()
			MarketplaceService:PromptProductPurchase(player, def.Id)
		end)
	end

	local starter = MonetizationConfig.DevProducts.StarterBundle
	local extraSlot = MonetizationConfig.DevProducts.ExtraSoldierSlot
	local starterLive = starter ~= nil and (tonumber(starter.Id) or 0) ~= 0
	local slotLive = extraSlot ~= nil and (tonumber(extraSlot.Id) or 0) ~= 0
	local robuxDefs: { { Label: string, OnClick: () -> (), Gold: boolean?, Robux: boolean? } } = {}
	if starterLive and starter then
		local price = tonumber(starter.RobuxPrice) or 249
		table.insert(robuxDefs, {
			Label = string.format("★ COMMANDER PACK  %d R$", price),
			OnClick = function()
				promptArmyRobux("StarterBundle")
			end,
			Gold = true,
			Robux = true,
		})
	end
	if slotLive and extraSlot then
		local price = tonumber(extraSlot.RobuxPrice) or 79
		table.insert(robuxDefs, {
			-- a secondary ExtraSoldierSlot chip when the Commander Pack is also offered
			Label = if starterLive then string.format("+1 SLOT  %d R$", price) else string.format("★ EXTRA SOLDIER SLOT  %d R$", price),
			OnClick = function()
				promptArmyRobux("ExtraSoldierSlot")
			end,
			Gold = true,
			Robux = true,
		})
	end
	if #robuxDefs > 0 then
		buttonRow(robuxDefs)
	end

	local recruitBtns = buttonRow({
		{
			Label = "RECRUIT x1 $500",
			OnClick = function()
				task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestRecruitSoldiers, 1)
			end,
			Gold = true,
		},
		{
			Label = "RECRUIT x5",
			OnClick = function()
				task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestRecruitSoldiers, 5)
			end,
			Gold = true,
		},
		{
			Label = "FILL CAP",
			OnClick = function()
				ensureArmyState()
				local free = if typeof(armyState) == "table" then tonumber(armyState.SlotsFree) or 0 else 0
				if free > 0 then
					task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestRecruitSoldiers, math.min(free, 50))
				else
					NotificationController.Show("Army full or no slots — upgrade the Barracks", "Warn", 3)
				end
			end,
		},
	})
	local recruit1, recruit5 = recruitBtns[1], recruitBtns[2]
	buttonRow({
		{
			Label = "DISMISS x1",
			OnClick = function()
				task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestDismissSoldiers, 1)
			end,
		},
		{
			Label = "DISMISS x5",
			OnClick = function()
				task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestDismissSoldiers, 5)
			end,
		},
	})

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

	local noteSize = PanelShell.Text(12)
	local note = Instance.new("TextLabel")
	note.Name = "Note"
	note.BackgroundTransparency = 1
	note.Position = UDim2.fromOffset(16, y)
	note.Size = UDim2.new(1, -32, 0, noteSize * 2 + 8)
	note.Font = Enum.Font.GothamMedium
	note.TextSize = noteSize
	note.TextWrapped = true
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.TextYAlignment = Enum.TextYAlignment.Top
	note.TextColor3 = Constants.Colors.Muted
	-- copy by device (mobile plan P1-15): the Y key only for keyboard / gamepad players (HudLayout.PrefersKeys)
	local function noteText(keys: boolean): string
		return if keys
			then "Recruits cost Cash; ★ Robux packs are optional. Squad orders: the Army tile or Y."
			else "Recruits cost Cash; ★ Robux packs are optional. Squad orders: tap the Army tile, hold it to switch."
	end
	note.Text = noteText(HudLayout.PrefersKeys())
	HudLayout.InputModeChanged:Connect(function(keys: boolean)
		note.Text = noteText(keys)
	end)
	note.Parent = body
	y += noteSize * 2 + 12
	body.CanvasSize = UDim2.fromOffset(0, y)
	if isTouch then
		-- phones: as tall as the content (the desktop panel keeps its fixed 580 × 364 v)
		sizeCap.MaxSize = Vector2.new(sizeCap.MaxSize.X, math.min(sizeCap.MaxSize.Y, headerH + y + 8))
	end

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
	})

	Remotes.BindEvent(Constants.RemoteNames.SoldierStateUpdate, function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		armyState = payload
		refreshLabels()
	end)

	Remotes.BindEvent(Constants.RemoteNames.PlayerStateUpdate, function(state: any)
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
	refreshLabels()
	print("[WAR EMPIRE] ArmyController ready (Activated recruit + state hydrate)")
end

function ArmyController.Toggle()
	local sh = shell
	if not open and sh and sh.TapThrough() then
		return
	end
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
