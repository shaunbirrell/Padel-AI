--!strict
--[[
	claude-bud BOARDS (2026-09-29): the Town Centre notice boards. Extends the JOB 13 leaderboard (server:
	EngagementService, client: EngagementClient; data: ReplicatedStorage.WE_Leaderboards). Live for all players.
	  * One OrderedDataStore per stat: StorePrefix .. Id (all-time) and StorePrefix .. Id .. "_W" .. IsoWeek(now)
	    (weekly: a fresh store every ISO week, UTC).
	  * Writes: per player at most once per WriteMinSeconds (only values that changed; never a 0), plus once on leave.
	    Reads: ONE server-wide fetch of the top FetchN per board every ReadSeconds, published for every client. Every
	    DataStore call is pcall'd; after a failure that kind of call backs off (BackoffSeconds doubling to BackoffMax).
	  * Kills: real player-vs-player kills only (the server's creator tag via CombatService.OnPlayerDeath), never self or
	    a clan mate, and one killer -> victim pair counts at most KillPairMax times per KillPairWindowSeconds.
	  * Code Bot v175: Supporters has an ALL-TIME and a THIS WEEK tab (WE_LB2_Supporters / WE_LB2_Supporters_W<week>):
	    this week = Monetization.RobuxSpent - profile.LB.SupWBase (the total at the week's start). Every dev product
	    (ProcessReceipt CurrencySpent) and confirmed pass purchase moves both; a never-counted pass credited on join
	    counts all-time only. Written at once on every saved purchase, on join and on leave ("[SUPPORTERS]" log lines).
	  * Supporters: Robux spent in game (profile.Monetization.RobuxSpent: dev products from ProcessReceipt's
	    CurrencySpent, saved before the ack; game passes at the real price once UserOwnsGamePassAsync confirms). A player
	    who spent nothing is never written; Settings "Supporter board" (profile.Settings.SupporterBoardOptOut) removes
	    the player from it.
	  * A player standing within YouRowStuds of a board sees his own line ("You: #12 · 56 kills"; rank known inside the
	    top FetchN, else "#100+"). The weekly #1 of each weekly board wears a gold crown while in game.
]]

export type Board = {
	Id: string,
	Title: string,
	Unit: string,
	AllTime: boolean,
	Weekly: boolean,
	Money: boolean?,
	OptOut: boolean?,
}

local LeaderboardConfig = {
	Boards = {
		{ Id = "Kills", Title = "MOST KILLS", Unit = "kills", AllTime = true, Weekly = true },
		{ Id = "Richest", Title = "RICHEST", Unit = "", AllTime = true, Weekly = false, Money = true },
		{ Id = "Supporters", Title = "TOP SUPPORTERS", Unit = "Robux", AllTime = true, Weekly = true, OptOut = true }, -- Code Bot v175: + THIS WEEK
		{ Id = "Plaza", Title = "PLAZA CONQUEROR", Unit = "captures", AllTime = false, Weekly = true },
		{ Id = "Rebirths", Title = "REBIRTH KINGS", Unit = "rebirths", AllTime = true, Weekly = false },
		{ Id = "Army", Title = "TOP ARMY", Unit = "soldiers", AllTime = true, Weekly = false },
	} :: { Board },

	StorePrefix = "WE_LB2_",
	WriteMinSeconds = 90, -- per player (the owner's rule: 60-120 s), plus on leave
	ReadSeconds = 90, -- one shared fetch per board (the owner's rule: 60-90 s). Code Bot v175: 90 (was 75): 10 keys / 90 s = 6.7 / min, inside a 1-player server's 5 + 2 x 1 = 7 GetSortedAsync / min
	TopN = 10, -- rows on a board
	FetchN = 100, -- rows fetched (one page) so a player's own rank is known inside the top 100
	BackoffSeconds = 30,
	BackoffMax = 600,
	MinBudget = 5, -- skip a write / read when the DataStore request budget is below this

	KillPairMax = 3, -- the same killer -> victim pair counts at most this many kills ...
	KillPairWindowSeconds = 600, -- ... per 10 minutes

	-- the row in the Town Centre square (90 x 90 at (-150, 150)): along its south edge, facing the fountain (north)
	Row = {
		FirstX = -187.5,
		StepX = 15,
		Z = 190,
		FaceDirZ = -1, -- the boards' fronts face -Z (the square's centre)
	},
	BoardSize = Vector3.new(14, 22, 1), -- 1.5-stud rows: readable on a phone from ~30 studs
	PixelsPerStud = 25,
	MaxDistance = 80, -- SurfaceGui cap (CLAUDE.md budget)
	YouRowStuds = 40,
	TabSeconds = 8, -- a board with both tabs alternates ALL-TIME / THIS WEEK
	NightCheckSeconds = 10,
	CrownMaxDistance = 40,
}

-- "2026W40": the ISO-8601 week (Monday start; week 1 holds the year's first Thursday) of a UTC time. Pure.
function LeaderboardConfig.IsoWeek(t: number): string
	local day = math.floor(t / 86400)
	local wd = (day + 3) % 7 -- 0 = Monday (1970-01-01 was a Thursday)
	local thursday = day - wd + 3
	local d = os.date("!*t", thursday * 86400) :: any
	local week = math.floor((d.yday - 1) / 7) + 1
	return string.format("%04dW%02d", d.year, week)
end

function LeaderboardConfig.StoreName(id: string, weekly: boolean, now: number): string
	if weekly then
		return LeaderboardConfig.StorePrefix .. id .. "_W" .. LeaderboardConfig.IsoWeek(now)
	end
	return LeaderboardConfig.StorePrefix .. id
end

-- may this player write again? (the per-player throttle). Pure.
function LeaderboardConfig.WriteDue(lastAt: number?, now: number): boolean
	return lastAt == nil or now - lastAt >= LeaderboardConfig.WriteMinSeconds
end

--[[ Does this kill count for the board? log = the server's pair log ("killer:victim" -> recent times, pruned here).
	Never self, never a clan mate (allied), at most KillPairMax per KillPairWindowSeconds per pair. Pure. ]]
function LeaderboardConfig.AllowKill(log: { [string]: { number } }, killerId: number, victimId: number, allied: boolean, now: number): boolean
	if killerId == victimId or killerId <= 0 or victimId <= 0 or allied then
		return false
	end
	local key = tostring(killerId) .. ":" .. tostring(victimId)
	local list = log[key] or {}
	local kept: { number } = {}
	for _, at in ipairs(list) do
		if now - at < LeaderboardConfig.KillPairWindowSeconds then
			table.insert(kept, at)
		end
	end
	if #kept >= LeaderboardConfig.KillPairMax then
		log[key] = kept
		return false
	end
	table.insert(kept, now)
	log[key] = kept
	return true
end

-- claude-bud JOB 38 ADDENDUM (owner 2026-09-30): ARMY KILLS replaces TOP ARMY in the same slot (army size is capped, so
-- TOP ARMY is a tie). Its own store keys ("WE_LB2_ArmyKills", weekly "_W<week>").
-- Code Bot v156 (Shaun 2026-10-01: the live plaza still showed TOP ARMY, everyone tied at 75). Root cause: the swap
-- below waited for ArmyOrdersConfig.LiveForAll(), which was false while army orders stayed owner-first (v166 flipped them live for all), AND
-- EngagementService.NoteArmyKill only counted kills for players army orders were live for (the owner, who is excluded
-- from every board), so nobody could ever score. The board is only a leaderboard: it now has its own switch,
-- ArmyKillsBoardLive (true = ARMY KILLS for everyone, whatever the army orders rollout; false = TOP ARMY exactly as
-- before). Kills count from the army's normal fire too (FOLLOW / HOLD / DEFEND escort shots, not only ATTACK / SEND).
-- Admin / owner accounts stay off every board (EngagementService.isBoardExcluded, at write and at read).
LeaderboardConfig.ArmyKillsBoard = { Id = "ArmyKills", Title = "ARMY KILLS", Unit = "kills", AllTime = true, Weekly = true } :: Board
LeaderboardConfig.ArmyKillsBoardLive = true
if LeaderboardConfig.ArmyKillsBoardLive == true then
	for i, b in ipairs(LeaderboardConfig.Boards) do
		if b.Id == "Army" then
			LeaderboardConfig.Boards[i] = LeaderboardConfig.ArmyKillsBoard
		end
	end
end
return LeaderboardConfig
