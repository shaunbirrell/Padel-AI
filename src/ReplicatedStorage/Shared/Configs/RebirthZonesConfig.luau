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
	-- claude-bud JOB 69: the fallback annex slots (plot-local X / Z / Yaw), tried in this order when a zone's own slot
	-- above is blocked (off the land, a road, water, another plot, a site): every zone on every plot gets a slot.
	-- RebirthZonesConfig.ResolveSlots picks them (one pure resolver: the live service and the sim both use it).
	AnnexAlt = {
		{ X = 218, Z = -80, Yaw = -90 },
		{ X = 218, Z = 190, Yaw = -90 },
		{ X = -218, Z = -80, Yaw = 90 },
		{ X = -218, Z = 190, Yaw = 90 },
		{ X = -218, Z = 10, Yaw = 90 },
		{ X = -218, Z = 100, Yaw = 90 },
		{ X = 218, Z = 10, Yaw = -90 },
		{ X = 218, Z = 100, Yaw = -90 },
		{ X = 290, Z = 100, Yaw = -90 },
		{ X = -290, Z = 100, Yaw = 90 },
		{ X = 290, Z = 10, Yaw = -90 },
		{ X = -290, Z = 10, Yaw = 90 },
		{ X = 290, Z = -80, Yaw = -90 },
		{ X = -290, Z = -80, Yaw = 90 },
		{ X = 290, Z = 190, Yaw = -90 },
		{ X = -290, Z = 190, Yaw = 90 },
		{ X = 360, Z = 100, Yaw = -90 },
		{ X = -360, Z = 100, Yaw = 90 },
		{ X = 360, Z = 10, Yaw = -90 },
		{ X = -360, Z = 10, Yaw = 90 },
		{ X = 360, Z = -80, Yaw = -90 },
		{ X = -360, Z = -80, Yaw = 90 },
		{ X = 360, Z = 190, Yaw = -90 },
		{ X = -360, Z = 190, Yaw = 90 },
	} :: { { X: number, Z: number, Yaw: number } },
	SlotGap = 6, -- studs between two zones' annex + apron boxes
	SlotApron = 26, -- the apron in front of an annex (the kiosk / plaque / run markers stand there)
	-- the zones in the order they claim slots (the Nuclear Silo first: it must always fit)
	SlotOrder = { "StrategicYard", "DroneBay", "WestYard", "WestStrip", "WestFlank", "EastYard", "EastStrip" },
	-- inside-the-base ZONE BOARD spots (plot-local) for a zone with no free slot at all (it can still be bought / upgraded)
	BoardSpots = { { X = -40, Z = 0 }, { X = -40, Z = 10 }, { X = -40, Z = 20 }, { X = -40, Z = 30 }, { X = -40, Z = 40 }, { X = -40, Z = 50 }, { X = -40, Z = 60 } },
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
	--[[ claude-bud JOB 65: the NUKE INSTANT RAID (NukeService.RaidPreview / RaidLaunch). A player with the silo (rebirth
		unlock, built) nukes a rival's HOME BASE: an instant successful raid that moves the target's FULL raidable ATM
		(MoneyCollectorService.GetRaidableBalance, the same number the preview shows) into the attacker's Cash through
		the raid payout path (MoneyCollectorService.NukeRaid: the 1:1 ATM transfer, never multiplied, so no Double
		Weekend / VIP / boost on a transfer). Fairness: the raid checks (ally, new player, shield, low balance), the
		shared protection (spawn / novice shield), never an admin, the JOB 63 same-base cooldown. Saved state: the
		existing NukeSilo warheads + NukeLastLaunch (no new save keys). Owner-first by the ATTACKER. ]]
	NukeRaid = {
		Enabled = true,
		OwnerFirst = true, -- NEW-OWNER-FIRST (claude-bud JOB 65): only Shaun until his phone test
		CooldownSeconds = 1800, -- after a nuke raid (saved: profile.NukeLastLaunch, the silo's one cooldown)
		UsesWarhead = true, -- spends one ready warhead (profile.NukeSilo.Ready)
		Vfx = true, -- the missile + blast on the target base (the MissileStrikeFx packet; light, phone-safe)
		FlightSeconds = 6, -- the missile's flight in the VFX (the cash moves at launch: the raid is instant)
		Targets = { -- who may be nuked (false = never)
			Shielded = false, -- a raid shield (ShieldUntil) / novice shield / spawn protection
			NewPlayers = false, -- inside NewPlayerProtectionSeconds
			Admins = false, -- AdminService.IsAdmin
			Allies = false, -- clan allies (GateDefenseService.IsAlly)
			CampCooldown = false, -- a base on his JOB 63 same-base cooldown
		},
		Text = {
			Launched = "NUKE LAUNCHED: +$%s from %s's ATM",
			Hit = "%s nuked your base: -$%s",
			Cooldown = "Silo cooling down: %s",
			NotReady = "No warhead ready",
			NoSilo = "Build the Nuclear Silo first",
			Blocked = "Can't nuke this base: %s",
		},
	},

	-- the gate rank banners and the title above the head (RebirthConfig.Trims / Titles; RebirthConfig.LiveFor "Trims")
	Rank = {
		BannerZ = 170, -- plot-local, just outside the front wall
		BannerX = 14,
		TitleMaxDistance = 40,
		TitlePx = 15,
	},
}

