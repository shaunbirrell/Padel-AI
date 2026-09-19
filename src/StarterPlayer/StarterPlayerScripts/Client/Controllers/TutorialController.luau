--!strict
--[[
	Interactive tutorial UI: claim base → command center → income → barracks → jeep → outpost
	Skip + mobile CTA (BUY ON PAD / OPEN GARAGE / …); pad StructureId fallback when markers missing.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)
local TutorialConfig = require(Shared.Configs.TutorialConfig)

local TutorialController = {}

local player = Players.LocalPlayer
local isTouch = UserInputService.TouchEnabled

local _gui: ScreenGui? = nil
local panel: Frame? = nil
local titleLabel: TextLabel? = nil
local hintLabel: TextLabel? = nil
local progressLabel: TextLabel? = nil
local dotsFrame: Frame? = nil
local ctaBtn: TextButton? = nil
local beam: Beam? = nil
local attach0: Attachment? = nil
local attach1: Attachment? = nil
local highlightPart: BasePart? = nil
local currentMarkerName: string? = nil
local currentPadStructureId: string? = nil
local currentCtaAction: string? = nil
local myPlotId: any = nil

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

local function findPadByStructure(structureId: string?): BasePart?
	if not structureId or structureId == "" then
		return nil
	end
	local best: BasePart? = nil
	local bestDist = math.huge
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local origin = if hrp and hrp:IsA("BasePart") then hrp.Position else Vector3.zero

	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.UpgradeSlot)) do
		if inst:IsA("BasePart") and inst:GetAttribute("StructureId") == structureId then
			local plotOk = true
			if myPlotId ~= nil then
				local pid = inst:GetAttribute("PlotId")
				-- Prefer own plot when known; still accept untagged Studio pads
				if pid ~= nil and pid ~= myPlotId then
					plotOk = false
				end
			end
			if plotOk then
				local d = (inst.Position - origin).Magnitude
				if d < bestDist then
					bestDist = d
					best = inst
				end
			end
		end
	end
	return best
end

local function findMarker(markerName: string?, padStructureId: string?): BasePart?
	-- Prefer live upgrade pad for buy steps (always present after MapSetup)
	local pad = findPadByStructure(padStructureId)
	if pad then
		return pad
	end
	if not markerName or markerName == "" then
		return nil
	end
	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.TutorialMarker)) do
		if inst:IsA("BasePart") and (inst.Name == markerName or inst:GetAttribute("TutorialStepId") == markerName) then
			return inst
		end
	end
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
	-- Last resort: nearest territory capture zone for outpost step
	if markerName == "Tutorial_Outpost" then
		local nearest: BasePart? = nil
		local nd = math.huge
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local origin = if hrp and hrp:IsA("BasePart") then hrp.Position else Vector3.zero
		for _, tag in ipairs({ Constants.Tags.Territory, Constants.Tags.CaptureZone }) do
			local ok, tagged = pcall(function()
				return CollectionService:GetTagged(tag)
			end)
			if ok and tagged then
				for _, inst in ipairs(tagged) do
					if inst:IsA("BasePart") then
						local d = (inst.Position - origin).Magnitude
						if d < nd then
							nd = d
							nearest = inst
						end
					end
				end
			end
		end
		return nearest
	end
	return nil
end

local function setWaypoint(markerName: string?, padStructureId: string?)
	clearWaypoint()
	currentMarkerName = markerName
	currentPadStructureId = padStructureId
	local target = findMarker(markerName, padStructureId)
	if not target then
		return
	end
	highlightPart = target
	local sel = Instance.new("SelectionBox")
	sel.Name = "WE_TutorialHighlight"
	sel.Adornee = target
	sel.Color3 = Constants.Colors.Gold
	sel.LineThickness = 0.06
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
	beam.Width0 = 0.45
	beam.Width1 = 0.45
	beam.Color = ColorSequence.new(Constants.Colors.Gold)
	beam.Transparency = NumberSequence.new(0.2)
	beam.Parent = hrp
end

local function setVisible(open: boolean)
	if panel then
		panel.Visible = open
	end
	if not open then
		clearWaypoint()
		if ctaBtn then
			ctaBtn.Visible = false
		end
	end
end

