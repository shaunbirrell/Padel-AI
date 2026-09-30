--!strict
--[[
	Code Bot STORE-PROPS (v132, 2026-09-30): the owner's Creator Store picks (docs/PROP-ASSETS.md, 80 ids in shaunie6's
	inventory) wired into the world. Server Services/StorePropsService reads this; nothing else does.

	DO NOT REMOVE: the store props live here (CLAUDE.md). Change a row, never delete the table.

	What happens (server only; the world is shared, so there is no per-player copy):
	  * each id a row uses is loaded ONCE with InsertService:LoadAsset (lazy, one at a time, after the map is up),
	    cleaned (scripts, humanoids, sounds, prompts, seats, particles, physics movers and joints removed, invisible
	    non-colliding parts dropped, every part Anchored, CanTouch off, lights capped and shadowless) and kept in
	    ServerStorage as a template; copies are placed with Clone + ScaleTo + PivotTo;
	  * WORLD rows dress the JOB 31 sites (WorldSitesConfig, "site:<Id>") and the named areas (MapAreas /
	    WorldConfig.POIs, "area:<Id>"): a copy only lands on open, level desert or pavement (5 ground rays, no slope
	    over Place.MaxSlope, bottom on the lowest ray so nothing floats), never on a road (Place.RoadPad), never touching
	    another part (Place.Pad), and >= Place.BaseClearStuds from every base plot (the plots and their rebirth annexes).
	    Mode "roof" = on a flat building roof in that area (all 5 rays on the same roof part);
	  * ZONE rows are the JOB 33 rebirth zone upgrade visuals: when RebirthZoneService builds a zone at level >= 1 for a
	    player this is live for, the Part complex (everything but the yard and the console) is swapped for these store
	    models on the yard. Layouts are checked before anything is removed (inside the yard, clear of the console lane,
	    no overlaps, within budget); any failure keeps the Part build;
	  * performance: Budget caps the parts (world total, per plot, per server); detail under Place.PruneStuds is
	    dropped; parts under Place.ShadowStuds cast no shadow and parts under Place.NoCollideStuds do not collide;
	    every copy is a WorldKits-style cluster (WE_Cluster "store:<kind>") under WorldFill / WE_RebirthZones, so the
	    client QualityGovernor culls small far decoration with its load / unload hysteresis and never culls a
	    building-sized copy (no pop-in on buildings); ModelStreamingMode = Atomic.
	Flags: Enabled = false is the KILL SWITCH (nothing loads, the Part build stays everywhere). Workspace attribute
	WE_StorePropsOff = true is the live kill (removes every copy; zones rebuild as Parts). OwnerFirst = true: world
	props are placed only once the owner (AdminConfig.IsPlaytestOwner) or a Studio tester is in the server, and zone
	visuals only on his plot. World / ZonesOn switch each half.
	Never touches WE_Building*, PreferMesh or VisualAssetConfig.
]]

export type Asset = { Name: string, Cat: string, Creator: string, Use: string, Parts: number, Size: Vector3, Note: string? }
export type WorldRow = { Id: number, At: string, Count: number, Scale: number, Mode: string?, Yaw: number?, Ring: number? }
export type ZoneRow = { Id: number, L0: number, L1: number, X: number, Z: number, Yaw: number, Scale: number }

