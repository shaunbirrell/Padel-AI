--!strict
--[[
	Code Bot STORE-PROPS (v132, 2026-09-30): places the owner's Creator Store picks (Shared/Configs/StorePropsConfig,
	docs/PROP-ASSETS.md). Server only. DO NOT REMOVE (CLAUDE.md): the store props live in StorePropsConfig.

	Init(deps) (after RebirthZoneService):
	  1. templates: each needed id is loaded ONCE (InsertService:LoadAsset, one at a time, LoadGapSeconds apart; the
	     zone ids first), cleaned (clean()) and kept in ServerStorage.WE_StorePropTemplates with its pivot at the
	     bottom centre of the visible parts (world-aligned, as the creator built it). Status per id: Status(id).
	  2. world: after the JOB 31 sites stand (WorldFill.Sites WE_SiteParts, or SiteWaitSeconds) and, while OwnerFirst,
	     once a player it is live for is in the server, every WorldRows copy is placed under WorldFill.StoreProps
	     (spot(): open, level ground / pavement or a flat roof; off roads; clear of every part; far from the plots),
	     a few per frame, until Budget.MaxWorldParts. If WorldFill is rebuilt, the dressing is placed again.
	  3. zones: every "Zone_<Id>" folder RebirthZoneService builds under WE_RebirthZones is looked at once it is
	     finished (deferred). At level >= 1, for a plot owner it is live for, with a ZoneRows layout that fits (yard,
	     console lane, no overlaps, budget), the Part complex is swapped for the store models; otherwise nothing is
	     touched. RebirthZoneService and RebirthZoneBuilder are not modified.
	Kill: StorePropsConfig.Enabled = false (Init does nothing); Workspace attribute WE_StorePropsOff = true removes
	every copy and asks RebirthZoneService to rebuild the Part zones.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Configs.StorePropsConfig)
local RebirthZonesConfig = require(Shared.Configs.RebirthZonesConfig)
local WorldSitesConfig = require(Shared.Configs.WorldSitesConfig)
local BaseConfig = require(Shared.Configs.BaseConfig)
local PlotFrame = require(Shared.Util.PlotFrame)
local MapAreas = require(Shared.Util.MapAreas)

local StorePropsService = {}

type Tpl = { State: string, Model: Model?, Size: Vector3, Parts: number, Err: string? }

local deps: { [string]: any } = {}
local templates: { [number]: Tpl } = {}
local stats = { WorldPlaced = 0, WorldParts = 0, WorldFailed = 0, ZoneSwaps = 0, ZoneParts = 0, ZoneKept = 0 }
local placedById: { [number]: number } = {}
local failedRows: { string } = {}
local zoneParts: { [Instance]: { Plot: number, Parts: number } } = {}
local worldFolder: Folder? = nil
local worldRuns = 0
local killed = false

local function log(fmt: string, ...: any)
	print("[StoreProps] " .. string.format(fmt, ...))
end

local function off(): boolean
	return killed or Cfg.Enabled ~= true or Workspace:GetAttribute(Cfg.LiveAttribute) == true
end

-- ── templates ─────────────────────────────────────────────────────────────────────────────────────────────────────
local STRIP = {
	"LuaSourceContainer", "Humanoid", "Sound", "ProximityPrompt", "ClickDetector", "Dialog", "BodyMover", "Constraint",
	"JointInstance", "WeldConstraint", "NoCollisionConstraint", "ParticleEmitter", "Fire", "Smoke", "Sparkles", "Beam",
	"Trail", "Explosion", "ForceField", "Tool", "BillboardGui", "ScreenGui", "RemoteEvent", "RemoteFunction",
	"BindableEvent", "BindableFunction", "AnimationController", "Animator", "Attachment",
}

local function templatesFolder(): Folder
	local f = ServerStorage:FindFirstChild("WE_StorePropTemplates")
	if f == nil then
		local nf = Instance.new("Folder")
		nf.Name = "WE_StorePropTemplates"
		nf.Parent = ServerStorage
		f = nf
	end
	return f :: Folder
end

local function isStripped(d: Instance): boolean
	for _, c in ipairs(STRIP) do
		if d:IsA(c) then
			-- an Attachment only goes when nothing (a light) hangs on it
			if c == "Attachment" and #d:GetChildren() > 0 then
				return false
			end
			return true
		end
	end
	return false
end

-- the world-aligned box of the visible parts
local function visibleBox(root: Instance): (Vector3?, Vector3?)
	local mn, mx = nil :: Vector3?, nil :: Vector3?
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.95 then
			local h = d.Size * 0.5
			local cf = d.CFrame
			local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
			local ext = Vector3.new(
				math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z,
				math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z,
				math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z
			)
			local a, b = cf.Position - ext, cf.Position + ext
			mn = if mn then (mn :: Vector3):Min(a) else a
			mx = if mx then (mx :: Vector3):Max(b) else b
		end
	end
	return mn, mx
