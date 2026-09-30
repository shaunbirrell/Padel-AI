--!strict

local AnalyticsConfig = {
	Enabled = true,
	LogToOutput = false, -- claude-bud JOB 24 §10: the Roblox sink below is live; Studio still prints every event
	-- claude-bud JOB 24 §10: Roblox AnalyticsService (Creator Hub -> Analytics). Funnel = the onboarding steps (new
	-- players only: FirstJoinUnix within FunnelNewPlayerSeconds; each step once, saved in profile.AnalyticsFunnel).
	-- Economy = Cash sources / sinks, summed per reason and flushed every EconomyFlushSeconds (never per collect).
	-- Custom = these events only, a few per player per minute at most (MaxCustomPerMinute + PerPlayer x players).
	Roblox = {
		Enabled = true,
		FunnelNewPlayerSeconds = 900,
		-- claude-bud JOB 29: the SAME funnel, extended with every onboarding step at the real moment it happens. "STEP:<x>"
		-- events come from AnalyticsService.Onboard: RetentionService (Joined / CharacterSpawned on the real join and first
		-- spawn) and TutorialService (BaseClaimed and Tut_<step Id> when that tutorial step is finished, TutorialDone /
		-- TutorialSkipped). Order = the owner's tutorial order; a step done early (bought before asked) still counts.
		Funnel = {
			{ Step = "Joined", Events = { "PLAYER_JOIN", "STEP:Joined" } },
			{ Step = "Spawned", Events = { "STEP:CharacterSpawned" } },
			{ Step = "BaseClaimed", Events = { "STEP:BaseClaimed" } },
			{ Step = "FirstBuilding", Events = { "STEP:Tut_CommandCenter", "FIRST_UPGRADE", "UPGRADE_PURCHASED" } },
			{ Step = "CollectedCash", Events = { "STEP:Tut_Income", "CASH_COLLECT" } },
			{ Step = "Recruited", Events = { "STEP:Tut_RecruitSoldiers", "SOLDIER_RECRUIT" } },
			{ Step = "Barracks", Events = { "STEP:Tut_Barracks" } },
			{ Step = "FirstOutpost", Events = { "STEP:Tut_Outpost", "FIRST_OUTPOST", "TERRITORY_CAPTURED" } },
			{ Step = "FirstVehicle", Events = { "STEP:Tut_Jeep", "VEHICLE_SPAWNED" } },
			{ Step = "TutorialDone", Events = { "STEP:TutorialDone", "STEP:TutorialSkipped" } },
			{ Step = "OpenedArmy", Events = { "ARMY_OPEN" } },
			{ Step = "FirstAttack", Events = { "ARMY_ATTACK" } },
			{ Step = "PurchasePrompt", Events = { "SHOP_PROMPT", "PREMIUM_VEHICLE_PROMPT" } },
			{ Step = "FirstPurchase", Events = { "FIRST_PURCHASE", "PURCHASE_RECEIPT" } },
		},
		EconomyFlushSeconds = 60,
		-- reason (prefix) -> Enum.AnalyticsEconomyTransactionType name; anything else = Gameplay
		EconomyTypes = { upgrade_ = "Shop", weapon_ = "Shop", vehicle_ = "Shop", research_ = "Shop", recruit_ = "Shop", devproduct = "IAP",
			daily = "TimedReward", premium_daily = "TimedReward", spinner = "TimedReward", code = "ContextualPurchase", onboarding = "Onboarding", offline = "TimedReward" }, -- claude-bud JOB 29: offline
		-- in-house event -> Roblox custom event name (value = the Value prop, else 1; field 1 = the Field prop)
		Custom = {
			SHOP_OPEN = { Name = "ShopOpened" },
			SHOP_PROMPT = { Name = "ProductPrompted", Field = "productKey" },
			PROMPT_CLOSED = { Name = "PromptCancelled", Field = "kind" },
			PURCHASE_RECEIPT = { Name = "RobuxPurchase", Value = "currencySpent", Field = "productKey" },
			VEHICLE_SPAWNED = { Name = "VehicleSpawned", Field = "vehicle" },
			MISSILE_STRIKE = { Name = "MissileLaunched" },
			NUKE_LAUNCH = { Name = "NukeLaunched" },
			CODE_REDEEM = { Name = "CodeRedeemed", Field = "code" },
			TUTORIAL_SHOWN = { Name = "TipShown", Field = "tip" },
			TUTORIAL_CLOSED = { Name = "TipClosed", Field = "tip" },
			ARMY_ATTACK = { Name = "ArmyAttack" },
			SESSION_END = { Name = "SessionLength", Value = "minutes", Field = "bucket" },
			-- claude-bud JOB 29: seconds to each funnel step (RetentionConfig.Funnel), offline pay, notification opt-in
			ONBOARD_STEP = { Name = "OnboardingSeconds", Value = "seconds", Field = "step" },
			OFFLINE_EARNED = { Name = "OfflineEarned", Value = "cash", Field = "hours" },
			NOTIF_OPTIN = { Name = "NotificationOptIn", Field = "result" },
			STREAK_DAY = { Name = "StreakDay", Value = "day" },
			-- claude-bud JOB 31: site activities
			ACTIVITY_START = { Name = "ActivityStarted", Field = "activity" },
			ACTIVITY_DONE = { Name = "ActivityFinished", Value = "seconds", Field = "activity" },
		},
		MaxCustomPerMinute = 100,
		PerPlayerPerMinute = 10,
		-- the client may report only these (RequestAnalyticsEvent; a few per minute per player)
		ClientEvents = { ShopOpened = "SHOP_OPEN", ArmyOpened = "ARMY_OPEN", TipShown = "TUTORIAL_SHOWN", TipClosed = "TUTORIAL_CLOSED" },
		ClientPerMinute = 12,
	},
	Events = {
		PLAYER_JOIN = "PLAYER_JOIN",
		PLAYER_LEAVE = "PLAYER_LEAVE",
		FIRST_UPGRADE = "FIRST_UPGRADE",
		UPGRADE_PURCHASED = "UPGRADE_PURCHASED",
		LEVEL_UP = "LEVEL_UP",
		DAILY_REWARD_CLAIMED = "DAILY_REWARD_CLAIMED",
		PURCHASE_RECEIPT = "PURCHASE_RECEIPT",
		ADMIN_COMMAND = "ADMIN_COMMAND",
		SESSION_LOCK_CONFLICT = "SESSION_LOCK_CONFLICT",
		FIRST_PVP = "FIRST_PVP",
		PLAYER_KILL = "PLAYER_KILL",
		NPC_KILL = "NPC_KILL",
		WEAPON_PURCHASED = "WEAPON_PURCHASED",
		WEAPON_EQUIPPED = "WEAPON_EQUIPPED",
		VEHICLE_PURCHASED = "VEHICLE_PURCHASED",
		VEHICLE_SPAWNED = "VEHICLE_SPAWNED",
		FIRST_OUTPOST = "FIRST_OUTPOST",
		TERRITORY_CAPTURED = "TERRITORY_CAPTURED",
		TERRITORY_LOST = "TERRITORY_LOST",
		MISSION_CLAIMED = "MISSION_CLAIMED",
		MISSION_PROGRESS = "MISSION_PROGRESS",
		ACHIEVEMENT_UNLOCKED = "ACHIEVEMENT_UNLOCKED",
		SHOP_PROMPT = "SHOP_PROMPT",
		SEASON_END = "SEASON_END",
		SEASON_RESUME = "SEASON_RESUME",
		CLAN_WAR_DECLARE = "CLAN_WAR_DECLARE",
		CLAN_WAR_SETTLE = "CLAN_WAR_SETTLE",
		SOLDIER_RECRUIT = "SOLDIER_RECRUIT",
		SOLDIER_DISMISS = "SOLDIER_DISMISS",
		BATTLEPASS_CLAIM = "BATTLEPASS_CLAIM",
		PRESTIGE = "PRESTIGE",
		CODE_REDEEM = "CODE_REDEEM",
		CAPTURE_STIPEND = "CAPTURE_STIPEND",
		TRAINING_INCOME = "TRAINING_INCOME",
		NATION_COLOR_ASSIGN = "NATION_COLOR_ASSIGN",
		SUPPLY_DROP_CLAIM = "SUPPLY_DROP_CLAIM",
		BANK_RAID = "BANK_RAID",
		SPINNER_CLAIM = "SPINNER_CLAIM",
		-- v71 money (M2): events named in the money designs (nothing logs them yet). Cut this round, so not
		-- listed: REBIRTH_PERMIT_APPLIED, REBIRTH_SKIP_USED (J12) and REBIRTH_KIT_GRANTED.
		-- Nuke (nuke §13)
		NUKE_GRANTED = "NUKE_GRANTED", -- kind, count, source (receipt/silo/gift/battlepass/admin/refund), inventoryAfter
		NUKE_LAUNCH = "NUKE_LAUNCH",
		NUKE_REJECT = "NUKE_REJECT",
		NUKE_DETONATE = "NUKE_DETONATE",
		NUKE_ABORT = "NUKE_ABORT",
		NUKE_REFUND = "NUKE_REFUND",
		NUKE_OFFER_SHOWN = "NUKE_OFFER_SHOWN",
		NUKE_SILO_BUILT = "NUKE_SILO_BUILT",
		-- Premium vehicles and vehicle combat (premium §3.6, §10)
		PREMIUM_VEHICLE_VIEW = "PREMIUM_VEHICLE_VIEW",
		PREMIUM_VEHICLE_PROMPT = "PREMIUM_VEHICLE_PROMPT",
		PREMIUM_VEHICLE_OWNED = "PREMIUM_VEHICLE_OWNED",
		PREMIUM_TRIAL_START = "PREMIUM_TRIAL_START",
		PREMIUM_TRIAL_END = "PREMIUM_TRIAL_END",
		PREMIUM_OFFER_SHOWN = "PREMIUM_OFFER_SHOWN",
		VEHICLE_WEAPON_KILL = "VEHICLE_WEAPON_KILL",
		VEHICLE_DESTROYED = "VEHICLE_DESTROYED", -- vehicle, premium, killer, class
		-- Rebirth expansion (rebirth §16)
		REBIRTH_ZONE_OPENED = "REBIRTH_ZONE_OPENED", -- zone, via (prestige/admin)
		REBIRTH_OFFER_SHOWN = "REBIRTH_OFFER_SHOWN",
		REBIRTH_CELEBRATION_SEEN = "REBIRTH_CELEBRATION_SEEN",
		DRONE_CRATE = "DRONE_CRATE",
		ARTILLERY_HIT = "ARTILLERY_HIT",
		-- Shop / Offer Director / purchase funnel (revenue audit §19.2; SHOP_PROMPT and PURCHASE_RECEIPT exist above)
		SHOP_OPEN = "SHOP_OPEN",
		SHOP_TAB = "SHOP_TAB",
		OFFER_SHOWN = "OFFER_SHOWN",
		OFFER_RESULT = "OFFER_RESULT",
		PROMPT_CLOSED = "PROMPT_CLOSED", -- analytics only, never a grant
		PASS_OWNED = "PASS_OWNED",
		FIRST_PURCHASE = "FIRST_PURCHASE",
		SHORTFALL_CHIP = "SHORTFALL_CHIP",
		ANNOUNCE_SHOWN = "ANNOUNCE_SHOWN",
		-- Nations (cosmetic country; nations spec section 2). The IP-based suggestion is never logged, in any field.
		NATION_PICKER_SHOWN = "NATION_PICKER_SHOWN", -- source ("join" / "flagpole" / "settings")
		NATION_PICK = "NATION_PICK", -- exactly { id, source, first }
		NATION_LATER = "NATION_LATER", -- count (NationPrompts after this LATER)
		-- W3 step 2 Phase B: Jobs (OpsService; props: site, value, bags, drops, picked, lost)
		OPS_OPEN = "OPS_OPEN", -- a big site opened (OpsDirector)
		OPS_START = "OPS_START", -- a run went Active (breach / start / hack / plant / provoked)
		OPS_DONE = "OPS_DONE", -- a run finished (paid at completion or bags out)
		OPS_FAIL = "OPS_FAIL", -- lockdown / window / empty ring / abandoned
		BAG_GRAB = "BAG_GRAB",
		BAG_DROP = "BAG_DROP", -- the carrier died (or the deadline ran out: lost = true)
		BAG_PICKUP = "BAG_PICKUP",
		BAG_DELIVER = "BAG_DELIVER",
		-- claude-bud JOB 24 §10: funnel / custom events
		CASH_COLLECT = "CASH_COLLECT",
		ARMY_OPEN = "ARMY_OPEN",
		ARMY_ATTACK = "ARMY_ATTACK",
		TUTORIAL_SHOWN = "TUTORIAL_SHOWN",
		TUTORIAL_CLOSED = "TUTORIAL_CLOSED",
		MISSILE_STRIKE = "MISSILE_STRIKE",
		SESSION_END = "SESSION_END",
		-- claude-bud JOB 29
		ONBOARD_STEP = "ONBOARD_STEP",
		OFFLINE_EARNED = "OFFLINE_EARNED",
		NOTIF_OPTIN = "NOTIF_OPTIN",
		STREAK_DAY = "STREAK_DAY",
		ACTIVITY_START = "ACTIVITY_START",
		ACTIVITY_DONE = "ACTIVITY_DONE",
	},
}

return AnalyticsConfig
