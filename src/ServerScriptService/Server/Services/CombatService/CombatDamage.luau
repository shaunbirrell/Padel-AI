--!strict
--[[ Raycast + damage math + creator tags for CombatService. ]]

local Workspace = game:GetService("Workspace")

local CombatDamage = {}

export type Bindings = {
	TerritoryService: any,
}

local B: Bindings = { TerritoryService = nil }

function CombatDamage.Bind(bindings: Bindings)
	B = bindings
end

function CombatDamage.Raycast(origin: Vector3, direction: Vector3, range: number, ignore: { Instance }): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	local unit = if direction.Magnitude > 1e-4 then direction.Unit else Vector3.new(0, 0, -1)
	return Workspace:Raycast(origin, unit * range, params)
end

--[[ Line of sight (same pattern as GateDefenseService.hasLos): a ray from `fromPos` to `toPos` that excludes
	`ignore`. With `target` nil, the target itself must be in `ignore` and any hit means blocked. With `target` set,
	the ray runs `pastStuds` beyond `toPos` and its FIRST hit must be part of `target` (nothing hit = no target
	there = blocked). Walls, terrain, vehicles, other players and NPCs all block; water never does. ]]
function CombatDamage.LineOfSight(
	fromPos: Vector3,
	toPos: Vector3,
	ignore: { Instance },
	target: Instance?,
	respectCanCollide: boolean?,
	pastStuds: number?
): boolean
	local delta = toPos - fromPos
	local len = delta.Magnitude
	if len < 1e-3 then
		return true
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	params.RespectCanCollide = respectCanCollide == true
	local reach = if target then len + math.max(0, pastStuds or 0) else len
	local hit = Workspace:Raycast(fromPos, delta.Unit * reach, params)
	if target == nil then
		return hit == nil
	end
	if hit == nil then
		return false
	end
	return hit.Instance == target or hit.Instance:IsDescendantOf(target)
end

-- P1-4: `unitShot` marks a hit landed by the attacker's squad unit (CombatService pays those kills a share)
function CombatDamage.TagCreator(humanoid: Humanoid, attacker: Player, unitShot: boolean?)
	local existing = humanoid:FindFirstChild("creator")
	if existing then
		existing:Destroy()
	end
	local tag = Instance.new("ObjectValue")
	tag.Name = "creator"
	tag.Value = attacker
	if unitShot then
		tag:SetAttribute("WE_UnitShot", true)
	end
	tag.Parent = humanoid
	task.delay(2, function()
		if tag.Parent then
			tag:Destroy()
		end
	end)
end

function CombatDamage.DamageFor(def: any, attacker: Player?): number
	local base = def.Damage * (def.Pellets or 1)
	if attacker and B.TerritoryService and B.TerritoryService.GetDamageMult then
		base = base * B.TerritoryService.GetDamageMult(attacker)
	end
	return base
end

return CombatDamage
