--!strict
--[[
	PanelShell — v70 "clean screen" chrome for the full-screen panels and the Army popover (spec §3.8).
	Used by Shop, Rebirth (Progression), Missions, Army, Garage, Settings, Base and the Army popover (Orders).

	  PanelShell.Screen(screen, displayOrder?)   HudLayout.ApplyScreen: Core safe insets + the ONE HUD UIScale
	                                             ("MobileScale", S = 0.70 on phones … 1.15 at 1080p)
	  PanelShell.Attach({Id, Screen, Panel, IsOpen, Close, Dim?, TapCloses?}) -> Shell
	      * HudLayout.RegisterPanel(Id, IsOpen, Close): one panel open at a time → the Modal flag
	      * the black dim behind the panel (UIUtil.MakeModalDim, HudConfig.Context.ModalDim; Active = false).
	        It covers the whole screen width of the gui plus the Roblox topbar row, so the HUD (rail, pill,
	        TopStrip) stays visible but dimmed under the panel. On touch a tap outside the panel closes it.
	      * Dim = false → an invisible tap-catcher instead (the Army popover).
	  shell.Sync(open)        call from the panel's setOpen: dim visibility + HudLayout.PanelOpened / PanelClosed
	  shell.TapThrough()      true for a moment after the dim closed the panel: the same tap then lands on the rail
	                          tile that toggles it, and Toggle must not re-open it
	  PanelShell.Tap(v)       a touch target in v: ≥ TouchMinV() (64 v = 44.8 real px at the phone scale 0.70)
	  PanelShell.Text(v)      a text size in v: ≥ 16 v on touch (11.2 px) / 13 v on desktop
	  PanelShell.CloseButton(parent, onClose)    ✕ from HudIcons "Close"; 64 v hit on touch, 44 v on desktop

	Nothing here touches a purchase path.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HudConfig = require(Shared.Configs.HudConfig)
local UIUtil = require(Shared.Util.UIUtil)

local HudLayout = require(script.Parent.HudLayout)
local HudIcons = require(script.Parent.HudIcons)

local PanelShell = {}

-- 64 v: the rail tile / hotbar slot size, = HudConfig.Scale.TouchMinPx (44) / Scale.Min (0.70) rounded up
local TOUCH_MIN_V = math.max(HudConfig.Hotbar.Slot, math.ceil(HudConfig.Scale.TouchMinPx / HudConfig.Scale.Min))
local DESKTOP_MIN_V = 44
local TEXT_MIN_TOUCH = math.ceil(HudConfig.Scale.MinTextPx / HudConfig.Scale.Min) -- 16 v = 11.2 px on phones
local TEXT_MIN_DESKTOP = 13 -- 11.7 px at 720p (S 0.90)
local TAP_THROUGH_SECONDS = 0.45

PanelShell.Colors = {
	Panel = Color3.fromRGB(24, 27, 31),
	PanelStroke = Color3.fromRGB(70, 78, 70),
	Row = Color3.fromRGB(34, 38, 44),
	CloseFace = Color3.fromRGB(44, 48, 54),
	Title = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(190, 196, 204),
}

export type Shell = {
	Id: string,
	Dim: Frame,
	Sync: (open: boolean) -> (),
	TapThrough: () -> boolean,
	Refit: () -> (),
}

export type AttachOpts = {
	Id: string, -- HudLayout panel id ("Shop", "Rebirth", "Missions", "Army", "Orders", "Garage", "Settings", "Base")
	Screen: ScreenGui,
	Panel: GuiObject?, -- taps inside it never close the panel
	IsOpen: () -> boolean,
	Close: () -> (),
	Dim: boolean?, -- default true; false = invisible tap-catcher (popover)
	TapCloses: boolean?, -- default: touch only (spec §3.8)
}

function PanelShell.IsTouch(): boolean
	return HudLayout.IsTouch()
end

function PanelShell.TouchMinV(): number
	return if HudLayout.IsTouch() then TOUCH_MIN_V else DESKTOP_MIN_V
end

--[[ A tappable's size in v: at least TouchMinV(). ]]
function PanelShell.Tap(v: number): number
	return math.max(v, PanelShell.TouchMinV())
end

--[[ A text size in v that renders ≥ 11 real px at the smallest HUD scale of the device class. ]]
function PanelShell.Text(v: number): number
	return math.max(v, if HudLayout.IsTouch() then TEXT_MIN_TOUCH else TEXT_MIN_DESKTOP)
end

--[[ The only way a panel ScreenGui is set up (HudLayout.ApplyScreen, Core insets, DisplayOrder Panels = 60). ]]
function PanelShell.Screen(screen: ScreenGui, displayOrder: number?): UIScale?
	return HudLayout.ApplyScreen(screen, {
		DisplayOrder = displayOrder or HudConfig.DisplayOrder.Panels,
		Insets = "Core",
	})
end

-- the dim covers the gui's safe area plus the Roblox topbar row above it (the notch bands are clipped by
-- ClipToDeviceSafeArea anyway). Offsets are in v (the gui's UIScale), Scale parts track the real screen.
local function fitDim(screen: ScreenGui, dim: Frame)
	local cam = Workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.zero
	local abs = screen.AbsoluteSize
	if vp.Y < 2 or abs.Y < 2 then
		return -- not laid out yet: keep MakeModalDim's oversize
	end
	local s = HudLayout.Scale()
	if s <= 0 then
		s = 1
	end
	local top = math.max(0, vp.Y - abs.Y) / s
	dim.AnchorPoint = Vector2.zero
	dim.Position = UDim2.fromOffset(0, -top)
	dim.Size = UDim2.new(1, 0, 1, top)
end

--[[ Register the panel with HudLayout and add its dim. Call once in Init, after the ScreenGui is parented. ]]
function PanelShell.Attach(o: AttachOpts): Shell
	local closedByTapAt = -math.huge
	local dim = UIUtil.MakeModalDim(o.Screen, function()
		local closes = if o.TapCloses == nil then HudLayout.IsTouch() else o.TapCloses == true
		if not closes then
			return
		end
		local ok, open = pcall(o.IsOpen)
		if not (ok and open == true) then
			return
		end
		closedByTapAt = os.clock()
		o.Close()
	end, o.Panel)
	dim.Visible = false
	if o.Dim == false then
		dim.BackgroundTransparency = 1
	end
	local function refit()
		fitDim(o.Screen, dim)
	end
	refit()
	HudLayout.LayoutChanged:Connect(refit)
	o.Screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)

	HudLayout.RegisterPanel(o.Id, o.IsOpen, o.Close)

	local shell: Shell = {
		Id = o.Id,
		Dim = dim,
		Sync = function(open: boolean)
			dim.Visible = open
			if open then
				refit()
				HudLayout.PanelOpened(o.Id)
			else
				HudLayout.PanelClosed(o.Id)
			end
		end,
		TapThrough = function(): boolean
			return os.clock() - closedByTapAt < TAP_THROUGH_SECONDS
		end,
		Refit = refit,
	}
	return shell
end

export type CloseOpts = {
	Position: UDim2?,
	AnchorPoint: Vector2?,
	ZIndex: number?,
	Face: Color3?,
}

--[[ ✕ close button: a transparent TouchMinV() square hit area around a rounded face with the HudIcons "Close".
	Default placement: the parent's top-right corner (AnchorPoint (1, 0), Position (1, -4, 0, 4)). ]]
function PanelShell.CloseButton(parent: Instance, onClose: () -> (), opts: CloseOpts?): TextButton
	local o: CloseOpts = opts or {}
	local hit = PanelShell.TouchMinV()
	local z = o.ZIndex or 5
	local btn = Instance.new("TextButton")
	btn.Name = "Close"
	btn.AnchorPoint = o.AnchorPoint or Vector2.new(1, 0)
	btn.Position = o.Position or UDim2.new(1, -4, 0, 4)
	btn.Size = UDim2.fromOffset(hit, hit)
	btn.BackgroundTransparency = 1
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Text = ""
	btn.Active = true
	btn.ZIndex = z
	local faceColor = o.Face or PanelShell.Colors.CloseFace
	local face = Instance.new("Frame")
	face.Name = "Face"
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.fromScale(0.5, 0.5)
	face.Size = UDim2.fromScale(0.66, 0.66)
	face.BackgroundColor3 = faceColor
	face.BorderSizePixel = 0
	face.Active = false
	face.ZIndex = z
	face.Parent = btn
	UIUtil.Corner(face, 10)
	local st = UIUtil.Stroke(face, Color3.fromRGB(255, 255, 255), 1.5)
	st.Transparency = 0.7
	HudIcons.Make("Close", face, {
		Size = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = z + 1,
		Color = Color3.fromRGB(255, 255, 255),
		Fill = faceColor,
	})
	btn.Activated:Connect(onClose)
	btn.Parent = parent
	return btn
end

--[[ Title label in the HUD's display font (FredokaOne) with the Ink outline. ]]
function PanelShell.Title(parent: Instance, text: string, size: number?): TextLabel
	local ts = PanelShell.Text(size or 24)
	local t = Instance.new("TextLabel")
	t.Name = "Title"
	t.BackgroundTransparency = 1
	t.Font = HudConfig.Fonts.Display
	t.TextSize = ts
	t.TextColor3 = PanelShell.Colors.Title
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.Text = text
	t.Size = UDim2.new(1, -(PanelShell.TouchMinV() + 24), 0, ts + 8)
	t.Position = UDim2.fromOffset(16, 10)
	t.Parent = parent
	UIUtil.TextOutline(t, 1.5)
	return t
end

return PanelShell
