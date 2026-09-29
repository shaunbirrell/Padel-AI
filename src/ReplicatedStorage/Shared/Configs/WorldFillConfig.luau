--!strict
--[[
	claude-bud JOB 3 (2026-09-29, owner: "the map feels too empty"): world detail between the bases and round the Central
	Plaza, placed by Server/Modules/WorldFill (called from MapDressing.Dress) into ONE Workspace folder, "WorldFill".

	Everything is data here. World studs, north = -Z. WorldKits kits face local -Z; Yaw in degrees.
	* Roads: flat 14-wide asphalt strips (no collision, top 0.625 like the world roads) from the four side-base gates
	  (P1 / P2 / P5 / P6; P3 / P4 already sit on RoadX0) to RoadZ0, which runs into the Town and the plaza. Built before
	  WorldDress, and reserved in its occupancy, so the travel dressing never lands on them.
	* Bridges: two raised crossings over the P1 and P6 dock channels (the map's "river"), DeckBottomY above the water so
	  boats still pass under; 7 parts each.
	* Fields: small army positions between the bases (Templates), 57 parts Full / 28 Low each, every item a WorldKits kit
	  (<= 8 parts, no scripts); Tier 2 items are Full quality only. Rocks and hills are Terrain (0 parts).
	* Plaza: a light ring just outside the Town footprint (the Town's 512-stud circle has ~22 parts of headroom).
	Every item is re-checked at build time against WorldDress.Blocked (plots, aprons, garage pads, roads, water, captures,
	POIs, events, the bank, the dressing already placed) and skipped (logged) if blocked.

	Planned parts: Full 388, Low 198 (roads 8 + bridges 14 + fields 6 x 57 + plaza 4 x 6; Low: Tier 1 only). With the world
	at ~2,476 Full / ~1,679 Low that stays under WorldConfig.Budgets (2,900 Full / 1,900 Low; hard cap 3,100).
	tools/checks/claude_bud_worldfill.py recomputes this from the table.
	Enabled = false removes the folder (the game as before).
]]

export type FillItem = {
	Kit: string, -- a WorldKits kit, "Rock" (Terrain: Kind + Radius)
	X: number, -- offset from the field centre (turned by the field yaw)
	Z: number,
	Yaw: number?,
	Tier: number, -- 1 = Low + Full, 2 = Full only
	Opts: { [string]: any }?, -- WorldKits KitOpts (Variant, Count, Length, Scale)
	Kind: string?, -- Rock: "outcrop" | "boulders" | "rubble"
	Radius: number?, -- Rock radius
}

local WorldFillConfig = {
	Enabled = true,
	FolderName = "WorldFill",

	Road = {
		Width = 14,
		Color = Color3.fromRGB(50, 52, 48),
		ReserveStep = 12, -- one occupancy disc per this many studs along each strip ...
		ReserveRadius = 13, -- ... of this radius (WorldDress road clearance)
	},
	-- { X0, Z0, X1, Z1 }: axis-aligned centre lines (one of X or Z equal). Each side gate's apron ends 60 studs out
	-- (x = +-580); the spur runs to x = +-400 (outside the Town footprint + its 30 margin), then along Z to RoadZ0.
	Roads = {
		{ Name = "Fill_RoadP1a", X0 = -580, Z0 = -400, X1 = -393, Z1 = -400 },
		{ Name = "Fill_RoadP1b", X0 = -400, Z0 = -407, X1 = -400, Z1 = -7 },
		{ Name = "Fill_RoadP2a", X0 = -580, Z0 = 400, X1 = -393, Z1 = 400 },
		{ Name = "Fill_RoadP2b", X0 = -400, Z0 = 407, X1 = -400, Z1 = 7 },
		{ Name = "Fill_RoadP5a", X0 = 580, Z0 = -400, X1 = 393, Z1 = -400 },
		{ Name = "Fill_RoadP5b", X0 = 400, Z0 = -407, X1 = 400, Z1 = -7 },
		{ Name = "Fill_RoadP6a", X0 = 580, Z0 = 400, X1 = 393, Z1 = 400 },
		{ Name = "Fill_RoadP6b", X0 = 400, Z0 = 407, X1 = 400, Z1 = 7 },
		-- claude-bud JOB 21: the new plots' gates to the nearest +-800 road, between the front wall and the gate pad
		-- (north plots: front edge z -1140, pad z -1078; south plots: front edge z 1120, pad z 1058)
		{ Name = "Fill_RoadP7", X0 = -980, Z0 = -1110, X1 = -807, Z1 = -1110 },
		{ Name = "Fill_RoadP8", X0 = 980, Z0 = -1110, X1 = 807, Z1 = -1110 },
		{ Name = "Fill_RoadP9", X0 = -1000, Z0 = 1090, X1 = -807, Z1 = 1090 },
		{ Name = "Fill_RoadP10", X0 = 560, Z0 = 1090, X1 = 793, Z1 = 1090 },
	} :: { { Name: string, X0: number, Z0: number, X1: number, Z1: number } },

	-- a bridge runs along Z at X, over a channel whose water spans Z0..Z1 (+ 6-stud banks)
	Bridge = {
		Width = 16,
		DeckBottomY = 21.5, -- 20 studs over the water surface (1.5): every boat passes under
		DeckThick = 1.2,
		RampLen = 60,
		RailH = 1.4,
		Color = Color3.fromRGB(120, 116, 106),
	},
	Bridges = {
		{ Name = "Fill_BridgeP1", X = -1050, Z0 = -554, Z1 = -502 }, -- P1 dock channel (z -548..-508)
		{ Name = "Fill_BridgeP6", X = 1300, Z0 = 502, Z1 = 554 }, -- P6 dock channel (z 508..548)
	} :: { { Name: string, X: number, Z0: number, Z1: number } },

	Templates = {
		-- an army position: tower, nest, bunker, wreck, fuel, crates (Tier 1) + trench, wire, ruin, trees (Tier 2)
		Outpost = {
			{ Kit = "Watchtower", X = 0, Z = 0, Yaw = 0, Tier = 1 },
			{ Kit = "SandbagNest", X = 14, Z = -10, Yaw = 0, Tier = 1 },
			{ Kit = "Bunker", X = -16, Z = -12, Yaw = 0, Tier = 1 },
			{ Kit = "Wreck", X = 22, Z = 16, Yaw = 30, Tier = 1, Opts = { Variant = "tank" } },
			{ Kit = "FuelTank", X = -24, Z = 14, Yaw = 0, Tier = 1, Opts = { Scale = 0.8 } },
			{ Kit = "CrateStack", X = -12, Z = 24, Yaw = 15, Tier = 1, Opts = { Count = 3 } },
			{ Kit = "Rock", X = 40, Z = -36, Tier = 1, Kind = "outcrop", Radius = 16 }, -- a low hill
			{ Kit = "Rock", X = -42, Z = 38, Tier = 1, Kind = "boulders", Radius = 10 },
			{ Kit = "SandbagLine", X = 0, Z = -26, Yaw = 0, Tier = 2, Opts = { Length = 30 } },
			{ Kit = "WireFence", X = 2, Z = 38, Yaw = 0, Tier = 2, Opts = { Length = 48 } },
			{ Kit = "Wreck", X = 32, Z = -22, Yaw = -40, Tier = 2, Opts = { Variant = "truck" } },
			{ Kit = "DrumGroup", X = -32, Z = 26, Yaw = 0, Tier = 2, Opts = { Count = 3 } },
			{ Kit = "RuinedHouse", X = -36, Z = -20, Yaw = 90, Tier = 2 },
			{ Kit = "Revetment", X = 26, Z = 2, Yaw = 90, Tier = 2 }, -- trench wall
			{ Kit = "DeadTree", X = 40, Z = 10, Tier = 2 },
			{ Kit = "Joshua", X = -42, Z = 4, Tier = 2 },
			{ Kit = "DeadTree", X = 8, Z = 46, Tier = 2 },
		} :: { FillItem },
		-- the plaza ring: one sandbag arc + tank trap pair per diagonal
		PlazaPost = {
			{ Kit = "SandbagArc", X = 0, Z = 0, Yaw = 0, Tier = 1 },
			{ Kit = "TankTrap", X = 9, Z = 6, Yaw = 20, Tier = 2 },
			{ Kit = "TankTrap", X = -9, Z = 6, Yaw = -20, Tier = 2 },
			{ Kit = "Rock", X = 0, Z = 18, Tier = 1, Kind = "rubble", Radius = 8 },
		} :: { FillItem },
	},

	-- field centres (world) and their yaw; kits face the field's -Z turned by Yaw
	Fields = {
		{ Id = "Q_NW", Template = "Outpost", X = -470, Z = -620, Yaw = 45 },
		{ Id = "Q_NE", Template = "Outpost", X = 470, Z = -620, Yaw = -45 },
		{ Id = "Q_SW", Template = "Outpost", X = -470, Z = 620, Yaw = 135 },
		{ Id = "Q_SE", Template = "Outpost", X = 470, Z = 620, Yaw = -135 },
		{ Id = "West", Template = "Outpost", X = -1150, Z = 400, Yaw = 90 },
		{ Id = "East", Template = "Outpost", X = 1150, Z = -400, Yaw = -90 },
		{ Id = "Plaza_NW", Template = "PlazaPost", X = -300, Z = -420, Yaw = 0 }, -- north of the Town (outside its footprint + 30), clear of RoadX0 and the spurs
		{ Id = "Plaza_NE", Template = "PlazaPost", X = 300, Z = -420, Yaw = 0 },
		{ Id = "Plaza_SW", Template = "PlazaPost", X = -300, Z = 420, Yaw = 180 },
		{ Id = "Plaza_SE", Template = "PlazaPost", X = 300, Z = 420, Yaw = 180 },
	} :: { { Id: string, Template: string, X: number, Z: number, Yaw: number } },

	--[[ claude-bud JOB 18 (2026-09-29, owner: "the map looks empty, especially from the bomber; the towns lack character"):
		WorldFill 2, the same system (WorldFill.Build runs it after the JOB 3 fill, same occupancy, same folder). Live
		for all. Everything is a WorldKits kit (<= 8 parts, no scripts), a Terrain rock (0 parts) or a plain flat part
		(tracks, wires, dunes); every item is re-checked against the shared occupancy (plots, aprons, runways, garage and
		naval pads, captures, spawn / event / airdrop anchors, roads, water, POIs unless it is that POI's own identity
		field) and skipped when blocked. Tier 2 = small clutter: Full quality only, and the client hides it beyond
		QualityConfig.HideTier2BeyondStuds (180) in low quality.
		  * Identity fields: Crossroads Town = a desert MARKET town (stalls, awnings, planters, parked cars, signs),
		    South Port = an INDUSTRIAL port (containers, tanks, trucks), West Depot / East Armory = GARRISON towns
		    (tents, sandbags, towers); a statue or the fountain in each square; made-up shop names only.
		  * Rooftops: town buildings get a water tank / AC unit / antenna on their real roof (raycast).
		  * Countryside: every 300-stud cell of the map with nothing within EmptyRadius gets a themed patch (farm, oil,
		    comms, ruins, tank graveyard, palms, rocks, wadi, checkpoint), picked by region, so from 80+ studs up no
		    empty square is bigger than ~300 x 300.
		  * Power lines along the two highways outside the Town, dirt tracks from the Town to the outer POIs, and a low
		    dune belt at the north / east / west edge in front of the skyline (the south is sea). ]]
	Fill2 = {
		Enabled = true,
		MaxParts2Full = 7000, -- new parts (the owner's cap is ~15k; kept well under for phones)
		MaxParts2Low = 2600,
		Themes = {
			-- a farm: crop patches, 2 silos, the farmhouse, fence, palms, a pickup
			Farm = {
				{ Kit = "CropField", X = -26, Z = -20, Tier = 1, Opts = { Width = 44, Depth = 32 } },
				{ Kit = "CropField", X = 26, Z = -20, Tier = 1, Opts = { Width = 44, Depth = 32, Variant = "dry" } },
				{ Kit = "CropField", X = -26, Z = 20, Tier = 1, Opts = { Width = 44, Depth = 32, Variant = "dry" } },
				{ Kit = "CropField", X = 26, Z = 20, Tier = 1, Opts = { Width = 44, Depth = 32 } },
				{ Kit = "Silo", X = 62, Z = -8, Tier = 1 },
				{ Kit = "Silo", X = 62, Z = 8, Tier = 1 },
				{ Kit = "AdobeHouse", X = -64, Z = 0, Yaw = 90, Tier = 1 },
				{ Kit = "WireFence", X = 0, Z = 44, Tier = 2, Opts = { Length = 64 } },
				{ Kit = "Palm", X = -62, Z = 22, Tier = 2 },
				{ Kit = "Palm", X = -60, Z = -24, Tier = 2 },
				{ Kit = "CivCar", X = -48, Z = 16, Yaw = 30, Tier = 2, Opts = { Variant = "pickup" } },
				{ Kit = "DrumGroup", X = 50, Z = 24, Tier = 2, Opts = { Count = 2 } },
			},
			-- an oil patch: pumpjacks, a pipeline, a tank, a flare
			Oil = {
				{ Kit = "Pumpjack", X = -30, Z = 0, Yaw = 20, Tier = 1 },
				{ Kit = "Pumpjack", X = 4, Z = 22, Yaw = -10, Tier = 1 },
				{ Kit = "Pumpjack", X = 32, Z = -6, Yaw = 60, Tier = 1 },
				{ Kit = "PipeRun", X = 0, Z = -24, Tier = 1, Opts = { Length = 40 } },
				{ Kit = "FuelTank", X = 44, Z = 30, Tier = 1, Opts = { Scale = 0.8 } },
				{ Kit = "FlareStack", X = -52, Z = -30, Tier = 1 },
				{ Kit = "DrumGroup", X = -20, Z = 32, Tier = 2, Opts = { Count = 3 } },
				{ Kit = "Rock", X = 40, Z = -40, Tier = 1, Kind = "rubble", Radius = 8 },
			},
			-- a comms post: a radio mast, bunker, tent, barriers
			Comms = {
				{ Kit = "RadioMast", X = 0, Z = 0, Tier = 1 },
				{ Kit = "Bunker", X = 18, Z = 12, Yaw = 180, Tier = 1 },
				{ Kit = "Tent", X = -16, Z = 14, Yaw = 90, Tier = 2 },
				{ Kit = "Jersey", X = 0, Z = -22, Tier = 2 },
				{ Kit = "Jersey", X = 6, Z = -22, Tier = 2 },
				{ Kit = "SandbagNest", X = -20, Z = -16, Yaw = 200, Tier = 2 },
				{ Kit = "WireFence", X = 0, Z = 30, Tier = 2, Opts = { Length = 48 } },
			},
			-- a ruined hamlet
			Ruins = {
				{ Kit = "RuinedHouse", X = -20, Z = -10, Yaw = 10, Tier = 1 },
				{ Kit = "RuinedHouse", X = 18, Z = 6, Yaw = -80, Tier = 1 },
				{ Kit = "RuinedHouse", X = -4, Z = 28, Yaw = 170, Tier = 1 },
				{ Kit = "Rock", X = 30, Z = -26, Tier = 1, Kind = "rubble", Radius = 9 },
				{ Kit = "Wreck", X = -34, Z = 20, Yaw = 50, Tier = 2, Opts = { Variant = "car" } },
				{ Kit = "DeadTree", X = 34, Z = 30, Tier = 2 },
				{ Kit = "DeadTree", X = -36, Z = -30, Tier = 2 },
			},
			-- a destroyed-tank graveyard
			TankYard = {
				{ Kit = "Wreck", X = -30, Z = -20, Yaw = 20, Tier = 1, Opts = { Variant = "tank" } },
				{ Kit = "Wreck", X = 0, Z = -26, Yaw = -35, Tier = 1, Opts = { Variant = "tank" } },
				{ Kit = "Wreck", X = 30, Z = -10, Yaw = 80, Tier = 1, Opts = { Variant = "tank" } },
				{ Kit = "Wreck", X = -24, Z = 16, Yaw = 140, Tier = 1, Opts = { Variant = "truck" } },
				{ Kit = "Wreck", X = 14, Z = 22, Yaw = -120, Tier = 1, Opts = { Variant = "tank" } },
				{ Kit = "Wreck", X = 40, Z = 30, Yaw = 10, Tier = 2, Opts = { Variant = "gun" } },
				{ Kit = "HeliWreck", X = -46, Z = 36, Yaw = 60, Tier = 2 },
				{ Kit = "Rock", X = 0, Z = 0, Tier = 1, Kind = "rubble", Radius = 10 },
			},
			-- a palm grove round a dry hollow
			Palms = {
				{ Kit = "Palm", X = -18, Z = -12, Tier = 1 },
				{ Kit = "Palm", X = 12, Z = -20, Tier = 1, Opts = { Scale = 1.2 } },
				{ Kit = "Palm", X = 20, Z = 12, Tier = 1 },
				{ Kit = "Palm", X = -10, Z = 20, Tier = 1, Opts = { Scale = 0.9 } },
				{ Kit = "Palm", X = -30, Z = 6, Tier = 2 },
				{ Kit = "DuneGrass", X = 0, Z = 0, Tier = 2 },
				{ Kit = "DuneGrass", X = 28, Z = -4, Tier = 2 },
				{ Kit = "Reeds", X = -4, Z = -30, Tier = 2 },
			},
			-- rock formations: a small hill / cliff and boulders
			Rocks = {
				{ Kit = "Rock", X = 0, Z = 0, Tier = 1, Kind = "outcrop", Radius = 24 },
				{ Kit = "Rock", X = 40, Z = 26, Tier = 1, Kind = "boulders", Radius = 12 },
				{ Kit = "Rock", X = -38, Z = -30, Tier = 1, Kind = "outcrop", Radius = 14 },
				{ Kit = "Joshua", X = 30, Z = -30, Tier = 2 },
				{ Kit = "Saguaro", X = -30, Z = 30, Tier = 2 },
			},
			-- a wadi: a dry stream bed of rubble, reeds and dead trees along local Z
			Wadi = {
				{ Kit = "Rock", X = 0, Z = -45, Tier = 1, Kind = "rubble", Radius = 9 },
				{ Kit = "Rock", X = 6, Z = -15, Tier = 1, Kind = "rubble", Radius = 8 },
				{ Kit = "Rock", X = -4, Z = 15, Tier = 1, Kind = "rubble", Radius = 9 },
				{ Kit = "Rock", X = 4, Z = 45, Tier = 1, Kind = "rubble", Radius = 8 },
				{ Kit = "Reeds", X = 10, Z = 0, Tier = 2 },
				{ Kit = "Reeds", X = -10, Z = 30, Tier = 2 },
				{ Kit = "DeadTree", X = 14, Z = -30, Tier = 2 },
				{ Kit = "Driftwood", X = -8, Z = -2, Tier = 2 },
			},
			-- a road checkpoint
			Checkpoint = {
				{ Kit = "Checkpoint", X = 0, Z = 0, Tier = 1 },
				{ Kit = "Jersey", X = -16, Z = 12, Tier = 2 },
				{ Kit = "Jersey", X = 16, Z = 12, Tier = 2 },
				{ Kit = "Tent", X = 20, Z = -14, Tier = 2 },
				{ Kit = "DirSign", X = -20, Z = -10, Tier = 2 },
			},
			-- Crossroads Town: a market street corner
			Market = {
				{ Kit = "MarketStall", X = -16, Z = 0, Tier = 1 },
				{ Kit = "MarketStall", X = -4, Z = 0, Tier = 1 },
				{ Kit = "MarketStall", X = 8, Z = 0, Tier = 1 },
				{ Kit = "Awning", X = 20, Z = 0, Tier = 1 },
				{ Kit = "Planter", X = -26, Z = 6, Tier = 2 },
				{ Kit = "Planter", X = 28, Z = 6, Tier = 2 },
				{ Kit = "Bench", X = 0, Z = 10, Tier = 2 },
				{ Kit = "Bin", X = -24, Z = -4, Tier = 2 },
				{ Kit = "CivCar", X = 14, Z = 14, Yaw = 90, Tier = 2 },
				{ Kit = "CrateStack", X = -30, Z = -2, Tier = 2, Opts = { Count = 2 } },
			},
			-- South Port: an industrial yard
			PortYard = {
				{ Kit = "ContainerStack", X = -20, Z = 0, Tier = 1, Opts = { Count = 3 } },
				{ Kit = "ContainerStack", X = 4, Z = 0, Tier = 1, Opts = { Count = 2 } },
				{ Kit = "FuelTank", X = 30, Z = -4, Tier = 1 },
				{ Kit = "CivCar", X = -6, Z = 22, Yaw = 90, Tier = 2, Opts = { Variant = "pickup" } },
				{ Kit = "DrumGroup", X = 22, Z = 20, Tier = 2, Opts = { Count = 3 } },
				{ Kit = "CrateStack", X = -32, Z = 20, Tier = 2, Opts = { Count = 3 } },
			},
			-- West Depot / East Armory: garrison lines
			Garrison = {
				{ Kit = "Tent", X = -18, Z = 0, Tier = 1 },
				{ Kit = "Tent", X = -6, Z = 0, Tier = 1 },
				{ Kit = "Tent", X = 6, Z = 0, Tier = 1 },
				{ Kit = "Watchtower", X = 26, Z = -10, Tier = 1 },
				{ Kit = "SandbagLine", X = 0, Z = -16, Tier = 2, Opts = { Length = 30 } },
				{ Kit = "CrateStack", X = -26, Z = 14, Tier = 2, Opts = { Count = 3 } },
				{ Kit = "Jersey", X = 18, Z = 16, Tier = 2 },
			},
			Square = {
				{ Kit = "Statue", X = 0, Z = 0, Tier = 1 },
				{ Kit = "Bench", X = -8, Z = 6, Yaw = 90, Tier = 2 },
				{ Kit = "Bench", X = 8, Z = 6, Yaw = -90, Tier = 2 },
				{ Kit = "Planter", X = 0, Z = -8, Tier = 2 },
			},
		} :: { [string]: { FillItem } },

		-- the towns' identity fields (AllowPOI: inside that POI's own footprint)
		Identity = {
			{ Id = "TownMarketN", Theme = "Market", X = 42, Z = -190, Yaw = 90, AllowPOI = "Town", Sign = "SANDLINE BAZAAR" },
			{ Id = "TownMarketS", Theme = "Market", X = -42, Z = 190, Yaw = -90, AllowPOI = "Town", Sign = "CAFE MIRAGE" },
			{ Id = "TownMarketE", Theme = "Market", X = 190, Z = 42, Yaw = 0, AllowPOI = "Town", Sign = "DUNE MOTORS" },
			{ Id = "TownMarketW", Theme = "Market", X = -190, Z = -42, Yaw = 180, AllowPOI = "Town", Sign = "SUNSTONE SPICE" },
			{ Id = "PortYard1", Theme = "PortYard", X = -150, Z = 1250, Yaw = 0, AllowPOI = "Port", Sign = "SOUTHWHARF FREIGHT" },
			{ Id = "PortYard2", Theme = "PortYard", X = 160, Z = 1250, Yaw = 0, AllowPOI = "Port" },
			{ Id = "PortSquare", Theme = "Square", X = 0, Z = 1170, Yaw = 0, AllowPOI = "Port" },
			{ Id = "DepotLines", Theme = "Garrison", X = -1300, Z = -150, Yaw = 90, AllowPOI = "Depot", Sign = "CAMP KESTREL" },
			{ Id = "DepotSquare", Theme = "Square", X = -1300, Z = 120, Yaw = 0, AllowPOI = "Depot" },
			{ Id = "ArmoryLines", Theme = "Garrison", X = 1300, Z = 150, Yaw = -90, AllowPOI = "Armory", Sign = "CAMP HALCYON" },
			{ Id = "ArmorySquare", Theme = "Square", X = 1300, Z = -120, Yaw = 0, AllowPOI = "Armory" },
		} :: { { Id: string, Theme: string, X: number, Z: number, Yaw: number, AllowPOI: string?, Sign: string? } },
		SignFarms = "RED MESA FARMS", -- the first farm patch carries this sign

		-- the empty-cell generator
		Cells = {
			Size = 300, -- one patch per empty cell of this size ...
			Extent = 1650, -- ... over +-Extent (inside the ring canal)
			EmptyRadius = 130, -- a cell is empty when nothing placed / no POI lies within this of its centre
			Jitter = 50,
			PatchRadius = 70, -- a theme's items lie within this of the patch centre
			-- theme by region (first match: x / z ranges, world studs); "Mix" = a hashed pick from MixThemes
			Regions = {
				{ Theme = "Oil", X0 = 500, X1 = 1700, Z0 = 500, Z1 = 1700 }, -- round the Oil Field (SE)
				{ Theme = "Farm", X0 = -1700, X1 = -900, Z0 = 200, Z1 = 1000 }, -- round the Oasis (W)
				{ Theme = "Ruins", X0 = -1000, X1 = -200, Z0 = -1700, Z1 = -1000 }, -- round the Ruined Village (N)
			},
			MixThemes = { "Farm", "Rocks", "Palms", "TankYard", "Wadi", "Comms", "Ruins", "Oil", "Rocks", "Palms" },
		},

		-- power lines along the highways outside the Town (RoadZ0 along X at z = 0, RoadX0 along Z at x = 0)
		Power = {
			Step = 140,
			Offset = 30, -- from the road centre line
			From = 420, -- |t| >= this (outside the Town)
			To = 1640,
			WireSag = 2,
			WireColor = Color3.fromRGB(40, 40, 42),
		},

		-- dirt tracks from the Town's corners to outer POIs (flat, no collision, pieces skipped over water / plots)
		Tracks = {
			Width = 8,
			Piece = 40,
			Color = Color3.fromRGB(150, 120, 86),
			Lines = {
				{ X0 = -330, Z0 = -330, X1 = -540, Z1 = -1180 }, -- Ruined Village
				{ X0 = -330, Z0 = 330, X1 = -1200, Z1 = 560 }, -- Oasis
				{ X0 = -330, Z0 = 330, X1 = -540, Z1 = 1000 }, -- Crash Site
				{ X0 = 330, Z0 = -330, X1 = 520, Z1 = -1150 }, -- Desert Airstrip
				{ X0 = 330, Z0 = 330, X1 = 900, Z1 = 900 }, -- Oil Field
				{ X0 = -330, Z0 = -330, X1 = -880, Z1 = -880 }, -- Radar Hill
			},
		},

		Rooftops = { Enabled = true, PerBuilding = 2, Kits = { "RoofTank", "ACUnit", "Antenna" } },

		-- the dune belt in front of the skyline (north / east / west; the south is the sea)
		Dunes = {
			Enabled = true,
			RInner = 2000,
			ROuter = 2550,
			PerSide = 8,
			Height = { 28, 70 },
			Color = Color3.fromRGB(196, 164, 118),
			ColorFar = Color3.fromRGB(176, 146, 108),
		},
	},

	ItemSpacing = 1, -- min edge gap to anything already placed (WorldDress.Blocked Spacing)
	MaxPartsFull = 400, -- a build that would pass this stops placing (the budget guard)
	MaxPartsLow = 210,
}

return WorldFillConfig
