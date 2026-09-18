--!strict
--[[
	Shared client→server remote argument guards.
	Use with RateLimitService + DataService.GetProfile — never trust client types/ranges.
]]

local RemoteGuard = {}

local DEFAULT_ID_MAX = 64
local DEFAULT_KEY_MAX = 48
local DEFAULT_CMD_MAX = 32

function RemoteGuard.IsFiniteNumber(n: any): boolean
	return typeof(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

--[[ Non-empty string within max length (ids, keys, mission ids). ]]
function RemoteGuard.IsIdString(value: any, maxLen: number?): boolean
	if typeof(value) ~= "string" then
		return false
	end
	local s = value :: string
	if s == "" then
		return false
	end
	local max = maxLen or DEFAULT_ID_MAX
	return #s <= max
end

function RemoteGuard.IsKeyString(value: any, maxLen: number?): boolean
	return RemoteGuard.IsIdString(value, maxLen or DEFAULT_KEY_MAX)
end

function RemoteGuard.IsCommandString(value: any, maxLen: number?): boolean
	return RemoteGuard.IsIdString(value, maxLen or DEFAULT_CMD_MAX)
end

--[[ Floor + clamp to [minN, maxN]; nil if not a finite number. ]]
function RemoteGuard.ClampInt(value: any, minN: number, maxN: number): number?
	if not RemoteGuard.IsFiniteNumber(value) then
		return nil
	end
	local n = math.floor(value :: number)
	if n < minN or n > maxN then
		return nil
	end
	return n
end

function RemoteGuard.ClampPositiveInt(value: any, maxN: number): number?
	return RemoteGuard.ClampInt(value, 1, maxN)
end

--[[ Profile must be loaded before mutating economy / progression. ]]
function RemoteGuard.RequireProfile(dataService: any, player: Player): any?
	if not dataService or not dataService.GetProfile then
		return nil
	end
	return dataService.GetProfile(player)
end

return RemoteGuard
