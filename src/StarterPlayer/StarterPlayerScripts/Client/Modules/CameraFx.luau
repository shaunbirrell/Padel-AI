--!strict
--[[
	CameraFx (W2 CC-3, contracts §5.2): the ONE owner of combat camera offsets. Numbers: HudConfig.CombatCamera,
	HudConfig.AimHelp. Libraries: Shared/Vendor/Spring (recoil, MIT) and Shared/Vendor/Shake (blast / hit shake, MIT).

	API
	  Init()                               idempotent
	  SetCombatMode(drawn, inputClass)     drawn = weapon out, alive, allowed to shoot from here (CombatController)
	  SetWeapon(weaponId?)                 the drawn weapon (range for the aim help)
	  Kick(weaponId)                       recoil: a Spring impulse from WeaponConfig.Recoil (touch x RecoilScaleTouch)
	  Blast(center, radius)                explosion shake, scaled by distance, within radius x Shake.MaxRadiusMult
	  HitTaken(damage)                     a small trauma pulse (Shake.HitAmplitude)
	  AimCFrame() -> CFrame                the camera CFrame WITHOUT the view-only shake (CombatController's aimRay)

	RENDER STEPS (bound only while needed; nothing runs while holstered and calm)
	  WE_CamFx_Undo  RenderPriority.Camera - 1   removes last frame's shake before the Roblox camera reads the CFrame
	  WE_CamFx_Aim   RenderPriority.Camera + 1   shoulder upkeep, aim help (friction + tracking), recoil spring delta.
	                                             Recoil / aim help ROTATE the real camera: the Roblox camera reads its
	                                             look vector back next frame, so recoil is real aim recoil that
	                                             recovers by itself (the spring returns to 0).
	  WE_CamFx_Shake RenderPriority.Last         view-only shake (never drifts the camera or the aim)

	SHOULDER (P1-3): while drawn, alive, on foot and CombatCamera.Shoulder[inputClass] (Touch only by default):
	Humanoid.CameraOffset = ShoulderOffset, AutoRotate = false, the root yaw follows the camera yaw (written only
	when it moves > 1°). All of it reverts on holster, seat, death or respawn.

	AIM HELP (touch / gamepad while drawn; never a snap): with AimTargets.Best() in the cone, the camera keeps only
	FrictionKeep of the player's own frame-to-frame turn and follows at most Tracking x the target's angular motion.

	REDUCED MOTION: GuiService.ReducedMotionEnabled (CombatCamera.RespectReducedMotion) turns off the shake and the
	recoil kick. Per frame: no Instance, table or closure is created (value types only).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60) -- ships with the place (Rojo); bounded wait anyway
local HudConfig = require(Shared.Configs.HudConfig)
local WeaponConfig = require(Shared.Configs.WeaponConfig)
local Spring = require(Shared.Vendor.Spring)
local Shake = require(Shared.Vendor.Shake)
local AimTargets = require(script.Parent.AimTargets)

local CameraFx = {}

local CC = HudConfig.CombatCamera
local SHK = CC.Shake
local STEP_UNDO = "WE_CamFx_Undo"
local STEP_AIM = "WE_CamFx_Aim"
local STEP_SHAKE = "WE_CamFx_Shake"
local YAW_EPS = math.rad(1) -- root yaw writes only when the camera yaw moved more than this
local MAX_TRACK_STEP = math.rad(4) -- one frame of tracking never turns the camera more than this
local MAX_PITCH = math.rad(80)
local SHAKE_POS = 1 -- studs per unit of Shake output
local SHAKE_ROT = Vector3.new(math.rad(8), math.rad(8), math.rad(4)) -- radians per unit of Shake output
local RECOIL_SETTLE = 0.01 -- degrees: the spring counts as settled below this

local player = Players.LocalPlayer

local initialized = false
local combatOn = false
local inputClass = "KeyboardAndMouse"
local weaponRange = 0

local function priority(name: string, delta: number): number
	local ok, v = pcall(function(): number
		return ((Enum.RenderPriority :: any)[name] :: EnumItem).Value
	end)
	if ok and type(v) == "number" then
		return v + delta
	end
	return (if name == "Camera" then 200 elseif name == "Last" then 2000 else 100) + delta
end

local PRIO_UNDO = priority("Camera", -1)
local PRIO_AIM = priority("Camera", 1)
local PRIO_SHAKE = priority("Last", 0)

-- shoulder
local shoulderHum: Humanoid? = nil
local shoulderSavedAutoRotate = true
local lastRootYaw: number? = nil

-- aim step
local aimBound = false
local lastYaw = 0
local lastPitch = 0
local lastValid = false
local trackModel: Model? = nil
local trackYaw = 0
local trackPitch = 0

-- recoil
type RecoilSpring = { Current: Vector3, Target: Vector3, Velocity: Vector3, SmoothTime: number, MaxSpeed: number }
local recoil: any = Spring.new(Vector3.zero, 0.16)
local springOk: boolean? = nil -- TweenService:SmoothDamp available (tested once)
local recoilApplied = Vector3.zero -- degrees (pitch, yaw) already applied to the camera
local recoilLive = false

-- shake
local shake = Shake.new()
shake.FadeInTime = 0
shake.SustainTime = 0.08
shake.FadeOutTime = 0.5
shake.Frequency = 0.08
shake.PositionInfluence = Vector3.one * SHAKE_POS
shake.RotationInfluence = SHAKE_ROT
local shakeBound = false
local shakeActive = false
local shakeApplied = false
local preShakeCF = CFrame.identity
local shakeAmp = 0

-- stats (tests)
local stats = { AimSteps = 0, ShakeSteps = 0, UndoSteps = 0, Kicks = 0, Blasts = 0, RootWrites = 0 }

---------------------------------------------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------------------------------------------

local function readReducedMotion(): any
	return (GuiService :: any).ReducedMotionEnabled
end

local function reducedMotion(): boolean
	if CC.RespectReducedMotion == false then
		return false
	end
	local ok, v = pcall(readReducedMotion)
	return ok and v == true
end

local function localHumanoid(): Humanoid?
	local ch = player.Character
	if not ch then
		return nil
	end
	return ch:FindFirstChildOfClass("Humanoid")
end

local function yawPitchOf(look: Vector3): (number, number)
	local y = math.clamp(look.Y, -1, 1)
	return math.atan2(-look.X, -look.Z), math.asin(y)
end

local function lookOf(yaw: number, pitch: number): Vector3
	local cp = math.cos(pitch)
	return Vector3.new(-math.sin(yaw) * cp, math.sin(pitch), -math.cos(yaw) * cp)
end

local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- TweenService:SmoothDamp is fairly new: test it once, else a hand-rolled critically damped spring (same maths)
local function probeSpring()
	local probe: any = Spring.new(Vector3.zero, 0.1)
	probe:Update(1 / 60)
	assert(typeof(probe.Current) == "Vector3")
end

local function springUpdate(dt: number): Vector3
	if springOk == nil then
		springOk = pcall(probeSpring) -- once per session
	end
	local s = recoil :: RecoilSpring
	if springOk then
		local ok = pcall(recoil.Update, recoil, dt)
		if ok and typeof(s.Current) == "Vector3" then
			return s.Current
		end
		springOk = false
	end
	-- fallback: x'' = -w^2 x - 2 w x' (critically damped, w = 2 / SmoothTime), semi-implicit Euler
	local w = 2 / math.max(0.02, s.SmoothTime)
	local x, v = s.Current - s.Target, s.Velocity
	local steps = math.clamp(math.ceil(dt / (1 / 120)), 1, 8)
	local h = dt / steps
	for _ = 1, steps do
		v += (-(w * w) * x - 2 * w * v) * h
		x += v * h
	end
	s.Current = s.Target + x
	s.Velocity = v
	return s.Current
end

---------------------------------------------------------------------------------------------------------------
-- shoulder camera (P1-3)
---------------------------------------------------------------------------------------------------------------

local function shoulderWanted(hum: Humanoid?): boolean
	if not combatOn or (CC.Shoulder :: any)[inputClass] ~= true then
		return false
	end
	return hum ~= nil and hum.Parent ~= nil and hum.Health > 0 and hum.SeatPart == nil
end

local function releaseShoulder()
	local h = shoulderHum
	shoulderHum = nil
	lastRootYaw = nil
	if h then
		pcall(function()
			h.CameraOffset = Vector3.zero
			h.AutoRotate = shoulderSavedAutoRotate
		end)
	end
end

local function syncShoulder(): Humanoid?
	local hum = localHumanoid()
	if shoulderWanted(hum) then
		local h = hum :: Humanoid
		if shoulderHum ~= h then
			releaseShoulder()
			shoulderHum = h
			shoulderSavedAutoRotate = true -- AutoRotate is always restored to the Roblox default
			h.CameraOffset = CC.ShoulderOffset
			h.AutoRotate = not (CC.FaceCameraYaw == true)
		end
		return h
	end
	if shoulderHum then
		releaseShoulder()
	end
	return nil
end

local function faceCameraYaw(hum: Humanoid, yaw: number)
	if CC.FaceCameraYaw ~= true then
		return
	end
	local ch = hum.Parent
	local root = if ch then ch:FindFirstChild("HumanoidRootPart") else nil
	if not (root and root:IsA("BasePart")) then
		return
	end
	local last = lastRootYaw
	if last == nil then
		local rl = root.CFrame.LookVector
		last = math.atan2(-rl.X, -rl.Z)
	end
	if math.abs(wrapAngle(yaw - (last :: number))) <= YAW_EPS then
		return
	end
	lastRootYaw = yaw
	root.CFrame = CFrame.Angles(0, yaw, 0) + root.Position
	stats.RootWrites += 1
end

---------------------------------------------------------------------------------------------------------------
-- WE_CamFx_Aim (Camera + 1): shoulder, aim help, recoil
---------------------------------------------------------------------------------------------------------------

local syncBindings: () -> ()

local function aimStep(dt: number)
	stats.AimSteps += 1
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local hum = syncShoulder()
	local cf = cam.CFrame
	local pos = cf.Position
	local yaw, pitch = yawPitchOf(cf.LookVector)
	local changed = false

	-- aim help: friction on the player's own turn, partial tracking of the target's motion
	if combatOn then
		local keep, tracking = AimTargets.HelpLevelFor(inputClass)
		if keep < 1 or tracking > 0 then
			local target, part = AimTargets.Best(cf, weaponRange)
			if target and part then
				if lastValid and keep < 1 then
					local dy = wrapAngle(yaw - lastYaw)
					local dp = pitch - lastPitch
					if math.abs(dy) > 1e-6 or math.abs(dp) > 1e-6 then
						yaw = lastYaw + dy * keep
						pitch = lastPitch + dp * keep
						changed = true
					end
				end
				local ty, tp = yawPitchOf((part.Position - pos).Unit)
				if trackModel == target and tracking > 0 then
					local sy = math.clamp(wrapAngle(ty - trackYaw) * tracking, -MAX_TRACK_STEP, MAX_TRACK_STEP)
					local sp = math.clamp((tp - trackPitch) * tracking, -MAX_TRACK_STEP, MAX_TRACK_STEP)
					if math.abs(sy) > 1e-6 or math.abs(sp) > 1e-6 then
						yaw += sy
						pitch += sp
						changed = true
					end
				end
				trackModel, trackYaw, trackPitch = target, ty, tp
			else
				trackModel = nil
			end
		else
			trackModel = nil
		end
	end

	-- recoil: the spring's frame-to-frame delta turns the real camera (it recovers as the spring returns to 0)
	if recoilLive then
		local v = springUpdate(dt)
		local dP, dY = v.X - recoilApplied.X, v.Y - recoilApplied.Y
		recoilApplied = v
		if math.abs(dP) > 1e-5 or math.abs(dY) > 1e-5 then
			pitch += math.rad(dP)
			yaw += math.rad(dY)
			changed = true
		end
		local s = recoil :: RecoilSpring
		if v.Magnitude < RECOIL_SETTLE and s.Velocity.Magnitude < RECOIL_SETTLE then
			recoilLive = false
			recoilApplied = Vector3.zero
			s.Current = Vector3.zero
			s.Velocity = Vector3.zero
		end
	end

	if changed then
		pitch = math.clamp(pitch, -MAX_PITCH, MAX_PITCH)
		cam.CFrame = CFrame.lookAt(pos, pos + lookOf(yaw, pitch))
	end
	lastYaw, lastPitch, lastValid = yaw, pitch, true
	if hum then
		faceCameraYaw(hum, yaw)
	end
	if not recoilLive and (not combatOn or shoulderHum == nil) then
		syncBindings() -- recoil settled / holstered: unbind unless the aim help or the shoulder still needs the step
	end
end

---------------------------------------------------------------------------------------------------------------
-- WE_CamFx_Shake (Last) / WE_CamFx_Undo (Camera - 1): view-only shake
---------------------------------------------------------------------------------------------------------------

local function undoStep()
	stats.UndoSteps += 1
	if shakeApplied then
		shakeApplied = false
		local cam = Workspace.CurrentCamera
		if cam then
			cam.CFrame = preShakeCF
		end
	end
	if not shakeActive then
		syncBindings()
	end
end

local function shakeStep()
	stats.ShakeSteps += 1
	local cam = Workspace.CurrentCamera
	if not cam or not shakeActive then
		return
	end
	local p, r, done = shake:Update()
	if done then
		shakeActive = false
		shakeAmp = 0
		return
	end
	preShakeCF = cam.CFrame
	cam.CFrame = preShakeCF * CFrame.new(p) * CFrame.Angles(r.X, r.Y, r.Z)
	shakeApplied = true
end

syncBindings = function()
	-- the aim step runs only while something needs it: recoil in flight, the shoulder camera, or aim help
	-- (touch / gamepad while drawn). A drawn PC gun with no recoil runs nothing per frame.
	local keep, tracking = AimTargets.HelpLevelFor(inputClass)
	local wantAim = recoilLive or shoulderHum ~= nil or (combatOn and (keep < 1 or tracking > 0))
	if wantAim ~= aimBound then
		aimBound = wantAim
		if wantAim then
			lastValid = false
			trackModel = nil
			RunService:BindToRenderStep(STEP_AIM, PRIO_AIM, aimStep)
		else
			RunService:UnbindFromRenderStep(STEP_AIM)
			lastValid = false
			trackModel = nil
		end
	end
	local wantShake = shakeActive or shakeApplied
	if wantShake ~= shakeBound then
		shakeBound = wantShake
		if wantShake then
			RunService:BindToRenderStep(STEP_UNDO, PRIO_UNDO, undoStep)
			RunService:BindToRenderStep(STEP_SHAKE, PRIO_SHAKE, shakeStep)
		else
			RunService:UnbindFromRenderStep(STEP_UNDO)
			RunService:UnbindFromRenderStep(STEP_SHAKE)
		end
	end
end

local function startShake(amplitude: number, sustain: number, fadeOut: number)
	if amplitude <= 0.001 or reducedMotion() then
		return
	end
	if shakeActive and shakeAmp >= amplitude then
		return -- a stronger shake is already running
	end
	shakeAmp = amplitude
	shake.Amplitude = amplitude
	shake.SustainTime = sustain
	shake.FadeOutTime = fadeOut
	shake:Start()
	shakeActive = true
	syncBindings()
end

---------------------------------------------------------------------------------------------------------------
-- public
---------------------------------------------------------------------------------------------------------------

function CameraFx.SetCombatMode(drawn: boolean, cls: string)
	local on = drawn == true
	if type(cls) == "string" and cls ~= "" then
		inputClass = cls
	end
	combatOn = on
	if on then
		syncShoulder() -- idempotent: applies / keeps / releases for the current humanoid and class
	else
		releaseShoulder()
		trackModel = nil
	end
	syncBindings()
end

function CameraFx.SetWeapon(weaponId: string?)
	local def = if weaponId then WeaponConfig.Weapons[weaponId] else nil
	weaponRange = if def then math.max(0, tonumber(def.Range) or 0) else 0
end

function CameraFx.Kick(weaponId: string)
	if reducedMotion() then
		return
	end
	local def = WeaponConfig.Weapons[weaponId]
	local rc = if def then def.Recoil else nil
	if not rc then
		return
	end
	local scale = if inputClass == "Touch" then tonumber(CC.RecoilScaleTouch) or 0.5 else 1
	local recover = math.max(1, tonumber(rc.Recover) or tonumber(CC.RecoilSpring.Speed) or 12)
	local smooth = 2 / recover -- SmoothDamp time; the peak comes at smooth / 2
	local s = recoil :: RecoilSpring
	s.SmoothTime = smooth
	-- a critically damped spring kicked with v0 peaks at v0 / (w e), w = 2 / smooth: v0 = peak x w x e
	local k = (2 / smooth) * math.exp(1)
	local side = (math.random() * 2 - 1) * (tonumber(rc.Side) or 0)
	s.Velocity += Vector3.new((tonumber(rc.Kick) or 0) * scale * k, side * scale * k, 0)
	recoilLive = true
	stats.Kicks += 1
	syncBindings()
end

function CameraFx.Blast(center: Vector3, radius: number)
	if typeof(center) ~= "Vector3" or type(radius) ~= "number" or radius <= 0 then
		return
	end
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local reach = radius * math.max(1, tonumber(SHK.MaxRadiusMult) or 3)
	local d = (cam.CFrame.Position - center).Magnitude
	if d >= reach then
		return
	end
	local base = if inputClass == "Touch" then SHK.BlastAmplitudeTouch else SHK.BlastAmplitude
	stats.Blasts += 1
	startShake(base * (1 - d / reach), 0.08, 0.5)
end

function CameraFx.HitTaken(damage: number)
	local amp = tonumber(SHK.HitAmplitude) or 0
	if inputClass == "Touch" then
		amp *= 0.5
	end
	local d = if type(damage) == "number" then damage else 0
	startShake(amp * math.clamp(d / 25, 0.5, 1.5), 0, 0.25)
end

function CameraFx.AimCFrame(): CFrame
	if shakeApplied then
		return preShakeCF
	end
	local cam = Workspace.CurrentCamera
	return if cam then cam.CFrame else CFrame.identity
end

function CameraFx.Stats(): { [string]: any }
	return {
		AimSteps = stats.AimSteps,
		ShakeSteps = stats.ShakeSteps,
		UndoSteps = stats.UndoSteps,
		Kicks = stats.Kicks,
		Blasts = stats.Blasts,
		RootWrites = stats.RootWrites,
		AimBound = aimBound,
		ShakeBound = shakeBound,
		ShakeActive = shakeActive,
		RecoilLive = recoilLive,
		SpringLib = springOk == true, -- the vendored Spring (TweenService:SmoothDamp) drives the recoil
		Shoulder = shoulderHum ~= nil,
		CombatOn = combatOn,
		InputClass = inputClass,
	}
end

function CameraFx.Init()
	if initialized then
		return
	end
	initialized = true
	AimTargets.Init()
	AimTargets.SetViewSource(CameraFx.AimCFrame)
	player.CharacterAdded:Connect(function()
		-- respawn: the new humanoid starts with the Roblox defaults; forget the old one
		shoulderHum = nil
		lastRootYaw = nil
		lastValid = false
		trackModel = nil
		syncBindings()
	end)
end

return CameraFx
