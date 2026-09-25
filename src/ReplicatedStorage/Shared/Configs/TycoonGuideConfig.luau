--!strict
--[[
	v72 tycoon guide: "which button next, and what does it do to my income" (owner feedback, sister's LV1/LV2 phone
	screenshots).

	The SERVER picks one next buy per player (Shared/Util/TycoonMath.PickNext) and stamps it on the Player as
	WE_NextBuy = "<Id>:<TargetLevel>" (or "Soldier:0", or "" when nothing is left / the guide is off). Clients only
	render it: the objective chip after the tutorial, the gold NEXT tag on that console and on its Base panel row, and
	the GO line to that console on the player's OWN plot. The pick is advice only; the server re-checks every buy.
	Every income number shown is dollars per second from config (TycoonMath) x the server-stamped WE_IncomeMult,
	floored to 0.1 below $10/s and to whole dollars from $10/s up, so a displayed rate never over-promises.

	Copy (Text): device-neutral (never a key name, "click" or "tap"), <= 42 characters per string, and no middle dot
	or arrow characters (the Display font has neither): parts are separated by two spaces. The phone-surface keys (ConsoleTag, BuyLane)
	live here, not in HudConfig.

	Enabled = false until integration (the lead flips it together with BusinessConfig.Enabled).

	F5 (owner's 11 features, lane K2): PickMode "Cheapest" = the one pointer is the cheapest unpaid console pad
	(TycoonMath.PickCheapest: the lowest next price among open, non-maxed structures and businesses; never soldiers or
	Robux items; affordability ignored). It drives WE_NextBuy, so the NEXT chip, the console NEXT tag, the Base-panel
	badge and the floor chevrons (Chevrons below) all agree. PickMode "Score" = the v72 Opening + payback score.
]]

local TycoonGuideConfig = {
	Enabled = true,

	-- F5: "Cheapest" (TycoonMath.PickCheapest; ties -> lower target level, then StructureOrder) | "Score" (v72 below)
	PickMode = "Cheapest",
	-- PickMode "Score" rules (TycoonMath.PickNext). Opening: the first entry that is open now (requirements met, level
	-- not owned) wins. After the Opening the candidate with the lowest score wins:
	--   score = WaitWeight * secondsUntilAffordable(wallet + ATM) + cost / ((gainPerTick + UnlockValuePerTick) / 5)
	Opening = { "CommandCenter:1", "AmmoWorks:1", "WeaponsFacility:1", "ArmsCrateLine:1", "Barracks:1" },
	WaitWeight = 1.0,
	IncludeSoldiers = true, -- "Score" only: "Recruit soldiers" is a candidate (ARMY opens the Army panel); "Cheapest" never
	SoldierCandidateId = "Soldier", -- WE_NextBuy = "Soldier:0"
	-- Soldiers are offered only while training income (soldiers x SoldierConfig.TrainingIncome.CashPerSoldierPerTick)
	-- is below this share of the total base income per tick (passive + training + plot oil).
	SoldierMaxShare = 0.34,
	-- Extra $ per tick the pick pretends a level earns, for what it unlocks. Ranking only; never shown, never paid.
	UnlockValuePerTick = {
		CommandCenter = { [1] = 1000, [2] = 40, [3] = 40 },
		VehicleDepot = { [1] = 20, [2] = 30 },
		DefensiveWalls = { [1] = 10 },
		Helipad = { [1] = 20 },
		Dock = { [1] = 15 },
	} :: { [string]: { [number]: number } },

	-- Server re-pick: after a purchase, an army change, plot ready and profile load, and every RepickSeconds. A
	-- challenger replaces the current pick only when its score < Hysteresis x the current pick's score, so the chip
	-- never flickers. WE_NextBuy is written only when the value changes.
	RepickSeconds = 15,
	Hysteresis = 0.75,
	ShowAfterTutorial = true, -- the chip takes the tutorial's slot once TutorialComplete (one message at a time)

	-- WE_IncomePerSec (EconomyService): the last amount granted per steady reason, summed, / TickSeconds (what the
	-- ATM really receives, multipliers included). A reason that misses this many ticks drops out (oil after a rebirth).
	SteadyIncomeReasons = { passive = true, training = true, plot_oil = true } :: { [string]: boolean },
	SteadyIncomeExpireTicks = 2,

	-- What a level unlocks besides income (BUY line 2 / chip hint after the $/s). <= 18 characters each.
	Unlocks = {
		CommandCenter = { [1] = "6 new buildings", [2] = "Radar + Lab", [3] = "Missile strikes" },
		Barracks = { [1] = "+5 army cap", [2] = "+5 army cap", [3] = "Special Forces", [4] = "+5 army cap", [5] = "+5 army cap" },
		VehicleDepot = { [1] = "Ground vehicles", [2] = "Helipad + Dock", [3] = "Heavy vehicles" },
		DefensiveWalls = { [1] = "Walls + guards", [2] = "Oil pumps", [3] = "Anti-heli roof", [4] = "Gate turrets" },
		Watchtowers = { [1] = "Corner towers" },
		Radar = { [2] = "Missile Defense" },
		ResearchLab = { [1] = "Research", [2] = "Special Forces" },
		Helipad = { [1] = "Helicopters", [2] = "Airfield" },
		Dock = { [1] = "Boats" },
		Airfield = { [1] = "Planes" },
		MissileDefense = { [1] = "Missile shield" },
	} :: { [string]: { [number]: string } },
	-- Unlock lines that only exist while BusinessConfig.Enabled (TycoonMath.UnlockText merges them)
	BusinessUnlocks = {
		WeaponsFacility = { [1] = "Arms Crate Line" },
	} :: { [string]: { [number]: string } },

	-- Upper-case short names (<= 10 characters) for the BUY button / console tag when the full name does not fit.
	-- Businesses carry their own (BusinessConfig ShortName).
	ShortNames = {
		CommandCenter = "COMMAND",
		Barracks = "BARRACKS",
		VehicleDepot = "DEPOT",
		WeaponsFacility = "WEAPONS",
		PowerStation = "POWER",
		Warehouse = "WAREHOUSE",
		DefensiveWalls = "WALLS",
		Watchtowers = "TOWERS",
		Radar = "RADAR",
		ResearchLab = "LAB",
		Helipad = "HELIPAD",
		Dock = "DOCK",
		Airfield = "AIRFIELD",
		MissileDefense = "AA DEFENSE",
		SpecialForcesFacility = "SPEC OPS",
	} :: { [string]: string },

	Text = {
		-- rates / prices (TycoonMath.PerSecText / RateText / ShortCash)
		PerSec = "+$%s/s", -- "+$3.3/s"
		Rate = "$%s/s", -- "$46/s" (Base panel subtitle)
		Pop = "+$%s", -- "+$16" over a business bin on each passive tick
		-- objective chip (after the tutorial, inside your own plot only)
		ChipTitle = "NEXT: %s", -- "NEXT: Ammo Works"
		ChipTitleUpgrade = "NEXT: %s Lv %d", -- "NEXT: Barracks Lv 2"
		ChipHintBuy = "%s  %s", -- "$600  +$3.3/s"
		ChipHintBuyUnlock = "%s  %s  %s", -- "$1,500  +$3.1/s  6 new buildings"
		ChipHintCollect = "Collect %s at your ATM", -- "Collect $1,240 at your ATM"
		ChipHintEarning = "%s  ready in %s", -- "+$3.3/s  ready in 0:42"
		ChipGo = "GO",
		ChipGoCollect = "ATM",
		ChipHide = "Hide",
		SoldierTitle = "NEXT: Recruit soldiers",
		SoldierHint = "%s each  %s each", -- "$500 each  +$1.6/s each"
		SoldierGo = "ARMY",
		-- BUY button (two lines: Display font line 1, Body font line 2)
		BuyBuild = "BUILD %s  %s", -- "BUILD AMMO WORKS  $600"
		BuyBuildShort = "BUILD  %s", -- "BUILD  $1,500" (the buy unlocks something: line 2 names it)
		BuyUpgrade = "UPGRADE %s LV %d  %s", -- "UPGRADE AMMO LV 2  $2,000"
		BuyIncome = "%s income", -- "+$3.3/s income"
		BuyIncomeUnlock = "%s  %s", -- "+$3.1/s  6 new buildings"
		BuyCollect = "COLLECT %s AT ATM", -- amber; the button fires nothing, it draws the line to your ATM
		BuyCollectLine2 = "%s when built", -- "+$3.3/s when built"
		BuyNeed = "NEED %s MORE", -- red: "NEED $1,240 MORE"
		BuyNeedLine2 = "%s  ready in %s", -- "+$3.3/s  ready in 0:42"
		CollectToast = "Follow the line to your ATM",
		-- console tag (owner-only, stud-scaled)
		TagTitleNext = "NEXT  %s", -- gold: "NEXT  AMMO WORKS"
		TagLine = "%s  %s", -- "$600  +$3.3/s" (green if wallet + ATM covers it, red otherwise)
		Locked = "Needs %s %d", -- "Needs Weapons Facility 1"
		MaxLevel = "MAX LEVEL",
		-- console screen (the 15 buildings only): "WAREHOUSE\n$3.2K\n+$5.2/s"
		ScreenLines = "%s\n%s\n%s",
		-- purchase toast: "Purchase SUCCESSFUL! Ammo Works Lv 1" .. ToastSuffix
		ToastSuffix = "  %s", -- "  +$3.3/s"
		-- Base panel
		PanelHeader = "WAR BUSINESSES",
		PanelSubtitle = "Income %s  buy at each console", -- "Income $46/s  buy at each console"
		PanelRowBuild = "Build %s  %s", -- "Build $600  +$3.3/s"
		PanelRowUpgrade = "Lv %d -> %d  %s  %s", -- "Lv 1 -> 2  $2,000  +$4.2/s"
		NextTag = "NEXT", -- the gold badge on the pick's Base panel row
		-- cash pill suffix "13,594  +$24/s": TycoonMath.RatePerSecText(WE_IncomePerSec) (PerSec)
	},

	-- Objective chip visibility (HudLayout flags; AtConsole is set by the BUY button while it is up)
	ChipRule = {
		ShowWhen = { "InOwnPlot" },
		HideWhen = { "Tutorial", "Modal", "Driving", "Dead", "RecentCombat", "AtConsole" },
	},
	AtConsoleFlag = "AtConsole",

	-- Phone surfaces (v72; here, not in HudConfig)
	ConsoleTag = {
		StudsW = 10, -- stud-scaled BillboardGui (shrinks with distance)
		StudsH = 2.6,
		DistanceLowerLimit = 10,
		MaxDistanceBuild = 18, -- unowned structure (BUILD)
		MaxDistanceUpgrade = 14, -- owned structure (UPGRADE)
		NextMaxDistance = 40, -- the pick's console
		NextColor = Color3.fromRGB(255, 208, 64),
	},
	BuyLane = {
		ThumbZoneFrac = 0.40, -- the BUY button's left edge stays right of 40% of the safe-area width ...
		ClearPx = 8, -- ... plus this many real px (TycoonMath.ActionLaneShiftV)
		TouchSize = Vector2.new(300, 72), -- v (x 0.70 on a phone = 210 x 50 real px)
	},
	AutoGuideIdleSeconds = 12, -- Build / Collect state, this long idle, farther than AutoGuideMinStuds: GO once per pick
	AutoGuideMinStuds = 20,
	HideSeconds = 300, -- "Hide" hides the chip this long, or until the next purchase acknowledgement
	TextRefreshHz = 2, -- cash pill +$/s suffix and console tags
	EtaRefreshHz = 1, -- "ready in m:ss" on the chip / BUY button
	PillIncome = true, -- "+$N/s" suffix on the cash pill (green, 20 v, not tappable)

	--[[ F5 floor chevrons (Client/Modules/NextPadChevrons, lane G): client-only, owner-only gold floor bars that lead
		from the player to TycoonMath.ApproachPoint of the pick (WE_NextBuy, else the local PickCheapest), inside the own
		plot only. Two bars at +-BarAngleDeg make one chevron; Count chevrons SpacingStuds apart, the first LeadStuds
		ahead of the player, the last StopShortStuds before the target; none within HideWithinStuds of it; points inside
		a TycoonMath.Footprints rectangle are skipped. Re-laid at RefreshHz only when the player moved
		MoveThresholdStuds or the target changed (BulkMoveTo, a 2 x Count part pool under the camera; no Neon, light,
		Beam or GUI; CastShadow off). FollowTutorial: while the tutorial runs they follow the active step instead
		(TycoonMath.GuideTarget: a PadBuy step's own pad, the Income step's ATM, else none). Hidden while any HideWhen
		flag is set (HudLayout flags; "Drawn" = weapon out). Enabled = false until integration (lane Z). ]]
	Chevrons = {
		Enabled = false,
		Count = 5,
		SpacingStuds = 5,
		LeadStuds = 6,
		StopShortStuds = 4,
		HideWithinStuds = 10,
		DoorLeadStuds = 5, -- walk-in approach point: this far out of the front door (TycoonMath.ApproachPoint)
		RefreshHz = 4, -- <= 10 (UI refresh cap)
		MoveThresholdStuds = 1.5,
		RetargetRetrySeconds = 1, -- the target pad is not streamed in yet: retry this often
		BarSize = Vector3.new(0.35, 0.08, 2.4),
		BarAngleDeg = 45,
		Lift = 0.12, -- above the pad top
		Color = Color3.fromRGB(255, 208, 64),
		TransparencyNear = 0.2,
		TransparencyFar = 0.55,
		HideWhen = { "Driving", "Dead", "RecentCombat", "Drawn", "Modal", "AtConsole" } :: { string },
		FollowTutorial = true,
	},
}

return TycoonGuideConfig
