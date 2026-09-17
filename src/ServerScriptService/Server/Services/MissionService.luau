--!strict
--[[ STUB — Missions. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage:WaitForChild("Shared").Constants)

local MissionService = {}

local DataService: any = nil
local EconomyService: any = nil
local XPService: any = nil
local RateLimitService: any = nil
local RemoteSetup: any = nil

function MissionService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	XPService = deps.XPService
	RateLimitService = deps.RateLimitService
	RemoteSetup = deps.RemoteSetup

	local remote = RemoteSetup.Get(Constants.RemoteNames.RequestStartMission) :: RemoteEvent
	remote.OnServerEvent:Connect(function(player: Player, missionId: any)
		if not RateLimitService.Allow(player, "start_mission", 1, 2) then
			return
		end
		MissionService.Start(player, missionId)
	end)
end

function MissionService.Start(_player: Player, _missionId: any): (boolean, string?)
	-- TODO: validate level, start timer / objectives, grant rewards on complete
	return false, "NotImplemented"
end

function MissionService.Complete(player: Player, missionId: string)
	-- TODO: use MissionConfig rewards via EconomyService / XPService
end

return MissionService
