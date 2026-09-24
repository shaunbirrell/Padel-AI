--!strict
--[[
	WAR EMPIRE World v2 Phase 2 (W3) — WorldDressConfig: every tunable of the travel dressing BETWEEN the POIs
	(gap/world_v2_spec.md §4.1–§4.4 and §7.1; roadmap §2.4 WORLD-B builder 2). Read by Server/Modules/WorldDress:
	  * Keepout   — the shared keep-out zones (WorldDress.Zones / WorldDress.Blocked; WorldPOI asserts its clusters too)
	  * Rhythm    — road rhythm: a cluster every 140–180 studs along every visible road, sides alternating (§4.1)
	  * Junctions — one corner kit at each of the 6 visible junctions (§4.2)
	  * Shore     — canal inner-bank features every 320 studs + the Bay's north shore (§4.3)
	  * Scatter   — natural Poisson scatter until the largest empty circle is <= 340 (§4.4)
	  * Quality   — Quality "Low": POIs at 60 %, rhythm every other, no scatter (roadmap §2.4)
	  * Budgets   — part caps per section (spec §7.1); the verifier fails above them
	Units: world studs, north = -Z. Desert floor top = 0.5. Every number is a start value to tune on the owner's phone.
	Placement is seeded (WorldKits.Rng(Seed + salt), a pure-Luau PRNG), so the headless sim and the live server build
	the same layout. Rules are enforced at build time (WorldDress.Blocked + WorldHygiene), never assumed from the sim.
]]

export type Point = { X: number, Z: number }
export type ShoreLine = { Side: string, AlongX: boolean, Across: number, From: number, To: number }
export type KindRow = { Kind: string, Parts: number, Natural: boolean }
export type RockRow = { Radius: number, Outer: number, MaxPrims: number, Count: number? }

