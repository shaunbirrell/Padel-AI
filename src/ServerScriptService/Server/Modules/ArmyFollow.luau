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

	v99 (Code Bot, owner 2026-09-29: "they fall far behind, vanish, reappear, the whole group suddenly catches up, they
	bunch into a blob; worst when sprinting / round buildings"). Root causes found in this module + SquadOrdersService:
	  * TWO controllers on one Humanoid: the escort fight (SquadOrdersService.escortUnit) moves a unit with its own
	    MoveTo while ArmyFollow sleeps, but ArmyFollow's throttle / stuck / far bookkeeping stayed from before the
	    fight: after it, the stale goal was never re-sent (the unit stood still up to ReissueSeconds) and the stale
	    stuck window (3 s old) fired at once = a TELEPORT back into the wedge (the snap-back). Same after HOLD /
	    ATTACK / RETREAT, the owner's death or a vehicle ride. Now: ONE owner per unit. ArmyFollow.Release(unit)
	    whenever another controller takes it; a think gap > ThinkGapReset re-acquires with fresh state.
	  * The yaw had two owners too: Humanoid.AutoRotate against the NPCFaceGyro that stayed at its spawn / last shot
	    yaw. The unit (and its client escort file, a rigid 7-12 stud arm, RigConfig.Escort.Offsets) swung about =
	    the blob / overlap on turns. Now ArmyFollow drives the gyro (AutoRotate off while it controls the unit).
	  * Blocked line (round buildings): every unit waiting for its path walked to ONE shared point (4 studs behind
	    the owner) = the blob; a path was dropped as soon as its end was 8 studs off the slot (every think at a
	    run) and a waypoint passed between thinks was walked back to. Now each unit walks to its own point, a path
	    is kept PathKeepSeconds / PathKeepStuds, passed waypoints are skipped.
	  * Formation direction snapped to the raw velocity every think (a sharp turn swung the whole wedge 180 degrees
	    at once). Now slots are the player's root CFrame (facing) turned at most TurnRateDeg per second,
	    CFrame:PointToWorldSpace of each unit's own offset.
	  * Slots: rank = index for non-Tidy owners (a death re-ranked everyone). Now every squad keeps persistent
	    unique seats; they are compacted only after the army size changed (SeatCompactSeconds).
	  * Regroup was quick (FarStuds 70 from the slot for 1 s; stuck 3 s) and landed IN the slot, 7 studs behind
	    him, in the phone camera's view. Now: far = FarStuds 100 for FarSeconds 3; stuck is staged (repath at
	    StuckSeconds, an alternate point at StuckAltSeconds, the reposition only at StuckTeleportSeconds); the spot
	    is its own slot pushed RegroupBehindStuds further back (behind the camera), never within
	    RegroupMinOwnerStuds of him. A seated owner (vehicle) is never an "owner jump".
	  * Speed stepped from x1.08 to x1.35 at CatchUpStartStuds (a lurch); now it ramps over CatchUpRampStuds and
	    changes at most SpeedUpPerThink / SpeedDownPerThink per think.
	  * Collision group "ArmyNPCs" (was WE_Squad, set on the first FOLLOW think only): registered at Init, set at
	    spawn for every order; never collides with itself, still collides with Default (world, players).
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local PhysicsService = game:GetService("PhysicsService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArmyConfig = require(Shared.Configs.ArmyConfig)
local FormationMath = require(Shared.Util.FormationMath) -- claude-bud JOB 22: the stable formation maths
local SoldierController = require(script.Parent.SoldierController) -- v114: the one writer of a soldier's movement
local AdminConfig = require(Shared.Configs.AdminConfig)
local BaseConfig = require(Shared.Configs.BaseConfig)
local BaseLayoutConfig = require(Shared.Configs.BaseLayoutConfig)
local PlotFrame = require(Shared.Util.PlotFrame)

local ArmyFollow = {}

ArmyFollow.Group = "ArmyNPCs" -- v99: the army NPC group (was WE_Squad); set at spawn for every unit

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

-- claude-bud JOB 22: the stable formation controller (ArmyConfig.Follow2.Stable)
local function stableOn(): boolean
	return cfg().Stable == true
end
ArmyFollow.StableOn = stableOn

-- v114: ArmyConfig.Follow3 (ArmyController) is switched on (the players group / hooks are needed for it too)
local function follow3On(): boolean
	local f = (ArmyConfig :: any).Follow3
	return typeof(f) == "table" and f.Enabled == true and (f.Rollout == "all" or f.Rollout == "owner")
end

-- claude-bud JOB 22: player characters in their own group, so soldiers never push / block players (Follow2.CollideWithPlayers)
ArmyFollow.PlayerGroup = "WE_PlayerChars"
local playersHooked = false
local function setCharGroup(char: Model)
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = ArmyFollow.PlayerGroup
		end
	end
	char.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = ArmyFollow.PlayerGroup
		end
	end)
end
local hookNow: () -> ()
local function hookPlayers()
	if playersHooked or not (stableOn() or follow3On()) then
		return
	end
	hookNow()
end
-- v123 (design rule: soldiers never body-block a player): every player character joins WE_PlayerChars whatever the
-- Follow2 / Follow3 rollout flags say (hookPlayers above keeps its old gate; ensureGroup calls this one after it)
hookNow = function()
	if playersHooked then
		return
	end
	playersHooked = true
	local function onPlayer(p: Player)
		if p.Character then
			setCharGroup(p.Character)
		end
		p.CharacterAdded:Connect(setCharGroup)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerAdded:Connect(onPlayer)
