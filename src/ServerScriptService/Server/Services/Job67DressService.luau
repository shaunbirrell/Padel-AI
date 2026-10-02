--!strict
--[[ Code Bot JOB 67 remainder (2026-10-02): the owned-asset dressing (Shared/Configs/Job67DressConfig, the one config).
	Batch 1: perimeter walls (sandbag -> Hesco tiers from the saved DefensiveWalls level) and base prop clusters (grow
	with the sum of the saved structure levels). Owner-first by the BASE OWNER (RetentionConfig.Live): only the playtest
	owner's base wears it; everyone sees his base.

	Packs load once per server (InsertService:LoadAsset, never on the boot path: the first wall / plot sync asks), are
	audited (scripts, lights, sounds, FX, prompts, GUIs, values, humanoids stripped) and kept in nil (never parented, so no
	script inside can ever run). Every clone: Anchored, CanCollide / CanTouch / CanQuery off (the Part walls and kits stay
	the colliders), CastShadow off unless the piece says Shadow = true, Massless. No lights, no scripts, no per-frame work.
	Folders: <plot>/WE_J67WallDress (beside WE_PerimeterWalls, rebuilt with it) and Workspace.WE_J67Props.Plot<N>.
	Batch 2: Workspace.WE_J67Buildings = detailed desert buildings over the outlying places' TownBlock kits (Buildings
	block; world dressing, live once a player it is live for is in the server). The kit parts go invisible and stop
	colliding (lights / guis off, all restored by ClearBuildings); the building's large parts are the colliders.
	claude-bud JOB 70 (LIVE FOR EVERYONE): every wall / prop clone also gets ONE invisible Box hull (createHull: anchored,
	CanCollide + CanQuery on, sized to the visual) so nothing is walk-through, and the wall tier's ONE style
	(Cfg.WallStyleFor) dresses every face: front / gate, both sides and the rear. ]]

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

-- claude-bud JOB 70 (LIVE FOR EVERYONE): ONE cheap invisible Box hull per placed prop / wall visual segment, sized to the
-- visual's bounds (Model: its bounding box; a fitted part: its CFrame / Size). Anchored, CanCollide + CanQuery on, CanTouch
-- off, Transparency 1, no shadow; the visual's own parts stay CanCollide = false (sanitizePart). `count` = the folder
-- whose WE_J67Hulls attribute caps the hulls (PropCollision.MaxHullsPerFolder). No per-frame work.
function Job67DressService.HullsLive(): boolean
	local K: any = C.PropCollision
	return K ~= nil and K.Enabled == true and RetentionConfig.Live(K, nil) == true
end

local function createHull(visual: Instance, key: string, parent: Instance, count: Instance): BasePart?
	local K: any = C.PropCollision
	if not Job67DressService.HullsLive() then
		return nil
	end
	local n = tonumber(count:GetAttribute("WE_J67Hulls")) or 0
	if n >= (tonumber(K.MaxHullsPerFolder) or 220) then
		return nil
	end
	local cf: CFrame, size: Vector3
	if visual:IsA("Model") then
		cf, size = visual:GetBoundingBox()
	elseif visual:IsA("BasePart") then
		cf, size = visual.CFrame, visual.Size
	else
		return nil
	end
	local m = tonumber(K.MinHullStuds) or 0.6
	local h = Instance.new("Part")
	h.Name = "J67Hull"
	h.Shape = Enum.PartType.Block
	h.Size = Vector3.new(math.max(m, size.X), math.max(m, size.Y), math.max(m, size.Z))
	h.CFrame = cf
	h.Anchored = true
	h.CanCollide = true -- players and soldiers stop here (PropCollision.HullCanCollide)
	h.CanQuery = true -- shots / line of sight see the cover (PropCollision.HullCanQuery)
	h.CanTouch = false
	h.Transparency = 1
	h.CastShadow = false
	h.Material = Enum.Material.SmoothPlastic
	h:SetAttribute("WE_J67Hull", key)
	h:SetAttribute("WE_J67Category", Cfg.CategoryOf(key) or "?")
	h.Parent = parent
	count:SetAttribute("WE_J67Hulls", n + 1)
	return h
