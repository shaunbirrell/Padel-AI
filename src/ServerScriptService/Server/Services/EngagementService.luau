--!strict
--[[
	claude-bud JOB 13 (2026-09-29): events, leaderboards, invite / friends / comeback rewards (Shared/Configs/EngagementConfig).
	claude-bud BOARDS: Town Centre notice boards (LeaderboardConfig) live for all.
	v104 (Code Bot, kept): friends daily cap (FriendsDay/FriendsPaid), comeback once-per-absence
	(ComebackPaidFor/ComebackPaidAt + persistent + saveNow), admin/playtest accounts off RICHEST writes.
	Server only. Every reward is paid here with EconomyService.AddCash and every DataStore call is pcall'd (a failure
	skips that write / read, never a player's session). Gated per feature by EngagementConfig.LiveFor.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local EngagementConfig = require(Shared.Configs.EngagementConfig)
local LeaderboardConfig = require(Shared.Configs.LeaderboardConfig) -- claude-bud BOARDS

local EngagementService = {}

local E: any = EngagementConfig
local deps: { [string]: any } = {}
local friendsOf: { [number]: { [number]: boolean } } = {}
local nameCache: { [number]: string } = {}

local function adminConfig(): any
	local ok, AC = pcall(require, Shared.Configs.AdminConfig)
	return if ok then AC else nil
end

-- v104: admin / playtest accounts (their Cash is a playtest floor) stay off the public boards
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

-- ── leaderboards: the Town Centre notice boards (claude-bud BOARDS, Shared/Configs/LeaderboardConfig; live for all) ──
local LB: any = LeaderboardConfig
local killLog: { [string]: { number } } = {}
local lastWriteAt: { [number]: number } = {}
local lastWritten: { [number]: { [string]: number? } } = {}
local backoff: { [string]: number } = { WriteUntil = 0, WriteStep = 0, ReadUntil = 0, ReadStep = 0 }
local crowned: { [number]: string } = {} -- userId -> the weekly board(s) he leads

local function lbOf(profile: any): any
	local lb = profile.LB
	if typeof(lb) ~= "table" then
		lb = {}
		profile.LB = lb
	end
	return lb
end

-- the week rolled over: weekly kills restart, weekly plaza captures count from here
local function rollWeek(profile: any, now: number)
	local lb = lbOf(profile)
	local week = LeaderboardConfig.IsoWeek(now)
	if lb.Week ~= week then
		lb.Week = week
		lb.KillsW = 0
		lb.ArmyKillsW = 0 -- claude-bud JOB 38: ARMY KILLS this week
		lb.PlazaBase = math.floor(tonumber(profile.Stats and profile.Stats.PlazaCaptures) or 0)
	end
	if lb.Seeded ~= true then
		lb.Seeded = true -- the all-time kill board starts from the kills already on the profile (PvP kills)
		lb.Kills = math.max(math.floor(tonumber(lb.Kills) or 0), math.floor(tonumber(profile.Stats and profile.Stats.Kills) or 0))
	end
end

-- key ("Kills" / "Kills_W" / ...) -> this player's value right now (nil = not on that board)
local function valuesOf(player: Player, profile: any): { [string]: number }
	local lb = lbOf(profile)
	local stats = if typeof(profile.Stats) == "table" then profile.Stats else {}
	local army = math.floor(tonumber(profile.Soldiers) or 0)
	if army > (tonumber(lb.ArmyMax) or 0) then
		lb.ArmyMax = army
	end
	local out: { [string]: number } = {
		Kills = math.floor(tonumber(lb.Kills) or 0),
		Kills_W = math.floor(tonumber(lb.KillsW) or 0),
		Richest = math.max(0, math.floor(tonumber(profile.Cash) or 0)),
		Plaza_W = math.max(0, math.floor(tonumber(stats.PlazaCaptures) or 0) - math.floor(tonumber(lb.PlazaBase) or 0)),
		Rebirths = math.max(0, math.floor(tonumber(profile.Prestige) or 0)),
		Army = math.floor(tonumber(lb.ArmyMax) or 0),
		ArmyKills = math.floor(tonumber(lb.ArmyKills) or 0), -- claude-bud JOB 38 (the board shows once live for everyone)
		ArmyKills_W = math.floor(tonumber(lb.ArmyKillsW) or 0),
	}
	-- Supporters: confirmed Robux only (profile.Monetization.RobuxSpent), never 0, never for an opted-out player
	local settings = if typeof(profile.Settings) == "table" then profile.Settings else {}
	local spent = math.floor(tonumber(typeof(profile.Monetization) == "table" and profile.Monetization.RobuxSpent) or 0)
	if spent > 0 and settings.SupporterBoardOptOut ~= true then
		out.Supporters = spent
	end
	return out
end

local function budgetOk(kind: Enum.DataStoreRequestType): boolean
	local ok, n = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(kind)
	end)
	return not ok or (tonumber(n) or 0) >= LB.MinBudget
end

local function fail(which: string)
	local step = math.clamp((backoff[which .. "Step"] or 0) * 2, LB.BackoffSeconds, LB.BackoffMax)
	backoff[which .. "Step"] = step
	backoff[which .. "Until"] = os.clock() + step
end

local function storeFor(key: string, now: number): OrderedDataStore
	local weekly = string.sub(key, -2) == "_W"
	local id = if weekly then string.sub(key, 1, -3) else key
	return DataStoreService:GetOrderedDataStore(LeaderboardConfig.StoreName(id, weekly, now))
end

-- write this player's changed values (force = on leave: ignore the per-player throttle)
local function writeScores(player: Player, force: boolean?)
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	if profile == nil then
		return
	end
	if isBoardExcluded(player.UserId) then
		return -- v104: admin / playtest cash floor never written to RICHEST
	end
	local now = os.clock()
	if not force and not LeaderboardConfig.WriteDue(lastWriteAt[player.UserId], now) then
		return
	end
	if now < backoff.WriteUntil then
		return
	end
	lastWriteAt[player.UserId] = now
	local unix = os.time()
	rollWeek(profile, unix)
	local vals = valuesOf(player, profile)
	local prev = lastWritten[player.UserId] or {}
	lastWritten[player.UserId] = prev
	for key, v in pairs(vals) do
		player:SetAttribute("WE_LBVal_" .. key, v) -- the "You:" line
		if v > 0 and prev[key] ~= v and budgetOk(Enum.DataStoreRequestType.SetIncrementSortedAsync) then
			local ok = pcall(function()
				storeFor(key, unix):SetAsync(tostring(player.UserId), v)
			end)
			if ok then
				prev[key] = v
			else
				fail("Write")
				return
			end
		end
	end
	backoff.WriteStep = 0
end

local function nameOf(uid: number): string
	local cached = nameCache[uid]
	if cached then
		return cached
	end
	local p = Players:GetPlayerByUserId(uid)
	if p then
		nameCache[uid] = p.DisplayName
		return p.DisplayName
	end
	local ok, got = pcall(function()
		return Players:GetNameFromUserIdAsync(uid)
	end)
	local name: string = if ok and typeof(got) == "string" then got else ("Player " .. tostring(uid))
	nameCache[uid] = name
	return name
end

local function setCrown(p: Player, label: string?)
	local char = p.Character
	local head = char and char:FindFirstChild("Head")
	local old = head and head:FindFirstChild("WE_Crown")
	if label == nil then
		if old then
			old:Destroy()
		end
		return
	end
	if head == nil then
		return
	end
	-- claude-bud JOB 24 §11: what the crown is for, under it ("#1 MOST KILLS this week"); rebuilt when the board changes
	local sub = "#1 " .. string.upper(label) .. " this week"
	if old ~= nil then
		local l = old:FindFirstChild("WE_CrownLabel")
		if l and l:IsA("TextLabel") and l.Text == sub then
			return
		end
		old:Destroy()
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "WE_Crown"
	bb.Size = UDim2.fromScale(5, 3.4)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.MaxDistance = LB.CrownMaxDistance
	bb.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 0.68)
	t.BackgroundTransparency = 1
	t.TextScaled = true
	t.Font = Enum.Font.GothamBlack
	t.TextColor3 = Color3.fromRGB(255, 205, 60)
	t.Text = "👑"
	t.Parent = bb
	local l = Instance.new("TextLabel")
	l.Name = "WE_CrownLabel"
	l.Position = UDim2.fromScale(0, 0.7)
	l.Size = UDim2.fromScale(1, 0.3)
	l.BackgroundColor3 = Color3.fromRGB(20, 22, 18)
	l.BackgroundTransparency = 0.25
	l.TextScaled = true
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = Color3.fromRGB(255, 215, 110)
	l.Text = sub
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.3, 0)
	c.Parent = l
	l.Parent = bb
	bb.Parent = head
