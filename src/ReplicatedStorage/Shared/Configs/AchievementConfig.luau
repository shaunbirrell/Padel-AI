--!strict
--[[
	Achievements. The first three (FirstUpgrade, Cash10k, Level10) are the original set: with Live off,
	MissionService.CheckAchievements / GrantAchievement still grant them exactly as before.

	claude-bud JOB 34 (2026-09-30): the full set + chat shout-outs + Roblox badges (Services/AchievementService).
	  * ONE list here; each entry fires ONCE per player (profile.Achievements[id] = true, the existing saved map), with
	    the time in profile.AchievementsAt.
	  * Progress reads EXISTING counters (Stat = a profile path); nothing new is counted except NukeStats.Launched, the
	    counter the profile already had for it. Event = granted when that server event happens (no counter).
	  * Earner: a popup + sound + the small reward below (server-side AddCash / AddGold / AddXP, reason "achievement").
	  * Whole server: one styled TextChatService system line ("[WAR EMPIRE] <name> just ..."), rate limited (Shout).
	    Big = also a short banner at the top for everyone.
	  * BadgeId: 0 = no badge yet. Code Bot creates them in Creator Hub (docs/BADGES.md) and fills the ids; the server
	    awards only a non-zero id (pcall, UserHasBadgeAsync first, retried, re-synced on join).
	  * Kill switch: Live (RetentionConfig.Live rule: OwnerFirst = UserId 470626172 + Studio). Off = the old 3-entry
	    behaviour.
	Shout text follows the player's name. Tokens: {nth} = the rebirth ordinal ("3rd"), {label} = the board title.
	Never a nation name or a flag in any line (CLAUDE.md).
]]

export type Achievement = {
	Id: string,
	DisplayName: string,
	Title: string?, -- the JOB 34 page / popup name (DisplayName stays the old toast text)
	Description: string,
	RewardCash: number,
	RewardGold: number,
	RewardXP: number,
	Stat: string?, -- a profile path ("Stats.TotalCashEarned", "LB.Kills", "Prestige" ...)
	Target: number?, -- earned when Stat >= Target
	Event: string?, -- or: earned when this event is noted ("KillNPC", "Crown")
	Shout: string?, -- the chat line after the name; nil = no chat line (popup only)
	Big: boolean?, -- also a banner for everyone
	BadgeId: number, -- 0 = no Roblox badge yet
	Order: number, -- page order
}

