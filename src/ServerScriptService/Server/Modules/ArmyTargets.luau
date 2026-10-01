--!strict
--[[
	Code Bot (army command bug, 2026-10-01): what a SEND may target, resolved ON THE SERVER from the id the map sends
	(the client never sends a position: it cannot point the army anywhere it likes).
	  "A:<areaId>"  a world-map area (Shared/Util/MapAreas: WorldConfig POIs + the TerritoryConfig outpost inside it),
	                e.g. "A:Town" = Crossroads Town (its objective: the Central Plaza outpost, radius 70)
	  "S:<siteId>"  a named site (WorldSitesConfig)
	  "B:<plotId>"  / a plain number: another player's base (ArmyPlan.StartSend: the fairness verdict, the gate siege)
	THE APPROACH POINT (the army's destination, never the objective's centre): ArmyOrdersConfig.Approach[id] when set
	(a list: Vector3s), else the points ApproachExtraStuds outside the objective's radius where a road (WaterConfig
	RoadEnds centre lines) enters it, else the four compass points on that ring. The one nearest the army is used, so a
	block never walks through the base it was sent to. Grounded by one raycast (Workspace) when it hits something.
	Pure apart from that raycast; the tests call Resolve directly.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArmyOrdersConfig = require(Shared.Configs.ArmyOrdersConfig) :: any
local MapAreas = require(Shared.Util.MapAreas)
local TerritoryConfig = require(Shared.Configs.TerritoryConfig) :: any
local WorldSitesConfig = require(Shared.Configs.WorldSitesConfig) :: any
local WaterConfig = require(Shared.Configs.WaterConfig) :: any

local ArmyTargets = {}

export type Target = {
	Key: string, -- "A:Town"
	Kind: string, -- "Area" | "Site" | "Base"
	Id: string,
	Name: string,
	Centre: Vector3, -- the objective (outpost / site centre)
	Radius: number, -- the objective's radius (the fight area is Radius + Travel.EngageExtraStuds)
	Approaches: { Vector3 },
	PlotId: number?,
	Territory: string?,
}

local function travelCfg(): { [string]: any }
	local t = ArmyOrdersConfig.Travel
	return if typeof(t) == "table" then t else {}
end

-- the road centre lines (RoadX<x>: along Z at x; RoadZ<z>: along X at z)
local function roads(): { { Axis: string, At: number, Min: number, Max: number } }
	local out = {}
	for key, e in pairs(WaterConfig.RoadEnds or {}) do
		local axis, at = string.match(key, "^Road([XZ])(%-?%d+)$")
		if axis and at and typeof(e) == "table" then
			table.insert(out, { Axis = axis, At = tonumber(at) :: number, Min = tonumber(e.Min) or -math.huge, Max = tonumber(e.Max) or math.huge })
		end
	end
	table.sort(out, function(a, b)
		return a.Axis .. tostring(a.At) < b.Axis .. tostring(b.At)
	end)
	return out
end

-- the default approach points round an objective: road entries first, else the compass ring
function ArmyTargets.ApproachRing(centre: Vector3, radius: number): { Vector3 }
	local ring = radius + (tonumber(travelCfg().ApproachExtraStuds) or 30)
	local out: { Vector3 } = {}
	for _, r in ipairs(roads()) do
		if r.Axis == "X" and math.abs(r.At - centre.X) < radius then
			-- a road along Z at x = At: it enters the ring at z = centre.Z +- ring
			for _, s in ipairs({ -1, 1 }) do
				local z = centre.Z + s * ring
				if z >= r.Min and z <= r.Max then
					table.insert(out, Vector3.new(r.At, centre.Y, z))
				end
			end
		elseif r.Axis == "Z" and math.abs(r.At - centre.Z) < radius then
			for _, s in ipairs({ -1, 1 }) do
				local x = centre.X + s * ring
				if x >= r.Min and x <= r.Max then
					table.insert(out, Vector3.new(x, centre.Y, r.At))
				end
			end
		end
	end
	if #out == 0 then
		for _, d in ipairs({ Vector3.new(0, 0, -1), Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0) }) do
			table.insert(out, centre + d * ring)
		end
	end
	return out
