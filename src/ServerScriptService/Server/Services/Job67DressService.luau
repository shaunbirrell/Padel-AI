--!strict
--[[ Code Bot JOB 67 remainder (2026-10-02): the owned-asset dressing (Shared/Configs/Job67DressConfig, the one config).
	Batch 1: perimeter walls (sandbag -> Hesco tiers from the saved DefensiveWalls level) and base prop clusters (grow
	with the sum of the saved structure levels). Owner-first by the BASE OWNER (RetentionConfig.Live): only the playtest
	owner's base wears it; everyone sees his base.

	Packs load once per server (InsertService:LoadAsset, never on the boot path: the first wall / plot sync asks), are
	audited (scripts, lights, sounds, FX, prompts, GUIs, values, humanoids stripped) and kept in nil (never parented, so no
	script inside can ever run). Every clone: Anchored, CanCollide / CanTouch / CanQuery off (the Part walls and kits stay
	the colliders), CastShadow off unless the piece says Shadow = true, Massless. No lights, no scripts, no per-frame work.
	Folders: <plot>/WE_J67WallDress (beside WE_PerimeterWalls, rebuilt with it) and Workspace.WE_J67Props.Plot<N>. ]]

local InsertService = game:GetService("InsertService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local Cfg = require(Shared.Configs.Job67DressConfig)
local RetentionConfig = require(Shared.Configs.RetentionConfig)
local PlotFrame = require(Shared.Util.PlotFrame)

local Job67DressService = {}

local C: any = Cfg
local deps: { [string]: any } = {}

local WALL_FOLDER = "WE_J67WallDress"
local STRIP_CLASSES = {
	"LuaSourceContainer", "Light", "Sound", "ParticleEmitter", "Fire", "Smoke", "Sparkles", "Beam", "Trail",
	"ProximityPrompt", "ClickDetector", "BillboardGui", "SurfaceGui", "ScreenGui", "ValueBase", "Configuration",
	"Humanoid", "Tool", "Seat", "VehicleSeat", "Camera", "ForceField", "Explosion", "BodyMover", "Constraint",
	"JointInstance", "Animator", "AnimationController", "Dialog",
}

-- ===== live switches (pure on the config + owner) =====
function Job67DressService.Live(block: any, ownerUserId: number?): boolean
	if ownerUserId == nil or not RetentionConfig.Live(C, ownerUserId) then
		return false
	end
	return RetentionConfig.Live(block, ownerUserId)
end

-- ===== pack loading + audit =====
local packRoot: { [number]: Instance | false } = {}
local packBusy: { [number]: boolean } = {}
Job67DressService._audit = {} :: { [number]: string }

local function stripInstance(root: Instance): number
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do
		if d.Parent ~= nil then
			for _, cls in ipairs(STRIP_CLASSES) do
				if d:IsA(cls) then
					n += 1
					d:Destroy()
					break
				end
			end
		end
	end
	return n
end

local function loadPack(assetId: number): Instance?
	local have = packRoot[assetId]
	if have ~= nil then
		return if have == false then nil else have :: Instance
	end
	local waited = 0
	while packBusy[assetId] and waited < 30 do
		task.wait(0.25)
		waited += 0.25
	end
	have = packRoot[assetId]
	if have ~= nil then
		return if have == false then nil else have :: Instance
	end
	packBusy[assetId] = true
	local ok, result = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	packBusy[assetId] = nil
	if not ok or typeof(result) ~= "Instance" then
		packRoot[assetId] = false
		warn(C.LogTag, "pack load failed", assetId, tostring(result))
		return nil
	end
	local scripts = 0
	for _, d in ipairs(result:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then
			scripts += 1
		end
	end
	local stripped = stripInstance(result)
	packRoot[assetId] = result
	Job67DressService._audit[assetId] = string.format("scripts=%d stripped=%d", scripts, stripped)
	print(C.LogTag, "pack", assetId, "loaded", Job67DressService._audit[assetId])
	return result
end

local function meshNum(mp: MeshPart): string
	return string.match(mp.MeshId, "(%d+)$") or ""
end

-- the pack piece (a BasePart or a Model), never parented
local function findPiece(ref: any): Instance?
	local id = C.Packs[ref.Pack]
	if typeof(id) ~= "number" then
		return nil
	end
	local root = loadPack(id)
	if root == nil then
		return nil
	end
	if ref.MeshId then
		local want = tostring(ref.MeshId)
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("MeshPart") and meshNum(d) == want then
				return d
			end
		end
		return nil
	end
	if ref.Name then
		return root:FindFirstChild(ref.Name, true)
	end
	return nil
end

local function sanitizePart(p: BasePart, shadow: boolean)
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = shadow
	p.Massless = true
	p:SetAttribute("WE_J67", true)
end

-- template cache: key -> Model (pivot = bottom centre of its box, pack-world axes) | false
local templates: { [string]: Model | false } = {}

function Job67DressService.Template(key: string): Model?
	local have = templates[key]
	if have ~= nil then
		return if have == false then nil else have :: Model
	end
	local ref = C.Pieces[key]
	local src = if ref then findPiece(ref) else nil
	if src == nil then
		templates[key] = false
		warn(C.LogTag, "piece missing", key)
		return nil
	end
	local m = Instance.new("Model")
	m.Name = "J67_" .. key
	local copy = (src :: Instance):Clone()
	stripInstance(copy)
	copy.Parent = m
	local parts = 0
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			sanitizePart(d, ref.Shadow == true)
			parts += 1
		end
	end
	if parts == 0 then
		templates[key] = false
		return nil
	end
	local cf, size = m:GetBoundingBox()
	m.WorldPivot = CFrame.new(cf.Position - Vector3.new(0, size.Y * 0.5, 0))
	m:SetAttribute("WE_J67Parts", parts)
	templates[key] = m
	return m
end

-- a clone standing with its bottom centre at `at` (yaw from `at`)
function Job67DressService.Place(key: string, at: CFrame, parent: Instance): Model?
	local t = Job67DressService.Template(key)
	if t == nil then
		return nil
	end
	local m = t:Clone()
	m:PivotTo(at)
	m.Parent = parent
	return m
end

-- a Line piece fitted into a box: centre `centre` (its X axis = along the run), size along x height x depth
function Job67DressService.FitLine(key: string, centre: CFrame, along: number, height: number, depth: number, parent: Instance): BasePart?
	local ref = C.Pieces[key]
	local t = Job67DressService.Template(key)
	if ref == nil or t == nil or ref.Line ~= true then
		return nil
	end
	local src = t:FindFirstChildWhichIsA("MeshPart", true)
	if src == nil then
		return nil
	end
	local p = (src :: MeshPart):Clone()
	if ref.LongAxis == "Z" then
		p.Size = Vector3.new(depth, height, along)
		p.CFrame = centre * CFrame.Angles(0, math.pi * 0.5, 0)
	else
		p.Size = Vector3.new(along, height, depth)
		p.CFrame = centre
	end
	p.Parent = parent
	return p
end

-- ===== ground =====
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function groundAt(x: number, z: number, near: number, skip: { Instance }): number
	local list = table.clone(skip)
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			table.insert(list, pl.Character)
		end
	end
	rayParams.FilterDescendantsInstances = list
	local r = Workspace:Raycast(Vector3.new(x, near + 40, z), Vector3.new(0, -90, 0), rayParams)
	if r and math.abs(r.Position.Y - near) <= 6 then
		return r.Position.Y
	end
	return near
end

-- ===== walls =====
local function faceOf(name: string): string
	if string.sub(name, 1, 8) == "WallGate" then
		return "Gate"
	elseif string.sub(name, 1, 10) == "WallClosed" then
		return "Rear"
	end
	return "Sides"
end

local function has(list: { string }?, v: string): boolean
	for _, x in ipairs(list or {}) do
		if x == v then
			return true
		end
	end
	return false
end

Job67DressService._lastWalls = {} :: { [number]: { [string]: number } }

-- called by StructureKitBuilder.SyncPerimeterWalls after it (re)built `folder`; level 0 / not live = cleared
function Job67DressService.DressWalls(plotId: number, plotFolder: Instance, folder: Instance?, level: number, padTop: number, centre: Vector3, ownerUserId: number?)
	local old = plotFolder:FindFirstChild(WALL_FOLDER)
	if old then
		old:Destroy()
	end
	local W: any = C.Walls
	local tier: any = Cfg.WallTier(level)
	if folder == nil or tier == nil or not Job67DressService.Live(W, ownerUserId) then
		return nil
	end
	local out = Instance.new("Folder")
	out.Name = WALL_FOLDER
	out:SetAttribute("WE_WallTier", level)
	out:SetAttribute("WE_WallTierName", tier.Name)
	local skip: { Instance } = { out, folder :: Instance }
	local gateAxis = (folder :: Instance):GetAttribute("WE_GateAxis")
	local gateSign = tonumber((folder :: Instance):GetAttribute("WE_GateSign")) or 1
	local walls: { BasePart } = {}
	for _, ch in ipairs((folder :: Instance):GetChildren()) do
		local nm = ch.Name
		if ch:IsA("BasePart") and ch:GetAttribute("WE_Perimeter") == true and not ch:GetAttribute("WE_GateVisual")
			and string.sub(nm, 1, 4) == "Wall" and string.sub(nm, -4) ~= "_Cap" and string.sub(nm, -5) ~= "_Wire" then
			table.insert(walls, ch)
		end
	end
	table.sort(walls, function(a, b)
		local fa, fb = faceOf(a.Name), faceOf(b.Name)
		local order = { Gate = 1, Sides = 2, Rear = 3 }
		if fa ~= fb then
			return order[fa] < order[fb]
		end
		return a.Name < b.Name
	end)
	-- whole faces get Hesco while the budget allows
	local hescoFaces: { [string]: boolean } = {}
	do
		local need: { [string]: number } = { Gate = 0, Sides = 0, Rear = 0 }
		for _, w in ipairs(walls) do
			local along = math.max(w.Size.X, w.Size.Z)
			local n = Cfg.HescoSplit(along, w.Size.Y)
			need[faceOf(w.Name)] += n
		end
		local used = 0
		for _, f in ipairs({ "Gate", "Sides", "Rear" }) do
			if has(tier.Hesco, f) and used + need[f] <= (tier.MaxHesco or 0) then
				hescoFaces[f] = true
				used += need[f]
			end
		end
	end
	local stats = { Hesco = 0, Lines = 0, Props = 0 }
	local gx, gz = centre.X, centre.Z
	for _, w in ipairs(walls) do
		local face = faceOf(w.Name)
		local alongX = w.Size.X >= w.Size.Z
		local along = if alongX then w.Size.X else w.Size.Z
		local thick = if alongX then w.Size.Z else w.Size.X
		local h = w.Size.Y
		-- outward: from the pad centre to the wall line
		local outSign = if alongX then (if w.Position.Z >= gz then 1 else -1) else (if w.Position.X >= gx then 1 else -1)
		local rot = if alongX then CFrame.new() else CFrame.Angles(0, math.pi * 0.5, 0) -- local X = along the run
		local outDir = if alongX then Vector3.new(0, 0, outSign) else Vector3.new(outSign, 0, 0)
		local alongDir = if alongX then Vector3.new(1, 0, 0) else Vector3.new(0, 0, -1)
		local base = Vector3.new(w.Position.X, padTop, w.Position.Z)
		if hescoFaces[face] then
			local n, len = Cfg.HescoSplit(along, h)
			for i = 1, n do
				local off = -along * 0.5 + len * (i - 0.5)
				local c = base + alongDir * off + Vector3.new(0, h * 0.5, 0)
				if Job67DressService.FitLine("HescoBlock", CFrame.new(c) * rot, len + 0.05, h, thick + 1.2, out) then
					stats.Hesco += 1
				end
			end
			w.Transparency = 1
			w:SetAttribute("WE_J67Hidden", true)
			local cap = (folder :: Instance):FindFirstChild(w.Name .. "_Cap")
			if cap and cap:IsA("BasePart") then
				cap.Transparency = 1
			end
		end
		if has(tier.Lines, face) and not hescoFaces[face] then
			local natural = C.Pieces.SandbagLine.Natural
			local n = math.max(1, math.ceil(along / (natural.Z * W.LineStretch) - 1e-6))
			local len = along / n
			local depth = natural.X
			for i = 1, n do
				local off = -along * 0.5 + len * (i - 0.5)
				local p = base + alongDir * off + outDir * (thick * 0.5 + depth * 0.5 + 0.2)
				-- the gate face keeps GateClear studs either side of the gate centre open (nests, guards, road)
				local dGate = if gateAxis == "X" then math.abs(p.Z - gz) else math.abs(p.X - gx)
				if not (face == "Gate" and dGate < W.GateClear) then
					local y = groundAt(p.X, p.Z, padTop, skip)
					if Job67DressService.FitLine("SandbagLine", CFrame.new(p.X, y + natural.Y * 0.5, p.Z) * rot, len + 0.1, natural.Y, depth, out) then
						stats.Lines += 1
					end
				end
			end
		end
	end
	-- gate dressing: stacks / wire / blockades out in front of the gate, beyond GateClear
	do
		local gateDir = if gateAxis == "X" then Vector3.new(gateSign, 0, 0) else Vector3.new(0, 0, gateSign)
		local across = if gateAxis == "X" then Vector3.new(0, 0, 1) else Vector3.new(1, 0, 0)
		local faceDist = 0
		for _, w in ipairs(walls) do
			if faceOf(w.Name) == "Gate" then
				faceDist = if gateAxis == "X" then math.abs(w.Position.X - gx) else math.abs(w.Position.Z - gz)
				break
			end
		end
		if faceDist > 0 then
			local front = Vector3.new(gx, padTop, gz) + gateDir * faceDist
			local yaw = math.atan2(-gateDir.X, -gateDir.Z)
			local function put(key: string, side: number, a: number, outward: number)
				local p = front + across * (side * a) + gateDir * outward
				local y = groundAt(p.X, p.Z, padTop, skip)
				if Job67DressService.Place(key, CFrame.new(p.X, y, p.Z) * CFrame.Angles(0, yaw, 0), out) then
					stats.Props += 1
				end
			end
			for i = 1, (tier.GateStacks or 0) do
				local side = if i % 2 == 1 then -1 else 1
				local k = math.ceil(i / 2)
				put(if k == 2 then "SandbagStackLow" else "SandbagStack", side, W.GateClear + 4 + (k - 1) * 11, 7)
			end
			for i = 1, (tier.Wire or 0) do
				local side = if i % 2 == 1 then -1 else 1
				local k = math.ceil(i / 2)
				put(if k == 2 then "BarbedWireB" else "BarbedWire", side, W.GateClear + 2 + (k - 1) * 12, 18)
			end
			for i = 1, (tier.Blockades or 0) do
				local side = if i % 2 == 1 then -1 else 1
				local k = math.ceil(i / 2)
				put("Blockade", side, W.GateClear + 30 + (k - 1) * 11, 8)
			end
		end
	end
	-- corners: outside each corner of the ring
	if tier.CornerStacks then
		local hx, hz = 0, 0
		for _, w in ipairs(walls) do
			hx = math.max(hx, math.abs(w.Position.X - gx) + (if w.Size.X < w.Size.Z then w.Size.X * 0.5 else 0))
			hz = math.max(hz, math.abs(w.Position.Z - gz) + (if w.Size.Z < w.Size.X then w.Size.Z * 0.5 else 0))
		end
		for _, s in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
			local p = Vector3.new(gx + s[1] * (hx + 5), padTop, gz + s[2] * (hz + 5))
			local y = groundAt(p.X, p.Z, padTop, skip)
			local yaw = math.atan2(s[1], s[2])
			if Job67DressService.Place(if tier.Trench then "TrenchNest" else "SandbagStack", CFrame.new(p.X, y, p.Z) * CFrame.Angles(0, yaw, 0), out) then
				stats.Props += 1
			end
		end
	end
	out.Parent = plotFolder
	out:SetAttribute("WE_J67Hesco", stats.Hesco)
	out:SetAttribute("WE_J67HescoTris", stats.Hesco * (C.Pieces.HescoBlock.Tris or 0))
	out:SetAttribute("WE_J67Lines", stats.Lines)
	out:SetAttribute("WE_J67Props", stats.Props)
	Job67DressService._lastWalls[plotId] = stats
	print(string.format("%s walls plot=%d L%d %s hesco=%d (%d tris) sandbagLines=%d props=%d", C.LogTag, plotId, level, tier.Name, stats.Hesco, stats.Hesco * (C.Pieces.HescoBlock.Tris or 0), stats.Lines, stats.Props))
	return stats
end

-- ===== base props =====
local function propsRoot(): Folder
	local f = Workspace:FindFirstChild("WE_J67Props")
	if f == nil then
		local nf = Instance.new("Folder")
		nf.Name = "WE_J67Props"
		nf.Parent = Workspace
		f = nf
	end
	return f :: Folder
end

local plotOwner: { [number]: number } = {}
local plotTier: { [number]: number } = {}

function Job67DressService.LevelSum(upgrades: any): number
	local sum = 0
	if typeof(upgrades) ~= "table" then
		return 0
	end
	local okB, BaseConfig = pcall(function(): any
		return require(Shared.Configs.BaseConfig)
	end)
	local structures = if okB and BaseConfig then BaseConfig.Structures else nil
	for id, lv in pairs(upgrades) do
		if structures == nil or structures[id] ~= nil then
			sum += math.max(0, tonumber(lv) or 0)
		end
	end
	return sum
end

local function setWarzoneHidden(plotId: number, hidden: boolean)
	local okS, SKB = pcall(function(): any
		return require(script.Parent.Parent.Modules.StructureKitBuilder)
	end)
	local plotFolder = if okS and SKB and SKB.FindPlotFolder then SKB.FindPlotFolder(plotId) else nil
	local wz = if plotFolder then plotFolder:FindFirstChild("PlotWarzone") else nil
	if wz == nil then
		return
	end
	for _, d in ipairs(wz:GetDescendants()) do
		if d:IsA("BasePart") then
			if hidden then
				if d:GetAttribute("WE_J67HidT") == nil then
					d:SetAttribute("WE_J67HidT", d.Transparency)
					d:SetAttribute("WE_J67HidC", d.CanCollide)
				end
				d.Transparency = 1
				d.CanCollide = false
			else
				local t = d:GetAttribute("WE_J67HidT")
				if t ~= nil then
					d.Transparency = tonumber(t) or 0
					d.CanCollide = d:GetAttribute("WE_J67HidC") == true
					d:SetAttribute("WE_J67HidT", nil)
					d:SetAttribute("WE_J67HidC", nil)
				end
			end
		end
	end
end

-- BaseLifeService: does the owner's plot use the model clusters instead of this part kit?
function Job67DressService.ReplacesKit(kit: string, ownerUserId: number?): boolean
	local B: any = C.BaseProps
	return B.ReplacesKits[kit] == true and Job67DressService.Live(B, ownerUserId)
end

function Job67DressService.ClearProps(plotId: number)
	local f = propsRoot():FindFirstChild("Plot" .. plotId)
	if f then
		f:Destroy()
	end
	if plotOwner[plotId] ~= nil then
		pcall(setWarzoneHidden, plotId, false)
	end
	plotOwner[plotId] = nil
	plotTier[plotId] = nil
end

local function plotCf(plotId: number, lx: number, lz: number, yawDeg: number, skip: { Instance }): CFrame?
	local pos = PlotFrame.PlotPosition(plotId)
	if pos == nil then
		return nil
	end
	local cf = PlotFrame.PlotCFrame(pos) * CFrame.new(lx, 0, lz)
	local y = groundAt(cf.X, cf.Z, cf.Y, skip)
	return CFrame.new(cf.X, y, cf.Z) * cf.Rotation * CFrame.Angles(0, math.rad(yawDeg), 0)
end

-- (re)build the owner's prop clusters for a tier; returns the pieces placed
function Job67DressService.SyncProps(plotId: number, ownerUserId: number?, levelSum: number): number
	local B: any = C.BaseProps
	local tier = Cfg.PropTier(levelSum)
	if ownerUserId == nil or not Job67DressService.Live(B, ownerUserId) or tier <= 0 then
		Job67DressService.ClearProps(plotId)
		return 0
	end
	if plotOwner[plotId] == ownerUserId and plotTier[plotId] == tier and propsRoot():FindFirstChild("Plot" .. plotId) then
		return -1 -- unchanged
	end
	local old = propsRoot():FindFirstChild("Plot" .. plotId)
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = "Plot" .. plotId
	f:SetAttribute("WE_PropTier", tier)
	f:SetAttribute("OwnerUserId", ownerUserId)
	local skip: { Instance } = { f, propsRoot() }
	local spots: { any } = table.clone(B.Spots)
	local okL, BaseLayoutConfig = pcall(function(): any
		return require(Shared.Configs.BaseLayoutConfig)
	end)
	if okL and BaseLayoutConfig and BaseLayoutConfig.Enabled and BaseLayoutConfig.WarzoneSpots then
		for i, s in ipairs(BaseLayoutConfig.WarzoneSpots) do
			table.insert(spots, { X = s.X, Z = s.Z, Yaw = (i * 37) % 180, Kind = B.WarzoneKinds[i % 3] })
		end
	end
	local placed = 0
	for _, s in ipairs(spots) do
		local kind = B.Kinds[s.Kind]
		local anchor = if kind then plotCf(plotId, s.X, s.Z, s.Yaw or 0, skip) else nil
		if kind and anchor then
			for t = 1, tier do
				for _, row in ipairs(kind[t] or {}) do
					if placed >= B.MaxPieces then
						break
					end
					local at = anchor * CFrame.new(row[2], 0, row[3])
					local y = groundAt(at.X, at.Z, anchor.Y, skip)
					local cf = CFrame.new(at.X, y, at.Z) * at.Rotation * CFrame.Angles(0, math.rad(row[4] or 0), 0)
					if Job67DressService.Place(row[1], cf, f) then
						placed += 1
					end
				end
			end
		end
	end
	f.Parent = propsRoot()
	plotOwner[plotId] = ownerUserId
	plotTier[plotId] = tier
	if B.HideWarzone then
		pcall(setWarzoneHidden, plotId, true)
	end
	print(string.format("%s props plot=%d owner=%d levels=%d tier=%d pieces=%d", C.LogTag, plotId, ownerUserId, levelSum, tier, placed))
	return placed
end

local function profileOf(userId: number): any
	local ds = deps.DataService
	local pl = Players:GetPlayerByUserId(userId)
	if ds and ds.GetProfile and pl then
		local ok, p = pcall(ds.GetProfile, pl)
		if ok then
			return p
		end
	end
	return nil
end

local function syncOwnerProps(player: Player, plotId: number)
	local prof = profileOf(player.UserId)
	local sum = if prof then Job67DressService.LevelSum(prof.BaseUpgrades) else 0
	local ok, err = pcall(Job67DressService.SyncProps, plotId, player.UserId, sum)
	if not ok then
		warn(C.LogTag, "SyncProps failed", err)
	end
end

function Job67DressService.Init(d: { [string]: any })
	deps = d
	if not C.Enabled then
		return
	end
	local bs = d.BaseService
	if bs and bs.OnPlotReady then
		pcall(bs.OnPlotReady, function(player: Player, plotId: number)
			task.defer(function()
				if player.Parent then
					syncOwnerProps(player, plotId)
				end
			end)
		end)
	end
	if bs and bs.GetUpgradeChangedEvent then
		pcall(function()
			bs.GetUpgradeChangedEvent().Event:Connect(function(userId: number, plotId: any)
				local pl = Players:GetPlayerByUserId(userId)
				local pid = tonumber(plotId)
				if pl and pid then
					task.defer(syncOwnerProps, pl, pid)
				end
			end)
		end)
	end
	Players.PlayerRemoving:Connect(function(p: Player)
		for plotId, uid in pairs(plotOwner) do
			if uid == p.UserId then
				Job67DressService.ClearProps(plotId)
			end
		end
	end)
	print("[WAR EMPIRE] Job67DressService Init")
end

return Job67DressService
