--!strict
--[[
	claude-bud PREMIUM (2026-09-29): FIRE / MISSILE for the Robux-only vehicles (VehicleConfig.Premium). Client side only:
	it sends "Fire" / "Missile" + the camera's aim to PremiumWeaponService, which decides everything (seat, ownership,
	pass, cone, range, line of sight, cooldown, damage, the missile's lock).
	  * Shown only while he DRIVES his own premium vehicle (DriverSeat, model attribute WE_PremiumGun, OwnerUserId = him);
	    a clean reset on exit (buttons, bindings, reticle, loops all go).
	  * Touch: two buttons placed by AirWeaponsClient.Layout (left of the drive column, clear of the jump button / EXIT /
	    the thumbstick zone), 64 code px (72 on tablets). FIRE is hold-to-fire at the gun's rate (capped at MaxRequestHz);
	    MISSILE shows its cooldown. Keyboard / gamepad (PreferredInput): LMB / R2 fire, R / X missile; key hints only then.
	  * Lock-on reticle: the candidate the server would lock (nearest enemy player or vehicle inside the cone, in range)
	    re-picked at 10 Hz; drawn at it every frame (one WorldToViewportPoint, no allocation). Display only.
	  * Fx from PremiumWeaponFx: tracers (G), explosions (X; visual Explosion, no pressure / no joints).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PremiumWeaponsClient = {}

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
if not Shared then
	return PremiumWeaponsClient
end
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local VehicleConfig = require(Shared.Configs.VehicleConfig)

local P: any = (VehicleConfig :: any).Premium
local lp = Players.LocalPlayer

type State = {
	Model: Model,
	Gun: any,
	Gui: ScreenGui,
	Fire: TextButton,
	Missile: TextButton,
	Reticle: Frame,
	Conns: { RBXScriptConnection },
	Holding: boolean,
	LastSend: number,
	LastMissile: number,
	Target: BasePart?,
	Alive: boolean,
}
local st: State? = nil

local function module(name: string): any?
	local inst = script.Parent:FindFirstChild(name)
	if inst and inst:IsA("ModuleScript") then
		local ok, m = pcall(require, inst)
		if ok then
			return m
		end
	end
	return nil
end

local function aim(): Vector3
	local cam = Workspace.CurrentCamera
	return if cam then cam.CFrame.LookVector else Vector3.new(0, 0, -1)
end

local function send(action: string)
	task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestPremiumWeapon, action, aim())
end

local function prefersKeys(): boolean
	local HL = module("HudLayout")
	return HL ~= nil and HL.PrefersKeys ~= nil and HL.PrefersKeys() == true
end

local function button(parent: Instance, text: string, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(64, 64)
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.fromRGB(20, 20, 20)
	b.Font = Enum.Font.GothamBlack
	b.TextSize = 20
	b.TextWrapped = true
	b.Text = text
	b.AutoButtonColor = true
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = b
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(255, 255, 255)
	s.Thickness = 2
	s.Parent = b
	b.Parent = parent
	return b
end

-- the candidate the server would lock (same rules; display only)
local function candidate(model: Model): BasePart?
	local M = P.Missile
	local seat = model:FindFirstChild("DriverSeat", true)
	if seat == nil or not seat:IsA("BasePart") then
		return nil
	end
	local origin = (seat :: BasePart).Position
	local dir = aim()
	local cosCone = math.cos(math.rad(M.LockConeDeg))
	local best: BasePart? = nil
	local bestScore = math.huge
	local function consider(part: BasePart)
		local d = part.Position - origin
		local dist = d.Magnitude
		if dist < 1 or dist > M.LockRange then
			return
		end
		local c = d.Unit:Dot(dir)
		if c >= cosCone and dist * (2 - c) < bestScore then
			best, bestScore = part, dist * (2 - c)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local root = p ~= lp and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			consider(root)
		end
	end
	local folder = Workspace:FindFirstChild("WarEmpireVehicles")
	if folder then
		for _, v in ipairs(folder:GetChildren()) do
			if v ~= model and v:IsA("Model") and v.PrimaryPart and v:GetAttribute("OwnerUserId") ~= lp.UserId then
				consider(v.PrimaryPart :: BasePart)
			end
		end
	end
	return best
end

local function layout(s: State)
	local AW = module("AirWeaponsClient")
	local vp = s.Gui.AbsoluteSize
	if vp.X < 1 then
		local cam = Workspace.CurrentCamera
		vp = if cam then cam.ViewportSize else Vector2.new(844, 390)
	end
	local size = if math.min(vp.X, vp.Y) >= 500 then 72 else 64
	local pos: { Vector2 }? = nil
	if AW and AW.Layout then
		local origin = s.Gui.AbsolutePosition
		local function rectOf(g: Instance?): any
			if g and g:IsA("GuiObject") and g.Visible and g.AbsoluteSize.X > 0 then
				return { Pos = g.AbsolutePosition - origin, Size = g.AbsoluteSize }
			end
			return nil
		end
		local pg = lp:FindFirstChildOfClass("PlayerGui")
		local hud = pg and pg:FindFirstChild("WarEmpireVehicleHUD")
		local ctl = hud and hud:FindFirstChild("WE_VehicleControls")
		local tg = pg and pg:FindFirstChild("TouchGui")
		local jf = tg and tg:FindFirstChild("TouchControlFrame")
		local jump = rectOf(jf and jf:FindFirstChild("JumpButton"))
		local ok, out = pcall(AW.Layout, 2, vp, rectOf(ctl and ctl:FindFirstChild("LiftDown")), rectOf(ctl and ctl:FindFirstChild("Exit")), if jump then { jump } else {})
		if ok then
			pos = out
		end
	end
	local p1 = if pos and pos[1] then pos[1] else Vector2.new(vp.X - size * 2 - 40, vp.Y - size - 120)
	local p2 = if pos and pos[2] then pos[2] else Vector2.new(p1.X - size - 16, p1.Y)
	s.Fire.Size = UDim2.fromOffset(size, size)
	s.Missile.Size = UDim2.fromOffset(size, size)
	s.Fire.Position = UDim2.fromOffset(p1.X, p1.Y)
	s.Missile.Position = UDim2.fromOffset(p2.X, p2.Y)
end

local function deactivate()
	local s = st
	st = nil
	if s == nil then
		return
	end
	s.Alive = false
	for _, c in ipairs(s.Conns) do
		c:Disconnect()
	end
	pcall(function()
		ContextActionService:UnbindAction("WE_PremiumFire")
		ContextActionService:UnbindAction("WE_PremiumMissile")
	end)
	s.Gui:Destroy()
end

local function activate(model: Model)
	deactivate()
	local gunId = model:GetAttribute("WE_PremiumGun")
	local gun = if typeof(gunId) == "string" then P.Guns[gunId] else nil
	if gun == nil then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "WE_PremiumWeapons"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	local keys = prefersKeys()
	local fireB = button(gui, if keys then "FIRE\nLMB" else "FIRE", Color3.fromRGB(255, 205, 60))
	local misB = button(gui, if keys then "MISSILE\nR" else "MISSILE", Color3.fromRGB(235, 120, 60))
	local ret = Instance.new("Frame")
	ret.Name = "LockReticle"
	ret.AnchorPoint = Vector2.new(0.5, 0.5)
	ret.Size = UDim2.fromOffset(56, 56)
	ret.BackgroundTransparency = 1
	ret.Visible = false
	local rs = Instance.new("UIStroke")
	rs.Color = Color3.fromRGB(255, 205, 60)
	rs.Thickness = 3
	rs.Parent = ret
	ret.Parent = gui
	gui.Parent = lp:FindFirstChildOfClass("PlayerGui")
	local s: State = {
		Model = model,
		Gun = gun,
		Gui = gui,
		Fire = fireB,
		Missile = misB,
		Reticle = ret,
		Conns = {},
		Holding = false,
		LastSend = 0,
		LastMissile = -math.huge,
		Target = nil,
		Alive = true,
	}
	st = s
	layout(s)
	table.insert(s.Conns, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		layout(s)
	end))
	local function tryMissile()
		local now = os.clock()
		if now - s.LastMissile >= P.Missile.Cooldown then
			s.LastMissile = now
			send("Missile")
		end
	end
	table.insert(s.Conns, fireB.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
			s.Holding = true
		end
	end))
	table.insert(s.Conns, fireB.InputEnded:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
			s.Holding = false
		end
	end))
	table.insert(s.Conns, misB.Activated:Connect(tryMissile))
	ContextActionService:BindAction("WE_PremiumFire", function(_, state)
		s.Holding = state == Enum.UserInputState.Begin
		return Enum.ContextActionResult.Pass
	end, false, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	ContextActionService:BindAction("WE_PremiumMissile", function(_, state)
		if state == Enum.UserInputState.Begin then
			tryMissile()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.R, Enum.KeyCode.ButtonX)
	-- fire loop + lock pick + missile label at 10 Hz; the reticle follows its target every frame
	task.spawn(function()
		local interval = 1 / math.min(gun.FireRate, P.MaxRequestHz)
		local lastPick = 0
		while s.Alive do
			local now = os.clock()
			if s.Holding and now - s.LastSend >= interval then
				s.LastSend = now
				send("Fire")
			end
			if now - lastPick >= 0.1 then
				lastPick = now
				s.Target = candidate(model)
				local left = P.Missile.Cooldown - (now - s.LastMissile)
				misB.Text = if left > 0 then string.format("MISSILE\n%d", math.ceil(left)) else (if keys then "MISSILE\nR" else "MISSILE")
			end
			task.wait(math.min(interval, 0.1))
		end
	end)
	table.insert(s.Conns, RunService.RenderStepped:Connect(function()
		local t = s.Target
		local cam = Workspace.CurrentCamera
		if t and t.Parent and cam then
			local v, on = cam:WorldToViewportPoint(t.Position)
			ret.Visible = on
			ret.Position = UDim2.fromOffset(v.X, v.Y)
		else
			ret.Visible = false
		end
	end))
end

local function onSeat(hum: Humanoid)
	local seat = hum.SeatPart
	if seat == nil or seat.Name ~= "DriverSeat" then
		deactivate()
		return
	end
	local node: Instance? = seat
	while node and node ~= Workspace do
		if node:IsA("Model") and node:GetAttribute("VehicleId") ~= nil then
			break
		end
		node = node.Parent
	end
	local model = if node and node:IsA("Model") then node else nil
	if model and model:GetAttribute("WE_PremiumGun") ~= nil and model:GetAttribute("OwnerUserId") == lp.UserId then
		activate(model)
	else
		deactivate()
	end
end

local function fxTracer(from: Vector3, to: Vector3)
	local PF = module("ProductionFx")
	local low = PF ~= nil and PF.IsLowFx ~= nil and PF.IsLowFx() == true
	local cam = Workspace.CurrentCamera
	if low and cam and (cam.CFrame.Position - from).Magnitude > 150 then
		return
	end
	local len = (to - from).Magnitude
	if len < 0.5 then
		return
	end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = P.Look.TrailColor
	p.Size = Vector3.new(0.2, 0.2, len)
	p.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -len / 2)
	p.Parent = Workspace.CurrentCamera
	task.delay(0.07, function()
		p:Destroy()
	end)
