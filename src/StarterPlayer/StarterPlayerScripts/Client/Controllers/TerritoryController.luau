--!strict
--[[ Phase 5 — Territory HUD, capture progress, Radar Hill enemy highlights ]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local TerritoryConfig = require(Shared.Configs.TerritoryConfig)
local UIUtil = require(Shared.Util.UIUtil)

local TerritoryController = {}

local player = Players.LocalPlayer
local _gui: ScreenGui? = nil
local progressFrame: Frame? = nil
local progressFill: Frame? = nil
local progressLabel: TextLabel? = nil
local alertLabel: TextLabel? = nil
local listFrame: ScrollingFrame? = nil
local radarBadge: TextLabel? = nil
local lastAlert = ""
local radarActive = false
local radarRadius = 350
local radarHighlights: { [number]: Highlight } = {}
local lastCapturePct = -1

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

	for i, entry in ipairs(payload.Territories) do
		local row = Instance.new("TextLabel")
		row.Size = UDim2.new(1, -4, 0, 18)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.Gotham
		row.TextSize = 12
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
		end
		row.Text = string.format("%s — %s", entry.DisplayName, owner)
		row.Parent = listFrame
	end
end

function TerritoryController.Init()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireTerritory"
	screen.Parent = player:WaitForChild("PlayerGui")
	UIUtil.PrepareScreen(screen, false)
	_gui = screen

	-- Capture progress (center-bottom)
	local prog = Instance.new("Frame")
	prog.Name = "CaptureProgress"
	prog.AnchorPoint = Vector2.new(0.5, 1)
	prog.Position = UDim2.new(0.5, 0, 1, -120)
	prog.Size = UDim2.fromOffset(300, 52)
	prog.BackgroundColor3 = Constants.Colors.Panel
	prog.BackgroundTransparency = 0.08
	prog.BorderSizePixel = 0
	prog.Visible = false
	prog.Parent = screen
	UIUtil.Corner(prog, 8)
	UIUtil.Stroke(prog, Color3.fromRGB(90, 100, 60), 1)
	progressFrame = prog

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(10, 4)
	title.Size = UDim2.new(1, -20, 0, 18)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 13
	title.TextColor3 = Constants.Colors.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Capturing..."
	title.Parent = prog
	progressLabel = title

	local bg = Instance.new("Frame")
	bg.Position = UDim2.fromOffset(10, 28)
	bg.Size = UDim2.new(1, -20, 0, 14)
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
	alert.Position = UDim2.new(0.5, 0, 0, 100)
	alert.Size = UDim2.fromOffset(360, 28)
	alert.BackgroundTransparency = 1
	alert.Font = Enum.Font.GothamBold
	alert.TextSize = 16
	alert.TextColor3 = Color3.fromRGB(230, 200, 80)
	alert.Text = ""
	alert.TextStrokeTransparency = 0.5
	alert.Parent = screen
	alertLabel = alert

	-- Radar active badge
	local badge = Instance.new("TextLabel")
	badge.Name = "RadarBadge"
	badge.AnchorPoint = Vector2.new(0, 0)
	badge.Position = UDim2.fromOffset(16, 248)
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

	-- Compact territory list (left side)
	local panel = Instance.new("Frame")
	panel.Name = "TerritoryList"
	panel.Position = UDim2.fromOffset(16, 100)
	panel.Size = UDim2.fromOffset(200, 140)
	panel.BackgroundColor3 = Constants.Colors.Panel
	panel.BackgroundTransparency = 0.25
	panel.BorderSizePixel = 0
	panel.Parent = screen
	UIUtil.Corner(panel, 8)
	UIUtil.Stroke(panel)

	local header = Instance.new("TextLabel")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, -8, 0, 20)
	header.Position = UDim2.fromOffset(6, 4)
	header.Font = Enum.Font.GothamBold
	header.TextSize = 12
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextColor3 = Constants.Colors.Muted
	header.Text = "TERRITORIES"
	header.Parent = panel

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(4, 24)
	list.Size = UDim2.new(1, -8, 1, -28)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 3
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel
	listFrame = list

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
		if progressLabel then
			progressLabel.Text = string.format("Capturing %s — %d%%", name, pct)
		end
		if progressFill then
			progressFill.Size = UDim2.fromScale(math.clamp(localCap.Progress, 0, 1), 1)
			-- Warm color as capture nears complete
			local t = math.clamp(localCap.Progress, 0, 1)
			progressFill.BackgroundColor3 = Color3.fromRGB(200 - 40 * t, 180 + 40 * t, 60)
		end
		-- Milestone toast at 50% / 90%
		if alertLabel and pct ~= lastCapturePct then
			if pct >= 90 and lastCapturePct < 90 then
				alertLabel.Text = "Almost captured!"
			elseif pct >= 50 and lastCapturePct < 50 then
				alertLabel.Text = "Capture halfway..."
			end
			lastCapturePct = pct
		end
	else
		setProgressVisible(false)
		lastCapturePct = -1
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
