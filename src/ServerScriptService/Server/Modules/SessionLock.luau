--!strict
--[[
	Simple DataStore session lock to reduce multi-server write races.
	JobId + timestamp; steal if stale.
]]

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local SessionLock = {}

local STORE_NAME = Constants.SessionStoreName
local LOCK_TTL = 60 * 30 -- 30 minutes stale threshold
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

export type LockInfo = {
	JobId: string,
	UserId: number,
	Timestamp: number,
}

function SessionLock.TryAcquire(userId: number): (boolean, string?)
	local ds = getStore()
	if not ds then
		-- Studio without API services: allow
		return true, nil
	end

	local key = "lock_" .. tostring(userId)
	local jobId = if RunService:IsStudio() then "STUDIO" else game.JobId
	local now = os.time()

	local ok, err = pcall(function()
		ds:UpdateAsync(key, function(old)
			local info = old :: LockInfo?
			if info and typeof(info) == "table" then
				local age = now - (tonumber(info.Timestamp) or 0)
				if info.JobId ~= jobId and age < LOCK_TTL then
					return nil -- abort acquire
				end
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

	-- UpdateAsync returning nil means conflict — re-read
	local readOk, current = pcall(function()
		return ds:GetAsync(key)
	end)
	if readOk and typeof(current) == "table" and (current :: LockInfo).JobId ~= jobId then
		return false, "Session locked by another server"
	end

	return true, nil
end

function SessionLock.Refresh(userId: number)
	local ds = getStore()
	if not ds then
		return
	end
	local key = "lock_" .. tostring(userId)
	local jobId = if RunService:IsStudio() then "STUDIO" else game.JobId
	pcall(function()
		ds:UpdateAsync(key, function(old)
			if typeof(old) == "table" and (old :: LockInfo).JobId == jobId then
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
	local jobId = if RunService:IsStudio() then "STUDIO" else game.JobId
	pcall(function()
		ds:UpdateAsync(key, function(old)
			if typeof(old) == "table" and (old :: LockInfo).JobId == jobId then
				return nil
			end
			return old
		end)
	end)
end

return SessionLock
