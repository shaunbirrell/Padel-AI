--!strict
--[[ W2 Combat Core (contracts §3.4, mobile plan P1-5, reusable parts G-c): server kinematic projectiles.

	No parts on the server: each projectile is a record stepped at CombatFeelConfig.Projectile.StepHz (20) by one
	shared thread that only runs while something is in flight. The path is the same closed form the client draws
	from the WeaponFx "L" event: pos(t) = O + V t + 1/2 g t^2, g = (0, -Workspace.Gravity * GravityFactor, 0). Each
	step casts ONE ray along the segment pos(t0) -> pos(t1) with the shot's Exclude filter (IgnoreWater = true). The
	first hit, or t = MaxSeconds, calls OnImpact once (pcall'd).

	Caps: MaxLivePerPlayer (3) per owner and MaxLiveServer (24) in total; Launch returns nil when either is reached
	(CombatService refuses the shot before any ammo is spent). ]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local CombatFeelConfig = require(Shared.Configs.CombatFeelConfig)

local Projectile = {}

export type Spec = {
	OwnerUserId: number,
	Origin: Vector3, -- spawn point (already SpawnForwardStuds ahead of the muzzle / origin)
	From: Vector3?, -- the shot origin behind Origin: the first ray starts here (W2 verify: no tunnelling through a wall)
	Velocity: Vector3,
	GravityFactor: number,
	MaxSeconds: number,
	Filter: { Instance }, -- Exclude list (shooter, their seated vehicle, the squad folder)
	OnImpact: (pos: Vector3, hit: RaycastResult?, rec: Record) -> (),
}

export type Record = {
	Id: number,
	OwnerUserId: number,
	O: Vector3,
	V: Vector3,
	G: Vector3,
	Pos: Vector3,
	T: number,
	StartAt: number,
	MaxSeconds: number,
	Params: RaycastParams,
	OnImpact: (pos: Vector3, hit: RaycastResult?, rec: Record) -> (),
	Done: boolean,
}

local live: { [number]: Record } = {}
local liveTotal = 0
local liveBy: { [number]: number } = {}
local serial = 0
local running = false

local function gravity(): number
	local ok, g = pcall(function()
		return (Workspace :: any).Gravity
	end)
	if ok and typeof(g) == "number" and g == g and g >= 0 and g < 1e4 then
		return g
	end
	return 196.2
end

local function cfg()
	return CombatFeelConfig.Projectile
end

function Projectile.LiveFor(userId: number): number
	return liveBy[userId] or 0
end

function Projectile.LiveTotal(): number
	return liveTotal
end

-- true when a new projectile from `userId` would be refused by the caps
function Projectile.AtCap(userId: number): boolean
	local c = cfg()
	return Projectile.LiveFor(userId) >= c.MaxLivePerPlayer or liveTotal >= c.MaxLiveServer
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
		warn("[Projectile] impact error:", err)
	end, pos, hit, rec)
end

local function step(rec: Record, now: number)
	if rec.Done then
		return
	end
	local t1 = math.min(math.max(now - rec.StartAt, rec.T), rec.MaxSeconds)
	local pos1 = rec.O + rec.V * t1 + rec.G * (0.5 * t1 * t1)
	local seg = pos1 - rec.Pos
	if seg.Magnitude > 1e-3 then
		local res = Workspace:Raycast(rec.Pos, seg, rec.Params)
		if res then
			rec.Pos = res.Position
			finish(rec, res.Position, res)
			return
		end
	end
	rec.Pos = pos1
	rec.T = t1
	if t1 >= rec.MaxSeconds then
		finish(rec, pos1, nil)
	end
end

-- Advance every live projectile to `now` (the runner thread; tests may call it directly)
function Projectile.StepAll(now: number?)
	local t = now or os.clock()
	for _, rec in pairs(live) do
		step(rec, t)
	end
end

local function runner()
	local dt = 1 / math.clamp(tonumber(cfg().StepHz) or 20, 5, 60)
	while liveTotal > 0 do
		task.wait(dt)
		xpcall(Projectile.StepAll, function(err: any)
			warn("[Projectile] step error:", err)
		end, os.clock())
	end
	running = false
end

--[[ Launch one projectile. Returns its record, or nil when a cap refuses it (or the spec is not finite). ]]
function Projectile.Launch(spec: Spec): Record?
	if Projectile.AtCap(spec.OwnerUserId) then
		return nil
	end
	local o, v = spec.Origin, spec.Velocity
	if not (o.Magnitude < 1e7 and v.Magnitude < 1e5) then -- NaN / inf fail here
		return nil
	end
	local from = spec.From
	local start: Vector3 = if typeof(from) == "Vector3" and (from - o).Magnitude < 20 then from else o -- NaN fails the < 20
	serial = (serial % 1000000) + 1
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = spec.Filter
	params.IgnoreWater = true
	local gf = math.clamp(tonumber(spec.GravityFactor) or 0, 0, 5)
	local rec: Record = {
		Id = serial,
		OwnerUserId = spec.OwnerUserId,
		O = o,
		V = v,
		G = Vector3.new(0, -gravity() * gf, 0),
		Pos = start,
		T = 0,
		StartAt = os.clock(),
		MaxSeconds = math.clamp(tonumber(spec.MaxSeconds) or 1, 0.05, 10),
		Params = params,
		OnImpact = spec.OnImpact,
		Done = false,
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

-- Remove an owner's projectiles without an impact (player left)
function Projectile.ForgetOwner(userId: number)
	for id, rec in pairs(live) do
		if rec.OwnerUserId == userId then
			rec.Done = true
			live[id] = nil
			liveTotal = math.max(0, liveTotal - 1)
		end
	end
	liveBy[userId] = nil
end

return Projectile
