--!strict
--[[
	Phase 6 — Daily missions, timed missions, daily login rewards, achievements.
]]


local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Types = require(Shared.Types)
local MissionConfig = require(Shared.Configs.MissionConfig)
local DailyRewardConfig = require(Shared.Configs.DailyRewardConfig)
local AchievementConfig = require(Shared.Configs.AchievementConfig)
local DailyOpsConfig = require(Shared.Configs.DailyOpsConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)

local MissionService = {}

local DataService: any = nil
local EconomyService: any = nil
local XPService: any = nil
local RateLimitService: any = nil
local RemoteSetup: any = nil
local AnalyticsService: any = nil
local NotificationService: any = nil
local TerritoryService: any = nil

local function yyyymmdd(unix: number): number
	local t = os.date("!*t", unix)
	return t.year * 10000 + t.month * 100 + t.day
end

local function ensureDaily(profile: Types.PlayerProfile)
	if typeof(profile.DailyMissions) ~= "table" then
		profile.DailyMissions = {
			DayKey = 0,
			Progress = {},
			Claimed = {},
			ActiveTimed = {},
		}
	end
	local dm = profile.DailyMissions
	if typeof(dm.Progress) ~= "table" then
		dm.Progress = {}
	end
	if typeof(dm.Claimed) ~= "table" then
		dm.Claimed = {}
	end
	if typeof(dm.ActiveTimed) ~= "table" then
		dm.ActiveTimed = {}
	end

	local today = yyyymmdd(os.time())
	if MissionConfig.RefreshOnUtcDayChange and dm.DayKey ~= today then
		dm.DayKey = today
		dm.Progress = {}
		dm.Claimed = {}
		-- Keep ActiveTimed; they can finish across midnight
	end
end

-- Timed missions share DailyMissions.Claimed (reset on UTC day change) under a prefixed key.
local function timedClaimKey(missionId: string): string
	return "timed:" .. missionId
end

local function dailyOpDefs(): { [string]: any }
	local map: { [string]: any } = {}
	if DailyOpsConfig.Enabled then
		for _, op in ipairs(DailyOpsConfig.Ops) do
			map[op.Id] = op
		end
	end
	return map
end

local function resolveMissionDef(id: string): any?
	local ops = dailyOpDefs()
	if ops[id] then
		return ops[id]
	end
	return MissionConfig.DailyMissions[id]
end

local function activeDailyIds(profile: Types.PlayerProfile): { string }
	local list: { string } = {}
	local level = profile.Level or 1
	local seen: { [string]: boolean } = {}
	-- Daily Ops first (3 rotating MT-style gold ops)
	if DailyOpsConfig.Enabled then
		for _, op in ipairs(DailyOpsConfig.Ops) do
			if level >= (op.MinLevel or 1) and not seen[op.Id] then
				table.insert(list, op.Id)
				seen[op.Id] = true
			end
		end
	end
	for _, id in ipairs(MissionConfig.DailyMissionOrder) do
		local def = MissionConfig.DailyMissions[id]
		if def and level >= def.MinLevel and not seen[id] then
			table.insert(list, id)
			seen[id] = true
			if #list >= (MissionConfig.MaxActiveDaily or 6) then
				break
			end
		end
	end
	return list
end

