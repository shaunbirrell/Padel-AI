--!strict
--[[
	WAR EMPIRE World v2 Phase 2 (W3) — WorldPOI: the named places between the bases (gap/world_v2_spec.md §3.1–§3.2,
	roadmap §2.4 WORLD-B builder 1). Each ENABLED POI in WorldConfig.POIs becomes WarEmpireSetup.WorldDressing.POI_<Id>,
	a folder of cluster Models (each <= 64 studs across, H10) built from WorldKits. W3 step 1 built Crossroads Town only;
	W3 step 2 (spec scratchpad w3s2 §6 lane P) builds the other 17 from their POILayouts rows once their enable step flips
	them on. A disabled footprint stays reserved (WorldDress keeps out).

	CONTRACT (scratchpad/w3/contracts.md §2 and §4; W3 step 2: scratchpad w3s2/build/L0/contract.md §3 and §7): owner = P.

	PUBLIC API (server only):
	  WorldPOI.Build(dressing, quality, occ?) -> Summary
	      dressing = WarEmpireSetup.WorldDressing (MapDressing created it). For each enabled POI: destroys an old
	      POI_<Id>, builds its rows (the Town: WorldConfig.Town; every other POI: Server/Modules/POILayouts/<Layout>[Id])
	      in config order (Quality "Low" = Tier-1 clusters only), asserts every cluster with
	      WorldDress.Blocked(occ, x, z, r, { AllowPOI = Id, … }) (a blocked cluster is skipped and warned, never placed),
	      records each built cluster with WorldDress.AddDisc(occ, …, "poi:<Id>"), stays within the POI's caps, then
	      stamps the activity anchors (below). Idempotent. Never yields (mesh overlays are deferred by WorldKits).
	  WorldPOI.Enabled() -> { WorldConfig.POI }        POIs with Enabled == true, in config order
	  WorldPOI.FolderName(id) -> string                "POI_" .. id

	CAPS (per POI). The Town: Budget; Quality Low <= WorldDressConfig.Quality.Low.POIShare of its planned Full build.
	A layout POI: Full cap = Budget - Reserve (parts kept free for the jobs' runtime transients); Low cap =
	min(Full cap, floor(planned Full x (LowShare or POIShare))). Lights / Signs are per-POI caps (a board over the sign
	cap stays unpainted; WorldKits.Sign also keeps the world budget WorldConfig.Budgets.SurfaceGuis). Planned counts come
	from WorldKits.Footprint for every kit with a builder (a later kit whose builder has not landed builds 0 and counts 0).

	THE RULES (the Town and every layout; rows are data, not code: one Model per cluster row at (X, Z) turned by Yaw):
	  * Block clusters: disc (AABB half-diagonal round the AABB centre) edge >= Town.RoadClear (30) from every road
	    centre line and outside every WorldDress keep-out (capture clear circles, the Empire Bank ring, garage pads,
	    event / NPC anchors, other POI footprints, water, …). A camp's own NPC anchors are not keep-outs for its own
	    clusters (WorldDress: the sandbags stand at the guard posts).
	  * Street clusters (Street = true: checkpoints, lamps, boards) stand beside or across a road: they skip the disc road
	    test and pass a per-part test instead (every collidable part >= 13, every visible part taller than 0.3 >= 9 from
	    every road centre line; CheckpointArm and road markings exempt, as in WorldHygiene H2).
	  * Flat markings (every part top <= 0.75 and no collision: PaveTile, HoldPad) may lie over an event anchor (the
	    supply crate lands on them) and are not added to the occupancy.
	  * InWater = true clusters (gantry, jetty) skip the water keep-out and carry WE_AllowInWater (Waterways cull, H3).
	  * The ActivityHost cluster (every kit of Class "anchor": 1 invisible part, no collision) passes the zones with the
	    default 13-stud road test, may sit over an event anchor and is not added to the occupancy.
	  * Every part stays inside the POI footprint (rect: every part's AABB; circle: the cluster disc). Terrain rubble /
	    scorch (WorldKits.Rock, 0 parts) passes Blocked too and keeps its centre (rect) / disc (circle) inside.
	  * Infra rows (the airstrip runway) are flat strips under POI_<Id>.Infra (one Model, WE_Infra: exempt from H10):
	    every part flat and non-collidable, inside the footprint, and sampled along its length through Blocked.
	  * The blocks are WorldKits.TownBlock rows; their Width / Depth / Storeys / Roof / Lantern (and HoldPad R) pass
	    through kitOpts, so the planned count (Footprint) and the build always use the same options.

	ACTIVITY ANCHORS (W3 step 2; WorldConfig.Activity): invisible Attachments tagged WE_ActivityAnchor (0 parts), each
	stamped through ActivityAnchors.Stamp, the one writer:
	  * Every built Checkpoint kit gets WorldConfig.Activity.CheckpointAnchors on its CheckpointBooth part, ids
	    "<POI>.<cluster Id>.<Role>" (ActivityAnchors.FromTemplate with the kit's world frame) — the Town's 4 included.
	  * Layout rows (POILayout.Anchors) go on the POI's ActivityHost part; Town rows (WorldConfig.Town.Anchors) on the
	    first part of the cluster they Require (a part of a kit with no mesh overlay). A row with Requires is stamped only
	    when that cluster was built (Quality Low drops Tier 2: expected; the job's site goes Quiet). A row whose id is not
	    of this POI, lies outside the footprint or repeats an id already stamped here is skipped and warned.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage.Shared.Configs
local WorldConfig = require(Configs.WorldConfig)
local WorldDressConfig = require(Configs.WorldDressConfig)
local WorldDress = require(script.Parent.WorldDress)
local WorldKits = require(script.Parent.WorldKits)
local ActivityAnchors = require(script.Parent.ActivityAnchors)

export type POISummary = {
	Id: string,
	Enabled: boolean,
	Built: boolean,
	Parts: number,
	Budget: number, -- Full cap = Budget - Reserve (Low cap = floor(planned Full x LowShare or POIShare), capped by it)
	Lights: number,
	LightsCap: number,
	Signs: number,
	SignsCap: number,
	Clusters: number,
	Skipped: number, -- clusters / rocks / infra rows dropped by WorldDress.Blocked or the caps (each one warned)
	TerrainPrims: number,
	Anchors: number, -- W3 step 2: activity anchors stamped (0 parts)
	AnchorsAbsent: number, -- anchor rows not stamped: Requires not built (Low: Tier 2), no host, or refused (warned)
}
export type Summary = {
	Quality: string,
	POIs: { POISummary },
	Parts: number,
	Lights: number,
	Signs: number,
	Clusters: number,
	TerrainPrims: number,
	Anchors: number,
	Seconds: number,
	Warnings: { string },
}

type Road = WorldDress.Road
type Occupancy = WorldDress.Occupancy
type TownCluster = WorldConfig.TownCluster
type LayoutGroup = { [string]: WorldConfig.POILayout }
-- one place's rows: the Town's (WorldConfig.Town) or a POILayouts entry
type Rows = {
	Clusters: { TownCluster },
	Rocks: { WorldConfig.TownRock },
	Infra: { WorldConfig.InfraRow },
	Anchors: { WorldConfig.ActivityAnchor },
	Board: string?,
	Seed: number,
	Layout: boolean, -- false = the Town (Budget / POIShare caps, Town rows host on their Required cluster)
}
type Booth = { Part: BasePart, Frame: CFrame }
-- what one built cluster offers the anchors
type Built = {
	First: BasePart?, -- the first part of a kit with no mesh overlay (Town rows host here)
	Host: BasePart?, -- the ActivityHost part (layout rows host here)
	Booths: { Booth }, -- one per Checkpoint kit: its CheckpointBooth part and the kit's world frame
	MissingBooths: number, -- Checkpoint kits without a CheckpointBooth part (warned)
}
type Ctx = {
	Poi: WorldConfig.POI,
	Folder: Folder,
	Quality: string,
	Occ: Occupancy,
	Row: POISummary,
	Warnings: { string },
	Built: { [string]: Built }, -- cluster Id -> what it built (clusters that were Finished only)
}

local WorldPOI = {}

local GROUND_Y = 0.5
local H = WorldConfig.Hygiene
local A = WorldConfig.Activity
local INFRA_NAME = "Infra" -- POI_<Id>.Infra: the flat infrastructure strips (InfraRow)
-- the attribute WorldHygiene exempts from H10 (read loosely: WorldConfig.Hygiene may name it later)
local INFRA_ATTR: string = (H :: any).InfraAttr or "WE_Infra"

function WorldPOI.FolderName(id: string): string
	return WorldDressConfig.Folders.POIPrefix .. id
end

function WorldPOI.Enabled(): { WorldConfig.POI }
	local out: { WorldConfig.POI } = {}
	for _, p in ipairs(WorldConfig.POIs) do
		if p.Enabled == true then
			table.insert(out, p)
		end
	end
	return out
end

local function toSet(list: { string }): { [string]: boolean }
	local s: { [string]: boolean } = {}
	for _, v in ipairs(list) do
		s[v] = true
	end
	return s
end

local ROAD_EXEMPT = toSet(H.RoadExemptNames)

local function hasPrefix(name: string, list: { string }): boolean
	for _, p in ipairs(list) do
		if string.sub(name, 1, #p) == p then
			return true
		end
	end
	return false
end

-- world AABB of one part
local function partBox(p: BasePart): (number, number, number, number, number, number)
	local cf, s = p.CFrame, p.Size
	local r = cf.RightVector * s.X * 0.5
	local u = cf.UpVector * s.Y * 0.5
	local l = cf.LookVector * s.Z * 0.5
	local hx = math.abs(r.X) + math.abs(u.X) + math.abs(l.X)
	local hy = math.abs(r.Y) + math.abs(u.Y) + math.abs(l.Y)
	local hz = math.abs(r.Z) + math.abs(u.Z) + math.abs(l.Z)
	local c = cf.Position
	return c.X - hx, c.X + hx, c.Y - hy, c.Y + hy, c.Z - hz, c.Z + hz
end

-- XZ distance from a box to the nearest road centre segment
local function roadBoxDist(roads: { Road }, x0: number, x1: number, z0: number, z1: number): number
	local best = math.huge
	for _, r in ipairs(roads) do
		local a0, a1, c0, c1 = x0, x1, z0, z1
		if not r.AlongX then
			a0, a1, c0, c1 = z0, z1, x0, x1
		end
		local dA = math.max(0, r.Min - a1, a0 - r.Max)
		local dC = math.max(0, c0 - r.Across, r.Across - c1)
		local d = math.sqrt(dA * dA + dC * dC)
		if d < best then
			best = d
		end
	end
	return best
end

type Measure = {
	Parts: number,
	Lights: number,
	Signs: number,
	X0: number,
	X1: number,
	Z0: number,
	Z1: number,
	Marking: boolean, -- every part flat (top <= RoadMinTop) and non-colliding
	RoadWhy: string?, -- the first part that breaks the per-part road rule
	Outside: string?, -- the first part outside the POI rect
}

local function measure(model: Model, roads: { Road }, rect: WorldConfig.Rect?): Measure
	local T = WorldConfig.Town
	local m: Measure = { Parts = 0, Lights = 0, Signs = 0, X0 = math.huge, X1 = -math.huge, Z0 = math.huge, Z1 = -math.huge, Marking = true, RoadWhy = nil, Outside = nil }
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			m.Parts += 1
			local x0, x1, _, y1, z0, z1 = partBox(d)
			m.X0, m.X1, m.Z0, m.Z1 = math.min(m.X0, x0), math.max(m.X1, x1), math.min(m.Z0, z0), math.max(m.Z1, z1)
			if d.CanCollide or y1 > H.RoadMinTop then
				m.Marking = false
			end
			if m.RoadWhy == nil and not ROAD_EXEMPT[d.Name] then
				local gap = roadBoxDist(roads, x0, x1, z0, z1)
				if d.CanCollide and y1 > H.RoadMinTop and gap < T.CollideRoadGap then
					m.RoadWhy = string.format("road: collidable %s %.1f from a road line", d.Name, gap)
				elseif d.Transparency < 0.99 and y1 > GROUND_Y + H.RoadLaneMaxHeight and gap < T.VisibleRoadGap and not hasPrefix(d.Name, H.RoadMarkingPrefixes) then
					m.RoadWhy = string.format("road: visible %s %.1f from a road line", d.Name, gap)
				end
			end
			if m.Outside == nil and rect ~= nil and (x0 < rect.X0 or x1 > rect.X1 or z0 < rect.Z0 or z1 > rect.Z1) then
				m.Outside = "outside the footprint: " .. d.Name
			end
		elseif d:IsA("Light") then
			m.Lights += 1
		elseif d:IsA("SurfaceGui") then
			m.Signs += 1
		end
	end
	return m
end

-- a circle footprint holds the whole cluster disc (a rect footprint is tested per part in measure)
local function circleWhy(poi: WorldConfig.POI, x: number, z: number, r: number): string?
	local c = poi.Circle
	if c == nil or poi.Rect ~= nil then
		return nil
	end
	local out = math.sqrt((x - c.X) ^ 2 + (z - c.Z) ^ 2) + r - c.R
	if out > 0.01 then
		return string.format("outside the footprint circle by %.1f", out)
	end
	return nil
end

-- a point inside the POI footprint (anchor rows; rocks test their centre in a rect, their disc in a circle)
local function insideFootprint(poi: WorldConfig.POI, x: number, z: number, r: number): boolean
	local rect = poi.Rect
	if rect then
		return x >= rect.X0 and x <= rect.X1 and z >= rect.Z0 and z <= rect.Z1
	end
	local c = poi.Circle
	if c then
		return math.sqrt((x - c.X) ^ 2 + (z - c.Z) ^ 2) + r <= c.R + 0.01
	end
	return false
end

-- the WorldKits options of one cluster kit row (text only for a real build)
local function kitOpts(k: WorldConfig.KitPlace, text: string?): WorldKits.KitOpts
	return {
		Variant = k.Variant,
		Count = k.Count,
		Length = k.Length,
		Scale = k.Scale,
		Color = k.Color,
		Text = text,
		Width = k.Width,
		Depth = k.Depth,
		Storeys = k.Storeys,
		Roof = k.Roof,
		Lantern = k.Lantern,
		R = k.R,
	}
end

local function kitParts(kit: WorldConfig.KitPlace): (number, number, number)
	local s = WorldKits.Specs[kit.Kit]
	if s == nil then
		return 0, 0, 0
	end
	-- the exact count, measured from the kit builder (cached): CrateStack / DrumGroup Count is crates / drums (1 part
	-- each), SandbagLine / CompoundWall Length is studs, Wreck "car" is 4 parts; W3 step 2 kits count the same way
	local fp = WorldKits.Footprint(kit.Kit, kitOpts(kit, nil))
	if fp == nil and s.Step ~= 1 then
		return 0, 0, 0 -- a later-POI kit whose builder has not landed: WorldKits.Add builds nothing for it either
	end
	local lights = s.Lights + (if kit.Lantern == true then 1 else 0) -- a TownBlock wall lantern carries a night light
	return if fp then fp.Parts else s.PartsMax, lights, s.Signs
end

local function planned(c: TownCluster): (number, number, number)
	local p, l, g = 0, 0, 0
	for _, k in ipairs(c.Kits) do
		local a, b, d = kitParts(k)
		p, l, g = p + a, l + b, g + d
	end
	return p, l, g
end

local function infraOpts(inf: WorldConfig.InfraRow): WorldKits.KitOpts
	return { Length = inf.Length, Taxiway = inf.Taxiway }
end

local function infraParts(inf: WorldConfig.InfraRow): number
	if WorldKits.Specs[inf.Kit] == nil then
		return 0
	end
	local fp = WorldKits.Footprint(inf.Kit, infraOpts(inf))
	return if fp then fp.Parts else 0
end

-- every kit of the cluster is the invisible activity host (Class "anchor")
local function isHostCluster(c: TownCluster): boolean
	if #c.Kits == 0 then
		return false
	end
	for _, k in ipairs(c.Kits) do
		local s = WorldKits.Specs[k.Kit]
		if s == nil or s.Class ~= "anchor" then
			return false
		end
	end
	return true
end

local function note(ctx: Ctx, msg: string)
	table.insert(ctx.Warnings, msg)
	warn(msg)
end

local function skip(ctx: Ctx, what: string, why: string)
	ctx.Row.Skipped += 1
	note(ctx, string.format("[WorldPOI] %s: %s skipped (%s)", ctx.Poi.Id, what, why))
end

local function childSet(model: Model): { [Instance]: boolean }
	local s: { [Instance]: boolean } = {}
	for _, ch in ipairs(model:GetChildren()) do
		s[ch] = true
	end
	return s
end

-- the parts one WorldKits.Add call put into the cluster (they are direct children), in GetChildren order
local function freshParts(model: Model, before: { [Instance]: boolean }): { BasePart }
	local out: { BasePart } = {}
	for _, ch in ipairs(model:GetChildren()) do
		if not before[ch] and ch:IsA("BasePart") then
			table.insert(out, ch)
		end
	end
	return out
end

-- remember the parts the anchors may host on (the booth of each checkpoint, the activity host, a plain first part)
local function noteKit(built: Built, kitId: string, parts: { BasePart }, kcf: CFrame)
	local spec = WorldKits.Specs[kitId]
	local plain = spec ~= nil and spec.Mesh == nil -- no deferred mesh overlay can replace or skin these parts
	local booth: BasePart? = nil
	for _, p in ipairs(parts) do
		if built.First == nil and plain then
			built.First = p
		end
		if kitId == A.HostKit and built.Host == nil then
			built.Host = p
		end
		if kitId == A.CheckpointKit and booth == nil and p.Name == A.CheckpointHost then
			booth = p
		end
	end
	if kitId == A.CheckpointKit and #parts > 0 then
		if booth then
			table.insert(built.Booths, { Part = booth, Frame = kcf })
		else
			built.MissingBooths += 1
		end
	end
end

-- the part cap of this place for this quality
local function partsCapOf(ctx: Ctx, rows: Rows): number
	local poi = ctx.Poi
	local low = ctx.Quality == "Low"
	local fullPlanned = 0
	for _, c in ipairs(rows.Clusters) do
		fullPlanned += (planned(c))
	end
	for _, inf in ipairs(rows.Infra) do
		fullPlanned += infraParts(inf)
	end
	if not rows.Layout then
		-- the Town: Budget; Quality Low at POIShare of its planned Full build
		local partsCap = if low then math.min(poi.Budget, math.floor(fullPlanned * WorldDressConfig.Quality.Low.POIShare + 1e-9)) else poi.Budget
		return partsCap
	end
	local fullCap = poi.Budget - (poi.Reserve or 0)
	local share = poi.LowShare or WorldDressConfig.Quality.Low.POIShare
	return if low then math.min(fullCap, math.floor(fullPlanned * share + 1e-9)) else fullCap
end

-- ── infra strips (the airstrip runway): POI_<Id>.Infra, flat, no collision, exempt from H10 ──────────────────────────
local function infraWhy(ctx: Ctx, parts: { BasePart }): string?
	local poi, occ = ctx.Poi, ctx.Occ
	for _, p in ipairs(parts) do
		local x0, x1, _, y1, z0, z1 = partBox(p)
		if p.CanCollide or y1 > H.RoadMinTop then
			return "not a flat marking: " .. p.Name
		end
		local rect, circle = poi.Rect, poi.Circle
		if rect and (x0 < rect.X0 or x1 > rect.X1 or z0 < rect.Z0 or z1 > rect.Z1) then
			return "outside the footprint: " .. p.Name
		end
		if rect == nil and circle then
			for _, q in ipairs({ { x0, z0 }, { x0, z1 }, { x1, z0 }, { x1, z1 } }) do
				if math.sqrt((q[1] - circle.X) ^ 2 + (q[2] - circle.Z) ^ 2) > circle.R + 0.01 then
					return "outside the footprint circle: " .. p.Name
				end
			end
		end
		-- the strip as discs along its long side: every zone except the road corridor (flat) and event anchors
		local dx, dz = x1 - x0, z1 - z0
		local w = math.max(1, math.min(dx, dz))
		local n = math.max(1, math.ceil(math.max(dx, dz) / w))
		local r = w * 0.5 * math.sqrt(2)
		for i = 1, n do
			local t = (i - 0.5) / n
			local sx = if dx >= dz then x0 + dx * t else (x0 + x1) * 0.5
			local sz = if dx >= dz then (z0 + z1) * 0.5 else z0 + dz * t
			local why = WorldDress.Blocked(occ, sx, sz, r, { AllowPOI = poi.Id, RoadClear = 0, RoadR = 0, SkipEvents = true })
			if why ~= nil then
				return string.format("%s at (%.0f, %.0f): %s", p.Name, sx, sz, why)
			end
		end
	end
	return nil
end

local function buildInfra(ctx: Ctx, rows: Rows, partsCap: number)
	if #rows.Infra == 0 then
		return
	end
	local poi, row = ctx.Poi, ctx.Row
	local model = Instance.new("Model")
	model.Name = INFRA_NAME
	local placed = 0
	local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
	for _, inf in ipairs(rows.Infra) do
		local what = "infra " .. inf.Id
		local s = WorldKits.Specs[inf.Kit]
		if s == nil or s.Class ~= "infra" then
			skip(ctx, what, "not an infra kit: " .. inf.Kit)
			continue
		end
		local pParts = infraParts(inf)
		if row.Parts + placed + pParts > partsCap then
			skip(ctx, what, string.format("caps: parts %d + %d > %d", row.Parts + placed, pParts, partsCap))
			continue
		end
		local before = childSet(model)
		local kcf = CFrame.new(inf.X, GROUND_Y, inf.Z) * CFrame.Angles(0, math.rad(inf.Yaw), 0)
		WorldKits.Add(model, inf.Kit, kcf, infraOpts(inf))
		local parts = freshParts(model, before)
		local why = if #parts == 0 then "no parts" else infraWhy(ctx, parts)
		if why == nil then
			for _, p in ipairs(parts) do
				if p:FindFirstChildWhichIsA("Light", true) or p:FindFirstChildWhichIsA("SurfaceGui", true) then
					why = "an infra strip carries no light or sign: " .. p.Name
					break
				end
			end
		end
		if why ~= nil then
			for _, ch in ipairs(model:GetChildren()) do
				if not before[ch] then
					ch:Destroy()
				end
			end
			skip(ctx, what, why)
			continue
		end
		for _, p in ipairs(parts) do
			local a0, a1, _, _, b0, b1 = partBox(p)
			x0, x1, z0, z1 = math.min(x0, a0), math.max(x1, a1), math.min(z0, b0), math.max(z1, b1)
		end
		placed += #parts
	end
	if placed == 0 then
		model:Destroy()
		return
	end
	model:SetAttribute("WE_Cluster", "poi:infra")
	model:SetAttribute("WE_Anchor", "poi:" .. poi.Id)
	model:SetAttribute("WE_AnchorX", math.floor((x0 + x1) * 50 + 0.5) / 100)
	model:SetAttribute("WE_AnchorZ", math.floor((z0 + z1) * 50 + 0.5) / 100)
	model:SetAttribute("WE_Tier", 1)
	model:SetAttribute(INFRA_ATTR, true)
	model.Parent = ctx.Folder
	row.Parts += placed
end

-- ── clusters (the Town and every layout) ───────────────────────────────────────────────────────────────────────────
local function placeClusters(ctx: Ctx, rows: Rows, partsCap: number)
	local T = WorldConfig.Town
	local poi, occ, row = ctx.Poi, ctx.Occ, ctx.Row
	local low = ctx.Quality == "Low"
	local roads = occ.Zones.Roads
	local lightsCap, signsCap = row.LightsCap, row.SignsCap
	local anchor = "poi:" .. poi.Id

	for _, c in ipairs(rows.Clusters) do
		if low and c.Tier ~= 1 then
			continue
		end
		local pParts, pLights = planned(c)
		if row.Parts + pParts > partsCap or row.Lights + pLights > lightsCap then
			skip(ctx, c.Id, string.format("caps: parts %d + %d > %d or lights %d + %d > %d", row.Parts, pParts, partsCap, row.Lights, pLights, lightsCap))
			continue
		end
		local model = WorldKits.NewCluster(c.Id, { Source = "poi", Kind = c.Role, Anchor = anchor, AnchorX = c.X, AnchorZ = c.Z, Tier = c.Tier, InWater = c.InWater })
		local frame = CFrame.new(c.X, GROUND_Y, c.Z) * CFrame.Angles(0, math.rad(c.Yaw), 0)
		local built: Built = { First = nil, Host = nil, Booths = {}, MissingBooths = 0 }
		local signsHere = 0
		for _, k in ipairs(c.Kits) do
			local text = k.Text
			if text == nil and k.Kit == "PoiBoard" then
				text = rows.Board
			end
			if text ~= nil and row.Signs + signsHere + 1 > signsCap then
				text = nil -- the POI's sign cap: the board stays, unpainted
			end
			if text ~= nil then
				signsHere += 1
			end
			local kcf = frame * CFrame.new(k.X, 0, k.Z) * CFrame.Angles(0, math.rad(k.Yaw or 0), 0)
			local before = childSet(model)
			WorldKits.Add(model, k.Kit, kcf, kitOpts(k, text))
			noteKit(built, k.Kit, freshParts(model, before), kcf)
		end
		local m = measure(model, roads, poi.Rect)
		local cx, cz = (m.X0 + m.X1) * 0.5, (m.Z0 + m.Z1) * 0.5
		local r = 0.5 * math.sqrt((m.X1 - m.X0) ^ 2 + (m.Z1 - m.Z0) ^ 2)
		local hostOnly = isHostCluster(c)
		local why: string? = nil
		if m.Parts == 0 then
			why = "no parts"
		elseif c.Street then
			why = WorldDress.Blocked(occ, cx, cz, r, { AllowPOI = poi.Id, RoadClear = 0, RoadR = 0, AllowWater = c.InWater })
		elseif hostOnly then
			-- the invisible activity host (nothing to see or bump into): the default road test; may sit over an event anchor
			why = WorldDress.Blocked(occ, cx, cz, r, { AllowPOI = poi.Id, SkipEvents = true })
		elseif c.InWater == true then
			why = WorldDress.Blocked(occ, cx, cz, r, { AllowPOI = poi.Id, RoadClear = T.RoadClear, AllowWater = true, SkipEvents = m.Marking })
		else
			why = WorldDress.Blocked(occ, cx, cz, r, { AllowPOI = poi.Id, RoadClear = T.RoadClear })
			if m.Marking and why ~= nil and string.sub(why, 1, 13) == "anchor:Event_" then
				-- flat paving / a hold pad under an event anchor: the crate lands on it (every other zone still counts)
				why = WorldDress.Blocked(occ, cx, cz, r, { AllowPOI = poi.Id, RoadClear = T.RoadClear, SkipEvents = true })
			end
		end
		why = why or m.RoadWhy or m.Outside or circleWhy(poi, cx, cz, r)
		if why == nil and row.Parts + m.Parts > partsCap then
			why = string.format("budget %d + %d > %d", row.Parts, m.Parts, partsCap)
		end
		if why == nil and row.Lights + m.Lights > lightsCap then
			why = string.format("lights %d + %d > %d", row.Lights, m.Lights, lightsCap)
		end
		if why == nil and row.Signs + m.Signs > signsCap then
			why = string.format("signs %d + %d > %d", row.Signs, m.Signs, signsCap)
		end
		if why ~= nil then
			WorldKits.Discard(model)
			skip(ctx, c.Id, why)
			continue
		end
		model:SetAttribute("WE_AnchorX", math.floor(cx * 100 + 0.5) / 100)
		model:SetAttribute("WE_AnchorZ", math.floor(cz * 100 + 0.5) / 100)
		local info = WorldKits.Finish(model, ctx.Folder)
		if not info.Ok then
			skip(ctx, c.Id, info.Reason or "Finish refused")
			continue
		end
		if not m.Marking and not hostOnly then
			WorldDress.AddDisc(occ, cx, cz, r, anchor)
		end
		row.Parts += info.Parts
		row.Lights += info.Lights
		row.Signs += info.Signs
		row.Clusters += 1
		ctx.Built[c.Id] = built
	end
end

-- a stable per-place seed for the terrain rubble (the Town keeps Town.Seed)
local function seedOf(id: string): number
	local h = WorldConfig.Town.Seed
	for i = 1, #id do
		h = (h * 31 + string.byte(id, i)) % 2147483647
	end
	return h
end

-- ── terrain rubble and scorch (0 parts; each group's disc passes the same block rule) ────────────────────────────
local function placeRocks(ctx: Ctx, rows: Rows)
	local T = WorldConfig.Town
	local poi, occ, row = ctx.Poi, ctx.Occ, ctx.Row
	local low = ctx.Quality == "Low"
	local anchor = "poi:" .. poi.Id
	local rng = WorldKits.Rng(rows.Seed)
	for i, rk in ipairs(rows.Rocks) do
		if low and rk.Tier ~= 1 then
			continue
		end
		local maxCount = ((WorldConfig.Kits.Rock :: any)[rk.Kind] or { Count = { 0, 4 } }).Count[2] :: number
		if row.TerrainPrims + maxCount > T.MaxTerrainPrims then
			skip(ctx, "rock " .. i, "terrain prim cap")
			continue
		end
		local why = WorldDress.Blocked(occ, rk.X, rk.Z, rk.Radius, { AllowPOI = poi.Id, RoadClear = T.RoadClear })
		if why == nil and not insideFootprint(poi, rk.X, rk.Z, if poi.Rect then 0 else rk.Radius) then
			why = "outside the footprint"
		end
		if why ~= nil then
			skip(ctx, "rock " .. i, why)
			continue
		end
		local prims = WorldKits.Rock(Vector3.new(rk.X, GROUND_Y, rk.Z), rk.Kind, rng, { Radius = rk.Radius })
		WorldDress.AddDisc(occ, rk.X, rk.Z, rk.Radius, anchor)
		row.TerrainPrims += #prims
	end
end

-- ── activity anchors (0 parts): the checkpoint template, then the place's rows ─────────────────────────────────────
local function stampAnchors(ctx: Ctx, rows: Rows)
	local poi, row = ctx.Poi, ctx.Row
	local stamped: { [string]: boolean } = {}
	local function stamp(host: BasePart, def: ActivityAnchors.StampDef)
		if stamped[def.Id] then
			row.AnchorsAbsent += 1
			note(ctx, string.format("[WorldPOI] %s: anchor %s skipped (duplicate id)", poi.Id, def.Id))
			return
		end
		if ActivityAnchors.Stamp(host, def) then
			stamped[def.Id] = true
			row.Anchors += 1
		else
			row.AnchorsAbsent += 1
			table.insert(ctx.Warnings, string.format("[WorldPOI] %s: anchor %s refused by ActivityAnchors.Stamp", poi.Id, tostring(def.Id)))
		end
	end

	-- 1) every built checkpoint: the template on its CheckpointBooth (site = the cluster Id)
	local host: BasePart? = nil
	local known: { [string]: boolean } = {}
	for _, c in ipairs(rows.Clusters) do
		known[c.Id] = true
		local b = ctx.Built[c.Id]
		if b then
			if host == nil and b.Host ~= nil then
				host = b.Host
			end
			if b.MissingBooths > 0 then
				row.AnchorsAbsent += #A.CheckpointAnchors * b.MissingBooths
				note(ctx, string.format("[WorldPOI] %s: %s has no %s part; its checkpoint anchors are not stamped", poi.Id, c.Id, A.CheckpointHost))
			end
			for i, booth in ipairs(b.Booths) do
				if i > 1 then
					row.AnchorsAbsent += #A.CheckpointAnchors
					note(ctx, string.format("[WorldPOI] %s: %s holds more than one checkpoint; only the first gets anchors", poi.Id, c.Id))
					continue
				end
				for _, t in ipairs(A.CheckpointAnchors) do
					stamp(booth.Part, ActivityAnchors.FromTemplate(t, poi.Id, c.Id, booth.Frame))
				end
			end
		end
	end

	-- 2) the rows: a layout's on its ActivityHost, the Town's on the first part of the cluster they Require
	local prefix = poi.Id .. "."
	local noHost = 0
	for _, a in ipairs(rows.Anchors) do
		local req = a.Requires
		if string.sub(a.Id, 1, #prefix) ~= prefix then
			row.AnchorsAbsent += 1
			note(ctx, string.format("[WorldPOI] %s: anchor %s skipped (not an id of this place)", poi.Id, a.Id))
			continue
		end
		if req ~= nil and not known[req] then
			row.AnchorsAbsent += 1
			note(ctx, string.format("[WorldPOI] %s: anchor %s skipped (Requires %s: no such cluster)", poi.Id, a.Id, req))
			continue
		end
		if not insideFootprint(poi, a.X, a.Z, 0) then
			row.AnchorsAbsent += 1
			note(ctx, string.format("[WorldPOI] %s: anchor %s skipped (outside the footprint)", poi.Id, a.Id))
			continue
		end
		local need = if req ~= nil then ctx.Built[req] else nil
		if req ~= nil and need == nil then
			row.AnchorsAbsent += 1 -- its cluster was not built (Quality Low drops Tier 2; a skipped cluster was warned)
			continue
		end
		local target: BasePart? = nil
		if rows.Layout then
			target = host
		elseif need ~= nil then
			target = need.First
		end
		if target == nil then
			row.AnchorsAbsent += 1
			noHost += 1
			continue
		end
		stamp(target, ActivityAnchors.FromRow(a))
	end
	if noHost > 0 then
		local why = if rows.Layout then "no " .. A.HostKit .. " cluster was built" else "a Town row needs Requires (its host cluster)"
		note(ctx, string.format("[WorldPOI] %s: %d anchor rows not stamped (%s)", poi.Id, noHost, why))
	end
end

-- ── places ─────────────────────────────────────────────────────────────────────────────────────────────────────────
local function buildPlace(ctx: Ctx, rows: Rows)
	local partsCap = partsCapOf(ctx, rows)
	buildInfra(ctx, rows, partsCap)
	placeClusters(ctx, rows, partsCap)
	placeRocks(ctx, rows)
	stampAnchors(ctx, rows)
end

-- Crossroads Town: its rows live in WorldConfig.Town
local function buildTown(ctx: Ctx)
	local T = WorldConfig.Town
	buildPlace(ctx, { Clusters = T.Clusters, Rocks = T.Rocks, Infra = {}, Anchors = T.Anchors, Board = T.BoardText, Seed = T.Seed, Layout = false })
end

-- POILayouts groups, required once (a failed or missing module warns and its places build nothing)
type GroupLoad = { Group: LayoutGroup?, Err: string? }
local groups: { [string]: GroupLoad } = {}
local function layoutGroup(name: string): GroupLoad
	local hit = groups[name]
	if hit then
		return hit
	end
	local res: GroupLoad = { Group = nil, Err = nil }
	local folder = script.Parent:FindFirstChild("POILayouts")
	local mod = if folder then folder:FindFirstChild(name) else nil
	if mod == nil or not mod:IsA("ModuleScript") then
		res.Err = "no module POILayouts." .. name
	else
		local ok, got = pcall(function(): any
			return (require :: any)(mod)
		end)
		if ok and type(got) == "table" then
			res.Group = got :: LayoutGroup
		else
			res.Err = "POILayouts." .. name .. " failed to load: " .. tostring(got)
		end
	end
	groups[name] = res
	return res
end

-- every other place: its rows live in Server/Modules/POILayouts/<POI.Layout>[Id]
local function buildLayout(ctx: Ctx)
	local poi = ctx.Poi
	local name = poi.Layout or "?"
	local load = layoutGroup(name)
	local group = load.Group
	local l = if group then group[poi.Id] else nil
	if l == nil then
		note(ctx, string.format("[WorldPOI] %s: no layout rows (%s)", poi.Id, load.Err or ("POILayouts." .. name .. " has no " .. poi.Id)))
		return
	end
	buildPlace(ctx, {
		Clusters = l.Clusters or {},
		Rocks = l.Rocks or {},
		Infra = l.Infra or {},
		Anchors = l.Anchors or {},
		Board = l.Board,
		Seed = seedOf(poi.Id),
		Layout = true,
	})
end

local BUILDERS: { [string]: (Ctx) -> () } = {
	town = buildTown,
}

function WorldPOI.Build(dressing: Instance, quality: string, occ: Occupancy?): Summary
	local t0 = os.clock()
	local q = WorldDress.Quality(quality)
	local o: Occupancy = occ or WorldDress.NewOccupancy()
	local summary: Summary = { Quality = q, POIs = {}, Parts = 0, Lights = 0, Signs = 0, Clusters = 0, TerrainPrims = 0, Anchors = 0, Seconds = 0, Warnings = {} }
	for _, p in ipairs(WorldConfig.POIs) do
		local row: POISummary = {
			Id = p.Id,
			Enabled = p.Enabled == true,
			Built = false,
			Parts = 0,
			Budget = p.Budget - (p.Reserve or 0),
			Lights = 0,
			LightsCap = p.Lights or 0,
			Signs = 0,
			SignsCap = p.Signs or 0,
			Clusters = 0,
			Skipped = 0,
			TerrainPrims = 0,
			Anchors = 0,
			AnchorsAbsent = 0,
		}
		table.insert(summary.POIs, row)
		if row.Enabled then
			local name = WorldPOI.FolderName(p.Id)
			local old = dressing:FindFirstChild(name)
			if old then
				old:Destroy()
			end
			local builder: ((Ctx) -> ())? = if p.Layout ~= nil then buildLayout else BUILDERS[p.Kind]
			if builder == nil then
				local msg = string.format("[WorldPOI] %s: no builder for kind %q yet", p.Id, p.Kind)
				table.insert(summary.Warnings, msg)
				warn(msg)
			else
				local folder = Instance.new("Folder")
				folder.Name = name
				folder.Parent = dressing
				local ctx: Ctx = { Poi = p, Folder = folder, Quality = q, Occ = o, Row = row, Warnings = summary.Warnings, Built = {} }
				local ok, err = pcall(function(): string?
					builder(ctx)
					return nil
				end)
				if not ok then
					local msg = string.format("[WorldPOI] %s build failed: %s", p.Id, tostring(err))
					table.insert(summary.Warnings, msg)
					warn(msg)
				end
				row.Built = row.Clusters > 0
			end
		end
		summary.Parts += row.Parts
		summary.Lights += row.Lights
		summary.Signs += row.Signs
		summary.Clusters += row.Clusters
		summary.TerrainPrims += row.TerrainPrims
		summary.Anchors += row.Anchors
	end
	summary.Seconds = os.clock() - t0
	for _, row in ipairs(summary.POIs) do
		if row.Enabled then
			print(string.format(
				"[WAR EMPIRE] WorldPOI: %s %s %d/%d parts, %d lights, %d signs, %d clusters, %d skipped, %d terrain (%.3f s)",
				q,
				row.Id,
				row.Parts,
				row.Budget,
				row.Lights,
				row.Signs,
				row.Clusters,
				row.Skipped,
				row.TerrainPrims,
				summary.Seconds
			))
			if row.Anchors + row.AnchorsAbsent > 0 then
				print(string.format("[WAR EMPIRE] WorldPOI: %s %s activity anchors %d stamped, %d absent", q, row.Id, row.Anchors, row.AnchorsAbsent))
			end
		end
	end
	return summary
end

return WorldPOI
