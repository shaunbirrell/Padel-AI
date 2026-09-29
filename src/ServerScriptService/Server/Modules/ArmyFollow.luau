--!strict
--[[
	v91 (Code Bot, owner 2026-09-28: "the army still despawns while I run; they glitch, walk into each other, then
	despawn; soldiers must not follow me inside my base"). Server-authoritative FOLLOW movement for the squad units of
	SquadOrdersService (ArmyConfig.Follow2; Rollout "all" / "owner" / "off"). SquadOrdersService keeps the unit
	lifecycle and the shooting; this module only decides where each FOLLOW unit walks, how fast, and when one is moved.

	What was wrong before (read from the code, see LATEST-HANDOFF v91):
	  * Units collided with each other (each HumanoidRootPart CanCollide, all in the Default group): at a run they
	    shoved one another, tripped (FallingDown / Ragdoll states) and were flung. A unit flung under the map lost its
	    HumanoidRootPart to FallenPartsDestroyHeight; for everyone except the owner (Rollout.Fix) that unit then stayed
	    in the squad forever as an invisible ghost (SyncArmy only culls a dead or parentless model), so it looked
	    despawned and never came back.
	  * Every unit re-aimed at a slot beside the player each think with no separation, so neighbours chased the same
	    spot when the player turned; the catch-up cap (28, or the owner's WalkSpeed x 1.8) was not always faster
	    than a boosted sprint; recover teleports were owner-only and needed 4 s far + cooldowns.

	What this does (every think, per squad):
	  1. Formation: a wedge behind the player (rank k: back WedgeBack + row x RowBack, side +-(WedgeSide + row x
	     RowSide)), turned by the player's move direction (his facing while he stands, re-aimed only past
	     FacingTurnDeg: no swirl when he turns on the spot). Each unit has its own slot (rank by SquadSlot).
	  2. Separation: a unit within SeparationStuds of another steers apart (added to its goal); units never collide
	     with each other (CollisionGroup "WE_Squad" does not collide with itself); trip / ragdoll states are off.
	  3. Movement: Humanoid:MoveTo straight to the slot while a ray sees it; only when the ray is blocked a path
	     (PathfindingService), computed at most once per PathCooldown per unit and PathBudgetPerSecond per server,
	     kept while its end stays within PathKeepStuds of the slot (hysteresis); a MoveTo is re-issued only when the
	     goal moved ReissueStuds or ReissueSeconds passed (no jitter).
	  4. Catch-up: the unit's speed is the owner's WalkSpeed (Speed Pass / Boost included) or his measured speed,
	     whichever is higher, x MatchMult in its slot, and x CatchUpMult (+ CatchUpPerStud per stud behind) up to
	     max(owner x CatchUpMaxMult, CatchUpMin) when behind: always faster than his sprint. Past FarStuds (FarSeconds),
	     stuck (StuckSeconds with less than StuckStuds moved), under the map (VoidBelowOwner / FallenPartsDestroyHeight
	     margin) or after the owner jumped (teleport / respawn): ONE PivotTo of the same unit to a clear spot behind
	     him (ground ray + a clear line from him: never inside a wall). Never deleted.
	  5. Own base: while the owner is inside his own plot square (BaseService owner, plot bounds with BaseInStuds /
	     BaseOutStuds hysteresis) his units wait spread out just outside his main gate (plot-local z = PlotSize / 2 +
	     BaseWaitOut, x beside the gate lane, never in it), and fall back into the wedge when he comes out.
	Every regroup and every unit removal is logged (rate-limited) with its reason.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local PhysicsService = game:GetService("PhysicsService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArmyConfig = require(Shared.Configs.ArmyConfig)
local AdminConfig = require(Shared.Configs.AdminConfig)
local BaseConfig = require(Shared.Configs.BaseConfig)
local BaseLayoutConfig = require(Shared.Configs.BaseLayoutConfig)
local PlotFrame = require(Shared.Util.PlotFrame)

local ArmyFollow = {}

ArmyFollow.Group = "WE_Squad"

local deps: { [string]: any } = {}
local groupReady = false
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
rayParams.RespectCanCollide = true -- the water sheets and decor are see-through for the rays
local pathBudget = { At = 0, N = 0 }
local logAt: { [string]: number } = {}
ArmyFollow.Stats = { Regroup = 0, Paths = 0, Removed = 0, Died = 0, Void = 0 }

local function cfg(): { [string]: any }
	local c = (ArmyConfig :: any).Follow2
	return if typeof(c) == "table" then c else {}
end

local function num(key: string, default: number): number
	local v = cfg()[key]
	return if typeof(v) == "number" then v else default
end

function ArmyFollow.Bind(d: { [string]: any })
	deps = d
end

-- Rollout: "all" = everyone, "owner" = the playtest owner only, anything else = nobody (the old follow code runs)
function ArmyFollow.LiveFor(userId: any): boolean
	local c = cfg()
	if c.Enabled ~= true then
		return false
	end
	local r = c.Rollout
	if r == "all" then
		return true
	end
	if r == "owner" then
		return AdminConfig.IsPlaytestOwner(userId) == true
	end
	return false
end

local function logLine(key: string, msg: string)
	local now = os.clock()
	local every = num("LogSeconds", 5)
	if now - (logAt[key] or -math.huge) >= every then
		logAt[key] = now
		print("[ArmyFollow] " .. msg)
	end
end
ArmyFollow.Log = logLine

local function ensureGroup()
	if groupReady then
		return
	end
	groupReady = true
	pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered(ArmyFollow.Group) then
			PhysicsService:RegisterCollisionGroup(ArmyFollow.Group)
		end
		PhysicsService:CollisionGroupSetCollidable(ArmyFollow.Group, ArmyFollow.Group, false)
	end)
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDist(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- once per unit: no soldier-vs-soldier collision, no trip / ragdoll, and a log line if it dies or loses its root
local function prepUnit(unit: any)
	if unit._afPrep then
		return
	end
	unit._afPrep = true
	ensureGroup()
	for _, d in ipairs(unit.Model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = ArmyFollow.Group
		end
	end
	unit.Model.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = ArmyFollow.Group
		end
	end)
	local hum: Humanoid = unit.Humanoid
	pcall(function()
		hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false)
	end)
	hum.Died:Connect(function()
		ArmyFollow.Stats.Died += 1
		local r = unit.Root
		logLine("died" .. tostring(unit.OwnerUserId), string.format("unit %s died (owner %s) at y=%.1f", tostring(unit.Id), tostring(unit.OwnerUserId), if r and r.Parent then r.Position.Y else -1))
	end)
	unit.Root.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			ArmyFollow.Stats.Void += 1
			logLine("root" .. tostring(unit.OwnerUserId), string.format("unit %s lost its HumanoidRootPart (fell out of the world) owner %s", tostring(unit.Id), tostring(unit.OwnerUserId)))
		end
	end)
end
ArmyFollow.PrepUnit = prepUnit

function ArmyFollow.LogRemoval(unit: any, reason: string)
	ArmyFollow.Stats.Removed += 1
	logLine("rm" .. tostring(unit.OwnerUserId) .. reason, string.format("unit %s removed: %s (owner %s)", tostring(unit.Id), reason, tostring(unit.OwnerUserId)))
end

-- the excluded instances for every ray: the squad folder and every character
local function refreshRayFilter(extra: Instance?)
	local list: { Instance } = {}
	local folder = deps.Folder and deps.Folder()
	if folder then
		table.insert(list, folder)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	if extra then
		table.insert(list, extra)
	end
	rayParams.FilterDescendantsInstances = list
end

local function clearLine(a: Vector3, b: Vector3): boolean
	local up = Vector3.new(0, 1.2, 0)
	local from, to = a + up, b + up
	return Workspace:Raycast(from, to - from, rayParams) == nil
end

local function groundAt(p: Vector3, fromY: number): Vector3?
	local top = Vector3.new(p.X, fromY + 12, p.Z)
	local hit = Workspace:Raycast(top, Vector3.new(0, -40, 0), rayParams)
	return if hit then hit.Position else nil
end

-- ── the owner's motion and the squad plan (once per think per squad) ──────────────────────────────────────────────
local function ownerWalkSpeed(root: BasePart): number
	local hum = root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
	return if hum then hum.WalkSpeed else 16
end

-- claude-bud: Follow2.Tidy (owner-only first): hold outside the plot, neat wait rows, fixed seats, no crossing
local function tidyCfg(): { [string]: any }
	local t = cfg().Tidy
	return if typeof(t) == "table" then t else {}
end

local function tnum(key: string, default: number): number
	local v = tidyCfg()[key]
	return if typeof(v) == "number" then v else default
end

local function tidyLive(player: Player?): boolean
	if player == nil then
		return false
	end
	local r = tidyCfg().Rollout
	return r == "all" or (r == "owner" and AdminConfig.IsPlaytestOwner(player.UserId) == true)
end
ArmyFollow.TidyLive = tidyLive

-- his own plot id (nil: none) and a point's plot-local position in it
local function ownPlotId(player: Player?): number?
	if player == nil or deps.OwnPlotId == nil then
		return nil
	end
	local id = deps.OwnPlotId(player)
	return if typeof(id) == "number" then id else nil
end

local function plotLocal(id: number, pos: Vector3): Vector3?
	local c = PlotFrame.PlotPosition(id)
	if c == nil then
		return nil
	end
	return PlotFrame.PlotCFrame(c):PointToObjectSpace(pos)
end

-- true when `pos` is inside plot `id` grown by `pad` studs
local function inPlot(id: number, pos: Vector3, pad: number): boolean
	local lp = plotLocal(id, pos)
	if lp == nil then
		return false
	end
	local half = BaseConfig.PlotSize.X * 0.5 + pad
	return math.abs(lp.X) <= half and math.abs(lp.Z) <= half
end

local function ownPlotInside(st: any, player: Player?, pos: Vector3): number?
	local id = ownPlotId(player)
	if id == nil then
		return nil
	end
	local lp = plotLocal(id, pos)
	if lp == nil then
		return nil
	end
	local half = BaseConfig.PlotSize.X * 0.5
	local edge = math.max(math.abs(lp.X), math.abs(lp.Z))
	local inside: boolean
	if st._afTidy then
		-- claude-bud: hold as he reaches his edge from outside (the wedge behind him never follows him in)
		inside = if st._afInBase then edge <= half + tnum("HoldReleaseStuds", 10) else edge <= half + tnum("HoldApproachStuds", 6)
	else
		inside = if st._afInBase then edge <= half + num("BaseOutStuds", 2) else edge <= half - num("BaseInStuds", 4)
	end
	return if inside then id else nil
end

-- claude-bud: tidy wait spot of seat `rank`: rows on both sides of the gate lane, facing out (plot-local +Z)
local function tidyWaitSpot(plotId: number, rank: number): (Vector3, Vector3)
	local half = BaseConfig.PlotSize.X * 0.5
	local gateHalf = (tonumber(BaseLayoutConfig.MainGateWidth) or 14) * 0.5
	local side = if rank % 2 == 1 then -1 else 1
	local j = math.floor((rank - 1) / 2) -- index on its side
	local perRow = math.max(1, math.floor(tnum("PerRow", 4)))
	local col = j % perRow
	local row = math.floor(j / perRow)
	local x = side * (gateHalf + tnum("WaitGap", 5) + col * tnum("ColSpacing", 4))
	local z = half + tnum("WaitOut", 14) + row * tnum("RowSpacing", 4)
	local p = PlotFrame.LocalToWorld(plotId, x, z)
	local out = PlotFrame.LocalToWorld(plotId, x, z + 1) - p
	out = Vector3.new(out.X, 0, out.Z)
	return p, if out.Magnitude > 1e-3 then out.Unit else Vector3.new(0, 0, 1)
end

local function waitSpot(plotId: number, rank: number): Vector3
	local half = BaseConfig.PlotSize.X * 0.5
	local gateHalf = (tonumber(BaseLayoutConfig.MainGateWidth) or 14) * 0.5
	local side = if rank % 2 == 1 then -1 else 1
	local k = math.floor((rank - 1) / 2)
	local row = k % 2
	local x = side * (gateHalf + num("BaseWaitGap", 5) + math.floor(k / 2) * num("BaseWaitSpacing", 4) + row * 2)
	local z = half + num("BaseWaitOut", 12) + row * 4
	return PlotFrame.LocalToWorld(plotId, x, z)
end

local function plan(st: any, player: Player?, root: BasePart, units: { any }, now: number)
	if st._afPlanAt == now then
		return
	end
	st._afPlanAt = now
	local pos = root.Position
	local lastPos: Vector3? = st._afLastPos
	local dt = now - (st._afLastAt or now)
	local vel = Vector3.zero
	local jumped = false
	if lastPos and dt > 0.05 and dt < 2 then
		vel = flat(pos - lastPos) / dt
		if vel.Magnitude > num("OwnerJumpSpeed", 60) then
			jumped = true
			vel = Vector3.zero
		end
	end
	st._afLastPos = pos
	st._afLastAt = now
	st._afJumped = jumped
	local hum = root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
	st._afSeated = hum ~= nil and (hum.Sit or hum.SeatPart ~= nil)
	local speed = vel.Magnitude
	st._afSpeed = (st._afSpeed or 0) * 0.4 + speed * 0.6
	st._afVel = vel
	st._afWalk = ownerWalkSpeed(root)
	-- facing: his move direction; standing, his look (re-aimed only past FacingTurnDeg)
	local want: Vector3 = if speed >= 2 then vel.Unit else flat(root.CFrame.LookVector)
	if want.Magnitude < 1e-3 then
		want = Vector3.new(0, 0, -1)
	end
	want = want.Unit
	local cur: Vector3? = st._afDir
	if cur == nil or speed >= 2 or cur:Dot(want) < math.cos(math.rad(num("FacingTurnDeg", 35))) then
		st._afDir = want
	end
	-- rank by SquadSlot (stable)
	local order = table.clone(units)
	table.sort(order, function(a, b)
		return (a.Slot or 0) < (b.Slot or 0)
	end)
	st._afTidy = tidyLive(player)
	if st._afTidy then
		-- claude-bud: fixed seats for life; a dead / gone unit frees its seat, nobody else moves up
		local taken: { [number]: any } = {}
		for _, u in ipairs(order) do
			local s = u._afSeat
			if typeof(s) == "number" and taken[s] == nil then
				taken[s] = u
			else
				u._afSeat = nil
			end
		end
		for _, u in ipairs(order) do
			if u._afSeat == nil then
				local s = 1
				while taken[s] ~= nil do
					s += 1
				end
				u._afSeat = s
				taken[s] = u
			end
			u._afRank = u._afSeat
		end
		st._afSeatMap = taken
	else
		for i, u in ipairs(order) do
			u._afRank = i
		end
		st._afSeatMap = nil
	end
	-- own base
	local plotId = ownPlotInside(st, player, pos)
	local wasIn = st._afInBase
	st._afInBase = plotId ~= nil
	st._afPlot = plotId
	st._afOwnPlot = ownPlotId(player)
	if wasIn and not st._afInBase then
		st._afLeftBaseAt = now -- claude-bud: the walk-back grace (no far / stuck teleport)
	end
	if st._afInBase ~= wasIn and player then
		logLine("base" .. tostring(player.UserId), string.format("owner %d %s his base: army %s", player.UserId, if plotId then "entered" else "left", if plotId then "waits at the gate" else "follows"))
	end
	-- claude-bud: wedge row pairs keep their world sides when he turns round (no crossing through each other)
	if st._afTidy and not st._afInBase and st._afSeatMap then
		local dir: Vector3 = st._afDir or Vector3.new(0, 0, -1)
		local right = Vector3.new(-dir.Z, 0, dir.X)
		st._afFlip = st._afFlip or {}
		local hyst = tnum("FlipHysteresisStuds", 1.5)
		for s, u in pairs(st._afSeatMap) do
			if s % 2 == 1 then
				local mate = st._afSeatMap[s + 1]
				local row = (s + 1) / 2
				if mate and u.Root and u.Root.Parent and mate.Root and mate.Root.Parent then
					-- seat s is the left one (side -1): flip when it stands clearly right of its mate
					local diff = (u.Root.Position - mate.Root.Position):Dot(right)
					if diff > hyst then
						st._afFlip[row] = true
					elseif diff < -hyst then
						st._afFlip[row] = false
					end
				else
					st._afFlip[row] = nil
				end
			end
		end
	end
	refreshRayFilter(nil)
end

local function slotPoint(st: any, root: BasePart, rank: number): Vector3
	if st._afInBase and st._afPlot then
		local w = waitSpot(st._afPlot, rank)
		if st._afTidy then
			w = (tidyWaitSpot(st._afPlot, rank)) -- claude-bud: neat rows facing out
		end
		return Vector3.new(w.X, root.Position.Y, w.Z)
	end
	local dir: Vector3 = st._afDir or Vector3.new(0, 0, -1)
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local row = math.ceil(rank / 2)
	local side = if rank % 2 == 1 then -1 else 1
	local back = num("WedgeBack", 3) + row * num("RowBack", 3)
	local lat = side * (num("WedgeSide", 2.5) + row * num("RowSide", 2.5))
	if st._afTidy then
		-- claude-bud: wider rows (never inside each other) and the row pair's kept world sides (no crossing)
		if st._afFlip and st._afFlip[row] == true then
			side = -side
		end
		back = num("WedgeBack", 3) + row * tnum("RowBack", 4)
		lat = side * (num("WedgeSide", 2.5) + row * tnum("RowSide", 3))
	end
	local lead = (st._afVel or Vector3.zero) * num("LeadSeconds", 0.3)
	local cap = num("LeadMaxStuds", 5)
	if lead.Magnitude > cap then
		lead = lead.Unit * cap
	end
	return root.Position - dir * back + right * lat + lead
end
ArmyFollow.SlotPoint = slotPoint

-- ── teleport (regroup): one PivotTo of the same unit, to a clear spot behind the owner ─────────────────────────
local function spotFor(st: any, root: BasePart, rank: number): CFrame?
	local dir: Vector3 = st._afDir or Vector3.new(0, 0, -1)
	local cands = { slotPoint(st, root, rank) }
	if not st._afInBase then
		for _, b in ipairs({ 8, 12, 5, 16 }) do
			table.insert(cands, root.Position - dir * b)
		end
	end
	for _, c in ipairs(cands) do
		local g = groundAt(c, root.Position.Y)
		if g and math.abs(g.Y - root.Position.Y) < 14 and (st._afInBase or clearLine(root.Position, g + Vector3.new(0, 1.8, 0))) then
			local p = g + Vector3.new(0, num("StandHeight", 3.2), 0)
			return CFrame.lookAt(p, p + dir)
		end
	end
	return nil
end

local function regroup(st: any, unit: any, root: BasePart, now: number, why: string): boolean
	if now < (unit._afTpAt or -math.huge) then
		return false
	end
	unit._afTpAt = now + num("TeleportCooldown", 2.5)
	local cf = spotFor(st, root, unit._afRank or 1)
	if cf == nil then
		logLine("nospot" .. tostring(unit.OwnerUserId), string.format("no clear regroup spot for unit %s (%s): it keeps walking", tostring(unit.Id), why))
		return false
	end
	unit.Model:PivotTo(cf)
	unit.Root.AssemblyLinearVelocity = Vector3.zero
	unit.Root.AssemblyAngularVelocity = Vector3.zero
	unit.Humanoid:MoveTo(cf.Position)
	unit._afPath = nil
	unit._afMoveGoal = cf.Position
	unit._afMoveAt = now
	unit._afProgPos = cf.Position
	unit._afProgAt = now
	unit._afFarSince = nil
	ArmyFollow.Stats.Regroup += 1
	logLine("rg" .. tostring(unit.OwnerUserId) .. why, string.format("regroup unit %s (%s) owner %s", tostring(unit.Id), why, tostring(unit.OwnerUserId)))
	return true
end

local function setSpeed(unit: any, s: number)
	local hum: Humanoid = unit.Humanoid
	if math.abs(hum.WalkSpeed - s) >= 1 then
		hum.WalkSpeed = s
	end
end

local function moveTo(unit: any, goal: Vector3, now: number)
	local last: Vector3? = unit._afMoveGoal
	if last == nil or flatDist(last, goal) >= num("ReissueStuds", 1.5) or now - (unit._afMoveAt or 0) >= num("ReissueSeconds", 5) then
		unit.Humanoid:MoveTo(goal)
		unit._afMoveGoal = goal
		unit._afMoveAt = now
	end
end

local function requestPath(unit: any, from: Vector3, to: Vector3, now: number)
	if unit._afPathBusy or now < (unit._afPathAt or -math.huge) then
		return
	end
	if now - pathBudget.At >= 1 then
		pathBudget.At = now
		pathBudget.N = 0
	end
	if pathBudget.N >= num("PathBudgetPerSecond", 8) then
		return
	end
	pathBudget.N += 1
	unit._afPathBusy = true
	unit._afPathAt = now + num("PathCooldown", 1.5)
	ArmyFollow.Stats.Paths += 1
	task.spawn(function()
		local ok, path = pcall(function()
			local p = PathfindingService:CreatePath({ AgentRadius = 1.5, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 6 })
			p:ComputeAsync(from, to)
			return p
		end)
		unit._afPathBusy = false
		if ok and path and path.Status == Enum.PathStatus.Success then
			local wps = path:GetWaypoints()
			unit._afPath = { Points = wps, I = math.min(2, #wps), Goal = to }
		else
			unit._afPath = nil
			unit._afPathFail = os.clock()
		end
	end)
end

--[[ one FOLLOW unit, one think. Returns nothing; SquadOrdersService calls it only for a live owner in FOLLOW, on foot
	or seated, after its escort shot (the escort's own walk runs only while the owner stands near a hostile). ]]
function ArmyFollow.Unit(player: Player?, st: any, unit: any, root: BasePart, now: number)
	if not unit.Alive or unit.Humanoid.Health <= 0 or unit.Root.Parent == nil then
		return
	end
	prepUnit(unit)
	plan(st, player, root, st.Units, now)
	local pos = unit.Root.Position
	local rank = unit._afRank or 1
	local slot = slotPoint(st, root, rank)
	local d = flatDist(pos, slot)
	local ownerD = flatDist(pos, root.Position)
	local seatedFast = st._afSeated and (st._afSpeed or 0) > num("VehicleDeferSpeed", 20)

	-- regroup triggers: under the map, the owner jumped, far, stuck (never while he drives fast)
	local fph = Workspace.FallenPartsDestroyHeight
	if pos.Y < root.Position.Y - num("VoidBelowOwner", 60) or pos.Y < fph + num("VoidMargin", 80) then
		if regroup(st, unit, root, now, "void") then
			return
		end
	end
	-- claude-bud (Tidy): just out of his base, they walk back into the wedge (no far / stuck teleport for a grace spell)
	local walkBack = st._afTidy and not st._afInBase and now - (st._afLeftBaseAt or -math.huge) < tnum("LeaveGraceSeconds", 8)
	if not seatedFast and not walkBack then
		if st._afJumped and ownerD > num("JumpRegroupStuds", 40) and regroup(st, unit, root, now, "owner-jump") then
			return
		end
		local far = if st._afInBase then num("BaseFarStuds", 140) else num("FarStuds", 70)
		if d > far then
			unit._afFarSince = unit._afFarSince or now
			if now - unit._afFarSince >= num("FarSeconds", 1) and regroup(st, unit, root, now, "far") then
				return
			end
		else
			unit._afFarSince = nil
		end
		-- stuck: it wants to move (goal further than StuckGoalStuds) but has moved less than StuckStuds in StuckSeconds
		local pp: Vector3? = unit._afProgPos
		if pp == nil or d <= num("StuckGoalStuds", 6) then
			unit._afProgPos = pos
			unit._afProgAt = now
		elseif flatDist(pos, pp) >= num("StuckStuds", 3) then
			unit._afProgPos = pos
			unit._afProgAt = now
		elseif now - (unit._afProgAt or now) >= num("StuckSeconds", 3) and d > num("StuckMinStuds", 10) then
			if regroup(st, unit, root, now, "stuck") then
				return
			end
		end
	else
		unit._afFarSince = nil
		unit._afProgPos = nil
	end

	-- separation: steer away from any squad-mate closer than SeparationStuds
	local sep = num("SeparationStuds", 3.5)
	local push = Vector3.zero
	for _, o in ipairs(st.Units) do
		if o ~= unit and o.Alive and o.Root and o.Root.Parent then
			local off = flat(pos - o.Root.Position)
			local m = off.Magnitude
			if m < sep then
				push += (if m > 1e-3 then off / m else Vector3.new(((rank % 2) * 2 - 1), 0, 0)) * (sep - m) / sep
			end
		end
	end
	local goal = slot + push * num("SeparationGain", 3)
	-- claude-bud (Tidy): a unit outside his plot never gets a goal inside it (it waits at its gate spot instead)
	local ownPlot: number? = if st._afTidy then st._afOwnPlot else nil
	local unitOutside = ownPlot ~= nil and not inPlot(ownPlot, pos, 0)
	local pad = tnum("PlotPadStuds", 2)
	local function keepOut(p: Vector3): Vector3
		if unitOutside and ownPlot and inPlot(ownPlot, p, pad) then
			local w = tidyWaitSpot(ownPlot, rank)
			return Vector3.new(w.X, p.Y, w.Z)
		end
		return p
	end
	goal = keepOut(goal)

	-- speed: never slower than his sprint when behind
	local ownerPace = math.max(st._afWalk or 16, st._afSpeed or 0)
	if st._afSeated then
		ownerPace = math.max(16, math.min(st._afSpeed or 0, num("CatchUpMin", 34)))
	end
	local base = (tonumber((deps.UnitWalkSpeed or function() return 14 end)()) or 14)
	local speed: number
	if st._afInBase then
		speed = base * 1.25
	elseif d > num("CatchUpStartStuds", 5) then
		local cap = math.max(ownerPace * num("CatchUpMaxMult", 1.8), num("CatchUpMin", 34))
		speed = math.min(cap, ownerPace * num("CatchUpMult", 1.35) + (d - num("CatchUpStartStuds", 5)) * num("CatchUpPerStud", 0.6))
	else
		speed = math.max(base, ownerPace * num("MatchMult", 1.08))
	end
	speed = math.clamp(speed, 8, num("MaxSpeed", 50))
	setSpeed(unit, speed)

	-- claude-bud (Tidy): at its gate wait spot it stands still facing out, whatever he does inside
	if st._afTidy and st._afInBase and st._afPlot and flatDist(pos, goal) <= num("ArriveStuds", 2) then
		if not unit._afStand then
			unit._afStand = true
			unit.Humanoid:MoveTo(pos)
			unit._afMoveGoal = pos
			unit._afMoveAt = now
			local _, out = tidyWaitSpot(st._afPlot, rank)
			unit.Model:PivotTo(CFrame.lookAt(unit.Root.Position, unit.Root.Position + out)) -- turn on the spot only
		end
		unit._afPath = nil
		return
	end
	-- arrive: stand in the slot while the owner stands
	if d <= num("ArriveStuds", 2) and (st._afSpeed or 0) < 1 and push.Magnitude < 0.05 then
		if not unit._afStand then
			unit._afStand = true
			unit.Humanoid:MoveTo(pos)
			unit._afMoveGoal = pos
			unit._afMoveAt = now
		end
		unit._afPath = nil
		return
	end
	unit._afStand = false

	-- movement: straight while it sees the slot, a throttled path only when blocked
	if clearLine(pos, goal) then
		unit._afPath = nil
		moveTo(unit, goal, now)
		return
	end
	local path = unit._afPath
	if path and flatDist(path.Goal, goal) <= num("PathKeepStuds", 8) and path.I <= #path.Points then
		local wp = path.Points[path.I]
		if flatDist(pos, wp.Position) < 3 then
			path.I += 1
			wp = path.Points[path.I]
		end
		if wp then
			if wp.Action == Enum.PathWaypointAction.Jump then
				unit.Humanoid.Jump = true
			end
			moveTo(unit, keepOut(wp.Position), now)
			return
		end
	end
	requestPath(unit, pos, goal, now)
	-- while the path is computed (or none exists): walk toward the owner's trail point = the owner himself
	moveTo(unit, if st._afInBase then goal else keepOut(root.Position - (st._afDir or Vector3.zero) * 4), now)
end

return ArmyFollow
