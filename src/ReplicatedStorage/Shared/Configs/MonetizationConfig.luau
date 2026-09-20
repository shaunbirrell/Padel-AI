--!strict
--[[ Live Robux product IDs (Creator Dashboard / Open Cloud). Id=0 = stub / hidden duplicate.
	Grants ONLY via server ProcessReceipt / GamePass ownership checks — never client confirmation.
	DevProducts AutoCollect/DoubleCash/VIPBoost are HideFromShop (GamePasses cover them). ]]

local MonetizationConfig = {
	GamePasses = {
		VIP = {
			Id = 1985475542,
			DisplayName = "VIP",
			RobuxPrice = 199,
			CashBonusMult = 0.25, -- additive +25% cash earnings
			Description = "+25% Cash earnings",
		},
		DoubleCash = {
			Id = 1982865711,
			DisplayName = "2x Cash",
			RobuxPrice = 149,
			CashMult = 2, -- multiplicative 2x cash earnings
			Description = "2x Cash earnings",
		},
		DoubleXP = {
			Id = 1982487698,
			DisplayName = "Double XP",
			RobuxPrice = 99,
			XPMult = 2,
			Description = "2x XP",
		},
		ExtraPlotCosmetic = {
			Id = 1983357731,
			DisplayName = "Elite Base Theme",
			RobuxPrice = 79,
			Description = "Cosmetic base theme",
		},
		AutoCollect = {
			Id = 1985115501,
			DisplayName = "Auto Collect",
			RobuxPrice = 99,
			Description = "Auto-claims Money Collector without touch",
		},
	},
	DevProducts = {
		CashSmall = { Id = 3713838744, DisplayName = "Cash Pack S", RobuxPrice = 49, Cash = 10000, Gold = 0 },
		CashMedium = { Id = 3713838815, DisplayName = "Cash Pack M", RobuxPrice = 149, Cash = 50000, Gold = 0 },
		CashLarge = { Id = 3713838888, DisplayName = "Cash Pack L", RobuxPrice = 399, Cash = 200000, Gold = 0 },
		CashMega = { Id = 3713838952, DisplayName = "Cash Pack Mega", RobuxPrice = 799, Cash = 2000000, Gold = 0 },
		GoldSmall = { Id = 3713839003, DisplayName = "Gold Pack S", RobuxPrice = 49, Cash = 0, Gold = 50 },
		GoldMedium = { Id = 3713839048, DisplayName = "Gold Pack M", RobuxPrice = 149, Cash = 0, Gold = 200 },
		GoldLarge = { Id = 3713839090, DisplayName = "Gold Pack L", RobuxPrice = 349, Cash = 0, Gold = 500 },
		-- Placeholder Id=0: ProcessReceipt sets Battle Pass Premium when Id is live; Studio uses admin grantpremium
		PremiumPass = {
			Id = 3713839151,
			DisplayName = "Battle Pass Premium",
			RobuxPrice = 499,
			Cash = 0,
			Gold = 0,
			GrantsBattlePassPremium = true,
		},
		-- Monetization add-ons (Ids = 0 until Creator Dashboard)
		-- Covered by GamePass AutoCollect — keep stub for ProcessReceipt compat; hidden in shop
		AutoCollect = {
			Id = 0,
			DisplayName = "Auto Collect",
			RobuxPrice = 99,
			Cash = 0,
			Gold = 0,
			GrantEntitlement = "AutoCollect",
			HideFromShop = true,
			Description = "Auto-claims Money Collector without touch",
		},
		-- Covered by GamePass DoubleCash — hidden in shop
		DoubleCash = {
			Id = 0,
			DisplayName = "2x Money",
			RobuxPrice = 149,
			Cash = 0,
			Gold = 0,
			GrantEntitlement = "DoubleCash",
			HideFromShop = true,
			Description = "2x Cash earnings (permanent flag)",
		},
		ExtraSoldierSlot = {
			Id = 3713839210,
			DisplayName = "Extra Soldier Slot",
			RobuxPrice = 79,
			Cash = 0,
			Gold = 0,
			GrantEntitlement = "ExtraSoldierSlot",
			Description = "+1 soldier capacity",
		},
		InstantBarracks = {
			Id = 3713839278,
			DisplayName = "Instant Barracks",
			RobuxPrice = 129,
			Cash = 0,
			Gold = 0,
			GrantEntitlement = "InstantBarracks",
			Description = "Unlocks Barracks L1 instantly (server grant)",
		},
		-- Covered by GamePass VIP — hidden in shop
		VIPBoost = {
			Id = 0,
			DisplayName = "VIP Boost",
			RobuxPrice = 199,
			Cash = 0,
			Gold = 0,
			GrantEntitlement = "VIP",
			HideFromShop = true,
			Description = "+25% Cash earnings (permanent flag)",
		},
		SpeedBoost = {
			Id = 3713839342,
			DisplayName = "Speed Boost",
			RobuxPrice = 99,
			Cash = 0,
			Gold = 0,
			GrantEntitlement = "SpeedBoost",
			Description = "Permanent move-speed boost",
		},
		-- Cosmetic oil pump gold dress — Id=0: MapSetup hides GoldenPump pad until Id set;
		-- ProcessReceipt + GrantEntitlement ready when Creator Dashboard Id is pasted
		GoldenPumpjack = {
			Id = 0,
			DisplayName = "Golden Pumpjack",
			RobuxPrice = 49,
			Cash = 0,
			Gold = 0,
			GrantEntitlement = "GoldenPumpjack",
			HideFromShop = true,
			Description = "Gold-dress plot oil pumps (pad hidden while Id=0)",
		},
		StarterBundle = {
			Id = 3713839505,
			DisplayName = "Commander Starter Bundle",
			RobuxPrice = 249,
			Cash = 25000,
			Gold = 25,
			GrantEntitlement = "StarterBundle",
			Description = "Cash + Gold jumpstart pack",
		},
	},
	-- Loot-box style RNG marked policy-pending — do not enable without compliance review
	-- v30: PvP death toast — DoubleCash GamePass + SpeedBoost DevProduct (live Ids)
	DeathShopOffers = { "DoubleCash", "SpeedBoost" },
	-- v32: one-shot soft offer on first join / low cash (server marks StarterBundleOffered)
	StarterBundleOffer = {
		DelaySeconds = 8,
		CashBelow = 12000, -- StartingCash*2 + buffer
		NewProfileMaxAgeSeconds = 600, -- FirstJoin→LastJoin span treats as new
	},
	-- v33: one-shot soft offer after first manual ATM collect (server marks AutoCollectOffered)
	AutoCollectOffer = {
		DelaySeconds = 1.2,
	},
	-- v34: one-shot DoubleCash soft offer after meaningful ATM collect (not spammy)
	DoubleCashOffer = {
		DelaySeconds = 1.8,
		MinCollectCash = 2500, -- only after a solid collect
	},
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
		manual_dropper = true, -- fixed click awards stay $10–25
		atm_raid = true,
		plot_oil = true, -- plot pump PendingCash via AccruePendingCash
	},
	XPMultExemptReasons = {
		admin = true,
		battlepass = true,
		achievement = true,
	},
}

return MonetizationConfig
