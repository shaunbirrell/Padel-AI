--!strict
--[[ Placeholder product IDs = 0 until created in Creator Dashboard.
	Grants ONLY via server ProcessReceipt / GamePass ownership checks — never client confirmation.
	DevProducts may set Entitlements flags (AutoCollect, DoubleCash, etc.) on profile. ]]

local MonetizationConfig = {
	GamePasses = {
		VIP = {
			Id = 0,
			DisplayName = "VIP",
			RobuxPrice = 199,
			CashBonusMult = 0.25, -- additive +25% cash earnings
			Description = "+25% Cash earnings",
		},
		DoubleCash = {
			Id = 0,
			DisplayName = "2x Cash",
			RobuxPrice = 149,
			CashMult = 2, -- multiplicative 2x cash earnings
			Description = "2x Cash earnings",
		},
		DoubleXP = {
			Id = 0,
			DisplayName = "Double XP",
			RobuxPrice = 99,
			XPMult = 2,
			Description = "2x XP",
		},
		ExtraPlotCosmetic = {
			Id = 0,
			DisplayName = "Elite Base Theme",
			RobuxPrice = 79,
			Description = "Cosmetic base theme",
		},
		AutoCollect = {
			Id = 0,
			DisplayName = "Auto Collect",
			RobuxPrice = 99,
			Description = "Auto-claims Money Collector without touch",
		},
	},
	DevProducts = {
		CashSmall = { Id = 0, DisplayName = "Cash Pack S", RobuxPrice = 49, Cash = 10000, Gold = 0 },
		CashMedium = { Id = 0, DisplayName = "Cash Pack M", RobuxPrice = 149, Cash = 50000, Gold = 0 },
		CashLarge = { Id = 0, DisplayName = "Cash Pack L", RobuxPrice = 399, Cash = 200000, Gold = 0 },
		GoldSmall = { Id = 0, DisplayName = "Gold Pack S", RobuxPrice = 49, Cash = 0, Gold = 50 },
		GoldMedium = { Id = 0, DisplayName = "Gold Pack M", RobuxPrice = 149, Cash = 0, Gold = 200 },
		GoldLarge = { Id = 0, DisplayName = "Gold Pack L", RobuxPrice = 349, Cash = 0, Gold = 500 },
		-- Placeholder Id=0: ProcessReceipt sets Battle Pass Premium when Id is live; Studio uses admin grantpremium
		PremiumPass = {
			Id = 0,
			DisplayName = "Battle Pass Premium",
			RobuxPrice = 499,
			Cash = 0,
			Gold = 0,
			GrantsBattlePassPremium = true,
		},
		-- Monetization add-ons (Ids = 0 until Creator Dashboard)
		AutoCollect = {
			Id = 0,
			DisplayName = "Auto Collect",
			RobuxPrice = 99,
			Cash = 0,
			Gold = 0,
			GrantEntitlement = "AutoCollect",
			Description = "Auto-claims Money Collector without touch",
		},
		DoubleCash = {
			Id = 0,
			DisplayName = "2x Money",
			RobuxPrice = 149,
			Cash = 0,
			Gold = 0,
			GrantEntitlement = "DoubleCash",
			Description = "2x Cash earnings (permanent flag)",
		},
		ExtraSoldierSlot = {
			Id = 0,
			DisplayName = "Extra Soldier Slot",
			RobuxPrice = 79,
			Cash = 0,
			Gold = 0,
			GrantEntitlement = "ExtraSoldierSlot",
			Description = "+1 soldier capacity",
		},
		InstantBarracks = {
			Id = 0,
			DisplayName = "Instant Barracks",
			RobuxPrice = 129,
			Cash = 0,
			Gold = 0,
			GrantEntitlement = "InstantBarracks",
			Description = "Unlocks Barracks L1 instantly (server grant)",
		},
		VIPBoost = {
			Id = 0,
			DisplayName = "VIP Boost",
			RobuxPrice = 199,
			Cash = 0,
			Gold = 0,
			GrantEntitlement = "VIP",
			Description = "+25% Cash earnings (permanent flag)",
		},
		StarterBundle = {
			Id = 0,
			DisplayName = "Commander Starter Bundle",
			RobuxPrice = 249,
			Cash = 25000,
			Gold = 25,
			GrantEntitlement = "StarterBundle",
			Description = "Cash + Gold jumpstart pack",
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
		code = true,
		spinner = true,
		supply_drop = true,
		bank_raid = true,
		clan_war_win = true,
		clan_war_participate = true,
		collector = true, -- pending already multiplied at accrue time
	},
	XPMultExemptReasons = {
		admin = true,
		battlepass = true,
		achievement = true,
	},
}

return MonetizationConfig