end

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
		PhysicsService:CollisionGroupSetCollidable(ArmyFollow.Group, "Default", true) -- the world and the players
		if stableOn() or follow3On() then
			if not PhysicsService:IsCollisionGroupRegistered(ArmyFollow.PlayerGroup) then
				PhysicsService:RegisterCollisionGroup(ArmyFollow.PlayerGroup)
			end
			-- v114: with Follow3 soldiers never collide with players (ArmyNPCs / WE_PlayerChars = false)
			PhysicsService:CollisionGroupSetCollidable(ArmyFollow.Group, ArmyFollow.PlayerGroup, cfg().CollideWithPlayers == true and not follow3On())
			PhysicsService:CollisionGroupSetCollidable(ArmyFollow.PlayerGroup, "Default", true) -- players still stand on the world
		end
	end)
	pcall(hookPlayers)
	-- v123 design rule, independent of every kill switch / rollout flag: an army soldier (ArmyNPCs, any owner's) never
	-- collides with a player character (WE_PlayerChars). The world (Default) still collides with both.
	pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered(ArmyFollow.PlayerGroup) then
			PhysicsService:RegisterCollisionGroup(ArmyFollow.PlayerGroup)
		end
		PhysicsService:CollisionGroupSetCollidable(ArmyFollow.Group, ArmyFollow.PlayerGroup, false) -- v123: soldiers never block players
		PhysicsService:CollisionGroupSetCollidable(ArmyFollow.PlayerGroup, "Default", true)
	end)
	pcall(hookNow)
end
ArmyFollow.EnsureGroup = ensureGroup

-- claude-bud JOB 22: ONE mover. Every Humanoid:MoveTo on an army soldier goes through here (ArmyFollow's own follow
-- states and SquadOrdersService's HOLD / ATTACK / RETREAT / escort states); `state` names who drives it now.
local function setState(unit: any, state: string)
	if unit._afState ~= state then
		unit._afState = state
		unit.MoveState = state
		pcall(function()
			unit.Model:SetAttribute("WE_MoveState", state) -- debugging (only on change)
		end)
	end
end
-- v114: forwarded to SoldierController.Move (the only Humanoid:MoveTo on a soldier)
function ArmyFollow.Command(unit: any, goal: Vector3, state: string?)
	SoldierController.Move(unit, goal, state)
end

-- claude-bud JOB 22: one yaw owner. Moving: AutoRotate faces travel and the face gyro has no torque (nothing else can
-- turn it); standing (InPosition): AutoRotate off, the gyro holds the formation heading.
local function setYawMode(unit: any, moving: boolean)
	if unit._afYawMoving == moving then
		return
	end
	unit._afYawMoving = moving
	local gyro = unit.Root and unit.Root:FindFirstChild("NPCFaceGyro")
	if gyro and gyro:IsA("BodyGyro") then
		if unit._afGyroTorque == nil then
			unit._afGyroTorque = gyro.MaxTorque
		end
		gyro.MaxTorque = if moving then Vector3.zero else unit._afGyroTorque
	end
	pcall(function()
		unit.Humanoid.AutoRotate = moving
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
			-- v99: a late rig part joins the assembly; the server keeps owning it (no ownership flip to a client)
			task.defer(function()
				local r = unit.Root
				if r and r.Parent and r:IsDescendantOf(Workspace) then
					pcall(function()
						if r:GetNetworkOwnershipAuto() then
							r:SetNetworkOwner(nil)
						end
					end)
				end
			end)
		end
	end)
	local hum: Humanoid = unit.Humanoid
	pcall(function()
		hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.Seated, false) -- claude-bud JOB 22: never joins a vehicle assembly
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

-- v99: ONE movement controller per unit. ArmyFollow owns a FOLLOW unit's MoveTo, WalkSpeed and yaw only while it
-- thinks it; the escort fight / HOLD / ATTACK / RETREAT call Release first. Fresh state on every (re)acquire: no stale
-- goal, path, stuck window or far timer survives a spell under another controller.
local function resetMotion(unit: any)
	unit._afMoveGoal = nil
	unit._afMoveAt = nil
	unit._afPath = nil
	unit._afStand = false
	unit._afProgPos = nil
	unit._afProgAt = nil
	unit._afFarSince = nil
	unit._afStuck = 0
	unit._afAlt = nil
	unit._afSpeedCur = nil
end

function ArmyFollow.Release(unit: any, state: string?)
	SoldierController.Release(unit) -- v114: the Follow3 controller lets go too (gyro re-aimed at its current yaw: no snap)
	if unit._afCtl then
		unit._afCtl = false
		resetMotion(unit)
		pcall(function()
			unit.Humanoid.AutoRotate = true
		end)
		-- claude-bud JOB 22: the face gyro gets its torque back (the order / combat code aims with it)
		local gyro = unit.Root and unit.Root:FindFirstChild("NPCFaceGyro")
		if gyro and gyro:IsA("BodyGyro") and unit._afGyroTorque ~= nil then
			local l = unit.Root.CFrame.LookVector -- v114: aimed at its current yaw first (a stale target snapped it round)
			gyro.CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(l.X, 0, l.Z))
			gyro.MaxTorque = unit._afGyroTorque
		end
		unit._afYawMoving = nil
	end
	if state then
		setState(unit, state)
	end