local StorePropsConfig = {
	Enabled = true, -- KILL SWITCH: false = no store props anywhere (the Part builds as before)
	OwnerFirst = false, -- codebot_v136 launch (owner 2026-09-30 14:17): everyone
	World = true, -- the site / area dressing
	ZonesOn = true, -- the rebirth zone upgrade visuals
	LiveAttribute = "WE_StorePropsOff", -- Workspace attribute: true = remove every copy now

	Budget = {
		MaxWorldParts = 9000, -- all world copies together (the map outside the bases is ~12.6k parts)
		MaxPlotParts = 7200, -- one plot's rebirth zones together (all 7 at level 3 = ~6.9k)
		MaxZoneServerParts = 16000, -- every plot's zone visuals together
		MaxPartsPerModel = 2300, -- a template bigger than this after cleaning is never placed
		MaxLightsPerModel = 2,
	},
	Place = {
		SiteWaitSeconds = 240, -- wait this long for WorldFill.Sites (JOB 31) before dressing without the sites
		BaseClearStuds = 330, -- from every plot centre (the plot + its rebirth annexes reach ~290)
		Pad = 2, -- clearance to any other part
		RoadPad = 8, -- clearance to a road
		MaxSlope = 1.2, -- studs between the highest and lowest ground ray
		Sink = 0.05, -- the bottom sits this far under the lowest ground ray (never floats)
		FloorSlabStuds = 300, -- a part at least this wide and deep is the desert floor
		PavementUp = 2.5, -- a flat slab this close above the floor counts as ground (plazas, pavements)
		RoofMinUp = 8, -- a roof is at least this far above the floor
		Tries = 70, -- random spots tried per copy
		OutsideRing = 90, -- an area row that finds no room inside tries this far outside the area's edge
		SiteRing = 34, -- a site row samples out to the site radius + this
		PruneStuds = 0.2, -- detail parts smaller than this (largest side, after scale) are dropped
		ShadowStuds = 8, -- parts smaller than this cast no shadow
		NoCollideStuds = 1.2, -- parts smaller than this do not collide
		LoadGapSeconds = 0.2, -- between two LoadAsset calls
		PlaceBatch = 4, -- copies placed per frame at most
		ZoneLane = { HalfX = 4.5, FromZ = 21 }, -- the console walk lane kept clear (annex local)
		ZoneEdge = 0.9, -- store models stay this far inside the yard curbs
	},

	Assets = {
		[9171585794] = { Name = "destroyed tank", Cat = "Tank wreck", Creator = "lobo73_audas", Use = "world", Parts = 12, Size = Vector3.new(20.3, 13.9, 26.3) },
		[9014990866] = { Name = "Destroyed Tank", Cat = "Tank wreck", Creator = "ElPelochorizo1", Use = "world", Parts = 2, Size = Vector3.new(45.0, 23.9, 21.8) },
		[2473378608] = { Name = "Destroyed tank", Cat = "Tank wreck", Creator = "IncursionFade", Use = "rejected", Parts = 263, Size = Vector3.new(25.2, 11.5, 23.1), Note = "the model inside is named \"m4 sherman\": a real-tank replica (CLAUDE.md: no real-world copies)" },
		[14269073207] = { Name = "destroyed tank mesh", Cat = "Vehicle wreck (APC)", Creator = "Oddsans33123", Use = "world", Parts = 16, Size = Vector3.new(22.9, 22.1, 34.2) },
		[8453210953] = { Name = "Destroyed)tanker truck (mesh)", Cat = "Vehicle wreck (truck)", Creator = "908KS_RKO", Use = "world", Parts = 2, Size = Vector3.new(59.7, 12.2, 21.0) },
		[1650602509] = { Name = "Destroyed Truck", Cat = "Vehicle wreck (truck)", Creator = "EpicCrossingSwords", Use = "world", Parts = 2, Size = Vector3.new(13.8, 9.3, 41.4) },
		[13989569039] = { Name = "Destroyed Gaz Jeep Mesh", Cat = "Vehicle wreck (jeep)", Creator = "cjng0909R", Use = "world", Parts = 6, Size = Vector3.new(12.2, 10.8, 23.7) },
		[4128315411] = { Name = "Wrecked White Car (Mesh)", Cat = "Vehicle wreck (car)", Creator = "bearduckmonkey", Use = "world", Parts = 2, Size = Vector3.new(6.6, 5.2, 14.1) },
		[3117530492] = { Name = "Rusty Car 4 (Mesh)", Cat = "Vehicle wreck (car)", Creator = "bearduckmonkey", Use = "rejected", Parts = 1, Size = Vector3.new(6.8, 4.1, 15.2), Note = "the mesh is named \"Volga (Metro 2033)\": a real car + franchise rip" },
		[5678434293] = { Name = "Sandbag Barrier", Cat = "Barriers", Creator = "vx0rn", Use = "both", Parts = 1, Size = Vector3.new(19.4, 4.7, 3.4) },
		[5678429543] = { Name = "Sandbags Corner", Cat = "Barriers", Creator = "vx0rn", Use = "world", Parts = 1, Size = Vector3.new(13.2, 4.2, 14.8) },
		[11654379868] = { Name = "Tank Trap", Cat = "Barriers", Creator = "TNMOXA8262", Use = "both", Parts = 1, Size = Vector3.new(7.7, 5.9, 7.6) },
		[1230286742] = { Name = "Spiral Barbed Wire", Cat = "Barriers", Creator = "bigcrazycarboy", Use = "both", Parts = 4, Size = Vector3.new(11.9, 4.1, 4.1) },
		[9154880131] = { Name = "Hesco Barrier", Cat = "Barriers", Creator = "Niceforme124", Use = "both", Parts = 1, Size = Vector3.new(7.0, 7.0, 7.0) },
		[4128301030] = { Name = "textured mesh road barrier", Cat = "Barriers", Creator = "bearduckmonkey", Use = "world", Parts = 1, Size = Vector3.new(2.5, 3.0, 7.2) },
		[2190705941] = { Name = "Military Crates & Ammo Resupply", Cat = "Crates/supply", Creator = "mrlengthly", Use = "both", Parts = 26, Size = Vector3.new(6.3, 4.5, 12.7) },
		[2930926216] = { Name = "Military Crates", Cat = "Crates/supply", Creator = "XIArchangel", Use = "world", Parts = 64, Size = Vector3.new(9.2, 6.7, 9.2) },
		[16540055496] = { Name = "Military Crates", Cat = "Crates/supply", Creator = "Antonov_Slonovskaya", Use = "both", Parts = 5, Size = Vector3.new(7.4, 4.2, 6.2) },
		[9021582812] = { Name = "PBR Oil Barrel", Cat = "Crates/supply", Creator = "Wabbiits", Use = "both", Parts = 1, Size = Vector3.new(1.8, 2.8, 1.8) },
		[9352751052] = { Name = "Watchtower", Cat = "Watchtower", Creator = "Flooksies", Use = "both", Parts = 148, Size = Vector3.new(16.0, 37.2, 16.0) },
		[3392535391] = { Name = "Watchtower", Cat = "Watchtower", Creator = "oxrock", Use = "world", Parts = 291, Size = Vector3.new(32.0, 50.6, 40.2) },
		[1974692711] = { Name = "WatchTower", Cat = "Watchtower", Creator = "urtotallyright", Use = "world", Parts = 216, Size = Vector3.new(35.0, 69.0, 37.0) },
		[12273282787] = { Name = "Bunker ww2", Cat = "Bunker/pillbox", Creator = "procheetah200", Use = "both", Parts = 110, Size = Vector3.new(29.0, 9.5, 21.8) },
		[15797919882] = { Name = "Ww1 Bunker", Cat = "Bunker/pillbox", Creator = "jaytlam2019abc", Use = "both", Parts = 108, Size = Vector3.new(28.9, 9.4, 28.3) },
		[182529039] = { Name = "Military Canvas Tent", Cat = "Tents", Creator = "Quenty", Use = "unused", Parts = 336, Size = Vector3.new(42.5, 18.7, 68.0), Note = "336 parts: the 6-part Modern Military Tent is used instead" },
		[11558767918] = { Name = "Modern Military Tent", Cat = "Tents", Creator = "APETTR2", Use = "both", Parts = 6, Size = Vector3.new(48.6, 13.2, 29.1) },
		[10485439002] = { Name = "RGG millitary tent", Cat = "Tents", Creator = "Y4mist", Use = "world", Parts = 8, Size = Vector3.new(33.8, 12.5, 45.0) },
		[8220562195] = { Name = "Military medical tent", Cat = "Tents", Creator = "LoganPlayz907", Use = "world", Parts = 212, Size = Vector3.new(34.5, 10.0, 27.0) },
		[11989298499] = { Name = "Military Gate or Border Gate", Cat = "Checkpoint/gate", Creator = "RealTrey_YT", Use = "unused", Parts = 1067, Size = Vector3.new(106.3, 20.2, 75.3), Note = "JOB 37 builds the road checkpoint from our own Parts by spec (no store models); kept for later" },
		[12125769119] = { Name = "Military Boarder or Gate", Cat = "Checkpoint/gate", Creator = "RealTrey_YT", Use = "unused", Parts = 697, Size = Vector3.new(83.6, 20.2, 61.0), Note = "JOB 37 builds the road checkpoint from our own Parts by spec (no store models); kept for later" },
		[9404286622] = { Name = "Military Checkpoint", Cat = "Checkpoint/gate", Creator = "R00So_o", Use = "unused", Parts = 84, Size = Vector3.new(8.2, 8.7, 41.9), Note = "JOB 37 builds the road checkpoint from our own Parts by spec (no store models); kept for later" },
		[8279648205] = { Name = "Boom gate", Cat = "Checkpoint/gate", Creator = "mortixPL", Use = "unused", Parts = 13, Size = Vector3.new(12.1, 8.6, 2.0), Note = "JOB 37 builds the road checkpoint from our own Parts by spec (no store models); kept for later" },
		[447143432] = { Name = "Ruined Apartment Building", Cat = "Ruined village", Creator = "TevRCC", Use = "world", Parts = 826, Size = Vector3.new(35.6, 54.2, 58.0) },
		[161539117] = { Name = "Desert House 2", Cat = "Ruined village", Creator = "SgtHamy", Use = "world", Parts = 101, Size = Vector3.new(30.2, 12.2, 29.2) },
		[16988151510] = { Name = "Ruined Building", Cat = "Ruined village", Creator = "jstedebilove", Use = "world", Parts = 61, Size = Vector3.new(631.4, 270.9, 372.0) },
		[539121004] = { Name = "Destroyed house", Cat = "Ruined village", Creator = "ImFarAway", Use = "world", Parts = 327, Size = Vector3.new(24.2, 11.8, 22.9) },
		[13525922265] = { Name = "Realistic Oil Pumpjack", Cat = "Oil field", Creator = "Unit5532", Use = "world", Parts = 172, Size = Vector3.new(52.0, 41.3, 18.0) },
		[395208145] = { Name = "Oil Pump (Pumpjack)", Cat = "Oil field", Creator = "Dummiez", Use = "world", Parts = 241, Size = Vector3.new(52.0, 41.3, 18.0) },
		[15569446609] = { Name = "Storage Tank", Cat = "Oil field", Creator = "Antonov_Slonovskaya", Use = "both", Parts = 1, Size = Vector3.new(30.5, 47.7, 33.9) },
		[15753397958] = { Name = "Fuel Tank", Cat = "Oil field", Creator = "Antonov_Slonovskaya", Use = "both", Parts = 4, Size = Vector3.new(6.0, 7.1, 12.9) },
		[9370327334] = { Name = "industrial pipes w/ valve", Cat = "Oil field", Creator = "amb6ent", Use = "unused", Parts = 201, Size = Vector3.new(8.2, 12.3, 5.2), Note = "201 parts for an 8-stud pipe cluster: poor detail per part" },
		[12423243620] = { Name = "Office Building", Cat = "City building (enterable)", Creator = "iLegend66", Use = "world", Parts = 1066, Size = Vector3.new(57.7, 64.8, 94.5) },
		[5201630514] = { Name = "[NO SCRIPTS] Hospital Building", Cat = "City building (enterable)", Creator = "TheWingedGuest", Use = "world", Parts = 406, Size = Vector3.new(68.5, 54.4, 48.7) },
		[18521807804] = { Name = "Building w/ Interior", Cat = "City building (enterable)", Creator = "Ebigdog1", Use = "world", Parts = 64, Size = Vector3.new(89.0, 26.8, 52.1) },
		[16365964601] = { Name = "Desert house", Cat = "City building (enterable)", Creator = "RussianAndRobloxer", Use = "world", Parts = 317, Size = Vector3.new(52.4, 17.0, 26.7) },
		[14243660153] = { Name = "New York City Corner Apartment Building", Cat = "City building (shell)", Creator = "Lihtsameelseke", Use = "unused", Parts = 2568, Size = Vector3.new(51.8, 66.4, 51.8), Note = "2568 unanchored parts: over Budget.MaxPartsPerModel" },
		[227190265] = { Name = "BEPC Air Conditioner Unit", Cat = "Rooftop props", Creator = "BackupSilly10", Use = "world", Parts = 36, Size = Vector3.new(6.8, 7.2, 11.6) },
		[4112608919] = { Name = "Water Tower 1 (Mesh)", Cat = "Rooftop props", Creator = "bearduckmonkey", Use = "world", Parts = 1, Size = Vector3.new(24.8, 101.5, 24.9) },
		[5193302623] = { Name = "Rooftop Prop 1", Cat = "Rooftop props", Creator = "olhuk", Use = "world", Parts = 18, Size = Vector3.new(6.0, 1.7, 6.0) },
		[262712273] = { Name = "Satellite Dish", Cat = "Rooftop props", Creator = "Balefulness", Use = "both", Parts = 63, Size = Vector3.new(49.6, 64.0, 51.8) },
		[11146095708] = { Name = "Street Lamp", Cat = "Street props", Creator = "BryanROBLOXgamer10", Use = "world", Parts = 4, Size = Vector3.new(12.0, 22.0, 2.0) },
		[96257169] = { Name = "Trash Dumpster", Cat = "Street props", Creator = "TofuBytes", Use = "world", Parts = 1, Size = Vector3.new(6.0, 6.9, 9.0) },
		[574054179] = { Name = "4 Wire Power Pole", Cat = "Street props", Creator = "JacobSMT", Use = "world", Parts = 39, Size = Vector3.new(8.0, 42.0, 2.0) },
		[2766525411] = { Name = "road barrier", Cat = "Street props", Creator = "SiameseMouse", Use = "world", Parts = 33, Size = Vector3.new(3.0, 4.2, 9.0) },
		[8878478175] = { Name = "factory", Cat = "Tank Factory", Creator = "monaliso12345", Use = "zone", Parts = 2117, Size = Vector3.new(127.0, 81.7, 242.0) },
		[2955329464] = { Name = "[Free] Stalinist Factory", Cat = "Tank Factory", Creator = "Vestegnens", Use = "unused", Parts = 1932, Size = Vector3.new(233.0, 165.0, 75.4), Note = "1932 parts, 233 x 165 studs: world budget" },
		[12734850183] = { Name = "Medium Warehouse", Cat = "Tank Factory", Creator = "CRRAANNNEEEEEEE", Use = "unused", Parts = 1711, Size = Vector3.new(73.8, 33.5, 104.8), Note = "1711 parts for a plain warehouse box: poor detail per part (world budget)" },
		[4784051512] = { Name = "Delta - 09 Missile Silo", Cat = "Nuclear Silo", Creator = "Lephicent", Use = "zone", Parts = 1723, Size = Vector3.new(26.1, 6.3, 19.5) },
		[7649697954] = { Name = "Improved nuclear missile silo", Cat = "Nuclear Silo", Creator = "WillRichterian", Use = "unused", Parts = 562, Size = Vector3.new(77.2, 102.5, 131.2), Note = "562 parts, 131 studs long: the Delta-09 complex is the silo pick" },
		[2861271828] = { Name = "Nuclear Missile", Cat = "Nuclear Silo", Creator = "nacker", Use = "zone", Parts = 32, Size = Vector3.new(16.0, 24.0, 19.0) },
		[929752007] = { Name = "QF Artillery", Cat = "Artillery Battery", Creator = "Aslanovich99", Use = "zone", Parts = 123, Size = Vector3.new(5.4, 5.2, 13.8) },
		[8535467243] = { Name = "Artillery gun (working)", Cat = "Artillery Battery", Creator = "Xenofell", Use = "world", Parts = 79, Size = Vector3.new(28.7, 9.6, 21.9) },
		[97895120562997] = { Name = "Artillery", Cat = "Artillery Battery", Creator = "retrogamer4590", Use = "both", Parts = 35, Size = Vector3.new(17.3, 20.9, 17.9) },
		[9064883345] = { Name = "Military Hangar", Cat = "Drone Hangar", Creator = "Germanyinaldi", Use = "unused", Parts = 1021, Size = Vector3.new(210.4, 56.9, 196.3), Note = "1021 parts: world budget (the Airstrip uses the 29-part Military Garage)" },
		[12365928579] = { Name = "Military Garage", Cat = "Drone Hangar", Creator = "PrinzAaron", Use = "both", Parts = 29, Size = Vector3.new(56.3, 21.3, 47.3) },
		[12922051897] = { Name = "Detailed HeliPad (Helicopter)", Cat = "Drone Hangar", Creator = "JuanCool_2004", Use = "unused", Parts = 1280, Size = Vector3.new(63.0, 19.1, 76.5), Note = "1280 parts: world budget (the Airstrip uses the 29-part Military Garage)" },
		[72422635987072] = { Name = "Drone", Cat = "Drone Hangar (drones)", Creator = "xXprogameryotXx", Use = "both", Parts = 7, Size = Vector3.new(3.7, 0.8, 3.2) },
		[132341868819826] = { Name = "Drone Molniya Handmade", Cat = "Drone Hangar (drones)", Creator = "IsuperDuperPro999", Use = "both", Parts = 45, Size = Vector3.new(8.8, 1.8, 8.8) },
		[2580028799] = { Name = "Recon Drone", Cat = "Drone Hangar (drones)", Creator = "XenoSynthesis", Use = "rejected", Parts = 1, Size = Vector3.new(1.0, 0.1, 1.0), Note = "it is a Tool with one flat 1x0.1x1 Handle part, not a drone model" },
		[8388537872] = { Name = "military base", Cat = "Elite Barracks", Creator = "Cenimosity", Use = "world", Parts = 326, Size = Vector3.new(155.6, 51.5, 125.3) },
		[11530941074] = { Name = "army base", Cat = "Elite Barracks", Creator = "Surfyxek", Use = "world", Parts = 309, Size = Vector3.new(91.5, 30.8, 67.8) },
		[8637034739] = { Name = "Military Barracks /Hostel", Cat = "Elite Barracks", Creator = "AviGaTro", Use = "unused", Parts = 38, Size = Vector3.new(35.3, 14.2, 73.0), Note = "a plain dark block: worse than our Part barracks (trim colour, 2/3/4 storeys), so the Elite Barracks keeps its Part build" },
		[4669786564] = { Name = "Oil Refinery", Cat = "Oil Refinery", Creator = "Lephicent", Use = "zone", Parts = 1230, Size = Vector3.new(36.8, 8.2, 28.0) },
		[15362548171] = { Name = "Oil Refinery Factory🏭", Cat = "Oil Refinery", Creator = "avav107", Use = "unused", Parts = 3819, Size = Vector3.new(266.2, 55.5, 176.4), Note = "3819 parts: over Budget.MaxPartsPerModel" },
		[7210304938] = { Name = "Refinery Structure", Cat = "Oil Refinery", Creator = "monsterguy90", Use = "unused", Parts = 958, Size = Vector3.new(67.5, 103.8, 117.7), Note = "5704 decals: far too heavy for phones" },
		[412251367] = { Name = "Concrete Bunker", Cat = "Bunker Complex", Creator = "JOHNEY9987", Use = "both", Parts = 42, Size = Vector3.new(23.1, 8.9, 10.9) },
		[6433272094] = { Name = "Dune Buggy", Cat = "Rebirth vehicle", Creator = "Roblox", Use = "world", Parts = 153, Size = Vector3.new(45.9, 7.0, 16.8) },
		[608760179] = { Name = "Racing Buggy", Cat = "Rebirth vehicle", Creator = "sheenamoonFun", Use = "world", Parts = 97, Size = Vector3.new(5.7, 5.5, 10.4) },
		[6192529467] = { Name = "Military Jeep, This is for transport.", Cat = "Rebirth vehicle", Creator = "boogalooSaint", Use = "world", Parts = 52, Size = Vector3.new(7.7, 7.2, 19.2) },
		[4928101363] = { Name = "Tank (Works) public!", Cat = "Rebirth vehicle", Creator = "xFavihx", Use = "both", Parts = 157, Size = Vector3.new(17.0, 17.2, 45.8) },
	} :: { [number]: Asset },

	-- world dressing, placed in this order (the heroes first, so a spent budget only drops small props)
	WorldRows = {
		{ Id = 16365964601, At = "site:DryWell", Count = 1, Scale = 1.0 },
		{ Id = 3392535391, At = "site:Overwatch", Count = 1, Scale = 0.7 },
		{ Id = 8388537872, At = "site:DustCamp", Count = 1, Scale = 0.6, Ring = 130 },
		{ Id = 12423243620, At = "area:Town", Count = 1, Scale = 1.0 },
		{ Id = 5201630514, At = "area:Town", Count = 1, Scale = 0.9 },
		{ Id = 447143432, At = "area:Ruins", Count = 1, Scale = 0.8 },
		{ Id = 539121004, At = "area:Ruins", Count = 1, Scale = 1.0 },
		{ Id = 11530941074, At = "area:Armory", Count = 1, Scale = 0.85 },
		{ Id = 11558767918, At = "site:CampViper", Count = 1, Scale = 0.55 },
		{ Id = 10485439002, At = "site:CampViper", Count = 1, Scale = 0.5 },
		{ Id = 9352751052, At = "site:CampViper", Count = 1, Scale = 0.85 },
		{ Id = 5678434293, At = "site:CampViper", Count = 3, Scale = 1.0 },
		{ Id = 2190705941, At = "site:CampViper", Count = 2, Scale = 1.0 },
		{ Id = 9021582812, At = "site:CampViper", Count = 4, Scale = 1.0 },
		{ Id = 13989569039, At = "site:CampViper", Count = 1, Scale = 0.65 },
		{ Id = 6192529467, At = "site:CampViper", Count = 1, Scale = 1.0 },
		{ Id = 161539117, At = "site:DryWell", Count = 1, Scale = 1.0 },
		{ Id = 16988151510, At = "site:DryWell", Count = 1, Scale = 0.1 },
		{ Id = 4112608919, At = "site:DryWell", Count = 1, Scale = 0.3 },
		{ Id = 4128315411, At = "site:DryWell", Count = 1, Scale = 1.0 },
		{ Id = 18521807804, At = "site:DryWell", Count = 1, Scale = 0.6 },
		{ Id = 96257169, At = "site:DryWell", Count = 1, Scale = 1.0 },
		{ Id = 13525922265, At = "site:PumpSeven", Count = 1, Scale = 0.55 },
		{ Id = 15569446609, At = "site:PumpSeven", Count = 1, Scale = 0.4 },
		{ Id = 15753397958, At = "site:PumpSeven", Count = 2, Scale = 1.0 },
		{ Id = 9021582812, At = "site:PumpSeven", Count = 6, Scale = 1.0 },
		{ Id = 8453210953, At = "site:PumpSeven", Count = 1, Scale = 0.6 },
		{ Id = 2190705941, At = "site:Kestrel", Count = 3, Scale = 1.0 },
		{ Id = 16540055496, At = "site:Kestrel", Count = 3, Scale = 1.0 },
		{ Id = 2930926216, At = "site:Kestrel", Count = 2, Scale = 1.0 },
		{ Id = 4128301030, At = "site:Kestrel", Count = 4, Scale = 1.0 },
		{ Id = 9154880131, At = "site:Kestrel", Count = 4, Scale = 1.0 },
		{ Id = 1650602509, At = "site:Kestrel", Count = 1, Scale = 0.8 },
		{ Id = 574054179, At = "site:Kestrel", Count = 1, Scale = 1.0 },
		{ Id = 12273282787, At = "site:Overwatch", Count = 1, Scale = 1.0 },
		{ Id = 15797919882, At = "site:Overwatch", Count = 1, Scale = 0.8 },
		{ Id = 1230286742, At = "site:Overwatch", Count = 4, Scale = 1.0 },
		{ Id = 5678429543, At = "site:Overwatch", Count = 2, Scale = 1.0 },
		{ Id = 9171585794, At = "site:Anvil", Count = 2, Scale = 0.8 },
		{ Id = 9014990866, At = "site:Anvil", Count = 1, Scale = 0.5 },
		{ Id = 14269073207, At = "site:Anvil", Count = 2, Scale = 0.6 },
		{ Id = 11654379868, At = "site:Anvil", Count = 6, Scale = 1.0 },
		{ Id = 13989569039, At = "site:Anvil", Count = 1, Scale = 0.65 },
		{ Id = 1650602509, At = "site:Anvil", Count = 1, Scale = 0.8 },
		{ Id = 8220562195, At = "site:DustCamp", Count = 1, Scale = 0.8 },
		{ Id = 9154880131, At = "site:DustCamp", Count = 4, Scale = 1.0 },
		{ Id = 16540055496, At = "site:DustCamp", Count = 2, Scale = 1.0 },
		{ Id = 11558767918, At = "site:DustCamp", Count = 1, Scale = 0.5 },
		{ Id = 11146095708, At = "area:Town", Count = 8, Scale = 1.0 },
		{ Id = 96257169, At = "area:Town", Count = 4, Scale = 1.0 },
		{ Id = 2766525411, At = "area:Town", Count = 4, Scale = 1.0 },
		{ Id = 4128315411, At = "area:Town", Count = 2, Scale = 1.0 },
		{ Id = 227190265, At = "area:Town", Count = 4, Scale = 1.0, Mode = "roof" },
		{ Id = 5193302623, At = "area:Town", Count = 4, Scale = 1.0, Mode = "roof" },
		{ Id = 4112608919, At = "area:Town", Count = 2, Scale = 0.2, Mode = "roof" },
		{ Id = 262712273, At = "area:Town", Count = 2, Scale = 0.12, Mode = "roof" },
		{ Id = 16988151510, At = "area:Ruins", Count = 1, Scale = 0.1 },
		{ Id = 161539117, At = "area:Ruins", Count = 1, Scale = 1.0 },
		{ Id = 4128315411, At = "area:Ruins", Count = 2, Scale = 1.0 },
		{ Id = 395208145, At = "area:OilField", Count = 1, Scale = 0.6 },
		{ Id = 15569446609, At = "area:OilField", Count = 3, Scale = 0.4 },
		{ Id = 15753397958, At = "area:OilField", Count = 2, Scale = 1.0 },
		{ Id = 9021582812, At = "area:OilField", Count = 8, Scale = 1.0 },
		{ Id = 8453210953, At = "area:OilField", Count = 1, Scale = 0.6 },
		{ Id = 2930926216, At = "area:Depot", Count = 2, Scale = 1.0 },
		{ Id = 2190705941, At = "area:Depot", Count = 2, Scale = 1.0 },
		{ Id = 4128301030, At = "area:Depot", Count = 4, Scale = 1.0 },
		{ Id = 1650602509, At = "area:Depot", Count = 1, Scale = 0.8 },
		{ Id = 15753397958, At = "area:Depot", Count = 1, Scale = 1.0 },
		{ Id = 9154880131, At = "area:Armory", Count = 4, Scale = 1.0 },
		{ Id = 4928101363, At = "area:Armory", Count = 2, Scale = 0.42 },
		{ Id = 6192529467, At = "area:Armory", Count = 1, Scale = 1.0 },
		{ Id = 12365928579, At = "area:Airstrip", Count = 2, Scale = 0.8 },
		{ Id = 72422635987072, At = "area:Airstrip", Count = 3, Scale = 2.0 },
		{ Id = 132341868819826, At = "area:Airstrip", Count = 2, Scale = 1.3 },
		{ Id = 262712273, At = "area:Radar", Count = 1, Scale = 0.6 },
		{ Id = 262712273, At = "area:Signal", Count = 1, Scale = 0.45 },
		{ Id = 574054179, At = "area:Signal", Count = 2, Scale = 1.0 },
		{ Id = 11146095708, At = "area:Port", Count = 3, Scale = 1.0 },
		{ Id = 4128301030, At = "area:Port", Count = 4, Scale = 1.0 },
		{ Id = 2766525411, At = "area:Port", Count = 4, Scale = 1.0 },
		{ Id = 9171585794, At = "area:Crash", Count = 1, Scale = 0.8 },
		{ Id = 14269073207, At = "area:Crash", Count = 1, Scale = 0.6 },
		{ Id = 1650602509, At = "area:Crash", Count = 1, Scale = 0.8 },
		{ Id = 9352751052, At = "area:Quarry", Count = 1, Scale = 0.8 },
		{ Id = 10485439002, At = "area:Quarry", Count = 1, Scale = 0.5 },
		{ Id = 1974692711, At = "area:RidgeCamp", Count = 1, Scale = 0.5 },
		{ Id = 11558767918, At = "area:RidgeCamp", Count = 1, Scale = 0.5 },
		{ Id = 11558767918, At = "area:DuneCamp", Count = 1, Scale = 0.5 },
		{ Id = 2190705941, At = "area:DuneCamp", Count = 2, Scale = 1.0 },
		{ Id = 11558767918, At = "area:Oasis", Count = 1, Scale = 0.55 },
		{ Id = 6433272094, At = "area:Oasis", Count = 1, Scale = 1.0 },
		{ Id = 608760179, At = "area:Oasis", Count = 1, Scale = 1.0 },
		{ Id = 11654379868, At = "area:FortI", Count = 6, Scale = 1.0 },
		{ Id = 9014990866, At = "area:FortI", Count = 1, Scale = 0.5 },
		{ Id = 97895120562997, At = "area:FortI", Count = 2, Scale = 0.8 },
		{ Id = 412251367, At = "area:FortI", Count = 1, Scale = 1.0 },
		{ Id = 1230286742, At = "area:FortI", Count = 3, Scale = 1.0 },
		{ Id = 11654379868, At = "area:FortS", Count = 6, Scale = 1.0 },
		{ Id = 15797919882, At = "area:FortS", Count = 1, Scale = 0.8 },
		{ Id = 8535467243, At = "area:FortS", Count = 1, Scale = 0.7 },
		{ Id = 5678429543, At = "area:FortS", Count = 2, Scale = 1.0 },
		{ Id = 15569446609, At = "area:RigA", Count = 1, Scale = 0.4 },
		{ Id = 9021582812, At = "area:RigA", Count = 4, Scale = 1.0 },
		{ Id = 15569446609, At = "area:RigB", Count = 1, Scale = 0.4 },
		{ Id = 9021582812, At = "area:RigB", Count = 4, Scale = 1.0 },
	} :: { WorldRow },

	-- rebirth zone upgrade visuals: annex-local X/Z (studs; +Z faces the base, the console is at X 0, Z +27), Yaw in 90s
	ZoneRows = {
		WestYard = {
			{ Id = 12365928579, L0 = 1, L1 = 2, X = -10, Z = -8, Yaw = 0, Scale = 0.85 },
			{ Id = 4928101363, L0 = 1, L1 = 2, X = 26, Z = -12, Yaw = 0, Scale = 0.42 },
			{ Id = 4928101363, L0 = 2, L1 = 2, X = 26, Z = 12, Yaw = 0, Scale = 0.42 },
			{ Id = 16540055496, L0 = 2, L1 = 2, X = 14, Z = 19, Yaw = 0, Scale = 1.0 },
			{ Id = 15753397958, L0 = 2, L1 = 3, X = -28, Z = 20, Yaw = 0, Scale = 1.0 },
			{ Id = 8878478175, L0 = 3, L1 = 3, X = 0, Z = -11, Yaw = 90, Scale = 0.28 },
			{ Id = 4928101363, L0 = 3, L1 = 3, X = 22, Z = 15, Yaw = 90, Scale = 0.42 },
			{ Id = 4928101363, L0 = 3, L1 = 3, X = -8, Z = 15, Yaw = 90, Scale = 0.42 },
			{ Id = 16540055496, L0 = 3, L1 = 3, X = 31, Z = 23, Yaw = 0, Scale = 1.0 },
		},
		StrategicYard = {
			{ Id = 2861271828, L0 = 1, L1 = 2, X = 0, Z = -10, Yaw = 0, Scale = 1.0 },
			{ Id = 12273282787, L0 = 1, L1 = 2, X = 22, Z = -17, Yaw = 180, Scale = 0.8 },
			{ Id = 15753397958, L0 = 2, L1 = 3, X = -28, Z = 16, Yaw = 0, Scale = 1.0 },
			{ Id = 262712273, L0 = 2, L1 = 2, X = -24, Z = -17, Yaw = 0, Scale = 0.28 },
			{ Id = 262712273, L0 = 3, L1 = 3, X = 26, Z = 14, Yaw = 0, Scale = 0.26 },
			{ Id = 4784051512, L0 = 3, L1 = 3, X = -8, Z = -10, Yaw = 0, Scale = 1.9 },
			{ Id = 2861271828, L0 = 3, L1 = 3, X = 24, Z = -12, Yaw = 0, Scale = 0.8 },
		},
		WestStrip = {
			{ Id = 97895120562997, L0 = 1, L1 = 3, X = -22, Z = -14, Yaw = 0, Scale = 0.8 },
			{ Id = 97895120562997, L0 = 1, L1 = 3, X = 0, Z = -14, Yaw = 0, Scale = 0.8 },
			{ Id = 5678434293, L0 = 1, L1 = 3, X = -22, Z = -26, Yaw = 0, Scale = 0.8 },
			{ Id = 5678434293, L0 = 1, L1 = 3, X = 0, Z = -26, Yaw = 0, Scale = 0.8 },
			{ Id = 12273282787, L0 = 1, L1 = 3, X = 24, Z = -17, Yaw = 180, Scale = 0.8 },
			{ Id = 929752007, L0 = 2, L1 = 3, X = -24, Z = 10, Yaw = 0, Scale = 1.2 },
			{ Id = 929752007, L0 = 2, L1 = 3, X = -12, Z = 10, Yaw = 0, Scale = 1.2 },
			{ Id = 2190705941, L0 = 2, L1 = 3, X = 12, Z = 6, Yaw = 0, Scale = 1.0 },
			{ Id = 9352751052, L0 = 3, L1 = 3, X = 28, Z = 14, Yaw = 0, Scale = 0.75 },
			{ Id = 9154880131, L0 = 3, L1 = 3, X = -10, Z = 24, Yaw = 0, Scale = 1.0 },
			{ Id = 9154880131, L0 = 3, L1 = 3, X = 10, Z = 24, Yaw = 0, Scale = 1.0 },
		},
		DroneBay = {
			{ Id = 12365928579, L0 = 1, L1 = 3, X = -14, Z = -9, Yaw = 0, Scale = 0.75 },
			{ Id = 72422635987072, L0 = 1, L1 = 3, X = 20, Z = -14, Yaw = 0, Scale = 2.0 },
			{ Id = 72422635987072, L0 = 1, L1 = 3, X = 30, Z = -14, Yaw = 0, Scale = 2.0 },
			{ Id = 132341868819826, L0 = 2, L1 = 3, X = 18, Z = 0, Yaw = 0, Scale = 1.3 },
			{ Id = 132341868819826, L0 = 2, L1 = 3, X = 30, Z = 0, Yaw = 0, Scale = 1.2 },
			{ Id = 262712273, L0 = 2, L1 = 3, X = 26, Z = 17, Yaw = 0, Scale = 0.26 },
			{ Id = 72422635987072, L0 = 3, L1 = 3, X = 20, Z = -24, Yaw = 0, Scale = 2.0 },
			{ Id = 72422635987072, L0 = 3, L1 = 3, X = 30, Z = -24, Yaw = 0, Scale = 2.0 },
			{ Id = 16540055496, L0 = 3, L1 = 3, X = -28, Z = 17, Yaw = 0, Scale = 1.0 },
			{ Id = 2190705941, L0 = 3, L1 = 3, X = -18, Z = 17, Yaw = 0, Scale = 1.0 },
		},
		EastYard = {
			-- the store barracks (8637034739) is a plain dark block: worse than our Part barracks (trim colour, grows 2/3/4
			-- storeys), so this zone KEEPS its Part build and only adds store dressing round it (ZoneKeepParts)
			{ Id = 11558767918, L0 = 2, L1 = 3, X = -20, Z = 15, Yaw = 0, Scale = 0.5 },
			{ Id = 16540055496, L0 = 2, L1 = 3, X = 10, Z = 12, Yaw = 0, Scale = 1.0 },
			{ Id = 2190705941, L0 = 2, L1 = 3, X = 20, Z = 10, Yaw = 0, Scale = 1.0 },
			{ Id = 9154880131, L0 = 3, L1 = 3, X = 12, Z = 22, Yaw = 0, Scale = 0.9 },
			{ Id = 9154880131, L0 = 3, L1 = 3, X = 19, Z = 22, Yaw = 0, Scale = 0.9 },
		},

		EastStrip = {
			{ Id = 15569446609, L0 = 1, L1 = 2, X = -27, Z = -20, Yaw = 0, Scale = 0.3 },
			{ Id = 15569446609, L0 = 1, L1 = 2, X = -27, Z = -6, Yaw = 0, Scale = 0.3 },
			{ Id = 15753397958, L0 = 1, L1 = 2, X = -12, Z = -18, Yaw = 0, Scale = 1.0 },
			{ Id = 9021582812, L0 = 1, L1 = 2, X = -14, Z = -6, Yaw = 0, Scale = 1.2 },
			{ Id = 9021582812, L0 = 3, L1 = 3, X = -30, Z = 22, Yaw = 0, Scale = 1.2 },
			{ Id = 9021582812, L0 = 3, L1 = 3, X = -26, Z = 23, Yaw = 0, Scale = 1.2 },
			{ Id = 15569446609, L0 = 2, L1 = 2, X = 26, Z = -20, Yaw = 0, Scale = 0.3 },
			{ Id = 15753397958, L0 = 2, L1 = 2, X = 10, Z = -18, Yaw = 0, Scale = 1.0 },
			{ Id = 4669786564, L0 = 3, L1 = 3, X = -5.5, Z = -6.5, Yaw = 0, Scale = 1.6 },
			{ Id = 15569446609, L0 = 3, L1 = 3, X = 30, Z = -20, Yaw = 0, Scale = 0.36 },
			{ Id = 15569446609, L0 = 3, L1 = 3, X = 30, Z = -4, Yaw = 0, Scale = 0.36 },
			{ Id = 15753397958, L0 = 3, L1 = 3, X = 28, Z = 12, Yaw = 0, Scale = 1.0 },
		},
		WestFlank = {
			{ Id = 12273282787, L0 = 1, L1 = 3, X = -18, Z = -18, Yaw = 180, Scale = 0.9 },
			{ Id = 5678434293, L0 = 1, L1 = 3, X = -18, Z = -4, Yaw = 0, Scale = 1.0 },
			{ Id = 11654379868, L0 = 1, L1 = 3, X = 14, Z = -4, Yaw = 0, Scale = 1.0 },
			{ Id = 11654379868, L0 = 1, L1 = 3, X = 24, Z = -4, Yaw = 30, Scale = 1.0 },
			{ Id = 412251367, L0 = 2, L1 = 3, X = 18, Z = -22, Yaw = 180, Scale = 1.0 },
			{ Id = 9154880131, L0 = 2, L1 = 3, X = 2, Z = -24, Yaw = 0, Scale = 1.0 },
			{ Id = 9154880131, L0 = 2, L1 = 3, X = 2, Z = -16, Yaw = 0, Scale = 1.0 },
			{ Id = 15797919882, L0 = 3, L1 = 3, X = -18, Z = 14, Yaw = 0, Scale = 0.75 },
			{ Id = 1230286742, L0 = 3, L1 = 3, X = 12, Z = 14, Yaw = 0, Scale = 1.0 },
			{ Id = 1230286742, L0 = 3, L1 = 3, X = 26, Z = 14, Yaw = 0, Scale = 1.0 },
			{ Id = 11654379868, L0 = 3, L1 = 3, X = 10, Z = 24, Yaw = 15, Scale = 1.0 },
			{ Id = 11654379868, L0 = 3, L1 = 3, X = 24, Z = 23, Yaw = 45, Scale = 1.0 },
		},
	} :: { [string]: { ZoneRow } },
	-- zones whose Part build stays (the store rows only add dressing that must clear every Part cluster)
	ZoneKeepParts = { EastYard = true } :: { [string]: boolean },
}

