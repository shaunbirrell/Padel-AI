--!strict
--[[
	Code Bot (army command bug, 2026-10-01): the ONE gate for the army command chain logs (client and server).
	  [ARMY SEND]        client: SEND pressed, map mode, GO pressed, the target, the remote fired
	  [SERVER ARMY]      server: a command received (player, command, target) / every rejection (warn, with the reason)
	  [ARMY STATE]       server: ArmyState old -> new SOURCE
	  [ARMY DESTINATION] server: the army destination old / new / source (never the player's pin)
	  [ARMY PATH]        server: route start / destination / distance / status / waypoints
	  [ARMY MOVE]        server: travel started / arrived / the block's progress
	Chain lines print only when ArmyLog.On(player): his WE_ArmyDebug attribute (/armydebug, the admin allowlist) or
	Studio. Live default: OFF for everyone (no spam). A REJECTION always warns (rate-limited per player and reason):
	it is rare, user-initiated, and the owner's bug report needed exactly that line ("the server silently rejects").
]]

local RunService = game:GetService("RunService")

local ArmyLog = {}

ArmyLog.ForceOn = false -- tests
local rejectAt: { [string]: number } = {}

function ArmyLog.On(player: any): boolean
	if ArmyLog.ForceOn then
		return true
	end
	local okS, studio = pcall(function(): boolean
		return RunService:IsStudio()
	end)
	if okS and studio == true then
		return true
	end
	if typeof(player) == "Instance" or typeof(player) == "table" then
		local ok, v = pcall(function(): any
			return (player :: any):GetAttribute("WE_ArmyDebug")
		end)
		return ok and v == true
	end
	return false
end

function ArmyLog.Line(player: any, tag: string, text: string)
	if ArmyLog.On(player) then
		print(string.format("[%s] %s", tag, text))
	end
end

-- a rejection: always a warn (one per player + reason per 2 s)
function ArmyLog.Reject(player: any, what: string, reason: string, detail: string?)
	local name = if player ~= nil then tostring((player :: any).Name) else "?"
	local key = name .. "|" .. what .. "|" .. reason
	local now = os.clock()
	if not ArmyLog.ForceOn and now - (rejectAt[key] or -math.huge) < 2 then
		return
	end
	rejectAt[key] = now
	warn(string.format("[SERVER ARMY] REJECTED %s %s reason=%s%s", name, what, reason, if detail then " " .. detail else ""))
end

function ArmyLog.Vec(v: any): string
	if typeof(v) == "Vector3" then
		return string.format("(%.0f,%.0f,%.0f)", v.X, v.Y, v.Z)
	end
	return tostring(v)
end

return ArmyLog
