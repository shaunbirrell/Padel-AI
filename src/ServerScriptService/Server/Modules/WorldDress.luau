--!strict
--[[
	WAR EMPIRE World v2 Phase 2 (W3) — WorldDress: the travel dressing BETWEEN the POIs (gap/world_v2_spec.md §4.1–§4.4,
	roadmap §2.4 WORLD-B builder 2), plus the ONE shared keep-out source that WorldPOI and WorldDress both use.
	Tunables: Shared/Configs/WorldDressConfig. Kits: Modules/WorldKits (B1). Order (MapDressing.Dress, B2):
	WorldPOI.Build → Dockside (as-is) → WorldDress.Build (rhythm, junctions, shore, scatter) → Waterways.CullDressing →
	WorldHygiene.Enforce.

	CONTRACT (scratchpad/w3/contracts.md §3–§4): owner = B2. The keep-out source (Zones, NewOccupancy, AddDisc, Blocked,
	RoadDist, POIDist, Quality) is pure (config math only, no workspace reads, streaming-safe). Build composes every
	cluster from WorldKits (Part kits + Terrain rocks), seeded with WorldKits.Rng(Seed + salt) so the headless sim and a
	live server build the same layout, and never yields on InsertService (mesh overlays are WorldKits' deferred job).
	  Rhythm    — along every road: a spot every rng(140, 180), rng(16, 34) off the centre line, sides alternating;
	              kinds rotate rock outcrop (Terrain) / wreck or MG nest / flora group / km or hazard marker. Never within
	              70 of a junction, never in a keep-out; the real parts stay >= 13 (collidable) / >= 9 (visible) off
	              every road line (pushed out along the road, never past 34). Low: half of each road's clusters.
	  Junctions — one corner kit per visible junction: arrow post, jersey pair on both shoulders, sandbag arc, boulders.
	  Shore     — every 320 along the ring canal's inner bank (revetment / reeds + rocks / jetty stub / barge wreck; the
	              jetty, barge and beached hull step <= 10 into the canal or the sea, never a channel, lagoon or harbour)
	              and every 300 along the Bay's north shore (driftwood + rocks / beached hull / dune grass).
	  Scatter   — Full only: natural clusters (Terrain rocks, flora groups, dead wood; >= 3 elements of >= 2 sizes) into
	              the largest empty circles until none is wider than 340 (Poisson: >= 120 apart, >= 40 off roads).

	PUBLIC API (server only; WorldDress never requires WorldPOI):
	  WorldDress.Zones() -> Zones
	      Every keep-out from the configs: ring interior, road centre lines, water (public + channels + plot water),
	      plot pads, front-gate aprons, land garage pads, capture clear circles, the Empire Bank, event / NPC anchors,
	      rig pier corridors, all 18 POI footprints (enabled or not) and the 6 visible junctions. Depends on
	      BaseLayoutConfig.FaceMapCentre exactly like Waterways / WorldHygiene.
	  WorldDress.NewOccupancy(zones?) -> Occupancy          zones + the discs placed so far (POI clusters, travel clusters)
	  WorldDress.AddDisc(occ, x, z, r, kind)
	  WorldDress.Blocked(occ, x, z, r, opts?) -> string?     nil = the disc (centre x, z, radius r) is free; else the first
	                                                          reason: "ring" | "road" | "water:<rect>" | "plot:<n>" |
	                                                          "apron:<n>" | "pad:<id>" | "capture:<id>" | "structure:<n>" |
	                                                          "anchor:<id>" | "clear:<n>" | "poi:<Id>" | "occupied:<kind>"
	                                                          W3 step 2: a camp's own NPC anchors (inside a Kind "camp"
	                                                          footprint) are no keep-out when AllowPOI names that camp
	                                                          (its sandbags stand at the guard posts); opts.SkipEvents
	                                                          lets a flat marking / the invisible activity host lie over
	                                                          an event anchor (every other zone still counts)
	  WorldDress.RoadDist(zones, x, z) -> number             XZ distance to the nearest road centre segment
	  WorldDress.POIDist(poi, x, z) -> number                XZ distance to a POI footprint (0 inside)
	  WorldDress.Quality(q?) -> "Full" | "Low"
	  WorldDress.Build(dressing, quality, occ?) -> Summary   builds WorldDressing.Rhythm / Junctions / Shore / Scatter
                                                          (replaces old ones: idempotent) and logs one summary line
  WorldDress.Emptiness(occ, cell?) -> Emptiness           the V10 metric over an occupancy (share of dry land > 100
                                                          from anything, the largest empty circle)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage.Shared.Configs
local WorldConfig = require(Configs.WorldConfig)
local WorldDressConfig = require(Configs.WorldDressConfig)
local TerritoryConfig = require(Configs.TerritoryConfig)
local BaseConfig = require(Configs.BaseConfig)
local BankRaidConfig = require(Configs.BankRaidConfig)
local BaseLayout = require(script.Parent.BaseLayout)
local Waterways = require(script.Parent.Waterways)
local WorldKits = require(script.Parent.WorldKits)

export type Rect = { Name: string, X0: number, X1: number, Z0: number, Z1: number }
export type Circle = { Name: string, X: number, Z: number, R: number, Owner: string? } -- Owner: the camp an NPC anchor belongs to
export type Road = Waterways.RoadLine
export type POIZone = { Id: string, Enabled: boolean, Rect: Rect?, Circle: Circle? }
export type Point = { X: number, Z: number }
export type Zones = {
	Ring: Rect,
	Roads: { Road },
	Water: { Rect },
	PlotPads: { Rect },
	Aprons: { Rect },
	Pads: { Rect },
	Captures: { Circle }, -- radius = Territory R x CaptureScale + CaptureExtra
	Structures: { Circle },
	Anchors: { Circle },
	ClearRects: { Rect },
	POIs: { POIZone },
	Junctions: { Point },
}
export type Disc = { X: number, Z: number, R: number, Kind: string }
export type Occupancy = { Zones: Zones, Discs: { Disc } }
export type BlockOpts = {
	AllowPOI: string?, -- the POI being built: its own footprint is not a keep-out (every zone inside it still is)
	RoadClear: number?, -- default Keepout.RoadClear (13): disc edge to any road centre line
	RoadR: number?, -- radius used for the road test only (default r): e.g. a kit's across-road half extent
	POIMargin: number?, -- default Keepout.POIMargin (30)
	Spacing: number?, -- min edge-to-edge gap to every disc already in the occupancy (nil = no spacing test)
	AllowWater: boolean?, -- jetty stub / barge / hull: skip the water test (the cluster carries WE_AllowInWater)
	SkipRing: boolean?,
	SkipEvents: boolean?, -- W3 step 2: a flat marking / the invisible activity host may lie over an event anchor
}
export type SectionSummary = {
	Name: string, -- "Rhythm" | "Junctions" | "Shore" | "Scatter"
	Clusters: number,
	Parts: number,
	PartsCap: number,
	TerrainPrims: number,
	Rejected: { [string]: number }, -- candidate spots dropped, by Blocked reason
}
export type Summary = {
	Quality: string,
	Sections: { SectionSummary },
	Parts: number,
	Clusters: number,
	TerrainPrims: number,
	LargestEmpty: number, -- diameter of the largest empty circle after scatter (0 = not measured)
	Far100: number, -- share of dry land > 100 studs from anything (0 = not measured)
	Seconds: number,
	Warnings: { string },
}

local WorldDress = {}

local K = WorldDressConfig.Keepout

-- ── geometry helpers ──────────────────────────────────────────────────────────────────────────────────────────────

local function rectDist(r: Rect, x: number, z: number): number
	local dx = math.max(r.X0 - x, 0, x - r.X1)
	local dz = math.max(r.Z0 - z, 0, z - r.Z1)
	return math.sqrt(dx * dx + dz * dz)
end

local function toSet(list: { string }): { [string]: boolean }
	local s: { [string]: boolean } = {}
	for _, v in ipairs(list) do
		s[v] = true
	end
	return s
end

function WorldDress.RoadDist(zones: Zones, x: number, z: number): number
	local best = math.huge
	for _, r in ipairs(zones.Roads) do
		local along = if r.AlongX then x else z
		local across = if r.AlongX then z else x
		local t = math.clamp(along, r.Min, r.Max)
		local d = math.sqrt((along - t) ^ 2 + (across - r.Across) ^ 2)
		if d < best then
			best = d
		end
	end
	return best
end

function WorldDress.POIDist(poi: POIZone, x: number, z: number): number
	local rect = poi.Rect
	if rect then
		return rectDist(rect, x, z)
	end
	local c = poi.Circle
	if c then
		return math.max(0, math.sqrt((x - c.X) ^ 2 + (z - c.Z) ^ 2) - c.R)
	end
	return math.huge
end

function WorldDress.Quality(q: string?): string
	return if string.lower(tostring(q or "Low")) == "full" then "Full" else "Low"
end

local EVENT_PREFIX = "Event_" -- the event-anchor zone names (Blocked: "anchor:Event_<Id>")
local CAMP_KIND = "camp" -- WorldConfig.POIs Kind of the camps whose NPC anchors are their own guard posts

-- the camp POI whose footprint holds (x, z), if any (enabled or not: a disabled camp builds nothing anyway)
local function campOf(x: number, z: number): string?
	for _, p in ipairs(WorldConfig.POIs) do
		if p.Kind == CAMP_KIND then
			local zone: POIZone = { Id = p.Id, Enabled = true, Rect = nil, Circle = nil }
			if p.Rect then
				zone.Rect = { Name = p.Id, X0 = p.Rect.X0, X1 = p.Rect.X1, Z0 = p.Rect.Z0, Z1 = p.Rect.Z1 }
			elseif p.Circle then
				zone.Circle = { Name = p.Id, X = p.Circle.X, Z = p.Circle.Z, R = p.Circle.R }
			end
			if (zone.Rect ~= nil or zone.Circle ~= nil) and WorldDress.POIDist(zone, x, z) <= 0 then
				return p.Id
			end
		end
	end
	return nil
end

-- ── the shared keep-out source ────────────────────────────────────────────────────────────────────────────────────

function WorldDress.Zones(): Zones
	local ring = K.Ring
	local zones: Zones = {
		Ring = { Name = "Ring", X0 = ring.X0, X1 = ring.X1, Z0 = ring.Z0, Z1 = ring.Z1 },
		Roads = Waterways.RoadLines(),
		Water = {},
		PlotPads = {},
		Aprons = {},
		Pads = {},
		Captures = {},
		Structures = {},
		Anchors = {},
		ClearRects = {},
		POIs = {},
		Junctions = {},
	}
	for _, r in ipairs(Waterways.AllRects()) do
		table.insert(zones.Water, { Name = r.Name or "water", X0 = r.X0, X1 = r.X1, Z0 = r.Z0, Z1 = r.Z1 })
	end

	-- plot pads and front-gate aprons (plot-local, so they turn with BaseLayoutConfig.FaceMapCentre)
	local plotPositions = BaseConfig.PlotPositions :: { Vector3 }
	local half = (BaseConfig.PlotSize :: Vector3).X * 0.5
	local apron = WorldConfig.Hygiene.GateApron
	for plotId, pos in ipairs(plotPositions) do
		table.insert(zones.PlotPads, { Name = "Plot" .. plotId, X0 = pos.X - half, X1 = pos.X + half, Z0 = pos.Z - half, Z1 = pos.Z + half })
		local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
		for _, c in ipairs({ { apron.X0, apron.Z0 }, { apron.X1, apron.Z0 }, { apron.X0, apron.Z1 }, { apron.X1, apron.Z1 } }) do
			local w = BaseLayout.PlotPoint(pos, c[1], c[2])
			x0, x1, z0, z1 = math.min(x0, w.X), math.max(x1, w.X), math.min(z0, w.Z), math.max(z1, w.Z)
		end
		table.insert(zones.Aprons, { Name = "Apron_P" .. plotId, X0 = x0, X1 = x1, Z0 = z0, Z1 = z1 })
	end

	-- land garage pads (MapSetup builds them from the same config; yaw is a multiple of 90, so the AABB is square)
	local padSize = WorldConfig.Spawns.PadSize
	local padHalf = math.max(padSize.X, padSize.Z) * 0.5
	for _, g in ipairs(WorldConfig.Spawns.Garage) do
		local px: number?, pz: number? = nil, nil
		if g.PlotId ~= nil then
			local pos = plotPositions[g.PlotId]
			if pos then
				local w = BaseLayout.PlotPoint(pos, g.LocalX or 0, g.LocalZ or 0)
				px, pz = w.X, w.Z
			end
		elseif g.X ~= nil and g.Z ~= nil then
			px, pz = g.X, g.Z
		end
		if px and pz then
			table.insert(zones.Pads, { Name = g.Id, X0 = px - padHalf, X1 = px + padHalf, Z0 = pz - padHalf, Z1 = pz + padHalf })
		end
	end

	-- capture clear circles (TerritoryCapture uses the marker half-diagonal)
	local skip = toSet(K.CaptureSkip)
	for id, t in pairs(TerritoryConfig.Territories :: { [string]: any }) do
		if not skip[id] then
			local p: Vector3 = t.Position
			local r: number = t.Radius
			table.insert(zones.Captures, { Name = id, X = p.X, Z = p.Z, R = r * K.CaptureScale + K.CaptureExtra })
		end
	end
	table.sort(zones.Captures, function(a: Circle, b: Circle): boolean
		return a.Name < b.Name
	end)

	-- the Empire Bank (plaza + guard ring; BankRaidService spawns guards on the ring)
	local bank: Vector3 = BankRaidConfig.Position
	local guardR: number = BankRaidConfig.GuardRingRadius or 18
	table.insert(zones.Structures, { Name = "EmpireBank", X = bank.X, Z = bank.Z, R = guardR + K.BankExtra })

	-- event anchors (supply crates land there) and NPC anchors (hostile spawns). W3 step 2: an NPC anchor inside a camp
	-- footprint (POI Kind "camp") belongs to that camp (Owner): the camp's own clusters may stand at it (the sandbags its
	-- guards stand behind), every other cluster still keeps out
	for _, a in ipairs(WorldConfig.Spawns.Event) do
		table.insert(zones.Anchors, { Name = EVENT_PREFIX .. a.Id, X = a.X, Z = a.Z, R = K.EventClear })
	end
	for _, a in ipairs(WorldConfig.Spawns.NPC) do
		table.insert(zones.Anchors, { Name = "NPC_" .. a.Id, X = a.X, Z = a.Z, R = K.NPCClear, Owner = campOf(a.X, a.Z) })
	end

	-- rig pier corridors (WorldConfig.Hygiene.ClearRects)
	for _, r in ipairs(WorldConfig.Hygiene.ClearRects) do
		table.insert(zones.ClearRects, { Name = r.Name or "clear", X0 = r.X0, X1 = r.X1, Z0 = r.Z0, Z1 = r.Z1 })
	end

	-- every POI footprint: enabled POIs are built by WorldPOI, disabled ones stay reserved for their later step
	for _, p in ipairs(WorldConfig.POIs) do
		local zone: POIZone = { Id = p.Id, Enabled = (p :: any).Enabled == true, Rect = nil, Circle = nil }
		if p.Rect then
			zone.Rect = { Name = p.Id, X0 = p.Rect.X0, X1 = p.Rect.X1, Z0 = p.Rect.Z0, Z1 = p.Rect.Z1 }
		elseif p.Circle then
			zone.Circle = { Name = p.Id, X = p.Circle.X, Z = p.Circle.Z, R = p.Circle.R }
		end
		table.insert(zones.POIs, zone)
	end

	for _, j in ipairs(WorldDressConfig.Junctions.Points) do
		table.insert(zones.Junctions, { X = j.X, Z = j.Z })
	end
	return zones
