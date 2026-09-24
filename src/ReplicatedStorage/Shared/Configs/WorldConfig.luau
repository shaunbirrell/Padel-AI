--!strict
--[[
	WAR EMPIRE World v2 (gap/world_v2_spec.md + roadmap §1.5 corrections): the world OUTSIDE the bases.
	One source of truth for the Phase 1 modules (all under ServerScriptService/Server/Modules):
	  * WorldTerrain    — Terrain canyon edge round the ring canal + the far shore that closes the Bay (Terrain section)
	  * WorldBounds     — Persistent skyline ridges, invisible ground / air walls, seabed tint, far-shore lighthouse and
	                      stranded freighter (Skyline, Bounds, Seabed, FarShore sections)
	  * WorldAtmosphere — Lighting / Sky / Atmosphere presets and the day cycle (Atmosphere section)
	  * WorldHygiene    — rules H1–H10 over the world dressing (Hygiene section)
	plus the Phase 2 data the hook step and W3 read (POIs, Spawns, Budgets).

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
	Kits: { KitPlace },
}
export type TownRock = { Kind: string, X: number, Z: number, Radius: number, Tier: number }
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
		Gen = 1,
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
		-- Canal / sea-cliff profile (east, west, north). Heights are world Y of the top.
		Side = {
			Skirt = { From = 0, To = 18, Min = 2.5, Max = 5.5 },
			Talus = { From = 18, To = 48, Min = 8, Max = 20 },
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
		SurfaceGuis = 12,
		ShadowCasters = 300,
		TerrainEdgePrims = 2500,
		SkylineParts = 48,
		BoundsParts = 52, -- walls 22 + tint 8 + far shore 22
	},

	-- ── Phase 2 data (W3 builds the POIs; H1 already uses the footprints as anchors) ────────────────────────────
	POIs = {
		{ Id = "Town", Name = "Crossroads Town", Kind = "town", Rect = { X0 = -330, X1 = 330, Z0 = -330, Z1 = 330 }, Budget = 220, Enabled = true, Lights = 6, Signs = 1 },
		{ Id = "Depot", Name = "West Supply Depot", Kind = "depot", Rect = { X0 = -1500, X1 = -1110, Z0 = -200, Z1 = 200 }, Budget = 120, Enabled = false, Lights = 3, Signs = 0 },
		{ Id = "Armory", Name = "East Armory", Kind = "armory", Rect = { X0 = 1110, X1 = 1500, Z0 = -200, Z1 = 200 }, Budget = 120, Enabled = false, Lights = 3, Signs = 0 },
		{ Id = "Signal", Name = "North Ridge Signal Station", Kind = "signal", Rect = { X0 = -280, X1 = 90, Z0 = -1480, Z1 = -1120 }, Budget = 90, Enabled = false, Lights = 0, Signs = 0 },
		{ Id = "Port", Name = "South Port", Kind = "port", Rect = { X0 = -330, X1 = 330, Z0 = 1180, Z1 = 1466 }, Budget = 150, Enabled = false, Lights = 4, Signs = 0 },
		{ Id = "OilField", Name = "Oil Field", Kind = "oil", Rect = { X0 = 830, X1 = 1230, Z0 = 830, Z1 = 1230 }, Budget = 110, Enabled = false, Lights = 0, Signs = 0 },
		{ Id = "Radar", Name = "Radar Hill", Kind = "radar", Circle = { X = -950, Z = -950, R = 130 }, Budget = 60, Enabled = false, Lights = 0, Signs = 0 },
		{ Id = "FortI", Name = "Fort Ironclad approach", Kind = "fort", Circle = { X = 1450, Z = -1450, R = 230 }, Budget = 60, Enabled = false, Lights = 0, Signs = 0 },
		{ Id = "FortS", Name = "Fort Sandhold approach", Kind = "fort", Circle = { X = -1450, Z = 1450, R = 200 }, Budget = 60, Enabled = false, Lights = 0, Signs = 0 },
		{ Id = "RigA", Name = "Rig Alpha shore base", Kind = "rigshore", Rect = { X0 = 1540, X1 = 1698, Z0 = -880, Z1 = -620 }, Budget = 40, Enabled = false, Lights = 1, Signs = 0 },
		{ Id = "RigB", Name = "Rig Bravo shore base", Kind = "rigshore", Rect = { X0 = -1698, X1 = -1540, Z0 = 620, Z1 = 880 }, Budget = 40, Enabled = false, Lights = 1, Signs = 0 },
		{ Id = "Airstrip", Name = "Desert Airstrip", Kind = "airstrip", Rect = { X0 = 240, X1 = 780, Z0 = -1380, Z1 = -1150 }, Budget = 100, Enabled = false, Lights = 3, Signs = 0 },
		{ Id = "Ruins", Name = "Ruined Village", Kind = "ruins", Circle = { X = -540, Z = -1320, R = 190 }, Budget = 100, Enabled = false, Lights = 0, Signs = 0 },
		{ Id = "Quarry", Name = "Quarry Camp", Kind = "camp", Circle = { X = -1380, Z = -1380, R = 220 }, Budget = 90, Enabled = false, Lights = 0, Signs = 0 },
		{ Id = "RidgeCamp", Name = "Ridge Camp", Kind = "camp", Circle = { X = 1420, Z = -1060, R = 150 }, Budget = 60, Enabled = false, Lights = 0, Signs = 0 },
		{ Id = "DuneCamp", Name = "Dune Camp", Kind = "camp", Circle = { X = 1450, Z = 1200, R = 160 }, Budget = 60, Enabled = false, Lights = 0, Signs = 0 },
		{ Id = "Crash", Name = "Crash Site", Kind = "crash", Circle = { X = -540, Z = 1140, R = 165 }, Budget = 80, Enabled = false, Lights = 0, Signs = 0 },
		{ Id = "Oasis", Name = "Oasis", Kind = "oasis", Circle = { X = -1300, Z = 560, R = 125 }, Budget = 60, Enabled = false, Lights = 2, Signs = 0 },
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
	},

	-- ── W3 Crossroads Town (WorldPOI; spec §3.1–§3.2, contracts §4.3). Data, not code: one row per cluster ────────
	-- Quadrants (north = -Z): NW market street + water tower, NE Empire Bank plaza (MapSetup) + houses, SW Town Square
	-- arena (event anchor TownSquare), SE clock tower + houses + ruin + wreck + motor pool (Pool_Town pad).
	-- Block clusters: disc edge >= RoadClear from both road centre lines and outside the CentralPlaza clear radius.
	-- Street clusters (checkpoints, lamps, board): every collidable part >= 13 and every visible part >= 9 from the lines.
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
			-- Plaza ring: one building on each inner quadrant corner facing the CentralPlaza flag (the clock tower holds SE)
			{ Id = "NW_Corner", Block = "NW", Role = "house", Tier = 2, X = -97, Z = -103, Yaw = -135, Kits = { { Kit = "AdobeHouse", X = 0, Z = 0, Variant = "tall", Color = Color3.fromRGB(204, 176, 132) } } },
			{ Id = "NE_Corner", Block = "NE", Role = "house", Tier = 1, X = 97, Z = -103, Yaw = 135, Kits = { { Kit = "AdobeHouse", X = 0, Z = 0, Variant = "shop", Color = Color3.fromRGB(190, 138, 104) } } },
			{ Id = "SW_Corner", Block = "SW", Role = "house", Tier = 2, X = -97, Z = 103, Yaw = -45, Kits = { { Kit = "AdobeHouse", X = 0, Z = 0, Variant = "wide" } } },
			{ Id = "SE_ClockTower", Block = "SE", Role = "tower", Tier = 1, X = 100, Z = 100, Yaw = 45, Kits = { { Kit = "ClockTower", X = 0, Z = 0 } } }, -- landmark, 40 tall; clock faces toward the plaza and the south-east
			-- NW: the market street (z -175) runs west off the north arm between frontage houses, closed by the water tower
			{ Id = "NW_WaterTower", Block = "NW", Role = "tower", Tier = 1, X = -118, Z = -175, Yaw = 0, Kits = { { Kit = "WaterTower", X = 0, Z = 0 } } }, -- landmark, 43 tall; the street runs under its legs
			{ Id = "NW_Stall_1", Block = "NW", Role = "stall", Tier = 1, X = -66, Z = -187, Yaw = 180, Kits = { { Kit = "MarketStall", X = 0, Z = 0, Color = Color3.fromRGB(160, 70, 55) } } },
			{ Id = "NW_Stall_2", Block = "NW", Role = "stall", Tier = 1, X = -72, Z = -163, Yaw = 0, Kits = { { Kit = "MarketStall", X = 0, Z = 0, Color = Color3.fromRGB(70, 95, 120) } } },
			{ Id = "NW_Stall_3", Block = "NW", Role = "stall", Tier = 2, X = -80, Z = -187, Yaw = 180, Kits = { { Kit = "MarketStall", X = 0, Z = 0, Color = Color3.fromRGB(190, 160, 90) } } },
			{ Id = "NW_Stall_4", Block = "NW", Role = "stall", Tier = 2, X = -86, Z = -163, Yaw = 0, Kits = { { Kit = "MarketStall", X = 0, Z = 0, Color = Color3.fromRGB(160, 70, 55) } } },
			{ Id = "NW_Goods", Block = "NW", Role = "goods", Tier = 2, X = -98, Z = -191, Yaw = 180, Kits = { { Kit = "CrateStack", X = -3, Z = 0, Count = 3 }, { Kit = "DrumGroup", X = 4, Z = 0 } } },
			{ Id = "NW_Shop", Block = "NW", Role = "house", Tier = 1, X = -44, Z = -140, Yaw = -90, Kits = { { Kit = "AdobeHouse", X = 0, Z = 0, Variant = "shop" } } }, -- frontage on the north arm
			{ Id = "NW_House_1", Block = "NW", Role = "house", Tier = 2, X = -44, Z = -212, Yaw = -90, Kits = { { Kit = "AdobeHouse", X = 0, Z = 0, Variant = "wide", Color = Color3.fromRGB(190, 138, 104) } } },
			{ Id = "NW_House_2", Block = "NW", Role = "house", Tier = 2, X = -150, Z = -44, Yaw = 180, Kits = { { Kit = "AdobeHouse", X = 0, Z = 0, Variant = "tall", Color = Color3.fromRGB(204, 176, 132) } } }, -- frontage on the west arm
			-- NE: the Empire Bank plaza (MapSetup, (220, -220); guard ring + 14 clear) framed by houses and a guard post
			{ Id = "NE_House_1", Block = "NE", Role = "house", Tier = 1, X = 165, Z = -205, Yaw = -90, Kits = { { Kit = "AdobeHouse", X = 0, Z = 0 } } }, -- faces the bank
			{ Id = "NE_House_2", Block = "NE", Role = "house", Tier = 2, X = 222, Z = -162, Yaw = 0, Kits = { { Kit = "AdobeHouse", X = 0, Z = 0, Variant = "tall", Color = Color3.fromRGB(204, 176, 132) } } }, -- faces the bank
			{ Id = "NE_GuardPost", Block = "NE", Role = "guardpost", Tier = 2, X = 176, Z = -168, Yaw = -45, Kits = { { Kit = "SandbagLine", X = 0, Z = 0, Length = 10 }, { Kit = "CrateStack", X = 0, Z = 5, Count = 2 } } },
			{ Id = "NE_House_3", Block = "NE", Role = "house", Tier = 2, X = 44, Z = -150, Yaw = 90, Kits = { { Kit = "AdobeHouse", X = 0, Z = 0, Color = Color3.fromRGB(190, 138, 104) } } }, -- frontage on the north arm
			{ Id = "NE_Wall", Block = "NE", Role = "wall", Tier = 2, X = 48, Z = -200, Yaw = 90, Kits = { { Kit = "CompoundWall", X = 0, Z = 0, Length = 32 } } },
			{ Id = "NE_House_4", Block = "NE", Role = "house", Tier = 2, X = 150, Z = -44, Yaw = 180, Kits = { { Kit = "AdobeHouse", X = 0, Z = 0, Variant = "wide" } } }, -- frontage on the east arm
			-- SW: the Town Square arena, 90 x 90 paving round the TownSquare event anchor (-150, 150): dry fountain, benches
			{ Id = "SW_Square_1", Block = "SW", Role = "square", Tier = 1, X = -172.5, Z = 127.5, Yaw = 0, Kits = { { Kit = "PaveTile", X = 0, Z = 0, Color = Color3.fromRGB(176, 160, 132) } } },
			{ Id = "SW_Square_2", Block = "SW", Role = "square", Tier = 1, X = -127.5, Z = 127.5, Yaw = 0, Kits = { { Kit = "PaveTile", X = 0, Z = 0, Color = Color3.fromRGB(160, 144, 116) } } },
			{ Id = "SW_Square_3", Block = "SW", Role = "square", Tier = 1, X = -172.5, Z = 172.5, Yaw = 0, Kits = { { Kit = "PaveTile", X = 0, Z = 0, Color = Color3.fromRGB(160, 144, 116) } } },
			{ Id = "SW_Square_4", Block = "SW", Role = "square", Tier = 1, X = -127.5, Z = 172.5, Yaw = 0, Kits = { { Kit = "PaveTile", X = 0, Z = 0, Color = Color3.fromRGB(176, 160, 132) } } },
			{ Id = "SW_Fountain", Block = "SW", Role = "fountain", Tier = 1, X = -150, Z = 120, Yaw = 0, Kits = { { Kit = "Fountain", X = 0, Z = 0 } } }, -- 30 from the anchor: its 20-stud landing circle stays clear
			{ Id = "SW_Benches_1", Block = "SW", Role = "benches", Tier = 2, X = -188, Z = 150, Yaw = -90, Kits = { { Kit = "Bench", X = -12, Z = 0 }, { Kit = "Bench", X = 12, Z = 0 } } },
			{ Id = "SW_Benches_2", Block = "SW", Role = "benches", Tier = 2, X = -150, Z = 188, Yaw = 0, Kits = { { Kit = "Bench", X = -12, Z = 0 }, { Kit = "Bench", X = 12, Z = 0 } } },
			{ Id = "SW_House_1", Block = "SW", Role = "house", Tier = 2, X = -150, Z = 213, Yaw = 0, Kits = { { Kit = "AdobeHouse", X = 0, Z = 0, Variant = "wide", Color = Color3.fromRGB(190, 138, 104) } } }, -- faces the square
			{ Id = "SW_Shop", Block = "SW", Role = "house", Tier = 2, X = -150, Z = 44, Yaw = 0, Kits = { { Kit = "AdobeHouse", X = 0, Z = 0, Variant = "shop" } } }, -- frontage on the west arm
			{ Id = "SW_House_2", Block = "SW", Role = "house", Tier = 2, X = -44, Z = 150, Yaw = -90, Kits = { { Kit = "AdobeHouse", X = 0, Z = 0, Color = Color3.fromRGB(204, 176, 132) } } }, -- frontage on the south arm, beside the square
			-- SE: frontage houses, a ruin and a burnt truck on the east arm, the motor pool by Pool_Town
			{ Id = "SE_Shop", Block = "SE", Role = "house", Tier = 1, X = 150, Z = 44, Yaw = 0, Kits = { { Kit = "AdobeHouse", X = 0, Z = 0, Variant = "shop", Color = Color3.fromRGB(190, 138, 104) } } }, -- frontage on the east arm
			{ Id = "SE_Wall", Block = "SE", Role = "wall", Tier = 2, X = 200, Z = 48, Yaw = 0, Kits = { { Kit = "CompoundWall", X = 0, Z = 0, Length = 32 } } },
			{ Id = "SE_Ruin", Block = "SE", Role = "ruin", Tier = 2, X = 212, Z = 96, Yaw = 20, Kits = { { Kit = "RuinedHouse", X = 0, Z = 0 } } },
			{ Id = "SE_Wreck", Block = "SE", Role = "wreck", Tier = 1, X = 250, Z = 52, Yaw = 0, Kits = { { Kit = "Wreck", X = 0, Z = 0, Variant = "truck" } } }, -- burnt truck parked on the east arm
			{ Id = "SE_House_1", Block = "SE", Role = "house", Tier = 2, X = 44, Z = 230, Yaw = 90, Kits = { { Kit = "AdobeHouse", X = 0, Z = 0, Variant = "wide", Color = Color3.fromRGB(204, 176, 132) } } }, -- frontage on the south arm
			{ Id = "SE_MotorPool", Block = "SE", Role = "motorpool", Tier = 2, X = 82, Z = 170, Yaw = 90, Kits = { { Kit = "Jersey", X = -4, Z = 0 }, { Kit = "Jersey", X = 4, Z = 0 }, { Kit = "DrumGroup", X = 0, Z = 3 } } }, -- beside the Pool_Town garage pad (+16 clear)
		} :: { TownCluster },
		Rocks = {
			{ Kind = "rubble", X = 228, Z = 112, Radius = 6, Tier = 1 },
			{ Kind = "rubble", X = 196, Z = 110, Radius = 5, Tier = 1 },
			{ Kind = "scorch", X = 250, Z = 54, Radius = 9, Tier = 1 },
			{ Kind = "rubble", X = -130, Z = -202, Radius = 6, Tier = 1 },
			{ Kind = "rubble", X = 258, Z = -150, Radius = 6, Tier = 1 },
			{ Kind = "rubble", X = -70, Z = 128, Radius = 6, Tier = 1 },
		} :: { TownRock },
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
			{ Id = "Pool_Depot", X = -1180, Z = 34, Yaw = -90 }, -- faces +X (RoadZ0)
			{ Id = "Pool_Armory", X = 1180, Z = -34, Yaw = 90 }, -- faces -X
			{ Id = "Pool_Town", X = 40, Z = 170, Yaw = 0 }, -- faces -Z
			{ Id = "Pool_Airstrip", X = 740, Z = -1180, Yaw = 180 }, -- faces +Z
		} :: { Pad },
		TutorialJeepPad = "Gate_P1", -- the tutorial's jeep step targets the player's own gate pad
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
}

return WorldConfig