end

-- a clone standing with its bottom centre at `at` (yaw from `at`); claude-bud JOB 70: + its Box hull (inside the model)
function Job67DressService.Place(key: string, at: CFrame, parent: Instance): Model?
	local t = Job67DressService.Template(key)
	if t == nil then
		return nil
	end
	local m = t:Clone()
	m:PivotTo(at)
	createHull(m, key, m, parent)
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
	createHull(p, key, parent, parent) -- claude-bud JOB 70: the fitted segment's Box hull
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
	-- claude-bud JOB 70: the tier's ONE wall style for EVERY face (front / gate, both sides, rear): Hesco on every run
	-- when the whole ring fits MaxHesco (stretch up to HescoStretchMax), else the tier's FallbackStyle on every run;
	-- never a face left on the old Part look and never a front-only dressing
	local style: any = Cfg.WallStyleFor(level)
	local runs: { number } = {}
	for i, w in ipairs(walls) do
		runs[i] = math.max(w.Size.X, w.Size.Z)
	end
	local hescoCounts: { number }? = nil
	local hescoStretch: number? = nil
	if style.Hesco and #walls > 0 then
		hescoStretch, hescoCounts = Cfg.HescoPlan(runs, walls[1].Size.Y, tier.MaxHesco or 0)
		if hescoCounts == nil then
			style = { Kind = style.FallbackStyle, Rows = W.WallStyle[style.FallbackStyle].Rows or 1, Hesco = false, Faces = style.Faces }
			warn(string.format("%s walls plot=%d L%d: Hesco does not fit MaxHesco %d on every face; every face uses %s", C.LogTag, plotId, level, tier.MaxHesco or 0, style.Kind))
		end
	end
	out:SetAttribute("WE_WallStyle", style.Kind)
	out:SetAttribute("WE_WallFaces", table.concat(style.Faces, ","))
	local stats: any = { Hesco = 0, Lines = 0, Props = 0, Faces = {} }
	local gx, gz = centre.X, centre.Z
	for wi, w in ipairs(walls) do
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
		local before = stats.Hesco + stats.Lines
		if style.Hesco and hescoCounts then
			local n = hescoCounts[wi]
			local len = along / n
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
		else
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
					for r = 1, math.max(1, style.Rows or 1) do -- Rows 2 = a sandbag wall: the second course on the first
						if Job67DressService.FitLine("SandbagLine", CFrame.new(p.X, y + natural.Y * (r - 0.5), p.Z) * rot, len + 0.1, natural.Y, depth, out) then
							stats.Lines += 1
						end
					end
				end
			end
		end
		stats.Faces[face] = (stats.Faces[face] or 0) + (stats.Hesco + stats.Lines - before)
	end
	if hescoStretch then
		out:SetAttribute("WE_J67HescoStretch", hescoStretch)
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
	print(string.format("%s walls plot=%d L%d %s style=%s (every face) hesco=%d (%d tris) sandbagLines=%d props=%d hulls=%d", C.LogTag, plotId, level, tier.Name, style.Kind, stats.Hesco, stats.Hesco * (C.Pieces.HescoBlock.Tris or 0), stats.Lines, stats.Props, tonumber(out:GetAttribute("WE_J67Hulls")) or 0))
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

-- ===== Batch 2 / 3: detailed models over the outlying places' Part kits (Job67DressConfig.Buildings / .Wrecks) =====
-- One code path for every WORLD block (WorldBlocks): each row = a POI cluster's kit (row.Kit, default TownBlock; the
-- row.KitIndex-th such kit) -> a pack model fitted to the kit footprint (the kit's Width x Depth, or row.Box in the
-- kit frame), bottom on the kit floor. Collide = "Model" (default): the kit goes invisible + non-colliding and the
-- model's big parts collide; Collide = "Kit": the kit only goes invisible and stays the collider (the model is visual).
local WORLD_BLOCKS = { { Key = "Buildings", Folder = "WE_J67Buildings" }, { Key = "Wrecks", Folder = "WE_J67Wrecks" } }
local worldTemplates: { [string]: Model | false } = {}
local hiddenKit: { [string]: { Instance } } = {} -- "<block>/<Poi>/<Cluster>/<kit index>" -> the kit instances hidden
local worldOn: { [string]: boolean } = {}
local layoutCache: { [string]: any } = {}