end

local function acquire(unit: any, now: number)
	if not unit._afCtl or now - (unit._afThinkAt or -math.huge) > num("ThinkGapReset", 1.2) then
		resetMotion(unit)
		unit._afCtl = true
		unit._afYawMoving = nil
		pcall(function()
			unit.Humanoid.AutoRotate = false -- the NPCFaceGyro turns it (faceTo): one yaw owner
		end)
	end
	unit._afThinkAt = now
end

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

--[[ claude-bud (Tidy): fixed seats for life, UNIQUE per squad (seat -> unit map): a dead / gone unit frees its seat,
	nobody else moves up, and no two units ever share one (a duplicated or missing seat is re-issued the lowest free
	number). FOLLOW (wedge), the base hold and ATTACK (march rows / target ring) all place a unit by its seat. ]]
local function assignSeats(st: any, units: { any })
	local order = table.clone(units)
	table.sort(order, function(a, b)
		return (a.Slot or 0) < (b.Slot or 0)
	end)
	local taken: { [number]: any } = {}
	for _, u in ipairs(order) do
		local s = u._afSeat
		if typeof(s) == "number" and s >= 1 and taken[s] == nil then
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
	end
	st._afSeatMap = taken
	st._afSeatCount = #order
end
ArmyFollow.AssignSeats = assignSeats

-- claude-bud: tidy wait spot of seat `rank`: rows on both sides of the gate lane, facing out (plot-local +Z)
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude
overlapParams.RespectCanCollide = true
local gridCache: { [number]: { At: number, Cells: { [number]: { Vector3 } }, Need: number } } = {}

-- one hold cell (plot-local x, z) is usable: ground under it (not water, not a roof) and nothing collidable in a
-- soldier-sized box on it (walls, props, parked vehicles; the squads and characters are excluded)
local function cellFree(plotId: number, lx: number, lz: number): Vector3?
	local w = PlotFrame.LocalToWorld(plotId, lx, lz)
	local c = PlotFrame.PlotPosition(plotId)
	local refY = if c then c.Y + 0.5 else w.Y
	local hit = Workspace:Raycast(Vector3.new(w.X, refY + 30, w.Z), Vector3.new(0, -60, 0), rayParams)
	if hit == nil or hit.Material == Enum.Material.Water or math.abs(hit.Position.Y - refY) > 2.5 then
		return nil
	end
	overlapParams.FilterDescendantsInstances = rayParams.FilterDescendantsInstances
	local box = CFrame.new(hit.Position + Vector3.new(0, 3.2, 0))
	local parts = Workspace:GetPartBoundsInBox(box, Vector3.new(3, 4.6, 3), overlapParams)
	if #parts > 0 then
		return nil
	end
	return hit.Position
end

-- the hold grid of plot `plotId`: per side (1 = left, 2 = right), the free cells in order (row 0 first, outward),
-- PerRow per row, ColSpacing apart, RowSpacing deep, never nearer the front edge than WaitOut (always outside the gate
-- plane). Cached for 30 s (props do not move).
local function holdCells(plotId: number, need: number): { [number]: { Vector3 } }
	local now = os.clock()
	local c = gridCache[plotId]
	local perSide = math.ceil(need / 2)
	if c and now - c.At < 30 and c.Need >= need then
		return c.Cells -- (a side short of free cells is not re-scanned every think: Need, not the cell count)
	end
	refreshRayFilter(nil)
	local half = BaseConfig.PlotSize.X * 0.5
	local gateHalf = (tonumber(BaseLayoutConfig.MainGateWidth) or 14) * 0.5
	local perRow = math.max(1, math.floor(tnum("PerRow", 4)))
	local cells: { [number]: { Vector3 } } = { {}, {} }
	for sideIdx, side in ipairs({ -1, 1 }) do
		local list = cells[sideIdx]
		for row = 0, 40 do
			if #list >= perSide then
				break
			end
			for col = 0, perRow - 1 do
				if #list >= perSide then
					break
				end
				local lx = side * (gateHalf + tnum("WaitGap", 5) + col * tnum("ColSpacing", 4))
				local lz = half + tnum("WaitOut", 14) + row * tnum("RowSpacing", 4)
				local at = cellFree(plotId, lx, lz)
				if at then
					table.insert(list, at)
				end
			end
		end
	end
	gridCache[plotId] = { At = now, Cells = cells, Need = math.max(need, 16) }
	return cells
end

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
	-- claude-bud (hold fix): the k-th FREE cell of this side (walls / props / water skipped, moved outward)
	local cells = holdCells(plotId, rank + 1)
	local mine = cells[if side < 0 then 1 else 2][j + 1]
	if mine then
		p = mine
	end
	return p, if out.Magnitude > 1e-3 then out.Unit else Vector3.new(0, 0, 1)
end

--[[ claude-bud (ATTACK fix): a unit's own attack spot by its seat, never a shared point.
	"march": rows abreast in front of `center` along `facing` (no target in reach): MarchPerRow per row, MarchSpacing
	apart, the first row MarchAhead studs ahead. "ring": round a target at `center`, one seat each, AttackRingSpacing
	studs apart along the ring (radius grows with the squad), the ring turned so the units approach from their side. ]]
