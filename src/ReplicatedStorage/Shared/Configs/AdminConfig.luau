--!strict
--[[ Add your Roblox UserIds here for admin commands + AdminPlaytestCash ]]

local AdminConfig = {
	-- shaunie6 — playtest owner only (do not add random players)
	UserIds = {
		470626172,
	} :: { number },
	-- LoadProfile only: if UserId==470626172 and Cash below this, raise to this (simple max).
	-- No ForceWipe / Ensure* floors. DataStore key bump (v2) forces fresh CreateDefault.
	AdminPlaytestCash = 50_000_000,
	Commands = {
		"cash",
		"givecash",
		"givegold",
		"givexp",
		"setlevel",
		"unlockall",
		"resetbase",
		"wipeprofile",
	},
}

return AdminConfig
