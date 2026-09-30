--!strict
--[[
	claude-bud JOB 30 (2026-09-30): the full-screen WORLD MAP (MapConfig, Shared/Util/MapAreas, server MapService).
	Code Bot MAP-REDESIGN (v129, owner: "labels overlap, it is not beautiful"): the phone-first redesign. Claude: this
	look is the owner's request; do not revert it to the v127 right-hand canvas / ALL CAPS labels.

	OPENS from the MAP rail tile, or M when the player prefers keys (Missions moved to N). It is a registered Modal
	panel ("Map"): one panel at a time.

	LAYOUT (phone landscape first; fitLayout, in v):
	  * the map: a square as tall as the panel, left of centre; the slim info card on its right (title, the selected
	    place, GO / CLEAR PIN each TouchMinV tall, the icon legend, the zoom hint). North (-Z) is up.
	  * over the map: the zoom button (top-left, + / -), the close X (top-right), the compass rose (bottom-left), a
	    gold frame with corner brackets and a dark vignette. Every tappable is >= 44 real px.

	DRAWS (world -> content by scale; the content frame is the map at Zoom x the viewport, panned by offset):
	  * cached once (buildStatic): sea gradient, the sand land gradient, a 500-stud grid, the roads (WaterConfig
	    RoadEnds centre lines) and the named zones as subtle patches;
	  * icons + labels (layoutLabels, Shared/Util/MapLabelLayout): one icon per area, JOB 31 site, base and the bank
	    (UICorner + UIStroke circles with an inner shape, colour by family, fixed sizes; an outpost adds a small owner
	    badge); title-case pills placed by the collision pass (8+ slots round the icon, clamped inside the view,
	    lower priority dropped when they still collide). Zoom 2 shows more; a tapped place shows its label on top.
	    It re-runs only on open, resize, zoom, pan end and when the live site / base set changes.
	  * live, from RequestMapLive every RefreshSeconds while open: outpost badges (yours green, enemy red, neutral
	    gold), supply crates / the airdrop, job spots, the player's own arrow and the pin (pooled frames).

	ZOOM: 2 levels (MapConfig.ZoomLevels): the + / - button, a pinch, or the mouse wheel. At zoom 2 a drag pans.

	TAPS on the map (a tap = press and release within 12 px):
	  * on the pin: removes it;
	  * on a label or an icon (IconTapPx): its card, with GO (pins it);
	  * inside a zone: its card; GO pins the tapped point. Code Bot v127: NO fast travel (removed at the owner's
	    request; do not re-add it);
	  * open ground: a PIN at once.

	THE PIN is the ONE objective marker: ObjectiveMarker.ShowWith({ Short = "PIN", ... }, { Pin = true, ArriveStuds =
	15 }). It uses the same GO line and compass as missions and airdrops, beats their targets while it is set, and ends
	ConsoleWaypoint's line. It clears on arrival, by tapping it, or with CLEAR PIN.

	COST: nothing runs while the map is closed. While it is open: one loop at RefreshSeconds (one server call, pooled
	marker frames moved by scale), plus the label pass on the events above (~40 items; no workspace scans).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
if not Shared then
	warn("[WAR EMPIRE] MapController: no ReplicatedStorage.Shared after 60 s; not started")
	return {}
end
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local MapConfig = require(Shared.Configs.MapConfig)
local HudConfig = require(Shared.Configs.HudConfig)
local RetentionConfig = require(Shared.Configs.RetentionConfig)
local BaseConfig = require(Shared.Configs.BaseConfig)
local BankRaidConfig = require(Shared.Configs.BankRaidConfig)
local WaterConfig = require(Shared.Configs.WaterConfig)
local WorldSitesConfig = require(Shared.Configs.WorldSitesConfig)
local MapAreas = require(Shared.Util.MapAreas)
local MapLabelLayout = require(Shared.Util.MapLabelLayout)
local SiteActivityConfig = require(Shared.Configs.SiteActivityConfig) -- claude-bud JOB 31

local PanelShell = require(script.Parent.Parent.Modules.PanelShell)
local ObjectiveMarker = require(script.Parent.Parent.Modules.ObjectiveMarker)
local AudioController = require(script.Parent.Parent.Modules.AudioController)

local MapController = {}

local PANEL_ID = "Map"
local C = MapConfig.Colors
local E = MapConfig.Extent
local I = MapConfig.Icon
local GAP = 14 -- map to card (v)
local STROKE = Color3.fromRGB(10, 12, 10)
local WHITE = Color3.new(1, 1, 1)

local player = Players.LocalPlayer
local open = false
local shell: PanelShell.Shell? = nil
local panel: Frame? = nil
local uiScale: UIScale? = nil
local canvas: TextButton? = nil -- the viewport (clips; the tap surface)
local content: Frame? = nil -- the zoomed map inside it
local cardFrame: Frame? = nil
local zoomBtn: TextButton? = nil
local zoomFace: TextLabel? = nil
local closeBtn: GuiObject? = nil
local staticBuilt = false
local iconLayer: Frame? = nil
local liveLayer: Frame? = nil
local labelLayer: Frame? = nil
local pool: { [string]: GuiObject } = {}
local iconPool: { [string]: Frame } = {}
local iconGroup: { [string]: string } = {}
local badges: { [string]: Frame } = {}
local labelPool: { [string]: Frame } = {}
local focusPill: Frame? = nil
local lastLive: any = nil
local inFlight = false
local loopToken = 0

-- view state (v): the viewport side, the zoom level index, the pan offset (<= 0)
local side = 0
local zoomIdx = 1
local panX, panY = 0, 0
local lastLayout: any = nil
local lastControls: { any } = {}
local lastView: any = nil
local liveSig = ""
local selectedItem: string? = nil

-- the card
local cardTitle: TextLabel? = nil
local cardBody: TextLabel? = nil
local goBtn: TextButton? = nil
local clearBtn: TextButton? = nil
local selected: { Kind: string, Id: string, X: number, Z: number }? = nil

local function isLive(): boolean
	return RetentionConfig.Live(MapConfig, player.UserId)
end

-- world (x, z) -> content scale (u, v); and back
local function toUV(x: number, z: number): (number, number)
	return (x - E.X0) / (E.X1 - E.X0), (z - E.Z0) / (E.Z1 - E.Z0)
end
local function toWorld(u: number, v: number): (number, number)
	return E.X0 + u * (E.X1 - E.X0), E.Z0 + v * (E.Z1 - E.Z0)
end

local function vScale(): number
	local s = uiScale
	return if s and s.Scale > 0 then s.Scale else 1
end

local function zoom(): number
	return MapConfig.ZoomLevels[zoomIdx] or 1
end

local function corner(p: Instance, r: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = r
	c.Parent = p
end

local function stroke(p: Instance, color: Color3, thick: number, transp: number?): UIStroke
	local st = Instance.new("UIStroke")
	st.Color = color
	st.Thickness = thick
	st.Transparency = transp or 0
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = p
	return st
end

local function box(parent: Instance, name: string, color: Color3, transp: number, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transp
	f.ZIndex = z
	f.Parent = parent
	return f
end

local function text(parent: Instance, s: string, size: number, color: Color3, font: Enum.Font?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = font or Enum.Font.GothamBold
	l.TextSize = PanelShell.Text(size)
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.5
	l.Text = s
	l.Parent = parent
	return l
end

local function button(parent: Instance, name: string, label: string, w: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = UDim2.fromOffset(w, PanelShell.TouchMinV())
	b.BackgroundColor3 = if name == "Go" then Color3.fromRGB(70, 96, 44) else Color3.fromRGB(58, 62, 44)
	b.TextColor3 = C.Text
	b.Font = Enum.Font.GothamBlack
	b.TextSize = PanelShell.Text(20)
	b.Text = label
	b.AutoButtonColor = true
	b.Visible = false
	corner(b, UDim.new(0, 8))
	stroke(b, C.Accent, 1.5)
	b.Parent = parent
	return b
end

-- ── icons: a circle (or a rounded square for bases) in the family colour, with a small white inner shape ─────────
local GROUP_COLOR: { [string]: Color3 } = {
	Town = C.Town, Military = C.Military, Industry = C.Industry, Wilds = C.Wilds, Site = C.Site,
	Base = C.Base, BaseMine = C.BaseMine, Bank = C.Bank, Job = C.Job, Drop = C.Drop,
}

local function inner(parent: Frame, shape: string)
	-- no Rotation anywhere inside the clipped map: a rotated frame could draw outside the viewport at zoom 2
	if shape == "square" or shape == "dot" then
		local q = box(parent, "Glyph", WHITE, 0, parent.ZIndex + 1)
		q.AnchorPoint = Vector2.new(0.5, 0.5)
		q.Position = UDim2.fromScale(0.5, 0.5)
		local k = if shape == "dot" then 0.38 else 0.4
		q.Size = UDim2.fromScale(k, k)
		if shape == "dot" then
			corner(q, UDim.new(0.5, 0))
		end
	elseif shape == "bars" then -- military: two rank bars
		for i = 1, 2 do
			local q = box(parent, "Glyph" .. i, WHITE, 0, parent.ZIndex + 1)
			q.AnchorPoint = Vector2.new(0.5, 0.5)
			q.Position = UDim2.fromScale(0.5, if i == 1 then 0.38 else 0.62)
			q.Size = UDim2.fromScale(0.5, 0.14)
		end
	elseif shape == "ring" then
		local q = box(parent, "Glyph", WHITE, 1, parent.ZIndex + 1)
		q.AnchorPoint = Vector2.new(0.5, 0.5)
		q.Position = UDim2.fromScale(0.5, 0.5)
		q.Size = UDim2.fromScale(0.46, 0.46)
		corner(q, UDim.new(0.5, 0))
		stroke(q, WHITE, 2)
	elseif shape == "cross" then
		for i = 1, 2 do
			local q = box(parent, "Glyph" .. i, WHITE, 0, parent.ZIndex + 1)
			q.AnchorPoint = Vector2.new(0.5, 0.5)
			q.Position = UDim2.fromScale(0.5, 0.5)
			q.Size = if i == 1 then UDim2.fromScale(0.56, 0.16) else UDim2.fromScale(0.16, 0.56)
		end
	elseif shape == "$" then
		local t = text(parent, "$", 14, Color3.fromRGB(40, 30, 0), Enum.Font.GothamBlack)
		t.TextStrokeTransparency = 1
		t.TextScaled = true
		t.Size = UDim2.fromScale(0.8, 0.8)
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Position = UDim2.fromScale(0.5, 0.5)
		t.ZIndex = parent.ZIndex + 1
	end
end

local GROUP_SHAPE: { [string]: string } = { Town = "square", Military = "bars", Industry = "dot", Wilds = "ring", Site = "cross", BaseMine = "square", Bank = "$" }

local function makeIcon(parent: Instance, group: string, s: number, z: number): Frame
	local f = box(parent, "Icon", GROUP_COLOR[group] or C.Area, 0, z)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(s, s)
	corner(f, if group == "Base" or group == "BaseMine" then UDim.new(0, 4) else UDim.new(0.5, 0))
	stroke(f, STROKE, 1.5, 0.1)
	local shape = GROUP_SHAPE[group]
	if shape then
		inner(f, shape)
	end
	return f
end

-- ── the cached terrain ─────────────────────────────────────────────────────────────────────────────────────────────
local function gradient(p: Instance, a: Color3, b: Color3, rot: number)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(a, b)
	g.Rotation = rot
	g.Parent = p
end

local function buildStatic(cv: GuiObject)
	if staticBuilt then
		return
	end
	staticBuilt = true
	;(cv :: any).BackgroundColor3 = WHITE -- the gradient carries the sea colour
	gradient(cv, C.SeaLight, C.SeaDark, 90)
	-- dry land (x +-1760, z -1760..1490; south of it is the bay): a sand gradient with a pale shore line
	local u0, v0 = toUV(-1760, -1760)
	local u1, v1 = toUV(1760, 1490)
	local land = box(cv, "Land", WHITE, 0, 2)
	land.Position = UDim2.fromScale(u0, v0)
	land.Size = UDim2.fromScale(u1 - u0, v1 - v0)
	corner(land, UDim.new(0.025, 0))
	gradient(land, C.SandLight, C.SandDark, 90)
	stroke(land, Color3.fromRGB(236, 220, 176), 1.5, 0.2)
	-- a 500-stud grid
	for k = -1500, 1500, 500 do
		local gu = toUV(k, 0)
		local _, gv = toUV(0, k)
		local a = box(cv, "GridX", C.Grid, 0.84, 3)
		a.Position = UDim2.fromScale(gu, 0)
		a.Size = UDim2.new(0, 1, 1, 0)
		local b = box(cv, "GridZ", C.Grid, 0.84, 3)
		b.Position = UDim2.fromScale(0, gv)
		b.Size = UDim2.new(1, 0, 0, 1)
	end
	-- the named zones: subtle patches (the icon carries the colour)
	for _, a in ipairs(MapAreas.List()) do
		local f = box(cv, "Area_" .. a.Id, C.Zone, if a.Kind == "town" then 0.72 else 0.82, 3)
		stroke(f, C.Zone, 1, 0.55)
		local r = a.Rect
		if r then
			local ra, rb = toUV(r.X0, r.Z0)
			local rc, rd = toUV(r.X1, r.Z1)
			f.Position = UDim2.fromScale(ra, rb)
			f.Size = UDim2.fromScale(rc - ra, rd - rb)
			corner(f, UDim.new(0.12, 0))
		else
			local cu, cv2 = toUV(a.X, a.Z)
			local su = a.R * 2 / (E.X1 - E.X0)
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Position = UDim2.fromScale(cu, cv2)
			f.Size = UDim2.fromScale(su, su * (E.X1 - E.X0) / (E.Z1 - E.Z0))
			corner(f, UDim.new(0.5, 0))
		end
	end
	-- the roads between the towns (WaterConfig.RoadEnds: RoadX<x> runs along Z at x, RoadZ<z> along X at z)
	local W = 0.0055
	for name, r in pairs(WaterConfig.RoadEnds) do
		local axis, at = string.match(name, "^Road([XZ])(%-?%d+)$")
		local c = tonumber(at)
		if axis and c then
			local road = box(cv, name, C.Road, 0.1, 4)
			local mid = box(road, "Centre", Color3.fromRGB(150, 124, 88), 0.2, 5)
			mid.AnchorPoint = Vector2.new(0.5, 0.5)
			mid.Position = UDim2.fromScale(0.5, 0.5)
			if axis == "X" then
				local u = toUV(c, 0)
				local _, a0 = toUV(0, r.Min)
				local _, a1 = toUV(0, r.Max)
				road.AnchorPoint = Vector2.new(0.5, 0)
				road.Position = UDim2.fromScale(u, a0)
				road.Size = UDim2.fromScale(W, a1 - a0)
				mid.Size = UDim2.fromScale(0.25, 1)
			else
				local _, v = toUV(0, c)
				local a0 = toUV(r.Min, 0)
				local a1 = toUV(r.Max, 0)
				road.AnchorPoint = Vector2.new(0, 0.5)
				road.Position = UDim2.fromScale(a0, v)
				road.Size = UDim2.fromScale(a1 - a0, W)
				mid.Size = UDim2.fromScale(1, 0.25)
			end
		end
	end
end

-- ── the label pass ──────────────────────────────────────────────────────────────────────────────────────────────────
local measured: { [string]: number } = {}
local function measure(s: string): number
	local tv = PanelShell.Text(MapConfig.LabelTextV)
	local key = s .. "|" .. tv
	local m = measured[key]
	if m then
		return m
	end
	local ok, v = pcall(function(): Vector2
		return TextService:GetTextSize(s, tv, Enum.Font.GothamBold, Vector2.new(2000, 200))
	end)
	m = if ok then math.ceil(v.X) + 2 else MapLabelLayout.EstimateWidth(s, tv)
	measured[key] = m
	return m
end

local function sitesNow(): { any }
	local live = lastLive
	if typeof(live) == "table" and typeof(live.Sites) == "table" and #live.Sites > 0 then
		return live.Sites
	end
	-- before the first server answer: the configured points (the placed ones differ by <= SearchStuds)
	local out = {}
	for _, s in ipairs(WorldSitesConfig.Sites) do
		local k = WorldSitesConfig.Kinds[s.Kind]
		table.insert(out, { Id = s.Id, N = s.Name, K = s.Kind, X = s.X, Z = s.Z, R = if k then k.R else 40 })
	end
	return out
end

local function basesNow(): { any }
	local live = lastLive
	if typeof(live) == "table" and typeof(live.Bases) == "table" and #live.Bases > 0 then
		return live.Bases
	end
	local out = {}
	for p, v in ipairs(BaseConfig.PlotPositions) do
		table.insert(out, { P = p, X = v.X, Z = v.Z, Mine = false })
	end
	return out
end

local function bankNow(): any
	local live = lastLive
	if typeof(live) == "table" and typeof(live.Bank) == "table" then
		return live.Bank
	end
	return { X = BankRaidConfig.Position.X, Z = BankRaidConfig.Position.Z }
end

local function syncIcons(icons: { any }, size: number)
	local layer = iconLayer
	if layer == nil then
		return
	end
	local seenI: { [string]: boolean } = {}
	for _, ic in ipairs(icons) do
		seenI[ic.Id] = true
		local f = iconPool[ic.Id]
		if f and iconGroup[ic.Id] ~= ic.Group then
			f:Destroy()
			f = nil
		end
		if not f then
			local nf = makeIcon(layer, ic.Group, ic.S, 6)
			nf.Name = ic.Id
			if ic.Territory then
				local b = box(nf, "Badge", C.Outpost, 0, 8) -- the outpost owner flag (not rotated: see inner())
				b.AnchorPoint = Vector2.new(0.5, 0.5)
				b.Position = UDim2.fromScale(0.92, 0.08)
				b.Size = UDim2.fromOffset(I.Badge, I.Badge)
				corner(b, UDim.new(0, 2))
				stroke(b, STROKE, 1.5)
				badges[ic.Territory] = b
			end
			iconPool[ic.Id] = nf
			iconGroup[ic.Id] = ic.Group
			f = nf
		end
		local ff = f :: Frame
		ff.Size = UDim2.fromOffset(ic.S, ic.S)
		ff.Position = UDim2.fromScale(ic.X / size, ic.Y / size)
		ff.Visible = true
	end
	for id, f in pairs(iconPool) do
		if not seenI[id] then
			f.Visible = false
		end
	end
end

local function pill(parent: Instance, name: string, z: number): Frame
	local f = box(parent, name, C.Pill, 0.32, z)
	corner(f, UDim.new(0.5, 0))
	stroke(f, WHITE, 1, 0.82)
	local t = text(f, "", MapConfig.LabelTextV, C.Text, Enum.Font.GothamBold)
	t.Name = "Text"
	t.Size = UDim2.fromScale(1, 1)
	t.TextStrokeTransparency = 0.35
	t.ZIndex = z + 1
	return f
end

local function setPill(f: Frame, s: string, pr: number)
	local t = f:FindFirstChild("Text") :: TextLabel?
	if t then
		t.Text = s
		t.Font = if pr <= 1 then Enum.Font.GothamBold else Enum.Font.GothamMedium
		t.TextColor3 = if pr == 0 then C.Accent else C.Text
	end
end

local function showFocus()
	local fp = focusPill
	for id, f in pairs(labelPool) do
		local st = f:FindFirstChildOfClass("UIStroke")
		if st then
			local on = id == selectedItem
			st.Color = if on then C.Accent else WHITE
			st.Transparency = if on then 0 else 0.82
		end
	end
	if fp == nil then
		return
	end
	local id = selectedItem
	local out = lastLayout
	local shownAlready = id ~= nil and labelPool[id] ~= nil and labelPool[id].Visible
	if id == nil or out == nil or shownAlready or lastView == nil then
		fp.Visible = false
		return
	end
	local it = out.Items[id]
	local v = lastView
	if it == nil or it.X < v.X0 or it.X > v.X1 or it.Y < v.Y0 or it.Y > v.Y1 then
		fp.Visible = false
		return
	end
	local r = MapLabelLayout.PlaceFocus(it, out.Icons, lastControls, v, MapConfig)
	setPill(fp, it.Text, 1)
	fp.Position = UDim2.fromOffset(r.X0, r.Y0)
	fp.Size = UDim2.fromOffset(r.X1 - r.X0, r.Y1 - r.Y0)
	fp.Visible = true
end

local function layoutLabels()
	local layer = labelLayer
	if layer == nil or side <= 0 then
		return
	end
	local size = side * zoom()
	local view = { X0 = -panX, Y0 = -panY, X1 = -panX + side, Y1 = -panY + side }
	local controls = MapLabelLayout.ControlRects(side, PanelShell.TouchMinV(), MapConfig.CompassV, panX, panY)
	local out = MapLabelLayout.Build({
		Areas = MapAreas.List(),
		Sites = sitesNow(),
		Bases = basesNow(),
		Bank = bankNow(),
		Config = MapConfig,
		Size = size,
		View = view,
		TextV = PanelShell.Text(MapConfig.LabelTextV),
		Measure = measure,
		Controls = controls,
		MaxPriority = MapConfig.ZoomMaxPriority[zoomIdx] or 3,
	})
	lastLayout, lastControls, lastView = out, controls, view
	syncIcons(out.Icons, size)
	local seenL: { [string]: boolean } = {}
	for _, l in ipairs(out.Labels) do
		seenL[l.Id] = true
		local f = labelPool[l.Id]
		if not f then
			f = pill(layer, "Label_" .. l.Id, 10)
			labelPool[l.Id] = f
		end
		local ff = f :: Frame
		setPill(ff, l.Text, l.Priority)
		ff.Position = UDim2.fromOffset(l.X0, l.Y0)
		ff.Size = UDim2.fromOffset(l.X1 - l.X0, l.Y1 - l.Y0)
		ff.Visible = true
	end
	for id, f in pairs(labelPool) do
		if not seenL[id] then
			f.Visible = false
		end
	end
	showFocus()
end

-- ── zoom / pan ──────────────────────────────────────────────────────────────────────────────────────────────────────
local function clampPan()
	local maxP = side * (zoom() - 1)
	panX = math.clamp(panX, -maxP, 0)
	panY = math.clamp(panY, -maxP, 0)
end

local function applyZoom()
	local c = content
	if c == nil or side <= 0 then
		return
	end
	clampPan()
	local z = zoom()
	c.Size = UDim2.fromOffset(side * z, side * z)
	c.Position = UDim2.fromOffset(panX, panY)
	local zf = zoomFace
	if zf then
		zf.Text = if zoomIdx < #MapConfig.ZoomLevels then "+" else "−"
	end
	layoutLabels()
end

-- focus = the viewport point (v) that stays put
local function setZoom(idx: number, focus: Vector2?)
	idx = math.clamp(idx, 1, #MapConfig.ZoomLevels)
	if idx == zoomIdx or side <= 0 then
		return
	end
	local f = focus or Vector2.new(side / 2, side / 2)
	local oldZ, newZ = zoom(), MapConfig.ZoomLevels[idx]
	local cx, cy = (f.X - panX) / oldZ, (f.Y - panY) / oldZ -- the focus in zoom-1 v
	zoomIdx = idx
	panX, panY = f.X - cx * newZ, f.Y - cy * newZ
	pcall(AudioController.PlayClick)
	applyZoom()
end

-- a screen point (real px) -> viewport v
local function viewPoint(p: Vector2): Vector2?
	local cv = canvas
	if cv == nil then
		return nil
	end
	local s = vScale()
	return Vector2.new((p.X - cv.AbsolutePosition.X) / s, (p.Y - cv.AbsolutePosition.Y) / s)
end

local function fitLayout()
	local p, cv, card = panel, canvas, cardFrame
	if not (p and cv and card) then
		return
	end
	local s = vScale()
	local W, H = p.AbsoluteSize.X / s, p.AbsoluteSize.Y / s
	if W <= 0 or H <= 0 then
		return
	end
	local cardW = math.clamp(math.floor(W * 0.26), 240, 320)
	local sv = math.floor(math.min(H - 16, W - cardW - GAP - 24))
	local x0 = math.floor((W - (sv + GAP + cardW)) / 2)
	local y0 = math.floor((H - sv) / 2)
	cv.Position = UDim2.fromOffset(x0, y0)
	cv.Size = UDim2.fromOffset(sv, sv)
	card.Position = UDim2.fromOffset(x0 + sv + GAP, y0)
	card.Size = UDim2.fromOffset(cardW, sv)
	if sv ~= side then
		local k = if side > 0 then sv / side else 1
		side = sv
		panX, panY = panX * k, panY * k
		applyZoom()
	end
end

-- ── pooled live markers ───────────────────────────────────────────────────────────────────────────────────────────
local function marker(key: string, x: number, z: number, color: Color3, size: number, shape: string, label: string?)
	local layer = liveLayer
	if layer == nil then
		return
	end
	local m: GuiObject? = pool[key]
	if not m then
		local f: GuiObject
		if shape == "arrow" or shape == "pin" then
			local t = text(layer, if shape == "arrow" then "▲" else "▼", size, color, Enum.Font.GothamBlack)
			t.TextStrokeTransparency = 0
			t.TextStrokeColor3 = STROKE
			f = t
		else
			local fr = box(layer, key, color, 0, 8)
			corner(fr, UDim.new(0.5, 0))
			stroke(fr, STROKE, 1.5, 0.1)
			if label then
				inner(fr, "dot")
			end
			f = fr
		end
		f.Name = key
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.fromOffset(size, size)
		f.ZIndex = 8
		f.Parent = layer
		pool[key] = f
		m = f
	end
	local mm = m :: any
	local u, v = toUV(x, z)
	mm.Position = UDim2.fromScale(u, v)
	if mm:IsA("Frame") then
		(mm :: Frame).BackgroundColor3 = color
	elseif mm:IsA("TextLabel") then
		(mm :: TextLabel).TextColor3 = color
	end
	mm.Visible = true
end

local seen: { [string]: boolean } = {}
local function mark(key: string, ...: any)
	seen[key] = true
	marker(key, ...)
end

local function myRoot(): BasePart?
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

-- the live site / base set: a change re-runs the label pass (sites land at their placed points, "Your Base" appears)
local function liveSignature(live: any): string
	local parts: { string } = {}
	for _, st in ipairs(live.Sites or {}) do
		table.insert(parts, string.format("%s:%d:%d", tostring(st.Id), math.floor(tonumber(st.X) or 0), math.floor(tonumber(st.Z) or 0)))
	end
	for _, b in ipairs(live.Bases or {}) do
		table.insert(parts, tostring(b.P) .. (if b.Mine then "m" else ""))
	end
	return table.concat(parts, ",")
end

local function paint()
	table.clear(seen)
	local live = lastLive
	if typeof(live) == "table" then
		local sig = liveSignature(live)
		if sig ~= liveSig then
			liveSig = sig
			layoutLabels()
		end
		-- outposts: the owner badge on their area icon (yours green, enemy red, neutral gold)
		for _, o in ipairs(live.Outposts or {}) do
			local b = badges[o.Id]
			if b then
				b.BackgroundColor3 = if o.Mine then C.OutpostMine elseif o.O == "Neutral" then C.Outpost else C.OutpostEnemy
			end
		end
		for i, d in ipairs(live.Drops or {}) do
			mark("Drop" .. tostring(i), d.X, d.Z, C.Drop, if d.A then I.Airdrop else I.Drop, "circle", if d.A then "AIRDROP" else nil)
		end
		for i, j in ipairs(live.Jobs or {}) do
			mark("Job" .. tostring(i), j.X, j.Z, C.Job, I.Job, "circle", nil)
		end
	end
	if ObjectiveMarker.Pinned() then
		local t = ObjectiveMarker.Current()
		if t then
			mark("Pin", t.X, t.Z, C.Pin, I.Pin, "pin", nil)
		end
	end
	local root = myRoot()
	if root then
		local p = root.Position
		mark("Me", p.X, p.Z, C.Me, I.Me, "arrow", nil)
		local me = pool.Me
		if me then
			local lv = root.CFrame.LookVector
			me.Rotation = math.deg(math.atan2(lv.X, -lv.Z)) -- north (-Z) is up
			-- the rotated arrow is not clipped by the viewport: hide it while it is off the zoomed view
			local v = lastView
			if v and zoomIdx > 1 then
				local u, w = toUV(p.X, p.Z)
				local size = side * zoom()
				me.Visible = u * size >= v.X0 and u * size <= v.X1 and w * size >= v.Y0 and w * size <= v.Y1
			end
		end
	end
	for key, m in pairs(pool) do
		if not seen[key] then
			m.Visible = false
		end
	end
	if clearBtn then
		clearBtn.Visible = ObjectiveMarker.Pinned()
	end
end

-- ── the card ──────────────────────────────────────────────────────────────────────────────────────────────────────
local function outpostState(id: string?): (string?, boolean)
	local live = lastLive
	if id == nil or typeof(live) ~= "table" then
		return nil, false
	end
	for _, o in ipairs(live.Outposts or {}) do
		if o.Id == id then
			return o.O, o.Mine == true
		end
	end
	return nil, false
end

local function jobsIn(a: MapAreas.Area): string?
	local live = lastLive
	if typeof(live) ~= "table" then
		return nil
	end
	local kinds: { [string]: boolean } = {}
	local list: { string } = {}
	for _, j in ipairs(live.Jobs or {}) do
		if MapAreas.Inside(a, j.X, j.Z) and not kinds[j.S] then
			kinds[j.S] = true
			table.insert(list, j.S)
		end
	end
	return if #list > 0 then "Jobs: " .. table.concat(list, ", ") else nil
end

local function showCard(title: string?, lines: { string }, canGo: boolean)
	if cardTitle then
		cardTitle.Text = title or ""
	end
	if cardBody then
		cardBody.Text = table.concat(lines, "\n")
	end
	if goBtn then
		goBtn.Visible = canGo
	end
end

local function selectArea(a: MapAreas.Area, x: number, z: number)
	selected = { Kind = "Area", Id = a.Id, X = x, Z = z }
	local lines: { string } = {}
	table.insert(lines, MapConfig.KindInfo[a.Kind] or "Area")
	local owner, mine = outpostState(a.Territory)
	if a.Territory then
		table.insert(lines, "Outpost: " .. (if mine then "yours" elseif owner == "Neutral" or owner == nil then "free to capture" elseif owner == "Contested" then "under attack" else "enemy held"))
		if a.Bonus then
			table.insert(lines, a.Bonus)
		end
	end
	if a.Tier and MapConfig.EnemyText[a.Tier] then
		table.insert(lines, MapConfig.EnemyText[a.Tier])
	end
	local jobs = jobsIn(a)
	if jobs then
		table.insert(lines, jobs)
	end
	showCard(a.Name, lines, true)
end

local function selectSite(st: any)
	selected = { Kind = "Site", Id = tostring(st.Id), X = st.X, Z = st.Z }
	local lines: { string } = { MapConfig.SiteKindInfo[st.K] or "Site" }
	local acts: { string } = {}
	for _, d in ipairs(SiteActivityConfig.Activities) do
		local here = d.Site == st.Id
		for _, s2 in ipairs(d.Sites or {}) do
			here = here or s2 == st.Id
		end
		if here then
			table.insert(acts, d.Title)
		end
	end
	if #acts > 0 then
		table.insert(lines, "Activity: " .. table.concat(acts, ", "))
		table.insert(lines, "Start it from Missions")
	end
	if SiteActivityConfig.Garrisons.Sites[st.Id] then
		table.insert(lines, "Enemies: posted soldiers")
	end
	showCard(tostring(st.N or st.Id), lines, true)
end

local function selectBase(b: any)
	selected = { Kind = "Base", Id = tostring(b.P), X = b.X, Z = b.Z }
	local title = if b.Mine then "Your base" elseif typeof(b.N) == "string" then b.N else "Unclaimed base"
	showCard(title, { if b.Mine then "Home: build, collect, recruit" else "Player base" }, true)
end

local function selectBank(bk: any)
	selected = { Kind = "Bank", Id = "Bank", X = bk.X, Z = bk.Z }
	showCard("Crossroads Bank", { "The town bank", "Raid it with your crew" }, true)
end

-- a tapped icon / label id ("A:<area>", "S:<site>", "B:<plot>", "Bank") -> its card and its label on top
local function selectItem(id: string): boolean
	local kind, ref = string.match(id, "^(%a):(.+)$")
	local live = lastLive
	local ok = false
	if kind == "A" and ref then
		local a = MapAreas.ById(ref)
		if a then
			selectArea(a, a.X, a.Z)
			ok = true
		end
	elseif kind == "S" and ref then
		for _, st in ipairs(sitesNow()) do
			if tostring(st.Id) == ref then
				selectSite(st)
				ok = true
				break
			end
		end
	elseif kind == "B" and ref then
		for _, b in ipairs(basesNow()) do
			if tostring(b.P) == ref then
				if typeof(live) == "table" then
					selectBase(b)
				else
					selected = { Kind = "Base", Id = ref, X = b.X, Z = b.Z }
					showCard("Player base", { "Home plot" }, true)
				end
				ok = true
				break
			end
		end
	elseif id == "Bank" then
		selectBank(bankNow())
		ok = true
	end
	if ok then
		selectedItem = id
		pcall(AudioController.PlayClick)
		showFocus()
	end
	return ok
end

local function pinAt(x: number, z: number)
	local y = 5
	local hit = Workspace:Raycast(Vector3.new(x, 600, z), Vector3.new(0, -1200, 0))
	if hit then
		y = hit.Position.Y
	end
	pcall(AudioController.PlayClick)
	ObjectiveMarker.ShowWith({ Short = MapConfig.PinLabel, X = x, Y = y, Z = z }, {
		Pin = true,
		ArriveStuds = MapConfig.PinArriveStuds,
		TimeoutSeconds = MapConfig.PinTimeoutSeconds,
	})
	paint()
end

local function hitGui(g: GuiObject?, p: Vector2): boolean
	if g == nil or not g.Visible then
		return false
	end
	local a, s = g.AbsolutePosition, g.AbsoluteSize
	return p.X >= a.X and p.X <= a.X + s.X and p.Y >= a.Y and p.Y <= a.Y + s.Y
end

local function onTap(pos: Vector2)
	local cv, c = canvas, content
	if cv == nil or c == nil then
		return
	end
	if not hitGui(cv, pos) or hitGui(zoomBtn, pos) or hitGui(closeBtn, pos) then
		return
	end
	local ap, as = c.AbsolutePosition, c.AbsoluteSize
	if as.X <= 0 or as.Y <= 0 then
		return
	end
	local u, v = (pos.X - ap.X) / as.X, (pos.Y - ap.Y) / as.Y
	if u < 0 or u > 1 or v < 0 or v > 1 then
		return
	end
	local x, z = toWorld(u, v)
	local pxPerStud = as.X / (E.X1 - E.X0)
	-- 1. the pin
	if ObjectiveMarker.Pinned() then
		local t = ObjectiveMarker.Current()
		if t and math.sqrt((t.X - x) ^ 2 + (t.Z - z) ^ 2) * pxPerStud <= MapConfig.PinTapPx then
			ObjectiveMarker.ClearPin()
			selected = nil
			selectedItem = nil
			showFocus()
			showCard("Pin removed", {}, false)
			paint()
			return
		end
	end
	-- 2. a label pill (the focus pill first: it is on top)
	if hitGui(focusPill, pos) and selectedItem then
		return
	end
	for id, f in pairs(labelPool) do
		if hitGui(f, pos) and selectItem(id) then
			return
		end
	end
	-- 3. the nearest icon within IconTapPx real px (or its own radius)
	local out = lastLayout
	if out then
		local best, bestD = nil, math.huge
		local k = as.X / (side * zoom()) -- real px per content v
		for _, ic in ipairs(out.Icons) do
			local d = math.sqrt((ap.X + ic.X * k - pos.X) ^ 2 + (ap.Y + ic.Y * k - pos.Y) ^ 2)
			if d <= math.max(MapConfig.IconTapPx, ic.S / 2 * k) and d < bestD then
				best, bestD = ic, d
			end
		end
		if best and selectItem(best.Id) then
			return
		end
	end
	-- 4. a named site's ground (claude-bud JOB 31)
	for _, st in ipairs(sitesNow()) do
		if math.sqrt((st.X - x) ^ 2 + (st.Z - z) ^ 2) <= (tonumber(st.R) or 40) * 1.3 then
			selectSite(st)
			selectedItem = "S:" .. tostring(st.Id)
			showFocus()
			return
		end
	end
	-- 5. an area (its card; GO pins the tapped point)
	local a = MapAreas.At(x, z)
	if a then
		selectArea(a, x, z)
		selectedItem = "A:" .. a.Id
		showFocus()
		return
	end
	-- 6. open ground: a pin at once
	selected = nil
	selectedItem = nil
	showFocus()
	pinAt(x, z)
	showCard("Pin set", { "Follow the gold line" }, false)
end

-- ── open / close / refresh ────────────────────────────────────────────────────────────────────────────────────────
local function fetch()
	if inFlight then
		return
	end
	inFlight = true
	task.spawn(function()
		local fn = Remotes.TryGetFunction(Constants.RemoteNames.RequestMapLive)
		if fn then
			local ok, res = pcall(function()
				return fn:InvokeServer()
			end)
			if ok and typeof(res) == "table" then
				lastLive = res
			end
		end
		inFlight = false
	end)
end

local function setOpen(v: boolean)
	if v and not isLive() then
		return
	end
	open = v
	local p = panel
	if p then
		p.Visible = v
	end
	if shell then
		shell.Sync(v)
	end
	loopToken += 1
	if not v then
		return
	end
	local c = content
	if c then
		buildStatic(c)
	end
	selectedItem = nil
	fitLayout()
	layoutLabels()
	showCard("Tap a place", { "See what is there", "Tap open ground to pin" }, false)
	local my = loopToken
	task.spawn(function()
		while open and loopToken == my do
			fetch()
			paint()
			task.wait(math.max(0.5, MapConfig.RefreshSeconds))
		end
	end)
end

function MapController.Toggle()
	setOpen(not open)
end

function MapController.Open()
	setOpen(true)
end

function MapController.Close()
	setOpen(false)
end

function MapController.IsOpen(): boolean
	return open
end

function MapController.Init()
	if MapConfig.Enabled ~= true then
		return
	end
	local pg = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 30)
	if not (pg and pg:IsA("PlayerGui")) then
		warn("[WAR EMPIRE] MapController: no PlayerGui after 30 s; map off")
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireMap"
	uiScale = PanelShell.Screen(screen)
	screen.Parent = pg

	local root = Instance.new("Frame")
	root.Name = "Panel"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = C.Background
	root.BackgroundTransparency = 0.18
	root.BorderSizePixel = 0
	root.Active = true
	root.Visible = false
	root.Parent = screen
	panel = root
	local TAP = PanelShell.TouchMinV()

	-- the map viewport: a square, left of centre (fitLayout sizes it); the content inside it zooms and pans
	local cv = Instance.new("TextButton")
	cv.Name = "Canvas"
	cv.AutoButtonColor = false
	cv.Text = ""
	cv.AnchorPoint = Vector2.new(0, 0)
	cv.BackgroundColor3 = C.SeaDark
	cv.BorderSizePixel = 0
	cv.ClipsDescendants = true
	cv.ZIndex = 1
	cv.Parent = root
	corner(cv, UDim.new(0, 6))
	canvas = cv
	local ct = box(cv, "Content", C.SeaDark, 0, 1)
	content = ct
	local il = box(ct, "Icons", WHITE, 1, 6)
	il.Size = UDim2.fromScale(1, 1)
	iconLayer = il
	local layer = box(ct, "Live", WHITE, 1, 8)
	layer.Size = UDim2.fromScale(1, 1)
	liveLayer = layer
	local ll = box(ct, "Labels", WHITE, 1, 10)
	ll.Size = UDim2.fromScale(1, 1)
	labelLayer = ll
	focusPill = pill(ll, "Focus", 12)
	;(focusPill :: Frame).Visible = false

	-- over the map: the vignette, the frame + corner brackets, the compass, the zoom and close buttons
	for i, e in ipairs({ { 0, 0, 1, 0.14, 90 }, { 0, 0.86, 1, 0.14, -90 }, { 0, 0, 0.14, 1, 0 }, { 0.86, 0, 0.14, 1, 180 } }) do
		local vg = box(cv, "Vignette" .. i, Color3.new(0, 0, 0), 0, 20)
		vg.Position = UDim2.fromScale(e[1], e[2])
		vg.Size = UDim2.fromScale(e[3], e[4])
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new(0.45, 1)
		g.Rotation = e[5]
		g.Parent = vg
	end
	local frame = box(cv, "Frame", WHITE, 1, 21)
	frame.Size = UDim2.fromScale(1, 1)
	stroke(frame, C.Accent, 2, 0.35)
	for _, k in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
		for arm = 1, 2 do
			local br = box(cv, "Bracket", C.Accent, 0, 22)
			br.AnchorPoint = Vector2.new(k[1], k[2])
			br.Position = UDim2.fromScale(k[1], k[2])
			br.Size = if arm == 1 then UDim2.fromOffset(26, 3) else UDim2.fromOffset(3, 26)
		end
	end
	local CV = MapConfig.CompassV
	local rose = box(cv, "Compass", Color3.fromRGB(14, 16, 12), 0.2, 22)
	rose.AnchorPoint = Vector2.new(0, 1)
	rose.Position = UDim2.new(0, 10, 1, -10)
	rose.Size = UDim2.fromOffset(CV, CV)
	corner(rose, UDim.new(0.5, 0))
	stroke(rose, C.Accent, 1.5)
	local nArm = box(rose, "North", Color3.fromRGB(214, 70, 52), 0, 23)
	nArm.AnchorPoint = Vector2.new(0.5, 1)
	nArm.Position = UDim2.fromScale(0.5, 0.62)
	nArm.Size = UDim2.fromScale(0.1, 0.24)
	local sArm = box(rose, "South", Color3.fromRGB(220, 214, 196), 0, 23)
	sArm.AnchorPoint = Vector2.new(0.5, 0)
	sArm.Position = UDim2.fromScale(0.5, 0.62)
	sArm.Size = UDim2.fromScale(0.1, 0.24)
	local ew = box(rose, "EastWest", Color3.fromRGB(120, 116, 100), 0, 23)
	ew.AnchorPoint = Vector2.new(0.5, 0.5)
	ew.Position = UDim2.fromScale(0.5, 0.62)
	ew.Size = UDim2.fromScale(0.6, 0.06)
	local nT = text(rose, "N", 14, C.Accent, Enum.Font.GothamBlack)
	nT.AnchorPoint = Vector2.new(0.5, 0)
	nT.Position = UDim2.fromScale(0.5, 0.02)
	nT.Size = UDim2.fromScale(1, 0.36)
	nT.TextStrokeTransparency = 0.2
	nT.ZIndex = 24
	local zb = Instance.new("TextButton")
	zb.Name = "Zoom"
	zb.Position = UDim2.fromOffset(4, 4)
	zb.Size = UDim2.fromOffset(TAP, TAP)
	zb.BackgroundTransparency = 1
	zb.Text = ""
	zb.ZIndex = 24
	zb.Parent = cv
	local zf = text(zb, "+", 26, C.Text, Enum.Font.GothamBold)
	zf.Name = "Face"
	zf.AnchorPoint = Vector2.new(0.5, 0.5)
	zf.Position = UDim2.fromScale(0.5, 0.5)
	zf.Size = UDim2.fromScale(0.72, 0.72)
	zf.BackgroundTransparency = 0.15
	zf.BackgroundColor3 = Color3.fromRGB(14, 16, 12)
	zf.ZIndex = 25
	corner(zf, UDim.new(0.22, 0))
	stroke(zf, C.Accent, 1.5)
	zoomBtn, zoomFace = zb, zf
	zb.Activated:Connect(function()
		setZoom(if zoomIdx < #MapConfig.ZoomLevels then zoomIdx + 1 else 1, nil)
	end)
	closeBtn = PanelShell.CloseButton(cv, function()
		setOpen(false)
	end, { ZIndex = 24 })

	-- input: a tap (press + release within 12 px) picks / pins; at zoom 2 a drag pans; a pinch or the wheel zooms
	local touches: { [InputObject]: boolean } = {}
	local downAt: Vector2? = nil
	local dragInput: InputObject? = nil
	local dragging = false
	local panStart = Vector2.zero
	local function touchCount(): number
		local n = 0
		for _ in pairs(touches) do
			n += 1
		end
		return n
	end
	cv.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if t == Enum.UserInputType.Touch then
			touches[input] = true
			if touchCount() > 1 then -- a pinch: no tap, no pan
				downAt, dragInput = nil, nil
				return
			end
		end
		downAt = Vector2.new(input.Position.X, input.Position.Y)
		dragInput = input
		dragging = false
		panStart = Vector2.new(panX, panY)
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local d0, di = downAt, dragInput
		if not open or d0 == nil or di == nil then
			return
		end
		local mine = input == di or (di.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)
		if not mine then
			return
		end
		local d = Vector2.new(input.Position.X, input.Position.Y) - d0
		if d.Magnitude > 12 then
			dragging = true
		end
		local c = content
		if dragging and zoomIdx > 1 and c then
			local s = vScale()
			panX, panY = panStart.X + d.X / s, panStart.Y + d.Y / s
			clampPan()
			c.Position = UDim2.fromOffset(panX, panY)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		touches[input] = nil
		local di = dragInput
		if di == nil or not (input == di or (di.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1)) then
			return
		end
		local d0 = downAt
		downAt, dragInput = nil, nil
		if not open or d0 == nil then
			return
		end
		local p = Vector2.new(input.Position.X, input.Position.Y)
		if not dragging and (p - d0).Magnitude <= 12 then
			onTap(p)
		elseif dragging and zoomIdx > 1 then
			layoutLabels()
		end
		dragging = false
	end)
	cv.TouchPinch:Connect(function(positions: { Vector2 }, scale: number, _velocity: number, state: Enum.UserInputState)
		downAt, dragInput = nil, nil
		if state ~= Enum.UserInputState.End and state ~= Enum.UserInputState.Cancel then
			return
		end
		local mid: Vector2? = nil
		if #positions >= 2 then
			mid = viewPoint((positions[1] + positions[2]) / 2)
		end
		if scale > 1.15 then
			setZoom(zoomIdx + 1, mid)
		elseif scale < 0.87 then
			setZoom(zoomIdx - 1, mid)
		end
	end)
	cv.MouseWheelForward:Connect(function(x: number, y: number)
		setZoom(zoomIdx + 1, viewPoint(Vector2.new(x, y)))
	end)
	cv.MouseWheelBackward:Connect(function(x: number, y: number)
		setZoom(zoomIdx - 1, viewPoint(Vector2.new(x, y)))
	end)

	-- the slim info card (right of the map): title, the selected place, GO / CLEAR PIN, the legend, the hint
	local card = box(root, "Side", C.Card, 0.08, 2)
	corner(card, UDim.new(0, 10))
	stroke(card, C.Accent, 1.5, 0.45)
	cardFrame = card
	local padF = Instance.new("UIPadding")
	padF.PaddingLeft, padF.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	padF.PaddingTop, padF.PaddingBottom = UDim.new(0, 10), UDim.new(0, 10)
	padF.Parent = card
	local y = 0
	local title = text(card, "WORLD MAP", 20, C.Accent, Enum.Font.GothamBlack)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Size = UDim2.new(1, 0, 0, PanelShell.Text(20) + 4)
	title.ZIndex = 3
	y += PanelShell.Text(20) + 8
	local rule1 = box(card, "Rule", C.Accent, 0.6, 3)
	rule1.Position = UDim2.fromOffset(0, y)
	rule1.Size = UDim2.new(1, 0, 0, 1)
	y += 8
	local ctl = text(card, "", 22, C.Text, Enum.Font.GothamBold)
	ctl.TextXAlignment = Enum.TextXAlignment.Left
	ctl.TextTruncate = Enum.TextTruncate.AtEnd
	ctl.Position = UDim2.fromOffset(0, y)
	ctl.Size = UDim2.new(1, 0, 0, PanelShell.Text(22) + 4)
	ctl.ZIndex = 3
	cardTitle = ctl
	y += PanelShell.Text(22) + 6
	local cb = text(card, "", 18, C.Muted, Enum.Font.GothamMedium)
	cb.TextXAlignment = Enum.TextXAlignment.Left
	cb.TextYAlignment = Enum.TextYAlignment.Top
	cb.TextWrapped = true
	cb.TextStrokeTransparency = 1
	cb.Position = UDim2.fromOffset(0, y)
	cb.Size = UDim2.new(1, 0, 0, (PanelShell.Text(18) + 3) * 3)
	cb.ZIndex = 3
	cardBody = cb
	y += (PanelShell.Text(18) + 3) * 3 + 6
	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(0, y)
	row.Size = UDim2.new(1, 0, 0, TAP)
	row.ZIndex = 3
	row.Parent = card
	local rl = Instance.new("UIListLayout")
	rl.FillDirection = Enum.FillDirection.Horizontal
	rl.Padding = UDim.new(0, 8)
	rl.Parent = row
	local goB = button(row, "Go", "GO", 96)
	local clearB = button(row, "ClearPin", "CLEAR PIN", 150)
	goBtn, clearBtn = goB, clearB
	y += TAP + 10
	local rule2 = box(card, "Rule", C.Accent, 0.6, 3)
	rule2.Position = UDim2.fromOffset(0, y)
	rule2.Size = UDim2.new(1, 0, 0, 1)
	y += 8
	-- the legend, as the map's own icons
	local legend = Instance.new("Frame")
	legend.Name = "Legend"
	legend.BackgroundTransparency = 1
	legend.Position = UDim2.fromOffset(0, y)
	legend.Size = UDim2.new(1, 0, 0, (PanelShell.Text(16) + 6) * 5)
	legend.Parent = card
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -4, 0, PanelShell.Text(16) + 4)
	grid.CellPadding = UDim2.fromOffset(8, 2)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = legend
	local ENTRIES = {
		{ "Town", "Town" }, { "Military", "Military" }, { "Industry", "Industry" }, { "Camp", "Wilds" }, { "Site", "Site" },
		{ "Your base", "BaseMine" }, { "Outpost", "Badge" }, { "Bank", "Bank" }, { "Crate / job", "Job" }, { "You", "Me" },
	}
	for i, en in ipairs(ENTRIES) do
		local cell = Instance.new("Frame")
		cell.Name = "Key" .. i
		cell.BackgroundTransparency = 1
		cell.LayoutOrder = i
		cell.Parent = legend
		local g = en[2]
		if g == "Badge" then
			local b = box(cell, "Icon", C.Outpost, 0, 4)
			b.AnchorPoint = Vector2.new(0.5, 0.5)
			b.Position = UDim2.new(0, 9, 0.5, 0)
			b.Size = UDim2.fromOffset(11, 11)
			corner(b, UDim.new(0, 2))
			stroke(b, STROKE, 1.5)
		elseif g == "Me" then
			local t = text(cell, "▲", 16, C.Me, Enum.Font.GothamBlack)
			t.TextStrokeTransparency = 0
			t.TextStrokeColor3 = STROKE
			t.AnchorPoint = Vector2.new(0.5, 0.5)
			t.Position = UDim2.new(0, 9, 0.5, 0)
			t.Size = UDim2.fromOffset(18, 18)
			t.ZIndex = 4
		else
			local ic = makeIcon(cell, g, 16, 4)
			ic.Position = UDim2.new(0, 9, 0.5, 0)
		end
		local t = text(cell, en[1], 16, C.Text, Enum.Font.GothamMedium)
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.TextStrokeTransparency = 1
		t.Position = UDim2.fromOffset(24, 0)
		t.Size = UDim2.new(1, -24, 1, 0)
		t.ZIndex = 4
	end
	local hint = text(card, "Pinch or + to zoom · tap to pin", 15, C.Muted, Enum.Font.GothamMedium)
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextStrokeTransparency = 1
	hint.TextTruncate = Enum.TextTruncate.AtEnd
	hint.AnchorPoint = Vector2.new(0, 1)
	hint.Position = UDim2.fromScale(0, 1)
	hint.Size = UDim2.new(1, 0, 0, PanelShell.Text(15) + 2)
	hint.ZIndex = 3

	goB.Activated:Connect(function()
		local s = selected
		if s then
			pinAt(s.X, s.Z)
			setOpen(false)
		end
	end)
	clearB.Activated:Connect(function()
		ObjectiveMarker.ClearPin()
		paint()
	end)

	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if open then
			fitLayout()
		end
	end)

	shell = PanelShell.Attach({
		Id = PANEL_ID,
		Screen = screen,
		Panel = root,
		IsOpen = function(): boolean
			return open
		end,
		Close = function()
			setOpen(false)
		end,
	})

	-- M opens it when the player prefers keys (Missions moved to N); never a touch-only feature
	UserInputService.InputBegan:Connect(function(input, gp)
		if gp or input.KeyCode ~= (HudConfig.Keys :: any).Map then
			return
		end
		setOpen(not open)
	end)
end

return MapController
