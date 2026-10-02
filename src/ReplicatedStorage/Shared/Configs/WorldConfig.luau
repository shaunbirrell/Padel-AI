--!strict
--[[
	WAR EMPIRE World v2 (gap/world_v2_spec.md + roadmap §1.5 corrections): the world OUTSIDE the bases.
	One source of truth for the Phase 1 modules (all under ServerScriptService/Server/Modules):
	  * WorldTerrain    — Terrain canyon edge round the ring canal + the far shore that closes the Bay (Terrain section)
	  * WorldBounds     — Persistent skyline ridges, invisible ground / air walls, seabed tint, far-shore lighthouse and
	                      stranded freighter (Skyline, Bounds, Seabed, FarShore sections)
	  * WorldAtmosphere — Lighting / Sky / Atmosphere presets and the day cycle (Atmosphere section)
	  * WorldHygiene    — rules H1–H10 over the world dressing (Hygiene section)
	plus the Phase 2 data the hook step and W3 read (POIs, Spawns, Budgets), and the W3 step 2 activity-anchor contract
	(Activity section: Server/Modules/ActivityAnchors reads the anchors, Server/Modules/POILayouts/* hold the POI rows).

	Units: world studs, +Y up, north = -Z. Desert floor (Part ground tiles) top = 0.5, plot pad top = 1.0.
	Playable dry land is inside the ring canal: x ±1760, z -1760 .. 1490 (the sea / Bay south of 1490).
	"Outward distance" (Terrain profiles) is measured from the belt's inner edge along the outward normal.

	Every number here is a start value to tune on the owner's phone (Test B).
]]

export type Band = { From: number, To: number, Min: number, Max: number } -- outward from..to; height min..max
export type Profile = {
	Skirt: Band, -- FillBlock Rock shelf, top Min..Max (the boats' +6 land probe sees it = shore brake)
	Talus: Band, -- FillBlock Ground to Min, then FillWedge rising Min -> Max (<= Terrain.MaxTalusTop)
	Face: Band, -- FillBlock Sandstone, vertical (yaw jitter only), height Min..Max by smooth noise
	FaceOverlap: number, -- the face block starts this far inside the talus, so its yaw jitter never opens a crack
	FaceYawJitter: number,
	FaceNoiseWave: number, -- studs per noise lattice cell along the edge
	StrataAt: { { number } }, -- centre height as a fraction of H: { lo, hi } per band
	StrataThick: { number }, -- { min, max }
	StrataDepth: number, -- outer skin depth (flush with the face, never a ledge)
	MesaDepth: number, -- roadmap §1.3: mesas end at most this far past the face (no back-fill wedge)
	MesaA: Band, -- From/To are measured from the face's outer end (negative From = overlaps the face: no cracks)
	MesaB: Band,
	MesaBChance: number,
	MesaBWidth: { number }, -- { min, max } along the edge
	MesaYawJitter: number,
	ButteEvery: number,
	ButteR: { number },
	ButteH: { number },
	ButteAt: number, -- centre, measured from the face's outer end (centre + R stays inside MesaDepth)
	ButteCap: number,
	AlcoveEvery: number,
	AlcoveR: { number },
	Boulders: { number }, -- { min, max } count per segment
	BoulderR: { number },
}
export type Rect = { Name: string?, X0: number, X1: number, Z0: number, Z1: number }
export type Notch = { Side: string, Out: number, Z0: number, Z1: number }
export type POI = {
	Id: string,
	Name: string,
	Kind: string,
	Rect: Rect?,
	Circle: { X: number, Z: number, R: number }?,
	Budget: number,
	Enabled: boolean?, -- W3: WorldPOI builds it (step 1: the Town only); a disabled footprint stays reserved
	Lights: number?, -- W3: PointLight cap (spec §3.1)
	Signs: number?, -- W3: painted SurfaceGui cap (world budget: Budgets.SurfaceGuis)
	-- W3 step 2 (layout POIs; the Town row sets none of these)
	Reserve: number?, -- parts kept free for runtime transients at this place: the build cap is Budget - Reserve
	LowShare: number?, -- Quality Low cap as a share of the planned Full build (default WorldDressConfig.Quality.Low.POIShare)
	Layout: string?, -- the Server/Modules/POILayouts module holding this POI's rows (keyed by Id): "Industry" | "Frontier" | "Wilds"
}
-- W3 (WorldPOI): one kit inside a Town cluster. X / Z / Yaw are local to the cluster frame (studs, degrees; the kit's
-- front is its local -Z). The optional fields are WorldKits.KitOpts.
export type KitPlace = {
	Kit: string,
	X: number,
	Z: number,
	Yaw: number?,
	Variant: string?,
	Count: number?,
	Length: number?,
	Scale: number?,
	Color: Color3?,
	Text: string?,
	Width: number?, -- TownBlock (Town v2): front width, depth, storeys, rooftop details, wall lantern
	Depth: number?,
	Storeys: number?,
	Roof: string?,
	Lantern: boolean?,
	R: number?, -- W3 step 2: HoldPad radius (studs)
	NoDetail: boolean?, -- codebot_v142: build this kit plain (WorldDetailConfig skipped; a Checkpoint then gets no guards)
}
-- A Town cluster: one Model <= 64 studs across at (X, Z) turned by Yaw (degrees; 0 = its front faces north, -Z).
-- Tier 1 = built in Quality Low and Full, 2 = Full only. Street = true: a road-side cluster (checkpoint, lamp, board)
-- tested part by part against the road lines instead of the 30-stud block margin.
export type TownCluster = {
	Id: string,
	Block: string,
	Role: string,
	Tier: number,
	X: number,
	Z: number,
	Yaw: number,
	Street: boolean?,
	InWater: boolean?, -- W3 step 2: may stand over water (gantry, jetty): sets WE_AllowInWater, skips the water keep-out
	Kits: { KitPlace },
}
export type TownRock = { Kind: string, X: number, Z: number, Radius: number, Tier: number }
-- W3 step 2: one activity anchor (an invisible tagged Attachment, 0 parts; see the Activity section). Layout and Town
-- rows are in WORLD studs; Id = "<POI>.<Site>.<Role>".
export type ActivityAnchor = {
	Id: string,
	Kind: string, -- one of Activity.Kinds
	X: number,
	Z: number,
	Yaw: number?, -- degrees, 0 = the anchor faces north (-Z); default 0
	Y: number?, -- standing surface above the desert floor (Activity.FloorY): 0 = the ground (default), 14 = a watchtower deck
	R: number?, -- zone radius (hold / console / sabotage / search / arena)
	Box: { number }?, -- vehicle: { width across, length along } of the spawn box
	Prompt: string?, -- one of Activity.Prompts: the job puts a ProximityPrompt here (Phase B)
	Part: string?, -- door: the name of the part it opens (HeistGate, BunkerDoor, BankGate)
	Requires: string?, -- a cluster Id of the same POI: stamped only when that cluster was built (Quality Low drops Tier 2)
	Probe: boolean?, -- not guaranteed clear: the job tests clearance at runtime and falls back to the nearest post
}
-- W3 step 2: an anchor stamped on every instance of a kit (Activity.CheckpointAnchors). X / Z / Yaw are local to the
-- kit's frame (front = local -Z, +X right); the anchor Id is "<POI>.<cluster Id>.<Role>".
export type AnchorTemplate = {
	Role: string,
	Kind: string,
	X: number,
	Z: number,
	Yaw: number?,
	Y: number?,
	R: number?,
	Prompt: string?,
	Part: string?,
	Probe: boolean?,
}
-- W3 step 2: a flat infrastructure strip (the airstrip runway): no cluster, built under POI_<Id>.Infra, exempt from H10
export type InfraRow = { Id: string, Kit: string, X: number, Z: number, Yaw: number, Length: number, Taxiway: { number }?, Width: number? }
-- Town buildings (owner feedback 2026-09-27): one Roblox-made mesh piece of a TownHouse style (Kits.TownHouse). Key =
-- VisualAssetConfig.DesertKit key; Size = the piece at scale 1 (the Part fallback box); Y = its bottom above the floor;
-- Z = its box centre on the kit's local Z (pieces are aligned on their 17.4-stud wall core, not on their boxes)
export type TownHousePiece = { Key: string, Size: Vector3, Y: number, Z: number }
export type TownHouseStyle = {
	Pieces: { TownHousePiece }, -- bottom to top; the first is the ground floor (the door / shutter side is local -Z)
	Front: string, -- the fallback's front detail: "door" | "shutter"
	WallFront: number, -- the ground floor's front wall plane on local Z (a wall lantern hangs 0.4 in front of it)
	Shadow: boolean, -- the building casts one shadow (its ground floor); off for the one-storey shops (Town <= 60 casters)
	Core: Vector3, -- the wall core the live collider covers: X across, Z deep (Y unused: the collider is the style's full
	-- height), measured from the pieces' wall planes, so players and shots meet the brick, not the stoop or the cornice
	CoreZ: number, -- the core's centre on local Z
	Color: Color3, -- the fallback boxes (shown only while the meshes have not loaded)
	Material: Enum.Material,
}
-- W3 step 2: one POI's rows in Server/Modules/POILayouts/<POI.Layout> (the Town keeps its rows in WorldConfig.Town)
export type POILayout = {
	Board: string?, -- the PoiBoard text (PoiBoard rows leave Text nil; painted within Signs and Budgets.SurfaceGuis)
	Clusters: { TownCluster },
	Rocks: { TownRock },
	Infra: { InfraRow }?,
	Anchors: { ActivityAnchor },
}
export type Pad = { Id: string, X: number?, Z: number?, PlotId: number?, LocalX: number?, LocalZ: number?, Yaw: number? }
export type Anchor = { Id: string, X: number, Z: number }

local M = Enum.Material

local WorldConfig = {
	-- Bump to rebuild the terrain edge and the bounds on the next server start (both are stamped with it).
	Gen = 1,

	-- ── Terrain canyon edge (WorldTerrain; spec §1.1–§1.2, roadmap §1.5 #1–#2) ────────────────────────────────
	Terrain = {
		Enabled = true,
		Seed = 70802,
		-- Workspace.Terrain:GetAttribute("WE_TerrainGen") == Gen → Build skips. A different stamp clears the terrain
		-- first (World v2 owns all terrain: nothing else in the game fills voxels).
		Gen = 2, -- 2: lane 32 toe ramp + notch hips (a server that finds Gen 1 terrain clears and refills it)
		ClearOnRegen = true,
		Decoration = false, -- no animated grass (phones)
		YieldEvery = 50, -- Build yields (task.wait) every N fills
		BuildBudgetSeconds = 5, -- logged; the owner checks it in the Output (Test B)
		MaxPrims = 2500, -- hard cap on fill calls for the edge (roadmap W1 headless check)
		MaxTalusTop = 20, -- roadmap §1.5 #1: never a ramp to the face (jump rise ~7.2)
		FootY = -4, -- every land prim starts here: under the Part ground top (0.5), above the SafetyCatch (-26)
		-- Keep-out: no voxel inside the playable ring (canal + its outer bank) …
		Ring = { X = 1846, ZMin = -1846, ZMax = 1490 },
		-- … and none inside a public water rect, except headland prims at |x| >= Edge.Inner whose top is >= this
		-- (they sit over the outer sea ends of Sea_W / Sea_E2 / Sea_E3 and hide them under rock).
		HeadlandMinTop = 2.5,
		Edge = {
			Inner = 1852, -- canal outer edge 1840 + bank 6 + beach 6
			FarShoreZ = 2234, -- sea edge 2210 + sea bank 24
			-- Rig lagoons: the skirt steps out to the lagoon edge + bank 6 + 6, so the cliffs wrap round each rig.
			Notches = {
				{ Side = "E", Out = 1902, Z0 = -846, Z1 = -654 }, -- Lagoon_Alpha z -840..-660
				{ Side = "W", Out = 1902, Z0 = 654, Z1 = 846 }, -- Lagoon_Bravo
			} :: { Notch },
			SegmentMin = 60,
			SegmentMax = 140,
			Overlap = 8, -- each segment's prims reach this far past its ends (no seams); never past a run end
			CornerSegments = 6, -- quarter circle at each of the 4 outer corners
			CornerButteR = { 45, 55 },
			CornerButteH = { 320, 340 },
		},
		-- Canal / sea-cliff profile (east, west, north). Heights are world Y of the top. Toe and talus = the far shore's
		-- (lane 32: one ramp 0 -> 8 over 26 studs (17°), then the talus at 0.4 (22°) to the face foot, y 12 here): the
		-- far-shore corner fans use this profile, so any difference would be a step where they meet the far shore.
		Side = {
			Skirt = { From = 0, To = 26, Min = 2.5, Max = 5.5 },
			Talus = { From = 26, To = 56, Min = 8, Max = 20 },
			Face = { From = 48, To = 108, Min = 90, Max = 150 },
			FaceOverlap = 12,
			FaceYawJitter = 6,
			FaceNoiseWave = 420,
			StrataAt = { { 0.30, 0.40 }, { 0.62, 0.72 } },
			StrataThick = { 8, 14 },
			StrataDepth = 4,
			MesaDepth = 120,
			MesaA = { From = -24, To = 62, Min = 160, Max = 220 },
			MesaB = { From = 40, To = 120, Min = 200, Max = 300 },
			MesaBChance = 0.8,
			MesaBWidth = { 50, 180 },
			MesaYawJitter = 8,
			ButteEvery = 4,
			ButteR = { 25, 45 },
			ButteH = { 260, 340 },
			ButteAt = 72,
			ButteCap = 8,
			AlcoveEvery = 5,
			AlcoveR = { 18, 30 },
			Boulders = { 1, 3 },
			BoulderR = { 3, 9 },
		} :: Profile,
		-- Lane 32: the skirt band (Profile.Skirt From..To) is a drivable toe, not a shelf: a Rock FillWedge from Toe.Y up
		-- to the talus foot (Talus.Min at Talus.From = Skirt.To) on a support block FootY..Toe.Y. Skirt Min / Max are no
		-- longer heights (still rolled: the seeded stream is unchanged). The old 2.5–5.5 shelf edge tripped vehicles.
		Toe = {
			Y = 0, -- the ramp's low edge, under the Part ground top (0.5): the rock grows out of the sand with no lip
			BuriedTop = 0.5, -- a prim whose top is at or under the Part ground is buried (Check lets it lie under water)
			HipClear = 24, -- notch run-end hip carves clear this far above the talus (boulder caps)
		},
		-- The Bay's far shore (south of the sea): beach skirt, sea cliffs 80–160, mesas 140–260.
		FarShore = {
			Skirt = { From = 0, To = 26, Min = 2.5, Max = 5.5 },
			Talus = { From = 26, To = 56, Min = 8, Max = 20 },
			Face = { From = 56, To = 116, Min = 80, Max = 160 },
			FaceOverlap = 12,
			FaceYawJitter = 6,
			FaceNoiseWave = 380,
			StrataAt = { { 0.30, 0.40 }, { 0.62, 0.72 } },
			StrataThick = { 8, 14 },
			StrataDepth = 4,
			MesaDepth = 120,
			MesaA = { From = -24, To = 62, Min = 140, Max = 200 },
			MesaB = { From = 40, To = 120, Min = 180, Max = 260 },
			MesaBChance = 0.8,
			MesaBWidth = { 50, 180 },
			MesaYawJitter = 8,
			ButteEvery = 4,
			ButteR = { 25, 45 },
			ButteH = { 240, 300 },
			ButteAt = 72,
			ButteCap = 8,
			AlcoveEvery = 5,
			AlcoveR = { 18, 30 },
			Boulders = { 1, 3 },
			BoulderR = { 3, 9 },
		} :: Profile,
		-- Sand slabs over the outer sea ends (Sea_W / Sea_E2 / Sea_E3 beyond the headlands), starting inside the belt
		-- (x ±1900, under the face) so no open water shows between or behind the mesas from the air. Top above the
		-- water surface (1.5). WaterConfig is not edited.
		SeaCover = {
			Top = 2.8,
			Rects = {
				{ Name = "SeaCover_W", X0 = -3264, X1 = -1900, Z0 = 1466, Z1 = 2234 },
				{ Name = "SeaCover_E", X0 = 1900, X1 = 3264, Z0 = 1466, Z1 = 2234 },
			} :: { Rect },
		},
		-- Rock pad the far-shore lighthouse stands on (WorldBounds builds the tower on top of it).
		LighthousePad = { X = -1300, Z = 2252, Half = 18, Top = 6 },
		Materials = {
			Skirt = M.Rock,
			Talus = M.Ground,
			Face = M.Sandstone,
			Strata = { M.Limestone, M.Slate },
			Mesa = { M.Sandstone, M.Sandstone, M.Limestone },
			Butte = M.Sandstone,
			ButteCap = M.Slate,
			Boulder = M.Rock,
			Cover = M.Sand,
		},
		-- Terrain:SetMaterialColor, once. Sand = MapSetup COL_GROUND so terrain meets the Part ground with no seam.
		Colors = {
			{ Material = M.Sand, Color = Color3.fromRGB(210, 185, 130) },
			{ Material = M.Sandstone, Color = Color3.fromRGB(176, 104, 66) },
			{ Material = M.Limestone, Color = Color3.fromRGB(222, 200, 160) },
			{ Material = M.Slate, Color = Color3.fromRGB(118, 92, 78) },
			{ Material = M.Rock, Color = Color3.fromRGB(134, 94, 72) },
			{ Material = M.Ground, Color = Color3.fromRGB(168, 128, 88) },
			{ Material = M.Basalt, Color = Color3.fromRGB(80, 68, 60) },
			{ Material = M.Salt, Color = Color3.fromRGB(228, 218, 196) },
		},
	},

	-- ── Skyline back range (WorldBounds; spec §1.3) ───────────────────────────────────────────────────────────
	Skyline = {
		Name = "WE_Skyline", -- Model under WarEmpireSetup, ModelStreamingMode = Persistent
		Seed = 70311,
		RInner = 2700, -- square ring: |x| or |z| between RInner and ROuter
		ROuter = 3300,
		PerSide = 4, -- 16 ridges x 3 parts = 48
		HeightMin = 340,
		HeightMax = 420,
		BodyShare = 0.62, -- body / slope height as a share of the peak height
		SlopeDepth = 200, -- front WedgePart (rises outward) from RInner
		PeakLength = { 0.35, 0.6 }, -- share of the ridge length
		YawJitter = 5,
		Overlap = 40,
		Material = M.Sandstone,
		-- darker and bluer than the belt (aerial perspective), so the two read as two ranges
		Colors = {
			Body = Color3.fromRGB(128, 86, 66),
			Slope = Color3.fromRGB(136, 94, 74),
			Peak = Color3.fromRGB(112, 80, 68),
		},
	},

	-- ── Bounds (WorldBounds; spec §1.4) ────────────────────────────────────────────────────────────────────────
	Bounds = {
		Folder = "WE_Bounds",
		-- Invisible, collidable, CanQuery / CanTouch / CastShadow off: raycasts, probes and shots ignore them.
		GroundWall = { X = 1960, ZMin = -1960, ZMax = 2300, Height = 400, Thick = 4, MaxPiece = 2000 }, -- 10 parts
		AirWall = { X = 2050, ZMin = -2050, ZMax = 2350, Height = 700, Thick = 4, MaxPiece = 2000 }, -- 12 parts
		-- Hand-off to the vehicles workflow (JEEP-2): heli / plane laws steer back and show "Restricted airspace"
		-- outside this box or above MaxY. The air wall is the backstop.
		Air = { X = 2050, ZMin = -2050, ZMax = 2350, MaxY = 360 },
		-- Hook step (MapSetup.buildSafetyUnderfloor): the SafetyCatch tiles become opaque sand.
		SafetyCatch = { Transparency = 0, Material = M.Sand, Color = Color3.fromRGB(196, 170, 120) },
	},

	-- ── Seabed depth tint (WorldBounds; spec §1.5) ─────────────────────────────────────────────────────────────
	Seabed = {
		-- Above every Waterways bank top (0.58 + 0.004 per rect, <= 0.672 with 24 rects) and inside the water
		-- volume (0.3 .. 1.5). No physics.
		Y0 = 0.68,
		Y1 = 0.70,
		Color = Color3.fromRGB(38, 86, 110),
		Material = M.SmoothPlastic,
		Rects = {
			-- deep band in the Bay, 70 in from the north shore (1490) and 50 from the far bank (2210)
			{ Name = "SeabedTint_Bay_W", X0 = -1790, X1 = 0, Z0 = 1560, Z1 = 2160 },
			{ Name = "SeabedTint_Bay_E", X0 = 0, X1 = 1790, Z0 = 1560, Z1 = 2160 },
			-- 40-wide stripe down the centre of each ring-canal side (the side stripes own the corners)
			{ Name = "SeabedTint_N_W", X0 = -1780, X1 = 0, Z0 = -1820, Z1 = -1780 },
			{ Name = "SeabedTint_N_E", X0 = 0, X1 = 1780, Z0 = -1820, Z1 = -1780 },
			{ Name = "SeabedTint_W_N", X0 = -1820, X1 = -1780, Z0 = -1820, Z1 = -165 },
			{ Name = "SeabedTint_W_S", X0 = -1820, X1 = -1780, Z0 = -165, Z1 = 1490 },
			{ Name = "SeabedTint_E_N", X0 = 1780, X1 = 1820, Z0 = -1820, Z1 = -165 },
			{ Name = "SeabedTint_E_S", X0 = 1780, X1 = 1820, Z0 = -165, Z1 = 1490 },
		} :: { Rect },
	},

	-- ── Far-shore landmarks (WorldBounds; spec §1.1): Part kits, 22 parts ───────────────────────────────────────
	FarShore = {
		Lighthouse = {
			X = -1300,
			Z = 2252,
			BaseY = 6, -- = Terrain.LighthousePad.Top
			Yaw = 0,
			-- one SpotLight, on only at night (tag WE_NightLight; WorldAtmosphere toggles it), aimed over the Bay
			Light = { Brightness = 0.8, Range = 18, Angle = 70, Color = Color3.fromRGB(255, 236, 190) },
		},
		Freighter = {
			X = 600,
			Z = 2222, -- stern in the Bay, bow on the far beach
			Yaw = 20, -- degrees; the bow (hull +Z) points south-south-east, up the far beach
			Pitch = 8, -- bow up
			Roll = 3,
		},
	},

	-- ── Atmosphere and lighting (WorldAtmosphere; spec §2, roadmap §1.3 / §1.6) ─────────────────────────────────
	Atmosphere = {
		-- One-line revert for Test B: "Classic" = the pre-v2 look (blue Decay below the horizon, light haze).
		Preset = "V2",
		DayLengthMinutes = 20,
		StepSeconds = 6, -- one day-cycle step every 6 s (was 1.5 s); steps are 4x larger, same 20-minute day
		StartClock = 12.5,
		-- night share: 1 before NightEnd / after NightStart, ramps over DawnHours / DuskHours
		NightEnd = 5,
		DawnEnd = 7,
		DuskStart = 18,
		NightStart = 20,
		NightLightTag = "WE_NightLight", -- lights with this tag are Enabled only while night > 0.5
		Lighting = {
			GeographicLatitude = 22,
			EnvironmentSpecularScale = 0.42,
			-- HUD spec §5 (agent F's numbers): day Ambient (78,72,62) + EnvironmentDiffuseScale 0.35 fix the washed-out
			-- interiors. StructureVisualConfig.WorldLighting (the in-base knob) overrides these two when present.
			EnvironmentDiffuseScale = 0.35,
			GlobalShadows = true,
		},
		Sky = { StarCount = 2500, SunAngularSize = 18, MoonAngularSize = 9 },
		Presets = {
			V2 = {
				Day = {
					Brightness = 3.2,
					Ambient = Color3.fromRGB(78, 72, 62),
					OutdoorAmbient = Color3.fromRGB(185, 165, 130),
					Density = 0.30,
					Offset = 0.22, -- silhouettes the canyon; less sky "ghosting" through far terrain
					Color = Color3.fromRGB(199, 178, 140), -- warm dust
					Decay = Color3.fromRGB(150, 122, 92), -- warm: no blue below the horizon
					Glare = 0.25,
					Haze = 1.8,
				},
				Night = {
					Brightness = 1.6, -- floor: phones never go black
					Ambient = Color3.fromRGB(40, 45, 70),
					OutdoorAmbient = Color3.fromRGB(50, 55, 85),
					Density = 0.36,
					Offset = 0.22,
					Color = Color3.fromRGB(70, 80, 110),
					Decay = Color3.fromRGB(40, 48, 80),
					Glare = 0.1,
					Haze = 2.4,
				},
			},
			Classic = { -- MapSetup.Run before World v2 (fog writes dropped: Atmosphere hides them anyway)
				Day = {
					Brightness = 3.2,
					Ambient = Color3.fromRGB(78, 72, 62),
					OutdoorAmbient = Color3.fromRGB(185, 165, 130),
					Density = 0.13,
					Offset = 0.08,
					Color = Color3.fromRGB(200, 185, 150),
					Decay = Color3.fromRGB(95, 130, 190),
					Glare = 0.32,
					Haze = 1.1,
				},
				Night = {
					Brightness = 1.1,
					Ambient = Color3.fromRGB(40, 45, 70),
					OutdoorAmbient = Color3.fromRGB(50, 55, 85),
					Density = 0.27,
					Offset = 0.08,
					Color = Color3.fromRGB(70, 80, 120),
					Decay = Color3.fromRGB(40, 50, 90),
					Glare = 0.12,
					Haze = 2.1,
				},
			},
		},
	},

	-- ── Lights outside the bases (spec §2 lights policy; WorldHygiene H8) ──────────────────────────────────────
	Lights = {
		MaxWorld = 24,
		MaxBrightness = 0.8,
		MaxRange = 18,
		Shadows = false,
		LampHeadColor = Color3.fromRGB(255, 236, 190), -- SmoothPlastic lamp heads, never Neon
	},

	-- ── Hygiene rules H1–H10 (WorldHygiene; spec §5.1, roadmap §1.5 #3) ────────────────────────────────────────
	Hygiene = {
		-- W3: H1 enforced (roadmap §1.5 #3)
		OrphanMode = "Enforce",
		-- Folders under WarEmpireSetup whose contents are world dressing (Enforce acts ONLY inside these).
		DressingFolders = { "WorldDressing", "DesertFlora", "WorldPOI", "WorldKits" },
		-- Never inspected as world parts (bases) / never mutated.
		BaseFolders = { "Bases" },
		-- Built by World v2 itself: exempt from H1 / H4 / H10 (designed pieces, Persistent skyline).
		WorldV2Folders = { "WE_Skyline", "WE_Bounds" },
		-- MapSetup blocks the hook step deletes (spec §1.6); Report counts their parts as "legacy".
		LegacyFolders = { "MountainRing", "NPCPlaceholders", "OilSpectacle", "WarzoneLandmarks" },
		-- H1 anchor distance (studs) to a POI footprint, road centre line, water edge or plot edge
		AnchorMax = 60,
		-- H1: natural clusters may stand alone as >= MinNatural elements within NaturalLink studs of each other
		MinNatural = 3,
		NaturalLink = 40,
		NaturalPrefixes = { "Palm", "Joshua", "Saguaro", "Barrel", "Grass", "Flora", "DesertRock", "WE_CatalogProp_DesertRock", "Rock", "Outcrop", "Mesa", "Cactus", "Bush", "Shrub", "Boulder", "Dune", "DeadTree", "Stump", "FallenLog", "Reed", "Driftwood" },
		-- W3: the cluster attribute holding a natural cluster's element count (terrain rocks included)
		ElementsAttr = "WE_Elements",
		NaturalFolders = { "DesertFlora" },
		-- H2 road corridor (roads = WaterConfig.RoadEnds centre lines)
		RoadCorridor = 12, -- nothing collidable with its top above RoadMinTop (lane 7 + shoulder 5)
		RoadMinTop = 0.75,
		RoadLane = 8, -- nothing visible taller than 0.5 + RoadLaneMaxHeight
		RoadLaneMaxHeight = 0.3,
		RoadMarkingPrefixes = { "RoadCrater", "RoadChevron", "AsphaltStrip", "ChevronWedge", "RoadDash", "WreckScorch" },
		RoadExemptAncestors = { "RoadEnds" },
		RoadExemptNames = { "CheckpointArm" },
		-- whole kit = nearest Model / kit Folder below the dressing folder when it spans <= KitMaxSpan (XZ)
		KitMaxSpan = 64,
		-- H3 clear zones
		CaptureClearScale = 1.414, -- TerritoryCapture uses the marker half-diagonal
		CaptureClearExtra = 25,
		CaptureSkip = { "CoastalOilAlpha", "CoastalOilBravo" }, -- rigs stand in water: the water rule covers them
		GateApron = { X0 = -45, X1 = 45, Z0 = 160, Z1 = 220 }, -- plot-local (+Z = front / main gate)
		PadClear = 16, -- round every land WE_VehicleSpawn pad
		PlotPadClear = 4, -- same as Waterways.CullDressing
		WaterClear = 6,
		ClearRects = {
			{ Name = "RigPier_Alpha", X0 = 1640, X1 = 1780, Z0 = -770, Z1 = -730 },
			{ Name = "RigPier_Bravo", X0 = -1780, X1 = -1640, Z0 = 730, Z1 = 770 },
		} :: { Rect },
		-- H4 cover is solid: man-made parts matching SolidKeywords (and none of SoftKeywords), >= SolidMinHeight tall
		-- (part or its kit), visible, not a MeshPart (meshes collide through their host part)
		SolidMinHeight = 1.5,
		SolidKeywords = { "Crate", "Drum", "Sandbag", "Wall", "Wreck", "Container", "Tank", "Booth", "Stall", "Hull", "Bunker", "Hesco", "Barrier", "Jersey", "Adobe", "Ruin", "Shed", "Hut", "Hangar", "Cabin", "Barricade", "Debris", "Decoy", "Truck", "Car" },
		SoftKeywords = { "Frond", "Leaf", "Crown", "Tarp", "Canopy", "Cloth", "Flag", "Wire", "GuyLine", "Cable", "Arm", "Lamp", "Marking", "Stripe", "Dash", "Chevron", "Scorch", "Accent", "Window", "Door", "Roof", "Glow", "Light", "Host", "Label", "Anchor", "Stake", "Grass", "Net", "Wheel", "Turret", "Barrel" },
		-- H5 world-code BillboardGuis: allowed only under these (service labels owned by agent F / the tutorial)
		BillboardAllowAncestors = { "Territories", "EmpireBank", "TutorialMarkers" },
		-- H7
		MaxPartSize = 2040,
		-- H9
		ShadowMinSize = 8,
		MaxShadowCasters = 300,
		-- H10
		MaxModelSpan = 64,
	},

	-- ── Budgets (spec §7.1; CLAUDE.md hard cap 3,100 world parts outside the bases) ─────────────────────────────
	Budgets = {
		PartsOutsideBasesFull = 2900,
		PartsOutsideBasesLow = 1900,
		HardCap = 3100,
		Lights = 24,
		-- W3 step 2: 6 gate-pad garage signs + the Town board + EMPIRE BANK + 9 POI boards (the 4 pool-pad labels go
		-- with lane BK; the CLAUDE.md game-wide cap of 1,134 SurfaceGuis is unaffected)
		SurfaceGuis = 17,
		ShadowCasters = 300,
		TerrainEdgePrims = 2500,
		SkylineParts = 48,
		BoundsParts = 52, -- walls 22 + tint 8 + far shore 22
	},

	-- ── Phase 2 data (W3 builds the POIs; H1 already uses the footprints as anchors) ────────────────────────────
	-- W3 step 2 (spec w3s2 §6): the 17 rows carry the geometry plan's Budget / Reserve / Lights / Signs / Layout
	-- (LowShare 0.75 on the small places) and stay Enabled = false until their enable step (lane P flips them:
	-- 1 = Port, Depot, Armory, OilField, RigA, RigB + Quarry, RidgeCamp, DuneCamp; 2 = Signal, Airstrip, Radar, FortI,
	-- FortS; 3 = Ruins, Crash, Oasis). A disabled footprint stays reserved (WorldDress keeps out). The comment on each
	-- row is the geometry model's planned Full (Low) part count, not a measured one.
	POIs = {
		{ Id = "Town", Name = "Crossroads Town", Kind = "town", Rect = { X0 = -330, X1 = 330, Z0 = -330, Z1 = 330 }, Budget = 370, Enabled = true, Lights = 8, Signs = 1 }, -- Town v2: 370 keeps every 512 circle <= 500 (spec 7.1)
		{ Id = "Depot", Name = "West Supply Depot", Kind = "depot", Rect = { X0 = -1500, X1 = -1110, Z0 = -200, Z1 = 200 }, Budget = 120, Reserve = 6, Enabled = true, Lights = 2, Signs = 1, Layout = "Industry" }, -- geometry model: builds 114 (Low 67)
		{ Id = "Armory", Name = "East Armory", Kind = "armory", Rect = { X0 = 1110, X1 = 1500, Z0 = -200, Z1 = 200 }, Budget = 115, Reserve = 6, Enabled = true, Lights = 2, Signs = 1, Layout = "Industry" }, -- geometry model: builds 106 (Low 59)
		{ Id = "Signal", Name = "North Ridge Signal Station", Kind = "signal", Rect = { X0 = -280, X1 = 90, Z0 = -1480, Z1 = -1120 }, Budget = 75, Reserve = 4, Enabled = true, Lights = 1, Signs = 1, Layout = "Frontier" }, -- geometry model: builds 71 (Low 40)
		{ Id = "Port", Name = "South Port", Kind = "port", Rect = { X0 = -330, X1 = 330, Z0 = 1150, Z1 = 1466 }, Budget = 140, Reserve = 8, Enabled = true, Lights = 3, Signs = 1, Layout = "Industry" }, -- geometry model: builds 129 (Low 76)
		{ Id = "OilField", Name = "Oil Field", Kind = "oil", Rect = { X0 = 830, X1 = 1230, Z0 = 830, Z1 = 1230 }, Budget = 85, Reserve = 6, Enabled = true, Lights = 0, Signs = 1, Layout = "Industry" }, -- geometry model: builds 76 (Low 43)
		{ Id = "Radar", Name = "Radar Hill", Kind = "radar", Circle = { X = -950, Z = -950, R = 130 }, Budget = 33, Reserve = 2, Enabled = true, Lights = 0, Signs = 0, Layout = "Frontier", LowShare = 0.75 }, -- geometry model: builds 27 (Low 16)
		{ Id = "FortI", Name = "Fort Ironclad approach", Kind = "fort", Circle = { X = 1450, Z = -1450, R = 230 }, Budget = 53, Reserve = 2, Enabled = true, Lights = 0, Signs = 0, Layout = "Frontier", LowShare = 0.75 }, -- geometry model: builds 50 (Low 36)
		{ Id = "FortS", Name = "Fort Sandhold approach", Kind = "fort", Circle = { X = -1450, Z = 1450, R = 200 }, Budget = 53, Reserve = 2, Enabled = true, Lights = 0, Signs = 0, Layout = "Frontier", LowShare = 0.75 }, -- geometry model: builds 50 (Low 36)
		{ Id = "RigA", Name = "Rig Alpha shore base", Kind = "rigshore", Rect = { X0 = 1540, X1 = 1698, Z0 = -880, Z1 = -620 }, Budget = 40, Reserve = 2, Enabled = true, Lights = 0, Signs = 0, Layout = "Industry", LowShare = 0.75 }, -- geometry model: builds 34 (Low 23)
		{ Id = "RigB", Name = "Rig Bravo shore base", Kind = "rigshore", Rect = { X0 = -1698, X1 = -1540, Z0 = 620, Z1 = 880 }, Budget = 40, Reserve = 2, Enabled = true, Lights = 0, Signs = 0, Layout = "Industry", LowShare = 0.75 }, -- geometry model: builds 34 (Low 23)
		{ Id = "Airstrip", Name = "Desert Airstrip", Kind = "airstrip", Rect = { X0 = 240, X1 = 780, Z0 = -1380, Z1 = -1150 }, Budget = 85, Reserve = 6, Enabled = true, Lights = 2, Signs = 1, Layout = "Frontier" }, -- geometry model: builds 77 (Low 46)
		{ Id = "Ruins", Name = "Ruined Village", Kind = "ruins", Circle = { X = -540, Z = -1320, R = 190 }, Budget = 85, Reserve = 4, Enabled = true, Lights = 0, Signs = 1, Layout = "Wilds" }, -- geometry model: builds 78 (Low 43)
		{ Id = "Quarry", Name = "Quarry Camp", Kind = "camp", Circle = { X = -1380, Z = -1380, R = 220 }, Budget = 55, Reserve = 4, Enabled = true, Lights = 0, Signs = 0, Layout = "Wilds", LowShare = 0.75 }, -- geometry model: builds 49 (Low 30)
		{ Id = "RidgeCamp", Name = "Ridge Camp", Kind = "camp", Circle = { X = 1420, Z = -1060, R = 150 }, Budget = 45, Reserve = 4, Enabled = true, Lights = 0, Signs = 0, Layout = "Wilds", LowShare = 0.75 }, -- geometry model: builds 37 (Low 23)
		{ Id = "DuneCamp", Name = "Dune Camp", Kind = "camp", Circle = { X = 1450, Z = 1200, R = 160 }, Budget = 40, Reserve = 4, Enabled = true, Lights = 0, Signs = 0, Layout = "Wilds", LowShare = 0.75 }, -- geometry model: builds 31 (Low 23)
		{ Id = "Crash", Name = "Crash Site", Kind = "crash", Circle = { X = -540, Z = 1140, R = 165 }, Budget = 45, Reserve = 4, Enabled = true, Lights = 0, Signs = 1, Layout = "Wilds", LowShare = 0.75 }, -- geometry model: builds 38 (Low 26)
		{ Id = "Oasis", Name = "Oasis", Kind = "oasis", Circle = { X = -1300, Z = 560, R = 125 }, Budget = 60, Reserve = 2, Enabled = true, Lights = 2, Signs = 1, Layout = "Wilds" }, -- geometry model: builds 55 (Low 31)
	} :: { POI },

	-- ── W3 kit catalogue tunables (Server/Modules/WorldKits; spec §4.5). Our own Part kits: no brand, no insignia ──
	Kits = {
		Palette = {
			Adobe = Color3.fromRGB(185, 150, 105),
			AdobeDark = Color3.fromRGB(155, 120, 80),
			AdobeLight = Color3.fromRGB(204, 176, 132),
			AdobeRose = Color3.fromRGB(190, 138, 104),
			TarpRed = Color3.fromRGB(160, 70, 55),
			TarpBlue = Color3.fromRGB(70, 95, 120),
			TarpSand = Color3.fromRGB(190, 160, 90),
			Burnt = Color3.fromRGB(45, 42, 40),
			Rust = Color3.fromRGB(112, 66, 44),
			Concrete = Color3.fromRGB(85, 85, 78),
			ConcreteLight = Color3.fromRGB(148, 144, 132),
			Sandbag = Color3.fromRGB(130, 115, 80),
			SandbagLight = Color3.fromRGB(150, 133, 94),
			Hazard = Color3.fromRGB(230, 190, 60),
			HazardDark = Color3.fromRGB(38, 38, 34),
			LampLens = Color3.fromRGB(255, 236, 190),
			Wood = Color3.fromRGB(105, 82, 55),
			WoodDark = Color3.fromRGB(72, 56, 38),
			Crate = Color3.fromRGB(118, 94, 60),
			CrateOlive = Color3.fromRGB(78, 86, 58),
			Steel = Color3.fromRGB(74, 72, 66),
			SteelDark = Color3.fromRGB(52, 54, 52),
			TankCream = Color3.fromRGB(184, 170, 142),
			DrumOlive = Color3.fromRGB(70, 85, 55),
			DrumRed = Color3.fromRGB(150, 62, 42),
			DrumBlue = Color3.fromRGB(58, 72, 88),
			Window = Color3.fromRGB(58, 76, 90),
			ClockFace = Color3.fromRGB(232, 222, 196),
			Paving = Color3.fromRGB(176, 160, 132),
			PavingDark = Color3.fromRGB(160, 144, 116),
			SignBoard = Color3.fromRGB(50, 55, 45),
			Cactus = Color3.fromRGB(62, 110, 58),
			CactusLight = Color3.fromRGB(78, 130, 72),
			JoshuaTrunk = Color3.fromRGB(95, 78, 52),
			JoshuaLeaf = Color3.fromRGB(70, 95, 45),
			DeadWood = Color3.fromRGB(122, 106, 86),
			Driftwood = Color3.fromRGB(176, 166, 146),
			Reed = Color3.fromRGB(122, 128, 70),
			DuneGrass = Color3.fromRGB(178, 152, 92),
			Hull = Color3.fromRGB(70, 95, 120),
			HullLight = Color3.fromRGB(190, 180, 160),
			-- W3 step 2 kits (lane K may use or ignore these; never Neon)
			Metal = Color3.fromRGB(128, 132, 124), -- corrugated sheds (TownBlock "metal", Hangar)
			MetalDark = Color3.fromRGB(92, 96, 90),
			Aluminium = Color3.fromRGB(168, 170, 166), -- plane / heli wrecks
			RadarWhite = Color3.fromRGB(214, 212, 204),
			Canvas = Color3.fromRGB(150, 138, 104), -- tents
			PalmTrunk = Color3.fromRGB(120, 96, 66),
			PalmFrond = Color3.fromRGB(88, 120, 60),
			Asphalt = Color3.fromRGB(62, 60, 56), -- runway
			RunwayPaint = Color3.fromRGB(224, 220, 206),
			PadPaint = Color3.fromRGB(214, 176, 72), -- HoldPad disc (hold zones)
			PondWater = Color3.fromRGB(58, 104, 118), -- the Oasis pond (HoldPad "pond")
		},
		-- StreetLamp night PointLight (H8: Brightness <= 0.8, Range <= 18, Shadows off, tag WE_NightLight)
		Lamp = { Brightness = 0.6, Range = 16, Color = Color3.fromRGB(255, 236, 190) },
		SignMaxDistance = 80, -- painted SurfaceGui signs (CLAUDE.md: <= 80)
		MeshOverlays = 40, -- per-server cap on deferred Roblox-owned mesh overlays (VisualAssetService.CloneKitMesh)
		-- WorldKits.Rock defaults: Radius = the group's outer radius (callers test WorldDress.Blocked with it)
		Rock = {
			outcrop = { Radius = 12, Count = { 2, 4 }, R = { 4, 9 } },
			boulders = { Radius = 10, Count = { 3, 6 }, R = { 2, 5 } },
			rubble = { Radius = 8, Count = { 2, 4 }, R = { 2, 4 } },
			scorch = { Radius = 9, Count = { 1, 1 }, R = { 0, 0 } },
		},
		-- W3 step 2 kit contracts (lane K builds to these; the POI layouts rely on them)
		HoldPad = { R = 10, MinR = 3, MaxR = 24, Top = 0.13 }, -- 1 flat disc, no collision: top 0.63 world (<= RoadMinTop)
		Runway = { Width = 40, Top = 0.12, TaxiwayWidth = 20 }, -- infra strips (flat, no collision, top <= 0.62 world)
		WatchtowerDeckY = 14, -- Watchtower deck top above the floor: anchors with Y = 14 stand on it
		--[[ Town buildings (owner feedback 2026-09-27: "need to be actual Roblox buildings"). Kit TownHouse, Variant =
			a style below. Every piece is a Roblox-made Synty City Pack piece (6933556508, creator Roblox, User 1; already
			loaded live for DesertKit.CarWreck: 0 new load attempts), kept at scale 1 (11-stud storeys, 8-stud doors) with
			its own texture atlas (windows, brick, stone). The Part fallback is one box per piece + one front detail, so the
			census counts exactly what the live overlay leaves: 1 invisible box collider + one mesh per piece. The
			overlay is deferred and all-or-nothing per building (a failed load keeps the Part fallback). Overlays = the
			building overlays one server may apply (their own cap: MeshOverlays stays with the travel dressing);
			MeshShadow = the ground-floor mesh of a style with Shadow casts the building's one shadow (as the Part kits:
			<= 60 casters in the Town). MeshCollide = the placed pieces collide and are queryable (Default collision
			group, never Touched) so Roblox's Poppercam stops the camera at the brick instead of passing through the
			invisible wall-core collider; false = the round-0 look-only pieces (the camera then goes through walls). ]]
		TownHouse = {
			Overlays = 64,
			MeshShadow = true,
			MeshCollide = true,
			Styles = {
				-- one-storey shop with a rolled shutter and a side door (264 tris)
				shop = {
					Pieces = { { Key = "TownShop", Size = Vector3.new(18, 11, 20.45), Y = 0, Z = 0 } },
					Front = "shutter",
					WallFront = -7.4,
					Shadow = false,
					Core = Vector3.new(17.2, 0, 17.4),
					CoreZ = 1.3,
					Color = Color3.fromRGB(116, 100, 88),
					Material = Enum.Material.Concrete,
				},
				-- two-storey red-brick walk-up: stoop door floor, arched upper floor, flat roof (1,801 tris)
				walkup = {
					Pieces = {
						{ Key = "TownAptDoorA", Size = Vector3.new(17.74, 11, 19.41), Y = 0, Z = -0.9 },
						{ Key = "TownAptFloorA", Size = Vector3.new(17.99, 11.02, 18.14), Y = 11, Z = -0.1 },
						{ Key = "TownAptRoofA", Size = Vector3.new(18.48, 2, 20.59), Y = 22.02, Z = 0 },
					},
					Front = "door",
					WallFront = -8.7,
					Shadow = true,
					Core = Vector3.new(17.6, 0, 17.4),
					CoreZ = 0,
					Color = Color3.fromRGB(150, 74, 58),
					Material = Enum.Material.Brick,
				},
				-- two-storey red-brick walk-up: plain door floor, bay-window upper floor, cornice roof (1,280 tris)
				walkupB = {
					Pieces = {
						{ Key = "TownAptDoorB", Size = Vector3.new(17.8, 11, 17.8), Y = 0, Z = -0.1 },
						{ Key = "TownAptFloorB", Size = Vector3.new(18.38, 11.02, 19.13), Y = 11, Z = -0.3 },
						{ Key = "TownAptRoofB", Size = Vector3.new(18.28, 3, 19.1), Y = 22.02, Z = 0 },
					},
					Front = "door",
					WallFront = -8.7,
					Shadow = true,
					Core = Vector3.new(17.6, 0, 17.4),
					CoreZ = 0,
					Color = Color3.fromRGB(140, 70, 56),
					Material = Enum.Material.Brick,
				},
				-- four-storey brick apartment block (door floor + a 3-floor stack + roof, top 46; 2,129 tris)
				tower = {
					Pieces = {
						{ Key = "TownAptDoorA", Size = Vector3.new(17.74, 11, 19.41), Y = 0, Z = -0.9 },
						{ Key = "TownAptStack", Size = Vector3.new(17.4, 33, 18.08), Y = 11, Z = -0.3 },
						{ Key = "TownAptRoofA", Size = Vector3.new(18.48, 2, 20.59), Y = 44, Z = 0 },
					},
					Front = "door",
					WallFront = -8.7,
					Shadow = true,
					Core = Vector3.new(17.6, 0, 17.4),
					CoreZ = 0,
					Color = Color3.fromRGB(150, 74, 58),
					Material = Enum.Material.Brick,
				},
				towerB = {
					Pieces = {
						{ Key = "TownAptDoorB", Size = Vector3.new(17.8, 11, 17.8), Y = 0, Z = -0.1 },
						{ Key = "TownAptStack", Size = Vector3.new(17.4, 33, 18.08), Y = 11, Z = -0.3 },
						{ Key = "TownAptRoofB", Size = Vector3.new(18.28, 3, 19.1), Y = 44, Z = 0 },
					},
					Front = "door",
					WallFront = -8.7,
					Shadow = true,
					Core = Vector3.new(17.6, 0, 17.4),
					CoreZ = 0,
					Color = Color3.fromRGB(140, 70, 56),
					Material = Enum.Material.Brick,
				},
				-- the sandstone hall with arched windows and a pedimented door, 3 storeys (6,638 tris: at most 4 in the Town)
				office = {
					Pieces = {
						{ Key = "TownOfficeBase", Size = Vector3.new(38.06, 21, 38.06), Y = 0, Z = 0 },
						{ Key = "TownOfficeTop", Size = Vector3.new(38.7, 15, 38.98), Y = 20.81, Z = 0 },
					},
					Front = "door",
					WallFront = -17.4,
					Shadow = true,
					Core = Vector3.new(34.8, 0, 34.8),
					CoreZ = 0,
					Color = Color3.fromRGB(176, 158, 128),
					Material = Enum.Material.Sandstone,
				},
			} :: { [string]: TownHouseStyle },
		},
		-- Town pavements (Kit Sidewalk, an infra strip): Width across, Top above the floor (flat, no collision, top 0.64
		-- world <= Hygiene.RoadMinTop): the frontage between the road shoulder and the building fronts
		Sidewalk = { Width = 26, Top = 0.14, MinLength = 40, MaxLength = 400, MinWidth = 6, MaxWidth = 48 },
	},

	-- ── W3 Crossroads Town (WorldPOI; spec §3.1–§3.2, contracts §4.3). Data, not code: one row per cluster ────────
	-- Town v3 (owner feedback 2026-09-27: "actual Roblox buildings"): Roblox-made brick walk-ups, shutter shops, two
	-- 4-storey apartment blocks and a sandstone hall (Kit TownHouse, Kits.TownHouse styles) line the plaza ring just
	-- outside r 124 and each road arm from r 131 out to ~290 (fronts facing the road about 34 off its centre line, a
	-- 7-9 stud alley between neighbours, a lane for the market), over paved frontages (Town.Infra), so every front gate
	-- sees a town skyline: water tower (NW, 43), apartment block (NE, 47), clock tower (SE, 40), radio mast (SW, 90).
	-- Fix round 1 (the pieces' backs and side walls are windowless flat brick): every public space shows fronts. The
	-- Town Square is closed on all four sides by buildings facing INTO it (the hall S, walk-up pairs W, rows SW_SqN /
	-- SW_SqE on N and E, their backs to the road rows' backs across a service yard); a walk-up facing the plaza closes
	-- each yard's mouth (SW_YardE / SW_YardN); the market lane is lined with lane-facing walk-ups up to the road (and
	-- NW_PlazaN, back to back with NW_Lane_S2, faces the plaza); and the first building of six arm rows is a plaza
	-- end-cap facing the flag along its road (NW_W1, NE_N1, NE_E1, SW_S1, SW_W1, SE_E1).
	-- Quadrants (north = -Z): NW market lane + water tower, NE tower block + Bank Street to the Empire Bank (MapSetup),
	-- SW Town Square arena (event anchor TownSquare) + radio mast, SE clock tower + motor pool (Pool_Town pad).
	-- Block clusters: disc edge >= RoadClear from both road centre lines and outside the CentralPlaza clear radius.
	-- Street clusters (checkpoints, lamps, board, the parked wreck): every collidable part >= 13 and every visible part
	-- >= 9 from the lines. Frontage buildings sit so their disc edge is >= 30.4 off the road line (WorldPOI skips and
	-- warns on any row that breaks a keep-out, so a moved row shows up in the Output).
	Town = {
		Id = "Town",
		Seed = 7021, -- WorldKits.Rng seed for the Town's terrain rubble
		RoadClear = 30, -- block clusters: disc edge to the road centre lines (spec §3.2)
		CollideRoadGap = 13, -- street clusters, per part (H2 corridor 12 + 1)
		VisibleRoadGap = 9, -- street clusters, per visible part taller than 0.3 (H2 lane 8 + 1)
		BoardText = "CROSSROADS",
		MaxTerrainPrims = 40,
		Clusters = {
			-- Entrances: a checkpoint v2 on each road at r 310 (booth on the shoulder, arm raised); yaw = the side arrivals come from
			{ Id = "CP_N", Block = "Road", Role = "checkpoint", Tier = 1, X = 0, Z = -310, Yaw = 0, Street = true, Kits = { { Kit = "Checkpoint", X = 0, Z = 0 } } }, -- booth on the east shoulder
			{ Id = "CP_E", Block = "Road", Role = "checkpoint", Tier = 1, X = 310, Z = 0, Yaw = -90, Street = true, Kits = { { Kit = "Checkpoint", X = 0, Z = 0 } } },
			{ Id = "CP_S", Block = "Road", Role = "checkpoint", Tier = 1, X = 0, Z = 310, Yaw = 180, Street = true, Kits = { { Kit = "Checkpoint", X = 0, Z = 0 } } },
			{ Id = "CP_W", Block = "Road", Role = "checkpoint", Tier = 1, X = -310, Z = 0, Yaw = 90, Street = true, Kits = { { Kit = "Checkpoint", X = 0, Z = 0 } } },
			-- 6 night lamps on the main-street frontages (poles 15 off the road lines, lenses 12.2) and the one painted board
			{ Id = "Lamp_1", Block = "Road", Role = "lamp", Tier = 1, X = -15, Z = -165, Yaw = -90, Street = true, Kits = { { Kit = "StreetLamp", X = 0, Z = 0 } } },
			{ Id = "Lamp_2", Block = "Road", Role = "lamp", Tier = 1, X = 15, Z = -235, Yaw = 90, Street = true, Kits = { { Kit = "StreetLamp", X = 0, Z = 0 } } },
			{ Id = "Lamp_3", Block = "Road", Role = "lamp", Tier = 1, X = -165, Z = 15, Yaw = 0, Street = true, Kits = { { Kit = "StreetLamp", X = 0, Z = 0 } } },
			{ Id = "Lamp_4", Block = "Road", Role = "lamp", Tier = 1, X = 165, Z = -15, Yaw = 180, Street = true, Kits = { { Kit = "StreetLamp", X = 0, Z = 0 } } },
			{ Id = "Lamp_5", Block = "Road", Role = "lamp", Tier = 1, X = -15, Z = 165, Yaw = -90, Street = true, Kits = { { Kit = "StreetLamp", X = 0, Z = 0 } } },
			{ Id = "Lamp_6", Block = "Road", Role = "lamp", Tier = 1, X = 15, Z = 235, Yaw = 90, Street = true, Kits = { { Kit = "StreetLamp", X = 0, Z = 0 } } },
			{ Id = "Board", Block = "Road", Role = "board", Tier = 1, X = -292, Z = -22, Yaw = 90, Street = true, Kits = { { Kit = "PoiBoard", X = 0, Z = 0 } } }, -- "CROSSROADS" facing arrivals from the west (RoadZ0 carries plots 1, 2, 5, 6)
			-- Plaza ring: the two apartment blocks facing the flag just outside the capture clear r 124 (SE: the clock tower; SW opens onto the Town Square)
			{ Id = "NW_Ring", Block = "NW", Role = "block", Tier = 1, X = -109.2, Z = -109.2, Yaw = -135, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "tower", Lantern = true } } }, -- 4-storey brick apartment block facing the flag, wall lantern
			{ Id = "NE_TowerBlock", Block = "NE", Role = "landmark", Tier = 1, X = 104.7, Z = -104.7, Yaw = 135, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "towerB" } } }, -- 4-storey brick apartment block (top 47): the NE skyline marker
			{ Id = "SE_ClockTower", Block = "SE", Role = "tower", Tier = 1, X = 95.5, Z = 95.5, Yaw = 45, Kits = { { Kit = "ClockTower", X = 0, Z = 0 } } }, -- landmark, 40 tall; clock faces toward the plaza and the south-east
			-- NW: frontage on the north arm (fronts facing east) broken by the market lane (z -175), then the west arm (fronts facing south)
			{ Id = "NW_N1", Block = "NW", Role = "block", Tier = 1, X = -44, Z = -131.5, Yaw = -90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkupB" } } },
			{ Id = "NW_N2", Block = "NW", Role = "block", Tier = 2, X = -44.7, Z = -200, Yaw = -90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkup" } } },
			{ Id = "NW_N3", Block = "NW", Role = "block", Tier = 2, X = -44.2, Z = -226, Yaw = -90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "shop" } } },
			{ Id = "NW_N4", Block = "NW", Role = "block", Tier = 2, X = -44.2, Z = -252, Yaw = -90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "shop" } } },
			{ Id = "NW_N5", Block = "NW", Role = "block", Tier = 2, X = -44, Z = -278, Yaw = -90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkupB" } } },
			{ Id = "NW_W1", Block = "NW", Role = "block", Tier = 1, X = -131.5, Z = -44.5, Yaw = -90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkup" } } }, -- plaza end-cap: faces the flag along the road
			{ Id = "NW_W2", Block = "NW", Role = "block", Tier = 2, X = -158, Z = -44.2, Yaw = 180, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "shop" } } },
			{ Id = "NW_W3", Block = "NW", Role = "block", Tier = 2, X = -184.5, Z = -44, Yaw = 180, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkupB" } } },
			{ Id = "NW_W4", Block = "NW", Role = "block", Tier = 2, X = -211, Z = -44.2, Yaw = 180, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "shop" } } },
			{ Id = "NW_W5", Block = "NW", Role = "block", Tier = 2, X = -237.5, Z = -44.7, Yaw = 180, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkup" } } },
			-- NW market lane: stalls between two walk-ups, the water tower closing the lane, a walk-up behind it
			{ Id = "NW_Lane_S", Block = "NW", Role = "block", Tier = 1, X = -88, Z = -147, Yaw = 0, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkup" } } }, -- south side of the market lane, facing it
			{ Id = "NW_Lane_N", Block = "NW", Role = "block", Tier = 2, X = -86, Z = -202, Yaw = 180, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkupB" } } }, -- north side of the market lane
			{ Id = "NW_Lane_S2", Block = "NW", Role = "block", Tier = 2, X = -66, Z = -147, Yaw = 0, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkupB" } } }, -- market lane south side, at the mouth
			{ Id = "NW_Lane_N2", Block = "NW", Role = "block", Tier = 2, X = -65.5, Z = -202, Yaw = 180, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkup" } } }, -- market lane north side, at the mouth
			{ Id = "NW_PlazaN", Block = "NW", Role = "block", Tier = 2, X = -66, Z = -126, Yaw = 180, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkup" } } }, -- back to back with NW_Lane_S2, facing the plaza
			{ Id = "NW_Stall_1", Block = "NW", Role = "stall", Tier = 1, X = -81, Z = -163.8, Yaw = 0, Kits = { { Kit = "MarketStall", X = 0, Z = 0, Color = Color3.fromRGB(160, 70, 55) } } },
			{ Id = "NW_Stall_2", Block = "NW", Role = "stall", Tier = 1, X = -80, Z = -185.2, Yaw = 180, Kits = { { Kit = "MarketStall", X = 0, Z = 0, Color = Color3.fromRGB(70, 95, 120) } } },
			{ Id = "NW_Stall_3", Block = "NW", Role = "stall", Tier = 2, X = -95, Z = -163.8, Yaw = 0, Kits = { { Kit = "MarketStall", X = 0, Z = 0, Color = Color3.fromRGB(190, 160, 90) } } },
			{ Id = "NW_Stall_4", Block = "NW", Role = "stall", Tier = 2, X = -94, Z = -185.2, Yaw = 180, Kits = { { Kit = "MarketStall", X = 0, Z = 0, Color = Color3.fromRGB(160, 70, 55) } } },
			{ Id = "NW_WaterTower", Block = "NW", Role = "tower", Tier = 1, X = -126, Z = -175, Yaw = 0, Kits = { { Kit = "WaterTower", X = 0, Z = 0 } } }, -- landmark, 43 tall, closing the market lane
			{ Id = "NW_Back_1", Block = "NW", Role = "block", Tier = 2, X = -153, Z = -175, Yaw = -90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkupB" } } }, -- faces down the market lane past the water tower
			-- NE: frontage on the north arm (fronts facing west) and the east arm (fronts facing south); Bank Street (x 200-240) runs down to the Empire Bank between two walk-ups
			{ Id = "NE_N1", Block = "NE", Role = "block", Tier = 1, X = 44.5, Z = -131.5, Yaw = 180, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkup" } } }, -- plaza end-cap: faces the flag along the road
			{ Id = "NE_N2", Block = "NE", Role = "block", Tier = 1, X = 44.2, Z = -158, Yaw = 90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "shop" } } },
			{ Id = "NE_N3", Block = "NE", Role = "block", Tier = 2, X = 44, Z = -184.5, Yaw = 90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkupB" } } },
			{ Id = "NE_N4", Block = "NE", Role = "block", Tier = 2, X = 44.2, Z = -211, Yaw = 90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "shop" } } },
			{ Id = "NE_N5", Block = "NE", Role = "block", Tier = 2, X = 44.7, Z = -237.5, Yaw = 90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkup" } } },
			{ Id = "NE_E1", Block = "NE", Role = "block", Tier = 1, X = 131.5, Z = -43.8, Yaw = 90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkupB" } } }, -- plaza end-cap: faces the flag along the road
			{ Id = "NE_E2", Block = "NE", Role = "block", Tier = 2, X = 158, Z = -44.7, Yaw = 180, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkup" } } },
			{ Id = "NE_E3", Block = "NE", Role = "block", Tier = 2, X = 252, Z = -44.2, Yaw = 180, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "shop" } } }, -- east of Bank Street
			{ Id = "NE_E4", Block = "NE", Role = "block", Tier = 2, X = 278.5, Z = -44, Yaw = 180, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkupB" } } },
			{ Id = "NE_Barricade", Block = "NE", Role = "barricade", Tier = 2, X = 16, Z = -132, Yaw = 90, Street = true, Kits = { { Kit = "Jersey", X = -3, Z = 0, Yaw = -10 }, { Kit = "Jersey", X = 3, Z = 0, Yaw = 10 } } }, -- jersey barricade on the north-arm verge at the plaza corner (collidable >= 13 off the line)
			{ Id = "NE_Bank_W", Block = "NE", Role = "block", Tier = 2, X = 189.4, Z = -150, Yaw = -90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkup" } } }, -- Bank Street, west side (front on x 200)
			{ Id = "NE_Bank_E", Block = "NE", Role = "block", Tier = 2, X = 249.9, Z = -150, Yaw = 90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkupB" } } }, -- Bank Street, east side (front on x 240)
			-- SW: frontage on the south arm (fronts facing east) and the west arm (fronts facing north); the Town Square (-150, 150) framed by the sandstone hall, two walk-ups and the radio mast
			{ Id = "SW_S1", Block = "SW", Role = "block", Tier = 1, X = -44.1, Z = 131.5, Yaw = 0, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "shop" } } }, -- plaza end-cap: faces the flag along the road
			{ Id = "SW_S2", Block = "SW", Role = "block", Tier = 2, X = -44, Z = 158, Yaw = -90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkupB" } } },
			{ Id = "SW_S3", Block = "SW", Role = "block", Tier = 2, X = -44.7, Z = 184.5, Yaw = -90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkup" } } },
			{ Id = "SW_S4", Block = "SW", Role = "block", Tier = 2, X = -44.2, Z = 211, Yaw = -90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "shop" } } },
			{ Id = "SW_S5", Block = "SW", Role = "block", Tier = 2, X = -44, Z = 237.5, Yaw = -90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkupB" } } },
			{ Id = "SW_W1", Block = "SW", Role = "block", Tier = 1, X = -131.5, Z = 44.5, Yaw = -90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkup" } } }, -- plaza end-cap: faces the flag along the road
			{ Id = "SW_W2", Block = "SW", Role = "block", Tier = 2, X = -158, Z = 44.2, Yaw = 0, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "shop" } } },
			{ Id = "SW_W3", Block = "SW", Role = "block", Tier = 2, X = -184.5, Z = 44, Yaw = 0, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkupB" } } },
			{ Id = "SW_W4", Block = "SW", Role = "block", Tier = 2, X = -211, Z = 44.2, Yaw = 0, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "shop" } } },
			{ Id = "SW_W5", Block = "SW", Role = "block", Tier = 2, X = -237.5, Z = 44.7, Yaw = 0, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkup" } } },
			-- SW: the Town Square arena, 90 x 90 paving round the TownSquare event anchor (-150, 150): dry fountain, benches
			{ Id = "SW_Square_1", Block = "SW", Role = "square", Tier = 1, X = -172.5, Z = 127.5, Yaw = 0, Kits = { { Kit = "PaveTile", X = 0, Z = 0, Color = Color3.fromRGB(176, 160, 132) } } },
			{ Id = "SW_Square_2", Block = "SW", Role = "square", Tier = 1, X = -127.5, Z = 127.5, Yaw = 0, Kits = { { Kit = "PaveTile", X = 0, Z = 0, Color = Color3.fromRGB(160, 144, 116) } } },
			{ Id = "SW_Square_3", Block = "SW", Role = "square", Tier = 1, X = -172.5, Z = 172.5, Yaw = 0, Kits = { { Kit = "PaveTile", X = 0, Z = 0, Color = Color3.fromRGB(160, 144, 116) } } },
			{ Id = "SW_Square_4", Block = "SW", Role = "square", Tier = 1, X = -127.5, Z = 172.5, Yaw = 0, Kits = { { Kit = "PaveTile", X = 0, Z = 0, Color = Color3.fromRGB(176, 160, 132) } } },
			{ Id = "SW_Fountain", Block = "SW", Role = "fountain", Tier = 1, X = -150, Z = 120, Yaw = 0, Kits = { { Kit = "Fountain", X = 0, Z = 0 } } }, -- 30 from the anchor: its 20-stud landing circle stays clear
			{ Id = "SW_Benches_1", Block = "SW", Role = "benches", Tier = 2, X = -188, Z = 150, Yaw = -90, Kits = { { Kit = "Bench", X = -12, Z = 0 }, { Kit = "Bench", X = 12, Z = 0 } } },
			{ Id = "SW_Square_S", Block = "SW", Role = "block", Tier = 1, X = -150, Z = 216, Yaw = 0, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "office" } } }, -- the sandstone hall closing the square's south side
			{ Id = "SW_Square_W", Block = "SW", Role = "block", Tier = 2, X = -207, Z = 150, Yaw = -90, Kits = { { Kit = "TownHouse", X = -9.6, Z = 0, Variant = "walkup" }, { Kit = "TownHouse", X = 9.6, Z = 0, Variant = "walkupB" } } }, -- two walk-ups closing the square's west side
			-- fix round 1: the square's north and east sides are walk-ups facing INTO the square (backs to the road rows' backs
			-- across a 28-stud service yard), and a walk-up closes each yard's mouth facing the plaza, so the square and the
			-- plaza corner see fronts, not backs
			{ Id = "SW_SqN1", Block = "SW", Role = "block", Tier = 1, X = -135, Z = 92.3, Yaw = 180, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkupB" } } }, -- Town Square north side, facing the square
			{ Id = "SW_SqN2", Block = "SW", Role = "block", Tier = 1, X = -161.5, Z = 92.3, Yaw = 180, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkup" } } },
			{ Id = "SW_SqN3", Block = "SW", Role = "block", Tier = 1, X = -188, Z = 92.3, Yaw = 180, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkupB" } } },
			{ Id = "SW_SqE1", Block = "SW", Role = "block", Tier = 1, X = -92.3, Z = 135, Yaw = 90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkup" } } }, -- Town Square east side, facing the square
			{ Id = "SW_SqE2", Block = "SW", Role = "block", Tier = 1, X = -92.3, Z = 161.5, Yaw = 90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkupB" } } },
			{ Id = "SW_SqE3", Block = "SW", Role = "block", Tier = 1, X = -92.3, Z = 188, Yaw = 90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkup" } } },
			{ Id = "SW_YardE", Block = "SW", Role = "block", Tier = 2, X = -68, Z = 121, Yaw = 0, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkupB" } } }, -- closes the yard behind the south-arm row, facing the plaza
			{ Id = "SW_YardN", Block = "SW", Role = "block", Tier = 2, X = -120, Z = 70, Yaw = -90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkup" } } }, -- closes the yard behind the west-arm row, facing the plaza
			{ Id = "SW_RadioMast", Block = "SW", Role = "mast", Tier = 1, X = -214, Z = 212, Yaw = 0, Kits = { { Kit = "RadioMast", X = 0, Z = 0 } } }, -- 90-tall lattice mast over the square: the SW skyline marker
			{ Id = "SW_Nest", Block = "SW", Role = "nest", Tier = 2, X = -95, Z = 95, Yaw = 135, Kits = { { Kit = "SandbagArc", X = 0, Z = 0 } } }, -- sandbag arc on the plaza corner, facing the flag
			-- SE: frontage on the east arm (fronts facing north) and the south arm past the Pool_Town pad (fronts facing west); motor pool garages
			{ Id = "SE_E1", Block = "SE", Role = "block", Tier = 1, X = 131.5, Z = 44.5, Yaw = 90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkup", Lantern = true } } }, -- plaza end-cap: faces the flag along the road
			{ Id = "SE_E2", Block = "SE", Role = "block", Tier = 2, X = 158, Z = 44.2, Yaw = 0, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "shop" } } },
			{ Id = "SE_E3", Block = "SE", Role = "block", Tier = 2, X = 184.5, Z = 44, Yaw = 0, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkupB" } } },
			{ Id = "SE_E4", Block = "SE", Role = "block", Tier = 2, X = 211, Z = 44.2, Yaw = 0, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "shop" } } },
			{ Id = "SE_E5", Block = "SE", Role = "block", Tier = 2, X = 237.5, Z = 44.7, Yaw = 0, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkup" } } },
			{ Id = "SE_S1", Block = "SE", Role = "block", Tier = 1, X = 44, Z = 212, Yaw = 90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkupB" } } },
			{ Id = "SE_S2", Block = "SE", Role = "block", Tier = 2, X = 44.2, Z = 238.5, Yaw = 90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "shop" } } },
			{ Id = "SE_S3", Block = "SE", Role = "block", Tier = 2, X = 44.7, Z = 265, Yaw = 90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "walkup" } } },
			{ Id = "SE_S4", Block = "SE", Role = "block", Tier = 2, X = 44.2, Z = 291.5, Yaw = 90, Kits = { { Kit = "TownHouse", X = 0, Z = 0, Variant = "shop" } } },
			{ Id = "SE_MotorShed", Block = "SE", Role = "block", Tier = 2, X = 100, Z = 170, Yaw = 90, Kits = { { Kit = "TownHouse", X = -9.3, Z = 0, Variant = "shop" }, { Kit = "TownHouse", X = 9.3, Z = 0, Variant = "shop" } } }, -- two shutter garages facing the Pool_Town pad
			{ Id = "SE_MotorPool", Block = "SE", Role = "motorpool", Tier = 2, X = 76, Z = 170, Yaw = 90, Kits = { { Kit = "Jersey", X = -4, Z = 0 }, { Kit = "Jersey", X = 4, Z = 0 }, { Kit = "DrumGroup", X = 0, Z = 3, Count = 2 } } }, -- beside the Pool_Town garage pad (+16 clear)
			{ Id = "SE_Wreck", Block = "SE", Role = "wreck", Tier = 1, X = 232, Z = 14.5, Yaw = 0, Street = true, Kits = { { Kit = "Wreck", X = 0, Z = 0, Variant = "truck" } } }, -- burnt truck parked on the east-arm verge (collidable >= 13 off the line)
		} :: { TownCluster },
		Rocks = {
			{ Kind = "rubble", X = -68, Z = -262, Radius = 6, Tier = 1 }, -- back lot behind the north-arm frontage
			{ Kind = "rubble", X = -262, Z = -62, Radius = 6, Tier = 1 }, -- back lot at the end of the west-arm frontage
			{ Kind = "rubble", X = -130, Z = -222, Radius = 6, Tier = 1 }, -- behind the market lane
			{ Kind = "rubble", X = 78, Z = -130, Radius = 6, Tier = 1 }, -- between the apartment block and the north-arm frontage
			{ Kind = "rubble", X = 290, Z = -64, Radius = 5, Tier = 1 }, -- back lot at the end of the east-arm frontage
			{ Kind = "rubble", X = -66, Z = 262, Radius = 6, Tier = 1 }, -- back lot behind the south-arm frontage
			{ Kind = "rubble", X = 228, Z = 72, Radius = 6, Tier = 1 }, -- back lot behind the east-arm frontage
			{ Kind = "rubble", X = 66, Z = 290, Radius = 6, Tier = 1 }, -- back lot behind the south-arm frontage
			{ Kind = "scorch", X = 150, Z = 170, Radius = 9, Tier = 1 }, -- a burnt patch behind the east-arm frontage
		} :: { TownRock },
		-- Town pavements (owner feedback 2026-09-27; Kit Sidewalk, one flat non-colliding strip each, under
		-- POI_Town.Infra, built in Low and Full): each road arm's two frontages from the road shoulder (7.6 off the centre
		-- line) to the building fronts (33.6), Length along the arm; Bank Street (x 200..240) down to the bank plaza's
		-- guard ring; the market lane between its two walk-ups. The south arm's east side starts past the Pool_Town pad
		-- (+16). 10 parts; every strip is sampled through WorldDress.Blocked (capture clear r 124, pads, bank).
		Infra = {
			{ Id = "Walk_N_W", Kit = "Sidewalk", X = -20.6, Z = -214.5, Yaw = 90, Length = 171 },
			{ Id = "Walk_N_E", Kit = "Sidewalk", X = 20.6, Z = -214.5, Yaw = 90, Length = 171 },
			{ Id = "Walk_S_W", Kit = "Sidewalk", X = -20.6, Z = 214.5, Yaw = 90, Length = 171 },
			{ Id = "Walk_S_E", Kit = "Sidewalk", X = 20.6, Z = 250.5, Yaw = 90, Length = 99 },
			{ Id = "Walk_W_N", Kit = "Sidewalk", X = -214.5, Z = -20.6, Yaw = 0, Length = 171 },
			{ Id = "Walk_W_S", Kit = "Sidewalk", X = -214.5, Z = 20.6, Yaw = 0, Length = 171 },
			{ Id = "Walk_E_N", Kit = "Sidewalk", X = 214.5, Z = -20.6, Yaw = 0, Length = 171 },
			{ Id = "Walk_E_S", Kit = "Sidewalk", X = 214.5, Z = 20.6, Yaw = 0, Length = 171 },
			{ Id = "Walk_Bank", Kit = "Sidewalk", X = 220, Z = -103.8, Yaw = 90, Length = 140.4, Width = 40 },
			{ Id = "Walk_Market", Kit = "Sidewalk", X = -75.8, Z = -174.95, Yaw = 0, Length = 84.4, Width = 34.3 },
		} :: { InfraRow },
		-- W3 step 2 activity anchors (world studs; see the Activity section). WorldPOI stamps each Town row on the first
		-- part of the cluster it Requires (a Town row always names one) and Activity.CheckpointAnchors on CP_N / CP_E /
		-- CP_S / CP_W (ids Town.CP_N.Booth …). 0 parts: the Town stays at 368 / 370.
		Anchors = {
			{ Id = "Town.Market.Box", Kind = "search", X = -81, Z = -169.3, Yaw = 0, R = 5, Prompt = "hold", Requires = "NW_Stall_1" }, -- the market cache, at the NW_Stall_1 counter (1.8 clear of it in the HEAD dump)
		} :: { ActivityAnchor },
		-- The Empire Bank's anchors (spec w3s2 §5). MapSetup (lane BK) stamps them on BankPlaza (top 1.6 = Y 1.1) once the
		-- 17-part hall is built; until then nothing stamps them and BankRaidService keeps its fallback posts.
		BankAnchors = {
			{ Id = "Town.Bank.Door", Kind = "door", X = 220, Z = -212.5, Yaw = 180, Y = 1.1, Prompt = "hold", Part = "BankGate" }, -- breach: hold 3 s, on foot
			{ Id = "Town.Bank.Vault", Kind = "hold", X = 220, Z = -226, Yaw = 180, Y = 1.1, R = 8 }, -- the crack ring stays inside the hall's walls
			{ Id = "Town.Bank.Loot", Kind = "loot", X = 220, Z = -228, Yaw = 180, Y = 1.1, Prompt = "hold" }, -- "Grab cash"
			{ Id = "Town.Bank.G1", Kind = "npc", X = 206, Z = -209.5, Yaw = 180, Y = 1.1 }, -- behind PlanterW
			{ Id = "Town.Bank.G2", Kind = "npc", X = 234, Z = -209.5, Yaw = 180, Y = 1.1 }, -- behind PlanterE
			{ Id = "Town.Bank.G3", Kind = "npc", X = 210.5, Z = -210.5, Yaw = 180, Y = 1.1 }, -- beside the west column
			{ Id = "Town.Bank.G4", Kind = "npc", X = 229.5, Z = -210.5, Yaw = 180, Y = 1.1 }, -- beside the east column
			{ Id = "Town.Bank.G5", Kind = "npc", X = 227, Z = -231, Yaw = 180, Y = 1.1 }, -- inside, by the vault door (Post stance)
			{ Id = "Town.Bank.R1", Kind = "npc", X = 252, Z = -208, Yaw = 90 }, -- alarm reinforcements, off the plaza (facing the bank)
			{ Id = "Town.Bank.R2", Kind = "npc", X = 188, Z = -208, Yaw = -90 },
		} :: { ActivityAnchor },
	},

	-- ── Spawn pads and anchors (spec §3.3; the hook step replaces MapSetup's makeSpawnFolder rings with these) ───
	Spawns = {
		-- Garage pads (WE_VehicleSpawn): painted Concrete aprons, no beacon, no billboard. Gate pads are plot-local
		-- (BaseLayout.PlotPoint(plotPos, LocalX, LocalZ)) and face the plot forward; pools face Yaw (degrees, 0 = -Z).
		PadSize = Vector3.new(20, 1.2, 20),
		Garage = {
			{ Id = "Gate_P1", PlotId = 1, LocalX = -62, LocalZ = 222 },
			{ Id = "Gate_P2", PlotId = 2, LocalX = -62, LocalZ = 222 },
			{ Id = "Gate_P3", PlotId = 3, LocalX = -62, LocalZ = 222 },
			{ Id = "Gate_P4", PlotId = 4, LocalX = -62, LocalZ = 222 },
			{ Id = "Gate_P5", PlotId = 5, LocalX = -62, LocalZ = 222 },
			{ Id = "Gate_P6", PlotId = 6, LocalX = -62, LocalZ = 222 },
			-- claude-bud JOB 21: the land plots 7-10 (no sign: the world sign budget of 17 is full)
			{ Id = "Gate_P7", PlotId = 7, LocalX = -62, LocalZ = 222, NoSign = true },
			{ Id = "Gate_P8", PlotId = 8, LocalX = -62, LocalZ = 222, NoSign = true },
			{ Id = "Gate_P9", PlotId = 9, LocalX = -62, LocalZ = 222, NoSign = true },
			{ Id = "Gate_P10", PlotId = 10, LocalX = -62, LocalZ = 222, NoSign = true },
			{ Id = "Pool_Depot", X = -1180, Z = 34, Yaw = -90 }, -- faces +X (RoadZ0)
			{ Id = "Pool_Armory", X = 1180, Z = -34, Yaw = 90 }, -- faces -X
			{ Id = "Pool_Town", X = 40, Z = 170, Yaw = 0 }, -- faces -Z
			{ Id = "Pool_Airstrip", X = 740, Z = -1180, Yaw = 180 }, -- faces +Z
		} :: { Pad },
		TutorialJeepPad = "Gate_P1", -- the tutorial's jeep step targets the player's own gate pad
		-- vscale R2: the gate pads' "Garage" sign post and board stand this far behind the pad centre (pad-local +Z, was
		-- PadSize.Z / 2 + 0.4 = 10.4): a Roblox-size Pickup / Van parked on the pad reaches 13.29 / 13.10 back
		GarageSignBack = 14.6,
		-- Invisible anchors (Transparency 1, CanCollide false, 14 x 1.2 x 14 at y 1)
		AnchorSize = Vector3.new(14, 1.2, 14),
		NPC = {
			{ Id = "Quarry_1", X = -1470, Z = -1300 },
			{ Id = "Quarry_2", X = -1320, Z = -1480 },
			{ Id = "Quarry_3", X = -1260, Z = -1330 },
			{ Id = "Quarry_4", X = -1440, Z = -1420 },
			{ Id = "Ridge_1", X = 1360, Z = -1100 },
			{ Id = "Ridge_2", X = 1480, Z = -1010 },
			{ Id = "Ridge_3", X = 1450, Z = -1120 },
			{ Id = "Dune_1", X = 1400, Z = 1150 },
			{ Id = "Dune_2", X = 1520, Z = 1240 },
			{ Id = "Dune_3", X = 1470, Z = 1300 },
		} :: { Anchor },
		Event = {
			{ Id = "TownSquare", X = -150, Z = 150 },
			{ Id = "AirdropApron", X = 520, Z = -1190 },
			{ Id = "Salvage", X = -520, Z = 1080 },
			{ Id = "VillageSquare", X = -540, Z = -1300 },
			{ Id = "OilYard", X = 1100, Z = 1100 },
			{ Id = "Quay", X = 250, Z = 1250 },
		} :: { Anchor },
	},

	-- ── W3 step 2 activity anchors (spec w3s2 §1.5–§1.6, §5; contract scratchpad w3s2/build/L0/contract.md) ─────────
	-- A job place is a set of invisible anchors: one Attachment per anchor (0 parts), tagged Tag, carrying the Attr
	-- attributes. The geometry stamps them through ActivityAnchors.Stamp (WorldPOI: layout rows on the POI's
	-- ActivityHost part, template rows on each CheckpointBooth, Town rows on a part of the cluster they Require;
	-- MapSetup: Town.BankAnchors on BankPlaza). The jobs read them through ActivityAnchors.List / Get (server only).
	-- Id = "<POI>.<Site>.<Role>": POI = a POIs Id, Site = one job place at it, Role = what the anchor is for there;
	-- the site id is "<POI>.<Site>". A site is live only when its POI is enabled and every anchor its job needs exists.
	Activity = {
		Tag = "WE_ActivityAnchor", -- CollectionService tag on every anchor Attachment
		Attr = {
			Id = "WE_ActivityId", -- string, the full id
			Site = "WE_ActivitySite", -- string, "<POI>.<Site>"
			POI = "WE_ActivityPOI", -- string
			Role = "WE_ActivityRole", -- string
			Kind = "WE_ActivityKind", -- string, one of Kinds
			Yaw = "WE_ActivityYaw", -- number, degrees (0 = faces north, -Z)
			R = "WE_ActivityR", -- number (optional): zone radius
			Prompt = "WE_ActivityPrompt", -- string (optional): one of Prompts
			Part = "WE_Part", -- string (optional): the part a door anchor opens (HeistGate, BunkerDoor, BankGate)
			BoxW = "WE_ActivityBoxW", -- number (optional): vehicle spawn box width
			BoxL = "WE_ActivityBoxL", -- number (optional): vehicle spawn box length
			Probe = "WE_ActivityProbe", -- boolean (optional): test clearance at runtime, fall back to the nearest post
		},
		-- On a part the jobs move or toggle at runtime (BankGate, HeistGate, BunkerDoor): WorldHygiene Enforce leaves it
		-- alone. GateStateAttr on the same part: "open" (raised, CanCollide false) | "closed".
		RuntimeDoorAttr = "WE_RuntimeDoor",
		GateStateAttr = "WE_GateState",
		HostKit = "ActivityHost", -- the 1-part invisible host kit each POI layout places once (its anchors attach to it)
		CheckpointKit = "Checkpoint", -- every instance gets CheckpointAnchors …
		CheckpointHost = "CheckpointBooth", -- … stamped on this part of the kit
		FloorY = 0.5, -- anchor world Y = FloorY + (row Y or 0): the standing surface, never a lifted prompt height
		MinClear = 1, -- studs: no anchor (Probe ones aside) within this of a collidable part (the geometry tests)
		Kinds = {
			"door", -- breach point in front of a door / gate part (Part names it)
			"hold", -- stand-in zone of radius R (a crack, a pump, a booth, a chest); freezes under fire
			"loot", -- where the loot is grabbed
			"console", -- hack / uplink / alarm console
			"npc", -- a guard post (Gn), an alarm reinforcement point (Rn) or a camp commander (Cmdr)
			"arena", -- an event / king-of-the-hill area of radius R
			"vehicle", -- a vehicle spawn box (Box) — reserved, not a job yet
			"deliver_boat", -- a boat delivery point — reserved
			"sabotage", -- plant a charge (radius R)
			"search", -- a cache to search (radius R)
		},
		Prompts = { "hold", "tap" },
		-- Role vocabulary (a stamped role outside it only warns): the names plus the numbered forms Gn, Rn, PumpN, CacheN
		Roles = { "Door", "Gate", "Vault", "Loot", "Console", "Chest", "Booth", "Alarm", "Pump", "Valve", "Truck", "Recorder", "Box", "Ring", "Arena", "BoatDrop", "Pad", "Pier", "Cmdr" },
		NumberedRoles = { "G", "R", "Pump", "Cache" },
		-- The checkpoint template (kit-local studs; the kit's front, local -Z, faces arriving traffic; booth on +X).
		-- Every Checkpoint kit gets these 6 anchors, "<POI>.<cluster Id>.<Role>" (a POI with one checkpoint names that
		-- cluster "CP"). Clear of the kit's collidables (WorldKits Checkpoint): booth x 15.5..19.5 z -0.2..4.2, far
		-- sandbag x -15.8..-13.4 z -4..4, near sandbag x 13.4..15.8 z -7.1..-2.1. R1 / R2 lie 90 up the road (Probe).
		CheckpointAnchors = {
			{ Role = "Booth", Kind = "hold", X = 17.5, Z = 9.5, Yaw = 0, R = 5, Prompt = "hold" }, -- "Take post", behind the booth
			{ Role = "Alarm", Kind = "console", X = 17.6, Z = -2.0, Yaw = 0, Prompt = "hold" }, -- on the booth front (1.8 clear)
			{ Role = "G1", Kind = "npc", X = -14.6, Z = 5.5, Yaw = 0 }, -- behind the far sandbag (1.5 clear)
			{ Role = "G2", Kind = "npc", X = 21.5, Z = 1.5, Yaw = 0 }, -- beside the booth (2.0 clear)
			{ Role = "R1", Kind = "npc", X = 18, Z = -90, Yaw = 180, Probe = true }, -- alarm reinforcements, running in
			{ Role = "R2", Kind = "npc", X = -18, Z = -90, Yaw = 180, Probe = true },
		} :: { AnchorTemplate },
	},
}

return WorldConfig
