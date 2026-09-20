--!strict
--[[
	Loads free Creator Store Models via InsertService (fallback AssetService).
	Caches clones; strips all scripts; never blocks Part-kit spawn on failure.
	Respects DevConfig.StudioSkipWorldDressing for 8GB Studio PERF.
]]

local InsertService = game:GetService("InsertService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local VisualAssetConfig = require(Shared.Configs.VisualAssetConfig)
local DevConfig = require(Shared.Configs.DevConfig)

local VisualAssetService = {}

local cache: { [number]: Model } = {} -- template models (parented to nil / folder)
local failed: { [number]: boolean } = {}
local loadAttempts = 0
local templatesFolder: Folder? = nil

local function ensureFolder(): Folder
	if templatesFolder and templatesFolder.Parent then
		return templatesFolder
	end
	local f = Instance.new("Folder")
	f.Name = "WE_VisualAssetTemplates"
	f.Parent = ReplicatedStorage
	templatesFolder = f
	return f
end

local function shouldSkipInserts(): boolean
	if not VisualAssetConfig.Enabled then
		return true
	end
	if RunService:IsStudio() then
		local force = DevConfig.StudioForceDress == true
		if DevConfig.StudioSkipWorldDressing ~= false and not force then
			return true
		end
	end
	return false
end

local function stripScripts(root: Instance)
	if not VisualAssetConfig.StripScripts then
		return
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BaseScript") or d:IsA("ModuleScript") then
			d:Destroy()
		end
	end
	-- Also direct children scripts
	for _, c in ipairs(root:GetChildren()) do
		if c:IsA("BaseScript") or c:IsA("ModuleScript") then
			c:Destroy()
		end
	end
end

local function loadModel(assetId: number, forceInsert: boolean?): Model?
	if assetId == 0 or failed[assetId] then
		return nil
	end
	if cache[assetId] then
		return cache[assetId]
	end
	-- P0: character dress MUST run even when StudioSkipWorldDressing (workers never brown bricks)
	if shouldSkipInserts() and not forceInsert then
		return nil
	end
	if loadAttempts >= (VisualAssetConfig.MaxLoadAttempts or 36) then
		return nil
	end
	loadAttempts += 1

	local ok, result = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok or typeof(result) ~= "Instance" then
		-- AssetService fallback (newer API)
		local AssetService = game:GetService("AssetService")
		if AssetService and (AssetService :: any).LoadAssetAsync then
			ok, result = pcall(function()
				return (AssetService :: any):LoadAssetAsync(assetId)
			end)
		end
	end
	if not ok or typeof(result) ~= "Instance" then
		failed[assetId] = true
		warn("[VisualAssetService] LoadAsset failed", assetId, result)
		return nil
	end

	local container = result :: Instance
	stripScripts(container)
	local model: Model? = nil
	if container:IsA("Model") then
		model = container
	else
		for _, c in ipairs(container:GetChildren()) do
			if c:IsA("Model") then
				model = c
				break
			end
		end
	end
	if not model then
		failed[assetId] = true
		container:Destroy()
		warn("[VisualAssetService] No Model in asset", assetId)
		return nil
	end

	stripScripts(model)
	model.Name = "WE_Asset_" .. tostring(assetId)
	-- Anchor all for template; clones will reconfigure
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CastShadow = false
			d.Massless = true
		end
	end
	model.Parent = ensureFolder()
	cache[assetId] = model
	if container ~= model and container.Parent == nil then
		-- LoadAsset returns Model in a Model container sometimes
		pcall(function()
			container:Destroy()
		end)
	elseif container ~= model then
		-- keep only our template
		for _, c in ipairs(container:GetChildren()) do
			if c ~= model then
				c:Destroy()
			end
		end
		model.Parent = ensureFolder()
		pcall(function()
			container:Destroy()
		end)
	end
	print("[VisualAssetService] Cached catalog model", assetId, model.Name)
	return model
end

local function weldCloneToPrimary(clone: Model, primary: BasePart, cloneName: string): boolean
	stripScripts(clone)
	clone.Name = cloneName

	-- Strip seats / humanoids / scripts / constraints — mesh is dress-only, never drive
	for _, d in ipairs(clone:GetDescendants()) do
		if
			d:IsA("Humanoid")
			or d:IsA("Tool")
			or d:IsA("VehicleSeat")
			or d:IsA("Seat")
			or d:IsA("BaseScript")
			or d:IsA("ModuleScript")
			or d:IsA("HingeConstraint")
			or d:IsA("CylindricalConstraint")
			or d:IsA("SpringConstraint")
			or d:IsA("PrismaticConstraint")
			or d:IsA("RodConstraint")
			or d:IsA("VectorForce")
			or d:IsA("LinearVelocity")
			or d:IsA("AngularVelocity")
		then
			d:Destroy()
		end
	end

	pcall(function()
		clone:PivotTo(primary.CFrame)
	end)

	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			d.CastShadow = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = primary
			weld.Part1 = d
			weld.Parent = d
		end
	end
	return true
end

function VisualAssetService.IsInsertEnabled(): boolean
	return not shouldSkipInserts()
end

function VisualAssetService.ResolveVehicleAssetId(vehicleId: string, kitFamily: string?): number?
	local ref = VisualAssetConfig.Vehicles[vehicleId]
	if ref and typeof(ref.ModelAssetId) == "number" and (ref.ModelAssetId :: number) > 0 then
		return ref.ModelAssetId
	end
	if kitFamily and VisualAssetConfig.KitFamilyFallback[kitFamily] then
		local key = VisualAssetConfig.KitFamilyFallback[kitFamily]
		local fb = VisualAssetConfig.Vehicles[key]
		if fb and typeof(fb.ModelAssetId) == "number" and (fb.ModelAssetId :: number) > 0 then
			return fb.ModelAssetId
		end
	end
	return nil
end

function VisualAssetService.ResolveCharacterAssetId(kind: string): number?
	local ref = VisualAssetConfig.Characters[kind]
	if not ref and kind == "Worker" then
		ref = VisualAssetConfig.Characters.Infantry or VisualAssetConfig.Characters.Soldier
	end
	if not ref then
		ref = VisualAssetConfig.Characters.Soldier
	end
	if ref and typeof(ref.ModelAssetId) == "number" and (ref.ModelAssetId :: number) > 0 then
		return ref.ModelAssetId
	end
	local alt = (VisualAssetConfig :: any).CharacterAlt
	if alt and typeof(alt.ModelAssetId) == "number" and (alt.ModelAssetId :: number) > 0 then
		return alt.ModelAssetId
	end
	return nil
end

function VisualAssetService.ResolveBuildingAssetId(structureId: string): number?
	local ref = VisualAssetConfig.Buildings[structureId]
	if ref and typeof(ref.ModelAssetId) == "number" and (ref.ModelAssetId :: number) > 0 then
		return ref.ModelAssetId
	end
	-- Fallback StructureVisualConfig.MeshAssetId (0 = composite / Part kit only)
	local ok, svc = pcall(function()
		return require(ReplicatedStorage.Shared.Configs.StructureVisualConfig)
	end)
	if ok and svc and svc.Palettes then
		local pal = svc.Palettes[structureId]
		if pal and typeof(pal.MeshAssetId) == "number" and (pal.MeshAssetId :: number) > 0 then
			return pal.MeshAssetId
		end
	end
	return nil
end

local function lookupPropRef(propKey: string): any
	local buckets = {
		(VisualAssetConfig :: any).WarzoneProps,
		VisualAssetConfig.DesertProps,
		(VisualAssetConfig :: any).MapDressing,
		(VisualAssetConfig :: any).IndustrialProps,
		(VisualAssetConfig :: any).Landmarks,
	}
	for _, bucket in ipairs(buckets) do
		if typeof(bucket) == "table" then
			local ref = bucket[propKey]
			if typeof(ref) == "table" then
				return ref
			end
		end
	end
	return nil
end

function VisualAssetService.ResolvePropAssetId(propKey: string): number?
	local ref = lookupPropRef(propKey)
	if ref and typeof(ref.ModelAssetId) == "number" and (ref.ModelAssetId :: number) > 0 then
		return ref.ModelAssetId
	end
	return nil
end

function VisualAssetService.ResolvePropMeshId(propKey: string): number?
	local ref = lookupPropRef(propKey)
	if ref and typeof(ref.MeshId) == "number" and (ref.MeshId :: number) > 0 then
		return ref.MeshId
	end
	return nil
end

--[[
	Clone catalog visual under hostModel, welded to primary, non-colliding.
	Returns true if attached. Never destroys host Part kit.
]]
function VisualAssetService.TryAttachVehicleVisual(hostModel: Model, vehicleId: string, kitFamily: string?): boolean
	local assetId = VisualAssetService.ResolveVehicleAssetId(vehicleId, kitFamily)
	if not assetId then
		return false
	end
	local template = loadModel(assetId)
	-- Design P0: NO JeepFallback 59524622. Part-kit hinge chassis remains if mesh fails.
	if not template then
		return false -- Part kit remains authoritative (hinge-drive)
	end
	local primary = hostModel.PrimaryPart
	if not primary then
		return false
	end

	local clone = template:Clone()
	if not weldCloneToPrimary(clone, primary, "WE_CatalogVisual") then
		clone:Destroy()
		return false
	end

	clone.Parent = hostModel
	hostModel:SetAttribute("WE_CatalogAssetId", assetId)
	-- Soften host body so catalog mesh reads; keep Part-kit physics wheels (hidden)
	primary.Transparency = math.max(primary.Transparency, 0.72)
	for _, d in ipairs(hostModel:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("WE_PhysicsWheel") == true then
			d.Transparency = 1 -- physics collider/motor only; mesh provides visible tires
			d.CanCollide = true
			d.Massless = false
		elseif d:IsA("BasePart") and d:GetAttribute("WE_KitCosmetic") == true then
			d.Transparency = math.max(d.Transparency, 0.85)
		end
	end
	-- Re-assert DriverSeat still present after mesh dress
	if not hostModel:FindFirstChild("DriverSeat") then
		warn("[VisualAssetService] DriverSeat missing after mesh attach — host kit corrupted")
	end
	return true
end

--[[
	Optional character visual overlay for NPC Part kits.
	Attaches non-colliding clone; host HumanoidRootPart stays authoritative.
]]
function VisualAssetService.TryAttachCharacterVisual(hostModel: Model, kind: string): boolean
	-- P0: always attempt character catalog inserts (bypass StudioSkipWorldDressing)
	local forceChar = true
	local assetId = VisualAssetService.ResolveCharacterAssetId(kind)
	if not assetId then
		return false
	end
	local template = loadModel(assetId, forceChar)
	-- Worker/Infantry → WorkerFallback (16134469614) → never leave brown Part bricks
	if not template then
		local fb = (VisualAssetConfig.Characters :: any).WorkerFallback
		local fbId = if fb and typeof(fb.ModelAssetId) == "number" then fb.ModelAssetId else 0
		if typeof(fbId) == "number" and fbId > 0 and fbId ~= assetId then
			template = loadModel(fbId, forceChar)
			if template then
				assetId = fbId
			end
		end
	end
	if not template and (kind == "Worker" or kind == "Infantry") then
		-- Final realistic fallback: Guard mesh
		local guard = VisualAssetConfig.Characters.Guard
		local gId = if guard and typeof(guard.ModelAssetId) == "number" then guard.ModelAssetId else 0
		if typeof(gId) == "number" and gId > 0 then
			template = loadModel(gId, forceChar)
			if template then
				assetId = gId
			end
		end
	end
	if not template then
		return false
	end
	local primary = hostModel.PrimaryPart or hostModel:FindFirstChild("HumanoidRootPart")
	if not (primary and primary:IsA("BasePart")) then
		return false
	end

	local clone = template:Clone()
	if not weldCloneToPrimary(clone, primary :: BasePart, "WE_CatalogCharacter") then
		clone:Destroy()
		return false
	end
	clone.Parent = hostModel
	hostModel:SetAttribute("WE_CatalogAssetId", assetId)
	-- Soften Part-kit body so realistic soldier mesh reads (dress-only)
	if primary:IsA("BasePart") then
		primary.Transparency = math.max(primary.Transparency, 0.85)
	end
	for _, d in ipairs(hostModel:GetDescendants()) do
		if d:IsA("BasePart") and d.Parent ~= clone and not d:IsDescendantOf(clone) then
			if d.Name ~= "HumanoidRootPart" then
				d.Transparency = math.max(d.Transparency, 0.92)
			end
		end
	end
	return true
end

--[[
	Optional building visual overlay for structure plinth Part kits.
	Welded non-colliding; plinth remains authoritative for walk-buy.
]]
function VisualAssetService.TryAttachBuildingVisual(hostPart: BasePart, structureId: string, level: number?): boolean
	-- STRUCTURE_SCALE_WIRE v21: ScaleTo TargetFootprint; NEVER MeshPart.Size = plinth.
	local DRESS_GEN = 29 -- v42: Hangar≠Warehouse≠Depot, Missile≠Tower; sync StructureVisualConfig.BuildingDressGen
	local REJECTED: { [number]: boolean } = {
		[12370174722] = true, -- blockout Airport Model (Design REJECT)
		[46981739] = true, -- tiny Plane Hangar (Design REJECT)
		[13195201090] = true, -- Build-a-Boat template (Design REJECT capital)
		[12630605935] = true, -- civilian Airplane Hangar text (not ceiling)
		[11399477618] = true, -- nation-branded gate
		[10339789720] = true, -- nation-branded gate
	}

	local existingGen = tonumber(hostPart:GetAttribute("WE_BuildingDressGen"))
	if hostPart:GetAttribute("WE_CatalogAssetId") and existingGen == DRESS_GEN then
		return false
	end
	if existingGen ~= DRESS_GEN then
		for _, ch in ipairs(hostPart:GetChildren()) do
			if ch:IsA("Model") and (ch.Name == "WE_CatalogBuilding" or ch.Name == "WE_AirfieldComposite" or string.sub(ch.Name, 1, 14) == "WE_CatalogBuild") then
				ch:Destroy()
			elseif ch:IsA("BasePart") and ch:GetAttribute("WE_AirfieldComposite") == true then
				ch:Destroy()
			end
		end
		hostPart:SetAttribute("WE_CatalogAssetId", nil)
	end

	-- v39 P0: NEVER ghost Part-kit silhouettes. Catalog mesh is optional dress on top.
	-- Prior hideKitBody (Transparency≥0.92) left empty pads when mesh failed/mis-scaled.
	local function hideKitBody()
		-- no-op: Part kits stay solid olive/military buildings
	end

	local function footprintFor(id: string): Vector3
		local ok, svc = pcall(function()
			return require(ReplicatedStorage.Shared.Configs.StructureVisualConfig)
		end)
		if ok and svc and svc.Palettes and svc.Palettes[id] and typeof(svc.Palettes[id].TargetFootprint) == "Vector3" then
			return svc.Palettes[id].TargetFootprint
		end
		local defaults: { [string]: Vector3 } = {
			CommandCenter = Vector3.new(36, 16, 28),
			Barracks = Vector3.new(28, 12, 16),
			VehicleDepot = Vector3.new(32, 14, 24),
			WeaponsFacility = Vector3.new(28, 18, 18),
			Warehouse = Vector3.new(36, 14, 22),
			Hangar = Vector3.new(40, 18, 28),
			Helipad = Vector3.new(22, 3, 22),
			Airfield = Vector3.new(70, 1, 10),
			Watchtowers = Vector3.new(10, 32, 10),
			Radar = Vector3.new(14, 18, 14),
			ResearchLab = Vector3.new(22, 12, 16),
			Dock = Vector3.new(40, 8, 16),
			PowerStation = Vector3.new(28, 16, 20),
			DefensiveWalls = Vector3.new(24, 8, 3),
			MissileDefense = Vector3.new(14, 10, 18),
			SpecialForcesFacility = Vector3.new(26, 14, 16),
			BaseGate = Vector3.new(16, 12, 4),
		}
		return defaults[id] or Vector3.new(28, 14, 20)
	end

	local function scaleModelToFootprint(model: Model, target: Vector3): number
		local ext = model:GetExtentsSize()
		local factor = math.min(target.X / math.max(ext.X, 0.05), target.Y / math.max(ext.Y, 0.05), target.Z / math.max(ext.Z, 0.05))
		factor = math.clamp(factor, 0.05, 80)
		local okScale = pcall(function()
			model:ScaleTo(factor)
		end)
		if not okScale then
			warn("[VisualAssetService] ScaleTo failed", structureId, factor)
		end
		return factor
	end

	local function weldScaledBuilding(clone: Model, target: Vector3, cloneName: string): boolean
		scaleModelToFootprint(clone, target)
		local topY = hostPart.Position.Y + hostPart.Size.Y * 0.5
		pcall(function()
			local ext = clone:GetExtentsSize()
			clone:PivotTo(CFrame.new(hostPart.Position.X, topY + ext.Y * 0.5, hostPart.Position.Z) * (hostPart.CFrame - hostPart.Position))
		end)
		if not weldCloneToPrimary(clone, hostPart, cloneName) then
			return false
		end
		clone.Parent = hostPart
		return true
	end

	-- Airfield COMPOSITE: runway 70×1×10 + asphalt decal + Hangar 6015472062
	if structureId == "Airfield" then
		local folder = Instance.new("Model")
		folder.Name = "WE_AirfieldComposite"
		folder.Parent = hostPart

		local runway = Instance.new("Part")
		runway.Name = "WE_Runway"
		runway.Size = Vector3.new(70, 1, 10)
		runway.Anchored = true
		runway.CanCollide = false
		runway.CanQuery = false
		runway.CanTouch = false
		runway.Material = Enum.Material.Asphalt
		runway.Color = Color3.fromRGB(45, 48, 52)
		runway.CastShadow = true
		local look = hostPart.CFrame.LookVector
		runway.CFrame = CFrame.new(hostPart.Position + look * 28 + Vector3.new(0, 0.55, 0)) * (hostPart.CFrame - hostPart.Position)
		runway:SetAttribute("WE_AirfieldComposite", true)
		runway.Parent = folder
		pcall(function()
			VisualAssetService.ApplyAsphaltDecal(runway)
		end)
		for i = -3, 3 do
			local dash = Instance.new("Part")
			dash.Name = "WE_RunwayDash"
			dash.Size = Vector3.new(4, 0.12, 0.55)
			dash.Anchored = true
			dash.CanCollide = false
			dash.CanQuery = false
			dash.Material = Enum.Material.SmoothPlastic
			dash.Color = Color3.fromRGB(240, 240, 220)
			dash.CFrame = runway.CFrame * CFrame.new(i * 8, 0.56, 0)
			dash:SetAttribute("WE_AirfieldComposite", true)
			dash.Parent = folder
		end

		local hangarId = 6015472062
		local hangarTemplate = loadModel(hangarId)
		if hangarTemplate then
			local hangar = hangarTemplate:Clone()
			scaleModelToFootprint(hangar, footprintFor("Hangar"))
			local ext = hangar:GetExtentsSize()
			pcall(function()
				hangar:PivotTo(runway.CFrame * CFrame.new(32, ext.Y * 0.5, 0))
			end)
			stripScripts(hangar)
			hangar.Name = "WE_CatalogHangar"
			for _, d in ipairs(hangar:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = false
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
					d.Massless = true
					local w = Instance.new("WeldConstraint")
					w.Part0 = hostPart
					w.Part1 = d
					w.Parent = d
				end
			end
			hangar.Parent = folder
		else
			warn("[VisualAssetService] Hangar insert failed — Part shed fallback", hangarId)
			local shed = Instance.new("Part")
			shed.Name = "WE_HangarShed"
			shed.Size = Vector3.new(40, 18, 28)
			shed.Anchored = true
			shed.CanCollide = false
			shed.Material = Enum.Material.Metal
			shed.Color = Color3.fromRGB(70, 75, 68)
			shed.CFrame = runway.CFrame * CFrame.new(32, 9, 0)
			shed:SetAttribute("WE_AirfieldComposite", true)
			shed.Parent = folder
			local mouth = Instance.new("Part")
			mouth.Name = "WE_HangarMouth"
			mouth.Size = Vector3.new(0.4, 14, 22)
			mouth.Anchored = true
			mouth.CanCollide = false
			mouth.Material = Enum.Material.Metal
			mouth.Color = Color3.fromRGB(30, 32, 28)
			mouth.CFrame = shed.CFrame * CFrame.new(-20.2, -1, 0)
			mouth:SetAttribute("WE_AirfieldComposite", true)
			mouth.Parent = folder
			hangarId = -6015472062
		end

		hideKitBody()
		hostPart:SetAttribute("WE_CatalogAssetId", hangarId)
		hostPart:SetAttribute("WE_BuildingDressGen", DRESS_GEN)
		return true
	end

	local assetId = VisualAssetService.ResolveBuildingAssetId(structureId)
	local lv = tonumber(level) or 0
	if structureId == "DefensiveWalls" and lv >= 3 then
		local l3 = VisualAssetConfig.Buildings.DefensiveWallsL3
		if l3 and typeof(l3.ModelAssetId) == "number" and (l3.ModelAssetId :: number) > 0 then
			assetId = l3.ModelAssetId
		else
			local okSvc, StructureVisualConfig = pcall(function()
				return require(ReplicatedStorage.Shared.Configs.StructureVisualConfig)
			end)
			if okSvc and StructureVisualConfig then
				local pal = StructureVisualConfig.Palettes and StructureVisualConfig.Palettes.DefensiveWalls
				if pal and typeof(pal.MeshAssetIdL3) == "number" and pal.MeshAssetIdL3 > 0 then
					assetId = pal.MeshAssetIdL3
				end
			end
		end
	end
	if not assetId or assetId <= 0 or REJECTED[assetId] == true then
		if assetId and REJECTED[assetId] then
			warn("[VisualAssetService] REJECTED building asset", structureId, assetId)
		end
		return false
	end
	local template = loadModel(assetId)
	if not template then
		warn("[VisualAssetService] Insert failed — Part kit remains", structureId, assetId)
		return false
	end

	local clone = template:Clone()
	if not weldScaledBuilding(clone, footprintFor(structureId), "WE_CatalogBuilding") then
		clone:Destroy()
		return false
	end
	hostPart:SetAttribute("WE_CatalogAssetId", assetId)
	hostPart:SetAttribute("WE_BuildingDressGen", DRESS_GEN)
	if structureId == "BaseGate" then
		hostPart:SetAttribute("WE_DisplayName", "Base Gate")
		local dressed = hostPart:FindFirstChild("WE_CatalogBuilding")
		if dressed and dressed:IsA("Model") then
			dressed.Name = "WE_BaseGate"
		end
	end
	hideKitBody()
	return true
end


--[[
	Optional desert prop overlay (cactus etc.) welded to a flora host part.
]]
--[[
	Attach MeshPart dress when catalog entry is MeshId-only (AssetType 40).
	Falls back to SpecialMesh on a Part if MeshPart.MeshId set fails.
]]
function VisualAssetService.TryAttachMeshPartVisual(hostPart: BasePart, meshId: number, label: string?): boolean
	if hostPart:GetAttribute("WE_CatalogAssetId") or hostPart:GetAttribute("WE_MeshId") then
		return false
	end
	if meshId <= 0 or shouldSkipInserts() then
		return false
	end
	local ok, err = pcall(function()
		local mp = Instance.new("MeshPart")
		mp.Name = label or "WE_CatalogMeshPart"
		mp.Size = hostPart.Size
		mp.Anchored = true
		mp.CanCollide = false
		mp.CanQuery = false
		mp.CanTouch = false
		mp.CastShadow = false
		mp.Massless = true
		-- MeshId via rbxassetid; if InsertService Model fails for type-40 assets
		mp.MeshId = "rbxassetid://" .. tostring(meshId)
		mp.TextureID = ""
		mp.CFrame = hostPart.CFrame
		mp.Parent = hostPart
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hostPart
		weld.Part1 = mp
		weld.Parent = mp
	end)
	if not ok then
		-- Fallback: Part + SpecialMesh
		local ok2 = pcall(function()
			local holder = Instance.new("Part")
			holder.Name = label or "WE_CatalogMeshHolder"
			holder.Size = hostPart.Size
			holder.Transparency = 1
			holder.Anchored = true
			holder.CanCollide = false
			holder.CanQuery = false
			holder.CanTouch = false
			holder.Massless = true
			holder.CFrame = hostPart.CFrame
			holder.Parent = hostPart
			local sm = Instance.new("SpecialMesh")
			sm.MeshType = Enum.MeshType.FileMesh
			sm.MeshId = "rbxassetid://" .. tostring(meshId)
			sm.Scale = Vector3.new(1, 1, 1)
			sm.Parent = holder
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = hostPart
			weld.Part1 = holder
			weld.Parent = holder
		end)
		if not ok2 then
			warn("[VisualAssetService] MeshPart pipeline failed", meshId, err)
			return false
		end
	end
	hostPart:SetAttribute("WE_MeshId", meshId)
	hostPart.Transparency = math.max(hostPart.Transparency, 0.7)
	return true
end

function VisualAssetService.TryAttachPropVisual(hostPart: BasePart, propKey: string): boolean
	if hostPart:GetAttribute("WE_CatalogAssetId") or hostPart:GetAttribute("WE_MeshId") then
		return false
	end
	-- MeshPart-only keys (DesertRock): prefer MeshId pipeline
	local meshId = VisualAssetService.ResolvePropMeshId(propKey)
	local assetId = VisualAssetService.ResolvePropAssetId(propKey)
	if (not assetId or assetId <= 0) and meshId then
		return VisualAssetService.TryAttachMeshPartVisual(hostPart, meshId, "WE_CatalogProp_" .. propKey)
	end
	if not assetId then
		return false
	end
	local template = loadModel(assetId)
	-- Palm/Tent/OilPumpjack alt fallback (Design Bot wire)
	if not template and (propKey == "Palm" or propKey == "Tent" or propKey == "OilPumpjack") then
		local altKey = if propKey == "Palm" then "PalmAlt" elseif propKey == "Tent" then "TentAlt" else "OilPumpjackAlt"
		local altId = VisualAssetService.ResolvePropAssetId(altKey)
		if altId then
			template = loadModel(altId)
			if template then
				assetId = altId
			end
		end
	end
	if not template then
		-- Last resort MeshId if both Model inserts fail
		if meshId then
			return VisualAssetService.TryAttachMeshPartVisual(hostPart, meshId, "WE_CatalogProp_" .. propKey)
		end
		return false
	end

	local clone = template:Clone()
	if not weldCloneToPrimary(clone, hostPart, "WE_CatalogProp") then
		clone:Destroy()
		return false
	end
	clone.Parent = hostPart
	hostPart:SetAttribute("WE_CatalogAssetId", assetId)
	hostPart.Transparency = math.max(hostPart.Transparency, 0.65)
	return true
end

--[[
	Paint asphalt Decal (Texture) on road Part faces. Uses MapDressing.AsphaltDecal MeshId as Decal texture id.
]]
function VisualAssetService.ApplyAsphaltDecal(roadPart: BasePart): boolean
	if roadPart:GetAttribute("WE_AsphaltDecal") then
		return false
	end
	local texId = VisualAssetService.ResolvePropMeshId("AsphaltDecal")
	if not texId or texId <= 0 then
		return false
	end
	local ok = pcall(function()
		for _, face in ipairs({ Enum.NormalId.Top, Enum.NormalId.Bottom }) do
			local d = Instance.new("Decal")
			d.Name = "WE_AsphaltDecal"
			d.Face = face
			d.Texture = "rbxassetid://" .. tostring(texId)
			d.Transparency = 0.15
			d.Parent = roadPart
		end
	end)
	if ok then
		roadPart:SetAttribute("WE_AsphaltDecal", texId)
	end
	return ok
end

local function collectAssetIds(primaryKey: string, fallbackKey: string?, altsKey: string?): { number }
	local ids: { number } = {}
	local seen: { [number]: boolean } = {}
	local function push(id: any)
		if typeof(id) == "number" and id > 0 and not seen[id] then
			seen[id] = true
			table.insert(ids, id)
		end
	end
	local primary = (VisualAssetConfig :: any)[primaryKey]
	if primary then
		push(primary.ModelAssetId)
	end
	if fallbackKey then
		local fb = (VisualAssetConfig :: any)[fallbackKey]
		if fb then
			push(fb.ModelAssetId)
		end
	end
	if altsKey then
		local alts = (VisualAssetConfig :: any)[altsKey]
		if typeof(alts) == "table" then
			for _, ref in ipairs(alts) do
				if typeof(ref) == "table" then
					push(ref.ModelAssetId)
				end
			end
		end
	end
	return ids
end

local function loadFirst(ids: { number }): (Model?, number?)
	for _, id in ipairs(ids) do
		local template = loadModel(id)
		if template then
			return template, id
		end
	end
	return nil, nil
end

--[[
	Dress WE_MoneyCollector with ATM catalog mesh (cosmetic only).
	Prefer Design Bot hero 75368157644109 → 175462478 → alts.
]]
function VisualAssetService.TryAttachCollectorVisual(hostPart: BasePart): boolean
	-- NEVER throw — Part kit ATM remains if Design Bot hero mesh / InsertService fails.
	local ok, result = pcall(function(): boolean
		if hostPart:GetAttribute("WE_CatalogAssetId") then
			return false
		end
		local template, assetId = loadFirst(collectAssetIds("MoneyCollector", "MoneyCollectorFallback", "MoneyCollectorAlts"))
		if not template or not assetId then
			return false -- Part kit only
		end
		local clone = template:Clone()
		if not weldCloneToPrimary(clone, hostPart, "WE_CatalogATM") then
			clone:Destroy()
			return false
		end
		clone.Parent = hostPart
		hostPart:SetAttribute("WE_CatalogAssetId", assetId)
		hostPart.Transparency = math.max(hostPart.Transparency, 0.55)
		-- Lime landmark glow (typed neon)
		local glow = hostPart:FindFirstChild("ATMGlow")
		if not (glow and glow:IsA("PointLight")) then
			local light = Instance.new("PointLight")
			light.Name = "ATMGlow"
			light.Color = Color3.fromRGB(120, 255, 90)
			light.Brightness = 1.1
			light.Range = 18
			light.Parent = hostPart
		else
			local pl = glow :: PointLight
			pl.Color = Color3.fromRGB(120, 255, 90)
			pl.Brightness = math.max(pl.Brightness, 1.0)
		end
		return true
	end)
	if not ok then
		warn("[VisualAssetService] TryAttachCollectorVisual failed (Part kit kept):", result)
		return false
	end
	return result == true
end

--[[
	One-shot collect burst FX — MoneyBagFX then VfxSparkles, then neon motes.
]]
function VisualAssetService.PlayMoneyBagFX(at: Vector3, parent: Instance?): boolean
	local ids = collectAssetIds("MoneyBagFX", "VfxSparkles", nil)
	local template, assetId = loadFirst(ids)
	if not template then
		local folder = Instance.new("Folder")
		folder.Name = "WE_MoneyBagFallback"
		folder.Parent = parent or game:GetService("Workspace")
		for i = 1, 6 do
			local mote = Instance.new("Part")
			mote.Name = "CashMote" .. i
			mote.Size = Vector3.new(0.35, 0.2, 0.55)
			mote.Color = Color3.fromRGB(120, 255, 90)
			mote.Material = Enum.Material.Neon
			mote.Anchored = true
			mote.CanCollide = false
			mote.CFrame = CFrame.new(at + Vector3.new((i - 3.5) * 0.4, 0.5, (i % 3 - 1) * 0.35))
			mote.Parent = folder
		end
		task.delay(0.85, function()
			folder:Destroy()
		end)
		return true
	end
	local clone = template:Clone()
	clone.Name = "WE_MoneyBagFX"
	clone:PivotTo(CFrame.new(at + Vector3.new(0, 1.5, 0)))
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.Massless = true
		elseif d:IsA("BaseScript") or d:IsA("ModuleScript") then
			d:Destroy()
		end
	end
	clone.Parent = parent or game:GetService("Workspace")
	if assetId then
		clone:SetAttribute("WE_CatalogAssetId", assetId)
	end
	task.delay(1.2, function()
		if clone.Parent then
			clone:Destroy()
		end
	end)
	return true
end

--[[
	Optional CashCrate overlay for supply / world crates.
]]
function VisualAssetService.TryAttachCashCrateVisual(hostPart: BasePart): boolean
	if hostPart:GetAttribute("WE_CatalogAssetId") then
		return false
	end
	local ref = (VisualAssetConfig :: any).CashCrate
	local assetId = if ref and typeof(ref.ModelAssetId) == "number" then ref.ModelAssetId else 0
	if not assetId or assetId <= 0 then
		return false
	end
	local template = loadModel(assetId)
	if not template then
		return false
	end
	local clone = template:Clone()
	if not weldCloneToPrimary(clone, hostPart, "WE_CatalogCashCrate") then
		clone:Destroy()
		return false
	end
	clone.Parent = hostPart
	hostPart:SetAttribute("WE_CatalogAssetId", assetId)
	hostPart.Transparency = math.max(hostPart.Transparency, 0.55)
	return true
end

--[[
	Dress VehicleDepot showroom hosts with podium / pedestal / rotator meshes.
]]
function VisualAssetService.TryAttachShowroomVisual(plinth: BasePart): boolean
	local attached = false
	local map = {
		Podium = "ShowroomPodium",
		PodiumRing = "ShowroomPedestal",
		ShowroomMesh = "ShowroomRotator",
	}
	for role, cfgKey in pairs(map) do
		local host = plinth:FindFirstChild(role)
		if host and host:IsA("BasePart") and not host:GetAttribute("WE_CatalogAssetId") then
			local ref = (VisualAssetConfig :: any)[cfgKey]
			local id = if ref and typeof(ref.ModelAssetId) == "number" then ref.ModelAssetId else 0
			if id > 0 then
				local template = loadModel(id)
				if template then
					local clone = template:Clone()
					if weldCloneToPrimary(clone, host, "WE_CatalogShowroom") then
						clone.Parent = host
						host:SetAttribute("WE_CatalogAssetId", id)
						host.Transparency = math.max(host.Transparency, 0.65)
						attached = true
					else
						clone:Destroy()
					end
				end
			end
		end
	end

	-- Tier 2 densify: extra pedestals (ghost locked stands) + entrance flag
	for pi = 2, 3 do
		local host = plinth:FindFirstChild("ShowroomPedestalHost" .. pi)
		if host and host:IsA("BasePart") and not host:GetAttribute("WE_CatalogAssetId") then
			pcall(function()
				local template, assetId = loadFirst(collectAssetIds("ShowroomPedestal", nil, nil))
				if template and assetId then
					local clone = template:Clone()
					if weldCloneToPrimary(clone, host, "WE_CatalogPedestal") then
						clone.Parent = host
						host:SetAttribute("WE_CatalogAssetId", assetId)
						host.Transparency = math.max(host.Transparency, 0.55)
						for _, d in ipairs(clone:GetDescendants()) do
							if d:IsA("BasePart") then
								d.Transparency = math.max(d.Transparency, 0.55)
								d.CanCollide = false
							end
						end
						attached = true
					else
						clone:Destroy()
					end
				end
			end)
		end
	end
	local flagHost = plinth:FindFirstChild("ShowroomFlagHost")
	if flagHost and flagHost:IsA("BasePart") then
		pcall(function()
			if VisualAssetService.TryAttachPropVisual(flagHost, "FlagPole") then
				attached = true
			end
		end)
	end

	return attached
end

--[[
	Dress tutorial marker with arrow mesh (first beats).
]]
function VisualAssetService.TryAttachTutorialArrow(hostPart: BasePart): boolean
	if hostPart:GetAttribute("WE_CatalogAssetId") then
		return false
	end
	local template, assetId = loadFirst(collectAssetIds("TutorialArrow", "TutorialArrowAlt", nil))
	if not template or not assetId then
		return false
	end
	local clone = template:Clone()
	if not weldCloneToPrimary(clone, hostPart, "WE_CatalogTutArrow") then
		clone:Destroy()
		return false
	end
	clone.Parent = hostPart
	hostPart:SetAttribute("WE_CatalogAssetId", assetId)
	return true
end


--[[
	Tier 2: attach HQ/Barracks/Depot interior props onto WE_DressHost_* kit parts.
	Part kit hosts remain; catalog inserts optional.
]]
function VisualAssetService.TryDressStructureInterior(plinth: BasePart, structureId: string): number
	if shouldSkipInserts() then
		return 0
	end
	local dress = (VisualAssetConfig :: any).StructureDress
	if typeof(dress) ~= "table" then
		return 0
	end
	local keys = dress[structureId]
	if typeof(keys) ~= "table" then
		return 0
	end
	local attached = 0
	local keyIdx = 1
	for _, child in ipairs(plinth:GetChildren()) do
		if child:IsA("BasePart") and string.sub(child.Name, 1, 12) == "WE_DressHost" then
			local propKey = child:GetAttribute("WE_DressProp")
			if typeof(propKey) ~= "string" or propKey == "" then
				propKey = keys[((keyIdx - 1) % #keys) + 1]
				keyIdx += 1
			end
			local ok = pcall(function()
				return VisualAssetService.TryAttachPropVisual(child, propKey :: string)
			end)
			if ok then
				attached += 1
			end
		end
	end
	return attached
end

function VisualAssetService.Init()
	ensureFolder()
	if shouldSkipInserts() then
		print("[VisualAssetService] Catalog inserts SKIPPED (StudioSkipWorldDressing / disabled). Part kits only.")
	else
		print("[VisualAssetService] Catalog inserts enabled — free Creator Store IDs via InsertService.")
	end
end


--[[
	v37: static parked aircraft/boat mesh on Helipad/Dock DressHosts.
	Uses existing VisualAssetConfig vehicle ModelAssetIds (TransportHeli / PatrolBoat).
	Part-kit ParkedHeli/ParkedBoat silhouette remains if insert skipped/fails.
]]
function VisualAssetService.TryAttachParkedPresence(plinth: BasePart, structureId: string, level: number?): boolean
	if not plinth or not plinth.Parent then
		return false
	end
	local lv = tonumber(level) or 0
	if lv < 1 then
		return false
	end
	if structureId ~= "Helipad" and structureId ~= "Dock" then
		return false
	end
	local attached = false
	for _, child in ipairs(plinth:GetChildren()) do
		if child:IsA("BasePart") then
			local vehicleId = child:GetAttribute("WE_DressVehicle")
			if typeof(vehicleId) == "string" and (vehicleId :: string) ~= "" then
				if child:FindFirstChild("WE_ParkedCatalog") then
					attached = true
				else
					local assetId = VisualAssetService.ResolveVehicleAssetId(vehicleId :: string, nil)
					if assetId then
						local template = loadModel(assetId)
						if template then
							local clone = template:Clone()
							if weldCloneToPrimary(clone, child, "WE_ParkedCatalog") then
								clone.Parent = child
								child:SetAttribute("WE_ParkedAssetId", assetId)
								-- v39: keep Part-kit parked silhouette visible under optional mesh
								for _, sib in ipairs(plinth:GetChildren()) do
									if sib:IsA("BasePart") then
										local role = sib:GetAttribute("WE_KitRole")
										if role == "ParkedHeli" or role == "ParkedBoat" then
											sib.Transparency = math.min(sib.Transparency, 0.35)
										end
									end
								end
								attached = true
							else
								clone:Destroy()
							end
						end
					end
				end
			end
		end
	end
	return attached
end


return VisualAssetService
