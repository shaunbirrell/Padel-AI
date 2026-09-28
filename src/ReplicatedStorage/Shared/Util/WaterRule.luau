--!strict
--[[
	fb4 water rule (VehicleConfig.Drive.WaterRule): the pure geometry both sides use.
	  * Server (the authority): Modules/VehicleWaterGuard, called by VehicleService at WaterRule.Hz per Car / Plane.
	  * The driver's client (feel only): VehicleDriveClient runs the same Probe on the WE_Water parts it has streamed in.
	  * Both Car laws (VehicleService carStep, VehicleDriveClient stepCar) apply the one-way bog inline: never deeper
	    along the outward normal of the bank it came over (Bog()).
	Every WE_Water part is flat and turned about Y only (Waterways; MapSetup turns plot water with the plot by an exact
	quarter turn), so each one is an XZ rectangle with a top face (the water surface). Build() turns a part list into
	plain numbers once (the callers rebuild it only when their part list changes); Probe(), DeepRun(), ExitAlong(),
	NearestBank(), Bog(), InAny() and ShorePoints() read those numbers and never touch an Instance. No services, no
	remotes, no yields.
]]

local WaterRule = {}

export type Rect = {
	CX: number,
	CZ: number,
	RX: number, -- the part's right axis, flat and unit
	RZ: number,
	LX: number, -- its look axis, flat and unit
	LZ: number,
	HX: number, -- half size along those axes
	HZ: number,
	Top: number, -- top face = the water surface
	PlotId: number?, -- WE_PlotId (DockWater) or WE_GatePlotId (SeaGateWater); nil = public water
}

export type ShorePoint = { X: number, Z: number, D: number }

function WaterRule.Build(parts: { BasePart }): { Rect }
	local out: { Rect } = {}
	for _, p in ipairs(parts) do
		if p.Parent ~= nil then
			local cf = p.CFrame
			local pos = cf.Position
			local r, l = cf.RightVector, cf.LookVector
			local rm = math.sqrt(r.X * r.X + r.Z * r.Z)
			local lm = math.sqrt(l.X * l.X + l.Z * l.Z)
			local id = p:GetAttribute("WE_PlotId")
			if id == nil then
				id = p:GetAttribute("WE_GatePlotId")
			end
			table.insert(out, {
				CX = pos.X,
				CZ = pos.Z,
				RX = if rm > 1e-6 then r.X / rm else 1,
				RZ = if rm > 1e-6 then r.Z / rm else 0,
				LX = if lm > 1e-6 then l.X / lm else 0,
				LZ = if lm > 1e-6 then l.Z / lm else 1,
				HX = p.Size.X * 0.5,
				HZ = p.Size.Z * 0.5,
				Top = pos.Y + p.Size.Y * 0.5,
				PlotId = tonumber(id),
			})
		end
	end
	return out
end

-- (x, z) inside r grown by m studs on every side (m < 0 shrinks it)
local function holds(r: Rect, x: number, z: number, m: number): boolean
	local dx, dz = x - r.CX, z - r.CZ
	return math.abs(dx * r.RX + dz * r.RZ) <= r.HX + m and math.abs(dx * r.LX + dz * r.LZ) <= r.HZ + m
end

-- the first water that holds (x, z) with the wheel line wheelY at most `above` over its surface and at most `below`
-- under it (wheelY nil: any height; nil = dry there)
local function wetRect(rects: { Rect }, x: number, z: number, wheelY: number?, above: number, below: number): Rect?
	for _, r in ipairs(rects) do
		if (wheelY == nil or (wheelY <= r.Top + above and wheelY >= r.Top - below)) and holds(r, x, z, 0) then
			return r
		end
	end
	return nil
end

--[[ (centreWet, deepWet, foreign, top) for a vehicle whose chassis centre is over (x, z) with its wheel line at wheelY.
	centreWet: (x, z) is water (see wetRect). deepWet: centreWet and the four points `depth` studs away along +-X / +-Z
	are water too (any part each, so a seam between two water parts is water). foreign: the centre's water is plot water
	(DockWater / SeaGateWater) of a plot other than ownPlot. top: the surface of the water under (x, z) whatever the wheel
	height (nil = over land), so a caller can tell "on a kerb / pontoon / in the air over water" from "on land".
	wheelY nil: the height is not tested (flat geometry only). `below` defaults to 8. ]]
