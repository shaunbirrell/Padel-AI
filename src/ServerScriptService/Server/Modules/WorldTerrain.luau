--!strict
--[[
	WAR EMPIRE World v2 Phase 1 — WorldTerrain: the Terrain canyon edge that closes the map (gap/world_v2_spec.md §1.1–§1.2
	with the roadmap §1.5 corrections: talus top <= 20, mesas end <= 120 studs past the face, no back-fill wedge).

	The belt starts 12 studs outside the ring canal (x ±1852, z -1852; the rig lagoons step it out to ±1902) and runs
	down both sides to the Bay's far shore at z 2234, which closes the old open sea. Profile, outward from the water:
	toe (Rock ramp from under the sand, Terrain.Toe.Y, up to the talus foot over the skirt band 0..26: no lip for a
	car; the boats' +6 land probe sees it ~5 studs in = shore brake) → talus (Ground, 8 rising to <= 20; the same toe
	and talus on every run, so corners and run joins have no step) → vertical Sandstone face 90–150 with flush
	Limestone / Slate strata → 1–2 stepped mesas 160–300 → a butte every 4th segment; a shallow alcove every 5th; 1–3
	boulders at the cliff foot (on the talus, never on the toe). Quarter-circle corners with a bigger butte. Where a run
	stops at a rig-lagoon notch, hip carves bring its toe and talus down to the sand (no side wall). Sand slabs hide the
	outer sea ends behind the headlands; a rock pad carries the far-shore lighthouse (WorldBounds builds the tower).
	No voxel ever lands inside the playable ring or in public water (Check; the toe's support block lies under the Part
	ground, so it may). No terrain water (boats sail WE_Water parts).

	PUBLIC API (server only; nothing here is hooked yet — the post-F hook step calls it from MapSetup.Run):
	  WorldTerrain.Plan(cfg?: TerrainCfg, phase?: number) -> { Prim }
	      PURE and seeded (cfg.Seed). Phase 1 = the edge. Every primitive that fails Check is dropped (and warned).
	  WorldTerrain.Check(plan: { Prim }, cfg?) -> { string }
	      Keep-out / profile violations (empty = pass): ring, public water (headland exception), talus top, cap.
	  WorldTerrain.Stats(plan: { Prim }) -> Stats
	      Counts by tag / op, fill volume (studs³) and voxel estimate (4³ cells), max talus top, face height range.
	  WorldTerrain.Build(plan?: { Prim }, opts?: BuildOpts) -> (filled: number, seconds: number, skipped: boolean)
	      Fills the plan (default Plan(WorldConfig.Terrain, 1)). Idempotent: skips when Workspace.Terrain's
	      "WE_TerrainGen" attribute equals WorldConfig.Terrain.Gen; otherwise Terrain:Clear() (World v2 owns all
	      terrain), SetMaterialColor, fill (yielding every YieldEvery prims), then stamp. Logs
	      "[WAR EMPIRE] WorldTerrain: <n> prims in <t> s". Call it inside task.spawn after the bases are built.
	      opts.Terrain replaces Workspace.Terrain (tests pass a recorder); opts.YieldEvery = 0 never yields;
	      opts.Force rebuilds even when stamped.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Configs = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Configs")
local WorldConfig = require(Configs:WaitForChild("WorldConfig"))
local WaterConfig = require(Configs:WaitForChild("WaterConfig"))

export type Prim = {
	Op: string, -- "Block" | "Wedge" | "Ball" | "Cylinder"
	CFrame: CFrame,
	Size: Vector3?, -- Block / Wedge
	Radius: number?, -- Ball / Cylinder
	Height: number?, -- Cylinder (along the CFrame's Y axis)
	Material: Enum.Material,
	Tag: string, -- skirt | talus | face | strata | mesa | butte | alcove | boulder | corner | cover | landmark | hip
	Run: string, -- N | E | W | S (far shore) | <side>notch | corner<k> | cover | landmark
	Top: number, -- world Y of the primitive's top (checks)
}
export type TerrainCfg = typeof(WorldConfig.Terrain)
export type Profile = WorldConfig.Profile
export type Stats = {
	Total: number,
	ByTag: { [string]: number },
	ByOp: { [string]: number },
	Volume: number,
	Voxels: number,
	MaxTalusTop: number,
	FaceMin: number,
	FaceMax: number,
}
export type BuildOpts = { Terrain: any?, YieldEvery: number?, Force: boolean? }

local WorldTerrain = {}

local UP = Vector3.new(0, 1, 0)

-- ── helpers ──────────────────────────────────────────────────────────────────

-- Frame at pos whose local +Z is the outward normal n (a FillWedge rises toward local +Z, like a WedgePart) and
-- local +X runs along the edge. Right-handed: X = Y × Z.
local function frame(pos: Vector3, n: Vector3): CFrame
	return CFrame.fromMatrix(pos, UP:Cross(n), UP, n)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- XZ half-extents of a primitive (rotated box corners / ball / upright cylinder)
local function halfXZ(p: Prim): (number, number)
	if p.Op == "Ball" or p.Op == "Cylinder" then
		local r = p.Radius or 0
		return r, r
	end
	local s = p.Size or Vector3.zero
	local cf = p.CFrame
	local rx, uy, lz = cf.RightVector, cf.UpVector, cf.LookVector
	local hx = math.abs(rx.X) * s.X * 0.5 + math.abs(uy.X) * s.Y * 0.5 + math.abs(lz.X) * s.Z * 0.5
	local hz = math.abs(rx.Z) * s.X * 0.5 + math.abs(uy.Z) * s.Y * 0.5 + math.abs(lz.Z) * s.Z * 0.5
	return hx, hz
end

-- world XZ AABB (x0, x1, z0, z1)
local function boxXZ(p: Prim): (number, number, number, number)
	local hx, hz = halfXZ(p)
	local c = p.CFrame.Position
	return c.X - hx, c.X + hx, c.Z - hz, c.Z + hz
end

local function volumeOf(p: Prim): number
	if p.Op == "Ball" then
		local r = p.Radius or 0
		return 4 / 3 * math.pi * r * r * r
	elseif p.Op == "Cylinder" then
		local r = p.Radius or 0
		return math.pi * r * r * (p.Height or 0)
	end
	local s = p.Size or Vector3.zero
	local v = s.X * s.Y * s.Z
	return if p.Op == "Wedge" then v * 0.5 else v
end

-- smooth 1-D value noise in [0, 1] along the edge (lattice cell = wave studs)
local function makeNoise(rng: Random, wave: number, length: number): (number) -> number
	local n = math.ceil(length / wave) + 2
	local lattice: { number } = {}
	for i = 1, n do
		lattice[i] = rng:NextNumber()
	end
	return function(s: number): number
		local u = math.clamp(s / wave, 0, n - 2)
		local i = math.floor(u)
		local f = u - i
		f = f * f * (3 - 2 * f)
		return lerp(lattice[i + 1], lattice[i + 2], f)
	end
end

-- ── the edge polyline: straight runs, each with its outward normal and profile ───────────────────────────────

-- HipA / HipB: that end of the run stops at a rig-lagoon notch (not at a corner fan): Plan carves a hip there
type Run = { Name: string, A: Vector3, B: Vector3, N: Vector3, Profile: Profile, HipA: boolean?, HipB: boolean? }

local function sideRuns(c: TerrainCfg, side: string, sign: number): { Run }
	local e = c.Edge
	local inner, far = e.Inner, e.FarShoreZ
	local notches = {}
	for _, n in ipairs(e.Notches) do
		if n.Side == side then
			table.insert(notches, n)
		end
	end
	table.sort(notches, function(a, b)
		return a.Z0 < b.Z0
	end)
	local out: { Run } = {}
	local normal = Vector3.new(sign, 0, 0)
	local z = -inner
	for _, n in ipairs(notches) do
		if n.Z0 > z then
			table.insert(out, {
				Name = side,
				A = Vector3.new(sign * inner, 0, z),
				B = Vector3.new(sign * inner, 0, n.Z0),
				N = normal,
				Profile = c.Side,
				HipA = z > -inner,
				HipB = true,
			})
		end
		table.insert(out, { Name = side .. "notch", A = Vector3.new(sign * n.Out, 0, n.Z0), B = Vector3.new(sign * n.Out, 0, n.Z1), N = normal, Profile = c.Side })
		z = n.Z1
	end
	table.insert(out, { Name = side, A = Vector3.new(sign * inner, 0, z), B = Vector3.new(sign * inner, 0, far), N = normal, Profile = c.Side, HipA = z > -inner })
	return out
end

local function edgeRuns(c: TerrainCfg): { Run }
	local e = c.Edge
	local inner, far = e.Inner, e.FarShoreZ
	local runs: { Run } = {
		{ Name = "N", A = Vector3.new(-inner, 0, -inner), B = Vector3.new(inner, 0, -inner), N = Vector3.new(0, 0, -1), Profile = c.Side },
	}
	for _, r in ipairs(sideRuns(c, "E", 1)) do
		table.insert(runs, r)
	end
	for _, r in ipairs(sideRuns(c, "W", -1)) do
		table.insert(runs, r)
	end
	table.insert(runs, { Name = "S", A = Vector3.new(-inner, 0, far), B = Vector3.new(inner, 0, far), N = Vector3.new(0, 0, 1), Profile = c.FarShore })
	return runs
end

-- cut a run of `len` studs into segments of SegmentMin..SegmentMax (the last two share the remainder evenly)
local function cuts(rng: Random, len: number, smin: number, smax: number): { number }
	local out = { 0 }
	local s = 0
	while len - s > smax do
		local step = rng:NextNumber(smin, smax)
		if len - (s + step) < smin then
			step = (len - s) * 0.5
		end
		s += step
		table.insert(out, s)
	end
	table.insert(out, len)
	return out
end

-- ── one belt segment ─────────────────────────────────────────────────────────────────────────────────────────

type Seg = {
	Origin: Vector3, -- straight: the inner-edge point at the segment middle; corner: the corner point
	T: Vector3, -- along the edge
	N: Vector3, -- outward
	Width: (d: number) -> number, -- band width along T at outward distance d
	Profile: Profile,
	Index: number,
	S: number, -- arc position (face noise)
	Run: string,
	Corner: boolean,
	Straight: boolean, -- no yaw jitter (fan corners and run-end segments: a jittered end would leave a sliver)
}

local function emitSegment(plan: { Prim }, rng: Random, c: TerrainCfg, noise: (number) -> number, g: Seg)
	local pr = g.Profile
	local mats = c.Materials
	local foot = c.FootY
	local function at(d: number, along: number, y: number): Vector3
		return g.Origin + g.N * d + g.T * along + UP * y
	end
	local function block(tag: string, mat: Enum.Material, d0: number, d1: number, y0: number, y1: number, along: number, width: number, yaw: number)
		local cf = frame(at((d0 + d1) * 0.5, along, (y0 + y1) * 0.5), g.N)
		if yaw ~= 0 then
			cf *= CFrame.Angles(0, math.rad(yaw), 0)
		end
		table.insert(plan, { Op = "Block", CFrame = cf, Size = Vector3.new(width, y1 - y0, d1 - d0), Material = mat, Tag = tag, Run = g.Run, Top = y1 })
		return cf
	end

	-- 1) toe (the skirt band): a Rock ramp, not a shelf. A support block FootY..Toe.Y (buried under the Part ground:
	--    it keeps the voxels under the ramp full, so the smooth-terrain surface sits where the wedge says) and a
	--    FillWedge rising Toe.Y -> Talus.Min over Skirt.From..Skirt.To (= Talus.From). The belt grows out of the sand
	--    with no lip and meets the talus foot level: the old 2.5..5.5 shelf edge, the shelf -> talus step and the
	--    shelf-height jumps between segments tripped vehicles. The Skirt Min..Max roll is still drawn, so the seeded
	--    stream (faces, mesas, buttes, alcoves, boulders) is unchanged.
	rng:NextNumber(pr.Skirt.Min, pr.Skirt.Max)
	local toe = c.Toe
	local sw = g.Width(pr.Skirt.To)
	block("skirt", mats.Skirt, pr.Skirt.From, pr.Skirt.To, foot, toe.Y, 0, sw, 0)
	do
		local cf = frame(at((pr.Skirt.From + pr.Skirt.To) * 0.5, 0, (toe.Y + pr.Talus.Min) * 0.5), g.N)
		table.insert(plan, {
			Op = "Wedge",
			CFrame = cf,
			Size = Vector3.new(sw, pr.Talus.Min - toe.Y, pr.Skirt.To - pr.Skirt.From),
			Material = mats.Skirt,
			Tag = "skirt",
			Run = g.Run,
			Top = pr.Talus.Min,
		})
	end

	-- 2) talus: Ground block to Min, then a wedge rising Min -> Max (<= MaxTalusTop) toward the face
	local talusTop = math.min(pr.Talus.Max, c.MaxTalusTop)
	local tw = g.Width(pr.Talus.To)
	block("talus", mats.Talus, pr.Talus.From, pr.Talus.To, foot, pr.Talus.Min, 0, tw, 0)
	do
		local cf = frame(at((pr.Talus.From + pr.Talus.To) * 0.5, 0, (pr.Talus.Min + talusTop) * 0.5), g.N)
		table.insert(plan, {
			Op = "Wedge",
			CFrame = cf,
			Size = Vector3.new(tw, talusTop - pr.Talus.Min, pr.Talus.To - pr.Talus.From),
			Material = mats.Talus,
			Tag = "talus",
			Run = g.Run,
			Top = talusTop,
		})
	end

	-- 3) face: vertical Sandstone, H = Min + (Max - Min) * noise, yaw jitter only (no lean). The block starts
	--    FaceOverlap inside the talus, so a jittered face never opens a crack behind the talus.
	local h = pr.Face.Min + (pr.Face.Max - pr.Face.Min) * noise(g.S)
	local fw = g.Width(pr.Face.To)
	local faceFrom = pr.Face.From - pr.FaceOverlap
	local faceYaw = if g.Straight then 0 else rng:NextNumber(-pr.FaceYawJitter, pr.FaceYawJitter)
	local faceCf = block("face", mats.Face, faceFrom, pr.Face.To, foot, h, 0, fw, faceYaw)

	-- 4) strata: two material-only skins, flush with the face (same frame, inner 4 studs), never a ledge
	local faceDepth = pr.Face.To - faceFrom
	local faceMidY = (foot + h) * 0.5
	for k, band in ipairs(pr.StrataAt) do
		local centre = h * rng:NextNumber(band[1], band[2])
		local thick = rng:NextNumber(pr.StrataThick[1], pr.StrataThick[2])
		local cf = faceCf * CFrame.new(0, centre - faceMidY, -(faceDepth - pr.StrataDepth) * 0.5)
		local mat = mats.Strata[((g.Index + k) % #mats.Strata) + 1]
		table.insert(plan, {
			Op = "Block",
			CFrame = cf,
			Size = Vector3.new(fw, thick, pr.StrataDepth),
			Material = mat,
			Tag = "strata",
			Run = g.Run,
			Top = centre + thick * 0.5,
		})
	end

	-- 5) mesas, stepping back; everything ends <= MesaDepth past the face (roadmap §1.3), no back-fill
	local faceEnd = pr.Face.To
	local cap = faceEnd + pr.MesaDepth
	local function mesa(band: WorldConfig.Band, width: number, along: number)
		local yaw = if g.Straight then 0 else rng:NextNumber(-pr.MesaYawJitter, pr.MesaYawJitter)
		local depth = band.To - band.From
		local reach = depth * 0.5 * math.cos(math.rad(yaw)) + width * 0.5 * math.abs(math.sin(math.rad(yaw)))
		-- corner fans measure from the corner point: the block's outer corners sit at hypot(d, width / 2)
		local capHere = if g.Corner then math.sqrt(math.max(cap * cap - (width * 0.5) ^ 2, 0)) else cap
		local centre = math.min(faceEnd + (band.From + band.To) * 0.5, capHere - reach)
		local top = rng:NextNumber(band.Min, band.Max)
		block("mesa", mats.Mesa[rng:NextInteger(1, #mats.Mesa)], centre - depth * 0.5, centre + depth * 0.5, foot, top, along, width, yaw)
	end
	local mesaAWidth = g.Width(faceEnd + pr.MesaA.To)
	mesa(pr.MesaA, mesaAWidth, 0)
	if rng:NextNumber() < pr.MesaBChance then
		local count = if g.Corner then 1 else rng:NextInteger(1, 2)
		local span = g.Width(faceEnd + pr.MesaB.To)
		for _ = 1, count do
			local width = if g.Corner then span else math.min(span, rng:NextNumber(pr.MesaBWidth[1], pr.MesaBWidth[2]))
			local along = if g.Corner then 0 else rng:NextNumber(-(span - width) * 0.5, (span - width) * 0.5)
			mesa(pr.MesaB, width, along)
		end
	end

	-- 6) butte every ButteEvery-th segment: Sandstone cylinder + round Slate cap, inside the mesa cap
	if not g.Corner and g.Index % pr.ButteEvery == 2 then
		local r = rng:NextNumber(pr.ButteR[1], pr.ButteR[2])
		local d = math.min(faceEnd + pr.ButteAt, cap - r - 2) -- the caprock is 2 wider
		local hb = rng:NextNumber(pr.ButteH[1], pr.ButteH[2])
		local along = rng:NextNumber(-fw * 0.25, fw * 0.25)
		local capH = pr.ButteCap
		table.insert(plan, {
			Op = "Cylinder",
			CFrame = CFrame.new(at(d, along, (foot + hb - capH) * 0.5)),
			Radius = r,
			Height = hb - capH - foot,
			Material = mats.Butte,
			Tag = "butte",
			Run = g.Run,
			Top = hb - capH,
		})
		table.insert(plan, {
			Op = "Cylinder",
			CFrame = CFrame.new(at(d, along, hb - capH * 0.5)),
			Radius = r + 2,
			Height = capH,
			Material = mats.ButteCap,
			Tag = "butte",
			Run = g.Run,
			Top = hb,
		})
	end

	-- 7) alcove every AlcoveEvery-th segment: a shallow scoop in the face foot, its floor at the talus height there
	if not g.Corner and g.Index % pr.AlcoveEvery == 3 then
		local r = rng:NextNumber(pr.AlcoveR[1], pr.AlcoveR[2])
		local along = rng:NextNumber(-fw * 0.25, fw * 0.25)
		local floorY = lerp(pr.Talus.Min, talusTop, math.clamp((faceFrom - pr.Talus.From) / (pr.Talus.To - pr.Talus.From), 0, 1))
		table.insert(plan, {
			Op = "Ball",
			CFrame = CFrame.new(at(faceFrom - 0.3 * r, along, floorY + r)),
			Radius = r,
			Material = Enum.Material.Air,
			Tag = "alcove",
			Run = g.Run,
			Top = floorY + 2 * r,
		})
	end

	-- 8) boulders at the cliff foot: on the talus between its foot and the face (half buried, fully inside the belt),
	--    never on the toe ramp, where a half-buried ball is a lip a car trips on. Same draws as before.
	local nb = rng:NextInteger(pr.Boulders[1], pr.Boulders[2])
	for _ = 1, nb do
		local r = rng:NextNumber(pr.BoulderR[1], pr.BoulderR[2])
		local lo = pr.Talus.From + r
		local d = rng:NextNumber(lo, math.max(lo, faceFrom))
		local span = g.Width(d) * 0.5 - r
		local along = if span > 0 then rng:NextNumber(-span, span) else 0
		local ground = lerp(pr.Talus.Min, talusTop, math.clamp((d - pr.Talus.From) / (pr.Talus.To - pr.Talus.From), 0, 1))
		local y = ground - 0.3 * r
		table.insert(plan, {
			Op = "Ball",
			CFrame = CFrame.new(at(d, along, y)),
			Radius = r,
			Material = mats.Boulder,
			Tag = "boulder",
			Run = g.Run,
			Top = y + r,
		})
	end
end

-- ── hip at a notch run end ──────────────────────────────────────────────────────────────────────────────────
-- A run that stops at a rig-lagoon notch used to end square: its toe and talus showed a side wall 0.5..15 studs
-- tall to the lagoon bank. Four Air prims, filled after the run's own prims, trim the toe and talus inside the last
-- D studs of the run (D = the face foot, Face.From - FaceOverlap) to min(f(across), f(along)): a hip roof that falls
-- to the sand at the run end. f = the toe ramp (Toe.Y at 0 -> Talus.Min at Skirt.To) then the talus. Each profile
-- plane is an upside-down FillWedge (it clears everything between its slope and its flat top); a block clears the rest
-- up to HipClear above the talus (boulder caps). The cliff face (from D outward) keeps its side.
local function emitHip(plan: { Prim }, c: TerrainCfg, run: Run, atB: boolean)
	local pr = run.Profile
	local toe = c.Toe
	local t = (run.B - run.A).Unit
	local u = if atB then -t else t -- from the run end into the run
	local p0 = if atB then run.B else run.A
	local n = run.N
	local D = pr.Face.From - pr.FaceOverlap
	local T = pr.Skirt.To
	local talusTop = math.min(pr.Talus.Max, c.MaxTalusTop)
	local fD = lerp(pr.Talus.Min, talusTop, math.clamp((D - pr.Talus.From) / (pr.Talus.To - pr.Talus.From), 0, 1))
	local clear = fD + toe.HipClear
	local flip = CFrame.Angles(math.pi, 0, 0) -- about the frame's X (across): the wedge's slope now bounds it from below
	local function add(op: string, along0: number, along1: number, y0: number, y1: number, flipped: boolean)
		local cf = frame(p0 + n * (D * 0.5) + u * ((along0 + along1) * 0.5) + UP * ((y0 + y1) * 0.5), u)
		table.insert(plan, {
			Op = op,
			CFrame = if flipped then cf * flip else cf,
			Size = Vector3.new(D, y1 - y0, along1 - along0),
			Material = Enum.Material.Air,
			Tag = "hip",
			Run = run.Name,
			Top = y1,
		})
	end
	if D <= 0 or T <= 0 then
		return
	end
	local toeTo = math.min(T, D)
	local toeTop = lerp(toe.Y, pr.Talus.Min, toeTo / T)
	add("Wedge", 0, toeTo, toe.Y, toeTop, true)
	add("Block", 0, toeTo, toeTop, clear, false)
	if D > T and fD > pr.Talus.Min then
		add("Wedge", T, D, pr.Talus.Min, fD, true)
		add("Block", T, D, fD, clear, false)
	end
end

-- ── Check / Stats ────────────────────────────────────────────────────────────────────────────────────────────

local function primViolation(p: Prim, c: TerrainCfg): string?
	if p.Material == Enum.Material.Air then
		return nil -- carving never adds voxels
	end
	local x0, x1, z0, z1 = boxXZ(p)
	local ring = c.Ring
	if x1 > -ring.X and x0 < ring.X and z1 > ring.ZMin and z0 < ring.ZMax then
		return string.format("inside the ring (%.0f..%.0f, %.0f..%.0f)", x0, x1, z0, z1)
	end
	local inner = c.Edge.Inner
	-- a prim whose top is at or under the Part ground (the toe's support block) is never seen and never meets a hull
	local buried = p.Top <= c.Toe.BuriedTop
	for _, w in ipairs(WaterConfig.Public) do
		if not buried and x1 > w.X0 and x0 < w.X1 and z1 > w.Z0 and z0 < w.Z1 then
			local headland = (x0 >= inner or x1 <= -inner) and p.Top >= c.HeadlandMinTop
			if not headland then
				return string.format("in water %s (%.0f..%.0f, %.0f..%.0f, top %.1f)", w.Name, x0, x1, z0, z1, p.Top)
			end
		end
	end
	if p.Tag == "talus" and p.Top > c.MaxTalusTop + 1e-6 then
		return string.format("talus top %.1f > %d", p.Top, c.MaxTalusTop)
	end
	return nil
end

function WorldTerrain.Check(plan: { Prim }, cfg: TerrainCfg?): { string }
	local c = cfg or WorldConfig.Terrain
	local out: { string } = {}
	for i, p in ipairs(plan) do
		local v = primViolation(p, c)
		if v then
			table.insert(out, string.format("#%d %s/%s %s", i, p.Run, p.Tag, v))
		end
	end
	if #plan > c.MaxPrims then
		table.insert(out, string.format("%d prims > cap %d", #plan, c.MaxPrims))
	end
	-- profile: the toe ramp must end where the talus starts, and every run / corner must share one toe + talus
	-- (a fan or run join between two different profiles is a step)
	local side, far = c.Side, c.FarShore
	for _, pr in ipairs({ side, far }) do
		if pr.Skirt.To ~= pr.Talus.From then
			table.insert(out, string.format("toe ends at %g but the talus starts at %g", pr.Skirt.To, pr.Talus.From))
		end
	end
	if side.Skirt.From ~= far.Skirt.From or side.Skirt.To ~= far.Skirt.To or side.Talus.To ~= far.Talus.To or side.Talus.Min ~= far.Talus.Min or side.Talus.Max ~= far.Talus.Max then
		table.insert(out, "Side and FarShore toe / talus differ (a step where the far-shore corner fans meet the far shore)")
	end
	if c.Toe.Y > c.Toe.BuriedTop then
		table.insert(out, string.format("toe low edge %.1f above the Part ground %.1f (a lip)", c.Toe.Y, c.Toe.BuriedTop))
	end
	return out
end

function WorldTerrain.Stats(plan: { Prim }): Stats
	local st: Stats = {
		Total = #plan,
		ByTag = {},
		ByOp = {},
		Volume = 0,
		Voxels = 0,
		MaxTalusTop = 0,
		FaceMin = math.huge,
		FaceMax = 0,
	}
	for _, p in ipairs(plan) do
		st.ByTag[p.Tag] = (st.ByTag[p.Tag] or 0) + 1
		st.ByOp[p.Op] = (st.ByOp[p.Op] or 0) + 1
		if p.Material ~= Enum.Material.Air then
			st.Volume += volumeOf(p)
		end
		if p.Tag == "talus" then
			st.MaxTalusTop = math.max(st.MaxTalusTop, p.Top)
		elseif p.Tag == "face" then
			st.FaceMin = math.min(st.FaceMin, p.Top)
			st.FaceMax = math.max(st.FaceMax, p.Top)
		end
	end
	st.Voxels = math.floor(st.Volume / 64)
	return st
end

-- ── Plan ─────────────────────────────────────────────────────────────────────────────────────────────────────

function WorldTerrain.Plan(cfg: TerrainCfg?, phase: number?): { Prim }
	local c = cfg or WorldConfig.Terrain
	local plan: { Prim } = {}
	if (phase or 1) < 1 then
		return plan
	end
	local rng = Random.new(c.Seed)
	local e = c.Edge
	local runs = edgeRuns(c)
	local total = 0
	for _, r in ipairs(runs) do
		total += (r.B - r.A).Magnitude
	end
	local sideNoise = makeNoise(rng, c.Side.FaceNoiseWave, total + 4000)
	local farNoise = makeNoise(rng, c.FarShore.FaceNoiseWave, total + 4000)

	local index = 0
	local sBase = 0
	for _, run in ipairs(runs) do
		local len = (run.B - run.A).Magnitude
		local t = (run.B - run.A).Unit
		local noise = if run.Profile == c.FarShore then farNoise else sideNoise
		local cs = cuts(rng, len, e.SegmentMin, e.SegmentMax)
		for k = 1, #cs - 1 do
			local s0, s1 = cs[k], cs[k + 1]
			local a0 = if k > 1 then s0 - e.Overlap else s0
			local a1 = if k < #cs - 1 then s1 + e.Overlap else s1
			local width = a1 - a0
			index += 1
			emitSegment(plan, rng, c, noise, {
				Origin = run.A + t * ((a0 + a1) * 0.5),
				T = t,
				N = run.N,
				Width = function(_d: number): number
					return width
				end,
				Profile = run.Profile,
				Index = index,
				S = sBase + (s0 + s1) * 0.5,
				Run = run.Name,
				Corner = false,
				Straight = k == 1 or k == #cs - 1,
			})
		end
		-- after the run's own fills, so the carve cuts them (no later prim reaches the hip square)
		if run.HipA then
			emitHip(plan, c, run, false)
		end
		if run.HipB then
			emitHip(plan, c, run, true)
		end
		sBase += len
	end

	-- four outer corners: a quarter circle of CornerSegments around the corner point + one bigger butte
	local inner, far = e.Inner, e.FarShoreZ
	local corners = {
		{ P = Vector3.new(-inner, 0, -inner), A0 = 180, A1 = 270 },
		{ P = Vector3.new(inner, 0, -inner), A0 = -90, A1 = 0 },
		{ P = Vector3.new(inner, 0, far), A0 = 0, A1 = 90 },
		{ P = Vector3.new(-inner, 0, far), A0 = 90, A1 = 180 },
	}
	local n = e.CornerSegments
	local half = math.rad(90 / n) * 0.5
	for ci, corner in ipairs(corners) do
		for k = 1, n do
			local ang = math.rad(corner.A0 + (k - 0.5) * (corner.A1 - corner.A0) / n)
			local nrm = Vector3.new(math.cos(ang), 0, math.sin(ang))
			index += 1
			emitSegment(plan, rng, c, sideNoise, {
				Origin = corner.P,
				T = UP:Cross(nrm),
				N = nrm,
				Width = function(d: number): number
					return 2 * math.max(d, 1) * math.tan(half) + 2 * e.Overlap
				end,
				Profile = c.Side,
				Index = index,
				S = sBase + ci * 97,
				Run = "corner" .. ci,
				Corner = true,
				Straight = true,
			})
		end
		local pr = c.Side
		local r = rng:NextNumber(e.CornerButteR[1], e.CornerButteR[2])
		local mid = math.rad((corner.A0 + corner.A1) * 0.5)
		local d = pr.Face.To + pr.MesaDepth - r - 2 -- caprock r + 2 stays inside the cap
		local hb = rng:NextNumber(e.CornerButteH[1], e.CornerButteH[2])
		local pos = corner.P + Vector3.new(math.cos(mid), 0, math.sin(mid)) * d
		table.insert(plan, {
			Op = "Cylinder",
			CFrame = CFrame.new(pos + UP * ((c.FootY + hb - pr.ButteCap) * 0.5)),
			Radius = r,
			Height = hb - pr.ButteCap - c.FootY,
			Material = c.Materials.Butte,
			Tag = "butte",
			Run = "corner" .. ci,
			Top = hb - pr.ButteCap,
		})
		table.insert(plan, {
			Op = "Cylinder",
			CFrame = CFrame.new(pos + UP * (hb - pr.ButteCap * 0.5)),
			Radius = r + 2,
			Height = pr.ButteCap,
			Material = c.Materials.ButteCap,
			Tag = "butte",
			Run = "corner" .. ci,
			Top = hb,
		})
	end

	-- sand over the outer sea ends behind the headlands
	for _, r in ipairs(c.SeaCover.Rects) do
		local top = c.SeaCover.Top
		table.insert(plan, {
			Op = "Block",
			CFrame = CFrame.new((r.X0 + r.X1) * 0.5, (c.FootY + top) * 0.5, (r.Z0 + r.Z1) * 0.5),
			Size = Vector3.new(r.X1 - r.X0, top - c.FootY, r.Z1 - r.Z0),
			Material = c.Materials.Cover,
			Tag = "cover",
			Run = "cover",
			Top = top,
		})
	end

	-- rock pad for the far-shore lighthouse
	do
		local lp = c.LighthousePad
		table.insert(plan, {
			Op = "Block",
			CFrame = CFrame.new(lp.X, (c.FootY + lp.Top) * 0.5, lp.Z),
			Size = Vector3.new(lp.Half * 2, lp.Top - c.FootY, lp.Half * 2),
			Material = c.Materials.Skirt,
			Tag = "landmark",
			Run = "landmark",
			Top = lp.Top,
		})
	end

	-- keep-outs are asserted here too: a violating primitive is dropped, never filled
	local kept: { Prim } = {}
	local dropped = 0
	for _, p in ipairs(plan) do
		local v = primViolation(p, c)
		if v then
			dropped += 1
			if dropped <= 5 then
				warn("[WAR EMPIRE] WorldTerrain: dropped " .. p.Run .. "/" .. p.Tag .. " " .. v)
			end
		else
			table.insert(kept, p)
		end
	end
	if #kept > c.MaxPrims then
		warn(string.format("[WAR EMPIRE] WorldTerrain: plan has %d prims (cap %d); trimming boulders", #kept, c.MaxPrims))
		local trimmed: { Prim } = {}
		local excess = #kept - c.MaxPrims
		for _, p in ipairs(kept) do
			if excess > 0 and p.Tag == "boulder" then
				excess -= 1
			else
				table.insert(trimmed, p)
			end
		end
		kept = trimmed
	end
	return kept
end

-- ── Build ────────────────────────────────────────────────────────────────────────────────────────────────────

local building = false

function WorldTerrain.Build(plan: { Prim }?, opts: BuildOpts?): (number, number, boolean)
	local c = WorldConfig.Terrain
	if not c.Enabled or building then
		return 0, 0, true
	end
	local terrain: any = if opts and opts.Terrain then opts.Terrain else Workspace.Terrain
	local force = opts ~= nil and opts.Force == true
	if not force and terrain:GetAttribute("WE_TerrainGen") == c.Gen then
		return 0, 0, true
	end
	building = true
	local ok, filled, seconds = pcall(function(): (number, number)
		local p = plan or WorldTerrain.Plan(c, 1)
		local yieldEvery = if opts and opts.YieldEvery ~= nil then opts.YieldEvery else c.YieldEvery
		local t0 = os.clock()
		if c.ClearOnRegen then
			terrain:Clear()
		end
		terrain.Decoration = c.Decoration
		for _, mc in ipairs(c.Colors) do
			terrain:SetMaterialColor(mc.Material, mc.Color)
		end
		local n = 0
		for _, prim in ipairs(p) do
			if prim.Op == "Block" then
				terrain:FillBlock(prim.CFrame, prim.Size, prim.Material)
			elseif prim.Op == "Wedge" then
				terrain:FillWedge(prim.CFrame, prim.Size, prim.Material)
			elseif prim.Op == "Ball" then
				terrain:FillBall(prim.CFrame.Position, prim.Radius, prim.Material)
			elseif prim.Op == "Cylinder" then
				terrain:FillCylinder(prim.CFrame, prim.Height, prim.Radius, prim.Material)
			end
			n += 1
			if yieldEvery > 0 and n % yieldEvery == 0 then
				task.wait()
			end
		end
		terrain:SetAttribute("WE_TerrainGen", c.Gen)
		return n, os.clock() - t0
	end)
	building = false
	if not ok then
		warn("[WAR EMPIRE] WorldTerrain: build failed:", filled)
		return 0, 0, false
	end
	local n: number, dt: number = filled :: any, seconds :: any
	print(string.format("[WAR EMPIRE] WorldTerrain: %d prims in %.2f s", n, dt))
	if dt > c.BuildBudgetSeconds then
		warn(string.format("[WAR EMPIRE] WorldTerrain: build took %.2f s (budget %d s)", dt, c.BuildBudgetSeconds))
	end
	return n, dt, false
end

return WorldTerrain
