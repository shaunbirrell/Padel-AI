--!strict
--[[
	claude-bud JOB 13 (2026-09-29): bring players back (Server/Services/EngagementService + Client/Modules/EngagementClient).
	v103 shipped owner-only; v104 (Code Bot) sets every Rollout to "all". Every reward is decided and paid on the server.
	  * Events: a weekly rotation from the Events table. Week n (UTC, weeks since Epoch Monday) runs Events[n % #Events];
	    Window "Weekend" = Friday 00:00 to Monday 00:00 UTC, "Week" = the whole week. Effects: CashMult (passive / pay
	    reasons, on top of everything), AirdropIntervalSeconds (the airdrop comes faster), PlazaBountyMult. A HUD banner
	    shows the running event and its countdown (or the next one and when it starts).
	  * Leaderboards: OrderedDataStores (Boards). Scores are written every WriteSeconds per player and on leave, top TopN
	    read every ReadSeconds, published to ReplicatedStorage.WE_Leaderboards (JSON). A board stands at Town Square
	    (client-built, only shown to players it is live for).
	  * Invite: the Shop's "Invite friends" row opens Roblox's invite prompt (SocialService). A new player who joins through
	    an invite (JoinData.ReferredByPlayerId) gets WelcomeCash once; the inviter gets InviteCash per new friend (at most
	    InviteDailyCap a day), right away when in the same server or on his next join (DataStore queue). v104: only for a
	    brand-new account (InviteNewPlayerSeconds) that is a real Roblox friend of the inviter, on a saved profile.
	  * Friends: every FriendsTickSeconds, FriendsCashPerTick per friend in the server (at most FriendsCap friends, at most
	    FriendsDailyCap a day).
	  * Comeback: away ComebackDays or more (since the last join) -> ComebackCash once per absence on the join.
	  v104: the reward reasons (invite_welcome / invite_reward / friends_bonus / comeback) are multiplier-exempt, so the
	  amounts and caps here are exactly what is paid.
]]

local EngagementConfig = {
	-- v104 (Code Bot, owner 2026-09-29: "switch ALL of JOB 13 on for all players"): every feature live for everyone
	Rollout = {
		Events = "all",
		Leaderboards = "all",
		Invite = "all",
		Friends = "all",
		Comeback = "all",
	} :: { [string]: string },

	Events = {
		{ Id = "DoubleCashWeekend", Name = "DOUBLE CASH WEEKEND", Window = "Weekend", CashMult = 2 },
		{ Id = "PlazaWarWeek", Name = "PLAZA WAR WEEK", Window = "Week", PlazaBountyMult = 2 },
		{ Id = "AirdropFrenzy", Name = "AIRDROP FRENZY", Window = "Weekend", AirdropIntervalSeconds = 180 },
	} :: { { Id: string, Name: string, Window: string, CashMult: number?, PlazaBountyMult: number?, AirdropIntervalSeconds: number? } },

	Boards = {
		{ Id = "Richest", Title = "RICHEST", Store = "WE_LB_Cash_v1" },
		{ Id = "Plaza", Title = "PLAZA CAPTURES", Store = "WE_LB_Plaza_v1" },
		{ Id = "Rebirths", Title = "REBIRTHS", Store = "WE_LB_Rebirths_v1" },
	} :: { { Id: string, Title: string, Store: string } },
	WriteSeconds = 300,
	ReadSeconds = 300,
	TopN = 10,
	WriteMinGapSeconds = 60, -- v104: at most one board write per player per minute (leave / rejoin spam cannot flood the budget)
	WriteBudgetFloor = 20, -- v104: skip a write while this server's sorted-store write budget is below this
	BoardX = -112, -- Town Square's north-east corner (the square is 90 x 90 at (-150, 150)), facing the square
	BoardZ = 112,

	WelcomeCash = 2500,
	InviteCash = 10000,
	InviteDailyCap = 5,
	InviteQueueStore = "WE_InviteRewards_v1",
	InviteNewPlayerSeconds = 900, -- v104: the invited account must be brand new here (first join at most 15 min ago)
	-- v104: and the inviter must be a real Roblox friend of the invited account (IsFriendsWithAsync; a failed check pays nothing)

	FriendsTickSeconds = 60,
	FriendsCashPerTick = 500,
	FriendsCap = 3,
	FriendsDailyCap = 30000, -- v104: at most $30,000 a day (UTC) from the friends bonus per player (saved: rejoining never resets it)

	ComebackDays = 3,
	ComebackCash = 25000,
	-- v104: paid once per absence (profile.ComebackPaidFor = the previous join it paid for) and saved right away
}

function EngagementConfig.LiveFor(feature: string, userId: any): boolean
	local mode = EngagementConfig.Rollout[feature]
	if mode == "all" then
		return true
	elseif mode == "owner" then
		return (require(script.Parent.AdminConfig) :: any).IsPlaytestOwner(userId)
	end
	return false
end

local WEEK = 7 * 86400
local EPOCH_MONDAY = 4 * 86400 -- 1970-01-05 00:00 UTC was a Monday (the Unix epoch was a Thursday)

--[[ The event running at `now` (UTC seconds) and when it ends, or nil plus the next event and when it starts. Pure. ]]
function EngagementConfig.EventAt(now: number): (any?, number, any?)
	local list = EngagementConfig.Events
	if #list == 0 then
		return nil, 0, nil
	end
	local week = math.floor((now - EPOCH_MONDAY) / WEEK)
	local weekStart = EPOCH_MONDAY + week * WEEK
	local ev = list[(week % #list) + 1]
	local startAt = if ev.Window == "Weekend" then weekStart + 4 * 86400 else weekStart
	local endAt = weekStart + WEEK
	if now >= startAt and now < endAt then
		return ev, endAt, nil
	end
	if now < startAt then
		return nil, startAt, ev
	end
	local nxt = list[((week + 1) % #list) + 1]
	local nextStart = if nxt.Window == "Weekend" then endAt + 4 * 86400 else endAt
	return nil, nextStart, nxt
end

return EngagementConfig
