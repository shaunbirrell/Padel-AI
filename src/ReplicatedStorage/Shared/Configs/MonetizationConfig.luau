--!strict
--[[ Placeholder product IDs = 0 until created in Creator Dashboard.
	Grants ONLY via server ProcessReceipt / GamePass ownership checks — never client confirmation. ]]

local MonetizationConfig = {
	GamePasses = {
		VIP = {
			Id = 0,
			DisplayName = "VIP",
			CashBonusMult = 0.25, -- additive +25% cash earnings
			Description = "+25% Cash earnings",
		},
		DoubleCash = {
			Id = 0,
			DisplayName = "2x Cash",
			CashMult = 2, -- multiplicative 2x cash earnings
			Description = "2x Cash earnings",
		},
		DoubleXP = {
			Id = 0,
			DisplayName = "Double XP",
			XPMult = 2,
			Description = "2x XP",
		},
		ExtraPlotCosmetic = {
			Id = 0,
			DisplayName = "Elite Base Theme",
			Description = "Cosmetic base theme",
		},
	},
	DevProducts = {
		CashSmall = { Id = 0, DisplayName = "Cash Pack S", Cash = 10000, Gold = 0 },
		CashMedium = { Id = 0, DisplayName = "Cash Pack M", Cash = 50000, Gold = 0 },
		CashLarge = { Id = 0, DisplayName = "Cash Pack L", Cash = 200000, Gold = 0 },
		GoldSmall = { Id = 0, DisplayName = "Gold Pack S", Cash = 0, Gold = 50 },
		GoldMedium = { Id = 0, DisplayName = "Gold Pack M", Cash = 0, Gold = 200 },
		GoldLarge = { Id = 0, DisplayName = "Gold Pack L", Cash = 0, Gold = 500 },
		-- Placeholder Id=0: ProcessReceipt sets Battle Pass Premium when Id is live; Studio uses admin grantpremium
		PremiumPass = {
			Id = 0,
			DisplayName = "Battle Pass Premium",
			Cash = 0,
			Gold = 0,
			GrantsBattlePassPremium = true,
		},
	},
	-- Loot-box style RNG marked policy-pending — do not enable without compliance review
	LootBoxPolicyPending = true,
	-- Reasons that skip VIP / 2x Cash multipliers (already granted amounts or admin)
	CashMultExemptReasons = {
		devproduct = true,
		admin = true,
		purchase_refund = true,
		prestige = true,
		battlepass = true,
		dismiss_soldiers = true,
		clan_war_win = true,
		clan_war_participate = true,
	},
	XPMultExemptReasons = {
		admin = true,
		battlepass = true,
		achievement = true,
	},
}

return MonetizationConfig
