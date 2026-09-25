--!strict
--[[
	Economy tuning. See BALANCE.md for design intent.
	First ~10 minutes feel fast; progression slows after.
]]

local EconomyConfig = {
	StartingCash = 10000, -- v55 restore: healthy start (v20 era used 5000; DS v2 fresh profiles get this)
	StartingGold = 0,
	MinCash = 0,
	MinGold = 0,
	MaxCash = 1_000_000_000,
	MaxGold = 10_000_000,

	-- Passive income: base + sum(structureLevel * rate)
	-- Early-game pacing (first 10 min): start $10k → CC L1 ($1500) immediately →
	-- base $25/tick (~$300/min) + CC $15 → Barracks L1 ($2500) in ~1 min →
	-- then ~$60/tick sustains VehicleDepot / WeaponsFacility without feeling stuck.
	PassiveIncome = {
		TickSeconds = 5,
		BaseCashPerTick = 25, -- alone: ~300/min → Barracks L1 (2500) in ~50s with upgrades help
		-- Per structure level contribution to Cash/tick
		PerLevelRates = {
			CommandCenter = 15,
			Barracks = 20,
			VehicleDepot = 12,
			WeaponsFacility = 10,
			Helipad = 18,
			Dock = 14,
			Airfield = 22,
			DefensiveWalls = 5,
			Watchtowers = 6,
			Radar = 8,
			ResearchLab = 14,
			MissileDefense = 7,
			PowerStation = 16,
			Warehouse = 25,
			SpecialForcesFacility = 20,
		} :: { [string]: number },
	},

	-- Soft caps / multipliers
	PrestigeCashMultiplierPerLevel = 0.10, -- +10% cash gains per prestige (stacking; see PrestigeConfig)
	DailyRewardCashBonus = true,

	-- Capture stipend tuning lives in TerritoryConfig.CaptureStipend
	-- (periodic cash for owned territories / coastal oil).

	-- Contested outpost income: stacks recount from owned territories (stealable).
	-- F3 (owner's 11 features): shown to players as "Empire Tax". Every captured outpost (not the Home Outpost) is one
	-- stack: +MultPerStack on every non-exempt income reason; the player's own Home Outpost (TerritoryConfig.Starter)
	-- adds StarterPct and is never a stack; the total is capped at MaxStacks * MultPerStack (+50 %).
	-- EconomyService.EmpireTaxPct(p) is the whole-number total; it is mirrored (display only, written on change) to
	-- the player attribute Attribute. PersistClaims: saved claims are re-planted on join in any server (Neutral or
	-- NPC-held zones), released when the player leaves, dropped when another online player holds the zone; false =
	-- claims live only in the current server (lane Z switches it on). Toast args: ToastSecured / ToastLost (total %),
	-- ToastStolenFromYou / ToastStealGain (zone name, total %), ToastClaimHeld (zone name, holder name).
	OutpostIncomeBuff = {
		DisplayName = "Empire Tax",
		MultPerStack = 0.10, -- +10% per stack
		MaxStacks = 5, -- cap +50%
		StarterPct = 5, -- F10: the player's own Home Outpost, whole percent (not a stack)
		Attribute = "WE_EmpireTaxPct", -- player attribute, whole percent (0 = chip hidden)
		PersistClaims = true, -- F3: on since lane Z (reversible)
		ToastSecured = "Outpost taken  Empire Tax +%d%%",
		ToastLost = "Outpost lost  Empire Tax +%d%%",
		ToastStolenFromYou = "%s taken  Empire Tax +%d%%",
		ToastStealGain = "Took %s  Empire Tax +%d%%",
		ToastClaimHeld = "%s is held by %s",
		-- Legacy alias kept for older callers
		ToastTemplate = "Outpost secured — +%d%% Income (yours)",
	},

	-- F4 (owner's 11 features): one client-only, owner-only floating label on the nearest own producer (Training Yard,
	-- oil pumps) within RadiusStuds, re-picked ScanHz times a second, pulsing for PulseSeconds on each income tick.
	-- Text sizes are real px (world labels are not UIScaled); MaxDistance in studs (CLAUDE.md: <= 40). Off until
	-- lane Z (the client module ships with it); on since lane Z (reversible).
	ProducerLabels = {
		Enabled = true,
		RadiusStuds = 24,
		ScanHz = 4,
		PulseSeconds = 0.6,
		TextSize = 18,
		SubSize = 14,
		MaxDistance = 24,
	},

	-- PvP ATM raid: touch another player's WE_MoneyCollector to steal PendingCash.
	AtmRaid = {
		Enabled = true,
		StealFraction = 0.10, -- 10% of victim PendingCash
		AtmRaidCooldownSeconds = 60, -- per thief→victim pair
		MaxDistanceStuds = 14, -- server distance check to collector part
		MinStealCash = 1,
		ToastThief = "ATM RAID +$%d (10%%) from %s — 1m cooldown",
		ToastVictim = "ATM RAIDED −10%% by %s (−$%d)",
		ToastCooldown = "ATM raid cooldown — %ds left",
	},
}

return EconomyConfig
