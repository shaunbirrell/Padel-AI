--!strict

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
