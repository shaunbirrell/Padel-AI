--!strict
--[[ Live Robux product IDs (Creator Dashboard / Open Cloud). Id=0 = stub / hidden duplicate.
	Grants ONLY via server ProcessReceipt / GamePass ownership checks — never client confirmation.
	DevProducts AutoCollect/DoubleCash/VIPBoost are HideFromShop (GamePasses cover them).
	v69: OneTime = true marks a DevProduct whose grant is a boolean (buying it twice adds nothing). The Shop
	shows OWNED instead of prompting once the server reports it owned (player attribute WE_Ent_<key>, see
	ShopController). ProcessReceipt still grants any receipt Roblox delivers. HideFromShop on a GamePass keeps
	it out of the Shop list.
	v71 money (M0): HideFromShop also stops selling dead items (Gold packs: Gold has no use yet; Instant Barracks).
	Their Ids stay unchanged (never set a live Id to 0). A receipt for a product Id that is not listed here is NOT
	acknowledged (MonetizationService J2): paste new Ids with tools/wire-monetization-ids.py, publish, then run
	Migrate to Latest Update.
	v71 money (M1): receipt fields for the grant path (MonetizationService.ProcessReceipt, all applied before the
	receipt is marked and saved; see the field notes below):
	  GrantEntitlement = "Key"          one boolean entitlement (profile.Entitlements[Key])
	  GrantEntitlements = { "A", "B" }  a list of them (merged with GrantEntitlement, each granted once)
	  StarterFallbackCash = N           + N Cash when the buyer already owns Auto Collect (decided before any grant)
	  GrantNukes = N (etc.)             counter grants: only the fields whitelisted in CounterGrants below
	  Feature = "Name"                  the SKU belongs to a feature that is not live yet (M3: shown only when the
	                                    ReplicatedStorage attribute WE_Feature_<Name> is true and Id ~= 0). Until
	                                    M3 ships, every Feature SKU also carries HideFromShop = true.
	New SKUs stay Id = 0 until the owner creates them; game passes are created with Item for Sale OFF (J3). ]]

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
		-- v69: HideFromShop — no code applies this theme yet, so it is not sold in the in-game Shop.
		-- Id kept unchanged (existing owners keep the pass); remove HideFromShop once the theme ships.
		ExtraPlotCosmetic = {
			Id = 1983357731,
			DisplayName = "Elite Base Theme",
			RobuxPrice = 79,
			Description = "Cosmetic base theme",
			HideFromShop = true,
		},
		AutoCollect = {
			Id = 1985115501,
			DisplayName = "Auto Collect",
			RobuxPrice = 99,
			Description = "Auto-claims Money Collector without touch",
		},
		-- v71 money (M1): premium Robux vehicles (plan §2.2, PremiumVehicleConfig.Lineup PassKey). Id = 0 until the
		-- owner creates each pass (Item for Sale OFF until the M6 publish, J3). HideFromShop until M3's feature gate
		-- (WE_Feature_PremiumVehicles); the generic Shop pass loop must skip VehicleIds passes (M3/M6 Garage sells
		-- them). BundlePassKeys = other passes that also unlock the car; HideIfOwnsAny hides the bundle row.
		PV_Razorfang = {
			Id = 0,
			DisplayName = "Razorfang GT Interceptor",
			RobuxPrice = 199,
			VehicleIds = { "PremiumRazorfang" },
			BundlePassKeys = { "PV_MotorPool" },
			Feature = "PremiumVehicles",
			HideFromShop = true,
			Description = "Premium armored car with twin hood machine guns",
		},
		PV_Bastion = {
			Id = 0,
			DisplayName = "Bastion Gun Truck",
			RobuxPrice = 399,
			VehicleIds = { "PremiumBastion" },
			BundlePassKeys = { "PV_MotorPool" },
			Feature = "PremiumVehicles",
			HideFromShop = true,
			Description = "Premium gun truck that carries up to 9 soldiers", -- J22
		},
		PV_Warlord = {
			Id = 0,
			DisplayName = "Warlord Siege Tank",
			RobuxPrice = 799,
			VehicleIds = { "PremiumWarlord" },
			BundlePassKeys = { "PV_MotorPool" },
			Feature = "PremiumVehicles",
			HideFromShop = true,
			Description = "Premium heavy tank with a siege cannon",
		},
		PV_MotorPool = {
			Id = 0,
			DisplayName = "Premium Motor Pool",
			RobuxPrice = 1099,
			VehicleIds = { "PremiumRazorfang", "PremiumBastion", "PremiumWarlord" },
			HideIfOwnsAny = { "PV_Razorfang", "PV_Bastion", "PV_Warlord" }, -- J3: single-car owners buy the others alone
			Feature = "PremiumVehicles",
			HideFromShop = true,
			Description = "All 3 premium ground vehicles",
		},
		PV_Stormwing = { -- M6b (after helicopter flight is verified on a phone)
			Id = 0,
			DisplayName = "Stormwing Gunship",
			RobuxPrice = 999,
			VehicleIds = { "PremiumStormwing" },
			Feature = "PremiumVehicles",
			HideFromShop = true,
			Description = "Premium attack helicopter",
		},
		PV_Tidebreaker = { -- M6b (after waterways / boats)
			Id = 0,
			DisplayName = "Tidebreaker Assault Boat",
			RobuxPrice = 299,
			VehicleIds = { "PremiumTidebreaker" },
			Feature = "PremiumVehicles",
			HideFromShop = true,
			Description = "Premium assault boat",
		},
		-- v71 money (M1): Rebirth Boost (J13: +15% Cash per Rebirth instead of +10%, 1.5x starting Cash; no Gold x2).
		-- RebirthConfig.Boost.GamePassKey. Id = 0 until created (OFF sale until the M7b/M7d publish).
		RebirthBoost = {
			Id = 0,
			DisplayName = "Rebirth Boost",
			RobuxPrice = 199,
			Feature = "Rebirth",
			HideFromShop = true,
			Description = "+15% Cash per Rebirth and 1.5x starting Cash",
		},
	},
	DevProducts = {
		CashSmall = { Id = 3713838744, DisplayName = "Cash Pack S", RobuxPrice = 49, Cash = 10000, Gold = 0 },
		CashMedium = { Id = 3713838815, DisplayName = "Cash Pack M", RobuxPrice = 149, Cash = 50000, Gold = 0 },
		CashLarge = { Id = 3713838888, DisplayName = "Cash Pack L", RobuxPrice = 399, Cash = 200000, Gold = 0 },
		CashMega = { Id = 3713838952, DisplayName = "Cash Pack Mega", RobuxPrice = 799, Cash = 2000000, Gold = 0 },
		-- v71 money (M0): Gold has no sink yet (revenue audit F9), so the Gold packs are not sold. Ids kept.
		GoldSmall = { Id = 3713839003, DisplayName = "Gold Pack S", RobuxPrice = 49, Cash = 0, Gold = 50, HideFromShop = true },
		GoldMedium = { Id = 3713839048, DisplayName = "Gold Pack M", RobuxPrice = 149, Cash = 0, Gold = 200, HideFromShop = true },
		GoldLarge = { Id = 3713839090, DisplayName = "Gold Pack L", RobuxPrice = 349, Cash = 0, Gold = 500, HideFromShop = true },
		-- Placeholder Id=0: ProcessReceipt sets Battle Pass Premium when Id is live; Studio uses admin grantpremium
		PremiumPass = {
			Id = 3713839151,
			DisplayName = "Battle Pass Premium",
			RobuxPrice = 499,
			Cash = 0,
			Gold = 0,
			GrantsBattlePassPremium = true,
			OneTime = true, -- v69: Premium is a boolean kept across seasons; the Shop shows OWNED once granted
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
		-- v71 money (M1, owner decision D3): "Army Expansion (+10)", 99 R$, same Id. SoldierService adds ArmyCapBonus
		-- for Entitlements.ExtraSoldierSlot, so earlier +1 buyers get +10 too (retroactive). The key and the
		-- ExtraSoldierSlot entitlement name stay (receipts, saves and the Army panel use them).
		ExtraSoldierSlot = {
			Id = 3713839210,
			DisplayName = "Army Expansion (+10)",
			RobuxPrice = 99,
			Cash = 0,
			Gold = 0,
			GrantEntitlement = "ExtraSoldierSlot",
			ArmyCapBonus = 10,
			OneTime = true, -- v69: boolean entitlement; a second purchase would add nothing
			Description = "+10 army capacity, permanent",
		},
		-- v71 money (M0): not sold any more (Barracks L1 costs $2,500 of early cash; audit F13). Id kept for receipt compat.
		InstantBarracks = {
			Id = 3713839278,
			DisplayName = "Instant Barracks",
			RobuxPrice = 129,
			Cash = 0,
			Gold = 0,
			GrantEntitlement = "InstantBarracks",
			OneTime = true, -- v69: only raises Barracks to L1; OWNED once granted or Barracks is already L1+
			HideFromShop = true,
			Description = "Unlocks Barracks L1 instantly",
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
			OneTime = true, -- v69: permanent boolean flag
			Description = "Permanent move-speed boost",
		},
		-- Cosmetic oil pump gold dress — Id=0: MapSetup hides GoldenPump pad until Id set;
		-- ProcessReceipt + GrantEntitlement ready when Creator Dashboard Id is pasted.
		-- v71 money (M0): one-time Developer Product (J29), 49 R$. M0b: paste the Id AND remove HideFromShop in the
		-- same commit (the Shop row stays hidden until then).
		GoldenPumpjack = {
			Id = 0,
			DisplayName = "Golden Pumpjacks",
			RobuxPrice = 49,
			Cash = 0,
			Gold = 0,
			GrantEntitlement = "GoldenPumpjack",
			OneTime = true, -- boolean entitlement: a second purchase adds nothing; the Shop shows OWNED
			HideFromShop = true,
			Description = "Gold-dress every oil pump on your base",
		},
		-- v71 money (M1, owner decision D2): Commander Starter Pack v2, same Id, 149 R$, one time (J14: no timer until
		-- M3's real 72 h window). $50,000 + Auto Collect (permanent); a buyer who already owns Auto Collect gets
		-- StarterFallbackCash more instead. Old 249 R$ buyers get Auto Collect once (StarterGoodwill below).
		StarterBundle = {
			Id = 3713839505,
			DisplayName = "Commander Starter Pack",
			RobuxPrice = 149,
			Cash = 50000,
			Gold = 0,
			GrantEntitlement = "StarterBundle", -- OWNED key (WE_Ent_StarterBundle); also in GrantEntitlements
			GrantEntitlements = { "StarterBundle", "AutoCollect" },
			StarterFallbackCash = 25000,
			OneTime = true,
			Description = "$50,000 Cash + Auto Collect (permanent)",
		},
		-- v71 money (M1): the Nuke (nuke §2.2, plan §2.3). Consumables: no OneTime, no entitlement; GrantNukes adds to
		-- profile.Nukes (CounterGrants). Id = 0 until created; hidden until M3's feature gate (WE_Feature_Nuke, M5).
		Nuke = {
			Id = 0,
			DisplayName = "Nuke",
			RobuxPrice = 19,
			Cash = 0,
			Gold = 0,
			GrantNukes = 1,
			Feature = "Nuke",
			HideFromShop = true,
			Description = "1 Nuke: the biggest blast in the game, bonus XP",
		},
		NukeBundle3 = {
			Id = 0,
			DisplayName = "Nuke x3",
			RobuxPrice = 49,
			Cash = 0,
			Gold = 0,
			GrantNukes = 3,
			Feature = "Nuke",
			HideFromShop = true,
			Description = "3 Nukes (save 14%)",
		},
	},
	--[[ v71 money (M1): counter grants — the ONLY product fields ProcessReceipt adds to a profile number. Field is the
		profile key (a whole number >= 0), Stats (optional) a counter table + key bumped by the same amount,
		Attribute (optional) a display-only player attribute (never read back), Currency (optional) the Roblox
		AnalyticsService economy currency name, MaxPerReceipt a sanity cap on the config value. ]]
	CounterGrants = {
		GrantNukes = {
			Field = "Nukes",
			Stats = { Table = "NukeStats", Key = "Bought" },
			Attribute = "WE_Nukes",
			Currency = "Nukes",
			MaxPerReceipt = 100,
		},
	},
	-- v71 money (M1, D2): one-time thank-you for players who bought the old 249 R$ Starter Bundle: Auto Collect on
	-- their next join. Entitlements[Flag] marks it done (set even when they already owned Auto Collect).
	StarterGoodwill = {
		Enabled = true,
		IfEntitlement = "StarterBundle",
		GrantEntitlement = "AutoCollect",
		Flag = "StarterGoodwillV2",
	},
	--[[ v71 money (M1): optional second argument of RequestPurchaseDevProduct / RequestPurchaseGamePass (where the
		prompt came from). Analytics only; anything not listed is logged as "other". A receipt within
		IntentAttributionSeconds of the intent for the same key inherits its source. ]]
	PurchaseSources = {
		shop = true,
		featured = true,
		hud_plus = true,
		rail_shop = true,
		armory = true,
		offer = true,
		starter_offer = true,
		death_card = true,
		pad = true,
		bp_panel = true,
		army_panel = true,
		army_full = true,
		garage = true,
		showroom = true,
		trial_end = true,
		nuke_tile = true,
		nuke_card = true,
		silo = true,
	} :: { [string]: boolean },
	IntentAttributionSeconds = 180,
	-- Loot-box style RNG marked policy-pending — do not enable without compliance review
	-- v30: PvP death toast — was { "DoubleCash", "SpeedBoost" } (live Ids).
	-- v71 money (M0): empty, so a PvP death no longer offers 2x Cash to players who already own it; the M3 Offer
	-- Director's death card replaces this toast. Keep the DeathShopOffers key (CombatService / ShopController read it).
	DeathShopOffers = {} :: { string },
	-- v32: one-shot soft offer (server marks StarterBundleOffered).
	-- v71 money (M1): never during the tutorial. TutorialService schedules it AfterTutorialSeconds after the tutorial
	-- completes (finished or skipped), or DelaySeconds after load when it is already done, and sends it through
	-- MonetizationService.TrySoftOfferStarterBundle (only while the pack is live, unoffered and unowned).
	StarterBundleOffer = {
		DelaySeconds = 8,
		AfterTutorialSeconds = 3,
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
	-- v35: one-shot VIP soft offer at mid-game (level≥10 OR first structure L3); not spammy
	VIPOffer = {
		DelaySeconds = 2.0,
		MinLevel = 10,
		MinStructureLevel = 3,
	},
	-- v36: one-shot SpeedBoost soft offer after first jeep sit / walk-speed moment (existing Id only)
	SpeedBoostOffer = {
		DelaySeconds = 1.5,
		-- v71 money (M1): the spawn / first-vehicle-sit pop-ups raced the Starter offer; both triggers are ignored
		IgnoreReasons = { walk_speed = true, vehicle_sit = true } :: { [string]: boolean },
	},
	-- v37: one-shot CashMega soft toast after big pending collect OR death path (existing Id 3713838952 only)
	CashMegaOffer = {
		DelaySeconds = 1.8,
		MinPendingCollect = 15000, -- pending/granted threshold
		-- v71 money (M1): no 799 R$ pop-up on a PvP death (the M3 Director's death card replaces it)
		IgnoreReasons = { death = true } :: { [string]: boolean },
	},
	-- v38: one soft-offer toast max per session minute (shared across Starter/VIP/Speed/CashMega/AC/2x)
	-- v71 money (M1, owner decision D8): at most SoftOfferSessionMax per session, SoftOfferSessionCooldownSeconds
	-- apart, and none before the tutorial is complete (SoftOfferQuietMaxSeconds of play lifts that for players who
	-- never finish it). Same numbers as HudConfig.Offer, so the server no longer spends a one-shot offer the client
	-- would refuse.
	SoftOfferSessionCooldownSeconds = 240,
	SoftOfferSessionMax = 3,
	SoftOfferQuietUntilTutorialComplete = true,
	SoftOfferQuietMaxSeconds = 900,
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
