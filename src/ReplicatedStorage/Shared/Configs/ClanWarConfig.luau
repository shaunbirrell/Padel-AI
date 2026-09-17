--!strict
--[[ Clan war / global war scaffolding — scores + reward hooks. Product IDs stay 0. ]]

local ClanWarConfig = {
	WarDurationSeconds = 3600,
	MinClanMembersToDeclare = 2,
	ScorePerTerritoryCapture = 10,
	ScorePerEnemyKill = 1,
	WinningClanCashReward = 25000,
	WinningClanGoldReward = 15,
	ParticipationCashReward = 2500,
	GlobalWarEnabled = true,
	GlobalWarSeasonKey = "GW_S1",
}

return ClanWarConfig
