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
	No positions or velocities are ever sent to the server. The only remote is VehicleDriveInput:
	  {K="Hello", V, P}            once per sit (+ retries) → the server hands the physics to this client
	  {K="Bye", V}                 leaving the seat
	  {K="In", V, T, S, L}         jeep fix F4b: the composed input, 2 decimals, Drive.Watchdog.StreamHz while any
	                               axis is non-zero + one zero message on release (feeds the server-driven fallback)
	  {K="Stuck", V, T, Spd, R, Src}  F4c: once per sit, throttle held 1.5 s under Client authority, speed < 1
	  {K="Exit", V}                F4d: jump button / Space (JumpRequest), the EXIT hold pill, F — the server ejects
	Every value is clamped to [-1, 1] on the server again; a client can only downgrade its own car to server driving.

	Laws (NewState / Step / ComposeInput / ControlsLayout / WaterSurfaceAt / ProbeDistances / BuildParams / AirBoxParams)
	are pure and are tested headless. The server's fallback + idle laws are a copy of the Car/Boat maths.

	JEEP-2 (roadmap W1 §2.2 item 4):
	  * air box: helicopters and planes turn back before the World v2 air box (VehicleConfig.Drive.AirBox.Box =
	    WorldConfig.Bounds.Air; the air wall has no roof) and show the device-neutral "Restricted airspace" line;
	    VehicleService's validator uses the same box, so nothing inside it is ever corrected
	  * W7: on touch the SPD pill and the hint line sit in HudLayout's top-centre stack under the capture bar; on
	    desktop / gamepad the pill takes the ammo readout's slot (bottom-right)
	  * jeep F9 / V8: while I sit in any vehicle seat, every ProximityPrompt outside WarEmpireVehicles is hushed
	    locally (MaxActivationDistance 0) and put back on the way out

	streaming2 lane C3 (acts only while Workspace.StreamingEnabled is true; with it false, as at 0a04776):
	  * F13: a hushed prompt that streams out and back in is hushed again when it shows (a local write can be lost)
	  * F16: a Humanoid that replicates after its character still binds (no 10 s give-up)
	  * F17: an aircraft's AGL ray over ground that has not streamed in uses the last hit or the desert floor

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
	Clear: boolean?, -- rollover fix: false = another player is within reach of this flipped car (no righting); nil = clear
}

-- Restricted: the air-box guard steered / capped this step (the HUD shows the "Restricted airspace" line)
export type Hud = { Speed: number, Alt: number?, Throttle: number?, Tag: string?, Restricted: boolean? }

-- Righting: flip recovery is lifting / levelling the car (applyOut sets WE_DriveAO.MaxAngularVelocity = Car.RecoverSpin)
export type Out = { Velocity: Vector3, HoldVertical: boolean, Orientation: CFrame, Hud: Hud, Righting: boolean? }

-- JEEP-2 World v2 air box for Heli / Plane (Laws.AirBoxParams; VehicleConfig.Drive.AirBox): Box edges + law tunables
export type AirBox = {
	X: number,
	ZMin: number,
	ZMax: number,
	MaxY: number,
	Band: number,
	LeadSeconds: number,
	Buffer: number,
	EdgeGain: number,
	PlaneEdgeGain: number,
	PushFrac: number,
	OutwardSpeed: number,
	SteerGain: number,
	AssistYawRate: number,
	CeilBand: number,
	CeilBuffer: number,
	CeilGain: number,
	CeilSink: number,
}

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
	AirBox: AirBox?,
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
	HopLeft: number, -- flip recovery: seconds left of the current righting (0 = none)
	RightFrom: Vector3?, -- where the righting started
	RightDown: number?, -- seconds spent lowering it (nil = still lifting / levelling)
	RightCool: number,
	RightClock: number, -- the law's own clock (sum of dt) for the per-minute cap
	RightTimes: { number },
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
	-- JEEP-2 air box guard (set every step by airGuardInput): turning back (until facing the box centre or out of the
	-- band), depth into the band 0..1, heading to the box centre, and "a plane's ▲ was capped under the ceiling"
	AirTurn: boolean,
	AirDepth: number,
	AirTarget: number,
	AirLift: boolean,
}

