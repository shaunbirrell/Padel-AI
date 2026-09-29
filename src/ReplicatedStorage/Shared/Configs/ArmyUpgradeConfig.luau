--!strict
--[[
	claude-bud JOB 4.4 (2026-09-29): army upgrades at the Barracks. Soldier HP / damage upgrades already exist as the
	Research "Soldiers" track (Body Armor = SoldierHealth, Marksman Training = SoldierDamage: cash, saved per player in
	the profile's research levels, applied by SquadOrdersService). A second, parallel upgrade would stack power, so this
	adds the missing SHOP: a prompt at the player's own Barracks ("Army Upgrades") that opens that track. Buying stays
	ResearchService.Purchase (server: price, cash, max level, save). The server tells only players it is live for
	where their Barracks prompt goes (FeaturePush "ArmyUpgrades"); the prompt is local to them.
	Rollout "owner" = AdminConfig.IsPlaytestOwner only, "all", anything else = off (Research Lab only, as before).
]]

local AdminConfig = require(script.Parent.AdminConfig)

local ArmyUpgradeConfig = {
	Rollout = "owner",
	Track = "Soldiers",
	-- plot-local spot (BaseLayoutConfig frame): in front of the Barracks (Site -110, 110, Yaw 90), toward the plot centre
	PromptX = -88,
	PromptZ = 110,
	PromptY = 3,
	MaxActivationDistance = 14,
}

function ArmyUpgradeConfig.LiveFor(userId: any): boolean
	local mode = ArmyUpgradeConfig.Rollout
	if mode == "all" then
		return true
	elseif mode == "owner" then
		return AdminConfig.IsPlaytestOwner(userId)
	end
	return false
end

return ArmyUpgradeConfig
