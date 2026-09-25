--!strict
--[[
	CompassController — v70 compass chip in the TopStrip (spec §3.1; HudConfig.TopStrip.Compass).
	A gold Frame-built arrow that points at your base relative to the camera, "BASE" and the distance ("95m",
	"1.2km"), right-aligned in the Roblox topbar row. Shown only OUTSIDE your own plot — this controller publishes
	the HudLayout flag "InOwnPlot" (plot square + OwnPlotMarginStuds) — and hidden while a panel is open.
	Tap → HudLayout.Signals.CompassTapped (TerritoryController opens the territory list under the chip).
	RadarReveal (flag "Radar", TerritoryController) → a pulsing purple dot at the chip's left edge.
	Gone: the 210x52 two-line card under the weapon panel and its "◎ nearest territory" line.
	W3 step 2 lane U0 — TRACKED MODE: while the one objective marker (Modules/ObjectiveMarker, set by a mission GO)
	has a target, the chip points at IT instead of your base: the label reads the target's short name ("BANK", in
	gold), the arrow and distance follow the target, and the chip also shows inside your own plot (GO is usually
	tapped at home). It still hides while a panel is open. Arrival / Clear / timeout → back to BASE. The chip reads
	ObjectiveMarker.Revision() each tick and copies the target only when it changed (no per-tick allocation).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60) -- ships with the place (Rojo); bounded wait anyway
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local BaseConfig = require(Shared.Configs.BaseConfig)
local HudConfig = require(Shared.Configs.HudConfig)
local UIUtil = require(Shared.Util.UIUtil)
local HudLayout = require(script.Parent.Parent.Modules.HudLayout)
local HudIcons = require(script.Parent.Parent.Modules.HudIcons)
local HUDController = require(script.Parent.HUDController)
local ObjectiveMarker = require(script.Parent.Parent.Modules.ObjectiveMarker)

local CompassController = {}

local TS = HudConfig.TopStrip
local C = TS.Compass

local player = Players.LocalPlayer
local myPlotId: number? = nil
local chip: TextButton? = nil
local arrow: Frame? = nil
local distLabel: TextLabel? = nil
local baseLabel: TextLabel? = nil
local baseKnown = false
local accum = 0

-- tracked mode (ObjectiveMarker): the target copied when ObjectiveMarker.Revision() changes
local tracked: ObjectiveMarker.Target? = nil
local trackedRev = -1
local HIDE_BASE = if C.HideInsideOwnPlot then { "InOwnPlot", "Modal" } else { "Modal" }
local HIDE_TRACKED = { "Modal" }

local function formatDist(studs: number): string
	if studs < 1000 then
		return string.format("%dm", math.floor(studs))
	end
	return string.format("%.1fkm", studs / 1000)
end

local function getRoot(): (Vector3?, Vector3?)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return nil, nil
	end
	local cam = Workspace.CurrentCamera
	local look = if cam then cam.CFrame.LookVector else hrp.CFrame.LookVector
	return hrp.Position, look
end

local function baseWorldPos(): Vector3?
	if typeof(myPlotId) ~= "number" then
		return nil
	end
	return BaseConfig.PlotPositions[myPlotId]
end

-- inside your own plot square (BaseConfig.PlotSize centred on the plot position) + the configured margin
local function insideOwnPlot(pos: Vector3, center: Vector3): boolean
	local size = BaseConfig.PlotSize
	local m = C.OwnPlotMarginStuds
	return math.abs(pos.X - center.X) <= size.X / 2 + m and math.abs(pos.Z - center.Z) <= size.Z / 2 + m
end

-- bearing of `to` relative to the camera look, degrees clockwise (0 = straight ahead = arrow up)
local function relativeBearing(from: Vector3, to: Vector3, look: Vector3): number
	local dx, dz = to.X - from.X, to.Z - from.Z
	if dx * dx + dz * dz < 1e-4 then
		return 0
	end
	local lx, lz = look.X, look.Z
	if lx * lx + lz * lz < 0.0025 then
		lx, lz = 0, -1
	end
	local worldAngle = math.deg(math.atan2(dx, -dz))
	local lookAngle = math.deg(math.atan2(lx, -lz))
	return (worldAngle - lookAngle) % 360
