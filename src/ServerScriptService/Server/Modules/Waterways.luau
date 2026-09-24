--!strict
--[[
	WAR EMPIRE v70 — Waterways (spec_final §5)
	One module for the public water network and the sea gates' boat loop:
	  * Build(root): root.CoastalWater — Water/<Name> (one WE_Water part per public rect: the sea band, the ring canal
	    with the oil-rig lagoons, the South Docks harbour + slips, and the 6 dock channels when the plots face the map
	    centre) and Banks/<Name>_Bank (a thin sand rim under/around each rect). Plot water (DockWater, SeaGateWater),
	    sea gates, naval pads, road ends and rig piers are built by MapSetup (spec J6), not here.
	  * StartSeaGates(deps) / StepSeaGates(now): the 4 Hz sea-gate loop (J1). StructureKitBuilder.SyncRearGates only
	    ARMS a sea gate (Dock L1+); this loop opens an armed gate while a boat DRIVEN by the plot owner or a clan-mate
	    is near it and closes it CloseDelay seconds after the last one leaves. Driverless boats never open it, so the
	    Dock is never a walk-in back door past the main-gate raid barrier.
	  * CullDressing(folder): safety net for MapDressing / DesertFlora — destroys decor parts that stand in water or on
	    a plot pad (parts with WE_AllowInWater are exempt), and (roadmap W0 ROAD, WaterConfig.RoadCull) decor in the
	    road corridor, whole kits where they are small. RoadLines / IsNearRoadXZ expose the road centre lines.
	Geometry lives in Configs/WaterConfig (world rects) and Configs/BaseLayoutConfig (plot-local sea gate / basin).
	Water parts are CanCollide / CanTouch / CanQuery / CastShadow false: boats read the tagged parts geometrically
	(VehicleService), combat and ground raycasts pass through to the real floor.
	Never requires MapSetup (MapSetup / MapDressing / DesertFlora require this module).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WaterConfig = require(Shared.Configs.WaterConfig)
local BaseConfig = require(Shared.Configs.BaseConfig)
local BaseLayout = require(script.Parent.BaseLayout)

type Rect = WaterConfig.Rect
export type RoadLine = { Name: string, AlongX: boolean, Across: number, Min: number, Max: number }

export type SeaGateDeps = {
	BaseService: any?,
	GateDefenseService: any?,
	ClanService: any?,
}

local Waterways = {}

local TAG_WATER = "WE_Water" -- = Constants.Tags.Water (VehicleService reads the tagged parts)
local GROUND_TOP_Y = 0.5 -- desert floor top (MapSetup Ground)
local SeaGate = WaterConfig.SeaGate

local function r2(v: number): number
	return math.round(v * 100) / 100
end

local function copyRect(r: Rect, name: string?): Rect
	return { Name = name or r.Name, X0 = r.X0, X1 = r.X1, Z0 = r.Z0, Z1 = r.Z1, Bank = r.Bank }
end

local function layoutPlotSize(): number
	local cfg = BaseLayout.Config() :: any
	return if type(cfg) == "table" and type(cfg.PlotSize) == "number" then cfg.PlotSize else 320
end

-- ── Geometry ────────────────────────────────────────────────────────────────

-- Channel from plot `plotId`'s sea gate (pad edge) straight out of the plot rear to WaterConfig.Channels[..].Until.
-- nil while the plots do not face the map centre (the docks stay isolated, as before v70).
function Waterways.ChannelRect(plotId: number): Rect?
	if not (WaterConfig.Enabled and BaseLayout.FacesMapCentre()) then
		return nil
	end
	local channel = nil
	for _, c in ipairs(WaterConfig.Channels) do
		if c.PlotId == plotId then
			channel = c
			break
		end
	end
	local pos: Vector3? = BaseConfig.PlotPositions[plotId]
	if channel == nil or pos == nil then
		return nil
	end
	local H = layoutPlotSize() * 0.5
	-- the gate opening's world across-range (a 1-deep strip just outside the pad edge)
	local c, sx, sz = BaseLayout.PlotRect(pos, (SeaGate.X0 + SeaGate.X1) * 0.5, -H - 0.5, SeaGate.X1 - SeaGate.X0, 1)
	local rear = BaseLayout.PlotCFrame(pos):VectorToWorldSpace(Vector3.new(0, 0, -1))
	local edge = BaseLayout.PlotPoint(pos, 0, -H)
	local name = "Ch_P" .. tostring(plotId)
	if math.abs(rear.X) > 0.5 then
		local e = r2(edge.X)
		return {
			Name = name,
			X0 = math.min(e, channel.Until),
			X1 = math.max(e, channel.Until),
			Z0 = r2(c.Z - sz * 0.5),
			Z1 = r2(c.Z + sz * 0.5),
		}
	end
	local e = r2(edge.Z)
	return {
		Name = name,
		X0 = r2(c.X - sx * 0.5),
		X1 = r2(c.X + sx * 0.5),
		Z0 = math.min(e, channel.Until),
		Z1 = math.max(e, channel.Until),
	}
end

-- Public water: WaterConfig.Public, plus the dock channels when BaseLayout.FacesMapCentre().
-- WaterConfig.Enabled = false keeps only the sea band (Sea_*), so the naval pads still float and no ring or harbour
-- appears where the roads (then full length) run.
function Waterways.PublicRects(): { Rect }
	local out: { Rect } = {}
	for _, r in ipairs(WaterConfig.Public) do
		if WaterConfig.Enabled or string.sub(r.Name, 1, 4) == "Sea_" then
			table.insert(out, copyRect(r))
		end
	end
	if WaterConfig.Enabled and BaseLayout.FacesMapCentre() then
		for plotId = 1, #BaseConfig.PlotPositions do
			local ch = Waterways.ChannelRect(plotId)
			if ch then
				table.insert(out, ch)
			end
		end
	end
	return out
end

-- Plot water world AABBs (MapSetup builds these parts): P<N>_DockWater always with the layout on, and
-- P<N>_SeaGateWater when the sea gates exist (FacesMapCentre and WaterConfig.Enabled).
function Waterways.PlotWaterRects(): { Rect }
	local out: { Rect } = {}
	if not BaseLayout.Enabled() then
		return out
	end
	local cfg = BaseLayout.Config() :: any
	local basin = cfg.Courtyard and cfg.Courtyard.DockBasin
	local gates = WaterConfig.Enabled and BaseLayout.FacesMapCentre()
	for plotId, pos in ipairs(BaseConfig.PlotPositions) do
		if basin then
			local c, sx, sz = BaseLayout.PlotRect(pos, basin.X, basin.Z, basin.SizeX, basin.SizeZ)
			table.insert(out, {
				Name = "P" .. plotId .. "_DockWater",
				X0 = r2(c.X - sx * 0.5),
				X1 = r2(c.X + sx * 0.5),
				Z0 = r2(c.Z - sz * 0.5),
				Z1 = r2(c.Z + sz * 0.5),
			})
		end
		if gates then
			local depth = SeaGate.BasinRearZ - SeaGate.PadEdgeZ
			local c, sx, sz = BaseLayout.PlotRect(
				pos,
				(SeaGate.X0 + SeaGate.X1) * 0.5,
				(SeaGate.PadEdgeZ + SeaGate.BasinRearZ) * 0.5,
				SeaGate.X1 - SeaGate.X0,
				depth
			)
			table.insert(out, {
				Name = "P" .. plotId .. "_SeaGateWater",
				X0 = r2(c.X - sx * 0.5),
				X1 = r2(c.X + sx * 0.5),
				Z0 = r2(c.Z - sz * 0.5),
				Z1 = r2(c.Z + sz * 0.5),
			})
		end
	end
	return out
end

-- Every WE_Water surface on the map (public + channels + plot water), world XZ rects.
function Waterways.AllRects(): { Rect }
	local out = Waterways.PublicRects()
	for _, r in ipairs(Waterways.PlotWaterRects()) do
		table.insert(out, r)
	end
	return out
end

local function inRects(rects: { Rect }, x: number, z: number, m: number): boolean
	for _, r in ipairs(rects) do
		if x >= r.X0 - m and x <= r.X1 + m and z >= r.Z0 - m and z <= r.Z1 + m then
			return true
		end
	end
	return false
end

-- true when (x, z) is on (or within `margin` studs of) any water: public, channels or plot water
function Waterways.IsWaterXZ(x: number, z: number, margin: number?): boolean
	return inRects(Waterways.AllRects(), x, z, margin or 0)
end

local function padRects(): { Rect }
	local half = (BaseConfig.PlotSize :: Vector3).X * 0.5
	local out: { Rect } = {}
	for plotId, pos in ipairs(BaseConfig.PlotPositions) do
		table.insert(out, { Name = "Plot" .. plotId, X0 = pos.X - half, X1 = pos.X + half, Z0 = pos.Z - half, Z1 = pos.Z + half })
	end
	return out
end

-- true when (x, z) is on (or within `margin` studs of) a plot pad (pads are square, so the plot yaw never matters)
function Waterways.IsOnPlotPadXZ(x: number, z: number, margin: number?): boolean
	return inRects(padRects(), x, z, margin or 0)
end

-- World road centre lines, from the WaterConfig.RoadEnds keys (MapSetup builds the roads from the same table):
-- RoadX<x> runs along Z at x = Across, RoadZ<z> along X at z = Across, over Min..Max (the whole map while
-- WaterConfig.Enabled is false, when MapSetup builds them full length). Sorted by name.
function Waterways.RoadLines(): { RoadLine }
	local out: { RoadLine } = {}
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
	table.sort(out, function(a: RoadLine, b: RoadLine): boolean
		return a.Name < b.Name
	end)
	return out
end

-- Smallest across-gap from the XZ box to the centre line of a road whose extent it overlaps along the road
-- (0 = the box straddles the line); math.huge when it is beside no road.
local function roadGap(roads: { RoadLine }, x0: number, x1: number, z0: number, z1: number): number
	local best = math.huge
	for _, r in ipairs(roads) do
		local a0, a1, c0, c1 = x0, x1, z0, z1 -- along, across
		if not r.AlongX then
			a0, a1, c0, c1 = z0, z1, x0, x1
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

-- true when (x, z) is within `margin` studs (default WaterConfig.RoadCull.Corridor) of a road centre line
function Waterways.IsNearRoadXZ(x: number, z: number, margin: number?): boolean
	return roadGap(Waterways.RoadLines(), x, x, z, z) <= (margin or WaterConfig.RoadCull.Corridor)
end

-- ── Build ───────────────────────────────────────────────────────────────────

local function flatPart(name: string, size: Vector3, cf: CFrame, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Parent = parent
	return p
end

-- Builds root.CoastalWater (replaces an old one). Called by MapSetup.Run where the old WaterPlane block was.
function Waterways.Build(root: Instance): Folder
	local old = root:FindFirstChild("CoastalWater")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "CoastalWater"
	local waterFolder = Instance.new("Folder")
	waterFolder.Name = "Water"
	waterFolder.Parent = folder
	local bankFolder = Instance.new("Folder")
	bankFolder.Name = "Banks"
	bankFolder.Parent = folder

	local look = WaterConfig.Look
	local bottom, top = WaterConfig.BottomY, WaterConfig.SurfaceY
	local rects = Waterways.PublicRects()
	local channels = 0
	for i, r in ipairs(rects) do
		local cx, cz = (r.X0 + r.X1) * 0.5, (r.Z0 + r.Z1) * 0.5
		local sx, sz = r.X1 - r.X0, r.Z1 - r.Z0
		local water = flatPart(r.Name, Vector3.new(sx, top - bottom, sz), CFrame.new(cx, (bottom + top) * 0.5, cz), waterFolder)
		water.Material = look.Material
		water.Color = look.Color
		water.Transparency = look.Transparency
		water.Reflectance = look.Reflectance
		water:SetAttribute("WE_WaterId", r.Name)
		CollectionService:AddTag(water, TAG_WATER)
		if string.sub(r.Name, 1, 3) == "Ch_" then
			channels += 1
		end

		-- sand rim: the rect grown by its bank width; tops step 0.004 per rect so overlapping banks never z-fight
		local b = r.Bank or WaterConfig.BankWidth
		local bankTop = WaterConfig.BankTop + (i - 1) * 0.004
		local bank = flatPart(
			r.Name .. "_Bank",
			Vector3.new(sx + b * 2, bankTop - GROUND_TOP_Y, sz + b * 2),
			CFrame.new(cx, (GROUND_TOP_Y + bankTop) * 0.5, cz),
			bankFolder
		)
		bank.Material = WaterConfig.BankMaterial
		bank.Color = WaterConfig.BankColor
	end
	folder.Parent = root
	print(
		string.format(
			"[WAR EMPIRE] Waterways: %d water parts (%d channels), %d banks, surface y %.2f, faceMapCentre=%s",
			#rects,
			channels,
			#rects,
			top,
			tostring(BaseLayout.FacesMapCentre())
		)
	)
	return folder
end

-- ── Dressing safety net (spec §9.12; roadmap W0 ROAD / World v2 H2) ─────────

type Box = { X0: number, X1: number, Y0: number, Y1: number, Z0: number, Z1: number }

local function worldBox(part: BasePart): Box
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = part.CFrame:GetComponents()
	local hx, hy, hz = part.Size.X * 0.5, part.Size.Y * 0.5, part.Size.Z * 0.5
	local ex = math.abs(r00) * hx + math.abs(r01) * hy + math.abs(r02) * hz
	local ey = math.abs(r10) * hx + math.abs(r11) * hy + math.abs(r12) * hz
	local ez = math.abs(r20) * hx + math.abs(r21) * hy + math.abs(r22) * hz
	return { X0 = x - ex, X1 = x + ex, Y0 = y - ey, Y1 = y + ey, Z0 = z - ez, Z1 = z + ez }
end

local function boxesTouch(a: Box, b: Box, grow: number): boolean
	return a.X0 <= b.X1 + grow
		and a.X1 >= b.X0 - grow
		and a.Y0 <= b.Y1 + grow
		and a.Y1 >= b.Y0 - grow
		and a.Z0 <= b.Z1 + grow
		and a.Z1 >= b.Z0 - grow
end

local function allowedInWater(part: Instance, stop: Instance): boolean
	local cur: Instance? = part
	while cur and cur ~= stop do
		if cur:GetAttribute("WE_AllowInWater") == true then
			return true
		end
		cur = cur.Parent
	end
	return false
end

local function toSet(list: { string }?): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for _, s in ipairs(list or {}) do
		out[s] = true
	end
	return out
end

local function overlapsAny(rects: { Rect }, x0: number, x1: number, z0: number, z1: number, grow: number): boolean
	for _, r in ipairs(rects) do
		if x0 < r.X1 + grow and x1 > r.X0 - grow and z0 < r.Z1 + grow and z1 > r.Z0 - grow then
			return true
		end
	end
	return false
end

-- Destroys decor under `folder` (MapDressing's WorldDressing, DesertFlora's DesertFlora) that
--   * overlaps water (grown by 2) with its bottom below SurfaceY + 14, or overlaps a plot pad grown by 4
--     (WE_AllowInWater on the part or an ancestor exempts it from this rule); or
--   * stands on a world road (WaterConfig.RoadCull): collidable with its top above MinTop within Corridor studs of a
--     centre line, or any visible non-marking part taller than LaneMaxHeight within Lane studs. A road hit takes its
--     whole kit (nearest Model / kit Folder spanning <= KitMaxSpan) or, part alone, the raised parts it carried.
--     Map.RoadEnds, Bases, Territories, Plot<N> folders, ExemptNames and WE_AllowOnRoad are never road hits.
-- Returns the number of BaseParts destroyed (kit members included).
function Waterways.CullDressing(folder: Instance): number
	local water = Waterways.AllRects()
	local pads = padRects()
	local maxBottom = WaterConfig.SurfaceY + 14
	local rc = WaterConfig.RoadCull
	local roads: { RoadLine } = if rc and rc.Enabled then Waterways.RoadLines() else {}
	local exemptAncestors = toSet(rc and rc.ExemptAncestors)
	local exemptNames = toSet(rc and rc.ExemptNames)
	local markings: { string } = (rc and rc.MarkingPrefixes) or {}
	local laneTop = GROUND_TOP_Y + ((rc and rc.LaneMaxHeight) or 0.3)

	local descendants = folder:GetDescendants()
	local boxes: { [BasePart]: Box } = {}
	local parts: { BasePart } = {}
	for _, d in ipairs(descendants) do
		if d:IsA("BasePart") then
			boxes[d] = worldBox(d)
			table.insert(parts, d)
		end
	end

	local roadExemptMemo: { [Instance]: boolean } = {}
	local function roadExempt(inst: Instance): boolean
		local memo = roadExemptMemo[inst]
		if memo ~= nil then
			return memo
		end
		local res = false
		if inst:GetAttribute("WE_AllowOnRoad") == true or exemptNames[inst.Name] then
			res = true
		elseif exemptAncestors[inst.Name] or string.match(inst.Name, "^Plot%d+$") ~= nil then
			res = not inst:IsA("BasePart")
		end
		if not res and inst ~= folder then
			local parent = inst.Parent
			res = parent ~= nil and roadExempt(parent)
		end
		roadExemptMemo[inst] = res
		return res
	end
	local function isMarking(name: string): boolean
		for _, prefix in ipairs(markings) do
			if string.sub(name, 1, #prefix) == prefix then
				return true
			end
		end
		return false
	end

	-- 1) hits
	local doomed: { [Instance]: boolean } = {}
	local wetHits: { BasePart } = {}
	local roadHits: { BasePart } = {}
	for _, d in ipairs(parts) do
		local b = boxes[d]
		if
			not allowedInWater(d, folder)
			and ((b.Y0 < maxBottom and overlapsAny(water, b.X0, b.X1, b.Z0, b.Z1, 2)) or overlapsAny(pads, b.X0, b.X1, b.Z0, b.Z1, 4))
		then
			table.insert(wetHits, d)
		elseif #roads > 0 and b.Y1 > rc.MinTop then
			local gap = roadGap(roads, b.X0, b.X1, b.Z0, b.Z1)
			local hit = (gap <= rc.Corridor and d.CanCollide)
				or (gap <= rc.Lane and b.Y1 > laneTop and d.Transparency < 0.99 and not isMarking(d.Name))
			if hit and not roadExempt(d) then
				table.insert(roadHits, d)
			end
		end
	end
	for _, d in ipairs(wetHits) do
		doomed[d] = true
	end

	-- 2) whole kit for road hits: the nearest Model / Folder below `folder`, if it is small and holds nothing exempt
	local kitMemo: { [Instance]: boolean } = {}
	local function kitOk(kit: Instance): boolean
		local memo = kitMemo[kit]
		if memo ~= nil then
			return memo
		end
		local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
		local ok = true
		for _, k in ipairs(kit:GetDescendants()) do
			local kb = if k:IsA("BasePart") then boxes[k] else nil
			if kb then
				x0, x1 = math.min(x0, kb.X0), math.max(x1, kb.X1)
				z0, z1 = math.min(z0, kb.Z0), math.max(z1, kb.Z1)
				if allowedInWater(k, folder) or roadExempt(k) then
					ok = false
					break
				end
			end
		end
		ok = ok and x1 >= x0 and math.max(x1 - x0, z1 - z0) <= rc.KitMaxSpan
		kitMemo[kit] = ok
		return ok
	end
	local kits = 0
	local loose: { BasePart } = {}
	for _, d in ipairs(roadHits) do
		-- climb out of part chains and catalog overlays (a Model parented to its host part): the part alone is then
		-- the top-most host part, and the kit is the container above it
		local victim: BasePart = d
		local cur = d.Parent
		while cur and cur ~= folder do
			if cur:IsA("BasePart") then
				victim = cur
			elseif not (cur:IsA("Model") and cur.Parent and cur.Parent:IsA("BasePart")) then
				break
			end
			cur = cur.Parent
		end
		if cur and cur ~= folder and (cur:IsA("Model") or cur:IsA("Folder")) and kitOk(cur) then
			if not doomed[cur] then
				doomed[cur] = true
				kits += 1
			end
		elseif not doomed[victim] then
			doomed[victim] = true
			table.insert(loose, victim)
		end
	end

	-- 3) part-alone road hits also take the raised siblings they carried (flood over touching AABBs, bounded)
	if rc and rc.SweepAttached and #loose > 0 then
		local siblings: { [Instance]: { BasePart } } = {}
		for _, d in ipairs(parts) do
			local parent = d.Parent
			if parent then
				local list = siblings[parent]
				if not list then
					list = {}
					siblings[parent] = list
				end
				table.insert(list, d)
			end
		end
		local minBottom = GROUND_TOP_Y + rc.SweepMinLift
		local queue: { { Part: BasePart, CX: number, CZ: number } } = {}
		for _, d in ipairs(loose) do
			local b = boxes[d]
			table.insert(queue, { Part = d, CX = (b.X0 + b.X1) * 0.5, CZ = (b.Z0 + b.Z1) * 0.5 })
		end
		local head = 1
		while head <= #queue do
			local item = queue[head]
			head += 1
			local pb = boxes[item.Part]
			local parent = item.Part.Parent
			for _, q in ipairs((parent and siblings[parent]) or {}) do
				local qb = boxes[q]
				if
					not doomed[q]
					and qb.Y0 > minBottom
					and boxesTouch(pb, qb, rc.SweepTouch)
					and math.max(math.abs((qb.X0 + qb.X1) * 0.5 - item.CX), math.abs((qb.Z0 + qb.Z1) * 0.5 - item.CZ))
						<= rc.KitMaxSpan
					and not allowedInWater(q, folder)
					and not roadExempt(q)
				then
					doomed[q] = true
					table.insert(queue, { Part = q, CX = item.CX, CZ = item.CZ })
				end
			end
		end
	end

	-- 4) count (kit members included), then destroy only the top-most doomed instances
	local function underDoomed(inst: Instance): boolean
		local cur: Instance? = inst
		while cur and cur ~= folder do
			if doomed[cur] then
				return true
			end
			cur = cur.Parent
		end
		return false
	end
	local wetSet: { [Instance]: boolean } = {}
	for _, d in ipairs(wetHits) do
		wetSet[d] = true
	end
	local function underWet(inst: Instance): boolean
		local cur: Instance? = inst
		while cur and cur ~= folder do
			if wetSet[cur] then
				return true
			end
			cur = cur.Parent
		end
		return false
	end
	local total, wetParts = 0, 0
	for _, d in ipairs(parts) do
		if underDoomed(d) then
			total += 1
			if underWet(d) then
				wetParts += 1
			end
		end
	end
	for inst in pairs(doomed) do
		local parent = inst.Parent
		if not (parent and parent ~= folder and underDoomed(parent)) then
			inst:Destroy()
		end
	end
	if total > 0 then
		print(
			string.format(
				"[WAR EMPIRE] Waterways: culled %d decor parts under %s (%d in water / on plot pads, %d on roads: %d hits, %d kits)",
				total,
				folder.Name,
				wetParts,
				total - wetParts,
				#roadHits,
				kits
			)
		)
	end
	return total
