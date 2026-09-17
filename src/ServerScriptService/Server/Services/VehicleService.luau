--!strict
--[[ STUB — Vehicle spawn/ownership. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage:WaitForChild("Shared").Constants)

local VehicleService = {}

local DataService: any = nil
local RateLimitService: any = nil
local RemoteSetup: any = nil

function VehicleService.Init(deps: { [string]: any })
	DataService = deps.DataService
	RateLimitService = deps.RateLimitService
	RemoteSetup = deps.RemoteSetup

	local remote = RemoteSetup.Get(Constants.RemoteNames.RequestSpawnVehicle) :: RemoteEvent
	remote.OnServerEvent:Connect(function(player: Player, vehicleId: any)
		if not RateLimitService.Allow(player, "spawn_vehicle", 1, 2) then
			return
		end
		VehicleService.RequestSpawn(player, vehicleId)
	end)
end

function VehicleService.Owns(player: Player, vehicleId: string): boolean
	local profile = DataService.GetProfile(player)
	return profile ~= nil and profile.Vehicles[vehicleId] == true
end

function VehicleService.RequestSpawn(player: Player, vehicleId: any): (boolean, string?)
	if typeof(vehicleId) ~= "string" then
		return false, "InvalidId"
	end
	if not VehicleService.Owns(player, vehicleId) then
		return false, "NotOwned"
	end
	-- TODO: clone vehicle model near plot / spawn pad
	return true, nil
end

function VehicleService.GrantVehicle(player: Player, vehicleId: string)
	local profile = DataService.GetProfile(player)
	if profile then
		profile.Vehicles[vehicleId] = true
		DataService.MarkDirty(player)
	end
end

return VehicleService