function MissionService.Push(player: Player)
	if not DataService or not RemoteSetup then
		return
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	ensureDaily(profile)

	local dailyPayload: { Types.MissionEntryPayload } = {}
	for _, id in ipairs(activeDailyIds(profile)) do
		local def = resolveMissionDef(id)
		if def then
			local progress = profile.DailyMissions.Progress[id] or 0
			local claimed = profile.DailyMissions.Claimed[id] == true
			local complete = progress >= def.Target
			table.insert(dailyPayload, {
				Id = def.Id,
				DisplayName = def.DisplayName,
				Description = def.Description,
				ObjectiveType = def.ObjectiveType,
				Progress = math.min(progress, def.Target),
				Target = def.Target,
				Claimed = claimed,
				Complete = complete,
				RewardCash = def.RewardCash,
				RewardXP = def.RewardXP,
				RewardGold = def.RewardGold or 0,
			})
		end
	end

	local today = yyyymmdd(os.time())
	local already = profile.DailyLogin.LastClaimDay == today

	local payload: Types.MissionStatePayload = {
		DayKey = profile.DailyMissions.DayKey,
		Daily = dailyPayload,
		DailyLogin = {
			Streak = profile.DailyLogin.Streak,
			CanClaim = not already,
			NextDay = if already then profile.DailyLogin.Streak else (profile.DailyLogin.Streak % DailyRewardConfig.StreakResetsAfterDay) + 1,
			AlreadyClaimedToday = already,
		},
	}

	local remote = RemoteSetup.Get(Constants.RemoteNames.MissionStateUpdate) :: RemoteEvent
	remote:FireClient(player, payload)
end

function MissionService.GrantAchievement(player: Player, achievementId: string): boolean
	local profile = DataService.GetProfile(player)
	if not profile then
		return false
	end
	if typeof(profile.Achievements) ~= "table" then
		profile.Achievements = {}
	end
	if profile.Achievements[achievementId] then
		return false
	end
	local def = AchievementConfig.Achievements[achievementId]
	if not def then
		return false
	end

	profile.Achievements[achievementId] = true
	if def.RewardCash and def.RewardCash > 0 then
		EconomyService.AddCash(player, def.RewardCash, "achievement")
	end
	if def.RewardGold and def.RewardGold > 0 then
		EconomyService.AddGold(player, def.RewardGold, "achievement")
	end
	if def.RewardXP and def.RewardXP > 0 then
		XPService.AddXP(player, def.RewardXP, "achievement")
	end
	DataService.MarkDirty(player)

	if NotificationService then
		NotificationService.Notify(player, "Achievement: " .. def.DisplayName, "Reward")
	end
	if AnalyticsService then
		AnalyticsService.Log(AnalyticsConfig.Events.ACHIEVEMENT_UNLOCKED, player.UserId, {
			id = achievementId,
		})
	end
	return true
end

