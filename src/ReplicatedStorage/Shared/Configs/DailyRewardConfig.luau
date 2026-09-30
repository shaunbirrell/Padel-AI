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
	--[[ claude-bud JOB 29 (2026-09-30): streak visibility.
		ShowTomorrow (kill switch, everyone): wherever the streak is shown, tomorrow's reward is shown too (the Missions
		panel's daily row, the auto-claim toast, the streak card).
		StreakCard (OwnerFirst first): the auto-claim shows ONE card with the 7-day strip (today lit, BigDays gold) and
		"Come back tomorrow for $Y" instead of two text toasts; the Missions panel shows the same strip plus 1-2
		"tomorrow" goals; day 7 also gives Day7Boost (army damage x Mult for Minutes; profile.ArmyBoostUntil; no Robux).
		The card waits while WE_Onboarding is on (FastStart). Both off = the JOB 4.2 toasts exactly as before. ]]
	ShowTomorrow = true,
	StreakCard = {
		Enabled = true,
		OwnerFirst = false, -- codebot_v136 launch (owner 2026-09-30 14:17): everyone
	},
	BigDays = { [3] = true, [7] = true } :: { [number]: boolean },
	CardSeconds = 6,
	Day7Boost = { Enabled = true, Mult = 1.25, Minutes = 30, Label = "ARMY BOOST" },
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

-- claude-bud JOB 29: is the streak card / strip / day-7 boost live for this player (fail closed)
function DailyRewardConfig.ShowTomorrowLiveFor(userId: any): boolean
	if DailyRewardConfig.ShowTomorrow ~= true then
		return false
	end
	return (require(script.Parent.RetentionConfig) :: any).Live(DailyRewardConfig.StreakCard, userId)
end

return DailyRewardConfig
