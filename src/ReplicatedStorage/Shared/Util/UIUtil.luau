--!strict
--[[
	Shared client UI helpers — consistent UIScale + dark military panel chrome.
	MobileActionBar tiles: large rounded color-coded squares (≥64px touch).
]]

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

	local base = basePx or DEFAULT_BASE
	local minS = minScale or DEFAULT_MIN
	local maxS = maxScale or DEFAULT_MAX

	local function updateScale()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local size = cam.ViewportSize
		scale.Scale = math.clamp(math.min(size.X, size.Y) / base, minS, maxS)
	end

	updateScale()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		updateScale()
		if workspace.CurrentCamera then
			workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
		end
	end)

	return scale
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
	btn.ZIndex = 10
	btn.Parent = parent
	UIUtil.Corner(btn, 16)
	local stroke = UIUtil.Stroke(btn, Color3.fromRGB(255, 255, 255), 1.5)
	stroke.Transparency = 0.45

	-- Glossy top highlight
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.Size = UDim2.new(1, -8, 0, math.floor(size * 0.28))
	gloss.Position = UDim2.fromOffset(4, 4)
	gloss.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	gloss.BackgroundTransparency = 0.72
	gloss.BorderSizePixel = 0
	gloss.ZIndex = 11
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
	icon.ZIndex = 12
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
	label.ZIndex = 12
	label.Parent = btn

	UIUtil.EnsureMinTouch(btn, 64)
	return btn
end

return UIUtil
