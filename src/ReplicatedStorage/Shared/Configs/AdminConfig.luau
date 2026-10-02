--!strict
--[[ Add your Roblox UserIds here for admin commands + AdminPlaytestCash ]]

-- v81: owner playtest account (shaunie6); see PlaytestOwnerUserId / IsPlaytestOwner below
local PLAYTEST_OWNER_USER_ID = 470626172
local PLAYTEST_LEVEL = 100

local AdminConfig = {
	-- shaunie6 — playtest owner only (do not add random players)
	UserIds = {
		470626172,
	} :: { number },
	-- LoadProfile only: if UserId==470626172 and Cash below this, raise to this (simple max).
	-- No ForceWipe / Ensure* floors. DataStore key bump (v2) forces fresh CreateDefault.
	AdminPlaytestCash = 50_000_000,
	-- v81: owner playtest (shaunie6 only, same LoadProfile hook as AdminPlaytestCash, every join, idempotent):
	--   * Level raised to AdminPlaytestLevel (clamped to LevelConfig.MaxLevel = 100; XP 0 = the full XP of that
	--     level, LevelConfig.GetTotalXPForLevel(100) = total earned). Never lowered.
	--   * AdminPlaytestAllVehicles: every VehicleConfig.Vehicles id written into profile.Vehicles (all Ground,
	--     all Air — helicopters, jets, bombers, transports — and all Naval).
	--   * VehicleService skips the Helipad / Airfield / Dock / Depot level, Prestige and rebirth-flag gates on
	--     SPAWN for this UserId only (AdminConfig.IsPlaytestOwner), so every aircraft spawns without the buildings.
	-- Nobody else's profile and no shared economy value is touched.
	PlaytestOwnerUserId = PLAYTEST_OWNER_USER_ID,
	AdminPlaytestLevel = PLAYTEST_LEVEL,
	AdminPlaytestAllVehicles = true,
	-- Code Bot v169 (Shaun 2026-10-01: "doesn't want to type /setrebirth"): a ONE-TIME rebirth grant on his next profile
	-- load, through PrestigeService.AdminSetRebirth (the /setrebirth path: cash / items kept, derived state refreshed,
	-- saved). Applied only if UserId is also in UserIds and profile.AdminGrants[Key] is unset; the Key is then stored,
	-- so it never re-applies (even after he rebirths further or lowers it). Already >= Rebirths: nothing changes (the
	-- Key is still stored). A new Key = a new one-time grant. nil = off.
	OwnerRebirthGrant = { UserId = PLAYTEST_OWNER_USER_ID, Rebirths = 10, Key = "rebirth10-2026-10-01" } :: { UserId: number, Rebirths: number, Key: string }?,
	-- v81: true only for the owner's playtest account (shaunie6). Pure: safe to require anywhere (server + Open
	-- Cloud checks). Used by DataService (level + vehicles on LoadProfile) and VehicleService (spawn gate bypass).
	IsPlaytestOwner = function(userId: any): boolean
		local uid = tonumber(userId)
		return uid ~= nil and uid == PLAYTEST_OWNER_USER_ID
	end,
	-- v81: the level the owner account is raised to (nil for everyone else), clamped to maxLevel (LevelConfig.MaxLevel)
	PlaytestLevelFor = function(userId: any, maxLevel: number): number?
		local uid = tonumber(userId)
		if uid == nil or uid ~= PLAYTEST_OWNER_USER_ID then
			return nil
		end
		return math.clamp(PLAYTEST_LEVEL, 1, math.max(1, math.floor(maxLevel)))
	end,
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
