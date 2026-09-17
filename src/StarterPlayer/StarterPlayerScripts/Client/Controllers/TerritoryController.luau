--!strict
--[[ Phase 5 — Territory HUD alerts + capture progress bar ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local TerritoryConfig = require(Shared.Configs.TerritoryConfig)

local TerritoryController = {}

local player = Players.LocalPlayer
local gui: ScreenGui? = nil
local progressFrame: Frame? = nil
local progressFill: Frame? = nil
local progressLabel: TextLabel? = nil
local alertLabel: TextLabel? = nil
local listFrame: ScrollingFrame? = nil
local lastAlert = ""

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function setProgressVisible(visible: boolean)
	if progressFrame then
		progressFrame.Visible = visible
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
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen

	-- Capture progress (center-bottom)
	local prog = Instance.new("Frame")
	prog.Name = "CaptureProgress"
	prog.AnchorPoint = Vector2.new(0.5, 1)
	prog.Position = UDim2.new(0.5, 0, 1, -120)
	prog.Size = UDim2.fromOffset(280, 48)
	prog.BackgroundColor3 = Constants.Colors.Panel
	prog.BackgroundTransparency = 0.1
	prog.BorderSizePixel = 0
	prog.Visible = false
	prog.Parent = screen
	corner(prog, 8)
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
	bg.Size = UDim2.new(1, -20, 0, 12)
	bg.BackgroundColor3 = Constants.Colors.Background
	bg.BorderSizePixel = 0
	bg.Parent = prog
	corner(bg, 4)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(200, 180, 60)
	fill.BorderSizePixel = 0
	fill.Parent = bg
	corner(fill, 4)
	progressFill = fill

	-- Alert toast
	local alert = Instance.new("TextLabel")
	alert.Name = "TerritoryAlert"
	alert.AnchorPoint = Vector2.new(0.5, 0)
	alert.Position = UDim2.new(0.5, 0, 0, 100)
	alert.Size = UDim2.fromOffset(320, 28)
	alert.BackgroundTransparency = 1
	alert.Font = Enum.Font.GothamBold
	alert.TextSize = 16
	alert.TextColor3 = Color3.fromRGB(230, 200, 80)
	alert.Text = ""
	alert.TextStrokeTransparency = 0.5
	alert.Parent = screen
	alertLabel = alert

	-- Compact territory list (left side)
	local panel = Instance.new("Frame")
	panel.Name = "TerritoryList"
	panel.Position = UDim2.fromOffset(16, 100)
	panel.Size = UDim2.fromOffset(200, 140)
	panel.BackgroundColor3 = Constants.Colors.Panel
	panel.BackgroundTransparency = 0.25
	panel.BorderSizePixel = 0
	panel.Parent = screen
	corner(panel, 8)

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

	Remotes.GetEvent(Constants.RemoteNames.TerritoryStateUpdate).OnClientEvent:Connect(function(payload: Types.TerritoryStatePayload)
		TerritoryController.Apply(payload)
	end)
end

function TerritoryController.Apply(payload: Types.TerritoryStatePayload)
	refreshList(payload)

	local localCap = payload.LocalCapture
	if localCap and localCap.Capturing and localCap.TerritoryId then
		setProgressVisible(true)
		local def = TerritoryConfig.Territories[localCap.TerritoryId]
		local name = if def then def.DisplayName else localCap.TerritoryId
		if progressLabel then
			progressLabel.Text = string.format("Capturing %s — %d%%", name, math.floor(localCap.Progress * 100))
		end
		if progressFill then
			progressFill.Size = UDim2.fromScale(math.clamp(localCap.Progress, 0, 1), 1)
		end
	else
		setProgressVisible(false)
	end

	-- Alert when local player owns newly (best-effort from payload)
	local owned = 0
	for _, entry in ipairs(payload.Territories) do
		if entry.OwnerUserId == player.UserId and entry.OwnerType == "Player" then
			owned += 1
		end
	end
	local msg = if owned > 0 then string.format("Outposts held: %d", owned) else ""
	if alertLabel and msg ~= "" and msg ~= lastAlert then
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