local WorldDressConfig = {
	Enabled = true,
	Seed = 702, -- spec §4 (model seed); each section adds its own salt

	-- Folder names under WarEmpireSetup.WorldDressing (POIs build WorldDressing.POI_<Id>; Dockside stays as-is)
	Folders = {
		Rhythm = "Rhythm",
		Junctions = "Junctions",
		Shore = "Shore",
		Scatter = "Scatter",
		POIPrefix = "POI_",
	},

	-- ── Shared keep-outs (WorldDress.Zones / WorldDress.Blocked) ───────────────────────────────────────────────────
	-- A cluster disc (centre x, z; radius r) is free only when its EDGE clears every zone below by the margin.
	Keepout = {
		RoadClear = 13, -- disc edge to any road centre line (H2 corridor 12 + 1); callers may pass a smaller RoadR
		WaterMargin = 6, -- every water rect (public, dock channels, plot water) + the bank
		PlotPadMargin = 40, -- plot pads (square, 320)
		CaptureScale = 1.414, -- TerritoryCapture uses the marker half-diagonal (= WorldConfig.Hygiene)
		CaptureExtra = 25,
		CaptureSkip = { "CoastalOilAlpha", "CoastalOilBravo" }, -- rigs stand in water: the water rule covers them
		PadMargin = 16, -- land garage pads (WorldConfig.Spawns.Garage, 20 x 20)
		ApronMargin = 0, -- front-gate aprons (WorldConfig.Hygiene.GateApron, plot-local)
		POIMargin = 30, -- every POI footprint except the one being built (disabled POIs stay reserved)
		EventClear = 20, -- event anchors: supply crates land here (WorldConfig.Spawns.Event)
		NPCClear = 10, -- NPC anchors (WorldConfig.Spawns.NPC)
		BankExtra = 14, -- Empire Bank: BankRaidConfig.GuardRingRadius (18) + 14 = 32 round BankRaidConfig.Position
		-- dry land inside the ring canal (x ±1760, z -1760 .. 1490), inset 20 (30 at the sea)
		Ring = { X0 = -1740, X1 = 1740, Z0 = -1740, Z1 = 1460 },
	},

	-- ── Road rhythm (spec §4.1: 74 clusters, 240 parts incl. the 6 junction kits) ──────────────────────────────────
	Rhythm = {
		Enabled = true,
		Salt = 1,
		Spacing = { 140, 180 }, -- the next spot is rng(140, 180) studs further along the road
		Offset = { 16, 34 }, -- road centre line to the cluster centre; sides alternate after each accepted cluster
		EndInset = 60, -- start / stop this far from each road end (WaterConfig.RoadEnds)
		JunctionClear = 70, -- no rhythm cluster within 70 of a junction centre (the junction kit is there)
		Radius = 8, -- disc radius for the zone tests; the road test uses RoadR = Radius with RoadClear = Offset[1] - Radius
		CollidableRoadGap = 13, -- every collidable part's AABB stays > 12 from every centre line (H2)
		VisibleRoadGap = 9, -- every visible part taller than 0.3 stays > 8 from every centre line (H2 lane)
		-- kinds rotate in this order over the accepted spots (rock_outcrop = Terrain, 0 parts)
		Kinds = { "rock_outcrop", "wreck_or_nest", "flora_group", "rock_outcrop", "sign_or_marker", "flora_group" },
		KindParts = { rock_outcrop = 0, wreck_or_nest = 6, flora_group = 5, sign_or_marker = 2 },
		Target = 74, -- model count incl. the 6 junction kits (the verifier allows ±15 %)
		MaxParts = 224, -- rhythm clusters; + Junctions 36 = 260 (spec §7.1)
		LowEvery = 2, -- Quality Low keeps half the rhythm clusters of each road (LowPattern); junction kits stay
		-- Low keeps accepted cluster i of a road when LowPattern[(i - 1) % 4 + 1]: the 1st, 4th, 5th, 8th, 9th, … Half of
		-- them, and still alternating sides (sides flip on every accepted cluster, so the 1st, 3rd, 5th … would all sit on
		-- the same side of the road). Low is always a subset of Full (the same spots, the same kits).
		LowPattern = { true, false, false, true },
		-- wreck_or_nest rotates over these recipes (6 parts each; contracts §2.3); sign_or_marker over the variants
		WreckRecipes = { "car", "truck", "nest" },
		MarkerVariants = { "km", "hazard" },
	},

	-- ── Junction kits (spec §4.2: 6 visible junctions, 6 parts each) ───────────────────────────────────────────────
	Junctions = {
		Enabled = true,
		Salt = 2,
		-- (0, 0) is the Town; (0, ±800) are under plots 3 / 4
		Points = {
			{ X = -800, Z = -800 },
			{ X = 800, Z = -800 },
			{ X = -800, Z = 0 },
			{ X = 800, Z = 0 },
			{ X = -800, Z = 800 },
			{ X = 800, Z = 800 },
		} :: { Point },
		Corner = 26, -- kit centre at (+26, +26) from the junction (then (-,+), (+,-), (-,-) when blocked): the corner, never the lane
		Radius = 9,
		Kits = { "DirSign", "Jersey", "Jersey", "SandbagArc" }, -- 2 + 1 + 1 + 2 = 6 parts, + 1 Terrain rock (0 parts)
		Parts = 6,
		-- The world SurfaceGui budget (WorldConfig.Budgets.SurfaceGuis = 12) is 10 garage signs + 1 Town board: the junction
		-- posts are painted arrow boards with NO text in this step (the lead re-plans signs before the other 17 POIs)
		SignText = false,
	},

	-- ── Canal and shore features (spec §4.3: 36 features, 105 parts) ──────────────────────────────────────────────
	Shore = {
		Enabled = true,
		Salt = 3,
		Spacing = 320, -- one feature every 320 studs along each line
		Inset = 28, -- feature centre this far in from the water edge (canal x / z ±1760; the lines below)
		Radius = 8,
		Lines = {
			{ Side = "N", AlongX = true, Across = -1732, From = -1700, To = 1700 },
			{ Side = "W", AlongX = false, Across = -1732, From = -1700, To = 1420 },
			{ Side = "E", AlongX = false, Across = 1732, From = -1700, To = 1420 },
		} :: { ShoreLine },
		-- ring landings (future POI jetties): no bank feature within LandingClear of these
		Landings = { { X = 0, Z = -1769 }, { X = 1769, Z = 0 }, { X = -1769, Z = 0 } } :: { Point },
		LandingClear = 60,
		Kinds = {
			{ Kind = "revetment", Parts = 3, Natural = false },
			{ Kind = "reeds_rocks", Parts = 2, Natural = true },
			{ Kind = "jetty_stub", Parts = 3, Natural = false },
			{ Kind = "barge_wreck", Parts = 5, Natural = false },
			{ Kind = "reeds_rocks", Parts = 2, Natural = true },
		} :: { KindRow },
		-- the Bay's north shore (sea edge z 1490): driftwood, a beached hull, dune grass
		Bay = {
			Z = 1446, -- 1490 - bank 24 - 20
			From = -1700,
			To = 1700,
			Spacing = 300,
			Kinds = {
				{ Kind = "driftwood_rocks", Parts = 2, Natural = true },
				{ Kind = "beached_boat", Parts = 4, Natural = false },
				{ Kind = "dune_grass", Parts = 2, Natural = true },
			} :: { KindRow },
			EdgeZ = 1490, -- the sea's north edge (WaterConfig Sea_* Z0): a beached hull reaches InWaterMax past it
		},
		InWaterMax = 10, -- a jetty stub / barge / hull may reach this far into the water (cluster WE_AllowInWater)
		-- these land kinds step from the bank line to the water's edge (their nearest part LandEdgeGap from the water;
		-- WorldHygiene H3 needs > 6): a revetment, reeds or driftwood 28 studs inland would read as litter on the sand
		ToWater = { revetment = true, reeds_rocks = true, driftwood_rocks = true } :: { [string]: boolean },
		LandEdgeGap = 7.5,
		-- ... and only into these water rects (never a dock channel, lagoon, harbour, slip or sea gate)
		InWaterRects = { "Ring_", "Sea_" },
		MaxParts = 120,
	},

	-- ── Natural scatter (spec §4.4: 49 clusters, 104 parts) ────────────────────────────────────────────────────────
	Scatter = {
		Enabled = true,
		Salt = 4,
		EmptyRadius = 155, -- fill only circles whose centre is more than this from anything (spec: 160; tuned with the target)
		MinSpacing = 120, -- to every other cluster centre (rhythm, shore, POI clusters, other scatter)
		RoadClear = 40, -- cluster centre to any road centre line
		Radius = 10,
		Grid = 24, -- emptiness grid cell (studs)
		-- stop when the largest empty circle (diameter, this grid) is <= 310. world_v2_model.py scatter() runs with
		-- target_diam = 320 (49 clusters; its final V10 measure at cell 20 reads 340). Our keep-outs and POI discs leave
		-- slightly different gaps: 320 stops at 40 clusters, 310 gives 46 (104 parts, far100 12 %, largest 322 at cell 20)
		TargetLargestEmpty = 310,
		MaxIterations = 80,
		MaxClusters = 56, -- model 49 +15 %; FaceMapCentre = false (rollback: no dock channels, more dry land) reaches it
		MaxParts = 120,
		-- kinds rotate (rock_cluster / boulder_field = Terrain, 0 parts)
		Kinds = {
			{ Kind = "rock_cluster", Parts = 0, Natural = true },
			{ Kind = "flora_group", Parts = 5, Natural = true },
			{ Kind = "dead_tree_stumps", Parts = 3, Natural = true },
			{ Kind = "flora_group", Parts = 5, Natural = true },
			{ Kind = "boulder_field", Parts = 0, Natural = true },
			{ Kind = "rock_cluster", Parts = 0, Natural = true },
		} :: { KindRow },
		MinElements = 3, -- H1: a natural cluster stands alone only as >= 3 elements of >= 2 sizes (terrain rocks count)
		-- search (world_v2_model.py scatter()): each round takes up to CirclesPerRound of the largest empty circles
		-- (greedy, the next one at least Suppress x r from the last) whose radius exceeds max(EmptyRadius, Target / 2); try
		-- the circle centre, then Tries - 1 spots jittered by rng(-Jitter, Jitter) x (1 + try / 10). A circle with no legal
		-- spot is not tried again (cells within FailClear x r of its centre leave the candidate list).
		CirclesPerRound = 8,
		Suppress = 1.6,
		Tries = 40,
		Jitter = 40,
		FailClear = 0.5,
		FieldMax = 480, -- distances in the emptiness field are exact up to this (studs); the ring is <= 3,520 across
		-- the dry land the emptiness metric measures (contracts §3.5: inside the ring canal, x ±1760, z -1760 .. 1490)
		Land = { X0 = -1760, X1 = 1760, Z0 = -1760, Z1 = 1490 },
	},

	-- ── Quality ────────────────────────────────────────────────────────────────────────────────────────────────────
	Quality = {
		-- MapSetup: live = "Full"; Studio = DevConfig.WorldDressQuality (default "Low")
		Low = {
			POIShare = 0.6, -- each POI builds its Tier-1 clusters only: parts <= 60 % of its Full build
			RhythmEvery = 2, -- = Rhythm.LowEvery
			Scatter = false,
			ShoreEvery = 1, -- the spec gives no Low rule for the shore: all features stay (ASSUMPTIONS, reversible)
		},
	},

	-- ── Terrain rocks (0 parts; WorldKits.Rock fills them) ────────────────────────────────────────────────────────
	Terrain = {
		MaxPrims = 400, -- spec §7.1: <= 400 rock prims on top of the edge's 2,500
		-- WorldKits.Rock groups as the travel dressing uses them: Radius = opts.Radius passed to Rock (every prim stays
		-- inside it), Outer = the keep-out radius tested with WorldDress.Blocked before the fill (terrain collides: rocks
		-- stay >= 13 off every road line, out of the water + 6 and every zone), MaxPrims = the most prims one call fills
		-- (the terrain budget reserves this much per accepted rock, Full or Low alike), Count = fixed prim count
		Rocks = {
			outcrop = { Radius = 12, Outer = 12, MaxPrims = 4 }, -- road rhythm / scatter rock outcrop (2–4 prims)
			boulders = { Radius = 7, Outer = 7, MaxPrims = 6 }, -- junction corner (3–6 balls)
			boulder_field = { Radius = 14, Outer = 14, MaxPrims = 6, Count = 6 }, -- scatter
			shore = { Radius = 5, Outer = 5, MaxPrims = 3, Count = 3 }, -- reeds / driftwood + rocks on the bank
		} :: { [string]: RockRow },
	},

	-- ── Budgets (spec §7.1; parts outside the bases <= 2,900 Full / 1,900 Low overall) ───────────────────────────────
	Budgets = {
		Rhythm = 224,
		Junctions = 36,
		Shore = 120,
		Scatter = 120,
		RhythmLow = 150, -- every other rhythm cluster + the 6 junction kits
		TerrainPrims = 400,
		BuildSeconds = 1.0, -- WorldDress.Build CPU time in the headless sim (logged)
		-- task.wait() after this many clusters (0 = never). 0 because the whole build is a fraction of a second of server
		-- CPU inside MapSetup's deferred dressing thread (the old coordinate-list dressing never yielded either), and the
		-- headless sim's driver thread cannot yield. Set 25 on live if the owner ever sees a start-up hitch.
		YieldEvery = 0,
	},
}

return WorldDressConfig