-- a world block is live once a player it is live for is in this server (the JOB 40 rule); OwnerFirst off = everyone
function Job67DressService.WorldLive(B: any): boolean
	if typeof(B) ~= "table" or B.Enabled ~= true or C.Enabled ~= true then
		return false
	end
	if B.OwnerFirst ~= true and C.OwnerFirst ~= true then
		return true
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if Job67DressService.Live(B, p.UserId) then
			return true
		end
	end
	return false
end

function Job67DressService.BuildingsLive(): boolean
	return Job67DressService.WorldLive(C.Buildings)
end

function Job67DressService.WorldTemplate(B: any, key: string): Model?
	local tkey = tostring(B.Tag or "") .. "/" .. key
	local have = worldTemplates[tkey]
	if have ~= nil then
		return if have == false then nil else have :: Model
	end
	local ref = B.Models[key]
	local id = if ref then C.Packs[ref.Pack] else nil
	local root = if typeof(id) == "number" then loadPack(id) else nil
	local src = if root and ref then (root :: Instance):FindFirstChild(ref.Name, true) else nil
	if src == nil or not ((src :: Instance):IsA("Model") or (src :: Instance):IsA("BasePart")) then
		worldTemplates[tkey] = false
		warn(C.LogTag, "world model missing", key)
		return nil
	end
	local m: Model
	if (src :: Instance):IsA("Model") then
		m = (src :: Model):Clone()
	else
		m = Instance.new("Model")
		;(src :: Instance):Clone().Parent = m
	end
	stripInstance(m)
	m.Name = "J67_" .. key
	local collideModel = (ref.Collide or B.Collide or "Model") == "Model"
	local parts = 0
	local mn, mx = Vector3.one * math.huge, Vector3.one * -math.huge
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			local mxs = math.max(d.Size.X, d.Size.Y, d.Size.Z)
			sanitizePart(d, mxs >= (B.ShadowMinStuds or 8))
			if collideModel and mxs >= (B.CollideMinStuds or 4) then
				d.CanCollide = true -- the model is the collider now (the kit under it stops colliding)
				d.CanQuery = true
			end
			parts += 1
			local cf, s = d.CFrame, d.Size * 0.5
			local ext = Vector3.new(
				math.abs(cf.RightVector.X) * s.X + math.abs(cf.UpVector.X) * s.Y + math.abs(cf.LookVector.X) * s.Z,
				math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z,
				math.abs(cf.RightVector.Z) * s.X + math.abs(cf.UpVector.Z) * s.Y + math.abs(cf.LookVector.Z) * s.Z
			)
			mn = mn:Min(cf.Position - ext)
			mx = mx:Max(cf.Position + ext)
		end
	end
	if parts == 0 then
		worldTemplates[tkey] = false
		return nil
	end
	-- pivot = the bottom centre of the world-axis box, unrotated (the Turn / kit yaw are applied at placement)
	m.WorldPivot = CFrame.new((mn.X + mx.X) * 0.5, mn.Y, (mn.Z + mx.Z) * 0.5)
	m:SetAttribute("WE_J67Parts", parts)
	m:SetAttribute("WE_J67Natural", mx - mn)
	worldTemplates[tkey] = m
	return m
end

function Job67DressService.BuildingTemplate(key: string): Model?
	return Job67DressService.WorldTemplate(C.Buildings, key)
end

