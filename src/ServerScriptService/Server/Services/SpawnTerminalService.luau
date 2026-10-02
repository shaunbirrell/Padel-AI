--!strict
--[[ claude-bud JOB 56: the helipad + dock spawn terminals (Shared/Configs/SpawnTerminalConfig).

	A console beside each BUILT helipad / dock on an owned plot (BaseUpgrades.Helipad / Dock >= 1). Its ProximityPrompt is
	the house terminal contract (Name WE_PanelPrompt, WE_OpenPanel = "Garage", WE_OpenTab = "Air" / "Naval"):
	UIController opens VehicleController.Open(tab), the Garage filtered to that category, and the spawn itself is the
	normal RequestSpawnVehicle remote into VehicleService.RequestSpawn with all of its gates. Nothing here spawns,
	grants or moves anyone.

	Lifecycle: built on OnPlotReady (claim / rejoin / restart) and on a Helipad / Dock upgrade, cleared when the owner
	leaves. Owner-first by the plot owner. Parts only: anchored, no Neon, no lights; one SurfaceGui (MaxDistance 40). ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local SpawnTerminalConfig = require(Shared.Configs.SpawnTerminalConfig)
local RetentionConfig = require(Shared.Configs.RetentionConfig)
local PlotFrame = require(Shared.Util.PlotFrame)

local SpawnTerminalService = {}

local deps: { [string]: any } = {}
local C: any = SpawnTerminalConfig
local plotOwner: { [number]: number } = {}

function SpawnTerminalService.Live(ownerUserId: number): boolean
	return RetentionConfig.Live(C, ownerUserId)
end

-- which terminals a profile has earned (pure; the tests): the structure built (level >= 1)
function SpawnTerminalService.Wanted(profile: any): { string }
	local out = {}
	local has = typeof(profile) == "table" and typeof(profile.BaseUpgrades) == "table"
	for _, kind in ipairs({ "Helipad", "Dock" }) do
		local t = C.Terminals[kind]
		if t and has and (tonumber(profile.BaseUpgrades[t.Need]) or 0) >= 1 then
			table.insert(out, kind)
		end
	end
	return out
end

local function root(): Folder
	local f = Workspace:FindFirstChild("WE_SpawnTerminals")
	if f == nil then
		local nf = Instance.new("Folder")
		nf.Name = "WE_SpawnTerminals"
		nf.Parent = Workspace
		f = nf
	end
	return f :: Folder
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function groundY(x: number, z: number): number?
	local chars = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(chars, p.Character)
		end
	end
	table.insert(chars, root())
	rayParams.FilterDescendantsInstances = chars
	local r = Workspace:Raycast(Vector3.new(x, 300, z), Vector3.new(0, -400, 0), rayParams)
	return if r then r.Position.Y else nil
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = true
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- one console (the HollowBuildingBuilder terminal look: a stand, a tilted screen, a lamp), its prompt on the stand
function SpawnTerminalService.BuildOne(plotId: number, kind: string, parent: Instance): Model?
	local t = C.Terminals[kind]
	if t == nil then
		return nil
	end
	local pos = PlotFrame.PlotPosition(plotId)
	if pos == nil then
		return nil
	end
	local pcf = PlotFrame.PlotCFrame(pos) * CFrame.new(t.At[1], 0, t.At[2]) -- the plot's own frame (its yaw included)
	local y = groundY(pcf.X, pcf.Z) or pcf.Y
	local frame = CFrame.new(pcf.X, y, pcf.Z) * pcf.Rotation * CFrame.Angles(0, math.rad(tonumber(t.Yaw) or 0), 0)
	local m = Instance.new("Model")
	m.Name = "WE_SpawnTerminal_" .. kind
	m:SetAttribute("PlotId", plotId)
	local body = part(m, "Stand", Vector3.new(2.4, 3.2, 1.2), frame * CFrame.new(0, 1.6, 0), Color3.fromRGB(46, 50, 46), Enum.Material.Metal)
	local screen = part(m, "Screen", Vector3.new(2.1, 1.3, 0.14), frame * CFrame.new(0, 3.55, 0.3) * CFrame.Angles(math.rad(-20), 0, 0), Color3.fromRGB(10, 24, 14), Enum.Material.SmoothPlastic)
	screen.CanCollide = false
	part(m, "Lamp", Vector3.new(0.4, 0.2, 0.4), frame * CFrame.new(0.8, 3.25, 0.35), Color3.fromRGB(110, 230, 140), Enum.Material.SmoothPlastic).CanCollide = false
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.MaxDistance = 40
	sg.PixelsPerStud = 50
	sg.LightInfluence = 0
	sg.Parent = screen
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextScaled = true
	lbl.TextColor3 = Color3.fromRGB(150, 255, 170)
	lbl.Text = table.concat(t.Screen, "\n")
	lbl.Parent = sg
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WE_PanelPrompt"
	prompt.ActionText = t.Action
	prompt.ObjectText = t.Object
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = C.PromptRange
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt:SetAttribute("WE_OpenPanel", C.Panel)
	prompt:SetAttribute("WE_OpenTab", t.Tab)
	prompt.Parent = body
	body:SetAttribute("WE_Terminal", C.Panel)
	m.Parent = parent
	return m
end

function SpawnTerminalService.Clear(plotId: number)
	plotOwner[plotId] = nil
	local f = root():FindFirstChild("Plot" .. plotId)
	if f then
		f:Destroy()
	end
end

-- (re)build one owned plot's terminals from the SAVED structures (owner-first; nil owner / OFF = cleared)
function SpawnTerminalService.Sync(plotId: number, ownerUserId: number?, profile: any): number
	SpawnTerminalService.Clear(plotId)
	if ownerUserId == nil or not SpawnTerminalService.Live(ownerUserId) then
		return 0
	end
	local kinds = SpawnTerminalService.Wanted(profile)
	if #kinds == 0 then
		return 0
	end
	local f = Instance.new("Folder")
	f.Name = "Plot" .. plotId
	local n = 0
	for _, kind in ipairs(kinds) do
		if SpawnTerminalService.BuildOne(plotId, kind, f) then
			n += 1
		end
	end
	f.Parent = root()
	plotOwner[plotId] = ownerUserId
	print(string.format("[SpawnTerminal] plot=%d owner=%d terminals=%s", plotId, ownerUserId, table.concat(kinds, ",")))
	return n
end

local function syncPlayer(player: Player, plotId: number?)
	local bs = deps.BaseService
	local pid = plotId or (if bs and bs.GetOwnedPlotId then bs.GetOwnedPlotId(player) else nil)
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	if typeof(pid) == "number" and profile then
		SpawnTerminalService.Sync(pid, player.UserId, profile)
	end
end

function SpawnTerminalService.Init(d: { [string]: any })
	deps = d
	if not C.Enabled then
		return
	end
	local bs = d.BaseService
	if bs and bs.OnPlotReady then
		pcall(bs.OnPlotReady, function(player: Player, plotId: number)
			task.defer(syncPlayer, player, plotId)
		end)
	end
	if bs and bs.GetUpgradeChangedEvent then
		bs.GetUpgradeChangedEvent().Event:Connect(function(userId: number, plotId: number?, structureId: string?, _level: number?)
			if structureId == "Helipad" or structureId == "Dock" then
				local p = Players:GetPlayerByUserId(userId)
				if p then
					task.defer(syncPlayer, p, plotId)
				end
			end
		end)
	end
	Players.PlayerRemoving:Connect(function(p: Player)
		for plotId, uid in pairs(plotOwner) do
			if uid == p.UserId then
				SpawnTerminalService.Clear(plotId)
			end
		end
	end)
	print("[WAR EMPIRE] SpawnTerminalService Init")
end

return SpawnTerminalService
