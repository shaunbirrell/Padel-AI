--!strict
--[[ 7-day login streak; day 7 resets streak after claim. Field names match MissionService. ]]

local AdminConfig = require(script.Parent.AdminConfig)
local OfflineConfig = require(script.Parent.OfflineConfig) -- Code Bot: Day 7 = one full offline cap (2 h x 10 %)

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
	--[[ claude-bud JOB 49 part A (2026-10-01): reasons to come back. Each block is owner-first (RetentionConfig.Live);
		OFF == the streak exactly as above.
		Grace: ONE missed UTC day per 7-day cycle keeps the streak (the strip marks that day SAVED); a second miss in
		the cycle, or a gap longer than MissedDaysAllowed, resets to Day 1 as before. Saved: DailyLogin.Cycle /
		GraceUsedCycle / GraceDay.
		Day7Scale: Day 7 pays max(the table's cash, IncomeMinutes x his income per minute), on the server at the claim
		(MonetizationService.PassivePerMin, the time-pack formula, timed boosts excluded); the table stays the floor.
		Calendar: the strip carries the REAL time to the next UTC claim day (the server's clock with the payload) and
		the SAVED mark; a new player's first streak card comes after the Guided chain's reward or at the latest at
		FirstCardSeconds of play (and the client still waits out combat / driving / panels). ]]
	Grace = {
		Enabled = true,
		OwnerFirst = false, -- Code Bot v177 (Shaun approved 2026-10-01): everyone (was NEW-OWNER-FIRST, claude-bud JOB 49)
		MissedDaysAllowed = 1,
		PerCycle = 1,
	},
	Day7Scale = {
		Enabled = true,
		OwnerFirst = false, -- Code Bot v177 (Shaun approved 2026-10-01): everyone (was NEW-OWNER-FIRST, claude-bud JOB 49)
		-- Code Bot (Shaun 2026-10-01): was 60 (an hour of income: $624,953.3k on the D7 tile at ~$174k/s). Now the
		-- same worth as one FULL offline cap: OfflineConfig.MaxSeconds x OfflineConfig.Rate / 60 = 7200 x 0.10 / 60
		-- = 12 min of income, so the D7 star and "Away 2 h: earn up to $X" agree. The table's Day 7 cash stays the floor.
		IncomeMinutes = OfflineConfig.MaxSeconds * OfflineConfig.Rate / 60,
	},
	Calendar = {
		Enabled = true,
		OwnerFirst = false, -- Code Bot v177 (Shaun approved 2026-10-01): everyone (was NEW-OWNER-FIRST, claude-bud JOB 49)
		FirstCardSeconds = 150, -- the latest a new player's first streak card waits for the onboarding hold
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

-- claude-bud JOB 49: is a JOB 49 streak block ("Grace" | "Day7Scale" | "Calendar") live for this player
function DailyRewardConfig.Live(block: string, userId: any): boolean
	local b = (DailyRewardConfig :: any)[block]
	return typeof(b) == "table" and (require(script.Parent.RetentionConfig) :: any).Live(b, userId)
end

-- claude-bud JOB 49: the UTC unix time of the next claim day (the next 00:00 UTC after `now`)
function DailyRewardConfig.NextClaimUnix(now: number): number
	return (math.floor(now / 86400) + 1) * 86400
end

-- claude-bud JOB 29: is the streak card / strip / day-7 boost live for this player (fail closed)
function DailyRewardConfig.ShowTomorrowLiveFor(userId: any): boolean
	if DailyRewardConfig.ShowTomorrow ~= true then
		return false
	end
	return (require(script.Parent.RetentionConfig) :: any).Live(DailyRewardConfig.StreakCard, userId)
end

return DailyRewardConfig
