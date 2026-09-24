--!strict
--[[
	Phase 4/7 — Vehicles & garage (server-authoritative).
	Validates ownership, level, structure, prestige/rebirth flags, cash, cooldown.
	Spawns Part kits by VehicleDef.KitFamily (scalable to 100+).
	Visual kits v2: multi-part silhouettes (cabin/wheels/turret/lights/exhaust; air rotors+disc; naval wake).
	Optional MeshAssetId reserved for future MeshPart swap (0 = Part kit).

	v70 driving (cars, helicopters, planes, boats). Spec: scratchpad vehicles/spec.md.
	  * The DRIVER'S CLIENT simulates: VehicleDriveClient turns input into a target velocity and
	    orientation every frame and writes the two movers this service builds on the Chassis
	    (WE_DriveLV LinearVelocity PerAxis, WE_DriveAO AlignOrientation OneAttachment).
	  * This service builds the vehicle unparented, chooses a spawn from its footprint (helipad deck,
	    runway, dock basin / sea, pads), hands network ownership to the owner when they sit, runs the
	    idle laws (10 Hz) for parked / abandoned vehicles, a Car/Boat fallback copy of the client law
	    (startGroundDrive) when the client module never says Hello, and 5 Hz checks (speed, altitude,
	    teleport, bounds, boats over WE_Water). A violation takes ownership back and puts the vehicle
	    at its last valid position; repeated hard violations recall it (one AntiExploit strike).
	  * The server never accepts positions or velocities from the client: VehicleDriveInput only
	    carries {K="Hello"|"Bye", V=<VehicleId>, P=<protocol>}, the input stream {K="In", V, T, S, L}
	    (clamped to [-1, 1]), {K="Stuck", V, ...} and {K="Exit", V}.
	  * Judge fix (jeep "doesn't drive"): whoever simulates owns every assembly (chassis + each hinge wheel).
	    A watchdog proves in each sit that the client-simulated car really moves while the driver pushes;
	    if not, the server takes ownership and drives it from the input stream (Car/Boat), logs one
	    NO-DRIVE line, and debug users (Drive.Debug) get a WE_Diag attribute + periodic server lines.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local VehicleConfig = require(Shared.Configs.VehicleConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)
local BaseConfig = require(Shared.Configs.BaseConfig)
local BaseLayoutConfig = require(Shared.Configs.BaseLayoutConfig)

type VehicleDef = VehicleConfig.VehicleDef

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)
local VisualAssetService = require(script.Parent.VisualAssetService)

local VehicleService = {}

local Drive = VehicleConfig.Drive
local CarCfg = Drive.Modes.Car
local HeliCfg = Drive.Modes.Heli
local PlaneCfg = Drive.Modes.Plane
local BoatCfg = Drive.Modes.Boat
local Valid = Drive.Validation
local WaterCfg = Drive.Water
local SpawnCfg = Drive.Spawn
local ResyncCfg = Drive.Resync
local W = Drive.Watchdog
local DBG = Drive.Debug

local debugUserSet: { [number]: boolean } = {}
for _, uid in ipairs(DBG.UserIds) do
	debugUserSet[uid] = true
end
local function isDebugUser(userId: number): boolean
	return DBG.All == true or debugUserSet[userId] == true
end

-- ── Types (law protocol shared with VehicleDriveClient; see spec §2) ─────────────────────────────
export type DriveInput = { Throttle: number, Steer: number, Lift: number, Strafe: number }
export type DriveSense = {
	Position: Vector3,
	Velocity: Vector3,
	Yaw: number,
	UpY: number,
	AGL: number,
	WaterY: number?,
	WaterNear: boolean?,
	WaterFar: boolean?,
	Time: number,
}
export type DriveHud = { Speed: number, Alt: number?, Throttle: number?, Tag: string? }
export type DriveOut = { Velocity: Vector3, HoldVertical: boolean, Orientation: CFrame, Hud: DriveHud }
export type DriveParams = {
	MaxSpeed: number,
	Accel: number,
	TurnRate: number,
	Tracked: boolean,
	RideOffset: number,
	HalfLength: number,
}
export type DriveState = {
	Speed: number,
	Heading: number,
	Age: number,
	SlowFor: number,
	FlipFor: number,
	HopLeft: number,
	BobT: number,
	LastWaterPos: Vector3?,
	LastWaterY: number?,
}
export type IdleState = {
	GlideSpeed: number?,
	Dir: Vector3?,
	Speed: number?,
	LastWaterPos: Vector3?,
	LastWaterY: number?,
	ReturnPos: Vector3?,
}
export type Footprint = { HalfX: number, HalfZ: number, Clearance: number, Top: number }
export type SpawnPad = { Pos: Vector3, CFrame: CFrame, Size: Vector3, Naval: boolean }
export type OccupiedSpot = { Pos: Vector3, Radius: number }
export type SpawnCtx = {
	Mode: string,
	PlayerPos: Vector3?,
	PlayerLook: Vector3?,
	PlotPos: Vector3?,
	PlotCFrame: CFrame?, -- the plot pad's CFrame (carries the plot yaw; nil → CFrame.new(PlotPos))
	PlotId: number?,
	Structures: { [string]: number },
	Footprint: Footprint,
	TakeoffSpeed: number?,
	VehiclePads: { SpawnPad },
	NavalPads: { SpawnPad },
	WaterParts: { BasePart },
	Occupied: { OccupiedSpot },
	SurfaceY: ((x: number, z: number, refY: number) -> number?)?,
	LandProbe: ((x: number, z: number, top: number) -> boolean)?,
	BoxFree: ((cf: CFrame, half: Vector3) -> boolean)?,
	-- Mobile P1-9: the player has a plot and stands outside it → SPAWN tries in front of the player first
	AwayFromHome: boolean?,
	-- P1-9 (verifier): every WE_Water part (WaterParts drops other plots' basin / gate water: not boat water for this
	-- player, but still water for a car), and a line-of-sight test (true = nothing solid between the two points)
	AllWater: { BasePart }?,
	Clear: ((from: Vector3, to: Vector3) -> boolean)?,
}
export type SpawnChoice = { CFrame: CFrame, Source: string, State: string, Speed: number }
export type ValidSample = { Pos: Vector3, Vel: Vector3, T: number, WaterY: number?, CFrame: CFrame? }

type ValidPoint = { CFrame: CFrame, Pos: Vector3, T: number }
type VehicleRec = {
	Model: Model,
	Owner: Player,
	OwnerUserId: number,
	Def: VehicleDef,
	Mode: string,
	Chassis: BasePart,
	Seat: VehicleSeat,
	Passengers: { Seat },
	LV: LinearVelocity,
	AO: AlignOrientation,
	Params: DriveParams,
	BaseMaxSpeed: number,
	MaxAltitude: number,
	Force: number,
	Authority: string,
	DriverUserId: number,
	SatAt: number?,
	HelloAt: number?,
	HelloTimedOut: boolean,
	FlightNoticeSent: boolean,
	EverSeated: boolean,
	LastSeatedAt: number,
	LastValid: ValidPoint,
	Window: { Pos: Vector3, T: number }?,
	LastSampleT: number?,
	LastSamplePos: Vector3?,
	NextSampleAt: number,
	NextIdleAt: number,
	LastIdleAt: number?,
	SpeedFlags: number,
	OffWaterFor: number,
	Violations: { number },
	CorrectUntil: number?,
	CorrectPos: Vector3?,
	Idle: IdleState,
	Fallback: DriveState?,
	LastStabilisedAt: number,
	Conns: { RBXScriptConnection },
	OutVel: Vector3?,
	OutHold: boolean?,
	OutRot: CFrame?,
	-- judge fix: ownership of every assembly, input stream, watchdog, diagnostics
	OwnParts: { BasePart },
	InT: number,
	InS: number,
	InL: number,
	InAt: number?,
	ClientProven: boolean,
	ClientBroken: boolean,
	ServerProven: boolean,
	BrokenReason: string?,
	HandOffPos: Vector3?,
	HandOffAt: number?,
	PushSince: number?,
	PushPos: Vector3?,
	OwnerBad: number,
	NextOwnerProbe: number,
	TripAt: number?,
	TripPos: Vector3?,
	TripSign: number?, -- sign of the pushed throttle at the trip (0 / nil = no push: ownership trip)
	TripLook: Vector3?, -- chassis look vector at the trip
	BlockPush: number,
	BlockLogged: boolean,
	LastWatchAt: number?,
	Pins: number,
	PinList: string,
	NextDiagAt: number,
	NextDiagLogAt: number,
}

local sitCueShown: { [number]: boolean } = {} -- ArmedJeep muzzle-flash cue on the first car sit (once per session)
local sitOfferShown: { [number]: boolean } = {} -- SpeedBoost soft offer after the first sit (once per session)

local DataService: any = nil
local EconomyService: any = nil
local AnalyticsService: any = nil
local RateLimitService: any = nil
local NotificationService: any = nil
local RemoteSetup: any = nil
local TerritoryService: any = nil
local MissionService: any = nil
local TutorialService: any = nil
local MonetizationService: any = nil
local ResearchService: any = nil
local AntiExploitService: any = nil

local activeVehicles: { [number]: Model } = {}
local lastSpawnAt: { [number]: number } = {}
local lastDamageAt: { [number]: number } = {} -- P1-9: character took damage (Humanoid.HealthChanged drop)
local brokenTrips: { [number]: number } = {} -- judge fix: server-proven watchdog trips this session (per UserId)
local vehicles: { [Model]: VehicleRec } = {}
local vehicleFolder: Folder? = nil

local function now(): number
	return os.clock()
end

local function ensureFolder(): Folder
	local cached = vehicleFolder
	if cached and cached.Parent then
		return cached
	end
	local existing = Workspace:FindFirstChild("WarEmpireVehicles")
	if existing and existing:IsA("Folder") then
		vehicleFolder = existing
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "WarEmpireVehicles"
	folder.Parent = Workspace
	vehicleFolder = folder
	return folder
end

local function getDef(vehicleId: string): VehicleDef?
	return VehicleConfig.Vehicles[vehicleId]
end

local function notify(player: Player, message: string, kind: string, duration: number?)
	if NotificationService and NotificationService.Notify then
		pcall(NotificationService.Notify, player, message, kind, duration)
	end
end

-- ── Maths shared with the client laws (spec §2.0) ───────────────────────────────────────────────
local function approach(x: number, target: number, rate: number, dt: number): number
	local d = target - x
	local m = rate * dt
	if d > m then
		return x + m
	elseif d < -m then
		return x - m
	end
	return target
end

local function fwd(h: number): Vector3
	return Vector3.new(-math.sin(h), 0, -math.cos(h))
end

local function right(h: number): Vector3
	return Vector3.new(math.cos(h), 0, -math.sin(h))
end

local function yawOf(cf: CFrame): number
	local look = cf.LookVector
	return math.atan2(-look.X, -look.Z)
end

local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function orient(pitchDeg: number, h: number, bankDeg: number): CFrame
	return CFrame.fromEulerAnglesYXZ(math.rad(pitchDeg), h, -math.rad(bankDeg))
end

local function unitInput(v: any): number
	local n = tonumber(v)
	if n == nil or n ~= n then
		return 0
	end
	return math.clamp(n, -1, 1)
end

local function partVelocity(part: BasePart): Vector3
	local v = (part :: any).AssemblyLinearVelocity
	if typeof(v) == "Vector3" then
		return v
	end
	return Vector3.zero
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- ── Water (spec §2.5; the same algorithm as VehicleDriveClient.Laws.WaterSurfaceAt) ─────────────
local waterParts: { BasePart } = {}
local waterRefreshAt = 0

local function refreshWaterParts()
	local list: { BasePart } = {}
	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.Water)) do
		if inst:IsA("BasePart") and inst.Parent then
			table.insert(list, inst)
		end
	end
	waterParts = list
end

local function getWaterParts(): { BasePart }
	local t = now()
	if t >= waterRefreshAt then
		waterRefreshAt = t + WaterCfg.RefreshSeconds
		refreshWaterParts()
	end
	return waterParts
end

--[[ Waterways C5: plot water (DockWater carries WE_PlotId, SeaGateWater WE_GatePlotId) is water only for a boat
	whose owner's BasePlotId is that plot. An enemy boat can then neither spawn in, drive into nor idle in someone's
	basin or gate water, not even behind an ally's boat while the sea gate is open. Public water has neither
	attribute and is water for every boat. ]]
local function waterPlotOf(p: BasePart): number?
	local id = p:GetAttribute("WE_PlotId")
	if id == nil then
		id = p:GetAttribute("WE_GatePlotId")
	end
	return tonumber(id)
end

local function filterPlotWater(parts: { BasePart }, plotId: number?): { BasePart }
	local out: { BasePart } = {}
	for _, p in ipairs(parts) do
		local id = waterPlotOf(p)
		if id == nil or id == plotId then
			table.insert(out, p)
		end
	end
	return out
end

-- per-plot filtered lists, rebuilt whenever getWaterParts() hands out a new list (every RefreshSeconds)
local plotWaterFrom: { BasePart }? = nil
local plotWaterLists: { [number]: { BasePart } } = {}

local function waterPartsFor(plotId: number?): { BasePart }
	local all = getWaterParts()
	if plotWaterFrom ~= all then
		plotWaterFrom = all
		plotWaterLists = {}
	end
	local key = plotId or -1
	local list = plotWaterLists[key]
	if list == nil then
		list = filterPlotWater(all, plotId)
		plotWaterLists[key] = list
	end
	return list
end

--[[ Top of the highest flat WE_Water part under pos (nil = no water). margin shrinks each part's
	rectangle (negative = slack outside the edge). landProbe(x, z, top) → true when something solid
	stands at/above the surface there (kerb, pier, pad, sandbar). ]]
local function waterSurfaceAt(
	parts: { BasePart },
	pos: Vector3,
	margin: number?,
	landProbe: ((number, number, number) -> boolean)?
): number?
	local m = margin or 0
	local best = -math.huge
	local found = false
	for _, p in ipairs(parts) do
		local lp = p.CFrame:PointToObjectSpace(pos)
		local size = p.Size
		if math.abs(lp.X) <= size.X * 0.5 - m and math.abs(lp.Z) <= size.Z * 0.5 - m then
			local top = p.Position.Y + size.Y * 0.5
			if pos.Y >= top - WaterCfg.QueryBelow and pos.Y <= top + WaterCfg.QueryAbove and top > best then
				best = top
				found = true
			end
		end
	end
	if not found then
		return nil
	end
	if landProbe and landProbe(pos.X, pos.Z, best) then
		return nil
	end
	return best
end

-- Water rectangle in XZ (parts are flat, rotated about Y only)
type Rect2 = { CX: number, CZ: number, UX: number, UZ: number, VX: number, VZ: number, HX: number, HZ: number, Top: number, Area: number }

local function rectOf(p: BasePart): Rect2
	local cf = p.CFrame
	local r = cf.RightVector
	local z = -cf.LookVector
	local rm = math.sqrt(r.X * r.X + r.Z * r.Z)
	local zm = math.sqrt(z.X * z.X + z.Z * z.Z)
	local ux, uz = if rm > 1e-6 then r.X / rm else 1, if rm > 1e-6 then r.Z / rm else 0
	local vx, vz = if zm > 1e-6 then z.X / zm else 0, if zm > 1e-6 then z.Z / zm else 1
	return {
		CX = cf.Position.X,
		CZ = cf.Position.Z,
		UX = ux,
		UZ = uz,
		VX = vx,
		VZ = vz,
		HX = p.Size.X * 0.5,
		HZ = p.Size.Z * 0.5,
		Top = p.Position.Y + p.Size.Y * 0.5,
		Area = p.Size.X * p.Size.Z,
	}
end

-- 2D separating-axis test: true when the rectangles overlap or come within `gap` studs.
local function rectsNear(a: Rect2, b: Rect2, gap: number): boolean
	local axes = { { a.UX, a.UZ }, { a.VX, a.VZ }, { b.UX, b.UZ }, { b.VX, b.VZ } }
	local dx, dz = b.CX - a.CX, b.CZ - a.CZ
	for _, n in ipairs(axes) do
		local nx, nz = n[1], n[2]
		local ra = a.HX * math.abs(a.UX * nx + a.UZ * nz) + a.HZ * math.abs(a.VX * nx + a.VZ * nz)
		local rb = b.HX * math.abs(b.UX * nx + b.UZ * nz) + b.HZ * math.abs(b.VX * nx + b.VZ * nz)
		local d = math.abs(dx * nx + dz * nz)
		if d - ra - rb > gap then
			return false
		end
	end
	return true
end

local function isConnectedToSea(basin: BasePart, parts: { BasePart }): boolean
	local list: { BasePart } = {}
	local basinIndex = 0
	for _, p in ipairs(parts) do
		table.insert(list, p)
		if p == basin then
			basinIndex = #list
		end
	end
	if basinIndex == 0 then
		table.insert(list, basin)
		basinIndex = #list
	end
	local rects: { Rect2 } = {}
	local sea, seaArea = 0, -1
	for i, p in ipairs(list) do
		rects[i] = rectOf(p)
		if rects[i].Area > seaArea then
			seaArea = rects[i].Area
			sea = i
		end
	end
	if sea == basinIndex then
		return true
	end
	local seen: { [number]: boolean } = { [basinIndex] = true }
	local queue = { basinIndex }
	local head = 1
	while head <= #queue do
		local cur = queue[head]
		head += 1
		local a = rects[cur]
		for j, b in ipairs(rects) do
			if not seen[j] and math.abs(a.Top - b.Top) <= WaterCfg.ConnectTopDelta and rectsNear(a, b, WaterCfg.ConnectGap) then
				if j == sea then
					return true
				end
				seen[j] = true
				table.insert(queue, j)
			end
		end
	end
	return false
end

-- ── Laws (server copies: idle, Car/Boat fallback; spec §2.1, §2.4, §2.6) ────────────────────────
local function newDriveState(sense: DriveSense): DriveState
	local waterY = sense.WaterY
	return {
		Speed = sense.Velocity:Dot(fwd(sense.Yaw)),
		Heading = sense.Yaw,
		Age = 0,
		SlowFor = 0,
		FlipFor = 0,
		HopLeft = 0,
		BobT = 0,
		LastWaterPos = if waterY ~= nil then sense.Position else nil,
		LastWaterY = waterY,
	}
end

local function throttleSpeed(
	speed: number,
	t: number,
	maxSpeed: number,
	rev: number,
	accel: number,
	brake: number,
	coast: number,
	revAccelFrac: number,
	dt: number
): number
	if t > 0.05 then
		if speed < 0 then
			return approach(speed, 0, brake, dt)
		end
		return approach(speed, t * maxSpeed, accel, dt)
	elseif t < -0.05 then
		if speed > 0 then
			return approach(speed, 0, brake, dt)
		end
		return approach(speed, t * rev, accel * revAccelFrac, dt)
	end
	return approach(speed, 0, coast, dt)
end

-- Pushed against a wall: commanded speed follows the real speed instead of winding up.
local function speedResync(state: DriveState, forwardActual: number, gap: number, dt: number)
	if state.Age < ResyncCfg.GraceSeconds then
		state.SlowFor = 0
		return
	end
	if forwardActual < state.Speed - gap then
		state.SlowFor += dt
		if state.SlowFor >= ResyncCfg.Seconds then
			state.Speed = forwardActual + gap
			state.SlowFor = 0
		end
	else
		state.SlowFor = 0
	end
end

local function carStep(state: DriveState, p: DriveParams, input: DriveInput, sense: DriveSense, dt: number): DriveOut
	dt = math.clamp(dt, 0, 0.1)
	state.Age += dt
	local c = if p.Tracked then CarCfg.Tracked else CarCfg.Wheeled
	local maxS = p.MaxSpeed
	local rev = maxS * CarCfg.ReverseFrac
	local t, s = unitInput(input.Throttle), unitInput(input.Steer)
	speedResync(state, sense.Velocity:Dot(fwd(state.Heading)), ResyncCfg.CarGap, dt)
	state.Speed = throttleSpeed(state.Speed, t, maxS, rev, p.Accel, c.Brake, c.Coast, CarCfg.ReverseAccelFrac, dt)
	state.Speed = math.clamp(state.Speed, -rev, maxS)
	local dir = if state.Speed < -0.5 then -1 else 1
	state.Heading -= s * p.TurnRate * math.clamp(math.abs(state.Speed) / CarCfg.TurnSpeedRef, c.MinTurnFactor, 1) * dir * dt
	if math.abs(wrapAngle(sense.Yaw - state.Heading)) > CarCfg.YawResyncRad then
		state.Heading = sense.Yaw -- a collision spun us: stop fighting it
	end
	local r = right(state.Heading)
	local lat = sense.Velocity:Dot(r) * math.exp(-c.Grip * dt)
	local vel = fwd(state.Heading) * state.Speed + r * lat
	local hold = false
	if sense.UpY < CarCfg.FlipUpY then
		state.FlipFor += dt
		if state.FlipFor >= CarCfg.FlipSeconds then
			state.FlipFor = 0
			state.HopLeft = CarCfg.HopSeconds
		end
	else
		state.FlipFor = 0
	end
	if state.HopLeft > 0 then
		state.HopLeft -= dt
		vel = Vector3.new(vel.X, CarCfg.HopSpeed, vel.Z)
		hold = true
	end
	return {
		Velocity = vel,
		HoldVertical = hold,
		Orientation = orient(0, state.Heading, 0),
		Hud = { Speed = math.abs(state.Speed) },
	}
end

-- Shore probes: the client calls this BEFORE building sense (WaterNear / WaterFar).
local function boatProbe(state: DriveState, p: DriveParams, input: DriveInput): (number, number, number)
	local t = unitInput(input.Throttle)
	local dir = if state.Speed < -0.5 or (state.Speed <= 0 and t < 0) then -1 else 1
	local near = p.HalfLength + BoatCfg.ShoreMargin
	local far = near + state.Speed * state.Speed / (2 * BoatCfg.ShoreBrake) + 2
	return dir, near, far
end

