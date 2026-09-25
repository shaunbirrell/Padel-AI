--!strict
--[[ Territory HUD — v70 "clean screen" (spec §3.4 + the E row of §9; was Phase 5/7's capture card, alert label,
	always-on TERRITORIES list and RADAR badge).

	* CAPTURE BAR: a top-centre stack item ("Capture", slot Progress — HudLayout.RegisterTopStack) built from the
	  shared ProgressPill (320×44 v): "CAPTURING RADAR HILL  62%". It reads only TerritoryStateUpdate.LocalCapture,
	  so it works the same for land outposts and the v70 naval outposts (oil rigs taken by a boat's driver or from
	  the deck) and stays visible while Driving. Contested → amber edge + "CONTESTED · NAME" and the nation-colour
	  pulse (contestedPulseActive); Protected → blue "PROTECTED · NAME" (capture slowed).
	* F3 "Empire Tax +N%" → one silent Info toast through NotificationController when the server's WE_EmpireTaxPct
	  (EconomyConfig.OutpostIncomeBuff.Attribute) rises or falls to N > 0 (it replaced "Outposts held: N"). Skipped
	  when a server toast named Empire Tax within TAX.SkipWindow (2 s) of the change (the capture / loss toasts carry
	  the %), and while joining. The old mid-screen TerritoryAlert label and its 50 % / 90 % lines are gone.
	* TERRITORY LIST → a dropdown under the compass chip, opened by HudLayout.Signals.CompassTapped (the compass chip
	  and the TopStrip Empire Tax chip both emit it; it was an always-on panel over the rail). It is a registered
	  panel ("Territories"): one panel at a time and Modal while open, so the combat buttons hide and the list may
	  use the right-hand column down to the jump button. ✕, a tap outside, another panel, Driving or death close it.
	  Header "Empire Tax +N%" (gold) while N > 0, else "TERRITORIES".
	* F10 Home Outposts: the list shows only the player's OWN one (TerritoryConfig.Starter rows, PlotId = the own
	  plot from BaseStateUpdate / PlayerStateUpdate); other plots' Home Outposts are never listed or counted.
	* RADAR HILL reveal → the HudLayout flag "Radar" (CompassController draws the purple dot on the chip) + the
	  enemy Highlights (kept) + a "RADAR ON" row in the list.
	* W3 step 2 lane U0 — ONE AlwaysOnTop label: TerritoryService makes a flag's WE_FlagBillboard diamond draw through
	  walls while the zone is contested (WorldLabel.SetRole "contested"). While an objective marker is on screen
	  (ObjectiveMarker.OnTop(): a mission GO line, or the ConsoleWaypoint line it yields to) this client turns that
	  off LOCALLY and restores the server's choice (the role) when the marker goes. Checked at 4 Hz (diamonds found by
	  the capture-zone tags, rescanned once a second only while a marker is up; no whole-tree scan).
	Display only: capture, ownership and payouts are server-side (TerritoryService).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60) -- ships with the place (Rojo); bounded wait anyway
local Constants = require(Shared.Constants)
local HudConfig = require(Shared.Configs.HudConfig)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local TerritoryConfig = require(Shared.Configs.TerritoryConfig)
local EconomyConfig = require(Shared.Configs.EconomyConfig)
local WorldLabelConfig = require(Shared.Configs.WorldLabelConfig)
local UIUtil = require(Shared.Util.UIUtil)

local HudLayout = require(script.Parent.Parent.Modules.HudLayout)
local HudIcons = require(script.Parent.Parent.Modules.HudIcons)
local ProgressPill = require(script.Parent.Parent.Modules.ProgressPill)
local ObjectiveMarker = require(script.Parent.Parent.Modules.ObjectiveMarker)
local NotificationController = require(script.Parent.NotificationController)

local TerritoryController = {}

local player = Players.LocalPlayer
local _gui: ScreenGui? = nil

-- capture bar
local capture: ProgressPill.Pill? = nil
local captureActive = false
-- v38: contested dual-color pulse cache (v70: amber when the server sends no nation colours)
local contestedPulseActive = false
local contestedColA: Color3? = nil
local contestedColB: Color3? = nil

-- radar
local radarActive = false
local radarRadius = 550
local radarHighlights: { [number]: Highlight } = {}

