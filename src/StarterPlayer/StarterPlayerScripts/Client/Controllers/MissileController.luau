--!strict
--[[
	v69 MISSILE COMMAND (client): the Command Center strike panel + the missile FX every client draws.

	Panel (WE_MissilePanel): opened by the Missile Command terminal inside the Command Center (UIController
	routes the prompt attribute WE_OpenPanel = "Missiles" to MissileController.Open). One row per enemy base
	on the server with the server's verdict (CanStrike / ReasonText), a live status line and a two-tap STRIKE
	button (STRIKE → CONFIRM within 3 s → RequestMissileStrike { Action = "Launch", TargetUserId }).
	Everything shown arrives in MissileStrikeStateUpdate; this file never requires RaidConfig. Countdowns tick
	locally from the seconds in the last payload: remaining = max(0, secs − (os.clock() − receivedAt)).
	The panel opens instantly in a loading state and never waits on the server.

	FX (always on): every MissileStrikeFx launch is drawn as a missile on a quadratic bezier arc from the
	attacker's Missile Defense battery to the target's gate, with an interceptor + mid-air burst when the
	outcome is Intercepted. The victim gets a siren, a pulsing red screen edge and an INCOMING banner; the
	attacker a small banner (hidden while this panel is open — the panel shows the same thing).

	Server-authoritative: the server re-checks unlock, cooldown, cash, distance to the Command Center and the
	target's shields, and charges the cost. The only remote sent from here is RequestMissileStrike.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)
local BaseConfig = require(Shared.Configs.BaseConfig)
local ClientSettings = require(script.Parent.Parent.Modules.ClientSettings)
local AudioController = require(script.Parent.Parent.Modules.AudioController)

local MissileController = {}

local player = Players.LocalPlayer
local isTouch = UserInputService.TouchEnabled

-- ── Layout (px) ─────────────────────────────────────────────────────────────
local PANEL_MAX_W, PANEL_MAX_H = 640, 340
local HEADER_H = 44
local STATUS_LINE_H = 28
local ROW_H = 60
local ROW_REASON_H = 20
local BTN_W, BTN_H = 112, 44
local SMALL_TEXT = if isTouch then 14 else 13 -- touch fonts never go below 14
local CHIP_TEXT = if isTouch then 14 else 13

-- ── Timing ──────────────────────────────────────────────────────────────────
local CONFIRM_SECONDS = 3
local REFRESH_SECONDS = 5
local RESULT_SECONDS = 3
local RESULT_REFRESH_DELAY = 0.5
local MIN_REQUEST_GAP = 0.75 -- client-side courtesy throttle for State requests
local LAUNCH_PENDING_SECONDS = 4 -- STRIKE buttons wait this long for the server's answer

-- ── FX ──────────────────────────────────────────────────────────────────────
local FX_CULL_STUDS = 2000
local FX_MAX_ACTIVE = 3
local FX_LATE_SECONDS = 3 -- skip a launch we hear about later than impact + this
local SHAKE_STUDS = 200
local INTERCEPTOR_SECONDS = 1.2
local ALERT_HOLD_SECONDS = 3
local EXPLOSION_RADIUS = 18
local SIREN_ID = "rbxasset://sounds/electronicpingshort.wav"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local C = {
	Panel = Color3.fromRGB(22, 26, 31),
	Header = Color3.fromRGB(64, 38, 34),
	Row = Color3.fromRGB(36, 41, 48),
	RowLocked = Color3.fromRGB(29, 32, 37),
	Chip = Color3.fromRGB(52, 59, 68),
	Text = Constants.Colors.Text,
	Muted = Constants.Colors.Muted,
	Red = Color3.fromRGB(196, 52, 44),
	RedDark = Color3.fromRGB(110, 20, 18),
	Orange = Color3.fromRGB(232, 122, 36),
	Amber = Color3.fromRGB(236, 176, 64),
	Green = Color3.fromRGB(64, 170, 96),
	Blue = Color3.fromRGB(64, 128, 196),
	Grey = Color3.fromRGB(62, 68, 76),
	Dim = Color3.fromRGB(88, 52, 50),
	Stroke = Color3.fromRGB(120, 60, 52),
}

-- Reasons that concern the attacker (not the target). The status line explains them, so rows don't repeat them.
local ATTACKER_REASONS: { [string]: boolean } = {
	Disabled = true,
	Loading = true,
	NoBase = true,
	Locked = true,
	Cooldown = true,
	InFlight = true,
	Busy = true,
}

-- ── Payload types (mirrors MissileStrikeService; spec §6.3) ─────────────────
type Requirement = { StructureId: string, DisplayName: string, Need: number, Have: number }

type Target = {
	UserId: number,
	Name: string,
	BaseName: string,
	PlotId: number,
	Distance: number,
	FlightSeconds: number,
	WallsLevel: number,
	HasAutoGuns: boolean,
	MissileDefenseLevel: number,
	InterceptChance: number,
	ShieldRemaining: number,
	DefensesDownRemaining: number,
	RebootRemaining: number,
	Incoming: boolean,
	CanStrike: boolean,
	Reason: string?,
	ReasonText: string?,
	ReasonSecs: number?, -- the m:ss inside ReasonText, so it can count down between refreshes
}

type StrikeResult = {
	Kind: string,
	TargetName: string?,
	Reason: string?,
	Text: string,
	DownSeconds: number?,
	ImpactIn: number?,
}

type InFlightInfo = { TargetUserId: number, TargetName: string, ImpactIn: number }

type State = {
	Unlocked: boolean,
	LockedText: string?,
	Requirements: { Requirement },
	Cost: number,
	Cash: number,
	CooldownRemaining: number,
	CooldownTotal: number,
	AtCommandCenter: boolean,
	InFlight: InFlightInfo?,
	Targets: { Target },
	Result: StrikeResult?,
}

type ChipSpec = { Text: string, Short: string?, Bg: Color3, Fg: Color3, Keep: boolean? }

type Row = {
	UserId: number,
	Frame: Frame,
	NameLabel: TextLabel,
	SubLabel: TextLabel,
	Chips: Frame,
	ChipPool: { TextLabel },
	ChipKey: string,
	Button: TextButton,
	ReasonLabel: TextLabel,
	Target: Target,
}

type Ui = {
	Screen: ScreenGui,
	Panel: Frame,
	Title: TextLabel,
	ResultFrame: Frame,
	ResultLabel: TextLabel,
	Status: Frame,
	StatusLabel: TextLabel,
	ReqHolder: Frame,
	ReqPool: { TextLabel },
	List: ScrollingFrame,
	Empty: TextLabel,
}

-- ── Module state ────────────────────────────────────────────────────────────
local ui: Ui? = nil
local isOpen = false
local state: State? = nil
local stateAt = 0 -- os.clock() when `state` arrived
local rows: { [number]: Row } = {}
local panelW, panelH = PANEL_MAX_W, PANEL_MAX_H
local statusH = STATUS_LINE_H
local confirmUserId: number? = nil
local confirmUntil = 0
local launchPendingUntil = 0
local pendingTargetUserId: number? = nil
local bannerToken = 0
local lastStateReqAt = -math.huge
local stateReqQueued = false
local baseUpgrades: { [string]: number } = {} -- own structure levels from BaseStateUpdate (prerequisite hints)
local initDone = false

-- ── Small helpers ───────────────────────────────────────────────────────────
local function num(v: any, default: number): number
	local n = tonumber(v)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return default
	end
	return n
end

local function str(v: any): string?
	if typeof(v) == "string" and v ~= "" then
		return v
	end
	return nil
end

local function commas(n: number): string
	local s = tostring(math.floor(math.abs(n)))
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return (if n < 0 then "-" else "") .. out
end

local function mmss(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- seconds left of a countdown that read `secs` when the last state arrived
local function live(secs: number): number
	return math.max(0, secs - (os.clock() - stateAt))
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function textWidth(text: string, size: number): number
	local ok, v = pcall(function()
		return TextService:GetTextSize(text, size, Enum.Font.GothamBold, Vector2.new(2000, 200))
	end)
	if ok and typeof(v) == "Vector2" then
		return math.ceil(v.X)
	end
	return math.ceil((utf8.len(text) or #text) * size * 0.62)
end

local function topInset(): number
	local y = 36
	pcall(function()
		local tl = GuiService:GetGuiInset()
		y = tl.Y
	end)
	return y
end

local function getPlayerGui(): PlayerGui?
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg then
		return pg
	end
	local waited = player:WaitForChild("PlayerGui", 5)
	if waited and waited:IsA("PlayerGui") then
		return waited
	end
	return nil
end

-- the ScreenGui area (IgnoreGuiInset = false → below the topbar)
local function guiArea(): (number, number)
	local u = ui
	if u then
		local abs: any = u.Screen.AbsoluteSize
		if typeof(abs) == "Vector2" and abs.X > 0 and abs.Y > 0 then
			return abs.X, abs.Y
		end
	end
	local cam = workspace.CurrentCamera
	if cam then
		local vp: any = cam.ViewportSize
		if typeof(vp) == "Vector2" and vp.X > 0 and vp.Y > 0 then
			return vp.X, math.max(0, vp.Y - topInset())
		end
	end
	return 844, 354
end

local function newLabel(parent: Instance, name: string, font: Enum.Font, size: number, color: Color3): TextLabel
	local lab = Instance.new("TextLabel")
	lab.Name = name
	lab.BackgroundTransparency = 1
	lab.BorderSizePixel = 0
	lab.Font = font
	lab.TextSize = size
	lab.TextColor3 = color
	lab.TextXAlignment = Enum.TextXAlignment.Left
	lab.TextYAlignment = Enum.TextYAlignment.Center
	lab.TextTruncate = Enum.TextTruncate.AtEnd
	lab.Text = ""
	lab.Parent = parent
	return lab
end

-- ── Payload parsing (never trust shapes) ────────────────────────────────────
local function parseTarget(t: any): Target?
	if typeof(t) ~= "table" then
		return nil
	end
	local uid = tonumber(t.UserId)
	if uid == nil then
		return nil
	end
	local name = str(t.Name) or ("Player " .. tostring(uid))
	local reasonText = str(t.ReasonText)
	local reasonSecs: number? = nil
	if reasonText then
		local m, s = string.match(reasonText, "(%d+):(%d%d)")
		if m and s then
			reasonSecs = (tonumber(m) or 0) * 60 + (tonumber(s) or 0)
		end
	end
	return {
		UserId = uid,
		Name = name,
		BaseName = str(t.BaseName) or (name .. "'s Base"),
		PlotId = math.floor(num(t.PlotId, 0)),
		Distance = math.max(0, num(t.Distance, 0)),
		FlightSeconds = math.max(0, num(t.FlightSeconds, 0)),
		WallsLevel = math.max(0, math.floor(num(t.WallsLevel, 0))),
		HasAutoGuns = t.HasAutoGuns == true,
		MissileDefenseLevel = math.max(0, math.floor(num(t.MissileDefenseLevel, 0))),
		InterceptChance = math.clamp(num(t.InterceptChance, 0), 0, 1),
		ShieldRemaining = math.max(0, num(t.ShieldRemaining, 0)),
		DefensesDownRemaining = math.max(0, num(t.DefensesDownRemaining, 0)),
		RebootRemaining = math.max(0, num(t.RebootRemaining, 0)),
		Incoming = t.Incoming == true,
		CanStrike = t.CanStrike == true,
		Reason = str(t.Reason),
		ReasonText = reasonText,
		ReasonSecs = reasonSecs,
	}
end

local function parseResult(r: any): StrikeResult?
	if typeof(r) ~= "table" then
		return nil
	end
	local kind = str(r.Kind) or "Refused"
	return {
		Kind = kind,
		TargetName = str(r.TargetName),
		Reason = str(r.Reason),
		Text = str(r.Text) or kind,
		DownSeconds = tonumber(r.DownSeconds),
		ImpactIn = tonumber(r.ImpactIn),
	}
end

local function parseState(p: any): State?
	if typeof(p) ~= "table" then
		return nil
	end
	local reqs: { Requirement } = {}
	if typeof(p.Requirements) == "table" then
		for _, r in ipairs(p.Requirements) do
			if typeof(r) == "table" then
				local sid = str(r.StructureId) or "?"
				table.insert(reqs, {
					StructureId = sid,
					DisplayName = str(r.DisplayName) or sid,
					Need = math.floor(num(r.Need, 0)),
					Have = math.floor(num(r.Have, 0)),
				})
			end
		end
	end
	local targets: { Target } = {}
	if typeof(p.Targets) == "table" then
		for _, t in ipairs(p.Targets) do
			local parsed = parseTarget(t)
			if parsed and parsed.UserId ~= player.UserId then
				table.insert(targets, parsed)
			end
		end
	end
	local inFlight: InFlightInfo? = nil
	if typeof(p.InFlight) == "table" then
		inFlight = {
			TargetUserId = math.floor(num(p.InFlight.TargetUserId, 0)),
			TargetName = str(p.InFlight.TargetName) or "target",
			ImpactIn = math.max(0, num(p.InFlight.ImpactIn, 0)),
		}
	end
	return {
		Unlocked = p.Unlocked == true,
		LockedText = str(p.LockedText),
		Requirements = reqs,
		Cost = math.max(0, num(p.Cost, 0)),
		Cash = math.max(0, num(p.Cash, 0)),
		CooldownRemaining = math.max(0, num(p.CooldownRemaining, 0)),
		CooldownTotal = math.max(0, num(p.CooldownTotal, 0)),
		AtCommandCenter = p.AtCommandCenter ~= false,
		InFlight = inFlight,
		Targets = targets,
		Result = parseResult(p.Result),
	}
end

-- ── Chips (manual flow layout so the panel never depends on engine wrapping) ─
local function poolChip(holder: Frame, pool: { TextLabel }, i: number): TextLabel
	local existing: TextLabel? = pool[i]
	if existing then
		return existing
	end
	local created = newLabel(holder, "Chip", Enum.Font.GothamBold, CHIP_TEXT, C.Text)
	created.BackgroundTransparency = 0
	created.TextXAlignment = Enum.TextXAlignment.Center
	UIUtil.Corner(created, 5)
	pool[i] = created
	return created
end

local CHIP_GAP, CHIP_LINE_GAP = 5, 4

local function chipLines(widths: { number }, maxW: number): number
	local x, lines = 0, 0
	for _, w in ipairs(widths) do
		if lines == 0 then
			lines = 1
		elseif x > 0 and x + w > maxW then
			lines += 1
			x = 0
		end
		x += w + CHIP_GAP
	end
	return lines
end

-- Places `specs` left→right, wrapping at maxW, at most maxLines lines; returns the lines used. When the full
-- texts need more lines, chips switch to their Short text; if that still overflows, Keep chips go first so
-- only the least important chips can drop.
local function flowChips(holder: Frame, pool: { TextLabel }, specs: { ChipSpec }, maxW: number, chipH: number, maxLines: number): number
	local order: { ChipSpec } = table.clone(specs)
	local texts: { string } = {}
	local widths: { number } = {}
	local function measure()
		for i = 1, #order do
			widths[i] = math.min(maxW, textWidth(texts[i], CHIP_TEXT) + 14)
		end
	end
	for i, spec in ipairs(order) do
		texts[i] = spec.Text
	end
	measure()
	if chipLines(widths, maxW) > maxLines then
		for i, spec in ipairs(order) do
			texts[i] = spec.Short or spec.Text
		end
		measure()
		if chipLines(widths, maxW) > maxLines then
			local kept: { ChipSpec } = {}
			local rest: { ChipSpec } = {}
			for _, spec in ipairs(order) do
				table.insert(if spec.Keep then kept else rest, spec)
			end
			order = kept
			for _, spec in ipairs(rest) do
				table.insert(order, spec)
			end
			for i, spec in ipairs(order) do
				texts[i] = spec.Short or spec.Text
			end
			measure()
		end
	end
	local x, line, lines = 0, 0, 0
	for i, spec in ipairs(order) do
		local lab = poolChip(holder, pool, i)
		local w = widths[i]
		if x > 0 and x + w > maxW then
			line += 1
			x = 0
		end
		if line >= maxLines then
			lab.Visible = false
		else
			lab.Visible = true
			lab.Text = texts[i]
			lab.BackgroundColor3 = spec.Bg
			lab.TextColor3 = spec.Fg
			lab.Position = UDim2.fromOffset(x, line * (chipH + CHIP_LINE_GAP))
			lab.Size = UDim2.fromOffset(w, chipH)
			x += w + CHIP_GAP
			lines = line + 1
		end
	end
	for i = #order + 1, #pool do
		pool[i].Visible = false
	end
	return lines
end

-- ── Panel geometry ──────────────────────────────────────────────────────────
local function geometry(): (number, number, number, number)
	local rowW = panelW - 26 -- list inset 8+8, scrollbar 6, row inset 4
	local nameW = math.clamp(math.floor(rowW * 0.27), 130, 170)
	local chipsX = 10 + nameW + 8
	local chipsW = math.max(60, rowW - chipsX - BTN_W - 16)
	return rowW, nameW, chipsX, chipsW
end

local function applyLayout()
	local u = ui
	if not u then
		return
	end
	local w, h = guiArea()
	panelW = math.max(300, math.min(PANEL_MAX_W, w - 32))
	panelH = math.max(220, math.min(PANEL_MAX_H, h - 16))
	u.Panel.Size = UDim2.fromOffset(panelW, panelH)
	u.Title.Size = UDim2.fromOffset(panelW - 14 - 52, HEADER_H)
	u.ResultFrame.Size = UDim2.fromOffset(panelW - 8 - 52, HEADER_H - 12)
	u.Status.Size = UDim2.fromOffset(panelW - 24, statusH)
	u.StatusLabel.Size = UDim2.fromOffset(panelW - 24, STATUS_LINE_H)
	u.ReqHolder.Size = UDim2.fromOffset(panelW - 24, statusH)
	local listY = HEADER_H + 2 + statusH + 4
	u.List.Position = UDim2.fromOffset(8, listY)
	u.List.Size = UDim2.fromOffset(panelW - 16, panelH - listY - 8)
	u.Empty.Size = UDim2.fromOffset(panelW - 40, 56)
end

-- ── Result banner (inside the panel header, 3 s) ───────────────────────────
local RESULT_COLORS: { [string]: Color3 } = {
	Launched = C.Orange,
	Hit = C.Green,
	Intercepted = C.Amber,
	Refunded = C.Blue,
	Refused = C.Red,
}

local function showBanner(text: string, kind: string)
	local u = ui
	if not u then
		return
	end
	bannerToken += 1
	local token = bannerToken
	u.ResultLabel.Text = text
	u.ResultFrame.BackgroundColor3 = RESULT_COLORS[kind] or C.Grey
	u.ResultLabel.TextColor3 = if kind == "Intercepted" then Constants.Colors.TextDark else Color3.fromRGB(255, 255, 255)
	u.ResultFrame.Visible = true
	u.Title.Visible = false
	task.delay(RESULT_SECONDS, function()
		if token == bannerToken and ui then
			u.ResultFrame.Visible = false
			u.Title.Visible = true
		end
	end)
end

-- ── Status line ─────────────────────────────────────────────────────────────
local function shortName(displayName: string): string
	return (string.gsub(displayName, " Station$", ""))
end

local function requirementText(r: Requirement): string
	if r.Have >= r.Need then
		return string.format("✓ %s L%d (you L%d)", r.DisplayName, r.Need, r.Have)
	end
	local hints: { string } = {}
	local def = (BaseConfig.Structures :: any)[r.StructureId]
	if typeof(def) == "table" and typeof(def.Requires) == "table" then
		for _, pre in ipairs(def.Requires) do
			local preId = tostring(pre.StructureId)
			local preLevel = tonumber(pre.Level) or 1
			local known = baseUpgrades[preId]
			if known == nil or known < preLevel then
				local preDef = (BaseConfig.Structures :: any)[preId]
				local preName = if typeof(preDef) == "table" and typeof(preDef.DisplayName) == "string" then preDef.DisplayName else preId
				table.insert(hints, string.format("needs %s L%d", shortName(preName), preLevel))
			end
		end
	end
	local extra = if #hints > 0 then " · " .. table.concat(hints, " · ") else ""
	return string.format("✗ %s L%d (you L%d%s)", r.DisplayName, r.Need, r.Have, extra)
end

local function setStatusHeight(h: number)
	if h ~= statusH then
		statusH = h
		applyLayout()
	end
end

local function renderStatus()
	local u = ui
	if not u then
		return
	end
	local s = state
	if s and not s.Unlocked and #s.Requirements > 0 then
		u.StatusLabel.Visible = false
		u.ReqHolder.Visible = true
		local specs: { ChipSpec } = {}
		for _, r in ipairs(s.Requirements) do
			local ok = r.Have >= r.Need
			table.insert(specs, {
				Text = requirementText(r),
				Bg = if ok then Color3.fromRGB(34, 78, 50) else Color3.fromRGB(96, 30, 28),
				Fg = if ok then Color3.fromRGB(170, 240, 190) else Color3.fromRGB(255, 196, 186),
			})
		end
		local lines = flowChips(u.ReqHolder, u.ReqPool, specs, panelW - 24, 24, 2)
		setStatusHeight(if lines >= 2 then 2 * STATUS_LINE_H else STATUS_LINE_H)
		return
	end
	u.ReqHolder.Visible = false
	u.StatusLabel.Visible = true
	setStatusHeight(STATUS_LINE_H)
	local label = u.StatusLabel
	if not s then
		label.Text = "Contacting Missile Command…"
		label.TextColor3 = C.Muted
	elseif not s.Unlocked then
		label.Text = s.LockedText or "Needs Command Center L3 + Missile Defense L1"
		label.TextColor3 = C.Amber
	elseif s.InFlight then
		local left = live(s.InFlight.ImpactIn)
		label.Text = if left > 0
			then string.format("🚀 Missile in the air → %s · %ds", s.InFlight.TargetName, math.ceil(left))
			else string.format("🚀 Missile in the air → %s · impact…", s.InFlight.TargetName)
		label.TextColor3 = C.Orange
	elseif live(s.CooldownRemaining) > 0 then
		label.Text = "Reloading " .. mmss(live(s.CooldownRemaining))
		label.TextColor3 = C.Amber
	elseif not s.AtCommandCenter then
		label.Text = "Use this at your Command Center terminal"
		label.TextColor3 = C.Amber
	elseif s.Cash < s.Cost then
		label.Text = string.format("Cost $%s · you have $%s", commas(s.Cost), commas(s.Cash))
		label.TextColor3 = Color3.fromRGB(255, 140, 120)
	else
		label.Text = string.format("Cost $%s · READY", commas(s.Cost))
		label.TextColor3 = Color3.fromRGB(120, 230, 150)
	end
end

-- ── Rows ────────────────────────────────────────────────────────────────────
type ButtonMode = "strike" | "confirm" | "sending" | "dim" | "off"

local function attackerBusy(s: State): boolean
	return s.InFlight ~= nil or live(s.CooldownRemaining) > 0
end

local function buttonMode(t: Target): ButtonMode
	local s = state
	if not s or not s.Unlocked or not t.CanStrike then
		return "off"
	end
	if os.clock() < launchPendingUntil then
		return if pendingTargetUserId == t.UserId then "sending" else "off"
	end
	if attackerBusy(s) then
		return "off"
	end
	if not s.AtCommandCenter or s.Cash < s.Cost then
		return "dim"
	end
	if confirmUserId == t.UserId and os.clock() < confirmUntil then
		return "confirm"
	end
	return "strike"
end

local function stateChip(t: Target): (string?, Color3?)
	-- one state chip, in the server's CanStrike order (shield → down → reboot → inbound)
	local sh = live(t.ShieldRemaining)
	if sh > 0 then
		return "🛡 " .. mmss(sh), C.Blue
	end
	local dd = live(t.DefensesDownRemaining)
	if dd > 0 then
		return "DEF DOWN " .. mmss(dd), C.Red
	end
	local rb = live(t.RebootRemaining)
	if rb > 0 then
		return "REBOOT " .. mmss(rb), Color3.fromRGB(150, 104, 30)
	end
	if t.Incoming then
		return "INBOUND", C.Red
	end
	return nil, nil
end

local function rowReasonText(t: Target): string?
	local s = state
	if not s or not s.Unlocked or t.CanStrike then
		return nil
	end
	if t.Reason and ATTACKER_REASONS[t.Reason] then
		return nil -- the status line already says it (and counts it down)
	end
	local text = t.ReasonText or t.Reason
	if not text then
		return nil
	end
	if t.ReasonSecs and t.ReasonText then
		text = (string.gsub(t.ReasonText, "%d+:%d%d", mmss(live(t.ReasonSecs)), 1))
	end
	return text
end

local function renderRow(row: Row)
	local t = row.Target
	local s = state
	local unlocked = s ~= nil and s.Unlocked
	local _, nameW, chipsX, chipsW = geometry()

	row.Frame.BackgroundColor3 = if unlocked then C.Row else C.RowLocked
	row.NameLabel.Size = UDim2.fromOffset(nameW, 22)
	row.NameLabel.Text = t.BaseName
	row.NameLabel.TextColor3 = if unlocked then C.Text else C.Muted
	row.SubLabel.Size = UDim2.fromOffset(nameW, 20)
	row.SubLabel.Text = string.format("%s studs · %ds flight", commas(t.Distance), math.max(1, math.floor(t.FlightSeconds + 0.5)))

	-- chips: Walls · AutoGuns · MD/intercept · state
	local specs: { ChipSpec } = {}
	table.insert(specs, {
		Text = if t.WallsLevel > 0 then "Walls L" .. tostring(t.WallsLevel) else "No walls",
		Bg = C.Chip,
		Fg = C.Text,
	})
	if t.HasAutoGuns then
		table.insert(specs, { Text = "AutoGuns", Bg = Color3.fromRGB(92, 64, 36), Fg = Color3.fromRGB(255, 214, 150), Keep = true })
	end
	table.insert(specs, {
		Text = string.format("MD L%d · %d%% intercept", t.MissileDefenseLevel, math.floor(t.InterceptChance * 100 + 0.5)),
		Short = string.format("MD L%d · %d%%", t.MissileDefenseLevel, math.floor(t.InterceptChance * 100 + 0.5)),
		Keep = true,
		Bg = C.Chip,
		Fg = C.Text,
	})
	local stText, stColor = stateChip(t)
	if stText and stColor then
		table.insert(specs, { Text = stText, Bg = stColor, Fg = Color3.fromRGB(255, 255, 255), Keep = true })
	end
	local keyParts = { tostring(chipsW) }
	for _, spec in ipairs(specs) do
		table.insert(keyParts, spec.Text)
	end
	local key = table.concat(keyParts, "|")
	if key ~= row.ChipKey then
		row.ChipKey = key
		local chipH = CHIP_TEXT + 8
		local lines = flowChips(row.Chips, row.ChipPool, specs, chipsW, chipH, 2)
		local blockH = math.max(1, lines) * chipH + math.max(0, lines - 1) * CHIP_LINE_GAP
		row.Chips.Position = UDim2.fromOffset(chipsX, math.floor((ROW_H - blockH) / 2))
		row.Chips.Size = UDim2.fromOffset(chipsW, blockH)
	end

	-- reason under the row
	local reason = rowReasonText(t)
	row.ReasonLabel.Visible = reason ~= nil
	row.ReasonLabel.Text = reason or ""
	row.Frame.Size = UDim2.new(1, -4, 0, if reason then ROW_H + ROW_REASON_H else ROW_H)

	-- STRIKE button
	local btn = row.Button
	local costText = "$" .. commas(if s then s.Cost else 0)
	local mode = buttonMode(t)
	if mode == "strike" then
		btn.Text = "STRIKE\n" .. costText
		btn.BackgroundColor3 = C.Red
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.AutoButtonColor = true
	elseif mode == "confirm" then
		btn.Text = "CONFIRM\n" .. costText
		btn.BackgroundColor3 = C.Orange
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.AutoButtonColor = true
	elseif mode == "sending" then
		btn.Text = "LAUNCHING…"
		btn.BackgroundColor3 = C.Grey
		btn.TextColor3 = C.Text
		btn.AutoButtonColor = false
	elseif mode == "dim" then
		btn.Text = "STRIKE\n" .. costText
		btn.BackgroundColor3 = C.Dim
		btn.TextColor3 = C.Muted
		btn.AutoButtonColor = false
	else
		btn.Text = "—"
		btn.BackgroundColor3 = C.Grey
		btn.TextColor3 = C.Muted
		btn.AutoButtonColor = false
	end
	btn:SetAttribute("WE_Mode", mode)
end

local function renderRows()
	for _, row in pairs(rows) do
		renderRow(row)
	end
end

local function requestState()
	if not isOpen then
		return
	end
	local now = os.clock()
	local waitFor = MIN_REQUEST_GAP - (now - lastStateReqAt)
	if waitFor > 0 then
		if not stateReqQueued then
			stateReqQueued = true
			task.delay(waitFor, function()
				stateReqQueued = false
				requestState()
			end)
		end
		return
	end
	lastStateReqAt = now
	task.spawn(function()
		Remotes.FireServer(Constants.RemoteNames.RequestMissileStrike, { Action = "State" })
	end)
end

local function onStrikeTap(row: Row)
	local s = state
	local t = row.Target
	local mode = buttonMode(t)
	if mode == "sending" then
		return
	end
	if mode == "off" then
		if s and not s.Unlocked then
			showBanner(s.LockedText or "Needs Command Center L3 + Missile Defense L1", "Refused")
		elseif s and s.InFlight then
			showBanner("Your missile is still in the air", "Refused")
		elseif s and live(s.CooldownRemaining) > 0 then
			showBanner("Reloading — " .. mmss(live(s.CooldownRemaining)), "Refused")
		elseif not t.CanStrike then
			showBanner(rowReasonText(t) or t.ReasonText or "Can't strike this base right now", "Refused")
		end
		return
	end
	if mode == "dim" and s then
		if not s.AtCommandCenter then
			showBanner("Use the Missile Command terminal in your Command Center", "Refused")
		else
			showBanner(string.format("Need $%s — you have $%s", commas(s.Cost), commas(s.Cash)), "Refused")
		end
		return
	end
	pcall(AudioController.PlayClick)
	if mode == "confirm" then
		confirmUserId = nil
		launchPendingUntil = os.clock() + LAUNCH_PENDING_SECONDS
		pendingTargetUserId = t.UserId
		local uid = t.UserId
		task.spawn(function()
			local sent = Remotes.FireServer(Constants.RemoteNames.RequestMissileStrike, { Action = "Launch", TargetUserId = uid })
			if not sent then
				launchPendingUntil = 0
				showBanner("Missile Command offline — try again", "Refused")
				renderRows()
			end
		end)
		task.delay(LAUNCH_PENDING_SECONDS + 0.05, renderRows)
	else
		confirmUserId = t.UserId
		confirmUntil = os.clock() + CONFIRM_SECONDS
		task.delay(CONFIRM_SECONDS + 0.05, renderRows)
	end
	renderRows()
end

local function makeRow(list: ScrollingFrame, t: Target): Row
	local frame = Instance.new("Frame")
	frame.Name = "Target_" .. tostring(t.UserId)
	frame.BackgroundColor3 = C.Row
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, -4, 0, ROW_H)
	frame.Parent = list
	UIUtil.Corner(frame, 8)

	local nameLabel = newLabel(frame, "BaseName", Enum.Font.GothamBold, 16, C.Text)
	nameLabel.Position = UDim2.fromOffset(10, 8)

	local subLabel = newLabel(frame, "Sub", Enum.Font.Gotham, SMALL_TEXT, C.Muted)
	subLabel.Position = UDim2.fromOffset(10, 31)

	local chips = Instance.new("Frame")
	chips.Name = "Chips"
	chips.BackgroundTransparency = 1
	chips.BorderSizePixel = 0
	chips.Parent = frame

	local btn = Instance.new("TextButton")
	btn.Name = "Strike"
	btn.AnchorPoint = Vector2.new(1, 0)
	btn.Position = UDim2.new(1, -8, 0, 8)
	btn.Size = UDim2.fromOffset(BTN_W, BTN_H)
	btn.BorderSizePixel = 0
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 14
	btn.TextWrapped = true
	btn.Text = "—"
	btn.Parent = frame
	UIUtil.Corner(btn, 8)
	UIUtil.EnsureMinTouch(btn, 44)

	local reasonLabel = newLabel(frame, "Reason", Enum.Font.GothamMedium, SMALL_TEXT, C.Amber)
	reasonLabel.Position = UDim2.fromOffset(10, ROW_H - 4)
	reasonLabel.Size = UDim2.new(1, -20, 0, ROW_REASON_H)
	reasonLabel.Visible = false

	local row: Row = {
		UserId = t.UserId,
		Frame = frame,
		NameLabel = nameLabel,
		SubLabel = subLabel,
		Chips = chips,
		ChipPool = {},
		ChipKey = "",
		Button = btn,
		ReasonLabel = reasonLabel,
		Target = t,
	}
	btn.Activated:Connect(function()
		onStrikeTap(row)
	end)
	return row
end

local function reconcileRows()
	local u = ui
	if not u then
		return
	end
	local s = state
	local seen: { [number]: boolean } = {}
	if s then
		local order = table.clone(s.Targets)
		table.sort(order, function(a: Target, b: Target): boolean
			if a.CanStrike ~= b.CanStrike then
				return a.CanStrike
			end
			if a.Distance ~= b.Distance then
				return a.Distance < b.Distance
			end
			return a.UserId < b.UserId
		end)
		for i, t in ipairs(order) do
			seen[t.UserId] = true
			local row = rows[t.UserId]
			if not row then
				row = makeRow(u.List, t)
				rows[t.UserId] = row
			end
			row.Target = t
			row.Frame.LayoutOrder = i
		end
	end
	for uid, row in pairs(rows) do
		if not seen[uid] then
			row.Frame:Destroy()
			rows[uid] = nil
		end
	end
	if confirmUserId and not seen[confirmUserId] then
		confirmUserId = nil
	end
	u.Empty.Visible = s == nil or #s.Targets == 0
	u.Empty.Text = if s == nil then "Loading targets…" else "No enemy bases on this server right now"
end

local function renderAll()
	if not ui then
		return
	end
	renderStatus()
	reconcileRows()
	renderRows()
end

-- ── Panel construction (lazy; never yields beyond a bounded PlayerGui lookup) ─
local function ensureUi(): Ui?
	local existing = ui
	if existing and existing.Screen.Parent then
		return existing
	end
	local pg = getPlayerGui()
	if not pg then
		return nil
	end
	rows = {}

	local screen = Instance.new("ScreenGui")
	screen.Name = "WE_MissilePanel"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	-- Spec said 30; 60 matches every other modal panel so the HUD dock (55) never covers the STRIKE buttons.
	screen.DisplayOrder = 60
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Enabled = true

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(PANEL_MAX_W, PANEL_MAX_H)
	panel.BackgroundColor3 = C.Panel
	panel.BorderSizePixel = 0
	panel.Active = true -- taps on the panel never fall through to the world
	panel.Visible = false
	panel.Parent = screen
	UIUtil.Corner(panel, 10)
	UIUtil.Stroke(panel, C.Stroke, 1.5)

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	header.Parent = panel
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.BackgroundColor3 = C.Header
	divider.BorderSizePixel = 0
	divider.Position = UDim2.fromOffset(0, HEADER_H)
	divider.Size = UDim2.new(1, 0, 0, 2)
	divider.Parent = panel

	local title = newLabel(header, "Title", Enum.Font.GothamBlack, 20, C.Text)
	title.Position = UDim2.fromOffset(14, 0)
	title.Text = "MISSILE COMMAND"

	local resultFrame = Instance.new("Frame")
	resultFrame.Name = "Result"
	resultFrame.Position = UDim2.fromOffset(8, 6)
	resultFrame.BorderSizePixel = 0
	resultFrame.Visible = false
	resultFrame.Parent = header
	UIUtil.Corner(resultFrame, 7)
	local resultLabel = newLabel(resultFrame, "Text", Enum.Font.GothamBold, 15, Color3.fromRGB(255, 255, 255))
	resultLabel.Position = UDim2.fromOffset(10, 0)
	resultLabel.Size = UDim2.new(1, -20, 1, 0)

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 0, 0, 0)
	close.Size = UDim2.fromOffset(44, 44)
	close.BackgroundTransparency = 1
	close.BorderSizePixel = 0
	close.Font = Enum.Font.GothamBold
	close.TextSize = 22
	close.TextColor3 = C.Text
	close.Text = "✕"
	close.Parent = header
	UIUtil.EnsureMinTouch(close, 44)
	close.Activated:Connect(function()
		pcall(AudioController.PlayClick)
		MissileController.Close()
	end)

	local status = Instance.new("Frame")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.BorderSizePixel = 0
	status.Position = UDim2.fromOffset(12, HEADER_H + 2)
	status.Parent = panel

	local statusLabel = newLabel(status, "Line", Enum.Font.GothamBold, 15, C.Muted)
	statusLabel.Position = UDim2.fromOffset(0, 0)

	local reqHolder = Instance.new("Frame")
	reqHolder.Name = "Requirements"
	reqHolder.BackgroundTransparency = 1
	reqHolder.BorderSizePixel = 0
	reqHolder.Position = UDim2.fromOffset(0, 2)
	reqHolder.Visible = false
	reqHolder.Parent = status

	local list = Instance.new("ScrollingFrame")
	list.Name = "Targets"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = C.Muted
	list.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local empty = newLabel(panel, "Empty", Enum.Font.GothamMedium, 15, C.Muted)
	empty.AnchorPoint = Vector2.new(0.5, 0.5)
	empty.Position = UDim2.new(0.5, 0, 0.5, 30)
	empty.TextXAlignment = Enum.TextXAlignment.Center
	empty.TextWrapped = true
	empty.Text = "Loading targets…"

	screen.Parent = pg

	local built: Ui = {
		Screen = screen,
		Panel = panel,
		Title = title,
		ResultFrame = resultFrame,
		ResultLabel = resultLabel,
		Status = status,
		StatusLabel = statusLabel,
		ReqHolder = reqHolder,
		ReqPool = {},
		List = list,
		Empty = empty,
	}
	ui = built

	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		applyLayout()
		if isOpen then
			renderAll()
		end
	end)
	applyLayout()
	return built
end

-- ── State updates ───────────────────────────────────────────────────────────
local function onState(payload: any)
	local parsed = parseState(payload)
	if not parsed then
		return
	end
	state = parsed
	stateAt = os.clock()
	local result = parsed.Result
	if result then
		launchPendingUntil = 0
		pendingTargetUserId = nil
		if isOpen then
			showBanner(result.Text, result.Kind)
			task.delay(RESULT_REFRESH_DELAY, requestState)
		end
	end
	if isOpen then
		renderAll()
	end
end

-- ── Missile FX ──────────────────────────────────────────────────────────────
type Strike = {
	Id: number,
	P0: Vector3,
	P1: Vector3,
	P2: Vector3,
	Launch: number,
	Flight: number,
	EndT: number, -- 1 for a hit, InterceptT when shot down
	Intercepted: boolean,
	InterceptFrom: Vector3?,
	Involved: boolean,
	Folder: Folder,
	Parts: { BasePart },
	Offsets: { CFrame },
	Effects: { Instance },
	IParts: { BasePart },
	IOffsets: { CFrame },
	IEffects: { Instance },
	Exploded: boolean,
	DestroyAt: number,
}

type Alert = {
	Role: string, -- "Victim" | "Attacker"
	StrikeId: number,
	ImpactAt: number,
	ResolveAt: number,
	EndAt: number,
	Outcome: string,
	Other: string,
	DownSeconds: number,
}

type AlertUi = { Screen: ScreenGui, Edges: { Frame }, Banner: Frame, Label: TextLabel, Stroke: UIStroke }

local strikes: { Strike } = {}
local seenStrikeIds: { [number]: boolean } = {}
local seenCount = 0
local alert: Alert? = nil
local alertUi: AlertUi? = nil
local fxWarned = false

local function bezier(s: Strike, t: number): Vector3
	local u = 1 - t
	return s.P0 * (u * u) + s.P1 * (2 * u * t) + s.P2 * (t * t)
end

local function bezierDir(s: Strike, t: number): Vector3
	return (s.P1 - s.P0) * (2 * (1 - t)) + (s.P2 - s.P1) * (2 * t)
end

local function fxFolder(): Folder
	local f = workspace:FindFirstChild("WE_MissileFx")
	if f and f:IsA("Folder") then
		return f :: Folder
	end
	local nf = Instance.new("Folder")
	nf.Name = "WE_MissileFx"
	nf.Parent = workspace
	return nf
end

local function fxPart(parent: Instance, name: string, shape: Enum.PartType, size: Vector3, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = material
	p.Parent = parent
	return p
end

-- Builds a missile (forward = −Z, like CFrame.lookAt). Returns parts + their offsets + trail/smoke effects.
local function buildMissile(parent: Instance, small: boolean): ({ BasePart }, { CFrame }, { Instance })
	local k = if small then 0.6 else 1
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	local effects: { Instance } = {}
	local function add(p: BasePart, off: CFrame)
		table.insert(parts, p)
		table.insert(offsets, off)
	end
	local bodyColor = if small then Color3.fromRGB(205, 210, 215) else Color3.fromRGB(236, 236, 230)
	-- body cylinder 1×1×5 (a cylinder's axis is X → turn it onto Z)
	add(fxPart(parent, "Body", Enum.PartType.Cylinder, Vector3.new(5 * k, 1 * k, 1 * k), bodyColor, Enum.Material.SmoothPlastic), CFrame.Angles(0, math.rad(90), 0))
	add(fxPart(parent, "Nose", Enum.PartType.Ball, Vector3.new(1, 1, 1) * k, if small then Color3.fromRGB(60, 140, 220) else Color3.fromRGB(180, 40, 30), Enum.Material.SmoothPlastic), CFrame.new(0, 0, -2.5 * k))
	if not small then
		local finColor = Color3.fromRGB(60, 66, 72)
		add(fxPart(parent, "Fin", Enum.PartType.Block, Vector3.new(0.9, 0.1, 1.0), finColor, Enum.Material.Metal), CFrame.new(0.7, 0, 2.0))
		add(fxPart(parent, "Fin", Enum.PartType.Block, Vector3.new(0.9, 0.1, 1.0), finColor, Enum.Material.Metal), CFrame.new(-0.7, 0, 2.0))
		add(fxPart(parent, "Fin", Enum.PartType.Block, Vector3.new(0.1, 0.9, 1.0), finColor, Enum.Material.Metal), CFrame.new(0, 0.7, 2.0))
		add(fxPart(parent, "Fin", Enum.PartType.Block, Vector3.new(0.1, 0.9, 1.0), finColor, Enum.Material.Metal), CFrame.new(0, -0.7, 2.0))
	end
	local glow = fxPart(parent, "TailGlow", Enum.PartType.Ball, Vector3.new(0.8, 0.8, 0.8) * k, if small then Color3.fromRGB(140, 210, 255) else Color3.fromRGB(255, 150, 60), Enum.Material.Neon)
	add(glow, CFrame.new(0, 0, 2.7 * k))

	local a0 = Instance.new("Attachment")
	a0.Name = "TrailA"
	a0.Position = Vector3.new(0.35 * k, 0, 0)
	a0.Parent = glow
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailB"
	a1.Position = Vector3.new(-0.35 * k, 0, 0)
	a1.Parent = glow
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(Color3.fromRGB(150, 150, 150), Color3.fromRGB(255, 255, 255))
	trail.Lifetime = 1.2
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.WidthScale = NumberSequence.new(1, 3)
	trail.FaceCamera = true
	trail.Parent = glow
	table.insert(effects, trail)

	if not small then
		local smoke = Instance.new("ParticleEmitter")
		smoke.Name = "Smoke"
		smoke.Texture = SMOKE_TEXTURE
		smoke.Rate = 30
		smoke.Lifetime = NumberRange.new(1.5)
		smoke.Speed = NumberRange.new(1, 3)
		smoke.SpreadAngle = Vector2.new(8, 8)
		smoke.EmissionDirection = Enum.NormalId.Back
		smoke.Rotation = NumberRange.new(0, 360)
		smoke.RotSpeed = NumberRange.new(-30, 30)
		smoke.Color = ColorSequence.new(Color3.fromRGB(190, 190, 190), Color3.fromRGB(120, 120, 120))
		smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 5) })
		smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		smoke.Parent = glow
		table.insert(effects, smoke)
	end
	return parts, offsets, effects
end

local function place(parts: { BasePart }, offsets: { CFrame }, root: CFrame)
	for i, p in ipairs(parts) do
		p.CFrame = root * offsets[i]
	end
end

local function hideMissile(parts: { BasePart }, effects: { Instance })
	for _, p in ipairs(parts) do
		p.Transparency = 1
	end
	for _, e in ipairs(effects) do
		if e:IsA("Trail") then
			e.Enabled = false
		elseif e:IsA("ParticleEmitter") then
			e.Enabled = false
		end
	end
end

local cameraShakeUntil, cameraShakeDur, cameraShakeAmp = 0, 0.4, 0
local shakeBound = false
local function shakeCamera(duration: number, amp: number)
	cameraShakeUntil = os.clock() + duration
	cameraShakeDur = duration
	cameraShakeAmp = amp
	if shakeBound then
		return
	end
	local ok = pcall(function()
		RunService:BindToRenderStep("WE_MissileShake", Enum.RenderPriority.Camera.Value + 1, function()
			local left = cameraShakeUntil - os.clock()
			local cam = workspace.CurrentCamera
			if left <= 0 or not cam then
				shakeBound = false
				pcall(function()
					RunService:UnbindFromRenderStep("WE_MissileShake")
				end)
				return
			end
			local a = cameraShakeAmp * (left / cameraShakeDur)
			cam.CFrame = cam.CFrame * CFrame.new((math.random() - 0.5) * a, (math.random() - 0.5) * a, 0)
		end)
	end)
	shakeBound = ok
end

local function cameraPos(): Vector3?
	local cam = workspace.CurrentCamera
	if cam then
		return cam.CFrame.Position
	end
	return nil
end

local function burst(pos: Vector3, radius: number)
	local folder = fxFolder()
	local ex = Instance.new("Explosion")
	ex.BlastPressure = 0
	ex.DestroyJointRadiusPercent = 0
	ex.BlastRadius = radius
	ex.ExplosionType = Enum.ExplosionType.NoCraters
	ex.Position = pos
	ex.Parent = folder
	Debris:AddItem(ex, 2)

	local ball = fxPart(folder, "Blast", Enum.PartType.Ball, Vector3.new(2, 2, 2), Color3.fromRGB(255, 140, 40), Enum.Material.Neon)
	ball.CFrame = CFrame.new(pos)
	ball.Transparency = 0.2
	local grow = radius * 1.6
	TweenService:Create(ball, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(grow, grow, grow),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ball, 2)

	local cam = cameraPos()
	if cam and (cam - pos).Magnitude <= SHAKE_STUDS then
		shakeCamera(0.4, 0.8)
	end
end

local function destroyStrike(s: Strike)
	if s.Folder.Parent then
		s.Folder:Destroy()
	end
end

-- one frame of one strike; false = finished (remove it)
local function stepStrike(s: Strike, now: number): boolean
	if s.Exploded then
		if now >= s.DestroyAt then
			destroyStrike(s)
			return false
		end
		return true
	end
	local t = math.clamp((now - s.Launch) / s.Flight, 0, 1)
	if t >= s.EndT then
		local at = bezier(s, s.EndT)
		burst(at, if s.Intercepted then 14 else EXPLOSION_RADIUS)
		hideMissile(s.Parts, s.Effects)
		hideMissile(s.IParts, s.IEffects)
		s.Exploded = true
		s.DestroyAt = s.Launch + s.Flight * s.EndT + 2
		Debris:AddItem(s.Folder, 3) -- safety net; the render loop destroys it at +2 s
		return true
	end
	local pos = bezier(s, t)
	local dir = bezierDir(s, t)
	if dir.Magnitude < 1e-3 then
		dir = s.P2 - s.P0
	end
	place(s.Parts, s.Offsets, CFrame.lookAt(pos, pos + dir))

	local from = s.InterceptFrom
	if s.Intercepted and from then
		local meetAt = s.Launch + s.Flight * s.EndT
		local startAt = meetAt - INTERCEPTOR_SECONDS
		if now >= startAt then
			if #s.IParts == 0 then
				local ip, io, ie = buildMissile(s.Folder, true)
				s.IParts, s.IOffsets, s.IEffects = ip, io, ie
			end
			local target = bezier(s, s.EndT)
			local k = math.clamp((now - startAt) / INTERCEPTOR_SECONDS, 0, 1)
			local ipos = from:Lerp(target, k)
			local idir = target - from
			if idir.Magnitude < 1e-3 then
				idir = Vector3.new(0, 1, 0)
			end
			place(s.IParts, s.IOffsets, CFrame.lookAt(ipos, ipos + idir))
		end
	end
	return true
end

-- ── Victim / attacker alert (screen overlay) ────────────────────────────────
local function ensureAlertUi(): AlertUi?
	local existing = alertUi
	if existing and existing.Screen.Parent then
		return existing
	end
	local pg = getPlayerGui()
	if not pg then
		return nil
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "WE_MissileAlert"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true -- the red edge hugs the real screen edge
	screen.DisplayOrder = 66 -- above the HUD (55) and panels (60), below toasts (70)
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local edges: { Frame } = {}
	local specs = {
		{ Name = "EdgeTop", Anchor = Vector2.new(0, 0), Pos = UDim2.fromScale(0, 0), Size = UDim2.new(1, 0, 0, 18) },
		{ Name = "EdgeBottom", Anchor = Vector2.new(0, 1), Pos = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 18) },
		{ Name = "EdgeLeft", Anchor = Vector2.new(0, 0), Pos = UDim2.new(0, 0, 0, 18), Size = UDim2.new(0, 18, 1, -36) },
		{ Name = "EdgeRight", Anchor = Vector2.new(1, 0), Pos = UDim2.new(1, 0, 0, 18), Size = UDim2.new(0, 18, 1, -36) },
	}
	for _, e in ipairs(specs) do
		local f = Instance.new("Frame")
		f.Name = e.Name
		f.AnchorPoint = e.Anchor
		f.Position = e.Pos
		f.Size = e.Size
		f.BackgroundColor3 = Color3.fromRGB(230, 30, 30)
		f.BackgroundTransparency = 0.45
		f.BorderSizePixel = 0
		f.Active = false
		f.Visible = false
		f.Parent = screen
		table.insert(edges, f)
	end

	local banner = Instance.new("Frame")
	banner.Name = "Banner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.BorderSizePixel = 0
	banner.Active = false
	banner.Visible = false
	banner.Parent = screen
	UIUtil.Corner(banner, 10)
	local stroke = UIUtil.Stroke(banner, Color3.fromRGB(255, 120, 100), 2)

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(12, 0)
	label.Size = UDim2.new(1, -24, 1, 0)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.5
	label.Text = ""
	label.Parent = banner
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = 14
	limit.MaxTextSize = 22
	limit.Parent = label

	screen.Parent = pg
	local built: AlertUi = { Screen = screen, Edges = edges, Banner = banner, Label = label, Stroke = stroke }
	alertUi = built
	return built
