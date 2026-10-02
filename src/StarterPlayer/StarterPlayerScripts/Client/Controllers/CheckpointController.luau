--!strict
--[[
	claude-bud JOB 37 (2026-09-30): the road checkpoint tower SEARCHLIGHT sweeps on this client only (the server builds it
	still: WorldKits Detail.Checkpoint tags the housing WE_Searchlight; its lens is the sibling "SearchlightLens").
	  * Every 2 s: the tagged housings (streamed in) within SweepStuds of the camera are swept, the rest are put back.
	  * One RenderStepped connection while at least one is swept (a few parts' CFrames: no tree scans), none otherwise.
	The sweep is a client-local CFrame on anchored parts: nothing replicates, the server never animates it.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CheckpointController = {}

local TAG = "WE_Searchlight"
local SWEEP_STUDS = 250
local SWEEP_DEG = 35
local SWEEP_SPEED = 0.45 -- radians of phase per second (a slow scan)

type Light = { Housing: BasePart, Lens: BasePart?, Base: CFrame, LensRel: CFrame? }
local active: { [BasePart]: Light } = {}
local conn: RBXScriptConnection? = nil
local t0 = os.clock()

local function restore(l: Light)
	if l.Housing.Parent then
		l.Housing.CFrame = l.Base
		local lens = l.Lens
		if lens and l.LensRel then
			lens.CFrame = l.Base * l.LensRel
		end
	end
end

local function step()
	local a = math.rad(SWEEP_DEG) * math.sin((os.clock() - t0) * SWEEP_SPEED)
	for _, l in pairs(active) do
		if l.Housing.Parent then
			local cf = l.Base * CFrame.Angles(0, a, 0)
			l.Housing.CFrame = cf
			local lens = l.Lens
			if lens and l.LensRel then
				lens.CFrame = cf * l.LensRel
			end
		end
	end
end

local function lensOf(h: BasePart): BasePart?
	local parent = h.Parent
	if parent == nil then
		return nil
	end
	local best, bestD = nil, 3
	for _, c in ipairs(parent:GetChildren()) do
		if c.Name == "SearchlightLens" and c:IsA("BasePart") then
			local d = (c.Position - h.Position).Magnitude
			if d < bestD then
				best, bestD = c, d
			end
		end
	end
	return best
end

local function scan()
	local cam = Workspace.CurrentCamera
	if cam == nil then
		return
	end
	local at = cam.CFrame.Position
	local seen: { [BasePart]: boolean } = {}
	for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
		if inst:IsA("BasePart") and inst:IsDescendantOf(Workspace) and (inst.Position - at).Magnitude <= SWEEP_STUDS then
			seen[inst] = true
			if active[inst] == nil then
				local lens = lensOf(inst)
				active[inst] = { Housing = inst, Lens = lens, Base = inst.CFrame, LensRel = if lens then inst.CFrame:ToObjectSpace(lens.CFrame) else nil }
			end
		end
	end
	for h, l in pairs(active) do
		if not seen[h] then
			restore(l)
			active[h] = nil
		end
	end
	if next(active) ~= nil and conn == nil then
		conn = RunService.RenderStepped:Connect(step)
	elseif next(active) == nil and conn then
		conn:Disconnect()
		conn = nil
	end
end

function CheckpointController.Init()
	task.spawn(function()
		while true do
			task.wait(2)
			local ok, err = pcall(scan :: any)
			if not ok then
				warn("[CheckpointController] " .. tostring(err))
			end
		end
	end)
end

return CheckpointController
