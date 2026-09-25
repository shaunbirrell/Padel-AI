--!strict
--[[
	NationController: the "Choose your nation" picker (nations spec lane C, fb2/spec_nations.md section 2 Client;
	contract fb2/nations/A1/contract.md section 5). Cosmetic only: the player's own flag on their base and a code in
	the player list. The server (NationColorService, lane B) decides everything; this panel only asks.

	OPENS
	  * join     by itself, once per session, 1.0 s after the first CharacterAdded, only while the attribute
	             WE_NationNeedsPick is true, the HudLayout flags Driving / Dead / RecentCombat / Modal are all false,
	             and the art gate passes (NationConfig.LiveRequiresArt off, every atlas id wired, or an admin).
	             Closing it any way except CONFIRM counts as LATER (sent once per session, spec R9).
	  * flagpole UIController panelOpeners.Nation("flagpole") from the flagpole prompt (WE_OpenTab = "flagpole")
	  * settings Open(nil): the Settings "YOUR FLAG" row (CHANGE)
	PICKING
	  Nothing is selected at the start. The IP-based suggestion (NationColorUpdate.Suggested, this session, memory
	  only) is a badged tile in "For you", never selected (NationConfig.SuggestPreselect = false). CONFIRM stays
	  disabled until a tile is tapped. Search text stays on this device: it is never sent, stored or shown back.
	  A tile shows the flag cropped from its atlas (NationTexture.Source) or, while no art is wired, the banner
	  colour + NationConfig.Code (the fallback tile).
	SAFETY
	  RequestSetNation goes out with Remotes.FireServer inside task.spawn (it gives up after 3 s when the remote does
	  not exist yet), and a pick waits at most 5 s for Result / WE_NationId: the UI never waits forever. No
	  per-frame work (events and task.delay only), no world access, no WaitForChild without a timeout. Layout is phone-first:
	  sizes in v (real px = v x HudLayout.Scale(), 0.70 on phones): every tap target >= 68 v (47.6 real px), text
	  >= 20 v (14 real px); on touch nothing tappable sits in the left 40 % of the safe area (thumbstick) and the
	  grid / buttons keep >= 20 real px from the Roblox jump button. HudLayout.IsTouch() is only the LAYOUT switch;
	  no copy here names a key or an input device.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local TextService = game:GetService("TextService")
local Workspace = game:GetService("Workspace")

-- Bootstrap.client waits for ReplicatedStorage.Shared before it requires any controller (and HudLayout /
-- PanelShell below already hold it), so Shared is indexed directly: no WaitForChild here at all.
local Shared = ReplicatedStorage.Shared
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local NationConfig = require(Shared.Configs.NationConfig)
local AdminConfig = require(Shared.Configs.AdminConfig)
local HudConfig = require(Shared.Configs.HudConfig)
local UIUtil = require(Shared.Util.UIUtil)
local NationTexture = require(Shared.Util.NationTexture)

local AudioController = require(script.Parent.Parent.Modules.AudioController)
local HudLayout = require(script.Parent.Parent.Modules.HudLayout)
local PanelShell = require(script.Parent.Parent.Modules.PanelShell)

type NationDef = NationConfig.NationDef

local NationController = {}

local PANEL_ID = "Nation"
local AUTO_OPEN_DELAY = 1.0 -- s after the first CharacterAdded (spec)
local REOPEN_SETTLE = 1.0 -- s the blocking flags must stay clear before the join picker opens
local REPLY_TIMEOUT = 5 -- s a pick waits for Result / WE_NationId (contract section 5)
local SEARCH_DEBOUNCE = 0.15
local SEARCH_MAX = 30 -- result tiles
local SEARCH_MAX_BYTES = 64
local BLOCK_FLAGS = { "Driving", "Dead", "RecentCombat", "Modal" }

-- geometry in v (HUD UIScale units); phones: real px = v x 0.70
local G = {
	Margin = 8, -- panel inset inside the safe area
	Pad = 16, -- panel padding
	Gap = 12, -- between columns / rows of controls
	ColGap = 16, -- preview column -> tabs / grid
	TabH = 68,
	TabMinW = 96,
	TabPadX = 32,
	TabGap = 8,
	ActW = 159, -- CONFIRM / LATER column
	ConfirmH = 112,
	ConfirmMinH = 68,
	SecondH = 68,
	TileMinW = 132,
	TileH = 136,
	TileGap = 8,
	FlagW = 96, -- 4:3 flag box on a tile
	SearchH = 68,
	ScrollBar = 8,
	FadeW = 32,
	BadgeH = 26,
	DesktopMaxW = 1180,
	DesktopMaxH = 700,
	ThumbZone = 0.40, -- CLAUDE.md: nothing tappable in the left 40 % x lower 2/3 of the safe area
	JumpClearPx = 20, -- real px kept clear around the Roblox jump button (CLAUDE.md: >= 16)
}

local COL = {
	Panel = PanelShell.Colors.Panel,
	Stroke = PanelShell.Colors.PanelStroke,
	Row = PanelShell.Colors.Row,
	RowOn = Color3.fromRGB(52, 58, 66),
	Title = PanelShell.Colors.Title,
	Muted = PanelShell.Colors.Muted,
	Gold = Color3.fromRGB(240, 196, 64),
	GoldInk = Color3.fromRGB(24, 20, 8),
	Mine = Color3.fromRGB(90, 190, 120),
	Confirm = Color3.fromRGB(46, 160, 80),
	Disabled = Color3.fromRGB(58, 66, 74),
	DisabledText = Color3.fromRGB(150, 158, 170),
	Second = PanelShell.Colors.CloseFace,
	Warn = Color3.fromRGB(255, 170, 140),
	Neutral = Color3.fromRGB(72, 88, 58), -- "No flag": plain army green
	Ink = HudConfig.Colors.Ink,
}

-- the one status line under the preview (short, no key names, never echoes search text)
local MSG = {
	Pick = "Pick a flag",
	Saving = "Saving...",
	NoSend = "Can't save now. Try later.",
	NoAnswer = "No answer. Try again.",
	Loading = "Still loading. Try again.",
	Invalid = "Pick another flag",
	Same = "Already your flag",
	SearchHint = "Type a country name",
	NoMatch = "No match",
}

type Tile = {
	Button: TextButton,
	Flag: ImageLabel,
	Swatch: Frame,
	Code: TextLabel,
	Name: TextLabel,
	Badge: TextLabel,
	Stroke: UIStroke,
	Id: string?,
}

type TabInfo = { Key: string, Label: string, Button: TextButton?, X: number, W: number }

type Pending = { Serial: number, Id: string }

local player = Players.LocalPlayer

-- ui
local panel: Frame? = nil
local shell: PanelShell.Shell? = nil
local ui: { [string]: any } = {} -- named children (Title, Sub, PrevFlag, PrevSwatch, PrevCode, PrevName, Status, Tabs, FadeL, FadeR, Grid, SearchBox, Hint, Confirm, Second)
local tiles: { Tile } = {}
local tabs: { TabInfo } = {}
local tabsW = 0 -- canvas width of the tab strip (v)
local stripW = 0 -- visible width of the tab strip (v)
local tileW, tileCols = G.TileMinW, 1

-- state
local open = false
local mode = "settings" -- "join" | "flagpole" | "settings"
local currentTab = "ForYou"
local selectedId: string? = nil
local suggestedId: string? = nil -- NationColorUpdate.Suggested: this session, memory only, never sent anywhere
local shownIds: { string } = {}
local message: string? = nil -- a result / error line (cleared by the next tap)
local messageWarn = false
local busy = false
local pickSerial = 0
local pending: Pending? = nil
local confirmed = false -- a pick was accepted while this open lasted
local laterSent = false -- once per session
local cooldownAt = 0 -- NextChangeAt from a "cooldown" reply (os.time() / server time)
local autoArmed, autoReady, autoDone = false, false, false
local autoSerial = 0
local searchSerial = 0
local preloaded = false
local isAdmin = false
local artReady = false

-- per-open caches (NationConfig.Visible() builds a new table on every call)
local visible: { NationDef } = {}
local byRegion: { [string]: { NationDef } } = {}
local sortKey: { [string]: string } = {}

---------------------------------------------------------------------------------------------------------------
-- small helpers
---------------------------------------------------------------------------------------------------------------

local function serverNow(): number
	local ok, t = pcall(function(): number
		return Workspace:GetServerTimeNow()
	end)
	if ok and typeof(t) == "number" and t > 0 then
		return t
	end
	return os.time()
end

local function attrNumber(name: string): number
	local v = player:GetAttribute(name)
	return if typeof(v) == "number" and v == v then v else 0
end

-- the player's stored nation: a NationConfig id, NationConfig.NeutralId, or nil (never picked)
local function currentId(): string?
	local v = player:GetAttribute("WE_NationId")
	if v == NationConfig.NeutralId then
		return NationConfig.NeutralId
	end
	local def = NationConfig.Get(v)
	return if def then def.Id else nil
end

local function validPickId(id: any): string?
	if id == NationConfig.NeutralId then
		return NationConfig.NeutralId
	end
	local def = NationConfig.Get(id)
	return if def then def.Id else nil
end

local function shortName(id: string?): string
	if id == nil then
		return ""
	end
	if id == NationConfig.NeutralId then
		return NationConfig.NeutralLabel
	end
	local def = NationConfig.Get(id)
	return if def then def.Short else ""
end

local function fmtWait(seconds: number): string
	local s = math.max(0, seconds)
	if s >= 3600 then
		return string.format("%dh", math.ceil(s / 3600))
	end
	return string.format("%dm", math.max(1, math.ceil(s / 60)))
end

-- os.time() of the next allowed change, or 0 = now (the server is the authority; this only greys CONFIRM)
local function nextChangeAt(): number
	local at = cooldownAt -- a "cooldown" reply always counts
	if currentId() ~= nil then
		at = math.max(at, attrNumber("WE_NationNextAt")) -- never picked: the first pick is always allowed
	end
	return at
end

local function inCooldown(): boolean
	return nextChangeAt() > serverNow()
end

local function text(v: number): number
	return PanelShell.Text(v)
end

local function textWidth(s: string, size: number): number
	local ok, v = pcall(function(): Vector2
		return TextService:GetTextSize(s, size, Enum.Font.GothamBold, Vector2.new(2000, 200))
	end)
	if ok and typeof(v) == "Vector2" and v.X > 0 then
		return v.X
	end
	return (utf8.len(s) or #s) * size * 0.6
end

local function label(name: string, parent: Instance, size: number, bold: boolean): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.Active = false
	t.Font = if bold then Enum.Font.GothamBold else Enum.Font.GothamMedium
	t.TextSize = text(size)
	t.TextColor3 = COL.Title
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.Text = ""
	t.Parent = parent
	return t
end

local function frame(name: string, parent: Instance): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Active = false
	f.Parent = parent
	return f
end

local function button(name: string, parent: Instance, caption: string, size: number, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Active = true
	b.Font = Enum.Font.GothamBold
	b.TextSize = text(size)
	b.TextColor3 = COL.Title
	b.Text = caption
	b.Parent = parent
	UIUtil.Corner(b, 10)
	return b
end

-- flag box: atlas crop when art is wired, else banner colour + code (the fallback tile)
local function showFlag(img: ImageLabel, swatch: Frame, code: TextLabel, id: string?)
	local src = if id then NationTexture.Source(id) else nil
	if src then
		img.Image = src.Image
		img.ImageRectOffset = Vector2.new(src.Rect.X, src.Rect.Y)
		img.ImageRectSize = Vector2.new(src.Rect.W, src.Rect.H)
		img.Visible = true
		swatch.Visible = false
		return
	end
	img.Visible = false
	img.Image = ""
	swatch.Visible = true
	local def = NationConfig.Get(id)
	if def then
		swatch.BackgroundColor3 = def.Color
		code.Text = NationConfig.Code(def.Id)
	elseif id == NationConfig.NeutralId then
		swatch.BackgroundColor3 = COL.Neutral -- "No flag": the plain army-green flag
		code.Text = ""
	else
		swatch.BackgroundColor3 = COL.Row -- nothing picked yet
		code.Text = "?"
	end
end

---------------------------------------------------------------------------------------------------------------
-- lists
---------------------------------------------------------------------------------------------------------------

local function buildLists()
	visible = NationConfig.Visible()
	byRegion = {}
	sortKey = {}
	for _, n in ipairs(visible) do
		sortKey[n.Id] = NationConfig.Fold(n.Short)
		local list = byRegion[n.Region]
		if not list then
			list = {}
			byRegion[n.Region] = list
		end
		table.insert(list, n)
	end
	for _, list in pairs(byRegion) do
		table.sort(list, function(a: NationDef, b: NationDef): boolean
			return (sortKey[a.Id] or a.Id) < (sortKey[b.Id] or b.Id)
		end)
	end
end

local function forYouIds(): { string }
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	local function add(id: string?)
		local v = validPickId(id)
		if v and not seen[v] then
			seen[v] = true
			table.insert(out, v)
		end
	end
	if mode ~= "join" then
		add(currentId())
	end
	add(suggestedId)
	for _, id in ipairs(NationConfig.Featured) do
		add(id)
	end
	add(NationConfig.NeutralId)
	return out
end

local function searchQuery(): string
	local box = ui.SearchBox :: TextBox?
	if not box then
		return ""
	end
	return NationConfig.Fold(string.sub(box.Text, 1, SEARCH_MAX_BYTES))
end

local function searchIds(q: string): { string }
	local scored: { { Id: string, Score: number, Key: string } } = {}
	for _, n in ipairs(visible) do
		local s = NationConfig.MatchScore(n, q)
		if s > 0 then
			table.insert(scored, { Id = n.Id, Score = s, Key = sortKey[n.Id] or n.Id })
		end
	end
	if string.find(NationConfig.Fold(NationConfig.NeutralLabel), q, 1, true) then
		table.insert(scored, { Id = NationConfig.NeutralId, Score = 1, Key = "~" })
	end
	table.sort(scored, function(a, b): boolean
		if a.Score ~= b.Score then
			return a.Score > b.Score
		end
		return a.Key < b.Key
	end)
	local out: { string } = {}
	for i = 1, math.min(#scored, SEARCH_MAX) do
		out[i] = scored[i].Id
	end
	return out
end

local function tabIds(key: string): { string }
	if key == "ForYou" then
		return forYouIds()
	elseif key == "Search" then
		local q = searchQuery()
		if q == "" then
			return {}
		end
		return searchIds(q)
	end
	local out: { string } = {}
	for _, n in ipairs(byRegion[key] or {}) do
		table.insert(out, n.Id)
	end
	return out
end

---------------------------------------------------------------------------------------------------------------
-- tiles
---------------------------------------------------------------------------------------------------------------

local selectId: (id: string) -> () -- forward

local function makeTile(i: number): Tile
	local grid = ui.Grid :: ScrollingFrame
	local b = Instance.new("TextButton")
	b.Name = "Tile" .. i
	b.BackgroundColor3 = COL.Row
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Active = true
	b.Text = ""
	b.Visible = false
	b.Parent = grid
	UIUtil.Corner(b, 8)
	local st = Instance.new("UIStroke")
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Color = COL.Gold
	st.Thickness = 3
	st.Enabled = false
	st.Parent = b
	local img = Instance.new("ImageLabel")
	img.Name = "Flag"
	img.BackgroundTransparency = 1
	img.BorderSizePixel = 0
	img.Active = false
	img.ScaleType = Enum.ScaleType.Stretch
	img.Visible = false
	img.Parent = b
	local sw = frame("Swatch", b)
	sw.BackgroundTransparency = 0
	UIUtil.Corner(sw, 4)
	local code = label("Code", sw, 24, true)
	code.Size = UDim2.fromScale(1, 1)
	code.TextXAlignment = Enum.TextXAlignment.Center
	code.TextStrokeColor3 = COL.Ink
	code.TextStrokeTransparency = 0.15
	local name = label("NameLabel", b, 20, true)
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.TextYAlignment = Enum.TextYAlignment.Top
	name.TextWrapped = true
	local badge = label("Badge", b, 20, true)
	badge.BackgroundTransparency = 0
	badge.TextXAlignment = Enum.TextXAlignment.Center
	badge.ZIndex = 3
	badge.Visible = false
	UIUtil.Corner(badge, 6)
	local t: Tile = { Button = b, Flag = img, Swatch = sw, Code = code, Name = name, Badge = badge, Stroke = st, Id = nil }
	b.Activated:Connect(function()
		local id = t.Id
		if id then
			selectId(id)
		end
	end)
	return t
end

local function placeTile(t: Tile, index: number)
	local col = (index - 1) % tileCols
	local row = (index - 1) // tileCols
	t.Button.Position = UDim2.fromOffset(col * (tileW + G.TileGap), row * (G.TileH + G.TileGap))
	t.Button.Size = UDim2.fromOffset(tileW, G.TileH)
	local fw = math.min(G.FlagW, tileW - 16)
	local fh = math.floor(fw * 3 / 4 + 0.5)
	local fx = math.floor((tileW - fw) / 2)
	t.Flag.Position = UDim2.fromOffset(fx, 8)
	t.Flag.Size = UDim2.fromOffset(fw, fh)
	t.Swatch.Position = UDim2.fromOffset(fx, 8)
	t.Swatch.Size = UDim2.fromOffset(fw, fh)
	local ny = 8 + fh + 6
	t.Name.Position = UDim2.fromOffset(4, ny)
	t.Name.Size = UDim2.fromOffset(tileW - 8, G.TileH - ny - 4)
	t.Badge.Position = UDim2.fromOffset(4, 4)
	t.Badge.Size = UDim2.fromOffset(tileW - 8, G.BadgeH)
end

local function paintTile(t: Tile)
	local id = t.Id
	if not id then
		return
	end
	local on = id == selectedId
	t.Stroke.Enabled = on
	t.Button.BackgroundColor3 = if on then COL.RowOn else COL.Row
	local mine = mode ~= "join" and id == currentId()
	if mine then
		t.Badge.Text = "Your flag"
		t.Badge.BackgroundColor3 = COL.Mine
		t.Badge.TextColor3 = COL.GoldInk
		t.Badge.Visible = true
	elseif id == suggestedId then
		t.Badge.Text = "Suggested"
		t.Badge.BackgroundColor3 = COL.Gold
		t.Badge.TextColor3 = COL.GoldInk
		t.Badge.Visible = true
	else
		t.Badge.Visible = false
	end
end

local function layoutTiles()
	local grid = ui.Grid :: ScrollingFrame?
	if not grid then
		return
	end
	for i, t in ipairs(tiles) do
		if t.Button.Visible then
			placeTile(t, i)
		end
	end
	local n = #shownIds
	local rows = if n > 0 then math.ceil(n / tileCols) else 0
	local h = if rows > 0 then rows * G.TileH + (rows - 1) * G.TileGap + 4 else 0
	grid.CanvasSize = UDim2.fromOffset(0, h)
end

local function rebuildTiles(resetScroll: boolean)
	local grid = ui.Grid :: ScrollingFrame?
	if not grid then
		return
	end
	shownIds = tabIds(currentTab)
	for i, id in ipairs(shownIds) do
		local t = tiles[i]
		if not t then
			t = makeTile(i)
			tiles[i] = t
		end
		t.Id = id
		t.Button.Visible = true
		t.Name.Text = shortName(id)
		showFlag(t.Flag, t.Swatch, t.Code, id)
		paintTile(t)
	end
	for i = #shownIds + 1, #tiles do
		local t = tiles[i]
		t.Id = nil
		t.Button.Visible = false
		t.Flag.Image = ""
	end
	layoutTiles()
	if resetScroll then
		grid.CanvasPosition = Vector2.zero
	end
	local hint = ui.Hint :: TextLabel?
	if hint then
		if currentTab == "Search" and #shownIds == 0 then
			hint.Text = if searchQuery() == "" then MSG.SearchHint else MSG.NoMatch -- never the typed text
			hint.Visible = true
		else
			hint.Visible = false
		end
	end
end

-- scroll the grid so the tile of `id` is in view (the current flag on open, the selection after a tab switch)
local function scrollTileIntoView(id: string?)
	local grid = ui.Grid :: ScrollingFrame?
	if not grid or id == nil then
		return
	end
	local index = table.find(shownIds, id)
	if not index then
		return
	end
	local row = (index - 1) // tileCols
	local y = row * (G.TileH + G.TileGap)
	local viewH = grid.Size.Y.Offset
	local cy = grid.CanvasPosition.Y
	if y < cy or y + G.TileH > cy + viewH then
		local maxY = math.max(0, grid.CanvasSize.Y.Offset - viewH)
		grid.CanvasPosition = Vector2.new(0, math.clamp(y - G.TileGap, 0, maxY))
	end
end

local function repaintTiles()
	for _, t in ipairs(tiles) do
		if t.Button.Visible then
			paintTile(t)
		end
	end
end

---------------------------------------------------------------------------------------------------------------
-- preview, status, buttons
---------------------------------------------------------------------------------------------------------------

local function canConfirm(): boolean
	local sel = selectedId
	if busy or sel == nil then
		return false
	end
	if sel == currentId() then
		return false
	end
	return not inCooldown()
end

local function refreshSide()
	if not panel then
		return
	end
	local title = ui.Title :: TextLabel
	title.Text = if mode == "join" then "Choose your nation" else "Your flag"
	local shown = selectedId or (if mode ~= "join" then currentId() else nil)
	showFlag(ui.PrevFlag :: ImageLabel, ui.PrevSwatch :: Frame, ui.PrevCode :: TextLabel, shown)
	local name = ui.PrevName :: TextLabel
	name.Text = if shown then shortName(shown) else MSG.Pick
	-- one message at a time: a result / error, else the cooldown, else the free window, else a hint
	local status = ui.Status :: TextLabel
	local line = ""
	local warnLine = false
	if message then
		line = message
		warnLine = messageWarn
	elseif selectedId ~= nil and selectedId == currentId() then
		line = MSG.Same
	elseif inCooldown() then
		line = "Next change in " .. fmtWait(nextChangeAt() - serverNow())
		warnLine = true
	elseif currentId() ~= nil and attrNumber("WE_NationFreeUntil") > serverNow() then
		line = "Free change for " .. fmtWait(attrNumber("WE_NationFreeUntil") - serverNow())
	end
	status.Text = line
	status.TextColor3 = if warnLine then COL.Warn else COL.Muted
	-- CONFIRM: disabled (grey, taps ignored) until a tile is tapped
	local c = ui.Confirm :: TextButton
	local enabled = canConfirm()
	c.BackgroundColor3 = if enabled then COL.Confirm else COL.Disabled
	c.TextColor3 = if enabled then COL.Title else COL.DisabledText
	c.Text = if busy then "SAVING" else "CONFIRM"
	c:SetAttribute("WE_Enabled", enabled)
	local second = ui.Second :: TextButton
	second.Text = if mode == "join" then "LATER" else "CLOSE"
end

---------------------------------------------------------------------------------------------------------------
-- tabs
---------------------------------------------------------------------------------------------------------------

local function updateFades()
	local strip = ui.Tabs :: ScrollingFrame?
	if not strip then
		return
	end
	local x = strip.CanvasPosition.X
	local maxX = math.max(0, tabsW - stripW)
	;(ui.FadeL :: Frame).Visible = x > 1
	;(ui.FadeR :: Frame).Visible = x < maxX - 1
end

local function scrollTabIntoView(key: string)
	local strip = ui.Tabs :: ScrollingFrame?
	if not strip then
		return
	end
	for _, t in ipairs(tabs) do
		if t.Key == key then
			local cx = strip.CanvasPosition.X
			local target = cx
			if t.X < cx + G.FadeW then
				target = t.X - G.FadeW
			elseif t.X + t.W > cx + stripW - G.FadeW then
				target = t.X + t.W - stripW + G.FadeW
			end
			target = math.clamp(target, 0, math.max(0, tabsW - stripW))
			strip.CanvasPosition = Vector2.new(target, 0)
			break
		end
	end
	updateFades()
end

local function paintTabs()
	for _, t in ipairs(tabs) do
		local b = t.Button
		if b then
			local on = t.Key == currentTab
			b.BackgroundColor3 = if on then COL.Gold else COL.Row
			b.TextColor3 = if on then COL.GoldInk else COL.Title
		end
	end
end

local layoutBody: () -> () -- forward

local function selectTab(key: string, fromTap: boolean?)
	if currentTab ~= key then
		currentTab = key
		if fromTap then
			pcall(AudioController.PlayClick)
		end
	end
	paintTabs()
	layoutBody()
	rebuildTiles(true)
	scrollTileIntoView(selectedId)
	scrollTabIntoView(key)
end

---------------------------------------------------------------------------------------------------------------
-- layout (phone first; recomputed on open and on HudLayout.LayoutChanged while open)
---------------------------------------------------------------------------------------------------------------

type Geo = { PW: number, PH: number, MidX0: number, GridX1: number, ActW: number, ConfirmH: number }
local geo: Geo = { PW = 800, PH = 400, MidX0 = 320, GridX1 = 600, ActW = G.ActW, ConfirmH = G.ConfirmH }

local function computeGeo(): (number, number, Geo)
	local sizeV = HudLayout.ContentSizeV()
	local cw, ch = sizeV.X, sizeV.Y
	local s = HudLayout.Scale()
	if s <= 0 then
		s = 1
	end
	local touch = HudLayout.IsTouch()
	local pw, ph = cw - 2 * G.Margin, ch - 2 * G.Margin
	if not touch then
		pw = math.min(pw, G.DesktopMaxW)
		ph = math.min(ph, G.DesktopMaxH)
	end
	local px0, py0 = (cw - pw) / 2, (ch - ph) / 2
	local midX0 = if touch
		then math.ceil(G.ThumbZone * cw + 4 - px0) -- tabs + grid start right of the thumbstick zone
		else G.Pad + math.floor(pw * 0.32)
	midX0 = math.max(midX0, G.Pad + 160)
	local actX1 = pw - G.Pad
	local actW = G.ActW
	local confirmH = G.ConfirmH
	if touch then
		-- keep the grid and the buttons >= JumpClearPx real px from the Roblox jump button (TouchGui: 70 px at
		-- (-95, -90) from the bottom-right on small screens, 120 px at (-170, -210) otherwise)
		local cam = Workspace.CurrentCamera
		local vp = if cam then cam.ViewportSize else Vector2.new(cw * s, ch * s)
		local small = math.min(vp.X, vp.Y) <= 500
		local jumpLeft = cw - (if small then 95 else 170) / s - px0 -- panel-local v
		local jumpTop = ch - (if small then 90 else 210) / s - py0
		local clear = G.JumpClearPx / s
		local maxGridX1 = jumpLeft - clear
		if actX1 - actW - G.Gap > maxGridX1 then
			actW = actX1 - G.Gap - maxGridX1
		end
		local maxBottom = jumpTop - clear
		if G.Pad + confirmH + G.Gap + G.SecondH > maxBottom then
			confirmH = math.max(G.ConfirmMinH, maxBottom - G.Pad - G.Gap - G.SecondH)
		end
	end
	local gridX1 = actX1 - actW - G.Gap
	return px0, py0, { PW = pw, PH = ph, MidX0 = midX0, GridX1 = gridX1, ActW = actW, ConfirmH = confirmH }
end

layoutBody = function()
	local grid = ui.Grid :: ScrollingFrame?
	if not grid then
		return
	end
	local top = G.Pad + G.TabH + G.Gap
	local gw = geo.GridX1 - geo.MidX0
	local box = ui.SearchBox :: TextBox
	local hint = ui.Hint :: TextLabel
	if currentTab == "Search" then
		box.Visible = true
		box.Position = UDim2.fromOffset(geo.MidX0, top)
		box.Size = UDim2.fromOffset(gw, G.SearchH)
		top += G.SearchH + G.TileGap
	else
		box.Visible = false
	end
	grid.Position = UDim2.fromOffset(geo.MidX0, top)
	grid.Size = UDim2.fromOffset(gw, math.max(G.TileH, geo.PH - G.Pad - top))
	hint.Position = UDim2.fromOffset(geo.MidX0, top)
	hint.Size = UDim2.fromOffset(gw, 60)
	local inner = gw - G.ScrollBar
	tileCols = math.max(1, (inner + G.TileGap) // (G.TileMinW + G.TileGap))
	tileW = math.floor((inner - (tileCols - 1) * G.TileGap) / tileCols)
	layoutTiles()
end

local function relayout()
	local p = panel
	if not p then
		return
	end
	local px0, py0, g = computeGeo()
	geo = g
	p.Position = UDim2.fromOffset(px0, py0)
	p.Size = UDim2.fromOffset(g.PW, g.PH)
	-- preview column (nothing here is tappable: it sits in the thumbstick zone on phones)
	local lw = g.MidX0 - G.Pad - G.ColGap
	local titleT, bodyT, nameT = text(28), text(20), text(28)
	local title = ui.Title :: TextLabel
	title.Position = UDim2.fromOffset(G.Pad, G.Pad)
	title.Size = UDim2.fromOffset(lw, titleT + 8)
	local sub = ui.Sub :: TextLabel
	sub.Position = UDim2.fromOffset(G.Pad, G.Pad + titleT + 10)
	sub.Size = UDim2.fromOffset(lw, bodyT + 6)
	local fy = G.Pad + titleT + 10 + bodyT + 6 + 10
	local statusH = 2 * (bodyT + 4)
	local avail = g.PH - G.Pad - fy - (nameT + 8) - statusH - 8
	local fh = math.max(48, math.min(avail, lw * 3 / 4))
	local fw = math.floor(fh * 4 / 3)
	fh = math.floor(fw * 3 / 4)
	for _, key in ipairs({ "PrevFlag", "PrevSwatch" }) do
		local o = ui[key] :: GuiObject
		o.Position = UDim2.fromOffset(G.Pad, fy)
		o.Size = UDim2.fromOffset(fw, fh)
	end
	local code = ui.PrevCode :: TextLabel
	code.TextSize = math.max(text(28), math.floor(fh * 0.28))
	local name = ui.PrevName :: TextLabel
	name.Position = UDim2.fromOffset(G.Pad, fy + fh + 6)
	name.Size = UDim2.fromOffset(lw, nameT + 8)
	local status = ui.Status :: TextLabel
	status.Position = UDim2.fromOffset(G.Pad, fy + fh + 6 + nameT + 8)
	status.Size = UDim2.fromOffset(lw, statusH)
	-- action column (right): CONFIRM, then LATER / CLOSE
	local ax0 = g.PW - G.Pad - g.ActW
	local c = ui.Confirm :: TextButton
	c.Position = UDim2.fromOffset(ax0, G.Pad)
	c.Size = UDim2.fromOffset(g.ActW, g.ConfirmH)
	local second = ui.Second :: TextButton
	second.Position = UDim2.fromOffset(ax0, G.Pad + g.ConfirmH + G.Gap)
	second.Size = UDim2.fromOffset(g.ActW, G.SecondH)
	-- tab strip (scrolls sideways; edge fades show there is more)
	local strip = ui.Tabs :: ScrollingFrame
	stripW = g.GridX1 - g.MidX0
	strip.Position = UDim2.fromOffset(g.MidX0, G.Pad)
	strip.Size = UDim2.fromOffset(stripW, G.TabH)
	strip.CanvasSize = UDim2.fromOffset(tabsW, 0)
	local fl, fr = ui.FadeL :: Frame, ui.FadeR :: Frame
	fl.Position = UDim2.fromOffset(g.MidX0, G.Pad)
	fl.Size = UDim2.fromOffset(G.FadeW, G.TabH)
	fr.Position = UDim2.fromOffset(g.GridX1 - G.FadeW, G.Pad)
	fr.Size = UDim2.fromOffset(G.FadeW, G.TabH)
	layoutBody()
	scrollTabIntoView(currentTab)
	local sh = shell
	if sh then
		sh.Refit()
	end
end

---------------------------------------------------------------------------------------------------------------
-- open / close / pick
---------------------------------------------------------------------------------------------------------------

local function preloadArt()
	if preloaded then
		return
	end
	preloaded = true
	local seen: { [string]: boolean } = {}
	local list: { any } = {}
	for _, n in ipairs(NationConfig.Visible()) do
		local src = NationTexture.Source(n.Id)
		if src and not seen[src.Image] then
			seen[src.Image] = true
			table.insert(list, src.Image)
		end
	end
	if #list == 0 then
		return -- no art wired yet: colour tiles, nothing to fetch
	end
	task.spawn(function()
		local ok, err = pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
		if not ok then
			warn("[NationController] flag preload failed:", err)
		end
	end)
end

local function setVisible(isOpen: boolean)
	open = isOpen
	local p = panel
	if p then
		p.Visible = isOpen
	end
	local sh = shell
	if sh then
		sh.Sync(isOpen)
	end
end

local function sendLater()
	if laterSent then
		return
	end
	laterSent = true
	local payload = { Action = "later", Source = "join" }
	task.spawn(function()
		Remotes.FireServer(Constants.RemoteNames.RequestSetNation, payload)
	end)
end

-- every close path (LATER / CLOSE, the dim, another panel opening, CloseAllPanels) ends here
local function closePicker()
	if not open then
		return
	end
	local wasJoin = mode == "join"
	setVisible(false)
	local box = ui.SearchBox :: TextBox?
	if box then
		box.Text = "" -- search text is never kept
	end
	if wasJoin and not confirmed and not busy then
		sendLater() -- spec R9: in join mode any close without CONFIRM counts as LATER (once per session)
	end
	for _, t in ipairs(tiles) do
		t.Flag.Image = "" -- release the atlas textures while closed
	end
	local prev = ui.PrevFlag :: ImageLabel?
	if prev then
		prev.Image = ""
	end
end

local function openAs(newMode: string)
	local p = panel
	if not p or not NationConfig.Enabled then
		return
	end
	if open then
		if mode ~= "join" then
			mode = newMode
		end
		refreshSide()
		repaintTiles()
		return
	end
	mode = newMode
	selectedId = nil -- nothing selected at the start (spec R3)
	message = nil
	confirmed = false
	buildLists()
	preloadArt()
	local cur = currentId()
	local def = NationConfig.Get(cur)
	currentTab = if mode ~= "join" and def then def.Region else "ForYou"
	setVisible(true)
	relayout()
	paintTabs()
	rebuildTiles(true)
	if mode ~= "join" then
		scrollTileIntoView(cur) -- the current flag's tile in view
	end
	refreshSide()
end

local function finishPick(serial: number, result: string, nextAt: number?)
	local pd = pending
	if not pd or pd.Serial ~= serial then
		return
	end
	pending = nil
	busy = false
	messageWarn = true
	if result == "ok" then
		confirmed = true
		message = nil
		selectedId = nil
		if open then
			closePicker() -- the server toast says "Flag raised: <Short>"
		end
		return
	elseif result == "cooldown" then
		if typeof(nextAt) == "number" and nextAt == nextAt and nextAt > 0 then
			cooldownAt = nextAt
		end
		message = if inCooldown() then "Next change in " .. fmtWait(nextChangeAt() - serverNow()) else MSG.NoSend
	elseif result == "loading" then
		message = MSG.Loading
	elseif result == "invalid" then
		message = MSG.Invalid
		selectedId = nil
	elseif result == "timeout" then
		message = MSG.NoAnswer
	else
		message = MSG.NoSend
	end
	if open then
		repaintTiles()
		refreshSide()
	end
end

local function confirm()
	if not open or busy then
		return
	end
	local id = selectedId
	if id == nil or not canConfirm() then
		return
	end
	pcall(AudioController.PlayClick)
	busy = true
	pickSerial += 1
	local serial = pickSerial
	pending = { Serial = serial, Id = id }
	message = MSG.Saving
	messageWarn = false
	refreshSide()
	local payload = { Action = "pick", Id = id, Source = mode }
	task.spawn(function()
		-- polls <= 3 s for the remote and returns false when it does not exist (before lane B's server lands)
		local sent = Remotes.FireServer(Constants.RemoteNames.RequestSetNation, payload)
		local pd = pending
		if not pd or pd.Serial ~= serial then
			return
		end
		if not sent then
			finishPick(serial, "nosend")
			return
		end
		task.delay(REPLY_TIMEOUT, function()
			local p2 = pending
			if p2 and p2.Serial == serial then
				finishPick(serial, "timeout")
			end
		end)
	end)
end

selectId = function(id: string)
	if busy or not open then
		return
	end
	local v = validPickId(id)
	if not v then
		return
	end
	pcall(AudioController.PlayClick)
	selectedId = v
	message = nil
	repaintTiles()
	refreshSide()
end

---------------------------------------------------------------------------------------------------------------
-- server state (NationColorUpdate: Suggested / Result only; attributes are the source of truth)
---------------------------------------------------------------------------------------------------------------

local function onState(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local sug = validPickId(payload.Suggested)
	if sug and sug ~= NationConfig.NeutralId and sug ~= suggestedId then
		suggestedId = sug
		if open and currentTab == "ForYou" then
			rebuildTiles(false)
		end
	end
	local res = payload.Result
	if typeof(res) == "string" then
		local nextAt = payload.NextChangeAt
		local n: number? = if typeof(nextAt) == "number" then nextAt else nil
		local pd = pending
		if pd then
			finishPick(pd.Serial, res, n)
		elseif res == "cooldown" and n and n == n then
			cooldownAt = n
		end
	end
end

---------------------------------------------------------------------------------------------------------------
-- auto-open (join)
---------------------------------------------------------------------------------------------------------------

local function artGateOk(): boolean
	return not NationConfig.LiveRequiresArt or artReady or isAdmin
end

local function blocked(): boolean
	for _, f in ipairs(BLOCK_FLAGS) do
		if HudLayout.GetFlag(f) then
			return true
		end
	end
	return false
end

local function autoWanted(): boolean
	return NationConfig.Enabled
		and not autoDone
		and not laterSent
		and player:GetAttribute("WE_NationNeedsPick") == true
		and currentId() == nil
		and artGateOk()
end

local function tryAutoOpen()
	if not autoReady or open or not autoWanted() or blocked() then
		return
	end
	autoDone = true
	openAs("join")
end

-- re-check after the blocking flags have stayed clear for REOPEN_SETTLE (a panel just closed, combat ended ...)
local function scheduleAutoOpen(delaySec: number)
	if autoDone or not autoReady then
		return
	end
	autoSerial += 1
	local s = autoSerial
	task.delay(delaySec, function()
		if s == autoSerial then
			tryAutoOpen()
		end
	end)
end

local function armAutoOpen()
	if autoArmed then
		return
	end
	autoArmed = true
	task.delay(AUTO_OPEN_DELAY, function()
		autoReady = true
		tryAutoOpen()
	end)
end

---------------------------------------------------------------------------------------------------------------
-- build
---------------------------------------------------------------------------------------------------------------

local function buildTabs(strip: ScrollingFrame)
	local list: { { Key: string, Label: string } } = {
		{ Key = "Search", Label = "Search" },
		{ Key = "ForYou", Label = "For you" },
	}
	for _, r in ipairs(NationConfig.RegionOrder) do
		table.insert(list, { Key = r, Label = NationConfig.RegionLabel[r] or r })
	end
	local size = text(20)
	local x = 0
	for i, e in ipairs(list) do
		local w = math.max(G.TabMinW, math.ceil(textWidth(e.Label, size)) + G.TabPadX)
		local b = button("Tab_" .. e.Key, strip, e.Label, 20, COL.Row)
		b.Position = UDim2.fromOffset(x, 0)
		b.Size = UDim2.fromOffset(w, G.TabH)
		b.LayoutOrder = i
		local key = e.Key
		b.Activated:Connect(function()
			if open then
				selectTab(key, true)
			end
		end)
		table.insert(tabs, { Key = e.Key, Label = e.Label, Button = b, X = x, W = w })
		x += w + G.TabGap
	end
	tabsW = math.max(0, x - G.TabGap)
end

local function fade(name: string, parent: Instance, leftSide: boolean): Frame
	local f = frame(name, parent)
	f.BackgroundTransparency = 0
	f.BackgroundColor3 = COL.Panel
	f.ZIndex = 4
	f.Visible = false
	local g = Instance.new("UIGradient")
	g.Transparency = if leftSide
		then NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		else NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
	g.Parent = f
	return f
end

local function build(pg: Instance)
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireNation"
	PanelShell.Screen(screen) -- DisplayOrder 60 (Panels), Core safe insets, the one HUD UIScale
	screen.Parent = pg

	local p = Instance.new("Frame")
	p.Name = "Panel"
	p.BackgroundColor3 = COL.Panel
	p.BorderSizePixel = 0
	p.Active = true -- sinks taps on the panel background (the dim closes only outside it)
	p.Visible = false
	p.Parent = screen
	UIUtil.Corner(p, 14)
	UIUtil.Stroke(p, COL.Stroke, 2)
	panel = p

	-- preview column
	local title = label("Title", p, 28, true)
	title.Font = HudConfig.Fonts.Display
	title.Text = "Choose your nation"
	title.TextTruncate = Enum.TextTruncate.AtEnd
	UIUtil.TextOutline(title, 1.5)
	ui.Title = title
	local sub = label("Sub", p, 20, false)
	sub.TextColor3 = COL.Muted
	sub.TextTruncate = Enum.TextTruncate.AtEnd
	sub.Text = "Your flag flies over your base"
	ui.Sub = sub
	local img = Instance.new("ImageLabel")
	img.Name = "PrevFlag"
	img.BackgroundTransparency = 1
	img.BorderSizePixel = 0
	img.Active = false
	img.ScaleType = Enum.ScaleType.Stretch
	img.Visible = false
	img.Parent = p
	ui.PrevFlag = img
	local sw = frame("PrevSwatch", p)
	sw.BackgroundTransparency = 0
	sw.BackgroundColor3 = COL.Neutral
	UIUtil.Corner(sw, 6)
	UIUtil.Stroke(sw, COL.Stroke, 2)
	ui.PrevSwatch = sw
	local code = label("PrevCode", sw, 28, true)
	code.Size = UDim2.fromScale(1, 1)
	code.TextXAlignment = Enum.TextXAlignment.Center
	code.TextStrokeColor3 = COL.Ink
	code.TextStrokeTransparency = 0.15
	ui.PrevCode = code
	local name = label("PrevName", p, 28, true)
	name.Font = HudConfig.Fonts.Display
	name.TextTruncate = Enum.TextTruncate.AtEnd
	UIUtil.TextOutline(name, 1.5)
	ui.PrevName = name
	local status = label("Status", p, 20, false)
	status.TextColor3 = COL.Muted
	status.TextWrapped = true
	status.TextYAlignment = Enum.TextYAlignment.Top
	ui.Status = status

	-- tabs
	local strip = Instance.new("ScrollingFrame")
	strip.Name = "Tabs"
	strip.BackgroundTransparency = 1
	strip.BorderSizePixel = 0
	strip.ScrollingDirection = Enum.ScrollingDirection.X
	strip.ScrollBarThickness = 0
	strip.CanvasSize = UDim2.fromOffset(0, 0)
	strip.ElasticBehavior = Enum.ElasticBehavior.Never
	strip.Parent = p
	ui.Tabs = strip
	buildTabs(strip)
	ui.FadeL = fade("FadeL", p, true)
	ui.FadeR = fade("FadeR", p, false)
	strip:GetPropertyChangedSignal("CanvasPosition"):Connect(updateFades)

	-- search (this device only)
	local box = Instance.new("TextBox")
	box.Name = "SearchBox"
	box.BackgroundColor3 = COL.Row
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Font = Enum.Font.GothamMedium
	box.TextSize = text(22)
	box.TextColor3 = COL.Title
	box.PlaceholderText = "Type a country"
	box.PlaceholderColor3 = COL.Muted
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Text = ""
	box.Visible = false
	box.Parent = p
	UIUtil.Corner(box, 10)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = box
	ui.SearchBox = box
	box:GetPropertyChangedSignal("Text"):Connect(function()
		searchSerial += 1
		local s = searchSerial
		task.delay(SEARCH_DEBOUNCE, function()
			if s == searchSerial and open and currentTab == "Search" then
				rebuildTiles(true)
			end
		end)
	end)

	-- grid
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.ScrollBarThickness = 6
	grid.CanvasSize = UDim2.fromOffset(0, 0)
	grid.Parent = p
	ui.Grid = grid
	local hint = label("Hint", p, 20, false)
	hint.TextColor3 = COL.Muted
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.Visible = false
	ui.Hint = hint

	-- action column
	local c = button("Confirm", p, "CONFIRM", 24, COL.Disabled)
	c.Font = HudConfig.Fonts.Display
	c.Activated:Connect(confirm)
	ui.Confirm = c
	local second = button("Second", p, "LATER", 22, COL.Second)
	second.Activated:Connect(function()
		pcall(AudioController.PlayClick)
		closePicker()
	end)
	ui.Second = second

	shell = PanelShell.Attach({
		Id = PANEL_ID,
		Screen = screen,
		Panel = p,
		IsOpen = function(): boolean
			return open
		end,
		Close = closePicker,
	})
end

---------------------------------------------------------------------------------------------------------------
-- public
---------------------------------------------------------------------------------------------------------------

function NationController.Init()
	if not NationConfig.Enabled then
		return
	end
	local pg = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
	if not pg then
		warn("[NationController] no PlayerGui; picker off this session")
		return
	end
	isAdmin = table.find(AdminConfig.UserIds, player.UserId) ~= nil
	artReady = NationTexture.ArtReady()
	build(pg)

	Remotes.BindEvent(Constants.RemoteNames.NationColorUpdate, onState)
	player:GetAttributeChangedSignal("WE_NationNeedsPick"):Connect(function()
		if player:GetAttribute("WE_NationNeedsPick") == true and artGateOk() then
			preloadArt()
		end
		tryAutoOpen()
	end)
	player:GetAttributeChangedSignal("WE_NationId"):Connect(function()
		cooldownAt = 0 -- the attributes are the source of truth again
		local pd = pending
		if pd and currentId() == pd.Id then
			finishPick(pd.Serial, "ok")
		end
		if open then
			repaintTiles()
			refreshSide()
		end
	end)
	for _, a in ipairs({ "WE_NationNextAt", "WE_NationFreeUntil" }) do
		player:GetAttributeChangedSignal(a):Connect(function()
			cooldownAt = 0 -- a "cooldown" reply only bridges the gap until the server's attributes arrive
			if open then
				refreshSide()
			end
		end)
	end
	HudLayout.FlagChanged:Connect(function(flagName: string, on: boolean)
		if on or autoDone or not autoReady then
			return
		end
		if table.find(BLOCK_FLAGS, flagName) then
			scheduleAutoOpen(REOPEN_SETTLE)
		end
	end)
	HudLayout.LayoutChanged:Connect(function()
		if open then
			relayout()
		end
	end)
	if player:GetAttribute("WE_NationNeedsPick") == true and artGateOk() then
		preloadArt()
	end
	if player.Character then
		armAutoOpen()
	end
	player.CharacterAdded:Connect(armAutoOpen)
end

--[[ Open from the flagpole prompt (tab "flagpole") or Settings (nil). UIController panelOpeners.Nation. ]]
function NationController.Open(tab: any?)
	-- a player with no base can see other players' owner-only prompts (PromptController treats "no plot" as not
	-- foreign), so a flagpole tap from them is never theirs; and nobody but an admin opens it before the art is live
	if tab == "flagpole" and player:GetAttribute("WE_NoPlot") == true then
		return
	end
	if not artGateOk() then
		return
	end
	openAs(if tab == "flagpole" then "flagpole" else "settings")
end

function NationController.Close()
	closePicker()
end

function NationController.IsOpen(): boolean
	return open
end

--[[ test hook (headless harness): the picker state. Never used by game code. ]]
function NationController._Debug(): { [string]: any }
	return {
		Open = open,
		Mode = mode,
		Tab = currentTab,
		Selected = selectedId,
		Suggested = suggestedId,
		Busy = busy,
		Message = message,
		LaterSent = laterSent,
		AutoDone = autoDone,
		Shown = table.clone(shownIds),
		Cols = tileCols,
		CanConfirm = canConfirm(),
	}
end

return NationController
