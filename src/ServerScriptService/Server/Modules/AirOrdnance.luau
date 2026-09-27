--!strict
--[[ Aircraft ordnance (AirWeaponService): server kinematic rockets, homing missiles and falling bombs.

	No parts on the server. Each round is a record stepped at AircraftWeaponConfig.Ordnance.StepHz by one shared
	thread that only runs while something is in flight: pos += v dt + 1/2 g dt^2, v += g dt, ONE ray per step along
	the segment (Exclude filter: the firing aircraft, the pilot, squad units; IgnoreWater). A homing round turns its
	velocity toward its Target part by at most TurnRateDeg x dt per step (the target was chosen by the server; a
	target that is gone, dead or wrecked is dropped and the round flies straight) and detonates within ProximityFuse
	of it. The first hit, the fuse, or t = MaxSeconds calls OnImpact once (pcall'd).
	Caps: MaxLivePerPlayer / MaxLiveServer (AtCap is checked before any ammo is spent). ]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local AircraftWeaponConfig = require(Shared.Configs.AircraftWeaponConfig)

local AirOrdnance = {}

export type Spec = {
	OwnerUserId: number,
	Origin: Vector3,
	Velocity: Vector3,
	GravityFactor: number,
	MaxSeconds: number,
	Filter: { Instance },
	Target: BasePart?, -- homing target (server-chosen)
	IsTargetAlive: (() -> boolean)?,
	TurnRateDeg: number?,
	ProximityFuse: number?,
	OnImpact: (pos: Vector3, hit: RaycastResult?, rec: Record) -> (),
}

export type Record = {
	Id: number,
	OwnerUserId: number,
	Pos: Vector3,
	V: Vector3,
	G: Vector3,
	T: number,
	At: number,
	MaxSeconds: number,
	Params: RaycastParams,
	Target: BasePart?,
	IsTargetAlive: (() -> boolean)?,
	TurnRad: number,
	Fuse: number,
	OnImpact: (pos: Vector3, hit: RaycastResult?, rec: Record) -> (),
	Done: boolean,
	Steps: number,
}

local live: { [number]: Record } = {}
local liveTotal = 0
local liveBy: { [number]: number } = {}
local serial = 0
local running = false

local function cfg()
	return AircraftWeaponConfig.Ordnance
end

local function gravity(): number
	local ok, g = pcall(function()
		return (Workspace :: any).Gravity
	end)
	if ok and typeof(g) == "number" and g == g and g >= 0 and g < 1e4 then
		return g
	end
	return 196.2
end

function AirOrdnance.LiveFor(userId: number): number
	return liveBy[userId] or 0
end

function AirOrdnance.LiveTotal(): number
	return liveTotal
end

-- true when `n` more rounds from `userId` would pass a cap
function AirOrdnance.AtCap(userId: number, n: number?): boolean
	local c = cfg()
	local k = n or 1
	return AirOrdnance.LiveFor(userId) + k > c.MaxLivePerPlayer or liveTotal + k > c.MaxLiveServer
end

local function finish(rec: Record, pos: Vector3, hit: RaycastResult?)
	if rec.Done then
		return
	end
	rec.Done = true
	live[rec.Id] = nil
	liveTotal = math.max(0, liveTotal - 1)
	local n = (liveBy[rec.OwnerUserId] or 1) - 1
	if n > 0 then
		liveBy[rec.OwnerUserId] = n
	else
		liveBy[rec.OwnerUserId] = nil
	end
	xpcall(rec.OnImpact, function(err: any)
		warn("[AirOrdnance] impact error:", err)
	end, pos, hit, rec)
end

-- turn `v` toward `want` (unit) by at most `maxRad`, keeping its speed
local function steer(v: Vector3, want: Vector3, maxRad: number): Vector3
	local speed = v.Magnitude
	if speed < 1e-3 then
		return want * speed
	end
	local cur = v / speed
	local d = math.clamp(cur:Dot(want), -1, 1)
	local ang = math.acos(d)
	if ang <= maxRad or ang < 1e-4 then
		return want * speed
	end
	local perp = want - cur * d
	if perp.Magnitude < 1e-6 then
		return v
	end
	perp = perp.Unit
	return (cur * math.cos(maxRad) + perp * math.sin(maxRad)) * speed
end

local function targetOk(rec: Record): boolean
	local tgt = rec.Target
	if tgt == nil or tgt.Parent == nil then
		return false
	end
	local fn = rec.IsTargetAlive
	if fn then
		local ok, alive = pcall(fn)
		if not ok or alive ~= true then
			return false
		end
	end
	return true
end

local function step(rec: Record, now: number)
	if rec.Done then
		return
	end
	local dt = math.min(now - rec.At, rec.MaxSeconds - rec.T)
	if not (dt > 0) then
		if rec.T >= rec.MaxSeconds then
			finish(rec, rec.Pos, nil)
		end
		return
	end
	rec.At = now
	rec.Steps += 1
	if rec.Target ~= nil then
		if targetOk(rec) then
			local tp = (rec.Target :: BasePart).Position
			local to = tp - rec.Pos
			if to.Magnitude <= rec.Fuse then
				finish(rec, rec.Pos, nil)
				return
			end
			rec.V = steer(rec.V, to.Unit, rec.TurnRad * dt)
		else
			rec.Target = nil -- lost: straight on
		end
	end
	local p1 = rec.Pos + rec.V * dt + rec.G * (0.5 * dt * dt)
	rec.V += rec.G * dt
	local seg = p1 - rec.Pos
	if seg.Magnitude > 1e-3 then
		local res = Workspace:Raycast(rec.Pos, seg, rec.Params)
		if res then
			rec.Pos = res.Position
			finish(rec, res.Position, res)
			return
		end
	end
	rec.Pos = p1
	rec.T += dt
	if rec.Target ~= nil and targetOk(rec) and ((rec.Target :: BasePart).Position - p1).Magnitude <= rec.Fuse then
		finish(rec, p1, nil)
		return
	end
	if rec.T >= rec.MaxSeconds - 1e-6 then
		finish(rec, p1, nil)
	end
end

-- advance every live round to `now` (the runner thread; tests may call it directly)
function AirOrdnance.StepAll(now: number?)
	local t = now or os.clock()
	local list: { Record } = {}
	for _, rec in pairs(live) do
		table.insert(list, rec)
	end
	for _, rec in ipairs(list) do
		step(rec, t)
	end
end

local function runner()
	local dt = 1 / math.clamp(tonumber(cfg().StepHz) or 20, 5, 60)
	while liveTotal > 0 do
		task.wait(dt)
		xpcall(AirOrdnance.StepAll, function(err: any)
			warn("[AirOrdnance] step error:", err)
		end, os.clock())
	end
	running = false
end

-- launch one round; nil when a cap refuses it or the spec is not finite
function AirOrdnance.Launch(spec: Spec): Record?
	if AirOrdnance.AtCap(spec.OwnerUserId, 1) then
		return nil
	end
	local o, v = spec.Origin, spec.Velocity
	if not (o.Magnitude < 1e7 and v.Magnitude < 1e5) then -- NaN / inf fail here
		return nil
	end
	serial = (serial % 1000000) + 1
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = spec.Filter
	params.IgnoreWater = true
	local gf = math.clamp(tonumber(spec.GravityFactor) or 0, 0, 5)
	local rec: Record = {
		Id = serial,
		OwnerUserId = spec.OwnerUserId,
		Pos = o,
		V = v,
		G = Vector3.new(0, -gravity() * gf, 0),
		T = 0,
		At = os.clock(),
		MaxSeconds = math.clamp(tonumber(spec.MaxSeconds) or 1, 0.05, 12),
		Params = params,
		Target = spec.Target,
		IsTargetAlive = spec.IsTargetAlive,
		TurnRad = math.rad(math.clamp(tonumber(spec.TurnRateDeg) or 0, 0, 720)),
		Fuse = math.clamp(tonumber(spec.ProximityFuse) or 0, 0, 30),
		OnImpact = spec.OnImpact,
		Done = false,
		Steps = 0,
	}
	live[rec.Id] = rec
	liveTotal += 1
	liveBy[rec.OwnerUserId] = (liveBy[rec.OwnerUserId] or 0) + 1
	if not running then
		running = true
		task.spawn(runner)
	end
	return rec
end

-- drop an owner's rounds without an impact (player left)
function AirOrdnance.ForgetOwner(userId: number)
	for id, rec in pairs(live) do
		if rec.OwnerUserId == userId then
			rec.Done = true
			live[id] = nil
			liveTotal = math.max(0, liveTotal - 1)
		end
	end
	liveBy[userId] = nil
end

return AirOrdnance
