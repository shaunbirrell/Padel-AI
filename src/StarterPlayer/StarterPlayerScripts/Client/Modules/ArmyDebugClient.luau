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
	gui.Size = UDim2.fromOffset(120, 34)
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
					v.Text.Text = string.format("S%02d / Slot %02d\n%s %.1f", id, slot, tostring(m:GetAttribute("WE_MoveState") or "?"), d)
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
				if not ok then
					warn("[ArmyDebugClient] " .. tostring(err))
				end
			elseif folder ~= nil then
				clearAll()
			end
		end
	end)
end

return ArmyDebugClient
