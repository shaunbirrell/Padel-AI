--!strict
--[[
	Loads free Creator Store Models via InsertService (fallback AssetService).
	Caches clones; strips all scripts; never blocks Part-kit spawn on failure.
	Respects DevConfig.StudioSkipWorldDressing for 8GB Studio PERF.

	W3 LOOK (roadmap §2.4; asset shortlist §6.2 C1):
	  • AssetRef.ChildName picks ONE piece of a pack (pack:FindFirstChild(ChildName, true); names hold "/", never split),
	    AssetRef.SubModel a descendant of it. A pack loads once; every configured piece of it becomes its own template
	    and the rest of the pack is destroyed. One id is inserted by one thread at a time (others wait for it).
	  • Every template is <= VisualAssetConfig.MaxPartsPerModel BaseParts and holds no Humanoid, or it is refused.
	  • Templates live in ServerStorage.WE_VisualAssetTemplates (never ReplicatedStorage).
	  • CloneKitMesh(key): one Roblox-owned mesh piece for a WorldKits Part kit (VisualAssetConfig.DesertKit).
	  • Vehicle refs with Fit = "Kit" scale the body to the kit chassis and hide the Part-kit visuals (physics unchanged).
]]

local InsertService = game:GetService("InsertService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- server module: the Rojo place ships ReplicatedStorage.Shared, so index it (no WaitForChild without a timeout)
local Shared = ReplicatedStorage.Shared
local VisualAssetConfig = require(Shared.Configs.VisualAssetConfig)
local DevConfig = require(Shared.Configs.DevConfig)

local VisualAssetService = {}

-- the fields of VisualAssetConfig.AssetRef this service reads (kept local: config tables are read through `any`)
type AssetRef = {
	ModelAssetId: number?,
	MeshId: number?,
	ChildName: string?,
	SubModel: string?,
	Color: Color3?,
	Material: Enum.Material?,
	ClearTexture: boolean?,
	StripDecals: boolean?,
	Fit: string?,
	Yaw: number?,
	HideKit: boolean?,
	KeepVisible: { string }?,
}

local cache: { [number]: Model } = {} -- template models (parented to nil / folder)
local failed: { [number]: boolean } = {}
local templateStrips: { [number]: { [string]: number } } = {} -- what loadModel stripped from each template
local dressLogged: { [number]: boolean } = {} -- vehicle dress strip summary printed once per assetId
local loadAttempts = 0
local templatesFolder: Folder? = nil
-- W3 LOOK: packs (ids whose config refs carry ChildName) are split into one template per configured piece
local pieceCache: { [string]: Instance } = {} -- pieceKey → Model or BasePart template (in the templates folder)
local pieceFailed: { [string]: string } = {} -- pieceKey → reason (logged once)
local packDone: { [number]: boolean } = {} -- the pack was loaded and split (never inserted again)
local inflight: { [number]: { thread } } = {} -- ids being inserted right now → threads waiting for them

-- Templates live in ServerStorage (CLAUDE.md): clones are made on the server, no client reads them, and in
-- ReplicatedStorage every joining client had to download every template before its loading screen ended.
local function ensureFolder(): Folder
	if templatesFolder and templatesFolder.Parent then
		return templatesFolder
	end
	local f = Instance.new("Folder")
	f.Name = "WE_VisualAssetTemplates"
	f.Parent = ServerStorage
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

--[[ v70 judge (jeep "doesn't drive", R3): a catalog dress model is welded into the vehicle's Chassis assembly, so any
	mover, joint or gameplay object it carries acts on (or rides with) the whole vehicle. A saved BodyVelocity /
	BodyPosition / AlignPosition is a hidden parking brake; a BodyGyro blocks turning. Strip by explicit class name
	(works the same in the headless sim) PLUS the abstract bases. WeldConstraint / NoCollisionConstraint are not
	Constraint subclasses, so they are listed by name. Every part is re-welded to the primary afterwards. ]]
local STRIP_CLASSES: { [string]: boolean } = {
	Humanoid = true, Tool = true, Seat = true, VehicleSeat = true, SpawnLocation = true,
	Script = true, LocalScript = true, ModuleScript = true,
	-- Constraint family
	AlignOrientation = true, AlignPosition = true, AngularVelocity = true, BallSocketConstraint = true,
	HingeConstraint = true, LineForce = true, LinearVelocity = true, PlaneConstraint = true, Plane = true,
	PrismaticConstraint = true, CylindricalConstraint = true, RigidConstraint = true, RodConstraint = true,
	RopeConstraint = true, SpringConstraint = true, Torque = true, TorsionSpringConstraint = true,
	UniversalConstraint = true, VectorForce = true, AnimationConstraint = true,
	-- legacy movers
	BodyAngularVelocity = true, BodyForce = true, BodyGyro = true, BodyPosition = true, BodyThrust = true,
	BodyVelocity = true, RocketPropulsion = true,
	-- joints (every part is re-welded to the primary below)
	Weld = true, Motor6D = true, Motor = true, Snap = true, ManualWeld = true, Glue = true, ManualGlue = true,
	Rotate = true, RotateP = true, RotateV = true, VelocityMotor = true, WeldConstraint = true, NoCollisionConstraint = true,
	-- gameplay objects a dress model must never bring along
	ProximityPrompt = true, ClickDetector = true, DragDetector = true, Sound = true, ForceField = true,
}
local STRIP_BASES = { "Constraint", "BodyMover", "JointInstance", "LuaSourceContainer" }

local function shouldStrip(d: Instance): boolean
	if STRIP_CLASSES[d.ClassName] then
		return true
	end
	for _, b in ipairs(STRIP_BASES) do
		if d:IsA(b) then
			return true
		end
	end
	return false
end

-- Destroys every strippable descendant; returns { [ClassName] = count } (children of a stripped object not counted).
local function stripDress(root: Instance): { [string]: number }
	local counts: { [string]: number } = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d.Parent ~= nil and shouldStrip(d) then
			counts[d.ClassName] = (counts[d.ClassName] or 0) + 1
			d:Destroy()
		end
	end
	return counts
end

local function mergeCounts(into: { [string]: number }, from: { [string]: number }?)
	if from then
		for k, n in pairs(from) do
			into[k] = (into[k] or 0) + n
		end
	end
end

local function stripSummary(counts: { [string]: number }): string
	local keys: { string } = {}
	for k in pairs(counts) do
		table.insert(keys, k)
	end
	if #keys == 0 then
		return "stripped nothing"
	end
	table.sort(keys)
	local parts: { string } = {}
	for _, k in ipairs(keys) do
		table.insert(parts, k .. "×" .. tostring(counts[k]))
	end
	return "stripped " .. table.concat(parts, ", ")
end

-- Template prep shared by loadModel and the test hook: dress-strip once, then anchor for the template.
local function prepareTemplate(assetId: number, model: Model)
	stripScripts(model)
	templateStrips[assetId] = stripDress(model)
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
end

-- ── W3 LOOK: part cap, packs and pieces ─────────────────────────────────────────────────────────────────────────
local function maxParts(): number
	local n = tonumber((VisualAssetConfig :: any).MaxPartsPerModel)
	return if n and n > 0 then n else 40
end

local function countParts(root: Instance): number
	local n = if root:IsA("BasePart") then 1 else 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

local function hasHumanoid(root: Instance): boolean
	return root:IsA("Humanoid") or root:FindFirstChildWhichIsA("Humanoid", true) ~= nil
end

local function refId(ref: any): number
	if typeof(ref) == "table" and typeof(ref.ModelAssetId) == "number" and ref.ModelAssetId > 0 then
		return ref.ModelAssetId
	end
	return 0
end

-- Every configured AssetRef (buckets one or two levels deep) that picks a piece of assetId.
local function pieceRefsFor(assetId: number): { AssetRef }
	local out: { AssetRef } = {}
	local function visit(t: any, depth: number)
		if typeof(t) ~= "table" or depth > 2 then
			return
		end
		if typeof(t.ModelAssetId) == "number" then
			if t.ModelAssetId == assetId and typeof(t.ChildName) == "string" then
				table.insert(out, t :: AssetRef)
			end
			return
		end
		for _, v in pairs(t) do
			visit(v, depth + 1)
		end
	end
	visit(VisualAssetConfig, 0)
	return out
end

local function isPack(assetId: number): boolean
	return #pieceRefsFor(assetId) > 0
end

local function pieceKey(ref: AssetRef): string
	return tostring(refId(ref)) .. "|" .. tostring(ref.ChildName) .. "|" .. tostring(ref.SubModel or "") .. "|" .. (if ref.StripDecals then "d" else "")
end

-- One configured piece of a prepared pack → its own template (or nil + reason). The pack itself is not changed.
local function extractPiece(pack: Instance, ref: AssetRef): (Instance?, string?)
	local name = ref.ChildName
	if typeof(name) ~= "string" then
		return nil, "no ChildName"
	end
	local piece = pack:FindFirstChild(name, true) -- the name holds "/": never split it
	if piece == nil then
		return nil, "child not found: " .. name
	end
	if typeof(ref.SubModel) == "string" then
		local sub = piece:FindFirstChild(ref.SubModel) or piece:FindFirstChild(ref.SubModel, true)
		if sub == nil then
			return nil, "sub-model not found: " .. ref.SubModel
		end
		piece = sub
	end
	if not (piece:IsA("BasePart") or piece:IsA("Model") or piece:IsA("Folder")) then
		return nil, "unsupported class " .. piece.ClassName
	end
	local copyOrNil: Instance? = piece:Clone()
	if copyOrNil == nil then
		return nil, "not archivable"
	end
	local copy: Instance = copyOrNil
	local t: Instance = copy
	if copy:IsA("BasePart") then
		-- one piece = one part: nested pieces, SurfaceAppearance, attachments all go
		for _, c in ipairs(copy:GetChildren()) do
			c:Destroy()
		end
	elseif copy:IsA("Folder") then
		local m = Instance.new("Model")
		for _, c in ipairs(copy:GetChildren()) do
			c.Parent = m
		end
		copy:Destroy()
		t = m
	end
	stripScripts(t)
	stripDress(t)
	for _, d in ipairs(t:GetDescendants()) do
		if ref.StripDecals and (d:IsA("Decal") or d:IsA("Texture")) then
			d:Destroy()
		end
	end
	for _, d in ipairs(if t:IsA("BasePart") then { t :: Instance } else t:GetDescendants()) do
		if d:IsA("BasePart") and d.Material == Enum.Material.Neon then
			d.Material = Enum.Material.SmoothPlastic -- no Neon from store pieces (phone bloom, world rule)
		end
	end
	local n = countParts(t)
	if n == 0 or n > maxParts() or hasHumanoid(t) then
		t:Destroy()
		return nil, string.format("refused: %d parts (cap %d)%s", n, maxParts(), if n > 0 and n <= maxParts() then ", Humanoid" else "")
	end
	t.Name = "WE_Asset_" .. tostring(refId(ref)) .. "_" .. name .. (if ref.SubModel then "_" .. ref.SubModel else "")
	t.Parent = ensureFolder()
	return t, nil
end

-- Split a prepared pack into one template per configured piece, then drop the pack (only the pieces stay).
local function splitPack(assetId: number, pack: Instance)
	for _, ref in ipairs(pieceRefsFor(assetId)) do
		local key = pieceKey(ref)
		local have: Instance? = pieceCache[key]
		if have == nil and pieceFailed[key] == nil then
			local t, why = extractPiece(pack, ref)
			if t then
				pieceCache[key] = t
			else
				pieceFailed[key] = why or "?"
				warn("[VisualAssetService] pack piece skipped", assetId, ref.ChildName, why)
			end
		end
	end
	packDone[assetId] = true
	cache[assetId] = nil
	pack:Destroy()
end

-- Prepared asset → cache (whole model), or split (pack), or refused (over the part cap / Humanoid left).
local function acceptTemplate(assetId: number, model: Model): Model?
	prepareTemplate(assetId, model)
	if isPack(assetId) then
		splitPack(assetId, model)
		print("[VisualAssetService] Split pack", assetId)
		return nil
	end
	local n = countParts(model)
	if n > maxParts() or hasHumanoid(model) then
		failed[assetId] = true
		model:Destroy()
		warn(string.format("[VisualAssetService] refused %d: %d parts (cap %d) — Part kit stays", assetId, n, maxParts()))
		return nil
	end
	model.Parent = ensureFolder()
	cache[assetId] = model
	return model
end

-- InsertService (AssetService fallback) → the asset's Model, or nil. Yields.
local function insertAsset(assetId: number): Model?
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
	if container ~= model then
		model.Parent = nil
		pcall(function()
			container:Destroy()
		end)
	end
	return model
end

local function releaseWaiters(assetId: number)
	local list = inflight[assetId]
	inflight[assetId] = nil
	if list then
		for _, co in ipairs(list) do
			task.spawn(co)
		end
	end
end

-- Whole-model template for assetId (nil for packs: use templateForRef). One insert per id at a time: a second caller
-- waits for the first (InsertService yields) instead of inserting the same id twice.
local function loadModel(assetId: number, forceInsert: boolean?): Model?
	if assetId == 0 or failed[assetId] or packDone[assetId] then
		return nil
	end
	if cache[assetId] then
		return cache[assetId]
	end
	-- P0: character dress MUST run even when StudioSkipWorldDressing (workers never brown bricks)
	if shouldSkipInserts() and not forceInsert then
		return nil
	end
	local waiting = inflight[assetId]
	if waiting then
		if coroutine.isyieldable() then
			table.insert(waiting, coroutine.running())
			coroutine.yield()
		end
		return cache[assetId]
	end
	if loadAttempts >= (VisualAssetConfig.MaxLoadAttempts or 36) then
		return nil
	end
	loadAttempts += 1
	inflight[assetId] = {}
	local ok, res = pcall(function(): Model?
		local model = insertAsset(assetId)
		if model == nil then
			return nil
		end
		local kept = acceptTemplate(assetId, model)
		if kept then
			print("[VisualAssetService] Cached catalog model", assetId, kept.Name)
		end
		return kept
	end)
	releaseWaiters(assetId)
	if not ok then
		failed[assetId] = true
		warn("[VisualAssetService] template prep failed", assetId, res)
		return nil
	end
	return res
end

-- Template for a config ref: the piece (ChildName / SubModel) of a pack, else the whole model. May yield (insert).
local function templateForRef(ref: AssetRef?): Instance?
	if ref == nil then
		return nil
	end
	local id = refId(ref)
	if id == 0 then
		return nil
	end
	if typeof(ref.ChildName) ~= "string" then
		return loadModel(id)
	end
	local key = pieceKey(ref)
	local have: Instance? = pieceCache[key]
	if have == nil and pieceFailed[key] == nil and not packDone[id] then
		loadModel(id) -- a pack id: inserts and splits it (every configured piece) before it returns
	end
	local t: Instance? = pieceCache[key]
	if t and t.Parent == nil then
		pieceCache[key] = nil -- someone destroyed the template
		return nil
	end
	return t
end

-- A template as a fresh Model (a single-part piece is wrapped).
local function cloneAsModel(template: Instance): Model?
	if template:IsA("Model") then
		return template:Clone()
	end
	local c: Instance? = template:Clone()
	if c == nil then
		return nil
	end
	local m = Instance.new("Model")
	m.Name = template.Name
	c.Parent = m
	return m
end

-- Returns (attached, { [ClassName] = count } stripped from this clone). keepPlace: the clone is already placed
-- (a fitted vehicle body), so it is welded where it is instead of pivoted onto the primary.
local function weldCloneToPrimary(clone: Model, primary: BasePart, cloneName: string, keepPlace: boolean?): (boolean, { [string]: number })
	stripScripts(clone)
	clone.Name = cloneName

	-- Strip seats / humanoids / scripts / movers / joints / prompts / sounds — mesh is dress-only, never drive
	local stripped = stripDress(clone)

	if not keepPlace then
		pcall(function()
			clone:PivotTo(primary.CFrame)
		end)
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
		end
	end
	return true, stripped
end

function VisualAssetService.IsInsertEnabled(): boolean
	return not shouldSkipInserts()
end

-- The vehicle's own ref, else its KitFamilyFallback ref (the whole ref: ChildName / Fit travel with the id).
local function resolveVehicleRef(vehicleId: string, kitFamily: string?): AssetRef?
	local vehicles = VisualAssetConfig.Vehicles :: any
	local ref = vehicles[vehicleId]
	if refId(ref) > 0 then
		return ref :: AssetRef
	end
	if kitFamily and VisualAssetConfig.KitFamilyFallback[kitFamily] then
		local fb = vehicles[VisualAssetConfig.KitFamilyFallback[kitFamily]]
		if refId(fb) > 0 then
			return fb :: AssetRef
		end
	end
	return nil
end

function VisualAssetService.ResolveVehicleAssetId(vehicleId: string, kitFamily: string?): number?
	local ref = resolveVehicleRef(vehicleId, kitFamily)
	return if ref then refId(ref) else nil
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

-- W3 LOOK: place a vehicle body (authored axis-aligned, front -Z) on the Part kit: one uniform scale so the body is
-- as long as the kit chassis, centred on the chassis, tyre bottoms on the physics-wheel bottoms, turned by ref.Yaw.
-- Moves each part (no Model:ScaleTo / pivots), so it does not depend on how the pack set its pivot. Returns the scale.
local function fitBodyToKit(clone: Model, hostModel: Model, primary: BasePart, ref: AssetRef): number?
	local parts: { BasePart } = {}
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	if #parts == 0 then
		return nil
	end
	local lx, ly, lz = math.huge, math.huge, math.huge
	local hx, hy, hz = -math.huge, -math.huge, -math.huge
	for _, p in ipairs(parts) do
		local cf, h = p.CFrame, p.Size * 0.5
		local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
		local ex = math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z
		local ey = math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z
		local ez = math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z
		local c = cf.Position
		lx, ly, lz = math.min(lx, c.X - ex), math.min(ly, c.Y - ey), math.min(lz, c.Z - ez)
		hx, hy, hz = math.max(hx, c.X + ex), math.max(hy, c.Y + ey), math.max(hz, c.Z + ez)
	end
	local yawDeg = tonumber(ref.Yaw) or 0
	local sideways = math.abs(math.sin(math.rad(yawDeg))) > 0.5
	local bodyLen = if sideways then hx - lx else hz - lz
	if bodyLen <= 0.05 then
		return nil
	end
	local s = math.clamp(primary.Size.Z / bodyLen, 0.05, 4)
	-- lowest physics-wheel point in the chassis frame (else the chassis bottom)
	local bottom = -primary.Size.Y * 0.5
	local found = false
	for _, d in ipairs(hostModel:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("WE_PhysicsWheel") == true then
			local rel = primary.CFrame:ToObjectSpace(d.CFrame)
			local h = d.Size * 0.5
			local ey = math.abs(rel.RightVector.Y) * h.X + math.abs(rel.UpVector.Y) * h.Y + math.abs(rel.LookVector.Y) * h.Z
			local b = rel.Position.Y - ey
			if not found or b < bottom then
				bottom = b
				found = true
			end
		end
	end
	local anchor = Vector3.new((lx + hx) * 0.5, ly, (lz + hz) * 0.5)
	local base = primary.CFrame * CFrame.new(0, bottom, 0) * CFrame.Angles(0, math.rad(yawDeg), 0)
	local shadowMin = primary.Size.Z * (tonumber((VisualAssetConfig :: any).FitShadowShare) or 0.5)
	for _, p in ipairs(parts) do
		local cf = p.CFrame
		local size = p.Size * s
		p.Size = size
		p.CFrame = base * CFrame.new((cf.Position - anchor) * s) * (cf - cf.Position)
		-- a few large body panels cast the car's shadow (the hidden kit no longer does); small parts never
		p:SetAttribute("WE_FitShadow", math.max(size.X, size.Y, size.Z) >= shadowMin)
	end
	return s
end

-- W3 LOOK: under a fitted body the Part-kit visuals go (Transparency 1). Physics, seats, hit boxes and names stay.
local function hideKitUnder(hostModel: Model, dress: Instance, ref: AssetRef)
	local keep: { [string]: boolean } = {}
	for _, n in ipairs(ref.KeepVisible or {}) do
		keep[n] = true
	end
	for _, d in ipairs(hostModel:GetDescendants()) do
		if d:IsA("BasePart") and not d:IsDescendantOf(dress) and not keep[d.Name] then
			d.Transparency = 1
		end
	end
end

--[[
	Clone catalog visual under hostModel, welded to primary, non-colliding.
	Returns true if attached. Never destroys host Part kit.
]]
function VisualAssetService.TryAttachVehicleVisual(hostModel: Model, vehicleId: string, kitFamily: string?): boolean
	local ref = resolveVehicleRef(vehicleId, kitFamily)
	if not ref then
		return false
	end
	local assetId = refId(ref)
	local template = templateForRef(ref)
	-- Design P0: NO JeepFallback 59524622. Part-kit hinge chassis remains if mesh fails.
	if not template then
		return false -- Part kit remains authoritative (hinge-drive)
	end
	local primary = hostModel.PrimaryPart
	if not primary then
		return false
	end

	local clone = cloneAsModel(template)
	if not clone then
		return false
	end
	local fitted = ref.Fit == "Kit" and fitBodyToKit(clone, hostModel, primary, ref) ~= nil
	local attached, stripped = weldCloneToPrimary(clone, primary, "WE_CatalogVisual", fitted)
	if not attached then
		clone:Destroy()
		return false
	end
	if fitted then
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CastShadow = d:GetAttribute("WE_FitShadow") == true
				d:SetAttribute("WE_FitShadow", nil)
			end
		end
	end
	if not dressLogged[assetId] then
		dressLogged[assetId] = true
		local counts: { [string]: number } = {}
		mergeCounts(counts, templateStrips[assetId])
		mergeCounts(counts, stripped)
		print(string.format("[VisualAssetService] dress %d on %s: %s", assetId, vehicleId, stripSummary(counts)))
	end

	clone.Parent = hostModel
	hostModel:SetAttribute("WE_CatalogAssetId", assetId)
	-- Soften host body so catalog mesh reads; keep Part-kit physics wheels (hidden)
	primary.Transparency = math.max(primary.Transparency, if fitted and ref.HideKit then 1 else 0.72)
	for _, d in ipairs(hostModel:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("WE_PhysicsWheel") == true then
			d.Transparency = 1 -- physics collider/motor only; mesh provides visible tires
			d.CanCollide = true
			d.Massless = false
		elseif d:IsA("BasePart") and d:GetAttribute("WE_KitCosmetic") == true then
			d.Transparency = math.max(d.Transparency, 0.85)
		end
	end
	if fitted and ref.HideKit then
		hideKitUnder(hostModel, clone, ref)
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
	-- v68: consoles are not where the building stands (WE_SiteCFrame); never hang a catalog building on one
	if hostPart:GetAttribute("WE_Console") == true then
		return false
	end
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

	-- v44 P0: Mesh welded ON TOP; kit stays fully opaque. NEVER raise Body/Roof/host Transparency.
	-- NEVER ghost Part-kit silhouettes. Catalog mesh is optional dress on top.
	-- Prior hideKitBody (Transparency≥0.92) and hostPart.Transparency=math.max(...,0.55-0.7) left ghost pads.
	local function hideKitBody()
		-- no-op on purpose
	end
	local function keepKitSolid()
		local solid = 0
		pcall(function()
			local cfg = require(ReplicatedStorage.Shared.Configs.StructureVisualConfig)
			if typeof(cfg.SolidTransparency) == "number" then
				solid = math.min(cfg.SolidTransparency, 0.05)
			end
		end)
		-- Host plinth itself may stay slightly visible; never fade it for mesh dress
		if hostPart.Transparency > 0.35 then
			hostPart.Transparency = solid
		end
		for _, ch in ipairs(hostPart:GetChildren()) do
			if ch:IsA("BasePart") then
				local role = ch:GetAttribute("WE_KitRole")
				if role == "Body" or role == "Roof" or role == "Accent" or role == "Antenna" then
					ch.Transparency = solid
				end
			end
		end
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

		keepKitSolid()
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
	keepKitSolid()
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
	-- v44 P0: never raise Transparency on structure kit hosts (Body/Roof/plinth). Vehicles/props OK.
	local kitRole = hostPart:GetAttribute("WE_KitRole")
	local isStructureHost = kitRole == "Body" or kitRole == "Roof" or hostPart:GetAttribute("StructureId") ~= nil or hostPart:GetAttribute("WE_StructureId") ~= nil
	if not isStructureHost then
		hostPart.Transparency = math.max(hostPart.Transparency, 0.7)
	end
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
	-- W3 LOOK: through the ref, so a ChildName piece of a pack works for props too
	local template: Instance? = templateForRef(lookupPropRef(propKey))
	-- Palm/Tent/OilPumpjack/Jersey/CamoNet/StreetLamp alt fallback (Design Bot wire)
	if not template then
		local altKey: string? = nil
		if propKey == "Palm" then
			altKey = "PalmAlt"
		elseif propKey == "Tent" then
			altKey = "TentAlt"
		elseif propKey == "OilPumpjack" then
			altKey = "OilPumpjackAlt"
		elseif propKey == "JerseyBarrier" then
			altKey = "JerseyBarrierAlt"
		elseif propKey == "CamoNet" then
			altKey = "CamoNetAlt"
		elseif propKey == "StreetLamp" then
			altKey = "StreetLampAlt"
		end
		if altKey then
			local altId = VisualAssetService.ResolvePropAssetId(altKey)
			if altId then
				template = templateForRef(lookupPropRef(altKey))
				if template then
					assetId = altId
				end
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

	local clone = cloneAsModel(template)
	if not clone then
		return false
	end
	if not weldCloneToPrimary(clone, hostPart, "WE_CatalogProp") then
		clone:Destroy()
		return false
	end
	clone.Parent = hostPart
	hostPart:SetAttribute("WE_CatalogAssetId", assetId)
	-- v44 P0: props on DressHost OK to soften; never fade Body/Roof structure kits
	local kitRole = hostPart:GetAttribute("WE_KitRole")
	if kitRole ~= "Body" and kitRole ~= "Roof" and hostPart:GetAttribute("StructureId") == nil then
		hostPart.Transparency = math.max(hostPart.Transparency, 0.65)
	end
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
	MoneyCollector (0 since W1: the paid hero id was dropped) → MoneyCollectorFallback 175462478 → alts → Part kit.
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
		-- W3 LOOK: insert the vehicle body pack once, deferred, so the first 4x4 spawn does not wait on InsertService
		task.defer(function()
			local seen: { [number]: boolean } = {}
			for _, ref in pairs(VisualAssetConfig.Vehicles :: any) do
				local id = refId(ref)
				if id > 0 and typeof(ref.ChildName) == "string" and not seen[id] then
					seen[id] = true
					pcall(templateForRef, ref :: AssetRef)
				end
			end
		end)
	end
end

--[[
	W3 LOOK (contracts §8.3): one Roblox-owned mesh piece for a WorldKits Part kit (VisualAssetConfig.DesertKit[key]).
	Returns an UNPARENTED, Anchored clone (CanCollide / CanQuery / CanTouch / CastShadow false; Color / Material /
	TextureID per config), or nil when the key is 0 or unknown, inserts are skipped (Studio), or the load fails.
	YIELDS on the first load of a pack (InsertService): call only from task.defer / task.spawn.
]]
function VisualAssetService.CloneKitMesh(key: string): BasePart?
	local kit = (VisualAssetConfig :: any).DesertKit
	local ref: any = if typeof(kit) == "table" then kit[key] else nil
	if refId(ref) == 0 or typeof(ref.ChildName) ~= "string" or shouldSkipInserts() then
		return nil
	end
	local ok, template = pcall(templateForRef, ref :: AssetRef)
	if not ok or typeof(template) ~= "Instance" or not template:IsA("BasePart") then
		return nil
	end
	local mpOrNil: BasePart? = (template :: BasePart):Clone()
	if mpOrNil == nil then
		return nil
	end
	local mp: BasePart = mpOrNil
	mp.Anchored = true
	mp.CanCollide = false
	mp.CanQuery = false
	mp.CanTouch = false
	mp.CastShadow = false
	mp.Massless = true
	if typeof(ref.Color) == "Color3" then
		mp.Color = ref.Color
	end
	if typeof(ref.Material) == "EnumItem" then
		mp.Material = ref.Material :: any
	end
	if mp.Material == Enum.Material.Neon then
		mp.Material = Enum.Material.SmoothPlastic
	end
	if ref.ClearTexture == true and mp:IsA("MeshPart") then
		mp.TextureID = ""
	end
	mp.Name = key .. "Mesh"
	mp:SetAttribute("WE_Decor", true)
	mp:SetAttribute("WE_KitMesh", key)
	return mp
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
					local ref = resolveVehicleRef(vehicleId :: string, nil)
					local assetId = if ref then refId(ref) else nil
					if assetId then
						local template = templateForRef(ref)
						local clone = if template then cloneAsModel(template) else nil
						if clone then
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


-- Test hook (headless sim, judge K2): install the asset for assetId as InsertService would return it, through the
-- same prep loadModel runs (a pack is split into its configured pieces; the part cap applies).
function VisualAssetService._SetTemplate(assetId: number, model: Model)
	local prefix = tostring(assetId) .. "|"
	for k, t in pairs(pieceCache) do
		if string.sub(k, 1, #prefix) == prefix then
			t:Destroy()
			pieceCache[k] = nil
		end
	end
	for k in pairs(pieceFailed) do
		if string.sub(k, 1, #prefix) == prefix then
			pieceFailed[k] = nil
		end
	end
	local old = cache[assetId]
	if old and old ~= model then
		old:Destroy()
	end
	cache[assetId] = nil
	failed[assetId] = nil
	packDone[assetId] = nil
	dressLogged[assetId] = nil
	acceptTemplate(assetId, model)
end

-- Test hook: loader counters.
function VisualAssetService._Stats(): { LoadAttempts: number, Cached: number, Pieces: number, PiecesFailed: number, PacksSplit: number }
	local c, p, f, d = 0, 0, 0, 0
	for _ in pairs(cache) do
		c += 1
	end
	for _ in pairs(pieceCache) do
		p += 1
	end
	for _ in pairs(pieceFailed) do
		f += 1
	end
	for _ in pairs(packDone) do
		d += 1
	end
	return { LoadAttempts = loadAttempts, Cached = c, Pieces = p, PiecesFailed = f, PacksSplit = d }
end

return VisualAssetService
