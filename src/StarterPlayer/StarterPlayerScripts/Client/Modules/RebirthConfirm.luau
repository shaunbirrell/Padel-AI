--!strict
--[[
	RebirthConfirm — the Rebirth confirm modal (owner's 11 features F7 + F11, lane P).

	The Rebirth panel's CONFIRM REBIRTH button opens it; a free rebirth is two presses (open, then REBIRTH).
	  * Two columns side by side, "CASH REBIRTH  FREE" and "KEEP BASE  R$ 50", each listing KEEP / RESET / GAIN from
	    the server's PrestigeStateUpdate.Summary (PrestigeConfig.RebirthSummary, built from the same reset tables
	    PrestigeService applies, so the modal can never promise something the server does not do). Shown RESET, GAIN,
	    KEEP, with the lines only one path has first and highlighted (ColumnRows), so the difference is in view on a phone.
	  * Banner "Keep all your Robux Items!" and a close control (back to the Rebirth panel).
	  * Footer buttons coloured like their columns:
	      REBIRTH           RequestPrestige() — disabled "Lv 40 needed" until the player can rebirth
	      KEEP BASE  R$ 50  saved tokens: "USE SAVED (n)" → RequestPrestige("KeepBase")
	                        product Id 0: "KEEP BASE  SOON", disabled, never prompts
	                        not eligible: "Lv 40 needed", disabled (never sells early)
	                        otherwise: RequestPurchaseDevProduct("RebirthKeepBase", "rebirth_panel") + PromptProductPurchase,
	                        then "REBIRTHING..." until the next PrestigeStateUpdate
	    The server decides everything (eligibility, tokens, the receipt grant, the rebirth); this module only asks.
	    RequestPrestige is fired from this module only.
	Phone first (CLAUDE.md §1): sizes are REAL px converted with the live HUD scale (buttons 196x50, close 48, headers
	16, lines 14; never under PanelShell's 64 v tap / 20 v text floors on touch). The footer buttons sit in the right
	60 % of the safe area and keep 16 px from the Roblox jump button; each column scrolls when it does not fit (800x360).
	A registered HudLayout panel ("RebirthConfirm"): black dim, the Modal flag, one panel at a time. No key names,
	no "click"/"tap" copy.
	Requests go out through deps.Fire (ProgressionController passes its non-blocking Shared/Remotes FireServer wrapper),
	so the headless drivers can record exactly what the modal sends.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local UIUtil = require(Shared.Util.UIUtil)
local HudConfig = require(Shared.Configs.HudConfig)
local PrestigeConfig = require(Shared.Configs.PrestigeConfig)
local MonetizationConfig = require(Shared.Configs.MonetizationConfig)

local HudLayout = require(script.Parent.HudLayout)
local PanelShell = require(script.Parent.PanelShell)

local RebirthConfirm = {}

local PANEL_ID = "RebirthConfirm"
local SOURCE = "rebirth_panel" -- MonetizationConfig.PurchaseSources (purchase intent → PrestigeService auto-use)
local CASH_PENDING_SECONDS = 8 -- a rebirth request that got no state push back re-enables the buttons after this
local BUY_SHEET_SECONDS = 120 -- the Robux sheet is open (the player may take a while)
local BUY_RECEIPT_SECONDS = 30 -- the sheet closed with a purchase: wait this long for the receipt's state push

-- real px (CLAUDE.md "size helpers take real px")
local PX = {
	ButtonW = 196,
	ButtonH = 50,
	Close = 48,
	Title = 20,
	Header = 16,
	Line = 14,
	Pad = 10,
	Gap = 8,
	JumpGap = 16, -- CLAUDE.md: nothing within 16 px of the jump button
	Margin = 6,
}
local MAX_W_V = 1000 -- modal size cap in v (tablets / desktops)
local MAX_H_V = 560

local COLORS = {
	Panel = PanelShell.Colors.Panel,
	Column = PanelShell.Colors.Row,
	Cash = Constants.Colors.Cash,
	CashButton = Constants.Colors.Accent,
	Keep = Constants.Colors.GoldBright,
	KeepText = Constants.Colors.TextDark,
	Reset = Color3.fromRGB(255, 130, 120),
	Gain = Constants.Colors.GoldBright,
	Text = Constants.Colors.TextOnDark,
	Muted = PanelShell.Colors.Muted,
	Disabled = Constants.Colors.Gunmetal,
	DisabledText = Color3.fromRGB(176, 184, 194),
	BannerBg = Color3.fromRGB(28, 72, 36),
}

--------------------------------------------------------------------------------------------------------------------
-- view model (pure; the headless drivers call these)
--------------------------------------------------------------------------------------------------------------------

export type View = {
	Ready: boolean, -- the player can rebirth now (level, not maxed, fee)
	Maxed: boolean,
	MinLevel: number,
	Tokens: number, -- saved keep-base rebirths
	Live: boolean, -- the keep-base product can be sold (server KeepBaseLive AND the config Id is not 0)
	Price: number,
	Pending: string?, -- "cash" | "keep" | "buy" while a request is on its way
}

export type ButtonState = {
	Text: string,
	Enabled: boolean,
	Action: string?, -- "cash" | "use" | "buy"
}

local function num(v: any, default: number): number
	local n = tonumber(v)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return default
	end
	return n
end

local function keepBaseDef(): any
	local def = (MonetizationConfig.DevProducts :: any)[PrestigeConfig.KeepBase.ProductKey]
	return if typeof(def) == "table" then def else nil
end

-- the product Id the client may prompt; 0 = never prompt
function RebirthConfirm.KeepBaseProductId(): number
	local def = keepBaseDef()
	return math.floor(num(if def then def.Id else 0, 0))
end

--[[ View from a PrestigeStateUpdate payload. level / xp: the freshest values (XPUpdate), when known. ]]
function RebirthConfirm.ViewOf(state: any, level: number?, pending: string?, attrTokens: number?): View
	local st = if typeof(state) == "table" then state else {}
	local minLevel = math.floor(num(st.MinLevel, PrestigeConfig.MinLevelToPrestige))
	local maxP = num(st.MaxPrestige, PrestigeConfig.MaxPrestige)
	local maxed = typeof(state) == "table" and num(st.Prestige, 0) >= maxP
	local lv = level or num(st.Level, 0)
	local fee = num(st.CashFee, 0)
	local ready = typeof(state) == "table"
		and not maxed
		and lv >= minLevel
		and (fee <= 0 or st.CanPrestige == true)
	-- a state without the level (older payload) falls back to the server's flag
	if typeof(state) == "table" and level == nil and st.Level == nil then
		ready = st.CanPrestige == true and not maxed
	end
	local tokens = math.max(0, math.floor(num(st.KeepBaseTokens, attrTokens or 0)))
	local def = keepBaseDef()
	return {
		Ready = ready == true,
		Maxed = maxed,
		MinLevel = minLevel,
		Tokens = tokens,
		Live = st.KeepBaseLive == true and RebirthConfirm.KeepBaseProductId() ~= 0,
		Price = math.floor(num(st.KeepBasePrice, num(if def then def.RobuxPrice else 50, 50))),
		Pending = pending,
	}
end

function RebirthConfirm.CashButton(v: View): ButtonState
	if v.Pending == "cash" then
		return { Text = "REBIRTHING...", Enabled = false }
	end
	if v.Maxed then
		return { Text = "MAX REBIRTH", Enabled = false }
	end
	if not v.Ready then
		return { Text = string.format("Lv %d needed", v.MinLevel), Enabled = false }
	end
	return { Text = "REBIRTH", Enabled = v.Pending == nil, Action = "cash" }
end

function RebirthConfirm.KeepButton(v: View): ButtonState
	if v.Pending == "keep" or v.Pending == "buy" then
		return { Text = "REBIRTHING...", Enabled = false }
	end
	if v.Maxed then
		return { Text = "MAX REBIRTH", Enabled = false }
	end
	if v.Tokens > 0 then
		if not v.Ready then
			return { Text = string.format("Lv %d needed", v.MinLevel), Enabled = false }
		end
		return { Text = string.format("USE SAVED (%d)", v.Tokens), Enabled = v.Pending == nil, Action = "use" }
	end
	if not v.Live then
		return { Text = "KEEP BASE  SOON", Enabled = false }
	end
	if not v.Ready then
		return { Text = string.format("Lv %d needed", v.MinLevel), Enabled = false }
	end
	return { Text = string.format("KEEP BASE  R$ %d", v.Price), Enabled = v.Pending == nil, Action = "buy" }
end

-- one short status line in the footer (explains a disabled button)
function RebirthConfirm.StatusText(v: View): string
	if v.Maxed then
		return "Max rebirth reached"
	end
	if v.Pending then
		return "Rebirthing..."
	end
	if not v.Ready then
		if v.Tokens > 0 then
			return string.format("Reach Lv %d  %d saved", v.MinLevel, v.Tokens)
		end
		return string.format("Reach Lv %d to rebirth", v.MinLevel)
	end
	if v.Tokens == 1 then
		return "1 Keep-Base Rebirth saved"
	elseif v.Tokens > 1 then
		return string.format("%d Keep-Base Rebirths saved", v.Tokens)
	end
	return "Both give +10% cash forever"
end

export type Row = {
	Text: string,
	Header: boolean, -- a section title (RESET / GAIN / KEEP)
	Section: string, -- "Reset" | "Gain" | "Keep"
	Highlight: boolean, -- a line only this column has (what makes the two paths different)
}

--[[ The rows of one column. Sections run RESET, GAIN, KEEP (what you lose is never below the fold on an 800x360
	phone), and inside a section the lines the OTHER column does not have come first, highlighted: the free
	column opens with "Base buildings (N built)", the keep-base column's KEEP list opens with "Base buildings and
	levels". Every line is the server's (Summary); nothing is added or dropped here. ]]
function RebirthConfirm.ColumnRows(summary: any, other: any): { Row }
	local rows: { Row } = {}
	if typeof(summary) ~= "table" then
		return rows
	end
	for _, key in ipairs({ "Reset", "Gain", "Keep" }) do
		local mine = summary[key]
		if typeof(mine) == "table" and #mine > 0 then
			local theirs: { [string]: boolean } = {}
			local otherLines = if typeof(other) == "table" then other[key] else nil
			if typeof(otherLines) == "table" then
				for _, line in ipairs(otherLines) do
					if typeof(line) == "string" then
						theirs[line] = true
					end
				end
			end
			local diff: { string } = {}
			local same: { string } = {}
			for _, line in ipairs(mine) do
				if typeof(line) == "string" then
					if typeof(other) == "table" and not theirs[line] then
						table.insert(diff, line)
					else
						table.insert(same, line)
					end
				end
			end
			if #diff + #same > 0 then
				table.insert(rows, { Text = string.upper(key), Header = true, Section = key, Highlight = false })
				for _, line in ipairs(diff) do
					table.insert(rows, { Text = line, Header = false, Section = key, Highlight = true })
				end
				for _, line in ipairs(same) do
					table.insert(rows, { Text = line, Header = false, Section = key, Highlight = false })
				end
			end
		end
	end
	return rows
end

function RebirthConfirm.CashTitle(): string
	return "CASH REBIRTH  FREE"
end

function RebirthConfirm.KeepTitle(v: View): string
	return string.format("KEEP BASE  R$ %d", v.Price)
end

--------------------------------------------------------------------------------------------------------------------
-- state
--------------------------------------------------------------------------------------------------------------------

export type OpenOpts = {
	OnBack: (() -> ())?, -- the close control was used (the Rebirth panel re-opens itself)
}

export type Deps = {
	Fire: (remoteName: string, ...any) -> (), -- non-blocking RemoteEvent:FireServer (Shared/Remotes helper)
}

local player = Players.LocalPlayer
local screen: ScreenGui? = nil
local modal: Frame? = nil
local shell: PanelShell.Shell? = nil
local isOpen = false
local openOpts: OpenOpts = {}
local state: any = nil
local liveLevel: number? = nil
local pending: string? = nil
local pendingSerial = 0
local pendingPrestige = -1
local pendingTokens = 0
local buyFinished = false
local relayoutQueued = false
local fireServer: ((string, ...any) -> ())? = nil

-- widgets refreshed in place (rebuilt by layout())
local cashBtn: TextButton? = nil
local keepBtn: TextButton? = nil
local statusLabel: TextLabel? = nil
local keepTitle: TextLabel? = nil
local cashList: ScrollingFrame? = nil
local keepList: ScrollingFrame? = nil
local listsFor: any = nil -- the Summary the two lists were built from (rebuilt only when it changes)

local function attrTokens(): number?
	local ok, v = pcall(function(): any
		return player:GetAttribute("WE_KeepBaseRebirths")
	end)
	return if ok and typeof(v) == "number" then v else nil
end

local function view(): View
	return RebirthConfirm.ViewOf(state, liveLevel, pending, attrTokens())
end

-- real px → v at the live HUD scale
local function scale(): number
	local s = HudLayout.Scale()
	return if s > 0 then s else 1
end
local function v(px: number): number
	return px / scale()
end
local function tapV(px: number): number
	return math.max(PanelShell.TouchMinV(), math.ceil(v(px) - 1e-6))
end
local function textV(px: number): number
	return PanelShell.Text(math.ceil(v(px) - 1e-6))
end

--------------------------------------------------------------------------------------------------------------------
-- layout
--------------------------------------------------------------------------------------------------------------------

local function label(parent: Instance, name: string, text: string, size: number, color: Color3, font: Enum.Font?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.Font = font or Enum.Font.GothamMedium
	t.TextSize = size
	t.TextColor3 = color
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Text = text
	t.Parent = parent
	return t
end

local SECTION_COLOR: { [string]: Color3 } = {
	Keep = COLORS.Cash,
	Reset = COLORS.Reset,
	Gain = COLORS.Gain,
}

local function fillList(list: ScrollingFrame?, summary: any, other: any)
	if not list then
		return
	end
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local lineSize = textV(PX.Line)
	local rowH = lineSize + math.ceil(v(6))
	local order = 0
	local function row(text: string, color: Color3, bold: boolean, indent: number)
		order += 1
		local t = label(list, "Line" .. order, text, lineSize, color, if bold then Enum.Font.GothamBold else Enum.Font.GothamMedium)
		t.LayoutOrder = order
		t.Size = UDim2.new(1, -8, 0, rowH)
		if indent > 0 then
			local p = Instance.new("UIPadding")
			p.PaddingLeft = UDim.new(0, indent)
			p.Parent = t
		end
	end
	local rows = RebirthConfirm.ColumnRows(summary, other)
	if #rows == 0 then
		row("Loading...", COLORS.Muted, false, 0)
		return
	end
	local indent = math.ceil(v(8))
	for _, r in ipairs(rows) do
		local color = SECTION_COLOR[r.Section] or COLORS.Text
		if r.Header then
			row(r.Text, color, true, 0)
		elseif r.Highlight then
			row(r.Text, color, true, indent)
		else
			row(r.Text, COLORS.Text, false, indent)
		end
	end
end

local function styleButton(b: TextButton?, st: ButtonState, face: Color3, textColor: Color3, stroke: Color3)
	if not b then
		return
	end
	b.Text = st.Text
	b.BackgroundColor3 = if st.Enabled then face else COLORS.Disabled
	b.TextColor3 = if st.Enabled then textColor else COLORS.DisabledText
	b.AutoButtonColor = st.Enabled
	local s = b:FindFirstChildOfClass("UIStroke")
	if s then
		s.Color = stroke
		s.Transparency = if st.Enabled then 0 else 0.45
	end
end

local function refresh()
	if not isOpen then
		return
	end
	local vw = view()
	styleButton(cashBtn, RebirthConfirm.CashButton(vw), COLORS.CashButton, COLORS.Text, COLORS.Cash)
	styleButton(keepBtn, RebirthConfirm.KeepButton(vw), COLORS.Keep, COLORS.KeepText, COLORS.Keep)
	if statusLabel then
		statusLabel.Text = RebirthConfirm.StatusText(vw)
	end
	if keepTitle then
		keepTitle.Text = RebirthConfirm.KeepTitle(vw)
	end
	local summary = if typeof(state) == "table" then state.Summary else nil
	if summary ~= listsFor or summary == nil then
		listsFor = summary
		local cashSum = if typeof(summary) == "table" then summary.Cash else nil
		local keepSum = if typeof(summary) == "table" then summary.KeepBase else nil
		fillList(cashList, cashSum, keepSum)
		fillList(keepList, keepSum, cashSum)
	end
end

local onCash: () -> ()
local onKeep: () -> ()
local closeModal: (reason: string) -> ()

-- the Roblox touch jump button in content-rect real px (x, y, w, h; the HUD harness' model of it); nil off touch
local function jumpRectPx(cw: number, ch: number): { number }?
	if not HudLayout.IsTouch() then
		return nil
	end
	local cam = Workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(cw, ch)
	if math.min(vp.X, vp.Y) <= 500 then
		return { cw - 95, ch - 90, 70, 70 }
	end
	return { cw - 170, ch - 210, 120, 120 }
end

local function column(parent: Instance, name: string, x: number, y: number, w: number, h: number, title: string, color: Color3): (TextLabel, ScrollingFrame)
	local col = Instance.new("Frame")
	col.Name = name
	col.Position = UDim2.fromOffset(x, y)
	col.Size = UDim2.fromOffset(w, h)
	col.BackgroundColor3 = COLORS.Column
	col.BorderSizePixel = 0
	col.Parent = parent
	UIUtil.Corner(col, 10)
	local st = UIUtil.Stroke(col, color, 2)
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local hs = textV(PX.Header)
	local pad = math.ceil(v(PX.Pad))
	local head = label(col, "Title", title, hs, color, Enum.Font.GothamBold)
	head.Position = UDim2.fromOffset(pad, math.ceil(v(4)))
	head.Size = UDim2.new(1, -2 * pad, 0, hs + math.ceil(v(8)))
	local top = head.Position.Y.Offset + head.Size.Y.Offset
	local list = Instance.new("ScrollingFrame")
	list.Name = "Lines"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(pad, top)
	list.Size = UDim2.new(1, -pad, 1, -(top + math.ceil(v(4))))
	list.ScrollBarThickness = if HudLayout.IsTouch() then 6 else 5
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = col
	local lay = Instance.new("UIListLayout")
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Padding = UDim.new(0, 0)
	lay.Parent = list
	return head, list
end

local function makeButton(parent: Instance, name: string, x: number, y: number, w: number, h: number, cb: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Position = UDim2.fromOffset(x, y)
	b.Size = UDim2.fromOffset(w, h)
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextSize = textV(PX.Line)
	b.TextTruncate = Enum.TextTruncate.AtEnd
	b.Active = true
	b.Parent = parent
	UIUtil.Corner(b, 10)
	local st = UIUtil.Stroke(b, Color3.new(1, 1, 1), 2)
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	b.Activated:Connect(cb)
	return b
end

local function layout()
	local m = modal
	if not m then
		return
	end
	local old = m:FindFirstChild("Content")
	if old then
		old:Destroy()
	end
	cashBtn, keepBtn, statusLabel, keepTitle, cashList, keepList = nil, nil, nil, nil, nil, nil
	listsFor = nil

	local s = scale()
	local contentV = HudLayout.ContentSizeV()
	local cw, ch = contentV.X * s, contentV.Y * s -- content rect, real px
	local margin = math.ceil(v(PX.Margin))
	local W = math.floor(math.min(contentV.X - 2 * margin, MAX_W_V))
	local H = math.floor(math.min(contentV.Y - 2 * margin, MAX_H_V))
	m.Size = UDim2.fromOffset(W, H)
	local mx = (contentV.X - W) / 2 -- modal left / top in content v
	local my = (contentV.Y - H) / 2

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Size = UDim2.fromScale(1, 1)
	content.Parent = m

	local pad = math.ceil(v(PX.Pad))
	local gap = math.ceil(v(PX.Gap))
	local closeV = tapV(PX.Close)

	-- header: title, banner, close
	local titleSize = textV(PX.Title)
	local title = label(content, "Title", "REBIRTH", titleSize, COLORS.Text, HudConfig.Fonts.Display)
	title.Position = UDim2.fromOffset(pad, 4)
	title.Size = UDim2.fromOffset(math.ceil(titleSize * 5.2), closeV)
	title.TextTruncate = Enum.TextTruncate.None
	UIUtil.TextOutline(title, 1.5)

	local bannerSize = textV(PX.Header)
	local bannerText = "Keep all your Robux Items!"
	local bannerW = math.ceil(#bannerText * bannerSize * 0.62) + 2 * pad
	local bannerRoom = W - 2 * (pad + math.ceil(titleSize * 5.2) + gap + closeV)
	local banner = label(content, "KeepRobuxBanner", bannerText, bannerSize, COLORS.Keep, HudConfig.Fonts.Display)
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.new(0.5, 0, 0, 4 + closeV / 2)
	banner.Size = UDim2.fromOffset(math.min(bannerW, math.max(bannerRoom, 120)), bannerSize + 2 * gap)
	banner.TextXAlignment = Enum.TextXAlignment.Center
	banner.BackgroundTransparency = 0.05
	banner.BackgroundColor3 = COLORS.BannerBg
	UIUtil.Corner(banner, 8)
	UIUtil.Stroke(banner, Constants.Colors.Gold, 2).ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	local close = PanelShell.CloseButton(content, function()
		closeModal("back")
	end, { Position = UDim2.new(1, -2, 0, 2), ZIndex = 5 })
	close.Size = UDim2.fromOffset(closeV, closeV)

	-- footer: status (left, text only) + two buttons right-aligned in the right 60 % of the safe area,
	-- clear of the jump button (+16 px)
	local btnH = tapV(PX.ButtonH)
	local wantW = math.max(tapV(PX.ButtonW), PanelShell.TouchMinV())
	local rightLimit = W - pad -- modal v
	local leftLimit = math.max(pad, 0.4 * contentV.X - mx)
	local footerTop = H - pad - btnH
	local jump = jumpRectPx(cw, ch)
	if jump then
		local keepX0 = (jump[1] - PX.JumpGap) / s - mx
		local keepY0 = (jump[2] - PX.JumpGap) / s - my
		local keepY1 = (jump[2] + jump[4] + PX.JumpGap) / s - my
		if footerTop < keepY1 and footerTop + btnH > keepY0 then
			rightLimit = math.min(rightLimit, math.floor(keepX0) - 2)
		end
	end
	local avail = rightLimit - leftLimit
	local bw = math.floor(math.min(wantW, (avail - gap) / 2))
	local minBw = math.max(PanelShell.TouchMinV() * 2, tapV(140))
	local stacked = bw < minBw
	local footerH = btnH
	if stacked then
		-- very narrow (portrait): full-width buttons, one above the other
		bw = math.floor(math.max(minBw, avail))
		footerH = 2 * btnH + gap
		footerTop = H - pad - footerH
	end
	if stacked then
		cashBtn = makeButton(content, "RebirthButton", rightLimit - bw, footerTop, bw, btnH, function()
			onCash()
		end)
		keepBtn = makeButton(content, "KeepBaseButton", rightLimit - bw, footerTop + btnH + gap, bw, btnH, function()
			onKeep()
		end)
	else
		cashBtn = makeButton(content, "RebirthButton", rightLimit - 2 * bw - gap, footerTop, bw, btnH, function()
			onCash()
		end)
		keepBtn = makeButton(content, "KeepBaseButton", rightLimit - bw, footerTop, bw, btnH, function()
			onKeep()
		end)
	end
	local statusW = math.floor((rightLimit - (if stacked then bw else 2 * bw + gap)) - 2 * pad)
	if statusW > 40 then
		local stl = label(content, "Status", "", textV(PX.Line), COLORS.Muted, Enum.Font.GothamBold)
		stl.Position = UDim2.fromOffset(pad, footerTop)
		stl.Size = UDim2.fromOffset(statusW, footerH)
		stl.TextWrapped = true
		stl.TextTruncate = Enum.TextTruncate.None
		statusLabel = stl
	end

	-- columns
	local colY = 4 + closeV + gap
	local colH = footerTop - gap - colY
	local colW = math.floor((W - 3 * pad) / 2)
	local _, cl = column(content, "CashColumn", pad, colY, colW, colH, RebirthConfirm.CashTitle(), COLORS.Cash)
	cashList = cl
	local kt, kl = column(content, "KeepBaseColumn", 2 * pad + colW, colY, colW, colH, RebirthConfirm.KeepTitle(view()), COLORS.Keep)
	keepTitle, keepList = kt, kl

	refresh()
end

--------------------------------------------------------------------------------------------------------------------
-- actions (the server re-checks all of it)
--------------------------------------------------------------------------------------------------------------------

local function send(remoteName: string, ...: any)
	local f = fireServer
	if f then
		f(remoteName, ...)
	else
		warn("[RebirthConfirm] no Fire dependency; request not sent:", remoteName)
	end
end

local function clearPending()
	pendingSerial += 1
	pending = nil
	buyFinished = false
end

-- the request got no answer in time: show the latest state again (the server's toast said why)
local function armTimeout(seconds: number)
	local my = pendingSerial
	task.delay(seconds, function()
		if pendingSerial == my and pending ~= nil then
			clearPending()
			refresh()
		end
	end)
end

local function startPending(kind: string, seconds: number)
	pendingSerial += 1
	pending = kind
	buyFinished = false
	pendingPrestige = if typeof(state) == "table" then num(state.Prestige, 0) else 0
	pendingTokens = RebirthConfirm.ViewOf(state, liveLevel, nil, attrTokens()).Tokens
	armTimeout(seconds)
	refresh()
end

onCash = function()
	local b = RebirthConfirm.CashButton(view())
	if b.Action ~= "cash" or not b.Enabled then
		return
	end
	startPending("cash", CASH_PENDING_SECONDS)
	send(Constants.RemoteNames.RequestPrestige)
end

onKeep = function()
	local b = RebirthConfirm.KeepButton(view())
	if not b.Enabled then
		return
	end
	if b.Action == "use" then
		startPending("keep", CASH_PENDING_SECONDS)
		send(Constants.RemoteNames.RequestPrestige, "KeepBase")
	elseif b.Action == "buy" then
		local id = RebirthConfirm.KeepBaseProductId()
		if id == 0 then
			return -- never prompts while the Id is 0
		end
		startPending("buy", BUY_SHEET_SECONDS)
		-- intent first (the source lets the server use the token right after the receipt is saved)
		send(Constants.RemoteNames.RequestPurchaseDevProduct, PrestigeConfig.KeepBase.ProductKey, SOURCE)
		local ok = pcall(function()
			MarketplaceService:PromptProductPurchase(player, id)
		end)
		if not ok then
			clearPending()
			refresh()
		end
	end
end

closeModal = function(reason: string)
	if not isOpen then
		return
	end
	isOpen = false
	local m = modal
	if m then
		m.Visible = false
	end
	local sh = shell
	if sh then
		sh.Sync(false)
	end
	if reason == "back" then
		local cb = openOpts.OnBack
		if cb then
			task.defer(cb)
		end
	end
end

--------------------------------------------------------------------------------------------------------------------
-- public
--------------------------------------------------------------------------------------------------------------------

function RebirthConfirm.Init(deps: Deps?)
	if deps and typeof(deps.Fire) == "function" then
		fireServer = deps.Fire
	end
	if screen then
		return
	end
	local sg = Instance.new("ScreenGui")
	sg.Name = "WarEmpireRebirthConfirm"
	PanelShell.Screen(sg, HudConfig.DisplayOrder.Panels + 1) -- above the Rebirth panel, under the toasts
	sg.Parent = player:WaitForChild("PlayerGui", 30)
	screen = sg

	local m = Instance.new("Frame")
	m.Name = "Modal"
	m.AnchorPoint = Vector2.new(0.5, 0.5)
	m.Position = UDim2.fromScale(0.5, 0.5)
	m.Size = UDim2.fromOffset(600, 360)
	m.BackgroundColor3 = COLORS.Panel
	m.BorderSizePixel = 0
	m.Active = true
	m.Visible = false
	m.ZIndex = 2
	m.Parent = sg
	UIUtil.Corner(m, 14)
	local st = UIUtil.Stroke(m, Constants.Colors.Gold, 2)
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	modal = m

	shell = PanelShell.Attach({
		Id = PANEL_ID,
		Screen = sg,
		Panel = m,
		IsOpen = function(): boolean
			return isOpen
		end,
		Close = function()
			closeModal("dismiss")
		end,
	})

	HudLayout.LayoutChanged:Connect(function()
		if not isOpen or relayoutQueued then
			return
		end
		relayoutQueued = true
		task.defer(function()
			relayoutQueued = false
			if isOpen then
				layout()
			end
		end)
	end)

	pcall(function()
		MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, productId: number, isPurchased: boolean)
			local id = RebirthConfirm.KeepBaseProductId()
			if userId ~= player.UserId or id == 0 or productId ~= id or pending ~= "buy" then
				return
			end
			if isPurchased then
				-- the receipt is on its way: keep REBIRTHING... until its state push (or the timeout)
				pendingSerial += 1
				buyFinished = true
				armTimeout(BUY_RECEIPT_SECONDS)
			else
				clearPending()
				refresh()
			end
		end)
	end)
	pcall(function()
		player:GetAttributeChangedSignal("WE_KeepBaseRebirths"):Connect(refresh)
	end)
end

--[[ Every PrestigeStateUpdate (ProgressionController forwards it). A rebirth that went through closes the modal;
	any other push ends a cash / use-token request (refused) or a purchase whose Robux sheet already closed. ]]
function RebirthConfirm.SetState(payload: any)
	state = payload
	if typeof(payload) == "table" and typeof(payload.Level) == "number" then
		liveLevel = payload.Level
	end
	if pending ~= nil and typeof(payload) == "table" then
		if num(payload.Prestige, 0) > pendingPrestige then
			clearPending()
			closeModal("done")
			return
		end
		-- a purchase whose sheet is still open ignores unrelated pushes, but a banked token ends it
		local banked = num(payload.KeepBaseTokens, 0) > pendingTokens
		if pending ~= "buy" or buyFinished or banked then
			clearPending()
		end
	end
	refresh()
end

-- the freshest level (XPUpdate); the REBIRTH button follows it without waiting for a state push
function RebirthConfirm.SetLevel(level: number?)
	if typeof(level) == "number" then
		liveLevel = level
		refresh()
	end
end

function RebirthConfirm.Open(payload: any?, opts: OpenOpts?)
	RebirthConfirm.Init()
	if payload ~= nil then
		state = payload
	end
	openOpts = opts or {}
	local m = modal
	if not m then
		return
	end
	isOpen = true
	layout()
	m.Visible = true
	local sh = shell
	if sh then
		sh.Sync(true)
	end
end

function RebirthConfirm.Close()
	closeModal("dismiss")
end

function RebirthConfirm.IsOpen(): boolean
	return isOpen
end

-- display snapshot for the headless drivers: the two button states and the status line
function RebirthConfirm.Snapshot(): { Cash: ButtonState, Keep: ButtonState, Status: string, Pending: string? }
	local vw = view()
	return {
		Cash = RebirthConfirm.CashButton(vw),
		Keep = RebirthConfirm.KeepButton(vw),
		Status = RebirthConfirm.StatusText(vw),
		Pending = pending,
	}
end

return RebirthConfirm
