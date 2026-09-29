--!strict
--[[
	claude-bud JOB 13 (2026-09-29): events, leaderboards, invite / friends / comeback rewards (Shared/Configs/EngagementConfig).
	Server only. Every reward is paid here with EconomyService.AddCash and every DataStore call is pcall'd (a failure
	skips that write / read, never a player's session). Gated per feature by EngagementConfig.LiveFor ("all" since v104).
	v104 (Code Bot) exploit guards for the all-players rollout:
	  * invite: only a saved profile (DataService.IsLoaded), a brand-new account (InviteNewPlayerSeconds since FirstJoinUnix)
	    that is a real Roblox friend of the inviter (IsFriendsWithAsync, a failed check pays nothing); ReferredBy is saved
	    right away; the inviter stays capped at InviteDailyCap a day.
	  * friends: at most FriendsCap friends per tick and FriendsDailyCap a day (profile.FriendsDay / FriendsPaid, saved).
	  * leaderboards: one write per player per WriteMinGapSeconds (kept across leave / rejoin in this server), unchanged
	    scores are not rewritten, a write waits while the server's sorted-store budget is low; admin accounts
	    (AdminConfig.UserIds / the playtest owner, whose Cash is a playtest floor) never appear on a board.
	  * comeback: once per absence (profile.ComebackPaidFor), only on a saved profile, saved right away.
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
local lastBoardWrite: { [number]: number } = {} -- v104: os.clock() of each user's last board write (survives leave / rejoin)
local lastBoardScores: { [number]: { [string]: number } } = {} -- v104: what was last written per user and board

local function adminConfig(): any
	local ok, AC = pcall(require, Shared.Configs.AdminConfig)
	return if ok then AC else nil
end

-- v104: admin / playtest accounts (their Cash is a playtest floor) are kept off the public boards
local function isBoardExcluded(uid: number): boolean
	local AC = adminConfig()
	if AC == nil then
		return false
	end
	if AC.IsPlaytestOwner and AC.IsPlaytestOwner(uid) then
		return true
	end
	for _, id in ipairs(AC.UserIds or {}) do
		if tonumber(id) == uid then
			return true
		end
	end
	return false
end

-- v104: a reward that must stick is only paid on a profile that will be saved (a session-only profile would pay again)
local function persistent(player: Player): boolean
	local DS = deps.DataService
	return DS ~= nil and DS.IsLoaded ~= nil and DS.IsLoaded(player) == true
end

local function saveNow(player: Player)
	local DS = deps.DataService
	if DS and DS.MarkDirty then
		DS.MarkDirty(player)
	end
	if DS and DS.SaveProfile then
		task.spawn(function()
			pcall(DS.SaveProfile, player)
		end)
	end
end

local function utcDay(): number
	return tonumber(os.date("!%Y%m%d")) or 0
end

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

local function writeBudgetOk(): boolean
	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.SetIncrementSortedAsync)
	end)
	if not ok or typeof(budget) ~= "number" then
		return true -- no budget API (tests): the per-player gap still throttles
	end
	return budget >= (tonumber(E.WriteBudgetFloor) or 0)
end

local function writeScores(player: Player)
	if not live("Leaderboards", player) then
		return
	end
	local uid = player.UserId
	if isBoardExcluded(uid) then
		return
	end
	local now = os.clock()
	local last = lastBoardWrite[uid]
	if last ~= nil and now - last < (tonumber(E.WriteMinGapSeconds) or 60) then
		return -- v104: throttled (one write per player per WriteMinGapSeconds)
	end
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	if profile == nil or not persistent(player) then
		return
	end
	lastBoardWrite[uid] = now
	local s = scoresOf(profile)
	local prev = lastBoardScores[uid] or {}
	lastBoardScores[uid] = prev
	for _, b in ipairs(E.Boards) do
		local v = s[b.Id]
		if v and prev[b.Id] ~= v and writeBudgetOk() then
			local okW = pcall(function()
				DataStoreService:GetOrderedDataStore(b.Store):SetAsync(tostring(player.UserId), v)
			end)
			if okW then
				prev[b.Id] = v
			end
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
			return DataStoreService:GetOrderedDataStore(b.Store):GetSortedAsync(false, math.min(100, E.TopN + 5))
		end)
		if ok and pages then
			local rows = {}
			for _, entry in ipairs(pages:GetCurrentPage()) do
				local uid = tonumber(entry.key)
				if uid and not isBoardExcluded(uid) and #rows < E.TopN then -- v104: admin / playtest scores never shown
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
	local today = utcDay()
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
	ref = math.floor(ref)
	if not EngagementConfig.LiveFor("Invite", ref) then
		return
	end
	-- v104: a saved profile only (a session-only default would pay the inviter again on every failed load)
	if not persistent(player) then
		return
	end
	-- v104: a brand-new account only (an old account joining through a link is not a new friend)
	local first = tonumber(profile.FirstJoinUnix) or 0
	if first <= 0 or os.time() - first > (tonumber(E.InviteNewPlayerSeconds) or 900) then
		return
	end
	-- v104: the inviter must really be this account's Roblox friend (a failed / errored check pays nothing)
	local okF, isFriend = pcall(function()
		return player:IsFriendsWithAsync(ref)
	end)
	if not okF or isFriend ~= true or player.Parent == nil or profile.ReferredBy ~= nil then
		return
	end
	profile.ReferredBy = ref -- once per account, ever
	pay(player, E.WelcomeCash, "invite_welcome")
	saveNow(player) -- v104: ReferredBy is on disk before the inviter is paid
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
	-- v104: once per absence (the previous join it paid for is kept) and only on a profile that will be saved
	if not persistent(player) or tonumber(profile.ComebackPaidFor) == prev then
		return
	end
	local lastPaid = tonumber(profile.ComebackPaidAt) or 0
	if lastPaid > 0 and os.time() - lastPaid < E.ComebackDays * 86400 then
		return
	end
	profile.ComebackPaidFor = prev
	profile.ComebackPaidAt = os.time()
	pay(player, E.ComebackCash, "comeback")
	saveNow(player)
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
			if live("Invite", player) and persistent(player) then
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
						local prof = if n > 0 and deps.DataService then deps.DataService.GetProfile(p) else nil
						if prof then
							-- v104: at most FriendsDailyCap a day (UTC), counted in the saved profile
							local today = utcDay()
							if tonumber(prof.FriendsDay) ~= today then
								prof.FriendsDay = today
								prof.FriendsPaid = 0
							end
							local room = math.max(0, (tonumber(E.FriendsDailyCap) or 0) - (tonumber(prof.FriendsPaid) or 0))
							local amount = math.min(room, E.FriendsCashPerTick * n)
							if amount > 0 then
								prof.FriendsPaid = (tonumber(prof.FriendsPaid) or 0) + amount
								pay(p, amount, "friends_bonus")
								deps.DataService.MarkDirty(p)
							end
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
