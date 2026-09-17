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
local bpClaimHint: TextLabel? = nil
local clanLabel: TextLabel? = nil
local trackList: ScrollingFrame? = nil
local prestigeState: any = nil
local bpState: any = nil
local clanState: any = nil

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function formatReward(reward: any): string
	if typeof(reward) ~= "table" then
		return ""
	end
	local parts = {}
	if typeof(reward.Cash) == "number" and reward.Cash > 0 then
		table.insert(parts, string.format("$%d", reward.Cash))
	end
	if typeof(reward.Gold) == "number" and reward.Gold > 0 then
		table.insert(parts, string.format("%dG", reward.Gold))
	end
	return table.concat(parts, " + ")
end

local function rebuildTrackPreview()
	if not trackList or typeof(bpState) ~= "table" then
		return
	end
	for _, child in ipairs(trackList:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local level = tonumber(bpState.Level) or 0
	local freeTrack = bpState.FreeTrack or {}
	local premTrack = bpState.PremiumTrack or {}
	local claimedFree = bpState.ClaimedFree or {}
	local claimedPrem = bpState.ClaimedPremium or {}
	local premium = bpState.Premium == true

	local tiers: { number } = {}
	local seen: { [number]: boolean } = {}
	for t in pairs(freeTrack) do
		local n = tonumber(t)
		if n and not seen[n] then
			seen[n] = true
			table.insert(tiers, n)
		end
	end
	for t in pairs(premTrack) do
		local n = tonumber(t)
		if n and not seen[n] then
			seen[n] = true
			table.insert(tiers, n)
		end
	end
	table.sort(tiers)

	local rows = 0
	local maxRows = 12
	for _, tier in ipairs(tiers) do
		if rows >= maxRows then
			break
		end
		local freeR = freeTrack[tier] or freeTrack[tostring(tier)]
		local premR = premTrack[tier] or premTrack[tostring(tier)]
		local freeClaimed = claimedFree[tostring(tier)] == true
		local premClaimed = claimedPrem[tostring(tier)] == true
		local reached = tier <= level
		local freeReady = reached and freeR ~= nil and not freeClaimed
		local premReady = reached and premium and premR ~= nil and not premClaimed
		local interesting = freeReady
			or premReady
			or (reached and ((freeR ~= nil and not freeClaimed) or (premR ~= nil and not premClaimed)))
			or (not reached and tier <= level + 6)
		local skip = false
		if not interesting and rows > 0 then
			skip = true
		elseif not interesting and rows == 0 and tier > level + 3 then
			skip = true
		end
		if not skip then
			rows += 1
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -6, 0, 28)
			row.BackgroundColor3 = Constants.Colors.Background
			row.BorderSizePixel = 0
			row.LayoutOrder = tier
			row.Parent = trackList
			corner(row, 4)

			local status = "locked"
			if freeReady or premReady then
				status = "READY"
			elseif reached then
				status = "claimed"
				if (freeR and not freeClaimed) or (premR and not premClaimed and not premium) then
					status = if premium then "partial" else "free done / need Prem"
				end
			end

			local freeTxt = formatReward(freeR)
			local premTxt = formatReward(premR)
			local lab = Instance.new("TextLabel")
			lab.BackgroundTransparency = 1
			lab.Position = UDim2.fromOffset(6, 0)
			lab.Size = UDim2.new(1, -12, 1, 0)
			lab.Font = Enum.Font.Gotham
			lab.TextSize = 11
			lab.TextXAlignment = Enum.TextXAlignment.Left
			lab.TextColor3 = if (freeReady or premReady) then Constants.Colors.Cash else Constants.Colors.Muted
			lab.Text = string.format(
				"L%d  Free:%s  Prem:%s  [%s]",
				tier,
				if freeTxt ~= "" then freeTxt else "-",
				if premTxt ~= "" then premTxt else "-",
				status
			)
			lab.Parent = row
		end
	end
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
		local claimFree = tonumber(bpState.ClaimableFree) or 0
		local claimPrem = tonumber(bpState.ClaimablePremium) or 0
		bpLabel.Text = string.format(
			"BP L%d  XP %d/%d  %s\nClaimable: %d free · %d premium",
			tonumber(bpState.Level) or 0,
			tonumber(bpState.XP) or 0,
			tonumber(bpState.XPPerLevel) or 1000,
			if bpState.Premium then "PREMIUM" else "Free (admin grantpremium / shop PremiumPass)",
			claimFree,
			claimPrem
		)
	end
	if bpClaimHint then
		if typeof(bpState) == "table" then
			local cf = tonumber(bpState.ClaimableFree) or 0
			local cp = tonumber(bpState.ClaimablePremium) or 0
			if cf + cp > 0 then
				bpClaimHint.Text = string.format("Tap CLAIM ALL — %d rewards ready", cf + cp)
				bpClaimHint.TextColor3 = Constants.Colors.Cash
			else
				bpClaimHint.Text = "No unclaimed rewards at current BP level"
				bpClaimHint.TextColor3 = Constants.Colors.Muted
			end
		end
	end
	if clanLabel and typeof(clanState) == "table" then
		if clanState.ClanId then
			clanLabel.Text = string.format(
				"Clan [%s] %s (%d)\nId: %s%s",
				tostring(clanState.Tag or "?"),
				tostring(clanState.Name or "?"),
				tonumber(clanState.MemberCount) or 0,
				tostring(clanState.ClanId),
				if clanState.Persisted == false then "\n(session-only — enable API Services)" else ""
			)
		else
			clanLabel.Text = "Not in a clan — create one below"
		end
	end
	rebuildTrackPreview()
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

	local scale = Instance.new("UIScale")
	scale.Name = "MobileScale"
	scale.Parent = screen
	local function updateScale()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local size = cam.ViewportSize
		scale.Scale = math.clamp(math.min(size.X, size.Y) / 900, 0.65, 1.1)
	end
	updateScale()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
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
	panel.Size = UDim2.fromOffset(480, 560)
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
		y += 22
	end
	local function body(h: number?): TextLabel
		local lab = Instance.new("TextLabel")
		lab.BackgroundTransparency = 1
		lab.Position = UDim2.fromOffset(16, y)
		lab.Size = UDim2.new(1, -32, 0, h or 40)
		lab.Font = Enum.Font.Gotham
		lab.TextSize = 12
		lab.TextWrapped = true
		lab.TextXAlignment = Enum.TextXAlignment.Left
		lab.TextYAlignment = Enum.TextYAlignment.Top
		lab.TextColor3 = Constants.Colors.Muted
		lab.Text = "..."
		lab.Parent = panel
		y += (h or 40) + 4
		return lab
	end
	local function btn(label: string, w: number, cb: () -> ()): TextButton
		local b = Instance.new("TextButton")
		b.Position = UDim2.fromOffset(16, y)
		b.Size = UDim2.fromOffset(w, 30)
		b.BackgroundColor3 = Constants.Colors.Accent
		b.Font = Enum.Font.GothamBold
		b.TextSize = 12
		b.TextColor3 = Constants.Colors.Text
		b.Text = label
		b.BorderSizePixel = 0
		corner(b, 6)
		b.Parent = panel
		b.MouseButton1Click:Connect(cb)
		return b
	end

	section("PRESTIGE")
	prestigeLabel = body(32)
	btn("PRESTIGE NOW", 200, function()
		Remotes.GetEvent(Constants.RemoteNames.RequestPrestige):FireServer()
	end)
	y += 36

	section("BATTLE PASS")
	bpLabel = body(44)
	bpClaimHint = body(18)
	btn("CLAIM ALL FREE", 150, function()
		-- level 0 = ClaimAll on server
		Remotes.GetEvent(Constants.RemoteNames.RequestClaimBattlePassReward):FireServer(0, "free")
	end)
	local premBtn = btn("CLAIM ALL PREMIUM", 170, function()
		if typeof(bpState) == "table" and not bpState.Premium then
			return
		end
		Remotes.GetEvent(Constants.RemoteNames.RequestClaimBattlePassReward):FireServer(0, "premium")
	end)
	premBtn.Position = UDim2.fromOffset(176, y)
	y += 36

	local trackTitle = Instance.new("TextLabel")
	trackTitle.BackgroundTransparency = 1
	trackTitle.Position = UDim2.fromOffset(16, y)
	trackTitle.Size = UDim2.new(1, -32, 0, 16)
	trackTitle.Font = Enum.Font.GothamBold
	trackTitle.TextSize = 11
	trackTitle.TextXAlignment = Enum.TextXAlignment.Left
	trackTitle.TextColor3 = Constants.Colors.Muted
	trackTitle.Text = "Reward track (ready / upcoming)"
	trackTitle.Parent = panel
	y += 18

	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromOffset(12, y)
	scroll.Size = UDim2.new(1, -24, 0, 110)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panel
	trackList = scroll
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 3)
	layout.Parent = scroll
	y += 118

	section("CLAN")
	clanLabel = body(48)
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
	btn("CREATE CLAN", 200, function()
		Remotes.GetEvent(Constants.RemoteNames.RequestCreateClan):FireServer(nameBox.Text, tagBox.Text)
	end)
	y += 36
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
	btn("JOIN CLAN", 140, function()
		Remotes.GetEvent(Constants.RemoteNames.RequestJoinClan):FireServer(joinBox.Text)
	end)
	local leaveBtn = btn("LEAVE CLAN", 140, function()
		Remotes.GetEvent(Constants.RemoteNames.RequestLeaveClan):FireServer()
	end)
	leaveBtn.Position = UDim2.fromOffset(166, y)

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
