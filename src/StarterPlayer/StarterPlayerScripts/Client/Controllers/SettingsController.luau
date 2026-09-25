--!strict
--[[
	Lightweight Settings panel — music/SFX local toggles, redeem codes, the supply spinner and the controls sheet.
	v70 "clean screen": opened ONLY from the TopStrip gear (UIController → SettingsController.Toggle) or a
	terminal. No key (O was Roblox camera zoom-out; HudConfig.Keys.Settings = nil). The keybind sheet is generated
	from HudConfig.Keys, so it can never drift from the real bindings; it shows ONLY while HudLayout.PrefersKeys()
	(UserInputService.PreferredInput keyboard / gamepad — mobile merge gate #7: phone players are never told to
	press keys). A registered Modal panel (HudLayout id "Settings") with the black dim; one HUD scale + safe area;
	every tappable ≥ 44 real px on touch.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)
local HudConfig = require(Shared.Configs.HudConfig)
local NationConfig = require(Shared.Configs.NationConfig)
local NationTexture = require(Shared.Util.NationTexture)
local AdminConfig = require(Shared.Configs.AdminConfig)

local ClientSettings = require(script.Parent.Parent.Modules.ClientSettings)
local AudioController = require(script.Parent.Parent.Modules.AudioController)
local PanelShell = require(script.Parent.Parent.Modules.PanelShell)
local HudLayout = require(script.Parent.Parent.Modules.HudLayout)

-- Nations (lane C): CHANGE opens the picker. Required defensively (UIController does the same), so a broken picker
-- can never take the Settings panel down; the YOUR FLAG row is simply left out then.
local NationController: any = nil
do
	local mod = script.Parent:FindFirstChild("NationController")
	if mod and mod:IsA("ModuleScript") then
		local req: any = require
		local ok, res = pcall(req, mod)
		if ok and typeof(res) == "table" and typeof(res.Open) == "function" then
			NationController = res
		end
	end
end

local SettingsController = {}

local PANEL_ID = "Settings"

local player = Players.LocalPlayer
local isTouch = UserInputService.TouchEnabled
local open = false
local screenGui: ScreenGui? = nil
local shell: PanelShell.Shell? = nil
local musicBtn: TextButton? = nil
local sfxBtn: TextButton? = nil

-- key cap text for a KeyCode (anything not listed shows its Enum name, e.g. "P")
local KEY_NAMES: { [string]: string } = {
	One = "1",
	Two = "2",
	Three = "3",
	Four = "4",
	ButtonR2 = "R2",
	ButtonR1 = "R1",
	ButtonL1 = "L1",
	ButtonY = "Y pad",
	ButtonX = "X pad",
	DPadUp = "D-pad Up",
}

local function keyName(k: Enum.KeyCode?): string
	if k == nil then
		return "—"
	end
	return KEY_NAMES[k.Name] or k.Name
end

local function keyRange(list: { Enum.KeyCode }?): string
	if not list or #list == 0 then
		return "—"
	end
	if #list == 1 then
		return keyName(list[1])
	end
	return keyName(list[1]) .. "-" .. keyName(list[#list])
end

export type KeyRow = { Key: string, Action: string }
export type KeySection = { Title: string, Rows: { KeyRow } }

--[[ The controls sheet, generated from HudConfig.Keys (spec §7). Exposed for tests. ]]
function SettingsController.BuildKeySheet(): { KeySection }
	local K = HudConfig.Keys
	local panels: { KeyRow } = {
		{ Key = keyName(K.Shop), Action = "Shop" },
		{ Key = keyName(K.Rebirth), Action = "Rebirth · Battle Pass · Clan" },
		{ Key = keyName(K.Army), Action = "Army orders (popover)" },
		{ Key = keyName(K.Garage), Action = "Garage" },
		{ Key = keyName(K.Missions), Action = "Missions · daily reward" },
		{ Key = keyName(K.Base), Action = "Base upgrades menu" },
	}
	if K.Settings == nil then
		table.insert(panels, { Key = "Gear", Action = "Settings (top bar button)" })
	else
		table.insert(panels, { Key = keyName(K.Settings), Action = "Settings" })
	end
	local combat: { KeyRow } = {
		{ Key = keyRange(K.Weapons), Action = "Draw / holster a hotbar weapon" },
		{ Key = keyName(K.WeaponPrev), Action = "Previous weapon" },
		{ Key = keyName(K.Reload), Action = "Reload" },
	}
	if K.WeaponWheel then
		table.insert(combat, { Key = "Wheel", Action = "Cycle weapons while drawn" })
	end
	if K.FireNeedsDrawn then
		table.insert(combat, { Key = "LMB", Action = "Fire (weapon drawn)" })
	else
		table.insert(combat, { Key = "LMB", Action = "Fire" })
	end
	local orders: { KeyRow } = {
		{ Key = keyName(K.OrdersCycle), Action = "Cycle the squad order" },
		{ Key = keyRange(K.Weapons), Action = "Squad orders while the Army popover is open" },
		{ Key = "E / F", Action = "Interact · terminals" },
	}
	local pad: { KeyRow } = {}
	local G = K.Gamepad
	if G then
		table.insert(pad, { Key = keyName(G.Fire), Action = "Fire" })
		table.insert(pad, { Key = keyName(G.Reload), Action = "Reload" })
		table.insert(pad, { Key = keyName(G.Next) .. " / " .. keyName(G.Prev), Action = "Next / previous weapon" })
		table.insert(pad, { Key = keyName(G.DrawHolster), Action = "Draw / holster" })
	end
	local sections: { KeySection } = {
		{ Title = "PANELS", Rows = panels },
		{ Title = "COMBAT", Rows = combat },
		{ Title = "SQUAD & WORLD", Rows = orders },
	}
	if #pad > 0 then
		table.insert(sections, { Title = "GAMEPAD", Rows = pad })
	end
	return sections
end

local function setOpen(isOpen: boolean)
	open = isOpen
	if screenGui then
		local panel = screenGui:FindFirstChild("Panel")
		if panel and panel:IsA("GuiObject") then
			panel.Visible = isOpen
		end
	end
	local sh = shell
	if sh then
		sh.Sync(isOpen)
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
	PanelShell.Screen(screen) -- DisplayOrder 60 (Panels), one HUD scale + safe area
	screen.Parent = player:WaitForChild("PlayerGui")
	screenGui = screen

	local TAP = PanelShell.TouchMinV()
	local GAP = 8

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = if isTouch then UDim2.new(0.94, 0, 1, -16) else UDim2.fromOffset(460, 580)
	panel.BackgroundColor3 = Constants.Colors.Panel
	panel.BorderSizePixel = 0
	panel.Active = true
	panel.Visible = false
	panel.Parent = screen
	UIUtil.Corner(panel, 12)
	UIUtil.Stroke(panel)
	do
		local cap = Instance.new("UISizeConstraint")
		cap.MaxSize = if isTouch then Vector2.new(760, 620) else Vector2.new(460, 580)
		cap.Parent = panel
	end

	PanelShell.Title(panel, "Settings")
	PanelShell.CloseButton(panel, function()
		AudioController.PlayClick()
		setOpen(false)
	end)

	local headerH = TAP + 8
	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Position = UDim2.fromOffset(0, headerH)
	body.Size = UDim2.new(1, 0, 1, -(headerH + 8))
	body.ScrollBarThickness = if isTouch then 6 else 4
	body.ScrollingDirection = Enum.ScrollingDirection.Y
	body.CanvasSize = UDim2.fromOffset(0, 0)
	body.Parent = panel

	local y = 0
	local host: GuiObject = body -- where section() / button() / the key rows go (the KeySheet frame for the sheet)
	local sectionSize = PanelShell.Text(14)
	local function section(text: string)
		local lab = Instance.new("TextLabel")
		lab.BackgroundTransparency = 1
		lab.Position = UDim2.fromOffset(16, y)
		lab.Size = UDim2.new(1, -32, 0, sectionSize + 6)
		lab.Font = Enum.Font.GothamBold
		lab.TextSize = sectionSize
		lab.TextXAlignment = Enum.TextXAlignment.Left
		lab.TextColor3 = Constants.Colors.Gold
		lab.Text = text
		lab.Parent = host
		y += sectionSize + 10
	end
	local function button(name: string, text: string, x: UDim, w: UDim, color: Color3?): TextButton
		local b = Instance.new("TextButton")
		b.Name = name
		b.Position = UDim2.new(x.Scale, x.Offset, 0, y)
		b.Size = UDim2.new(w.Scale, w.Offset, 0, TAP)
		b.BackgroundColor3 = color or Constants.Colors.Accent
		b.Font = Enum.Font.GothamBold
		b.TextSize = PanelShell.Text(13)
		b.TextColor3 = Constants.Colors.Text
		b.TextWrapped = true
		b.Text = text
		b.BorderSizePixel = 0
		b.Active = true
		UIUtil.Corner(b, 8)
		b.Parent = host
		return b
	end

	-- Sound (local-only)
	section("SOUND (this device only)")
	local mb = button("Music", "Music: ON", UDim.new(0, 16), UDim.new(0.5, -16 - GAP / 2))
	mb.Activated:Connect(function()
		ClientSettings.ToggleMusic()
		refreshToggleLabels()
		AudioController.PlayClick()
	end)
	musicBtn = mb
	local sb = button("Sfx", "SFX: ON", UDim.new(0.5, GAP / 2), UDim.new(0.5, -16 - GAP / 2))
	sb.Activated:Connect(function()
		ClientSettings.ToggleSfx()
		refreshToggleLabels()
		AudioController.PlayClick()
	end)
	sfxBtn = sb
	y += TAP + 14

	-- Your flag (nations): the country shown on your own base. CHANGE opens the picker in Settings mode
	-- (NationController.Open(nil)); the server decides whether a change is allowed. 68 v tall on every device
	-- (47.6 real px on phones), text >= 20 v on touch.
	-- Lead decision 6 (nations lane B): until the flag art is uploaded (NationTexture.ArtReady) only admins see
	-- nations at all, so the row is left out for everyone else (same gate as the join picker and the flagpole prompt).
	local nationArtOk = not NationConfig.LiveRequiresArt
		or NationTexture.ArtReady()
		or table.find(AdminConfig.UserIds, player.UserId) ~= nil
	if NationController and NationConfig.Enabled and nationArtOk then
		section("YOUR FLAG")
		local changeW, changeH = 170, 68
		local swatch = Instance.new("Frame")
		swatch.Name = "NationSwatch"
		swatch.Position = UDim2.fromOffset(16, y + 10)
		swatch.Size = UDim2.fromOffset(64, 48) -- 4:3, the flag's banner colour
		swatch.BackgroundColor3 = Constants.Colors.Olive
		swatch.BorderSizePixel = 0
		swatch.Active = false
		swatch.Parent = body
		UIUtil.Corner(swatch, 4)
		UIUtil.Stroke(swatch)
		local nameLab = Instance.new("TextLabel")
		nameLab.Name = "NationName"
		nameLab.BackgroundTransparency = 1
		nameLab.Position = UDim2.fromOffset(16 + 64 + 12, y)
		nameLab.Size = UDim2.new(1, -(16 + 64 + 12 + 16 + changeW + GAP), 0, changeH)
		nameLab.Font = Enum.Font.GothamBold
		nameLab.TextSize = PanelShell.Text(14)
		nameLab.TextColor3 = Constants.Colors.Text
		nameLab.TextXAlignment = Enum.TextXAlignment.Left
		nameLab.TextTruncate = Enum.TextTruncate.AtEnd
		nameLab.Text = "Not chosen"
		nameLab.Parent = body
		local change = Instance.new("TextButton")
		change.Name = "NationChange"
		change.Position = UDim2.new(1, -(16 + changeW), 0, y)
		change.Size = UDim2.fromOffset(changeW, changeH)
		change.BackgroundColor3 = Constants.Colors.Accent
		change.Font = Enum.Font.GothamBold
		change.TextSize = PanelShell.Text(14)
		change.TextColor3 = Constants.Colors.Text
		change.Text = "CHANGE"
		change.BorderSizePixel = 0
		change.Active = true
		UIUtil.Corner(change, 8)
		change.Parent = body
		change.Activated:Connect(function()
			AudioController.PlayClick()
			NationController.Open(nil) -- Settings mode (the picker's own panel replaces this one)
		end)
		local function refreshNation()
			local id = player:GetAttribute("WE_NationId")
			local def = NationConfig.Get(id)
			if def then
				nameLab.Text = def.Short
				swatch.BackgroundColor3 = def.Color
			elseif id == NationConfig.NeutralId then
				nameLab.Text = NationConfig.NeutralLabel
				swatch.BackgroundColor3 = Constants.Colors.Olive
			else
				nameLab.Text = "Not chosen"
				swatch.BackgroundColor3 = Constants.Colors.Gunmetal
			end
		end
		player:GetAttributeChangedSignal("WE_NationId"):Connect(refreshNation)
		refreshNation()
		y += changeH + 14
	end

	-- Promo codes (server-validated, once each)
	section("REDEEM CODE")
	local redeemW = if isTouch then 170 else 120
	local codeBox = Instance.new("TextBox")
	codeBox.Name = "CodeBox"
	codeBox.Position = UDim2.fromOffset(16, y)
	codeBox.Size = UDim2.new(1, -(32 + redeemW + GAP), 0, TAP)
	codeBox.BackgroundColor3 = Constants.Colors.Background
	codeBox.Font = Enum.Font.GothamMedium
	codeBox.TextSize = PanelShell.Text(14)
	codeBox.TextColor3 = Constants.Colors.Text
	codeBox.PlaceholderText = "WARFOUNDING / BUILDCONQUER"
	codeBox.PlaceholderColor3 = Constants.Colors.Muted
	codeBox.Text = ""
	codeBox.ClearTextOnFocus = false
	codeBox.BorderSizePixel = 0
	UIUtil.Corner(codeBox, 8)
	codeBox.Parent = body
	local redeemBtn = button("Redeem", "REDEEM", UDim.new(1, -(16 + redeemW)), UDim.new(0, redeemW))
	redeemBtn.Activated:Connect(function()
		AudioController.PlayClick()
		local code = codeBox.Text
		if code and #code > 0 then
			task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestRedeemCode, code)
			codeBox.Text = ""
		end
	end)
	y += TAP + 14

	-- Supply spinner (the Missions panel has the same claim row; this section stays per spec §3.7)
	section("SUPPLY SPINNER")
	local spinnerBtn = button("SpinnerClaim", "SUPPLY SPINNER — Claim free Cash/Gold", UDim.new(0, 16), UDim.new(1, -32))
	spinnerBtn.Activated:Connect(function()
		AudioController.PlayClick()
		task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestClaimSpinner)
	end)
	Remotes.BindEvent(Constants.RemoteNames.SpinnerStateUpdate, function(payload: any)
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
	y += TAP + 14

	-- Controls sheet, generated from HudConfig.Keys. Its own frame (KeySheet) so it can come and go with the
	-- device: shown only while HudLayout.PrefersKeys() (keyboard / gamepad), never to a touch player.
	local sheetTop = y
	local sheet = Instance.new("Frame")
	sheet.Name = "KeySheet"
	sheet.BackgroundTransparency = 1
	sheet.BorderSizePixel = 0
	sheet.Position = UDim2.fromOffset(0, sheetTop)
	sheet.Size = UDim2.new(1, 0, 0, 0)
	sheet.Parent = body
	host = sheet
	y = 0
	section("CONTROLS")
	local rowText = PanelShell.Text(13)
	local rowH = rowText + 12
	local capW = if isTouch then 110 else 92
	for _, sec in ipairs(SettingsController.BuildKeySheet()) do
		local head = Instance.new("TextLabel")
		head.BackgroundTransparency = 1
		head.Position = UDim2.fromOffset(16, y)
		head.Size = UDim2.new(1, -32, 0, rowText + 4)
		head.Font = Enum.Font.GothamBold
		head.TextSize = rowText
		head.TextXAlignment = Enum.TextXAlignment.Left
		head.TextColor3 = Constants.Colors.Muted
		head.Text = sec.Title
		head.Parent = host
		y += rowText + 8
		for _, r in ipairs(sec.Rows) do
			local row = Instance.new("Frame")
			row.Name = "Key_" .. r.Key
			row.Position = UDim2.fromOffset(16, y)
			row.Size = UDim2.new(1, -32, 0, rowH)
			row.BackgroundColor3 = Constants.Colors.Background
			row.BackgroundTransparency = 0.35
			row.BorderSizePixel = 0
			row.Parent = host
			UIUtil.Corner(row, 6)
			local cap = Instance.new("TextLabel")
			cap.Name = "Cap"
			cap.Position = UDim2.fromOffset(4, 3)
			cap.Size = UDim2.new(0, capW, 1, -6)
			cap.BackgroundColor3 = Constants.Colors.Gunmetal
			cap.BorderSizePixel = 0
			cap.Font = HudConfig.Fonts.Display
			cap.TextSize = rowText
			cap.TextColor3 = Constants.Colors.Text
			cap.Text = r.Key
			cap.Parent = row
			UIUtil.Corner(cap, 5)
			local act = Instance.new("TextLabel")
			act.BackgroundTransparency = 1
			act.Position = UDim2.fromOffset(capW + 14, 0)
			act.Size = UDim2.new(1, -(capW + 18), 1, 0)
			act.Font = Enum.Font.GothamMedium
			act.TextSize = rowText
			act.TextXAlignment = Enum.TextXAlignment.Left
			act.TextTruncate = Enum.TextTruncate.AtEnd
			act.TextColor3 = Constants.Colors.Text
			act.Text = r.Action
			act.Parent = row
			y += rowH + 4
		end
		y += 6
	end
	local sheetH = y
	sheet.Size = UDim2.new(1, 0, 0, sheetH)
	local function applySheet(show: boolean)
		sheet.Visible = show
		body.CanvasSize = UDim2.fromOffset(0, sheetTop + (if show then sheetH else 0) + 8)
	end
	applySheet(HudLayout.PrefersKeys())
	HudLayout.InputModeChanged:Connect(applySheet)

	shell = PanelShell.Attach({
		Id = PANEL_ID,
		Screen = screen,
		Panel = panel,
		IsOpen = function(): boolean
			return open
		end,
		Close = function()
			setOpen(false)
		end,
	})

	refreshToggleLabels()
	ClientSettings.OnChanged(refreshToggleLabels)
end

function SettingsController.Toggle()
	local sh = shell
	if not open and sh and sh.TapThrough() then
		return
	end
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
