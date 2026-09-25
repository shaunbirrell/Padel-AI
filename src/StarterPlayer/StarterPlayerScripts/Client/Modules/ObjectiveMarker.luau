--!strict
--[[
	WAR EMPIRE W3 step 2 — ObjectiveMarker: the one AlwaysOnTop objective marker for jobs (spec scratchpad w3s2 §3:
	"AlwaysOnTop: only ObjectiveMarker"; §6 Phase A lanes L0 / U0 / M0, Phase B lane U).

	FROZEN API (lane L0; lane M0's MissionController GO and later OpsController call it):
	  ObjectiveMarker.Show(target)            target = { Short: string, X: number, Y: number, Z: number }: world studs
	                                          of the objective's standing surface and a short device-neutral label
	                                          ("BANK"); replaces the current one. An invalid target (empty label,
	                                          non-finite position) is ignored with one warning.
	  ObjectiveMarker.Clear()                 removes the current target (no-op when there is none)
	  ObjectiveMarker.Current() -> Target?    a copy of the current target, or nil
	Additive (lane U0, read-only helpers for other client code; no allocation):
	  ObjectiveMarker.Revision() -> number    bumps on every Show / Clear / arrival / timeout (callers re-read Current()
	                                          only when it changed: CompassController's tracked mode)
	  ObjectiveMarker.Showing() -> boolean    this marker is drawn: a target is set and ConsoleWaypoint is not guiding
	  ObjectiveMarker.OnTop() -> boolean      an objective marker is drawing AlwaysOnTop right now (this one, or the
	                                          ConsoleWaypoint line it yields to): TerritoryController's contested
	                                          diamond yields to it, so only ONE AlwaysOnTop label is on screen
	Additive (Phase B lane U; OpsController follows a job with them, the frozen three are unchanged):
	  ObjectiveMarker.ShowWith(target, opts?) Show with this target's own arrival radius / timeout
	                                          (opts = { ArriveStuds?, TimeoutSeconds? }: OpsConfig.Ui for jobs);
	                                          Show(target) = ShowWith(target, nil) = the OBJ numbers below
	  ObjectiveMarker.Move(x, y, z) -> boolean  the current target moved (a carried bag, a rotating cache): same label,
	                                          same timeout, the line and marker follow without a rebuild; Revision()
	                                          bumps. false when there is no target or the point is not finite
	  ObjectiveMarker.Ended() -> string?      how the last target ended: "Arrived" | "Timeout" | "Cleared" (Clear(),
	                                          a ConsoleWaypoint GO); nil while one is set (a Show over a Show just
	                                          replaces it: Revision() tells the old owner)

	What it draws (client only, nothing replicates, 0 parts): an invisible Attachment in Workspace.Terrain at the
	target (+ MarkerLift), a thin Beam from the local character to it (the "GO line"), and ONE BillboardGui on it:
	the label ("BANK") over the distance ("620m"), 14-20 px text, AlwaysOnTop = true — the only AlwaysOnTop label the
	game draws on purpose (WE_LabelRole "objective", WorldLabel.SetRole). It is transient: only after a GO, and gone
	on arrival (ArriveRadius), after TimeoutSeconds, on Clear() or on the next Show().

	Yields to ConsoleWaypoint: while ConsoleWaypoint.Current() ~= nil (a Base-panel GO or the tutorial's guide line
	to your own console / ATM) the line and marker are hidden (Enabled = false) and come back when that line ends.
	ConsoleWaypoint is required lazily, so Phase B's two ConsoleWaypoint lines that call ObjectiveMarker.Clear() cannot
	make a require cycle. Phase B (lane U): the latest GO wins both ways — a console GO clears this marker (those two
	lines) and a Show / ShowWith ends a running console line (ConsoleWaypoint.Clear()), so the yield is only a guard.

	Cost: one Heartbeat connection only while a target is set; the work inside runs at <= RefreshHz (<= 10 Hz, the
	CLAUDE.md UI refresh cap): arrival / timeout / yield checks and a distance text rewritten only when the shown
	value changes. No unbounded WaitForChild, no whole-tree scan, no remote, nothing per frame beyond the accumulator.
	Streaming-safe: it never looks up a workspace part; the target is the position the caller (the server's data)
	gave, and the character is found with FindFirstChild each tick (respawn → the line re-attaches).
	Look: the ConsoleWaypoint line's config (ConsoleBuyConfig.Waypoint) so both guide lines look the same; the
	three objective-only numbers are OBJ below (they move to OpsConfig.Ui with Phase B lane O, ASSUMPTIONS U0-1).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60) -- ships with the place (Rojo); bounded wait anyway
local ConsoleBuyConfig = require(Shared.Configs.ConsoleBuyConfig)
local WorldLabel = require(Shared.Util.WorldLabel)

export type Target = { Short: string, X: number, Y: number, Z: number }
export type Opts = { ArriveStuds: number?, TimeoutSeconds: number? }

local ObjectiveMarker = {}

local W = ConsoleBuyConfig.Waypoint
-- objective-only tunables (world studs / seconds); see the header
local OBJ = {
	ArriveRadius = 24, -- cleared when the character is this close (3D) to the target: "you are there"
	TimeoutSeconds = 600, -- a forgotten marker goes away after 10 min
	MarkerLift = 6, -- studs above the target's standing surface (the line ends there too)
	TitlePx = 20, -- "BANK" (real px; a BillboardGui has no UIScale)
	DistancePx = 16, -- "620m"
	MaxLabelChars = 12,
}
local PERIOD = 1 / math.clamp(W.RefreshHz, 1, 10) -- CLAUDE.md: UI refresh <= 10 Hz

local player = Players.LocalPlayer

local current: Target? = nil
local warnedBad = false
local revision = 0
local arriveR = OBJ.ArriveRadius -- this target's (ShowWith opts, else OBJ)
local timeoutS = OBJ.TimeoutSeconds
local ended: string? = nil -- Ended()
local startedAt = 0
local lastAttemptAt = -math.huge
local stepConn: RBXScriptConnection? = nil
local stepAcc = 0
local yielded = false
local stepKey = -1 -- distKey of the distance text on screen

-- visuals (all client-only)
local anchor: Attachment? = nil -- in Workspace.Terrain at the target (+ MarkerLift)
local att0: Attachment? = nil -- on the character's HumanoidRootPart
local beam: Beam? = nil
local marker: BillboardGui? = nil
local distLabel: TextLabel? = nil

---------------------------------------------------------------------------------------------------------------
-- ConsoleWaypoint (read only, lazy: see the header)
---------------------------------------------------------------------------------------------------------------

type ConsoleWaypointApi = { Current: () -> string?, Clear: (() -> ())? }
local ConsoleWaypoint: ConsoleWaypointApi? = nil
local cwTried = false

-- true while ConsoleWaypoint is guiding (its own AlwaysOnTop line and marker are up)
local function consoleGuiding(): boolean
	if not cwTried then
		cwTried = true
		local ok, mod = pcall(function(): any
			return require(script.Parent.ConsoleWaypoint)
		end)
		if ok and type(mod) == "table" and type(mod.Current) == "function" then
			ConsoleWaypoint = mod
		else
			warn("[ObjectiveMarker] ConsoleWaypoint unavailable; the marker never yields:", mod)
		end
	end
	if ConsoleWaypoint == nil then
		return false
	end
	return ConsoleWaypoint.Current() ~= nil
end

-- Phase B: a new objective ends a running console line (the latest GO wins; the console GO clears us likewise)
local function endConsoleLine()
	if not consoleGuiding() then
		return
	end
	local cw = ConsoleWaypoint
	local clear = cw and cw.Clear
	if clear then
		local ok, err = pcall(function(): any
			clear()
			return nil
		end)
		if not ok then
			warn("[ObjectiveMarker] ConsoleWaypoint.Clear failed:", err)
		end
	end
end

---------------------------------------------------------------------------------------------------------------

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -1e7 and n < 1e7
end

local function rootPart(): BasePart?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

-- The distance line: "95m" under 1 km, "1.2km" above (the compass chip's format). distKey is the shown value, so
-- the text is rebuilt only when what the player sees changes.
local function distKey(metres: number): number
	if metres < 1000 then
		return metres
	end
	return 100000 + math.floor(metres / 100 + 0.5)
end

local function distText(key: number): string
	if key < 100000 then
		return string.format("%dm", key)
	end
	return string.format("%.1fkm", (key - 100000) / 10)
end

local function destroyVisuals()
	local b, m, a, a0 = beam, marker, anchor, att0
	beam, marker, anchor, att0, distLabel = nil, nil, nil, nil, nil
	if b then
		b:Destroy()
	end
	if m then
		m:Destroy()
	end
	if a then
		a:Destroy()
	end
	if a0 then
		a0:Destroy()
	end
	stepKey = -1
end

local function applyEnabled()
	local on = not yielded
	local b, m = beam, marker
	if b and b.Enabled ~= on then
		b.Enabled = on
	end
	if m and m.Enabled ~= on then
		m.Enabled = on
	end
end

-- the line's start on the (current) character; nil while respawning
local function attachStart(): boolean
	local hrp = rootPart()
	local b = beam
	if hrp == nil or b == nil then
		return false
	end
	local a0 = att0
	if a0 and a0.Parent == hrp then
		return true
	end
	if a0 then
		a0:Destroy()
	end
	local na = Instance.new("Attachment")
	na.Name = "WE_ObjectiveAtt0"
	na.Parent = hrp
	att0 = na
	b.Attachment0 = na
	return true
end

local function textLabel(name: string, y: number, h: number, px: number, color: Color3, parent: Instance): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(0, y)
	l.Size = UDim2.new(1, 0, 0, h)
	l.Font = Enum.Font.GothamBold
	l.TextScaled = false
	l.TextSize = px
	l.TextColor3 = color
	l.TextStrokeColor3 = Color3.new(0, 0, 0)
	l.TextStrokeTransparency = 0.35
	l.Text = ""
	l.Parent = parent
	return l
end

-- (re)build the anchor, line and marker for the current target; false when it cannot yet (no Terrain)
local function build(): boolean
	lastAttemptAt = os.clock()
	local c = current
	if c == nil then
		return false
	end
	destroyVisuals()
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain == nil then
		return false
	end
	local a = Instance.new("Attachment")
	a.Name = "WE_ObjectiveAnchor"
	a.Position = Vector3.new(c.X, c.Y + OBJ.MarkerLift, c.Z) -- Terrain's frame is the world frame
	a.Parent = terrain
	anchor = a

	local b = Instance.new("Beam")
	b.Name = "WE_ObjectiveBeam"
	b.Attachment1 = a
	b.FaceCamera = true
	b.Segments = 1
	b.Width0 = W.BeamWidth0
	b.Width1 = W.BeamWidth1
	b.LightEmission = W.BeamLightEmission
	b.Color = ColorSequence.new(W.BeamColor)
	b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0.85) })
	b.Parent = terrain -- not on the character: only the start attachment is rebuilt after a respawn
	beam = b
	attachStart()

	local title = string.upper(string.sub(c.Short, 1, OBJ.MaxLabelChars))
	local bb = Instance.new("BillboardGui")
	bb.Name = "WE_ObjectiveMarker"
	bb.Adornee = a
	-- real px (a BillboardGui has no UIScale); the width follows the label like the console marker
	bb.Size = UDim2.fromOffset(math.clamp(#title * 12 + 16, W.MarkerMinWidth, W.MarkerMaxWidth), OBJ.TitlePx + OBJ.DistancePx + 8)
	bb.LightInfluence = 0
	bb.Active = false
	bb.ClipsDescendants = false
	bb.AlwaysOnTop = true -- the ONE objective marker (CLAUDE.md world labels); transient, after GO only
	WorldLabel.SetRole(bb, "objective") -- WE_LabelRole: LabelGovernor / WorldLabelPolicy leave it on top
	local t = textLabel("Title", 0, OBJ.TitlePx + 4, OBJ.TitlePx, W.BeamColor, bb)
	t.Text = title
	distLabel = textLabel("Distance", OBJ.TitlePx + 4, OBJ.DistancePx + 4, OBJ.DistancePx, Color3.new(1, 1, 1), bb)
	bb.Parent = a
	marker = bb
	applyEnabled()
	return true
end

local function stop()
	local conn = stepConn
	stepConn = nil
	if conn then
		conn:Disconnect()
	end
end

local function clearNow(reason: string)
	stop()
	destroyVisuals()
	if current ~= nil then
		current = nil
		revision += 1
		ended = reason
	end
	yielded = false
end

local function step(dt: number)
	stepAcc += dt
	if stepAcc < PERIOD then
		return
	end
	stepAcc = 0
	local c = current
	if c == nil then
		clearNow("Cleared")
		return
	end
	local now = os.clock()
	if now - startedAt > timeoutS then
		clearNow("Timeout")
		return
	end
	local hrp = rootPart()
	-- arrival: counts even while yielding (you are there, whatever line is up)
	if hrp then
		local p = hrp.Position
		local dx, dy, dz = p.X - c.X, p.Y - c.Y, p.Z - c.Z
		if dx * dx + dy * dy + dz * dz <= arriveR * arriveR then
			clearNow("Arrived")
			return
		end
	end
	local y = consoleGuiding()
	if y ~= yielded then
		yielded = y
		applyEnabled()
	end
	-- rebuild when something removed the visuals; re-attach the line after a respawn (throttled)
	local m, a0 = marker, att0
	local broken = m == nil or m.Parent == nil or anchor == nil or (anchor :: Attachment).Parent == nil
	local detached = hrp ~= nil and (a0 == nil or a0.Parent ~= hrp)
	if (broken or detached) and now - lastAttemptAt >= W.RetrySeconds then
		lastAttemptAt = now
		if broken then
			build()
		else
			attachStart()
		end
	end
	if yielded or hrp == nil then
		return
	end
	local p = (hrp :: BasePart).Position
	local dx, dz = p.X - c.X, p.Z - c.Z
	local metres = math.floor(math.sqrt(dx * dx + dz * dz))
	local key = distKey(metres)
	local dl = distLabel
	if dl and key ~= stepKey then
		stepKey = key
		dl.Text = distText(key)
	end
end

---------------------------------------------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------------------------------------------

function ObjectiveMarker.ShowWith(target: Target, opts: Opts?)
	local t: any = target
	if type(t) ~= "table" or type(t.Short) ~= "string" or t.Short == "" or not (finite(t.X) and finite(t.Y) and finite(t.Z)) then
		if not warnedBad then
			warnedBad = true
			warn("[ObjectiveMarker] Show ignored an invalid target (want { Short = string, X, Y, Z = numbers })")
		end
		return
	end
	stop()
	endConsoleLine()
	local o: any = opts
	arriveR = if type(o) == "table" and finite(o.ArriveStuds) then math.clamp(o.ArriveStuds, 4, 200) else OBJ.ArriveRadius
	timeoutS = if type(o) == "table" and finite(o.TimeoutSeconds) then math.clamp(o.TimeoutSeconds, 10, 3600) else OBJ.TimeoutSeconds
	current = { Short = t.Short, X = t.X, Y = t.Y, Z = t.Z }
	revision += 1
	ended = nil
	startedAt = os.clock()
	yielded = consoleGuiding()
	build() -- the line starts at once (or after a respawn: step() retries)
	stepAcc = math.huge -- first step runs on the next Heartbeat (distance text)
	stepConn = RunService.Heartbeat:Connect(step)
end

function ObjectiveMarker.Show(target: Target)
	ObjectiveMarker.ShowWith(target, nil)
end

function ObjectiveMarker.Clear()
	clearNow("Cleared")
end

function ObjectiveMarker.Move(x: number, y: number, z: number): boolean
	local c = current
	if c == nil or not (finite(x) and finite(y) and finite(z)) then
		return false
	end
	if c.X == x and c.Y == y and c.Z == z then
		return true
	end
	c.X, c.Y, c.Z = x, y, z
	revision += 1
	local a = anchor
	if a then
		a.Position = Vector3.new(x, y + OBJ.MarkerLift, z)
	end
	stepKey = -1 -- the distance text is rewritten on the next step
	return true
end

function ObjectiveMarker.Ended(): string?
	if current ~= nil then
		return nil
	end
	return ended
end

function ObjectiveMarker.Current(): Target?
	local c = current
	if c == nil then
		return nil
	end
	return { Short = c.Short, X = c.X, Y = c.Y, Z = c.Z }
end

function ObjectiveMarker.Revision(): number
	return revision
end

function ObjectiveMarker.Showing(): boolean
	return current ~= nil and not consoleGuiding()
end

function ObjectiveMarker.OnTop(): boolean
	return current ~= nil or consoleGuiding()
end

return ObjectiveMarker