end

local function hideAlertUi()
	local au = alertUi
	if not au then
		return
	end
	au.Banner.Visible = false
	for _, e in ipairs(au.Edges) do
		e.Visible = false
	end
end

local function alertResultText(a: Alert): string
	if a.Role == "Victim" then
		if a.Outcome == "Intercepted" then
			return string.format("✓ Your Missile Defense shot down %s's missile", a.Other)
		end
		return string.format("💥 Missile hit! Defenses down %s — protect your ATM!", mmss(a.DownSeconds))
	end
	if a.Outcome == "Intercepted" then
		return string.format("Intercepted by %s's Missile Defense", a.Other)
	end
	return string.format("Direct hit! %s's defenses down %s — go raid!", a.Other, mmss(a.DownSeconds))
end

local function playSiren()
	local sfxOn = true
	pcall(function()
		sfxOn = ClientSettings.ShouldPlaySfx()
	end)
	if not sfxOn then
		return
	end
	local volume = 0.5 * AudioController.GetSfxVolume()
	local sound = Instance.new("Sound")
	sound.Name = "WE_MissileSiren"
	sound.SoundId = SIREN_ID
	sound.Volume = volume
	sound.Parent = SoundService
	task.spawn(function()
		for i = 1, 8 do -- 8 × 0.35 s = 2.8 s
			if not sound.Parent then
				break
			end
			sound.PlaybackSpeed = if i % 2 == 1 then 0.7 else 1.0
			sound.TimePosition = 0
			sound:Play()
			task.wait(0.35)
		end
		sound:Destroy()
	end)
