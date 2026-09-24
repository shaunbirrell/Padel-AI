--!strict
--[[ Progression UI — Prestige + Battle Pass + Clan + Clan War (the rail's Rebirth tile / K).
	v70 "clean screen" (spec §3.7 / §3.8): the season banner left the HUD — the season line sits under this
	panel's title (SeasonStateUpdate). The near-rebirth banner became the Rebirth tile's "!" badge. A registered
	Modal panel (HudLayout id "Rebirth") with the black dim; one HUD scale + safe area; every tappable ≥ 44 real
	px on touch. Server-authoritative: every button only fires its request remote. ]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)
local HudConfig = require(Shared.Configs.HudConfig)
local ProgressionUI = require(script.ProgressionUI)
local ProgressionBattlePass = require(script.ProgressionBattlePass)

local PanelShell = require(script.Parent.Parent.Modules.PanelShell)

local ProgressionController = {}

local PANEL_ID = "Rebirth"

local player = Players.LocalPlayer
local isTouch = UserInputService.TouchEnabled
local menuOpen = false
local screenGui: ScreenGui? = nil
local shell: PanelShell.Shell? = nil
local seasonLabel: TextLabel? = nil
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
local prestigeState: any = nil
local bpState: any = nil
local clanState: any = nil
local warState: any = nil

-- non-blocking request (Remotes.FireServer polls ≤ 3 s for the remote; never waits forever)
local function fire(remoteName: string, ...: any)
	task.spawn(Remotes.FireServer, remoteName, ...)
end

local function rebuildTrackPreview()
	ProgressionBattlePass.RebuildTrackPreview(trackList, bpState)
	-- v70: the shared track builder makes 40 v rows with 36 v CLAIM buttons and 10-11 v text; lift them to the
	-- panel's touch target / text floor (≥ 44 real px targets, ≥ 11 px text)
	local list = trackList
	if not list then
		return
	end
	local tap = PanelShell.TouchMinV()
	for _, row in ipairs(list:GetChildren()) do
		if row:IsA("Frame") then
			if isTouch then
				row.Size = UDim2.new(row.Size.X.Scale, row.Size.X.Offset, 0, tap + 8)
			end
			for _, d in ipairs(row:GetChildren()) do
				if d:IsA("TextButton") then
					d.TextSize = PanelShell.Text(d.TextSize)
					if isTouch then
						d.Size = UDim2.fromOffset(math.max(d.Size.X.Offset, 96), tap)
					end
				elseif d:IsA("TextLabel") then
					d.TextSize = PanelShell.Text(d.TextSize)
					d.TextTruncate = Enum.TextTruncate.AtEnd
					if isTouch then
						d.Size = UDim2.new(1, -112, 1, 0)
					end
				end
			end
		end
	end
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
			prestigeConfirm.Text = string.format("Reach Lv %d to unlock Rebirth · Fee: none · +10%% cash forever · keep all Robux items.", need)
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
	local sh = shell
	if sh then
		sh.Sync(open)
	end
end

-- SeasonStateUpdate → the line under the title (was the HUD's SeasonLabel banner)
local function applySeason(payload: any)
	local lab = seasonLabel
	if not lab or typeof(payload) ~= "table" then
		return
	end
	local name = tostring(payload.DisplayName or payload.SeasonId or "Season")
	if payload.Active == true then
		local xpB = tonumber(payload.XPBonusMult) or 1
		local cashB = tonumber(payload.CashBonusMult) or 1
		lab.TextColor3 = Constants.Colors.Cash
		lab.Text = string.format("%s  ·  XP×%.2f  Cash×%.2f", name, xpB, cashB)
	else
		lab.TextColor3 = Constants.Colors.Muted
		lab.Text = name .. "  ·  ENDED"
	end
	lab.Visible = true
end

function ProgressionController.Init()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireProgression"
	PanelShell.Screen(screen) -- DisplayOrder 60 (Panels), one HUD scale + safe area
	screen.Parent = player:WaitForChild("PlayerGui")
	screenGui = screen

	local TAP = PanelShell.TouchMinV()

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = if isTouch then UDim2.new(0.94, 0, 1, -16) else UDim2.fromOffset(540, 660)
	panel.BackgroundColor3 = Constants.Colors.Panel
	panel.BorderSizePixel = 0
	panel.Active = true
	panel.Visible = false
	panel.Parent = screen
	UIUtil.Corner(panel, 12)
	UIUtil.Stroke(panel)
	do
		local sizeConstraint = Instance.new("UISizeConstraint")
		sizeConstraint.MinSize = Vector2.new(280, 300)
		sizeConstraint.MaxSize = if isTouch then Vector2.new(820, 900) else Vector2.new(540, 660)
		sizeConstraint.Parent = panel
	end

	local title = PanelShell.Title(panel, if isTouch then "Rebirth / Progression" else "Progression")

	-- v70: the season line (was the HUD's top-centre SeasonLabel banner)
	local seasonSize = PanelShell.Text(13)
	local season = Instance.new("TextLabel")
	season.Name = "SeasonLabel"
	season.BackgroundTransparency = 1
	season.Position = UDim2.fromOffset(16, title.Position.Y.Offset + title.Size.Y.Offset - 2)
	season.Size = UDim2.new(1, -(TAP + 28), 0, seasonSize + 4)
	season.Font = Enum.Font.GothamBold
	season.TextSize = seasonSize
	season.TextXAlignment = Enum.TextXAlignment.Left
	season.TextTruncate = Enum.TextTruncate.AtEnd
	season.TextColor3 = Constants.Colors.Muted
	season.Text = ""
	season.Visible = false
	season.Parent = panel
	seasonLabel = season

	PanelShell.CloseButton(panel, function()
		setOpen(false)
	end)

	local headerH = math.max(TAP + 8, season.Position.Y.Offset + seasonSize + 10)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Content"
	scroll.Position = UDim2.fromOffset(0, headerH)
	scroll.Size = UDim2.new(1, 0, 1, -(headerH + 8))
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = if isTouch then 6 else 5
	scroll.CanvasSize = UDim2.fromOffset(0, 1100)
	scroll.Parent = panel

	local y = 8
	local sectionSize = PanelShell.Text(14)
	local bodySize = PanelShell.Text(12)
	local bodyK = bodySize / 12 -- body heights were designed for 12 v text
	local function section(text: string)
		local lab = Instance.new("TextLabel")
		lab.BackgroundTransparency = 1
		lab.Position = UDim2.fromOffset(16, y)
		lab.Size = UDim2.new(1, -32, 0, sectionSize + 6)
		lab.Font = Enum.Font.GothamBold
		lab.TextSize = sectionSize
		lab.TextXAlignment = Enum.TextXAlignment.Left
		lab.TextColor3 = Constants.Colors.Accent
		lab.Text = text
		lab.Parent = scroll
		y += sectionSize + 8
	end
	local function body(h: number?): TextLabel
		local hh = math.ceil((h or 40) * bodyK)
		local lab = Instance.new("TextLabel")
		lab.BackgroundTransparency = 1
		lab.Position = UDim2.fromOffset(16, y)
		lab.Size = UDim2.new(1, -32, 0, hh)
		lab.Font = Enum.Font.GothamMedium
		lab.TextSize = bodySize
		lab.TextWrapped = true
		lab.TextXAlignment = Enum.TextXAlignment.Left
		lab.TextYAlignment = Enum.TextYAlignment.Top
		lab.TextColor3 = Constants.Colors.Muted
		lab.Text = "..."
		lab.Parent = scroll
		y += hh + 4
		return lab
	end
	-- a button on the current row; on touch it is TAP (≥ 44 real px) tall
	local function btn(label: string, w: number, cb: () -> ()): TextButton
		local b = Instance.new("TextButton")
		b.Position = UDim2.fromOffset(16, y)
		b.Size = UDim2.fromOffset(math.max(w, if isTouch then 180 else w), if isTouch then TAP else 36)
		b.BackgroundColor3 = Constants.Colors.Accent
		b.Font = Enum.Font.GothamBold
		b.TextSize = PanelShell.Text(13)
		b.TextColor3 = Constants.Colors.Text
		b.Text = label
		b.BorderSizePixel = 0
		b.Active = true
		UIUtil.Corner(b, 8)
		b.Parent = scroll
		UIUtil.EnsureMinTouch(b, if isTouch then TAP else 36)
		b.Activated:Connect(cb)
		return b
	end
	local rowH = if isTouch then TAP else 36
	local function textBox(placeholder: string, x: number, w: UDim): TextBox
		local box = Instance.new("TextBox")
		box.Position = UDim2.fromOffset(x, y)
		box.Size = UDim2.new(w.Scale, w.Offset, 0, if isTouch then TAP else 32)
		box.BackgroundColor3 = Constants.Colors.Background
		box.Font = Enum.Font.GothamMedium
		box.TextSize = PanelShell.Text(13)
		box.TextColor3 = Constants.Colors.Text
		box.PlaceholderText = placeholder
		box.PlaceholderColor3 = Constants.Colors.Muted
		box.Text = ""
		box.ClearTextOnFocus = false
		box.BorderSizePixel = 0
		UIUtil.Corner(box, 8)
		box.Parent = scroll
		return box
	end

	section("REBIRTH / PRESTIGE")
	prestigeLabel = body(40)
	unlockLabel = body(110)
	prestigeConfirm = body(52)
	-- Competitor rebirth trust cue (Entitlements / GamePasses never cleared on prestige)
	do
		local keepH = if isTouch then 44 else 34
		local keep = Instance.new("TextLabel")
		keep.Name = "KeepRobuxBanner"
		keep.Position = UDim2.fromOffset(16, y)
		keep.Size = UDim2.new(1, -32, 0, keepH)
		keep.BackgroundColor3 = Color3.fromRGB(28, 72, 36)
		keep.BackgroundTransparency = 0.05
		keep.BorderSizePixel = 0
		keep.Font = HudConfig.Fonts.Display
		keep.TextSize = PanelShell.Text(if isTouch then 18 else 16)
		keep.TextColor3 = Constants.Colors.GoldBright
		keep.Text = "★ Keep all your Robux Items!"
		keep.TextXAlignment = Enum.TextXAlignment.Center
		keep.Parent = scroll
		UIUtil.Corner(keep, 8)
		UIUtil.Stroke(keep, Constants.Colors.Gold, 2).ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		prestigeKeepBanner = keep
		y += keepH + 6
	end
	local rebirthBtn = btn(if isTouch then "CONFIRM REBIRTH (+10% CASH)" else "CONFIRM REBIRTH", 220, function()
		print("[Progression] CONFIRM REBIRTH tap")
		fire(Constants.RemoteNames.RequestPrestige)
	end)
	rebirthBtn.BackgroundColor3 = Constants.Colors.Gunmetal
	rebirthBtn.TextColor3 = Constants.Colors.Gold
	UIUtil.Stroke(rebirthBtn, Constants.Colors.Gold, 1.5).ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	if isTouch then
		rebirthBtn.Size = UDim2.new(1, -32, 0, TAP)
	end
	y += rowH + 10

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
	local fillBar = Instance.new("Frame")
	fillBar.Size = UDim2.fromScale(0, 1)
	fillBar.BackgroundColor3 = Constants.Colors.XP
	fillBar.BorderSizePixel = 0
	fillBar.Parent = bpBg
	UIUtil.Corner(fillBar, 4)
	bpBarFill = fillBar
	y += 16
	bpClaimHint = body(18)
	local freeClaim = btn("CLAIM ALL FREE", 150, function()
		print("[Progression] CLAIM ALL FREE tap")
		fire(Constants.RemoteNames.RequestClaimBattlePassReward, 0, "free")
	end)
	local premBtn = btn("CLAIM ALL PREMIUM", 170, function()
		print("[Progression] CLAIM ALL PREMIUM tap")
		if typeof(bpState) == "table" and not bpState.Premium then
			return
		end
		fire(Constants.RemoteNames.RequestClaimBattlePassReward, 0, "premium")
	end)
	if isTouch then
		-- side by side, each half the row
		freeClaim.Size = UDim2.new(0.5, -20, 0, TAP)
		premBtn.Position = UDim2.new(0.5, 4, 0, y)
		premBtn.Size = UDim2.new(0.5, -20, 0, TAP)
		y += TAP + 10
	else
		premBtn.Position = UDim2.fromOffset(176, y)
		y += 36 + 6
	end

	local trackTitle = Instance.new("TextLabel")
	trackTitle.BackgroundTransparency = 1
	trackTitle.Position = UDim2.fromOffset(16, y)
	trackTitle.Size = UDim2.new(1, -32, 0, bodySize + 4)
	trackTitle.Font = Enum.Font.GothamBold
	trackTitle.TextSize = bodySize
	trackTitle.TextXAlignment = Enum.TextXAlignment.Left
	trackTitle.TextColor3 = Constants.Colors.Muted
	trackTitle.Text = "Reward track (CLAIM on READY rows)"
	trackTitle.Parent = scroll
	y += bodySize + 6

	local trackH = if isTouch then 3 * (TAP + 11) else 110
	local trackScroll = Instance.new("ScrollingFrame")
	trackScroll.Position = UDim2.fromOffset(12, y)
	trackScroll.Size = UDim2.new(1, -24, 0, trackH)
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
	y += trackH + 8

	section("CLAN")
	clanLabel = body(48)
	local nameBox = textBox("Clan name", 16, if isTouch then UDim.new(0.6, -20) else UDim.new(0, 200))
	local tagBox = textBox("TAG", if isTouch then 0 else 224, if isTouch then UDim.new(0.4, -20) else UDim.new(0, 80))
	if isTouch then
		tagBox.Position = UDim2.new(0.6, 4, 0, y)
	end
	y += (if isTouch then TAP else 32) + 6
	btn("CREATE CLAN", 200, function()
		fire(Constants.RemoteNames.RequestCreateClan, nameBox.Text, tagBox.Text)
	end)
	y += rowH + 8
	local joinBox = textBox("Clan Id to join", 16, if isTouch then UDim.new(1, -32) else UDim.new(0, 280))
	y += (if isTouch then TAP else 32) + 6
	btn("JOIN CLAN", 140, function()
		fire(Constants.RemoteNames.RequestJoinClan, joinBox.Text)
	end)
	local leaveBtn = btn("LEAVE CLAN", 140, function()
		fire(Constants.RemoteNames.RequestLeaveClan)
	end)
	leaveBtn.Position = if isTouch then UDim2.new(0, 16 + 180 + 8, 0, y) else UDim2.fromOffset(166, y)
	y += rowH + 10

	section("CLAN WAR")
	warLabel = body(52)
	scoreboardLabel = body(72)
	local warBox = textBox("Enemy clan Id to declare war", 16, if isTouch then UDim.new(1, -32) else UDim.new(0, 260))
	y += (if isTouch then TAP else 32) + 6
	btn("DECLARE WAR", 160, function()
		if warBox.Text ~= "" then
			fire(Constants.RemoteNames.RequestDeclareClanWar, warBox.Text)
		end
	end)
	y += rowH + 10
	scroll.CanvasSize = UDim2.fromOffset(0, y + 20)

	shell = PanelShell.Attach({
		Id = PANEL_ID,
		Screen = screen,
		Panel = panel,
		IsOpen = function(): boolean
			return menuOpen
		end,
		Close = function()
			setOpen(false)
		end,
	})

	Remotes.BindEvent(Constants.RemoteNames.PrestigeStateUpdate, function(payload: any)
		prestigeState = payload
		refreshLabels()
	end)
	Remotes.BindEvent(Constants.RemoteNames.BattlePassStateUpdate, function(payload: any)
		bpState = payload
		refreshLabels()
	end)
	Remotes.BindEvent(Constants.RemoteNames.ClanStateUpdate, function(payload: any)
		clanState = payload
		refreshLabels()
	end)
	Remotes.BindEvent(Constants.RemoteNames.ClanWarStateUpdate, function(payload: any)
		warState = payload
		refreshLabels()
	end)
	Remotes.BindEvent(Constants.RemoteNames.SeasonStateUpdate, applySeason)

	local rebirthKey: Enum.KeyCode = HudConfig.Keys.Rebirth or Enum.KeyCode.K
	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then
			return
		end
		if input.KeyCode == rebirthKey then
			setOpen(not menuOpen)
		end
	end)
	refreshLabelsImmediate()
end

function ProgressionController.Toggle()
	local sh = shell
	if not menuOpen and sh and sh.TapThrough() then
		return
	end
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
