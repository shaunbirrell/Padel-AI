--!strict
--[[ Progression UI — Prestige + Battle Pass + Clan + Clan War (key K / PROGRESS) ]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)
local ProgressionUI = require(script.ProgressionUI)
local ProgressionBattlePass = require(script.ProgressionBattlePass)

local ProgressionController = {}

local player = Players.LocalPlayer
local isTouch = UserInputService.TouchEnabled
local menuOpen = false
local screenGui: ScreenGui? = nil
local prestigeLabel: TextLabel? = nil
local unlockLabel: TextLabel? = nil
local prestigeConfirm: TextLabel? = nil
local prestigeKeepBanner: TextLabel? = nil
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

local function rebuildTrackPreview()
	ProgressionBattlePass.RebuildTrackPreview(trackList, bpState)
end

local debouncedRefresh = ProgressionUI.Debounce(0.12)

local function refreshLabelsImmediate()
	if prestigeLabel then
		if typeof(prestigeState) == "table" then
			local p = tonumber(prestigeState.Prestige) or 0
			local cur = tonumber(prestigeState.CashMultPercent)
				or math.floor(p * (tonumber(prestigeState.CashBonusPerLevel) or 0.10) * 100)
			local nxt = tonumber(prestigeState.NextCashMultPercent)
				or math.floor((p + 1) * (tonumber(prestigeState.CashBonusPerLevel) or 0.10) * 100)
			prestigeLabel.Text = string.format(
				"Rebirth P%d  |  Cash +%d%% now  |  Next +%d%%  |  Need Lv %d  |  Can: %s",
				p,
				cur,
				nxt,
				tonumber(prestigeState.MinLevel) or 40,
				if prestigeState.CanPrestige then "YES" else "no"
			)
		else
			prestigeLabel.Text = "Rebirth data loading… reach max level to prestige (+10% cash / rebirth)."
		end
	end
	if unlockLabel then
		if typeof(prestigeState) == "table" and typeof(prestigeState.UnlockTrack) == "table" then
			local lines = { "Unlock track:" }
			for _, u in ipairs(prestigeState.UnlockTrack) do
				local mark = if u.Unlocked then "✓" else "·"
				table.insert(
					lines,
					string.format("  %s P%d — %s", mark, tonumber(u.AtPrestige) or 0, tostring(u.DisplayName or u.Flag))
				)
			end
			if #lines == 1 then
				table.insert(lines, "  (none configured)")
			end
			unlockLabel.Text = table.concat(lines, "\n")
		else
			unlockLabel.Text = "Unlock track loading…"
		end
	end
	if prestigeConfirm then
		if typeof(prestigeState) == "table" and prestigeState.CanPrestige then
			local feeLine = prestigeState.FeeSummary
			if typeof(feeLine) ~= "string" or feeLine == "" then
				local fee = tonumber(prestigeState.CashFee) or 0
				local feePart = if fee > 0 then string.format("Fee $%s", tostring(fee)) else "Fee: none"
				local pct = tonumber(prestigeState.BaseCompletionPercent)
				feeLine = string.format(
					"%s · Cash → $%s after · +%d Gold%s",
					feePart,
					tostring(prestigeState.StartingCashAfter or 10000),
					tonumber(prestigeState.GoldBonusOnPrestige) or 50,
					if pct ~= nil then string.format(" · Base %d%%", math.floor(pct)) else ""
				)
			end
			prestigeConfirm.Text = "Confirm Rebirth: " .. feeLine .. " · +10% cash forever. Keep all Robux purchases / Game Passes."
			prestigeConfirm.TextColor3 = Constants.Colors.Gold
		else
			local need = 40
			if typeof(prestigeState) == "table" then
				need = tonumber(prestigeState.MinLevel) or 40
			end
			prestigeConfirm.Text = string.format("Reach Lv %d to unlock Rebirth. Fee shown here when ready.", need)
			prestigeConfirm.TextColor3 = Constants.Colors.Muted
		end
	end

	if prestigeKeepBanner then
		prestigeKeepBanner.Text = "★ Keep all your Robux Items!"
		prestigeKeepBanner.TextColor3 = Constants.Colors.GoldBright or Constants.Colors.Gold
		prestigeKeepBanner.Visible = true
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
	if bpLabel and typeof(bpState) ~= "table" then
		bpLabel.Text = "Battle Pass loading… play to earn BP XP."
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

