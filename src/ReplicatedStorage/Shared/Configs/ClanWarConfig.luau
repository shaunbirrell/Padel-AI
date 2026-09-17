--!strict
--[[ Clan war / global war scaffolding — scores + reward hooks. Marketplace IDs stay 0. ]]

local ClanWarConfig = {
	WarDurationSeconds = 3600, -- 1 hour default war window
	MinClanMembersToDeclare = 2,
	ScorePerTerritoryCapture = 10,
	ScorePerEnemyKill = 1,
	WinningClanCashReward = 25000,
	WinningClanGoldReward = 15,
	ParticipationCashReward = 2500,
	-- Global war stub: all clans score into a shared season pool
	GlobalWarEnabled = true,
	GlobalWarSeasonKey = "GW_S1",
}

return ClanWarConfig
