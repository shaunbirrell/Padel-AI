--!strict
--[[ W2 Combat Core (contracts §2.1–§2.2): WeaponFx fan-out (UnreliableRemoteEvent, server → client, cosmetic).

	One small table per event (Types.WeaponFxPayload), sent with FireClient to every player whose HumanoidRootPart is
	within CombatFeelConfig.Fx.RadiusStuds of the event's origin O or end point P.
	  - Bullets ("P"/"N"/"V"/"G"/"W"/"M"): leave out the shooter (the client predicts its own shots); per-shooter
	    token bucket PerShooterHz / PerShooterBurst (players by UserId, NPCs by record id).
	  - Projectile launch "L" / explosion "X": include the shooter; exempt from the shooter bucket (the weapon fire
	    rate bounds them at <= 0.5/s).
	  - Every recipient: token bucket PerRecipientHz / PerRecipientBurst.
	Over a cap the event is dropped, never queued. Every send is pcall'd: a missing remote drops the effect, never
	the shot.
	army lane A0 (ArmyConfig.ShotFx): ArmyBullet sends a squad unit's shot for a live owner's army (S = 0, W = "NPC":
	the NPC rifle look), at most one per army per MinGap s, through a per-army shooter bucket and an army bucket per
	recipient (checked before the recipient bucket above). Its own tables and ArmyStats(); Forget(userId) clears them. ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local Constants = require(Shared.Constants)
local Types = require(Shared.Types)
local CombatFeelConfig = require(Shared.Configs.CombatFeelConfig)

local CombatFx = {}

export type Bindings = {
	getRemote: () -> Instance?, -- RemoteSetup.GetUnreliable(WeaponFx) (pcall'd here)
	clock: () -> number,
}

type Bucket = { Tokens: number, At: number }

local B: Bindings? = nil
local shooterBuckets: { [any]: Bucket } = {}
local recipientBuckets: { [number]: Bucket } = {}
local cachedRemote: Instance? = nil
local stats = { Sent = 0, Events = 0, DroppedShooter = 0, DroppedRecipient = 0, Failed = 0 }
local serial = 0
-- army lane A0: squad unit shot fx (ArmyBullet), keyed by the owner's UserId; separate from the tables above
local army = {
	sampleAt = {} :: { [number]: number }, -- owner UserId -> the last event sent for his army (the PerArmyMinGap sampler)
	shooter = {} :: { [number]: Bucket }, -- owner UserId -> the army's shooter bucket (CombatFeelConfig.Fx.PerShooterHz)
	recipient = {} :: { [number]: Bucket }, -- recipient UserId -> the army bucket (ArmyConfig.ShotFx.PerRecipientHz)
	stats = { Events = 0, Sampled = 0, DroppedShooter = 0, DroppedRecipient = 0, Sent = 0 },
}

function CombatFx.Bind(bindings: Bindings)
	B = bindings
end

local function now(): number
	local b = B
	return if b then b.clock() else os.clock()
end

local function take(buckets: { [any]: Bucket }, key: any, hz: number, burst: number, t: number): boolean
	local b = buckets[key]
	if b == nil then
		b = { Tokens = burst, At = t }
		buckets[key] = b
	else
		local dt = t - b.At
		if dt > 0 then
			b.Tokens = math.min(burst, b.Tokens + dt * hz)
		end
		b.At = t
	end
	if b.Tokens >= 1 then
		b.Tokens -= 1
		return true
	end
	return false
end

local function remote(): Instance?
	local r = cachedRemote
	if r and r.Parent then
		return r
	end
	cachedRemote = nil
	local b = B
	if b == nil then
		return nil
	end
	local ok, got = pcall(b.getRemote)
	if ok and typeof(got) == "Instance" and (got :: Instance):IsA("UnreliableRemoteEvent") then
		cachedRemote = got
		return got
	end
	return nil
end

-- `armyHz` / `armyBurst` (army lane A0, ArmyBullet only): each recipient first spends a token of its army bucket
local function fanOut(payload: Types.WeaponFxPayload, excludeUid: number?, armyHz: number?, armyBurst: number?)
	local r = remote()
	if r == nil then
		stats.Failed += 1
		return
	end
	local fx = CombatFeelConfig.Fx
	local r2 = fx.RadiusStuds * fx.RadiusStuds
	local o, p = payload.O, payload.P
	local t = now()
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.UserId ~= excludeUid then
			local char = plr.Character
			local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
			if root and root:IsA("BasePart") then
				local pos = root.Position
				local dO, dP = pos - o, pos - p
				if dO:Dot(dO) <= r2 or dP:Dot(dP) <= r2 then
					if armyHz ~= nil and not take(army.recipient, plr.UserId, armyHz, armyBurst or 1, t) then
						army.stats.DroppedRecipient += 1 -- army lane A0: this recipient's army bucket is empty
					elseif take(recipientBuckets, plr.UserId, fx.PerRecipientHz, fx.PerRecipientBurst, t) then
						local ok = pcall(function()
							(r :: any):FireClient(plr, payload)
						end)
						if ok then
							stats.Sent += 1
							if armyHz ~= nil then
								army.stats.Sent += 1
							end
						else
							stats.Failed += 1
						end
					else
						stats.DroppedRecipient += 1
					end
				end
			end
		end
	end
end

--[[ One bullet event. `shooterKey` is the player's UserId (players) or the NPC record id (NPCs, S = 0).
	Returns false when the shooter bucket dropped it. ]]
function CombatFx.Bullet(shooterKey: any, shooterUid: number, weaponId: string, origin: Vector3, landed: Vector3, kind: string): boolean
	local fx = CombatFeelConfig.Fx
	if not take(shooterBuckets, shooterKey, fx.PerShooterHz, fx.PerShooterBurst, now()) then
		stats.DroppedShooter += 1
		return false
	end
	stats.Events += 1
	local payload: Types.WeaponFxPayload = { S = shooterUid, W = weaponId, O = origin, P = landed, K = kind }
	fanOut(payload, if shooterUid ~= 0 then shooterUid else nil)
	return true
end

--[[ army lane A0 (ArmyConfig.ShotFx): one squad unit shot of `ownerUid`'s army, from `origin` (the unit's eye) to
	`landed`, kind "N" (hit) or "M" (miss). Sent as an NPC shot (S = 0, W = "NPC") to every player near either end,
	the owner included. Returns false when sampled out (another event of this army less than `minGap` s ago) or
	dropped by the army's shooter bucket; per recipient, the army bucket (`recipientHz`, `recipientBurst`) then the
	CombatFx recipient bucket may drop it. Never queued. ]]
function CombatFx.ArmyBullet(ownerUid: number, origin: Vector3, landed: Vector3, kind: string, minGap: number, recipientHz: number, recipientBurst: number): boolean
	local t = now()
	local last = army.sampleAt[ownerUid]
	if last ~= nil and t - last < minGap then
		army.stats.Sampled += 1
		return false
	end
	army.sampleAt[ownerUid] = t
	local fx = CombatFeelConfig.Fx
	if not take(army.shooter, ownerUid, fx.PerShooterHz, fx.PerShooterBurst, t) then
		army.stats.DroppedShooter += 1
		return false
	end
	army.stats.Events += 1
	stats.Events += 1
	local payload: Types.WeaponFxPayload = { S = 0, W = "NPC", O = origin, P = landed, K = kind }
	fanOut(payload, nil, recipientHz, recipientBurst)
	return true
end

-- army lane A0: ArmyBullet counters (Events sent, Sampled out, DroppedShooter, DroppedRecipient, Sent to recipients)
function CombatFx.ArmyStats(): { [string]: number }
	return table.clone(army.stats)
end

function CombatFx.ResetArmyStats()
	local st = army.stats
	st.Events = 0
	st.Sampled = 0
	st.DroppedShooter = 0
	st.DroppedRecipient = 0
	st.Sent = 0
end

-- Projectile serial shared by one projectile's "L" and "X" events
function CombatFx.NextSerial(): number
	serial = (serial % 1000000) + 1
	return serial
end

-- Projectile launch "L" (shooter included). `gravityFactor` (aircraft bombs) rides in G for weapon ids the client's
-- WeaponConfig does not know; nil for every infantry projectile (the client reads their GravityFactor itself).
function CombatFx.Launch(shooterUid: number, weaponId: string, origin: Vector3, velocity: Vector3, maxSeconds: number, id: number, gravityFactor: number?)
	stats.Events += 1
	local g = if typeof(gravityFactor) == "number" and gravityFactor > 0 then gravityFactor else nil
	fanOut({ S = shooterUid, W = weaponId, O = origin, P = origin, K = "L", R = true, I = id, V = velocity, T = maxSeconds, G = g }, nil)
end

-- Projectile explosion "X" (shooter included). `origin` is the launch point (recipients near either end get it).
function CombatFx.Explode(shooterUid: number, weaponId: string, origin: Vector3, at: Vector3, radius: number, id: number)
	stats.Events += 1
	fanOut({ S = shooterUid, W = weaponId, O = origin, P = at, K = "X", R = true, I = id, D = radius }, nil)
end

function CombatFx.Forget(key: any)
	shooterBuckets[key] = nil
	if typeof(key) == "number" then
		recipientBuckets[key] = nil
		army.sampleAt[key] = nil -- army lane A0: his army's sampler / shooter bucket, his army recipient bucket
		army.shooter[key] = nil
		army.recipient[key] = nil
	end
end

function CombatFx.Stats(): { [string]: number }
	return table.clone(stats)
end

function CombatFx.ResetStats()
	stats.Sent = 0
	stats.Events = 0
	stats.DroppedShooter = 0
	stats.DroppedRecipient = 0
	stats.Failed = 0
end

CombatFx.RemoteName = Constants.RemoteNames.WeaponFx

return CombatFx
