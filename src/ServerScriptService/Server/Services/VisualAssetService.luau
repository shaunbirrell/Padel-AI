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
	if loadAttempts >= (VisualAssetConfig.MaxLoadAttempts or 24) then
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
	if not template then
		return false
	end
	local primary = hostModel.PrimaryPart
	if not primary then
		return false
	end

	local clone = template:Clone()
	clone.Name = "WE_CatalogVisual"
	stripScripts(clone)

	-- Hide host body mesh slightly? Keep for collision — hide only decorative duplicates
	local cf = primary.CFrame
	if clone.PrimaryPart then
		clone:PivotTo(cf)
	else
		local first: BasePart? = nil
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") then
				first = d
				break
			end
		end
		if first then
			clone:PivotTo(cf)
		end
	end

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
		elseif d:IsA("VehicleSeat") or d:IsA("Seat") then
			-- Disable nested seats from catalog — we own DriverSeat
			d:Destroy()
		elseif d:IsA("Humanoid") then
			d:Destroy()
		end
	end

	clone.Parent = hostModel
	hostModel:SetAttribute("WE_CatalogAssetId", assetId)
	-- Soften host body visibility so catalog mesh reads better
	primary.Transparency = math.max(primary.Transparency, 0.55)
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
	if not template then
		return false
	end
	local primary = hostModel.PrimaryPart or hostModel:FindFirstChild("HumanoidRootPart")
	if not (primary and primary:IsA("BasePart")) then
		return false
	end

	local clone = template:Clone()
	clone.Name = "WE_CatalogCharacter"
	stripScripts(clone)

	-- Remove competing Humanoids / tools / scripts
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("Humanoid") or d:IsA("Tool") or d:IsA("BaseScript") or d:IsA("ModuleScript") then
			d:Destroy()
		end
	end

	clone:PivotTo((primary :: BasePart).CFrame)
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			d.CastShadow = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = primary :: BasePart
			weld.Part1 = d
			weld.Parent = d
		end
	end
	clone.Parent = hostModel
	hostModel:SetAttribute("WE_CatalogAssetId", assetId)
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