end

local function startAlert(role: string, strikeId: number, launch: number, flight: number, endT: number, outcome: string, other: string, downSeconds: number)
	local current = alert
	if current and current.Role == "Victim" and role == "Attacker" and serverNow() < current.EndAt then
		return -- an incoming missile outranks our own launch banner
	end
	local resolveAt = launch + flight * endT
	alert = {
		Role = role :: string,
		StrikeId = strikeId,
		ImpactAt = launch + flight,
		ResolveAt = resolveAt,
		EndAt = resolveAt + ALERT_HOLD_SECONDS,
		Outcome = outcome,
		Other = other,
		DownSeconds = downSeconds,
	}
	local au = ensureAlertUi()
	if au then
		local w = guiArea()
		local victim = role == "Victim"
		au.Banner.Position = UDim2.new(0.5, 0, 0, topInset() + 8)
		au.Banner.Size = UDim2.fromOffset(math.max(200, math.min(if victim then 620 else 480, w - 32)), if victim then 50 else 38)
		au.Banner.BackgroundColor3 = if victim then Color3.fromRGB(128, 18, 16) else Color3.fromRGB(34, 38, 44)
		au.Stroke.Color = if victim then Color3.fromRGB(255, 120, 100) else C.Orange
		au.Label.Font = if victim then Enum.Font.GothamBlack else Enum.Font.GothamBold
		local limit = au.Label:FindFirstChildOfClass("UITextSizeConstraint")
		if limit then
			limit.MaxTextSize = if victim then 22 else 16
		end
		for _, e in ipairs(au.Edges) do
			e.Visible = false
		end
	end
	if role == "Victim" then
		playSiren()
	end