local function boatStep(state: DriveState, p: DriveParams, input: DriveInput, sense: DriveSense, dt: number): DriveOut
	dt = math.clamp(dt, 0, 0.1)
	state.Age += dt
	local maxS = p.MaxSpeed
	local rev = maxS * BoatCfg.ReverseFrac
	local t, s = unitInput(input.Throttle), unitInput(input.Steer)
	speedResync(state, sense.Velocity:Dot(fwd(state.Heading)), ResyncCfg.Gap, dt)
	local dir = boatProbe(state, p, input)
	local before = state.Speed
	state.Speed = throttleSpeed(state.Speed, t, maxS, rev, p.Accel, BoatCfg.Brake, BoatCfg.Coast, BoatCfg.ReverseAccelFrac, dt)
	state.Speed = math.clamp(state.Speed, -rev, maxS)
	if sense.WaterNear == false then
		-- hard stop: no throttle into the shore
		state.Speed = if dir > 0 then math.min(state.Speed, 0) else math.max(state.Speed, 0)
	elseif sense.WaterFar == false then
		-- brake before the shore; throttle never adds speed toward it meanwhile
		local base = if math.abs(state.Speed) > math.abs(before) then before else state.Speed
		state.Speed = approach(base, 0, BoatCfg.ShoreBrake, dt)
	end
	state.Heading -= s * p.TurnRate * math.clamp(math.abs(state.Speed) / BoatCfg.TurnSpeedRef, BoatCfg.MinTurnFactor, 1) * dir * dt
	local pos = sense.Position
	local vel: Vector3
	local hold = true
	local tag: string? = nil
	local waterY = sense.WaterY
	if waterY == nil then
		-- pushed aground: head back to the last water position
		tag = "AGROUND"
		state.Speed = 0
		local lw, lwy = state.LastWaterPos, state.LastWaterY
		if lw ~= nil and lwy ~= nil then
			local d = Vector3.new(lw.X - pos.X, 0, lw.Z - pos.Z)
			local horiz = if d.Magnitude > 1e-4 then d.Unit * BoatCfg.AgroundSpeed else Vector3.zero
			local vy = math.clamp((lwy + p.RideOffset - pos.Y) * BoatCfg.HeightGain, -BoatCfg.MaxVy, BoatCfg.MaxVy)
			vel = horiz + Vector3.new(0, vy, 0)
		else
			vel = Vector3.zero
			hold = false
		end
	else
		state.LastWaterPos = pos
		state.LastWaterY = waterY
		state.BobT += dt
		local rideY = waterY + p.RideOffset + BoatCfg.BobAmp * 0.5 * (1 + math.sin(2 * math.pi * BoatCfg.BobHz * state.BobT))
		local vy = math.clamp((rideY - pos.Y) * BoatCfg.HeightGain, -BoatCfg.MaxVy, BoatCfg.MaxVy)
		local r = right(state.Heading)
		local lat = sense.Velocity:Dot(r) * math.exp(-BoatCfg.Drift * dt)
		vel = fwd(state.Heading) * state.Speed + r * lat + Vector3.new(0, vy, 0)
	end
	local ratio = if maxS > 0 then state.Speed / maxS else 0
	local bob = state.BobT
	local orientation = CFrame.fromEulerAnglesYXZ(
		math.rad(ratio * BoatCfg.BowUpDeg + BoatCfg.BobPitchDeg * math.sin(math.pi * bob)),
		state.Heading,
		math.rad(-s * math.clamp(ratio, 0, 1) * BoatCfg.TurnLeanDeg + BoatCfg.BobRollDeg * math.sin(2 * math.pi * BoatCfg.BobRollHz * bob + 1))
	)
	return { Velocity = vel, HoldVertical = hold, Orientation = orientation, Hud = { Speed = math.abs(state.Speed), Tag = tag } }
end

-- Idle law (no driver, or a correction hold). Spec §2.6.
local function idleTarget(mode: string, p: DriveParams, idle: IdleState, sense: DriveSense, dt: number): DriveOut
	local pos = sense.Position
	local level = orient(0, sense.Yaw, 0)
	local hud = { Speed = flat(sense.Velocity).Magnitude }
	if mode == "Heli" then
		if sense.AGL > HeliCfg.IdleLandAGL then
			return { Velocity = Vector3.new(0, -HeliCfg.IdleSink, 0), HoldVertical = true, Orientation = level, Hud = hud }
		end
		return { Velocity = Vector3.zero, HoldVertical = false, Orientation = level, Hud = hud }
	elseif mode == "Plane" then
		if sense.AGL > PlaneCfg.IdleGlideAGL then
			local look = fwd(sense.Yaw)
			local current: number = idle.GlideSpeed or math.max(0, sense.Velocity:Dot(look))
			local speed = math.max(PlaneCfg.IdleGlideMinSpeed, current - PlaneCfg.IdleGlideDecel * dt)
			idle.GlideSpeed = speed
			return {
				Velocity = look * speed + Vector3.new(0, -PlaneCfg.IdleGlideSink, 0),
				HoldVertical = true,
				Orientation = orient(PlaneCfg.IdleGlidePitch, sense.Yaw, 0),
				Hud = hud,
			}
		end
		idle.GlideSpeed = nil
		return { Velocity = Vector3.zero, HoldVertical = false, Orientation = level, Hud = hud }
	elseif mode == "Boat" then
		local waterY = sense.WaterY
		if waterY ~= nil then
			idle.LastWaterPos = pos
			idle.LastWaterY = waterY
			local vy = math.clamp((waterY + p.RideOffset - pos.Y) * BoatCfg.IdleHeightGain, -BoatCfg.IdleMaxVy, BoatCfg.IdleMaxVy)
			local h = flat(sense.Velocity)
			local current: number = idle.Speed or h.Magnitude
			local dir: Vector3 = idle.Dir or (if h.Magnitude > 0.05 then h.Unit else Vector3.zero)
			local speed = approach(current, 0, BoatCfg.IdleDecel, dt)
			idle.Speed = speed
			idle.Dir = dir
			return { Velocity = dir * speed + Vector3.new(0, vy, 0), HoldVertical = true, Orientation = level, Hud = hud }
		end
		-- no water under the hull: go back to the last water / valid position
		local target = idle.LastWaterPos or idle.ReturnPos
		local horiz = Vector3.zero
		local vy = 0
		if target then
			local d = Vector3.new(target.X - pos.X, 0, target.Z - pos.Z)
			if d.Magnitude > 0.05 then
				horiz = d.Unit * math.min(BoatCfg.AgroundSpeed, d.Magnitude * 2)
			end
			local ty = if idle.LastWaterY ~= nil then idle.LastWaterY + p.RideOffset else target.Y
			vy = math.clamp((ty - pos.Y) * BoatCfg.IdleHeightGain, -BoatCfg.IdleMaxVy, BoatCfg.IdleMaxVy)
		end
		return { Velocity = horiz + Vector3.new(0, vy, 0), HoldVertical = true, Orientation = level, Hud = hud }
	end
	-- Car: parking brake, level at the current heading
	return { Velocity = Vector3.zero, HoldVertical = false, Orientation = level, Hud = hud }
end

-- ── Drive attributes / footprint / movers ──────────────────────────────────────────────────────
local function driveModeFor(def: VehicleDef): string
	local cat = def.Category or "Ground"
	if cat == "Air" then
		local fam = def.KitFamily or ""
		if string.sub(fam, 1, 3) == "Jet" then
			return "Plane"
		end
		return "Heli"
	elseif cat == "Naval" then
		return "Boat"
	end
	return "Car"
end

local function footprintOf(model: Model): Footprint
	local chassis = model.PrimaryPart or model:FindFirstChild("Chassis")
	local ccf = if chassis and chassis:IsA("BasePart") then chassis.CFrame else model:GetPivot()
	local hx, hz, low, top = 0, 0, 0, 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.CanCollide then
			local cf = d.CFrame
			local s = d.Size * 0.5
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local lp = ccf:PointToObjectSpace(cf * Vector3.new(s.X * sx, s.Y * sy, s.Z * sz))
						hx = math.max(hx, math.abs(lp.X))
						hz = math.max(hz, math.abs(lp.Z))
						low = math.min(low, lp.Y)
						top = math.max(top, lp.Y)
					end
				end
			end
		end
	end
	return { HalfX = hx, HalfZ = hz, Clearance = -low, Top = top }
end

local function driveAttributes(def: VehicleDef, fp: Footprint, bonus: number?, armorMult: number?): { [string]: any }
	local mode = driveModeFor(def)
	local b = math.clamp(tonumber(bonus) or 1, 1, Drive.MaxResearchSpeedBonus)
	local a: { [string]: any } = {
		WE_DriveMode = mode,
		WE_ProtocolVersion = Drive.ProtocolVersion,
		WE_GroundClearance = fp.Clearance,
		WE_HalfLength = fp.HalfZ,
		WE_HalfWidth = fp.HalfX,
		WE_ArmorMult = math.clamp(tonumber(armorMult) or 1, 1, Drive.MaxResearchArmorBonus),
	}
	local base: number
	if mode == "Car" then
		local isTracked = string.find(def.KitFamily or "", "Tracked") ~= nil
		local c = if isTracked then CarCfg.Tracked else CarCfg.Wheeled
		base = if isTracked
			then math.clamp(def.Speed, CarCfg.TrackedMinSpeed, CarCfg.TrackedMaxSpeed)
			else math.max(def.Speed, CarCfg.WheeledMinSpeed)
		a.WE_Accel = c.Accel
		a.WE_TurnRate = c.TurnRate
		a.WE_Tracked = isTracked
	elseif mode == "Heli" then
		base = def.Speed
		a.WE_Accel = HeliCfg.Accel
		a.WE_TurnRate = HeliCfg.TurnRate
		a.WE_ClimbRate = HeliCfg.ClimbRate
		a.WE_MaxAltitude = HeliCfg.MaxAltitude
	elseif mode == "Plane" then
		base = def.Speed
		local vto = math.clamp(PlaneCfg.TakeoffFrac * def.Speed, PlaneCfg.TakeoffMin, PlaneCfg.TakeoffMax)
		a.WE_Accel = PlaneCfg.Thrust
		a.WE_TurnRate = PlaneCfg.TurnRate
		a.WE_MaxAltitude = PlaneCfg.MaxAltitude
		a.WE_TakeoffSpeed = vto
		a.WE_StallSpeed = PlaneCfg.StallFrac * vto
	else
		base = def.Speed
		a.WE_Accel = BoatCfg.Accel
		a.WE_TurnRate = BoatCfg.TurnRate
		a.WE_RideOffset = fp.Clearance - BoatCfg.Draft
	end
	a.WE_BaseMaxSpeed = base
	a.WE_MaxSpeed = base * b
	return a
end

local function moverTuning(mode: string): (number, number, number, number)
	if mode == "Heli" then
		return HeliCfg.ForcePerMass, HeliCfg.TorqueScale, HeliCfg.Responsiveness, HeliCfg.MaxAngularVelocity
	elseif mode == "Plane" then
		return PlaneCfg.ForcePerMass, PlaneCfg.TorqueScale, PlaneCfg.Responsiveness, PlaneCfg.MaxAngularVelocity
	elseif mode == "Boat" then
		return BoatCfg.ForcePerMass, BoatCfg.TorqueScale, BoatCfg.Responsiveness, BoatCfg.MaxAngularVelocity
	end
	return CarCfg.ForcePerMass, CarCfg.TorqueScale, CarCfg.Responsiveness, CarCfg.MaxAngularVelocity
end

local function estimateMass(model: Model): number
	local m = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not d.Massless then
			local ok, pm = pcall(function(): number
				return d:GetMass()
			end)
			if ok and typeof(pm) == "number" then
				m += pm
			end
		end
	end
	return math.max(m, 1)
end

-- F = (mass + 20 x seats) x ForcePerMass; MaxTorque = mass x |Chassis.Size|² x TorqueScale.
local function setMoverLimits(lv: LinearVelocity, ao: AlignOrientation, chassis: BasePart, mode: string, seats: number, mass: number, holdVertical: boolean): number
	local forcePerMass, torqueScale, responsiveness, maxAngular = moverTuning(mode)
	local force = (mass + Drive.SeatMassAllowance * math.max(1, seats)) * forcePerMass
	lv.MaxAxesForce = Vector3.new(force, if holdVertical then force else 0, force)
	local sizeMag = chassis.Size.Magnitude
	ao.MaxTorque = mass * sizeMag * sizeMag * torqueScale
	ao.Responsiveness = responsiveness
	ao.MaxAngularVelocity = maxAngular
	return force
end

local function createMovers(model: Model, chassis: BasePart, def: VehicleDef, mode: string)
	local attach = Instance.new("Attachment")
	attach.Name = "WE_DriveAttach"
	attach.CFrame = CFrame.new()
	attach.Parent = chassis
	local lv = Instance.new("LinearVelocity")
	lv.Name = "WE_DriveLV"
	lv.Attachment0 = attach
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	lv.ForceLimitsEnabled = true
	lv.VectorVelocity = Vector3.zero
	lv.Parent = chassis
	local ao = Instance.new("AlignOrientation")
	ao.Name = "WE_DriveAO"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.AlignType = Enum.AlignType.AllAxes
	ao.PrimaryAxisOnly = false
	ao.Attachment0 = attach
	ao.RigidityEnabled = false
	ao.CFrame = chassis.CFrame.Rotation
	ao.Parent = chassis
	-- Fy starts at F only for boats (planes that start in the air get it at spawn)
	setMoverLimits(lv, ao, chassis, mode, def.Seats or 1, estimateMass(model), mode == "Boat")
end

