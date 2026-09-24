--!strict
--[[
	v67: keep base labels readable instead of covering the screen.

	Up to 43 BillboardGuis sat on one plot, several AlwaysOnTop with infinite or 80-110 stud range, so
	"CLICK · $15", the ATM card, premium pads and soldier tags drew over each other from across the map.
	For every BillboardGui anchored inside a plot (config: WorldLabelConfig) this turns AlwaysOnTop off
	and caps MaxDistance. Label size/layout is left alone (several use fixed pixel layouts).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local WorldLabelConfig = require(Shared.Configs.WorldLabelConfig)

local WorldLabelPolicy = {}

local function anchorPosition(bb: BillboardGui): Vector3?
	local ad: Instance? = bb.Adornee or bb.Parent
	if ad == nil then
		return nil
	end
	if ad:IsA("BasePart") then
		return ad.Position
	elseif ad:IsA("Attachment") then
		return ad.WorldPosition
	elseif ad:IsA("Model") then
		return ad:GetPivot().Position
	end
	return nil
end

local function insidePlot(pos: Vector3): boolean
	local margin = WorldLabelConfig.PlotMargin
	for _, pad in ipairs(CollectionService:GetTagged(Constants.Tags.BasePlot)) do
		if pad:IsA("BasePart") then
			local lp = pad.CFrame:PointToObjectSpace(pos)
			if math.abs(lp.X) <= pad.Size.X * 0.5 + margin and math.abs(lp.Z) <= pad.Size.Z * 0.5 + margin then
				return true
			end
		end
	end
	return false
end

local function enforce(bb: BillboardGui)
	if bb.AlwaysOnTop and WorldLabelConfig.AllowAlwaysOnTop[bb.Name] ~= true then
		bb.AlwaysOnTop = false
	end
	local cap = WorldLabelConfig.MaxDistance
	if bb.MaxDistance <= 0 or bb.MaxDistance > cap then
		bb.MaxDistance = cap
	end
end

function WorldLabelPolicy.Apply(bb: BillboardGui)
	if not WorldLabelConfig.Enabled then
		return
	end
	if bb:GetAttribute("WE_LabelPolicy") then
		enforce(bb)
		return
	end
	local pos = anchorPosition(bb)
	if not pos or not insidePlot(pos) then
		return
	end
	bb:SetAttribute("WE_LabelPolicy", true)
	enforce(bb)
	-- Some services re-style their labels later (level changes, offers); keep the rule in force.
	bb:GetPropertyChangedSignal("AlwaysOnTop"):Connect(function()
		enforce(bb)
	end)
	bb:GetPropertyChangedSignal("MaxDistance"):Connect(function()
		enforce(bb)
	end)
end

function WorldLabelPolicy.Init()
	if not WorldLabelConfig.Enabled then
		return
	end
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BillboardGui") then
			WorldLabelPolicy.Apply(d)
		end
	end
	Workspace.DescendantAdded:Connect(function(d: Instance)
		if d:IsA("BillboardGui") then
			-- Defer so the creating code finishes setting Adornee/AlwaysOnTop/MaxDistance first.
			task.defer(function()
				if d.Parent then
					WorldLabelPolicy.Apply(d :: BillboardGui)
				end
			end)
		end
	end)
end

return WorldLabelPolicy
