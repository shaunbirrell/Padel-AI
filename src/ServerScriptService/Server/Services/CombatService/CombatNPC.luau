--!strict
--[[ NPC spawn gathering, nearest-player, think loop — used by CombatService façade.
	P1-2 (mobile plan): an NPC shot needs line of sight (CombatDamage.LineOfSight, the GateDefenseService.hasLos
	pattern), waits CombatFairnessConfig.NpcReactionSeconds after acquiring a target, and hits with a chance that
	falls with distance and against fast-moving targets. All numbers live in CombatFairnessConfig. ]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedRoot = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(SharedRoot.Constants)
local CombatConfig = require(SharedRoot.Configs.CombatConfig)
local CombatFairnessConfig = require(SharedRoot.Configs.CombatFairnessConfig)

local CombatDamage = require(script.Parent.CombatDamage)

local CombatNPC = {}

local rng = Random.new()
-- per-player horizontal speed, sampled from server positions once per Think (P1-2 moving-target penalty)
local samplePos: { [number]: Vector3 } = {}
local sampleAt: { [number]: number } = {}
local speedOf: { [number]: number } = {}

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

-- Tests seed the hit roll; production uses an unseeded Random
function CombatNPC.SetRandom(seedOrRandom: any)
	if typeof(seedOrRandom) == "Random" then
		rng = seedOrRandom
	elseif typeof(seedOrRandom) == "number" then
		rng = Random.new(seedOrRandom)
	else
		rng = Random.new()
	end
end

function CombatNPC.ForgetPlayer(userId: number)
	samplePos[userId] = nil
	sampleAt[userId] = nil
	speedOf[userId] = nil
end

function CombatNPC.TargetSpeed(player: Player): number
	return speedOf[player.UserId] or 0
end

--[[ Hit chance of one NPC shot: NpcNearHitChance at <= NpcNearStuds, falling linearly to NpcFarHitChance at the
	type's max range; minus NpcFastTargetPenalty against a target faster than NpcFastTargetSpeed studs/s. ]]
function CombatNPC.HitChance(dist: number, maxRange: number, targetSpeed: number): number
	local C = CombatFairnessConfig
	local nearD = C.NpcNearStuds
	local chance: number
	if dist <= nearD or maxRange <= nearD then
		chance = C.NpcNearHitChance
	else
		local t = math.clamp((dist - nearD) / (maxRange - nearD), 0, 1)
		chance = C.NpcNearHitChance + (C.NpcFarHitChance - C.NpcNearHitChance) * t
	end
	if targetSpeed > C.NpcFastTargetSpeed then
		chance -= C.NpcFastTargetPenalty
	end
	return math.clamp(chance, C.NpcMinHitChance, 1)
end

local function sampleSpeeds(now: number)
	for _, player in ipairs(Players:GetPlayers()) do
		local _, hum, root = B.characterParts(player)
		local uid = player.UserId
		if hum and root and hum.Health > 0 then
			local pos = root.Position
			local prev = samplePos[uid]
			local prevAt = sampleAt[uid]
			if prev and prevAt and now - prevAt > 1e-3 then
				local dx, dz = pos.X - prev.X, pos.Z - prev.Z
				speedOf[uid] = math.sqrt(dx * dx + dz * dz) / (now - prevAt)
			else
				speedOf[uid] = 0
			end
			samplePos[uid] = pos
			sampleAt[uid] = now
		else
			CombatNPC.ForgetPlayer(uid)
		end
	end
end

-- The vehicle model (VehicleService tags it with a VehicleId attribute) around a seat, or nil
local function vehicleOf(seat: Instance?): Instance?
	local cur = if seat then seat.Parent else nil
	while cur and cur ~= Workspace do
		if cur:IsA("Model") and cur:GetAttribute("VehicleId") ~= nil then
			return cur
		end
		cur = cur.Parent
	end
	return nil
end

-- Clear shot from the NPC's eyes to the target's root (the NPC and the target's own character never block)
local function npcHasLos(rec: any, target: Player, th: Humanoid, troot: BasePart): boolean
	if not CombatFairnessConfig.NpcRequireLos then
		return true
	end
	local ignore: { Instance } = { rec.Model }
	local character = target.Character
	if character then
		table.insert(ignore, character)
	end
	if CombatFairnessConfig.NpcIgnoreTargetVehicle then
		-- until vehicles take NPC damage (money plan M4), the vehicle a target sits in is not a free shield
		local vehicle = vehicleOf(th.SeatPart)
		if vehicle then
			table.insert(ignore, vehicle)
		end
	end
	local eye = rec.Root.Position + Vector3.new(0, CombatFairnessConfig.NpcEyeHeight, 0)
	return CombatDamage.LineOfSight(eye, troot.Position, ignore, nil, CombatFairnessConfig.NpcLosRespectCanCollide)
end

function CombatNPC.Think()
	if next(B.npcRecords) == nil then
		return
	end
	local now = B.clock()
	sampleSpeeds(now)
	local C = CombatFairnessConfig
	for _, rec in pairs(B.npcRecords) do
		if rec.Alive and rec.Humanoid.Health > 0 and rec.Root.Parent then
			local target, dist = CombatNPC.NearestPlayer(rec.Root.Position, rec.Def.AggroRange)
			if target ~= rec.AimTarget then
				-- P1-2: a new (or lost) target restarts the reaction delay
				rec.AimTarget = target
				rec.AimSince = now
				rec.AimBlocked = false
			end
			if target then
				local _, th, troot = B.characterParts(target)
				if th and troot then
					-- Face via yaw gyro only — never set Root.CFrame (fights MoveTo physics)
					local look = CFrame.lookAt(
						rec.Root.Position,
						Vector3.new(troot.Position.X, rec.Root.Position.Y, troot.Position.Z)
					)
					local gyro = rec.Root:FindFirstChild("NPCFaceGyro") or rec.Root:FindFirstChildOfClass("BodyGyro")
					if gyro and gyro:IsA("BodyGyro") then
						gyro.CFrame = look
					end
					if dist > rec.Def.Range * 0.85 then
						rec.Humanoid:MoveTo(troot.Position)
					elseif not npcHasLos(rec, target, th, troot) then
						-- P1-2: walls, terrain, parked vehicles and other players give cover (not the seat you sit in)
						if C.NpcChaseWithoutLos then
							rec.Humanoid:MoveTo(troot.Position)
						else
							rec.Humanoid:MoveTo(rec.Root.Position)
						end
						if C.NpcReactionOnLosRegain then
							rec.AimBlocked = true
						end
					else
						if rec.AimBlocked then
							-- sight regained this tick: the reaction delay starts now (peeking from cover is fair)
							rec.AimBlocked = false
							rec.AimSince = now
						end
						rec.Humanoid:MoveTo(rec.Root.Position)
						local interval = 1 / math.max(rec.Def.FireRate, 0.1)
						local aimed = now - (rec.AimSince or now) >= C.NpcReactionSeconds
						if aimed and now - rec.LastFireAt >= interval and dist <= rec.Def.Range then
							rec.LastFireAt = now
							local tState = B.combatStates[target.UserId]
							local chance = CombatNPC.HitChance(dist, rec.Def.Range, speedOf[target.UserId] or 0)
							if not (tState and now < tState.InvulnerableUntil) and rng:NextNumber() < chance then
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
