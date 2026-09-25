--!strict
--[[
	v71 console-only buying: Base panel GO -> a guide line and a small marker to that structure's console on YOUR plot.
	Never buys (buying happens at the console: BUY button in the action lane or the console prompt).

	Target: the real console part (Shared/Util/ConsoleLocator.Find(plotId, sid)). When the plot id is not known yet or
	the part is not on this client (StreamingEnabled streamed it out), the server-stamped player attribute
	WE_ConsolePos_<StructureId> (world Vector3 of YOUR console, set by UpgradePadService on plot ready) anchors a
	local invisible part until the real console is found.
	Cleared on arrival (ArriveRadius), timeout, another GO or Clear(); re-attached after respawn. Rebuild / retarget
	attempts are throttled to Waypoint.RetrySeconds; the distance label refreshes at Waypoint.RefreshHz (<= 10 Hz,
	CLAUDE.md UI refresh cap) and only rewrites its text when the whole-metre value changes. No WaitForChild; no
	remote calls.
	The marker is the one AlwaysOnTop objective marker (CLAUDE.md world labels): transient, only after GO, 14-20 px
	text (UITextSizeConstraint), sized to the structure name so long names never shrink below 14 px.
	v72 guide: ShowAtm(plotId?) draws the same line to the player's OWN ATM (the "Collect at your ATM" state of the BUY
	button and the guide chip). Target: the own WE_MoneyCollector part (PlotId = plotId) when it is on this client,
	else the server-stamped WE_AtmPos (streaming-safe; never another player's ATM). Same beam, marker, arrival, timeout
	and RefreshHz rules as a console line; the marker reads TycoonGuideConfig.Text.ChipGoCollect ("ATM").
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local BaseConfig = require(Shared.Configs.BaseConfig)
local ConsoleBuyConfig = require(Shared.Configs.ConsoleBuyConfig)
local TycoonGuideConfig = require(Shared.Configs.TycoonGuideConfig)
local ConsoleLocator = require(Shared.Util.ConsoleLocator)

local ConsoleWaypoint = {}

local player = Players.LocalPlayer
local W = ConsoleBuyConfig.Waypoint

local current: string? = nil -- structureId being guided to (ConsoleWaypoint.AtmKey while guiding to the ATM)
local currentPlot: number? = nil
local guidingAtm = false -- v72: ShowAtm (the target is the player's own ATM, not a console)
local startedAt = 0
local lastAttemptAt = -math.huge
local target: BasePart? = nil -- console part or local anchor
local anchor: BasePart? = nil -- client-only stand-in while the console is not on this client
local att0: Attachment? = nil
local att1: Attachment? = nil
local beam: Beam? = nil
local marker: BillboardGui? = nil
local distLabel: TextLabel? = nil
local stepConn: RBXScriptConnection? = nil
local stepAcc = 0
local shownMetres = -1

local function destroyVisuals()
	for _, inst in ipairs({ beam, marker, att0, att1, anchor } :: { Instance? }) do
		if inst then
			inst:Destroy()
		end
	end
	beam, marker, att0, att1, anchor, distLabel, target = nil, nil, nil, nil, nil, nil, nil
end

function ConsoleWaypoint.Clear()
	destroyVisuals()
	if stepConn then
		stepConn:Disconnect()
		stepConn = nil
	end
	current, currentPlot = nil, nil
	guidingAtm = false
end

-- ConsoleWaypoint.Current() while ShowAtm is guiding (no structure id is ever "ATM")
ConsoleWaypoint.AtmKey = "ATM"

function ConsoleWaypoint.Current(): string?
	return current
end

local function rootPart(): BasePart?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

-- v72: the player's OWN ATM part (Money Collector tagged with PlotId == plotId) when it is on this client
local function ownAtm(plotId: number): BasePart?
	local hrp = rootPart()
	local best: BasePart? = nil
	local bestD = math.huge
	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.MoneyCollector)) do
		if inst:IsA("BasePart") and tonumber(inst:GetAttribute("PlotId") :: any) == plotId and inst:IsDescendantOf(Workspace) then
			local d = if hrp then (inst.Position - hrp.Position).Magnitude else 0
			if best == nil or d < bestD then
				best, bestD = inst, d
			end
		end
	end
	return best
end

local function realConsole(structureId: string): BasePart?
	local plotId = currentPlot
	if plotId == nil then
		return nil
	end
	if guidingAtm then
		return ownAtm(plotId)
	end
	return ConsoleLocator.Find(plotId, structureId)
end

local function stampedPos(structureId: string): Vector3?
	local pos = player:GetAttribute(if guidingAtm then "WE_AtmPos" else "WE_ConsolePos_" .. structureId)
	return if typeof(pos) == "Vector3" then pos else nil
end

-- true when a target can be resolved (console part or stamped position), without building anything
local function resolvable(structureId: string): boolean
	return realConsole(structureId) ~= nil or stampedPos(structureId) ~= nil
end

local function build(structureId: string)
	lastAttemptAt = os.clock()
	local hrp = rootPart()
	if hrp == nil then
		return -- respawning: try again after RetrySeconds (no anchor churn while dead)
	end
	destroyVisuals()
	local t: BasePart? = realConsole(structureId)
	if t == nil then
		local pos = stampedPos(structureId)
		if pos == nil then
			return
		end
		local a = Instance.new("Part")
		a.Name = "WE_ConsoleWaypointAnchor"
		a.Anchored = true
		a.CanCollide = false
		a.CanQuery = false
		a.CanTouch = false
		a.Transparency = 1
		a.Size = Vector3.new(1, 1, 1)
		a.CFrame = CFrame.new(pos)
		a.Parent = Workspace.CurrentCamera or Workspace
		anchor = a
		t = a
	end
	local tp = t :: BasePart
	target = tp
	local top = (if anchor then 1.7 else tp.Size.Y * 0.5) + W.MarkerLift
	local a1 = Instance.new("Attachment")
	a1.Name = "WE_WaypointAtt1"
	a1.Position = Vector3.new(0, top, 0)
	a1.Parent = tp
	att1 = a1
	local a0 = Instance.new("Attachment")
	a0.Name = "WE_WaypointAtt0"
	a0.Parent = hrp
	att0 = a0

	local b = Instance.new("Beam")
	b.Name = "WE_ConsoleBeam"
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.FaceCamera = true
	b.Width0 = W.BeamWidth0
	b.Width1 = W.BeamWidth1
	b.LightEmission = W.BeamLightEmission
	b.Color = ColorSequence.new(W.BeamColor)
	b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0.85) })
	b.Parent = hrp
	beam = b

	local def = BaseConfig.Structures[structureId]
	local title = string.upper(if guidingAtm then TycoonGuideConfig.Text.ChipGoCollect elseif def then def.DisplayName else structureId)
	local bb = Instance.new("BillboardGui")
	bb.Name = "WE_ConsoleWaypoint"
	bb.Adornee = tp
	-- real px (a BillboardGui has no UIScale): 12 px per character keeps "SPECIAL FORCES FACILITY" at >= 14 px text
	bb.Size = UDim2.fromOffset(math.clamp(#title * 12 + 16, W.MarkerMinWidth, W.MarkerMaxWidth), 36)
	bb.StudsOffsetWorldSpace = Vector3.new(0, top, 0)
	bb.AlwaysOnTop = true -- transient: only after the player tapped GO, gone on arrival / timeout (walk-ins hide it otherwise)
	bb.LightInfluence = 0
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0.55, 0)
	name.Font = Enum.Font.GothamBold
	name.TextScaled = true
	name.TextColor3 = W.BeamColor
	name.TextStrokeTransparency = 0.4
	name.Text = title
	name.Parent = bb
	local nameCap = Instance.new("UITextSizeConstraint")
	nameCap.MinTextSize = W.MarkerMinTextPx
	nameCap.MaxTextSize = W.MarkerMaxTextPx
	nameCap.Parent = name
	local dist = Instance.new("TextLabel")
	dist.BackgroundTransparency = 1
	dist.Position = UDim2.fromScale(0, 0.55)
	dist.Size = UDim2.new(1, 0, 0.45, 0)
	dist.Font = Enum.Font.GothamBold
	dist.TextScaled = true
	dist.TextColor3 = Color3.new(1, 1, 1)
	dist.TextStrokeTransparency = 0.4
	dist.Text = ""
	dist.Parent = bb
	local distCap = Instance.new("UITextSizeConstraint")
	distCap.MinTextSize = W.MarkerMinTextPx
	distCap.MaxTextSize = W.MarkerMaxTextPx
	distCap.Parent = dist
	distLabel = dist
	shownMetres = -1
	bb.Parent = tp
	marker = bb
end

local function step(dt: number)
	local sid = current
	if sid == nil then
		return
	end
	-- <= RefreshHz: the arrival check, the distance label and the retry timer need no per-frame work
	stepAcc += dt
	if stepAcc < 1 / W.RefreshHz then
		return
	end
	stepAcc = 0
	local now = os.clock()
	if now - startedAt > W.TimeoutSeconds then
		ConsoleWaypoint.Clear()
		return
	end
	local hrp = rootPart()
	local t = target
	local broken = t == nil or t.Parent == nil or hrp == nil or att0 == nil or (att0 :: Attachment).Parent ~= hrp
	-- rebuild after respawn / console rebuilt, or retarget from the stamped anchor to the real console once it
	-- streams in; throttled (a tag scan per attempt)
	if (broken or anchor ~= nil) and now - lastAttemptAt >= W.RetrySeconds then
		if broken or realConsole(sid) ~= nil then
			build(sid)
		else
			lastAttemptAt = now
		end
		return
	end
	if broken or hrp == nil or t == nil then
		return
	end
	local d = ((hrp :: BasePart).Position - (t :: BasePart).Position).Magnitude
	if d <= W.ArriveRadius then
		ConsoleWaypoint.Clear() -- the BUY button takes over at the console
		return
	end
	local metres = math.floor(d + 0.5)
	local dl = distLabel
	if dl and metres ~= shownMetres then
		shownMetres = metres
		dl.Text = string.format("%d m", metres)
	end
end

--[[ Guide the local player to structureId's console on their own plot (plotId: from BaseStateUpdate / PlayerState;
	nil falls back to the server-stamped position). Returns false when neither the console part nor a stamped position
	is known yet (the caller shows ConsoleBuyConfig.Text.NoConsole). ]]
