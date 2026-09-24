--!strict
--[[
	NotificationController — v70 "clean screen" toast lane + offer toast + the base-alert slot.

	LANE (HudConfig.Toast, spec §4.1): plain outlined FredokaOne text in the top-centre stack (TopStack "Toasts"),
	no cards. Max 2 lines (newest at the bottom; a 3rd evicts the oldest of the lowest priority), the same key
	(digits stripped) within 3 s updates the line to "Text ×N" and restarts its timer. Only Success / Error /
	Warn / Reward play a sound (≤ 1 per 0.4 s). Type "Collect" never makes a line: it becomes the "+$N" cash float
	at the pill (HudLayout.CashFloat → HUDController).

	ROUTING (client side of spec §4.2; the server fixes are deferred, so TODAY's server lines are handled here):
	NotificationConfig.Rewrite → HudConfig.Toast.Reroute → HudConfig.Toast.Drop → NotificationConfig.Throttle →
	purchase-failure echo dedupe (one failed buy = one line) → lane.

	OFFER (spec §4.3): NotificationController.ShowOffer({Key, Title, Sub?, Cta, OnGet}) → one gold offer pill
	under the toasts (TopStack "Offer") for HudConfig.Offer.HoldSeconds. Throttle (owner decision, money plan D8):
	first ≥ FirstAfterJoinSeconds after join, ≥ MinGapSeconds apart, ≤ MaxPerSession per session, the death offer
	≥ DeathOfferMinGapSeconds apart. Deferred while Drawn / RecentCombat / Driving / Modal / Tutorial; a deferred
	offer that never found a calm moment is dropped after DropAfterQueuedSeconds and lights the Shop badge "!".
	OnGet is the caller's existing promptDevProduct / promptGamePass call — this file never grants anything.

	P0 marker: Purchase SUCCESSFUL lines keep the green Success type (HIGH_CONTRAST_SUCCESS below).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local HudConfig = require(Shared.Configs.HudConfig)
local NotificationConfig = require(Shared.Configs.NotificationConfig)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)

local AudioController = require(script.Parent.Parent.Modules.AudioController)
local HudLayout = require(script.Parent.Parent.Modules.HudLayout)
local HudIcons = require(script.Parent.Parent.Modules.HudIcons)

local NotificationController = {}

export type OfferDef = {
	Key: string,
	Title: string,
	Sub: string?,
	Cta: string,
	OnGet: () -> (),
}

local player = Players.LocalPlayer

-- Marker for BuyPathStatic / QA: the Purchase SUCCESSFUL line keeps the Success type (green, sound, 1.8 s)
local HIGH_CONTRAST_SUCCESS = true

local TOAST = HudConfig.Toast
local OFFER = HudConfig.Offer
local COLORS = HudConfig.Colors
local FONT_DISPLAY = HudConfig.Fonts.Display
local FONT_BODY = HudConfig.Fonts.Body

---------------------------------------------------------------------------------------------------------------
-- state
---------------------------------------------------------------------------------------------------------------

type Line = {
	Label: TextLabel,
	Stroke: UIStroke,
	Pop: UIScale,
	Key: string,
	Type: string,
	Text: string,
	Count: number,
	Seq: number,
	UpdatedAt: number,
	Token: number,
	Dying: boolean,
}

type OfferEntry = {
	Def: OfferDef,
	Death: boolean,
	EligibleAt: number,
	QueuedAt: number,
}

local gui: ScreenGui? = nil
local lane: Frame? = nil
local laneList: UIListLayout? = nil
local lines: { Line } = {}
local lineSeq = 0
local lastSoundAt = -math.huge

local rerouteAt: { [number]: number } = {}
local throttleAt: { [number]: number } = {}
local throttleTexts: { [string]: boolean } = {}
local lastPurchaseFailureAt = -math.huge

local alertFrame: Frame? = nil
local alertLabel: TextLabel? = nil
local alertToken = 0

local offerFrame: Frame? = nil
local offerQueue: { OfferEntry } = {}
local offerShowing: OfferEntry? = nil
local offerToken = 0
local offersShown = 0
local lastOfferAt = -math.huge
local lastDeathOfferAt = -math.huge
local joinClock = os.clock()

---------------------------------------------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------------------------------------------

local function isTouch(): boolean
	return HudLayout.IsTouch()
end

local function laneTextSize(): number
	return if isTouch() then TOAST.TextSize else TOAST.TextSizeDesktop
end

local function laneMaxWidth(): number
	local w = HudLayout.TopStackMaxWidthV()
	if w ~= w or w <= 0 then
		return 600
	end
	return math.floor(w)
end

-- text box in v at `size` (wrapped to maxW); falls back to an estimate when TextService is unavailable
local function measure(text: string, size: number, font: Enum.Font, maxW: number): Vector2
	local ok, v = pcall(function(): Vector2
		return TextService:GetTextSize(text, size, font, Vector2.new(maxW, 10000))
	end)
	if ok and typeof(v) == "Vector2" and v.X > 0 then
		return v
	end
	local w = (utf8.len(text) or #text) * size * 0.55
	return Vector2.new(math.min(w, maxW), size * math.max(1, math.ceil(w / math.max(1, maxW))))
end

local function typeDef(notifType: string): { Color: Color3?, Hold: number?, Sound: boolean? }
	local t = (TOAST.Types :: any)[notifType]
	if type(t) ~= "table" or t.Color == nil then
		t = TOAST.Types.Info
	end
	return t
end

local function normType(notifType: any): string
	local t = if type(notifType) == "string" then notifType else "Info"
	if (TOAST.Types :: any)[t] == nil then
		return "Info"
	end
	return t
end

local function playSound(notifType: string)
	local def = typeDef(notifType)
	if def.Sound ~= true then
		return
	end
	local now = os.clock()
	if now - lastSoundAt < TOAST.SoundMinGap then
		return
	end
	lastSoundAt = now
	pcall(AudioController.PlayNotification)
end

-- first "$1,234" in a message → 1234 (nil when there is none)
local function parseAmount(message: string): number?
	local digits = string.match(message, "%$([%d,]+)")
	if not digits then
		return nil
	end
	local n = tonumber((string.gsub(digits, ",", "")))
	if n == nil or n ~= n or n <= 0 then
		return nil
	end
	-- "−$5,000" / "-$5,000" spends
	local before = string.match(message, "(.)%$[%d,]+")
	if before == "-" or string.find(message, "−%$" .. digits, 1, false) then
		return -n
	end
	return n
end

local function tween(inst: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local ok, tw = pcall(function()
		return TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	end)
	if ok and tw then
		tw:Play()
	end
end

---------------------------------------------------------------------------------------------------------------
-- lane
---------------------------------------------------------------------------------------------------------------

local function relayoutLane()
	local l = lane
	if not l then
		return
	end
	local maxW = laneMaxWidth()
	local total = 0
	local n = 0
	for _, line in ipairs(lines) do
		if line.Label.Parent == l then
			if n > 0 then
				total += TOAST.LineGap
			end
			total += line.Label.Size.Y.Offset
			n += 1
		end
	end
	l.Size = UDim2.fromOffset(maxW, total)
	l.Visible = n > 0
	-- the headless sim never fires AbsoluteSize changes; Roblox would, this keeps both exact
	HudLayout.RelayoutTopStack()
end

local function sizeLine(line: Line)
	local size = laneTextSize()
	local maxW = laneMaxWidth()
	local padX, padY = NotificationConfig.LinePadX, NotificationConfig.LinePadY
	local b = measure(line.Label.Text, size, FONT_DISPLAY, maxW - padX * 2)
	line.Label.TextSize = size
	line.Label.Size = UDim2.fromOffset(math.min(maxW, math.ceil(b.X) + padX * 2), math.ceil(b.Y) + padY * 2)
end

local function removeLine(line: Line, instant: boolean)
	if line.Dying and not instant then
		return
	end
	line.Dying = true
	line.Token += 1
	local idx = table.find(lines, line)
	if instant then
		if idx then
			table.remove(lines, idx)
		end
		line.Label:Destroy()
		relayoutLane()
		return
	end
	local my = line.Token
	tween(line.Label, TOAST.FadeOut, { TextTransparency = 1 })
	tween(line.Stroke, TOAST.FadeOut, { Transparency = 1 })
	task.delay(TOAST.FadeOut, function()
		if line.Token ~= my then
			return
		end
		local i = table.find(lines, line)
		if i then
			table.remove(lines, i)
		end
		line.Label:Destroy()
		relayoutLane()
	end)
end

local function arm(line: Line, hold: number)
	line.Token += 1
	local my = line.Token
	task.delay(hold, function()
		if line.Token == my and not line.Dying then
			removeLine(line, false)
		end
	end)
end

local function holdFor(notifType: string, duration: number?): number
	local base = typeDef(notifType).Hold or 2
	local want = if type(duration) == "number" and duration == duration then duration else base
	return math.clamp(want, NotificationConfig.MinHoldSeconds, math.max(base, NotificationConfig.MaxHoldSeconds))
end

local function coalesceKey(text: string, notifType: string): string
	if TOAST.CoalesceKey == "StripDigits" then
		return notifType .. "|" .. (string.gsub(text, "%d", ""))
	end
	return notifType .. "|" .. text
end

local function priorityOf(notifType: string): number
	return tonumber((NotificationConfig.Priority :: any)[notifType]) or 1
end

local function evictOne()
	-- lowest priority first, oldest among equals; lines already fading out go first of all
	local victim: Line? = nil
	for _, line in ipairs(lines) do
		if line.Dying then
			victim = line
			break
		end
		local v = victim
		if v == nil or priorityOf(line.Type) < priorityOf(v.Type) or (priorityOf(line.Type) == priorityOf(v.Type) and line.Seq < v.Seq) then
			victim = line
		end
	end
	if victim then
		removeLine(victim, true)
	end
end

local function laneShow(text: string, notifType: string, duration: number?)
	local l = lane
	if not l then
		return
	end
	local now = os.clock()
	local key = coalesceKey(text, notifType)
	local hold = holdFor(notifType, duration)

	-- coalesce: same key still on screen within the window → "Text ×N", timer restarts
	for _, line in ipairs(lines) do
		if not line.Dying and line.Key == key and now - line.UpdatedAt <= TOAST.CoalesceWindow then
			line.Count += 1
			line.UpdatedAt = now
			line.Text = text
			line.Label.Text = text .. string.format(NotificationConfig.CoalesceSuffix, line.Count)
			sizeLine(line)
			line.Pop.Scale = 1.08
			tween(line.Pop, 0.12, { Scale = 1 })
			relayoutLane()
			arm(line, hold)
			playSound(notifType)
			return
		end
	end

	while #lines >= TOAST.MaxVisible do
		evictOne()
	end

	local def = typeDef(notifType)
	lineSeq += 1
	local label = Instance.new("TextLabel")
	label.Name = "Line"
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Active = false
	label.Font = FONT_DISPLAY
	label.TextSize = laneTextSize()
	label.TextColor3 = def.Color or COLORS.Info
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Text = text
	label.LayoutOrder = lineSeq
	label.TextTransparency = 1
	local stroke = UIUtil.TextOutline(label, TOAST.StrokePx, COLORS.Ink, 1)
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Scale = TOAST.PopFrom
	pop.Parent = label

	local line: Line = {
		Label = label,
		Stroke = stroke,
		Pop = pop,
		Key = key,
		Type = notifType,
		Text = text,
		Count = 1,
		Seq = lineSeq,
		UpdatedAt = now,
		Token = 0,
		Dying = false,
	}
	sizeLine(line)
	label.Parent = l
	table.insert(lines, line)
	relayoutLane()

	tween(label, TOAST.FadeIn, { TextTransparency = 0 })
	tween(stroke, TOAST.FadeIn, { Transparency = 0 })
	tween(pop, 0.14, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	arm(line, hold)
	playSound(notifType)
end

---------------------------------------------------------------------------------------------------------------
-- alert slot ("BASE UNDER ATTACK!" — TopStack "BaseAlert", same order as the missile alert)
---------------------------------------------------------------------------------------------------------------

-- an Alert is up (BASE UNDER ATTACK here, INCOMING MISSILE in WE_MissileAlert): no Robux offer during an attack,
-- and the stack stays short enough to keep clear of the bottom-right reserve on phones
local function alertVisible(): boolean
	local f = alertFrame
	if f and f.Visible then
		return true
	end
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local missile = pg and pg:FindFirstChild("WE_MissileAlert")
	local banner = missile and missile:FindFirstChild("Banner")
	return banner ~= nil and banner:IsA("GuiObject") and banner.Visible and (missile :: ScreenGui).Enabled
end

--[[ Light the top-centre Alert slot for `seconds` with a red banner (Warn sound). ]]
function NotificationController.ShowAlert(text: string, seconds: number?)
	local f, lab = alertFrame, alertLabel
	if not (f and lab) then
		return
	end
	local size = if isTouch() then 22 else 24
	local b = measure(text, size, FONT_DISPLAY, laneMaxWidth() - 40)
	lab.TextSize = size
	lab.Text = text
	f.Size = UDim2.fromOffset(math.min(laneMaxWidth(), math.ceil(b.X) + 40), 44)
	f.Visible = true
	if offerFrame then
		HudLayout.RefreshVisibility(offerFrame)
	end
	HudLayout.RelayoutTopStack()
	playSound("Warn")
	alertToken += 1
	local my = alertToken
	task.delay(seconds or 4, function()
		if alertToken == my and f.Parent then
			f.Visible = false
			if offerFrame then
				HudLayout.RefreshVisibility(offerFrame)
			end
			HudLayout.RelayoutTopStack()
		end
	end)
end

---------------------------------------------------------------------------------------------------------------
-- routing
---------------------------------------------------------------------------------------------------------------

local function isPurchaseFailureText(text: string): boolean
	for _, pat in ipairs(NotificationConfig.PurchaseFailure.Patterns) do
		if string.find(text, pat) then
			return true
		end
	end
	return false
end

-- true = the line may show (and stamps the window); false = an echo of a failure already on screen
local function passPurchaseFailureGate(): boolean
	local now = os.clock()
	if now - lastPurchaseFailureAt < NotificationConfig.PurchaseFailure.WindowSeconds then
		return false
	end
	lastPurchaseFailureAt = now
	return true
end

local function dropped(text: string, fromServer: boolean): boolean
	for _, pat in ipairs(TOAST.Drop) do
		if string.find(text, pat) then
			if fromServer or not table.find(NotificationConfig.LocalExemptDrop, pat) then
				return true
			end
		end
	end
	return false
end

local function throttled(text: string): boolean
	local now = os.clock()
	for i, rule in ipairs(NotificationConfig.Throttle) do
		if string.find(text, rule.Match) then
			if rule.OncePerText then
				if throttleTexts[text] then
					return true
				end
				throttleTexts[text] = true
			end
			local gap = rule.MinGapSeconds
			if gap then
				if now - (throttleAt[i] or -math.huge) < gap then
					return true
				end
				throttleAt[i] = now
			end
			return false
		end
	end
	return false
end

-- returns (handled, text, type): handled = a Reroute rule took the message (floats / alert done here)
local function reroute(text: string, notifType: string, amount: number?): (boolean, string?, string)
	local now = os.clock()
	for i, rule in ipairs(TOAST.Reroute) do
		if string.find(text, rule.Match) then
			local gap = rule.MinGapSeconds
			if gap and now - (rerouteAt[i] or -math.huge) < gap then
				return true, nil, notifType
			end
			rerouteAt[i] = now
			if rule.Float then
				local amt = amount or parseAmount(text)
				if amt then
					HudLayout.CashFloat(amt)
				end
			end
			local show: string? = nil
			if rule.Show == "%STRIP%" then
				show = if rule.Strip then (string.gsub(text, rule.Strip, "")) else text
			elseif rule.Show and rule.Show ~= "" then
				show = rule.Show
			end
			local t = normType(rule.Type or notifType)
			local alertSecs = rule.AlertSeconds
			if show and alertSecs and alertSecs > 0 and alertFrame then
				NotificationController.ShowAlert(show, alertSecs)
				return true, nil, t -- the Alert slot IS the warning (no duplicate lane line)
			end
			return true, show, t
		end
	end
	return false, text, notifType
end

local function route(message: any, notifType: any, duration: any, amount: any, fromServer: boolean, isPurchaseFailure: boolean?): boolean
	local text = if type(message) == "string" then message else tostring(message or "")
	if text == "" then
		return false
	end
	local t = if type(notifType) == "string" then notifType else "Info"
	local dur: number? = if type(duration) == "number" then duration else nil
	local amt: number? = if type(amount) == "number" and amount == amount then amount else nil

	-- 1. rewrite
	for _, rule in ipairs(NotificationConfig.Rewrite) do
		if string.find(text, rule.Match) then
			if rule.Replace then
				text = (string.gsub(text, rule.Match, rule.Replace, 1))
			end
			if rule.Type then
				t = rule.Type
			end
			break
		end
	end

	-- the Alert banner already says it (strike results under the INCOMING MISSILE banner)
	if fromServer and alertVisible() then
		for _, pat in ipairs(NotificationConfig.AlertEcho) do
			if string.find(text, pat) then
				return false
			end
		end
	end

	-- Collect: never a lane line (spec §3.3 source rule) → "+$N" at the pill
	if t == "Collect" then
		local a = amt or parseAmount(text)
		if a then
			HudLayout.CashFloat(a)
		end
		return false
	end

	-- 2. reroute (today's server lines)
	local handled, show, rt = reroute(text, t, amt)
	if handled then
		if not show then
			return false
		end
		text, t = show, rt
	end

	-- 3. drop
	if dropped(text, fromServer) then
		return false
	end

	-- 4. throttle
	if throttled(text) then
		return false
	end

	-- 5. one failed purchase = one line
	if TOAST.DedupePurchaseFailure and (isPurchaseFailure or isPurchaseFailureText(text)) then
		if not passPurchaseFailureGate() then
			return false
		end
	end

	laneShow(text, normType(t), dur)
	return true
end

---------------------------------------------------------------------------------------------------------------
-- offer toast
---------------------------------------------------------------------------------------------------------------

local offerTitle: TextLabel? = nil
local offerSub: TextLabel? = nil
local offerGet: TextButton? = nil
local offerGetFace: Frame? = nil
local offerGetLabel: TextLabel? = nil
local offerClose: TextButton? = nil
local offerIcon: Frame? = nil

local function offerDeferred(): boolean
	local rule = { HideWhen = table.clone(OFFER.DeferWhen) }
	table.insert(rule.HideWhen, "Dead")
	return not HudLayout.EvalRule(rule) or alertVisible()
end

local function touchMinV(): number
	local s = HudLayout.Scale()
	if s <= 0 then
		return 64
	end
	return math.ceil(HudConfig.Scale.TouchMinPx / s)
end

local function layoutOffer(def: OfferDef)
	local f = offerFrame
	local title, sub, get, face, getLab, close, icon = offerTitle, offerSub, offerGet, offerGetFace, offerGetLabel, offerClose, offerIcon
	if not (f and title and sub and get and face and getLab and close and icon) then
		return
	end
	local touch = isTouch()
	local h = if touch then OFFER.Height else OFFER.HeightDesktop
	local padL, padR, gap = 10, 6, 10
	local iconSize = NotificationConfig.Offer.IconSize
	local maxW = math.min(OFFER.MaxWidth + (if touch then NotificationConfig.Offer.TouchExtraWidth else 0), laneMaxWidth())

	title.Text = def.Title
	sub.Text = def.Sub or ""
	sub.Visible = def.Sub ~= nil and def.Sub ~= ""
	getLab.Text = if def.Cta ~= "" then def.Cta else NotificationConfig.Offer.GetText

	local ctaB = measure(getLab.Text, 18, FONT_DISPLAY, 400)
	local faceW = math.ceil(ctaB.X) + 28
	local hitH = if touch then math.max(OFFER.GetHit, touchMinV()) else h
	local closeW = if touch then math.max(OFFER.CloseHit, touchMinV()) else OFFER.CloseHit
	local closeH = if touch then math.max(OFFER.CloseHit, touchMinV()) else h

	local fixed = padL + iconSize.X + gap + gap + faceW + 4 + closeW + padR
	local textMax = math.max(60, maxW - fixed)
	local tb = measure(def.Title, OFFER.TitleSize, FONT_DISPLAY, textMax)
	local sb = if sub.Visible then measure(sub.Text, OFFER.SubSize, FONT_BODY, textMax) else Vector2.zero
	-- 8 % slack: GetTextSize measures the glyphs, the UIStroke outline and font fallbacks draw a little wider
	local textW = math.min(textMax, math.ceil(math.max(tb.X, sb.X) * 1.08))
	local w = math.min(maxW, fixed + textW)

	f.Size = UDim2.fromOffset(w, h)
	icon.Position = UDim2.new(0, padL, 0.5, 0)
	local textX = padL + iconSize.X + gap
	local titleH = OFFER.TitleSize + 2
	local subH = OFFER.SubSize + 2
	if sub.Visible then
		local top = math.floor((h - titleH - subH) / 2)
		title.Position = UDim2.fromOffset(textX, top)
		sub.Position = UDim2.fromOffset(textX, top + titleH)
	else
		title.Position = UDim2.fromOffset(textX, math.floor((h - titleH) / 2))
	end
	title.Size = UDim2.fromOffset(textW, titleH)
	sub.Size = UDim2.fromOffset(textW, subH)

	get.Size = UDim2.fromOffset(faceW, hitH)
	get.Position = UDim2.new(0, textX + textW + gap, 0.5, 0)
	face.Size = UDim2.new(1, 0, 0, h - 12)
	close.Size = UDim2.fromOffset(closeW, closeH)
	close.Position = UDim2.new(1, 0, 0.5, 0)
end

local function hideOffer()
	offerShowing = nil
	offerToken += 1
	local f = offerFrame
	if f then
		HudLayout.RefreshVisibility(f)
		HudLayout.RelayoutTopStack()
	end
end

local function presentOffer(entry: OfferEntry)
	local now = os.clock()
	offerShowing = entry
	offersShown += 1
	lastOfferAt = now
	if entry.Death then
		lastDeathOfferAt = now
	end
	layoutOffer(entry.Def)
	local f = offerFrame
	if f then
		HudLayout.RefreshVisibility(f)
		HudLayout.RelayoutTopStack()
		local pop = f:FindFirstChild("Pop")
		if pop and pop:IsA("UIScale") then
			pop.Scale = TOAST.PopFrom
			tween(pop, 0.16, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end
	end
	playSound("Reward")
	offerToken += 1
	local my = offerToken
	task.delay(OFFER.HoldSeconds, function()
		if offerToken == my and offerShowing == entry then
			hideOffer()
		end
	end)
end

-- the time-based throttle (session cap, gap, death gap); nil = allowed, else the reason
local function offerBlockedReason(entry: OfferEntry, now: number): string?
	if offersShown >= OFFER.MaxPerSession then
		return "SessionCap"
	end
	if now - lastOfferAt < OFFER.MinGapSeconds then
		return "MinGap"
	end
	if entry.Death and now - lastDeathOfferAt < OFFER.DeathOfferMinGapSeconds then
		return "DeathGap"
	end
	return nil
end

local function pumpOffers()
	local now = os.clock()
	-- expire: a deferred offer that never found a calm moment → dropped, Shop badge "!" (spec §4.3)
	local i = 1
	while i <= #offerQueue do
		local e = offerQueue[i]
		if now > e.EligibleAt + OFFER.DropAfterQueuedSeconds then
			table.remove(offerQueue, i)
			if OFFER.ShopBadgeWhenDropped and offerBlockedReason(e, now) == nil then
				HudLayout.SetBadge("Shop", "!")
			end
		else
			i += 1
		end
	end
	local of = offerFrame
	if of and offerShowing then
		local before = of.Visible
		HudLayout.RefreshVisibility(of)
		if of.Visible ~= before then
			HudLayout.RelayoutTopStack()
		end
	end
	if offerShowing or #offerQueue == 0 or offerDeferred() then
		return
	end
	local j = 1
	while j <= #offerQueue do
		local e = offerQueue[j]
		if e.EligibleAt <= now then
			local why = offerBlockedReason(e, now)
			table.remove(offerQueue, j)
			if why == nil then
				presentOffer(e)
				return
			end
			-- throttled while it waited (another offer won the slot): silently gone
		else
			j += 1
		end
	end
end

--[[
	Show one Robux offer toast: def = {Key, Title, Sub?, Cta, OnGet}. OnGet runs the caller's own
	promptDevProduct / promptGamePass (the purchase stays server-verified). Returns true when the offer is
	showing or queued for a calm moment, false when the throttle refused it (session cap, gap, death gap).
]]
function NotificationController.ShowOffer(def: OfferDef): boolean
	if type(def) ~= "table" or type(def.Key) ~= "string" or type(def.Title) ~= "string" or type(def.OnGet) ~= "function" then
		warn("[NotificationController] ShowOffer: bad def")
		return false
	end
	local cur = offerShowing
	if cur and cur.Def.Key == def.Key then
		return true
	end
	for _, e in ipairs(offerQueue) do
		if e.Def.Key == def.Key then
			e.Def = def -- newest copy wins (price / text refresh)
			return true
		end
	end
	local now = os.clock()
	local entry: OfferEntry = {
		Def = def,
		Death = string.find(def.Key, NotificationConfig.Offer.DeathKeyPattern) ~= nil,
		EligibleAt = math.max(now, joinClock + OFFER.FirstAfterJoinSeconds),
		QueuedAt = now,
	}
	if offerBlockedReason(entry, now) ~= nil then
		return false
	end
	if not offerFrame then
		return false
	end
	if entry.EligibleAt <= now and not offerShowing and not offerDeferred() then
		presentOffer(entry)
		return true
	end
	if cur then
		return false -- one at a time; a second offer inside the gap would be refused anyway
	end
	while #offerQueue >= NotificationConfig.Offer.QueueMax do
		table.remove(offerQueue, 1)
	end
	table.insert(offerQueue, entry)
	return true
end

function NotificationController.IsOfferShowing(): boolean
	return offerShowing ~= nil
end

---------------------------------------------------------------------------------------------------------------
-- build
---------------------------------------------------------------------------------------------------------------

local function buildOffer(screen: ScreenGui)
	local touch = isTouch()
	local h = if touch then OFFER.Height else OFFER.HeightDesktop
	local f = Instance.new("Frame")
	f.Name = "Offer"
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.Position = UDim2.new(0.5, 0, 0, 0)
	f.Size = UDim2.fromOffset(300, h)
	f.BackgroundColor3 = OFFER.Bg
	f.BackgroundTransparency = OFFER.BgTransparency
	f.BorderSizePixel = 0
	f.Active = false
	f.Visible = false
	f.ZIndex = 5
	f.Parent = screen
	UIUtil.Corner(f, 14)
	local stroke = UIUtil.Stroke(f, OFFER.Stroke, 2)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = f

	local iconSize = NotificationConfig.Offer.IconSize
	local icon = HudIcons.Make("Cash", f, {
		Name = "Icon",
		Size = UDim2.fromOffset(iconSize.X, iconSize.Y),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		ZIndex = 6,
		Fill = OFFER.Bg,
	})

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Font = FONT_DISPLAY
	title.TextSize = OFFER.TitleSize
	title.TextColor3 = COLORS.Gold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.ZIndex = 6
	title.Parent = f
	UIUtil.TextOutline(title, 1.4)

	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.BackgroundTransparency = 1
	sub.Font = FONT_BODY
	sub.TextSize = OFFER.SubSize
	sub.TextColor3 = COLORS.White
	sub.TextTransparency = 0.25
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextTruncate = Enum.TextTruncate.AtEnd
	sub.ZIndex = 6
	sub.Parent = f

	-- GET: transparent ≥ 44 px hit area around a green face (spec: 64 v hit)
	local get = Instance.new("TextButton")
	get.Name = "Get"
	get.AnchorPoint = Vector2.new(0, 0.5)
	get.BackgroundTransparency = 1
	get.Text = ""
	get.AutoButtonColor = false
	get.Active = true
	get.Selectable = true
	get.ZIndex = 7
	get.Parent = f
	local face = Instance.new("Frame")
	face.Name = "Face"
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.fromScale(0.5, 0.5)
	face.BackgroundColor3 = COLORS.PlusGreen
	face.BorderSizePixel = 0
	face.Active = false
	face.ZIndex = 7
	face.Parent = get
	UIUtil.Corner(face, 10)
	local faceStroke = UIUtil.Stroke(face, COLORS.PlusGreenStroke, 2)
	faceStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local getLab = Instance.new("TextLabel")
	getLab.Name = "Cta"
	getLab.BackgroundTransparency = 1
	getLab.Size = UDim2.fromScale(1, 1)
	getLab.Font = FONT_DISPLAY
	getLab.TextSize = 18
	getLab.TextColor3 = COLORS.White
	getLab.ZIndex = 8
	getLab.Parent = face
	UIUtil.TextOutline(getLab, 1.2)

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.BackgroundTransparency = 1
	close.Font = FONT_BODY
	close.TextSize = 16
	close.TextColor3 = COLORS.White
	close.TextTransparency = 0.4
	close.Text = NotificationConfig.Offer.CloseText
	close.AutoButtonColor = false
	close.Active = true
	close.Selectable = true
	close.ZIndex = 7
	close.Parent = f

	get.Activated:Connect(function()
		local cur = offerShowing
		hideOffer()
		if cur then
			pcall(AudioController.PlayClick)
			local onGet = cur.Def.OnGet
			local ok, err = pcall(function(): string?
				onGet()
				return nil
			end)
			if not ok then
				warn("[NotificationController] offer OnGet failed:", cur.Def.Key, err)
			end
		end
	end)
	close.Activated:Connect(function()
		hideOffer()
	end)

	offerFrame = f
	offerTitle, offerSub, offerGet, offerGetFace, offerGetLabel, offerClose, offerIcon = title, sub, get, face, getLab, close, icon
	HudLayout.BindVisibility(f, { HideWhen = { "Modal", "Driving", "Dead" } }, function(): boolean
		return offerShowing ~= nil and not alertVisible()
	end)
	HudLayout.RegisterTopStack("Offer", f, HudConfig.TopStack.Order.Offer, { Space = "Hud" })
end

local function buildAlert(screen: ScreenGui)
	local f = Instance.new("Frame")
	f.Name = "BaseAlert"
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.Position = UDim2.new(0.5, 0, 0, 0)
	f.Size = UDim2.fromOffset(320, 44)
	f.BackgroundColor3 = Color3.fromRGB(128, 18, 16)
	f.BackgroundTransparency = 0.05
	f.BorderSizePixel = 0
	f.Active = false
	f.Visible = false
	f.Parent = screen
	UIUtil.Corner(f, 10)
	local stroke = UIUtil.Stroke(f, Color3.fromRGB(255, 120, 100), 2)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local lab = Instance.new("TextLabel")
	lab.Name = "Text"
	lab.BackgroundTransparency = 1
	lab.Size = UDim2.fromScale(1, 1)
	lab.Font = FONT_DISPLAY
	lab.TextSize = 22
	lab.TextColor3 = COLORS.White
	lab.Text = ""
	lab.Parent = f
	UIUtil.TextOutline(lab, 1.4)
	alertFrame = f
	alertLabel = lab
	-- same order as the missile alert (MissileController registers "Alert"); ties keep registration order
	HudLayout.RegisterTopStack("BaseAlert", f, HudConfig.TopStack.Order.Alert, { Space = "Hud" })
end

function NotificationController.Init()
	if gui and gui.Parent then
		return
	end
	local pg = player:WaitForChild("PlayerGui")
	local old = pg:FindFirstChild("WarEmpireNotifications")
	if old then
		old:Destroy()
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireNotifications"
	screen.DisplayOrder = HudConfig.DisplayOrder.WarEmpireNotifications -- above modal panels (60)
	HudLayout.ApplyScreen(screen, { Insets = "Core" })
	screen.Parent = pg
	gui = screen

	local l = Instance.new("Frame")
	l.Name = "Lane"
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = UDim2.new(0.5, 0, 0, HudConfig.TopStack.Top)
	l.Size = UDim2.fromOffset(laneMaxWidth(), 0)
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.Active = false -- never block HUD / world clicks
	l.Visible = false
	l.Parent = screen
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, TOAST.LineGap)
	list.Parent = l
	lane = l
	laneList = list
	HudLayout.RegisterTopStack("Toasts", l, HudConfig.TopStack.Order.Toasts, { Space = "Hud" })

	buildAlert(screen)
	buildOffer(screen)

	-- viewport / touch changes: re-measure the lines (text size and lane width follow the device)
	HudLayout.LayoutChanged:Connect(function()
		for _, line in ipairs(lines) do
			sizeLine(line)
		end
		relayoutLane()
		local cur = offerShowing
		if cur then
			layoutOffer(cur.Def)
		end
	end)
	HudLayout.FlagChanged:Connect(function(_name: string, _on: boolean)
		pumpOffers()
	end)
	task.spawn(function()
		while screen.Parent do
			task.wait(NotificationConfig.Offer.TickSeconds)
			pumpOffers()
		end
	end)

	-- v60: never block Init on the Notification remote
	Remotes.BindEvent(Constants.RemoteNames.Notification, function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		route(payload.Message, payload.Type, payload.Duration, payload.Amount, true)
	end)
end

--[[ Local toast (unchanged signature). Type "Collect" → cash float. Returns nothing (legacy callers pcall it). ]]
function NotificationController.Show(message: string, notifType: string, duration: number?)
	route(message, notifType, duration, nil, false)
end

--[[ A failed purchase line (WorldPromptController / BaseController): one line per failure — the other client
	path and the server's Warn echo inside NotificationConfig.PurchaseFailure.WindowSeconds are skipped.
	Returns true when it showed. ]]
function NotificationController.ShowPurchaseFailure(message: string, notifType: string?, duration: number?): boolean
	return route(message, notifType or "Warn", duration, nil, false, true)
end

--[[ Test / QA helper: the lane's current texts, top to bottom. ]]
function NotificationController.GetLaneTexts(): { string }
	local out = {}
	local sorted = table.clone(lines)
	table.sort(sorted, function(a: Line, b: Line): boolean
		return a.Seq < b.Seq
	end)
	for _, line in ipairs(sorted) do
		if not line.Dying then
			table.insert(out, line.Label.Text)
		end
	end
	return out
end

-- keep the marker referenced (strict mode: no unused-local noise)
local _ = HIGH_CONTRAST_SUCCESS
local _list = laneList

return NotificationController
