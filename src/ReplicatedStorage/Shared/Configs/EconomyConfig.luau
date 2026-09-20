--!strict
--[[
	Economy tuning. See BALANCE.md for design intent.
	First ~10 minutes feel fast; progression slows after.
]]

local EconomyConfig = {
	StartingCash = 5000,
	StartingGold = 0,
	MinCash = 0,
	MinGold = 0,
	MaxCash = 1_000_000_000,
	MaxGold = 10_000_000,

	-- Passive income: base + sum(structureLevel * rate)
	-- Early-game pacing (first 10 min): start $5k → CC L1 ($1500) immediately →
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
	OutpostIncomeBuff = {
		MultPerStack = 0.10, -- +10% per stack
		MaxStacks = 5, -- cap +50%
		ToastSecured = "Outpost secured — +%d%% Income (yours)",
		ToastLost = "Outpost lost — Income buff dropped (stolen)",
		ToastStolenFromYou = "%s stolen by enemy — −Income buff",
		ToastStealGain = "Stole %s — +%d%% Income is now yours",
		-- Legacy alias kept for older callers
		ToastTemplate = "Outpost secured — +%d%% Income (yours)",
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
