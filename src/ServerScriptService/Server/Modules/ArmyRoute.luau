--!strict
--[[
	claude-bud JOB 38 (2026-09-30): the long-route planner for an army march (ArmyPlan). The route is for the BLOCK's lead
	point, not for each soldier: SoldierController still walks every soldier to its formation slot.
	  * The straight line from -> to is cut into legs of at most LegStuds; each leg is a PathfindingService path (agent
	    sized for a soldier). A failed leg is retried with its end point moved sideways (+-24 studs), up to RouteRetries
	    tries in all; then the route fails ("No route": the army holds; there is NO teleport fallback).
	  * One server-wide budget: at most PathBudgetPerSecond computes per second (the caller yields for a token).
	  * The result is a list of flat waypoints (no jump / climb actions: soldiers walk).
	Computing yields: always call it from a spawned thread.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArmyOrdersConfig = require(ReplicatedStorage:WaitForChild("Shared").Configs.ArmyOrdersConfig)

local ArmyRoute = {}

type Computer = (from: Vector3, to: Vector3) -> { Vector3 }?

local tokens = 0
local tokenAt = os.clock()
local stats = { Computes = 0, Failed = 0, Legs = 0 }

local function defaultCompute(from: Vector3, to: Vector3): { Vector3 }?
	local PathfindingService = game:GetService("PathfindingService")
	local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 8 })
	local ok = pcall(function()
		path:ComputeAsync(from, to)
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		return nil
	end
	local out: { Vector3 } = {}
	for _, w in ipairs(path:GetWaypoints()) do
		table.insert(out, w.Position)
	end
	return out
end

local compute: Computer = defaultCompute

-- tests: replace the PathfindingService call
function ArmyRoute._SetComputer(fn: Computer?)
	compute = fn or defaultCompute
end

function ArmyRoute.Stats(): { Computes: number, Failed: number, Legs: number }
	return stats
end

-- wait for one path-compute token (the server-wide budget)
local function takeToken()
	local rate = math.max(0.1, ArmyOrdersConfig.PathBudgetPerSecond)
	while true do
		local now = os.clock()
		tokens = math.min(rate, tokens + (now - tokenAt) * rate)
		tokenAt = now
		if tokens >= 1 then
			tokens -= 1
			return
		end
		task.wait(0.25)
	end
end

-- the leg end points from -> to (each at most LegStuds apart)
function ArmyRoute.Legs(from: Vector3, to: Vector3, legStuds: number?): { Vector3 }
	local leg = math.max(20, legStuds or ArmyOrdersConfig.LegStuds)
	local d = to - from
	local n = math.max(1, math.ceil(Vector3.new(d.X, 0, d.Z).Magnitude / leg))
	local out: { Vector3 } = {}
	for i = 1, n do
		table.insert(out, from + d * (i / n))
	end
	return out
end

--[[ Plan the whole route. Returns the waypoints (ending at `to`), or nil and "no_route" after RouteRetries failures in
	one leg. Yields (the budget + PathfindingService). ]]
function ArmyRoute.Plan(from: Vector3, to: Vector3): ({ Vector3 }?, string?)
	local out: { Vector3 } = {}
	local start = from
	for _, legEnd in ipairs(ArmyRoute.Legs(from, to)) do
		local got: { Vector3 }? = nil
		local tries = 0
		local target = legEnd
		while got == nil and tries < math.max(1, ArmyOrdersConfig.RouteRetries) do
			tries += 1
			takeToken()
			stats.Computes += 1
			got = compute(start, target)
			if got == nil then
				stats.Failed += 1
				-- try the leg end a little to either side (a wall or water on the straight line)
				local dir = target - start
				local side = Vector3.new(-dir.Z, 0, dir.X)
				side = if side.Magnitude > 0 then side.Unit else Vector3.xAxis
				target = legEnd + side * (if tries % 2 == 1 then 24 else -24)
			end
		end
		if got == nil then
			return nil, "no_route"
		end
		stats.Legs += 1
		for _, p in ipairs(got :: { Vector3 }) do
			table.insert(out, p)
		end
		start = out[#out] or target
	end
	return out, nil
end

--[[ Move a lead point along waypoints at `speed` for `dt` (pure; ArmyPlan and the tests call it). Returns the new point,
	the new waypoint index and the direction moved (zero when at the end). ]]
function ArmyRoute.Advance(at: Vector3, route: { Vector3 }, idx: number, speed: number, dt: number): (Vector3, number, Vector3)
	local left = math.max(0, speed * dt)
	local pos = at
	local dir = Vector3.zero
	local i = idx
	while left > 0 and i <= #route do
		local goal = route[i]
		local d = Vector3.new(goal.X - pos.X, 0, goal.Z - pos.Z)
		local len = d.Magnitude
		if len <= left then
			pos = Vector3.new(goal.X, goal.Y, goal.Z)
			left -= len
			i += 1
			if len > 1e-3 then
				dir = d / len
			end
		else
			dir = d / len
			pos = pos + dir * left + Vector3.new(0, (goal.Y - pos.Y) * math.min(1, left / len), 0)
			left = 0
		end
	end
	return pos, i, dir
end

return ArmyRoute