function WaterRule.Probe(
	rects: { Rect },
	x: number,
	z: number,
	wheelY: number?,
	depth: number,
	above: number,
	ownPlot: number?,
	below: number?
): (boolean, boolean, boolean, number?)
	local b = below or 8
	local r = wetRect(rects, x, z, wheelY, above, b)
	if r == nil then
		for _, o in ipairs(rects) do
			if holds(o, x, z, 0) then
				return false, false, false, o.Top
			end
		end
		return false, false, false, nil
	end
	local foreign = r.PlotId ~= nil and r.PlotId ~= ownPlot
	local deep = wetRect(rects, x + depth, z, wheelY, above, b) ~= nil
		and wetRect(rects, x - depth, z, wheelY, above, b) ~= nil
		and wetRect(rects, x, z + depth, wheelY, above, b) ~= nil
		and wetRect(rects, x, z - depth, wheelY, above, b) ~= nil
	return true, deep, foreign, r.Top
end

--[[ The longest stretch (studs) of deep water (Probe's deepWet with the wheel line at wheelY; nil = flat geometry only)
	along the straight line (x0, z0) → (x1, z1), tested every `step` studs (at most 400 points). The water rule's crossing
	test: a line from where a vehicle went in (or its last check) to where it is now that runs over a long stretch of
	deep water means it came out on another shore. ]]
function WaterRule.DeepRun(
	rects: { Rect },
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	wheelY: number?,
	depth: number,
	above: number,
	below: number?,
	step: number
): number
	local dx, dz = x1 - x0, z1 - z0
	local len = math.sqrt(dx * dx + dz * dz)
	local n = math.min(400, math.max(1, math.ceil(len / math.max(0.5, step))))
	local seg = len / n
	local run, best = 0, 0
	for i = 0, n do
		local f = i / n
		local _, deep = WaterRule.Probe(rects, x0 + dx * f, z0 + dz * f, wheelY, depth, above, nil, below)
		if deep then
			run += if i == 0 then 0 else seg
			if run > best then
				best = run
			end
		else
			run = 0
		end
	end
	return best
end

-- how far a ray from (px, pz), inside r, runs along the unit flat direction (dx, dz) before it leaves r
local function rayExit(r: Rect, px: number, pz: number, dx: number, dz: number): number
	local a = (px - r.CX) * r.RX + (pz - r.CZ) * r.RZ
	local b = (px - r.CX) * r.LX + (pz - r.CZ) * r.LZ
	local da = dx * r.RX + dz * r.RZ
	local db = dx * r.LX + dz * r.LZ
	local t = math.huge
	if da > 1e-9 then
		t = math.min(t, (r.HX - a) / da)
	elseif da < -1e-9 then
		t = math.min(t, (-r.HX - a) / da)
	end
	if db > 1e-9 then
		t = math.min(t, (r.HZ - b) / db)
	elseif db < -1e-9 then
		t = math.min(t, (-r.HZ - b) / db)
	end
	return math.max(0, t)
end

--[[ How far the ray from (x, z) along the unit flat direction (dx, dz) runs before it is out of every water rectangle
	(exact, rectangle by rectangle: at most 64 hops); 0 when (x, z) is dry, maxDist when it is still in water there. ]]
function WaterRule.ExitAlong(rects: { Rect }, x: number, z: number, dx: number, dz: number, maxDist: number): number
	local s = 0
	for _ = 1, 64 do
		local px, pz = x + dx * s, z + dz * s
		local far = -1
		for _, r in ipairs(rects) do
			if holds(r, px, pz, 0) then
				far = math.max(far, rayExit(r, px, pz, dx, dz))
			end
		end
		if far < 0 then
			return s -- dry here
		end
		s += far + 1e-4
		if s >= maxDist then
			return maxDist
		end
	end
	return maxDist
end

--[[ The nearest bank from (x, z) in water: of 16 flat directions, the one whose ray leaves the water soonest
	(ExitAlong). Returns (nx, nz, bx, bz, d): that direction (the bank's outward normal: away from the water), the first
	dry point on it and how far that is. d = 0 when (x, z) is dry; nx nil when no dry point is within maxDist. ]]
function WaterRule.NearestBank(rects: { Rect }, x: number, z: number, maxDist: number): (number?, number, number, number, number)
	local best, bx, bz = maxDist, 0, 0
	local found = false
	for k = 0, 15 do
		local a = k * math.pi / 8
		local dx, dz = math.cos(a), math.sin(a)
		local d = WaterRule.ExitAlong(rects, x, z, dx, dz, maxDist)
		if d <= 0 then
			return 0, 0, x, z, 0 -- dry already
		end
		if d < best - 1e-6 then
			best, bx, bz = d, dx, dz
			found = true
		end
	end
	if not found then
		return nil, 0, x, z, maxDist
	end
	return bx, bz, x + bx * best, z + bz * best, best
end

--[[ The one-way bog for a vehicle that has just gone in at (x, z), coming from (ox, oz) (where it was at the last check
	before). Walk back along that line (and on past (ox, oz)), at most maxStuds, to the bank it came over; the outward
	normal of THAT bank (NearestBank from a point 1 stud inside it on the line) is the way out. When the line finds no
	land within maxStuds (a shallow drift along a bank: (ox, oz) is already in the water) it is the normal of the bank
	nearest (ox, oz). Returns (nx, nz, rx, rz, ex, ez); nx nil when no bank is found at all:
	  * n: the unit outward normal. The drive law lets the vehicle move only where it does not get deeper along n.
	  * r: a point on that bank. Depth = (r - p) . n, how far p is inside along n (the grace watches it fall).
	  * e: the entry, on the land it came from: `push` studs past the bank on the line back (else along n). ]]
function WaterRule.Bog(
	rects: { Rect },
	x: number,
	z: number,
	ox: number,
	oz: number,
	push: number,
	maxStuds: number
): (number?, number, number, number, number, number)
	local qx, qz = ox, oz -- the point near the bank the normal is taken from
	local ex, ez, onLine = 0, 0, false
	local dx, dz = ox - x, oz - z
	local len = math.sqrt(dx * dx + dz * dz)
	if len > 1e-3 then
		dx, dz = dx / len, dz / len
		local s = WaterRule.ExitAlong(rects, x, z, dx, dz, maxStuds)
		if s < maxStuds then
			ex, ez, onLine = x + dx * (s + push), z + dz * (s + push), true
			local back = s - math.min(s, 1)
			qx, qz = x + dx * back, z + dz * back
		end
	end
	local nx, nz, bx, bz, d = WaterRule.NearestBank(rects, qx, qz, maxStuds)
	if nx == nil or d <= 0 then
		nx, nz, bx, bz, d = WaterRule.NearestBank(rects, x, z, maxStuds) -- (ox, oz) dry and far: from where it is
	end
	if nx == nil or d <= 0 then
		return nil, 0, 0, 0, 0, 0
	end
	local mx: number = nx
	if not onLine then
		ex, ez = bx + mx * push, bz + nz * push
	end
	return mx, nz, bx, bz, ex, ez
end

-- true when any water rectangle grown by `margin` holds (x, z) (surface heights ignored)
function WaterRule.InAny(rects: { Rect }, x: number, z: number, margin: number): boolean
	for _, r in ipairs(rects) do
		if holds(r, x, z, margin) then
			return true
		end
	end
	return false
end

--[[ Dry points round (x, z), nearest first: along 8 directions, the first point at step, 2 x step, ... up to maxDist
	that no water rectangle grown by `margin` holds, pushed `margin` further out. Surface heights are ignored (the caller's
	ground ray and stand checks decide whether a character can stand there). ]]
function WaterRule.ShorePoints(rects: { Rect }, x: number, z: number, step: number, maxDist: number, margin: number): { ShorePoint }
	local out: { ShorePoint } = {}
	local s0 = math.max(0.5, step)
	for k = 0, 7 do
		local a = k * math.pi / 4
		local dx, dz = math.cos(a), math.sin(a)
		local s = s0
		while s <= maxDist do
			local px, pz = x + dx * s, z + dz * s
			if not WaterRule.InAny(rects, px, pz, margin) then
				table.insert(out, { X = px + dx * margin, Z = pz + dz * margin, D = s + margin })
				break
			end
			s += s0
		end
	end
	table.sort(out, function(a: ShorePoint, b: ShorePoint): boolean
		return a.D < b.D
	end)
	return out
end

return WaterRule
