--!strict
--[[ STUB — Prestige reset. ]]

local PrestigeService = {}

local DataService: any = nil
local EconomyService: any = nil

function PrestigeService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
end

function PrestigeService.CanPrestige(player: Player): boolean
	local PrestigeConfig = require(game:GetService("ReplicatedStorage").Shared.Configs.PrestigeConfig)
	local profile = DataService.GetProfile(player)
	if not profile then
		return false
	end
	return profile.Level >= PrestigeConfig.MinLevelToPrestige and profile.Prestige < PrestigeConfig.MaxPrestige
end

function PrestigeService.DoPrestige(_player: Player): (boolean, string?)
	-- TODO: reset per PrestigeConfig, grant gold bonus
	return false, "NotImplemented"
end

return PrestigeService