-- live for this player? (OwnerFirst: the owner + Studio testers only)
--[[ claude-bud JOB 40 part C (2026-09-30): two more row types (owner-first, JOB40.OwnerFirst):
	  * ReplaceRows: a store copy REPLACES a WorldKits landmark (e.g. the 6-part RadarDome at Radar Hill's Frontier
	    "Dome" slot): the copy is placed on the kit's footprint first and only THEN the kit's parts are hidden
	    (Transparency 1, no collision / query); any failed check keeps the kit. { Kit part name, At (world X / Z of the
	    slot), Radius (studs to find it), Id, Scale, Yaw }.
	  * BaseRows: per-plot military dressing for a LIVE owner (the helipad / airfield / dock areas that
	    Place.BaseClearStuds keeps every WorldRow out of): plot-local X / Z / Yaw from BaseLayoutConfig's frame, MinLevel
	    of the Anchor structure, Budget.MaxBasePartsPerPlot. Never on VehicleConfig.HelipadSpots / the runway / basin,
	    never touching another part (Place.Pad).
	Both lists stay EMPTY until the Open Cloud probe (tools/probes/job40_props_probe.luau) proves each id loads (rule:
	wire only ids the probe shows loading). The candidates are listed in Candidates + docs/PROP-ASSETS.md. Empty lists =
	OFF == OLD (the RadarDome kit and the plain helipad exactly as today). ]]