local function refreshDots(step: number, total: number)
	local frame = dotsFrame
	if not frame then
		return
	end
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local layout = frame:FindFirstChildOfClass("UIListLayout")
	if not layout then
		local l = Instance.new("UIListLayout")
		l.FillDirection = Enum.FillDirection.Horizontal
		l.HorizontalAlignment = Enum.HorizontalAlignment.Left
		l.Padding = UDim.new(0, 6)
		l.Parent = frame
	end
	for i = 1, total do
		local dot = Instance.new("Frame")
		dot.Name = "Dot" .. i
		dot.Size = UDim2.fromOffset(10, 10)
		dot.BorderSizePixel = 0
		dot.BackgroundColor3 = if i == step then Constants.Colors.Gold elseif i < step then Constants.Colors.Accent else Constants.Colors.Muted
		dot.BackgroundTransparency = if i <= step then 0 else 0.45
		corner(dot, 5)
		dot.Parent = frame
	end
end

local function runCta()
	local action = currentCtaAction
	print("[Tutorial] CTA", tostring(action), "pad=", tostring(currentPadStructureId))
	if action == "PadBuy" or action == "OpenBase" then
		-- Re-aim beam at the buy pad; open base menu as secondary path (B)
		setWaypoint(currentMarkerName, currentPadStructureId)
		local ok, BaseController = pcall(function()
			return require(script.Parent.BaseController)
		end)
		if ok and BaseController and BaseController.Open then
			BaseController.Open()
		end
	elseif action == "OpenGarage" then
		local ok, VehicleController = pcall(function()
			return require(script.Parent.VehicleController)
		end)
		if ok and VehicleController and VehicleController.Open then
			VehicleController.Open()
		end
	else
		-- Capture / WatchHud / unknown: re-aim beam
		setWaypoint(currentMarkerName, currentPadStructureId)
	end
end

local lastAnnouncedId: string? = nil