end

-- clean a loaded asset in place; returns the part count left
local function clean(root: Instance): number
	local kill: { Instance } = {}
	for _, d in ipairs(root:GetDescendants()) do
		if isStripped(d) then
			table.insert(kill, d)
		end
	end
	for _, d in ipairs(kill) do
		pcall(function()
			d:Destroy()
		end)
	end
	local parts, lights = 0, 0
	local drop: { Instance } = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Transparency >= 0.95 and not d.CanCollide then
				table.insert(drop, d)
				continue
			end
			d.Anchored = true
			d.CanTouch = false
			pcall(function()
				d.Locked = true
			end)
			if d:IsA("Seat") or d:IsA("VehicleSeat") then
				(d :: any).Disabled = true
			end
			parts += 1
		elseif d:IsA("Light") then
			lights += 1
			if lights > Cfg.Budget.MaxLightsPerModel then
				table.insert(drop, d)
			else
				d.Shadows = false
			end
		end
	end
	for _, d in ipairs(drop) do
		pcall(function()
			d:Destroy()
		end)
	end
	return parts
end

local function loadTemplate(id: number): Tpl
	local t = templates[id]
	if t and t.State ~= "loading" then
		return t
	end
	if t and t.State == "loading" then
		local t0 = os.clock()
		while t.State == "loading" and os.clock() - t0 < 60 do
			task.wait(0.25)
		end
		return t
	end
	local rec: Tpl = { State = "loading", Model = nil, Size = Vector3.zero, Parts = 0, Err = nil }
	templates[id] = rec
	local ok, res = pcall(InsertService.LoadAsset, InsertService, id)
	if not ok then
		task.wait(2)
		ok, res = pcall(InsertService.LoadAsset, InsertService, id)
	end
	if not ok or typeof(res) ~= "Instance" then
		rec.State, rec.Err = "fail", tostring(res)
		log("%d load FAILED: %s", id, tostring(res))
		return rec
	end
	local m = res :: Model
	local parts = clean(m)
	local mn, mx = visibleBox(m)
	if parts <= 0 or mn == nil or mx == nil then
		m:Destroy()
		rec.State, rec.Err = "fail", "no visible parts after cleaning"
		log("%d: %s", id, rec.Err :: string)
		return rec
	end
	if parts > Cfg.Budget.MaxPartsPerModel then
		m:Destroy()
		rec.State, rec.Err = "fail", string.format("%d parts > MaxPartsPerModel", parts)
		log("%d: %s", id, rec.Err :: string)
		return rec
	end
	local a, b = mn :: Vector3, mx :: Vector3
	m.Name = "StoreTpl_" .. id
	m.WorldPivot = CFrame.new((a.X + b.X) * 0.5, a.Y, (a.Z + b.Z) * 0.5)
	m.Parent = templatesFolder()
	rec.Model, rec.Size, rec.Parts, rec.State = m, b - a, parts, "ok"
	return rec
end

function StorePropsService.Status(id: number): (string, string?)
	local t = templates[id]
	if t == nil then
		return "not loaded", nil
	end
	return t.State, t.Err
end

function StorePropsService.Stats(): { [string]: any }
	return { Stats = stats, PlacedById = placedById, Failed = failedRows }
end

-- the planned footprint (half sizes on world X / Z) of a template at scale s turned by yaw (radians)
local function halfXZ(size: Vector3, s: number, yaw: number): (number, number)
	local c, n = math.abs(math.cos(yaw)), math.abs(math.sin(yaw))
	local x, z = size.X * s, size.Z * s
	return (x * c + z * n) * 0.5, (x * n + z * c) * 0.5
end

