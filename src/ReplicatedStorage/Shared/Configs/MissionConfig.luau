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
]]

export type DailyMissionDef = {
	Id: string,
	DisplayName: string,
	Description: string,
	-- KillNPC | KillPlayer | CaptureTerritory | PurchaseUpgrade | EarnCash | SpawnVehicle | RecruitSoldiers | Heist
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
	-- a mission that uses this Go is offered only while the server resolves at least one target (the job is on)
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
	-- whose type is not listed is never offered (it could not be finished). Phase B (OpsService) adds Checkpoint,
	-- Camp, Uplink, Delivery and Job.
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

	-- GO targets. Where a Go key points is decided on the SERVER per player (MissionService) and sent with the
	-- mission; the client picks the one nearest to the player. Phase B adds Checkpoint / Hostiles / Capture / Job.
	Go = {
		Bank = {
			Short = "BANK",
			Anchor = "Town.Bank.Vault", -- until it exists: BankRaidConfig.Position
			Required = true, -- only while BankRaidConfig.Enabled
		},
	} :: { [string]: GoDef },

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
