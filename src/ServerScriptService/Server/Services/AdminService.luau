--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AdminConfig = require(ReplicatedStorage:WaitForChild("Shared").Configs.AdminConfig)
local Constants = require(ReplicatedStorage:WaitForChild("Shared").Constants)

local AdminService = {}

local EconomyService: any = nil
local XPService: any = nil
local DataService: any = nil
local AnalyticsService: any = nil
local RateLimitService: any = nil

function AdminService.IsAdmin(player: Player): boolean
	for _, id in ipairs(AdminConfig.UserIds) do
		if id == player.UserId then
			return true
		end
	end
	return false
end

function AdminService.Init(deps: { [string]: any })
	EconomyService = deps.EconomyService
	XPService = deps.XPService
	DataService = deps.DataService
	AnalyticsService = deps.AnalyticsService
	RateLimitService = deps.RateLimitService

	local RemoteSetup = deps.RemoteSetup
	local remote = RemoteSetup.Get(Constants.RemoteNames.RequestAdminCommand) :: RemoteEvent

	remote.OnServerEvent:Connect(function(player: Player, command: any, arg1: any, arg2: any)
		if not RateLimitService.Allow(player, "admin", 2, 4) then
			return
		end
		if not AdminService.IsAdmin(player) then
			warn("[AdminService] Unauthorized admin attempt:", player.UserId)
			return
		end
		if typeof(command) ~= "string" then
			return
		end

		local cmd = string.lower(command)
		AnalyticsService.Log("ADMIN_COMMAND", player.UserId, { command = cmd })

		if cmd == "givecash" and typeof(arg1) == "number" then
			EconomyService.AddCash(player, math.floor(arg1), "admin")
		elseif cmd == "givegold" and typeof(arg1) == "number" then
			EconomyService.AddGold(player, math.floor(arg1), "admin")
		elseif cmd == "givexp" and typeof(arg1) == "number" then
			XPService.AddXP(player, math.floor(arg1), "admin")
		elseif cmd == "setlevel" and typeof(arg1) == "number" then
			XPService.SetLevel(player, math.floor(arg1))
		elseif cmd == "unlockall" then
			local profile = DataService.GetProfile(player)
			if profile then
				local VehicleConfig = require(ReplicatedStorage.Shared.Configs.VehicleConfig)
				local WeaponConfig = require(ReplicatedStorage.Shared.Configs.WeaponConfig)
				for id in pairs(VehicleConfig.Vehicles) do
					profile.Vehicles[id] = true
				end
				for id in pairs(WeaponConfig.Weapons) do
					profile.Weapons[id] = true
				end
				DataService.MarkDirty(player)
			end
		elseif cmd == "resetbase" then
			local profile = DataService.GetProfile(player)
			if profile then
				for id in pairs(profile.BaseUpgrades) do
					profile.BaseUpgrades[id] = 0
				end
				DataService.MarkDirty(player)
				if deps.BaseService then
					deps.BaseService.PushState(player)
				end
			end
		end
	end)
end

return AdminService
