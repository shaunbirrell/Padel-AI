--!strict
--[[
	claude-bud JOB 31 (2026-09-30): things to DO at the new sites (WorldSitesConfig). Server SiteActivityService; the
	Missions panel lists them under ACTIVITIES with START / GO. Everything is decided on the server: who started it,
	kills credited by CombatService (the killer), time limits, rewards.

	GARRISONS ("enemy patrols"): a few hostile soldiers posted at the camps, the ridge, the scrapyard and the depot.
	  * They wake when a player the switch is live for comes within WakeStuds and sleep beyond SleepStuds.
	  * Leashed to the site (they move around inside it, never across the map).
	  * They come back RespawnSeconds after the garrison is cleared.
	  * They use CombatService's normal NPC slots (MaxActiveNPCs), never the special over-cap headroom.

	ACTIVITIES: one at a time per player, each with a time limit, a reward and a per-player cooldown. Activity NPCs are
	that player's own group (GroupId "Act.<UserId>") and are removed when the activity ends.
	  ClearCamp   "Clear the camp": kill the soldiers at the camp.
	  Depot       "Capture the depot": clear the guards, then hold the depot zone for HoldSeconds.
	  Convoy      "Defend the convoy": hold the checkpoint while Waves come in; stay in the zone.
	  Cache       "Find the supply cache": a crate is hidden at a site; the GO line leads to the site, then search and
	              hold the prompt.
	  Sniper      "Rooftop sniper": from the Overwatch tower deck, drop Targets posted soldiers far off. Only kills
	              made while standing on the deck count.

	Kill switch: Enabled = false (no garrisons, no activities, no ACTIVITIES section). OwnerFirst as RetentionConfig.Live
	(the owner + Studio test players first; garrisons wake only for them).
]]

export type ActivityDef = {
	Id: string,
	Kind: string,
	Title: string, -- <= 24 characters (the row title)
	Desc: string, -- <= 42 characters, device-neutral
	Site: string, -- WorldSitesConfig site Id (Cache: one of Sites)
	Sites: { string }?,
	Short: string, -- the GO marker label (<= 12)
	Seconds: number, -- time limit
	Cooldown: number, -- per player, after a finish (win or lose)
	Cash: number,
	XP: number,
	Gold: number?,
	Npc: { string }?, -- NPC types spawned for it
	Waves: number?,
	WaveGap: number?,
	HoldSeconds: number?,
	Targets: number?,
}

local SiteActivityConfig = {
	Enabled = true,
	OwnerFirst = false, -- codebot_v136 launch (owner 2026-09-30 14:17): everyone
	PushSeconds = 1, -- state push to the player while an activity runs (<= 1 Hz)
	ZonePadStuds = 12, -- the zone = the site radius + this

	Garrisons = {
		Enabled = true,
		WakeStuds = 250,
		SleepStuds = 380,
		RespawnSeconds = 180,
		CheckSeconds = 2,
		Sites = {
			CampViper = { "Infantry", "Infantry", "HeavyInfantry" },
			DustCamp = { "Infantry", "Infantry", "Infantry" },
			Overwatch = { "Infantry", "Infantry" },
			Anvil = { "Infantry", "HeavyInfantry" },
		} :: { [string]: { string } },
	},

	Activities = {
		{ Id = "ClearViper", Kind = "ClearCamp", Title = "Clear Camp Viper", Desc = "Defeat the soldiers at Camp Viper.", Site = "CampViper", Short = "CAMP", Seconds = 240, Cooldown = 600, Cash = 6000, XP = 150, Npc = { "Infantry", "Infantry", "Infantry", "HeavyInfantry" } },
		{ Id = "TakeKestrel", Kind = "Depot", Title = "Capture Kestrel Depot", Desc = "Clear the guards, then hold the depot.", Site = "Kestrel", Short = "DEPOT", Seconds = 300, Cooldown = 600, Cash = 8000, XP = 200, Npc = { "Infantry", "Infantry", "HeavyInfantry" }, HoldSeconds = 30 },
		{ Id = "HawkConvoy", Kind = "Convoy", Title = "Defend the Convoy", Desc = "Hold Hawk Checkpoint until it passes.", Site = "Hawk", Short = "CONVOY", Seconds = 150, Cooldown = 600, Cash = 7000, XP = 180, Npc = { "Infantry", "Infantry", "Infantry" }, Waves = 3, WaveGap = 30 },
		{ Id = "FindCache", Kind = "Cache", Title = "Find the Supply Cache", Desc = "Search the site for the hidden crate.", Site = "DryWell", Sites = { "DryWell", "PumpSeven", "Anvil" }, Short = "CACHE", Seconds = 300, Cooldown = 420, Cash = 4000, XP = 100, Gold = 5 },
		{ Id = "RidgeSniper", Kind = "Sniper", Title = "Rooftop Sniper", Desc = "From the ridge tower, drop 5 far targets.", Site = "Overwatch", Short = "PERCH", Seconds = 150, Cooldown = 600, Cash = 7500, XP = 200, Npc = { "Infantry" }, Targets = 5 },
	} :: { ActivityDef },

	Sniper = { MinStuds = 90, MaxStuds = 150, PerchStuds = 6 }, -- targets 90-150 studs from the perch; "on the deck" = within 6 studs of it
	Cache = { HideStuds = 30, HoldSeconds = 1.5, PromptStuds = 10 },
}

return SiteActivityConfig
