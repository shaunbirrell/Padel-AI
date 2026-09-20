--!strict
--[[
	Simple DataStore session lock to reduce multi-server write races.
	JobId + timestamp; steal if stale / malformed so rejoin after crash
	or place update is reliable within LOCK_TTL (never soft-lock forever).
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
	local aborted = false

	local ok, err = pcall(function()
		ds:UpdateAsync(key, function(old)
			if isLockHeldByOther(old, jobId, now) then
				aborted = true
				return nil -- abort acquire
			end
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

	if aborted then
		return false, "Session locked by another server"
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
			if typeof(old) == "table" and tostring((old :: LockInfo).JobId or "") == jobId then
				return {
					JobId = jobId,
					UserId = userId,
					Timestamp = os.time(),
				}
			end
			return old
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
	pcall(function()
		ds:UpdateAsync(key, function(old)
			if typeof(old) ~= "table" then
				return nil
			end
			local held = tostring((old :: LockInfo).JobId or "")
			-- Release our lock; also clear empty/malformed so rejoin never soft-locks forever
			if held == "" or held == jobId then
				return nil
			end
			return old
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
	pcall(function()
		ds:UpdateAsync(key, function(old)
			if typeof(old) ~= "table" then
				return nil
			end
			local info = old :: LockInfo
			local held = tostring(info.JobId or "")
			local age = now - (tonumber(info.Timestamp) or 0)
			if held == "" or held == jobId or age >= LOCK_TTL then
				return nil
			end
			return old
		end)
	end)
end

return SessionLock