local function weldTo(body: BasePart, other: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = body
	w.Part1 = other
	w.Parent = body
end

local function addPart(
	model: Model,
	body: BasePart,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?,
	collide: boolean?
): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Metal
	p.CFrame = body.CFrame * offset
	p.Anchored = false
	p.CanCollide = if collide == nil then false else collide
	p.Massless = true
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	weldTo(body, p)
	return p
end

local function addWheels(model: Model, body: BasePart, scale: number, positions: { Vector3 }, radius: number?)
	-- Physics wheels on HingeConstraints (NOT welded). v70: free-rolling (ActuatorType None) — the
	-- WE_DriveLV / WE_DriveAO movers carry the vehicle, so nothing fights the drive.
	-- Catalog mesh wheels stay cosmetic-only via VisualAssetService (CanCollide false).
	-- Cylinder PartType axis is local X (= axle). Do NOT Z-rotate 90° (that stood the can on end).
	local r = radius or 1.1
	for i, offset in ipairs(positions) do
		local wheel = Instance.new("Part")
		wheel.Name = "Wheel" .. i
		wheel.Shape = Enum.PartType.Cylinder
		-- Thin in X (axle/width), diameter in Y/Z — axle already along body X with identity rot
		wheel.Size = Vector3.new(r * 0.85, r * 1.8 * scale, r * 1.8 * scale)
		wheel.Color = Color3.fromRGB(22, 22, 24)
		wheel.Material = Enum.Material.SmoothPlastic
		wheel.CFrame = body.CFrame * CFrame.new(offset * scale)
		wheel.Anchored = false
		wheel.CanCollide = true
		wheel.Massless = false
		-- v70 verifier: LOW friction. The axles are fixed, so yawing drags every wheel sideways; at friction 2.0
		-- that drag (mu x load x |wheel Z|) was 1.1-3.3x the WE_DriveAO torque and cars / tanks could not turn.
		-- Sideways grip comes from the law (Grip term through WE_DriveLV), not from the tyres.
		wheel.CustomPhysicalProperties =
			PhysicalProperties.new(0.9, CarCfg.WheelFriction, 0.1, CarCfg.WheelFrictionWeight, 1)
		wheel:SetAttribute("WE_PhysicsWheel", true)
		wheel.Parent = model

		local att0 = Instance.new("Attachment")
		att0.Name = "WE_WheelAttBody" .. i
		-- Identity → Attachment.Axis (1,0,0) = body right = axle
		att0.CFrame = CFrame.new(offset * scale)
		att0.Parent = body

		local att1 = Instance.new("Attachment")
		att1.Name = "WE_WheelAtt" .. i
		att1.CFrame = CFrame.new() -- wheel local X = axle
		att1.Parent = wheel

		local hinge = Instance.new("HingeConstraint")
		hinge.Name = "WE_DriveHinge" .. i
		hinge.Attachment0 = att0
		hinge.Attachment1 = att1
		hinge.ActuatorType = Enum.ActuatorType.None
		hinge:SetAttribute("WE_DriveHinge", true)
		hinge:SetAttribute("WE_WheelSide", if offset.X < 0 then -1 else 1)
		hinge.Parent = wheel
		-- v70 judge: hinge-joined parts are separate assemblies and DO collide; every kit's wheels sit
		-- 0.15-1.3 studs inside the Chassis, so the hinge and the contact fought forever (jitter, locked wheels, flings).
		local nc = Instance.new("NoCollisionConstraint")
		nc.Name = "WE_WheelNoCollide" .. i
		nc.Part0 = body
		nc.Part1 = wheel
		nc.Parent = wheel

		local hub = Instance.new("Part")
		hub.Name = "Hub" .. i
		hub.Shape = Enum.PartType.Cylinder
		hub.Size = Vector3.new(r * 0.35, r * 0.7 * scale, r * 0.7 * scale)
		hub.Color = Color3.fromRGB(90, 95, 100)
		hub.Material = Enum.Material.Metal
		hub.CFrame = wheel.CFrame
		hub.Anchored = false
		hub.CanCollide = false
		hub.Massless = true
		hub.Parent = model
		local hubWeld = Instance.new("WeldConstraint")
		hubWeld.Part0 = wheel
		hubWeld.Part1 = hub
		hubWeld.Parent = hub
	end
end

-- Visual kits v2 shared accents (keep part counts modest)
local function addHeadlights(model: Model, body: BasePart, s: number, zFront: number, y: number, spacing: number, col: Color3?)
	local c = col or Color3.fromRGB(255, 240, 180)
	addPart(model, body, "LightL", Vector3.new(0.45 * s, 0.35 * s, 0.35 * s), CFrame.new(-spacing * s, y * s, zFront * s), c, Enum.Material.Neon, nil, false)
	addPart(model, body, "LightR", Vector3.new(0.45 * s, 0.35 * s, 0.35 * s), CFrame.new(spacing * s, y * s, zFront * s), c, Enum.Material.Neon, nil, false)
end

local function addTaillights(model: Model, body: BasePart, s: number, zRear: number, y: number, spacing: number)
	local c = Color3.fromRGB(220, 50, 40)
	addPart(model, body, "TailL", Vector3.new(0.4 * s, 0.3 * s, 0.25 * s), CFrame.new(-spacing * s, y * s, zRear * s), c, Enum.Material.Neon, nil, false)
	addPart(model, body, "TailR", Vector3.new(0.4 * s, 0.3 * s, 0.25 * s), CFrame.new(spacing * s, y * s, zRear * s), c, Enum.Material.Neon, nil, false)
end

local function addExhaust(model: Model, body: BasePart, s: number, offset: CFrame, accent: Color3)
	addPart(model, body, "Exhaust", Vector3.new(0.35 * s, 0.35 * s, 1.4 * s), offset, Color3.fromRGB(35, 35, 38), Enum.Material.Metal, Enum.PartType.Cylinder, false)
	addPart(model, body, "ExhaustGlow", Vector3.new(0.28 * s, 0.28 * s, 0.35 * s), offset * CFrame.new(0, 0, 0.7 * s), accent, Enum.Material.Neon, Enum.PartType.Cylinder, false)
end

local function addRotorDisc(model: Model, body: BasePart, s: number, y: number, radius: number, accent: Color3)
	-- Thin neon disc under rotor (silhouette read at distance)
	local disc = addPart(
		model,
		body,
		"RotorDisc",
		Vector3.new(0.08 * s, radius * 2 * s, radius * 2 * s),
		CFrame.new(0, y * s, -0.3 * s) * CFrame.Angles(0, 0, math.rad(90)),
		accent,
		Enum.Material.Neon,
		Enum.PartType.Cylinder,
		false
	)
	disc.Transparency = 0.55
end

local function addWakeStrip(model: Model, body: BasePart, s: number, length: number, accent: Color3)
	addPart(model, body, "WakeNeon", Vector3.new(0.35 * s, 0.12 * s, length * s), CFrame.new(0, -0.7 * s, 0.5 * s), accent, Enum.Material.Neon, nil, false)
end

local function addSideRails(model: Model, body: BasePart, s: number, length: number, height: number, width: number, color: Color3)
	addPart(model, body, "RailL", Vector3.new(0.2 * s, 0.25 * s, length * s), CFrame.new(-width * s, height * s, 0), color, Enum.Material.Metal, nil, false)
	addPart(model, body, "RailR", Vector3.new(0.2 * s, 0.25 * s, length * s), CFrame.new(width * s, height * s, 0), color, Enum.Material.Metal, nil, false)
end

local function buildVehicleModel(def: VehicleDef, at: CFrame, ownerUserId: number, bonus: number?, armorMult: number?): Model
	local model = Instance.new("Model")
	model.Name = def.DisplayName
	model:SetAttribute("VehicleId", def.Id)
	model:SetAttribute("OwnerUserId", ownerUserId)

	local id = def.Id
	local family = def.KitFamily or "WheeledLight"
	local scale = if typeof(def.KitScale) == "number" then def.KitScale :: number else 1
	local olive = Color3.fromRGB(55, 70, 48)
	local oliveDark = Color3.fromRGB(40, 50, 38)
	local armor = Color3.fromRGB(62, 68, 55)
	local armorDark = Color3.fromRGB(45, 50, 42)
	local sand = Color3.fromRGB(110, 100, 70)
	local accent = Color3.fromRGB(230, 190, 60)
	local blueAcc = Color3.fromRGB(90, 160, 220)
	local redAcc = Color3.fromRGB(200, 80, 60)
	local sky = Color3.fromRGB(70, 90, 110)
	local rarity = def.Rarity or "Common"
	local accentCol = if rarity == "Legendary"
		then redAcc
		elseif rarity == "Epic" then accent
		elseif rarity == "Rare" then blueAcc
		else accent

	local body = Instance.new("Part")
	body.Name = "Chassis"
	body.Anchored = false
	body.CanCollide = true
	body.Material = Enum.Material.Metal
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.CFrame = at
	body.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.5, 0.2, 1, 1)
	body.Parent = model

	local seatOffset = CFrame.new(0, 2.0, -0.5)
	local labelY = 4.5
	local s = scale

	local function kitWheeledLight()
		local armed = id == "ArmedJeep"
		local scout = id == "ScoutCar" or id == "ReconBuggy"
		local quad = id == "UtilityQuad"
		body.Size = Vector3.new(5.2 * s, 1.6 * s, if quad then 6.5 * s else 8.5 * s)
		body.Color = if armed then Color3.fromRGB(48, 58, 42) elseif scout then Color3.fromRGB(70, 85, 55) else olive
		addPart(model, body, "Hood", Vector3.new(4.6 * s, 0.7 * s, 2.8 * s), CFrame.new(0, 0.9 * s, -2.4 * s), oliveDark, Enum.Material.Metal, nil, false)
		addPart(model, body, "Cabin", Vector3.new(4.4 * s, 1.4 * s, 2.8 * s), CFrame.new(0, 1.3 * s, 0.2 * s), oliveDark, Enum.Material.SmoothPlastic, nil, true)
		if not quad then
			addPart(model, body, "Bed", Vector3.new(4.4 * s, 0.9 * s, 2.6 * s), CFrame.new(0, 0.7 * s, 2.6 * s), olive, Enum.Material.Metal, nil, false)
		end
		addPart(model, body, "Bumper", Vector3.new(5.0 * s, 0.5 * s, 0.4 * s), CFrame.new(0, -0.3 * s, -4.0 * s), Color3.fromRGB(30, 30, 30), Enum.Material.Metal, nil, false)
		-- Olive metal trim (no neon green/gold until mesh loads)
		addPart(model, body, "AccentStrip", Vector3.new(4.8 * s, 0.12 * s, 0.35 * s), CFrame.new(0, 1.1 * s, -1.2 * s), if armed then Color3.fromRGB(90, 55, 45) else oliveDark, Enum.Material.Metal, nil, false)
		if armed then
			addPart(model, body, "GunMount", Vector3.new(0.8 * s, 0.8 * s, 0.8 * s), CFrame.new(0, 2.2 * s, 0.4 * s), Color3.fromRGB(35, 35, 35), Enum.Material.Metal, nil, false)
			addPart(model, body, "Barrel", Vector3.new(0.25 * s, 0.25 * s, 2.4 * s), CFrame.new(0, 2.5 * s, -1.0 * s), Color3.fromRGB(40, 40, 40), Enum.Material.Metal, nil, false)
		end
		addWheels(model, body, s, {
			Vector3.new(-2.4, -0.9, 2.6),
			Vector3.new(2.4, -0.9, 2.6),
			Vector3.new(-2.4, -0.9, -2.6),
			Vector3.new(2.4, -0.9, -2.6),
		}, 1.05)
		addHeadlights(model, body, s, -4.1, 0.2, 1.8)
		addTaillights(model, body, s, if quad then 3.0 else 4.0, 0.15, 1.9)
		addExhaust(model, body, s, CFrame.new(1.8 * s, -0.2 * s, 3.2 * s) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(50, 55, 45))
		addSideRails(model, body, s, if quad then 4.5 else 5.5, 0.6, 2.5, oliveDark)
		seatOffset = CFrame.new(0, 1.9 * s, 0.1 * s)
		labelY = 4.2 * s
	end

	local function kitWheeledTruck()
		local supply = id == "SupplyTruck"
		local fuel = id == "FuelTanker"
		local missile = id == "MissileTruck" or id == "AntiAirTruck"
		local eng = id == "EngineeringTruck"
		body.Size = Vector3.new(6.2 * s, 2.4 * s, 11 * s)
		body.Color = if supply then sand elseif fuel then Color3.fromRGB(90, 95, 55) else armor
		addPart(model, body, "Cabin", Vector3.new(5.6 * s, 2.0 * s, 3.2 * s), CFrame.new(0, 1.6 * s, -3.2 * s), armorDark, Enum.Material.Metal, nil, true)
		addPart(model, body, "Cargo", Vector3.new(5.8 * s, 2.6 * s, 6.5 * s), CFrame.new(0, 1.4 * s, 2.0 * s), if supply then Color3.fromRGB(130, 115, 75) elseif fuel then Color3.fromRGB(70, 80, 45) else sand, Enum.Material.Metal, nil, true)
		addPart(model, body, "Accent", Vector3.new(5.9 * s, 0.15 * s, 0.4 * s), CFrame.new(0, 2.5 * s, -2.0 * s), accentCol, Enum.Material.Neon, nil, false)
		if supply then
			addPart(model, body, "Crate", Vector3.new(3.5 * s, 1.4 * s, 3.5 * s), CFrame.new(0, 3.0 * s, 2.0 * s), Color3.fromRGB(90, 75, 50), Enum.Material.Wood, nil, false)
		elseif fuel then
			addPart(model, body, "Tank", Vector3.new(4.5 * s, 2.2 * s, 5.5 * s), CFrame.new(0, 2.8 * s, 2.0 * s), Color3.fromRGB(80, 85, 50), Enum.Material.Metal, Enum.PartType.Cylinder, false)
		elseif missile then
			addPart(model, body, "Launcher", Vector3.new(4.0 * s, 1.2 * s, 5.0 * s), CFrame.new(0, 3.0 * s, 1.5 * s) * CFrame.Angles(math.rad(-20), 0, 0), Color3.fromRGB(50, 55, 45), Enum.Material.Metal, nil, false)
		elseif eng then
			addPart(model, body, "Crane", Vector3.new(0.5 * s, 4.0 * s, 0.5 * s), CFrame.new(1.5 * s, 4.0 * s, 1.0 * s), Color3.fromRGB(200, 160, 60), Enum.Material.Metal, nil, false)
		end
		addPart(model, body, "Bumper", Vector3.new(6.0 * s, 0.55 * s, 0.45 * s), CFrame.new(0, -0.6 * s, -5.2 * s), Color3.fromRGB(28, 28, 30), Enum.Material.Metal, nil, false)
		addWheels(model, body, 1.15 * s, {
			Vector3.new(-2.8, -1.2, 3.5),
			Vector3.new(2.8, -1.2, 3.5),
			Vector3.new(-2.8, -1.2, 0),
			Vector3.new(2.8, -1.2, 0),
			Vector3.new(-2.8, -1.2, -3.5),
			Vector3.new(2.8, -1.2, -3.5),
		}, 1.2)
		addHeadlights(model, body, s, -5.3, 0.4, 2.2)
		addTaillights(model, body, s, 5.2, 0.3, 2.4)
		addExhaust(model, body, s, CFrame.new(2.4 * s, -0.4 * s, 4.5 * s) * CFrame.Angles(0, 0, math.rad(90)), accentCol)
		seatOffset = CFrame.new(0, 2.4 * s, -3.0 * s)
		labelY = 5.5 * s
	end

	local function kitWheeledAPC()
		local carrier = id == "InfantryCarrier"
		local cmd = id == "CommandVehicle"
		body.Size = Vector3.new((if carrier then 7.2 else 6.5) * s, 2.6 * s, (if carrier then 12 else 10.5) * s)
		body.Color = armorDark
		addPart(model, body, "HullTop", Vector3.new(5.8 * s, 1.4 * s, 8.5 * s), CFrame.new(0, 1.8 * s, 0), armor, Enum.Material.Metal, nil, true)
		addPart(model, body, "Turret", Vector3.new(2.4 * s, 1.2 * s, 2.4 * s), CFrame.new(0, 3.0 * s, 0.5 * s), Color3.fromRGB(50, 55, 48), Enum.Material.Metal, nil, false)
		addPart(model, body, "Barrel", Vector3.new(0.35 * s, 0.35 * s, 3.2 * s), CFrame.new(0, 3.1 * s, -2.0 * s), Color3.fromRGB(35, 35, 35), Enum.Material.Metal, nil, false)
		addPart(model, body, "Accent", Vector3.new(6.0 * s, 0.12 * s, 0.35 * s), CFrame.new(0, 2.6 * s, -3 * s), accentCol, Enum.Material.Neon, nil, false)
		if cmd then
			addPart(model, body, "Dish", Vector3.new(2.2 * s, 0.3 * s, 2.2 * s), CFrame.new(0, 4.0 * s, 1.5 * s), Color3.fromRGB(80, 90, 100), Enum.Material.Metal, Enum.PartType.Cylinder, false)
		end
		addPart(model, body, "Bumper", Vector3.new(6.2 * s, 0.6 * s, 0.5 * s), CFrame.new(0, -0.7 * s, -5.0 * s), Color3.fromRGB(30, 32, 28), Enum.Material.Metal, nil, false)
		addWheels(model, body, 1.2 * s, {
			Vector3.new(-3.0, -1.3, 3.2),
			Vector3.new(3.0, -1.3, 3.2),
			Vector3.new(-3.0, -1.3, 0.5),
			Vector3.new(3.0, -1.3, 0.5),
			Vector3.new(-3.0, -1.3, -2.5),
			Vector3.new(3.0, -1.3, -2.5),
		}, 1.25)
		addHeadlights(model, body, s, -5.1, 0.2, 2.4)
		addTaillights(model, body, s, 4.8, 0.2, 2.5)
		addExhaust(model, body, s, CFrame.new(2.8 * s, 0.2 * s, 4.0 * s) * CFrame.Angles(0, 0, math.rad(90)), accentCol)
		seatOffset = CFrame.new(0, 2.2 * s, -2.5 * s)
		labelY = 5.8 * s
	end

	local function kitTracked(kind: string)
		local isSPAAG = kind == "SPAAG"
		local isArty = kind == "Artillery"
		local isIFV = kind == "IFV"
		body.Size = Vector3.new(6.5 * s, 2.2 * s, 9.5 * s)
		body.Color = if s >= 1.4 then Color3.fromRGB(45, 48, 40) else armor
		addPart(model, body, "TrackL", Vector3.new(1.2 * s, 1.6 * s, 9 * s), CFrame.new(-3.2 * s, -0.4 * s, 0), Color3.fromRGB(30, 32, 28), Enum.Material.Metal, nil, true)
		addPart(model, body, "TrackR", Vector3.new(1.2 * s, 1.6 * s, 9 * s), CFrame.new(3.2 * s, -0.4 * s, 0), Color3.fromRGB(30, 32, 28), Enum.Material.Metal, nil, true)
		if isSPAAG then
			addPart(model, body, "Turret", Vector3.new(3.2 * s, 1.4 * s, 3.2 * s), CFrame.new(0, 2.0 * s, 0), armorDark, Enum.Material.Metal, nil, true)
			addPart(model, body, "BarrelA", Vector3.new(0.3 * s, 0.3 * s, 4.5 * s), CFrame.new(-0.6 * s, 2.4 * s, -3.0 * s) * CFrame.Angles(math.rad(-35), 0, 0), Color3.fromRGB(35, 35, 35), Enum.Material.Metal, nil, false)
			addPart(model, body, "BarrelB", Vector3.new(0.3 * s, 0.3 * s, 4.5 * s), CFrame.new(0.6 * s, 2.4 * s, -3.0 * s) * CFrame.Angles(math.rad(-35), 0, 0), Color3.fromRGB(35, 35, 35), Enum.Material.Metal, nil, false)
		elseif isArty then
			local rocket = id == "RocketArtillery"
			addPart(model, body, "Turret", Vector3.new(3.4 * s, 1.5 * s, 3.8 * s), CFrame.new(0, 1.9 * s, 0.8 * s), armorDark, Enum.Material.Metal, nil, true)
			if rocket then
				addPart(model, body, "Pod", Vector3.new(3.0 * s, 1.8 * s, 4.5 * s), CFrame.new(0, 3.2 * s, 0.5 * s) * CFrame.Angles(math.rad(-25), 0, 0), Color3.fromRGB(55, 60, 50), Enum.Material.Metal, nil, false)
			else
				addPart(model, body, "Barrel", Vector3.new(0.5 * s, 0.5 * s, 7 * s), CFrame.new(0, 2.8 * s, -3.5 * s) * CFrame.Angles(math.rad(-15), 0, 0), Color3.fromRGB(35, 35, 35), Enum.Material.Metal, nil, false)
			end
		elseif isIFV then
			addPart(model, body, "HullTop", Vector3.new(5.5 * s, 1.2 * s, 7.5 * s), CFrame.new(0, 1.7 * s, 0), armor, Enum.Material.Metal, nil, true)
			addPart(model, body, "Turret", Vector3.new(2.8 * s, 1.3 * s, 3.0 * s), CFrame.new(0, 2.8 * s, 0.3 * s), armorDark, Enum.Material.Metal, nil, true)
			addPart(model, body, "Barrel", Vector3.new(0.35 * s, 0.35 * s, 4.2 * s), CFrame.new(0, 2.9 * s, -2.5 * s), Color3.fromRGB(35, 35, 35), Enum.Material.Metal, nil, false)
		else
			addPart(model, body, "Turret", Vector3.new(3.6 * s, 1.6 * s, 4.2 * s), CFrame.new(0, 2.0 * s, 0.3 * s), armorDark, Enum.Material.Metal, nil, true)
			addPart(model, body, "Barrel", Vector3.new(0.45 * s, 0.45 * s, 5.5 * s), CFrame.new(0, 2.1 * s, -4.2 * s), Color3.fromRGB(35, 35, 35), Enum.Material.Metal, nil, false)
		end
		addPart(model, body, "Accent", Vector3.new(3.2 * s, 0.12 * s, 0.3 * s), CFrame.new(0, 2.9 * s, 1.2 * s), accentCol, Enum.Material.Neon, nil, false)
		addPart(model, body, "Mantlet", Vector3.new(2.2 * s, 1.0 * s, 0.6 * s), CFrame.new(0, 2.1 * s, -1.6 * s), armorDark, Enum.Material.Metal, nil, false)
		addHeadlights(model, body, s, -4.6, 0.4, 2.2, Color3.fromRGB(255, 230, 160))
		addExhaust(model, body, s, CFrame.new(2.6 * s, 0.8 * s, 4.0 * s) * CFrame.Angles(0, 0, math.rad(90)), accentCol)
		-- v36: hinged road wheels → same WE_GroundDrive LV+HingeMotor path as MilitaryJeep (tracks are dress skirts)
		local trackL = model:FindFirstChild("TrackL")
		local trackR = model:FindFirstChild("TrackR")
		if trackL and trackL:IsA("BasePart") then
			trackL.CanCollide = false
		end
		if trackR and trackR:IsA("BasePart") then
			trackR.CanCollide = false
		end
		addWheels(model, body, s, {
			Vector3.new(-3.2, -1.0, 3.2),
			Vector3.new(3.2, -1.0, 3.2),
			Vector3.new(-3.2, -1.0, 1.0),
			Vector3.new(3.2, -1.0, 1.0),
			Vector3.new(-3.2, -1.0, -1.2),
			Vector3.new(3.2, -1.0, -1.2),
			Vector3.new(-3.2, -1.0, -3.2),
			Vector3.new(3.2, -1.0, -3.2),
		}, 0.9)
		seatOffset = CFrame.new(0, 2.6 * s, 0.2 * s)
		labelY = 5.5 * s
	end

	local function kitHeli(kind: string)
		local attack = kind == "Attack"
		local light = kind == "Light"
		local transport = kind == "Transport"
		local len = if transport then 12 elseif light then 8.5 else 10
		local wid = if transport then 4.5 elseif light then 2.8 else 3.2
		body.Size = Vector3.new(wid * s, 2.0 * s, len * s)
		body.Color = if id == "StealthHeli" then Color3.fromRGB(25, 30, 38) else sky
		addPart(model, body, "Cockpit", Vector3.new((wid - 0.6) * s, 1.6 * s, 3.2 * s), CFrame.new(0, 0.6 * s, -len * 0.32 * s), Color3.fromRGB(40, 55, 70), Enum.Material.Glass, nil, true)
		if transport then
			addPart(model, body, "Cabin", Vector3.new(4.0 * s, 2.0 * s, 5.5 * s), CFrame.new(0, 0.5 * s, 1.5 * s), sky, Enum.Material.Metal, nil, true)
		end
		addPart(model, body, "Tail", Vector3.new(1.0 * s, 1.0 * s, 5.5 * s), CFrame.new(0, 0.8 * s, len * 0.55 * s), body.Color, Enum.Material.Metal, nil, false)
		addPart(model, body, "TailFin", Vector3.new(0.3 * s, 2.4 * s, 1.6 * s), CFrame.new(0, 2.0 * s, len * 0.72 * s), Color3.fromRGB(50, 65, 80), Enum.Material.Metal, nil, false)
		local rotor = if transport then 16 elseif light then 11 else 14
		addPart(model, body, "RotorHub", Vector3.new(1.2 * s, 0.5 * s, 1.2 * s), CFrame.new(0, 2.0 * s, -0.3 * s), Color3.fromRGB(30, 30, 30), Enum.Material.Metal, nil, false)
		addPart(model, body, "RotorA", Vector3.new(rotor * s, 0.15 * s, 0.6 * s), CFrame.new(0, 2.35 * s, -0.3 * s), Color3.fromRGB(35, 35, 38), Enum.Material.Metal, nil, false)
		addPart(model, body, "RotorB", Vector3.new(0.6 * s, 0.15 * s, rotor * s), CFrame.new(0, 2.4 * s, -0.3 * s), Color3.fromRGB(35, 35, 38), Enum.Material.Metal, nil, false)
		addPart(model, body, "SkidL", Vector3.new(0.25 * s, 0.25 * s, 7 * s), CFrame.new(-wid * 0.5 * s, -1.3 * s, 0), Color3.fromRGB(40, 40, 40), Enum.Material.Metal, nil, true)
		addPart(model, body, "SkidR", Vector3.new(0.25 * s, 0.25 * s, 7 * s), CFrame.new(wid * 0.5 * s, -1.3 * s, 0), Color3.fromRGB(40, 40, 40), Enum.Material.Metal, nil, true)
		addPart(model, body, "SkidPadL", Vector3.new(0.9 * s, 0.2 * s, 1.2 * s), CFrame.new(-wid * 0.5 * s, -1.45 * s, 2 * s), Color3.fromRGB(50, 50, 55), Enum.Material.Metal, nil, true)
		addPart(model, body, "SkidPadR", Vector3.new(0.9 * s, 0.2 * s, 1.2 * s), CFrame.new(wid * 0.5 * s, -1.45 * s, 2 * s), Color3.fromRGB(50, 50, 55), Enum.Material.Metal, nil, true)
		addRotorDisc(model, body, s, 2.2, rotor * 0.48, accentCol)
		addPart(model, body, "Accent", Vector3.new((wid - 0.4) * s, 0.12 * s, 0.35 * s), CFrame.new(0, 1.2 * s, -1 * s), accentCol, Enum.Material.Neon, nil, false)
		addPart(model, body, "NavLight", Vector3.new(0.35 * s, 0.35 * s, 0.35 * s), CFrame.new(0, 1.6 * s, len * 0.4 * s), Color3.fromRGB(255, 60, 50), Enum.Material.Neon, Enum.PartType.Ball, false)
		if attack then
			addPart(model, body, "StubWingL", Vector3.new(3.5 * s, 0.25 * s, 1.2 * s), CFrame.new(-2.5 * s, 0, 0.5 * s), Color3.fromRGB(55, 70, 85), Enum.Material.Metal, nil, false)
			addPart(model, body, "StubWingR", Vector3.new(3.5 * s, 0.25 * s, 1.2 * s), CFrame.new(2.5 * s, 0, 0.5 * s), Color3.fromRGB(55, 70, 85), Enum.Material.Metal, nil, false)
		end
		seatOffset = CFrame.new(0, 1.2 * s, -2.8 * s)
		labelY = 5.5 * s
	end

	local function kitJet(kind: string)
		local bomber = kind == "Bomber"
		local cargo = kind == "Transport"
		local strike = kind == "Strike"
		local len = if cargo then 16 elseif bomber then 14 else 12
		local wid = if cargo then 3.5 elseif bomber then 2.8 else 2.4
		body.Size = Vector3.new(wid * s, 1.5 * s, len * s)
		body.Color = if cargo then Color3.fromRGB(100, 105, 95) elseif bomber then Color3.fromRGB(70, 75, 80) else Color3.fromRGB(90, 95, 100)
		addPart(model, body, "Nose", Vector3.new((wid - 0.8) * s, 1.0 * s, 3.5 * s), CFrame.new(0, 0.1 * s, -len * 0.48 * s), Color3.fromRGB(70, 75, 80), Enum.Material.Metal, nil, false)
		addPart(model, body, "Cockpit", Vector3.new(1.6 * s, 0.9 * s, 2.2 * s), CFrame.new(0, 0.9 * s, -len * 0.28 * s), Color3.fromRGB(40, 80, 120), Enum.Material.Glass, nil, false)
		local wingSpan = if cargo then 10 elseif bomber then 9 else 7
		addPart(model, body, "WingL", Vector3.new(wingSpan * s, 0.25 * s, 2.8 * s), CFrame.new(-wingSpan * 0.55 * s, 0, 0.5 * s), Color3.fromRGB(80, 85, 90), Enum.Material.Metal, nil, false)
		addPart(model, body, "WingR", Vector3.new(wingSpan * s, 0.25 * s, 2.8 * s), CFrame.new(wingSpan * 0.55 * s, 0, 0.5 * s), Color3.fromRGB(80, 85, 90), Enum.Material.Metal, nil, false)
		addPart(model, body, "TailFin", Vector3.new(0.25 * s, (if bomber then 3.2 else 2.8) * s, 2.0 * s), CFrame.new(0, 1.8 * s, len * 0.38 * s), Color3.fromRGB(85, 90, 95), Enum.Material.Metal, nil, false)
		if not cargo then
			addPart(model, body, "StabL", Vector3.new(2.5 * s, 0.2 * s, 1.2 * s), CFrame.new(-1.5 * s, 0.8 * s, len * 0.38 * s), Color3.fromRGB(80, 85, 90), Enum.Material.Metal, nil, false)
			addPart(model, body, "StabR", Vector3.new(2.5 * s, 0.2 * s, 1.2 * s), CFrame.new(1.5 * s, 0.8 * s, len * 0.38 * s), Color3.fromRGB(80, 85, 90), Enum.Material.Metal, nil, false)
		end
		if strike or kind == "Fighter" then
			addPart(model, body, "IntakeL", Vector3.new(0.9 * s, 0.9 * s, 2.5 * s), CFrame.new(-1.3 * s, -0.2 * s, 1.5 * s), Color3.fromRGB(50, 50, 55), Enum.Material.Metal, nil, false)
			addPart(model, body, "IntakeR", Vector3.new(0.9 * s, 0.9 * s, 2.5 * s), CFrame.new(1.3 * s, -0.2 * s, 1.5 * s), Color3.fromRGB(50, 50, 55), Enum.Material.Metal, nil, false)
		end
		if bomber then
			addPart(model, body, "Bay", Vector3.new((wid - 0.4) * s, 0.8 * s, 4 * s), CFrame.new(0, -0.6 * s, 0.5 * s), Color3.fromRGB(45, 48, 52), Enum.Material.Metal, nil, false)
		end
		addPart(model, body, "Accent", Vector3.new(2.0 * s, 0.1 * s, 0.3 * s), CFrame.new(0, 0.8 * s, -1 * s), accentCol, Enum.Material.Neon, nil, false)
		addPart(model, body, "EngineGlow", Vector3.new((wid - 0.6) * s, 0.7 * s, 0.5 * s), CFrame.new(0, 0, len * 0.42 * s), accentCol, Enum.Material.Neon, nil, false)
		-- Landing gear: nose wheel + two main wheels at the same height (3-point stance). v70: low
		-- friction (friction weight 100) so the plane slides along the runway under the movers.
		local gearParts = {
			addPart(model, body, "GearF", Vector3.new(0.3 * s, 0.8 * s, 0.3 * s), CFrame.new(0, -1.0 * s, -len * 0.3 * s), Color3.fromRGB(30, 30, 30), Enum.Material.Metal, nil, true),
			addPart(model, body, "WheelF", Vector3.new(0.5 * s, 0.9 * s, 0.9 * s), CFrame.new(0, -1.5 * s, -len * 0.3 * s) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(25, 25, 28), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, true),
			addPart(model, body, "GearL", Vector3.new(0.3 * s, 0.8 * s, 0.3 * s), CFrame.new(-1.5 * s, -1.0 * s, 1 * s), Color3.fromRGB(30, 30, 30), Enum.Material.Metal, nil, true),
			addPart(model, body, "GearR", Vector3.new(0.3 * s, 0.8 * s, 0.3 * s), CFrame.new(1.5 * s, -1.0 * s, 1 * s), Color3.fromRGB(30, 30, 30), Enum.Material.Metal, nil, true),
			addPart(model, body, "WheelL", Vector3.new(0.5 * s, 0.9 * s, 0.9 * s), CFrame.new(-1.5 * s, -1.5 * s, 1 * s) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(25, 25, 28), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, true),
			addPart(model, body, "WheelR", Vector3.new(0.5 * s, 0.9 * s, 0.9 * s), CFrame.new(1.5 * s, -1.5 * s, 1 * s) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(25, 25, 28), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, true),
		}
		for _, g in ipairs(gearParts) do
			g.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.02, 0.1, 100, 1)
		end
		addPart(model, body, "WingTipL", Vector3.new(0.3 * s, 0.3 * s, 0.3 * s), CFrame.new(-wingSpan * 0.95 * s, 0.1 * s, 0.5 * s), Color3.fromRGB(255, 60, 50), Enum.Material.Neon, Enum.PartType.Ball, false)
		addPart(model, body, "WingTipR", Vector3.new(0.3 * s, 0.3 * s, 0.3 * s), CFrame.new(wingSpan * 0.95 * s, 0.1 * s, 0.5 * s), Color3.fromRGB(60, 255, 90), Enum.Material.Neon, Enum.PartType.Ball, false)
		seatOffset = CFrame.new(0, 1.3 * s, -len * 0.26 * s)
		labelY = 4.8 * s
	end

	local function kitNaval(kind: string)
		if kind == "Landing" then
			body.Size = Vector3.new(8 * s, 2.0 * s, 16 * s)
			body.Color = Color3.fromRGB(55, 65, 55)
			addPart(model, body, "Deck", Vector3.new(7.2 * s, 0.5 * s, 13 * s), CFrame.new(0, 1.1 * s, 0.5 * s), Color3.fromRGB(70, 80, 65), Enum.Material.Metal, nil, true)
			addPart(model, body, "Ramp", Vector3.new(6.5 * s, 0.4 * s, 4 * s), CFrame.new(0, 0.6 * s, -7.5 * s) * CFrame.Angles(math.rad(-18), 0, 0), Color3.fromRGB(60, 70, 55), Enum.Material.Metal, nil, true)
			addPart(model, body, "Cabin", Vector3.new(3.5 * s, 2.2 * s, 3.0 * s), CFrame.new(0, 2.3 * s, 5.5 * s), Color3.fromRGB(50, 60, 50), Enum.Material.Metal, nil, true)
			addPart(model, body, "WallL", Vector3.new(0.4 * s, 1.6 * s, 12 * s), CFrame.new(-3.6 * s, 1.6 * s, 0), oliveDark, Enum.Material.Metal, nil, false)
			addPart(model, body, "WallR", Vector3.new(0.4 * s, 1.6 * s, 12 * s), CFrame.new(3.6 * s, 1.6 * s, 0), oliveDark, Enum.Material.Metal, nil, false)
			addPart(model, body, "Accent", Vector3.new(6.0 * s, 0.12 * s, 0.35 * s), CFrame.new(0, 1.6 * s, 4 * s), accentCol, Enum.Material.Neon, nil, false)
			addWakeStrip(model, body, s, 12, accentCol)
			addPart(model, body, "GunMount", Vector3.new(1.2 * s, 0.8 * s, 1.2 * s), CFrame.new(0, 2.6 * s, -2 * s), Color3.fromRGB(40, 45, 40), Enum.Material.Metal, nil, false)
			seatOffset = CFrame.new(0, 3.0 * s, 5.2 * s)
			labelY = 6.0 * s
		elseif kind == "Sub" then
			-- Surface stub: low dark hull (no underwater physics yet)
			body.Size = Vector3.new(5 * s, 2.2 * s, 18 * s)
			body.Color = Color3.fromRGB(30, 40, 48)
			addPart(model, body, "Sail", Vector3.new(1.8 * s, 2.8 * s, 4 * s), CFrame.new(0, 2.4 * s, -1 * s), Color3.fromRGB(35, 45, 55), Enum.Material.Metal, nil, true)
			addPart(model, body, "Bow", Vector3.new(3.5 * s, 1.6 * s, 4 * s), CFrame.new(0, 0.2 * s, -8 * s), Color3.fromRGB(28, 38, 45), Enum.Material.Metal, nil, false)
			addPart(model, body, "Accent", Vector3.new(4.0 * s, 0.12 * s, 0.3 * s), CFrame.new(0, 1.2 * s, 2 * s), accentCol, Enum.Material.Neon, nil, false)
			addWakeStrip(model, body, s, 14, accentCol)
			addPart(model, body, "Periscope", Vector3.new(0.25 * s, 2.2 * s, 0.25 * s), CFrame.new(0, 4.2 * s, -1 * s), Color3.fromRGB(50, 55, 60), Enum.Material.Metal, nil, false)
			seatOffset = CFrame.new(0, 3.5 * s, -1 * s)
			labelY = 6.5 * s
		elseif kind == "Capital" then
			body.Size = Vector3.new(8 * s, 2.4 * s, 28 * s)
			body.Color = Color3.fromRGB(40, 55, 70)
			addPart(model, body, "Deck", Vector3.new(7.2 * s, 0.5 * s, 24 * s), CFrame.new(0, 1.3 * s, 0), Color3.fromRGB(50, 65, 80), Enum.Material.Metal, nil, true)
			addPart(model, body, "Superstructure", Vector3.new(4.5 * s, 3.5 * s, 8 * s), CFrame.new(0, 3.2 * s, 2 * s), Color3.fromRGB(45, 60, 75), Enum.Material.Metal, nil, true)
			addPart(model, body, "Bridge", Vector3.new(3.5 * s, 2.0 * s, 3.5 * s), CFrame.new(0, 5.5 * s, 1 * s), Color3.fromRGB(55, 70, 85), Enum.Material.Metal, nil, true)
			addPart(model, body, "Bow", Vector3.new(5.5 * s, 1.6 * s, 5 * s), CFrame.new(0, 0.6 * s, -12 * s), Color3.fromRGB(45, 60, 75), Enum.Material.Metal, nil, false)
			addPart(model, body, "TurretF", Vector3.new(2.4 * s, 1.2 * s, 2.8 * s), CFrame.new(0, 2.4 * s, -6 * s), Color3.fromRGB(35, 45, 55), Enum.Material.Metal, nil, false)
			addPart(model, body, "BarrelF", Vector3.new(0.4 * s, 0.4 * s, 5 * s), CFrame.new(0, 2.6 * s, -9 * s), Color3.fromRGB(30, 30, 30), Enum.Material.Metal, nil, false)
			addPart(model, body, "TurretA", Vector3.new(2.2 * s, 1.1 * s, 2.5 * s), CFrame.new(0, 2.3 * s, 8 * s), Color3.fromRGB(35, 45, 55), Enum.Material.Metal, nil, false)
			addPart(model, body, "Stack", Vector3.new(1.8 * s, 3.5 * s, 1.8 * s), CFrame.new(0, 5.5 * s, 5 * s), Color3.fromRGB(50, 50, 55), Enum.Material.Metal, nil, false)
			addPart(model, body, "Accent", Vector3.new(6.5 * s, 0.15 * s, 0.4 * s), CFrame.new(0, 1.8 * s, -2 * s), accentCol, Enum.Material.Neon, nil, false)
			addWakeStrip(model, body, s, 22, accentCol)
			addPart(model, body, "Mast", Vector3.new(0.35 * s, 6 * s, 0.35 * s), CFrame.new(0, 8.5 * s, 2 * s), Color3.fromRGB(55, 60, 70), Enum.Material.Metal, nil, false)
			addPart(model, body, "RadarDish", Vector3.new(2.4 * s, 0.35 * s, 2.4 * s), CFrame.new(0, 11.5 * s, 2 * s), accentCol, Enum.Material.Neon, Enum.PartType.Cylinder, false)
			seatOffset = CFrame.new(0, 6.2 * s, 1 * s)
			labelY = 9.0 * s
		else
			-- Patrol / Gun
			local gun = kind == "Gun" or id == "Gunboat" or id == "MissileBoat"
			local hull = Color3.fromRGB(45, 70, 85)
			body.Size = Vector3.new((if gun then 6.5 else 5.5) * s, 1.8 * s, (if gun then 14 else 11) * s)
			body.Color = hull
			addPart(model, body, "Deck", Vector3.new((if gun then 5.8 else 4.8) * s, 0.4 * s, (if gun then 11 else 8.5) * s), CFrame.new(0, 1.0 * s, 0), Color3.fromRGB(55, 80, 95), Enum.Material.Metal, nil, true)
			addPart(model, body, "Cabin", Vector3.new(3.2 * s, 2.0 * s, 3.5 * s), CFrame.new(0, 2.2 * s, -1.5 * s), Color3.fromRGB(40, 60, 75), Enum.Material.Metal, nil, true)
			addPart(model, body, "Bow", Vector3.new((if gun then 4.5 else 3.8) * s, 1.2 * s, 3.0 * s), CFrame.new(0, 0.4 * s, (if gun then -6.5 else -5.2) * s), Color3.fromRGB(50, 75, 90), Enum.Material.Metal, nil, false)
			addPart(model, body, "Accent", Vector3.new(4.0 * s, 0.12 * s, 0.35 * s), CFrame.new(0, 1.5 * s, -2 * s), accentCol, Enum.Material.Neon, nil, false)
			addWakeStrip(model, body, s, if gun then 11 else 8, accentCol)
			addPart(model, body, "BridgeGlass", Vector3.new(2.8 * s, 0.9 * s, 0.3 * s), CFrame.new(0, 2.8 * s, -3.0 * s), Color3.fromRGB(60, 100, 130), Enum.Material.Glass, nil, false)
			if gun then
				addPart(model, body, "Turret", Vector3.new(2.0 * s, 1.0 * s, 2.0 * s), CFrame.new(0, 2.8 * s, 2.5 * s), Color3.fromRGB(35, 45, 50), Enum.Material.Metal, nil, false)
				addPart(model, body, "Barrel", Vector3.new(0.35 * s, 0.35 * s, 3.5 * s), CFrame.new(0, 3.0 * s, 0.5 * s), Color3.fromRGB(30, 30, 30), Enum.Material.Metal, nil, false)
				addPart(model, body, "GunShield", Vector3.new(1.6 * s, 1.0 * s, 0.25 * s), CFrame.new(0, 3.2 * s, 1.4 * s), Color3.fromRGB(40, 50, 55), Enum.Material.Metal, nil, false)
			end
			seatOffset = CFrame.new(0, 2.8 * s, -1.2 * s)
			labelY = 5.5 * s
		end
	end

	if family == "WheeledLight" then
		kitWheeledLight()
	elseif family == "WheeledTruck" then
		kitWheeledTruck()
	elseif family == "WheeledAPC" then
		kitWheeledAPC()
	elseif family == "TrackedIFV" then
		kitTracked("IFV")
	elseif family == "TrackedMBT" then
		kitTracked("MBT")
	elseif family == "TrackedSPAAG" then
		kitTracked("SPAAG")
	elseif family == "TrackedArtillery" then
		kitTracked("Artillery")
	elseif family == "HeliLight" then
		kitHeli("Light")
	elseif family == "HeliTransport" then
		kitHeli("Transport")
	elseif family == "HeliAttack" then
		kitHeli("Attack")
	elseif family == "JetFighter" then
		kitJet("Fighter")
	elseif family == "JetStrike" then
		kitJet("Strike")
	elseif family == "JetBomber" then
		kitJet("Bomber")
	elseif family == "JetTransport" then
		kitJet("Transport")
	elseif family == "NavalPatrol" then
		kitNaval("Patrol")
	elseif family == "NavalGun" then
		kitNaval("Gun")
	elseif family == "NavalLanding" then
		kitNaval("Landing")
	elseif family == "NavalCapital" then
		kitNaval("Capital")
	elseif family == "NavalSub" then
		kitNaval("Sub")
	else
		body.Size = Vector3.new(6 * s, 2 * s, 10 * s)
		body.Color = olive
		addPart(model, body, "Cabin", Vector3.new(4 * s, 1.5 * s, 4 * s), CFrame.new(0, 1.5 * s, -1 * s), oliveDark, Enum.Material.SmoothPlastic, nil, true)
		addWheels(model, body, s, {
			Vector3.new(-2.5, -1.2, 3),
			Vector3.new(2.5, -1.2, 3),
			Vector3.new(-2.5, -1.2, -3),
			Vector3.new(2.5, -1.2, -3),
		}, 1.1)
		seatOffset = CFrame.new(0, 2.0 * s, -1 * s)
	end

	local cat = def.Category or "Ground"
	local mode = driveModeFor(def)
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 0.8, 2)
	seat.Color = Color3.fromRGB(70, 80, 60)
	seat.Material = Enum.Material.SmoothPlastic
	seat.CFrame = body.CFrame * seatOffset
	seat.Anchored = false
	seat.CanCollide = true
	seat.HeadsUpDisplay = false
	-- v70: the seat only reports ThrottleFloat / SteerFloat; the WE_DriveLV / WE_DriveAO movers drive
	seat.MaxSpeed = 0
	seat.Torque = 0
	seat.TurnSpeed = 0
	seat.Disabled = false
	seat:SetAttribute("WE_DriverSeat", true)
	seat.Parent = model
	weldTo(body, seat)
	model:SetAttribute("WE_Category", cat)
	model:SetAttribute("WE_KitFamily", family)
	if def.MeshAssetId and def.MeshAssetId ~= 0 then
		model:SetAttribute("MeshAssetId", def.MeshAssetId)
	end

	local extra = math.max(0, (def.Seats or 1) - 1)
	for i = 1, math.min(extra, 4) do
		local ps = Instance.new("Seat")
		ps.Name = "PassengerSeat" .. i
		ps.Size = Vector3.new(1.4, 0.5, 1.4)
		ps.Color = Color3.fromRGB(60, 70, 55)
		ps.CFrame = body.CFrame * CFrame.new((i % 2 == 0 and 1.4 or -1.4), seatOffset.Y, seatOffset.Z + 1.4 + math.floor((i - 1) / 2) * 1.5)
		ps.Anchored = false
		ps.CanCollide = true
		ps.Parent = model
		weldTo(body, ps)
	end

	do
		-- Mobile P1-8: no server nameplate and no key-name tips. The old nameplate billboard (always on top, 280 studs,
		-- keyboard tips) showed to everyone through the HUD. The owner-only nameplate is client-side
		-- (VehicleDriveClient); WE_LabelY is the kit's label height above the Chassis centre for it.
		model:SetAttribute("WE_LabelY", labelY)
		-- v36 ArmedJeep: static ARMED billboard on barrel (no fire logic yet). World-label rules: stud-scaled,
		-- MaxDistance <= 40, never AlwaysOnTop.
		if id == "ArmedJeep" then
			local barrel = model:FindFirstChild("Barrel")
			if barrel and barrel:IsA("BasePart") then
				local abb = Instance.new("BillboardGui")
				abb.Name = "WE_ArmedCue"
				abb.Size = UDim2.fromScale(2.4, 0.6) -- studs
				abb.StudsOffset = Vector3.new(0, 1.2, 0)
				abb.AlwaysOnTop = false
				abb.MaxDistance = 40
				abb.Parent = barrel
				local al = Instance.new("TextLabel")
				al.Size = UDim2.fromScale(1, 1)
				al.BackgroundColor3 = Color3.fromRGB(40, 20, 16)
				al.BackgroundTransparency = 0.2
				al.Text = "ARMED"
				al.TextColor3 = Color3.fromRGB(255, 180, 100)
				al.TextStrokeTransparency = 0.35
				al.Font = Enum.Font.GothamBold
				al.TextScaled = true
				al.Parent = abb
			end
		end
	end

	model.PrimaryPart = body
	-- Optional free Creator Store visual (non-colliding); Part kit stays authoritative
	pcall(function()
		VisualAssetService.TryAttachVehicleVisual(model, def.Id or "", family)
	end)
	CollectionService:AddTag(model, Constants.Tags.Vehicle)

	-- v70: movers + drive attributes (protocol for VehicleDriveClient). Built at `at`, NOT parented:
	-- RequestSpawn measures the footprint, chooses the spawn, PivotTo, then parents.
	createMovers(model, body, def, mode)
	local fp = footprintOf(model)
	for k, v in pairs(driveAttributes(def, fp, bonus, armorMult)) do
		model:SetAttribute(k, v)
	end
	model:SetAttribute("WE_DriveAuthority", "Server")
	model:SetAttribute("WE_DriverUserId", 0)
	if mode == "Car" then
		model:SetAttribute("WE_GroundDrive", "Client")
	end
	return model
