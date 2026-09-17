--!strict
--[[ Season battle pass tracks. PremiumProductId = 0 until Creator Dashboard. ]]

local BattlePassConfig = {
	SeasonId = "S1_Foundation",
	MaxLevel = 50,
	XPPerLevel = 1000,
	PremiumProductId = 0, -- placeholder — never grant premium from client
	FreeTrack = {
		[1] = { Cash = 500 },
		[3] = { Cash = 1000 },
		[5] = { Cash = 2000 },
		[8] = { Gold = 2 },
		[10] = { Gold = 5 },
		[15] = { Cash = 5000 },
		[20] = { Cash = 8000 },
		[25] = { Cash = 15000 },
		[30] = { Gold = 10 },
		[40] = { Cash = 25000 },
		[50] = { Gold = 25 },
	},
	PremiumTrack = {
		[1] = { Cash = 1500 },
		[3] = { Gold = 1 },
		[5] = { Gold = 3 },
		[8] = { Cash = 5000 },
		[10] = { Cash = 10000 },
		[15] = { Gold = 8 },
		[20] = { Cash = 20000 },
		[25] = { Gold = 15 },
		[30] = { Cash = 35000 },
		[40] = { Gold = 25 },
		[50] = { Gold = 50 },
	},
}

return BattlePassConfig
