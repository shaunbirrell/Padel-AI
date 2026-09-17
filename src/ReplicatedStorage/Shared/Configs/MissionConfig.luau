--!strict
--[[
	Daily objective missions (progress tracked server-side) + legacy timed missions.
]]

export type DailyMissionDef = {
	Id: string,
	DisplayName: string,
	Description: string,
	ObjectiveType: string, -- KillNPC | KillPlayer | CaptureTerritory | PurchaseUpgrade | EarnCash | SpawnVehicle
	Target: number,
	RewardCash: number,
	RewardXP: number,
	RewardGold: number?,
	MinLevel: number,
}

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
	-- How many daily missions are offered (first N unlocked by level from DailyMissions order)
	MaxActiveDaily = 4,
	RefreshOnUtcDayChange = true,

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
			Description = "Purchase 2 base upgrades.",
			ObjectiveType = "PurchaseUpgrade",
			Target = 2,
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
			Description = "Spawn a vehicle from the garage.",
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
	} :: { [string]: DailyMissionDef },

	DailyMissionOrder = {
		"DailyKillNPC",
		"DailyCapture",
		"DailyUpgrade",
		"DailyEarnCash",
		"DailySpawnVehicle",
		"DailyKillPlayer",
	},

	-- Legacy timed missions (optional start → wait Duration → claim)
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
