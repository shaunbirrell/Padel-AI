--!strict

local AchievementConfig = {
	Achievements = {
		FirstUpgrade = {
			Id = "FirstUpgrade",
			DisplayName = "First Brick",
			Description = "Purchase your first base upgrade.",
			RewardCash = 500,
			RewardGold = 0,
			RewardXP = 25,
		},
		Cash10k = {
			Id = "Cash10k",
			DisplayName = "War Chest",
			Description = "Earn 10,000 total Cash.",
			RewardCash = 1000,
			RewardGold = 0,
			RewardXP = 50,
		},
		Level10 = {
			Id = "Level10",
			DisplayName = "Sergeant",
			Description = "Reach Level 10.",
			RewardCash = 0,
			RewardGold = 5,
			RewardXP = 100,
		},
	},
}

return AchievementConfig
