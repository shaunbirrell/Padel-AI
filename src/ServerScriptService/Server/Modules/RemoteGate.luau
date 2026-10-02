--!strict
--[[
	claude-bud JOB 15 (2026-09-29): the gate in front of every client -> server remote (Shared/Configs/SecurityConfig).
	  RemoteGate.Check(player, remoteName, ...) -> boolean   first line of every OnServerEvent / OnServerInvoke:
	      false = drop the request (only for players the gate is enforced for; observe mode always returns true)
	  RemoteGate.Sink(player, remoteName)                     listener on a remote the client must never fire
	Rate ceiling (token bucket per player per remote) + argument schema. A bad request is logged (throttled, with
	counts) and ignored; only an extreme flood (FloodKick) kicks. Pure Lua state, no instances, no yields.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local SecurityConfig = require(Shared.Configs.SecurityConfig)

local RemoteGate = {}

local C: any = SecurityConfig.RemoteGate
local SCHEMAS: any = SecurityConfig.Schemas

type Bucket = { Tokens: number, At: number }
type PlayerState = {
	Buckets: { [string]: Bucket },
	Rejects: { number }, -- os.clock() of recent rejects (flood window)
	Counts: { [string]: number }, -- reason -> count since the last log line
	LoggedAt: number,
	Kicked: boolean,
}
local states: { [number]: PlayerState } = {}

RemoteGate._clock = os.clock -- tests replace it
RemoteGate._log = warn
RemoteGate._kick = function(player: Player, msg: string)
	player:Kick(msg)
end

local function stateOf(uid: number): PlayerState
	local s = states[uid]
	if s == nil then
		s = { Buckets = {}, Rejects = {}, Counts = {}, LoggedAt = -math.huge, Kicked = false }
		states[uid] = s
	end
	return s :: PlayerState
end

local function finite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function tableOk(t: any, depth: number): boolean
	if depth > C.MaxDepth then
		return false
	end
	local n = 0
	for k, v in pairs(t) do
		n += 1
		if n > C.MaxTableKeys then
			return false
		end
		local kt, vt = typeof(k), typeof(v)
		if kt ~= "string" and kt ~= "number" then
			return false
		end
		if kt == "string" and #k > C.MaxString then
			return false
		end
		if kt == "number" and not finite(k) then
			return false
		end
		if vt == "number" then
			if not finite(v) then
				return false
			end
		elseif vt == "string" then
			if #v > C.MaxString then
				return false
			end
		elseif vt == "Vector3" then
			if not (finite(v.X) and finite(v.Y) and finite(v.Z)) then
				return false
			end
		elseif vt == "table" then
			if not tableOk(v, depth + 1) then
				return false
			end
		elseif vt ~= "boolean" and vt ~= "CFrame" and vt ~= "EnumItem" then
			return false -- Instances and other userdata never ride inside a request table
		end
	end
	return true
end

-- one alternative ("string:32", "number", "table", "Vector3", "boolean", "any")
local function typeOk(spec: string, v: any): boolean
	local base, arg = string.match(spec, "^(%w+):(%d+)$") -- "string:32"; else the whole spec ("Vector3")
	if base == nil then
		base, arg = spec, ""
	end
	if base == "any" then
		return true
	end
	local t = typeof(v)
	if base == "string" then
		local max = tonumber(arg) or C.MaxString
		return t == "string" and #v <= max
	elseif base == "number" then
		return t == "number" and finite(v)
	elseif base == "boolean" then
		return t == "boolean"
	elseif base == "table" then
		return t == "table" and tableOk(v, 1)
	elseif base == "Vector3" then
		return t == "Vector3" and finite(v.X) and finite(v.Y) and finite(v.Z)
	end
	return false
end

-- (ok, reason?) for one remote's arguments
function RemoteGate.Validate(name: string, args: { any }, n: number): (boolean, string?)
	local schema = SCHEMAS[name]
	if schema == nil then
		return true, nil -- no schema: the handler's own checks only
	end
	if n > #schema then
		return false, "extra_args"
	end
	for i, spec in ipairs(schema) do
		local v = args[i]
		local s = spec
		local optional = string.sub(s, -1) == "?"
		if optional then
			s = string.sub(s, 1, -2)
		end
		if v == nil then
			if not optional then
				return false, "arg" .. i .. "_missing"
			end
		else
			local any = false
			for alt in string.gmatch(s, "[^|]+") do
				if typeOk(alt, v) then
					any = true
					break
				end
			end
			if not any then
				return false, "arg" .. i .. "_" .. typeof(v)
			end
		end
	end
	return true, nil
end

local function take(s: PlayerState, name: string, now: number): boolean
	local lim = C.Limits[name] or C.Default
	local b = s.Buckets[name]
	if b == nil then
		b = { Tokens = lim.Burst, At = now }
		s.Buckets[name] = b
	end
	local bk = b :: Bucket
	bk.Tokens = math.min(lim.Burst, bk.Tokens + (now - bk.At) * lim.Rate)
	bk.At = now
	if bk.Tokens >= 1 then
		bk.Tokens -= 1
		return true
	end
	return false
end

-- log + flood accounting for one bad request; returns whether the request must be dropped
local function reject(player: Player, s: PlayerState, name: string, reason: string, enforce: boolean, now: number): boolean
	local key = name .. ":" .. reason
	s.Counts[key] = (s.Counts[key] or 0) + 1
	if now - s.LoggedAt >= C.LogSeconds then
		s.LoggedAt = now
		local parts = {}
		for k, c in pairs(s.Counts) do
			table.insert(parts, k .. " x" .. tostring(c))
		end
		table.sort(parts)
		s.Counts = {}
		RemoteGate._log(string.format("[RemoteGate] %s %s (%d): %s", if enforce then "rejected" else "would reject", player.Name, player.UserId, table.concat(parts, ", ")))
	end
	if not enforce then
		return false
	end
	local fk = C.FloodKick
	table.insert(s.Rejects, now)
	while #s.Rejects > 0 and now - s.Rejects[1] > fk.WindowSeconds do
		table.remove(s.Rejects, 1)
	end
	if #s.Rejects >= fk.Rejects and not s.Kicked then
		s.Kicked = true
		RemoteGate._log(string.format("[RemoteGate] KICK %s (%d): %d rejected requests in %d s", player.Name, player.UserId, #s.Rejects, fk.WindowSeconds))
		pcall(RemoteGate._kick, player, C.KickMessage)
	end
	return true
end

local function mode(player: Player): string
	if SecurityConfig.GateLiveFor(player.UserId) then
		return "enforce"
	end
	return if C.Others == "observe" then "observe" else "off"
end

--[[ true = let the handler run. The first line of every client -> server handler. ]]
function RemoteGate.Check(player: Player, name: string, ...: any): boolean
	local m = mode(player)
	if m == "off" then
		return true
	end
	local enforce = m == "enforce"
	local now = RemoteGate._clock()
	local s = stateOf(player.UserId)
	if s.Kicked and enforce then
		return false
	end
	if not take(s, name, now) then
		return not reject(player, s, name, "rate", enforce, now)
	end
	local n = select("#", ...)
	local ok, why = RemoteGate.Validate(name, { ... }, n)
	if not ok then
		return not reject(player, s, name, why or "bad", enforce, now)
	end
	return true
end

--[[ A client fired a remote it must never fire (a server push or an unused request): always a bad request. ]]
function RemoteGate.Sink(player: Player, name: string)
	local m = mode(player)
	if m == "off" then
		return
	end
	reject(player, stateOf(player.UserId), name, "not_client", m == "enforce", RemoteGate._clock())
end

function RemoteGate.Forget(userId: number)
	states[userId] = nil
end

function RemoteGate._Reset()
	states = {}
end

return RemoteGate
