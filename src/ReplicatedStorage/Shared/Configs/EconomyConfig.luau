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
	PrestigeCashMultiplierPerLevel = 0.05, -- +5% cash gains per prestige
	DailyRewardCashBonus = true,
}

return EconomyConfig
