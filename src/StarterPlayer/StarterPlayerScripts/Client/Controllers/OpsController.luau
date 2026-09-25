--!strict
--[[
	OpsController — Jobs on the client (W3 step 2 Phase B, lane U; players see "Jobs", the code says Ops).
	Contract: scratchpad w3s2/buildB/KB/contract.md §6. Spec: w3s2/spec_w3s2.md §6-§10 + activities §1.1-§1.6, §9.

	Ships OFF: while OpsConfig.Enabled is false, Init returns at once (no gui, no remote, no loop). The server decides
	every state, pay, cooldown and point; this controller only shows them. It never sends a job request (there is no
	Ops client -> server remote): every job action is a server ProximityPrompt that PromptController already adopts.

	DATA   OpsState (RemoteEvent) -> OpsJobs.Merge into one cache (Full replaces, deltas merge, "Off" drops).
	       OpsProgress (RemoteEvent, 4 Hz inside a job zone) -> the hold pill.
	       OpsPing (UnreliableRemoteEvent, a bag carrier every 10 s) -> "Steal the Bag" (polled with a bounded retry
	       from a spawned task; never Remotes.GetUnreliableEvent on this thread).
	JOBS   MissionController's JOBS section reads Rows() (OpsJobs: tracked / carried, nearest open, the bank or a bag)
	       and calls Track(id) (GO) / Stop() (STOP). GO resolves the point NOW, per player: the site's own Target
	       anchor (the nearest open one of that job if it closed meanwhile), your own Home, or the last bag position.
	       Never a fixed world marker.
	MARKER ObjectiveMarker.ShowWith(point, OpsConfig.Ui arrival / timeout). The marker is followed (Move) when its
	       point moves (a bag, a rotating cache). Arrival hides it (the site label and the prompt pill take over); the
	       job stays tracked for the card until it is done, gone, or you walk away. Another GO (a mission, a console
	       line) or Clear wins: the job is untracked. Carrying a bag auto-tracks Home ("BASE"); delivery clears it.
	       CompassController's tracked mode follows ObjectiveMarker.Revision(), so the chip shows the same target.
	CARD   One top-stack item (Order.Objective, HudConfig.TopStack.Objective sizes): the job title + "Go to <place> ·
	       620m" / the first step on arrival / "GET THE BAG HOME · 3:20 left". X (64 v = 44.8 real px) stops tracking.
	       Hidden in a panel, dead, in the tutorial, in your own plot or while driving, EXCEPT while carrying a bag
	       (then only a panel or death hide it, and there is no X). It collapses whenever the hold pill shows: one
	       message at a time.
	PILL   ProgressPill in the Progress slot (360 x 44 v, 20 v text). Text from OpsConfig.Text.Pill by Stage /
	       Blocked. It yields to the territory capture pill.

	Cost: no per-frame connection, no whole-tree scan, no wait without a timeout. One 1 Hz loop
	(countdowns, ping expiry, marker follow); everything else runs on payload arrival (<= 2 Hz state, 4 Hz progress).
	Copy: OpsConfig.Text only — no key names, no "tap" / "click", never a nation name.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60) -- ships with the place (Rojo); bounded wait anyway
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local HudConfig = require(Shared.Configs.HudConfig)
local OpsConfig = require(Shared.Configs.OpsConfig)
local UIUtil = require(Shared.Util.UIUtil)

local HudLayout = require(script.Parent.Parent.Modules.HudLayout)
local HudIcons = require(script.Parent.Parent.Modules.HudIcons)
local ProgressPill = require(script.Parent.Parent.Modules.ProgressPill)
local ObjectiveMarker = require(script.Parent.Parent.Modules.ObjectiveMarker)
local OpsJobs = require(script.Parent.Parent.Modules.OpsJobs)
local AudioController = require(script.Parent.Parent.Modules.AudioController)

local OpsController = {}

local UI = OpsConfig.Ui
local TEXT = OpsConfig.Text
local OBJ = HudConfig.TopStack.Objective
local UI_ANY: any = UI
-- after arrival, the job is forgotten this far from its point (pending edit: OpsConfig.Ui.ForgetStuds)
local FORGET_STUDS: number = if type(UI_ANY.ForgetStuds) == "number" then UI_ANY.ForgetStuds else OpsConfig.Npc.SleepRadius
local PROGRESS_STALE = 3 / math.max(1, OpsConfig.Remote.ProgressHz) + 1 -- no progress for this long: the pill hides
local WAVE_SHOW_SECONDS = 2 -- "WAVE 2 OF 3" replaces the pill title this long when a wave starts
local TICK = 1 / math.max(0.2, UI.CountdownHz)
local MARKER_OPTS: ObjectiveMarker.Opts = { ArriveStuds = UI.ArriveStuds, TimeoutSeconds = UI.MarkerTimeoutSeconds }
local UNDER_FIRE = Color3.fromRGB(255, 96, 72)
local VEHICLE = Color3.fromRGB(255, 176, 48)
local GOLD = HudConfig.Colors.Gold
local CARD_PAD_L = 14
local CARD_TITLE_H = 24
local CARD_CORNER = 16
local HIDE_CARD = { "Tutorial", "Modal", "Dead", "InOwnPlot", "Driving" }
local HIDE_CARD_CARRYING = { "Modal", "Dead" }

local player = Players.LocalPlayer
local running = false

local cache: OpsJobs.Cache = OpsJobs.NewCache()
local tracked: string? = nil -- a site id, OpsJobs.HomeId or "@bag:<UserId>"
local arrived = false -- the marker reached the tracked point (arrival hid it)
local myRev = -1 -- ObjectiveMarker.Revision() right after our own Show / Move
local shownAt: ObjectiveMarker.Target? = nil -- the point our marker shows
local cdAtTrack = false -- the tracked site was already on this player's cooldown when tracking began
local wasCarrying = false
local rowsVersion = 0 -- bumps whenever what Rows() returns may differ (the JOBS section rebuilds on change)

-- progress (OpsProgress)
type Prog = {
	Site: string,
	Stage: string,
	Frac: number?,
	Blocked: string?,
	Guards: number?,
	Left: number?,
	Wave: number?,
	Waves: number?,
}
local prog: Prog? = nil
local progAt = -math.huge
local lastWave = 0
local waveShownAt = -math.huge

-- gui
local card: Frame? = nil
local cardTitle: TextLabel? = nil
local cardHint: TextLabel? = nil
local cardClose: TextButton? = nil
local cardCarryRule: boolean? = nil
local pill: ProgressPill.Pill? = nil
local captureFrame: GuiObject? = nil

-- MissionController (the JOBS section lives in its panel); required lazily so a load order change never breaks
type JobsHost = { SetJobsSource: (any) -> (), JobsChanged: () -> () }
local host: JobsHost? = nil

local function now(): number
	return os.clock()
end

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -1e7 and n < 1e7
end

local function rootPos(): Vector3?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp.Position
	end
	return nil
end

-- where distances are measured from: your front gate (Home) while you stand in your own plot, else your character
local function measurePoint(): OpsJobs.Me?
	local h = cache.Home
	if h and HudLayout.GetFlag("InOwnPlot") then
		return { X = h.X, Z = h.Z }
	end
	local p = rootPos()
	if p then
		return { X = p.X, Z = p.Z }
	end
	if h then
		return { X = h.X, Z = h.Z }
	end
	return nil
end

local function isBagId(id: string): boolean
	return string.sub(id, 1, #OpsJobs.BagPrefix) == OpsJobs.BagPrefix
end

local function isSiteId(id: string): boolean
	return id ~= OpsJobs.HomeId and not isBagId(id)
end

local function notifyRows()
	rowsVersion += 1
	local h = host
	if h then
		pcall(h.JobsChanged)
	end
end

---------------------------------------------------------------------------------------------------------------
-- marker
---------------------------------------------------------------------------------------------------------------

local function samePoint(a: ObjectiveMarker.Target?, b: ObjectiveMarker.Target): boolean
	return a ~= nil and a.X == b.X and a.Y == b.Y and a.Z == b.Z
end

local function showMarker(p: ObjectiveMarker.Target)
	local ok, err = pcall(function(): any
		ObjectiveMarker.ShowWith(p, MARKER_OPTS)
		return nil
	end)
	if not ok then
		warn("[OpsController] ObjectiveMarker.ShowWith failed:", err)
	end
	myRev = ObjectiveMarker.Revision()
	shownAt = p
end

local function moveMarker(p: ObjectiveMarker.Target)
	if samePoint(shownAt, p) then
		return
	end
	if ObjectiveMarker.Revision() == myRev and ObjectiveMarker.Move(p.X, p.Y, p.Z) then
		myRev = ObjectiveMarker.Revision()
		shownAt = p
	end
end

local refreshCard: () -> () -- forward

-- stop tracking; clear the marker only while it is still ours (another GO's marker is never touched)
local function untrack()
	if tracked == nil then
		return
	end
	if not arrived and ObjectiveMarker.Revision() == myRev then
		ObjectiveMarker.Clear()
	end
	tracked = nil
	arrived = false
	shownAt = nil
	myRev = -1
	notifyRows()
	refreshCard()
end

local function siteCd(id: string): boolean
	local e = cache.Sites[id]
	return e ~= nil and OpsJobs.Remaining(e.MyCd, e.At, now()) > 0
end

-- start following `id` from `p` (a fresh marker)
local function follow(id: string, p: ObjectiveMarker.Target)
	tracked = id
	arrived = false
	cdAtTrack = isSiteId(id) and siteCd(id)
	showMarker(p)
	notifyRows()
	refreshCard()
end

--[[ GO on a JOBS row: resolve the point now, per player. A site that closed since the rows were drawn falls back to
	the nearest open site doing the same job. false = nothing to go to (the row is stale). ]]
function OpsController.Track(id: string): boolean
	if not running or type(id) ~= "string" then
		return false
	end
	local me = measurePoint()
	local t = now()
	local p = OpsJobs.GoFor(cache, id, me, player.UserId, t)
	if p == nil and isSiteId(id) then
		local alt = OpsJobs.NearestLike(cache, id, me, t)
		if alt then
			id = alt
			p = OpsJobs.GoFor(cache, alt, me, player.UserId, t)
		end
	end
	if p == nil then
		notifyRows()
		return false
	end
	pcall(AudioController.PlayClick)
	follow(id, p)
	return true
end

--[[ STOP on the tracked row / the card's X. ]]
function OpsController.Stop()
	untrack()
end

function OpsController.Tracked(): string?
	return tracked
end

function OpsController.Rows(): { OpsJobs.Row }
	if not running then
		return {}
	end
	return OpsJobs.Rows(cache, measurePoint(), tracked, player.UserId, now())
end

function OpsController.RowsVersion(): number
	return rowsVersion
end

-- the marker changed under us: our arrival keeps the job; any other GO / Clear / timeout wins (also after arrival:
-- a newer marker from another GO untracks the job, so the card never names a job the marker no longer points at)
local function checkMarker()
	if tracked == nil then
		return
	end
	local rev = ObjectiveMarker.Revision()
	-- after arrival our marker is gone, so any marker or console / ATM line up now is a newer GO
	if rev == myRev and not (arrived and ObjectiveMarker.OnTop()) then
		return
	end
	if not arrived and ObjectiveMarker.Current() == nil and ObjectiveMarker.Ended() == "Arrived" then
		arrived = true
		myRev = rev
		refreshCard()
		return
	end
	tracked = nil
	arrived = false
	shownAt = nil
	myRev = -1
	notifyRows()
	refreshCard()
end

-- a moving target (a bag, your Home while carrying) that got away after arrival: show the marker again
local function refollowIfFar(id: string, p: ObjectiveMarker.Target, me: OpsJobs.Me?)
	if me == nil then
		return
	end
	local dx, dz = p.X - me.X, p.Z - me.Z
	local far = UI.ArriveStuds * 2
	if dx * dx + dz * dz > far * far then
		follow(id, p)
	end
end

-- keep the tracked job honest after new data / each tick: done, gone, moved, or walked away from
local function followTracked()
	checkMarker() -- first: a newer GO (mission / console) wins before anything here could re-show our marker
	local id = tracked
	if id == nil then
		return
	end
	local t = now()
	local me = measurePoint()
	if id == OpsJobs.HomeId then
		if cache.Carrying == nil then
			untrack() -- delivered (or the bag was lost): the job is over
			return
		end
		local p = OpsJobs.HomeGo(cache)
		if p then
			if arrived then
				refollowIfFar(id, p, me)
			else
				moveMarker(p)
			end
		end
		return
	end
	if isBagId(id) then
		local p = OpsJobs.GoFor(cache, id, me, player.UserId, t)
		if p == nil then
			untrack() -- picked up by someone / gone
			return
		end
		if arrived then
			refollowIfFar(id, p, me) -- the carrier ran off: chase it again
		else
			moveMarker(p)
		end
		return
	end
	local e = cache.Sites[id]
	if e == nil or not OpsJobs.Available(e, t) then
		local done = e ~= nil
			and ((e.HeldBy ~= nil and e.HeldBy == player.UserId) or (not cdAtTrack and OpsJobs.Remaining(e.MyCd, e.At, t) > 0))
		if done or arrived then
			untrack() -- you did it (or it closed while you were there): the card goes
			return
		end
		local alt = OpsJobs.NearestLike(cache, id, me, t)
		local p = alt and OpsJobs.GoFor(cache, alt, me, player.UserId, t)
		if alt and p then
			follow(alt, p) -- it closed on the way: the nearest open one of the same job
		else
			untrack()
		end
		return
	end
	local def = OpsConfig.Get(id)
	local p = def and OpsJobs.SiteGo(e, def)
	if p then
		if arrived then
			if me then
				local dx, dz = p.X - me.X, p.Z - me.Z
				if dx * dx + dz * dz > FORGET_STUDS * FORGET_STUDS then
					untrack() -- walked away after arriving
				end
			end
		else
			moveMarker(p) -- a rotating cache moved its box
		end
	end
end

---------------------------------------------------------------------------------------------------------------
-- card
---------------------------------------------------------------------------------------------------------------

local function pillShowing(): boolean
	local pr = prog
	if pr == nil or now() - progAt > PROGRESS_STALE then
		return false
	end
	-- yield to the territory capture pill (both live in the Progress slot)
	local f = captureFrame
	if f == nil or f.Parent == nil then
		f = nil
		local pg = player:FindFirstChildOfClass("PlayerGui")
		local g = pg and pg:FindFirstChild("WarEmpireTerritory")
		local c = g and g:FindFirstChild("CaptureProgress")
		if c and c:IsA("GuiObject") then
			f = c
		end
		captureFrame = f
	end
	return not (f ~= nil and f.Visible)
end

local function cardWanted(): boolean
	if not running then
		return false
	end
	if cache.Carrying == nil and tracked == nil then
		return false
	end
	return not pillShowing()
end

local function distTo(x: number, z: number): number?
	local me = measurePoint()
	if me == nil then
		return nil
	end
	local dx, dz = x - me.X, z - me.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- (title, hint) for the card right now
local function cardText(): (string, string)
	local C = TEXT.Card
	local t = now()
	local carry = cache.Carrying
	if carry then
		return C.Carry, string.format(C.CarryHint, OpsJobs.Clock(OpsJobs.Remaining(carry.Left, cache.CarryAt, t)))
	end
	local id = tracked
	if id == nil then
		return "", ""
	end
	if isBagId(id) then
		local p = OpsJobs.GoFor(cache, id, measurePoint(), player.UserId, t)
		local d = p and distTo(p.X, p.Z)
		return TEXT.Row.StealTitle, if d then OpsJobs.Dist(d) else ""
	end
	local def = OpsConfig.Get(id)
	local e = cache.Sites[id]
	if def == nil then
		return "", ""
	end
	local title = def.Title
	if e == nil or e.X == nil or e.Z == nil then
		return title, def.Name
	end
	local d = distTo(e.X :: number, e.Z :: number)
	if arrived then
		if def.Kind == "Vault" and (e.State == "Open" or e.State == "Dormant") then
			return title, C.Breach
		end
		local g = e.Guards
		if g ~= nil and g > 0 and (e.State == "Open" or e.State == "Active") then
			return title, string.format(C.Clear, g)
		end
	end
	if d == nil then
		return title, def.Name
	end
	return title, string.format(C.GoTo, def.Name, OpsJobs.Dist(d))
end

refreshCard = function()
	local c = card
	if c == nil then
		return
	end
	local carrying = cache.Carrying ~= nil
	if cardCarryRule ~= carrying then
		cardCarryRule = carrying
		HudLayout.BindVisibility(c, { HideWhen = if carrying then HIDE_CARD_CARRYING else HIDE_CARD }, cardWanted)
	else
		HudLayout.RefreshVisibility(c)
	end
	local x = cardClose
	if x and x.Visible == carrying then
		x.Visible = not carrying -- the bag has to go home: no X while carrying
	end
	if not c.Visible then
		return
	end
	local title, hint = cardText()
	local tl, hl = cardTitle, cardHint
	if tl and tl.Text ~= title then
		tl.Text = title
	end
	if hl and hl.Text ~= hint then
		hl.Text = hint
	end
end

local function layoutCard()
	local c, tl, hl, x = card, cardTitle, cardHint, cardClose
	if not (c and tl and hl and x) then
		return
	end
	local w = math.floor(math.min(OBJ.MaxWidth, HudLayout.TopStackMaxWidthV()))
	local h = OBJ.Height
	c.Size = UDim2.fromOffset(w, h)
	local closeW = math.max(UI.Card.CloseHit, if HudLayout.IsTouch() then 64 else 44)
	x.Size = UDim2.fromOffset(closeW, h)
	local textW = math.max(60, w - CARD_PAD_L - closeW - 4)
	local top = math.max(3, math.floor((h - CARD_TITLE_H - OBJ.HintSize - 4) / 2))
	tl.Position = UDim2.fromOffset(CARD_PAD_L, top)
	tl.Size = UDim2.fromOffset(textW, CARD_TITLE_H)
	hl.Position = UDim2.fromOffset(CARD_PAD_L, top + CARD_TITLE_H)
	hl.Size = UDim2.fromOffset(textW, OBJ.HintSize + 4)
end

local function buildCard(parent: ScreenGui)
	local c = Instance.new("Frame")
	c.Name = "OpsCard"
	c.AnchorPoint = Vector2.new(0.5, 0)
	c.Position = UDim2.new(0.5, 0, 0, HudConfig.TopStack.Top) -- Y is rewritten by HudLayout's top stack
	c.Size = UDim2.fromOffset(OBJ.MaxWidth, OBJ.Height)
	c.BackgroundColor3 = HudConfig.Colors.PillBg
	c.BackgroundTransparency = 0.16
	c.BorderSizePixel = 0
	c.Active = true -- taps on the card never fall through to the world
	c.Visible = false
	c.ZIndex = 2
	c.Parent = parent
	UIUtil.Corner(c, CARD_CORNER)
	UIUtil.Stroke(c, GOLD, 2)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Font = HudConfig.Fonts.Display
	title.TextSize = OBJ.TitleSize
	title.TextColor3 = GOLD
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Text = ""
	title.Active = false
	title.ZIndex = 3
	title.Parent = c
	UIUtil.TextOutline(title, 1.4)

	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.BackgroundTransparency = 1
	hint.Font = HudConfig.Fonts.Body
	hint.TextSize = OBJ.HintSize
	hint.TextColor3 = HudConfig.Colors.White
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextYAlignment = Enum.TextYAlignment.Center
	hint.TextTruncate = Enum.TextTruncate.AtEnd
	hint.Text = ""
	hint.Active = false
	hint.ZIndex = 3
	hint.Parent = c

	-- X: a transparent touch-size hit area (Ui.Card.CloseHit 64 v = 44.8 real px) around a small cross
	local x = Instance.new("TextButton")
	x.Name = "Close"
	x.AnchorPoint = Vector2.new(1, 0.5)
	x.Position = UDim2.new(1, 0, 0.5, 0)
	x.BackgroundTransparency = 1
	x.BorderSizePixel = 0
	x.AutoButtonColor = false
	x.Text = ""
	x.Active = true
	x.Selectable = true
	x.ZIndex = 3
	x.Parent = c
	HudIcons.Make("Close", x, {
		Name = "Icon",
		Size = UDim2.fromOffset(22, 22),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = HudConfig.Colors.White,
		ZIndex = 4,
	})
	x.Activated:Connect(function()
		pcall(AudioController.PlayClick)
		OpsController.Stop()
	end)

	card, cardTitle, cardHint, cardClose = c, title, hint, x
	layoutCard()
	HudLayout.RegisterTopStack("OpsCard", c, HudConfig.TopStack.Order.Objective, { Space = "Hud" })
	HudLayout.AssertTouchTarget(x, "OpsCard.Close")
	refreshCard()
end

---------------------------------------------------------------------------------------------------------------
-- pill
---------------------------------------------------------------------------------------------------------------

local function stageDef(def: OpsConfig.SiteDef, stageId: string): OpsConfig.StageDef?
	for _, st in ipairs(def.Stages) do
		if st.Id == stageId then
			return st
		end
	end
	return nil
end

local function pct(f: number?): number
	local v = tonumber(f) or 0
	if v ~= v then
		v = 0
	end
	return math.floor(math.clamp(v, 0, 1) * 100)
end

--[[ The pill for one progress payload: (title, value, fraction, accent?). Pure; exported for the tests. ]]
function OpsController.PillText(p: Prog, def: OpsConfig.SiteDef?, myCdLeft: number, showWave: boolean): (string, string, number, Color3?)
	local P = TEXT.Pill
	local value = if p.Left ~= nil then OpsJobs.Clock(p.Left) else ""
	local frac = p.Frac or 0
	local b = p.Blocked
	if b == "UnderFire" then
		return P.UnderFire, ProgressPill.Percent(frac), frac, UNDER_FIRE
	elseif b == "Enemy" then
		return P.Enemy, ProgressPill.Percent(frac), frac, UNDER_FIRE
	elseif b == "Vehicle" then
		return P.Vehicle, ProgressPill.Percent(frac), frac, VEHICLE
	elseif b == "Cooldown" then
		return string.format(P.Cooldown, OpsJobs.Clock(myCdLeft)), "", 0, ProgressPill.Colors.Idle
	end
	if showWave and p.Wave ~= nil and p.Waves ~= nil then
		return string.format(P.Wave, p.Wave, p.Waves), value, frac, nil
	end
	local s = p.Stage
	if s == "Breach" then
		return P.Breach, value, frac, nil
	elseif s == "Crack" then
		return string.format(P.Crack, pct(p.Frac)), value, frac, nil
	elseif s == "Hack" then
		return string.format(P.Hack, pct(p.Frac)), value, frac, nil
	elseif s == "Hold" then
		return string.format(P.Hold, pct(p.Frac)), value, frac, nil
	elseif s == "Alarm" then
		local st = def and stageDef(def, "Alarm")
		local total = st and st.Seconds
		local f = if total and total > 0 and p.Left then math.clamp(p.Left / total, 0, 1) else 0
		return string.format(P.Alarm, OpsJobs.Clock(p.Left or 0)), "", f, VEHICLE
	elseif s == "Take" then
		return P.Take, value, frac, nil
	elseif s == "Clear" then
		return string.format(TEXT.Card.Clear, p.Guards or 0), value, frac, nil
	end
	-- Grab / Start / Plant / Recover / Open / Fuse: the stage's own prompt words, else the job title
	local st = def and stageDef(def, s)
	local promptKey = st and st.Prompt
	local words = promptKey and TEXT.Prompts[promptKey]
	if words then
		return string.upper(words), value, frac, nil
	end
	return if def then string.upper(def.Title) else "", value, frac, nil
end

local function refreshPill()
	local pl = pill
	if pl == nil then
		return
	end
	local p = prog
	local show = pillShowing()
	if show and p then
		local def = OpsConfig.Get(p.Site)
		local e = cache.Sites[p.Site]
		local cd = if e then OpsJobs.Remaining(e.MyCd, e.At, now()) else 0
		local title, value, frac, accent = OpsController.PillText(p, def, cd, now() - waveShownAt < WAVE_SHOW_SECONDS)
		if pl.Title.Text ~= title then
			pl.Title.Text = title
		end
		if pl.Value.Text ~= value then
			pl.Value.Text = value
		end
		ProgressPill.SetFraction(pl, frac)
		if accent then
			pl.Title.TextColor3 = accent
			pl.Fill.BackgroundColor3 = accent
			ProgressPill.AccentStroke(pl, accent)
		else
			pl.Title.TextColor3 = ProgressPill.Colors.Title
			pl.Fill.BackgroundColor3 = GOLD
			ProgressPill.ResetStroke(pl)
		end
	end
	HudLayout.RefreshVisibility(pl.Frame)
	refreshCard() -- the card collapses while the pill shows
end

local function onProgress(payload: any)
	if type(payload) ~= "table" or type(payload.Site) ~= "string" then
		return
	end
	if type(payload.Stage) ~= "string" or OpsConfig.Get(payload.Site) == nil then
		if prog and prog.Site == payload.Site then
			prog = nil -- the final {Site} with no Stage: hide
		end
		refreshPill()
		return
	end
	local wave = if finite(payload.Wave) then payload.Wave else nil
	prog = {
		Site = payload.Site,
		Stage = payload.Stage,
		Frac = if finite(payload.Frac) then payload.Frac else nil,
		Blocked = if type(payload.Blocked) == "string" then payload.Blocked else nil,
		Guards = if finite(payload.Guards) then payload.Guards else nil,
		Left = if finite(payload.Left) then math.max(0, payload.Left) else nil,
		Wave = wave,
		Waves = if finite(payload.Waves) then payload.Waves else nil,
	}
	progAt = now()
	if wave and wave ~= lastWave then
		lastWave = wave
		if wave > 1 then
			waveShownAt = progAt
		end
	elseif wave == nil then
		lastWave = 0
	end
	refreshPill()
end

local function buildPill(parent: ScreenGui)
	local p = ProgressPill.Build(parent, "OpsProgress")
	pill = p
	HudLayout.BindVisibility(p.Frame, { HideWhen = { "Dead" } }, function(): boolean
		return running and pillShowing()
	end)
	HudLayout.RegisterTopStack("OpsProgress", p.Frame, HudConfig.TopStack.Order.Progress, { Space = "Hud" })
end

---------------------------------------------------------------------------------------------------------------
-- data
---------------------------------------------------------------------------------------------------------------

local function onData()
	-- carrying a bag: the job becomes "get it home" (auto-tracked, GO = your own Home); delivery / loss ends it
	local carrying = cache.Carrying ~= nil
	if carrying and not wasCarrying then
		local p = OpsJobs.HomeGo(cache)
		if p then
			follow(OpsJobs.HomeId, p)
		end
	end
	wasCarrying = carrying
	followTracked()
	notifyRows()
	refreshCard()
end

--[[ Apply one OpsState payload (the remote handler; exported for the headless tests). ]]
function OpsController.ApplyState(payload: any)
	if not running then
		return
	end
	if OpsJobs.Merge(cache, payload, now()) then
		onData()
	end
end

--[[ Apply one OpsPing payload (exported for the headless tests). ]]
function OpsController.ApplyPing(payload: any)
	if not running then
		return
	end
	if OpsJobs.AddPing(cache, payload, now(), player.UserId) then
		followTracked()
		notifyRows()
	end
end

--[[ Apply one OpsProgress payload (exported for the headless tests). ]]
function OpsController.ApplyProgress(payload: any)
	if not running then
		return
	end
	onProgress(payload)
end

local function bindPing()
	task.spawn(function()
		-- UnreliableRemoteEvent: poll the non-blocking getter (Remotes.GetUnreliableEvent would wait minutes)
		for _ = 1, 60 do
			local ev = Remotes.TryGetUnreliableEvent(Constants.RemoteNames.OpsPing)
			if ev then
				ev.OnClientEvent:Connect(OpsController.ApplyPing)
				return
			end
			task.wait(1)
		end
		warn("[OpsController] OpsPing not found after 60 s; carrier pings off")
	end)
end

local function tick()
	checkMarker()
	if OpsJobs.ExpirePings(cache, now()) then
		followTracked()
		notifyRows()
	end
	followTracked()
	if prog and now() - progAt > PROGRESS_STALE then
		prog = nil
	end
	refreshPill() -- also refreshes the card (countdowns, distance)
end

local function playerGui(): PlayerGui?
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg then
		return pg
	end
	local waited = player:WaitForChild("PlayerGui", 30)
	if waited and waited:IsA("PlayerGui") then
		return waited
	end
	return nil
end

function OpsController.Init()
	if running then
		return
	end
	if OpsConfig.Enabled ~= true then
		return -- Jobs ship off: nothing is built, bound or looped
	end
	local pg = playerGui()
	if not pg then
		warn("[OpsController] no PlayerGui after 30 s; Jobs HUD off")
		return
	end
	running = true
	local s = Instance.new("ScreenGui")
	s.Name = "WarEmpireOps"
	HudLayout.ApplyScreen(s, { Insets = "Core" }) -- Core safe insets + the one HUD UIScale
	s.Parent = pg
	buildPill(s)
	buildCard(s)
	HudLayout.LayoutChanged:Connect(layoutCard)
	HudLayout.FlagChanged:Connect(function(name: string)
		if name == "InOwnPlot" then
			notifyRows() -- distances switch between your gate and your character
		end
	end)

	Remotes.BindEvent(Constants.RemoteNames.OpsState, OpsController.ApplyState)
	Remotes.BindEvent(Constants.RemoteNames.OpsProgress, OpsController.ApplyProgress)
	bindPing()

	-- the JOBS section in the Missions panel
	local ok, mc = pcall(function(): any
		return require(script.Parent.MissionController)
	end)
	if ok and type(mc) == "table" and type(mc.SetJobsSource) == "function" and type(mc.JobsChanged) == "function" then
		host = mc
		mc.SetJobsSource({
			Rows = OpsController.Rows,
			Go = OpsController.Track,
			Stop = OpsController.Stop,
			Version = OpsController.RowsVersion,
		})
	else
		warn("[OpsController] MissionController has no JOBS section; the board is off:", mc)
	end

	task.spawn(function()
		while running do
			task.wait(TICK)
			local okT, err = pcall(function(): any
				tick()
				return nil
			end)
			if not okT then
				warn("[OpsController] tick failed:", err)
			end
		end
	end)
	print("[WAR EMPIRE] OpsController ready")
end

-- test hook: the headless harness flips OpsConfig.Enabled before Init; nothing else calls this
function OpsController._Cache(): OpsJobs.Cache
	return cache
end

return OpsController
