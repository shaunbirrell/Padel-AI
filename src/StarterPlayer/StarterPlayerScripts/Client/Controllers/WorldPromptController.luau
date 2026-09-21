--!strict
--[[
	World interactivity for StudioSetup-tagged parts.

	Upgrade pads (WE_UpgradeSlot):
	  PRIMARY UX (mobile): large bottom ScreenGui BUY button while standing on
	  own-plot pad → RequestPurchaseUpgrade (Activated / touch).
	  BACKUP: walk-over auto-purchase — Touched + Heartbeat overlap (debounced).
	  Server UpgradePadService remains authoritative walk-over path. Never grants on client.
	Edge cases: respawn clears overlap; seated-in-vehicle skips buy; multi-part
	touch uses pad keys; plot reassignment clears state; standing retry after
	debounce for failed-purchase UX. Prompt/Touched connections disconnect on
	part destroy. BillboardGuis throttled refresh on Base/Economy updates.
	Billboard subtitle: "Stand or tap BUY". Hide BUY for leave / wrong plot / MAX / prereq.

	ProximityPrompts only for non-buy actions (Open Base, Open Garage, capture ping, tutorial).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local BaseConfig = require(Shared.Configs.BaseConfig)
local EconomyConfig = require(Shared.Configs.EconomyConfig)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local BaseController = require(script.Parent.BaseController)
local VehicleController = require(script.Parent.VehicleController)
local NotificationController = require(script.Parent.NotificationController)
local UIUtil = require(Shared.Util.UIUtil)

local WorldPromptController = {}

local PROMPT_NAME = "WE_WorldPrompt"
local BILLBOARD_NAME = "WE_PriceBillboard"
local DEBOUNCE_SEC = 1.1 -- mobile standing-retry; still under server rate (6/8s)
local OVERLAP_MARGIN = 2.4 -- generous pad hitbox for mobile walk-over
local BILLBOARD_THROTTLE = 0.35 -- perf: avoid refreshing every economy tick frame
local PRICE_BILLBOARD_MAX_DIST = 42 -- near-only chips (was 56)
local ATM_HIDE_PRICE_STUDS = 12 -- P0: hide price boards near MoneyCollector -- near-only (was 650) — mobile screen clutter
local PRICE_CHIP_MAX_W = 120 -- v50: tighter mobile chips (was 160)
local PRICE_BILLBOARD_SIZE = UDim2.fromOffset(118, 40) -- phone-readable chip (was 160×52)
local PRICE_BILLBOARD_OWNED_SIZE = UDim2.fromOffset(96, 26) -- owned L1+: tiny roof chip
local BUY_GUI_NAME = "WE_PadBuyGui"
local BUY_BTN_MIN_H = 56

local player = Players.LocalPlayer
local upgrades: { [string]: number } = {}
local cash = 0
-- v57: every afford/BUY/NEED check reads max of module cash, WE_Cash, leaderstats.Cash
local function liveCash(): number
	local best = math.floor(tonumber(cash) or 0)
	local attr = tonumber(player:GetAttribute("WE_Cash"))
	if typeof(attr) == "number" then
		best = math.max(best, math.floor(attr))
	end
	local folder = player:FindFirstChild("leaderstats")
	if folder then
		local cashV = folder:FindFirstChild("Cash")
		if cashV and (cashV:IsA("IntValue") or cashV:IsA("NumberValue")) then
			best = math.max(best, math.floor((cashV :: any).Value))
		end
	end
	return best
end
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
local failToastAt: { [string]: number } = {} -- throttle Not enough / prereq (~0.85s)
local FAIL_TOAST_CD = 0.9
local _buyGui: ScreenGui? = nil
local buyBtn: TextButton? = nil
local activeBuyStructureId: string? = nil
local activeBuyPart: BasePart? = nil

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

local function incomePerLevel(structureId: string): number
	local rates = EconomyConfig.PassiveIncome and EconomyConfig.PassiveIncome.PerLevelRates
	if typeof(rates) ~= "table" then
		return 0
	end
	return tonumber(rates[structureId]) or 0
end

local function formatIncomeRate(structureId: string): string?
	local rate = incomePerLevel(structureId)
	if rate <= 0 then
		return nil
	end
	return string.format("+$%d/tick", rate)
end

local structureInfo: (structureId: string) -> (string, number, number?, boolean, string?)
local tryPurchase: (structureId: string, opts: { silentMax: boolean }?) -> ()
local isSeatedInVehicle: () -> boolean
local isOwnPlotPad: (part: BasePart) -> boolean


local padBuyFlashToken = 0
local lastPadLevels: { [string]: number } = {}
local function flashPadBuyBought(displayName: string)
	local btn = buyBtn
	if not btn or not btn.Visible then
		return
	end
	padBuyFlashToken += 1
	local my = padBuyFlashToken
	btn.Text = string.format("BOUGHT %s ✓", displayName)
	btn.BackgroundColor3 = Color3.fromRGB(30, 70, 40)
	btn.TextColor3 = Constants.Colors.Cash
	-- Standing Heartbeat refreshPadBuyButton rewrites label after flash window
	task.delay(1.0, function()
		if my ~= padBuyFlashToken then
			return
		end
		-- no-op; next pad refresh overwrites
	end)
end

local function hidePadBuyButton()
	activeBuyStructureId = nil
	activeBuyPart = nil
	if buyBtn then
		buyBtn.Visible = false
	end
end

local function ensurePadBuyGui(): TextButton
	if buyBtn and buyBtn.Parent then
		return buyBtn
	end
	local pg = player:WaitForChild("PlayerGui")
	local existing = pg:FindFirstChild(BUY_GUI_NAME)
	if existing and existing:IsA("ScreenGui") then
		existing:Destroy()
	end

	local screen = Instance.new("ScreenGui")
	screen.Name = BUY_GUI_NAME
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Above HUD dock (55); below modal panels (60+)
	screen.DisplayOrder = 65 -- above dock (55); below toast (70); avoids burying notifications
	screen.Parent = pg
	UIUtil.AttachMobileScale(screen, 800, 0.7, 1.05)
	_buyGui = screen

	local btn = Instance.new("TextButton")
	btn.Name = "BuyButton"
	btn.AnchorPoint = Vector2.new(0.5, 1)
	btn.Position = UDim2.new(0.5, 0, 1, -108)
	btn.Size = UDim2.fromOffset(300, 58)
	btn.BackgroundColor3 = Color3.fromRGB(40, 32, 10)
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 18
	btn.TextColor3 = Color3.fromRGB(255, 250, 235)
	btn.TextStrokeTransparency = 0.55
	btn.Text = "BUY"
	btn.Visible = false
	btn.Active = true
	btn.Selectable = true
	btn.ZIndex = 40
	btn.Parent = screen
	UIUtil.Corner(btn, 16)
	local stroke = UIUtil.GoldStroke(btn, 3)
	stroke.Transparency = 0.05
	UIUtil.EnsureMinTouch(btn, BUY_BTN_MIN_H)

	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.Size = UDim2.new(1, -12, 0, 18)
	gloss.Position = UDim2.fromOffset(6, 6)
	gloss.BackgroundColor3 = Color3.fromRGB(255, 230, 140)
	gloss.BackgroundTransparency = 0.78
	gloss.BorderSizePixel = 0
	gloss.Active = false
	gloss.ZIndex = 41
	gloss.Parent = btn
	UIUtil.Corner(gloss, 10)

	local function onBuyPressed()
		local sid = activeBuyStructureId
		if typeof(sid) ~= "string" then
			return
		end
		local display, _level, cost, isMax, prereqHint = structureInfo(sid)
		if isMax or prereqHint or cost == nil then
			hidePadBuyButton()
			return
		end
		-- Intentional tap: clear walk-over debounce so BUY always fires
		lastPurchaseAt[sid] = 0
		pendingPurchase[sid] = nil
		NotificationController.Show(string.format("Buying %s…", display), "Info", 1.5)
		print(string.format("[WorldPrompt] BUY button tap → RequestPurchaseUpgrade %s cost=%s", sid, tostring(cost)))
		tryPurchase(sid)
	end
	btn.Activated:Connect(onBuyPressed)
	btn.MouseButton1Click:Connect(onBuyPressed)

	buyBtn = btn
	return btn
end

local function refreshPadBuyButton(part: BasePart?, structureId: string?)
	if part == nil or structureId == nil then
		hidePadBuyButton()
		return
	end
	if isSeatedInVehicle() then
		hidePadBuyButton()
		return
	end
	if not isOwnPlotPad(part) then
		hidePadBuyButton()
		return
	end

	local display, _level, cost, isMax, prereqHint = structureInfo(structureId)
	if isMax or prereqHint or cost == nil then
		hidePadBuyButton()
		return
	end

	local btn = ensurePadBuyGui()
	activeBuyStructureId = structureId
	activeBuyPart = part
	local have = liveCash()
	local canAfford = have >= cost
	local incomeStr = formatIncomeRate(structureId)
	if not canAfford then
		local need = cost - have
		if incomeStr then
			btn.Text = string.format("NEED %s · %s · %s", formatCost(cost), display, incomeStr)
		else
			btn.Text = string.format("NEED %s more · %s", formatCost(need), display)
		end
	elseif incomeStr then
		btn.Text = string.format("BUY %s · %s · %s", display, formatCost(cost), incomeStr)
	else
		btn.Text = string.format("BUY %s · %s", display, formatCost(cost))
	end
	btn.TextColor3 = if canAfford then Color3.fromRGB(255, 252, 240) else Color3.fromRGB(255, 200, 200)
	btn.BackgroundColor3 = if canAfford then Color3.fromRGB(28, 24, 10) else Color3.fromRGB(42, 16, 16)
	btn.AutoButtonColor = canAfford
	btn.Visible = true
end

function structureInfo(structureId: string): (string, number, number?, boolean, string?)
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

local function clampChipSize(size: UDim2): UDim2
	-- v50: hard clamp width+height so legacy/Scale chips never dominate mobile
	local w = size.X.Offset
	local h = size.Y.Offset
	if w <= 0 and h <= 0 then
		return PRICE_BILLBOARD_SIZE
	end
	local cw = if w > 0 then math.min(w, PRICE_CHIP_MAX_W) else PRICE_CHIP_MAX_W
	local ch = if h > 0 then math.min(h, 44) else 40
	return UDim2.fromOffset(cw, ch)
end

local function setBillboardNearOnly(bb: BillboardGui, ownedChip: boolean?)
	-- never AlwaysOnTop giant tabs — owned = tiny chip; buyable = readable but ≤160 wide
	if ownedChip then
		bb.Size = clampChipSize(PRICE_BILLBOARD_OWNED_SIZE)
		bb.StudsOffset = Vector3.new(0, 6, 0)
		bb.MaxDistance = 28
		bb.AlwaysOnTop = false
	else
		bb.Size = clampChipSize(PRICE_BILLBOARD_SIZE)
		bb.StudsOffset = Vector3.new(0, 5.5, 0)
		bb.MaxDistance = PRICE_BILLBOARD_MAX_DIST
		bb.AlwaysOnTop = false
	end
	-- Defensive: legacy / stale oversized chips
	if bb.Size.X.Offset > PRICE_CHIP_MAX_W then
		bb.Size = clampChipSize(bb.Size)
	end
end

local function hidePriceBillboard(part: BasePart)
	local host = part:FindFirstChild("WE_BillboardHost")
	local existing = (host and host:FindFirstChild(BILLBOARD_NAME)) or part:FindFirstChild(BILLBOARD_NAME)
	if existing and existing:IsA("BillboardGui") then
		existing.Enabled = false
	end
	-- MapSetup non-price Label billboards on other parts are left alone
end

local function resolveBillboardAdornee(part: BasePart): BasePart
	local host = part:FindFirstChild("WE_BillboardHost")
	if host and host:IsA("BasePart") then
		return host
	end
	-- Prefer tall invisible host above kit roof so geometry never occludes BUY name
	local roofY = 0
	for _, ch in ipairs(part:GetChildren()) do
		if ch:IsA("BasePart") and ch:GetAttribute("WE_KitRole") == "Roof" then
			roofY = math.max(roofY, (ch.Position.Y - part.Position.Y) + ch.Size.Y * 0.5)
		end
	end
	host = Instance.new("Part")
	host.Name = "WE_BillboardHost"
	host.Size = Vector3.new(0.4, 0.4, 0.4)
	host.Transparency = 1
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.Massless = true
	host.CFrame = part.CFrame * CFrame.new(0, math.max(roofY + 1.2, 5), 0) -- v39: keep chip near roof
	host.Parent = part
	return host
end

local function ensurePadNameSurface(part: BasePart, displayName: string)
	local existing = part:FindFirstChild("WE_PadNameGui")
	if existing and existing:IsA("SurfaceGui") then
		local lab = existing:FindFirstChild("Name", true)
		if lab and lab:IsA("TextLabel") then
			lab.Text = string.upper(displayName)
			lab.TextColor3 = Color3.fromRGB(255, 245, 180)
			lab.TextStrokeTransparency = 0.2
			lab.BackgroundTransparency = 0.12
		end
		return
	end
	local sg = Instance.new("SurfaceGui")
	sg.Name = "WE_PadNameGui"
	sg.Face = Enum.NormalId.Top
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 60
	sg.LightInfluence = 0
	sg.Parent = part
	local lab = Instance.new("TextLabel")
	lab.Name = "Name"
	lab.Size = UDim2.fromScale(1, 1)
	lab.BackgroundTransparency = 0.12
	lab.BackgroundColor3 = Color3.fromRGB(6, 8, 10)
	lab.Text = string.upper(displayName)
	lab.TextColor3 = Color3.fromRGB(255, 245, 180)
	lab.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	lab.TextStrokeTransparency = 0.2
	lab.Font = Enum.Font.GothamBold
	lab.TextScaled = true
	lab.Parent = sg
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(230, 190, 60)
	stroke.Thickness = 2
	stroke.Transparency = 0.25
	stroke.Parent = lab
end

local function ensurePriceBillboard(part: BasePart): BillboardGui
	local adornee = resolveBillboardAdornee(part)
	local existing = adornee:FindFirstChild(BILLBOARD_NAME) or part:FindFirstChild(BILLBOARD_NAME)
	if existing and existing:IsA("BillboardGui") then
		existing.Adornee = adornee
		existing.Parent = adornee
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
	bb.Adornee = adornee
	bb.Parent = adornee

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(8, 10, 12)
	backdrop.BackgroundTransparency = 0.02
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
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
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
		titleLab.Text = string.upper(titleLine)
		titleLab.TextColor3 = Color3.fromRGB(255, 245, 180)
		titleLab.TextStrokeTransparency = 0.25
		titleLab.Font = Enum.Font.GothamBold
		costLab.Text = detailLine
		costLab.TextColor3 = textColor
		costLab.TextStrokeTransparency = 0.35
	elseif textLab and textLab:IsA("TextLabel") then
		if detailLine ~= "" then
			textLab.Text = string.upper(titleLine) .. "\n" .. detailLine
		else
			textLab.Text = string.upper(titleLine)
		end
		textLab.TextColor3 = textColor
		textLab.TextStrokeTransparency = 0.25
		textLab.Font = Enum.Font.GothamBold
	end
end

function isOwnPlotPad(part: BasePart): boolean
	-- Hide / skip refresh for other players' plots once we know our PlotId.
	-- Studio / ambiguous PlotId: ALWAYS show BUY (never suppress CTA).
	if myPlotId == nil then
		return true -- loading / solo until assigned
	end
	local pid = part:GetAttribute("PlotId")
	if typeof(pid) ~= "number" then
		-- Also accept BasePlotId attribute some kits use
		pid = part:GetAttribute("BasePlotId")
	end
	if typeof(pid) ~= "number" then
		return true -- ambiguous → show BUY
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

	local display, level, cost, isMax, prereqHint = structureInfo(structureId)
	local owned = level >= 1
	-- Owned: pad SurfaceGui name is enough for L0 buy; skip giant top-of-pad wash when built
	if owned then
		local padName = part:FindFirstChild("WE_PadNameGui")
		if padName then
			padName:Destroy()
		end
	else
		ensurePadNameSurface(part, display)
	end

	local bb = ensurePriceBillboard(part)
	setBillboardNearOnly(bb, owned)

	local incomeStr = formatIncomeRate(structureId)
	local incomeLine = if incomeStr then (" · " .. incomeStr) else ""

	if isMax then
		-- v39: tiny roof chip only — never dominate screen over the building
		local ownedIncome = if incomePerLevel(structureId) > 0
			then string.format(" +$%d/t", incomePerLevel(structureId) * level)
			else ""
		applyBillboardCopy(
			bb,
			display,
			string.format("L%d MAX%s", level, ownedIncome),
			Constants.Colors.Muted,
			Color3.fromRGB(70, 80, 70)
		)
	elseif owned and cost then
		-- L1+ upgradeable: small chip, not AlwaysOnTop billboard wall
		applyBillboardCopy(
			bb,
			display,
			string.format("L%d→%d %s%s", level, level + 1, formatCost(cost), incomeLine),
			if liveCash() >= cost then Color3.fromRGB(255, 230, 140) else Color3.fromRGB(255, 190, 190),
			if liveCash() >= cost then Color3.fromRGB(230, 190, 60) else Color3.fromRGB(180, 70, 70)
		)
	elseif prereqHint then
		local costStr = if cost then formatCost(cost) else ""
		applyBillboardCopy(
			bb,
			display,
			string.format("Lv %d → %d %s%s\n%s", level, level + 1, costStr, incomeLine, prereqHint),
			Color3.fromRGB(200, 170, 120),
			Color3.fromRGB(160, 130, 70)
		)
	elseif cost then
		local canAfford = liveCash() >= cost
		applyBillboardCopy(
			bb,
			display,
			string.format("Lv %d → %d  %s%s\nStand or tap BUY", level, level + 1, formatCost(cost), incomeLine),
			if canAfford then Color3.fromRGB(255, 230, 140) else Color3.fromRGB(255, 190, 190),
			if canAfford then Color3.fromRGB(230, 190, 60) else Color3.fromRGB(180, 70, 70)
		)
	else
		applyBillboardCopy(bb, display, incomeStr or "", Constants.Colors.Text, Constants.Colors.Gold)
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
	-- Keep BUY label/cost in sync while camping the pad
	if activeBuyPart and activeBuyStructureId and activeBuyPart.Parent then
		refreshPadBuyButton(activeBuyPart, activeBuyStructureId)
	end
end

local function markBillboardsDirty()
	billboardDirty = true
end

function isSeatedInVehicle(): boolean
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

function tryPurchase(structureId: string, opts: { silentMax: boolean }?)
	local now = os.clock()
	local last = lastPurchaseAt[structureId] or 0
	if now - last < DEBOUNCE_SEC then
		return
	end
	if pendingPurchase[structureId] then
		print("[WorldPrompt] BUY skip in-flight", structureId)
		return
	end

	local display, _level, cost, isMax, prereqHint = structureInfo(structureId)
	if isMax then
		lastPurchaseAt[structureId] = now
		local silent = opts and opts.silentMax
		local lastMax = maxToastAt[structureId] or 0
		if not silent and (now - lastMax) >= 8 then
			maxToastAt[structureId] = now
			NotificationController.Show("Already MAX", "Info", 2)
			print("[WorldPrompt] BUY FAIL MAX", structureId)
		end
		return
	end
	if prereqHint then
		lastPurchaseAt[structureId] = now
		if not (opts and opts.silentMax) then
			local fk = "prereq|" .. structureId
			local lastFail = failToastAt[fk] or 0
			if (now - lastFail) >= FAIL_TOAST_CD then
				failToastAt[fk] = now
				NotificationController.Show(prereqHint, "Warn", 3)
			end
			print("[WorldPrompt] BUY FAIL prereq", structureId, prereqHint)
		end
		return
	end
	local have = liveCash()
	if cost and have < cost then
		-- v57: no client soft-fail toast (server InsufficientCash is authoritative); still FireServer
		print(string.format("[WorldPrompt] BUY soft-hint cash %s have=%d need=%s (FireServer anyway)", structureId, have, tostring(cost)))
	end

	lastPurchaseAt[structureId] = now
	pendingPurchase[structureId] = true
	print(string.format("[WorldPrompt] FireServer RequestPurchaseUpgrade %s cost=%s cash=%d", structureId, tostring(cost), have))
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
		pid = part:GetAttribute("BasePlotId")
	end
	if typeof(pid) ~= "number" then
		return true -- ambiguous → allow buy
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
		local prompt = makePrompt(part, "Open Garage", "Vehicle Pad", 0, 12)
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		-- Secondary Drive hint via ObjectText when vehicles nearby (seat has its own Drive prompt)
		prompt.ObjectText = "Garage · seat has Drive"
		return prompt
	end, function()
		VehicleController.Open()
	end)
end

local function attachTutorialMarker(_part: BasePart)
	-- No proximity prompts / toasts on tutorial markers — TutorialController owns UX
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
	hidePadBuyButton()
end

local function startOverlapLoop()
	if overlapConn then
		overlapConn:Disconnect()
		overlapConn = nil
	end
	overlapConn = RunService.Heartbeat:Connect(function()

	
	-- P0 STRUCTURE_SCALE: hide WORKER/TRAINING tags near ATM or upgrade pads (stop name stack)
	do
		local cam = workspace.CurrentCamera
		local camPos = if cam then cam.CFrame.Position else nil
		local nearPad = false
		if camPos then
			for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.UpgradeSlot)) do
				if inst:IsA("BasePart") and (inst.Position - camPos).Magnitude <= 20 then
					nearPad = true
					break
				end
			end
		end
		for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.MoneyCollector)) do
			if inst:IsA("BasePart") and camPos and (inst.Position - camPos).Magnitude <= 14 then
				nearPad = true
				break
			end
		end
		for _, bb in ipairs(workspace:GetDescendants()) do
			if bb:IsA("BillboardGui") and (bb.Name == "WE_WorkerTag" or bb.Name == "WE_TrainingEarnBillboard") then
				if nearPad then
					bb.Enabled = false
				elseif bb.MaxDistance > 0 then
					bb.Enabled = true
				end
			end
		end
		-- Season banner: tuck/hide when near pads (never cover structure names)
		local pg = player:FindFirstChildOfClass("PlayerGui")
		local hud = pg and pg:FindFirstChild("WE_HUD")
		local season = hud and hud:FindFirstChild("SeasonLabel", true)
		if season and season:IsA("GuiObject") then
			season.Visible = not nearPad and season.Text ~= ""
			if season:IsA("GuiObject") then
				season.ZIndex = 2 -- keep below dock/action chrome
			end
		end
		-- v31: Supply Drop labels — hide when near upgrade pads / ATM so structure names win
		local supplyTag = (Constants.Tags and Constants.Tags.SupplyDrop) or "WE_SupplyDrop"
		local okSup, supplies = pcall(function()
			return CollectionService:GetTagged(supplyTag)
		end)
		if okSup and supplies then
			for _, crate in ipairs(supplies) do
				if crate:IsA("BasePart") then
					for _, d in ipairs(crate:GetDescendants()) do
						if d:IsA("BillboardGui") then
							d.AlwaysOnTop = false
							if nearPad then
								d.Enabled = false
							elseif d.MaxDistance > 0 then
								d.Enabled = true
							end
						end
					end
				end
			end
		end
	end

