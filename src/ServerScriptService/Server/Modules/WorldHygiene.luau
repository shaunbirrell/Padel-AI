--!strict
--[[
	WAR EMPIRE World v2 Phase 1 — WorldHygiene: rules H1–H10 for the world outside the bases (gap/world_v2_spec.md §5,
	roadmap §1.3 / §1.5 #3). The fix for "dead, out of place props". Thresholds: WorldConfig.Hygiene / WorldConfig.Lights.

	  H1  Anchored: every man-made dressing unit lies <= 60 studs from an anchor (POI footprint, road centre line,
	      water edge, plot edge, capture zone); natural units may stand alone only as groups of >= 3.
	      W1: REPORT ONLY (Hygiene.OrphanMode = "Report": listed for W3, never deleted). "Enforce" destroys them.
	  H2  Road corridor: nothing collidable with its top above 0.75 within 12 of a road centre line; nothing visible
	      taller than 0.3 within 8 (markings, RoadEnds, CheckpointArm and WE_AllowOnRoad exempt).  → destroy kit
	  H3  Clear zones: capture zones (R x 1.414 + 25), front-gate aprons, land garage pads + 16, plot pads + 4,
	      water + 6 (WE_AllowInWater exempt), rig pier corridors, and the Terrain belt / beyond (hidden in rock).
	                                                                                                 → destroy kit
	  H4  Cover is solid: visible man-made cover (crates, drums, sandbags, walls, wrecks, …) whose top is >= 1.5 above
	      the floor collides (CanCollide + CanQuery). MeshParts collide through their host part.            → set
	  H5  No Neon (→ SmoothPlastic), no Beam, no world-code BillboardGui (service labels under
	      Hygiene.BillboardAllowAncestors are F's).                                                  → set / destroy
	  H6  No static Humanoid outside the bases.                                                  → destroy model
	  H7  No part over 2,040 studs on any axis.                                                    → check only
	  H8  <= 24 lights outside the bases; Brightness <= 0.8, Range <= 18, Shadows off, tag WE_NightLight.
	                                                                                  → clamp, tag, drop extras
	  H9  CastShadow only on parts >= 8 studs; <= 300 casters outside the bases.                          → set
	  H10 Streaming structure: no dressing Model wider than 64 studs.                              → check only

	Enforce acts ONLY inside the dressing folders (Hygiene.DressingFolders: WorldDressing, DesertFlora, and W3's
	WorldPOI / WorldKits). Everything else outside the bases (Map, Territories, spawns, MapSetup blocks) is reported,
	never touched: those are the hook step's deletions.

	PUBLIC API (server only; not hooked yet — the post-F hook step calls Enforce at the end of MapDressing.Dress and
	DesertFlora.Dress, after Waterways.CullDressing, and may log Report(root) at the end of MapSetup.Run):
	  WorldHygiene.Report(root: Instance, opts?: Opts) -> Report
	      Read-only census + every violation of H1–H10 under root (WarEmpireSetup, or one dressing folder), bases
	      excluded. Report.Orphans lists the H1 units for W3.
	  WorldHygiene.Enforce(root: Instance, opts?: Opts) -> Report
	      Applies H2–H6, H8, H9 (and H1 when OrphanMode = "Enforce") inside the dressing folders under / at root,
	      then returns Report(root) with Report.Actions = what it changed. Idempotent: a second call changes nothing
	      (all Actions 0).
	  WorldHygiene.Check(root: Instance, opts?: Opts) -> { Violation }   (= Report(root).Violations; spec name)
	  WorldHygiene.Rules                                                  (the per-instance predicates, pure)
	Opts = { WorldRoot: Instance? (for the world light count; default: root's parent when root is a dressing folder),
	         Pads: { BasePart }? (land garage pads; default: parts tagged WE_VehicleSpawn but not WE_NavalSpawn),
	         OrphanMode: string?, Log: boolean? (one summary line; default true for Enforce) }
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Configs")
local WorldConfig = require(Configs:WaitForChild("WorldConfig"))
local WaterConfig = require(Configs:WaitForChild("WaterConfig"))
local TerritoryConfig = require(Configs:WaitForChild("TerritoryConfig"))
local BaseConfig = require(Configs:WaitForChild("BaseConfig"))
local BaseLayout = require(script.Parent:WaitForChild("BaseLayout"))
local Waterways = require(script.Parent:WaitForChild("Waterways"))
local WorldAtmosphere = require(script.Parent:WaitForChild("WorldAtmosphere"))

export type Violation = { Rule: string, Path: string, Detail: string, X: number, Z: number }
export type Orphan = { Path: string, Kind: string, X: number, Z: number, Parts: number, Nearest: number }
export type Report = {
	Mode: string,
	Root: string,
	Parts: number, -- BaseParts under root outside the bases
	DressingParts: number,
	Counts: { [string]: number }, -- violations per rule
	Actions: { [string]: number }, -- Enforce: parts destroyed (H1/H2/H3/H6) or properties set (H4/H5/H8/H9)
	Violations: { Violation },
	Orphans: { Orphan },
	Census: { [string]: number },
	Legacy: { [string]: number }, -- parts in the MapSetup blocks the hook deletes
	ByTop: { [string]: number }, -- parts per child of root
}
export type Opts = { WorldRoot: Instance?, Pads: { BasePart }?, OrphanMode: string?, Log: boolean? }

type Box = { X0: number, X1: number, Y0: number, Y1: number, Z0: number, Z1: number }
type Rect = { Name: string?, X0: number, X1: number, Z0: number, Z1: number }
type Road = { Name: string, AlongX: boolean, Across: number, Min: number, Max: number }
type Circle = { Name: string, X: number, Z: number, R: number }
type Ctx = {
	Roads: { Road },
	Water: { Rect },
	PlotPads: { Rect },
	Captures: { Circle },
	Territories: { Circle },
	Aprons: { Rect },
	Pads: { Rect },
	ClearRects: { Rect },
	POIs: { WorldConfig.POI },
}

local WorldHygiene = {}

local H = WorldConfig.Hygiene
local GROUND_TOP_Y = 0.5
local RULES = { "H1", "H2", "H3", "H4", "H5", "H6", "H7", "H8", "H9", "H10" }

-- ── small helpers ────────────────────────────────────────────────────────────

local function toSet(list: { string }): { [string]: boolean }
	local s: { [string]: boolean } = {}
	for _, v in ipairs(list) do
		s[v] = true
	end
	return s
end

local DRESSING = toSet(H.DressingFolders)
local BASES = toSet(H.BaseFolders)
local V2 = toSet(H.WorldV2Folders)
local LEGACY = toSet(H.LegacyFolders)
local NATURAL_FOLDERS = toSet(H.NaturalFolders)
local ROAD_EXEMPT_ANC = toSet(H.RoadExemptAncestors)
local ROAD_EXEMPT_NAMES = toSet(H.RoadExemptNames)
local BB_ALLOW = toSet(H.BillboardAllowAncestors)
local CAPTURE_SKIP = toSet(H.CaptureSkip)

local function hasPrefix(name: string, list: { string }): boolean
	for _, p in ipairs(list) do
		if string.sub(name, 1, #p) == p then
			return true
		end
	end
	return false
end

local function hasKeyword(name: string, list: { string }): boolean
	for _, k in ipairs(list) do
		if string.find(name, k, 1, true) then
			return true
		end
	end
	return false
end

local function worldBox(p: BasePart): Box
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = p.CFrame:GetComponents()
	local s = p.Size
	local hx = (math.abs(r00) * s.X + math.abs(r01) * s.Y + math.abs(r02) * s.Z) * 0.5
	local hy = (math.abs(r10) * s.X + math.abs(r11) * s.Y + math.abs(r12) * s.Z) * 0.5
	local hz = (math.abs(r20) * s.X + math.abs(r21) * s.Y + math.abs(r22) * s.Z) * 0.5
	return { X0 = x - hx, X1 = x + hx, Y0 = y - hy, Y1 = y + hy, Z0 = z - hz, Z1 = z + hz }
end

local function overlapsRect(b: Box, r: Rect, grow: number): boolean
	return b.X1 > r.X0 - grow and b.X0 < r.X1 + grow and b.Z1 > r.Z0 - grow and b.Z0 < r.Z1 + grow
end

-- XZ distance from a box to a point (0 inside)
local function boxDist(b: Box, x: number, z: number): number
	local dx = math.max(b.X0 - x, 0, x - b.X1)
	local dz = math.max(b.Z0 - z, 0, z - b.Z1)
	return math.sqrt(dx * dx + dz * dz)
end

-- XZ distance from a point to a rect (0 inside)
local function rectDist(r: Rect, x: number, z: number): number
	local dx = math.max(r.X0 - x, 0, x - r.X1)
	local dz = math.max(r.Z0 - z, 0, z - r.Z1)
	return math.sqrt(dx * dx + dz * dz)
end

local function attrUp(inst: Instance, attr: string, stop: Instance?): boolean
	local cur: Instance? = inst
	while cur and cur ~= stop do
		if cur:GetAttribute(attr) == true then
			return true
		end
		cur = cur.Parent
	end
	return false
end

local function underNames(inst: Instance, names: { [string]: boolean }, stop: Instance?): boolean
	local cur = inst.Parent
	while cur and cur ~= stop do
		if names[cur.Name] then
			return true
		end
		cur = cur.Parent
	end
	return false
end

-- ── context (zones and anchors), rebuilt per call ─────────────────────────────

local function roadLines(): { Road }
	local out: { Road } = {}
	for name, ends in pairs(WaterConfig.RoadEnds) do
		local axis, num = string.match(name, "^Road([XZ])(%-?[%d%.]+)$")
		local across = if num then tonumber(num) else nil
		if axis and across then
			table.insert(out, {
				Name = name,
				AlongX = axis == "Z",
				Across = across,
				Min = if WaterConfig.Enabled then ends.Min else -math.huge,
				Max = if WaterConfig.Enabled then ends.Max else math.huge,
			})
		end
	end
	table.sort(out, function(a: Road, b: Road): boolean
		return a.Name < b.Name
	end)
	return out
end

local function landPads(opts: Opts?): { Rect }
	local out: { Rect } = {}
	local list: { BasePart } = {}
	if opts and opts.Pads then
		list = opts.Pads
	else
		for _, inst in ipairs(CollectionService:GetTagged("WE_VehicleSpawn")) do
			if inst:IsA("BasePart") and not CollectionService:HasTag(inst, "WE_NavalSpawn") then
				table.insert(list, inst)
			end
		end
	end
	for _, p in ipairs(list) do
		local b = worldBox(p)
		table.insert(out, { Name = p.Name, X0 = b.X0 - H.PadClear, X1 = b.X1 + H.PadClear, Z0 = b.Z0 - H.PadClear, Z1 = b.Z1 + H.PadClear })
	end
	return out
end

local function buildContext(opts: Opts?): Ctx
	local ctx: Ctx = {
		Roads = roadLines(),
		Water = {},
		PlotPads = {},
		Captures = {},
		Territories = {},
		Aprons = {},
		Pads = landPads(opts),
		ClearRects = H.ClearRects,
		POIs = WorldConfig.POIs,
	}
	for _, r in ipairs(Waterways.AllRects()) do
		table.insert(ctx.Water, { Name = r.Name, X0 = r.X0, X1 = r.X1, Z0 = r.Z0, Z1 = r.Z1 })
	end
	local half = (BaseConfig.PlotSize :: Vector3).X * 0.5
	for plotId, pos in ipairs(BaseConfig.PlotPositions :: { Vector3 }) do
		table.insert(ctx.PlotPads, { Name = "Plot" .. plotId, X0 = pos.X - half, X1 = pos.X + half, Z0 = pos.Z - half, Z1 = pos.Z + half })
		local a = H.GateApron
		local xs, zs = {}, {}
		for _, c in ipairs({ { a.X0, a.Z0 }, { a.X1, a.Z0 }, { a.X0, a.Z1 }, { a.X1, a.Z1 } }) do
			local w = BaseLayout.PlotPoint(pos, c[1], c[2])
			table.insert(xs, w.X)
			table.insert(zs, w.Z)
		end
		table.insert(ctx.Aprons, {
			Name = "Apron_P" .. plotId,
			X0 = math.min(table.unpack(xs)),
			X1 = math.max(table.unpack(xs)),
			Z0 = math.min(table.unpack(zs)),
			Z1 = math.max(table.unpack(zs)),
		})
	end
	for id, t in pairs(TerritoryConfig.Territories :: { [string]: any }) do
		local pos: Vector3 = t.Position
		local r: number = t.Radius
		table.insert(ctx.Territories, { Name = id, X = pos.X, Z = pos.Z, R = r })
		if not CAPTURE_SKIP[id] then
			table.insert(ctx.Captures, { Name = id, X = pos.X, Z = pos.Z, R = r * H.CaptureClearScale + H.CaptureClearExtra })
		end
	end
	table.sort(ctx.Captures, function(a: Circle, b: Circle): boolean
		return a.Name < b.Name
	end)
	return ctx
end

-- smallest across-gap from the box to the centre line of a road whose extent it overlaps (math.huge: none)
local function roadGap(ctx: Ctx, b: Box): number
	local best = math.huge
	for _, r in ipairs(ctx.Roads) do
		local a0, a1, c0, c1 = b.X0, b.X1, b.Z0, b.Z1
		if not r.AlongX then
			a0, a1, c0, c1 = b.Z0, b.Z1, b.X0, b.X1
		end
		if a1 >= r.Min and a0 <= r.Max then
			local gap = math.max(0, c0 - r.Across, r.Across - c1)
			if gap < best then
				best = gap
			end
		end
	end
	return best
end

-- XZ distance from a point to the nearest road centre segment
local function roadDist(ctx: Ctx, x: number, z: number): number
	local best = math.huge
	for _, r in ipairs(ctx.Roads) do
		local along, across = if r.AlongX then x else z, if r.AlongX then z else x
		local t = math.clamp(along, r.Min, r.Max)
		local d = math.sqrt((along - t) ^ 2 + (across - r.Across) ^ 2)
		if d < best then
			best = d
		end
	end
	return best
end

local function beyondBelt(b: Box): boolean
	local e = WorldConfig.Terrain.Edge
	return b.X0 >= e.Inner or b.X1 <= -e.Inner or b.Z1 <= -e.Inner or b.Z0 >= e.FarShoreZ
end

-- ── rules (pure predicates) ───────────────────────────────────────────────────

local Rules = {}

function Rules.IsNatural(part: Instance, stop: Instance?): boolean
	if hasPrefix(part.Name, H.NaturalPrefixes) then
		return true
	end
	local cur = part.Parent
	while cur and cur ~= stop do
		if NATURAL_FOLDERS[cur.Name] or hasPrefix(cur.Name, H.NaturalPrefixes) then
			return true
		end
		cur = cur.Parent
	end
	return false
end

local function isMarking(name: string): boolean
	return hasPrefix(name, H.RoadMarkingPrefixes)
end

function Rules.RoadExempt(part: Instance, stop: Instance?): boolean
	return ROAD_EXEMPT_NAMES[part.Name] == true or attrUp(part, "WE_AllowOnRoad", stop) or underNames(part, ROAD_EXEMPT_ANC, stop)
end

-- H2: nil or the reason
function Rules.H2(ctx: Ctx, part: BasePart, b: Box): string?
	if b.Y1 <= H.RoadMinTop then
		return nil
	end
	local gap = roadGap(ctx, b)
	if gap <= H.RoadCorridor and part.CanCollide then
		return string.format("collidable %.1f from a road line, top %.1f", gap, b.Y1)
	end
	if gap <= H.RoadLane and b.Y1 > GROUND_TOP_Y + H.RoadLaneMaxHeight and part.Transparency < 0.99 and not isMarking(part.Name) then
		return string.format("visible in the lane (%.1f), top %.1f", gap, b.Y1)
	end
	return nil
end

-- H3: nil or the zone name. Water hits honour WE_AllowInWater (checked by the caller).
function Rules.H3(ctx: Ctx, b: Box): (string?, boolean)
	if beyondBelt(b) then
		return "belt", false
	end
	for _, c in ipairs(ctx.Captures) do
		if boxDist(b, c.X, c.Z) < c.R then
			return "capture:" .. c.Name, false
		end
	end
	for _, r in ipairs(ctx.Aprons) do
		if overlapsRect(b, r, 0) then
			return r.Name or "apron", false
		end
	end
	for _, r in ipairs(ctx.Pads) do
		if overlapsRect(b, r, 0) then
			return "pad:" .. (r.Name or "?"), false
		end
	end
	for _, r in ipairs(ctx.PlotPads) do
		if overlapsRect(b, r, H.PlotPadClear) then
			return r.Name or "plot", false
		end
	end
	for _, r in ipairs(ctx.ClearRects) do
		if overlapsRect(b, r, 0) then
			return r.Name or "clear", false
		end
	end
	for _, r in ipairs(ctx.Water) do
		if overlapsRect(b, r, H.WaterClear) then
			return "water:" .. (r.Name or "?"), true
		end
	end
	return nil, false
end

-- H4: a visible man-made cover part that should collide
function Rules.H4Candidate(part: BasePart, b: Box, stop: Instance?): boolean
	if part:IsA("MeshPart") or part.Transparency >= 0.9 then
		return false
	end
	if b.Y1 - GROUND_TOP_Y < H.SolidMinHeight then
		return false
	end
	local name = part.Name
	if hasKeyword(name, H.SoftKeywords) or not hasKeyword(name, H.SolidKeywords) then
		return false
	end
	return not Rules.IsNatural(part, stop)
end

-- H5: "Neon" / "Beam" / "BillboardGui" / nil
function Rules.H5(inst: Instance, stop: Instance?): string?
	if inst:IsA("BasePart") then
		return if inst.Material == Enum.Material.Neon then "Neon" else nil
	elseif inst:IsA("Beam") then
		return "Beam"
	elseif inst:IsA("BillboardGui") then
		return if underNames(inst, BB_ALLOW, stop) then nil else "BillboardGui"
	end
	return nil
end

function Rules.H6(inst: Instance): boolean
	return inst:IsA("Humanoid")
end

function Rules.H7(part: BasePart): boolean
	local s = part.Size
	return math.max(s.X, s.Y, s.Z) > H.MaxPartSize
end

-- H8: nil or what is out of policy on one light
function Rules.H8(light: Light): string?
	local L = WorldConfig.Lights
	local bad: { string } = {}
	if light.Brightness > L.MaxBrightness + 1e-6 then
		table.insert(bad, string.format("Brightness %.2f", light.Brightness))
	end
	local range = (light :: any).Range
	if type(range) == "number" and range > L.MaxRange + 1e-6 then
		table.insert(bad, string.format("Range %.0f", range))
	end
	if light.Shadows ~= L.Shadows then
		table.insert(bad, "Shadows")
	end
	if not CollectionService:HasTag(light, WorldConfig.Atmosphere.NightLightTag) then
		table.insert(bad, "untagged")
	end
	return if #bad > 0 then table.concat(bad, ", ") else nil
end

function Rules.H9(part: BasePart): boolean
	local s = part.Size
	return part.CastShadow and math.max(s.X, s.Y, s.Z) < H.ShadowMinSize
end

WorldHygiene.Rules = Rules

-- ── walking the world ─────────────────────────────────────────────────────────

-- the children of root to inspect (bases excluded) and whether root itself is a dressing folder
local function scopes(root: Instance): ({ Instance }, boolean)
	if DRESSING[root.Name] then
		return { root }, true
	end
	local out: { Instance } = {}
	for _, ch in ipairs(root:GetChildren()) do
		if not BASES[ch.Name] then
			table.insert(out, ch)
		end
	end
	return out, false
end

local function pathOf(inst: Instance, root: Instance): string
	local names: { string } = {}
	local cur: Instance? = inst
	while cur and cur ~= root do
		table.insert(names, 1, cur.Name)
		cur = cur.Parent
	end
	return table.concat(names, ".")
end

local function centreOf(b: Box): (number, number)
	return (b.X0 + b.X1) * 0.5, (b.Z0 + b.Z1) * 0.5
end

local function newReport(mode: string, root: Instance): Report
	local rep: Report = {
		Mode = mode,
		Root = root:GetFullName(),
		Parts = 0,
		DressingParts = 0,
		Counts = {},
		Actions = {},
		Violations = {},
		Orphans = {},
		Census = {
			Neon = 0,
			Beams = 0,
			Billboards = 0,
			BillboardsWorldCode = 0,
			Humanoids = 0,
			Lights = 0,
			LightsDressing = 0,
			SurfaceGuis = 0,
			ShadowCasters = 0,
			Oversize = 0,
			InvisibleCollidable = 0,
		},
		Legacy = {},
		ByTop = {},
	}
	for _, r in ipairs(RULES) do
		rep.Counts[r] = 0
		rep.Actions[r] = 0
	end
	return rep
end

local function addViolation(rep: Report, rule: string, path: string, detail: string, x: number, z: number)
	rep.Counts[rule] += 1
	table.insert(rep.Violations, { Rule = rule, Path = path, Detail = detail, X = x, Z = z })
end

-- ── H1 units and orphans ──────────────────────────────────────────────────────

type Unit = { Key: string, Inst: Instance?, Parts: { BasePart }, Box: Box, Natural: boolean }

-- dressing parts → units: the kit Folder / Model directly under a section, else touching loose parts of a section
local function unitsOf(folder: Instance, boxes: { [BasePart]: Box }): { Unit }
	local units: { Unit } = {}
	local byInst: { [Instance]: Unit } = {}
	local loose: { [Instance]: { BasePart } } = {}
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") and boxes[d] then
			-- chain: folder > section > kit > ...
			local chain: { Instance } = {}
			local cur: Instance? = d
			while cur and cur ~= folder do
				table.insert(chain, 1, cur)
				cur = cur.Parent
			end
			local section = chain[1]
			local kit = chain[2]
			local key: Instance? = nil
			if section == d then
				key = d -- a loose part directly under the dressing folder
			elseif kit and kit ~= d and (kit:IsA("Folder") or kit:IsA("Model") or kit:IsA("BasePart")) then
				key = kit
			elseif section:IsA("Model") then
				key = section
			end
			if key then
				local u: Unit? = byInst[key]
				if not u then
					local nu: Unit = { Key = pathOf(key, folder.Parent or folder), Inst = key, Parts = {}, Box = boxes[d], Natural = false }
					byInst[key] = nu
					table.insert(units, nu)
					u = nu
				end
				table.insert((u :: Unit).Parts, d)
			else
				local list = loose[section]
				if not list then
					list = {}
					loose[section] = list
				end
				table.insert(list, d)
			end
		end
	end
	-- loose parts of a section: union parts whose boxes come within 4 studs
	for section, list in pairs(loose) do
		local parent: { number } = {}
		for i = 1, #list do
			parent[i] = i
		end
		local function find(i: number): number
			while parent[i] ~= i do
				parent[i] = parent[parent[i]]
				i = parent[i]
			end
			return i
		end
		for i = 1, #list do
			local a = boxes[list[i]]
			for j = i + 1, #list do
				local b = boxes[list[j]]
				if a.X1 + 4 >= b.X0 and b.X1 + 4 >= a.X0 and a.Z1 + 4 >= b.Z0 and b.Z1 + 4 >= a.Z0 then
					local ri, rj = find(i), find(j)
					if ri ~= rj then
						parent[ri] = rj
					end
				end
			end
		end
		local groups: { [number]: Unit } = {}
		local base = pathOf(section, folder.Parent or folder)
		for i, p in ipairs(list) do
			local r = find(i)
			local u: Unit? = groups[r]
			if not u then
				local nu: Unit = { Key = base .. "#" .. list[r].Name, Inst = nil, Parts = {}, Box = boxes[p], Natural = false }
				groups[r] = nu
				table.insert(units, nu)
				u = nu
			end
			table.insert((u :: Unit).Parts, p)
		end
	end
	for _, u in ipairs(units) do
		local b: Box = { X0 = math.huge, X1 = -math.huge, Y0 = math.huge, Y1 = -math.huge, Z0 = math.huge, Z1 = -math.huge }
		local natural = true
		for _, p in ipairs(u.Parts) do
			local pb = boxes[p]
			b.X0, b.X1 = math.min(b.X0, pb.X0), math.max(b.X1, pb.X1)
			b.Y0, b.Y1 = math.min(b.Y0, pb.Y0), math.max(b.Y1, pb.Y1)
			b.Z0, b.Z1 = math.min(b.Z0, pb.Z0), math.max(b.Z1, pb.Z1)
			if p.Transparency < 0.99 and not Rules.IsNatural(p, folder) then
				natural = false
			end
		end
		u.Box = b
		u.Natural = natural
	end
	table.sort(units, function(a: Unit, b: Unit): boolean
		return a.Key < b.Key
	end)
	return units
end

-- distance from a unit centre to its nearest anchor
local function anchorDist(ctx: Ctx, b: Box): number
	local x, z = centreOf(b)
	local best = roadDist(ctx, x, z)
	for _, p in ipairs(ctx.POIs) do
		local d
		if p.Rect then
			d = rectDist(p.Rect, x, z)
		elseif p.Circle then
			d = math.max(0, math.sqrt((x - p.Circle.X) ^ 2 + (z - p.Circle.Z) ^ 2) - p.Circle.R)
		else
			d = math.huge
		end
		best = math.min(best, d)
	end
	for _, r in ipairs(ctx.Water) do
		best = math.min(best, rectDist(r, x, z))
	end
	for _, r in ipairs(ctx.PlotPads) do
		best = math.min(best, rectDist(r, x, z))
	end
	for _, c in ipairs(ctx.Territories) do
		best = math.min(best, math.max(0, math.sqrt((x - c.X) ^ 2 + (z - c.Z) ^ 2) - c.R))
	end
	return best
end

local function findOrphans(ctx: Ctx, folder: Instance, boxes: { [BasePart]: Box }): { { Unit: Unit, Nearest: number } }
	local units = unitsOf(folder, boxes)
	local out: { { Unit: Unit, Nearest: number } } = {}
	local naturals: { Unit } = {}
	local dist: { [Unit]: number } = {}
	for _, u in ipairs(units) do
		dist[u] = anchorDist(ctx, u.Box)
		if u.Natural then
			table.insert(naturals, u)
		end
	end
	-- natural groups: units whose centres are within NaturalLink of each other
	local groupSize: { [Unit]: number } = {}
	do
		local parent: { [Unit]: Unit } = {}
		for _, u in ipairs(naturals) do
			parent[u] = u
		end
		local function find(u: Unit): Unit
			while parent[u] ~= u do
				u = parent[u]
			end
			return u
		end
		for i = 1, #naturals do
			local ax, az = centreOf(naturals[i].Box)
			for j = i + 1, #naturals do
				local bx, bz = centreOf(naturals[j].Box)
				if (ax - bx) ^ 2 + (az - bz) ^ 2 <= H.NaturalLink ^ 2 then
					local ri, rj = find(naturals[i]), find(naturals[j])
					if ri ~= rj then
						parent[ri] = rj
					end
				end
			end
		end
		local counts: { [Unit]: number } = {}
		for _, u in ipairs(naturals) do
			local r = find(u)
			counts[r] = (counts[r] or 0) + 1
		end
		for _, u in ipairs(naturals) do
			groupSize[u] = counts[find(u)]
		end
	end
	for _, u in ipairs(units) do
		local anchored = dist[u] <= H.AnchorMax
		if u.Natural then
			anchored = anchored or (groupSize[u] or 1) >= H.MinNatural
		end
		if not anchored then
			table.insert(out, { Unit = u, Nearest = dist[u] })
		end
	end
	return out
end

-- ── Report ────────────────────────────────────────────────────────────────────

function WorldHygiene.Report(root: Instance, opts: Opts?): Report
	local rep = newReport("Report", root)
	local ctx = buildContext(opts)
	local list, rootIsDressing = scopes(root)
	local lights: { Light } = {}
	for _, top in ipairs(list) do
		local isDressing = rootIsDressing or DRESSING[top.Name] == true
		local isV2 = V2[top.Name] == true
		local roadExemptTop = top.Name == "Map" or top.Name == "CoastalWater" or isV2
		local all = top:GetDescendants()
		table.insert(all, 1, top)
		local boxes: { [BasePart]: Box } = {}
		local topParts = 0
		for _, d in ipairs(all) do
			if d:IsA("BasePart") then
				local b = worldBox(d)
				boxes[d] = b
				topParts += 1
				local x, z = centreOf(b)
				local path = pathOf(d, root)
				if d.Material == Enum.Material.Neon then
					rep.Census.Neon += 1
					addViolation(rep, "H5", path, "Neon", x, z)
				end
				if Rules.H7(d) then
					rep.Census.Oversize += 1
					addViolation(rep, "H7", path, string.format("size %s", tostring(d.Size)), x, z)
				end
				if d.CastShadow then
					rep.Census.ShadowCasters += 1
					if Rules.H9(d) then
						addViolation(rep, "H9", path, "small shadow caster", x, z)
					end
				end
				if d.CanCollide and d.Transparency >= 0.95 and not isV2 then
					rep.Census.InvisibleCollidable += 1
				end
				if not roadExemptTop and not Rules.RoadExempt(d, root) then
					local why = Rules.H2(ctx, d, b)
					if why then
						addViolation(rep, "H2", path, why, x, z)
					end
				end
				if isDressing then
					local zone, wet = Rules.H3(ctx, b)
					if zone and not (wet and attrUp(d, "WE_AllowInWater", root)) then
						addViolation(rep, "H3", path, zone, x, z)
					end
					if Rules.H4Candidate(d, b, root) and not (d.CanCollide and d.CanQuery) then
						addViolation(rep, "H4", path, "walk-through cover", x, z)
					end
				end
			elseif d:IsA("BillboardGui") then
				rep.Census.Billboards += 1
				if Rules.H5(d, root) then
					rep.Census.BillboardsWorldCode += 1
					addViolation(rep, "H5", pathOf(d, root), "BillboardGui", 0, 0)
				end
			elseif d:IsA("Beam") then
				rep.Census.Beams += 1
				addViolation(rep, "H5", pathOf(d, root), "Beam", 0, 0)
			elseif d:IsA("Humanoid") then
				rep.Census.Humanoids += 1
				addViolation(rep, "H6", pathOf(d, root), "static Humanoid", 0, 0)
			elseif d:IsA("Light") then
				rep.Census.Lights += 1
				if isDressing then
					rep.Census.LightsDressing += 1
				end
				table.insert(lights, d)
				local why = Rules.H8(d)
				if why then
					addViolation(rep, "H8", pathOf(d, root), why, 0, 0)
				end
			elseif d:IsA("SurfaceGui") then
				rep.Census.SurfaceGuis += 1
			end
		end
		rep.Parts += topParts
		rep.ByTop[top.Name] = (rep.ByTop[top.Name] or 0) + topParts
		if LEGACY[top.Name] then
			rep.Legacy[top.Name] = topParts
		end
		if isDressing then
			rep.DressingParts += topParts
			-- H10: dressing Models wider than MaxModelSpan
			for _, d in ipairs(all) do
				if d:IsA("Model") then
					local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
					for _, q in ipairs(d:GetDescendants()) do
						local qb = if q:IsA("BasePart") then boxes[q] else nil
						if qb then
							x0, x1, z0, z1 = math.min(x0, qb.X0), math.max(x1, qb.X1), math.min(z0, qb.Z0), math.max(z1, qb.Z1)
						end
					end
					local span = math.max(x1 - x0, z1 - z0)
					if x1 >= x0 and span > H.MaxModelSpan then
						addViolation(rep, "H10", pathOf(d, root), string.format("model %.0f studs across", span), (x0 + x1) * 0.5, (z0 + z1) * 0.5)
					end
				end
			end
			-- H1 orphans
			for _, o in ipairs(findOrphans(ctx, top, boxes)) do
				local x, z = centreOf(o.Unit.Box)
				local kind = if o.Unit.Natural then "natural" else "man-made"
				table.insert(rep.Orphans, { Path = o.Unit.Key, Kind = kind, X = x, Z = z, Parts = #o.Unit.Parts, Nearest = o.Nearest })
				addViolation(rep, "H1", o.Unit.Key, string.format("%s orphan, %d parts, %.0f from an anchor", kind, #o.Unit.Parts, o.Nearest), x, z)
			end
		end
	end
	if #lights > WorldConfig.Lights.MaxWorld then
		addViolation(rep, "H8", rep.Root, string.format("%d lights > %d", #lights, WorldConfig.Lights.MaxWorld), 0, 0)
	end
	if rep.Census.ShadowCasters > H.MaxShadowCasters then
		addViolation(rep, "H9", rep.Root, string.format("%d shadow casters > %d", rep.Census.ShadowCasters, H.MaxShadowCasters), 0, 0)
	end
	return rep
end

function WorldHygiene.Check(root: Instance, opts: Opts?): { Violation }
	return WorldHygiene.Report(root, opts).Violations
end

-- ── Enforce ───────────────────────────────────────────────────────────────────

local function countParts(inst: Instance): number
	local n = if inst:IsA("BasePart") then 1 else 0
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

-- one dressing folder: H6, H5, H3, H4, H2, H9 (H8 / H1 run across all targets afterwards)
local function enforceFolder(folder: Instance, ctx: Ctx, actions: { [string]: number })
	local boxes: { [BasePart]: Box } = {}
	local parts: { BasePart } = {}
	local desc = folder:GetDescendants()
	for _, d in ipairs(desc) do
		if d:IsA("BasePart") then
			boxes[d] = worldBox(d)
			table.insert(parts, d)
		end
	end

	local doomed: { [Instance]: string } = {} -- instance -> rule
	local function isDoomed(inst: Instance): boolean
		local cur: Instance? = inst
		while cur and cur ~= folder do
			if doomed[cur] then
				return true
			end
			cur = cur.Parent
		end
		return false
	end

	-- H6: static Humanoids → their model (or the Humanoid alone)
	for _, d in ipairs(desc) do
		if d:IsA("Humanoid") then
			local m = d.Parent
			local victim: Instance = if m and m ~= folder and m:IsA("Model") then m else d
			if not doomed[victim] then
				doomed[victim] = "H6"
			end
		end
	end

	-- H5: Beams and BillboardGuis go; Neon becomes SmoothPlastic
	for _, d in ipairs(desc) do
		if d.Parent ~= nil and (d:IsA("Beam") or (d:IsA("BillboardGui") and Rules.H5(d, folder) ~= nil)) then
			d:Destroy()
			actions.H5 += 1
		end
	end
	for _, p in ipairs(parts) do
		if p.Material == Enum.Material.Neon then
			p.Material = Enum.Material.SmoothPlastic
			actions.H5 += 1
		end
	end

	-- kit resolution for destroy rules: the nearest Model / kit Folder below `folder` when it spans <= KitMaxSpan
	-- and holds nothing protected; otherwise the part alone (plus the raised parts it carried)
	local kitMemo: { [Instance]: boolean } = {}
	local function kitOk(kit: Instance, protected: (Instance) -> boolean): boolean
		local memo = kitMemo[kit]
		if memo ~= nil then
			return memo
		end
		local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
		local ok = true
		for _, k in ipairs(kit:GetDescendants()) do
			local kb = if k:IsA("BasePart") then boxes[k] else nil
			if kb then
				x0, x1, z0, z1 = math.min(x0, kb.X0), math.max(x1, kb.X1), math.min(z0, kb.Z0), math.max(z1, kb.Z1)
				if protected(k) then
					ok = false
					break
				end
			end
		end
		ok = ok and x1 >= x0 and math.max(x1 - x0, z1 - z0) <= H.KitMaxSpan
		kitMemo[kit] = ok
		return ok
	end
	local siblings: { [Instance]: { BasePart } } = {}
	for _, p in ipairs(parts) do
		local parent = p.Parent
		if parent then
			local l = siblings[parent]
			if not l then
				l = {}
				siblings[parent] = l
			end
			table.insert(l, p)
		end
	end
	local function doom(hit: BasePart, rule: string, protected: (Instance) -> boolean)
		local victim: BasePart = hit
		local cur = hit.Parent
		while cur and cur ~= folder do
			if cur:IsA("BasePart") then
				victim = cur
			elseif not (cur:IsA("Model") and cur.Parent and cur.Parent:IsA("BasePart")) then
				break
			end
			cur = cur.Parent
		end
		if cur and cur ~= folder and (cur:IsA("Model") or cur:IsA("Folder")) and kitOk(cur, protected) then
			if not doomed[cur] then
				doomed[cur] = rule
			end
			return
		end
		if doomed[victim] then
			return
		end
		doomed[victim] = rule
		-- sweep: raised siblings touching it (sandbag tops, sign faces), bounded to KitMaxSpan from the hit
		local vb = boxes[victim]
		if not vb then
			return
		end
		local cx, cz = centreOf(vb)
		local queue: { BasePart } = { victim }
		local head = 1
		while head <= #queue do
			local item = queue[head]
			head += 1
			local ib = boxes[item]
			for _, q in ipairs((item.Parent and siblings[item.Parent]) or {}) do
				local qb = boxes[q]
				if
					not doomed[q]
					and qb.Y0 > GROUND_TOP_Y + 0.1
					and qb.X1 >= ib.X0 - 0.1
					and qb.X0 <= ib.X1 + 0.1
					and qb.Y1 >= ib.Y0 - 0.1
					and qb.Y0 <= ib.Y1 + 0.1
					and qb.Z1 >= ib.Z0 - 0.1
					and qb.Z0 <= ib.Z1 + 0.1
					and math.max(math.abs((qb.X0 + qb.X1) * 0.5 - cx), math.abs((qb.Z0 + qb.Z1) * 0.5 - cz)) <= H.KitMaxSpan
					and not protected(q)
				then
					doomed[q] = rule
					table.insert(queue, q)
				end
			end
		end
	end

	-- H3: clear zones (water hits honour WE_AllowInWater)
	local function inWaterAllowed(inst: Instance): boolean
		return attrUp(inst, "WE_AllowInWater", folder)
	end
	local function noProtection(_inst: Instance): boolean
		return false
	end
	for _, p in ipairs(parts) do
		if not isDoomed(p) then
			local zone, wet = Rules.H3(ctx, boxes[p])
			if zone and not (wet and inWaterAllowed(p)) then
				doom(p, "H3", if wet then inWaterAllowed else noProtection)
			end
		end
	end

	-- H4: walk-through cover becomes solid (before H2, so new blockers on a road are then removed)
	for _, p in ipairs(parts) do
		if not isDoomed(p) and Rules.H4Candidate(p, boxes[p], folder) and not (p.CanCollide and p.CanQuery) then
			p.CanCollide = true
			p.CanQuery = true
			actions.H4 += 1
		end
	end

	-- H2: road corridor
	local function roadProtected(inst: Instance): boolean
		return Rules.RoadExempt(inst, folder)
	end
	for _, p in ipairs(parts) do
		if not isDoomed(p) and not Rules.RoadExempt(p, folder) and Rules.H2(ctx, p, boxes[p]) then
			doom(p, "H2", roadProtected)
		end
	end

	-- H9: no small shadow casters
	for _, p in ipairs(parts) do
		if not isDoomed(p) and Rules.H9(p) then
			p.CastShadow = false
			actions.H9 += 1
		end
	end

	-- destroy the top-most doomed instances; count parts per rule
	local function underDoomedParent(inst: Instance): boolean
		local parent = inst.Parent
		return parent ~= nil and parent ~= folder and isDoomed(parent)
	end
	local tops: { Instance } = {}
	for inst in pairs(doomed) do
		if not underDoomedParent(inst) then
			table.insert(tops, inst)
		end
	end
	for _, inst in ipairs(tops) do
		local rule = doomed[inst]
		actions[rule] += countParts(inst)
		inst:Destroy()
	end
end

function WorldHygiene.Enforce(root: Instance, opts: Opts?): Report
	local ctx = buildContext(opts)
	local actions: { [string]: number } = {}
	for _, r in ipairs(RULES) do
		actions[r] = 0
	end
	local targets: { Instance } = {}
	if DRESSING[root.Name] then
		table.insert(targets, root)
	else
		for _, ch in ipairs(root:GetChildren()) do
			if DRESSING[ch.Name] then
				table.insert(targets, ch)
			end
		end
	end
	for _, folder in ipairs(targets) do
		enforceFolder(folder, ctx, actions)
	end

	-- H8: clamp and tag dressing lights; drop dressing lights beyond the world budget (deterministic order)
	local worldRoot: Instance = (opts and opts.WorldRoot) or (if DRESSING[root.Name] and root.Parent then root.Parent else root)
	local L = WorldConfig.Lights
	local tag = WorldConfig.Atmosphere.NightLightTag
	local clock: any = Lighting.ClockTime
	local night = WorldAtmosphere.NightShare(if type(clock) == "number" then clock else 12) > 0.5
	local dressingLights: { Light } = {}
	for _, folder in ipairs(targets) do
		for _, d in ipairs(folder:GetDescendants()) do
			if d:IsA("Light") then
				table.insert(dressingLights, d)
			end
		end
	end
	table.sort(dressingLights, function(a: Light, b: Light): boolean
		return a:GetFullName() < b:GetFullName()
	end)
	-- every world light outside the folders enforced now counts, including OTHER dressing folders (the hook enforces
	-- WorldDressing and DesertFlora in separate calls; each call must see the other's lights to keep the 24 total)
	local isTarget: { [Instance]: boolean } = {}
	for _, folder in ipairs(targets) do
		isTarget[folder] = true
	end
	local otherLights = 0
	local wl, _ = scopes(worldRoot)
	for _, top in ipairs(wl) do
		if not isTarget[top] then
			for _, d in ipairs(top:GetDescendants()) do
				if d:IsA("Light") then
					otherLights += 1
				end
			end
		end
	end
	local budget = math.max(0, L.MaxWorld - otherLights)
	for i, light in ipairs(dressingLights) do
		if i > budget then
			light:Destroy()
			actions.H8 += 1
		else
			local changed = false
			if light.Brightness > L.MaxBrightness then
				light.Brightness = L.MaxBrightness
				changed = true
			end
			local anyLight: any = light
			if type(anyLight.Range) == "number" and anyLight.Range > L.MaxRange then
				anyLight.Range = L.MaxRange
				changed = true
			end
			if light.Shadows ~= L.Shadows then
				light.Shadows = L.Shadows
				changed = true
			end
			if not CollectionService:HasTag(light, tag) then
				CollectionService:AddTag(light, tag)
				light.Enabled = night
				changed = true
			end
			if changed then
				actions.H8 += 1
			end
		end
	end

	-- H1: orphans (W1 = Report mode: listed, not destroyed)
	local mode = (opts and opts.OrphanMode) or H.OrphanMode
	if mode == "Enforce" then
		for _, folder in ipairs(targets) do
			local boxes: { [BasePart]: Box } = {}
			for _, d in ipairs(folder:GetDescendants()) do
				if d:IsA("BasePart") then
					boxes[d] = worldBox(d)
				end
			end
			for _, o in ipairs(findOrphans(ctx, folder, boxes)) do
				local u = o.Unit
				if u.Inst and u.Inst.Parent then
					actions.H1 += countParts(u.Inst)
					u.Inst:Destroy()
				else
					for _, p in ipairs(u.Parts) do
						if p.Parent then
							actions.H1 += 1
							p:Destroy()
						end
					end
				end
			end
		end
	end

	local rep = WorldHygiene.Report(root, opts)
	rep.Mode = "Enforce"
	rep.Actions = actions
	if not (opts and opts.Log == false) then
		print(
			string.format(
				"[WAR EMPIRE] WorldHygiene: %s — destroyed H2 %d, H3 %d, H6 %d, H8 %d lights; set H4 %d, H5 %d, H9 %d; orphans %d (%s); left %d parts",
				root.Name,
				actions.H2,
				actions.H3,
				actions.H6,
				actions.H8,
				actions.H4,
				actions.H5,
				actions.H9,
				#rep.Orphans,
				mode,
				rep.Parts
			)
		)
	end
	return rep
end

return WorldHygiene
