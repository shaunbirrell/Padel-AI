--!strict
--[[
	Shared client UI helpers — consistent UIScale + dark military panel chrome.
	MobileActionBar tiles: large rounded color-coded squares (≥64px touch).
	v70 HUD: MakeRailTile / SetTileBadge (left rail), TextOutline, Lighten, MakeModalDim (panel dim).
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local HudConfig = require(script.Parent.Parent.Configs.HudConfig)

local UIUtil = {}

local DEFAULT_BASE = 900
local DEFAULT_MIN = 0.65
local DEFAULT_MAX = 1.1

function UIUtil.Corner(parent: Instance, radius: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

function UIUtil.Stroke(parent: Instance, color: Color3?, thickness: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.fromRGB(55, 65, 55)
	s.Thickness = thickness or 1
	s.Parent = parent
	return s
end

--[[
	MobileScale tracker: ONE ViewportSize connection for every UIScale made by AttachMobileScale (v70 fix: the
	old per-call closures reconnected on every CurrentCamera change and never disconnected). Weak keys, so a
	destroyed gui's UIScale drops out by itself. HudLayout.ApplyScreen takes a scale over with ReleaseMobileScale.
]]
type ScaleParams = { Base: number, Min: number, Max: number }
local trackedScales: { [UIScale]: ScaleParams } = setmetatable({} :: any, { __mode = "k" })
local trackerStarted = false
local trackerCamConn: RBXScriptConnection? = nil

local function scaleValue(p: ScaleParams): number?
	local cam = workspace.CurrentCamera
	if not cam then
		return nil
	end
	local size = cam.ViewportSize
	return math.clamp(math.min(size.X, size.Y) / p.Base, p.Min, p.Max)
end

local function updateTrackedScales()
	for scale, p in pairs(trackedScales) do
		local v = scaleValue(p)
		if v and scale.Scale ~= v then
			scale.Scale = v
		end
	end
end

local function bindTrackerCamera()
	if trackerCamConn then
		trackerCamConn:Disconnect()
		trackerCamConn = nil
	end
	local cam = workspace.CurrentCamera
	if cam then
		trackerCamConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateTrackedScales)
	end
	updateTrackedScales()
end

local function ensureScaleTracker()
	if trackerStarted then
		return
	end
	trackerStarted = true
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindTrackerCamera)
	bindTrackerCamera()
end

--[[
	Attaches a MobileScale UIScale that tracks viewport size.
	Returns the UIScale instance.
]]
function UIUtil.AttachMobileScale(
	screen: ScreenGui,
	basePx: number?,
	minScale: number?,
	maxScale: number?
): UIScale
	local scale = Instance.new("UIScale")
	scale.Name = "MobileScale"
	scale.Parent = screen

	local p: ScaleParams = { Base = basePx or DEFAULT_BASE, Min = minScale or DEFAULT_MIN, Max = maxScale or DEFAULT_MAX }
	trackedScales[scale] = p
	local v = scaleValue(p)
	if v then
		scale.Scale = v
	end
	ensureScaleTracker()

	return scale
end

--[[ Stop AttachMobileScale's tracker from driving this UIScale (HudLayout.ApplyScreen owns it from then on). ]]
function UIUtil.ReleaseMobileScale(scale: UIScale)
	trackedScales[scale] = nil
end

--[[ Standard ScreenGui defaults for WAR EMPIRE panels. ]]
function UIUtil.PrepareScreen(screen: ScreenGui, ignoreInset: boolean?)
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.IgnoreGuiInset = ignoreInset == true
	UIUtil.AttachMobileScale(screen)
end

--[[ Lightweight empty-state label for list panels. ]]
function UIUtil.EmptyState(parent: Instance, message: string, order: number?): TextLabel
	local lab = Instance.new("TextLabel")
	lab.Name = "EmptyState"
	lab.Size = UDim2.new(1, -8, 0, 56)
	lab.BackgroundTransparency = 1
	lab.Font = Enum.Font.Gotham
	lab.TextSize = 13
	lab.TextWrapped = true
	lab.TextXAlignment = Enum.TextXAlignment.Center
	lab.TextYAlignment = Enum.TextYAlignment.Center
	lab.TextColor3 = Color3.fromRGB(140, 150, 140)
	lab.Text = message
	lab.LayoutOrder = order or 0
	lab.Parent = parent
	return lab
end

--[[ Ensure a GuiButton meets mobile min touch (default 64px for advanced HUD). ]]
function UIUtil.EnsureMinTouch(btn: GuiButton, minPx: number?)
	local m = minPx or 64
	local sz = btn.Size
	local w = sz.X.Offset
	local h = sz.Y.Offset
	if w > 0 and w < m then
		btn.Size = UDim2.new(sz.X.Scale, m, sz.Y.Scale, math.max(h, m))
	elseif h > 0 and h < m then
		btn.Size = UDim2.new(sz.X.Scale, math.max(w, m), sz.Y.Scale, m)
	end
end

function UIUtil.GoldStroke(parent: Instance, thickness: number?): UIStroke
	return UIUtil.Stroke(parent, Color3.fromRGB(230, 190, 60), thickness or 1.5)
end

--[[
	Large rounded glossy action tile for mobile dock.
	icon: short emoji/symbol string; label: caption under icon.
]]
function UIUtil.MakeActionTile(
	parent: Instance,
	props: {
		Name: string,
		Icon: string,
		Label: string,
		Color: Color3,
		LayoutOrder: number?,
		SizePx: number?,
	}
): TextButton
	local size = props.SizePx or 72
	local btn = Instance.new("TextButton")
	btn.Name = props.Name
	btn.Size = UDim2.fromOffset(size, size)
	btn.BackgroundColor3 = props.Color
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true
	btn.Text = ""
	btn.LayoutOrder = props.LayoutOrder or 0
	btn.ZIndex = 20
	btn.Active = true
	btn.Selectable = true
	btn.Parent = parent
	UIUtil.Corner(btn, 16)
	local stroke = UIUtil.Stroke(btn, Color3.fromRGB(255, 255, 255), 1.5)
	stroke.Transparency = 0.45

	-- Glossy top highlight — Active=false so it never steals Activated/clicks
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.Size = UDim2.new(1, -8, 0, math.floor(size * 0.28))
	gloss.Position = UDim2.fromOffset(4, 4)
	gloss.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	gloss.BackgroundTransparency = 0.72
	gloss.BorderSizePixel = 0
	gloss.ZIndex = 21
	gloss.Active = false
	gloss.Parent = btn
	UIUtil.Corner(gloss, 10)

	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.new(1, 0, 0, math.floor(size * 0.48))
	icon.Position = UDim2.fromOffset(0, 6)
	icon.Font = Enum.Font.GothamBold
	icon.TextSize = math.floor(size * 0.36)
	icon.TextColor3 = Color3.fromRGB(255, 255, 255)
	icon.Text = props.Icon
	icon.ZIndex = 22
	icon.Active = false
	icon.Parent = btn

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -4, 0, 16)
	label.Position = UDim2.new(0, 2, 1, -20)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 11
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.5
	label.Text = props.Label
	label.ZIndex = 22
	label.Active = false
	label.Parent = btn

	UIUtil.EnsureMinTouch(btn, 64)
	return btn
end

---------------------------------------------------------------------------------------------------------------
-- v70 HUD helpers (HudConfig-driven)
---------------------------------------------------------------------------------------------------------------

--[[ Mix a colour toward white by t (0..1). ]]
function UIUtil.Lighten(c: Color3, t: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), math.clamp(t, 0, 1))
end

--[[ Glyph outline (UIStroke, Contextual) — the v70 "plain outlined text" look. Default HudConfig.Colors.Ink. ]]
function UIUtil.TextOutline(label: GuiObject, thickness: number?, color: Color3?, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Color = color or HudConfig.Colors.Ink
	s.Thickness = thickness or 2
	s.Transparency = transparency or 0
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = label
	return s
end

export type RailTileProps = {
	Name: string, -- MobileActionBar child name (pinned: "DockShop", "DockMissions" ...)
	Label: string, -- "Shop"
	Accent: Color3,
	Fill: Color3,
	Icon: string?, -- HudIcons kind (kept as the attribute "Icon")
	-- draws the icon into IconSlot (60 % of the tile, centred in its top 78 %). HUDController passes
	-- function(slot, ink, fill) HudIcons.Make(kind, slot, {Size = UDim2.fromScale(1, 1), Color = ink, Fill = fill}) end
	IconBuilder: ((slot: Frame, ink: Color3, fill: Color3) -> ())?,
	LayoutOrder: number?,
	Touch: boolean?, -- touch sizes (HudConfig.Rail.Tile …); default UserInputService.TouchEnabled
}

local function circle(parent: Instance, name: string, size: number, color: Color3, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromOffset(size, size)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = z
	f.Active = false
	f.Parent = parent
	UIUtil.Corner(f, math.ceil(size / 2))
	return f
end

--[[
	v70 left-rail cell (HudConfig.Rail). ONE TextButton of T × (T + LabelOverhang) v, so the hit area includes
	the label (64 x 70 v touch = 44.8 x 49 real px on phones). Children:
	  Group (press UIScale "Press") › Outline (1.5 v Ink) + Tile (Accent ring = StrokePx edge)
	    Tile › Face (Fill lightened 16 % → Fill gradient), IconSlot, Badge (hidden; see SetTileBadge)
	  Label — FredokaOne, white, 2 px Ink outline, straddling the tile's bottom edge
	The caller wires btn.Activated (pinned) — this helper only adds the visual press feedback.
	-- dock≤8: rail gap 5/8 v (HudConfig.Rail.Gap / GapDesktop)
]]
function UIUtil.MakeRailTile(parent: Instance?, props: RailTileProps): TextButton
	local R = HudConfig.Rail
	local touch = if props.Touch == nil then UserInputService.TouchEnabled else props.Touch == true
	local T = if touch then R.Tile else R.TileDesktop
	local ov = if touch then R.LabelOverhang else R.LabelOverhangDesktop
	local L = if touch then R.LabelSize else R.LabelSizeDesktop
	local edge = R.StrokePx
	local ink = HudConfig.Colors.Ink

	local btn = Instance.new("TextButton")
	btn.Name = props.Name
	btn.Size = UDim2.fromOffset(T, T + ov)
	btn.BackgroundTransparency = 1
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.LayoutOrder = props.LayoutOrder or 0
	btn.Active = true
	btn.Selectable = true
	btn.ZIndex = 20
	btn:SetAttribute("RailTile", true)
	if props.Icon then
		btn:SetAttribute("Icon", props.Icon)
	end

	local group = Instance.new("Frame")
	group.Name = "Group"
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.new(0.5, 0, 0, T / 2)
	group.Size = UDim2.fromOffset(T, T)
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	group.ZIndex = 20
	group.Active = false
	group.Parent = btn
	local press = Instance.new("UIScale")
	press.Name = "Press"
	press.Parent = group

	local outline = Instance.new("Frame")
	outline.Name = "Outline"
	outline.AnchorPoint = Vector2.new(0.5, 0.5)
	outline.Position = UDim2.fromScale(0.5, 0.5)
	outline.Size = UDim2.new(1, 3, 1, 3)
	outline.BackgroundColor3 = ink
	outline.BackgroundTransparency = 0.45
	outline.BorderSizePixel = 0
	outline.ZIndex = 20
	outline.Active = false
	outline.Parent = group
	UIUtil.Corner(outline, R.Corner + 1.5)

	local tile = Instance.new("Frame")
	tile.Name = "Tile"
	tile.AnchorPoint = Vector2.new(0.5, 0.5)
	tile.Position = UDim2.fromScale(0.5, 0.5)
	tile.Size = UDim2.fromScale(1, 1)
	tile.BackgroundColor3 = props.Accent
	tile.BorderSizePixel = 0
	tile.ZIndex = 21
	tile.Active = false
	tile.Parent = group
	UIUtil.Corner(tile, R.Corner)

	local top = UIUtil.Lighten(props.Fill, 0.16)
	local face = Instance.new("Frame")
	face.Name = "Face"
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.fromScale(0.5, 0.5)
	face.Size = UDim2.new(1, -2 * edge, 1, -2 * edge)
	face.BackgroundColor3 = top
	face.BorderSizePixel = 0
	face.ZIndex = 22
	face.Active = false
	face.Parent = tile
	UIUtil.Corner(face, math.max(0, R.Corner - edge))
	-- UIGradient multiplies: top colour × 1 → Fill at the bottom (per-channel ratio)
	local function ratio(a: number, b: number): number
		return if b > 0 then math.clamp(a / b, 0, 1) else 1
	end
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(
		Color3.new(1, 1, 1),
		Color3.new(ratio(props.Fill.R, top.R), ratio(props.Fill.G, top.G), ratio(props.Fill.B, top.B))
	)
	grad.Parent = face

	local slot = Instance.new("Frame")
	slot.Name = "IconSlot"
	slot.AnchorPoint = Vector2.new(0.5, 0.5)
	slot.Position = UDim2.fromScale(0.5, 0.39)
	slot.Size = UDim2.fromScale(R.IconScale, R.IconScale)
	slot.BackgroundTransparency = 1
	slot.BorderSizePixel = 0
	slot.ZIndex = 23
	slot.Active = false
	slot.Parent = tile
	if props.IconBuilder then
		-- the face colour behind the icon's centre (gradient at 39 %)
		local behind = props.Fill:Lerp(top, 1 - 0.39)
		local build = props.IconBuilder
		local ok, err = pcall(function(): string?
			build(slot, UIUtil.Lighten(props.Accent, 0.12), behind)
			return nil
		end)
		if not ok then
			warn("[UIUtil] rail icon failed:", props.Name, err)
		end
	end

	local B = R.Badge
	local badge = circle(tile, "Badge", B.Size + 4, ink, 30)
	badge.Position = UDim2.new(1, -4, 0, 4)
	badge.Visible = false
	local dot = circle(badge, "Dot", B.Size, B.Bg, 31)
	local btext = Instance.new("TextLabel")
	btext.Name = "Text"
	btext.BackgroundTransparency = 1
	btext.Size = UDim2.fromScale(1, 1)
	btext.Font = HudConfig.Fonts.Display
	btext.TextSize = B.TextSize
	btext.TextColor3 = HudConfig.Colors.White
	btext.Text = ""
	btext.ZIndex = 32
	btext.Active = false
	btext.Parent = dot
	local badgeScale = Instance.new("UIScale")
	badgeScale.Name = "Pop"
	badgeScale.Parent = badge

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 1, -(ov + 0.62 * L))
	label.Size = UDim2.new(1, 32, 0, L)
	label.Font = HudConfig.Fonts.Display
	label.TextSize = L
	label.TextColor3 = HudConfig.Colors.White
	label.Text = props.Label
	label.ZIndex = 25
	label.Active = false
	label.Parent = btn
	UIUtil.TextOutline(label, R.LabelStroke)

	btn.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			press.Scale = R.PressScale
		end
	end)
	local function release()
		if press.Scale ~= 1 then
			TweenService:Create(press, TweenInfo.new(0.06), { Scale = 1 }):Play()
		end
	end
	btn.InputEnded:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			release()
		end
	end)
	btn.MouseLeave:Connect(release)

	if parent then
		btn.Parent = parent
	end
	return btn
end

--[[ Rail badge on a MakeRailTile button: "!" = gold ready style, a count = red, nil / "" / "0" hides.
	Pops once (UIScale 1 → 1.2 → 1) when it appears. ]]
function UIUtil.SetTileBadge(tileButton: Instance, text: string?)
	local badge = tileButton:FindFirstChild("Badge", true)
	if not (badge and badge:IsA("GuiObject")) then
		return
	end
	local show = text ~= nil and text ~= "" and text ~= "0"
	local was = badge.Visible
	badge.Visible = show
	if not show or text == nil then
		return
	end
	local B = HudConfig.Rail.Badge
	local ready = text == "!"
	local dot = badge:FindFirstChild("Dot")
	if dot and dot:IsA("GuiObject") then
		dot.BackgroundColor3 = if ready then B.ReadyBg else B.Bg
		local lab = dot:FindFirstChild("Text")
		if lab and lab:IsA("TextLabel") then
			lab.Text = text
			lab.TextColor3 = if ready then B.ReadyText else HudConfig.Colors.White
		end
	end
	if not was and B.PulseWhenNew then
		local pop = badge:FindFirstChild("Pop")
		if pop and pop:IsA("UIScale") then
			pop.Scale = 1
			TweenService:Create(pop, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), { Scale = 1.2 }):Play()
		end
	end
