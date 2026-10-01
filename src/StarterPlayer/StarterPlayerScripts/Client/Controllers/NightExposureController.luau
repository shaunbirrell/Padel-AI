--!strict
--[[ claude-bud JOB 54: the night exposure. The server's day / night cycle (WorldAtmosphere) never writes
	Lighting.ExposureCompensation, so a client write stays. While LightingConfig.Night2 is live for this player
	(owner-first), it eases the exposure from Exposure.Day (0 = today's look) to Exposure.Night by the night share
	(LightingConfig.Cycle, the same ramps the server uses), every Exposure.RefreshSeconds (no per-frame work), and
	writes only when the value changed. OFF = never touches the property. ]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)

local NightExposureController = {}

-- the night share of a clock time (pure; = WorldAtmosphere.NightShare on LightingConfig.Cycle)
function NightExposureController.NightShare(t: number, C: any): number
	if t < C.NightEnd or t > C.NightStart then
		return 1
	elseif t < C.DawnEnd then
		return 1 - (t - C.NightEnd) / math.max(0.01, C.DawnEnd - C.NightEnd)
	elseif t > C.DuskStart then
		return (t - C.DuskStart) / math.max(0.01, C.NightStart - C.DuskStart)
	end
	return 0
end

-- the exposure for a clock time (pure; rounded to 0.01 so it settles and stops writing)
function NightExposureController.ExposureAt(t: number, LC: any): number
	local E = LC.Night2.Exposure
	local share = NightExposureController.NightShare(t, LC.Cycle)
	return math.floor((E.Day + (E.Night - E.Day) * share) * 100 + 0.5) / 100
end

function NightExposureController.Init()
	if Shared == nil then
		return
	end
	local okC, LC = pcall(function(): any
		return (require :: any)((Shared :: any).Configs.LightingConfig)
	end)
	local okR, RC = pcall(function(): any
		return (require :: any)((Shared :: any).Configs.RetentionConfig)
	end)
	if not okC or not okR or typeof(LC.Night2) ~= "table" or not LC.Enabled then
		return
	end
	local player = Players.LocalPlayer
	if not RC.Live(LC.Night2, player.UserId) then
		return
	end
	task.spawn(function()
		while true do
			local v = NightExposureController.ExposureAt(Lighting.ClockTime, LC)
			if math.abs(Lighting.ExposureCompensation - v) > 0.005 then
				Lighting.ExposureCompensation = v
			end
			task.wait(math.max(1, tonumber(LC.Night2.Exposure.RefreshSeconds) or 2))
		end
	end)
end

return NightExposureController
