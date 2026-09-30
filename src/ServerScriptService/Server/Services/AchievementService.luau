--!strict
--[[
	claude-bud JOB 34 (2026-09-30): achievements, chat shout-outs and Roblox badges. Server-authoritative; the list is
	AchievementConfig.Achievements.
	  * ONCE per player: profile.Achievements[id] = true (the existing saved map) + profile.AchievementsAt[id] = os.time().
	  * Progress reads the counters the game already keeps (AchievementConfig Stat paths: Stats.*, LB.Kills (validated PvP
	    kills), Prestige, NukeStats.Launched, BaseUpgrades.CommandCenter, Soldiers, DailyLogin.Streak, Level). Event
	    achievements ("KillNPC", "Crown") are granted when that event is noted.
	  * Hooks (all one line, lazy): MissionService.TrackProgress / CheckAchievements (cash, builds, captures, recruits,
	    NPC + player kills, profile load), ClaimDailyLogin, PrestigeService.DoPrestige (OnRebirth), NukeService.Launch
	    (NukeStats.Launched += 1), EngagementService crownNote (Note "Crown"), SoldierService.OnArmyChanged.
	  * First check of a profile (AchievementsSeeded): what the player already reached is granted QUIETLY (rewards +
	    badges, one toast, no popups or chat), so an old player joining does not flood the server.
	  * Earner: FeaturePush "AchUnlocked" (popup + sound) + the config reward (AddCash / AddGold / AddXP "achievement";
	    "achievement" cash never re-enters TrackProgress).
	  * Everyone: FeaturePush "AchShout" { Name, Text, Big } -> one TextChatService system line (Big = a banner too).
	    Rate limited server-wide (AchievementConfig.Shout: one line per GapSeconds, a player's lines within
	    CombineSeconds merge, small lines dropped past MaxQueue).
	  * Badges: BadgeService:AwardBadge only for BadgeId ~= 0, after UserHasBadgeAsync, pcall + retries; re-synced once
	    per session on join so a failed award is retried later.
	  * Analytics ACHIEVEMENT_UNLOCKED { id, backfill } per unlock.
	  * The page: RequestAchievements -> FeaturePush "AchState" { List, Earned, Total }.
	Owner / admin accounts earn and are announced like anyone (they stay off the leaderboards, EngagementService).
	Kill switch: AchievementConfig.Live (owner-first). Off = MissionService's old 3-achievement path, untouched.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BadgeService = game:GetService("BadgeService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local AchievementConfig = require(Shared.Configs.AchievementConfig)
local RetentionConfig = require(Shared.Configs.RetentionConfig)

local AchievementService = {}

type Def = AchievementConfig.Achievement
export type Shout = { Uid: number, Name: string, Text: string, Big: boolean, Extra: number, At: number }

local deps: { [string]: any } = {}
local checking: { [Player]: boolean } = {}
local badgeSynced: { [Player]: boolean } = {}
local rebirthShouted: { [number]: number } = {} -- uid -> the prestige already announced
local queue: { Shout } = {}
local lastSent = -math.huge
local pumping = false
local clock: () -> number = os.clock

local ORDERED: { Def } = {}
for _, d in pairs(AchievementConfig.Achievements) do
	table.insert(ORDERED, d)
end
table.sort(ORDERED, function(a: Def, b: Def)
	return a.Order < b.Order
end)

local function live(uid: number): boolean
	return RetentionConfig.Live(AchievementConfig.Live, uid)
end

function AchievementService.LiveFor(uid: number): boolean
	return live(uid)
end

-- "1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st" ...
function AchievementService.Ordinal(n: number): string
	n = math.floor(n)
	local h = n % 100
	local suffix = "th"
	if h < 11 or h > 13 then
		local t = n % 10
		suffix = if t == 1 then "st" elseif t == 2 then "nd" elseif t == 3 then "rd" else "th"
	end
	return tostring(n) .. suffix
end

-- a number at a dotted profile path ("Stats.TotalCashEarned"); 0 when missing
function AchievementService.StatValue(profile: any, path: string): number
	local v: any = profile
	for key in string.gmatch(path, "[^%.]+") do
		if typeof(v) ~= "table" then
			return 0
		end
		v = v[key]
	end
	return tonumber(v) or 0
end

--[[ The rate-limit queue (pure; tests call it). Adds `e` at time `now`:
	"combined" = merged into the same player's queued line (count + the bigger text wins);
	"queued" = added; "dropped" = the queue is full of lines at least as important. ]]
function AchievementService.Combine(q: { Shout }, e: Shout, now: number): string
	local S = AchievementConfig.Shout
	for _, old in ipairs(q) do
		if old.Uid == e.Uid and now - old.At <= S.CombineSeconds then
			old.Extra += 1 + e.Extra
			if e.Big and not old.Big then
				old.Text = e.Text
				old.Big = true
			end
			return "combined"
		end
	end
	if #q >= S.MaxQueue then
		if not e.Big then
			return "dropped"
		end
		local drop: number? = nil
		for i, old in ipairs(q) do
			if not old.Big then
				drop = i
				break
			end
		end
		if drop == nil then
			return "dropped"
		end
		table.remove(q, drop :: number)
	end
	e.At = now
	table.insert(q, e)
	return "queued"
end

local function push(target: Player?, kind: string, data: any)
	local rs = deps.RemoteSetup
	local ev = rs and rs.Get(Constants.RemoteNames.FeaturePush)
	if ev == nil or not ev:IsA("RemoteEvent") then
		return
	end
	if target then
		(ev :: RemoteEvent):FireClient(target, kind, data)
	else
		(ev :: RemoteEvent):FireAllClients(kind, data)
	end
end

local function send(e: Shout)
	local text = e.Text
	if e.Extra > 0 then
		text ..= string.format(" (+%d more)", e.Extra)
	end
	push(nil, "AchShout", { Name = e.Name, Text = text, Big = e.Big })
end

local function pump()
	if pumping then
		return
	end
	pumping = true
	task.spawn(function()
		while #queue > 0 do
			local wait = lastSent + AchievementConfig.Shout.GapSeconds - clock()
			if wait > 0 then
				task.wait(wait)
			end
			local e = table.remove(queue, 1)
			if e then
				lastSent = clock()
				pcall(send, e)
			end
		end
		pumping = false
	end)
end

function AchievementService.Shout(player: Player, text: string, big: boolean)
	AchievementService.Combine(queue, { Uid = player.UserId, Name = player.Name, Text = text, Big = big, Extra = 0, At = 0 }, clock())
	pump()
end

local function fill(template: string, profile: any, info: any): string
	local out = string.gsub(template, "{nth}", function()
		return AchievementService.Ordinal(math.max(1, AchievementService.StatValue(profile, "Prestige")))
	end)
	out = string.gsub(out, "{label}", function()
		return tostring(typeof(info) == "table" and info.Label or "a leaderboard")
	end)
	return out
end

-- one award attempt chain (pcall, UserHasBadgeAsync first, retried); BadgeId 0 = nothing
local function awardBadge(player: Player, def: Def)
	local bid = math.floor(tonumber(def.BadgeId) or 0)
	if bid <= 0 then
		return
	end
	local B = AchievementConfig.Badges
	for attempt = 1, B.Retries do
		if player.Parent == nil then
			return
		end
		local okH, has = pcall(function()
			return BadgeService:UserHasBadgeAsync(player.UserId, bid)
		end)
		if okH and has == true then
			return
		end
		if okH then
			local okA, res = pcall(function()
				return BadgeService:AwardBadge(player.UserId, bid)
			end)
			if okA and res == true then
				return
			end
		end
		task.wait(B.RetryDelaySeconds * attempt)
	end
end

function AchievementService.Progress(profile: any, def: Def): (number, number)
	local earned = typeof(profile.Achievements) == "table" and profile.Achievements[def.Id] == true
	if def.Stat and def.Target then
		local target = def.Target :: number
		return if earned then target else math.min(target, AchievementService.StatValue(profile, def.Stat :: string)), target
	end
	return if earned then 1 else 0, 1
end

function AchievementService.State(profile: any): any
	local list = {}
	local earned = 0
	for _, def in ipairs(ORDERED) do
		local have, target = AchievementService.Progress(profile, def)
		local done = typeof(profile.Achievements) == "table" and profile.Achievements[def.Id] == true
		if done then
			earned += 1
		end
		table.insert(list, {
			Id = def.Id,
			Title = def.Title or def.DisplayName,
			Desc = def.Description,
			Done = done,
			Have = have,
			Target = target,
			Cash = def.RewardCash,
			Gold = def.RewardGold,
		})
	end
	return { List = list, Earned = earned, Total = #ORDERED }
end

local function pushState(player: Player)
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	if profile then
		push(player, "AchState", AchievementService.State(profile))
	end
end

--[[ Grant one achievement (once). opts: Quiet = no popup / chat (the first-check backfill), NoShout, Info (tokens).
	Returns true when it was newly granted. ]]
function AchievementService.Grant(player: Player, profile: any, id: string, opts: any?): boolean
	local def = AchievementConfig.Achievements[id]
	if def == nil then
		return false
	end
	if typeof(profile.Achievements) ~= "table" then
		profile.Achievements = {}
	end
	if profile.Achievements[id] == true then
		return false
	end
	local o = opts or {}
	profile.Achievements[id] = true
	if typeof(profile.AchievementsAt) ~= "table" then
		profile.AchievementsAt = {}
	end
	profile.AchievementsAt[id] = os.time()
	local econ = deps.EconomyService
	if econ then
		if def.RewardCash > 0 then
			pcall(econ.AddCash, player, def.RewardCash, "achievement")
		end
		if def.RewardGold > 0 then
			pcall(econ.AddGold, player, def.RewardGold, "achievement")
		end
	end
	if def.RewardXP > 0 and deps.XPService then
		pcall(deps.XPService.AddXP, player, def.RewardXP, "achievement")
	end
	if deps.DataService then
		pcall(deps.DataService.MarkDirty, player)
	end
	if deps.AnalyticsService then
		local ev = ((require(Shared.Configs.AnalyticsConfig) :: any).Events or {}).ACHIEVEMENT_UNLOCKED or "ACHIEVEMENT_UNLOCKED"
		pcall(deps.AnalyticsService.Log, ev, player.UserId, { id = id, backfill = o.Quiet == true })
	end
	task.spawn(awardBadge, player, def)
	if o.Quiet ~= true then
		push(player, "AchUnlocked", {
			Id = id,
			Title = def.Title or def.DisplayName,
			Desc = def.Description,
			Cash = def.RewardCash,
			Gold = def.RewardGold,
			XP = def.RewardXP,
			Big = def.Big == true,
		})
		if def.Shout and o.NoShout ~= true then
			if def.Stat == "Prestige" then
				rebirthShouted[player.UserId] = AchievementService.StatValue(profile, "Prestige")
			end
			AchievementService.Shout(player, fill(def.Shout :: string, profile, o.Info), def.Big == true)
		end
	end
	return true
end

-- every Stat achievement reached and not yet earned; the first check of a profile grants quietly
local function evaluate(player: Player, profile: any): { string }
	local seeding = profile.AchievementsSeeded ~= true
	local granted: { string } = {}
	for _, def in ipairs(ORDERED) do
		if def.Stat and def.Target and AchievementService.StatValue(profile, def.Stat :: string) >= (def.Target :: number) then
			if AchievementService.Grant(player, profile, def.Id, { Quiet = seeding }) then
				table.insert(granted, def.Id)
			end
		end
	end
	if seeding then
		profile.AchievementsSeeded = true
		if deps.DataService then
			pcall(deps.DataService.MarkDirty, player)
		end
		local ns = deps.NotificationService
		if #granted > 0 and ns and ns.Notify then
			pcall(ns.Notify, player, string.format("%d achievements unlocked! See Missions.", #granted), "Reward", 5)
		end
	end
	if #granted > 0 then
		pushState(player)
	end
	return granted
end

--[[ Re-check the Stat achievements. Returns true when the JOB 34 path handled it (live for this player), so
	MissionService skips its old 3-achievement check. ]]
function AchievementService.Check(player: Player): boolean
	if deps.DataService == nil or not live(player.UserId) then
		return false
	end
	local profile = deps.DataService.GetProfile(player)
	if profile == nil or checking[player] then
		return true
	end
	checking[player] = true
	local ok, err = pcall(evaluate, player, profile)
	checking[player] = nil
	if not ok then
		warn("[WAR EMPIRE] AchievementService.Check: " .. tostring(err))
	end
	return true
end

-- an event (MissionService objective types, "Crown"): grants the Event achievements; "KillPlayer" re-checks once
-- EngagementService has counted the validated kill (LB.Kills)
function AchievementService.Note(player: Player, event: string, info: any?)
	if deps.DataService == nil or not live(player.UserId) then
		return
	end
	if event == "KillPlayer" then
		task.delay(0.5, function()
			if player.Parent then
				AchievementService.Check(player)
			end
		end)
		return
	end
	local profile = deps.DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local any = false
	for _, def in ipairs(ORDERED) do
		if def.Event == event and AchievementService.Grant(player, profile, def.Id, { Info = info }) then
			any = true
		end
	end
	if any then
		pushState(player)
	end
end

-- after a rebirth: the milestone achievements, and (AnnounceEveryRebirth) the big line for every rebirth
function AchievementService.OnRebirth(player: Player)
	if deps.DataService == nil or not live(player.UserId) then
		return
	end
	AchievementService.Check(player)
	local profile = deps.DataService.GetProfile(player)
	if profile == nil or AchievementConfig.AnnounceEveryRebirth ~= true then
		return
	end
	local p = AchievementService.StatValue(profile, "Prestige")
	if p >= 1 and rebirthShouted[player.UserId] ~= p then
		rebirthShouted[player.UserId] = p
		AchievementService.Shout(player, fill("just REBIRTHED for the {nth} time!", profile, nil), true)
	end
end

-- once per session: award any earned achievement's badge the player does not have yet (a failed award retries here)
local function syncBadges(player: Player)
	if badgeSynced[player] then
		return
	end
	badgeSynced[player] = true
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	if profile == nil or typeof(profile.Achievements) ~= "table" then
		return
	end
	for _, def in ipairs(ORDERED) do
		if profile.Achievements[def.Id] == true and (tonumber(def.BadgeId) or 0) > 0 then
			awardBadge(player, def)
			task.wait(AchievementConfig.Badges.SyncGapSeconds)
		end
	end
end

-- test hooks (tools/sim/run_achievement_test.py)
function AchievementService._SetClock(fn: () -> number)
	clock = fn
end
function AchievementService._Queue(): { Shout }
	return queue
end

function AchievementService.Init(d: { [string]: any })
	deps = d
	local remote = d.RemoteSetup and d.RemoteSetup.Get(Constants.RemoteNames.RequestAchievements)
	if remote and remote:IsA("RemoteEvent") then
		(remote :: RemoteEvent).OnServerEvent:Connect(function(player: Player)
			if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestAchievements") then
				return
			end
			if d.RateLimitService and not d.RateLimitService.Allow(player, "achievements", 1, 3) then
				return
			end
			if live(player.UserId) then
				AchievementService.Check(player)
				pushState(player)
			end
		end)
	end
	if d.SoldierService and d.SoldierService.OnArmyChanged then
		d.SoldierService.OnArmyChanged(function(player: Player)
			AchievementService.Check(player)
		end)
	end
	if d.DataService and d.DataService.OnProfileLoaded then
		d.DataService.OnProfileLoaded(function(player: Player)
			if not live(player.UserId) then
				return
			end
			task.delay(4, function()
				if player.Parent then
					AchievementService.Check(player)
					syncBadges(player)
				end
			end)
		end)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		checking[player] = nil
		badgeSynced[player] = nil
		rebirthShouted[player.UserId] = nil
	end)
	print("[WAR EMPIRE] AchievementService Init")
end

return AchievementService
