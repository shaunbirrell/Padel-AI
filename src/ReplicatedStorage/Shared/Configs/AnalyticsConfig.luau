--!strict

local AnalyticsConfig = {
	Enabled = true,
	-- JOB 61: one server-side schema for every Roblox AnalyticsService call. These names are
	-- deliberately SKU-like and contain no player/name/device data.
	Economy = {
		Currencies = { "Cash", "Gold" },
		TransactionTypes = { IAP = "IAP", Gameplay = "Gameplay", Shop = "Shop", TimedReward = "TimedReward", Onboarding = "Onboarding" },
		SourceSKUs = {
			passive = "base_income", training = "base_income", plot_oil = "base_income", collector = "base_income",
			collect = "cash_collect", offline = "offline_cash", daily = "daily_reward", mission = "mission_reward",
			timed_mission = "mission_reward", bank_raid = "raid_loot", atm_raid = "raid_loot", army_raid = "raid_loot",
			endgame_reward = "contract_reward", comeback = "return_sequence", onboarding = "onboarding_reward",
		},
		SinkSKUs = {
			upgrade_ = "building_upgrade", recruit_ = "unit_recruit", army_ = "army_order", unit_ = "unit_purchase",
			vehicle_ = "vehicle_purchase", weapon_ = "weapon_purchase", research_ = "research_upgrade",
			defense_ = "defence_upgrade", defence_ = "defence_upgrade", gate_ = "defence_upgrade",
			reroll = "mission_reroll", nuke_ = "defence_upgrade", missile_ = "defence_upgrade",
		},
	},
	Onboarding = {
		Enabled = true,
		MaxFirstSessionSeconds = 900,
		Steps = {
			{ Name = "joined", Event = "PLAYER_JOIN" },
			{ Name = "base_claimed", Event = "BASE_CLAIMED" },
			{ Name = "first_collect", Event = "CASH_COLLECT" },
			{ Name = "first_upgrade", Event = "FIRST_UPGRADE" },
			{ Name = "first_recruit", Event = "SOLDIER_RECRUIT" },
			{ Name = "first_army_order", Event = "ARMY_ATTACK" },
			{ Name = "first_raid_or_attack", Event = "RIVAL_RAID_WON" },
			{ Name = "reached_5_minutes", Event = "REACHED_5_MINUTES" },
		},
	},
	Funnels = {
		Shop = { Name = "Shop", Steps = { "open_shop", "view_item", "prompt_purchase", "purchase_complete" } },
		Rebirth = { Name = "Rebirth", Steps = { "available", "opened", "confirmed" } },
	},
	Privacy = { ExcludeAdminUserIds = true, NeverLogPII = true },
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
		-- JOB 61 onboarding is the only production onboarding sequence. Legacy event names below
		-- remain valid custom events, but do not create extra funnel rows.
		Funnel = {
			{ Step = "joined", Events = { "PLAYER_JOIN" } },
			{ Step = "base_claimed", Events = { "BASE_CLAIMED" } },
			{ Step = "first_collect", Events = { "CASH_COLLECT" } },
			{ Step = "first_upgrade", Events = { "FIRST_UPGRADE" } },
			{ Step = "first_recruit", Events = { "SOLDIER_RECRUIT" } },
			{ Step = "first_army_order", Events = { "ARMY_ATTACK" } },
			{ Step = "first_raid_or_attack", Events = { "RIVAL_RAID_WON", "BANK_RAID" } },
			{ Step = "reached_5_minutes", Events = { "REACHED_5_MINUTES" } },
		},
		EconomyFlushSeconds = 60,
		-- reason (prefix) -> Enum.AnalyticsEconomyTransactionType name; anything else = Gameplay
		EconomyTypes = { upgrade_ = "Shop", weapon_ = "Shop", vehicle_ = "Shop", research_ = "Shop", recruit_ = "Shop", devproduct = "IAP",
			daily = "TimedReward", premium_daily = "TimedReward", spinner = "TimedReward", code = "Gameplay", onboarding = "Onboarding", offline = "TimedReward" }, -- claude-bud JOB 29: offline
		-- in-house event -> Roblox custom event name (value = the Value prop, else 1; field 1 = the Field prop)
		Custom = {
			SHOP_OPEN = { Name = "ShopOpened" },
			SHOP_PROMPT = { Name = "ProductPrompted", Field = "productKey" },
			PROMPT_CLOSED = { Name = "PromptCancelled", Field = "kind" },
			PURCHASE_RECEIPT = { Name = "RobuxPurchase", Value = "currencySpent", Field = "productKey", Field2 = "perMinBucket" }, -- claude-bud JOB 42: + the time-pack income bucket
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
			-- claude-bud JOB 40 part D: the rate reminder (never a "liked" event: there is no such signal)
			RATE_PROMPT_SHOWN = { Name = "rate_prompt_shown", Field = "trigger" },
			RATE_PROMPT_ANSWER = { Name = "rate_prompt_answer", Field = "answer" },
			-- claude-bud JOB 41: the Guided first minutes (Funnels.FirstMinutes is logged separately)
			GUIDED_STEP = { Name = "GuidedStepSeconds", Value = "seconds", Field = "step" },
			GUIDED_SKIPPED = { Name = "GuidedSkipped", Field = "step" },
			GUIDED_STUCK = { Name = "GuidedStuck", Field = "step" },
			RECRUIT_PACK_OFFERED = { Name = "RecruitPackOffered", Field = "trigger" }, -- claude-bud JOB 41 B
			-- claude-bud JOB 48: the Hook (TutorialConfig.Guided.Hook): the 3-minute wall + time to the first fight win
			SESSION_MILESTONE = { Name = "SessionMilestone", Value = "sec", Field = "sec" },
			FTUE_TIME_TO_FIGHT = { Name = "FtueTimeToFight", Value = "seconds" },
			GOAL_FALLBACK = { Name = "GoalFallback", Field = "reason" }, -- the raid goal fell back (no rival allowed)
			-- claude-bud JOB 49: reasons to come back (streak / offline / missions / the return day)
			STREAK_CLAIMED = { Name = "StreakClaimed", Value = "day", Field = "grace" },
			STREAK_RESET = { Name = "StreakReset", Field = "lastDay" },
			OFFLINE_COLLECTED = { Name = "OfflineCollected", Value = "cash", Field = "capped" },
			BASE_CLAIMED = { Name = "BaseClaimed" },
			MISSION_DONE = { Name = "MissionDone", Field = "type" },
			DAILY_MISSION_COMPLETED = { Name = "DailyMissionCompleted", Field = "mission" },
			RETURN_SEQUENCE_CLAIMED = { Name = "ReturnSequenceClaimed", Value = "cash", Field = "days" },
			MISSIONS_ALL_DONE = { Name = "MissionsAllDone", Value = "cash" },
			MISSION_REROLL = { Name = "MissionReroll", Field = "kind" },
			RETURN_DAY = { Name = "ReturnDay", Value = "days", Field = "guidedDone" },
			-- claude-bud JOB 41 C: rival targets (PvP rate = RivalSendTapped per session)
			RIVAL_LIST_OPENED = { Name = "RivalListOpened" },
			RIVAL_SEND_TAPPED = { Name = "RivalSendTapped", Field = "verdict" },
			RIVAL_RAID_WON = { Name = "RivalRaidWon", Value = "loot" },
			STREAK_DAY = { Name = "StreakDay", Value = "day" },
			-- claude-bud JOB 31: site activities
			ACTIVITY_START = { Name = "ActivityStarted", Field = "activity" },
			ACTIVITY_DONE = { Name = "ActivityFinished", Value = "seconds", Field = "activity" },
			-- claude-bud JOB 33: the rebirth funnel (value = level; field = minutes of play in this life) + zones / nukes
			REBIRTH_AVAILABLE = { Name = "rebirth_available", Value = "level", Field = "minutes" },
			REBIRTH_OPENED = { Name = "rebirth_opened", Value = "level", Field = "minutes" },
			REBIRTH_CONFIRMED = { Name = "rebirth_confirmed", Value = "level", Field = "minutes" },
			REBIRTH_ZONE_BUILT = { Name = "RebirthZoneBuilt", Value = "level", Field = "zone" },
			-- Code Bot v153: the offer / pass funnel in Creator Hub (which offers were SEEN, dropped unseen, and bought).
			-- ProductPrompted / RobuxPurchase read productKey (MonetizationService now sends it; it sent only `key`).
			OFFER_SHOWN = { Name = "OfferShown", Field = "productKey" }, -- the client confirmed the card showed
			OFFER_RESULT = { Name = "OfferDropped", Field = "productKey" }, -- sent but never shown (re-queued)
			PASS_OWNED = { Name = "PassBought", Value = "price", Field = "productKey" }, -- a confirmed game pass purchase
		},
		MaxCustomPerMinute = 100,
		PerPlayerPerMinute = 10,
		-- the client may report only these (RequestAnalyticsEvent; a few per minute per player)
		ClientEvents = {
			ShopOpened = "SHOP_OPEN", ShopItemViewed = "SHOP_ITEM_VIEW", ArmyOpened = "ARMY_OPEN",
			TipShown = "TUTORIAL_SHOWN", TipClosed = "TUTORIAL_CLOSED", RebirthOpened = "REBIRTH_OPENED",
		}, -- claude-bud JOB 33: + RebirthOpened
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
		BASE_CLAIMED = "BASE_CLAIMED",
		REACHED_5_MINUTES = "REACHED_5_MINUTES",
		DAILY_MISSION_COMPLETED = "DAILY_MISSION_COMPLETED",
		RETURN_SEQUENCE_CLAIMED = "RETURN_SEQUENCE_CLAIMED",
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
		RATE_PROMPT_SHOWN = "RATE_PROMPT_SHOWN", -- claude-bud JOB 40 D
		RATE_PROMPT_ANSWER = "RATE_PROMPT_ANSWER",
		GUIDED_STEP = "GUIDED_STEP", -- claude-bud JOB 41
		GUIDED_SKIPPED = "GUIDED_SKIPPED",
		GUIDED_STUCK = "GUIDED_STUCK",
		RECRUIT_PACK_OFFERED = "RECRUIT_PACK_OFFERED", -- claude-bud JOB 41 B
		RIVAL_LIST_OPENED = "RIVAL_LIST_OPENED", -- claude-bud JOB 41 C
		RIVAL_SEND_TAPPED = "RIVAL_SEND_TAPPED",
		RIVAL_RAID_WON = "RIVAL_RAID_WON",
		STREAK_DAY = "STREAK_DAY",
		ACTIVITY_START = "ACTIVITY_START",
		ACTIVITY_DONE = "ACTIVITY_DONE",
	},
}

return AnalyticsConfig
