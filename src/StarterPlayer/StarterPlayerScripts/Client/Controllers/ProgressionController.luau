--!strict
--[[ Progression UI — Prestige + Battle Pass + Clan + Clan War (key K / PROGRESS) ]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)

local ProgressionController = {}

local player = Players.LocalPlayer
local menuOpen = false
local screenGui: ScreenGui? = nil
local prestigeLabel: TextLabel? = nil
local bpLabel: TextLabel? = nil
local bpClaimHint: TextLabel? = nil
local bpBarFill: Frame? = nil
local clanLabel: TextLabel? = nil
local warLabel: TextLabel? = nil
local scoreboardLabel: TextLabel? = nil
local trackList: ScrollingFrame? = nil
local warIdBox: TextBox? = nil
local prestigeState: any = nil
local bpState: any = nil
local clanState: any = nil
local warState: any = nil

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
	local maxRows = 14
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
		local skip = (not interesting) and (rows > 0 or tier > level + 3)
		if not skip then
			rows += 1
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -6, 0, 28)
			row.BackgroundColor3 = Constants.Colors.Background
			row.BorderSizePixel = 0
			row.LayoutOrder = tier
			row.Parent = trackList
			UIUtil.Corner(row, 4)

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
			lab.Size = UDim2.new(1, -70, 1, 0)
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

			if freeReady then
				local claimBtn = Instance.new("TextButton")
				claimBtn.AnchorPoint = Vector2.new(1, 0.5)
				claimBtn.Position = UDim2.new(1, -4, 0.5, 0)
				claimBtn.Size = UDim2.fromOffset(52, 22)
				claimBtn.BackgroundColor3 = Constants.Colors.Accent
				claimBtn.Font = Enum.Font.GothamBold
				claimBtn.TextSize = 10
				claimBtn.TextColor3 = Constants.Colors.Text
				claimBtn.Text = "CLAIM"
				claimBtn.BorderSizePixel = 0
				UIUtil.Corner(claimBtn, 4)
				claimBtn.Parent = row
				local claimTier = tier
				claimBtn.MouseButton1Click:Connect(function()
					Remotes.GetEvent(Constants.RemoteNames.RequestClaimBattlePassReward):FireServer(claimTier, "free")
				end)
			elseif premReady then
				local claimBtn = Instance.new("TextButton")
				claimBtn.AnchorPoint = Vector2.new(1, 0.5)
				claimBtn.Position = UDim2.new(1, -4, 0.5, 0)
				claimBtn.Size = UDim2.fromOffset(52, 22)
				claimBtn.BackgroundColor3 = Constants.Colors.Gold
				claimBtn.Font = Enum.Font.GothamBold
				claimBtn.TextSize = 10
				claimBtn.TextColor3 = Constants.Colors.Background
				claimBtn.Text = "CLAIM"
				claimBtn.BorderSizePixel = 0
				UIUtil.Corner(claimBtn, 4)
				claimBtn.Parent = row
				local claimTier = tier
				claimBtn.MouseButton1Click:Connect(function()
					Remotes.GetEvent(Constants.RemoteNames.RequestClaimBattlePassReward):FireServer(claimTier, "premium")
				end)
			end
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
		local xp = tonumber(bpState.XP) or 0
		local need = tonumber(bpState.XPPerLevel) or 1000
		bpLabel.Text = string.format(
			"BP L%d  XP %d/%d  %s\nClaimable: %d free · %d premium",
			tonumber(bpState.Level) or 0,
			xp,
			need,
			if bpState.Premium then "PREMIUM" else "Free (shop PremiumPass / admin)",
			claimFree,
			claimPrem
		)
		if bpBarFill and need > 0 then
			bpBarFill.Size = UDim2.fromScale(math.clamp(xp / need, 0, 1), 1)
		end
	end
	if bpClaimHint then
		if typeof(bpState) == "table" then
			local cf = tonumber(bpState.ClaimableFree) or 0
			local cp = tonumber(bpState.ClaimablePremium) or 0
			if cf + cp > 0 then
				bpClaimHint.Text = string.format("Tap CLAIM ALL or CLAIM on a READY row — %d ready", cf + cp)
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
	if warLabel then
		if typeof(warState) == "table" then
			local war = warState.War
			local cd = tonumber(warState.DeclareCooldownLeft) or 0
			if typeof(war) == "table" and war.Active then
				local left = math.max(0, (tonumber(war.EndUnix) or 0) - os.time())
				warLabel.Text = string.format(
					"WAR ACTIVE  %s vs %s\nScore %d – %d  ·  %dm left",
					tostring(war.AttackerName or war.AttackerClanId),
					tostring(war.DefenderName or war.DefenderClanId),
					tonumber(war.AttackerScore) or 0,
					tonumber(war.DefenderScore) or 0,
					math.floor(left / 60)
				)
				warLabel.TextColor3 = Color3.fromRGB(230, 160, 60)
			elseif typeof(war) == "table" and war.Settled then
				warLabel.Text = string.format(
					"Last war settled · Winner: %s\nCooldown: %ds before next declare",
					tostring(war.WinnerClanId or "draw"),
					cd
				)
				warLabel.TextColor3 = Constants.Colors.Muted
			else
				local rewards = warState.Rewards
				local winCash = if typeof(rewards) == "table" then tonumber(rewards.WinCash) or 0 else 0
				warLabel.Text = string.format(
					"No active war. Leader declares vs clan Id.\nWin ≈ $%d · cooldown %ds · min members %d",
					winCash,
					cd,
					tonumber(warState.MinMembers) or 2
				)
				warLabel.TextColor3 = Constants.Colors.Muted
			end
		else
			warLabel.Text = "War state loading..."
		end
	end
	if scoreboardLabel and typeof(warState) == "table" then
		local board = warState.Scoreboard
		if typeof(board) == "table" and #board > 0 then
			local lines = { "Global war scoreboard:" }
			for i, row in ipairs(board) do
				if i > 5 then
					break
				end
				table.insert(lines, string.format("  %d. %s — %d", i, tostring(row.Name or row.ClanId), tonumber(row.Score) or 0))
			end
			scoreboardLabel.Text = table.concat(lines, "\n")
		else
			scoreboardLabel.Text = "Scoreboard empty — capture territories with a clan"
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
	screen.Parent = player:WaitForChild("PlayerGui")
	UIUtil.PrepareScreen(screen, false)
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
	UIUtil.Corner(toggle, 8)
	UIUtil.Stroke(toggle)
	toggle.Parent = screen
	toggle.MouseButton1Click:Connect(function()
		setOpen(not menuOpen)
	end)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(500, 620)
	panel.BackgroundColor3 = Constants.Colors.Panel
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screen
	UIUtil.Corner(panel, 10)
	UIUtil.Stroke(panel)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Content"
	scroll.Position = UDim2.fromOffset(0, 44)
	scroll.Size = UDim2.new(1, 0, 1, -52)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.CanvasSize = UDim2.fromOffset(0, 900)
	scroll.Parent = panel

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
	UIUtil.Corner(close, 6)
	close.Parent = panel
	close.MouseButton1Click:Connect(function()
		setOpen(false)
	end)

	local y = 8
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
		lab.Parent = scroll
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
		lab.Parent = scroll
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
		UIUtil.Corner(b, 6)
		b.Parent = scroll
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
	-- XP bar
	local bpBg = Instance.new("Frame")
	bpBg.Position = UDim2.fromOffset(16, y)
	bpBg.Size = UDim2.new(1, -32, 0, 12)
	bpBg.BackgroundColor3 = Constants.Colors.Background
	bpBg.BorderSizePixel = 0
	bpBg.Parent = scroll
	UIUtil.Corner(bpBg, 4)
	bpBarFill = Instance.new("Frame")
	bpBarFill.Size = UDim2.fromScale(0, 1)
	bpBarFill.BackgroundColor3 = Constants.Colors.XP
	bpBarFill.BorderSizePixel = 0
	bpBarFill.Parent = bpBg
	UIUtil.Corner(bpBarFill, 4)
	y += 16
	bpClaimHint = body(18)
	btn("CLAIM ALL FREE", 150, function()
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
	trackTitle.Text = "Reward track (CLAIM on READY rows)"
	trackTitle.Parent = scroll
	y += 18

	local trackScroll = Instance.new("ScrollingFrame")
	trackScroll.Position = UDim2.fromOffset(12, y)
	trackScroll.Size = UDim2.new(1, -24, 0, 110)
	trackScroll.BackgroundTransparency = 1
	trackScroll.BorderSizePixel = 0
	trackScroll.ScrollBarThickness = 4
	trackScroll.CanvasSize = UDim2.fromOffset(0, 0)
	trackScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	trackScroll.Parent = scroll
	trackList = trackScroll
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 3)
	layout.Parent = trackScroll
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
	UIUtil.Corner(nameBox, 6)
	nameBox.Parent = scroll
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
	UIUtil.Corner(tagBox, 6)
	tagBox.Parent = scroll
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
	UIUtil.Corner(joinBox, 6)
	joinBox.Parent = scroll
	y += 36
	btn("JOIN CLAN", 140, function()
		Remotes.GetEvent(Constants.RemoteNames.RequestJoinClan):FireServer(joinBox.Text)
	end)
	local leaveBtn = btn("LEAVE CLAN", 140, function()
		Remotes.GetEvent(Constants.RemoteNames.RequestLeaveClan):FireServer()
	end)
	leaveBtn.Position = UDim2.fromOffset(166, y)
	y += 40

	section("CLAN WAR")
	warLabel = body(52)
	scoreboardLabel = body(72)
	warIdBox = Instance.new("TextBox")
	warIdBox.Position = UDim2.fromOffset(16, y)
	warIdBox.Size = UDim2.fromOffset(260, 28)
	warIdBox.BackgroundColor3 = Constants.Colors.Background
	warIdBox.Font = Enum.Font.Gotham
	warIdBox.TextSize = 12
	warIdBox.TextColor3 = Constants.Colors.Text
	warIdBox.PlaceholderText = "Enemy clan Id to declare war"
	warIdBox.Text = ""
	warIdBox.ClearTextOnFocus = false
	warIdBox.BorderSizePixel = 0
	UIUtil.Corner(warIdBox, 6)
	warIdBox.Parent = scroll
	y += 36
	btn("DECLARE WAR", 160, function()
		if warIdBox and warIdBox.Text ~= "" then
			Remotes.GetEvent(Constants.RemoteNames.RequestDeclareClanWar):FireServer(warIdBox.Text)
		end
	end)
	y += 40
	scroll.CanvasSize = UDim2.fromOffset(0, y + 20)

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
	Remotes.GetEvent(Constants.RemoteNames.ClanWarStateUpdate).OnClientEvent:Connect(function(payload)
		warState = payload
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
