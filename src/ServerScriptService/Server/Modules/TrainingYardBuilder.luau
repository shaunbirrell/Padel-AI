--!strict
--[[
	TrainingYardBuilder (owner feedback 2026-09-27): builds Plot<n>.TrainingYard from TrainingYardConfig. Called once per
	plot from MapSetup's plot build (the yard is the same at every base level).

	Contract other code relies on (unchanged from the old yard):
	  • the folder is named "TrainingYard" and sits directly in the plot folder;
	  • it holds a BasePart "YardPad" (ProducerLabels' yard label anchor, SoldierService's pop anchor) and the invisible
	    anchors "YardEarnAnchor" / "YardAnchor" (ManualDropperService builds ManualDropper_Yard at YardEarnAnchor +
	    ManualDropperConfig.YardOffset, inside this folder);
	  • the targets are "TrainingTarget1..3" with the attributes WE_TrainingTarget and PlotId.

	Figures are makeSoldierKit statues passed in by MapSetup (so R-RIG's statue path turns them into Roblox's Soldier;
	today's Part-kit look stays the fallback). Meshes (VisualAssetConfig.DesertKit keys, Roblox-made Synty pieces) are
	asked for in ONE deferred task per yard through VisualAssetService.CloneKitMesh (it may yield on a pack's first
	load). A dressed piece's mesh is fitted into the piece's box (one uniform scale, standing on the box bottom); a
	colliding piece stays as an invisible collider, a non-colliding one is destroyed (replace, never add). A failed or
	skipped load (Studio, outage) leaves the Part look, which is complete on its own. Every mesh is anchored,
	non-colliding, CanQuery / CanTouch off and casts no shadow (CloneKitMesh). No lights, no Neon, no surface or
	billboard GUIs. Streaming: every piece is a loose anchored part (a statue is an Atomic Model); no client code assumes
	any of them exists except YardPad, which ProducerLabels already treats as "not streamed in yet".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TrainingYardConfig = require(ReplicatedStorage.Shared.Configs.TrainingYardConfig)

type Piece = TrainingYardConfig.Piece
type Figure = TrainingYardConfig.Figure
type Decor = TrainingYardConfig.Decor

local TrainingYardBuilder = {}

-- the axis-aligned size of a box of size s turned by `rot` (a yaw)
local function turnedExtent(rot: CFrame, s: Vector3): Vector3
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = rot:GetComponents()
	return Vector3.new(
		math.abs(r00) * s.X + math.abs(r01) * s.Y + math.abs(r02) * s.Z,
		math.abs(r10) * s.X + math.abs(r11) * s.Y + math.abs(r12) * s.Z,
		math.abs(r20) * s.X + math.abs(r21) * s.Y + math.abs(r22) * s.Z
	)
end

local function buildPiece(folder: Instance, F: CFrame, origin: Vector3, pc: Piece, plotId: number): BasePart
	local p: BasePart
	if pc.Shape == "Wedge" then
		p = Instance.new("WedgePart")
	else
		local q = Instance.new("Part")
		if pc.Shape == "Cylinder" then
			q.Shape = Enum.PartType.Cylinder
		end
		p = q
	end
	p.Name = pc.Name
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = pc.Size
	-- pieces turn about Y only, so the vertical extent stays Size.Y: Y is the piece's bottom above the plot pad top
	local centre = origin + Vector3.new(pc.X, TrainingYardConfig.GroundY + pc.Y + pc.Size.Y * 0.5, pc.Z)
	p.CFrame = F * CFrame.new(centre) * CFrame.Angles(0, math.rad(pc.Yaw or 0), 0)
	p.Color = pc.Color
	p.Material = pc.Material
	p.CanCollide = pc.Collide
	if not pc.Collide then
		-- paint and target faces: never block a ray or fire a touch
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
	end
	if pc.Target then
		p:SetAttribute("PlotId", plotId)
		p:SetAttribute("WE_TrainingTarget", true)
	end
	p.Parent = folder
	return p
end

local function invisibleAnchor(folder: Instance, name: string, cf: CFrame)
	local a = Instance.new("Part")
	a.Name = name
	a.Anchored = true
	a.Size = Vector3.new(1, 1, 1)
	a.CFrame = cf
	a.Transparency = 1
	a.CanCollide = false
	a.CanQuery = false
	a.CanTouch = false
	a.CastShadow = false
	a.Parent = folder
end

-- one CloneKitMesh call; nil unless it returned a BasePart (a failed load, Studio skip, an unwired key)
local function cloneMesh(vas: any, key: string): BasePart?
	local ok, res = pcall(vas.CloneKitMesh, key)
	if ok and typeof(res) == "Instance" and res:IsA("BasePart") then
		return res
	end
	return nil
end

-- deferred: dress the pieces that name a mesh, then place the mesh-only decor (at most MaxMeshesPerYard meshes)
local function dressYard(folder: Instance, F: CFrame, origin: Vector3, hosts: { { part: BasePart, piece: Piece } }): number
	local okReq, vas = pcall(function()
		return require(script.Parent.Parent.Services.VisualAssetService) :: any
	end)
	if not okReq or typeof(vas) ~= "table" or typeof(vas.CloneKitMesh) ~= "function" then
		return 0
	end
	local cap = TrainingYardConfig.MaxMeshesPerYard
	local placed = 0
	for _, h in ipairs(hosts) do
		if placed >= cap then
			return placed
		end
		local host, pc = h.part, h.piece
		local key = pc.Mesh
		if key and host.Parent == folder and folder.Parent then
			local mp = cloneMesh(vas, key)
			-- the first load of a pack yields: the yard may have been rebuilt meanwhile
			if mp and host.Parent == folder and folder.Parent then
				local rot = CFrame.Angles(0, math.rad(pc.MeshYaw or 0), 0)
				local s = mp.Size
				local ext = turnedExtent(rot, s)
				local hs = host.Size
				local k = math.min(hs.X / ext.X, hs.Y / ext.Y, hs.Z / ext.Z)
				mp.Size = s * k
				mp.CFrame = host.CFrame * CFrame.new(0, -hs.Y * 0.5 + ext.Y * k * 0.5, 0) * rot
				mp.Name = host.Name .. "Mesh"
				mp:SetAttribute("WE_YardMesh", key)
				mp.Parent = folder
				placed += 1
				if host.CanCollide then
					host.Transparency = 1 -- stays the collider under the mesh
					host.CastShadow = false
				else
					host:Destroy()
				end
			elseif mp then
				mp:Destroy()
			end
		end
	end
	for i, d in ipairs(TrainingYardConfig.Decor) do
		if placed >= cap or not folder.Parent then
			return placed
		end
		local mp = cloneMesh(vas, d.Mesh)
		if mp and folder.Parent then
			mp.Size = mp.Size * d.Scale
			local pos = origin + Vector3.new(d.X, TrainingYardConfig.GroundY + d.Y, d.Z)
			mp.CFrame = F * CFrame.new(pos) * CFrame.Angles(0, math.rad(d.Yaw), 0) * CFrame.Angles(math.rad(d.Tilt or 0), 0, 0)
			mp.Name = "YardDecor" .. i
			mp:SetAttribute("WE_YardMesh", d.Mesh)
			mp.Parent = folder
			placed += 1
		elseif mp then
			mp:Destroy()
		end
	end
	return placed
end

--[[ Build the yard into plotFolder. F: the plot frame (MapSetup's BaseLayout.PlotCFrame); site: the plot-local yard
	origin (BaseLayoutConfig.Courtyard.TrainingYard), nil = TrainingYardConfig.LegacyOrigin; makeSoldierKit: MapSetup's
	static soldier builder. Returns the TrainingYard folder. ]]
function TrainingYardBuilder.Build(plotFolder: Instance, plotId: number, F: CFrame, site: { X: number, Z: number }?, makeSoldierKit: (...any) -> any): Folder
	local o = site or TrainingYardConfig.LegacyOrigin
	local origin = Vector3.new(o.X, 0, o.Z)
	local folder = Instance.new("Folder")
	folder.Name = "TrainingYard"
	folder.Parent = plotFolder

	local hosts: { { part: BasePart, piece: Piece } } = {}
	for _, pc in ipairs(TrainingYardConfig.Pieces) do
		local p = buildPiece(folder, F, origin, pc, plotId)
		if pc.Mesh then
			table.insert(hosts, { part = p, piece = pc })
		end
	end

	-- soldiers at the firing line, facing downrange (R-RIG statue path: makeSoldierKit → TryAttachCharacterVisual)
	local rootY = TrainingYardConfig.GroundY + TrainingYardConfig.FigureRootY
	for _, fig in ipairs(TrainingYardConfig.Figures) do
		local cf = F * CFrame.new(origin + Vector3.new(fig.X, rootY, fig.Z)) * CFrame.Angles(0, math.rad(fig.Yaw), 0)
		makeSoldierKit(folder, fig.Name, cf, fig.Body, nil, fig.Accent, TrainingYardConfig.FigureHealth, fig.Kind, nil)
	end

	local ya, ye = TrainingYardConfig.YardAnchor, TrainingYardConfig.YardEarnAnchor
	invisibleAnchor(folder, "YardAnchor", F * CFrame.new(origin + Vector3.new(ya.X, TrainingYardConfig.GroundY + ya.Y, ya.Z)))
	invisibleAnchor(folder, "YardEarnAnchor", F * CFrame.new(origin + Vector3.new(ye.X, TrainingYardConfig.GroundY + ye.Y, ye.Z)))

	if TrainingYardConfig.UseMeshes then
		task.defer(function()
			local ok, err = pcall(dressYard, folder, F, origin, hosts)
			if not ok then
				warn("[TrainingYardBuilder] mesh dress failed (Part look stays): " .. tostring(err))
			end
		end)
	end
	return folder
end

return TrainingYardBuilder