-- one copy: clone, scale, pivot, per-part polish; returns the model + its part count
local function spawnCopy(tpl: Tpl, cf: CFrame, s: number, kind: string, id: number, parent: Instance): (Model?, number)
	local src = tpl.Model
	if src == nil then
		return nil, 0
	end
	local m = src:Clone()
	if math.abs(s - 1) > 1e-3 then
		local okS = pcall(function()
			m:ScaleTo(s)
		end)
		if not okS then
			m:Destroy()
			return nil, 0
		end
	end
	m:PivotTo(cf)
	local P = Cfg.Place
	local n = 0
	local drop: { BasePart } = {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			local big = math.max(d.Size.X, d.Size.Y, d.Size.Z)
			if big < P.PruneStuds and d.Transparency < 0.95 then
				table.insert(drop, d)
				continue
			end
			d.CastShadow = big >= P.ShadowStuds
			if big < P.NoCollideStuds then
				d.CanCollide = false
				d.CanQuery = false
			end
			n += 1
		end
	end
	for _, d in ipairs(drop) do
		d:Destroy()
	end
	m.Name = "Store_" .. id
	m:SetAttribute("WE_Cluster", "store:" .. kind)
	m:SetAttribute("WE_Tier", 1)
	m:SetAttribute("WE_StoreProp", id)
	pcall(function()
		(m :: any).ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	m.Parent = parent
	return m, n
end

-- ── ground / clearance tests ──────────────────────────────────────────────────────────────────────────────────────
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude
overlap.RespectCanCollide = false

local floorY: number? = nil

local function isFloor(p: BasePart): boolean
	return p.Size.X >= Cfg.Place.FloorSlabStuds and p.Size.Z >= Cfg.Place.FloorSlabStuds
end

local function isRoad(p: Instance): boolean
	local n = p.Name
	if string.sub(n, 1, 4) == "Road" then
		return true
	end
	local a = p.Parent
	while a and a ~= Workspace do
		if a.Name == "Roads" or a.Name == "RoadEnds" or string.sub(a.Name, 1, 5) == "Road_" then
			return true
		end
		a = a.Parent
	end
	return false
end

local function charExcludes(): { Instance }
	local ex: { Instance } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ex, p.Character)
		end
	end
	-- (the store props are NOT excluded: a copy never lands on or in another copy)
	return ex
end

-- the desert floor height (once): the median ground hit over a few open points
local function getFloorY(): number
	if floorY then
		return floorY :: number
	end
	local ys = {}
	rayParams.FilterDescendantsInstances = charExcludes()
	for _, p in ipairs({ { 900, 300 }, { -900, -300 }, { 300, -900 }, { -300, 900 }, { 1300, -300 } }) do
		local hit = Workspace:Raycast(Vector3.new(p[1], 500, p[2]), Vector3.new(0, -1000, 0), rayParams)
		if hit and (hit.Instance:IsA("Terrain") or (hit.Instance:IsA("BasePart") and isFloor(hit.Instance :: BasePart))) then
			table.insert(ys, hit.Position.Y)
		end
	end
	table.sort(ys)
	local v: number = if #ys > 0 then ys[math.ceil(#ys / 2)] else 0.5
	floorY = v
	return v
end

-- one downward ray: (y, part or nil for terrain / floor), or nil = not usable ground
local function groundAt(x: number, z: number, roof: boolean): (number?, BasePart?, boolean)
	local hit = Workspace:Raycast(Vector3.new(x, 500, z), Vector3.new(0, -1000, 0), rayParams)
	if hit == nil then
		return nil, nil, false
	end
	local inst = hit.Instance
	local fy = getFloorY()
	if inst:IsA("Terrain") then
		if hit.Material == Enum.Material.Water or roof then
			return nil, nil, false
		end
		return hit.Position.Y, nil, false
	end
	if not inst:IsA("BasePart") then
		return nil, nil, false
	end
	local p = inst :: BasePart
	if isRoad(p) or hit.Normal.Y < 0.98 or not p.Anchored then
		return nil, nil, false
	end
	if roof then
		-- a flat roof of the game's own Part buildings (never a mesh / union: its collision box may not be its look,
		-- and never another store copy)
		if hit.Position.Y < fy + Cfg.Place.RoofMinUp or not p.CanCollide or (worldFolder ~= nil and p:IsDescendantOf(worldFolder :: Folder)) then
			return nil, nil, false
		end
		if p.Transparency > 0.2 then
			-- the town's invisible HouseCollider box: the visible roof right under it must be flush (so nothing floats)
			local keep = rayParams.FilterDescendantsInstances
			local ex = table.clone(keep)
			table.insert(ex, p)
			rayParams.FilterDescendantsInstances = ex
			local vis = Workspace:Raycast(Vector3.new(x, hit.Position.Y + 0.2, z), Vector3.new(0, -3, 0), rayParams)
			rayParams.FilterDescendantsInstances = keep
			if vis == nil or not vis.Instance:IsA("BasePart") or (vis.Instance :: BasePart).Transparency > 0.2
				or vis.Normal.Y < 0.98 or math.abs(vis.Position.Y - hit.Position.Y) > 0.3 then
				return nil, nil, false
			end
		elseif not p:IsA("Part") then
			return nil, nil, false -- a visible mesh / union roof: its collision box may not be its look
		end
		return hit.Position.Y, p, true
	end
	if isFloor(p) then
		return hit.Position.Y, p, false
	end
	-- a pavement / plaza slab just above the floor counts as ground
	if hit.Position.Y <= fy + Cfg.Place.PavementUp and p.Size.X >= 12 and p.Size.Z >= 12 then
		return hit.Position.Y, p, false
	end
	return nil, nil, false
end

