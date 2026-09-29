--!strict
--[[
	claude-bud PREMIUM (2026-09-29): the Robux-only vehicles' weapons (VehicleConfig.Premium). Server-authoritative:
	the client only says "fire" / "missile" with its aim direction. The server:
	  * finds the premium vehicle the player DRIVES (his own: OwnerUserId, a Premium def, the pass live for him through
	    MonetizationConfig.SkuLiveFor or the playtest owner), rate-limits (MaxRequestHz, then the gun's FireRate / the
	    missile Cooldown per vehicle);
	  * clamps the aim to the gun's ConeDeg around the vehicle's nose, casts from the vehicle's muzzle itself (its own model
	    and his character excluded: real line of sight, real Range), and never trusts a client target;
	  * friendly fire off: himself, his own vehicles and his clan allies take nothing (direct hits skipped here; splash
	    through CombatService.ApplyRadiusDamage's own ally rule); every hit goes through CombatService.ApplyHit /
	    ApplyRadiusDamage, so PvP-off, the spawn and novice shields, vehicle spawn protection and occupant rules all hold;
	  * missiles: the server picks the lock (nearest enemy player or vehicle inside LockConeDeg of the aim, within
	    LockRange, in line of sight), flies them itself at StepHz with a TurnRateDeg limit (dodgeable), explodes within
	    ProximityStuds / on a hit / after Lifetime.
	Effects: one UnreliableRemoteEvent (PremiumWeaponFx) to every client: { K = "G" gun | "M" missile launch | "X" boom }.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local Constants = require(Shared.Constants)
local VehicleConfig = require(Shared.Configs.VehicleConfig)
local MonetizationConfig = require(Shared.Configs.MonetizationConfig)
local AdminConfig = require(Shared.Configs.AdminConfig)
local WorldLabel = require(Shared.Util.WorldLabel)

local PremiumWeaponService = {}

local P: any = (VehicleConfig :: any).Premium
local deps: { [string]: any } = {}
local lastFire: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local lastMissile: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local fxRemote: UnreliableRemoteEvent? = nil

type Missile = {
	Part: BasePart,
	Pos: Vector3,
	Dir: Vector3,
	Target: BasePart?,
	Born: number,
	Owner: Player,
	Vehicle: Model,
}
local missiles: { Missile } = {}
local missileFolder: Folder? = nil

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
rayParams.RespectCanCollide = true

local function fx(data: { [string]: any })
	if fxRemote then
		pcall(function()
			(fxRemote :: UnreliableRemoteEvent):FireAllClients(data)
		end)
	end
end

local function vehicleModelOf(inst: Instance?): Model?
	local node = inst
	while node and node ~= Workspace do
		if node:IsA("Model") and node:GetAttribute("VehicleId") ~= nil then
			return node
		end
		node = node.Parent
	end
	return nil
end

-- the premium vehicle this player drives right now (all checks), and its def
local function drivenPremium(player: Player): (Model?, any, BasePart?)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if seat == nil or seat.Name ~= "DriverSeat" or hum == nil or hum.Health <= 0 then
		return nil, nil, nil
	end
	local model = vehicleModelOf(seat)
	if model == nil or model:GetAttribute("OwnerUserId") ~= player.UserId then
		return nil, nil, nil
	end
	local def: any = (VehicleConfig.Vehicles :: any)[model:GetAttribute("VehicleId")]
	local prem = def and def.Premium
	if prem == nil or typeof(prem.Gun) ~= "string" then
		return nil, nil, nil
	end
	local ownerTest = AdminConfig.IsPlaytestOwner(player.UserId) and (MonetizationConfig :: any).LaunchAll ~= true -- claude-bud JOB 12
	if not (MonetizationConfig.SkuLiveFor(player.UserId, tostring(prem.PassKey)) or ownerTest) then
		return nil, nil, nil
	end
	return model, def, seat
end

local function unitDir(v: any): Vector3?
	if typeof(v) ~= "Vector3" then
		return nil
	end
	local m = (v :: Vector3).Magnitude
	if m ~= m or m < 0.1 or m == math.huge then
		return nil
	end
	return (v :: Vector3) / m
end

-- `dir` turned toward `fwd` until it is at most `coneDeg` off it
local function clampCone(fwd: Vector3, dir: Vector3, coneDeg: number): Vector3
	local cosA = math.clamp(fwd:Dot(dir), -1, 1)
	local maxA = math.rad(coneDeg)
	if math.acos(cosA) <= maxA then
		return dir
	end
	local perp = dir - fwd * cosA
	if perp.Magnitude < 1e-4 then
		return fwd
	end
	return (fwd * math.cos(maxA) + perp.Unit * math.sin(maxA)).Unit
end

local function muzzle(model: Model, seat: BasePart): Vector3
	local half = tonumber(model:GetAttribute("WE_HalfLength")) or 6
	return seat.Position + seat.CFrame.UpVector * 2 + seat.CFrame.LookVector * (half + 1)
end

-- whose is this hit? (a player's character or a vehicle's owner)
local function ownerOf(inst: Instance): Player?
	local veh = vehicleModelOf(inst)
	if veh then
		local uid = veh:GetAttribute("OwnerUserId")
		return if typeof(uid) == "number" then Players:GetPlayerByUserId(uid) else nil
	end
	local m = inst:FindFirstAncestorOfClass("Model")
	return if m then Players:GetPlayerFromCharacter(m) else nil
end

local function friendly(attacker: Player, inst: Instance): boolean
	local o = ownerOf(inst)
	if o == nil then
		return false
	end
	if o == attacker then
		return true
	end
	local cs = deps.CombatService
	return cs ~= nil and cs.IsClanAlly ~= nil and cs.IsClanAlly(attacker, o) == true
end

local function exclude(model: Model, player: Player, extra: Instance?)
	local list: { Instance } = { model }
	if player.Character then
		table.insert(list, player.Character)
	end
	if extra then
		table.insert(list, extra)
	end
	rayParams.FilterDescendantsInstances = list
end

local function hit(player: Player, model: Model, inst: Instance, pos: Vector3, amount: number, weaponId: string, class: string, vsInf: number)
	local cs = deps.CombatService
	if cs == nil or cs.ApplyHit == nil or friendly(player, inst) then
		return
	end
	pcall(cs.ApplyHit, player, inst, amount, {
		WeaponId = weaponId,
		Class = class,
		VsInfantryMult = vsInf,
		Vehicle = model,
		HitPos = pos,
	})
end

local function splash(player: Player, model: Model, pos: Vector3, radius: number, amount: number, weaponId: string, vsInf: number)
	local cs = deps.CombatService
	if radius <= 0 or cs == nil or cs.ApplyRadiusDamage == nil then
		return
	end
	pcall(cs.ApplyRadiusDamage, player, pos, radius, amount, {
		WeaponId = weaponId,
		Vehicle = model,
		RequireLos = true,
		IgnoreModel = model,
		VsInfantryMult = vsInf,
	})
end

local function fire(player: Player, aim: any)
	local model, def, seat = drivenPremium(player)
	if model == nil or seat == nil then
		return
	end
	local gunId = def.Premium.Gun
	local gun = P.Guns[gunId]
	local dir = unitDir(aim)
	if gun == nil or dir == nil then
		return
	end
	local t = os.clock()
	if t - (lastFire[model] or -math.huge) < 0.9 / math.max(0.1, gun.FireRate) then
		return
	end
	lastFire[model] = t
	dir = clampCone(seat.CFrame.LookVector, dir :: Vector3, gun.ConeDeg)
	local origin = muzzle(model, seat)
	exclude(model, player, nil)
	local r = Workspace:Raycast(origin, (dir :: Vector3) * gun.Range, rayParams)
	local at = if r then r.Position else origin + (dir :: Vector3) * gun.Range
	local wid = "V_Prem_" .. gunId
	if r then
		hit(player, model, r.Instance, at, gun.Damage, wid, gun.Class, gun.VsInfantryMult)
		splash(player, model, at, gun.Splash, gun.Damage * 0.5, wid, gun.VsInfantryMult)
	end
	fx({ K = "G", G = gunId, F = origin, T = at })
end

-- the lock: nearest enemy player (root) or vehicle (primary part) inside the cone of `dir`, within LockRange, in sight
local function pickTarget(player: Player, model: Model, origin: Vector3, dir: Vector3): BasePart?
	local M = P.Missile
	local cosCone = math.cos(math.rad(M.LockConeDeg))
	local best: BasePart? = nil
	local bestScore = math.huge
	local function consider(part: BasePart, owner: Player?)
		if owner == player or (owner and deps.CombatService and deps.CombatService.IsClanAlly and deps.CombatService.IsClanAlly(player, owner)) then
			return
		end
		local d = part.Position - origin
		local dist = d.Magnitude
		if dist < 1 or dist > M.LockRange then
			return
		end
		local c = d.Unit:Dot(dir)
		if c < cosCone then
			return
		end
		local score = dist * (2 - c)
		if score >= bestScore then
			return
		end
		exclude(model, player, part:FindFirstAncestorOfClass("Model"))
		if Workspace:Raycast(origin, d, rayParams) ~= nil then
			return
		end
		best, bestScore = part, score
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			local ch = p.Character
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			if root and root:IsA("BasePart") and hum and hum.Health > 0 then
				consider(root, p)
			end
		end
	end
	local folder = Workspace:FindFirstChild("WarEmpireVehicles")
	if folder then
		for _, v in ipairs(folder:GetChildren()) do
			if v ~= model and v:IsA("Model") and v.PrimaryPart then
				local uid = v:GetAttribute("OwnerUserId")
				consider(v.PrimaryPart :: BasePart, if typeof(uid) == "number" then Players:GetPlayerByUserId(uid) else nil)
			end
		end
	end
	return best
end

local function launch(player: Player, aim: any)
	local model, def, seat = drivenPremium(player)
	if model == nil or seat == nil then
		return
	end
	local M = P.Missile
	local dir = unitDir(aim)
	if dir == nil then
		return
	end
	local t = os.clock()
	if t - (lastMissile[model] or -math.huge) < M.Cooldown then
		return
	end
	lastMissile[model] = t
	local gun = P.Guns[def.Premium.Gun]
	dir = clampCone(seat.CFrame.LookVector, dir :: Vector3, if gun then gun.ConeDeg else 45)
	local origin = muzzle(model, seat)
	local target = pickTarget(player, model, origin, dir :: Vector3)
	if missileFolder == nil or missileFolder.Parent == nil then
		local f = Instance.new("Folder")
		f.Name = "WE_PremiumMissiles"
		f.Parent = Workspace
		missileFolder = f
	end
	local part = Instance.new("Part")
	part.Name = "PremiumMissile"
	part.Size = Vector3.new(0.7, 0.7, 3)
	part.Color = P.Look.TrailColor
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = CFrame.lookAt(origin, origin + (dir :: Vector3))
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0, 1.5)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, 0.3, 1.5)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 240, 200))
	trail.Lifetime = 0.35
	trail.Parent = part
	part.Parent = missileFolder
	table.insert(missiles, { Part = part :: BasePart, Pos = origin, Dir = dir :: Vector3, Target = target, Born = t, Owner = player, Vehicle = model })
	fx({ K = "M", F = origin, L = target ~= nil })
