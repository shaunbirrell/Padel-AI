--!strict
--[[
	HudIcons — v70 HUD icons built ONLY from Frames + UICorner + Rotation (no emoji, no uploaded images).

	Every part is placed in Scale units of the icon box, so an icon draws at any size and follows the gui's
	UIScale. Frame.Rotation turns about the centre, so every part is centred (AnchorPoint 0.5,0.5) and bars that
	pivot about an end have their centres pre-computed.

	  local icon = HudIcons.Make("Cart", parent, { Size = UDim2.fromOffset(38, 38), Color = accent, Fill = tileFill })
	  HudIcons.SetColor(icon, newInk, newFill?)      -- recolour (e.g. locked / pressed states)
	  HudIcons.SetRotation(compassArrow, bearingDeg)  -- "Arrow" only: turns the inner "Rot" group

	Colours: Color = the icon ink (default white). Fill = the colour of what the icon sits on: holes and gap
	masks (gear hole, ring centres, clipboard rows, cart slots) are painted with it (default HudConfig PillBg).
	"Cash" has its own fixed greens and a 42:32 box (HudConfig.CashPill.IconSize).

	Kinds: Cart Cycle Helmet Car Clipboard Gear Cash Shield Crosshair Arrow Plus Up Down Close Chevron Dot Flag
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HudConfig = require(Shared.Configs.HudConfig)

local HudIcons = {}

export type IconOpts = {
	Size: UDim2?, -- default UDim2.fromOffset(24, 24) (v units under a HUD UIScale)
	Position: UDim2?,
	AnchorPoint: Vector2?,
	ZIndex: number?, -- base ZIndex; parts stack above it in draw order
	LayoutOrder: number?,
	Name: string?,
	Color: Color3?, -- ink
	Fill: Color3?, -- background the icon sits on
	Rotation: number?, -- "Arrow": bearing in degrees, clockwise (same as SetRotation)
	Transparency: number?, -- ink/fill transparency (0 = solid)
}

-- role: "Ink" (Color), "Fill" (Fill), or a fixed Color3
type Part = {
	x: number, -- centre, fraction of the box
	y: number,
	w: number,
	h: number,
	role: string?,
	color: Color3?,
	r: number?, -- UICorner scale (0.5 = round); nil = square
	rot: number?,
	clip: { x: number, y: number, w: number, h: number }?, -- draw inside an axis-aligned clip frame (box coords)
}

local INK_DEFAULT = Color3.fromRGB(255, 255, 255)
local FILL_DEFAULT: Color3 = HudConfig.Colors.PillBg

-- top-left box (x, y, w, h) → centred part
local function box(x: number, y: number, w: number, h: number, role: string?, r: number?, rot: number?): Part
	return { x = x + w / 2, y = y + h / 2, w = w, h = h, role = role or "Ink", r = r, rot = rot }
end
local function fixed(x: number, y: number, w: number, h: number, color: Color3, r: number?): Part
	return { x = x + w / 2, y = y + h / 2, w = w, h = h, role = "Fixed", color = color, r = r }
end
-- a bar of length len and thickness t whose END sits at (ex, ey), pointing away from it at rot degrees
-- (rot 0 = straight down from the end point; positive = clockwise, like Frame.Rotation)
local function barFrom(ex: number, ey: number, t: number, len: number, rot: number, role: string?): Part
	local a = math.rad(rot)
	return {
		x = ex - math.sin(a) * len / 2,
		y = ey + math.cos(a) * len / 2,
		w = t,
		h = len,
		role = role or "Ink",
		r = 0.5,
		rot = rot,
	}
end

local SHAPES: { [string]: { Part } } = {}

SHAPES.Cart = {
	box(0.03, 0.17, 0.24, 0.08, "Ink", 0.5, 18), -- handle
	box(0.24, 0.3, 0.64, 0.38, "Ink", 0.26), -- basket (rounded bottom)
	box(0.24, 0.3, 0.64, 0.19, "Ink"), -- squares the basket's top corners
	box(0.2, 0.28, 0.72, 0.08, "Ink", 0.5), -- rim
	box(0.34, 0.39, 0.07, 0.2, "Fill", 0.43),
	box(0.51, 0.39, 0.07, 0.2, "Fill", 0.43),
	box(0.68, 0.39, 0.07, 0.2, "Fill", 0.43),
	box(0.3, 0.72, 0.16, 0.16, "Ink", 0.5), -- wheels
	box(0.66, 0.72, 0.16, 0.16, "Ink", 0.5),
}

SHAPES.Cycle = {
	box(0.1, 0.1, 0.8, 0.8, "Ink", 0.5), -- ring
	box(0.23, 0.23, 0.54, 0.54, "Fill", 0.5), -- ring hole
	box(0.62, 0.02, 0.3, 0.24, "Fill", nil, 30), -- gap top-right
	box(0.08, 0.74, 0.3, 0.24, "Fill", nil, 30), -- gap bottom-left
	-- arrowheads: half of a 45° diamond, clipped (a right-angled wedge)
	{ x = 0, y = 0.5, w = 0.2121, h = 0.2121, role = "Ink", rot = 45, clip = { x = 0.52, y = 0.04, w = 0.15, h = 0.3 } },
	{ x = 1, y = 0.5, w = 0.2121, h = 0.2121, role = "Ink", rot = 45, clip = { x = 0.33, y = 0.66, w = 0.15, h = 0.3 } },
}

SHAPES.Helmet = {
	box(0.14, 0.18, 0.72, 0.52, "Ink", 0.5), -- dome
	box(0.14, 0.44, 0.72, 0.26, "Ink"), -- squares the dome's lower corners
	box(0.05, 0.64, 0.9, 0.12, "Ink", 0.5), -- brim
	box(0.14, 0.52, 0.72, 0.07, "Fill"), -- band
	box(0.43, 0.28, 0.14, 0.14, "Fill", 0.5), -- badge
}

SHAPES.Car = {
	box(0.26, 0.24, 0.48, 0.26, "Ink", 0.46), -- cabin
	box(0.26, 0.37, 0.48, 0.13, "Ink"),
	box(0.33, 0.3, 0.34, 0.14, "Fill", 0.29), -- window
	box(0.06, 0.46, 0.88, 0.26, "Ink", 0.35), -- body
	box(0.17, 0.6, 0.22, 0.22, "Ink", 0.5), -- wheel rims
	box(0.61, 0.6, 0.22, 0.22, "Ink", 0.5),
	fixed(0.22, 0.65, 0.12, 0.12, Color3.fromRGB(21, 24, 27), 0.5), -- tyres
	fixed(0.66, 0.65, 0.12, 0.12, Color3.fromRGB(21, 24, 27), 0.5),
}

SHAPES.Clipboard = {
	box(0.18, 0.12, 0.64, 0.82, "Ink", 0.125), -- board
	box(0.34, 0.05, 0.32, 0.15, "Ink", 0.33), -- clip
	box(0.38, 0.09, 0.24, 0.07, "Fill", 0.5),
	box(0.27, 0.36, 0.11, 0.11, "Fill", 0.18), -- rows
	box(0.43, 0.385, 0.3, 0.06, "Fill", 0.5),
	box(0.27, 0.53, 0.11, 0.11, "Fill", 0.18),
	box(0.43, 0.555, 0.3, 0.06, "Fill", 0.5),
	box(0.27, 0.7, 0.11, 0.11, "Fill", 0.18),
	box(0.43, 0.725, 0.3, 0.06, "Fill", 0.5),
}

SHAPES.Gear = {
	box(0.4, 0.04, 0.2, 0.92, "Ink", 0.2, 0), -- 8 teeth = 4 bars
	box(0.4, 0.04, 0.2, 0.92, "Ink", 0.2, 45),
	box(0.4, 0.04, 0.2, 0.92, "Ink", 0.2, 90),
	box(0.4, 0.04, 0.2, 0.92, "Ink", 0.2, 135),
	box(0.16, 0.16, 0.68, 0.68, "Ink", 0.5), -- disc
	box(0.35, 0.35, 0.3, 0.3, "Fill", 0.5), -- hole
}

do -- Cash: 3 stacked bills in a 42:32 box (converted from the mock's 42x42 box shifted up 5)
	local edge = Color3.fromRGB(11, 61, 22)
	local cols = { Color3.fromRGB(28, 140, 52), Color3.fromRGB(44, 176, 70), Color3.fromRGB(74, 214, 96) }
	local ys = { 0.5, 0.303, 0.106 }
	local h = 0.4725
	local bw = 0.03 -- border, fraction of the box width
	local parts: { Part } = {}
	for i = 1, 3 do
		local x = 0.02 + (i - 1) * 0.04
		table.insert(parts, fixed(x, ys[i], 0.9, h, edge, 0.17))
		table.insert(parts, fixed(x + bw, ys[i] + bw * 42 / 32, 0.9 - 2 * bw, h - 2 * bw * 42 / 32, cols[i], 0.15))
	end
	table.insert(parts, fixed(0.4, 0.225, 0.22, 0.236, Color3.fromRGB(29, 107, 48), 0.5)) -- coin on the top bill
	SHAPES.Cash = parts
end

SHAPES.Shield = {
	box(0.2, 0.08, 0.6, 0.46, "Ink", 0.22), -- top (rounded)
	box(0.2, 0.3, 0.6, 0.24, "Ink"), -- squares the lower corners
	box(0.29, 0.31, 0.42, 0.42, "Ink", nil, 45), -- point
}

SHAPES.Crosshair = {
	box(0.2, 0.2, 0.6, 0.6, "Ink", 0.5), -- ring
	box(0.28, 0.28, 0.44, 0.44, "Fill", 0.5),
	box(0.46, 0.04, 0.08, 0.26, "Ink"), -- ticks
	box(0.46, 0.7, 0.08, 0.26, "Ink"),
	box(0.04, 0.46, 0.26, 0.08, "Ink"),
	box(0.7, 0.46, 0.26, 0.08, "Ink"),
	box(0.44, 0.44, 0.12, 0.12, "Ink", 0.5), -- dot
}

-- compass arrow (points UP at rotation 0): stem + chevron whose bars pivot about the tip
SHAPES.Arrow = {
	box(0.5 - 0.065, 0.16, 0.13, 0.66, "Ink", 0.46),
	barFrom(0.5, 0.16, 0.13, 0.4, 38),
	barFrom(0.5, 0.16, 0.13, 0.4, -38),
}

SHAPES.Plus = {
	box(0.2, 0.42, 0.6, 0.16, "Ink", 0.31),
	box(0.42, 0.2, 0.16, 0.6, "Ink", 0.31),
}

-- solid-looking chevrons (FredokaOne has no ▲▼ glyphs — risk #5)
SHAPES.Up = { barFrom(0.5, 0.28, 0.17, 0.5, 45), barFrom(0.5, 0.28, 0.17, 0.5, -45) }
SHAPES.Down = { barFrom(0.5, 0.72, 0.17, 0.5, 135), barFrom(0.5, 0.72, 0.17, 0.5, -135) }
SHAPES.Chevron = { barFrom(0.68, 0.5, 0.16, 0.5, 45 + 90), barFrom(0.68, 0.5, 0.16, 0.5, 45) } -- ▸
SHAPES.Close = { -- ✕
	{ x = 0.5, y = 0.5, w = 0.16, h = 0.84, role = "Ink", r = 0.5, rot = 45 },
	{ x = 0.5, y = 0.5, w = 0.16, h = 0.84, role = "Ink", r = 0.5, rot = -45 },
}
SHAPES.Dot = { box(0.2, 0.2, 0.6, 0.6, "Ink", 0.5) }
-- F3 Empire Tax chip: a plain pennant on a pole (2 Frames). Generic on purpose: never a country's flag (CLAUDE.md).
SHAPES.Flag = {
	box(0.2, 0.08, 0.1, 0.84, "Ink", 0.5), -- pole
	box(0.3, 0.12, 0.52, 0.38, "Ink", 0.12), -- cloth
}

local KINDS: { string } = {}
for k in pairs(SHAPES) do
	table.insert(KINDS, k)
end
table.sort(KINDS)
HudIcons.Kinds = KINDS

function HudIcons.Has(kind: string): boolean
	return SHAPES[kind] ~= nil
end

local function colorFor(p: Part, ink: Color3, fill: Color3): Color3
	if p.role == "Fill" then
		return fill
	elseif p.role == "Fixed" and p.color then
		return p.color
	end
	return ink
end

local function corner(parent: Instance, r: number?)
	if r and r > 0 then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(math.min(r, 0.5), 0)
		c.Parent = parent
	end
end

--[[ Build an icon. parent may be nil (parent it yourself). Unknown kinds draw a Dot and warn once. ]]
local warnedKinds: { [string]: boolean } = {}
function HudIcons.Make(kind: string, parent: Instance?, opts: IconOpts?): Frame
	local o: IconOpts = opts or {}
	local shape = SHAPES[kind]
	if not shape then
		if not warnedKinds[kind] then
			warnedKinds[kind] = true
			warn("[HudIcons] unknown icon kind:", kind)
		end
		shape = SHAPES.Dot
	end
	local ink = o.Color or INK_DEFAULT
	local fill = o.Fill or FILL_DEFAULT
	local alpha = o.Transparency or 0
	local base = o.ZIndex or 1

	local root = Instance.new("Frame")
	root.Name = o.Name or ("Icon" .. kind)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = o.Size or UDim2.fromOffset(24, 24)
	root.Position = o.Position or UDim2.fromScale(0, 0)
	root.AnchorPoint = o.AnchorPoint or Vector2.zero
	root.ZIndex = base
	root.LayoutOrder = o.LayoutOrder or 0
	root.Active = false
	root:SetAttribute("HudIcon", kind)

	-- "Arrow" draws into an inner full-size group so SetRotation turns the whole glyph
	local host: Frame = root
	if kind == "Arrow" then
		local rot = Instance.new("Frame")
		rot.Name = "Rot"
		rot.BackgroundTransparency = 1
		rot.BorderSizePixel = 0
		rot.AnchorPoint = Vector2.new(0.5, 0.5)
		rot.Position = UDim2.fromScale(0.5, 0.5)
		rot.Size = UDim2.fromScale(1, 1)
		rot.Rotation = o.Rotation or 0
		rot.ZIndex = base
		rot.Active = false
		rot.Parent = root
		host = rot
	end

	for i, p in ipairs(shape) do
		local f = Instance.new("Frame")
		f.Name = "P" .. i
		f.BorderSizePixel = 0
		f.BackgroundColor3 = colorFor(p, ink, fill)
		f.BackgroundTransparency = alpha
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Rotation = p.rot or 0
		f.ZIndex = base + i
		f.Active = false
		f:SetAttribute("Role", p.role or "Ink")
		corner(f, p.r)
		local clip = p.clip
		if clip then
			-- an axis-aligned clipping frame in box coords; the part is placed in the clip frame's coords
			local c = Instance.new("Frame")
			c.Name = "Clip" .. i
			c.BackgroundTransparency = 1
			c.BorderSizePixel = 0
			c.ClipsDescendants = true
			c.Position = UDim2.fromScale(clip.x, clip.y)
			c.Size = UDim2.fromScale(clip.w, clip.h)
			c.ZIndex = base + i
			c.Active = false
			c.Parent = host
			-- part size is given in box fractions: convert to clip-frame fractions
			f.Size = UDim2.fromScale(p.w / clip.w, p.h / clip.h)
			f.Position = UDim2.fromScale(p.x, p.y)
			f.Parent = c
		else
			f.Size = UDim2.fromScale(p.w, p.h)
			f.Position = UDim2.fromScale(p.x, p.y)
			f.Parent = host
		end
	end

	if parent then
		root.Parent = parent
	end
	return root
end

--[[ Recolour an icon made by Make (ink parts → color; fill parts → fill when given). ]]
function HudIcons.SetColor(icon: Instance, color: Color3, fill: Color3?)
	for _, d in ipairs(icon:GetDescendants()) do
		if d:IsA("Frame") then
			local role = d:GetAttribute("Role")
			if role == "Ink" then
				d.BackgroundColor3 = color
			elseif role == "Fill" and fill then
				d.BackgroundColor3 = fill
			end
		end
	end
end

--[[ "Arrow": point the glyph at a bearing (degrees, clockwise; 0 = up). No-op for other kinds. ]]
function HudIcons.SetRotation(icon: Instance, degrees: number)
	local rot = icon:FindFirstChild("Rot")
	if rot and rot:IsA("GuiObject") then
		rot.Rotation = degrees
	end
end

return HudIcons