-- F3 Empire Tax toast + list header (see the header comment)
local BUFF = EconomyConfig.OutpostIncomeBuff
local TAX = {
	Attr = (BUFF and BUFF.Attribute) or "WE_EmpireTaxPct",
	Name = (BUFF and BUFF.DisplayName) or "Empire Tax",
	SkipWindow = 2, -- s: a server toast naming Empire Tax this close to the change already said it
	Settle = 0.6, -- s: decide this long after the change, so a server toast landing just after the attribute counts
	JoinQuietSeconds = 10, -- s after the first TerritoryStateUpdate: re-planted claims / the Home Outpost never toast
	Color = ((HudConfig.TopStrip :: any).EmpireTax and (HudConfig.TopStrip :: any).EmpireTax.Color) or HudConfig.Colors.Gold,
}
local taxPct = 0
local taxBaselineAt: number? = nil -- os.clock() of the first TerritoryStateUpdate (nil: still joining)
local taxToken = 0
local lastServerTaxToastAt = -math.huge

-- F10: the own plot (BaseStateUpdate / PlayerStateUpdate), for the own-Home-Outpost-only list
local myPlotId: number? = nil

-- dropdown list (panel "Territories")
local PANEL_ID = "Territories"
local listPanel: Frame? = nil
local listScroll: ScrollingFrame? = nil
local listCount: TextLabel? = nil
local listTitle: TextLabel? = nil
local listDim: Frame? = nil
local listOpen = false
local listDirty = true
local lastPayload: Types.TerritoryStatePayload? = nil