end

-- ── Sea-gate loop (J1) ──────────────────────────────────────────────────────

local deps: SeaGateDeps = {}
local started = false
local gateCache: { Instance } = {}
local lastScan = -math.huge
local allyAt: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any
local warned: { [string]: boolean } = {}
local warnedCount = 0
local skbModule: any = nil
local clanModule: any = nil -- false = looked up and missing

local function warnOnce(msg: string)
	if warned[msg] or warnedCount >= 20 then
		return
	end
	warned[msg] = true
	warnedCount += 1
	warn("[WAR EMPIRE] Waterways sea gate:", msg)
end

local function kitBuilder(): any
	if skbModule == nil then
		skbModule = require(script.Parent.StructureKitBuilder) :: any
	end
	return skbModule
end

local function clanService(): any?
	if deps.ClanService then
		return deps.ClanService
	end
	if clanModule == nil then
		local ok, m = pcall(function(): any
			return require(script.Parent.Parent.Services.ClanService) :: any
		end)
		clanModule = if ok and type(m) == "table" then m else false
	end
	return if clanModule then clanModule else nil
end

-- the plot owner, or a player in the owner's clan (GateDefenseService.IsAlly; ClanService directly if that is
-- missing; neither → owner only)
local function isAlly(ownerUserId: number, player: Player): boolean
	if player.UserId == ownerUserId then
		return true
	end
	local gds = deps.GateDefenseService
	if gds and type(gds.IsAlly) == "function" then
		local ok, res = pcall(gds.IsAlly, ownerUserId, player)
		return ok and res == true
	end
	local cs = clanService()
	if cs and type(cs.GetClanId) == "function" then
		local owner = Players:GetPlayerByUserId(ownerUserId)
		if not owner then
			return false
		end
		local okA, a = pcall(cs.GetClanId, owner)
		local okB, b = pcall(cs.GetClanId, player)
		return okA and okB and type(a) == "string" and a ~= "" and a == b
	end
	return false
