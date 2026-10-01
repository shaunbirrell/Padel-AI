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

	W3 step 2 Phase B, lane M1 (jobs):
	- MissionService.SetOpsHooks({ GoTargets, ObjectiveLive }) is called once by OpsService.Init while it runs (nil
	  clears; never yields). With no hook the offer, the GO targets and the pushes are exactly Phase A's.
	- An Ops objective (MissionConfig.OpsObjectives: Checkpoint, Camp, Uplink, Delivery, Job) is live only while
	  hooks.ObjectiveLive(type) == true. OpsService reports progress through TrackProgress(player, type, 1), the only
	  entry point it uses; nothing here trusts the client.
	- resolveGo asks hooks.GoTargets(key) first; nil ("not mine") falls back to the Phase A resolver. A Required key
	  keeps its mission on the offer while it is SERVED (the hook answers, even with no Open site right now), so the
	  day's list never reshuffles when a site cools or the director rotates.
	- Each entry carries the GoMaxTargets targets nearest to the player's character (server positions); the client
	  picks the nearest. While a hook is set, a GoRefreshSeconds timer re-sends a player's list only when it changed
	  (a target list, the offer, or the day), so GO never points at a site that closed long ago.
]]


local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
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

-- OpsService's side of the missions (W3 step 2 Phase B). nil from either function means "not mine".
export type OpsHooks = {
	GoTargets: (goKey: string) -> { MissionConfig.GoTarget }?, -- every Open site of that Go key (the client picks)
	ObjectiveLive: (objectiveType: string) -> boolean?, -- does a live job site report this objective type?
}

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

-- claude-bud JOB 29: the streak strip / tomorrow data (DailyRewardConfig.ShowTomorrow), or nil when it is not live
local function streakStrip(player: Player, profile: any, claimedToday: boolean): { [string]: any }?
	if not DailyRewardConfig.ShowTomorrowLiveFor(player.UserId) then
		return nil
	end
	local days = DailyRewardConfig.StreakResetsAfterDay
	local streak = math.max(0, math.floor(tonumber(profile.DailyLogin and profile.DailyLogin.Streak) or 0))
	local cash: { number } = {}
	local big: { boolean } = {}
	for d = 1, days do
		local r = DailyRewardConfig.Rewards[d]
		cash[d] = if r then r.Cash else 0
		big[d] = DailyRewardConfig.BigDays[d] == true
	end
	-- tomorrow's day: the day after today's claim, or the day after the one he could claim today
	local last = tonumber(profile.DailyLogin and profile.DailyLogin.LastClaimDay) or 0
	if not claimedToday and DailyRewardConfig.MissedDayResetsStreak and last ~= 0 and last ~= yyyymmdd(os.time() - 86400)
		and not MissionService.GraceCovers(player, profile.DailyLogin, os.time()) then -- claude-bud JOB 49: grace keeps it
		streak = 0 -- a missed day: the next claim starts again at day 1
	end
	local nextToClaim = (streak % days) + 1
	local tomorrowDay = if claimedToday then nextToClaim else (nextToClaim % days) + 1
	local offlineCap = 0
	local okR, RS = pcall(function(): any
		return require(script.Parent.RetentionService)
	end)
	if okR and RS and RS.OfflineCapCash then
		local okC, v = pcall(RS.OfflineCapCash, player)
		offlineCap = if okC and typeof(v) == "number" then math.floor(v) else 0
	end
	local boost = DailyRewardConfig.Day7Boost
	-- claude-bud JOB 49 A: the income-scaled Day 7, the SAVED (grace) day and the real countdown
	if DailyRewardConfig.Live("Day7Scale", player.UserId) then
		cash[days] = MissionService.Day7Cash(player, profile)
	end
	local cal = DailyRewardConfig.Live("Calendar", player.UserId)
	local dl = profile.DailyLogin or {}
	local now = os.time()
	return {
		Days = days,
		GraceDay = if cal and tonumber(dl.GraceUsedCycle) ~= nil and tonumber(dl.GraceUsedCycle) == tonumber(dl.Cycle) then tonumber(dl.GraceDay) else nil,
		ServerNow = if cal then now else nil,
		NextClaimUnix = if cal then DailyRewardConfig.NextClaimUnix(now) else nil,
		Today = if claimedToday then (if streak == 0 then 1 else streak) else nextToClaim,
		Claimed = claimedToday,
		Cash = cash,
		Big = big,
		TomorrowDay = tomorrowDay,
		TomorrowCash = cash[tomorrowDay] or 0,
		OfflineCap = offlineCap,
		OfflineCapHours = if okR and RS and RS.OfflineCapSeconds then math.floor((tonumber(RS.OfflineCapSeconds(player)) or 0) / 3600) else nil, -- claude-bud JOB 49 B
		Day7Boost = if boost.Enabled == true then boost.Label else nil,
	}
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

	local today = yyyymmdd(os.time() - MissionService.ResetOffsetSeconds()) -- claude-bud JOB 49 C: Core.ResetHourUtc (0 = 00:00 UTC)
	if MissionConfig.RefreshOnUtcDayChange and dm.DayKey ~= today then
		dm.DayKey = today
		dm.Progress = {}
		dm.Claimed = {}
		-- Keep ActiveTimed; they can finish across midnight
		local d: any = dm
		d.Core, d.CoreChest, d.RerollsUsed = nil, nil, nil -- claude-bud JOB 49 C: a fresh core list / chest / free reroll each day
	end