-- Dropdown geometry, v (the gui carries HudLayout's MobileScale). Candidates for HudConfig.TopStrip.Compass.List.
local LIST = {
	Width = 300,
	WidthTouch = 340, -- room for 20 v names ("Coastal Oil Bravo") beside a 20 v tag
	RowH = 30,
	Gap = 6, -- under the compass chip
	PadX = 12,
	PadBottom = 8,
	TitleSize = 20,
	TextSize = 16, -- desktop (the HUD scale there keeps it >= 14 real px)
	TextSizeTouch = 20, -- 14 real px at the phone scale 0.70 (CLAUDE.md text floor; was 16 v = 11.2 px)
	CountWidth = 56, -- "3/12" right of the title
	TagWidth = 104,
	TagWidthTouch = 112, -- "CONTESTED" at 20 v
	DotSize = 10,
	MinHeight = 140,
	-- touch: stay above Roblox's jump button (top at H − 90 real, see HudConfig.TouchCombat) plus a 10 px gap
	JumpClearPx = 100,
	Bg = HudConfig.Colors.PillBg,
	BgTransparency = 0.12,
	Corner = 14,
}

local COL = {
	You = HudConfig.Colors.Positive,
	Enemy = HudConfig.Colors.Negative,
	Clan = Color3.fromRGB(120, 180, 255),
	Guarded = Color3.fromRGB(255, 150, 60),
	Neutral = HudConfig.Colors.Muted,
	Contested = HudConfig.TopStack.Progress.ContestedColor,
	Protected = Color3.fromRGB(140, 180, 255),
	Radar = HudConfig.TopStrip.Compass.RadarDot,
}

local function textSizeV(): number
	return if HudLayout.IsTouch() then LIST.TextSizeTouch else LIST.TextSize
end

local function tagWidthV(): number
	return if HudLayout.IsTouch() then LIST.TagWidthTouch else LIST.TagWidth
end

local function touchMinV(): number
	if HudLayout.IsTouch() then
		-- 64 v = 44.8 real px at the smallest HUD scale (0.70)
		return math.max(HudConfig.Hotbar.Slot, math.ceil(HudConfig.Scale.TouchMinPx / HudConfig.Scale.Min))
	end
	return 44
end

---------------------------------------------------------------------------------------------------------------
-- radar (Radar Hill reveal) — unchanged behaviour, the badge became the "Radar" flag
---------------------------------------------------------------------------------------------------------------

local function clearRadarHighlights()
	for userId, h in pairs(radarHighlights) do
		if h and h.Parent then
			h:Destroy()
		end
		radarHighlights[userId] = nil
	end
end

local function ensureHighlight(target: Model): Highlight
	local existing = target:FindFirstChild("WE_RadarHighlight")
	if existing and existing:IsA("Highlight") then
		return existing
	end
	local h = Instance.new("Highlight")
	h.Name = "WE_RadarHighlight"
	h.FillColor = Color3.fromRGB(200, 80, 80)
	h.OutlineColor = Color3.fromRGB(255, 180, 80)
	h.FillTransparency = 0.65
	h.OutlineTransparency = 0.15
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Parent = target
	return h
end

local function updateRadar()
	if not radarActive then
		clearRadarHighlights()
		return
	end
	local myChar = player.Character
	local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not myRoot then
		clearRadarHighlights()
		return
	end

	local seen: { [number]: boolean } = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local char = other.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			if char and root and humanoid and humanoid.Health > 0 then
				local dist = (root.Position - myRoot.Position).Magnitude
				if dist <= radarRadius then
					seen[other.UserId] = true
					local h = ensureHighlight(char)
					radarHighlights[other.UserId] = h
				end
			end
		end
	end
	for userId, h in pairs(radarHighlights) do
		if not seen[userId] then
			if h and h.Parent then
				h:Destroy()
			end
			radarHighlights[userId] = nil
		end
	end
end

---------------------------------------------------------------------------------------------------------------
-- W3 step 2 lane U0: the contested diamond yields to the one objective marker (see the header)
---------------------------------------------------------------------------------------------------------------

local DIAMOND = {
	Name = "WE_FlagBillboard", -- TerritoryService's diamond over <TerritoryId>_Flag
	CheckSeconds = 0.25, -- is an objective marker up? (4 Hz; CLAUDE.md UI refresh <= 10 Hz)
	RescanSeconds = 1, -- while one is up: find diamonds that streamed in since
}
local ROLE_ATTR = WorldLabelConfig.RoleAttribute
local MARKER_TAGS = { Constants.Tags.CaptureZone, Constants.Tags.Territory }
local diamonds: { [BillboardGui]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local markerOnTop = false
local diamondAccum = 0
local rescanAccum = 0

-- what the server wants (WorldLabel.SetRole wrote the role before AlwaysOnTop), unless an objective marker is up
local function diamondOnTop(bb: BillboardGui): boolean
	if markerOnTop then
		return false
	end
	local role = bb:GetAttribute(ROLE_ATTR)
	return type(role) == "string" and WorldLabelConfig.AlwaysOnTopRoles[role] == true
end

local function applyDiamond(bb: BillboardGui)
	local want = diamondOnTop(bb)
	if bb.AlwaysOnTop ~= want then
		bb.AlwaysOnTop = want
	end
end

local function watchDiamond(bb: BillboardGui)
	if diamonds[bb] then
		applyDiamond(bb)
		return
	end
	diamonds[bb] = true
	-- a contest starting replicates AlwaysOnTop = true (and the role): yield again at once while a marker is up
	bb:GetPropertyChangedSignal("AlwaysOnTop"):Connect(function()
		if markerOnTop and bb.AlwaysOnTop then
			bb.AlwaysOnTop = false
		end
	end)
	bb:GetAttributeChangedSignal(ROLE_ATTR):Connect(function()
		if markerOnTop and bb.AlwaysOnTop then
			bb.AlwaysOnTop = false
		end
	end)
	applyDiamond(bb)
end

-- the diamonds on this client (StreamingEnabled: only nearby zones), found through the capture-zone tags
local function rescanDiamonds()
	for _, tag in ipairs(MARKER_TAGS) do
		for _, inst in ipairs(CollectionService:GetTagged(tag)) do
			local tid = inst:GetAttribute("TerritoryId")
			local parent = inst.Parent
			if type(tid) == "string" and parent and inst:IsA("BasePart") then
				local flag = parent:FindFirstChild(tid .. "_Flag")
				local bb = flag and flag:FindFirstChild(DIAMOND.Name)
				if bb and bb:IsA("BillboardGui") then
					watchDiamond(bb)
				end
			end
		end
	end
end

local function syncDiamonds(elapsed: number)
	local on = ObjectiveMarker.OnTop()
	if on ~= markerOnTop then
		markerOnTop = on
		rescanAccum = 0
		if on then
			rescanDiamonds()
		end
		for bb in pairs(diamonds) do
			if bb.Parent then
				applyDiamond(bb)
			end
		end
		return
	end
	if on then
		rescanAccum += elapsed
		if rescanAccum >= DIAMOND.RescanSeconds then
			rescanAccum = 0
			rescanDiamonds()
		end
	end
end

-- test hook (client sims): the yield state right now
function TerritoryController._DiamondYield(): boolean
	return markerOnTop
end

---------------------------------------------------------------------------------------------------------------
-- territory dropdown
---------------------------------------------------------------------------------------------------------------

type RowInfo = { Name: string, Tag: string, Color: Color3, NameColor: Color3, Rank: number }

local function describe(entry: Types.TerritoryEntryPayload, capturingId: string?, capturePct: number): RowInfo
	local name = tostring(entry.DisplayName or entry.Id)
	if capturingId ~= nil and entry.Id == capturingId then
		return { Name = name, Tag = string.format("%d%%", capturePct), Color = HudConfig.Colors.Gold, NameColor = HudConfig.Colors.White, Rank = 1 }
	end
	if entry.Contested then
		return { Name = name, Tag = "CONTESTED", Color = COL.Contested, NameColor = HudConfig.Colors.White, Rank = 2 }
	end
	local owner = entry.OwnerType
	if owner == "Player" and entry.OwnerUserId == player.UserId then
		return { Name = name, Tag = "YOU", Color = COL.You, NameColor = HudConfig.Colors.White, Rank = 0 }
	elseif owner == "Player" then
		return { Name = name, Tag = "ENEMY", Color = COL.Enemy, NameColor = HudConfig.Colors.White, Rank = 3 }
	elseif owner == "Clan" then
		return { Name = name, Tag = "CLAN", Color = COL.Clan, NameColor = HudConfig.Colors.White, Rank = 3 }
	elseif owner == "NPC" then
		return { Name = name, Tag = "GUARDED", Color = COL.Guarded, NameColor = HudConfig.Colors.White, Rank = 4 }
	end
	return { Name = name, Tag = "NEUTRAL", Color = COL.Neutral, NameColor = COL.Neutral, Rank = 5 }
end

-- F10: the plot a Home Outpost row belongs to (TerritoryConfig.Starter rows: IsStarter + PlotId, or the Starter_P<n>
-- id when this client's config has no such row); nil = not a Home Outpost, -1 = a Home Outpost of unknown plot
local function starterPlotOf(id: string): number?
	local st = TerritoryConfig.Starter
	local prefix = if st and type(st.IdPrefix) == "string" and st.IdPrefix ~= "" then st.IdPrefix else "Starter_P"
	local def = TerritoryConfig.Territories[id]
	local named = string.sub(id, 1, #prefix) == prefix
	if not (TerritoryConfig.IsStarterDef(def) or named) then
		return nil
	end
	local fromDef = if def then tonumber(def.PlotId) else nil
	return fromDef or (if named then tonumber(string.sub(id, #prefix + 1)) else nil) or -1
end

--[[ F10, pure (exported for the client sim): does the dropdown list this row? Every zone, except Home Outposts: only
	the one on the player's own plot (myPlot); while the plot is not known yet, only one the player holds. ]]
function TerritoryController.Lists(entry: Types.TerritoryEntryPayload, myPlot: number?, myUserId: number): boolean
	local plot = starterPlotOf(tostring(entry.Id))
	if plot == nil then
		return true
	end
	if myPlot ~= nil then
		return plot == myPlot
	end
	return entry.OwnerType == "Player" and entry.OwnerUserId == myUserId
end

local function listed(payload: Types.TerritoryStatePayload?): { Types.TerritoryEntryPayload }
	local out = {}
	for _, entry in ipairs(if payload then payload.Territories or {} else {}) do
		if typeof(entry) == "table" and TerritoryController.Lists(entry, myPlotId, player.UserId) then
			table.insert(out, entry)
		end
	end
	return out
end

local function rowCount(payload: Types.TerritoryStatePayload?): number
	if not payload then
		return 1
	end
	local n = #listed(payload)
	if n == 0 then
		n = 1 -- the empty-state line
	end
	if payload.RadarReveal == true then
		n += 1
	end
	return n
end

local function makeText(parent: Instance, name: string, text: string, color: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Font = HudConfig.Fonts.Body
	t.TextSize = textSizeV()
	t.TextColor3 = color
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Text = text
	t.Active = false
	t.ZIndex = 7
	t.Parent = parent
	return t
end

local function rebuildList()
	local scroll = listScroll
	local payload = lastPayload
	if not scroll then
		return
	end
	listDirty = false
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local list = listed(payload)
	local lc = if payload then payload.LocalCapture else nil
	local capId: string? = nil
	local capPct = 0
	if lc and lc.Capturing and lc.TerritoryId then
		capId = lc.TerritoryId
		capPct = math.floor(math.clamp(tonumber(lc.Progress) or 0, 0, 1) * 100)
	end

	local order = 0
	if payload and payload.RadarReveal == true then
		local r = makeText(scroll, "RadarRow", string.format("RADAR ON · %d studs", math.floor(radarRadius)), COL.Radar)
		r.Size = UDim2.new(1, 0, 0, LIST.RowH)
		r.LayoutOrder = order
		order += 1
	end

	local rows: { RowInfo } = {}
	local owned = 0
	for _, entry in ipairs(list) do
		local info = describe(entry, capId, capPct)
		if info.Tag == "YOU" then
			owned += 1
		end
		table.insert(rows, info)
	end
	table.sort(rows, function(a: RowInfo, b: RowInfo): boolean
		if a.Rank ~= b.Rank then
			return a.Rank < b.Rank
		end
		return a.Name < b.Name
	end)

	if #rows == 0 then
		local e = makeText(scroll, "Empty", "No territories yet — explore the map.", COL.Neutral)
		e.Size = UDim2.new(1, 0, 0, LIST.RowH)
		e.LayoutOrder = order
	end
	for _, info in ipairs(rows) do
		local row = Instance.new("Frame")
		row.Name = "Row_" .. info.Name
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, LIST.RowH)
		row.LayoutOrder = order
		row.Active = false
		row.ZIndex = 6
		order += 1

		local dot = Instance.new("Frame")
		dot.Name = "Dot"
		dot.AnchorPoint = Vector2.new(0, 0.5)
		dot.Position = UDim2.new(0, 0, 0.5, 0)
		dot.Size = UDim2.fromOffset(LIST.DotSize, LIST.DotSize)
		dot.BackgroundColor3 = info.Color
		dot.BorderSizePixel = 0
		dot.Active = false
		dot.ZIndex = 7
		dot.Parent = row
		UIUtil.Corner(dot, math.ceil(LIST.DotSize / 2))

		local nameLabel = makeText(row, "Name", info.Name, info.NameColor)
		nameLabel.Position = UDim2.fromOffset(LIST.DotSize + 8, 0)
		nameLabel.Size = UDim2.new(1, -(LIST.DotSize + 8 + tagWidthV()), 1, 0)

		local tag = makeText(row, "Tag", info.Tag, info.Color)
		tag.AnchorPoint = Vector2.new(1, 0)
		tag.Position = UDim2.fromScale(1, 0)
		tag.Size = UDim2.new(0, tagWidthV(), 1, 0)
		tag.TextXAlignment = Enum.TextXAlignment.Right

		row.Parent = scroll
	end

	local cnt = listCount
	if cnt then
		cnt.Text = string.format("%d/%d", owned, #list)
	end
end

local function headerV(): number
	return touchMinV()
end

-- Position / size in the gui's v space, right-aligned under the compass chip (HudLayout.GetRect("Compass")),
-- down to the jump button on touch. Rects are AbsolutePosition space, like HudLayout's.
local function placeList()
	local f = listPanel
	local screen = _gui
	if not (f and screen) then
		return
	end
	local s = HudLayout.Scale()
	if s <= 0 then
		s = 1
	end
	local content = HudLayout.ContentRect()
	local guiPos = screen.AbsolutePosition
	local cpos, csize = HudLayout.GetRect("Compass")
	local right: number
	local top: number
	-- use the chip only when it really sits in the topbar row (its bottom at or above the content top);
	-- otherwise (no chip yet, a fallback placement) hang the list from the content's top-right corner
	local chipBottom = cpos.Y + csize.Y
	if csize.X > 1 and csize.Y > 1 and chipBottom <= content.Min.Y + HudConfig.TopStack.Top * s then
		right = cpos.X + csize.X
		top = math.max(chipBottom, content.Min.Y) + LIST.Gap * s
	else
		right = content.Max.X - HudConfig.Edge * s
		top = content.Min.Y + HudConfig.TopStack.Top * s
	end
	right = math.min(right, content.Max.X)
	local bottom = content.Max.Y - (if HudLayout.IsTouch() then LIST.JumpClearPx else HudConfig.Edge * s)
	local availV = math.max(LIST.MinHeight, (bottom - top) / s)
	local widthV = math.max(200, math.min(if HudLayout.IsTouch() then LIST.WidthTouch else LIST.Width, (right - content.Min.X) / s - HudConfig.Edge))
	-- whole rows only (the rest scrolls), so no row is ever cut in half at the bottom edge
	local hv = headerV()
	local fitRows = math.max(1, math.floor((availV - hv - LIST.PadBottom) / LIST.RowH))
	local shown = math.min(rowCount(lastPayload), fitRows)
	f.Size = UDim2.fromOffset(widthV, hv + shown * LIST.RowH + LIST.PadBottom)
	f.Position = UDim2.fromOffset((right - guiPos.X) / s, (top - guiPos.Y) / s)
end

local function setListOpen(open: boolean)
	if listOpen == open then
		return
	end
	listOpen = open
	local f = listPanel
	local dim = listDim
	if open then
		if listDirty then
			rebuildList()
		end
		placeList()
	end
	if f then
		f.Visible = open
	end
	if dim then
		dim.Visible = open
	end
	if open then
		HudLayout.PanelOpened(PANEL_ID)
	else
		HudLayout.PanelClosed(PANEL_ID)
	end
end

function TerritoryController.IsOpen(): boolean
	return listOpen
end

function TerritoryController.Close()
	setListOpen(false)
end

function TerritoryController.Toggle()
	setListOpen(not listOpen)
end

local function buildList(screen: ScreenGui)
	local f = Instance.new("Frame")
	f.Name = "TerritoryList"
	f.AnchorPoint = Vector2.new(1, 0)
	f.Position = UDim2.new(1, -HudConfig.Edge, 0, HudConfig.TopStack.Top)
	f.Size = UDim2.fromOffset(LIST.Width, LIST.MinHeight)
	f.BackgroundColor3 = LIST.Bg
	f.BackgroundTransparency = LIST.BgTransparency
	f.BorderSizePixel = 0
	f.Active = true -- taps on the list never reach the world
	f.Visible = false
	f.ZIndex = 5
	f.Parent = screen
	UIUtil.Corner(f, LIST.Corner)
	local st = UIUtil.Stroke(f, HudConfig.Colors.PillStroke, 2)
	st.Transparency = HudConfig.Colors.PillStrokeTransparency
	listPanel = f

	local hv = headerV()
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(LIST.PadX, 0)
	-- up to the count (F3: "Empire Tax +50%" is longer than "TERRITORIES")
	title.Size = UDim2.new(1, -(LIST.PadX + LIST.CountWidth + hv + 4), 0, hv)
	title.Font = HudConfig.Fonts.Display
	title.TextSize = LIST.TitleSize
	title.TextColor3 = HudConfig.Colors.White
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Text = "TERRITORIES"
	title.Active = false
	title.ZIndex = 7
	title.Parent = f
	UIUtil.TextOutline(title, 1.4)
	listTitle = title

	local count = makeText(f, "Count", "0/0", HudConfig.Colors.Muted)
	count.AnchorPoint = Vector2.new(1, 0)
	count.Position = UDim2.new(1, -(hv + 4), 0, 0)
	count.Size = UDim2.new(0, LIST.CountWidth, 0, hv)
	count.TextXAlignment = Enum.TextXAlignment.Right
	listCount = count

	-- ✕: transparent touch-size hit area around a small rounded face (same look as the panels' close button)
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.Size = UDim2.fromOffset(hv, hv)
	close.BackgroundTransparency = 1
	close.BorderSizePixel = 0
	close.AutoButtonColor = false
	close.Text = ""
	close.Active = true
	close.ZIndex = 7
	close.Parent = f
	local face = Instance.new("Frame")
	face.Name = "Face"
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.fromScale(0.5, 0.5)
	face.Size = UDim2.fromScale(0.6, 0.6)
	face.BackgroundColor3 = Color3.fromRGB(44, 48, 54)
	face.BorderSizePixel = 0
	face.Active = false
	face.ZIndex = 7
	face.Parent = close
	UIUtil.Corner(face, 10)
	HudIcons.Make("Close", face, {
		Size = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 8,
		Color = HudConfig.Colors.White,
		Fill = Color3.fromRGB(44, 48, 54),
	})
	close.Activated:Connect(function()
		setListOpen(false)
	end)
	HudLayout.AssertTouchTarget(close, "TerritoryList.Close")

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.Position = UDim2.fromOffset(LIST.PadX, hv)
	scroll.Size = UDim2.new(1, -LIST.PadX * 2, 1, -(hv + LIST.PadBottom))
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ZIndex = 6
	scroll.Parent = f
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 0)
	layout.Parent = scroll
	listScroll = scroll

	-- tap / click outside the list closes it (invisible catcher: the world stays visible, Active = false)
	local dim = UIUtil.MakeModalDim(screen, function()
		if listOpen then
			setListOpen(false)
		end
	end, f)
	dim.BackgroundTransparency = 1
	dim.Visible = false
	listDim = dim

	HudLayout.RegisterPanel(PANEL_ID, function(): boolean
		return listOpen
	end, function()
		setListOpen(false)
	end)
	HudLayout.Signals.CompassTapped:Connect(function()
		setListOpen(not listOpen)
	end)
	HudLayout.FlagChanged:Connect(function(name: string, on: boolean)
		if on and listOpen and (name == "Driving" or name == "Dead") then
			setListOpen(false)
		end
	end)
	HudLayout.LayoutChanged:Connect(function()
		if listOpen then
			placeList()
		end
	end)
end

---------------------------------------------------------------------------------------------------------------
-- F3 Empire Tax: list header + "Empire Tax +N%" toast (display only; the server owns the %)
---------------------------------------------------------------------------------------------------------------

local function readTaxPct(): number
	local v = player:GetAttribute(TAX.Attr)
	return if typeof(v) == "number" and v == v and v > 0 and v < math.huge then math.floor(v + 0.5) else 0
end

-- "Empire Tax +20%" (the list header and the toast)
function TerritoryController.TaxText(pct: number): string
	return string.format("%s +%d%%", TAX.Name, math.floor(pct + 0.5))
end

--[[ Pure (exported for the client sim): toast "Empire Tax +N%" for a change at changedAt? Not for 0, not while
	joining (joinedAt nil or within JoinQuietSeconds), and not when a server toast naming Empire Tax came at serverAt
	within SkipWindow before the change or after it (the decision runs Settle seconds after the change). ]]
function TerritoryController.ShouldToastTax(pct: number, changedAt: number, serverAt: number, joinedAt: number?): boolean
	if pct <= 0 or joinedAt == nil or changedAt - joinedAt < TAX.JoinQuietSeconds then
		return false
	end
	return serverAt < changedAt - TAX.SkipWindow
end

local function retitle()
	local t = listTitle
	if not t then
		return
	end
	local text = if taxPct > 0 then TerritoryController.TaxText(taxPct) else "TERRITORIES"
	if t.Text ~= text then
		t.Text = text
	end
	t.TextColor3 = if taxPct > 0 then TAX.Color else HudConfig.Colors.White
end

local function onTaxChanged()
	local pct = readTaxPct()
	if pct == taxPct then
		return
	end
	taxPct = pct
	retitle()
	taxToken += 1
	local my = taxToken
	local changedAt = os.clock()
	task.delay(TAX.Settle, function()
		-- a newer change decides for itself; the % must still be this one
		if my ~= taxToken or readTaxPct() ~= pct then
			return
		end
		if TerritoryController.ShouldToastTax(pct, changedAt, lastServerTaxToastAt, taxBaselineAt) then
			NotificationController.Show(TerritoryController.TaxText(pct), "Info")
		end
	end)
end

-- test hook (client sims): (current %, list header text)
function TerritoryController._TaxState(): (number, string)
	return taxPct, if listTitle then listTitle.Text else ""
end

---------------------------------------------------------------------------------------------------------------
-- capture bar
---------------------------------------------------------------------------------------------------------------

local function setCaptureVisible(visible: boolean)
	if captureActive == visible then
		return
	end
	captureActive = visible
	local p = capture
	if p then
		HudLayout.RefreshVisibility(p.Frame)
	end
end

local function applyCapture(localCap: any)
	local p = capture
	if not (localCap and localCap.Capturing and localCap.TerritoryId) then
		setCaptureVisible(false)
		contestedPulseActive = false
		contestedColA = nil
		contestedColB = nil
		return
	end
	local id = tostring(localCap.TerritoryId)
	local def = TerritoryConfig.Territories[id]
	local name = string.upper(if def then def.DisplayName else id)
	local frac = math.clamp(tonumber(localCap.Progress) or 0, 0, 1)
	local contested = localCap.Contested == true
	local protected = localCap.Protected == true
	if p then
		p.Value.Text = ProgressPill.Percent(frac)
		ProgressPill.SetFraction(p, frac)
		if contested then
			p.Title.Text = "CONTESTED · " .. name
			p.Title.TextColor3 = COL.Contested
			ProgressPill.AccentStroke(p, COL.Contested)
		elseif protected then
			p.Title.Text = "PROTECTED · " .. name
			p.Title.TextColor3 = COL.Protected
			ProgressPill.ResetStroke(p)
		else
			p.Title.Text = "CAPTURING " .. name
			p.Title.TextColor3 = ProgressPill.Colors.Title
			ProgressPill.ResetStroke(p)
		end
	end
	if contested then
		contestedPulseActive = true
		local ca = localCap.ContesterColorA
		local cb = localCap.ContesterColorB
		if typeof(ca) == "table" and typeof(cb) == "table" and #ca >= 3 and #cb >= 3 then
			contestedColA = Color3.new(ca[1], ca[2], ca[3])
			contestedColB = Color3.new(cb[1], cb[2], cb[3])
		else
			contestedColA = COL.Contested
			contestedColB = UIUtil.Lighten(COL.Contested, 0.5)
		end
		if p then
			local pulse = (math.sin(os.clock() * 5) + 1) * 0.5
			p.Fill.BackgroundColor3 = (contestedColA :: Color3):Lerp(contestedColB :: Color3, pulse)
		end
	else
		contestedPulseActive = false
		contestedColA = nil
		contestedColB = nil
		if p then
			p.Fill.BackgroundColor3 = if protected then COL.Protected else ProgressPill.Colors.Fill
		end
	end
	setCaptureVisible(true)
end

---------------------------------------------------------------------------------------------------------------

local function playerGui(): PlayerGui?
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg then
		return pg
	end
	local waited = player:WaitForChild("PlayerGui", 30)
	if waited and waited:IsA("PlayerGui") then
		return waited
	end
	return nil
end

function TerritoryController.Init()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireTerritory"
	-- Core safe insets + the one HUD UIScale; DisplayOrder from HudConfig (28)
	HudLayout.ApplyScreen(screen, { Insets = "Core" })
	local pg = playerGui()
	if pg then
		screen.Parent = pg
	else
		warn("[WAR EMPIRE] TerritoryController: no PlayerGui after 30 s; capture bar not shown")
	end
	_gui = screen

	local p = ProgressPill.Build(screen, "CaptureProgress")
	capture = p
	HudLayout.BindVisibility(p.Frame, { HideWhen = { "Dead" } }, function(): boolean
		return captureActive
	end)
	HudLayout.RegisterTopStack("Capture", p.Frame, HudConfig.TopStack.Order.Progress, { Space = "Hud" })

	buildList(screen)

	-- F3: the Empire Tax % (server attribute) heads the list and toasts on change
	taxPct = readTaxPct()
	retitle()
	player:GetAttributeChangedSignal(TAX.Attr):Connect(onTaxChanged)
	-- the server's capture / loss toasts name the % already ("Outpost taken  Empire Tax +10%"): remember when
	Remotes.BindEvent(Constants.RemoteNames.Notification, function(payload: any)
		if type(payload) == "table" and type(payload.Message) == "string" and string.find(payload.Message, TAX.Name, 1, true) then
			lastServerTaxToastAt = os.clock()
		end
	end)

	-- F10: the own plot, so the list shows only the own Home Outpost
	local function applyPlot(id: any)
		if typeof(id) ~= "number" or id ~= id or id == myPlotId then
			return
		end
		myPlotId = id
		listDirty = true
		if listOpen then
			rebuildList()
			placeList()
		end
	end
	Remotes.BindEvent(Constants.RemoteNames.BaseStateUpdate, function(base: any)
		if typeof(base) == "table" then
			applyPlot(base.PlotId)
		end
	end)
	Remotes.BindEvent(Constants.RemoteNames.PlayerStateUpdate, function(state: any)
		if typeof(state) == "table" and typeof(state.Base) == "table" then
			applyPlot(state.Base.PlotId)
		end
	end)

	local applyToken = 0
	Remotes.BindEvent(Constants.RemoteNames.TerritoryStateUpdate, function(payload: Types.TerritoryStatePayload)
		if typeof(payload) ~= "table" then
			return
		end
		applyToken += 1
		local my = applyToken
		task.delay(0.1, function()
			if my == applyToken then
				TerritoryController.Apply(payload)
			end
		end)
	end)

	local radarAccum = 0
	RunService.Heartbeat:Connect(function(dt)
		-- v38: continuous contested dual-color pulse on the capture bar
		local cp = capture
		if contestedPulseActive and cp and contestedColA and contestedColB then
			local pulse = (math.sin(os.clock() * 5) + 1) * 0.5
			cp.Fill.BackgroundColor3 = contestedColA:Lerp(contestedColB, pulse)
		end
		-- W3 step 2 lane U0: the contested diamond yields to the objective marker (4 Hz)
		diamondAccum += dt
		if diamondAccum >= DIAMOND.CheckSeconds then
			local elapsed = diamondAccum
			diamondAccum = 0
			syncDiamonds(elapsed)
		end
		if not radarActive then
			return
		end
		radarAccum += dt
		if radarAccum >= 0.2 then
			radarAccum = 0
			updateRadar()
		end
	end)

	Players.PlayerRemoving:Connect(function(leaving)
		local h = radarHighlights[leaving.UserId]
		if h then
			h:Destroy()
			radarHighlights[leaving.UserId] = nil
		end
	end)
end

function TerritoryController.Apply(payload: Types.TerritoryStatePayload)
	lastPayload = payload

	radarActive = payload.RadarReveal == true
	radarRadius = tonumber(payload.RadarRadius) or TerritoryConfig.RadarRevealRadius or 220
	HudLayout.SetFlag("Radar", radarActive)
	if not radarActive then
		clearRadarHighlights()
	end

	applyCapture(payload.LocalCapture)

	-- the list: rebuild now when it is open, otherwise on the next open
	listDirty = true
	if listOpen then
		rebuildList()
		placeList()
	end

	-- F3: the first payload ends "joining" for the Empire Tax toast (it replaced "Outposts held: N")
	if taxBaselineAt == nil then
		taxBaselineAt = os.clock()
	end
end

return TerritoryController