end

local function meetsStructureReq(profile: any, def: VehicleDef): (boolean, string?)
	local req = def.RequiresStructure
	if not req then
		return true, nil
	end
	local level = 0
	if profile.BaseUpgrades then
		level = profile.BaseUpgrades[req.StructureId] or 0
	end
	if level < req.Level then
		return false, "MissingStructure"
	end
	return true, nil
end

local function meetsPrestigeReq(profile: any, def: VehicleDef): (boolean, string?)
	local needP = def.RequiresPrestige
	if typeof(needP) == "number" and needP > 0 then
		if (profile.Prestige or 0) < needP then
			return false, "PrestigeTooLow"
		end
	end
	local flag = def.RequiresRebirthFlag
	if typeof(flag) == "string" and flag ~= "" then
		local unlocks = profile.RebirthUnlocks
		if typeof(unlocks) ~= "table" or unlocks[flag] ~= true then
			return false, "MissingRebirthUnlock"
		end
	end
	return true, nil
end

-- ── State push (garage) ────────────────────────────────────────────────────────────────────────
local GATE_STRUCTURES = { "VehicleDepot", "Helipad", "Airfield", "Dock" }

-- P1-9: seconds until SPAWN is allowed again after the player's character took damage
local function damageLockLeft(userId: number): number
	local at = lastDamageAt[userId]
	if at == nil then
		return 0
	end
	return math.max(0, SpawnCfg.DamageLockSeconds - (now() - at))
end

local function cooldownLeft(userId: number, player: Player?): number
	local last = lastSpawnAt[userId]
	if not last then
		return 0
	end
	local cd = VehicleConfig.SpawnCooldownSeconds or 15
	if player and TerritoryService and TerritoryService.GetVehicleCooldownMult then
		cd = cd * math.max(0.1, TerritoryService.GetVehicleCooldownMult(player))
	end
	return math.max(0, cd - (now() - last))
end

local function gatesFor(profile: any): { [string]: any }
	local structures: { [string]: number } = {}
	local upgrades = profile.BaseUpgrades
	for _, sid in ipairs(GATE_STRUCTURES) do
		structures[sid] = if typeof(upgrades) == "table" then (tonumber(upgrades[sid]) or 0) else 0
	end
	local rebirth: { [string]: boolean } = {}
	if typeof(profile.RebirthUnlocks) == "table" then
		for k, v in pairs(profile.RebirthUnlocks) do
			if typeof(k) == "string" and v == true then
				rebirth[k] = true
			end
		end
	end
	return {
		Level = tonumber(profile.Level) or 1,
		Prestige = tonumber(profile.Prestige) or 0,
		Structures = structures,
		Rebirth = rebirth,
	}
end