local function refreshLabels()
	debouncedRefresh(refreshLabelsImmediate)
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
	screen.DisplayOrder = 60 -- above HUD dock (55); panels must not open behind HUD
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
	toggle.Visible = false -- docked in HUD MobileActionBar
	UIUtil.Corner(toggle, 8)
	UIUtil.Stroke(toggle)
	toggle.Parent = screen
	UIUtil.EnsureMinTouch(toggle, 44)
	toggle.Activated:Connect(function()
		setOpen(not menuOpen)
	end)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = if isTouch then UDim2.new(0.94, 0, 0.82, 0) else UDim2.fromOffset(520, 660)
	panel.BackgroundColor3 = Constants.Colors.Panel
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screen
	UIUtil.Corner(panel, 10)
	UIUtil.Stroke(panel)
	if isTouch then
		local sizeConstraint = Instance.new("UISizeConstraint")
		sizeConstraint.MinSize = Vector2.new(280, 360)
		sizeConstraint.MaxSize = Vector2.new(720, 900)
		sizeConstraint.Parent = panel
	end

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Content"
	scroll.Position = UDim2.fromOffset(0, 44)
	scroll.Size = UDim2.new(1, 0, 1, -52)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.CanvasSize = UDim2.fromOffset(0, 1100)
	scroll.Parent = panel

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -80, 0, 28)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Constants.Colors.Text
	title.Text = if isTouch then "Rebirth / Progression" else "Progression"
	title.Parent = panel

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 10)
	close.Size = UDim2.fromOffset(48, 48)
	close.BackgroundColor3 = Constants.Colors.Background
	close.Font = Enum.Font.GothamBold
	close.Text = "X"
	close.TextColor3 = Constants.Colors.Text
	close.BorderSizePixel = 0
	UIUtil.Corner(close, 6)
	close.Parent = panel
	UIUtil.EnsureMinTouch(close, 48)
	close.Activated:Connect(function()
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
		b.Size = UDim2.fromOffset(math.max(w, if isTouch then 160 else w), if isTouch then 44 else 36)
		b.BackgroundColor3 = Constants.Colors.Accent
		b.Font = Enum.Font.GothamBold
		b.TextSize = if isTouch then 13 else 12
		b.TextColor3 = Constants.Colors.Text
		b.Text = label
		b.BorderSizePixel = 0
		UIUtil.Corner(b, 6)
		b.Parent = scroll
		UIUtil.EnsureMinTouch(b, 44)
		b.Activated:Connect(cb)
		return b
	end

	section("REBIRTH / PRESTIGE")
	prestigeLabel = body(40)
	unlockLabel = body(110)
	prestigeConfirm = body(52)
	-- Competitor rebirth trust cue (Entitlements / GamePasses never cleared on prestige)
	do
		local keep = Instance.new("TextLabel")
		keep.Name = "KeepRobuxBanner"
		keep.Position = UDim2.fromOffset(16, y)
		keep.Size = UDim2.new(1, -32, 0, if isTouch then 40 else 32)
		keep.BackgroundColor3 = Color3.fromRGB(28, 72, 36)
		keep.BackgroundTransparency = 0.05
		keep.BorderSizePixel = 0
		keep.Font = Enum.Font.GothamBold
		keep.TextSize = if isTouch then 16 else 15
		keep.TextColor3 = Constants.Colors.GoldBright
		keep.Text = "★ Keep all your Robux Items!"
		keep.TextXAlignment = Enum.TextXAlignment.Center
		keep.Parent = scroll
		UIUtil.Corner(keep, 6)
		UIUtil.Stroke(keep, Constants.Colors.Gold, 2)
		prestigeKeepBanner = keep
		y += if isTouch then 46 else 38
	end
	local rebirthBtn = btn(if isTouch then "CONFIRM REBIRTH (+10% CASH)" else "CONFIRM REBIRTH", 220, function()
		print("[Progression] CONFIRM REBIRTH tap")
		Remotes.GetEvent(Constants.RemoteNames.RequestPrestige):FireServer()
	end)
	rebirthBtn.BackgroundColor3 = Constants.Colors.Gunmetal
	rebirthBtn.TextColor3 = Constants.Colors.Gold
	UIUtil.Stroke(rebirthBtn, Constants.Colors.Gold, 1.5)
	if isTouch then
		rebirthBtn.Size = UDim2.new(1, -32, 0, 52)
		UIUtil.EnsureMinTouch(rebirthBtn, 52)
	end
	y += if isTouch then 60 else 40

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
	local freeClaim = btn("CLAIM ALL FREE", 150, function()
		print("[Progression] CLAIM ALL FREE tap")
		Remotes.GetEvent(Constants.RemoteNames.RequestClaimBattlePassReward):FireServer(0, "free")
	end)
	local premBtn = btn("CLAIM ALL PREMIUM", 170, function()
		print("[Progression] CLAIM ALL PREMIUM tap")
		if typeof(bpState) == "table" and not bpState.Premium then
			return
		end
		Remotes.GetEvent(Constants.RemoteNames.RequestClaimBattlePassReward):FireServer(0, "premium")
	end)
	if isTouch then
		freeClaim.Size = UDim2.new(1, -32, 0, 48)
		y += 52
		premBtn.Position = UDim2.fromOffset(16, y)
		premBtn.Size = UDim2.new(1, -32, 0, 48)
		y += 56
	else
		premBtn.Position = UDim2.fromOffset(176, y)
		y += 36
	end

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


function ProgressionController.Toggle()
	setOpen(not menuOpen)
end

function ProgressionController.Open()
	setOpen(true)
end

function ProgressionController.Close()
	setOpen(false)
end

function ProgressionController.IsOpen(): boolean
	return menuOpen
end

return ProgressionController