end

function PremiumWeaponsClient.Init()
	if P == nil then
		return
	end
	local function hookChar(char: Model)
		local hum = char:WaitForChild("Humanoid", 10)
		if hum and hum:IsA("Humanoid") then
			hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
				onSeat(hum)
			end)
			hum.Died:Connect(deactivate)
			onSeat(hum)
		end
	end
	if lp.Character then
		task.spawn(hookChar, lp.Character)
	end
	lp.CharacterAdded:Connect(function(c)
		deactivate()
		hookChar(c)
	end)
	lp.CharacterRemoving:Connect(deactivate)
	task.spawn(function()
		local ev = Remotes.TryGetUnreliableEvent and Remotes.TryGetUnreliableEvent(Constants.RemoteNames.PremiumWeaponFx)
		local tries = 0
		while ev == nil and tries < 60 do
			task.wait(1)
			tries += 1
			ev = Remotes.TryGetUnreliableEvent(Constants.RemoteNames.PremiumWeaponFx)
		end
		if ev == nil then
			return
		end
		(ev :: UnreliableRemoteEvent).OnClientEvent:Connect(function(d: any)
			if typeof(d) ~= "table" then
				return
			end
			if d.K == "G" and typeof(d.F) == "Vector3" and typeof(d.T) == "Vector3" then
				fxTracer(d.F, d.T)
				local GF = module("GameFeelClient") -- claude-bud JOB 14: the premium gun was silent
				if GF then
					GF.Sound("PremiumGun", d.F)
				end
			elseif d.K == "M" and typeof(d.F) == "Vector3" then
				local GF = module("GameFeelClient") -- claude-bud JOB 14: the missile launch was silent
				if GF then
					GF.Sound("PremiumMissile", d.F)
				end
			elseif d.K == "X" and typeof(d.T) == "Vector3" then
				local e = Instance.new("Explosion")
				e.Position = d.T
				e.BlastPressure = 0
				e.DestroyJointRadiusPercent = 0
				e.BlastRadius = 8
				e.Parent = Workspace
				local A = module("AudioController")
				local cam = Workspace.CurrentCamera
				if A and A.Play and cam and (cam.CFrame.Position - d.T).Magnitude < 250 then
					pcall(A.Play, "Explosion.Small")
				end
			end
		end)
	end)
end

return PremiumWeaponsClient
