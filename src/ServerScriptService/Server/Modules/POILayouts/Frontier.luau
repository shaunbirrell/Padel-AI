--!strict
--[[
	WAR EMPIRE W3 step 2 — POI layout rows, group "Frontier": Airstrip, Signal, Radar, FortI, FortS.

	Lane D2, from the geometry plan's drafts (scratchpad w3s2/geo, layouts.py) with the merged spec's renames (§1.5) and
	the L0 contract's edits (§4). Keyed by POI Id; WorldPOI (lane P) reads a row for every ENABLED WorldConfig.POIs row
	whose Layout = "Frontier" (enable step 2). Budgets, Reserve, lights, signs and LowShare live in that WorldConfig row,
	not here. Data only: it requires nothing but WorldConfig (for the row types) and never yields.

	Rows (WorldConfig.POILayout):
	  • Clusters — the Town row format (TownCluster / KitPlace), world studs. Yaw 0 = the cluster front faces north (-Z),
	    90 = west (-X), -90 = east (+X), 180 = south (+Z); kits are local to the cluster frame. Tier 1 = built in Quality
	    Low and Full, Tier 2 = Full only.
	  • Rocks — Terrain rubble (0 parts). Infra — the airstrip runway (flat, no collision; POI_Airstrip.Infra).
	  • Anchors — activity anchors (invisible tagged Attachments, 0 parts) in WORLD studs, ids "<POI>.<Site>.<Role>".
	    They are stamped on the POI's one ActivityHost part (the "Host" cluster; it never moves). Every anchor here is on
	    the desert floor (Y 0) and at least WorldConfig.Activity.MinClear from every collidable part (checked on the real
	    kit builds). Yaw is the way the post / spot faces.
	  • The checkpoint anchors (Booth, Alarm, G1, G2, R1, R2) are NOT rows here: WorldPOI stamps
	    WorldConfig.Activity.CheckpointAnchors on every Checkpoint kit, ids "<POI>.<cluster Id>.<Role>". The Signal's one
	    road checkpoint is therefore the cluster "CP" (Signal.CP.*).
	  • PoiBoard kits leave Text nil: WorldPOI paints Board (within the POI's Signs and Budgets.SurfaceGuis).

	Consoles: a console anchor is where the player STANDS to use it, in front of the Terminal's screen (the kit's -Z
	side), never inside the desk. Each Terminal sits 2.5 behind its cluster pivot so the console anchor keeps the
	geometry plan's spot (the cluster pivot; the Signal relay's HoldPad centre) and stays 1.5 clear of the desk.

	Jobs here (spec §1.7; Phase B OpsService reads the anchors, nothing reads them yet):
	  Airstrip — tower uplink at Tower.Console, held against waves, 2 tower posts. The Hangar vault / loot / posts are
	             reserved (built, not a job yet).
	  Signal   — relay uplink at Relay.Console + the road checkpoint (Signal.CP.* from the template).
	  Radar    — uplink at Uplink.Console, 2 posts behind the ring sandbags.
	  FortI/S  — breach the fort: plant a charge at Breach.Gate (the 16-wide gate gap; there is no gate part), 4 posts.
	Prompt = "hold" marks where a job puts a hold prompt (start, grab, plant), as in Town.BankAnchors.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldConfig = require(ReplicatedStorage.Shared.Configs.WorldConfig)

local Layouts: { [string]: WorldConfig.POILayout } = {
	-- ═══ DESERT AIRSTRIP (Airdrop Apron arena; tower uplink; the hangar cargo heist is reserved) ══════════════════════
	Airstrip = {
		Board = "AIRSTRIP",
		Clusters = {
			{ Id = "Board", Block = "Road", Role = "board", Tier = 1, X = 772, Z = -1214, Yaw = -90, Street = true, Kits = { { Kit = "PoiBoard", X = 0, Z = 0 } } },
			-- north apron: the cargo hangar (reserved heist), a second hangar, the control tower (landmark) and its uplink desk
			{ Id = "N_Hangar1", Block = "N", Role = "heist", Tier = 1, X = 360, Z = -1332, Yaw = 180, Kits = { { Kit = "Hangar", X = 0, Z = 0, Width = 32 } } },
			{ Id = "N_Cargo", Block = "N", Role = "heist", Tier = 1, X = 360, Z = -1336, Yaw = 180, Kits = { { Kit = "CrateStack", X = -8, Z = 0, Variant = "ammo", Count = 6 }, { Kit = "HoldPad", X = 5, Z = -3, R = 7 } } },
			{ Id = "N_Hangar2", Block = "N", Role = "block", Tier = 2, X = 438, Z = -1332, Yaw = 180, Kits = { { Kit = "Hangar", X = 0, Z = 0, Width = 32 } } },
			{ Id = "N_Tower", Block = "N", Role = "landmark", Tier = 1, X = 680, Z = -1340, Yaw = 180, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "side+rear", Width = 12, Depth = 12, Storeys = 4, Roof = "mast+dish" } } },
			{ Id = "N_TowerDesk", Block = "N", Role = "heist", Tier = 1, X = 662, Z = -1318, Yaw = 180, Kits = { { Kit = "Terminal", X = 0, Z = 2.5 }, { Kit = "SandbagArc", X = 0, Z = -4 } } },
			{ Id = "N_Bowser", Block = "N", Role = "wrecks", Tier = 2, X = 560, Z = -1330, Yaw = 0, Kits = { { Kit = "Wreck", X = 0, Z = 0, Variant = "truck" }, { Kit = "FuelTank", X = 22, Z = -8, Scale = 0.8 } } },
			{ Id = "N_Bags", Block = "N", Role = "cover", Tier = 1, X = 520, Z = -1300, Yaw = 0, Kits = { { Kit = "SandbagLine", X = 0, Z = 0, Length = 15 } } },
			-- south apron: the ops block (lantern), the motor shed, cover round the Airdrop Apron arena
			{ Id = "S_Ops", Block = "S", Role = "block", Tier = 2, X = 330, Z = -1186, Yaw = 0, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "shop+side", Width = 26, Depth = 16, Storeys = 2, Roof = "tank", Lantern = true } } },
			{ Id = "S_MotorShed", Block = "S", Role = "block", Tier = 2, X = 682, Z = -1170, Yaw = 90, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "roller+metal", Width = 22, Depth = 14, Storeys = 1 } } },
			{ Id = "S_Apron1", Block = "S", Role = "cover", Tier = 1, X = 488, Z = -1188, Yaw = 90, Kits = { { Kit = "SandbagArc", X = 0, Z = 0 } } },
			{ Id = "S_Apron2", Block = "S", Role = "cover", Tier = 1, X = 552, Z = -1188, Yaw = -90, Kits = { { Kit = "SandbagArc", X = 0, Z = 0 } } },
			{ Id = "S_Apron3", Block = "S", Role = "cover", Tier = 2, X = 520, Z = -1160, Yaw = 180, Kits = { { Kit = "CrateStack", X = 0, Z = 0, Count = 3 }, { Kit = "Jersey", X = 8, Z = 1 } } },
			{ Id = "S_Lamp", Block = "S", Role = "lamp", Tier = 2, X = 440, Z = -1172, Yaw = 0, Kits = { { Kit = "StreetLamp", X = 0, Z = 0 } } },
			{ Id = "Host", Block = "Host", Role = "anchor", Tier = 1, X = 600, Z = -1170, Yaw = 0, Kits = { { Kit = "ActivityHost", X = 0, Z = 0 } } },
		},
		Rocks = {
			{ Kind = "scorch", X = 620, Z = -1280, Radius = 8, Tier = 2 },
		},
		Infra = {
			{ Id = "Runway", Kit = "Runway", X = 510, Z = -1250, Yaw = 0, Length = 500, Taxiway = { 760, 780, -1260, -1240 } },
		},
		Anchors = {
			{ Id = "Airstrip.Tower.Console", Kind = "console", X = 662, Z = -1318, Yaw = 180, R = 6, Prompt = "hold" }, -- uplink: in front of the desk, the sandbag arc at your back
			{ Id = "Airstrip.Tower.G1", Kind = "npc", X = 671, Z = -1336, Yaw = 180 }, -- beside the tower's west wall (3 clear), watching the desk
			{ Id = "Airstrip.Tower.G2", Kind = "npc", X = 689, Z = -1336, Yaw = 180 }, -- beside the tower's east wall (3 clear); both posts stay outside the console's R 6 zone
			{ Id = "Airstrip.Hangar.Vault", Kind = "hold", X = 355, Z = -1333, Yaw = 180, R = 7, Prompt = "hold" }, -- N_Cargo's HoldPad inside the open-front hangar (reserved)
			{ Id = "Airstrip.Hangar.Loot", Kind = "loot", X = 368, Z = -1334.4, Yaw = 0, Prompt = "hold" }, -- the ammo crates' open side (1.6 clear; reserved)
			{ Id = "Airstrip.Hangar.G1", Kind = "npc", X = 380, Z = -1318, Yaw = 180 }, -- east of the hangar mouth
			{ Id = "Airstrip.Hangar.G2", Kind = "npc", X = 520, Z = -1306, Yaw = 180 }, -- 6 north of N_Bags, which screen it from the runway
			{ Id = "Airstrip.Hangar.G3", Kind = "npc", X = 340, Z = -1318, Yaw = 180 }, -- west of the hangar mouth
			{ Id = "Airstrip.Apron.Arena", Kind = "arena", X = 520, Z = -1190, Yaw = 0 }, -- the existing AirdropApron event spot
		},
	},

	-- ═══ NORTH RIDGE SIGNAL STATION (NorthRidge capture; relay uplink; pass checkpoint) ═══════════════════════════════
	Signal = {
		Board = "NORTH RIDGE",
		Clusters = {
			{ Id = "CP", Block = "Road", Role = "checkpoint", Tier = 1, X = 0, Z = -1150, Yaw = 180, Street = true, Kits = { { Kit = "Checkpoint", X = 0, Z = 0 } } },
			{ Id = "Board", Block = "Road", Role = "board", Tier = 1, X = 24, Z = -1138, Yaw = 180, Street = true, Kits = { { Kit = "PoiBoard", X = 0, Z = 0 } } },
			-- west slope: the radio mast (landmark), huts, the relay uplink inside its sandbag horseshoe, a tower
			{ Id = "W_Mast", Block = "W", Role = "landmark", Tier = 1, X = -170, Z = -1400, Yaw = 0, Kits = { { Kit = "RadioMast", X = 0, Z = 0 } } },
			{ Id = "W_Hut1", Block = "W", Role = "block", Tier = 1, X = -150, Z = -1335, Yaw = -90, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "side", Width = 18, Depth = 12, Storeys = 1, Roof = "mast+dish", Lantern = true } } },
			{ Id = "W_Hut2", Block = "W", Role = "block", Tier = 2, X = -150, Z = -1262, Yaw = -90, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Width = 18, Depth = 12, Storeys = 1, Roof = "dish" } } },
			{ Id = "W_Relay", Block = "W", Role = "heist", Tier = 1, X = -196, Z = -1300, Yaw = -90, Kits = { { Kit = "Terminal", X = 0, Z = 2.5 }, { Kit = "SandbagLine", X = 0, Z = -7, Length = 10 }, { Kit = "SandbagLine", X = -7, Z = 0, Yaw = 90, Length = 10 }, { Kit = "SandbagLine", X = 7, Z = 0, Yaw = -90, Length = 10 }, { Kit = "HoldPad", X = 0, Z = 0, R = 6 } } },
			{ Id = "W_Block", Block = "W", Role = "block", Tier = 2, X = -236, Z = -1360, Yaw = -90, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "damaged", Width = 22, Depth = 16, Storeys = 2, Roof = "tank" } } },
			{ Id = "W_Gen", Block = "W", Role = "crates", Tier = 2, X = -118, Z = -1206, Yaw = -90, Kits = { { Kit = "DrumGroup", X = 0, Z = 0, Count = 3 }, { Kit = "CrateStack", X = 0, Z = 7, Count = 2 } } },
			{ Id = "W_BagsN", Block = "W", Role = "cover", Tier = 1, X = -128, Z = -1418, Yaw = -45, Kits = { { Kit = "SandbagLine", X = 0, Z = 0, Length = 15 } } },
			{ Id = "W_BagsS", Block = "W", Role = "cover", Tier = 1, X = -128, Z = -1182, Yaw = -135, Kits = { { Kit = "SandbagLine", X = 0, Z = 0, Length = 15 } } },
			{ Id = "W_Watch", Block = "W", Role = "tower", Tier = 2, X = -255, Z = -1455, Yaw = 0, Kits = { { Kit = "Watchtower", X = 0, Z = 0 } } },
			{ Id = "W_RelayArc", Block = "W", Role = "cover", Tier = 1, X = -212, Z = -1290, Yaw = -90, Kits = { { Kit = "SandbagArc", X = 0, Z = 0 } } },
			-- east of the pass
			{ Id = "E_Block", Block = "E", Role = "block", Tier = 2, X = 62, Z = -1452, Yaw = 90, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "gutted", Width = 20, Depth = 14, Storeys = 2 } } },
			{ Id = "E_Bags", Block = "E", Role = "cover", Tier = 2, X = 58, Z = -1160, Yaw = 135, Kits = { { Kit = "SandbagArc", X = 0, Z = 0 }, { Kit = "SandbagArc", X = 8, Z = 0 } } },
			{ Id = "Host", Block = "Host", Role = "anchor", Tier = 1, X = -200, Z = -1200, Yaw = 0, Kits = { { Kit = "ActivityHost", X = 0, Z = 0 } } },
		},
		Rocks = {
			{ Kind = "outcrop", X = -250, Z = -1200, Radius = 12, Tier = 1 },
			{ Kind = "rubble", X = -236, Z = -1340, Radius = 6, Tier = 2 },
		},
		Anchors = {
			-- Signal.CP.* (Booth, Alarm, G1, G2, R1, R2) come from the checkpoint template on cluster "CP"
			{ Id = "Signal.Relay.Console", Kind = "console", X = -196, Z = -1300, Yaw = -90, R = 6, Prompt = "hold" }, -- uplink: the HoldPad centre, in front of the relay desk
			{ Id = "Signal.Relay.G1", Kind = "npc", X = -160, Z = -1333, Yaw = -90 }, -- west of W_Hut1
			{ Id = "Signal.Relay.G2", Kind = "npc", X = -128, Z = -1412, Yaw = -45 }, -- behind W_BagsN
			{ Id = "Signal.Relay.G3", Kind = "npc", X = -217.5, Z = -1290, Yaw = -90 }, -- behind W_RelayArc
		},
	},

	-- ═══ RADAR HILL (RadarHill capture; radar uplink). Everything on the 110..130 ring outside the capture clear ═════════
	Radar = {
		Clusters = {
			{ Id = "Dome", Block = "Ring", Role = "landmark", Tier = 1, X = -1053.5, Z = -1009.8, Yaw = 0, Kits = { { Kit = "RadarDome", X = 0, Z = 0 } } },
			{ Id = "Console", Block = "Ring", Role = "heist", Tier = 1, X = -1068.9, Z = -945.8, Yaw = -88, Kits = { { Kit = "Terminal", X = 0, Z = 2.5 }, { Kit = "SandbagArc", X = 0, Z = 5 } } },
			{ Id = "Hut", Block = "Ring", Role = "block", Tier = 2, X = -1050.9, Z = -886.9, Yaw = -90, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Width = 12, Depth = 8, Storeys = 1, Roof = "dish" } } },
			{ Id = "Bags_N", Block = "Ring", Role = "cover", Tier = 1, X = -991.4, Z = -1063.7, Yaw = -160, Kits = { { Kit = "SandbagLine", X = 0, Z = 0, Length = 15 } } },
			{ Id = "Bags_NE", Block = "Ring", Role = "cover", Tier = 1, X = -904.7, Z = -1062.2, Yaw = 158, Kits = { { Kit = "SandbagLine", X = 0, Z = 0, Length = 15 } } },
			{ Id = "Bags_SW", Block = "Ring", Role = "cover", Tier = 2, X = -1014.1, Z = -847.4, Yaw = -32, Kits = { { Kit = "SandbagLine", X = 0, Z = 0, Length = 10 } } },
			{ Id = "Crates", Block = "Ring", Role = "crates", Tier = 2, X = -1022.6, Z = -1043, Yaw = -142, Kits = { { Kit = "CrateStack", X = 0, Z = 0, Count = 3 }, { Kit = "DrumGroup", X = 8, Z = 1, Count = 2 } } },
			{ Id = "Host", Block = "Ring", Role = "anchor", Tier = 1, X = -950, Z = -1072, Yaw = 0, Kits = { { Kit = "ActivityHost", X = 0, Z = 0 } } },
		},
		Rocks = {
			{ Kind = "outcrop", X = -1063.7, Z = -908.6, Radius = 8, Tier = 1 },
		},
		Anchors = {
			{ Id = "Radar.Uplink.Console", Kind = "console", X = -1068.9, Z = -945.8, Yaw = -88, R = 6, Prompt = "hold" }, -- in front of the radar desk, facing the hill
			{ Id = "Radar.Uplink.G1", Kind = "npc", X = -990, Z = -1059.9, Yaw = 20 }, -- behind Bags_N, facing out
			{ Id = "Radar.Uplink.G2", Kind = "npc", X = -906.2, Z = -1058.5, Yaw = -22 }, -- behind Bags_NE, facing out
		},
	},

	-- ═══ FORT IRONCLAD approach (the gate side only; the fort itself is MapSetup's) ═══════════════════════════════════
	FortI = {
		Clusters = {
			{ Id = "GateNest_W", Block = "Gate", Role = "nest", Tier = 1, X = 1424, Z = -1333, Yaw = 180, Kits = { { Kit = "SandbagNest", X = 0, Z = 0 } } },
			{ Id = "GateNest_E", Block = "Gate", Role = "nest", Tier = 1, X = 1476, Z = -1333, Yaw = 180, Kits = { { Kit = "SandbagNest", X = 0, Z = 0 } } },
			{ Id = "Trench_1", Block = "Trench", Role = "trench", Tier = 1, X = 1405, Z = -1290, Yaw = 20, Kits = { { Kit = "SandbagLine", X = 0, Z = 0, Length = 30 } } },
			{ Id = "Trench_2", Block = "Trench", Role = "trench", Tier = 1, X = 1495, Z = -1290, Yaw = -20, Kits = { { Kit = "SandbagLine", X = 0, Z = 0, Length = 30 } } },
			{ Id = "Traps_W", Block = "Traps", Role = "traps", Tier = 1, X = 1385, Z = -1325, Yaw = 0, Kits = { { Kit = "TankTrap", X = -14, Z = 0 }, { Kit = "TankTrap", X = 0, Z = 3 }, { Kit = "TankTrap", X = 14, Z = 0 } } },
			{ Id = "Traps_E", Block = "Traps", Role = "traps", Tier = 2, X = 1515, Z = -1325, Yaw = 0, Kits = { { Kit = "TankTrap", X = -14, Z = 0 }, { Kit = "TankTrap", X = 0, Z = 3 }, { Kit = "TankTrap", X = 14, Z = 0 } } },
			{ Id = "Tank", Block = "Field", Role = "wreck", Tier = 1, X = 1375, Z = -1262, Yaw = 25, Kits = { { Kit = "Wreck", X = 0, Z = 0, Variant = "tank" } } },
			{ Id = "Watch", Block = "Field", Role = "tower", Tier = 2, X = 1560, Z = -1300, Yaw = 180, Kits = { { Kit = "Watchtower", X = 0, Z = 0 } } },
			{ Id = "Host", Block = "Host", Role = "anchor", Tier = 1, X = 1600, Z = -1400, Yaw = 0, Kits = { { Kit = "ActivityHost", X = 0, Z = 0 } } },
		},
		Rocks = {
			{ Kind = "outcrop", X = 1335, Z = -1300, Radius = 12, Tier = 1 },
			{ Kind = "scorch", X = 1420, Z = -1300, Radius = 8, Tier = 1 },
			{ Kind = "scorch", X = 1520, Z = -1270, Radius = 8, Tier = 2 },
		},
		Anchors = {
			{ Id = "FortI.Breach.Gate", Kind = "door", X = 1450, Z = -1376, Yaw = 180, Prompt = "hold" }, -- the 16-wide gate gap: plant the charge (no gate part)
			{ Id = "FortI.Breach.G1", Kind = "npc", X = 1438, Z = -1380, Yaw = 180 }, -- inside, behind the west gate wall piece
			{ Id = "FortI.Breach.G2", Kind = "npc", X = 1462, Z = -1380, Yaw = 180 }, -- inside, behind the east gate wall piece
			{ Id = "FortI.Breach.G3", Kind = "npc", X = 1424, Z = -1337, Yaw = 180 }, -- in the west gate nest
			{ Id = "FortI.Breach.G4", Kind = "npc", X = 1476, Z = -1337, Yaw = 180 }, -- in the east gate nest
		},
	},

	-- ═══ FORT SANDHOLD approach (Fort Ironclad's point mirror through the map centre; r 200: tower and tank pulled in) ═══
	FortS = {
		Clusters = {
			{ Id = "GateNest_W", Block = "Gate", Role = "nest", Tier = 1, X = -1424, Z = 1333, Yaw = 0, Kits = { { Kit = "SandbagNest", X = 0, Z = 0 } } },
			{ Id = "GateNest_E", Block = "Gate", Role = "nest", Tier = 1, X = -1476, Z = 1333, Yaw = 0, Kits = { { Kit = "SandbagNest", X = 0, Z = 0 } } },
			{ Id = "Trench_1", Block = "Trench", Role = "trench", Tier = 1, X = -1405, Z = 1290, Yaw = -160, Kits = { { Kit = "SandbagLine", X = 0, Z = 0, Length = 30 } } },
			{ Id = "Trench_2", Block = "Trench", Role = "trench", Tier = 1, X = -1495, Z = 1290, Yaw = 160, Kits = { { Kit = "SandbagLine", X = 0, Z = 0, Length = 30 } } },
			{ Id = "Traps_W", Block = "Traps", Role = "traps", Tier = 1, X = -1385, Z = 1325, Yaw = -180, Kits = { { Kit = "TankTrap", X = -14, Z = 0 }, { Kit = "TankTrap", X = 0, Z = 3 }, { Kit = "TankTrap", X = 14, Z = 0 } } },
			{ Id = "Traps_E", Block = "Traps", Role = "traps", Tier = 2, X = -1515, Z = 1325, Yaw = -180, Kits = { { Kit = "TankTrap", X = -14, Z = 0 }, { Kit = "TankTrap", X = 0, Z = 3 }, { Kit = "TankTrap", X = 14, Z = 0 } } },
			{ Id = "Tank", Block = "Field", Role = "wreck", Tier = 1, X = -1396, Z = 1282, Yaw = -155, Kits = { { Kit = "Wreck", X = 0, Z = 0, Variant = "tank" } } }, -- moved 3 from the draft's (-1395, 1285), whose tracks cut 0.8 into Trench_1: now 2.3 clear
			{ Id = "Watch", Block = "Field", Role = "tower", Tier = 2, X = -1545, Z = 1290, Yaw = 0, Kits = { { Kit = "Watchtower", X = 0, Z = 0 } } },
			{ Id = "Host", Block = "Host", Role = "anchor", Tier = 1, X = -1600, Z = 1400, Yaw = -180, Kits = { { Kit = "ActivityHost", X = 0, Z = 0 } } },
		},
		Rocks = {
			{ Kind = "outcrop", X = -1345, Z = 1310, Radius = 12, Tier = 1 },
			{ Kind = "scorch", X = -1420, Z = 1300, Radius = 8, Tier = 1 },
			{ Kind = "scorch", X = -1510, Z = 1285, Radius = 8, Tier = 2 },
		},
		Anchors = {
			{ Id = "FortS.Breach.Gate", Kind = "door", X = -1450, Z = 1376, Yaw = 0, Prompt = "hold" }, -- the 16-wide gate gap: plant the charge (no gate part)
			{ Id = "FortS.Breach.G1", Kind = "npc", X = -1438, Z = 1380, Yaw = 0 }, -- inside, behind the gate wall piece
			{ Id = "FortS.Breach.G2", Kind = "npc", X = -1462, Z = 1380, Yaw = 0 }, -- inside, behind the other gate wall piece
			{ Id = "FortS.Breach.G3", Kind = "npc", X = -1424, Z = 1337, Yaw = 0 }, -- in a gate nest
			{ Id = "FortS.Breach.G4", Kind = "npc", X = -1476, Z = 1337, Yaw = 0 }, -- in the other gate nest
		},
	},
}

return Layouts
