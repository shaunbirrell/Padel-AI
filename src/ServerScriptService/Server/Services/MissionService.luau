--!strict
--[[
	Phase 6 — Daily missions, timed missions, daily login rewards, achievements.

	W3 step 2, lane M0 (spec w3s2 §6 Phase A):
	- The daily offer rotates (offerFor): DailyOpsConfig.Picks Daily Ops (slot 1 a job op) + the daily missions of
	  MissionConfig.Rotation, MaxActiveDaily in total. Picks are seeded by (UserId, UTC day) with pure integer maths
	  (no Random, no save), so a player sees the same list all day on every server, and a rotation cycle of at most
	  7 days offers every unlocked mission. A mission that already has progress today stays offered (a level-up
	  mid-day never hides it). Only offered missions progress or can be claimed.
	- An entry whose def has a Go key carries Go + GoTargets (server-resolved world points, e.g. the bank vault
	  anchor, else BankRaidConfig.Position) while incomplete; MissionController's GO points the objective marker at
	  the nearest one. Nothing the client sends is trusted: claims re-check the offer, the progress and Claimed.
]]


local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local Constants = require(Shared.Constants)
local Types = require(Shared.Types)
local MissionConfig = require(Shared.Configs.MissionConfig)
local DailyRewardConfig = require(Shared.Configs.DailyRewardConfig)
local AchievementConfig = require(Shared.Configs.AchievementConfig)
local DailyOpsConfig = require(Shared.Configs.DailyOpsConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)
local BankRaidConfig = require(Shared.Configs.BankRaidConfig)

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

local function commas(n: number): string
	local v = math.floor(n)
	local str = tostring(math.abs(v))
	local out = string.reverse((string.gsub(string.reverse(str), "(%d%d%d)", "%1,")))
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return if v < 0 then "-" .. out else out
end

-- Daily Op defs by id (the config is static: built once)
local opDefsById: { [string]: DailyOpsConfig.DailyOpDef }? = nil
local function dailyOpDefs(): { [string]: DailyOpsConfig.DailyOpDef }
	local map = opDefsById
	if map == nil then
		local m: { [string]: DailyOpsConfig.DailyOpDef } = {}
		for _, op in ipairs(DailyOpsConfig.Ops) do
			if m[op.Id] == nil then
				m[op.Id] = op
			end
		end
		opDefsById = m
		return m
	end
	return map
end

local function resolveMissionDef(id: string): any?
	if DailyOpsConfig.Enabled then
		local op = dailyOpDefs()[id]
		if op then
			return op
		end
	end
	return MissionConfig.DailyMissions[id]
end

-- ── GO targets (server side; the client only draws the marker) ─────────────────────────────────────────────────
local GO_CACHE_SECONDS = 30 -- anchors are stamped once at world build; re-read at most this often
local goCache: { [string]: { At: number, List: { MissionConfig.GoTarget } } } = {}
local anchorsModule: any = nil
local anchorsTried = false

-- ActivityAnchors (W3 step 2 L0, server only) is optional here: found lazily, never waited for
local function anchorPosition(id: string): Vector3?
	if not anchorsTried then
		anchorsTried = true
		local modules = script.Parent.Parent:FindFirstChild("Modules")
		local m = modules and modules:FindFirstChild("ActivityAnchors")
		if m and m:IsA("ModuleScript") then
			local ok, mod = pcall(require, m)
			if ok and type(mod) == "table" then
				anchorsModule = mod
			end
		end
	end
	local mod = anchorsModule
	if mod == nil or type(mod.Get) ~= "function" then
		return nil
	end
	local ok, a = pcall(mod.Get, id)
	if ok and type(a) == "table" and typeof(a.Position) == "Vector3" then
		return a.Position
	end
	return nil
end

local function round1(n: number): number
	return math.floor(n * 10 + 0.5) / 10
end

local function resolveGo(kind: string): { MissionConfig.GoTarget }
	local gd = MissionConfig.Go[kind]
	if gd == nil then
		return {}
	end
	local p: Vector3? = nil
	if kind == "Bank" then
		-- Phase A: the bank job is BankRaidService's (Phase B lane M1 points this at OpsService's bank site)
		if BankRaidConfig.Enabled == false then
			return {}
		end
		if gd.Anchor then
			p = anchorPosition(gd.Anchor)
		end
		if p == nil and typeof(BankRaidConfig.Position) == "Vector3" then
			p = BankRaidConfig.Position
		end
	elseif gd.Anchor then
		p = anchorPosition(gd.Anchor)
	end
	if p == nil then
		return {}
	end
	return { { X = round1(p.X), Y = round1(p.Y), Z = round1(p.Z) } }
end