--[[ claude-bud JOB 46 (2026-10-01, Shaun: "before you buy them it's not clear what you're buying ... the buildings are
	pretty bad ... there should be more to do"). ONE source for what a zone shows and does:
	  * Info[zoneId].Do: what you can do there (the preview card, the locked sign);
	  * Info[zoneId].Activity: the one thing to do in the area once built (RebirthZoneService handles it, server-side):
	      "ship"   a shipment worth Shipment.Minutes of THIS zone's income, once every Shipment.CooldownMinutes;
	      "sweep"  the drones empty your ATM now (Sweep.CooldownSeconds);
	      "drill"  opens the Elite Training panel (EndgameService, the Recruitment Office's list);
	      "strike" opens the missile strike panel;
	      "nuke"   the silo's own NUKE panel (NukeService);
	  * Gains(zoneId, level): the exact gains of one level, read from Zones (never typed twice). ]]
local cfg: any = RebirthZonesConfig
cfg.Info = {
	WestYard = { Do = "Builds tanks for cash. Ship a batch here every 20 min.", Activity = "ship", ActionText = "SHIP TANKS", Theme = "factory" },
	StrategicYard = { Do = "Charges nukes. Launch from the silo console.", Activity = "nuke", ActionText = "NUKE", Theme = "silo" },
	WestStrip = { Do = "Cuts your missile reload. Call a strike from here.", Activity = "strike", ActionText = "CALL STRIKE", Theme = "artillery" },
	DroneBay = { Do = "Drones empty your ATM. Launch a sweep any time.", Activity = "sweep", ActionText = "LAUNCH SWEEP", Theme = "drones" },
	EastYard = { Do = "More soldiers. Drill your army at the yard.", Activity = "drill", ActionText = "DRILL", Theme = "barracks" },
	EastStrip = { Do = "Big cash every tick. Fill a tanker every 20 min.", Activity = "ship", ActionText = "FILL TANKER", Theme = "refinery" },
	WestFlank = { Do = "Longer raid shield. Run a supply drop every 20 min.", Activity = "ship", ActionText = "SUPPLY RUN", Theme = "bunker" },
}
cfg.Shipment = { Minutes = 10, CooldownMinutes = 20 } -- "ship": Minutes of the zone's own flat income (before multipliers)
cfg.Sweep = { CooldownSeconds = 45 }
cfg.Card = { MaxDistance = 18 } -- the preview card shows while the zone's prompt is shown (the console)

--[[ claude-bud JOB 50 (2026-10-01, Shaun: "the rebirth zones still lack detail, quality and any purpose or fun").
	ROOT CAUSE (docs/proof/job50/before.md): every zone's activity was ONE tap at the kiosk for a payout of 10 min of
	that zone's flat income (often a sliver of the player's real income by rebirth 10), with no skill, no goal, no best,
	no status, and nothing logged. Rebuild (owner-first; OFF == the JOB 46 one-tap activities exactly):
	  * Runs: each zone's kiosk starts a short, server-timed run on the apron (steps shown one at a time as prompts the
	    server validates, or an NPC wave); a cooldown per zone (saved), a first-clear bonus, a personal best, an effect
	    tied to the zone (the silo charge, the missile reload, an army buff, a recon pin, a banner stage).
	  * Reward: the ONE formula (cfg.ShipmentCash) x a speed factor (1.0 .. SpeedBonusMax); never below ShipmentCash.
	  * Plaques at each gateway: "UNLOCKED BY <name> · REBIRTH N" + the best time; all 7 zones at L3 = ZONE COMMANDER.
	  * Free for everyone; no Robux anywhere in it. ]]
