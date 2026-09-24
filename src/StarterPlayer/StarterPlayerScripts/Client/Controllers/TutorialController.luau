--!strict
--[[
	Interactive tutorial (v31 steps): claim → collect → click-dropper → CC → recruit → barracks → jeep → outpost.

	v70 "clean screen" (spec §3.4 item 3): the step is an OBJECTIVE CHIP in the top-centre stack (HudLayout
	TopStack "Objective"; was a 94 %-wide 168 v card across mid-screen):
	  ( 2 )  Collect cash                              [ GO ]  Skip
	         Touch the Money Collector (green ATM …
	≤ 460×64 v pill (HudConfig.TopStack.Objective), 2 v gold edge. Step disc, title (Display font), hint (Body
	font, up to 2 lines, "…" when longer), GO (64 v hit: runs the step's CTA — BUY/ARMY/GARAGE opener or re-aims
	the beam), Skip (touch-size hit; tap twice — "Sure?" — so a stray tap never ends the tutorial).
	While a step is active the HudLayout flag "Tutorial" is on (offers wait). The chip hides while a panel is open
	(Modal), while Driving (the beam keeps guiding) and while dead. The world guide beam + SelectionBox are unchanged.
	v71 P0-6: every per-player target resolves to the player's OWN plot BEFORE any name lookup (the Tutorial_* marker
	parts are all built on Plot 1, so 5 of 6 players were led into someone else's base):
	  ClaimBase -> own PlayerSpawn · Income -> own WE_MoneyCollector · ClickDropper -> own WE_ManualDropper ·
	  CommandCenter / Barracks -> own console (ConsoleLocator) · Recruit / Jeep -> no beam (GO opens Army / Garage) ·
	  Outpost -> nearest uncontested, walkable territory. No plot id yet -> no beam (re-aimed when it arrives).
	  A marker part is only ever shown when it IS the target (unknown future steps, and only inside the own plot).
	v71 console-only buying: the CommandCenter / Barracks GO only re-aims the beam at the console; it never opens the
	Base panel (that panel cannot buy any more).
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local HudConfig = require(Shared.Configs.HudConfig)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)
local TutorialConfig = require(Shared.Configs.TutorialConfig)
local TerritoryConfig = require(Shared.Configs.TerritoryConfig)
local ConsoleLocator = require(Shared.Util.ConsoleLocator)

local HudLayout = require(script.Parent.Parent.Modules.HudLayout)

local TutorialController = {}

local player = Players.LocalPlayer

local _gui: ScreenGui? = nil
local guideBeam: Beam? = nil
local attach0: Attachment? = nil
local attach1: Attachment? = nil
local highlightPart: BasePart? = nil
local currentMarkerName: string? = nil
local currentPadStructureId: string? = nil
local currentCtaAction: string? = nil
local currentStepId: string? = nil
local myPlotId: number? = nil

-- objective chip
local OBJ = HudConfig.TopStack.Objective
local chip: Frame? = nil
local discLabel: TextLabel? = nil
local titleLabel: TextLabel? = nil
local hintLabel: TextLabel? = nil
local goBtn: TextButton? = nil
local skipBtn: TextButton? = nil
local skipLabel: TextLabel? = nil
local stepActive = false -- a step is showing (drives the "Tutorial" flag and the chip)
local rawTitle = ""
local rawHint = ""

-- chip internals, v (the gui carries HudLayout's MobileScale)
local PAD_L = 10
local DISC = 36
local DISC_GAP = 10
local TEXT_GAP = 6
local PAD_R = 2
local TITLE_H = 22
local GO_FACE = Vector2.new(56, 44)
local CORNER = 16
local GOLD = HudConfig.Colors.Gold
local DARK_INK = HudConfig.Rail.Badge.ReadyText
local SKIP_CONFIRM_SECONDS = 3

local function clearWaypoint()
	if guideBeam then
		guideBeam:Destroy()
		guideBeam = nil
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

-- Show a tutorial marker part only when it IS the resolved target (P0-6: the Tutorial_* markers are built on Plot 1;
-- revealing them led every other player to Plot 1). Everything else stays hidden.
local function syncMarkerVisibility(activePart: BasePart?)
	local tag = Constants.Tags.TutorialMarker
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		if inst:IsA("BasePart") then
			local isActive = activePart ~= nil and inst == activePart
			-- MapSetup starts Transparency=1; must set Transparency (not only LocalTransparencyModifier)
			inst.Transparency = if isActive then 0.25 else 1
			inst.LocalTransparencyModifier = 0
			for _, child in ipairs(inst:GetDescendants()) do
				if child:IsA("BillboardGui") or child:IsA("SurfaceGui") then
					child.Enabled = isActive == true
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------
-- P0-6 target resolution: the player's OWN plot first, never a fixed world marker (CLAUDE.md "Pointers")
---------------------------------------------------------------------------------------------------------------

local MANUAL_DROPPER_TAG = "WE_ManualDropper" -- ManualDropperService TAG_DROPPER
local OUTPOST_TIER_GAP = 1e6 -- a lower tier always wins over distance

local function ownPlotPad(plotId: number): BasePart?
	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.BasePlot)) do
		if inst:IsA("BasePart") and inst:GetAttribute("PlotId") == plotId then
			return inst
		end
	end
	return nil
end

-- plot-local rectangle test on the plot pad (the pad carries the plot yaw, so rotated plots need no extra math)
local function insidePad(pad: BasePart, pos: Vector3): boolean
	local lp = pad.CFrame:PointToObjectSpace(pos)
	return math.abs(lp.X) <= pad.Size.X * 0.5 and math.abs(lp.Z) <= pad.Size.Z * 0.5
end

-- nearest part with `tag` whose PlotId is exactly plotId (a part with no PlotId is never "own")
local function nearestOwnTagged(tag: string, plotId: number, origin: Vector3): BasePart?
	local best: BasePart? = nil
	local bestD = math.huge
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		if inst:IsA("BasePart") and inst:GetAttribute("PlotId") == plotId and inst:IsDescendantOf(Workspace) then
			local d = (inst.Position - origin).Magnitude
			if d < bestD then
				bestD = d
				best = inst
			end
		end
	end
	return best
end

local function ownSpawn(plotId: number): BasePart?
	local root = Workspace:FindFirstChild("WarEmpireSetup")
	local bases = root and root:FindFirstChild("Bases")
	local folder = bases and bases:FindFirstChild("Plot" .. tostring(plotId))
	local sp = folder and folder:FindFirstChild("PlayerSpawn")
	if sp and sp:IsA("BasePart") then
		return sp
	end
	return ownPlotPad(plotId) -- the spawn streamed out / renamed: the plot pad is still inside the plot
end

-- Outpost: the nearest zone the player can take on foot. Tiers: neutral land zone, then any uncontested land zone
-- they do not own, then any uncontested zone (oil rigs need a boat, forts have guards), then anything.
local function nearestOutpost(origin: Vector3, userId: number): BasePart?
	local ot = TerritoryConfig.OwnerTypes
	local best: BasePart? = nil
	local bestScore = math.huge
	local seen: { [Instance]: boolean } = {}
	for _, tag in ipairs({ Constants.Tags.Territory, Constants.Tags.CaptureZone }) do
		for _, inst in ipairs(CollectionService:GetTagged(tag)) do
			if not seen[inst] and inst:IsA("BasePart") and inst:IsDescendantOf(Workspace) then
				seen[inst] = true
				local tid = inst:GetAttribute("TerritoryId")
				local def = if typeof(tid) == "string" then (TerritoryConfig.Territories :: any)[tid] else nil
				local ownerType = inst:GetAttribute("OwnerType")
				local contested = ownerType == ot.Contested
				local mine = ownerType == ot.Player and inst:GetAttribute("OwnerUserId") == userId
				local hard = def ~= nil and (def.IsOilRig == true or def.IsFortress == true)
				local tier = if contested or mine then 3 elseif hard then 2 elseif ownerType ~= nil and ownerType ~= ot.Neutral then 1 else 0
				local score = tier * OUTPOST_TIER_GAP + (inst.Position - origin).Magnitude
				if score < bestScore then
					bestScore = score
					best = inst
				end
			end
		end
	end
	return best
end

--[[ Where the tutorial beam points for a step. Pure (reads the world, builds nothing), exported for the headless
	test (every target except Outpost lies inside the player's own plot, plots 1-6, flat and rotated).
	stepId: TutorialStateUpdate.Id; markerName / padStructureId: the step's MarkerName / PadStructureId;
	plotId: the player's own plot (nil = not known yet -> no per-player beam); origin: where "nearest" is measured. ]]
function TutorialController.ResolveTarget(stepId: string?, markerName: string?, padStructureId: string?, plotId: number?, origin: Vector3, userId: number?): BasePart?
	if stepId == "Outpost" or markerName == "Tutorial_Outpost" then
		return nearestOutpost(origin, userId or player.UserId)
	end
	if stepId == "RecruitSoldiers" or markerName == "Tutorial_Recruit" or stepId == "Jeep" or markerName == "Tutorial_Jeep" then
		return nil -- GO opens Army / the Garage; nothing to walk to
	end
	if plotId == nil then
		return nil -- per-player target: wait for the plot id (applyPlotId re-aims)
	end
	if typeof(padStructureId) == "string" and padStructureId ~= "" then
		return ConsoleLocator.Find(plotId, padStructureId)
	end
	if stepId == "ClaimBase" or markerName == "Tutorial_ClaimBase" then
		return ownSpawn(plotId)
	end
	if stepId == "Income" or markerName == "Tutorial_Income" then
		return nearestOwnTagged(Constants.Tags.MoneyCollector, plotId, origin)
	end
	if stepId == "ClickDropper" or markerName == "Tutorial_Dropper" then
		return nearestOwnTagged(MANUAL_DROPPER_TAG, plotId, origin)
	end
	-- unknown (future) step: its named marker, but only when it lies inside the player's own plot
	if typeof(markerName) == "string" and markerName ~= "" then
		local pad = ownPlotPad(plotId)
		if pad then
			for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.TutorialMarker)) do
				if inst:IsA("BasePart") and (inst.Name == markerName or inst:GetAttribute("TutorialStepId") == markerName)
					and insidePad(pad, inst.Position) then
					return inst
				end
			end
		end
	end
	return nil
end

local function originPos(): Vector3
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp.Position
	end
	local pad = if myPlotId ~= nil then ownPlotPad(myPlotId) else nil
	return if pad then pad.Position else Vector3.zero
end

local function setWaypoint(markerName: string?, padStructureId: string?)
	clearWaypoint()
	currentMarkerName = markerName
	currentPadStructureId = padStructureId
	local target = TutorialController.ResolveTarget(currentStepId, markerName, padStructureId, myPlotId, originPos())
	syncMarkerVisibility(target)
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

	local a0 = Instance.new("Attachment")
	a0.Name = "WE_TutAtt0"
	a0.Parent = hrp
	attach0 = a0
	local a1 = Instance.new("Attachment")
	a1.Name = "WE_TutAtt1"
	a1.Parent = target
	attach1 = a1

	local beam = Instance.new("Beam")
	beam.Name = "WE_TutorialBeam"
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.FaceCamera = true
	-- v68: subtle guide (was a thick glowing neon line): thin, mostly transparent, fading out toward the target
	beam.Width0 = 0.22
	beam.Width1 = 0.12
	beam.Color = ColorSequence.new(Color3.fromRGB(240, 214, 110))
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0.85) })
	beam.LightEmission = 0.2
	beam.Parent = hrp
	guideBeam = beam