local function pushState(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	local active = activeVehicles[player.UserId]
	local activeId: string? = nil
	if active and active.Parent then
		local vid = active:GetAttribute("VehicleId")
		if typeof(vid) == "string" then
			activeId = vid
		end
	end
	-- plain table (Types.VehicleStatePayload + v70 Gates; the client copes with a missing Gates)
	local payload = {
		Owned = profile.Vehicles,
		ActiveVehicleId = activeId,
		CooldownRemaining = cooldownLeft(player.UserId, player),
		Gates = gatesFor(profile),
	}
	local remote = RemoteSetup.Get(Constants.RemoteNames.VehicleStateUpdate) :: RemoteEvent
	remote:FireClient(player, payload)
end

-- Readable purchase / spawn refusals (garage G4)
local function errorText(err: string, def: VehicleDef?, player: Player?): string
	if err == "LevelTooLow" and def then
		return string.format("Reach Lv %d to unlock %s", def.UnlockLevel, def.DisplayName)
	elseif err == "MissingStructure" and def and def.RequiresStructure then
		local req = def.RequiresStructure
		local sdef = (BaseConfig.Structures :: any)[req.StructureId]
		local name = if sdef and typeof(sdef.DisplayName) == "string" then sdef.DisplayName else req.StructureId
		return string.format("Upgrade %s to L%d first", name, req.Level)
	elseif err == "PrestigeTooLow" and def then
		return string.format("Needs Prestige %d", tonumber(def.RequiresPrestige) or 0)
	elseif err == "MissingRebirthUnlock" then
		return "Needs a rebirth unlock"
	elseif err == "InsufficientCash" then
		return "Not enough cash"
	elseif err == "AlreadyOwned" then
		return "Already yours — tap SPAWN"
	elseif err == "NoProfile" then
		return "Still loading your save — try again"
	elseif err == "NoWater" then
		return "No open water to launch a boat"
	elseif err == "Cooldown" then
		local left = if player then math.ceil(cooldownLeft(player.UserId, player)) else 0
		return if left > 0 then string.format("Vehicle spawn cooling down (%ds)", left) else "Vehicle spawn cooling down"
	elseif err == "InCombat" then
		local left = if player then math.ceil(damageLockLeft(player.UserId)) else 0
		return if left > 0 then string.format("In combat — wait %ds", left) else "In combat — wait a moment"
	elseif err == "NotOwned" then
		return "Buy this vehicle first"
	elseif err == "SpawnBuildFailed" or err == "SpawnKitIncomplete" or err == "SpawnOrphaned" then
		return "Spawn failed — try again"
	elseif err == "InvalidId" or err == "UnknownVehicle" then
		return "Unknown vehicle"
	end
	return "Cannot do that right now (" .. err .. ")"
end

-- ── Spawn choice (spec §4) ─────────────────────────────────────────────────────────────────────
type PadDist = { Pad: SpawnPad, D: number }
type Offset2 = { X: number, Z: number }

local function footRadius(fp: Footprint): number
	return math.max(fp.HalfX, fp.HalfZ)
end

local function rideOffsetOf(fp: Footprint): number
	return fp.Clearance - BoatCfg.Draft
end

local function spotFree(ctx: SpawnCtx, cf: CFrame): boolean
	local fp = ctx.Footprint
	local pos = cf.Position
	local r = footRadius(fp)
	for _, o in ipairs(ctx.Occupied) do
		if (pos - o.Pos).Magnitude < r + o.Radius + 2 then
			return false
		end
	end
	local boxFree = ctx.BoxFree
	if boxFree then
		-- from just above the lowest solid point to the top of the kit, over the XZ footprint
		local lowY = -fp.Clearance + 0.15
		local highY = math.max(fp.Top, lowY + 0.5)
		local half = Vector3.new(fp.HalfX, (highY - lowY) * 0.5, fp.HalfZ)
		if not boxFree(cf * CFrame.new(0, (lowY + highY) * 0.5, 0), half) then
			return false
		end
	end
	return true
end

-- Land spot: chassis Y = surface + Clearance + 0.3 (a ray when available, else refTop).
local function landSpot(ctx: SpawnCtx, x: number, z: number, refTop: number, heading: number): CFrame?
	local y = refTop
	local surfaceY = ctx.SurfaceY
	if surfaceY then
		local hit = surfaceY(x, z, refTop)
		if hit ~= nil then
			if hit > refTop + SpawnCfg.MaxStepUp then
				return nil -- something solid stands here
			end
			y = hit
		end
	end
	return CFrame.new(x, y + ctx.Footprint.Clearance + SpawnCfg.Clearance, z) * CFrame.Angles(0, heading, 0)
end

local function aroundOffsets(fp: Footprint): { Offset2 }
	local s = 2 * footRadius(fp) + SpawnCfg.OffsetStep
	return { { X = 0, Z = 0 }, { X = s, Z = 0 }, { X = -s, Z = 0 }, { X = 0, Z = s }, { X = 0, Z = -s } }
end

local function firstFreeLand(ctx: SpawnCtx, x: number, z: number, refTop: number, heading: number, offsets: { Offset2 }): CFrame?
	for _, o in ipairs(offsets) do
		local cf = landSpot(ctx, x + o.X, z + o.Z, refTop, heading)
		if cf and spotFree(ctx, cf) then
			return cf
		end
	end
	return nil
end

local function padsByDistance(pads: { SpawnPad }, origin: Vector3?, wantNaval: boolean?, maxDist: number?): { PadDist }
	local out: { PadDist } = {}
	for _, pad in ipairs(pads) do
		if wantNaval == nil or pad.Naval == wantNaval then
			local d = if origin then (pad.Pos - origin).Magnitude else pad.Pos.Magnitude
			if maxDist == nil or d <= maxDist then
				table.insert(out, { Pad = pad, D = d })
			end
		end
	end
	table.sort(out, function(a: PadDist, b: PadDist): boolean
		return a.D < b.D
	end)
	return out
end

local function padTop(pad: SpawnPad): number
	return pad.Pos.Y + pad.Size.Y * 0.5
end

local function choice(cf: CFrame, source: string, state: string, speed: number?): SpawnChoice
	return { CFrame = cf, Source = source, State = state, Speed = speed or 0 }
end

--[[ P1-9: the land spot (centre or a footprint corner) lies in any water whose surface is above the ground there.
	Every WE_Water part counts (AllWater): another plot's dock basin is not boat water for this player, but a car
	must never land in it. Depth-independent (the ground ray ignores water, so it lands on the basin floor). ]]
local function overAnyWater(ctx: SpawnCtx, cf: CFrame): boolean
	local fp = ctx.Footprint
	local ground = cf.Position.Y - fp.Clearance - SpawnCfg.Clearance
	local lists = { ctx.WaterParts, ctx.AllWater or {} }
	for _, o in ipairs({ Vector3.zero, Vector3.new(fp.HalfX, 0, fp.HalfZ), Vector3.new(-fp.HalfX, 0, fp.HalfZ), Vector3.new(fp.HalfX, 0, -fp.HalfZ), Vector3.new(-fp.HalfX, 0, -fp.HalfZ) }) do
		local pt = cf:PointToWorldSpace(o)
		for _, list in ipairs(lists) do
			for _, w in ipairs(list) do
				local lp = w.CFrame:PointToObjectSpace(pt)
				if math.abs(lp.X) <= w.Size.X * 0.5 and math.abs(lp.Z) <= w.Size.Z * 0.5 and w.Position.Y + w.Size.Y * 0.5 > ground - 0.5 then
					return true
				end
			end
		end
	end
	return false
end

-- P1-9: nothing solid between the player's root part and the spot (never a spawn across a wall: the auto-sit would
-- carry the player through it, e.g. from outside an enemy base's perimeter wall into its courtyard)
local function inSight(ctx: SpawnCtx, from: Vector3, cf: CFrame): boolean
	local clear = ctx.Clear
	return clear == nil or clear(from, cf.Position + Vector3.new(0, 1, 0))
end

-- P1-9: open sky over the spot (no roof, upper floor or hangar within 40 studs): never inside a building
local function openSky(ctx: SpawnCtx, cf: CFrame): boolean
	local clear = ctx.Clear
	local top = cf.Position + Vector3.new(0, math.max(ctx.Footprint.Top, 1) + 0.5, 0)
	return clear == nil or clear(top, top + Vector3.new(0, 40, 0))
end

local function playerFront(ctx: SpawnCtx, state: string): SpawnChoice?
	local pp = ctx.PlayerPos
	if not pp then
		return nil
	end
	local look = flat(ctx.PlayerLook or Vector3.new(0, 0, -1))
	look = if look.Magnitude > 0.05 then look.Unit else Vector3.new(0, 0, -1)
	local ahead = pp + look * (SpawnCfg.FrontDistance + footRadius(ctx.Footprint))
	local heading = math.atan2(-look.X, -look.Z)
	-- land vehicles only (Car / Heli / Plane): never a spot over water (a player on a pier facing the sea), never
	-- across a wall (the auto-sit would carry the player through it) and never under a roof (inside a building)
	for _, o in ipairs(aroundOffsets(ctx.Footprint)) do
		local cf = landSpot(ctx, ahead.X + o.X, ahead.Z + o.Z, pp.Y - 3, heading)
		if cf and not overAnyWater(ctx, cf) and inSight(ctx, pp, cf) and openSky(ctx, cf) and spotFree(ctx, cf) then
			return choice(cf, "PlayerFront", state)
		end
	end
	return nil
end

--[[ Waterways C1: every plot-local → world conversion goes through the plot frame, i.e. the plot pad's CFrame
	(PlotPad / WE_BasePlot is built with BaseLayout.PlotCFrame(pos), which carries the plot yaw once
	BaseLayoutConfig.FaceMapCentre is on). A plot-local heading h becomes h + yawOf(frame). While the flag is off the
	pad's rotation is the identity, so every spot and heading below equals the old plot + (x, 0, z) exactly. ]]
local function plotFrame(ctx: SpawnCtx): CFrame?
	local cf = ctx.PlotCFrame
	if cf then
		return cf
	end
	local p = ctx.PlotPos
	return if p then CFrame.new(p) else nil
end

-- plot-local point (x, z) plus a plot-local offset (ox, oz) → world X, Z (base first, then the turned offset)
local function plotXZ(frame: CFrame, x: number, z: number, ox: number?, oz: number?): (number, number)
	local w = frame:PointToWorldSpace(Vector3.new(x, 0, z))
	if ox == nil and oz == nil then
		return w.X, w.Z
	end
	local o = frame:VectorToWorldSpace(Vector3.new(ox or 0, 0, oz or 0))
	return w.X + o.X, w.Z + o.Z
end

-- firstFreeLand at plot-local (x, z) with a plot-local heading; the offsets turn with the plot
local function firstFreePlotLand(
	ctx: SpawnCtx,
	frame: CFrame,
	x: number,
	z: number,
	refTop: number,
	heading: number,
	offsets: { Offset2 }
): CFrame?
	local h = heading + yawOf(frame)
	for _, o in ipairs(offsets) do
		local wx, wz = plotXZ(frame, x, z, o.X, o.Z)
		local cf = landSpot(ctx, wx, wz, refTop, h)
		if cf and spotFree(ctx, cf) then
			return cf
		end
	end
	return nil
end

local function lastResort(ctx: SpawnCtx, state: string): SpawnChoice
	local base = ctx.PlotPos or ctx.PlayerPos or Vector3.new(0, 0.5, 0)
	local y = base.Y + 0.5 + ctx.Footprint.Clearance + SpawnCfg.Clearance
	local frame = if ctx.PlotPos then plotFrame(ctx) else nil
	if frame then
		-- plot-local (0, PlotFallback.Z), turned with the plot
		local wx, wz = plotXZ(frame, 0, SpawnCfg.PlotFallback.Z)
		return choice(CFrame.new(wx, y, wz) * CFrame.Angles(0, yawOf(frame), 0), "WorldOrigin", state)
	end
	return choice(CFrame.new(base.X, y, base.Z), "WorldOrigin", state)
end

local function chooseCar(ctx: SpawnCtx): SpawnChoice
	local fp = ctx.Footprint
	local offsets = aroundOffsets(fp)
	if ctx.AwayFromHome then
		-- P1-9: away from your own plot SPAWN puts it in front of you, not on a pad 650 studs away or at home
		local front = playerFront(ctx, "Grounded")
		if front then
			return front
		end
	end
	if ctx.PlayerPos then
		for _, e in ipairs(padsByDistance(ctx.VehiclePads, ctx.PlayerPos, false, SpawnCfg.CarPadRadius)) do
			local cf = firstFreeLand(ctx, e.Pad.Pos.X, e.Pad.Pos.Z, padTop(e.Pad), yawOf(e.Pad.CFrame), offsets)
			if cf then
				return choice(cf, "VehicleSpawn", "Grounded")
			end
		end
	end
	local plot = ctx.PlotPos
	local frame = plotFrame(ctx)
	if plot and frame then
		local o = SpawnCfg.PlotFallback
		local cf = firstFreePlotLand(ctx, frame, o.X, o.Z, plot.Y + 0.5, 0, offsets)
		if cf then
			return choice(cf, "BasePlot", "Grounded")
		end
	end
	return playerFront(ctx, "Grounded") or lastResort(ctx, "Grounded")
end

local function chooseHeli(ctx: SpawnCtx): SpawnChoice
	local fp = ctx.Footprint
	local plot = ctx.PlotPos
	local frame = plotFrame(ctx)
	if ctx.AwayFromHome then
		local front = playerFront(ctx, "Landed") -- P1-9
		if front then
			return front
		end
	end
	if plot and frame and (ctx.Structures.Helipad or 0) >= 1 then
		local site = BaseLayoutConfig.Structures.Helipad.Site
		local refTop = plot.Y + 0.5 + SpawnCfg.HelipadDeckHeight
		local heading = SpawnCfg.HeliHeadingRad + yawOf(frame)
		for _, o in ipairs(SpawnCfg.HelipadSpots) do
			local wx, wz = plotXZ(frame, site.X, site.Z, o.X, o.Z)
			local cf = landSpot(ctx, wx, wz, refTop, heading)
			if cf and spotFree(ctx, cf) then
				return choice(cf, "Helipad", "Landed")
			end
		end
	end
	local origin = ctx.PlayerPos or plot
	local offsets = aroundOffsets(fp)
	for _, e in ipairs(padsByDistance(ctx.VehiclePads, origin, false, nil)) do
		local cf = firstFreeLand(ctx, e.Pad.Pos.X, e.Pad.Pos.Z, padTop(e.Pad), yawOf(e.Pad.CFrame), offsets)
		if cf then
			return choice(cf, "VehicleSpawn", "Landed")
		end
	end
	return playerFront(ctx, "Landed") or lastResort(ctx, "Landed")
end

local function runwayRoad(): { X: number, Z: number, SizeX: number, SizeZ: number }?
	for _, r in ipairs(BaseLayoutConfig.Roads) do
		if r.Name == SpawnCfg.RunwayRoad then
			return r
		end
	end
	return nil
end

local function choosePlane(ctx: SpawnCtx): SpawnChoice
	local fp = ctx.Footprint
	local plot = ctx.PlotPos
	local road = runwayRoad()
	local frame = plotFrame(ctx)
	if ctx.AwayFromHome then
		local front = playerFront(ctx, "Grounded") -- P1-9: taxi and take off from where you stand
		if front then
			return front
		end
	end
	if plot and frame and road and (ctx.Structures.Airfield or 0) >= 1 then
		-- start 12 studs in from the end nearer the plot edge, facing along the runway toward the other end
		-- (runway X/Z, the ends and the heading are plot-local; plotXZ / yawOf(frame) turn them with the plot)
		local minX, maxX = road.X - road.SizeX * 0.5, road.X + road.SizeX * 0.5
		local fromMin = math.abs(minX) >= math.abs(maxX)
		local startX = if fromMin then minX + SpawnCfg.RunwayInset else maxX - SpawnCfg.RunwayInset
		local step = if fromMin then 1 else -1
		local heading = (if fromMin then -math.pi / 2 else math.pi / 2) + yawOf(frame) -- plot +X / -X
		local refTop = plot.Y + 0.5 + SpawnCfg.RunwayHeight
		local spacing = 2 * fp.HalfZ + 6
		for k = 0, 3 do
			local x = startX + step * k * spacing
			if math.abs(x - road.X) > road.SizeX * 0.5 - fp.HalfZ then
				break
			end
			if k > 0 and math.abs(x - startX) > road.SizeX * 0.5 then
				break -- keep at least half the runway ahead
			end
			local wx, wz = plotXZ(frame, x, road.Z)
			local cf = landSpot(ctx, wx, wz, refTop, heading)
			if cf and spotFree(ctx, cf) then
				return choice(cf, "Runway", "Grounded")
			end
		end
	end
	-- air start over the nearest land pad
	local vto = ctx.TakeoffSpeed or PlaneCfg.TakeoffMin
	local speed = PlaneCfg.AirStartSpeedFrac * vto
	local origin = ctx.PlayerPos or plot
	for _, e in ipairs(padsByDistance(ctx.VehiclePads, origin, false, nil)) do
		local p = e.Pad.Pos + Vector3.new(0, PlaneCfg.AirStartHeight, 0)
		local cf = CFrame.new(p) * CFrame.Angles(0, 0, 0)
		if spotFree(ctx, cf) then
			return choice(cf, "AirStart", "Airborne", speed)
		end
	end
	local base = origin or Vector3.new(0, 0.5, 0)
	return choice(CFrame.new(base + Vector3.new(0, PlaneCfg.AirStartHeight, 0)), "AirStart", "Airborne", speed)
end

-- Boat spot: the centre and the 4 hull corners over water (margin 1, land probe), free.
local function boatSpot(ctx: SpawnCtx, cx: number, cz: number, h: number, refY: number): CFrame?
	local fp = ctx.Footprint
	local parts = ctx.WaterParts
	local margin = WaterCfg.SpawnMargin
	local centre = Vector3.new(cx, refY, cz)
	local top = waterSurfaceAt(parts, centre, margin, ctx.LandProbe)
	if top == nil then
		return nil
	end
	local f, r = fwd(h), right(h)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local p = centre + r * (sx * fp.HalfX) + f * (sz * fp.HalfZ)
			if waterSurfaceAt(parts, p, margin, ctx.LandProbe) == nil then
				return nil
			end
		end
	end
	local cf = CFrame.new(cx, top + rideOffsetOf(fp), cz) * CFrame.Angles(0, h, 0)
	if not spotFree(ctx, cf) then
		return nil
	end
	return cf
end

local function plotBasin(ctx: SpawnCtx): BasePart?
	local plotId = ctx.PlotId
	if plotId == nil then
		return nil
	end
	for _, p in ipairs(ctx.WaterParts) do
		if p:GetAttribute("WE_PlotId") == plotId then
			return p
		end
	end
	return nil
end

local function chooseBoat(ctx: SpawnCtx): (SpawnChoice?, string?)
	local fp = ctx.Footprint
	-- own dock basin, only when a channel links it to the sea
	local function basinChoice(): SpawnChoice?
		local basin = plotBasin(ctx)
		if basin and ctx.PlotPos and (ctx.Structures.Dock or 0) >= 1 and isConnectedToSea(basin, ctx.WaterParts) then
			local bcf = basin.CFrame
			local top = basin.Position.Y + basin.Size.Y * 0.5
			local step = WaterCfg.GridStep
			local pts: { Vector3 } = {}
			local hx, hz = basin.Size.X * 0.5, basin.Size.Z * 0.5
			local nx, nz = math.floor(hx / step), math.floor(hz / step)
			for i = -nx, nx do
				for j = -nz, nz do
					table.insert(pts, Vector3.new(i * step, 0, j * step))
				end
			end
			table.sort(pts, function(a: Vector3, b: Vector3): boolean
				return a.Magnitude < b.Magnitude
			end)
			local byaw = yawOf(bcf)
			for _, lp in ipairs(pts) do
				local wp = bcf:PointToWorldSpace(lp)
				for _, h in ipairs({ byaw, byaw + math.pi / 2 }) do
					local cf = boatSpot(ctx, wp.X, wp.Z, h, top)
					if cf then
						return choice(cf, "DockBasin", "Floating")
					end
				end
			end
		end
		return nil
	end
	-- naval pads by distance (no limit): 8 directions, bow pointing away from the pad
	local function padChoice(): SpawnChoice?
		local origin = ctx.PlayerPos or ctx.PlotPos
		for _, e in ipairs(padsByDistance(ctx.NavalPads, origin, nil, nil)) do
			local pad = e.Pad
			local padHalf = math.max(pad.Size.X, pad.Size.Z) * 0.5
			local away = if origin then flat(pad.Pos - origin) else Vector3.new(0, 0, 1)
			away = if away.Magnitude > 0.05 then away.Unit else Vector3.new(0, 0, 1)
			local dirs: { Vector3 } = {}
			for k = 0, 7 do
				table.insert(dirs, fwd(k * math.pi / 4))
			end
			table.sort(dirs, function(a: Vector3, b: Vector3): boolean
				return a:Dot(away) > b:Dot(away)
			end)
			for _, d in ipairs(dirs) do
				local c = pad.Pos + d * (padHalf + fp.HalfZ + SpawnCfg.NavalPadGap)
				local h = math.atan2(-d.X, -d.Z)
				local cf = boatSpot(ctx, c.X, c.Z, h, pad.Pos.Y)
				if cf then
					return choice(cf, "NavalSpawn", "Floating")
				end
			end
		end
		return nil
	end
	-- centre of the largest water part (and a ring around it)
	local function openChoice(): SpawnChoice?
		local largest: BasePart? = nil
		local area = -1
		for _, p in ipairs(ctx.WaterParts) do
			local a = p.Size.X * p.Size.Z
			if a > area then
				area = a
				largest = p
			end
		end
		if largest then
			local top = largest.Position.Y + largest.Size.Y * 0.5
			local c = largest.Position
			local ring = 2 * footRadius(fp) + SpawnCfg.OffsetStep
			for k = 0, 8 do
				local off = if k == 0 then Vector3.zero else fwd((k - 1) * math.pi / 4) * ring
				local cf = boatSpot(ctx, c.X + off.X, c.Z + off.Z, yawOf(largest.CFrame), top)
				if cf then
					return choice(cf, "OpenWater", "Floating")
				end
			end
		end
		return nil
	end
	-- P1-9: away from your own plot, water right in front of you first (never your dock basin across the map first)
	local function frontChoice(): SpawnChoice?
		local pp = ctx.PlayerPos
		if not pp then
			return nil
		end
		local look = flat(ctx.PlayerLook or Vector3.new(0, 0, -1))
		look = if look.Magnitude > 0.05 then look.Unit else Vector3.new(0, 0, -1)
		local ahead = pp + look * (SpawnCfg.FrontDistance + footRadius(fp))
		local cf = boatSpot(ctx, ahead.X, ahead.Z, math.atan2(-look.X, -look.Z), pp.Y)
		return if cf and inSight(ctx, pp, cf) then choice(cf, "PlayerFront", "Floating") else nil
	end
	local order = if ctx.AwayFromHome then { frontChoice, padChoice, basinChoice, openChoice } else { basinChoice, padChoice, openChoice }
	for _, step in ipairs(order) do
		local c = step()
		if c then
			return c, nil
		end
	end
	return nil, "NoWater"
end

local function chooseSpawn(ctx: SpawnCtx): (SpawnChoice?, string?)
	local mode = ctx.Mode
	if mode == "Boat" then
		return chooseBoat(ctx)
	elseif mode == "Heli" then
		return chooseHeli(ctx), nil
	elseif mode == "Plane" then
		return choosePlane(ctx), nil
	end
	return chooseCar(ctx), nil
end

-- Real-world ctx (raycasts, pads, water, other vehicles)
local function characterList(): { Instance }
	local list: { Instance } = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		local ch = pl.Character
		if ch then
			table.insert(list, ch)
		end
	end
	return list
end

local function exclusionList(withWater: boolean, withPads: boolean): { Instance }
	local list = characterList()
	table.insert(list, ensureFolder())
	if withWater then
		for _, w in ipairs(getWaterParts()) do
			table.insert(list, w)
		end
	end
	if withPads then
		for _, tag in ipairs({ Constants.Tags.VehicleSpawn, Constants.Tags.NavalSpawn }) do
			for _, inst in ipairs(CollectionService:GetTagged(tag)) do
				table.insert(list, inst)
			end
		end
	end
	return list
end

local function rayParams(exclude: { Instance }): RaycastParams
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = exclude
	rp.RespectCanCollide = true
	return rp
end

local function findPlotPart(plotId: any): BasePart?
	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.BasePlot)) do
		if inst:IsA("BasePart") and inst:GetAttribute("PlotId") == plotId then
			return inst
		end
	end
	return nil
end

-- P1-9: pos on the plot pad's rectangle (plot-local XZ, grown by OwnPlotMargin)
local function insidePlot(plot: BasePart, pos: Vector3): boolean
	local lp = plot.CFrame:PointToObjectSpace(pos)
	local m = SpawnCfg.OwnPlotMargin
	return math.abs(lp.X) <= plot.Size.X * 0.5 + m and math.abs(lp.Z) <= plot.Size.Z * 0.5 + m
end

-- P1-9: the player stands inside their own plot (nil plot / no character → false)
local function playerAtHome(player: Player, profile: any): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) or not (profile and profile.BasePlotId) then
		return false
	end
	local plot = findPlotPart(profile.BasePlotId)
	return plot ~= nil and insidePlot(plot, root.Position)
end

