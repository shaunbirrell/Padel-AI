--!strict
--[[ 7-day login streak; day 7 resets streak after claim ]]

local DailyRewardConfig = {
	Rewards = {
		{ Day = 1, Cash = 1000, Gold = 0, XP = 25 },
		{ Day = 2, Cash = 2000, Gold = 0, XP = 40 },
		{ Day = 3, Cash = 3500, Gold = 1, XP = 60 },
		{ Day = 4, Cash = 5000, Gold = 0, XP = 80 },
		{ Day = 5, Cash = 7500, Gold = 2, XP = 100 },
		{ Day = 6, Cash = 10000, Gold = 0, XP = 125 },
		{ Day = 7, Cash = 20000, Gold = 10, XP = 200 },
	},
	StreakResetsAfterDay = 7,
	MissedDayResetsStreak = true,
}

return DailyRewardConfig
