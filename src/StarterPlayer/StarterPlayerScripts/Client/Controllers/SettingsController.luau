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
local Remotes = require(Shared.Remotes)
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
	"Codes — Settings redeem row",
	"Spinner — HUD / Settings free reward",
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
	screen.DisplayOrder = 60 -- above HUD dock (55); panels must not open behind HUD
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
	toggle.Visible = false -- docked in HUD MobileActionBar
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
	panel.Size = UDim2.fromOffset(400, 560)
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

	-- Promo codes (server-validated, once each)
	local codesTitle = Instance.new("TextLabel")
	codesTitle.BackgroundTransparency = 1
	codesTitle.Position = UDim2.fromOffset(16, 140)
	codesTitle.Size = UDim2.new(1, -32, 0, 20)
	codesTitle.Font = Enum.Font.GothamBold
	codesTitle.TextSize = 14
	codesTitle.TextXAlignment = Enum.TextXAlignment.Left
	codesTitle.TextColor3 = Constants.Colors.Text
	codesTitle.Text = "Redeem code"
	codesTitle.Parent = panel

	local codeBox = Instance.new("TextBox")
	codeBox.Position = UDim2.fromOffset(16, 164)
	codeBox.Size = UDim2.fromOffset(240, 40)
	codeBox.BackgroundColor3 = Constants.Colors.Background
	codeBox.Font = Enum.Font.Gotham
	codeBox.TextSize = 14
	codeBox.TextColor3 = Constants.Colors.Text
	codeBox.PlaceholderText = "WARFOUNDING / BUILDCONQUER"
	codeBox.PlaceholderColor3 = Constants.Colors.Muted
	codeBox.Text = ""
	codeBox.ClearTextOnFocus = false
	codeBox.BorderSizePixel = 0
	UIUtil.Corner(codeBox, 6)
	codeBox.Parent = panel

	local redeemBtn = Instance.new("TextButton")
	redeemBtn.Position = UDim2.fromOffset(268, 164)
	redeemBtn.Size = UDim2.fromOffset(116, 40)
	redeemBtn.BackgroundColor3 = Constants.Colors.Accent
	redeemBtn.Font = Enum.Font.GothamBold
	redeemBtn.TextSize = 13
	redeemBtn.TextColor3 = Constants.Colors.Text
	redeemBtn.Text = "REDEEM"
	redeemBtn.BorderSizePixel = 0
	UIUtil.Corner(redeemBtn, 6)
	redeemBtn.Parent = panel
	redeemBtn.MouseButton1Click:Connect(function()
		AudioController.PlayClick()
		local code = codeBox.Text
		if code and #code > 0 then
			Remotes.GetEvent(Constants.RemoteNames.RequestRedeemCode):FireServer(code)
			codeBox.Text = ""
		end
	end)

	local spinnerBtn = Instance.new("TextButton")
	spinnerBtn.Name = "SpinnerClaim"
	spinnerBtn.Position = UDim2.fromOffset(16, 212)
	spinnerBtn.Size = UDim2.new(1, -32, 0, 40)
	spinnerBtn.BackgroundColor3 = Constants.Colors.Accent
	spinnerBtn.Font = Enum.Font.GothamBold
	spinnerBtn.TextSize = 13
	spinnerBtn.TextColor3 = Constants.Colors.Text
	spinnerBtn.Text = "SUPPLY SPINNER — Claim free Cash/Gold"
	spinnerBtn.BorderSizePixel = 0
	UIUtil.Corner(spinnerBtn, 6)
	spinnerBtn.Parent = panel
	spinnerBtn.MouseButton1Click:Connect(function()
		AudioController.PlayClick()
		Remotes.GetEvent(Constants.RemoteNames.RequestClaimSpinner):FireServer()
	end)
	Remotes.GetEvent(Constants.RemoteNames.SpinnerStateUpdate).OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		if payload.Ready == true then
			spinnerBtn.Text = "SUPPLY SPINNER — READY (claim)"
			spinnerBtn.BackgroundColor3 = Constants.Colors.Accent
		else
			local mins = math.ceil((tonumber(payload.CooldownRemaining) or 0) / 60)
			spinnerBtn.Text = string.format("SUPPLY SPINNER — ready in %dm", mins)
			spinnerBtn.BackgroundColor3 = Constants.Colors.Background
		end
	end)

	local bindsTitle = Instance.new("TextLabel")
	bindsTitle.BackgroundTransparency = 1
	bindsTitle.Position = UDim2.fromOffset(16, 260)
	bindsTitle.Size = UDim2.new(1, -32, 0, 22)
	bindsTitle.Font = Enum.Font.GothamBold
	bindsTitle.TextSize = 14
	bindsTitle.TextXAlignment = Enum.TextXAlignment.Left
	bindsTitle.TextColor3 = Constants.Colors.Text
	bindsTitle.Text = "Keybind cheat-sheet"
	bindsTitle.Parent = panel

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(12, 288)
	list.Size = UDim2.new(1, -24, 1, -300)
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


function SettingsController.Toggle()
	setOpen(not open)
end

function SettingsController.Open()
	setOpen(true)
end

function SettingsController.Close()
	setOpen(false)
end

function SettingsController.IsOpen(): boolean
	return open
end

return SettingsController
