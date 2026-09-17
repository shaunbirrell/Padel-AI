--!strict
--[[
	Analytics abstraction. MVP logs to output; plug in real sink later.
	Does not fabricate metrics — only logs events you fire.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnalyticsConfig = require(ReplicatedStorage:WaitForChild("Shared").Configs.AnalyticsConfig)

local AnalyticsService = {}

local sink: ((eventName: string, userId: number?, props: { [string]: any }?) -> ())? = nil

function AnalyticsService.Init()
	-- default sink
end

function AnalyticsService.SetSink(fn: (eventName: string, userId: number?, props: { [string]: any }?) -> ())
	sink = fn
end

function AnalyticsService.Log(eventName: string, userId: number?, props: { [string]: any }?)
	if not AnalyticsConfig.Enabled then
		return
	end
	if sink then
		sink(eventName, userId, props)
		return
	end
	if AnalyticsConfig.LogToOutput then
		local propStr = ""
		if props then
			local parts = {}
			for k, v in pairs(props) do
				table.insert(parts, string.format("%s=%s", tostring(k), tostring(v)))
			end
			propStr = table.concat(parts, ", ")
		end
		print(string.format("[Analytics] %s user=%s %s", eventName, tostring(userId), propStr))
	end
end

return AnalyticsService
