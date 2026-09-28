--!strict
--[[ Aircraft weapons (owner request part 2). Numbers: Shared/Configs/AircraftWeaponConfig.luau.

	Only combat aircraft are armed (AircraftWeaponConfig.Aircraft / Loadouts). The feature is dark while
	WeaponsLive = false, except for the owner's playtest account (AircraftWeaponConfig.LiveFor, evaluated HERE).

	RequestVehicleFire (the v71 M2 remote, contract { M = mountId, D = direction }) + optional I = input class.
	Nothing else in the payload is read: a client never names a target. Order of checks (first failure wins, the
	reason is returned for tests and never shown to the player):
	  "payload"   not a table / M not an id string / D not a finite Vector3 (non-finite D = one AntiExploit strike)
	  "rate"      RateLimitService "air_fire" (RemoteRate / RemoteBurst)
	  "off"       weapons are not live for this player
	  "not_seated" / "not_pilot" / "not_owner"   seated in the DriverSeat (WE_SeatRole "Driver") of an aircraft they own
	  "no_vehicle" / "wrecked" / "trial"         a live registered (VehicleHealth) vehicle, not a free trial
	  "unarmed" / "not_in_loadout"               the aircraft's loadout holds M
	  "reloading" "cooldown" "direction" "busy"  magazine / fire interval / zero direction / ordnance caps
	The aim is clamped into the weapon's ArcDeg around the nose (a pilot looking backwards still fires forward).
	Accepted fire ends a novice shield (reason "fire", like any shot) and spends ammo before it resolves.

	DAMAGE (the existing path only): guns = one server ray from the mount + spread → CombatService.ApplyHit (players,
	NPCs, vehicles, gates / gate guards → GateDefenseService.ApplyDamage); a miss may take ONE assisted target
	(AimAssistConfig.Aircraft, humanoids only, line of sight). Rockets / missiles / bombs = AirOrdnance rounds; on
	impact: direct vehicle hit (ApplyHit), humanoid splash (CombatService.ApplyRadiusDamage), vehicle splash
	(VehicleHealth.ApplyRadiusDamage), gate + gate guard splash (ApplyHit on the nearest gate leaf / each guard root
	in range, line of sight). Missiles home only on a target the server picked in LockConeDeg / LockRange with line of
	sight. Never damaged: clan allies (players, their vehicles, their gates), novice-shielded players and their
	vehicles and bases, raid-shielded or new-player-protected bases, VehicleHealth-protected vehicles, the aircraft
	itself and its occupants. HitOpts.WeaponId = "V_<mount>" (GateDefenseService allows those hits out to the
	weapon's Range + GateReachSlack).

	FX: guns → CombatFx.Bullet with S = 0 so the pilot also sees the tracer (bucket key "air<UserId>", the WeaponFx
	UnreliableRemoteEvent, <= 20 Hz per shooter); ordnance → CombatFx.Launch (G = GravityFactor for bombs) and
	CombatFx.Explode, serials offset by FX_SERIAL_BASE so they never collide with infantry projectiles.
	Ammo for the fire buttons: aircraft Model attributes WE_AW_<mount> (rounds) and WE_AW_<mount>_Rl (reload seconds
	while reloading, else 0), written on change only. Player attribute WE_AirWeaponsLive (display only). ]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local Constants = require(Shared.Constants)
local AircraftWeaponConfig = require(Shared.Configs.AircraftWeaponConfig)
local AimAssistConfig = require(Shared.Configs.AimAssistConfig)
local VisualAssetConfig = require(Shared.Configs.VisualAssetConfig)
local RaidConfig = require(Shared.Configs.RaidConfig)
local GameConfig = require(Shared.Configs.GameConfig)

local VehicleHealth = require(script.Parent.Parent.Modules.VehicleHealth)
local AirOrdnance = require(script.Parent.Parent.Modules.AirOrdnance)
local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)
local CombatAssist = require(script.Parent.CombatService.CombatAssist)
local CombatDamage = require(script.Parent.CombatService.CombatDamage)
local CombatFx = require(script.Parent.CombatService.CombatFx)

type WeaponDef = AircraftWeaponConfig.WeaponDef
type SlotState = { Ammo: number, ReloadUntil: number, Gen: number, LastFire: number, Pod: number, WAmmo: number, WRl: number }
type ModelState = { Slots: { [string]: SlotState }, Conn: RBXScriptConnection? }
type Cand = { Part: BasePart, Model: Model, Score: number, Alive: () -> boolean }

local AirWeaponService = {}

local CFG = AircraftWeaponConfig
local FX_SERIAL_BASE = 2000000 -- infantry Projectile serials stay below 1,000,001

local DataService: any = nil
local RemoteSetup: any = nil
local RateLimitService: any = nil
local AntiExploitService: any = nil
local CombatService: any = nil
local GateDefenseService: any = nil
local ClanService: any = nil

local states: { [Model]: ModelState } = {}
local rng = Random.new()
local stats = { Accepted = 0, Refused = 0, Hits = 0, Launched = 0, Impacts = 0, Assisted = 0, Locks = 0 }
local lastReason: { [number]: string } = {}
local tagCache: { [string]: { At: number, List: { Instance } } } = {}

local function clock(): number
	return os.clock()
end

local function tagged(tag: string): { Instance }
	local e = tagCache[tag]
	local t = clock()
	if e and t - e.At < 1 then
		return e.List
	end
	local list = CollectionService:GetTagged(tag)
	tagCache[tag] = { At = t, List = list }
	return list
end

local function finiteV(v: any): boolean
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z and v.Magnitude < 1e9
end

-- ── allies / shields ──────────────────────────────────────────────────────────────────────────────────────────

-- same non-empty clan (pcall'd; no ClanService = never allies)
local function sameClan(a: Player, b: Player): boolean
	if a == b then
		return true
	end
	if ClanService == nil or ClanService.GetClanId == nil then
		return false
	end
	local okA, ca = pcall(ClanService.GetClanId, a)
	local okB, cb = pcall(ClanService.GetClanId, b)
	return okA and okB and typeof(ca) == "string" and ca ~= "" and ca == cb
end

-- owner userId is the attacker or a clan ally of the attacker
local function allyUid(attacker: Player, uid: any): boolean
	local n = tonumber(uid)
	if n == nil then
		return false
	end
	if n == attacker.UserId then
		return true
	end
	local owner = Players:GetPlayerByUserId(n)
	return owner ~= nil and sameClan(attacker, owner)
end

local function noviceShielded(p: Player?): boolean
	if p == nil or CombatService == nil or CombatService.IsNoviceShielded == nil then
		return false
	end
	local ok, on = pcall(CombatService.IsNoviceShielded, p)
	return ok and on == true
end

-- a vehicle / thing owned by `uid` may not be hit by `attacker`: ally, or a novice-shielded owner
local function ownerProtected(attacker: Player, uid: any): boolean
	if allyUid(attacker, uid) then
		return true
	end
	local n = tonumber(uid)
	return n ~= nil and noviceShielded(Players:GetPlayerByUserId(n))
end

-- the base of `uid` is shielded: raid shield (profile.Raid.ShieldUntil), new-player protection, novice shield
function AirWeaponService.BaseShielded(uid: any): boolean
	local n = tonumber(uid)
	local owner = if n then Players:GetPlayerByUserId(n) else nil
	if owner == nil then
		return false
	end
	if noviceShielded(owner) then
		return true
	end
	local profile = if DataService and DataService.GetProfile then DataService.GetProfile(owner) else nil
	if typeof(profile) ~= "table" then
		return true -- save not loaded yet: never hit an unknown base
	end
	local nowUnix = os.time()
	local raid = profile.Raid
	if typeof(raid) == "table" and (tonumber(raid.ShieldUntil) or 0) > nowUnix then
		return true
	end
	local R = RaidConfig.Raid
	if not (RunService:IsStudio() and not R.ProtectNewPlayersInStudio) then
		local first = tonumber(profile.FirstJoinUnix) or 0
		if first > 0 and first + R.NewPlayerProtectionSeconds > nowUnix then
			return true
		end
	end
	return false
end

-- owner of a gate leaf / gate guard part, or nil
local function gateOwnerOf(part: Instance): number?
	local own = part:GetAttribute("OwnerUserId")
	if typeof(own) == "number" then
		return own
	end
	local node: Instance? = part.Parent
	while node ~= nil and node ~= Workspace do
		local o = node:GetAttribute("OwnerUserId")
		if typeof(o) == "number" then
			return o
		end
		node = node.Parent
	end
	return nil
end

-- may this hit part be damaged by `attacker` at all? (ApplyHit / GateDefenseService still apply their own rules)
local function hitAllowed(attacker: Player, inst: Instance): boolean
	local node: Instance? = inst
	while node ~= nil and node ~= Workspace do
		if node:IsA("Model") then
			local victim = Players:GetPlayerFromCharacter(node)
			if victim then
				return not sameClan(attacker, victim)
			end
		end
		node = node.Parent
	end
	local veh = VehicleHealth.FindVehicleModel(inst)
	local rec = if veh then VehicleHealth.Get(veh) else nil
	if rec then
		return not ownerProtected(attacker, rec.OwnerUserId)
	end
	if inst:GetAttribute("GateBarrier") == true then
		local uid = gateOwnerOf(inst)
		return uid ~= nil and not allyUid(attacker, uid) and not AirWeaponService.BaseShielded(uid)
	end
	return true
end

-- ── aircraft / mounts ─────────────────────────────────────────────────────────────────────────────────────────

local function hitId(mountId: string): string
	return CFG.HitIdPrefix .. mountId
end

local function filterFor(player: Player, model: Model): { Instance }
	local list: { Instance } = { model }
	if player.Character then
		table.insert(list, player.Character)
	end
	local squads = Workspace:FindFirstChild("WarEmpireSquads")
	if squads then
		table.insert(list, squads)
	end
	return list
end

-- muzzle / bay point of a mount (its v79 hook's Mount kit part; the chassis when the kit has none). podIndex even =
-- the mirrored (right) pod for MirrorX mounts.
local function muzzle(model: Model, def: WeaponDef, podIndex: number): Vector3?
	local chassis = model.PrimaryPart
	if chassis == nil then
		return nil
	end
	local hook = (VisualAssetConfig.VehicleWeapons :: any)[def.Hook]
	local mountName = if typeof(hook) == "table" and typeof(hook.Mount) == "string" then hook.Mount else nil
	local found = if mountName then model:FindFirstChild(mountName) else nil
	local part: BasePart = if found and found:IsA("BasePart") then found else chassis
	local cf = chassis.CFrame
	local base = part.Position
	if def.MirrorX == true and podIndex % 2 == 0 then
		local lp = cf:PointToObjectSpace(base)
		base = cf:PointToWorldSpace(Vector3.new(-lp.X, lp.Y, lp.Z))
	end
	if def.Kind == "Bomb" then
		return base - cf.UpVector * (part.Size.Y * 0.5 + (tonumber(def.MuzzleDrop) or 1))
	end
	return base + cf.LookVector * (part.Size.Z * 0.5 + (tonumber(def.MuzzleForward) or 0)) - cf.UpVector * (tonumber(def.MuzzleDrop) or 0)
end

-- `dir` (unit) clamped into a cone of `arcDeg` around `fwd` (unit)
local function clampToArc(dir: Vector3, fwd: Vector3, arcDeg: number): Vector3
	local d = math.clamp(dir:Dot(fwd), -1, 1)
	local maxRad = math.rad(math.clamp(arcDeg, 0, 180))
	if math.acos(d) <= maxRad + 1e-6 then
		return dir
	end
	local perp = dir - fwd * d
	if perp.Magnitude < 1e-6 then
		return fwd
	end
	perp = perp.Unit
	return (fwd * math.cos(maxRad) + perp * math.sin(maxRad)).Unit
end

local function spread(dir: Vector3, deg: number): Vector3
	if not (deg > 0) then
		return dir
	end
	local u = dir:Cross(Vector3.new(0, 1, 0))
	if u.Magnitude < 1e-3 then
		u = dir:Cross(Vector3.new(1, 0, 0))
	end
	u = u.Unit
	local w = dir:Cross(u).Unit
	local r = math.rad(deg) * math.sqrt(rng:NextNumber())
	local phi = rng:NextNumber() * math.pi * 2
	return (dir * math.cos(r) + (u * math.cos(phi) + w * math.sin(phi)) * math.sin(r)).Unit
end

local function writeAttrs(model: Model, mountId: string, st: SlotState, def: WeaponDef)
	local p = CFG.AmmoAttributePrefix .. mountId
	local ammo = math.max(0, math.floor(st.Ammo))
	if st.WAmmo ~= ammo then
		st.WAmmo = ammo
		model:SetAttribute(p, ammo)
	end
	local rl = if st.ReloadUntil > 0 then def.Magazine.ReloadSeconds else 0
	if st.WRl ~= rl then
		st.WRl = rl
		model:SetAttribute(p .. "_Rl", rl)
	end
end

local function stateFor(model: Model): ModelState
	local s = states[model]
	if s then
		return s
	end
	local ns: ModelState = { Slots = {}, Conn = nil }
	states[model] = ns
	ns.Conn = model.AncestryChanged:Connect(function()
		if model.Parent == nil and states[model] == ns then
			states[model] = nil
			if ns.Conn then
				ns.Conn:Disconnect()
			end
		end
	end)
	return ns
end

local function slotFor(model: Model, mountId: string, def: WeaponDef): SlotState
	local ms = stateFor(model)
	local st = ms.Slots[mountId]
	if st == nil then
		st = { Ammo = def.Magazine.Size, ReloadUntil = 0, Gen = 0, LastFire = -math.huge, Pod = 0, WAmmo = -1, WRl = -1 }
		ms.Slots[mountId] = st
		writeAttrs(model, mountId, st, def)
	end
	return st
end

local function startReload(model: Model, mountId: string, st: SlotState, def: WeaponDef)
	st.Gen += 1
	local gen = st.Gen
	local secs = def.Magazine.ReloadSeconds
	st.ReloadUntil = clock() + secs
	writeAttrs(model, mountId, st, def)
	task.delay(secs, function()
		if st.Gen == gen and st.ReloadUntil > 0 and clock() >= st.ReloadUntil - 1e-3 then
			st.Ammo = def.Magazine.Size
			st.ReloadUntil = 0
			if model.Parent ~= nil then
				writeAttrs(model, mountId, st, def)
			end
		end
	end)
end

-- ── targets ───────────────────────────────────────────────────────────────────────────────────────────────────

local function torsoOf(model: Model): BasePart?
	local t = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart")
	return if t and t:IsA("BasePart") then t else nil
end

local function aliveHum(model: Model): Humanoid?
	local h = model:FindFirstChildOfClass("Humanoid")
	return if h and h.Health > 0 then h else nil
end

-- humanoid candidates (players + NPC records) for gun assist and missile locks; `fn(model, part, alive)`
local function eachHumanoid(attacker: Player, firing: Model, fn: (Model, BasePart, () -> boolean) -> ())
	if GameConfig.PvPEnabled then
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			if plr ~= attacker and char and not sameClan(attacker, plr) then
				local hum = aliveHum(char)
				local torso = torsoOf(char)
				local spawnSafe = false
				if CombatService and CombatService.IsSpawnInvulnerable then
					local ok, inv = pcall(CombatService.IsSpawnInvulnerable, plr)
					spawnSafe = ok and inv == true
				end
				local veh = VehicleHealth.GetSeatedVehicle(plr)
				if hum and torso and not spawnSafe and veh == nil then
					fn(char, torso, function()
						return hum.Health > 0 and char.Parent ~= nil
					end)
				end
			end
		end
	end
	for _, inst in ipairs(tagged(Constants.Tags.NPC)) do
		if inst:IsA("Model") and typeof(inst:GetAttribute("NPCId")) == "string" and inst ~= firing then
			local hum = aliveHum(inst)
			local torso = torsoOf(inst)
			if hum and torso then
				fn(inst, torso, function()
					return hum.Health > 0 and inst.Parent ~= nil
				end)
			end
		end
	end
end

-- AimAssistConfig.Aircraft: ONE humanoid near the fire ray, in range, in front of what the ray hit, line of sight
local function assistPick(attacker: Player, firing: Model, origin: Vector3, dir: Vector3, cls: string?, range: number, maxAlong: number, filter: { Instance }): (Model?, BasePart?)
	local A = AimAssistConfig.Aircraft
	local classes: any = A.Classes
	local c = classes[cls or ""] or classes[AimAssistConfig.DefaultClass]
	if c == nil or AimAssistConfig.Enabled ~= true then
		return nil, nil
	end
	local maxRange = math.min(range, A.MaxRangeStuds)
	local best: { Cand } = {}
	eachHumanoid(attacker, firing, function(model: Model, torso: BasePart, alive: () -> boolean)
		local lat = CombatAssist.Evaluate(origin, dir, torso.Position, c, maxRange, maxAlong, nil)
		if lat ~= nil then
			table.insert(best, { Part = torso, Model = model, Score = lat, Alive = alive })
		end
	end)
	table.sort(best, function(a: Cand, b: Cand)
		return a.Score < b.Score
	end)
	for i = 1, math.min(3, #best) do
		local cd = best[i]
		if CombatDamage.LineOfSight(origin, cd.Part.Position, filter, cd.Model, false, AimAssistConfig.LosPastTorsoStuds) then
			return cd.Model, cd.Part
		end
	end
	return nil, nil
end

-- missile lock: the enemy vehicle / humanoid closest to the aim inside LockConeDeg and LockRange, line of sight.
function AirWeaponService._PickLock(attacker: Player, firing: Model, origin: Vector3, dir: Vector3, def: WeaponDef, filter: { Instance }): (BasePart?, (() -> boolean)?)
	local range = tonumber(def.LockRange) or 0
	local cosMin = math.cos(math.rad(math.clamp(tonumber(def.LockConeDeg) or 0, 0, 89)))
	local cands: { Cand } = {}
	local function consider(model: Model, part: BasePart, alive: () -> boolean)
		local v = part.Position - origin
		local dist = v.Magnitude
		if dist < 1 or dist > range then
			return
		end
		local c = dir:Dot(v / dist)
		if c >= cosMin then
			table.insert(cands, { Part = part, Model = model, Score = -c, Alive = alive })
		end
	end
	for _, inst in ipairs(tagged(Constants.Tags.Vehicle)) do
		if inst:IsA("Model") and inst ~= firing then
			local rec = VehicleHealth.Get(inst)
			local chassis = inst.PrimaryPart
			if rec and chassis and not rec.Destroyed and not VehicleHealth.IsProtected(inst, attacker) and not ownerProtected(attacker, rec.OwnerUserId) then
				consider(inst, chassis, function()
					local r = VehicleHealth.Get(inst)
					return r ~= nil and not r.Destroyed
				end)
			end
		end
	end
	eachHumanoid(attacker, firing, consider)
	table.sort(cands, function(a: Cand, b: Cand)
		return a.Score < b.Score
	end)
	for i = 1, math.min(3, #cands) do
		local cd = cands[i]
		if CombatDamage.LineOfSight(origin, cd.Part.Position, filter, cd.Model, false, 3) then
			return cd.Part, cd.Alive
		end
	end
	return nil, nil
end

-- ── damage ────────────────────────────────────────────────────────────────────────────────────────────────────

local function applyHit(attacker: Player, part: Instance, amount: number, def: WeaponDef, mountId: string, pos: Vector3, firing: Model, extra: { [string]: any }?): any
	if CombatService == nil or CombatService.ApplyHit == nil or not hitAllowed(attacker, part) then
		return nil
	end
	local opts: { [string]: any } = {
		WeaponId = hitId(mountId),
		Class = def.Class,
		VsInfantryMult = def.VsInfantryMult,
		HitPos = pos,
		Vehicle = firing,
	}
	if extra then
		for k, v in pairs(extra) do
			opts[k] = v
		end
	end
	local ok, res = pcall(CombatService.ApplyHit, attacker, part, amount, opts)
	if ok and typeof(res) == "table" and (tonumber(res.Dealt) or 0) > 0 then
		stats.Hits += 1
	end
	return if ok then res else nil
end

local function distToBox(part: BasePart, p: Vector3): (number, Vector3)
	local lp = part.CFrame:PointToObjectSpace(p)
	local h = part.Size * 0.5
	local c = Vector3.new(math.clamp(lp.X, -h.X, h.X), math.clamp(lp.Y, -h.Y, h.Y), math.clamp(lp.Z, -h.Z, h.Z))
	return (lp - c).Magnitude, part.CFrame:PointToWorldSpace(c)
end

-- gates and gate guards around a blast (the gate: the nearest leaf of each plot once; guards: each root in range)
local function gateSplash(attacker: Player, center: Vector3, radius: number, amount: number, def: WeaponDef, mountId: string, firing: Model)
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	local bases = setup and setup:FindFirstChild("Bases")
	if bases == nil then
		return
	end
	local minMult = tonumber(def.SplashMinMult) or 0.25
	local from = center + Vector3.new(0, CFG.Splash.LosLiftStuds, 0)
	for _, plot in ipairs(bases:GetChildren()) do
		local folder = plot:FindFirstChild("WE_GateDefense")
		if folder == nil then
			continue
		end
		local ownerUid = folder:GetAttribute("OwnerUserId")
		if ownerUid == nil or allyUid(attacker, ownerUid) or AirWeaponService.BaseShielded(ownerUid) then
			continue
		end
		local bestLeaf: BasePart? = nil
		local bestD, bestPt = math.huge, center
		for _, ch in ipairs(folder:GetChildren()) do
			if ch:IsA("BasePart") and ch:GetAttribute("GateBarrier") == true and ch:GetAttribute("GateGuardPart") ~= true then
				local d, pt = distToBox(ch, center)
				if d <= radius and d < bestD then
					bestLeaf, bestD, bestPt = ch, d, pt
				end
			elseif ch:IsA("Model") and ch:GetAttribute("GateGuard") == true then
				local root = ch:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") and aliveHum(ch) then
					local d = (root.Position - center).Magnitude
					if d <= radius and CombatDamage.LineOfSight(from, root.Position, { firing }, ch, false, 2) then
						local amt = amount * def.VsInfantryMult * CombatDamage.SplashMult(d, radius, minMult)
						if amt > 0 then
							applyHit(attacker, root, amt, def, mountId, center, firing, { VsInfantryMult = 1 })
						end
					end
				end
			end
		end
		local leaf = bestLeaf
		if leaf and (bestD < 0.5 or CombatDamage.LineOfSight(from, bestPt, { firing }, leaf, false, 1)) then
			local amt = amount * CombatDamage.SplashMult(bestD, radius, minMult)
			if amt > 0 then
				applyHit(attacker, leaf, amt, def, mountId, center, firing, nil)
			end
		end
	end
end

local function impact(attacker: Player, firing: Model, def: WeaponDef, mountId: string, pos: Vector3, hit: RaycastResult?, fxFrom: Vector3, fxId: number)
	stats.Impacts += 1
	local center = pos
	if hit then
		center = hit.Position + hit.Normal * 0.5
	end
	local radius = tonumber(def.Splash) or 0
	if attacker.Parent ~= nil and CombatService ~= nil then
		local direct: Model? = nil
		if hit then
			local veh = VehicleHealth.FindVehicleModel(hit.Instance)
			local rec = if veh then VehicleHealth.Get(veh) else nil
			if veh and rec and not rec.Destroyed and veh ~= firing then
				applyHit(attacker, hit.Instance, def.Damage, def, mountId, hit.Position, firing, nil)
				direct = veh
			end
		end
		if radius > 0 then
			if CombatService.ApplyRadiusDamage then
				pcall(CombatService.ApplyRadiusDamage, attacker, center, radius, def.Damage, {
					WeaponId = hitId(mountId),
					MinMult = def.SplashMinMult,
					VsInfantryMult = def.VsInfantryMult,
					Vehicle = firing,
				})
			end
			if not noviceShielded(attacker) then
				pcall(VehicleHealth.ApplyRadiusDamage, center, radius, def.Damage, attacker, def.Class, {
					MinMult = def.SplashMinMult,
					WeaponMult = 1,
					IgnoreModel = direct,
					WeaponId = hitId(mountId),
					SkipOwner = function(uid: number): boolean
						return ownerProtected(attacker, uid)
					end,
				})
				gateSplash(attacker, center, radius, def.Damage, def, mountId, firing)
			end
		end
	end
	pcall(CombatFx.Explode, attacker.UserId, hitId(mountId), fxFrom, center, radius, fxId)
end

-- ── fire ──────────────────────────────────────────────────────────────────────────────────────────────────────

local function fireGun(player: Player, model: Model, def: WeaponDef, mountId: string, dir: Vector3, inputClass: string?)
	local origin = muzzle(model, def, 1)
	if origin == nil then
		return
	end
	local filter = filterFor(player, model)
	local sdir = spread(dir, tonumber(def.SpreadDeg) or 0)
	local res = CombatDamage.Raycast(origin, sdir, def.Range, filter)
	local landed = origin + sdir * def.Range
	local kind = "M"
	local decided = false
	if res then
		landed = res.Position
		local inst = res.Instance
		local r = applyHit(player, inst, def.Damage, def, mountId, res.Position, model, nil)
		local k = if typeof(r) == "table" then r.Kind else nil
		if k == "Player" then
			kind, decided = "P", true
		elseif k == "NPC" then
			kind, decided = "N", true
		elseif k == "Vehicle" then
			kind, decided = "V", true
		elseif k == "Gate" then
			kind, decided = "G", true
		elseif VehicleHealth.FindVehicleModel(inst) ~= nil or inst:GetAttribute("GateBarrier") == true then
			kind, decided = "V", true -- a protected / allied target: it takes the round, nothing is dealt
		else
			kind = "W"
		end
	end
	if not decided then
		local maxAlong = if res then res.Distance + AimAssistConfig.LosPastTorsoStuds else def.Range
		local m, torso = assistPick(player, model, origin, dir, inputClass, def.Range, maxAlong, filter)
		if m and torso then
			stats.Assisted += 1
			landed = torso.Position
			local r = applyHit(player, torso, def.Damage, def, mountId, torso.Position, model, { Assist = true })
			kind = if typeof(r) == "table" and r.Kind == "Player" then "P" else "N"
		end
	end
	pcall(CombatFx.Bullet, "air" .. tostring(player.UserId), 0, hitId(mountId), origin, landed, kind)
end

local function launchRound(player: Player, model: Model, def: WeaponDef, mountId: string, origin: Vector3, vel: Vector3, target: BasePart?, alive: (() -> boolean)?)
	local filter = filterFor(player, model)
	local fwd = if vel.Magnitude > 1e-3 then vel.Unit else Vector3.new(0, -1, 0)
	local spawnAt = origin + fwd * CFG.Ordnance.SpawnForwardStuds
	local rec = AirOrdnance.Launch({
		OwnerUserId = player.UserId,
		Origin = spawnAt,
		Velocity = vel,
		GravityFactor = tonumber(def.GravityFactor) or 0,
		MaxSeconds = tonumber(def.MaxSeconds) or 2,
		Filter = filter,
		Target = target,
		IsTargetAlive = alive,
		TurnRateDeg = def.TurnRateDeg,
		ProximityFuse = def.ProximityFuse,
		OnImpact = function(pos: Vector3, hit: RaycastResult?, r: AirOrdnance.Record)
			impact(player, model, def, mountId, pos, hit, spawnAt, FX_SERIAL_BASE + r.Id)
		end,
	})
	if rec == nil then
		return
	end
	stats.Launched += 1
	local fxV = vel
	if target then
		local to = target.Position - spawnAt
		if to.Magnitude > 1 then
			fxV = to.Unit * vel.Magnitude
		end
	end
	pcall(CombatFx.Launch, player.UserId, hitId(mountId), spawnAt, fxV, tonumber(def.MaxSeconds) or 2, FX_SERIAL_BASE + rec.Id, tonumber(def.GravityFactor) or 0)
end

local function aircraftVelocity(model: Model, cap: number): Vector3
	local chassis = model.PrimaryPart
	if chassis == nil then
		return Vector3.zero
	end
	local ok, v = pcall(function()
		return chassis.AssemblyLinearVelocity
	end)
	if not ok or not finiteV(v) then
		return Vector3.zero
	end
	local vv = v :: Vector3
	if vv.Magnitude > cap then
		vv = vv.Unit * cap
	end
	return vv
end

local function dropBomb(player: Player, model: Model, def: WeaponDef, mountId: string, pod: number)
	if model.Parent == nil or player.Parent == nil then
		return
	end
	local origin = muzzle(model, def, pod)
	if origin == nil then
		return
	end
	local vel = aircraftVelocity(model, tonumber(def.MaxInheritSpeed) or 100) * (tonumber(def.InheritVelocity) or 1)
		+ Vector3.new(0, -(tonumber(def.DropSpeed) or 0), 0)
	launchRound(player, model, def, mountId, origin, vel, nil, nil)
end

--[[ One fire request. Returns (accepted, reason). ]]
function AirWeaponService.RequestFire(player: Player, payload: any): (boolean, string)
	local function refuse(reason: string): (boolean, string)
		stats.Refused += 1
		lastReason[player.UserId] = reason
		return false, reason
	end
	if typeof(payload) ~= "table" or not RemoteGuard.IsIdString(payload.M, CFG.MountIdMaxLength) then
		return refuse("payload")
	end
	local d = payload.D
	if typeof(d) ~= "Vector3" then
		return refuse("payload")
	end
	if not finiteV(d) then
		if AntiExploitService and AntiExploitService.Strike then
			pcall(AntiExploitService.Strike, player, "afire_bad_dir")
		end
		return refuse("payload")
	end
	if RateLimitService and not RateLimitService.Allow(player, "air_fire", CFG.RemoteRate, CFG.RemoteBurst) then
		return refuse("rate")
	end
	if not CFG.LiveFor(player.UserId) then
		return refuse("off")
	end
	local model, seat = VehicleHealth.GetSeatedVehicle(player)
	if model == nil or seat == nil then
		return refuse("not_seated")
	end
	if seat:GetAttribute("WE_SeatRole") ~= "Driver" then
		return refuse("not_pilot")
	end
	local rec = VehicleHealth.Get(model)
	if rec == nil then
		return refuse("no_vehicle")
	end
	if rec.OwnerUserId ~= player.UserId then
		return refuse("not_owner")
	end
	if rec.Destroyed then
		return refuse("wrecked")
	end
	if rec.Trial then
		return refuse("trial")
	end
	local loadout = CFG.LoadoutFor(model:GetAttribute("VehicleId"))
	if loadout == nil then
		return refuse("unarmed")
	end
	local mountId = payload.M :: string
	local def = CFG.Weapon(mountId)
	if def == nil or table.find(loadout, mountId) == nil then
		return refuse("not_in_loadout")
	end
	local chassis = model.PrimaryPart
	if chassis == nil then
		return refuse("no_vehicle")
	end
	local st = slotFor(model, mountId, def)
	local now = clock()
	if st.ReloadUntil > 0 then
		if now < st.ReloadUntil then
			return refuse("reloading")
		end
		st.Ammo = def.Magazine.Size
		st.ReloadUntil = 0
		writeAttrs(model, mountId, st, def)
	end
	if st.Ammo <= 0 then
		startReload(model, mountId, st, def)
		return refuse("reloading")
	end
	if now - st.LastFire < CFG.FireIntervalSlack / math.max(def.Rate, 0.01) then
		return refuse("cooldown")
	end
	if d.Magnitude < 0.05 then
		return refuse("direction")
	end
	local dir = clampToArc(d.Unit, chassis.CFrame.LookVector, def.ArcDeg)
	local take = math.min(math.max(1, math.floor(tonumber(def.ShotsPerFire) or 1)), st.Ammo)
	if def.Kind ~= "Gun" and AirOrdnance.AtCap(player.UserId, take) then
		return refuse("busy")
	end
	-- accepted: spend first, then resolve
	st.LastFire = now
	st.Ammo -= take
	writeAttrs(model, mountId, st, def)
	if st.Ammo <= 0 then
		startReload(model, mountId, st, def)
	end
	stats.Accepted += 1
	lastReason[player.UserId] = "ok"
	if CombatService and CombatService.EndNoviceShield then
		pcall(CombatService.EndNoviceShield, player, "fire")
	end
	local inputClass: string? = nil
	if typeof(payload.I) == "string" and (AimAssistConfig.Aircraft.Classes :: any)[payload.I] ~= nil then
		inputClass = payload.I
	elseif CombatService and CombatService.InputClass then
		local ok, c = pcall(CombatService.InputClass, player)
		inputClass = if ok and typeof(c) == "string" then c else nil
	end
	if def.Kind == "Gun" then
		fireGun(player, model, def, mountId, dir, inputClass)
	elseif def.Kind == "Rocket" or def.Kind == "Missile" then
		local speed = tonumber(def.Speed) or 200
		for i = 1, take do
			st.Pod += 1
			local origin = muzzle(model, def, st.Pod)
			if origin then
				local target: BasePart? = nil
				local alive: (() -> boolean)? = nil
				if def.Kind == "Missile" then
					target, alive = AirWeaponService._PickLock(player, model, origin, dir, def, filterFor(player, model))
					if target then
						stats.Locks += 1
					end
				end
				launchRound(player, model, def, mountId, origin, dir * speed, target, alive)
			end
		end
	elseif def.Kind == "Bomb" then
		local gap = math.max(0, tonumber(def.ShotIntervalSeconds) or 0)
		for i = 1, take do
			st.Pod += 1
			local pod = st.Pod
			if i == 1 or gap <= 0 then
				dropBomb(player, model, def, mountId, pod)
			else
				task.delay(gap * (i - 1), dropBomb, player, model, def, mountId, pod)
			end
		end
	end
	return true, "ok"
end

-- ── lifecycle ─────────────────────────────────────────────────────────────────────────────────────────────────

local function markLive(player: Player)
	player:SetAttribute(CFG.LiveAttribute, if CFG.LiveFor(player.UserId) then true else nil)
end

function AirWeaponService.Init(deps: { [string]: any })
	DataService = deps.DataService
	RemoteSetup = deps.RemoteSetup
	RateLimitService = deps.RateLimitService
	AntiExploitService = deps.AntiExploitService
	CombatService = deps.CombatService
	GateDefenseService = deps.GateDefenseService
	ClanService = deps.ClanService
	Players.PlayerAdded:Connect(markLive)
	for _, p in ipairs(Players:GetPlayers()) do
		markLive(p)
	end
	Players.PlayerRemoving:Connect(function(p: Player)
		AirOrdnance.ForgetOwner(p.UserId)
		lastReason[p.UserId] = nil
	end)
	local remote: Instance? = if RemoteSetup then RemoteSetup.Get(Constants.RemoteNames.RequestVehicleFire) else nil
	if remote and remote:IsA("RemoteEvent") then
		local ev = remote :: RemoteEvent
		ev.OnServerEvent:Connect(function(player: Player, payload: any)
			local ok, res = pcall(function()
				AirWeaponService.RequestFire(player, payload)
			end)
			if not ok then
				warn("[AirWeaponService] fire error:", tostring(res))
			end
		end)
	else
		warn("[AirWeaponService] RequestVehicleFire remote missing: aircraft weapons stay off")
	end
	print(string.format("[WAR EMPIRE] AirWeaponService ready (WeaponsLive=%s; owner playtest account always live)", tostring(CFG.WeaponsLive)))
end

-- tests
function AirWeaponService._Stats(): { [string]: number }
	return stats
end
function AirWeaponService._LastReason(userId: number): string?
	return lastReason[userId]
end
function AirWeaponService._SetRandom(r: Random)
	rng = r
end
function AirWeaponService._Slot(model: Model, mountId: string): SlotState?
	local s = states[model]
	return if s then s.Slots[mountId] else nil
end
function AirWeaponService._Deps(): any
	return GateDefenseService
end

return AirWeaponService
