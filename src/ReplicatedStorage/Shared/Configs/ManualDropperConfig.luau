--!strict
--[[
	Early-game manual click/proximity droppers near Money Collector + Training Yard.
	Server-authoritative; client only fires ClickDetector / ProximityPrompt.
]]

local ManualDropperConfig = {
	Enabled = true,

	-- Award (PendingCash). Prefer AwardAmount; else random [MinAward, MaxAward].
	MinAward = 10,
	MaxAward = 25,
	AwardAmount = 15,

	CooldownSeconds = 0.35,
	RateLimitRate = 4,
	RateLimitBurst = 3,

	-- v69 income budget per player (both droppers share it) so an auto-clicker can't farm all night.
	-- Refilling buckets: a full minute bucket gives a quick burst, then it refills at N/60 per second;
	-- the hour bucket caps long sessions at ~MaxAwardsPerHour (600 x $15 = $9k/h, below base passive).
	MaxAwardsPerMinute = 30,
	MaxAwardsPerHour = 600,
	BudgetEmptyToast = "Cash drop is recharging — the ATM keeps earning meanwhile",
	BudgetEmptyToastCooldown = 20,

	CollectorOffset = Vector3.new(-5.5, 0, 4),
	YardOffset = Vector3.new(6, 0, -4),

	PromptActionText = "Grab Cash",
	PromptObjectText = "Cash Drop",
	PromptMaxDistance = 12,
	PromptHoldDuration = 0,

	PartSize = Vector3.new(2.4, 1.2, 2.4),
	PartColor = Color3.fromRGB(40, 140, 70),
	NeonAccentColor = Color3.fromRGB(90, 255, 120),
	BillboardLabel = "CLICK · $",

	PopupDuration = 0.55,
	PopupRiseStuds = 3.2,
}

return ManualDropperConfig
