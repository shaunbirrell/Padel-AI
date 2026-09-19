--!strict
--[[
	World interactivity for StudioSetup-tagged parts.

	Upgrade pads (WE_UpgradeSlot): WALK-OVER auto-purchase — Touched + Heartbeat
	overlap fires RequestPurchaseUpgrade (debounced) as SECONDARY path.
	Server UpgradePadService is primary. Never grants on client.
	Edge cases: respawn clears overlap; seated-in-vehicle skips buy; multi-part
	touch uses pad keys; plot reassignment clears state; standing retry after
	debounce for failed-purchase UX. Prompt/Touched connections disconnect on
	part destroy. BillboardGuis throttled refresh on Base/Economy updates.

	ProximityPrompts only for non-buy actions (Open Base, Open Garage, capture ping, tutorial).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local BaseConfig = require(Shared.Configs.BaseConfig)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local BaseController = require(script.Parent.BaseController)
local VehicleController = require(script.Parent.VehicleController)
local NotificationController = require(script.Parent.NotificationController)

local WorldPromptController = {}

local PROMPT_NAME = "WE_WorldPrompt"
local BILLBOARD_NAME = "WE_PriceBillboard"
local DEBOUNCE_SEC = 1.1 -- mobile standing-retry; still under server rate (6/8s)
local OVERLAP_MARGIN = 2.4 -- generous pad hitbox for mobile walk-over
local BILLBOARD_THROTTLE = 0.35 -- perf: avoid refreshing every economy tick frame
local PRICE_BILLBOARD_MAX_DIST = 48 -- near-only (was 650) — mobile screen clutter
local PRICE_BILLBOARD_SIZE = UDim2.fromOffset(200, 70) -- readable on phones when close

local player = Players.LocalPlayer
local upgrades: { [string]: number } = {}
local cash = 0
local myPlotId: number? = nil
local attachedPrompt: { [Instance]: boolean } = {}
local slotParts: { [BasePart]: boolean } = {}
local slotConns: { [BasePart]: { RBXScriptConnection } } = {}
local promptConns: { [Instance]: { RBXScriptConnection } } = {}
local lastPurchaseAt: { [string]: number } = {} -- keyed by structureId (server rate is global)
local lastOverlap: { [string]: boolean } = {} -- keyed by padKey (plot|structure)
local pendingPurchase: { [string]: boolean } = {} -- structureId in-flight
local billboardDirty = false
local lastBillboardRefresh = 0
local overlapConn: RBXScriptConnection? = nil
local tagsBound = false
local maxToastAt: { [string]: number } = {} -- throttle MAX toasts while camping

local function padKey(part: BasePart, structureId: string): string
	local pid = part:GetAttribute("PlotId")
	if typeof(pid) == "number" then
		return tostring(pid) .. "|" .. structureId
	end
	return structureId
end

local function trackConn(bucket: { [Instance]: { RBXScriptConnection } }, owner: Instance, conn: RBXScriptConnection)
	local list = bucket[owner]
	if not list then
		list = {}
		bucket[owner] = list
	end
	table.insert(list, conn)
end

local function disconnectAll(bucket: { [Instance]: { RBXScriptConnection } }, owner: Instance)
	local list = bucket[owner]
	if not list then
		return
	end
	for _, c in ipairs(list) do
		c:Disconnect()
	end
	bucket[owner] = nil
end

local function makePrompt(parent: BasePart, actionText: string, objectText: string, hold: number?, maxDist: number?): ProximityPrompt
	local existing = parent:FindFirstChild(PROMPT_NAME)
	if existing and existing:IsA("ProximityPrompt") then
		existing:Destroy()
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = hold or 0
	prompt.MaxActivationDistance = maxDist or 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = parent
	return prompt
end

local function formatCost(cost: number): string
	if cost >= 1_000_000 then
		return string.format("$%.1fM", cost / 1_000_000)
	elseif cost >= 10_000 then
		return string.format("$%dk", math.floor(cost / 1000))
	end
	return "$" .. tostring(cost)
end

local function structureInfo(structureId: string): (string, number, number?, boolean, string?)
	local def = BaseConfig.Structures[structureId]
	local display = if def then def.DisplayName else structureId
	local level = upgrades[structureId] or 0
	if not def then
		return display, level, nil, false, nil
	end
	if level >= def.MaxLevel then
		return display, level, nil, true, nil
	end
	local prereqHint: string? = nil
	if def.Requires then
		for _, req in ipairs(def.Requires) do
			local have = upgrades[req.StructureId] or 0
			if have < req.Level then
				local reqDef = BaseConfig.Structures[req.StructureId]
				local reqName = if reqDef then reqDef.DisplayName else req.StructureId
				prereqHint = string.format("Needs %s L%d", reqName, req.Level)
				break
			end
		end
	end
	local nextLevel = level + 1
	local cost = def.Costs[nextLevel]
	return display, level, cost, false, prereqHint
end

local function setBillboardNearOnly(bb: BillboardGui)
	bb.Size = PRICE_BILLBOARD_SIZE
	bb.StudsOffset = Vector3.new(0, 5.2, 0)
	bb.MaxDistance = PRICE_BILLBOARD_MAX_DIST
	-- AlwaysOnTop only helps when already near (short MaxDistance); avoid map-wide stack
	bb.AlwaysOnTop = true
end

local function hidePriceBillboard(part: BasePart)
	local existing = part:FindFirstChild(BILLBOARD_NAME)
	if existing and existing:IsA("BillboardGui") then
		existing.Enabled = false
	end
	local legacy = part:FindFirstChild("Label")
	if legacy and legacy:IsA("BillboardGui") and legacy.Name ~= BILLBOARD_NAME then
		-- MapSetup may leave a non-price Label on other parts; ignore here
	end
end

local function ensurePriceBillboard(part: BasePart): BillboardGui
	local existing = part:FindFirstChild(BILLBOARD_NAME)
	if existing and existing:IsA("BillboardGui") then
		setBillboardNearOnly(existing)
		existing.Enabled = true
		return existing
	end
	local legacy = part:FindFirstChild("Label")
	if legacy and legacy:IsA("BillboardGui") then
		legacy.Name = BILLBOARD_NAME
		setBillboardNearOnly(legacy)
		legacy.Enabled = true
		return legacy
	end

	local bb = Instance.new("BillboardGui")
	bb.Name = BILLBOARD_NAME
	setBillboardNearOnly(bb)
	bb.Parent = part

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(10, 12, 14)
	backdrop.BackgroundTransparency = 0.12
	backdrop.BorderSizePixel = 0
	backdrop.Parent = bb
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = backdrop
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Stroke"
	stroke.Color = Constants.Colors.Gold
	stroke.Thickness = 2
	stroke.Transparency = 0.15
	stroke.Parent = backdrop

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Constants.Colors.Text
	label.TextStrokeTransparency = 0.45
	label.Text = "…"
	label.Parent = backdrop
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = backdrop

	return bb
end

local function applyBillboardCopy(
	bb: BillboardGui,
	titleLine: string,
	detailLine: string,
	textColor: Color3,
	strokeColor: Color3
)
	local stroke = bb:FindFirstChild("Stroke", true)
	if stroke and stroke:IsA("UIStroke") then
		stroke.Color = strokeColor
	end

	-- MapSetup price cards use Title + Cost; client-created use Text
	local titleLab = bb:FindFirstChild("Title", true)
	local costLab = bb:FindFirstChild("Cost", true)
	local textLab = bb:FindFirstChild("Text", true)

	if titleLab and titleLab:IsA("TextLabel") and costLab and costLab:IsA("TextLabel") then
		titleLab.Text = titleLine
		titleLab.TextColor3 = Color3.fromRGB(245, 245, 248)
		costLab.Text = detailLine
		costLab.TextColor3 = textColor
	elseif textLab and textLab:IsA("TextLabel") then
		if detailLine ~= "" then
			textLab.Text = titleLine .. "\n" .. detailLine
		else
			textLab.Text = titleLine
		end
		textLab.TextColor3 = textColor
	end
end

local function isOwnPlotPad(part: BasePart): boolean
	-- Hide / skip refresh for other players' plots once we know our PlotId
	if myPlotId == nil then
		return true -- loading / solo until assigned
	end
	local pid = part:GetAttribute("PlotId")
	if typeof(pid) ~= "number" then
		return true
	end
	return pid == myPlotId
end

local function refreshSlotBillboard(part: BasePart)
	local structureId = part:GetAttribute("StructureId")
	if typeof(structureId) ~= "string" then
		return
	end

	if not isOwnPlotPad(part) then
		hidePriceBillboard(part)
		return
	end

	local bb = ensurePriceBillboard(part)
	local display, level, cost, isMax, prereqHint = structureInfo(structureId)

	if isMax then
		applyBillboardCopy(
			bb,
			display,
			string.format("Lv %d  MAX", level),
			Constants.Colors.Muted,
			Color3.fromRGB(70, 80, 70)
		)
	elseif prereqHint then
		local costStr = if cost then formatCost(cost) else ""
		applyBillboardCopy(
			bb,
			display,
			string.format("Lv %d → %d %s\n%s", level, level + 1, costStr, prereqHint),
			Color3.fromRGB(200, 170, 120),
			Color3.fromRGB(160, 130, 70)
		)
	elseif cost then
		local canAfford = cash >= cost
		applyBillboardCopy(
			bb,
			display,
			string.format("Lv %d → %d\n%s", level, level + 1, formatCost(cost)),
			if canAfford then Constants.Colors.Gold else Color3.fromRGB(220, 140, 140),
			if canAfford then Constants.Colors.Gold else Color3.fromRGB(160, 70, 70)
		)
	else
		applyBillboardCopy(bb, display, "", Constants.Colors.Text, Constants.Colors.Gold)
	end
end

local function refreshAllBillboardsNow()
	lastBillboardRefresh = os.clock()
	billboardDirty = false
	local stale: { BasePart } = {}
	for part in pairs(slotParts) do
		if part.Parent then
			refreshSlotBillboard(part)
		else
			table.insert(stale, part)
		end
	end
	for _, part in ipairs(stale) do
		slotParts[part] = nil
		disconnectAll(slotConns, part)
	end
end

local function markBillboardsDirty()
	billboardDirty = true
end

local function isSeatedInVehicle(): boolean
	local char = player.Character
	if not char then
		return false
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return false
	end
	local seat = hum.SeatPart
	if seat == nil then
		return false
	end
	-- Any seat (VehicleSeat or passenger Seat) — driving over pads must not buy
	if seat:IsA("VehicleSeat") or seat:IsA("Seat") then
		return true
	end
	return false
end

local function tryPurchase(structureId: string, opts: { silentMax: boolean }?)
	local now = os.clock()
	local last = lastPurchaseAt[structureId] or 0
	if now - last < DEBOUNCE_SEC then
		return
	end
	if pendingPurchase[structureId] then
		return
	end

	local _display, _level, _cost, isMax = structureInfo(structureId)
	if isMax then
		lastPurchaseAt[structureId] = now
		local silent = opts and opts.silentMax
		local lastMax = maxToastAt[structureId] or 0
		if not silent and (now - lastMax) >= 8 then
			maxToastAt[structureId] = now
			NotificationController.Show("Already MAX", "Info", 2)
		end
		return
	end

	lastPurchaseAt[structureId] = now
	pendingPurchase[structureId] = true
	Remotes.GetEvent(Constants.RemoteNames.RequestPurchaseUpgrade):FireServer({
		StructureId = structureId,
	} :: Types.PurchaseUpgradeRequest)
	-- Clear in-flight after debounce (server toast handles success/fail UX)
	task.delay(DEBOUNCE_SEC, function()
		pendingPurchase[structureId] = nil
	end)
end

local function pointInPad(hrpPos: Vector3, part: BasePart): boolean
	local localPos = part.CFrame:PointToObjectSpace(hrpPos)
	local half = part.Size * 0.5
	return math.abs(localPos.X) <= half.X + OVERLAP_MARGIN
		and math.abs(localPos.Z) <= half.Z + OVERLAP_MARGIN
		and localPos.Y >= -half.Y - 3
		and localPos.Y <= half.Y + 8
end

local function isOwnPlot(part: BasePart): boolean
	if myPlotId == nil then
		return true -- until plot assigned, allow (solo / loading)
	end
	local pid = part:GetAttribute("PlotId")
	if typeof(pid) ~= "number" then
		return true
	end
	return pid == myPlotId
end

local function onEnterPad(part: BasePart, structureId: string, fromStandingRetry: boolean?)
	if isSeatedInVehicle() then
		return
	end
	local key = padKey(part, structureId)
	if not isOwnPlot(part) then
		local now = os.clock()
		local last = lastPurchaseAt[structureId] or 0
		if now - last >= DEBOUNCE_SEC then
			lastPurchaseAt[structureId] = now
			NotificationController.Show("Not your base — walk your plot pads to buy", "Warn", 2.5)
		end
		lastOverlap[key] = true
		return
	end
	if lastOverlap[key] and not fromStandingRetry then
		return
	end
	lastOverlap[key] = true
	tryPurchase(structureId, { silentMax = fromStandingRetry == true })
end

local function onLeavePad(key: string)
	lastOverlap[key] = false
end

local function detachUpgradeSlot(part: BasePart)
	disconnectAll(slotConns, part)
	slotParts[part] = nil
end

local function attachUpgradeSlot(part: BasePart)
	if slotParts[part] then
		return
	end
	slotParts[part] = true
	part.CanTouch = true -- walk-over buy must receive Touched

	local existing = part:FindFirstChild(PROMPT_NAME)
	if existing then
		existing:Destroy()
	end

	refreshSlotBillboard(part)

	trackConn(slotConns, part, part.Touched:Connect(function(hit)
		local char = player.Character
		if not char then
			return
		end
		-- Multi-part: only accept character descendants (any body part)
		if not hit:IsDescendantOf(char) then
			return
		end
		local structureId = part:GetAttribute("StructureId")
		if typeof(structureId) == "string" then
			onEnterPad(part, structureId)
		end
	end))

	trackConn(slotConns, part, part.TouchEnded:Connect(function(hit)
		local char = player.Character
		if not char then
			return
		end
		if not hit:IsDescendantOf(char) then
			return
		end
		local structureId = part:GetAttribute("StructureId")
		if typeof(structureId) ~= "string" then
			return
		end
		local key = padKey(part, structureId)
		task.defer(function()
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") and pointInPad(hrp.Position, part) then
				-- Another character part still overlapping — keep overlap
				return
			end
			onLeavePad(key)
		end)
	end))

	trackConn(slotConns, part, part.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			detachUpgradeSlot(part)
		end
	end))
end

local function attachPromptOnce(part: BasePart, build: () -> ProximityPrompt, onTriggered: () -> ())
	if attachedPrompt[part] then
		return
	end
	attachedPrompt[part] = true
	local prompt = build()
	trackConn(promptConns, part, prompt.Triggered:Connect(function(who)
		if who ~= player then
			return
		end
		onTriggered()
	end))
	trackConn(promptConns, part, part.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			disconnectAll(promptConns, part)
			attachedPrompt[part] = nil
		end
	end))
