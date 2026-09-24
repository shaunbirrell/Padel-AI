--!strict
--[[ Base menu → RequestPurchaseUpgrade remote (the menu BUY path; the console BUY in the world stays primary).
	v70 "clean screen" (spec §3.7 / §3.8):
	  * No HUD button any more: the "BASE [B]" / "Base Upgrades [B]" CTA and the stale first-join hint toasts
	    are gone. The menu opens from B (HudConfig.Keys.Base, respects gameProcessed / chat), the Command Center
	    map-table terminal (WE_OpenPanel "Base") and the tutorial CTA.
	  * Passive income moved here from the cash pill: the subtitle reads "+$N/tick passive · +$N/tick training".
	  * A registered Modal panel (HudLayout id "Base") with the black dim; one HUD scale + safe area.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local BaseConfig = require(Shared.Configs.BaseConfig)
local EconomyConfig = require(Shared.Configs.EconomyConfig)
local HudConfig = require(Shared.Configs.HudConfig)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)
local Types = require(Shared.Types)

local PanelShell = require(script.Parent.Parent.Modules.PanelShell)
local NotificationController = require(script.Parent.NotificationController)

local BaseController = {}

local PANEL_ID = "Base"

local player = Players.LocalPlayer
local isTouch = UserInputService.TouchEnabled
local upgrades: { [string]: number } = {}
local cash = 0
local passivePerTick = 0
local trainingPerTick = 0
local menuOpen = false
local menuFailToastAt = 0
local screenGui: ScreenGui? = nil
local listFrame: ScrollingFrame? = nil
local subLabel: TextLabel? = nil
local shell: PanelShell.Shell? = nil

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out
end

-- the passive-income hint that used to sit on the cash pill ("+N$/tick")
local function refreshSubtitle()
	local sub = subLabel
	if not sub then
		return
	end
	local tickSec = (EconomyConfig.PassiveIncome and tonumber(EconomyConfig.PassiveIncome.TickSeconds)) or 5
	local parts = { string.format("+$%s/tick passive", commas(passivePerTick)) }
	if trainingPerTick > 0 then
		table.insert(parts, string.format("+$%s/tick training", commas(trainingPerTick)))
	end
	sub.Text = table.concat(parts, " · ") .. string.format("  (every %ds)", tickSec)
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

	local TAP = PanelShell.TouchMinV()
	local rowH = TAP + 16
	local titleSize = PanelShell.Text(15)
	local descSize = PanelShell.Text(12)
	local btnW = if isTouch then 190 else 136

	for order, structureId in ipairs(BaseConfig.StructureOrder) do
		local def = BaseConfig.Structures[structureId]
		if def then
			local level = upgrades[structureId] or 0
			local nextLevel = level + 1
			local cost = if nextLevel <= def.MaxLevel then def.Costs[nextLevel] else nil

			local row = Instance.new("Frame")
			row.Name = structureId
			row.Size = UDim2.new(1, -8, 0, rowH)
			row.BackgroundColor3 = Constants.Colors.Background
			row.BorderSizePixel = 0
			row.LayoutOrder = order
			row.Parent = listFrame
			corner(row, 8)

			-- Highlight first purchasable row (Command Center) when still L0
			if structureId == "CommandCenter" and level == 0 then
				local stroke = Instance.new("UIStroke")
				stroke.Color = Constants.Colors.Gold
				stroke.Thickness = 2
				stroke.Parent = row
			end

			local title = Instance.new("TextLabel")
			title.BackgroundTransparency = 1
			title.Position = UDim2.fromOffset(12, 6)
			title.Size = UDim2.new(1, -(btnW + 28), 0, titleSize + 6)
			title.Font = Enum.Font.GothamBold
			title.TextSize = titleSize
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.TextColor3 = Constants.Colors.Text
			title.TextTruncate = Enum.TextTruncate.AtEnd
			title.Text = string.format("%s  Lv%d/%d", def.DisplayName, level, def.MaxLevel)
			title.Parent = row

			local desc = Instance.new("TextLabel")
			desc.BackgroundTransparency = 1
			desc.Position = UDim2.fromOffset(12, titleSize + 14)
			desc.Size = UDim2.new(1, -(btnW + 28), 0, descSize + 6)
			desc.Font = Enum.Font.GothamMedium
			desc.TextSize = descSize
			desc.TextXAlignment = Enum.TextXAlignment.Left
			desc.TextColor3 = Constants.Colors.Muted
			desc.Text = def.Description
			desc.TextTruncate = Enum.TextTruncate.AtEnd
			desc.Parent = row

			local btn = Instance.new("TextButton")
			btn.AnchorPoint = Vector2.new(1, 0.5)
			btn.Position = UDim2.new(1, -8, 0.5, 0)
			btn.Size = UDim2.fromOffset(btnW, TAP)
			btn.Font = Enum.Font.GothamBold
			btn.TextSize = PanelShell.Text(13)
			btn.TextColor3 = Constants.Colors.Text
			btn.TextWrapped = true
			btn.AutoButtonColor = true
			btn.BorderSizePixel = 0
			corner(btn, 8)

			if not cost then
				btn.Text = "MAX"
				btn.BackgroundColor3 = Color3.fromRGB(50, 55, 60)
				btn.Active = false
			else
				-- Clear BUY path — not instant on B; tap this button to purchase.
				local rates = EconomyConfig.PassiveIncome and EconomyConfig.PassiveIncome.PerLevelRates
				local rate = if typeof(rates) == "table" then (tonumber(rates[structureId]) or 0) else 0
				local incomeSuffix = if rate > 0 then (" +" .. tostring(rate) .. "/t") else ""
				local idleText = (if level == 0 then "BUY $" else "UP $") .. commas(cost) .. incomeSuffix
				btn.Text = idleText
				local canAfford = cash >= cost
				btn.BackgroundColor3 = if canAfford then Constants.Colors.Accent else Color3.fromRGB(70, 50, 50)
				btn.Active = true
				UIUtil.EnsureMinTouch(btn, TAP)
				local lastTapAt = 0
				local function onMenuBuy()
					-- v67: one purchase per tap
					local tapNow = os.clock()
					if tapNow - lastTapAt < 0.35 then
						return
					end
					lastTapAt = tapNow
					print(string.format("[WAR EMPIRE] Base menu BUY: %s cost=%s cash=%d rate=+%d/tick", structureId, tostring(cost), cash, rate))
					if cash < cost then
						local now = os.clock()
						if now - menuFailToastAt >= 0.9 then
							menuFailToastAt = now
							NotificationController.Show("Not enough cash — need $" .. commas(cost), "Warn", 2.5)
						end
						print("[WAR EMPIRE] Base menu BUY soft-fail cash", structureId)
					end
					-- v61: FireServer via TryGet (≤3s); the button reads BUYING… only if the fire succeeded
					local fired = Remotes.FireServer(Constants.RemoteNames.RequestPurchaseUpgrade, {
						StructureId = structureId,
					} :: Types.PurchaseUpgradeRequest)
					if not fired then
						local now = os.clock()
						if now - menuFailToastAt >= 8 then
							menuFailToastAt = now
							NotificationController.Show("Buy failed — remotes not ready. Rejoin game.", "Error", 4)
						end
						return
					end
					if cash >= cost and btn.Parent then
						-- v70: feedback on the button itself (the "Buying X…" toast is dropped by the toast lane)
						btn.Text = "BUYING…"
						task.delay(1.5, function()
							if btn.Parent and btn.Text == "BUYING…" then
								btn.Text = idleText
							end
						end)
					end
				end
				-- v67: Activated only (MouseButton1Click as well fired two purchases per click)
				btn.Activated:Connect(onMenuBuy)
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
	local sh = shell
	if sh then
		sh.Sync(open)
	end
	if open then
		refreshSubtitle()
		refreshList()
	end
end

function BaseController.Open()
	setOpen(true)
end

function BaseController.Close()
	setOpen(false)
end

function BaseController.Toggle()
	local sh = shell
	if not menuOpen and sh and sh.TapThrough() then
		return
	end
	setOpen(not menuOpen)
end

function BaseController.IsOpen(): boolean
	return menuOpen
end

function BaseController.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "WarEmpireBaseUI"
	-- DisplayOrder 58 (HudConfig.DisplayOrder.WarEmpireBaseUI): above the HUD (55); one HUD scale + safe area
	PanelShell.Screen(gui, HudConfig.DisplayOrder.WarEmpireBaseUI)
	gui.Parent = player:WaitForChild("PlayerGui")
	screenGui = gui

	local TAP = PanelShell.TouchMinV()
	local panel = Instance.new("Frame")
	panel.Name = "UpgradePanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = if isTouch then UDim2.new(0.94, 0, 1, -16) else UDim2.fromOffset(480, 520)
	panel.BackgroundColor3 = Constants.Colors.Panel
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Active = true
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 12)
	do
		local ps = Instance.new("UIStroke")
		ps.Color = Constants.Colors.Gold
		ps.Thickness = 1.5
		ps.Transparency = 0.4
		ps.Parent = panel
		local cap = Instance.new("UISizeConstraint")
		cap.MaxSize = if isTouch then Vector2.new(760, 620) else Vector2.new(480, 520)
		cap.Parent = panel
	end

	local title = PanelShell.Title(panel, "BASE UPGRADES")

	local subSize = PanelShell.Text(13)
	local sub = Instance.new("TextLabel")
	sub.Name = "PassiveIncome"
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromOffset(16, title.Position.Y.Offset + title.Size.Y.Offset)
	sub.Size = UDim2.new(1, -(TAP + 28), 0, subSize + 4)
	sub.Font = Enum.Font.GothamBold
	sub.TextSize = subSize
	sub.TextColor3 = Constants.Colors.Cash
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextTruncate = Enum.TextTruncate.AtEnd
	sub.Text = ""
	sub.Parent = panel
	subLabel = sub

	PanelShell.CloseButton(panel, function()
		setOpen(false)
	end)

	local listTop = math.max(TAP + 8, sub.Position.Y.Offset + subSize + 10)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.Position = UDim2.fromOffset(10, listTop)
	scroll.Size = UDim2.new(1, -20, 1, -(listTop + 10))
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = if isTouch then 6 else 4
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.Parent = panel
	listFrame = scroll

	shell = PanelShell.Attach({
		Id = PANEL_ID,
		Screen = gui,
		Panel = panel,
		IsOpen = function(): boolean
			return menuOpen
		end,
		Close = function()
			setOpen(false)
		end,
	})

	Remotes.BindEvent(Constants.RemoteNames.BaseStateUpdate, function(base: Types.BaseStatePayload)
		if typeof(base) ~= "table" then
			return
		end
		upgrades = base.Upgrades or upgrades
		if typeof(base.PassiveIncomePerTick) == "number" then
			passivePerTick = base.PassiveIncomePerTick
		end
		refreshSubtitle()
		if menuOpen then
			refreshList()
		end
	end)

	Remotes.BindEvent(Constants.RemoteNames.SoldierStateUpdate, function(payload: any)
		if typeof(payload) == "table" then
			trainingPerTick = tonumber(payload.TrainingIncomePerTick) or trainingPerTick
			refreshSubtitle()
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

	Remotes.BindEvent(Constants.RemoteNames.EconomyUpdate, function(payload: Types.EconomyUpdatePayload)
		applyCash(payload.Cash)
	end)

	player:GetAttributeChangedSignal("WE_Cash"):Connect(function()
		applyCash(player:GetAttribute("WE_Cash"))
	end)
	applyCash(player:GetAttribute("WE_Cash"))

	Remotes.BindEvent(Constants.RemoteNames.PlayerStateUpdate, function(state: Types.PlayerStatePayload)
		applyCash(state.Cash)
		if state.Base then
			upgrades = state.Base.Upgrades
			if typeof(state.Base.PassiveIncomePerTick) == "number" then
				passivePerTick = state.Base.PassiveIncomePerTick
			end
		end
		if typeof(state.TrainingIncomePerTick) == "number" then
			trainingPerTick = state.TrainingIncomePerTick
		end
		refreshSubtitle()
	end)

	local baseKey: Enum.KeyCode = HudConfig.Keys.Base or Enum.KeyCode.B
	UserInputService.InputBegan:Connect(function(input, gp)
		-- Respect chat / processed UI (gp true while typing in chat).
		if gp then
			return
		end
		if input.KeyCode == baseKey then
			setOpen(not menuOpen)
		end
	end)

	refreshSubtitle()
	print("[WAR EMPIRE] BaseController ready (B / terminal / tutorial open the menu; BUY via Activated)")
end

return BaseController
