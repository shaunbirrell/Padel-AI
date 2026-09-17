--!strict
--[[
	Shared client UI helpers — consistent UIScale + dark military panel chrome.
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

return UIUtil
