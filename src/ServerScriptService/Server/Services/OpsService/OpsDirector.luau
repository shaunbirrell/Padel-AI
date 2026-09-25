--!strict
--[[
	OpsDirector — which BIG job sites are open (W3 step 2 Phase B, lane O; activities §2.1, contract §4.6). SERVER ONLY.
	It replaces the roadmap's EventDirectorService (spec §1.9): one authority for what is open and announced.

	* Director.BigOpenMax (3) big sites are open at once: every live Pinned site (the bank) plus rotating slots.
	* Small sites (checkpoints, caches, camps, forts, rigs) are never closed here.
	* Every Director.TickSeconds: an open rotating site that nobody entered for IdleRotateSeconds (and is not Active)
	  closes; a free slot opens the closed site with the best score:
	      score = sum over players of 1 / (1 + d(player's plot, site) / DistScale) + AgeWeight x (seconds since it last
	      closed) / AgeUnitSeconds
	* When a big site opens, "<Title> is open" goes to players whose own plot is within OpenToastRadius, at most once
	  per OpenToastGapSeconds each, never while they were hit in the last SkipToastIfHitSeconds.
	* Director.Events (Supply Run, Vault Window) is Phase C and stays off.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local OpsConfig = require(Shared.Configs.OpsConfig)
local PlotFrame = require(Shared.Util.PlotFrame)

local D = OpsConfig.Director

local OpsDirector = {}

local ctx: any = nil

function OpsDirector.Init(context: any)
	ctx = context
end

local function rotating(rt: any): boolean
	local d: OpsConfig.SiteDef = rt.Def
	return d.Big and d.Pinned ~= true
end
OpsDirector.Rotating = rotating

function OpsDirector.Slots(sites: { any }): number
	local pinned = 0
	for _, rt in ipairs(sites) do
		if rt.Live and (rt.Def :: OpsConfig.SiteDef).Big and (rt.Def :: OpsConfig.SiteDef).Pinned == true then
			pinned += 1
		end
	end
	return math.max(0, D.BigOpenMax - pinned)
end

function OpsDirector.Score(rt: any, nowC: number): number
	local score = 0
	local pos: Vector3 = rt.Target.Position
	for _, p in ipairs(ctx.PlayerList) do
		local plotId = ctx.PlotOf(p)
		local plotPos = if plotId then PlotFrame.PlotPosition(plotId) else nil
		if plotPos then
			local dx, dz = plotPos.X - pos.X, plotPos.Z - pos.Z
			score += 1 / (1 + math.sqrt(dx * dx + dz * dz) / D.DistScale)
		end
	end
	local age = nowC - (rt.ClosedAt or (nowC - D.AgeUnitSeconds))
	return score + D.AgeWeight * math.max(0, age) / D.AgeUnitSeconds
end

-- "<Title> is open" to players whose plot is near (throttled per player; never while being shot at)
local function announce(rt: any, nowC: number)
	local d: OpsConfig.SiteDef = rt.Def
	local pos: Vector3 = rt.Target.Position
	for _, p in ipairs(ctx.PlayerList) do
		local plotId = ctx.PlotOf(p)
		local plotPos = if plotId then PlotFrame.PlotPosition(plotId) else nil
		if plotPos and not ctx.Zones.HitWithin(p, nowC, D.SkipToastIfHitSeconds) then
			local dx, dz = plotPos.X - pos.X, plotPos.Z - pos.Z
			if dx * dx + dz * dz <= D.OpenToastRadius * D.OpenToastRadius then
				ctx.NotifyThrottled(p, string.format(OpsConfig.Text.Toast.Open, d.Title), "Info", D.OpenToastGapSeconds, "ops_open")
			end
		end
	end
end

function OpsDirector.Close(rt: any, nowC: number)
	rt.ClosedAt = nowC
	ctx.Garrison.Sleep(rt)
	ctx.Sites.DropPrompts(rt)
	ctx.SetState(rt, "Closed")
end

function OpsDirector.Open(rt: any, nowC: number, quiet: boolean?)
	rt.LastEntered = nowC
	ctx.SetState(rt, if rt.Need > 0 then "Dormant" else "Open")
	ctx.Kinds.Reset(rt)
	ctx.Rewards.Log(ctx.Events.OPS_OPEN, nil, { site = rt.Id })
	if not quiet then
		announce(rt, nowC)
	end
end

--[[ Every Director.TickSeconds (and once when the sites resolve). ]]
function OpsDirector.Tick(sites: { any }, nowC: number, quiet: boolean?)
	local slots = OpsDirector.Slots(sites)
	local open = 0
	local closed: { any } = {}
	for _, rt in ipairs(sites) do
		if rt.Live and rotating(rt) then
			if rt.State == "Closed" then
				table.insert(closed, rt)
			else
				local idle = nowC - (rt.LastEntered or nowC) >= D.IdleRotateSeconds
				if idle and (rt.State == "Open" or rt.State == "Dormant" or rt.State == "Quiet") then
					OpsDirector.Close(rt, nowC)
					table.insert(closed, rt)
				else
					open += 1
				end
			end
		end
	end
	if open >= slots or #closed == 0 then
		return
	end
	local scored: { { Rt: any, S: number } } = {}
	for _, rt in ipairs(closed) do
		table.insert(scored, { Rt = rt, S = OpsDirector.Score(rt, nowC) })
	end
	table.sort(scored, function(a, b)
		if a.S ~= b.S then
			return a.S > b.S
		end
		return a.Rt.Order < b.Rt.Order
	end)
	for _, e in ipairs(scored) do
		if open >= slots then
			break
		end
		-- a site that just rotated out waits one tick before it may come back (unless nothing else can open)
		if e.Rt.ClosedAt ~= nowC or #scored <= slots - open then
			OpsDirector.Open(e.Rt, nowC, quiet)
			open += 1
		end
	end
end

return OpsDirector
