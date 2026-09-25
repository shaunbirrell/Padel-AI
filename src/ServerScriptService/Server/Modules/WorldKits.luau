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
	                                                  default opts, Parts x units with Count / Length (<= PartsMax),
	                                                  Specs[kit].Variants[v] with Variant v;
	                                                  0 = unknown kit or a reserved kit with no builder (warned once)
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
	A piece whose ref has Yaw = +-90 / 270 (attribute WE_KitYaw from CloneKitMesh; Driftwood, CarWreck) is turned by it
	and takes the box with X and Z swapped, so its long axis lies on the kit's. A key VisualAssetService.IsKitMeshWired
	calls unwired (config id 0) takes no MeshOverlays slot, and one wired key takes at most ceil(cap / wired keys used
	by Specs) slots, so the kits built first (Town crates, reeds, wrecks) cannot use up the cap before the travel
	dressing's logs, driftwood, dead trees, stumps and grass (headless world sim: 40 slots went to 3 keys before).
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

-- Class: "manmade" | "natural" | "marking" | "anchor" (W3 step 2: the invisible ActivityHost) | "infra" (W3 step 2: flat
-- strips built outside the clusters, exempt from H10). Solid: its cover parts >= 1.5 tall collide + query (H4).
-- Size: AABB size at yaw 0 (X across, Y up from the floor, Z depth; the kit's front faces local -Z), default opts.
-- Parts: exact count at default opts (per unit for Count / Length kits). Step: 1 = needed in W3 step 1 (Town + travel
-- dressing), 2 = later POIs. Use: who places it in step 1 ("Town", "Travel", "Town+Travel", "POI" = later).
-- Variants (W3 step 2 contract): exact part count per Variant at otherwise default opts (per unit for Count / Length
-- kits); the lane K kit harness checks Footprint(kit, { Variant = v }).Parts against it.
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
	Variants: { [string]: number }?,
}

