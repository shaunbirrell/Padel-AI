--!strict
--[[ Prestige reset rules. Cash mult at runtime uses EconomyConfig.PrestigeCashMultiplierPerLevel. ]]

local PrestigeConfig = {
	MinLevelToPrestige = 100,
	MaxPrestige = 50,
	CashBonusPerPrestige = 0.05, -- documentation mirror of EconomyConfig
	GoldBonusOnPrestige = 50,
	ResetOnPrestige = {
		Cash = true,
		Level = true,
		XP = true,
		BaseUpgrades = true,
		KeepVehicles = true,
		KeepWeapons = true,
		KeepGold = true,
	},
	StartingCashAfterPrestige = 10000,
}

return PrestigeConfig
