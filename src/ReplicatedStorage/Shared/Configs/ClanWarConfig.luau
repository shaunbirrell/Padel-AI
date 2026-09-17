--!strict
--[[ Clan war / global war — scores + rewards. Product IDs stay 0. ]]

local ClanWarConfig = {
	WarDurationSeconds = 3600,
	MinClanMembersToDeclare = 2,
	DeclareCooldownSeconds = 300, -- anti-abuse: delay before same clan can declare again after settle
	ScorePerTerritoryCapture = 10,
	ScorePerEnemyKill = 1,
	WinningClanCashReward = 25000,
	WinningClanGoldReward = 15,
	ParticipationCashReward = 2500,
	ParticipationGoldReward = 2,
	-- Extra cash per score point for winning clan members (online)
	ScoreBonusCashPerPoint = 50,
	GlobalWarEnabled = true,
	GlobalWarSeasonKey = "GW_S1",
	ScoreboardTopN = 8,
}

return ClanWarConfig