local function buildSpawnCtx(player: Player, profile: any, mode: string, fp: Footprint, attrs: { [string]: any }, exclude: Model?): SpawnCtx
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local playerPos: Vector3? = nil
	local playerLook: Vector3? = nil
	if root and root:IsA("BasePart") then
		playerPos = root.Position
		playerLook = root.CFrame.LookVector
	end
	local plotPos: Vector3? = nil
	local plotCFrame: CFrame? = nil
	local plotId: number? = nil
	local awayFromHome = false
	if profile and profile.BasePlotId then
		local plot = findPlotPart(profile.BasePlotId)
		if plot then
			plotPos = plot.Position
			plotCFrame = plot.CFrame -- C1: the pad carries the plot yaw
			plotId = tonumber(profile.BasePlotId)
			awayFromHome = playerPos ~= nil and not insidePlot(plot, playerPos)
		end
	end
	-- C5: someone else's DockWater / SeaGateWater is not water for this player's boats
	local ownPlotId: number? = if profile then tonumber(profile.BasePlotId) else nil
	local structures: { [string]: number } = {}
	if profile and typeof(profile.BaseUpgrades) == "table" then
		for k, v in pairs(profile.BaseUpgrades) do
			if typeof(k) == "string" then
				structures[k] = tonumber(v) or 0
			end
		end
	end
	local vehiclePads: { SpawnPad } = {}
	local navalPads: { SpawnPad } = {}
	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.VehicleSpawn)) do
		if inst:IsA("BasePart") and inst.Parent then
			table.insert(vehiclePads, {
				Pos = inst.Position,
				CFrame = inst.CFrame,
				Size = inst.Size,
				Naval = CollectionService:HasTag(inst, Constants.Tags.NavalSpawn),
			})
		end
	end
	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.NavalSpawn)) do
		if inst:IsA("BasePart") and inst.Parent then
			table.insert(navalPads, { Pos = inst.Position, CFrame = inst.CFrame, Size = inst.Size, Naval = true })
		end
	end
	local occupied: { OccupiedSpot } = {}
	for m, rec in pairs(vehicles) do
		if m ~= exclude and m.Parent and rec.Chassis.Parent then
			local hx = tonumber(m:GetAttribute("WE_HalfWidth")) or 4
			local hz = tonumber(m:GetAttribute("WE_HalfLength")) or 6
			table.insert(occupied, { Pos = rec.Chassis.Position, Radius = math.max(hx, hz) })
		end
	end
	local groundEx = rayParams(exclusionList(true, false))
	local ctx: SpawnCtx = {
		Mode = mode,
		PlayerPos = playerPos,
		PlayerLook = playerLook,
		PlotPos = plotPos,
		PlotCFrame = plotCFrame,
		PlotId = plotId,
		Structures = structures,
		Footprint = fp,
		TakeoffSpeed = tonumber(attrs.WE_TakeoffSpeed),
		VehiclePads = vehiclePads,
		NavalPads = navalPads,
		WaterParts = waterPartsFor(ownPlotId),
		Occupied = occupied,
		SurfaceY = function(x: number, z: number, refY: number): number?
			local hit = Workspace:Raycast(Vector3.new(x, refY + 10, z), Vector3.new(0, -40, 0), groundEx)
			return if hit then hit.Position.Y else nil
		end,
		LandProbe = function(x: number, z: number, top: number): boolean
			local h = WaterCfg.LandProbeHeight
			local hit = Workspace:Raycast(Vector3.new(x, top + h, z), Vector3.new(0, -(h + 0.05), 0), groundEx)
			return hit ~= nil and hit.Position.Y > top - 0.05
		end,
		BoxFree = function(cf: CFrame, half: Vector3): boolean
			local op = OverlapParams.new()
			op.FilterType = Enum.RaycastFilterType.Exclude
			op.FilterDescendantsInstances = exclusionList(true, true)
			op.RespectCanCollide = true
			op.MaxParts = 1
			local hits = Workspace:GetPartBoundsInBox(cf, half * 2, op)
			return #hits == 0
		end,
		AwayFromHome = awayFromHome,
		AllWater = getWaterParts(),
		Clear = function(from: Vector3, to: Vector3): boolean
			return Workspace:Raycast(from, to - from, groundEx) == nil
		end,
	}
	return ctx
end

-- ── Vehicle records: ownership handoff, idle, fallback, checks ─────────────────────────────────
local function setAuthority(rec: VehicleRec, authority: string)
	if rec.Authority ~= authority then
		rec.Authority = authority
		rec.Model:SetAttribute("WE_DriveAuthority", authority)
	end
	-- the client may have written the movers: the next server write always goes through
	rec.OutVel = nil
	rec.OutHold = nil
	rec.OutRot = nil
end

local function applyOut(rec: VehicleRec, out: DriveOut)
	local lv, ao = rec.LV, rec.AO
	if lv.Parent == nil or ao.Parent == nil then
		return
	end
	if rec.OutVel ~= out.Velocity then
		lv.VectorVelocity = out.Velocity
		rec.OutVel = out.Velocity
	end
	if rec.OutHold ~= out.HoldVertical then
		local f = rec.Force
		lv.MaxAxesForce = Vector3.new(f, if out.HoldVertical then f else 0, f)
		rec.OutHold = out.HoldVertical
	end
	local rot = out.Orientation.Rotation
	if rec.OutRot ~= rot then
		ao.CFrame = rot
		rec.OutRot = rot
	end
end

local function refreshMoverLimits(rec: VehicleRec)
	local mass = (rec.Chassis :: any).AssemblyMass
	if typeof(mass) ~= "number" or mass <= 0 then
		mass = estimateMass(rec.Model)
	end
	local hold = rec.OutHold
	if hold == nil then
		hold = rec.LV.MaxAxesForce.Y > 0
	end
	rec.Force = setMoverLimits(rec.LV, rec.AO, rec.Chassis, rec.Mode, rec.Def.Seats or 1, mass, hold == true)
end

local function playerOfHumanoid(hum: Instance?): Player?
	if hum == nil then
		return nil
	end
	local char = hum.Parent
	if char == nil then
		return nil
	end
	return Players:GetPlayerFromCharacter(char)
end

local function seatedDriver(rec: VehicleRec): Player?
	return playerOfHumanoid(rec.Seat.Occupant)
end

local function ejectSeat(seat: BasePart)
	local weld = seat:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end
end

local function zeroVelocity(part: BasePart)
	pcall(function()
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
	end)
end

local function setNetworkOwner(part: BasePart, owner: Player?): boolean
	local ok = pcall(function()
		part:SetNetworkOwner(owner)
	end)
	return ok
end

-- Every assembly the vehicle is made of: the chassis (+ welded kit, seats, catalog dress) and each hinge wheel.
local function ownPartsOf(model: Model, chassis: BasePart): { BasePart }
	local list: { BasePart } = { chassis }
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("WE_PhysicsWheel") == true then
			table.insert(list, d)
		end
	end
	return list
end

-- Whoever simulates owns everything: the chassis assembly and every wheel assembly (true = no call refused).
local function setOwner(rec: VehicleRec, owner: Player?): boolean
	local ok = true
	for _, p in ipairs(rec.OwnParts) do
		if p.Parent ~= nil and not setNetworkOwner(p, owner) then
			ok = false
		end
	end
	return ok
end

--[[ ("drv" | "srv" | "split" | "oth" | "unk", per-part detail "drv,drv,srv,…"). GetNetworkOwner is server-only and
	errors on anchored parts ("err"); an unreadable part is not evidence of a wrong owner ("unk" = the probe neither
	counts nor clears; a pinned car is caught by the no-motion check instead). ]]
local function ownerState(rec: VehicleRec, driver: Player?): (string, string)
	local tags: { string } = {}
	local allDrv, allSrv, anyOth, anyErr = true, true, false, false
	for i, p in ipairs(rec.OwnParts) do
		local ok, o = pcall(function(): Player?
			return p:GetNetworkOwner()
		end)
		local tag = if not ok then "err" elseif o == nil then "srv" elseif o == driver then "drv" else "oth"
		tags[i] = tag
		if tag == "err" then
			anyErr = true
		else
			allDrv = allDrv and tag == "drv"
			allSrv = allSrv and tag == "srv"
			anyOth = anyOth or tag == "oth"
		end
	end
	local st = if anyOth then "oth" elseif anyErr and allDrv then "unk" elseif allDrv then "drv" elseif allSrv and not anyErr then "srv" else "split"
	return st, table.concat(tags, ",")
end

local function resetValid(rec: VehicleRec, t: number)
	local cf = rec.Chassis.CFrame
	rec.LastValid = { CFrame = cf, Pos = cf.Position, T = t }
	rec.Window = { Pos = cf.Position, T = t }
	rec.LastSampleT = t
	rec.LastSamplePos = cf.Position
	rec.SpeedFlags = 0
	rec.OffWaterFor = 0
end

local function anyOccupied(rec: VehicleRec): boolean
	if rec.Seat.Occupant ~= nil then
		return true
	end
	for _, s in ipairs(rec.Passengers) do
		if s.Parent and s.Occupant ~= nil then
			return true
		end
	end
	return false
end

local aglParams: RaycastParams? = nil
local aglParamsAt = -math.huge

local function groundRayParams(t: number): RaycastParams
	local cached = aglParams
	if cached and t - aglParamsAt < WaterCfg.RefreshSeconds then
		return cached
	end
	local rp = rayParams(exclusionList(false, false))
	aglParams = rp
	aglParamsAt = t
	return rp
end

