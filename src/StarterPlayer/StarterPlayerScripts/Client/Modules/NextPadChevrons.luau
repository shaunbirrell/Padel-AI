--!strict
--[[
	F5 (owner's 11 features, lane G): gold floor chevrons from the player to the next pad, on the player's OWN plot.
	Client-only and owner-only by construction (local parts under this client's camera; nothing is sent to or read
	from the server beyond the replicated state below). Display only: the server re-checks every buy.

	Target (TycoonMath.GuideTarget, the one pointer shared with the console NEXT tag):
	  * while the tutorial runs (TycoonGuideConfig.Chevrons.FollowTutorial): the active step's own pad (PadBuy steps),
	    the own ATM (Pointer "ATM", the Collect cash step), else nothing (claim / recruit / outpost / 4x4);
	  * afterwards: the server pick WE_NextBuy (the cheapest unpaid pad), else the local TycoonMath.PickCheapest over
	    the last BaseStateUpdate.Upgrades. Soldiers / nothing left -> no chevrons.
	  The tutorial step comes from TutorialStateUpdate (or PlayerStateUpdate). If that push reached another listener
	  before this module connected, the HudLayout "Tutorial" flag still says a step is up: then no chevrons until the
	  step is known, never the post-tutorial pick by mistake.
	Where: TycoonMath.ApproachPoint(id) (plot-local: a walk-in's door + DoorLeadStuds, a kiosk, the ATM) through
	Shared/Util/PlotFrame into the own plot's frame. Config only: nothing here waits for a part to stream in. The own
	plot id is BaseStateUpdate / PlayerStateUpdate PlotId, else the plot that holds the server-stamped WE_AtmPos /
	WE_ConsolePos_CommandCenter (retried every RetargetRetrySeconds until known).
	Layout (TycoonMath.ChevronCount): chevron k (1..Count) sits LeadStuds + (k - 1) x SpacingStuds along the straight
	line to the target; the count stops StopShortStuds before it and is 0 within HideWithinStuds. A chevron that would
	touch a TycoonMath.Footprints rectangle or the own pad's edge (its whole reach, about 2 studs, stays clear) is left
	out (the others keep their spacing). Each
	chevron is two BarSize bars meeting at a tip that points at the target (+-BarAngleDeg), BarY = pad top + Lift;
	transparency runs TransparencyNear (nearest the player) to TransparencyFar.
	Hidden: outside the own plot, any TycoonGuideConfig.Chevrons.HideWhen HudLayout flag (Driving, Dead, RecentCombat,
	Drawn, Modal, AtConsole), while the GO beam is up (ConsoleWaypoint), no target, or within HideWithinStuds.

	Phone cost: a pool of 2 x Count Parts in Workspace.CurrentCamera.WE_NextChevrons (Anchored, CanCollide / CanTouch /
	CanQuery off, CastShadow = false, SmoothPlastic; no special material, no light, no GUI), built once. One Heartbeat
	accumulator: the per-frame path only adds dt. At RefreshHz (<= 10) it re-lays the chevrons only when the character
	moved MoveThresholdStuds or the target changed, moving all of them with one Workspace:BulkMoveTo into
	preallocated arrays; a pass that re-lays nothing allocates nothing. No per-frame scans, no yields.
	Off (Init returns at once) while TycoonGuideConfig.Chevrons.Enabled is false.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60) -- Bootstrap already waited for it; bounded anyway
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local BaseConfig = require(Shared.Configs.BaseConfig)
local TutorialConfig = require(Shared.Configs.TutorialConfig)
local TycoonGuideConfig = require(Shared.Configs.TycoonGuideConfig)
local TycoonMath = require(Shared.Util.TycoonMath)
local PlotFrame = require(Shared.Util.PlotFrame)

local HudLayout = require(script.Parent.HudLayout)
local ConsoleWaypoint = require(script.Parent.ConsoleWaypoint)

local NextPadChevrons = {}

local C = TycoonGuideConfig.Chevrons
local COUNT = math.max(1, math.floor(C.Count))
local POOL = 2 * COUNT
local LEAD = C.LeadStuds
local SPACING = C.SpacingStuds
local BAR_LEN = C.BarSize.Z
local ARM = math.rad(C.BarAngleDeg)
local COS_ARM, SIN_ARM = math.cos(ARM), math.sin(ARM)
local APEX = 0.5 * BAR_LEN * COS_ARM -- the tip sits this far ahead of the chevron's centre point
local MOVE2 = C.MoveThresholdStuds * C.MoveThresholdStuds
local PERIOD = 1 / math.clamp(C.RefreshHz, 1, 10) -- <= 10 Hz (CLAUDE.md UI refresh cap)
local RETRY = math.max(0.25, C.RetargetRetrySeconds)
local HALF_PAD = BaseConfig.PlotSize.X * 0.5 -- the own pad (plot-local square)
-- how far a chevron reaches from its centre point: the arm ends (half a bar behind the centre along the line, a whole
-- bar x sin(BarAngleDeg) to the side) plus half a bar's width. That much stays clear of the pad edge and of every
-- footprint, so no bar pokes into a building or off the pad.
local CLEAR = math.sqrt((0.5 * BAR_LEN * COS_ARM) ^ 2 + (BAR_LEN * SIN_ARM) ^ 2) + 0.5 * C.BarSize.X
local FOLDER_NAME = "WE_NextChevrons"
-- server-stamped world positions on the own plot (the plot id when no state push has named it yet)
local PLOT_HINT_ATTRS = { "WE_AtmPos", "WE_ConsolePos_CommandCenter" }

type Step = { PadStructureId: string?, Pointer: string? }

local player = Players.LocalPlayer
local started = false

-- replicated state (events)
local plotId: number? = nil
local upgrades: { [string]: any }? = nil
local tutKnown = false -- a TutorialStateUpdate / PlayerStateUpdate tutorial field has arrived
local tutStep: Step? = nil -- the active step (nil = none / complete)
local payloadStep: Step = { PadStructureId = nil, Pointer = nil } -- reused for a step Id this client does not know

-- target (plot-local tlx/tlz, world twx/twz), refreshed by retarget()
local hasTarget = false
local targetId: string? = nil
local plotCF: CFrame = CFrame.identity
local tlx, tlz, twx, twz = 0, 0, 0, 0
local barY = 0
local retargetDue = true
local retryAt = 0

-- layout
local laid = false -- chevrons are laid out for (lastX, lastZ) and the current target
local lastX, lastZ = 0, 0
local folder: Folder? = nil
local parts: { BasePart } = {}
local cframes: { CFrame } = {}
local shownT: { number } = {} -- the Transparency each part was last given (writes only on change)
local forceTick = true

-- ── pure helpers (tests call these) ───────────────────────────────────────────────────────────────────────────

--[[ The active step as GuideTarget wants it (nil once the tutorial is complete / skipped), and `unknown` = true while
	a step is up on the HUD but its Id has not reached this module (then: no pointer until it has). ]]
function NextPadChevrons.ActiveStep(): (Step?, boolean)
	if tutKnown then
		return tutStep, false
	end
	return nil, HudLayout.GetFlag("Tutorial")
end

-- The plot (1..MaxPlots) whose pad square holds world point `pos` (with `margin` studs of slack), else nil
function NextPadChevrons.PlotAt(pos: Vector3, margin: number?): number?
	local half = HALF_PAD + (margin or 0)
	for id = 1, BaseConfig.MaxPlots do
		local pp = PlotFrame.PlotPosition(id)
		if pp ~= nil then
			local l = PlotFrame.PlotCFrame(pp):PointToObjectSpace(pos)
			if math.abs(l.X) <= half and math.abs(l.Z) <= half then
				return id
			end
		end
	end
	return nil
end

--[[ Chevron k (1..count) for a player at plot-local (lx, lz) heading to plot-local (tx, tz): its centre along the
	line, or nil when it is left out (inside a footprint / off the pad). Returns (cx, cz, dirX, dirZ) plot-local. ]]
function NextPadChevrons.Slot(lx: number, lz: number, tx: number, tz: number, k: number): (number?, number, number, number)
	local dx, dz = tx - lx, tz - lz
	local d = math.sqrt(dx * dx + dz * dz)
	if d <= 0 then
		return nil, 0, 0, 0
	end
	local ux, uz = dx / d, dz / d
	local s = LEAD + (k - 1) * SPACING
	local cx, cz = lx + ux * s, lz + uz * s
	if math.abs(cx) > HALF_PAD - CLEAR or math.abs(cz) > HALF_PAD - CLEAR then
		return nil, cx, cz, 0
	end
	if TycoonMath.InFootprint(cx, cz, CLEAR) ~= nil then
		return nil, cx, cz, 0
	end
	return cx, cz, ux, uz
end

-- ── state ─────────────────────────────────────────────────────────────────────────────────────────────────────

local function markRetarget()
	retargetDue = true
	forceTick = true
end

local function ownPlot(): number?
	if plotId ~= nil then
		return plotId
	end
	for _, name in ipairs(PLOT_HINT_ATTRS) do
		local v = player:GetAttribute(name)
		if typeof(v) == "Vector3" then
			local id = NextPadChevrons.PlotAt(v, 24)
			if id ~= nil then
				return id
			end
		end
	end
	return nil
end

local function stepFromId(id: any, pad: any, pointer: any): Step?
	if typeof(id) == "string" then
		local i = TutorialConfig.IndexOf(id)
		local def = if i ~= nil then TutorialConfig.Steps[i] else nil
		if def ~= nil then
			return def
		end
	end
	-- a step this client's config does not list (older client, newer server): the push carries what we need
	payloadStep.PadStructureId = if typeof(pad) == "string" then pad else nil
	payloadStep.Pointer = if typeof(pointer) == "string" then pointer else nil
	return payloadStep
end

local function onTutorial(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	tutKnown = true
	if payload.Complete == true then
		tutStep = nil
	else
		tutStep = stepFromId(payload.Id, payload.PadStructureId, payload.Pointer)
	end
	markRetarget()
end

local function applyPlot(v: any)
	if typeof(v) == "number" and v ~= plotId then
		plotId = v
		markRetarget()
	end
end

local function onBase(base: any)
	if typeof(base) ~= "table" then
		return
	end
	applyPlot(base.PlotId)
	if typeof(base.Upgrades) == "table" then
		upgrades = base.Upgrades
		markRetarget()
	end
end

local function onPlayerState(state: any)
	if typeof(state) ~= "table" then
		return
	end
	onBase(state.Base)
	if state.TutorialComplete == true then
		tutKnown = true
		tutStep = nil
		markRetarget()
	elseif state.TutorialComplete == false and typeof(state.TutorialStep) == "number" then
		local def = TutorialConfig.GetStep(state.TutorialStep)
		if def ~= nil then
			tutKnown = true
			tutStep = def
			markRetarget()
		end
	end
end

-- ── pool ──────────────────────────────────────────────────────────────────────────────────────────────────────

local function ensurePool(): boolean
	local cam = Workspace.CurrentCamera
	if cam == nil then
		return false
	end
	local f = folder
	if f ~= nil and f.Parent ~= nil and #parts == POOL and parts[1].Parent == f then
		if f.Parent ~= cam then
			f.Parent = cam
		end
		return true
	end
	-- first use, or the old camera (and the pool with it) went away: build it again
	if f ~= nil then
		f:Destroy()
	end
	laid = false
	local nf = Instance.new("Folder")
	nf.Name = FOLDER_NAME
	table.clear(parts)
	table.clear(cframes)
	table.clear(shownT)
	for i = 1, POOL do
		local p = Instance.new("Part")
		p.Name = "Chevron"
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic
		p.Color = C.Color
		p.Size = C.BarSize
		p.Transparency = 1
		p.CFrame = CFrame.identity
		p.Parent = nf
		parts[i] = p
		cframes[i] = CFrame.identity
		shownT[i] = 1
	end
	nf.Parent = cam
	folder = nf
	return true
end

local function setT(i: number, t: number)
	if shownT[i] ~= t then
		shownT[i] = t
		parts[i].Transparency = t
	end
end

local function hideParts()
	for i = 1, #parts do
		setT(i, 1)
	end
end

-- hidden for a reason other than where the character stands: lay out again once it is shown
local function hideAll()
	laid = false
	hideParts()
end

-- ── target + layout ───────────────────────────────────────────────────────────────────────────────────────────

local function retarget()
	retargetDue = false
	hasTarget = false
	laid = false
	local pid = ownPlot()
	local pos = if pid ~= nil then PlotFrame.PlotPosition(pid) else nil
	if pid == nil or pos == nil then
		retryAt = os.clock() + RETRY -- the plot id is not known yet: try again soon
		return
	end
	local step, unknown = NextPadChevrons.ActiveStep()
	if unknown then
		return -- a tutorial step is up but not known here yet: its push retargets
	end
	local id = TycoonMath.GuideTarget(step, player:GetAttribute("WE_NextBuy"), upgrades)
	targetId = id
	local lp = if id ~= nil then TycoonMath.ApproachPoint(id) else nil
	if lp == nil then
		return
	end
	plotCF = PlotFrame.PlotCFrame(pos)
	tlx, tlz = lp.X, lp.Z
	local w = plotCF:PointToWorldSpace(Vector3.new(tlx, 0, tlz))
	twx, twz = w.X, w.Z
	barY = pos.Y + BaseConfig.PlotSize.Y * 0.5 + C.Lift
	hasTarget = true
end

local function hiddenByFlags(): boolean
	for _, name in ipairs(C.HideWhen) do
		if HudLayout.GetFlag(name) then
			return true
		end
	end
	return ConsoleWaypoint.Current() ~= nil -- the GO beam is up: one pointer at a time
end

-- one bar of chevron `k` (side -1 / +1): its centre is half a bar behind the tip along the arm
local function barCFrame(tipX: number, tipZ: number, ux: number, uz: number, side: number): CFrame
	-- arm = the backward direction (-ux, -uz) turned by side x ARM
	local s = side * SIN_ARM
	local ax = -ux * COS_ARM + uz * s
	local az = -uz * COS_ARM - ux * s
	local h = 0.5 * BAR_LEN
	-- bar length (local Z) along the arm, Y up, X = Y x Z
	return CFrame.new(tipX + ax * h, barY, tipZ + az * h, az, 0, ax, 0, 1, 0, -ax, 0, az)
end

-- lay the chevrons out for a character at (px, py, pz); the answer (shown or not) holds until it moves again
local function layout(px: number, py: number, pz: number)
	laid = true
	lastX, lastZ = px, pz
	local l = plotCF:PointToObjectSpace(Vector3.new(px, py, pz))
	local lx, lz = l.X, l.Z
	if math.abs(lx) > HALF_PAD or math.abs(lz) > HALF_PAD then
		hideParts() -- not on the own plot
		return
	end
	local dx, dz = tlx - lx, tlz - lz
	local d = math.sqrt(dx * dx + dz * dz)
	local count = TycoonMath.ChevronCount(d)
	if count <= 0 then
		hideParts() -- arrived (within HideWithinStuds)
		return
	end
	-- world direction (the plot frame only turns about Y, so world and plot-local distances agree)
	local wx, wz = twx - px, twz - pz
	local wd = math.sqrt(wx * wx + wz * wz)
	if wd <= 0 then
		hideParts()
		return
	end
	local ux, uz = wx / wd, wz / wd
	local any = false
	local span = math.max(1, COUNT - 1)
	for k = 1, COUNT do
		local i1, i2 = 2 * k - 1, 2 * k
		local cx = if k <= count then NextPadChevrons.Slot(lx, lz, tlx, tlz, k) else nil
		if cx ~= nil then
			local s = LEAD + (k - 1) * SPACING
			local tipX, tipZ = px + ux * (s + APEX), pz + uz * (s + APEX)
			cframes[i1] = barCFrame(tipX, tipZ, ux, uz, -1)
			cframes[i2] = barCFrame(tipX, tipZ, ux, uz, 1)
			local t = C.TransparencyNear + (C.TransparencyFar - C.TransparencyNear) * (k - 1) / span
			setT(i1, t)
			setT(i2, t)
			any = true
		else
			setT(i1, 1)
			setT(i2, 1)
		end
	end
	if any then
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function tick()
	if not ensurePool() then
		return
	end
	if retargetDue or (not hasTarget and os.clock() >= retryAt and plotId == nil) then
		retarget()
	end
	if not hasTarget or hiddenByFlags() then
		hideAll() -- writes only parts still showing (a target that just went away included)
		return
	end
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if hrp == nil or not hrp:IsA("BasePart") then
		hideAll()
		return
	end
	local p = (hrp :: BasePart).Position
	if laid then
		local mx, mz = p.X - lastX, p.Z - lastZ
		if mx * mx + mz * mz < MOVE2 then
			return -- nothing moved: nothing to do (no allocation)
		end
	end
	layout(p.X, p.Y, p.Z)
end

-- test / debug: the resolved target id and whether any chevron shows
function NextPadChevrons.State(): (string?, boolean, number)
	local shown = 0
	for i = 1, #parts, 2 do
		if shownT[i] ~= 1 then
			shown += 1
		end
	end
	return (if hasTarget then targetId else nil), shown > 0, shown
end

function NextPadChevrons.Tick()
	tick()
end

function NextPadChevrons.Init()
	if started or C.Enabled ~= true then
		return
	end
	started = true
	Remotes.BindEvent(Constants.RemoteNames.TutorialStateUpdate, onTutorial)
	Remotes.BindEvent(Constants.RemoteNames.BaseStateUpdate, onBase)
	Remotes.BindEvent(Constants.RemoteNames.PlayerStateUpdate, onPlayerState)
	player:GetAttributeChangedSignal("WE_NextBuy"):Connect(markRetarget)
	for _, name in ipairs(PLOT_HINT_ATTRS) do
		player:GetAttributeChangedSignal(name):Connect(function()
			if plotId == nil then
				markRetarget()
			end
		end)
	end
	player.CharacterAdded:Connect(markRetarget)
	HudLayout.FlagChanged:Connect(function(name: string)
		if name == "Tutorial" then
			markRetarget()
		elseif table.find(C.HideWhen, name) ~= nil then
			forceTick = true -- hide / show on the next frame, not the next refresh
		end
	end)
	local acc = PERIOD -- first pass on the first beat
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < PERIOD and not forceTick then
			return
		end
		acc = 0 -- reset, never catch up
		forceTick = false
		tick()
	end)
end

return NextPadChevrons
