--!strict
--[[
	WAR EMPIRE World v2 Phase 2 (W3) — WorldKits: the Part-kit catalogue for everything built OUTSIDE the bases
	(gap/world_v2_spec.md §4.5, roadmap §2.4). Our own designs only: no competitor asset, no third-party model, no brand
	or insignia. Every kit is built from anchored Parts (H1–H10 compliant by construction) and, where a Roblox-owned
	Synty mesh exists (VisualAssetConfig.DesertKit, LOOK lane), may carry a deferred mesh overlay that REPLACES the
	fallback visuals and never adds a part — the Part kit is always built first, so a failed load (or the headless sim,
	which has no InsertService) keeps it.

	CONTRACT (scratchpad/w3/contracts.md §2): owner = B1.

	PUBLIC API (server only):
	  WorldKits.Specs : { [kitId]: KitSpec }          part count, footprint, class, collide / light / sign / mesh rules
	  WorldKits.List() -> { string }                  kit ids, sorted
	  WorldKits.Rng(seed) -> Rng                      pure-Luau xorshift32: identical sequence in the sim and on live;
	                                                  rng:NextNumber(min?, max?), rng:NextInteger(min, max) (Random API)
	  WorldKits.Part(spec, parent) -> Part            the one factory: anchored, CanTouch off, Collide → CanCollide +
	                                                  CanQuery, never Neon, CastShadow only when largest dim >= 8 (H9)
	  WorldKits.NewCluster(name, attrs) -> Model      UNPARENTED cluster Model carrying the H1 attributes (WE_Cluster,
	                                                  WE_Anchor, WE_AnchorX/Z, WE_Elements, WE_Tier, WE_AllowInWater);
	                                                  natural clusters are named "Flora_…" (a Hygiene natural prefix)
	  WorldKits.Add(cluster, kitId, cf, opts?) -> number
	                                                  builds one kit into the cluster at cf (ground pivot, y = 0.5, local
	                                                  -Z = front); returns the parts added: exactly Specs[kit].Parts at
	                                                  default opts, Parts x units with Count / Length (<= PartsMax);
	                                                  0 = unknown kit or a step-2 kit not built yet (warned once)
	  WorldKits.Finish(cluster, parent) -> ClusterInfo
	                                                  checks parts > 0 and XZ span <= 64 (H10), parents it, then queues
	                                                  the deferred mesh overlays; an invalid cluster is destroyed and
	                                                  never parented (Ok = false)
	  WorldKits.Discard(cluster)                      destroys a cluster that was built but not Finished (a keep-out
	                                                  hit): its pending signs / overlays are dropped
	  WorldKits.Place(kitId, cf, parent, opts) -> Model?
	                                                  NewCluster + Add + Finish for a one-kit cluster
	  WorldKits.Footprint(kitId, opts?) -> Footprint  the kit's exact extents in its own frame at yaw 0 (measured once
	                                                  from a throw-away build, cached): X0 / X1 / Z0 / Z1 / Top, plus
	                                                  CollideZ0 (nearest collidable part toward the front, -Z) and
	                                                  VisibleZ0 (nearest visible part taller than 0.3). Road-side kits
	                                                  keep every collidable part at local z >= 0 (the back half)
	  WorldKits.Rock(pos, kind, rng, opts?) -> { Prim }
	                                                  Terrain rock group (0 parts): "outcrop" | "boulders" | "rubble" |
	                                                  "scorch"; every prim stays within opts.Radius (default
	                                                  WorldConfig.Kits.Rock[kind].Radius) of pos; fills through the
	                                                  terrain handle and appends to the log (Tag "rock", Run = kind).
	                                                  It does not test keep-outs: callers test WorldDress.Blocked first
	  WorldKits.Sign(board, face, text, opts?) -> SurfaceGui?
	                                                  painted sign (Shared/Util/WorldLabel.Surface, MaxDistance <= 80);
	                                                  nil when the world sign budget (WorldConfig.Budgets.SurfaceGuis,
	                                                  counted outside the bases) is spent
	  WorldKits.SetTerrain(handle?) / TerrainLog() / ResetTerrainLog() / TerrainHandle()
	                                                  terrain handle (tests pass a recorder; nil = Workspace.Terrain) and
	                                                  the prims filled since the last reset (the sim dumps them)

	FRAME: cf is the kit's ground pivot (desert floor y = 0.5, yaw only). Local -Z is the kit's front (it faces the road
	or the viewer); +X is right. Specs[kit].Size is the kit's AABB size at yaw 0 (default opts); Footprint gives the
	pivot-relative extents. Pivots: road-side kits (wrecks, drums, crates, sandbags, nest, markers, signs, jersey) sit
	at the front edge of their collidable mass (collidables at z >= 0); JettyStub / BargeWreck / BeachedHull at their
	landward end (the hull reaches toward -Z, the water); Checkpoint on the road centre line (X across the road, booth
	on +X); everything else roughly centred.

	MESH OVERLAYS (contracts §8.3; LOOK's VisualAssetService.CloneKitMesh): deferred, capped by
	WorldConfig.Kits.MeshOverlays, never blocking, never adding a part:
	  "each"     natural kits (DeadTree, Stump, Log, Reeds, DuneGrass, Driftwood): each part becomes one mesh (net 0)
	  "skin"     1-part solid units (CrateStack crates, Bench): the part keeps its box collision and renders the mesh
	             through a SpecialMesh (net 0; a separate collider would add a part)
	  "collider" multi-part solid kits (Wreck "car"): the largest part becomes the invisible box collider sized to the
	             kit, the other parts go, one mesh is added (net 2 - n)
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Configs = ReplicatedStorage.Shared.Configs
local WorldConfig = require(Configs.WorldConfig)
local WorldTerrain = require(script.Parent.WorldTerrain)
local WorldLabel = require(ReplicatedStorage.Shared.Util.WorldLabel)

export type Prim = WorldTerrain.Prim

-- Class: "manmade" | "natural" | "marking". Solid: its cover parts >= 1.5 tall collide + query (H4).
-- Size: AABB size at yaw 0 (X across, Y up from the floor, Z depth; the kit's front faces local -Z), default opts.
-- Parts: exact count at default opts (per unit for Count / Length kits). Step: 1 = needed in W3 step 1 (Town + travel
-- dressing), 2 = later POIs. Use: who places it in step 1 ("Town", "Travel", "Town+Travel", "POI" = later).
export type KitSpec = {
	Parts: number,
	PartsMax: number,
	Size: Vector3,
	Class: string,
	Solid: boolean,
	Lights: number,
	Signs: number,
	Mesh: string?, -- VisualAssetConfig.DesertKit key (Roblox-owned Synty piece) for the deferred overlay
	Water: boolean, -- may step into water (its cluster carries WE_AllowInWater)
	Step: number,
	Use: string,
	Unit: string?, -- Count / Length kits: what Parts counts per
}

export type KitOpts = {
	Variant: string?, -- Wreck: "car" | "truck" | "tank"; RoadMarker: "km" | "hazard"; AdobeHouse: "tall" | "wide" | "shop"; CrateStack: "ammo"
	Count: number?, -- CrateStack / DrumGroup units
	Length: number?, -- SandbagLine studs (1 part per 5); CompoundWall studs (1 part per 16)
	Scale: number?, -- natural kits only (0.7 .. 1.3; >= 2 sizes per natural cluster)
	Text: string?, -- PoiBoard / DirSign: SurfaceGui text, only when the world sign budget allows
	Color: Color3?, -- tint override (tarps, walls)
	Light: boolean?, -- StreetLamp: build its night PointLight (default true)
	Mesh: boolean?, -- try the Roblox-owned mesh overlay when Specs[kit].Mesh is set (default true)
	Seed: number?, -- per-instance jitter (default: from the pivot position)
}

export type ClusterAttrs = {
	Source: string, -- "poi" | "rhythm" | "junction" | "shore" | "bay" | "scatter"
	Kind: string, -- cluster kind, e.g. "stall", "wreck_or_nest", "flora_group"
	Anchor: string, -- "poi:<Id>" | "road:<RoadName>" | "junction:<x>,<z>" | "water:<Side>" | "natural"
	AnchorX: number, -- the anchor point H1 measures to (nearest point of the anchor feature)
	AnchorZ: number,
	Natural: boolean?, -- every part natural (flora / dead wood): name gets the "Flora_" prefix
	Elements: number?, -- natural clusters: elements incl. Terrain rocks (H1 stand-alone rule >= 3)
	Tier: number?, -- POIs: 1 = built in Low and Full, 2 = Full only
	InWater: boolean?, -- sets WE_AllowInWater (jetty stub, barge, beached hull)
}

export type PlaceOpts = {
	Name: string,
	Cluster: ClusterAttrs,
	Kit: KitOpts?,
}

export type ClusterInfo = {
	Ok: boolean,
	Parts: number,
	Span: number, -- XZ extent (studs)
	Lights: number,
	Signs: number,
	Reason: string?,
}

export type PartSpec = {
	Name: string,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3?,
	Material: Enum.Material?,
	Shape: Enum.PartType?,
	Transparency: number?,
	Collide: boolean?, -- true → CanCollide + CanQuery (cover); default false (both off)
	CastShadow: boolean?, -- honoured only when the largest dimension >= WorldConfig.Hygiene.ShadowMinSize (8)
}

export type Rng = {
	NextNumber: (self: any, min: number?, max: number?) -> number,
	NextInteger: (self: any, min: number, max: number) -> number,
}

export type Footprint = {
	X0: number,
	X1: number,
	Z0: number,
	Z1: number,
	Top: number, -- above the floor
	CollideZ0: number, -- min local z of the collidable parts (math.huge: none)
	VisibleZ0: number, -- min local z of the visible parts taller than 0.3 (math.huge: none)
	Parts: number,
}

local WorldKits = {}

local NATURAL_PREFIX = "Flora_"
local MAX_SPAN = WorldConfig.Hygiene.MaxModelSpan -- 64 (H10)
local SHADOW_MIN = WorldConfig.Hygiene.ShadowMinSize -- 8 (H9)
local GROUND_Y = 0.5 -- desert floor top
local KC = WorldConfig.Kits
local PAL = KC.Palette
local M = Enum.Material

type SpecExtra = { Lights: number?, Signs: number?, Mesh: string?, Water: boolean?, Unit: string? }

local function spec(
	parts: number,
	partsMax: number,
	size: Vector3,
	class: string,
	solid: boolean,
	step: number,
	use: string,
	extra: SpecExtra?
): KitSpec
	local e: SpecExtra = extra or {}
	return {
		Parts = parts,
		PartsMax = partsMax,
		Size = size,
		Class = class,
		Solid = solid,
		Lights = e.Lights or 0,
		Signs = e.Signs or 0,
		Mesh = e.Mesh,
		Water = e.Water == true,
		Step = step,
		Use = use,
		Unit = e.Unit,
	}
end

-- ── Catalogue (spec §4.5; part caps in brackets there). Sizes = measured AABB of the default build ─────────────────
WorldKits.Specs = {
	-- Step 1 — Crossroads Town (B1 places)
	MarketStall = spec(7, 7, Vector3.new(10.6, 7.5, 8.9), "manmade", true, 1, "Town"), -- tarp roof (cloth), counter, 2 crates on the table, posts, back wall
	WaterTower = spec(9, 9, Vector3.new(13, 43.2, 13), "manmade", true, 1, "Town"), -- landmark: top >= 42
	ClockTower = spec(8, 8, Vector3.new(10, 40, 10), "manmade", true, 1, "Town"), -- landmark: top >= 38
	AdobeHouse = spec(5, 5, Vector3.new(13.2, 8, 10.2), "manmade", true, 1, "Town"), -- kitAdobeBuilding without the Neon accent ("tall": 2 storeys)
	RuinedHouse = spec(5, 5, Vector3.new(14, 7, 11.4), "manmade", true, 1, "Town"), -- kitRuinLandmark trimmed: broken walls + fallen roof slab
	CompoundWall = spec(1, 4, Vector3.new(16, 3, 1.2), "manmade", true, 1, "Town", { Unit = "16 studs" }), -- chest-high adobe wall (cover)
	Checkpoint = spec(8, 8, Vector3.new(36.3, 12.9, 11.9), "manmade", true, 1, "Town"), -- v2: booth on the shoulder, raised CheckpointArm, sandbags >= 13 off the line, painted board
	StreetLamp = spec(3, 3, Vector3.new(1.2, 12, 3.7), "manmade", false, 1, "Town", { Lights = 1 }), -- pole, arm, SmoothPlastic lens + night PointLight
	PoiBoard = spec(2, 2, Vector3.new(10, 6.2, 1), "manmade", false, 1, "Town", { Signs = 1 }), -- post + painted board (+1 SurfaceGui with Text)
	PaveTile = spec(1, 1, Vector3.new(45, 0.12, 45), "marking", false, 1, "Town"), -- Town Square paving, top <= 0.75, no collide
	Fountain = spec(4, 4, Vector3.new(10, 3.6, 10), "manmade", true, 1, "Town"), -- dry fountain
	Bench = spec(1, 1, Vector3.new(6, 1.2, 1.8), "manmade", false, 1, "Town", { Mesh = "Bench" }),
	-- Step 1 — shared by the Town and the travel dressing
	CrateStack = spec(3, 6, Vector3.new(5.2, 4.8, 2.9), "manmade", true, 1, "Town+Travel", { Mesh = "CrateWood", Unit = "crate" }),
	DrumGroup = spec(3, 6, Vector3.new(3.2, 2.2, 3.0), "manmade", true, 1, "Town+Travel", { Unit = "drum" }),
	SandbagLine = spec(1, 8, Vector3.new(5.05, 2, 1.7), "manmade", true, 1, "Town+Travel", { Unit = "5 studs" }),
	Jersey = spec(1, 1, Vector3.new(4.5, 2.2, 1.1), "manmade", true, 1, "Town+Travel"),
	Wreck = spec(5, 5, Vector3.new(14.9, 3.4, 4.4), "manmade", true, 1, "Town+Travel", { Mesh = "CarWreck" }), -- car 4 / truck 5 / tank 5 parts (Variant); long axis along X
	-- Step 1 — travel dressing (B2 places, B1 builds)
	SandbagNest = spec(6, 6, Vector3.new(8.8, 3.5, 7.3), "manmade", true, 1, "Travel"), -- U of sandbags + MG silhouette
	RoadMarker = spec(2, 2, Vector3.new(1.05, 3.1, 0.75), "manmade", false, 1, "Travel"), -- Variant "km" (km post) | "hazard" (sign)
	DirSign = spec(2, 2, Vector3.new(4, 6, 0.6), "manmade", false, 1, "Travel", { Signs = 1 }), -- post + arrow board (text only with Text + budget)
	SandbagArc = spec(2, 2, Vector3.new(7.1, 2, 2.6), "manmade", true, 1, "Travel"),
	Revetment = spec(3, 3, Vector3.new(16.1, 2.3, 3.9), "manmade", true, 1, "Travel"), -- concrete slabs on the canal bank
	JettyStub = spec(3, 3, Vector3.new(4, 1.6, 14), "manmade", false, 1, "Travel", { Water = true }), -- deck + 2 piles
	BargeWreck = spec(5, 5, Vector3.new(9.2, 8.3, 23.3), "manmade", true, 1, "Travel", { Water = true }),
	BeachedHull = spec(4, 4, Vector3.new(6.4, 3.9, 16.2), "manmade", true, 1, "Travel", { Water = true }),
	Joshua = spec(2, 2, Vector3.new(5.7, 7.8, 5.7), "natural", false, 1, "Travel"), -- trimmed: trunk + crown
	Saguaro = spec(2, 2, Vector3.new(4.1, 9.5, 1.4), "natural", false, 1, "Travel"), -- trimmed: trunk + arm
	BarrelCactus = spec(1, 1, Vector3.new(2.2, 1.8, 2.2), "natural", false, 1, "Travel"),
	DeadTree = spec(1, 1, Vector3.new(2.05, 11, 1.1), "natural", false, 1, "Travel", { Mesh = "DeadTree" }),
	Stump = spec(1, 1, Vector3.new(2.4, 1.6, 2.4), "natural", false, 1, "Travel", { Mesh = "Stump" }),
	Log = spec(1, 1, Vector3.new(1.5, 1.5, 9), "natural", false, 1, "Travel", { Mesh = "Log" }),
	Reeds = spec(2, 2, Vector3.new(3.5, 3.2, 2.3), "natural", false, 1, "Travel", { Mesh = "Reeds" }),
	DuneGrass = spec(2, 2, Vector3.new(4.8, 1.1, 3.5), "natural", false, 1, "Travel", { Mesh = "DuneGrass" }),
	Driftwood = spec(2, 2, Vector3.new(7.05, 0.9, 3.8), "natural", false, 1, "Travel", { Mesh = "Log" }),
	-- Step 2 — later POIs (caps from spec §4.5; not built in W3 step 1: Add warns once and returns 0)
	ContainerStack = spec(3, 12, Vector3.new(10, 9, 22), "manmade", true, 2, "POI", { Unit = "container" }),
	GantryCrane = spec(8, 8, Vector3.new(30, 55, 20), "manmade", true, 2, "POI"),
	FuelTank = spec(3, 3, Vector3.new(14, 12, 14), "manmade", true, 2, "POI"),
	FlareStack = spec(3, 3, Vector3.new(6, 45, 6), "manmade", true, 2, "POI"),
	RadarDome = spec(5, 5, Vector3.new(16, 18, 16), "manmade", true, 2, "POI"),
	CargoPlaneWreck = spec(10, 10, Vector3.new(60, 12, 64), "manmade", true, 2, "POI"),
	HeliWreck = spec(6, 6, Vector3.new(10, 6, 24), "manmade", true, 2, "POI"),
	TankTrap = spec(2, 2, Vector3.new(3, 3, 3), "manmade", true, 2, "POI"),
	TrenchRun = spec(6, 18, Vector3.new(4, 2, 20), "manmade", true, 2, "POI", { Unit = "20 studs" }),
	Crusher = spec(6, 6, Vector3.new(16, 14, 20), "manmade", true, 2, "POI"),
	Bollard = spec(1, 1, Vector3.new(1, 1.5, 1), "manmade", false, 2, "POI"),
	GaragePadV2 = spec(3, 3, Vector3.new(20, 1.2, 20), "manmade", false, 2, "POI"),
	PontoonV2 = spec(2, 2, Vector3.new(16, 1.2, 16), "manmade", false, 2, "POI", { Water = true }),
	Watchtower = spec(8, 8, Vector3.new(8, 20, 8), "manmade", true, 2, "POI"),
	Bunker = spec(4, 4, Vector3.new(16, 6, 12), "manmade", true, 2, "POI"),
	Hangar = spec(5, 5, Vector3.new(28, 12, 22), "manmade", true, 2, "POI"),
	AmmoShed = spec(5, 5, Vector3.new(12, 6, 10), "manmade", true, 2, "POI"),
	RadioMast = spec(5, 5, Vector3.new(10, 90, 10), "manmade", true, 2, "POI"),
	WireFence = spec(4, 12, Vector3.new(16, 3, 0.4), "manmade", false, 2, "POI", { Unit = "16 studs" }),
	Tent = spec(5, 5, Vector3.new(9, 5, 7), "manmade", true, 2, "POI"),
	Campfire = spec(3, 3, Vector3.new(4, 1, 4), "manmade", false, 2, "POI"),
	Palm = spec(5, 5, Vector3.new(10, 13, 10), "natural", false, 2, "POI"),
	Pumpjack = spec(7, 7, Vector3.new(8, 12, 20), "manmade", true, 2, "POI"), -- the OilSpectacle derrick + walking beam
} :: { [string]: KitSpec }

function WorldKits.List(): { string }
	local out: { string } = {}
	for id in pairs(WorldKits.Specs) do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

-- ── PRNG (xorshift32 on bit32): the same numbers in the headless sim and on a live server ─────────────────────────
function WorldKits.Rng(seed: number): Rng
	local state = bit32.bxor(math.floor(seed) % 4294967296, 0x9E3779B9)
	if state == 0 then
		state = 0x6D2B79F5
	end
	local function step(): number
		local x = state
		x = bit32.bxor(x, bit32.lshift(x, 13))
		x = bit32.bxor(x, bit32.rshift(x, 17))
		x = bit32.bxor(x, bit32.lshift(x, 5))
		state = x
		return x
	end
	for _ = 1, 4 do
		step()
	end
	local rng = {}
	function rng.NextNumber(_self: any, min: number?, max: number?): number
		local f = step() / 4294967296
		if min ~= nil and max ~= nil then
			return min + (max - min) * f
		end
		return f
	end
	function rng.NextInteger(_self: any, min: number, max: number): number
		local f = step() / 4294967296
		return math.min(max, min + math.floor(f * (max - min + 1)))
	end
	return rng :: Rng
end

-- ── Part factory ──────────────────────────────────────────────────────────────────────────────────────────────────
function WorldKits.Part(ps: PartSpec, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = ps.Name
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = ps.Size
	p.CFrame = ps.CFrame
	if ps.Shape then
		p.Shape = ps.Shape
	end
	p.Color = ps.Color or Color3.fromRGB(150, 130, 90)
	local mat = ps.Material or Enum.Material.SmoothPlastic
	p.Material = if mat == Enum.Material.Neon then Enum.Material.SmoothPlastic else mat -- H5: never Neon
	p.Transparency = ps.Transparency or 0
	local collide = ps.Collide == true
	p.CanCollide = collide
	p.CanQuery = collide
	p.CanTouch = false
	local s = ps.Size
	p.CastShadow = ps.CastShadow == true and math.max(s.X, s.Y, s.Z) >= SHADOW_MIN -- H9
	p:SetAttribute("WE_Decor", true)
	p.Parent = parent
	return p
end

-- ── cluster state (open = built by NewCluster, not yet Finished / Discarded) ───────────────────────────────────────
type Overlay = { Key: string, Mode: string, Frame: CFrame, Parts: { BasePart } }
local openClusters = setmetatable({} :: { [Model]: boolean }, { __mode = "k" })
local pendingSigns = setmetatable({} :: { [Model]: number }, { __mode = "k" })
local pendingMesh = setmetatable({} :: { [Model]: { Overlay } }, { __mode = "k" })
local overlaysQueued = 0

function WorldKits.NewCluster(name: string, attrs: ClusterAttrs): Model
	local m = Instance.new("Model")
	local natural = attrs.Natural == true
	m.Name = if natural and string.sub(name, 1, #NATURAL_PREFIX) ~= NATURAL_PREFIX then NATURAL_PREFIX .. name else name
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- a cluster never streams in half-built
	m:SetAttribute("WE_Cluster", attrs.Source .. ":" .. attrs.Kind)
	m:SetAttribute("WE_Anchor", attrs.Anchor)
	m:SetAttribute("WE_AnchorX", attrs.AnchorX)
	m:SetAttribute("WE_AnchorZ", attrs.AnchorZ)
	if natural then
		m:SetAttribute("WE_Natural", true)
	end
	if attrs.Elements ~= nil then
		m:SetAttribute("WE_Elements", attrs.Elements)
	end
	if attrs.Tier ~= nil then
		m:SetAttribute("WE_Tier", attrs.Tier)
	end
	if attrs.InWater == true then
		m:SetAttribute("WE_AllowInWater", true)
	end
	openClusters[m] = true
	return m
end

local function openClusterOf(inst: Instance): Model?
	local cur: Instance? = inst
	while cur do
		if cur:IsA("Model") and openClusters[cur :: Model] then
			return cur :: Model
		end
		cur = cur.Parent
	end
	return nil
end

-- ── Signs (painted SurfaceGui; the world budget is WorldConfig.Budgets.SurfaceGuis outside the bases) ─────────────
local BASES: { [string]: boolean } = {}
for _, n in ipairs(WorldConfig.Hygiene.BaseFolders) do
	BASES[n] = true
end

local function worldSignsUsed(): number
	local n = 0
	local root = Workspace:FindFirstChild("WarEmpireSetup")
	if root then
		for _, ch in ipairs(root:GetChildren()) do
			if not BASES[ch.Name] then
				for _, d in ipairs(ch:GetDescendants()) do
					if d:IsA("SurfaceGui") then
						n += 1
					end
				end
			end
		end
	end
	for c, k in pairs(pendingSigns) do
		if openClusters[c] then
			n += k
		end
	end
	return n
end

function WorldKits.Sign(board: BasePart, face: Enum.NormalId, text: string, opts: { MaxDistance: number? }?): SurfaceGui?
	if text == "" then
		return nil
	end
	local used = worldSignsUsed()
	if used >= WorldConfig.Budgets.SurfaceGuis then
		warn(string.format("[WorldKits] sign %q skipped: the world sign budget is spent (%d / %d)", text, used, WorldConfig.Budgets.SurfaceGuis))
		return nil
	end
	local maxD = math.min((opts and opts.MaxDistance) or KC.SignMaxDistance, KC.SignMaxDistance)
	local gui = WorldLabel.Surface(board, face, text, { Name = "WE_WorldSign", MaxDistance = maxD, Color = PAL.LampLens })
	local cluster = openClusterOf(board)
	if cluster then
		pendingSigns[cluster] = (pendingSigns[cluster] or 0) + 1
	end
	return gui
end

-- ── Kit builders ──────────────────────────────────────────────────────────────────────────────────────────────────
type B = {
	Cluster: Model,
	CF: CFrame,
	Opts: KitOpts,
	Parts: { BasePart },
	Rng: Rng,
	Overlays: { Overlay },
}

local VCYL = CFrame.Angles(0, 0, math.rad(90)) -- a Cylinder's axis (its local X) turned vertical
local ZCYL = CFrame.Angles(0, math.rad(90), 0) -- a Cylinder's axis along the kit's local Z

local function rotY(deg: number): CFrame
	return CFrame.Angles(0, math.rad(deg), 0)
end
local function rotX(deg: number): CFrame
	return CFrame.Angles(math.rad(deg), 0, 0)
end
local function rotZ(deg: number): CFrame
	return CFrame.Angles(0, 0, math.rad(deg))
end

-- one part in the kit frame (lcf = local CFrame of the part centre, y measured from the floor)
local function put(
	b: B,
	name: string,
	size: Vector3,
	lcf: CFrame,
	color: Color3,
	mat: Enum.Material?,
	collide: boolean?,
	shadow: boolean?,
	shape: Enum.PartType?
): Part
	local p = WorldKits.Part({
		Name = name,
		Size = size,
		CFrame = b.CF * lcf,
		Color = color,
		Material = mat,
		Collide = collide,
		CastShadow = shadow,
		Shape = shape,
	}, b.Cluster)
	table.insert(b.Parts, p)
	return p
end

-- vertical cylinder standing on y0 (height h, diameter d)
local function vcyl(b: B, name: string, x: number, y0: number, z: number, h: number, d: number, color: Color3, mat: Enum.Material?, collide: boolean?, shadow: boolean?): Part
	return put(b, name, Vector3.new(h, d, d), CFrame.new(x, y0 + h * 0.5, z) * VCYL, color, mat, collide, shadow, Enum.PartType.Cylinder)
end

local function scaleOf(b: B): number
	return math.clamp(b.Opts.Scale or 1, 0.5, 1.6)
end

-- queue a mesh overlay for this kit instance (Finish schedules it)
local function queueMesh(b: B, kitId: string, mode: string, parts: { BasePart })
	local key = WorldKits.Specs[kitId].Mesh
	if key == nil or b.Opts.Mesh == false then
		return
	end
	table.insert(b.Overlays, { Key = key, Mode = mode, Frame = b.CF, Parts = table.clone(parts) })
end

local Builders: { [string]: (b: B) -> () } = {}

-- Town ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
Builders.MarketStall = function(b: B)
	local tarp = b.Opts.Color or PAL.TarpRed
	put(b, "StallCounter", Vector3.new(8, 2.8, 2.2), CFrame.new(0, 1.4, -2.6), PAL.Wood, M.Wood, true)
	put(b, "Crate", Vector3.new(1.6, 1.4, 1.6), CFrame.new(-2.2, 3.5, -2.6) * rotY(15), PAL.Crate, M.Wood, true)
	put(b, "Crate", Vector3.new(1.4, 1.2, 1.4), CFrame.new(2.0, 3.4, -2.5) * rotY(-10), PAL.CrateOlive, M.Wood, true)
	put(b, "StallPost", Vector3.new(0.5, 6.4, 0.5), CFrame.new(-4.7, 3.2, -3.9), PAL.WoodDark, M.Wood, true)
	put(b, "StallPost", Vector3.new(0.5, 6.4, 0.5), CFrame.new(4.7, 3.2, -3.9), PAL.WoodDark, M.Wood, true)
	put(b, "StallWall", Vector3.new(10, 7.2, 0.6), CFrame.new(0, 3.6, 3.9), PAL.AdobeDark, M.Sandstone, true, true)
	-- cloth awning from the back wall top (z 4.2, y 7.35) down to the posts (z -4.6, y 6.55)
	put(b, "StallTarp", Vector3.new(10.6, 0.3, 8.9), CFrame.new(0, 6.95, -0.2) * rotX(-5.2), tarp, M.Fabric, false, true)
end

Builders.WaterTower = function(b: B)
	for _, c in ipairs({ { -5, -5 }, { 5, -5 }, { -5, 5 }, { 5, 5 } }) do
		put(b, "TowerLeg", Vector3.new(1, 30, 1), CFrame.new(c[1], 15, c[2]), PAL.Steel, M.Metal, true)
	end
	put(b, "TowerLadder", Vector3.new(1.4, 30, 0.2), CFrame.new(0, 15, -5.4), PAL.SteelDark, M.Metal, false)
	put(b, "TowerDeck", Vector3.new(13, 0.6, 13), CFrame.new(0, 30.3, 0), PAL.WoodDark, M.Wood, true, true)
	vcyl(b, "WaterTank", 0, 30.6, 0, 10, 11, PAL.TankCream, M.Metal, true, true)
	vcyl(b, "TankRoof", 0, 40.6, 0, 1, 12.4, PAL.Rust, M.CorrodedMetal, true, true)
	vcyl(b, "TankRoofCap", 0, 41.6, 0, 1.6, 4, PAL.Rust, M.CorrodedMetal, false)
end

Builders.ClockTower = function(b: B)
	put(b, "ClockPlinth", Vector3.new(10, 2, 10), CFrame.new(0, 1, 0), PAL.AdobeDark, M.Sandstone, true)
	put(b, "ClockShaftAdobe", Vector3.new(8, 27, 8), CFrame.new(0, 15.5, 0), PAL.Adobe, M.Sandstone, true, true)
	put(b, "ClockHead", Vector3.new(9, 6, 9), CFrame.new(0, 32, 0), PAL.AdobeLight, M.Sandstone, true, true)
	put(b, "ClockRoof", Vector3.new(10, 1, 10), CFrame.new(0, 35.5, 0), PAL.AdobeDark, M.Sandstone, true)
	put(b, "ClockDome", Vector3.new(4.4, 4.4, 4.4), CFrame.new(0, 37.8, 0), PAL.Adobe, M.Sandstone, true, false, Enum.PartType.Ball)
	put(b, "ClockFace", Vector3.new(0.3, 5, 5), CFrame.new(0, 32, -4.65) * ZCYL, PAL.ClockFace, M.SmoothPlastic, false, false, Enum.PartType.Cylinder)
	put(b, "ClockFace", Vector3.new(0.3, 5, 5), CFrame.new(0, 32, 4.65) * ZCYL, PAL.ClockFace, M.SmoothPlastic, false, false, Enum.PartType.Cylinder)
	put(b, "ClockHand", Vector3.new(0.35, 2.2, 0.2), CFrame.new(0.45, 32.7, -4.9) * rotZ(-30), PAL.HazardDark, M.SmoothPlastic, false)
end

-- Variants (always 5 parts): nil = 12 x 7 (door, 2 windows), "tall" = 2 storeys, "wide" = an 18-wide row house,
-- "shop" = a cloth awning over the door instead of the second window (opts.Color tints the walls)
Builders.AdobeHouse = function(b: B)
	local v = b.Opts.Variant
	local tall, wide, shop = v == "tall", v == "wide", v == "shop"
	local h = if tall then 11 else 7
	local w = if wide then 18 else 12
	local wall = b.Opts.Color or PAL.Adobe
	put(b, "AdobeBody", Vector3.new(w, h, 9), CFrame.new(0, h * 0.5, 0), wall, M.Sandstone, true, true)
	put(b, "AdobeRoof", Vector3.new(w + 1.2, 1, 10.2), CFrame.new(0, h + 0.5, 0), PAL.AdobeDark, M.Sandstone, true)
	local doorX = if tall then -3 elseif wide then -4.5 elseif shop then -2.5 else 0
	put(b, "AdobeDoor", Vector3.new(2.2, 3.4, 0.35), CFrame.new(doorX, 1.7, -4.675), PAL.WoodDark, M.Wood, false)
	if shop then
		put(b, "AdobeWindow", Vector3.new(2.4, 1.6, 0.25), CFrame.new(2.8, 2.6, -4.62), PAL.Window, M.SmoothPlastic, false)
		-- a shop awning over the door and window (cloth, soft)
		put(b, "ShopTarp", Vector3.new(10.4, 0.25, 2.6), CFrame.new(0.2, 4.6, -5.7) * rotX(12), b.Opts.Color and PAL.TarpBlue or PAL.TarpRed, M.Fabric, false, true)
		return
	end
	local wy = if tall then 7.8 else 4.2
	local wx = if tall then { -0.2, 3.6 } elseif wide then { 0.5, 5.5 } else { -3.5, 3.5 }
	for _, x in ipairs(wx) do
		put(b, "AdobeWindow", Vector3.new(1.6, 1.4, 0.25), CFrame.new(x, wy, -4.62), PAL.Window, M.SmoothPlastic, false)
	end
end

-- a chest-high adobe compound wall (cover): 1 part per 16 studs of opts.Length (default 16, max 4), centred on the pivot
Builders.CompoundWall = function(b: B)
	local n = math.clamp(math.floor((b.Opts.Length or 16) / 16 + 0.5), 1, 4)
	for i = 1, n do
		local x = (i - (n + 1) * 0.5) * 16
		local h = if i % 2 == 0 then 3.4 else 3.0
		put(b, "AdobeWall", Vector3.new(16, h, 1.2), CFrame.new(x, h * 0.5, 0.6), b.Opts.Color or PAL.AdobeDark, M.Sandstone, true)
	end
end

Builders.RuinedHouse = function(b: B)
	local wall = b.Opts.Color or PAL.Adobe
	put(b, "RuinWallBack", Vector3.new(14, 7, 1.2), CFrame.new(0, 3.5, 5.4), wall, M.Sandstone, true, true)
	put(b, "RuinWallSide", Vector3.new(1.2, 5, 10), CFrame.new(-6.4, 2.5, 0.2), PAL.AdobeDark, M.Sandstone, true, true)
	put(b, "RuinWallFront", Vector3.new(5, 3.2, 1.2), CFrame.new(-4.5, 1.6, -4.8), wall, M.Sandstone, true)
	put(b, "RuinWallFront", Vector3.new(3.4, 5.6, 1.2), CFrame.new(5.3, 2.8, -4.8), wall, M.Sandstone, true)
	-- the fallen roof slab, resting on the side wall and the floor
	put(b, "RuinDebris", Vector3.new(9.5, 0.8, 8), CFrame.new(-1.2, 2.6, 0.6) * rotZ(-28), PAL.AdobeDark, M.Sandstone, true, true)
end

Builders.Checkpoint = function(b: B)
	-- pivot on the road centre line; X across the road, the booth on the +X shoulder; -Z faces arriving traffic
	put(b, "CheckpointBooth", Vector3.new(4, 5, 4.4), CFrame.new(17.5, 2.5, 2.0), PAL.ConcreteLight, M.Concrete, true)
	put(b, "BoothRoof", Vector3.new(6, 0.4, 6.4), CFrame.new(17.5, 5.2, 1.6), PAL.SteelDark, M.Metal, false)
	put(b, "BoothWindow", Vector3.new(0.2, 1.6, 2.8), CFrame.new(15.4, 3.2, 2.0), PAL.Window, M.SmoothPlastic, false)
	put(b, "CheckpointSign", Vector3.new(3.2, 1.6, 0.2), CFrame.new(17.6, 3.4, -0.3), PAL.TarpRed, M.SmoothPlastic, false)
	-- the boom, raised: standing on the shoulder, tilted 8 degrees away from the lane (never across it)
	local dir = Vector3.new(math.sin(math.rad(8)), math.cos(math.rad(8)), 0)
	local hinge = Vector3.new(13.6, 0, -0.9)
	local c1 = hinge + dir * 6.5
	put(b, "CheckpointArm", Vector3.new(0.45, 13, 0.45), CFrame.new(c1.X, c1.Y, c1.Z) * rotZ(-8), PAL.Hazard, M.SmoothPlastic, false)
	local c2 = hinge + dir * 5.0
	put(b, "ArmStripe", Vector3.new(0.5, 1.8, 0.5), CFrame.new(c2.X, c2.Y, c2.Z) * rotZ(-8), PAL.HazardDark, M.SmoothPlastic, false)
	put(b, "Sandbag", Vector3.new(2.4, 2.2, 8), CFrame.new(-14.6, 1.1, 0), PAL.Sandbag, M.Sand, true)
	put(b, "Sandbag", Vector3.new(2.4, 2.2, 5), CFrame.new(14.6, 1.1, -4.6), PAL.SandbagLight, M.Sand, true)
end

local function nightOn(): boolean
	local ok, on = pcall(function(): boolean
		local mod = script.Parent:FindFirstChild("WorldAtmosphere")
		if mod == nil or not mod:IsA("ModuleScript") then
			return false
		end
		local WA: any = (require :: any)(mod)
		return WA.NightShare(Lighting.ClockTime) > 0.5
	end)
	return ok and on == true
end

Builders.StreetLamp = function(b: B)
	put(b, "LampPole", Vector3.new(0.5, 12, 0.5), CFrame.new(0, 6, 0), PAL.SteelDark, M.Metal, true)
	put(b, "LampArm", Vector3.new(0.3, 0.3, 3.2), CFrame.new(0, 11.7, -1.45), PAL.Steel, M.Metal, false)
	local lens = put(b, "LampLens", Vector3.new(1.2, 0.5, 1.2), CFrame.new(0, 11.3, -2.8), PAL.LampLens, M.SmoothPlastic, false)
	if b.Opts.Light ~= false then
		local L = KC.Lamp
		local light = Instance.new("PointLight")
		light.Name = "LampLight"
		light.Brightness = math.min(L.Brightness, WorldConfig.Lights.MaxBrightness)
		light.Range = math.min(L.Range, WorldConfig.Lights.MaxRange)
		light.Color = L.Color
		light.Shadows = false
		light.Enabled = nightOn() -- WorldAtmosphere flips WE_NightLight lights at dusk / dawn
		CollectionService:AddTag(light, WorldConfig.Atmosphere.NightLightTag)
		light.Parent = lens
	end
end

Builders.PoiBoard = function(b: B)
	put(b, "BoardPost", Vector3.new(0.8, 6.2, 0.8), CFrame.new(0, 3.1, 0.4), PAL.WoodDark, M.Wood, true)
	local panel = put(b, "BoardPanel", Vector3.new(10, 3.2, 0.4), CFrame.new(0, 4.4, 0), PAL.SignBoard, M.Wood, true)
	local text = b.Opts.Text
	if text ~= nil and text ~= "" then
		WorldKits.Sign(panel, Enum.NormalId.Front, text, { MaxDistance = KC.SignMaxDistance })
	end
end

Builders.PaveTile = function(b: B)
	put(b, "PaveTile", Vector3.new(45, 0.12, 45), CFrame.new(0, 0.06, 0), b.Opts.Color or PAL.Paving, M.Pavement, false)
end

Builders.Fountain = function(b: B)
	vcyl(b, "FountainWall", 0, 0, 0, 1.4, 10, PAL.ConcreteLight, M.Concrete, true, true)
	vcyl(b, "FountainBed", 0, 1.4, 0, 0.1, 8.6, PAL.PavingDark, M.Pavement, false)
	vcyl(b, "FountainColumn", 0, 1.5, 0, 1.6, 1.6, PAL.ConcreteLight, M.Concrete, true)
	vcyl(b, "FountainBowl", 0, 3.1, 0, 0.5, 4, PAL.ConcreteLight, M.Concrete, true)
end

Builders.Bench = function(b: B)
	local p = put(b, "Bench", Vector3.new(6, 1.2, 1.8), CFrame.new(0, 0.6, 0), PAL.Wood, M.Wood, true)
	queueMesh(b, "Bench", "skin", { p })
end

-- Shared ───────────────────────────────────────────────────────────────────────────────────────────────────────────
local CRATE_SLOTS = {
	{ -1.3, 0, 1.3, 4 },
	{ 1.3, 0, 1.3, -6 },
	{ 0, 2.4, 1.5, 10 },
	{ -1.3, 0, 4.0, -3 },
	{ 1.3, 0, 4.0, 8 },
	{ 0, 2.4, 4.0, -10 },
}
Builders.CrateStack = function(b: B)
	local n = math.clamp(math.floor(b.Opts.Count or 3), 1, 6)
	local ammo = b.Opts.Variant == "ammo"
	local list: { BasePart } = {}
	for i = 1, n do
		local s = CRATE_SLOTS[i]
		local col = if ammo or i % 2 == 0 then PAL.CrateOlive else PAL.Crate
		table.insert(list, put(b, "Crate", Vector3.new(2.4, 2.4, 2.4), CFrame.new(s[1], s[2] + 1.2, s[3]) * rotY(s[4]), col, M.Wood, true))
	end
	queueMesh(b, "CrateStack", "skin", list)
end

local DRUM_SLOTS = { { -0.85, 0.8 }, { 0.85, 0.85 }, { 0, 2.25 }, { -1.7, 2.3 }, { 1.75, 2.3 }, { 0.05, 3.7 } }
Builders.DrumGroup = function(b: B)
	local n = math.clamp(math.floor(b.Opts.Count or 3), 1, 6)
	local cols = { PAL.DrumOlive, PAL.DrumRed, PAL.DrumBlue }
	local k0 = b.Rng:NextInteger(0, 2)
	for i = 1, n do
		local s = DRUM_SLOTS[i]
		vcyl(b, "OilDrum", s[1], 0, s[2], 2.2, 1.5, cols[(k0 + i - 1) % 3 + 1], M.Metal, true)
	end
end

Builders.SandbagLine = function(b: B)
	local n = math.clamp(math.floor((b.Opts.Length or 5) / 5 + 0.5), 1, 8)
	for i = 1, n do
		local x = (i - (n + 1) * 0.5) * 5
		local h = if i % 2 == 0 then 1.8 else 2.0
		put(b, "Sandbag", Vector3.new(5, h, 1.6), CFrame.new(x, h * 0.5, 0.9) * rotY(if i % 2 == 0 then 1.5 else -1.5), if i % 2 == 0 then PAL.SandbagLight else PAL.Sandbag, M.Sand, true)
	end
end

Builders.Jersey = function(b: B)
	put(b, "JerseyBarrier", Vector3.new(4.5, 2.2, 1.1), CFrame.new(0, 1.1, 0.55), PAL.ConcreteLight, M.Concrete, true)
end

Builders.Wreck = function(b: B)
	local v = b.Opts.Variant or "truck"
	local burnt, rust = PAL.Burnt, PAL.Rust
	local cm = M.CorrodedMetal
	if v == "car" then
		local list: { BasePart } = {}
		table.insert(list, put(b, "WreckCarBody", Vector3.new(8, 1.8, 3.8), CFrame.new(0, 0.9, 2.0), burnt, cm, true))
		table.insert(list, put(b, "WreckCarCabin", Vector3.new(3.8, 1.4, 3.4), CFrame.new(0.6, 2.5, 2.0) * rotY(3), rust, cm, true))
		table.insert(list, put(b, "WreckCarHood", Vector3.new(2.4, 0.35, 3.4), CFrame.new(-2.9, 1.95, 2.0) * rotZ(12), rust, cm, true))
		table.insert(list, put(b, "WreckDoor", Vector3.new(0.2, 1.4, 2.2), CFrame.new(0.4, 0.75, 4.3) * rotY(90) * rotZ(-20), burnt, cm, false))
		queueMesh(b, "Wreck", "collider", list)
	elseif v == "tank" then
		put(b, "WreckTankTrack", Vector3.new(9.6, 1.8, 1.3), CFrame.new(0, 0.9, 0.65), burnt, cm, true)
		put(b, "WreckTankTrack", Vector3.new(9.6, 1.8, 1.3), CFrame.new(0, 0.9, 5.95), burnt, cm, true)
		put(b, "WreckTankHull", Vector3.new(9, 1.6, 4.0), CFrame.new(0, 1.4, 3.3), rust, cm, true)
		put(b, "WreckTankTurret", Vector3.new(4, 1.5, 3.6), CFrame.new(0.5, 2.95, 3.3) * rotY(22), burnt, cm, true)
		put(b, "WreckTankBarrel", Vector3.new(6, 0.45, 0.45), CFrame.new(-4.14, 2.7, 5.17) * rotY(22) * rotZ(-5), burnt, cm, false)
	else
		put(b, "WreckTruckBed", Vector3.new(9, 1.8, 4.4), CFrame.new(2.95, 0.9, 2.2), burnt, cm, true)
		put(b, "WreckTruckCab", Vector3.new(3.6, 3.4, 4.2), CFrame.new(-3.45, 1.7, 2.2), rust, cm, true)
		put(b, "WreckTruckHood", Vector3.new(2.2, 2.0, 4.0), CFrame.new(-6.35, 1.0, 2.2), burnt, cm, true)
		put(b, "WreckTruckSide", Vector3.new(9, 1.2, 0.3), CFrame.new(2.95, 2.4, 0.15), rust, cm, true)
		put(b, "WreckTruckSide", Vector3.new(9, 1.2, 0.3), CFrame.new(2.95, 2.4, 4.25), rust, cm, true)
	end
end

-- Travel ───────────────────────────────────────────────────────────────────────────────────────────────────────────
Builders.SandbagNest = function(b: B)
	put(b, "SandbagFront", Vector3.new(6, 2, 1.4), CFrame.new(0, 1, 0.8), PAL.Sandbag, M.Sand, true)
	put(b, "SandbagSide", Vector3.new(1.4, 2, 4.2), CFrame.new(-3.7, 1, 2.9), PAL.SandbagLight, M.Sand, true)
	put(b, "SandbagSide", Vector3.new(1.4, 2, 4.2), CFrame.new(3.7, 1, 2.9), PAL.SandbagLight, M.Sand, true)
	put(b, "SandbagTop", Vector3.new(5.2, 0.8, 1.2), CFrame.new(0, 2.4, 0.8), PAL.SandbagLight, M.Sand, true)
	put(b, "NestTurret", Vector3.new(0.8, 0.7, 1.8), CFrame.new(0, 3.15, 1.2), PAL.SteelDark, M.Metal, false)
	put(b, "NestBarrel", Vector3.new(0.25, 0.25, 2.6), CFrame.new(0, 3.2, -1.0), PAL.SteelDark, M.Metal, false)
end

Builders.RoadMarker = function(b: B)
	if b.Opts.Variant == "hazard" then
		put(b, "HazardPost", Vector3.new(0.3, 3.6, 0.3), CFrame.new(0, 1.8, 0.4), PAL.SteelDark, M.Metal, true)
		put(b, "HazardSign", Vector3.new(2, 2, 0.15), CFrame.new(0, 3.4, 0.17) * rotZ(45), PAL.Hazard, M.SmoothPlastic, false)
	else
		put(b, "KmPost", Vector3.new(1, 3, 0.7), CFrame.new(0, 1.5, 0.35), PAL.ConcreteLight, M.Concrete, true)
		put(b, "KmPostCap", Vector3.new(1.05, 0.7, 0.75), CFrame.new(0, 2.75, 0.35), PAL.TarpRed, M.SmoothPlastic, false)
	end
end

Builders.DirSign = function(b: B)
	put(b, "DirSignPost", Vector3.new(0.4, 6, 0.4), CFrame.new(0, 3, 0.4), PAL.SteelDark, M.Metal, true)
	local board = put(b, "DirSignBoard", Vector3.new(4, 1.2, 0.25), CFrame.new(0.6, 5.2, 0.125), PAL.Hazard, M.SmoothPlastic, false)
	local text = b.Opts.Text
	if text ~= nil and text ~= "" then
		WorldKits.Sign(board, Enum.NormalId.Front, text, { MaxDistance = KC.SignMaxDistance })
	end
end

Builders.SandbagArc = function(b: B)
	put(b, "SandbagArc", Vector3.new(3.6, 2, 1.4), CFrame.new(-1.65, 1, 1.3) * rotY(20), PAL.Sandbag, M.Sand, true)
	put(b, "SandbagArc", Vector3.new(3.6, 2, 1.4), CFrame.new(1.65, 1, 1.3) * rotY(-20), PAL.SandbagLight, M.Sand, true)
end

Builders.Revetment = function(b: B)
	local yaws, leans = { -3, 2, -2 }, { -4, 4, -4 }
	for i, x in ipairs({ -5.4, 0, 5.4 }) do
		-- slabs leaning a little, each resting on its lower edge (centre raised by the lean's drop)
		put(b, "RevetmentWall", Vector3.new(5.2, 2, 3.4), CFrame.new(x, 1.13, 1.95) * rotY(yaws[i]) * rotX(leans[i]), if i == 2 then PAL.ConcreteLight else PAL.Concrete, M.Concrete, true)
	end
end

Builders.JettyStub = function(b: B)
	-- pivot at the landward end; the deck reaches 14 toward -Z (the water)
	put(b, "JettyDeck", Vector3.new(4, 0.5, 14), CFrame.new(0, 1.35, -7), PAL.Wood, M.WoodPlanks, true)
	vcyl(b, "JettyPile", -1.6, -1.4, -13, 3, 0.7, PAL.WoodDark, M.Wood, false)
	vcyl(b, "JettyPile", 1.6, -1.4, -13, 3, 0.7, PAL.WoodDark, M.Wood, false)
end

Builders.BargeWreck = function(b: B)
	-- pivot at the bow ramp on the bank; the hull lies toward -Z (the water)
	put(b, "BargeHull", Vector3.new(9, 2.6, 20), CFrame.new(0, 1.3, -10) * rotZ(6), PAL.Rust, M.CorrodedMetal, true, true)
	put(b, "BargeCabin", Vector3.new(5, 3, 4.5), CFrame.new(0.4, 4.1, -16.5) * rotZ(6), PAL.Burnt, M.CorrodedMetal, true)
	put(b, "BargeRoof", Vector3.new(5.8, 0.4, 5.2), CFrame.new(0.6, 5.8, -16.5) * rotZ(6), PAL.Rust, M.CorrodedMetal, false)
	put(b, "BargeRampHull", Vector3.new(8, 0.6, 4), CFrame.new(0, 1.0, 1.4) * rotX(25), PAL.Rust, M.CorrodedMetal, true)
	put(b, "BargeMast", Vector3.new(0.5, 6, 0.5), CFrame.new(3, 5.3, -12) * rotZ(6), PAL.SteelDark, M.Metal, false)
end

Builders.BeachedHull = function(b: B)
	-- pivot at the bow on the beach; the hull lies toward -Z (the water), rolled onto its side
	put(b, "BoatHull", Vector3.new(6, 2.4, 13), CFrame.new(0, 1.5, -6.5) * rotZ(18), PAL.Hull, M.WoodPlanks, true, true)
	put(b, "BoatHullBow", Vector3.new(4, 2, 3), CFrame.new(0, 1.2, 1.2) * rotZ(18), PAL.Hull, M.WoodPlanks, true)
	put(b, "BoatHullStern", Vector3.new(5.4, 2.2, 0.6), CFrame.new(0, 1.4, -13.2) * rotZ(18), PAL.HullLight, M.WoodPlanks, true)
	put(b, "BoatCabin", Vector3.new(3, 1.8, 3.6), CFrame.new(0.8, 2.6, -8) * rotZ(18), PAL.HullLight, M.WoodPlanks, true)
end

-- Natural (never collide; names start with a Hygiene natural prefix) ───────────────────────────────────────────────
Builders.Joshua = function(b: B)
	local s = scaleOf(b)
	put(b, "JoshuaTrunk", Vector3.new(1.1 * s, 6.5 * s, 1.1 * s), CFrame.new(0, 3.25 * s, 0) * rotZ(6), PAL.JoshuaTrunk, M.Wood, false)
	put(b, "JoshuaCrown", Vector3.new(4.4 * s, 1.6 * s, 4.4 * s), CFrame.new(0.35 * s, 7.0 * s, 0) * rotY(20), PAL.JoshuaLeaf, M.Grass, false)
end

Builders.Saguaro = function(b: B)
	local s = scaleOf(b)
	vcyl(b, "SaguaroTrunk", 0, 0, 0, 9.5 * s, 1.4 * s, PAL.Cactus, M.SmoothPlastic, false)
	put(b, "SaguaroArm", Vector3.new(4.6 * s, 0.9 * s, 0.9 * s), CFrame.new(1.62 * s, 6.08 * s, 0) * rotZ(55), PAL.CactusLight, M.SmoothPlastic, false, false, Enum.PartType.Cylinder)
end

Builders.BarrelCactus = function(b: B)
	local s = scaleOf(b)
	vcyl(b, "BarrelCactus", 0, 0, 0, 1.8 * s, 2.2 * s, PAL.CactusLight, M.SmoothPlastic, false)
end

Builders.DeadTree = function(b: B)
	local s = scaleOf(b)
	local p = put(b, "DeadTree", Vector3.new(1.1 * s, 11 * s, 1.1 * s), CFrame.new(0.25 * s, 5.5 * s, 0) * rotZ(-5), PAL.DeadWood, M.Wood, false)
	queueMesh(b, "DeadTree", "each", { p })
end

Builders.Stump = function(b: B)
	local s = scaleOf(b)
	local p = vcyl(b, "Stump", 0, 0, 0, 1.6 * s, 2.4 * s, PAL.JoshuaTrunk, M.Wood, false)
	queueMesh(b, "Stump", "each", { p })
end

Builders.Log = function(b: B)
	local s = scaleOf(b)
	local p = put(b, "FallenLog", Vector3.new(9 * s, 1.5 * s, 1.5 * s), CFrame.new(0, 0.75 * s, 0) * ZCYL, PAL.DeadWood, M.Wood, false, false, Enum.PartType.Cylinder)
	queueMesh(b, "Log", "each", { p })
end

Builders.Reeds = function(b: B)
	local s = scaleOf(b)
	local a = put(b, "ReedsClump", Vector3.new(1.5 * s, 3.2 * s, 1.5 * s), CFrame.new(-0.8 * s, 1.6 * s, 0) * rotY(20), PAL.Reed, M.Grass, false)
	local c = put(b, "ReedsClump", Vector3.new(1.2 * s, 2.4 * s, 1.2 * s), CFrame.new(1.0 * s, 1.2 * s, 0.6 * s) * rotY(-15), PAL.DuneGrass, M.Grass, false)
	queueMesh(b, "Reeds", "each", { a, c })
end

Builders.DuneGrass = function(b: B)
	local s = scaleOf(b)
	local a = put(b, "DuneGrassTuft", Vector3.new(2.6 * s, 1.1 * s, 2.6 * s), CFrame.new(-0.9 * s, 0.55 * s, 0), PAL.DuneGrass, M.Grass, false)
	local c = put(b, "DuneGrassTuft", Vector3.new(2.0 * s, 0.8 * s, 2.0 * s), CFrame.new(1.2 * s, 0.4 * s, 0.8 * s) * rotY(30), PAL.Reed, M.Grass, false)
	queueMesh(b, "DuneGrass", "each", { a, c })
end

Builders.Driftwood = function(b: B)
	local s = scaleOf(b)
	local a = put(b, "DriftwoodLog", Vector3.new(7 * s, 0.9 * s, 0.9 * s), CFrame.new(0, 0.45 * s, 0) * rotY(10), PAL.Driftwood, M.Wood, false, false, Enum.PartType.Cylinder)
	local c = put(b, "DriftwoodLog", Vector3.new(4.5 * s, 0.7 * s, 0.7 * s), CFrame.new(0.6 * s, 0.35 * s, 1.2 * s) * rotY(-35), PAL.DeadWood, M.Wood, false, false, Enum.PartType.Cylinder)
	queueMesh(b, "Driftwood", "each", { a, c })
end

-- ── Add / Finish / Place ──────────────────────────────────────────────────────────────────────────────────────────
local warnedStep2: { [string]: boolean } = {}

local function seedOf(cf: CFrame, opts: KitOpts): number
	if opts.Seed ~= nil then
		return opts.Seed
	end
	local p = cf.Position
	return math.floor(p.X * 7.31 + p.Z * 13.7 + 104729) % 2147483647
end

function WorldKits.Add(cluster: Model, kitId: string, cf: CFrame, opts: KitOpts?): number
	local s = WorldKits.Specs[kitId]
	local builder = Builders[kitId]
	if s == nil or builder == nil then
		if not warnedStep2[kitId] then
			warnedStep2[kitId] = true
			warn(if s == nil then "[WorldKits] unknown kit " .. kitId else "[WorldKits] kit " .. kitId .. " is a later-POI kit (not built in W3 step 1)")
		end
		return 0
	end
	local o: KitOpts = opts or {}
	local b: B = { Cluster = cluster, CF = cf, Opts = o, Parts = {}, Rng = WorldKits.Rng(seedOf(cf, o)), Overlays = {} }
	builder(b)
	if #b.Overlays > 0 then
		local list = pendingMesh[cluster]
		if list == nil then
			list = {}
			pendingMesh[cluster] = list
		end
		for _, ov in ipairs(b.Overlays) do
			table.insert(list :: { Overlay }, ov)
		end
	end
	return #b.Parts
end

-- ── Mesh overlays (deferred; LOOK's VisualAssetService.CloneKitMesh) ──────────────────────────────────────────────
local vasCache: any = nil
local function getVAS(): any
	if vasCache ~= nil then
		return if vasCache == false then nil else vasCache
	end
	local ok, mod = pcall(function(): any
		local services = script.Parent.Parent:FindFirstChild("Services")
		local m = services and services:FindFirstChild("VisualAssetService")
		if m and m:IsA("ModuleScript") then
			return (require :: any)(m)
		end
		return nil
	end)
	vasCache = if ok and mod ~= nil and type((mod :: any).CloneKitMesh) == "function" then mod else false
	return if vasCache == false then nil else vasCache
end

-- AABB of parts in the axes of `frame` → (box CFrame with frame's rotation, size)
local function boxIn(frame: CFrame, parts: { BasePart }): (CFrame, Vector3)
	local x0, x1, y0, y1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
	for _, p in ipairs(parts) do
		local rel = frame:ToObjectSpace(p.CFrame)
		local s = p.Size
		local r, u, l = rel.RightVector * s.X * 0.5, rel.UpVector * s.Y * 0.5, rel.LookVector * s.Z * 0.5
		local hx = math.abs(r.X) + math.abs(u.X) + math.abs(l.X)
		local hy = math.abs(r.Y) + math.abs(u.Y) + math.abs(l.Y)
		local hz = math.abs(r.Z) + math.abs(u.Z) + math.abs(l.Z)
		local c = rel.Position
		x0, x1 = math.min(x0, c.X - hx), math.max(x1, c.X + hx)
		y0, y1 = math.min(y0, c.Y - hy), math.max(y1, c.Y + hy)
		z0, z1 = math.min(z0, c.Z - hz), math.max(z1, c.Z + hz)
	end
	return frame * CFrame.new((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5), Vector3.new(x1 - x0, y1 - y0, z1 - z0)
end

type Skin = { MeshId: string, TextureId: string, MeshSize: Vector3 }
local skinCache: { [string]: Skin } = {}
local skinMiss: { [string]: boolean } = {}

-- one CloneKitMesh call; nil unless it returned a BasePart (a failed load, the sim, an unwired key)
local function cloneMesh(vas: any, key: string): BasePart?
	local ok, res = pcall(vas.CloneKitMesh, key)
	if ok and typeof(res) == "Instance" and res:IsA("BasePart") then
		return res
	end
	return nil
end

local function gone(inst: Instance): boolean
	return inst.Parent == nil
end

local function applyOverlay(cluster: Model, ov: Overlay, vas: any)
	local alive: { BasePart } = {}
	for _, p in ipairs(ov.Parts) do
		if p.Parent ~= nil and p:IsDescendantOf(cluster) then
			table.insert(alive, p)
		end
	end
	if #alive == 0 or cluster.Parent == nil then
		return
	end
	if ov.Mode == "skin" then
		if skinMiss[ov.Key] then
			return
		end
		local sk: Skin? = skinCache[ov.Key]
		if sk == nil then
			local mp = cloneMesh(vas, ov.Key)
			if mp and mp:IsA("MeshPart") then
				local m = mp :: MeshPart
				local fresh: Skin = { MeshId = m.MeshId, TextureId = m.TextureID, MeshSize = m.MeshSize }
				skinCache[ov.Key] = fresh
				sk = fresh
			else
				skinMiss[ov.Key] = true
			end
			if mp then
				mp:Destroy()
			end
		end
		if sk == nil then
			return
		end
		local ms = sk.MeshSize
		if ms.X <= 0 or ms.Y <= 0 or ms.Z <= 0 then
			return
		end
		for _, p in ipairs(alive) do
			if p:FindFirstChildOfClass("SpecialMesh") == nil then
				local sm = Instance.new("SpecialMesh")
				sm.MeshType = Enum.MeshType.FileMesh
				sm.MeshId = sk.MeshId
				sm.TextureId = sk.TextureId
				sm.Scale = Vector3.new(p.Size.X / ms.X, p.Size.Y / ms.Y, p.Size.Z / ms.Z)
				sm.Parent = p -- the Part keeps its box collision: net 0 parts
			end
		end
		return
	end
	if ov.Mode == "each" then
		for _, p in ipairs(alive) do
			local m = cloneMesh(vas, ov.Key)
			if m == nil then
				return
			end
			if gone(p) or gone(cluster) then
				m:Destroy()
				return
			end
			local frame = ov.Frame - ov.Frame.Position + p.Position
			local boxCf, size = boxIn(frame, { p })
			m.CFrame = boxCf
			m.Size = size
			m.Name = p.Name
			m.Parent = p.Parent
			p:Destroy() -- net 0 parts
		end
		return
	end
	if ov.Mode == "collider" and #alive >= 2 then
		local m = cloneMesh(vas, ov.Key)
		if m == nil then
			return
		end
		if gone(cluster) then
			m:Destroy()
			return
		end
		local boxCf, size = boxIn(ov.Frame, alive)
		local biggest = alive[1]
		for _, p in ipairs(alive) do
			if p.Size.X * p.Size.Y * p.Size.Z > biggest.Size.X * biggest.Size.Y * biggest.Size.Z then
				biggest = p
			end
		end
		for _, p in ipairs(alive) do
			if p ~= biggest then
				p:Destroy()
			end
		end
		biggest.CFrame = boxCf
		biggest.Size = size
		biggest.Transparency = 1
		biggest.CanCollide = true
		biggest.CanQuery = true
		biggest.CastShadow = false
		biggest.Name = "WreckCollider"
		m.CFrame = boxCf
		m.Size = size
		m.Name = ov.Key .. "Mesh"
		m.Parent = cluster -- 1 collider + 1 mesh replace n >= 2 parts
	end
end

local function scheduleOverlays(cluster: Model, list: { Overlay })
	local cap = KC.MeshOverlays
	local take: { Overlay } = {}
	for _, ov in ipairs(list) do
		if overlaysQueued >= cap then
			break
		end
		overlaysQueued += 1
		table.insert(take, ov)
	end
	if #take == 0 then
		return
	end
	task.defer(function()
		local vas = getVAS()
		if vas == nil then
			return
		end
		for _, ov in ipairs(take) do
			local ok, err = pcall(function(): string?
				applyOverlay(cluster, ov, vas)
				return nil
			end)
			if not ok then
				warn("[WorldKits] mesh overlay " .. ov.Key .. " failed: " .. tostring(err))
			end
		end
	end)
end

local function closeCluster(cluster: Model)
	openClusters[cluster] = nil
	pendingSigns[cluster] = nil
	pendingMesh[cluster] = nil
end

function WorldKits.Discard(cluster: Model)
	closeCluster(cluster)
	cluster:Destroy()
end

function WorldKits.Finish(cluster: Model, parent: Instance): ClusterInfo
	local parts, lights, signs = 0, 0, 0
	local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
	for _, d in ipairs(cluster:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
			local cf, s = d.CFrame, d.Size
			local r = cf.RightVector * s.X * 0.5
			local u = cf.UpVector * s.Y * 0.5
			local l = cf.LookVector * s.Z * 0.5
			local hx = math.abs(r.X) + math.abs(u.X) + math.abs(l.X)
			local hz = math.abs(r.Z) + math.abs(u.Z) + math.abs(l.Z)
			local p = cf.Position
			x0, x1 = math.min(x0, p.X - hx), math.max(x1, p.X + hx)
			z0, z1 = math.min(z0, p.Z - hz), math.max(z1, p.Z + hz)
		elseif d:IsA("Light") then
			lights += 1
		elseif d:IsA("SurfaceGui") then
			signs += 1
		end
	end
	local span = if parts > 0 then math.max(x1 - x0, z1 - z0) else 0
	local reason: string? = nil
	if parts == 0 then
		reason = "no parts"
	elseif span > MAX_SPAN then
		reason = string.format("span %.0f > %d", span, MAX_SPAN)
	end
	local overlays = pendingMesh[cluster]
	closeCluster(cluster)
	if reason then
		cluster:Destroy()
		return { Ok = false, Parts = 0, Span = span, Lights = 0, Signs = 0, Reason = reason }
	end
	cluster.Parent = parent
	if overlays and #overlays > 0 then
		scheduleOverlays(cluster, overlays)
	end
	return { Ok = true, Parts = parts, Span = span, Lights = lights, Signs = signs, Reason = nil }
end

function WorldKits.Place(kitId: string, cf: CFrame, parent: Instance, opts: PlaceOpts): Model?
	local cluster = WorldKits.NewCluster(opts.Name, opts.Cluster)
	WorldKits.Add(cluster, kitId, cf, opts.Kit)
	local info = WorldKits.Finish(cluster, parent)
	return if info.Ok then cluster else nil
end

-- ── Footprint (measured from a throw-away build; cached) ──────────────────────────────────────────────────────────
local footCache: { [string]: Footprint } = {}

function WorldKits.Footprint(kitId: string, opts: KitOpts?): Footprint?
	local o: KitOpts = opts or {}
	local key = table.concat({ kitId, tostring(o.Variant), tostring(o.Count), tostring(o.Length), tostring(o.Scale) }, "|")
	local hit = footCache[key]
	if hit then
		return hit
	end
	if Builders[kitId] == nil then
		return nil
	end
	local tmp = Instance.new("Model")
	local frame = CFrame.new(0, GROUND_Y, 0)
	local b: B = { Cluster = tmp, CF = frame, Opts = { Variant = o.Variant, Count = o.Count, Length = o.Length, Scale = o.Scale, Light = false, Mesh = false, Seed = 1 }, Parts = {}, Rng = WorldKits.Rng(1), Overlays = {} }
	Builders[kitId](b)
	local fp: Footprint = { X0 = math.huge, X1 = -math.huge, Z0 = math.huge, Z1 = -math.huge, Top = 0, CollideZ0 = math.huge, VisibleZ0 = math.huge, Parts = #b.Parts }
	for _, p in ipairs(b.Parts) do
		local boxCf, size = boxIn(frame, { p })
		local c = boxCf.Position - frame.Position
		local px0, px1, pz0, pz1 = c.X - size.X * 0.5, c.X + size.X * 0.5, c.Z - size.Z * 0.5, c.Z + size.Z * 0.5
		local top = c.Y + size.Y * 0.5
		fp.X0, fp.X1, fp.Z0, fp.Z1 = math.min(fp.X0, px0), math.max(fp.X1, px1), math.min(fp.Z0, pz0), math.max(fp.Z1, pz1)
		fp.Top = math.max(fp.Top, top)
		if p.CanCollide then
			fp.CollideZ0 = math.min(fp.CollideZ0, pz0)
		end
		if p.Transparency < 0.99 and top > 0.3 then
			fp.VisibleZ0 = math.min(fp.VisibleZ0, pz0)
		end
	end
	tmp:Destroy()
	footCache[key] = fp
	return fp
end

-- ── Terrain (0 parts) ─────────────────────────────────────────────────────────────────────────────────────────────
local terrainHandle: any = nil
local terrainLog: { Prim } = {}

function WorldKits.SetTerrain(handle: any?)
	terrainHandle = handle
end

function WorldKits.TerrainLog(): { Prim }
	return terrainLog
end

function WorldKits.ResetTerrainLog()
	terrainLog = {}
end

-- the handle every Rock fill goes through (tests pass a recorder)
function WorldKits.TerrainHandle(): any
	return terrainHandle or Workspace.Terrain
end

type RockDef = { Radius: number, Count: { number }, R: { number } }

function WorldKits.Rock(pos: Vector3, kind: string, rng: Rng, opts: { Radius: number?, Material: Enum.Material?, Count: number? }?): { Prim }
	local def = (KC.Rock :: any)[kind] :: RockDef?
	if def == nil then
		warn("[WorldKits] unknown rock kind " .. kind)
		return {}
	end
	local o: { Radius: number?, Material: Enum.Material?, Count: number? } = opts or {}
	local run: string = kind
	local outer = math.max(2, o.Radius or def.Radius)
	local prims: { Prim } = {}
	local function ball(x: number, z: number, r: number, mat: Enum.Material)
		local y = GROUND_Y - 0.35 * r -- partly buried
		table.insert(prims, { Op = "Ball", CFrame = CFrame.new(x, y, z), Radius = r, Material = mat, Tag = "rock", Run = run, Top = y + r })
	end
	-- a random point whose disc of radius r stays inside the group's outer radius
	local function spot(r: number, spread: number): (number, number)
		local room = math.max(0, math.min(spread, outer - r))
		local a = rng:NextNumber(0, math.pi * 2)
		local d = room * math.sqrt(rng:NextNumber())
		return pos.X + math.cos(a) * d, pos.Z + math.sin(a) * d
	end
	local n = o.Count or rng:NextInteger(def.Count[1], def.Count[2])
	if kind == "scorch" then
		local w, d = outer * 1.6, outer * 1.1
		local yaw = rng:NextNumber(0, 180)
		-- the rotated block's corners stay within the outer radius: half-diagonal of (w, d) = outer * 0.97
		table.insert(prims, {
			Op = "Block",
			CFrame = CFrame.new(pos.X, GROUND_Y, pos.Z) * rotY(yaw),
			Size = Vector3.new(w, 1, d),
			Material = o.Material or M.Basalt,
			Tag = "rock",
			Run = run,
			Top = GROUND_Y + 0.5,
		})
	elseif kind == "outcrop" then
		local r0 = math.min(rng:NextNumber(math.max(def.R[1], 6), def.R[2]), outer * 0.75)
		local x, z = spot(r0, outer * 0.15)
		ball(x, z, r0, o.Material or M.Sandstone)
		for _ = 2, n do
			local r = math.min(rng:NextNumber(def.R[1], math.max(def.R[1], r0 * 0.7)), outer * 0.6)
			local sx, sz = spot(r, outer)
			ball(sx, sz, r, M.Rock)
		end
	else
		local mats = if kind == "rubble" then { M.Ground, M.Rock } else { o.Material or M.Rock, M.Rock }
		for i = 1, n do
			local r = math.min(rng:NextNumber(def.R[1], def.R[2]), outer * 0.6)
			local x, z = spot(r, outer)
			ball(x, z, r, mats[(i - 1) % #mats + 1])
		end
	end
	local handle = WorldKits.TerrainHandle()
	for _, p in ipairs(prims) do
		local ok, err = pcall(function()
			if p.Op == "Ball" then
				handle:FillBall(p.CFrame.Position, p.Radius, p.Material)
			else
				handle:FillBlock(p.CFrame, p.Size, p.Material)
			end
		end)
		if not ok then
			warn("[WorldKits] terrain fill failed: " .. tostring(err))
		end
		table.insert(terrainLog, p)
	end
	return prims
end

return WorldKits
