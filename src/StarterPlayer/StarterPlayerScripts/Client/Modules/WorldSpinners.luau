--!strict
--[[
	v68: rotates radar dishes and other "WE_Spinner" Models (built by the server's HollowBuildingBuilder
	api.spin) around a vertical axis. Purely visual and local: the server copies stay still, so nothing
	replicates per frame. Only spinners within SPIN_RANGE of the camera are updated.

	Model attributes: WE_SpinPivot (CFrame, world) and WE_SpinRPM (number).

	streaming2 lane C4 (F21), StreamingEnabled: a spinner part can stream out and back in (the same instance), and
	the whole Model can leave and come back (its tag is removed and added again). The CFrame it comes back with can
	still hold this client's local spin: the docs say local writes "can be" lost, so they can also be kept. Reading
	that as the rest pose would turn the part out of step with the rest of the dish. So, only while
	Workspace.StreamingEnabled is on, the rest offset from the first time this client saw a part is kept and used
	again: in the spinner's own `seen` map (strong, for as long as the spinner is tracked, so a part that streams out
	on its own keeps its entry) and in a weak-keyed table for a Model that is tracked again (best effort: Roblox may
	collect an Instance key that no script holds; inside lane S4's Atomic WE_Building the Model leaves and comes back
	as one unit, so its parts stay in step with each other anyway). Each Model's DescendantAdded connection is stored
	and disconnected when the spinner is dropped, so a re-tracked Model never stacks a second one. With streaming off
	the offset is read from the part as at 0a04776 (nothing streams, so nothing is ever re-added).
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WorldSpinners = {}

local TAG = "WE_Spinner"
local SPIN_RANGE = 320

type Spinner = {
	pivot: CFrame,
	rate: number, -- radians per second
	angle: number,
	parts: { [BasePart]: CFrame }, -- part → offset from the pivot at angle 0
	seen: { [BasePart]: CFrame }, -- streaming2 F21: every part seen while tracked → its first offset (streaming on)
	conn: RBXScriptConnection?, -- the Model's DescendantAdded (disconnected when the spinner is dropped)
}

local spinners: { [Model]: Spinner } = {}
-- streaming2 F21: part → its rest offset from the pivot, as first seen (read and written only while streaming is on)
local restOffsets: { [BasePart]: CFrame } = setmetatable({}, { __mode = "k" }) :: any

-- the place's StreamingEnabled (default.project.json; scripts cannot set it)
local function streamingOn(): boolean
	return Workspace.StreamingEnabled == true
end

local function addPart(s: Spinner, p: Instance)
	if p:IsA("BasePart") and not s.parts[p] then
		local streaming = streamingOn()
		local cached: CFrame? = if streaming then (s.seen[p] or restOffsets[p]) else nil
		-- the server built it at angle 0, so its CFrame when first seen is the rest pose
		local offset: CFrame = if cached ~= nil then cached else s.pivot:ToObjectSpace(p.CFrame)
		if streaming then
			s.seen[p] = offset
			if cached == nil then
				restOffsets[p] = offset
			end
		end
		s.parts[p] = offset
	end
end

local function untrack(m: Model)
	local s = spinners[m]
	spinners[m] = nil
	local c = s and s.conn
	if c then
		c:Disconnect()
	end
end

local function track(m: Instance)
	if not m:IsA("Model") or spinners[m] then
		return
	end
	local pivot = m:GetAttribute("WE_SpinPivot")
	local rpm = m:GetAttribute("WE_SpinRPM")
	if typeof(pivot) ~= "CFrame" or typeof(rpm) ~= "number" then
		return
	end
	local s: Spinner = { pivot = pivot, rate = rpm * math.pi * 2 / 60, angle = 0, parts = {}, seen = {}, conn = nil }
	spinners[m] = s
	for _, d in ipairs(m:GetDescendants()) do
		addPart(s, d)
	end
	-- StreamingEnabled can deliver parts after the Model, or take one out and bring it back
	s.conn = m.DescendantAdded:Connect(function(d: Instance)
		local cur = spinners[m]
		if cur then
			addPart(cur, d)
		end
	end)
end

function WorldSpinners.Init()
	for _, m in ipairs(CollectionService:GetTagged(TAG)) do
		track(m)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(m: Instance)
		-- attributes are set before the tag, but wait a frame for children on slow joins
		task.defer(track, m)
	end)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(m: Instance)
		if m:IsA("Model") then
			untrack(m)
		end
	end)
	RunService.RenderStepped:Connect(function(dt: number)
		local cam = Workspace.CurrentCamera
		local camPos = if cam then cam.CFrame.Position else Vector3.zero
		for m, s in pairs(spinners) do
			if m.Parent == nil then
				untrack(m)
			elseif (s.pivot.Position - camPos).Magnitude <= SPIN_RANGE then
				s.angle = (s.angle + s.rate * dt) % (math.pi * 2)
				local frame = s.pivot * CFrame.Angles(0, s.angle, 0)
				for p, offset in pairs(s.parts) do
					if p.Parent then
						p.CFrame = frame * offset
					else
						s.parts[p] = nil
					end
				end
			end
		end
	end)
end

return WorldSpinners