local function applyState(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	if payload.Complete == true then
		setVisible(false)
		clearWaypoint()
		lastAnnouncedId = nil
		currentCtaAction = nil
		return
	end
	setVisible(true)
	if titleLabel then
		titleLabel.Text = tostring(payload.Title or "Tutorial")
	end
	if hintLabel then
		hintLabel.Text = tostring(payload.Hint or "")
	end
	local step = tonumber(payload.Step) or 0
	local total = tonumber(payload.Total) or TutorialConfig.StepCount()
	if progressLabel then
		progressLabel.Text = string.format("Step %d / %d", math.clamp(step, 1, total), total)
	end
	refreshDots(math.clamp(step, 1, total), total)

	local padSid = if typeof(payload.PadStructureId) == "string" then payload.PadStructureId else nil
	local marker = if typeof(payload.MarkerName) == "string" then payload.MarkerName else nil
	currentCtaAction = if typeof(payload.CtaAction) == "string" then payload.CtaAction else nil
	setWaypoint(marker, padSid)

	if ctaBtn then
		local label = if typeof(payload.CtaLabel) == "string" and payload.CtaLabel ~= ""
			then payload.CtaLabel
			else "CONTINUE"
		ctaBtn.Text = label
		ctaBtn.Visible = currentCtaAction ~= nil and currentCtaAction ~= ""
	end

	local id = if typeof(payload.Id) == "string" then payload.Id else nil
	if id and id ~= lastAnnouncedId then
		lastAnnouncedId = id
		if id == "CommandCenter" or id == "Barracks" then
			print("[Tutorial] Step", id, "— stand on pad → tap BUY (or CTA / B menu)")
		elseif id == "Jeep" then
			print("[Tutorial] Step Jeep — OPEN GARAGE CTA / G → SPAWN")
		elseif id == "Income" then
			print("[Tutorial] Step Income — watch HUD +$/tick")
		end
	end
end

function TutorialController.Init()
	local pg = player:WaitForChild("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireTutorial"
	screen.DisplayOrder = 20
	screen.Parent = pg
	UIUtil.PrepareScreen(screen, false)
	_gui = screen

	local panelH = if isTouch then 168 else 148
	local panelW = if isTouch then 0 else 460
	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	-- Lift above pad BUY (~108) + mobile dock
	frame.Position = UDim2.new(0.5, 0, 1, if isTouch then -210 else -196)
	if isTouch then
		frame.Size = UDim2.new(0.94, 0, 0, panelH)
	else
		frame.Size = UDim2.fromOffset(panelW, panelH)
	end
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
	prog.Position = UDim2.fromOffset(14, 6)
	prog.Size = UDim2.new(1, -120, 0, 14)
	prog.Font = Enum.Font.Gotham
	prog.TextSize = 11
	prog.TextXAlignment = Enum.TextXAlignment.Left
	prog.TextColor3 = Constants.Colors.Muted
	prog.Text = ""
	prog.Parent = frame
	progressLabel = prog

	local dots = Instance.new("Frame")
	dots.Name = "Dots"
	dots.BackgroundTransparency = 1
	dots.Position = UDim2.fromOffset(14, 22)
	dots.Size = UDim2.new(1, -130, 0, 12)
	dots.Parent = frame
	dotsFrame = dots

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(14, 38)
	title.Size = UDim2.new(1, -120, 0, 20)
	title.Font = Enum.Font.GothamBold
	title.TextSize = if isTouch then 15 else 16
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Constants.Colors.Text
	title.Text = "Tutorial"
	title.Parent = frame
	titleLabel = title

	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.BackgroundTransparency = 1
	hint.Position = UDim2.fromOffset(14, 58)
	hint.Size = UDim2.new(1, -120, 0, if isTouch then 40 else 34)
	hint.Font = Enum.Font.Gotham
	hint.TextSize = if isTouch then 12 else 13
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
	skip.Position = UDim2.new(1, -12, 0, 8)
	skip.Size = UDim2.fromOffset(72, 28)
	skip.BackgroundColor3 = Constants.Colors.Background
	skip.Font = Enum.Font.GothamBold
	skip.TextSize = 12
	skip.TextColor3 = Constants.Colors.Text
	skip.Text = "SKIP"
	skip.BorderSizePixel = 0
	corner(skip, 6)
	skip.Parent = frame
	UIUtil.EnsureMinTouch(skip, 44)
	skip.Activated:Connect(function()
		print("[Tutorial] SKIP pressed")
		Remotes.GetEvent(Constants.RemoteNames.RequestSkipTutorial):FireServer()
	end)

	local cta = Instance.new("TextButton")
	cta.Name = "Cta"
	cta.AnchorPoint = Vector2.new(0.5, 1)
	cta.Position = UDim2.new(0.5, 0, 1, -10)
	cta.Size = UDim2.new(1, -24, 0, if isTouch then 44 else 36)
	cta.BackgroundColor3 = Constants.Colors.Gold
	cta.Font = Enum.Font.GothamBold
	cta.TextSize = if isTouch then 14 else 13
	cta.TextColor3 = Color3.fromRGB(20, 22, 18)
	cta.Text = "CONTINUE"
	cta.BorderSizePixel = 0
	cta.Visible = false
	cta.AutoButtonColor = true
	corner(cta, 8)
	cta.Parent = frame
	UIUtil.EnsureMinTouch(cta, 44)
	ctaBtn = cta
	cta.Activated:Connect(function()
		runCta()
	end)

	-- Soft pulse on panel + CTA when shown
	task.spawn(function()
		while screen.Parent do
			if frame.Visible then
				local tw = TweenService:Create(stroke, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
					Transparency = 0.55,
				})
				tw:Play()
				local ctaTw: Tween? = nil
				if cta.Visible then
					ctaTw = TweenService:Create(cta, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
						BackgroundColor3 = Color3.fromRGB(28, 32, 38),
					})
					ctaTw:Play()
				end
				while frame.Visible and screen.Parent do
					task.wait(0.5)
				end
				tw:Cancel()
				stroke.Transparency = 0
				if ctaTw then
					ctaTw:Cancel()
					cta.BackgroundColor3 = Constants.Colors.Gold
				end
			end
			task.wait(0.25)
		end
	end)

	Remotes.GetEvent(Constants.RemoteNames.TutorialStateUpdate).OnClientEvent:Connect(applyState)

	Remotes.GetEvent(Constants.RemoteNames.PlayerStateUpdate).OnClientEvent:Connect(function(state: any)
		if typeof(state) ~= "table" then
			return
		end
		if state.TutorialComplete == true then
			setVisible(false)
			clearWaypoint()
		end
		if state.BasePlotId ~= nil then
			myPlotId = state.BasePlotId
			-- Re-bind pad beam once plot is known
			if panel and panel.Visible and currentPadStructureId then
				task.defer(function()
					setWaypoint(currentMarkerName, currentPadStructureId)
				end)
			end
		end
	end)

	player.CharacterAdded:Connect(function()
		if currentMarkerName and panel and panel.Visible then
			task.defer(function()
				setWaypoint(currentMarkerName, currentPadStructureId)
			end)
		end
	end)
end

return TutorialController
