--!strict
--[[
	Interactive tutorial UI: claim base → command center → income → barracks → jeep → outpost
	Skip button; waypoints/highlights are best-effort via StudioSetup WE_TutorialMarker placeholders.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local TutorialConfig = require(Shared.Configs.TutorialConfig)

local TutorialController = {}

local player = Players.LocalPlayer
local gui: ScreenGui? = nil
local panel: Frame? = nil
local titleLabel: TextLabel? = nil
local hintLabel: TextLabel? = nil
local progressLabel: TextLabel? = nil
local beam: Beam? = nil
local attach0: Attachment? = nil
local attach1: Attachment? = nil
local highlightPart: BasePart? = nil
local currentMarkerName: string? = nil

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function clearWaypoint()
	if beam then
		beam:Destroy()
		beam = nil
	end
	if attach0 then
		attach0:Destroy()
		attach0 = nil
	end
	if attach1 then
		attach1:Destroy()
		attach1 = nil
	end
	if highlightPart then
		local stroke = highlightPart:FindFirstChild("WE_TutorialHighlight")
		if stroke then
			stroke:Destroy()
		end
		highlightPart = nil
	end
	currentMarkerName = nil
end

local function findMarker(markerName: string?): BasePart?
	if not markerName or markerName == "" then
		return nil
	end
	-- Prefer CollectionService tag
	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.TutorialMarker)) do
		if inst:IsA("BasePart") and (inst.Name == markerName or inst:GetAttribute("TutorialStepId") == markerName) then
			return inst
		end
	end
	-- Fallback: search under WarEmpireSetup
	local root = Workspace:FindFirstChild("WarEmpireSetup")
	if root then
		local found = root:FindFirstChild(markerName, true)
		if found and found:IsA("BasePart") then
			return found
		end
	end
	local any = Workspace:FindFirstChild(markerName, true)
	if any and any:IsA("BasePart") then
		return any
	end
	return nil
end

local function setWaypoint(markerName: string?)
	clearWaypoint()
	if not markerName then
		return
	end
	currentMarkerName = markerName
	local target = findMarker(markerName)
	if not target then
		return
	end
	highlightPart = target
	local sel = Instance.new("SelectionBox")
	sel.Name = "WE_TutorialHighlight"
	sel.Adornee = target
	sel.Color3 = Constants.Colors.Gold
	sel.LineThickness = 0.05
	sel.Parent = target

	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		return
	end

	attach0 = Instance.new("Attachment")
	attach0.Name = "WE_TutAtt0"
	attach0.Parent = hrp
	attach1 = Instance.new("Attachment")
	attach1.Name = "WE_TutAtt1"
	attach1.Parent = target

	beam = Instance.new("Beam")
	beam.Name = "WE_TutorialBeam"
	beam.Attachment0 = attach0
	beam.Attachment1 = attach1
	beam.FaceCamera = true
	beam.Width0 = 0.4
	beam.Width1 = 0.4
	beam.Color = ColorSequence.new(Constants.Colors.Gold)
	beam.Transparency = NumberSequence.new(0.25)
	beam.Parent = hrp
end

local function setVisible(open: boolean)
	if panel then
		panel.Visible = open
	end
	if not open then
		clearWaypoint()
	end
end

local function applyState(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	if payload.Complete == true then
		setVisible(false)
		clearWaypoint()
		return
	end
	setVisible(true)
	if titleLabel then
		titleLabel.Text = tostring(payload.Title or "Tutorial")
	end
	if hintLabel then
		hintLabel.Text = tostring(payload.Hint or "")
	end
	if progressLabel then
		local step = tonumber(payload.Step) or 0
		local total = tonumber(payload.Total) or TutorialConfig.StepCount()
		progressLabel.Text = string.format("Step %d / %d", math.clamp(step, 1, total), total)
	end
	setWaypoint(payload.MarkerName)
end

function TutorialController.Init()
	local pg = player:WaitForChild("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireTutorial"
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = 20
	screen.Parent = pg
	gui = screen

	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -24)
	frame.Size = UDim2.fromOffset(420, 110)
	frame.BackgroundColor3 = Constants.Colors.Panel
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = screen
	panel = frame
	corner(frame, 10)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Constants.Colors.Accent
	stroke.Thickness = 2
	stroke.Parent = frame

	local prog = Instance.new("TextLabel")
	prog.Name = "Progress"
	prog.BackgroundTransparency = 1
	prog.Position = UDim2.fromOffset(14, 8)
	prog.Size = UDim2.new(1, -120, 0, 16)
	prog.Font = Enum.Font.Gotham
	prog.TextSize = 12
	prog.TextXAlignment = Enum.TextXAlignment.Left
	prog.TextColor3 = Constants.Colors.Muted
	prog.Text = ""
	prog.Parent = frame
	progressLabel = prog

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(14, 28)
	title.Size = UDim2.new(1, -120, 0, 22)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Constants.Colors.Text
	title.Text = "Tutorial"
	title.Parent = frame
	titleLabel = title

	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.BackgroundTransparency = 1
	hint.Position = UDim2.fromOffset(14, 52)
	hint.Size = UDim2.new(1, -120, 0, 48)
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 13
	hint.TextWrapped = true
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextYAlignment = Enum.TextYAlignment.Top
	hint.TextColor3 = Constants.Colors.Muted
	hint.Text = ""
	hint.Parent = frame
	hintLabel = hint

	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.AnchorPoint = Vector2.new(1, 0)
	skip.Position = UDim2.new(1, -12, 0, 10)
	skip.Size = UDim2.fromOffset(72, 28)
	skip.BackgroundColor3 = Constants.Colors.Background
	skip.Font = Enum.Font.GothamBold
	skip.TextSize = 12
	skip.TextColor3 = Constants.Colors.Text
	skip.Text = "SKIP"
	skip.BorderSizePixel = 0
	corner(skip, 6)
	skip.Parent = frame
	skip.MouseButton1Click:Connect(function()
		Remotes.GetEvent(Constants.RemoteNames.RequestSkipTutorial):FireServer()
	end)

	-- Soft pulse on panel when shown
	task.spawn(function()
		while screen.Parent do
			if frame.Visible then
				local tw = TweenService:Create(stroke, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
					Transparency = 0.55,
				})
				tw:Play()
				while frame.Visible and screen.Parent do
					task.wait(0.5)
				end
				tw:Cancel()
				stroke.Transparency = 0
			end
			task.wait(0.25)
		end
	end)

	Remotes.GetEvent(Constants.RemoteNames.TutorialStateUpdate).OnClientEvent:Connect(applyState)

	-- Also hide soft-complete from PlayerStateUpdate
	Remotes.GetEvent(Constants.RemoteNames.PlayerStateUpdate).OnClientEvent:Connect(function(state: any)
		if typeof(state) == "table" and state.TutorialComplete == true then
			setVisible(false)
			clearWaypoint()
		end
	end)

	player.CharacterAdded:Connect(function()
		-- Re-bind beam to new character if tutorial active
		if currentMarkerName and panel and panel.Visible then
			task.defer(function()
				setWaypoint(currentMarkerName)
			end)
		end
	end)
end

return TutorialController
