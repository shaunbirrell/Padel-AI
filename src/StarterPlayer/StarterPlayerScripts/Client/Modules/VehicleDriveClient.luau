--!strict
--[[
	v70: client half of drivable vehicles (cars, helicopters, planes, boats).

	The driver's client owns the vehicle's physics. Every frame this module turns the seat input
	(DriverSeat.ThrottleFloat/SteerFloat + the extra lift/strafe keys) into a target velocity and
	orientation, and writes them to the two movers the server built on the Chassis:
	  WE_DriveLV (LinearVelocity, PerAxis)  -> VectorVelocity + the Y part of MaxAxesForce
	  WE_DriveAO (AlignOrientation)         -> CFrame (rotation only)
	It writes only while the model's WE_DriveAuthority == "Client". The server checks the result
	(speed, altitude, teleports, map bounds, boats over WE_Water) and takes ownership back on a violation.
	No positions or velocities are ever sent to the server: the only remote is VehicleDriveInput
	{K="Hello"/"Bye"}.

	Laws (NewState / Step / ComposeInput / ControlsLayout / WaterSurfaceAt / ProbeDistances / BuildParams)
	are pure and are tested headless. The server's fallback + idle laws are a copy of the Car/Boat maths.

	Requiring this module does nothing heavy (GetService only). Init() is called by VehicleController.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local VehicleDriveClient = {}

export type Input = { Throttle: number, Steer: number, Lift: number, Strafe: number }

export type RawInput = {
	Throttle: number,
	Steer: number,
	Up: boolean?, -- Space
	Down: boolean?, -- LeftCtrl / C
	TouchUp: boolean?, -- mobile ▲
	TouchDown: boolean?, -- mobile ▼
	R2: number?, -- gamepad analog 0..1
	L2: number?,
	Left: boolean?, -- Z / L1 (strafe left)
	Right: boolean?, -- X / R1 (strafe right)
}

export type Sense = {
	Position: Vector3,
	Velocity: Vector3,
	Yaw: number,
	UpY: number,
	AGL: number, -- lowest solid point to the ground below; math.huge when nothing is below
	Time: number,
	Look: Vector3?, -- chassis LookVector (defaults to the flat heading)
	WaterY: number?,
	WaterNear: boolean?,
	WaterFar: boolean?,
}

export type Hud = { Speed: number, Alt: number?, Throttle: number?, Tag: string? }

export type Out = { Velocity: Vector3, HoldVertical: boolean, Orientation: CFrame, Hud: Hud }

export type Params = {
	Mode: string,
	MaxSpeed: number,
	Accel: number,
	TurnRate: number,
	Tracked: boolean,
	ClimbRate: number,
	MaxAltitude: number,
	Vto: number,
	Vstall: number,
	RideOffset: number,
	Clearance: number,
	HalfLength: number,
	HalfWidth: number,
	SpawnState: string?,
	SpawnSpeed: number,
	SoftBound: number,
	AutoTakeoff: boolean,
	C: { [string]: number },
}

export type State = {
	Mode: string,
	Age: number,
	Heading: number,
	LagFor: number,
	-- car / boat
	Speed: number,
	FlipFor: number,
	HopLeft: number,
	-- heli
	Fwd: number,
	Side: number,
	Vy: number,
	YawRate: number,
	HoldY: number?,
	Landed: boolean,
	Roll: number,
	-- plane (Pitch is shared with heli)
	Pitch: number,
	Lever: number,
	Airspeed: number,
	Airborne: boolean,
	ClimbOut: boolean,
	Stalled: boolean,
	Bank: number,
	-- boat
	BobT: number,
	LastWaterPos: Vector3?,
	LastWaterY: number?,
}

export type Rect = { Pos: Vector2, Size: Vector2 }
export type Layout = { Up: Rect, Down: Rect, Where: string }

-- ─────────────────────────────────────────────────────────────────────────────
-- Defaults (spec section 2). VehicleConfig.Drive overrides any of these when present.
-- ─────────────────────────────────────────────────────────────────────────────
local PROTOCOL_VERSION = 1

local DEFAULTS: any = {
	ProtocolVersion = PROTOCOL_VERSION,
	HelloTimeoutSeconds = 2.5,
	World = { SoftBound = 3300 },
	Resync = { Gap = 10, CarGap = 6, Seconds = 0.3, GraceSeconds = 1 },
	Water = { RefreshSeconds = 2, QueryBelow = 8, QueryAbove = 20, LandProbeHeight = 30 },
	Modes = {
		Car = {
			ReverseFrac = 0.45,
			ReverseAccelFrac = 0.7,
			TurnSpeedRef = 12,
			YawResyncRad = 0.6,
			FlipUpY = 0.3,
			FlipSeconds = 2,
			HopSeconds = 0.5,
			HopSpeed = 15,
			Wheeled = { Accel = 28, Brake = 60, Coast = 10, TurnRate = 2.4, MinTurnFactor = 0.35, Grip = 8 },
			Tracked = { Accel = 16, Brake = 40, Coast = 10, TurnRate = 1.5, MinTurnFactor = 0.7, Grip = 12 },
		},
		Heli = {
			Accel = 22,
			Drag = 20,
			BackFrac = 0.4,
			StrafeFrac = 0.5,
			ClimbRate = 24,
			SinkRate = 20,
			AccelV = 30,
			TurnRate = 1.6,
			YawAccel = 5,
			MaxPitchTilt = 14,
			MaxRollTilt = 12,
			BankPerYawRate = 6,
			TiltRate = 25,
			AltHoldGain = 1.5,
			AltHoldMax = 6,
			LandAGL = 0.8,
			MaxAltitude = 450,
		},
		Plane = {
			Thrust = 20,
			Drag = 6,
			GroundDrag = 10,
			Brake = 30,
			GravityAlong = 25,
			OverspeedFrac = 1.15,
			ThrottleRateUp = 0.6,
			ThrottleRateDown = 0.8,
			MaxPitchUp = 30,
			MaxPitchDown = 35,
			PitchRate = 40,
			MaxBank = 55,
			BankRate = 90,
			TurnRate = 0.9,
			TaxiTurnRate = 0.8,
			StallNoseDown = -20,
			StallSinkMax = 35,
			StallClearMargin = 3,
			ClimbOutPitch = 15,
			ClimbOutAGL = 45,
			AutoTakeoff = true,
			AutoTakeoffLever = 0.9,
			AutoTakeoffSpeedFrac = 1.1,
			LiftoffPitch = 6,
			RolledOffAGL = 3,
			LandAGL = 1.5,
			MaxAltitude = 600,
			AirStartHeight = 120,
			AirStartSpeedFrac = 1.3,
			TakeoffFrac = 0.45,
			TakeoffMin = 40,
			TakeoffMax = 60,
			StallFrac = 0.8,
		},
		Boat = {
			Accel = 14,
			Brake = 18,
			Coast = 6,
			ReverseFrac = 0.35,
			ReverseAccelFrac = 0.7,
			TurnRate = 1.1,
			MinTurnFactor = 0.25,
			TurnSpeedRef = 8,
			Drift = 3,
			Draft = 0.15,
			BobAmp = 0.15,
			BobHz = 0.35,
			HeightGain = 4,
			MaxVy = 10,
			BowUpDeg = 4,
			TurnLeanDeg = 6,
			BobPitchDeg = 1.2,
			BobRollDeg = 1.5,
			BobRollHz = 0.4,
			ShoreBrake = 50,
			ShoreMargin = 3,
			AgroundSpeed = 8,
		},
	},
}

local DEFAULT_MAX_SPEED: { [string]: number } = { Car = 40, Heli = 60, Plane = 100, Boat = 40 }
local VALID_MODES: { [string]: boolean } = { Car = true, Heli = true, Plane = true, Boat = true }
-- per-variant car keys: a tracked vehicle never falls back to the wheeled value of these
local CAR_VARIANT_KEYS: { [string]: boolean } =
	{ Accel = true, Brake = true, Coast = true, TurnRate = true, MinTurnFactor = true, Grip = true }

-- ─────────────────────────────────────────────────────────────────────────────
-- Math helpers (spec 2.0 conventions)
-- ─────────────────────────────────────────────────────────────────────────────
local TAU = math.pi * 2

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

-- = CFrame.Angles(0, h, 0).LookVector
local function fwd(h: number): Vector3
	return Vector3.new(-math.sin(h), 0, -math.cos(h))
end

local function right(h: number): Vector3
	return Vector3.new(math.cos(h), 0, -math.sin(h))
end

local function yawOf(cf: CFrame): number
	local lv = cf.LookVector
	return math.atan2(-lv.X, -lv.Z)
end

local function wrap(a: number): number
	return (a + math.pi) % TAU - math.pi
end

-- pitch > 0 = nose up; bank > 0 = right wing down
local function orient(pitchDeg: number, h: number, bankDeg: number): CFrame
	return CFrame.fromEulerAnglesYXZ(math.rad(pitchDeg), h, -math.rad(bankDeg))
end

-- = orient(pitchDeg, h, 0).LookVector
local function lookVector(pitchDeg: number, h: number): Vector3
	local p = math.rad(pitchDeg)
	local cp = math.cos(p)
	return Vector3.new(-math.sin(h) * cp, math.sin(p), -math.cos(h) * cp)
end

local function flatUnit(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-4 then
		return Vector3.zero
	end
	return f.Unit
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Laws (pure)
-- ─────────────────────────────────────────────────────────────────────────────
local Laws = {}
VehicleDriveClient.Laws = Laws
VehicleDriveClient.DEFAULTS = DEFAULTS
VehicleDriveClient.PROTOCOL_VERSION = PROTOCOL_VERSION
Laws.Helpers = {
	approach = approach,
	fwd = fwd,
	right = right,
	yawOf = yawOf,
	wrap = wrap,
	orient = orient,
	lookVector = lookVector,
}

local function cfgNumber(src: any, key: string): number?
	if typeof(src) == "table" then
		local v = src[key]
		if typeof(v) == "number" then
			return v
		end
	end
	return nil
end

local function modeConstants(mode: string, tracked: boolean, drive: any): { [string]: number }
	local out: { [string]: number } = {}
	local defaults: any = DEFAULTS.Modes[mode] or DEFAULTS.Modes.Car
	local cfgModes: any = if typeof(drive) == "table" and typeof(drive.Modes) == "table" then drive.Modes else nil
	local cfg: any = if cfgModes and typeof(cfgModes[mode]) == "table" then cfgModes[mode] else nil
	for k, v in pairs(defaults) do
		if typeof(v) == "number" then
			out[k] = v
		end
	end
	if mode == "Car" then
		local variant = if tracked then "Tracked" else "Wheeled"
		for k, v in pairs(defaults[variant]) do
			out[k] = v
		end
		if cfg then
			local sub: any = cfg[variant]
			for k in pairs(out) do
				local val = cfgNumber(sub, k)
				if val == nil and tracked then
					val = cfgNumber(cfg, "Tracked" .. k)
				end
				if val == nil and (not tracked or not CAR_VARIANT_KEYS[k]) then
					val = cfgNumber(cfg, k)
				end
				if val ~= nil then
					out[k] = val
				end
			end
		end
	elseif cfg then
		for k in pairs(out) do
			local val = cfgNumber(cfg, k)
			if val ~= nil then
				out[k] = val
			end
		end
	end
	-- speed resync (Drive.Resync, shared by every mode)
	local rs: any = if typeof(drive) == "table" then drive.Resync else nil
	local d: any = DEFAULTS.Resync
	out.ResyncGap = if mode == "Car" then (cfgNumber(rs, "CarGap") or d.CarGap) else (cfgNumber(rs, "Gap") or d.Gap)
	out.ResyncSeconds = cfgNumber(rs, "Seconds") or d.Seconds
	out.ResyncGrace = cfgNumber(rs, "GraceSeconds") or d.GraceSeconds
	return out
end

--[[ Params from the vehicle model's attributes (spec 6.2) + VehicleConfig.Drive (or DEFAULTS). ]]
function Laws.BuildParams(mode: string, attrs: { [string]: any }, drive: any?): Params
	local function a(key: string): number?
		local v = attrs[key]
		if typeof(v) == "number" and v == v then
			return v
		end
		return nil
	end
	local tracked = attrs.WE_Tracked == true
	local C = modeConstants(mode, tracked, drive)
	local maxSpeed = math.max(1, a("WE_MaxSpeed") or DEFAULT_MAX_SPEED[mode] or 40)
	local accelDefault = if mode == "Plane" then (C.Thrust or 20) else (C.Accel or 20)
	local vto = a("WE_TakeoffSpeed")
		or math.clamp((C.TakeoffFrac or 0.45) * maxSpeed, C.TakeoffMin or 40, math.max(C.TakeoffMin or 40, C.TakeoffMax or 60))
	local clearance = a("WE_GroundClearance") or 2
	local autoTakeoff = true
	if typeof(drive) == "table" and typeof(drive.Modes) == "table" and typeof(drive.Modes.Plane) == "table" then
		local v = drive.Modes.Plane.AutoTakeoff
		if typeof(v) == "boolean" then
			autoTakeoff = v
		end
	end
	local softBound = 3300
	if typeof(drive) == "table" then
		softBound = cfgNumber(drive.World, "SoftBound") or softBound
	end
	local spawnState = attrs.WE_SpawnState
	return {
		Mode = mode,
		MaxSpeed = maxSpeed,
		Accel = math.max(0.1, a("WE_Accel") or accelDefault),
		TurnRate = a("WE_TurnRate") or C.TurnRate or 1,
		Tracked = tracked,
		ClimbRate = a("WE_ClimbRate") or C.ClimbRate or 24,
		MaxAltitude = a("WE_MaxAltitude") or C.MaxAltitude or 450,
		Vto = math.max(1, vto),
		Vstall = math.max(0.5, a("WE_StallSpeed") or (C.StallFrac or 0.8) * vto),
		RideOffset = a("WE_RideOffset") or (clearance - (C.Draft or 0.15)),
		Clearance = clearance,
		HalfLength = a("WE_HalfLength") or 6,
		HalfWidth = a("WE_HalfWidth") or 3,
		SpawnState = if typeof(spawnState) == "string" then spawnState else nil,
		SpawnSpeed = a("WE_SpawnSpeed") or 0,
		SoftBound = softBound,
		AutoTakeoff = autoTakeoff,
		C = C,
	}
end

local function blankState(mode: string): State
	return {
		Mode = mode,
		Age = 0,
		Heading = 0,
		LagFor = 0,
		Speed = 0,
		FlipFor = 0,
		HopLeft = 0,
		Fwd = 0,
		Side = 0,
		Vy = 0,
		YawRate = 0,
		HoldY = nil,
		Landed = false,
		Roll = 0,
		Pitch = 0,
		Lever = 0,
		Airspeed = 0,
		Airborne = false,
		ClimbOut = false,
		Stalled = false,
		Bank = 0,
		BobT = 0,
		LastWaterPos = nil,
		LastWaterY = nil,
	}
end

--[[ Fresh law state from the vehicle's current pose. Re-run whenever WE_DriveAuthority becomes "Client". ]]
function Laws.NewState(P: Params, sense: Sense): State
	local st = blankState(P.Mode)
	st.Heading = sense.Yaw
	local look = sense.Look or fwd(sense.Yaw)
	local vel = sense.Velocity
	if P.Mode == "Heli" then
		st.Landed = sense.AGL <= P.C.LandAGL
		if not st.Landed then
			st.Fwd = vel:Dot(fwd(sense.Yaw))
			st.Side = vel:Dot(right(sense.Yaw))
			st.Vy = vel.Y
		end
		st.Pitch = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
		st.HoldY = nil
	elseif P.Mode == "Plane" then
		local forwardActual = vel:Dot(look)
		-- the WE_SpawnState "Airborne" flag only counts while actually off the ground (a parked
		-- air-start plane re-entered on the runway must not start rolling at its spawn speed)
		st.Airborne = sense.AGL > P.C.RolledOffAGL or (P.SpawnState == "Airborne" and sense.AGL > P.C.LandAGL)
		st.ClimbOut = false
		st.Bank = 0
		if st.Airborne then
			st.Airspeed = math.max(forwardActual, P.SpawnSpeed)
			st.Lever = math.clamp(st.Airspeed / P.MaxSpeed, 0, 1)
		else
			st.Airspeed = math.max(forwardActual, 0)
			st.Lever = 0
		end
		st.Pitch = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
	else
		st.Speed = vel:Dot(fwd(sense.Yaw))
		if P.Mode == "Boat" and sense.WaterY ~= nil then
			st.LastWaterPos = sense.Position
			st.LastWaterY = sense.WaterY
		end
	end
	return st
end

-- spec 2.0 "speed resync": a vehicle pushed against a wall does not build up to full speed
local function resync(st: State, C: { [string]: number }, current: number, forwardActual: number, dt: number): number
	local gap = C.ResyncGap
	if st.Age < C.ResyncGrace then
		st.LagFor = 0
		return current
	end
	if forwardActual < current - gap then
		st.LagFor += dt
		if st.LagFor >= C.ResyncSeconds then
			st.LagFor = 0
			return forwardActual + gap
		end
	else
		st.LagFor = 0
	end
	return current
end

local function speedUpdate(
	speed: number,
	t: number,
	max: number,
	rev: number,
	accel: number,
	brake: number,
	coast: number,
	reverseAccelFrac: number,
	dt: number
): number
	if t > 0.05 then
		if speed < 0 then
			speed = approach(speed, 0, brake, dt)
		else
			speed = approach(speed, t * max, accel, dt)
		end
	elseif t < -0.05 then
		if speed > 0 then
			speed = approach(speed, 0, brake, dt)
		else
			speed = approach(speed, t * rev, accel * reverseAccelFrac, dt)
		end
	else
		speed = approach(speed, 0, coast, dt)
	end
	return math.clamp(speed, -rev, max)
end

-- 2.1 CAR (wheeled + tracked)
local function stepCar(st: State, P: Params, input: Input, sense: Sense, dt: number): Out
	local C = P.C
	local t, s = input.Throttle, input.Steer
	local Max = P.MaxSpeed
	local Rev = C.ReverseFrac * Max
	st.Speed = resync(st, C, st.Speed, sense.Velocity:Dot(fwd(st.Heading)), dt)
	st.Speed = speedUpdate(st.Speed, t, Max, Rev, P.Accel, C.Brake, C.Coast, C.ReverseAccelFrac, dt)
	local dir = if st.Speed < -0.5 then -1 else 1
	st.Heading -= s * P.TurnRate * math.clamp(math.abs(st.Speed) / C.TurnSpeedRef, C.MinTurnFactor, 1) * dir * dt
	if math.abs(wrap(sense.Yaw - st.Heading)) > C.YawResyncRad then
		st.Heading = sense.Yaw -- a collision spun us: stop fighting it
	end
	local r = right(st.Heading)
	local lat = sense.Velocity:Dot(r) * math.exp(-C.Grip * dt)
	local vel = fwd(st.Heading) * st.Speed + r * lat
	local hold = false
	-- unstick: upside down for FlipSeconds -> short vertical hop while the AO rights the car
	if sense.UpY < C.FlipUpY then
		st.FlipFor += dt
	else
		st.FlipFor = 0
	end
	if st.FlipFor >= C.FlipSeconds then
		st.FlipFor = 0
		st.HopLeft = C.HopSeconds
	end
	if st.HopLeft > 0 then
		st.HopLeft -= dt
		vel = Vector3.new(vel.X, C.HopSpeed, vel.Z)
		hold = true
	end
	return {
		Velocity = vel,
		HoldVertical = hold,
		Orientation = orient(0, st.Heading, 0),
		Hud = { Speed = math.abs(st.Speed) },
	}
end

-- 2.2 HELICOPTER
local function stepHeli(st: State, P: Params, input: Input, sense: Sense, dt: number): Out
	local C = P.C
	local Max = P.MaxSpeed
	local t, s, lift = input.Throttle, input.Steer, input.Lift
	st.Fwd = resync(st, C, st.Fwd, sense.Velocity:Dot(fwd(st.Heading)), dt)
	local fT = if t >= 0 then t * Max else t * Max * C.BackFrac
	st.Fwd = approach(st.Fwd, fT, if math.abs(fT) > math.abs(st.Fwd) then P.Accel else C.Drag, dt)
	local sT = input.Strafe * Max * C.StrafeFrac
	st.Side = approach(st.Side, sT, if math.abs(sT) > math.abs(st.Side) then P.Accel else C.Drag, dt)
	st.YawRate = approach(st.YawRate, -s * P.TurnRate, C.YawAccel, dt)
	st.Heading += st.YawRate * dt

	local y = sense.Position.Y
	local vyT: number
	if math.abs(lift) > 0.05 then
		vyT = if lift > 0 then lift * P.ClimbRate else lift * C.SinkRate
		st.HoldY = nil
	else
		local holdY = st.HoldY
		if holdY == nil then
			vyT = 0 -- settle first, then capture the hover height
			if math.abs(st.Vy) < 1 then
				st.HoldY = y
			end
		else
			vyT = math.clamp((holdY - y) * C.AltHoldGain, -C.AltHoldMax, C.AltHoldMax)
		end
	end
	if y >= P.MaxAltitude then
		vyT = math.min(vyT, -(y - P.MaxAltitude))
	end
	st.Vy = approach(st.Vy, vyT, C.AccelV, dt)

	if lift > 0.05 then
		st.Landed = false -- take off
	elseif not st.Landed and sense.AGL <= C.LandAGL and st.Vy <= 0 then
		st.Landed = true
	end
	if st.Landed then
		st.Fwd = 0
		st.Side = 0
		st.Vy = 0
		st.YawRate = 0
		st.HoldY = nil
	end

	local vel = fwd(st.Heading) * st.Fwd + right(st.Heading) * st.Side + Vector3.new(0, st.Vy, 0)
	local pitchT = -(st.Fwd / Max) * C.MaxPitchTilt -- nose down when flying forward
	local rollT = -(st.Side / (Max * C.StrafeFrac)) * C.MaxRollTilt + st.YawRate * C.BankPerYawRate
	st.Pitch = approach(st.Pitch, pitchT, C.TiltRate, dt)
	st.Roll = approach(st.Roll, rollT, C.TiltRate, dt)
	return {
		Velocity = vel,
		HoldVertical = not st.Landed,
		Orientation = CFrame.fromEulerAnglesYXZ(math.rad(st.Pitch), st.Heading, math.rad(st.Roll)),
		Hud = {
			Speed = math.sqrt(st.Fwd * st.Fwd + st.Side * st.Side),
			Alt = sense.AGL,
			Tag = if st.Landed then "LANDED" else nil,
		},
	}
end

-- 2.3 PLANE
local function stepPlane(st: State, P: Params, input: Input, sense: Sense, dt: number): Out
	local C = P.C
	local Max = P.MaxSpeed
	local Vto, Vstall = P.Vto, P.Vstall
	local t, s, lift = input.Throttle, input.Steer, input.Lift
	local agl = sense.AGL
	local look0 = if st.Airborne then lookVector(st.Pitch, st.Heading) else fwd(st.Heading)
	st.Airspeed = resync(st, C, st.Airspeed, sense.Velocity:Dot(look0), dt)

	st.Lever = math.clamp(st.Lever + t * (if t > 0 then C.ThrottleRateUp else C.ThrottleRateDown) * dt, 0, 1)
	local target = st.Lever * Max

	local function groundOut(): Out
		return {
			Velocity = fwd(st.Heading) * st.Airspeed,
			HoldVertical = false,
			Orientation = orient(st.Pitch, st.Heading, st.Bank),
			Hud = {
				Speed = st.Airspeed,
				Alt = agl,
				Throttle = st.Lever,
				Tag = if st.Airspeed < Vto then ("LIFT OFF AT " .. tostring(math.floor(Vto))) else nil,
			},
		}
	end

	if not st.Airborne then
		local rate = if target > st.Airspeed then P.Accel elseif t < -0.05 then C.Brake else C.GroundDrag
		st.Airspeed = approach(st.Airspeed, target, rate, dt)
		st.Heading -= s * C.TaxiTurnRate * math.clamp(st.Airspeed / 10, 0.3, 1) * dt
		st.Pitch = approach(st.Pitch, 0, C.PitchRate, dt)
		st.Bank = approach(st.Bank, 0, C.BankRate, dt)
		if
			st.Airspeed >= Vto
			and (
				lift > 0.2
				or (P.AutoTakeoff and st.Lever >= C.AutoTakeoffLever and st.Airspeed >= C.AutoTakeoffSpeedFrac * Vto)
			)
		then
			st.Airborne = true
			st.Pitch = math.max(st.Pitch, C.LiftoffPitch) -- 6°: climbing at once, no instant touchdown
			st.ClimbOut = true
		end
		if agl > C.RolledOffAGL then
			st.Airborne = true -- rolled off an edge
		end
		if not st.Airborne then
			return groundOut()
		end
	end

	-- AIRBORNE
	st.Airspeed = approach(st.Airspeed, target, if target > st.Airspeed then P.Accel else C.Drag, dt)
		- C.GravityAlong * math.sin(math.rad(st.Pitch)) * dt
	st.Airspeed = math.clamp(st.Airspeed, 0, Max * C.OverspeedFrac)
	if st.Stalled then
		if st.Airspeed >= Vstall + C.StallClearMargin then
			st.Stalled = false
		end
	elseif st.Airspeed < Vstall then
		st.Stalled = true
	end
	local pitchT = if lift >= 0 then lift * C.MaxPitchUp else lift * C.MaxPitchDown
	if st.ClimbOut and (agl >= C.ClimbOutAGL or lift < -0.05) then
		st.ClimbOut = false
	end
	if st.ClimbOut then
		pitchT = math.max(pitchT, C.ClimbOutPitch) -- climb-out assist, only right after lift-off
	end
	if st.Stalled then
		pitchT = math.min(pitchT, C.StallNoseDown)
	end
	local y = sense.Position.Y
	if y > P.MaxAltitude - 30 then
		pitchT = math.min(pitchT, 0)
	end
	if y > P.MaxAltitude then
		pitchT = math.min(pitchT, -5)
	end
	st.Pitch = approach(st.Pitch, pitchT, C.PitchRate, dt)
	st.Bank = approach(st.Bank, s * C.MaxBank, C.BankRate, dt)
	st.Heading -= (st.Bank / C.MaxBank) * P.TurnRate * math.clamp(st.Airspeed / Vto, 0.5, 1) * dt
	local sink = if st.Stalled then C.StallSinkMax * math.max(0, 1 - st.Airspeed / Vstall) else 0
	local vel = lookVector(st.Pitch, st.Heading) * st.Airspeed - Vector3.new(0, sink, 0)

	-- TOUCHDOWN
	if agl <= C.LandAGL and vel.Y <= 2 then
		st.Airborne = false
		st.ClimbOut = false
		st.Stalled = false
		st.Pitch = 0
		st.Bank = 0
		st.Airspeed = math.min(st.Airspeed, Vto)
		return groundOut()
	end

	local tag: string? = nil
	if st.Stalled then
		tag = "STALL"
	elseif agl < 15 and vel.Y < -20 then
		tag = "PULL UP"
	end
	return {
		Velocity = vel,
		HoldVertical = true,
		Orientation = orient(st.Pitch, st.Heading, st.Bank),
		Hud = { Speed = st.Airspeed, Alt = agl, Throttle = st.Lever, Tag = tag },
	}
end

--[[ 2.4 boat shore probes. The client calls this BEFORE building sense.WaterNear/WaterFar:
	near/far points are Position + fwd(Heading) * dir * near / far. ]]
function Laws.ProbeDistances(st: State, P: Params, input: Input): (number, number, number)
	local C = P.C
	local dir = if st.Speed < -0.5 or (st.Speed <= 0 and input.Throttle < 0) then -1 else 1
	local near = P.HalfLength + C.ShoreMargin
	local far = near + (st.Speed * st.Speed) / (2 * C.ShoreBrake) + 2
	return dir, near, far
end

-- 2.4 BOAT
local function stepBoat(st: State, P: Params, input: Input, sense: Sense, dt: number): Out
	local C = P.C
	local t, s = input.Throttle, input.Steer
	local Max = P.MaxSpeed
	local Rev = C.ReverseFrac * Max
	st.Speed = resync(st, C, st.Speed, sense.Velocity:Dot(fwd(st.Heading)), dt)
	local dir = Laws.ProbeDistances(st, P, input)
	local before = st.Speed
	st.Speed = speedUpdate(st.Speed, t, Max, Rev, P.Accel, C.Brake, C.Coast, C.ReverseAccelFrac, dt)
	if sense.WaterNear == false then
		-- hard stop: no throttle into the shore
		st.Speed = if dir > 0 then math.min(st.Speed, 0) else math.max(st.Speed, 0)
	elseif sense.WaterFar == false then
		-- brake before the shore; throttle never adds speed toward it meanwhile (prototype behaviour)
		local base = if math.abs(st.Speed) > math.abs(before) then before else st.Speed
		st.Speed = approach(base, 0, C.ShoreBrake, dt)
	end
	st.Heading -= s * P.TurnRate * math.clamp(math.abs(st.Speed) / C.TurnSpeedRef, C.MinTurnFactor, 1) * dir * dt

	local pos = sense.Position
	local vel: Vector3
	local hold = true
	local tag: string? = nil
	local waterY = sense.WaterY
	if waterY == nil then
		-- pushed aground: head back to the last water position
		tag = "AGROUND"
		st.Speed = 0
		local lastPos, lastY = st.LastWaterPos, st.LastWaterY
		if lastPos and lastY then
			local vy = math.clamp((lastY + P.RideOffset - pos.Y) * C.HeightGain, -C.MaxVy, C.MaxVy)
			vel = flatUnit(lastPos - pos) * C.AgroundSpeed + Vector3.new(0, vy, 0)
		else
			vel = Vector3.zero
			hold = false
		end
	else
		st.LastWaterPos = pos
		st.LastWaterY = waterY
		st.BobT += dt
		local rideY = waterY + P.RideOffset + C.BobAmp * 0.5 * (1 + math.sin(TAU * C.BobHz * st.BobT))
		local vy = math.clamp((rideY - pos.Y) * C.HeightGain, -C.MaxVy, C.MaxVy)
		local r = right(st.Heading)
		local lat = sense.Velocity:Dot(r) * math.exp(-C.Drift * dt)
		vel = fwd(st.Heading) * st.Speed + r * lat + Vector3.new(0, vy, 0)
	end
	local pitchDeg = (st.Speed / Max) * C.BowUpDeg + C.BobPitchDeg * math.sin(math.pi * st.BobT)
	local rollDeg = -s * math.clamp(st.Speed / Max, 0, 1) * C.TurnLeanDeg
		+ C.BobRollDeg * math.sin(TAU * C.BobRollHz * st.BobT + 1)
	return {
		Velocity = vel,
		HoldVertical = hold,
		Orientation = CFrame.fromEulerAnglesYXZ(math.rad(pitchDeg), st.Heading, math.rad(rollDeg)),
		Hud = { Speed = math.abs(st.Speed), Tag = tag },
	}
end

-- soft map edge: past SoftBound drop the outward horizontal velocity; aircraft turn back to the centre
local function applySoftBound(st: State, P: Params, sense: Sense, out: Out, dt: number)
	local sb = P.SoftBound
	local p = sense.Position
	if math.abs(p.X) <= sb and math.abs(p.Z) <= sb then
		return
	end
	local v = out.Velocity
	local vx, vz = v.X, v.Z
	if (p.X > sb and vx > 0) or (p.X < -sb and vx < 0) then
		vx = 0
	end
	if (p.Z > sb and vz > 0) or (p.Z < -sb and vz < 0) then
		vz = 0
	end
	out.Velocity = Vector3.new(vx, v.Y, vz)
	if P.Mode == "Heli" or P.Mode == "Plane" then
		local toCentre = math.atan2(p.X, p.Z) -- fwd(h) points at the origin
		st.Heading += math.clamp(wrap(toCentre - st.Heading), -0.5 * dt, 0.5 * dt)
	end
	if out.Hud.Tag == nil then
		out.Hud.Tag = "TURN BACK"
	end
end

--[[ One control step. Changes `st` in place; returns the mover targets (spec 2.0). ]]
function Laws.Step(st: State, P: Params, input: Input, sense: Sense, dt: number): Out
	dt = math.clamp(dt, 0, 0.1)
	st.Age += dt
	local out: Out
	if P.Mode == "Heli" then
		out = stepHeli(st, P, input, sense, dt)
	elseif P.Mode == "Plane" then
		out = stepPlane(st, P, input, sense, dt)
	elseif P.Mode == "Boat" then
		out = stepBoat(st, P, input, sense, dt)
	else
		out = stepCar(st, P, input, sense, dt)
	end
	applySoftBound(st, P, sense, out, dt)
	return out
end

--[[ Seat throttle/steer + extra axes -> law input (spec 3). ]]
function Laws.ComposeInput(mode: string, raw: RawInput): Input
	local lift = 0
	if mode == "Heli" or mode == "Plane" then
		local up = if raw.Up or raw.TouchUp then 1 else math.clamp(raw.R2 or 0, 0, 1)
		local down = if raw.Down or raw.TouchDown then 1 else math.clamp(raw.L2 or 0, 0, 1)
		lift = math.clamp(up - down, -1, 1)
	end
	local strafe = 0
	if mode == "Heli" then
		strafe = (if raw.Right then 1 else 0) - (if raw.Left then 1 else 0)
	end
	return {
		Throttle = math.clamp(raw.Throttle, -1, 1),
		Steer = math.clamp(raw.Steer, -1, 1),
		Lift = lift,
		Strafe = strafe,
	}
end

--[[ Mobile ▲/▼ column in pixels (spec 3.1). Positions are top-left corners in the same space as jumpPos. ]]
function Laws.ControlsLayout(
	jumpPos: Vector2?,
	jumpSize: Vector2?,
	viewport: Vector2,
	reservedTopFromBottom: number?
): Layout
	local reserved = reservedTopFromBottom or 250
	local size = if viewport.Y < 500 then 52 else 60
	local gap = 8
	local S = Vector2.new(size, size)
	if jumpPos and jumpSize then
		-- 1) column centred above the jump button
		local x = jumpPos.X + jumpSize.X / 2 - size / 2
		local downY = jumpPos.Y - 10 - size
		local upY = downY - gap - size
		if upY >= viewport.Y - reserved then
			return {
				Up = { Pos = Vector2.new(x, upY), Size = S },
				Down = { Pos = Vector2.new(x, downY), Size = S },
				Where = "Above",
			}
		end
		-- 2) column left of the jump button, bottom-aligned with it
		local lx = jumpPos.X - 10 - size
		local ldown = jumpPos.Y + jumpSize.Y - size
		return {
			Up = { Pos = Vector2.new(lx, ldown - gap - size), Size = S },
			Down = { Pos = Vector2.new(lx, ldown), Size = S },
			Where = "Left",
		}
	end
	-- 3) no jump button
	local fx = viewport.X - 24 - size
	local fdown = viewport.Y - 110 - size
	return {
		Up = { Pos = Vector2.new(fx, fdown - gap - size), Size = S },
		Down = { Pos = Vector2.new(fx, fdown), Size = S },
		Where = "Fallback",
	}
end

-- Drive.Water.QueryBelow / QueryAbove (set from VehicleConfig in Init; same defaults as the server)
local waterBelow, waterAbove = 8, 20

--[[ Water surface Y under pos (spec 2.5; same algorithm as VehicleService._WaterSurfaceAt). ]]
function Laws.WaterSurfaceAt(
	parts: { BasePart },
	pos: Vector3,
	margin: number?,
	landProbe: ((number, number, number) -> boolean)?
): number?
	local m = margin or 0
	local best: number? = nil
	for _, p in ipairs(parts) do
		local lp = p.CFrame:PointToObjectSpace(pos)
		local size = p.Size
		if math.abs(lp.X) <= size.X / 2 - m and math.abs(lp.Z) <= size.Z / 2 - m then
			local top = p.Position.Y + size.Y / 2
			if pos.Y >= top - waterBelow and pos.Y <= top + waterAbove and (best == nil or top > best) then
				best = top
			end
		end
	end
	if best ~= nil and landProbe ~= nil and landProbe(pos.X, pos.Z, best) then
		return nil
	end
	return best
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Runtime (client only; everything below runs from Init)
-- ─────────────────────────────────────────────────────────────────────────────
type Drive = {
	Model: Model,
	Seat: VehicleSeat,
	Chassis: BasePart,
	Humanoid: Humanoid,
	Mode: string,
	VehicleId: string,
	Params: Params,
	State: State?,
	LV: LinearVelocity?,
	AO: AlignOrientation?,
	WasClient: boolean,
	HelloSent: number,
	LastHelloAt: number,
	LastMoverLookAt: number,
	HudAcc: number,
	Blocked: string?,
	Conns: { RBXScriptConnection },
}

local WATER_TAG_DEFAULT = "WE_Water"
local DRIVE_INPUT_DEFAULT = "VehicleDriveInput"
local VEHICLE_FOLDER = "WarEmpireVehicles"
local AGL_RAY = 1200
local HELLO_RETRY_SECONDS = 1.0
local HELLO_MAX = 4
local RESERVED_FROM_BOTTOM = 250

local ACTION_UP = "WE_VehLiftUp"
local ACTION_DOWN = "WE_VehLiftDown"
local ACTION_STRAFE = "WE_VehStrafe"
local ACTION_EXIT = "WE_VehExit"

local HINTS: { [string]: { PC: string, Touch: string } } = {
	Heli = {
		PC = "W/S fly · A/D turn · SPACE up · CTRL down · Z/X strafe · F exit",
		Touch = "Stick: fly/turn · ▲▼ climb/descend · Jump exits",
	},
	Plane = {
		PC = "Hold W: throttle · A/D bank · SPACE nose up (lift off at %d) · F exit",
		Touch = "Push stick up for throttle · ▲ to lift off · Jump exits",
	},
}
local RED_TAGS: { [string]: boolean } = { STALL = true, ["PULL UP"] = true, AGROUND = true, ["TURN BACK"] = true }

local initialized = false
local RemotesMod: any = nil
local waterTag = WATER_TAG_DEFAULT
local driveInputName = DRIVE_INPUT_DEFAULT
local driveCfg: any = nil
local isTouch = false
local landProbeHeight = 30
local waterRefreshSeconds = 2

local active: Drive? = nil
local waterParts: { BasePart } = {}
local rayParams: RaycastParams? = nil
local promptFolderConn: RBXScriptConnection? = nil
local hintShown: { [string]: boolean } = {}
local hintToken = 0

-- input state (reset whenever the actions unbind)
local keyDown: { [Enum.KeyCode]: boolean } = {}
local analog = { R2 = 0, L2 = 0 }
local touchOwners: { [InputObject]: string } = {}
local touchUp, touchDown = false, false

-- HUD
local hudGui: ScreenGui? = nil
local pill: TextLabel? = nil
local hintLabel: TextLabel? = nil
local controlsFrame: Frame? = nil
local upBtn: TextButton? = nil
local downBtn: TextButton? = nil
local layoutConns: { RBXScriptConnection } = {}

local function localPlayer(): Player
	return Players.LocalPlayer
end

local function loadShared()
	-- Shared is already loaded by VehicleController (the only caller of Init), so these never wait long
	local okC, C = pcall(function(): any
		return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
	end)
	if okC and typeof(C) == "table" then
		if typeof(C.Tags) == "table" and typeof(C.Tags.Water) == "string" then
			waterTag = C.Tags.Water
		end
		if typeof(C.RemoteNames) == "table" and typeof(C.RemoteNames.VehicleDriveInput) == "string" then
			driveInputName = C.RemoteNames.VehicleDriveInput
		end
	end
	local okR, R = pcall(function(): any
		return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
	end)
	if okR and typeof(R) == "table" then
		RemotesMod = R
	else
		warn("[VehicleDriveClient] Remotes module:", R)
	end
	local okV, V = pcall(function(): any
		return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Configs"):WaitForChild("VehicleConfig"))
	end)
	if okV and typeof(V) == "table" and typeof(V.Drive) == "table" then
		driveCfg = V.Drive
	end
end

local function sendDriveInput(msg: { [string]: any })
	local mod = RemotesMod
	if not mod then
		return
	end
	task.spawn(function()
		local ok, err = pcall(mod.FireServer, driveInputName, msg)
		if not ok then
			warn("[VehicleDriveClient] VehicleDriveInput:", err)
		end
	end)
end

-- ── world queries ───────────────────────────────────────────────────────────
local function refreshWater()
	local list: { BasePart } = {}
	for _, inst in ipairs(CollectionService:GetTagged(waterTag)) do
		if inst:IsA("BasePart") then
			table.insert(list, inst)
		end
	end
	waterParts = list
end

local function refreshRayFilter()
	local params = rayParams
	if not params then
		return
	end
	local list: { Instance } = {}
	local folder = Workspace:FindFirstChild(VEHICLE_FOLDER)
	if folder then
		table.insert(list, folder)
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		local ch = plr.Character
		if ch then
			table.insert(list, ch)
		end
	end
	for _, p in ipairs(waterParts) do
		table.insert(list, p)
	end
	params.FilterDescendantsInstances = list
end

-- kerbs, piers, pads, HarborShelf = land (spec 2.5)
local function landProbe(x: number, z: number, top: number): boolean
	local params = rayParams
	if not params then
		return false
	end
	local hit = Workspace:Raycast(Vector3.new(x, top + landProbeHeight, z), Vector3.new(0, -(landProbeHeight + 0.05), 0), params)
	return hit ~= nil and hit.Position.Y > top - 0.05
end

local function groundAGL(pos: Vector3, clearance: number): number
	local params = rayParams
	if not params then
		return math.huge
	end
	local hit = Workspace:Raycast(pos, Vector3.new(0, -AGL_RAY, 0), params)
	if not hit then
		return math.huge
	end
	return (pos.Y - hit.Position.Y) - clearance
end

-- ── prompts: only the owner sees "Drive", and not while already driving ─────
local function vehicleModelOf(inst: Instance): Model?
	local p = inst.Parent
	while p and p ~= Workspace do
		if p:IsA("Model") and p:GetAttribute("VehicleId") ~= nil then
			return p
		end
		p = p.Parent
	end
	return nil
end

local function refreshPrompt(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") or prompt.Name ~= "WE_DrivePrompt" then
		return
	end
	local model = vehicleModelOf(prompt)
	if not model then
		return
	end
	local mine = model:GetAttribute("OwnerUserId") == localPlayer().UserId
	local driving = active ~= nil and (active :: Drive).Model == model
	local want = mine and not driving
	if prompt.Enabled ~= want then
		prompt.Enabled = want
	end
end

local function refreshAllPrompts()
	local folder = Workspace:FindFirstChild(VEHICLE_FOLDER)
	if not folder then
		return
	end
	for _, d in ipairs(folder:GetDescendants()) do
		if d.Name == "WE_DrivePrompt" then
			refreshPrompt(d)
		end
	end
end

local function hookVehicleFolder()
	if promptFolderConn then
		return
	end
	local folder = Workspace:FindFirstChild(VEHICLE_FOLDER)
	if not folder then
		return
	end
	promptFolderConn = folder.DescendantAdded:Connect(function(d: Instance)
		if d.Name == "WE_DrivePrompt" then
			refreshPrompt(d)
		end
	end)
	refreshAllPrompts()
end

-- ── HUD ─────────────────────────────────────────────────────────────────────
local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function releaseTouches()
	table.clear(touchOwners)
	touchUp, touchDown = false, false
	for _, b in ipairs({ upBtn, downBtn }) do
		if b then
			b.BackgroundTransparency = 0.3
		end
	end
end

local function recomputeTouches()
	local up, down = false, false
	for _, which in pairs(touchOwners) do
		if which == "Up" then
			up = true
		elseif which == "Down" then
			down = true
		end
	end
	touchUp, touchDown = up, down
	if upBtn then
		upBtn.BackgroundTransparency = if up then 0.05 else 0.3
	end
	if downBtn then
		downBtn.BackgroundTransparency = if down then 0.05 else 0.3
	end
end

local function makeLiftButton(parent: Instance, name: string, text: string, which: string): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = text
	b.Font = Enum.Font.GothamBold
	b.TextSize = 24
	b.TextColor3 = Color3.fromRGB(245, 248, 252)
	b.BackgroundColor3 = Color3.fromRGB(42, 48, 55)
	b.BackgroundTransparency = 0.3
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Active = true
	b.Size = UDim2.fromOffset(52, 52)
	b.Parent = parent
	corner(b, 12)
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(230, 190, 60)
	st.Thickness = 1.5
	st.Transparency = 0.3
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = b
	-- hold buttons: track each touch separately so a thumb on the stick does not interfere
	b.InputBegan:Connect(function(io: InputObject)
		local ut = io.UserInputType
		if ut == Enum.UserInputType.Touch or ut == Enum.UserInputType.MouseButton1 then
			touchOwners[io] = which
			recomputeTouches()
		end
	end)
	b.InputEnded:Connect(function(io: InputObject)
		if touchOwners[io] then
			touchOwners[io] = nil
			recomputeTouches()
		end
	end)
	return b
end

local function ensureHud(): ScreenGui?
	local gui = hudGui
	if gui and gui.Parent then
		return gui
	end
	local pg = localPlayer():FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireVehicleHUD"
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.IgnoreGuiInset = false
	screen.DisplayOrder = 56 -- above the dock (55), below panels (60)
	screen.Enabled = true

	local p = Instance.new("TextLabel")
	p.Name = "WE_VehiclePill"
	p.AnchorPoint = Vector2.new(0.5, 1)
	p.Position = UDim2.new(0.5, 0, 1, if isTouch then -236 else -64)
	p.Size = UDim2.fromOffset(230, 30)
	p.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
	p.BackgroundTransparency = 0.25
	p.BorderSizePixel = 0
	p.Font = Enum.Font.GothamBold
	p.TextSize = 14
	p.TextColor3 = Color3.fromRGB(245, 248, 252)
	p.RichText = true
	p.Text = ""
	p.Visible = false
	p.Parent = screen
	corner(p, 8)
	pill = p

	local h = Instance.new("TextLabel")
	h.Name = "WE_VehicleHint"
	h.AnchorPoint = Vector2.new(0.5, 1)
	h.Position = UDim2.new(0.5, 0, 1, (if isTouch then -236 else -64) - 36)
	h.Size = UDim2.new(0.92, 0, 0, 26)
	h.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
	h.BackgroundTransparency = 0.35
	h.BorderSizePixel = 0
	h.Font = Enum.Font.Gotham
	h.TextSize = if isTouch then 12 else 13
	h.TextColor3 = Color3.fromRGB(255, 210, 90)
	h.TextWrapped = true
	h.Text = ""
	h.Visible = false
	h.Parent = screen
	corner(h, 6)
	local hc = Instance.new("UISizeConstraint")
	hc.MaxSize = Vector2.new(560, 40)
	hc.Parent = h
	hintLabel = h

	local cf = Instance.new("Frame")
	cf.Name = "WE_VehicleControls"
	cf.BackgroundTransparency = 1
	cf.Size = UDim2.fromScale(1, 1)
	cf.Active = false
	cf.Visible = false
	cf.Parent = screen
	controlsFrame = cf
	upBtn = makeLiftButton(cf, "LiftUp", "▲", "Up")
	downBtn = makeLiftButton(cf, "LiftDown", "▼", "Down")

	screen.Parent = pg
	hudGui = screen
	return screen
end

local function findJumpButton(): GuiObject?
	local pg = localPlayer():FindFirstChildOfClass("PlayerGui")
	local tg = pg and pg:FindFirstChild("TouchGui")
	if not (tg and tg:IsA("ScreenGui") and tg.Enabled) then
		return nil
	end
	local frame = tg:FindFirstChild("TouchControlFrame")
	local jb = frame and frame:FindFirstChild("JumpButton")
	if jb and jb:IsA("GuiObject") and jb.Visible and typeof(jb.AbsoluteSize) == "Vector2" and jb.AbsoluteSize.X > 0 then
		return jb
	end
	return nil
end

local function layoutControls()
	local gui, ub, db = hudGui, upBtn, downBtn
	if not (gui and ub and db) then
		return
	end
	local vp: Vector2 = gui.AbsoluteSize
	if typeof(vp) ~= "Vector2" or vp.X < 1 or vp.Y < 1 then
		local cam = Workspace.CurrentCamera
		vp = if cam then cam.ViewportSize else Vector2.new(844, 390)
	end
	-- the jump button lives in TouchGui; convert its absolute pixels into this ScreenGui's space
	local origin: Vector2 = gui.AbsolutePosition
	if typeof(origin) ~= "Vector2" then
		origin = Vector2.zero
	end
	local jb = findJumpButton()
	local jpos: Vector2? = nil
	local jsize: Vector2? = nil
	if jb then
		jpos = jb.AbsolutePosition - origin
		jsize = jb.AbsoluteSize
	end
	local L = Laws.ControlsLayout(jpos, jsize, vp, RESERVED_FROM_BOTTOM)
	ub.Position = UDim2.fromOffset(L.Up.Pos.X, L.Up.Pos.Y)
	ub.Size = UDim2.fromOffset(L.Up.Size.X, L.Up.Size.Y)
	db.Position = UDim2.fromOffset(L.Down.Pos.X, L.Down.Pos.Y)
	db.Size = UDim2.fromOffset(L.Down.Size.X, L.Down.Size.Y)
end

local function hideControls()
	for _, c in ipairs(layoutConns) do
		c:Disconnect()
	end
	table.clear(layoutConns)
	releaseTouches()
	if controlsFrame then
		controlsFrame.Visible = false
	end
end

local function showControls()
	if not ensureHud() or not controlsFrame then
		return
	end
	hideControls()
	layoutControls()
	local cam = Workspace.CurrentCamera
	if cam then
		table.insert(layoutConns, cam:GetPropertyChangedSignal("ViewportSize"):Connect(layoutControls))
	end
	local jb = findJumpButton()
	if jb then
		table.insert(layoutConns, jb:GetPropertyChangedSignal("AbsolutePosition"):Connect(layoutControls))
		table.insert(layoutConns, jb:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutControls))
	end
	;(controlsFrame :: Frame).Visible = true
end

local function hudText(mode: string, hud: Hud?, fallbackSpeed: number, blocked: string?): string
	if blocked then
		return string.format('<font color="#FF5A50">%s</font>', blocked)
	end
	local speed = if hud then hud.Speed else fallbackSpeed
	local text = string.format("SPD %d", math.floor(speed + 0.5))
	if hud and (mode == "Heli" or mode == "Plane") then
		local alt = hud.Alt
		if alt ~= nil and alt < 1e6 then
			text ..= string.format(" · ALT %d", math.max(0, math.floor(alt + 0.5)))
		else
			text ..= " · ALT --"
		end
		if mode == "Plane" and hud.Throttle ~= nil then
			text ..= string.format(" · THR %d%%", math.floor(hud.Throttle * 100 + 0.5))
		end
	end
	local tag = hud and hud.Tag
	if tag then
		local color = if RED_TAGS[tag] then "#FF5A50" else "#FFC850"
		text ..= string.format('  <font color="%s">%s</font>', color, tag)
	end
	return text
end

--[[ Device-aware control hint (spec 3.1), or nil for modes without one. ]]
function Laws.HintText(mode: string, touch: boolean, vto: number): string?
	local spec = HINTS[mode]
	if not spec then
		return nil
	end
	if touch then
		return spec.Touch
	end
	if mode == "Plane" then
		return string.format(spec.PC, math.floor(vto))
	end
	return spec.PC
end

local function showHint(mode: string, params: Params)
	if hintShown[mode] or not HINTS[mode] or not ensureHud() then
		return
	end
	local lab = hintLabel
	local text = Laws.HintText(mode, isTouch, params.Vto)
	if not lab or not text then
		return
	end
	hintShown[mode] = true
	lab.Text = text
	lab.Visible = true
	hintToken += 1
	local token = hintToken
	task.delay(8, function()
		if hintToken == token and hintLabel then
			hintLabel.Visible = false
		end
	end)
end

-- ── input actions (aircraft only) ───────────────────────────────────────────
local function onLiftAction(_name: string, state: Enum.UserInputState, io: InputObject): Enum.ContextActionResult?
	local down = state == Enum.UserInputState.Begin or state == Enum.UserInputState.Change
	local kc = io.KeyCode
	if kc == Enum.KeyCode.ButtonR2 then
		analog.R2 = if down then math.clamp(io.Position.Z, 0, 1) else 0
	elseif kc == Enum.KeyCode.ButtonL2 then
		analog.L2 = if down then math.clamp(io.Position.Z, 0, 1) else 0
	else
		keyDown[kc] = down
	end
	return Enum.ContextActionResult.Sink
end

--[[ F = leave the aircraft. Setting Humanoid.Jump from an input callback is NOT enough: the PlayerModule
	ControlModule rewrites Humanoid.Jump every render step (RenderPriority.Input) from its own jump keys, and
	Space is sunk by the lift action, so it writes false before the physics step. ChangeState(Jumping) leaves
	the seat directly, and a render-step binding just after the ControlModule re-asserts Jump for a few frames. ]]
local EXIT_STEP = "WE_VehExitJump"
local exitFramesLeft = 0

local function requestExit(hum: Humanoid)
	hum.Jump = true
	pcall(function()
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
	end)
	exitFramesLeft = 4
	pcall(function()
		RunService:UnbindFromRenderStep(EXIT_STEP)
	end)
	pcall(function()
		RunService:BindToRenderStep(EXIT_STEP, Enum.RenderPriority.Input.Value + 1, function()
			exitFramesLeft -= 1
			if exitFramesLeft >= 0 and hum.Parent ~= nil and hum.SeatPart ~= nil then
				hum.Jump = true
			else
				pcall(function()
					RunService:UnbindFromRenderStep(EXIT_STEP)
				end)
			end
		end)
	end)
end

local function onExitAction(_name: string, state: Enum.UserInputState, _io: InputObject): Enum.ContextActionResult?
	if state == Enum.UserInputState.Begin then
		local d = active
		if d then
			requestExit(d.Humanoid)
		end
	end
	return Enum.ContextActionResult.Sink
end

local function unbindActions()
	for _, name in ipairs({ ACTION_UP, ACTION_DOWN, ACTION_STRAFE, ACTION_EXIT }) do
		pcall(function()
			ContextActionService:UnbindAction(name)
		end)
	end
	table.clear(keyDown)
	analog.R2 = 0
	analog.L2 = 0
end

local function bindAircraftActions(mode: string)
	unbindActions()
	local hi = Enum.ContextActionPriority.High.Value
	ContextActionService:BindActionAtPriority(ACTION_UP, onLiftAction, false, hi, Enum.KeyCode.Space, Enum.KeyCode.ButtonR2)
	ContextActionService:BindActionAtPriority(
		ACTION_DOWN,
		onLiftAction,
		false,
		hi,
		Enum.KeyCode.LeftControl,
		Enum.KeyCode.C,
		Enum.KeyCode.ButtonL2
	)
	if mode == "Heli" then
		ContextActionService:BindActionAtPriority(
			ACTION_STRAFE,
			onLiftAction,
			false,
			hi,
			Enum.KeyCode.Z,
			Enum.KeyCode.X,
			Enum.KeyCode.ButtonL1,
			Enum.KeyCode.ButtonR1
		)
	end
	ContextActionService:BindActionAtPriority(ACTION_EXIT, onExitAction, false, hi, Enum.KeyCode.F)
end

local function readRaw(d: Drive): RawInput
	return {
		Throttle = d.Seat.ThrottleFloat,
		Steer = d.Seat.SteerFloat,
		Up = keyDown[Enum.KeyCode.Space] == true,
		Down = keyDown[Enum.KeyCode.LeftControl] == true or keyDown[Enum.KeyCode.C] == true,
		TouchUp = touchUp,
		TouchDown = touchDown,
		R2 = analog.R2,
		L2 = analog.L2,
		Left = keyDown[Enum.KeyCode.Z] == true or keyDown[Enum.KeyCode.ButtonL1] == true,
		Right = keyDown[Enum.KeyCode.X] == true or keyDown[Enum.KeyCode.ButtonR1] == true,
	}
end

-- ── the drive loop ──────────────────────────────────────────────────────────
local function locateMovers(d: Drive)
	local lv = d.Chassis:FindFirstChild("WE_DriveLV")
	local ao = d.Chassis:FindFirstChild("WE_DriveAO")
	d.LV = if lv and lv:IsA("LinearVelocity") then lv else nil
	d.AO = if ao and ao:IsA("AlignOrientation") then ao else nil
end

local function buildSense(d: Drive): Sense
	local cf = d.Chassis.CFrame
	local pos = cf.Position
	local look = cf.LookVector
	local sense: Sense = {
		Position = pos,
		Velocity = d.Chassis.AssemblyLinearVelocity,
		Yaw = math.atan2(-look.X, -look.Z),
		UpY = cf.UpVector.Y,
		-- only aircraft use AGL (cars and boats skip the long ray)
		AGL = if d.Mode == "Heli" or d.Mode == "Plane" then groundAGL(pos, d.Params.Clearance) else math.huge,
		Time = os.clock(),
		Look = look,
	}
	if d.Mode == "Boat" then
		sense.WaterY = Laws.WaterSurfaceAt(waterParts, pos, 0, landProbe)
	end
	return sense
end

local function applyOut(d: Drive, out: Out)
	local lv, ao = d.LV, d.AO
	if not (lv and ao) then
		return
	end
	lv.VectorVelocity = out.Velocity
	local cur = lv.MaxAxesForce
	local F = cur.X
	local wantY = if out.HoldVertical then F else 0
	if cur.Y ~= wantY or cur.Z ~= F then
		lv.MaxAxesForce = Vector3.new(F, wantY, F)
	end
	ao.CFrame = out.Orientation
end

local stopDrive: () -> ()

local function sendHello(d: Drive)
	d.HelloSent += 1
	d.LastHelloAt = os.clock()
	sendDriveInput({ K = "Hello", V = d.VehicleId, P = PROTOCOL_VERSION })
end

local function updateHud(d: Drive, dt: number, hud: Hud?)
	d.HudAcc += dt
	if d.HudAcc < 0.1 then
		return
	end
	d.HudAcc = 0
	local p = pill
	if not p then
		return
	end
	local v = d.Chassis.AssemblyLinearVelocity
	local fallback = if d.Mode == "Heli" or d.Mode == "Plane" then v.Magnitude else Vector3.new(v.X, 0, v.Z).Magnitude
	p.Text = hudText(d.Mode, hud, fallback, d.Blocked)
	p.Visible = true
end

local function stepDrive(d: Drive, dt: number)
	if active ~= d then
		return
	end
	local hum = d.Humanoid
	if not d.Model.Parent or hum.SeatPart ~= d.Seat or hum.Health <= 0 then
		stopDrive()
		return
	end
	dt = math.clamp(dt, 0, 0.1)
	if d.Blocked then
		updateHud(d, dt, nil)
		return
	end
	local now = os.clock()
	if (not d.LV or not d.AO or not (d.LV :: LinearVelocity).Parent) and now - d.LastMoverLookAt > 0.5 then
		d.LastMoverLookAt = now
		locateMovers(d)
	end
	local auth = d.Model:GetAttribute("WE_DriveAuthority")
	if auth ~= "Client" or not d.LV or not d.AO then
		d.WasClient = false
		if d.HelloSent < HELLO_MAX and now - d.LastHelloAt >= HELLO_RETRY_SECONDS then
			sendHello(d)
		end
		updateHud(d, dt, nil)
		return
	end
	local sense = buildSense(d)
	local st = d.State
	if not d.WasClient or st == nil then
		st = Laws.NewState(d.Params, sense)
		d.State = st
		d.WasClient = true
	end
	local state = st :: State
	local input = Laws.ComposeInput(d.Mode, readRaw(d))
	if d.Mode == "Boat" then
		local dir, near, far = Laws.ProbeDistances(state, d.Params, input)
		local f = fwd(state.Heading) * dir
		sense.WaterNear = Laws.WaterSurfaceAt(waterParts, sense.Position + f * near, 0, landProbe) ~= nil
		sense.WaterFar = Laws.WaterSurfaceAt(waterParts, sense.Position + f * far, 0, landProbe) ~= nil
	end
	local out = Laws.Step(state, d.Params, input, sense, dt)
	applyOut(d, out)
	updateHud(d, dt, out.Hud)
end

stopDrive = function()
	local d = active
	if not d then
		return
	end
	active = nil
	for _, c in ipairs(d.Conns) do
		c:Disconnect()
	end
	unbindActions()
	hideControls()
	if pill then
		pill.Visible = false
	end
	if hintLabel then
		hintLabel.Visible = false
	end
	pcall(function()
		localPlayer():SetAttribute("WE_DriveMode", nil)
	end)
	if not d.Blocked then
		sendDriveInput({ K = "Bye", V = d.VehicleId })
	end
	refreshAllPrompts()
end

local function startDrive(hum: Humanoid, seat: VehicleSeat)
	local cur = active
	if cur and cur.Seat == seat and cur.Humanoid == hum then
		return
	end
	if cur then
		stopDrive()
	end
	local model = vehicleModelOf(seat)
	if not model then
		return
	end
	if model:GetAttribute("OwnerUserId") ~= localPlayer().UserId then
		return -- the server ejects non-owners from the driver seat
	end
	local modeAttr = model:GetAttribute("WE_DriveMode")
	if typeof(modeAttr) ~= "string" or not VALID_MODES[modeAttr] then
		return -- pre-v70 server: its own drive loop handles the seat
	end
	local mode: string = modeAttr
	local chassis = model.PrimaryPart or model:FindFirstChild("Chassis")
	if not (chassis and chassis:IsA("BasePart")) then
		return
	end
	local vid = model:GetAttribute("VehicleId")
	local d: Drive = {
		Model = model,
		Seat = seat,
		Chassis = chassis,
		Humanoid = hum,
		Mode = mode,
		VehicleId = if typeof(vid) == "string" then vid else "",
		Params = Laws.BuildParams(mode, model:GetAttributes(), driveCfg),
		State = nil,
		LV = nil,
		AO = nil,
		WasClient = false,
		HelloSent = 0,
		LastHelloAt = 0,
		LastMoverLookAt = 0,
		HudAcc = 1,
		Blocked = nil,
		Conns = {},
	}
	local proto = model:GetAttribute("WE_ProtocolVersion")
	if typeof(proto) == "number" and proto ~= PROTOCOL_VERSION then
		d.Blocked = "Rejoin to update"
	end
	locateMovers(d)
	active = d
	pcall(function()
		localPlayer():SetAttribute("WE_DriveMode", mode)
	end)
	ensureHud()
	refreshRayFilter()
	if not d.Blocked then
		if mode == "Heli" or mode == "Plane" then
			bindAircraftActions(mode)
			if isTouch then
				showControls()
			end
			showHint(mode, d.Params)
		end
		sendHello(d)
		table.insert(
			d.Conns,
			model.AttributeChanged:Connect(function(attr: string)
				if attr ~= "WE_DriveAuthority" and attr ~= "WE_DriverUserId" and string.sub(attr, 1, 3) == "WE_" then
					d.Params = Laws.BuildParams(d.Mode, model:GetAttributes(), driveCfg)
				end
			end)
		)
	end
	table.insert(
		d.Conns,
		RunService.Heartbeat:Connect(function(dt: number)
			stepDrive(d, dt)
		end)
	)
	refreshAllPrompts()
end

local function checkSeat(hum: Humanoid)
	local sp = hum.SeatPart
	if sp and sp:IsA("VehicleSeat") and sp.Name == "DriverSeat" then
		startDrive(hum, sp)
	end
end

local function bindCharacter(char: Model)
	local h = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 10)
	if not (h and h:IsA("Humanoid")) then
		return
	end
	local hum: Humanoid = h
	hum.Seated:Connect(function(isSeated: boolean, seatPart: BasePart?)
		if isSeated and seatPart and seatPart:IsA("VehicleSeat") and seatPart.Name == "DriverSeat" then
			startDrive(hum, seatPart)
		else
			local d = active
			if d and d.Humanoid == hum then
				stopDrive()
			end
		end
	end)
	checkSeat(hum)
end

-- test hook: device class is read once in Init; the headless tests flip it to cover the touch layout
function VehicleDriveClient._SetTouch(value: boolean)
	isTouch = value
	if pill then
		pill.Position = UDim2.new(0.5, 0, 1, if isTouch then -236 else -64)
	end
	if hintLabel then
		hintLabel.Position = UDim2.new(0.5, 0, 1, (if isTouch then -236 else -64) - 36)
	end
end

function VehicleDriveClient.IsDriving(): boolean
	return active ~= nil
end

function VehicleDriveClient.ActiveMode(): string?
	local d = active
	return if d then d.Mode else nil
end

function VehicleDriveClient.Init()
	if initialized then
		return
	end
	initialized = true
	isTouch = UserInputService.TouchEnabled
	loadShared()
	local wcfg: any = if typeof(driveCfg) == "table" then driveCfg.Water else nil
	waterBelow = cfgNumber(wcfg, "QueryBelow") or waterBelow
	waterAbove = cfgNumber(wcfg, "QueryAbove") or waterAbove
	landProbeHeight = cfgNumber(wcfg, "LandProbeHeight") or landProbeHeight
	waterRefreshSeconds = math.max(0.5, cfgNumber(wcfg, "RefreshSeconds") or waterRefreshSeconds)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	rayParams = params

	refreshWater()
	CollectionService:GetInstanceAddedSignal(waterTag):Connect(refreshWater)
	CollectionService:GetInstanceRemovedSignal(waterTag):Connect(refreshWater)
	refreshRayFilter()

	UserInputService.TouchEnded:Connect(function(io: InputObject)
		if touchOwners[io] then
			touchOwners[io] = nil
			recomputeTouches()
		end
	end)
	UserInputService.InputEnded:Connect(function(io: InputObject)
		if io.UserInputType == Enum.UserInputType.MouseButton1 and touchOwners[io] then
			touchOwners[io] = nil
			recomputeTouches()
		end
	end)

	local plr = localPlayer()
	plr.CharacterAdded:Connect(function(char: Model)
		task.spawn(bindCharacter, char)
	end)
	plr.CharacterRemoving:Connect(function()
		stopDrive()
	end)
	if plr.Character then
		task.spawn(bindCharacter, plr.Character)
	end
	Workspace.ChildAdded:Connect(function(child: Instance)
		if child.Name == VEHICLE_FOLDER then
			hookVehicleFolder()
		end
	end)
	hookVehicleFolder()

	-- light reconcile: late Seated events, water/filter lists, the vehicles folder
	task.spawn(function()
		local acc = 0
		while true do
			task.wait(0.5)
			acc += 0.5
			if not active then
				local ch = plr.Character
				local h = ch and ch:FindFirstChildOfClass("Humanoid")
				if h then
					checkSeat(h)
				end
			end
			if acc >= waterRefreshSeconds then
				acc = 0
				refreshWater()
				refreshRayFilter()
				hookVehicleFolder()
			end
		end
	end)
end

return VehicleDriveClient
