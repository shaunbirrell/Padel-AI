--!strict
--[[
	claude-bud JOB 51 (2026-10-01, P0 "the Central Plaza guards don't shoot my girlfriend / she can't damage them"):
	THE one shared hostility / protection rule. CombatService binds the existing reasons into it (the F6 novice shield,
	the spawn shield, pvpBlock, UnitMayHitPlayer) and exposes it as CombatService.ProtectedReason / NpcMayTarget /
	MayHurt; CombatNPC calls NpcMayTarget in EVERY NPC target pick; CheckpointGuardService.Protected calls
	ProtectedReason. No second copy of any reason lives here: every answer comes from a bound function.
	Gate: CombatConfig.SharedHostility (RetentionConfig.Live, by the CANDIDATE player); OFF == the old pick exactly.
]]

local Hostility = {}

export type Deps = {
	IsNoviceShielded: (Player) -> boolean,
	IsSpawnInvulnerable: (Player) -> boolean,
	PvPBlock: (Player, Player) -> string?,
	UnitMayHitPlayer: (Player, Player) -> (boolean, string?),
	Live: (Player) -> boolean, -- SharedHostility live for this player
}

local deps: Deps? = nil

function Hostility.Bind(d: Deps)
	deps = d
end

-- why nobody may hurt this player right now ("novice" | "spawn"), or nil
function Hostility.ProtectedReason(player: Player): string?
	local d = deps
	if d == nil then
		return nil
	end
	if d.IsNoviceShielded(player) then
		return "novice"
	end
	if d.IsSpawnInvulnerable(player) then
		return "spawn"
	end
	return nil
end

-- may a CombatService NPC (any group) TARGET this player? Live: never a protected one (so the NPC picks the nearest
-- player it may actually hurt, instead of firing guaranteed misses at a shielded one). OFF: true (the old pick).
function Hostility.NpcMayTarget(player: Player): (boolean, string?)
	local d = deps
	if d == nil or not d.Live(player) then
		return true, nil
	end
	local why = Hostility.ProtectedReason(player)
	return why == nil, why
end

--[[ May `attacker` hurt the player `victim`? One answer for every shooter kind:
	"Player" (guns) / "Vehicle" (a player's vehicle weapon) -> PvPBlock; "Unit" / "Turret" / "BaseGuard" (owned by
	`attacker`) -> UnitMayHitPlayer; "NPC" (attacker = the NPC record or nil) -> NpcMayTarget. ]]
function Hostility.MayHurt(attacker: any, victim: Player, kind: string): (boolean, string?)
	local d = deps
	if d == nil then
		return true, nil
	end
	if kind == "NPC" then
		return Hostility.NpcMayTarget(victim)
	elseif kind == "Unit" or kind == "Turret" or kind == "BaseGuard" then
		return d.UnitMayHitPlayer(attacker, victim)
	end
	local why = d.PvPBlock(attacker, victim)
	return why == nil, why
end

return Hostility
