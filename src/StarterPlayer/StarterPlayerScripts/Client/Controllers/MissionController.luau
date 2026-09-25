--!strict
--[[ Phase 6 — Missions UI + daily reward claim.
	v70 "clean screen": the cash pill's SPIN chip moved here — a "FREE SUPPLY SPIN · CLAIM" row at the top of
	the panel (fires RequestClaimSpinner; SpinnerService decides). The rail's Missions badge counts completed-
	unclaimed missions + a claimable daily login + a READY spinner (HUDController). Opened from the rail's
	Missions tile / M (HudConfig.Keys.Missions) / the terminal. A registered Modal panel (HudLayout id "Missions")
	with the black dim; one HUD scale + safe area; every tappable ≥ 44 real px on touch.
	W3 step 2 lane M0: each mission row has ONE right-hand button (MissionConfig.Ui, 112 x 72 v on touch): CLAIM when
	complete, GO while incomplete when the server sent GO targets (e.g. "Rob the Bank"), nothing otherwise (a
	claimed row shows a plain DONE tag). GO closes the panel and points the one objective marker (ObjectiveMarker)
	at the target nearest to the player; it grants nothing — progress and rewards stay on the server. ]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)
local Types = require(Shared.Types)
local DailyRewardConfig = require(Shared.Configs.DailyRewardConfig)
local HudConfig = require(Shared.Configs.HudConfig)
local MissionConfig = require(Shared.Configs.MissionConfig)

local PanelShell = require(script.Parent.Parent.Modules.PanelShell)
local AudioController = require(script.Parent.Parent.Modules.AudioController)
local ObjectiveMarker = require(script.Parent.Parent.Modules.ObjectiveMarker)

local MissionController = {}

local PANEL_ID = "Missions"

local player = Players.LocalPlayer
local isTouch = UserInputService.TouchEnabled
local menuOpen = false
local screenGui: ScreenGui? = nil
local shell: PanelShell.Shell? = nil
local listFrame: ScrollingFrame? = nil
local dailyBtn: TextButton? = nil
local dailyInfo: TextLabel? = nil
local spinBtn: TextButton? = nil
local spinInfo: TextLabel? = nil
local state: Types.MissionStatePayload? = nil

-- spinner (SpinnerStateUpdate: Ready, CooldownRemaining seconds)
local spinnerReady = false
local spinnerReadyAt = 0 -- os.clock() when the cooldown ends
local spinnerKnown = false

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

-- UIUtil.EmptyState at the panel text floor (≥ 11 real px)
local function emptyState(parent: Instance, message: string)
	local lab = UIUtil.EmptyState(parent, message, 0)
	lab.TextSize = PanelShell.Text(14)
	lab.Size = UDim2.new(1, -8, 0, PanelShell.Text(14) * 3 + 8)
	lab.Font = Enum.Font.GothamMedium
end

local function fire(remoteName: string, ...: any)
	task.spawn(Remotes.FireServer, remoteName, ...)
end

local function commas(n: number): string
	local v = math.floor(n)
	local str = tostring(math.abs(v))
	local out = string.reverse((string.gsub(string.reverse(str), "(%d%d%d)", "%1,")))
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return if v < 0 then "-" .. out else out
end

-- ── GO (W3 step 2) ──────────────────────────────────────────────────────────────────────────────────────────────
local MAX_GO_TARGETS = 16

local function finiteCoord(n: any): boolean
	return type(n) == "number" and n == n and n > -1e6 and n < 1e6
end

