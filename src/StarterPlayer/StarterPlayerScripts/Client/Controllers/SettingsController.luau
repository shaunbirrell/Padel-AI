--!strict
--[[
	Lightweight Settings panel — music/SFX local toggles + keybind cheat-sheet.
	Toggle: O key or SETTINGS button (bottom-right).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local UIUtil = require(Shared.Util.UIUtil)

local ClientSettings = require(script.Parent.Parent.Modules.ClientSettings)
local AudioController = require(script.Parent.Parent.Modules.AudioController)

local SettingsController = {}

local player = Players.LocalPlayer
local open = false
local screenGui: ScreenGui? = nil
local musicBtn: TextButton? = nil
local sfxBtn: TextButton? = nil

local KEYBINDS = {
	"B — Base Upgrades",
	"G — Garage (vehicles)",
	"M — Missions / daily",
	"P — Shop (monetization)",
	"K — Progression (BP / clan / war)",
	"A — Army (soldiers)",
	"O — Settings (this panel)",
	"LMB — Fire · R — Reload",
	"Sit VehicleSeat — Drive",
}

local function setOpen(isOpen: boolean)
	open = isOpen
	if screenGui then
		local panel = screenGui:FindFirstChild("Panel")
		if panel and panel:IsA("GuiObject") then
			panel.Visible = isOpen
		end
	end
end

local function refreshToggleLabels()
	if musicBtn then
		musicBtn.Text = if ClientSettings.GetMusicEnabled() then "Music: ON" else "Music: OFF"
		musicBtn.BackgroundColor3 = if ClientSettings.GetMusicEnabled() then Constants.Colors.Accent else Constants.Colors.Background
	end
	if sfxBtn then
		sfxBtn.Text = if ClientSettings.GetSfxEnabled() then "SFX: ON" else "SFX: OFF"
		sfxBtn.BackgroundColor3 = if ClientSettings.GetSfxEnabled() then Constants.Colors.Accent else Constants.Colors.Background
	end
end

function SettingsController.Init()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireSettings"
	screen.Parent = player:WaitForChild("PlayerGui")
	UIUtil.PrepareScreen(screen, false)
	screenGui = screen

	local toggle = Instance.new("TextButton")
	toggle.Name = "SettingsToggle"
	toggle.AnchorPoint = Vector2.new(1, 1)
	toggle.Position = UDim2.new(1, -16, 1, -16)
	toggle.Size = UDim2.fromOffset(96, 44)
	toggle.BackgroundColor3 = Constants.Colors.Panel
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 12
	toggle.TextColor3 = Constants.Colors.Text
	toggle.Text = "SETTINGS"
	toggle.BorderSizePixel = 0
	UIUtil.Corner(toggle, 8)
	UIUtil.Stroke(toggle)
	toggle.Parent = screen
	toggle.MouseButton1Click:Connect(function()
		AudioController.PlayClick()
		setOpen(not open)
	end)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(380, 420)
	panel.BackgroundColor3 = Constants.Colors.Panel
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screen
	UIUtil.Corner(panel, 10)
	UIUtil.Stroke(panel)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -80, 0, 28)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Constants.Colors.Text
	title.Text = "Settings"
	title.Parent = panel

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 10)
	close.Size = UDim2.fromOffset(32, 28)
	close.BackgroundColor3 = Constants.Colors.Background
	close.Font = Enum.Font.GothamBold
	close.Text = "X"
	close.TextColor3 = Constants.Colors.Text
	close.BorderSizePixel = 0
	UIUtil.Corner(close, 6)
	close.Parent = panel
	close.MouseButton1Click:Connect(function()
		AudioController.PlayClick()
		setOpen(false)
	end)

	local audioNote = Instance.new("TextLabel")
	audioNote.BackgroundTransparency = 1
	audioNote.Position = UDim2.fromOffset(16, 48)
	audioNote.Size = UDim2.new(1, -32, 0, 28)
	audioNote.Font = Enum.Font.Gotham
	audioNote.TextSize = 11
	audioNote.TextWrapped = true
	audioNote.TextXAlignment = Enum.TextXAlignment.Left
	audioNote.TextColor3 = Constants.Colors.Muted
	audioNote.Text = "Music / SFX are local-only (session). Toggles mute/unmute AudioController immediately. Placeholder SoundIds — swap in Studio."
	audioNote.Parent = panel

	musicBtn = Instance.new("TextButton")
	musicBtn.Position = UDim2.fromOffset(16, 88)
	musicBtn.Size = UDim2.fromOffset(160, 44)
	musicBtn.Font = Enum.Font.GothamBold
	musicBtn.TextSize = 13
	musicBtn.TextColor3 = Constants.Colors.Text
	musicBtn.BorderSizePixel = 0
	UIUtil.Corner(musicBtn, 6)
	musicBtn.Parent = panel
	musicBtn.MouseButton1Click:Connect(function()
		ClientSettings.ToggleMusic()
		refreshToggleLabels()
		AudioController.PlayClick()
	end)

	sfxBtn = Instance.new("TextButton")
	sfxBtn.Position = UDim2.fromOffset(192, 88)
	sfxBtn.Size = UDim2.fromOffset(160, 44)
	sfxBtn.Font = Enum.Font.GothamBold
	sfxBtn.TextSize = 13
	sfxBtn.TextColor3 = Constants.Colors.Text
	sfxBtn.BorderSizePixel = 0
	UIUtil.Corner(sfxBtn, 6)
	sfxBtn.Parent = panel
	sfxBtn.MouseButton1Click:Connect(function()
		ClientSettings.ToggleSfx()
		refreshToggleLabels()
		AudioController.PlayClick()
	end)

	local bindsTitle = Instance.new("TextLabel")
	bindsTitle.BackgroundTransparency = 1
	bindsTitle.Position = UDim2.fromOffset(16, 136)
	bindsTitle.Size = UDim2.new(1, -32, 0, 22)
	bindsTitle.Font = Enum.Font.GothamBold
	bindsTitle.TextSize = 14
	bindsTitle.TextXAlignment = Enum.TextXAlignment.Left
	bindsTitle.TextColor3 = Constants.Colors.Text
	bindsTitle.Text = "Keybind cheat-sheet"
	bindsTitle.Parent = panel

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(12, 164)
	list.Size = UDim2.new(1, -24, 1, -176)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.Parent = list

	for i, line in ipairs(KEYBINDS) do
		local row = Instance.new("TextLabel")
		row.Size = UDim2.new(1, -8, 0, 22)
		row.BackgroundColor3 = Constants.Colors.Background
		row.BackgroundTransparency = 0.35
		row.BorderSizePixel = 0
		row.Font = Enum.Font.Gotham
		row.TextSize = 12
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = Constants.Colors.Muted
		row.Text = "  " .. line
		row.LayoutOrder = i
		row.Parent = list
		UIUtil.Corner(row, 4)
	end

	refreshToggleLabels()
	ClientSettings.OnChanged(refreshToggleLabels)

	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then
			return
		end
		if input.KeyCode == Enum.KeyCode.O then
			setOpen(not open)
		end
	end)
end

return SettingsController