end

local function attachBasePlot(part: BasePart)
	local plotId = part:GetAttribute("PlotId")
	local label = if typeof(plotId) == "number" then ("Base Plot " .. tostring(plotId)) else "Base"
	attachPromptOnce(part, function()
		return makePrompt(part, "Open Base", label, 0, 14)
	end, function()
		BaseController.Open()
	end)
end

local function attachCaptureZone(part: BasePart)
	local territoryId = part:GetAttribute("TerritoryId")
	local idStr = if typeof(territoryId) == "string" then territoryId else part.Name
	attachPromptOnce(part, function()
		return makePrompt(part, "Hold to capture", idStr, 0.4, 18)
	end, function()
		Remotes.GetEvent(Constants.RemoteNames.RequestCaptureTerritory):FireServer(idStr)
		NotificationController.Show("Stand in the zone to capture — progress fills while you hold ground.", "Info", 3.5)
	end)
end

local function attachVehicleSpawn(part: BasePart)
	attachPromptOnce(part, function()
		return makePrompt(part, "Open Garage", "Vehicle Pad", 0, 12)
	end, function()
		VehicleController.Open()
	end)
end

local function attachTutorialMarker(part: BasePart)
	local stepId = part:GetAttribute("TutorialStepId")
	local label = if typeof(stepId) == "string" then stepId else part.Name
	attachPromptOnce(part, function()
		return makePrompt(part, "Continue", "Tutorial: " .. tostring(label), 0, 10)
	end, function()
		NotificationController.Show("Follow the gold beam / tutorial panel — or press SKIP.", "Info", 3.5)
	end)