function MissionService.CheckAchievements(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	if profile.Stats.UpgradesPurchased >= 1 then
		MissionService.GrantAchievement(player, "FirstUpgrade")
	end
	if profile.Stats.TotalCashEarned >= 10000 then
		MissionService.GrantAchievement(player, "Cash10k")
	end
	if profile.Level >= 10 then
		MissionService.GrantAchievement(player, "Level10")
	end
end

function MissionService.TrackProgress(player: Player, objectiveType: string, amount: number)
	if not DataService then
		return
	end
	if typeof(objectiveType) ~= "string" or typeof(amount) ~= "number" or amount <= 0 then
		return
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	ensureDaily(profile)

	local changed = false
	for _, id in ipairs(activeDailyIds(profile)) do
		local def = resolveMissionDef(id)
		if def and def.ObjectiveType == objectiveType then
			local claimed = profile.DailyMissions.Claimed[id] == true
			local prev = profile.DailyMissions.Progress[id] or 0
			if not claimed and prev < def.Target then
				local nextVal = math.min(def.Target, prev + amount)
				profile.DailyMissions.Progress[id] = nextVal
				changed = true
				if AnalyticsService and nextVal >= def.Target and prev < def.Target then
					AnalyticsService.Log(AnalyticsConfig.Events.MISSION_PROGRESS, player.UserId, {
						mission = id,
						complete = true,
					})
					if NotificationService then
						NotificationService.Notify(player, def.DisplayName .. " complete — claim reward!", "Info")
					end
				end
			end
		end
	end

	if changed then
		DataService.MarkDirty(player)
		MissionService.Push(player)
	end

	MissionService.CheckAchievements(player)
end

function MissionService.ClaimDailyMission(player: Player, missionId: string): (boolean, string?)
	if not RemoteGuard.IsIdString(missionId, 48) then
		return false, "InvalidMission"
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end
	ensureDaily(profile)

	local def = resolveMissionDef(missionId)
	if not def then
		return false, "UnknownMission"
	end
	if profile.DailyMissions.Claimed[missionId] then
		return false, "AlreadyClaimed"
	end
	local progress = profile.DailyMissions.Progress[missionId] or 0
	if progress < def.Target then
		return false, "Incomplete"
	end

	profile.DailyMissions.Claimed[missionId] = true
	profile.Stats.MissionsCompleted += 1

	local cash = def.RewardCash
	if TerritoryService and TerritoryService.GetMissionCashMult then
		cash = math.floor(cash * TerritoryService.GetMissionCashMult(player))
	end
	if cash > 0 then
		EconomyService.AddCash(player, cash, "mission")
	end
	if (def.RewardGold or 0) > 0 then
		EconomyService.AddGold(player, def.RewardGold :: number, "mission")
	end
	if def.RewardXP > 0 then
		XPService.AddXP(player, def.RewardXP, "mission")
	end

	DataService.MarkDirty(player)
	if NotificationService then
		NotificationService.Notify(player, string.format("Mission reward: $%d", cash), "Reward")
	end
	if AnalyticsService then
		AnalyticsService.Log(AnalyticsConfig.Events.MISSION_CLAIMED, player.UserId, {
			mission = missionId,
			cash = cash,
		})
	end
	MissionService.Push(player)
	return true, nil
end

function MissionService.ClaimDailyLogin(player: Player): (boolean, string?)
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end
	local today = yyyymmdd(os.time())
	local daily = profile.DailyLogin
	if daily.LastClaimDay == today then
		if NotificationService then
			NotificationService.Notify(player, "Daily reward already claimed.", "Warn")
		end
		return false, "AlreadyClaimed"
	end

	local yesterday = yyyymmdd(os.time() - 86400)
	if DailyRewardConfig.MissedDayResetsStreak and daily.LastClaimDay ~= 0 and daily.LastClaimDay ~= yesterday then
		daily.Streak = 0
	end

	daily.Streak = (daily.Streak % DailyRewardConfig.StreakResetsAfterDay) + 1
	daily.LastClaimDay = today
	daily.LastClaimUnix = os.time()

	local reward = DailyRewardConfig.Rewards[daily.Streak]
	if reward then
		if reward.Cash > 0 then
			EconomyService.AddCash(player, reward.Cash, "daily")
		end
		if reward.Gold > 0 then
			EconomyService.AddGold(player, reward.Gold, "daily")
		end
		if reward.XP > 0 then
			XPService.AddXP(player, reward.XP, "daily")
		end
		if NotificationService then
			NotificationService.Notify(
				player,
				string.format("Day %d reward: $%d", daily.Streak, reward.Cash),
				"Reward"
			)
		end
		if AnalyticsService then
			AnalyticsService.Log(AnalyticsConfig.Events.DAILY_REWARD_CLAIMED, player.UserId, { day = daily.Streak })
		end
	end
	DataService.MarkDirty(player)
	MissionService.Push(player)
	return true, nil
end

function MissionService.Start(player: Player, missionId: any): (boolean, string?)
	if not RemoteGuard.IsIdString(missionId, 48) then
		return false, "InvalidMission"
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end
	ensureDaily(profile)

	local def = MissionConfig.Missions[missionId]
	if not def then
		return false, "UnknownMission"
	end
	if profile.Level < def.MinLevel then
		return false, "LevelTooLow"
	end
	if profile.DailyMissions.ActiveTimed[missionId] and profile.DailyMissions.ActiveTimed[missionId] > os.time() then
		return false, "AlreadyActive"
	end
	-- v69: each timed mission pays once per UTC day (was repeatable every Duration seconds)
	if profile.DailyMissions.Claimed[timedClaimKey(missionId)] then
		return false, "AlreadyClaimed"
	end

	profile.DailyMissions.ActiveTimed[missionId] = os.time() + def.DurationSeconds
	DataService.MarkDirty(player)
	if NotificationService then
		NotificationService.Notify(
			player,
			string.format("%s started (%ds)", def.DisplayName, def.DurationSeconds),
			"Info"
		)
	end

	-- Auto-complete after duration (MVP: timer-based, no world objectives)
	task.delay(def.DurationSeconds, function()
		if not player.Parent then
			return
		end
		local p = DataService.GetProfile(player)
		if not p then
			return
		end
		ensureDaily(p)
		local ends = p.DailyMissions.ActiveTimed[missionId]
		if not ends or ends > os.time() + 1 then
			return
		end
		p.DailyMissions.ActiveTimed[missionId] = nil
		MissionService.Complete(player, missionId)
	end)

	MissionService.Push(player)
	return true, nil
end

function MissionService.Complete(player: Player, missionId: string)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	local def = MissionConfig.Missions[missionId]
	if not def then
		return
	end
	ensureDaily(profile)
	local claimKey = timedClaimKey(missionId)
	if profile.DailyMissions.Claimed[claimKey] then
		return
	end
	profile.DailyMissions.Claimed[claimKey] = true

	profile.Stats.MissionsCompleted += 1
	local cash = def.RewardCash
	if TerritoryService and TerritoryService.GetMissionCashMult then
		cash = math.floor(cash * TerritoryService.GetMissionCashMult(player))
	end
	if cash > 0 then
		EconomyService.AddCash(player, cash, "timed_mission")
	end
	if def.RewardXP > 0 then
		XPService.AddXP(player, def.RewardXP, "timed_mission")
	end
	DataService.MarkDirty(player)
	if NotificationService then
		NotificationService.Notify(player, string.format("%s complete! +$%d", def.DisplayName, cash), "Reward")
	end
	if AnalyticsService then
		AnalyticsService.Log(AnalyticsConfig.Events.MISSION_CLAIMED, player.UserId, {
			mission = missionId,
			timed = true,
			cash = cash,
		})
	end
	MissionService.Push(player)
end

function MissionService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	XPService = deps.XPService
	RateLimitService = deps.RateLimitService
	RemoteSetup = deps.RemoteSetup
	AnalyticsService = deps.AnalyticsService
	NotificationService = deps.NotificationService
	TerritoryService = deps.TerritoryService

	-- v69: no client UI starts timed missions; with the remote open an executor could loop them for
	-- cash/XP. Keep a listener (so events never queue) but drop requests unless explicitly enabled.
	local startRemote = RemoteSetup.Get(Constants.RemoteNames.RequestStartMission) :: RemoteEvent
	startRemote.OnServerEvent:Connect(function(player: Player, missionId: any)
		if MissionConfig.TimedMissionsRemoteEnabled ~= true then
			return
		end
		if not RateLimitService.Allow(player, "start_mission", 1, 2) then
			return
		end
		if not RemoteGuard.RequireProfile(DataService, player) then
			return
		end
		MissionService.Start(player, missionId)
	end)

	local claimRemote = RemoteSetup.Get(Constants.RemoteNames.RequestClaimMission) :: RemoteEvent
	claimRemote.OnServerEvent:Connect(function(player: Player, missionId: any)
		if not RateLimitService.Allow(player, "claim_mission", 2, 3) then
			return
		end
		MissionService.ClaimDailyMission(player, missionId)
	end)

	local dailyRemote = RemoteSetup.Get(Constants.RemoteNames.RequestClaimDailyReward) :: RemoteEvent
	dailyRemote.OnServerEvent:Connect(function(player: Player)
		if not RateLimitService.Allow(player, "daily_reward", 1, 2) then
			return
		end
		MissionService.ClaimDailyLogin(player)
	end)

	DataService.OnProfileLoaded(function(player: Player, _profile: Types.PlayerProfile)
		ensureDaily(_profile)
		MissionService.CheckAchievements(player)
		MissionService.Push(player)
	end)
end

return MissionService