local function nearPlot(x: number, z: number, r: number): boolean
	for plotId = 1, BaseConfig.MaxPlots do
		local ok, pos = pcall(PlotFrame.PlotPosition :: any, plotId)
		if ok and typeof(pos) == "Vector3" then
			local dx, dz = pos.X - x, pos.Z - z
			if math.sqrt(dx * dx + dz * dz) < Cfg.Place.BaseClearStuds + r then
				return true
			end
		end
	end
	return false
end

-- may this footprint stand at (x, z, yaw)? returns the base CFrame (bottom centre) or nil
local function spot(x: number, z: number, yaw: number, size: Vector3, s: number, roof: boolean): (CFrame?, BasePart?)
	local P = Cfg.Place
	local hx, hz = halfXZ(size, s, yaw)
	local h = size.Y * s
	local L = WorldSitesConfig.Land
	if x - hx < L.X0 or x + hx > L.X1 or z - hz < L.Z0 or z + hz > L.Z1 then
		return nil
	end
	if nearPlot(x, z, math.max(hx, hz)) then
		return nil
	end
	rayParams.FilterDescendantsInstances = charExcludes()
	-- 5 rays: centre + the corners of the (rotated) footprint, pulled in 0.5
	local rot = CFrame.Angles(0, yaw, 0)
	local lx, lz = size.X * s * 0.5 - 0.5, size.Z * s * 0.5 - 0.5
	local lo, hi = math.huge, -math.huge
	local roofPart: BasePart? = nil
	local groundParts: { BasePart } = {}
	for _, o in ipairs({ { 0, 0 }, { lx, lz }, { -lx, lz }, { lx, -lz }, { -lx, -lz } }) do
		local w = rot * Vector3.new(o[1], 0, o[2])
		local y, part, isRoof = groundAt(x + w.X, z + w.Z, roof)
		if y == nil then
			return nil
		end
		if roof then
			if not isRoof or part == nil then
				return nil
			end
			roofPart = roofPart or part
			table.insert(groundParts, part :: BasePart) -- (a roof may be several flush parts: the flatness test below)
		elseif part then
			table.insert(groundParts, part)
		end
		lo, hi = math.min(lo, y :: number), math.max(hi, y :: number)
	end
	if hi - lo > (if roof then 0.1 else P.MaxSlope) then
		return nil
	end
	local base = lo - P.Sink
	-- clearance: nothing (but the floor, the ground slabs under us, triggers) in the padded box
	local ex = charExcludes()
	for _, gp in ipairs(groundParts) do
		table.insert(ex, gp)
	end
	if roofPart then
		table.insert(ex, roofPart :: BasePart)
	end
	overlap.FilterDescendantsInstances = ex
	local center = CFrame.new(x, base + 0.3 + h * 0.5, z) * rot
	local hits = Workspace:GetPartBoundsInBox(center, Vector3.new(size.X * s + P.Pad * 2, math.max(0.5, h - 0.2), size.Z * s + P.Pad * 2), overlap)
	for _, p in ipairs(hits) do
		if isFloor(p) then
			continue
		end
		if p.Transparency >= 0.95 and not p.CanCollide then
			continue -- a trigger / zone volume
		end
		return nil
	end
	if not roof then
		local roadBox = CFrame.new(x, base + 1, z) * rot
		local rh = Workspace:GetPartBoundsInBox(roadBox, Vector3.new(size.X * s + P.RoadPad * 2, 4, size.Z * s + P.RoadPad * 2), overlap)
		for _, p in ipairs(rh) do
			if isRoad(p) then
				return nil
			end
		end
	end
	return CFrame.new(x, base, z) * rot, roofPart
end

-- ── world dressing ────────────────────────────────────────────────────────────────────────────────────────────────
local function hashSeed(s: string): number
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 2147483647
	end
	return h
end

local function siteList(): { any }
	local ok, WS = pcall(function()
		return require(script.Parent.Parent.Modules.WorldSites) :: any
	end)
	if ok and WS and WS.List then
		local l = WS.List()
		if #l > 0 then
			return l
		end
	end
	-- fallback: the site folders' attributes
	local out = {}
	local wf = Workspace:FindFirstChild("WorldFill")
	local sf = wf and wf:FindFirstChild("Sites")
	if sf then
		for _, f in ipairs(sf:GetChildren()) do
			local id = f:GetAttribute("WE_SiteId")
			if typeof(id) == "string" then
				table.insert(out, { Id = id, X = f:GetAttribute("WE_SiteX"), Z = f:GetAttribute("WE_SiteZ"), R = f:GetAttribute("WE_SiteR") or 44 })
			end
		end
	end
	return out
end

type Sampler = (rng: Random, outside: boolean) -> (number, number)