local AchievementConfig = {
	Live = {
		Enabled = true,
		OwnerFirst = true, -- only UserId 470626172 (+ Studio test players) until Code Bot sets false = everyone
	},

	-- the chat line: "[WAR EMPIRE] <name> <text>" (rich text colours; the client formats it)
	Chat = {
		Prefix = "[WAR EMPIRE]",
		PrefixColor = "#FFC83C",
		NameColor = "#7FD4FF",
		TextColor = "#FFFFFF",
		BigColor = "#FF8A3C",
	},
	-- server-wide rate limit: at most one line per GapSeconds; a player's lines inside CombineSeconds merge into one
	-- ("... (+2 more)"); the queue holds MaxQueue lines, then small ones are dropped (big ones kept)
	Shout = {
		GapSeconds = 3,
		CombineSeconds = 6,
		MaxQueue = 6,
	},
	AnnounceEveryRebirth = true, -- every rebirth gets the big line ("REBIRTHED for the 3rd time!"), not only milestones
	Banner = { Seconds = 4, MaxQueued = 2, TextPx = 18 },
	Popup = { Seconds = 4, MaxQueued = 4, Sound = "Level.Up", TextPx = 17 },
	Badges = { Retries = 3, RetryDelaySeconds = 6, SyncGapSeconds = 1 },

	Achievements = {
		FirstUpgrade = {
			Id = "FirstUpgrade",
			DisplayName = "First Brick",
			Title = "First Building",
			Description = "Purchase your first base upgrade.",
			RewardCash = 500,
			RewardGold = 0,
			RewardXP = 25,
			Stat = "Stats.UpgradesPurchased",
			Target = 1,
			Shout = "just built their first building!",
			BadgeId = 0,
			Order = 3,
		},
		Cash10k = {
			Id = "Cash10k",
			DisplayName = "War Chest",
			Description = "Earn 10,000 total Cash.",
			RewardCash = 1000,
			RewardGold = 0,
			RewardXP = 50,
			Stat = "Stats.TotalCashEarned",
			Target = 10000,
			BadgeId = 0,
			Order = 4,
		},
		Level10 = {
			Id = "Level10",
			DisplayName = "Sergeant",
			Description = "Reach Level 10.",
			RewardCash = 0,
			RewardGold = 5,
			RewardXP = 100,
			Stat = "Level",
			Target = 10,
			BadgeId = 0,
			Order = 8,
		},

		-- claude-bud JOB 34
		FirstKillNPC = {
			Id = "FirstKillNPC", DisplayName = "First Blood", Description = "Defeat your first enemy soldier.",
			RewardCash = 500, RewardGold = 0, RewardXP = 25, Event = "KillNPC",
			Shout = "drew first blood!", BadgeId = 0, Order = 1,
		},
		FirstPlayerKill = {
			Id = "FirstPlayerKill", DisplayName = "Duelist", Description = "Defeat another player.",
			RewardCash = 1500, RewardGold = 1, RewardXP = 50, Stat = "LB.Kills", Target = 1,
			Shout = "won their first player duel!", BadgeId = 0, Order = 2,
		},
		PlayerKills10 = {
			Id = "PlayerKills10", DisplayName = "Hunter", Description = "Defeat 10 players.",
			RewardCash = 5000, RewardGold = 3, RewardXP = 100, Stat = "LB.Kills", Target = 10,
			Shout = "has defeated 10 players!", BadgeId = 0, Order = 5,
		},
		PlayerKills100 = {
			Id = "PlayerKills100", DisplayName = "Warlord", Description = "Defeat 100 players.",
			RewardCash = 25000, RewardGold = 10, RewardXP = 300, Stat = "LB.Kills", Target = 100,
			Shout = "has defeated 100 players!", BadgeId = 0, Order = 12,
		},
		Cash100k = {
			Id = "Cash100k", DisplayName = "Six Figures", Description = "Earn $100,000 in total.",
			RewardCash = 2500, RewardGold = 1, RewardXP = 50, Stat = "Stats.TotalCashEarned", Target = 100000,
			Shout = "has earned their first $100,000!", BadgeId = 0, Order = 6,
		},
		Cash1M = {
			Id = "Cash1M", DisplayName = "Millionaire", Description = "Earn $1,000,000 in total.",
			RewardCash = 10000, RewardGold = 3, RewardXP = 150, Stat = "Stats.TotalCashEarned", Target = 1000000,
			Shout = "is a MILLIONAIRE!", BadgeId = 0, Order = 9,
		},
		Cash100M = {
			Id = "Cash100M", DisplayName = "War Tycoon", Description = "Earn $100,000,000 in total.",
			RewardCash = 100000, RewardGold = 15, RewardXP = 500, Stat = "Stats.TotalCashEarned", Target = 100000000,
			Shout = "has earned $100,000,000!", Big = true, BadgeId = 0, Order = 16,
		},
		CommandCenterMax = {
			-- Target = BaseConfig.Structures.CommandCenter.MaxLevel (the test checks they match)
			Id = "CommandCenterMax", DisplayName = "High Command", Description = "Upgrade the Command Center to max level.",
			RewardCash = 5000, RewardGold = 2, RewardXP = 100, Stat = "BaseUpgrades.CommandCenter", Target = 5,
			Shout = "maxed out their Command Center!", BadgeId = 0, Order = 10,
		},
		FirstOutpost = {
			Id = "FirstOutpost", DisplayName = "Outpost Taken", Description = "Capture an outpost.",
			RewardCash = 2000, RewardGold = 1, RewardXP = 50, Stat = "Stats.TerritoriesCaptured", Target = 1,
			Shout = "captured their first outpost!", BadgeId = 0, Order = 7,
		},
		PlazaCaptured = {
			Id = "PlazaCaptured", DisplayName = "Plaza Conqueror", Description = "Capture the Central Plaza.",
			RewardCash = 10000, RewardGold = 5, RewardXP = 200, Stat = "Stats.PlazaCaptures", Target = 1,
			Shout = "CAPTURED THE CENTRAL PLAZA!", Big = true, BadgeId = 0, Order = 11,
		},
		Rebirth1 = {
			Id = "Rebirth1", DisplayName = "Reborn", Description = "Rebirth for the first time.",
			RewardCash = 0, RewardGold = 5, RewardXP = 0, Stat = "Prestige", Target = 1,
			Shout = "just REBIRTHED for the {nth} time!", Big = true, BadgeId = 0, Order = 13,
		},
		Rebirth5 = {
			Id = "Rebirth5", DisplayName = "Veteran Reborn", Description = "Rebirth 5 times.",
			RewardCash = 0, RewardGold = 10, RewardXP = 0, Stat = "Prestige", Target = 5,
			Shout = "just REBIRTHED for the {nth} time!", Big = true, BadgeId = 0, Order = 17,
		},
		Rebirth10 = {
			Id = "Rebirth10", DisplayName = "Legend Reborn", Description = "Rebirth 10 times.",
			RewardCash = 0, RewardGold = 20, RewardXP = 0, Stat = "Prestige", Target = 10,
			Shout = "just REBIRTHED for the {nth} time!", Big = true, BadgeId = 0, Order = 18,
		},
		Rebirth20 = {
			Id = "Rebirth20", DisplayName = "Eternal Commander", Description = "Rebirth 20 times.",
			RewardCash = 0, RewardGold = 40, RewardXP = 0, Stat = "Prestige", Target = 20,
			Shout = "just REBIRTHED for the {nth} time!", Big = true, BadgeId = 0, Order = 19,
		},
		FirstNuke = {
			Id = "FirstNuke", DisplayName = "Doomsday", Description = "Launch a nuke from your silo.",
			RewardCash = 0, RewardGold = 10, RewardXP = 200, Stat = "NukeStats.Launched", Target = 1,
			Shout = "just LAUNCHED A NUKE!", Big = true, BadgeId = 0, Order = 15,
		},
		Army50 = {
			Id = "Army50", DisplayName = "Grand Army", Description = "Command an army of 50 soldiers.",
			RewardCash = 10000, RewardGold = 3, RewardXP = 150, Stat = "Soldiers", Target = 50,
			Shout = "now commands an army of 50 soldiers!", BadgeId = 0, Order = 14,
		},
		Streak7 = {
			Id = "Streak7", DisplayName = "Loyal Soldier", Description = "Log in 7 days in a row.",
			RewardCash = 5000, RewardGold = 3, RewardXP = 100, Stat = "DailyLogin.Streak", Target = 7,
			Shout = "logged in 7 days in a row!", BadgeId = 0, Order = 20,
		},
		WeeklyCrown = {
			Id = "WeeklyCrown", DisplayName = "Number One", Description = "Be #1 on a weekly leaderboard.",
			RewardCash = 0, RewardGold = 15, RewardXP = 200, Event = "Crown",
			Shout = "is #1 on {label} this week!", Big = true, BadgeId = 0, Order = 21,
		},
	} :: { [string]: Achievement },
}

return AchievementConfig
