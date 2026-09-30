--!strict
--[[
	claude-bud JOB 33 (2026-09-30): the 7 REBIRTH ZONES (RebirthConfig.Zones: which rebirth opens which) as add-on
	complexes ATTACHED to the base. The 320 x 320 plot is full (buildings, runway, helipad, dock), so each zone is an
	annex yard just outside the plot, on the side its name says:
	  * West Yard / West Battery / West Flank on the west side (-X);
	  * East Yard / Refinery Row on the east side (+X);
	  * the Strategic Yard (the silo) and the Drone Bay at the rear (-Z).
	Each annex front faces the base.

	Server RebirthZoneService builds them for the plot's owner (Modules/RebirthZoneBuilder) when his base is ready,
	after a rebirth and after an upgrade:
	  * a zone he has not reached shows a fence and a sign "Unlocks at Rebirth N";
	  * a reached zone shows a foundation with a BUILD console;
	  * levels 1-3 visibly grow the complex (more halls, guns, drones, towers, storeys). A maxed rebirth base reads bigger
	    and better from a distance.
	Every building earns or does something real (Effects, server-side). The upgrades are paid in Cash at the console
	(SpendCash, reason "rebirth_zone_<Id>"), are kept through rebirths (profile.RebirthZones) and are never Robux.

	Placement: at plot-ready each annex footprint is checked once:
	  * procedural decor (travel dressing / world fill clusters) inside it is cleared;
	  * a road, POI, site, building or anything else inside it blocks that one annex on that plot (logged), so it never
	    lands on top of something;
	  * off dry land = blocked.

	Kill switch: RebirthConfig.Live.Parts.Zones / RebirthConfig.ZonesLive (and the owner-first gate).
]]

export type Annex = { X: number, Z: number, W: number, D: number, Yaw: number }
export type ZoneLevels = {
	Name: string, -- the building
	Short: string, -- one line for the console (what it does)
	Cost: { number }, -- Cash per level 1..3
	IncomePerTick: { number }?, -- + Cash per passive tick (before the cash multiplier), per level
	Soldiers: { number }?, -- + army cap, per level
	MissileReloadCut: { number }?, -- seconds off the missile strike reload, per level
	AutoCollectSeconds: { number }?, -- the drones empty your ATM this often, per level
	RaidShieldBonus: { number }?, -- seconds added to your raid shield after an ATM raid, per level
	SiloCapacity: { number }?, -- warheads held, per level
	SiloChargeMinutes: { number }?, -- minutes to charge one warhead, per level
}

local RebirthZonesConfig = {
	MaxLevel = 3,
	FolderName = "WE_RebirthZones",
	-- plot-local annex frames (studs; the plot edge is +-160). Yaw = the direction the annex front faces (BaseLayout
	-- convention: 0 = +Z, 90 = +X, -90 = -X)
	Annex = {
		WestYard = { X = -218, Z = 100, W = 74, D = 60, Yaw = 90 },
		WestStrip = { X = -218, Z = 10, W = 74, D = 60, Yaw = 90 },
		WestFlank = { X = -218, Z = -80, W = 74, D = 60, Yaw = 90 },
		EastYard = { X = 218, Z = 100, W = 74, D = 60, Yaw = -90 },
		EastStrip = { X = 218, Z = 10, W = 74, D = 60, Yaw = -90 },
		StrategicYard = { X = -50, Z = -218, W = 74, D = 60, Yaw = 0 },
		DroneBay = { X = 60, Z = -218, W = 74, D = 60, Yaw = 0 },
	} :: { [string]: Annex },
	-- procedural decor the placement check may clear (WE_Cluster sources); anything else blocks the annex
	ClearableSources = { rhythm = true, junction = true, shore = true, scatter = true, bay = true, fill = true, fill2 = true } :: { [string]: boolean },

	Zones = {
		WestYard = { Name = "Tank Factory", Short = "Cash every tick", Cost = { 60000, 180000, 500000 }, IncomePerTick = { 150, 350, 700 } },
		StrategicYard = { Name = "Nuclear Silo", Short = "Charges a nuke", Cost = { 250000, 750000, 2000000 }, SiloCapacity = { 1, 2, 3 }, SiloChargeMinutes = { 60, 45, 30 } },
		WestStrip = { Name = "Artillery Battery", Short = "Faster missile reload", Cost = { 90000, 270000, 700000 }, IncomePerTick = { 60, 150, 300 }, MissileReloadCut = { 90, 180, 270 } },
		DroneBay = { Name = "Drone Hangar", Short = "Drones empty your ATM", Cost = { 110000, 330000, 850000 }, IncomePerTick = { 40, 100, 200 }, AutoCollectSeconds = { 60, 40, 25 } },
		EastYard = { Name = "Elite Barracks", Short = "+5 soldiers a level", Cost = { 130000, 390000, 1000000 }, IncomePerTick = { 50, 120, 250 }, Soldiers = { 5, 10, 15 } },
		EastStrip = { Name = "Oil Refinery", Short = "Big Cash every tick", Cost = { 150000, 450000, 1200000 }, IncomePerTick = { 250, 600, 1200 } },
		WestFlank = { Name = "Bunker Complex", Short = "Longer raid shield", Cost = { 200000, 600000, 1500000 }, IncomePerTick = { 80, 200, 400 }, RaidShieldBonus = { 120, 240, 360 } },
	} :: { [string]: ZoneLevels },

	--[[ The nuke (NukeService; numbers tied to NukeConfig where it has them: Kinds.Nuke.Radius, CountdownSeconds,
		Rules.NewPlayerProtection). Launch from the silo console at the Central Plaza, an outpost or an enemy site (never
		within BaseClearStuds of any base: bases are never nuked). Siren + countdown for everyone, then one blast
		through CombatService.ApplyRadiusDamage (THE shared PvP rule: novice shields, spawn protection, clan allies and
		pvp-off all respected; NPCs hit). Long cooldowns. Rush: finish the current warhead for Cash. ]]
	Nuke = {
		Damage = 260, -- at the centre; MinMult at the edge
		MinMult = 0.15,
		PlayerCooldownSeconds = 1800,
		ServerCooldownSeconds = 300,
		BaseClearStuds = 360,
		RushCashPerMinute = 4000,
		SirenSoundId = "", -- a Roblox-uploaded siren sound id (owner fills it; "" = the visual siren only)
		MaxTargets = 10,
	},

	-- the gate rank banners and the title above the head (RebirthConfig.Trims / Titles; RebirthConfig.LiveFor "Trims")
	Rank = {
		BannerZ = 170, -- plot-local, just outside the front wall
		BannerX = 14,
		TitleMaxDistance = 40,
		TitlePx = 15,
	},
}

return RebirthZonesConfig
