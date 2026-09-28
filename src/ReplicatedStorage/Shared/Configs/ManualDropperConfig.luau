--!strict
--[[
	Early-game manual cash droppers near Money Collector + Training Yard (prompt on touch, ClickDetector on PC).
	Server-authoritative; client only fires ClickDetector / ProximityPrompt.
	v71 (HUD v70 spec §5): the price tag reads "$15" (no mouse wording — wrong on phones), owner-only, stud-scaled; the
	"+$15" pop is owner-only too; the plate keeps its glow but no PointLight.

	droppers v1b (spec_droppers.md §3.8, owner decision OD-4 = A): one tap (the prompt or the plate's ClickDetector,
	still instant: PromptHoldDuration 0) pays a bundle of BundleAwards awards, AwardAmount x BundleAwards = $75, into
	the ATM. The bundle needs BundleAwards in BOTH budget buckets (no partial bundle); the award size, cooldown, rate
	limit and the minute / hour budgets are unchanged, so the plate's cap on money is unchanged ($450 a burst minute,
	$18,000 in the first hour from full buckets, $9,000 an hour after). BundleAwards = 1 is today's $15 tap (option E):
	one line to revert. BundleAwards must stay within 1..MaxAwardsPerMinute (BuyPathStatic rule; the service clamps).
	The server no longer builds the "+$" pop or the money-bag model: it sends the grabber one owner-only unreliable
	DropperFx packet and the client draws the bundle and the world "+$75" pop with its chirp on EVERY paid grab (the
	Bundle / Pop / Fx keys below are read by the client, Client/Modules/ProductionFx). When the ATM collects the grab at
	once, its own pill float shows it too, as today (revision 3: at least one "+$", at most two). The plate inset is
	plain green (PlateNeon = false). While the budget holds no bundle the server keeps the Player attribute
	RechargeAttribute (the server time when the next bundle is ready), so "Recharging" survives a lost packet and a
	same-server rejoin; it is a look only, never money.
]]

local ManualDropperConfig = {
	Enabled = true,

	-- Award (PendingCash). Prefer AwardAmount; else random [MinAward, MaxAward].
	MinAward = 10,
	MaxAward = 25,
	AwardAmount = 15,

	-- droppers v1b (OD-4 = A): awards paid per grab. 5 x $15 = a $75 bundle; 1 = today's $15 tap (option E).
	-- Must satisfy 1 <= BundleAwards <= MaxAwardsPerMinute (BuyPathStatic rule; ManualDropperService clamps too).
	BundleAwards = 5,

	CooldownSeconds = 0.35,
	RateLimitRate = 4,
	RateLimitBurst = 3,

	-- v69 income budget per player (both droppers share it) so an auto-clicker can't farm all night.
	-- Refilling buckets: a full minute bucket gives a quick burst, then it refills at N/60 per second;
	-- the hour bucket caps long sessions at ~MaxAwardsPerHour (600 x $15 = $9k/h, below base passive).
	-- droppers v1b: counted in awards; a bundle takes BundleAwards from both buckets.
	MaxAwardsPerMinute = 30,
	MaxAwardsPerHour = 600,
	-- droppers v1b: short line; NotificationConfig's Throttle rule matches "^Cash drop is recharging"
	BudgetEmptyToast = "Cash drop is recharging",
	BudgetEmptyToastCooldown = 20,

	CollectorOffset = Vector3.new(-5.5, 0, 4),
	YardOffset = Vector3.new(6, 0, -4),

	PromptActionText = "Grab Cash",
	PromptObjectText = "Cash Drop",
	PromptMaxDistance = 12,
	PromptHoldDuration = 0,
	-- atmprompt (ASSUMPTIONS ATM-6): the plate's own prompt keys. They differ from the ATM "Collect" prompt 7.5 studs away
	-- (EconomyConfig.AtmCollectPrompt: E / ButtonX), so under OnePerButton each is the only prompt on its key there: both
	-- pills show and each key triggers only its own (BuyPathStatic pins them apart). F matches the terminals' second prompt
	-- key; gamepad B, not Y, because Y is Reload (HudConfig.Keys.Gamepad) and would be swallowed beside any plate.
	PromptKeyboardKey = Enum.KeyCode.F,
	PromptGamepadKey = Enum.KeyCode.ButtonB,
	PromptExclusivity = Enum.ProximityPromptExclusivity.OnePerButton,

	PartSize = Vector3.new(2.4, 1.2, 2.4),
	PartColor = Color3.fromRGB(40, 140, 70),
	NeonAccentColor = Color3.fromRGB(90, 255, 120), -- the inset colour (plain SmoothPlastic since v1b: PlateNeon)
	-- droppers v1b (OD-6): the plate inset "DropNeon" (name kept) is SmoothPlastic, not Neon (world Neon 306 -> 294)
	PlateNeon = false,
	BillboardLabel = "$", -- v71: device-neutral (the old tag told phone players to use a mouse); the owner sees "$75"
	LabelMaxDistance = 30, -- studs (WorldLabel caps at 40)
	LabelStuds = Vector2.new(3, 1.2), -- the tag's box, studs

	PopupDuration = 0.55,
	PopupRiseStuds = 3.2,

	-- droppers v1b: the client plate effect (spec §3.7 / §3.8). The server only sends the owner-only DropperFx packet
	-- (drop point, amount, left, eta); ProductionFx validates it and draws the bundle and the "+$" pop on every grab.
	FxEvent = true, -- false: no DropperFx packet (the grab still pays; the client then shows nothing over the plate)
	RechargeTag = "Recharging", -- the plate tag while the budget holds no bundle (client write; the pill hides)
	-- revision 3: Player attribute the server keeps while the budget holds no bundle = Workspace:GetServerTimeNow() when
	-- the next one is ready (nil once it holds one). Stamped on the paid grab that empties it, on a refused tap and on a
	-- same-server rejoin, so "Recharging" survives a lost DropperFx packet and a rejoin. A look only: never money.
	RechargeAttribute = "WE_DropRechargeAt",
	BundleSize = Vector3.new(1.4, 0.6, 0.9), -- the pooled green cash bundle, studs
	BundleColor = Color3.fromRGB(86, 150, 80),
	BundleDropStuds = 3.5, -- the bundle falls this far onto the drop point
	BundleSeconds = 0.35, -- in this long (one reused Tween), then hides
	DropPointClearance = 0.3, -- studs above a dressed plate's model (bounding-box top) where the bundle lands
	PopTextPx = 20, -- the world "+$N" pop (real px; world labels are 14-20)
	PopColor = Color3.fromRGB(80, 255, 120), -- the HEAD "+$15" pop colour
	PopGlowColor = Color3.fromRGB(8, 36, 14), -- its UIStroke "CashPopGlow" (HEAD look)
	PopGlowThickness = 1.4,
	-- refix 1: a pop whose rise would pass the pop's MaxDistance (LabelMaxDistance) from the camera, i.e. a zoomed-out
	-- phone camera, is drawn this many studs from the camera on the line of sight to the plate (it still covers the plate
	-- on screen and is always drawn; the chirp plays there). The client caps it at LabelMaxDistance - PopupRiseStuds - 1.
	PopNearCameraStuds = 24,
	FxMaxPayloadAmount = 10000, -- the client ignores a DropperFx amount outside 1..this
	FxMaxPayloadStuds = 60, -- or a drop point farther than this from the character
}

return ManualDropperConfig
