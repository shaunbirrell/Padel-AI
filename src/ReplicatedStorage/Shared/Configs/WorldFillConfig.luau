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

	ItemSpacing = 1, -- min edge gap to anything already placed (WorldDress.Blocked Spacing)
	MaxPartsFull = 400, -- a build that would pass this stops placing (the budget guard)
	MaxPartsLow = 210,
}

return WorldFillConfig
