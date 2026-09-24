--!strict
--[[
	v67: keep base labels readable instead of covering the screen.

	Up to 43 BillboardGuis sat on one plot, several AlwaysOnTop with infinite or 80-110 stud range, so
	"CLICK · $15", the ATM card, premium pads and soldier tags drew over each other from across the map.
	For every BillboardGui anchored inside a plot (config: WorldLabelConfig) this turns AlwaysOnTop off
	and caps MaxDistance. Label size/layout is left alone (several use fixed pixel layouts).

	v70 (HUD spec §5, mobile P1-10): the same rule outside the plots (WorldLabelConfig.ApplyOutsidePlots,
	OutsideMaxDistance). The position is the label's Adornee, else its first ancestor with a position (a part,
	an attachment or a model), not only the direct parent. AlwaysOnTop survives only for a name in
	AllowAlwaysOnTop or a WE_LabelRole in AlwaysOnTopRoles (Shared/Util/WorldLabel.SetRole: the one objective
	marker, a contested flag). WE_LabelPolicy records the scope: "plot" or "world".
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local WorldLabelConfig = require(Shared.Configs.WorldLabelConfig)

local WorldLabelPolicy = {}

local SCOPE_ATTR = "WE_LabelPolicy"
local ROLE_ATTR = WorldLabelConfig.RoleAttribute

local function positionOf(inst: Instance): Vector3?
	if inst:IsA("BasePart") then
		return inst.Position
	elseif inst:IsA("Attachment") then
		return inst.WorldPosition
	elseif inst:IsA("Model") then
		return inst:GetPivot().Position
	end
	return nil
end

-- The label's Adornee, else the first ancestor with a position (a label under a Folder inside a model still counts).
local function anchorPosition(bb: BillboardGui): Vector3?
	local ad: Instance? = bb.Adornee
	if ad then
		local p = positionOf(ad)
		if p then
			return p
		end
	end
	local node: Instance? = bb.Parent
	while node ~= nil and node ~= Workspace and node ~= game do
		local p = positionOf(node)
		if p then
			return p
		end
		node = node.Parent
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

local function mayDrawOnTop(bb: BillboardGui): boolean
	if WorldLabelConfig.AllowAlwaysOnTop[bb.Name] == true then
		return true
	end
	local role = bb:GetAttribute(ROLE_ATTR)
	return type(role) == "string" and WorldLabelConfig.AlwaysOnTopRoles[role] == true
end

local function enforce(bb: BillboardGui)
	if bb.AlwaysOnTop and not mayDrawOnTop(bb) then
		bb.AlwaysOnTop = false
	end
	local cap = if bb:GetAttribute(SCOPE_ATTR) == "world" then WorldLabelConfig.OutsideMaxDistance else WorldLabelConfig.MaxDistance
	if bb.MaxDistance <= 0 or bb.MaxDistance > cap then
		bb.MaxDistance = cap
	end
end

function WorldLabelPolicy.Apply(bb: BillboardGui)
	if not WorldLabelConfig.Enabled then
		return
	end
	if bb:GetAttribute(SCOPE_ATTR) ~= nil then
		enforce(bb)
		return
	end
	local pos = anchorPosition(bb)
	local inPlot = pos ~= nil and insidePlot(pos)
	if not inPlot and not WorldLabelConfig.ApplyOutsidePlots then
		return
	end
	bb:SetAttribute(SCOPE_ATTR, if inPlot then "plot" else "world")
	enforce(bb)
	-- Some services re-style their labels later (level changes, offers, roles); keep the rule in force.
	bb:GetPropertyChangedSignal("AlwaysOnTop"):Connect(function()
		enforce(bb)
	end)
	bb:GetPropertyChangedSignal("MaxDistance"):Connect(function()
		enforce(bb)
	end)
	bb:GetAttributeChangedSignal(ROLE_ATTR):Connect(function()
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
