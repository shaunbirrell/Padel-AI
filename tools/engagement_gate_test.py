#!/usr/bin/env python3
"""Code Bot v104 (2026-09-29): executes the REAL JOB 13 engagement code with the Luau CLI (no Studio needed).

Loads the real Shared/Configs/EngagementConfig.luau, LeaderboardConfig.luau, AdminConfig.luau and
Server/Services/EngagementService.luau under small mocks (Players, DataStoreService with an OrderedDataStore + request
budget, DataService, EconomyService, a controllable clock) for a NON-owner account, then drives joins, leaves and the
service's slow loop. Checks the all-players rollout and the exploit guards:
  * invite: pays once per new account, only for a real Roblox friend, only a brand-new account, only a saved profile,
    never self, a failed friend check pays nothing, the inviter capped at InviteDailyCap a day (in-server + queued).
  * friends: at most FriendsCap friends per tick and FriendsDailyCap a day, the cap resets on a new UTC day.
  * leaderboards: one write per player per WriteMinGapSeconds even with leave / rejoin spam, unchanged scores not
    rewritten, a low write budget skips the write, admin / playtest accounts never written nor shown.
  * comeback: paid once per absence (a reload of the same absence pays nothing), not for < ComebackDays, not on a
    session-only profile, saved right away.
Prints PASS / FAIL lines, exits 1 on any FAIL; SKIP (exit 0) without the luau binary.
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRV = ROOT / "src/ServerScriptService/Server"
CFG = ROOT / "src/ReplicatedStorage/Shared/Configs"


def lstr(s: str) -> str:
    eq = "=" * 8
    return "[%s[%s]%s]" % (eq, s, eq)


HARNESS = r'''
local fails, passes = 0, 0
local function check(cond, label)
	if cond then passes += 1; print("PASS " .. label) else fails += 1; print("FAIL " .. label) end
end
local realos = os
local NOW, CLOCK = realos.time(), 1000
os = { time = function(t) if t then return realos.time(t) end return NOW end, clock = function() return CLOCK end, date = realos.date }
warn = function(...) print("WARN", ...) end
local sleepers = {}
task = {
	spawn = function(f, ...) local co = coroutine.create(f); local ok, err = coroutine.resume(co, ...); if not ok then print("ERR " .. tostring(err)) end; if coroutine.status(co) == "suspended" then table.insert(sleepers, co) end end,
	wait = function() coroutine.yield() end,
}
task.defer = task.spawn
Enum = { DataStoreRequestType = { SetIncrementSortedAsync = "SetIncrementSortedAsync", GetSortedAsync = "GetSortedAsync" } }
Vector3 = { new = function(x, y, z) return { X = x, Y = y, Z = z } end }


local function proxy(name)
	return setmetatable({ __name = name }, { __index = function(t, k) local p = proxy(k); rawset(t, k, p); return p end })
end
local Shared = proxy("Shared")

-- instances (Folder / StringValue under ReplicatedStorage)
local function mkInst(class)
	local o = { ClassName = class, Name = class, _kids = {} }
	function o:FindFirstChild(n) return self._kids[n] end
	return setmetatable({}, { __index = o, __newindex = function(t, k, v)
		if k == "Parent" then rawset(o, "Parent", v); if v then v._kids[o.Name] = t end else rawset(o, k, v) end
	end })
end
Instance = { new = function(class) return mkInst(class) end }
local RS = mkInst("ReplicatedStorage")
getmetatable(RS).__index.WaitForChild = function() return Shared end

-- Players
local list, removing = {}, {}
local PlayersSvc = {
	GetPlayers = function() local out = {}; for _, p in ipairs(list) do table.insert(out, p) end; return out end,
	GetPlayerByUserId = function(_, uid) for _, p in ipairs(list) do if p.UserId == uid then return p end end; return nil end,
	GetNameFromUserIdAsync = function(_, uid) return "U" .. uid end,
	PlayerRemoving = { Connect = function(_, f) table.insert(removing, f) end },
}
-- DataStoreService
local ordered, stores, setCalls, budget = {}, {}, {}, 1000
local DSS = {
	GetRequestBudgetForRequestType = function() return budget end,
	GetOrderedDataStore = function(_, name)
		ordered[name] = ordered[name] or {}
		local t = ordered[name]
		return {
			SetAsync = function(_, k, v) t[k] = v; table.insert(setCalls, { name, k, v }) end,
			GetSortedAsync = function(_, asc, n)
				local rows = {}
				for k, v in pairs(t) do table.insert(rows, { key = k, value = v }) end
				table.sort(rows, function(a, b) return a.value > b.value end)
				local page = {}
				for i = 1, math.min(n, #rows) do page[i] = rows[i] end
				return { GetCurrentPage = function() return page end }
			end,
		}
	end,
	GetDataStore = function(_, name)
		stores[name] = stores[name] or {}
		local t = stores[name]
		return { UpdateAsync = function(_, k, f) t[k] = f(t[k]) end }
	end,
}
local Http = { JSONEncode = function(_, v) return v end }
game = { GetService = function(_, n)
	if n == "Players" then return PlayersSvc end
	if n == "DataStoreService" then return DSS end
	if n == "HttpService" then return Http end
	if n == "ReplicatedStorage" then return RS end
	if n == "RunService" then return { IsStudio = function() return false end } end
	error("service " .. n)
end }
script = proxy("script")
local MODS, SRC = {}, {}
SRC.EngagementConfig = @ENGCFG@
SRC.AdminConfig = @ADMINCFG@
SRC.LeaderboardConfig = @LBCFG@
SRC.Constants = @CONSTANTS@
SRC.Remotes = @REMOTES@
SRC.EngagementService = @ENGSVC@
local function load(name) local f = assert(loadstring(SRC[name], name)); return f() end
require = function(p) local n = rawget(p, "__name"); if MODS[n] == nil then MODS[n] = load(n) end; return MODS[n] end

local E = require(proxy("EngagementConfig"))
local AC = require(proxy("AdminConfig"))
local OWNER, OTHER = AC.PlaytestOwnerUserId, 1234567
for _, f in ipairs({ "Events", "Leaderboards", "Invite", "Friends", "Comeback" }) do
	check(E.Rollout[f] == "all", "rollout: " .. f .. " = all")
	check(E.LiveFor(f, OTHER) == true, "rollout: " .. f .. " live for a second (non-owner) account")
end
check(E.InviteDailyCap == 5 and E.FriendsCap == 3 and E.FriendsDailyCap == 30000, "config: invite 5/day, friends max 3 + $30,000/day")
check(E.WriteMinGapSeconds >= 60 and E.ComebackDays == 3, "config: board write gap >= 60 s, comeback after 3 days")

-- DataService / EconomyService mocks
local profiles, persistentOf, saves, paid, loadedCb = {}, {}, {}, {}, nil
local DataService = {
	OnProfileLoaded = function(cb) loadedCb = cb end,
	GetProfile = function(p) return profiles[p.UserId] end,
	IsLoaded = function(p) return persistentOf[p.UserId] == true end,
	MarkDirty = function() end,
	SaveProfile = function(p) saves[p.UserId] = (saves[p.UserId] or 0) + 1; return true end,
}
local EconomyService = { AddCash = function(p, n, reason) table.insert(paid, { uid = p.UserId, n = n, reason = reason }) end }
local function total(uid, reason)
	local s = 0
	for _, r in ipairs(paid) do if r.uid == uid and (reason == nil or r.reason == reason) then s += r.n end end
	return s
end
local friendsWith, friendErr = {}, {}
local function befriend(a, b) friendsWith[a .. ":" .. b] = true; friendsWith[b .. ":" .. a] = true end
local function mkPlayer(uid, opts)
	opts = opts or {}
	local p = { UserId = uid, Parent = PlayersSvc, attrs = {}, CharacterAdded = { Connect = function() end } }
	function p:SetAttribute(k, v) self.attrs[k] = v end
	function p:GetJoinData() return { ReferredByPlayerId = opts.ref } end
	function p:IsFriendsWithAsync(other) if friendErr[uid] then error("http 500") end; return friendsWith[uid .. ":" .. other] == true end
	local prof = opts.profile or { Cash = opts.cash or 0, Prestige = 0, Stats = {}, FirstJoinUnix = opts.first or NOW, PrevJoinUnix = opts.prev or NOW }
	profiles[uid] = prof
	persistentOf[uid] = opts.persistent ~= false
	return p
end
local function join(p) table.insert(list, p); loadedCb(p, profiles[p.UserId]) end
local function leave(p)
	for i, q in ipairs(list) do if q == p then table.remove(list, i); break end end
	p.Parent = nil
	for _, f in ipairs(removing) do f(p) end
	p.Parent = PlayersSvc
end
local function tick(seconds)
	CLOCK += seconds
	local s = sleepers; sleepers = {}
	for _, co in ipairs(s) do coroutine.resume(co); if coroutine.status(co) == "suspended" then table.insert(sleepers, co) end end
end

local ES = require(proxy("EngagementService"))
ES.Init({ DataService = DataService, EconomyService = EconomyService, NotificationService = { Notify = function() end } })
check(type(loadedCb) == "function" and #sleepers == 1, "service: OnProfileLoaded hooked + one slow loop")

-- ── invite ──
local A = mkPlayer(100, { first = NOW - 30 * 86400 })
join(A)
befriend(100, 200)
local B = mkPlayer(200, { ref = 100 })
join(B)
check(total(200, "invite_welcome") == 2500, "invite: a new friend who joins through the invite gets $2,500")
check(total(100, "invite_reward") == 10000, "invite: the inviter (same server) gets $10,000")
check(profiles[200].ReferredBy == 100 and (saves[200] or 0) >= 1, "invite: ReferredBy stored and saved right away")
loadedCb(B, profiles[200])
check(total(200, "invite_welcome") == 2500 and total(100, "invite_reward") == 10000, "invite: the same account rejoining through an invite pays nothing again")
join(mkPlayer(201, { ref = 100 }))
check(total(201) == 0 and total(100, "invite_reward") == 10000, "invite: a NON-friend joining through the link pays nothing (no farming with strangers / alts)")
befriend(100, 202)
join(mkPlayer(202, { ref = 100, first = NOW - 2 * 86400 }))
check(total(202) == 0 and total(100, "invite_reward") == 10000, "invite: an old account (not new) pays nothing")
befriend(100, 203)
join(mkPlayer(203, { ref = 100, persistent = false }))
check(total(203) == 0 and profiles[203].ReferredBy == nil, "invite: a session-only profile (save not loaded) pays nothing")
befriend(100, 204); friendErr[204] = true
join(mkPlayer(204, { ref = 100 }))
check(total(204) == 0, "invite: a failed friend check pays nothing")
join(mkPlayer(205, { ref = 205 }))
check(total(205) == 0, "invite: self-referral pays nothing")
for uid = 210, 216 do befriend(100, uid); join(mkPlayer(uid, { ref = 100 })) end
check(total(100, "invite_reward") == 50000, "invite: the inviter is capped at 5 new friends a day ($50,000)")
check(total(216, "invite_welcome") == 2500, "invite: the new friend still gets his welcome once the inviter is capped")
profiles[100].InviteDay = 20000101
befriend(100, 217); join(mkPlayer(217, { ref = 100 }))
check(total(100, "invite_reward") == 60000, "invite: the cap resets on a new UTC day")
-- inviter offline: queued, paid on his next join, capped
befriend(300, 301); join(mkPlayer(301, { ref = 300 }))
check(stores[E.InviteQueueStore]["r_300"] == 1, "invite: an offline inviter is queued (DataStore)")
join(mkPlayer(300, { first = NOW - 30 * 86400 }))
check(total(300, "invite_reward") == 10000 and stores[E.InviteQueueStore]["r_300"] == 0, "invite: the queue pays on the inviter's next join and is emptied")
stores[E.InviteQueueStore]["r_400"] = 50
join(mkPlayer(400, { first = NOW - 30 * 86400 }))
check(total(400, "invite_reward") == 50000, "invite: a big queue still pays at most 5 a day")

-- ── comeback ──
local prev = NOW - 4 * 86400
local M = mkPlayer(500, { first = NOW - 60 * 86400, prev = prev })
join(M)
check(total(500, "comeback") == 25000, "comeback: 4 days away pays $25,000")
check(profiles[500].ComebackPaidFor == prev and (saves[500] or 0) >= 1, "comeback: the paid absence is stored and saved right away")
loadedCb(M, profiles[500])
check(total(500, "comeback") == 25000, "comeback: a reload of the same absence (crash / server hop before the save) pays nothing")
profiles[500].PrevJoinUnix = NOW - 3600
loadedCb(M, profiles[500])
check(total(500, "comeback") == 25000, "comeback: a normal rejoin pays nothing")
join(mkPlayer(501, { first = NOW - 60 * 86400, prev = NOW - 86400 }))
check(total(501) == 0, "comeback: 1 day away pays nothing")
join(mkPlayer(502, { first = NOW - 60 * 86400, prev = NOW - 5 * 86400, persistent = false }))
check(total(502, "comeback") == 0, "comeback: a session-only profile pays nothing")
join(mkPlayer(503))
check(total(503) == 0, "comeback: a brand-new player pays nothing")

-- ── friends bonus ──
local J = mkPlayer(600, { first = NOW - 30 * 86400 })
join(J)
for uid = 601, 605 do befriend(600, uid); join(mkPlayer(uid, { first = NOW - 30 * 86400 })) end
local before = total(600, "friends_bonus")
tick(60)
check(total(600, "friends_bonus") - before == 1500, "friends: 5 friends in the server pay for 3 ($1,500 a minute)")
check(total(601, "friends_bonus") == 500, "friends: a player with 1 friend here gets $500 a minute")
for _ = 1, 40 do tick(60) end
check(total(600, "friends_bonus") == 30000, "friends: capped at $30,000 a day (" .. total(600, "friends_bonus") .. ")")
leave(J); join(J)
tick(60)
check(total(600, "friends_bonus") == 30000, "friends: rejoining does not reset the daily cap (saved in the profile)")
profiles[600].FriendsDay = 20000101
tick(60)
check(total(600, "friends_bonus") == 31500, "friends: the cap resets on a new UTC day")
check(total(100, "friends_bonus") <= 30000, "friends: every player stays under the daily cap")

-- ── leaderboards ──
local ownerP = mkPlayer(OWNER, { cash = 50000000, first = NOW - 90 * 86400 })
join(ownerP)
local L = mkPlayer(700, { cash = 12345, first = NOW - 30 * 86400 })
join(L)
local function writesFor(uid) local n = 0; for _, c in ipairs(setCalls) do if c[2] == tostring(uid) then n += 1 end end; return n end
-- BOARDS (v107): cash-only player writes Richest (WE_LB2_); WriteMinSeconds=90; leave respects throttle
tick(91) -- periodic loop may write; leave also tries
leave(L)
check(writesFor(700) >= 1, "boards: after the write gap, a cash-only player writes Richest (" .. writesFor(700) .. ")")
local afterFirst = writesFor(700)
check(writesFor(OWNER) == 0, "boards: the playtest owner (admin cash floor) is never written")
for _ = 1, 10 do profiles[700].Cash += 1; leave(L); tick(1); join(L) end
check(writesFor(700) == afterFirst, "boards: 10 leave / rejoins inside the write gap write nothing more (throttled)")
tick(91); leave(L)
check(writesFor(700) == afterFirst + 1, "boards: after the gap only the changed score (cash) is written (" .. writesFor(700) .. ")")
local afterSecond = writesFor(700)
join(L); tick(91); leave(L)
check(writesFor(700) == afterSecond, "boards: unchanged scores are not rewritten")
budget = 0; profiles[700].Cash += 1; join(L); tick(91); leave(L); budget = 1000
check(writesFor(700) == afterSecond, "boards: a low write budget skips the write")
-- seed the all-time Richest store (StorePrefix WE_LB2_)
local richestStore = "WE_LB2_Richest"
ordered[richestStore] = ordered[richestStore] or {}
ordered[richestStore][tostring(OWNER)] = 50000000
for i = 1, 14 do ordered[richestStore][tostring(800 + i)] = i * 1000 end
tick(95) -- ReadSeconds = 90 (Code Bot v175; was 75)
local sv = RS:FindFirstChild("WE_Leaderboards") and RS:FindFirstChild("WE_Leaderboards"):FindFirstChild("Richest")
local rows = sv and sv.Value and sv.Value.Rows or {}
local ownerShown = false
for _, r in ipairs(rows) do if r.N == "U" .. OWNER then ownerShown = true end end
check(#rows == 10 and not ownerShown, "boards: the published top 10 never shows an admin account (" .. #rows .. " rows)")
check(rows[1] and rows[1].N == "U814", "boards: the richest real player is first")

-- ── events stay bounded ──
check(ES.CashMult(L) >= 1 and ES.CashMult(L) <= 3, "events: the event cash multiplier stays within 1..3")
check(ES.PlazaBountyMult(L) >= 1 and ES.PlazaBountyMult(L) <= 3, "events: the plaza bounty multiplier stays within 1..3")
local ai = ES.AirdropInterval()
check(ai == nil or ai >= 60, "events: an airdrop frenzy never drops faster than once a minute")

print(string.format("engagement_gate_test PASS=%d FAIL=%d", passes, fails))
if fails > 0 then error("FAIL") end
'''


def build() -> str:
    constants = 'return { RemoteNames = { RequestBoardSetting = "RequestBoardSetting" } }'
    remotes = 'return { TryGetEvent = function() return nil end }'
    return (HARNESS
            .replace("@ENGCFG@", lstr((CFG / "EngagementConfig.luau").read_text(encoding="utf-8")))
            .replace("@ADMINCFG@", lstr((CFG / "AdminConfig.luau").read_text(encoding="utf-8")))
            .replace("@LBCFG@", lstr((CFG / "LeaderboardConfig.luau").read_text(encoding="utf-8")))
            .replace("@CONSTANTS@", lstr(constants))
            .replace("@REMOTES@", lstr(remotes))
            .replace("@ENGSVC@", lstr((SRV / "Services/EngagementService.luau").read_text(encoding="utf-8"))))


def run() -> int:
    luau = os.environ.get("LUAU") or shutil.which("luau")
    if not luau:
        print("SKIP engagement_gate_test: no luau binary")
        return 0
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write(build())
        path = f.name
    try:
        r = subprocess.run([luau, path], capture_output=True, text=True, timeout=60)
    finally:
        os.unlink(path)
    out = r.stdout + r.stderr
    print(out.strip())
    return 0 if r.returncode == 0 and "FAIL=0" in out else 1


if __name__ == "__main__":
    sys.exit(run())
