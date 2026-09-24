--!strict
--[[
	WAR EMPIRE World v2 Phase 1 — WorldBounds: what closes the map beyond the Terrain edge (gap/world_v2_spec.md §1.1,
	§1.3–§1.5). Parts only, all numbers in WorldConfig (Skyline, Bounds, Seabed, FarShore):
	  * <root>.WE_Skyline (Model, ModelStreamingMode = Persistent): 16 ridges x 3 parts (body block, front WedgePart
	    rising outward, peak block) on the square ring r 2700..3300, 340–420 tall, no physics (Anchored; CanCollide,
	    CanQuery, CanTouch, CastShadow false), darker and bluer than the belt.
	  * <root>.WE_Bounds (Folder):
	      GroundWall  10 invisible collidable parts at x ±1960, z -1960 / 2300, 400 tall (players and vehicles)
	      AirWall     12 invisible collidable parts at x ±2050, z -2050 / 2350, 700 tall (aircraft backstop)
	                  both: Transparency 1, CanQuery / CanTouch / CastShadow false (rays, probes and shots pass)
	      SeabedTint  8 flat no-physics SmoothPlastic parts inside the water volume (deep Bay band + canal stripes)
	      FarShore    Lighthouse (10 parts, one night-only SpotLight tagged WE_NightLight) on the Terrain rock pad,
	                  and a stranded freighter (12 parts in two Models <= 64 across; its low hull is the boats' "land")
	  Total 100 parts (48 + 52). Every part <= 2,000 studs per axis.

	PUBLIC API (server only; not hooked yet — the post-F hook step calls Build from MapSetup.Run):
	  WorldBounds.Build(root: Instance, opts?: { Force: boolean? }) -> Result
	      Idempotent: when root already holds WE_Skyline + WE_Bounds stamped with WorldConfig.Gen and the expected
	      part counts, nothing is touched (Result.Skipped = true); otherwise both are rebuilt from scratch.
	  WorldBounds.AirBox() -> { X, ZMin, ZMax, MaxY }   (WorldConfig.Bounds.Air; hand-off to the vehicles workflow)
	  WorldBounds.InAirBox(pos: Vector3) -> boolean
	  WorldBounds.Expected() -> { Skyline: number, Bounds: number }   (part counts Build produces)
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Configs")
local WorldConfig = require(Configs:WaitForChild("WorldConfig"))

export type Result = {
	Skipped: boolean,
	Skyline: Model?,
	Folder: Folder?,
	SkylineParts: number,
	BoundsParts: number,
	Lights: number,
}

local WorldBounds = {}

local GROUND_TOP_Y = 0.5
local UP = Vector3.new(0, 1, 0)
local GEN_ATTR = "WE_BoundsGen"

local LIGHTHOUSE_PARTS = 10
local FREIGHTER_PARTS = 12

-- ── helpers ──────────────────────────────────────────────────────────────────

type PartSpec = {
	Name: string,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3?,
	Material: Enum.Material?,
	Transparency: number?,
	Collide: boolean?, -- default false
	Query: boolean?, -- default = Collide
	Class: string?, -- "Part" (default) | "WedgePart"
}

local function makePart(spec: PartSpec, parent: Instance): BasePart
	local p: BasePart = if spec.Class == "WedgePart" then Instance.new("WedgePart") else Instance.new("Part")
	p.Name = spec.Name
	p.Anchored = true
	p.Size = spec.Size
	p.CFrame = spec.CFrame
	p.Color = spec.Color or Color3.fromRGB(128, 128, 128)
	p.Material = spec.Material or Enum.Material.SmoothPlastic
	p.Transparency = spec.Transparency or 0
	local collide = spec.Collide == true
	p.CanCollide = collide
	p.CanQuery = if spec.Query ~= nil then spec.Query else collide
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function countParts(inst: Instance): number
	local n = 0
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

-- Frame at pos whose local +Z is the outward normal n (a WedgePart rises toward +Z) and +X runs along the side.
local function frame(pos: Vector3, n: Vector3): CFrame
	return CFrame.fromMatrix(pos, UP:Cross(n), UP, n)
end

-- pieces of <= maxPiece covering a..b: { centre, length }
local function pieces(a: number, b: number, maxPiece: number): { { number } }
	local len = b - a
	local n = math.max(1, math.ceil(len / maxPiece - 1e-9))
	local step = len / n
	local out: { { number } } = {}
	for i = 1, n do
		table.insert(out, { a + (i - 0.5) * step, step })
	end
	return out
end

-- ── skyline ──────────────────────────────────────────────────────────────────

local function buildSkyline(root: Instance): Model
	local cfg = WorldConfig.Skyline
	local model = Instance.new("Model")
	model.Name = cfg.Name
	pcall(function()
		(model :: any).ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
	local rng = Random.new(cfg.Seed)
	local mid = (cfg.RInner + cfg.ROuter) * 0.5
	local sides = {
		{ Name = "N", N = Vector3.new(0, 0, -1) },
		{ Name = "E", N = Vector3.new(1, 0, 0) },
		{ Name = "S", N = Vector3.new(0, 0, 1) },
		{ Name = "W", N = Vector3.new(-1, 0, 0) },
	}
	local span = cfg.ROuter * 2
	local segLen = span / cfg.PerSide
	for _, side in ipairs(sides) do
		local n = side.N
		local t = UP:Cross(n)
		for k = 1, cfg.PerSide do
			local along = -cfg.ROuter + (k - 0.5) * segLen
			local h = rng:NextNumber(cfg.HeightMin, cfg.HeightMax)
			local hb = h * cfg.BodyShare
			local yaw = math.rad(rng:NextNumber(-cfg.YawJitter, cfg.YawJitter))
			local len = segLen + cfg.Overlap
			local centre = n * mid + t * along
			local rot = CFrame.Angles(0, yaw, 0)
			-- body: from the slope's top edge to ROuter
			local bodyFrom = cfg.RInner + cfg.SlopeDepth
			local bodyDepth = cfg.ROuter - bodyFrom
			local bodyAt = n * (bodyFrom + bodyDepth * 0.5) + t * along
			makePart({
				Name = string.format("Ridge_%s%d_Body", side.Name, k),
				Size = Vector3.new(len, hb, bodyDepth),
				CFrame = CFrame.new(centre) * rot * CFrame.new(centre):Inverse() * frame(bodyAt + UP * (GROUND_TOP_Y + hb * 0.5), n),
				Color = cfg.Colors.Body,
				Material = cfg.Material,
			}, model)
			-- front slope: rises outward from RInner to the body
			local slopeAt = n * (cfg.RInner + cfg.SlopeDepth * 0.5) + t * along
			makePart({
				Name = string.format("Ridge_%s%d_Slope", side.Name, k),
				Size = Vector3.new(len, hb, cfg.SlopeDepth),
				CFrame = CFrame.new(centre) * rot * CFrame.new(centre):Inverse() * frame(slopeAt + UP * (GROUND_TOP_Y + hb * 0.5), n),
				Color = cfg.Colors.Slope,
				Material = cfg.Material,
				Class = "WedgePart",
			}, model)
			-- peak: a shorter block standing on the body at a random place along the ridge
			local plen = segLen * rng:NextNumber(cfg.PeakLength[1], cfg.PeakLength[2])
			local poff = rng:NextNumber(-(segLen - plen) * 0.5, (segLen - plen) * 0.5)
			local peakDepth = bodyDepth * 0.7
			local peakAt = n * (bodyFrom + bodyDepth * 0.45) + t * (along + poff)
			makePart({
				Name = string.format("Ridge_%s%d_Peak", side.Name, k),
				Size = Vector3.new(plen, h, peakDepth),
				CFrame = CFrame.new(centre) * rot * CFrame.new(centre):Inverse() * frame(peakAt + UP * (GROUND_TOP_Y + h * 0.5), n),
				Color = cfg.Colors.Peak,
				Material = cfg.Material,
			}, model)
		end
	end
	model.Parent = root
	return model
end

-- ── invisible walls ──────────────────────────────────────────────────────────

type WallCfg = { X: number, ZMin: number, ZMax: number, Height: number, Thick: number, MaxPiece: number }

local function buildWall(parent: Instance, name: string, w: WallCfg)
	local folder = Instance.new("Folder")
	folder.Name = name
	local y = GROUND_TOP_Y + w.Height * 0.5
	local th = w.Thick
	-- west / east: along z from ZMin to ZMax
	for _, sgn in ipairs({ -1, 1 }) do
		for i, pc in ipairs(pieces(w.ZMin, w.ZMax, w.MaxPiece)) do
			makePart({
				Name = string.format("%s_%s%d", name, if sgn < 0 then "W" else "E", i),
				Size = Vector3.new(th, w.Height, pc[2]),
				CFrame = CFrame.new(sgn * (w.X + th * 0.5), y, pc[1]),
				Transparency = 1,
				Collide = true,
				Query = false,
			}, folder)
		end
	end
	-- north / south: along x from -X to X
	local edges: { { Tag: string, Z: number } } = { { Tag = "N", Z = w.ZMin - th * 0.5 }, { Tag = "S", Z = w.ZMax + th * 0.5 } }
	for _, edge in ipairs(edges) do
		for i, pc in ipairs(pieces(-w.X - th, w.X + th, w.MaxPiece)) do
			makePart({
				Name = string.format("%s_%s%d", name, edge.Tag, i),
				Size = Vector3.new(pc[2], w.Height, th),
				CFrame = CFrame.new(pc[1], y, edge.Z),
				Transparency = 1,
				Collide = true,
				Query = false,
			}, folder)
		end
	end
	folder.Parent = parent
end

-- ── seabed tint ──────────────────────────────────────────────────────────────

local function buildSeabed(parent: Instance)
	local cfg = WorldConfig.Seabed
	local folder = Instance.new("Folder")
	folder.Name = "SeabedTint"
	for _, r in ipairs(cfg.Rects) do
		makePart({
			Name = r.Name or "SeabedTint",
			Size = Vector3.new(r.X1 - r.X0, cfg.Y1 - cfg.Y0, r.Z1 - r.Z0),
			CFrame = CFrame.new((r.X0 + r.X1) * 0.5, (cfg.Y0 + cfg.Y1) * 0.5, (r.Z0 + r.Z1) * 0.5),
			Color = cfg.Color,
			Material = cfg.Material,
		}, folder)
	end
	folder.Parent = parent
end

-- ── far shore: lighthouse and stranded freighter ─────────────────────────────

local WHITE = Color3.fromRGB(226, 222, 210)
local RED = Color3.fromRGB(150, 58, 46)
local DARK = Color3.fromRGB(46, 44, 42)
local CONCRETE = Color3.fromRGB(150, 144, 130)

local function buildLighthouse(parent: Instance)
	local cfg = WorldConfig.FarShore.Lighthouse
	local model = Instance.new("Model")
	model.Name = "Lighthouse"
	local base = CFrame.new(cfg.X, cfg.BaseY, cfg.Z) * CFrame.Angles(0, math.rad(cfg.Yaw), 0)
	local function at(y: number): CFrame
		return base * CFrame.new(0, y, 0)
	end
	local y = -1
	local function stack(name: string, size: Vector3, color: Color3, material: Enum.Material, collide: boolean): BasePart
		local p = makePart({ Name = name, Size = size, CFrame = at(y + size.Y * 0.5), Color = color, Material = material, Collide = collide }, model)
		y += size.Y
		return p
	end
	stack("Plinth", Vector3.new(14, 4, 14), CONCRETE, Enum.Material.Concrete, true)
	stack("TowerLow", Vector3.new(9, 14, 9), WHITE, Enum.Material.SmoothPlastic, true)
	stack("TowerMid", Vector3.new(8, 12, 8), RED, Enum.Material.SmoothPlastic, true)
	stack("TowerTop", Vector3.new(7, 10, 7), WHITE, Enum.Material.SmoothPlastic, true)
	stack("Gallery", Vector3.new(11, 0.8, 11), DARK, Enum.Material.Metal, true)
	local lamp = stack("LampRoom", Vector3.new(6, 5, 6), WorldConfig.Lights.LampHeadColor, Enum.Material.SmoothPlastic, false)
	lamp.Transparency = 0.25
	stack("Roof", Vector3.new(7, 2, 7), RED, Enum.Material.SmoothPlastic, false)
	stack("Spire", Vector3.new(1, 3, 1), DARK, Enum.Material.Metal, false)
	makePart({ Name = "Door", Size = Vector3.new(3, 5, 0.4), CFrame = base * CFrame.new(0, 5.5, -4.7), Color = DARK, Material = Enum.Material.Wood }, model)
	makePart({ Name = "Window", Size = Vector3.new(2, 2.4, 0.3), CFrame = base * CFrame.new(0, 24, -4.1), Color = DARK, Material = Enum.Material.Glass }, model)
	-- one night-only SpotLight over the Bay (north = -Z), within the H8 caps
	local lc = cfg.Light
	local spot = Instance.new("SpotLight")
	spot.Name = "Beacon"
	spot.Face = Enum.NormalId.Front
	spot.Brightness = math.min(lc.Brightness, WorldConfig.Lights.MaxBrightness)
	spot.Range = math.min(lc.Range, WorldConfig.Lights.MaxRange)
	spot.Angle = lc.Angle
	spot.Color = lc.Color
	spot.Shadows = false
	spot.Enabled = false -- WorldAtmosphere enables WE_NightLight lights at night
	spot.Parent = lamp
	CollectionService:AddTag(spot, WorldConfig.Atmosphere.NightLightTag)
	model.Parent = parent
end

local function buildFreighter(parent: Instance)
	local cfg = WorldConfig.FarShore.Freighter
	local rust = Color3.fromRGB(112, 62, 46)
	local hullCol = Color3.fromRGB(70, 74, 78)
	local deckCol = Color3.fromRGB(96, 92, 84)
	-- hull frame: origin on the waterline at the hull centre, +Z = bow (up the beach), bow pitched up, slight roll
	local hull = CFrame.new(cfg.X, 1.5, cfg.Z)
		* CFrame.Angles(0, math.rad(cfg.Yaw), 0)
		* CFrame.Angles(math.rad(-cfg.Pitch), 0, math.rad(cfg.Roll))
	local stern = Instance.new("Model")
	stern.Name = "Freighter_Stern"
	local bow = Instance.new("Model")
	bow.Name = "Freighter_Bow"
	local function hp(model: Model, name: string, size: Vector3, x: number, y: number, z: number, color: Color3, material: Enum.Material, collide: boolean, class: string?, turn: CFrame?)
		local cf = hull * CFrame.new(x, y, z)
		if turn then
			cf *= turn
		end
		makePart({ Name = name, Size = size, CFrame = cf, Color = color, Material = material, Collide = collide, Class = class }, model)
	end
	-- low hull = the boats' "land": top ~3 above the waterline, under the +6 land probe origin
	hp(stern, "KeelStern", Vector3.new(16, 5, 42), 0, -1.5, -21, rust, Enum.Material.Metal, true)
	hp(bow, "KeelBow", Vector3.new(16, 5, 36), 0, -1.5, 18, rust, Enum.Material.Metal, true)
	hp(stern, "HullStern", Vector3.new(18, 7, 42), 0, 4.5, -21, hullCol, Enum.Material.Metal, true)
	hp(bow, "HullBow", Vector3.new(18, 7, 36), 0, 4.5, 18, hullCol, Enum.Material.Metal, true)
	-- raked stem: a WedgePart turned over (flat top, full height at the hull joint, slope facing forward and down)
	hp(bow, "Stem", Vector3.new(18, 9, 10), 0, 3.5, 41, hullCol, Enum.Material.Metal, true, "WedgePart", CFrame.Angles(math.pi, 0, 0))
	hp(stern, "Bridge", Vector3.new(14, 10, 10), 0, 13, -34, deckCol, Enum.Material.Metal, true)
	hp(stern, "BridgeWindows", Vector3.new(14.2, 1.4, 0.4), 0, 16, -28.9, DARK, Enum.Material.Glass, false)
	hp(stern, "Funnel", Vector3.new(4, 7, 4), 0, 21.5, -37, RED, Enum.Material.Metal, true)
	hp(stern, "Mast", Vector3.new(0.8, 12, 0.8), 0, 24, -30, DARK, Enum.Material.Metal, false)
	hp(bow, "ContainerA", Vector3.new(8, 8, 18), -4.2, 12, 6, Color3.fromRGB(46, 92, 120), Enum.Material.DiamondPlate, true)
	hp(bow, "ContainerB", Vector3.new(8, 8, 18), 4.2, 12, 10, Color3.fromRGB(150, 110, 48), Enum.Material.DiamondPlate, true)
	hp(bow, "CraneBoom", Vector3.new(1.2, 1.2, 20), 0, 19, 20, Color3.fromRGB(190, 150, 50), Enum.Material.Metal, false)
	stern.Parent = parent
	bow.Parent = parent
end

-- ── public ───────────────────────────────────────────────────────────────────

function WorldBounds.Expected(): { Skyline: number, Bounds: number }
	local b = WorldConfig.Bounds
	local function wallCount(w: WallCfg): number
		return 2 * #pieces(w.ZMin, w.ZMax, w.MaxPiece) + 2 * #pieces(-w.X - w.Thick, w.X + w.Thick, w.MaxPiece)
	end
	return {
		Skyline = 4 * WorldConfig.Skyline.PerSide * 3,
		Bounds = wallCount(b.GroundWall) + wallCount(b.AirWall) + #WorldConfig.Seabed.Rects + LIGHTHOUSE_PARTS + FREIGHTER_PARTS,
	}
end

function WorldBounds.Build(root: Instance, opts: { Force: boolean? }?): Result
	local exp = WorldBounds.Expected()
	local oldSky = root:FindFirstChild(WorldConfig.Skyline.Name)
	local oldFolder = root:FindFirstChild(WorldConfig.Bounds.Folder)
	local force = opts ~= nil and opts.Force == true
	if
		not force
		and oldSky
		and oldFolder
		and oldSky:IsA("Model")
		and oldFolder:IsA("Folder")
		and oldSky:GetAttribute(GEN_ATTR) == WorldConfig.Gen
		and oldFolder:GetAttribute(GEN_ATTR) == WorldConfig.Gen
		and countParts(oldSky) == exp.Skyline
		and countParts(oldFolder) == exp.Bounds
	then
		return { Skipped = true, Skyline = oldSky, Folder = oldFolder, SkylineParts = exp.Skyline, BoundsParts = exp.Bounds, Lights = 1 }
	end
	if oldSky then
		oldSky:Destroy()
	end
	if oldFolder then
		oldFolder:Destroy()
	end

	local sky = buildSkyline(root)
	sky:SetAttribute(GEN_ATTR, WorldConfig.Gen)

	local folder = Instance.new("Folder")
	folder.Name = WorldConfig.Bounds.Folder
	buildWall(folder, "GroundWall", WorldConfig.Bounds.GroundWall)
	buildWall(folder, "AirWall", WorldConfig.Bounds.AirWall)
	buildSeabed(folder)
	local far = Instance.new("Folder")
	far.Name = "FarShore"
	buildLighthouse(far)
	buildFreighter(far)
	far.Parent = folder
	folder:SetAttribute(GEN_ATTR, WorldConfig.Gen)
	folder.Parent = root

	local skyParts, boundsParts = countParts(sky), countParts(folder)
	if skyParts ~= exp.Skyline or boundsParts ~= exp.Bounds then
		warn(string.format("[WAR EMPIRE] WorldBounds: built %d skyline / %d bounds parts (expected %d / %d)", skyParts, boundsParts, exp.Skyline, exp.Bounds))
	end
	print(string.format("[WAR EMPIRE] WorldBounds: skyline %d parts (Persistent), bounds %d parts", skyParts, boundsParts))
	return { Skipped = false, Skyline = sky, Folder = folder, SkylineParts = skyParts, BoundsParts = boundsParts, Lights = 1 }
end

function WorldBounds.AirBox(): { X: number, ZMin: number, ZMax: number, MaxY: number }
	local a = WorldConfig.Bounds.Air
	return { X = a.X, ZMin = a.ZMin, ZMax = a.ZMax, MaxY = a.MaxY }
end

function WorldBounds.InAirBox(pos: Vector3): boolean
	local a = WorldConfig.Bounds.Air
	return math.abs(pos.X) <= a.X and pos.Z >= a.ZMin and pos.Z <= a.ZMax and pos.Y <= a.MaxY
end

return WorldBounds
