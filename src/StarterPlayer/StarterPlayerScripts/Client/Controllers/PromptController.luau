--!strict
--[[
	PromptController — v70 custom ProximityPrompt pills in the ACTION LANE (spec §3.5, §5, §6).

	Every ProximityPrompt in workspace gets Style = ProximityPromptStyle.Custom LOCALLY (a replicated property set on
	the client stays local), so Roblox stops drawing its floating cards and this controller draws the prompts as
	pills in one fixed slot above the hotbar (gui WE_PromptLane, bottom edge HudLayout.ActionLaneBottomV()):
	  * height 64 v on touch (the pill IS the tap target, 44.8 px on phones) / 50 v desktop, auto width ≥ 150 v
	  * FredokaOne ActionText (ObjectText only when ActionText is empty); desktop / gamepad show a key cap
	  * hold prompts fill left → right (PromptButtonHoldBegan / Ended); touch drives the engine's own hold timer
	    with prompt:InputHoldBegin() / InputHoldEnd() — the 0.35 s console hold and the 0.6 s gate-repair hold work
	  * a finger that slides off a pill or lifts anywhere releases the hold (UserInputService.TouchEnded /
	    InputEnded + TouchMoved past HOLD_SLOP_PX), and a stale hold never swallows the next tap (merge gate #4)
	  * at most 2 pills, side by side (E + F), centred; hidden while Modal or Dead; while Driving only the
	    vehicle's own prompts
	  * OWNER-ONLY: WE_ServerBuyPrompt / WE_PanelPrompt / WE_DrivePrompt on another player's plot or vehicle get
	    Enabled = false locally (no pill, no E)
	  * the console's own WE_ServerBuyPrompt pill hides while the BUY button shows (the desktop E-hold still works);
	    any other pill moves up one slot above the BUY button meanwhile

	The engine still owns triggering (keyboard / gamepad keys, hold timing, MaxActivationDistance, Triggered on the
	server) — nothing here grants anything. If Init fails before the pills exist, prompts keep the Default style
	(adoption runs LAST, after the lane and the PromptShown handlers are up — spec risk #2).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HudConfig = require(Shared.Configs.HudConfig)
local UIUtil = require(Shared.Util.UIUtil)

local HudLayout = require(script.Parent.Parent.Modules.HudLayout)

local PromptController = {}

local LANE = HudConfig.ActionLane
local COLORS = HudConfig.Colors
local FONT_DISPLAY = HudConfig.Fonts.Display
local FONT_BODY = HudConfig.Fonts.Body
local MAX_PILLS = 2
local PILL_BG_TRANSPARENCY = 0.16
local FILL_TRANSPARENCY = 0.72
-- a held finger may wander this far (real px) outside its pill before the hold is released (forgiving on touch)
local HOLD_SLOP_PX = 24

local OWNER_ONLY: { [string]: boolean } = {}
for _, n in ipairs(LANE.OwnerOnlyPromptNames) do
	OWNER_ONLY[n] = true
end

local player = Players.LocalPlayer

type Pill = {
	Prompt: ProximityPrompt,
	Button: TextButton,
	Fill: Frame,
	Label: TextLabel,
	KeyCap: Frame,
	KeyText: TextLabel,
	InputType: Enum.ProximityPromptInputType,
	Seq: number,
	Held: boolean,
	HoldInput: InputObject?, -- the touch / mouse input that started the current hold
	Conns: { RBXScriptConnection },
}

local screen: ScreenGui? = nil
local laneFrame: Frame? = nil
local pills: { [ProximityPrompt]: Pill } = {}
local pillSeq = 0
local adopted: { [ProximityPrompt]: boolean } = setmetatable({} :: any, { __mode = "k" })
local disabledByUs: { [ProximityPrompt]: boolean } = setmetatable({} :: any, { __mode = "k" })
local suppressed: { [ProximityPrompt]: boolean } = setmetatable({} :: any, { __mode = "k" })
local myPlotId: number? = nil
local buyActive = false
local started = false
local shutDown = false
local lanePending = false
local globalConns: { RBXScriptConnection } = {}

---------------------------------------------------------------------------------------------------------------
-- ownership
---------------------------------------------------------------------------------------------------------------

local function numAttr(inst: Instance, name: string): number?
	local v = inst:GetAttribute(name)
	if typeof(v) == "number" then
		return v
	end
	return nil
end

-- the plot a world object belongs to (PlotId / BasePlotId attribute on it or an ancestor, or a Bases.PlotN folder)
local function plotIdOf(inst: Instance?): number?
	local cur = inst
	while cur and cur ~= Workspace do
		local pid = numAttr(cur, "PlotId") or numAttr(cur, "BasePlotId")
		if pid then
			return pid
		end
		local parent = cur.Parent
		if parent and parent.Name == "Bases" then
			local n = tonumber(string.match(cur.Name, "^Plot(%d+)$"))
			if n then
				return n
			end
		end
		cur = parent
	end
	return nil
end

local function ownerUserIdOf(inst: Instance?): number?
	local cur = inst
	while cur and cur ~= Workspace do
		local uid = numAttr(cur, "OwnerUserId")
		if uid then
			return uid
		end
		cur = cur.Parent
	end
	return nil
end

local function currentPlotId(): number?
	if myPlotId then
		return myPlotId
	end
	local attr = player:GetAttribute("WE_PlotId")
	if typeof(attr) == "number" then
		return attr
	end
	return nil
end

-- true = an owner-only prompt that belongs to SOMEONE ELSE (ambiguous → false, like isOwnPlotPad)
local function isForeign(prompt: ProximityPrompt): boolean
	if not OWNER_ONLY[prompt.Name] then
		return false
	end
	if prompt.Name == "WE_DrivePrompt" then
		local uid = ownerUserIdOf(prompt.Parent)
		return uid ~= nil and uid ~= 0 and uid ~= player.UserId
	end
	local mine = currentPlotId()
	local pid = plotIdOf(prompt.Parent)
	if mine == nil or pid == nil then
		return false
	end
	return pid ~= mine
end

local function applyOwnerOnly(prompt: ProximityPrompt)
	if not OWNER_ONLY[prompt.Name] then
		return
	end
	if isForeign(prompt) then
		if prompt.Enabled then
			prompt.Enabled = false
		end
		disabledByUs[prompt] = true
	elseif disabledByUs[prompt] then
		disabledByUs[prompt] = nil
		prompt.Enabled = true
	end
end

---------------------------------------------------------------------------------------------------------------
-- pills
---------------------------------------------------------------------------------------------------------------

local function isTouch(): boolean
	return HudLayout.IsTouch()
end

local function measure(text: string, size: number, font: Enum.Font): Vector2
	local ok, v = pcall(function(): Vector2
		return TextService:GetTextSize(text, size, font, Vector2.new(2000, 1000))
	end)
	if ok and typeof(v) == "Vector2" and v.X > 0 then
		return v
	end
	return Vector2.new((utf8.len(text) or #text) * size * 0.55, size)
end

local function promptText(prompt: ProximityPrompt): string
	local a = prompt.ActionText
	if a ~= "" then
		return a
	end
	return prompt.ObjectText
end

local function keyLabel(pill: Pill): string?
	local p = pill.Prompt
	if pill.InputType == Enum.ProximityPromptInputType.Touch then
		return nil
	end
	if pill.InputType == Enum.ProximityPromptInputType.Gamepad then
		local n = p.GamepadKeyCode.Name
		return (string.gsub(n, "^Button", ""))
	end
	local k = p.KeyboardKeyCode
	if k.Name == "Unknown" then
		return nil
	end
	return k.Name
end

local function vehicleModelOfSeat(): Instance?
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if not seat then
		return nil
	end
	local model = seat:FindFirstAncestorWhichIsA("Model")
	-- the vehicle is the outermost model under workspace (seats sit in sub-models)
	local cur: Instance? = model
	while cur and cur.Parent and cur.Parent ~= Workspace and cur.Parent:IsA("Model") do
		cur = cur.Parent
	end
	return cur or seat
end

local function pillWanted(pill: Pill, vehicle: Instance?): boolean
	local p = pill.Prompt
	if not p.Parent or not p.Enabled then
		return false
	end
	if suppressed[p] then
		return false
	end
	if buyActive and LANE.SuppressPromptWhenBuyButton and p.Name == "WE_ServerBuyPrompt" then
		return false
	end
	if HudLayout.GetFlag("Driving") then
		return vehicle ~= nil and p:IsDescendantOf(vehicle)
	end
	return true
end

local function sizePill(pill: Pill)
	local touch = isTouch()
	local h = if touch then LANE.PromptHeight else LANE.PromptHeightDesktop
	local text = promptText(pill.Prompt)
	pill.Label.Text = text
	local key = keyLabel(pill)
	local capW = 0
	if key then
		pill.KeyText.Text = key
		pill.KeyCap.Visible = true
		capW = LANE.KeyCapSize + 10
	else
		pill.KeyCap.Visible = false
	end
	local padL = if key then 8 else 20
	local padR = 20
	local tb = measure(text, LANE.PromptTextSize, FONT_DISPLAY)
	local textW = math.ceil(tb.X) + 4
	local w = math.max(LANE.PromptMinWidth, padL + capW + textW + padR)
	pill.Button.Size = UDim2.fromOffset(w, h)
	pill.KeyCap.Position = UDim2.new(0, padL, 0.5, 0)
	pill.KeyCap.Size = UDim2.fromOffset(LANE.KeyCapSize, LANE.KeyCapSize)
	-- centre the label in the space right of the key cap
	pill.Label.Position = UDim2.new(0, padL + capW, 0, 0)
	pill.Label.Size = UDim2.new(1, -(padL + capW + padR), 1, 0)
	local c = pill.Button:FindFirstChildOfClass("UICorner")
	if c then
		c.CornerRadius = UDim.new(0, math.floor(h / 2))
	end
	local fc = pill.Fill:FindFirstChildOfClass("UICorner")
	if fc then
		fc.CornerRadius = UDim.new(0, math.floor(h / 2))
	end
end

local function relayout()
	lanePending = false
	local lane = laneFrame
	if not lane then
		return
	end
	local vehicle = if HudLayout.GetFlag("Driving") then vehicleModelOfSeat() else nil
	local list: { Pill } = {}
	for _, pill in pairs(pills) do
		if pillWanted(pill, vehicle) then
			table.insert(list, pill)
		else
			pill.Button.Visible = false
		end
	end
	-- newest two win (E + F side by side); drawn oldest → newest, left → right
	table.sort(list, function(a: Pill, b: Pill): boolean
		return a.Seq > b.Seq
	end)
	local shown = 0
	local totalW = 0
	local h = if isTouch() then LANE.PromptHeight else LANE.PromptHeightDesktop
	for i, pill in ipairs(list) do
		if i <= MAX_PILLS then
			sizePill(pill)
			pill.Button.Visible = true
			pill.Button.LayoutOrder = pill.Seq
			totalW += pill.Button.Size.X.Offset
			shown += 1
		else
			pill.Button.Visible = false
		end
	end
	totalW += math.max(0, shown - 1) * LANE.PromptGap
	lane.Size = UDim2.fromOffset(math.max(1, totalW), h)
	-- the BUY button owns the lane slot while it shows: other pills (a terminal next to a console) sit just above it
	local bottom = HudLayout.ActionLaneBottomV()
	if buyActive then
		local buySize = if isTouch() then LANE.BuyButtonSizeTouch else LANE.BuyButtonSize
		bottom += buySize.Y.Offset + LANE.PromptGap
	end
	lane.Position = UDim2.new(0.5, 0, 1, -bottom)
	lane:SetAttribute("WE_PillCount", shown)
	HudLayout.RefreshVisibility(lane)
end

local function queueRelayout()
	if lanePending then
		return
	end
	lanePending = true
	task.defer(relayout)
end

local function endHold(pill: Pill)
	pill.HoldInput = nil
	if pill.Held then
		pill.Held = false
		pcall(function()
			pill.Prompt:InputHoldEnd()
		end)
	end
end

local function inputFinished(input: InputObject?): boolean
	if input == nil then
		return true
	end
	local st = input.UserInputState
	return st == Enum.UserInputState.End or st == Enum.UserInputState.Cancel
end

-- merge gate #4: release every hold that `input` owns (it ended, or the finger left its pill). A hold whose input
-- is unknown is released by any touch / left-click end, so a missed InputEnded can never leave Held = true.
local function releaseHoldsOf(input: InputObject)
	for _, pill in pairs(pills) do
		if pill.Held and (pill.HoldInput == nil or pill.HoldInput == input or inputFinished(pill.HoldInput)) then
			endHold(pill)
		end
	end
end

local function outsidePill(pill: Pill, pos: Vector3): boolean
	local b = pill.Button
	local a, sz = b.AbsolutePosition, b.AbsoluteSize
	if sz.X <= 0 or sz.Y <= 0 then
		return false
	end
	-- InputObject.Position is in screen px with the topbar inset excluded, like AbsolutePosition of a gui that
	-- respects the inset; the slop covers the difference on guis with other insets
	local slop = HOLD_SLOP_PX
	return pos.X < a.X - slop or pos.X > a.X + sz.X + slop or pos.Y < a.Y - slop or pos.Y > a.Y + sz.Y + slop
end

local function resetFill(pill: Pill, seconds: number?)
	local t = seconds or 0.12
	pcall(function()
		TweenService:Create(pill.Fill, TweenInfo.new(t), { Size = UDim2.fromScale(0, 1) }):Play()
	end)
end

local function removePill(prompt: ProximityPrompt)
	local pill = pills[prompt]
	if not pill then
		return
	end
	pills[prompt] = nil
	endHold(pill)
	for _, c in ipairs(pill.Conns) do
		c:Disconnect()
	end
	pill.Button:Destroy()
	queueRelayout()
end

local function makePill(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): Pill?
	local lane = laneFrame
	if not lane then
		return nil
	end
	pillSeq += 1
	local btn = Instance.new("TextButton")
	btn.Name = "Pill"
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.BackgroundColor3 = COLORS.PillBg
	btn.BackgroundTransparency = PILL_BG_TRANSPARENCY
	btn.BorderSizePixel = 0
	btn.ClipsDescendants = true
	btn.Active = true
	btn.Selectable = false -- gamepad uses the prompt key, not GUI selection
	btn.Visible = false
	btn.LayoutOrder = pillSeq
	btn:SetAttribute("PromptName", prompt.Name)
	UIUtil.Corner(btn, 32)
	local stroke = UIUtil.Stroke(btn, COLORS.PillStroke, 2)
	stroke.Transparency = 0.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	local fill = Instance.new("Frame")
	fill.Name = "HoldFill"
	fill.BackgroundColor3 = LANE.HoldFill
	fill.BackgroundTransparency = FILL_TRANSPARENCY
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Active = false
	fill.ZIndex = 1
	fill.Parent = btn
	UIUtil.Corner(fill, 32)

	local cap = Instance.new("Frame")
	cap.Name = "KeyCap"
	cap.AnchorPoint = Vector2.new(0, 0.5)
	cap.BackgroundColor3 = Color3.fromRGB(242, 244, 246)
	cap.BorderSizePixel = 0
	cap.Active = false
	cap.Visible = false
	cap.ZIndex = 2
	cap.Parent = btn
	UIUtil.Corner(cap, 8)
	local keyText = Instance.new("TextLabel")
	keyText.Name = "Key"
	keyText.BackgroundTransparency = 1
	keyText.Size = UDim2.fromScale(1, 1)
	keyText.Font = FONT_BODY
	keyText.TextSize = 17
	keyText.TextColor3 = Color3.fromRGB(21, 24, 27)
	keyText.ZIndex = 3
	keyText.Parent = cap

	local label = Instance.new("TextLabel")
	label.Name = "Action"
	label.BackgroundTransparency = 1
	label.Font = FONT_DISPLAY
	label.TextSize = LANE.PromptTextSize
	label.TextColor3 = COLORS.White
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.ZIndex = 3
	label.Parent = btn
	UIUtil.TextOutline(label, 1.3)

	local pill: Pill = {
		Prompt = prompt,
		Button = btn,
		Fill = fill,
		Label = label,
		KeyCap = cap,
		KeyText = keyText,
		InputType = inputType,
		Seq = pillSeq,
		Held = false,
		HoldInput = nil,
		Conns = {},
	}

	-- touch / click: drive the engine's hold (HoldDuration 0 prompts trigger on InputHoldBegin)
	table.insert(pill.Conns, btn.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		local isTap = t == Enum.UserInputType.Touch or (t == Enum.UserInputType.MouseButton1 and prompt.ClickablePrompt)
		if not isTap or input.UserInputState == Enum.UserInputState.Change then
			return
		end
		if pill.Held then
			if pill.HoldInput ~= nil and pill.HoldInput ~= input and not inputFinished(pill.HoldInput) then
				return -- a second finger on a pill that is already held
			end
			endHold(pill) -- stale hold (its finger is gone): release it, then start this tap's hold
		end
		pill.Held = true
		pill.HoldInput = input
		pcall(function()
			prompt:InputHoldBegin()
		end)
	end))
	table.insert(pill.Conns, btn.InputEnded:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			endHold(pill)
		end
	end))
	table.insert(pill.Conns, prompt.PromptButtonHoldBegan:Connect(function()
		local secs = math.max(0.01, prompt.HoldDuration)
		fill.Size = UDim2.fromScale(0, 1)
		pcall(function()
			TweenService:Create(fill, TweenInfo.new(secs, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) }):Play()
		end)
	end))
	table.insert(pill.Conns, prompt.PromptButtonHoldEnded:Connect(function()
		resetFill(pill)
	end))
	table.insert(pill.Conns, prompt.Triggered:Connect(function()
		resetFill(pill, 0.2)
	end))
	for _, prop in ipairs({ "ActionText", "ObjectText", "KeyboardKeyCode", "GamepadKeyCode", "Enabled" }) do
		table.insert(pill.Conns, prompt:GetPropertyChangedSignal(prop):Connect(queueRelayout))
	end
	table.insert(pill.Conns, prompt.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			removePill(prompt)
		end
	end))

	btn.Parent = lane
	return pill
end

---------------------------------------------------------------------------------------------------------------
-- adoption (Style = Custom) + service events
---------------------------------------------------------------------------------------------------------------

local function adopt(inst: Instance)
	if shutDown or not inst:IsA("ProximityPrompt") then
		return
	end
	local prompt: ProximityPrompt = inst
	if adopted[prompt] then
		return
	end
	adopted[prompt] = true
	pcall(function()
		prompt.Style = Enum.ProximityPromptStyle.Custom
	end)
	if OWNER_ONLY[prompt.Name] then
		applyOwnerOnly(prompt)
		prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
			-- the server re-replicating Enabled = true must not re-open someone else's console / terminal / car
			if prompt.Enabled and isForeign(prompt) then
				prompt.Enabled = false
				disabledByUs[prompt] = true
			end
		end)
	end
end

local function onShown(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	if not adopted[prompt] then
		adopt(prompt) -- a prompt the DescendantAdded sweep has not seen yet (takes effect from now on)
	end
	if prompt.Style ~= Enum.ProximityPromptStyle.Custom then
		return -- the engine draws it (adoption refused)
	end
	if OWNER_ONLY[prompt.Name] and isForeign(prompt) then
		applyOwnerOnly(prompt)
		return
	end
	-- prompts the v70 HUD removed ("Open Base", "Hold to capture"): an older client-made copy never shows
	if prompt.Name == "WE_WorldPrompt" and table.find(LANE.RemovePrompts, prompt.ActionText) then
		prompt.Enabled = false
		return
	end
	local pill = pills[prompt]
	if pill then
		pill.InputType = inputType
	else
		local made = makePill(prompt, inputType)
		if not made then
			return
		end
		pills[prompt] = made
	end
	queueRelayout()
end

---------------------------------------------------------------------------------------------------------------
-- public
---------------------------------------------------------------------------------------------------------------

--[[ WorldPromptController: the local player's plot (owner-only prompts re-evaluate). ]]
function PromptController.SetMyPlotId(plotId: number?)
	if myPlotId == plotId then
		return
	end
	myPlotId = plotId
	for prompt in pairs(adopted) do
		if prompt.Parent and OWNER_ONLY[prompt.Name] then
			applyOwnerOnly(prompt)
		end
	end
	queueRelayout()
end

--[[ WorldPromptController: the console BUY button is showing → hide WE_ServerBuyPrompt pills. ]]
function PromptController.SetBuyButtonActive(on: boolean)
	if buyActive == on then
		return
	end
	buyActive = on
	queueRelayout()
end

--[[ Hide one prompt's pill (the engine keeps its keyboard / gamepad key). E.g. a MAX or locked console. ]]
function PromptController.SetSuppressed(prompt: ProximityPrompt, on: boolean)
	if (suppressed[prompt] == true) == on then
		return
	end
	if on then
		suppressed[prompt] = true
	else
		suppressed[prompt] = nil
	end
	queueRelayout()
end

--[[ Is this owner-only prompt someone else's (WorldPromptController / tests). ]]
function PromptController.IsForeign(prompt: ProximityPrompt): boolean
	return isForeign(prompt)
end

function PromptController.Init()
	if started then
		return
	end
	started = true
	local pg = player:WaitForChild("PlayerGui")
	local old = pg:FindFirstChild("WE_PromptLane")
	if old then
		old:Destroy()
	end
	local sg = Instance.new("ScreenGui")
	sg.Name = "WE_PromptLane"
	sg.DisplayOrder = HudConfig.DisplayOrder.WE_PromptLane
	HudLayout.ApplyScreen(sg, { Insets = "Core" })

	local lane = Instance.new("Frame")
	lane.Name = "Lane"
	lane.AnchorPoint = Vector2.new(0.5, 1)
	lane.Position = UDim2.new(0.5, 0, 1, -HudLayout.ActionLaneBottomV())
	lane.Size = UDim2.fromOffset(1, LANE.PromptHeight)
	lane.BackgroundTransparency = 1
	lane.BorderSizePixel = 0
	lane.Active = false
	lane.Parent = sg
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, LANE.PromptGap)
	list.Parent = lane
	sg.Parent = pg
	screen = sg
	laneFrame = lane
	HudLayout.BindVisibility(lane, { HideWhen = LANE.HideWhen })
	HudLayout.SetRect("ActionLane", lane)

	-- handlers BEFORE adoption: a Custom prompt must never show without a pill
	local function keep(c: RBXScriptConnection)
		table.insert(globalConns, c)
	end
	keep(ProximityPromptService.PromptShown:Connect(onShown))
	keep(ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		removePill(prompt)
	end))
	keep(HudLayout.FlagChanged:Connect(function(name: string, _on: boolean)
		if name == "Driving" or name == "Modal" or name == "Dead" then
			if name ~= "Driving" then
				for _, pill in pairs(pills) do
					endHold(pill)
				end
			end
			queueRelayout()
		end
	end))
	keep(HudLayout.LayoutChanged:Connect(queueRelayout))
	-- merge gate #4 backstop: a finger lifted anywhere (even off the pill, where the button's own InputEnded may
	-- never fire) releases its hold; a finger that slides off the pill releases it too
	keep(UserInputService.TouchEnded:Connect(function(input: InputObject)
		releaseHoldsOf(input)
	end))
	keep(UserInputService.InputEnded:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			releaseHoldsOf(input)
		end
	end))
	keep(UserInputService.TouchMoved:Connect(function(input: InputObject)
		for _, pill in pairs(pills) do
			if pill.Held and pill.HoldInput == input and outsidePill(pill, input.Position) then
				endHold(pill)
			end
		end
	end))
	keep(player:GetAttributeChangedSignal("WE_PlotId"):Connect(function()
		for prompt in pairs(adopted) do
			if prompt.Parent and OWNER_ONLY[prompt.Name] then
				applyOwnerOnly(prompt)
			end
		end
	end))

	-- adoption LAST (spec risk #2)
	keep(Workspace.DescendantAdded:Connect(function(inst: Instance)
		if inst:IsA("ProximityPrompt") then
			adopt(inst)
		end
	end))
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("ProximityPrompt") then
			pcall(adopt, inst)
		end
	end
	relayout()
end

--[[
	Back to Roblox's own prompt UI (UIController calls this when Init failed half-way — spec risk #2): every
	adopted prompt gets Style = Default again, the lane gui goes, no more adoption. Owner-only prompts on other
	players' plots stay disabled. Safe to call more than once.
]]
function PromptController.Shutdown()
	shutDown = true
	for _, c in ipairs(globalConns) do
		c:Disconnect()
	end
	table.clear(globalConns)
	for prompt in pairs(pills) do
		removePill(prompt)
	end
	for prompt in pairs(adopted) do
		pcall(function()
			prompt.Style = Enum.ProximityPromptStyle.Default
		end)
	end
	local sg = screen
	if sg then
		sg:Destroy()
	end
	screen = nil
	laneFrame = nil
end

--[[ QA: how many pills are holding their prompt right now (merge gate #4 harness check). ]]
function PromptController.GetHeldCount(): number
	local n = 0
	for _, pill in pairs(pills) do
		if pill.Held then
			n += 1
		end
	end
	return n
end

--[[ QA: texts of the pills on screen, left → right. ]]
function PromptController.GetPillTexts(): { string }
	local list: { Pill } = {}
	for _, pill in pairs(pills) do
		if pill.Button.Visible then
			table.insert(list, pill)
		end
	end
	table.sort(list, function(a: Pill, b: Pill): boolean
		return a.Seq < b.Seq
	end)
	local out = {}
	for _, pill in ipairs(list) do
		table.insert(out, pill.Label.Text)
	end
	return out
end

return PromptController
