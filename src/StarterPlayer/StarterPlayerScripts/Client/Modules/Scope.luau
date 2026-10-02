--!strict
--[[
	claude-bud JOB 35 (2026-09-30): the sniper scope (WeaponConfig Scope = true; PremiumGunsConfig.Scope). Client only:
	it changes what this player sees, never what the server decides (the shot is the camera ray, as always).
	  * Level 0 = off, 1 = FOV Levels[1] (20), 2 = Levels[2] (12). CombatController: hold RMB / L2 = level 1 (release
	    = off); the wheel or a second SCOPE tap = level 2; a third SCOPE tap = off.
	  * A black vignette with a round hole + a thin reticle (one Frame whose huge UIStroke is the vignette; no images).
	  * Mouse sensitivity x FOV / BaseFov while scoped (restored after).
	  * Sway while moving (small, idle a little); CameraFx recoil x RecoilMult (CombatController passes RecoilMult()).
	  * Exits by itself when Scope.Start's check says so (reload, death, seat, weapon switch, holster).
	Camera writes follow CameraFx's apply / undo rule: the sway is applied after the shake (Last + 1) and undone before
	CameraFx's own undo (Camera - 2), so the camera scripts never read our offset.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Shared is replicated before any client script runs (bounded wait for StreamingEnabled rules)
local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
if not Shared then
	error("[WAR EMPIRE] Scope: no ReplicatedStorage.Shared after 60 s")
end
local PremiumGunsConfig = require(Shared.Configs.PremiumGunsConfig)

local Scope = {}

local S = PremiumGunsConfig.Scope
local STEP_SWAY = "WE_Scope_Sway"
local STEP_UNDO = "WE_Scope_Undo"
local level = 0
local savedFov: number? = nil
local savedSens: number? = nil
local gui: ScreenGui? = nil
local shouldExit: () -> boolean = function()
	return false
end
local preSway: CFrame? = nil
local t0 = os.clock()

-- the FOV for a level (0 = nil)
function Scope.FovFor(n: number): number?
	if n <= 0 then
		return nil
	end
	return S.Levels[math.min(n, #S.Levels)]
end

function Scope.Level(): number
	return level
end

function Scope.RecoilMult(): number
	return if level > 0 then S.RecoilMult else 1
end

local function overlay(): ScreenGui?
	local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if pg == nil then
		return nil
	end
	local g = Instance.new("ScreenGui")
	g.Name = "WE_Scope"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = 1 -- under the HUD (FIRE / RELOAD / SCOPE stay on top)
	local cam = Workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(844, 390)
	local d = math.floor(math.min(vp.X, vp.Y) * 0.92)
	local hole = Instance.new("Frame")
	hole.Name = "Lens"
	hole.AnchorPoint = Vector2.new(0.5, 0.5)
	hole.Position = UDim2.fromScale(0.5, 0.5)
	hole.Size = UDim2.fromOffset(d, d)
	hole.BackgroundTransparency = 1
	hole.Active = false
	hole.Parent = g
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = hole
	local st = Instance.new("UIStroke")
	st.Color = Color3.new(0, 0, 0)
	st.Thickness = math.ceil(math.max(vp.X, vp.Y)) -- the vignette: everything outside the lens is black
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = hole
	local function line(w: number, h: number)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromOffset(w, h)
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BorderSizePixel = 0
		f.Active = false
		f.Parent = hole
	end
	line(d, 2) -- the cross hairs
	line(2, d)
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(6, 6)
	dot.BackgroundColor3 = Color3.fromRGB(220, 40, 40)
	dot.BorderSizePixel = 0
	dot.Parent = hole
	local dc = Instance.new("UICorner")
	dc.CornerRadius = UDim.new(0.5, 0)
	dc.Parent = dot
	g.Parent = pg
	return g
end

local function undoStep()
	local cam = Workspace.CurrentCamera
	if preSway and cam then
		cam.CFrame = preSway
	end
	preSway = nil
end

local function swayStep()
	local cam = Workspace.CurrentCamera
	if cam == nil then
		return
	end
	if shouldExit() then
		Scope.Exit()
		return
	end
	local fov = Scope.FovFor(level)
	if fov and cam.FieldOfView ~= fov then
		cam.FieldOfView = fov
	end
	local char = Players.LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local moving = hum ~= nil and hum.MoveDirection.Magnitude > 0.1
	local amp = math.rad(if moving then S.SwayDeg else S.SwayIdleDeg)
	local t = os.clock() - t0
	preSway = cam.CFrame
	cam.CFrame = cam.CFrame * CFrame.Angles(math.sin(t * 1.7) * amp, math.cos(t * 1.1) * amp, 0)
end

-- set the zoom level (0 = off)
function Scope.Set(n: number)
	n = math.clamp(math.floor(n), 0, #S.Levels)
	if n == level then
		return
	end
	local cam = Workspace.CurrentCamera
	if n == 0 then
		level = 0
		pcall(function()
			RunService:UnbindFromRenderStep(STEP_SWAY)
			RunService:UnbindFromRenderStep(STEP_UNDO)
		end)
		undoStep()
		if cam and savedFov then
			cam.FieldOfView = savedFov
		end
		if savedSens then
			UserInputService.MouseDeltaSensitivity = savedSens
		end
		savedFov, savedSens = nil, nil
		if gui then
			gui:Destroy()
			gui = nil
		end
		return
	end
	if level == 0 then
		savedFov = if cam then cam.FieldOfView else S.BaseFov
		savedSens = UserInputService.MouseDeltaSensitivity
		gui = overlay()
		RunService:BindToRenderStep(STEP_UNDO, Enum.RenderPriority.Camera.Value - 2, undoStep)
		RunService:BindToRenderStep(STEP_SWAY, Enum.RenderPriority.Last.Value + 1, swayStep)
	end
	level = n
	local fov = Scope.FovFor(n) or S.BaseFov
	if savedSens then
		UserInputService.MouseDeltaSensitivity = savedSens * fov / S.BaseFov
	end
end

-- off -> 1 -> 2 -> off (the SCOPE button)
function Scope.Cycle()
	Scope.Set(if level >= #S.Levels then 0 else level + 1)
end

function Scope.Exit()
	Scope.Set(0)
end

-- the auto-exit check (CombatController: reload / death / seat / switch / holster / a gun without a scope)
function Scope.Start(check: () -> boolean)
	shouldExit = check
end

return Scope
