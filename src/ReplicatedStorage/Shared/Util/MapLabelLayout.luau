--!strict
--[[
	Code Bot MAP-REDESIGN (v129, 2026-09-30): the world map's icon + label layout (pure; no Roblox calls, so the offline
	test tools/sim/run_map_layout_test.py runs this exact code on the real POI / site / base positions).

	Build(input) -> { Icons, Labels, Hidden }
	  * Icons: one per named area (MapAreas), JOB 31 site, base and the bank, in CONTENT v coordinates (the zoomed map
	    frame; 0,0 = its top-left, Size = the viewport side x Zoom). Every icon is the same few sizes (MapConfig.Icon).
	  * Labels: the collision pass. Items are placed in priority order (MapConfig.LabelPriority: towns / sites 1 >
	    outposts / camps 2 > depots 3; your base 0). Each tries up to 32 candidates round its icon (the 8 slots right,
	    left, above, below, the diagonals; the side slots slid a little; the 8 slots two steps further out), is clamped inside the visible map window, and is kept only if its pill touches
	    no placed pill, no icon and no map control (close X, zoom button, compass). Items whose priority is above
	    MaxPriority (zoom 1 hides the depots) or that still collide are Hidden: the card names them on tap, zoom 2
	    shows more of them.
	PlaceFocus(...) places ONE label (the tapped place) against the icons only: the tap-to-see-a-hidden-label pill.
]]

local MapLabelLayout = {}

export type Rect = { X0: number, Y0: number, X1: number, Y1: number }
export type Icon = { Id: string, Ref: string, Kind: string, Group: string, X: number, Y: number, S: number, Territory: string? }
export type Item = { Id: string, Text: string, X: number, Y: number, R: number, W: number, H: number, Priority: number, Rank: number, Order: number }
export type Label = { Id: string, Text: string, X0: number, Y0: number, X1: number, Y1: number, Priority: number, Slot: number }

-- right, left, above, below, above-right, below-right, above-left, below-left
MapLabelLayout.Slots = { { 1, 0 }, { -1, 0 }, { 0, -1 }, { 0, 1 }, { 1, -1 }, { 1, 1 }, { -1, -1 }, { -1, 1 } }

-- "FORT IRONCLAD approach" -> "Fort Ironclad Approach"
function MapLabelLayout.TitleCase(s: string): string
	return (string.gsub(s, "(%a)([%w']*)", function(a: string, b: string): string
		return string.upper(a) .. string.lower(b)
	end))
end

-- a conservative width for a Gotham Medium / Bold line (the client measures with TextService when it can)
local NARROW = { i = 0.28, l = 0.28, j = 0.3, f = 0.36, t = 0.38, r = 0.4, I = 0.32, [" "] = 0.3, ["'"] = 0.26, ["."] = 0.3 }
local WIDE = { m = 0.9, w = 0.82, M = 0.9, W = 1.0 }
function MapLabelLayout.EstimateWidth(text: string, size: number): number
	local w = 0
	for i = 1, #text do
		local ch = string.sub(text, i, i)
		local f = NARROW[ch] or WIDE[ch]
		if f == nil then
			if string.match(ch, "%u") then
				f = 0.7
			elseif string.match(ch, "%d") then
				f = 0.62
			else
				f = 0.6
			end
		end
		w += f * size
	end
	return math.ceil(w)
end

function MapLabelLayout.Overlaps(a: Rect, b: Rect, pad: number): boolean
	return a.X0 < b.X1 + pad and b.X0 < a.X1 + pad and a.Y0 < b.Y1 + pad and b.Y0 < a.Y1 + pad
end

local function inside(r: Rect, b: Rect): boolean
	return r.X0 >= b.X0 - 0.01 and r.Y0 >= b.Y0 - 0.01 and r.X1 <= b.X1 + 0.01 and r.Y1 <= b.Y1 + 0.01
end

-- the candidate pill for slot (dx, dy) round an icon of radius r at (x, y)
local function candidate(it: Item, dx: number, dy: number, gap: number): Rect
	local r = it.R
	local x0, y0
	local diag = dx ~= 0 and dy ~= 0
	local rx = if diag then r * 0.72 else r
	if dx > 0 then
		x0 = it.X + rx + gap
	elseif dx < 0 then
		x0 = it.X - rx - gap - it.W
	else
		x0 = it.X - it.W / 2
	end
	if dy < 0 then
		y0 = it.Y - rx - gap - it.H
	elseif dy > 0 then
		y0 = it.Y + rx + gap
	else
		y0 = it.Y - it.H / 2
	end
	return { X0 = x0, Y0 = y0, X1 = x0 + it.W, Y1 = y0 + it.H }
end

-- shift r inside b (a pill wider than b is left as it is: it will fail inside())
local function clamp(r: Rect, b: Rect): Rect
	local sx, sy = 0, 0
	if r.X0 < b.X0 then
		sx = b.X0 - r.X0
	elseif r.X1 > b.X1 then
		sx = b.X1 - r.X1
	end
	if r.Y0 < b.Y0 then
		sy = b.Y0 - r.Y0
	elseif r.Y1 > b.Y1 then
		sy = b.Y1 - r.Y1
	end
	return { X0 = r.X0 + sx, Y0 = r.Y0 + sy, X1 = r.X1 + sx, Y1 = r.Y1 + sy }
