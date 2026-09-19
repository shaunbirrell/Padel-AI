--!strict
--[[
	Studio-only: listen for StudioSmokeLog RemoteEvent and print loud [SMOKE] lines
	in the *client* Output window (Play Solo). Server prints alone can be easy to miss
	when the Output filter is set to Client.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StudioSmokeClient = {}

function StudioSmokeClient.Init()
	if not RunService:IsStudio() then
		return
	end

	task.spawn(function()
		local Shared = ReplicatedStorage:WaitForChild("Shared", 30)
		if not Shared then
			return
		end
		local okC, Constants = pcall(function()
			return require(Shared.Constants)
		end)
		local okR, Remotes = pcall(function()
			return require(Shared.Remotes)
		end)
		if not (okC and okR and Constants and Remotes) then
			warn("[SMOKE] client listener: Constants/Remotes require failed")
			return
		end
		local name = Constants.RemoteNames and Constants.RemoteNames.StudioSmokeLog
		if typeof(name) ~= "string" then
			return
		end
		local okEv, ev = pcall(function()
			return Remotes.GetEvent(name)
		end)
		if not okEv or not ev then
			warn("[SMOKE] client listener: StudioSmokeLog remote missing")
			return
		end

		print("[SMOKE] client listener armed — will echo StudioSmokeLog here")
		ev.OnClientEvent:Connect(function(kind: any, line: any, _t: any)
			local text = if typeof(line) == "string" then line else string.format("[SMOKE] BUY %s", tostring(kind))
			print("========== CLIENT " .. text .. " ==========")
			print(text)
			if tostring(kind) == "FAIL" then
				warn(text)
			elseif tostring(kind) == "OK" then
				print("[SMOKE] ★★★ CLIENT SAW BUY OK ★★★")
			end
		end)
	end)
end

return StudioSmokeClient
