--!strict
--[[
	claude-bud JOB 30 (2026-09-30): the full-screen WORLD MAP (Client/Controllers/MapController, Server MapService,
	Shared/Util/MapAreas).
	  * Opened from the MAP rail tile (and M on PC; Missions moved to N).
	  * Shows the Central Plaza / town, every base ("<Name>'s Empire", BaseSignService.TitleFor), the outposts, the
	    bank, airdrops and supply crates, mission / job spots, and the player's own position and facing.
	  * Areas are the real zones: WorldConfig.POIs, joined to the TerritoryConfig outpost inside each one and to the
	    OutpostDefenderConfig garrison of the same Id. Tapping one shows what is there, with GO (pins it).
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
	--[[ Code Bot MAP-REDESIGN (v129): the phone-first look (MapController + Shared/Util/MapLabelLayout).
		Icons are a few fixed sizes (v); labels are title-case pills placed by the collision pass (8 slots round the icon,
		clamped inside the map, lower priority skipped when they still collide; tap a place to see its hidden label, zoom
		in for more). ]]
	Icon = { Area = 22, Site = 20, Base = 16, BaseMine = 22, Bank = 20, Drop = 14, Airdrop = 20, Job = 10, Me = 26, Pin = 28, Badge = 10 },
	LabelTextV = 14, -- PanelShell.Text floors it to 20 v on touch (= 14 real px, HudConfig.Scale.MinTextPx)
	LabelPadX = 7,
	LabelPadY = 3,
	LabelGap = 3, -- icon edge to pill
	LabelPad = 3, -- pill to pill
	LabelIconPad = 2, -- pill to any icon
	LabelEdge = 4, -- pill to the map edge
	LabelMaxSlide = 40, -- a clamp may slide a pill this far along the edge, no further (it stays next to its icon)
	MyBaseLabel = "Your Base",
	IconTapPx = 24, -- real px: a tap this close to an icon picks it (a 48 px touch circle)
	CompassV = 56,
	-- 0 = your base, 1 = towns / sites / forts, 2 = outposts / camps / rigs, 3 = depots + rig shore bases (zoom 1 shows <= 2)
	LabelPriority = {
		town = 1, fort = 1, port = 1, airstrip = 1, oil = 1, radar = 1, signal = 1, armory = 1, site = 1,
		ruins = 2, camp = 2, crash = 2, oasis = 2, rig = 2, outpost = 2,
		depot = 3, site_depot = 3, rigshore = 3,
	} :: { [string]: number },
	-- inside one priority: who gets the first pick of the space (town, the forts, the port ...)
	LabelRank = { town = 1, fort = 2, port = 3, airstrip = 4, armory = 5, oil = 6, signal = 7, radar = 8, site = 9 } :: { [string]: number },
	ZoomLevels = { 1, 2 },
	ZoomMaxPriority = { 2, 3 }, -- per zoom level: the lowest-priority label kind shown
	-- short map names (the card shows the full name)
	LabelShort = {
		Town = "Crossroads", Armory = "Armory", Depot = "West Depot", Signal = "North Ridge", Port = "South Port", OilField = "Oil Field",
		Radar = "Radar Hill", FortI = "Fort Ironclad", FortS = "Fort Sandhold", RigA = "Alpha Shore", RigB = "Bravo Shore",
		Airstrip = "Airstrip", Ruins = "Ruined Village", Quarry = "Quarry Camp", CoastalOilAlpha = "Rig Alpha",
		CoastalOilBravo = "Rig Bravo", Kestrel = "Kestrel Depot", PumpSeven = "Pump Station 7", DryWell = "Dry Well",
		Overwatch = "Overwatch Ridge", CampViper = "Camp Viper", Hawk = "Hawk Checkpoint", Anvil = "Anvil Scrapyard",
	} :: { [string]: string },
	-- icon family per POI kind (colour + inner shape: MapController.Groups)
	KindGroup = {
		town = "Town", fort = "Military", armory = "Military", radar = "Military", signal = "Military", airstrip = "Military",
		outpost = "Military", port = "Industry", oil = "Industry", depot = "Industry", rigshore = "Industry", rig = "Industry",
		ruins = "Wilds", camp = "Wilds", crash = "Wilds", oasis = "Wilds",
	} :: { [string]: string },
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
		Site = Color3.fromRGB(196, 66, 58), -- claude-bud JOB 31: the named sites (WorldSitesConfig); MAP-REDESIGN: brick red
		-- Code Bot MAP-REDESIGN: the terrain and icon families
		SandLight = Color3.fromRGB(222, 196, 140),
		SandDark = Color3.fromRGB(170, 138, 88),
		SeaLight = Color3.fromRGB(34, 74, 92),
		SeaDark = Color3.fromRGB(12, 30, 42),
		Road = Color3.fromRGB(92, 72, 50),
		Grid = Color3.fromRGB(70, 54, 34),
		Zone = Color3.fromRGB(140, 110, 70),
		Town = Color3.fromRGB(248, 214, 96),
		Military = Color3.fromRGB(86, 132, 186),
		Industry = Color3.fromRGB(230, 126, 40),
		Wilds = Color3.fromRGB(120, 150, 70),
		Pill = Color3.fromRGB(12, 14, 12),
		Card = Color3.fromRGB(20, 24, 20),
	},
	-- claude-bud JOB 31: what each site kind is (the card's first line)
	SiteKindInfo = {
		camp = "Enemy camp",
		village = "Ruined village",
		oil = "Pump station",
		depot = "Supply depot",
		checkpoint = "Road checkpoint",
		overwatch = "Sniper ridge",
		tankyard = "Tank scrapyard",
	} :: { [string]: string },
	--[[ Code Bot v127/v128: fast travel is REMOVED at the owner's request (Shaun wants tap-to-pin only, so players see where
		to go and get there themselves). There is no remote, no server handler and no TRAVEL button; the flag stays false
		and codebot_v127/v128.py fails the build if any of that comes back. Do not re-add fast travel. ]]
	FastTravelEnabled = false,
}

return MapConfig
