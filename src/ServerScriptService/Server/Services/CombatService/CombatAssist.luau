--!strict
--[[ W2 Combat Core (contracts §1.3 step 3, mobile plan §4.1): server-side aim assist for hitscan shots.

	Runs only when the exact server ray did not decide the shot and the P0-7 claim did not confirm a target.
	CombatService offers every eligible candidate (alive player / live NPC record; it filters PvP, allies, spawn
	shields, the shooter's own vehicle and enclosed seats), this module keeps the ones inside the class cone, and
	Finish returns the one with the smallest sideways distance that has a clear line of sight. At most one target
	per shot. The client never names the target: TargetUserId / TargetNpcId are not read here.

	Per candidate (torso = UpperTorso / Torso / root):
	  v = torso - origin, along = dir . v, lateral = |v - dir * along|
	  along > 0 (NaN-safe), |v| <= maxRange (min(weapon Range, AimAssistConfig.MaxRangeStuds)),
	  along <= maxAlong (scenery hit distance + ClaimBeyondHitStuds, or the assist range),
	  lateral <= class LateralStuds, angle(dir, v) <= class MaxConeDeg,
	  CombatDamage.LineOfSight(origin, torso, shotFilter, candidate, false, LosPastTorsoStuds).

	No allocation per shot beyond the returned candidate: the pending list is reused. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local AimAssistConfig = require(Shared.Configs.AimAssistConfig)

local CombatDamage = require(script.Parent.CombatDamage)

local CombatAssist = {}

export type AssistClass = AimAssistConfig.AssistClass

export type Pick = {
	Model: Model,
	Torso: BasePart,
	Player: Player?,
	NpcId: string?,
	Lateral: number,
	Distance: number,
}

local MAX_PENDING = 8 -- geometric passes kept per shot (smallest lateral wins; LOS checked in that order)
local MAX_LOS_CHECKS = 3 -- line-of-sight rays per shot at most

-- cos(MaxConeDeg) per class name, computed once
local cosCache: { [string]: number } = {}

local function classOf(name: string?): (AssistClass, string)
	local classes = AimAssistConfig.Classes
	if typeof(name) == "string" then
		local c = classes[name]
		if c then
			return c, name
		end
	end
	local def = AimAssistConfig.DefaultClass
	return classes[def] or { LateralStuds = 1, MaxConeDeg = 1.5 }, def
end

local function coneCos(name: string, cls: AssistClass): number
	local c = cosCache[name]
	if c == nil then
		c = math.cos(math.rad(math.clamp(tonumber(cls.MaxConeDeg) or 0, 0, 89)))
		cosCache[name] = c
	end
	return c
end

--[[ Pure cone test for one torso position. `dir` must be a unit vector. Returns the lateral distance when every
	geometric rule holds (line of sight is not checked here), else nil and a short reason. ]]
function CombatAssist.Evaluate(
	origin: Vector3,
	dir: Vector3,
	torsoPos: Vector3,
	cls: AssistClass,
	maxRange: number,
	maxAlong: number,
	coneCosine: number?
): (number?, string)
	local v = torsoPos - origin
	local along = v:Dot(dir)
	if not (along > 0) then -- NaN-safe
		return nil, "behind the shot"
	end
	local dist = v.Magnitude
	if not (dist <= maxRange) then
		return nil, "out of range"
	end
	if not (along <= maxAlong) then
		return nil, "beyond what the shot hit"
	end
	local lateral = (v - dir * along).Magnitude
	if not (lateral <= cls.LateralStuds) then
		return nil, "off the ray"
	end
	local cosMin = coneCosine or math.cos(math.rad(cls.MaxConeDeg))
	if not (along / dist >= cosMin) then
		return nil, "outside the cone"
	end
	return lateral, "ok"
end

-- ── one shot: Begin → Offer × n → Finish ────────────────────────────────────────────────────────────────────
type Pending = { Model: Model?, Torso: BasePart?, Player: Player?, NpcId: string?, Lateral: number, Distance: number }

local pending: { Pending } = {}
for i = 1, MAX_PENDING do
	pending[i] = { Model = nil, Torso = nil, Player = nil, NpcId = nil, Lateral = 0, Distance = 0 }
end
local nPending = 0
local cur = {
	Origin = Vector3.zero,
	Dir = Vector3.new(0, 0, -1),
	Class = (nil :: any) :: AssistClass,
	ConeCos = 1,
	MaxRange = 0,
	MaxAlong = 0,
	Active = false,
}

-- The class actually used for `inputClass` (unknown names fall back to AimAssistConfig.DefaultClass)
function CombatAssist.ClassFor(inputClass: string?): (AssistClass, string)
	return classOf(inputClass)
end

function CombatAssist.Begin(origin: Vector3, dir: Vector3, inputClass: string?, maxRange: number, maxAlong: number)
	local cls, name = classOf(inputClass)
	cur.Origin = origin
	cur.Dir = dir
	cur.Class = cls
	cur.ConeCos = coneCos(name, cls)
	cur.MaxRange = maxRange
	cur.MaxAlong = maxAlong
	cur.Active = true
	nPending = 0
end

-- Cheap pre-check for the current shot (lets the caller skip its seat / clan lookups for far-off candidates)
function CombatAssist.InCone(torsoPos: Vector3): boolean
	if not cur.Active then
		return false
	end
	return CombatAssist.Evaluate(cur.Origin, cur.Dir, torsoPos, cur.Class, cur.MaxRange, cur.MaxAlong, cur.ConeCos) ~= nil
end

-- Offer one eligible candidate; kept only if it passes the cone (the worst pending entry is dropped when full).
function CombatAssist.Offer(model: Model, torso: BasePart, player: Player?, npcId: string?)
	if not cur.Active then
		return
	end
	local lateral = CombatAssist.Evaluate(cur.Origin, cur.Dir, torso.Position, cur.Class, cur.MaxRange, cur.MaxAlong, cur.ConeCos)
	if lateral == nil then
		return
	end
	local slot: Pending
	if nPending < MAX_PENDING then
		nPending += 1
		slot = pending[nPending]
	else
		local worst, worstI = -1, 0
		for i = 1, nPending do
			if pending[i].Lateral > worst then
				worst = pending[i].Lateral
				worstI = i
			end
		end
		if lateral >= worst then
			return
		end
		slot = pending[worstI]
	end
	slot.Model = model
	slot.Torso = torso
	slot.Player = player
	slot.NpcId = npcId
	slot.Lateral = lateral
	slot.Distance = (torso.Position - cur.Origin).Magnitude
end

--[[ The candidate with the smallest lateral that has a clear line of sight (at most MAX_LOS_CHECKS rays), or nil.
	`shotFilter` is the shot's Exclude list (shooter, their seated vehicle, the squad folder). ]]
function CombatAssist.Finish(shotFilter: { Instance }): Pick?
	cur.Active = false
	local checks = 0
	local result: Pick? = nil
	while nPending > 0 and checks < MAX_LOS_CHECKS do
		local bestI, bestL = 0, math.huge
		for i = 1, nPending do
			if pending[i].Lateral < bestL then
				bestL = pending[i].Lateral
				bestI = i
			end
		end
		local p = pending[bestI]
		-- remove it from the pending list (swap with the last entry)
		local model, torso = p.Model, p.Torso
		local player, npcId, lateral, dist = p.Player, p.NpcId, p.Lateral, p.Distance
		pending[bestI], pending[nPending] = pending[nPending], pending[bestI]
		nPending -= 1
		if model and torso then
			checks += 1
			if CombatDamage.LineOfSight(cur.Origin, torso.Position, shotFilter, model, false, AimAssistConfig.LosPastTorsoStuds) then
				result = { Model = model, Torso = torso, Player = player, NpcId = npcId, Lateral = lateral, Distance = dist }
				break
			end
		end
	end
	for i = 1, MAX_PENDING do -- never hold on to models between shots
		local p = pending[i]
		p.Model = nil
		p.Torso = nil
		p.Player = nil
		p.NpcId = nil
	end
	nPending = 0
	return result
end

return CombatAssist