end

---------------------------------------------------------------------------------------------------------------
-- objective chip
---------------------------------------------------------------------------------------------------------------

local function touchMinV(): number
	if HudLayout.IsTouch() then
		-- 64 v = 44.8 real px at the smallest HUD scale (0.70)
		return math.max(HudConfig.Hotbar.Slot, math.ceil(HudConfig.Scale.TouchMinPx / HudConfig.Scale.Min))
	end
	return 0
end

local function goHitV(): number
	return math.max(OBJ.GoHit, touchMinV())
end

local function skipHitV(): number
	return math.max(OBJ.SkipHit, touchMinV())
end

local function chipWidthV(): number
	return math.floor(math.min(OBJ.MaxWidth, HudLayout.TopStackMaxWidthV()))
end

-- rendered size of `text` in v (text size and width are both v, so the gui's UIScale cancels out)
local function measure(text: string, size: number, font: Enum.Font, widthV: number): Vector2
	local ok, v = pcall(function(): Vector2
		return TextService:GetTextSize(text, size, font, Vector2.new(widthV, 10000))
	end)
	if ok and typeof(v) == "Vector2" then
		return v
	end
	return Vector2.new(#text * size * 0.55, size)
end

local function lineCount(text: string, size: number, font: Enum.Font, widthV: number): number
	if text == "" then
		return 0
	end
	local h = measure(text, size, font, widthV).Y
	return math.max(1, math.floor(h / size + 0.5))
end

-- `text` cut on a word boundary + "…" so it fits in maxLines lines of widthV (TextTruncate stays on as a backstop)
local function fitText(text: string, size: number, font: Enum.Font, widthV: number, maxLines: number): string
	if lineCount(text, size, font, widthV) <= maxLines then
		return text
	end
	local words = string.split(text, " ")
	local lo, hi = 1, #words
	local best = ""
	while lo <= hi do
		local mid = (lo + hi) // 2
		local candidate = table.concat(words, " ", 1, mid) .. "…"
		if lineCount(candidate, size, font, widthV) <= maxLines then
			best = candidate
			lo = mid + 1
		else
			hi = mid - 1
		end
	end
	if best == "" then
		best = string.sub(text, 1, math.max(1, math.floor(widthV / (size * 0.6)))) .. "…"
	end
	return best
end

-- Size the chip to the current scale and lay the title / hint out for 0, 1 or 2 hint lines.
local function layoutChip()
	local c = chip
	local title = titleLabel
	local hint = hintLabel
	local go = goBtn
	local skip = skipBtn
	if not (c and title and hint and go and skip) then
		return
	end
	local w = chipWidthV()
	local h = OBJ.Height
	c.Size = UDim2.fromOffset(w, h)
	local goW = if go.Visible then goHitV() else 0
	local skipW = skipHitV()
	go.Size = UDim2.fromOffset(goW, h)
	go.Position = UDim2.new(1, -(PAD_R + skipW), 0.5, 0)
	skip.Size = UDim2.fromOffset(skipW, h)
	local left = PAD_L + DISC + DISC_GAP
	local textW = math.max(60, w - left - TEXT_GAP - goW - skipW - PAD_R)

	title.Text = fitText(rawTitle, OBJ.TitleSize, HudConfig.Fonts.Display, textW, 1)
	local lines = math.min(2, lineCount(rawHint, OBJ.HintSize, HudConfig.Fonts.Body, textW))
	hint.Text = fitText(rawHint, OBJ.HintSize, HudConfig.Fonts.Body, textW, 2)
	hint.Visible = lines > 0
	local hintH = lines * OBJ.HintSize + 2
	local blockH = TITLE_H + (if lines > 0 then hintH else 0)
	local top = math.max(3, math.floor((h - blockH) / 2))
	title.Position = UDim2.fromOffset(left, top)
	title.Size = UDim2.fromOffset(textW, TITLE_H)
	hint.Position = UDim2.fromOffset(left, top + TITLE_H)
	hint.Size = UDim2.fromOffset(textW, math.max(hintH, 1))
end

local skipArmedAt = -math.huge
local function resetSkip()
	skipArmedAt = -math.huge
	local l = skipLabel
	if l then
		l.Text = "Skip"
		l.TextColor3 = HudConfig.Colors.White
		l.TextTransparency = 0.35
	end
end

local function setVisible(open: boolean)
	if stepActive ~= open then
		stepActive = open
		HudLayout.SetFlag("Tutorial", open)
		local c = chip
		if c then
			HudLayout.RefreshVisibility(c)
		end
	end
	if not open then
		clearWaypoint()
		syncMarkerVisibility(nil)
		resetSkip()
	end
end

local function runCta()
	local action = currentCtaAction
	-- CTA silent (avoid Output spam)
	if action == "PadBuy" then
		-- v71: buying happens at the console only — GO re-aims the beam at it (never opens the Base panel to buy)
		setWaypoint(currentMarkerName, currentPadStructureId)
	elseif action == "OpenBase" then
		-- Base overview (GO rows guide to consoles; it cannot buy)
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
	elseif action == "OpenArmy" then
		local ok, ArmyController = pcall(function()
			return require(script.Parent.ArmyController)
		end)
		if ok and ArmyController and ArmyController.Open then
			ArmyController.Open()
		end
		setWaypoint(currentMarkerName, currentPadStructureId)
	else
		-- Capture / WatchHud / unknown: re-aim beam
		setWaypoint(currentMarkerName, currentPadStructureId)
	end
end

local lastApplyAt = 0.0
local APPLY_DEBOUNCE = 0.2

local pendingPayload: any = nil
local pendingScheduled = false

local function applyState(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local now = os.clock()
	if (now - lastApplyAt) < APPLY_DEBOUNCE and payload.Complete ~= true then
		-- coalesce bursty pushes; always allow Complete through.
		-- v69: keep the NEWEST payload and apply it when the window ends. It used to be dropped, so a step
		-- advance pushed right after the join push (Claim → Collect) left the panel on the old step.
		pendingPayload = payload
		if not pendingScheduled then
			pendingScheduled = true
			task.delay(APPLY_DEBOUNCE + 0.05, function()
				pendingScheduled = false
				local latest = pendingPayload
				pendingPayload = nil
				if latest ~= nil then
					applyState(latest)
				end
			end)
		end
		return
	end
	pendingPayload = nil
	lastApplyAt = now
	if payload.Complete == true then
		setVisible(false)
		currentCtaAction = nil
		return
	end

	local step = tonumber(payload.Step) or 0
	local total = tonumber(payload.Total) or TutorialConfig.StepCount()
	rawTitle = tostring(payload.Title or "Tutorial")
	rawHint = tostring(payload.Hint or "")
	local disc = discLabel
	if disc then
		disc.Text = tostring(math.clamp(step, 1, math.max(1, total)))
	end

	local padSid = if typeof(payload.PadStructureId) == "string" then payload.PadStructureId else nil
	local marker = if typeof(payload.MarkerName) == "string" then payload.MarkerName else nil
	currentStepId = if typeof(payload.Id) == "string" then payload.Id else nil
	currentCtaAction = if typeof(payload.CtaAction) == "string" and payload.CtaAction ~= "" then payload.CtaAction else nil
	setWaypoint(marker, padSid)

	local go = goBtn
	if go then
		go.Visible = currentCtaAction ~= nil
	end
	resetSkip()
	layoutChip()
	setVisible(true)
end

local function buildChip(screen: ScreenGui)
	local c = Instance.new("Frame")
	c.Name = "Objective"
	c.AnchorPoint = Vector2.new(0.5, 0)
	c.Position = UDim2.new(0.5, 0, 0, HudConfig.TopStack.Top) -- Y is rewritten by HudLayout's top stack
	c.Size = UDim2.fromOffset(chipWidthV(), OBJ.Height)
	c.BackgroundColor3 = HudConfig.Colors.PillBg
	c.BackgroundTransparency = 0.16
	c.BorderSizePixel = 0
	c.Active = true -- taps on the chip never fall through to the world
	c.Visible = false
	c.ZIndex = 2
	c.Parent = screen
	UIUtil.Corner(c, CORNER)
	local st = UIUtil.Stroke(c, GOLD, 2)
	chip = c

	local disc = Instance.new("TextLabel")
	disc.Name = "Step"
	disc.AnchorPoint = Vector2.new(0, 0.5)
	disc.Position = UDim2.new(0, PAD_L, 0.5, 0)
	disc.Size = UDim2.fromOffset(DISC, DISC)
	disc.BackgroundColor3 = GOLD
	disc.BorderSizePixel = 0
	disc.Font = HudConfig.Fonts.Display
	disc.TextSize = OBJ.TitleSize
	disc.TextColor3 = DARK_INK
	disc.Text = "1"
	disc.Active = false
	disc.ZIndex = 3
	disc.Parent = c
	UIUtil.Corner(disc, math.ceil(DISC / 2))
	discLabel = disc

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Font = HudConfig.Fonts.Display
	title.TextSize = OBJ.TitleSize
	title.TextColor3 = HudConfig.Colors.White
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Text = ""
	title.Active = false
	title.ZIndex = 3
	title.Parent = c
	UIUtil.TextOutline(title, 1.4)
	titleLabel = title

	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.BackgroundTransparency = 1
	hint.Font = HudConfig.Fonts.Body
	hint.TextSize = OBJ.HintSize
	hint.TextColor3 = HudConfig.Colors.White
	hint.TextTransparency = 0.2
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextYAlignment = Enum.TextYAlignment.Top
	hint.TextWrapped = true
	hint.TextTruncate = Enum.TextTruncate.AtEnd
	hint.Text = ""
	hint.Active = false
	hint.ZIndex = 3
	hint.Parent = c
	hintLabel = hint

	-- GO: transparent touch-size hit area around a gold face (runs the step's CTA)
	local go = Instance.new("TextButton")
	go.Name = "Go"
	go.AnchorPoint = Vector2.new(1, 0.5)
	go.BackgroundTransparency = 1
	go.BorderSizePixel = 0
	go.AutoButtonColor = false
	go.Text = ""
	go.Active = true
	go.Visible = false
	go.ZIndex = 3
	go.Parent = c
	local face = Instance.new("TextLabel")
	face.Name = "Face"
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.fromScale(0.5, 0.5)
	face.Size = UDim2.fromOffset(GO_FACE.X, GO_FACE.Y)
	face.BackgroundColor3 = GOLD
	face.BorderSizePixel = 0
	face.Font = HudConfig.Fonts.Display
	face.TextSize = OBJ.TitleSize
	face.TextColor3 = DARK_INK
	face.Text = "GO"
	face.Active = false
	face.ZIndex = 4
	face.Parent = go
	UIUtil.Corner(face, 12)
	local faceStroke = UIUtil.Stroke(face, Color3.fromRGB(107, 77, 0), 2)
	faceStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border -- the face is a TextLabel: edge, not glyph outline
	local press = Instance.new("UIScale")
	press.Parent = face
	go.MouseButton1Down:Connect(function()
		press.Scale = HudConfig.Rail.PressScale
	end)
	go.MouseButton1Up:Connect(function()
		press.Scale = 1
	end)
	go.MouseLeave:Connect(function()
		press.Scale = 1
	end)
	go.Activated:Connect(function()
		press.Scale = 1
		runCta()
	end)
	goBtn = go
	HudLayout.AssertTouchTarget(go, "Objective.GO")

	-- Skip: first tap arms ("Sure?"), a second tap within SKIP_CONFIRM_SECONDS skips
	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.AnchorPoint = Vector2.new(1, 0.5)
	skip.Position = UDim2.new(1, -PAD_R, 0.5, 0)
	skip.BackgroundTransparency = 1
	skip.BorderSizePixel = 0
	skip.AutoButtonColor = false
	skip.Text = ""
	skip.Active = true
	skip.ZIndex = 3
	skip.Parent = c
	local sl = Instance.new("TextLabel")
	sl.Name = "Label"
	sl.BackgroundTransparency = 1
	sl.Size = UDim2.fromScale(1, 1)
	sl.Font = HudConfig.Fonts.Body
	sl.TextSize = OBJ.HintSize
	sl.TextColor3 = HudConfig.Colors.White
	sl.TextTransparency = 0.35
	sl.Text = "Skip"
	sl.Active = false
	sl.ZIndex = 4
	sl.Parent = skip
	skipLabel = sl
	skip.Activated:Connect(function()
		local now = os.clock()
		if now - skipArmedAt > SKIP_CONFIRM_SECONDS then
			skipArmedAt = now
			sl.Text = "Sure?"
			sl.TextColor3 = HudConfig.Colors.Warn
			sl.TextTransparency = 0
			task.delay(SKIP_CONFIRM_SECONDS, function()
				if skipArmedAt == now then
					resetSkip()
				end
			end)
			return
		end
		-- Optimistic hide so Skip always feels reliable; the server confirms with Complete
		setVisible(false)
		task.spawn(function()
			Remotes.FireServer(Constants.RemoteNames.RequestSkipTutorial)
		end)
	end)
	skipBtn = skip
	HudLayout.AssertTouchTarget(skip, "Objective.Skip")

	HudLayout.BindVisibility(c, { HideWhen = { "Modal", "Driving", "Dead" } }, function(): boolean
		return stepActive
	end)
	HudLayout.RegisterTopStack("Objective", c, HudConfig.TopStack.Order.Objective, { Space = "Hud" })

	-- soft gold edge pulse while the chip is on screen
	local pulse: Tween? = nil
	local function syncPulse()
		if c.Visible and not pulse then
			local tw = TweenService:Create(st, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
				Transparency = 0.55,
			})
			tw:Play()
			pulse = tw
		elseif not c.Visible and pulse then
			pulse:Cancel()
			pulse = nil
			st.Transparency = 0
		end
	end
	c:GetPropertyChangedSignal("Visible"):Connect(syncPulse)
	syncPulse()

	HudLayout.LayoutChanged:Connect(layoutChip)
	layoutChip()
end

function TutorialController.Init()
	local pg = player:WaitForChild("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireTutorial"
	-- Core safe insets + the one HUD UIScale; DisplayOrder from HudConfig (50, under the HUD rail / TopStrip)
	HudLayout.ApplyScreen(screen, { Insets = "Core" })
	screen.Parent = pg
	_gui = screen
	buildChip(screen)

	Remotes.BindEvent(Constants.RemoteNames.TutorialStateUpdate, applyState)

	-- v69: the plot id arrives as state.Base.PlotId / BaseStatePayload.PlotId. The payload never had a top-level
	-- BasePlotId, so myPlotId stayed nil and the beam could pick another player's pad. nil = no plot (server full).
	local function applyPlotId(plotId: any)
		if typeof(plotId) ~= "number" or plotId == myPlotId then
			return
		end
		myPlotId = plotId
		-- P0-6: every per-player target (spawn, ATM, dropper, console) needs the plot: re-aim once it is known
		if stepActive then
			task.defer(function()
				setWaypoint(currentMarkerName, currentPadStructureId)
			end)
		end
	end

	Remotes.BindEvent(Constants.RemoteNames.PlayerStateUpdate, function(state: any)
		if typeof(state) ~= "table" then
			return
		end
		if state.TutorialComplete == true then
			setVisible(false)
		end
		if typeof(state.Base) == "table" then
			applyPlotId(state.Base.PlotId)
		end
	end)

	Remotes.BindEvent(Constants.RemoteNames.BaseStateUpdate, function(base: any)
		if typeof(base) == "table" then
			applyPlotId(base.PlotId)
		end
	end)

	player.CharacterAdded:Connect(function()
		if currentMarkerName and stepActive then
			task.defer(function()
				setWaypoint(currentMarkerName, currentPadStructureId)
			end)
		end
	end)
end

return TutorialController