end

local function stepAlert(now: number)
	local a = alert
	if not a then
		return
	end
	if now >= a.EndAt then
		alert = nil
		hideAlertUi()
		return
	end
	local au = ensureAlertUi()
	if not au then
		return
	end
	local victim = a.Role == "Victim"
	au.Banner.Visible = victim or not isOpen -- the open panel already shows our own launch
	if now >= a.ResolveAt then
		for _, e in ipairs(au.Edges) do
			e.Visible = false
		end
		au.Label.Text = alertResultText(a)
		if a.Outcome == "Intercepted" then
			au.Banner.BackgroundColor3 = if victim then Color3.fromRGB(30, 96, 54) else Color3.fromRGB(110, 78, 20)
		else
			au.Banner.BackgroundColor3 = if victim then Color3.fromRGB(150, 28, 20) else Color3.fromRGB(30, 96, 54)
		end
		return
	end
	local secs = math.max(0, math.ceil(a.ImpactAt - now))
	if victim then
		au.Label.Text = string.format("⚠ INCOMING MISSILE from %s — impact %ds", a.Other, secs)
		local tr = 0.45 + 0.25 * math.sin(os.clock() * math.pi * 4) -- 2 Hz between 0.2 and 0.7
		for _, e in ipairs(au.Edges) do
			e.Visible = true
			e.BackgroundTransparency = tr
		end
	else
		au.Label.Text = string.format("🚀 Missile away → %s · %ds", a.Other, secs)
	end
