--!strict
--[[
	F4 / spec §1.1 (owner's 11 features, lane G): LabelGovernor makes CLAUDE.md's "at most 3 world labels on screen at a
	base" true on this client, whatever the server and the other client modules build.

	Every base BillboardGui carries the CollectionService tag WorldLabelConfig.BaseLabelTag ("WE_BaseLabel"): the ATM
	premium pads and the gold pump pad (lane W, server), the producer label (ProducerLabels), the console / NEXT tags
	(WorldPromptController) and the business "+$N" pops (BusinessVisuals). BaseLabelGovernor.Hz times a second the
	governor keeps the MaxOnScreen tagged labels nearest the camera that could draw (their owner wants them on, they
	are not another player's owner-only label, and the camera is within their own MaxDistance) and holds every other
	tagged label off through WorldLabel.Hold. A held label keeps its owner's wish and comes back when released. A label
	tagged between two passes starts held and is decided on the next Heartbeat, so the cap holds on every frame.

	Never touched: a label whose WorldLabelConfig.RoleAttribute is "objective" (the one AlwaysOnTop objective marker)
	does not count toward the cap and is never held (one held before it became the objective is released). SurfaceGuis
	(painted signs) are not governed.

	Phone cost: one Heartbeat accumulator (the per-frame path only adds dt); the pass walks a dense list of tagged
	labels with scalar maths into preallocated arrays: no whole-tree scan, no table or closure per pass, no yields. Off
	(Init returns at once) while WorldLabelConfig.BaseLabelGovernor.Enabled is false.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60) -- Bootstrap already waited for it; bounded anyway
local WorldLabelConfig = require(Shared.Configs.WorldLabelConfig)
local WorldLabel = require(Shared.Util.WorldLabel)

local LabelGovernor = {}

local CFG = WorldLabelConfig.BaseLabelGovernor
local TAG = WorldLabelConfig.BaseLabelTag
local ROLE_ATTR = WorldLabelConfig.RoleAttribute
local EXEMPT_ROLE = "objective"
local HUGE = math.huge

local started = false
local labels: { BillboardGui } = {} -- dense list of the tagged billboards on this client
local slot: { [BillboardGui]: number } = {} -- label -> index in `labels`
local pick: { boolean } = {} -- per index: kept on by the last pass (reused, never reallocated)
local bestIdx: { number } = {} -- the MaxOnScreen nearest candidates (insertion-sorted, preallocated)
local bestD: { number } = {}
local passDue = true -- run a pass on the next Heartbeat (a label was tagged / untagged)

local function maxOnScreen(): number
	return math.max(0, math.floor(tonumber(CFG.MaxOnScreen) or 3))
end

local function isExempt(gui: BillboardGui): boolean
	return gui:GetAttribute(ROLE_ATTR) == EXEMPT_ROLE
end

-- the label's world anchor (Adornee, else its parent: BasePart / Attachment / a Model's PrimaryPart) as three numbers;
-- nil when it is not placed in this client's world (streamed out, parked)
local function anchorXYZ(gui: BillboardGui): (number?, number, number)
	local a: Instance? = gui.Adornee
	if a == nil then
		a = gui.Parent
	end
	if a == nil then
		return nil, 0, 0
	end
	if a:IsA("Model") then
		local pp = (a :: Model).PrimaryPart
		if pp == nil then
			return nil, 0, 0
		end
		a = pp
	end
	local inst = a :: Instance
	if inst:IsA("BasePart") then
		if not inst:IsDescendantOf(Workspace) then
			return nil, 0, 0
		end
		local p = inst.Position
		return p.X, p.Y, p.Z
	elseif inst:IsA("Attachment") then
		if not inst:IsDescendantOf(Workspace) then
			return nil, 0, 0
		end
		local p = inst.WorldPosition
		return p.X, p.Y, p.Z
	end
	return nil, 0, 0
end

-- distance from the camera to the label's drawn point, or HUGE when it cannot draw here
local function distanceOf(gui: BillboardGui, cx: number, cy: number, cz: number): number
	local x, y, z = anchorXYZ(gui)
	if x == nil then
		return HUGE
	end
	local o = gui.StudsOffsetWorldSpace
	local dx, dy, dz = x + o.X - cx, y + o.Y - cy, z + o.Z - cz
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- one pass: the MaxOnScreen nearest drawable labels stay on, every other governed label is held off
local function pass()
	local cam = Workspace.CurrentCamera
	if cam == nil then
		return
	end
	local camPos = cam.CFrame.Position
	local cx, cy, cz = camPos.X, camPos.Y, camPos.Z
	local cap = maxOnScreen()
	local n = #labels
	local kept = 0
	for i = 1, n do
		local gui = labels[i]
		pick[i] = false
		if not isExempt(gui) and WorldLabel.Wanted(gui) then
			local d = distanceOf(gui, cx, cy, cz)
			if d <= gui.MaxDistance and d < HUGE then
				if kept < cap then
					kept += 1
					bestIdx[kept] = i
					bestD[kept] = d
				elseif cap > 0 and d < bestD[kept] then
					bestIdx[kept] = i
					bestD[kept] = d
				else
					continue
				end
				local k = kept
				while k > 1 and bestD[k] < bestD[k - 1] do
					bestD[k], bestD[k - 1] = bestD[k - 1], bestD[k]
					bestIdx[k], bestIdx[k - 1] = bestIdx[k - 1], bestIdx[k]
					k -= 1
				end
			end
		end
	end
	for k = 1, kept do
		pick[bestIdx[k]] = true
	end
	for i = 1, n do
		local gui = labels[i]
		if isExempt(gui) then
			if WorldLabel.IsHeld(gui) then
				WorldLabel.Hold(gui, false) -- became the objective marker while held: give it back, then hands off
			end
		else
			WorldLabel.Hold(gui, not pick[i])
		end
	end
end

local function track(inst: Instance)
	if not inst:IsA("BillboardGui") then
		return
	end
	local gui = inst :: BillboardGui
	if slot[gui] ~= nil then
		return
	end
	table.insert(labels, gui)
	slot[gui] = #labels
	pick[#labels] = false
	if not isExempt(gui) then
		WorldLabel.Hold(gui, true) -- held until the next pass decides (the cap holds between passes)
	end
	passDue = true
end

local function untrack(inst: Instance)
	local gui = inst :: BillboardGui
	local i = slot[gui]
	if i == nil then
		return
	end
	local last = #labels
	local moved = labels[last]
	labels[i] = moved
	slot[moved] = i
	pick[i] = pick[last]
	labels[last] = nil
	pick[last] = nil
	slot[gui] = nil
	if WorldLabel.IsHeld(gui) then
		WorldLabel.Hold(gui, false) -- no longer governed (untagged but still here): its owner decides again
	end
	passDue = true
end

-- test / debug: how many governed labels are on this client, and how many are not held
function LabelGovernor.Counts(): (number, number)
	local on = 0
	for _, gui in ipairs(labels) do
		if gui.Enabled and not isExempt(gui) then
			on += 1
		end
	end
	return #labels, on
end

function LabelGovernor.Pass()
	pass()
end

function LabelGovernor.Init()
	if started or CFG.Enabled ~= true then
		return
	end
	started = true
	CollectionService:GetInstanceAddedSignal(TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(untrack)
	for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
		track(inst)
	end
	local period = 1 / math.clamp(tonumber(CFG.Hz) or 4, 1, 10) -- <= 10 Hz (CLAUDE.md UI refresh cap)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < period and not passDue then
			return
		end
		acc = 0 -- reset, never catch up
		passDue = false
		pass()
	end)
end

return LabelGovernor
