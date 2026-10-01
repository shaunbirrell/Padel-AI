--!strict
--[[
	Economy tuning. See BALANCE.md for design intent.
	First ~10 minutes feel fast; progression slows after.
]]

local EconomyConfig = {
	StartingCash = 10000, -- v55 restore: healthy start (v20 era used 5000; DS v2 fresh profiles get this)
	StartingGold = 0,
	MinCash = 0,
	MinGold = 0,
	MaxCash = 1_000_000_000,
	MaxGold = 10_000_000,

	-- Passive income: base + sum(structureLevel * rate)
	-- Early-game pacing (first 10 min): start $10k → CC L1 ($1500) immediately →
	-- base $25/tick (~$300/min) + CC $15 → Barracks L1 ($2500) in ~1 min →
	-- then ~$60/tick sustains VehicleDepot / WeaponsFacility without feeling stuck.
	PassiveIncome = {
		TickSeconds = 5,
		BaseCashPerTick = 25, -- alone: ~300/min → Barracks L1 (2500) in ~50s with upgrades help
		-- Per structure level contribution to Cash/tick
		PerLevelRates = {
			CommandCenter = 15,
			Barracks = 20,
			VehicleDepot = 12,
			WeaponsFacility = 10,
			Helipad = 18,
			Dock = 14,
			Airfield = 22,
			DefensiveWalls = 5,
			Watchtowers = 6,
			Radar = 8,
			ResearchLab = 14,
			MissileDefense = 7,
			PowerStation = 16,
			Warehouse = 25,
			SpecialForcesFacility = 20,
		} :: { [string]: number },
	},

	-- Soft caps / multipliers
	PrestigeCashMultiplierPerLevel = 0.10, -- +10% cash gains per prestige (stacking; see PrestigeConfig)
	DailyRewardCashBonus = true,

	-- Capture stipend tuning lives in TerritoryConfig.CaptureStipend
	-- (periodic cash for owned territories / coastal oil).

	-- Contested outpost income: stacks recount from owned territories (stealable).
	-- F3 (owner's 11 features): shown to players as "Empire Tax". Every captured outpost (not the Home Outpost) is one
	-- stack: +MultPerStack on every non-exempt income reason; the player's own Home Outpost (TerritoryConfig.Starter)
	-- adds StarterPct and is never a stack; the total is capped at MaxStacks * MultPerStack (+50 %).
	-- EconomyService.EmpireTaxPct(p) is the whole-number total; it is mirrored (display only, written on change) to
	-- the player attribute Attribute. PersistClaims: saved claims are re-planted on join in any server (Neutral or
	-- NPC-held zones), released when the player leaves, dropped when another online player holds the zone; false =
	-- claims live only in the current server (lane Z switched it on; fb4 capture lane switched it off again: owner
	-- 2026-09-28, a rejoin must never bring an outpost back; TerritoryConfig.ReleaseOnLeave frees a leaver's zones).
	-- Toast args: ToastSecured / ToastLost (total %),
	-- ToastStolenFromYou / ToastStealGain (zone name, total %), ToastClaimHeld (zone name, holder name).
	OutpostIncomeBuff = {
		DisplayName = "Empire Tax",
		MultPerStack = 0.10, -- +10% per stack
		MaxStacks = 5, -- cap +50%
		StarterPct = 5, -- F10: the player's own Home Outpost, whole percent (not a stack)
		Attribute = "WE_EmpireTaxPct", -- player attribute, whole percent (0 = chip hidden)
		PersistClaims = false, -- F3: off since fb4 capture lane (owner: no outpost comes back on rejoin); true = lane Z re-plant
		ToastSecured = "Outpost taken  Empire Tax +%d%%",
		ToastLost = "Outpost lost  Empire Tax +%d%%",
		ToastStolenFromYou = "%s taken  Empire Tax +%d%%",
		ToastStealGain = "Took %s  Empire Tax +%d%%",
		ToastClaimHeld = "%s is held by %s",
		-- Legacy alias kept for older callers
		ToastTemplate = "Outpost secured — +%d%% Income (yours)",
	},

	-- F4 (owner's 11 features): one client-only, owner-only floating label on the nearest own producer (Training Yard,
	-- oil pumps) within RadiusStuds, re-picked ScanHz times a second, pulsing for PulseSeconds on each income tick.
	-- Text sizes are real px (world labels are not UIScaled); MaxDistance in studs (CLAUDE.md: <= 40). Off until
	-- lane Z (the client module ships with it); on since lane Z (reversible).
	ProducerLabels = {
		Enabled = true,
		RadiusStuds = 24,
		ScanHz = 4,
		PulseSeconds = 0.6,
		TextSize = 18,
		SubSize = 14,
		MaxDistance = 24,
	},

	-- PvP ATM raid: touch another player's WE_MoneyCollector to steal PendingCash.
	AtmRaid = {
		Enabled = true,
		StealFraction = 0.10, -- 10% of victim PendingCash
		AtmRaidCooldownSeconds = 60, -- per thief→victim pair
		MaxDistanceStuds = 14, -- server distance check to collector part
		MinStealCash = 1,
		ToastThief = "ATM RAID +$%d (10%%) from %s — 1m cooldown",
		ToastVictim = "ATM RAIDED −10%% by %s (−$%d)",
		ToastCooldown = "ATM raid cooldown — %ds left",
	},

	-- atmprompt (ASSUMPTIONS ATM-6): the ATM's "Collect" ProximityPrompt (MoneyCollectorService; these were literals).
	-- Its keys must differ from the cash plate beside it (ManualDropperConfig.PromptKeyboardKey / PromptGamepadKey:
	-- F / ButtonB): with one shared key and OnePerButton only the closer prompt showed, on PC and on phones. With distinct
	-- keys each is the only prompt on its key there, so both pills show side by side and each key triggers only its own
	-- (BuyPathStatic pins the keys apart). HoldDuration 0 = one tap, as before.
	AtmCollectPrompt = {
		ActionText = "Collect",
		ObjectText = "ATM",
		HoldDuration = 0,
		MaxActivationDistance = 14,
		KeyboardKey = Enum.KeyCode.E,
		GamepadKey = Enum.KeyCode.ButtonX,
		Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton,
	},
	--[[ claude-bud JOB 29 (2026-09-30): OFFLINE EARNINGS. When the save loads, the server pays for the time away since
		the last save was written (profile.LastSeenUnix, os.time(), stamped by DataService on every write). The formula is
		the live passive tick's: BaseService.ComputePassiveIncomePerTick x EconomyService.GetCashMult(player, "passive"),
		once per PassiveIncome.TickSeconds, for the seconds away (capped at CapSeconds), x Share, x (1 + PremiumBonus)
		for Roblox Premium. It is paid straight into PendingCash (the ATM, like the tick) with reason "offline" (the
		multiplier is already in, so never applied twice), then a "Welcome back: +$X while away" card shows.
		No payout: first join (no LastSeenUnix), a negative gap, or a gap under MinSeconds.
		Kill switch: Enabled = false (no payout, no card). OwnerFirst as TutorialConfig.FastStart. No Robux option. ]]
	OfflineEarnings = {
		Enabled = true,
		OwnerFirst = false, -- codebot_v136 launch (owner 2026-09-30 14:17): everyone
		Share = 0.25,
		CapSeconds = 8 * 3600,
		MinSeconds = 300,
		PremiumBonus = 0.10,
		ShowDelaySeconds = 6, -- the card: after the save loads (and after the onboarding hold)
		--[[ claude-bud JOB 49 part B (2026-10-01): "Welcome back! Collect $X". Owner-first; OFF = the JOB 29 card. The
			card shows the real server amount, the time away and "(capped at N h)"; COLLECT draws the gold line to his
			own ATM (ConsoleWaypoint.ShowAtm: the money is already in the ATM; no travel, no second claim). ]]
		Card = {
			Enabled = true,
			OwnerFirst = false, -- Code Bot v177 (Shaun approved 2026-10-01): everyone (was NEW-OWNER-FIRST, claude-bud JOB 49)
		},
		--[[ claude-bud JOB 49 B: the Robux SIDEGRADE hook, DISABLED. With the MonetizationConfig.DevProducts.OfflineCap2x
			entitlement (Id 0 + no price until Shaun approves one: never prompted, never in the Shop) the cap TIME is
			CapMult x CapSeconds. It never raises Share and gives no combat stat. ]]
		CapBoost = {
			Enabled = false,
			OwnerFirst = true, -- NEW-OWNER-FIRST (claude-bud JOB 49): stays off until Shaun approves a price
			ProductKey = "OfflineCap2x",
			CapMult = 2,
		},
	},
}

return EconomyConfig
