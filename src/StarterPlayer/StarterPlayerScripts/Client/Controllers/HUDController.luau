--!strict
--[[
	HUDController — the v70 "clean screen" HUD shell (spec §3.1-3.3). Numbers: Shared/Configs/HudConfig.luau;
	scale / insets / flags / badges / cash-float plumbing: Client/Modules/HudLayout.luau; icons: HudIcons.luau.

	WarEmpireHUD (DisplayOrder 55, the shared "MobileScale" UIScale, CoreUISafeInsets)
	  Rail          5 tiles down the left edge (Shop · Rebirth · Army · Garage · Missions) + badges; desktop key hints
	  CurrencyPill  bottom-left: cash icon · number (count-up) · green + (cash packs); "+$141" floats rise from it
	WE_TopStrip (DisplayOrder 56, the Roblox topbar row, real px — Roblox's own buttons are 44 px there too)
	  LevelChip (tap / hover → the GoalLabel tooltip) · SettingsGear · ShieldChip (while WE_ShieldUntil runs)
	  CompassController adds the compass chip at the right end.

	REMOVED from the screen (spec §3.7; where each thing lives now):
	  LevelPanel goal / rebirth text → the level-chip tooltip (GoalLabel) + the Rebirth "!" badge
	  level-up / near-prestige banners → chip pulse / Rebirth tile pulse (the server's reward toast is the text)
	  SeasonLabel → Progression panel header · SpinnerButton → Missions badge + the Missions panel claim row
	  PassiveHint → Base panel subtitle · GoldLabel "◆ 0" → Shop header (gold > 0)
	  PendingLabel "+$N pending" → the in-world ATM screen · the 7-tile MobileActionBar dock → Rail + TopStrip gear
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local UIUtil = require(Shared.Util.UIUtil)
local HudConfig = require(Shared.Configs.HudConfig)
local LevelConfig = require(Shared.Configs.LevelConfig)
local PrestigeConfig = require(Shared.Configs.PrestigeConfig)
local HudLayout = require(script.Parent.Parent.Modules.HudLayout)
local HudIcons = require(script.Parent.Parent.Modules.HudIcons)

local HUDController = {}

-- One rail tile binding (UIController): Id = HudConfig.Rail.Tiles[].Id; Name = the pinned child name ("DockMissions").
export type RailAction = { Id: string, Name: string?, OnClick: () -> () }

type FloatRec = { Label: TextLabel, Stroke: UIStroke, Amount: number, Last: number, Token: number, Tweens: { Tween } }

local player = Players.LocalPlayer
local Colors = HudConfig.Colors
local Fonts = HudConfig.Fonts
local TS = HudConfig.TopStrip

local _gui: ScreenGui? = nil
local topArea: Frame? = nil

-- TopStrip
local levelLabel: TextLabel? = nil
local xpBarFill: Frame? = nil
local chipStroke: UIStroke? = nil
local chipPop: UIScale? = nil
local goalTip: Frame? = nil
local goalLabel: TextLabel? = nil
local rebirthLabel: TextLabel? = nil
local tipToken = 0
local shieldChip: Frame? = nil
local shieldText: TextLabel? = nil
local shieldLoop = false

-- Rail
local rail: Frame? = nil
local railGrid: UIGridLayout? = nil
local railTiles: { [string]: TextButton } = {}
local railCount = 0

-- Cash pill
local pill: Frame? = nil
local cashLabel: TextLabel? = nil
local cashPop: UIScale? = nil
local plusSlot: Frame? = nil
local cashTarget: number? = nil -- last synced cash; nil until the first sync (the label shows "$…")
local countFrom, countTo, countElapsed, counting = 0, 0, 0, false
local flashToken = 0
local floats: { FloatRec } = {}
local floatBirths: { number } = {}
local lastBuyVisibleAt = -math.huge
-- ONE spend float per purchase: WorldPromptController floats console / Base buys from PurchaseResult (the exact
-- cost) through HudLayout.CashFloat; the cash-drop float (setCash) is only for drops nothing else explained.
local SPEND_FLOAT_DELAY = 0.35 -- s after a cash drop: a stale sync that bounces back, or PurchaseResult, lands first
local lastExplicitSpendAt = -math.huge
local lastDropFloat: { Amount: number, At: number }? = nil

local shopOpener: (() -> ())? = nil
local settingsOpener: (() -> ())? = nil

-- badge inputs
local spinnerReady = false
local missionClaimables = 0
local loginClaimable = false
local nearPulseLevel = -1
local feedsStarted = false

---------------------------------------------------------------------------------------------------------------
-- small builders
---------------------------------------------------------------------------------------------------------------

local function isTouch(): boolean
	return HudLayout.IsTouch()
end

local function label(parent: Instance?, name: string, font: Enum.Font, size: number, color: Color3, text: string): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.Font = font
	t.TextSize = size
	t.TextColor3 = color
	t.Text = text
	t.Active = false
	if parent then
		t.Parent = parent
	end
	return t
end

local function hList(parent: Instance, padding: number, align: Enum.VerticalAlignment?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.VerticalAlignment = align or Enum.VerticalAlignment.Center
	l.Padding = UDim.new(0, padding)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = parent
	return l
end

local function padding(parent: Instance, left: number, right: number, top: number?, bottom: number?): UIPadding
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, left)
	p.PaddingRight = UDim.new(0, right)
	p.PaddingTop = UDim.new(0, top or 0)
	p.PaddingBottom = UDim.new(0, bottom or 0)
	p.Parent = parent
	return p
end

local function chipBase(inst: GuiObject)
	inst.BackgroundColor3 = TS.Bg
	inst.BackgroundTransparency = TS.BgTransparency
	inst.BorderSizePixel = 0
	UIUtil.Corner(inst, TS.Corner)
end

local function withCommas(n: number): string
	local s = tostring(math.floor(math.abs(n) + 0.5))
	s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return if n < 0 then "-" .. s else s
end

local ABBREV: { { Value: number, Suffix: string } } = {
	{ Value = 1e12, Suffix = "T" },
	{ Value = 1e9, Suffix = "B" },
	{ Value = 1e6, Suffix = "M" },
	{ Value = 1e3, Suffix = "K" },
}

-- "50,015,946"; at/above HudConfig.CashPill.AbbreviateAbove → "1.23B" (no "$": the pill's icon says cash)
local function formatCash(n: number): string
	local P = HudConfig.CashPill
	local v = math.floor((tonumber(n) or 0) + 0.5)
	local body = withCommas(v)
	if math.abs(v) >= P.AbbreviateAbove then
		for _, a in ipairs(ABBREV) do
			if math.abs(v) >= a.Value then
				body = string.format("%.2f%s", v / a.Value, a.Suffix)
				break
			end
		end
	end
	return if P.ShowDollarSign then "$" .. body else body
end

local function floatText(amount: number): string
	return (if amount >= 0 then "+$" else "-$") .. withCommas(math.abs(amount))
end

local function serverNow(): number
	local ok, t = pcall(function(): number
		return Workspace:GetServerTimeNow()
	end)
	if ok and typeof(t) == "number" and t > 0 then
		return t
	end
	return os.time()
end

---------------------------------------------------------------------------------------------------------------
-- TopStrip (WE_TopStrip): level chip + GoalLabel tooltip, settings gear, shield chip
---------------------------------------------------------------------------------------------------------------

local function ensureTopStrip(): Frame?
	local area = topArea
	if area and area.Parent then
		return area
	end
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil
	end
	local existing = pg:FindFirstChild("WE_TopStrip")
	local screen: ScreenGui
	if existing and existing:IsA("ScreenGui") then
		screen = existing
	else
		screen = Instance.new("ScreenGui")
		screen.Name = "WE_TopStrip"
		HudLayout.ApplyScreen(screen, { Insets = "Topbar", DisplayOrder = HudConfig.DisplayOrder.WE_TopStrip })
		screen.Parent = pg
	end
	local a = HudLayout.TopbarArea(screen)
	topArea = a
	return a
end

local function showGoalTip(seconds: number?)
	local tip = goalTip
	if not tip then
		return
	end
	tipToken += 1
	local my = tipToken
	tip.Visible = true
	if seconds then
		task.delay(seconds, function()
			if tipToken == my and goalTip then
				goalTip.Visible = false
			end
		end)
	end
end

local function hideGoalTip()
	tipToken += 1
	if goalTip then
		goalTip.Visible = false
	end
end

local function buildTopStrip()
	local area = ensureTopStrip()
	if not area then
		warn("[HUDController] TopStrip: no PlayerGui")
		return
	end
	local L = TS.Level

	local group = Instance.new("Frame")
	group.Name = "LeftGroup"
	group.AnchorPoint = Vector2.new(0, 1)
	group.Position = UDim2.new(0, TS.EdgePad, 1, -TS.BottomPad + TS.YNudge)
	group.Size = UDim2.fromOffset(0, TS.Height)
	group.AutomaticSize = Enum.AutomaticSize.X
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	group.Active = false
	hList(group, TS.Gap)

	-- Level chip: "LV 7" + XP bar. Tap / hover → the GoalLabel tooltip (goal + rebirth summary).
	local chip = Instance.new("TextButton")
	chip.Name = "LevelChip"
	chip.LayoutOrder = 1
	chip.Size = UDim2.fromOffset(L.MinWidth, TS.Height)
	chip.AutomaticSize = Enum.AutomaticSize.X
	chip.AutoButtonColor = false
	chip.Text = ""
	chip.Active = true
	chip.Selectable = true
	chipBase(chip)
	padding(chip, 14, 14)
	hList(chip, 8)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "PulseStroke"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Constants.Colors.GoldBright
	stroke.Thickness = 2
	stroke.Transparency = 1
	stroke.Parent = chip
	chipStroke = stroke
	local pop = Instance.new("UIScale")
	pop.Name = "Pulse"
	pop.Parent = chip
	chipPop = pop

	local cap = label(chip, "LevelCaption", Fonts.Body, L.CaptionSize, Colors.White, "LV")
	cap.TextTransparency = 0.28
	cap.Size = UDim2.new(0, 0, 1, 0)
	cap.AutomaticSize = Enum.AutomaticSize.X
	cap.LayoutOrder = 1
	local num = label(chip, "LevelLabel", Fonts.Display, L.NumberSize, Colors.White, "1")
	num.Size = UDim2.new(0, 0, 1, 0)
	num.AutomaticSize = Enum.AutomaticSize.X
	num.LayoutOrder = 2
	UIUtil.TextOutline(num, TS.TextStroke)
	levelLabel = num
	local barBg = Instance.new("Frame")
	barBg.Name = "XPBarBG"
	barBg.LayoutOrder = 3
	barBg.Size = UDim2.fromOffset(L.BarSize.X, L.BarSize.Y)
	barBg.BackgroundColor3 = L.BarBg
	barBg.BackgroundTransparency = L.BarBgTransparency
	barBg.BorderSizePixel = 0
	barBg.Active = false
	barBg.Parent = chip
	UIUtil.Corner(barBg, math.ceil(L.BarSize.Y / 2))
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Colors.XP
	fill.BorderSizePixel = 0
	fill.Active = false
	fill.Parent = barBg
	UIUtil.Corner(fill, math.ceil(L.BarSize.Y / 2))
	xpBarFill = fill

	-- GoalLabel tooltip: a small dark card under the chip (line 1 goal, line 2 rebirth summary)
	local tip = Instance.new("Frame")
	tip.Name = "GoalTip"
	tip.Position = UDim2.new(0, TS.EdgePad, 1, L.TipGap)
	tip.Size = UDim2.fromOffset(L.TipMaxWidth, 0)
	tip.AutomaticSize = Enum.AutomaticSize.Y
	tip.BackgroundColor3 = TS.Bg
	tip.BackgroundTransparency = 0.08
	tip.BorderSizePixel = 0
	tip.Active = false
	tip.Visible = false
	tip.ZIndex = 5
	UIUtil.Corner(tip, 10)
	padding(tip, 10, 10, 8, 8)
	local tipList = Instance.new("UIListLayout")
	tipList.FillDirection = Enum.FillDirection.Vertical
	tipList.Padding = UDim.new(0, 3)
	tipList.SortOrder = Enum.SortOrder.LayoutOrder
	tipList.Parent = tip
	local goal = label(tip, "GoalLabel", Fonts.Body, L.TipGoalSize, Colors.White, "")
	goal.Size = UDim2.new(1, 0, 0, 0)
	goal.AutomaticSize = Enum.AutomaticSize.Y
	goal.TextWrapped = true
	goal.TextXAlignment = Enum.TextXAlignment.Left
	goal.LayoutOrder = 1
	goal.ZIndex = 6
	goalLabel = goal
	local reb = label(tip, "RebirthLabel", Fonts.BodyMedium, L.TipRebirthSize, Colors.Gold, "")
	reb.Size = UDim2.new(1, 0, 0, 0)
	reb.AutomaticSize = Enum.AutomaticSize.Y
	reb.TextWrapped = true
	reb.TextXAlignment = Enum.TextXAlignment.Left
	reb.LayoutOrder = 2
	reb.ZIndex = 6
	rebirthLabel = reb
	goalTip = tip

	chip.Activated:Connect(function()
		if goalTip and goalTip.Visible then
			hideGoalTip()
		else
			showGoalTip(L.TapShowsGoalSeconds)
		end
	end)
	chip.MouseEnter:Connect(function()
		if not isTouch() then
			showGoalTip(nil)
		end
	end)
	chip.MouseLeave:Connect(function()
		if not isTouch() then
			hideGoalTip()
		end
	end)
	chip.Parent = group

	-- Settings gear (the only way into Settings: no rail tile, no key)
	local G = TS.Settings
	local gear = Instance.new("TextButton")
	gear.Name = "SettingsGear"
	gear.LayoutOrder = 2
	gear.Size = UDim2.fromOffset(G.Size, G.Size)
	gear.AutoButtonColor = false
	gear.Text = ""
	gear.Active = true
	gear.Selectable = true
	chipBase(gear)
	HudIcons.Make("Gear", gear, {
		Size = UDim2.fromOffset(24, 24),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = G.IconColor,
		Fill = TS.Bg,
		ZIndex = 2,
	})
	gear.Activated:Connect(function()
		if settingsOpener then
			local ok, err = pcall(settingsOpener :: any)
			if not ok then
				warn("[HUDController] settings gear:", err)
			end
		end
	end)
	gear.Parent = group

	-- Shield chip (raid victim shield): cyan shield + "9:12" while WE_ShieldUntil is in the future
	local SH = TS.Shield
	local sh = Instance.new("Frame")
	sh.Name = "ShieldChip"
	sh.LayoutOrder = 3
	sh.Size = UDim2.fromOffset(0, TS.Height)
	sh.AutomaticSize = Enum.AutomaticSize.X
	sh.Active = false
	sh.Visible = false
	chipBase(sh)
	padding(sh, 10, 14)
	hList(sh, 6)
	HudIcons.Make("Shield", sh, { Name = "Icon", Size = UDim2.fromOffset(SH.IconSize, SH.IconSize), Color = SH.IconColor, LayoutOrder = 1 })
	local st = label(sh, "ShieldText", Fonts.Display, SH.TextSize, Colors.White, "")
	st.Size = UDim2.new(0, 0, 1, 0)
	st.AutomaticSize = Enum.AutomaticSize.X
	st.LayoutOrder = 2
	UIUtil.TextOutline(st, TS.TextStroke)
	sh.Parent = group
	shieldChip = sh
	shieldText = st

	tip.Parent = area
	group.Parent = area
	HudLayout.SetRect("LevelChip", chip)
end

local function shieldLeft(): number
	local v = tonumber(player:GetAttribute(TS.Shield.Attribute)) or 0
	return math.max(0, v - serverNow())
end

local function refreshShield()
	local chip, txt = shieldChip, shieldText
	if not chip or not txt then
		return
	end
	local left = shieldLeft()
	if left <= 0 then
		chip.Visible = false
		return
	end
	local s = math.ceil(left)
	txt.Text = string.format("%d:%02d", s // 60, s % 60)
	chip.Visible = true
	if shieldLoop then
		return
	end
	shieldLoop = true
	task.spawn(function()
		while shieldLeft() > 0 do
			task.wait(1)
			local c, t = shieldChip, shieldText
			if not c or not t then
				break
			end
			local r = math.ceil(shieldLeft())
			t.Text = string.format("%d:%02d", r // 60, r % 60)
		end
		shieldLoop = false
		if shieldChip and shieldLeft() <= 0 then
			shieldChip.Visible = false
		end
	end)
end

---------------------------------------------------------------------------------------------------------------
-- Rail (WarEmpireHUD › Rail): one UIGridLayout column of MakeRailTile cells, vertically centred between the
-- content top and the cash pill; wraps to a 2nd column when a screen is too short (800x360 → 4 + 1).
---------------------------------------------------------------------------------------------------------------

local function layoutRail()
	local host, grid = rail, railGrid
	if not host or not grid then
		return
	end
	local R = HudConfig.Rail
	local touch = isTouch()
	local T = if touch then R.Tile else R.TileDesktop
	local ov = if touch then R.LabelOverhang else R.LabelOverhangDesktop
	local gap = if touch then R.Gap else R.GapDesktop -- dock≤8: rail gap 5/8 v
	local pillH = if touch then HudConfig.CashPill.Height else HudConfig.CashPill.HeightDesktop
	local n = math.max(1, railCount)
	local cv = HudLayout.ContentSizeV()
	local bandTop = R.TopReserve
	local bandBot = cv.Y - (HudConfig.CashPill.Bottom + pillH + HudConfig.Edge)
	local bandH = math.max(0, bandBot - bandTop)
	local perCol = math.clamp(math.floor((bandH + gap) / (T + ov + gap)), 1, n)
	local cols = math.ceil(n / perCol)
	local colH = perCol * (T + ov) + (perCol - 1) * gap
	local colGap = gap + R.ColumnGap
	local top = math.clamp(bandTop + R.CenterY * bandH - colH / 2, bandTop, math.max(bandTop, bandBot - colH))
	grid.CellSize = UDim2.fromOffset(T, T + ov)
	grid.CellPadding = UDim2.fromOffset(colGap, gap)
	grid.FillDirectionMaxCells = perCol
	host.Position = UDim2.fromOffset(R.Left, top)
	host.Size = UDim2.fromOffset(cols * T + (cols - 1) * colGap, colH)
end

local function tileDef(id: string): any?
	for _, t in ipairs(HudConfig.Rail.Tiles) do
		if t.Id == id then
			return t
		end
	end
	return nil
end

-- desktop: hovering a tile shows "Shop [P]" after HudConfig.Rail.KeyHintDelay
local function addKeyHint(btn: TextButton, id: string, def: any?)
	if isTouch() then
		return
	end
	local key = (HudConfig.Keys :: any)[id] or (def and def.Key)
	if typeof(key) ~= "EnumItem" then
		return
	end
	local R = HudConfig.Rail
	local text = string.format("%s [%s]", if def then tostring(def.Label) else id, key.Name)
	local hint = label(nil, "KeyHint", Fonts.Body, R.KeyHintSize, Colors.White, text)
	hint.AnchorPoint = Vector2.new(0, 0.5)
	hint.Position = UDim2.new(1, 8, 0, R.TileDesktop / 2)
	hint.AutomaticSize = Enum.AutomaticSize.XY
	hint.BackgroundColor3 = TS.Bg
	hint.BackgroundTransparency = 0.15
	hint.Visible = false
	hint.ZIndex = 40
	UIUtil.Corner(hint, 8)
	padding(hint, 8, 8, 4, 4)
	hint.Parent = btn
	local token = 0
	btn.MouseEnter:Connect(function()
		token += 1
		local my = token
		task.delay(R.KeyHintDelay, function()
			if my == token then
				hint.Visible = true
			end
		end)
	end)
	local function hide()
		token += 1
		hint.Visible = false
	end
	btn.MouseLeave:Connect(hide)
	btn.Activated:Connect(hide)
end

local function pulseTile(id: string, scale: number)
	local btn = railTiles[id]
	local press = btn and btn:FindFirstChild("Press", true)
	if press and press:IsA("UIScale") then
		press.Scale = scale
		TweenService:Create(press, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

--[[ Rail badge: "!" (gold ready style), a count ("3"), or nil to clear. Anyone else calls HudLayout.SetBadge. ]]
function HUDController.SetRailBadge(id: string, text: string?)
	HudLayout.SetBadge(id, text)
end

local function refreshMissionsBadge()
	local n = missionClaimables + (if loginClaimable then 1 else 0) + (if spinnerReady then 1 else 0)
	HUDController.SetRailBadge("Missions", if n > 0 then tostring(n) else nil)
end

---------------------------------------------------------------------------------------------------------------
-- Cash pill (WarEmpireHUD › CurrencyPill) + cash float
---------------------------------------------------------------------------------------------------------------

local function pillHeight(): number
	return if isTouch() then HudConfig.CashPill.Height else HudConfig.CashPill.HeightDesktop
end

local function openShopFromHud()
	if shopOpener then
		local ok, err = pcall(shopOpener :: any)
		if not ok then
			warn("[HUDController] cash + :", err)
		end
	end
end

local function buildPill(screen: ScreenGui)
	local P = HudConfig.CashPill
	local touch = isTouch()
	local h = pillHeight()

	local p = Instance.new("Frame")
	p.Name = "CurrencyPill"
	p.AnchorPoint = Vector2.new(0, 1)
	p.Position = UDim2.new(0, P.Left, 1, -P.Bottom)
	p.Size = UDim2.fromOffset(P.MinWidth, h)
	p.AutomaticSize = Enum.AutomaticSize.X
	p.BackgroundColor3 = Colors.PillBg
	p.BackgroundTransparency = Colors.PillBgTransparency
	p.BorderSizePixel = 0
	p.Active = false
	p.ZIndex = 12
	UIUtil.Corner(p, P.Corner)
	local ring = UIUtil.Stroke(p, Colors.PillStroke, P.StrokePx)
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Transparency = Colors.PillStrokeTransparency
	padding(p, P.PadLeft, P.PadRight)
	local lim = Instance.new("UISizeConstraint")
	lim.MinSize = Vector2.new(P.MinWidth, 0)
	lim.MaxSize = Vector2.new(P.MaxWidth, math.huge)
	lim.Parent = p
	hList(p, P.Gap)

	HudIcons.Make("Cash", p, { Name = "Icon", Size = UDim2.fromOffset(P.IconSize.X, P.IconSize.Y), LayoutOrder = 1, ZIndex = 13 })

	local cash = label(p, "CashLabel", Fonts.Display, if touch then P.NumberSize else P.NumberSizeDesktop, P.NumberColor, "")
	cash.LayoutOrder = 2
	cash.Size = UDim2.new(0, 0, 1, 0)
	cash.AutomaticSize = Enum.AutomaticSize.X
	cash.TextXAlignment = Enum.TextXAlignment.Left
	cash.ZIndex = 13
	-- v36: high-contrast cash (white FredokaOne + a 2 px Ink outline on the dark pill — not yellow/gold)
	cash.TextStrokeColor3 = Colors.Ink
	cash.TextStrokeTransparency = 0.25
	-- v60: brief $… then leaderstats/0 within 0.5s — never stuck forever
	cash.Text = "$…"
	UIUtil.TextOutline(cash, 2)
	padding(cash, 0, P.NumberPadRight)
	local cp = Instance.new("UIScale")
	cp.Name = "Pop"
	cp.Parent = cash
	cashLabel = cash
	cashPop = cp

	-- green + : a transparent PlusHit v hit area around the PlusVisual v circle → cash packs (no toast)
	local slot = Instance.new("Frame")
	slot.Name = "PlusSlot"
	slot.LayoutOrder = 3
	slot.Size = UDim2.fromOffset(P.PlusVisual, P.PlusVisual)
	slot.BackgroundTransparency = 1
	slot.BorderSizePixel = 0
	slot.Active = false
	slot.Parent = p
	plusSlot = slot
	local cashPlus = Instance.new("TextButton")
	cashPlus.Name = "CashPlus"
	cashPlus.AnchorPoint = Vector2.new(0.5, 0.5)
	cashPlus.Position = UDim2.fromScale(0.5, 0.5)
	cashPlus.Size = UDim2.fromOffset(P.PlusHit, P.PlusHit)
	cashPlus.BackgroundTransparency = 1
	cashPlus.BorderSizePixel = 0
	cashPlus.AutoButtonColor = false
	cashPlus.Text = ""
	cashPlus.Active = true
	cashPlus.Selectable = true
	cashPlus.ZIndex = 14
	cashPlus.Parent = slot
	UIUtil.EnsureMinTouch(cashPlus, 44)
	local circle = Instance.new("Frame")
	circle.Name = "Circle"
	circle.AnchorPoint = Vector2.new(0.5, 0.5)
	circle.Position = UDim2.fromScale(0.5, 0.5)
	circle.Size = UDim2.fromOffset(P.PlusVisual, P.PlusVisual)
	circle.BackgroundColor3 = Colors.PlusGreen
	circle.BorderSizePixel = 0
	circle.Active = false
	circle.ZIndex = 15
	circle.Parent = cashPlus
	UIUtil.Corner(circle, math.ceil(P.PlusVisual / 2))
	local cs = UIUtil.Stroke(circle, Colors.PlusGreenStroke, P.PlusStrokePx)
	cs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	HudIcons.Make("Plus", circle, {
		Size = UDim2.fromScale(0.76, 0.76),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = Colors.White,
		ZIndex = 16,
	})
	local press = Instance.new("UIScale")
	press.Name = "Press"
	press.Parent = circle
	cashPlus.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			press.Scale = HudConfig.Rail.PressScale
		end
	end)
	cashPlus.InputEnded:Connect(function()
		press.Scale = 1
	end)
	cashPlus.Activated:Connect(openShopFromHud)

	p.Parent = screen
	pill = p
	HudLayout.BindVisibility(p, HudConfig.CashPill)
	HudLayout.SetRect("CashPill", p)
end

local function renderCash(v: number)
	if cashLabel then
		cashLabel.Text = formatCash(v)
	end
end

local function flashCash(color: Color3)
	local lab, pop = cashLabel, cashPop
	if not lab then
		return
	end
	local P = HudConfig.CashPill
	flashToken += 1
	local my = flashToken
	lab.TextColor3 = color
	TweenService:Create(lab, TweenInfo.new(P.FlashSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextColor3 = P.NumberColor }):Play()
	task.delay(P.FlashSeconds + 0.05, function()
		if my == flashToken and cashLabel then
			cashLabel.TextColor3 = P.NumberColor
		end
	end)
	if pop then
		pop.Scale = P.PopScale
		TweenService:Create(pop, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

local function floatBaseY(): number
	return -(4 + (pillHeight() - HudConfig.CashPill.PlusVisual) / 2)
end

-- X offset (v) of the float's right edge from the + slot: normally -4, shifted right when a long "-$120,000" next
-- to a short pill would run into the rail's bottom tile (spec §3.3: the float never overlaps the rail)
local function floatX(f: FloatRec): number
	local x = -4
	local p = pill
	local r = rail
	if not (p and r and r.Visible) then
		return x
	end
	local railPos, railSize = HudLayout.GetRect("Rail")
	if railSize.X <= 0 then
		return x
	end
	local lab = f.Label
	local ok, tb = pcall(function(): Vector2
		return TextService:GetTextSize(lab.Text, lab.TextSize, lab.Font, Vector2.new(4000, 1000))
	end)
	if not ok or typeof(tb) ~= "Vector2" then
		return x
	end
	local s = HudLayout.Scale()
	-- the + slot is the pill's last list item, PadRight from its right edge. Pill width: its AbsoluteSize, or its
	-- content measured from the cash text when the AutomaticSize width has not been resolved yet
	local P = HudConfig.CashPill
	local pillW = p.AbsoluteSize.X
	local cl = cashLabel
	if cl then
		local okN, nb = pcall(function(): Vector2
			return TextService:GetTextSize(cl.Text, cl.TextSize, cl.Font, Vector2.new(4000, 1000))
		end)
		if okN and typeof(nb) == "Vector2" then
			local wV = P.PadLeft + P.IconSize.X + P.Gap + nb.X + P.NumberPadRight + P.Gap + P.PlusVisual + P.PadRight
			pillW = math.max(pillW, math.clamp(wV, P.MinWidth, P.MaxWidth) * s)
		end
	end
	local slotLeftPx = p.AbsolutePosition.X + pillW - (P.PadRight + P.PlusVisual) * s
	local leftPx = slotLeftPx + (x - tb.X - HudConfig.CashFloat.StrokePx) * s
	local minLeft = railPos.X + railSize.X + 4 * s
	if leftPx < minLeft then
		x += (minLeft - leftPx) / s
	end
	return x
end

local function animateFloat(f: FloatRec)
	local CF = HudConfig.CashFloat
	for _, tw in ipairs(f.Tweens) do
		tw:Cancel()
	end
	local y = floatBaseY()
	local x = floatX(f)
	f.Label.Position = UDim2.new(0, x, 0, y)
	f.Label.TextTransparency = 0
	f.Stroke.Transparency = 0
	local rise = TweenInfo.new(CF.Seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	-- hold opaque for the first half, fade over the second
	local fade = TweenInfo.new(CF.Seconds * 0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, CF.Seconds * 0.5)
	f.Tweens = {
		TweenService:Create(f.Label, rise, { Position = UDim2.new(0, x, 0, y - CF.Rise) }),
		TweenService:Create(f.Label, fade, { TextTransparency = 1 }),
		TweenService:Create(f.Stroke, fade, { Transparency = 1 }),
	}
	for _, tw in ipairs(f.Tweens) do
		tw:Play()
	end
	f.Token += 1
	local my = f.Token
	task.delay(CF.Seconds + 0.05, function()
		if f.Token ~= my then
			return
		end
		local i = table.find(floats, f)
		if i then
			table.remove(floats, i)
		end
		f.Label:Destroy()
	end)
end

--[[
	"+$141" rising from the cash pill, just left of the + (spend: "-$5,000" in red). Gains within
	HudConfig.CashFloat.MergeWindow add into the same float; at most MaxPerSecond new floats per second (extra
	amounts merge into the newest float or are left to the count-up). Fed by HudLayout.CashFloat (Collect
	notifications) and by cash drops while buying (SetEconomy).
]]
function HUDController.ShowCashFloat(amount: number)
	if typeof(amount) ~= "number" or amount ~= amount or amount == 0 or math.abs(amount) == math.huge then
		return
	end
	local CF = HudConfig.CashFloat
	if amount < 0 and not CF.ShowSpend then
		return
	end
	local slot = plusSlot
	if not slot then
		return
	end
	local now = os.clock()
	for i = #floatBirths, 1, -1 do
		if now - floatBirths[i] > 1 then
			table.remove(floatBirths, i)
		end
	end
	local newest = floats[#floats]
	if newest and newest.Label.Parent and (newest.Amount > 0) == (amount > 0) then
		if now - newest.Last <= CF.MergeWindow or #floatBirths >= CF.MaxPerSecond then
			newest.Amount += amount
			newest.Last = now
			newest.Label.Text = floatText(newest.Amount)
			animateFloat(newest)
			return
		end
	end
	if #floatBirths >= CF.MaxPerSecond then
		return -- over the rate limit with nothing to merge into: the count-up alone shows it
	end
	local lab = label(nil, "CashFloat", Fonts.Display, CF.TextSize, if amount > 0 then CF.GainColor else CF.SpendColor, floatText(amount))
	lab.AnchorPoint = Vector2.new(1, 1)
	lab.AutomaticSize = Enum.AutomaticSize.XY
	lab.Size = UDim2.fromOffset(0, 0)
	lab.ZIndex = 20
	local stroke = UIUtil.TextOutline(lab, CF.StrokePx)
	lab.Parent = slot
	local rec: FloatRec = { Label = lab, Stroke = stroke, Amount = amount, Last = now, Token = 0, Tweens = {} }
	table.insert(floats, rec)
	table.insert(floatBirths, now)
	animateFloat(rec)
end

local function buyButtonShowing(): boolean
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local g = pg and pg:FindFirstChild("WE_PadBuyGui")
	if not (g and g:IsA("ScreenGui") and g.Enabled) then
		return false
	end
	local b = g:FindFirstChild("BuyButton", true)
	return b ~= nil and b:IsA("GuiObject") and b.Visible
end

-- spend floats only for drops the player caused: a panel is open, or the console BUY button was just on screen
local function spendContext(): boolean
	if HudLayout.GetFlag("Modal") or buyButtonShowing() then
		return true
	end
	return os.clock() - lastBuyVisibleAt <= HudConfig.CashFloat.SpendContextSeconds
end

local function setCash(newCash: number)
	local prev = cashTarget
	cashTarget = newCash
	if not cashLabel then
		return
	end
	if prev == nil then
		counting = false
		countTo = newCash
		renderCash(newCash)
		return
	end
	if newCash == prev and not counting then
		renderCash(newCash)
		return
	end
	if newCash == countTo then
		return
	end
	local P = HudConfig.CashPill
	local shown = if counting then countFrom + (countTo - countFrom) * math.clamp(countElapsed / P.CountUpSeconds, 0, 1) else prev
	countFrom = shown
	countTo = newCash
	countElapsed = 0
	counting = true
	local delta = newCash - prev
	if delta > 0 then
		flashCash(HudConfig.CashFloat.GainColor)
	elseif delta < 0 then
		flashCash(HudConfig.CashFloat.SpendColor)
		if HudConfig.CashFloat.ShowSpend and spendContext() then
			-- after a beat, so a stale sync that bounces straight back never floats, and skipped when the buy
			-- already floated its exact cost (WorldPromptController → HudLayout.CashFloat): no "-$40,000" for $20,000
			task.delay(SPEND_FLOAT_DELAY, function()
				local now = os.clock()
				if cashTarget and cashTarget <= newCash and now - lastExplicitSpendAt > HudConfig.CashFloat.SpendContextSeconds then
					lastDropFloat = { Amount = delta, At = now }
					HUDController.ShowCashFloat(delta)
				end
			end)
		end
	end
end

local function stepHud(dt: number)
	if counting then
		countElapsed += dt
		local a = math.clamp(countElapsed / HudConfig.CashPill.CountUpSeconds, 0, 1)
		local e = 1 - (1 - a) * (1 - a)
		if a >= 1 then
			counting = false
			renderCash(countTo)
		else
			renderCash(countFrom + (countTo - countFrom) * e)
		end
	end
end

---------------------------------------------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------------------------------------------

local function startBadgeFeeds()
	if feedsStarted then
		return
	end
	feedsStarted = true
	-- Bound after every controller's Init (deferred), so MissionController's own listener is already connected
	-- when the join push arrives.
	Remotes.BindEvent(Constants.RemoteNames.SpinnerStateUpdate, function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		spinnerReady = payload.Ready == true
		refreshMissionsBadge()
	end)
	Remotes.BindEvent(Constants.RemoteNames.MissionStateUpdate, function(payload: Types.MissionStatePayload)
		if typeof(payload) ~= "table" then
			return
		end
		local n = 0
		local daily = (payload :: any).Daily
		if typeof(daily) == "table" then
			for _, m in ipairs(daily) do
				if typeof(m) == "table" and m.Complete == true and m.Claimed ~= true then
					n += 1
				end
			end
		end
		missionClaimables = n
		local dl = (payload :: any).DailyLogin
		loginClaimable = typeof(dl) == "table" and dl.CanClaim == true
		refreshMissionsBadge()
	end)
end

function HUDController.Init()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireHUD"
	screen.IgnoreGuiInset = false
	-- above the world HUDs (combat 25 … orders 52) so rail tiles receive clicks; below modal panels (60+)
	screen.DisplayOrder = 55
	HudLayout.ApplyScreen(screen, { DisplayOrder = HudConfig.DisplayOrder.WarEmpireHUD })
	screen.Parent = player:WaitForChild("PlayerGui")
	_gui = screen

	-- Left rail (tiles come from BindActionBar)
	local r = Instance.new("Frame")
	r.Name = "Rail"
	r.BackgroundTransparency = 1
	r.BorderSizePixel = 0
	r.Active = false
	r.ZIndex = 20
	local grid = Instance.new("UIGridLayout")
	grid.FillDirection = Enum.FillDirection.Vertical
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
	grid.VerticalAlignment = Enum.VerticalAlignment.Top
	grid.Parent = r
	r.Parent = screen
	rail = r
	railGrid = grid
	layoutRail()
	HudLayout.BindVisibility(r, HudConfig.Rail)
	HudLayout.SetRect("Rail", r)

	buildPill(screen)
	buildTopStrip()

	HudLayout.LayoutChanged:Connect(layoutRail)
	HudLayout.BadgeChanged:Connect(function(id: string, text: string?)
		local btn = railTiles[id]
		if btn then
			UIUtil.SetTileBadge(btn, text)
		end
	end)
	-- Shop "!" (offer deferred / dropped) and Garage "!" (vehicle not spawned yet) clear when that panel opens
	HudLayout.PanelChanged:Connect(function(id: string, open: boolean)
		local src = (HudConfig.Rail.BadgeSources :: any)[id]
		if open and (src == "OfferPending" or src == "NewVehicle") then
			HudLayout.SetBadge(id, nil)
		end
	end)
	HudLayout.CashFloatRequested:Connect(function(amount: number)
		if typeof(amount) == "number" and amount < 0 then
			local now = os.clock()
			lastExplicitSpendAt = now
			local d = lastDropFloat
			if d and now - d.At <= HudConfig.CashFloat.SpendContextSeconds and math.abs(d.Amount - amount) < 0.5 then
				return -- the cash-drop float already showed this exact spend (PurchaseResult came late)
			end
		end
		HUDController.ShowCashFloat(amount)
	end)

	player:GetAttributeChangedSignal(TS.Shield.Attribute):Connect(refreshShield)
	refreshShield()

	do
		local acc = 0
		RunService.Heartbeat:Connect(function(dt: number)
			stepHud(dt)
			acc += dt
			if acc >= 0.25 then
				acc = 0
				if buyButtonShowing() then
					lastBuyVisibleAt = os.clock()
				end
			end
		end)
	end

	-- v60 NUCLEAR: leaderstats FIRST — never WaitForChild remotes on HUD cash path
	local function tryLeaderstats(): boolean
		local folder = player:FindFirstChild("leaderstats")
		if not folder then
			return false
		end
		local cashV = folder:FindFirstChild("Cash")
		if not cashV or not (cashV:IsA("IntValue") or cashV:IsA("NumberValue")) then
			return false
		end
		local goldV = folder:FindFirstChild("Gold")
		local g = 0
		if goldV and (goldV:IsA("IntValue") or goldV:IsA("NumberValue")) then
			g = (goldV :: any).Value
		end
		HUDController.SetEconomy((cashV :: any).Value, g, tonumber(player:GetAttribute("WE_PendingCash")) or 0)
		return true
	end

	local function wireLeaderstatsFolder(folder: Instance)
		local cashV = folder:FindFirstChild("Cash")
		if cashV and (cashV:IsA("IntValue") or cashV:IsA("NumberValue")) then
			(cashV :: any):GetPropertyChangedSignal("Value"):Connect(function()
				tryLeaderstats()
			end)
		end
		folder.ChildAdded:Connect(function(ch)
			if ch.Name == "Cash" and (ch:IsA("IntValue") or ch:IsA("NumberValue")) then
				(ch :: any):GetPropertyChangedSignal("Value"):Connect(function()
					tryLeaderstats()
				end)
				tryLeaderstats()
			end
		end)
		tryLeaderstats()
	end

	tryLeaderstats()
	do
		local existing = player:FindFirstChild("leaderstats")
		if existing then
			wireLeaderstatsFolder(existing)
		end
	end
	player.ChildAdded:Connect(function(ch)
		if ch.Name == "leaderstats" then
			wireLeaderstatsFolder(ch)
		end
	end)

	player:GetAttributeChangedSignal("WE_Cash"):Connect(function()
		local c = tonumber(player:GetAttribute("WE_Cash")) or 0
		local g = tonumber(player:GetAttribute("WE_Gold")) or 0
		local pend = tonumber(player:GetAttribute("WE_PendingCash")) or 0
		HUDController.SetEconomy(c, g, pend)
	end)
	do
		local c = player:GetAttribute("WE_Cash")
		if typeof(c) == "number" then
			HUDController.SetEconomy(
				c,
				tonumber(player:GetAttribute("WE_Gold")) or 0,
				tonumber(player:GetAttribute("WE_PendingCash")) or 0
			)
		end
	end

	-- EconomyUpdate IF present — never infinite WaitForChild
	local econToken = 0
	Remotes.BindEvent(Constants.RemoteNames.EconomyUpdate, function(payload: Types.EconomyUpdatePayload)
		econToken += 1
		local my = econToken
		local cashAmt, goldAmt = payload.Cash, payload.Gold
		local pendingAmt = tonumber(payload.PendingCash) or 0
		task.defer(function()
			if my == econToken then
				HUDController.SetEconomy(cashAmt, goldAmt, pendingAmt)
			end
		end)
	end)

	-- 0.5s hard fallback: never leave $… / $—
	task.delay(0.5, function()
		if not cashLabel then
			return
		end
		local txt = cashLabel.Text
		if txt == "$…" or txt == "$—" or txt == "$..." then
			if not tryLeaderstats() then
				local attr = tonumber(player:GetAttribute("WE_Cash"))
				if typeof(attr) == "number" then
					HUDController.SetEconomy(attr, tonumber(player:GetAttribute("WE_Gold")) or 0, tonumber(player:GetAttribute("WE_PendingCash")) or 0)
				else
					HUDController.SetEconomy(0, 0, 0)
				end
			end
		end
	end)

	-- Poll: attrs/leaderstats only; GetPlayerState via TryGet (no hang)
	task.spawn(function()
		local synced = false
		for i = 0, 20 do
			if typeof(player:GetAttribute("WE_Cash")) == "number" then
				HUDController.SetEconomy(
					player:GetAttribute("WE_Cash") :: number,
					tonumber(player:GetAttribute("WE_Gold")) or 0,
					tonumber(player:GetAttribute("WE_PendingCash")) or 0
				)
				synced = true
			end
			if tryLeaderstats() then
				synced = true
			end
			local fn = Remotes.TryGetFunction(Constants.RemoteNames.GetPlayerState)
			if fn then
				local ok, state = pcall(function()
					return fn:InvokeServer()
				end)
				if ok and state then
					HUDController.ApplyState(state :: Types.PlayerStatePayload)
					synced = true
					break
				end
			end
			if synced and i >= 2 then
				break
			end
			task.wait(0.25)
		end
		if not synced then
			warn("[HUDController] attr/leaderstats bootstrap still empty after poll")
		end
	end)

	-- XP / state via BindEvent — never block Init
	Remotes.BindEvent(Constants.RemoteNames.XPUpdate, function(payload: Types.XPUpdatePayload)
		HUDController.SetXP(payload.Level, payload.XP, payload.XPToNext, payload.HudGoal)
		if payload.LevelUp == true then
			-- the server's "★ LEVEL n!" reward toast is the text (and the sound); the chip just celebrates
			HUDController.ShowLevelUpCelebration(payload.Level, payload.UnlockMessage)
		end
	end)

	Remotes.BindEvent(Constants.RemoteNames.PlayerStateUpdate, function(state: Types.PlayerStatePayload)
		HUDController.ApplyState(state)
	end)

	-- spinner + mission badge feeds: after every controller's Init (see startBadgeFeeds)
	task.defer(startBadgeFeeds)
end

--[[ The TopStrip's free-topbar-row Frame (HudLayout.TopbarArea of WE_TopStrip); CompassController parents the
	compass chip here. Builds the gui on demand, so it works whatever the Init order. ]]
function HUDController.GetTopStripArea(): Frame?
	return ensureTopStrip()
end

--[[ v70: no banner — the level chip pops (UIScale 1 → 1.15 → 1) and its stroke flashes GoldBright; the
	server's "★ LEVEL n! — unlock" reward toast in the lane is the only text. ]]
function HUDController.ShowLevelUpCelebration(level: number, _unlockMessage: string?)
	local L = TS.Level
	if levelLabel then
		levelLabel.Text = tostring(math.floor(level))
	end
	local pop, stroke = chipPop, chipStroke
	if pop then
		pop.Scale = 1
		TweenService:Create(pop, TweenInfo.new(L.PopSeconds / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), { Scale = L.PopScale }):Play()
	end
	if stroke then
		stroke.Color = Constants.Colors.GoldBright
		stroke.Transparency = 0
		TweenService:Create(stroke, TweenInfo.new(L.PulseSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
	end
end

--[[ v38 soft rebirth CTA, v70 form: no banner. The Rebirth tile pulses once (the "!" badge comes at minLevel,
	see SetXP) and the level-chip tooltip carries the copy ("Rebirth 38/40 … · Keep all Robux Items"). ]]
function HUDController.ShowNearPrestigeBanner(level: number, minLevel: number)
	if level >= minLevel then
		HUDController.SetRailBadge("Rebirth", "!")
	end
	pulseTile("Rebirth", HudConfig.Rail.NearPrestigePulse)
end

--[[
	Rail tiles (spec §3.2). actions: { {Id, Name?, OnClick} } — visuals (label, icon, colours) come from
	HudConfig.Rail.Tiles by Id, in config order. Each cell is ONE TextButton (UIUtil.MakeRailTile) whose hit area
	includes the label; btn.Activated → OnClick (UIController: opener, one click sound, no toast).
]]
function HUDController.BindActionBar(actions: { RailAction })
	local host = rail
	if not host then
		warn("[HUDController] BindActionBar: rail nil — Init order broken?")
		return
	end
	for _, child in ipairs(host:GetChildren()) do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	table.clear(railTiles)
	local byId: { [string]: RailAction } = {}
	for _, a in ipairs(actions) do
		byId[a.Id] = a
	end
	local ordered: { { Def: any?, Action: RailAction } } = {}
	for _, t in ipairs(HudConfig.Rail.Tiles) do
		local a = byId[t.Id]
		if a then
			table.insert(ordered, { Def = t, Action = a })
			byId[t.Id] = nil
		end
	end
	for _, a in ipairs(actions) do
		if byId[a.Id] then
			table.insert(ordered, { Def = tileDef(a.Id), Action = a })
			byId[a.Id] = nil
		end
	end
	local touch = isTouch()
	for i, entry in ipairs(ordered) do
		local def = entry.Def
		local id = entry.Action.Id
		local kind: string = if def then def.Icon else "Dot"
		local btn = UIUtil.MakeRailTile(nil, {
			Name = entry.Action.Name or (if def then def.Name else "Dock" .. id),
			Label = if def then def.Label else id,
			Accent = if def then def.Accent else Colors.Muted,
			Fill = if def then def.Fill else Colors.PillBg,
			Icon = kind,
			LayoutOrder = i,
			Touch = touch,
			IconBuilder = function(slot: Frame, ink: Color3, fill: Color3)
				HudIcons.Make(kind, slot, { Size = UDim2.fromScale(1, 1), Color = ink, Fill = fill, ZIndex = 24 })
			end,
		})
		btn.Active = true
		local onClick = entry.Action.OnClick
		-- Activated = mouse + touch + gamepad (MouseButton1Click alone misses some touch paths)
		btn.Activated:Connect(function()
			onClick()
		end)
		addKeyHint(btn, id, def)
		btn.Parent = host
		railTiles[id] = btn
		UIUtil.SetTileBadge(btn, HudLayout.GetBadge(id))
		HudLayout.SetRect(id .. "Tile", btn)
		HudLayout.AssertTouchTarget(btn, "rail " .. id)
	end
	railCount = #ordered
	layoutRail()
	local order = if _gui then _gui.DisplayOrder else -1
	print(string.format("[HUDController] BindActionBar: %d rail tiles DisplayOrder=%d", railCount, order))
end

function HUDController.SetEconomy(cash: number, gold: number, pending: number?)
	-- v57: coerce so nil never skips update (only called after confirmed Economy sync). Gold and pending are
	-- accepted for every caller but no longer drawn: gold > 0 lives in the Shop header, pending on the ATM screen.
	local _ = gold
	local _p = pending
	setCash(tonumber(cash) or 0)
end

function HUDController.SetXP(level: number, xp: number, xpToNext: number, hudGoal: string?)
	local lv = math.floor(tonumber(level) or 0)
	if levelLabel then
		levelLabel.Text = tostring(lv)
	end
	local maxed = xpToNext == math.huge or xpToNext <= 0
	local alpha = if maxed then 1 else math.clamp(xp / xpToNext, 0, 1)
	if xpBarFill then
		xpBarFill.Size = UDim2.fromScale(alpha, 1)
	end
	-- Rebirth progress toward PrestigeConfig.MinLevelToPrestige (default 40) → the GoalLabel tooltip + badge
	local minPrestige = (PrestigeConfig and PrestigeConfig.MinLevelToPrestige) or 40
	local nearBand = (PrestigeConfig and PrestigeConfig.NearPrestigeLevels) or 2
	local fee = tonumber(PrestigeConfig and PrestigeConfig.CashFee) or 0
	local feeBit = if fee > 0 then string.format("Fee $%s", withCommas(fee)) else "Fee: none"
	local bonusPct = math.floor((tonumber(PrestigeConfig.CashBonusPerPrestige) or 0.1) * 100 + 0.5)
	local rebirthKey = HudConfig.Keys.Rebirth.Name
	local goalText = if typeof(hudGoal) == "string" and hudGoal ~= "" then hudGoal else LevelConfig.GetHudGoal(lv)
	local rebirthText: string
	if lv >= minPrestige then
		rebirthText = string.format("Rebirth READY · %s · +%d%% cash forever · Keep all Robux Items · press %s", feeBit, bonusPct, rebirthKey)
	else
		local pct = math.clamp(math.floor((lv / minPrestige) * 100), 0, 99)
		rebirthText = string.format("Rebirth %d/%d (%d%%) · %s · +%d%%/P", lv, minPrestige, pct, feeBit, bonusPct)
		if lv >= minPrestige - nearBand then
			rebirthText ..= " · Keep all Robux Items"
		end
	end
	if goalLabel then
		goalLabel.Text = goalText
	end
	if rebirthLabel then
		rebirthLabel.Text = rebirthText
	end
	HUDController.SetRailBadge("Rebirth", if lv >= minPrestige then "!" else nil)
	-- v38 near-prestige nudge: once per level in the band
	if lv >= minPrestige - nearBand and lv < minPrestige and nearPulseLevel ~= lv then
		nearPulseLevel = lv
		HUDController.ShowNearPrestigeBanner(lv, minPrestige)
	end
end

function HUDController.ApplyState(state: Types.PlayerStatePayload)
	HUDController.SetEconomy(state.Cash, state.Gold, (state :: any).PendingCash)
	local goal = LevelConfig.GetHudGoal(state.Level)
	HUDController.SetXP(state.Level, state.XP, state.XPToNext, goal)
end

--[[ Wire the cash-pill + → ShopController (cash packs) after Shop Init. ]]
function HUDController.BindShopOpener(fn: () -> ())
	shopOpener = fn
end

--[[ Wire the TopStrip settings gear → SettingsController after Settings Init. ]]
function HUDController.BindSettingsOpener(fn: () -> ())
	settingsOpener = fn
end

return HUDController
