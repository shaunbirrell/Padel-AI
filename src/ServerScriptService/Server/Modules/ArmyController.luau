--!strict
--[[
	v114 (Code Bot Roblox, 2026-09-29, docs/ARMY-FOLLOW-ROOTCAUSE-2.md): ArmyController — ONE authoritative movement
	controller per army (ArmyConfig.Follow3; Enabled false / Rollout off = the v113 ArmyFollow path).

	  * State machine per army: FOLLOW / HOLD / ATTACK / RETREAT (= the squad order). Only the current state issues
	    destinations: FOLLOW here (every Follow3.UpdateSeconds), the other three in SquadOrdersService (their MoveTo
	    goes through SoldierController too). In FOLLOW the escort code only shoots and aims.
	  * Anchor + heading: Shared/Util/FormationController (smoothed position, rate-limited heading with deadband and
	    hysteresis).
	  * Slots: FormationController.Assign — PERMANENT per unit, kept across FOLLOW <-> ATTACK / HOLD / RETREAT (an
	    attacker walks back to its SAME slot, no teleport, no wipe); a roster change only fills holes.
	  * Per unit: SoldierController.Drive (MoveTo, speed, facing, arrival, stuck, the emergency reposition).
	  * His own base (Follow2.Tidy hold): units wait at their gate cells (ArmyFollow.HoldSpot), never cross his plot.
	  * Publishes WE_FormYaw (the formation heading, on change only) and WE_EscSide / WE_FormSlot per unit so every
	    client lays that unit's escort figures out along its formation row (RigAnimator) instead of a rigid file
	    ahead of the unit that swings with every turn.
	  * Collision audit every AuditSeconds: every part of every unit carries the ArmyNPCs group.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArmyConfig = require(Shared.Configs.ArmyConfig)
local AdminConfig = require(Shared.Configs.AdminConfig)
local FormationController = require(Shared.Util.FormationController)
local SoldierController = require(script.Parent.SoldierController)
local ArmyFollow = require(script.Parent.ArmyFollow)

local ArmyController = {}
ArmyController.Stats = { Ticks = 0, Errors = 0, AuditFixes = 0 }

local deps: { [string]: any } = {}
local started = false
local errAt: { [number]: number } = {}

local function cfg(): { [string]: any }
	local c = (ArmyConfig :: any).Follow3
	return if typeof(c) == "table" then c else {}
end

local function num(key: string, default: number): number
	local v = cfg()[key]
	return if typeof(v) == "number" then v else default
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDist(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Follow3 live for this owner (and the Follow2 module it builds on)
function ArmyController.LiveFor(userId: any): boolean
	local c = cfg()
	if c.Enabled ~= true or not ArmyFollow.LiveFor(userId) then
		return false
	end
	if c.Rollout == "all" then
		return true
	end
	if c.Rollout == "owner" then
		return AdminConfig.IsPlaytestOwner(userId) == true
	end
	return false
end

local STATE_OF: { [string]: string } = { Follow = "FOLLOW", Hold = "HOLD", Attack = "ATTACK", Retreat = "RETREAT" }

local function army(st: any): any
	local a = st._ac
	if a == nil then
		a = {
			State = nil,
			Anchor = FormationController.NewAnchor(),
			Assign = FormationController.NewAssignment(),
			LastPos = nil,
			LastAt = nil,
			Yaw = nil,
			AuditAt = -math.huge,
		}
		st._ac = a
	end
	return a
end

-- the slot index of a unit (assigned permanently on first sight)
function ArmyController.SlotOf(st: any, unit: any): number
	local a = army(st)
	local idx = a.Assign.ByUnit[unit]
	if idx == nil then
		FormationController.Assign(a.Assign, st.Units)
		idx = a.Assign.ByUnit[unit]
	end
	return idx or tonumber(unit.Slot) or 1
end

-- spawn offset (owner frame: x = right, z = behind) of a new unit with SquadSlot `slot`: its future formation cell
function ArmyController.SpawnOffset(slot: number): Vector3
	local lat, back = FormationController.SlotLocal(slot, cfg())
	return Vector3.new(lat, 0, back)
end

local function publish(st: any, a: any)
	-- per unit: its side / slot (on change only: attributes replicate) and the heading (past YawPublishDeg only)
	local dir = a.Anchor.Dir
	local yaw = if dir then math.floor(FormationController.YawDeg(dir) + 0.5) else nil
	local pub = yaw ~= nil and (a.Yaw == nil or math.abs(((yaw - a.Yaw + 180) % 360) - 180) >= num("YawPublishDeg", 2))
	if pub then
		a.Yaw = yaw
	end
	for _, u in ipairs(st.Units) do
		if u.Alive and u.Model and u.Model.Parent then
			local idx = a.Assign.ByUnit[u]
			if idx and u._acIdx ~= idx then
				u._acIdx = idx
				local side = FormationController.SideRow(idx)
				pcall(function()
					u.Model:SetAttribute("WE_FormSlot", idx)
					u.Model:SetAttribute("WE_EscSide", side)
				end)
				u._acYaw = nil
			end
			if yaw ~= nil and u._acYaw ~= a.Yaw then
				u._acYaw = a.Yaw
				pcall(function()
					u.Model:SetAttribute("WE_FormYaw", a.Yaw)
				end)
			end
		end
	end
end

-- every part of every unit in the ArmyNPCs group (late rig parts / accessories included)
local function audit(st: any, a: any, now: number)
	if now - a.AuditAt < num("AuditSeconds", 5) then
		return
	end
	a.AuditAt = now
	local group = ArmyFollow.Group
	for _, u in ipairs(st.Units) do
		if u.Model and u.Model.Parent then
			for _, d in ipairs(u.Model:GetDescendants()) do
				if d:IsA("BasePart") and d.CollisionGroup ~= group then
					d.CollisionGroup = group
					ArmyController.Stats.AuditFixes += 1
				end
			end
		end
	end
end

-- a unit position the owner cannot see: behind him (past his shoulder line) or with the view line blocked
local function outOfView(ownerRoot: BasePart, p: Vector3): boolean
	local look = flat(ownerRoot.CFrame.LookVector)
	local off = flat(p - ownerRoot.Position)
	if off.Magnitude > 1e-3 and look.Magnitude > 1e-3 and off.Unit:Dot(look.Unit) < -0.2 then
		return true
	end
	return not ArmyFollow.ClearLine(ownerRoot.Position + Vector3.new(0, 1.5, 0), p)
end

-- the emergency reposition spot: its own slot pushed RepositionBehindStuds back (behind the phone camera), then
-- half that, then the slot; on the ground, with a clear line from him (never inside a wall), never near him
local function repositionSpot(a: any, ownerRoot: BasePart, lat: number, back: number): CFrame?
	local dir: Vector3 = a.Anchor.Dir or Vector3.new(0, 0, -1)
	local y = ownerRoot.Position.Y
	local slot = FormationController.SlotWorld(a.Anchor, lat, back, y)
	local behind = num("RepositionBehindStuds", 16)
	ArmyFollow.RefreshRayFilter(nil)
	for _, c in ipairs({ slot - dir * behind, slot - dir * behind * 0.5, slot }) do
		local g = ArmyFollow.GroundAt(c, y)
		if g and flatDist(g, ownerRoot.Position) >= num("RepositionMinOwnerStuds", 8) and math.abs(g.Y - y) < 14
			and ArmyFollow.ClearLine(ownerRoot.Position, g + Vector3.new(0, 1.8, 0)) then
			local p = g + Vector3.new(0, 3.2, 0)
			return CFrame.lookAt(p, p + dir)
		end
	end
	return nil
end

local function stepArmy(player: Player, st: any, now: number)
	local a = army(st)
	local state = STATE_OF[st.Order] or "FOLLOW"
	local living: { any } = {}
	for _, u in ipairs(st.Units) do
		if u.Alive and u.Humanoid and u.Humanoid.Health > 0 and u.Root and u.Root.Parent then
			table.insert(living, u)
		end
	end
	-- permanent slots (only a roster change touches the table; survivors never move)
	FormationController.Assign(a.Assign, living)
	audit(st, a, now)
	local prevState = a.State
	a.State = state
	if state ~= "FOLLOW" then
		-- HOLD / ATTACK / RETREAT: SquadOrdersService issues their goals (through SoldierController); nothing here
		a.LastPos = nil
		return
	end
	local root: BasePart? = deps.CharacterRoot and deps.CharacterRoot(player)
	if root == nil then
		-- the owner is dead: stop once, wait
		for _, u in ipairs(living) do
			if u._acIdle ~= true then
				u._acIdle = true
				SoldierController.Stop(u, "Hold")
			end
		end
		a.LastPos = nil
		return
	end
	local proot = root :: BasePart
	local pos = proot.Position
	local dt = if a.LastAt then math.clamp(now - a.LastAt, 0.01, 1) else num("UpdateSeconds", 0.2)
	local vel = Vector3.zero
	local jumped = false
	local fresh = a.LastPos == nil -- first tick after a gap (respawn, order change): the anchor starts on him
	local hum = proot.Parent and proot.Parent:FindFirstChildOfClass("Humanoid")
	local seated = hum ~= nil and (hum.Sit or hum.SeatPart ~= nil)
	if a.LastPos then
		vel = flat(pos - a.LastPos) / dt
		if not seated and vel.Magnitude > num("OwnerJumpSpeed", 80) then
			jumped = true -- a teleport / respawn: the anchor snaps (no sweep across the map)
			vel = Vector3.zero
		end
	end
	a.LastPos = pos
	a.LastAt = now
	-- a teleport / respawn, or FOLLOW just (re)started: the anchor starts on him (only the anchor snaps, never a unit)
	FormationController.Step(a.Anchor, pos, proot.CFrame.LookVector, vel, dt, now, jumped or fresh or prevState ~= "FOLLOW", cfg())
	publish(st, a)
	local inBase, plotId = ArmyFollow.BaseState(st, player, pos, now)
	local tidy = st._afTidy == true
	local ownPlot: number? = if tidy then st._afOwnPlot else nil
	local walkBack = tidy and not inBase and now - (st._afLeftBaseAt or -math.huge) < 8
	local speedSmooth = a.Anchor.Vel.Magnitude
	local drivingFast = seated and speedSmooth > num("VehicleDeferSpeed", 20)
	-- his MEASURED (smoothed) pace: a slow phone-joystick walk is not his full WalkSpeed (units would outrun the
	-- slot and stop-start); falling behind is covered by the per-stud catch-up
	local pace = speedSmooth
	if hum and speedSmooth > hum.WalkSpeed * 0.9 then
		pace = math.max(speedSmooth, hum.WalkSpeed)
	end
	if seated then
		pace = math.max(16, math.min(speedSmooth, num("CatchUpMin", 30)))
	end
	local lead = FormationController.MoveLead(a.Anchor, cfg())
	local base = tonumber((deps.UnitWalkSpeed or function()
		return 14
	end)()) or 14
	local c = cfg()
	for _, u in ipairs(living) do
		u._acIdle = false
		local idx = a.Assign.ByUnit[u] or 1
		local lat, back = FormationController.SlotLocal(idx, c)
		local goal = FormationController.SlotWorld(a.Anchor, lat, back, pos.Y)
		local heading: Vector3 = a.Anchor.Dir or Vector3.new(0, 0, -1)
		local moving = a.Anchor.Moving
		local allow = not drivingFast and not walkBack
		local noPath = false
		local clear = num("OwnerClearStuds", 5)
		local upos = u.Root.Position
		if inBase and plotId then
			-- his base: its gate cell (straight, never through his plot), standing facing out
			local cell, out = ArmyFollow.HoldSpot(plotId, idx)
			goal = Vector3.new(cell.X, pos.Y, cell.Z)
			heading = out
			moving = false
			clear = 0
			if not ArmyFollow.InPlot(plotId, upos, 0) then
				goal = ArmyFollow.HoldVia(plotId, upos, goal)
				noPath = true
				allow = false
			end
		elseif ownPlot and not ArmyFollow.InPlot(ownPlot, upos, 0) and ArmyFollow.InPlot(ownPlot, goal, 2) then
			-- a unit outside his plot never gets a goal inside it
			local cell = ArmyFollow.HoldSpot(ownPlot, idx)
			goal = Vector3.new(cell.X, pos.Y, cell.Z)
		end
		local okU, errU = pcall(SoldierController.Drive, u, {
			Goal = goal,
			Heading = heading,
			Lead = if moving then lead else Vector3.zero,
			OwnerPos = pos,
			OwnerMoving = moving,
			Pace = pace,
			BaseSpeed = base,
			Dt = dt,
			Now = now,
			AllowRecover = allow,
			Jumped = jumped,
			NoPath = noPath,
			OwnerClear = clear,
			Pivot = if inBase then nil else a.Anchor.Pos, -- the wheel pivot (U-turns: round the outside, not through him)
			Spot = function()
				return repositionSpot(a, proot, lat, back)
			end,
			OutOfView = function(p: Vector3): boolean
				return outOfView(proot, p)
			end,
		})
		if not okU then
			-- one unit's error never stops the rest of the army (logged by the caller's rate limit)
			ArmyController.Stats.Errors += 1
			if now - (errAt[-player.UserId] or -math.huge) > 30 then
				errAt[-player.UserId] = now
				warn("[ArmyController] unit tick error for " .. tostring(player.UserId) .. ": " .. tostring(errU))
			end
		end
	end
end
ArmyController._StepArmy = stepArmy

-- deps: Squads() -> { [userId]: st }, CharacterRoot(player) -> BasePart?, UnitWalkSpeed() -> number
function ArmyController.Start(d: { [string]: any })
	deps = d
	SoldierController.Bind({ ClearLine = ArmyFollow.ClearLine })
	if started then
		return
	end
	started = true
	task.spawn(function()
		while true do
			task.wait(math.clamp(num("UpdateSeconds", 0.2), 0.1, 0.5))
			local now = os.clock()
			local squads = deps.Squads and deps.Squads() or {}
			for _, player in ipairs(Players:GetPlayers()) do
				local st = squads[player.UserId]
				if st and #st.Units > 0 and ArmyController.LiveFor(player.UserId) then
					local ok, err = pcall(stepArmy, player, st, now)
					ArmyController.Stats.Ticks += 1
					if not ok then
						ArmyController.Stats.Errors += 1
						if now - (errAt[player.UserId] or -math.huge) > 30 then
							errAt[player.UserId] = now
							warn("[ArmyController] tick error for " .. tostring(player.UserId) .. ": " .. tostring(err))
						end
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p: Player)
		errAt[p.UserId] = nil
		errAt[-p.UserId] = nil
	end)
	print("[ArmyController] v114 Follow3 controller started (" .. tostring(cfg().Enabled) .. ", " .. tostring(cfg().Rollout) .. ")")
end

return ArmyController