end

local function boom(m: Missile, at: Vector3, direct: Instance?)
	local M = P.Missile
	if direct then
		hit(m.Owner, m.Vehicle, direct, at, M.Damage, "V_Prem_Missile", M.Class, M.VsInfantryMult)
	end
	splash(m.Owner, m.Vehicle, at, M.Splash, M.Damage * 0.5, "V_Prem_Missile", M.VsInfantryMult)
	fx({ K = "X", T = at })
	m.Part:Destroy()
end

local function step(dt: number)
	local M = P.Missile
	local now = os.clock()
	local maxTurn = math.rad(M.TurnRateDeg) * dt
	local i = 1
	while i <= #missiles do
		local m = missiles[i]
		local done = false
		local tgt = m.Target
		if tgt and (tgt.Parent == nil or not tgt:IsDescendantOf(Workspace)) then
			m.Target = nil
			tgt = nil
		end
		if tgt then
			local want = tgt.Position - m.Pos
			if want.Magnitude > 0.1 then
				m.Dir = clampCone(m.Dir, want.Unit, math.deg(maxTurn)) -- the turn-rate limit: dodgeable
			end
		end
		local nextPos = m.Pos + m.Dir * M.Speed * dt
		exclude(m.Vehicle, m.Owner, m.Part)
		local r = Workspace:Raycast(m.Pos, nextPos - m.Pos, rayParams)
		if r then
			boom(m, r.Position, r.Instance)
			done = true
		elseif tgt and (tgt.Position - nextPos).Magnitude <= M.ProximityStuds then
			boom(m, tgt.Position, tgt)
			done = true
		elseif now - m.Born >= M.Lifetime then
			fx({ K = "X", T = nextPos })
			m.Part:Destroy()
			done = true
		else
			m.Pos = nextPos
			m.Part.CFrame = CFrame.lookAt(nextPos, nextPos + m.Dir)
		end
		if done then
			table.remove(missiles, i)
		else
			i += 1
		end
	end