end

-- ── MissileStrikeFx ─────────────────────────────────────────────────────────
local function onFx(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local from, to = payload.From, payload.To
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then
		return
	end
	local id = tonumber(payload.StrikeId)
	local launch = tonumber(payload.LaunchTime)
	local flight = tonumber(payload.FlightSeconds)
	if id == nil or launch == nil or flight == nil or flight <= 0 or flight > 60 then
		return
	end
	if seenStrikeIds[id] then
		return
	end
	seenCount += 1
	if seenCount > 256 then
		seenStrikeIds = {}
		seenCount = 1
	end
	seenStrikeIds[id] = true

	local now = serverNow()
	if now > launch + flight + FX_LATE_SECONDS then
		return -- late joiner: it is already over
	end
	local intercepted = payload.Outcome == "Intercepted"
	local endT = if intercepted then math.clamp(num(payload.InterceptT, 0.8), 0.05, 1) else 1
	local interceptFrom: Vector3? = if typeof(payload.InterceptFrom) == "Vector3" then payload.InterceptFrom else nil
	if intercepted and not interceptFrom then
		interceptFrom = to + Vector3.new(0, 6, 0)
	end
	local me = player.UserId
	local isVictim = tonumber(payload.VictimUserId) == me
	local isAttacker = tonumber(payload.AttackerUserId) == me
	local attackerName = str(payload.AttackerName) or "an enemy"
	local victimName = str(payload.VictimName) or "the target"
	local downSeconds = math.max(0, num(payload.DownSeconds, 120))
	local outcome = if intercepted then "Intercepted" else "Hit"

	if isVictim then
		startAlert("Victim", id, launch, flight, endT, outcome, attackerName, downSeconds)
	elseif isAttacker then
		startAlert("Attacker", id, launch, flight, endT, outcome, victimName, downSeconds)
	end

	-- 3D: only near the camera, or when we are part of it; at most FX_MAX_ACTIVE at once
	local arc = math.clamp(num(payload.ArcHeight, 200), 0, 2000)
	local p1 = (from + to) / 2 + Vector3.new(0, arc, 0)
	local involved = isVictim or isAttacker
	if not involved then
		local cam = cameraPos()
		if not cam then
			return
		end
		local mid = from * 0.25 + p1 * 0.5 + to * 0.25
		if (cam - from).Magnitude > FX_CULL_STUDS and (cam - to).Magnitude > FX_CULL_STUDS and (cam - mid).Magnitude > FX_CULL_STUDS then
			return
		end
	end
	if #strikes >= FX_MAX_ACTIVE then
		local evict: number? = nil
		for i, s in ipairs(strikes) do
			if not s.Involved then
				evict = i
				break
			end
		end
		if evict == nil and involved then
			evict = 1
		end
		if evict == nil then
			return
		end
		destroyStrike(strikes[evict])
		table.remove(strikes, evict)
	end

	local folder = Instance.new("Folder")
	folder.Name = "Strike_" .. tostring(id)
	folder.Parent = fxFolder()
	local parts, offsets, effects = buildMissile(folder, false)
	local s: Strike = {
		Id = id,
		P0 = from,
		P1 = p1,
		P2 = to,
		Launch = launch,
		Flight = flight,
		EndT = endT,
		Intercepted = intercepted,
		InterceptFrom = interceptFrom,
		Involved = involved,
		Folder = folder,
		Parts = parts,
		Offsets = offsets,
		Effects = effects,
		IParts = {},
		IOffsets = {},
		IEffects = {},
		Exploded = false,
		DestroyAt = 0,
	}
	table.insert(strikes, s)
	stepStrike(s, now)
end

local function stepFx()
	if #strikes == 0 and alert == nil then
		return
	end
	local now = serverNow()
	for i = #strikes, 1, -1 do
		local s = strikes[i]
		if not stepStrike(s, now) then
			table.remove(strikes, i)
		end
	end
	stepAlert(now)
end

-- ── Public API ──────────────────────────────────────────────────────────────
function MissileController.Open(_tab: string?)
	local u = ensureUi()
	if not u then
		warn("[WAR EMPIRE] Missile panel: PlayerGui not ready")
		return
	end
	isOpen = true
	u.Panel.Visible = true
	applyLayout()
	renderAll()
	requestState()
end

function MissileController.Close()
	isOpen = false
	confirmUserId = nil
	local u = ui
	if u then
		u.Panel.Visible = false
	end
end

function MissileController.Toggle()
	if isOpen then
		MissileController.Close()
	else
		MissileController.Open()
	end
end

function MissileController.IsOpen(): boolean
	return isOpen
end

function MissileController.Init()
	if initDone then
		return
	end
	initDone = true

	Remotes.BindEvent(Constants.RemoteNames.MissileStrikeStateUpdate, function(payload: any)
		local ok, err = pcall(function()
			onState(payload)
		end)
		if not ok then
			warn("[WAR EMPIRE] Missile state update failed:", err)
		end
	end)
	Remotes.BindEvent(Constants.RemoteNames.MissileStrikeFx, function(payload: any)
		local ok, err = pcall(function()
			onFx(payload)
		end)
		if not ok then
			warn("[WAR EMPIRE] Missile FX failed:", err)
		end
	end)
	-- own structure levels → "needs Radar L2" hints on the locked requirement chips
	Remotes.BindEvent(Constants.RemoteNames.BaseStateUpdate, function(payload: any)
		if typeof(payload) == "table" and typeof(payload.Upgrades) == "table" then
			local levels: { [string]: number } = {}
			for k, v in pairs(payload.Upgrades) do
				if typeof(k) == "string" and tonumber(v) then
					levels[k] = tonumber(v) :: number
				end
			end
			baseUpgrades = levels
		end
	end)

	local function fxError(err: any)
		if not fxWarned then
			fxWarned = true
			warn("[WAR EMPIRE] Missile FX step failed:", err)
		end
	end
	RunService.RenderStepped:Connect(function()
		xpcall(stepFx, fxError)
	end)

	-- 1 s ticker: live countdowns while open; State refresh every REFRESH_SECONDS
	task.spawn(function()
		while true do
			task.wait(1)
			if isOpen then
				local ok, err = pcall(function()
					renderStatus()
					renderRows()
					if os.clock() - lastStateReqAt >= REFRESH_SECONDS - 0.05 then
						requestState()
					end
				end)
				if not ok then
					warn("[WAR EMPIRE] Missile panel tick failed:", err)
				end
			end
		end
	end)
end

return MissileController
