--!strict
--[[
	claude-bud JOB 13 (2026-09-29): events, leaderboards, invite / friends / comeback rewards (Shared/Configs/EngagementConfig).
	Server only. Every reward is paid here with EconomyService.AddCash and every DataStore call is pcall'd (a failure
	skips that write / read, never a player's session). Owner-only first through EngagementConfig.LiveFor per feature.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local EngagementConfig = require(Shared.Configs.EngagementConfig)

local EngagementService = {}

local E: any = EngagementConfig
local deps: { [string]: any } = {}
local friendsOf: { [number]: { [number]: boolean } } = {}
local nameCache: { [number]: string } = {}

local function live(feature: string, player: Player): boolean
	return EngagementConfig.LiveFor(feature, player.UserId)
end

local function notify(p: Player, msg: string, kind: string)
	local ns = deps.NotificationService
	if ns and ns.Notify then
		ns.Notify(p, msg, kind)
	end
end

local function pay(p: Player, amount: number, reason: string)
	local econ = deps.EconomyService
	if econ and econ.AddCash and amount > 0 then
		econ.AddCash(p, amount, reason)
	end
end

-- ── events ──
local function activeEvent(): any?
	local ev = EngagementConfig.EventAt(os.time())
	return ev
end

-- x on non-exempt cash (EconomyService.cashMultFor) while a CashMult event runs, for a player events are live for
function EngagementService.CashMult(player: Player): number
	if not live("Events", player) then
		return 1
	end
	local ev = activeEvent()
	return if ev and tonumber(ev.CashMult) then math.clamp(ev.CashMult, 1, 3) else 1
end

-- the airdrop interval while an Airdrop Frenzy runs (nil = the normal one); only while an events-live player is here
function EngagementService.AirdropInterval(): number?
	local ev = activeEvent()
	if ev == nil or tonumber(ev.AirdropIntervalSeconds) == nil then
		return nil
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if live("Events", p) then
			return math.max(60, ev.AirdropIntervalSeconds)
		end
	end
	return nil
end

function EngagementService.PlazaBountyMult(player: Player): number
	if not live("Events", player) then
		return 1
	end
	local ev = activeEvent()
	return if ev and tonumber(ev.PlazaBountyMult) then math.clamp(ev.PlazaBountyMult, 1, 3) else 1
end

-- ── leaderboards ──
local function scoresOf(profile: any): { [string]: number }
	local stats = if typeof(profile.Stats) == "table" then profile.Stats else {}
	return {
		Richest = math.max(0, math.floor(tonumber(profile.Cash) or 0)),
		Plaza = math.max(0, math.floor(tonumber(stats.PlazaCaptures) or 0)),
		Rebirths = math.max(0, math.floor(tonumber(profile.Prestige) or 0)),
	}
end

local function writeScores(player: Player)
	if not live("Leaderboards", player) then
		return
	end
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	if profile == nil then
		return
	end
	local s = scoresOf(profile)
	for _, b in ipairs(E.Boards) do
		local v = s[b.Id]
		if v then
			pcall(function()
				DataStoreService:GetOrderedDataStore(b.Store):SetAsync(tostring(player.UserId), v)
			end)
		end
	end
end

local function nameOf(uid: number): string
	local cached = nameCache[uid]
	if cached then
		return cached
	end
	local ok, got = pcall(function()
		return Players:GetNameFromUserIdAsync(uid)
	end)
	local name: string = if ok and typeof(got) == "string" then got else ("Player " .. tostring(uid))
	nameCache[uid] = name
	return name
end

local function readBoards()
	local folder = ReplicatedStorage:FindFirstChild("WE_Leaderboards")
	if folder == nil then
		local f = Instance.new("Folder")
		f.Name = "WE_Leaderboards"
		f.Parent = ReplicatedStorage
		folder = f
	end
	for _, b in ipairs(E.Boards) do
		local ok, pages = pcall(function()
			return DataStoreService:GetOrderedDataStore(b.Store):GetSortedAsync(false, E.TopN)
		end)
		if ok and pages then
			local rows = {}
			for _, entry in ipairs(pages:GetCurrentPage()) do
				local uid = tonumber(entry.key)
				if uid then
					table.insert(rows, { N = nameOf(uid), V = entry.value })
				end
			end
			local sv = (folder :: Instance):FindFirstChild(b.Id)
			if sv == nil then
				local v = Instance.new("StringValue")
				v.Name = b.Id
				v.Parent = folder
				sv = v
			end
			(sv :: StringValue).Value = HttpService:JSONEncode({ Title = b.Title, Rows = rows })
		end
	end
end

-- ── invite / friends / comeback ──
local function claimQueuedInvites(player: Player, profile: any)
	local ok, n = pcall(function()
		local got = 0
		DataStoreService:GetDataStore(E.InviteQueueStore):UpdateAsync("r_" .. player.UserId, function(old)
			got = math.max(0, math.floor(tonumber(old) or 0))
			return 0
		end)
		return got
	end)
	if ok and typeof(n) == "number" and n > 0 then
		EngagementService._PayInviter(player, profile, n)
	end
end

function EngagementService._PayInviter(inviter: Player, profile: any, count: number)
	local today = tonumber(os.date("!%Y%m%d")) or 0
	if tonumber(profile.InviteDay) ~= today then
		profile.InviteDay = today
		profile.InviteCount = 0
	end
	local room = math.max(0, E.InviteDailyCap - (tonumber(profile.InviteCount) or 0))
	local paid = math.min(room, count)
	if paid > 0 then
		profile.InviteCount = (tonumber(profile.InviteCount) or 0) + paid
		pay(inviter, E.InviteCash * paid, "invite_reward")
		deps.DataService.MarkDirty(inviter)
		notify(inviter, string.format("Friend joined! +$%d", E.InviteCash * paid), "Reward")
	end
end

local function onReferral(player: Player, profile: any)
	local ok, jd = pcall(function()
		return player:GetJoinData()
	end)
	local ref = if ok and typeof(jd) == "table" then tonumber((jd :: any).ReferredByPlayerId) else nil
	if ref == nil or ref <= 0 or ref == player.UserId or profile.ReferredBy ~= nil then
		return
	end
	if not EngagementConfig.LiveFor("Invite", ref) then
		return
	end
	profile.ReferredBy = ref -- once per account, ever
	pay(player, E.WelcomeCash, "invite_welcome")
	deps.DataService.MarkDirty(player)
	notify(player, string.format("Welcome! Your friend's invite: +$%d", E.WelcomeCash), "Reward")
	local inviter = Players:GetPlayerByUserId(ref)
	local iprof = inviter and deps.DataService.GetProfile(inviter)
	if inviter and iprof then
		EngagementService._PayInviter(inviter, iprof, 1)
	else
		pcall(function()
			DataStoreService:GetDataStore(E.InviteQueueStore):UpdateAsync("r_" .. ref, function(old)
				return math.min(1000, math.max(0, math.floor(tonumber(old) or 0)) + 1)
			end)
		end)
	end
end

local function onComeback(player: Player, profile: any)
	if not live("Comeback", player) then
		return
	end
	local prev = tonumber(profile.PrevJoinUnix)
	if prev == nil or prev <= 0 or os.time() - prev < E.ComebackDays * 86400 then
		return
	end
	pay(player, E.ComebackCash, "comeback")
	deps.DataService.MarkDirty(player)
	notify(player, string.format("Welcome back, Commander! +$%d", E.ComebackCash), "Reward")
end

local function learnFriends(player: Player)
	local mine = friendsOf[player.UserId] or {}
	friendsOf[player.UserId] = mine
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			task.spawn(function()
				local ok, yes = pcall(function()
					return player:IsFriendsWithAsync(other.UserId)
				end)
				if ok and yes then
					mine[other.UserId] = true
					local theirs = friendsOf[other.UserId] or {}
					friendsOf[other.UserId] = theirs
					theirs[player.UserId] = true
				end
			end)
		end
	end
end

function EngagementService.Init(d: { [string]: any })
	deps = d
	local DS = d.DataService
	if DS == nil then
		return
	end
	DS.OnProfileLoaded(function(player: Player, profile: any)
		task.defer(function()
			if player.Parent == nil then
				return
			end
			onComeback(player, profile)
			onReferral(player, profile)
			if live("Invite", player) then
				claimQueuedInvites(player, profile)
			end
			if live("Events", player) or live("Leaderboards", player) then
				player:SetAttribute("WE_Engagement", true) -- the client shows the event banner / the board
			end
			learnFriends(player)
		end)
	end)
	Players.PlayerRemoving:Connect(function(p)
		writeScores(p)
		friendsOf[p.UserId] = nil
		for _, set in pairs(friendsOf) do
			set[p.UserId] = nil
		end
	end)
	-- the friends bonus + leaderboard writes / reads, one slow loop (no per-frame work)
	task.spawn(function()
		local lastWrite, lastRead, lastFriends = 0, -math.huge, 0
		while true do
			task.wait(5)
			local now = os.clock()
			if now - lastFriends >= E.FriendsTickSeconds then
				lastFriends = now
				for _, p in ipairs(Players:GetPlayers()) do
					if live("Friends", p) then
						local n = 0
						for uid in pairs(friendsOf[p.UserId] or {}) do
							if Players:GetPlayerByUserId(uid) then
								n += 1
							end
						end
						n = math.min(n, E.FriendsCap)
						if n > 0 then
							pay(p, E.FriendsCashPerTick * n, "friends_bonus")
						end
					end
				end
			end
			if now - lastWrite >= E.WriteSeconds then
				lastWrite = now
				for _, p in ipairs(Players:GetPlayers()) do
					task.spawn(writeScores, p)
				end
			end
			if now - lastRead >= E.ReadSeconds and not RunService:IsStudio() then
				lastRead = now
				task.spawn(readBoards)
			end
		end
	end)
end

return EngagementService