--[[ The objective-marker target for a mission entry's GO: of the GoTargets the SERVER sent with the entry, the one
	nearest (XZ) to `from` (the player's character; nil → the first valid one), labelled MissionConfig.Go[Go].Short.
	nil when the entry has no usable Go (unknown key, no finite target). Pure; exported for tests. ]]
function MissionController.GoTarget(entry: any, from: Vector3?): ObjectiveMarker.Target?
	if type(entry) ~= "table" or type(entry.Go) ~= "string" or type(entry.GoTargets) ~= "table" then
		return nil
	end
	local gd = MissionConfig.Go[entry.Go]
	if gd == nil then
		return nil
	end
	local best: any = nil
	local bestD = math.huge
	for i, t in ipairs(entry.GoTargets) do
		if i > MAX_GO_TARGETS then
			break
		end
		if type(t) == "table" and finiteCoord(t.X) and finiteCoord(t.Y) and finiteCoord(t.Z) then
			local d = if from then (t.X - from.X) ^ 2 + (t.Z - from.Z) ^ 2 else i
			if d < bestD then
				bestD = d
				best = t
			end
		end
	end
	if best == nil then
		return nil
	end
	return { Short = gd.Short, X = best.X, Y = best.Y, Z = best.Z }
end

-- the character's root, if it is streamed in and spawned (never waited for)
local function rootPosition(): Vector3?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

local onGo: (entry: any) -> () -- set after setOpen (GO closes the panel)

local function formatWait(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	if s >= 3600 then
		return string.format("%dh %02dm", s // 3600, (s % 3600) // 60)
	elseif s >= 60 then
		return string.format("%dm", math.ceil(s / 60))
	end
	return string.format("%ds", s)
end

local function paintSpinner()
	local btn, info = spinBtn, spinInfo
	if not (btn and info) then
		return
	end
	local ready = spinnerReady or (spinnerKnown and os.clock() >= spinnerReadyAt)
	if ready then
		info.Text = "FREE SUPPLY SPIN · ready"
		info.TextColor3 = Constants.Colors.Gold
		btn.Text = "CLAIM"
		btn.BackgroundColor3 = Constants.Colors.Gold
		btn.TextColor3 = Color3.fromRGB(30, 30, 20)
		btn.AutoButtonColor = true
		btn:SetAttribute("WE_Disabled", false)
	else
		info.Text = if spinnerKnown
			then string.format("FREE SUPPLY SPIN · next in %s", formatWait(spinnerReadyAt - os.clock()))
			else "FREE SUPPLY SPIN · checking…"
		info.TextColor3 = Constants.Colors.Muted
		btn.Text = "WAIT"
		btn.BackgroundColor3 = Color3.fromRGB(50, 55, 60)
		btn.TextColor3 = Constants.Colors.Muted
		btn.AutoButtonColor = false
		btn:SetAttribute("WE_Disabled", true)
	end
end

-- a mission row's right-hand button (btnW x btnH v, vertically centred)
local function rowButton(row: Frame, name: string, text: string, bg: Color3, fg: Color3, w: number, h: number): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position = UDim2.new(1, -8, 0.5, 0)
	btn.Size = UDim2.fromOffset(w, h)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = PanelShell.Text(if isTouch then 22 else 16)
	btn.Text = text
	btn.TextColor3 = fg
	btn.BackgroundColor3 = bg
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true
	btn.Active = true
	corner(btn, 8)
	btn.Parent = row
	return btn
end

local function refresh()
	if not listFrame then
		return
	end
	paintSpinner()
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("Frame") or (child:IsA("TextLabel") and child.Name == "EmptyState") then
			child:Destroy()
		end
	end
	if not state then
		emptyState(listFrame, "Loading missions… stand by for server sync.")
		return
	end
	local layout = listFrame:FindFirstChildOfClass("UIListLayout")
	if not layout then
		local l = Instance.new("UIListLayout")
		l.Padding = UDim.new(0, 6)
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.Parent = listFrame
	end

	if #state.Daily == 0 then
		emptyState(listFrame, "No daily missions right now — check back after UTC midnight refresh.")
	end

	local TAP = PanelShell.TouchMinV()
	local titleSize = PanelShell.Text(14)
	local descSize = PanelShell.Text(11)
	local progSize = PanelShell.Text(11)
	local ui = MissionConfig.Ui
	local btnW = if isTouch then ui.ButtonW else ui.DesktopButtonW
	local btnH = if isTouch then math.max(ui.ButtonH, TAP) else TAP
	local rowH = math.max(btnH + 12, 6 + titleSize + 4 + descSize + 6 + progSize + 10)

	for i, mission in ipairs(state.Daily) do
		local row = Instance.new("Frame")
		row.Name = "Mission_" .. tostring(mission.Id)
		row.Size = UDim2.new(1, -8, 0, rowH) -- v37 progress chip
		row.BackgroundColor3 = Constants.Colors.Background
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.Parent = listFrame
		corner(row, 8)

		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Position = UDim2.fromOffset(10, 6)
		title.Size = UDim2.new(1, -(btnW + 28), 0, titleSize + 2)
		title.Font = Enum.Font.GothamBold
		title.TextSize = titleSize
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextColor3 = Constants.Colors.Text
		title.TextTruncate = Enum.TextTruncate.AtEnd
		title.Text = mission.DisplayName
		title.Parent = row

		local desc = Instance.new("TextLabel")
		desc.BackgroundTransparency = 1
		desc.Position = UDim2.fromOffset(10, 6 + titleSize + 4)
		desc.Size = UDim2.new(1, -(btnW + 28), 0, descSize + 2)
		desc.Font = Enum.Font.GothamMedium
		desc.TextSize = descSize
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextColor3 = Constants.Colors.Muted
		desc.Text = mission.Description
		desc.TextTruncate = Enum.TextTruncate.AtEnd
		desc.Parent = row

		-- v37: progress chip bar + clearer reward copy
		local chipY = 6 + titleSize + 4 + descSize + 8
		local chipBg = Instance.new("Frame")
		chipBg.Name = "ProgressChip"
		chipBg.Position = UDim2.fromOffset(10, chipY + 2)
		chipBg.Size = UDim2.new(0.34, 0, 0, progSize - 2)
		chipBg.BackgroundColor3 = Color3.fromRGB(35, 40, 48)
		chipBg.BorderSizePixel = 0
		chipBg.Parent = row
		corner(chipBg, 4)
		local pct = 0
		if mission.Target > 0 then
			pct = math.clamp(mission.Progress / mission.Target, 0, 1)
		end
		local chipFill = Instance.new("Frame")
		chipFill.Size = UDim2.new(pct, 0, 1, 0)
		chipFill.BackgroundColor3 = if mission.Claimed then Constants.Colors.Muted elseif pct >= 1 then Constants.Colors.Cash else Constants.Colors.XP
		chipFill.BorderSizePixel = 0
		chipFill.Parent = chipBg
		corner(chipFill, 4)
		local prog = Instance.new("TextLabel")
		prog.BackgroundTransparency = 1
		prog.Position = UDim2.new(0.34, 18, 0, chipY - 1)
		prog.Size = UDim2.new(0.66, -(btnW + 46), 0, progSize + 4)
		prog.Font = Enum.Font.GothamBold
		prog.TextSize = progSize
		prog.TextXAlignment = Enum.TextXAlignment.Left
		prog.TextColor3 = Constants.Colors.Gold
		local goldBit = if (mission.RewardGold or 0) > 0 then string.format(" · %dg", mission.RewardGold) else ""
		prog.Text = string.format("%d/%d  ★ $%s + %dXP%s", mission.Progress, mission.Target, commas(mission.RewardCash), mission.RewardXP, goldBit)
		prog.TextTruncate = Enum.TextTruncate.AtEnd
		prog.Parent = row

		-- one right-hand button per row: CLAIM (complete) / GO (incomplete with a server GO target) / none
		if mission.Claimed then
			local done = Instance.new("TextLabel")
			done.Name = "DoneTag"
			done.AnchorPoint = Vector2.new(1, 0.5)
			done.Position = UDim2.new(1, -8, 0.5, 0)
			done.Size = UDim2.fromOffset(btnW, titleSize + 8)
			done.BackgroundTransparency = 1
			done.Font = Enum.Font.GothamBold
			done.TextSize = titleSize
			done.TextColor3 = Constants.Colors.Muted
			done.Text = "DONE"
			done.Parent = row
		elseif mission.Complete then
			local btn = rowButton(row, "ClaimButton", "CLAIM", Constants.Colors.Accent, Constants.Colors.Text, btnW, btnH)
			local missionId = mission.Id
			btn.Activated:Connect(function()
				pcall(AudioController.PlayClick)
				fire(Constants.RemoteNames.RequestClaimMission, missionId)
			end)
		else
			local goEntry: any = mission
			if MissionController.GoTarget(goEntry, nil) ~= nil then
				local btn = rowButton(row, "GoButton", "GO", Constants.Colors.XP, Constants.Colors.TextDark, btnW, btnH)
				btn.Activated:Connect(function()
					onGo(goEntry)
				end)
			end
		end
	end

	if dailyInfo and state.DailyLogin then
		local d = state.DailyLogin
		local reward = DailyRewardConfig.Rewards[d.NextDay]
		local rewardText = if reward then "$" .. commas(reward.Cash) else ""
		if d.AlreadyClaimedToday then
			dailyInfo.Text = string.format("Daily streak: Day %d (claimed)", d.Streak)
			if dailyBtn then
				dailyBtn.Text = "CLAIMED"
				dailyBtn.BackgroundColor3 = Color3.fromRGB(50, 55, 60)
				dailyBtn.Active = false
			end
		else
			dailyInfo.Text = string.format("Claim Day %d reward %s", d.NextDay, rewardText)
			if dailyBtn then
				dailyBtn.Text = "CLAIM DAILY"
				dailyBtn.BackgroundColor3 = Constants.Colors.Gold
				dailyBtn.TextColor3 = Color3.fromRGB(30, 30, 20)
				dailyBtn.Active = true
			end
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
	local sh = shell
	if sh then
		sh.Sync(open)
	end
	if open then
		refresh()
	end
end

-- GO: point the one objective marker at the nearest target, then get the panel out of the way
onGo = function(entry: any)
	local target = MissionController.GoTarget(entry, rootPosition())
	if target == nil then
		return
	end
	pcall(AudioController.PlayClick)
	local ok, err = pcall(function(): any
		ObjectiveMarker.Show(target)
		return nil
	end)
	if not ok then
		warn("[WAR EMPIRE] MissionController: ObjectiveMarker.Show failed: " .. tostring(err))
	end
	setOpen(false)
end

-- a claim row (spinner / daily login): info text left, a TAP-tall button right
local function claimRow(parent: Instance, name: string, y: number, btnText: string): (Frame, TextLabel, TextButton)
	local TAP = PanelShell.TouchMinV()
	local row = Instance.new("Frame")
	row.Name = name
	row.Position = UDim2.fromOffset(12, y)
	row.Size = UDim2.new(1, -24, 0, TAP + 8)
	row.BackgroundColor3 = Constants.Colors.Background
	row.BorderSizePixel = 0
	corner(row, 8)
	row.Parent = parent

	local btnW = if isTouch then 150 else 120
	local info = Instance.new("TextLabel")
	info.BackgroundTransparency = 1
	info.Position = UDim2.fromOffset(12, 0)
	info.Size = UDim2.new(1, -(btnW + 28), 1, 0)
	info.Font = Enum.Font.GothamBold
	info.TextSize = PanelShell.Text(14)
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.TextTruncate = Enum.TextTruncate.AtEnd
	info.TextColor3 = Constants.Colors.Text
	info.Parent = row

	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.new(1, -4, 0.5, 0)
	b.Size = UDim2.fromOffset(btnW, TAP)
	b.Font = Enum.Font.GothamBold
	b.TextSize = PanelShell.Text(13)
	b.Text = btnText
	b.TextColor3 = Color3.fromRGB(30, 30, 20)
	b.BackgroundColor3 = Constants.Colors.Gold
	b.BorderSizePixel = 0
	b.Active = true
	corner(b, 8)
	b.Parent = row
	return row, info, b
end

local function playerGui(): PlayerGui?
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg then
		return pg
	end
	local waited = player:WaitForChild("PlayerGui", 30)
	if waited and waited:IsA("PlayerGui") then
		return waited
	end
	return nil
end

function MissionController.Init()
	local pg = playerGui()
	if not pg then
		warn("[WAR EMPIRE] MissionController: no PlayerGui after 30 s; Missions panel off")
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireMissions"
	PanelShell.Screen(screen) -- DisplayOrder 60 (Panels), one HUD scale + safe area
	screen.Parent = pg
	screenGui = screen

	local TAP = PanelShell.TouchMinV()
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = if isTouch then UDim2.new(0.94, 0, 1, -16) else UDim2.fromOffset(480, 520)
	panel.BackgroundColor3 = Constants.Colors.Panel
	panel.BorderSizePixel = 0
	panel.Active = true
	panel.Visible = false
	panel.Parent = screen
	corner(panel, 12)
	do
		local cap = Instance.new("UISizeConstraint")
		cap.MaxSize = if isTouch then Vector2.new(820, 620) else Vector2.new(480, 520)
		cap.Parent = panel
	end

	PanelShell.Title(panel, "Daily Missions")
	PanelShell.CloseButton(panel, function()
		setOpen(false)
	end)

	local y = TAP + 8
	-- v70: FREE SUPPLY SPIN (was the SPIN chip on the cash pill)
	local _, sInfo, sBtn = claimRow(panel, "SpinnerRow", y, "CLAIM")
	spinInfo = sInfo
	spinBtn = sBtn
	sBtn.Activated:Connect(function()
		if sBtn:GetAttribute("WE_Disabled") == true then
			return
		end
		pcall(AudioController.PlayClick)
		fire(Constants.RemoteNames.RequestClaimSpinner)
	end)
	y += TAP + 8 + 6

	local _, dInfo, dBtn = claimRow(panel, "DailyRow", y, "CLAIM DAILY")
	dInfo.Text = "Daily reward"
	dInfo.Font = Enum.Font.GothamMedium
	dailyInfo = dInfo
	dailyBtn = dBtn
	dBtn.Activated:Connect(function()
		pcall(AudioController.PlayClick)
		fire(Constants.RemoteNames.RequestClaimDailyReward)
	end)
	y += TAP + 8 + 8

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Position = UDim2.fromOffset(12, y)
	list.Size = UDim2.new(1, -24, 1, -(y + 12))
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = if isTouch then 6 else 4
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel
	listFrame = list

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

	Remotes.BindEvent(Constants.RemoteNames.MissionStateUpdate, function(payload: Types.MissionStatePayload)
		if typeof(payload) ~= "table" then
			return
		end
		state = payload
		if menuOpen then
			refresh()
		end
	end)

	Remotes.BindEvent(Constants.RemoteNames.SpinnerStateUpdate, function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		spinnerKnown = true
		spinnerReady = payload.Ready == true
		spinnerReadyAt = os.clock() + math.max(0, tonumber(payload.CooldownRemaining) or 0)
		paintSpinner()
	end)
	paintSpinner()

	-- countdown on the spinner row while the panel is open (repaints text only)
	task.spawn(function()
		while true do
			task.wait(1)
			if menuOpen and spinnerKnown and not spinnerReady then
				paintSpinner()
			end
		end
	end)

	local missionsKey: Enum.KeyCode = HudConfig.Keys.Missions or Enum.KeyCode.M
	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then
			return
		end
		if input.KeyCode == missionsKey then
			setOpen(not menuOpen)
		end
	end)
end

function MissionController.Toggle()
	local sh = shell
	if not menuOpen and sh and sh.TapThrough() then
		return
	end
	setOpen(not menuOpen)
end

function MissionController.Open()
	setOpen(true)
end

function MissionController.Close()
	setOpen(false)
end

function MissionController.IsOpen(): boolean
	return menuOpen
end

return MissionController
