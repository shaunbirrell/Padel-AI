--!strict
--[[
	Daily objective missions (progress tracked server-side) + legacy timed missions.

	W3 step 2, lane M0 (spec w3s2 §6 Phase A):
	- The daily offer ROTATES (MissionService): 3 Daily Ops (DailyOpsConfig) + 3 daily missions = MaxActiveDaily 6.
	  Levels 1..Rotation.NewPlayerMaxLevel get the Rotation.Fixed missions plus NewPlayerPicks rotating ones; higher
	  levels get Rotation.Picks rotating out of every unlocked mission. Picks are seeded by (UserId, UTC day), so they
	  are stable for the day, need no save, and every unlocked mission comes round within a few days.
	- ObjectiveType "Heist" (a bank job done; BankRaidService tracks it today, OpsService in Phase B).
	- Go: a mission row with a Go key shows GO while it is incomplete. GO points the one objective marker
	  (Client/Modules/ObjectiveMarker) at the nearest target the SERVER sent for that key; never a fixed marker.

	W3 step 2 Phase B, lane M1 (jobs):
	- OpsObjectives (Checkpoint, Camp, Uplink, Delivery, Job) are reported by OpsService (TrackProgress, 1 per finished
	  job for each type in OpsConfig.Kinds[kind].Track). They are live ONLY while OpsService's hook says so
	  (MissionService.SetOpsHooks: ObjectiveLive), so with no hook (OpsConfig.Enabled = false) the offer is exactly
	  Phase A's. Heist stays in LiveObjectives: BankRaidService reports it until the cutover, OpsService after.
	- Go keys Checkpoint / Camp / Uplink / Job / Cargo / Hostiles are answered by the same hook (GoTargets: every Open
	  site of that key; the server sends the GoMaxTargets nearest to the player, the client picks the nearest).
	  With no hook they have no target: a Required one keeps its mission off the offer, Hostiles just hides GO.
	- Capture has no Go key yet (TerritoryService is batch B's; a neutral-zone pointer must skip every Home Outpost).
]]

export type DailyMissionDef = {
	Id: string,
	DisplayName: string,
	Description: string,
	-- KillNPC | KillPlayer | CaptureTerritory | PurchaseUpgrade | EarnCash | SpawnVehicle | RecruitSoldiers | Heist
	-- | Checkpoint | Camp | Uplink | Delivery | Job (the last five: MissionConfig.OpsObjectives, live through OpsService)
	ObjectiveType: string,
	Target: number,
	RewardCash: number,
	RewardXP: number,
	RewardGold: number?,
	MinLevel: number,
	Go: string?, -- a MissionConfig.Go key (GO button while incomplete)
}

export type GoDef = {
	Short: string, -- objective marker / compass label: 2-7 capitals, device-neutral ("BANK")
	-- server only: the WE_ActivityAnchor id to point at once it exists (lane BK stamps the bank's)
	Anchor: string?,
	-- a mission that uses this Go is offered only while the key is served (the job is on): the old resolver has a
	-- target, or OpsService's hook answers the key (a table, even an empty one while every site is busy: the offer
	-- never reshuffles when a site cools or the director rotates; GO shows once a site is Open again)
	Required: boolean?,
}

-- One GO target as sent to the client (world studs). MissionService adds Go / GoTargets to a mission entry.
export type GoTarget = { X: number, Y: number, Z: number }

export type MissionDef = {
	Id: string,
	DisplayName: string,
	Description: string,
	MinLevel: number,
	DurationSeconds: number,
	RewardCash: number,
	RewardXP: number,
	Difficulty: string,
}

local MissionConfig = {
	-- How many entries the daily list offers in total: the Daily Ops first, then the daily missions
	MaxActiveDaily = 6, -- includes Daily Ops when merged
	RefreshOnUtcDayChange = true,

	-- Which daily missions are offered each UTC day (MissionService; seeded by UserId + day, nothing saved)
	Rotation = {
		NewPlayerMaxLevel = 4, -- levels 1..4: Fixed + NewPlayerPicks rotating missions
		Fixed = { "DailyUpgrade", "DailyRecruit" }, -- first-5-minute missions for new players
		NewPlayerPicks = 1,
		Picks = 3, -- from NewPlayerMaxLevel + 1: this many rotate out of every unlocked daily mission
	},

	-- Objective types some server system reports through MissionService.TrackProgress today. A mission or daily op
	-- whose type is not listed here (or live through OpsObjectives) is never offered (it could not be finished).
	LiveObjectives = {
		KillNPC = true,
		KillPlayer = true,
		CaptureTerritory = true,
		PurchaseUpgrade = true,
		EarnCash = true,
		SpawnVehicle = true,
		RecruitSoldiers = true,
		Heist = true, -- BankRaidService: a bank job done (lane F)
	} :: { [string]: boolean },

	-- Objective types only OpsService reports (W3 step 2 Phase B). Live ONLY while its hook's ObjectiveLive(type) is
	-- true (a live job site reports it); never through LiveObjectives, so they stay off until the Ops cutover.
	OpsObjectives = {
		Checkpoint = true, -- a road checkpoint taken
		Camp = true, -- a raid camp cleared (its chest opened)
		Uplink = true, -- an uplink hacked and held
		Delivery = true, -- a cargo haul brought home (the heist yards and the black box; the bank counts as Heist)
		Job = true, -- any job finished
	} :: { [string]: boolean },

	-- GO targets. Where a Go key points is decided on the SERVER per player (MissionService) and sent with the
	-- mission; the client picks the one nearest to the player. OpsService's hook answers first (Phase B); a key it
	-- does not know falls back to the Anchor / BankRaidConfig resolver.
	Go = {
		Bank = {
			Short = "BANK",
			Anchor = "Town.Bank.Vault", -- until it exists: BankRaidConfig.Position
			Required = true, -- only while BankRaidConfig.Enabled (or, after the cutover, while the bank is an Ops site)
		},
		-- Phase B (lane M1): answered only by OpsService's hook (every Open site of these kinds)
		Checkpoint = { Short = "POST", Required = true },
		Camp = { Short = "CAMP", Required = true },
		Uplink = { Short = "UPLINK", Required = true },
		Job = { Short = "JOB", Required = true }, -- any Open job
		Cargo = { Short = "CARGO", Required = true }, -- the heist yards and the black box (Delivery)
		Hostiles = { Short = "HOSTILE" }, -- the nearest Open checkpoint or camp (KillNPC); no hook = no GO button
	} :: { [string]: GoDef },
	GoMaxTargets = 16, -- GO targets sent per entry: the nearest to the player (MissionController reads at most 16)
	GoRefreshSeconds = 30, -- while OpsService's hook is set: re-send a player's list when its targets change (0 = off)

	-- Missions panel row button (GO / CLAIM), in v (the panel's UI scale): 112 x 72 v is about 73 x 47 real px on a
	-- phone (spec w3s2 activities §9); the desktop button is DesktopButtonW wide and the desktop tap height tall.
	Ui = {
		ButtonW = 112,
		ButtonH = 72,
		DesktopButtonW = 96,
	},

	DailyMissions = {
		DailyKillNPC = {
			Id = "DailyKillNPC",
			DisplayName = "Clear Hostiles",
			Description = "Eliminate 10 NPC hostiles.",
			ObjectiveType = "KillNPC",
			Target = 10,
			RewardCash = 2500,
			RewardXP = 80,
			RewardGold = 0,
			MinLevel = 1,
			Go = "Hostiles", -- GO once OpsService has an Open checkpoint or camp
		},
		DailyCapture = {
			Id = "DailyCapture",
			DisplayName = "Seize Ground",
			Description = "Capture 1 territory.",
			ObjectiveType = "CaptureTerritory",
			Target = 1,
			RewardCash = 4000,
			RewardXP = 120,
			RewardGold = 1,
			MinLevel = 1,
		},
		DailyUpgrade = {
			Id = "DailyUpgrade",
			DisplayName = "Fortify Base",
			Description = "Buy 1 base upgrade — reward $3,000 + 100 XP.",
			ObjectiveType = "PurchaseUpgrade",
			Target = 1, -- v37: completable in first ~5 min
			RewardCash = 3000,
			RewardXP = 100,
			RewardGold = 0,
			MinLevel = 1,
		},
		DailyEarnCash = {
			Id = "DailyEarnCash",
			DisplayName = "War Chest",
			Description = "Earn $8,000 Cash from any source.",
			ObjectiveType = "EarnCash",
			Target = 8000,
			RewardCash = 2000,
			RewardXP = 60,
			RewardGold = 0,
			MinLevel = 1,
		},
		DailySpawnVehicle = {
			Id = "DailySpawnVehicle",
			DisplayName = "Mobilize",
			Description = "Spawn 1 vehicle from the garage — reward $1,500 + 40 XP.",
			ObjectiveType = "SpawnVehicle",
			Target = 1,
			RewardCash = 1500,
			RewardXP = 40,
			RewardGold = 0,
			MinLevel = 1,
		},
		DailyKillPlayer = {
			Id = "DailyKillPlayer",
			DisplayName = "Combat Ready",
			Description = "Eliminate 3 enemy players.",
			ObjectiveType = "KillPlayer",
			Target = 3,
			RewardCash = 5000,
			RewardXP = 150,
			RewardGold = 2,
			MinLevel = 5,
		},
		DailyRecruit = {
			Id = "DailyRecruit",
			DisplayName = "Muster Troops",
			Description = "Recruit 1 soldier — reward $2,000 + 50 XP + 1 Gold.",
			ObjectiveType = "RecruitSoldiers",
			Target = 1, -- v37: first-5-min friendly
			RewardCash = 2000,
			RewardXP = 50,
			RewardGold = 1,
			MinLevel = 1,
		},
	} :: { [string]: DailyMissionDef },

	-- Display order, and the order of the rotation pool (MissionService)
	DailyMissionOrder = {
		"DailyUpgrade", -- v37: first 5-min completable
		"DailyRecruit",
		"DailySpawnVehicle",
		"DailyKillNPC",
		"DailyCapture",
		"DailyEarnCash",
		"DailyKillPlayer",
	},

	-- Legacy timed missions (optional start → wait Duration → claim). v69: no client UI starts them,
	-- so the RequestStartMission remote is ignored unless this is true; each one pays once per UTC day.
	TimedMissionsRemoteEnabled = false,
	Missions = {
		PatrolOutskirts = {
			Id = "PatrolOutskirts",
			DisplayName = "Patrol the Outskirts",
			Description = "Secure the perimeter around your base.",
			MinLevel = 1,
			DurationSeconds = 60,
			RewardCash = 800,
			RewardXP = 50,
			Difficulty = "Easy",
		},
		SupplyRun = {
			Id = "SupplyRun",
			DisplayName = "Supply Run",
			Description = "Escort a convoy to the depot.",
			MinLevel = 3,
			DurationSeconds = 120,
			RewardCash = 2000,
			RewardXP = 120,
			Difficulty = "Normal",
		},
		RaidOutpost = {
			Id = "RaidOutpost",
			DisplayName = "Raid Enemy Outpost",
			Description = "Strike a hostile forward base.",
			MinLevel = 8,
			DurationSeconds = 180,
			RewardCash = 6000,
			RewardXP = 300,
			Difficulty = "Hard",
		},
	} :: { [string]: MissionDef },
}

return MissionConfig