local function samplerFor(at: string, ringOverride: number?): (Sampler?, boolean)
	local kind, id = string.match(at, "^(%a+):(.+)$")
	if kind == "site" then
		for _, s in ipairs(siteList()) do
			if s.Id == id then
				local sx, sz, r = tonumber(s.X) or 0, tonumber(s.Z) or 0, tonumber(s.R) or 44
				return function(rng: Random, _o: boolean): (number, number)
					local d = rng:NextNumber(r * 0.35, r + (ringOverride or Cfg.Place.SiteRing))
					local a = rng:NextNumber(0, math.pi * 2)
					return sx + d * math.cos(a), sz + d * math.sin(a)
				end, false
			end
		end
		return nil, false
	elseif kind == "area" then
		for _, a in ipairs(MapAreas.List()) do
			if a.Id == id then
				local R = a.Rect
				local ring = Cfg.Place.OutsideRing
				if R then
					return function(rng: Random, outside: boolean): (number, number)
						if not outside then
							return rng:NextNumber(R.X0 + 8, R.X1 - 8), rng:NextNumber(R.Z0 + 8, R.Z1 - 8)
						end
						-- a band just outside the rect
						local side = rng:NextInteger(1, 4)
						if side == 1 then
							return rng:NextNumber(R.X0 - ring, R.X1 + ring), rng:NextNumber(R.Z0 - ring, R.Z0 - 6)
						elseif side == 2 then
							return rng:NextNumber(R.X0 - ring, R.X1 + ring), rng:NextNumber(R.Z1 + 6, R.Z1 + ring)
						elseif side == 3 then
							return rng:NextNumber(R.X0 - ring, R.X0 - 6), rng:NextNumber(R.Z0, R.Z1)
						end
						return rng:NextNumber(R.X1 + 6, R.X1 + ring), rng:NextNumber(R.Z0, R.Z1)
					end, true
				end
				local cx, cz, r = a.X, a.Z, a.R
				return function(rng: Random, outside: boolean): (number, number)
					local d = if outside then rng:NextNumber(r + 6, r + ring) else math.sqrt(rng:NextNumber(0, 1)) * math.max(4, r - 8)
					local ang = rng:NextNumber(0, math.pi * 2)
					return cx + d * math.cos(ang), cz + d * math.sin(ang)
				end, true
			end
		end
	end
	return nil, false
end

local function ensureWorldFolder(): Folder?
	local wf = Workspace:FindFirstChild("WorldFill")
	if wf == nil then
		return nil
	end
	local f = wf:FindFirstChild("StoreProps")
	if f == nil then
		local nf = Instance.new("Folder")
		nf.Name = "StoreProps"
		nf.Parent = wf
		f = nf
	end
	return f :: Folder
end

local function placeWorld()
	if off() or Cfg.World ~= true then
		return
	end
	local folder = ensureWorldFolder()
	if folder == nil then
		log("world: no Workspace.WorldFill; world dressing skipped")
		return
	end
	folder:ClearAllChildren()
	worldFolder = folder
	worldRuns += 1
	stats.WorldPlaced, stats.WorldParts, stats.WorldFailed = 0, 0, 0
	table.clear(placedById)
	table.clear(failedRows)
	local budget = Cfg.Budget.MaxWorldParts
	local inFrame = 0
	for rowIndex, row in ipairs(Cfg.WorldRows) do
		if off() or folder.Parent == nil then
			return
		end
		local tpl = loadTemplate(row.Id)
		if tpl.State ~= "ok" then
			table.insert(failedRows, string.format("%d@%s: %s", row.Id, row.At, tostring(tpl.Err)))
			stats.WorldFailed += row.Count
			continue
		end
		local sample, canOutside = samplerFor(row.At, row.Ring)
		if sample == nil then
			table.insert(failedRows, string.format("%d@%s: no such site/area", row.Id, row.At))
			stats.WorldFailed += row.Count
			continue
		end
		local asset = Cfg.Assets[row.Id]
		local kind = if asset then string.lower((string.gsub(asset.Cat, "%W+", ""))) else "prop"
		local rng = Random.new(hashSeed(row.At .. ":" .. row.Id .. ":" .. rowIndex))
		local bigModel = math.max(tpl.Size.X, tpl.Size.Z) * row.Scale >= 14
		for k = 1, row.Count do
			if tpl.Parts > budget then
				table.insert(failedRows, string.format("%d@%s #%d: world part budget spent", row.Id, row.At, k))
				stats.WorldFailed += 1
				continue
			end
			local placedCf: CFrame? = nil
			local onRoof: BasePart? = nil
			for try = 1, Cfg.Place.Tries * (if canOutside then 2 else 1) do
				local outside = canOutside and try > Cfg.Place.Tries
				local x, z = (sample :: Sampler)(rng, outside)
				local yaw = if row.Yaw then math.rad(row.Yaw :: number)
					elseif bigModel then math.rad(90 * rng:NextInteger(0, 3))
					else rng:NextNumber(0, math.pi * 2)
				placedCf, onRoof = spot(x, z, yaw, tpl.Size, row.Scale, row.Mode == "roof")
				if placedCf then
					break
				end
				if try % 12 == 0 then
					task.wait()
				end
			end
			if placedCf == nil then
				table.insert(failedRows, string.format("%d@%s #%d: no clear level spot", row.Id, row.At, k))
				stats.WorldFailed += 1
				continue
			end
			local m, n = spawnCopy(tpl, placedCf :: CFrame, row.Scale, kind, row.Id, folder)
			if m then
				m:SetAttribute("WE_StoreAt", row.At)
				if onRoof then
					m:SetAttribute("WE_StoreOn", (onRoof :: BasePart):GetFullName())
				end
				budget -= n
				stats.WorldPlaced += 1
				stats.WorldParts += n
				placedById[row.Id] = (placedById[row.Id] or 0) + 1
			end
			inFrame += 1
			if inFrame >= Cfg.Place.PlaceBatch then
				inFrame = 0
				task.wait()
			end
		end
	end
	folder:SetAttribute("WE_StoreParts", stats.WorldParts)
	folder:SetAttribute("WE_StoreCopies", stats.WorldPlaced)
	log("world: placed %d copies (%d parts, cap %d), %d not placed", stats.WorldPlaced, stats.WorldParts, Cfg.Budget.MaxWorldParts, stats.WorldFailed)
	for _, f in ipairs(failedRows) do
		log("world: not placed %s", f)
	end
	-- WorldFill rebuilt (MapSetup heal): dress again, at most 3 times
	folder.AncestryChanged:Connect(function()
		if folder.Parent == nil and worldRuns < 3 and not off() then
			task.delay(8, placeWorld)
		end
	end)
