--!strict
--[[
	claude-bud JOB 4.3 (2026-09-29): plaza bounty. When someone captures the Central Plaza, every OTHER player the
	feature is live for gets a timed bounty: retake the plaza within WindowSeconds for Cash (server-side, paid by
	Server/Modules/PlazaBounty from TerritoryService's capture). Anti-farm: the retaker must not be the bounty's holder,
	each player earns at most once per EarnCooldownSeconds, and a capture of the plaza starts a new bounty only after
	the previous one ended. The plaza gets the objective marker ("BOUNTY") for the window.
	Rollout "owner" = AdminConfig.IsPlaytestOwner only (the owner is offered and can earn it), "all", anything else =
	off (no bounty: the game as before).
]]

local AdminConfig = require(script.Parent.AdminConfig)

local PlazaBountyConfig = {
	Rollout = "all", -- v101
	ZoneId = "CentralPlaza",
	WindowSeconds = 180,
	Cash = 15000,
	EarnCooldownSeconds = 600,
}

function PlazaBountyConfig.LiveFor(userId: any): boolean
	if (require(script.Parent.MonetizationConfig) :: any).Launched("PlazaBounty") then
		return true -- claude-bud JOB 12: MonetizationConfig.LaunchAll
	end
	local mode = PlazaBountyConfig.Rollout
	if mode == "all" then
		return true
	elseif mode == "owner" then
		return AdminConfig.IsPlaytestOwner(userId)
	end
	return false
end

return PlazaBountyConfig
