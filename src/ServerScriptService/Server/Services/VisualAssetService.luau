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

	Owner asset list (2026-09-25, docs/ASSET_WIRING.md):
	  • AssetRef.OmitParts: BaseParts of a pack piece with these names are removed before the part count (the Roblox
	    Pickup Truck Body is 41 parts; without its tail-light glass it is 40).
	  • VisualAssetConfig.StripEffectsAssetIds: for these whole models Fire / Smoke / Sparkles / ParticleEmitter / lights /
	    Beam / Trail are removed at load (the Roblox oil drum keeps no smoke). Every other id keeps its effects.
	  • AssetRef.NoFamilyFallback: a vehicle ref at 0 keeps its Part kit and never takes a KitFamilyFallback body.
	  • A ref's PendingAssetId (the owner's third-party pick) is never read here (no load, no MaxLoadAttempts cost):
	    tools/wire-asset-ids.py moves it to ModelAssetId.
	  • The Airfield hangar is VisualAssetConfig.Buildings.Hangar (0 = the Part shed, no load).
	  • CloneKitMesh marks a piece with its ref's Yaw (attribute WE_KitYaw) for WorldKits; IsKitMeshWired(key) tells
	    WorldKits, from config only, whether a key can ever give a mesh (an unwired key takes no overlay slot).
	  • Hooks (2026-09-25): TryAttachBusinessVisual (war-business lines: model part i takes over kit role i, so
	    PartsPerBusinessL5 holds), TryAttachVehicleWeaponVisual (turret dress on allow-listed vehicles only, welded and
	    massless, the kit gun hidden), and the prop ref options Fit = "Ground" (upright on the host), FitLong (one uniform
	    size) and KeepHost (no host fade). OmitParts drops parts from whole-model props, businesses and weapons too, and
	    their Configuration / value objects go. A 0 id is a no-op in every hook: no load, no attribute, no change.

	Load failures (each one leaves the Part kit look and prints one Output line):
	  • transient (HTTP 5xx / throttle / timeout): retried in the BACKGROUND (task.delay), VisualAssetConfig
	    LoadRetryCount times, LoadRetryDelay s then x LoadRetryBackoff. While a retry is pending or running, callers
	    get nil at once (no caller ever waits on a retry). Retries count toward MaxLoadAttempts and never use its last
	    LoadRetryReserve attempts (kept for first loads). Silent until it loads (one print) or gives up (one warn).
	  • permanent (LoadRetryPermanentErrors text, no Model, template prep error, over the part cap / Humanoid): final.
	  • MaxLoadAttempts reached: an id asked for after that is not loaded ("load cap" line, once per id).
]]