end

local function ownerOf(plotId: number?): number?
	local bs = deps.BaseService
	if plotId == nil or not (bs and type(bs.GetOwnerUserId) == "function") then
		return nil
	end
	local ok, uid = pcall(bs.GetOwnerUserId, plotId)
	return if ok and type(uid) == "number" then uid else nil
end

-- a Naval vehicle whose DriverSeat is occupied by a living ally of `ownerUserId`, whose own OwnerUserId (when set) is
-- an ally too, and whose pivot is within OpenRadius (horizontal) / OpenHeight (vertical) of the gate centre
local function allyBoatNear(ownerUserId: number, centre: Vector3): boolean
	local folder = Workspace:FindFirstChild("WarEmpireVehicles")
	if not folder then
		return false
	end
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("WE_Category") == "Naval" then
			local seat = m:FindFirstChild("DriverSeat")
			local occ = if seat and seat:IsA("VehicleSeat") then seat.Occupant else nil
			local character = if occ and occ.Health > 0 then occ.Parent else nil
			if character then
				local d = m:GetPivot().Position - centre
				if Vector3.new(d.X, 0, d.Z).Magnitude <= SeaGate.OpenRadius and math.abs(d.Y) <= SeaGate.OpenHeight then
					local driver = Players:GetPlayerFromCharacter(character)
					if driver and isAlly(ownerUserId, driver) then
						local boatOwner = m:GetAttribute("OwnerUserId")
						local ownerOk = true
						if type(boatOwner) == "number" and boatOwner ~= ownerUserId then
							local bp = Players:GetPlayerByUserId(boatOwner)
							ownerOk = bp ~= nil and isAlly(ownerUserId, bp)
						end
						if ownerOk then
							return true
						end
					end
				end
			end
		end
	end
	return false