end

-- claude-bud JOB 49 C: the daily reset hour as an offset (Core.ResetHourUtc while Core is enabled; 0 = 00:00 UTC)
function MissionService.ResetOffsetSeconds(): number
	local core: any = (MissionConfig :: any).Core
	if typeof(core) ~= "table" or core.Enabled ~= true then
		return 0
	end
	return math.clamp(math.floor(tonumber(core.ResetHourUtc) or 0), 0, 23) * 3600
end

-- the unix time of the next daily reset after `now`
function MissionService.NextResetUnix(now: number): number
	local off = MissionService.ResetOffsetSeconds()
	return (math.floor((now - off) / 86400) + 1) * 86400 + off
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
local GO_CACHE_MAX = 64 -- targets kept per key (the payload sends the GoMaxTargets nearest)
type GoCacheRow = { At: number, List: { MissionConfig.GoTarget }, Served: boolean }
local goCache: { [string]: GoCacheRow } = {}
local goRev: { [string]: number } = {} -- bumped when a key's target list changes (the refresher compares these)
local liveCache: { [string]: { At: number, Live: boolean } } = {}
local opsHooks: OpsHooks? = nil
local hookGen = 0
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

local function finiteCoord(n: any): boolean
	return type(n) == "number" and n == n and n > -1e6 and n < 1e6
end

-- a hook's answer, checked: finite points only, rounded, at most GO_CACHE_MAX
local function cleanTargets(raw: { any }): { MissionConfig.GoTarget }
	local out: { MissionConfig.GoTarget } = {}
	for _, t in ipairs(raw) do
		if #out >= GO_CACHE_MAX then
			break
		end
		if type(t) == "table" and finiteCoord(t.X) and finiteCoord(t.Y) and finiteCoord(t.Z) then
			table.insert(out, { X = round1(t.X), Y = round1(t.Y), Z = round1(t.Z) })
		end
	end
	return out
end

--[[ The targets of a Go key and whether the key is SERVED. OpsService's hook answers first: a table (even an empty
	one while no site of that key is Open) serves the key; nil means "not mine" and the Phase A resolver runs. ]]
local function resolveGo(kind: string): ({ MissionConfig.GoTarget }, boolean)
	local gd = MissionConfig.Go[kind]
	if gd == nil then
		return {}, false
	end
	local hooks = opsHooks
	if hooks ~= nil and type(hooks.GoTargets) == "function" then
		local ok, res = pcall(hooks.GoTargets, kind)
		if not ok then
			warn("[MissionService] Ops GoTargets(" .. kind .. ") failed: " .. tostring(res))
		elseif type(res) == "table" then
			return cleanTargets(res), true
		end
	end
	-- claude-bud JOB 37: the road checkpoints with guards up (CheckpointGuardService) when Ops serves none
	if kind == "Checkpoint" then
		local okC, CG = pcall(function(): any
			return require(script.Parent.CheckpointGuardService)
		end)
		if okC and CG and CG.GoTargets then
			local okT, list = pcall(CG.GoTargets)
			if okT and type(list) == "table" and #list > 0 then
				return cleanTargets(list), true
			end
		end
	end
	local p: Vector3? = nil
	if kind == "Bank" then
		-- no Ops bank site (yet): the bank job is BankRaidService's until the cutover
		if BankRaidConfig.Enabled == false then
			return {}, false
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
		return {}, false
	end
	return { { X = round1(p.X), Y = round1(p.Y), Z = round1(p.Z) } }, true
end

local function sameTargets(a: { MissionConfig.GoTarget }, b: { MissionConfig.GoTarget }): boolean
	if #a ~= #b then
		return false
	end
	for i, t in ipairs(a) do
		local u = b[i]
		if t.X ~= u.X or t.Y ~= u.Y or t.Z ~= u.Z then
			return false
		end
	end
	return true
end

-- (targets, served) for a Go key, re-resolved at most every GO_CACHE_SECONDS
local function goLookup(kind: string): GoCacheRow
	local now = os.clock()
	local c = goCache[kind]
	if c and now - c.At < GO_CACHE_SECONDS then
		return c
	end
	local list, served = resolveGo(kind)
	if c == nil or c.Served ~= served or not sameTargets(c.List, list) then
		goRev[kind] = (goRev[kind] or 0) + 1
	end
	local row: GoCacheRow = { At = now, List = list, Served = served }
	goCache[kind] = row
	return row
end

local function goTargets(kind: string): { MissionConfig.GoTarget }
	return goLookup(kind).List
end

-- the player's character root on the SERVER (nil while they have none); never waited for
local function rootPosition(player: Player): Vector3?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