end

local function setKnown(known: boolean)
	if known == baseKnown then
		return
	end
	baseKnown = known
	if chip then
		HudLayout.RefreshVisibility(chip)
	end
end

-- visible: base mode needs the base position and hides inside your own plot; tracked mode needs neither
local function chipVisible(): boolean
	return tracked ~= nil or baseKnown
end

local function bindChip()
	local c = chip
	if c then
		HudLayout.BindVisibility(c, { HideWhen = if tracked ~= nil then HIDE_TRACKED else HIDE_BASE }, chipVisible)
	end
end

-- re-read the objective only when ObjectiveMarker changed it; switch the label and the visibility rule
local function syncTracked()
	local rev = ObjectiveMarker.Revision()
	if rev == trackedRev then
		return
	end
	trackedRev = rev
	local was = tracked ~= nil
	tracked = ObjectiveMarker.Current()
	local t = tracked
	local bl = baseLabel
	if bl then
		bl.Text = if t then t.Short else "BASE"
		bl.TextColor3 = if t then C.ArrowColor else HudConfig.Colors.White
	end
	if was ~= (t ~= nil) then
		bindChip()
	end
	local dl = distLabel
	if dl then
		dl.Text = "…" -- until this tick's distance
	end
end

local function tickCompass()
	syncTracked()
	local pos, look = getRoot()
	local center = baseWorldPos()
	local t = tracked
	if t then
		-- tracked: keep publishing InOwnPlot for the rest of the HUD, then point at the objective
		if not center then
			setKnown(false)
		elseif pos then
			HudLayout.SetFlag("InOwnPlot", insideOwnPlot(pos, center))
			setKnown(true)
		end
		if not pos or not look then
			return -- respawning: keep the last state
		end
		local target = Vector3.new(t.X, pos.Y, t.Z)
		if arrow then
			HudIcons.SetRotation(arrow, relativeBearing(pos, target, look))
		end
		if distLabel then
			distLabel.Text = formatDist(Vector3.new(t.X - pos.X, 0, t.Z - pos.Z).Magnitude)
		end
		return
	end
	if not center then
		setKnown(false)
		return
	end
	if not pos or not look then
		return -- respawning: keep the last state
	end
	local inPlot = insideOwnPlot(pos, center)
	HudLayout.SetFlag("InOwnPlot", inPlot)
	setKnown(true)
	if inPlot and C.HideInsideOwnPlot then
		return
	end
	if arrow then
		HudIcons.SetRotation(arrow, relativeBearing(pos, center, look))
	end
	if distLabel then
		distLabel.Text = formatDist(Vector3.new(center.X - pos.X, 0, center.Z - pos.Z).Magnitude)
	end
end