function ArmyFollow.AttackPoint(st: any, unit: any, center: Vector3, facing: Vector3, mode: string): Vector3
	if unit._afSeat == nil or st._afSeatMap == nil or st._afSeatMap[unit._afSeat] ~= unit then
		assignSeats(st, st.Units)
	end
	local k = unit._afSeat or 1
	local n = math.max(1, st._afSeatCount or #st.Units)
	local f = Vector3.new(facing.X, 0, facing.Z)
	f = if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, -1)
	local right = Vector3.new(-f.Z, 0, f.X)
	if mode == "ring" then
		local spacing = tnum("AttackRingSpacing", 3.5)
		local r = math.max(tnum("AttackRingMin", 8), n * spacing / (2 * math.pi))
		local a = (k - 1) * 2 * math.pi / n
		local dir = -f * math.cos(a) + right * math.sin(a)
		return center + dir * r
	end
	local perRow = math.max(1, math.floor(tnum("MarchPerRow", 5)))
	local spacing = tnum("MarchSpacing", 3.5)
	local row = math.floor((k - 1) / perRow)
	local col = (k - 1) % perRow
	local inRow = math.min(perRow, n - row * perRow)
	local lateral = (col - (inRow - 1) * 0.5) * spacing
	return center + f * (tnum("MarchAhead", 10) + row * spacing) + right * lateral
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

-- v99: `cur` turned toward `want` (flat unit vectors) by at most `maxRad`
local function turnToward(cur: Vector3, want: Vector3, maxRad: number): Vector3
	local a = math.atan2(cur.X, cur.Z)
	local b = math.atan2(want.X, want.Z)
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	if math.abs(d) <= maxRad then
		return want
	end
	local r = a + (if d > 0 then maxRad else -maxRad)
	return Vector3.new(math.sin(r), 0, math.cos(r))
end

--[[ v99: seats are reassigned ONLY when the army size changed: once the living count has been the same for
	SeatCompactSeconds and a seat above that count exists (a hole after a death / trim), the units are renumbered
	1..n keeping their order (each moves at most up into the next free seat, nobody swaps sides at random). ]]
local function compactSeats(st: any, order: { any }, now: number)
	local n = #order
	if st._afSeatN ~= n then
		st._afSeatN = n
		st._afSeatNAt = now
		return
	end
	if now - (st._afSeatNAt or now) < num("SeatCompactSeconds", 4) then
		return
	end
	local hole = false
	for _, u in ipairs(order) do
		if typeof(u._afSeat) == "number" and u._afSeat > n then
			hole = true
			break
		end
	end
	if not hole then
		return
	end
	local bySeat = table.clone(order)
	table.sort(bySeat, function(a, b)
		return (a._afSeat or math.huge) < (b._afSeat or math.huge)
	end)
	for i, u in ipairs(bySeat) do
		u._afSeat = i
	end
	st._afFlip = nil
	logLine("compact" .. tostring(st), string.format("army of %d: seats compacted after a size change", n))
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
	local hum = root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
	st._afSeated = hum ~= nil and (hum.Sit or hum.SeatPart ~= nil)
	if lastPos and dt > 0.05 and dt < 2 then
		vel = flat(pos - lastPos) / dt
		-- v99: only on foot is a very fast move a jump (teleport / respawn); a fast vehicle is real speed (before, it
		-- zeroed his speed, dropped the vehicle defer and teleported the army every TeleportCooldown behind him)
		if not st._afSeated and vel.Magnitude > num("OwnerJumpSpeed", 60) then
			jumped = true
			vel = Vector3.zero
		end
	end
	st._afLastPos = pos
	st._afLastAt = now
	st._afJumped = jumped
	local speed = vel.Magnitude
	st._afSpeed = (st._afSpeed or 0) * 0.4 + speed * 0.6
	st._afVel = vel
	st._afWalk = ownerWalkSpeed(root)
	-- facing (v99): his root CFrame's look (his move direction when he backs away), turned at most TurnRateDeg per
	-- second (a sharp turn swings the wedge round smoothly, never 180 degrees in one think); standing, re-aimed only
	-- once he turned past FacingTurnDeg (no swirl on the spot), then turned all the way
	-- claude-bud JOB 22: the smoothed formation anchor (position lag, smoothed lead, capped turn, deadzone, no 180 flip)
	if stableOn() then
		st._afAnchor = st._afAnchor or FormationMath.NewAnchor()
		FormationMath.Step(st._afAnchor, pos, root.CFrame.LookVector, vel, dt, now, jumped or st._afSeated == true, cfg())
		st._afDir = st._afAnchor.Dir
		st._afFlip = nil -- seat sides never swap
	end
	local look = flat(root.CFrame.LookVector)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
	local want: Vector3 = look
	if speed >= 2 and look:Dot(vel.Unit) < 0 then
		want = vel.Unit
	end
	local cur: Vector3? = st._afDir
	local tdt = math.clamp(now - (st._afDirAt or now), 0, 0.6)
	st._afDirAt = now
	if stableOn() then
		-- (the anchor above owns the heading)
	elseif cur == nil or jumped then
		st._afDir = want
		st._afTurning = false
	else
		if speed >= 2 or cur:Dot(want) < math.cos(math.rad(num("FacingTurnDeg", 35))) then
			st._afTurning = true
		end
		if st._afTurning then
			local nd = turnToward(cur, want, math.rad(num("TurnRateDeg", 300)) * tdt)
			st._afDir = nd
			if speed < 2 and nd:Dot(want) > math.cos(math.rad(2)) then
				st._afTurning = false
			end
		end
	end
	-- rank by SquadSlot (stable)
	local order = table.clone(units)
	table.sort(order, function(a, b)
		return (a.Slot or 0) < (b.Slot or 0)
	end)
	st._afTidy = tidyLive(player)
	do
		-- v99: EVERY squad keeps persistent unique seats (was: Tidy only; the rest ranked by index, so one death
		-- re-ranked the whole wedge and every unit crossed to a new spot). Compacted only after the size changed.
		compactSeats(st, order, now)
		assignSeats(st, order)
		for _, u in ipairs(order) do
			u._afRank = u._afSeat
		end
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
	if st._afTidy and not st._afInBase and st._afSeatMap and not stableOn() then
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
		-- claude-bud (owner: "the army is still glitchy and despawns when walking"): the wedge trails 7-19 studs
		-- behind him plus the catch-up lag, i.e. AT or BEHIND the phone camera (~12-15 studs back): the back rows leave
		-- the view (and the camera guard hides one filling the screen) while he walks, and pop back when he stops.
		-- Flank: a file on each side of him from FlankFront (ahead) back FlankRowBack per row, each row FlankRowSide
		-- further out (its client escort file ahead of it never lands on another soldier). All in front of the camera.
		if tidyCfg().Formation == "Flank" then
			back = tnum("FlankFront", -1) + (row - 1) * tnum("FlankRowBack", 3)
			lat = side * (tnum("FlankSide", 3.5) + (row - 1) * tnum("FlankRowSide", 2.6))
		end
	end
	if stableOn() and st._afAnchor then
		-- claude-bud JOB 22: slot = the smoothed anchor x this seat's fixed offset (+ the smoothed, capped lead)
		return FormationMath.SlotWorld(st._afAnchor, lat, back, root.Position.Y, cfg())
	end
	local lead = (st._afVel or Vector3.zero) * num("LeadSeconds", 0.3)
	local cap = num("LeadMaxStuds", 5)
	if lead.Magnitude > cap then
		lead = lead.Unit * cap
	end
	-- v99: this unit's own offset (x = side, z = back) in his facing frame (root position, turned by st._afDir)
	local frame = CFrame.lookAt(root.Position, root.Position + dir)
	return frame:PointToWorldSpace(Vector3.new(lat, 0, back)) + lead
