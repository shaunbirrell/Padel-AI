--!strict
--[[
	claude-bud JOB 29 (2026-09-30): the ONE place the client asks Roblox for experience-notification opt-in.
	Used by RetentionController (the server's calm-moment ask, FeaturePush "NotifOptIn") and SettingsController (the
	player's own TURN ON tap).

	The steps:
	  1. ExperienceNotificationService:CanPromptOptInAsync(), then :PromptOptIn();
	  2. wait for OptInPromptClosed (at most 120 s);
	  3. ask CanPromptOptInAsync() again: false = accepted (or Roblox's own limit), true = declined; an error or no
	     prompt = unavailable.
	The result goes to the server on RequestNotifOptInResult (result, source). Every Roblox call is pcall'd; it never
	throws. Studio cannot show the Roblox prompt, so it reports "unavailable" there.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NotifOptIn = {}

local asking = false

-- true when Roblox would show the prompt now (yields; false on any error)
function NotifOptIn.CanAsk(): boolean
	local okS, svc = pcall(function(): any
		return game:GetService("ExperienceNotificationService")
	end)
	if not okS or svc == nil then
		return false
	end
	local ok, can = pcall(function()
		return svc:CanPromptOptInAsync()
	end)
	return ok and can == true
end

--[[ Ask (source = "auto" | "settings"). Yields in its own thread; reports the result to the server. Returns at once
	when an ask is already running. ]]
function NotifOptIn.Ask(source: string)
	if asking then
		return
	end
	asking = true
	task.spawn(function()
		local result = "unavailable"
		local okS, ens = pcall(function(): any
			return game:GetService("ExperienceNotificationService")
		end)
		local svc: any = if okS then ens else nil
		if svc and NotifOptIn.CanAsk() then
			local closed = false
			local conn: RBXScriptConnection? = nil
			pcall(function()
				conn = svc.OptInPromptClosed:Connect(function()
					closed = true
				end)
			end)
			local okP = pcall(function()
				svc:PromptOptIn()
			end)
			if okP then
				local left = 120
				while not closed and left > 0 do
					task.wait(0.5)
					left -= 0.5
				end
				local okA, stillCan = pcall(function()
					return svc:CanPromptOptInAsync()
				end)
				result = if okA and stillCan == false then "accepted" elseif okA then "declined" else "unavailable"
			end
			if conn then
				conn:Disconnect()
			end
		end
		local Shared = ReplicatedStorage:FindFirstChild("Shared")
		if Shared then
			local Remotes = require((Shared :: any).Remotes) :: any
			local Constants = require((Shared :: any).Constants) :: any
			Remotes.FireServer(Constants.RemoteNames.RequestNotifOptInResult, result, if source == "settings" then "settings" else nil)
		end
		asking = false
	end)
end

return NotifOptIn