-- the POILayouts cluster row + its n-th kit of that kind for a POI / cluster id
local function clusterRow(poiId: string, clusterId: string, kitName: string?, kitIndex: number?): (any, any)
	local okW, WorldConfig = pcall(function(): any
		return require(Shared.Configs.WorldConfig)
	end)
	if not okW then
		return nil, nil
	end
	local layout: string? = nil
	for _, p in ipairs(WorldConfig.POIs or {}) do
		if p.Id == poiId then
			layout = p.Layout
		end
	end
	if layout == nil then
		return nil, nil
	end
	local group = layoutCache[layout :: string]
	if group == nil then
		local mod = script.Parent.Parent:FindFirstChild("Modules")
		mod = mod and mod:FindFirstChild("POILayouts")
		mod = mod and mod:FindFirstChild(layout :: string)
		local ok, got = pcall(function(): any
			return (require :: any)(mod)
		end)
		group = if ok and type(got) == "table" then got else false
		layoutCache[layout :: string] = group
	end
	local l = if group then group[poiId] else nil
	local want, nth, seen = kitName or "TownBlock", kitIndex or 1, 0
	for _, c in ipairs(if l then l.Clusters or {} else {}) do
		if c.Id == clusterId then
			for _, k in ipairs(c.Kits or {}) do
				if k.Kit == want then
					seen += 1
					if seen == nth then
						return c, k
					end
				end
			end
		end
	end
	return nil, nil
end

local function hideKit(key: string, cluster: Instance, kcf: CFrame, hw: number, hd: number, keepCollide: boolean)
	local list: { Instance } = {}
	for _, d in ipairs(cluster:GetDescendants()) do
		if d:IsA("BasePart") then
			local lp = kcf:PointToObjectSpace(d.Position)
			if math.abs(lp.X) <= hw + 2 and math.abs(lp.Z) <= hd + 2 then
				d:SetAttribute("WE_J67T", d.Transparency)
				d:SetAttribute("WE_J67C", d.CanCollide)
				d:SetAttribute("WE_J67Q", d.CanQuery)
				d.Transparency = 1
				if not keepCollide then
					d.CanCollide = false -- the model took over
					d.CanQuery = false
				end
				table.insert(list, d)
				for _, x in ipairs(d:GetDescendants()) do
					if x:IsA("Decal") then -- Decal + Texture
						x:SetAttribute("WE_J67T", x.Transparency)
						x.Transparency = 1
						table.insert(list, x)
					elseif x:IsA("Light") or x:IsA("SurfaceGui") or x:IsA("BillboardGui") then
						x:SetAttribute("WE_J67E", (x :: any).Enabled)
						;(x :: any).Enabled = false
						table.insert(list, x)
					end
				end
			end
		end
	end
	hiddenKit[key] = list
	return #list
end

local function restoreKit(key: string)
	for _, x in ipairs(hiddenKit[key] or {}) do
		if x.Parent ~= nil then
			local t0 = x:GetAttribute("WE_J67T")
			if typeof(t0) == "number" then
				(x :: any).Transparency = t0
			end
			local c0, q0 = x:GetAttribute("WE_J67C"), x:GetAttribute("WE_J67Q")
			if x:IsA("BasePart") then
				if typeof(c0) == "boolean" then
					x.CanCollide = c0
				end
				if typeof(q0) == "boolean" then
					x.CanQuery = q0
				end
			end
			x:SetAttribute("WE_J67C", nil)
			x:SetAttribute("WE_J67Q", nil)
			local e0 = x:GetAttribute("WE_J67E")
			if typeof(e0) == "boolean" then
				(x :: any).Enabled = e0
			end
			x:SetAttribute("WE_J67T", nil)
			x:SetAttribute("WE_J67E", nil)
		end
	end
	hiddenKit[key] = nil
end