end

-- VehicleService calls this on a premium spawn: the weapon marker for the client + the gold look for everyone
function PremiumWeaponService.OnSpawn(model: Model, def: any, player: Player)
	local prem = def and def.Premium
	if prem == nil then
		return
	end
	model:SetAttribute("WE_PremiumGun", prem.Gun)
	model:SetAttribute("WE_Premium", true)
	local primary = model.PrimaryPart
	if primary == nil then
		return
	end
	local half = tonumber(model:GetAttribute("WE_HalfLength")) or 6
	local a0 = Instance.new("Attachment")
	a0.Name = "WE_PremiumTrail0"
	a0.Position = Vector3.new(0, 0.6, half)
	a0.Parent = primary
	local a1 = Instance.new("Attachment")
	a1.Name = "WE_PremiumTrail1"
	a1.Position = Vector3.new(0, 2.4, half)
	a1.Parent = primary
	local trail = Instance.new("Trail")
	trail.Name = "WE_PremiumTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(P.Look.TrailColor)
	trail.Lifetime = P.Look.TrailLifetime
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Parent = primary
	pcall(function()
		local bb = WorldLabel.Create(primary, P.Look.Badge, {
			Name = "WE_PremiumBadge",
			Color = P.Look.TrailColor,
			MaxDistance = P.Look.BadgeMaxDistance,
		})
		bb.AlwaysOnTop = false
	end)