end

-- claude-bud JOB 24 §11: a one-time note to the player who takes a weekly #1 (once per board per week, saved in his
-- profile so another server does not repeat it). Owner / admin are never on the boards, so never crowned.
local function crownNote(p: Player, label: string, unix: number)
	local profile = deps.DataService and deps.DataService.GetProfile(p)
	if profile == nil then
		return
	end
	local week = os.date("!%Y-%W", unix)
	local key = week .. ":" .. label
	local seen = (profile :: any).CrownNotes
	if typeof(seen) ~= "table" or seen.Week ~= week then
		seen = { Week = week }
		;(profile :: any).CrownNotes = seen
	end
	if seen[key] then
		return
	end
	seen[key] = true
	pcall(deps.DataService.MarkDirty, p)
	local ns = deps.NotificationService
	if ns and ns.Notify then
		pcall(ns.Notify, p, "You're #1 on " .. label .. " this week! Keep it to keep your crown.", "Reward")
	end
	local ach = deps.AchievementService -- claude-bud JOB 34: the weekly #1 achievement (+ its chat line)
	if ach and ach.Note then
		pcall(ach.Note, p, "Crown", { Label = label })
	end
end

-- ONE server-wide fetch per board, published for every client; ranks for the players in this server
local function readBoards()
	if os.clock() < backoff.ReadUntil then
		return
	end
	local folder = ReplicatedStorage:FindFirstChild("WE_Leaderboards")
	if folder == nil then
		local f = Instance.new("Folder")
		f.Name = "WE_Leaderboards"
		f.Parent = ReplicatedStorage
		folder = f
	end
	local unix = os.time()
	local leaders: { [number]: string } = {}
	for _, b in ipairs(LB.Boards) do
		local keys = {}
		if b.AllTime then
			table.insert(keys, b.Id)
		end
		if b.Weekly then
			table.insert(keys, b.Id .. "_W")
		end
		for _, key in ipairs(keys) do
			if not budgetOk(Enum.DataStoreRequestType.GetSortedAsync) then
				return
			end
			local ok, page = pcall(function()
				return storeFor(key, unix):GetSortedAsync(false, LB.FetchN):GetCurrentPage()
			end)
			if not ok or typeof(page) ~= "table" then
				fail("Read")
				return
			end
			local rows = {}
			local rankOf: { [number]: number } = {}
			local shown = 0
			for i, entry in ipairs(page) do
				local uid = tonumber(entry.key)
				if uid and not isBoardExcluded(uid) then
					rankOf[uid] = i
					if shown < LB.TopN then
						shown += 1
						table.insert(rows, { U = uid, N = nameOf(uid), V = entry.value })
					end
				end
			end
			if string.sub(key, -2) == "_W" and rows[1] then
				local u = rows[1].U
				leaders[u] = if leaders[u] then leaders[u] .. " + " .. b.Title else b.Title
			end
			for _, p in ipairs(Players:GetPlayers()) do
				p:SetAttribute("WE_LBRank_" .. key, rankOf[p.UserId] or 0)
			end
			local sv = (folder :: Instance):FindFirstChild(key)
			if sv == nil then
				local v = Instance.new("StringValue")
				v.Name = key
				v.Parent = folder
				sv = v
			end
			(sv :: StringValue).Value = HttpService:JSONEncode({ Title = b.Title, Unit = b.Unit, Money = b.Money == true, Weekly = string.sub(key, -2) == "_W", Rows = rows, At = unix })
		end
	end
	backoff.ReadStep = 0
	-- the weekly #1 of each weekly board wears the crown while in game
	crowned = leaders
	for _, p in ipairs(Players:GetPlayers()) do
		pcall(setCrown, p, crowned[p.UserId])
		if crowned[p.UserId] then
			pcall(crownNote, p, crowned[p.UserId], unix)
		end
	end
