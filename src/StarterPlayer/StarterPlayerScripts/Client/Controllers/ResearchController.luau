--!strict
--[[
	v69 Research Lab panel: permanent upgrades for weapons, soldiers, vehicles and defenses.

	Opened from the Research Lab terminals. UIController routes WE_OpenPanel = "Research" to
	ResearchController.Open(tab), where tab is the prompt's WE_OpenTab ("Weapons", "Soldiers", "Vehicles", "Defenses").

	Display only. ResearchService (server) owns levels, prices and every check:
	  * ResearchStateUpdate is bound with Remotes.BindEvent (never blocks) and carries a ResearchStatePayload.
	  * Open fires RequestResearch("Sync"); a BUY tap fires RequestResearch("Buy", upgradeId).
	  * Prices come only from payload.Costs. ResearchConfig gives names, badges, effects, MaxLevel and LabLevelFor.
	  * The GUI is built lazily on the first Open, so Init cannot fail.

	Layout: an 800 x 340 logical panel, centred, scaled by its own UIScale (not UIUtil.PrepareScreen, whose 0.65
	floor would shrink the 56 px touch targets). Every tap target is at least 56 logical px in both dimensions.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared") -- already loaded: the client Bootstrap waits for it
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local ResearchConfig = require(Shared.Configs.ResearchConfig)

local NotificationController = require(script.Parent.NotificationController)
local AudioController = require(script.Parent.Parent.Modules.AudioController)

type UpgradeDef = ResearchConfig.UpgradeDef
type ResearchLock = ResearchConfig.ResearchLock
type Payload = ResearchConfig.ResearchStatePayload

type RowStatus = {
	Kind: string, -- "Pending" | "Disabled" | "Maxed" | "NeedStructure" | "NeedLab" | "Locked" | "Unaffordable" | "CanBuy"
	Label: string, -- BUY button text
	Line: string?, -- replaces the effect line when set (plain text)
	LineColor: Color3?,
	Preview: boolean?, -- after Line, also show what the next level gives
	Reason: string, -- toast when a blocked button is tapped
}
type RowRefs = {
	Def: UpgradeDef,
	Frame: Frame,
	Stroke: UIStroke,
	Name: TextLabel,
	Effect: TextLabel,
	Pips: { Frame },
	PipStrokes: { UIStroke },
	Button: TextButton,
	BusyUntil: number,
	LastToastAt: number,
}
type TabRefs = { Button: TextButton, Bar: Frame, Title: TextLabel, Progress: TextLabel }

local ResearchController = {}

-- ── layout (logical px inside the 800 x 340 panel) ─────────────────────────────
local PANEL_W, PANEL_H = 800, 340
local HEADER_H = 60
local STRIPE_H = 4
local RAIL_X, RAIL_Y, RAIL_W, RAIL_H = 12, 66, 150, 262
local TAB_H, TAB_GAP = 58, 8
local CONTENT_X, CONTENT_Y, CONTENT_W, CONTENT_H = 174, 66, 614, 266
local ROW_H, ROW_GAP, BANNER_H = 62, 6, 36
local BANNER_MAX_ROWS = 3 -- tabs with at most this many upgrades get the 36 px banner
local BADGE_X, BADGE_SIZE = 9, 44
local TEXT_X = 62
local NAME_W = 292
local EFFECT_W = 404
local PIP_X, PIP_Y, PIP_W, PIP_H, PIP_GAP = 362, 12, 16, 10, 4
local BUY_X, BUY_W, BUY_H = 474, 128, 56
local CLOSE_SIZE = 56
local FIT_MIN, FIT_MAX = 0.6, 1.3

local BUSY_SECONDS = 0.8
local BUSY_MAX_SECONDS = 4 -- a BUY stays busy until the server answers (it always pushes state after a Buy)
local SYNC_RETRY_SECONDS, SYNC_RETRY_MAX = 3, 5
local BLOCKED_TOAST_COOLDOWN = 0.6

local Colors = Constants.Colors
local COLOR = {
	Plate = Colors.PlateDark,
	Row = Colors.Background,
	Olive = Colors.Olive,
	Gold = Colors.GoldBright,
	Text = Colors.TextOnDark,
	TextDark = Colors.TextDark,
	Muted = Colors.Muted,
	Cash = Colors.Cash,
	Danger = Colors.Danger,
	Gunmetal = Colors.Gunmetal,
	Amber = Color3.fromRGB(230, 196, 70),
	Black = Color3.fromRGB(0, 0, 0),
}

local LOCK_FALLBACK_TEXT: { [string]: string } = {
	Disabled = "Coming soon",
	Maxed = "MAXED",
	NeedStructure = "Locked",
	NeedLab = "Needs a higher Research Lab level",
}

-- ── state ──────────────────────────────────────────────────────────────────────
local player = Players.LocalPlayer
local wired = false
local isOpen = false
local currentTab = ResearchConfig.TrackOrder[1] or "Weapons"
local state: Payload? = nil
local retryToken = 0
local statusOverride: string? = nil

local screen: ScreenGui? = nil
local panelScale: UIScale? = nil
local labChip: TextLabel? = nil
local cashLabel: TextLabel? = nil
local statusLabel: TextLabel? = nil
local rows: { [string]: RowRefs } = {}
local awaitingReply: { [string]: number } = {} -- upgrade id -> earliest release (tap + BUSY_SECONDS)
local tabs: { [string]: TabRefs } = {}
local pages: { [string]: Frame } = {}
local banners: { [string]: TextLabel } = {}

-- ── small helpers ──────────────────────────────────────────────────────────────
local function hex(c: Color3): string
	return string.format(
		"#%02X%02X%02X",
		math.floor(c.R * 255 + 0.5),
		math.floor(c.G * 255 + 0.5),
		math.floor(c.B * 255 + 0.5)
	)
end

local function esc(s: string): string
	local out = string.gsub(s, "&", "&amp;")
	out = string.gsub(out, "<", "&lt;")
	out = string.gsub(out, ">", "&gt;")
	return out
end

local function paint(text: string, color: Color3): string
	return string.format('<font color="%s">%s</font>', hex(color), text)
end

local function bold(text: string): string
	return "<b>" .. text .. "</b>"
end

local function roman(n: number): string
	return ResearchConfig.Roman[n] or tostring(n)
end

local function cash(n: number): string
	return ResearchConfig.FormatCash(n)
end

local function currentCash(): number
	local v = tonumber(player:GetAttribute("WE_Cash"))
	if v == nil or v ~= v then
		return 0
	end
	return v
end

local function levelOf(id: string): number
	local st = state
	if st == nil then
		return 0
	end
	return ResearchConfig.LevelOf(st.Levels, id)
end

local function trackIdFrom(tab: any): string?
	if typeof(tab) ~= "string" then
		return nil
	end
	local want = string.lower(tab)
	for _, id in ipairs(ResearchConfig.TrackOrder) do
		if string.lower(id) == want then
			return id
		end
	end
	return nil
end

-- "%s weapon damage" -> "weapon damage" (the words after the amount), or nil for other formats
local function effectTail(def: UpgradeDef): string?
	local text = def.EffectText
	if string.sub(text, 1, 2) ~= "%s" then
		return nil
	end
	local tail = string.gsub(string.sub(text, 3), "^%s+", "")
	return tail
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number, borderMode: boolean?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	if borderMode then
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border -- on a TextButton, Contextual would outline the text
	end
	s.Parent = parent
	return s
end

local function frame(parent: Instance, name: string, x: number, y: number, w: number, h: number, color: Color3?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.BorderSizePixel = 0
	if color then
		f.BackgroundColor3 = color
		f.BackgroundTransparency = 0
	else
		f.BackgroundTransparency = 1
	end
	f.Parent = parent
	return f
end

local function label(
	parent: Instance,
	name: string,
	x: number,
	y: number,
	w: number,
	h: number,
	font: Enum.Font,
	size: number,
	color: Color3,
	text: string
): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Position = UDim2.fromOffset(x, y)
	l.Size = UDim2.fromOffset(w, h)
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Font = font
	l.TextSize = size
	l.TextColor3 = color
	l.Text = text
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.Parent = parent
	return l
end

local function maxTextSize(parent: Instance, maxSize: number, minSize: number)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.MinTextSize = minSize
	c.Parent = parent
end

local function requestSync()
	task.spawn(function()
		Remotes.FireServer(Constants.RemoteNames.RequestResearch, "Sync")
	end)
end

-- ── row status (what the BUY button and the effect line show) ──────────────────
local function statusFor(def: UpgradeDef): RowStatus
	local st = state
	if st == nil then
		return { Kind = "Pending", Label = "…", Reason = "Connecting to the lab…" }
	end
	local lvl = ResearchConfig.LevelOf(st.Levels, def.Id)
	local target = lvl + 1
	local lock = st.Locks[def.Id]
	local code = if lock then lock.Code else nil
	if def.Enabled == false or code == "Disabled" then
		return {
			Kind = "Disabled",
			Label = "SOON",
			Line = if lock and lock.Text ~= "" then lock.Text else "Coming soon",
			LineColor = COLOR.Amber,
			Reason = def.DisplayName .. " — coming soon",
		}
	end
	if lvl >= def.MaxLevel or code == "Maxed" then
		return { Kind = "Maxed", Label = "MAXED", Reason = def.DisplayName .. " is fully researched" }
	end
	local trackLock = st.Tracks[def.Track]
	if code == "NeedStructure" or (trackLock ~= nil and code == nil) then
		-- the tab's banner already says what to build, so the row keeps its effect preview
		local text = if lock and lock.Text ~= "" then lock.Text elseif trackLock then trackLock.Text else "Locked"
		return { Kind = "NeedStructure", Label = "LOCKED", Reason = text }
	end
	if code == "NeedLab" then
		local need = ResearchConfig.LabLevelFor(def, target)
		return {
			Kind = "NeedLab",
			Label = string.format("LAB L%d", need),
			Line = if lock and lock.Text ~= "" then lock.Text else string.format("Needs Research Lab L%d", need),
			LineColor = COLOR.Amber,
			Preview = true,
			Reason = string.format(
				"%s %s needs Research Lab L%d — upgrade the lab at its console",
				def.DisplayName,
				roman(target),
				need
			),
		}
	end
	if lock then
		-- a lock code this client does not know yet: trust the server's text
		local text = if lock.Text ~= "" then lock.Text else "Locked"
		return { Kind = "Locked", Label = "LOCKED", Line = text, LineColor = COLOR.Amber, Reason = text }
	end
	local cost = st.Costs[def.Id]
	if cost == nil then
		return { Kind = "Pending", Label = "…", Reason = "Price not loaded yet — close and reopen the panel" }
	end
	local short = math.ceil(cost - currentCash())
	if short > 0 then
		return {
			Kind = "Unaffordable",
			Label = cash(cost),
			Line = "Need " .. cash(short) .. " more",
			LineColor = COLOR.Danger,
			Preview = true,
			Reason = string.format("Not enough Cash — %s %s costs %s", def.DisplayName, roman(target), cash(cost)),
		}
	end
	return { Kind = "CanBuy", Label = "BUY " .. cash(cost), Reason = "" }
end

local function effectMarkup(def: UpgradeDef, lvl: number, status: RowStatus): string
	local tail = effectTail(def)
	if status.Line then
		local reason = paint(esc(status.Line), status.LineColor or COLOR.Amber)
		if not status.Preview or lvl >= def.MaxLevel then
			return reason
		end
		local nextLevel = lvl + 1
		local preview = if tail
			then bold(paint(ResearchConfig.FormatAmount(def, nextLevel), COLOR.Gold)) .. paint(" " .. esc(tail), COLOR.Muted)
			else paint(esc(ResearchConfig.FormatEffect(def, nextLevel)), COLOR.Muted)
		return reason .. paint("  ·  Next ", COLOR.Muted) .. preview
	end
	if status.Kind == "Maxed" then
		if tail then
			return paint("Max ", COLOR.Muted)
				.. bold(paint(ResearchConfig.FormatAmount(def, def.MaxLevel), COLOR.Cash))
				.. " "
				.. esc(tail)
		end
		return paint("Max: ", COLOR.Muted) .. esc(ResearchConfig.FormatEffect(def, def.MaxLevel))
	end
	local nowPart = if lvl > 0
		then paint("Now ", COLOR.Muted) .. bold(paint(ResearchConfig.FormatAmount(def, lvl), COLOR.Cash))
		else paint("No bonus yet", COLOR.Muted)
	local nextLevel = math.min(lvl + 1, def.MaxLevel)
	if tail then
		return nowPart
			.. paint(" › Next ", COLOR.Muted)
			.. bold(paint(ResearchConfig.FormatAmount(def, nextLevel), COLOR.Gold))
			.. " "
			.. esc(tail)
	end
	return nowPart .. paint(" › Next: ", COLOR.Muted) .. esc(ResearchConfig.FormatEffect(def, nextLevel))
end

local BUTTON_STYLE: { [string]: { Bg: Color3, Fg: Color3 } } = {
	CanBuy = { Bg = COLOR.Gold, Fg = COLOR.TextDark },
	Unaffordable = { Bg = COLOR.Gunmetal, Fg = COLOR.Danger },
	NeedLab = { Bg = COLOR.Gunmetal, Fg = COLOR.Muted },
	NeedStructure = { Bg = COLOR.Gunmetal, Fg = COLOR.Muted },
	Locked = { Bg = COLOR.Gunmetal, Fg = COLOR.Muted },
	Maxed = { Bg = COLOR.Olive, Fg = COLOR.Text },
	Disabled = { Bg = COLOR.Gunmetal, Fg = COLOR.Muted },
	Pending = { Bg = COLOR.Gunmetal, Fg = COLOR.Muted },
}

-- ── rendering ──────────────────────────────────────────────────────────────────
local function renderRow(row: RowRefs)
	local def = row.Def
	local lvl = levelOf(def.Id)
	local status = statusFor(def)
	local busy = os.clock() < row.BusyUntil

	local levelText = if lvl > 0 then roman(lvl) else "0"
	row.Name.Text = esc(string.upper(def.DisplayName))
		.. "  "
		.. paint(levelText .. " / " .. roman(def.MaxLevel), COLOR.Muted)
	row.Effect.Text = effectMarkup(def, lvl, status)

	for i, pip in ipairs(row.Pips) do
		local owned = i <= lvl
		pip.BackgroundColor3 = if owned then COLOR.Gold else COLOR.Gunmetal
		row.PipStrokes[i].Color = if owned then COLOR.Gold else COLOR.Olive
	end

	local style = BUTTON_STYLE[status.Kind] or BUTTON_STYLE.Pending
	local btn = row.Button
	btn.BackgroundColor3 = style.Bg
	btn.TextColor3 = style.Fg
	btn.Text = if busy then "…" else status.Label
	btn.AutoButtonColor = status.Kind == "CanBuy" and not busy
	btn:SetAttribute("WE_State", if busy then "Busy" else status.Kind)
end

local function renderTabs()
	local st = state
	for _, trackId in ipairs(ResearchConfig.TrackOrder) do
		local t = tabs[trackId]
		if t then
			local active = trackId == currentTab
			t.Button.BackgroundColor3 = if active then COLOR.Olive else COLOR.Gunmetal
			t.Bar.Visible = active
			t.Title.TextColor3 = if active then COLOR.Text else COLOR.Muted
			local trackDef = ResearchConfig.Tracks[trackId]
			if st == nil then
				t.Progress.Text = "…"
				t.Progress.TextColor3 = COLOR.Muted
			elseif st.Tracks[trackId] ~= nil then
				local req = trackDef and trackDef.Requires
				t.Progress.Text = if req then req.Short else "LOCKED"
				t.Progress.TextColor3 = COLOR.Amber
			else
				local owned, total = 0, 0
				for _, def in ipairs(ResearchConfig.UpgradesForTrack(trackId)) do
					owned += ResearchConfig.LevelOf(st.Levels, def.Id)
					total += def.MaxLevel
				end
				t.Progress.Text = string.format("%d/%d", owned, total)
				t.Progress.TextColor3 = if total > 0 and owned >= total then COLOR.Gold else COLOR.Muted
			end
		end
	end
end

local function bannerMarkup(trackId: string): string
	local trackDef = ResearchConfig.Tracks[trackId]
	local blurb = if trackDef then trackDef.Blurb else ""
	local st = state
	local trackLock = if st then st.Tracks[trackId] else nil
	if trackLock then
		local text = if trackLock.Text ~= "" then trackLock.Text else "Locked"
		return bold(paint(esc(text), COLOR.Amber)) .. "\n" .. paint(esc(blurb), COLOR.Muted)
	end
	local notes = {}
	for _, def in ipairs(ResearchConfig.UpgradesForTrack(trackId)) do
		local note = def.Note
		if note and note ~= "" then
			table.insert(notes, esc(def.DisplayName .. ": " .. string.lower(string.sub(note, 1, 1)) .. string.sub(note, 2)))
		end
	end
	local first = bold(paint(esc(blurb), COLOR.Text))
	if #notes == 0 then
		return first
	end
	return first .. "\n" .. paint(table.concat(notes, "  ·  "), COLOR.Muted)
end

local function renderAll()
	if not screen then
		return
	end
	local st = state
	if labChip then
		if st == nil then
			labChip.Text = "LAB —"
			labChip.TextColor3 = COLOR.Text
		elseif st.LabLevel <= 0 then
			labChip.Text = "NO LAB"
			labChip.TextColor3 = COLOR.Amber
		else
			labChip.Text = string.format("LAB L%d", st.LabLevel)
			labChip.TextColor3 = COLOR.Text
		end
	end
	if cashLabel then
		cashLabel.Text = cash(currentCash())
	end
	renderTabs()
	for trackId, page in pairs(pages) do
		page.Visible = st ~= nil and trackId == currentTab
	end
	for trackId, banner in pairs(banners) do
		banner.Text = bannerMarkup(trackId)
	end
	for _, row in pairs(rows) do
		renderRow(row)
	end
	if statusLabel then
		statusLabel.Visible = st == nil
		statusLabel.Text = statusOverride or "Connecting to the lab…"
	end
end

local function flashRow(row: RowRefs, fromLevel: number, toLevel: number)
	row.Stroke.Color = COLOR.Gold
	row.Stroke.Thickness = 3
	TweenService:Create(
		row.Stroke,
		TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Color = COLOR.Gunmetal, Thickness = 1 }
	):Play()
	for i = fromLevel + 1, math.min(toLevel, #row.Pips) do
		local pip = row.Pips[i]
		pip.Size = UDim2.fromOffset(PIP_W * 0.8, PIP_H * 0.8)
		TweenService:Create(
			pip,
			TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(PIP_W, PIP_H) }
		):Play()
	end
end

-- ── taps ───────────────────────────────────────────────────────────────────────
local function onBuyTapped(row: RowRefs)
	local now = os.clock()
	if now < row.BusyUntil then
		return
	end
	local status = statusFor(row.Def)
	if status.Kind ~= "CanBuy" then
		if status.Kind == "Pending" then
			requestSync()
		end
		if now - row.LastToastAt >= BLOCKED_TOAST_COOLDOWN then
			row.LastToastAt = now
			pcall(NotificationController.Show, status.Reason, "Info", 2)
		end
		return
	end
	-- busy until the reply payload (never a second buy at a stale price on a laggy phone), 0.8 s minimum
	row.BusyUntil = now + BUSY_MAX_SECONDS
	renderRow(row)
	local id = row.Def.Id
	awaitingReply[id] = now + BUSY_SECONDS
	task.spawn(function()
		Remotes.FireServer(Constants.RemoteNames.RequestResearch, "Buy", id)
	end)
	pcall(AudioController.PlayClick)
	-- the server answers with a toast + ResearchStateUpdate; restore the label if nothing changed
	task.delay(BUSY_SECONDS + 0.05, function()
		if rows[id] == row then
			renderRow(row)
		end
	end)
	task.delay(BUSY_MAX_SECONDS + 0.05, function()
		if rows[id] == row then
			awaitingReply[id] = nil
			renderRow(row)
		end
	end)
end

local function selectTab(trackId: string)
	currentTab = trackId
	renderAll()
end

-- ── build (lazy, on the first Open) ────────────────────────────────────────────
local function updateScale()
	local gui = screen
	local sc = panelScale
	if not (gui and sc) then
		return
	end
	local w, h = 0, 0
	local abs: any = gui.AbsoluteSize
	if typeof(abs) == "Vector2" then
		w, h = abs.X, abs.Y
	end
	if w <= 1 or h <= 1 then
		-- not laid out yet: use the viewport minus a worst-case topbar (IgnoreGuiInset is false)
		local cam = workspace.CurrentCamera
		if cam then
			w, h = cam.ViewportSize.X, cam.ViewportSize.Y - 58
		end
	end
	if w > 1 and h > 1 then
		sc.Scale = ResearchController.FitScale(w, h)
	end
end

local function buildRow(parent: Instance, def: UpgradeDef): RowRefs
	local f = frame(parent, "Row_" .. def.Id, 0, 0, CONTENT_W, ROW_H, COLOR.Row)
	f.LayoutOrder = 10 + def.Order
	corner(f, 8)
	local rowStroke = stroke(f, COLOR.Gunmetal, 1)

	local badge = frame(f, "Badge", BADGE_X, math.floor((ROW_H - BADGE_SIZE) / 2), BADGE_SIZE, BADGE_SIZE, COLOR.Olive)
	corner(badge, 6)
	local badgeText = label(badge, "Caption", 0, 0, BADGE_SIZE, BADGE_SIZE, Enum.Font.GothamBlack, 14, COLOR.Gold, def.Badge)
	badgeText.TextXAlignment = Enum.TextXAlignment.Center

	local name = label(f, "Title", TEXT_X, 6, NAME_W, 22, Enum.Font.GothamBold, 16, COLOR.Text, "")
	name.RichText = true
	name.TextTruncate = Enum.TextTruncate.AtEnd

	local effect = label(f, "Effect", TEXT_X, 32, EFFECT_W, 24, Enum.Font.Gotham, 13, COLOR.Text, "")
	effect.RichText = true
	effect.TextScaled = true -- the longest line ("gate guard and auto-gun damage") shrinks instead of clipping
	maxTextSize(effect, 13, 10)

	local pipBox = frame(f, "Pips", PIP_X, PIP_Y, def.MaxLevel * (PIP_W + PIP_GAP) - PIP_GAP, PIP_H)
	local pips: { Frame } = {}
	local pipStrokes: { UIStroke } = {}
	for i = 1, def.MaxLevel do
		local pip = Instance.new("Frame")
		pip.Name = "Pip" .. i
		pip.AnchorPoint = Vector2.new(0.5, 0.5)
		pip.Position = UDim2.fromOffset((i - 1) * (PIP_W + PIP_GAP) + PIP_W / 2, PIP_H / 2)
		pip.Size = UDim2.fromOffset(PIP_W, PIP_H)
		pip.BackgroundColor3 = COLOR.Gunmetal
		pip.BorderSizePixel = 0
		pip.Parent = pipBox
		corner(pip, 2)
		pips[i] = pip
		pipStrokes[i] = stroke(pip, COLOR.Olive, 1)
	end

	local btn = Instance.new("TextButton")
	btn.Name = "Buy"
	btn.Position = UDim2.fromOffset(BUY_X, math.floor((ROW_H - BUY_H) / 2))
	btn.Size = UDim2.fromOffset(BUY_W, BUY_H)
	btn.BackgroundColor3 = COLOR.Gunmetal
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.GothamBold
	btn.TextScaled = true
	btn.TextSize = 16
	btn.TextColor3 = COLOR.Muted
	btn.Text = "…"
	btn.Parent = f
	corner(btn, 8)
	maxTextSize(btn, 16, 9)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = btn

	local row: RowRefs = {
		Def = def,
		Frame = f,
		Stroke = rowStroke,
		Name = name,
		Effect = effect,
		Pips = pips,
		PipStrokes = pipStrokes,
		Button = btn,
		BusyUntil = 0,
		LastToastAt = -math.huge,
	}
	btn.Activated:Connect(function()
		onBuyTapped(row)
	end)
	return row
end

local function build(): boolean
	local pg = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
	if pg == nil then
		error("PlayerGui missing", 0)
	end
	rows, tabs, pages, banners = {}, {}, {}, {}

	local gui = Instance.new("ScreenGui")
	gui.Name = "WE_Research"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 60 -- modal panels; toasts are at 70
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	-- swallows camera drags behind the panel; tapping it does not close the panel
	local backdrop = frame(gui, "Backdrop", 0, 0, 0, 0, COLOR.Black)
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundTransparency = 0.45
	backdrop.Active = true

	local panel = frame(gui, "Panel", 0, 0, PANEL_W, PANEL_H, COLOR.Plate)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Active = true
	panel.ZIndex = 2
	corner(panel, 10)
	stroke(panel, COLOR.Olive, 2)
	local sc = Instance.new("UIScale")
	sc.Name = "FitScale"
	sc.Parent = panel
	panelScale = sc

	-- header
	local header = frame(panel, "Header", 0, 0, PANEL_W, HEADER_H)
	label(header, "Title", 18, 7, 196, 28, Enum.Font.GothamBlack, 22, COLOR.Gold, "RESEARCH LAB")
	local chip = label(header, "LabChip", 220, 8, 78, 26, Enum.Font.GothamBold, 14, COLOR.Text, "LAB —")
	chip.BackgroundColor3 = COLOR.Olive
	chip.BackgroundTransparency = 0
	chip.TextXAlignment = Enum.TextXAlignment.Center
	corner(chip, 6)
	labChip = chip
	label(
		header,
		"Sub",
		18,
		37,
		440,
		16,
		Enum.Font.Gotham,
		13,
		COLOR.Muted,
		"Permanent upgrades · kept through Rebirth"
	)

	local closeX = PANEL_W - 12 - CLOSE_SIZE
	local cashBox = frame(header, "CashChip", closeX - 10 - 170, 12, 170, 36, COLOR.Row)
	corner(cashBox, 8)
	stroke(cashBox, COLOR.Gunmetal, 1)
	local cashText = label(cashBox, "Amount", 10, 0, 150, 36, Enum.Font.GothamBold, 18, COLOR.Cash, cash(currentCash()))
	cashText.TextXAlignment = Enum.TextXAlignment.Center
	cashText.TextScaled = true
	maxTextSize(cashText, 18, 10)
	cashLabel = cashText

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Position = UDim2.fromOffset(closeX, 2)
	close.Size = UDim2.fromOffset(CLOSE_SIZE, CLOSE_SIZE)
	close.BackgroundColor3 = COLOR.Gunmetal
	close.BorderSizePixel = 0
	close.Font = Enum.Font.GothamBlack
	close.TextSize = 22
	close.TextColor3 = COLOR.Text
	close.Text = "X"
	close.Parent = header
	corner(close, 8)
	close.Activated:Connect(function()
		pcall(AudioController.PlayClick)
		ResearchController.Close()
	end)

	-- hazard stripe under the header: gold tape with dark notches
	local stripe = frame(panel, "Stripe", 0, HEADER_H, PANEL_W, STRIPE_H, COLOR.Gold)
	local notchX = 14
	local n = 0
	while notchX + 10 <= PANEL_W - 14 do
		n += 1
		frame(stripe, "Notch" .. n, notchX, 0, 10, STRIPE_H, COLOR.Plate)
		notchX += 26
	end

	-- tab rail
	local rail = frame(panel, "Rail", RAIL_X, RAIL_Y, RAIL_W, RAIL_H)
	for i, trackId in ipairs(ResearchConfig.TrackOrder) do
		local trackDef = ResearchConfig.Tracks[trackId]
		local b = Instance.new("TextButton")
		b.Name = "Tab_" .. trackId
		b.Position = UDim2.fromOffset(0, (i - 1) * (TAB_H + TAB_GAP))
		b.Size = UDim2.fromOffset(RAIL_W, TAB_H)
		b.BackgroundColor3 = COLOR.Gunmetal
		b.BorderSizePixel = 0
		b.Text = ""
		b.AutoButtonColor = true
		b.Parent = rail
		corner(b, 8)
		local bar = frame(b, "Bar", 0, 0, 4, TAB_H, COLOR.Gold)
		bar.Visible = false
		local title = label(
			b,
			"Label",
			14,
			9,
			RAIL_W - 20,
			20,
			Enum.Font.GothamBold,
			15,
			COLOR.Muted,
			string.upper(if trackDef then trackDef.DisplayName else trackId)
		)
		local progress = label(b, "Progress", 14, 31, RAIL_W - 20, 16, Enum.Font.Gotham, 13, COLOR.Muted, "…")
		tabs[trackId] = { Button = b, Bar = bar, Title = title, Progress = progress }
		b.Activated:Connect(function()
			if currentTab ~= trackId then
				pcall(AudioController.PlayClick)
			end
			selectTab(trackId)
		end)
	end

	-- content: one page per track (optional banner + upgrade rows)
	local content = frame(panel, "Content", CONTENT_X, CONTENT_Y, CONTENT_W, CONTENT_H)
	for _, trackId in ipairs(ResearchConfig.TrackOrder) do
		local page = frame(content, "Page_" .. trackId, 0, 0, CONTENT_W, CONTENT_H)
		page.Visible = false
		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Vertical
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Padding = UDim.new(0, ROW_GAP)
		list.Parent = page
		local defs = ResearchConfig.UpgradesForTrack(trackId)
		if #defs <= BANNER_MAX_ROWS then
			local banner = frame(page, "Banner", 0, 0, CONTENT_W, BANNER_H, COLOR.Olive)
			banner.BackgroundTransparency = 0.72
			banner.LayoutOrder = 0
			corner(banner, 6)
			local text = label(banner, "Caption", 12, 0, CONTENT_W - 24, BANNER_H, Enum.Font.Gotham, 13, COLOR.Muted, "")
			text.RichText = true
			text.TextWrapped = true
			text.LineHeight = 1.05
			banners[trackId] = text
		end
		for _, def in ipairs(defs) do
			rows[def.Id] = buildRow(page, def)
		end
		pages[trackId] = page
	end
	local status = label(content, "Status", 0, 0, CONTENT_W, CONTENT_H, Enum.Font.GothamBold, 16, COLOR.Muted, "")
	status.TextXAlignment = Enum.TextXAlignment.Center
	status.TextWrapped = true
	statusLabel = status

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateScale)
	gui.Parent = pg
	screen = gui
	updateScale()
	return true
end

local function ensureBuilt(): boolean
	local gui = screen
	if gui and gui.Parent then
		return true
	end
	if gui then
		gui:Destroy()
		screen = nil
	end
	local ok, err = pcall(build)
	if not ok then
		warn("[WAR EMPIRE] Research panel build failed:", err)
		local partial = screen
		if partial then
			partial:Destroy()
			screen = nil
		end
		return false
	end
	return screen ~= nil
end

-- ── server state ───────────────────────────────────────────────────────────────
local function readLocks(raw: any): { [string]: ResearchLock }
	local out: { [string]: ResearchLock } = {}
	if typeof(raw) ~= "table" then
		return out
	end
	for id, lk in pairs(raw) do
		if typeof(id) == "string" and typeof(lk) == "table" and typeof(lk.Code) == "string" then
			local text = if typeof(lk.Text) == "string" then lk.Text else (LOCK_FALLBACK_TEXT[lk.Code] or "")
			out[id] = { Code = lk.Code, Text = text }
		end
	end
	return out
end

local function sanitize(payload: any): Payload?
	if typeof(payload) ~= "table" then
		return nil
	end
	local lab = payload.LabLevel
	if typeof(payload.Levels) ~= "table" or typeof(payload.Costs) ~= "table" then
		return nil
	end
	if typeof(lab) ~= "number" or lab ~= lab then
		return nil
	end
	local levels: { [string]: number } = {}
	for id, v in pairs(payload.Levels) do
		if typeof(id) == "string" and typeof(v) == "number" and v == v then
			levels[id] = v
		end
	end
	local costs: { [string]: number } = {}
	for id, v in pairs(payload.Costs) do
		if typeof(id) == "string" and typeof(v) == "number" and v == v and v > 0 and v < math.huge then
			costs[id] = v
		end
	end
	return {
		LabLevel = math.floor(lab),
		Levels = levels,
		Costs = costs,
		Locks = readLocks(payload.Locks),
		Tracks = readLocks(payload.Tracks),
	}
end

local function onState(payload: any)
	local st = sanitize(payload)
	if st == nil then
		return
	end
	local prev = state
	state = st
	statusOverride = nil
	local t = os.clock()
	for id, minUntil in pairs(awaitingReply) do
		local row = rows[id]
		if row and row.BusyUntil > t then
			row.BusyUntil = math.max(minUntil, t)
		end
		awaitingReply[id] = nil
	end
	if not (isOpen and screen) then
		return
	end
	renderAll()
	if prev then
		for id, row in pairs(rows) do
			local was = ResearchConfig.LevelOf(prev.Levels, id)
			local now = ResearchConfig.LevelOf(st.Levels, id)
			if now > was then
				flashRow(row, was, now)
			end
		end
	end
end

local function onCashChanged()
	if not (isOpen and screen) then
		return
	end
	if cashLabel then
		cashLabel.Text = cash(currentCash())
	end
	for _, row in pairs(rows) do
		renderRow(row)
	end
end

local function startSyncRetries()
	retryToken += 1
	local token = retryToken
	task.spawn(function()
		for _ = 1, SYNC_RETRY_MAX do
			task.wait(SYNC_RETRY_SECONDS)
			if token ~= retryToken or not isOpen or state ~= nil then
				return
			end
			requestSync()
		end
		task.wait(SYNC_RETRY_SECONDS)
		if token == retryToken and isOpen and state == nil then
			statusOverride = "The lab is not answering. Close and reopen the panel to try again."
			renderAll()
		end
	end)
end

local function wire()
	if wired then
		return
	end
	wired = true
	Remotes.BindEvent(Constants.RemoteNames.ResearchStateUpdate, onState)
	player:GetAttributeChangedSignal("WE_Cash"):Connect(onCashChanged)
end

-- ── public API ─────────────────────────────────────────────────────────────────
-- Panel scale for a ScreenGui of w x h px: the 800 x 340 panel fits with a 12 px margin each side.
function ResearchController.FitScale(w: number, h: number): number
	return math.clamp(math.min((w - 24) / PANEL_W, (h - 12) / PANEL_H), FIT_MIN, FIT_MAX)
end

function ResearchController.Init()
	wire()
end

function ResearchController.Open(tab: any?)
	wire()
	if not ensureBuilt() then
		pcall(NotificationController.Show, "Research panel failed to load — try again", "Warn", 3)
		return
	end
	local gui = screen
	if gui == nil then
		return
	end
	local trackId = trackIdFrom(tab)
	if trackId then
		currentTab = trackId
	end
	isOpen = true
	gui.Enabled = true
	statusOverride = nil
	updateScale()
	renderAll()
	requestSync() -- every Open: also picks up a Lab reset by Rebirth
	if state == nil then
		startSyncRetries()
	end
end

function ResearchController.Close()
	isOpen = false
	retryToken += 1
	local gui = screen
	if gui then
		gui.Enabled = false
	end
end

function ResearchController.Toggle()
	if isOpen then
		ResearchController.Close()
	else
		ResearchController.Open(nil)
	end
end

function ResearchController.IsOpen(): boolean
	return isOpen
end

return ResearchController
