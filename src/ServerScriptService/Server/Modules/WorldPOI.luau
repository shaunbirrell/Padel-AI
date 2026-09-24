--!strict
--[[
	WAR EMPIRE World v2 Phase 2 (W3) — WorldPOI: the named places between the bases (gap/world_v2_spec.md §3.1–§3.2,
	roadmap §2.4 WORLD-B builder 1). Each ENABLED POI in WorldConfig.POIs becomes WarEmpireSetup.WorldDressing.POI_<Id>,
	a folder of cluster Models (each <= 64 studs across, H10) built from WorldKits. W3 step 1 enables Crossroads Town
	only; the other 17 stay in WorldConfig with Enabled = false (their footprints stay reserved: WorldDress keeps out)
	until the owner signs off the Town's style and density.

	CONTRACT (scratchpad/w3/contracts.md §2 and §4): owner = B1.

	PUBLIC API (server only):
	  WorldPOI.Build(dressing, quality, occ?) -> Summary
	      dressing = WarEmpireSetup.WorldDressing (MapDressing created it). For each enabled POI: destroys an old
	      POI_<Id>, builds its clusters in config order (Quality "Low" = Tier-1 clusters only, <= 60 % of the Full
	      parts), asserts every cluster with WorldDress.Blocked(occ, x, z, r, { AllowPOI = Id, … }) (a blocked cluster
	      is skipped and warned, never placed), records each built cluster with WorldDress.AddDisc(occ, …, "poi:<Id>"),
	      and stays within the POI's Budget / Lights / Signs caps. Idempotent. Never yields (mesh overlays are deferred
	      by WorldKits).
	  WorldPOI.Enabled() -> { WorldConfig.POI }        POIs with Enabled == true, in config order
	  WorldPOI.FolderName(id) -> string                "POI_" .. id

	THE TOWN (WorldConfig.Town, data only): every cluster row is one Model at (X, Z) turned by Yaw.
	  * Block clusters: disc (AABB half-diagonal round the AABB centre) edge >= Town.RoadClear (30) from both road
	    centre lines, outside the CentralPlaza capture clear circle, the Empire Bank guard ring, the Pool_Town pad
	    + 16 and the TownSquare event anchor (all through WorldDress.Blocked).
	  * Street clusters (Street = true: checkpoints, lamps, the board) stand beside or across a road: they skip the
	    disc road test and pass a per-part test instead (every collidable part >= 13, every visible part taller than
	    0.3 >= 9 from every road centre line; CheckpointArm and road markings exempt, as in WorldHygiene H2).
	  * Flat markings (PaveTile only: top <= 0.75, no collision) may lie over an event anchor (the supply crate lands
	    on the paving); they are not added to the occupancy.
	  * Every part stays inside the POI footprint. Terrain rubble / scorch (WorldKits.Rock) passes Blocked too.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage.Shared.Configs
local WorldConfig = require(Configs.WorldConfig)
local WorldDressConfig = require(Configs.WorldDressConfig)
local WorldDress = require(script.Parent.WorldDress)
local WorldKits = require(script.Parent.WorldKits)

export type POISummary = {
	Id: string,
	Enabled: boolean,
	Built: boolean,
	Parts: number,
	Budget: number, -- Full cap (Low cap = floor(Budget-used-in-Full x POIShare))
	Lights: number,
	LightsCap: number,
	Signs: number,
	SignsCap: number,
	Clusters: number,
	Skipped: number, -- clusters dropped by WorldDress.Blocked or the caps (each one warned)
	TerrainPrims: number,
}
export type Summary = {
	Quality: string,
	POIs: { POISummary },
	Parts: number,
	Lights: number,
	Signs: number,
	Clusters: number,
	TerrainPrims: number,
	Seconds: number,
	Warnings: { string },
}

type Road = WorldDress.Road
type Occupancy = WorldDress.Occupancy
type TownCluster = WorldConfig.TownCluster
type Ctx = {
	Poi: WorldConfig.POI,
	Folder: Folder,
	Quality: string,
	Occ: Occupancy,
	Row: POISummary,
	Warnings: { string },
}

local WorldPOI = {}

local GROUND_Y = 0.5
local H = WorldConfig.Hygiene

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

local function kitParts(kit: WorldConfig.KitPlace): (number, number, number)
	local s = WorldKits.Specs[kit.Kit]
	if s == nil or s.Step ~= 1 then
		return 0, 0, 0
	end
	-- the exact count, measured from the kit builder (cached): CrateStack / DrumGroup Count is crates / drums (1 part
	-- each), SandbagLine / CompoundWall Length is studs, Wreck "car" is 4 parts
	local fp = WorldKits.Footprint(kit.Kit, { Variant = kit.Variant, Count = kit.Count, Length = kit.Length, Scale = kit.Scale })
	return if fp then fp.Parts else s.PartsMax, s.Lights, s.Signs
end

local function planned(c: TownCluster): (number, number, number)
	local p, l, g = 0, 0, 0
	for _, k in ipairs(c.Kits) do
		local a, b, d = kitParts(k)
		p, l, g = p + a, l + b, g + d
	end
	return p, l, g
end

local function skip(ctx: Ctx, what: string, why: string)
	ctx.Row.Skipped += 1
	local msg = string.format("[WorldPOI] %s: %s skipped (%s)", ctx.Poi.Id, what, why)
	table.insert(ctx.Warnings, msg)
	warn(msg)
end

-- ── Crossroads Town ───────────────────────────────────────────────────────────────────────────────────────────────
local function buildTown(ctx: Ctx)
	local T = WorldConfig.Town
	local poi, occ, row = ctx.Poi, ctx.Occ, ctx.Row
	local low = ctx.Quality == "Low"
	local roads = occ.Zones.Roads
	local fullPlanned = 0
	for _, c in ipairs(T.Clusters) do
		fullPlanned += (planned(c))
	end
	local partsCap = if low then math.min(poi.Budget, math.floor(fullPlanned * WorldDressConfig.Quality.Low.POIShare + 1e-9)) else poi.Budget
	local lightsCap, signsCap = row.LightsCap, row.SignsCap
	local anchor = "poi:" .. poi.Id

	for _, c in ipairs(T.Clusters) do
		if low and c.Tier ~= 1 then
			continue
		end
		local pParts, pLights = planned(c)
		if row.Parts + pParts > partsCap or row.Lights + pLights > lightsCap then
			skip(ctx, c.Id, string.format("caps: parts %d + %d > %d or lights %d + %d > %d", row.Parts, pParts, partsCap, row.Lights, pLights, lightsCap))
			continue
		end
		local model = WorldKits.NewCluster(c.Id, { Source = "poi", Kind = c.Role, Anchor = anchor, AnchorX = c.X, AnchorZ = c.Z, Tier = c.Tier })
		local frame = CFrame.new(c.X, GROUND_Y, c.Z) * CFrame.Angles(0, math.rad(c.Yaw), 0)
		local signsHere = 0
		for _, k in ipairs(c.Kits) do
			local text = k.Text
			if text == nil and k.Kit == "PoiBoard" then
				text = T.BoardText
			end
			if text ~= nil and row.Signs + signsHere + 1 > signsCap then
				text = nil -- the POI's sign cap: the board stays, unpainted
			end
			if text ~= nil then
				signsHere += 1
			end
			local kcf = frame * CFrame.new(k.X, 0, k.Z) * CFrame.Angles(0, math.rad(k.Yaw or 0), 0)
			WorldKits.Add(model, k.Kit, kcf, { Variant = k.Variant, Count = k.Count, Length = k.Length, Scale = k.Scale, Color = k.Color, Text = text })
		end
		local m = measure(model, roads, poi.Rect)
		local cx, cz = (m.X0 + m.X1) * 0.5, (m.Z0 + m.Z1) * 0.5
		local r = 0.5 * math.sqrt((m.X1 - m.X0) ^ 2 + (m.Z1 - m.Z0) ^ 2)
		local why: string? = nil
		if m.Parts == 0 then
			why = "no parts"
		elseif c.Street then
			why = WorldDress.Blocked(occ, cx, cz, r, { AllowPOI = poi.Id, RoadClear = 0, RoadR = 0 })
		else
			why = WorldDress.Blocked(occ, cx, cz, r, { AllowPOI = poi.Id, RoadClear = T.RoadClear })
			if m.Marking and why ~= nil and string.sub(why, 1, 13) == "anchor:Event_" then
				why = nil -- flat paving under an event anchor: the crate lands on it
			end
		end
		why = why or m.RoadWhy or m.Outside
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
		if not m.Marking then
			WorldDress.AddDisc(occ, cx, cz, r, anchor)
		end
		row.Parts += info.Parts
		row.Lights += info.Lights
		row.Signs += info.Signs
		row.Clusters += 1
	end

	-- Terrain rubble and scorch (0 parts; each group's disc passes the same block rule)
	local rng = WorldKits.Rng(T.Seed)
	for i, rk in ipairs(T.Rocks) do
		if low and rk.Tier ~= 1 then
			continue
		end
		local maxCount = ((WorldConfig.Kits.Rock :: any)[rk.Kind] or { Count = { 0, 4 } }).Count[2] :: number
		if row.TerrainPrims + maxCount > T.MaxTerrainPrims then
			skip(ctx, "rock " .. i, "terrain prim cap")
			continue
		end
		local why = WorldDress.Blocked(occ, rk.X, rk.Z, rk.Radius, { AllowPOI = poi.Id, RoadClear = T.RoadClear })
		if why ~= nil then
			skip(ctx, "rock " .. i, why)
			continue
		end
		local prims = WorldKits.Rock(Vector3.new(rk.X, GROUND_Y, rk.Z), rk.Kind, rng, { Radius = rk.Radius })
		WorldDress.AddDisc(occ, rk.X, rk.Z, rk.Radius, anchor)
		row.TerrainPrims += #prims
	end
end

local BUILDERS: { [string]: (Ctx) -> () } = {
	town = buildTown,
}

function WorldPOI.Build(dressing: Instance, quality: string, occ: Occupancy?): Summary
	local t0 = os.clock()
	local q = WorldDress.Quality(quality)
	local o: Occupancy = occ or WorldDress.NewOccupancy()
	local summary: Summary = { Quality = q, POIs = {}, Parts = 0, Lights = 0, Signs = 0, Clusters = 0, TerrainPrims = 0, Seconds = 0, Warnings = {} }
	for _, p in ipairs(WorldConfig.POIs) do
		local row: POISummary = {
			Id = p.Id,
			Enabled = p.Enabled == true,
			Built = false,
			Parts = 0,
			Budget = p.Budget,
			Lights = 0,
			LightsCap = p.Lights or 0,
			Signs = 0,
			SignsCap = p.Signs or 0,
			Clusters = 0,
			Skipped = 0,
			TerrainPrims = 0,
		}
		table.insert(summary.POIs, row)
		if row.Enabled then
			local name = WorldPOI.FolderName(p.Id)
			local old = dressing:FindFirstChild(name)
			if old then
				old:Destroy()
			end
			local builder = BUILDERS[p.Kind]
			if builder == nil then
				local msg = string.format("[WorldPOI] %s: no builder for kind %q yet", p.Id, p.Kind)
				table.insert(summary.Warnings, msg)
				warn(msg)
			else
				local folder = Instance.new("Folder")
				folder.Name = name
				folder.Parent = dressing
				local ctx: Ctx = { Poi = p, Folder = folder, Quality = q, Occ = o, Row = row, Warnings = summary.Warnings }
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
		end
	end
	return summary
end

return WorldPOI
