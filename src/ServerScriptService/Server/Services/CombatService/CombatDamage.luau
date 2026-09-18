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

function CombatDamage.TagCreator(humanoid: Humanoid, attacker: Player)
	local existing = humanoid:FindFirstChild("creator")
	if existing then
		existing:Destroy()
	end
	local tag = Instance.new("ObjectValue")
	tag.Name = "creator"
	tag.Value = attacker
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
