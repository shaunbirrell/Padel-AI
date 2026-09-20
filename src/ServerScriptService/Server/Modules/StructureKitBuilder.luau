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

--[[ Perimeter fortification around PlotPad. level 0 clears; 1+ builds wall ring with +Z gate. ]]
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
	local half = math.max(pad.Size.X, pad.Size.Z) * 0.5 - 1.5 -- just inside pad edge
	local thickness = 2.2 + lv * 0.45
	local height = 6.5 + lv * 2.2
	local y = pad.Position.Y + pad.Size.Y * 0.5 + height * 0.5
	local gateHalf = 14 -- walk gap on +Z (spawn) side
	local cx, cz = pad.Position.X, pad.Position.Z

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
		-- Cap / battlement strip
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

	-- North (-Z), East (+X), West (-X): full spans
	wall("WallN", Vector3.new(half * 2, height, thickness), Vector3.new(cx, y, cz - half))
	wall("WallE", Vector3.new(thickness, height, half * 2), Vector3.new(cx + half, y, cz))
	wall("WallW", Vector3.new(thickness, height, half * 2), Vector3.new(cx - half, y, cz))
	-- South (+Z): split around gate
	local span = half - gateHalf
	if span > 4 then
		local mid = (half + gateHalf) * 0.5
		wall("WallS_L", Vector3.new(span * 2 - 2, height, thickness), Vector3.new(cx - mid, y, cz + half))
		wall("WallS_R", Vector3.new(span * 2 - 2, height, thickness), Vector3.new(cx + mid, y, cz + half))
	end
	-- Gate posts
	local postW = 2.4 + lv * 0.2
	local postH = height + 2
	for _, sx in ipairs({ -gateHalf, gateHalf }) do
		local post = makePart({
			Name = "GatePost",
			Size = Vector3.new(postW, postH, postW),
			Position = Vector3.new(cx + sx, pad.Position.Y + pad.Size.Y * 0.5 + postH * 0.5, cz + half),
			Color = pal.Roof,
			Material = Enum.Material.Metal,
			Transparency = 0,
			CanCollide = true,
			Parent = folder,
		})
		post:SetAttribute("WE_Perimeter", true)
		post.CastShadow = true
	end
end

--[[ Corner watchtowers when Watchtowers upgraded. ]]
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
