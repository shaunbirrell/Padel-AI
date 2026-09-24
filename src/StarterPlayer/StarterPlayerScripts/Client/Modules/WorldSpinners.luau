--!strict
--[[
	v68: rotates radar dishes and other "WE_Spinner" Models (built by the server's HollowBuildingBuilder
	api.spin) around a vertical axis. Purely visual and local: the server copies stay still, so nothing
	replicates per frame. Only spinners within SPIN_RANGE of the camera are updated.

	Model attributes: WE_SpinPivot (CFrame, world) and WE_SpinRPM (number).
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
}

local spinners: { [Model]: Spinner } = {}

local function addPart(s: Spinner, p: Instance)
	if p:IsA("BasePart") and not s.parts[p] then
		-- the server built it at angle 0, so its current CFrame is the rest pose
		s.parts[p] = s.pivot:ToObjectSpace(p.CFrame)
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
	local s: Spinner = { pivot = pivot, rate = rpm * math.pi * 2 / 60, angle = 0, parts = {} }
	spinners[m] = s
	for _, d in ipairs(m:GetDescendants()) do
		addPart(s, d)
	end
	-- StreamingEnabled can deliver parts after the Model
	m.DescendantAdded:Connect(function(d: Instance)
		local cur = spinners[m]
		if cur then
			-- a late part arrives in its rest pose; store its offset as if at angle 0
			if d:IsA("BasePart") and not cur.parts[d] then
				cur.parts[d] = cur.pivot:ToObjectSpace(d.CFrame)
			end
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
			spinners[m] = nil
		end
	end)
	RunService.RenderStepped:Connect(function(dt: number)
		local cam = Workspace.CurrentCamera
		local camPos = if cam then cam.CFrame.Position else Vector3.zero
		for m, s in pairs(spinners) do
			if m.Parent == nil then
				spinners[m] = nil
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
