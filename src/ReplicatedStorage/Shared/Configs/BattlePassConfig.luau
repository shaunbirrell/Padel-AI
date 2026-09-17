--!strict

local BattlePassConfig = {
	SeasonId = "S1_Foundation",
	MaxLevel = 50,
	XPPerLevel = 1000,
	PremiumProductId = 0, -- placeholder
	FreeTrack = {
		-- sparse examples; full track filled in later seasons
		[1] = { Cash = 500 },
		[5] = { Cash = 2000 },
		[10] = { Gold = 5 },
		[25] = { Cash = 15000 },
		[50] = { Gold = 25 },
	},
	PremiumTrack = {
		[1] = { Cash = 1500 },
		[5] = { Gold = 3 },
		[10] = { Cash = 10000 },
		[25] = { Gold = 15 },
		[50] = { Gold = 50 },
	},
}

return BattlePassConfig