export type KitOpts = {
	Variant: string?, -- Wreck: "car" | "truck" | "tank" | "gun"; RoadMarker: "km" | "hazard"; AdobeHouse: "tall" | "wide" | "shop"; CrateStack: "ammo"
	-- W3 step 2: WaterTower "broken"; Fountain "well"; CompoundWall "gate"; DrumGroup "fire"; PlaneWreck "nose" | "mid" |
	-- "tail"; HoldPad "pond"; PipeRun "rack" (Specs[kit].Variants gives each one's part count)
	Count: number?, -- CrateStack / DrumGroup units
	Length: number?, -- SandbagLine studs (1 part per 5); CompoundWall studs (1 part per 16)
	Scale: number?, -- natural kits (0.7 .. 1.3; >= 2 sizes per natural cluster); W3 step 2 also FuelTank, GantryCrane
	Text: string?, -- PoiBoard / DirSign: SurfaceGui text, only when the world sign budget allows
	Color: Color3?, -- tint override (tarps, walls)
	Light: boolean?, -- StreetLamp: build its night PointLight (default true)
	Mesh: boolean?, -- try the Roblox-owned mesh overlay when Specs[kit].Mesh is set (default true)
	Seed: number?, -- per-instance jitter (default: from the pivot position)
	-- Town v2 (TownBlock only; see its builder)
	Width: number?, -- front width, local X (default 20)
	Depth: number?, -- local Z (default 16)
	Storeys: number?, -- 1 .. 6 (default 2), 7 studs each; 5+ = a concrete tower block
	Roof: string?, -- "+"-joined: "bare", "tank", "tanks", "hut", "mast", "dish"
	Lantern: boolean?, -- a soft night lamp over the door (1 part + 1 WE_NightLight PointLight)
	-- W3 step 2 (also Width: Hangar, default 28; Length: WireFence per 16, PipeRun per 40, Runway total)
	R: number?, -- HoldPad radius (WorldConfig.Kits.HoldPad: default 10, 3 .. 24)
	Taxiway: { number }?, -- Runway: { X0, X1, Z0, Z1 } world rect of the taxiway strip
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

type SpecExtra = { Lights: number?, Signs: number?, Mesh: string?, Water: boolean?, Unit: string?, Variants: { [string]: number }? }

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
		Variants = e.Variants,
	}
end

-- ── Catalogue (spec §4.5; part caps in brackets there). Sizes = measured AABB of the default build ─────────────────
WorldKits.Specs = {
	-- Step 1 — Crossroads Town (B1 places)
	MarketStall = spec(7, 7, Vector3.new(10.6, 7.5, 8.9), "manmade", true, 1, "Town"), -- tarp roof (cloth), counter, 2 crates on the table, posts, back wall
	WaterTower = spec(9, 9, Vector3.new(13, 43.2, 13), "manmade", true, 1, "Town", { Variants = { broken = 6 } }), -- landmark: top >= 42; "broken" (W3 step 2, the Ruins): 3 legs, the tank on the ground, top 30
	ClockTower = spec(8, 8, Vector3.new(10, 40, 10), "manmade", true, 1, "Town"), -- landmark: top >= 38
	AdobeHouse = spec(5, 5, Vector3.new(13.2, 8, 10.2), "manmade", true, 1, "Town"), -- kitAdobeBuilding without the Neon accent ("tall": 2 storeys)
	RuinedHouse = spec(5, 5, Vector3.new(14, 7, 11.4), "manmade", true, 1, "Town"), -- kitRuinLandmark trimmed: broken walls + fallen roof slab
	CompoundWall = spec(1, 4, Vector3.new(16, 3, 1.2), "manmade", true, 1, "Town", { Unit = "16 studs", Variants = { gate = 1 } }), -- chest-high adobe wall (cover); "gate" (W3 step 2): one steel yard gate part "HeistGate" per 16 (WE_RuntimeDoor)
	Checkpoint = spec(8, 8, Vector3.new(36.3, 12.9, 11.9), "manmade", true, 1, "Town"), -- v2: booth on the shoulder (7 tall: taller than an avatar), raised CheckpointArm, sandbags >= 13 off the line, painted board
	StreetLamp = spec(3, 3, Vector3.new(1.2, 12, 3.7), "manmade", false, 1, "Town", { Lights = 1 }), -- pole, arm, SmoothPlastic lens + night PointLight
	PoiBoard = spec(2, 2, Vector3.new(10, 6.2, 1), "manmade", false, 1, "Town", { Signs = 1 }), -- post + painted board (+1 SurfaceGui with Text)
	PaveTile = spec(1, 1, Vector3.new(45, 0.12, 45), "marking", false, 1, "Town"), -- Town Square paving, top <= 0.75, no collide
	Fountain = spec(4, 4, Vector3.new(10, 3.6, 10), "manmade", true, 1, "Town", { Variants = { well = 4 } }), -- dry fountain; "well" (W3 step 2): ring wall + 2 posts + beam
	Bench = spec(1, 1, Vector3.new(6, 1.2, 1.8), "manmade", false, 1, "Town", { Mesh = "Bench" }),
	-- Town v2 (densify): 1–6 storey blocks from a few big parts (default = 20 x 16, 2 storeys: body, parapet, 1 window
	-- strip, door); parts grow with Storeys / Variant / Roof / Lantern (Footprint gives the exact count)
	TownBlock = spec(4, 31, Vector3.new(20.8, 15.2, 16.8), "manmade", true, 1, "Town"), -- max: 6 storeys, every face and roof option
	-- W3 step 2 Variant tokens (lane K): "roller" = one vehicle-wide roller door instead of the door (same count as the
	-- door; "shop" wins if both), "metal" = corrugated-metal walls and trim (colour / material only, +0 parts), "hall" =
	-- a walk-in hall (5 wall parts: back, 2 sides, 2 front piers round a centred opening min(10, Width - 8) wide and full
	-- height, + 1 roof slab with the parapet, + 1 upper-front window strip when Storeys >= 2; no door; roof details as
	-- usual): exactly 7 parts at Storeys 2 with no Roof / Lantern (the Empire Bank, lane BK, counts on it)
	RadioMast = spec(5, 5, Vector3.new(6, 90, 6), "manmade", true, 1, "Town+POI"), -- lattice mast, 90 tall (Town landmark; later the Signal Station)
	-- Step 1 — shared by the Town and the travel dressing
	CrateStack = spec(3, 6, Vector3.new(5.2, 4.8, 2.9), "manmade", true, 1, "Town+Travel", { Mesh = "CrateWood", Unit = "crate" }),
	DrumGroup = spec(3, 6, Vector3.new(3.2, 2.2, 3.0), "manmade", true, 1, "Town+Travel", { Unit = "drum", Variants = { fire = 1 } }), -- "fire" (W3 step 2, camps): burn barrels, no light
	SandbagLine = spec(1, 8, Vector3.new(5.05, 2, 1.7), "manmade", true, 1, "Town+Travel", { Unit = "5 studs" }),
	Jersey = spec(1, 1, Vector3.new(4.5, 2.2, 1.1), "manmade", true, 1, "Town+Travel"),
	Wreck = spec(5, 5, Vector3.new(14.9, 3.4, 4.4), "manmade", true, 1, "Town+Travel", { Mesh = "CarWreck", Variants = { car = 4, truck = 5, tank = 5, gun = 3 } }), -- long axis along X; "gun" (W3 step 2): a wrecked field gun
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
	Driftwood = spec(2, 2, Vector3.new(7.05, 0.9, 3.8), "natural", false, 1, "Travel", { Mesh = "Driftwood" }), -- own key (sharing "Log" squashed the Z-long log piece onto this X-long box)
	-- Step 2 — later POIs (W3 step 2, spec w3s2 §6 lane K; rows = the geometry plan's kit list: exact parts at default
	-- opts, measured AABB of the default build at yaw 0). Reserved rows (no builder: TrenchRun, Bollard, GaragePadV2,
	-- PontoonV2, AmmoShed, Campfire) make Add warn once and return 0; no layout uses them.
	ContainerStack = spec(3, 6, Vector3.new(14.8, 15, 18), "manmade", true, 2, "POI", { Unit = "container" }), -- Count 1 .. 6 (default 3: 2 side by side + 1 on top); 4 .. 6 add a second row behind
	GantryCrane = spec(7, 7, Vector3.new(24, 55, 53), "manmade", true, 2, "POI", { Water = true }), -- landmark; the boom reaches 40 toward -Z (the water); Scale (RigA / RigB 0.6)
	FuelTank = spec(3, 3, Vector3.new(12.4, 11, 12.4), "manmade", true, 2, "POI"), -- Scale 0.5 .. 1.6
	FlareStack = spec(3, 3, Vector3.new(6, 45, 6), "manmade", true, 2, "POI"), -- landmark; the flame is a painted part (never Neon, no light)
	RadarDome = spec(5, 5, Vector3.new(13, 26, 13), "manmade", true, 2, "POI"), -- landmark
	PlaneWreck = spec(4, 4, Vector3.new(34.2, 10, 22), "manmade", true, 2, "POI", { Variants = { nose = 3, mid = 4, tail = 2 } }), -- the Crash Site in 3 pieces (default "mid": fuselage, 2 wings, engine): nose 12 x 10 x 26, tail 7.3 x 12 x 18
	HeliWreck = spec(5, 5, Vector3.new(9.7, 5.7, 24), "manmade", true, 2, "POI"), -- body rolled on its side, tail boom toward +Z, rotor blade + skid in the sand
	TankTrap = spec(2, 2, Vector3.new(4, 3, 4), "manmade", true, 2, "POI"), -- 2 crossed steel beams
	TrenchRun = spec(6, 18, Vector3.new(4, 2, 20), "manmade", true, 2, "POI", { Unit = "20 studs" }), -- reserved (no layout uses it)
	Crusher = spec(5, 5, Vector3.new(13, 14, 36), "manmade", true, 2, "POI"), -- landmark (the Quarry); the conveyor runs toward +Z
	Bollard = spec(1, 1, Vector3.new(1, 1.5, 1), "manmade", false, 2, "POI"), -- reserved
	GaragePadV2 = spec(3, 3, Vector3.new(20, 1.2, 20), "manmade", false, 2, "POI"), -- reserved
	PontoonV2 = spec(2, 2, Vector3.new(16, 1.2, 16), "manmade", false, 2, "POI", { Water = true }), -- reserved
	Watchtower = spec(8, 8, Vector3.new(9, 23, 9), "manmade", true, 2, "POI"), -- deck top WorldConfig.Kits.WatchtowerDeckY (14) above the floor: tower posts stand on it; ladder (TrussPart) at the back; roof 8.5 above the deck, no collision (owner feedback #29)
	Bunker = spec(3, 3, Vector3.new(18, 7, 11.5), "manmade", true, 2, "POI"), -- pivot at the front; its blast door part is "BunkerDoor" (WE_RuntimeDoor)
	Hangar = spec(5, 5, Vector3.new(29.2, 13.5, 25), "manmade", true, 2, "POI"), -- open front (-Z), 12.9 clear inside (11.5 under the lintel); Width (inside, default 28, 16 .. 48)
	AmmoShed = spec(5, 5, Vector3.new(12, 6, 10), "manmade", true, 2, "POI"), -- reserved
	WireFence = spec(1, 4, Vector3.new(16, 3, 0.4), "manmade", true, 2, "POI", { Unit = "16 studs" }), -- Length 16 .. 64; see-through panels that collide (not cover: "Wire" is a soft keyword)
	Tent = spec(3, 3, Vector3.new(7.8, 4.9, 9), "manmade", true, 2, "POI"), -- A-frame canvas (2 panels) + front pole
	Campfire = spec(3, 3, Vector3.new(4, 1, 4), "manmade", false, 2, "POI"), -- reserved (camps use DrumGroup "fire")
	Palm = spec(3, 3, Vector3.new(10, 13, 10), "natural", false, 2, "POI"), -- trunk + 2 crossed fronds; Scale
	Pumpjack = spec(5, 5, Vector3.new(4, 9.9, 14), "manmade", true, 2, "POI"), -- the Oil Field pumps (sabotage anchors sit on them); horsehead toward -Z
	Terminal = spec(2, 2, Vector3.new(3, 3.2, 2), "manmade", true, 2, "POI"), -- console desk + screen (never Neon): uplink / hack anchors
	HoldPad = spec(1, 1, Vector3.new(20, 0.13, 20), "marking", false, 2, "POI", { Variants = { pond = 1 } }), -- one flat painted disc, radius R (WorldConfig.Kits.HoldPad), no collision, top 0.63 world; "pond" = the Oasis pond (Glass, not WE_Water)
	PipeRun = spec(1, 9, Vector3.new(40, 1.8, 1.8), "manmade", true, 2, "POI", { Unit = "40 studs", Variants = { rack = 3 } }), -- Length 40 .. 120 (a cluster must stay <= 64 wide: the layouts use 40); "rack" = 3 per 40 (pipe on 2 posts, top 4.5, 2 deep)
	ActivityHost = spec(1, 1, Vector3.new(1, 1, 1), "anchor", false, 2, "POI"), -- invisible, CanCollide / CanQuery / CanTouch off, no overlay: hosts a POI layout's activity anchors (WorldConfig.Activity.HostKit)
	Runway = spec(5, 5, Vector3.new(500, 0.12, 40), "infra", false, 2, "POI"), -- InfraRow only: Length (default 500) + Taxiway; flat, no collision, top <= 0.62 world, under POI_<Id>.Infra
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
local overlaysByKey: { [string]: number } = {} -- slots spent per mesh key (owner list: fair share of the cap)
local keyShare: number? = nil -- most slots one wired key may take (ceil(cap / wired keys); set on first use)

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
	if b.Opts.Variant == "broken" then
		-- W3 step 2 (the Ruins): 3 legs left standing (snapped at 30 / 27 / 24), the NW leg fallen along the front,
		-- the tank and its roof lying on the ground where the leg was (6 parts, top 30, x -10 .. 10, z -8 .. 12)
		for _, c in ipairs({ { 5, -5, 30 }, { -5, -5, 27 }, { 5, 5, 24 } }) do
			put(b, "TowerLeg", Vector3.new(1, c[3], 1), CFrame.new(c[1], c[3] * 0.5, c[2]), PAL.Steel, M.Metal, true)
		end
		put(b, "TowerLeg", Vector3.new(20, 1, 1), CFrame.new(0, 0.5, -7.5), PAL.Rust, M.CorrodedMetal, true)
		put(b, "WaterTank", Vector3.new(10, 11, 11), CFrame.new(-4, 5.5, 5.8), PAL.TankCream, M.Metal, true, true, Enum.PartType.Cylinder)
		put(b, "TankRoof", Vector3.new(1, 12.4, 12.4), CFrame.new(-9.5, 6.2, 5.8), PAL.Rust, M.CorrodedMetal, true, true, Enum.PartType.Cylinder)
		return
	end
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

-- a chest-high adobe compound wall (cover): 1 part per 16 studs of opts.Length (default 16, max 4), centred on the pivot.
-- Variant "gate" (W3 step 2, heist yards): one steel yard gate per 16 instead, 4.4 tall, on the same line (z 0 .. 1.2),
-- named "HeistGate" and flagged WorldConfig.Activity.RuntimeDoorAttr (the jobs open it at runtime; WorldHygiene leaves
-- it alone). It is built closed: collidable, GateStateAttr = "closed".
Builders.CompoundWall = function(b: B)
	local n = math.clamp(math.floor((b.Opts.Length or 16) / 16 + 0.5), 1, 4)
	if b.Opts.Variant == "gate" then
		local A = WorldConfig.Activity
		for i = 1, n do
			local x = (i - (n + 1) * 0.5) * 16
			local g = put(b, "HeistGate", Vector3.new(16, 4.4, 1.2), CFrame.new(x, 2.2, 0.6), b.Opts.Color or PAL.SteelDark, M.DiamondPlate, true)
			g:SetAttribute(A.RuntimeDoorAttr, true)
			g:SetAttribute(A.GateStateAttr, "closed")
		end
		return
	end
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
	-- pivot on the road centre line; X across the road, the booth on the +X shoulder; -Z faces arriving traffic.
	-- W3 step 2 (owner feedback #29, as at the base gate): the booth is taller than an avatar (7, roof top 7.4) with
	-- the window at eye height; its footprint (x 15.5 .. 19.5, z -0.2 .. 4.2) is unchanged, so the
	-- WorldConfig.Activity.CheckpointAnchors clearances hold. The arm stays raised and never collides.
	put(b, "CheckpointBooth", Vector3.new(4, 7, 4.4), CFrame.new(17.5, 3.5, 2.0), PAL.ConcreteLight, M.Concrete, true)
	put(b, "BoothRoof", Vector3.new(6, 0.4, 6.4), CFrame.new(17.5, 7.2, 1.6), PAL.SteelDark, M.Metal, false)
	put(b, "BoothWindow", Vector3.new(0.2, 1.6, 2.8), CFrame.new(15.4, 5.0, 2.0), PAL.Window, M.SmoothPlastic, false)
	put(b, "CheckpointSign", Vector3.new(3.2, 1.6, 0.2), CFrame.new(17.6, 5.4, -0.3), PAL.TarpRed, M.SmoothPlastic, false)
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

-- the soft night PointLight of a street lamp or a wall lantern (H8: Brightness <= 0.8, Range <= 18, no shadows, tagged)
local function nightLamp(host: BasePart)
	local L = KC.Lamp
	local light = Instance.new("PointLight")
	light.Name = "LampLight"
	light.Brightness = math.min(L.Brightness, WorldConfig.Lights.MaxBrightness)
	light.Range = math.min(L.Range, WorldConfig.Lights.MaxRange)
	light.Color = L.Color
	light.Shadows = false
	light.Enabled = nightOn() -- WorldAtmosphere flips WE_NightLight lights at dusk / dawn
	CollectionService:AddTag(light, WorldConfig.Atmosphere.NightLightTag)
	light.Parent = host
end

Builders.StreetLamp = function(b: B)
	put(b, "LampPole", Vector3.new(0.5, 12, 0.5), CFrame.new(0, 6, 0), PAL.SteelDark, M.Metal, true)
	put(b, "LampArm", Vector3.new(0.3, 0.3, 3.2), CFrame.new(0, 11.7, -1.45), PAL.Steel, M.Metal, false)
	local lens = put(b, "LampLens", Vector3.new(1.2, 0.5, 1.2), CFrame.new(0, 11.3, -2.8), PAL.LampLens, M.SmoothPlastic, false)
	if b.Opts.Light ~= false then
		nightLamp(lens)
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
	if b.Opts.Variant == "well" then
		-- W3 step 2 (the Oasis): a stone well, ring wall + 2 posts + the winch beam (4 parts, 5.4 x 4.8 x 5; the posts
		-- stand 0.2 above the beam so no top faces are coplanar)
		vcyl(b, "WellWall", 0, 0, 0, 1.6, 5, PAL.AdobeDark, M.Sandstone, true)
		put(b, "WellPost", Vector3.new(0.5, 4.8, 0.5), CFrame.new(-2.25, 2.4, 0), PAL.WoodDark, M.Wood, false)
		put(b, "WellPost", Vector3.new(0.5, 4.8, 0.5), CFrame.new(2.25, 2.4, 0), PAL.WoodDark, M.Wood, false)
		put(b, "WellBeam", Vector3.new(5.4, 0.4, 0.4), CFrame.new(0, 4.4, 0), PAL.Wood, M.Wood, false)
		return
	end
	vcyl(b, "FountainWall", 0, 0, 0, 1.4, 10, PAL.ConcreteLight, M.Concrete, true, true)
	vcyl(b, "FountainBed", 0, 1.4, 0, 0.1, 8.6, PAL.PavingDark, M.Pavement, false)
	vcyl(b, "FountainColumn", 0, 1.5, 0, 1.6, 1.6, PAL.ConcreteLight, M.Concrete, true)
	vcyl(b, "FountainBowl", 0, 3.1, 0, 0.5, 4, PAL.ConcreteLight, M.Concrete, true)
end

Builders.Bench = function(b: B)
	local p = put(b, "Bench", Vector3.new(6, 1.2, 1.8), CFrame.new(0, 0.6, 0), PAL.Wood, M.Wood, true)
	queueMesh(b, "Bench", "skin", { p })
end

-- Town v2 (densify) ────────────────────────────────────────────────────────────────────────────────────────────────
local STOREY = 7 -- studs per storey (TownBlock)

local function tokens(s: string?): { [string]: boolean }
	local t: { [string]: boolean } = {}
	if s ~= nil then
		for w in string.gmatch(s, "[^+]+") do
			t[w] = true
		end
	end
	return t
end

--[[ A town block: height and street frontage for few parts. The walls are ONE solid part (cover, H4), the cornice ONE
	parapet slab, each upper storey ONE inset window strip per face, the ground floor a door or a shopfront (rolled
	shutter + cloth awning), plus cheap rooftop details. The pivot is the footprint centre on the floor; the front (door,
	shopfront, window strips) faces local -Z.
	Opts: Width (local X, 8..48, default 20), Depth (local Z, 8..48, default 16), Storeys (1..6, default 2; 5+ = a
	concrete tower block), Color (walls; trim = 20 % darker), Lantern (a soft night lamp beside the door),
	Variant ("+"-joined): "shop" (shutter + awning instead of the door), "side" / "left" / "rear" (window strips on the
	+X / -X / back face too),
	"damaged" (the top storey's +X half is blown off: remnant + the fallen floor slab on the broken roof, no parapet),
	"gutted" (a burnt-out shell: back and side walls, a ground-floor front stub, the collapsed floor leaning inside);
	W3 step 2: "roller" (one vehicle-wide roller door, min(12, W - 6) x 5.6, instead of the door: +0 parts; "shop" wins),
	"metal" (corrugated-metal colour and material for the walls and trim: +0 parts; opts.Color still wins),
	"hall" (a walk-in hall: back wall, 2 side walls and 2 front piers round a centred full-height opening
	clamp(W - 8, 4, 10) wide, all 1.2 thick and collidable, + 1 roof slab carrying the parapet (the block's one shadow
	caster) + the usual upper window strips; no door or shutter, "damaged" is ignored: exactly 7 parts at Storeys 2 with
	no Roof / Lantern / side strips);
	Roof ("+"-joined): "bare" (no parapet), "tank" / "tanks" (1 / 2 water tanks), "hut" (stair hut), "mast" (antenna,
	2 parts), "dish" (1 part). Every part stays inside the parapet footprint (W + 0.8) x (D + 0.8), except the awning
	(3.1 in front) and the lantern (0.8 in front). One shadow caster per block (its body, or a shell's back wall: H9,
	the Town keeps <= 60 casters for phones). ]]
Builders.TownBlock = function(b: B)
	local o = b.Opts
	local W = math.clamp(o.Width or 20, 8, 48)
	local D = math.clamp(o.Depth or 16, 8, 48)
	local S = math.clamp(math.floor(o.Storeys or 2), 1, 6)
	local v, roof = tokens(o.Variant), tokens(o.Roof)
	local tower = S >= 5
	local metal = v.metal == true
	local mat = if metal then M.Metal elseif tower then M.Concrete else M.Sandstone
	local wall = o.Color or (if metal then PAL.Metal elseif tower then PAL.ConcreteLight else PAL.Adobe)
	local trim = wall:Lerp(Color3.new(0, 0, 0), 0.2)
	local H = S * STOREY
	local fz = -D * 0.5 -- the front face
	local rng = b.Rng

	if v.gutted then
		put(b, "RuinWallBack", Vector3.new(W, H, 1.2), CFrame.new(0, H * 0.5, D * 0.5 - 0.6), wall, mat, true, true)
		local sh = math.max(H - 2, 4)
		put(b, "RuinWallSide", Vector3.new(1.2, sh, D - 1.2), CFrame.new(-W * 0.5 + 0.6, sh * 0.5, -0.6), trim, mat, true)
		local fw = math.floor(W * 0.45 + 0.5)
		local fh = if S == 1 then 4 else STOREY + 1
		put(b, "RuinWallFront", Vector3.new(fw, fh, 1.2), CFrame.new(W * 0.5 - fw * 0.5, fh * 0.5, fz + 0.6), wall, mat, true)
		-- the collapsed upper floor: its high end on the side wall, its low end on the floor inside the shell
		local L = W * 0.7
		local a = math.asin(math.min(0.8, math.min(STOREY, H - 1) * 0.8 / L))
		local cy = L * 0.5 * math.sin(a) + 0.4 * math.cos(a) + 0.02
		put(b, "RuinFloorSlab", Vector3.new(L, 0.8, D - 3), CFrame.new(-W * 0.5 + 1.2 + L * 0.5 * math.cos(a), cy, 0) * rotZ(-math.deg(a)), trim, mat, true)
		return
	end

	local hall = v.hall == true
	local damaged = v.damaged == true and S >= 2 and not hall
	local rx0, rx1 = -W * 0.5, W * 0.5 -- the roof the details stand on
	local roofY = H
	local topW = W - 4 -- the top storey's window strip
	if hall then
		local T = 1.2
		local gap = math.clamp(W - 8, 4, 10) -- the full-height opening (the door)
		local pw = (W - gap) * 0.5
		put(b, "HallWall", Vector3.new(W, H, T), CFrame.new(0, H * 0.5, D * 0.5 - T * 0.5), wall, mat, true)
		-- the side walls run between the front piers and the back wall (no shared faces: nothing z-fights)
		put(b, "HallWall", Vector3.new(T, H, D - 2 * T), CFrame.new(-W * 0.5 + T * 0.5, H * 0.5, 0), trim, mat, true)
		put(b, "HallWall", Vector3.new(T, H, D - 2 * T), CFrame.new(W * 0.5 - T * 0.5, H * 0.5, 0), trim, mat, true)
		put(b, "HallPier", Vector3.new(pw, H, T), CFrame.new(-gap * 0.5 - pw * 0.5, H * 0.5, fz + T * 0.5), wall, mat, true)
		put(b, "HallPier", Vector3.new(pw, H, T), CFrame.new(gap * 0.5 + pw * 0.5, H * 0.5, fz + T * 0.5), wall, mat, true)
		if roof.bare then
			put(b, "HallRoof", Vector3.new(W, 0.8, D), CFrame.new(0, H + 0.4, 0), trim, mat, true, true)
			roofY = H + 0.8
		else
			put(b, "HallRoof", Vector3.new(W + 0.8, 1.2, D + 0.8), CFrame.new(0, H + 0.6, 0), trim, mat, true, true)
			roofY = H + 1.2
		end
	elseif damaged then
		local lowH = H - STOREY
		local rw = math.floor(W * 0.55 + 0.5)
		put(b, "AdobeBlock", Vector3.new(W, lowH, D), CFrame.new(0, lowH * 0.5, 0), wall, mat, true, true)
		put(b, "AdobeBlockUpper", Vector3.new(rw, STOREY, D), CFrame.new(-W * 0.5 + rw * 0.5, lowH + STOREY * 0.5, 0), wall, mat, true)
		-- the fallen floor of the blown corner, tipped from the remnant down to the broken edge
		local sw = W - rw - 1
		local tilt = math.rad(10)
		put(b, "AdobeDebris", Vector3.new(sw, 0.8, D * 0.7), CFrame.new(W * 0.5 - sw * 0.5 - 0.3, lowH + sw * 0.5 * math.sin(tilt) + 0.4 * math.cos(tilt), 0.1 * D) * rotZ(-10), trim, mat, true)
		rx1 = -W * 0.5 + rw
		topW = rw - 3
	else
		put(b, "AdobeBlock", Vector3.new(W, H, D), CFrame.new(0, H * 0.5, 0), wall, mat, true, true)
		if not roof.bare then
			put(b, "AdobeParapet", Vector3.new(W + 0.8, 1.2, D + 0.8), CFrame.new(0, H + 0.6, 0), trim, mat, true)
			roofY = H + 1.2
		end
	end

	-- one inset window strip per upper storey (front; "side" / "left" / "rear": the +X / -X / back face too; damaged:
	-- none on the blown half)
	for k = 2, S do
		local y = (k - 1) * STOREY + 3.6
		local top = k == S
		local w = if top then topW else W - 4
		local x = if top and damaged then rx0 + 1.5 + w * 0.5 else 0
		put(b, "AdobeWindowStrip", Vector3.new(math.max(w, 2), 1.8, 0.3), CFrame.new(x, y, fz - 0.15), PAL.Window, M.SmoothPlastic, false)
		if v.side and not (top and damaged) then
			put(b, "AdobeWindowStrip", Vector3.new(0.3, 1.8, math.max(D - 4, 2)), CFrame.new(W * 0.5 + 0.15, y, 0), PAL.Window, M.SmoothPlastic, false)
		end
		if v.left then
			put(b, "AdobeWindowStrip", Vector3.new(0.3, 1.8, math.max(D - 4, 2)), CFrame.new(-W * 0.5 - 0.15, y, 0), PAL.Window, M.SmoothPlastic, false)
		end
		if v.rear and not (top and damaged) then
			put(b, "AdobeWindowStrip", Vector3.new(math.max(W - 4, 2), 1.8, 0.3), CFrame.new(0, y, D * 0.5 + 0.15), PAL.Window, M.SmoothPlastic, false)
		end
	end

	-- ground floor: a rolled steel shutter under a cloth awning, a vehicle-wide roller door, or a door (a hall's
	-- opening is its door)
	if hall then
		-- nothing: the full-height opening
	elseif v.shop then
		local shutters = { PAL.Rust, PAL.SteelDark, PAL.DrumBlue }
		local tarps = { PAL.TarpRed, PAL.TarpBlue, PAL.TarpSand }
		local sw = math.max(W - 6, 4)
		put(b, "ShopShutter", Vector3.new(sw, 4.2, 0.3), CFrame.new(0, 2.3, fz - 0.15), shutters[rng:NextInteger(1, 3)], M.CorrodedMetal, false)
		put(b, "ShopTarp", Vector3.new(sw, 0.25, 3.1), CFrame.new(0, 5.2, fz - 1.52) * rotX(-14), tarps[rng:NextInteger(1, 3)], M.Fabric, false)
	elseif v.roller then
		local rw = math.max(math.min(12, W - 6), 4)
		put(b, "RollerDoor", Vector3.new(rw, 5.6, 0.3), CFrame.new(0, 2.8, fz - 0.15), if metal then PAL.MetalDark else PAL.SteelDark, M.CorrodedMetal, false)
	else
		put(b, "AdobeDoor", Vector3.new(2.4, 4.2, 0.3), CFrame.new(-W * 0.5 + 3.2, 2.1, fz - 0.15), PAL.WoodDark, M.Wood, false)
	end
	if o.Lantern == true then
		local lamp = put(b, "LampLantern", Vector3.new(0.8, 1.1, 0.8), CFrame.new(W * 0.5 - 1.6, 6.2, fz - 0.4), PAL.LampLens, M.SmoothPlastic, false)
		if o.Light ~= false then
			nightLamp(lamp)
		end
	end

	-- rooftop details (inside the roof outline, standing on it)
	if roof.tank or roof.tanks then
		local cols = { PAL.SteelDark, PAL.TankCream, PAL.DrumBlue }
		vcyl(b, "RoofTank", rx1 - 2.6, roofY, D * 0.5 - 2.6, 3.2, 3.4, cols[rng:NextInteger(1, 3)], M.Plastic, true)
		if roof.tanks then
			vcyl(b, "RoofTank", rx1 - 6.4, roofY, D * 0.5 - 2.6, 3.2, 3.4, cols[rng:NextInteger(1, 3)], M.Plastic, true)
		end
	end
	if roof.hut then
		put(b, "RoofHut", Vector3.new(4.6, 3.2, 4.2), CFrame.new(rx0 + 3.0, roofY + 1.6, D * 0.5 - 2.8), trim, mat, true)
	end
	if roof.mast then
		put(b, "RoofMast", Vector3.new(0.45, 12, 0.45), CFrame.new(rx0 + 2.0, roofY + 6, fz + 2.2), PAL.SteelDark, M.Metal, false)
		put(b, "RoofMastBar", Vector3.new(3.2, 0.3, 0.3), CFrame.new(rx0 + 2.0, roofY + 10.5, fz + 2.2), PAL.SteelDark, M.Metal, false)
	end
	if roof.dish then
		put(b, "RoofDish", Vector3.new(0.4, 3, 3), CFrame.new((rx0 + rx1) * 0.5, roofY + 1.3, fz + 2.4) * rotY(90) * rotZ(40), PAL.ConcreteLight, M.SmoothPlastic, false, false, Enum.PartType.Cylinder)
	end
end

-- a lattice radio mast, 90 tall (the Town's skyline marker from every gate): plinth, two tapering sections, a red tip
-- and a relay dish. Solid, no light (the aviation tip is painted, never Neon).
Builders.RadioMast = function(b: B)
	put(b, "MastPlinth", Vector3.new(6, 2, 6), CFrame.new(0, 1, 0), PAL.ConcreteLight, M.Concrete, true)
	put(b, "MastSection", Vector3.new(3.2, 40, 3.2), CFrame.new(0, 22, 0), PAL.Steel, M.DiamondPlate, true, true)
	put(b, "MastSection", Vector3.new(2.2, 30, 2.2), CFrame.new(0, 57, 0), PAL.Steel, M.DiamondPlate, true, true)
	put(b, "MastTip", Vector3.new(1, 18, 1), CFrame.new(0, 81, 0), PAL.TarpRed, M.SmoothPlastic, true)
	put(b, "MastDish", Vector3.new(0.5, 4.4, 4.4), CFrame.new(0, 48, -1.35) * ZCYL, PAL.ConcreteLight, M.SmoothPlastic, false, false, Enum.PartType.Cylinder)
end

-- W3 step 2: the later POIs (spec w3s2 §6 lane K; contract w3s2/build/L0/contract.md §5) ─────────────────────────────
-- Cheap big-part builds in the Town v2 style: a few large anchored Parts per kit, no Neon, no light, no GUI; the parts
-- counts are exactly Specs[kit].Parts (Variants / per unit). Names follow the Hygiene keywords: solid-keyword parts that
-- reach 1.5 above the floor collide (H4), natural parts carry a natural prefix and never collide.

-- a horizontal cylinder along the kit's local X (length L, diameter d) centred at (x, y, z)
local function xcyl(b: B, name: string, x: number, y: number, z: number, L: number, d: number, color: Color3, mat: Enum.Material?, collide: boolean?, shadow: boolean?): Part
	return put(b, name, Vector3.new(L, d, d), CFrame.new(x, y, z), color, mat, collide, shadow, Enum.PartType.Cylinder)
end

-- a horizontal cylinder along the kit's local Z
local function zcyl(b: B, name: string, x: number, y: number, z: number, L: number, d: number, color: Color3, mat: Enum.Material?, collide: boolean?, shadow: boolean?): Part
	return put(b, name, Vector3.new(L, d, d), CFrame.new(x, y, z) * ZCYL, color, mat, collide, shadow, Enum.PartType.Cylinder)
end

-- a climbable ladder: one TrussPart (Roblox keeps a truss 2 x 2 across and an even length), set up like WorldKits.Part
-- (anchored, CanTouch off, no shadow, WE_Decor); it collides, or it could not be climbed
local function truss(b: B, name: string, height: number, lcf: CFrame, color: Color3): TrussPart
	local t = Instance.new("TrussPart")
	t.Name = name
	t.Anchored = true
	t.Size = Vector3.new(2, 2 * math.max(1, math.floor(height / 2 + 0.5)), 2)
	t.CFrame = b.CF * lcf
	t.Color = color
	t.Material = M.Metal
	t.Transparency = 0
	t.CanCollide = true
	t.CanQuery = true
	t.CanTouch = false
	t.CastShadow = false
	t:SetAttribute("WE_Decor", true)
	t.Parent = b.Cluster
	table.insert(b.Parts, t)
	return t
end

-- a runtime door part (HeistGate, BunkerDoor): the jobs open it (Phase B), WorldHygiene Enforce leaves it alone
local function runtimeDoor(p: BasePart)
	local A = WorldConfig.Activity
	p:SetAttribute(A.RuntimeDoorAttr, true)
	p:SetAttribute(A.GateStateAttr, "closed")
end

-- shipping containers, 7.2 x 7.5 x 18 each: Count 1 .. 6 (default 3 = 2 side by side + 1 on top); 4 .. 6 fill a second
-- row 1 stud behind (z 10 .. 28). Every container casts a shadow (the geometry plan counts n casters)
local CONTAINER_SLOTS = { { -3.8, 0, 0 }, { 3.8, 0, 0 }, { 0, 7.5, 0 }, { -3.8, 0, 19 }, { 3.8, 0, 19 }, { 0, 7.5, 19 } }
Builders.ContainerStack = function(b: B)
	local n = math.clamp(math.floor(b.Opts.Count or 3), 1, 6)
	local cols = { PAL.Rust, PAL.DrumBlue, PAL.CrateOlive, PAL.TarpRed, PAL.TankCream }
	local k0 = b.Rng:NextInteger(0, #cols - 1)
	for i = 1, n do
		local s = CONTAINER_SLOTS[i]
		put(b, "Container", Vector3.new(7.2, 7.5, 18), CFrame.new(s[1], s[2] + 3.75, s[3]), cols[(k0 + i - 1) % #cols + 1], M.Metal, true, true)
	end
end

-- a quay gantry crane (landmark, 55 tall): 4 legs on the quay (z -6.8 .. 6.8), the cross girder, the boom reaching 40
-- over the water (-Z) and 13 behind, the stay apex. Scale (0.5 .. 1.6; the rig shore bases use 0.6)
Builders.GantryCrane = function(b: B)
	local s = scaleOf(b)
	for _, c in ipairs({ { -11.2, -6 }, { 11.2, -6 }, { -11.2, 6 }, { 11.2, 6 } }) do
		put(b, "GantryLeg", Vector3.new(1.6, 40, 1.6) * s, CFrame.new(c[1] * s, 20 * s, c[2] * s), PAL.Hazard, M.Metal, true)
	end
	put(b, "GantryGirder", Vector3.new(24, 3, 14) * s, CFrame.new(0, 41.5 * s, 0), PAL.SteelDark, M.Metal, true, true)
	put(b, "GantryBoom", Vector3.new(2.4, 2.4, 53) * s, CFrame.new(0, 44.2 * s, -13.5 * s), PAL.Hazard, M.Metal, true, true)
	put(b, "GantryApex", Vector3.new(2, 9.6, 2) * s, CFrame.new(0, 50.2 * s, 10 * s), PAL.SteelDark, M.Metal, true)
end

-- a vertical fuel tank on a concrete ring, 12.4 across and 11 tall at Scale 1 (0.5 .. 1.6)
Builders.FuelTank = function(b: B)
	local s = scaleOf(b)
	vcyl(b, "FuelTankBase", 0, 0, 0, 0.6 * s, 12.4 * s, PAL.ConcreteLight, M.Concrete, true)
	vcyl(b, "FuelTankBody", 0, 0.6 * s, 0, 9.8 * s, 12 * s, PAL.TankCream, M.Metal, true, true)
	vcyl(b, "FuelTankRoof", 0, 10.4 * s, 0, 0.6 * s, 8 * s, PAL.Rust, M.CorrodedMetal, true)
end

-- a gas flare stack (landmark, 45 tall): plinth, pipe, and a painted flame ball on top (never Neon, no light)
Builders.FlareStack = function(b: B)
	put(b, "FlareBase", Vector3.new(6, 1.5, 6), CFrame.new(0, 0.75, 0), PAL.ConcreteLight, M.Concrete, true)
	vcyl(b, "FlareStackPipe", 0, 1.5, 0, 40, 1.8, PAL.Steel, M.Metal, true, true)
	put(b, "FlareFlame", Vector3.new(3.5, 3.5, 3.5), CFrame.new(0, 43.25, 0), PAL.Hazard:Lerp(PAL.TarpRed, 0.35), M.SmoothPlastic, false, false, Enum.PartType.Ball)
end

-- a radar dome on a concrete tower (landmark, 26 tall): tower (door on the front), deck, dome, mast
Builders.RadarDome = function(b: B)
	put(b, "RadarBase", Vector3.new(7, 12, 7), CFrame.new(0, 6, 0), PAL.ConcreteLight, M.Concrete, true, true)
	put(b, "RadarDoor", Vector3.new(2.4, 4.2, 0.3), CFrame.new(0, 2.1, -3.65), PAL.SteelDark, M.Metal, false)
	put(b, "RadarDeck", Vector3.new(13, 0.8, 13), CFrame.new(0, 12.4, 0), PAL.SteelDark, M.Metal, true)
	put(b, "RadarDome", Vector3.new(12.6, 12.6, 12.6), CFrame.new(0, 19.1, 0), PAL.RadarWhite, M.SmoothPlastic, true, true, Enum.PartType.Ball)
	put(b, "RadarMast", Vector3.new(0.4, 1.2, 0.4), CFrame.new(0, 25.4, 0), PAL.SteelDark, M.Metal, false)
end

-- the Crash Site cargo plane in 3 pieces (fuselage along local Z). Variant "mid" (default: fuselage, both wings, an
-- engine), "nose" (fuselage, rounded nose, wing stub), "tail" (tail cone + a fin, rolled over)
Builders.PlaneWreck = function(b: B)
	local v = b.Opts.Variant or "mid"
	local alu, burnt, cm = PAL.Aluminium, PAL.Burnt, M.CorrodedMetal
	if v == "nose" then
		zcyl(b, "PlaneWreckNose", 0, 5, 4, 18, 10, alu, M.Metal, true, true)
		put(b, "PlaneWreckCockpit", Vector3.new(10, 10, 10), CFrame.new(0, 5, -8), alu, M.Metal, true, false, Enum.PartType.Ball)
		put(b, "PlaneWreckWing", Vector3.new(12, 0.8, 4), CFrame.new(0, 2.6, 6) * rotZ(4), burnt, cm, true)
	elseif v == "tail" then
		zcyl(b, "PlaneWreckTail", 0, 3, 0, 18, 6, alu, M.Metal, true, true)
		-- the fin, 7 tall, on the fuselage top at the back, rolled 35 degrees toward +X
		local a = math.rad(35)
		put(b, "PlaneWreckFin", Vector3.new(0.8, 7, 5), CFrame.new(3.5 * math.sin(a), 6 + 3.5 * math.cos(a), 6.5) * rotZ(-35), burnt, cm, true)
	else
		zcyl(b, "PlaneWreckFuselage", 0, 5, 0, 22, 10, alu, M.Metal, true, true)
		-- left wing: root at x -4.2, y 3, 10 degrees of dihedral; right wing: broken, drooping 8 degrees into the sand
		local function wing(side: number, deg: number, color: Color3, shadow: boolean)
			local a = math.rad(deg)
			local cx, cy = side * (4.2 + 6.5 * math.cos(a)), 3 + 6.5 * math.sin(a)
			put(b, "PlaneWreckWing", Vector3.new(13, 0.8, 7), CFrame.new(cx, cy, 1) * rotZ(side * deg), color, cm, true, shadow)
		end
		wing(-1, 10, alu, true)
		wing(1, -8, burnt, false)
		zcyl(b, "PlaneWreckEngine", -9, 1.5, 1.5, 6, 3, burnt, cm, true)
	end
end

-- a downed helicopter: body rolled 15 degrees, tail boom (+Z), fin, a rotor blade and a skid lying in the sand
Builders.HeliWreck = function(b: B)
	local cm = M.CorrodedMetal
	put(b, "HeliWreckBody", Vector3.new(4.6, 4.6, 9), CFrame.new(0, 2.85, -7.5) * rotZ(15), PAL.DrumOlive, cm, true, true)
	zcyl(b, "HeliWreckTail", 0.4, 2.2, 3.5, 13, 1.4, PAL.DrumOlive, cm, true)
	put(b, "HeliWreckFin", Vector3.new(0.4, 3, 2), CFrame.new(0.4, 3.4, 11), PAL.Burnt, cm, true)
	put(b, "HeliWreckRotor", Vector3.new(10, 0.2, 0.8), CFrame.new(0, 0.1, -5) * rotY(20), PAL.SteelDark, M.Metal, false)
	put(b, "HeliWreckSkid", Vector3.new(0.4, 0.4, 8), CFrame.new(-3.4, 0.2, -6.5) * rotY(-6), PAL.SteelDark, M.Metal, false)
end

-- a hedgehog tank trap: two steel beams crossed at the centre along the plan diagonals, tilted 27 degrees in opposite
-- senses, so it reads as an X from the road (4 x 3 x 4, resting on the floor)
Builders.TankTrap = function(b: B)
	local L, t, deg = 5.2, 0.7, 27
	local a = math.rad(deg)
	local cy = (L * math.sin(a) + t * math.cos(a)) * 0.5
	put(b, "TankTrapBeam", Vector3.new(L, t, t), CFrame.new(0, cy, 0) * rotY(45) * rotZ(deg), PAL.SteelDark, M.CorrodedMetal, true)
	put(b, "TankTrapBeam", Vector3.new(L, t, t), CFrame.new(0, cy, 0) * rotY(-45) * rotZ(-deg), PAL.Rust, M.CorrodedMetal, true)
end

-- the Quarry rock crusher (landmark): crusher house, hopper on top, the conveyor running down to +Z (z 6 .. 30) on one
-- support leg, a gravel heap beside its foot
Builders.Crusher = function(b: B)
	put(b, "CrusherBody", Vector3.new(13, 10, 12), CFrame.new(0, 5, 0), PAL.ConcreteLight, M.Concrete, true, true)
	put(b, "CrusherHopper", Vector3.new(9, 4, 9), CFrame.new(0, 12, -0.5), PAL.Rust, M.CorrodedMetal, true)
	local L, t = 26.2, 0.6
	local a = math.atan2(10.5, 24)
	local cy, cz = (L * math.sin(a) + t * math.cos(a)) * 0.5, 17.85
	put(b, "CrusherConveyor", Vector3.new(3, t, L), CFrame.new(0, cy, cz) * CFrame.Angles(a, 0, 0), PAL.SteelDark, M.Metal, true, true)
	local lz = 14
	local legTop = cy + (cz - lz) * math.tan(a) - t * 0.5 / math.cos(a)
	put(b, "CrusherLeg", Vector3.new(1, legTop, 1), CFrame.new(0, legTop * 0.5, lz), PAL.Steel, M.Metal, true)
	put(b, "CrusherGravel", Vector3.new(4.4, 2.4, 8), CFrame.new(4.2, 1.2, 25), PAL.PavingDark, M.Pebble, true)
end

-- a timber watchtower (8 parts, 9 x 9): 4 legs running up to the roof, the deck (top = WorldConfig.Kits.WatchtowerDeckY,
-- 14: tower posts stand on it), a front half-wall, a climbable ladder at the back (TrussPart; it tops out 2 above the
-- deck so a player steps off without jumping), and a roof 8.5 above the deck that nothing collides with (owner feedback
-- #29, as at the base tower: heads, jumps and the Poppercam never catch on it)
local TOWER_HEADROOM = 8.5
Builders.Watchtower = function(b: B)
	local deckY = KC.WatchtowerDeckY
	local roofY = deckY + TOWER_HEADROOM
	for _, c in ipairs({ { -3.9, -3.9 }, { 3.9, -3.9 }, { -3.9, 3.9 }, { 3.9, 3.9 } }) do
		put(b, "TowerLeg", Vector3.new(0.8, roofY, 0.8), CFrame.new(c[1], roofY * 0.5, c[2]), PAL.WoodDark, M.Wood, true)
	end
	-- the deck stops at z 2 so the ladder (z 2 .. 4) rises clear of it
	put(b, "TowerDeck", Vector3.new(9, 0.6, 6.5), CFrame.new(0, deckY - 0.3, -1.25), PAL.Wood, M.WoodPlanks, true)
	put(b, "TowerWall", Vector3.new(9, 3.4, 0.4), CFrame.new(0, deckY + 1.7, -4.3), PAL.Wood, M.WoodPlanks, true)
	put(b, "TowerRoof", Vector3.new(9, 0.5, 9), CFrame.new(0, roofY + 0.25, 0), PAL.SteelDark, M.Metal, false, true)
	truss(b, "TowerLadder", deckY + 2, CFrame.new(0, (deckY + 2) * 0.5, 3), PAL.SteelDark)
end

-- an earth-covered bunker, pivot at the front: the mound (z 0 .. 11), the concrete facade and the yellow blast door
-- "BunkerDoor" (a runtime door, built closed)
Builders.Bunker = function(b: B)
	put(b, "BunkerBody", Vector3.new(18, 7, 11), CFrame.new(0, 3.5, 5.5), PAL.Sandbag, M.Ground, true, true)
	put(b, "BunkerFacade", Vector3.new(10, 5.6, 0.3), CFrame.new(0, 2.8, -0.15), PAL.Concrete, M.Concrete, true)
	runtimeDoor(put(b, "BunkerDoor", Vector3.new(4.4, 4.4, 0.2), CFrame.new(0, 2.2, -0.4), PAL.Hazard, M.DiamondPlate, true))
end

-- an open-front hangar (-Z open), Width (inside, default 28, 16 .. 48) x 25 deep: 2 side walls and the back wall
-- 12.9 tall, the yellow front lintel (the opening is 11.5 clear), a flat roof slab (the one shadow caster). All collide, so
-- the phone camera pulls in under the roof instead of seeing its top
Builders.Hangar = function(b: B)
	local W = math.clamp(b.Opts.Width or 28, 16, 48)
	local H, D, T = 12.9, 25, 0.6
	local wall = b.Opts.Color or PAL.Metal
	put(b, "HangarWall", Vector3.new(T, H, D), CFrame.new(-W * 0.5 - T * 0.5, H * 0.5, 0), wall, M.Metal, true)
	put(b, "HangarWall", Vector3.new(T, H, D), CFrame.new(W * 0.5 + T * 0.5, H * 0.5, 0), wall, M.Metal, true)
	put(b, "HangarWall", Vector3.new(W, H, T), CFrame.new(0, H * 0.5, D * 0.5 - T * 0.5), wall, M.Metal, true)
	put(b, "HangarLintel", Vector3.new(W, 1.4, T), CFrame.new(0, H - 0.7, -D * 0.5 + T * 0.5), PAL.Hazard, M.Metal, true)
	put(b, "HangarRoof", Vector3.new(W + 2 * T, 0.6, D), CFrame.new(0, H + 0.3, 0), PAL.MetalDark, M.Metal, true, true)
end

-- a see-through wire fence, 1 panel per 16 studs of opts.Length (16 .. 64), centred on the pivot line. It collides
-- (nobody walks through a fence); "Wire" is a soft keyword, so it is not cover (H4)
Builders.WireFence = function(b: B)
	local n = math.clamp(math.floor((b.Opts.Length or 16) / 16 + 0.5), 1, 4)
	for i = 1, n do
		local x = (i - (n + 1) * 0.5) * 16
		local p = put(b, "WireFence", Vector3.new(16, 3, 0.4), CFrame.new(x, 1.5, 0), PAL.Steel, M.DiamondPlate, true)
		p.Transparency = 0.45
	end
end

-- an A-frame canvas tent (open ends along Z) with its front pole
Builders.Tent = function(b: B)
	local half, h, t = 3.8, 4.8, 0.2
	local a = math.atan2(h, half)
	local L = math.sqrt(half * half + h * h)
	local cy = (L * math.sin(a) + t * math.cos(a)) * 0.5
	put(b, "TentCanvas", Vector3.new(L, t, 9), CFrame.new(-half * 0.5, cy, 0) * rotZ(math.deg(a)), PAL.Canvas, M.Fabric, true)
	put(b, "TentCanvas", Vector3.new(L, t, 9), CFrame.new(half * 0.5, cy, 0) * rotZ(-math.deg(a)), PAL.Canvas:Lerp(PAL.WoodDark, 0.15), M.Fabric, true)
	put(b, "TentPole", Vector3.new(0.3, h, 0.3), CFrame.new(0, h * 0.5, -4.3), PAL.WoodDark, M.Wood, false)
end

-- a date palm (natural: never collides): the trunk leaning 6 degrees toward -X from a foot 1.3 * Scale right of the
-- pivot, so the crown (two crossed fronds, 10 across) is centred over the pivot. Scale
Builders.Palm = function(b: B)
	local s = scaleOf(b)
	local h, tilt = 12.6 * s, math.rad(6)
	local lean, ty = h * math.sin(tilt), h * math.cos(tilt)
	-- lifted by the tilted foot's half-width so no edge dips below the floor
	put(b, "PalmTrunk", Vector3.new(h, 1.1 * s, 1.1 * s), CFrame.new(lean * 0.5, ty * 0.5 + 0.55 * s * math.sin(tilt), 0) * rotZ(96), PAL.PalmTrunk, M.Wood, false, false, Enum.PartType.Cylinder)
	put(b, "PalmFrond", Vector3.new(10 * s, 0.35 * s, 2.4 * s), CFrame.new(0, ty + 0.3 * s, 0), PAL.PalmFrond, M.Grass, false)
	put(b, "PalmFrond", Vector3.new(10 * s, 0.35 * s, 2.4 * s), CFrame.new(0, ty + 0.2 * s, 0) * rotY(90), PAL.PalmFrond:Lerp(PAL.JoshuaLeaf, 0.4), M.Grass, false)
end

-- an oil pumpjack (long axis along Z): skid, Samson post, walking beam, horsehead (-Z), counterweight / motor (+Z)
Builders.Pumpjack = function(b: B)
	put(b, "PumpjackBase", Vector3.new(2.6, 0.6, 14), CFrame.new(0, 0.3, 0), PAL.Concrete, M.Concrete, true)
	put(b, "PumpjackPost", Vector3.new(1.2, 7.4, 1.2), CFrame.new(0, 4.3, 0.8), PAL.SteelDark, M.Metal, true)
	put(b, "PumpjackBeam", Vector3.new(1, 1, 11), CFrame.new(0, 8.6, -1) * rotX(8), PAL.SteelDark, M.Metal, true)
	put(b, "PumpjackHead", Vector3.new(1.2, 3.4, 1.4), CFrame.new(0, 8, -6.2), PAL.Hazard, M.Metal, true)
	put(b, "PumpjackWeight", Vector3.new(4, 2.4, 3), CFrame.new(0, 1.8, 5.2), PAL.Rust, M.CorrodedMetal, true)
end

-- a console desk with its screen tilted back (never Neon): the uplink / hack consoles
Builders.Terminal = function(b: B)
	put(b, "TerminalDesk", Vector3.new(3, 2.4, 2), CFrame.new(0, 1.2, 0), PAL.SteelDark, M.Metal, true)
	put(b, "TerminalScreen", Vector3.new(2.6, 0.8, 0.25), CFrame.new(0, 2.8, 0.55) * rotX(15), PAL.Window, M.SmoothPlastic, false)
end

-- a flat painted disc marking a hold zone: radius opts.R (WorldConfig.Kits.HoldPad: default 10, 3 .. 24), top 0.13
-- above the floor, no collision. Variant "pond": the Oasis pond (Glass, 20 % see-through; not WE_Water, boats ignore it)
Builders.HoldPad = function(b: B)
	local HP = KC.HoldPad
	local r = math.clamp(b.Opts.R or HP.R, HP.MinR, HP.MaxR)
	if b.Opts.Variant == "pond" then
		local p = vcyl(b, "HoldPadPond", 0, 0, 0, HP.Top, r * 2, PAL.PondWater, M.Glass, false)
		p.Transparency = 0.2
	else
		vcyl(b, "HoldPad", 0, 0, 0, HP.Top, r * 2, PAL.PadPaint, M.SmoothPlastic, false)
	end
end

-- a pipe run along local X, 1 unit per 40 studs of opts.Length (1 .. 3 units; a cluster stays <= 64 wide, so the
-- layouts use 40): a pipe on the ground (d 1.8), or Variant "rack": the pipe (d 1.2) on 2 rack posts, top 4.5
Builders.PipeRun = function(b: B)
	local n = math.clamp(math.floor((b.Opts.Length or 40) / 40 + 0.5), 1, 3)
	local rack = b.Opts.Variant == "rack"
	for i = 1, n do
		local x = (i - (n + 1) * 0.5) * 40
		if rack then
			put(b, "PipeRackPost", Vector3.new(0.6, 3.3, 2), CFrame.new(x - 14, 1.65, 0), PAL.SteelDark, M.Metal, true)
			put(b, "PipeRackPost", Vector3.new(0.6, 3.3, 2), CFrame.new(x + 14, 1.65, 0), PAL.SteelDark, M.Metal, true)
			xcyl(b, "Pipe", x, 3.9, 0, 40, 1.2, PAL.Rust, M.CorrodedMetal, true)
		else
			xcyl(b, "Pipe", x, 0.9, 0, 40, 1.8, PAL.Rust, M.CorrodedMetal, true)
		end
	end
end

-- the invisible 1-stud host of a POI layout's activity anchors (WorldConfig.Activity.HostKit): never collides, never
-- queried or touched, no overlay; it must never move
Builders.ActivityHost = function(b: B)
	local p = put(b, "ActivityHost", Vector3.new(1, 1, 1), CFrame.new(0, 0.5, 0), PAL.SteelDark, M.SmoothPlastic, false)
	p.Transparency = 1
end

-- the airstrip runway (infra, not a cluster: 500 long, exempt from H10; WorldPOI builds it under POI_<Id>.Infra):
-- asphalt (WorldConfig.Kits.Runway.Width wide), centre line, 2 threshold bars, and the taxiway strip over opts.Taxiway
-- (a WORLD rect { X0, X1, Z0, Z1 }, built axis-aligned) or, without one, a touchdown aim marking. 5 parts, flat (top
-- Kits.Runway.Top above the floor), no collision, no shadow. Length 200 .. 2000 (default 500)
Builders.Runway = function(b: B)
	local RW = KC.Runway
	local L = math.clamp(b.Opts.Length or 500, 200, 2000)
	local W = RW.Width
	local PAINT = 0.06 -- the paint stands 0.06 proud of the asphalt (as the road dashes do): a thinner gap flickers on phones
	local slab = RW.Top - PAINT
	put(b, "RunwayAsphalt", Vector3.new(L, slab, W), CFrame.new(0, slab * 0.5, 0), PAL.Asphalt, M.Asphalt, false)
	put(b, "RunwayCentreLine", Vector3.new(L - 60, PAINT, 1), CFrame.new(0, slab + PAINT * 0.5, 0), PAL.RunwayPaint, M.SmoothPlastic, false)
	for _, sx in ipairs({ -1, 1 }) do
		put(b, "RunwayThreshold", Vector3.new(3, PAINT, W - 6), CFrame.new(sx * (L * 0.5 - 4), slab + PAINT * 0.5, 0), PAL.RunwayPaint, M.SmoothPlastic, false)
	end
	local tw = b.Opts.Taxiway
	if tw ~= nil and #tw >= 4 then
		local x0, x1 = math.min(tw[1], tw[2]), math.max(tw[1], tw[2])
		local z0, z1 = math.min(tw[3], tw[4]), math.max(tw[3], tw[4])
		local p = WorldKits.Part({
			Name = "RunwayTaxiway",
			Size = Vector3.new(math.max(x1 - x0, 1), slab, math.max(z1 - z0, 1)),
			CFrame = CFrame.new((x0 + x1) * 0.5, b.CF.Position.Y + slab * 0.5, (z0 + z1) * 0.5),
			Color = PAL.Asphalt,
			Material = M.Asphalt,
		}, b.Cluster)
		table.insert(b.Parts, p)
	else
		put(b, "RunwayAimPoint", Vector3.new(24, PAINT, 10), CFrame.new(-L * 0.5 + 70, slab + PAINT * 0.5, 0), PAL.RunwayPaint, M.SmoothPlastic, false)
	end
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
	local fire = b.Opts.Variant == "fire" -- W3 step 2 (camps): scorched burn drums, 1 part each, no light, no particles
	local cols = if fire then { PAL.Burnt, PAL.Rust, PAL.Burnt } else { PAL.DrumOlive, PAL.DrumRed, PAL.DrumBlue }
	local k0 = b.Rng:NextInteger(0, 2)
	for i = 1, n do
		local s = DRUM_SLOTS[i]
		vcyl(b, if fire then "FireDrum" else "OilDrum", s[1], 0, s[2], 2.2, 1.5, cols[(k0 + i - 1) % 3 + 1], if fire then M.CorrodedMetal else M.Metal, true)
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
	elseif v == "gun" then
		-- W3 step 2: a wrecked field gun (shield plate, split trail, barrel cocked up toward -X); collidables at z >= 0
		put(b, "WreckGunShield", Vector3.new(0.3, 2.6, 3.4), CFrame.new(-1.2, 1.3, 3.0) * rotY(4), rust, cm, true)
		put(b, "WreckGunTrail", Vector3.new(5.5, 0.6, 1.0), CFrame.new(1.8, 0.3, 3.0) * rotY(8), burnt, cm, true)
		put(b, "WreckGunBarrel", Vector3.new(5.2, 0.5, 0.5), CFrame.new(-3.8, 2.05, 3.0) * rotZ(-10), burnt, cm, false, false, Enum.PartType.Cylinder)
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
local warnedStep2: { [string]: boolean } = {} -- reserved kits (Specs row, no builder) and unknown ids: warned once

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
			warn(if s == nil then "[WorldKits] unknown kit " .. kitId else "[WorldKits] kit " .. kitId .. " is reserved (no builder yet)")
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

-- the mesh's frame and size inside a kit box: a WE_KitYaw quarter turn (90 / 180 / 270, or -90) turns the piece,
-- and an odd one swaps the box's X and Z so the piece's long axis lies on the kit's
local function yawedBox(m: BasePart, boxCf: CFrame, size: Vector3): (CFrame, Vector3)
	local yaw = tonumber(m:GetAttribute("WE_KitYaw")) or 0
	if yaw % 90 ~= 0 then
		return boxCf, size
	end
	local q = math.floor(yaw / 90 + 0.5) % 4
	if q == 0 then
		return boxCf, size
	end
	local cf = boxCf * CFrame.Angles(0, math.rad(q * 90), 0)
	if q % 2 == 1 then
		return cf, Vector3.new(size.Z, size.Y, size.X)
	end
	return cf, size
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
			local meshCf, meshSize = yawedBox(m, boxCf, size)
			m.CFrame = meshCf
			m.Size = meshSize
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
		local meshCf, meshSize = yawedBox(m, boxCf, size)
		m.CFrame = meshCf
		m.Size = meshSize
		m.Name = ov.Key .. "Mesh"
		m.Parent = cluster -- 1 collider + 1 mesh replace n >= 2 parts
	end
end

-- ceil(cap / the number of distinct wired mesh keys in Specs), computed once (config lookups only, never yields)
local function shareOfCap(isWired: (string) -> boolean, cap: number): number
	local share = keyShare
	if share == nil then
		local seen: { [string]: boolean } = {}
		local n = 0
		for _, sp in pairs(WorldKits.Specs) do
			local key = sp.Mesh
			if key ~= nil and not seen[key] then
				seen[key] = true
				local ok, w = pcall(isWired, key)
				if ok and w == true then
					n += 1
				end
			end
		end
		share = if n > 0 then math.ceil(cap / n) else cap
		keyShare = share
	end
	return share :: number
end

local function scheduleOverlays(cluster: Model, list: { Overlay })
	local cap = KC.MeshOverlays
	local take: { Overlay } = {}
	-- owner list: a key that can never give a mesh (config id 0) takes no slot, and no key takes more than its share
	-- of the cap (config lookups only, never yields)
	local vasNow = getVAS()
	local isWired = if vasNow and type(vasNow.IsKitMeshWired) == "function" then vasNow.IsKitMeshWired else nil
	for _, ov in ipairs(list) do
		if overlaysQueued >= cap then
			break
		end
		if isWired then
			local okW, wired = pcall(isWired, ov.Key)
			if okW and wired == false then
				continue
			end
			if (overlaysByKey[ov.Key] or 0) >= shareOfCap(isWired, cap) then
				continue
			end
		end
		overlaysQueued += 1
		overlaysByKey[ov.Key] = (overlaysByKey[ov.Key] or 0) + 1
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

-- Test hook (headless sim): mesh overlay slots spent so far, per key, and the per-key share of the cap (nil = unset).
function WorldKits._OverlayStats(): { Queued: number, ByKey: { [string]: number }, Share: number? }
	return { Queued = overlaysQueued, ByKey = table.clone(overlaysByKey), Share = keyShare }
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
	local tw = o.Taxiway
	-- W3 step 2: keyed on R (HoldPad) and Taxiway (Runway) too
	local key = table.concat({ kitId, tostring(o.Variant), tostring(o.Count), tostring(o.Length), tostring(o.Scale), tostring(o.Width), tostring(o.Depth), tostring(o.Storeys), tostring(o.Roof), tostring(o.Lantern), tostring(o.R), if tw ~= nil then table.concat(tw, ",") else "nil" }, "|")
	local hit = footCache[key]
	if hit then
		return hit
	end
	if Builders[kitId] == nil then
		return nil
	end
	local tmp = Instance.new("Model")
	local frame = CFrame.new(0, GROUND_Y, 0)
	local b: B = {
		Cluster = tmp,
		CF = frame,
		Opts = {
			Variant = o.Variant,
			Count = o.Count,
			Length = o.Length,
			Scale = o.Scale,
			Width = o.Width,
			Depth = o.Depth,
			Storeys = o.Storeys,
			Roof = o.Roof,
			Lantern = o.Lantern,
			R = o.R,
			Taxiway = o.Taxiway,
			Light = false,
			Mesh = false,
			Seed = 1,
		},
		Parts = {},
		Rng = WorldKits.Rng(1),
		Overlays = {},
	}
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
