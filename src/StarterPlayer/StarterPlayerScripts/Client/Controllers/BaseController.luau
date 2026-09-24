--!strict
--[[ Base overview panel. v71 console-only buying: it NEVER buys.
	Each row: level, next cost or the first unmet requirement, income; the row button is GO — a guide line to that
	structure's console on YOUR plot (Modules/ConsoleWaypoint) — and the panel closes. Buying happens at the console
	only (WorldPromptController BUY button / the console prompt); the server refuses remote buys (NotAtConsole).
	v70 "clean screen" (spec §3.7 / §3.8):
	  * No HUD button any more: the "BASE [B]" / "Base Upgrades [B]" CTA and the stale first-join hint toasts
	    are gone. The menu opens from B (HudConfig.Keys.Base, respects gameProcessed / chat), the Command Center
	    map-table terminal (WE_OpenPanel "Base") and the tutorial CTA.
	  * Passive income moved here from the cash pill: the subtitle reads "+$N/tick passive · +$N/tick training".
	  * A registered Modal panel (HudLayout id "Base") with the black dim; one HUD scale + safe area.
	v72 tycoon guide (TycoonGuideConfig.Enabled):
	  * rows "Build $600  +$3.3/s" / "Lv 1 -> 2  $2,000  +$4.2/s" (TycoonGuideConfig.Text; the rate is
	    TycoonMath.PerSecText(StepGainPerTick(id, level, WE_IncomeMult)), floored so it never over-promises);
	  * the server's pick (Player attribute WE_NextBuy) gets a gold outline and a gold NEXT badge, and the list opens
	    scrolled to it;
	  * war businesses (BaseConfig Kind "Business", only while BusinessConfig.Enabled) sit under a WAR BUSINESSES
	    header after the buildings;
	  * subtitle "Income $46/s  buy at each console" from WE_IncomePerSec (what the ATM really receives).
	  With the guide on, "+$N/s" replaces the old "+N/t" row suffix; with the guide off the rows and the subtitle
	  read exactly as before v72 (flags off = HEAD).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local BaseConfig = require(Shared.Configs.BaseConfig)
local EconomyConfig = require(Shared.Configs.EconomyConfig)
local HudConfig = require(Shared.Configs.HudConfig)
local ConsoleBuyConfig = require(Shared.Configs.ConsoleBuyConfig)
local BusinessConfig = require(Shared.Configs.BusinessConfig)
local TycoonGuideConfig = require(Shared.Configs.TycoonGuideConfig)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)
local TycoonMath = require(Shared.Util.TycoonMath)
local Types = require(Shared.Types)

local PanelShell = require(script.Parent.Parent.Modules.PanelShell)
local HudLayout = require(script.Parent.Parent.Modules.HudLayout)
local NotificationController = require(script.Parent.NotificationController)
local ConsoleWaypoint = require(script.Parent.Parent.Modules.ConsoleWaypoint)

local BaseController = {}

local PANEL_ID = "Base"
local GUIDE_ON = TycoonGuideConfig.Enabled -- v72 rows / NEXT / subtitle
local GT = TycoonGuideConfig.Text
local BIZ_ORDER = 1000 -- LayoutOrder base of the WAR BUSINESSES header + business rows (after the buildings)
local NEXT_INK = Color3.fromRGB(28, 22, 6) -- dark text on the gold NEXT badge

local player = Players.LocalPlayer
local isTouch = UserInputService.TouchEnabled
local upgrades: { [string]: number } = {}
local cash = 0
local passivePerTick = 0
local trainingPerTick = 0
local myPlotId: number? = nil -- BaseStateUpdate.PlotId / PlayerStateUpdate.Base.PlotId (nil until the plot is known)
local menuOpen = false
local screenGui: ScreenGui? = nil
local listFrame: ScrollingFrame? = nil
local subLabel: TextLabel? = nil
local shell: PanelShell.Shell? = nil

local setOpen: (boolean) -> ()

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

local function attrNum(name: string, default: number): number
	local v = tonumber(player:GetAttribute(name) :: any)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then
		return default
	end
	return v
end

-- the passive-income hint that used to sit on the cash pill ("+N$/tick")
local function refreshSubtitle()
	local sub = subLabel
	if not sub then
		return
	end
	if GUIDE_ON then
		-- v72: "Income $46/s  buy at each console" = what the ATM really receives (server-stamped, multipliers in);
		-- before the first stamp: the server's per-tick figures (pre-multiplier, so it can only under-read)
		local perSec = attrNum("WE_IncomePerSec", 0)
		if perSec <= 0 then
			perSec = (passivePerTick + trainingPerTick) / TycoonMath.TickSeconds()
		end
		sub.Text = string.format(GT.PanelSubtitle, string.format(GT.Rate, TycoonMath.RateText(perSec)))
		return
	end
	local tickSec = (EconomyConfig.PassiveIncome and tonumber(EconomyConfig.PassiveIncome.TickSeconds)) or 5
	local parts = { string.format("+$%s/tick passive", commas(passivePerTick)) }
	if trainingPerTick > 0 then
		table.insert(parts, string.format("+$%s/tick training", commas(trainingPerTick)))
	end
	sub.Text = table.concat(parts, " · ") .. string.format("  (every %ds)", tickSec)
end

-- v72: width (v) of the gold NEXT badge for text size `size`
local function badgeWidth(text: string, size: number): number
	local ok, v = pcall(function(): Vector2
		return TextService:GetTextSize(text, size, Enum.Font.GothamBold, Vector2.new(1000, 1000))
	end)
	local w = if ok and typeof(v) == "Vector2" then v.X else #text * size * 0.72
	return math.ceil(w) + 16
end

-- v72 row copy: "Build $600  +$3.3/s" / "Lv 1 -> 2  $2,000  +$4.2/s". A step that adds no income names what it
-- unlocks instead of a "+$0/s".
local function guideRowText(structureId: string, level: number, cost: number, mult: number): string
	local gainPerTick = TycoonMath.StepGainPerTick(structureId, level, mult)
	local tail = if gainPerTick > 0 then TycoonMath.PerSecText(gainPerTick) else (TycoonMath.UnlockText(structureId, level + 1) or "")
	local text = if level == 0
		then string.format(GT.PanelRowBuild, TycoonMath.ShortCash(cost), tail)
		else string.format(GT.PanelRowUpgrade, level, level + 1, TycoonMath.ShortCash(cost), tail)
	return (string.gsub(text, "%s+$", ""))
end

local function refreshList(scrollToNext: boolean?)
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
	local btnW = if PanelShell.IsTouch() then 120 else 88 -- GO / MAX chip (was the "BUY $N +N/t" button)

	-- v72 guide: the server's pick (WE_NextBuy) and the income multiplier the rows' +$/s use
	local nextId: string? = nil
	local mult = 1
	if GUIDE_ON then
		nextId = TycoonMath.Decode(player:GetAttribute("WE_NextBuy"))
		mult = attrNum("WE_IncomeMult", 1)
		if mult <= 0 then
			mult = 1
		end
	end
	local listPad = 6 -- the UIListLayout Padding below
	local placed: { { Order: number, H: number, Next: boolean } } = {} -- for scrolling to the NEXT row
	local headerDone = false

	for order, structureId in ipairs(BaseConfig.StructureOrder) do
		local def = BaseConfig.Structures[structureId]
		if def then
			local level = upgrades[structureId] or 0
			local nextLevel = level + 1
			local cost = if nextLevel <= def.MaxLevel then def.Costs[nextLevel] else nil
			local isBusiness = def.Kind ~= nil and def.Kind == BusinessConfig.Kind
			local isNext = nextId ~= nil and structureId == nextId
			local layoutOrder = if isBusiness then BIZ_ORDER + order else order

			-- v72: one WAR BUSINESSES header above the first business row
			if isBusiness and not headerDone then
				headerDone = true
				local headerH = titleSize + 14
				local header = Instance.new("Frame")
				header.Name = "BusinessHeader"
				header.Size = UDim2.new(1, -8, 0, headerH)
				header.BackgroundTransparency = 1
				header.BorderSizePixel = 0
				header.LayoutOrder = BIZ_ORDER
				header.Parent = listFrame
				local ht = Instance.new("TextLabel")
				ht.Name = "Label"
				ht.BackgroundTransparency = 1
				ht.Position = UDim2.fromOffset(12, 0)
				ht.Size = UDim2.new(1, -24, 1, 0)
				ht.Font = Enum.Font.GothamBold
				ht.TextSize = titleSize
				ht.TextColor3 = Constants.Colors.Gold
				ht.TextXAlignment = Enum.TextXAlignment.Left
				ht.TextYAlignment = Enum.TextYAlignment.Bottom
				ht.TextTruncate = Enum.TextTruncate.AtEnd
				ht.Text = GT.PanelHeader
				ht.Parent = header
				table.insert(placed, { Order = BIZ_ORDER, H = headerH, Next = false })
			end

			local row = Instance.new("Frame")
			row.Name = structureId
			row.Size = UDim2.new(1, -8, 0, rowH)
			row.BackgroundColor3 = Constants.Colors.Background
			row.BorderSizePixel = 0
			row.LayoutOrder = layoutOrder
			row.Parent = listFrame
			corner(row, 8)
			table.insert(placed, { Order = layoutOrder, H = rowH, Next = isNext })

			-- Highlight first purchasable row (Command Center) when still L0; v72 guide: the server's pick instead
			if (GUIDE_ON and isNext) or (not GUIDE_ON and structureId == "CommandCenter" and level == 0) then
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

			-- v72: gold NEXT badge on the pick's row (between the title and GO)
			if GUIDE_ON and isNext then
				local badgeSize = PanelShell.Text(13)
				local bw = badgeWidth(GT.NextTag, badgeSize)
				local badge = Instance.new("TextLabel")
				badge.Name = "NextBadge"
				badge.AnchorPoint = Vector2.new(1, 0)
				badge.Position = UDim2.new(1, -(btnW + 16), 0, 6)
				badge.Size = UDim2.fromOffset(bw, titleSize + 6)
				badge.BackgroundColor3 = TycoonGuideConfig.ConsoleTag.NextColor
				badge.BorderSizePixel = 0
				badge.Font = Enum.Font.GothamBold
				badge.TextSize = badgeSize
				badge.TextColor3 = NEXT_INK
				badge.Text = GT.NextTag
				badge.Parent = row
				corner(badge, 6)
				title.Size = UDim2.new(1, -(btnW + 28 + bw + 8), 0, titleSize + 6)
			end

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
				btn.Text = ConsoleBuyConfig.Text.Max
				btn.BackgroundColor3 = Color3.fromRGB(50, 55, 60)
				btn.AutoButtonColor = false
				btn.Active = false
			else
				-- v71: overview only. GO draws a guide line to this structure's console on your plot; buying happens
				-- there (BUY button / hold the console prompt). The server refuses a remote buy (NotAtConsole).
				local lockedBy: string? = nil
				for _, req in ipairs(def.Requires or {}) do
					if (upgrades[req.StructureId] or 0) < req.Level then
						local rdef = BaseConfig.Structures[req.StructureId]
						lockedBy = string.format(ConsoleBuyConfig.Text.Needs, if rdef then rdef.DisplayName else req.StructureId, req.Level)
						break
					end
				end
				local price = "$" .. commas(cost)
				if lockedBy then
					desc.Text = lockedBy
					desc.TextColor3 = Color3.fromRGB(235, 120, 110)
				elseif GUIDE_ON then
					desc.Text = guideRowText(structureId, level, cost, mult)
				else
					-- guide off (flags off = HEAD): the pre-v72 per-tick suffix stays until the lead flips the guide on
					local rates = EconomyConfig.PassiveIncome and EconomyConfig.PassiveIncome.PerLevelRates
					local rate = if typeof(rates) == "table" then (tonumber(rates[structureId]) or 0) else 0
					local legacySuffix = if rate > 0 then string.format("  +%s/t", tostring(rate)) else ""
					if level == 0 then
						desc.Text = string.format(ConsoleBuyConfig.Text.Build, price) .. legacySuffix
					else
						desc.Text = string.format(ConsoleBuyConfig.Text.Upgrade, level, nextLevel, price) .. legacySuffix
					end
				end
				btn.Text = ConsoleBuyConfig.Text.Go
				-- accent when unlocked and affordable; grey otherwise but still tappable (GO finds the console)
				local ready = lockedBy == nil and cash >= cost
				btn.BackgroundColor3 = if ready then Constants.Colors.Accent else Color3.fromRGB(58, 62, 68)
				btn.Active = true
				UIUtil.EnsureMinTouch(btn, TAP)
				local function onGo()
					if ConsoleWaypoint.Show(structureId, myPlotId) then
						setOpen(false)
						NotificationController.Show(string.format(ConsoleBuyConfig.Text.WaypointSet, def.DisplayName), "Info", 2)
					else
						NotificationController.Show(ConsoleBuyConfig.Text.NoConsole, "Warn", 2.5)
					end
				end
				-- v67: Activated only (fires once for mouse, touch and gamepad)
				btn.Activated:Connect(onGo)
			end
			btn.Parent = row
		end
	end

	local l = listFrame:FindFirstChildOfClass("UIListLayout")
	if l then
		listFrame.CanvasSize = UDim2.fromOffset(0, l.AbsoluteContentSize.Y + 12)
	end

	-- v72: open on the NEXT row (a phone shows about 3 rows; the pick is often a business at the bottom)
	if GUIDE_ON and scrollToNext then
		table.sort(placed, function(a, b)
			return a.Order < b.Order
		end)
		local y = 0
		local nextH = 0
		local headerY: number? = nil
		local found = false
		for _, p in ipairs(placed) do
			if p.Order == BIZ_ORDER then
				headerY = y
			end
			if p.Next then
				found = true
				nextH = p.H
				break
			end
			y += p.H + listPad
		end
		local lf = listFrame :: ScrollingFrame
		if found then
			local total = 0
			for _, p in ipairs(placed) do
				total += p.H + listPad
			end
			-- AbsoluteWindowSize is real px; the canvas is in v (the panel gui carries the one HUD UIScale)
			local window = lf.AbsoluteWindowSize.Y / math.max(HudLayout.Scale(), 0.01)
			local maxY = math.max(0, total + 12 - window)
			local target = y - listPad
			-- a business pick: start at the WAR BUSINESSES header while the NEXT row still fits below it
			if headerY ~= nil and y + nextH - headerY <= window then
				target = headerY
			end
			lf.CanvasSize = UDim2.fromOffset(0, math.max(lf.CanvasSize.Y.Offset, total + 12))
			lf.CanvasPosition = Vector2.new(0, math.clamp(target, 0, maxY))
		else
			lf.CanvasPosition = Vector2.new(0, 0)
		end
	end
end

function setOpen(open: boolean)
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
		refreshList(true)
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

	local title = PanelShell.Title(panel, "YOUR BASE")

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

	-- v71: how buying works now (the rows only show the way)
	local how = Instance.new("TextLabel")
	how.Name = "HowToBuy"
	how.BackgroundTransparency = 1
	how.Position = UDim2.fromOffset(16, sub.Position.Y.Offset + subSize + 4)
	how.Size = UDim2.new(1, -(TAP + 28), 0, subSize + 4)
	how.Font = Enum.Font.GothamMedium
	how.TextSize = subSize
	how.TextColor3 = PanelShell.Colors.Muted
	how.TextXAlignment = Enum.TextXAlignment.Left
	how.TextTruncate = Enum.TextTruncate.AtEnd
	how.Text = ConsoleBuyConfig.Text.PanelSubtitle
	how.Parent = panel

	PanelShell.CloseButton(panel, function()
		setOpen(false)
	end)

	local listTop = math.max(TAP + 8, how.Position.Y.Offset + subSize + 10)
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
		if typeof(base.PlotId) == "number" then
			myPlotId = base.PlotId
		end
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
			if typeof(state.Base.PlotId) == "number" then
				myPlotId = state.Base.PlotId
			end
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

	-- v72 guide: the server re-picks / re-stamps these (at most every few seconds): subtitle + rows follow
	if GUIDE_ON then
		player:GetAttributeChangedSignal("WE_IncomePerSec"):Connect(refreshSubtitle)
		local function relist()
			if menuOpen then
				refreshList()
			end
		end
		player:GetAttributeChangedSignal("WE_NextBuy"):Connect(relist)
		player:GetAttributeChangedSignal("WE_IncomeMult"):Connect(relist)
	end

	refreshSubtitle()
	print("[WAR EMPIRE] BaseController ready (B / terminal / tutorial open the overview; rows GO to the console, never buy)")
end

return BaseController
