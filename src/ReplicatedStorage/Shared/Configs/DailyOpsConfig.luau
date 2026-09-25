--!strict
--[[
	Daily Ops: short, gold-forward objectives. MissionService offers Picks of them each UTC day, above the daily
	missions, while Enabled.

	W3 step 2, lane M0 (spec w3s2 §6 Phase A): the pool grows by three "job" ops and the offer rotates.
	- Slot 1 is a job op: FirstJob once the player's level allows it, otherwise one of OtherJobs (seeded).
	- The other slots rotate through the rest of the pool, seeded by (UserId, UTC day): stable for the day, nothing
	  saved, and every unlocked op comes round within a few days.
	- An op is offered only when MissionConfig.LiveObjectives lists its ObjectiveType and, with a Required Go, while
	  the server has a target for it. DailyOpCheckpoint and DailyOpJobs therefore wait for Phase B (OpsService).
	- Copy is device-neutral (no key names, no "tap" / "click"); the job ops' descriptions stay within 28 characters.

	W3 step 2 Phase B, lane M1: the job ops Checkpoint / Jobs / Camp / Uplink / Cargo count OpsService's jobs
	(MissionConfig.OpsObjectives). They are offered only while OpsService's hook reports the job live, so nothing
	changes before the Ops cutover. Their GO points at the nearest Open site of the kind (never a fixed marker).
]]

export type DailyOpDef = {
	Id: string,
	DisplayName: string,
	Description: string,
	ObjectiveType: string, -- CaptureTerritory | KillNPC | RecruitSoldiers | Heist | Checkpoint | Job | Camp | Uplink | Delivery
	Target: number,
	RewardCash: number,
	RewardXP: number,
	RewardGold: number,
	MinLevel: number,
	Go: string?, -- a MissionConfig.Go key (GO button while incomplete)
}

local DailyOpsConfig = {
	Enabled = true,
	Picks = 3, -- ops offered per UTC day
	FirstJob = "DailyOpBank", -- slot 1 once its MinLevel is reached (and the bank job is on)
	OtherJobs = { "DailyOpCheckpoint", "DailyOpJobs" }, -- slot 1 below that level (Phase B: once they are live)
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
			Go = "Hostiles", -- GO once OpsService has an Open checkpoint or camp
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
		-- W3 step 2 job ops
		{
			Id = "DailyOpBank",
			DisplayName = "Daily Op: Rob the Bank",
			Description = "Loot the Empire Bank vault",
			ObjectiveType = "Heist",
			Target = 1,
			RewardCash = 6000,
			RewardXP = 150,
			RewardGold = 4,
			MinLevel = 3,
			Go = "Bank",
		},
		{
			Id = "DailyOpCheckpoint",
			DisplayName = "Daily Op: Take 2 Checkpoints",
			Description = "Take 2 enemy checkpoints",
			ObjectiveType = "Checkpoint", -- live only through OpsService (MissionConfig.OpsObjectives)
			Target = 2,
			RewardCash = 4000,
			RewardXP = 100,
			RewardGold = 2,
			MinLevel = 2,
			Go = "Checkpoint",
		},
		{
			Id = "DailyOpJobs",
			DisplayName = "Daily Op: Finish 3 Jobs",
			Description = "Finish 3 jobs anywhere",
			ObjectiveType = "Job", -- live only through OpsService (MissionConfig.OpsObjectives)
			Target = 3,
			RewardCash = 5000,
			RewardXP = 120,
			RewardGold = 3,
			MinLevel = 2,
			Go = "Job",
		},
		-- W3 step 2 Phase B (lane M1): more job ops, live only through OpsService
		{
			Id = "DailyOpCamp",
			DisplayName = "Daily Op: Raid a Camp",
			Description = "Raid 1 enemy camp",
			ObjectiveType = "Camp",
			Target = 1,
			RewardCash = 4000,
			RewardXP = 100,
			RewardGold = 2,
			MinLevel = 2,
			Go = "Camp",
		},
		{
			Id = "DailyOpUplink",
			DisplayName = "Daily Op: Hack an Uplink",
			Description = "Hack and hold 1 uplink",
			ObjectiveType = "Uplink",
			Target = 1,
			RewardCash = 5000,
			RewardXP = 120,
			RewardGold = 3,
			MinLevel = 3,
			Go = "Uplink",
		},
		{
			Id = "DailyOpCargo",
			DisplayName = "Daily Op: Haul Cargo",
			Description = "Bring 1 haul to your base",
			ObjectiveType = "Delivery",
			Target = 1,
			RewardCash = 5000,
			RewardXP = 120,
			RewardGold = 3,
			MinLevel = 3,
			Go = "Cargo", -- offered once OpsService answers the Cargo key (the heist yards and the black box)
		},
	} :: { DailyOpDef },
}

return DailyOpsConfig