local function clearWorld(blockKey: string, folderName: string)
	for key in pairs(hiddenKit) do
		if string.sub(key, 1, #blockKey + 1) == blockKey .. "/" then
			restoreKit(key)
		end
	end
	local f = Workspace:FindFirstChild(folderName)
	if f then
		f:Destroy()
	end
	worldOn[blockKey] = false
end

function Job67DressService.ClearBuildings()
	clearWorld("Buildings", "WE_J67Buildings")
end

function Job67DressService.ClearWorld()
	for _, wb in ipairs(WORLD_BLOCKS) do
		clearWorld(wb.Key, wb.Folder)
	end
end

-- dress one world block (idempotent: clears and rebuilds). Returns the models placed.
local function syncWorld(blockKey: string, folderName: string): number
	local B = C[blockKey]
	clearWorld(blockKey, folderName)
	if typeof(B) ~= "table" or not Job67DressService.WorldLive(B) then
		return 0
	end
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	local wd = setup and setup:FindFirstChild("WorldDressing")
	if wd == nil then
		return 0
	end
	local out = Instance.new("Folder")
	out.Name = folderName
	local placed, parts = 0, 0
	local perPoi: { [string]: number } = {}
	for _, row in ipairs(B.Rows) do
		if placed >= (B.MaxModels or 12) or (perPoi[row.Poi] or 0) >= (B.MaxPerPoi or 2) then
			continue
		end
		local poiFolder = (wd :: Instance):FindFirstChild("POI_" .. row.Poi)
		local cluster = poiFolder and poiFolder:FindFirstChild(row.Cluster)
		local c, k = clusterRow(row.Poi, row.Cluster, row.Kit, row.KitIndex)
		local ref = B.Models[row.Model]
		local t = Job67DressService.WorldTemplate(B, row.Model)
		if cluster == nil or c == nil or k == nil or ref == nil or t == nil then
			print(string.format("%s %s %s/%s: skipped (cluster=%s row=%s model=%s)", C.LogTag, blockKey, row.Poi, row.Cluster, tostring(cluster ~= nil), tostring(c ~= nil), tostring(t ~= nil)))
			continue
		end
		-- the kit footprint in its own frame: row.Box (X0, X1, Z0, Z1) or the kit's Width x Depth round its centre
		local box = row.Box or B.Boxes and B.Boxes[row.Kit or "TownBlock"] and B.Boxes[row.Kit or "TownBlock"][k.Variant or "default"]
		local bx0, bx1, bz0, bz1
		if typeof(box) == "table" then
			bx0, bx1, bz0, bz1 = box[1], box[2], box[3], box[4]
		else
			bx0, bx1, bz0, bz1 = -(k.Width or 20) * 0.5, (k.Width or 20) * 0.5, -(k.Depth or 16) * 0.5, (k.Depth or 16) * 0.5
		end
		local hw, hd = (bx1 - bx0) * 0.5, (bz1 - bz0) * 0.5
		local frameK = CFrame.new(c.X, 0, c.Z) * CFrame.Angles(0, math.rad(c.Yaw or 0), 0) * CFrame.new(k.X or 0, 0, k.Z or 0) * CFrame.Angles(0, math.rad(k.Yaw or 0), 0)
		local frame0 = frameK * CFrame.new((bx0 + bx1) * 0.5, 0, (bz0 + bz1) * 0.5)
		-- the kit floor: the lowest kit part bottom in the footprint
		local floorY = math.huge
		for _, d in ipairs((cluster :: Instance):GetDescendants()) do
			if d:IsA("BasePart") then
				local lp = frame0:PointToObjectSpace(Vector3.new(d.Position.X, 0, d.Position.Z))
				if math.abs(lp.X) <= hw + 2 and math.abs(lp.Z) <= hd + 2 then
					floorY = math.min(floorY, d.Position.Y - d.Size.Y * 0.5)
				end
			end
		end
		if floorY == math.huge then
			continue
		end
		local nat = t:GetAttribute("WE_J67Natural") :: Vector3
		local turned = math.abs((ref.Turn or 0) % 180) == 90
		local nx, nz = if turned then nat.Z else nat.X, if turned then nat.X else nat.Z
		local s = math.min((hw * 2) / nx, (hd * 2) / nz) * (ref.Grow or B.Grow or 1)
		s = math.clamp(s, ref.ScaleMin or B.ScaleMin or 0.45, ref.ScaleMax or B.ScaleMax or 1.2)
		local m = t:Clone()
		m:ScaleTo(m:GetScale() * s) -- relative: a pack model can ship at a non-1 scale (Synty models are at 2)
		local kcf = CFrame.new(frame0.Position.X, floorY, frame0.Position.Z) * (frame0 - frame0.Position)
		m:PivotTo(kcf * CFrame.Angles(0, math.rad((ref.Turn or 0) + (row.Yaw or 0)), 0))
		m:SetAttribute("WE_J67Poi", row.Poi)
		m:SetAttribute("WE_J67Cluster", row.Cluster)
		m:SetAttribute("WE_J67Scale", s)
		m.Parent = out
		local keepCollide = (ref.Collide or B.Collide or "Model") == "Kit"
		local hid = hideKit(blockKey .. "/" .. row.Poi .. "/" .. row.Cluster .. "/" .. tostring(row.KitIndex or 1), cluster :: Instance, kcf, hw, hd, keepCollide)
		placed += 1
		perPoi[row.Poi] = (perPoi[row.Poi] or 0) + 1
		parts += (t:GetAttribute("WE_J67Parts") :: number) or 0
		print(string.format("%s %s %s/%s -> %s scale=%.2f kit=%.0fx%.0f hidden=%d", C.LogTag, blockKey, row.Poi, row.Cluster, row.Model, s, hw * 2, hd * 2, hid))
	end
	out.Parent = Workspace
	worldOn[blockKey] = placed > 0
	out:SetAttribute("WE_J67Models", placed)
	out:SetAttribute("WE_J67Parts", parts)
	print(string.format("%s %s: %d models, %d parts", C.LogTag, blockKey, placed, parts))
	return placed
end

-- claude-bud (rebirth-zone buildings): the main block building of one built zone -> a detailed desert house
-- (Cfg.ZoneBuildings). Called by RebirthZoneService right after the zone's Part build; returns the model or nil.
function Job67DressService.DressZone(folder: Instance, zoneId: string, frame: CFrame, ownerUserId: number?): Model?
	local Z: any = C.ZoneBuildings
	local row = if typeof(Z) == "table" and typeof(Z.Rows) == "table" then Z.Rows[zoneId] else nil
	if row == nil or Z.Enabled ~= true or C.Enabled ~= true or not Job67DressService.Live(Z, ownerUserId) then
		return nil
	end
	if folder:GetAttribute("WE_StoreProps") == "on" then
		return nil -- the zone already wears store models (no block building left)
	end
	-- the target cluster: the one named row.Cluster nearest row.At (zone frame)
	local want = frame * Vector3.new(row.At[1], 0, row.At[2])
	local best: Model? = nil
	local bestD = math.huge
	for _, c in ipairs(folder:GetChildren()) do
		if c:IsA("Model") and c.Name == row.Cluster then
			local d = (c:GetPivot().Position - want).Magnitude
			local cf = c:GetBoundingBox()
			d = math.min(d, (Vector3.new(cf.X, want.Y, cf.Z) - want).Magnitude)
			if d < bestD then
				best, bestD = c, d
			end
		end
	end
	if best == nil then
		return nil
	end
	local t = Job67DressService.WorldTemplate(C.Buildings, row.Model)
	if t == nil then
		return nil
	end
	-- the plot's budget (houses already on this plot's zones)
	local plotParts = 0
	local pf = folder.Parent
	if pf then
		for _, z in ipairs(pf:GetChildren()) do
			local h = z:FindFirstChild("J67Zone")
			if h then
				plotParts += tonumber(h:GetAttribute("WE_J67Parts")) or 0
			end
		end
	end
	local parts = tonumber(t:GetAttribute("WE_J67Parts")) or 0
	if plotParts + parts > (Z.MaxPartsPerPlot or 1300) then
		print(string.format("%s zone %s: kept the block building (plot budget %d + %d)", C.LogTag, zoneId, plotParts, parts))
		return nil
	end
	-- the cluster footprint in the zone frame + its floor
	local x0, x1, z0, z1, floorY = math.huge, -math.huge, math.huge, -math.huge, math.huge
	for _, d in ipairs((best :: Model):GetDescendants()) do
		if d:IsA("BasePart") then
			local h = d.Size * 0.5
			for _, sx in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local l = frame:PointToObjectSpace((d.CFrame * CFrame.new(h.X * sx, 0, h.Z * sz)).Position)
					x0, x1, z0, z1 = math.min(x0, l.X), math.max(x1, l.X), math.min(z0, l.Z), math.max(z1, l.Z)
				end
			end
			floorY = math.min(floorY, d.Position.Y - d.Size.Y * 0.5)
		end
	end
	if floorY == math.huge then
		return nil
	end
	local yard = folder:FindFirstChild(zoneId .. "_Yard")
	local slab = yard and yard:FindFirstChild("ZoneYard", true)
	if slab and slab:IsA("BasePart") then
		floorY = slab.Position.Y + slab.Size.Y * 0.5
	end
	local ref = C.Buildings.Models[row.Model]
	local yaw = (ref.Turn or 0) + (row.Yaw or 0)
	local s = Cfg.ZoneFit(t:GetAttribute("WE_J67Natural") :: Vector3, x1 - x0, z1 - z0, math.abs(yaw % 180) == 90)
	local m = t:Clone()
	m.Name = "J67Zone"
	m:ScaleTo(m:GetScale() * s)
	local c = frame * CFrame.new((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5)
	m:PivotTo(CFrame.new(c.X, floorY, c.Z) * frame.Rotation * CFrame.Angles(0, math.rad(yaw), 0))
	m:SetAttribute("WE_J67Parts", parts)
	m:SetAttribute("WE_J67Zone", zoneId)
	m:SetAttribute("WE_J67Scale", s)
	m:SetAttribute("WE_J67Replaced", row.Cluster)
	;(best :: Model):Destroy() -- the block building goes; the house's big parts collide
	m.Parent = folder
	print(string.format("%s zone %s: %s -> %s scale=%.2f footprint=%.0fx%.0f parts=%d", C.LogTag, zoneId, row.Cluster, row.Model, s, x1 - x0, z1 - z0, parts))
	return m
end

function Job67DressService.SyncBuildings(): number
	return syncWorld("Buildings", "WE_J67Buildings")
end

function Job67DressService.SyncWorld(): number
	local n = 0
	for _, wb in ipairs(WORLD_BLOCKS) do
		n += syncWorld(wb.Key, wb.Folder)
	end
	return n
end

local function anyWorldOn(): boolean
	for _, v in pairs(worldOn) do
		if v then
			return true
		end
	end
	return false
end

local worldBusy = false
local function syncWorldSoon()
	if worldBusy then
		return
	end
	worldBusy = true
	task.delay(2, function()
		worldBusy = false
		local ok, err = pcall(Job67DressService.SyncWorld)
		if not ok then
			warn(C.LogTag, "SyncWorld failed", err)
		end
	end)
end
Job67DressService._syncWorldSoon = syncWorldSoon

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
	-- batches 2 + 3: the world blocks (once a live player is here; a rebuilt POI folder is dressed again)
	Players.PlayerAdded:Connect(function(p: Player)
		for _, wb in ipairs(WORLD_BLOCKS) do
			if not worldOn[wb.Key] and typeof(C[wb.Key]) == "table" and Job67DressService.Live(C[wb.Key], p.UserId) then
				syncWorldSoon()
				break
			end
		end
	end)
	task.defer(function()
		local setup = Workspace:WaitForChild("WarEmpireSetup", 120)
		local wd = setup and setup:WaitForChild("WorldDressing", 120)
		if wd then
			wd.ChildAdded:Connect(function(ch: Instance)
				if anyWorldOn() and string.sub(ch.Name, 1, 4) == "POI_" then
					syncWorldSoon()
				end
			end)
		end
		for _, wb in ipairs(WORLD_BLOCKS) do
			if Job67DressService.WorldLive(C[wb.Key]) then
				syncWorldSoon()
				break
			end
		end
	end)
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