end

local function bindTag(tag: string, handler: (BasePart) -> ())
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		if inst:IsA("BasePart") then
			handler(inst)
		end
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
		if inst:IsA("BasePart") then
			handler(inst)
		end
	end)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
		if inst:IsA("BasePart") then
			if tag == Constants.Tags.UpgradeSlot then
				detachUpgradeSlot(inst)
			else
				disconnectAll(promptConns, inst)
				attachedPrompt[inst] = nil
			end
		end
	end)
end

local function clearOverlapState()
	table.clear(lastOverlap)
	table.clear(pendingPurchase)
end

local function startOverlapLoop()
	if overlapConn then
		overlapConn:Disconnect()
		overlapConn = nil
	end
	overlapConn = RunService.Heartbeat:Connect(function()
		if billboardDirty and (os.clock() - lastBillboardRefresh) >= BILLBOARD_THROTTLE then
			refreshAllBillboardsNow()
		end

		local char = player.Character
		if not char then
			return
		end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not (hrp and hrp:IsA("BasePart")) then
			return
		end
		if isSeatedInVehicle() then
			-- Driving: clear any stuck overlap so stepping out can buy fresh
			for key in pairs(lastOverlap) do
				if lastOverlap[key] then
					lastOverlap[key] = false
				end
			end
			return
		end

		local pos = hrp.Position
		for part in pairs(slotParts) do
			if part.Parent then
				local structureId = part:GetAttribute("StructureId")
				if typeof(structureId) == "string" then
					local key = padKey(part, structureId)
					local inside = pointInPad(pos, part)
					if inside then
						if not lastOverlap[key] then
							onEnterPad(part, structureId)
						else
							-- Standing retry: failed buy / cash refresh / sequential upgrades
							onEnterPad(part, structureId, true)
						end
					elseif lastOverlap[key] then
						onLeavePad(key)
					end
				end
			end
		end
	end)