end

-- a real PvP kill (the server's creator tag): counts for the kill boards unless self / clan mate / farmed
local killCounted = false -- claude-bud JOB 38: the last onKill passed the kill rules (the ARMY KILLS credit reuses them)
local function onKill(victim: Player, killer: Player?)
	killCounted = false
	if killer == nil or killer == victim or killer.Parent == nil then
		return
	end
	local cs = deps.CombatService
	local allied = cs ~= nil and cs.IsClanAlly ~= nil and cs.IsClanAlly(killer, victim) == true
	if not LeaderboardConfig.AllowKill(killLog, killer.UserId, victim.UserId, allied, os.clock()) then
		return
	end
	local profile = deps.DataService and deps.DataService.GetProfile(killer)
	if profile == nil then
		return
	end
	rollWeek(profile, os.time())
	local lb = lbOf(profile)
	lb.Kills = (tonumber(lb.Kills) or 0) + 1
	lb.KillsW = (tonumber(lb.KillsW) or 0) + 1
	deps.DataService.MarkDirty(killer)
	killCounted = true
end

--[[ claude-bud JOB 38 ADDENDUM: ARMY KILLS. One kill made by this player's army units: an enemy player killed by army fire
	(after the same kill rules as MOST KILLS: no self, clan mate or farmed pair), a checkpoint / bank guard
	(ArmyOrdersConfig.ArmyKillNpcTypes, CombatService ByUnit), a base / tower guard (GateDefenseService, weapon "Squad").
	Protected targets cannot be hit at all (the shared rule), so they never count. Admin / owner stay off the board. ]]
function EngagementService.NoteArmyKill(killer: Player)
	if typeof(killer) ~= "Instance" or not killer:IsA("Player") or killer.Parent == nil then
		return
	end
	-- Code Bot v156: the board's own switch (it was ArmyOrdersConfig.LiveFor: only the owner, who is off every board)
	if LeaderboardConfig.ArmyKillsBoardLive ~= true then
		return
	end
	local profile = deps.DataService and deps.DataService.GetProfile(killer)
	if profile == nil then
		return
	end
	rollWeek(profile, os.time())
	local lb = lbOf(profile)
	lb.ArmyKills = (tonumber(lb.ArmyKills) or 0) + 1
	lb.ArmyKillsW = (tonumber(lb.ArmyKillsW) or 0) + 1
	deps.DataService.MarkDirty(killer)
end

-- claude-bud JOB 24 §6: an outpost / area DEFENDER killed by this player (or his army) counts on MOST KILLS too.
-- Defenders respawn on a timer (OutpostDefenderConfig.RespawnSeconds) and only exist near players, so this cannot be
-- farmed faster than the defenders come back. Owner / admin boards stay excluded when the board is written.
function EngagementService.NoteDefenderKill(killer: Player)
	if typeof(killer) ~= "Instance" or not killer:IsA("Player") or killer.Parent == nil then
		return
	end
	local profile = deps.DataService and deps.DataService.GetProfile(killer)
	if profile == nil then
		return
	end
	rollWeek(profile, os.time())
	local lb = lbOf(profile)
	lb.Kills = (tonumber(lb.Kills) or 0) + 1
	lb.KillsW = (tonumber(lb.KillsW) or 0) + 1
	deps.DataService.MarkDirty(killer)
end

-- Settings "Supporter board": hide / show this player on TOP SUPPORTERS (hiding removes the stored entry)
local function onBoardSetting(player: Player, hide: any)
	if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestBoardSetting", hide) then -- claude-bud JOB 15
		return
	end
	local rl = deps.RateLimitService
	if rl and not rl.Allow(player, "board_setting", 1, 3) then
		return
	end
	if typeof(hide) ~= "boolean" then
		return
	end
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	if profile == nil then
		return
	end
	if typeof(profile.Settings) ~= "table" then
		profile.Settings = {}
	end
	profile.Settings.SupporterBoardOptOut = hide
	deps.DataService.MarkDirty(player)
	player:SetAttribute("WE_SupporterOptOut", hide)
	local prev = lastWritten[player.UserId]
	if prev then
		prev.Supporters = nil -- showing again rewrites it on the next write
	end
	if hide then
		task.spawn(function()
			pcall(function()
				storeFor("Supporters", os.time()):RemoveAsync(tostring(player.UserId))
			end)
		end)
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

-- claude-bud JOB 20: are these two players Roblox friends (learned at join; false when unknown)
function EngagementService.AreFriends(a: number, b: number): boolean
	local set = friendsOf[a]
	return set ~= nil and set[b] == true
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
			-- claude-bud BOARDS: the Settings toggle's state; the crown comes back with every character
			local st = if typeof(profile.Settings) == "table" then profile.Settings else {}
			player:SetAttribute("WE_SupporterOptOut", st.SupporterBoardOptOut == true)
			pcall(rollWeek, profile, os.time())
			player.CharacterAdded:Connect(function()
				task.wait(1)
				pcall(setCrown, player, crowned[player.UserId])
			end)
		end)
	end)
	-- claude-bud BOARDS: real PvP kills (CombatService's creator tag), the supporter opt-out toggle
	if d.CombatService and d.CombatService.OnPlayerDeath then
		d.CombatService.OnPlayerDeath(function(victim: Player, killer: Player?, _info: any)
			onKill(victim, killer)
			if killCounted and killer and typeof(_info) == "table" and _info.WeaponId == "Squad" then
				EngagementService.NoteArmyKill(killer) -- claude-bud JOB 38: killed by his army's fire
			end
		end)
	end
	if d.CombatService and d.CombatService.OnNPCDeath then
		d.CombatService.OnNPCDeath(function(info: any) -- claude-bud JOB 38: army kills of checkpoint / bank guards
			local AOC: any = require(Shared.Configs.ArmyOrdersConfig)
			if typeof(info) == "table" and info.ByUnit == true and info.Killer and AOC.ArmyKillNpcTypes[info.TypeId] == true then
				EngagementService.NoteArmyKill(info.Killer)
			end
		end)
	end
	local okR, Remotes = pcall(require, Shared.Remotes)
	local Constants = require(Shared.Constants)
	local ev = okR and (Remotes :: any).TryGetEvent(Constants.RemoteNames.RequestBoardSetting)
	if ev then
		ev.OnServerEvent:Connect(onBoardSetting)
	end
	Players.PlayerRemoving:Connect(function(p)
		-- v107: flush on leave but still respect WriteDue (leave/rejoin spam cannot flood stores)
		writeScores(p, false)
		friendsOf[p.UserId] = nil
		for _, set in pairs(friendsOf) do
			set[p.UserId] = nil
		end
	end)
	-- the friends bonus + leaderboard writes / reads, one slow loop (no per-frame work)
	task.spawn(function()
		local lastRead, lastFriends = -math.huge, 0
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
			-- claude-bud BOARDS: each player's writes are throttled inside writeScores (WriteMinSeconds)
			for _, p in ipairs(Players:GetPlayers()) do
				task.spawn(writeScores, p, false)
			end
			if now - lastRead >= LeaderboardConfig.ReadSeconds then
				lastRead = now
				task.spawn(readBoards)
			end
		end
	end)
end

return EngagementService
