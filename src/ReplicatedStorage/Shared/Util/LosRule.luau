--!strict
--[[
	claude-bud JOB 32 (2026-09-30): the ONE line-of-sight / shot rule (CombatConfig.LineOfSight). Every shooter uses it:
	  * player guns (CombatDamage.Raycast / LineOfSight, aim assist, the lag-tolerance claim, splash);
	  * projectiles and vehicle guns;
	  * NPCs, the army, base turrets and gate / base guards;
	  * the client's shot preview.
	THE RULE: a solid part (CanCollide) stops a shot and blocks sight; a non-colliding part (decor, zones, prompt hosts,
	window gaps) never does; water never does. A shot (a HIT ray) can also stop on any part of a character, since that
	is what it is aiming at (R15 limbs do not collide).
	So a shot through a window gap or from a roof works, and nothing goes through a wall.
	  * SightRespect(legacy) -> the RespectCanCollide a SIGHT ray uses: always true while the rule is on (the NPC /
	    army / turret checks did this already, now nobody can turn it off per shooter). legacy is used when it is off.
	  * HitCast(origin, dir, params) -> the first hit a SHOT stops on. It casts with RespectCanCollide off (so limbs are
	    hittable) and steps over non-colliding, non-character parts (at most MaxSkips re-casts, on a copy of params:
	    the caller's params are never grown).
	Kill switch: CombatConfig.LineOfSight.Unified = false (every call site behaves exactly as before).
]]

local Workspace = game:GetService("Workspace")

local LosRule = {}

local cfgCache: any = nil
local function cfg(): any
	if cfgCache == nil then
		local ok, c = pcall(function(): any
			return require(script.Parent.Parent.Configs.CombatConfig)
		end)
		cfgCache = if ok and typeof(c) == "table" and typeof(c.LineOfSight) == "table" then c.LineOfSight else { Unified = false }
	end
	return cfgCache
end

function LosRule.Unified(): boolean
	return cfg().Unified == true
end

function LosRule.SightRespect(legacy: boolean): boolean
	if LosRule.Unified() then
		return true
	end
	return legacy == true
end

-- a part of a character (a Model holding a Humanoid), or of one of its accessories
function LosRule.IsCharacterPart(p: Instance): boolean
	local m = p.Parent
	for _ = 1, 3 do
		if m == nil then
			return false
		end
		if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") then
			return true
		end
		m = m.Parent
	end
	return false
end

local function copyParams(src: RaycastParams): RaycastParams
	local p = RaycastParams.new()
	p.FilterType = src.FilterType
	p.FilterDescendantsInstances = src.FilterDescendantsInstances
	p.IgnoreWater = src.IgnoreWater
	p.CollisionGroup = src.CollisionGroup
	p.RespectCanCollide = false
	return p
end

function LosRule.HitCast(origin: Vector3, dir: Vector3, params: RaycastParams): RaycastResult?
	if not LosRule.Unified() then
		return Workspace:Raycast(origin, dir, params)
	end
	local p = params
	if p.RespectCanCollide then
		p = copyParams(params)
	end
	local maxSkips = math.clamp(tonumber(cfg().MaxSkips) or 6, 1, 12)
	for _ = 1, maxSkips do
		local r = Workspace:Raycast(origin, dir, p)
		if r == nil then
			return nil
		end
		local inst = r.Instance
		if (inst:IsA("BasePart") and inst.CanCollide) or inst:IsA("Terrain") or LosRule.IsCharacterPart(inst) then
			return r
		end
		-- see-through (non-colliding, not a character): step over it on a private copy
		if p == params then
			p = copyParams(params)
		end
		p:AddToFilter(inst)
	end
	return nil
end

return LosRule