end

--[[
	Black dim behind an open panel (HudConfig.Context.ModalDim = its BackgroundTransparency). Put it in the
	panel's own ScreenGui; it is created as the lowest layer and oversized so it covers the whole gui area.
	Active = false (the world still gets the input); on a tap/click OUTSIDE `panel` (when given) it calls onTap.
	Returns the existing "ModalDim" when there is one. Toggle .Visible with the panel.
]]
function UIUtil.MakeModalDim(screen: Instance, onTap: (() -> ())?, panel: GuiObject?): Frame
	local existing = screen:FindFirstChild("ModalDim")
	if existing and existing:IsA("Frame") then
		return existing
	end
	local dim = Instance.new("Frame")
	dim.Name = "ModalDim"
	dim.AnchorPoint = Vector2.new(0.5, 0.5)
	dim.Position = UDim2.fromScale(0.5, 0.5)
	dim.Size = UDim2.fromScale(3, 3)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = HudConfig.Context.ModalDim
	dim.BorderSizePixel = 0
	dim.ZIndex = 0
	dim.LayoutOrder = -1000
	dim.Active = false
	dim.Parent = screen
	if onTap then
		local cb: () -> () = onTap
		dim.InputBegan:Connect(function(input: InputObject)
			local t = input.UserInputType
			if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then
				return
			end
			if panel and panel.Visible then
				local p = Vector2.new(input.Position.X, input.Position.Y)
				local a, s = panel.AbsolutePosition, panel.AbsoluteSize
				if p.X >= a.X and p.X <= a.X + s.X and p.Y >= a.Y and p.Y <= a.Y + s.Y then
					return
				end
			end
			cb()
		end)
	end
	return dim
end

return UIUtil
