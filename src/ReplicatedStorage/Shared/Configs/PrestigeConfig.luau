--!strict

local PrestigeConfig = {
	MinLevelToPrestige = 100,
	MaxPrestige = 50,
	CashBonusPerPrestige = 0.05,
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