end

local function anyLivePlayer(): boolean
	for _, p in ipairs(Players:GetPlayers()) do
		if Cfg.LiveFor(p.UserId) then
			return true
		end
	end
	return false
end

local function worldLoop()
	-- after the JOB 31 sites stand
	local t0 = os.clock()
	while os.clock() - t0 < Cfg.Place.SiteWaitSeconds do
		local wf = Workspace:FindFirstChild("WorldFill")
		local s = wf and wf:FindFirstChild("Sites")
		if s and s:GetAttribute("WE_SiteParts") ~= nil then
			break
		end
		task.wait(2)
	end
	-- owner first: only once someone it is live for is here (then it stays for everyone in this server)
	while not anyLivePlayer() do
		if off() then
			return
		end
		task.wait(3)
	end
	task.wait(2)
	placeWorld()
end

-- ── rebirth zone visuals ──────────────────────────────────────────────────────────────────────────────────────────
local function zoneBudgetUsed(plotId: number?): (number, number)
	local plot, all = 0, 0
	for f, u in pairs(zoneParts) do
		if f.Parent == nil then
			zoneParts[f] = nil
		else
			all += u.Parts
			if u.Plot == plotId then
				plot += u.Parts
			end
		end
	end
	return plot, all
end

local function ownerOfPlot(plotId: number): Player?
	local bs = deps.BaseService
	if bs == nil or bs.GetOwnedPlotId == nil then
		return nil
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local ok, id = pcall(bs.GetOwnedPlotId, p)
		if ok and id == plotId then
			return p
		end
	end
	return nil
end

local function zoneLevel(player: Player, zoneId: string): number
	local ds = deps.DataService
	local profile = ds and ds.GetProfile and ds.GetProfile(player)
	local z = profile and profile.RebirthZones
	local lv = if typeof(z) == "table" then tonumber(z[zoneId]) or 0 else 0
	return math.clamp(math.floor(lv), 0, RebirthZonesConfig.MaxLevel)
end