-- C5: the water this boat may use (its owner's plot water + public water). Owner's BasePlotId is read live from
-- the profile (nil until the real save loaded → public water only).
local function recWaterParts(rec: VehicleRec): { BasePart }
	local owner: Player? = rec.Owner
	local profile = if owner and DataService then DataService.GetProfile(owner) else nil
	return waterPartsFor(if profile then tonumber(profile.BasePlotId) else nil)
end

local function senseFor(rec: VehicleRec, t: number): DriveSense
	local cf = rec.Chassis.CFrame
	local pos = cf.Position
	local agl = math.huge
	if rec.Mode == "Heli" or rec.Mode == "Plane" then
		local hit = Workspace:Raycast(pos, Vector3.new(0, -600, 0), groundRayParams(t))
		if hit then
			agl = (pos.Y - hit.Position.Y) - (tonumber(rec.Model:GetAttribute("WE_GroundClearance")) or 0)
		end
	end
	local waterY: number? = nil
	if rec.Mode == "Boat" then
		waterY = waterSurfaceAt(recWaterParts(rec), pos, 0, nil)
	end
	return {
		Position = pos,
		Velocity = partVelocity(rec.Chassis),
		Yaw = yawOf(cf),
		UpY = cf.UpVector.Y,
		AGL = agl,
		WaterY = waterY,
		Time = t,
	}
end

local function idleStep(rec: VehicleRec, t: number, dt: number)
	if rec.Idle.ReturnPos == nil then
		rec.Idle.ReturnPos = rec.LastValid.Pos
	end
	local out = idleTarget(rec.Mode, rec.Params, rec.Idle, senseFor(rec, t), dt)
	applyOut(rec, out)
end

local function seatInput(seat: VehicleSeat): DriveInput
	-- a dead driver's client stops updating the seat: its last ThrottleFloat (e.g. W held when killed) is stale
	local occ = seat.Occupant
	if occ == nil or (tonumber(occ.Health) or 0) <= 0 then
		return { Throttle = 0, Steer = 0, Lift = 0, Strafe = 0 }
	end
	return { Throttle = unitInput(seat.ThrottleFloat), Steer = unitInput(seat.SteerFloat), Lift = 0, Strafe = 0 }
end

-- F5b: the client's input stream while fresh, else the seat floats (an old cached client sends no stream)
local function serverInput(rec: VehicleRec, t: number): DriveInput
	local occ = rec.Seat.Occupant
	if occ == nil or (tonumber(occ.Health) or 0) <= 0 then
		return { Throttle = 0, Steer = 0, Lift = 0, Strafe = 0 }
	end
	local at = rec.InAt
	if at ~= nil and t - at <= W.StreamStaleSeconds then
		return { Throttle = rec.InT, Steer = rec.InS, Lift = rec.InL, Strafe = 0 }
	end
	return seatInput(rec.Seat)
end

--[[ "The driver is pushing" = input that must move this vehicle. Car/Boat: |throttle| (spec). Aircraft refine
	the spec's rule so nothing trips on a landed craft: a landed heli ignores the stick until it lifts off (lift up
	only), and a plane's throttle-back at rest moves nothing (throttle forward only). ]]
local function pushing(rec: VehicleRec, input: DriveInput): boolean
	local th = W.PushThrottle
	if rec.Mode == "Heli" then
		return input.Lift > th
	elseif rec.Mode == "Plane" then
		return input.Throttle > th
	end
	return math.abs(input.Throttle) > th
end

-- F5i diagnostics: what could pin this vehicle (anchored parts, foreign movers / joints, movers in its riders)
local CONSTRAINT_CLASSES: { [string]: boolean } = {
	AlignOrientation = true, AlignPosition = true, AngularVelocity = true, BallSocketConstraint = true,
	HingeConstraint = true, LineForce = true, LinearVelocity = true, PlaneConstraint = true, Plane = true,
	PrismaticConstraint = true, CylindricalConstraint = true, RigidConstraint = true, RodConstraint = true,
	RopeConstraint = true, SpringConstraint = true, Torque = true, TorsionSpringConstraint = true,
	UniversalConstraint = true, VectorForce = true, AnimationConstraint = true,
}
local BODYMOVER_CLASSES: { [string]: boolean } = {
	BodyAngularVelocity = true, BodyForce = true, BodyGyro = true, BodyPosition = true, BodyThrust = true,
	BodyVelocity = true, RocketPropulsion = true,
}
local JOINT_CLASSES: { [string]: boolean } = {
	Weld = true, Motor = true, Motor6D = true, Snap = true, ManualWeld = true, Glue = true, ManualGlue = true,
	Rotate = true, RotateP = true, RotateV = true, VelocityMotor = true,
}

local function isMover(d: Instance): boolean
	local c = d.ClassName
	return BODYMOVER_CLASSES[c] == true or CONSTRAINT_CLASSES[c] == true or d:IsA("BodyMover") or d:IsA("Constraint")
end

local function isOwnDriveObject(d: Instance): boolean
	local n = d.Name
	return n == "WE_DriveLV"
		or n == "WE_DriveAO"
		or n == "SeatWeld"
		or string.sub(n, 1, 17) == "WE_WheelNoCollide"
		or (d:IsA("HingeConstraint") and d:GetAttribute("WE_DriveHinge") == true)
end

local function riderCharacters(rec: VehicleRec): { Instance }
	local list: { Instance } = {}
	local seats: { BasePart } = { rec.Seat }
	for _, s in ipairs(rec.Passengers) do
		table.insert(seats, s)
	end
	for _, s in ipairs(seats) do
		local occ = if s.Parent then (s :: any).Occupant else nil
		local ch = if occ then occ.Parent else nil
		if ch then
			table.insert(list, ch)
		end
	end
	return list
end

local function countPins(rec: VehicleRec): (number, string)
	local n = 0
	local names: { string } = {}
	local function add(what: string)
		n += 1
		if #names < 3 then
			table.insert(names, what)
		end
	end
	for _, d in ipairs(rec.Model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Anchored then
				add("anchored:" .. d.Name)
			end
		elseif (isMover(d) or JOINT_CLASSES[d.ClassName] == true or d:IsA("JointInstance")) and not isOwnDriveObject(d) then
			add(d.ClassName .. ":" .. d.Name)
		end
	end
	for _, ch in ipairs(riderCharacters(rec)) do
		for _, d in ipairs(ch:GetDescendants()) do
			if d:IsA("BasePart") then
				if d.Anchored then
					add("rider-anchored:" .. d.Name)
				end
			elseif isMover(d) then
				local c = d.ClassName
				if c ~= "AnimationConstraint" and c ~= "BallSocketConstraint" and c ~= "HingeConstraint" then
					add("rider-" .. c .. ":" .. d.Name)
				end
			end
		end
	end
	return n, table.concat(names, ",")
end

-- occupied passenger seats whose occupant is not a player (F8 ejects them; the log proves it)
local function npcRiders(rec: VehicleRec): number
	local n = 0
	for _, s in ipairs(rec.Passengers) do
		local occ = if s.Parent then s.Occupant else nil
		if occ ~= nil and playerOfHumanoid(occ) == nil then
			n += 1
		end
	end
	return n
end

local function signed(x: number): string
	return string.format("%+.2f", x)
end

-- a client-sent field for a log line: short, printable
local function logField(v: any): string
	local str = string.sub(tostring(v), 1, 16)
	return (string.gsub(str, "[^%w%.%+%-_]", "?"))
end

local function movedFromSit(rec: VehicleRec): number
	local from = rec.HandOffPos
	if from == nil then
		return 0
	end
	local d = rec.Chassis.Position - from
	return if rec.Mode == "Heli" or rec.Mode == "Plane" then d.Magnitude else Vector3.new(d.X, 0, d.Z).Magnitude
end

-- one server log line (F5i)
local function diagLine(rec: VehicleRec, t: number, head: string, extra: any?): string
	local st, detail = ownerState(rec, rec.Owner)
	local seat = rec.Seat
	local ex = ""
	if typeof(extra) == "table" then
		ex = string.format(" extra=T=%s Spd=%s R=%s Src=%s", logField(extra.T), logField(extra.Spd), logField(extra.R), logField(extra.Src))
	end
	local inAge = if rec.InAt ~= nil then string.format("%.1f", t - (rec.InAt :: number)) else "-"
	return string.format(
		"[VehicleService] %s u=%d %s auth=%s own=%s(%s) hello=%d in=%s/%s@%s seatT=%s/%s lvS=%.1f moved=%.1f pins=%d(%s) npc=%d catalog=%s%s",
		head,
		rec.OwnerUserId,
		tostring(rec.Def.Id),
		rec.Authority,
		st,
		detail,
		if rec.HelloAt ~= nil then 1 else 0,
		signed(rec.InT),
		signed(rec.InS),
		inAge,
		signed(unitInput(seat.ThrottleFloat)),
		signed(unitInput(seat.SteerFloat)),
		rec.LV.VectorVelocity.Magnitude,
		movedFromSit(rec),
		rec.Pins,
		rec.PinList,
		npcRiders(rec),
		tostring(rec.Model:GetAttribute("WE_CatalogAssetId") or "-"),
		ex
	)
end

-- F5j: the compact WE_Diag attribute (debug users only); the client's NO DRIVE line parses these key=value pairs
local function diagCompact(rec: VehicleRec): string
	local st = ownerState(rec, rec.Owner)
	local seat = rec.Seat
	return string.format(
		"own=%s hello=%d in=%s/%s seat=%s/%s lv=%.0f moved=%.1f pins=%d npc=%d fail=%s",
		st,
		if rec.HelloAt ~= nil then 1 else 0,
		signed(rec.InT),
		signed(rec.InS),
		signed(unitInput(seat.ThrottleFloat)),
		signed(unitInput(seat.SteerFloat)),
		rec.LV.VectorVelocity.Magnitude,
		movedFromSit(rec),
		rec.Pins,
		npcRiders(rec),
		rec.BrokenReason or "-"
	)
end

-- Fallback / trip: the server runs the Car / Boat law from the client's input stream (or the seat floats).
local function fallbackStep(rec: VehicleRec, t: number, dt: number)
	local sense = senseFor(rec, t)
	local st: DriveState = rec.Fallback or newDriveState(sense)
	rec.Fallback = st
	local input = serverInput(rec, t)
	local out: DriveOut
	if rec.Mode == "Boat" then
		local dir, near, far = boatProbe(st, rec.Params, input)
		local f = fwd(st.Heading) * dir
		local parts = recWaterParts(rec)
		sense.WaterNear = waterSurfaceAt(parts, sense.Position + f * near, 0, nil) ~= nil
		sense.WaterFar = waterSurfaceAt(parts, sense.Position + f * far, 0, nil) ~= nil
		out = boatStep(st, rec.Params, input, sense, dt)
	else
		out = carStep(st, rec.Params, input, sense, dt)
	end
	applyOut(rec, out)
end

-- Car fallback (name kept from v27-v69; the old server LV + "LV+HingeMotor" path is gone: wheels roll
-- free and the WE_DriveLV / WE_DriveAO movers carry the car). Boats share the same loop.
-- F5c: the server both drives and simulates (owns every assembly), so its own mover values act.
local function startGroundDrive(rec: VehicleRec, t: number)
	setAuthority(rec, "Fallback")
	if not setOwner(rec, nil) then
		warn("[VehicleService] Fallback: SetNetworkOwner(nil) refused", rec.Def.Id) -- server writes still replicate to the owner
	end
	rec.Fallback = newDriveState(senseFor(rec, t))
	if rec.Mode == "Car" then
		rec.Model:SetAttribute("WE_GroundDrive", "Fallback")
	end
end

local function stopDrive(rec: VehicleRec)
	rec.Fallback = nil
	if rec.Mode == "Car" then
		rec.Model:SetAttribute("WE_GroundDrive", "Client")
	end
end

-- Driver (owner) seated: give them the physics. fresh = a new sit (vs the end of a correction). F5d.
local function handOff(rec: VehicleRec, player: Player, t: number, fresh: boolean)
	rec.CorrectUntil = nil
	rec.CorrectPos = nil
	rec.DriverUserId = player.UserId
	rec.Model:SetAttribute("WE_DriverUserId", player.UserId)
	local ground = rec.Mode == "Car" or rec.Mode == "Boat"
	if fresh then
		rec.SatAt = t
		rec.HelloAt = nil
		rec.HelloTimedOut = false
		rec.ClientProven = false
		rec.PushSince = nil
		rec.PushPos = nil
		rec.OwnerBad = 0
		rec.BlockPush = 0
		rec.BlockLogged = false
		rec.TripAt = nil
		rec.TripPos = nil
		rec.TripSign, rec.TripLook = nil, nil
		rec.InT, rec.InS, rec.InL, rec.InAt = 0, 0, 0, nil
		rec.HandOffPos = rec.Chassis.Position
		rec.HandOffAt = t
		rec.NextOwnerProbe = t + 0.5
		rec.NextDiagAt = t
		rec.NextDiagLogAt = t
		rec.ClientBroken = ground and W.Enabled and (brokenTrips[player.UserId] or 0) >= W.SessionTrips
		rec.BrokenReason = if rec.ClientBroken then "session" else nil
		rec.ServerProven = rec.ClientBroken
		rec.Model:SetAttribute("WE_DriveFail", rec.BrokenReason)
		rec.Pins, rec.PinList = countPins(rec)
	end
	resetValid(rec, t)
	rec.NextSampleAt = t + 1 / Valid.SampleHz
	stopDrive(rec)
	if ground and (rec.ClientBroken or (rec.HelloTimedOut and rec.HelloAt == nil)) then
		startGroundDrive(rec, t)
		return
	end
	if not setOwner(rec, player) then
		warn("[VehicleService] SetNetworkOwner(driver) refused", rec.Def.Id)
		if ground then
			rec.ClientBroken = true
			rec.BrokenReason = "owner-refused"
			rec.TripAt = t
			rec.TripPos = rec.Chassis.Position
			rec.TripSign = 0 -- no push involved: any server-driven motion proves the client link was the fault
			rec.ServerProven = false
			rec.Model:SetAttribute("WE_DriveFail", "owner-refused")
			startGroundDrive(rec, t)
			return
		end
	end
	setAuthority(rec, "Client")
end

--[[ F5e: a character that left a (possibly server-owned) vehicle assembly goes back to its player explicitly, on the
	next deferred tick (after the SeatWeld is gone). Harmless when the player already owns it. ]]
local function handBackCharacter(player: Player, chassis: BasePart)
	task.defer(function()
		local ch = player.Character
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") and not hrp.Anchored and hrp.AssemblyRootPart ~= chassis.AssemblyRootPart then
			pcall(function()
				hrp:SetNetworkOwner(player)
			end)
		end
	end)
end

-- Nobody in the driver seat: the server owns the physics and runs the idle law. F5e.
local function releaseToServer(rec: VehicleRec, t: number)
	local leaving = if rec.DriverUserId ~= 0 then Players:GetPlayerByUserId(rec.DriverUserId) else nil
	stopDrive(rec)
	rec.CorrectUntil = nil
	rec.CorrectPos = nil
	rec.DriverUserId = 0
	rec.Model:SetAttribute("WE_DriverUserId", 0)
	rec.SatAt = nil
	rec.HelloAt = nil
	rec.HelloTimedOut = false
	rec.InT, rec.InS, rec.InL, rec.InAt = 0, 0, 0, nil
	setAuthority(rec, "Server")
	setOwner(rec, nil)
	rec.Idle = {}
	rec.NextIdleAt = t
	rec.LastSeatedAt = t
	if rec.Model:GetAttribute("WE_Diag") ~= nil then
		rec.Model:SetAttribute("WE_Diag", nil)
	end
	if leaving then
		handBackCharacter(leaving, rec.Chassis)
	end
end

local function ejectDriver(rec: VehicleRec)
	ejectSeat(rec.Seat)
end

local function forgetVehicle(model: Model)
	local rec = vehicles[model]
	vehicles[model] = nil
	if rec then
		for _, c in ipairs(rec.Conns) do
			c:Disconnect()
		end
		table.clear(rec.Conns)
		rec.Fallback = nil
		-- the vehicle goes away with riders in it (recall, SPAWN of another, despawn): their characters were part of
		-- the vehicle assembly, which the server may own; give each character back to its player
		local seats: { BasePart } = { rec.Seat }
		for _, ps in ipairs(rec.Passengers) do
			table.insert(seats, ps)
		end
		for _, seat in ipairs(seats) do
			local rider = playerOfHumanoid((seat :: any).Occupant)
			if rider then
				handBackCharacter(rider, rec.Chassis)
			end
		end
	end
end

local function destroyActive(userId: number)
	local model = activeVehicles[userId]
	activeVehicles[userId] = nil
	if model then
		forgetVehicle(model)
		-- Ensure kit parts / welds / seats are fully cleaned
		pcall(function()
			model:Destroy()
		end)
	end
end

local function destroyVehicle(rec: VehicleRec, message: string?)
	local uid = rec.OwnerUserId
	if activeVehicles[uid] == rec.Model then
		destroyActive(uid)
	else
		forgetVehicle(rec.Model)
		pcall(function()
			rec.Model:Destroy()
		end)
	end
	local owner = rec.Owner
	if owner.Parent then
		if message then
			notify(owner, message, "Warn", 4)
		end
		pcall(pushState, owner)
	end
end

local function recallVehicle(rec: VehicleRec, reason: string)
	if AntiExploitService and AntiExploitService.Strike then
		pcall(AntiExploitService.Strike, rec.Owner, "vehicle_" .. reason)
	end
	warn("[VehicleService] recalled", rec.Owner.Name, rec.Def.Id, reason)
	destroyVehicle(rec, "Vehicle recalled")
end

-- Violation: take the physics back and put the vehicle at its last valid position.
local function beginCorrection(rec: VehicleRec, t: number)
	stopDrive(rec)
	setAuthority(rec, "Server")
	local released = setOwner(rec, nil)
	local back = rec.LastValid
	pcall(function()
		rec.Model:PivotTo(back.CFrame)
	end)
	zeroVelocity(rec.Chassis)
	rec.CorrectUntil = t + Valid.CorrectionHold
	rec.CorrectPos = back.Pos
	-- a plane glides at the idle minimum during the hold (bounded, so correctionStep can tell it from a client
	-- that kept the physics)
	rec.Idle = { ReturnPos = back.Pos, GlideSpeed = if rec.Mode == "Plane" then PlaneCfg.IdleGlideMinSpeed else nil }
	rec.NextIdleAt = t
	rec.NextSampleAt = t + 1 / Valid.SampleHz
	resetValid(rec, t)
	if not released then
		ejectDriver(rec) -- ownership cannot be taken back with the driver seated
	end
	if t - rec.LastStabilisedAt >= Drive.StabilisedNoticeSeconds then
		rec.LastStabilisedAt = t
		notify(rec.Owner, "Vehicle stabilised", "Warn", 3)
	end
end

local function onViolation(rec: VehicleRec, reason: string, soft: boolean, t: number)
	if not soft then
		local kept: { number } = {}
		for _, at in ipairs(rec.Violations) do
			if t - at <= Valid.RecallWindow then
				table.insert(kept, at)
			end
		end
		table.insert(kept, t)
		rec.Violations = kept
		if #kept >= Valid.RecallViolations then
			recallVehicle(rec, reason)
			return
		end
	end
	beginCorrection(rec, t)
end

--[[ One 5 Hz check. (ok, reason?, soft). Measures teleports from the last VALID sample (a lag burst
	passes); LastValid only advances when fresh data arrived (the position changed) or the vehicle is
	really at rest, so a frozen replication stream does not shrink the allowance. ]]
local function validateSample(rec: VehicleRec, s: ValidSample): (boolean, string?, boolean)
	local mode = rec.Mode
	local air = mode == "Heli" or mode == "Plane"
	local cap = rec.Params.MaxSpeed * Valid.SpeedTolerance + (if air then Valid.AirSpeedSlack else Valid.SpeedSlack)
	local pos, vel = s.Pos, s.Vel
	local speed = if air then vel.Magnitude else flat(vel).Magnitude
	local prevT = rec.LastSampleT or s.T
	local prevPos = rec.LastSamplePos or pos
	local dtS = math.max(0, s.T - prevT)
	rec.LastSampleT = s.T
	rec.LastSamplePos = pos
	if math.abs(pos.X) > Valid.WorldHalfExtent or math.abs(pos.Z) > Valid.WorldHalfExtent then
		return false, "bounds", false
	end
	local lv = rec.LastValid
	local dtV = math.clamp(s.T - lv.T, 0, Valid.MaxLagWindow)
	local allow = cap * dtV + Valid.TeleportSlack
	local dist = (pos - lv.Pos).Magnitude
	if dist > allow then
		return false, "teleport", dist <= allow + Valid.HardTeleport
	end
	-- Per-sample slack adds up: 20 studs every 0.2 s let a client that reports a sub-cap velocity move at
	-- cap + 100 studs/s (a 55 car at 180). Over a ~1 s window the slack is granted once.
	local win = rec.Window
	if win then
		local wdist = (pos - win.Pos).Magnitude
		local wallow = cap * math.max(0, s.T - win.T) + Valid.TeleportSlack
		if wdist > wallow then
			return false, "teleport", wdist <= wallow + Valid.HardTeleport
		end
	end
	if air then
		if pos.Y > rec.MaxAltitude + Valid.AirAltitudeSlack then
			return false, "altitude", false
		end
	else
		if pos.Y > Valid.GroundMaxY then
			return false, "altitude", false
		end
		if mode == "Car" and vel.Y > Valid.MaxGroundUpSpeed then
			return false, "fling", false
		end
	end
	if speed > cap then
		rec.SpeedFlags += 1
		if rec.SpeedFlags >= Valid.SpeedSamplesToFlag then
			rec.SpeedFlags = 0
			return false, "speed", false
		end
	else
		rec.SpeedFlags = 0
	end
	local overWater = true
	if mode == "Boat" then
		if waterSurfaceAt(recWaterParts(rec), pos, Valid.OffWaterMargin, nil) == nil then
			overWater = false
			rec.OffWaterFor += dtS
			if rec.OffWaterFor > Valid.OffWaterGrace then
				rec.OffWaterFor = 0
				return false, "offwater", true
			end
		else
			rec.OffWaterFor = 0
		end
		local wy = s.WaterY
		if wy ~= nil and pos.Y > wy + Valid.BoatMaxAboveWater then
			return false, "altitude", false
		end
	end
	local fresh = (pos - prevPos).Magnitude > 0.01 or vel.Magnitude < 0.5
	if overWater and fresh then
		rec.LastValid = { CFrame = s.CFrame or CFrame.new(pos), Pos = pos, T = s.T }
		if win == nil or s.T - win.T >= Valid.WindowSeconds then
			rec.Window = { Pos = pos, T = s.T }
		end
	end
	return true, nil, false
end

local function sampleAndCheck(rec: VehicleRec, t: number)
	local cf = rec.Chassis.CFrame
	local pos = cf.Position
	local sample: ValidSample = {
		Pos = pos,
		Vel = partVelocity(rec.Chassis),
		T = t,
		WaterY = if rec.Mode == "Boat" then waterSurfaceAt(recWaterParts(rec), pos, 0, nil) else nil,
		CFrame = cf,
	}
	local ok, reason, soft = validateSample(rec, sample)
	if not ok and reason then
		onViolation(rec, reason, soft, t)
	end
end

-- How fast the idle law itself may carry the vehicle during a correction hold (studs/s). Without this an
-- airborne plane (idle glide ~31 studs/s) drifted past TeleportSlack in ~0.7 s and its pilot was ejected mid-air.
local function idleDriftSpeed(mode: string): number
	if mode == "Plane" then
		return PlaneCfg.IdleGlideMinSpeed + PlaneCfg.IdleGlideSink
	elseif mode == "Heli" then
		return HeliCfg.IdleSink
	elseif mode == "Boat" then
		return BoatCfg.AgroundSpeed + BoatCfg.IdleMaxVy
	end
	return 0
end

local function correctionStep(rec: VehicleRec, t: number)
	local until_ = rec.CorrectUntil
	if until_ == nil then
		return
	end
	if t >= rec.NextSampleAt then
		rec.NextSampleAt = t + 1 / Valid.SampleHz
		local cp = rec.CorrectPos
		local held = math.max(0, t - (until_ - Valid.CorrectionHold))
		if cp and (rec.Chassis.Position - cp).Magnitude > Valid.TeleportSlack + held * idleDriftSpeed(rec.Mode) then
			-- still moving away: the client kept the physics → eject the driver and put it back
			ejectDriver(rec)
			local back = rec.LastValid
			pcall(function()
				rec.Model:PivotTo(back.CFrame)
			end)
			zeroVelocity(rec.Chassis)
		end
	end
	if t >= until_ then
		rec.CorrectUntil = nil
		rec.CorrectPos = nil
		local driver = seatedDriver(rec)
		if driver and driver == rec.Owner then
			handOff(rec, driver, t, false)
		end
	end
end

-- F5g: the client-simulation link is broken for this sit → server drive (Car/Boat) or a notice (aircraft).
local function trip(rec: VehicleRec, reason: string, t: number, extra: any?)
	if rec.ClientBroken then
		return
	end
	rec.ClientBroken = true
	rec.BrokenReason = reason
	rec.TripAt = t
	rec.TripPos = rec.Chassis.Position
	local th = serverInput(rec, t).Throttle
	rec.TripSign = if th > W.PushThrottle then 1 elseif th < -W.PushThrottle then -1 else 0
	rec.TripLook = rec.Chassis.CFrame.LookVector
	rec.ServerProven = false
	rec.BlockPush = 0
	rec.BlockLogged = false
	rec.Model:SetAttribute("WE_DriveFail", reason)
	rec.Pins, rec.PinList = countPins(rec)
	warn(diagLine(rec, t, "NO-DRIVE " .. reason, extra)) -- every player, one line per trip
	if rec.Mode == "Car" or rec.Mode == "Boat" then
		startGroundDrive(rec, t)
	else
		setOwner(rec, rec.Owner) -- aircraft: no server law (spec §5); re-assert and tell the pilot once
		if not rec.FlightNoticeSent then
			rec.FlightNoticeSent = true
			notify(rec.Owner, "Flight controls not responding — jump out and sit again", "Warn", 6)
		end
	end
end

-- 5 Hz next to sampleAndCheck: prove the client-simulated vehicle moves; after a trip, prove server drive does.
local function watchdogStep(rec: VehicleRec, t: number)
	if not W.Enabled or rec.DriverUserId == 0 then
		return
	end
	local air = rec.Mode == "Heli" or rec.Mode == "Plane"
	local pos = rec.Chassis.Position
	local function moved(from: Vector3?): number
		if from == nil then
			return 0
		end
		local d = pos - from
		return if air then d.Magnitude else Vector3.new(d.X, 0, d.Z).Magnitude
	end
	local push = pushing(rec, serverInput(rec, t))
	local last = rec.LastWatchAt
	local since = if last ~= nil then math.clamp(t - last, 0, 0.5) else 0 -- real time between 5 Hz calls
	rec.LastWatchAt = t
	if rec.Authority == "Client" and not rec.ClientProven and not rec.ClientBroken then
		if moved(rec.HandOffPos) > W.ProvenStuds then
			rec.ClientProven = true
			rec.PushSince = nil
			return
		end
		if t - (rec.HandOffAt or t) <= W.OwnerProbeSeconds and t >= rec.NextOwnerProbe then
			rec.NextOwnerProbe = t + 1 / W.OwnerProbeHz
			local st, detail = ownerState(rec, rec.Owner)
			if st == "drv" then
				rec.OwnerBad = 0
			elseif st ~= "unk" then
				rec.OwnerBad += 1
				if rec.OwnerBad == 2 then
					setOwner(rec, rec.Owner) -- one re-assert
				elseif rec.OwnerBad >= 3 then
					trip(rec, "owner:" .. st .. "(" .. detail .. ")", t)
					return
				end
			end
		end
		if push then
			local pushSince = rec.PushSince
			if pushSince == nil then
				rec.PushSince, rec.PushPos = t, pos
			elseif t - pushSince >= W.Seconds and moved(rec.PushPos) < W.MinMoveStuds then
				trip(rec, "nomove", t)
			end
		else
			rec.PushSince = nil
		end
	elseif rec.ClientBroken and rec.Authority == "Fallback" and not rec.ServerProven then
		if moved(rec.TripPos) > W.ProvenStuds then
			rec.ServerProven = true
			-- the client link was the fault only if server drive moved it the way the driver pushed at the trip: a car
			-- parked nose-to-wall trips, then reverses away under server drive; that proves nothing (spec: a blocked
			-- car must not count toward SessionTrips)
			local sign, look, from = rec.TripSign or 0, rec.TripLook, rec.TripPos
			local along = if look and from then (pos - from):Dot(look) * sign else 0
			if sign == 0 or along > W.MinMoveStuds then
				brokenTrips[rec.OwnerUserId] = (brokenTrips[rec.OwnerUserId] or 0) + 1 -- remember it for this session
				print(diagLine(rec, t, "SERVER-DRIVE ok (" .. tostring(rec.BrokenReason) .. ")", nil))
			else
				print(diagLine(rec, t, "SERVER-DRIVE moved away from the trip spot (not counted)", nil))
			end
		elseif push then
			rec.BlockPush += since
			if rec.BlockPush >= W.BlockedSeconds and not rec.BlockLogged then
				rec.BlockLogged = true
				warn(diagLine(rec, t, "BLOCKED (server drive cannot move it either: pinned or wedged)", nil))
			end
		end
	end
end

-- F5j: debug users (Drive.Debug) get WE_Diag at 2 Hz and a server line every ServerLogSeconds while pushing.
local function debugStep(rec: VehicleRec, t: number)
	if rec.DriverUserId == 0 or not isDebugUser(rec.OwnerUserId) then
		return
	end
	if t >= rec.NextDiagAt then
		rec.NextDiagAt = t + 0.5
		rec.Model:SetAttribute("WE_Diag", diagCompact(rec))
	end
	if t >= rec.NextDiagLogAt and pushing(rec, serverInput(rec, t)) then
		rec.NextDiagLogAt = t + DBG.ServerLogSeconds
		print(diagLine(rec, t, "DIAG", nil))
	end
end

local function tickRecord(rec: VehicleRec, t: number, dt: number)
	local model, chassis = rec.Model, rec.Chassis
	if model.Parent == nil or chassis.Parent == nil then
		if activeVehicles[rec.OwnerUserId] == model then
			activeVehicles[rec.OwnerUserId] = nil
		end
		forgetVehicle(model)
		return
	end
	local pos = chassis.Position
	local lim = Valid.WorldHalfExtent + Drive.LostMargin
	if pos.Y < Drive.LostBelowY or math.abs(pos.X) > lim or math.abs(pos.Z) > lim then
		destroyVehicle(rec, "Vehicle lost")
		return
	end
	if anyOccupied(rec) then
		rec.LastSeatedAt = t
	elseif t - rec.LastSeatedAt >= Drive.IdleDespawnSeconds then
		destroyVehicle(rec, nil)
		return
	end
	-- no Hello from the driver's client in time
	local satAt = rec.SatAt
	if rec.DriverUserId ~= 0 and rec.HelloAt == nil and not rec.HelloTimedOut and satAt ~= nil and t - satAt >= Drive.HelloTimeoutSeconds then
		rec.HelloTimedOut = true
		if rec.Mode == "Car" or rec.Mode == "Boat" then
			if rec.Authority == "Client" then
				startGroundDrive(rec, t)
			end
		elseif not rec.FlightNoticeSent then
			rec.FlightNoticeSent = true
			notify(rec.Owner, "Flight controls failed to load — rejoin", "Warn", 6)
		end
	end
	local auth = rec.Authority
	if auth == "Fallback" then
		fallbackStep(rec, t, dt)
	end
	if auth == "Client" or auth == "Fallback" then
		if t >= rec.NextSampleAt then
			rec.NextSampleAt = t + 1 / Valid.SampleHz
			sampleAndCheck(rec, t)
			if vehicles[model] == rec then -- sampleAndCheck can recall (destroy) it
				watchdogStep(rec, t)
			end
		end
	else
		if rec.CorrectUntil ~= nil then
			correctionStep(rec, t)
		end
		if rec.Authority == "Server" and vehicles[model] == rec and t >= rec.NextIdleAt then
			local last = rec.LastIdleAt
			local idt = if last then math.min(t - last, 0.25) else 0
			rec.LastIdleAt = t
			rec.NextIdleAt = t + 1 / Drive.IdleHz
			idleStep(rec, t, idt)
		end
	end
	if vehicles[model] == rec then
		debugStep(rec, t)
	end
end

local function tickAll(dt: number)
	local t = now()
	local list: { VehicleRec } = {}
	for _, rec in pairs(vehicles) do
		table.insert(list, rec)
	end
	for _, rec in ipairs(list) do
		if vehicles[rec.Model] == rec then
			local ok, err = pcall(tickRecord :: any, rec, t, dt)
			if not ok then
				warn("[VehicleService] tick failed", rec.Def.Id, err)
			end
		end
	end
end

-- First sit extras (once per session). Mobile P1-8: no keyboard drive-tip toast any more (key names on phones);
-- the ArmedJeep keeps its cosmetic muzzle-flash cue.
local function onFirstSit(rec: VehicleRec, player: Player)
	local model = rec.Model
	if rec.Mode == "Car" and not sitCueShown[player.UserId] then
		sitCueShown[player.UserId] = true
		if model:GetAttribute("VehicleId") == "ArmedJeep" then
			-- Brief muzzle flash cue (cosmetic; no fire logic)
			local barrel = model:FindFirstChild("Barrel")
			if barrel and barrel:IsA("BasePart") then
				local flash = Instance.new("PointLight")
				flash.Name = "WE_MuzzleFlash"
				flash.Color = Color3.fromRGB(255, 200, 120)
				flash.Brightness = 4
				flash.Range = 14
				flash.Shadows = false
				flash.Parent = barrel
				task.delay(0.18, function()
					if flash.Parent then
						flash:Destroy()
					end
				end)
			end
		end
	end
	-- v36: one-shot SpeedBoost soft offer after the first vehicle sit
	if sitOfferShown[player.UserId] then
		return
	end
	sitOfferShown[player.UserId] = true
	if MonetizationService and MonetizationService.TrySoftOfferSpeedBoost then
		task.defer(function()
			MonetizationService.TrySoftOfferSpeedBoost(player, "vehicle_sit")
		end)
	end
end

local function onDriverChanged(model: Model, occupant: Instance?)
	local rec = vehicles[model]
	if not rec then
		return
	end
	local t = now()
	if occupant == nil then
		if rec.DriverUserId ~= 0 or rec.Authority ~= "Server" then
			releaseToServer(rec, t)
		end
		return
	end
	local player = playerOfHumanoid(occupant)
	if player == nil or player ~= rec.Owner then
		ejectSeat(rec.Seat) -- only the owner can drive; passenger seats take players only (F8)
		return
	end
	rec.EverSeated = true
	rec.LastSeatedAt = t
	refreshMoverLimits(rec) -- AssemblyMass now includes the driver
	handOff(rec, player, t, true)
	onFirstSit(rec, player)
end

-- a stream axis: finite number clamped to [-1, 1], anything else 0
local function axis(v: any): number
	if typeof(v) ~= "number" or v ~= v then
		return 0
	end
	return math.clamp(v, -1, 1)
end

--[[ VehicleDriveInput (F5f). Kinds: Hello {P}, Bye, In {T, S, L} (10 Hz while any axis is non-zero), Stuck (once per
	sit), Exit (touch jump / EXIT pill). Only the seated owner-driver of their own active vehicle is heard; the
	messages carry clamped inputs only, never positions or velocities. ]]
local function handleDriveInput(player: Player, msg: any)
	if typeof(msg) ~= "table" then
		if AntiExploitService and AntiExploitService.Strike then
			pcall(AntiExploitService.Strike, player, "vehicle_input_payload")
		end
		return
	end
	local kind = msg.K
	local key: string, rate: number, burst: number
	if kind == "In" then
		key, rate, burst = "vehicle_drive_stream", W.StreamRate, W.StreamBurst
	elseif kind == "Hello" or kind == "Bye" or kind == "Stuck" then
		key, rate, burst = "vehicle_drive_input", 4, 2
	elseif kind == "Exit" then
		key, rate, burst = "vehicle_exit", 4, 2
	else
		return
	end
	if RateLimitService and not RateLimitService.Allow(player, key, rate, burst) then
		return
	end
	if not RemoteGuard.IsIdString(msg.V, 48) then
		return
	end
	local model = activeVehicles[player.UserId]
	local rec = if model then vehicles[model] else nil
	if rec == nil or rec.Model:GetAttribute("VehicleId") ~= msg.V then
		return
	end
	if seatedDriver(rec) ~= player or rec.DriverUserId ~= player.UserId then
		return
	end
	local t = now()
	if kind == "In" then
		rec.InT, rec.InS, rec.InL = axis(msg.T), axis(msg.S), axis(msg.L)
		rec.InAt = t
		return
	elseif kind == "Exit" then
		ejectSeat(rec.Seat) -- works whoever simulates the seat (a client jump may not leave a server-owned seat)
		return
	elseif kind == "Stuck" then
		if rec.Authority == "Client" and not rec.ClientProven then
			local air = rec.Mode == "Heli" or rec.Mode == "Plane"
			-- aircraft: only when the server also sees input that must move the craft (a landed heli ignores the stick)
			if not air or pushing(rec, serverInput(rec, t)) then
				trip(rec, "client-stuck", t, msg)
			end
		end
		return
	elseif kind == "Hello" then
		if msg.P ~= nil and msg.P ~= Drive.ProtocolVersion then
			return -- an old client: it refuses to drive; Car/Boat fall back after the timeout
		end
		rec.HelloAt = t
		if rec.Authority == "Fallback" and not rec.ClientBroken then
			stopDrive(rec)
			if setOwner(rec, player) then
				setAuthority(rec, "Client")
			else
				startGroundDrive(rec, t)
			end
		end
	elseif rec.Mode == "Car" or rec.Mode == "Boat" then
		-- Bye while still seated: the client stopped driving → the server takes over
		if rec.Authority == "Client" then
			rec.HelloAt = nil
			rec.HelloTimedOut = true
			startGroundDrive(rec, t)
		end
	end
end

local function researchMult(player: Player, statId: string, maxBonus: number): number
	local rs = ResearchService
	if rs == nil or typeof(rs.GetBonus) ~= "function" then
		return 1
	end
	local ok, v = pcall(rs.GetBonus, player, statId)
	local n = if ok then tonumber(v) else nil
	if n == nil or n ~= n then
		return 1
	end
	return math.clamp(n, 1, maxBonus)
end

local function registerVehicle(player: Player, model: Model, def: VehicleDef, mode: string, spawn: SpawnChoice): VehicleRec?
	local chassis = model.PrimaryPart
	local seat = model:FindFirstChild("DriverSeat")
	if not (chassis and seat and seat:IsA("VehicleSeat")) then
		return nil
	end
	local lv = chassis:FindFirstChild("WE_DriveLV")
	local ao = chassis:FindFirstChild("WE_DriveAO")
	if not (lv and lv:IsA("LinearVelocity") and ao and ao:IsA("AlignOrientation")) then
		return nil
	end
	local passengers: { Seat } = {}
	for _, c in ipairs(model:GetChildren()) do
		if c:IsA("Seat") then
			table.insert(passengers, c)
		end
	end
	local t = now()
	local baseMax = tonumber(model:GetAttribute("WE_BaseMaxSpeed")) or def.Speed
	local cf = chassis.CFrame
	local rec: VehicleRec = {
		Model = model,
		Owner = player,
		OwnerUserId = player.UserId,
		Def = def,
		Mode = mode,
		Chassis = chassis,
		Seat = seat,
		Passengers = passengers,
		LV = lv,
		AO = ao,
		Params = {
			MaxSpeed = tonumber(model:GetAttribute("WE_MaxSpeed")) or baseMax,
			Accel = tonumber(model:GetAttribute("WE_Accel")) or 20,
			TurnRate = tonumber(model:GetAttribute("WE_TurnRate")) or 1,
			Tracked = model:GetAttribute("WE_Tracked") == true,
			RideOffset = tonumber(model:GetAttribute("WE_RideOffset")) or 0,
			HalfLength = tonumber(model:GetAttribute("WE_HalfLength")) or 5,
		},
		BaseMaxSpeed = baseMax,
		MaxAltitude = tonumber(model:GetAttribute("WE_MaxAltitude")) or Valid.GroundMaxY,
		Force = lv.MaxAxesForce.X,
		Authority = "Server",
		DriverUserId = 0,
		SatAt = nil,
		HelloAt = nil,
		HelloTimedOut = false,
		FlightNoticeSent = false,
		EverSeated = false,
		LastSeatedAt = t,
		LastValid = { CFrame = cf, Pos = cf.Position, T = t },
		Window = { Pos = cf.Position, T = t },
		LastSampleT = t,
		LastSamplePos = cf.Position,
		NextSampleAt = t,
		NextIdleAt = t,
		LastIdleAt = nil,
		SpeedFlags = 0,
		OffWaterFor = 0,
		Violations = {},
		CorrectUntil = nil,
		CorrectPos = nil,
		Idle = {},
		Fallback = nil,
		LastStabilisedAt = -math.huge,
		Conns = {},
		OutVel = nil,
		OutHold = nil,
		OutRot = nil,
		OwnParts = ownPartsOf(model, chassis),
		InT = 0,
		InS = 0,
		InL = 0,
		InAt = nil,
		ClientProven = false,
		ClientBroken = false,
		ServerProven = false,
		BrokenReason = nil,
		HandOffPos = nil,
		HandOffAt = nil,
		PushSince = nil,
		PushPos = nil,
		OwnerBad = 0,
		NextOwnerProbe = t,
		TripAt = nil,
		TripPos = nil,
		BlockPush = 0,
		BlockLogged = false,
		LastWatchAt = nil,
		Pins = 0,
		PinList = "",
		NextDiagAt = t,
		NextDiagLogAt = t,
	}
	vehicles[model] = rec
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
		end
	end
	setOwner(rec, nil)
	refreshMoverLimits(rec)
	if spawn.State == "Airborne" and spawn.Speed > 0 then
		-- air start: moving at 1.3 x takeoff speed, held by the idle glide until the pilot sits
		local look = flat(cf.LookVector)
		look = if look.Magnitude > 0.05 then look.Unit else Vector3.new(0, 0, -1)
		pcall(function()
			chassis.AssemblyLinearVelocity = look * spawn.Speed
		end)
		rec.Idle.GlideSpeed = spawn.Speed
		lv.MaxAxesForce = Vector3.new(rec.Force, rec.Force, rec.Force)
		lv.VectorVelocity = look * spawn.Speed + Vector3.new(0, -PlaneCfg.IdleGlideSink, 0)
	end
	idleStep(rec, t, 0)
	table.insert(
		rec.Conns,
		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			onDriverChanged(model, seat.Occupant)
		end)
	)
	-- F8: passenger seats take players only. NPC squad units / guards never ride (their BodyGyro would steer the car).
	-- A player leaving a passenger seat gets their character handed back (the car may be server-owned).
	for _, ps in ipairs(passengers) do
		local prevRider: Player? = nil
		table.insert(
			rec.Conns,
			ps:GetPropertyChangedSignal("Occupant"):Connect(function()
				local occ = ps.Occupant
				local rider = playerOfHumanoid(occ)
				if prevRider and prevRider ~= rider then
					handBackCharacter(prevRider, chassis)
				end
				prevRider = rider
				if occ ~= nil and rider == nil then
					task.defer(function()
						if ps.Occupant == occ then
							ejectSeat(ps)
						end
					end)
				end
			end)
		)
	end
	return rec
end

function VehicleService.Owns(player: Player, vehicleId: string): boolean
	local profile = DataService.GetProfile(player)
	return profile ~= nil and profile.Vehicles[vehicleId] == true
end

function VehicleService.GrantVehicle(player: Player, vehicleId: string)
	local profile = DataService.GetProfile(player)
	if not profile or not getDef(vehicleId) then
		return
	end
	profile.Vehicles[vehicleId] = true
	DataService.MarkDirty(player)
	pushState(player)
end

function VehicleService.Purchase(player: Player, vehicleId: any): (boolean, string?)
	if not RemoteGuard.IsIdString(vehicleId, 48) then
		return false, "InvalidId"
	end
	local def = getDef(vehicleId)
	if not def then
		return false, "UnknownVehicle"
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end
	if profile.Vehicles[vehicleId] then
		return false, "AlreadyOwned"
	end
	if profile.Level < def.UnlockLevel then
		return false, "LevelTooLow"
	end
	local okStruct, structErr = meetsStructureReq(profile, def)
	if not okStruct then
		return false, structErr
	end
	local okPres, presErr = meetsPrestigeReq(profile, def)
	if not okPres then
		return false, presErr
	end
	local cost = def.CostCash or 0
	if cost > 0 then
		local ok, err = EconomyService.SpendCash(player, cost, "vehicle_" .. vehicleId)
		if not ok then
			return false, err or "SpendFailed"
		end
	end
	profile.Vehicles[vehicleId] = true
	DataService.MarkDirty(player)
	if AnalyticsService then
		AnalyticsService.Log(AnalyticsConfig.Events.VEHICLE_PURCHASED, player.UserId, {
			vehicle = vehicleId,
			cost = cost,
		})
	end
	if NotificationService then
		NotificationService.Notify(player, "Acquired " .. def.DisplayName, "Reward")
	end
	pushState(player)
	return true, nil
end

function VehicleService.Despawn(player: Player)
	destroyActive(player.UserId)
	pushState(player)
end

function VehicleService.RequestSpawn(player: Player, vehicleId: any): (boolean, string?)
	if not RemoteGuard.IsIdString(vehicleId, 48) then
		return false, "InvalidId"
	end
	local def = getDef(vehicleId)
	if not def then
		return false, "UnknownVehicle"
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end
	if not profile.Vehicles[vehicleId] then
		return false, "NotOwned"
	end
	if profile.Level < def.UnlockLevel then
		return false, "LevelTooLow"
	end
	local okStruct, structErr = meetsStructureReq(profile, def)
	if not okStruct then
		return false, structErr
	end
	local okPres, presErr = meetsPrestigeReq(profile, def)
	if not okPres then
		return false, presErr
	end
	if cooldownLeft(player.UserId, player) > 0 then
		return false, "Cooldown"
	end
	if damageLockLeft(player.UserId) > 0 then
		return false, "InCombat" -- P1-9: SPAWN is not an escape from a fight
	end
	-- P1-9: inside your own plot the garage flow seats you on your own pad / helipad / runway / basin; anywhere
	-- else only a vehicle that appears next to you (in front of you) seats you. Never a cross-map teleport.
	local sitRadius = if playerAtHome(player, profile) then SpawnCfg.AutoSitHomeRadius else SpawnCfg.AutoSitRadius

	-- 1) build unparented at the origin (movers + drive attributes included)
	local bonus = researchMult(player, "VehicleSpeed", Drive.MaxResearchSpeedBonus)
	local armorMult = researchMult(player, "VehicleArmor", Drive.MaxResearchArmorBonus)
	local buildOk, modelOrErr = pcall(function()
		return buildVehicleModel(def, CFrame.identity, player.UserId, bonus, armorMult)
	end)
	if not buildOk or typeof(modelOrErr) ~= "Instance" then
		warn("[VehicleService] buildVehicleModel failed", vehicleId, modelOrErr)
		return false, "SpawnBuildFailed"
	end
	local model = modelOrErr :: Model
	local function discard()
		pcall(function()
			model:Destroy()
		end)
	end
	if not model.PrimaryPart or not model:FindFirstChild("DriverSeat") then
		warn("[VehicleService] spawn kit incomplete", vehicleId, "PrimaryPart/DriverSeat missing")
		discard()
		return false, "SpawnKitIncomplete"
	end
	local mode = driveModeFor(def)

	-- 2) footprint → 3) choose the spawn (the player's current vehicle is replaced, so it is not "occupied")
	local fp = footprintOf(model)
	local attrs = model:GetAttributes()
	local ctxOk, chosen, chooseErr = pcall(function(): (SpawnChoice?, string?)
		return chooseSpawn(buildSpawnCtx(player, profile, mode, fp, attrs, activeVehicles[player.UserId]))
	end)
	if not ctxOk then
		warn("[VehicleService] spawn choice failed", vehicleId, chosen)
		discard()
		return false, "SpawnBuildFailed"
	end
	local spawn = chosen :: SpawnChoice?
	if spawn == nil then
		discard()
		return false, chooseErr or "NoWater"
	end

	-- One active vehicle per player: the old one goes now
	destroyActive(player.UserId)

	-- 4) PivotTo → parent → hand over
	model:PivotTo(spawn.CFrame)
	model:SetAttribute("WE_SpawnState", spawn.State)
	if spawn.Speed > 0 then
		model:SetAttribute("WE_SpawnSpeed", spawn.Speed)
	end
	model.Parent = ensureFolder()
	if not model.Parent then
		warn("[VehicleService] spawn model unparented", vehicleId)
		discard()
		return false, "SpawnOrphaned"
	end
	local rec = registerVehicle(player, model, def, mode, spawn)
	if not rec then
		warn("[VehicleService] spawn kit incomplete (movers)", vehicleId)
		discard()
		return false, "SpawnKitIncomplete"
	end
	activeVehicles[player.UserId] = model
	lastSpawnAt[player.UserId] = now()

	-- Driveability: Drive prompt + auto-sit the DriverSeat so garage SPAWN is immediately usable
	local autoSeat = false
	do
		local seat = rec.Seat
		seat.Disabled = false
		seat.Anchored = false
		seat.CanTouch = true
		-- Drive prompt if auto-sit misses (mobile / late character); clients hide it on vehicles they don't own
		if not seat:FindFirstChild("WE_DrivePrompt") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "WE_DrivePrompt"
			prompt.ActionText = "Drive"
			prompt.ObjectText = def.DisplayName or "Vehicle"
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 14
			prompt.RequiresLineOfSight = false
			prompt.Parent = seat
			table.insert(
				rec.Conns,
				prompt.Triggered:Connect(function(who: Player)
					if who ~= player then
						return
					end
					local ch = who.Character
					local hum = ch and ch:FindFirstChildOfClass("Humanoid")
					if hum and seat.Occupant == nil then
						pcall(function()
							seat:Sit(hum)
						end)
					end
				end)
			)
		end
		-- "close" = the player's root part within sitRadius of the vehicle's footprint (centre distance - radius)
		local reach = footRadius(fp)
		local function seatNear(): boolean
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			return hrp ~= nil and hrp:IsA("BasePart") and (hrp.Position - rec.Chassis.Position).Magnitude - reach <= sitRadius
		end
		autoSeat = seatNear()
		local function trySit()
			if rec.EverSeated or not player.Parent or not model.Parent or not seat.Parent then
				return
			end
			local character = player.Character
			local hum = character and character:FindFirstChildOfClass("Humanoid")
			local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hum and hrp and seat.Occupant == nil and seatNear() then
				-- Place character on seat so Sit always has a valid near-seat humanoid
				hrp.CFrame = seat.CFrame * CFrame.new(0, 2.5, 0)
				pcall(function()
					seat:Sit(hum)
				end)
			end
		end
		task.defer(trySit)
		task.delay(0.2, trySit)
		task.delay(0.5, trySit)
		task.delay(1.0, trySit)
		task.delay(2.0, trySit)
	end

	if profile.Stats then
		profile.Stats.VehiclesSpawned = (profile.Stats.VehiclesSpawned or 0) + 1
	end
	if MissionService and MissionService.TrackProgress then
		MissionService.TrackProgress(player, "SpawnVehicle", 1)
	end
	if TutorialService and TutorialService.Notify then
		TutorialService.Notify(player, "SpawnVehicle", vehicleId)
	end
	DataService.MarkDirty(player)

	if AnalyticsService then
		AnalyticsService.Log(AnalyticsConfig.Events.VEHICLE_SPAWNED, player.UserId, {
			vehicle = vehicleId,
			source = spawn.Source,
		})
	end
	local at = spawn.CFrame.Position
	print(string.format(
		"[VehicleService] SPAWN ok %s → %s (%s) @ %s (%.0f,%.0f,%.0f)",
		player.Name,
		tostring(vehicleId),
		mode,
		spawn.Source,
		at.X,
		at.Y,
		at.Z
	))
	if NotificationService then
		local msg = if autoSeat then "Deployed " .. def.DisplayName else "Deployed " .. def.DisplayName .. " — walk over to drive"
		NotificationService.Notify(player, msg, "Success")
	end
	pushState(player)
	return true, nil