end

function WorldDress.NewOccupancy(zones: Zones?): Occupancy
	return { Zones = zones or WorldDress.Zones(), Discs = {} }
end

function WorldDress.AddDisc(occ: Occupancy, x: number, z: number, r: number, kind: string)
	table.insert(occ.Discs, { X = x, Z = z, R = r, Kind = kind })
end

function WorldDress.Blocked(occ: Occupancy, x: number, z: number, r: number, opts: BlockOpts?): string?
	local o: BlockOpts = opts or {}
	local zones = occ.Zones
	if not o.SkipRing then
		local ring = zones.Ring
		if x - r < ring.X0 or x + r > ring.X1 or z - r < ring.Z0 or z + r > ring.Z1 then
			return "ring"
		end
	end
	if WorldDress.RoadDist(zones, x, z) - (o.RoadR or r) < (o.RoadClear or K.RoadClear) then
		return "road"
	end
	if not o.AllowWater then
		for _, w in ipairs(zones.Water) do
			if rectDist(w, x, z) < r + K.WaterMargin then
				return "water:" .. w.Name
			end
		end
	end
	for _, p in ipairs(zones.PlotPads) do
		if rectDist(p, x, z) < r + K.PlotPadMargin then
			return "plot:" .. p.Name
		end
	end
	for _, a in ipairs(zones.Aprons) do
		if rectDist(a, x, z) < r + K.ApronMargin then
			return "apron:" .. a.Name
		end
	end
	for _, p in ipairs(zones.Pads) do
		if rectDist(p, x, z) < r + K.PadMargin then
			return "pad:" .. p.Name
		end
	end
	for _, c in ipairs(zones.Captures) do
		if math.sqrt((x - c.X) ^ 2 + (z - c.Z) ^ 2) - r < c.R then
			return "capture:" .. c.Name
		end
	end
	for _, c in ipairs(zones.Structures) do
		if math.sqrt((x - c.X) ^ 2 + (z - c.Z) ^ 2) - r < c.R then
			return "structure:" .. c.Name
		end
	end
	for _, c in ipairs(zones.Anchors) do
		local own = c.Owner ~= nil and c.Owner == o.AllowPOI -- a camp's own guard post
		local event = o.SkipEvents == true and string.sub(c.Name, 1, #EVENT_PREFIX) == EVENT_PREFIX
		if not own and not event and math.sqrt((x - c.X) ^ 2 + (z - c.Z) ^ 2) - r < c.R then
			return "anchor:" .. c.Name
		end
	end
	for _, c in ipairs(zones.ClearRects) do
		if rectDist(c, x, z) < r then
			return "clear:" .. c.Name
		end
	end
	local margin = o.POIMargin or K.POIMargin
	for _, p in ipairs(zones.POIs) do
		if p.Id ~= o.AllowPOI and WorldDress.POIDist(p, x, z) < r + margin then
			return "poi:" .. p.Id
		end
	end
	local spacing = o.Spacing
	if spacing ~= nil then
		for _, d in ipairs(occ.Discs) do
			if math.sqrt((x - d.X) ^ 2 + (z - d.Z) ^ 2) - r - d.R < spacing then
				return "occupied:" .. d.Kind
			end
		end
	end
	return nil
end

-- ── Build ─────────────────────────────────────────────────────────────────────────────────────────────────────────
-- Every cluster is composed from WorldKits (B1's Part kits and Terrain rocks), checked against the keep-outs twice:
--   * its disc (centre, radius) with Blocked — the contract rule the verifier re-runs on the occupancy;
--   * its real parts, measured after WorldKits.Add: collidable parts >= 13 and visible parts >= 9 from every road centre
--     line (H2; a road-side cluster is pushed out along its road, never past Offset max), and the part AABBs clear every
--     WorldHygiene H3 zone (captures, aprons, garage pads + 16, plot pads + 4, pier corridors, water + 6).
-- So Waterways.CullDressing and WorldHygiene.Enforce find nothing to remove in these sections.

type Rng = WorldKits.Rng
type RockRow = WorldDressConfig.RockRow
type KitOpts = WorldKits.KitOpts
type Piece = { Kit: string, X: number, Z: number, Yaw: number, Opts: KitOpts? }
type RockReq = { Style: string, X: number, Z: number } -- local offsets in the cluster frame; Style = Terrain.Rocks key
type Recipe = { Pieces: { Piece }, Rocks: { RockReq }, Natural: boolean, InWater: boolean }
type Box = { X0: number, X1: number, Y0: number, Y1: number, Z0: number, Z1: number }
type Ctx = {
	Quality: string,
	Full: boolean,
	Occ: Occupancy,
	Zones: Zones,
	Warnings: { string },
	Prims: number, -- terrain prims actually filled
	PrimsReserved: number, -- MaxPrims per accepted rock, Full or Low alike (the budget decision never depends on quality)
	Busy: number,
	SegStart: number,
	SinceYield: number,
}
type Built = { Ok: boolean, Reason: string?, Model: Model?, X: number, Z: number, Parts: number, Rocks: { { Pos: Vector3, Style: string } } }
type Field = {
	Cell: number,
	X0: number, -- centre of cell 1
	Z0: number,
	NX: number,
	NZ: number,
	D2: { number }, -- squared distance to the nearest "anything" (capped at FieldMax^2)
	Valid: { boolean }, -- dry land, not on a plot pad
	Cap: number,
}
type EmptyCircle = { X: number, Z: number, R: number, Idx: number }

local HY = WorldConfig.Hygiene
local GROUND_Y = 0.5
local RH = WorldDressConfig.Rhythm
local JN = WorldDressConfig.Junctions
local SH = WorldDressConfig.Shore
local SC = WorldDressConfig.Scatter
local TR = WorldDressConfig.Terrain
local BUD = WorldDressConfig.Budgets
local FOLDERS = WorldDressConfig.Folders

local function hasPrefix(name: string, list: { string }): boolean
	for _, p in ipairs(list) do
		if string.sub(name, 1, #p) == p then
			return true
		end
	end
	return false
end

local ROAD_EXEMPT = toSet(HY.RoadExemptNames)

local function partBox(p: BasePart): Box
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = p.CFrame:GetComponents()
	local s = p.Size
	local hx = (math.abs(r00) * s.X + math.abs(r01) * s.Y + math.abs(r02) * s.Z) * 0.5
	local hy = (math.abs(r10) * s.X + math.abs(r11) * s.Y + math.abs(r12) * s.Z) * 0.5
	local hz = (math.abs(r20) * s.X + math.abs(r21) * s.Y + math.abs(r22) * s.Z) * 0.5
	return { X0 = x - hx, X1 = x + hx, Y0 = y - hy, Y1 = y + hy, Z0 = z - hz, Z1 = z + hz }
end

local function partsOf(m: Instance): { BasePart }
	local out: { BasePart } = {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

local function unionBox(parts: { BasePart }): Box?
	if #parts == 0 then
		return nil
	end
	local b: Box = { X0 = math.huge, X1 = -math.huge, Y0 = math.huge, Y1 = -math.huge, Z0 = math.huge, Z1 = -math.huge }
	for _, p in ipairs(parts) do
		local pb = partBox(p)
		b.X0, b.X1 = math.min(b.X0, pb.X0), math.max(b.X1, pb.X1)
		b.Y0, b.Y1 = math.min(b.Y0, pb.Y0), math.max(b.Y1, pb.Y1)
		b.Z0, b.Z1 = math.min(b.Z0, pb.Z0), math.max(b.Z1, pb.Z1)
	end
	return b
end

local function translate(parts: { BasePart }, delta: Vector3)
	for _, p in ipairs(parts) do
		p.CFrame = p.CFrame + delta
	end
end

-- yaw (radians) whose LookVector (the kit front, local -Z) points along (dx, dz)
local function facingYaw(dx: number, dz: number): number
	return math.atan2(-dx, -dz)
end

local function frameAt(x: number, z: number, yaw: number): CFrame
	return CFrame.new(x, GROUND_Y, z) * CFrame.Angles(0, yaw, 0)
end

-- H2 on the real parts. own = the road a road-side cluster stands beside (side = +1 / -1 across its centre line):
-- returns how far the cluster must move away from `own` so every collidable part is >= CollidableRoadGap and every
-- visible part >= VisibleRoadGap from it; any other road closer than that → a reason (the spot is dropped).
local function roadCheck(zones: Zones, parts: { BasePart }, own: Road?, side: number): (number, string?)
	local need = 0
	for _, p in ipairs(parts) do
		if not ROAD_EXEMPT[p.Name] then
			local b = partBox(p)
			local collide = p.CanCollide and b.Y1 > HY.RoadMinTop
			local visible = p.Transparency < 0.99 and b.Y1 > GROUND_Y + HY.RoadLaneMaxHeight and not hasPrefix(p.Name, HY.RoadMarkingPrefixes)
			if collide or visible then
				local req = if collide then RH.CollidableRoadGap else RH.VisibleRoadGap
				for _, r in ipairs(zones.Roads) do
					local a0, a1, c0, c1 = b.X0, b.X1, b.Z0, b.Z1
					if not r.AlongX then
						a0, a1, c0, c1 = b.Z0, b.Z1, b.X0, b.X1
					end
					if a1 >= r.Min and a0 <= r.Max then
						if own ~= nil and r.Name == own.Name then
							local signed = if side > 0 then c0 - r.Across else r.Across - c1
							if signed < req then
								need = math.max(need, req - signed)
							end
						else
							local gap = math.max(0, c0 - r.Across, r.Across - c1)
							if gap < req then
								return 0, "partroad:" .. r.Name
							end
						end
					end
				end
			end
		end
	end
	return need, nil
end

local function overlaps(b: Box, r: Rect, grow: number): boolean
	return b.X1 > r.X0 - grow and b.X0 < r.X1 + grow and b.Z1 > r.Z0 - grow and b.Z0 < r.Z1 + grow
end

local function boxPointDist(b: Box, x: number, z: number): number
	local dx = math.max(b.X0 - x, 0, x - b.X1)
	local dz = math.max(b.Z0 - z, 0, z - b.Z1)
	return math.sqrt(dx * dx + dz * dz)
end

-- WorldHygiene H3 on the cluster's part AABB (+ 0.5 slack): nil = clear. inWater: water overlap is allowed, but only
-- into SH.InWaterRects (the ring canal and the sea), never a channel, lagoon, harbour, slip or plot water.
local function zoneBoxCheck(zones: Zones, b: Box, inWater: boolean): string?
	local e = WorldConfig.Terrain.Edge
	if b.X1 >= e.Inner or b.X0 <= -e.Inner or b.Z0 <= -e.Inner or b.Z1 >= e.FarShoreZ then
		return "partzone:belt"
	end
	for _, c in ipairs(zones.Captures) do
		if boxPointDist(b, c.X, c.Z) < c.R + 0.5 then
			return "partzone:capture:" .. c.Name
		end
	end
	for _, a in ipairs(zones.Aprons) do
		if overlaps(b, a, 0.5) then
			return "partzone:" .. a.Name
		end
	end
	for _, p in ipairs(zones.Pads) do
		if overlaps(b, p, HY.PadClear + 0.5) then
			return "partzone:pad:" .. p.Name
		end
	end
	for _, p in ipairs(zones.PlotPads) do
		if overlaps(b, p, HY.PlotPadClear + 0.5) then
			return "partzone:" .. p.Name
		end
	end
	for _, c in ipairs(zones.ClearRects) do
		if overlaps(b, c, 0.5) then
			return "partzone:clear:" .. c.Name
		end
	end
	for _, w in ipairs(zones.Water) do
		if overlaps(b, w, HY.WaterClear + 0.5) then
			if not inWater or not hasPrefix(w.Name, SH.InWaterRects) then
				return "partzone:water:" .. w.Name
			end
		end
	end
	return nil
end

-- ── build context: yields, rocks, clusters ─────────────────────────────────────────────────────────────────────────

local function warnOnce(ctx: Ctx, msg: string)
	if #ctx.Warnings < 40 then
		table.insert(ctx.Warnings, msg)
	end
end

-- task.wait() at most every YieldEvery clusters, on the build thread itself (the sim's main-thread waits return at once)
local function maybeYield(ctx: Ctx)
	ctx.SinceYield += 1
	if BUD.YieldEvery > 0 and ctx.SinceYield >= BUD.YieldEvery then
		ctx.SinceYield = 0
		ctx.Busy += os.clock() - ctx.SegStart
		task.wait()
		ctx.SegStart = os.clock()
	end
end

local function rockRow(style: string): RockRow
	return TR.Rocks[style] or TR.Rocks.boulders
end

-- the keep-out test for one Terrain rock group (terrain collides: it stays out of the road corridor like a collidable part)
-- (skipRing: a bank rock between the ring box and the canal; the water + 6 rule is its boundary there)
local function rockBlocked(ctx: Ctx, pos: Vector3, style: string, skipRing: boolean?): string?
	local row = rockRow(style)
	if ctx.PrimsReserved + row.MaxPrims > math.min(BUD.TerrainPrims, TR.MaxPrims) then
		return "rockbudget"
	end
	return WorldDress.Blocked(ctx.Occ, pos.X, pos.Z, row.Outer, { RoadClear = RH.CollidableRoadGap, SkipRing = skipRing })
end

local function fillRock(ctx: Ctx, pos: Vector3, style: string, rng: Rng): number
	local row = rockRow(style)
	local kind = if style == "outcrop" then "outcrop" else "boulders"
	local ok, prims = pcall(WorldKits.Rock, pos, kind, rng, { Radius = row.Radius, Count = row.Count })
	if not ok then
		warnOnce(ctx, "WorldKits.Rock failed: " .. tostring(prims))
		return 0
	end
	local n = if type(prims) == "table" then #prims else 0
	ctx.Prims += n
	return n
end

local function localPos(frame: CFrame, x: number, z: number): Vector3
	return (frame * CFrame.new(x, 0, z)).Position
end

-- Builds the recipe's Part kits into a new UNPARENTED cluster (nil when it has no Part kits) and resolves its rock spots.
-- The caller moves / validates it, then keeps it (WorldKits.Finish) or destroys it.
local function compose(name: string, attrs: WorldKits.ClusterAttrs, frame: CFrame, recipe: Recipe): (Model?, number, { { Pos: Vector3, Style: string } })
	local model: Model? = nil
	local parts = 0
	if #recipe.Pieces > 0 then
		local m = WorldKits.NewCluster(name, attrs)
		for _, pc in ipairs(recipe.Pieces) do
			local cf = frame * CFrame.new(pc.X, 0, pc.Z) * CFrame.Angles(0, math.rad(pc.Yaw), 0)
			parts += WorldKits.Add(m, pc.Kit, cf, pc.Opts)
		end
		-- the travel dressing casts no shadows (contracts §2.2: 0 casters outside the POIs; phones)
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CastShadow = false
			end
		end
		model = m
	end
	local rocks: { { Pos: Vector3, Style: string } } = {}
	for _, r in ipairs(recipe.Rocks) do
		table.insert(rocks, { Pos = localPos(frame, r.X, r.Z), Style = r.Style })
	end
	return model, parts, rocks
end

-- a cluster built but not Finished (a keep-out hit, or Low's dropped half): WorldKits drops its pending overlays too
local function destroyModel(m: Model?)
	if m then
		local discard = (WorldKits :: any).Discard
		if type(discard) == "function" then
			discard(m)
		else
			m:Destroy()
		end
	end
end

-- move the parts so their XZ box is centred on (x, z): road-side kits pivot at their front edge (WorldKits), so a
-- composed cluster is re-centred on its spot before the road rule measures it
local function centreOn(parts: { BasePart }, x: number, z: number)
	local b = unionBox(parts)
	if b then
		translate(parts, Vector3.new(x - (b.X0 + b.X1) * 0.5, 0, z - (b.Z0 + b.Z1) * 0.5))
	end
end

-- keep a validated cluster: parent it (WorldKits.Finish), fill its rocks, record its disc
local function commit(ctx: Ctx, folder: Instance, built: Built, rng: Rng, discR: number, kind: string, sec: SectionSummary): boolean
	local parts = 0
	local model = built.Model
	if model then
		local info = WorldKits.Finish(model, folder)
		if not info.Ok then
			sec.Rejected["finish"] = (sec.Rejected["finish"] or 0) + 1
			warnOnce(ctx, string.format("%s: WorldKits.Finish refused %s (%s)", sec.Name, model.Name, tostring(info.Reason)))
			return false
		end
		parts = info.Parts
	end
	for _, r in ipairs(built.Rocks) do
		sec.TerrainPrims += fillRock(ctx, r.Pos, r.Style, rng)
	end
	sec.Clusters += 1
	sec.Parts += parts
	WorldDress.AddDisc(ctx.Occ, built.X, built.Z, discR, kind)
	maybeYield(ctx)
	return true
end

local function reject(sec: SectionSummary, reason: string)
	local key = string.match(reason, "^([^:]+:?[^:]*)") or reason
	sec.Rejected[key] = (sec.Rejected[key] or 0) + 1
end

-- ── recipes (contracts §2.3; local frame: -Z = the front, toward the road / junction / water) ───────────────────────

local function jitter(rng: Rng, a: number): number
	return rng:NextNumber(-a, a)
end

local function floraRecipe(rng: Rng, variant: number): Recipe
	-- 3 plants at >= 2 sizes (a tall one, a short one, a barrel cactus): 5 parts
	local tall, short = rng:NextNumber(1.05, 1.3), rng:NextNumber(0.7, 0.85)
	local second = if variant % 2 == 1 then "Saguaro" else "Joshua"
	return {
		Pieces = {
			{ Kit = "Joshua", X = -3.5 + jitter(rng, 0.8), Z = 0.5 + jitter(rng, 0.8), Yaw = rng:NextNumber(0, 360), Opts = { Scale = tall } },
			{ Kit = second, X = 3.5 + jitter(rng, 0.8), Z = 2.5 + jitter(rng, 0.8), Yaw = rng:NextNumber(0, 360), Opts = { Scale = short } },
			{ Kit = "BarrelCactus", X = jitter(rng, 1), Z = -3, Yaw = rng:NextNumber(0, 360), Opts = { Scale = rng:NextNumber(0.8, 1.15) } },
		},
		Rocks = {},
		Natural = true,
		InWater = false,
	}
end

local function wreckRecipe(rng: Rng, which: string): Recipe
	local pieces: { Piece }
	-- WorldKits' wrecks lie along their local X (parallel to the road at yaw 0), the body behind the pivot (z >= 0)
	if which == "car" then
		pieces = {
			{ Kit = "Wreck", X = 0, Z = 0, Yaw = jitter(rng, 14), Opts = { Variant = "car" } },
			{ Kit = "DrumGroup", X = 6.8, Z = 1.2, Yaw = jitter(rng, 30), Opts = { Count = 2 } },
		}
	elseif which == "truck" then
		pieces = {
			{ Kit = "Wreck", X = 0, Z = 0, Yaw = 180 + jitter(rng, 14), Opts = { Variant = "truck" } },
			{ Kit = "DrumGroup", X = -9.4, Z = -2, Yaw = jitter(rng, 30), Opts = { Count = 1 } },
		}
	else
		pieces = { { Kit = "SandbagNest", X = 0, Z = 0, Yaw = jitter(rng, 10) } }
	end
	return { Pieces = pieces, Rocks = {}, Natural = false, InWater = false }
end

local function markerRecipe(variant: string): Recipe
	return { Pieces = { { Kit = "RoadMarker", X = 0, Z = 0, Yaw = 0, Opts = { Variant = variant } } }, Rocks = {}, Natural = false, InWater = false }
end

local function rockRecipe(style: string): Recipe
	return { Pieces = {}, Rocks = { { Style = style, X = 0, Z = 0 } }, Natural = true, InWater = false }
end

local function deadwoodRecipe(rng: Rng): Recipe
	-- DeadTree + Stump + FallenLog: 3 elements of 3 sizes, 3 parts
	return {
		Pieces = {
			{ Kit = "DeadTree", X = 0, Z = 0, Yaw = rng:NextNumber(0, 360), Opts = { Scale = rng:NextNumber(0.95, 1.25) } },
			{ Kit = "Stump", X = 4 + jitter(rng, 1), Z = 3 + jitter(rng, 1), Yaw = rng:NextNumber(0, 360), Opts = { Scale = rng:NextNumber(0.8, 1.1) } },
			{ Kit = "Log", X = -4 + jitter(rng, 1), Z = 2 + jitter(rng, 1), Yaw = rng:NextNumber(0, 360), Opts = { Scale = rng:NextNumber(0.8, 1.1) } },
		},
		Rocks = {},
		Natural = true,
		InWater = false,
	}
end

local function shoreRecipe(rng: Rng, kind: string): Recipe
	if kind == "revetment" then
		return { Pieces = { { Kit = "Revetment", X = 0, Z = 0, Yaw = jitter(rng, 4) } }, Rocks = {}, Natural = false, InWater = false }
	elseif kind == "jetty_stub" then
		return { Pieces = { { Kit = "JettyStub", X = 0, Z = 0, Yaw = 0 } }, Rocks = {}, Natural = false, InWater = true }
	elseif kind == "barge_wreck" then
		return { Pieces = { { Kit = "BargeWreck", X = 0, Z = 0, Yaw = jitter(rng, 20) } }, Rocks = {}, Natural = false, InWater = true }
	elseif kind == "beached_boat" then
		return { Pieces = { { Kit = "BeachedHull", X = 0, Z = 0, Yaw = jitter(rng, 25) } }, Rocks = {}, Natural = false, InWater = true }
	elseif kind == "dune_grass" then
		return { Pieces = { { Kit = "DuneGrass", X = 0, Z = 0, Yaw = rng:NextNumber(0, 360) } }, Rocks = {}, Natural = true, InWater = false }
	elseif kind == "driftwood_rocks" then
		return {
			Pieces = { { Kit = "Driftwood", X = -2, Z = 0, Yaw = rng:NextNumber(0, 360) } },
			Rocks = { { Style = "shore", X = 6, Z = 7 } },
			Natural = true,
			InWater = false,
		}
	end
	-- reeds_rocks
	return {
		Pieces = { { Kit = "Reeds", X = -2, Z = 0, Yaw = rng:NextNumber(0, 360) } },
		Rocks = { { Style = "shore", X = 6, Z = 7 } },
		Natural = true,
		InWater = false,
	}
end

-- ── Rhythm (spec §4.1) ─────────────────────────────────────────────────────────────────────────────────────────────

local function nearJunction(zones: Zones, x: number, z: number, clear: number): boolean
	for _, j in ipairs(zones.Junctions) do
		if (x - j.X) ^ 2 + (z - j.Z) ^ 2 < clear * clear then
			return true
		end
	end
	-- (0, 0), where RoadX0 meets RoadZ0, is the Town's crossing (inside its footprint + 30 anyway)
	return x * x + z * z < clear * clear
end

local function recipeFor(kind: string, rng: Rng, counters: { [string]: number }): Recipe
	if kind == "wreck_or_nest" then
		local list = RH.WreckRecipes
		return wreckRecipe(rng, list[counters.wreck % #list + 1])
	elseif kind == "flora_group" then
		return floraRecipe(rng, counters.flora)
	elseif kind == "sign_or_marker" then
		local list = RH.MarkerVariants
		return markerRecipe(list[counters.sign % #list + 1])
	end
	return rockRecipe("outcrop")
end

local function bumpCounters(kind: string, counters: { [string]: number })
	if kind == "wreck_or_nest" then
		counters.wreck += 1
	elseif kind == "flora_group" then
		counters.flora += 1
	elseif kind == "sign_or_marker" then
		counters.sign += 1
	end
end

-- one road-side spot: compose, push out of the road corridor if needed (never past Offset max), validate
local function buildRoadside(ctx: Ctx, road: Road, t: number, side: number, off: number, kind: string, name: string, rng: Rng, counters: { [string]: number }): Built
	local recipe = recipeFor(kind, rng, counters)
	local dirX, dirZ = if road.AlongX then 0 else -side, if road.AlongX then -side else 0 -- toward the road
	local function xz(o: number): (number, number)
		if road.AlongX then
			return t, road.Across + side * o
		end
		return road.Across + side * o, t
	end
	local ax, az = xz(0)
	local x, z = xz(off)
	local attrs: WorldKits.ClusterAttrs = {
		Source = "rhythm",
		Kind = kind,
		Anchor = "road:" .. road.Name,
		AnchorX = ax,
		AnchorZ = az,
		Natural = if recipe.Natural and #recipe.Pieces > 0 then true else nil,
		Elements = if recipe.Natural and #recipe.Pieces > 0 then #recipe.Pieces else nil,
	}
	local model, _, rocks = compose(name, attrs, frameAt(x, z, facingYaw(dirX, dirZ)), recipe)
	local offset = off
	if model then
		local parts = partsOf(model)
		centreOn(parts, x, z)
		if #parts == 0 then
			destroyModel(model)
			return { Ok = false, Reason = "noparts", Model = nil, X = x, Z = z, Parts = 0, Rocks = {} }
		end
		local need, why = roadCheck(ctx.Zones, parts, road, side)
		if why then
			destroyModel(model)
			return { Ok = false, Reason = why, Model = nil, X = x, Z = z, Parts = 0, Rocks = {} }
		end
		if need > 0 then
			local push = need + 0.25
			if offset + push > RH.Offset[2] then
				destroyModel(model)
				return { Ok = false, Reason = "partroad:push", Model = nil, X = x, Z = z, Parts = 0, Rocks = {} }
			end
			offset += push
			local nx, nz = xz(offset)
			translate(parts, Vector3.new(nx - x, 0, nz - z))
			x, z = nx, nz
		end
		local b = unionBox(parts) :: Box
		local zr = zoneBoxCheck(ctx.Zones, b, false)
		if zr then
			destroyModel(model)
			return { Ok = false, Reason = zr, Model = nil, X = x, Z = z, Parts = 0, Rocks = {} }
		end
		return { Ok = true, Reason = nil, Model = model, X = x, Z = z, Parts = #parts, Rocks = rocks }
	end
	-- terrain-only (rock_outcrop): the rock's reach clears the road corridor and every zone; push out if needed
	local row = rockRow(recipe.Rocks[1].Style)
	local minOff = RH.CollidableRoadGap + row.Outer + 0.25
	if offset < minOff then
		if minOff > RH.Offset[2] then
			return { Ok = false, Reason = "rockroad", Model = nil, X = x, Z = z, Parts = 0, Rocks = {} }
		end
		offset = minOff
		x, z = xz(offset)
	end
	local pos = Vector3.new(x, GROUND_Y, z)
	local why = rockBlocked(ctx, pos, recipe.Rocks[1].Style)
	if why then
		return { Ok = false, Reason = "rock" .. why, Model = nil, X = x, Z = z, Parts = 0, Rocks = {} }
	end
	return { Ok = true, Reason = nil, Model = nil, X = x, Z = z, Parts = 0, Rocks = { { Pos = pos, Style = recipe.Rocks[1].Style } } }
end

local function buildRhythm(ctx: Ctx, folder: Instance, sec: SectionSummary)
	local zones = ctx.Zones
	local rng = WorldKits.Rng(WorldDressConfig.Seed + RH.Salt)
	local kindIdx = 0
	local counters: { [string]: number } = { wreck = 0, flora = 0, sign = 0 }
	local reservedParts = 0 -- parts of every accepted cluster, kept or not (identical in Full and Low)
	local cap = BUD.Rhythm
	local ring = zones.Ring
	for _, road in ipairs(zones.Roads) do
		-- roads run full length while WaterConfig is off (Min / Max = ±huge): clamp to the ring
		local lo = math.max(road.Min, if road.AlongX then ring.X0 else ring.Z0)
		local hi = math.min(road.Max, if road.AlongX then ring.X1 else ring.Z1)
		local t = lo + RH.EndInset
		local side = 1
		local accepted = 0
		while t < hi - RH.EndInset do
			local off = rng:NextNumber(RH.Offset[1], RH.Offset[2])
			local seed = rng:NextInteger(1, 2147483646) -- per spot, so every cluster looks the same in Full and Low
			local x = if road.AlongX then t else road.Across + side * off
			local z = if road.AlongX then road.Across + side * off else t
			local reason: string? = nil
			if nearJunction(zones, x, z, RH.JunctionClear) then
				reason = "junction"
			else
				reason = WorldDress.Blocked(ctx.Occ, x, z, RH.Radius, { RoadClear = RH.Offset[1] - RH.Radius })
			end
			if reason == nil then
				local kind = RH.Kinds[kindIdx % #RH.Kinds + 1]
				local kParts = (RH.KindParts :: { [string]: number })[kind] or 0
				if reservedParts + kParts > cap then
					reason = "budget"
				else
					local crng = WorldKits.Rng(seed)
					local name = string.format("%s_%02d_%s", road.Name, accepted + 1, kind)
					local built = buildRoadside(ctx, road, t, side, off, kind, name, crng, counters)
					if built.Ok then
						-- the pushed centre still passes the disc rule
						local why = WorldDress.Blocked(ctx.Occ, built.X, built.Z, RH.Radius, { RoadClear = RH.Offset[1] - RH.Radius })
						if why then
							destroyModel(built.Model)
							reason = why
						else
							accepted += 1
							kindIdx += 1
							bumpCounters(kind, counters)
							reservedParts += built.Parts
							if #built.Rocks > 0 then
								ctx.PrimsReserved += rockRow(built.Rocks[1].Style).MaxPrims
							end
							local pattern = RH.LowPattern
							local keep = ctx.Full or pattern[(accepted - 1) % #pattern + 1] == true
							if keep then
								commit(ctx, folder, built, crng, RH.Radius, "rhythm:" .. kind, sec)
							else
								destroyModel(built.Model)
							end
							side = -side
						end
					else
						reason = built.Reason or "build"
					end
				end
			end
			if reason then
				reject(sec, reason)
			end
			t += rng:NextNumber(RH.Spacing[1], RH.Spacing[2])
		end
	end
end

-- ── Junctions (spec §4.2) ──────────────────────────────────────────────────────────────────────────────────────────

local CORNERS = { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }

local function buildJunctions(ctx: Ctx, folder: Instance, sec: SectionSummary)
	local rng = WorldKits.Rng(WorldDressConfig.Seed + JN.Salt)
	for _, j in ipairs(JN.Points) do
		local seed = rng:NextInteger(1, 2147483646)
		local placed = false
		local lastReason = "corner"
		for _, c in ipairs(CORNERS) do
			local sx, sz = c[1], c[2]
			local cx, cz = j.X + JN.Corner * sx, j.Z + JN.Corner * sz
			local why = WorldDress.Blocked(ctx.Occ, cx, cz, JN.Radius, { RoadClear = RH.Offset[1] - RH.Radius })
			if why == nil then
				local crng = WorldKits.Rng(seed)
				local faceJ = math.deg(facingYaw(-sx, -sz))
				local signText = if JN.SignText then "◄ ► " else nil
				-- world-aligned frame at the corner: the post faces the junction, the jersey pair lines both shoulders,
				-- the sandbag arc and a Terrain boulder group sit behind them
				local recipe: Recipe = {
					Pieces = {
						{ Kit = "DirSign", X = -5 * sx, Z = -5 * sz, Yaw = faceJ, Opts = { Text = signText } },
						{ Kit = "Jersey", X = 1 * sx, Z = -8.4 * sz, Yaw = math.deg(facingYaw(0, -sz)) },
						{ Kit = "Jersey", X = -8.4 * sx, Z = 1 * sz, Yaw = math.deg(facingYaw(-sx, 0)) },
						{ Kit = "SandbagArc", X = 1.5 * sx, Z = 1.5 * sz, Yaw = faceJ + jitter(crng, 8) },
					},
					Rocks = { { Style = "boulders", X = 9 * sx, Z = 9 * sz } },
					Natural = false,
					InWater = false,
				}
				local name = string.format("Junction_%d_%d", j.X, j.Z)
				local attrs: WorldKits.ClusterAttrs = {
					Source = "junction",
					Kind = "junction",
					Anchor = string.format("junction:%d,%d", j.X, j.Z),
					AnchorX = j.X,
					AnchorZ = j.Z,
				}
				local model, _, rocks = compose(name, attrs, CFrame.new(cx, GROUND_Y, cz), recipe)
				local parts = if model then partsOf(model) else {}
				local _, rw = roadCheck(ctx.Zones, parts, nil, 0)
				local b = unionBox(parts)
				local zr = if b then zoneBoxCheck(ctx.Zones, b, false) else "noparts"
				local rr: string? = nil
				for _, r in ipairs(rocks) do
					rr = rr or rockBlocked(ctx, r.Pos, r.Style)
				end
				if rw or zr or #parts == 0 then
					destroyModel(model)
					lastReason = rw or zr or "noparts"
				else
					if rr then
						rocks = {} -- the kit stands without its boulder group rather than put terrain in a keep-out
						warnOnce(ctx, string.format("Junction (%d, %d): boulders skipped (%s)", j.X, j.Z, rr))
					else
						ctx.PrimsReserved += rockRow("boulders").MaxPrims
					end
					local built: Built = { Ok = true, Reason = nil, Model = model, X = cx, Z = cz, Parts = #parts, Rocks = rocks }
					placed = commit(ctx, folder, built, crng, JN.Radius, "junction:junction", sec)
					if placed then
						break
					end
					lastReason = "finish"
				end
			else
				lastReason = why
			end
		end
		if not placed then
			reject(sec, lastReason)
			warnOnce(ctx, string.format("Junction (%d, %d): no free corner (%s)", j.X, j.Z, lastReason))
		end
	end
end

-- ── Shore (spec §4.3) ──────────────────────────────────────────────────────────────────────────────────────────────

type ShoreRun = { Side: string, AlongX: boolean, Across: number, From: number, To: number, Spacing: number, Dir: number, Edge: number, Kinds: { WorldDressConfig.KindRow }, Source: string }

-- penetration of a box past the water edge along the water direction (+ = into the water)
local function penetration(run: ShoreRun, b: Box): number
	if run.AlongX then
		return if run.Dir > 0 then b.Z1 - run.Edge else run.Edge - b.Z0
	end
	return if run.Dir > 0 then b.X1 - run.Edge else run.Edge - b.X0
end

local function buildShore(ctx: Ctx, folder: Instance, sec: SectionSummary)
	local rng = WorldKits.Rng(WorldDressConfig.Seed + SH.Salt)
	local runs: { ShoreRun } = {}
	for _, l in ipairs(SH.Lines) do
		local dir = if l.Across < 0 then -1 else 1
		table.insert(runs, {
			Side = l.Side,
			AlongX = l.AlongX,
			Across = l.Across,
			From = l.From,
			To = l.To,
			Spacing = SH.Spacing,
			Dir = dir,
			Edge = l.Across + dir * SH.Inset,
			Kinds = SH.Kinds,
			Source = "shore",
		})
	end
	local bay = SH.Bay
	table.insert(runs, { Side = "Bay", AlongX = true, Across = bay.Z, From = bay.From, To = bay.To, Spacing = bay.Spacing, Dir = 1, Edge = bay.EdgeZ, Kinds = bay.Kinds, Source = "bay" })

	local parts = 0
	local rot: { [string]: number } = { shore = 0, bay = 0 } -- kinds rotate over the accepted spots of all canal lines
	for _, run in ipairs(runs) do
		local nn = 0
		local t = run.From
		while t <= run.To + 1e-6 do
			local seed = rng:NextInteger(1, 2147483646)
			local x = if run.AlongX then t else run.Across
			local z = if run.AlongX then run.Across else t
			local reason: string? = nil
			for _, l in ipairs(SH.Landings) do
				if (x - l.X) ^ 2 + (z - l.Z) ^ 2 < SH.LandingClear * SH.LandingClear then
					reason = "landing"
				end
			end
			reason = reason or WorldDress.Blocked(ctx.Occ, x, z, SH.Radius)
			if reason == nil then
				local row = run.Kinds[rot[run.Source] % #run.Kinds + 1]
				if parts + row.Parts > SH.MaxParts then
					reason = "budget"
				else
					local crng = WorldKits.Rng(seed)
					local recipe = shoreRecipe(crng, row.Kind)
					local wx = if run.AlongX then x else run.Edge
					local wz = if run.AlongX then run.Edge else z
					local dx, dz = if run.AlongX then 0 else run.Dir, if run.AlongX then run.Dir else 0 -- toward the water
					local hasParts = #recipe.Pieces > 0
					local attrs: WorldKits.ClusterAttrs = {
						Source = run.Source,
						Kind = row.Kind,
						Anchor = "water:" .. run.Side,
						AnchorX = wx,
						AnchorZ = wz,
						Natural = if recipe.Natural then true else nil,
						Elements = if recipe.Natural then #recipe.Pieces + #recipe.Rocks else nil,
						InWater = if recipe.InWater then true else nil,
					}
					local name = string.format("Shore_%s_%02d_%s", run.Side, nn + 1, row.Kind)
					local model, _, rocks = compose(name, attrs, frameAt(x, z, facingYaw(dx, dz)), recipe)
					local ps = if model then partsOf(model) else {}
					if hasParts and #ps == 0 then
						reason = "noparts"
					elseif hasParts then
						local move = 0
						if recipe.InWater then
							-- step into the water: the far end reaches exactly InWaterMax past the edge
							local b0 = unionBox(ps) :: Box
							move = SH.InWaterMax - penetration(run, b0) - 0.25
						elseif (SH.ToWater :: { [string]: boolean })[row.Kind] then
							-- step to the water's edge: the nearest part stays LandEdgeGap from the water (H3: > 6)
							local b0 = unionBox(ps) :: Box
							move = -SH.LandEdgeGap - penetration(run, b0)
						end
						if move ~= 0 then
							translate(ps, Vector3.new(dx * move, 0, dz * move))
							for _, r in ipairs(rocks) do
								r.Pos += Vector3.new(dx * move, 0, dz * move)
							end
						end
						local b = unionBox(ps) :: Box
						local _, rw = roadCheck(ctx.Zones, ps, nil, 0)
						reason = rw or zoneBoxCheck(ctx.Zones, b, recipe.InWater)
						if reason == nil and recipe.InWater then
							-- the stepped kit (not just the bank disc) clears every non-water keep-out
							local cx, cz = (b.X0 + b.X1) * 0.5, (b.Z0 + b.Z1) * 0.5
							local r = math.sqrt((b.X1 - b.X0) ^ 2 + (b.Z1 - b.Z0) ^ 2) * 0.5
							local why = WorldDress.Blocked(ctx.Occ, cx, cz, r, { AllowWater = true, SkipRing = true, RoadClear = RH.CollidableRoadGap })
							reason = if why then "inwater:" .. why else nil
						end
					end
					if reason == nil then
						local rr: string? = nil
						for _, r in ipairs(rocks) do
							rr = rr or rockBlocked(ctx, r.Pos, r.Style, true)
						end
						if rr then
							rocks = {} -- the feature stands without its rocks rather than put terrain in a keep-out
							warnOnce(ctx, string.format("%s: rocks skipped (%s)", name, rr))
						else
							for _, r in ipairs(rocks) do
								ctx.PrimsReserved += rockRow(r.Style).MaxPrims
							end
						end
						if model and recipe.Natural then
							model:SetAttribute("WE_Elements", #recipe.Pieces + #rocks)
						end
						local built: Built = { Ok = true, Reason = nil, Model = model, X = x, Z = z, Parts = #ps, Rocks = rocks }
						if commit(ctx, folder, built, crng, SH.Radius, run.Source .. ":" .. row.Kind, sec) then
							parts += #ps
							rot[run.Source] += 1
							nn += 1
						else
							reason = "finish"
						end
					else
						destroyModel(model)
					end
				end
			end
			if reason then
				reject(sec, reason)
			end
			t += run.Spacing
		end
	end
end

-- ── Emptiness field (contracts §3.5, the metric of world_v2_model.py emptiness()) ─────────────────────────────────

local function fieldIdx(f: Field, i: number, j: number): number
	return (j - 1) * f.NX + i
end

-- lower the field to the distance from (px, pz) for every cell within r
local function stamp(f: Field, px: number, pz: number, r: number)
	local cell = f.Cell
	local jlo = math.max(1, math.ceil((pz - r - f.Z0) / cell) + 1)
	local jhi = math.min(f.NZ, math.floor((pz + r - f.Z0) / cell) + 1)
	local r2 = r * r
	local d2 = f.D2
	for j = jlo, jhi do
		local dz = f.Z0 + (j - 1) * cell - pz
		local rem = r2 - dz * dz
		if rem >= 0 then
			local w = math.sqrt(rem)
			local ilo = math.max(1, math.ceil((px - w - f.X0) / cell) + 1)
			local ihi = math.min(f.NX, math.floor((px + w - f.X0) / cell) + 1)
			local dz2 = dz * dz
			local base = (j - 1) * f.NX
			for i = ilo, ihi do
				local dx = f.X0 + (i - 1) * cell - px
				local dd = dx * dx + dz2
				local idx = base + i
				if dd < d2[idx] then
					d2[idx] = dd
				end
			end
		end
	end
end

-- lattice samples of a footprint; boundary samples reach the whole field, interior ones only 40 (the nearest sample to
-- any point more than 40 away is always on the boundary of the lattice set)
local function stampSamples(f: Field, xs: { number }, zs: { number }, inside: (number, number) -> boolean)
	local set: { [number]: boolean } = {}
	local nxs, nzs = #xs, #zs
	for a = 1, nxs do
		for b = 1, nzs do
			if inside(xs[a], zs[b]) then
				set[(a - 1) * nzs + b] = true
			end
		end
	end
	for a = 1, nxs do
		for b = 1, nzs do
			if set[(a - 1) * nzs + b] then
				local edge = a == 1 or a == nxs or b == 1 or b == nzs
					or not set[(a - 2) * nzs + b] or not set[a * nzs + b] or not set[(a - 1) * nzs + b - 1] or not set[(a - 1) * nzs + b + 1]
				stamp(f, xs[a], zs[b], if edge then f.Cap else 40.01)
			end
		end
	end
end

local function range(from: number, to: number, step: number): { number }
	local out: { number } = {}
	local v = from
	while v <= to do
		table.insert(out, v)
		v += step
	end
	return out
end

local function newField(zones: Zones, occ: Occupancy, cell: number): Field
	local land = SC.Land
	local cap = SC.FieldMax
	local nx = math.floor((land.X1 - land.X0 - cell * 0.5) / cell) + 1
	local nz = math.floor((land.Z1 - land.Z0 - cell * 0.5) / cell) + 1
	local f: Field = {
		Cell = cell,
		X0 = land.X0 + cell * 0.5,
		Z0 = land.Z0 + cell * 0.5,
		NX = nx,
		NZ = nz,
		D2 = table.create(nx * nz, cap * cap),
		Valid = table.create(nx * nz, true),
		Cap = cap,
	}
	local d2, valid = f.D2, f.Valid
	-- the ring edge
	for j = 1, nz do
		local z = f.Z0 + (j - 1) * cell
		for i = 1, nx do
			local x = f.X0 + (i - 1) * cell
			local e = math.min(x - land.X0, land.X1 - x, z - land.Z0, land.Z1 - z)
			local idx = fieldIdx(f, i, j)
			if e * e < d2[idx] then
				d2[idx] = e * e
			end
		end
	end
	-- plot pads are not land (and are sampled below)
	for _, p in ipairs(zones.PlotPads) do
		for j = 1, nz do
			local z = f.Z0 + (j - 1) * cell
			if z >= p.Z0 and z <= p.Z1 then
				for i = 1, nx do
					local x = f.X0 + (i - 1) * cell
					if x >= p.X0 and x <= p.X1 then
						valid[fieldIdx(f, i, j)] = false
					end
				end
			end
		end
	end
	-- water (+ bank 6): wet cells are not land; land cells measure to the bank line
	local margin = K.WaterMargin
	for _, w in ipairs(zones.Water) do
		local reach = cap + margin
		local jlo = math.max(1, math.ceil((w.Z0 - reach - f.Z0) / cell) + 1)
		local jhi = math.min(nz, math.floor((w.Z1 + reach - f.Z0) / cell) + 1)
		local ilo = math.max(1, math.ceil((w.X0 - reach - f.X0) / cell) + 1)
		local ihi = math.min(nx, math.floor((w.X1 + reach - f.X0) / cell) + 1)
		for j = jlo, jhi do
			local z = f.Z0 + (j - 1) * cell
			local dz = math.max(w.Z0 - z, 0, z - w.Z1)
			for i = ilo, ihi do
				local x = f.X0 + (i - 1) * cell
				local dx = math.max(w.X0 - x, 0, x - w.X1)
				local d = math.sqrt(dx * dx + dz * dz)
				local idx = fieldIdx(f, i, j)
				if d <= margin then
					valid[idx] = false
					d2[idx] = 0
				else
					local dd = (d - margin) * (d - margin)
					if dd < d2[idx] then
						d2[idx] = dd
					end
				end
			end
		end
	end
	-- every POI footprint (reserved, built or not), sampled every 40
	for _, p in ipairs(zones.POIs) do
		local rect = p.Rect
		local circ = p.Circle
		if rect then
			stampSamples(f, range(rect.X0 + 20, rect.X1, 40), range(rect.Z0 + 20, rect.Z1, 40), function(_x: number, _z: number): boolean
				return true
			end)
		elseif circ then
			stampSamples(f, range(circ.X - circ.R, circ.X + circ.R, 40), range(circ.Z - circ.R, circ.Z + circ.R, 40), function(x: number, z: number): boolean
				return (x - circ.X) ^ 2 + (z - circ.Z) ^ 2 <= circ.R * circ.R
			end)
		end
	end
	-- the plot pads, sampled every 40
	for _, p in ipairs(zones.PlotPads) do
		stampSamples(f, range(p.X0, p.X1 + 0.1, 40), range(p.Z0, p.Z1 + 0.1, 40), function(_x: number, _z: number): boolean
			return true
		end)
	end
	-- the land garage pads and every placed cluster (POI clusters and the travel dressing so far, terrain-only included)
	for _, p in ipairs(zones.Pads) do
		stamp(f, (p.X0 + p.X1) * 0.5, (p.Z0 + p.Z1) * 0.5, cap)
	end
	for _, d in ipairs(occ.Discs) do
		stamp(f, d.X, d.Z, cap)
	end
	return f
end

-- share of land cells more than 100 from anything; the largest empty circle (diameter) and its centre
local function fieldStats(f: Field): (number, number, number, number)
	local valid, far, best, bi = 0, 0, -1, 0
	local lim = 100 * 100
	for idx = 1, f.NX * f.NZ do
		if f.Valid[idx] then
			valid += 1
			local dd = f.D2[idx]
			if dd > lim then
				far += 1
			end
			if dd > best then
				best, bi = dd, idx
			end
		end
	end
	local i = (bi - 1) % f.NX + 1
	local j = (bi - i) // f.NX + 1
	return far / math.max(1, valid), 2 * math.sqrt(math.max(0, best)), f.X0 + (i - 1) * f.Cell, f.Z0 + (j - 1) * f.Cell
end

local function cellXZ(f: Field, idx: number): (number, number)
	local i = (idx - 1) % f.NX + 1
	local j = (idx - i) // f.NX + 1
	return f.X0 + (i - 1) * f.Cell, f.Z0 + (j - 1) * f.Cell
end

export type Emptiness = { Far100: number, Largest: number, X: number, Z: number, Cell: number }

-- The emptiness metric over the occupancy (contracts §3.5): dry land inside the ring, "anything" = every disc in occ,
-- the garage pads, every POI footprint and plot pad (sampled every 40), the ring edge and the water (+ 6).
function WorldDress.Emptiness(occ: Occupancy, cell: number?): Emptiness
	local f = newField(occ.Zones, occ, cell or SC.Grid)
	local far, largest, x, z = fieldStats(f)
	return { Far100 = far, Largest = largest, X = x, Z = z, Cell = f.Cell }
end

-- ── Scatter (spec §4.4) ────────────────────────────────────────────────────────────────────────────────────────────

local function scatterRecipe(kind: string, rng: Rng, counter: number): Recipe
	if kind == "flora_group" then
		return floraRecipe(rng, counter)
	elseif kind == "dead_tree_stumps" then
		return deadwoodRecipe(rng)
	elseif kind == "boulder_field" then
		return rockRecipe("boulder_field")
	end
	return rockRecipe("outcrop")
end

local function buildScatter(ctx: Ctx, folder: Instance, sec: SectionSummary): Field
	local rng = WorldKits.Rng(WorldDressConfig.Seed + SC.Salt)
	local f = newField(ctx.Zones, ctx.Occ, SC.Grid)
	local rmin = math.max(SC.EmptyRadius, SC.TargetLargestEmpty * 0.5)
	local rmin2 = rmin * rmin
	local failed: { [number]: boolean } = {}
	local placed, parts, kindIdx, flora = 0, 0, 0, 0
	local n = f.NX * f.NZ

	local function spacingOk(x: number, z: number): boolean
		local s2 = SC.MinSpacing * SC.MinSpacing
		for _, d in ipairs(ctx.Occ.Discs) do
			if (x - d.X) ^ 2 + (z - d.Z) ^ 2 < s2 then
				return false
			end
		end
		return true
	end

	-- one spot: the kind in rotation (a Part kind over the cap becomes a boulder field), built and validated
	local function tryAt(x: number, z: number): (boolean, string?)
		local why = WorldDress.Blocked(ctx.Occ, x, z, SC.Radius, { RoadClear = SC.RoadClear - SC.Radius })
		if why then
			return false, why
		end
		if not spacingOk(x, z) then
			return false, "spacing"
		end
		local row = SC.Kinds[kindIdx % #SC.Kinds + 1]
		local kind = row.Kind
		if parts + row.Parts > SC.MaxParts then
			kind = "boulder_field"
		end
		local seed = rng:NextInteger(1, 2147483646)
		local crng = WorldKits.Rng(seed)
		local recipe = scatterRecipe(kind, crng, flora)
		local elements = #recipe.Pieces
		local attrs: WorldKits.ClusterAttrs = {
			Source = "scatter",
			Kind = kind,
			Anchor = "natural",
			AnchorX = x,
			AnchorZ = z,
			Natural = true,
			Elements = elements,
		}
		local model, _, rocks = compose(string.format("Scatter_%02d_%s", placed + 1, kind), attrs, frameAt(x, z, crng:NextNumber(0, math.pi * 2)), recipe)
		local ps = if model then partsOf(model) else {}
		if model then
			centreOn(ps, x, z)
			if #ps < SC.MinElements then
				destroyModel(model)
				return false, "noparts"
			end
			local _, rw = roadCheck(ctx.Zones, ps, nil, 0)
			local zr = rw or zoneBoxCheck(ctx.Zones, unionBox(ps) :: Box, false)
			if zr then
				destroyModel(model)
				return false, zr
			end
		end
		for _, r in ipairs(rocks) do
			local rr = rockBlocked(ctx, r.Pos, r.Style)
			if rr then
				destroyModel(model)
				return false, "rock" .. rr
			end
		end
		for _, r in ipairs(rocks) do
			ctx.PrimsReserved += rockRow(r.Style).MaxPrims
		end
		local built: Built = { Ok = true, Reason = nil, Model = model, X = x, Z = z, Parts = #ps, Rocks = rocks }
		if not commit(ctx, folder, built, crng, SC.Radius, "scatter:" .. kind, sec) then
			return false, "finish"
		end
		placed += 1
		parts += #ps
		kindIdx += 1
		if kind == "flora_group" then
			flora += 1
		end
		stamp(f, x, z, f.Cap)
		return true, nil
	end

	for _ = 1, SC.MaxIterations do
		if placed >= SC.MaxClusters then
			break
		end
		local alive: { number } = {}
		for idx = 1, n do
			if f.Valid[idx] and not failed[idx] and f.D2[idx] > rmin2 then
				table.insert(alive, idx)
			end
		end
		if #alive == 0 then
			break
		end
		-- the largest empty circles, greedy, each at least Suppress x r from the ones before it
		local circles: { EmptyCircle } = {}
		while #circles < SC.CirclesPerRound and #alive > 0 do
			local best, bk = -1, 0
			for k, idx in ipairs(alive) do
				if f.D2[idx] > best then
					best, bk = f.D2[idx], k
				end
			end
			local idx = alive[bk]
			local cx, cz = cellXZ(f, idx)
			local r = math.sqrt(best)
			table.insert(circles, { X = cx, Z = cz, R = r, Idx = idx })
			local sup2 = (SC.Suppress * r) ^ 2
			local keep: { number } = {}
			for _, other in ipairs(alive) do
				local ox, oz = cellXZ(f, other)
				if (ox - cx) ^ 2 + (oz - cz) ^ 2 >= sup2 then
					table.insert(keep, other)
				end
			end
			alive = keep
		end
		for _, c in ipairs(circles) do
			if placed >= SC.MaxClusters then
				break
			end
			if f.D2[c.Idx] > rmin2 then -- still empty after this round's earlier placements
				local ok = false
				local lastWhy: string? = nil
				for try = 0, SC.Tries - 1 do
					local x, z = c.X, c.Z
					if try > 0 then
						local scale = 1 + try / 10
						x = c.X + rng:NextNumber(-SC.Jitter, SC.Jitter) * scale
						z = c.Z + rng:NextNumber(-SC.Jitter, SC.Jitter) * scale
					end
					local good, why = tryAt(x, z)
					if good then
						ok = true
						break
					end
					lastWhy = why
				end
				if not ok then
					reject(sec, lastWhy or "circle")
					-- this circle cannot be filled: its middle leaves the candidate list (still counted in the metric)
					local fr2 = (SC.FailClear * c.R) ^ 2
					for idx = 1, n do
						if f.D2[idx] > rmin2 then
							local x, z = cellXZ(f, idx)
							if (x - c.X) ^ 2 + (z - c.Z) ^ 2 <= fr2 then
								failed[idx] = true
							end
						end
					end
				end
			end
		end
	end
	return f
end

-- ── Build ─────────────────────────────────────────────────────────────────────────────────────────────────────────

local function freshFolder(parent: Instance, name: string): Folder
	local old = parent:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function WorldDress.Build(dressing: Instance, quality: string, occ: Occupancy?): Summary
	local q = WorldDress.Quality(quality)
	local o = occ or WorldDress.NewOccupancy()
	local ctx: Ctx = {
		Quality = q,
		Full = q == "Full",
		Occ = o,
		Zones = o.Zones,
		Warnings = {},
		Prims = 0,
		PrimsReserved = 0,
		Busy = 0,
		SegStart = os.clock(),
		SinceYield = 0,
	}
	local sections: { SectionSummary } = {
		{ Name = "Rhythm", Clusters = 0, Parts = 0, PartsCap = BUD.Rhythm, TerrainPrims = 0, Rejected = {} },
		{ Name = "Junctions", Clusters = 0, Parts = 0, PartsCap = BUD.Junctions, TerrainPrims = 0, Rejected = {} },
		{ Name = "Shore", Clusters = 0, Parts = 0, PartsCap = BUD.Shore, TerrainPrims = 0, Rejected = {} },
		{ Name = "Scatter", Clusters = 0, Parts = 0, PartsCap = BUD.Scatter, TerrainPrims = 0, Rejected = {} },
	}
	local enabled = WorldDressConfig.Enabled ~= false
	local builders: { [string]: (Ctx, Instance, SectionSummary) -> () } = {
		Rhythm = buildRhythm,
		Junctions = buildJunctions,
		Shore = buildShore,
	}
	local cfgOn: { [string]: boolean } = {
		Rhythm = enabled and RH.Enabled ~= false,
		Junctions = enabled and JN.Enabled ~= false,
		Shore = enabled and SH.Enabled ~= false and (ctx.Full or (WorldDressConfig.Quality.Low.ShoreEvery or 1) > 0),
		Scatter = enabled and SC.Enabled ~= false and (ctx.Full or WorldDressConfig.Quality.Low.Scatter == true),
	}
	local largest, far100 = 0, 0
	for _, sec in ipairs(sections) do
		local folder = freshFolder(dressing, (FOLDERS :: any)[sec.Name] or sec.Name)
		if cfgOn[sec.Name] then
			local ok, err = pcall(function()
				if sec.Name == "Scatter" then
					local f = buildScatter(ctx, folder, sec)
					local far, lg = fieldStats(f)
					far100, largest = far, lg
				else
					builders[sec.Name](ctx, folder, sec)
				end
			end)
			if not ok then
				warnOnce(ctx, sec.Name .. " failed: " .. tostring(err))
			end
		end
		if sec.Parts > sec.PartsCap then
			warnOnce(ctx, string.format("%s: %d parts > cap %d", sec.Name, sec.Parts, sec.PartsCap))
		end
	end
	ctx.Busy += os.clock() - ctx.SegStart
	local total, clusters, prims = 0, 0, 0
	for _, sec in ipairs(sections) do
		total += sec.Parts
		clusters += sec.Clusters
		prims += sec.TerrainPrims
	end
	local sum: Summary = {
		Quality = q,
		Sections = sections,
		Parts = total,
		Clusters = clusters,
		TerrainPrims = prims,
		LargestEmpty = largest,
		Far100 = far100,
		Seconds = ctx.Busy,
		Warnings = ctx.Warnings,
	}
	local s1, s2, s3, s4 = sections[1], sections[2], sections[3], sections[4]
	print(
		string.format(
			"[WAR EMPIRE] WorldDress: %s rhythm %d (%d) junctions %d (%d) shore %d (%d) scatter %d (%d); terrain %d prims; largest empty %.0f; %.2f s",
			q,
			s1.Clusters,
			s1.Parts,
			s2.Clusters,
			s2.Parts,
			s3.Clusters,
			s3.Parts,
			s4.Clusters,
			s4.Parts,
			prims,
			largest,
			ctx.Busy
		)
	)
	if #ctx.Warnings > 0 then
		warn(string.format("[WorldDress] %d warnings; first: %s", #ctx.Warnings, ctx.Warnings[1]))
	end
	return sum
end

return WorldDress