-- pure layout check (annex local): inside the yard, clear of the console lane, no overlaps
function StorePropsService.CheckLayout(zoneId: string, rows: { any }, sizeOf: (number) -> Vector3?, obstacles: { { number } }?): (boolean, string?)
	local a = RebirthZonesConfig.Annex[zoneId]
	if a == nil then
		return false, "no annex"
	end
	local P = Cfg.Place
	local XL, ZL = a.W * 0.5 - P.ZoneEdge, a.D * 0.5 - P.ZoneEdge
	local boxes: { { number } } = {}
	for _, o in ipairs(obstacles or {}) do
		table.insert(boxes, o) -- kept Part clusters (annex local x0, x1, z0, z1)
	end
	for _, r in ipairs(rows) do
		local size = sizeOf(r.Id)
		if size == nil then
			return false, "no size for " .. tostring(r.Id)
		end
		local hx, hz = halfXZ(size :: Vector3, r.Scale, math.rad(r.Yaw))
		local b = { r.X - hx, r.X + hx, r.Z - hz, r.Z + hz }
		if b[1] < -XL or b[2] > XL or b[3] < -ZL or b[4] > ZL then
			return false, string.format("%d outside the yard", r.Id)
		end
		if b[2] > -P.ZoneLane.HalfX and b[1] < P.ZoneLane.HalfX and b[4] > P.ZoneLane.FromZ then
			return false, string.format("%d in the console lane", r.Id)
		end
		for _, o in ipairs(boxes) do
			if b[1] < o[2] + 0.4 and o[1] < b[2] + 0.4 and b[3] < o[4] + 0.4 and o[3] < b[4] + 0.4 then
				return false, string.format("%d overlaps", r.Id)
			end
		end
		table.insert(boxes, b)
	end
	return true, nil
end