end

function PremiumWeaponService.Init(d: { [string]: any })
	deps = d
	local RS = d.RemoteSetup
	if RS == nil or P == nil then
		return
	end
	local req = RS.Get(Constants.RemoteNames.RequestPremiumWeapon)
	local fxr = RS.Get(Constants.RemoteNames.PremiumWeaponFx)
	if fxr and fxr:IsA("UnreliableRemoteEvent") then
		fxRemote = fxr
	end
	if req and req:IsA("RemoteEvent") then
		(req :: RemoteEvent).OnServerEvent:Connect(function(player: Player, action: any, aim: any)
			local rl = d.RateLimitService
			if rl and not rl.Allow(player, "premium_weapon", P.MaxRequestHz, P.MaxRequestHz) then
				return
			end
			if action == "Fire" then
				fire(player, aim)
			elseif action == "Missile" then
				launch(player, aim)
			end
		end)
	end
	local acc = 0
	local stepDt = 1 / math.max(5, P.Missile.StepHz)
	RunService.Heartbeat:Connect(function(dt)
		if #missiles == 0 then
			acc = 0
			return
		end
		acc = math.min(acc + dt, stepDt * 3) -- never more than 3 catch-up steps after a hitch
		while acc >= stepDt do
			acc -= stepDt
			step(stepDt)
		end
	end)
end

return PremiumWeaponService