--[[ At most GoMaxTargets of a key's targets for this player: the nearest to their character (the client re-picks).
	The second value names the chosen set ("" when nothing was cut): it goes into the refresh signature, so a player
	who walks or drives across the map is re-sent the targets now nearest (at most once per refresh). ]]
local function nearestTargets(list: { MissionConfig.GoTarget }, player: Player): ({ MissionConfig.GoTarget }, string)
	local max = math.max(1, math.floor(tonumber(MissionConfig.GoMaxTargets) or 16))
	if #list <= max then
		return list, ""
	end
	local idx: { number } = table.create(#list)
	for i = 1, #list do
		idx[i] = i
	end
	local at = rootPosition(player)
	if at then
		local ax, az = at.X, at.Z
		table.sort(idx, function(i: number, j: number): boolean
			local a, b = list[i], list[j]
			local da, db = (a.X - ax) ^ 2 + (a.Z - az) ^ 2, (b.X - ax) ^ 2 + (b.Z - az) ^ 2
			if da ~= db then
				return da < db
			end
			return i < j
		end)
	end
	local out: { MissionConfig.GoTarget } = table.create(max)
	local chosen: { number } = table.create(max)
	for k = 1, max do
		out[k] = list[idx[k]]
		chosen[k] = idx[k]
	end
	table.sort(chosen)
	return out, "~" .. table.concat(chosen, ".")
end

-- an Ops objective is live only while OpsService's hook says so (cached like the GO targets)
local function opsObjectiveLive(objectiveType: string): boolean
	local hooks = opsHooks
	if hooks == nil or type(hooks.ObjectiveLive) ~= "function" then
		return false
	end
	local now = os.clock()
	local c = liveCache[objectiveType]
	if c and now - c.At < GO_CACHE_SECONDS then
		return c.Live
	end
	local ok, res = pcall(hooks.ObjectiveLive, objectiveType)
	if not ok then
		warn("[MissionService] Ops ObjectiveLive(" .. objectiveType .. ") failed: " .. tostring(res))
	end
	local live = ok and res == true
	liveCache[objectiveType] = { At = now, Live = live }
	return live
end

local function objectiveLive(objectiveType: any): boolean
	if type(objectiveType) ~= "string" then
		return false
	end
	if objectiveType == "Checkpoint" and (require(Shared.Configs.CheckpointGuardConfig) :: any).LiveForAll() then
		return true -- claude-bud JOB 37: the checkpoint guards report it (global offer: only once live for everyone)
	end
	if MissionConfig.OpsObjectives[objectiveType] == true then
		return opsObjectiveLive(objectiveType)
	end
	return MissionConfig.LiveObjectives[objectiveType] == true
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

-- can this def be offered right now (its objective is tracked, and a Required Go is served)?
local function isLive(def: any): boolean
	if not objectiveLive(def.ObjectiveType) then
		return false
	end
	local go = def.Go
	if type(go) == "string" then
		local gd = MissionConfig.Go[go]
		if gd and gd.Required == true and not goLookup(go).Served then
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

-- ── claude-bud JOB 49 C: the 3 CORE missions ───────────────────────────────────────────────────────────────────────
local SALT_CORE = 15485863
local CORE: any = (MissionConfig :: any).Core

local function coreLive(userId: number): boolean
	return typeof(CORE) == "table" and MissionConfig.CoreLiveFor(userId)
end

-- a raid is possible for him right now (the JOB 38 verdicts: RivalService lists at least one allowed base)
function MissionService.RaidPossible(player: Player?): boolean
	if player == nil then
		return false
	end
	local ok, RS = pcall(function(): any
		return (require :: any)(script.Parent.RivalService)
	end)
	if not ok or RS == nil or RS.Candidates == nil then
		return false
	end
	local okC, rows = pcall(RS.Candidates, player)
	return okC and typeof(rows) == "table" and #rows > 0
end

local function coreTypeOf(id: string): string?
	return string.match(id, "^Core(%a+)%d$")
end

-- today's core ids (saved in DailyMissions.Core on the first build of the day: the list never reshuffles)
local function coreList(userId: number, profile: Types.PlayerProfile): { string }
	local dm: any = profile.DailyMissions
	if typeof(dm.Core) == "table" and #dm.Core > 0 then
		return dm.Core
	end
	local player = Players:GetPlayerByUserId(userId)
	local raidOk = MissionService.RaidPossible(player)
	local pool: { string } = {}
	for _, t in ipairs(CORE.Pool) do
		if CORE.Types[t] ~= nil and (t ~= "Raid" or raidOk) then
			table.insert(pool, t)
		end
	end
	local tier = MissionConfig.CoreTier(levelOf(profile))
	local picks = rotatePick(pool, math.max(1, math.floor(tonumber(CORE.Count) or 3)), userId, dayIndexOf(tonumber(dm.DayKey) or 0), SALT_CORE)
	local out: { string } = {}
	for _, t in ipairs(picks) do
		table.insert(out, "Core" .. t .. tostring(math.min(tier, #CORE.Types[t].Targets)))
	end
	dm.Core = out
	if DataService and player then
		DataService.MarkDirty(player)
	end
	return out
end

-- the cash a core mission / the chest pays: max(the floor, minutes x his income per minute)
local function incomeScaled(player: Player, profile: any, floorCash: number, minutes: number): number
	local okM, MS = pcall(function(): any
		return (require :: any)(script.Parent.MonetizationService)
	end)
	local perMin = 0
	if okM and MS and MS.PassivePerMin then
		local okP, v = pcall(MS.PassivePerMin, player, profile, true)
		perMin = if okP and typeof(v) == "number" and v == v and v > 0 then v else 0
	end
	return math.max(math.floor(floorCash), math.floor(perMin * math.max(0, minutes)))
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
	if coreLive(userId) then
		-- claude-bud JOB 49 C: the 3 core missions on top, the Daily Ops below (unchanged)
		local out: { string } = table.clone(coreList(userId, profile))
		for _, id in ipairs(ops) do
			table.insert(out, id)
		end
		return out
	end
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

-- what each player was last sent (weak keys: a player who left is dropped with their Player object)
local lastSig: { [Player]: string } = setmetatable({}, { __mode = "k" }) :: any

--[[ The player's mission state and a short signature of everything in it that can change without a TrackProgress
	(the offer, the day, each Go key's target revision). The refresher re-sends only when the signature changes. ]]
local function buildPayload(player: Player, profile: Types.PlayerProfile): (Types.MissionStatePayload, string)
	ensureDaily(profile)
	local sig: { string } = { tostring(profile.DailyMissions.DayKey) }

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
			if coreTypeOf(id) and coreLive(player.UserId) then
				-- claude-bud JOB 49 C: a core row: the real (income-scaled) reward, client GO, reroll allowed
				local e: any = entry
				e.Core = true
				e.RewardCash = incomeScaled(player, profile, def.RewardCash, tonumber(CORE.RewardIncomeMinutes) or 0)
				e.CanReroll = not claimed and not complete and MissionService.RerollsLeft(player, profile) > 0
				-- Code Bot v180: free reroll used and no token: the 19 R$ reroll button (prompts DevProducts.MissionReroll;
				-- ProcessReceipt grants the token, the reroll itself stays MissionService.Reroll)
				e.CanBuyReroll = if not claimed and not complete and not e.CanReroll and MissionService.RerollBuyLive(player) then true else nil
				if def.Go == "Build" then
					e.GoStructure = MissionService.NextBuild(profile)
				end
			end
			-- W3 step 2: GO while incomplete. Extra fields ride on the entry without a Types edit (Types is in flight)
			local go = def.Go
			local goBit = ""
			local goDef: any = if type(go) == "string" then MissionConfig.Go[go] else nil
			if goDef and goDef.Client == true then
				-- claude-bud JOB 49 C: a client-side GO (the TARGETS card / Army panel / next console): no world target
				if not complete and not claimed then
					local e: any = entry
					e.Go = go
					goBit = go
				end
			elseif type(go) == "string" and not complete and not claimed and MissionConfig.Go[go] ~= nil then
				local targets = goTargets(go)
				goBit = go .. "@" .. tostring(goRev[go] or 0)
				if #targets > 0 then
					local e: any = entry
					e.Go = go
					local near, setKey = nearestTargets(targets, player)
					e.GoTargets = near
					goBit ..= setKey
				end
			end
			table.insert(sig, id .. ":" .. tostring(entry.Progress) .. ":" .. (if claimed then "C" elseif complete then "D" else "") .. goBit)
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
	table.insert(sig, if already then "L1" else "L0")
	if coreLive(player.UserId) then
		-- claude-bud JOB 49 C: the real time to the next reset, the free rerolls left, the chest
		local now = os.time()
		local dm: any = profile.DailyMissions
		;(payload :: any).Core = {
			ServerNow = now,
			ResetUnix = MissionService.NextResetUnix(now),
			RerollsLeft = MissionService.RerollsLeft(player, profile),
			ChestDone = dm.CoreChest == true,
		}
		table.insert(sig, "C" .. tostring(MissionService.RerollsLeft(player, profile)) .. (if dm.CoreChest == true then "X" else ""))
	end
	-- claude-bud JOB 29: the 7-day strip + tomorrow goals ride on the payload (nil while ShowTomorrow is off)
	local strip = streakStrip(player, profile, already)
	if strip then
		(payload :: any).Streak7 = strip
		table.insert(sig, "S" .. tostring(strip.Today) .. ":" .. tostring(strip.OfflineCap))
	end
	return payload, table.concat(sig, "|")
end

local function send(player: Player, payload: Types.MissionStatePayload, sig: string)
	lastSig[player] = sig
	local remote = RemoteSetup.Get(Constants.RemoteNames.MissionStateUpdate) :: RemoteEvent
	remote:FireClient(player, payload)
end

function MissionService.Push(player: Player)
	if not DataService or not RemoteSetup then
		return
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	local payload, sig = buildPayload(player, profile)
	send(player, payload, sig)
end

-- ── Ops hooks (W3 step 2 Phase B) ─────────────────────────────────────────────────────────────────────────────────
-- re-send a player's list only when it changed (a Go key's targets, the offer or the day); never per frame
local function refreshPlayer(player: Player)
	if lastSig[player] == nil or not DataService or not RemoteSetup then
		return -- never pushed yet: the profile-load push comes first
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	local payload, sig = buildPayload(player, profile)
	if sig ~= lastSig[player] then
		send(player, payload, sig)
	end
end

local function scheduleRefresh(gen: number)
	local period = tonumber(MissionConfig.GoRefreshSeconds) or 0
	if period <= 0 then
		return
	end
	task.delay(math.max(5, period), function()
		if gen ~= hookGen or opsHooks == nil then
			return -- the hooks were replaced or cleared: that call runs its own timer
		end
		for _, player in ipairs(Players:GetPlayers()) do
			local ok, err = pcall(function(): any
				refreshPlayer(player)
				return nil
			end)
			if not ok then
				warn("[MissionService] GO refresh failed: " .. tostring(err))
			end
		end
		scheduleRefresh(gen)
	end)
end

--[[ OpsService.Init calls this once while it runs; nil clears it. Never yields. Hook answers are cached like the GO
	targets (GO_CACHE_SECONDS) and a hook that errors counts as "not mine". ]]
function MissionService.SetOpsHooks(hooks: OpsHooks?)
	if hooks ~= nil and type(hooks) ~= "table" then
		return
	end
	opsHooks = hooks
	hookGen += 1
	table.clear(goCache)
	table.clear(liveCache)
	if hooks ~= nil then
		scheduleRefresh(hookGen)
	end
end

-- claude-bud JOB 34: AchievementService (lazy; nil until it loads). While AchievementConfig.Live is on for a player it
-- handles every achievement (the full list, chat, badges); off = the old 3-achievement path below, unchanged.
local function achievements(): any
	local ok, AS = pcall(function(): any
		return require(script.Parent.AchievementService)
	end)
	return if ok then AS else nil
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
	local ach = achievements()
	if ach and ach.Check and ach.Check(player) then
		return -- claude-bud JOB 34: the full achievement list handled it
	end
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

	local ach = achievements()
	if ach and ach.Note then
		ach.Note(player, objectiveType) -- claude-bud JOB 34: event achievements (first NPC kill; a player kill re-checks)
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
	local isCore = coreTypeOf(missionId) ~= nil and coreLive(player.UserId)
	if isCore then
		cash = incomeScaled(player, profile, def.RewardCash, tonumber(CORE.RewardIncomeMinutes) or 0) -- claude-bud JOB 49 C
	end
	if TerritoryService and TerritoryService.GetMissionCashMult then
		cash = math.floor(cash * TerritoryService.GetMissionCashMult(player))
	end
	if cash > 0 then
		EconomyService.AddCash(player, cash, "mission")
	end
	if isCore then
		MissionService.CoreClaimed(player, profile, missionId)
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

--[[ claude-bud JOB 49 A: true when the grace rule keeps this streak across the gap to `now`: Grace live, the last claim
	was 2 .. MissedDaysAllowed + 1 UTC days ago, and no grace used in this 7-day cycle yet (PerCycle 1). Pure reads. ]]
function MissionService.GraceCovers(player: Player, daily: any, now: number): boolean
	if typeof(daily) ~= "table" or not DailyRewardConfig.Live("Grace", player.UserId) then
		return false
	end
	local G: any = (DailyRewardConfig :: any).Grace
	local last = tonumber(daily.LastClaimDay) or 0
	if last == 0 or (tonumber(daily.Streak) or 0) <= 0 then
		return false
	end
	if (tonumber(G.PerCycle) or 1) <= 0 or tonumber(daily.GraceUsedCycle) == (tonumber(daily.Cycle) or 0) then
		return false -- already used in this cycle
	end
	for k = 2, 1 + math.max(0, math.floor(tonumber(G.MissedDaysAllowed) or 1)) do
		if last == yyyymmdd(now - k * 86400) then
			return true
		end
	end
	return false
end

-- claude-bud JOB 49 A: Day 7's cash: max(the table floor, Day7Scale.IncomeMinutes x income per minute) while live
function MissionService.Day7Cash(player: Player, profile: any): number
	local days = DailyRewardConfig.StreakResetsAfterDay
	local floorCash = (DailyRewardConfig.Rewards[days] or { Cash = 0 }).Cash
	if not DailyRewardConfig.Live("Day7Scale", player.UserId) then
		return floorCash
	end
	local okM, MS = pcall(function(): any
		return (require :: any)(script.Parent.MonetizationService) -- dynamic: keeps it out of this module's type graph
	end)
	local perMin = 0
	if okM and MS and MS.PassivePerMin then
		local okP, v = pcall(MS.PassivePerMin, player, profile, true)
		perMin = if okP and typeof(v) == "number" and v == v and v > 0 then v else 0
	end
	local mins = math.max(0, tonumber((DailyRewardConfig :: any).Day7Scale.IncomeMinutes) or 0)
	return math.max(floorCash, math.floor(perMin * mins))
end

-- ── claude-bud JOB 49 C: chest, reroll, next build ─────────────────────────────────────────────────────────────────
-- a core mission was claimed: MissionDone, and the chest once all of today's core missions are claimed
function MissionService.CoreClaimed(player: Player, profile: any, missionId: string)
	local dm: any = profile.DailyMissions
	if AnalyticsService then
		AnalyticsService.Log("MISSION_DONE", player.UserId, { type = coreTypeOf(missionId) or "?" })
	end
	if dm.CoreChest == true or typeof(dm.Core) ~= "table" then
		return
	end
	for _, id in ipairs(dm.Core) do
		if dm.Claimed[id] ~= true then
			return
		end
	end
	dm.CoreChest = true
	local chest = CORE.Chest
	local cash = incomeScaled(player, profile, tonumber(chest.Cash) or 0, tonumber(chest.IncomeMinutes) or 0)
	if cash > 0 then
		EconomyService.AddCash(player, cash, "mission_chest")
	end
	if (tonumber(chest.Gold) or 0) > 0 then
		EconomyService.AddGold(player, math.floor(chest.Gold), "mission_chest")
	end
	if NotificationService then
		NotificationService.Notify(player, "All 3 missions done! Chest +$" .. commas(cash), "Reward")
	end
	if AnalyticsService then
		AnalyticsService.Log("MISSIONS_ALL_DONE", player.UserId, { cash = cash })
	end
end

-- Code Bot v180: the paid reroll is on sale to this player (Reroll.Robux live + the product Id set)
function MissionService.RerollBuyLive(player: Player): boolean
	if typeof(CORE) ~= "table" or not coreLive(player.UserId) then
		return false
	end
	local robux: any = CORE.Reroll.Robux
	if not (require(Shared.Configs.RetentionConfig) :: any).Live(robux, player.UserId) then
		return false
	end
	local MC: any = require(Shared.Configs.MonetizationConfig)
	local def = MC.DevProducts[robux.ProductKey]
	return typeof(def) == "table" and (tonumber(def.Id) or 0) ~= 0
end

-- free rerolls left today (+ Robux reroll tokens while Reroll.Robux is live; Code Bot v180: live)
function MissionService.RerollsLeft(player: Player, profile: any): number
	if typeof(CORE) ~= "table" or not coreLive(player.UserId) then
		return 0
	end
	local dm: any = profile.DailyMissions
	local free = math.max(0, math.floor(tonumber(CORE.Reroll.FreePerDay) or 0) - math.floor(tonumber(dm.RerollsUsed) or 0))
	local robux = 0
	if (require(Shared.Configs.RetentionConfig) :: any).Live(CORE.Reroll.Robux, player.UserId) then
		robux = math.max(0, math.floor(tonumber(profile.MissionRerollTokens) or 0))
	end
	return free + robux
end

--[[ Reroll one of today's core missions (server-checked; never gives a reward): it must be offered, not claimed and
	not complete. The free reroll first (saved per day), then a Robux token (only while that hook is live). The new
	mission is another loop type at the same tier that is not already in today's list (Raid only when a raid is
	possible). ]]
function MissionService.Reroll(player: Player, missionId: any): (boolean, string?)
	if not RemoteGuard.IsIdString(missionId, 48) or not coreLive(player.UserId) then
		return false, "Off"
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end
	ensureDaily(profile)
	local dm: any = profile.DailyMissions
	local list = coreList(player.UserId, profile)
	local slot = table.find(list, missionId)
	local def = resolveMissionDef(missionId)
	if slot == nil or def == nil then
		return false, "NotOffered"
	end
	if dm.Claimed[missionId] == true or (dm.Progress[missionId] or 0) >= def.Target then
		return false, "Done"
	end
	local free = math.max(0, math.floor(tonumber(CORE.Reroll.FreePerDay) or 0) - math.floor(tonumber(dm.RerollsUsed) or 0))
	local useToken = false
	if free <= 0 then
		if MissionService.RerollsLeft(player, profile) <= 0 then
			return false, "NoRerolls"
		end
		useToken = true
	end
	local have: { [string]: boolean } = {}
	for _, id in ipairs(list) do
		local t = coreTypeOf(id)
		if t then
			have[t] = true
		end
	end
	local raidOk = MissionService.RaidPossible(player)
	local tier = string.match(missionId, "(%d)$") or "1"
	local pick: string? = nil
	for _, t in ipairs(CORE.Pool) do
		if not have[t] and CORE.Types[t] ~= nil and (t ~= "Raid" or raidOk) then
			pick = t
			break
		end
	end
	if pick == nil then
		return false, "NoOther"
	end
	local newId = "Core" .. pick .. tostring(math.min(tonumber(tier) or 1, #CORE.Types[pick].Targets))
	list[slot] = newId
	dm.Core = list
	dm.Progress[missionId] = nil
	if useToken then
		profile.MissionRerollTokens = math.max(0, (tonumber(profile.MissionRerollTokens) or 0) - 1)
	else
		dm.RerollsUsed = (tonumber(dm.RerollsUsed) or 0) + 1
	end
	DataService.MarkDirty(player)
	if AnalyticsService then
		AnalyticsService.Log("MISSION_REROLL", player.UserId, { kind = if useToken then "robux" else "free" })
	end
	MissionService.Push(player)
	return true, nil
end

-- the Robux reroll's grant (MonetizationService ProcessReceipt, once per receipt; Code Bot v180: 3715836569, 19 R$)
function MissionService.GrantRerollToken(player: Player): boolean
	local profile = DataService and DataService.GetProfile(player)
	if not profile then
		return false
	end
	profile.MissionRerollTokens = math.max(0, math.floor(tonumber(profile.MissionRerollTokens) or 0)) + 1
	DataService.MarkDirty(player)
	MissionService.Push(player)
	return true
end

-- the Build mission's GO: his cheapest next base upgrade (the console the gold line goes to)
function MissionService.NextBuild(profile: any): string?
	local okB, BC = pcall(function(): any
		return require(Shared.Configs.BaseConfig)
	end)
	if not okB or typeof(BC) ~= "table" or typeof(BC.Structures) ~= "table" then
		return nil
	end
	local best, bestCost = nil, math.huge
	for id, s in pairs(BC.Structures) do
		local lv = if typeof(profile.BaseUpgrades) == "table" then math.floor(tonumber(profile.BaseUpgrades[id]) or 0) else 0
		local costs = if typeof(s) == "table" then s.Costs else nil
		local cost = if typeof(costs) == "table" then tonumber(costs[lv + 1]) else nil
		if cost and cost < bestCost then
			best, bestCost = id, cost
		end
	end
	return best
end

-- quiet (claude-bud JOB 29): no "Day N reward" toast (the caller shows the streak card instead)
function MissionService.ClaimDailyLogin(player: Player, quiet: boolean?): (boolean, string?)
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
	local graced = false
	local lastDay = daily.Streak
	if DailyRewardConfig.MissedDayResetsStreak and daily.LastClaimDay ~= 0 and daily.LastClaimDay ~= yesterday then
		if MissionService.GraceCovers(player, daily, os.time()) then
			-- claude-bud JOB 49 A: one missed day per cycle keeps the streak; the missed day is marked SAVED
			graced = true
			daily.GraceUsedCycle = tonumber(daily.Cycle) or 0
			daily.GraceDay = (daily.Streak % DailyRewardConfig.StreakResetsAfterDay) + 1
		else
			daily.Streak = 0
			if AnalyticsService and lastDay > 0 then
				AnalyticsService.Log("STREAK_RESET", player.UserId, { lastDay = lastDay }) -- claude-bud JOB 49
			end
		end
	end

	daily.Streak = (daily.Streak % DailyRewardConfig.StreakResetsAfterDay) + 1
	daily.LastClaimDay = today
	daily.LastClaimUnix = os.time()
	if daily.Streak == 1 then
		daily.Cycle = (tonumber(daily.Cycle) or 0) + 1 -- claude-bud JOB 49 A: a new 7-day cycle (its own grace)
		daily.GraceDay = nil
	end

	local reward = DailyRewardConfig.Rewards[daily.Streak]
	if reward then
		-- claude-bud JOB 49 A: Day 7 scales with his income (the table is the floor)
		local cashPaid = if daily.Streak == DailyRewardConfig.StreakResetsAfterDay then MissionService.Day7Cash(player, profile) else reward.Cash
		if cashPaid > 0 then
			EconomyService.AddCash(player, cashPaid, "daily")
		end
		if reward.Gold > 0 then
			EconomyService.AddGold(player, reward.Gold, "daily")
		end
		if reward.XP > 0 then
			XPService.AddXP(player, reward.XP, "daily")
		end
		if NotificationService and quiet ~= true then
			-- claude-bud JOB 29 (DailyRewardConfig.ShowTomorrow): tomorrow's reward wherever the streak is shown
			local nextReward = DailyRewardConfig.Rewards[(daily.Streak % DailyRewardConfig.StreakResetsAfterDay) + 1]
			NotificationService.Notify(
				player,
				if DailyRewardConfig.ShowTomorrow == true and nextReward
					then string.format("Day %d: +$%s. Tomorrow: $%s", daily.Streak, commas(cashPaid), commas(nextReward.Cash))
					else string.format("Day %d reward: $%d", daily.Streak, reward.Cash),
				"Reward"
			)
		end
		if AnalyticsService then
			AnalyticsService.Log(AnalyticsConfig.Events.DAILY_REWARD_CLAIMED, player.UserId, { day = daily.Streak })
			AnalyticsService.Log("STREAK_DAY", player.UserId, { day = daily.Streak }) -- claude-bud JOB 29
			AnalyticsService.Log("STREAK_CLAIMED", player.UserId, { day = daily.Streak, grace = if graced then "yes" else "no", cash = cashPaid }) -- claude-bud JOB 49
		end
		-- claude-bud JOB 29: day 7 = an army damage boost for a while (no Robux; SquadOrdersService reads it)
		local boost = DailyRewardConfig.Day7Boost
		if daily.Streak == DailyRewardConfig.StreakResetsAfterDay and boost.Enabled == true and DailyRewardConfig.ShowTomorrowLiveFor(player.UserId) then
			local untilUnix = os.time() + math.max(1, math.floor(tonumber(boost.Minutes) or 30)) * 60
			;(profile :: any).ArmyBoostUntil = untilUnix
			player:SetAttribute("WE_ArmyBoostUntil", untilUnix)
		end
	end
	MissionService.CheckAchievements(player) -- claude-bud JOB 34: the 7-day streak achievement
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
		if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestStartMission", missionId) then -- claude-bud JOB 15: rate ceiling + argument schema
			return
		end
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
		if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestClaimMission", missionId) then -- claude-bud JOB 15: rate ceiling + argument schema
			return
		end
		if not RateLimitService.Allow(player, "claim_mission", 2, 3) then
			return
		end
		MissionService.ClaimDailyMission(player, missionId)
		pcall(function() -- claude-bud JOB 48: the Hook's "Open Missions" step also finishes on a claim
			(require(script.Parent.TutorialService) :: any).Notify(player, "ClaimMission")
		end)
	end)

	-- claude-bud JOB 49 C: reroll one of today's core missions (the mission id only; every rule is checked here)
	local rerollRemote = RemoteSetup.Get(Constants.RemoteNames.RequestMissionReroll) :: RemoteEvent
	rerollRemote.OnServerEvent:Connect(function(player: Player, missionId: any)
		if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestMissionReroll", missionId) then
			return
		end
		if not RateLimitService.Allow(player, "mission_reroll", 1, 2) then
			return
		end
		MissionService.Reroll(player, missionId)
	end)

	local dailyRemote = RemoteSetup.Get(Constants.RemoteNames.RequestClaimDailyReward) :: RemoteEvent
	dailyRemote.OnServerEvent:Connect(function(player: Player)
		if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestClaimDailyReward") then -- claude-bud JOB 15: rate ceiling + argument schema
			return
		end
		if not RateLimitService.Allow(player, "daily_reward", 1, 2) then
			return
		end
		MissionService.ClaimDailyLogin(player)
	end)

	DataService.OnProfileLoaded(function(player: Player, _profile: Types.PlayerProfile)
		ensureDaily(_profile)
		MissionService.CheckAchievements(player)
		MissionService.Push(player)
		-- claude-bud JOB 4.2: auto-claim today's login reward (DailyRewardConfig.AutoClaim, owner-only first)
		if DailyRewardConfig.AutoClaimLiveFor(player.UserId) then
			task.delay(DailyRewardConfig.AutoClaim.DelaySeconds, function()
				if player.Parent == nil then
					return
				end
				-- claude-bud JOB 29: nothing covers a new player's screen before the Command Center (FastStart hold)
				local okR, RS = pcall(function(): any
					return require(script.Parent.RetentionService)
				end)
				-- claude-bud JOB 49 A (Calendar): wait out the Guided chain (the hold ends at its reward), at the latest
				-- until FirstCardSeconds of play; OFF = the JOB 29 90 s
				local holdMax = 90
				if DailyRewardConfig.Live("Calendar", player.UserId) then
					holdMax = math.max(0, (tonumber((DailyRewardConfig :: any).Calendar.FirstCardSeconds) or 150) - DailyRewardConfig.AutoClaim.DelaySeconds)
				end
				if okR and RS and RS.WaitOnboarding and not RS.WaitOnboarding(player, holdMax) then
					return
				end
				local prof = DataService.GetProfile(player)
				if prof == nil or prof.DailyLogin == nil or prof.DailyLogin.LastClaimDay == yyyymmdd(os.time()) then
					return
				end
				local card = DailyRewardConfig.ShowTomorrowLiveFor(player.UserId)
				local okClaim = MissionService.ClaimDailyLogin(player, card)
				if okClaim and card then
					-- claude-bud JOB 29: ONE card with the 7-day strip and "Come back tomorrow for $Y"
					local strip = streakStrip(player, prof, true)
					local ev = RemoteSetup and RemoteSetup.Get(Constants.RemoteNames.FeaturePush)
					if strip and ev and ev:IsA("RemoteEvent") then
						strip.Boost = (tonumber((prof :: any).ArmyBoostUntil) or 0) > os.time() and prof.DailyLogin.Streak == DailyRewardConfig.StreakResetsAfterDay
						strip.BoostMinutes = DailyRewardConfig.Day7Boost.Minutes
						strip.Seconds = DailyRewardConfig.CardSeconds
						;(ev :: RemoteEvent):FireClient(player, "Streak", strip)
					end
				elseif okClaim and NotificationService then
					local day = prof.DailyLogin.Streak
					local nextDay = (day % DailyRewardConfig.StreakResetsAfterDay) + 1
					local nextReward = DailyRewardConfig.Rewards[nextDay]
					NotificationService.Notify(
						player,
						string.format("Login streak: day %d of %d. Tomorrow: $%d", day, DailyRewardConfig.StreakResetsAfterDay, if nextReward then nextReward.Cash else 0),
						"Info"
					)
				end
			end)
		end
	end)
end

return MissionService