cfg.Rebuild = {
	Enabled = true,
	OwnerFirst = true, -- NEW-OWNER-FIRST (claude-bud JOB 50): Code Bot flips it after Shaun's phone test
	Activities = true,
	Plaques = true,
	Signs = true,
	Visuals = true,
	Slots = true, -- claude-bud JOB 69: the fallback annex slots (every zone on every plot) + the ZONE BOARD
	HowTo = true, -- claude-bud JOB 69: the how-to-play card before a run + the run tracker / cancel
}
cfg.RunRules = {
	CooldownMinutes = 20, -- per zone, saved (profile.ZoneRunAt)
	SpeedBonusMax = 1.5, -- the fastest run pays this x ShipmentCash (a run at the time limit pays 1.0 x)
	FirstClearMult = 1, -- the first clear of a zone also pays this x ShipmentCash once (profile.ZoneFirstClear)
	ReadyToast = true, -- claude-bud JOB 50 C: one toast when a zone's run comes off cooldown (Rebuild.Signs)
	StatusRefreshSeconds = 30, -- claude-bud JOB 50 C: the gateway plaque's READY / NEXT RUN line (minutes, no per-second churn)
	AnnexSlackStuds = 24, -- a step only counts with him inside the annex + this (no remote triggering)
	StepHold = 0.3, -- seconds to hold a step prompt (fingers)
	StepReach = 9, -- the step prompt's MaxActivationDistance
	-- the base pay is max(ShipmentCash, IncomeMinutes x his passive income per minute): the silo / artillery / drone / bunker
	-- zones have no flat income of their own, and late in the game 10 min of a zone's income is a sliver of his real income
	IncomeMinutes = 2, -- 2 min of his income (x up to 1.5 by speed): 7 zones every 20 min stays well under his passive rate
}
-- step x / dz: annex-local x, and z = D / 2 + dz (the apron in front of the yard, where the JOB 46 dressing stands)
local function step(label: string, x: number, dz: number): any -- claude-bud JOB 50 A: one run step (label, x, dz)
	local t: { any } = {}
	t[1], t[2], t[3] = label, x, dz
	return t
end
cfg.Runs = ({
	WestYard = { Title = "PRODUCTION RUN", Seconds = 60, Effect = "cash",
		Steps = { step("PICK UP CRATE", -22, 4), step("LOAD TRUCK", 22, 10), step("PICK UP CRATE", -22, 4), step("LOAD TRUCK", 22, 10),
			step("PICK UP CRATE", -22, 4), step("LOAD TRUCK", 22, 10) } },
	StrategicYard = { Title = "LAUNCH PREP", Seconds = 30, Effect = "nukecharge", ChargeCutMinutes = 5,
		Steps = { step("ARM 1 OF 3", -22, 5), step("ARM 2 OF 3", 0, 14), step("ARM 3 OF 3", 22, 5) } },
	WestStrip = { Title = "RANGE PRACTICE", Seconds = 45, Effect = "reloadcut", ReloadCutSeconds = 120,
		Steps = { step("HIT TARGET", -30, 6), step("HIT TARGET", -20, 14), step("HIT TARGET", -8, 6), step("HIT TARGET", 8, 14),
			step("HIT TARGET", 20, 6), step("HIT TARGET", 30, 14) } },
	DroneBay = { Title = "RECON FLIGHT", Seconds = 0, Effect = "recon" }, -- instant: the drones mark the nearest raidable rival + sweep
	EastYard = { Title = "DRILL COURSE", Seconds = 45, Par = 30, Effect = "armyboost", BoostMinutes = 10,
		Steps = { step("START", -30, 8), step("CLIMB WALL", -26, 14), step("ROPE FRAME", 27, 11), step("FINISH", 0, 6) } },
	EastStrip = { Title = "PRESSURE VALVES", Seconds = 30, Effect = "cash", Shuffle = true,
		Steps = { step("VALVE", -24, 6), step("VALVE", -12, 12), step("VALVE", 12, 12), step("VALVE", 24, 6) } },
	WestFlank = { Title = "HOLD THE LINE", Seconds = 60, Effect = "banner", Wave = { "Infantry", "Infantry", "Infantry" },
		WaveAt = { { -20, 14 }, { 0, 18 }, { 20, 14 } }, BannerStages = 3 },
} :: any)

function cfg.RebuildLive(userId: any, part: string?): boolean
	local R: any = cfg.Rebuild
	if typeof(R) ~= "table" or (part ~= nil and R[part] ~= true) then
		return false
	end
	return (require(script.Parent.RetentionConfig) :: any).Live(R, userId)
end