end

local function bindAllTags()
	if tagsBound then
		-- Re-attach any slots that appeared since first bind (GetInstanceAdded covers
		-- new tags, but stale/untagged-then-tagged races still need a GetTagged sweep)
		for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.UpgradeSlot)) do
			if inst:IsA("BasePart") then
				attachUpgradeSlot(inst)
			end
		end
		return
	end
	tagsBound = true
	bindTag(Constants.Tags.BasePlot, attachBasePlot)
	bindTag(Constants.Tags.UpgradeSlot, attachUpgradeSlot)
	bindTag(Constants.Tags.CaptureZone, attachCaptureZone)
	bindTag(Constants.Tags.VehicleSpawn, attachVehicleSpawn)
	bindTag(Constants.Tags.TutorialMarker, attachTutorialMarker)
end

-- Attribute fallback: StructureId pads under WarEmpireSetup.Bases missing the tag
local function rescanUntaggedSlots()
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	if not setup then
		return
	end
	local bases = setup:FindFirstChild("Bases")
	if not bases then
		return
	end
	for _, desc in ipairs(bases:GetDescendants()) do
		if desc:IsA("BasePart") then
			local sid = desc:GetAttribute("StructureId")
			if typeof(sid) == "string" and not slotParts[desc] then
				-- Attach even if CollectionService tag lagged / missing on client replica
				attachUpgradeSlot(desc)
			end
		end
	end
