--!strict
--[[ Add your Roblox UserIds here for admin commands + AdminPlaytestCash ]]

local AdminConfig = {
	-- shaunie6 — playtest owner only (do not add random players)
	UserIds = {
		470626172,
	} :: { number },
	-- Every join (not wipe-only): if UserId in UserIds and Cash below this, raise to this amount.
	-- Idempotent top-up — recovers after force_wipe_done + prior $0 save. 0 = disabled.
	-- Server-authoritative; not a global economy change. Does NOT auto-max BaseUpgrades.
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
