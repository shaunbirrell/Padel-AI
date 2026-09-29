--!strict
--[[ 7-day login streak; day 7 resets streak after claim. Field names match MissionService. ]]

local AdminConfig = require(script.Parent.AdminConfig)

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
	--[[ claude-bud JOB 4.2 (2026-09-29): the streak is claimed FOR the player DelaySeconds after the save loads (no
		panel to find, no tap), through the same server claim (MissionService.ClaimDailyLogin: once per UTC day, saved
		in the profile's DailyLogin), then one toast "Day N of 7: +$X. Tomorrow: $Y". Rollout "owner" =
		AdminConfig.IsPlaytestOwner only, "all", anything else = off (claim from the Missions panel only, as before). ]]
	AutoClaim = {
		Rollout = "all", -- v101
		DelaySeconds = 8,
	},
}

-- claude-bud: is auto-claim live for this player (fail closed)
function DailyRewardConfig.AutoClaimLiveFor(userId: any): boolean
	if (require(script.Parent.MonetizationConfig) :: any).Launched("DailyAutoClaim") then
		return true -- claude-bud JOB 12: MonetizationConfig.LaunchAll
	end
	local mode = DailyRewardConfig.AutoClaim.Rollout
	if mode == "all" then
		return true
	elseif mode == "owner" then
		return AdminConfig.IsPlaytestOwner(userId)
	end
	return false
end

return DailyRewardConfig