end

function WorldPromptController.Init()
	Remotes.GetEvent(Constants.RemoteNames.BaseStateUpdate).OnClientEvent:Connect(function(base: Types.BaseStatePayload)
		upgrades = base.Upgrades or upgrades
		if typeof(base.PlotId) == "number" then
			if myPlotId ~= nil and myPlotId ~= base.PlotId then
				-- Plot reassignment — drop overlap so new pads can fire
				clearOverlapState()
			end
			myPlotId = base.PlotId
		end
		markBillboardsDirty()
	end)

	Remotes.GetEvent(Constants.RemoteNames.EconomyUpdate).OnClientEvent:Connect(function(payload: Types.EconomyUpdatePayload)
		cash = payload.Cash
		markBillboardsDirty()
	end)

	Remotes.GetEvent(Constants.RemoteNames.PlayerStateUpdate).OnClientEvent:Connect(function(state: Types.PlayerStatePayload)
		cash = state.Cash
		if state.Base then
			upgrades = state.Base.Upgrades
			if typeof(state.Base.PlotId) == "number" then
				if myPlotId ~= nil and myPlotId ~= state.Base.PlotId then
					clearOverlapState()
				end
				myPlotId = state.Base.PlotId
			end
		end
		markBillboardsDirty()
	end)

	player.CharacterAdded:Connect(function()
		clearOverlapState()
		task.defer(function()
			task.wait(0.3)
			markBillboardsDirty()
		end)
	end)

	player.CharacterRemoving:Connect(function()
		clearOverlapState()
	end)

	task.defer(function()
		-- Wait for map (MapSetup + MapDressing can take >0.5s on cold Studio Play)
		local setup = Workspace:WaitForChild("WarEmpireSetup", 60)
		if not setup then
			warn("[WorldPromptController] WarEmpireSetup missing after 60s — binding tags anyway")
		end
		bindAllTags()
		startOverlapLoop()
		refreshAllBillboardsNow()
		rescanUntaggedSlots()

		-- Periodic rescan first ~20s for race / late-tagged pads
		for _ = 1, 10 do
			task.wait(2)
			bindAllTags()
			rescanUntaggedSlots()
			refreshAllBillboardsNow()
		end
	end)
end

return WorldPromptController