-- the run's base pay: max(the ONE ShipmentCash formula, IncomeMinutes x his passive income per minute)
function cfg.RunBase(zoneId: string, level: number, tickSeconds: number, perMin: number?): number
	local inc = math.max(0, tonumber(perMin) or 0) * math.max(0, tonumber(cfg.RunRules.IncomeMinutes) or 0)
	return math.max(cfg.ShipmentCash(zoneId, level, tickSeconds), math.floor(inc))
end

-- the run's cash: RunBase x (1 .. SpeedBonusMax) by the time left (pure; tickSeconds = EconomyConfig PassiveIncome)
function cfg.RunCash(zoneId: string, level: number, tickSeconds: number, secondsUsed: number, limit: number, perMin: number?): number
	local base = cfg.RunBase(zoneId, level, tickSeconds, perMin)
	if limit <= 0 then
		return base
	end
	local left = math.clamp((limit - secondsUsed) / limit, 0, 1)
	return math.floor(base * (1 + (math.max(1, tonumber(cfg.RunRules.SpeedBonusMax) or 1.5) - 1) * left))
end

local function at(list: { number }?, level: number): number
	if list == nil or level < 1 then
		return 0
	end
	return tonumber(list[math.min(level, #list)]) or 0
end

local function commas(n: number): string
	local s = tostring(math.floor(n + 0.5))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- the exact gains of one level (1..MaxLevel), as short lines, from Zones; tickSeconds = EconomyConfig PassiveIncome
function cfg.Gains(zoneId: string, level: number, tickSeconds: number): { string }
	local z = RebirthZonesConfig.Zones[zoneId]
	local out: { string } = {}
	if z == nil or level < 1 then
		return out
	end
	local inc = at(z.IncomePerTick, level)
	if inc > 0 then
		table.insert(out, string.format("+$%s/s income", commas(inc / math.max(1, tickSeconds))))
	end
	local sol = at(z.Soldiers, level)
	if sol > 0 then
		table.insert(out, string.format("+%d soldiers", sol))
	end
	local cut = at(z.MissileReloadCut, level)
	if cut > 0 then
		table.insert(out, string.format("Missile reload -%d s", cut))
	end
	local ac = at(z.AutoCollectSeconds, level)
	if ac > 0 then
		table.insert(out, string.format("Drones empty your ATM every %d s", ac))
	end
	local sh = at(z.RaidShieldBonus, level)
	if sh > 0 then
		table.insert(out, string.format("+%d s raid shield", sh))
	end
	local cap = at(z.SiloCapacity, level)
	if cap > 0 then
		table.insert(out, string.format("Holds %d nuke%s, %d min charge", cap, if cap == 1 then "" else "s", at(z.SiloChargeMinutes, level)))
	end
	return out
end

-- the shipment of an income zone at a level ($), from Shipment.Minutes of its flat income
function cfg.ShipmentCash(zoneId: string, level: number, tickSeconds: number): number
	local z = RebirthZonesConfig.Zones[zoneId]
	local inc = if z then at(z.IncomePerTick, level) else 0
	return math.floor(inc / math.max(1, tickSeconds) * 60 * cfg.Shipment.Minutes)
end

-- claude-bud JOB 50 C: what the run is and what a win gives, one short line (pure; the preview card + the map card)
local EFFECT_TEXT: { [string]: (r: any) -> string } = {
	cash = function(_r) return "cash" end,
	nukecharge = function(r) return string.format("nuke -%d min", tonumber(r.ChargeCutMinutes) or 0) end,
	reloadcut = function(r) return string.format("reload -%d s", tonumber(r.ReloadCutSeconds) or 0) end,
	recon = function(_r) return "marks a rival" end,
	armyboost = function(r) return string.format("par %d s: boost", tonumber(r.Par) or 0) end,
	banner = function(_r) return "cash + banner" end,
}
function cfg.RunLine(zoneId: string): string?
	local r: any = (cfg.Runs :: any)[zoneId]
	if r == nil then
		return nil
	end
	local fx = EFFECT_TEXT[r.Effect]
	local secs = tonumber(r.Seconds) or 0
	return string.format("Run: %s%s%s", r.Title, if secs > 0 then string.format(" · %d s", secs) else "", if fx then " · " .. fx(r) else "")
end

-- claude-bud JOB 50 C: the plaque / map status of a run (pure): READY, IN PROGRESS, or NEXT RUN n MIN (rounded up)
function cfg.RunStatus(cooldownLeft: number, active: boolean): (string, boolean)
	if active then
		return "RUN IN PROGRESS", false
	end
	if cooldownLeft <= 0 then
		return "RUN READY", true
	end
	return string.format("NEXT RUN %d MIN", math.max(1, math.ceil(cooldownLeft / 60))), false
end

--[[ The preview card for a zone at its current level: { Title, Level, Cost (nil at max), Gains (the NEXT level's, or
	the current at max), Do, Action }. Pure (the client card, the locked sign and the tests). ]]
function cfg.CardFor(zoneId: string, level: number, tickSeconds: number): any
	local z = RebirthZonesConfig.Zones[zoneId]
	local info = cfg.Info[zoneId]
	if z == nil or info == nil then
		return nil
	end
	local maxed = level >= RebirthZonesConfig.MaxLevel
	local nextL = if maxed then level else level + 1
	return {
		Title = string.upper(z.Name),
		Level = level,
		NextLevel = nextL,
		Cost = if maxed then nil else math.floor(tonumber(z.Cost[math.min(level + 1, #z.Cost)]) or 0),
		Gains = cfg.Gains(zoneId, nextL, tickSeconds),
		Do = info.Do,
		Action = info.ActionText,
		Maxed = maxed,
		Run = cfg.RunLine(zoneId), -- claude-bud JOB 50 C (shown only while Rebuild.Signs is live)
	}
end


-- ── claude-bud JOB 69: the annex slot resolver (pure) ──────────────────────────────────────────────────────────────
export type Slot = { X: number, Z: number, Yaw: number }

-- the plot-local box (X0, X1, Z0, Z1) of an annex + its apron at slot `s` (W across the front, D deep, yaw a multiple
-- of 90: 0 = front +Z, 90 = +X, -90 = -X, 180 = -Z); pad grows it on every side
function RebirthZonesConfig.SlotBox(s: Slot, W: number, D: number, pad: number?): { number }
	local ap = tonumber((RebirthZonesConfig :: any).SlotApron) or 26
	local g = pad or 0
	local yaw = ((math.floor((tonumber(s.Yaw) or 0) + 0.5) % 360) + 360) % 360
	local hw, back, front = W / 2, D / 2, D / 2 + ap
	if yaw == 0 then -- front +Z
		return { s.X - hw - g, s.X + hw + g, s.Z - back - g, s.Z + front + g }
	elseif yaw == 180 then -- front -Z
		return { s.X - hw - g, s.X + hw + g, s.Z - front - g, s.Z + back + g }
	elseif yaw == 90 then -- front +X
		return { s.X - back - g, s.X + front + g, s.Z - hw - g, s.Z + hw + g }
	end
	return { s.X - front - g, s.X + back + g, s.Z - hw - g, s.Z + hw + g } -- -90: front -X
end

local function boxesOverlap(a: { number }, b: { number }): boolean
	return a[1] < b[2] and b[1] < a[2] and a[3] < b[4] and b[3] < a[4]
end

--[[ Every zone's slot on one plot. isFree(zoneId, slot) is the world check (the live part overlap test in
	RebirthZoneService; the config geometry in the sim). Zones claim slots in SlotOrder: the zone's own slot first, then
	AnnexAlt in order, skipping any slot whose box (+ SlotGap) overlaps a slot already taken on this plot. With
	altsAllowed = false only the zone's own slot is tried (Rebuild OFF = today's placement exactly).
	Returns { [zoneId] = Slot | false } (false = no slot fits: the service puts a ZONE BOARD in the base). ]]
function RebirthZonesConfig.ResolveSlots(isFree: (string, Slot) -> boolean, altsAllowed: boolean?): { [string]: Slot | false }
	local Zc: any = RebirthZonesConfig
	local out: { [string]: Slot | false } = {}
	local taken: { { number } } = {}
	for _, zoneId in ipairs(Zc.SlotOrder) do
		local a = Zc.Annex[zoneId]
		if a then
			local cands: { Slot } = { { X = a.X, Z = a.Z, Yaw = a.Yaw } }
			if altsAllowed ~= false then
				for _, s in ipairs(Zc.AnnexAlt) do
					table.insert(cands, s)
				end
			end
			out[zoneId] = false
			for _, c in ipairs(cands) do
				local box = RebirthZonesConfig.SlotBox(c, a.W, a.D, Zc.SlotGap)
				local clash = false
				for _, t in ipairs(taken) do
					if boxesOverlap(box, t) then
						clash = true
						break
					end
				end
				if not clash and isFree(zoneId, c) then
					out[zoneId] = c
					table.insert(taken, box)
					break
				end
			end
		end
	end
	return out
end
return RebirthZonesConfig