function ConsoleWaypoint.Show(structureId: string, plotId: number?): boolean
	pcall(function() local req: any = require; req(script.Parent.ObjectiveMarker).Clear() end) -- W3s2 Phase B: the latest GO wins (one guide line)
	ConsoleWaypoint.Clear()
	current, currentPlot, startedAt = structureId, plotId, os.clock()
	if not resolvable(structureId) then
		ConsoleWaypoint.Clear()
		return false
	end
	build(structureId) -- no-op while respawning; step() retries
	stepAcc = math.huge -- first step runs at once (distance label)
	stepConn = RunService.Heartbeat:Connect(step)
	return true
end

--[[ v72 guide: the same line to the local player's OWN ATM ("Collect $N at your ATM"). plotId: the player's plot
	(nil: only the server-stamped WE_AtmPos is used). false when neither the ATM part nor WE_AtmPos is known. ]]
function ConsoleWaypoint.ShowAtm(plotId: number?): boolean
	pcall(function() local req: any = require; req(script.Parent.ObjectiveMarker).Clear() end) -- W3s2 Phase B: the latest GO wins (one guide line)
	ConsoleWaypoint.Clear()
	guidingAtm = true
	local key = ConsoleWaypoint.AtmKey
	current, currentPlot, startedAt = key, plotId, os.clock()
	if not resolvable(key) then
		ConsoleWaypoint.Clear()
		return false
	end
	build(key)
	stepAcc = math.huge
	stepConn = RunService.Heartbeat:Connect(step)
	return true
end

return ConsoleWaypoint
