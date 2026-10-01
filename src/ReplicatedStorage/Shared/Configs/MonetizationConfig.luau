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
	  SoldFrom = "Panel"                the SKU is sold from that panel only (HideFromShop keeps it out of the Shop
	                                    list; the Id wiring tool does not ask to remove HideFromShop for it).
	New SKUs stay Id = 0 until the owner creates them; game passes are created with Item for Sale OFF (J3).
	Owner's 11 features (lane K1, spec_f11 §2): GamePasses.ImpulseSpeed (5 R$ Speed Pass), DevProducts.RebirthKeepBase
	(50 R$ keep-base rebirth token, counter grant GrantKeepBaseRebirths), the GoldenPumpjack Shop row (lights up when
	the Id is pasted), DeathSpeedOffer (one death offer per session) and PremiumPads (the ATM pad slots). Every new Id
	stays 0 until the owner creates the product: nothing prompts, no pad is built and no Shop row shows while it is 0. ]]

local AdminConfig = require(script.Parent.AdminConfig)

-- F1: one PremiumPads slot (see MonetizationConfig.PremiumPads)
export type PremiumPadOffer = { Kind: "GamePass" | "DevProduct", Key: string }
export type PremiumPadSlot = {
	Id: string,
	Label: string,
	Color: Color3,
	Offset: Vector3,
	Offers: { PremiumPadOffer },
	OwnedIfAny: { string }?,
}

