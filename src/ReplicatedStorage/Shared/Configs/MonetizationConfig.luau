--!strict
--[[ Placeholder product IDs = 0 until created in Creator Dashboard ]]

local MonetizationConfig = {
	GamePasses = {
		VIP = { Id = 0, DisplayName = "VIP", CashBonusMult = 0.25, Description = "+25% Cash earnings" },
		DoubleXP = { Id = 0, DisplayName = "Double XP", XPMult = 2, Description = "2x XP" },
		ExtraPlotCosmetic = { Id = 0, DisplayName = "Elite Base Theme", Description = "Cosmetic base theme" },
	},
	DevProducts = {
		CashSmall = { Id = 0, DisplayName = "Cash Pack S", Cash = 10000, Gold = 0 },
		CashMedium = { Id = 0, DisplayName = "Cash Pack M", Cash = 50000, Gold = 0 },
		CashLarge = { Id = 0, DisplayName = "Cash Pack L", Cash = 200000, Gold = 0 },
		GoldSmall = { Id = 0, DisplayName = "Gold Pack S", Cash = 0, Gold = 50 },
		GoldMedium = { Id = 0, DisplayName = "Gold Pack M", Cash = 0, Gold = 200 },
		GoldLarge = { Id = 0, DisplayName = "Gold Pack L", Cash = 0, Gold = 500 },
	},
	-- Loot-box style RNG marked policy-pending — do not enable without compliance review
	LootBoxPolicyPending = true,
}

return MonetizationConfig
