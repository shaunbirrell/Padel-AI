--!strict
--[[
	WAR EMPIRE W3 step 2 — POI layout rows, group "Industry": Port, Depot, Armory, OilField, RigA, RigB.

	Lane D1, from the geometry plan's drafts (scratchpad w3s2/geo, layouts.py) with the merged spec's renames (§1.5) and
	the L0 contract's edits (§4). Keyed by POI Id; WorldPOI (lane P) reads a row for every ENABLED WorldConfig.POIs row
	whose Layout = "Industry". Budgets, Reserve, lights, signs and LowShare live in that WorldConfig row, not here.
	Data only: it requires nothing but WorldConfig (for the row types) and never yields.

	Rows (WorldConfig.POILayout):
	  • Clusters — the Town row format (TownCluster / KitPlace), world studs. Yaw 0 = the cluster front faces north (-Z),
	    90 = west (-X), -90 = east (+X), 180 = south (+Z); kits are local to the cluster frame. Tier 1 = built in Quality
	    Low and Full, Tier 2 = Full only. InWater = may stand over water (gantry, jetty).
	  • Rocks — Terrain rubble (0 parts).
	  • Anchors — activity anchors (invisible tagged Attachments, 0 parts) in WORLD studs, ids "<POI>.<Site>.<Role>".
	    They are stamped on the POI's one ActivityHost part (the "Host" cluster; it never moves). Y is the standing surface
	    above the desert floor (14 = a watchtower deck). Requires = a cluster Id here: the anchor exists only when that
	    cluster was built (Tier 2 clusters are not built at Quality Low).
	  • The checkpoint anchors (Booth, Alarm, G1, G2, R1, R2) are NOT rows here: WorldPOI stamps
	    WorldConfig.Activity.CheckpointAnchors on every Checkpoint kit, ids "<POI>.<cluster Id>.<Role>". So a POI with one
	    road checkpoint names that cluster "CP" (Port.CP.*, RigA.CP.*) and the Depot / Armory keep CP_E and CP_W.
	  • PoiBoard kits leave Text nil: WorldPOI paints Board (within the POI's Signs and Budgets.SurfaceGuis).

	Jobs here (spec §1.7; Phase B OpsService reads the anchors, nothing reads them yet):
	  Port     — customs-yard heist: breach the HeistGate (Gate) → crack at Vault → grab at Loot → carry home.
	  Depot    — fuel-yard heist: "Start siphon" at Pump → crack → grab → carry. Truck is reserved (vehicle delivery).
	  Armory   — hangar cache: "Start crack" at Vault → crack → grab at Loot → carry. Bunker.Door is reserved.
	  OilField — sabotage the pumps (Pump3 / Pump4 need Quality Full). Siphon.Valve / Siphon.Truck are reserved.
	  RigA/B   — storm the rig (deck posts come from OpsConfig) + the road checkpoint, with G3 behind the sandbag arc.
	  Prompt = "hold" marks where a job puts a hold prompt (breach, start, grab, plant), as in Town.BankAnchors.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldConfig = require(ReplicatedStorage.Shared.Configs.WorldConfig)

local YARD_STEEL = Color3.fromRGB(74, 72, 66) -- the customs-yard walls

local Layouts: { [string]: WorldConfig.POILayout } = {
	-- ═══ SOUTH PORT (SouthDocks capture by boat; Quay arena; customs-yard heist). Replaces the legacy Dockside kit. ═══
	Port = {
		Board = "SOUTH DOCKS",
		Clusters = {
			{ Id = "CP", Block = "Road", Role = "checkpoint", Tier = 1, X = 0, Z = 1168, Yaw = 0, Street = true, Kits = { { Kit = "Checkpoint", X = 0, Z = 0 } } },
			{ Id = "Board", Block = "Road", Role = "board", Tier = 1, X = -24, Z = 1158, Yaw = 0, Street = true, Kits = { { Kit = "PoiBoard", X = 0, Z = 0 } } },
			-- east yard: harbour office (lantern), the customs yard (heist), containers round the Quay arena, the gantry.
			-- The yard (x 251.2 .. 283.2, z 1176.2 .. 1213.8) is closed: the N / S walls meet the W wall and the customs shed,
			-- so on foot the way in is the HeistGate (the walls are chest-high: a jump still clears them).
			{ Id = "E_Office", Block = "E", Role = "block", Tier = 1, X = 150, Z = 1190, Yaw = 90, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "shop+side", Width = 24, Depth = 18, Storeys = 3, Roof = "mast+tank", Lantern = true } } },
			{ Id = "E_Customs", Block = "E", Role = "heist", Tier = 1, X = 292.2, Z = 1195, Yaw = 90, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "roller+metal+rear", Width = 38, Depth = 18, Storeys = 2, Roof = "tank" } } }, -- closes the yard's east side
			{ Id = "E_YardN", Block = "E", Role = "heist", Tier = 1, X = 267.2, Z = 1175, Yaw = 0, Kits = { { Kit = "CompoundWall", X = 0, Z = 0, Length = 32, Color = YARD_STEEL } } },
			{ Id = "E_YardS", Block = "E", Role = "heist", Tier = 1, X = 267.2, Z = 1215, Yaw = 180, Kits = { { Kit = "CompoundWall", X = 0, Z = 0, Length = 32, Color = YARD_STEEL } } },
			{ Id = "E_YardW", Block = "E", Role = "heist", Tier = 1, X = 250, Z = 1195, Yaw = 90, Kits = { { Kit = "CompoundWall", X = -13, Z = 0, Length = 16 }, { Kit = "CompoundWall", X = 13, Z = 0, Length = 16 }, { Kit = "CompoundWall", X = 0, Z = -2, Variant = "gate", Length = 16 } } },
			{ Id = "E_Cargo", Block = "E", Role = "heist", Tier = 1, X = 276, Z = 1192, Yaw = 90, Kits = { { Kit = "CrateStack", X = 0, Z = 0, Variant = "ammo", Count = 6 }, { Kit = "HoldPad", X = 0, Z = -9, R = 7 } } },
			{ Id = "E_Block2", Block = "E", Role = "block", Tier = 2, X = 206, Z = 1178, Yaw = 180, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "damaged", Width = 22, Depth = 18, Storeys = 2 } } },
			{ Id = "E_Cont1", Block = "E", Role = "containers", Tier = 1, X = 195, Z = 1300, Yaw = 0, Kits = { { Kit = "ContainerStack", X = 0, Z = 0, Count = 3 } } },
			{ Id = "E_Cont2", Block = "E", Role = "containers", Tier = 2, X = 305, Z = 1285, Yaw = 90, Kits = { { Kit = "ContainerStack", X = 0, Z = 0, Count = 3 } } },
			{ Id = "E_Cont3", Block = "E", Role = "containers", Tier = 2, X = 232, Z = 1338, Yaw = 90, Kits = { { Kit = "ContainerStack", X = 0, Z = 0, Count = 2 } } },
			{ Id = "E_Cont4", Block = "E", Role = "containers", Tier = 2, X = 305, Z = 1332, Yaw = 0, Kits = { { Kit = "ContainerStack", X = 0, Z = 0, Count = 2 } } },
			{ Id = "E_Gantry", Block = "E", Role = "landmark", Tier = 1, X = 150, Z = 1340, Yaw = 180, InWater = true, Kits = { { Kit = "GantryCrane", X = 0, Z = 0 } } },
			{ Id = "E_Lamp", Block = "E", Role = "lamp", Tier = 1, X = 215, Z = 1238, Yaw = 0, Kits = { { Kit = "StreetLamp", X = 0, Z = 0 } } },
			{ Id = "E_Jetty", Block = "E", Role = "jetty", Tier = 2, X = 205, Z = 1364, Yaw = 180, InWater = true, Kits = { { Kit = "JettyStub", X = 0, Z = 0 } } },
			{ Id = "SE_Watch", Block = "SE", Role = "tower", Tier = 2, X = 295, Z = 1420, Yaw = 180, Kits = { { Kit = "Watchtower", X = 0, Z = 0 } } },
			-- west yard: the big transit shed, a dock office, a damaged block, the SW tank farm, the quay
			{ Id = "W_Shed", Block = "W", Role = "block", Tier = 1, X = -262, Z = 1235, Yaw = -90, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "roller+metal+left", Width = 46, Depth = 30, Storeys = 2, Roof = "hut" } } },
			{ Id = "W_Office", Block = "W", Role = "block", Tier = 2, X = -205, Z = 1190, Yaw = -90, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "shop+side", Width = 24, Depth = 18, Storeys = 3, Roof = "tank" } } },
			{ Id = "W_Block3", Block = "W", Role = "block", Tier = 2, X = -208, Z = 1290, Yaw = -90, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "damaged", Width = 22, Depth = 18, Storeys = 3 } } },
			{ Id = "SW_Tanks", Block = "SW", Role = "landmark", Tier = 1, X = -288, Z = 1415, Yaw = 0, Kits = { { Kit = "FuelTank", X = -12, Z = -23 }, { Kit = "FuelTank", X = 16, Z = 0 }, { Kit = "FuelTank", X = -12, Z = 23 } } },
			{ Id = "W_Quay", Block = "W", Role = "crates", Tier = 2, X = -195, Z = 1333, Yaw = 0, Kits = { { Kit = "CrateStack", X = 0, Z = 0, Count = 3 }, { Kit = "DrumGroup", X = 22, Z = 2, Count = 3 } } },
			{ Id = "W_Jetty", Block = "W", Role = "jetty", Tier = 2, X = -200, Z = 1364, Yaw = 180, InWater = true, Kits = { { Kit = "JettyStub", X = 0, Z = 0 } } },
			{ Id = "W_Lamp", Block = "W", Role = "lamp", Tier = 1, X = -232, Z = 1290, Yaw = 90, Kits = { { Kit = "StreetLamp", X = 0, Z = 0 } } },
			{ Id = "W_Nest", Block = "W", Role = "nest", Tier = 2, X = -172, Z = 1240, Yaw = -90, Kits = { { Kit = "SandbagNest", X = 0, Z = 0 } } },
			{ Id = "E_GuardArc", Block = "E", Role = "cover", Tier = 1, X = 211, Z = 1200, Yaw = 90, Kits = { { Kit = "SandbagArc", X = 0, Z = 0 } } },
			{ Id = "Host", Block = "Host", Role = "anchor", Tier = 1, X = 170, Z = 1255, Yaw = 0, Kits = { { Kit = "ActivityHost", X = 0, Z = 0 } } },
		},
		Rocks = {
			{ Kind = "scorch", X = -190, Z = 1320, Radius = 8, Tier = 1 },
			{ Kind = "rubble", X = 222, Z = 1165, Radius = 6, Tier = 1 },
		},
		Anchors = {
			-- Port.CP.* (Booth, Alarm, G1, G2, R1, R2) come from the checkpoint template on cluster "CP"
			{ Id = "Port.Customs.Gate", Kind = "door", X = 246, Z = 1195, Yaw = -90, Prompt = "hold", Part = "HeistGate" }, -- outside the yard, 2 studs in front of the HeistGate, facing it
			{ Id = "Port.Customs.Vault", Kind = "hold", X = 267, Z = 1192, Yaw = 0, R = 7 }, -- on E_Cargo's HoldPad (in front of the crates, inside the gate); freezes under fire
			{ Id = "Port.Customs.Loot", Kind = "loot", X = 273.5, Z = 1192, Yaw = -90, Prompt = "hold" }, -- on the pad, 2.5 studs in front of the seized-cargo crates; carry to your own ATM
			{ Id = "Port.Customs.G1", Kind = "npc", X = 280, Z = 1210, Yaw = 90 }, -- inside the yard, the south-east corner
			{ Id = "Port.Customs.G2", Kind = "npc", X = 254, Z = 1182, Yaw = 90 }, -- inside the yard, behind the west wall
			{ Id = "Port.Customs.G3", Kind = "npc", X = 216, Z = 1200, Yaw = 90 }, -- behind E_GuardArc
			{ Id = "Port.Quay.Arena", Kind = "arena", X = 250, Z = 1250, Yaw = 0 }, -- the existing Quay event spot (supply run / events)
			{ Id = "Port.Harbour.BoatDrop", Kind = "deliver_boat", X = 205, Z = 1382, Yaw = 180 }, -- off the east jetty: loot delivery by boat (reserved)
		},
	},

	-- ═══ WEST SUPPLY DEPOT (WestDepot capture; fuel-yard heist; 2 road checkpoints) ═══════════════════════════════════
	Depot = {
		Board = "WEST DEPOT",
		Clusters = {
			{ Id = "CP_E", Block = "Road", Role = "checkpoint", Tier = 1, X = -1127, Z = 0, Yaw = -90, Street = true, Kits = { { Kit = "Checkpoint", X = 0, Z = 0 } } },
			{ Id = "CP_W", Block = "Road", Role = "checkpoint", Tier = 1, X = -1483, Z = 0, Yaw = 90, Street = true, Kits = { { Kit = "Checkpoint", X = 0, Z = 0 } } },
			{ Id = "Board", Block = "Road", Role = "board", Tier = 1, X = -1124, Z = -27, Yaw = -90, Street = true, Kits = { { Kit = "PoiBoard", X = 0, Z = 0 } } },
			{ Id = "FenceE_N", Block = "Road", Role = "fence", Tier = 2, X = -1135, Z = -62, Yaw = 90, Kits = { { Kit = "WireFence", X = 0, Z = 0, Length = 32 } } },
			{ Id = "FenceE_S", Block = "Road", Role = "fence", Tier = 2, X = -1135, Z = 62, Yaw = 90, Kits = { { Kit = "WireFence", X = 0, Z = 0, Length = 32 } } },
			-- north yard: the tank farm (landmark), the pipe rack, the pump house + fuel yard (heist), trucks, 2 towers
			{ Id = "N_Tanks", Block = "N", Role = "landmark", Tier = 1, X = -1305, Z = -165, Yaw = 0, Kits = { { Kit = "FuelTank", X = -20, Z = 0, Scale = 1.3 }, { Kit = "FuelTank", X = 0, Z = -4, Scale = 1.3 }, { Kit = "FuelTank", X = 20, Z = 0, Scale = 1.3 } } },
			{ Id = "N_Rack", Block = "N", Role = "pipes", Tier = 2, X = -1305, Z = -136, Yaw = 0, Kits = { { Kit = "PipeRun", X = 0, Z = 0, Variant = "rack", Length = 40 } } },
			{ Id = "N_PumpHouse", Block = "N", Role = "heist", Tier = 1, X = -1472, Z = -120, Yaw = -90, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "roller+metal", Width = 16, Depth = 12, Storeys = 1, Roof = "tank" } } },
			{ Id = "N_FuelYard", Block = "N", Role = "heist", Tier = 1, X = -1440, Z = -112, Yaw = 0, Kits = { { Kit = "HoldPad", X = 0, Z = 0, R = 8 }, { Kit = "FuelTank", X = -20, Z = -30, Scale = 0.8 }, { Kit = "Jersey", X = -8, Z = 20 }, { Kit = "Jersey", X = 8, Z = 20 } } },
			{ Id = "N_Trucks", Block = "N", Role = "wrecks", Tier = 2, X = -1178, Z = -150, Yaw = 0, Kits = { { Kit = "Wreck", X = 0, Z = 0, Variant = "truck" }, { Kit = "Wreck", X = 0, Z = 12, Variant = "truck" } } },
			{ Id = "N_Watch1", Block = "N", Role = "tower", Tier = 1, X = -1482, Z = -183, Yaw = 0, Kits = { { Kit = "Watchtower", X = 0, Z = 0 } } },
			{ Id = "N_Watch2", Block = "N", Role = "tower", Tier = 2, X = -1128, Z = -183, Yaw = 0, Kits = { { Kit = "Watchtower", X = 0, Z = 0 } } },
			{ Id = "N_Barracks", Block = "N", Role = "block", Tier = 2, X = -1400, Z = -178, Yaw = 180, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "side", Width = 30, Depth = 14, Storeys = 2, Roof = "mast" } } },
			-- south yard: the garrison (lantern), sheds, crates
			{ Id = "S_Garrison", Block = "S", Role = "block", Tier = 1, X = -1380, Z = 165, Yaw = 0, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "side+rear", Width = 30, Depth = 16, Storeys = 2, Roof = "mast", Lantern = true } } },
			{ Id = "S_Shed1", Block = "S", Role = "block", Tier = 1, X = -1248, Z = 165, Yaw = 0, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "roller+metal+side", Width = 34, Depth = 20, Storeys = 2, Roof = "tanks" } } },
			{ Id = "S_Shed2", Block = "S", Role = "block", Tier = 2, X = -1455, Z = 150, Yaw = 0, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "roller+metal", Width = 26, Depth = 18, Storeys = 1 } } },
			{ Id = "S_Crates", Block = "S", Role = "crates", Tier = 2, X = -1300, Z = 140, Yaw = 0, Kits = { { Kit = "CrateStack", X = -6, Z = 0, Count = 6 }, { Kit = "CrateStack", X = 6, Z = 0, Count = 3 }, { Kit = "DrumGroup", X = 0, Z = 9, Count = 3 } } },
			{ Id = "S_Lamp", Block = "S", Role = "lamp", Tier = 1, X = -1155, Z = 72, Yaw = 90, Kits = { { Kit = "StreetLamp", X = 0, Z = 0 } } },
			{ Id = "N_GuardArc", Block = "N", Role = "cover", Tier = 1, X = -1415, Z = -134, Yaw = 180, Kits = { { Kit = "SandbagArc", X = 0, Z = 0 } } },
			{ Id = "Host", Block = "Host", Role = "anchor", Tier = 1, X = -1250, Z = 120, Yaw = 0, Kits = { { Kit = "ActivityHost", X = 0, Z = 0 } } },
		},
		Rocks = {
			{ Kind = "scorch", X = -1200, Z = -120, Radius = 8, Tier = 1 },
		},
		Anchors = {
			-- Depot.CP_E.* and Depot.CP_W.* come from the checkpoint template
			{ Id = "Depot.Fuel.Pump", Kind = "hold", X = -1440, Z = -112, Yaw = 0, R = 8, Prompt = "hold" }, -- "Start siphon" on the fuel-yard HoldPad; freezes under fire
			{ Id = "Depot.Fuel.Truck", Kind = "vehicle", X = -1440, Z = -112, Yaw = 90, Box = { 10, 24 } }, -- event tanker spawn (reserved: vehicle delivery)
			{ Id = "Depot.Fuel.G1", Kind = "npc", X = -1482, Z = -183, Yaw = 0, Y = 14, Requires = "N_Watch1" }, -- watchtower deck
			{ Id = "Depot.Fuel.G2", Kind = "npc", X = -1448, Z = -95, Yaw = 180 }, -- behind the fuel-yard jersey
			{ Id = "Depot.Fuel.G3", Kind = "npc", X = -1415, Z = -139.5, Yaw = 180 }, -- behind N_GuardArc
		},
	},

	-- ═══ EAST ARMORY (EastArmory capture; hangar arms cache; 2 road checkpoints) ═══════════════════════════════════════
	Armory = {
		Board = "EAST ARMORY",
		Clusters = {
			{ Id = "CP_W", Block = "Road", Role = "checkpoint", Tier = 1, X = 1127, Z = 0, Yaw = 90, Street = true, Kits = { { Kit = "Checkpoint", X = 0, Z = 0 } } },
			{ Id = "CP_E", Block = "Road", Role = "checkpoint", Tier = 1, X = 1483, Z = 0, Yaw = -90, Street = true, Kits = { { Kit = "Checkpoint", X = 0, Z = 0 } } },
			{ Id = "Board", Block = "Road", Role = "board", Tier = 1, X = 1124, Z = 27, Yaw = 90, Street = true, Kits = { { Kit = "PoiBoard", X = 0, Z = 0 } } },
			{ Id = "FenceW_N", Block = "Road", Role = "fence", Tier = 2, X = 1135, Z = -62, Yaw = 90, Kits = { { Kit = "WireFence", X = 0, Z = 0, Length = 32 } } },
			{ Id = "FenceW_S", Block = "Road", Role = "fence", Tier = 2, X = 1135, Z = 62, Yaw = 90, Kits = { { Kit = "WireFence", X = 0, Z = 0, Length = 32 } } },
			-- south yard: the hangar with the arms cache (heist), 2 bunkers, 2 gun pits, a tower
			{ Id = "S_Hangar", Block = "S", Role = "heist", Tier = 1, X = 1300, Z = 168, Yaw = 0, Kits = { { Kit = "Hangar", X = 0, Z = 0, Width = 32 } } },
			{ Id = "S_Cache", Block = "S", Role = "heist", Tier = 1, X = 1300, Z = 172, Yaw = 0, Kits = { { Kit = "CrateStack", X = -8, Z = 0, Variant = "ammo", Count = 6 }, { Kit = "HoldPad", X = 4, Z = -4, R = 7 } } },
			{ Id = "S_Bunker1", Block = "S", Role = "heist", Tier = 1, X = 1420, Z = 176, Yaw = 0, Kits = { { Kit = "Bunker", X = 0, Z = 0 } } },
			{ Id = "S_Bunker2", Block = "S", Role = "bunker", Tier = 2, X = 1188, Z = 176, Yaw = 0, Kits = { { Kit = "Bunker", X = 0, Z = 0 } } },
			{ Id = "S_Gun1", Block = "S", Role = "gunpit", Tier = 1, X = 1238, Z = 120, Yaw = -45, Kits = { { Kit = "SandbagArc", X = -3, Z = -2, Yaw = 20 }, { Kit = "SandbagArc", X = 3, Z = -2, Yaw = -20 } } },
			{ Id = "S_Gun1g", Block = "S", Role = "gunpit", Tier = 2, X = 1235.9, Z = 122.1, Yaw = -45, Kits = { { Kit = "Wreck", X = 0, Z = 0, Variant = "gun" } } },
			{ Id = "S_Gun2", Block = "S", Role = "gunpit", Tier = 1, X = 1368, Z = 118, Yaw = 45, Kits = { { Kit = "SandbagArc", X = -3, Z = -2, Yaw = 20 }, { Kit = "SandbagArc", X = 3, Z = -2, Yaw = -20 } } },
			{ Id = "S_Gun2g", Block = "S", Role = "gunpit", Tier = 2, X = 1370.1, Z = 120.1, Yaw = 45, Kits = { { Kit = "Wreck", X = 0, Z = 0, Variant = "gun" } } },
			{ Id = "S_Watch", Block = "S", Role = "tower", Tier = 2, X = 1482, Z = 183, Yaw = 180, Kits = { { Kit = "Watchtower", X = 0, Z = 0 } } },
			-- north yard: the HQ (landmark, lantern), barracks, tank traps, a tower, crates
			{ Id = "N_HQ", Block = "N", Role = "landmark", Tier = 1, X = 1400, Z = -168, Yaw = 180, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "shop+side+left", Width = 30, Depth = 18, Storeys = 3, Roof = "mast+dish", Lantern = true } } },
			{ Id = "N_Barracks", Block = "N", Role = "block", Tier = 2, X = 1250, Z = -172, Yaw = 180, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "side", Width = 28, Depth = 14, Storeys = 2, Roof = "tank" } } },
			{ Id = "N_Traps", Block = "N", Role = "traps", Tier = 2, X = 1470, Z = -85, Yaw = 0, Kits = { { Kit = "TankTrap", X = 0, Z = -20 }, { Kit = "TankTrap", X = 0, Z = 0 }, { Kit = "TankTrap", X = 0, Z = 20 } } },
			{ Id = "N_Watch", Block = "N", Role = "tower", Tier = 2, X = 1128, Z = -183, Yaw = 0, Kits = { { Kit = "Watchtower", X = 0, Z = 0 } } },
			{ Id = "N_Crates", Block = "N", Role = "crates", Tier = 2, X = 1300, Z = -140, Yaw = 180, Kits = { { Kit = "CrateStack", X = 0, Z = 0, Count = 3 }, { Kit = "DrumGroup", X = 8, Z = 1, Count = 3 } } },
			{ Id = "N_Lamp", Block = "N", Role = "lamp", Tier = 1, X = 1155, Z = -72, Yaw = -90, Kits = { { Kit = "StreetLamp", X = 0, Z = 0 } } },
			{ Id = "Host", Block = "Host", Role = "anchor", Tier = 1, X = 1250, Z = -120, Yaw = 0, Kits = { { Kit = "ActivityHost", X = 0, Z = 0 } } },
		},
		Rocks = {
			{ Kind = "outcrop", X = 1420, Z = 190, Radius = 10, Tier = 1 },
			{ Kind = "outcrop", X = 1188, Z = 190, Radius = 10, Tier = 2 },
		},
		Anchors = {
			-- Armory.CP_W.* and Armory.CP_E.* come from the checkpoint template
			{ Id = "Armory.Cache.Vault", Kind = "hold", X = 1304, Z = 168, Yaw = 180, R = 7, Prompt = "hold" }, -- "Start crack" on S_Cache's HoldPad inside the open-front hangar (13 tall: a phone camera fits)
			{ Id = "Armory.Cache.Loot", Kind = "loot", X = 1297, Z = 174, Yaw = 90, Prompt = "hold" }, -- 2.3 studs east of the arms crates, facing them
			{ Id = "Armory.Cache.G1", Kind = "npc", X = 1230, Z = 111, Yaw = -45 }, -- beside the west gun pit
			{ Id = "Armory.Cache.G2", Kind = "npc", X = 1376, Z = 109, Yaw = 45 }, -- beside the east gun pit
			{ Id = "Armory.Cache.G3", Kind = "npc", X = 1282, Z = 160, Yaw = 0 }, -- the hangar mouth
			{ Id = "Armory.Bunker.Door", Kind = "door", X = 1420, Z = 173.5, Yaw = 180, Prompt = "hold", Part = "BunkerDoor" }, -- 2 studs in front of the blast door, facing it (reserved)
		},
	},

	-- ═══ OIL FIELD (OilFields capture; sabotage the pumps) ═════════════════════════════════════════════════════════════
	OilField = {
		Board = "OIL FIELDS",
		Clusters = {
			{ Id = "Board", Block = "Road", Role = "board", Tier = 1, X = 842, Z = 1012, Yaw = 90, Street = true, Kits = { { Kit = "PoiBoard", X = 0, Z = 0 } } },
			-- the 4 pumpjacks (sabotage targets; PJ_3 / PJ_4 are Quality Full only)
			{ Id = "PJ_1", Block = "Pumps", Role = "pumpjack", Tier = 1, X = 1112, Z = 872, Yaw = 90, Kits = { { Kit = "Pumpjack", X = 0, Z = 0 }, { Kit = "DrumGroup", X = 6, Z = 4, Count = 2 } } },
			{ Id = "PJ_2", Block = "Pumps", Role = "pumpjack", Tier = 1, X = 1182, Z = 962, Yaw = 90, Kits = { { Kit = "Pumpjack", X = 0, Z = 0 } } },
			{ Id = "PJ_3", Block = "Pumps", Role = "pumpjack", Tier = 2, X = 872, Z = 1112, Yaw = 0, Kits = { { Kit = "Pumpjack", X = 0, Z = 0 }, { Kit = "DrumGroup", X = 6, Z = 4, Count = 2 } } },
			{ Id = "PJ_4", Block = "Pumps", Role = "pumpjack", Tier = 2, X = 962, Z = 1182, Yaw = 0, Kits = { { Kit = "Pumpjack", X = 0, Z = 0 } } },
			-- the yard: tank farm and flare stack (landmarks), pump house, the manifold (siphon, reserved), pipe racks
			{ Id = "Tanks", Block = "Yard", Role = "landmark", Tier = 1, X = 1192, Z = 1060, Yaw = 0, Kits = { { Kit = "FuelTank", X = -12, Z = -20, Scale = 1.4 }, { Kit = "FuelTank", X = 12, Z = 0, Scale = 1.4 }, { Kit = "FuelTank", X = -12, Z = 20, Scale = 1.4 } } },
			{ Id = "Flare", Block = "Yard", Role = "landmark", Tier = 1, X = 1205, Z = 1205, Yaw = 0, Kits = { { Kit = "FlareStack", X = 0, Z = 0 } } },
			{ Id = "PumpHouse", Block = "Yard", Role = "heist", Tier = 1, X = 1062, Z = 1205, Yaw = 0, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "roller+metal", Width = 20, Depth = 14, Storeys = 1, Roof = "tank" } } },
			{ Id = "Manifold", Block = "Yard", Role = "heist", Tier = 1, X = 1030, Z = 1160, Yaw = 0, Kits = { { Kit = "FuelTank", X = 0, Z = 12, Scale = 0.6 }, { Kit = "HoldPad", X = 0, Z = -2, R = 8 }, { Kit = "Jersey", X = -12, Z = -12, Yaw = 30 }, { Kit = "Jersey", X = 12, Z = -12, Yaw = -30 } } },
			{ Id = "RackN", Block = "Yard", Role = "pipes", Tier = 2, X = 1120, Z = 1170, Yaw = 0, Kits = { { Kit = "PipeRun", X = 0, Z = 0, Variant = "rack", Length = 40 } } },
			{ Id = "RackE", Block = "Yard", Role = "pipes", Tier = 2, X = 1165, Z = 1120, Yaw = 90, Kits = { { Kit = "PipeRun", X = 0, Z = 0, Variant = "rack", Length = 40 } } },
			{ Id = "Shack_E", Block = "Yard", Role = "block", Tier = 2, X = 1212, Z = 880, Yaw = 90, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Width = 18, Depth = 12, Storeys = 1, Roof = "hut" } } },
			{ Id = "Shack_S", Block = "Yard", Role = "block", Tier = 2, X = 880, Z = 1212, Yaw = 0, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "damaged", Width = 20, Depth = 14, Storeys = 2 } } },
			{ Id = "YardCover1", Block = "Yard", Role = "cover", Tier = 1, X = 1100, Z = 1060, Yaw = 0, Kits = { { Kit = "CrateStack", X = 0, Z = 0, Count = 3 }, { Kit = "DrumGroup", X = 10, Z = 0, Count = 3 } } },
			{ Id = "YardCover2", Block = "Yard", Role = "cover", Tier = 2, X = 1140, Z = 1100, Yaw = -90, Kits = { { Kit = "Wreck", X = 0, Z = 0, Variant = "truck" } } },
			{ Id = "PipeN", Block = "Road", Role = "pipes", Tier = 2, X = 1150, Z = 852, Yaw = 0, Kits = { { Kit = "PipeRun", X = 0, Z = 0, Length = 40 } } },
			{ Id = "Host", Block = "Host", Role = "anchor", Tier = 1, X = 1150, Z = 1000, Yaw = 0, Kits = { { Kit = "ActivityHost", X = 0, Z = 0 } } },
		},
		Rocks = {
			{ Kind = "scorch", X = 1075, Z = 1125, Radius = 9, Tier = 1 },
			{ Kind = "scorch", X = 1180, Z = 990, Radius = 8, Tier = 1 },
			{ Kind = "scorch", X = 990, Z = 1180, Radius = 8, Tier = 2 },
		},
		Anchors = {
			{ Id = "OilField.Siphon.Valve", Kind = "hold", X = 1030, Z = 1158, Yaw = 0, R = 8 }, -- the manifold HoldPad: fill an oil tanker (reserved)
			{ Id = "OilField.Siphon.Truck", Kind = "vehicle", X = 1062, Z = 1178, Yaw = 90, Box = { 10, 24 } }, -- tanker spawn (reserved)
			{ Id = "OilField.Pumps.G1", Kind = "npc", X = 1018, Z = 1146, Yaw = 30 }, -- behind the west manifold jersey
			{ Id = "OilField.Pumps.G2", Kind = "npc", X = 1042, Z = 1146, Yaw = -30 }, -- behind the east manifold jersey
			{ Id = "OilField.Pumps.G3", Kind = "npc", X = 1100, Z = 1068, Yaw = 0 }, -- behind YardCover1
			{ Id = "OilField.Pumps.Pump1", Kind = "sabotage", X = 1112, Z = 876, Yaw = 0, R = 5, Prompt = "hold" }, -- beside PJ_1 (2.7 off its base, the field side), facing it
			{ Id = "OilField.Pumps.Pump2", Kind = "sabotage", X = 1182, Z = 966, Yaw = 0, R = 5, Prompt = "hold" },
			{ Id = "OilField.Pumps.Pump3", Kind = "sabotage", X = 876, Z = 1112, Yaw = 90, R = 5, Prompt = "hold", Requires = "PJ_3" },
			{ Id = "OilField.Pumps.Pump4", Kind = "sabotage", X = 966, Z = 1182, Yaw = 90, R = 5, Prompt = "hold", Requires = "PJ_4" },
			{ Id = "OilField.Yard.Arena", Kind = "arena", X = 1100, Z = 1100, Yaw = 0 }, -- the existing OilYard event spot
		},
	},

	-- ═══ RIG ALPHA shore base (the CoastalOilAlpha pier foot; storm the rig by boat or the pier) ════════════════════════
	RigA = {
		Clusters = {
			{ Id = "CP", Block = "Road", Role = "checkpoint", Tier = 1, X = 1600, Z = -800, Yaw = 90, Street = true, Kits = { { Kit = "Checkpoint", X = 0, Z = 0 } } },
			{ Id = "Office", Block = "Yard", Role = "block", Tier = 1, X = 1578, Z = -857, Yaw = 180, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "metal", Width = 16, Depth = 10, Storeys = 1, Roof = "mast" } } },
			{ Id = "Crane", Block = "Yard", Role = "landmark", Tier = 1, X = 1668, Z = -700, Yaw = -90, InWater = true, Kits = { { Kit = "GantryCrane", X = 0, Z = 0, Scale = 0.6 } } },
			{ Id = "Tanks", Block = "Yard", Role = "tanks", Tier = 2, X = 1590, Z = -690, Yaw = 0, Kits = { { Kit = "FuelTank", X = -12, Z = 0 }, { Kit = "FuelTank", X = 12, Z = 8 } } },
			{ Id = "Rack", Block = "Yard", Role = "pipes", Tier = 2, X = 1605, Z = -742, Yaw = 0, Kits = { { Kit = "PipeRun", X = 0, Z = 0, Variant = "rack", Length = 40 } } },
			{ Id = "Boxes", Block = "Yard", Role = "containers", Tier = 2, X = 1560, Z = -645, Yaw = 90, Kits = { { Kit = "ContainerStack", X = 0, Z = 0, Count = 2 } } },
			{ Id = "Arc", Block = "Yard", Role = "cover", Tier = 1, X = 1655, Z = -850, Yaw = 0, Kits = { { Kit = "SandbagArc", X = 0, Z = 0 } } },
			{ Id = "Host", Block = "Host", Role = "anchor", Tier = 1, X = 1560, Z = -780, Yaw = 0, Kits = { { Kit = "ActivityHost", X = 0, Z = 0 } } },
		},
		Rocks = {},
		Anchors = {
			-- RigA.CP.* (Booth, Alarm, G1, G2, R1, R2) come from the checkpoint template on cluster "CP"
			{ Id = "RigA.CP.G3", Kind = "npc", X = 1655, Z = -846, Yaw = 90 }, -- behind the sandbag arc
			{ Id = "RigA.Deck.Pier", Kind = "npc", X = 1655, Z = -750, Yaw = 90 }, -- the pier foot, on the sand 4 studs west of the stair landing (MapSetup CoastalOilAlpha_RampApproach, x 1659..1689)
		},
	},

	-- ═══ RIG BRAVO shore base (RigA mirrored through the map centre) ═══════════════════════════════════════════════════
	RigB = {
		Clusters = {
			{ Id = "CP", Block = "Road", Role = "checkpoint", Tier = 1, X = -1600, Z = 800, Yaw = -90, Street = true, Kits = { { Kit = "Checkpoint", X = 0, Z = 0 } } },
			{ Id = "Office", Block = "Yard", Role = "block", Tier = 1, X = -1578, Z = 857, Yaw = 0, Kits = { { Kit = "TownBlock", X = 0, Z = 0, Variant = "metal", Width = 16, Depth = 10, Storeys = 1, Roof = "mast" } } },
			{ Id = "Crane", Block = "Yard", Role = "landmark", Tier = 1, X = -1668, Z = 700, Yaw = 90, InWater = true, Kits = { { Kit = "GantryCrane", X = 0, Z = 0, Scale = 0.6 } } },
			{ Id = "Tanks", Block = "Yard", Role = "tanks", Tier = 2, X = -1590, Z = 690, Yaw = -180, Kits = { { Kit = "FuelTank", X = -12, Z = 0 }, { Kit = "FuelTank", X = 12, Z = 8 } } },
			{ Id = "Rack", Block = "Yard", Role = "pipes", Tier = 2, X = -1605, Z = 742, Yaw = -180, Kits = { { Kit = "PipeRun", X = 0, Z = 0, Variant = "rack", Length = 40 } } },
			{ Id = "Boxes", Block = "Yard", Role = "containers", Tier = 2, X = -1560, Z = 645, Yaw = -90, Kits = { { Kit = "ContainerStack", X = 0, Z = 0, Count = 2 } } },
			{ Id = "Arc", Block = "Yard", Role = "cover", Tier = 1, X = -1655, Z = 850, Yaw = -180, Kits = { { Kit = "SandbagArc", X = 0, Z = 0 } } },
			{ Id = "Host", Block = "Host", Role = "anchor", Tier = 1, X = -1560, Z = 780, Yaw = -180, Kits = { { Kit = "ActivityHost", X = 0, Z = 0 } } },
		},
		Rocks = {},
		Anchors = {
			-- RigB.CP.* (Booth, Alarm, G1, G2, R1, R2) come from the checkpoint template on cluster "CP"
			{ Id = "RigB.CP.G3", Kind = "npc", X = -1655, Z = 846, Yaw = -90 }, -- behind the sandbag arc
			{ Id = "RigB.Deck.Pier", Kind = "npc", X = -1655, Z = 750, Yaw = -90 }, -- the pier foot, on the sand 4 studs east of the stair landing (MapSetup CoastalOilBravo_RampApproach, x -1689..-1659)
		},
	},
}

return Layouts
