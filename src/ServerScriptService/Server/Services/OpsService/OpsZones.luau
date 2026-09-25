--!strict
--[[
	OpsZones — who stands where, for job holds and participation (W3 step 2 Phase B, lane O; contract §4.3,
	activities §2.2). SERVER ONLY; server positions only.

	One sample per player per OpsService tick (4 Hz, Zones.TickSeconds), the BankRaidService pattern:
	  * root position, alive, seated (Humanoid.SeatPart ~= nil);
	  * under fire: a health drop seen within Zones.UnderFireSeconds (a respawn or regen raises health, never counts);
	  * teleport lockout: an on-foot root that moved more than Zones.TeleportStuds in one tick (a seated one more
	    than Zones.TeleportStudsSeated; scaled by the real tick length) resets that player's participation
	    everywhere (OnTeleport; a carried bag drops where they were) and locks them out for
	    Zones.TeleportLockoutSeconds. A new character (respawn) only re-bases the position.
	Presence test: flat XZ within r, root Y within Zones.MaxHeightDelta of the zone point (skipped for seated-allowed
	sites: a boat by the rig deck sits 26 studs below it).
	Allies: the same clan (ClanService.GetClanId, pcall'd); a player is always their own ally.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local OpsConfig = require(Shared.Configs.OpsConfig)

local Z = OpsConfig.Zones

local OpsZones = {}

export type Sample = {
	Root: BasePart?,
	Hum: Humanoid?,
	Pos: Vector3?,
	Alive: boolean,
	Seated: boolean,
	HurtAt: number,
	LockedUntil: number,
	LastHealth: number?,
	LastRoot: BasePart?,
}

local samples: { [number]: Sample } = {}
local ClanService: any = nil
local onTeleport: ((Player, Vector3?) -> ())? = nil

function OpsZones.Init(deps: { [string]: any }, teleportFn: (Player, Vector3?) -> ())
	ClanService = deps.ClanService
	onTeleport = teleportFn
end

local function blank(): Sample
	return { Root = nil, Hum = nil, Pos = nil, Alive = false, Seated = false, HurtAt = -math.huge, LockedUntil = -math.huge, LastHealth = nil, LastRoot = nil }
end

function OpsZones.Get(player: Player): Sample
	local s = samples[player.UserId]
	if s == nil then
		s = blank()
		samples[player.UserId] = s
	end
	return s
end

--[[ One sample of one player (the 4 Hz tick). dt = seconds since the last sample. ]]
function OpsZones.SamplePlayer(player: Player, nowC: number, dt: number)
	local s = OpsZones.Get(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and hum) then
		s.Root, s.Hum, s.Pos, s.Alive, s.Seated = nil, nil, nil, false, false
		s.LastHealth, s.LastRoot = nil, nil
		return
	end
	local pos = root.Position
	local seated = hum.SeatPart ~= nil
	-- teleport lockout (on foot only): participation reset + locked out. A new root (a respawn) re-bases without a
	-- lock, but a carried bag still drops where the old character stood (OpsService's callback).
	local prev = s.Pos
	local jumped = false
	if s.LastRoot == root and prev ~= nil then
		-- seated: a vehicle may go faster, but never TeleportStudsSeated in one tick (a client-owned vehicle moved into
		-- the own plot, or a server rescue while seated, is a teleport: the bag drops, the player is locked out)
		local base = if seated or s.Seated then (Z.TeleportStudsSeated or 150) else Z.TeleportStuds
		local limit = base * math.max(1, dt / Z.TickSeconds)
		local dx, dz = pos.X - prev.X, pos.Z - prev.Z
		if dx * dx + dz * dz > limit * limit then
			s.LockedUntil = nowC + Z.TeleportLockoutSeconds
			jumped = true
		end
	elseif s.LastRoot ~= nil and s.LastRoot ~= root and prev ~= nil then
		jumped = true -- a new character: no lock, but the old position is where a bag drops
	end
	if jumped and onTeleport then
		local ok, err = pcall(onTeleport :: any, player, prev)
		if not ok then
			warn("[Ops] teleport reset failed: " .. tostring(err))
		end
	end
	-- under fire: a health drop since the last sample (same humanoid only)
	local hp = hum.Health
	if s.Hum == hum and s.LastHealth ~= nil and hp < s.LastHealth - 0.01 then
		s.HurtAt = nowC
	end
	s.Root, s.Hum, s.Pos = root, hum, pos
	s.Alive = hp > 0
	s.Seated = seated
	s.LastHealth = hp
	s.LastRoot = root
end

function OpsZones.Forget(player: Player)
	samples[player.UserId] = nil
end

function OpsZones.UnderFire(player: Player, nowC: number): boolean
	local s = samples[player.UserId]
	if s == nil or not s.Alive then
		return true
	end
	return nowC - s.HurtAt < Z.UnderFireSeconds
end

function OpsZones.HitWithin(player: Player, nowC: number, seconds: number): boolean
	local s = samples[player.UserId]
	return s ~= nil and nowC - s.HurtAt < seconds
end

function OpsZones.Locked(player: Player, nowC: number): boolean
	local s = samples[player.UserId]
	return s ~= nil and nowC < s.LockedUntil
end

-- flat XZ within r of p, and within MaxHeightDelta in Y (unless ignoreY)
function OpsZones.Within(pos: Vector3, p: Vector3, r: number, ignoreY: boolean?): boolean
	local dx, dz = pos.X - p.X, pos.Z - p.Z
	if dx * dx + dz * dz > r * r then
		return false
	end
	return ignoreY == true or math.abs(pos.Y - p.Y) <= Z.MaxHeightDelta
end

-- flat XZ distance from pos to the nearest of pts (math.huge for none)
function OpsZones.Nearest(pos: Vector3, pts: { Vector3 }): number
	local best = math.huge
	for _, p in ipairs(pts) do
		local dx, dz = pos.X - p.X, pos.Z - p.Z
		local d = dx * dx + dz * dz
		if d < best then
			best = d
		end
	end
	return if best == math.huge then best else math.sqrt(best)
end

function OpsZones.NearAny(pos: Vector3, pts: { Vector3 }, r: number, ignoreY: boolean?): boolean
	for _, p in ipairs(pts) do
		if OpsZones.Within(pos, p, r, ignoreY) then
			return true
		end
	end
	return false
end

function OpsZones.ClanOf(player: Player): string?
	if ClanService == nil or ClanService.GetClanId == nil then
		return nil
	end
	local ok, id = pcall(ClanService.GetClanId, player)
	if ok and typeof(id) == "string" and id ~= "" then
		return id
	end
	return nil
end

-- same player, or both in one clan
function OpsZones.Allies(a: Player, b: Player): boolean
	if a == b then
		return true
	end
	local ca = OpsZones.ClanOf(a)
	return ca ~= nil and ca == OpsZones.ClanOf(b)
end

return OpsZones
