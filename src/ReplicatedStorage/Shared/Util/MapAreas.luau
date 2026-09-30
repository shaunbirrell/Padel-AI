--!strict
--[[
	claude-bud JOB 30: the world map's named areas, built from the REAL zones (pure; client and server agree):
	  * every enabled WorldConfig.POIs row (Rect or Circle) is an area;
	  * the TerritoryConfig outpost whose Position lies inside an area's footprint is joined to it (Territory);
	  * an OutpostDefenderConfig.Areas garrison with the same Id gives its Tier (the enemies line);
	  * an outpost inside no POI (the offshore rigs) becomes its own area (Kind "rig").
	  Home Outposts (Starter_Pn) are left out: they sit on each base, which the map draws.
	Coordinates are world studs (X, Z); R is the radius used for drawing and tapping.
]]

local Configs = script.Parent.Parent.Configs
local WorldConfig = require(Configs.WorldConfig) :: any
local TerritoryConfig = require(Configs.TerritoryConfig) :: any
local OutpostDefenderConfig = require(Configs.OutpostDefenderConfig) :: any

export type Area = {
	Id: string,
	Name: string,
	Kind: string,
	X: number,
	Z: number,
	R: number,
	Rect: { X0: number, X1: number, Z0: number, Z1: number }?,
	Territory: string?, -- TerritoryConfig Id of the outpost inside it
	Bonus: string?, -- that outpost's Description
	Tier: string?, -- garrison tier ("Easy" | "Medium" | "Hard")
}

local MapAreas = {}

local cache: { Area }? = nil

local function inside(a: Area, x: number, z: number): boolean
	local r = a.Rect
	if r then
		return x >= r.X0 and x <= r.X1 and z >= r.Z0 and z <= r.Z1
	end
	local dx, dz = x - a.X, z - a.Z
	return dx * dx + dz * dz <= a.R * a.R
end

function MapAreas.Inside(a: Area, x: number, z: number): boolean
	return inside(a, x, z)
end

function MapAreas.List(): { Area }
	if cache then
		return cache
	end
	local out: { Area } = {}
	for _, poi in ipairs(WorldConfig.POIs or {}) do
		if poi.Enabled ~= false and typeof(poi.Id) == "string" then
			local a: Area
			if typeof(poi.Rect) == "table" then
				local r = poi.Rect
				a = {
					Id = poi.Id,
					Name = tostring(poi.Name or poi.Id),
					Kind = tostring(poi.Kind or ""),
					X = (r.X0 + r.X1) / 2,
					Z = (r.Z0 + r.Z1) / 2,
					R = math.max(r.X1 - r.X0, r.Z1 - r.Z0) / 2,
					Rect = { X0 = r.X0, X1 = r.X1, Z0 = r.Z0, Z1 = r.Z1 },
				}
			elseif typeof(poi.Circle) == "table" then
				local c = poi.Circle
				a = { Id = poi.Id, Name = tostring(poi.Name or poi.Id), Kind = tostring(poi.Kind or ""), X = c.X, Z = c.Z, R = c.R }
			else
				continue
			end
			table.insert(out, a)
		end
	end
	-- TerritoryConfig.Territories is keyed by Id: walk it in a fixed (sorted) order
	local ids: { string } = {}
	for id in pairs(TerritoryConfig.Territories or {}) do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, tid in ipairs(ids) do
		local def = TerritoryConfig.Territories[tid]
		if def.IsStarter == true or typeof(def.Position) ~= "Vector3" then
			continue
		end
		local host: Area? = nil
		for _, a in ipairs(out) do
			if a.Territory == nil and inside(a, def.Position.X, def.Position.Z) then
				host = a
				break
			end
		end
		if host then
			host.Territory = def.Id
			host.Bonus = def.Description
		else
			table.insert(out, {
				Id = def.Id,
				Name = tostring(def.DisplayName or def.Id),
				Kind = if def.IsOilRig == true then "rig" else "outpost",
				X = def.Position.X,
				Z = def.Position.Z,
				R = math.max(40, tonumber(def.Radius) or 50),
				Territory = def.Id,
				Bonus = def.Description,
			})
		end
	end
	for _, g in ipairs(OutpostDefenderConfig.Areas or {}) do
		for _, a in ipairs(out) do
			if a.Id == g.Id then
				a.Tier = g.Tier
			end
		end
	end
	cache = out
	return out
end

-- the area containing (x, z), the smallest one first (a camp inside the town rect wins); nil = open ground
function MapAreas.At(x: number, z: number): Area?
	local best: Area? = nil
	for _, a in ipairs(MapAreas.List()) do
		if inside(a, x, z) and (best == nil or a.R < best.R) then
			best = a
		end
	end
	return best
end

function MapAreas.ById(id: string): Area?
	for _, a in ipairs(MapAreas.List()) do
		if a.Id == id then
			return a
		end
	end
	return nil
end

return MapAreas