local function dressZone(folder: Instance, forcedLevel: number?)
	if off() or Cfg.ZonesOn ~= true or not folder:IsA("Folder") or folder.Parent == nil then
		return
	end
	if folder:GetAttribute("WE_StoreProps") ~= nil then
		return
	end
	local zoneId = string.match(folder.Name, "^Zone_(.+)$")
	local plotId = tonumber(string.match(folder.Parent.Name, "^Plot(%d+)$"))
	if zoneId == nil or plotId == nil then
		return
	end
	local rowsAll = Cfg.ZoneRows[zoneId]
	if rowsAll == nil or folder:FindFirstChild(zoneId .. "_Console") == nil then
		return -- locked (fence + sign) or no layout
	end
	local lv = 0
	if forcedLevel then
		lv = forcedLevel -- (the Open Cloud / Studio layout test only)
	else
		local owner = ownerOfPlot(plotId)
		if owner == nil or not Cfg.LiveFor(owner.UserId) then
			return
		end
		lv = zoneLevel(owner, zoneId)
	end
	if lv < 1 then
		return
	end
	folder:SetAttribute("WE_StoreProps", "pending")
	local rows = {}
	local parts = 0
	for _, r in ipairs(rowsAll) do
		if lv >= r.L0 and lv <= r.L1 then
			local tpl = loadTemplate(r.Id) -- (yields while loading)
			if tpl.State ~= "ok" then
				log("zone %s plot %d L%d: kept the Part build (%d: %s)", zoneId, plotId, lv, r.Id, tostring(tpl.Err))
				folder:SetAttribute("WE_StoreProps", "kept")
				stats.ZoneKept += 1
				return
			end
			parts += tpl.Parts
			table.insert(rows, r)
		end
	end
	if folder.Parent == nil or off() then
		return
	end
	if #rows == 0 then
		folder:SetAttribute("WE_StoreProps", "none")
		return
	end
	local a = RebirthZonesConfig.Annex[zoneId]
	local okP, pos = pcall(PlotFrame.PlotPosition :: any, plotId)
	if not okP or typeof(pos) ~= "Vector3" then
		return
	end
	local frame = PlotFrame.PlotCFrame(pos) * CFrame.new(a.X, 0, a.Z) * CFrame.Angles(0, math.rad(a.Yaw), 0)
	local keep = Cfg.ZoneKeepParts[zoneId] == true
	local obstacles: { { number } } = {}
	if keep then
		-- the Part clusters that stay: their boxes in annex-local X / Z
		for _, c in ipairs(folder:GetChildren()) do
			if c:IsA("Model") and c.Name ~= zoneId .. "_Yard" and c.Name ~= zoneId .. "_Console" then
				local cf, size = c:GetBoundingBox()
				local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
				for _, sx in ipairs({ -0.5, 0.5 }) do
					for _, sz in ipairs({ -0.5, 0.5 }) do
						local w = cf * Vector3.new(size.X * sx, 0, size.Z * sz)
						local l = frame:PointToObjectSpace(w)
						x0, x1, z0, z1 = math.min(x0, l.X), math.max(x1, l.X), math.min(z0, l.Z), math.max(z1, l.Z)
					end
				end
				table.insert(obstacles, { x0, x1, z0, z1 })
			end
		end
	end
	local okL, why = StorePropsService.CheckLayout(zoneId, rows, function(id: number): Vector3?
		local t = templates[id]
		return if t and t.State == "ok" then t.Size else nil
	end, obstacles)
	local usedPlot, usedAll = zoneBudgetUsed(plotId)
	if okL and (usedPlot + parts > Cfg.Budget.MaxPlotParts or usedAll + parts > Cfg.Budget.MaxZoneServerParts) then
		okL, why = false, string.format("budget (%d + %d parts)", usedAll, parts)
	end
	if not okL then
		log("zone %s plot %d L%d: kept the Part build (%s)", zoneId, plotId, lv, tostring(why))
		folder:SetAttribute("WE_StoreProps", "kept")
		stats.ZoneKept += 1
		return
	end
	-- the yard top (the ZoneYard slab of the Part build)
	local top = frame.Position.Y + 0.4
	local yardCl = folder:FindFirstChild(zoneId .. "_Yard")
	local slab = yardCl and yardCl:FindFirstChild("ZoneYard", true)
	if slab and slab:IsA("BasePart") then
		top = slab.Position.Y + slab.Size.Y * 0.5
	end
	-- swap: the Part complex goes, the yard + console stay
	if not keep then
		for _, c in ipairs(folder:GetChildren()) do
			if c.Name ~= zoneId .. "_Yard" and c.Name ~= zoneId .. "_Console" then
				c:Destroy()
			end
		end
	end
	local n = 0
	for _, r in ipairs(rows) do
		local p = (frame * CFrame.new(r.X, 0, r.Z)).Position
		local cf = CFrame.new(p.X, top - 0.02, p.Z) * frame.Rotation * CFrame.Angles(0, math.rad(r.Yaw), 0)
		local _, k = spawnCopy(templates[r.Id], cf, r.Scale, zoneId, r.Id, folder)
		n += k
	end
	folder:SetAttribute("WE_StoreProps", "on")
	folder:SetAttribute("WE_StoreParts", n)
	zoneParts[folder] = { Plot = plotId, Parts = n }
	stats.ZoneSwaps += 1
	stats.ZoneParts += n
	log("zone %s plot %d L%d: store visuals on (%d models, %d parts)", zoneId, plotId, lv, #rows, n)
end

local function watchZones()
	local connected: Instance? = nil
	while not off() do
		local root = Workspace:FindFirstChild(RebirthZonesConfig.FolderName)
		if root and root ~= connected then
			connected = root
			root.DescendantAdded:Connect(function(d)
				if d:IsA("Folder") and string.sub(d.Name, 1, 5) == "Zone_" then
					task.defer(function()
						task.spawn(dressZone, d)
					end)
				end
			end)
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("Folder") and string.sub(d.Name, 1, 5) == "Zone_" then
					task.spawn(dressZone, d)
				end
			end
		end
		task.wait(3)
	end
end

-- live kill: remove every copy, rebuild the Part zones
local function killAll()
	killed = true
	if worldFolder then
		(worldFolder :: Folder):ClearAllChildren()
	end
	local root = Workspace:FindFirstChild(RebirthZonesConfig.FolderName)
	local rz = deps.RebirthZoneService
	if root and rz and rz.Refresh then
		for _, p in ipairs(Players:GetPlayers()) do
			pcall(rz.Refresh, p)
		end
	end
	log("live kill: every store prop removed")
end

-- test hooks (server only, never behind a remote): the Open Cloud / Studio harness places without a player
StorePropsService.PlaceWorldNow = function()
	placeWorld()
end
StorePropsService.DressZoneTest = function(folder: Instance, level: number)
	dressZone(folder, level)
end
StorePropsService.LoadTemplate = loadTemplate

function StorePropsService.Init(d: { [string]: any })
	deps = d
	if Cfg.Enabled ~= true then
		log("off (StorePropsConfig.Enabled = false)")
		return
	end
	Workspace:GetAttributeChangedSignal(Cfg.LiveAttribute):Connect(function()
		if Workspace:GetAttribute(Cfg.LiveAttribute) == true and not killed then
			killAll()
		end
	end)
	-- 1. templates: the zone ids first (lazy: nothing blocks the boot)
	task.spawn(function()
		local zs, ws = Cfg.NeededIds()
		if Cfg.ZonesOn then
			for _, id in ipairs(zs) do
				if off() then
					return
				end
				loadTemplate(id)
				task.wait(Cfg.Place.LoadGapSeconds)
			end
		end
		if Cfg.World then
			for _, id in ipairs(ws) do
				if off() then
					return
				end
				loadTemplate(id)
				task.wait(Cfg.Place.LoadGapSeconds)
			end
		end
		local okN, failN = 0, 0
		for _, t in pairs(templates) do
			if t.State == "ok" then
				okN += 1
			else
				failN += 1
			end
		end
		log("templates: %d loaded, %d failed", okN, failN)
	end)
	-- 2. world, 3. zones
	if Cfg.World then
		task.spawn(worldLoop)
	end
	if Cfg.ZonesOn then
		task.spawn(watchZones)
	end
	log("Init (OwnerFirst=%s, World=%s, Zones=%s)", tostring(Cfg.OwnerFirst), tostring(Cfg.World), tostring(Cfg.ZonesOn))
end

return StorePropsService