local function goTargets(kind: string): { MissionConfig.GoTarget }
	local now = os.clock()
	local c = goCache[kind]
	if c and now - c.At < GO_CACHE_SECONDS then
		return c.List
	end
	local list = resolveGo(kind)
	goCache[kind] = { At = now, List = list }
	return list
end

-- ── the daily offer ──────────────────────────────────────────────────────────────────────────────────────────────
-- Park–Miller minimal standard generator: modulus 2^31 - 1, every product < 2^53, so it is exact in doubles and
-- gives the same numbers on every server (no Random, no os.time inside).
local PM = 2147483647
local SALT_JOB, SALT_OPS, SALT_MISSIONS = 7919, 104729, 1299709

local function mix(h: number, v: number): number
	h = (h * 48271 + (v % PM)) % PM
	return if h == 0 then 1 else h
end

local function seedOf(userId: number, cycle: number, salt: number): number
	local u = math.abs(math.floor(userId))
	local h = mix(20240917, u % 65536)
	h = mix(h, (u // 65536) % PM)
	h = mix(h, cycle)
	h = mix(h, salt)
	for _ = 1, 4 do
		h = mix(h, 0)
	end
	return h
end

local function seededShuffle(list: { string }, seed: number): { string }
	local out = table.clone(list)
	local s = seed
	for i = #out, 2, -1 do
		s = (s * 48271) % PM
		local j = (s % i) + 1
		out[i], out[j] = out[j], out[i]
	end
	return out
end

--[[ k picks for this day out of pool. The pool is dealt k per day from a seeded permutation that is re-shuffled
	each cycle of ceil(#pool / k) days, so every entry is offered once per cycle (≤ 7 days for these pools) and the
	picks depend only on (userId, dayIndex, salt). The result keeps the pool's order. ]]
local function rotatePick(pool: { string }, k: number, userId: number, dayIndex: number, salt: number): { string }
	local n = #pool
	if k <= 0 or n == 0 then
		return {}
	end
	if n <= k then
		return table.clone(pool)
	end
	local cycleLen = math.ceil(n / k)
	local cycle = dayIndex // cycleLen
	local slot = dayIndex - cycle * cycleLen
	local perm = seededShuffle(pool, seedOf(userId, cycle, salt))
	local chosen: { [string]: boolean } = {}
	for i = 1, k do
		local idx = slot * k + i
		if idx > n then
			idx -= n -- the last, short slot of a cycle tops up from the start (never a repeat within the day)
		end
		chosen[perm[idx]] = true
	end
	local out: { string } = {}
	for _, id in ipairs(pool) do
		if chosen[id] then
			table.insert(out, id)
		end
	end
	return out
end

-- UTC yyyymmdd -> days since 1970-01-01 (civil-from-days inverse; pure integer maths)
local function dayIndexOf(dayKey: number): number
	local y = dayKey // 10000
	local m = (dayKey // 100) % 100
	local d = dayKey % 100
	if m <= 2 then
		y -= 1
	end
	local era = y // 400
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = (153 * mp + 2) // 5 + d - 1
	local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
	return era * 146097 + doe - 719468
end

-- can this def be offered right now (its objective is tracked, and a Required Go has a target)?
local function isLive(def: any): boolean
	if MissionConfig.LiveObjectives[def.ObjectiveType] ~= true then
		return false
	end
	local go = def.Go
	if type(go) == "string" then
		local gd = MissionConfig.Go[go]
		if gd and gd.Required == true and #goTargets(go) == 0 then
			return false
		end
	end
	return true
end

local function levelOf(profile: Types.PlayerProfile): number
	local lv = tonumber(profile.Level) or 1
	return math.max(1, math.floor(lv))
end

local function pickOps(level: number, userId: number, dayIndex: number): { string }
	if not DailyOpsConfig.Enabled then
		return {}
	end
	local picks = DailyOpsConfig.Picks or 3
	local eligible: { string } = {}
	local ok: { [string]: boolean } = {}
	for _, op in ipairs(DailyOpsConfig.Ops) do
		if not ok[op.Id] and level >= (op.MinLevel or 1) and isLive(op) then
			ok[op.Id] = true
			table.insert(eligible, op.Id)
		end
	end
	local out: { string } = {}
	local first = DailyOpsConfig.FirstJob
	if first and ok[first] then
		out = { first }
	else
		local others: { string } = {}
		for _, id in ipairs(DailyOpsConfig.OtherJobs or {}) do
			if ok[id] then
				table.insert(others, id)
			end
		end
		out = rotatePick(others, 1, userId, dayIndex, SALT_JOB)
	end
	local rest: { string } = {}
	for _, id in ipairs(eligible) do
		if not table.find(out, id) then
			table.insert(rest, id)
		end
	end
	for _, id in ipairs(rotatePick(rest, picks - #out, userId, dayIndex, SALT_OPS)) do
		table.insert(out, id)
	end
	return out
end

-- room: how many list places the ops left (MaxActiveDaily - #ops; 3 normally). Rotation's pick counts are the
-- minimum; if fewer ops were offered (Daily Ops off) the missions fill the list back up to MaxActiveDaily.
local function pickMissions(level: number, userId: number, dayIndex: number, room: number): { string }
	local rot = MissionConfig.Rotation
	local eligible: { string } = {}
	local ok: { [string]: boolean } = {}
	for _, id in ipairs(MissionConfig.DailyMissionOrder) do
		local def = MissionConfig.DailyMissions[id]
		if def and not ok[id] and level >= def.MinLevel and isLive(def) then
			ok[id] = true
			table.insert(eligible, id)
		end
	end
	if level > rot.NewPlayerMaxLevel then
		return rotatePick(eligible, math.max(rot.Picks, room), userId, dayIndex, SALT_MISSIONS)
	end
	local out: { string } = {}
	for _, id in ipairs(rot.Fixed) do
		if ok[id] and not table.find(out, id) then
			table.insert(out, id)
		end
	end
	local pool: { string } = {}
	for _, id in ipairs(eligible) do
		if not table.find(out, id) then
			table.insert(pool, id)
		end
	end
	for _, id in ipairs(rotatePick(pool, math.max(rot.NewPlayerPicks, room - #out), userId, dayIndex, SALT_MISSIONS)) do
		table.insert(out, id)
	end
	return out
end

--[[ Today's offered ids for this player (ops first). Deterministic in (UserId, DayKey, level) plus today's progress:
	any mission with progress today stays offered, taking the place of the last pick of its kind that has none. ]]
local function offerFor(userId: number, profile: Types.PlayerProfile): { string }
	local dm = profile.DailyMissions
	local dayKey = tonumber(dm.DayKey) or 0
	if dayKey < 19700101 then
		dayKey = yyyymmdd(os.time())
	end
	local dayIndex = dayIndexOf(dayKey)
	local level = levelOf(profile)
	local ops = pickOps(level, userId, dayIndex)
	local room = math.max(0, (MissionConfig.MaxActiveDaily or 6) - #ops)
	local missions = pickMissions(level, userId, dayIndex, room)
	while #missions > room do
		table.remove(missions)
	end

	local progress = dm.Progress
	local function hasProgress(id: string): boolean
		local v = progress[id]
		return type(v) == "number" and v > 0
	end
	local sticky: { string } = {}
	for id, v in pairs(progress) do
		if type(id) == "string" and type(v) == "number" and v > 0
			and not table.find(ops, id) and not table.find(missions, id) and resolveMissionDef(id) ~= nil then
			table.insert(sticky, id)
		end
	end
	if #sticky > 0 then
		table.sort(sticky)
		local ops2 = if DailyOpsConfig.Enabled then dailyOpDefs() else {}
		-- the slot-1 job op is never displaced (e.g. a level-2 player who progressed every base op reaches level 3):
		-- the sticky entry then takes another place without progress, or is added at the end of its kind
		local firstJob = DailyOpsConfig.FirstJob
		for _, id in ipairs(sticky) do
			local list = if ops2[id] then ops else missions
			local placed = false
			for j = #list, 1, -1 do
				if list[j] ~= firstJob and not hasProgress(list[j]) then
					list[j] = id
					placed = true
					break
				end
			end
			if not placed then
				table.insert(list, id)
			end
		end
	end

	local out: { string } = table.clone(ops)
	for _, id in ipairs(missions) do
		table.insert(out, id)
	end
	return out
end

local function activeDailyIds(player: Player, profile: Types.PlayerProfile): { string }
	return offerFor(player.UserId, profile)
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
	for _, id in ipairs(activeDailyIds(player, profile)) do
		local def = resolveMissionDef(id)
		if def then
			local progress = profile.DailyMissions.Progress[id] or 0
			local claimed = profile.DailyMissions.Claimed[id] == true
			local complete = progress >= def.Target
			local entry: Types.MissionEntryPayload = {
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
			}
			-- W3 step 2: GO while incomplete. Extra fields ride on the entry without a Types edit (Types is in flight)
			local go = def.Go
			if type(go) == "string" and not complete and not claimed and MissionConfig.Go[go] ~= nil then
				local targets = goTargets(go)
				if #targets > 0 then
					local e: any = entry
					e.Go = go
					e.GoTargets = targets
				end
			end
			table.insert(dailyPayload, entry)
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
	for _, id in ipairs(activeDailyIds(player, profile)) do
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
	-- only today's offer can be claimed (a completed mission always stays in it)
	if not table.find(activeDailyIds(player, profile), missionId) then
		return false, "NotOffered"
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
		NotificationService.Notify(player, "Mission reward $" .. commas(cash), "Reward")
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