end

local function free(r: Rect, placed: { Rect }, obstacles: { Rect }, pad: number, obstaclePad: number): boolean
	for _, p in ipairs(placed) do
		if MapLabelLayout.Overlaps(r, p, pad) then
			return false
		end
	end
	for _, o in ipairs(obstacles) do
		if MapLabelLayout.Overlaps(r, o, obstaclePad) then
			return false
		end
	end
	return true
end

-- the candidate list, best first: the 8 slots; then the side slots slid along the icon (a pill may sit a little
-- above / below its icon's centre line, or left / right of it); then the 8 slots one step further out
local SHIFTS = { 0, -1, 1 }
local function candidates(it: Item, gap: number): { Rect }
	local out: { Rect } = {}
	for _, d in ipairs(MapLabelLayout.Slots) do
		table.insert(out, candidate(it, d[1], d[2], gap))
	end
	for k = 2, 3 do
		for _, d in ipairs(MapLabelLayout.Slots) do
			if d[1] == 0 or d[2] == 0 then
				local c = candidate(it, d[1], d[2], gap)
				local sx = if d[1] == 0 then SHIFTS[k] * it.W * 0.3 else 0
				local sy = if d[2] == 0 then SHIFTS[k] * it.H * 0.6 else 0
				table.insert(out, { X0 = c.X0 + sx, Y0 = c.Y0 + sy, X1 = c.X1 + sx, Y1 = c.Y1 + sy })
			end
		end
	end
	for _, far in ipairs({ 8, 16 }) do
		for _, d in ipairs(MapLabelLayout.Slots) do
			table.insert(out, candidate(it, d[1], d[2], gap + far))
		end
	end
	return out
end
MapLabelLayout.CandidateCount = 8 + 8 + 16 -- 8 slots, 4 side slots x 2 slides, 8 slots at 2 steps further out

-- one item: the first free candidate (clamped inside bounds; a clamp may slide a pill at most MaxSlide v)
local function placeItem(it: Item, placed: { Rect }, obstacles: { Rect }, bounds: Rect, o: any): (Rect?, number)
	for slot, raw in ipairs(candidates(it, o.Gap)) do
		local c = clamp(raw, bounds)
		if inside(c, bounds) and math.abs(c.X0 - raw.X0) + math.abs(c.Y0 - raw.Y0) <= o.MaxSlide and free(c, placed, obstacles, o.Pad, o.ObstaclePad) then
			return c, slot
		end
	end
	return nil, 0
end

local function iconRect(ic: Icon): Rect
	local h = ic.S / 2
	return { X0 = ic.X - h, Y0 = ic.Y - h, X1 = ic.X + h, Y1 = ic.Y + h }
end

--[[ input = {
	Areas = MapAreas.List(), Sites = { { Id, N, K, X, Z, R } }, Bases = { { P, X, Z, Mine } }, Bank = { X, Z }?,
	Config = MapConfig, Size = content side (v), View = the visible window (content v Rect), TextV = label text size (v),
	Measure = (text) -> width v, Controls = { Rect } (content v: close X, zoom, compass), MaxPriority = number,
} ]]
function MapLabelLayout.Build(input: any): { Icons: { Icon }, Labels: { Label }, Hidden: { string }, Items: { [string]: Item } }
	local cfg = input.Config
	local E = cfg.Extent
	local size: number = input.Size
	local I = cfg.Icon
	local function px(x: number, z: number): (number, number)
		return (x - E.X0) / (E.X1 - E.X0) * size, (z - E.Z0) / (E.Z1 - E.Z0) * size
	end
	local icons: { Icon } = {}
	local items: { Item } = {}
	local byId: { [string]: Item } = {}
	local textV: number = input.TextV
	local h = textV + 2 * cfg.LabelPadY
	local function addItem(id: string, text: string, x: number, y: number, s: number, pr: number, kind: string)
		local w = input.Measure(text) + 2 * cfg.LabelPadX
		local rank = cfg.LabelRank[kind] or 50
		local it: Item = { Id = id, Text = text, X = x, Y = y, R = s / 2, W = w, H = h, Priority = pr, Rank = rank, Order = #items + 1 }
		table.insert(items, it)
		byId[id] = it
	end
	for _, a in ipairs(input.Areas or {}) do
		local x, y = px(a.X, a.Z)
		local id = "A:" .. a.Id
		local kind = if a.Kind == "" then "outpost" else a.Kind
		table.insert(icons, { Id = id, Ref = a.Id, Kind = kind, Group = cfg.KindGroup[kind] or "Wilds", X = x, Y = y, S = I.Area, Territory = a.Territory })
		local name = cfg.LabelShort[a.Id] or MapLabelLayout.TitleCase((string.gsub(a.Name, " approach$", "")))
		addItem(id, name, x, y, I.Area, cfg.LabelPriority[kind] or 2, kind)
	end
	for _, st in ipairs(input.Sites or {}) do
		local x, y = px(st.X, st.Z)
		local id = "S:" .. tostring(st.Id)
		table.insert(icons, { Id = id, Ref = tostring(st.Id), Kind = tostring(st.K), Group = "Site", X = x, Y = y, S = I.Site })
		local name = cfg.LabelShort[st.Id] or MapLabelLayout.TitleCase(tostring(st.N or st.Id))
		addItem(id, name, x, y, I.Site, cfg.LabelPriority["site_" .. tostring(st.K)] or cfg.LabelPriority.site or 1, "site")
	end
	for _, b in ipairs(input.Bases or {}) do
		local x, y = px(b.X, b.Z)
		local id = "B:" .. tostring(b.P)
		local s = if b.Mine then I.BaseMine else I.Base
		table.insert(icons, { Id = id, Ref = tostring(b.P), Kind = if b.Mine then "basemine" else "base", Group = if b.Mine then "BaseMine" else "Base", X = x, Y = y, S = s })
		if b.Mine then
			addItem(id, cfg.MyBaseLabel, x, y, s, 0, "base")
		end
	end
	if typeof(input.Bank) == "table" then
		local x, y = px(input.Bank.X, input.Bank.Z)
		table.insert(icons, { Id = "Bank", Ref = "Bank", Kind = "bank", Group = "Bank", X = x, Y = y, S = I.Bank })
	end

	local obstacles: { Rect } = {}
	for _, ic in ipairs(icons) do
		table.insert(obstacles, iconRect(ic))
	end
	for _, c in ipairs(input.Controls or {}) do
		table.insert(obstacles, c)
	end
	local m = cfg.LabelEdge
	local v = input.View
	local bounds: Rect = { X0 = v.X0 + m, Y0 = v.Y0 + m, X1 = v.X1 - m, Y1 = v.Y1 - m }
	local order = table.clone(items)
	table.sort(order, function(a: Item, b: Item): boolean
		if a.Priority ~= b.Priority then
			return a.Priority < b.Priority
		end
		if a.Rank ~= b.Rank then
			return a.Rank < b.Rank
		end
		return a.Order < b.Order
	end)
	local opts = { Gap = cfg.LabelGap, Pad = cfg.LabelPad, ObstaclePad = cfg.LabelIconPad, MaxSlide = cfg.LabelMaxSlide }
	local placed: { Rect } = {}
	local labels: { Label } = {}
	local hidden: { string } = {}
	for _, it in ipairs(order) do
		local onView = it.X >= bounds.X0 and it.X <= bounds.X1 and it.Y >= bounds.Y0 and it.Y <= bounds.Y1
		local r: Rect?, slot = nil, 0
		if onView and it.Priority <= input.MaxPriority then
			r, slot = placeItem(it, placed, obstacles, bounds, opts)
		end
		if r then
			table.insert(placed, r)
			table.insert(labels, { Id = it.Id, Text = it.Text, X0 = r.X0, Y0 = r.Y0, X1 = r.X1, Y1 = r.Y1, Priority = it.Priority, Slot = slot })
		else
			table.insert(hidden, it.Id)
		end
	end
	return { Icons = icons, Labels = labels, Hidden = hidden, Items = byId }
end

-- the tapped place's pill: free of icons and controls if it can be (other labels may sit under it: it is drawn on top)
function MapLabelLayout.PlaceFocus(it: Item, icons: { Icon }, controls: { Rect }, view: Rect, cfg: any): Rect
	local obstacles: { Rect } = {}
	for _, ic in ipairs(icons) do
		table.insert(obstacles, iconRect(ic))
	end
	for _, c in ipairs(controls) do
		table.insert(obstacles, c)
	end
	local m = cfg.LabelEdge
	local bounds: Rect = { X0 = view.X0 + m, Y0 = view.Y0 + m, X1 = view.X1 - m, Y1 = view.Y1 - m }
	local opts = { Gap = cfg.LabelGap, Pad = 0, ObstaclePad = cfg.LabelIconPad, MaxSlide = math.huge }
	local r = placeItem(it, {}, obstacles, bounds, opts)
	return r or clamp(candidate(it, 0, -1, cfg.LabelGap), bounds)
end

-- the map controls drawn over the viewport (content v coords for pan offset (ox, oy) <= 0), so labels keep off them
function MapLabelLayout.ControlRects(viewSide: number, tap: number, compass: number, ox: number, oy: number): { Rect }
	local x0, y0 = -ox, -oy
	local x1, y1 = x0 + viewSide, y0 + viewSide
	return {
		{ X0 = x1 - tap - 4, Y0 = y0, X1 = x1, Y1 = y0 + tap + 4 }, -- close X (top-right)
		{ X0 = x0, Y0 = y0, X1 = x0 + tap + 4, Y1 = y0 + tap + 4 }, -- zoom (top-left)
		{ X0 = x0, Y0 = y1 - compass - 10, X1 = x0 + compass + 10, Y1 = y1 }, -- compass rose (bottom-left)
	}
end

return MapLabelLayout
