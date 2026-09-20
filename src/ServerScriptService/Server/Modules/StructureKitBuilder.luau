--!strict
--[[
	Part-kit builders for base structures (no MeshIds required).
	Used by BaseService to ENSURE visible kits exist on purchase / join rehydrate,
	even if MapSetup plinths are bare or kits were stripped.
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StructureVisualConfig = require(Shared.Configs.StructureVisualConfig)
local Constants = require(Shared.Constants)

local StructureKitBuilder = {}

local PERIMETER_FOLDER = "WE_PerimeterWalls"
local CORNER_FOLDER = "WE_CornerTowers"

local function makePart(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Name = props.Name or "Part"
	if props.Size then
		p.Size = props.Size
	end
	if props.CFrame then
		p.CFrame = props.CFrame
	elseif props.Position then
		p.Position = props.Position
	end
	if props.Color then
		p.Color = props.Color
	end
	if props.Material then
		p.Material = props.Material
	end
	if props.Transparency ~= nil then
		p.Transparency = props.Transparency
	end
	if props.CanCollide ~= nil then
		p.CanCollide = props.CanCollide
	else
		p.CanCollide = false
	end
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	if props.Shape then
		p.Shape = props.Shape
	end
	p.Parent = props.Parent
	return p
end

local function kitPart(plinth: BasePart, role: string, size: Vector3, localOffset: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?)
	local p = makePart({
		Name = role,
		Size = size,
		CFrame = plinth.CFrame * CFrame.new(localOffset),
		Color = color,
		Material = material or Enum.Material.Metal,
		Transparency = 1, -- hidden until BaseService.applyKitVisuals (L0 ghost / L1+ solid)
		CanCollide = false,
		Parent = plinth,
		Shape = shape,
	})
	p:SetAttribute("WE_KitRole", role)
	p:SetAttribute("WE_BaseSize", size)
	p:SetAttribute("WE_LocalOffset", localOffset)
	p:SetAttribute("WE_Decor", true)
	return p
end

export type KitPalette = {
	Plinth: Color3,
	Body: Color3,
	Accent: Color3,
	Roof: Color3,
	Kit: string,
}

local function paletteFor(structureId: string): KitPalette
	local p = StructureVisualConfig.Palettes[structureId]
	if p then
		return p
	end
	return {
		Plinth = Color3.fromRGB(50, 55, 48),
		Body = Color3.fromRGB(70, 80, 65),
		Accent = Color3.fromRGB(200, 180, 80),
		Roof = Color3.fromRGB(45, 50, 42),
		Kit = "special",
	}
end

local function clearKitChildren(plinth: BasePart)
	for _, child in ipairs(plinth:GetChildren()) do
		if child:IsA("BasePart") and child:GetAttribute("WE_KitRole") ~= nil then
			child:Destroy()
		end
	end
end

local function countKitRoles(plinth: BasePart): number
	local n = 0
	for _, child in ipairs(plinth:GetChildren()) do
		if child:IsA("BasePart") and child:GetAttribute("WE_KitRole") ~= nil then
			n += 1
		end
	end
	return n
end

--[[ Build Part kit silhouette on plinth. Replaces any existing WE_KitRole children. ]]
function StructureKitBuilder.BuildKitOnPlinth(plinth: BasePart, structureId: string)
	local pal = paletteFor(structureId)
	local kit = pal.Kit
	clearKitChildren(plinth)

	if kit == "hq" then
		kitPart(plinth, "Body", Vector3.new(5.5, 3.4, 5.5), Vector3.new(0, 2.3, 0), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(6.4, 0.55, 6.4), Vector3.new(0, 4.3, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Antenna", Vector3.new(0.35, 4.8, 0.35), Vector3.new(1.8, 6.8, 1.8), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Accent", Vector3.new(6.6, 0.22, 6.6), Vector3.new(0, 0.72, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Detail", Vector3.new(1.1, 1.1, 1.1), Vector3.new(-2, 3.6, -2), pal.Accent, Enum.Material.Neon, Enum.PartType.Ball)
		kitPart(plinth, "Door", Vector3.new(1.6, 2.2, 0.25), Vector3.new(0, 1.7, -2.85), Color3.fromRGB(30, 35, 32), Enum.Material.Metal, nil)
		kitPart(plinth, "Window", Vector3.new(1.4, 1.0, 0.2), Vector3.new(2.0, 2.6, -2.8), Color3.fromRGB(70, 120, 150), Enum.Material.Glass, nil)
	elseif kit == "barracks" then
		kitPart(plinth, "Body", Vector3.new(6.6, 2.6, 4.4), Vector3.new(0, 1.9, 0), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(7.1, 0.5, 5.0), Vector3.new(0, 3.35, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(6.9, 0.18, 4.7), Vector3.new(0, 0.7, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Door", Vector3.new(1.4, 2.0, 0.25), Vector3.new(0, 1.6, -2.3), Color3.fromRGB(35, 40, 32), Enum.Material.Metal, nil)
		kitPart(plinth, "Window", Vector3.new(1.2, 0.9, 0.2), Vector3.new(-2.2, 2.3, -2.25), Color3.fromRGB(70, 120, 140), Enum.Material.Glass, nil)
		kitPart(plinth, "Detail", Vector3.new(0.7, 1.8, 0.7), Vector3.new(-3.0, 2.3, 1.5), pal.Accent, Enum.Material.Neon, nil)
	elseif kit == "depot" then
		kitPart(plinth, "Body", Vector3.new(6.9, 2.2, 5.6), Vector3.new(0, 1.7, 0), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(7.3, 0.4, 6.1), Vector3.new(0, 2.95, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(3.2, 0.28, 5.9), Vector3.new(0, 0.72, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Door", Vector3.new(2.8, 2.0, 0.3), Vector3.new(0, 1.6, -2.9), Color3.fromRGB(40, 50, 60), Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(1.0, 1.0, 1.0), Vector3.new(2.8, 2.4, 2.0), pal.Accent, Enum.Material.Neon, Enum.PartType.Ball)
		-- Showroom podium: PlateDark cylinder + GoldBright ring + rarity billboard host
		local podium = kitPart(plinth, "Podium", Vector3.new(3.6, 0.55, 3.6), Vector3.new(0, 0.95, 4.2), Constants.Colors.PlateDark, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		-- Cylinder default axis X — stand upright
		if podium then
			local off = podium:GetAttribute("WE_LocalOffset")
			if typeof(off) == "Vector3" then
				podium.CFrame = plinth.CFrame * CFrame.new(off :: Vector3) * CFrame.Angles(0, 0, math.rad(90))
			end
		end
		local ring = kitPart(plinth, "PodiumRing", Vector3.new(4.2, 0.18, 4.2), Vector3.new(0, 1.15, 4.2), Constants.Colors.GoldBright, Enum.Material.Neon, Enum.PartType.Cylinder)
		if ring then
			local off = ring:GetAttribute("WE_LocalOffset")
			if typeof(off) == "Vector3" then
				ring.CFrame = plinth.CFrame * CFrame.new(off :: Vector3) * CFrame.Angles(0, 0, math.rad(90))
			end
		end
		local display = kitPart(plinth, "ShowroomMesh", Vector3.new(2.4, 1.1, 4.0), Vector3.new(0, 1.85, 4.2), Color3.fromRGB(70, 88, 62), Enum.Material.Metal, nil)
		if display then
			display:SetAttribute("WE_ShowroomSpin", true)
			local bb = Instance.new("BillboardGui")
			bb.Name = "WE_RarityBillboard"
			bb.Size = UDim2.fromOffset(140, 28)
			bb.StudsOffset = Vector3.new(0, 2.4, 0)
			bb.AlwaysOnTop = true
			bb.MaxDistance = 80
			bb.Parent = display
			local lab = Instance.new("TextLabel")
			lab.Size = UDim2.fromScale(1, 1)
			lab.BackgroundColor3 = Constants.Colors.PlateDark
			lab.BackgroundTransparency = 0.15
			lab.BorderSizePixel = 0
			lab.Font = Enum.Font.GothamBold
			lab.TextScaled = true
			lab.TextColor3 = Constants.Colors.GoldBright
			lab.Text = "COMMON · JEEP"
			lab.Parent = bb
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 4)
			corner.Parent = lab
		end
	elseif kit == "lab" then
		kitPart(plinth, "Body", Vector3.new(5.1, 3.2, 5.1), Vector3.new(0, 2.2, 0), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(5.5, 0.5, 5.5), Vector3.new(0, 4.0, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Antenna", Vector3.new(0.4, 3.8, 0.4), Vector3.new(0, 6.1, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Accent", Vector3.new(5.7, 0.2, 5.7), Vector3.new(0, 0.7, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Window", Vector3.new(1.5, 1.2, 0.2), Vector3.new(0, 2.6, -2.6), Color3.fromRGB(80, 160, 200), Enum.Material.Glass, nil)
		kitPart(plinth, "Detail", Vector3.new(0.9, 0.9, 0.9), Vector3.new(2.0, 3.5, 2.0), pal.Accent, Enum.Material.Neon, Enum.PartType.Ball)
	elseif kit == "tower" then
		kitPart(plinth, "Body", Vector3.new(2.9, 5.8, 2.9), Vector3.new(0, 3.5, 0), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(3.8, 0.5, 3.8), Vector3.new(0, 6.6, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Antenna", Vector3.new(0.3, 3.5, 0.3), Vector3.new(0, 8.5, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Accent", Vector3.new(3.3, 0.22, 3.3), Vector3.new(0, 0.7, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Window", Vector3.new(1.0, 0.8, 0.2), Vector3.new(0, 4.5, -1.5), Color3.fromRGB(90, 140, 180), Enum.Material.Glass, nil)
		kitPart(plinth, "Detail", Vector3.new(0.7, 0.7, 0.7), Vector3.new(0, 7.0, 0), pal.Accent, Enum.Material.Neon, Enum.PartType.Ball)
	elseif kit == "dock" then
		kitPart(plinth, "Body", Vector3.new(7.5, 0.55, 7.5), Vector3.new(0, 0.9, 0), pal.Body, Enum.Material.Concrete, nil)
		kitPart(plinth, "Pier", Vector3.new(8.8, 0.4, 2.4), Vector3.new(0, 1.15, 3.3), pal.Roof, Enum.Material.Wood, nil)
		kitPart(plinth, "Accent", Vector3.new(7.2, 0.14, 0.4), Vector3.new(0, 1.25, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Detail", Vector3.new(1.2, 2.8, 0.4), Vector3.new(3.3, 2.1, 2.6), pal.Accent, Enum.Material.Metal, nil)
		kitPart(plinth, "Door", Vector3.new(1.8, 0.3, 1.2), Vector3.new(0, 1.35, 4.2), Color3.fromRGB(40, 55, 70), Enum.Material.Metal, nil)
	elseif kit == "pad" then
		kitPart(plinth, "Body", Vector3.new(7.3, 0.45, 7.3), Vector3.new(0, 0.92, 0), pal.Body, Enum.Material.Concrete, nil)
		kitPart(plinth, "Accent", Vector3.new(6.6, 0.14, 0.5), Vector3.new(0, 1.18, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Detail", Vector3.new(0.5, 0.14, 6.6), Vector3.new(0, 1.18, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Roof", Vector3.new(1.6, 0.3, 1.6), Vector3.new(0, 1.35, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Window", Vector3.new(0.5, 0.5, 0.5), Vector3.new(2.8, 1.4, 2.8), pal.Accent, Enum.Material.Neon, Enum.PartType.Ball)
	elseif kit == "wall" then
		-- Pad-local wall segment (perimeter walls are separate)
		kitPart(plinth, "Body", Vector3.new(7.5, 3.2, 1.8), Vector3.new(0, 2.2, 0), pal.Body, Enum.Material.Concrete, nil)
		kitPart(plinth, "Accent", Vector3.new(7.7, 0.28, 2.0), Vector3.new(0, 3.9, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Roof", Vector3.new(7.5, 0.45, 2.2), Vector3.new(0, 4.15, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(0.9, 1.4, 0.9), Vector3.new(-3.2, 3.4, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Detail", Vector3.new(0.9, 1.4, 0.9), Vector3.new(3.2, 3.4, 0), pal.Accent, Enum.Material.Neon, nil)
	elseif kit == "power" then
		kitPart(plinth, "Body", Vector3.new(4.6, 3.6, 4.6), Vector3.new(0, 2.5, 0), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(2.3, 2.3, 2.3), Vector3.new(0, 4.7, 0), pal.Accent, Enum.Material.Neon, Enum.PartType.Ball)
		kitPart(plinth, "Roof", Vector3.new(5.1, 0.4, 5.1), Vector3.new(0, 4.4, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Detail", Vector3.new(0.6, 2.5, 0.6), Vector3.new(2.0, 2.8, 2.0), Color3.fromRGB(60, 55, 40), Enum.Material.Metal, nil)
	elseif kit == "warehouse" then
		kitPart(plinth, "Body", Vector3.new(7.1, 2.8, 5.6), Vector3.new(0, 2.0, 0), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(7.5, 0.5, 6.1), Vector3.new(0, 3.55, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Accent", Vector3.new(7.3, 0.2, 5.9), Vector3.new(0, 0.7, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Door", Vector3.new(2.6, 2.2, 0.3), Vector3.new(0, 1.7, -2.95), Color3.fromRGB(50, 45, 38), Enum.Material.Metal, nil)
	else
		kitPart(plinth, "Body", Vector3.new(5.3, 3.5, 5.3), Vector3.new(0, 2.4, 0), pal.Body, Enum.Material.Metal, nil)
		kitPart(plinth, "Roof", Vector3.new(4.2, 1.2, 4.2), Vector3.new(0, 4.6, 0), pal.Roof, Enum.Material.Metal, nil)
		kitPart(plinth, "Antenna", Vector3.new(0.35, 4.2, 0.35), Vector3.new(0, 7.2, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Accent", Vector3.new(5.9, 0.22, 5.9), Vector3.new(0, 0.7, 0), pal.Accent, Enum.Material.Neon, nil)
		kitPart(plinth, "Detail", Vector3.new(1.0, 1.0, 1.0), Vector3.new(2.0, 3.5, -2.0), pal.Accent, Enum.Material.Neon, Enum.PartType.Ball)
	end
end

--[[ Ensure plinth has kit children; rebuild if missing/incomplete. Returns role count. ]]
function StructureKitBuilder.EnsureKit(plinth: BasePart, structureId: string): number
	local n = countKitRoles(plinth)
	-- Expect at least Body + one more for all kits
	if n < 2 then
		StructureKitBuilder.BuildKitOnPlinth(plinth, structureId)
		n = countKitRoles(plinth)
	end
	return n
end

local function findPlotPad(plotId: number): BasePart?
	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.BasePlot)) do
		if inst:IsA("BasePart") and inst:GetAttribute("PlotId") == plotId then
			return inst
		end
	end
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	local bases = setup and setup:FindFirstChild("Bases")
	local plotFolder = bases and bases:FindFirstChild("Plot" .. tostring(plotId))
	if plotFolder then
		local pad = plotFolder:FindFirstChild("PlotPad")
		if pad and pad:IsA("BasePart") then
			return pad
		end
	end
	return nil
end

function StructureKitBuilder.FindPlotFolder(plotId: number): Folder?
	local pad = findPlotPad(plotId)
	if pad and pad.Parent and pad.Parent:IsA("Folder") then
		return pad.Parent
	end
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	local bases = setup and setup:FindFirstChild("Bases")
	local plotFolder = bases and bases:FindFirstChild("Plot" .. tostring(plotId))
	if plotFolder and plotFolder:IsA("Folder") then
		return plotFolder
	end
	return nil
end

--[[ Perimeter fortification around PlotPad.
	level 0 clears; 1+ builds a collide wall ring with a walkable gate facing PlayerSpawn.
	BUGFIX: prior WallS used span*2 which overlapped and sealed the gate on 200-stud pads.
]]
function StructureKitBuilder.SyncPerimeterWalls(plotId: number, level: number)
	local plotFolder = StructureKitBuilder.FindPlotFolder(plotId)
	local pad = findPlotPad(plotId)
	if not plotFolder or not pad then
		return
	end

	local existing = plotFolder:FindFirstChild(PERIMETER_FOLDER)
	if level <= 0 then
		if existing then
			existing:Destroy()
		end
		return
	end

	local folder: Folder
	if existing and existing:IsA("Folder") then
		existing:ClearAllChildren()
		folder = existing
	else
		if existing then
			existing:Destroy()
		end
		folder = Instance.new("Folder")
		folder.Name = PERIMETER_FOLDER
		folder.Parent = plotFolder
	end

	local pal = paletteFor("DefensiveWalls")
	local lv = math.clamp(level, 1, 5)
	local halfX = pad.Size.X * 0.5 - 1.5
	local halfZ = pad.Size.Z * 0.5 - 1.5
	local thickness = 2.2 + lv * 0.45
	local height = 6.5 + lv * 2.2
	local y = pad.Position.Y + pad.Size.Y * 0.5 + height * 0.5
	local cx, cz = pad.Position.X, pad.Position.Z

	-- Clear walkable opening (8–12 studs). Posts/arch are visual-only outside this span.
	local GATE_CLEAR = 10
	local gateHalf = GATE_CLEAR * 0.5

	-- Gate faces PlayerSpawn (plot-local). Fallback: PlotForward attr, else pad LookVector / +Z.
	local gateAxis = "Z" -- gate on ±Z face; "X" = gate on ±X face
	local gateSign = 1
	local spawnPart = plotFolder:FindFirstChild("PlayerSpawn")
	local dx, dz = 0.0, 1.0
	if spawnPart and spawnPart:IsA("BasePart") then
		dx = spawnPart.Position.X - cx
		dz = spawnPart.Position.Z - cz
	else
		local attrFwd = plotFolder:GetAttribute("PlotForward")
		if typeof(attrFwd) == "Vector3" then
			dx = (attrFwd :: Vector3).X
			dz = (attrFwd :: Vector3).Z
		else
			local look = pad.CFrame.LookVector
			dx, dz = look.X, look.Z
			if math.abs(dx) < 0.05 and math.abs(dz) < 0.05 then
				dx, dz = 0, 1
			end
		end
	end
	if math.abs(dx) >= math.abs(dz) then
		gateAxis = "X"
		gateSign = if dx >= 0 then 1 else -1
	else
		gateAxis = "Z"
		gateSign = if dz >= 0 then 1 else -1
	end
	folder:SetAttribute("WE_GateAxis", gateAxis)
	folder:SetAttribute("WE_GateSign", gateSign)
	folder:SetAttribute("WE_GateClear", GATE_CLEAR)

	local function wall(name: string, size: Vector3, pos: Vector3)
		local w = makePart({
			Name = name,
			Size = size,
			Position = pos,
			Color = pal.Body,
			Material = Enum.Material.Concrete,
			Transparency = 0,
			CanCollide = true,
			Parent = folder,
		})
		w.CanTouch = false
		w.CanQuery = true
		w.CastShadow = true
		w:SetAttribute("WE_Perimeter", true)
		w:SetAttribute("PlotId", plotId)
		w:SetAttribute("WE_WallLevel", lv)
		local capH = 0.45 + lv * 0.08
		local cap = makePart({
			Name = name .. "_Cap",
			Size = Vector3.new(size.X + 0.4, capH, size.Z + 0.4),
			Position = Vector3.new(pos.X, pos.Y + height * 0.5 + capH * 0.5, pos.Z),
			Color = pal.Accent,
			Material = Enum.Material.Neon,
			Transparency = 0.05,
			CanCollide = false,
			Parent = folder,
		})
		cap:SetAttribute("WE_Perimeter", true)
		return w
	end

	-- Segment from outer corner to gate edge: length = alongHalf - gateHalf (NOT *2 — that sealed the gate).
	local function gateFaceSegments(alongHalf: number): (number, number)
		local segLen = math.max(alongHalf - gateHalf, 2)
		local mid = (alongHalf + gateHalf) * 0.5
		return segLen, mid
	end

	if gateAxis == "Z" then
		local closedZ = cz - gateSign * halfZ
		local openZ = cz + gateSign * halfZ
		wall("WallClosed", Vector3.new(halfX * 2, height, thickness), Vector3.new(cx, y, closedZ))
		wall("WallE", Vector3.new(thickness, height, halfZ * 2), Vector3.new(cx + halfX, y, cz))
		wall("WallW", Vector3.new(thickness, height, halfZ * 2), Vector3.new(cx - halfX, y, cz))
		local segLen, mid = gateFaceSegments(halfX)
		if segLen > 2 then
			wall("WallGate_L", Vector3.new(segLen, height, thickness), Vector3.new(cx - mid, y, openZ))
			wall("WallGate_R", Vector3.new(segLen, height, thickness), Vector3.new(cx + mid, y, openZ))
		end
		local postW = 2.2 + lv * 0.15
		local postH = height + 1.5
		local postY = pad.Position.Y + pad.Size.Y * 0.5 + postH * 0.5
		local postInset = gateHalf + postW * 0.5 -- outside clear opening
		for _, sx in ipairs({ -postInset, postInset }) do
			local post = makePart({
				Name = "GatePost",
				Size = Vector3.new(postW, postH, postW),
				Position = Vector3.new(cx + sx, postY, openZ),
				Color = pal.Roof,
				Material = Enum.Material.Metal,
				Transparency = 0,
				CanCollide = false,
				Parent = folder,
			})
			post:SetAttribute("WE_Perimeter", true)
			post:SetAttribute("WE_GateVisual", true)
			post.CastShadow = true
		end
		local arch = makePart({
			Name = "GateArch",
			Size = Vector3.new(GATE_CLEAR + postW * 2, 1.2, thickness + 0.6),
			Position = Vector3.new(cx, pad.Position.Y + pad.Size.Y * 0.5 + height + 0.4, openZ),
			Color = pal.Accent,
			Material = Enum.Material.Metal,
			Transparency = 0,
			CanCollide = false,
			Parent = folder,
		})
		arch:SetAttribute("WE_Perimeter", true)
		arch:SetAttribute("WE_GateVisual", true)
	else
		local closedX = cx - gateSign * halfX
		local openX = cx + gateSign * halfX
		wall("WallClosed", Vector3.new(thickness, height, halfZ * 2), Vector3.new(closedX, y, cz))
		wall("WallN", Vector3.new(halfX * 2, height, thickness), Vector3.new(cx, y, cz - halfZ))
		wall("WallS", Vector3.new(halfX * 2, height, thickness), Vector3.new(cx, y, cz + halfZ))
		local segLen, mid = gateFaceSegments(halfZ)
		if segLen > 2 then
			wall("WallGate_L", Vector3.new(thickness, height, segLen), Vector3.new(openX, y, cz - mid))
			wall("WallGate_R", Vector3.new(thickness, height, segLen), Vector3.new(openX, y, cz + mid))
		end
		local postW = 2.2 + lv * 0.15
		local postH = height + 1.5
		local postY = pad.Position.Y + pad.Size.Y * 0.5 + postH * 0.5
		local postInset = gateHalf + postW * 0.5
		for _, sz in ipairs({ -postInset, postInset }) do
			local post = makePart({
				Name = "GatePost",
				Size = Vector3.new(postW, postH, postW),
				Position = Vector3.new(openX, postY, cz + sz),
				Color = pal.Roof,
				Material = Enum.Material.Metal,
				Transparency = 0,
				CanCollide = false,
				Parent = folder,
			})
			post:SetAttribute("WE_Perimeter", true)
			post:SetAttribute("WE_GateVisual", true)
			post.CastShadow = true
		end
		local arch = makePart({
			Name = "GateArch",
			Size = Vector3.new(thickness + 0.6, 1.2, GATE_CLEAR + postW * 2),
			Position = Vector3.new(openX, pad.Position.Y + pad.Size.Y * 0.5 + height + 0.4, cz),
			Color = pal.Accent,
			Material = Enum.Material.Metal,
			Transparency = 0,
			CanCollide = false,
			Parent = folder,
		})
		arch:SetAttribute("WE_Perimeter", true)
		arch:SetAttribute("WE_GateVisual", true)
	end
end

function StructureKitBuilder.SyncCornerTowers(plotId: number, level: number)
	local plotFolder = StructureKitBuilder.FindPlotFolder(plotId)
	local pad = findPlotPad(plotId)
	if not plotFolder or not pad then
		return
	end

	local existing = plotFolder:FindFirstChild(CORNER_FOLDER)
	if level <= 0 then
		if existing then
			existing:Destroy()
		end
		return
	end

	local folder: Folder
	if existing and existing:IsA("Folder") then
		existing:ClearAllChildren()
		folder = existing
	else
		if existing then
			existing:Destroy()
		end
		folder = Instance.new("Folder")
		folder.Name = CORNER_FOLDER
		folder.Parent = plotFolder
	end

	local pal = paletteFor("Watchtowers")
	local lv = math.clamp(level, 1, 5)
	local half = math.max(pad.Size.X, pad.Size.Z) * 0.5 - 3
	local towerW = 4.5 + lv * 0.3
	local towerH = 10 + lv * 2.5
	local y = pad.Position.Y + pad.Size.Y * 0.5 + towerH * 0.5
	local cx, cz = pad.Position.X, pad.Position.Z
	local corners = {
		Vector3.new(cx - half, y, cz - half),
		Vector3.new(cx + half, y, cz - half),
		Vector3.new(cx - half, y, cz + half),
		Vector3.new(cx + half, y, cz + half),
	}
	for i, pos in ipairs(corners) do
		local body = makePart({
			Name = "CornerTower" .. i,
			Size = Vector3.new(towerW, towerH, towerW),
			Position = pos,
			Color = pal.Body,
			Material = Enum.Material.Concrete,
			Transparency = 0,
			CanCollide = true,
			Parent = folder,
		})
		body.CastShadow = true
		body:SetAttribute("WE_CornerTower", true)
		makePart({
			Name = "TowerCap" .. i,
			Size = Vector3.new(towerW + 1.2, 0.6, towerW + 1.2),
			Position = Vector3.new(pos.X, pos.Y + towerH * 0.5 + 0.35, pos.Z),
			Color = pal.Roof,
			Material = Enum.Material.Metal,
			Transparency = 0,
			CanCollide = false,
			Parent = folder,
		})
		makePart({
			Name = "TowerBeacon" .. i,
			Size = Vector3.new(0.6, 2.2 + lv * 0.4, 0.6),
			Position = Vector3.new(pos.X, pos.Y + towerH * 0.5 + 2, pos.Z),
			Color = pal.Accent,
			Material = Enum.Material.Neon,
			Transparency = 0,
			CanCollide = false,
			Parent = folder,
		})
	end
end

function StructureKitBuilder.ClearPlotExtras(plotId: number)
	StructureKitBuilder.SyncPerimeterWalls(plotId, 0)
	StructureKitBuilder.SyncCornerTowers(plotId, 0)
end

return StructureKitBuilder