local cfg40: any = StorePropsConfig
cfg40.JOB40 = { Enabled = true, OwnerFirst = true }
cfg40.ReplaceRows = {
	-- after the probe, e.g.: { KitPart = "RadarDome", At = Vector3.new(-1053.5, 0, -1009.8), Radius = 20, Id = <radar station id>, Scale = 1, Yaw = 0 },
} :: { any }
cfg40.BaseRows = {
	-- after the probe, e.g.: { Id = <ops building id>, Anchor = "Helipad", MinLevel = 1, X = 58, Z = -110, Yaw = 180, Scale = 1 },
} :: { any }
cfg40.Budget.MaxBasePartsPerPlot = 600
cfg40.BaseKeepOut = { -- plot-local boxes no BaseRow may touch (centre X / Z, half sizes): helipad spots, runway, basin
	{ X = 40, Z = -125, HX = 18, HZ = 18 }, -- the helipad pad (HelipadSpots inside)
	{ X = -63, Z = -80, HX = 97, HZ = 16 }, -- the runway
	{ X = 128, Z = -112, HX = 27, HZ = 37 }, -- the dock basin
	{ X = 40, Z = -86, HX = 8, HZ = 26 }, -- the HeliApron lane
}
-- JOB 40 candidates (Creator Store search 2026-09-30), PENDING the probe; rejected up front: SN-75 radar (a real weapon
-- system), the Phoenix Sky Harbor / Orly control towers (real places)
cfg40.Candidates = {
	{ Id = 856258654, Name = "Radar Station", Use = "Radar Hill ReplaceRow" },
	{ Id = 91764409, Name = "Radar Station", Use = "Radar Hill ReplaceRow" },
	{ Id = 124247102466690, Name = "Radar Station Military Dish Satellite", Use = "Radar Hill ReplaceRow" },
	{ Id = 110033425601385, Name = "Military Satellite Dish Radar Station", Use = "Radar Hill / North Ridge" },
	{ Id = 37473580, Name = "Pre-War Radar/Radio Station", Use = "Radar Hill" },
	{ Id = 12972439539, Name = "ATC tower", Use = "base helipad BaseRow" },
	{ Id = 10140810871, Name = "ATC Tower", Use = "base helipad BaseRow" },
	{ Id = 10480494876, Name = "ATC Tower", Use = "base airfield BaseRow" },
	{ Id = 1660469777, Name = "Military Cargo HQ", Use = "base airfield BaseRow" },
	{ Id = 5437548774, Name = "Radio Command", Use = "capture sites" },
	{ Id = 9230948087, Name = "Sandbag Bunker", Use = "base guard post / capture sites" },
	{ Id = 12735882090, Name = "Sandbags Bunker", Use = "capture sites" },
	{ Id = 11921729320, Name = "Sandbag Bunker small", Use = "base BaseRow" },
	{ Id = 11921736228, Name = "Sandbag Bunker medium", Use = "base BaseRow" },
	{ Id = 8887518461, Name = "Firebase Sandbag Bunker", Use = "capture sites" },
	{ Id = 86311252190175, Name = "Market stall", Use = "Crossroads Town" },
	{ Id = 388036950, Name = "Market Stand", Use = "Crossroads Town" },
	{ Id = 2033520495, Name = "Stall V2", Use = "Crossroads Town" },
	{ Id = 740042082, Name = "Market", Use = "Crossroads Town" },
}

