--!strict
--[[
	Codes panel — Code Bot v102. Opened from the "Codes" rail tile (UIController → CodesController.Toggle) and from
	Settings → REDEEM CODE. A registered Modal panel (HudLayout id "Codes") with the black dim; one HUD scale + safe
	area; every tappable ≥ 44 real px on touch; no text under 14 real px.

	Text box + REDEEM → Remotes RedeemCode (RemoteFunction, CodesService validates + rate-limits) → the result line
	(Success / AlreadyUsed / Invalid / Expired / RateLimited). Shows the running 2x Cash boost from the player
	attribute WE_CashBoostUntil. The Discord line comes from SocialConfig.DiscordText (no link in-game).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- streaming2 C5: bounded wait (CLAUDE.md); a missing Shared warns and returns this module empty, never throws
local CodesController = {}
local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
if not Shared then
	warn("[WAR EMPIRE] CodesController: no ReplicatedStorage.Shared after 60 s; not started")
	return CodesController
end
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)
local HudConfig = require(Shared.Configs.HudConfig)
local SocialConfig = require(Shared.Configs.SocialConfig)

local AudioController = require(script.Parent.Parent.Modules.AudioController)
local PanelShell = require(script.Parent.Parent.Modules.PanelShell)

local PANEL_ID = "Codes"

local RESULT_COLORS: { [string]: Color3 } = {
	Success = Color3.fromRGB(90, 230, 120),
	AlreadyUsed = Color3.fromRGB(255, 190, 70),
	Expired = Color3.fromRGB(255, 190, 70),
	Invalid = Color3.fromRGB(255, 96, 96),
	RateLimited = Color3.fromRGB(255, 96, 96),
	NotReady = Color3.fromRGB(190, 196, 204),
}

local player = Players.LocalPlayer
local open = false
local busy = false
local panelFrame: Frame? = nil
local shell: PanelShell.Shell? = nil
local codeBox: TextBox? = nil
local redeemBtn: TextButton? = nil
local resultLabel: TextLabel? = nil
local boostLabel: TextLabel? = nil
local boostLoop = false

local function serverNow(): number
	local ok, t = pcall(function()
		return Workspace:GetServerTimeNow()
	end)
	return if ok and typeof(t) == "number" then t else os.time()
end

local function boostLeft(): number
	local u = player:GetAttribute("WE_CashBoostUntil")
	if typeof(u) ~= "number" then
		return 0
	end
	return math.max(0, u - serverNow())
end

local function refreshBoost()
	local lab = boostLabel
	if not lab then
		return
	end
	local left = math.floor(boostLeft())
	if left > 0 then
		local h = left // 3600
		local m = (left % 3600) // 60
		local s = left % 60
		lab.Text = if h > 0
			then string.format("2x CASH BOOST ACTIVE  %d:%02d:%02d left", h, m, s)
			else string.format("2x CASH BOOST ACTIVE  %d:%02d left", m, s)
		lab.Visible = true
	else
		lab.Visible = false
	end
end

local function startBoostLoop()
	if boostLoop then
		return
	end
	boostLoop = true
	task.spawn(function()
		while open do
			refreshBoost()
			task.wait(1)
		end
		boostLoop = false
	end)
end

local function setResult(kind: string, message: string)
	local lab = resultLabel
	if not lab then
		return
	end
	lab.Text = message
	lab.TextColor3 = RESULT_COLORS[kind] or PanelShell.Colors.Muted
end

local function setOpen(isOpen: boolean)
	open = isOpen
	local p = panelFrame
	if p then
		p.Visible = isOpen
	end
	if isOpen then
		refreshBoost()
		startBoostLoop()
	else
		local box = codeBox
		if box and box:IsFocused() then
			box:ReleaseFocus()
		end
	end
	local sh = shell
	if sh then
		sh.Sync(isOpen)
	end
end

local function doRedeem()
	local box = codeBox
	if busy or not box then
		return
	end
	local code = string.gsub(box.Text, "%s+", "")
	if code == "" then
		setResult("Invalid", "Type a code first.")
		return
	end
	local fn = Remotes.TryGetFunction(Constants.RemoteNames.RedeemCode)
	if not fn then
		setResult("NotReady", "Still loading. Try again in a moment.")
		return
	end
	busy = true
	local btn = redeemBtn
	if btn then
		btn.Text = "..."
		btn.AutoButtonColor = false
	end
	setResult("NotReady", "Checking code...")
	task.spawn(function()
		local ok, res = pcall(function()
			return fn:InvokeServer(string.sub(code, 1, 64))
		end)
		busy = false
		if btn then
			btn.Text = "REDEEM"
			btn.AutoButtonColor = true
		end
		if ok and typeof(res) == "table" and typeof(res.Result) == "string" then
			local kind = res.Result :: string
			setResult(kind, if typeof(res.Message) == "string" then res.Message else kind)
			if kind == "Success" then
				box.Text = ""
				refreshBoost()
			end
		else
			setResult("NotReady", "Couldn't reach the server. Try again.")
		end
	end)
end

local function label(name: string, text: string, size: number, color: Color3, y: number, h: number, parent: Instance): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromOffset(16, y)
	t.Size = UDim2.new(1, -32, 0, h)
	t.Font = Enum.Font.GothamBold
	t.TextSize = PanelShell.Text(size)
	t.TextColor3 = color
	t.TextWrapped = true
	t.TextXAlignment = Enum.TextXAlignment.Center
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.Text = text
	t.Parent = parent
	return t
end

function CodesController.Init()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireCodes"
	PanelShell.Screen(screen) -- DisplayOrder 60 (Panels), one HUD scale + safe area
	local pg = player:WaitForChild("PlayerGui", 30) -- bounded (streaming2 C5, CLAUDE.md)
	if not pg then
		warn("[WAR EMPIRE] CodesController: no PlayerGui after 30 s; Codes panel off")
		screen:Destroy()
		return
	end
	screen.Parent = pg

	local touch = PanelShell.IsTouch()
	local TAP = PanelShell.TouchMinV()
	local GAP = 12
	local headerH = TAP + 8
	local textH = PanelShell.Text(16) + 10
	local resultH = PanelShell.Text(16) * 2 + 12 -- two lines of result text
	local panelH = headerH + TAP + GAP + TAP + GAP + resultH + textH + textH + 20

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = if touch then UDim2.new(0.7, 0, 0, panelH) else UDim2.fromOffset(460, panelH)
	panel.BackgroundColor3 = Constants.Colors.Panel
	panel.BorderSizePixel = 0
	panel.Active = true
	panel.Visible = false
	panel.Parent = screen
	UIUtil.Corner(panel, 12)
	UIUtil.Stroke(panel)
	do
		local cap = Instance.new("UISizeConstraint")
		cap.MinSize = Vector2.new(if touch then 420 else 380, 0)
		cap.MaxSize = Vector2.new(if touch then 640 else 460, panelH)
		cap.Parent = panel
	end
	panelFrame = panel

	PanelShell.Title(panel, "Codes")
	PanelShell.CloseButton(panel, function()
		pcall(AudioController.PlayClick)
		setOpen(false)
	end)

	local y = headerH
	local box = Instance.new("TextBox")
	box.Name = "CodeBox"
	box.Position = UDim2.fromOffset(16, y)
	box.Size = UDim2.new(1, -32, 0, TAP)
	box.BackgroundColor3 = Constants.Colors.Background
	box.Font = Enum.Font.GothamBold
	box.TextSize = PanelShell.Text(22)
	box.TextColor3 = Constants.Colors.Text
	box.PlaceholderText = "Enter code"
	box.PlaceholderColor3 = Constants.Colors.Muted
	box.Text = ""
	box.ClearTextOnFocus = false
	box.TextTruncate = Enum.TextTruncate.AtEnd
	box.BorderSizePixel = 0
	box.Parent = panel
	UIUtil.Corner(box, 8)
	UIUtil.Stroke(box, Constants.Colors.GunmetalLight, 1.5)
	box.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			doRedeem()
		end
	end)
	codeBox = box
	y += TAP + GAP

	local btn = Instance.new("TextButton")
	btn.Name = "Redeem"
	btn.Position = UDim2.fromOffset(16, y)
	btn.Size = UDim2.new(1, -32, 0, TAP)
	btn.BackgroundColor3 = Color3.fromRGB(46, 170, 82)
	btn.Font = HudConfig.Fonts.Display
	btn.TextSize = PanelShell.Text(24)
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Text = "REDEEM"
	btn.BorderSizePixel = 0
	btn.Active = true
	btn.Parent = panel
	UIUtil.Corner(btn, 10)
	UIUtil.TextOutline(btn, 1.5)
	btn.Activated:Connect(function()
		pcall(AudioController.PlayClick)
		doRedeem()
	end)
	redeemBtn = btn
	y += TAP + GAP

	resultLabel = label("Result", "", 16, PanelShell.Colors.Muted, y, resultH, panel)
	y += resultH

	boostLabel = label("Boost", "", 16, Constants.Colors.Cash, y, textH, panel)
	boostLabel.Visible = false
	y += textH

	label("Discord", SocialConfig.DiscordText, 16, Constants.Colors.GoldBright, y, textH, panel)

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

	player:GetAttributeChangedSignal("WE_CashBoostUntil"):Connect(function()
		if open then
			refreshBoost()
		end
	end)
end

function CodesController.Toggle()
	local sh = shell
	if not open and sh and sh.TapThrough() then
		return
	end
	setOpen(not open)
end

function CodesController.Open()
	setOpen(true)
end

function CodesController.Close()
	setOpen(false)
end

function CodesController.IsOpen(): boolean
	return open
end

return CodesController