end
ArmyFollow.SlotPoint = slotPoint

-- ── teleport (regroup): one PivotTo of the same unit, to a clear spot behind the owner ─────────────────────────
--[[ v99: the reposition spot is the unit's OWN slot, first pushed RegroupBehindStuds further back (behind the phone
	camera, ~12.5 studs behind him: it runs in instead of popping up in view), then half that, then the slot itself,
	then points behind him on its own side line. Never within RegroupMinOwnerStuds of him (never on top of him). ]]
local function spotFor(st: any, root: BasePart, rank: number): CFrame?
	local dir: Vector3 = st._afDir or Vector3.new(0, 0, -1)
	local slot = slotPoint(st, root, rank)
	local cands: { Vector3 } = {}
	if not st._afInBase then
		local behind = num("RegroupBehindStuds", 16)
		table.insert(cands, slot - dir * behind)
		table.insert(cands, slot - dir * behind * 0.5)
	end
	table.insert(cands, slot)
	if not st._afInBase then
		local right = Vector3.new(-dir.Z, 0, dir.X)
		local lat = (slot - root.Position):Dot(right)
		for _, b in ipairs({ 8, 12, 5, 16 }) do
			table.insert(cands, root.Position - dir * b + right * lat)
		end
	end
	local minOwner = num("RegroupMinOwnerStuds", 6)
	for _, c in ipairs(cands) do
		local g = groundAt(c, root.Position.Y)
		if g and flatDist(g, root.Position) >= minOwner and math.abs(g.Y - root.Position.Y) < 14 and (st._afInBase or clearLine(root.Position, g + Vector3.new(0, 1.8, 0))) then
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
	SoldierController.Reposition(unit, cf, why, true) -- v114: the one emergency PivotTo lives in SoldierController
	unit._afPath = nil
	unit._afMoveGoal = cf.Position
	unit._afMoveAt = now
	unit._afProgPos = cf.Position
	unit._afProgAt = now
	unit._afFarSince = nil
	unit._afStuck = 0
	unit._afAlt = nil
	ArmyFollow.Stats.Regroup += 1
	logLine("rg" .. tostring(unit.OwnerUserId) .. why, string.format("regroup unit %s (%s) owner %s", tostring(unit.Id), why, tostring(unit.OwnerUserId)))
	return true
end

local function setSpeed(unit: any, s: number)
	local hum: Humanoid = unit.Humanoid
	unit._afSpeedCur = s
	if math.abs(hum.WalkSpeed - s) >= 1 then
		hum.WalkSpeed = s
		unit.Speed = s -- v99: SquadOrdersService's WalkSpeed cache stays true (its setSpeed skips equal writes)
	end
end

