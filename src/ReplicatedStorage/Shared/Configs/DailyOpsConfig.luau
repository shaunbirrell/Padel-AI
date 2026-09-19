--!strict
--[[
	Three rotating Daily Ops (Military Tycoon–style short objectives).
	MissionService merges these into the daily mission list when enabled.
]]

export type DailyOpDef = {
	Id: string,
	DisplayName: string,
	Description: string,
	ObjectiveType: string, -- CaptureTerritory | KillNPC | RecruitSoldiers
	Target: number,
	RewardCash: number,
	RewardXP: number,
	RewardGold: number,
	MinLevel: number,
}

local DailyOpsConfig = {
	Enabled = true,
	-- Always offer exactly these 3 (gold-forward rewards)
	Ops = {
		{
			Id = "DailyOpCapture",
			DisplayName = "Daily Op: Seize",
			Description = "Capture 2 territories or oil platforms.",
			ObjectiveType = "CaptureTerritory",
			Target = 2,
			RewardCash = 5000,
			RewardXP = 100,
			RewardGold = 3,
			MinLevel = 1,
		},
		{
			Id = "DailyOpKillNPC",
			DisplayName = "Daily Op: Clear Hostiles",
			Description = "Eliminate 15 NPC hostiles.",
			ObjectiveType = "KillNPC",
			Target = 15,
			RewardCash = 3500,
			RewardXP = 90,
			RewardGold = 2,
			MinLevel = 1,
		},
		{
			Id = "DailyOpRecruit",
			DisplayName = "Daily Op: Muster",
			Description = "Recruit 10 soldiers at the Training Yard.",
			ObjectiveType = "RecruitSoldiers",
			Target = 10,
			RewardCash = 2500,
			RewardXP = 70,
			RewardGold = 2,
			MinLevel = 1,
		},
	} :: { DailyOpDef },
}

return DailyOpsConfig
