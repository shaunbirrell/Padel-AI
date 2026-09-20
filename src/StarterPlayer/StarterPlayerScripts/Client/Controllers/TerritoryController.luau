--!strict
--[[ Phase 5/7 — Territory HUD, capture progress, Radar Hill enemy highlights.
	Mobile: larger capture bar, STAND IN ZONE / CONTESTED / PROTECTED status,
	% + ETA, list collapses on touch, clear of dock / pad BUY / combat HP.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local TerritoryConfig = require(Shared.Configs.TerritoryConfig)
local UIUtil = require(Shared.Util.UIUtil)

local TerritoryController = {}

local player = Players.LocalPlayer
local isTouch = UserInputService.TouchEnabled
local _gui: ScreenGui? = nil
local progressFrame: Frame? = nil
local progressFill: Frame? = nil
local progressLabel: TextLabel? = nil
local statusLabel: TextLabel? = nil
local pctLabel: TextLabel? = nil
local alertLabel: TextLabel? = nil
local listFrame: ScrollingFrame? = nil
local listPanel: Frame? = nil
local radarBadge: TextLabel? = nil
local lastAlert = ""
local radarActive = false
local radarRadius = 550
local radarHighlights: { [number]: Highlight } = {}
local lastCapturePct = -1
local listCollapsed = isTouch -- start collapsed on phone
-- v38: contested dual-color pulse cache
local contestedPulseActive = false
local contestedColA: Color3? = nil
local contestedColB: Color3? = nil

local function setProgressVisible(visible: boolean)
	if progressFrame then
		progressFrame.Visible = visible
	end
end

local function clearRadarHighlights()
	for userId, h in pairs(radarHighlights) do
		if h and h.Parent then
			h:Destroy()
		end
		radarHighlights[userId] = nil
	end
end

local function ensureHighlight(target: Model): Highlight
	local existing = target:FindFirstChild("WE_RadarHighlight")
	if existing and existing:IsA("Highlight") then
		return existing
	end
	local h = Instance.new("Highlight")
	h.Name = "WE_RadarHighlight"
	h.FillColor = Color3.fromRGB(200, 80, 80)
	h.OutlineColor = Color3.fromRGB(255, 180, 80)
	h.FillTransparency = 0.65
	h.OutlineTransparency = 0.15
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Parent = target
	return h
end

local function updateRadar()
	if not radarActive then
		clearRadarHighlights()
		return
	end
	local myChar = player.Character
	local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not myRoot then
		clearRadarHighlights()
		return
	end

	local seen: { [number]: boolean } = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local char = other.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			if char and root and humanoid and humanoid.Health > 0 then
				local dist = (root.Position - myRoot.Position).Magnitude
				if dist <= radarRadius then
					seen[other.UserId] = true
					local h = ensureHighlight(char)
					radarHighlights[other.UserId] = h
				end
			end
		end
	end
	for userId, h in pairs(radarHighlights) do
		if not seen[userId] then
			if h and h.Parent then
				h:Destroy()
			end
			radarHighlights[userId] = nil
		end
	end
end

local function refreshList(payload: Types.TerritoryStatePayload)
	if not listFrame then
		return
	end
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("TextLabel") or child:IsA("Frame") then
			child:Destroy()
		end
	end
	local layout = listFrame:FindFirstChildOfClass("UIListLayout")
	if not layout then
		local l = Instance.new("UIListLayout")
		l.Padding = UDim.new(0, 2)
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.Parent = listFrame
	end

	if #payload.Territories == 0 then
		UIUtil.EmptyState(listFrame, "No territories yet — explore the map.", 0)
		return
	end

	for i, entry in ipairs(payload.Territories) do
		local row = Instance.new("TextLabel")
		row.Size = UDim2.new(1, -4, 0, if isTouch then 22 else 18)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.Gotham
		row.TextSize = if isTouch then 13 else 12
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = Constants.Colors.Text
		row.LayoutOrder = i
		local owner = entry.OwnerType
		if entry.OwnerUserId == player.UserId and entry.OwnerType == "Player" then
			owner = "YOU"
			row.TextColor3 = Constants.Colors.Cash
		elseif entry.Contested then
			owner = "CONTESTED"
			row.TextColor3 = Color3.fromRGB(230, 160, 60)
		elseif entry.OwnerType == "NPC" then
			row.TextColor3 = Constants.Colors.Danger
		elseif entry.OwnerType == "Neutral" or entry.OwnerType == nil then
			row.TextColor3 = Constants.Colors.Muted
			owner = "NEUTRAL"
		end
		row.Text = string.format("%s — %s", entry.DisplayName, owner)
		row.Parent = listFrame
	end
end

local function applyListCollapsed()
	if not listPanel or not listFrame then
		return
	end
	if listCollapsed then
		listPanel.Size = UDim2.fromOffset(if isTouch then 160 else 200, 36)
		listFrame.Visible = false
	else
		listPanel.Size = UDim2.fromOffset(if isTouch then 200 else 200, if isTouch then 160 else 140)
		listFrame.Visible = true
	end
	local toggle = listPanel:FindFirstChild("CollapseToggle")
	if toggle and toggle:IsA("TextButton") then
		toggle.Text = if listCollapsed then "TERRITORIES ▾" else "TERRITORIES ▴"
	end
end

function TerritoryController.Init()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireTerritory"
	screen.Parent = player:WaitForChild("PlayerGui")
	UIUtil.PrepareScreen(screen, false)
	screen.DisplayOrder = 28 -- below combat HUD cluster / pad BUY
	_gui = screen

	-- Capture progress — above pad BUY (-108) and combat HP (-188 on touch)
	local prog = Instance.new("Frame")
	prog.Name = "CaptureProgress"
	prog.AnchorPoint = Vector2.new(0.5, 1)
	prog.Position = UDim2.new(0.5, 0, 1, if isTouch then -250 else -120)
	prog.Size = UDim2.fromOffset(if isTouch then 340 else 300, if isTouch then 78 else 52)
	prog.BackgroundColor3 = Constants.Colors.Panel
	prog.BackgroundTransparency = 0.05
	prog.BorderSizePixel = 0
	prog.Visible = false
	prog.ZIndex = 12
	prog.Parent = screen
	UIUtil.Corner(prog, 10)
	UIUtil.Stroke(prog, Constants.Colors.Gold, 2)
	progressFrame = prog

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(12, 6)
	title.Size = UDim2.new(1, -90, 0, if isTouch then 20 else 18)
	title.Font = Enum.Font.GothamBold
	title.TextSize = if isTouch then 15 else 13
	title.TextColor3 = Constants.Colors.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Capturing..."
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Parent = prog
	progressLabel = title

	local pct = Instance.new("TextLabel")
	pct.Name = "Pct"
	pct.BackgroundTransparency = 1
	pct.AnchorPoint = Vector2.new(1, 0)
	pct.Position = UDim2.new(1, -12, 0, 6)
	pct.Size = UDim2.fromOffset(72, if isTouch then 22 else 18)
	pct.Font = Enum.Font.GothamBold
	pct.TextSize = if isTouch then 18 else 14
	pct.TextColor3 = Constants.Colors.Gold
	pct.TextXAlignment = Enum.TextXAlignment.Right
	pct.Text = "0%"
	pct.Parent = prog
	pctLabel = pct

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromOffset(12, if isTouch then 28 else 24)
	status.Size = UDim2.new(1, -24, 0, 16)
	status.Font = Enum.Font.GothamBold
	status.TextSize = if isTouch then 12 else 11
	status.TextColor3 = Color3.fromRGB(200, 210, 140)
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Text = "STAND IN THE ZONE"
	status.Parent = prog
	statusLabel = status

	local bg = Instance.new("Frame")
	bg.Position = UDim2.fromOffset(12, if isTouch then 50 else 36)
	bg.Size = UDim2.new(1, -24, 0, if isTouch then 18 else 14)
	bg.BackgroundColor3 = Constants.Colors.Background
	bg.BorderSizePixel = 0
	bg.Parent = prog
	UIUtil.Corner(bg, 4)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(200, 180, 60)
	fill.BorderSizePixel = 0
	fill.Parent = bg
	UIUtil.Corner(fill, 4)
	progressFill = fill

	-- Alert toast
	local alert = Instance.new("TextLabel")
	alert.Name = "TerritoryAlert"
	alert.AnchorPoint = Vector2.new(0.5, 0)
	alert.Position = UDim2.new(0.5, 0, 0, if isTouch then 72 else 100)
	alert.Size = UDim2.fromOffset(if isTouch then 340 else 360, if isTouch then 32 else 28)
	alert.BackgroundTransparency = 1
	alert.Font = Enum.Font.GothamBold
	alert.TextSize = if isTouch then 15 else 16
	alert.TextColor3 = Color3.fromRGB(230, 200, 80)
	alert.Text = ""
	alert.TextStrokeTransparency = 0.5
	alert.Parent = screen
	alertLabel = alert

	-- Radar active badge
	local badge = Instance.new("TextLabel")
	badge.Name = "RadarBadge"
	badge.AnchorPoint = Vector2.new(0, 0)
	badge.Position = UDim2.fromOffset(16, if isTouch then 56 else 248)
	badge.Size = UDim2.fromOffset(200, 20)
	badge.BackgroundTransparency = 1
	badge.Font = Enum.Font.GothamBold
	badge.TextSize = 11
	badge.TextXAlignment = Enum.TextXAlignment.Left
	badge.TextColor3 = Color3.fromRGB(180, 120, 220)
	badge.Text = ""
	badge.Visible = false
	badge.Parent = screen
	radarBadge = badge

	-- Compact territory list (left) — collapsible on mobile
	local panel = Instance.new("Frame")
	panel.Name = "TerritoryList"
	panel.Position = UDim2.fromOffset(16, if isTouch then 80 else 100)
	panel.Size = UDim2.fromOffset(200, 140)
	panel.BackgroundColor3 = Constants.Colors.Panel
	panel.BackgroundTransparency = 0.25
	panel.BorderSizePixel = 0
	panel.Parent = screen
	UIUtil.Corner(panel, 8)
	UIUtil.Stroke(panel)
	listPanel = panel

	local toggle = Instance.new("TextButton")
	toggle.Name = "CollapseToggle"
	toggle.BackgroundTransparency = 1
	toggle.Size = UDim2.new(1, -8, 0, 28)
	toggle.Position = UDim2.fromOffset(4, 4)
	toggle.Font = Enum.Font.GothamBold
	toggle.TextSize = if isTouch then 13 else 12
	toggle.TextXAlignment = Enum.TextXAlignment.Left
	toggle.TextColor3 = Constants.Colors.Muted
	toggle.Text = "TERRITORIES"
	toggle.AutoButtonColor = true
	toggle.Parent = panel
	UIUtil.EnsureMinTouch(toggle, 28)
	toggle.Activated:Connect(function()
		listCollapsed = not listCollapsed
		applyListCollapsed()
	end)

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(4, 32)
	list.Size = UDim2.new(1, -8, 1, -36)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = if isTouch then 5 else 3
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel
	listFrame = list
	applyListCollapsed()

	local applyToken = 0
	Remotes.GetEvent(Constants.RemoteNames.TerritoryStateUpdate).OnClientEvent:Connect(function(payload: Types.TerritoryStatePayload)
		applyToken += 1
		local my = applyToken
		task.delay(0.1, function()
			if my == applyToken then
				TerritoryController.Apply(payload)
			end
		end)
	end)

	local radarAccum = 0
	RunService.Heartbeat:Connect(function(dt)
		-- v38: continuous contested dual-color pulse on capture bar
		if contestedPulseActive and progressFill and contestedColA and contestedColB then
			local pulse = (math.sin(os.clock() * 5) + 1) * 0.5
			progressFill.BackgroundColor3 = contestedColA:Lerp(contestedColB, pulse)
		end
		if not radarActive then
			return
		end
		radarAccum += dt
		if radarAccum >= 0.2 then
			radarAccum = 0
			updateRadar()
		end
	end)

	Players.PlayerRemoving:Connect(function(leaving)
		local h = radarHighlights[leaving.UserId]
		if h then
			h:Destroy()
			radarHighlights[leaving.UserId] = nil
		end
	end)
end

function TerritoryController.Apply(payload: Types.TerritoryStatePayload)
	refreshList(payload)

	radarActive = payload.RadarReveal == true
	radarRadius = tonumber(payload.RadarRadius) or TerritoryConfig.RadarRevealRadius or 220
	if radarBadge then
		radarBadge.Visible = radarActive
		radarBadge.Text = if radarActive then string.format("RADAR ACTIVE · %dstud", math.floor(radarRadius)) else ""
	end
	if not radarActive then
		clearRadarHighlights()
	end

	local localCap = payload.LocalCapture
	if localCap and localCap.Capturing and localCap.TerritoryId then
		setProgressVisible(true)
		local def = TerritoryConfig.Territories[localCap.TerritoryId]
		local name = if def then def.DisplayName else localCap.TerritoryId
		local pct = math.floor(localCap.Progress * 100)
		local contested = localCap.Contested == true
		local protected = localCap.Protected == true
		if progressLabel then
			progressLabel.Text = string.format("Capturing %s", name)
		end
		if pctLabel then
			pctLabel.Text = string.format("%d%%", pct)
		end
		if statusLabel then
			if contested then
				statusLabel.Text = "CONTESTED — clear enemies!"
				statusLabel.TextColor3 = Color3.fromRGB(230, 140, 60)
			elseif protected then
				statusLabel.Text = "PROTECTED — capture slowed"
				statusLabel.TextColor3 = Color3.fromRGB(140, 180, 255)
			else
				statusLabel.Text = "STAND IN THE ZONE — don't leave"
				statusLabel.TextColor3 = Color3.fromRGB(200, 210, 140)
			end
		end
		if progressFill then
			progressFill.Size = UDim2.fromScale(math.clamp(localCap.Progress, 0, 1), 1)
			local t = math.clamp(localCap.Progress, 0, 1)
			if contested then
				contestedPulseActive = true
				local ca = (localCap :: any).ContesterColorA
				local cb = (localCap :: any).ContesterColorB
				if typeof(ca) == "table" and typeof(cb) == "table" and #ca >= 3 and #cb >= 3 then
					contestedColA = Color3.new(ca[1], ca[2], ca[3])
					contestedColB = Color3.new(cb[1], cb[2], cb[3])
				else
					contestedColA = Color3.fromRGB(230, 120, 50)
					contestedColB = Color3.fromRGB(80, 140, 255)
				end
				local pulse = (math.sin(os.clock() * 5) + 1) * 0.5
				progressFill.BackgroundColor3 = (contestedColA :: Color3):Lerp(contestedColB :: Color3, pulse)
			else
				contestedPulseActive = false
				contestedColA = nil
				contestedColB = nil
				progressFill.BackgroundColor3 = Color3.fromRGB(200 - 40 * t, 180 + 50 * t, 60)
			end
		end
		if progressFrame then
			local stroke = progressFrame:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if contested then Color3.fromRGB(230, 120, 50) else Constants.Colors.Gold
			end
		end
		-- Milestone toast at 50% / 90%
		if alertLabel and pct ~= lastCapturePct then
			if pct >= 90 and lastCapturePct < 90 then
				alertLabel.Text = "Almost captured — stay in zone!"
			elseif pct >= 50 and lastCapturePct < 50 then
				alertLabel.Text = "Capture halfway..."
			end
			lastCapturePct = pct
		end
	else
		setProgressVisible(false)
		lastCapturePct = -1
		contestedPulseActive = false
		contestedColA = nil
		contestedColB = nil
	end

	local owned = 0
	for _, entry in ipairs(payload.Territories) do
		if entry.OwnerUserId == player.UserId and entry.OwnerType == "Player" then
			owned += 1
		end
	end
	local msg = if owned > 0 then string.format("Outposts held: %d", owned) else ""
	if alertLabel and msg ~= "" and msg ~= lastAlert and lastCapturePct < 0 then
		lastAlert = msg
		alertLabel.Text = msg
		task.delay(3, function()
			if alertLabel and alertLabel.Text == msg then
				alertLabel.Text = ""
			end
		end)
	end
end

return TerritoryController
