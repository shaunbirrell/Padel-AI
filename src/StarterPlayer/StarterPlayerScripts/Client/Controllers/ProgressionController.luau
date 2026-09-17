--!strict
--[[ Progression UI — Prestige + Battle Pass + Clan (key K / PROGRESS button) ]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)

local ProgressionController = {}

local player = Players.LocalPlayer
local menuOpen = false
local screenGui: ScreenGui? = nil
local prestigeLabel: TextLabel? = nil
local bpLabel: TextLabel? = nil
local clanLabel: TextLabel? = nil
local prestigeState: any = nil
local bpState: any = nil
local clanState: any = nil

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function refreshLabels()
	if prestigeLabel and typeof(prestigeState) == "table" then
		prestigeLabel.Text = string.format(
			"Prestige P%d  |  Need Lv %d  |  Can: %s",
			tonumber(prestigeState.Prestige) or 0,
			tonumber(prestigeState.MinLevel) or 100,
			if prestigeState.CanPrestige then "YES" else "no"
		)
	end
	if bpLabel and typeof(bpState) == "table" then
		bpLabel.Text = string.format(
			"BP L%d  XP %d/%d  %s",
			tonumber(bpState.Level) or 0,
			tonumber(bpState.XP) or 0,
			tonumber(bpState.XPPerLevel) or 1000,
			if bpState.Premium then "PREMIUM" else "Free"
		)
	end
	if clanLabel and typeof(clanState) == "table" then
		if clanState.ClanId then
			clanLabel.Text = string.format(
				"Clan [%s] %s (%d)\nId: %s",
				tostring(clanState.Tag or "?"),
				tostring(clanState.Name or "?"),
				tonumber(clanState.MemberCount) or 0,
				tostring(clanState.ClanId)
			)
		else
			clanLabel.Text = "Not in a clan — create one below"
		end
	end
end

local function setOpen(open: boolean)
	menuOpen = open
	if screenGui then
		local panel = screenGui:FindFirstChild("Panel")
		if panel and panel:IsA("GuiObject") then
			panel.Visible = open
		end
	end
end