-- P0: hide structure price boards when near MoneyCollector ATM
	do
		local nearAtm = false
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.MoneyCollector)) do
				if inst:IsA("BasePart") then
					local d = (inst.Position - hrp.Position).Magnitude
					if d <= ATM_HIDE_PRICE_STUDS then
						nearAtm = true
						break
					end
				end
			end
		end
		for _, part in ipairs(CollectionService:GetTagged(Constants.Tags.UpgradeSlot)) do
			if part:IsA("BasePart") then
				local host = part:FindFirstChild("WE_BillboardHost")
				local bb = (host and host:FindFirstChild(BILLBOARD_NAME)) or part:FindFirstChild(BILLBOARD_NAME)
				if bb and bb:IsA("BillboardGui") then
					if nearAtm then
						bb.Enabled = false
					elseif bb.Enabled == false and part:GetAttribute("WE_PriceForceHidden") ~= true then
						-- re-enable only if still in range logic elsewhere; soft restore
						bb.Enabled = true
					end
				end
			end
		end
	end
		if billboardDirty and (os.clock() - lastBillboardRefresh) >= BILLBOARD_THROTTLE then
			refreshAllBillboardsNow()
		end

		local char = player.Character
		if not char then
			hidePadBuyButton()
			return
		end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not (hrp and hrp:IsA("BasePart")) then
			hidePadBuyButton()
			return
		end
		if isSeatedInVehicle() then
			-- Driving: clear any stuck overlap so stepping out can buy fresh
			for key in pairs(lastOverlap) do
				if lastOverlap[key] then
					lastOverlap[key] = false
				end
			end
			hidePadBuyButton()
			return
		end

		local pos = hrp.Position
		local bestPart: BasePart? = nil
		local bestSid: string? = nil
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
						-- Prefer own-plot pad for BUY button (first match is fine; typically one pad)
						if isOwnPlot(part) and bestPart == nil then
							bestPart = part
							bestSid = structureId
						end
					elseif lastOverlap[key] then
						onLeavePad(key)
					end
				end
			end
		end
		refreshPadBuyButton(bestPart, bestSid)
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
		local prev = upgrades
		upgrades = base.Upgrades or upgrades
		if typeof(base.PlotId) == "number" then
			if myPlotId ~= nil and myPlotId ~= base.PlotId then
				-- Plot reassignment — drop overlap so new pads can fire
				clearOverlapState()
			end
			myPlotId = base.PlotId
		end
		-- BUY edge: flash BOUGHT when standing on a pad that just leveled
		if activeBuyStructureId and typeof(upgrades) == "table" then
			local sid = activeBuyStructureId
			local before = if typeof(prev) == "table" then (prev[sid] or 0) else 0
			local after = upgrades[sid] or 0
			if after > before then
				local def = BaseConfig.Structures[sid]
				local name = if def then def.DisplayName else sid
				flashPadBuyBought(name)
				print(string.format("[WorldPrompt] BUY OK flash %s %d→%d", sid, before, after))
			end
		end
		markBillboardsDirty()
	end)

	local function applyCash(n: any)
		local v = tonumber(n)
		if typeof(v) == "number" then
			cash = math.floor(v)
			markBillboardsDirty()
			-- v57: NEED→BUY while standing when cash syncs
			if activeBuyPart and activeBuyStructureId then
				refreshPadBuyButton(activeBuyPart, activeBuyStructureId)
			end
		end
	end

	Remotes.GetEvent(Constants.RemoteNames.EconomyUpdate).OnClientEvent:Connect(function(payload: Types.EconomyUpdatePayload)
		applyCash(payload.Cash)
	end)

	Remotes.GetEvent(Constants.RemoteNames.PlayerStateUpdate).OnClientEvent:Connect(function(state: Types.PlayerStatePayload)
		applyCash(state.Cash)
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

	-- Attribute fallback when FireClient was missed (join race)
	do
		local attrCash = player:GetAttribute("WE_Cash")
		if typeof(attrCash) == "number" then
			applyCash(attrCash)
		end
		player:GetAttributeChangedSignal("WE_Cash"):Connect(function()
			applyCash(player:GetAttribute("WE_Cash"))
		end)
	end

	local function tryLeaderstatsCash(): boolean
		local folder = player:FindFirstChild("leaderstats")
		if not folder then
			return false
		end
		local cashV = folder:FindFirstChild("Cash")
		if cashV and (cashV:IsA("IntValue") or cashV:IsA("NumberValue")) then
			applyCash((cashV :: any).Value)
			return true
		end
		return false
	end
	tryLeaderstatsCash()
	player.ChildAdded:Connect(function(ch)
		if ch.Name == "leaderstats" then
			task.defer(tryLeaderstatsCash)
			ch.ChildAdded:Connect(function()
				task.defer(tryLeaderstatsCash)
			end)
		end
	end)

	-- v56 bootstrap: poll WE_Cash / leaderstats / GetPlayerState so BUY not NEED when server has cash
	task.spawn(function()
		local synced = false
		for i = 0, 15 do
			if typeof(player:GetAttribute("WE_Cash")) == "number" then
				applyCash(player:GetAttribute("WE_Cash"))
				synced = true
			end
			if tryLeaderstatsCash() then
				synced = true
			end
			local ok, state = pcall(function()
				return Remotes.GetFunction(Constants.RemoteNames.GetPlayerState):InvokeServer()
			end)
			if ok and typeof(state) == "table" then
				applyCash((state :: any).Cash)
				local base = (state :: any).Base
				if typeof(base) == "table" then
					if typeof(base.Upgrades) == "table" then
						upgrades = base.Upgrades
					end
					if typeof(base.PlotId) == "number" then
						myPlotId = base.PlotId
					end
				end
				markBillboardsDirty()
				print(string.format("[WorldPrompt] cash bootstrap have=%d", cash))
				return
			end
			if synced and i >= 3 then
				markBillboardsDirty()
				print(string.format("[WorldPrompt] cash bootstrap via attr/leaderstats have=%d", cash))
				return
			end
			task.wait(1)
		end
		if not synced then
			warn("[WorldPrompt] cash bootstrap failed — relying on EconomyUpdate/Attribute")
		end
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
		local n = 0
		for _ in pairs(slotParts) do
			n += 1
		end
		print(string.format("[WorldPrompt] bound upgrade slots=%d tagged=%d", n, #CollectionService:GetTagged(Constants.Tags.UpgradeSlot)))

		-- Periodic rescan first ~20s for race / late-tagged pads
		for _ = 1, 10 do
			task.wait(2)
			bindAllTags()
			rescanUntaggedSlots()
			refreshAllBillboardsNow()
		end
		local n2 = 0
		for _ in pairs(slotParts) do
			n2 += 1
		end
		print(string.format("[WorldPrompt] after rescan slots=%d", n2))
	end)
end

return WorldPromptController