end

function VehicleService.PushState(player: Player)
	pushState(player)
end

-- Research workflow: call after a vehicle upgrade so a vehicle that is already out picks it up.
function VehicleService.OnResearchChanged(player: Player)
	local model = activeVehicles[player.UserId]
	local rec = if model then vehicles[model] else nil
	if rec == nil then
		return
	end
	local bonus = researchMult(player, "VehicleSpeed", Drive.MaxResearchSpeedBonus)
	rec.Params.MaxSpeed = rec.BaseMaxSpeed * bonus
	rec.Model:SetAttribute("WE_MaxSpeed", rec.Params.MaxSpeed)
	rec.Model:SetAttribute("WE_ArmorMult", researchMult(player, "VehicleArmor", Drive.MaxResearchArmorBonus))
end

-- ── Test hooks (headless sim; spec §7) ─────────────────────────────────────────────────────────
VehicleService._DriveModeFor = driveModeFor
VehicleService._DriveAttributes = driveAttributes
VehicleService._Footprint = footprintOf
VehicleService._WaterSurfaceAt = waterSurfaceAt
VehicleService._IsConnectedToSea = isConnectedToSea
VehicleService._ChooseSpawn = chooseSpawn
VehicleService._BuildSpawnCtx = buildSpawnCtx
VehicleService._ValidateSample = validateSample
VehicleService._IdleTarget = idleTarget
VehicleService._OnDriverChanged = onDriverChanged
VehicleService._HandleDriveInput = handleDriveInput
VehicleService._Build = function(def: VehicleDef, at: CFrame?, ownerUserId: number?, bonus: number?): Model
	return buildVehicleModel(def, at or CFrame.identity, ownerUserId or 0, bonus, 1)
end
VehicleService._Laws = {
	NewState = newDriveState,
	CarStep = carStep,
	BoatStep = boatStep,
	BoatProbe = boatProbe,
	Idle = idleTarget,
}
VehicleService._Tick = tickAll
VehicleService._Record = function(model: Model): any
	return vehicles[model]
end
VehicleService._BrokenTrips = function(userId: number): number
	return brokenTrips[userId] or 0
end
VehicleService._DamageLockLeft = damageLockLeft
VehicleService._OnViolation = function(model: Model, reason: string, soft: boolean)
	local rec = vehicles[model]
	if rec then
		onViolation(rec, reason, soft, now())
	end
end

function VehicleService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	AnalyticsService = deps.AnalyticsService
	RateLimitService = deps.RateLimitService
	NotificationService = deps.NotificationService
	RemoteSetup = deps.RemoteSetup
	TerritoryService = deps.TerritoryService
	MissionService = deps.MissionService
	TutorialService = deps.TutorialService
	MonetizationService = deps.MonetizationService
	ResearchService = deps.ResearchService
	AntiExploitService = deps.AntiExploitService

	ensureFolder()
	refreshWaterParts()
	waterRefreshAt = now() + WaterCfg.RefreshSeconds
	CollectionService:GetInstanceAddedSignal(Constants.Tags.Water):Connect(function()
		waterRefreshAt = 0
	end)
	CollectionService:GetInstanceRemovedSignal(Constants.Tags.Water):Connect(function()
		waterRefreshAt = 0
	end)

	local spawnRemote = RemoteSetup.Get(Constants.RemoteNames.RequestSpawnVehicle) :: RemoteEvent
	spawnRemote.OnServerEvent:Connect(function(player: Player, vehicleId: any)
		if not RateLimitService.Allow(player, "spawn_vehicle", 1, 2) then
			if NotificationService then
				NotificationService.Notify(player, "Spawn too fast — wait a moment", "Warn", 2)
			end
			return
		end
		print(string.format("[VehicleService] Remote SPAWN attempt %s → %s", player.Name, tostring(vehicleId)))
		local ok, err = VehicleService.RequestSpawn(player, vehicleId)
		print(string.format("[VehicleService] Remote SPAWN result %s → Ok=%s Err=%s", player.Name, tostring(ok), tostring(err)))
		if not ok and NotificationService and err then
			local def = if typeof(vehicleId) == "string" then getDef(vehicleId) else nil
			NotificationService.Notify(player, errorText(err, def, player), "Warn")
		end
	end)

	local purchaseRemote = RemoteSetup.Get(Constants.RemoteNames.RequestPurchaseVehicle) :: RemoteEvent
	purchaseRemote.OnServerEvent:Connect(function(player: Player, vehicleId: any)
		if not RateLimitService.Allow(player, "buy_vehicle", 2, 3) then
			return
		end
		local ok, err = VehicleService.Purchase(player, vehicleId)
		if not ok and err then
			if err == "AlreadyOwned" then
				pcall(pushState, player)
			end
			if NotificationService then
				local def = if typeof(vehicleId) == "string" then getDef(vehicleId) else nil
				NotificationService.Notify(player, errorText(err, def, player), "Warn")
			end
		end
	end)

	local despawnRemote = RemoteSetup.Get(Constants.RemoteNames.RequestDespawnVehicle) :: RemoteEvent
	despawnRemote.OnServerEvent:Connect(function(player: Player)
		if not RateLimitService.Allow(player, "despawn_vehicle", 2, 3) then
			return
		end
		VehicleService.Despawn(player)
	end)

	local driveRemote = RemoteSetup.Get(Constants.RemoteNames.VehicleDriveInput) :: RemoteEvent
	driveRemote.OnServerEvent:Connect(function(player: Player, msg: any)
		handleDriveInput(player, msg)
	end)

	DataService.OnProfileLoaded(function(player: Player, profile: any)
		local starter = VehicleConfig.StarterVehicle
		if not profile.Vehicles[starter] then
			profile.Vehicles[starter] = true
			DataService.MarkDirty(player)
		end
		pushState(player)
	end)

	RunService.Heartbeat:Connect(tickAll)

	-- P1-9: remember when each player's character last took damage (a Health drop at an unchanged MaxHealth;
	-- CombatService's spawn reset of MaxHealth / regen never counts)
	local function watchCharacter(player: Player, character: Model)
		task.spawn(function()
			local found = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
			if not (found and found:IsA("Humanoid")) then
				return
			end
			local hum = found :: Humanoid
			local lastHealth, lastMax = hum.Health, hum.MaxHealth
			hum.HealthChanged:Connect(function(h: number)
				local max = hum.MaxHealth
				if h < lastHealth - 0.01 and max == lastMax then
					lastDamageAt[player.UserId] = now()
				end
				lastHealth, lastMax = h, max
			end)
		end)
	end
	local function hookPlayer(player: Player)
		player.CharacterAdded:Connect(function(character: Model)
			watchCharacter(player, character)
		end)
		local character = player.Character
		if character then
			watchCharacter(player, character)
		end
	end
	Players.PlayerAdded:Connect(hookPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		hookPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		destroyActive(player.UserId)
		lastSpawnAt[player.UserId] = nil
		lastDamageAt[player.UserId] = nil
		brokenTrips[player.UserId] = nil
		sitCueShown[player.UserId] = nil
		sitOfferShown[player.UserId] = nil
	end)
end

return VehicleService
