--!strict
--[[
	WAR EMPIRE W3 step 2 — POI layout rows, group "Wilds": Ruins, Crash, Oasis, Quarry, RidgeCamp, DuneCamp.

	Lane D3, from the geometry plan's drafts (scratchpad w3s2/geo, layouts.py) with the merged spec's renames (§1.5) and
	the L0 contract's edits (§4). Keyed by POI Id; WorldPOI (lane P) reads a row for every ENABLED WorldConfig.POIs row
	whose Layout = "Wilds". The three camps (Quarry, RidgeCamp, DuneCamp) switch on in enable step 1 with the Industry
	places; Ruins, Crash and Oasis in enable step 3. Budgets, Reserve, lights, signs and LowShare live in that WorldConfig
	row, not here. Data only: it requires nothing but WorldConfig (for the row types) and never yields.

	Rows (WorldConfig.POILayout):
	  • Clusters — the Town row format (TownCluster / KitPlace), world studs. Yaw 0 = the cluster front faces north (-Z),
	    90 = west (-X), -90 = east (+X), 180 = south (+Z); kits are local to the cluster frame. Tier 1 = built in Quality
	    Low and Full, Tier 2 = Full only.
	  • Rocks — Terrain rubble (0 parts).
	  • Anchors — activity anchors (invisible tagged Attachments, 0 parts) in WORLD studs, ids "<POI>.<Site>.<Role>".
	    They are stamped on the POI's one ActivityHost part (the "Host" cluster; it never moves). Y is the standing surface
	    above the desert floor (14 = a watchtower deck). Requires = a cluster Id here: the anchor exists only when that
	    cluster was built (the camp watchtowers are Tier 2, so their deck posts are absent at Quality Low). Every anchor
	    is at least WorldConfig.Activity.MinClear from every collidable part (checked on the real kit builds).
	  • PoiBoard kits leave Text nil: WorldPOI paints Board (within the POI's Signs and Budgets.SurfaceGuis). The camps
	    have no board (Signs 0).

	Jobs here (spec §1.7; Phase B OpsService reads the anchors, nothing reads them yet):
	  Ruins    — holdout: hold the village square (Holdout.Ring, R 30) against the posts; plus Caches: one of 3 search
	             spots, each inside a burnt-out shell, is loaded per cycle.
	  Crash    — black box: recover the flight recorder at the cockpit (BlackBox.Recorder), then carry it home.
	  Oasis    — stash: search the smuggler's stash (Stash.Box). The well (Well.Pad, a heal pad) is reserved.
	  Camps    — raid the camp: the legacy posts on the old NPC spawn spots (Quarry G1..G4, Ridge / Dune G1..G3), the
	             watchtower deck post (Full only), and the commander (Camp.Cmdr, within 25 studs of the chest); then open
	             the chest (Camp.Chest, on its painted HoldPad).
	Prompt = "hold" marks where a job puts a hold prompt (start, grab, search, open), as in Town.BankAnchors and the
	Industry / Frontier groups; stand-in zones (the holdout ring, the heal pad) have none.
	Posts face what they defend: a camp post looks over its sandbag line (the line's Yaw), a holdout post at the ring, a
	commander toward the roads he is attacked from (the map centre), a deck post over the tower's front wall.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldConfig = require(ReplicatedStorage.Shared.Configs.WorldConfig)

local Layouts: { [string]: WorldConfig.POILayout } = {
	-- ═══ RUINED VILLAGE (Village Square event spot; holdout + caches) ═══════════════════════════════════════════════
	Ruins = {
		Board = "RUINED VILLAGE",
		Clusters = {
			{ Id = "R_1", Block = "Ring", Role = "block", Tier = 1, X = -590.1, Z = -1359.8, Yaw = -140, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "gutted", Width = 22, Depth = 16, Storeys = 2 } } },
			{ Id = "R_2", Block = "Ring", Role = "block", Tier = 1, X = -528.9, Z = -1379.2, Yaw = 172, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "damaged", Width = 24, Depth = 18, Storeys = 3, Roof = "tank" } } },
			{ Id = "R_3", Block = "Ring", Role = "block", Tier = 2, X = -481.7, Z = -1345.6, Yaw = 128, Kits = { { Kit = "RuinedHouse", X = 0, Z = 0 } } },
			{ Id = "R_4", Block = "Ring", Role = "block", Tier = 1, X = -457.3, Z = -1285.4, Yaw = 80, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "gutted", Width = 26, Depth = 18, Storeys = 3 } } },
			{ Id = "R_5", Block = "Ring", Role = "block", Tier = 2, X = -497.5, Z = -1237, Yaw = 34, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "damaged", Width = 20, Depth = 16, Storeys = 2 } } },
			{ Id = "R_6", Block = "Ring", Role = "block", Tier = 1, X = -562.1, Z = -1223.1, Yaw = -16, Kits = { { Kit = "RuinedHouse", X = 0, Z = 0 } } },
			{ Id = "R_7", Block = "Ring", Role = "block", Tier = 1, X = -610.1, Z = -1265.8, Yaw = -64, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "gutted", Width = 20, Depth = 14, Storeys = 2 } } },
			{ Id = "R_8", Block = "Ring", Role = "block", Tier = 2, X = -623.4, Z = -1333.7, Yaw = -112, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "side", Width = 22, Depth = 18, Storeys = 3, Roof = "hut" } } },
			{ Id = "R_9", Block = "Ring", Role = "block", Tier = 2, X = -476, Z = -1189.1, Yaw = 30, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "gutted", Width = 18, Depth = 14, Storeys = 2 } } },
			{ Id = "R_10", Block = "Ring", Role = "block", Tier = 2, X = -664, Z = -1254.9, Yaw = -70, Kits = { { Kit = "RuinedHouse", X = 0, Z = 0 } } },
			{ Id = "WaterTower", Block = "Ring", Role = "landmark", Tier = 1, X = -496.2, Z = -1420.3, Yaw = 160, Kits = { { Kit = "WaterTower", X = 0, Z = 0, Variant = "broken" } } },
			{ Id = "Car_1", Block = "Square", Role = "wreck", Tier = 1, X = -501.9, Z = -1278, Yaw = 30, Kits = { { Kit = "Wreck", X = 0, Z = 0, Variant = "car" } } },
			{ Id = "Car_2", Block = "Square", Role = "wreck", Tier = 2, X = -569.6, Z = -1335.2, Yaw = -60, Kits = { { Kit = "Wreck", X = 0, Z = 0, Variant = "car" } } },
			{ Id = "Well", Block = "Square", Role = "well", Tier = 1, X = -540, Z = -1262, Yaw = 0, Kits = { { Kit = "Fountain", X = 0, Z = 0, Variant = "well" } } },
			{ Id = "WallN", Block = "Edge", Role = "wall", Tier = 2, X = -600, Z = -1420, Yaw = 20, Kits = { { Kit = "CompoundWall", X = 0, Z = 0, Length = 32 } } },
			{ Id = "WallE", Block = "Edge", Role = "wall", Tier = 2, X = -420, Z = -1360, Yaw = -70, Kits = { { Kit = "CompoundWall", X = 0, Z = 0, Length = 32 } } },
			{ Id = "WallS", Block = "Edge", Role = "wall", Tier = 1, X = -520, Z = -1195, Yaw = 170, Kits = { { Kit = "CompoundWall", X = 0, Z = 0, Length = 32 } } },
			{ Id = "Board", Block = "Edge", Role = "board", Tier = 1, X = -712, Z = -1318, Yaw = 90, Kits = { { Kit = "PoiBoard", X = 0, Z = 0 } } },
			{ Id = "Host", Block = "Host", Role = "anchor", Tier = 1, X = -560, Z = -1180, Yaw = 0, Kits = { { Kit = "ActivityHost", X = 0, Z = 0 } } },
		},
		Rocks = {
			{ Kind = "rubble", X = -604.3, Z = -1376.6, Radius = 6, Tier = 1 },
			{ Kind = "rubble", X = -437.6, Z = -1281.9, Radius = 6, Tier = 1 },
			{ Kind = "rubble", X = -628.1, Z = -1257, Radius = 6, Tier = 1 },
			{ Kind = "rubble", X = -483.6, Z = -1320.5, Radius = 6, Tier = 1 },
			{ Kind = "rubble", X = -561.2, Z = -1241.7, Radius = 6, Tier = 1 },
			{ Kind = "rubble", X = -595, Z = -1395.3, Radius = 6, Tier = 2 },
			{ Kind = "rubble", X = -566, Z = -1152.3, Radius = 6, Tier = 2 },
			{ Kind = "scorch", X = -520, Z = -1330, Radius = 8, Tier = 1 },
		},
		Anchors = {
			{ Id = "Ruins.Holdout.Ring", Kind = "hold", X = -540, Z = -1300, Yaw = 0, R = 30 }, -- hold the village square (the VillageSquare event spot)
			{ Id = "Ruins.Holdout.G1", Kind = "npc", X = -529, Z = -1364.5, Yaw = 170 }, -- the square side of R_2, facing the ring
			{ Id = "Ruins.Holdout.G2", Kind = "npc", X = -500, Z = -1285, Yaw = 69 }, -- beside Car_1, facing the ring
			{ Id = "Ruins.Holdout.G3", Kind = "npc", X = -578, Z = -1343, Yaw = -139 }, -- the square side of R_1, facing the ring
			{ Id = "Ruins.Caches.Cache1", Kind = "search", X = -596.17, Z = -1355.36, Yaw = 0, R = 5, Prompt = "hold" }, -- inside gutted R_1
			{ Id = "Ruins.Caches.Cache2", Kind = "search", X = -455.24, Z = -1294.18, Yaw = 0, R = 5, Prompt = "hold" }, -- inside gutted R_4
			{ Id = "Ruins.Caches.Cache3", Kind = "search", X = -607.48, Z = -1259.29, Yaw = 0, R = 5, Prompt = "hold" }, -- inside gutted R_7
		},
	},
	-- ═══ CRASH SITE (Salvage event spot; the black box) ═════════════════════════════════════════════════════════════
	Crash = {
		Board = "CRASH SITE",
		Clusters = {
			{ Id = "Plane_Nose", Block = "Wreck", Role = "landmark", Tier = 1, X = -605, Z = 1182, Yaw = -55, Kits = { { Kit = "PlaneWreck", X = 0, Z = 0, Variant = "nose" } } },
			{ Id = "Plane_Mid", Block = "Wreck", Role = "landmark", Tier = 1, X = -560, Z = 1150, Yaw = -55, Kits = { { Kit = "PlaneWreck", X = 0, Z = 0, Variant = "mid" } } },
			{ Id = "Plane_Tail", Block = "Wreck", Role = "landmark", Tier = 1, X = -500, Z = 1112, Yaw = -40, Kits = { { Kit = "PlaneWreck", X = 0, Z = 0, Variant = "tail" } } },
			{ Id = "Cargo_1", Block = "Wreck", Role = "crates", Tier = 1, X = -470, Z = 1150, Yaw = 20, Kits = { { Kit = "CrateStack", X = 0, Z = 0, Count = 3 }, { Kit = "CrateStack", X = 9, Z = 4, Count = 2 } } },
			{ Id = "Cargo_2", Block = "Wreck", Role = "crates", Tier = 1, X = -585, Z = 1080, Yaw = -30, Kits = { { Kit = "CrateStack", X = 0, Z = 0, Count = 3 }, { Kit = "DrumGroup", X = 8, Z = 2, Count = 2 } } },
			{ Id = "Cargo_3", Block = "Wreck", Role = "crates", Tier = 2, X = -640, Z = 1215, Yaw = 60, Kits = { { Kit = "CrateStack", X = 0, Z = 0, Count = 2 } } },
			{ Id = "Engine", Block = "Wreck", Role = "wreck", Tier = 2, X = -455, Z = 1095, Yaw = 10, Kits = { { Kit = "Wreck", X = 0, Z = 0, Variant = "car" } } },
			{ Id = "Recovery", Block = "Wreck", Role = "vehicle", Tier = 2, X = -470, Z = 1215, Yaw = -100, Kits = { { Kit = "Wreck", X = 0, Z = 0, Variant = "truck" }, { Kit = "Jersey", X = 0, Z = -8 } } },
			{ Id = "Bags", Block = "Wreck", Role = "cover", Tier = 1, X = -612, Z = 1128, Yaw = 60, Kits = { { Kit = "SandbagArc", X = 0, Z = 0 }, { Kit = "SandbagArc", X = 8, Z = 0 } } },
			{ Id = "Board", Block = "Edge", Role = "board", Tier = 1, X = -695, Z = 1128, Yaw = 90, Kits = { { Kit = "PoiBoard", X = 0, Z = 0 } } },
			{ Id = "Host", Block = "Host", Role = "anchor", Tier = 1, X = -540, Z = 1250, Yaw = 0, Kits = { { Kit = "ActivityHost", X = 0, Z = 0 } } },
		},
		Rocks = {
			{ Kind = "scorch", X = -525, Z = 1128, Radius = 9, Tier = 1 },
			{ Kind = "scorch", X = -470, Z = 1090, Radius = 9, Tier = 1 },
			{ Kind = "scorch", X = -420, Z = 1060, Radius = 8, Tier = 2 },
			{ Kind = "rubble", X = -640, Z = 1160, Radius = 6, Tier = 2 },
		},
		Anchors = {
			{ Id = "Crash.BlackBox.Recorder", Kind = "hold", X = -598, Z = 1168, Yaw = -55, R = 6, Prompt = "hold" }, -- the cockpit: recover the flight recorder, then carry it home
			{ Id = "Crash.BlackBox.G1", Kind = "npc", X = -612, Z = 1134, Yaw = 60 }, -- behind the Bags sandbag arcs
			{ Id = "Crash.BlackBox.G2", Kind = "npc", X = -467, Z = 1158.5, Yaw = 20 }, -- behind Cargo_1 (its crates between him and the north)
			{ Id = "Crash.BlackBox.G3", Kind = "npc", X = -585, Z = 1088, Yaw = -30 }, -- behind Cargo_2
			{ Id = "Crash.Salvage.Arena", Kind = "arena", X = -520, Z = 1080, Yaw = 0 }, -- the existing Salvage event spot
		},
	},
	-- ═══ OASIS (pond, palms, huts; the smuggler's stash; the well is reserved) ═══════════════════════════════════════
	Oasis = {
		Board = "OASIS",
		Clusters = {
			{ Id = "Pond", Block = "Pond", Role = "pond", Tier = 1, X = -1300, Z = 560, Yaw = 0, Kits = { { Kit = "HoldPad", X = 0, Z = 0, Variant = "pond", R = 22 } } },
			{ Id = "Reeds_1", Block = "Pond", Role = "reeds", Tier = 2, X = -1286.5, Z = 536.6, Yaw = 0, Kits = { { Kit = "Reeds", X = 0, Z = 0 }, { Kit = "Reeds", X = 3, Z = 2, Scale = 0.8 } } },
			{ Id = "Reeds_2", Block = "Pond", Role = "reeds", Tier = 2, X = -1286.5, Z = 583.4, Yaw = 120, Kits = { { Kit = "Reeds", X = 0, Z = 0 }, { Kit = "Reeds", X = 3, Z = 2, Scale = 0.8 } } },
			{ Id = "Reeds_3", Block = "Pond", Role = "reeds", Tier = 2, X = -1327, Z = 560, Yaw = 240, Kits = { { Kit = "Reeds", X = 0, Z = 0 }, { Kit = "Reeds", X = 3, Z = 2, Scale = 0.8 } } },
			{ Id = "Palm_1", Block = "Grove", Role = "palm", Tier = 1, X = -1286.3, Z = 522.4, Yaw = -146, Kits = { { Kit = "Palm", X = 0, Z = 0, Scale = 0.9 } } },
			{ Id = "Palm_2", Block = "Grove", Role = "palm", Tier = 1, X = -1257.5, Z = 548.6, Yaw = -52.5, Kits = { { Kit = "Palm", X = 0, Z = 0, Scale = 0.95 } } },
			{ Id = "Palm_3", Block = "Grove", Role = "palm", Tier = 1, X = -1275.6, Z = 589.1, Yaw = 58, Kits = { { Kit = "Palm", X = 0, Z = 0, Scale = 1 } } },
			{ Id = "Palm_4", Block = "Grove", Role = "palm", Tier = 2, X = -1315.7, Z = 603.2, Yaw = 160, Kits = { { Kit = "Palm", X = 0, Z = 0, Scale = 1.05 } } },
			{ Id = "Palm_5", Block = "Grove", Role = "palm", Tier = 2, X = -1338.6, Z = 570.4, Yaw = -106.5, Kits = { { Kit = "Palm", X = 0, Z = 0, Scale = 0.9 } } },
			{ Id = "Palm_6", Block = "Grove", Role = "palm", Tier = 2, X = -1336.8, Z = 529.1, Yaw = -13, Kits = { { Kit = "Palm", X = 0, Z = 0, Scale = 0.95 } } },
			{ Id = "Palm_7", Block = "Grove", Role = "palm", Tier = 2, X = -1357.3, Z = 600.2, Yaw = -140.5, Kits = { { Kit = "Palm", X = 0, Z = 0, Scale = 1 } } },
			{ Id = "Hut_1", Block = "Huts", Role = "block", Tier = 1, X = -1370, Z = 490, Yaw = 45, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Width = 14, Depth = 10, Storeys = 1, Lantern = true } } },
			{ Id = "Hut_2", Block = "Huts", Role = "block", Tier = 1, X = -1225, Z = 622, Yaw = -135, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "damaged", Width = 16, Depth = 10, Storeys = 2, Lantern = true } } },
			{ Id = "Well", Block = "Huts", Role = "well", Tier = 1, X = -1248, Z = 505, Yaw = -45, Kits = { { Kit = "Fountain", X = 0, Z = 0, Variant = "well" } } },
			{ Id = "Stash", Block = "Huts", Role = "loot", Tier = 1, X = -1385, Z = 610, Yaw = 120, Kits = { { Kit = "CrateStack", X = 0, Z = 0, Count = 2 }, { Kit = "DrumGroup", X = 5, Z = 1, Count = 2 } } },
			{ Id = "Board", Block = "Edge", Role = "board", Tier = 1, X = -1192, Z = 575, Yaw = -90, Kits = { { Kit = "PoiBoard", X = 0, Z = 0 } } },
			{ Id = "Host", Block = "Host", Role = "anchor", Tier = 1, X = -1300, Z = 660, Yaw = 0, Kits = { { Kit = "ActivityHost", X = 0, Z = 0 } } },
		},
		Rocks = {
			{ Kind = "boulders", X = -1340, Z = 640, Radius = 8, Tier = 1 },
			{ Kind = "outcrop", X = -1222, Z = 488, Radius = 10, Tier = 2 },
		},
		Anchors = {
			{ Id = "Oasis.Stash.Box", Kind = "search", X = -1381.42, Z = 606.2, Yaw = 120, R = 5, Prompt = "hold" }, -- at the stash crates' back (2.3 clear), facing them; the smuggler's stash (daily)
			{ Id = "Oasis.Well.Pad", Kind = "hold", X = -1248, Z = 509.5, Yaw = 0, R = 6 }, -- beside the well, facing it (2 clear; the well inside the ring): stand 4 s to heal (reserved)
		},
	},
	-- ═══ QUARRY CAMP (the crusher; camp raid) ═══════════════════════════════════════════════════════════════════════
	Quarry = {
		Clusters = {
			{ Id = "Crusher", Block = "Pit", Role = "landmark", Tier = 1, X = -1352, Z = -1428, Yaw = -35, Kits = { { Kit = "Crusher", X = 0, Z = 0 } } },
			{ Id = "Dump_1", Block = "Pit", Role = "wreck", Tier = 1, X = -1302, Z = -1395, Yaw = 20, Kits = { { Kit = "Wreck", X = 0, Z = 0, Variant = "truck" } } },
			{ Id = "Dump_2", Block = "Pit", Role = "wreck", Tier = 2, X = -1440, Z = -1470, Yaw = -70, Kits = { { Kit = "Wreck", X = 0, Z = 0, Variant = "truck" } } },
			{ Id = "Tents", Block = "Camp", Role = "tents", Tier = 1, X = -1418, Z = -1330, Yaw = 20, Kits = { { Kit = "Tent", X = -8, Z = 0 }, { Kit = "Tent", X = 8, Z = 0 } } },
			{ Id = "Tent3", Block = "Camp", Role = "tents", Tier = 2, X = -1356, Z = -1318, Yaw = -10, Kits = { { Kit = "Tent", X = 0, Z = 0 } } },
			{ Id = "Fire", Block = "Camp", Role = "fire", Tier = 1, X = -1395, Z = -1360, Yaw = 0, Kits = { { Kit = "DrumGroup", X = 0, Z = 0, Variant = "fire", Count = 1 } } },
			{ Id = "Chest", Block = "Camp", Role = "loot", Tier = 1, X = -1380, Z = -1352, Yaw = 0, Kits = { { Kit = "CrateStack", X = 0, Z = 0, Variant = "ammo", Count = 3 }, { Kit = "HoldPad", X = 0, Z = -6, R = 6 } } },
			{ Id = "Bags_1", Block = "Camp", Role = "cover", Tier = 1, X = -1473.2, Z = -1298.1, Yaw = 120, Kits = { { Kit = "SandbagLine", X = 0, Z = 0, Length = 10 } } },
			{ Id = "Bags_2", Block = "Camp", Role = "cover", Tier = 1, X = -1318.4, Z = -1483.4, Yaw = -25.1, Kits = { { Kit = "SandbagLine", X = 0, Z = 0, Length = 10 } } },
			{ Id = "Bags_3", Block = "Camp", Role = "cover", Tier = 1, X = -1256.4, Z = -1329.3, Yaw = -100.4, Kits = { { Kit = "SandbagLine", X = 0, Z = 0, Length = 10 } } },
			{ Id = "Bags_4", Block = "Camp", Role = "cover", Tier = 1, X = -1442.4, Z = -1422.8, Yaw = 41.4, Kits = { { Kit = "SandbagLine", X = 0, Z = 0, Length = 10 } } },
			{ Id = "Watch", Block = "Camp", Role = "tower", Tier = 2, X = -1300, Z = -1290, Yaw = -135, Kits = { { Kit = "Watchtower", X = 0, Z = 0 } } },
			{ Id = "Shed", Block = "Pit", Role = "block", Tier = 2, X = -1470, Z = -1400, Yaw = 90, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "roller+metal", Width = 20, Depth = 14, Storeys = 1 } } },
			{ Id = "Host", Block = "Host", Role = "anchor", Tier = 1, X = -1380, Z = -1250, Yaw = 0, Kits = { { Kit = "ActivityHost", X = 0, Z = 0 } } },
		},
		Rocks = {
			{ Kind = "outcrop", X = -1500, Z = -1360, Radius = 12, Tier = 1 },
			{ Kind = "outcrop", X = -1290, Z = -1470, Radius = 12, Tier = 1 },
			{ Kind = "boulders", X = -1400, Z = -1500, Radius = 10, Tier = 1 },
			{ Kind = "rubble", X = -1330, Z = -1440, Radius = 8, Tier = 2 },
			{ Kind = "outcrop", X = -1510, Z = -1440, Radius = 12, Tier = 2 },
			{ Kind = "outcrop", X = -1250, Z = -1420, Radius = 12, Tier = 2 },
		},
		Anchors = {
			{ Id = "Quarry.Camp.Chest", Kind = "hold", X = -1380, Z = -1358, Yaw = 0, R = 6, Prompt = "hold" }, -- the chest's HoldPad: opens when the squad is down
			{ Id = "Quarry.Camp.Cmdr", Kind = "npc", X = -1388, Z = -1366, Yaw = -135 }, -- the commander: 11 NW of the chest, the side away from the roads, facing them
			{ Id = "Quarry.Camp.G1", Kind = "npc", X = -1470, Z = -1300, Yaw = 120 }, -- the legacy NPC spot Quarry_1, behind Bags_1, facing over it
			{ Id = "Quarry.Camp.G2", Kind = "npc", X = -1320, Z = -1480, Yaw = -25.1 }, -- Quarry_2, behind Bags_2
			{ Id = "Quarry.Camp.G3", Kind = "npc", X = -1260, Z = -1330, Yaw = -100.4 }, -- Quarry_3, behind Bags_3
			{ Id = "Quarry.Camp.G4", Kind = "npc", X = -1440, Z = -1420, Yaw = 41.4 }, -- Quarry_4, behind Bags_4
			{ Id = "Quarry.Camp.G5", Kind = "npc", X = -1300, Z = -1290, Yaw = -135, Y = 14, Requires = "Watch" }, -- the watchtower deck (Full only)
		},
	},
	-- ═══ RIDGE CAMP (the technical; camp raid) ══════════════════════════════════════════════════════════════════════
	RidgeCamp = {
		Clusters = {
			{ Id = "Technical", Block = "Camp", Role = "landmark", Tier = 1, X = 1410, Z = -1060, Yaw = 30, Kits = { { Kit = "Wreck", X = 0, Z = 0, Variant = "truck" } } },
			{ Id = "TechNest", Block = "Camp", Role = "nest", Tier = 2, X = 1414, Z = -1053.1, Yaw = 30, Kits = { { Kit = "SandbagNest", X = 0, Z = 0 } } },
			{ Id = "Watch", Block = "Camp", Role = "tower", Tier = 2, X = 1420, Z = -985, Yaw = 180, Kits = { { Kit = "Watchtower", X = 0, Z = 0 } } },
			{ Id = "Tents", Block = "Camp", Role = "tents", Tier = 1, X = 1470, Z = -1070, Yaw = -80, Kits = { { Kit = "Tent", X = -8, Z = 0 }, { Kit = "Tent", X = 8, Z = 0 } } },
			{ Id = "Fire", Block = "Camp", Role = "fire", Tier = 1, X = 1440, Z = -1050, Yaw = 0, Kits = { { Kit = "DrumGroup", X = 0, Z = 0, Variant = "fire", Count = 1 } } },
			{ Id = "Chest", Block = "Camp", Role = "loot", Tier = 1, X = 1428, Z = -1035, Yaw = 0, Kits = { { Kit = "CrateStack", X = 0, Z = 0, Variant = "ammo", Count = 3 }, { Kit = "HoldPad", X = 0, Z = -6, R = 6 } } },
			{ Id = "Bags_1", Block = "Camp", Role = "cover", Tier = 1, X = 1357.3, Z = -1102.6, Yaw = 46.3, Kits = { { Kit = "SandbagLine", X = 0, Z = 0, Length = 10 } } },
			{ Id = "Bags_2", Block = "Camp", Role = "cover", Tier = 1, X = 1483.3, Z = -1008.4, Yaw = -115.7, Kits = { { Kit = "SandbagLine", X = 0, Z = 0, Length = 10 } } },
			{ Id = "Bags_3", Block = "Camp", Role = "cover", Tier = 1, X = 1450.9, Z = -1123.6, Yaw = -14.5, Kits = { { Kit = "SandbagLine", X = 0, Z = 0, Length = 10 } } },
			{ Id = "Host", Block = "Host", Role = "anchor", Tier = 1, X = 1360, Z = -1010, Yaw = 0, Kits = { { Kit = "ActivityHost", X = 0, Z = 0 } } },
		},
		Rocks = {
			{ Kind = "outcrop", X = 1340, Z = -1040, Radius = 12, Tier = 1 },
			{ Kind = "boulders", X = 1510, Z = -1090, Radius = 10, Tier = 1 },
			{ Kind = "outcrop", X = 1395, Z = -960, Radius = 12, Tier = 2 },
			{ Kind = "rubble", X = 1500, Z = -1060, Radius = 8, Tier = 2 },
		},
		Anchors = {
			{ Id = "RidgeCamp.Camp.Chest", Kind = "hold", X = 1428, Z = -1041, Yaw = 0, R = 6, Prompt = "hold" }, -- the chest's HoldPad
			{ Id = "RidgeCamp.Camp.Cmdr", Kind = "npc", X = 1434, Z = -1052, Yaw = 135 }, -- the commander: 12.5 NNE of the chest, the side away from the roads, facing them
			{ Id = "RidgeCamp.Camp.G1", Kind = "npc", X = 1360, Z = -1100, Yaw = 46.3 }, -- the legacy NPC spot Ridge_1, behind Bags_1, facing over it
			{ Id = "RidgeCamp.Camp.G2", Kind = "npc", X = 1480, Z = -1010, Yaw = -115.7 }, -- Ridge_2, behind Bags_2
			{ Id = "RidgeCamp.Camp.G3", Kind = "npc", X = 1450, Z = -1120, Yaw = -14.5 }, -- Ridge_3, behind Bags_3
			{ Id = "RidgeCamp.Camp.G4", Kind = "npc", X = 1420, Z = -985, Yaw = 180, Y = 14, Requires = "Watch" }, -- the watchtower deck (Full only)
		},
	},
	-- ═══ DUNE CAMP (the downed helicopter; camp raid) ═══════════════════════════════════════════════════════════════
	DuneCamp = {
		Clusters = {
			{ Id = "Heli", Block = "Camp", Role = "landmark", Tier = 1, X = 1452, Z = 1212, Yaw = 35, Kits = { { Kit = "HeliWreck", X = 0, Z = 0 } } },
			{ Id = "Tents", Block = "Camp", Role = "tents", Tier = 1, X = 1400, Z = 1235, Yaw = 10, Kits = { { Kit = "Tent", X = -8, Z = 0 }, { Kit = "Tent", X = 8, Z = 0 } } },
			{ Id = "Fire", Block = "Camp", Role = "fire", Tier = 1, X = 1428, Z = 1250, Yaw = 0, Kits = { { Kit = "DrumGroup", X = 0, Z = 0, Variant = "fire", Count = 1 } } },
			{ Id = "Chest", Block = "Camp", Role = "loot", Tier = 1, X = 1480, Z = 1180, Yaw = 0, Kits = { { Kit = "CrateStack", X = 0, Z = 0, Variant = "ammo", Count = 3 }, { Kit = "HoldPad", X = 0, Z = -6, R = 6 } } },
			{ Id = "Bags_1", Block = "Camp", Role = "cover", Tier = 1, X = 1396.5, Z = 1148.7, Yaw = 69.4, Kits = { { Kit = "SandbagLine", X = 0, Z = 0, Length = 10 } } },
			{ Id = "Bags_2", Block = "Camp", Role = "cover", Tier = 1, X = 1522.1, Z = 1243.1, Yaw = -146.3, Kits = { { Kit = "SandbagLine", X = 0, Z = 0, Length = 10 } } },
			{ Id = "Bags_3", Block = "Camp", Role = "cover", Tier = 1, X = 1469.7, Z = 1303.7, Yaw = 175.2, Kits = { { Kit = "SandbagLine", X = 0, Z = 0, Length = 10 } } },
			{ Id = "Watch", Block = "Camp", Role = "tower", Tier = 2, X = 1535, Z = 1165, Yaw = -90, Kits = { { Kit = "Watchtower", X = 0, Z = 0 } } },
			{ Id = "Host", Block = "Host", Role = "anchor", Tier = 1, X = 1380, Z = 1300, Yaw = 0, Kits = { { Kit = "ActivityHost", X = 0, Z = 0 } } },
		},
		Rocks = {
			{ Kind = "outcrop", X = 1540, Z = 1300, Radius = 12, Tier = 1 },
			{ Kind = "boulders", X = 1370, Z = 1120, Radius = 10, Tier = 1 },
			{ Kind = "outcrop", X = 1360, Z = 1270, Radius = 12, Tier = 2 },
			{ Kind = "boulders", X = 1560, Z = 1210, Radius = 10, Tier = 2 },
		},
		Anchors = {
			{ Id = "DuneCamp.Camp.Chest", Kind = "hold", X = 1480, Z = 1174, Yaw = 0, R = 6, Prompt = "hold" }, -- the chest's HoldPad
			{ Id = "DuneCamp.Camp.Cmdr", Kind = "npc", X = 1484, Z = 1188, Yaw = 45 }, -- the commander: behind the ammo crates (14.6 S of the chest ring's centre), facing the roads
			{ Id = "DuneCamp.Camp.G1", Kind = "npc", X = 1400, Z = 1150, Yaw = 69.4 }, -- the legacy NPC spot Dune_1, behind Bags_1, facing over it
			{ Id = "DuneCamp.Camp.G2", Kind = "npc", X = 1520, Z = 1240, Yaw = -146.3 }, -- Dune_2, behind Bags_2
			{ Id = "DuneCamp.Camp.G3", Kind = "npc", X = 1470, Z = 1300, Yaw = 175.2 }, -- Dune_3, behind Bags_3
			{ Id = "DuneCamp.Camp.G4", Kind = "npc", X = 1535, Z = 1165, Yaw = -90, Y = 14, Requires = "Watch" }, -- the watchtower deck (Full only)
		},
	},
}

return Layouts