function cfg40.JOB40LiveFor(userId: any): boolean
	local b = cfg40.JOB40
	if b.Enabled ~= true then
		return false
	end
	if b.OwnerFirst ~= true then
		return true
	end
	local okR, RS = pcall(function(): any
		return game:GetService("RunService")
	end)
	if okR and RS and RS:IsStudio() then
		return true
	end
	return (require(script.Parent.AdminConfig) :: any).IsPlaytestOwner(userId)
end

function StorePropsConfig.LiveFor(userId: any): boolean
	if StorePropsConfig.Enabled ~= true then
		return false
	end
	if StorePropsConfig.OwnerFirst ~= true then
		return true
	end
	local uid = tonumber(userId)
	if uid == nil then
		return false
	end
	if uid <= 0 and game:GetService("RunService"):IsStudio() then
		return true -- Studio test players
	end
	return (require(script.Parent.AdminConfig) :: any).IsPlaytestOwner(uid)
end

-- every asset id some row uses (sorted; the zone ids first: the zones swap in as soon as a plot is ready)
function StorePropsConfig.NeededIds(): ({ number }, { number })
	local zs, ws, seen = {}, {}, {}
	for _, rows in pairs(StorePropsConfig.ZoneRows) do
		for _, r in ipairs(rows) do
			if not seen[r.Id] then
				seen[r.Id] = true
				table.insert(zs, r.Id)
			end
		end
	end
	for _, r in ipairs(StorePropsConfig.WorldRows) do
		if not seen[r.Id] then
			seen[r.Id] = true
			table.insert(ws, r.Id)
		end
	end
	table.sort(zs)
	return zs, ws
end

return StorePropsConfig