local InsertService = game:GetService("InsertService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- server module: the Rojo place ships ReplicatedStorage.Shared, so index it (no WaitForChild without a timeout)
local Shared = ReplicatedStorage.Shared
local VisualAssetConfig = require(Shared.Configs.VisualAssetConfig)
local DevConfig = require(Shared.Configs.DevConfig)
local RigBuilder = require(script.Parent.Parent.Modules.RigBuilder) -- R-RIG
local RigConfig = require(Shared.Configs.RigConfig) -- R-RIG
local AirBodyRig = require(script.Parent.Parent.Modules.AirBodyRig) -- air-looks: aircraft body anchor / floor / mounts / rotors

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
	BodyScale: number?, -- vscale: the fitted body's scale (1 = Roblox size); nil = as long as the kit chassis
	BodySeats: { [string]: Vector3 }?, -- vscale: kit seat -> the body's own seat top (unscaled, body box frame)
	BodyRoofParts: { string }?, -- vscale: kit parts (the Armed 4x4 turret) lifted onto the fitted body's roof
	BodyAnchor: string?, -- air-looks: this BodySeats seat is put over the kit seat of that name (the body moves, the kit stays)
	BodyFloor: string?, -- air-looks: "Collide" = lowest body point on the kit's lowest collidable part (no physics wheels)
	BodyMounts: { [string]: Vector3 }?, -- air-looks: kit weapon mount -> its front face on the body (AirBodyRig.Apply)
	RotorParts: { any }?, -- air-looks: spinning body / kit parts (AirBodyRig.Apply, AircraftBodyClient)
	ChaseCamera: boolean?, -- air-looks: WE_CamMinZoom for the seated camera (AirBodyRig.Apply)
	BodyLift: number?, -- air2 fix1: the fitted body stands this many studs over the kit's floor line (drawn gear under it)
	OmitParts: { string }?, -- owner list: pack piece parts removed before the part count
	NoFamilyFallback: boolean?, -- owner list: a vehicle ref at 0 never takes the family body
	KeepHost: boolean?, -- hooks: props: the host keeps its look (no fade)
	FitLong: number?, -- hooks: props: longest side in studs (one uniform scale)
	ReplacesRoles: { string }?, -- hooks: Businesses: model part i takes over kit role i
	Mount: string?, -- hooks: VehicleWeapons: the kit part the weapon sits on
	FitScale: number?, -- hooks: VehicleWeapons: longest side = the mount's longest side x FitScale
	KitFamilies: { string }?, -- hooks: VehicleWeapons: allow-listed kit families
	Vehicles: { string }?, -- hooks: VehicleWeapons: allow-listed vehicle ids
	HideParts: { string }?, -- hooks: VehicleWeapons: kit parts hidden once the dress attaches
	Into: string?, -- bizlook: BusinessPieces: the kit role whose box the piece fills (default: the replaced role's own)
	HideRoles: { string }?, -- bizlook: BusinessPieces: kit roles turned invisible (collision kept) once the piece is on
	FromLevel: number?, -- bizlook: BusinessPieces: worn from this business level
	ToLevel: number?, -- bizlook: BusinessPieces: ... up to this level
	Rig: string?, -- R-RIG: "R6" = an animated rig template (RigBuilder), never a welded statue
	Headwear: string?, -- R-RIG: "Beret" | "KitHelmet" | "None"
}

local cache: { [number]: Model } = {} -- template models (parented to nil / folder)
local failed: { [number]: boolean } = {} -- final: never inserted again
local retryTries: { [number]: number } = {} -- background retries scheduled so far per id
local cooling: { [number]: boolean } = {} -- a background retry is pending or running: callers get nil at once
local capLogged: { [number]: boolean } = {} -- "load cap" Output line printed once per id
local requestOrder: { number } = {} -- QA (_Stats / _Requested): distinct ids that asked for an insert, in order
local requestSeen: { [number]: boolean } = {}
local capRefused = 0 -- distinct ids refused by MaxLoadAttempts
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

-- owner list: whole models listed in VisualAssetConfig.StripEffectsAssetIds lose their effects at load
local EFFECT_CLASSES = { "Fire", "Smoke", "Sparkles", "ParticleEmitter", "Light", "Beam", "Trail" }

local function stripsEffects(assetId: number): boolean
	local list = (VisualAssetConfig :: any).StripEffectsAssetIds
	if typeof(list) ~= "table" then
		return false
	end
	for _, id in ipairs(list) do
		if id == assetId then
			return true
		end
	end
	return false
end

-- Destroys every effect under root; adds what went to counts.
local function stripEffects(root: Instance, counts: { [string]: number })
	for _, d in ipairs(root:GetDescendants()) do
		if d.Parent ~= nil then
			for _, cls in ipairs(EFFECT_CLASSES) do
				if d:IsA(cls) then
					counts[d.ClassName] = (counts[d.ClassName] or 0) + 1
					d:Destroy()
					break
				end
			end
		end
	end
end

-- Template prep shared by loadModel and the test hook: dress-strip once, then anchor for the template.
local function prepareTemplate(assetId: number, model: Model)
	stripScripts(model)
	templateStrips[assetId] = stripDress(model)
	if stripsEffects(assetId) then
		stripEffects(model, templateStrips[assetId])
	end
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

-- the OmitParts names of a ref ({} when none)
local function omitNames(ref: AssetRef): { string }
	local out: { string } = {}
	local list = ref.OmitParts
	if typeof(list) == "table" then
		for _, nm in ipairs(list) do
			if typeof(nm) == "string" and nm ~= "" then
				table.insert(out, nm)
			end
		end
	end
	return out
end

local function pieceKey(ref: AssetRef): string
	local omit = omitNames(ref)
	return tostring(refId(ref)) .. "|" .. tostring(ref.ChildName) .. "|" .. tostring(ref.SubModel or "") .. "|" .. (if ref.StripDecals then "d" else "")
		.. (if #omit > 0 then "|-" .. table.concat(omit, ",") else "")
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
	-- owner list: OmitParts (e.g. the Pickup Truck's tail-light glass) go before the part count
	local omit = omitNames(ref)
	if #omit > 0 and not t:IsA("BasePart") then
		local drop: { [string]: boolean } = {}
		for _, nm in ipairs(omit) do
			drop[nm] = true
		end
		for _, d in ipairs(t:GetDescendants()) do
			if d.Parent ~= nil and d:IsA("BasePart") and drop[d.Name] then
				d:Destroy()
			end
		end
	end
	local n = countParts(t)
	if n == 0 or n > maxParts() or hasHumanoid(t) then
		t:Destroy()
		if n > 0 and n <= maxParts() then
			return nil, string.format("holds a Humanoid (%d parts)", n)
		end
		return nil, string.format("%d parts > cap %d (VisualAssetConfig.MaxPartsPerModel)", n, maxParts())
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
				-- one line per piece (pieceFailed keeps it from being tried again); the Part kit look stays
				warn(string.format("[VisualAssetService] refused %d \"%s%s\": %s — Part kit look stays", assetId,
					tostring(ref.ChildName), if ref.SubModel then "/" .. ref.SubModel else "", why or "?"))
			end
		end
	end
	packDone[assetId] = true
	cache[assetId] = nil
	pack:Destroy()
end

-- Prepared asset → cache (whole model), or split (pack), or refused (over the part cap / Humanoid left).
-- R-RIG: ids that a Characters ref with Rig = "R6" names are baked by RigBuilder (joints kept, no Humanoid)
local function isRigId(assetId: number): boolean
	for _, ref in pairs(VisualAssetConfig.Characters :: any) do
		if typeof(ref) == "table" and ref.Rig == "R6" and (ref.ModelAssetId == assetId or ref.FallbackAssetId == assetId) then
			return true
		end
	end
	return false
end

-- v119: the rig id a Characters row uses now: its ModelAssetId, or its FallbackAssetId once that failed for good
-- (LoadAsset not authorized / archived, or BakeTemplate refused it: not an R6 rig, over the part cap)
local function rigIdOf(ref: any): number
	local id = refId(ref)
	local fb = if typeof(ref) == "table" and typeof(ref.FallbackAssetId) == "number" then ref.FallbackAssetId else 0
	if id > 0 and failed[id] and fb > 0 and fb ~= id then
		return fb
	end
	return id
end

-- v119: every script, remote and bindable of an inserted rig file goes before anything reads it, whatever
-- VisualAssetConfig.StripScripts says (free models can hide require() backdoors); returns how many went
local RIG_HAZARDS = { "LuaSourceContainer", "RemoteEvent", "RemoteFunction", "UnreliableRemoteEvent", "BindableEvent", "BindableFunction" }
local function stripRigHazards(model: Instance): number
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do
		for _, cls in ipairs(RIG_HAZARDS) do
			if d:IsA(cls) then
				n += 1
				pcall(d.Destroy, d)
				break
			end
		end
	end
	return n
end

-- R-RIG: hosts that asked for a rig while its file was loading or waiting for a retry (weak keys: a host that is
-- destroyed meanwhile is simply forgotten). They get the rig when the file arrives (flushRigPending).
local rigPending: { [Model]: string } = setmetatable({} :: any, { __mode = "k" })
local flushRigPending: (number) -> ()
local rigFallback: (number) -> ()

local function acceptTemplate(assetId: number, model: Model): Model?
	if isRigId(assetId) then
		local stripped = stripRigHazards(model)
		if stripped > 0 then
			print(string.format("[VisualAssetService] rig %d: stripped %d script(s) / remote(s) before baking", assetId, stripped))
		end
		local rig, why = RigBuilder.BakeTemplate(model, assetId)
		if rig == nil or countParts(rig) > maxParts() or hasHumanoid(rig) then
			failed[assetId] = true
			if rig then
				rig:Destroy()
			else
				pcall(model.Destroy, model) -- not an R6 rig (e.g. R15): the inserted model goes, the Part kit stays
			end
			warn(string.format("[VisualAssetService] rig %d refused: %s — Part kit look stays", assetId, why or "over the cap / Humanoid"))
			return nil
		end
		rig.Parent = ensureFolder()
		cache[assetId] = rig
		task.defer(flushRigPending, assetId) -- R-RIG: hosts that asked while it loaded / cooled get it now
		return rig
	end
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
		local why = if n > maxParts()
			then string.format("%d parts > cap %d (VisualAssetConfig.MaxPartsPerModel)", n, maxParts())
			else string.format("holds a Humanoid (%d parts)", n)
		warn(string.format("[VisualAssetService] refused %d: %s — Part kit look stays", assetId, why))
		return nil
	end
	model.Parent = ensureFolder()
	cache[assetId] = model
	return model
end

-- true when a LoadAsset error message says retrying cannot help (VisualAssetConfig.LoadRetryPermanentErrors)
local function isPermanentError(msg: string): boolean
	local lower = string.lower(msg)
	local list = (VisualAssetConfig :: any).LoadRetryPermanentErrors
	if typeof(list) ~= "table" then
		return false
	end
	for _, pat in ipairs(list) do
		if typeof(pat) == "string" and pat ~= "" and string.find(lower, pat, 1, true) then
			return true
		end
	end
	return false
end

-- InsertService (AssetService fallback) → the asset's Model, or (nil, "transient" | "permanent", error text). Yields.
-- Marks and logs nothing for a LoadAsset error: loadAttempt decides (silent background retry, or one final line).
local function insertAsset(assetId: number): (Model?, string?, string?)
	local ok, result = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	local errs: { string } = {}
	if not ok or typeof(result) ~= "Instance" then
		table.insert(errs, tostring(result))
		-- AssetService fallback (newer API)
		local AssetService = game:GetService("AssetService")
		if AssetService and (AssetService :: any).LoadAssetAsync then
			ok, result = pcall(function()
				return (AssetService :: any):LoadAssetAsync(assetId)
			end)
			if not ok or typeof(result) ~= "Instance" then
				table.insert(errs, tostring(result))
			end
		end
	end
	if not ok or typeof(result) ~= "Instance" then
		-- transient only when no message says the asset can never load here
		local kind = "transient"
		for _, e in ipairs(errs) do
			if isPermanentError(e) then
				kind = "permanent"
				break
			end
		end
		return nil, kind, table.concat(errs, " | ")
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
		container:Destroy()
		warn("[VisualAssetService] No Model in asset", assetId, "— Part kit look stays")
		return nil, "logged", nil
	end
	if container ~= model then
		model.Parent = nil
		pcall(function()
			container:Destroy()
		end)
	end
	return model, nil, nil
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

local function maxLoadAttempts(): number
	return tonumber(VisualAssetConfig.MaxLoadAttempts) or 36
end

-- retries may use the load budget only up to MaxLoadAttempts - LoadRetryReserve (the rest is kept for first loads)
local function retryBudgetLeft(): boolean
	local reserve = math.max(0, math.floor(tonumber(VisualAssetConfig.LoadRetryReserve) or 0))
	return loadAttempts < maxLoadAttempts() - reserve
end

-- the load cap refuses assetId: one Output line per id (the Part kit look stays)
local function refuseOverCap(assetId: number)
	if capLogged[assetId] then
		return
	end
	capLogged[assetId] = true
	capRefused += 1
	warn(string.format("[VisualAssetService] load cap reached (%d attempts, VisualAssetConfig.MaxLoadAttempts): %d not loaded — Part kit look stays",
		maxLoadAttempts(), assetId))
end

local scheduleRetry: (number, string) -> ()

-- One insert of assetId (counts toward MaxLoadAttempts; the caller checked the cap). Other first-try callers for the id
-- wait on inflight[assetId]; during a retry cooling[assetId] stays set, so nobody waits on it. A transient failure
-- schedules a background retry; any other failure is final.
local function loadAttempt(assetId: number): Model?
	loadAttempts += 1
	inflight[assetId] = {}
	local kind: string? = nil
	local errText = "?"
	local ok, res = pcall(function(): Model?
		local model, why, text = insertAsset(assetId)
		if model == nil then
			kind = why
			errText = text or "?"
			return nil
		end
		local kept = acceptTemplate(assetId, model)
		if kept then
			print("[VisualAssetService] Cached catalog model", assetId, kept.Name)
		end
		return kept
	end)
	-- record the outcome (failed / cooling) BEFORE waking waiters: a woken waiter whose caller asks for the same id
	-- again (a dress loop, another piece of the same pack) must see it, never start a second insert
	if not ok then
		failed[assetId] = true
		warn("[VisualAssetService] template prep failed", assetId, res)
	elseif res == nil and kind == "transient" then
		scheduleRetry(assetId, errText) -- silent until it finally loads (one print) or gives up (one warn)
	elseif res == nil and kind == "permanent" then
		failed[assetId] = true
		warn(string.format("[VisualAssetService] LoadAsset failed %d (%s) — Part kit look stays", assetId, errText))
	elseif res == nil and kind ~= nil then
		failed[assetId] = true -- no Model in the asset (already logged): never inserted again
	end
	releaseWaiters(assetId)
	if not ok then
		return nil
	end
	return res
end

-- a transient failure that will not be retried (again): final, one Output line
local function giveUp(assetId: number, tries: number, errText: string, why: string?)
	cooling[assetId] = nil
	failed[assetId] = true
	task.defer(rigFallback, assetId) -- v119: hosts waiting on a rig id that never came get its fallback
	warn(string.format("[VisualAssetService] LoadAsset failed %d after %d %s (%s%s) — Part kit look stays", assetId,
		tries, if tries == 1 then "try" else "tries", errText, if why then "; " .. why else ""))
end

-- Background retry after a transient failure: LoadRetryDelay s, then x LoadRetryBackoff each time; after
-- LoadRetryCount retries the id is final. Never yields the caller (task.delay); the budget is re-checked when it runs.
function scheduleRetry(assetId: number, errText: string)
	local tries = retryTries[assetId] or 0
	local maxTries = math.max(0, math.floor(tonumber(VisualAssetConfig.LoadRetryCount) or 0))
	if tries >= maxTries then
		giveUp(assetId, tries + 1, errText, nil)
		return
	end
	if not retryBudgetLeft() then
		giveUp(assetId, tries + 1, errText, "no retry: the last load attempts are kept for first loads")
		return
	end
	retryTries[assetId] = tries + 1
	cooling[assetId] = true
	local base = math.max(0, tonumber(VisualAssetConfig.LoadRetryDelay) or 20)
	local mult = math.max(1, tonumber(VisualAssetConfig.LoadRetryBackoff) or 2)
	task.delay(base * mult ^ tries, function()
		if cache[assetId] or packDone[assetId] or failed[assetId] then
			cooling[assetId] = nil
			return
		end
		if not retryBudgetLeft() then
			giveUp(assetId, tries + 1, errText, "no retry: the last load attempts are kept for first loads")
			return
		end
		loadAttempt(assetId) -- cooling stays set meanwhile: callers get nil, nobody waits on a retry
		if cache[assetId] or packDone[assetId] then
			cooling[assetId] = nil
			print(string.format("[VisualAssetService] %d loaded on retry %d", assetId, tries + 1))
		elseif failed[assetId] then
			cooling[assetId] = nil
			task.defer(rigFallback, assetId) -- v119: a retry that failed for good (refused rig / permanent error)
		end
		-- else: another retry is scheduled (cooling stays set)
	end)
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
	if cooling[assetId] then
		return nil -- a background retry is pending / running: the Part kit look now, never a wait
	end
	local waiting = inflight[assetId]
	if waiting then
		if coroutine.isyieldable() then
			table.insert(waiting, coroutine.running())
			coroutine.yield()
		end
		return cache[assetId]
	end
	if not requestSeen[assetId] then
		requestSeen[assetId] = true
		table.insert(requestOrder, assetId)
	end
	if loadAttempts >= maxLoadAttempts() then
		refuseOverCap(assetId)
		return nil
	end
	return loadAttempt(assetId)
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
	-- claude-bud JOB 5a: a Robux-only clone (VehicleConfig Premium* rows) wears its base vehicle's body (LookId)
	do
		local okV, VC = pcall(function(): any
			return require(ReplicatedStorage.Shared.Configs.VehicleConfig)
		end)
		local vdef = if okV and VC and VC.Vehicles then VC.Vehicles[vehicleId] else nil
		if vdef and typeof(vdef.LookId) == "string" then
			vehicleId = vdef.LookId
		end
	end
	local vehicles = VisualAssetConfig.Vehicles :: any
	local ref = vehicles[vehicleId]
	if refId(ref) > 0 then
		return ref :: AssetRef
	end
	if typeof(ref) == "table" and ref.NoFamilyFallback == true then
		return nil -- owner list: this vehicle keeps its own Part kit (never a family body)
	end
	if kitFamily and VisualAssetConfig.KitFamilyFallback[kitFamily] then
		local fb = vehicles[VisualAssetConfig.KitFamilyFallback[kitFamily]]
		if refId(fb) > 0 then
			return fb :: AssetRef
		end
	end
	return nil
end

-- v87 (Code Bot): a Rollout = "Body" ref (the helicopter / bomber / transport / ship store bodies) is worn only as
-- VisualAssetConfig.BodyRollout allows: "all" = everyone, "owner" = only a vehicle whose owner is the playtest owner
-- (AdminConfig.IsPlaytestOwner, shaunie6), anything else = nobody. Every other ref is always allowed (cars, jets).
function VisualAssetService.BodyAllowed(ref: any, ownerUserId: number?): boolean
	if typeof(ref) ~= "table" or ref.Rollout ~= "Body" then
		return true
	end
	local mode = (VisualAssetConfig :: any).BodyRollout
	if mode == "all" then
		return true
	elseif mode == "owner" then
		local ok, admin = pcall(function()
			return require(Shared.Configs.AdminConfig)
		end)
		return ok and typeof(admin) == "table" and admin.IsPlaytestOwner(ownerUserId) == true
	end
	return false
end

--[[ claude-bud JOB 58: a vehicle's approved store body as a STATIC display (the hangar / dock showpieces). Only a ref
	BodyAllowed for ownerUserId (the same rule as a driven vehicle: live refs for everyone, Rollout = "Body" refs only on
	the playtest owner's things). The house template (scripts / seats / sounds / movers stripped), every part Anchored,
	CanCollide / CanQuery / CanTouch off, scaled so its longest flat side is fitLength (clamped 0.05 .. 4). Returns the
	unparented model and the ref's Yaw (the body's turn against a kit front), or nil (no body: the caller keeps its Part
	build). May yield (the template load). ]]
function VisualAssetService.CloneDisplayBody(vehicleId: string, ownerUserId: number?, fitLength: number?): (Model?, number)
	if shouldSkipInserts() then
		return nil, 0
	end
	local ref = resolveVehicleRef(vehicleId, nil)
	if ref == nil or not VisualAssetService.BodyAllowed(ref, ownerUserId) then
		return nil, 0
	end
	local template = templateForRef(ref)
	if template == nil then
		return nil, 0
	end
	local clone = cloneAsModel(template)
	if clone == nil then
		return nil, 0
	end
	stripScripts(clone)
	stripDress(clone)
	local nParts = 0
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			nParts += 1
		end
	end
	if nParts == 0 or nParts > maxParts() then
		clone:Destroy()
		return nil, 0
	end
	if typeof(fitLength) == "number" and fitLength > 0 then
		local _, size = clone:GetBoundingBox()
		local long = math.max(size.X, size.Z)
		if long > 0 then
			pcall(function()
				clone:ScaleTo(math.clamp(clone:GetScale() * fitLength / long, 0.05, 4))
			end)
		end
	end
	clone.Name = "WE_Display_" .. vehicleId
	return clone, tonumber((ref :: any).Yaw) or 0
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

-- wc3 (owner pick 4954987035, the recon plane): the box Roblox DRAWS for a part. A Part with Shape = Cylinder is drawn
-- Size.X long and min(Size.Y, Size.Z) across (the plane's fuselage is 15.83 x 11.26 x 3.88, drawn 3.88 round), a Ball
-- min(Size) across; MeshParts, unions, wedges and blocks are their Size. The fit measures this box, so a cylinder-bodied
-- model stands on its wheels instead of 3.7 studs over them.
local function drawnSize(p: BasePart): Vector3
	local size = p.Size
	if p:IsA("Part") then
		if p.Shape == Enum.PartType.Cylinder then
			local d = math.min(size.Y, size.Z)
			return Vector3.new(size.X, d, d)
		elseif p.Shape == Enum.PartType.Ball then
			local d = math.min(size.X, size.Y, size.Z)
			return Vector3.new(d, d, d)
		end
	end
	return size
end

-- W3 LOOK: place a vehicle body (authored axis-aligned, front -Z) on the Part kit: one uniform scale so the body is
-- as long as the kit chassis, centred on the chassis, tyre bottoms on the physics-wheel bottoms, turned by ref.Yaw.
-- Moves each part (no Model:ScaleTo / pivots), so it does not depend on how the pack set its pivot. Returns the scale.
-- vscale: ref.BodyScale sets the scale instead (Roblox size: the avatar fits inside); the physics kit is unchanged.
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
		local cf, h = p.CFrame, drawnSize(p) * 0.5
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
	local fitScale = if typeof(ref.BodyScale) == "number" and ref.BodyScale > 0 then ref.BodyScale else nil
	local s = AirBodyRig.ClampScale(ref, fitScale or primary.Size.Z / bodyLen) -- v87: a ref's BodyMinScale lowers the 0.05 floor
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
	-- air-looks: an aircraft stands on its skids / gear (BodyFloor), its cockpit over the kit seat (BodyAnchor)
	if ref.BodyFloor == "Collide" and not found then
		bottom = AirBodyRig.KitFloor(hostModel, primary, bottom)
	end
	local shift = AirBodyRig.AnchorShift(hostModel, primary, ref, s, yawDeg)
	if shift ~= Vector3.zero then
		clone:SetAttribute("WE_BodyShift", shift)
	end
	-- air2 fix1: BodyLift stands a long aircraft body higher on its drawn gear (AirBodyRig), so its tail clears the runway
	local lift = if fitScale and typeof(ref.BodyLift) == "number" then math.clamp(ref.BodyLift, 0, 4) else 0
	-- v87: a ship body sinks BodyWaterline studs, so its hull sits in the water the kit rides on (not on top of it)
	lift -= if fitScale and typeof(ref.BodyWaterline) == "number" then math.clamp(ref.BodyWaterline, 0, 30) else 0
	local anchor = Vector3.new((lx + hx) * 0.5, ly, (lz + hz) * 0.5)
	local base = primary.CFrame * CFrame.new(shift.X, bottom + lift, shift.Z) * CFrame.Angles(0, math.rad(yawDeg), 0)
	-- vscale: FitShadowShare of the FITTED body's length (at BodyScale the chassis is far shorter than the body)
	local shadowMin = (if fitScale then bodyLen * s else primary.Size.Z) * (tonumber((VisualAssetConfig :: any).FitShadowShare) or 0.5)
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

-- vscale: move a kit part welded to the primary (unweld, set CFrame, weld again: a CFrame set on a welded part would
-- move the whole car).
local function reweldAt(primary: BasePart, part: BasePart, cf: CFrame)
	for _, holder in ipairs({ primary :: Instance, part :: Instance }) do
		for _, w in ipairs(holder:GetChildren()) do
			if w:IsA("WeldConstraint") and ((w.Part0 == primary and w.Part1 == part) or (w.Part0 == part and w.Part1 == primary)) then
				w:Destroy()
			end
		end
	end
	part.CFrame = cf
	local w = Instance.new("WeldConstraint")
	w.Part0 = primary
	w.Part1 = part
	w.Parent = primary
end

-- vscale: half height of a part in the chassis frame
local function halfHeightIn(rel: CFrame, size: Vector3): number
	local h = size * 0.5
	return math.abs(rel.RightVector.Y) * h.X + math.abs(rel.UpVector.Y) * h.Y + math.abs(rel.LookVector.Y) * h.Z
end

-- vscale (option B): after a successful fit at ref.BodyScale the kit seats sit on the body's own seats (CanCollide off,
-- so the drive footprint stays the kit's), the ref's roof parts stand on the roof and the label is 1 stud over the
-- higher of the two. A kit whose body did not load keeps its own seats and label. The body frame is measured on the
-- fitted clone: its lowest point is on the physics-wheel bottom and its box is centred on the chassis (fitBodyToKit).
-- vscale R2: the fitted body's half length / half width / top in the chassis frame go on the model
-- (WE_VisualHalfLength / WE_VisualHalfWidth / WE_VisualTop) for VehicleService's spawn spot, exit spot, prompt ranges
-- and the friendly gate; WE_HalfLength / WE_HalfWidth stay the kit's (driving, splash, collisions).
local function placeKitOnBody(hostModel: Model, primary: BasePart, clone: Model, ref: AssetRef)
	local s = AirBodyRig.ClampScale(ref, ref.BodyScale or 1)
	local bottom, roofY = math.huge, -math.huge
	local halfX, halfZ = 0, 0
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			local rel = primary.CFrame:ToObjectSpace(d.CFrame)
			local ey = halfHeightIn(rel, drawnSize(d))
			bottom, roofY = math.min(bottom, rel.Position.Y - ey), math.max(roofY, rel.Position.Y + ey)
			local h = drawnSize(d) * 0.5
			local ex = math.abs(rel.RightVector.X) * h.X + math.abs(rel.UpVector.X) * h.Y + math.abs(rel.LookVector.X) * h.Z
			local ez = math.abs(rel.RightVector.Z) * h.X + math.abs(rel.UpVector.Z) * h.Y + math.abs(rel.LookVector.Z) * h.Z
			halfX, halfZ = math.max(halfX, math.abs(rel.Position.X) + ex), math.max(halfZ, math.abs(rel.Position.Z) + ez)
		end
	end
	if bottom > roofY then
		return
	end
	local shift = clone:GetAttribute("WE_BodyShift") -- air-looks: BodyAnchor moved the body (AirBodyRig.AnchorShift)
	local sh = if typeof(shift) == "Vector3" then shift else Vector3.zero
	local base = primary.CFrame * CFrame.new(sh.X, bottom, sh.Z) * CFrame.Angles(0, math.rad(tonumber(ref.Yaw) or 0), 0)
	-- vscale R2.1: the kit's collidable half width / length (every CanCollide part but the seats, as WE_HalfWidth /
	-- WE_HalfLength will be): a moved seat keeps its centre BodySeatKitInset inside it. A seat past the kit's nose or
	-- tail (the Cargo Van's front row, the Dispatch Car's back seat) sits inside a wall the kit touches, and so does
	-- its rider.
	local kx, kz = 0, 0
	for _, d in ipairs(hostModel:GetDescendants()) do
		if d:IsA("BasePart") and d.CanCollide and not d:IsA("Seat") and not d:IsA("VehicleSeat") then
			local rel = primary.CFrame:ToObjectSpace(d.CFrame)
			local h = d.Size * 0.5
			kx = math.max(kx, math.abs(rel.Position.X) + math.abs(rel.RightVector.X) * h.X + math.abs(rel.UpVector.X) * h.Y + math.abs(rel.LookVector.X) * h.Z)
			kz = math.max(kz, math.abs(rel.Position.Z) + math.abs(rel.RightVector.Z) * h.X + math.abs(rel.UpVector.Z) * h.Y + math.abs(rel.LookVector.Z) * h.Z)
		end
	end
	local inset = tonumber((VisualAssetConfig :: any).BodySeatKitInset) or 0
	local mx, mz = math.max(kx - inset, 0), math.max(kz - inset, 0)
	for name, top in pairs(ref.BodySeats or {}) do
		local seat = hostModel:FindFirstChild(name)
		if seat and seat:IsA("BasePart") and typeof(top) == "Vector3" then
			local rot = seat.CFrame - seat.CFrame.Position
			local at = primary.CFrame:PointToObjectSpace((base * CFrame.new(top * s)).Position)
			at = Vector3.new(math.clamp(at.X, -mx, mx), at.Y, math.clamp(at.Z, -mz, mz))
			reweldAt(primary, seat, CFrame.new(primary.CFrame:PointToWorldSpace(at)) * rot * CFrame.new(0, -seat.Size.Y * 0.5, 0))
			seat.CanCollide = false
		end
	end
	local lift: number? = nil
	local roofParts: { BasePart } = {}
	for _, name in ipairs(ref.BodyRoofParts or {}) do
		local p = hostModel:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			local rel = primary.CFrame:ToObjectSpace(p.CFrame)
			lift = math.max(lift or -math.huge, roofY - (rel.Position.Y - halfHeightIn(rel, p.Size)))
			table.insert(roofParts, p)
		end
	end
	if lift and lift > 0 then
		for _, p in ipairs(roofParts) do
			reweldAt(primary, p, p.CFrame + primary.CFrame.UpVector * lift)
		end
	end
	-- vscale R2: the label clears the lifted roof parts too (the Armed 4x4 gun mount stands 0.8 over the roof)
	local topY = roofY
	for _, p in ipairs(roofParts) do
		local rel = primary.CFrame:ToObjectSpace(p.CFrame)
		topY = math.max(topY, rel.Position.Y + halfHeightIn(rel, p.Size))
	end
	-- vscale R2.3: the margin grows with the body's height over the ground (bottom = the physics-wheel bottom)
	local lm = (VisualAssetConfig :: any).BodyLabelMargin or {}
	local margin = (tonumber(lm.Base) or 1) + (tonumber(lm.PerStud) or 0) * math.max(0, topY - bottom - (tonumber(lm.EyeHeight) or 0))
	hostModel:SetAttribute("WE_LabelY", topY + margin)
	hostModel:SetAttribute("WE_VisualHalfLength", halfZ)
	hostModel:SetAttribute("WE_VisualHalfWidth", halfX)
	hostModel:SetAttribute("WE_VisualTop", topY)
	-- air-looks: weapon mounts on the body, rotor joints, the seated chase camera (a no-op for a ref without them)
	AirBodyRig.Apply(hostModel, primary, clone, ref)
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
function VisualAssetService.TryAttachVehicleVisual(hostModel: Model, vehicleId: string, kitFamily: string?, ownerUserId: number?): boolean
	local ref = resolveVehicleRef(vehicleId, kitFamily)
	if not ref then
		return false
	end
	-- v87: an owner-only store body (Rollout = "Body") on anyone else's vehicle: the Part kit stays (no load at all)
	if not VisualAssetService.BodyAllowed(ref, ownerUserId) then
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
	AirBodyRig.StripSigns(clone, ref) -- air-looks: a store body's name signs (and decals with StripDecals) go, whole model or pack piece
	-- v87: a whole-model body drops its OmitParts before the fit (a pack piece lost them when it was split), and a plain
	-- store mesh takes BodyColor / BodyMaterial (BodyClearTexture: a dead texture path goes so the colour shows)
	if typeof(ref.ChildName) ~= "string" and typeof(ref.OmitParts) == "table" then
		local omit: { [string]: boolean } = {}
		for _, n in ipairs(ref.OmitParts :: { string }) do
			omit[n] = true
		end
		for _, d in ipairs(clone:GetDescendants()) do
			if d.Parent ~= nil and omit[d.Name] and (d:IsA("BasePart") or d:IsA("Model")) then
				d:Destroy()
			end
		end
	end
	if typeof(ref.BodyColor) == "Color3" then
		local col: Color3 = ref.BodyColor :: any
		local mat: any = ref.BodyMaterial
		-- v90: BodyColorParts = only the parts with these names take the colour (a jet's panels; trim and glass keep theirs)
		local only: { [string]: boolean }? = nil
		if typeof(ref.BodyColorParts) == "table" then
			local set: { [string]: boolean } = {}
			for _, n in ipairs(ref.BodyColorParts :: { string }) do
				set[n] = true
			end
			only = set
		end
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") and (only == nil or only[d.Name] == true) then
				d.Color = col
				if typeof(mat) == "EnumItem" then
					d.Material = mat
				end
				if ref.BodyClearTexture == true and d:IsA("MeshPart") then
					d.TextureID = ""
				end
			end
		end
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
		if typeof(ref.BodyScale) == "number" and ref.BodyScale > 0 then
			placeKitOnBody(hostModel, primary, clone, ref)
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
-- R-RIG: attach the rig to every host that asked while `assetId` was loading or cooling and is still alive in the
-- world with no rig (a late statue, squad unit, NPC or gate guard gets the same body as the rest). Bounded by the
-- hosts waiting (at most the figures alive); runs once per template arrival.
function flushRigPending(assetId: number)
	local template: Model? = cache[assetId]
	if template == nil or RigConfig.Enabled ~= true then
		return
	end
	local hosts: { Model } = {}
	for host in pairs(rigPending) do
		table.insert(hosts, host)
	end
	local n = 0
	local world = game:GetService("Workspace")
	for _, host in ipairs(hosts) do
		local kind = rigPending[host]
		rigPending[host] = nil
		local ref = (VisualAssetConfig.Characters :: any)[kind] or VisualAssetConfig.Characters.Soldier
		-- still in the world and still a Part kit (a dying host is removed by its builder moments later anyway)
		if typeof(ref) == "table" and ref.Rig == "R6" and rigIdOf(ref) == assetId and host:IsDescendantOf(world)
			and host:FindFirstChild(RigBuilder.RigName) == nil then
			if RigBuilder.Attach(host, template, { Headwear = ref.Headwear, StaticHoldDeg = RigConfig.Anim.StaticHoldDeg }) then
				host:SetAttribute("WE_CatalogAssetId", assetId)
				n += 1
			end
		end
	end
	if n > 0 then
		print(string.format("[VisualAssetService] rig %d attached late to %d figure(s)", assetId, n))
	end
end

-- v119: a rig id failed for good: the hosts waiting on it (rigPending) get the row's FallbackAssetId (one insert,
-- in its own thread; flushRigPending attaches it). Nothing to do for ids without a fallback row.
function rigFallback(assetId: number)
	if not failed[assetId] then
		return
	end
	local seen: { [number]: boolean } = {}
	for _, ref in pairs(VisualAssetConfig.Characters :: any) do
		if typeof(ref) == "table" and ref.Rig == "R6" and refId(ref) == assetId then
			local fb = rigIdOf(ref)
			if fb ~= assetId and fb > 0 and not seen[fb] then
				seen[fb] = true
				warn(string.format("[VisualAssetService] rig %d unavailable — soldiers use the fallback rig %d", assetId, fb))
				task.spawn(function()
					if loadModel(fb, true) then
						flushRigPending(fb)
					end
				end)
			end
		end
	end
end

function VisualAssetService.TryAttachCharacterVisual(hostModel: Model, kind: string): boolean
	-- P0: always attempt character catalog inserts (bypass StudioSkipWorldDressing)
	local forceChar = true
	-- R-RIG: a friendly squad soldier has its own look key; a Rig ref gets the animated rig or keeps its Part kit
	local rigKind = if hostModel:GetAttribute("FriendlySquad") == true and (VisualAssetConfig.Characters :: any).Squad then "Squad" else kind
	local rigRef = (VisualAssetConfig.Characters :: any)[rigKind] or VisualAssetConfig.Characters.Soldier
	if typeof(rigRef) == "table" and rigRef.Rig == "R6" then
		if RigConfig.Enabled ~= true then
			return false -- R-RIG off: the Part kit stays (no load, never a welded statue)
		end
		local rid = rigIdOf(rigRef) -- v119: the fallback rig once the preferred one failed for good
		local rigTemplate = if rid > 0 then loadModel(rid, forceChar) else nil
		if rigTemplate == nil and rigIdOf(rigRef) ~= rid then
			rid = rigIdOf(rigRef) -- the preferred rig just failed (not authorized / refused): its fallback now
			rigTemplate = loadModel(rid, forceChar)
		end
		if rigTemplate == nil then
			if rid > 0 and not failed[rid] then
				rigPending[hostModel] = rigKind -- loading / retry cooling: the rig comes when the file does
			end
			return false -- the Part kit stays (no welded-statue fallback for rig kinds)
		end
		local ok = RigBuilder.Attach(hostModel, rigTemplate, { Headwear = rigRef.Headwear, StaticHoldDeg = RigConfig.Anim.StaticHoldDeg })
		if ok then
			hostModel:SetAttribute("WE_CatalogAssetId", rid)
		end
		return ok
	end
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

	-- Airfield COMPOSITE: runway 70×1×10 + asphalt decal + VisualAssetConfig.Buildings.Hangar (0 = the Part shed)
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

		-- owner rule 5 (2026-09-25): the hangar id comes from config; 0 = the Part shed, no LoadAsset call
		local hangarId = refId((VisualAssetConfig.Buildings :: any).Hangar)
		local hangarTemplate = if hangarId > 0 then loadModel(hangarId) else nil
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
			if hangarId > 0 then
				warn("[VisualAssetService] Hangar insert failed — Part shed fallback", hangarId)
			end
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
			hangarId = if hangarId > 0 then -hangarId else 0 -- a failed id is stored negative; 0 = no hangar model
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
-- ── hooks (2026-09-25): clone helpers (no per-frame use; each runs once per dressed host) ───────────────────────────
local function listParts(root: Instance): { BasePart }
	local out: { BasePart } = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

-- a dress clone keeps no data objects (the stripped scripts' Configuration / IntValue / BoolValue ...): they replicate
-- for nothing
local function dropDataChildren(clone: Instance)
	for _, d in ipairs(clone:GetDescendants()) do
		if d.Parent ~= nil and (d:IsA("Configuration") or d:IsA("ValueBase")) then
			d:Destroy()
		end
	end
end

-- ref.OmitParts on a whole-model clone (packs drop them in extractPiece before the part count)
local function dropOmitParts(clone: Instance, ref: AssetRef?)
	if ref == nil then
		return
	end
	local omit = omitNames(ref)
	if #omit == 0 then
		return
	end
	local drop: { [string]: boolean } = {}
	for _, nm in ipairs(omit) do
		drop[nm] = true
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if d.Parent ~= nil and d:IsA("BasePart") and drop[d.Name] then
			d:Destroy()
		end
	end
end

local function hasFileMesh(p: BasePart): boolean
	for _, c in ipairs(p:GetChildren()) do
		if c:IsA("SpecialMesh") and c.MeshType == Enum.MeshType.FileMesh then
			return true
		end
	end
	return false
end

-- half extents of a part box (cf, size) along the axes of the frame the cf is expressed in
local function halfExtents(cf: CFrame, size: Vector3): Vector3
	local h = size * 0.5
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	return Vector3.new(
		math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z,
		math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z,
		math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z
	)
end

-- axis-aligned box (lo, hi) of parts in the space of `frame`
local function aabbIn(frame: CFrame, parts: { BasePart }): (Vector3, Vector3)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, p in ipairs(parts) do
		local rel = frame:ToObjectSpace(p.CFrame)
		local e = halfExtents(rel, p.Size)
		lo = lo:Min(rel.Position - e)
		hi = hi:Max(rel.Position + e)
	end
	return lo, hi
end

-- Fit = "Ground": the clone stands upright (its template axes) at the host's centre, its lowest point on the host's
-- lowest point, scale 1 (a pure move: the template parts keep their authored orientation)
local function placeOnGround(clone: Model, host: BasePart)
	local parts = listParts(clone)
	if #parts == 0 then
		return
	end
	local lo, hi = aabbIn(CFrame.identity, parts)
	local e = halfExtents(host.CFrame, host.Size)
	local p = host.Position
	local shift = Vector3.new(p.X - (lo.X + hi.X) * 0.5, (p.Y - e.Y) - lo.Y, p.Z - (lo.Z + hi.Z) * 0.5)
	for _, part in ipairs(parts) do
		part.CFrame = part.CFrame + shift
	end
end

-- one uniform scale k for a part and its mesh (FileMesh SpecialMesh scale, every mesh offset)
local function scalePartMeshes(p: BasePart, k: number)
	for _, c in ipairs(p:GetChildren()) do
		if c:IsA("SpecialMesh") then
			if c.MeshType == Enum.MeshType.FileMesh then
				c.Scale = c.Scale * k
			end
			c.Offset = c.Offset * k
		elseif c:IsA("BlockMesh") or c:IsA("CylinderMesh") then
			local m = c :: any
			m.Offset = m.Offset * k
		end
	end
end

-- ref.FitLong: one uniform scale (parts, meshes) about the model's bottom centre so its longest side is `long` studs
local function scaleToLong(parts: { BasePart }, long: number)
	if #parts == 0 or long <= 0 then
		return
	end
	local lo, hi = aabbIn(CFrame.identity, parts)
	local size = hi - lo
	local cur = math.max(size.X, size.Y, size.Z)
	if cur < 0.05 then
		return
	end
	local k = math.clamp(long / cur, 0.05, 40)
	local about = Vector3.new((lo.X + hi.X) * 0.5, lo.Y, (lo.Z + hi.Z) * 0.5)
	for _, p in ipairs(parts) do
		local cf = p.CFrame
		p.Size = p.Size * k
		scalePartMeshes(p, k)
		p.CFrame = CFrame.new(about + (cf.Position - about) * k) * cf.Rotation
	end
end

--[[ Fit parts (template axes) into the box lo..hi of `frame`: one uniform scale so the model's longest side is `long`
	(alignLong: the box's longest side, the model's longest side turned onto it), then turned by yawDeg, centred on the
	box in X / Z, lowest point on the box bottom. Moves each part (no pivots), like fitBodyToKit. ]]
local function fitInBox(parts: { BasePart }, frame: CFrame, lo: Vector3, hi: Vector3, alignLong: boolean, yawDeg: number, long: number): boolean
	local dLo, dHi = aabbIn(CFrame.identity, parts)
	local dSize = dHi - dLo
	local dLong = math.max(dSize.X, dSize.Y, dSize.Z)
	if dLong < 0.05 then
		return false
	end
	local rot = CFrame.Angles(0, math.rad(yawDeg), 0)
	local target = long
	if alignLong then
		local bSize = hi - lo
		local function axis(v: Vector3): number
			return if v.X >= v.Y and v.X >= v.Z then 1 elseif v.Y >= v.Z then 2 else 3
		end
		local da, ba = axis(dSize), axis(bSize)
		if da ~= ba then
			rot = if da + ba == 3 then CFrame.Angles(0, 0, math.rad(90)) elseif da + ba == 4 then CFrame.Angles(0, math.rad(90), 0) else CFrame.Angles(math.rad(90), 0, 0)
		end
		target = math.max(bSize.X, bSize.Y, bSize.Z)
	end
	local k = math.clamp(target / dLong, 0.05, 40)
	local c = (dLo + dHi) * 0.5
	local rel: { CFrame } = {}
	local rLo = Vector3.new(math.huge, math.huge, math.huge)
	local rHi = -rLo
	for i, p in ipairs(parts) do
		local cf = p.CFrame
		local r = rot * CFrame.new((cf.Position - c) * k) * cf.Rotation
		rel[i] = r
		local e = halfExtents(r, p.Size * k)
		rLo = rLo:Min(r.Position - e)
		rHi = rHi:Max(r.Position + e)
	end
	local shift = Vector3.new((lo.X + hi.X) * 0.5 - (rLo.X + rHi.X) * 0.5, lo.Y - rLo.Y, (lo.Z + hi.Z) * 0.5 - (rLo.Z + rHi.Z) * 0.5)
	for i, p in ipairs(parts) do
		p.Size = p.Size * k
		scalePartMeshes(p, k)
		p.CFrame = frame * CFrame.new(shift) * rel[i]
	end
	return true
end

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
	local usedRef: any = lookupPropRef(propKey)
	local template: Instance? = templateForRef(usedRef)
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
					usedRef = lookupPropRef(altKey)
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

	-- hooks (2026-09-25): a first load may have yielded: the host may be gone, or another caller dressed it meanwhile
	local hostParent: Instance? = hostPart.Parent
	if hostParent == nil or hostPart:GetAttribute("WE_CatalogAssetId") ~= nil then
		return false
	end
	local clone = cloneAsModel(template)
	if not clone then
		return false
	end
	-- hooks (2026-09-25): ref options. OmitParts drops parts (the Capture Points beam and highlight), data objects go;
	-- FitLong sets one uniform size; Fit = "Ground" stands the model upright on the host (the Home Outpost ring is a
	-- Cylinder turned on its side, so a pivot onto its CFrame would lay the pad on edge); KeepHost leaves the host alone.
	local refT = if typeof(usedRef) == "table" then usedRef :: AssetRef else nil
	dropOmitParts(clone, refT)
	dropDataChildren(clone)
	local fitLong = if refT then tonumber(refT.FitLong) else nil
	if fitLong and fitLong > 0 then
		scaleToLong(listParts(clone), fitLong)
	end
	local ground = refT ~= nil and refT.Fit == "Ground"
	if ground then
		placeOnGround(clone, hostPart)
	end
	if not weldCloneToPrimary(clone, hostPart, "WE_CatalogProp", ground) then
		clone:Destroy()
		return false
	end
	clone.Parent = hostPart
	hostPart:SetAttribute("WE_CatalogAssetId", assetId)
	-- v44 P0: props on DressHost OK to soften; never fade Body/Roof structure kits
	local kitRole = hostPart:GetAttribute("WE_KitRole")
	local keepHost = refT ~= nil and refT.KeepHost == true
	if not keepHost and kitRole ~= "Body" and kitRole ~= "Roof" and hostPart:GetAttribute("StructureId") == nil then
		hostPart.Transparency = math.max(hostPart.Transparency, 0.65)
	end
	return true
end

-- ── hooks (2026-09-25): war-business lines and vehicle turrets ─────────────────────────────────────────────────────
local bizWarned: { [string]: boolean } = {}

local function bizWarn(key: string, msg: string)
	if bizWarned[key] then
		return
	end
	bizWarned[key] = true
	warn("[VisualAssetService] " .. msg .. " — Part kit look stays")
end

-- BusinessConfig.Kit MinLevel of a kit role (nil = unknown role); lazy: VisualAssetService loads before any business
local bizKitLevels: { [string]: number }? = nil
local function kitMinLevel(role: string): number?
	if bizKitLevels == nil then
		local levels: { [string]: number } = {}
		local ok, bc = pcall(function()
			return require(ReplicatedStorage.Shared.Configs.BusinessConfig) :: any
		end)
		if ok and typeof(bc) == "table" and typeof(bc.Kit) == "table" then
			for _, kp in ipairs(bc.Kit) do
				levels[kp.Role] = kp.MinLevel
			end
		end
		bizKitLevels = levels
	end
	return (bizKitLevels :: { [string]: number })[role]
end

-- the listed roles still to dress: { index into ReplacesRoles = its built, non-colliding kit part that does not wear
-- assetId }, and how many built non-colliding roles there are (dressed or not)
local function bizMissing(model: Model, roles: { string }, assetId: number, bizId: string, piece: string?): ({ [number]: BasePart }, number)
	local missing: { [number]: BasePart } = {}
	local built = 0
	for i, role in ipairs(roles) do
		local p = model:FindFirstChild("Kit_" .. role)
		if p and p:IsA("BasePart") then
			-- bizlook: a pack piece is "on" only when the part wears that piece (one pack serves several roles / levels)
			if p:GetAttribute("WE_CatalogAssetId") == assetId and (piece == nil or p:GetAttribute("WE_CatalogPiece") == piece) then
				built += 1
			elseif p.CanCollide then
				-- a dress never takes a wall or a floor away: colliding kit parts are never taken over
				bizWarn(bizId .. "|collide|" .. role, string.format("business %s: kit role %s collides, not replaced by %d", bizId, role, assetId))
			else
				built += 1
				missing[i] = p
			end
		end
	end
	return missing, built
end

--[[ Hooks (2026-09-25): the catalog dress of a war-business line (VisualAssetConfig.Businesses[id]). Called deferred by
	BusinessService.SyncBusiness after its kit loop (a re-sync, an upgrade, a rebirth reset). Model part i (the template's
	part order) takes over the built kit part of ReplacesRoles[i]: it is named Kit_<Role>, fitted into THAT part's own box
	and the kit part is destroyed, so the business never goes over BusinessConfig.PartsPerBusinessL5 and SyncBusiness (by
	name) and the client belt crates (Kit_Belt) keep working. A Belt part (and every part with Fit = "Box") is stretched
	into its kit box exactly (block parts only); any other part gets one uniform scale onto its box's long side. Done only
	when every built listed role wears the id: a role rebuilt after a level-down is dressed again from the cached template.
	Refused (one warn, the Part kit stays): more model parts than roles, roles with different kit MinLevels (a half-built
	list), a mesh part on a Belt / Box role; colliding roles are never taken over. Same loader rules as every hook
	(MaxPartsPerModel, Humanoid stripped, MaxLoadAttempts, StripEffectsAssetIds); anchored, non-colliding; a 0 id is a no-op. ]]
local function attachBusinessRef(model: Model, id: string, level: number, ref: AssetRef?): boolean
	local assetId = refId(ref)
	if ref == nil or assetId == 0 or model.Parent == nil or (tonumber(level) or 0) < 1 then
		return false -- 0 / PendingAssetId (never read here): no load; the Part kit stays
	end
	local roles = ref.ReplacesRoles or {}
	if #roles == 0 then
		return false
	end
	local firstLevel = kitMinLevel(roles[1])
	for _, role in ipairs(roles) do
		local lv = kitMinLevel(role)
		if lv == nil or lv ~= firstLevel then
			bizWarn(id .. "|minlevel", string.format("business %s: ReplacesRoles of %d must be known kit roles with one MinLevel (%s: %s)",
				id, assetId, role, tostring(lv)))
			return false
		end
	end
	-- bizlook (BusinessPieces): a piece worn only at some levels, and the box it fills (Into: default the role's own)
	local lvNow = tonumber(level) or 0
	if (ref.FromLevel ~= nil and lvNow < ref.FromLevel) or (ref.ToLevel ~= nil and lvNow > ref.ToLevel) then
		return false
	end
	local piece: string? = if typeof(ref.ChildName) == "string" then ref.ChildName else nil
	local intoPart: BasePart? = nil
	if ref.Into ~= nil then
		local ip = model:FindFirstChild("Kit_" .. ref.Into)
		if ip == nil or not ip:IsA("BasePart") or ip:GetAttribute("WE_CatalogAssetId") ~= nil then
			return false -- the box to fill is not built (or is itself dressed): the Part kit stays
		end
		intoPart = ip
	end
	local missing, built = bizMissing(model, roles, assetId, id, piece)
	if next(missing) == nil then
		return built > 0 -- every built role already wears it (a re-sync / level-up: nothing to do)
	end
	local template = templateForRef(ref) -- may yield on the first load of this id; cached afterwards
	if not template then
		return false
	end
	-- after a yield: the kiosk may be gone, or another deferred sync may have dressed it meanwhile
	local parentNow: Instance? = model.Parent
	if parentNow == nil then
		return false
	end
	missing, built = bizMissing(model, roles, assetId, id, piece)
	if next(missing) == nil then
		return built > 0
	end
	if intoPart ~= nil and (intoPart.Parent ~= model or intoPart:GetAttribute("WE_CatalogAssetId") ~= nil) then
		return false -- the box to fill went during the insert
	end
	local clone = cloneAsModel(template)
	if not clone then
		return false
	end
	dropOmitParts(clone, ref)
	dropDataChildren(clone)
	local parts = listParts(clone)
	if #parts == 0 or #parts > #roles then
		clone:Destroy()
		bizWarn(id .. "|count", string.format("business %s: %d has %d parts for %d kit roles (BusinessConfig.PartsPerBusinessL5)", id, assetId, #parts, #roles))
		return false
	end
	-- check every part first (nothing changes on a refusal)
	for i, kp in pairs(missing) do
		local p = parts[i]
		if p and (roles[i] == "Belt" or ref.Fit == "Box") and (p:IsA("MeshPart") or hasFileMesh(p)) then
			clone:Destroy()
			bizWarn(id .. "|box", string.format("business %s: %d part %d is a mesh; the %s role needs a block part stretched into its box", id, assetId, i, roles[i]))
			return false
		end
	end
	local site = model:GetAttribute("WE_SiteCFrame")
	local dressed = 0
	for i, kp in pairs(missing) do
		local p = parts[i]
		if p then -- a role past the model's parts keeps its kit part
			if roles[i] == "Belt" or ref.Fit == "Box" then
				p.Size = kp.Size -- the client crates read Kit_Belt's box: keep it exactly
				p.CFrame = kp.CFrame
			elseif ref.Fit == "Stretch" then
				-- bizlook: a building piece (a MeshPart) turned by Yaw, then stretched to fill the Into box exactly: the
				-- front keeps its proportions when the box does, the depth is squashed (seen from the front on a phone)
				local box = intoPart or kp
				local yaw = tonumber(ref.Yaw) or 0
				local quarter = math.floor(yaw / 90 + 0.5) % 2 == 1
				p.Size = if quarter then Vector3.new(box.Size.Z, box.Size.Y, box.Size.X) else box.Size
				p.CFrame = box.CFrame * CFrame.Angles(0, math.rad(yaw), 0)
			else
				local frame: CFrame = if typeof(site) == "CFrame" then site else kp.CFrame
				local lo, hi = aabbIn(frame, { kp })
				if intoPart ~= nil then
					lo, hi = aabbIn(frame, { intoPart }) -- bizlook: a piece with Into fills that role's box
				end
				if not fitInBox({ p }, frame, lo, hi, true, 0, 1) then
					continue
				end
			end
			p.Name = kp.Name
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Massless = true
			p:SetAttribute("WE_BizRole", kp:GetAttribute("WE_BizRole"))
			p:SetAttribute("WE_CatalogAssetId", assetId)
			if piece ~= nil then
				p:SetAttribute("WE_CatalogPiece", piece) -- bizlook: which pack piece (a level swap re-dresses the role)
			end
			if ref.Into ~= nil and ref.Fit == "Stretch" then
				p:SetAttribute("WE_BizFitRole", ref.Into) -- bizlook: BusinessService refits it when that box grows
			end
			p.Parent = model
			kp:Destroy()
			dressed += 1
		end
	end
	clone:Destroy() -- the wrapper and any part no missing role needed
	-- bizlook: the collider boxes the piece stands in for turn invisible (their collision, query and name stay);
	-- BusinessService shows them again when the piece goes (WE_BizHiddenBy = the role the piece replaced)
	if dressed > 0 and ref.HideRoles ~= nil then
		for _, hr in ipairs(ref.HideRoles) do
			local hp = model:FindFirstChild("Kit_" .. hr)
			if hp and hp:IsA("BasePart") and hp:GetAttribute("WE_CatalogAssetId") == nil then
				hp.Transparency = 1
				hp.CastShadow = false
				hp:SetAttribute("WE_BizHiddenBy", roles[1])
			end
		end
	end
	return dressed > 0
end

-- bizlook: the line's own dress (VisualAssetConfig.Businesses[id]) plus the Roblox-made building pieces every line
-- may wear (VisualAssetConfig.BusinessPieces). The same one-for-one rule for both: a piece takes a non-colliding kit
-- role's place (PartsPerBusinessL5 holds); a colliding role is never taken over (a piece that stands in for a collider
-- fills that collider's box, Into, and hides it, HideRoles, keeping its collision); a 0 id is a no-op. true when the
-- line's own dress is on.
function VisualAssetService.TryAttachBusinessVisual(model: Model, id: string, level: number): boolean
	local bucket = (VisualAssetConfig :: any).Businesses
	local ref: AssetRef? = if typeof(bucket) == "table" and typeof(bucket[id]) == "table" then bucket[id] :: AssetRef else nil
	local dressed = attachBusinessRef(model, id, level, ref)
	local pieces = (VisualAssetConfig :: any).BusinessPieces
	if typeof(pieces) == "table" then
		for _, pref in pairs(pieces) do
			if typeof(pref) == "table" and model.Parent ~= nil then
				attachBusinessRef(model, id, level, pref :: AssetRef)
			end
		end
	end
	return dressed
end

-- hooks (2026-09-25): is this vehicle on the weapon ref's allow-list (KitFamilies / Vehicles)? No list = nobody.
function VisualAssetService.VehicleWeaponAllowed(weaponId: string, vehicleId: string?, kitFamily: string?): boolean
	local bucket = (VisualAssetConfig :: any).VehicleWeapons
	local ref = if typeof(bucket) == "table" then bucket[weaponId] else nil
	if typeof(ref) ~= "table" then
		return false
	end
	for _, f in ipairs(if typeof(ref.KitFamilies) == "table" then ref.KitFamilies else {}) do
		if f == kitFamily then
			return true
		end
	end
	for _, v in ipairs(if typeof(ref.Vehicles) == "table" then ref.Vehicles else {}) do
		if v == vehicleId then
			return true
		end
	end
	return false
end

--[[ Hooks (2026-09-25): the catalog dress of a vehicle weapon (VisualAssetConfig.VehicleWeapons[weaponId]) on the kit's
	mount part. Dress only: one uniform scale (longest side = the mount's longest side x FitScale), turned by Yaw
	(front -Z), centred on the mount, its lowest point on the mount's lowest point, then every part is massless,
	non-colliding, unanchored and welded to the mount (weldCloneToPrimary), so the driven assembly and its physics are
	unchanged; built before the vehicle is parented (Atomic). Only a vehicle on the ref's allow-list (KitFamilies /
	Vehicles) is dressed; the ref's HideParts (the kit gun) go invisible once it attaches. OmitParts and data objects are
	dropped. A 0 id is a no-op: no load, no attribute. ]]
function VisualAssetService.TryAttachVehicleWeaponVisual(hostModel: Model, weaponId: string, mountPart: BasePart): boolean
	local bucket = (VisualAssetConfig :: any).VehicleWeapons
	local ref: AssetRef? = if typeof(bucket) == "table" and typeof(bucket[weaponId]) == "table" then bucket[weaponId] :: AssetRef else nil
	local assetId = refId(ref)
	if ref == nil or assetId == 0 then
		return false -- 0 / PendingAssetId (never read here): no load; the kit gun stays
	end
	local vid, fam = hostModel:GetAttribute("VehicleId"), hostModel:GetAttribute("WE_KitFamily")
	if not VisualAssetService.VehicleWeaponAllowed(weaponId, if typeof(vid) == "string" then vid else nil, if typeof(fam) == "string" then fam else nil) then
		return false -- not on the ref's allow-list (a tank cannon never lands on an AA or rocket kit)
	end
	if mountPart:GetAttribute("WE_CatalogAssetId") ~= nil or not mountPart:IsDescendantOf(hostModel) then
		return false
	end
	local template = templateForRef(ref)
	if not template then
		return false
	end
	local clone = cloneAsModel(template)
	if not clone then
		return false
	end
	dropOmitParts(clone, ref)
	dropDataChildren(clone)
	local parts = listParts(clone)
	local h = mountPart.Size * 0.5
	local long = math.max(mountPart.Size.X, mountPart.Size.Y, mountPart.Size.Z) * (tonumber(ref.FitScale) or 1)
	if #parts == 0 or not fitInBox(parts, mountPart.CFrame, -h, h, false, tonumber(ref.Yaw) or 0, long) then
		clone:Destroy()
		return false
	end
	local attached = weldCloneToPrimary(clone, mountPart, "WE_CatalogWeapon_" .. weaponId, true)
	if not attached then
		clone:Destroy()
		return false
	end
	clone.Parent = hostModel
	mountPart:SetAttribute("WE_CatalogAssetId", assetId)
	-- the kit gun goes invisible under the dress (its parts, collisions and combat stay)
	for _, nm in ipairs(ref.HideParts or {}) do
		local kp = hostModel:FindFirstChild(nm)
		if kp and kp:IsA("BasePart") and not kp:IsDescendantOf(clone) then
			kp.Transparency = 1
		end
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
	if typeof(ref.Yaw) == "number" then
		mp:SetAttribute("WE_KitYaw", ref.Yaw) -- WorldKits turns the piece by it (Driftwood, CarWreck)
	end
	return mp
end

--[[ Owner list: true when VisualAssetConfig.DesertKit[key] names a piece (id > 0 and a ChildName), i.e. CloneKitMesh
	can ever return a mesh for it. Config only: never loads, never yields. WorldKits spends no MeshOverlays slot on a
	key that is not wired. ]]
function VisualAssetService.IsKitMeshWired(key: string): boolean
	local kit = (VisualAssetConfig :: any).DesertKit
	local ref: any = if typeof(kit) == "table" then kit[key] else nil
	return refId(ref) > 0 and typeof(ref.ChildName) == "string"
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
					if ref and ref.Rollout == "Body" then
						ref = nil -- v87: the owner-only fitted bodies never dress a plot's parked silhouette (unscaled, everyone sees it)
					end
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
	cooling[assetId] = nil
	retryTries[assetId] = nil
	packDone[assetId] = nil
	dressLogged[assetId] = nil
	acceptTemplate(assetId, model)
end

-- Test hook: loader counters. Requested = distinct ids that asked for an insert (first tries), CapRefused = distinct
-- ids refused by MaxLoadAttempts, Cooling = ids with a background retry pending / running, Failed = final failures.
function VisualAssetService._Stats(): { LoadAttempts: number, Cached: number, Pieces: number, PiecesFailed: number, PacksSplit: number, Requested: number, CapRefused: number, Cooling: number, Failed: number }
	local c, p, f, d, cool, fin = 0, 0, 0, 0, 0, 0
	for _ in pairs(cooling) do
		cool += 1
	end
	for _ in pairs(failed) do
		fin += 1
	end
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
	return {
		LoadAttempts = loadAttempts,
		Cached = c,
		Pieces = p,
		PiecesFailed = f,
		PacksSplit = d,
		Requested = #requestOrder,
		CapRefused = capRefused,
		Cooling = cool,
		Failed = fin,
	}
end

-- Test hook: the distinct ids that asked for an insert, in first-request order (a copy).
function VisualAssetService._Requested(): { number }
	return table.clone(requestOrder)
end

return VisualAssetService
