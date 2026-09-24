--!strict
--[[
	v69 Research Lab upgrades (soldiers, weapons, vehicles, defenses). Stub: the real service replaces this
	file but must keep GetBonus.
	Remotes: RequestResearch (client → server), ResearchStateUpdate (server → client).

	Contract used by other services (safe to call before/without research):
	  ResearchService.GetBonus(player, statId) -> multiplier (1 = no bonus)
	  statId ∈ WeaponDamage, WeaponFireRate, WeaponMagazine, WeaponReload, SoldierHealth, SoldierDamage,
	           VehicleSpeed, VehicleArmor, TurretDamage
]]

local ResearchService = {}

function ResearchService.GetBonus(_player: Player, _statId: string): number
	return 1
end

function ResearchService.Init(_deps: { [string]: any })
	print("[WAR EMPIRE] ResearchService stub (no upgrades yet)")
end

return ResearchService