end

local function configured(key: string): { Vector3 }?
	local A = ArmyOrdersConfig.Approach
	local list = if typeof(A) == "table" then A[key] else nil
	if typeof(list) == "Vector3" then
		return { list }
	end
	if typeof(list) == "table" and #list > 0 then
		return list
	end
	return nil
end

local function ground(p: Vector3): Vector3
	local ok, hit = pcall(function(): any
		return Workspace:Raycast(Vector3.new(p.X, p.Y + 200, p.Z), Vector3.new(0, -400, 0))
	end)
	if ok and hit and typeof(hit.Position) == "Vector3" then
		return Vector3.new(p.X, hit.Position.Y + 3, p.Z)
	end
	return p
end

-- the approach point of a target nearest to `from` (the army's block centre)
function ArmyTargets.ApproachFor(t: Target, from: Vector3?): Vector3
	local best, bestD = t.Approaches[1], math.huge
	if from then
		for _, a in ipairs(t.Approaches) do
			local d = Vector3.new(a.X - from.X, 0, a.Z - from.Z).Magnitude
			if d < bestD then
				best, bestD = a, d
			end
		end
	end
	return ground(best or t.Centre)
end

--[[ (target, nil) or (nil, reason): "BadTarget" (not a target id), "UnknownTarget" (no such area / site). A base id
	comes back as Kind "Base" with its PlotId: ArmyPlan.StartSend checks it (owner online, fairness, his own base). ]]
function ArmyTargets.Resolve(raw: any): (Target?, string?)
	if typeof(raw) == "number" then
		if raw ~= raw or raw <= 0 or raw % 1 ~= 0 then
			return nil, "BadTarget"
		end
		return { Key = "B:" .. tostring(raw), Kind = "Base", Id = tostring(raw), Name = "base " .. tostring(raw), Centre = Vector3.zero, Radius = 0, Approaches = {}, PlotId = raw }, nil
	end
	if typeof(raw) ~= "string" or #raw > 40 then
		return nil, "BadTarget"
	end
	local kind, id = string.match(raw, "^(%a):([%w_]+)$")
	if kind == nil or id == nil then
		return nil, "BadTarget"
	end
	if kind == "B" then
		local n = tonumber(id)
		if n == nil then
			return nil, "BadTarget"
		end
		return ArmyTargets.Resolve(n)
	elseif kind == "A" then
		local a = MapAreas.ById(id)
		if a == nil then
			return nil, "UnknownTarget"
		end
		local centre = Vector3.new(a.X, 1, a.Z)
		local radius = math.min(a.R, tonumber(travelCfg().AreaRadiusCap) or 80)
		local terr = if a.Territory then TerritoryConfig.Territories[a.Territory] else nil
		if typeof(terr) == "table" and typeof(terr.Position) == "Vector3" then
			centre = terr.Position
			radius = tonumber(terr.Radius) or radius
		end
		local key = "A:" .. a.Id
		return {
			Key = key, Kind = "Area", Id = a.Id, Name = a.Name, Centre = centre, Radius = radius,
			Approaches = configured(key) or ArmyTargets.ApproachRing(centre, radius), Territory = a.Territory,
		}, nil
	elseif kind == "S" then
		for _, s in ipairs(WorldSitesConfig.Sites or {}) do
			if s.Id == id then
				local k = (WorldSitesConfig.Kinds or {})[s.Kind]
				local radius = if typeof(k) == "table" then tonumber(k.R) or 40 else 40
				local centre = Vector3.new(s.X, 1, s.Z)
				local key = "S:" .. s.Id
				return { Key = key, Kind = "Site", Id = s.Id, Name = tostring(s.Name or s.Id), Centre = centre, Radius = radius,
					Approaches = configured(key) or ArmyTargets.ApproachRing(centre, radius) }, nil
			end
		end
		return nil, "UnknownTarget"
	end
	return nil, "BadTarget"
end

return ArmyTargets
