--!strict
--[[ Add your Roblox UserIds here for admin commands + AdminPlaytestCash ]]

local AdminConfig = {
	-- shaunie6 — playtest owner only (do not add random players)
	UserIds = {
		470626172,
	} :: { number },
	-- On profile load, if UserId is in UserIds and Cash below this, raise to this amount.
	-- Server-authoritative; not a global economy change. 0 = disabled.
	AdminPlaytestCash = 50_000_000,
	-- allowlist for force wipe; DataService force_wipe_done_USERID makes each wipe one-shot
	ForceWipeUserIds = { 470626172 } :: { number },
	Commands = {
		"givecash",
		"givegold",
		"givexp",
		"setlevel",
		"unlockall",
		"resetbase",
		"wipeprofile",
		"clearwipedone",
	},
}

return AdminConfig