-- v99: the one yaw writer while ArmyFollow controls the unit (AutoRotate is off): the NPCFaceGyro's target, written
-- only past 4 degrees of change (no property write per think); an escort that just shot keeps its aim for
-- FaceAfterShotSeconds
local function faceTo(unit: any, dir: Vector3, now: number)
	if now - (tonumber(unit.LastFireAt) or 0) < num("FaceAfterShotSeconds", 1.2) then
		return
	end
	local f = flat(dir)
	if f.Magnitude < 1e-3 then
		return
	end
	f = f.Unit
	local gyro = unit.Root:FindFirstChild("NPCFaceGyro")
	if gyro and gyro:IsA("BodyGyro") then
		-- compared with the gyro's own target (another writer, e.g. the escort's faceYaw, may have turned it)
		if flat(gyro.CFrame.LookVector):Dot(f) > math.cos(math.rad(4)) then
			return
		end
		gyro.CFrame = CFrame.lookAt(Vector3.zero, f)
	end
end

local function moveTo(unit: any, goal: Vector3, now: number)
	local last: Vector3? = unit._afMoveGoal
	local due = if stableOn()
		then FormationMath.ReissueDue(last, unit._afMoveAt, goal, now, cfg()) -- claude-bud JOB 22: never every frame
		else (last == nil or flatDist(last, goal) >= num("ReissueStuds", 1.5) or now - (unit._afMoveAt or 0) >= num("ReissueSeconds", 5))
	if due then
		ArmyFollow.Command(unit, goal)
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
			unit._afPath = { Points = wps, I = math.min(2, #wps), Goal = to, At = os.clock() }
		else
			unit._afPath = nil
			unit._afPathFail = os.clock()
		end
	end)
end

-- claude-bud (hold fix), v114 extracted: the point to walk to from `pos` (outside plot `plotId`) toward `goal`: the goal,
-- or first the nearest outside corner point when the straight line would clip his plot square (never crossed)
local function holdVia(plotId: number, pos: Vector3, goal: Vector3): Vector3
	local lp = plotLocal(plotId, pos)
	local lg = plotLocal(plotId, goal)
	local via = goal
	if lp and lg then
		local half = BaseConfig.PlotSize.X * 0.5 + tnum("PlotPadStuds", 2) + 4
		local crosses = false
		for i = 1, 7 do
			local t = i / 8
			local x, z = lp.X + (lg.X - lp.X) * t, lp.Z + (lg.Z - lp.Z) * t
			if math.abs(x) < half and math.abs(z) < half then
				crosses = true
				break
			end
		end
		if crosses then
			local sx = if lp.X < 0 then -1 else 1
			local cx, cz
			if math.abs(lp.X) >= half then
				cx, cz = sx * half, half
			elseif lp.Z < 0 then
				cx, cz = sx * half, lp.Z
			else
				cx, cz = lg.X, half
			end
			via = PlotFrame.LocalToWorld(plotId, cx, cz)
			via = Vector3.new(via.X, goal.Y, via.Z)
		end
	end
	return via
end

--[[ one FOLLOW unit, one think. Returns nothing; SquadOrdersService calls it only for a live owner in FOLLOW, on foot
	or seated, after its escort shot (the escort's own walk runs only while the owner stands near a hostile). ]]
function ArmyFollow.Unit(player: Player?, st: any, unit: any, root: BasePart, now: number)
	if not unit.Alive or unit.Humanoid.Health <= 0 or unit.Root.Parent == nil then
		return
	end
	prepUnit(unit) -- (v99: already done at spawn; a no-op here)
	acquire(unit, now) -- v99: this unit's one movement controller from here until Release
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
	-- claude-bud (hold fix): while he is in his base, a unit OUTSIDE his plot walks straight to its hold cell: no
	-- pathfinding (a path ran through the open gate), no stuck / far teleport correction (void rescue only)
	local holdOut = st._afTidy and st._afInBase and st._afPlot ~= nil and not inPlot(st._afPlot, pos, 0)
	if not seatedFast and not walkBack and not holdOut then
		if st._afJumped and ownerD > num("JumpRegroupStuds", 40) and regroup(st, unit, root, now, "owner-jump") then
			return
		end
		-- v99: the emergency reposition only when EXTREMELY far (FarStuds 100 from its slot for FarSeconds 3);
		-- falling behind is handled by the catch-up speed, never by a teleport or a new unit
		local far = if st._afInBase then num("BaseFarStuds", 140) else num("FarStuds", 100)
		if d > far then
			unit._afFarSince = unit._afFarSince or now
			if now - unit._afFarSince >= num("FarSeconds", 3) and regroup(st, unit, root, now, "far") then
				return
			end
		else
			unit._afFarSince = nil
		end
		-- stuck (v99, staged): it wants to move (goal further than StuckGoalStuds) but has moved less than StuckStuds:
		-- StuckSeconds -> a fresh path now; StuckAltSeconds -> an alternate point beside it (+ a jump);
		-- StuckTeleportSeconds -> the reposition (the final fallback)
		local pp: Vector3? = unit._afProgPos
		if pp == nil or d <= num("StuckGoalStuds", 6) or flatDist(pos, pp) >= num("StuckStuds", 3) then
			unit._afProgPos = pos
			unit._afProgAt = now
			unit._afStuck = 0
		elseif d > num("StuckMinStuds", 10) then
			local since = now - (unit._afProgAt or now)
			if since >= num("StuckTeleportSeconds", 10) then
				if regroup(st, unit, root, now, "stuck") then
					return
				end
			elseif since >= num("StuckAltSeconds", 6) and (unit._afStuck or 0) < 2 then
				unit._afStuck = 2
				setState(unit, "StuckRecovery") -- claude-bud JOB 22
				local to = flat(slot - pos)
				to = if to.Magnitude > 1e-3 then to.Unit else Vector3.new(0, 0, -1)
				local side = Vector3.new(-to.Z, 0, to.X) * num("StuckAltStuds", 6)
				local first = if rank % 2 == 1 then -1 else 1
				local alt: Vector3? = nil
				for _, sgn in ipairs({ first, -first }) do
					local c = pos + side * sgn + to * 2
					if clearLine(pos, c) then
						alt = c
						break
					end
				end
				if alt then
					unit._afAlt = { P = alt, Until = now + num("StuckAltHoldSeconds", 2.5) }
					unit._afPath = nil
					unit.Humanoid.Jump = true
					logLine("alt" .. tostring(unit.OwnerUserId), string.format("unit %s stuck %.1f s: alternate point", tostring(unit.Id), since))
				end
			elseif since >= num("StuckSeconds", 3) and (unit._afStuck or 0) < 1 then
				unit._afStuck = 1
				setState(unit, "StuckRecovery") -- claude-bud JOB 22
				unit._afPath = nil
				unit._afPathAt = -math.huge -- one repath now (the per-unit cooldown is skipped once)
				requestPath(unit, pos, slot, now)
			end
		end
	else
		unit._afFarSince = nil
		unit._afProgPos = nil
	end

	-- separation: steer away from any squad-mate closer than SeparationStuds
	local sep = if st._afTidy and st._afInBase then 0 else num("SeparationStuds", 3.5) -- claude-bud: hold cells are exact
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
	-- claude-bud JOB 22: the owner is in the separation too (they never walk into him)
	if stableOn() and not st._afInBase then
		local oc = num("OwnerClearStuds", 3.5)
		local off = flat(pos - root.Position)
		local m = off.Magnitude
		if m < oc then
			push += (if m > 1e-3 then off / m else Vector3.new(((rank % 2) * 2 - 1), 0, 0)) * (oc - m) / oc
		end
	end
	-- v99: the push is capped (SeparationMaxStuds): neighbours step apart, the goal never jumps round the slot
	local pushOff = push * num("SeparationGain", 3)
	local maxPush = num("SeparationMaxStuds", 3)
	if pushOff.Magnitude > maxPush then
		pushOff = pushOff.Unit * maxPush
	end
	local goal = slot + pushOff
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
	else
		-- v99: one continuous curve (was a step from x MatchMult to x CatchUpMult at CatchUpStartStuds): his pace x
		-- MatchMult in the slot, ramping to x CatchUpMult over CatchUpRampStuds, then + CatchUpPerStud per stud
		-- further behind, capped at max(his pace x CatchUpMaxMult, CatchUpMin); back to normal once in formation
		local start = num("CatchUpStartStuds", 5)
		local ramp = math.max(1, num("CatchUpRampStuds", 10))
		local t = math.clamp((d - start) / ramp, 0, 1)
		local mm = num("MatchMult", 1.08)
		local mult = mm + (num("CatchUpMult", 1.35) - mm) * t
		local cap = math.max(ownerPace * num("CatchUpMaxMult", 1.8), num("CatchUpMin", 34))
		speed = math.max(base, ownerPace * mult + math.max(0, d - start - ramp) * num("CatchUpPerStud", 0.6))
		speed = math.min(cap, speed)
	end
	speed = math.clamp(speed, 8, num("MaxSpeed", 50))
	-- v99: smooth: at most SpeedUpPerThink faster / SpeedDownPerThink slower than the last think
	local curSpeed = tonumber(unit._afSpeedCur) or unit.Humanoid.WalkSpeed
	speed = math.clamp(speed, curSpeed - num("SpeedDownPerThink", 6), curSpeed + num("SpeedUpPerThink", 8))
	setSpeed(unit, speed)

	-- claude-bud (Tidy): at its gate wait spot it stands still facing out, whatever he does inside
	if st._afTidy and st._afInBase and st._afPlot and flatDist(pos, goal) <= tnum("HoldArriveStuds", 1.5) then
		if not unit._afStand then
			unit._afStand = true
			ArmyFollow.Command(unit, pos, "BaseHold")
			unit._afMoveGoal = pos
			unit._afMoveAt = now
			local _, out = tidyWaitSpot(st._afPlot, rank)
			-- v114: no PivotTo turn (a hard yaw snap); the gyro turns it
			faceTo(unit, out, now) -- v99: the gyro holds that facing (it no longer pulls back to a stale yaw)
		end
		unit._afPath = nil
		return
	end
	if stableOn() and not st._afInBase then
		-- claude-bud JOB 22: the follow state machine. InPosition (arrival deadzone, left only past LeaveDeadzone):
		-- one stop, then NOTHING is issued; the gyro holds the formation heading. Following / CatchingUp: AutoRotate
		-- faces travel (no gyro), MoveTo only when the target moved MoveReissueStuds or MoveRefreshSeconds passed.
		local prevState = unit._afState
		local state = FormationMath.State(prevState, flatDist(pos, goal), cfg())
		if state == "InPosition" then
			if prevState ~= "InPosition" then
				ArmyFollow.Command(unit, pos, "InPosition")
				unit._afMoveGoal = pos
				unit._afMoveAt = now
				setYawMode(unit, false)
			end
			faceTo(unit, st._afDir or Vector3.new(0, 0, -1), now) -- (the gyro writes only past 4 degrees)
			unit._afPath = nil
			unit._afStand = true
			return
		end
		setState(unit, state)
		setYawMode(unit, true)
	else
		-- v99: facing: toward its goal while it runs to catch up, else his facing (so its client escort file points
		-- where the formation points and never swings through its neighbours)
		faceTo(unit, if d > num("FaceMoveStuds", 8) then goal - pos else (st._afDir or Vector3.new(0, 0, -1)), now)
		-- arrive: stand in the slot while the owner stands
		if d <= num("ArriveStuds", 2) and (st._afSpeed or 0) < 1 and push.Magnitude < 0.05 then
			if not unit._afStand then
				unit._afStand = true
				ArmyFollow.Command(unit, pos, "InPosition")
				unit._afMoveGoal = pos
				unit._afMoveAt = now
			end
			unit._afPath = nil
			return
		end
	end
	unit._afStand = false

	-- claude-bud (hold fix): outside his plot while he is in it: straight to the cell; if that line would clip his plot
	-- square, first to the nearest outside corner point (the plot is never crossed, no path through the gate)
	if holdOut and st._afPlot then
		local via = holdVia(st._afPlot, pos, goal)
		unit._afPath = nil
		moveTo(unit, via, now)
		return
	end
	-- v99 stuck stage 2: the alternate point beside it, for a short spell
	local alt = unit._afAlt
	if alt then
		if now < alt.Until and flatDist(pos, alt.P) > 1.5 then
			moveTo(unit, keepOut(alt.P), now)
			return
		end
		unit._afAlt = nil
	end
	-- movement: straight while it sees the slot, a throttled path only when blocked
	if clearLine(pos, goal) then
		unit._afPath = nil
		moveTo(unit, goal, now)
		return
	end
	local path = unit._afPath
	-- v99: a path is kept while its end is within PathKeepStuds of the slot OR it is younger than PathKeepSeconds (at
	-- a run the slot moved > 8 studs every think and the path was dropped each time)
	if path and (flatDist(path.Goal, goal) <= num("PathKeepStuds", 12) or now - (path.At or 0) < num("PathKeepSeconds", 2)) and path.I <= #path.Points then
		local wp = path.Points[path.I]
		-- v99: skip every waypoint already reached or passed between thinks (never walk back to one)
		while wp do
			local nxt = path.Points[path.I + 1]
			if flatDist(pos, wp.Position) < 3 or (nxt ~= nil and flatDist(pos, nxt.Position) < flatDist(wp.Position, nxt.Position)) then
				path.I += 1
				wp = path.Points[path.I]
			else
				break
			end
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
	-- while the path is computed (or none exists), v99: each unit walks to its OWN point, half-way from him to its
	-- slot when it can see that (else the slot itself). Before, every unit walked to the SAME point 4 studs behind
	-- him = the blob round buildings.
	local mid = root.Position + (slot - root.Position) * 0.5
	moveTo(unit, if st._afInBase then goal else keepOut(if clearLine(pos, mid) then mid else goal), now)
end

-- claude-bud JOB 22: is the owner moving (the escort-vs-follow switch), with hysteresis (no flicker at ~2 studs/s)
function ArmyFollow.OwnerMoving(st: any, speed: number): boolean
	if not stableOn() then
		return speed >= 2
	end
	local m = FormationMath.Moving(st._afOwnerMoving == true, speed, cfg())
	st._afOwnerMoving = m
	return m
end

-- claude-bud JOB 22: this unit's formation slot (the SAME one ArmyFollow walks it to), for the escort's standing fight
function ArmyFollow.HomePoint(player: Player?, st: any, unit: any, root: BasePart, now: number): Vector3
	plan(st, player, root, st.Units, now)
	return slotPoint(st, root, unit._afRank or 1)
end

-- ── v114: helpers ArmyController (Follow3) shares with this module (same plot / hold rules, same rays) ──────────────
ArmyFollow.Follow3On = follow3On
ArmyFollow.ClearLine = clearLine
ArmyFollow.GroundAt = groundAt
ArmyFollow.RefreshRayFilter = refreshRayFilter
ArmyFollow.InPlot = inPlot
ArmyFollow.HoldVia = holdVia
ArmyFollow.HoldSpot = function(plotId: number, rank: number): (Vector3, Vector3)
	return tidyWaitSpot(plotId, rank)
end
-- his base state for this pass (the Tidy hold: inside / near his own plot square, with hysteresis); sets the same
-- st._afTidy / _afInBase / _afPlot / _afOwnPlot / _afLeftBaseAt fields plan() does
function ArmyFollow.BaseState(st: any, player: Player?, pos: Vector3, now: number): (boolean, number?)
	st._afTidy = tidyLive(player)
	local plotId = ownPlotInside(st, player, pos)
	local wasIn = st._afInBase
	st._afInBase = plotId ~= nil
	st._afPlot = plotId
	st._afOwnPlot = ownPlotId(player)
	if wasIn and not st._afInBase then
		st._afLeftBaseAt = now
	end
	if st._afInBase ~= wasIn and player then
		logLine("base" .. tostring(player.UserId), string.format("owner %d %s his base: army %s", player.UserId, if plotId then "entered" else "left", if plotId then "waits at the gate" else "follows"))
	end
	return st._afInBase == true, plotId
end

return ArmyFollow
