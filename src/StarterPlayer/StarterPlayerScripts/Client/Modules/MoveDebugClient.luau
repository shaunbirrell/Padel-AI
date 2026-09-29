--!strict
--[[
	v123 MoveDebugClient (Code Bot): the phone side of /movedebug (server: Modules/MoveDebug). Nothing runs and nothing
	is created unless the server set this player's WE_MoveDebug attribute (admin allowlist). While on, every frame:
	  * MoveDirection, the ControlModule move vector, WalkSpeed, horizontal speed, HumanoidState, Sit / PlatformStand /
	    AutoRotate, root Anchored, root ReceiveAge (> 0: this phone is NOT simulating its own character: network owner
	    lost), AssemblyRootPart (welded to something), FloorMaterial;
	  * the thumb: the last touch in the left 45 % of the screen and every Active GuiObject under it (not TouchGui);
	  * TouchGui enabled / TouchControlFrame visible; the ControlModule's active controller and whether it is enabled;
	  * his army: own units (Workspace.WarEmpireSquads, OwnerUserId = him), nearest / centre distance, within 8 studs,
	    CatchingUp (WE_MoveState, only published with /armydebug on);
	  * blockers: parts in a box just ahead of him that CAN collide with his root (his CollisionGroup, CanCollide).
	[MOVEMENT BLOCK DETECTED]: MoveDirection.Magnitude > 0.5 but horizontal speed < 1 for more than 0.25 s. One full
	dump per episode (+ its end with the duration). [MOVEMENT INPUT LOST]: a thumb held on the stick side while the
	move vector is 0 for more than 0.25 s. A one-line summary each second; the latest lines on a small non-Active label.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local MoveDebugClient = {}

local ATTR = "WE_MoveDebug"
local BLOCK_MOVE = 0.5
local BLOCK_SPEED = 1
local BLOCK_SECONDS = 0.25
local NEAR_STUDS = 8

local player = Players.LocalPlayer
local conn: RBXScriptConnection? = nil
local inputConns: { RBXScriptConnection } = {}
local gui: ScreenGui? = nil
local label: TextLabel? = nil
local controls: any = nil
local thumb: InputObject? = nil
local thumbPos: Vector2? = nil
local blockSince: number? = nil
local blockLogged = false
local inputLostSince: number? = nil
local inputLostLogged = false
local lastSummaryAt = -math.huge
local lastEvent = ""
local wsChanges: { string } = {}

MoveDebugClient.Stats = { Frames = 0, Blocks = 0, InputLost = 0 }

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function getControls(): any
	if controls ~= nil then
		return controls
	end
	pcall(function()
		local ps = player:FindFirstChildOfClass("PlayerScripts")
		local pm = ps and ps:FindFirstChild("PlayerModule")
		if pm and pm:IsA("ModuleScript") then
			local req: any = require
			controls = req(pm):GetControls()
		end
	end)
	return controls
end

local function controlsInfo(): (string, Vector3)
	local c = getControls()
	if c == nil then
		return "controls=?", Vector3.zero
	end
	local mv = Vector3.zero
	pcall(function()
		mv = c:GetMoveVector()
	end)
	local ac: any = c.activeController
	local name = "none"
	local en = "?"
	if ac then
		name = "active"
		pcall(function()
			en = tostring(ac.enabled)
		end)
	end
	return string.format("controls=%s enabled=%s", name, en), mv
end

local function touchGuiInfo(): string
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local tg = pg and pg:FindFirstChild("TouchGui")
	if not (tg and tg:IsA("ScreenGui")) then
		return "touchgui=none"
	end
	local f = tg:FindFirstChild("TouchControlFrame")
	return string.format("touchgui=%s frame=%s", tostring(tg.Enabled), if f and f:IsA("GuiObject") then tostring(f.Visible) else "none")
end

local function guisAtThumb(): string
	local pos = thumbPos
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pos == nil or pg == nil then
		return "thumb=none"
	end
	local hits = {}
	local ok, objs = pcall(function()
		return pg:GetGuiObjectsAtPosition(pos.X, pos.Y)
	end)
	if ok and objs then
		for _, o in ipairs(objs) do
			local sg = o:FindFirstAncestorOfClass("ScreenGui")
			if (o.Active or o:IsA("GuiButton")) and not (sg and sg.Name == "TouchGui") and o.Visible then
				table.insert(hits, (if sg then sg.Name .. "." else "") .. o.Name)
				if #hits >= 4 then
					break
				end
			end
		end
	end
	return string.format("thumb=(%d,%d) activeGuis=%s", math.floor(pos.X), math.floor(pos.Y), if #hits > 0 then table.concat(hits, ",") else "0")
end

local function armyInfo(root: BasePart): (string, number)
	local folder = Workspace:FindFirstChild("WarEmpireSquads")
	if folder == nil then
		return "army=none", 0
	end
	local n, near, catching = 0, 0, 0
	local nearest = math.huge
	local sum = Vector3.zero
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("OwnerUserId") == player.UserId then
			local r = m:FindFirstChild("HumanoidRootPart")
			if r and r:IsA("BasePart") then
				n += 1
				local d = flat(r.Position - root.Position).Magnitude
				nearest = math.min(nearest, d)
				sum += r.Position
				if d <= NEAR_STUDS then
					near += 1
				end
				if m:GetAttribute("WE_MoveState") == "CatchingUp" then
					catching += 1
				end
			end
		end
	end
	if n == 0 then
		return "army=0", 0
	end
	return string.format("army=%d nearest=%.1f centre=%.1f within%d=%d catchingUp=%d", n, nearest, flat(sum / n - root.Position).Magnitude, NEAR_STUDS, near, catching), near
end

local function blockers(char: Model, root: BasePart, md: Vector3): string
	local dir = if md.Magnitude > 0.1 then flat(md).Unit else flat(root.CFrame.LookVector).Unit
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	params.RespectCanCollide = true
	params.CollisionGroup = root.CollisionGroup
	local centre = CFrame.lookAt(root.Position + dir * 1.8, root.Position + dir * 3)
	local ok, parts = pcall(function()
		return Workspace:GetPartBoundsInBox(centre, Vector3.new(3, 4.5, 2.2), params)
	end)
	if not ok or parts == nil or #parts == 0 then
		return "blockers=0"
	end
	local names = {}
	for _, p in ipairs(parts) do
		if p.Position.Y > root.Position.Y - 2.6 then -- not the floor he stands on
			table.insert(names, string.format("%s@%s", p:GetFullName():sub(-60), p.CollisionGroup))
			if #names >= 4 then
				break
			end
		end
	end
	return "blockers=" .. (if #names > 0 then table.concat(names, " | ") else "0")
end

local function show(text: string)
	local l = label
	if l then
		l.Text = text
	end
end

local function buildGui()
	if gui then
		return
	end
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg == nil then
		return
	end
	local g = Instance.new("ScreenGui")
	g.Name = "WE_MoveDebug"
	g.ResetOnSpawn = false
	g.DisplayOrder = 50
	g.IgnoreGuiInset = false
	local l = Instance.new("TextLabel")
	l.Name = "Lines"
	l.Active = false -- never takes a touch (it sits top centre, far from the thumbstick)
	l.Selectable = false
	l.BackgroundTransparency = 0.45
	l.BackgroundColor3 = Color3.new(0, 0, 0)
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextScaled = false
	l.TextSize = 11
	l.Font = Enum.Font.Code
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.TextWrapped = true
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = UDim2.new(0.5, 0, 0, 40)
	l.Size = UDim2.new(0.62, 0, 0, 96)
	l.Text = "MOVE DEBUG ON"
	l.Parent = g
	g.Parent = pg
	gui, label = g, l
end

local function frame(_dt: number)
	MoveDebugClient.Stats.Frames += 1
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (char and hum and root and root:IsA("BasePart")) then
		return
	end
	local h = hum :: Humanoid
	local r = root :: BasePart
	local now = os.clock()
	local md = h.MoveDirection
	local hv = flat(r.AssemblyLinearVelocity).Magnitude
	-- 1) body block / stop: he asks to move, he does not
	if md.Magnitude > BLOCK_MOVE and hv < BLOCK_SPEED and h.Health > 0 and h.SeatPart == nil then
		blockSince = blockSince or now
		if not blockLogged and now - (blockSince :: number) > BLOCK_SECONDS then
			blockLogged = true
			MoveDebugClient.Stats.Blocks += 1
			local cInfo, mv = controlsInfo()
			local armyTxt = armyInfo(r)
			local ar = r.AssemblyRootPart
			lastEvent = string.format("BLOCK %.2fs md=%.2f spd=%.2f ws=%.1f state=%s", now - (blockSince :: number), md.Magnitude, hv, h.WalkSpeed, h:GetState().Name)
			warn(string.format(
				"[MOVEMENT BLOCK DETECTED] md=(%.2f,%.2f) |md|=%.2f moveVec=%.2f spd=%.2f ws=%.1f state=%s sit=%s ps=%s autoRot=%s anch=%s receiveAge=%.2f asm=%s floor=%s group=%s %s %s %s %s %s wsChanges=%s",
				md.X, md.Z, md.Magnitude, mv.Magnitude, hv, h.WalkSpeed, h:GetState().Name, tostring(h.Sit), tostring(h.PlatformStand),
				tostring(h.AutoRotate), tostring(r.Anchored), r.ReceiveAge, if ar == r then "self" else (if ar then ar:GetFullName() else "nil"),
				h.FloorMaterial.Name, r.CollisionGroup, armyTxt, blockers(char, r, md), cInfo, touchGuiInfo(), guisAtThumb(),
				if #wsChanges > 0 then table.concat(wsChanges, ",") else "none"))
		end
	else
		if blockLogged and blockSince then
			warn(string.format("[MOVEMENT BLOCK END] after %.2fs spd=%.2f |md|=%.2f %s", now - blockSince, hv, md.Magnitude, (armyInfo(r))))
		end
		blockSince = nil
		blockLogged = false
	end
	-- 2) input lost: a thumb held on the stick side, no move vector
	local cInfo, mv = controlsInfo()
	if thumb ~= nil and mv.Magnitude < 0.05 and md.Magnitude < 0.05 and h.SeatPart == nil then
		inputLostSince = inputLostSince or now
		if not inputLostLogged and now - (inputLostSince :: number) > BLOCK_SECONDS then
			inputLostLogged = true
			MoveDebugClient.Stats.InputLost += 1
			lastEvent = "INPUT LOST " .. guisAtThumb()
			warn(string.format("[MOVEMENT INPUT LOST] thumb held, moveVec=0 md=0 %s %s %s spd=%.2f state=%s", cInfo, touchGuiInfo(), guisAtThumb(), hv, h:GetState().Name))
		end
	else
		inputLostSince = nil
		inputLostLogged = false
	end
	-- 3) the once-a-second summary (console + label)
	if now - lastSummaryAt >= 1 then
		lastSummaryAt = now
		local armyTxt = armyInfo(r)
		local line = string.format("|md|=%.2f mv=%.2f spd=%.1f ws=%.1f %s anch=%s rAge=%.2f %s\n%s %s\n%s", md.Magnitude, mv.Magnitude, hv, h.WalkSpeed,
			h:GetState().Name, tostring(r.Anchored), r.ReceiveAge, armyTxt, cInfo, touchGuiInfo(), lastEvent)
		print("[MoveDebug] C " .. string.gsub(line, "\n", " | "))
		show(line)
	end
end

local function trackInput()
	local function onTouch(io: InputObject)
		local cam = Workspace.CurrentCamera
		local vp = if cam then cam.ViewportSize else Vector2.new(844, 390)
		if io.UserInputType == Enum.UserInputType.Touch and io.Position.X < vp.X * 0.45 then
			if thumb == nil or thumb == io then
				thumb = io
				thumbPos = Vector2.new(io.Position.X, io.Position.Y)
			end
		end
	end
	table.insert(inputConns, UserInputService.TouchStarted:Connect(function(io)
		if thumb == nil then
			onTouch(io)
		end
	end))
	table.insert(inputConns, UserInputService.TouchMoved:Connect(onTouch))
	table.insert(inputConns, UserInputService.TouchEnded:Connect(function(io)
		if io == thumb then
			thumb = nil
		end
	end))
end

local function watchHumanoid(char: Model)
	local hum = char:WaitForChild("Humanoid", 10)
	if hum and hum:IsA("Humanoid") then
		table.insert(inputConns, hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
			if player:GetAttribute(ATTR) == true then
				local s = string.format("%.1f@%.1f", hum.WalkSpeed, os.clock())
				table.insert(wsChanges, s)
				if #wsChanges > 4 then
					table.remove(wsChanges, 1)
				end
				print("[MoveDebug] C WalkSpeed -> " .. s)
			end
		end))
		table.insert(inputConns, hum.StateChanged:Connect(function(old, new)
			if player:GetAttribute(ATTR) == true and (new == Enum.HumanoidStateType.PlatformStanding or new == Enum.HumanoidStateType.Physics
				or new == Enum.HumanoidStateType.Seated or new == Enum.HumanoidStateType.Ragdoll or new == Enum.HumanoidStateType.FallingDown) then
				warn(string.format("[MoveDebug] C state %s -> %s", old.Name, new.Name))
			end
		end))
	end
end

local function setOn(on: boolean)
	if on and conn == nil then
		buildGui()
		trackInput()
		if player.Character then
			task.spawn(watchHumanoid, player.Character)
		end
		table.insert(inputConns, player.CharacterAdded:Connect(watchHumanoid))
		conn = RunService.Heartbeat:Connect(function(dt)
			local ok, err = pcall(frame, dt)
			if not ok then
				show("MoveDebug error: " .. tostring(err))
			end
		end)
		print("[MoveDebug] C on")
	elseif not on and conn ~= nil then
		(conn :: RBXScriptConnection):Disconnect()
		conn = nil
		for _, c in ipairs(inputConns) do
			c:Disconnect()
		end
		table.clear(inputConns)
		thumb, thumbPos = nil, nil
		if gui then
			gui:Destroy()
		end
		gui, label = nil, nil
		print("[MoveDebug] C off")
	end
end

function MoveDebugClient.Init()
	player:GetAttributeChangedSignal(ATTR):Connect(function()
		setOn(player:GetAttribute(ATTR) == true)
	end)
	setOn(player:GetAttribute(ATTR) == true)
end

return MoveDebugClient
