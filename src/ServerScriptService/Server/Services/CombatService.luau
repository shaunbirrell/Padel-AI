--!strict
--[[ STUB — Phase 3 Combat. Public API reserved. ]]

local CombatService = {}

function CombatService.Init(_deps: { [string]: any })
	-- TODO: weapon fire validation, damage application, hit registration
end

function CombatService.ApplyDamage(_attacker: Player, _target: Humanoid, _weaponId: string, _amount: number)
	-- TODO: server-authoritative damage
end

function CombatService.RegisterKill(_attacker: Player, _victim: Player)
	-- TODO: stats + XP reward
end

return CombatService
