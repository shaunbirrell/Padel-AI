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

	ProximityPrompts only for non-buy actions (the vehicle pad "Garage" prompt; tutorial markers have none).

	v70 "clean screen" (spec §3.5 action lane, §4.1 one failed buy = one line, §5 console labels):
	  * BUY lives in the ACTION LANE (bottom-centre, above the hotbar; HudLayout.ActionLaneBottomV()): green when
	    affordable / dark red "NEED $N more"; "BUILD HELIPAD  $5,000" / "UPGRADE HELIPAD  $12,000"; desktop shows an
	    "E" key cap; hidden while a panel is open (Modal), seated or dead. The buy path is unchanged: btn.Activated →
	    tryPurchase → Remotes.FireServer(RequestPurchaseUpgrade) → WE_BuyAck / PurchaseResult.
	  * Console price label: plain 2-line outlined text, owner-only, 2.2 studs above the console, no card, no income,
	    no "Stand or tap BUY"; MAX → no label (MAX is on the console screen). No pad-name wash on consoles.
	  * Prompts are pills (PromptController); the "Open Base" and "Hold to capture" client prompts are gone.
	  * No per-frame workspace scan, no WE_HUD season hack; a price label hidden for a reason stays hidden.

	v72 tycoon guide (only while TycoonGuideConfig.Enabled; off = the v70 look above, unchanged):
	  * BUY is two lines of 20 v (TycoonGuideConfig.BuyLane.TouchSize 300x72 v on touch; line 1 Display, line 2 Body)
	    from TycoonMath.MoneyState(cost, wallet, ATM, WE_IncomePerSec):
	      Buy      green  "BUILD AMMO WORKS  $600" / "UPGRADE AMMO LV 2  $2,000" / "BUILD  $1,500"  over
	                      "+$3.3/s income" or "+$3.1/s  6 new buildings"
	      Collect  amber  "COLLECT $1,240 AT ATM" / "+$3.3/s when built": fires NOTHING, draws the line to your own
	                      ATM (ConsoleWaypoint.ShowAtm) and toasts "Follow the line to your ATM"
	      Earn     red    "NEED $1,240 MORE" / "+$3.3/s  ready in 0:42" (the countdown ticks at EtaRefreshHz)
	    A line that does not fit at 20 v (TextService) falls back to the short name / the unlock is dropped; text is
	    never scaled below 20 v. On touch the lane moves right of the thumb zone (TycoonMath.ActionLaneShiftV). While
	    it shows, HudLayout flag "AtConsole" is on (the guide chip hides).
	  * Console tag: stud-scaled (ConsoleTag StudsW x StudsH, DistanceLowerLimit), fixed 14-20 px lines stacked like
	    WorldLabel, owner-only: "AMMO WORKS" (gold "NEXT  AMMO WORKS" on the WE_NextBuy pick, MaxDistance 40) over
	    "$600  +$3.3/s" (green when wallet + ATM covers it, red otherwise) / "Needs Weapons Facility 1" / "MAX LEVEL"
	    (kiosks without a screen). Console screens of the 15 buildings read "WAREHOUSE\n$3.2K\n+$5.2/s".
	  * Every number is TycoonMath over configs x the server-stamped WE_IncomeMult; no remote is added.

	F4 / F5 (owner's 11 features, lane G):
	  * One pointer: the gold NEXT tag marks what the floor chevrons point at (TycoonMath.GuideTarget): while the
	    tutorial runs (TycoonGuideConfig.Chevrons.FollowTutorial) the active step's own pad (Command Center, Barracks)
	    and no console otherwise (the Collect cash step points at the ATM; claim / recruit / outpost / 4x4 at none);
	    after it, the server's pick WE_NextBuy (the cheapest unpaid pad). The step comes from TutorialStateUpdate /
	    PlayerStateUpdate; while a step is up on the HUD (HudLayout "Tutorial") but not known here, no console is NEXT.
	  * The price / NEXT tags are base labels (WorldLabel.TagBaseLabel: the client LabelGovernor counts them toward
	    "at most 3 labels on screen at a base"), and every show / hide goes through WorldLabel.SetShown, so a governor
	    hold is never undone by the 4 Hz pass below.

	streaming2 lane C4 (StreamingEnabled):
	  * F14: a console's screen is its own part (MapSetup.dressConsole), so it can stream in after its plinth, or
	    leave and come back with the server's text (the local price text "can be lost" on stream-in). While
	    streaming is on, each console's ChildAdded("ConsoleScreen") marks the billboards dirty, so the next throttled
	    pass writes the owner's line again. Streaming off: not connected.
	  * F19: the global Workspace.DescendantAdded hook that hid the removed "TRAINING" labels is gone, with its start
	    scan. Nothing in the game makes either label any more, so it matched nothing, streaming on or off; under
	    streaming it ran for every instance that streamed in. While streaming is on, the untagged-StructureId
	    fallback walk is skipped too: every StructureId part is tagged (MapSetup plinths, BusinessService consoles),
	    and the tag's added signal fires on each stream-in. Streaming off: the walk runs as before.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local BaseConfig = require(Shared.Configs.BaseConfig)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local HudConfig = require(Shared.Configs.HudConfig)
local ConsoleBuyConfig = require(Shared.Configs.ConsoleBuyConfig)
local TycoonGuideConfig = require(Shared.Configs.TycoonGuideConfig)
local TutorialConfig = require(Shared.Configs.TutorialConfig)
local TycoonMath = require(Shared.Util.TycoonMath)

local VehicleController = require(script.Parent.VehicleController)
local NotificationController = require(script.Parent.NotificationController)
-- v70 prompt pills: required defensively (like UIController does) — a broken PromptController must never take the
-- BUY path down with it; the stub keeps every call a no-op.
local PromptController: any = {
	SetMyPlotId = function(_: number?) end,
	SetBuyButtonActive = function(_: boolean) end,
	SetSuppressed = function(_: ProximityPrompt, _: boolean) end,
}
do
	local mod = script.Parent:FindFirstChild("PromptController")
	if mod and mod:IsA("ModuleScript") then
		local req: any = require
		local ok, res = pcall(req, mod)
		if ok and typeof(res) == "table" then
			PromptController = res
		else
			warn("[WorldPrompt] PromptController failed to load:", res)
		end
	end
end
local UIUtil = require(Shared.Util.UIUtil)
local WorldLabel = require(Shared.Util.WorldLabel)
local HudLayout = require(script.Parent.Parent.Modules.HudLayout)
-- any: ConsoleWaypoint.ShowAtm arrives with the v72 guide lane; every call is guarded (`if ConsoleWaypoint.ShowAtm`)
local ConsoleWaypoint: any = require(script.Parent.Parent.Modules.ConsoleWaypoint)

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
-- v70 action-lane BUY (HudConfig.ActionLane): desktop keeps the pinned 300x58; touch is 64 v (44.8 px on phones)
local BUY_BTN_SIZE_DESKTOP = UDim2.fromOffset(300, 58)
local BUY_BTN_SIZE_TOUCH = HudConfig.ActionLane.BuyButtonSizeTouch
local CONSOLE_LABEL = HudConfig.WorldLabels.Console
local BUY_FAIL_DEDUPE_SEC = 1 -- WE_BuyAck + PurchaseResult for the same structure = one line

-- v72 tycoon guide surfaces (TycoonGuideConfig.Enabled only)
local GTEXT = TycoonGuideConfig.Text
local BUY_LANE = TycoonGuideConfig.BuyLane
local TAG = TycoonGuideConfig.ConsoleTag
local BUY_LINE_V = 20 -- v per BUY line (14 real px at the 0.70 phone scale); never scaled below this
local BUY_LINE_ROW_V = BUY_LINE_V + 4 -- row height (two rows centred in the button)
local BUY_TEXT_PAD_V = 12 -- v between the button edge (or the key cap) and the text
local BUY_KEYCAP_V = 28
local BUY_COPY_MIN_SEC = 0.1 -- copy rebuilds at most 10 Hz while its inputs change (CLAUDE.md UI refresh cap)
local COLLECT_TOAST_CD = 3 -- "Follow the line to your ATM" at most every 3 s
-- console tag lines: real px (BillboardGui), fixed size (the box is stud-scaled; WorldLabel's model, 14-20 px)
local TAG_TITLE_PX = math.clamp(CONSOLE_LABEL.NameSize, 14, 20)
local TAG_LINE_PX = math.clamp(CONSOLE_LABEL.PriceSize, 14, 20)
local TAG_LINE_PAD = 2

local function guideOn(): boolean
	return TycoonGuideConfig.Enabled == true
end

-- dirty labels refresh at most this often (v72 guide: the console tags at TextRefreshHz)
local billboardThrottle = if guideOn()
	then math.max(BILLBOARD_THROTTLE, 1 / math.max(0.1, TycoonGuideConfig.TextRefreshHz))
	else BILLBOARD_THROTTLE

local player = Players.LocalPlayer

-- a numeric Player attribute (NaN / missing / wrong type -> default)
local function numAttr(name: string, default: number): number
	local v = player:GetAttribute(name)
	if typeof(v) == "number" and v == v then
		return v
	end
	return default
end

-- ATM balance (EconomyService WE_PendingCash)
local function pendingCash(): number
	return math.max(0, numAttr("WE_PendingCash", 0))
end

-- what the ATM receives per second right now (server WE_IncomePerSec; 0 until the first steady grant)
local function incomePerSec(): number
	return math.max(0, numAttr("WE_IncomePerSec", 0))
end

-- what one base $ of income pays (server WE_IncomeMult; 1 until the first passive tick)
local function incomeMult(): number
	local m = numAttr("WE_IncomeMult", 1)
	return if m > 0 then m else 1
end

-- "+$3.3/s": the income buying level + 1 of structureId adds (floored; oil counted unscaled)
local function stepGainText(structureId: string, level: number): string
	return TycoonMath.PerSecText(TycoonMath.StepGainPerTick(structureId, level, incomeMult()))
end

-- F5 one pointer: the tutorial step the server last pushed (tutKnown) / nil once the tutorial is complete
local tutKnown = false
local tutStep: TycoonMath.GuideStep? = nil
local tutPayloadStep: TycoonMath.GuideStep = { PadStructureId = nil, Pointer = nil } -- a step Id this config lacks

local function applyTutorialStep(complete: boolean, id: any, pad: any, pointer: any)
	tutKnown = true
	if complete then
		tutStep = nil
		return
	end
	local i = if typeof(id) == "string" then TutorialConfig.IndexOf(id) else nil
	local def = if i ~= nil then TutorialConfig.Steps[i] else nil
	if def ~= nil then
		tutStep = def
	else
		tutPayloadStep.PadStructureId = if typeof(pad) == "string" then pad else nil
		tutPayloadStep.Pointer = if typeof(pointer) == "string" then pointer else nil
		tutStep = tutPayloadStep
	end
end

-- the one pointer (TycoonMath.GuideTarget: the tutorial step's pad, else the server's pick WE_NextBuy "Id:Level")
-- is buying level + 1 of structureId
local function isNextPick(structureId: string, level: number): boolean
	local step: TycoonMath.GuideStep? = nil
	if tutKnown then
		step = tutStep
	elseif HudLayout.GetFlag("Tutorial") then
		return false -- a tutorial step is up but has not reached this controller yet: no NEXT tag anywhere
	end
	local id, lv = TycoonMath.GuideTarget(step, player:GetAttribute("WE_NextBuy"))
	return id == structureId and lv == level + 1
end

-- TextService width (v, at BUY_LINE_V) of one BUY line; memoised (a few dozen distinct strings per session)
local textWidthCache: { [string]: number } = {}
local textWidthCount = 0
local function lineWidthV(text: string, font: Enum.Font): number
	local key = font.Name .. "|" .. text
	local hit = textWidthCache[key]
	if hit then
		return hit
	end
	local ok, v = pcall(function(): Vector2
		return TextService:GetTextSize(text, BUY_LINE_V, font, Vector2.new(4000, 200))
	end)
	local w = if ok and typeof(v) == "Vector2" and v.X > 0 then v.X else (utf8.len(text) or #text) * BUY_LINE_V * 0.62
	if textWidthCount >= 128 then
		table.clear(textWidthCache)
		textWidthCount = 0
	end
	textWidthCache[key] = w
	textWidthCount += 1
	return w
end
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
local slotConns: { [Instance]: { RBXScriptConnection } } = {}
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

-- v68: consoles (BaseLayoutConfig) — the BUY button shows when you walk up; buying needs a tap or the prompt
local function isConsolePart(part: BasePart): boolean
	return part:GetAttribute("WE_Console") == true
end

-- streaming2: the place's StreamingEnabled (default.project.json; scripts cannot set it). The lane C4 changes act
-- only while it is true.
local function streamingOn(): boolean
	return Workspace.StreamingEnabled == true
end

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

-- 12000 → "12,000"
local function withCommas(n: number): string
	local s = tostring(math.floor(math.abs(n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return if n < 0 then "-" .. out else out
end

-- BUY button: the full price ("$12,000")
local function fullCost(cost: number): string
	return "$" .. withCommas(cost)
end

-- console label: "$5,000" under 10K, then "$12K" / "$12.5K" / "$1.2M"
local function shortCost(cost: number): string
	if cost >= 1_000_000 then
		return (string.format("$%.1fM", cost / 1_000_000):gsub("%.0M", "M"))
	elseif cost >= 10_000 then
		local k = cost / 1000
		if k >= 100 or math.abs(k - math.floor(k)) < 0.05 then
			return string.format("$%dK", math.floor(k))
		end
		return string.format("$%.1fK", k)
	end
	return fullCost(cost)
end

local function escapeRich(t: string): string
	return (t:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local structureInfo: (structureId: string) -> (string, number, number?, boolean, string?)
local tryPurchase: (structureId: string, opts: { silentMax: boolean?, showBuying: boolean? }?) -> ()
local isSeatedInVehicle: () -> boolean
local isOwnPlotPad: (part: BasePart) -> boolean


local padBuyFlashToken = 0
-- the BUY caption keeps "BUYING…" / "BOUGHT …!" until this os.clock() (the Heartbeat refresh would overwrite it)
local captionHoldUntil = 0
local buyCaption: TextLabel? = nil
local buyStroke: UIStroke? = nil
local buyGradient: UIGradient? = nil

-- affordable: green gradient (63,220,85) → (35,165,58), 3 v dark-green stroke; short of cash: dark red
local BUY_OK_TOP = Color3.fromRGB(63, 220, 85)
local BUY_OK_BOTTOM = Color3.fromRGB(35, 165, 58)
local BUY_OK_STROKE = Color3.fromRGB(12, 70, 22)
local BUY_SHORT_TOP = Color3.fromRGB(96, 44, 44)
local BUY_SHORT_BOTTOM = Color3.fromRGB(58, 26, 26)
local BUY_SHORT_STROKE = Color3.fromRGB(30, 10, 10)
local BUY_SHORT_PRICE = "#ff8080"
-- v72 Collect (money is in the ATM): amber
local BUY_COLLECT_TOP = Color3.fromRGB(255, 180, 40)
local BUY_COLLECT_BOTTOM = Color3.fromRGB(205, 118, 12)
local BUY_COLLECT_STROKE = Color3.fromRGB(88, 46, 4)

type BuyLook = "Buy" | "Collect" | "Earn" -- green / amber / dark red (TycoonMath.MoneyState)

local function asLook(state: string): BuyLook
	if state == "Collect" then
		return "Collect"
	elseif state == "Earn" then
		return "Earn"
	end
	return "Buy"
end

-- v72 two-line BUY (guide on): line 2, the key cap, and the copy cache (rebuilt only when its inputs change)
local buyLine2: TextLabel? = nil
local buyKeyCap: Frame? = nil
local buyLaneFrame: Frame? = nil
local buyLaneConn: RBXScriptConnection? = nil
local buyCopyDirty = true
local copySid: string? = nil
local copyLevel = -1
local copyCost = -1
local copyAt = -math.huge
local copyLook: BuyLook = "Buy"
local copyGain = ""
local copyEtaEnd: number? = nil
local copyEtaAt = -math.huge
local collectToastAt = -math.huge

-- UIGradient colours multiply BackgroundColor3: bg = top colour, gradient white → bottom/top per channel
local function gradientTo(top: Color3, bottom: Color3): ColorSequence
	local function ratio(b: number, t: number): number
		return if t > 0 then math.clamp(b / t, 0, 1) else 1
	end
	return ColorSequence.new(Color3.new(1, 1, 1), Color3.new(ratio(bottom.R, top.R), ratio(bottom.G, top.G), ratio(bottom.B, top.B)))
end

local buyLook: BuyLook? = nil
local function setBuyLook(look: BuyLook)
	local btn = buyBtn
	if not btn or buyLook == look then
		return
	end
	buyLook = look
	local top, bottom, edge = BUY_OK_TOP, BUY_OK_BOTTOM, BUY_OK_STROKE
	if look == "Earn" then
		top, bottom, edge = BUY_SHORT_TOP, BUY_SHORT_BOTTOM, BUY_SHORT_STROKE
	elseif look == "Collect" then
		top, bottom, edge = BUY_COLLECT_TOP, BUY_COLLECT_BOTTOM, BUY_COLLECT_STROKE
	end
	btn.BackgroundColor3 = top
	local g = buyGradient
	if g then
		g.Color = gradientTo(top, bottom)
	end
	local st = buyStroke
	if st then
		st.Color = edge
	end
	btn.AutoButtonColor = look ~= "Earn"
end

local function setBuyCaption(rich: string)
	local cap = buyCaption
	if cap and cap.Text ~= rich then
		cap.Text = rich
	end
end

-- v72 two-line layout: rows centred as a pair (one row centred alone), right of the key cap when it shows
local function layoutBuyLines(twoLines: boolean, capVisible: boolean)
	local cap, line2 = buyCaption, buyLine2
	if not (cap and line2) then
		return
	end
	local padL = BUY_TEXT_PAD_V + (if capVisible then BUY_KEYCAP_V + 8 else 0)
	local size = UDim2.new(1, -(padL + BUY_TEXT_PAD_V), 0, BUY_LINE_ROW_V)
	local p1 = UDim2.new(0, padL, 0.5, if twoLines then -BUY_LINE_ROW_V / 2 else 0)
	if cap.Position ~= p1 then
		cap.Position = p1
	end
	if cap.Size ~= size then
		cap.Size = size
		line2.Size = size
	end
	local p2 = UDim2.new(0, padL, 0.5, BUY_LINE_ROW_V / 2)
	if line2.Position ~= p2 then
		line2.Position = p2
	end
	if line2.Visible ~= twoLines then
		line2.Visible = twoLines
	end
	local kc = buyKeyCap
	if kc and kc.Visible ~= capVisible then
		kc.Visible = capVisible
	end
end

local function setBuyLine2(text: string)
	local l2 = buyLine2
	if l2 and l2.Text ~= text then
		l2.Text = text
	end
end

-- the text width (v) left for one BUY line
local function buyInnerWidthV(capVisible: boolean): number
	local btn = buyBtn
	local w = if btn then btn.Size.X.Offset else BUY_LANE.TouchSize.X
	return w - 2 * BUY_TEXT_PAD_V - (if capVisible then BUY_KEYCAP_V + 8 else 0)
end

-- v72: "BUYING…" / "BOUGHT …!" alone on one centred line; the copy is rebuilt once the hold ends
local function holdBuyCaption(text: string)
	setBuyCaption(text)
	if guideOn() then
		buyCopyDirty = true
		layoutBuyLines(false, false)
	end
end

local function flashPadBuyBought(displayName: string, structureId: string?)
	local btn = buyBtn
	if not btn or not btn.Visible then
		return
	end
	padBuyFlashToken += 1
	captionHoldUntil = os.clock() + 1.0
	setBuyLook("Buy")
	if guideOn() then
		-- plain text (RichText off); the short name when the full one does not fit at 20 v
		local text = string.format("BOUGHT %s!", string.upper(displayName))
		if structureId and lineWidthV(text, HudConfig.Fonts.Display) > buyInnerWidthV(false) then
			text = string.format("BOUGHT %s!", TycoonMath.ShortName(structureId))
		end
		holdBuyCaption(text)
		return
	end
	setBuyCaption(string.format("BOUGHT %s!", escapeRich(string.upper(displayName))))
	-- the standing Heartbeat refreshPadBuyButton rewrites the caption once captionHoldUntil passes
end

local function hidePadBuyButton()
	activeBuyStructureId = nil
	activeBuyPart = nil
	if buyBtn then
		buyBtn.Visible = false
	end
	PromptController.SetBuyButtonActive(false)
	if guideOn() then
		HudLayout.SetFlag(TycoonGuideConfig.AtConsoleFlag, false)
	end
end

-- v72 Collect: the money is in the ATM. Fires nothing; the GO line goes to YOUR ATM + one short toast.
local function showAtmLine()
	if ConsoleWaypoint.ShowAtm then
		local ok, err = pcall(ConsoleWaypoint.ShowAtm, myPlotId)
		if not ok then
			warn("[WorldPrompt] ConsoleWaypoint.ShowAtm failed:", err)
		end
	end
	local now = os.clock()
	if now - collectToastAt >= COLLECT_TOAST_CD then
		collectToastAt = now
		NotificationController.Show(GTEXT.CollectToast, "Info", 3)
	end
end

-- TouchSize on touch, the pinned desktop size otherwise (v72 guide: the desktop button is wider by the "E" key cap,
-- so both lines get the same text width as on touch)
local function buyButtonSize(touch: boolean): UDim2
	if not touch then
		if guideOn() then
			return UDim2.fromOffset(BUY_LANE.TouchSize.X + BUY_KEYCAP_V + 8, BUY_BTN_SIZE_DESKTOP.Y.Offset)
		end
		return BUY_BTN_SIZE_DESKTOP
	end
	if guideOn() then
		return UDim2.fromOffset(BUY_LANE.TouchSize.X, BUY_LANE.TouchSize.Y)
	end
	return BUY_BTN_SIZE_TOUCH
end

-- v72 F3: on touch the BUY lane's left edge sits ThumbZoneFrac of the safe width + ClearPx right of its left edge
local function buyLaneShiftV(widthV: number): number
	if not (guideOn() and HudLayout.IsTouch()) then
		return 0
	end
	return TycoonMath.ActionLaneShiftV(HudLayout.ContentSizeV(), widthV, BUY_LANE.ThumbZoneFrac, BUY_LANE.ClearPx, HudLayout.Scale())
end

local function placeBuyLane()
	local lane = buyLaneFrame
	if not lane then
		return
	end
	local want = UDim2.new(0.5, buyLaneShiftV(lane.Size.X.Offset), 1, -HudLayout.ActionLaneBottomV())
	if lane.Position ~= want then
		lane.Position = want
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
	-- Above the HUD (55) and panels (60); below toasts (70). One HUD scale + CoreUISafeInsets (HudLayout).
	screen.DisplayOrder = HudConfig.DisplayOrder.WE_PadBuyGui
	HudLayout.ApplyScreen(screen, { Insets = "Core" })
	screen.Parent = pg
	_buyGui = screen

	local touch = HudLayout.IsTouch()
	local guide = guideOn()
	local size = buyButtonSize(touch)
	-- the action lane slot: bottom-centre, 100 v (touch) / 86 v (desktop) above the content bottom
	-- (v72 guide on touch: shifted right so its left edge clears the thumb zone)
	local lane = Instance.new("Frame")
	lane.Name = "Lane"
	lane.AnchorPoint = Vector2.new(0.5, 1)
	lane.Position = UDim2.new(0.5, buyLaneShiftV(size.X.Offset), 1, -HudLayout.ActionLaneBottomV())
	lane.Size = size
	lane.BackgroundTransparency = 1
	lane.BorderSizePixel = 0
	lane.Active = false
	lane.Parent = screen
	HudLayout.BindVisibility(lane, { HideWhen = { "Modal", "Driving", "Dead" } })
	if guide then
		buyLaneFrame = lane
		if buyLaneConn == nil then
			-- rotation / safe-area change: the thumb-zone edge moves with the viewport
			buyLaneConn = HudLayout.LayoutChanged:Connect(placeBuyLane)
		end
	end

	local btn = Instance.new("TextButton")
	btn.Name = "BuyButton"
	btn.AnchorPoint = Vector2.new(0.5, 0.5)
	btn.Position = UDim2.fromScale(0.5, 0.5)
	btn.Size = size
	btn.BackgroundColor3 = BUY_OK_TOP
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = true
	btn.Text = ""
	btn.Visible = false
	btn.Active = true
	btn.Selectable = true
	btn.ZIndex = 40
	btn.Parent = lane
	UIUtil.Corner(btn, 14)
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = gradientTo(BUY_OK_TOP, BUY_OK_BOTTOM)
	grad.Parent = btn
	buyGradient = grad
	local stroke = UIUtil.Stroke(btn, BUY_OK_STROKE, 3)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Transparency = 0
	buyStroke = stroke
	buyLook = nil
	UIUtil.EnsureMinTouch(btn, BUY_BTN_MIN_H)

	if guide then
		-- v72: two fixed 20 v lines (Display over Body), never TextScaled; the "E" key cap only while
		-- HudLayout.PrefersKeys() (PreferredInput) and E does what the button says (not in the Collect state)
		local cap = Instance.new("Frame")
		cap.Name = "KeyCap"
		cap.AnchorPoint = Vector2.new(0, 0.5)
		cap.Position = UDim2.new(0, BUY_TEXT_PAD_V, 0.5, 0)
		cap.Size = UDim2.fromOffset(BUY_KEYCAP_V, BUY_KEYCAP_V)
		cap.BackgroundColor3 = Color3.fromRGB(232, 255, 232)
		cap.BorderSizePixel = 0
		cap.Active = false
		cap.Visible = false
		cap.ZIndex = 41
		cap.Parent = btn
		UIUtil.Corner(cap, 5)
		local key = Instance.new("TextLabel")
		key.Name = "Key"
		key.BackgroundTransparency = 1
		key.Size = UDim2.fromScale(1, 1)
		key.Font = HudConfig.Fonts.Body
		key.TextSize = 16
		key.TextColor3 = BUY_OK_STROKE
		key.Text = "E"
		key.ZIndex = 42
		key.Parent = cap
		buyKeyCap = cap

		local function line(name: string, font: Enum.Font): TextLabel
			local t = Instance.new("TextLabel")
			t.Name = name
			t.BackgroundTransparency = 1
			t.AnchorPoint = Vector2.new(0, 0.5)
			t.Font = font
			t.TextSize = BUY_LINE_V
			t.TextScaled = false
			t.TextWrapped = false
			t.RichText = false
			t.TextXAlignment = Enum.TextXAlignment.Center
			t.TextColor3 = Color3.fromRGB(255, 255, 255)
			t.Text = ""
			t.ZIndex = 42
			t.Parent = btn
			UIUtil.TextOutline(t, 1.4)
			return t
		end
		buyCaption = line("Caption", HudConfig.Fonts.Display)
		buyLine2 = line("Line2", HudConfig.Fonts.Body)
		buyCopyDirty = true
		layoutBuyLines(true, false)
	end

	-- desktop / gamepad: an "E" key cap (the console's E-hold prompt still works; its pill hides while BUY shows)
	local padL = 14
	if not touch and not guide then
		local cap = Instance.new("Frame")
		cap.Name = "KeyCap"
		cap.AnchorPoint = Vector2.new(0, 0.5)
		cap.Position = UDim2.new(0, padL, 0.5, 0)
		cap.Size = UDim2.fromOffset(28, 28)
		cap.BackgroundColor3 = Color3.fromRGB(232, 255, 232)
		cap.BorderSizePixel = 0
		cap.Active = false
		cap.ZIndex = 41
		cap.Parent = btn
		UIUtil.Corner(cap, 5)
		local key = Instance.new("TextLabel")
		key.Name = "Key"
		key.BackgroundTransparency = 1
		key.Size = UDim2.fromScale(1, 1)
		key.Font = HudConfig.Fonts.Body
		key.TextSize = 16
		key.TextColor3 = BUY_OK_STROKE
		key.Text = "E"
		key.ZIndex = 42
		key.Parent = cap
		padL += 28 + 8
	end

	if not guide then
		local caption = Instance.new("TextLabel")
		caption.Name = "Caption"
		caption.BackgroundTransparency = 1
		caption.AnchorPoint = Vector2.new(0, 0.5)
		caption.Position = UDim2.new(0, padL, 0.5, 0)
		caption.Size = UDim2.new(1, -(padL + 12), 1, -10)
		caption.Font = HudConfig.Fonts.Display
		caption.RichText = true
		caption.TextScaled = true
		caption.TextColor3 = Color3.fromRGB(255, 255, 255)
		caption.Text = "BUY"
		caption.ZIndex = 42
		caption.Parent = btn
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 20
		limit.MinTextSize = 12
		limit.Parent = caption
		UIUtil.TextOutline(caption, 1.4)
		buyCaption = caption
	end

	local lastTapAt = 0
	local function onBuyPressed()
		local sid = activeBuyStructureId
		if typeof(sid) ~= "string" then
			return
		end
		-- v67: one purchase per tap (a stray double event bought two levels)
		local now = os.clock()
		if now - lastTapAt < 0.35 then
			return
		end
		lastTapAt = now
		local display, _level, cost, isMax, prereqHint = structureInfo(sid)
		if isMax or prereqHint or cost == nil then
			hidePadBuyButton()
			return
		end
		-- v72 Collect (wallet short, wallet + ATM enough): no buy request; the line goes to the player's own ATM
		if guideOn() and (TycoonMath.MoneyState(cost, liveCash(), pendingCash(), incomePerSec())) == "Collect" then
			showAtmLine()
			return
		end
		-- Intentional tap: clear walk-over debounce so BUY always fires
		lastPurchaseAt[sid] = 0
		pendingPurchase[sid] = nil
		print(string.format("[WorldPrompt] BUY button tap → RequestPurchaseUpgrade %s %s cost=%s", sid, display, tostring(cost)))
		-- v61: "BUYING…" only after FireServer actually ran (see tryPurchase showBuying)
		tryPurchase(sid, { showBuying = true })
	end
	-- v67: Activated only — it already fires for mouse, touch and gamepad. Also wiring MouseButton1Click
	-- ran the handler twice per click (two RequestPurchaseUpgrade = two levels bought).
	btn.Activated:Connect(onBuyPressed)

	buyBtn = btn
	return btn
end

-- v72 line 1 of the Buy state: the full name, else the short name, else no name ("BUILD  $600"); an upgrade keeps
-- "LV n" and the price. Everything comes from TycoonGuideConfig.Text.
local function buyLine1(sid: string, display: string, level: number, price: string, unlock: string?, innerW: number): string
	local font = HudConfig.Fonts.Display
	if level <= 0 then
		if unlock then
			return string.format(GTEXT.BuyBuildShort, price) -- line 2 names what it unlocks
		end
		local full = string.format(GTEXT.BuyBuild, string.upper(display), price)
		if lineWidthV(full, font) <= innerW then
			return full
		end
		local short = string.format(GTEXT.BuyBuild, TycoonMath.ShortName(sid), price)
		if lineWidthV(short, font) <= innerW then
			return short
		end
		return string.format(GTEXT.BuyBuildShort, price)
	end
	local up = string.format(GTEXT.BuyUpgrade, TycoonMath.ShortName(sid), level + 1, price)
	if lineWidthV(up, font) <= innerW then
		return up
	end
	return string.format(GTEXT.BuyUpgrade, "", level + 1, price) -- "UPGRADE  LV 5  $12.5K"
end

--[[ v72 BUY copy (guide on). Rebuilt when its inputs change (structure, level, price, or buyCopyDirty: cash, ATM,
	WE_IncomePerSec, WE_IncomeMult, upgrades), at most every BUY_COPY_MIN_SEC; the Earn countdown ticks at
	EtaRefreshHz from the end time taken at the last rebuild. No allocation on the frames in between. ]]
local function refreshGuideBuyCopy(sid: string, display: string, level: number, cost: number)
	local now = os.clock()
	local same = sid == copySid and level == copyLevel and cost == copyCost
	if same and not buyCopyDirty then
		local etaEnd = copyEtaEnd
		local hz = math.max(0.1, TycoonGuideConfig.EtaRefreshHz)
		if copyLook == "Earn" and etaEnd ~= nil and now - copyEtaAt >= 1 / hz then
			copyEtaAt = now
			setBuyLine2(string.format(GTEXT.BuyNeedLine2, copyGain, TycoonMath.FormatEta(math.max(0, etaEnd - now))))
		end
		return
	end
	if same and now - copyAt < BUY_COPY_MIN_SEC then
		return
	end
	copySid, copyLevel, copyCost, copyAt = sid, level, cost, now
	buyCopyDirty = false

	local gain = stepGainText(sid, level)
	local moneyState, short, eta = TycoonMath.MoneyState(cost, liveCash(), pendingCash(), incomePerSec())
	local state: BuyLook = asLook(moneyState)
	local capVisible = state ~= "Collect" and HudLayout.PrefersKeys()
	local innerW = buyInnerWidthV(capVisible)
	local line1: string
	local line2: string
	copyEtaEnd = nil
	if state == "Collect" then
		line1 = string.format(GTEXT.BuyCollect, TycoonMath.ShortCash(short))
		line2 = string.format(GTEXT.BuyCollectLine2, gain)
	elseif state == "Earn" then
		line1 = string.format(GTEXT.BuyNeed, TycoonMath.ShortCash(short))
		if eta ~= nil then
			copyEtaEnd = now + eta
			line2 = string.format(GTEXT.BuyNeedLine2, gain, TycoonMath.FormatEta(eta))
		else
			line2 = string.format(GTEXT.BuyIncome, gain) -- no income yet: no countdown
		end
	else
		local unlock = TycoonMath.UnlockText(sid, level + 1)
		line1 = buyLine1(sid, display, level, TycoonMath.ShortCash(cost), unlock, innerW)
		line2 = string.format(GTEXT.BuyIncome, gain)
		if unlock then
			local withUnlock = string.format(GTEXT.BuyIncomeUnlock, gain, unlock)
			if lineWidthV(withUnlock, HudConfig.Fonts.Body) <= innerW then
				line2 = withUnlock
			end
		end
	end
	copyLook, copyGain, copyEtaAt = state, gain, now
	setBuyLook(state)
	layoutBuyLines(true, capVisible)
	setBuyCaption(line1)
	setBuyLine2(line2)
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

	local display, level, cost, isMax, prereqHint = structureInfo(structureId)
	if isMax or prereqHint or cost == nil then
		hidePadBuyButton()
		return
	end

	local btn = ensurePadBuyGui()
	activeBuyStructureId = structureId
	activeBuyPart = part
	if guideOn() then
		if os.clock() >= captionHoldUntil then
			refreshGuideBuyCopy(structureId, display, level, cost)
		end
	elseif os.clock() >= captionHoldUntil then
		local have = liveCash()
		local canAfford = have >= cost
		setBuyLook(if canAfford then "Buy" else "Earn")
		if canAfford then
			-- "BUILD HELIPAD  $5,000" / "UPGRADE HELIPAD  $12,000" (income lives on the console screen / Base panel)
			local verb = if level <= 0 then "BUILD" else "UPGRADE"
			setBuyCaption(string.format("%s %s  %s", verb, escapeRich(string.upper(display)), fullCost(cost)))
		else
			setBuyCaption(string.format('NEED  <font color="%s">%s more</font>', BUY_SHORT_PRICE, fullCost(cost - have)))
		end
	end
	btn.Visible = true
	PromptController.SetBuyButtonActive(true)
	if guideOn() then
		HudLayout.SetFlag(TycoonGuideConfig.AtConsoleFlag, true) -- the guide chip steps aside (one message at a time)
	end
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

-- v70: the console label grows with the HUD scale: k = clamp(S / 0.9, 0.9, 1.3) → 106x36 phone, 118x40 at
-- 720p, 151x51 at 1080p (BillboardGui offsets are real px; the HUD UIScale never reaches them)
local function chipScale(): number
	return math.clamp(HudLayout.Scale() / 0.9, 0.9, 1.3)
end

local function clampChipSize(size: UDim2, k: number?): UDim2
	-- v50: hard clamp width+height so legacy/Scale chips never dominate mobile (v70: then × k)
	local kk = k or 1
	local w = size.X.Offset
	local h = size.Y.Offset
	if w <= 0 and h <= 0 then
		w, h = PRICE_BILLBOARD_SIZE.X.Offset, PRICE_BILLBOARD_SIZE.Y.Offset
	end
	local cw = if w > 0 then math.min(w, PRICE_CHIP_MAX_W) else PRICE_CHIP_MAX_W
	local ch = if h > 0 then math.min(h, 44) else 40
	return UDim2.fromOffset(math.floor(cw * kk + 0.5), math.floor(ch * kk + 0.5))
end

-- the latest "standing near an ATM" answer (the throttled loop keeps it); price labels stay off near the ATM
local nearAtmNow = false
-- labels hidden on purpose (another player's plot, MAX): the ATM soft-restore must never switch these back on
local priceHidden: { [BasePart]: boolean } = setmetatable({} :: any, { __mode = "k" })

-- v72 console tag geometry (guide on): stud-scaled box above the console top; the range is set with the copy
local tagPlaced: { [BillboardGui]: boolean } = setmetatable({} :: any, { __mode = "k" })
local function placeConsoleTag(bb: BillboardGui, part: BasePart)
	local size = UDim2.fromScale(TAG.StudsW, TAG.StudsH)
	if bb.Size ~= size then
		bb.Size = size
	end
	local offset = Vector3.new(0, part.Size.Y * 0.5 + CONSOLE_LABEL.StudsAboveConsoleTop, 0)
	if bb.StudsOffsetWorldSpace ~= offset then
		bb.StudsOffsetWorldSpace = offset
	end
	if tagPlaced[bb] then
		return
	end
	tagPlaced[bb] = true
	bb.StudsOffset = Vector3.zero
	-- stops growing closer than this (deprecated in the API docs, still honoured; skipped if an engine drops it)
	pcall(function()
		(bb :: any).DistanceLowerLimit = TAG.DistanceLowerLimit
	end)
	bb.ClipsDescendants = false
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
end

local function setBillboardNearOnly(bb: BillboardGui, ownedChip: boolean?, part: BasePart?)
	-- never AlwaysOnTop giant tabs — plain text, near-only, owner-only
	if part and guideOn() and isConsolePart(part) then
		placeConsoleTag(bb, part)
		return
	end
	local k = chipScale()
	if part and isConsolePart(part) then
		-- v70: 2.2 studs above the console top (the old 5-stud host + 5.5 landed in the ceiling of walk-ins)
		bb.Size = clampChipSize(PRICE_BILLBOARD_SIZE, k)
		bb.StudsOffset = Vector3.zero
		bb.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y * 0.5 + CONSOLE_LABEL.StudsAboveConsoleTop, 0)
		bb.MaxDistance = if ownedChip then CONSOLE_LABEL.MaxDistanceUpgrade else CONSOLE_LABEL.MaxDistanceBuild
		bb.AlwaysOnTop = false
	elseif ownedChip then
		bb.Size = clampChipSize(PRICE_BILLBOARD_OWNED_SIZE, k)
		bb.StudsOffset = Vector3.new(0, 6, 0)
		bb.MaxDistance = 28
		bb.AlwaysOnTop = false
	else
		bb.Size = clampChipSize(PRICE_BILLBOARD_SIZE, k)
		bb.StudsOffset = Vector3.new(0, 5.5, 0)
		bb.MaxDistance = PRICE_BILLBOARD_MAX_DIST
		bb.AlwaysOnTop = false
	end
	bb.LightInfluence = 0
	-- Defensive: legacy / stale oversized chips
	if bb.Size.X.Offset > PRICE_CHIP_MAX_W * k + 1 then
		bb.Size = clampChipSize(bb.Size, 1)
	end
end

local function hidePriceBillboard(part: BasePart)
	priceHidden[part] = true
	-- every copy: the client host's and a server card still sitting on the part (MapSetup priceBillboard)
	local host = part:FindFirstChild("WE_BillboardHost")
	for _, holder in ipairs({ host, part } :: { Instance? }) do
		local existing = holder and holder:FindFirstChild(BILLBOARD_NAME)
		if existing and existing:IsA("BillboardGui") then
			WorldLabel.SetShown(existing, false) -- F4: through WorldLabel (a LabelGovernor hold stays consistent)
		end
	end
	-- MapSetup non-price Label billboards on other parts are left alone
end

local function resolveBillboardAdornee(part: BasePart): BasePart
	local found = part:FindFirstChild("WE_BillboardHost")
	if found and found:IsA("BasePart") then
		return found
	end
	-- Prefer tall invisible host above kit roof so geometry never occludes BUY name
	local roofY = 0
	for _, ch in ipairs(part:GetChildren()) do
		if ch:IsA("BasePart") and ch:GetAttribute("WE_KitRole") == "Roof" then
			roofY = math.max(roofY, (ch.Position.Y - part.Position.Y) + ch.Size.Y * 0.5)
		end
	end
	local host = Instance.new("Part")
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

local function styleChipLabel(lab: TextLabel, maxText: number)
	lab.BackgroundTransparency = 1
	lab.Font = HudConfig.Fonts.Display
	lab.TextScaled = true
	lab.TextWrapped = false
	lab.TextStrokeColor3 = HudConfig.Colors.Ink
	lab.TextStrokeTransparency = CONSOLE_LABEL.StrokeTransparency
	local limit = lab:FindFirstChildOfClass("UITextSizeConstraint")
	if not limit then
		local c = Instance.new("UITextSizeConstraint")
		c.Parent = lab
		limit = c
	end
	if limit then
		limit.MaxTextSize = maxText
		limit.MinTextSize = 8
	end
end

local function ensurePriceBillboard(part: BasePart): BillboardGui
	priceHidden[part] = nil
	local adornee: BasePart = if isConsolePart(part) then part else resolveBillboardAdornee(part)
	local host = part:FindFirstChild("WE_BillboardHost")
	local existing = adornee:FindFirstChild(BILLBOARD_NAME)
		or part:FindFirstChild(BILLBOARD_NAME)
		or (host and host:FindFirstChild(BILLBOARD_NAME))
	if existing and existing:IsA("BillboardGui") then
		existing.Adornee = adornee
		existing.Parent = adornee
		setBillboardNearOnly(existing, nil, part)
		WorldLabel.TagBaseLabel(existing) -- F4: counted by the LabelGovernor
		WorldLabel.SetShown(existing, not nearAtmNow)
		return existing
	end
	local legacy = part:FindFirstChild("Label")
	if legacy and legacy:IsA("BillboardGui") then
		legacy.Name = BILLBOARD_NAME
		setBillboardNearOnly(legacy, nil, part)
		WorldLabel.TagBaseLabel(legacy)
		WorldLabel.SetShown(legacy, not nearAtmNow)
		return legacy
	end

	-- v70: plain 2-line outlined text, NO card (Backdrop stays as a transparent holder)
	local bb = Instance.new("BillboardGui")
	bb.Name = BILLBOARD_NAME
	setBillboardNearOnly(bb, nil, part)
	bb.Adornee = adornee
	WorldLabel.SetShown(bb, not nearAtmNow)
	WorldLabel.TagBaseLabel(bb) -- F4: counted by the LabelGovernor (tagged before it is parented)
	bb.Parent = adornee

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Parent = bb

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Text = ""
	title.Parent = backdrop
	local cost = Instance.new("TextLabel")
	cost.Name = "Cost"
	cost.Text = ""
	cost.Parent = backdrop
	return bb
end

local function applyBillboardCopy(bb: BillboardGui, titleLine: string, detailLine: string, detailColor: Color3)
	local k = chipScale()
	-- plain text: no card, no stroke box (server cards arrive with a dark Backdrop + gold Stroke)
	local backdrop = bb:FindFirstChild("Backdrop")
	if backdrop and backdrop:IsA("Frame") then
		backdrop.BackgroundTransparency = 1
		local pad = backdrop:FindFirstChildOfClass("UIPadding")
		if pad then
			pad:Destroy()
		end
	end
	local stroke = bb:FindFirstChild("Stroke", true)
	if stroke and stroke:IsA("UIStroke") then
		stroke.Enabled = false
	end

	-- MapSetup price cards and v70 client labels use Title + Cost; pre-v70 client chips used one "Text"
	local titleLab = bb:FindFirstChild("Title", true)
	local costLab = bb:FindFirstChild("Cost", true)
	local textLab = bb:FindFirstChild("Text", true)

	if titleLab and titleLab:IsA("TextLabel") and costLab and costLab:IsA("TextLabel") then
		local twoLines = detailLine ~= ""
		titleLab.Position = UDim2.fromScale(0, 0)
		titleLab.Size = if twoLines then UDim2.fromScale(1, 0.5) else UDim2.fromScale(1, 1)
		titleLab.Text = titleLine
		titleLab.TextColor3 = CONSOLE_LABEL.NameColor
		styleChipLabel(titleLab, math.floor(CONSOLE_LABEL.NameSize * k + 0.5))
		costLab.Position = UDim2.fromScale(0, 0.5)
		costLab.Size = UDim2.fromScale(1, 0.5)
		costLab.Visible = twoLines
		costLab.Text = detailLine
		costLab.TextColor3 = detailColor
		styleChipLabel(costLab, math.floor(CONSOLE_LABEL.PriceSize * k + 0.5))
	elseif textLab and textLab:IsA("TextLabel") then
		textLab.Text = if detailLine ~= "" then (titleLine .. "\n" .. detailLine) else titleLine
		textLab.TextColor3 = detailColor
		styleChipLabel(textLab, math.floor(CONSOLE_LABEL.NameSize * k + 0.5))
	end
end

-- v72 console tag copy (guide on): fixed-size lines stacked in px around the box centre (WorldLabel's layout), so
-- they never overlap however small the stud box gets; the text overflows the box symmetrically (no clipping).
local function styleTagLabel(lab: TextLabel, px: number)
	lab.BackgroundTransparency = 1
	lab.Font = HudConfig.Fonts.Display
	lab.TextScaled = false
	lab.TextWrapped = false
	lab.TextSize = px
	lab.TextXAlignment = Enum.TextXAlignment.Center
	lab.TextYAlignment = Enum.TextYAlignment.Center
	lab.TextStrokeColor3 = HudConfig.Colors.Ink
	lab.TextStrokeTransparency = CONSOLE_LABEL.StrokeTransparency
	lab.AnchorPoint = Vector2.new(0.5, 0.5)
	lab.Size = UDim2.new(1, 0, 0, px + TAG_LINE_PAD)
	local limit = lab:FindFirstChildOfClass("UITextSizeConstraint")
	if limit then
		limit:Destroy() -- a v70 chip's TextScaled limits; this text is a fixed size
	end
end

local function applyTagCopy(bb: BillboardGui, titleLine: string, titleColor: Color3, detailLine: string, detailColor: Color3)
	local backdrop = bb:FindFirstChild("Backdrop")
	if backdrop and backdrop:IsA("Frame") then
		backdrop.BackgroundTransparency = 1
		local pad = backdrop:FindFirstChildOfClass("UIPadding")
		if pad then
			pad:Destroy()
		end
	end
	local stroke = bb:FindFirstChild("Stroke", true)
	if stroke and stroke:IsA("UIStroke") then
		stroke.Enabled = false
	end
	local titleLab = bb:FindFirstChild("Title", true)
	local costLab = bb:FindFirstChild("Cost", true)
	if titleLab and titleLab:IsA("TextLabel") and costLab and costLab:IsA("TextLabel") then
		styleTagLabel(titleLab, TAG_TITLE_PX)
		styleTagLabel(costLab, TAG_LINE_PX)
		if titleLab.Text ~= titleLine then
			titleLab.Text = titleLine
		end
		titleLab.TextColor3 = titleColor
		local twoLines = detailLine ~= ""
		costLab.Visible = twoLines
		if costLab.Text ~= detailLine then
			costLab.Text = detailLine
		end
		costLab.TextColor3 = detailColor
		if twoLines then
			local hT, hS = TAG_TITLE_PX + TAG_LINE_PAD, TAG_LINE_PX + TAG_LINE_PAD
			titleLab.Position = UDim2.new(0.5, 0, 0.5, -hS / 2)
			costLab.Position = UDim2.new(0.5, 0, 0.5, hT / 2)
		else
			titleLab.Position = UDim2.fromScale(0.5, 0.5)
		end
		return
	end
	local textLab = bb:FindFirstChild("Text", true) -- pre-v70 client chip: one label
	if textLab and textLab:IsA("TextLabel") then
		styleTagLabel(textLab, TAG_LINE_PX)
		textLab.Size = UDim2.new(1, 0, 0, 2 * (TAG_LINE_PX + TAG_LINE_PAD))
		textLab.Position = UDim2.fromScale(0.5, 0.5)
		textLab.Text = if detailLine ~= "" then (titleLine .. "\n" .. detailLine) else titleLine
		textLab.TextColor3 = detailColor
	end
end

-- MapSetup's console screen (ConsoleScreen.WE_ConsoleScreen): the owner reads the level / price there;
-- everyone else just sees the name. Local text only (the server wrote it once at build).
local function consoleScreenLabel(part: BasePart): TextLabel?
	local screenPart = part:FindFirstChild("ConsoleScreen")
	local sg = screenPart and screenPart:FindFirstChild("WE_ConsoleScreen")
	local lbl = sg and sg:FindFirstChildWhichIsA("TextLabel")
	return if lbl and lbl:IsA("TextLabel") then lbl else nil
end

local function setConsoleScreen(part: BasePart, text: string)
	local lbl = consoleScreenLabel(part)
	if lbl and lbl.Text ~= text then
		lbl.Text = text
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
	local isConsole = isConsolePart(part)
	local display, level, cost, isMax, prereqHint = structureInfo(structureId)
	local name = string.upper(display)

	if not isOwnPlotPad(part) then
		-- owner-only (spec §5): no price label, no pad wash; the console screen shows just the name
		-- (PromptController disables this console's WE_ServerBuyPrompt locally)
		hidePriceBillboard(part)
		if isConsole then
			setConsoleScreen(part, name)
		end
		return
	end

	local owned = level >= 1
	-- pad-name wash on the pad top: legacy walk-over pads before their first level only (never on consoles)
	local padName = part:FindFirstChild("WE_PadNameGui")
	if padName and (owned or isConsole) then
		padName:Destroy()
	end
	if not owned and not isConsole then
		ensurePadNameSurface(part, display)
	end

	local guide = guideOn()
	if isConsole then
		if isMax then
			setConsoleScreen(part, name .. "\nMAX")
		elseif prereqHint then
			setConsoleScreen(part, name .. "\nLOCKED")
		elseif cost then
			if guide then
				-- v72 (the 15 buildings; business kiosks have no screen): "WAREHOUSE\n$3.2K\n+$5.2/s"
				setConsoleScreen(part, string.format(GTEXT.ScreenLines, TycoonMath.ShortName(structureId), TycoonMath.ShortCash(cost, true), stepGainText(structureId, level)))
			elseif owned then
				setConsoleScreen(part, string.format("%s\nLV %d → %d\n%s", name, level, level + 1, shortCost(cost)))
			else
				setConsoleScreen(part, string.format("%s\nBUILD\n%s", name, shortCost(cost)))
			end
		end
		-- nothing to buy (MAX / locked) → no "Build / Upgrade" pill; the BUY button covers the buyable case
		local sp = part:FindFirstChild("WE_ServerBuyPrompt")
		if sp and sp:IsA("ProximityPrompt") then
			PromptController.SetSuppressed(sp, isMax or prereqHint ~= nil)
		end
	end

	if guide and isConsole then
		-- v72 console tag: MAX stays off where the console screen shows it (the 15 buildings); a business kiosk has
		-- no screen, so its tag reads MAX LEVEL
		local hasScreen = consoleScreenLabel(part) ~= nil
		if isMax and not CONSOLE_LABEL.ShowOnMax and hasScreen then
			hidePriceBillboard(part)
			return
		end
		local bb = ensurePriceBillboard(part)
		local pick = cost ~= nil and not isMax and isNextPick(structureId, level)
		local title = if pick then string.format(GTEXT.TagTitleNext, name) else name
		local titleColor = if pick then TAG.NextColor else CONSOLE_LABEL.NameColor
		local detail, detailColor = "", CONSOLE_LABEL.NameColor
		local met, req = TycoonMath.MeetsRequirements(structureId, upgrades)
		if isMax then
			detail = GTEXT.MaxLevel
		elseif not met and req then
			detail = string.format(GTEXT.Locked, TycoonMath.DisplayName(req.StructureId), req.Level)
			detailColor = CONSOLE_LABEL.LockedColor
		elseif cost then
			local state = TycoonMath.MoneyState(cost, liveCash(), pendingCash(), incomePerSec())
			detail = string.format(GTEXT.TagLine, TycoonMath.ShortCash(cost), stepGainText(structureId, level))
			detailColor = if state ~= "Earn" then CONSOLE_LABEL.PriceAffordable else CONSOLE_LABEL.PriceShort
		end
		bb.MaxDistance = if pick then TAG.NextMaxDistance elseif owned then TAG.MaxDistanceUpgrade else TAG.MaxDistanceBuild
		applyTagCopy(bb, title, titleColor, detail, detailColor)
		return
	end

	-- MAX → no label in the air (MAX is on the console screen); income is on the screen / Base panel
	if isMax and not CONSOLE_LABEL.ShowOnMax then
		hidePriceBillboard(part)
		return
	end

	local bb = ensurePriceBillboard(part)
	setBillboardNearOnly(bb, owned, part)

	if prereqHint then
		-- "Needs Command Center 2" in grey
		applyBillboardCopy(bb, name, (string.gsub(prereqHint, " L(%d+)$", " %1")), CONSOLE_LABEL.LockedColor)
	elseif cost then
		local canAfford = liveCash() >= cost
		local color = if canAfford then CONSOLE_LABEL.PriceAffordable else CONSOLE_LABEL.PriceShort
		if owned then
			applyBillboardCopy(bb, string.format("%s LV %d", name, level), "UPGRADE " .. shortCost(cost), color)
		else
			applyBillboardCopy(bb, name, "BUILD " .. shortCost(cost), color)
		end
	else
		applyBillboardCopy(bb, name, "", CONSOLE_LABEL.NameColor)
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

function tryPurchase(structureId: string, opts: { silentMax: boolean?, showBuying: boolean? }?)
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
			NotificationController.ShowPurchaseFailure("Already at MAX level", "Info", 2)
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
				NotificationController.ShowPurchaseFailure(prereqHint, "Warn", 3)
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
	-- v61: never unbounded GetEvent wait; never "Buying…" unless FireServer ran
	local fired = Remotes.FireServer(Constants.RemoteNames.RequestPurchaseUpgrade, {
		StructureId = structureId,
	} :: Types.PurchaseUpgradeRequest)
	if not fired then
		pendingPurchase[structureId] = nil
		local fk = "noremote|purchase"
		local lastFail = failToastAt[fk] or 0
		if (now - lastFail) >= 8 then
			failToastAt[fk] = now
			NotificationController.ShowPurchaseFailure("Buy failed — remotes not ready. Rejoin game.", "Error", 4)
		end
		warn("[WorldPrompt] BUY FAIL remote missing RequestPurchaseUpgrade")
		return
	end
	if opts and opts.showBuying then
		-- v70: the BUY button itself reads BUYING… (no "Buying X…" toast; the lane drops that line anyway)
		if buyBtn and buyBtn.Visible and activeBuyStructureId == structureId then
			captionHoldUntil = os.clock() + 1.5
			holdBuyCaption("BUYING…")
		end
		print(string.format("[WorldPrompt] BUY sent %s (%s)", structureId, display))
	end
	-- v63: keep in-flight until WE_BuyAck attribute OR PurchaseResult (8s hard timeout)
	local ackBefore = player:GetAttribute("WE_BuyAck")
	task.delay(8, function()
		if pendingPurchase[structureId] then
			-- Only timeout if attribute never advanced (primary ack path missed)
			local ackNow = player:GetAttribute("WE_BuyAck")
			if ackNow ~= nil and ackNow ~= ackBefore then
				pendingPurchase[structureId] = nil
				return
			end
			pendingPurchase[structureId] = nil
			warn("[WorldPrompt] BUY timeout no WE_BuyAck/PurchaseResult", structureId)
			captionHoldUntil = 0
			NotificationController.ShowPurchaseFailure("Buy timed out — try again", "Warn", 3)
		end
	end)
end

local CONSOLE_MARGIN = 5

local function pointInPad(hrpPos: Vector3, part: BasePart): boolean
	local localPos = part.CFrame:PointToObjectSpace(hrpPos)
	local half = part.Size * 0.5
	local margin = if isConsolePart(part) then CONSOLE_MARGIN else OVERLAP_MARGIN
	return math.abs(localPos.X) <= half.X + margin
		and math.abs(localPos.Z) <= half.Z + margin
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
	-- v68: never auto-buy at a console (walk-over + standing retries bought levels by accident)
	if isConsolePart(part) then
		return
	end
	local key = padKey(part, structureId)
	if not isOwnPlot(part) then
		local now = os.clock()
		local last = lastPurchaseAt[structureId] or 0
		if not fromStandingRetry and not lastOverlap[key] and now - last >= DEBOUNCE_SEC then
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
	-- streaming2 F14: the screen part streamed in (late, or again with the server's text): redraw on the next pass
	if streamingOn() and isConsolePart(part) then
		trackConn(slotConns, part, part.ChildAdded:Connect(function(child: Instance)
			if child.Name == "ConsoleScreen" then
				markBillboardsDirty()
			end
		end))
	end

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

-- v70: the client "Open Base" (WE_BasePlot) and "Hold to capture" (capture zones) prompts are gone (spec §5):
-- the Base menu opens from B / the Command Center map table / the tutorial; capture runs by standing in the zone
-- (the HUD capture bar shows it). A leftover prompt from an older client build is removed on sight.
local function removeClientPrompt(part: BasePart)
	local existing = part:FindFirstChild(PROMPT_NAME)
	if existing and existing:IsA("ProximityPrompt") then
		existing:Destroy()
	end
end

local function attachVehicleSpawn(part: BasePart)
	attachPromptOnce(part, function()
		-- v70: a lane pill "Garage" (PromptController); the seat keeps its own "Drive" prompt
		local prompt = makePrompt(part, "Garage", "", 0, 12)
		prompt.KeyboardKeyCode = Enum.KeyCode.E
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

local WORLD_LABEL_PASS_SEC = 0.25
local lastWorldLabelPass = 0

-- v70: the "TRAINING" worker tags and the training "+$/tick" billboard are removed from the design (spec §5). The
-- server no longer creates either, so the client hook that switched them off is gone too (streaming2 F19: it was a
-- Workspace.DescendantAdded listener that ran for every instance, and under streaming for every stream-in).

-- 4 Hz: SupplyDrop labels step aside near your consoles / ATM; price labels hide near the ATM. A label hidden on
-- purpose (hidePriceBillboard: another plot, MAX) or by WE_PriceForceHidden is never switched back on here.
local function worldLabelPass()
	local cam = Workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else nil
	local nearPad = false
	if camPos then
		for part in pairs(slotParts) do
			if part.Parent and (part.Position - camPos).Magnitude <= 20 then
				nearPad = true
				break
			end
		end
		if not nearPad then
			for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.MoneyCollector)) do
				if inst:IsA("BasePart") and (inst.Position - camPos).Magnitude <= 14 then
					nearPad = true
					break
				end
			end
		end
	end
	-- v31: Supply Drop labels — hide when near upgrade pads / ATM so structure names win
	local supplyTag = (Constants.Tags and (Constants.Tags :: any).SupplyDrop) or "WE_SupplyDrop"
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
							if d.Enabled then
								d.Enabled = false
							end
						elseif d.MaxDistance > 0 and not d.Enabled then
							d.Enabled = true
						end
					end
				end
			end
		end
	end

	-- P0: hide structure price boards when near MoneyCollector ATM
	local nearAtm = false
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.MoneyCollector)) do
			if inst:IsA("BasePart") and (inst.Position - hrp.Position).Magnitude <= ATM_HIDE_PRICE_STUDS then
				nearAtm = true
				break
			end
		end
	end
	nearAtmNow = nearAtm
	for part in pairs(slotParts) do
		if part.Parent then
			local host = part:FindFirstChild("WE_BillboardHost")
			local bb = (host and host:FindFirstChild(BILLBOARD_NAME)) or part:FindFirstChild(BILLBOARD_NAME)
			if bb and bb:IsA("BillboardGui") then
				local want = not nearAtm and not priceHidden[part] and part:GetAttribute("WE_PriceForceHidden") ~= true
				WorldLabel.SetShown(bb, want) -- F4: writes only on change, keeps a LabelGovernor hold
			end
		end
	end
end

local function startOverlapLoop()
	if overlapConn then
		overlapConn:Disconnect()
		overlapConn = nil
	end
	overlapConn = RunService.Heartbeat:Connect(function()
		-- v70: world-label upkeep at 4 Hz, not every frame (the per-frame workspace:GetDescendants() tag scan and
		-- the WE_HUD season-banner hack are gone: MapSetup / HUD own those labels)
		local now = os.clock()
		if now - lastWorldLabelPass >= WORLD_LABEL_PASS_SEC then
			lastWorldLabelPass = now
			worldLabelPass()
		end
		if billboardDirty and (os.clock() - lastBillboardRefresh) >= billboardThrottle then
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
	bindTag(Constants.Tags.BasePlot, removeClientPrompt)
	bindTag(Constants.Tags.UpgradeSlot, attachUpgradeSlot)
	bindTag(Constants.Tags.CaptureZone, removeClientPrompt)
	bindTag(Constants.Tags.VehicleSpawn, attachVehicleSpawn)
	bindTag(Constants.Tags.TutorialMarker, attachTutorialMarker)
end

-- Attribute fallback: StructureId pads under WarEmpireSetup.Bases missing the tag
local function rescanUntaggedSlots()
	if streamingOn() then
		-- streaming2 F19: the tag path binds every slot, on stream-in too; this walk would only see streamed parts
		return
	end
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
	-- v70 (spec §5): server labels made with WorldLabel{OwnerUserId} carry WE_LabelOwner; hide everyone else's here.
	local okFilter, errFilter = pcall(WorldLabel.StartOwnerFilter)
	if not okFilter then
		warn("[WorldPrompt] WorldLabel owner filter failed:", errFilter)
	end
	-- v58: liveCash listeners FIRST (before BaseState/other remotes that WaitForChild-block)
	local function applyCash(n: any)
		local v = tonumber(n)
		if typeof(v) == "number" then
			cash = math.floor(v)
			buyCopyDirty = true
			markBillboardsDirty()
			-- NEED→BUY while standing when cash syncs
			if activeBuyPart and activeBuyStructureId then
				refreshPadBuyButton(activeBuyPart, activeBuyStructureId)
			end
		end
	end

	-- v60: leaderstats/attrs FIRST — BindEvent never blocks Init
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

	local function wireLs(folder: Instance)
		local cashV = folder:FindFirstChild("Cash")
		if cashV and (cashV:IsA("IntValue") or cashV:IsA("NumberValue")) then
			(cashV :: any):GetPropertyChangedSignal("Value"):Connect(function()
				tryLeaderstatsCash()
			end)
		end
		folder.ChildAdded:Connect(function(ch)
			if ch.Name == "Cash" and (ch:IsA("IntValue") or ch:IsA("NumberValue")) then
				(ch :: any):GetPropertyChangedSignal("Value"):Connect(function()
					tryLeaderstatsCash()
				end)
				tryLeaderstatsCash()
			end
		end)
		tryLeaderstatsCash()
	end
	do
		local existing = player:FindFirstChild("leaderstats")
		if existing then
			wireLs(existing)
		end
	end
	player.ChildAdded:Connect(function(ch)
		if ch.Name == "leaderstats" then
			wireLs(ch)
		end
	end)

	do
		local attrCash = player:GetAttribute("WE_Cash")
		if typeof(attrCash) == "number" then
			applyCash(attrCash)
		end
		player:GetAttributeChangedSignal("WE_Cash"):Connect(function()
			applyCash(player:GetAttribute("WE_Cash"))
		end)
	end

	-- v72 guide: the ATM balance, the income rate / multiplier and the server's pick feed the BUY copy and the tags
	-- (server-stamped attributes; a missing one reads as its default, see the helpers at the top)
	if guideOn() then
		local function onGuideInput()
			buyCopyDirty = true
			markBillboardsDirty()
		end
		for _, attr in ipairs({ "WE_PendingCash", "WE_IncomePerSec", "WE_IncomeMult", "WE_NextBuy" }) do
			player:GetAttributeChangedSignal(attr):Connect(onGuideInput)
		end
		HudLayout.InputModeChanged:Connect(onGuideInput) -- the "E" key cap follows PreferredInput
		-- F5 one pointer: the NEXT tag follows the tutorial step (TutorialStateUpdate / the HUD "Tutorial" flag)
		Remotes.BindEvent(Constants.RemoteNames.TutorialStateUpdate, function(payload: any)
			if typeof(payload) == "table" then
				applyTutorialStep(payload.Complete == true, payload.Id, payload.PadStructureId, payload.Pointer)
				markBillboardsDirty()
			end
		end)
		HudLayout.FlagChanged:Connect(function(name: string)
			if name == "Tutorial" then
				markBillboardsDirty()
			end
		end)
	end

	Remotes.BindEvent(Constants.RemoteNames.EconomyUpdate, function(payload: Types.EconomyUpdatePayload)
		applyCash(payload.Cash)
	end)

	-- v70: one failed purchase = one line. WE_BuyAck (attribute) and PurchaseResult (remote) both answer every
	-- buy; the first one shows, the second is skipped for the same structure inside BUY_FAIL_DEDUPE_SEC, and
	-- NotificationController.ShowPurchaseFailure also swallows the server's own Warn echo.
	local lastAckAt: { [string]: number } = {}
	local spendFloatAt: { [string]: number } = {}
	local function failureText(err: string, sid: any): (string, string)
		if err == "NotAtConsole" then
			-- v71 console-only buying: the server saw this character away from its own console for sid
			local def = if typeof(sid) == "string" then BaseConfig.Structures[sid] else nil
			return string.format(ConsoleBuyConfig.Text.NotAtConsole, if def then def.DisplayName else tostring(sid)), "Warn"
		elseif err == "InsufficientCash" then
			return "You need more Money!", "Warn" -- competitor wording; the BUY button already reads NEED $N more
		elseif err == "NoPlot" then
			return "Claim a base first — stand on your plot pad", "Error"
		elseif err == "NoProfile" then
			return "Profile still loading — try BUY again", "Error"
		elseif err == "MissingRequirement" then
			return "Missing prerequisite structure", "Error"
		elseif err == "MaxLevel" then
			return "Already at MAX level", "Info"
		elseif err == "WrongPlot" then
			return "Not your base — walk your plot pads to buy", "Error"
		elseif err == "RateLimited" then
			return "Buying too fast — wait a moment", "Error"
		end
		return "Buy failed: " .. err, "Error"
	end
	local function onBuyResult(source: string, sid: any, ok: boolean, err: string?, newCash: any, newLevel: any)
		if typeof(sid) == "string" then
			pendingPurchase[sid] = nil
		end
		captionHoldUntil = 0
		-- the ack's cash is only meaningful on success (a failed ack stamps WE_BuyCash = 0)
		if ok and typeof(newCash) == "number" then
			applyCash(newCash)
		end
		local key = tostring(sid) .. "|" .. (if ok then "ok" else tostring(err))
		local now = os.clock()
		local dup = now - (lastAckAt[key] or -math.huge) < BUY_FAIL_DEDUPE_SEC
		lastAckAt[key] = now
		if ok then
			local def = if typeof(sid) == "string" then BaseConfig.Structures[sid] else nil
			local name = if def then def.DisplayName else tostring(sid)
			print(string.format("[WorldPrompt] %s OK %s Lv=%s cash=%s", source, tostring(sid), tostring(newLevel), tostring(newCash)))
			if not dup then
				flashPadBuyBought(name, if typeof(sid) == "string" then sid else nil)
			end
			-- "-$20,000" spend float at the cash pill (HudConfig.CashFloat.ShowSpend) — only PurchaseResult knows
			-- the level bought (WE_BuyAck has no level); the server's "Purchase SUCCESSFUL!" line is the toast
			local lvl = tonumber(newLevel)
			local spent = if def and lvl then def.Costs[lvl] else nil
			local fk = tostring(sid) .. "|" .. tostring(lvl)
			if HudConfig.CashFloat.ShowSpend and typeof(spent) == "number" and spent > 0 and now - (spendFloatAt[fk] or -math.huge) > 2 then
				spendFloatAt[fk] = now
				HudLayout.CashFloat(-spent)
			end
		else
			local errStr = tostring(err or "Failed")
			print(string.format("[WorldPrompt] %s FAIL %s → %s%s", source, tostring(sid), errStr, if dup then " (dup)" else ""))
			if not dup then
				local msg, kind = failureText(errStr, sid)
				NotificationController.ShowPurchaseFailure(msg, kind, 3)
			end
		end
		markBillboardsDirty()
	end

	-- v63 PRIMARY: attribute ack (replicates without remotes) — clear pending + apply result
	player:GetAttributeChangedSignal("WE_BuyAck"):Connect(function()
		onBuyResult(
			"WE_BuyAck",
			player:GetAttribute("WE_BuyStructure"),
			player:GetAttribute("WE_BuyOk") == true,
			tostring(player:GetAttribute("WE_BuyErr") or "Failed"),
			player:GetAttribute("WE_BuyCash"),
			nil
		)
	end)

	-- v62/v63 secondary: PurchaseResult remote — clear pending + show server reason (deduped with WE_BuyAck)
	Remotes.BindEvent(Constants.RemoteNames.PurchaseResult, function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		onBuyResult("PurchaseResult", payload.StructureId, payload.Ok == true, tostring(payload.Error or "Failed"), payload.Cash, payload.NewLevel)
	end)

	task.spawn(function()
		local synced = false
		for i = 0, 20 do
			if typeof(player:GetAttribute("WE_Cash")) == "number" then
				applyCash(player:GetAttribute("WE_Cash"))
				synced = true
			end
			if tryLeaderstatsCash() then
				synced = true
			end
			local fn = Remotes.TryGetFunction(Constants.RemoteNames.GetPlayerState)
			if fn then
				local ok, state = pcall(function()
					return fn:InvokeServer()
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
							PromptController.SetMyPlotId(myPlotId)
						end
					end
					markBillboardsDirty()
					print(string.format("[WorldPrompt] cash bootstrap have=%d", cash))
					return
				end
			end
			if synced and i >= 2 then
				markBillboardsDirty()
				print(string.format("[WorldPrompt] cash bootstrap via attr/leaderstats have=%d", cash))
				return
			end
			task.wait(0.25)
		end
		if not synced then
			warn("[WorldPrompt] cash bootstrap failed — relying on EconomyUpdate/Attribute")
		end
	end)

	Remotes.BindEvent(Constants.RemoteNames.BaseStateUpdate, function(base: Types.BaseStatePayload)
		local prev = upgrades
		upgrades = base.Upgrades or upgrades
		if typeof(base.PlotId) == "number" then
			if myPlotId ~= nil and myPlotId ~= base.PlotId then
				clearOverlapState()
			end
			myPlotId = base.PlotId
			PromptController.SetMyPlotId(myPlotId)
		end
		if activeBuyStructureId and typeof(upgrades) == "table" then
			local sid = activeBuyStructureId
			local before = if typeof(prev) == "table" then (prev[sid] or 0) else 0
			local after = upgrades[sid] or 0
			if after > before then
				local def = BaseConfig.Structures[sid]
				local name = if def then def.DisplayName else sid
				flashPadBuyBought(name, sid)
				print(string.format("[WorldPrompt] BUY OK flash %s %d→%d", sid, before, after))
			end
		end
		markBillboardsDirty()
	end)

	Remotes.BindEvent(Constants.RemoteNames.PlayerStateUpdate, function(state: Types.PlayerStatePayload)
		applyCash(state.Cash)
		-- F5 one pointer: the tutorial step (index in the current order) or complete
		if state.TutorialComplete == true then
			applyTutorialStep(true, nil, nil, nil)
		elseif state.TutorialComplete == false and typeof(state.TutorialStep) == "number" then
			local def = TutorialConfig.GetStep(state.TutorialStep)
			if def ~= nil then
				applyTutorialStep(false, def.Id, nil, nil)
			end
		end
		if state.Base then
			upgrades = state.Base.Upgrades
			if typeof(state.Base.PlotId) == "number" then
				if myPlotId ~= nil and myPlotId ~= state.Base.PlotId then
					clearOverlapState()
				end
				myPlotId = state.Base.PlotId
				PromptController.SetMyPlotId(myPlotId)
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
