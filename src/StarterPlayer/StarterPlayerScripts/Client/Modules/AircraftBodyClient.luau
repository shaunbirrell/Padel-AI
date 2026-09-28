--!strict
--[[ air-looks (2026-09-28): store aircraft bodies, the client half (VisualAssetConfig.AirBody; server:
	Server/Modules/AirBodyRig). Purely visual and local: nothing here is replicated or sent to the server.

	  • Rotors: every Motor6D tagged WE_RotorJoint (AirBodyRig made it for a RotorParts part, its joint Y axis on the
	    rotor axis, attribute WE_RotorRps) turns by setting Motor6D.Transform to one of RotorSpin.Steps precomputed
	    CFrames (no allocation per update). One PreSimulation loop for every aircraft, at most RotorSpin.Hz updates a
	    second. A rotor turns only while its aircraft's driver seat is taken (the server's WE_DriverUserId), spins up
	    and down over SpinUpSeconds, and only the MaxAircraft nearest aircraft within MaxDistance of the camera are
	    updated (re-picked every Refresh seconds; the others hold their last angle). No tree scans: joints come
	    and go with the tag's added / removed signals (StreamingEnabled-safe: a streamed-out aircraft drops out).
	  • Chase camera: while the local player sits in any seat of a vehicle that carries WE_CamMinZoom (AirBodyRig,
	    ChaseCamera refs), Player.CameraMinZoomDistance = min(WE_CamMinZoom, CameraMaxZoomDistance), so the camera
	    stays behind a Roblox-size body instead of inside it (the body parts are CanQuery false, so Roblox's camera
	    does not pop in front of them). The player's own value comes back when they leave the seat, die or respawn.
	    Touch, keyboard and gamepad alike; no button, no text.
	    air fix2: the minimum also stays at least AirBody.ChaseCameraSpan studs under CameraMaxZoomDistance (never under
	    the player's own minimum), re-checked whenever the maximum changes while seated: another module that caps the
	    maximum (the vehicle-kit chase cap) can then never pin min = max, so pinch zoom keeps working on phones. ]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AircraftBodyClient = {}

local TAG = "WE_RotorJoint"

type Joint = {
	motor: Motor6D,
	model: Model?, -- the vehicle (the ancestor Model with a VehicleId attribute)
	rps: number,
	turns: number, -- 0..1
	speed: number, -- turns per second now
	idx: number, -- LUT index last written (0 = never)
	near: boolean, -- among the MaxAircraft nearest within MaxDistance at the last refresh
}

local cfg = {
	Enabled = true,
	Hz = 30,
	Steps = 24,
	MaxAircraft = 6,
	MaxDistance = 400,
	SpinUpSeconds = 2.5,
	Refresh = 0.5,
}
local zoomSpan = 8 -- air fix2: AirBody.ChaseCameraSpan (readConfig; the chase camera below)
local joints: { Joint } = {}
local byMotor: { [Motor6D]: Joint } = {}
local lut: { CFrame } = {}
local acc, sinceRefresh = 0, math.huge
local started = false

local function readConfig()
	local ok, VisualAssetConfig = pcall(function()
		local shared = ReplicatedStorage:FindFirstChild("Shared")
		local configs = shared and shared:FindFirstChild("Configs")
		local mod = configs and configs:FindFirstChild("VisualAssetConfig")
		return if mod and mod:IsA("ModuleScript") then require(mod) :: any else nil
	end)
	local span = ok and VisualAssetConfig and VisualAssetConfig.AirBody and VisualAssetConfig.AirBody.ChaseCameraSpan
	if typeof(span) == "number" then
		zoomSpan = math.clamp(span, 0, 40)
	end
	local rs = ok and VisualAssetConfig and VisualAssetConfig.AirBody and VisualAssetConfig.AirBody.RotorSpin
	if typeof(rs) == "table" then
		for k, v in pairs(rs) do
			if (cfg :: any)[k] ~= nil and typeof(v) == typeof((cfg :: any)[k]) then
				(cfg :: any)[k] = v
			end
		end
	end
	cfg.Hz = math.clamp(cfg.Hz, 1, 60)
	cfg.Steps = math.clamp(math.floor(cfg.Steps), 4, 360)
	cfg.MaxAircraft = math.max(0, math.floor(cfg.MaxAircraft))
	table.clear(lut)
	for i = 1, cfg.Steps do
		lut[i] = CFrame.Angles(0, (i - 1) / cfg.Steps * 2 * math.pi, 0)
	end
end

local function vehicleOf(inst: Instance): Model?
	local x = inst.Parent
	while x and x ~= Workspace do
		if x:IsA("Model") and x:GetAttribute("VehicleId") ~= nil then
			return x
		end
		x = x.Parent
	end
	return nil
end

local function addJoint(inst: Instance)
	if not inst:IsA("Motor6D") or byMotor[inst] then
		return
	end
	local rps = inst:GetAttribute("WE_RotorRps")
	local j: Joint = {
		motor = inst,
		model = vehicleOf(inst),
		rps = if typeof(rps) == "number" and rps > 0 then rps else 0,
		turns = 0,
		speed = 0,
		idx = 0,
		near = false,
	}
	byMotor[inst] = j
	table.insert(joints, j)
	sinceRefresh = math.huge -- re-pick the nearest aircraft on the next update
end

local function removeJoint(inst: Instance)
	local j = if inst:IsA("Motor6D") then byMotor[inst] else nil
	if j == nil then
		return
	end
	byMotor[inst :: Motor6D] = nil
	for i = #joints, 1, -1 do
		if joints[i] == j then
			joints[i] = joints[#joints]
			joints[#joints] = nil
			break
		end
	end
end

local function powered(m: Model?): boolean
	if m == nil or m.Parent == nil then
		return false
	end
	local u = m:GetAttribute("WE_DriverUserId")
	return typeof(u) == "number" and u ~= 0
end

-- the MaxAircraft nearest aircraft within MaxDistance of the camera (a few times a second, never per frame)
local function refresh()
	local cam = Workspace.CurrentCamera
	local at = if cam then cam.CFrame.Position else nil
	local dist: { [Model]: number } = {}
	local models: { Model } = {}
	for _, j in ipairs(joints) do
		local m = j.model
		if m and dist[m] == nil then
			local pp = m.PrimaryPart
			local d = if at and pp then (pp.Position - at).Magnitude else math.huge
			dist[m] = d
			if d <= cfg.MaxDistance then
				table.insert(models, m)
			end
		end
	end
	table.sort(models, function(a: Model, b: Model): boolean
		return dist[a] < dist[b]
	end)
	local keep: { [Model]: boolean } = {}
	for i = 1, math.min(#models, cfg.MaxAircraft) do
		keep[models[i]] = true
	end
	for _, j in ipairs(joints) do
		j.near = j.model ~= nil and keep[j.model :: Model] == true
	end
end

-- one update of every near joint: dt seconds of spin. No allocation (LUT CFrames, numbers only).
function AircraftBodyClient._Step(dt: number)
	local up = if cfg.SpinUpSeconds > 0 then dt / cfg.SpinUpSeconds else 1
	for _, j in ipairs(joints) do
		if j.near and j.rps > 0 then
			local target = if powered(j.model) then j.rps else 0
			if j.speed < target then
				j.speed = math.min(target, j.speed + j.rps * up)
			elseif j.speed > target then
				j.speed = math.max(target, j.speed - j.rps * up)
			end
			if j.speed > 0 then
				j.turns = (j.turns + j.speed * dt) % 1
				local idx = math.floor(j.turns * cfg.Steps) % cfg.Steps + 1
				if idx ~= j.idx then
					j.idx = idx
					j.motor.Transform = lut[idx]
				end
			end
		end
	end
end

local function onStep(dt: number)
	if not cfg.Enabled or #joints == 0 then
		return
	end
	sinceRefresh += dt
	if sinceRefresh >= cfg.Refresh then
		sinceRefresh = 0
		refresh()
	end
	acc += dt
	local period = 1 / cfg.Hz
	if acc < period then
		return
	end
	local step = math.min(acc, 0.25)
	acc = 0
	AircraftBodyClient._Step(step)
end

-- ── chase camera ──────────────────────────────────────────────────────────────────────────────────────────────────
local savedMin: number? = nil -- the player's own CameraMinZoomDistance while a chase zoom is applied
local wantZoom = 0 -- the seated vehicle's WE_CamMinZoom while applied
local maxConn: RBXScriptConnection? = nil -- CameraMaxZoomDistance watch while applied

-- air fix2: min(WE_CamMinZoom, max - span), never under the player's own minimum
function AircraftBodyClient._ChaseMin(want: number, own: number, maxZoom: number, span: number): number
	return math.max(own, math.min(want, maxZoom - span))
end

local function applyMin()
	local plr = Players.LocalPlayer
	if plr and savedMin ~= nil then
		local v = AircraftBodyClient._ChaseMin(wantZoom, savedMin, plr.CameraMaxZoomDistance, zoomSpan)
		if plr.CameraMinZoomDistance ~= v then
			plr.CameraMinZoomDistance = v
		end
	end
end

local function restoreZoom()
	if maxConn then
		maxConn:Disconnect()
		maxConn = nil
	end
	local plr = Players.LocalPlayer
	if savedMin ~= nil and plr then
		plr.CameraMinZoomDistance = savedMin
	end
	savedMin = nil
end

local function onSeated(isSeated: boolean, seat: Instance?)
	local plr = Players.LocalPlayer
	if plr == nil then
		return
	end
	if not isSeated or seat == nil then
		restoreZoom()
		return
	end
	local m = vehicleOf(seat)
	local zoom = if m then m:GetAttribute("WE_CamMinZoom") else nil
	if typeof(zoom) ~= "number" or zoom <= 0 then
		restoreZoom()
		return
	end
	if savedMin == nil then
		savedMin = plr.CameraMinZoomDistance
	end
	wantZoom = zoom
	if maxConn == nil then
		maxConn = plr:GetPropertyChangedSignal("CameraMaxZoomDistance"):Connect(applyMin)
	end
	applyMin()
end

local function bindHumanoid(hum: Humanoid)
	hum.Seated:Connect(onSeated)
	hum.Died:Connect(restoreZoom)
	if hum.SeatPart then
		onSeated(true, hum.SeatPart)
	end
end

local function bindCharacter(char: Model)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		bindHumanoid(hum)
		return
	end
	local conn: RBXScriptConnection? = nil
	conn = char.ChildAdded:Connect(function(c: Instance)
		if c:IsA("Humanoid") then
			if conn then
				conn:Disconnect()
			end
			bindHumanoid(c)
		end
	end)
end

function AircraftBodyClient._Joints(): { Joint }
	return joints
end

function AircraftBodyClient._Refresh()
	refresh()
end

function AircraftBodyClient._Config(): { [string]: any }
	return cfg :: any
end

function AircraftBodyClient.Init()
	if started then
		return
	end
	started = true
	readConfig()
	for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
		addJoint(inst)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(addJoint)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(removeJoint)
	RunService.PreSimulation:Connect(onStep)
	local plr = Players.LocalPlayer
	if plr then
		if plr.Character then
			bindCharacter(plr.Character)
		end
		plr.CharacterAdded:Connect(bindCharacter)
		plr.CharacterRemoving:Connect(restoreZoom)
	end
end

return AircraftBodyClient
