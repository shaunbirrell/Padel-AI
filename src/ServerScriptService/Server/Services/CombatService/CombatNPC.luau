--!strict
--[[ NPC spawn gathering, nearest-player, think loop — used by CombatService façade.
	P1-2 (mobile plan): an NPC shot needs line of sight (CombatDamage.LineOfSight, the GateDefenseService.hasLos
	pattern), waits CombatFairnessConfig.NpcReactionSeconds after acquiring a target, and hits with a chance that
	falls with distance and against fast-moving targets. All numbers live in CombatFairnessConfig.
	W2 Combat Core (contracts §2.2, §3.8): every NPC shot sends one WeaponFx bullet event through the optional `fx`
	binding (a miss lands 2–4 studs beside the target), and a hit on a player sitting in an ENCLOSED seat
	(WE_Exposed == false) of a live registered vehicle damages the vehicle instead (VehicleHealth, class "NPC").
	W3 step 2 Phase B, lane N (contract §5.3): stances for NPCs spawned with SpawnNPC opts. A record with no opts
	(Stance "Aggressive", no Leash, no GroupId) takes today's path unchanged.
	  - Aggressive: today's fight, plus the leash: past Leash (flat studs from Home) it drops its target and walks
	    Home, ignoring targets until back within NPCStance.HomeSlack; with no target it walks Home.
	  - Passive, not provoked: turns to the nearest target (gyro only), never walks to it, never fires; walks Home.
	    Provoked by a player hurting any group member, by ProvokeGroup, or by a player ON FOOT (SeatPart == nil)
	    within ProvokeRadius of a member's Home for NPCStance.ProvokeHoldSeconds (a seated player never provokes).
	    Provoked, it fights like Aggressive with the leash; the group calms CalmSeconds after its last contact.
	  - Post (and Static): never calls MoveTo, not even Home; turns and fires within Range through the same line-of-
	    sight and hit-chance gates. A Post in a passive group (a Passive member, or its own ProvokeRadius) holds fire
	    like a Passive until the group is provoked.
	  Group state is keyed by GroupId (the NPC's own Id when it has none). No table is allocated per tick. ]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedRoot = ReplicatedStorage:WaitForChild("Shared", 60)
local Constants = require(SharedRoot.Constants)
local CombatConfig = require(SharedRoot.Configs.CombatConfig)
local CombatFairnessConfig = require(SharedRoot.Configs.CombatFairnessConfig)

local CombatDamage = require(script.Parent.CombatDamage)
local CombatFeelConfig = require(SharedRoot.Configs.CombatFeelConfig) -- W2
local VehicleHealth = require(script.Parent.Parent.Parent.Modules.VehicleHealth) -- W2 (CC-2; nil-safe calls below)

local CombatNPC = {}

local rng = Random.new()
local fxRng = Random.new() -- W2: miss offsets for WeaponFx only (never touches the seeded hit roll)
-- per-player horizontal speed, sampled from server positions once per Think (P1-2 moving-target penalty)
local samplePos: { [number]: Vector3 } = {}
local sampleAt: { [number]: number } = {}
local speedOf: { [number]: number } = {}

-- W3 step 2 Phase B, lane N: stance groups, keyed by GroupId (or the NPC's own Id)
type Group = {
	Provoked: boolean,
	LastContact: number, -- clock of the last contact (a target in AggroRange, a hurt member, ProvokeGroup)
	CalmSeconds: number, -- calm this long after LastContact
	NearSince: number?, -- an on-foot player has been inside a member's ProvokeRadius since then
	NearTick: number, -- the Think tick that last saw one
	HasPassive: boolean, -- a Passive member was spawned into the group (its Post members hold fire too)
}
local groups: { [string]: Group } = {}
-- GroupIds that have ever had a Passive member (verifier fix): a Post re-spawned alone into an emptied passive group
-- (a top-up or a wake that spawns the static row first) still holds fire. Bounded by the Ops site ids.
local passiveGroupIds: { [string]: boolean } = {}
local thinkTick = 0

export type Bindings = {
	npcRecords: { [string]: any },
	combatStates: { [number]: any },
	clock: () -> number,
	characterParts: (Player) -> (Model?, Humanoid?, BasePart?),
	hitFeedback: (Player, any) -> (),
	pushState: (Player) -> (),
	spawnNPC: (string?, CFrame) -> any,
	getTagged: (string) -> { Instance },
	-- W2 (optional): one WeaponFx bullet event per NPC shot (origin = eye, landed, kind "P" / "V" / "M")
	fx: ((rec: any, origin: Vector3, landed: Vector3, kind: string) -> ())?,
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

--[[ W2 (contracts §3.8): a target sitting in an ENCLOSED seat (WE_Exposed == false; a missing attribute counts as
	exposed) of a live registered vehicle is shielded by it: the vehicle takes the NPC's damage (class "NPC", no
	attacker, no feedback to the occupant). Returns true when the hit went to the vehicle. ]]
local function redirectToVehicle(target: Player, damage: number): boolean
	local ok, veh, seat = pcall(VehicleHealth.GetSeatedVehicle, target)
	if not ok or veh == nil or seat == nil then
		return false
	end
	if (seat :: BasePart):GetAttribute("WE_Exposed") ~= false then
		return false
	end
	local okRec, rec = pcall(VehicleHealth.Get, veh :: Model)
	if not okRec or rec == nil or (rec :: any).Destroyed == true then
		return false
	end
	pcall(VehicleHealth.ApplyDamage, veh :: Model, { Attacker = nil, Amount = damage, Class = "NPC", WeaponId = "NPC" })
	return true
end

local function sendFx(rec: any, origin: Vector3, landed: Vector3, kind: string)
	local fx = B.fx
	if fx and CombatFeelConfig.Fx.NpcShots then
		pcall(fx, rec, origin, landed, kind)
	end
end

-- a missed NPC shot lands 2–4 studs beside the target (horizontal), for the tracer only
local function missPoint(at: Vector3): Vector3
	local m = CombatFeelConfig.Fx.NpcMissOffset
	local a = fxRng:NextNumber() * math.pi * 2
	local r = fxRng:NextNumber(m.Min, m.Max)
	return at + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
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

--[[ One NPC's fight against `target` this tick: today's Think body (P1-2 / W2), unchanged for a walking NPC.
	`canMove` false = the Post stance (lane N): no MoveTo at all (no chase, no stop-in-place); it turns, and fires
	within Range through the same line-of-sight and hit-chance gates. ]]
local function engage(rec: any, target: Player, dist: number, now: number, canMove: boolean)
	local C = CombatFairnessConfig
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
		if canMove and dist > rec.Def.Range * 0.85 then
			rec.Humanoid:MoveTo(troot.Position)
		elseif not canMove and dist > rec.Def.Range then
			-- Post (lane N): out of range, it only turns
		elseif not npcHasLos(rec, target, th, troot) then
			-- P1-2: walls, terrain, parked vehicles and other players give cover (not the seat you sit in)
			if not canMove then
				-- Post (lane N): holds its spot behind the cover
			elseif C.NpcChaseWithoutLos then
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
			if canMove then
				rec.Humanoid:MoveTo(rec.Root.Position)
			end
			local interval = 1 / math.max(rec.Def.FireRate, 0.1)
			local aimed = now - (rec.AimSince or now) >= C.NpcReactionSeconds
			if aimed and now - rec.LastFireAt >= interval and dist <= rec.Def.Range then
				rec.LastFireAt = now
				local tState = B.combatStates[target.UserId]
				local chance = CombatNPC.HitChance(dist, rec.Def.Range, speedOf[target.UserId] or 0)
				local eye = rec.Root.Position + Vector3.new(0, C.NpcEyeHeight, 0)
				if not (tState and now < tState.InvulnerableUntil) and rng:NextNumber() < chance then
					if redirectToVehicle(target, rec.Def.Damage) then
						sendFx(rec, eye, troot.Position, "V") -- W2: the enclosed seat's vehicle took it
					else
						th:TakeDamage(rec.Def.Damage)
						B.hitFeedback(target, {
							Kind = if th.Health <= 0 then "Death" else "Damaged",
							Damage = rec.Def.Damage,
							TargetName = rec.Def.DisplayName,
							From = eye, -- W2: direction cue
						})
						B.pushState(target)
						sendFx(rec, eye, troot.Position, "P")
					end
				else
					sendFx(rec, eye, missPoint(troot.Position), "M")
				end
			end
		end
	end
end

-- P1-2: a new (or lost) target restarts the reaction delay
local function aim(rec: any, target: Player?, now: number)
	if target ~= rec.AimTarget then
		rec.AimTarget = target
		rec.AimSince = now
		rec.AimBlocked = false
	end
end

-- ── lane N: stances, leash, groups ─────────────────────────────────────────────────────────────────────────
local function groupKey(rec: any): string
	return rec.GroupId or rec.Id
end

-- false for today's NPCs (2-argument SpawnNPC): they never touch the group table
local function usesGroup(rec: any): boolean
	return rec.GroupId ~= nil or (rec.Stance ~= nil and rec.Stance ~= "Aggressive")
end

local function newGroup(): Group
	return {
		Provoked = false,
		LastContact = 0,
		CalmSeconds = CombatConfig.NPCStance.CalmSeconds,
		NearSince = nil,
		NearTick = 0,
		HasPassive = false,
	}
end

local function aliveInGroup(records: { [string]: any }, key: string, except: any?): number
	local n = 0
	for _, r in pairs(records) do
		if r ~= except and r.Alive and r.Humanoid.Health > 0 and groupKey(r) == key then
			n += 1
		end
	end
	return n
end

-- flat (XZ) distance² from the NPC's root to its Home
local function homeDistSq(rec: any): number
	local h = rec.Home.Position
	local p = rec.Root.Position
	local dx, dz = p.X - h.X, p.Z - h.Z
	return dx * dx + dz * dz
end

-- yaw gyro toward a point (flat); never Root.CFrame
local function faceTowards(rec: any, point: Vector3)
	local p = rec.Root.Position
	local dx, dz = point.X - p.X, point.Z - p.Z
	if dx * dx + dz * dz < 0.01 then
		return
	end
	local gyro = rec.Root:FindFirstChild("NPCFaceGyro") or rec.Root:FindFirstChildOfClass("BodyGyro")
	if gyro and gyro:IsA("BodyGyro") then
		gyro.CFrame = CFrame.lookAt(p, Vector3.new(point.X, p.Y, point.Z))
	end
end

-- MoveTo(Home) while farther than HomeSlack (flat). Returns true while it is still walking back.
local function walkHome(rec: any): boolean
	local slack = CombatConfig.NPCStance.HomeSlack
	if homeDistSq(rec) <= slack * slack then
		return false
	end
	local h = rec.Home.Position
	faceTowards(rec, h)
	rec.Humanoid:MoveTo(h)
	return true
end

--[[ Verifier fix: true when the NPC stands within one think-step of its leash and its target is outside the leash
	circle, so a chase would carry it past the leash. A target inside the circle is chased as usual (a straight walk
	between two points inside a circle stays inside it). ]]
local function atLeashEdge(rec: any, target: Player): boolean
	local _, _, troot = B.characterParts(target)
	if troot == nil then
		return false
	end
	local leash = rec.Leash :: number
	local h = rec.Home.Position
	local tp = troot.Position
	local tx, tz = tp.X - h.X, tp.Z - h.Z
	if tx * tx + tz * tz <= leash * leash then
		return false
	end
	local step = math.max(CombatConfig.NPCStance.HomeSlack, (rec.Humanoid.WalkSpeed or 16) * CombatConfig.NPCThinkInterval)
	local edge = math.max(0, leash - step)
	return homeDistSq(rec) >= edge * edge
end

-- a living player ON FOOT within `radius` of `at` (a seated player never provokes by proximity)
local function onFootWithin(at: Vector3, radius: number): boolean
	local r2 = radius * radius
	for _, player in ipairs(Players:GetPlayers()) do
		local _, hum, root = B.characterParts(player)
		if hum and root and hum.Health > 0 and hum.SeatPart == nil then
			local d = root.Position - at
			if d.X * d.X + d.Y * d.Y + d.Z * d.Z <= r2 then
				return true
			end
		end
	end
	return false
end

-- SpawnNPC hook: a grouped / non-Aggressive record joins its group. A group with no living member starts calm.
function CombatNPC.JoinGroup(records: { [string]: any }, rec: any)
	if not usesGroup(rec) then
		return
	end
	local key = groupKey(rec)
	local g = groups[key]
	if g == nil or aliveInGroup(records, key, rec) == 0 then
		g = newGroup()
		groups[key] = g
	end
	if rec.Stance == "Passive" then
		(g :: Group).HasPassive = true
		if rec.GroupId ~= nil then
			passiveGroupIds[rec.GroupId] = true
		end
	end
end

-- destroy hook (the record is already out of `records`): drop its group's state once nobody in it is left
function CombatNPC.ForgetRecord(records: { [string]: any }, rec: any)
	local key = groupKey(rec)
	if groups[key] ~= nil and (rec.GroupId == nil or aliveInGroup(records, key, rec) == 0) then
		groups[key] = nil
	end
end

--[[ Provoke a group (key = GroupId, or an ungrouped NPC's Id): its Passive members fight until `seconds` (default
	NPCStance.CalmSeconds; the longer one wins while already provoked) after the group's last contact. Returns the
	number of living members (0 = no such group: nothing is stored). ]]
function CombatNPC.ProvokeGroup(records: { [string]: any }, key: string, seconds: number?, now: number): number
	local n = aliveInGroup(records, key, nil)
	if n == 0 then
		return 0
	end
	local g = groups[key]
	if g == nil then
		g = newGroup()
		groups[key] = g
	end
	local gg = g :: Group
	local secs = CombatConfig.NPCStance.CalmSeconds
	if typeof(seconds) == "number" and seconds > 0 and seconds < math.huge then
		secs = seconds
	end
	gg.CalmSeconds = if gg.Provoked then math.max(gg.CalmSeconds, secs) else secs
	gg.Provoked = true
	gg.LastContact = now
	gg.NearSince = nil
	return n
end

-- Calm a provoked group now (its Passive members walk Home). Returns the living members calmed (0 if it was calm).
function CombatNPC.CalmGroup(records: { [string]: any }, key: string): number
	local g = groups[key]
	if g == nil or not g.Provoked then
		return 0
	end
	g.Provoked = false
	g.NearSince = nil
	return aliveInGroup(records, key, nil)
end

function CombatNPC.IsProvoked(rec: any): boolean
	local g = groups[groupKey(rec)]
	return g ~= nil and g.Provoked
end

-- A stance NPC's tick (lane N; contract §5.3)
local function thinkStance(rec: any, now: number)
	local g = groups[groupKey(rec)]
	local provoked = g ~= nil and g.Provoked
	local stance = rec.Stance
	local canMove = stance ~= "Post"
	local target, dist = CombatNPC.NearestPlayer(rec.Root.Position, rec.Def.AggroRange)
	if target and g and provoked then
		g.LastContact = now -- contact keeps a provoked group fighting
	end
	local held = not provoked
		and (
			stance == "Passive"
			or (
				stance == "Post"
				and (rec.ProvokeRadius ~= nil or (g ~= nil and g.HasPassive) or (rec.GroupId ~= nil and passiveGroupIds[rec.GroupId] == true))
			)
		)
	if held then
		-- not provoked: never walks to a target, never fires; the reaction delay starts only once provoked
		rec.AimTarget = nil
		rec.AimBlocked = false
		if g and rec.ProvokeRadius ~= nil and g.NearTick ~= thinkTick and onFootWithin(rec.Home.Position, rec.ProvokeRadius) then
			g.NearTick = thinkTick
		end
		if not (canMove and walkHome(rec)) and target then
			local _, _, troot = B.characterParts(target)
			if troot then
				faceTowards(rec, troot.Position)
			end
		end
		return
	end
	if canMove and rec.Leash ~= nil then
		local slack = CombatConfig.NPCStance.HomeSlack
		local d2 = homeDistSq(rec)
		if rec.Returning and d2 <= slack * slack then
			rec.Returning = false
		elseif not rec.Returning and d2 > rec.Leash * rec.Leash then
			rec.Returning = true
		end
		if rec.Returning then
			-- past the leash: drop the target and walk back to the post (targets ignored until home)
			aim(rec, nil, now)
			walkHome(rec)
			return
		end
	end
	aim(rec, target, now)
	if target and canMove and rec.Leash ~= nil and atLeashEdge(rec, target) then
		-- verifier fix: never chase past the leash (it would turn back without a shot while the player shoots it from
		-- just outside); it stops at the edge and fights from there like a Post (same LOS and hit-chance gates)
		rec.Humanoid:MoveTo(rec.Root.Position)
		engage(rec, target, dist, now, false)
	elseif target then
		engage(rec, target, dist, now, canMove)
	elseif canMove and (rec.Leash ~= nil or stance == "Passive") then
		walkHome(rec) -- no target: back to the post
	end
end

-- after every tick: calm groups past their calm time; provoke groups an on-foot player has stood near long enough
local function settleGroups(now: number)
	local S = CombatConfig.NPCStance
	for _, g in pairs(groups) do
		if g.Provoked then
			if now - g.LastContact >= g.CalmSeconds then
				g.Provoked = false
				g.NearSince = nil
			end
		elseif g.NearTick == thinkTick then
			local since = g.NearSince
			if since == nil then
				g.NearSince = now
			elseif now - since >= S.ProvokeHoldSeconds then
				g.Provoked = true
				g.LastContact = now
				g.CalmSeconds = S.CalmSeconds
				g.NearSince = nil
			end
		else
			g.NearSince = nil
		end
	end
end

function CombatNPC.Think()
	if next(B.npcRecords) == nil then
		return
	end
	local now = B.clock()
	sampleSpeeds(now)
	thinkTick += 1
	for _, rec in pairs(B.npcRecords) do
		if rec.Alive and rec.Humanoid.Health > 0 and rec.Root.Parent then
			if rec.Leash == nil and not usesGroup(rec) then
				-- today's NPC (no opts, or Aggressive with no leash and no group): unchanged
				local target, dist = CombatNPC.NearestPlayer(rec.Root.Position, rec.Def.AggroRange)
				aim(rec, target, now)
				if target then
					engage(rec, target, dist, now, true)
				end
			else
				thinkStance(rec, now)
			end
		end
	end
	if next(groups) ~= nil then
		settleGroups(now)
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