local function buildChip(area: Frame)
	local c = Instance.new("TextButton")
	c.Name = "Compass"
	c.AnchorPoint = Vector2.new(1, 1)
	c.Position = UDim2.new(1, -TS.EdgePad, 1, -TS.BottomPad + TS.YNudge)
	c.Size = UDim2.fromOffset(C.MinWidth, TS.Height)
	c.AutomaticSize = Enum.AutomaticSize.X
	c.BackgroundColor3 = TS.Bg
	c.BackgroundTransparency = TS.BgTransparency
	c.BorderSizePixel = 0
	c.AutoButtonColor = false
	c.Text = ""
	c.Active = true
	c.Selectable = true
	UIUtil.Corner(c, TS.Corner)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = c
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 7)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = c

	local box = Instance.new("Frame")
	box.Name = "ArrowBox"
	box.LayoutOrder = 1
	box.Size = UDim2.fromOffset(C.ArrowBox, C.ArrowBox)
	box.BackgroundColor3 = Color3.new(1, 1, 1)
	box.BackgroundTransparency = 0.88
	box.BorderSizePixel = 0
	box.Active = false
	box.Parent = c
	UIUtil.Corner(box, math.ceil(C.ArrowBox / 2))
	arrow = HudIcons.Make("Arrow", box, {
		Name = "Arrow",
		Size = UDim2.fromOffset(C.ArrowSize, C.ArrowSize),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = C.ArrowColor,
		ZIndex = 2,
	})

	-- RadarReveal: 8 px pulsing purple dot at the chip's left edge (TerritoryController sets the "Radar" flag)
	local dot = Instance.new("Frame")
	dot.Name = "RadarDot"
	dot.AnchorPoint = Vector2.new(1, 0.5)
	dot.Position = UDim2.new(0, -1, 0.5, 0)
	dot.Size = UDim2.fromOffset(8, 8)
	dot.BackgroundColor3 = C.RadarDot
	dot.BorderSizePixel = 0
	dot.Active = false
	dot.ZIndex = 3
	dot.Parent = box
	UIUtil.Corner(dot, 4)
	HudLayout.BindVisibility(dot, { ShowWhen = { "Radar" } })
	local pulse: Tween? = nil
	local function syncPulse()
		local on = HudLayout.GetFlag("Radar")
		if on and not pulse then
			dot.BackgroundTransparency = 0
			pulse = TweenService:Create(dot, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.7 })
			if pulse then
				pulse:Play()
			end
		elseif not on and pulse then
			pulse:Cancel()
			pulse = nil
			dot.BackgroundTransparency = 0
		end
	end
	HudLayout.FlagChanged:Connect(function(name: string)
		if name == "Radar" then
			syncPulse()
		end
	end)
	syncPulse()

	local base = Instance.new("TextLabel")
	base.Name = "BaseLabel"
	base.LayoutOrder = 2
	base.BackgroundTransparency = 1
	base.Size = UDim2.new(0, 0, 1, 0)
	base.AutomaticSize = Enum.AutomaticSize.X
	base.Font = HudConfig.Fonts.Body
	base.TextSize = C.LabelSize
	base.TextColor3 = HudConfig.Colors.White
	base.TextTransparency = 0.15
	base.Text = "BASE"
	base.Active = false
	base.Parent = c
	baseLabel = base

	local dist = Instance.new("TextLabel")
	dist.Name = "Distance"
	dist.LayoutOrder = 3
	dist.BackgroundTransparency = 1
	dist.Size = UDim2.new(0, 0, 1, 0)
	dist.AutomaticSize = Enum.AutomaticSize.X
	dist.Font = HudConfig.Fonts.Display
	dist.TextSize = C.DistanceSize
	dist.TextColor3 = HudConfig.Colors.White
	dist.Text = "…"
	dist.Active = false
	dist.Parent = c
	UIUtil.TextOutline(dist, TS.TextStroke)
	distLabel = dist

	c.Activated:Connect(function()
		if C.TapOpensTerritories then
			HudLayout.Emit("CompassTapped")
		end
	end)
	c.Parent = area
	chip = c
	bindChip()
	HudLayout.SetRect("Compass", c)
end

function CompassController.Init()
	local area = HUDController.GetTopStripArea()
	if area then
		buildChip(area)
	else
		warn("[CompassController] no TopStrip area — compass chip skipped")
	end

	-- plot id: BindEvent (never an infinite WaitForChild on a remote)
	Remotes.BindEvent(Constants.RemoteNames.BaseStateUpdate, function(basePayload: Types.BaseStatePayload)
		if typeof(basePayload) == "table" and typeof(basePayload.PlotId) == "number" then
			myPlotId = basePayload.PlotId
		end
	end)
	Remotes.BindEvent(Constants.RemoteNames.PlayerStateUpdate, function(state: Types.PlayerStatePayload)
		if typeof(state) == "table" and state.Base and typeof(state.Base.PlotId) == "number" then
			myPlotId = state.Base.PlotId
		end
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		accum += dt
		if accum >= C.TickSeconds then
			accum = 0
			tickCompass()
		end
	end)
end

return CompassController
