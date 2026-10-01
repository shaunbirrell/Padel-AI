--!strict
--[[ claude-bud JOB 57: base life on the owner's plot (Shared/Configs/BaseLifeConfig).

	Props: BaseLifeConfig.Props rows built with WorldKits (plain kits, NoDetail) on the plot's own frame, ground-snapped,
	skipped inside StorePropsConfig.BaseKeepOut, counted against StorePropsConfig.Budget.MaxBasePartsPerPlot (600, the
	JOB 40 C per-plot allowance: the store BaseRows share it) and stopped there.
	Soldiers: PerBase unarmed ambient soldiers (a 7-part kit + a Humanoid + the house R6 visual), one per Route, IDLE /
	PATROL (BaseLifeConfig.Next) from ONE loop at ThinkHz for every plot. Never hostile: not CombatService NPCs, not
	tagged WE_NPC, every part CanQuery off (no shot or raycast hits them), no weapon. At most ServerMax in a server
	(CombatConfig.MaxActiveNPCs). Server network owner; no per-frame work.
	Lifecycle: OnPlotReady (claim / rejoin / restart) builds, PlayerRemoving clears. Owner-first by the plot owner.
	Folder: Workspace.WE_BaseLife.Plot<N> (never inside a base folder that BaseService rebuilds). ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local BaseLifeConfig = require(Shared.Configs.BaseLifeConfig)
local RetentionConfig = require(Shared.Configs.RetentionConfig)
local PlotFrame = require(Shared.Util.PlotFrame)

local BaseLifeService = {}

local deps: { [string]: any } = {}
local C: any = BaseLifeConfig
local S: any = BaseLifeConfig.Soldiers

type Soldier = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Route: { Vector3 },
	Index: number,
	State: string,
	IdleUntil: number,
	LegStarted: number,
}
local soldiers: { [number]: { Soldier } } = {}
local plotOwner: { [number]: number } = {}
local rng = Random.new()

BaseLifeService._clock = os.clock

function BaseLifeService.Live(ownerUserId: number): boolean
	return RetentionConfig.Live(C, ownerUserId)
end

function BaseLifeService.ServerMax(): number
	if S.ServerMaxFromCombat then
		local ok, CC = pcall(function(): any
			return require(Shared.Configs.CombatConfig)
		end)
		if ok and CC and tonumber(CC.MaxActiveNPCs) then
			return tonumber(CC.MaxActiveNPCs) :: number
		end
	end
	return 18
end

function BaseLifeService.Count(): number
	local n = 0
	for _, list in pairs(soldiers) do
		n += #list
	end
	return n
end

local function storeProps(): any
	local ok, SP = pcall(function(): any
		return require(Shared.Configs.StorePropsConfig)
	end)
	return if ok then SP else nil
end

-- a plot-local box inside StorePropsConfig.BaseKeepOut (pure; the tests)
function BaseLifeService.InKeepOut(x: number, z: number, hx: number, hz: number): boolean
	local SP = storeProps()
	for _, k in ipairs(if SP and SP.BaseKeepOut then SP.BaseKeepOut else {}) do
		if math.abs(x - k.X) < k.HX + hx and math.abs(z - k.Z) < k.HZ + hz then
			return true
		end
	end
	return false
end

local function root(): Folder
	local f = Workspace:FindFirstChild("WE_BaseLife")
	if f == nil then
		local nf = Instance.new("Folder")
		nf.Name = "WE_BaseLife"
		nf.Parent = Workspace
		f = nf
	end
	return f :: Folder
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function groundY(x: number, z: number): number?
	local skip: { Instance } = { root() }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(skip, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = skip
	local r = Workspace:Raycast(Vector3.new(x, 300, z), Vector3.new(0, -400, 0), rayParams)
	return if r then r.Position.Y else nil
end

local function plotCf(plotId: number, lx: number, lz: number, yawDeg: number): CFrame?
	local pos = PlotFrame.PlotPosition(plotId)
	if pos == nil then
		return nil
	end
	local cf = PlotFrame.PlotCFrame(pos) * CFrame.new(lx, 0, lz)
	local y = groundY(cf.X, cf.Z) or cf.Y
	return CFrame.new(cf.X, y, cf.Z) * cf.Rotation * CFrame.Angles(0, math.rad(yawDeg), 0)
end

-- the props of one plot; returns the parts added (<= the per-plot allowance)
function BaseLifeService.BuildProps(plotId: number, parent: Instance, ownerUserId: number?): number
	local okW, WorldKits = pcall(function(): any
		return require(script.Parent.Parent.Modules.WorldKits)
	end)
	if not okW or WorldKits == nil then
		return 0
	end
	local SP = storeProps()
	local cap = if SP and SP.Budget then tonumber(SP.Budget.MaxBasePartsPerPlot) or 600 else 600
	local used = 0
	-- Code Bot JOB 67 remainder: kits the owner's real-model prop clusters replace (Job67DressConfig.BaseProps)
	local okJ, J67 = pcall(function(): any
		return require(script.Parent.Job67DressService)
	end)
	for i, row in ipairs(C.Props) do
		local spec = WorldKits.Specs[row.Kit]
		local hx = if spec then spec.Size.X / 2 else 4
		local hz = if spec then spec.Size.Z / 2 else 4
		local replaced = okJ and J67 and J67.ReplacesKit and J67.ReplacesKit(row.Kit, ownerUserId) == true
		if not replaced and not BaseLifeService.InKeepOut(row.X, row.Z, math.max(hx, hz), math.max(hx, hz)) then
			local cf = plotCf(plotId, row.X, row.Z, row.Yaw)
			if cf then
				local cl = WorldKits.NewCluster("BaseLife_" .. i .. "_" .. row.Kit, { Source = "baselife", Kind = row.Kit, Anchor = "plot", AnchorX = row.X, AnchorZ = row.Z, Tier = 1 })
				local o: { [string]: any } = { NoDetail = true }
				for k, v in pairs(row.Opts or {}) do
					o[k] = v
				end
				local n = WorldKits.Add(cl, row.Kit, cf, o :: any)
				if used + n > cap then
					cl:Destroy()
					break
				end
				WorldKits.Finish(cl, parent)
				used += n
			end
		end
	end
	return used
end

-- one unarmed soldier at a route's first point (the gate guard's build, no rifle, never hittable)
local function spawnSoldier(plotId: number, route: { Vector3 }, parent: Instance): Soldier?
	local first: Vector3? = route[1]
	if first == nil then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "BaseLifeSoldier"
	local at = CFrame.new(first + Vector3.new(0, 3, 0))
	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(2, 2, 1)
	rootPart.Transparency = 1
	rootPart.CanCollide = true
	rootPart.CanQuery = false
	rootPart.CanTouch = false
	rootPart.CFrame = at
	rootPart.Parent = model
	local olive = Color3.fromRGB(70, 75, 55)
	local function weldPart(name: string, size: Vector3, offset: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = at * offset
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		p.Color = color
		p.Material = mat
		if shape then
			p.Shape = shape
		end
		p.Parent = model
		local w = Instance.new("WeldConstraint")
		w.Part0 = rootPart
		w.Part1 = p
		w.Parent = rootPart
	end
	weldPart("Head", Vector3.new(1.05, 1.05, 1.05), CFrame.new(0, 1.55, 0), Color3.fromRGB(190, 160, 120), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	weldPart("Helmet", Vector3.new(1.2, 0.5, 1.2), CFrame.new(0, 1.95, 0), Color3.fromRGB(45, 50, 40), Enum.Material.Metal, nil)
	weldPart("Vest", Vector3.new(2.1, 1.2, 1.15), CFrame.new(0, 0.15, 0), olive, Enum.Material.Fabric, nil)
	weldPart("LegL", Vector3.new(1, 2, 1), CFrame.new(-0.5, -2, 0), olive, Enum.Material.Fabric, nil)
	weldPart("LegR", Vector3.new(1, 2, 1), CFrame.new(0.5, -2, 0), olive, Enum.Material.Fabric, nil)
	weldPart("ArmL", Vector3.new(1, 2, 1), CFrame.new(-1.5, 0, 0), olive, Enum.Material.Fabric, nil)
	weldPart("ArmR", Vector3.new(1, 2, 1), CFrame.new(1.5, 0, 0), olive, Enum.Material.Fabric, nil)
	local hum = Instance.new("Humanoid")
	hum.WalkSpeed = S.WalkSpeed
	hum.HipHeight = 2
	hum.AutoRotate = true
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.NameOcclusion = Enum.NameOcclusion.OccludeAll
	hum.BreakJointsOnDeath = false
	hum.Parent = model
	-- the house R6 soldier look added later must not take shots either
	model.DescendantAdded:Connect(function(d: Instance)
		if d:IsA("BasePart") then
			d.CanQuery = false
			d.CanTouch = false
		end
	end)
	model.PrimaryPart = rootPart
	model:SetAttribute("PlotId", plotId)
	model:SetAttribute("WE_Ambient", true)
	model.Parent = parent
	pcall(function()
		rootPart:SetNetworkOwner(nil)
	end)
	local vas = deps.VisualAssetService
	if vas and vas.TryAttachCharacterVisual then
		pcall(vas.TryAttachCharacterVisual, model, S.VisualKind)
	end
	local now = BaseLifeService._clock()
	local s: Soldier = {
		Model = model,
		Humanoid = hum,
		Root = rootPart,
		Route = route,
		Index = 1,
		State = "IDLE",
		IdleUntil = now + rng:NextNumber(S.IdleSeconds[1], S.IdleSeconds[2]),
		LegStarted = now,
	}
	return s
end

function BaseLifeService.Clear(plotId: number)
	plotOwner[plotId] = nil
	soldiers[plotId] = nil
	local f = root():FindFirstChild("Plot" .. plotId)
	if f then
		f:Destroy()
	end
end

-- (re)build one owned plot (owner-first; nil owner / OFF = cleared). Returns props parts, soldiers.
function BaseLifeService.Sync(plotId: number, ownerUserId: number?): (number, number)
	BaseLifeService.Clear(plotId)
	if ownerUserId == nil or not C.Enabled or not BaseLifeService.Live(ownerUserId) then
		return 0, 0
	end
	local f = Instance.new("Folder")
	f.Name = "Plot" .. plotId
	f.Parent = root()
	local parts = BaseLifeService.BuildProps(plotId, f, ownerUserId)
	local list: { Soldier } = {}
	local room = BaseLifeService.ServerMax() - BaseLifeService.Count()
	for i, r in ipairs(S.Routes) do
		if i > S.PerBase or #list >= room then
			break
		end
		local pts: { Vector3 } = {}
		for _, p in ipairs(r) do
			local cf = plotCf(plotId, p.X, p.Z, 0)
			if cf then
				table.insert(pts, cf.Position)
			end
		end
		local s = spawnSoldier(plotId, pts, f)
		if s then
			table.insert(list, s)
		end
	end
	soldiers[plotId] = list
	plotOwner[plotId] = ownerUserId
	print(string.format("[BaseLife] plot=%d owner=%d props=%d parts soldiers=%d (server %d / %d)", plotId, ownerUserId, parts, #list, BaseLifeService.Count(), BaseLifeService.ServerMax()))
	return parts, #list
end

-- one think pass for every soldier (ThinkHz)
function BaseLifeService.Step()
	local now = BaseLifeService._clock()
	for _, list in pairs(soldiers) do
		for _, s in ipairs(list) do
			if s.Model.Parent ~= nil and s.Humanoid.Health > 0 then
				local target = s.Route[s.Index]
				local flat = Vector3.new(s.Root.Position.X - target.X, 0, s.Root.Position.Z - target.Z)
				local nextState = BaseLifeConfig.Next(s.State, { Now = now, IdleUntil = s.IdleUntil, LegStarted = s.LegStarted, Dist = flat.Magnitude })
				if nextState ~= s.State then
					s.State = nextState
					if nextState == "PATROL" then
						s.Index = s.Index % #s.Route + 1
						s.LegStarted = now
						s.Humanoid:MoveTo(s.Route[s.Index])
					else
						s.IdleUntil = now + rng:NextNumber(S.IdleSeconds[1], S.IdleSeconds[2])
						s.Humanoid:MoveTo(s.Root.Position)
					end
				end
			end
		end
	end
end

function BaseLifeService.Init(d: { [string]: any })
	deps = d
	if not C.Enabled then
		return
	end
	local bs = d.BaseService
	if bs and bs.OnPlotReady then
		pcall(bs.OnPlotReady, function(player: Player, plotId: number)
			task.defer(function()
				if player.Parent then
					BaseLifeService.Sync(plotId, player.UserId)
				end
			end)
		end)
	end
	Players.PlayerRemoving:Connect(function(p: Player)
		for plotId, uid in pairs(plotOwner) do
			if uid == p.UserId then
				BaseLifeService.Clear(plotId)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1 / math.max(0.5, tonumber(S.ThinkHz) or 2))
			pcall(BaseLifeService.Step)
		end
	end)
	print("[WAR EMPIRE] BaseLifeService Init")
end

return BaseLifeService