export type Rect = { Pos: Vector2, Size: Vector2 }
export type Layout = { Up: Rect, Down: Rect, Exit: Rect, Where: string }

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
	-- jeep fix (fix_spec §1.2). VehicleConfig.Drive.Watchdog / .Debug override these key by key.
	Watchdog = { StreamHz = 10 },
	-- Debug: nobody unless VehicleConfig.Drive.Debug names them (the on-device NO DRIVE line is config-gated)
	Debug = { UserIds = {}, All = false, NoDriveSeconds = 1.0, NoDriveSpeed = 1.0, ShowSeconds = 6 },
	-- mobile P1-7: EXIT pill + airborne jump lock (VehicleConfig.Drive.Exit overrides)
	Exit = {
		HoldSeconds = 0.5, -- the EXIT pill fires after this long held
		LockAGL = 8, -- Heli/Plane higher than this above the ground: local JumpHeight 0 (the touch jump button hides)
		UnlockAGL = 7, -- ... and back below this (hysteresis: the jump button does not flicker at 8)
		RequestGapSeconds = 0.3, -- at most one {K="Exit"} per this long
		StuckSeconds = 1.5, -- F4c: throttle held this long under Client authority at speed < StuckSpeed → one Stuck report
		StuckSpeed = 1.0,
	},
	-- mobile P1-8: client-side owner nameplate (VehicleConfig.Drive.Nameplate overrides)
	Nameplate = { MaxDistance = 36, WidthStuds = 2, HeightStuds = 0.4, HeightPx = 20, MinText = 14, MaxText = 20 },
	-- JEEP-2 air-box law tunables (VehicleConfig.Drive.AirBox overrides key by key). No Box here: without
	-- VehicleConfig.Drive.AirBox.Box (WorldConfig.Bounds.Air) there is no air box and the old SoftBound applies.
	AirBox = {
		Enabled = true,
		Band = 160,
		LeadSeconds = 1.6,
		Buffer = 30,
		EdgeGain = 0.6,
		PlaneEdgeGain = 1.5,
		PushFrac = 0.5,
		OutwardSpeed = 2,
		SteerGain = 2,
		AssistYawRate = 0.8,
		CeilBand = 100,
		CeilBuffer = 10,
		CeilGain = 1.0,
		CeilSink = 20,
		NoticeHoldSeconds = 1.5,
		Notice = "Restricted airspace — turning back",
	},
	-- W7: SPD pill / hint placement (VehicleConfig.Drive.Hud overrides)
	Hud = { PillStackOrder = 25, HintStackOrder = 26, DiagStackOrder = 27, StackWidthScale = 0.62, DesktopPillInset = 14 },
	-- streaming2 F17: an aircraft's AGL ray that hits nothing while Workspace.StreamingEnabled is on (VehicleConfig.Drive.Ground
	-- overrides key by key). FallbackY = the desert floor top (MapSetup GROUND_TOP_Y 0.5), the lowest ground on the map;
	-- LastHitRadius = how far (flat studs) from its last hit the ray may still use that hit's height.
	Ground = { FallbackY = 0.5, LastHitRadius = 16 },
	Modes = {
		Car = {
			ReverseFrac = 0.45,
			ReverseAccelFrac = 0.7,
			TurnSpeedRef = 12,
			YawResyncRad = 0.6,
			-- rollover fix: flip recovery (VehicleConfig.Drive.Modes.Car; Laws.FlipRecover)
			FlipUpY = 0.5,
			FlipSeconds = 1.5,
			RecoverSpeed = 3,
			RecoverLift = 2.5,
			RecoverLiftSpeed = 6,
			RecoverDoneUpY = 0.9,
			RecoverMaxSeconds = 2.5,
			RecoverMaxStuds = 5,
			RecoverCooldown = 4,
			RecoverMaxPerMinute = 5,
			RecoverClearRadius = 4,
			RecoverSpin = 2.5,
			Wheeled = { Accel = 28, Brake = 60, Coast = 10, TurnRate = 2.4, MinTurnFactor = 0.35, Grip = 8, MaxLatAccel = 120 },
			Tracked = { Accel = 16, Brake = 40, Coast = 10, TurnRate = 1.5, MinTurnFactor = 0.7, Grip = 12, MaxLatAccel = 120 },
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
	{ Accel = true, Brake = true, Coast = true, TurnRate = true, MinTurnFactor = true, Grip = true, MaxLatAccel = true }

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

--[[ JEEP-2: the air box for aircraft from VehicleConfig.Drive.AirBox (Box = WorldConfig.Bounds.Air, tunables over
	DEFAULTS.AirBox key by key). nil when the section is missing, Enabled = false or the Box is malformed. ]]
function Laws.AirBoxParams(drive: any): AirBox?
	local cfg: any = if typeof(drive) == "table" then drive.AirBox else nil
	if typeof(cfg) ~= "table" or cfg.Enabled == false then
		return nil
	end
	local box: any = cfg.Box
	if typeof(box) ~= "table" then
		return nil
	end
	local x, z0, z1, top = cfgNumber(box, "X"), cfgNumber(box, "ZMin"), cfgNumber(box, "ZMax"), cfgNumber(box, "MaxY")
	if x == nil or z0 == nil or z1 == nil or top == nil or x <= 0 or z1 <= z0 or top <= 0 then
		return nil
	end
	local d: any = DEFAULTS.AirBox
	local function n(key: string): number
		return cfgNumber(cfg, key) or d[key]
	end
	return {
		X = x,
		ZMin = z0,
		ZMax = z1,
		MaxY = top,
		Band = math.max(1, n("Band")),
		LeadSeconds = math.max(0, n("LeadSeconds")),
		Buffer = math.max(0, n("Buffer")),
		EdgeGain = math.max(0.01, n("EdgeGain")),
		PlaneEdgeGain = math.max(0.01, n("PlaneEdgeGain")),
		PushFrac = math.clamp(n("PushFrac"), 0, 1),
		OutwardSpeed = math.max(0, n("OutwardSpeed")),
		SteerGain = math.max(0.01, n("SteerGain")),
		AssistYawRate = math.max(0, n("AssistYawRate")),
		CeilBand = math.max(1, n("CeilBand")),
		CeilBuffer = math.max(0, n("CeilBuffer")),
		CeilGain = math.max(0.01, n("CeilGain")),
		CeilSink = math.max(0, n("CeilSink")),
	}
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
		AirBox = if mode == "Heli" or mode == "Plane" then Laws.AirBoxParams(drive) else nil,
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
		RightFrom = nil,
		RightDown = nil,
		RightCool = 0,
		RightClock = 0,
		RightTimes = {},
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
		AirTurn = false,
		AirDepth = 0,
		AirTarget = 0,
		AirLift = false,
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

--[[ Rollover fix: flip recovery (server copy: VehicleService._FlipRecover, for server drive and empty cars). On its side
	or roof (UpY < FlipUpY) and slower than RecoverSpeed for FlipSeconds, with nobody else near (sense.Clear ~= false),
	not cooling down and under RecoverMaxPerMinute starts in the last 60 s of the law's clock: X/Z held still, lifted at
	RecoverLiftSpeed to RecoverLift studs above where it lay while WE_DriveAO levels it, then lowered at RecoverLiftSpeed
	until it touches down. Ends when down, after RecoverMaxSeconds or past RecoverMaxStuds from the start. Returns the
	mover velocity while righting, nil otherwise. Pure (tested headless). ]]
function Laws.FlipRecover(st: State, C: { [string]: number }, sense: Sense, dt: number): Vector3?
	local clock = st.RightClock + dt
	st.RightClock = clock
	st.RightCool = math.max(0, st.RightCool - dt)
	local pos = sense.Position
	if st.HopLeft > 0 then
		st.HopLeft -= dt
		local from = st.RightFrom or pos
		local down = st.RightDown
		if down == nil and sense.UpY >= C.RecoverDoneUpY then
			down = 0 -- level again: lower it onto its wheels
		end
		local landed = down ~= nil and down >= 0.1 and sense.Velocity.Y > -0.5 * C.RecoverLiftSpeed
		if landed or st.HopLeft <= 0 or (pos - from).Magnitude > C.RecoverMaxStuds then
			st.HopLeft = 0
			st.RightFrom = nil
			st.RightDown = nil
			st.FlipFor = 0
			st.RightCool = C.RecoverCooldown
			return nil
		end
		if down ~= nil then
			st.RightDown = down + dt
			return Vector3.new(0, -C.RecoverLiftSpeed, 0)
		end
		local rise = pos.Y - from.Y
		return Vector3.new(0, math.clamp((C.RecoverLift - rise) * 4, 0, C.RecoverLiftSpeed), 0)
	end
	local v = sense.Velocity
	if sense.UpY < C.FlipUpY and Vector3.new(v.X, 0, v.Z).Magnitude < C.RecoverSpeed then
		st.FlipFor += dt
	else
		st.FlipFor = 0
	end
	if st.FlipFor < C.FlipSeconds or st.RightCool > 0 or sense.Clear == false then
		return nil
	end
	local times = st.RightTimes
	while #times > 0 and clock - times[1] >= 60 do
		table.remove(times, 1)
	end
	if #times >= C.RecoverMaxPerMinute then
		st.RightCool = 60 - (clock - times[1]) -- wait for the oldest start to leave the minute
		return nil
	end
	table.insert(times, clock)
	st.FlipFor = 0
	st.HopLeft = C.RecoverMaxSeconds
	st.RightFrom = pos
	st.RightDown = nil
	return Vector3.new(0, C.RecoverLiftSpeed, 0)
end

-- 2.1 CAR (wheeled + tracked)
local function stepCar(st: State, P: Params, input: Input, sense: Sense, dt: number): Out
	local C = P.C
	local t, s = input.Throttle, input.Steer
	local Max = P.MaxSpeed
	local Rev = C.ReverseFrac * Max
	st.Speed = resync(st, C, st.Speed, sense.Velocity:Dot(fwd(st.Heading)), dt)
	if sense.UpY < C.FlipUpY then
		-- rollover fix: no traction and no steering on its side / roof (the law used to drive a flipped car along
		-- on its side at full speed, so it never stopped long enough to be righted)
		s = 0
		st.Speed = approach(st.Speed, 0, C.Brake, dt)
	else
		st.Speed = speedUpdate(st.Speed, t, Max, Rev, P.Accel, C.Brake, C.Coast, C.ReverseAccelFrac, dt)
	end
	local dir = if st.Speed < -0.5 then -1 else 1
	local spd = math.abs(st.Speed)
	local turn = s * P.TurnRate * math.clamp(spd / C.TurnSpeedRef, C.MinTurnFactor, 1)
	local latMax = C.MaxLatAccel or 0
	if latMax > 0 and spd > 1 then
		turn = math.clamp(turn, -latMax / spd, latMax / spd) -- rollover fix: speed-sensitive steering
	end
	st.Heading -= turn * dir * dt
	if math.abs(wrap(sense.Yaw - st.Heading)) > C.YawResyncRad then
		st.Heading = sense.Yaw -- a collision spun us: stop fighting it
	end
	local r = right(st.Heading)
	local lat = sense.Velocity:Dot(r) * math.exp(-C.Grip * dt)
	local vel = fwd(st.Heading) * st.Speed + r * lat
	-- rollover fix: on its side / roof and stopped → flip recovery (replaces the old 15 studs/s hop)
	local rv = Laws.FlipRecover(st, C, sense, dt)
	if rv then
		st.Speed = 0
		vel = rv
	end
	return {
		Velocity = vel,
		HoldVertical = rv ~= nil,
		Orientation = orient(0, st.Heading, 0),
		Hud = { Speed = math.abs(st.Speed), Tag = if rv then "RIGHTING" else nil },
		Righting = rv ~= nil,
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

--[[ JEEP-2 World v2 air box (Heli / Plane; P.AirBox from Laws.AirBoxParams). Pure; two halves around the mode law.
	"room" = studs from the position to a side edge, positive inside; ceiling = min(P.MaxAltitude, box.MaxY).
	airGuardInput (before the law): inside the side band while the law's own velocity heads outward (faster than
	  OutwardSpeed), a turn-back starts and the stick is steered toward the box centre until the aircraft faces it
	  (AIR_TURN_DONE) or leaves the band; an airborne plane's ▲ is capped so its climb tapers to 0 under the ceiling
	  (and noses down above it).
	airGuardOutput (after the law): per-axis outward speed cap (room - Buffer) x gain (a heli past the Buffer is pushed
	  back in; a plane only loses the outward part), climb cap / sink under and above the ceiling, a heading assist at
	  the edge, and Hud.Restricted = true while any of it acted (the "Restricted airspace" line). ]]
function Laws.AirCeiling(P: Params, box: AirBox): number
	return math.min(P.MaxAltitude, box.MaxY)
end

-- a turn-back ends when the heading is this close to the box centre (rad, ~20°)
local AIR_TURN_DONE = 0.35

-- the law's own horizontal velocity intent (last step). Not the measured velocity: the guard's own cap pushes that
-- inward, which would hide an outward intent and stop the turn-back half way.
local function horizontalIntent(st: State, P: Params): Vector3
	if P.Mode == "Plane" then
		return fwd(st.Heading) * st.Airspeed
	end
	return fwd(st.Heading) * st.Fwd + right(st.Heading) * st.Side
end

-- (no closures and no tables per frame: the guard's findings go into st.AirTurn / AirDepth / AirTarget / AirLift;
-- a new Input table is made only on the frames the guard actually overrides the stick)
local function airGuardInput(st: State, P: Params, box: AirBox, input: Input, sense: Sense): Input
	local p = sense.Position
	local v = horizontalIntent(st, P)
	local band = box.Band
	if P.Mode == "Plane" then
		band = math.max(band, box.Buffer + box.LeadSeconds * v.Magnitude) -- a fast plane needs room to turn
	end
	local ow = box.OutwardSpeed
	local rXp, rXn, rZp, rZn = box.X - p.X, p.X + box.X, box.ZMax - p.Z, p.Z - box.ZMin
	local minRoom = math.min(rXp, rXn, rZp, rZn)
	-- heading out through an edge we are within Band of
	local outward = (rXp < band and v.X > ow) or (rXn < band and -v.X > ow) or (rZp < band and v.Z > ow) or (rZn < band and -v.Z > ow)
	local target = math.atan2(p.X, p.Z - (box.ZMin + box.ZMax) / 2) -- fwd(target) points at the box centre
	local err = wrap(target - st.Heading)
	local grounded = if P.Mode == "Plane" then not st.Airborne else st.Landed
	-- start a turn-back when heading out inside the band; keep it until facing the centre (or out of the band)
	local turning = (st.AirTurn or outward) and not grounded and minRoom < band and math.abs(err) > AIR_TURN_DONE
	st.AirTurn = turning
	st.AirDepth = math.clamp((band - minRoom) / math.max(1, band - box.Buffer), 0, 1)
	st.AirTarget = target
	st.AirLift = false
	local out = input
	if turning then
		out = { Throttle = input.Throttle, Steer = -math.clamp(err * box.SteerGain, -1, 1), Lift = input.Lift, Strafe = input.Strafe }
	end
	if P.Mode == "Plane" and st.Airborne then
		local room = Laws.AirCeiling(P, box) - box.CeilBuffer - p.Y
		if room < box.CeilBand then
			-- the highest pitch that keeps Vy under the climb cap at this airspeed
			local vyCap = math.max(-box.CeilSink, room * box.CeilGain)
			local pitchCap = math.deg(math.asin(math.clamp(vyCap / math.max(st.Airspeed, 1), -1, 1)))
			local C = P.C
			local liftCap = math.clamp(
				if pitchCap >= 0 then pitchCap / math.max(1, C.MaxPitchUp) else pitchCap / math.max(1, C.MaxPitchDown),
				-1,
				1
			)
			if out.Lift > liftCap then
				st.AirLift = out.Lift - liftCap > 0.05
				out = { Throttle = out.Throttle, Steer = out.Steer, Lift = liftCap, Strafe = out.Strafe }
			end
		end
	end
	return out
end

local function airGuardOutput(st: State, P: Params, box: AirBox, sense: Sense, out: Out, dt: number)
	local p = sense.Position
	local v = out.Velocity
	local plane = P.Mode == "Plane"
	local gain = if plane then box.PlaneEdgeGain else box.EdgeGain
	local b = box.Buffer
	local grounded = if plane then not st.Airborne else st.Landed
	-- per-axis outward cap (room - Buffer) x gain: an airborne heli past the Buffer is pushed back in (negative cap,
	-- at most PushFrac x its max speed per axis: one outside the box, e.g. spawned in the live map's outer desert, is
	-- never flung), a plane or anything on the ground only loses the outward part (never below 0)
	local floor = if plane or grounded then 0 else -box.PushFrac * P.MaxSpeed
	local capXp = math.max(floor, (box.X - p.X - b) * gain)
	local capXn = math.max(floor, (p.X + box.X - b) * gain)
	local capZp = math.max(floor, (box.ZMax - p.Z - b) * gain)
	local capZn = math.max(floor, (p.Z - box.ZMin - b) * gain)
	local nx = math.max(math.min(v.X, capXp), -capXn)
	local nz = math.max(math.min(v.Z, capZp), -capZn)
	local ny = v.Y
	if not grounded then
		local top = Laws.AirCeiling(P, box) - box.CeilBuffer
		local vyCap = math.max(-box.CeilSink, (top - p.Y) * box.CeilGain)
		if ny > vyCap then
			ny = vyCap
		end
		if not plane then
			st.Vy = math.min(st.Vy, vyCap)
			local hold = st.HoldY
			if hold ~= nil and hold > top then
				st.HoldY = top
			end
		end
	end
	local capped = math.abs(nx - v.X) > 0.5 or math.abs(nz - v.Z) > 0.5 or v.Y - ny > 0.5
	if nx ~= v.X or nz ~= v.Z or ny ~= v.Y then
		out.Velocity = Vector3.new(nx, ny, nz)
		-- the guard slowed us, not a wall: no speed resync from it (a plane would stall; a heli's commanded speed would
		-- snap to the capped one, flip its intent inward and stop the turn-back half way)
		st.LagFor = 0
	end
	if st.AirTurn and box.AssistYawRate > 0 then
		local m = box.AssistYawRate * st.AirDepth * dt
		st.Heading += math.clamp(wrap(st.AirTarget - st.Heading), -m, m)
	end
	if st.AirTurn or st.AirLift or capped then
		out.Hud.Restricted = true
	end
end

--[[ One control step. Changes `st` in place; returns the mover targets (spec 2.0). ]]
function Laws.Step(st: State, P: Params, input: Input, sense: Sense, dt: number): Out
	dt = math.clamp(dt, 0, 0.1)
	st.Age += dt
	local box = if P.Mode == "Heli" or P.Mode == "Plane" then P.AirBox else nil
	if box ~= nil then
		input = airGuardInput(st, P, box, input, sense)
	end
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
	if box ~= nil then
		airGuardOutput(st, P, box, sense, out, dt)
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

--[[ Mobile ▲/▼ column + EXIT pill in pixels (spec 3.1, mobile plan P1-7). Positions are top-left corners in the
	same space as jumpPos. Every control is ≥ 44 px (50 on phones, 60 on tablets) and CONTROL_GAP (16) px from
	the others and from the Roblox jump button. The phone column tops out at H − 222 (HudConfig.Reserve.CombatTouch
	MinHeightPx), the EXIT pill sits left of the jump button (cars/boats and the "Above" column) or left of the
	column ("Left"/"Fallback"), bottom-aligned with the lowest control: never in the thumbstick zone.
	lift = false (cars/boats): no column, only the EXIT pill. ]]
local CONTROL_GAP = 16
function Laws.ControlsLayout(
	jumpPos: Vector2?,
	jumpSize: Vector2?,
	viewport: Vector2,
	reservedTopFromBottom: number?,
	lift: boolean?
): Layout
	local reserved = reservedTopFromBottom or 250
	local size = if viewport.Y < 500 then 50 else 60
	local gap = CONTROL_GAP
	local S = Vector2.new(size, size)
	local exitW = math.floor(size * 1.8 + 0.5)
	local E = Vector2.new(exitW, size)
	local column = lift ~= false
	if jumpPos and jumpSize then
		local jumpBottom = jumpPos.Y + jumpSize.Y
		-- 1) column centred above the jump button; EXIT left of the jump button
		local x = jumpPos.X + jumpSize.X / 2 - size / 2
		local downY = jumpPos.Y - gap - size
		local upY = downY - gap - size
		if upY >= viewport.Y - reserved then
			return {
				Up = { Pos = Vector2.new(x, upY), Size = S },
				Down = { Pos = Vector2.new(x, downY), Size = S },
				Exit = { Pos = Vector2.new(jumpPos.X - gap - exitW, jumpBottom - size), Size = E },
				Where = "Above",
			}
		end
		-- 2) column left of the jump button, bottom-aligned with it; EXIT left of the column
		local lx = jumpPos.X - gap - size
		local ldown = jumpBottom - size
		local ex = if column then lx - gap - exitW else jumpPos.X - gap - exitW
		return {
			Up = { Pos = Vector2.new(lx, ldown - gap - size), Size = S },
			Down = { Pos = Vector2.new(lx, ldown), Size = S },
			Exit = { Pos = Vector2.new(ex, ldown), Size = E },
			Where = "Left",
		}
	end
	-- 3) no jump button (hidden TouchGui): column right 24 / bottom 106, EXIT left of it (or in its place)
	local fx = viewport.X - 24 - size
	local fdown = viewport.Y - 106 - size
	local fex = if column then fx - gap - exitW else viewport.X - 24 - exitW
	return {
		Up = { Pos = Vector2.new(fx, fdown - gap - size), Size = S },
		Down = { Pos = Vector2.new(fx, fdown), Size = S },
		Exit = { Pos = Vector2.new(fex, fdown), Size = E },
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
	-- jeep fix F4 / F7
	InputSrc: string, -- "seat" | "stick" | "none" (where readRaw found the throttle/steer)
	LastStreamAt: number,
	StreamZeroSent: boolean,
	NoDriveFor: number, -- pushing with speed < Debug.NoDriveSpeed for this long (diagnostic line)
	StuckFor: number, -- pushing with speed < Exit.StuckSpeed for this long (Stuck report)
	MovedFor: number, -- speed ≥ 3 for this long
	StuckSent: boolean,
	DiagUntil: number,
	DiagAcc: number,
	LastExitAt: number,
	StartedAt: number,
	-- mobile P1-7
	AirLocked: boolean, -- Heli/Plane above Exit.LockAGL: the local JumpHeight is 0
	NextAirCheck: number,
	-- JEEP-2: the "Restricted airspace" line shows until this os.clock() (the guard acted within NoticeHoldSeconds)
	RestrictedUntil: number,
	-- rollover fix: flip recovery is righting (WE_DriveAO spin lowered); "nobody else near" re-checked at most 5 Hz
	Righting: boolean,
	ClearAt: number,
	ClearVal: boolean,
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

-- Copy by device (CLAUDE.md §1): key names only for PreferredInput KeyboardAndMouse (PC) or Gamepad (Pad).
local HINTS: { [string]: { PC: string, Pad: string, Touch: string } } = {
	Heli = {
		PC = "W/S fly · A/D turn · SPACE up · CTRL down · Z/X strafe · F exit",
		Pad = "Stick: fly/turn · RT up · LT down · LB/RB strafe",
		Touch = "Stick: fly/turn · ▲▼ climb/descend · hold EXIT to leave",
	},
	Plane = {
		PC = "Hold W: throttle · A/D bank · SPACE nose up (lift off at %d) · F exit",
		Pad = "Stick up: throttle · RT nose up (lift off at %d)",
		Touch = "Push stick up for throttle · ▲ to lift off · hold EXIT to leave",
	},
}
local RED_TAGS: { [string]: boolean } = { STALL = true, ["PULL UP"] = true, AGROUND = true, ["TURN BACK"] = true }
local HINT_COLOR = Color3.fromRGB(255, 210, 90)
local RESTRICTED_COLOR = Color3.fromRGB(255, 140, 120)

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
local diagLabel: TextLabel? = nil
local controlsFrame: Frame? = nil
local upBtn: TextButton? = nil
local downBtn: TextButton? = nil
local exitBtn: TextButton? = nil
local exitFill: Frame? = nil
local exitLabel: TextLabel? = nil
local layoutConns: { RBXScriptConnection } = {}
local controlsLift = true -- the ▲▼ column is shown (aircraft); false = EXIT pill only (cars/boats)

-- EXIT hold (P1-7): the touch that is holding the pill and since when
local exitIo: InputObject? = nil
local exitHoldStart = 0
local exitTapHintUntil = 0

-- airborne jump lock (P1-7): the Humanoid whose JumpHeight/JumpPower we zeroed and the values to put back
local jumpLock: { Hum: Humanoid, Height: number, Power: number }? = nil

-- F4a: the PlayerModule ControlModule (stick / WASD move vector); looked up lazily, retried every 2 s while missing
local controls: any = nil
local nextControlsTry = 0

-- device (CLAUDE.md §1: PreferredInput, not TouchEnabled, decides the copy); nil = not overridden
local deviceOverride: string? = nil

-- config sections resolved at each sit (VehicleConfig.Drive.<name> over DEFAULTS.<name>)
local W: any = DEFAULTS.Watchdog
local DBG: any = DEFAULTS.Debug
local EXIT: any = DEFAULTS.Exit
local PLATE: any = DEFAULTS.Nameplate
local AIRC: any = DEFAULTS.AirBox -- JEEP-2: Notice / NoticeHoldSeconds (the law reads Params.AirBox)
local HUDC: any = DEFAULTS.Hud -- W7: pill / hint placement
local GROUND: any = DEFAULTS.Ground -- streaming2 F17: AGL ray-miss fallback
local debugUser = false

-- W7: HudLayout (sibling module), required lazily; false = not available (headless tests) → fixed positions
local hudLayoutMod: any = nil
local stackedHud = false -- pill / hint / diag are registered in HudLayout's top-centre stack
local restrictShown = false -- the hint line currently shows the "Restricted airspace" notice

-- jeep F9 / mobile V8: prompts hushed while seated in a vehicle (prompt → its MaxActivationDistance before the hush)
type Hushed = { Range: number, Conn: RBXScriptConnection? }
local shownPrompts: { [ProximityPrompt]: boolean } = {}
local hushedPrompts: { [ProximityPrompt]: Hushed } = {}
local hushOn = false

-- streaming2 F16: the character's ChildAdded while its Humanoid has not arrived yet (streaming on only)
local humWaitConn: RBXScriptConnection? = nil

-- P1-8 owner nameplates (client-only BillboardGuis in PlayerGui, adorned to each of my vehicles' Chassis)
local plates: { [Model]: BillboardGui } = {}

local function localPlayer(): Player
	return Players.LocalPlayer
end

-- streaming2: the place's StreamingEnabled (set in default.project.json, never by a script). Every lane C3 change
-- (F13 prompt re-hush, F16 late Humanoid, F17 AGL ray miss) acts only while it is true; with it false this module
-- behaves as at 0a04776.
local function streamingOn(): boolean
	return Workspace.StreamingEnabled == true
end

-- Drive.<name> with DEFAULTS.<name> filled in, key by key, only when the types match
local function cfgSection(name: string): any
	local d: any = DEFAULTS[name]
	local c: any = if typeof(driveCfg) == "table" and typeof(driveCfg[name]) == "table" then driveCfg[name] else nil
	local out: any = {}
	for k, v in pairs(d) do
		local o = if c then c[k] else nil
		out[k] = if o ~= nil and typeof(o) == typeof(v) then o else v
	end
	return out
end

local function refreshConfig()
	W = cfgSection("Watchdog")
	DBG = cfgSection("Debug")
	EXIT = cfgSection("Exit")
	PLATE = cfgSection("Nameplate")
	AIRC = cfgSection("AirBox")
	HUDC = cfgSection("Hud")
	GROUND = cfgSection("Ground")
	local uid = localPlayer().UserId
	local ids: any = DBG.UserIds
	debugUser = DBG.All == true or (typeof(ids) == "table" and table.find(ids, uid) ~= nil)
end

--[[ "Touch" | "Gamepad" | "KeyboardAndMouse" from UserInputService.PreferredInput (TouchEnabled only when the
	property is unavailable). Decides the copy: key names are shown only for KeyboardAndMouse / Gamepad. ]]
local function preferredInput(): string
	if deviceOverride then
		return deviceOverride
	end
	local ok, name = pcall(function(): string?
		local pi: any = (UserInputService :: any).PreferredInput
		return if typeof(pi) == "EnumItem" then pi.Name else nil
	end)
	if ok and typeof(name) == "string" then
		if name == "Touch" then
			return "Touch"
		elseif string.find(name, "Gamepad", 1, true) ~= nil then
			return "Gamepad"
		end
		return "KeyboardAndMouse"
	end
	return if UserInputService.TouchEnabled then "Touch" else "KeyboardAndMouse"
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

-- streaming2 F17: where the AGL ray last hit the ground (plain numbers: the ray runs every frame, nothing is allocated)
local lastGroundX, lastGroundZ, lastGroundY = 0, 0, 0
local haveLastGround = false

--[[ streaming2 F17: the AGL when the down-ray hits nothing while Workspace.StreamingEnabled is on, i.e. the ground
	below has not streamed in (high up, under memory pressure). The ground is the last one this ray hit while the
	aircraft is still within Ground.LastHitRadius of that spot (flat distance), else Ground.FallbackY (the desert floor
	top, the lowest ground on the map). A last hit that reads Exit.LockAGL or less AND lower than the floor would read
	(the aircraft has just left a roof or cliff edge) is not trusted: the floor wins, so a miss never lands an
	aircraft in mid-air or frees its jump button there. ]]
local function missAGL(pos: Vector3, clearance: number): number
	local floorAGL = (pos.Y - GROUND.FallbackY) - clearance
	if haveLastGround then
		local dx, dz = pos.X - lastGroundX, pos.Z - lastGroundZ
		local r = GROUND.LastHitRadius
		if dx * dx + dz * dz <= r * r then
			local agl = (pos.Y - lastGroundY) - clearance
			if agl > EXIT.LockAGL or agl >= floorAGL then
				return agl
			end
		end
	end
	return floorAGL
end

local function groundAGL(pos: Vector3, clearance: number): number
	local params = rayParams
	if not params then
		return math.huge
	end
	local hit = Workspace:Raycast(pos, Vector3.new(0, -AGL_RAY, 0), params)
	if not hit then
		-- streaming off: nothing below within AGL_RAY really means nothing (0a04776)
		return if streamingOn() then missAGL(pos, clearance) else math.huge
	end
	local groundY = hit.Position.Y
	lastGroundX, lastGroundZ, lastGroundY = pos.X, pos.Z, groundY
	haveLastGround = true
	return (pos.Y - groundY) - clearance
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

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

-- P1-8: the server's old always-on-top "VehicleLabel" (280 studs, key names) is replaced by the owner-only client
-- nameplate below; any copy an older server still builds is switched off on this client.
local function suppressServerLabel(d: Instance)
	if d.Name == "VehicleLabel" and d:IsA("BillboardGui") and d.Enabled then
		d.Enabled = false
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
		elseif d.Name == "VehicleLabel" then
			suppressServerLabel(d)
		end
	end
end

--[[ jeep F9 / mobile V8: while I sit in any seat of a vehicle (driver or passenger), every ProximityPrompt OUTSIDE
	WarEmpireVehicles (garage pad "Garage", console BUY / panel prompts, ATM, terminals, gate repair, ...) is hushed on
	this client and put back when I get up — no tap target next to the thumbstick, no stray E while driving over a pad.
	Hushing sets the prompt's MaxActivationDistance to 0 LOCALLY and restores the saved range: Enabled stays untouched
	because other code owns it (the server toggles gate-repair prompts, PromptController the owner-only ones,
	WorldPromptController its own), and a restore of Enabled could undo their decision; the range is only written at
	creation (a server re-write while hushed is remembered for the restore). Event-driven: prompts are found through
	ProximityPromptService.PromptShown / PromptHidden (no workspace scan); the vehicle's own prompts stay. ]]
local function seatIsVehicle(seat: Instance?): boolean
	return seat ~= nil and (seat:IsA("Seat") or seat:IsA("VehicleSeat")) and vehicleModelOf(seat) ~= nil
end

local function isVehiclePrompt(prompt: Instance): boolean
	local folder = Workspace:FindFirstChild(VEHICLE_FOLDER)
	return folder ~= nil and prompt:IsDescendantOf(folder)
end

local function hushPrompt(prompt: ProximityPrompt)
	if hushedPrompts[prompt] ~= nil or isVehiclePrompt(prompt) then
		return
	end
	local range = prompt.MaxActivationDistance
	if typeof(range) ~= "number" or range <= 0 then
		return
	end
	local rec: Hushed = { Range = range, Conn = nil }
	hushedPrompts[prompt] = rec
	prompt.MaxActivationDistance = 0
	pcall(function()
		rec.Conn = prompt:GetPropertyChangedSignal("MaxActivationDistance"):Connect(function()
			local r = prompt.MaxActivationDistance
			if hushedPrompts[prompt] == rec and typeof(r) == "number" and r > 0 then
				rec.Range = r -- someone re-set the range while I sit: keep it for the restore, stay hushed
				prompt.MaxActivationDistance = 0
			end
		end)
	end)
end

local function restorePrompts()
	for prompt, rec in pairs(hushedPrompts) do
		hushedPrompts[prompt] = nil
		local c = rec.Conn
		if c then
			c:Disconnect()
		end
		pcall(function()
			if prompt.MaxActivationDistance == 0 then
				prompt.MaxActivationDistance = rec.Range
			end
		end)
	end
end

--[[ Is a shown prompt gone from the world? streaming2 F13: with streaming on, what streams out is the prompt's PART
	(parented to nil, not destroyed), so the prompt keeps its Parent: only IsDescendantOf(Workspace) tells. A gone
	prompt is forgotten, not hushed: a local write on it can be lost when it streams back in, and PromptShown hushes it
	then. Streaming off: the 0a04776 test. ]]
local function promptGone(prompt: ProximityPrompt): boolean
	if streamingOn() then
		return not prompt:IsDescendantOf(Workspace)
	end
	return prompt.Parent == nil
end

local function setPromptHush(on: boolean)
	if on == hushOn then
		return
	end
	hushOn = on
	if on then
		for prompt in pairs(shownPrompts) do
			if promptGone(prompt) then
				shownPrompts[prompt] = nil
			else
				hushPrompt(prompt)
			end
		end
	else
		restorePrompts()
	end
end

local function syncPromptHush()
	local ch = localPlayer().Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	setPromptHush(hum ~= nil and hum.Health > 0 and seatIsVehicle(hum.SeatPart))
end

local function onPromptShown(prompt: ProximityPrompt)
	shownPrompts[prompt] = true
	if not hushOn then
		return
	end
	local rec = hushedPrompts[prompt]
	if rec ~= nil and streamingOn() then
		--[[ streaming2 F13: a hushed prompt that streamed out and back in can come back with the server's range (local
			writes "can be lost", maybe with no changed signal): it is showing again, so hush it again and keep that
			range for the restore. ]]
		local r = prompt.MaxActivationDistance
		if typeof(r) == "number" and r > 0 then
			rec.Range = r
			prompt.MaxActivationDistance = 0
		end
		return
	end
	hushPrompt(prompt)
end

local function onPromptHidden(prompt: ProximityPrompt)
	shownPrompts[prompt] = nil
end

-- ── P1-8 owner nameplate: small, owner-only, stud-scaled, 14–20 px text, MaxDistance ≤ 40, never AlwaysOnTop,
-- hidden while seated. Client-only BillboardGui in PlayerGui (Adornee = Chassis), so streaming a vehicle out
-- only blanks it and no server instance or remote is involved. No key names: it shows the vehicle's name only.
local function removePlate(model: Model)
	local g = plates[model]
	if g then
		plates[model] = nil
		g:Destroy()
	end
end

local function seatedNow(): boolean
	if active ~= nil then
		return true
	end
	local ch = localPlayer().Character
	local h = ch and ch:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.SeatPart ~= nil
end

local function plateHeight(model: Model, chassis: BasePart): number
	-- the kit's own label height above the Chassis centre (VehicleService sets WE_LabelY); else the model's top
	local ly = model:GetAttribute("WE_LabelY")
	if typeof(ly) == "number" and ly == ly and ly > 0 then
		return math.min(ly, 30)
	end
	local ok, top = pcall(function(): number
		local cf, size = model:GetBoundingBox()
		return cf.Position.Y + size.Y / 2
	end)
	if ok and typeof(top) == "number" and top == top then
		return math.clamp(top - chassis.Position.Y + 1.2, 1.5, 30)
	end
	return chassis.Size.Y / 2 + 3
end

local function makePlate(model: Model, chassis: BasePart, parent: Instance): BillboardGui
	local text = model.Name
	local g = Instance.new("BillboardGui")
	g.Name = "WE_VehicleNameplate"
	g.Adornee = chassis
	g.AlwaysOnTop = false
	g.LightInfluence = 0
	g.ResetOnSpawn = false
	g.MaxDistance = math.min(40, PLATE.MaxDistance)
	-- width: a fixed px part sized to the name + a small stud part; height: 20 px + 0.4 studs (≈ 23–32 px box)
	local widthPx = math.clamp(#text * 9 + 20, 80, 240)
	g.Size = UDim2.new(PLATE.WidthStuds, widthPx, PLATE.HeightStuds, PLATE.HeightPx)
	g.StudsOffsetWorldSpace = Vector3.new(0, plateHeight(model, chassis), 0)
	local lab = Instance.new("TextLabel")
	lab.Name = "Label"
	lab.Size = UDim2.fromScale(1, 1)
	lab.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
	lab.BackgroundTransparency = 0.35
	lab.BorderSizePixel = 0
	lab.Font = Enum.Font.GothamBold
	lab.TextColor3 = Color3.fromRGB(240, 242, 246)
	lab.TextScaled = true
	lab.Text = text
	lab.Parent = g
	local tc = Instance.new("UITextSizeConstraint")
	tc.MinTextSize = PLATE.MinText
	tc.MaxTextSize = PLATE.MaxText
	tc.Parent = lab
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 6)
	pad.Parent = lab
	corner(lab, 6)
	g.Parent = parent
	return g
end

local function refreshPlate(inst: Instance)
	if not inst:IsA("Model") then
		return
	end
	local model: Model = inst
	local folder = model.Parent
	local chassis = model.PrimaryPart or model:FindFirstChild("Chassis")
	local mine = model:GetAttribute("OwnerUserId") == localPlayer().UserId and model:GetAttribute("VehicleId") ~= nil
	if not mine or folder == nil or folder.Name ~= VEHICLE_FOLDER or not (chassis and chassis:IsA("BasePart")) then
		removePlate(model)
		return
	end
	local gui = plates[model]
	if not gui or gui.Parent == nil or gui.Adornee ~= chassis then
		removePlate(model)
		local pg = localPlayer():FindFirstChildOfClass("PlayerGui")
		if not pg then
			return
		end
		local made = makePlate(model, chassis, pg)
		plates[model] = made
		gui = made
	end
	if not gui then
		return
	end
	local want = not seatedNow()
	if gui.Enabled ~= want then
		gui.Enabled = want
	end
end

local function refreshPlates()
	for model in pairs(plates) do
		if model.Parent == nil then
			removePlate(model)
		end
	end
	local folder = Workspace:FindFirstChild(VEHICLE_FOLDER)
	if folder then
		for _, m in ipairs(folder:GetChildren()) do
			refreshPlate(m)
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
		elseif d.Name == "VehicleLabel" then
			suppressServerLabel(d)
		elseif d.Parent == folder then
			task.defer(refreshPlate, d) -- attributes + chassis arrive with the model; defer past its children
		elseif d.Name == "Chassis" and d.Parent and d.Parent.Parent == folder then
			task.defer(refreshPlate, d.Parent) -- streamed in after its model
		end
	end)
	folder.ChildRemoved:Connect(function(child: Instance)
		if child:IsA("Model") then
			removePlate(child)
		end
	end)
	refreshAllPrompts()
	refreshPlates()
end

-- ── HUD ─────────────────────────────────────────────────────────────────────
local function setExitProgress(p: number)
	local f = exitFill
	if f then
		f.Size = UDim2.fromScale(math.clamp(p, 0, 1), 1)
		f.Visible = p > 0
	end
end

local function cancelExitHold()
	exitIo = nil
	setExitProgress(0)
end

local function releaseTouches()
	table.clear(touchOwners)
	touchUp, touchDown = false, false
	for _, b in ipairs({ upBtn, downBtn }) do
		if b then
			b.BackgroundTransparency = 0.3
		end
	end
	cancelExitHold()
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

-- a finger lifted before Exit.HoldSeconds: the pill says HOLD for a moment instead of exiting
local function exitReleasedEarly(io: InputObject)
	if exitIo == io then
		cancelExitHold()
		exitTapHintUntil = os.clock() + 1.2
	end
end

--[[ P1-7 EXIT pill: hold Exit.HoldSeconds (0.5 s) to leave the vehicle. The same pill in every vehicle, so an
	airborne exit is never one stray tap, and phone players always have a labelled way out. ]]
local function makeExitButton(parent: Instance): TextButton
	local b = Instance.new("TextButton")
	b.Name = "Exit"
	b.Text = ""
	b.BackgroundColor3 = Color3.fromRGB(120, 28, 24)
	b.BackgroundTransparency = 0.2
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Active = true
	b.ClipsDescendants = true
	b.Size = UDim2.fromOffset(90, 50)
	b.Parent = parent
	corner(b, 12)
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(255, 200, 190)
	st.Thickness = 1.5
	st.Transparency = 0.25
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = b
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Color3.fromRGB(255, 120, 100)
	fill.BackgroundTransparency = 0.35
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Visible = false
	fill.ZIndex = 2
	fill.Parent = b
	exitFill = fill
	local lab = Instance.new("TextLabel")
	lab.Name = "Label"
	lab.BackgroundTransparency = 1
	lab.Size = UDim2.fromScale(1, 1)
	lab.Font = Enum.Font.GothamBold
	lab.TextSize = 18
	lab.TextColor3 = Color3.fromRGB(255, 244, 240)
	lab.Text = "EXIT"
	lab.ZIndex = 3
	lab.Parent = b
	exitLabel = lab
	b.InputBegan:Connect(function(io: InputObject)
		local ut = io.UserInputType
		if (ut == Enum.UserInputType.Touch or ut == Enum.UserInputType.MouseButton1) and exitIo == nil then
			exitIo = io
			exitHoldStart = os.clock()
			exitTapHintUntil = 0
		end
	end)
	b.InputEnded:Connect(function(io: InputObject)
		exitReleasedEarly(io)
	end)
	return b
end

-- W7: HudLayout (sibling module) or nil. Required lazily and never at require time; any failure → nil for good.
local function hudLayout(): any
	if hudLayoutMod == nil then
		local ok, m = pcall(function(): any
			local here: any = script
			local mod = here.Parent and here.Parent:FindFirstChild("HudLayout")
			if mod and mod:IsA("ModuleScript") then
				local req: any = require
				return req(mod)
			end
			return nil
		end)
		hudLayoutMod = if ok and typeof(m) == "table" and typeof(m.RegisterTopStack) == "function" then m else false
	end
	return if hudLayoutMod then hudLayoutMod else nil
end

local STACK_NAMES = { "VehiclePill", "VehicleHint", "VehicleDiag" }

--[[ W7 (mobile plan P2): where the SPD pill, the hint line and the debug diag line sit.
	Touch: HudLayout's top-centre stack right under the Progress slot (capture bar, ATM / bank raid), orders
	Drive.Hud.PillStackOrder / HintStackOrder / DiagStackOrder (25 / 26 / 27, between Progress 20 and Objective 30).
	The stack owns Position.Y and collapses hidden items, so the capture bar can never cover them on any screen.
	Desktop / gamepad: the pill takes the ammo readout's slot (bottom-right; the combat HUD hides while seated), the
	hint and diag lines stay bottom-centre. Without HudLayout (headless tests) touch keeps the old bottom column. ]]
local function placeHud()
	local p, h, dg = pill, hintLabel, diagLabel
	if not (p and h and dg) then
		return
	end
	local HL = if isTouch then hudLayout() else nil
	local widthScale = tonumber(HUDC.StackWidthScale) or 0.62
	if HL then
		if stackedHud then
			return -- already in the stack: it owns Position.Y
		end
		-- X centred here; Y is written by the stack (RegisterTopStack relayouts at once, then on Visible / size)
		p.AnchorPoint = Vector2.new(0.5, 0)
		p.Position = UDim2.new(0.5, 0, 0, 0)
		h.AnchorPoint = Vector2.new(0.5, 0)
		h.Position = UDim2.new(0.5, 0, 0, 0)
		h.Size = UDim2.new(widthScale, 0, 0, 26)
		dg.AnchorPoint = Vector2.new(0.5, 0)
		dg.Position = UDim2.new(0.5, 0, 0, 0)
		dg.Size = UDim2.new(widthScale, 0, 0, 40)
		local ok = pcall(function()
			HL.RegisterTopStack(STACK_NAMES[1], p, tonumber(HUDC.PillStackOrder) or 25, { Space = "Screen" })
			HL.RegisterTopStack(STACK_NAMES[2], h, tonumber(HUDC.HintStackOrder) or 26, { Space = "Screen" })
			HL.RegisterTopStack(STACK_NAMES[3], dg, tonumber(HUDC.DiagStackOrder) or 27, { Space = "Screen" })
		end)
		if ok then
			stackedHud = true
			return
		end
		for _, name in ipairs(STACK_NAMES) do
			pcall(HL.UnregisterTopStack, name) -- a half-registered set never stays behind
		end
	end
	if stackedHud then
		stackedHud = false
		local L = hudLayout()
		if L then
			for _, name in ipairs(STACK_NAMES) do
				pcall(L.UnregisterTopStack, name)
			end
		end
	end
	h.AnchorPoint = Vector2.new(0.5, 1)
	h.Size = UDim2.new(0.92, 0, 0, 26)
	dg.AnchorPoint = Vector2.new(0.5, 1)
	dg.Size = UDim2.new(0.94, 0, 0, 40)
	if isTouch then
		p.AnchorPoint = Vector2.new(0.5, 1)
		p.Position = UDim2.new(0.5, 0, 1, -236)
		h.Position = UDim2.new(0.5, 0, 1, -236 - 36)
		dg.Position = UDim2.new(0.5, 0, 1, -236 - 72)
	else
		local inset = tonumber(HUDC.DesktopPillInset) or 14
		p.AnchorPoint = Vector2.new(1, 1)
		p.Position = UDim2.new(1, -inset, 1, -inset)
		h.Position = UDim2.new(0.5, 0, 1, -64 - 36) -- hint / diag keep their v70 rows (bottom-centre)
		dg.Position = UDim2.new(0.5, 0, 1, -64 - 72)
	end
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

	-- positions: placeHud() below (W7)
	local p = Instance.new("TextLabel")
	p.Name = "WE_VehiclePill"
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
	h.Size = UDim2.new(0.92, 0, 0, 26)
	h.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
	h.BackgroundTransparency = 0.35
	h.BorderSizePixel = 0
	h.Font = Enum.Font.Gotham
	h.TextSize = 14 -- ≥ 14 px real (this ScreenGui has no UIScale)
	h.TextColor3 = HINT_COLOR
	h.TextWrapped = true
	h.Text = ""
	h.Visible = false
	h.Parent = screen
	corner(h, 6)
	local hc = Instance.new("UISizeConstraint")
	hc.MaxSize = Vector2.new(560, 40)
	hc.Parent = h
	hintLabel = h

	-- F7 / fix_spec §2.1: on-device "NO DRIVE" line, debug users only (Drive.Debug), never interactive
	local dg = Instance.new("TextLabel")
	dg.Name = "WE_VehicleDiag"
	dg.Size = UDim2.new(0.94, 0, 0, 40)
	dg.BackgroundColor3 = Color3.fromRGB(0x3A, 0x0E, 0x0E)
	dg.BackgroundTransparency = 0.2
	dg.BorderSizePixel = 0
	dg.Active = false
	dg.Font = Enum.Font.Code
	dg.TextSize = if isTouch then 11 else 12
	dg.TextColor3 = Color3.fromRGB(0xFF, 0xD7, 0xD0)
	dg.TextWrapped = true
	dg.RichText = false
	dg.Text = ""
	dg.Visible = false
	dg.Parent = screen
	corner(dg, 6)
	local dc = Instance.new("UISizeConstraint")
	dc.MaxSize = Vector2.new(620, 44)
	dc.Parent = dg
	diagLabel = dg

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
	exitBtn = makeExitButton(cf)

	screen.Parent = pg
	hudGui = screen
	stackedHud = false -- a rebuilt gui re-registers its new labels
	placeHud()
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
	-- while our airborne lock hides it (JumpHeight 0), keep laying out around its rect so nothing moves
	if
		jb
		and jb:IsA("GuiObject")
		and (jb.Visible or jumpLock ~= nil)
		and typeof(jb.AbsoluteSize) == "Vector2"
		and jb.AbsoluteSize.X > 0
	then
		return jb
	end
	return nil
end

local function layoutControls()
	local gui, ub, db, eb = hudGui, upBtn, downBtn, exitBtn
	if not (gui and ub and db and eb) then
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
	local L = Laws.ControlsLayout(jpos, jsize, vp, RESERVED_FROM_BOTTOM, controlsLift)
	ub.Position = UDim2.fromOffset(L.Up.Pos.X, L.Up.Pos.Y)
	ub.Size = UDim2.fromOffset(L.Up.Size.X, L.Up.Size.Y)
	db.Position = UDim2.fromOffset(L.Down.Pos.X, L.Down.Pos.Y)
	db.Size = UDim2.fromOffset(L.Down.Size.X, L.Down.Size.Y)
	eb.Position = UDim2.fromOffset(L.Exit.Pos.X, L.Exit.Pos.Y)
	eb.Size = UDim2.fromOffset(L.Exit.Size.X, L.Exit.Size.Y)
	ub.Visible = controlsLift
	db.Visible = controlsLift
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

local function showControls(lift: boolean)
	if not ensureHud() or not controlsFrame then
		return
	end
	hideControls()
	controlsLift = lift
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

--[[ Device-aware control hint (spec 3.1), or nil for modes without one. device: true / "Touch" = touch copy (no
	key names), "Gamepad" = pad buttons, false / "KeyboardAndMouse" = keys. ]]
function Laws.HintText(mode: string, device: boolean | string, vto: number): string?
	local spec = HINTS[mode]
	if not spec then
		return nil
	end
	if device == true or device == "Touch" then
		return spec.Touch
	end
	local text = if device == "Gamepad" then spec.Pad else spec.PC
	if mode == "Plane" then
		return string.format(text, math.floor(vto))
	end
	return text
end

local function showHint(mode: string, params: Params)
	if hintShown[mode] or not HINTS[mode] or not ensureHud() then
		return
	end
	local lab = hintLabel
	local text = Laws.HintText(mode, preferredInput(), params.Vto)
	if not lab or not text then
		return
	end
	hintShown[mode] = true
	lab.Text = text
	lab.TextColor3 = HINT_COLOR
	lab.Visible = true
	restrictShown = false
	hintToken += 1
	local token = hintToken
	task.delay(8, function()
		if hintToken == token and hintLabel then
			hintLabel.Visible = false
		end
	end)
end

--[[ JEEP-2: the "Restricted airspace" line (device-neutral, Drive.AirBox.Notice) in the hint slot while the air-box
	guard acts and Drive.AirBox.NoticeHoldSeconds after; it replaces the control hint (one message at a time). ]]
local function setRestrictedLine(on: boolean)
	if on == restrictShown then
		return
	end
	local lab = hintLabel
	if not lab then
		return
	end
	restrictShown = on
	hintToken += 1 -- a pending control-hint hide must not touch the notice
	if on then
		lab.Text = if typeof(AIRC.Notice) == "string" then AIRC.Notice else "Restricted airspace — turning back"
		lab.TextColor3 = RESTRICTED_COLOR
		lab.Visible = true
	else
		lab.Visible = false
		lab.TextColor3 = HINT_COLOR
	end
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

--[[ P1-7 airborne jump lock. JumpHeight (and JumpPower) 0 hides the Roblox touch jump button and stops a stray jump
	from leaving the seat mid-air; the exit paths below put the saved values back before they jump. Only values we
	zeroed are restored (a value someone else changed meanwhile is left alone). ]]
local function lockJump(hum: Humanoid)
	if jumpLock ~= nil then
		return
	end
	local okH, h = pcall(function(): any
		return hum.JumpHeight
	end)
	local okP, p = pcall(function(): any
		return hum.JumpPower
	end)
	local height: number = if okH and typeof(h) == "number" then h else 7.2
	local power: number = if okP and typeof(p) == "number" then p else 50
	jumpLock = { Hum = hum, Height = height, Power = power }
	pcall(function()
		hum.JumpHeight = 0
		hum.JumpPower = 0
	end)
end

local function unlockJump()
	local j = jumpLock
	if j == nil then
		return
	end
	jumpLock = nil
	pcall(function()
		if j.Hum.JumpHeight == 0 then
			j.Hum.JumpHeight = j.Height
		end
		if j.Hum.JumpPower == 0 then
			j.Hum.JumpPower = j.Power
		end
	end)
end

--[[ Leave the vehicle: jump back on, ask the server to eject (F4d: works even while the server owns the car's
	assembly) and jump locally (requestExit). Used by the EXIT pill and by F. ]]
local function exitVehicle(d: Drive)
	unlockJump()
	local now = os.clock()
	if not d.Blocked and now - d.LastExitAt >= EXIT.RequestGapSeconds then
		d.LastExitAt = now
		sendDriveInput({ K = "Exit", V = d.VehicleId })
	end
	requestExit(d.Humanoid)
end

local function onExitAction(_name: string, state: Enum.UserInputState, _io: InputObject): Enum.ContextActionResult?
	if state == Enum.UserInputState.Begin then
		local d = active
		if d then
			exitVehicle(d)
		end
	end
	return Enum.ContextActionResult.Sink
end

--[[ F4d: the Roblox jump button / Space / gamepad A (UserInputService.JumpRequest) also asks the server to eject,
	so jump exits even when the seated character's assembly is server-owned (Fallback / correction). Aircraft:
	never while airborne (the EXIT pill hold or F is the way out up there), and never on Space (Space = climb). ]]
local function onJumpRequest(d: Drive)
	if active ~= d or d.Blocked then
		return
	end
	local now = os.clock()
	if now - d.StartedAt < 0.3 or now - d.LastExitAt < EXIT.RequestGapSeconds then
		return
	end
	if d.Mode == "Heli" or d.Mode == "Plane" then
		if d.AirLocked then
			return
		end
		local okK, spaceDown = pcall(function(): boolean
			return UserInputService:IsKeyDown(Enum.KeyCode.Space)
		end)
		if (okK and spaceDown) or keyDown[Enum.KeyCode.Space] == true then
			return
		end
	end
	d.LastExitAt = now
	sendDriveInput({ K = "Exit", V = d.VehicleId })
end

-- per frame while driving: the EXIT pill's hold progress; fires exitVehicle at Exit.HoldSeconds
local function updateExitHold(d: Drive, now: number)
	local lab = exitLabel
	if lab then
		local want = if exitIo == nil and now < exitTapHintUntil then "HOLD" else "EXIT"
		if lab.Text ~= want then
			lab.Text = want
		end
	end
	if exitIo == nil then
		return
	end
	local hold = math.max(0.05, EXIT.HoldSeconds)
	local p = (now - exitHoldStart) / hold
	if p >= 1 then
		cancelExitHold()
		exitVehicle(d)
	else
		setExitProgress(p)
	end
end

-- P1-7: Heli/Plane more than Exit.LockAGL above the ground → JumpHeight 0 (5 Hz ray; hysteresis to UnlockAGL)
local function updateAirLock(d: Drive, now: number)
	if d.Mode ~= "Heli" and d.Mode ~= "Plane" then
		return
	end
	if now < d.NextAirCheck then
		return
	end
	d.NextAirCheck = now + 0.2
	local agl = groundAGL(d.Chassis.Position, d.Params.Clearance)
	if d.AirLocked then
		if agl <= EXIT.UnlockAGL then
			d.AirLocked = false
			unlockJump()
		end
	elseif agl > EXIT.LockAGL then
		d.AirLocked = true
		lockJump(d.Humanoid)
	end
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
	-- v70: gamepad B also exits (jump is locked while airborne, so pads need their own bail-out)
	ContextActionService:BindActionAtPriority(ACTION_EXIT, onExitAction, false, hi, Enum.KeyCode.F, Enum.KeyCode.ButtonB)
end

--[[ F4a: the PlayerModule's ControlModule (GetControls). Looked up lazily (never at require time) and retried every
	2 s while missing, so a late PlayerModule still gets picked up. ]]
local function playerControls(): any
	if controls ~= nil then
		return controls
	end
	local now = os.clock()
	if now < nextControlsTry then
		return nil
	end
	nextControlsTry = now + 2
	local ok, c = pcall(function(): any
		local ps = localPlayer():FindFirstChildOfClass("PlayerScripts")
		local pm = ps and ps:FindFirstChild("PlayerModule")
		if pm and pm:IsA("ModuleScript") then
			local req: any = require
			return req(pm):GetControls()
		end
		return nil
	end)
	controls = if ok then c else nil
	return controls
end

--[[ Seat floats first (the PlayerModule VehicleController writes them from the same stick/WASD vector); when both
	are ~0, the ControlModule's move vector directly (ThrottleFloat = -Z, SteerFloat = X), so a missed client
	Humanoid.Seated (the VehicleController never switched on) no longer means zero throttle. ]]
local function readRaw(d: Drive): RawInput
	local t, s, src = tonumber(d.Seat.ThrottleFloat) or 0, tonumber(d.Seat.SteerFloat) or 0, "seat"
	if math.abs(t) < 0.05 and math.abs(s) < 0.05 then
		local c = playerControls()
		if c then
			local ok, mv = pcall(c.GetMoveVector, c)
			if ok and typeof(mv) == "Vector3" and mv.Magnitude > 0.05 then
				t, s, src = -mv.Z, mv.X, "stick"
			end
		end
	end
	d.InputSrc = if math.abs(t) < 0.05 and math.abs(s) < 0.05 then "none" else src
	return {
		Throttle = t,
		Steer = s,
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

-- rollover fix: any other player (not riding this car) with a root part within `radius` of `pos`
local function othersNear(model: Model, pos: Vector3, radius: number): boolean
	local me = Players.LocalPlayer
	for _, plr in ipairs(Players:GetPlayers()) do
		local ch = plr.Character
		if plr ~= me and ch then
			local root = ch:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") and (root.Position - pos).Magnitude <= radius then
				local hum = ch:FindFirstChildOfClass("Humanoid")
				local seat = if hum then hum.SeatPart else nil
				local riding = seat ~= nil and seat:IsDescendantOf(model)
				if not riding and hum then
					for _, c in ipairs(model:GetChildren()) do
						if (c:IsA("Seat") or c:IsA("VehicleSeat")) and (c :: any).Occupant == hum then
							riding = true
							break
						end
					end
				end
				if not riding then
					return true
				end
			end
		end
	end
	return false
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
	elseif d.Mode == "Car" and sense.UpY < (d.Params.C.FlipUpY or 0.5) then
		-- rollover fix: a flipped car checks (5 Hz at most) that no other player is within reach before righting
		local t = sense.Time
		if t - d.ClearAt >= 0.2 then
			d.ClearAt = t
			d.ClearVal = not othersNear(d.Model, pos, math.max(d.Params.HalfLength, d.Params.HalfWidth) + (d.Params.C.RecoverClearRadius or 4))
		end
		sense.Clear = d.ClearVal
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
	local righting = out.Righting == true
	if righting ~= d.Righting then
		-- rollover fix: level the car gently while righting, then the server's normal limit (WE_Spin) again
		d.Righting = righting
		ao.MaxAngularVelocity = if righting
			then (d.Params.C.RecoverSpin or 2.5)
			else (tonumber(ao:GetAttribute("WE_Spin")) or ao.MaxAngularVelocity)
	end
end

local stopDrive: () -> ()

local function sendHello(d: Drive)
	d.HelloSent += 1
	d.LastHelloAt = os.clock()
	sendDriveInput({ K = "Hello", V = d.VehicleId, P = PROTOCOL_VERSION })
end

local function round2(x: number): number
	return math.floor(x * 100 + 0.5) / 100
end

--[[ F4b: the composed input to the server ({K="In", V, T, S, L}, 2 decimals) at Drive.Watchdog.StreamHz while any
	axis is non-zero, one zero message on release, nothing while idle, under every authority (it feeds the
	server-driven fallback). ~10 × 40 bytes/s per driver; the server rate-limits it on its own key. ]]
local function streamInput(d: Drive, input: Input, now: number)
	local hz = tonumber(W.StreamHz) or 0
	if hz <= 0 then
		return
	end
	local t, s, l = input.Throttle, input.Steer, input.Lift
	if math.abs(t) > 0.05 or math.abs(s) > 0.05 or math.abs(l) > 0.05 then
		-- 0.98: a 60 Hz Heartbeat sends on every 6th frame (10 Hz), never faster than ~10.2 Hz
		if now - d.LastStreamAt >= 0.98 / hz then
			d.LastStreamAt = now
			d.StreamZeroSent = false
			sendDriveInput({ K = "In", V = d.VehicleId, T = round2(t), S = round2(s), L = round2(l) })
		end
	elseif not d.StreamZeroSent then
		d.StreamZeroSent = true
		d.LastStreamAt = now
		sendDriveInput({ K = "In", V = d.VehicleId, T = 0, S = 0, L = 0 })
	end
end

local function receiveAge(p: BasePart): number?
	local ok, v = pcall(function(): any
		return (p :: any).ReceiveAge
	end)
	return if ok and typeof(v) == "number" then v else nil
end

local function signed(x: number): string
	return string.format("%+.2f", x)
end

-- the server's WE_Diag "k=v k=v" string → map (debug users only; F5j)
local function parseDiag(model: Model): { [string]: string }
	local out: { [string]: string } = {}
	local raw = model:GetAttribute("WE_Diag")
	if typeof(raw) == "string" then
		for k, v in string.gmatch(raw, "(%w+)=(%S+)") do
			if k and v then
				out[k] = v
			end
		end
	end
	return out
end

-- fix_spec §2.1: the two NO DRIVE lines, each value from its named source
local function diagText(d: Drive, input: Input, auth: any, spd: number): string
	local sv = parseDiag(d.Model)
	local srvIn = sv["in"]
	if srvIn then
		srvIn = string.match(srvIn, "^([^/]+)") or srvIn
	end
	local fail = d.Model:GetAttribute("WE_DriveFail")
	local lvMag = 0
	local lv = d.LV
	if lv then
		lvMag = lv.VectorVelocity.Magnitude
	end
	local age = receiveAge(d.Chassis)
	local rcv = if age == nil then "rep?" elseif age < 0.05 then "sim" else string.format("rep%.2f", age)
	return string.format(
		"NO DRIVE · auth=%s · own=%s · hello=%s · fail=%s\nin %s/%s (%s) · srvIn %s · lv %d · spd %.1f · rcv %s · pins %s · npc %s · %s",
		tostring(auth),
		sv.own or "?",
		sv.hello or "?",
		if typeof(fail) == "string" and fail ~= "" then fail else "-",
		signed(input.Throttle),
		signed(input.Steer),
		d.InputSrc,
		srvIn or "?",
		math.floor(lvMag + 0.5),
		spd,
		rcv,
		sv.pins or "?",
		sv.npc or "?",
		d.Seat.Name
	)
end

--[[ F4c + F7, every frame: is the driver pushing while the vehicle does not move?
	Every player: one {K="Stuck"} per sit after Exit.StuckSeconds under Client authority (feeds the server watchdog).
	Debug users (Drive.Debug): the WE_VehicleDiag line, up while stuck and Debug.ShowSeconds after, 4 Hz text. ]]
--[[ "The driver is asking this vehicle to move" (same idea as VehicleService's watchdog `pushing`): |throttle| > 0.5
	for cars and boats; a plane only on forward throttle (brake / ▲ at rest never move it, by design); a helicopter on
	▲, or on the stick while it is not sitting landed (a landed heli never taxis on the stick alone, by design). ]]
local function pushing(d: Drive, input: Input): boolean
	if d.Mode == "Heli" then
		local st = d.State
		return input.Lift > 0.5 or (math.abs(input.Throttle) > 0.5 and not (st ~= nil and st.Landed))
	elseif d.Mode == "Plane" then
		return input.Throttle > 0.5
	end
	return math.abs(input.Throttle) > 0.5
end

local function watchClient(d: Drive, input: Input, auth: any, dt: number, now: number)
	local v = d.Chassis.AssemblyLinearVelocity
	local air = d.Mode == "Heli" or d.Mode == "Plane"
	local spd = if air then v.Magnitude else Vector3.new(v.X, 0, v.Z).Magnitude
	-- rollover fix: on its side / roof the law has no traction by design and a righting lifts it straight up, so the
	-- stick held meanwhile is not "stuck" (a Stuck report here tripped the server watchdog → server drive)
	local push = pushing(d, input)
		and not d.Righting
		and not (d.Mode == "Car" and d.Chassis.CFrame.UpVector.Y < (d.Params.C.FlipUpY or 0.5))
	d.NoDriveFor = if push and spd < DBG.NoDriveSpeed then d.NoDriveFor + dt else 0
	d.MovedFor = if spd >= 3 then d.MovedFor + dt else 0
	-- the Stuck clock only runs under Client authority (a car stuck in server drive is the server's to report)
	d.StuckFor = if push and spd < EXIT.StuckSpeed and auth == "Client" then d.StuckFor + dt else 0
	if not d.StuckSent and d.StuckFor >= EXIT.StuckSeconds then
		d.StuckSent = true
		local age = receiveAge(d.Chassis)
		sendDriveInput({
			K = "Stuck",
			V = d.VehicleId,
			T = round2(input.Throttle),
			Spd = math.floor(spd * 10 + 0.5) / 10,
			R = if age ~= nil and age < 0.05 then "sim" else "rep",
			Src = d.InputSrc,
		})
	end
	local lab = diagLabel
	if not debugUser or not lab then
		return
	end
	if d.NoDriveFor >= DBG.NoDriveSeconds then
		d.DiagUntil = now + DBG.ShowSeconds
	end
	if d.MovedFor >= 1 then
		d.DiagUntil = 0
	end
	local show = now < d.DiagUntil
	d.DiagAcc += dt
	if show and (d.DiagAcc >= 0.25 or not lab.Visible) then
		d.DiagAcc = 0
		lab.Text = diagText(d, input, auth, spd)
	end
	if lab.Visible ~= show then
		lab.Visible = show
	end
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
	-- F6: cars and boats show the ACTUAL flat speed (a frozen car honestly reads SPD 0; the law's commanded speed
	-- saws 6-14 against a blocked chassis). Aircraft keep the law's HUD (ALT / THR / STALL).
	local shown = hud
	if d.Mode == "Car" or d.Mode == "Boat" then
		shown = { Speed = fallback, Tag = if hud then hud.Tag else nil }
	end
	p.Text = hudText(d.Mode, shown, fallback, d.Blocked)
	p.Visible = true
	setRestrictedLine(os.clock() < d.RestrictedUntil)
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
	local now = os.clock()
	updateAirLock(d, now)
	updateExitHold(d, now)
	if active ~= d then
		return -- the EXIT hold just fired and the seat is already gone
	end
	if d.Blocked then
		updateHud(d, dt, nil)
		return
	end
	if (not d.LV or not d.AO or not (d.LV :: LinearVelocity).Parent) and now - d.LastMoverLookAt > 0.5 then
		d.LastMoverLookAt = now
		locateMovers(d)
	end
	-- F4e: the input is read every frame under every authority (stream + stuck report + diagnostic)
	local input = Laws.ComposeInput(d.Mode, readRaw(d))
	streamInput(d, input, now)
	local auth = d.Model:GetAttribute("WE_DriveAuthority")
	watchClient(d, input, auth, dt, now)
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
	if d.Mode == "Boat" then
		local dir, near, far = Laws.ProbeDistances(state, d.Params, input)
		local f = fwd(state.Heading) * dir
		sense.WaterNear = Laws.WaterSurfaceAt(waterParts, sense.Position + f * near, 0, landProbe) ~= nil
		sense.WaterFar = Laws.WaterSurfaceAt(waterParts, sense.Position + f * far, 0, landProbe) ~= nil
	end
	local out = Laws.Step(state, d.Params, input, sense, dt)
	applyOut(d, out)
	if out.Hud.Restricted then
		d.RestrictedUntil = now + (tonumber(AIRC.NoticeHoldSeconds) or 1.5)
	end
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
	local ao = d.AO
	if d.Righting and ao then
		-- rollover fix: my local spin limit would outlive the sit (the server never re-sends an unchanged value)
		d.Righting = false
		ao.MaxAngularVelocity = tonumber(ao:GetAttribute("WE_Spin")) or ao.MaxAngularVelocity
	end
	unbindActions()
	hideControls()
	unlockJump()
	setRestrictedLine(false)
	if pill then
		pill.Visible = false
	end
	if hintLabel then
		hintLabel.Visible = false
	end
	if diagLabel then
		diagLabel.Visible = false
	end
	pcall(function()
		localPlayer():SetAttribute("WE_DriveMode", nil)
	end)
	if not d.Blocked then
		sendDriveInput({ K = "Bye", V = d.VehicleId })
	end
	refreshAllPrompts()
	refreshPlates()
end

-- server attributes that never change the drive law (the diagnostic ones change at 2 Hz for debug users)
local NON_PARAM_ATTRS: { [string]: boolean } = {
	WE_DriveAuthority = true,
	WE_DriverUserId = true,
	WE_Diag = true,
	WE_DriveFail = true,
	WE_GroundDrive = true,
}

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
		InputSrc = "none",
		LastStreamAt = 0,
		StreamZeroSent = true,
		NoDriveFor = 0,
		StuckFor = 0,
		MovedFor = 0,
		StuckSent = false,
		DiagUntil = 0,
		DiagAcc = 0,
		LastExitAt = 0,
		StartedAt = os.clock(),
		AirLocked = false,
		NextAirCheck = 0,
		RestrictedUntil = 0,
		Righting = false,
		ClearAt = -math.huge,
		ClearVal = true,
	}
	local proto = model:GetAttribute("WE_ProtocolVersion")
	if typeof(proto) == "number" and proto ~= PROTOCOL_VERSION then
		d.Blocked = "Rejoin to update"
	end
	refreshConfig()
	if controls == nil then
		nextControlsTry = 0
	end
	playerControls() -- F4a warm-up (never at require time)
	locateMovers(d)
	active = d
	pcall(function()
		localPlayer():SetAttribute("WE_DriveMode", mode)
	end)
	ensureHud()
	refreshRayFilter()
	local air = mode == "Heli" or mode == "Plane"
	if isTouch then
		showControls(air and not d.Blocked) -- the EXIT pill in every vehicle; ▲▼ for aircraft
	end
	if not d.Blocked then
		if air then
			bindAircraftActions(mode)
			showHint(mode, d.Params)
		end
		sendHello(d)
		table.insert(
			d.Conns,
			model.AttributeChanged:Connect(function(attr: string)
				if not NON_PARAM_ATTRS[attr] and string.sub(attr, 1, 3) == "WE_" then
					d.Params = Laws.BuildParams(d.Mode, model:GetAttributes(), driveCfg)
				end
			end)
		)
	end
	-- F4d: jump (touch button / Space / pad A) also asks the server to eject
	pcall(function()
		local jr: any = (UserInputService :: any).JumpRequest
		if jr then
			table.insert(
				d.Conns,
				jr:Connect(function()
					onJumpRequest(d)
				end)
			)
		end
	end)
	table.insert(
		d.Conns,
		RunService.Heartbeat:Connect(function(dt: number)
			stepDrive(d, dt)
		end)
	)
	refreshAllPrompts()
	refreshPlates()
end

local function checkSeat(hum: Humanoid)
	local sp = hum.SeatPart
	if sp and sp:IsA("VehicleSeat") and sp.Name == "DriverSeat" then
		startDrive(hum, sp)
	end
end

local function stopHumanoidWait()
	local c = humWaitConn
	humWaitConn = nil
	if c then
		c:Disconnect()
	end
end

local function bindHumanoid(hum: Humanoid)
	hum.Seated:Connect(function(isSeated: boolean, seatPart: BasePart?)
		if isSeated and seatPart and seatPart:IsA("VehicleSeat") and seatPart.Name == "DriverSeat" then
			startDrive(hum, seatPart)
		else
			local d = active
			if d and d.Humanoid == hum then
				stopDrive()
			end
		end
		refreshPlates() -- P1-8: nameplates hide while seated anywhere
		-- jeep F9: any vehicle seat (driver or passenger) hushes the world's prompts; getting up restores them
		setPromptHush(isSeated and seatIsVehicle(seatPart) and hum.Health > 0)
	end)
	pcall(function()
		hum.Died:Connect(function()
			setPromptHush(false)
		end)
	end)
	checkSeat(hum)
	refreshPlates()
	syncPromptHush()
end

local function bindCharacter(char: Model)
	stopHumanoidWait()
	local h: Instance? = char:FindFirstChildOfClass("Humanoid")
	if not h and streamingOn() then
		--[[ streaming2 F16: under streaming the character model is parented before its descendants have replicated,
			so its Humanoid can come later than any fixed wait. Bind whenever it arrives (the HudLayout pattern); the
			next character and CharacterRemoving stop the wait. ]]
		humWaitConn = char.ChildAdded:Connect(function(c: Instance)
			if c:IsA("Humanoid") then
				stopHumanoidWait()
				bindHumanoid(c)
			end
		end)
		return
	end
	if not h then
		h = char:WaitForChild("Humanoid", 10) -- streaming off: the character arrives whole (0a04776)
	end
	if not (h and h:IsA("Humanoid")) then
		return
	end
	local hum: Humanoid = h
	bindHumanoid(hum)
end

-- test hook: device class is read once in Init; the headless tests flip it to cover the touch layout
function VehicleDriveClient._SetTouch(value: boolean)
	isTouch = value
	deviceOverride = if value then "Touch" else nil
	placeHud()
	if diagLabel then
		diagLabel.TextSize = if isTouch then 11 else 12
	end
end

-- test hooks (headless): replace / drop the HudLayout module (false = none), and read the prompt hush state
function VehicleDriveClient._SetHudLayout(mod: any)
	if stackedHud then
		local L = hudLayout()
		stackedHud = false
		if L then
			for _, name in ipairs(STACK_NAMES) do
				pcall(L.UnregisterTopStack, name)
			end
		end
	end
	hudLayoutMod = if mod == nil then nil else mod
	placeHud()
end

function VehicleDriveClient._HushedPrompts(): { [ProximityPrompt]: number }
	local out: { [ProximityPrompt]: number } = {}
	for prompt, rec in pairs(hushedPrompts) do
		out[prompt] = rec.Range
	end
	return out
end

-- test hooks (headless): the ControlModule stand-in for F4a, and the current jump lock
function VehicleDriveClient._SetControls(c: any)
	controls = c
	nextControlsTry = 0
end

function VehicleDriveClient._JumpLocked(): boolean
	return jumpLock ~= nil
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
	-- on-screen touch controls whenever the device can touch (they agree with HudLayout's touch reserve);
	-- the COPY follows PreferredInput (preferredInput()), so a phone never sees a key name
	isTouch = UserInputService.TouchEnabled or preferredInput() == "Touch"
	loadShared()
	refreshConfig()
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
		exitReleasedEarly(io)
	end)
	UserInputService.InputEnded:Connect(function(io: InputObject)
		if io.UserInputType == Enum.UserInputType.MouseButton1 then
			if touchOwners[io] then
				touchOwners[io] = nil
				recomputeTouches()
			end
			exitReleasedEarly(io)
		end
	end)

	local plr = localPlayer()
	plr.CharacterAdded:Connect(function(char: Model)
		task.spawn(bindCharacter, char)
	end)
	plr.CharacterRemoving:Connect(function()
		stopHumanoidWait() -- streaming2 F16 (nil while streaming is off)
		stopDrive()
		setPromptHush(false)
	end)
	-- jeep F9: which prompts the engine shows (no scan); hushed at once while seated
	pcall(function()
		local pps: any = game:GetService("ProximityPromptService")
		pps.PromptShown:Connect(onPromptShown)
		pps.PromptHidden:Connect(onPromptHidden)
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
			syncPromptHush() -- a missed Seated event never leaves the world's prompts hushed (or shown) for long
			if acc >= waterRefreshSeconds then
				acc = 0
				refreshWater()
				refreshRayFilter()
				hookVehicleFolder()
				refreshPlates() -- children of the vehicles folder only (no descendant scan)
			end
		end
	end)
end

return VehicleDriveClient
