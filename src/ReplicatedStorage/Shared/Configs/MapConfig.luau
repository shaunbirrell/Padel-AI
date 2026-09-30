--!strict
--[[
	claude-bud JOB 30 (2026-09-30): the full-screen WORLD MAP (Client/Controllers/MapController, Server MapService,
	Shared/Util/MapAreas).
	  * Opened from the MAP rail tile (and M on PC; Missions moved to N).
	  * Shows the Central Plaza / town, every base ("<Name>'s Empire", BaseSignService.TitleFor), the outposts, the
	    bank, airdrops and supply crates, mission / job spots, and the player's own position and facing.
	  * Areas are the real zones: WorldConfig.POIs, joined to the TerritoryConfig outpost inside each one and to the
	    OutpostDefenderConfig garrison of the same Id. Tapping one shows what is there, with GO (and TRAVEL when it is
	    unlocked).
	  * Tapping anywhere else drops a PIN on the ONE objective marker (ObjectiveMarker.ShowWith { Pin = true }): the
	    same GO line and compass as missions and airdrops. Tapping the pin again, the CLEAR PIN button, or arriving
	    (PinArriveStuds) removes it.
	  * Performance: the area layer is built once and cached; markers refresh RefreshSeconds (2x a second) and only
	    while the map is open; nothing runs while it is closed.
	Kill switch: Enabled = false (no tile, no key, no server feed). OwnerFirst as RetentionConfig.Live.
]]

local MapConfig = {
	Enabled = true,
	OwnerFirst = true, -- only UserId 470626172 (+ Studio test players) until Code Bot sets false = everyone
	-- the world square the map shows (studs; north = -Z is up). Dry land is x +-1760, z -1760..1490 (WorldConfig).
	Extent = { X0 = -2000, X1 = 2000, Z0 = -2000, Z1 = 2000 },
	RefreshSeconds = 0.5, -- markers (and the server feed) at most 2x a second, only while open
	PinArriveStuds = 15,
	PinTimeoutSeconds = 1800,
	PinLabel = "PIN",
	PinTapPx = 26, -- real px: a tap this close to the pin removes it
	-- short label shown on the map for these area Ids (the rest show on tap; <= 10 labels keep a phone map readable)
	LabelIds = { Town = true, Depot = true, Armory = true, Signal = true, Port = true, OilField = true, Radar = true, FortI = true, FortS = true, Airstrip = true } :: { [string]: boolean },
	-- what each POI kind is, in 2-4 words (the card's first line)
	KindInfo = {
		town = "City and Central Plaza",
		depot = "Supply depot",
		armory = "Armory compound",
		signal = "Radio outpost",
		port = "Harbour and docks",
		oil = "Oil wells",
		radar = "Radar station",
		fort = "Fortress approach",
		rigshore = "Oil rig shore base",
		airstrip = "Desert airfield",
		ruins = "Ruined village",
		camp = "Bandit camp",
		crash = "Crash site",
		oasis = "Desert oasis",
		rig = "Offshore oil rig",
	} :: { [string]: string },
	EnemyText = { Easy = "Enemies: light guard", Medium = "Enemies: armed guard", Hard = "Enemies: heavy guard" } :: { [string]: string },
	Colors = {
		Background = Color3.fromRGB(14, 17, 14),
		Sea = Color3.fromRGB(18, 34, 44),
		Land = Color3.fromRGB(58, 52, 38),
		Area = Color3.fromRGB(120, 110, 80),
		Outpost = Color3.fromRGB(200, 170, 70),
		OutpostMine = Color3.fromRGB(80, 200, 110),
		OutpostEnemy = Color3.fromRGB(210, 80, 60),
		Base = Color3.fromRGB(150, 150, 150),
		BaseMine = Color3.fromRGB(80, 200, 110),
		Drop = Color3.fromRGB(80, 170, 255),
		Job = Color3.fromRGB(255, 150, 32),
		Bank = Color3.fromRGB(255, 214, 72),
		Pin = Color3.fromRGB(255, 205, 60),
		Me = Color3.fromRGB(255, 255, 255),
		Text = Color3.fromRGB(230, 225, 205),
		Muted = Color3.fromRGB(160, 155, 135),
		Accent = Color3.fromRGB(235, 195, 90),
	},
	--[[ Fast travel (server MapService): to your own base or an outpost you (or your clan) hold, never into a contested
		one, never while hurt (the server's damage lock), never from a seat, once per CooldownSeconds. ]]
	FastTravel = {
		Enabled = true,
		OwnerFirst = true, -- only UserId 470626172 (+ Studio test players) until Code Bot sets false = everyone
		CooldownSeconds = 120,
	},
}

return MapConfig
