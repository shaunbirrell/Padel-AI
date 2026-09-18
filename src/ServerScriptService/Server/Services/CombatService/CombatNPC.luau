--!strict
--[[ NPC spawn gathering, nearest-player, think loop — used by CombatService façade. ]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedRoot = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(SharedRoot.Constants)
local CombatConfig = require(SharedRoot.Configs.CombatConfig)

local CombatNPC = {}

export type Bindings = {
	npcRecords: { [string]: any },
	combatStates: { [number]: any },
	clock: () -> number,
	characterParts: (Player) -> (Model?, Humanoid?, BasePart?),
	hitFeedback: (Player, any) -> (),
	pushState: (Player) -> (),
	spawnNPC: (string?, CFrame) -> any,
	getTagged: (string) -> { Instance },
}

local B: Bindings

function CombatNPC.Bind(bindings: Bindings)
	B = bindings
end

function CombatNPC.AliveCount(): number
	local n = 0
	for _, rec in pairs(B.npcRecords) do
		if rec.Alive then
			n += 1
		end
	end
	return n
end

function CombatNPC.Destroy(rec: any)
	rec.Alive = false
	B.npcRecords[rec.Id] = nil
	if rec.Model and rec.Model.Parent then
		rec.Model:Destroy()
	end
end

function CombatNPC.NearestPlayer(position: Vector3, maxRange: number): (Player?, number)
	local best: Player? = nil
	local bestDistSq = maxRange * maxRange
	for _, player in ipairs(Players:GetPlayers()) do
		local _, hum, root = B.characterParts(player)
		if hum and root and hum.Health > 0 then
			local delta = root.Position - position
			local dSq = delta.X * delta.X + delta.Y * delta.Y + delta.Z * delta.Z
			if dSq < bestDistSq then
				bestDistSq = dSq
				best = player
			end
		end
	end
	return best, math.sqrt(bestDistSq)
end

function CombatNPC.Think()
	if next(B.npcRecords) == nil then
		return
	end
	local now = B.clock()
	for _, rec in pairs(B.npcRecords) do
		if rec.Alive and rec.Humanoid.Health > 0 and rec.Root.Parent then
			local target, dist = CombatNPC.NearestPlayer(rec.Root.Position, rec.Def.AggroRange)
			if target then
				local _, th, troot = B.characterParts(target)
				if th and troot then
					local look = CFrame.lookAt(
						rec.Root.Position,
						Vector3.new(troot.Position.X, rec.Root.Position.Y, troot.Position.Z)
					)
					rec.Root.CFrame = look
					local gyro = rec.Root:FindFirstChildOfClass("BodyGyro")
					if gyro then
						gyro.CFrame = look
					end
					if dist > rec.Def.Range * 0.85 then
						rec.Humanoid:MoveTo(troot.Position)
					else
						rec.Humanoid:MoveTo(rec.Root.Position)
						local interval = 1 / math.max(rec.Def.FireRate, 0.1)
						if now - rec.LastFireAt >= interval and dist <= rec.Def.Range then
							rec.LastFireAt = now
							local tState = B.combatStates[target.UserId]
							if not (tState and now < tState.InvulnerableUntil) then
								th:TakeDamage(rec.Def.Damage)
								B.hitFeedback(target, {
									Kind = if th.Health <= 0 then "Death" else "Damaged",
									Damage = rec.Def.Damage,
									TargetName = rec.Def.DisplayName,
								})
								B.pushState(target)
							end
						end
					end
				end
			end
		end
	end
end

function CombatNPC.GatherSpawns(): { CFrame }
	local list: { CFrame } = {}
	for _, inst in ipairs(B.getTagged(Constants.Tags.NPCSpawn)) do
		if inst:IsA("BasePart") then
			table.insert(list, inst.CFrame + Vector3.new(0, 3, 0))
		end
	end
	if CombatConfig.NPCAlsoSpawnNearTerritories then
		local added = 0
		local maxNear = CombatConfig.MaxTerritoryNPCSpawns or 8
		for _, inst in ipairs(B.getTagged(Constants.Tags.Territory)) do
			if inst:IsA("BasePart") and added < maxNear then
				local offset = Vector3.new(math.random(-20, 20), 3, math.random(-20, 20))
				table.insert(list, inst.CFrame + offset)
				added += 1
			end
		end
	end
	if #list == 0 then
		for i = 1, 6 do
			local angle = (i / 6) * math.pi * 2
			table.insert(list, CFrame.new(100 + math.cos(angle) * 60, 4, 100 + math.sin(angle) * 60))
		end
	end
	return list
end

function CombatNPC.Bootstrap()
	local points = CombatNPC.GatherSpawns()
	local types = { "Infantry", "Infantry", "HeavyInfantry" }
	local spawned = 0
	for i, cf in ipairs(points) do
		if spawned >= CombatConfig.MaxActiveNPCs then
			break
		end
		local typeId = types[((i - 1) % #types) + 1]
		if B.spawnNPC(typeId, cf) then
			spawned += 1
		end
	end
	if RunService:IsStudio() then
		print(string.format("[CombatService] Spawned %d NPCs (cap %d)", spawned, CombatConfig.MaxActiveNPCs))
	end
	return spawned
end

return CombatNPC
