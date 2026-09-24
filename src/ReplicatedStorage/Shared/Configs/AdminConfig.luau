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
	-- v71 money (M2): test commands for the money workflows. AdminService allows them for the UserIds above and,
	-- in Studio only, for any player (Local Server tests). Each is logged as ADMIN_COMMAND and replies
	-- "not built yet" until its service exists. None of them touches Cash (AdminPlaytestCash stays owner-only).
	--   grantent <key>            MonetizationService.GrantEntitlement on yourself (a MonetizationConfig pass key
	--                             or DevProduct GrantEntitlement value)
	--   givenuke <n> [tactical]   NukeService.Grant(player, "Nuke" | "TacticalNuke", n, "admin")
	--   nukecd                    NukeService.AdminResetCooldowns()
	--   vhp <pct>                 VehicleService.AdminSetHP(player, pct): your active vehicle's HP (0-100%)
	--   setprestige <n>           RebirthExpansionService.AdminSetPrestige(player, n)
	--   openzone <id>             RebirthExpansionService.AdminOpenZone(player, zoneId)
	--   resetrebirth              RebirthExpansionService.AdminResetRebirth(player)
	MoneyCommands = {
		"grantent",
		"givenuke",
		"nukecd",
		"vhp",
		"setprestige",
		"openzone",
		"resetrebirth",
	} :: { string },
}

return AdminConfig
