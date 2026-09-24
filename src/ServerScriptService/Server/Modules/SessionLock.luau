--!strict
--[[
	Simple DataStore session lock to reduce multi-server write races.
	JobId + timestamp; steal if stale / malformed so rejoin after crash
	or place update is reliable within LOCK_TTL (never soft-lock forever).

	v70: returning nil from an UpdateAsync transform CANCELS the write (it never deletes the key), so
	Release / ForceRelease write a free tombstone { JobId = "" } instead. TryAcquire waits a few seconds
	for another server's lock to be released (the server the player just left is still saving), so the
	load that follows reads that server's final save instead of an older one.
]]

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local SessionLock = {}

export type LockInfo = {
	JobId: string,
	UserId: number,
	Timestamp: number,
}

local STORE_NAME = Constants.SessionStoreName
-- Stale threshold: after force-quit / dead server, rejoin can take over.
-- Must stay ABOVE SessionLockRefreshSeconds (see DataService heartbeat).
local LOCK_TTL = Constants.SessionLockTtlSeconds
-- A player hopping servers: the old server's leave-save + Release usually lands within a few seconds.
local ACQUIRE_WAIT_SECONDS = tonumber((Constants :: any).SessionLockAcquireWaitSeconds) or 12
local ACQUIRE_POLL_SECONDS = 2
-- v70: userIds whose lock THIS server released (leave / shutdown). Refresh never re-claims those; for the
-- rest it takes over a free or stale lock, so a session whose TryAcquire timed out still ends up holding it.
local releasedHere: { [number]: boolean } = {}
local store: DataStore? = nil

local function getStore(): DataStore?
	if store then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
		return store
	end
	warn("[SessionLock] DataStore unavailable:", result)
	return nil
end

local function thisJobId(): string
	return if RunService:IsStudio() then "STUDIO" else game.JobId
end

local function isLockHeldByOther(info: any, jobId: string, now: number): boolean
	if typeof(info) ~= "table" then
		return false
	end
	local heldJob = tostring((info :: LockInfo).JobId or "")
	if heldJob == "" or heldJob == jobId then
		return false -- missing jobId or ours → take / refresh
	end
	local age = now - (tonumber((info :: LockInfo).Timestamp) or 0)
	if age < 0 then
		age = 0
	end
	-- Stale lock → allow takeover (crash / BindToClose miss / place update)
	if age >= LOCK_TTL then
		return false
	end
	return true
end

--- A released lock. isLockHeldByOther treats JobId "" as free, so any server may take it.
local function freeLock(userId: number): LockInfo
	return {
		JobId = "",
		UserId = userId,
		Timestamp = 0,
	}
end

function SessionLock.GetTtlSeconds(): number
	return LOCK_TTL
end

function SessionLock.TryAcquire(userId: number): (boolean, string?)
	local ds = getStore()
	if not ds then
		-- Studio without API services: allow
		return true, nil
	end

	local key = "lock_" .. tostring(userId)
	local jobId = thisJobId()
	local now = os.time()
	local deadline = os.clock() + ACQUIRE_WAIT_SECONDS
	releasedHere[userId] = nil

	while true do
		local aborted = false
		now = os.time()
		local ok, err = pcall(function()
			ds:UpdateAsync(key, function(old)
				if isLockHeldByOther(old, jobId, now) then
					aborted = true
					return nil -- cancel: leave the other server's lock untouched
				end
				aborted = false
				return {
					JobId = jobId,
					UserId = userId,
					Timestamp = now,
				} :: LockInfo
			end)
		end)

		if not ok then
			return false, tostring(err)
		end
		if not aborted then
			break
		end
		-- Held by a live server — usually the one the player just left, still saving. Give it time to
		-- release so the caller's read sees that final save; stale locks expire via LOCK_TTL.
		if os.clock() >= deadline then
			return false, "Session locked by another server"
		end
		task.wait(ACQUIRE_POLL_SECONDS)
	end

	-- Confirm we hold the lock (UpdateAsync nil-abort path + races)
	local readOk, current = pcall(function()
		return ds:GetAsync(key)
	end)
	if readOk and typeof(current) == "table" then
		local cur = current :: LockInfo
		local curJob = tostring(cur.JobId or "")
		if curJob ~= jobId then
			local age = now - (tonumber(cur.Timestamp) or 0)
			if age < LOCK_TTL and curJob ~= "" then
				return false, "Session locked by another server"
			end
			-- Stale or missing JobId after race: clear and claim
			local claimed = false
			local clearOk = pcall(function()
				ds:UpdateAsync(key, function(old)
					if isLockHeldByOther(old, jobId, os.time()) then
						return nil
					end
					claimed = true
					return {
						JobId = jobId,
						UserId = userId,
						Timestamp = os.time(),
					} :: LockInfo
				end)
			end)
			if not clearOk or not claimed then
				-- Re-check; another server may have won the race
				local verifyOk, verify = pcall(function()
					return ds:GetAsync(key)
				end)
				if verifyOk and typeof(verify) == "table" and tostring((verify :: LockInfo).JobId or "") ~= jobId then
					return false, "Session locked by another server"
				end
			end
		end
	end

	return true, nil
end

function SessionLock.Refresh(userId: number)
	local ds = getStore()
	if not ds then
		return
	end
	local key = "lock_" .. tostring(userId)
	local jobId = thisJobId()
	pcall(function()
		ds:UpdateAsync(key, function(old)
			local ours = typeof(old) == "table" and tostring((old :: LockInfo).JobId or "") == jobId
			-- v70: a free / stale lock is taken over (this server still has the player loaded: e.g. TryAcquire
			-- timed out while the previous server was still saving) — unless this server already released it.
			if ours or (not releasedHere[userId] and not isLockHeldByOther(old, jobId, os.time())) then
				return {
					JobId = jobId,
					UserId = userId,
					Timestamp = os.time(),
				}
			end
			return nil -- another server's live lock, or released here: cancel (no write)
		end)
	end)
end

function SessionLock.Release(userId: number)
	local ds = getStore()
	if not ds then
		return
	end
	local key = "lock_" .. tostring(userId)
	local jobId = thisJobId()
	releasedHere[userId] = true -- before the yield: a Refresh queued after this must not re-claim
	pcall(function()
		ds:UpdateAsync(key, function(old)
			if typeof(old) ~= "table" then
				return nil -- no lock record: nothing to release (nil cancels the write)
			end
			local held = tostring((old :: LockInfo).JobId or "")
			if held == jobId then
				-- v70: write a free lock. Returning nil here would cancel the write and keep our lock.
				return freeLock(userId)
			end
			return nil -- already free, or another server's lock: leave it untouched
		end)
	end)
end

--- BindToClose / emergency: clear lock for this user if we own it or it is stale.
function SessionLock.ForceReleaseIfStaleOrOurs(userId: number)
	local ds = getStore()
	if not ds then
		return
	end
	local key = "lock_" .. tostring(userId)
	local jobId = thisJobId()
	local now = os.time()
	releasedHere[userId] = true
	pcall(function()
		ds:UpdateAsync(key, function(old)
			if typeof(old) ~= "table" then
				return nil -- nothing to clear (nil cancels the write)
			end
			local info = old :: LockInfo
			local held = tostring(info.JobId or "")
			if held == "" then
				return nil -- already free
			end
			local age = now - (tonumber(info.Timestamp) or 0)
			if held == jobId or age >= LOCK_TTL then
				return freeLock(userId) -- v70: an actual write; nil would keep the lock
			end
			return nil -- another live server's lock: leave it untouched
		end)
	end)
end

return SessionLock
