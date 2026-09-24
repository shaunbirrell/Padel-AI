--!strict
--[[
	ProgressPill — the v70 top-centre stack "Progress" component (spec §3.4 item 2), shared by every hold / capture
	bar so they all look the same: one dark pill (HudConfig.TopStack.Progress: 320×44 v), GothamBold title on the
	left, FredokaOne value on the right ("62%", "4m"), an 8 v bar along the bottom.

	Users: TerritoryController (capture — land outposts and the v70 naval outposts alike), BankRaidController (vault
	hold). ShopController's ATM raid hold can use it as well.

	  local pill = ProgressPill.Build(screen, "CaptureProgress")          -- Visible = false, centred on X
	  HudLayout.RegisterTopStack("Capture", pill.Frame, HudConfig.TopStack.Order.Progress, { Space = "Hud" })
	  pill.Title.Text = "CAPTURING RADAR HILL"; pill.Value.Text = "62%"; ProgressPill.SetFraction(pill, 0.62)

	The caller owns Visible (or hands it to HudLayout.BindVisibility) and every colour change; HudLayout owns the
	Frame's Position.Y. Sizes are v (the parent gui carries HudLayout's "MobileScale" UIScale).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HudConfig = require(Shared.Configs.HudConfig)
local UIUtil = require(Shared.Util.UIUtil)

local ProgressPill = {}

export type Pill = {
	Frame: Frame,
	Title: TextLabel,
	Value: TextLabel,
	Track: Frame,
	Fill: Frame,
	Stroke: UIStroke,
}

local CFG = HudConfig.TopStack.Progress
local PAD_X = 12 -- v, title / value / bar inset from the pill's sides
local PAD_TOP = 4 -- v above the title row
local PAD_BOTTOM = 7 -- v under the bar
local VALUE_W = 56 -- v, "100%" / "10m" in the value font
local CORNER = 12

ProgressPill.Colors = {
	Fill = HudConfig.Colors.Positive, -- normal progress (green)
	Contested = CFG.ContestedColor, -- amber: someone else is in the zone
	Warn = HudConfig.Colors.Negative, -- under fire
	Idle = Color3.fromRGB(120, 128, 138), -- cooldown / paused
	Title = HudConfig.Colors.White,
	Value = HudConfig.Colors.Gold,
	Stroke = HudConfig.Colors.PillStroke,
	StrokeTransparency = 0.5,
	Track = Color3.fromRGB(255, 255, 255),
	TrackTransparency = 0.82,
}

--[[ One pill, parented to `parent` (a HUD ScreenGui set up with HudLayout.ApplyScreen). Starts hidden. ]]
function ProgressPill.Build(parent: Instance, name: string): Pill
	local size = CFG.Size
	local textSize = CFG.TextSize

	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.Position = UDim2.new(0.5, 0, 0, HudConfig.TopStack.Top) -- Y is rewritten by HudLayout's top stack
	f.Size = UDim2.fromOffset(size.X, size.Y)
	f.BackgroundColor3 = HudConfig.Colors.PillBg
	f.BackgroundTransparency = HudConfig.Colors.PillBgTransparency
	f.BorderSizePixel = 0
	f.Active = false
	f.Visible = false
	f.ZIndex = 2
	UIUtil.Corner(f, CORNER)
	local stroke = UIUtil.Stroke(f, ProgressPill.Colors.Stroke, 2)
	stroke.Transparency = ProgressPill.Colors.StrokeTransparency

	local rowH = textSize + 4
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(PAD_X, PAD_TOP)
	title.Size = UDim2.new(1, -(PAD_X * 2 + VALUE_W), 0, rowH)
	title.Font = HudConfig.Fonts.Body
	title.TextSize = textSize
	title.TextColor3 = ProgressPill.Colors.Title
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Text = ""
	title.ZIndex = 3
	title.Parent = f

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.BackgroundTransparency = 1
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.new(1, -PAD_X, 0, PAD_TOP)
	value.Size = UDim2.fromOffset(VALUE_W, rowH)
	value.Font = HudConfig.Fonts.Display
	value.TextSize = textSize + 2
	value.TextColor3 = ProgressPill.Colors.Value
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.TextYAlignment = Enum.TextYAlignment.Center
	value.Text = "0%"
	value.ZIndex = 3
	value.Parent = f

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0, 1)
	track.Position = UDim2.new(0, PAD_X, 1, -PAD_BOTTOM)
	track.Size = UDim2.new(1, -PAD_X * 2, 0, CFG.BarH)
	track.BackgroundColor3 = ProgressPill.Colors.Track
	track.BackgroundTransparency = ProgressPill.Colors.TrackTransparency
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.ZIndex = 3
	track.Parent = f
	UIUtil.Corner(track, math.ceil(CFG.BarH / 2))

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = ProgressPill.Colors.Fill
	fill.BorderSizePixel = 0
	fill.ZIndex = 4
	fill.Parent = track
	UIUtil.Corner(fill, math.ceil(CFG.BarH / 2))

	f.Parent = parent
	return {
		Frame = f,
		Title = title,
		Value = value,
		Track = track,
		Fill = fill,
		Stroke = stroke,
	}
end

--[[ Bar fill 0..1 (NaN / nil → 0). ]]
function ProgressPill.SetFraction(pill: Pill, fraction: number?)
	local f = tonumber(fraction) or 0
	if f ~= f then
		f = 0
	end
	pill.Fill.Size = UDim2.fromScale(math.clamp(f, 0, 1), 1)
end

--[[ "62%" from a 0..1 fraction (floored, like the server's capture %). ]]
function ProgressPill.Percent(fraction: number?): string
	local f = tonumber(fraction) or 0
	if f ~= f then
		f = 0
	end
	return string.format("%d%%", math.floor(math.clamp(f, 0, 1) * 100))
end

--[[ Normal look (stroke back to the dark default). ]]
function ProgressPill.ResetStroke(pill: Pill)
	pill.Stroke.Color = ProgressPill.Colors.Stroke
	pill.Stroke.Transparency = ProgressPill.Colors.StrokeTransparency
end

--[[ Coloured edge (contested amber, under-fire red …). ]]
function ProgressPill.AccentStroke(pill: Pill, color: Color3)
	pill.Stroke.Color = color
	pill.Stroke.Transparency = 0
end

return ProgressPill