function ProgressionController.Init()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireProgression"
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = player:WaitForChild("PlayerGui")
	screenGui = screen

	local toggle = Instance.new("TextButton")
	toggle.Name = "ProgressToggle"
	toggle.AnchorPoint = Vector2.new(0, 1)
	toggle.Position = UDim2.new(0, 224, 1, -16)
	toggle.Size = UDim2.fromOffset(100, 36)
	toggle.BackgroundColor3 = Constants.Colors.Panel
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = 13
	toggle.TextColor3 = Constants.Colors.Text
	toggle.Text = "PROGRESS"
	toggle.BorderSizePixel = 0
	corner(toggle, 8)
	toggle.Parent = screen
	toggle.MouseButton1Click:Connect(function()
		setOpen(not menuOpen)
	end)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(440, 440)
	panel.BackgroundColor3 = Constants.Colors.Panel
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screen
	corner(panel, 10)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -80, 0, 28)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Constants.Colors.Text
	title.Text = "Progression"
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
	corner(close, 6)
	close.Parent = panel
	close.MouseButton1Click:Connect(function()
		setOpen(false)
	end)

	local y = 48
	local function section(text: string)
		local lab = Instance.new("TextLabel")
		lab.BackgroundTransparency = 1
		lab.Position = UDim2.fromOffset(16, y)
		lab.Size = UDim2.new(1, -32, 0, 20)
		lab.Font = Enum.Font.GothamBold
		lab.TextSize = 14
		lab.TextXAlignment = Enum.TextXAlignment.Left
		lab.TextColor3 = Constants.Colors.Accent
		lab.Text = text
		lab.Parent = panel
		y += 24
	end
	local function body(): TextLabel
		local lab = Instance.new("TextLabel")
		lab.BackgroundTransparency = 1
		lab.Position = UDim2.fromOffset(16, y)
		lab.Size = UDim2.new(1, -32, 0, 36)
		lab.Font = Enum.Font.Gotham
		lab.TextSize = 12
		lab.TextWrapped = true
		lab.TextXAlignment = Enum.TextXAlignment.Left
		lab.TextYAlignment = Enum.TextYAlignment.Top
		lab.TextColor3 = Constants.Colors.Muted
		lab.Text = "..."
		lab.Parent = panel
		y += 40
		return lab
	end
	local function btn(label: string, cb: () -> ())
		local b = Instance.new("TextButton")
		b.Position = UDim2.fromOffset(16, y)
		b.Size = UDim2.fromOffset(220, 32)
		b.BackgroundColor3 = Constants.Colors.Accent
		b.Font = Enum.Font.GothamBold
		b.TextSize = 13
		b.TextColor3 = Constants.Colors.Text
		b.Text = label
		b.BorderSizePixel = 0
		corner(b, 6)
		b.Parent = panel
		b.MouseButton1Click:Connect(cb)
		y += 40
	end

	section("PRESTIGE")
	prestigeLabel = body()
	btn("PRESTIGE NOW", function()
		Remotes.GetEvent(Constants.RemoteNames.RequestPrestige):FireServer()
	end)

	section("BATTLE PASS")
	bpLabel = body()
	btn("CLAIM FREE REWARDS", function()
		if typeof(bpState) ~= "table" then
			return
		end
		local level = tonumber(bpState.Level) or 0
		local claimed = bpState.ClaimedFree or {}
		for i = 1, level do
			if not claimed[tostring(i)] then
				Remotes.GetEvent(Constants.RemoteNames.RequestClaimBattlePassReward):FireServer(i, "free")
			end
		end
	end)
	btn("CLAIM PREMIUM REWARDS", function()
		if typeof(bpState) ~= "table" or not bpState.Premium then
			return
		end
		local level = tonumber(bpState.Level) or 0
		local claimed = bpState.ClaimedPremium or {}
		for i = 1, level do
			if not claimed[tostring(i)] then
				Remotes.GetEvent(Constants.RemoteNames.RequestClaimBattlePassReward):FireServer(i, "premium")
			end
		end
	end)

	section("CLAN")
	clanLabel = body()
	local nameBox = Instance.new("TextBox")
	nameBox.Position = UDim2.fromOffset(16, y)
	nameBox.Size = UDim2.fromOffset(200, 28)
	nameBox.BackgroundColor3 = Constants.Colors.Background
	nameBox.Font = Enum.Font.Gotham
	nameBox.TextSize = 13
	nameBox.TextColor3 = Constants.Colors.Text
	nameBox.PlaceholderText = "Clan name"
	nameBox.Text = ""
	nameBox.ClearTextOnFocus = false
	nameBox.BorderSizePixel = 0
	corner(nameBox, 6)
	nameBox.Parent = panel
	local tagBox = Instance.new("TextBox")
	tagBox.Position = UDim2.fromOffset(224, y)
	tagBox.Size = UDim2.fromOffset(80, 28)
	tagBox.BackgroundColor3 = Constants.Colors.Background
	tagBox.Font = Enum.Font.Gotham
	tagBox.TextSize = 13
	tagBox.TextColor3 = Constants.Colors.Text
	tagBox.PlaceholderText = "TAG"
	tagBox.Text = ""
	tagBox.ClearTextOnFocus = false
	tagBox.BorderSizePixel = 0
	corner(tagBox, 6)
	tagBox.Parent = panel
	y += 36
	btn("CREATE CLAN", function()
		Remotes.GetEvent(Constants.RemoteNames.RequestCreateClan):FireServer(nameBox.Text, tagBox.Text)
	end)
	local joinBox = Instance.new("TextBox")
	joinBox.Position = UDim2.fromOffset(16, y)
	joinBox.Size = UDim2.fromOffset(280, 28)
	joinBox.BackgroundColor3 = Constants.Colors.Background
	joinBox.Font = Enum.Font.Gotham
	joinBox.TextSize = 12
	joinBox.TextColor3 = Constants.Colors.Text
	joinBox.PlaceholderText = "Clan Id to join"
	joinBox.Text = ""
	joinBox.ClearTextOnFocus = false
	joinBox.BorderSizePixel = 0
	corner(joinBox, 6)
	joinBox.Parent = panel
	y += 36
	btn("JOIN CLAN", function()
		Remotes.GetEvent(Constants.RemoteNames.RequestJoinClan):FireServer(joinBox.Text)
	end)
	btn("LEAVE CLAN", function()
		Remotes.GetEvent(Constants.RemoteNames.RequestLeaveClan):FireServer()
	end)

	Remotes.GetEvent(Constants.RemoteNames.PrestigeStateUpdate).OnClientEvent:Connect(function(payload)
		prestigeState = payload
		refreshLabels()
	end)
	Remotes.GetEvent(Constants.RemoteNames.BattlePassStateUpdate).OnClientEvent:Connect(function(payload)
		bpState = payload
		refreshLabels()
	end)
	Remotes.GetEvent(Constants.RemoteNames.ClanStateUpdate).OnClientEvent:Connect(function(payload)
		clanState = payload
		refreshLabels()
	end)

	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then
			return
		end
		if input.KeyCode == Enum.KeyCode.K then
			setOpen(not menuOpen)
		end
	end)
end

return ProgressionController
