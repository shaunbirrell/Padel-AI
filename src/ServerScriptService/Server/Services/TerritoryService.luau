--!strict
--[[ STUB — Territory capture / bonuses. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage:WaitForChild("Shared").Constants)

local TerritoryService = {}

local DataService: any = nil
local RateLimitService: any = nil
local RemoteSetup: any = nil

-- territoryId -> userId
local controllers: { [string]: number } = {}

function TerritoryService.Init(deps: { [string]: any })
	DataService = deps.DataService
	RateLimitService = deps.RateLimitService
	RemoteSetup = deps.RemoteSetup

	local remote = RemoteSetup.Get(Constants.RemoteNames.RequestCaptureTerritory) :: RemoteEvent
	remote.OnServerEvent:Connect(function(player: Player, territoryId: any)
		if not RateLimitService.Allow(player, "capture_territory", 1, 2) then
			return
		end
		TerritoryService.BeginCapture(player, territoryId)
	end)
end

function TerritoryService.BeginCapture(_player: Player, _territoryId: any): (boolean, string?)
	-- TODO: proximity check, capture channel, award control
	return false, "NotImplemented"
end

function TerritoryService.GetController(territoryId: string): number?
	return controllers[territoryId]
end

function TerritoryService.GetBonusesForPlayer(player: Player): { [string]: number }
	-- TODO: aggregate TerritoryConfig bonuses for controlled territories
	return {}
end

return TerritoryService
