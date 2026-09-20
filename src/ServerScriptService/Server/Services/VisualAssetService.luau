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

local function loadModel(assetId: number): Model?
	if assetId == 0 or failed[assetId] then
		return nil
	end
	if cache[assetId] then
		return cache[assetId]
	end
	if shouldSkipInserts() then
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
	local ref = VisualAssetConfig.Characters[kind] or VisualAssetConfig.Characters.Soldier
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
	return nil
end

local function lookupPropRef(propKey: string): any
	local buckets = {
		(VisualAssetConfig :: any).WarzoneProps,
		VisualAssetConfig.DesertProps,
		(VisualAssetConfig :: any).MapDressing,
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
	local assetId = VisualAssetService.ResolveCharacterAssetId(kind)
	if not assetId then
		return false
	end
	local template = loadModel(assetId)
	-- Optional CharacterAlt only if primary insert fails
	if not template then
		local alt = (VisualAssetConfig :: any).CharacterAlt
		local altId = if alt and typeof(alt.ModelAssetId) == "number" then alt.ModelAssetId else 0
		if typeof(altId) == "number" and altId > 0 and altId ~= assetId then
			template = loadModel(altId)
			if template then
				assetId = altId
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
	if hostPart:GetAttribute("WE_CatalogAssetId") then
		return false -- already dressed
	end
	local assetId = VisualAssetService.ResolveBuildingAssetId(structureId)
	-- DefensiveWalls L3+: prefer heavy wall mesh 9703136850 (Buildings.DefensiveWallsL3)
	local lv = tonumber(level) or 0
	if structureId == "DefensiveWalls" and lv >= 3 then
		local l3 = VisualAssetConfig.Buildings.DefensiveWallsL3
		if l3 and typeof(l3.ModelAssetId) == "number" and (l3.ModelAssetId :: number) > 0 then
			assetId = l3.ModelAssetId
		else
			-- StructureVisualConfig.MeshAssetIdL3 fallback
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
	if not assetId then
		return false
	end
	local template = loadModel(assetId)
	if not template then
		return false
	end

	local clone = template:Clone()
	if not weldCloneToPrimary(clone, hostPart, "WE_CatalogBuilding") then
		clone:Destroy()
		return false
	end
	clone.Parent = hostPart
	hostPart:SetAttribute("WE_CatalogAssetId", assetId)
	-- Soften kit body parts so catalog silhouette reads
	for _, child in ipairs(hostPart:GetChildren()) do
		if child:IsA("BasePart") and child:GetAttribute("WE_KitRole") == "Body" then
			child.Transparency = math.max(child.Transparency, 0.45)
		end
	end
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
	-- Palm → PalmAlt fallback (Design Bot wire)
	if not template and (propKey == "Palm" or propKey == "Tent") then
		local altKey = if propKey == "Palm" then "PalmAlt" else "TentAlt"
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

function VisualAssetService.Init()
	ensureFolder()
	if shouldSkipInserts() then
		print("[VisualAssetService] Catalog inserts SKIPPED (StudioSkipWorldDressing / disabled). Part kits only.")
	else
		print("[VisualAssetService] Catalog inserts enabled — free Creator Store IDs via InsertService.")
	end
end

return VisualAssetService
