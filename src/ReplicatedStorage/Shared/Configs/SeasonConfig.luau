--!strict

local SeasonConfig = {
	CurrentSeasonId = "S1_Foundation",
	DisplayName = "Season 1: Foundation",
	StartUnix = 0, -- set at launch
	EndUnix = 0,
	BattlePassLevels = 50,
	XPPerBattlePassLevel = 1000,
	-- Active-season multipliers (SeasonService; server-authoritative)
	XPBonusMult = 1.1,
	CashBonusMult = 1.05,
	Ended = false, -- SeasonService.EndSeason stub flips this
}

return SeasonConfig
