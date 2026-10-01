--!strict
--[[
	claude-bud JOB 41 part C (2026-10-01): the TARGETS pill + list (RivalConfig). The server picks the targets
	(RivalService, FeaturePush "RivalTargets" { Rows = { PlotId, Name, Army, Verdict, Loot (a bucket), Dist } }); this
	only draws them.
	  * The pill: top-right under the top-bar pills (real px; clear of the left-rail thumbstick band, the fire / jump
	    controls and the top bar), "TARGETS" + a count badge, 48 px tall. Shown only while the server lists >= 1 target
	    (the server lists nothing during the Guided hold or without soldiers: the JOB 38 verdict says NoArmy).
	  * The list (one panel at a time: HudLayout.RegisterPanel): one row per target with the name, "Army 12",
	    "Loot $10k+" and the verdict chip; SEND ARMY = the same JOB 38 RequestArmySend remote the map uses (the server
	    re-checks everything; the army WALKS: ArmyPlan), VIEW = the world map on that base card (tap-to-pin, no travel).
	No exact loot number ever reaches this client.
	Code Bot v163 (Shaun 2026-10-01: "I can't figure out where we can see the rival players for raids"): the pill was
	hidden whenever the server listed 0 targets, which is nearly always for the owner (his server rarely has another
	player past new-player protection, with $10k+ in the ATM, beatable by his army). The pill now ALWAYS shows for
	everyone RivalConfig is live for; with no targets it is dimmed with no badge, and the list opens on an empty state
	(RivalConfig.EmptyText + the server's one-line reason, RivalTargets.Why). It steps aside (hidden) only while a
	full-screen panel is open (HudLayout "Modal", except its own list), while dead, and while the Recruit Pack card
	(WE_RecruitPack, the same top-right corner) is on screen.
	Code Bot v168 (Shaun 2026-10-01: the pill "isn't very clear and in depth": small dim yellow text on a dark pill):
	the pill is now a 64 px CARD (RivalConfig.Pill / RivalConfig.Layout, real px in the safe content rect, right under
	the topbar row that holds the compass / BASE pill): a crosshair icon, "TARGETS" + the count badge, then the
	server's suggested rival (rows[1]: most loot, then nearest) as its name and "500m · $100k+"; with nothing to raid
	"No target now" + the short reason (RivalConfig.ShortWhy). Full opacity, white / bright gold text >= 14 px.
	The list rows are bigger too: the name + "Lv 23", "Army 12" + the verdict chip, "$100k+ loot · 500m", SEND
	ARMY (the same JOB 38 remote) and VIEW (the map; tap-to-pin, no travel). Visibility rules unchanged (v163).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
if not Shared then
	warn("[WAR EMPIRE] RivalController: no ReplicatedStorage.Shared after 60 s; not started")
	return {}
end
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local RivalConfig = require(Shared.Configs.RivalConfig)

local HudLayout = require(script.Parent.Parent.Modules.HudLayout)

local RivalController = {}

local player = Players.LocalPlayer
local GOLD = Color3.fromRGB(255, 214, 72)
local WHITE = Color3.fromRGB(255, 255, 255)
local PLATE = Color3.fromRGB(16, 18, 14)
local ROW = Color3.fromRGB(36, 40, 32)
local HOT = Color3.fromRGB(255, 72, 56) -- the crosshair / stroke while a target is listed
local LOOT = Color3.fromRGB(150, 235, 120)
local MUTED = Color3.fromRGB(225, 225, 215)
local AMBER = Color3.fromRGB(255, 176, 80)
local CHIP = { easy = Color3.fromRGB(60, 150, 70), even = Color3.fromRGB(150, 125, 45), risky = Color3.fromRGB(175, 60, 50) }
local PANEL_ID = "RivalTargets"

local gui: ScreenGui? = nil
local pill: TextButton? = nil
local badge: TextLabel? = nil
local pillStroke: UIStroke? = nil
local crossParts: { GuiObject } = {}
local crossRing: UIStroke? = nil
local crossBox: Frame? = nil
local lineTitle: TextLabel? = nil
local lineName: TextLabel? = nil
local lineDetail: TextLabel? = nil
local panel: Frame? = nil
local rows: { any } = {}
local why: string? = nil -- v163: the server's one-line reason when the list is empty
local open = false
local emptyLabel: TextLabel? = nil

local updatePillLater: () -> () = function() end -- v163: set once updatePill exists (setOpen is defined first)

local function corner(p: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = p
end

local function label(parent: Instance, name: string, x: number, y: number, w: number, h: number, px: number, font: Enum.Font, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(x, y)
	l.Size = UDim2.fromOffset(w, h)
	l.Font = font
	l.TextSize = px
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Active = false
	l.Text = ""
	l.Parent = parent
	local st = Instance.new("UIStroke") -- a thin dark outline: readable over bright sand / sky
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	st.Color = Color3.new(0, 0, 0)
	st.Transparency = 0.45
	st.Thickness = 1
	st.Parent = l
	return l
end

local function setOpen(on: boolean)
	open = on
	local p = panel
	if p then
		p.Visible = on
	end
	if on then
		HudLayout.PanelOpened(PANEL_ID)
	else
		HudLayout.PanelClosed(PANEL_ID)
	end
	updatePillLater()
end

local function button(parent: Instance, text: string, color: Color3, x: number, y: number, w: number, h: number): TextButton
	local b = Instance.new("TextButton")
	b.Position = UDim2.fromOffset(x, y)
	b.Size = UDim2.fromOffset(w, h)
	b.BackgroundColor3 = color
	b.TextColor3 = WHITE
	b.Font = Enum.Font.GothamBlack
	b.TextSize = 15
	b.Text = text
	corner(b, 8)
	b.Parent = parent
	return b
end

-- the crosshair icon (Frames only): a ring, four ticks, a centre dot
local function crosshair(parent: Instance, x: number, y: number, size: number)
	local box = Instance.new("Frame")
	box.Name = "Crosshair"
	box.BackgroundTransparency = 1
	box.Position = UDim2.fromOffset(x, y)
	box.Size = UDim2.fromOffset(size, size)
	box.Active = false
	box.Parent = parent
	crossBox = box
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(0.72, 0.72)
	ring.BackgroundTransparency = 1
	ring.Parent = box
	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(0.5, 0)
	rc.Parent = ring
	local rs = Instance.new("UIStroke")
	rs.Thickness = 2.5
	rs.Color = GOLD
	rs.Parent = ring
	crossRing = rs
	table.clear(crossParts)
	local t = 2
	for _, spec in ipairs({
		{ 0.5, 0, UDim2.new(0, t, 0.32, 0), Vector2.new(0.5, 0) },
		{ 0.5, 1, UDim2.new(0, t, 0.32, 0), Vector2.new(0.5, 1) },
		{ 0, 0.5, UDim2.new(0.32, 0, 0, t), Vector2.new(0, 0.5) },
		{ 1, 0.5, UDim2.new(0.32, 0, 0, t), Vector2.new(1, 0.5) },
	}) do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.AnchorPoint = spec[5]
		f.Position = UDim2.fromScale(spec[1], spec[2])
		f.Size = spec[3]
		f.BackgroundColor3 = GOLD
		f.Parent = box
		table.insert(crossParts, f)
	end
	local dot = Instance.new("Frame")
	dot.BorderSizePixel = 0
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(4, 4)
	dot.BackgroundColor3 = GOLD
	dot.Parent = box
	corner(dot, 4)
	table.insert(crossParts, dot)
end

local function contentSize(): Vector2
	local g = gui
	local v = if g then g.AbsoluteSize else Vector2.zero
	if v.X < 2 or v.Y < 2 then
		local cam = workspace.CurrentCamera
		v = if cam then Vector2.new(cam.ViewportSize.X, cam.ViewportSize.Y - 58) else Vector2.new(1024, 413)
	end
	return v
end

-- the card and the list at RivalConfig.Layout's numbers (re-run when the screen size or the row count changes)
local function layout()
	local pl, p = pill, panel
	if pl == nil or p == nil then
		return
	end
	local cs = contentSize()
	local L = RivalConfig.Layout(cs.X, cs.Y, #rows)
	local C = L.Pill
	pl.Position = UDim2.fromOffset(C.X, C.Y)
	pl.Size = UDim2.fromOffset(C.W, C.H)
	local ic = crossBox
	if ic then
		ic.Position = UDim2.fromOffset(C.IconX, C.IconY)
		ic.Size = UDim2.fromOffset(C.Icon, C.Icon)
	end
	local t, n, d = lineTitle, lineName, lineDetail
	if t and n and d then
		t.Position = UDim2.fromOffset(C.TitleX, 5)
		t.Size = UDim2.fromOffset(C.TitleW, 18)
		n.Position = UDim2.fromOffset(C.TextX, 24)
		n.Size = UDim2.fromOffset(C.TextW, 17)
		d.Position = UDim2.fromOffset(C.TextX, 42)
		d.Size = UDim2.fromOffset(C.TextW, 16)
	end
	p.Position = UDim2.fromOffset(L.List.X, L.List.Y)
	p.Size = UDim2.fromOffset(L.List.W, L.List.H)
end

local function rebuildList()
	local p = panel
	if p == nil then
		return
	end
	for _, c in ipairs(p:GetChildren()) do
		if c:IsA("Frame") and c.Name == "Row" then
			c:Destroy()
		end
	end
	local L = RivalConfig.List
	local cs = contentSize()
	local lw = RivalConfig.Layout(cs.X, cs.Y, #rows).List.W
	local rowW = lw - 16
	local textW = rowW - 10 - L.SendWidth - L.ViewWidth - 3 * 8
	for i, r in ipairs(rows) do
		local t = RivalConfig.RowLines(r)
		local row = Instance.new("Frame")
		row.Name = "Row"
		row.Position = UDim2.fromOffset(8, L.Header + (i - 1) * (L.RowHeight + L.RowGap))
		row.Size = UDim2.fromOffset(rowW, L.RowHeight)
		row.BackgroundColor3 = ROW
		row.Parent = p
		corner(row, 8)
		label(row, "Name", 10, 3, textW - 52, 20, 16, Enum.Font.GothamBold, WHITE).Text = t.Name
		local lv = label(row, "Level", 10 + textW - 50, 3, 50, 20, 14, Enum.Font.GothamBold, GOLD)
		lv.TextXAlignment = Enum.TextXAlignment.Right
		lv.Text = t.Level
		label(row, "Army", 10, 23, textW - 64, 18, 14, Enum.Font.GothamBold, MUTED).Text = t.Army
		local chip = Instance.new("TextLabel")
		chip.Name = "Verdict"
		chip.Position = UDim2.fromOffset(10 + textW - 60, 23)
		chip.Size = UDim2.fromOffset(60, 18)
		chip.BackgroundColor3 = CHIP[tostring(r.Verdict)] or CHIP.even
		chip.TextColor3 = WHITE
		chip.Font = Enum.Font.GothamBold
		chip.TextSize = 14
		chip.Text = t.Chip
		chip.Parent = row
		corner(chip, 6)
		label(row, "LootDist", 10, 42, textW, 18, 14, Enum.Font.GothamBold, LOOT).Text = t.Loot .. " · " .. t.Dist
		local plotId = tonumber(r.PlotId) or 0
		local by = math.floor((L.RowHeight - L.ButtonHeight) / 2)
		local send = button(row, "SEND ARMY", Color3.fromRGB(170, 55, 45), rowW - 8 - L.ViewWidth - 8 - L.SendWidth, by, L.SendWidth, L.ButtonHeight)
		send.Activated:Connect(function()
			-- the SAME JOB 38 send path as the map's SEND ARMY (the server re-checks every fairness rule)
			task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestArmySend, plotId)
			task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestRivalAction, "send", plotId)
			setOpen(false)
		end)
		local view = button(row, "VIEW", Color3.fromRGB(60, 66, 54), rowW - 8 - L.ViewWidth, by, L.ViewWidth, L.ButtonHeight)
		view.Activated:Connect(function()
			setOpen(false)
			local okM, MC = pcall(function(): any
				return require(script.Parent.MapController)
			end)
			if okM and MC and MC.OpenBase then
				MC.OpenBase(plotId) -- the map on that base card: tap-to-pin only, nothing moves the player
			end
		end)
	end
	local e = emptyLabel
	if e then
		e.Visible = #rows == 0
		e.Text = if why and why ~= "" then RivalConfig.EmptyText .. "\n" .. why else RivalConfig.EmptyText
	end
	layout()
end

-- v163: the pill is always there for a live player; it only steps aside for a full-screen panel (not its own list),
-- death, and the Recruit Pack card that slides into the same corner
local function recruitCardUp(): boolean
	local pg = player:FindFirstChildOfClass("PlayerGui")
	return pg ~= nil and pg:FindFirstChild("WE_RecruitPack") ~= nil
end

local function updatePill()
	local pl = pill
	if pl == nil then
		return
	end
	local modalOther = HudLayout.GetFlag("Modal") and not open
	pl.Visible = not modalOther and not HudLayout.GetFlag("Dead") and not recruitCardUp()
end

updatePillLater = function()
	updatePill()
end

local function refresh()
	local pl, b = pill, badge
	if pl == nil or b == nil then
		return
	end
	local lines = RivalConfig.PillLines(rows, why)
	b.Text = tostring(lines.Count)
	b.Visible = lines.Has
	local t, n, d = lineTitle, lineName, lineDetail
	if t and n and d then
		t.Text = lines.Title
		n.Text = lines.Name
		n.TextColor3 = if lines.Has then WHITE else MUTED
		d.Text = lines.Detail
		d.TextColor3 = if lines.Has then LOOT else AMBER
	end
	local accent = if lines.Has then HOT else GOLD
	local st = pillStroke
	if st then
		st.Color = accent
	end
	local ring = crossRing
	if ring then
		ring.Color = accent
	end
	for _, f in ipairs(crossParts) do
		f.BackgroundColor3 = accent
	end
	updatePill()
	rebuildList()
end

local function build()
	local pg = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
	if pg == nil then
		return
	end
	local g = Instance.new("ScreenGui")
	g.Name = "WE_RivalTargets"
	g.ResetOnSpawn = false
	g.DisplayOrder = 30
	-- v168: explicit: the safe content rect (below the 58 px topbar row with the compass / BASE pill, inside notches)
	g.IgnoreGuiInset = false
	pcall(function()
		g.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)
	g.Parent = pg
	gui = g
	local P = RivalConfig.Pill
	local b = Instance.new("TextButton")
	b.Name = "TargetsPill"
	b.BackgroundColor3 = PLATE
	b.BackgroundTransparency = 0.05
	b.AutoButtonColor = true
	b.Text = ""
	b.Visible = true -- v163: always there for a live player
	b.Parent = g
	corner(b, 12)
	local st = Instance.new("UIStroke")
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Color = GOLD
	st.Thickness = 2
	st.Parent = b
	pillStroke = st
	crosshair(b, 8, math.floor((P.Height - P.Icon) / 2), P.Icon) -- layout() places / sizes it (RivalConfig.Layout)
	lineTitle = label(b, "Title", 46, 5, 100, 18, 16, Enum.Font.GothamBlack, GOLD)
	lineName = label(b, "Rival", 46, 24, 100, 17, 15, Enum.Font.GothamBold, WHITE)
	lineDetail = label(b, "Detail", 46, 42, 100, 16, 14, Enum.Font.GothamBold, LOOT)
	local bd = Instance.new("TextLabel")
	bd.Name = "Count"
	bd.AnchorPoint = Vector2.new(1, 0)
	bd.Position = UDim2.new(1, -6, 0, 4)
	bd.Size = UDim2.fromOffset(24, 20)
	bd.BackgroundColor3 = Color3.fromRGB(225, 40, 50)
	bd.TextColor3 = WHITE
	bd.Font = Enum.Font.GothamBlack
	bd.TextSize = 14
	bd.Text = "0"
	bd.Visible = false
	bd.Parent = b
	corner(bd, 10)
	pill = b
	badge = bd
	local f = Instance.new("Frame")
	f.Name = "TargetsList"
	f.BackgroundColor3 = PLATE
	f.BackgroundTransparency = 0.03
	f.Visible = false
	f.ZIndex = 3 -- on a short screen the list slides up over the card (RivalConfig.Layout); X closes it
	f.Parent = g
	corner(f, 12)
	local fs = Instance.new("UIStroke")
	fs.Color = GOLD
	fs.Thickness = 1.5
	fs.Parent = f
	local title = label(f, "Title", 12, 4, 280, 28, 18, Enum.Font.GothamBlack, GOLD)
	title.Text = "RIVAL TARGETS"
	-- v163: the empty state (shown while the server lists 0 targets)
	local empty = Instance.new("TextLabel")
	empty.Name = "Empty"
	empty.BackgroundTransparency = 1
	empty.Position = UDim2.fromOffset(12, RivalConfig.List.Header)
	empty.Size = UDim2.new(1, -24, 0, RivalConfig.EmptyHeight - 8)
	empty.Font = Enum.Font.GothamMedium
	empty.TextSize = 15
	empty.TextWrapped = true
	empty.TextXAlignment = Enum.TextXAlignment.Left
	empty.TextYAlignment = Enum.TextYAlignment.Top
	empty.TextColor3 = MUTED
	empty.Text = RivalConfig.EmptyText
	empty.Parent = f
	emptyLabel = empty
	local x = Instance.new("TextButton")
	x.Name = "Close"
	x.AnchorPoint = Vector2.new(1, 0)
	x.Position = UDim2.new(1, -2, 0, -2)
	x.Size = UDim2.fromOffset(48, 48)
	x.BackgroundTransparency = 1
	x.TextColor3 = WHITE
	x.Font = Enum.Font.GothamBold
	x.TextSize = 20
	x.Text = "X"
	x.Parent = f
	panel = f
	x.Activated:Connect(function()
		setOpen(false)
	end)
	b.Activated:Connect(function()
		if open then
			setOpen(false)
		else
			setOpen(true)
			task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestRivalAction, "open", nil)
		end
	end)
	HudLayout.RegisterPanel(PANEL_ID, function()
		return open
	end, function()
		setOpen(false)
	end)
	-- v163: visibility follows the HUD flags and the Recruit Pack card
	HudLayout.FlagChanged:Connect(function(name: string)
		if name == "Modal" or name == "Dead" then
			updatePill()
		end
	end)
	pg.ChildAdded:Connect(function(c: Instance)
		if c.Name == "WE_RecruitPack" then
			updatePill()
		end
	end)
	pg.ChildRemoved:Connect(function(c: Instance)
		if c.Name == "WE_RecruitPack" then
			updatePill()
		end
	end)
	g:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() -- v168: rotate / resize: the card keeps its slot
		rebuildList()
	end)
	refresh()
end

function RivalController.Init()
	if RivalConfig.Enabled ~= true or not RivalConfig.LiveFor(player.UserId) then
		return -- OFF / not live: no pill, nothing pushed
	end
	task.spawn(build)
	Remotes.BindEvent(Constants.RemoteNames.FeaturePush, function(kind: any, data: any)
		if kind ~= "RivalTargets" or typeof(data) ~= "table" or typeof(data.Rows) ~= "table" then
			return
		end
		rows = data.Rows
		why = if typeof(data.Why) == "string" then string.sub(data.Why, 1, 120) else nil
		refresh()
	end)
end

return RivalController