end

local function gateList(now: number): { Instance }
	local stale = now - lastScan >= (if #gateCache == 0 then 2 else 10)
	if not stale then
		for _, g in ipairs(gateCache) do
			if not g:IsDescendantOf(Workspace) then
				stale = true
				break
			end
		end
	end
	if not stale then
		return gateCache
	end
	lastScan = now
	local out: { Instance } = {}
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	local bases = setup and setup:FindFirstChild("Bases")
	if bases then
		for _, plot in ipairs(bases:GetChildren()) do
			local ground = plot:FindFirstChild("LayoutGround")
			if ground then
				for _, g in ipairs(ground:GetChildren()) do
					if g:GetAttribute("WE_GateMode") == "Proximity" then
						table.insert(out, g)
					end
				end
			end
		end
	end
	gateCache = out
	return out
end

local function gatePlotId(gate: Instance): number?
	local id = tonumber(gate:GetAttribute("PlotId"))
	if id then
		return id
	end
	local ground = gate.Parent
	local plot = ground and ground.Parent
	return if plot then tonumber(string.match(plot.Name, "^Plot(%d+)$")) else nil
end

local function stepGate(gate: Instance, now: number)
	local isOpen = gate:GetAttribute("WE_GateOpen") == true
	if gate:GetAttribute("WE_GateArmed") ~= true then
		-- SyncRearGates keeps an unarmed gate closed; belt and braces if something left it open
		allyAt[gate] = nil
		if isOpen then
			kitBuilder().SetGateOpen(gate, false)
		end
		return
	end
	local owner = ownerOf(gatePlotId(gate))
	local centre = gate:GetAttribute("WE_GateCentre")
	local near = owner ~= nil and typeof(centre) == "Vector3" and allyBoatNear(owner, centre)
	if near then
		allyAt[gate] = now
		if not isOpen then
			kitBuilder().SetGateOpen(gate, true)
		end
	elseif isOpen and now - (allyAt[gate] or -math.huge) >= SeaGate.CloseDelay then
		allyAt[gate] = nil
		kitBuilder().SetGateOpen(gate, false)
	end
end

-- One pass over every sea gate (the loop calls it at 1 / LoopSeconds Hz; tests call it with their own clock).
function Waterways.StepSeaGates(now: number)
	for _, gate in ipairs(gateList(now)) do
		local ok, err = pcall(function()
			stepGate(gate, now)
		end)
		if not ok then
			warnOnce(tostring(err))
		end
	end
end

-- Called once by Bootstrap after the services' Init. A second call is ignored.
function Waterways.StartSeaGates(d: SeaGateDeps?)
	if started then
		return
	end
	started = true
	deps = d or {}
	task.spawn(function()
		while true do
			local ok, err = pcall(function()
				Waterways.StepSeaGates(os.clock())
			end)
			if not ok then
				warnOnce(tostring(err))
			end
			task.wait(SeaGate.LoopSeconds)
		end
	end)
end

return Waterways
