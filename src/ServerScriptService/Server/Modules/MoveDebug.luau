--!strict
--[[
	v123 MoveDebug (Code Bot): the player-movement investigation for "running on a phone, he stops dead while his army is
	behind, then moves again once it catches up". Quiet unless the player's WE_MoveDebug attribute is true (/movedebug,
	admin allowlist). Design rule it guards: nothing ever stops, slows, freezes, anchors, repositions or body-blocks a
	PLAYER because his army is behind; the army adapts.

	Tagged writers: every server write to a player's Humanoid.WalkSpeed or a player character's PivotTo goes through
	MoveDebug.SetWalkSpeed / MoveDebug.PivotChar (or MoveDebug.Note next to it), so a log names WHO wrote it last.
	Watchers (every player, cheap, event driven): Humanoid WalkSpeed / JumpPower / JumpHeight / PlatformStand / Sit,
	root Anchored, and a mover / constraint / weld reaching out of the character are noted with the last tagged writer
	(or "unknown"). His parts outside WE_PlayerChars are listed by the sampler.
	Sampler (only players with WE_MoveDebug, 4 Hz, one summary line per second): network owner of his root (NOT him =
	[MOVEMENT OWNER LOST]: his phone can no longer move him), AssemblyRootPart (welded to something else), Anchored,
	WalkSpeed, Sit / PlatformStand, horizontal speed, parts outside WE_PlayerChars, and his army: order, units,
	nearest / centre distance, units within 6 studs, units CatchingUp, and any soldier part that could collide with him.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")

local MoveDebug = {}

MoveDebug.Attr = "WE_MoveDebug"
MoveDebug.PlayerGroup = "WE_PlayerChars"
MoveDebug.ArmyGroup = "ArmyNPCs"
MoveDebug.Stats = { Notes = 0, Samples = 0, OwnerLost = 0, Welded = 0, SoldierCollidable = 0 }

type Write = { T: number, What: string, Who: string }

local RING = 8
local writes: { [number]: { Write } } = {}
local deps: { [string]: any } = {}
local started = false
local lastSummaryAt: { [number]: number } = {}
local lastWarnAt: { [string]: number } = {}

local MOVER_CLASSES: { [string]: boolean } = {
	AlignPosition = true, AlignOrientation = true, LinearVelocity = true, VectorForce = true, BodyPosition = true,
	BodyVelocity = true, BodyGyro = true, BodyForce = true, BodyThrust = true, RocketPropulsion = true,
	BodyAngularVelocity = true, AngularVelocity = true, LineForce = true, Torque = true, PlaneConstraint = true,
	RopeConstraint = true, RodConstraint = true, SpringConstraint = true, BallSocketConstraint = true,
	WeldConstraint = true, Weld = true, ManualWeld = true, Motor6D = true, NoCollisionConstraint = false,
}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function playerOf(x: any): Player?
	if typeof(x) ~= "Instance" then
		return nil
	end
	if x:IsA("Player") then
		return x
	end
	local model: Instance? = if x:IsA("Model") then x else x:FindFirstAncestorOfClass("Model")
	while model do
		local p = Players:GetPlayerFromCharacter(model)
		if p then
			return p
		end
		model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model")
	end
	return nil
end

function MoveDebug.On(player: Player): boolean
	return player:GetAttribute(MoveDebug.Attr) == true
end

local function warnOnce(key: string, every: number, msg: string)
	local now = os.clock()
	if now - (lastWarnAt[key] or -math.huge) >= every then
		lastWarnAt[key] = now
		warn(msg)
	end
end

-- a tagged write on a PLAYER (character / humanoid / part / player): kept in his ring, printed while he debugs
function MoveDebug.Note(target: any, what: string, who: string)
	local p = playerOf(target)
	if p == nil then
		return
	end
	MoveDebug.Stats.Notes += 1
	local r = writes[p.UserId]
	if r == nil then
		r = {}
		writes[p.UserId] = r
	end
	table.insert(r, { T = os.clock(), What = what, Who = who })
	if #r > RING then
		table.remove(r, 1)
	end
	if MoveDebug.On(p) then
		print(string.format("[MoveDebug] WRITE %s %s by %s", p.Name, what, who))
	end
end

-- the ONE server setter for a player's WalkSpeed (tagged)
function MoveDebug.SetWalkSpeed(hum: Humanoid, value: number, who: string)
	MoveDebug.Note(hum, string.format("WalkSpeed=%.1f", value), who)
	hum.WalkSpeed = value
end

-- the ONE server mover of a player character (tagged): teleports only (respawn / base / fall rescue / vehicle exit)
function MoveDebug.PivotChar(char: Model, cf: CFrame, who: string)
	MoveDebug.Note(char, "PivotTo", who)
	char:PivotTo(cf)
end

function MoveDebug.LastWrites(player: Player): string
	local r = writes[player.UserId]
	if r == nil or #r == 0 then
		return "none"
	end
	local now = os.clock()
	local parts = {}
	for i = #r, math.max(1, #r - 4), -1 do
		local w = r[i]
		table.insert(parts, string.format("%s<-%s %.1fs ago", w.What, w.Who, now - w.T))
	end
	return table.concat(parts, "; ")
end

local function lastWho(player: Player): string
	local r = writes[player.UserId]
	if r and #r > 0 and os.clock() - r[#r].T < 1 then
		return r[#r].Who
	end
	return "unknown"
end

-- can a part in `group` touch a player character (WE_PlayerChars)?
local function collidesWithPlayers(group: string): boolean
	local ok, c = pcall(function()
		return PhysicsService:CollisionGroupsAreCollidable(group, MoveDebug.PlayerGroup)
	end)
	return ok and c == true
end
MoveDebug.CollidesWithPlayers = collidesWithPlayers

local function watchCharacter(player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid", 10)
	if not (hum and hum:IsA("Humanoid")) then
		return
	end
	local h = hum :: Humanoid
	for _, prop in ipairs({ "WalkSpeed", "JumpPower", "JumpHeight", "PlatformStand", "Sit" }) do
		h:GetPropertyChangedSignal(prop):Connect(function()
			local v = (h :: any)[prop]
			local r = writes[player.UserId]
			local tagged = r and #r > 0 and os.clock() - r[#r].T < 0.05
			if not tagged then
				MoveDebug.Note(player, string.format("%s->%s", prop, tostring(v)), "untagged:" .. lastWho(player))
			end
		end)
	end
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if root and root:IsA("BasePart") then
		root:GetPropertyChangedSignal("Anchored"):Connect(function()
			MoveDebug.Note(player, "root.Anchored->" .. tostring((root :: BasePart).Anchored), lastWho(player))
		end)
	end
	char.DescendantAdded:Connect(function(d)
		if MOVER_CLASSES[d.ClassName] == true then
			-- a joint inside his own rig is normal; one that reaches OUT of the character (or any mover) is logged
			local out = false
			if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
				local a: any = d
				local p0, p1 = a.Part0, a.Part1
				out = (p0 ~= nil and not p0:IsDescendantOf(char)) or (p1 ~= nil and not p1:IsDescendantOf(char))
			else
				out = true
			end
			if out then
				MoveDebug.Note(player, "added " .. d.ClassName .. " " .. d:GetFullName(), lastWho(player))
			end
		end
	end)
end

local function unitState(u: any): string
	return tostring(u._scState or u.MoveState or "?")
end

-- one sample of one debugging player
local function sample(player: Player, now: number)
	MoveDebug.Stats.Samples += 1
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (char and root and root:IsA("BasePart") and hum) then
		return
	end
	local r = root :: BasePart
	local h = hum :: Humanoid
	local okO, owner = pcall(function()
		return r:GetNetworkOwner()
	end)
	local ownerName = if okO then (if owner then owner.Name else "SERVER") else "?"
	if okO and owner ~= player and h.Health > 0 and h.SeatPart == nil then
		MoveDebug.Stats.OwnerLost += 1
		warnOnce("own" .. player.UserId, 1, string.format("[MOVEMENT OWNER LOST] %s root owner=%s assemblyRoot=%s last=%s", player.Name, ownerName, r.AssemblyRootPart and r.AssemblyRootPart:GetFullName() or "nil", MoveDebug.LastWrites(player)))
	end
	local ar = r.AssemblyRootPart
	if ar and ar ~= r and not ar:IsDescendantOf(char) and h.SeatPart == nil then
		MoveDebug.Stats.Welded += 1
		warnOnce("weld" .. player.UserId, 1, string.format("[MOVEMENT WELDED] %s is in the assembly of %s", player.Name, ar:GetFullName()))
	end
	-- his parts outside WE_PlayerChars (would collide with soldiers)
	local stray = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and d.CanCollide and d.CollisionGroup ~= MoveDebug.PlayerGroup then
			table.insert(stray, d.Name .. "@" .. d.CollisionGroup)
			if #stray >= 3 then
				break
			end
		end
	end
	-- his army
	local armyTxt = "army=none"
	local squads = deps.Squads and deps.Squads() or nil
	local st = squads and squads[player.UserId]
	local soldierCollide = {}
	if st and st.Units then
		local n, near6, catching, sum = 0, 0, 0, Vector3.zero
		local nearest = math.huge
		for _, u in ipairs(st.Units) do
			local ur = u.Root
			if u.Alive ~= false and ur and ur.Parent then
				n += 1
				local d = flat(ur.Position - r.Position).Magnitude
				nearest = math.min(nearest, d)
				sum += ur.Position
				if d < 6 then
					near6 += 1
				end
				if unitState(u) == "CatchingUp" then
					catching += 1
				end
				if d < 12 and #soldierCollide < 3 then
					for _, p in ipairs(u.Model:GetDescendants()) do
						if p:IsA("BasePart") and p.CanCollide and collidesWithPlayers(p.CollisionGroup) then
							table.insert(soldierCollide, u.Model.Name .. "." .. p.Name .. "@" .. p.CollisionGroup)
							break
						end
					end
				end
			end
		end
		local centre = if n > 0 then flat(sum / n - r.Position).Magnitude else 0
		armyTxt = string.format("army=%s units=%d nearest=%.1f centre=%.1f within6=%d catchingUp=%d", tostring(st.Order), n, if n > 0 then nearest else -1, centre, near6, catching)
	end
	if #soldierCollide > 0 then
		MoveDebug.Stats.SoldierCollidable += 1
		warnOnce("sc" .. player.UserId, 2, "[MOVEMENT SOLDIER CAN COLLIDE] " .. player.Name .. ": " .. table.concat(soldierCollide, ", "))
	end
	if now - (lastSummaryAt[player.UserId] or -math.huge) >= 1 then
		lastSummaryAt[player.UserId] = now
		print(string.format(
			"[MoveDebug] S %s spd=%.1f ws=%.1f sit=%s ps=%s anch=%s owner=%s asm=%s group=%s stray=%s %s last=%s",
			player.Name, flat(r.AssemblyLinearVelocity).Magnitude, h.WalkSpeed, tostring(h.Sit), tostring(h.PlatformStand),
			tostring(r.Anchored), ownerName, if ar == r then "self" else (if ar then ar.Name else "nil"), r.CollisionGroup,
			if #stray > 0 then table.concat(stray, ",") else "0", armyTxt, MoveDebug.LastWrites(player)))
	end
end

-- deps: Squads() -> { [userId]: st }
function MoveDebug.Start(d: { [string]: any }?)
	if d then
		for k, v in pairs(d) do
			deps[k] = v
		end
	end
	if started then
		return
	end
	started = true
	local function onPlayer(p: Player)
		if p.Character then
			task.spawn(watchCharacter, p, p.Character)
		end
		p.CharacterAdded:Connect(function(c)
			watchCharacter(p, c)
		end)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(p)
		writes[p.UserId] = nil
		lastSummaryAt[p.UserId] = nil
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.25 then
			return
		end
		acc = 0
		local now = os.clock()
		for _, p in ipairs(Players:GetPlayers()) do
			if MoveDebug.On(p) then
				local ok, err = pcall(sample, p, now)
				if not ok then
					warnOnce("err", 10, "[MoveDebug] sample error: " .. tostring(err))
				end
			end
		end
	end)
end

return MoveDebug
