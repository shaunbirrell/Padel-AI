--!strict
--[[
	v115 (Code Bot Roblox, 2026-09-29, docs/ARMY-FOLLOW-ROOTCAUSE-3.md): ArmyDebugClient — the owner's army-follow
	debug overlay. Client-side only (so only he sees it): while ArmyConfig.Follow3.Debug is true AND his WE_ArmyDebug
	attribute is true (default on for Follow3.DebugUserIds; /armydebug toggles it), every one of HIS units
	(Workspace.WarEmpireSquads, OwnerUserId = him) gets:
	  * a neon slot marker (anchored, CanCollide / CanQuery / CanTouch off) at its current world slot (WE_SlotPos,
	    published by the server's ArmyController only in debug mode);
	  * a thin line from the soldier to its slot, green (in its slot) / yellow (a few studs off) / red (far off);
	  * a label over the soldier: "S07 / Slot 07" + its move state (WE_MoveState) + its distance to its slot.
	Refreshed at RefreshHz; nothing is created while debug is off (all of it is destroyed when it turns off).

	claude-bud JOB 23 (docs/ARMY-FOLLOW-ROOTCAUSE-4.md):
	  * compact two-line labels: "S01 / Slot 01" and "<state letter> <distance to its slot>" (S = settled / InPosition,
	    F = Following, C = CatchingUp, R = stuck recovery, else its first letter); the full per-soldier lines stay in the
	    server console ([ArmyDebug], DebugLogSeconds);
	  * the formation panel (top right, under the top bar; tap it to fold it to one line): the server's WE_ArmyPanel
	    player attribute (formation speed, turn rate, heading error, player / desired / actual heading, max slot speed,
	    average / max slot error, catching up N / total);
	  * trails: the last TRAIL_SECONDS of the world slot of two opposite outer corners (the lowest and the highest
	    FormationSlot: cyan / magenta dots), to see a slot's path through a turn.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60) :: Instance -- Bootstrap already waited for it; bounded anyway
local okCfg, ArmyConfigOrErr = pcall(require, (Shared :: any).Configs.ArmyConfig)
local ArmyConfig: any = if okCfg and typeof(ArmyConfigOrErr) == "table" then ArmyConfigOrErr else {}

local ArmyDebugClient = {}

local REFRESH = 0.2 -- seconds (5 Hz)
local GREEN = Color3.fromRGB(60, 230, 90)
local YELLOW = Color3.fromRGB(255, 210, 40)
local RED = Color3.fromRGB(255, 60, 60)

type Vis = { Marker: BasePart, Line: BasePart, Gui: BillboardGui, Text: TextLabel }

local folder: Folder? = nil
local vis: { [Model]: Vis } = {}

-- JOB 23: panel + corner-slot trails
local TRAIL_SECONDS = 1.6
local TRAIL_DOTS = 8 -- (5 Hz x 1.6 s)
local CYAN = Color3.fromRGB(60, 220, 255)
local MAGENTA = Color3.fromRGB(255, 80, 220)
local panelGui: ScreenGui? = nil
local panelText: TextButton? = nil
local panelFolded = false
type Trail = { Dots: { BasePart }, Hist: { { P: Vector3, At: number } } }
local trails: { [string]: Trail } = {}

local STATE_LETTER: { [string]: string } = { InPosition = "S", Following = "F", CatchingUp = "C", StuckRecovery = "R" }

local function enabled(player: Player): boolean
	local f3 = (ArmyConfig :: any).Follow3
	return typeof(f3) == "table" and f3.Debug == true and player:GetAttribute("WE_ArmyDebug") == true
end

local function part(name: string, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Parent = parent
	return p
end

local function clearAll()
	for _, v in pairs(vis) do
		v.Marker:Destroy()
		v.Line:Destroy()
		v.Gui:Destroy()
	end
	table.clear(vis)
	for _, tr in pairs(trails) do
		for _, d in ipairs(tr.Dots) do
			d:Destroy()
		end
	end
	table.clear(trails)
	if panelGui then
		panelGui:Destroy()
		panelGui = nil
		panelText = nil
	end
	if folder then
		folder:Destroy()
		folder = nil
	end
end

local function ensure(model: Model): Vis
	local v = vis[model]
	if v then
		return v
	end
	if folder == nil or folder.Parent == nil then
		local f = Instance.new("Folder")
		f.Name = "WE_ArmyDebugLocal"
		f.Parent = Workspace
		folder = f
	end
	local marker = part("SlotMarker", GREEN, folder :: Folder)
	marker.Shape = Enum.PartType.Cylinder
	marker.Size = Vector3.new(0.3, 2.2, 2.2)
	marker.Transparency = 0.25
	local line = part("SlotLine", GREEN, folder :: Folder)
	line.Size = Vector3.new(0.15, 0.15, 1)
	line.Transparency = 0.35
	local gui = Instance.new("BillboardGui")
	gui.Name = "WE_ArmyDebugLabel"
	gui.Size = UDim2.fromOffset(96, 34) -- (two short lines, TextScaled)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 0.45
	text.BackgroundColor3 = Color3.new(0, 0, 0)
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextScaled = true
	text.Font = Enum.Font.GothamBold
	text.Parent = gui
	gui.Parent = folder
	v = { Marker = marker, Line = line, Gui = gui, Text = text }
	vis[model] = v
	return v
end

local function drop(model: Model)
	local v = vis[model]
	if v then
		v.Marker:Destroy()
		v.Line:Destroy()
		v.Gui:Destroy()
		vis[model] = nil
	end
end

local function refresh(player: Player)
	local squads = Workspace:FindFirstChild("WarEmpireSquads")
	local seen: { [Model]: boolean } = {}
	if squads then
		for _, m in ipairs(squads:GetChildren()) do
			if m:IsA("Model") and m:GetAttribute("OwnerUserId") == player.UserId then
				local root = m:FindFirstChild("HumanoidRootPart")
				local sp = m:GetAttribute("WE_SlotPos")
				if root and root:IsA("BasePart") and typeof(sp) == "Vector3" then
					seen[m] = true
					local v = ensure(m)
					local slot = tonumber(m:GetAttribute("FormationSlot")) or 0
					local id = tonumber(m:GetAttribute("SquadSlot")) or 0
					local pos = root.Position
					local ground = Vector3.new(sp.X, sp.Y - 2.8, sp.Z) -- (the slot sits at his root height on his path)
					local dx, dz = pos.X - sp.X, pos.Z - sp.Z
					local d = math.sqrt(dx * dx + dz * dz)
					local col = if d <= 2.5 then GREEN elseif d <= 6 then YELLOW else RED
					v.Marker.Color = col
					v.Marker.CFrame = CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(90))
					local a = Vector3.new(pos.X, pos.Y - 2.6, pos.Z)
					local len = (ground - a).Magnitude
					if len > 0.3 then
						v.Line.Transparency = 0.35
						v.Line.Size = Vector3.new(0.15, 0.15, len)
						v.Line.CFrame = CFrame.lookAt((a + ground) * 0.5, ground)
					else
						v.Line.Transparency = 1
					end
					v.Line.Color = col
					v.Gui.Adornee = root
					local st = tostring(m:GetAttribute("WE_MoveState") or "?")
					v.Text.Text = string.format("S%02d / Slot %02d\n%s %.1f", id, slot, STATE_LETTER[st] or string.sub(st, 1, 1), d)
					v.Text.TextColor3 = col
				end
			end
		end
	end
	for m, _ in pairs(vis) do
		if not seen[m] then
			drop(m)
		end
	end
end

-- JOB 23: the formation panel (top right, below the top bar; a tap folds it to its first line)
local function panel(player: Player)
	local txt = player:GetAttribute("WE_ArmyPanel")
	if typeof(txt) ~= "string" then
		if panelGui then
			panelGui.Enabled = false
		end
		return
	end
	if panelGui == nil or panelGui.Parent == nil then
		local pg = player:FindFirstChildOfClass("PlayerGui")
		if pg == nil then
			return
		end
		local g = Instance.new("ScreenGui")
		g.Name = "WE_ArmyDebugPanel"
		g.ResetOnSpawn = false
		g.DisplayOrder = 40
		local b = Instance.new("TextButton")
		b.Name = "Panel"
		b.AnchorPoint = Vector2.new(1, 0)
		b.Position = UDim2.new(1, -12, 0, 64) -- (under the top-bar pills, clear of the jump button)
		b.Size = UDim2.fromOffset(250, 150)
		b.BackgroundColor3 = Color3.new(0, 0, 0)
		b.BackgroundTransparency = 0.35
		b.TextColor3 = Color3.new(1, 1, 1)
		b.TextSize = 14 -- (no UIScale on this gui: 14 px real)
		b.Font = Enum.Font.GothamMedium
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.TextYAlignment = Enum.TextYAlignment.Top
		b.AutoButtonColor = false
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingTop = UDim.new(0, 6)
		pad.Parent = b
		b.Activated:Connect(function()
			panelFolded = not panelFolded
		end)
		b.Parent = g
		g.Parent = pg
		panelGui = g
		panelText = b
	end
	local g = panelGui :: ScreenGui
	local b = panelText :: TextButton
	g.Enabled = true
	if panelFolded then
		b.Size = UDim2.fromOffset(250, 48) -- (>= 44 px tap target)
		b.Text = string.split(txt, "\n")[1] .. "  (tap)"
	else
		b.Size = UDim2.fromOffset(250, 150)
		b.Text = txt
	end
end

-- JOB 23: the last TRAIL_SECONDS of the world slot of the two opposite outer corners (lowest / highest FormationSlot)
local function trailStep(player: Player, now: number)
	local squads = Workspace:FindFirstChild("WarEmpireSquads")
	local lo, hi = math.huge, -math.huge
	local loM: Model? = nil
	local hiM: Model? = nil
	if squads then
		for _, m in ipairs(squads:GetChildren()) do
			if m:IsA("Model") and m:GetAttribute("OwnerUserId") == player.UserId and typeof(m:GetAttribute("WE_SlotPos")) == "Vector3" then
				local slot = tonumber(m:GetAttribute("FormationSlot")) or 0
				if slot < lo then
					lo, loM = slot, m
				end
				if slot > hi then
					hi, hiM = slot, m
				end
			end
		end
	end
	local want: { [string]: { M: Model?, C: Color3 } } = { first = { M = loM, C = CYAN }, last = { M = if hi ~= lo then hiM else nil, C = MAGENTA } }
	for key, w in pairs(want) do
		local tr = trails[key]
		if w.M == nil then
			if tr then
				for _, d in ipairs(tr.Dots) do
					d:Destroy()
				end
				trails[key] = nil
			end
		else
			if tr == nil then
				local nt: Trail = { Dots = {}, Hist = {} }
				for i = 1, TRAIL_DOTS do
					local d = part("SlotTrail", w.C, folder :: Folder)
					d.Shape = Enum.PartType.Ball
					d.Size = Vector3.new(0.6, 0.6, 0.6)
					d.Transparency = 1
					nt.Dots[i] = d
				end
				trails[key] = nt
				tr = nt
			end
			local t = tr :: Trail
			local sp = (w.M :: Model):GetAttribute("WE_SlotPos") :: Vector3
			table.insert(t.Hist, { P = Vector3.new(sp.X, sp.Y - 2.6, sp.Z), At = now })
			while #t.Hist > TRAIL_DOTS or (#t.Hist > 0 and now - t.Hist[1].At > TRAIL_SECONDS) do
				table.remove(t.Hist, 1)
			end
			for i, d in ipairs(t.Dots) do
				local h = t.Hist[i]
				if h then
					d.CFrame = CFrame.new(h.P)
					d.Transparency = 0.2 + 0.7 * math.clamp((now - h.At) / TRAIL_SECONDS, 0, 1)
				else
					d.Transparency = 1
				end
			end
		end
	end
end

function ArmyDebugClient.Init()
	local player = Players.LocalPlayer
	if player == nil then
		return
	end
	task.spawn(function()
		while true do
			task.wait(REFRESH)
			if enabled(player) then
				local ok, err = pcall(refresh, player)
				if ok and folder ~= nil then
					ok, err = pcall(trailStep, player, os.clock())
				end
				if ok then
					ok, err = pcall(panel, player)
				end
				if not ok then
					warn("[ArmyDebugClient] " .. tostring(err))
				end
			elseif folder ~= nil or panelGui ~= nil then
				clearAll()
			end
		end
	end)
end

return ArmyDebugClient
