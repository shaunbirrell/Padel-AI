--!strict
--[[
	claude-bud JOB 43 (2026-10-01, Shaun's phone test: "my soldiers only shoot the enemy PLAYER; they ignore his soldiers
	and once he dies the fight stops"). ROOT CAUSE (static trace, pinned in tools/checks/claude_bud_job43.py):
	  * SquadOrdersService.nearestHostile scans CombatService NPCs only and SKIPS every model with an OwnerUserId
	    attribute: army soldiers carry OwnerUserId, so an enemy soldier is never a candidate;
	  * pickSquadTarget (ATTACK / SEND) adds NPCs + enemy PLAYERS + base guards; pickDefendTarget (FOLLOW / HOLD) adds
	    enemy PLAYERS only. Nothing ever adds an enemy soldier, so the candidate list empties when the player dies.
	FIX (ArmyConfig.ArmyBrawl, owner-first by the SHOOTING army's owner): enemy soldiers become candidates of their own
	("Unit"), under THE shared army rule (CombatService.ArmyHostility: PvP on, not self, not a clan ally, not novice /
	new-player protected) re-checked on every shot by CombatService.ApplyUnitUnitHit. Players still come first; the fight
	goes on against the soldiers after the player dies, until one side is wiped or out of reach. Real shots only (the
	squad's own LOS, hit chance and fire rate); nothing teleports or snaps.
	This module is pure (tests call it): the enemy-soldier candidates around a point, nearest first.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArmyBrawl = {}

local function cfg(): any
	local okA, AC = pcall(function(): any
		return require(ReplicatedStorage:WaitForChild("Shared", 10).Configs.ArmyConfig)
	end)
	return if okA and AC then AC.ArmyBrawl else nil
end

function ArmyBrawl.Config(): any
	return cfg()
end

-- owner-first by the shooting army's owner (RetentionConfig.Live: Enabled + OwnerFirst)
function ArmyBrawl.LiveFor(userId: any): boolean
	local b = cfg()
	if typeof(b) ~= "table" then
		return false
	end
	local okR, RC = pcall(function(): any
		return require(ReplicatedStorage:WaitForChild("Shared", 10).Configs.RetentionConfig)
	end)
	return okR and RC ~= nil and RC.Live(b, userId) == true
end

export type Cand = { Hum: Humanoid, Root: BasePart, Model: Instance, Owner: Player, Dist: number }

--[[ The live enemy soldiers within `reach` (flat) of `centre`, nearest first, at most `cap`. squads = { [ownerUserId] =
	{ Units = { { Alive, Humanoid, Root, Model } } } } (SquadOrdersService's table); hostile(attacker, owner) -> (ok, why)
	is THE shared rule (CombatService.ArmyHostility). A squad whose owner is not in the server is skipped. ]]
function ArmyBrawl.Candidates(attacker: Player, squads: { [number]: any }, centre: Vector3, reach: number, hostile: (Player, Player) -> (boolean, string), cap: number?): { Cand }
	local out: { Cand } = {}
	for uid, st in pairs(squads) do
		if uid ~= attacker.UserId and typeof(st) == "table" and typeof(st.Units) == "table" then
			local owner = Players:GetPlayerByUserId(uid)
			if owner then
				local okH, may = pcall(function(): boolean
					local m = hostile(attacker, owner)
					return m == true
				end)
				if okH and may == true then
					for _, u in ipairs(st.Units) do
						local hum, root = u.Humanoid, u.Root
						if u.Alive and hum and root and root.Parent ~= nil and hum.Health > 0 then
							local p = root.Position
							local d = Vector3.new(p.X - centre.X, 0, p.Z - centre.Z).Magnitude
							if d <= reach then
								table.insert(out, { Hum = hum, Root = root, Model = u.Model, Owner = owner, Dist = d })
							end
						end
					end
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.Dist < b.Dist
	end)
	local n = math.max(0, math.floor(tonumber(cap) or #out))
	while #out > n do
		table.remove(out)
	end
	return out
end

return ArmyBrawl