local MonetizationConfig = {
	--[[ claude-bud: rollout of the three Robux SKUs in RolloutKeys. "owner" = only AdminConfig.IsPlaytestOwner can buy
		them and feel their effect; "all" = everyone; anything else = off (fail closed). ProcessReceipt still grants any
		receipt Roblox delivers for these Ids (a paid receipt is never dropped). OFF must equal the old game. ]]
	Rollout = "all", -- v101 (Code Bot, owner 2026-09-29: "enable everything for all players"): every RolloutKeys SKU on sale to everyone
	--[[ claude-bud JOB 12: the launch switch. LaunchAll = true makes every gate named in LaunchSafe live for EVERYONE at
		once (as if its Rollout were "all"), and turns off the playtest owner's shortcuts on the Robux path (premium vehicle
		spawn without the pass, the Extra Garage Slot test, premium weapons), so he buys like anyone else. Gates NOT in
		LaunchSafe (the BalanceConfig curve, the army rollouts, the aircraft / rebirth weapon lanes, the store vehicle
		bodies, Bridge Layer wading) keep their own switches: see LATEST-HANDOFF "Launch readiness". false = today. ]]
	LaunchAll = false,
	LaunchSafe = {
		Sales = true, -- MonetizationConfig.Rollout over RolloutKeys: the 13 Robux products (+ premium vehicle weapons)
		VIPPerks = true,
		Placement = true,
		Retention = true,
		Airdrop = true,
		DailyAutoClaim = true,
		PlazaBounty = true,
		ArmyUpgrades = true,
		GuardsFightBack = true,
		NpcUnstick = true,
		BagLos = true,
		FirstMinutes = true,
		QualityTier = true,
		Juice = true,
	} :: { [string]: boolean },
	RolloutKeys = { ImpulseSpeed = true, RebirthKeepBase = true, GoldenPumpjack = true, PV_Skylance = true, PV_Stormwing = true, PV_Leviathan = true, PV_Tidebreaker = true, PV_Warlord = true, PV_Razorfang = true, BiggerArmy = true, ExtraGarageSlot = true, SoldierRefill = true, PlazaAirstrike = true } :: { [string]: boolean },
	GamePasses = {
		VIP = {
			Id = 1985475542,
			DisplayName = "VIP",
			RobuxPrice = 199,
			CashBonusMult = 0.25, -- additive +25% cash earnings
			Description = "+25% cash on everything you earn", -- Code Bot v156: plain player text
			-- claude-bud JOB 36 (ShopOverhaulConfig, owner-first): the premium VIP. Shown at this price while the overhaul is
			-- live. codebot_v142 (2026-09-30): the Creator Hub price stays 199 (owner has NOT approved 349), so the Shop shows
			-- the real price. Change this only together with the Creator Hub price.
			OverhaulRobuxPrice = 199,
			OverhaulDescription = "+50% cash, a daily cash crate and VIP lounge", -- Code Bot v156: plain player text
		},
		-- claude-bud JOB 36: new passes (ShopOverhaulConfig). codebot_v140 (2026-09-30): owner created them on the Creator
		-- Hub (universe 10767159222, on sale, prices match); Ids wired. Implies = passes this one counts as owning.
		WarChest = {
			Id = 2002640637,
			OverhaulShop = true, -- sold by the JOB 36 Shop (and prompted) while ShopOverhaulConfig is live
			DisplayName = "War Chest",
			RobuxPrice = 799,
			Implies = { "DoubleCash", "AutoCollect", "VIP", "BiggerArmy" },
			HideFromShop = true, -- listed by the overhaul Shop only (hidden once all four are owned)
			Description = "2x cash, Auto Collect, VIP and Bigger Army", -- Code Bot v156: plain player text
		},
		SuperSoldiers = {
			Id = 1998231741,
			OverhaulShop = true, -- sold by the JOB 36 Shop (and prompted) while ShopOverhaulConfig is live
			DisplayName = "Super Soldiers",
			RobuxPrice = 349,
			HideFromShop = true, -- listed by the overhaul Shop only
			Description = "Your soldiers get +25% damage and health", -- Code Bot v156: plain player text
		},
		DoubleHP = {
			Id = 2002214665,
			OverhaulShop = true, -- sold by the JOB 36 Shop (and prompted) while ShopOverhaulConfig is live
			DisplayName = "Double HP",
			RobuxPrice = 199,
			HideFromShop = true, -- listed by the overhaul Shop only
			Description = "Double your max health",
		},
		DoubleCash = {
			Id = 1982865711,
			DisplayName = "2x Cash",
			RobuxPrice = 149,
			CashMult = 2, -- multiplicative 2x cash earnings
			Description = "Double your cash income", -- Code Bot v156: plain player text
		},
		DoubleXP = {
			Id = 1982487698,
			DisplayName = "Double XP",
			RobuxPrice = 99,
			XPMult = 2,
			Description = "Double the XP you earn", -- Code Bot v156: plain player text
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
			Description = "Your ATM cash is collected for you", -- Code Bot v156: plain player text
		},
		-- F8 (owner's 11 features): 5 R$ Speed Pass, walk speed x WalkSpeedMult forever. Id = 0 until the owner creates
		-- the pass. The 99 R$ Speed Boost Developer Product (DevProducts.SpeedBoost) stays; owning both gives the higher
		-- multiplier (MonetizationService.SpeedMultFor). Keep this key name: BuyPathStatic matches the first Speed Boost
		-- product block by its key.
		ImpulseSpeed = {
			Id = 1998656357,
			DisplayName = "Speed Pass",
			RobuxPrice = 99, -- 2026-09-29 owner repriced 5 -> 99 in Creator Hub
			WalkSpeedMult = 1.5, -- v133 (owner: "still not fast"): was 1.4 (v126, 16 -> 22.4); now 16 -> 24
			WalkSpeedMultV2 = 1.75, -- claude-bud JOB 40 (SpeedV2 live): 16 -> 28, "Run 75% faster"
			-- Description: set below from MonetizationConfig.SpeedText (one source for every speed string)
		},
		-- v71 money (M1): premium Robux vehicles (plan §2.2, PremiumVehicleConfig.Lineup PassKey). Id = 0 until the
		-- owner creates each pass (Item for Sale OFF until the M6 publish, J3). HideFromShop until M3's feature gate
		-- (WE_Feature_PremiumVehicles); the generic Shop pass loop must skip VehicleIds passes (M3/M6 Garage sells
		-- them). BundlePassKeys = other passes that also unlock the car; HideIfOwnsAny hides the bundle row.
		PV_Razorfang = {
			Id = 2002484380,
			DisplayName = "Razorfang GT Interceptor",
			RobuxPrice = 199,
			VehicleIds = { "PremiumRazorfang" },
			BundlePassKeys = { "PV_MotorPool" },
			Feature = "PremiumVehicles",
			Description = "Armored car with twin machine guns", -- Code Bot v156: plain player text
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
			Id = 2001320428,
			DisplayName = "Warlord Siege Tank",
			RobuxPrice = 799,
			VehicleIds = { "PremiumWarlord" },
			BundlePassKeys = { "PV_MotorPool" },
			Feature = "PremiumVehicles",
			Description = "Heavy tank with a siege cannon", -- Code Bot v156: plain player text
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
			Id = 2001722392,
			DisplayName = "Stormwing Gunship",
			RobuxPrice = 999,
			VehicleIds = { "PremiumStormwing" },
			Feature = "PremiumVehicles",
			Description = "Attack helicopter with a chin gun", -- Code Bot v156: plain player text
		},
		PV_Tidebreaker = { -- M6b (after waterways / boats)
			Id = 1999263465,
			DisplayName = "Tidebreaker Assault Boat",
			RobuxPrice = 299,
			VehicleIds = { "PremiumTidebreaker" },
			Feature = "PremiumVehicles",
			Description = "Fast assault boat with a machine gun", -- Code Bot v156: plain player text
		},
		-- claude-bud JOB 5a: Robux-only jet and capital ship (VehicleConfig Premium defs). TODO(owner): create on the Creator
		-- Hub, then paste the Ids (tools/wire-monetization-ids.py). Id 0 = hidden everywhere, nothing prompts.
		PV_Skylance = {
			Id = 2001602422,
			DisplayName = "Skylance Interceptor",
			RobuxPrice = 899,
			VehicleIds = { "PremiumSkylance" },
			Feature = "PremiumVehicles",
			Description = "Fighter jet with an air cannon", -- Code Bot v156: plain player text
		},
		-- claude-bud JOB 5b: Bigger Army pass (+ArmyCapBonus army capacity, mirrored into profile.Entitlements.BiggerArmy on
		-- ownership so SoldierService's cap reads it). TODO(owner): create "Bigger Army" (game pass, 249 R$), paste the Id.
		BiggerArmy = {
			Id = 2001734404,
			DisplayName = "Bigger Army",
			RobuxPrice = 249,
			ArmyCapBonus = 10,
			Description = "+10 soldiers in your army", -- Code Bot v156: plain player text (the Shop adds PERMANENT)
		},
		-- claude-bud JOB 6: Extra Garage Slot: +1 vehicle slot. Spawning a different vehicle PARKS the one you have out
		-- (it stays in the world, health kept) instead of removing it; sit in it to drive it again (VehicleService
		-- _Parked). TODO(owner): create "Extra Garage Slot" (game pass, 199 R$), paste the Id. Owner-only (RolloutKeys);
		-- GarageSlot.OwnerTest gives the playtest owner the slot before the Id exists.
		ExtraGarageSlot = {
			Id = 1999359549,
			DisplayName = "Extra Garage Slot",
			RobuxPrice = 199,
			Description = "Keep 2 vehicles out at the same time", -- Code Bot v156: plain player text
		},
		PV_Leviathan = {
			Id = 2001398410,
			DisplayName = "Leviathan Dreadnought",
			RobuxPrice = 1199,
			VehicleIds = { "PremiumLeviathan" },
			Feature = "PremiumVehicles",
			Description = "Giant battleship with a deck cannon", -- Code Bot v156: plain player text
		},
		-- claude-bud JOB 35: the PREMIUM GUNS ARMORY (PremiumGunsConfig; WeaponConfig Premium defs). Robux-only guns; owning
		-- a pass sets profile.Weapons[id] = true (PremiumGunService, on join + OnPassOwned). Id 0 = hidden in the Shop, the
		-- armory case shows SOON and never prompts. TODO(owner): create each pass on the Creator Hub, paste the Id.
		-- BundlePassKeys = the other pass that also unlocks the gun (the Armory Pass). Not in RolloutKeys (Id 0).
		PG_Sovereign = {
			Id = 2002154652,
			DisplayName = "Sovereign Gold Pistol",
			RobuxPrice = 99,
			WeaponIds = { "SovereignPistol" },
			BundlePassKeys = { "PG_ArmoryPass" },
			HideFromShop = true, -- sold from Shop > WEAPONS (gold rows) and the base armory, never the generic pass list
			Description = "Gold pistol that fires 2-shot bursts", -- Code Bot v156: plain player text
		},
		PG_Quake = {
			Id = 2003492417,
			DisplayName = "Quake Grenade Launcher",
			RobuxPrice = 249,
			WeaponIds = { "QuakeLauncher" },
			BundlePassKeys = { "PG_ArmoryPass" },
			HideFromShop = true, -- sold from Shop > WEAPONS (gold rows) and the base armory, never the generic pass list
			Description = "Lobs grenades, 6 per reload", -- Code Bot v156: plain player text
		},
		PG_Longshot = {
			Id = 2003180431,
			DisplayName = "Longshot Sniper",
			RobuxPrice = 299,
			WeaponIds = { "LongshotSniper" },
			BundlePassKeys = { "PG_ArmoryPass" },
			HideFromShop = true, -- sold from Shop > WEAPONS (gold rows) and the base armory, never the generic pass list
			Description = "Scoped sniper: 110 damage, long range", -- Code Bot v156: plain player text
		},
		PG_Havoc = {
			Id = 2002250646,
			DisplayName = "Havoc Rotary Gun",
			RobuxPrice = 349,
			WeaponIds = { "HavocRotary" },
			BundlePassKeys = { "PG_ArmoryPass" },
			HideFromShop = true, -- sold from Shop > WEAPONS (gold rows) and the base armory, never the generic pass list
			Description = "Spinning minigun with a 150-round belt", -- Code Bot v156: plain player text
		},
		PG_Thunderhead = {
			Id = 1999305818,
			DisplayName = "Thunderhead Rocket Launcher",
			RobuxPrice = 399,
			WeaponIds = { "ThunderheadLauncher" },
			BundlePassKeys = { "PG_ArmoryPass" },
			HideFromShop = true, -- sold from Shop > WEAPONS (gold rows) and the base armory, never the generic pass list
			Description = "Fires 2 rockets at once", -- Code Bot v156: plain player text
		},
		PG_Tempest = {
			Id = 2002682646,
			DisplayName = "Tempest Railgun",
			RobuxPrice = 499,
			WeaponIds = { "TempestRailgun" },
			BundlePassKeys = { "PG_ArmoryPass" },
			HideFromShop = true, -- sold from Shop > WEAPONS (gold rows) and the base armory, never the generic pass list
			Description = "Charged shot that goes through 3 enemies", -- Code Bot v156: plain player text
		},
		PG_ArmoryPass = {
			Id = 2002868467,
			DisplayName = "Armory Pass",
			RobuxPrice = 1299,
			WeaponIds = { "SovereignPistol", "QuakeLauncher", "LongshotSniper", "HavocRotary", "ThunderheadLauncher", "TempestRailgun" },
			BundlePassKeys = { "PG_Sovereign", "PG_Quake", "PG_Longshot", "PG_Havoc", "PG_Thunderhead", "PG_Tempest" }, -- hidden once all six are owned
			HideFromShop = true,
			Description = "All 6 premium guns", -- Code Bot v156: plain player text
		},
		-- claude-bud JOB 49 B / Code Bot v180 (Shaun approved + created 2026-10-01, universe 10767159222): 2x Offline Cash,
		-- a permanent Game Pass (was a Developer Product stub at Id 0). Owned = UserOwnsGamePassAsync on join / after
		-- PromptGamePassPurchaseFinished (WE_Ent_OfflineCap2x display flag); EconomyConfig.OfflineEarnings.CapBoost doubles
		-- the offline cap TIME (8 h -> 16 h). Never raises Share, no combat stat. Sold in the Shop (SUPPLY pass rows).
		OfflineCap2x = {
			Id = 2002664894,
			DisplayName = "2x Offline Cash",
			RobuxPrice = 149,
			Description = "Offline cash builds for 16 h instead of 8 h",
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
		-- claude-bud JOB 49 (Robux sidegrade). Code Bot v180 (Shaun approved + created 2026-10-01): the paid reroll after the
		-- free daily one, 19 R$. Sold from the Missions panel only (the 19 R$ reroll button on a core mission row once the
		-- free reroll is used); ProcessReceipt grants ONE MissionRerollTokens per receipt (idempotent: ProcessedReceipts).
		-- OfflineCap2x moved to GamePasses (it is a Game Pass on the Creator Hub, 2002664894).
		MissionReroll = { Id = 3715836569, DisplayName = "Mission Reroll", RobuxPrice = 19, Cash = 0, Gold = 0, GrantsMissionReroll = true, HideFromShop = true, SoldFrom = "Missions" },
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
			Description = "Unlock premium rewards on every Battle Pass tier", -- Code Bot v156: plain player text (was a dev note in the Shop)
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
			DisplayName = "Extra Soldier Slot", -- Code Bot v156: the Roblox product name (was "Army Expansion (+10)")
			RobuxPrice = 79, -- Code Bot v156: the real Creator Hub price (was 99; display fallback only, LivePrices)
			Cash = 0,
			Gold = 0,
			GrantEntitlement = "ExtraSoldierSlot",
			ArmyCapBonus = 10,
			OneTime = true, -- v69: boolean entitlement; a second purchase would add nothing
			Description = "+10 soldiers in your army, forever", -- Code Bot v156: plain player text
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
			WalkSpeedMult = 2.0, -- v133 (owner: "still not fast"): was 1.6 (v126, 16 -> 25.6); now 16 -> 32. Speed Pass 1.5
			WalkSpeedMultV2 = 2.5, -- claude-bud JOB 40 (SpeedV2 live): 16 -> 40, "Run 2.5x faster"
			-- Description: set below from MonetizationConfig.SpeedText
		},
		-- Cosmetic oil pump gold dress. v71 money (M0): one-time Developer Product (J29), 49 R$.
		-- F9 (owner's 11 features): lights up when the Id is pasted. While Id = 0 the Shop skips the row (it skips
		-- every Id 0 Developer Product) and no gold pad is built at the pumps; once the Id is live the Shop row and the
		-- pump pad appear with no other edit. ProcessReceipt + GrantEntitlement are ready.
		GoldenPumpjack = {
			Id = 3714663783,
			DisplayName = "Golden Pumpjacks",
			RobuxPrice = 49,
			Cash = 0,
			Gold = 0,
			GrantEntitlement = "GoldenPumpjack",
			OneTime = true, -- boolean entitlement: a second purchase adds nothing; the Shop shows OWNED
			IncomeMult = 1.5, -- claude-bud: plot pump cash per tick x this for an owner (PlotOilPumpService)
			Description = "Gold oil pumps that earn 50% more, forever", -- Code Bot v156: plain player text
		},
		-- v71 money (M1, owner decision D2): Commander Starter Pack v2, same Id, 149 R$, one time (J14: no timer until
		-- M3's real 72 h window). $50,000 + Auto Collect (permanent); a buyer who already owns Auto Collect gets
		-- StarterFallbackCash more instead. Old 249 R$ buyers get Auto Collect once (StarterGoodwill below).
		StarterBundle = {
			Id = 3713839505,
			-- Code Bot v156: the Roblox product name and REAL price (Creator Hub: "Commander Starter Bundle", 249 R$). The
			-- v71 D2 repricing to 149 never reached the Creator Hub, so the Shop said 149 while Roblox charged 249. These two
			-- are only the display fallback now (Shared/Util/LivePrices reads the live product); change the price on the
			-- Creator Hub, never here.
			DisplayName = "Commander Starter Bundle",
			RobuxPrice = 249,
			Cash = 50000,
			Gold = 0,
			GrantEntitlement = "StarterBundle", -- OWNED key (WE_Ent_StarterBundle); also in GrantEntitlements
			GrantEntitlements = { "StarterBundle", "AutoCollect" },
			StarterFallbackCash = 25000,
			OneTime = true,
			Description = "$50,000 cash plus Auto Collect forever", -- Code Bot v156: plain player text
		},
		-- claude-bud JOB 41 part B: the Recruit Pack (one time). Id 0 until the owner OKs 49 R$ and Code Bot creates the
		-- product. Cash is computed in ProcessReceipt from his income (RecruitPackOffer: 30 min of income, $25k..$150k), plus a
		-- 2x cash boost for 30 min (CodesService.GrantCashBoost) and the gold "RECRUIT" base trim (entitlement, no stat).
		-- NOT pay-to-win: no damage / health / armour / army / raid / protection key in this row (pinned).
		-- claude-bud JOB 42: TIME-based cash packs (repeatable). Id 0 until Code Bot creates them in the Creator Hub (an Id 0
		-- product never prompts and the Shop skips it). Cash = the floor; ProcessReceipt grants max(Floor, Minutes x his
		-- income) at receipt time (ShopOverhaulConfig.TimePacks). Cash only: no stat key.
		Cash15m = { Id = 3715776339, DisplayName = "15 Minutes of Cash", RobuxPrice = 25, Cash = 10000, Gold = 0 },
		Cash30m = { Id = 3715776410, DisplayName = "30 Minutes of Cash", RobuxPrice = 49, Cash = 25000, Gold = 0 },
		Cash1h = { Id = 3715776466, DisplayName = "1 Hour of Cash", RobuxPrice = 89, Cash = 50000, Gold = 0 },
		Cash2h = { Id = 3715776582, DisplayName = "2 Hours of Cash", RobuxPrice = 159, Cash = 100000, Gold = 0 },
		Cash4h = { Id = 3715776616, DisplayName = "4 Hours of Cash", RobuxPrice = 279, Cash = 200000, Gold = 0 },
		RecruitPack = { Id = 3715776659, DisplayName = "Recruit Pack", RobuxPrice = 49, Cash = 0, Gold = 0, GrantEntitlement = "RecruitPack", OneTime = true, CashFromTimePack = "Cash30m", Description = "Cash, 2x cash for 30 min and a gold base trim" }, -- claude-bud JOB 42 C: cash = the 30-min pack while TimePacks is live
	-- claude-bud JOB 66 (price approved by Shaun 2026-10-01 22:13 Dublin: 5 R$ each). Id 0 until Code Bot creates the
	-- products (turn OFF managed / dynamic pricing on both so they stay 5 R$). LiveBlock = owner-first switch (cfg.Starter5).
	StarterRecruit5 = { Id = 0, DisplayName = "Recruit Starter Pack", RobuxPrice = 5, Cash = 0, Gold = 0, GrantEntitlement = "StarterRecruit5", OneTime = true, GrantSoldiers = 3, StarterCash = true, LiveBlock = "Starter5", Description = "3 soldiers join your army + starter cash (one time)" },
	Boost2x10m = { Id = 0, DisplayName = "2x Income 10 min", RobuxPrice = 5, Cash = 0, Gold = 0, GrantsCashBoostMinutes = 10, LiveBlock = "Starter5", Description = "2x earned income for 10 minutes (buy again to extend)" },
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
		-- F7 (owner's 11 features): 50 R$ keep-base rebirth. Consumable: each receipt adds one token to
		-- profile.KeepBaseRebirths (CounterGrants.GrantKeepBaseRebirths), granted only in ProcessReceipt and saved
		-- before PurchaseGranted. The rebirth itself runs after the save (PrestigeService OnGranted listener,
		-- PrestigeConfig.KeepBase); a token that cannot be used yet is banked and never expires. Sold only from the
		-- Rebirth panel (SoldFrom), never from the Shop list. Id = 0 until the owner creates it: the Rebirth panel
		-- shows SOON and never prompts. Paste the Id only after the double prestige multiplier (B1) is fixed.
		-- claude-bud JOB 5c: TODO(owner) create "Instant Army Refill" (dev product, 49 R$) and "Plaza Airstrike" (dev
		-- product, 79 R$), then paste the Ids. Both bank a saved counter in ProcessReceipt (CounterGrants below), spent
		-- by the server (SoldierService.ConsumeRefills / Server/Modules/PlazaAirstrike). Owner-only first (RolloutKeys).
		SoldierRefill = {
			Id = 3715442523,
			DisplayName = "Instant Army Refill",
			RobuxPrice = 49,
			Cash = 0,
			Gold = 0,
			GrantSoldierRefills = 1,
			Description = "Refill your army to full right now", -- Code Bot v156: plain player text
		},
		PlazaAirstrike = {
			Id = 3715442542,
			DisplayName = "Plaza Airstrike",
			RobuxPrice = 79,
			Cash = 0,
			Gold = 0,
			GrantAirstrikes = 1,
			Description = "1 airstrike on the plaza: hurts, never kills", -- Code Bot v156: plain player text
		},
		RebirthKeepBase = {
			Id = 3714663721,
			DisplayName = "Keep-Base Rebirth",
			RobuxPrice = 50,
			Cash = 0,
			Gold = 0,
			GrantKeepBaseRebirths = 1,
			HideFromShop = true,
			SoldFrom = "RebirthPanel",
			Description = "Rebirth and keep every base upgrade",
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
		-- F7: keep-base rebirth tokens (DevProducts.RebirthKeepBase); WE_KeepBaseRebirths is display only
		GrantKeepBaseRebirths = {
			Field = "KeepBaseRebirths",
			Attribute = "WE_KeepBaseRebirths",
			MaxPerReceipt = 1,
		},
		-- claude-bud JOB 5c: army refill tokens (spent at once by SoldierService.ConsumeRefills; on join if a crash came first)
		GrantSoldierRefills = {
			Field = "SoldierRefills",
			Attribute = "WE_SoldierRefills",
			MaxPerReceipt = 1,
		},
		-- claude-bud JOB 5c: plaza airstrike charges (spent by Server/Modules/PlazaAirstrike)
		GrantAirstrikes = {
			Field = "AirstrikeCharges",
			Attribute = "WE_AirstrikeCharges",
			MaxPerReceipt = 1,
		},
	},
	-- claude-bud JOB 5c: Plaza Airstrike balance (Server/Modules/PlazaAirstrike)
	PlazaAirstrikeTuning = {
		UseRangeStuds = 220,
		WarnSeconds = 3,
		Damage = 35,
		MinHealthLeft = 1,
		ServerCooldownSeconds = 120,
		PlayerCooldownSeconds = 300,
	},
	-- v71 money (M1, D2): one-time thank-you for players who bought the old 249 R$ Starter Bundle: Auto Collect on
	-- their next join. Entitlements[Flag] marks it done (set even when they already owned Auto Collect).
	StarterGoodwill = {
		Enabled = true,
		IfEntitlement = "StarterBundle",
		GrantEntitlement = "AutoCollect",
		Flag = "StarterGoodwillV2",
	},
	--[[ F1 (owner's 11 features): walk-over pads beside the ATM, in this order (MapSetup.buildPremiumPads reads it).
		At most 3 slots: CLAUDE.md allows at most 3 world labels on screen at a base (VIP is sold in the Shop only; the
		Golden Pump pad sits at the pumps, PlotOilPumpConfig.Golden). Per slot:
		  Offset      plot-local offset from the ATM cluster anchor (the pad turns with the plot)
		  Offers      the first offer whose Id is not 0 is the one the pad sells; a slot with no live offer is not built
		  OwnedIfAny  owning any of these keys (game pass, or the entitlement a Developer Product grants) shows OWNED
		              and never prompts; default = the offer's own key
		Pads are 7x7-stud floor triggers (no tap target); each label is stud-scaled, MaxDistance = LabelMaxDistance,
		never AlwaysOnTop, tagged WorldLabelConfig.BaseLabelTag. The server decides ownership and "coming soon". ]]
	-- claude-bud JOB 6: the playtest owner has the Extra Garage Slot for testing while its pass Id is 0
	GarageSlot = {
		OwnerTest = true,
	},

	--[[ claude-bud JOB 5e: retention, owner-only first. FREE rows at the top of the Shop's Robux tab: the daily
		login reward (the existing server claim), the airdrop (tracks the live one), a group-join reward (GroupCash once,
		checked with IsInGroupAsync on the server; hidden while GroupId is 0 — TODO(owner): paste the group id) and an
		UNREWARDED favorite prompt (Roblox rules forbid rewards for favorites / likes). Roblox Premium members get
		PremiumDailyCash once per UTC day (server MembershipType check), which keeps them playing (Premium Payouts). ]]
	Retention = {
		Rollout = "all", -- v101
		GroupId = 0,
		GroupCash = 10000,
		PremiumDailyCash = 2500,
		FavoritePrompt = true,
	},

	--[[ claude-bud JOB 5d: purchase prompts at the right moments, owner-only first. Every server offer spends the
		existing soft-offer budget (MonetizationService.ClaimSoftOfferSlot: SoftOfferCooldownSeconds apart, at most
		SoftOfferSessionMax per session, quiet during the tutorial) and never shows for something already owned.
		  CantAffordVehicle: the Garage's "Need $X" tap offers the smallest cash pack that covers it (client toast).
		  AfterRebirth: after a rebirth, 2x Cash (if not owned) else the large cash pack.
		  ArmyWiped: when his last field soldier dies, the army refill (if its Id is live) else Army Expansion.
		  StarterLimitedHours: the Commander Starter Pack is offered only within this many hours of the first join,
		  and its toast shows the time left (a real limit, never a fake timer). ]]
	Placement = {
		Rollout = "all", -- v101
		CantAffordVehicle = true,
		AfterRebirth = true,
		ArmyWiped = true,
		StarterLimitedHours = 48,
	},

	--[[ claude-bud JOB 5b: VIP perks on top of the live VIP pass (+25 % cash, unchanged: live buyers paid for it). For a VIP
		they are live for: a [VIP] chat tag (player attribute WE_VIPTag -> FeatureController's OnIncomingMessage) and the
		VIP lounge near the plaza (Server/Modules/VIPLounge: a VIP-only door, a bonus pad paying LoungeCash once per
		LoungeCooldownSeconds). Rollout "owner" = AdminConfig.IsPlaytestOwner only, "all", anything else = off. ]]
	VIPPerks = {
		Rollout = "all", -- v101
		ChatTag = "[VIP]",
		Lounge = true,
		LoungeX = -150,
		LoungeZ = -430,
		LoungeCash = 5000,
		LoungeHoldSeconds = 2,
		LoungeCooldownSeconds = 900,
	},

	PremiumPads = {
		LabelMaxDistance = 20,
		-- claude-bud JOB 19: every base Robux offer is a purchase STAND (Server/Modules/PurchaseStands): a hexagonal steel
		-- plinth with a gold trim, a spinning hologram, an info board with the price from this config, a pulsing floor
		-- ring; ONLY its ProximityPrompt buys (stepping on it never does). Stands = true; false = the old flat pads.
		Stands = true,
		Stand = {
			Radius = 3.2, -- hexagon circumradius
			Height = 1.6,
			HoloSize = 1.6,
			HoloLift = 2.6, -- hologram centre above the top
			HoloTransparency = 0.3,
			RingTransparency = 0.55,
			LabelMaxDistance = 30, -- CLAUDE.md world labels (<= 40)
			PromptDistance = 10,
			HoldSeconds = 0.3, -- a short hold: never an accidental buy, easy with a finger
			LightBrightness = 0.7,
			LightRange = 10,
			Steel = Color3.fromRGB(58, 62, 68),
			Top = Color3.fromRGB(40, 43, 48),
			Gold = Color3.fromRGB(214, 170, 62),
			Owned = Color3.fromRGB(80, 210, 110),
			SpinSeconds = 6, -- one hologram turn (client)
			PulseSeconds = 1.6, -- ring pulse (client)
			-- Code Bot v175: ONE physical sign per stand (PurchaseStands.BuildSign, a SurfaceGui panel): never wider than
			-- Depot.Step minus a 5-stud gap, so neighbouring signs can never overlap (Code Bot v175)
			SignW = 6.4,
			SignH = 3.4,
			SignPixelsPerStud = 60,
			SignBack = Color3.fromRGB(26, 30, 26), -- dark military panel (the gold edge is Gold)
		},
		-- the Supply Depot corner (plot-local): the stands in one row (front-left, off the gate road and the ATM), the sign
		-- behind them facing the plot
		Depot = { X0 = -78, Step = 12, Z = 146, SignZ = 153, Sign = "SUPPLY DEPOT", SignLift = 11 }, -- Code Bot v175: SignLift (board centre height)
		Slots = {
			{
				Id = "AutoCollect",
				Label = "Auto Collect",
				Color = Color3.fromRGB(220, 50, 50), -- red
				Icon = "💰",
				Offset = Vector3.new(-10, 0.55, 14),
				Offers = { { Kind = "GamePass", Key = "AutoCollect" } },
			},
			{
				Id = "DoubleCash",
				Label = "2x Cash",
				Color = Color3.fromRGB(255, 210, 40), -- yellow
				Icon = "2x",
				Offset = Vector3.new(0, 0.55, 16),
				Offers = { { Kind = "GamePass", Key = "DoubleCash" } },
			},
			{
				Id = "Speed",
				Label = "Speed",
				Color = Color3.fromRGB(60, 190, 255), -- cyan
				Icon = "⚡",
				Offset = Vector3.new(10, 0.55, 14),
				-- the 5 R$ pass once its Id is live, else the 99 R$ Speed Boost product; owning either = OWNED
				Offers = { { Kind = "GamePass", Key = "ImpulseSpeed" }, { Kind = "DevProduct", Key = "SpeedBoost" } },
				OwnedIfAny = { "ImpulseSpeed", "SpeedBoost" },
			},
		} :: { PremiumPadSlot },
	},
	--[[ v71 money (M1): optional second argument of RequestPurchaseDevProduct / RequestPurchaseGamePass (where the
		prompt came from). Analytics only; anything not listed is logged as "other". A receipt within
		IntentAttributionSeconds of the intent for the same key inherits its source. ]]
	PurchaseSources = {
		recruit_offer = true, -- claude-bud JOB 41 B: the Recruit Pack card
		shop = true,
		featured = true,
		hud_plus = true,
		rail_shop = true,
		armory = true,
		offer = true,
		starter_offer = true,
		death_card = true,
		pad = true,
		missions = true, -- Code Bot v180: the Missions panel's paid reroll button
		bp_panel = true,
		army_panel = true,
		army_full = true,
		garage = true,
		showroom = true,
		trial_end = true,
		nuke_tile = true,
		nuke_card = true,
		silo = true,
		rebirth_panel = true, -- F7: the Keep-Base Rebirth button in the Rebirth confirm modal
	} :: { [string]: boolean },
	IntentAttributionSeconds = 180,
	-- Loot-box style RNG marked policy-pending — do not enable without compliance review
	-- v30: PvP death toast — was { "DoubleCash", "SpeedBoost" } (live Ids).
	-- v71 money (M0): empty, so a PvP death no longer offers 2x Cash to players who already own it; the M3 Offer
	-- Director's death card replaces this toast. Keep the DeathShopOffers key (CombatService / ShopController read it).
	DeathShopOffers = {} :: { string },
	-- F8 (owner's 11 features): the ONE death offer that is allowed, kept apart from DeathShopOffers (which stays
	-- empty: no 2x Cash / Cash Mega offer after a death). MonetizationService.TryDeathSpeedOffer sends
	-- DeathShopOffer { Offers = { PassKey } } after a PvP non-blast death only when the pass Id is live, the player
	-- owns none of SkipIfOwnsAny, the tutorial is complete (RequireTutorialComplete), it is the first send this
	-- session (OncePerSession) and a soft-offer slot is free (SoftOfferSession* budget below).
	DeathSpeedOffer = {
		PassKey = "ImpulseSpeed",
		OncePerSession = true,
		SkipIfOwnsAny = { "ImpulseSpeed", "SpeedBoost" } :: { string },
		RequireTutorialComplete = true,
	},
	-- v32: one-shot soft offer (server marks StarterBundleOffered).
	-- v71 money (M1): never during the tutorial. TutorialService schedules it AfterTutorialSeconds after the tutorial
	-- completes (finished or skipped), or DelaySeconds after load when it is already done, and sends it through
	-- MonetizationService.TrySoftOfferStarterBundle (only while the pack is live, unoffered and unowned).
	StarterBundleOffer = {
		DelaySeconds = 8,
		AfterTutorialSeconds = 3,
	},
	-- Code Bot v153 (Shaun: "ship the sales fixes"; ~1,100 ad visits, 0 sales, 2.8-minute sessions, almost nobody saw
	-- an offer). Live for everyone (a timing / bug fix, not owner-first). While Enabled:
	--   * the soft-offer quiet window is the first AtPlaySeconds of the session, WHATEVER the tutorial state (it was:
	--     none until the 7-step tutorial is done, or SoftOfferQuietMaxSeconds 900 s for players who never finish);
	--   * MonetizationService.ScheduleFirstOffer sends the Starter Pack at AtPlaySeconds (TutorialService schedules it
	--     at load for every player; after the tutorial when that comes later). When the pack is not wanted (owned /
	--     window over / already SHOWN), the first FallbackKeys offer that is live and unowned goes instead, once;
	--   * the Starter Pack is marked StarterBundleOffered only when the client confirms it SHOWED (OfferResult
	--     remote, OfferLedger). A dropped / refused / unanswered card is re-queued RequeueSeconds later (slot
	--     refunded), at most MaxSendsPerSession sends a session;
	--   * a seated player (driving) is waited for up to SeatedWaitSeconds before the send; on the client the card
	--     still waits out active combat (RecentCombat, a few seconds), a modal, death, an alert, and driving.
	-- The D8 budget stays: SoftOfferSessionMax per session, SoftOfferSessionCooldownSeconds apart (and HudConfig.Offer
	-- MaxPerSession / MinGapSeconds on the client). Prices / passes / products are unchanged.
	FirstOffer = {
		Enabled = true,
		AtPlaySeconds = 120,
		SeatedWaitSeconds = 30,
		SeatedCheckSeconds = 1,
		AckTimeoutSeconds = 100, -- > the client's 60 s queue drop + a pump tick
		RequeueSeconds = 45, -- > ShopController's 30 s Starter toast debounce
		MaxSendsPerSession = 4,
		MaxSlotWaits = 6, -- slot busy (another offer's cooldown): wait for it this many times, then stop
		FallbackKeys = { "SpeedBoost" } :: { string }, -- 99 R$ Speed Boost (existing product, TrySoftOfferSpeedBoost)
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
		vip_supply = true, -- claude-bud JOB 36: the VIP crate is already minutes of multiplied income
		checkpoint = true, -- claude-bud JOB 37: the checkpoint-cleared bonus is already minutes of multiplied income
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
		offline = true, -- claude-bud JOB 29: the offline pay is already a share of the multiplied income rate
		onboarding = true, -- claude-bud JOB 29: the FastStart starter payout is a fixed amount
		atm_raid = true,
		plot_oil = true, -- plot pump PendingCash via AccruePendingCash
		ops = true, -- W3s2 Jobs: fixed job pay (OpsConfig.Rewards), never pass-multiplied
		-- v104 (Code Bot): JOB 13 engagement rewards are fixed amounts (EngagementConfig), so their caps are the real caps
		invite_welcome = true,
		invite_reward = true,
		friends_bonus = true,
		comeback = true,
	},
	XPMultExemptReasons = {
		admin = true,
		battlepass = true,
		achievement = true,
		build_backfill = true, -- XP rebalance XP-L2: the one-time backfill grant (season x1.1 only; no pass check at join)
	},
}

-- claude-bud JOB 12: is the launch switch on for this gate (LaunchAll and the gate is in LaunchSafe)
function MonetizationConfig.Launched(gate: string): boolean
	return (MonetizationConfig :: any).LaunchAll == true and (MonetizationConfig :: any).LaunchSafe[gate] == true
end

-- claude-bud JOB 5e: is retention (free Shop rows, group reward, Premium bonus) live for this player (fail closed)
function MonetizationConfig.RetentionLiveFor(userId: any): boolean
	if MonetizationConfig.Launched("Retention") then
		return true
	end
	local mode = (MonetizationConfig :: any).Retention.Rollout
	if mode == "all" then
		return true
	elseif mode == "owner" then
		return AdminConfig.IsPlaytestOwner(userId)
	end
	return false
end

-- claude-bud JOB 5d: are the placement prompts live for this player (fail closed)
function MonetizationConfig.PlacementLiveFor(userId: any): boolean
	if MonetizationConfig.Launched("Placement") then
		return true
	end
	local mode = (MonetizationConfig :: any).Placement.Rollout
	if mode == "all" then
		return true
	elseif mode == "owner" then
		return AdminConfig.IsPlaytestOwner(userId)
	end
	return false
end

-- claude-bud JOB 5b: are the VIP perks (chat tag, lounge) live for this player (fail closed)
function MonetizationConfig.VIPPerksLiveFor(userId: any): boolean
	if MonetizationConfig.Launched("VIPPerks") then
		return true
	end
	local mode = (MonetizationConfig :: any).VIPPerks.Rollout
	if mode == "all" then
		return true
	elseif mode == "owner" then
		return AdminConfig.IsPlaytestOwner(userId)
	end
	return false
end

-- claude-bud: is this SKU key on sale / effective for this player under Rollout. Keys outside RolloutKeys are always live.
-- claude-bud JOB 66: the two 5 R$ starter products (owner-first; the one-time offer after ~5 min of play)
(MonetizationConfig :: any).Starter5 = {
	Enabled = true,
	OwnerFirst = true, -- NEW-OWNER-FIRST (claude-bud JOB 66): only Shaun until his phone test
	OfferAfterPlaySeconds = 300, -- the "5 R$ ONE-TIME OFFER" card (once, saved: profile.Starter5Offered)
	CashIncomeMinutes = 2.5, -- the Recruit Starter Pack's cash = about 2-3 minutes of his early income ...
	CashMin = 750, -- ... at least this (a brand-new base earns about $300 / min)
	CashMax = 20000, -- ... and never more (a starter pack, not a cash pack)
	BoostMult = 2, -- the 10-minute boost (CodesService.GrantCashBoost: extends a running one)
	Title = "5 R$ ONE-TIME OFFER",
	Lines = { Soldiers = "3 soldiers join your army", Cash = "$%s starter cash", Boost = "2x income 10 min: in the Shop" },
}

function MonetizationConfig.Starter5LiveFor(userId: any): boolean
	return (require(script.Parent.RetentionConfig) :: any).Live((MonetizationConfig :: any).Starter5, userId)
end

-- the Recruit Starter Pack cash for an income of perMin (pure)
function MonetizationConfig.Starter5Cash(perMin: number): number
	local S = (MonetizationConfig :: any).Starter5
	return math.clamp(math.floor(S.CashIncomeMinutes * math.max(0, tonumber(perMin) or 0) + 0.5), S.CashMin, S.CashMax)
end

function MonetizationConfig.SkuLiveFor(userId: any, key: string): boolean
	-- claude-bud JOB 66: a row tied to an owner-first switch (LiveBlock) follows that switch
	local row: any = (MonetizationConfig.DevProducts :: any)[key]
	if row and typeof(row.LiveBlock) == "string" then
		local block = (MonetizationConfig :: any)[row.LiveBlock]
		return (require(script.Parent.RetentionConfig) :: any).Live(block, userId)
	end
	if not (MonetizationConfig.RolloutKeys :: any)[key] then
		return true
	end
	if MonetizationConfig.Launched("Sales") then
		return true -- claude-bud JOB 12
	end
	local mode = MonetizationConfig.Rollout :: any
	if mode == "all" then
		return true
	elseif mode == "owner" then
		return AdminConfig.IsPlaytestOwner(userId)
	end
	return false
end

--[[ F1: the offer a PremiumPads slot sells right now: the first offer whose GamePasses / DevProducts entry exists with
	a non-zero Id, or nil when none is live (the pad is not built). Pure; the server and the client call it alike. ]]
function MonetizationConfig.LivePadOffer(slot: PremiumPadSlot): PremiumPadOffer?
	for _, offer in ipairs(slot.Offers) do
		local section: any = if offer.Kind == "GamePass"
			then MonetizationConfig.GamePasses
			elseif offer.Kind == "DevProduct" then MonetizationConfig.DevProducts
			else nil
		local def = section and section[offer.Key]
		if
			typeof(def) == "table"
			and typeof(def.Id) == "number"
			and def.Id ~= 0
			and (MonetizationConfig.Rollout == "all" or MonetizationConfig.Launched("Sales") or not (MonetizationConfig.RolloutKeys :: any)[offer.Key])
		then
			return offer
		end
	end
	return nil
end

-- F1: the keys whose ownership makes a slot's pad read OWNED (OwnedIfAny, else the live offer's own key).
function MonetizationConfig.PadOwnedKeys(slot: PremiumPadSlot): { string }
	if slot.OwnedIfAny ~= nil and #slot.OwnedIfAny > 0 then
		return slot.OwnedIfAny
	end
	local offer = MonetizationConfig.LivePadOffer(slot)
	return if offer then { offer.Key } else {}
end

--[[ claude-bud JOB 40 part B: SPEED, with text that cannot go stale. SpeedV2 (owner-first) switches the speed SKUs to
	their WalkSpeedMultV2 (Speed Pass x1.75 = 28, Speed Boost x2.5 = 40; owning both = the higher); off = x1.5 / x2 as
	today. Every speed string comes from SpeedText (the Descriptions below, the stands, the Shop rows, the death card,
	the Speed Boost toast). MaxWalkSpeedMult is the sanity cap MonetizationService applies (it was a local 2.0). Robux
	prices and Ids are unchanged. ]]
local cfg: any = MonetizationConfig

--[[ claude-bud JOB 41 part B: WHEN the Recruit Pack is offered (owner-first; RetentionConfig.Live). Once per profile
	(profile.RecruitPackOffered), at the FIRST of: his first capture, or OfferAfterPlaySeconds of total play
	(Stats.PlayTimeSeconds); never in the Guided hold, combat, a seat or another card; through ClaimSoftOfferSlot (busy =
	retry every RetrySeconds this session). While it is live for a player the old after-tutorial Starter Pack pop-up does
	NOT fire for him (the StarterBundle row stays in the Shop). Id 0 = never offered. ]]
cfg.RecruitPackOffer = {
	Enabled = true,
	OwnerFirst = false, -- codebot_v166 flip-all-live (owner 2026-10-01 10:31): everyone (Id 0 = never offered)
	IncomeMinutes = 30, -- cash = this many minutes of his passive income ...
	MinCash = 25000, -- ... at least (2.5x the 49 R$ Cash Pack S $10,000) ...
	MaxCash = 150000, -- ... at most
	BoostMinutes = 30,
	BoostMult = 2,
	OfferAfterPlaySeconds = 600,
	CombatQuietSeconds = 20,
	RetrySeconds = 30,
	MaxTriesPerSession = 6,
	TickSeconds = 5,
	AutoHideSeconds = 20,
	ClientWaitMaxSeconds = 90,
	Lines = { Cash = "$%s Cash", Boost = "2x Cash for 30 min", Trim = "Gold base trim" },
}

function cfg.RecruitPackLiveFor(userId: any): boolean
	return (require(script.Parent.RetentionConfig) :: any).Live(cfg.RecruitPackOffer, userId)
end

-- Code Bot v166: the Recruit Pack takes the old Starter Pack pop-up slot only once it can actually be offered (live for
-- him AND its Id set). While the Id is 0 the Starter Pack first offer (+ its Speed Boost fallback) runs as before.
function cfg.RecruitPackTakesStarterSlot(userId: any): boolean
	local def = cfg.DevProducts.RecruitPack
	local id = if typeof(def) == "table" then tonumber(def.Id) or 0 else 0
	return id ~= 0 and cfg.RecruitPackLiveFor(userId) == true
end

-- claude-bud JOB 42 part C: the Recruit Pack's cash for a player: the CashFromTimePack time pack's amount (no cap, the
-- Cash30m floor = MinCash) while TimePacks is live for him, else the JOB 41 clamp below (OFF == OLD). One formula each.
function cfg.RecruitPackCashFor(userId: any, perMin: number): number
	local key = cfg.DevProducts.RecruitPack.CashFromTimePack
	local okS, SO = pcall(function(): any
		return (require :: any)(script.Parent.ShopOverhaulConfig) -- (any: breaks the static cycle with ShopOverhaulConfig for the type checker)
	end)
	if okS and SO and typeof(key) == "string" and SO.TimePacks.Packs[key] ~= nil and SO.TimePacksLiveFor(userId) then
		return SO.TimePackAmount(key, perMin) or cfg.RecruitPackCash(perMin)
	end
	return cfg.RecruitPackCash(perMin)
end

-- true when the Recruit Pack's cash follows a time pack for this player (the income then leaves out timed boosts)
function cfg.RecruitPackUsesTimePack(userId: any): boolean
	local key = cfg.DevProducts.RecruitPack.CashFromTimePack
	local okS, SO = pcall(function(): any
		return (require :: any)(script.Parent.ShopOverhaulConfig) -- (any: breaks the static cycle with ShopOverhaulConfig for the type checker)
	end)
	return okS and SO ~= nil and typeof(key) == "string" and SO.TimePacks.Packs[key] ~= nil and SO.TimePacksLiveFor(userId) == true
end

-- the pack's cash for an income of `perMin` $/min (clamped; never below MinCash)
function cfg.RecruitPackCash(perMin: number): number
	local o = cfg.RecruitPackOffer
	local p = tonumber(perMin) or 0
	if p ~= p or p < 0 then
		p = 0
	end
	return math.clamp(math.floor(o.IncomeMinutes * p + 0.5), o.MinCash, o.MaxCash)
end
cfg.SpeedV2 = {
	Enabled = true,
	OwnerFirst = false, -- codebot_v166 flip-all-live (owner 2026-10-01 10:31): everyone: only changes the speed SKUs' multiplier, so only Speed Pass / Speed Boost owners run faster (SpeedMultFor counts owned SKUs only)
}
cfg.MaxWalkSpeedMult = 2.5

function cfg.SpeedV2LiveFor(userId: any): boolean
	local b = cfg.SpeedV2
	if b.Enabled ~= true then
		return false
	end
	if b.OwnerFirst ~= true then
		return true
	end
	local okR, RS = pcall(function(): any
		return game:GetService("RunService")
	end)
	if okR and RS and RS:IsStudio() then
		return true
	end
	return AdminConfig.IsPlaytestOwner(userId)
end

-- "Run 75% faster" (x < 2) / "Run 2x faster" / "Run 2.5x faster" (x >= 2); forever adds ", forever"
function cfg.SpeedText(mult: number, forever: boolean?): string
	local m = tonumber(mult) or 1
	local s
	if m < 2 then
		s = string.format("Run %d%% faster", math.floor((m - 1) * 100 + 0.5))
	elseif math.abs(m - math.floor(m + 0.5)) < 0.001 then
		s = string.format("Run %dx faster", math.floor(m + 0.5))
	else
		s = string.format("Run %sx faster", (string.gsub(string.format("%.2f", m), "0+$", "")))
	end
	return if forever then s .. ", forever" else s
end

-- a speed SKU's multiplier for this player (V2 while live; nil userId = today's)
function cfg.SpeedMultOf(def: any, userId: any): number
	if typeof(def) ~= "table" then
		return 1
	end
	if userId ~= nil and typeof(def.WalkSpeedMultV2) == "number" and cfg.SpeedV2LiveFor(userId) then
		return def.WalkSpeedMultV2
	end
	return tonumber(def.WalkSpeedMult) or 1
end

-- the description a player should read for a SKU (speed SKUs from SpeedText, everything else its Description)
function cfg.DescFor(def: any, userId: any): string?
	if typeof(def) ~= "table" then
		return nil
	end
	if typeof(def.WalkSpeedMult) == "number" and def.WalkSpeedMult > 1 then
		return cfg.SpeedText(cfg.SpeedMultOf(def, userId), true)
	end
	return if typeof(def.Description) == "string" then def.Description else nil
end

cfg.GamePasses.ImpulseSpeed.Description = cfg.SpeedText(cfg.GamePasses.ImpulseSpeed.WalkSpeedMult, true)
cfg.DevProducts.SpeedBoost.Description = cfg.SpeedText(cfg.DevProducts.SpeedBoost.WalkSpeedMult, true)

return MonetizationConfig
