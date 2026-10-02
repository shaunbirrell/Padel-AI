--!strict
--[[
	claude-bud JOB 35 (2026-09-30): the optional gun mechanics of WeaponConfig (nil = unchanged for every existing
	gun). Pure functions, shared: the SERVER decides (CombatService.RequestFire), the client runs the same rules only to
	pace its own visuals.
	  * Burst { Count, Gap }: one trigger cycle fires Count shots Gap seconds apart; FireRate = cycles per second.
	  * SpinUp (s): the trigger going down sends a "Spin" prime (no shot); shots are refused until the barrel has spun
	    SpinUp seconds, and it stays warm while the gun keeps firing (SpinKeep).
	  * ChargeSeconds (s): the trigger going down sends a "Charge" prime; the shot (on release) needs that much charge.
	    One charge = one shot.
	  * Pierce (n): a hitscan shot hits up to n players / NPCs in a line (CombatService re-casts past each body).
	  * HeadshotMult: this gun's headshot multiplier (nil = CombatFeelConfig.HeadshotMult).
	Tolerance: primes arrive before shots over the same ordered remote; Tolerance absorbs send jitter only.
]]

export type State = {
	LastShotAt: number,
	BurstShots: number,
	SpinAt: number?,
	ChargeAt: number?,
}

local GunMechanics = {
	Tolerance = 0.8, -- a spin / charge counts once 80 % of it has passed (ping jitter), never less
	SpinKeep = 0.35, -- seconds without a shot before a spun barrel needs a new spin-up
	SpinPrimeTtl = 2.5, -- a spin prime with no shot after SpinUp + this is stale
	ChargeHoldMax = 6, -- a charge held longer than ChargeSeconds + this is dropped (no infinite pre-charge)
}

function GunMechanics.New(): State
	return { LastShotAt = -math.huge, BurstShots = 0, SpinAt = nil, ChargeAt = nil }
end

-- "Spin" / "Charge" when this gun needs a trigger-down prime, else nil
function GunMechanics.PrimeKind(def: any): string?
	if typeof(def) ~= "table" then
		return nil
	end
	if (tonumber(def.SpinUp) or 0) > 0 then
		return "Spin"
	end
	if (tonumber(def.ChargeSeconds) or 0) > 0 then
		return "Charge"
	end
	return nil
end

-- record a prime; false when this gun does not take that kind (ignored, no strike)
function GunMechanics.Prime(def: any, st: State, now: number, kind: any): boolean
	if kind == "Spin" and (tonumber(def.SpinUp) or 0) > 0 then
		if now - st.LastShotAt > GunMechanics.SpinKeep then
			st.SpinAt = now -- a warm barrel keeps its spin; a cold one starts spinning now
		end
		return true
	end
	if kind == "Charge" and (tonumber(def.ChargeSeconds) or 0) > 0 then
		st.ChargeAt = now
		return true
	end
	return false
end

-- may this gun fire now? (false, "Spin" | "Charge") = still spinning up / not charged
function GunMechanics.Ready(def: any, st: State, now: number): (boolean, string?)
	local spin = tonumber(def.SpinUp) or 0
	if spin > 0 then
		local warm = now - st.LastShotAt <= GunMechanics.SpinKeep
		local at = st.SpinAt
		if not warm and at ~= nil then
			local since = now - at
			warm = since >= spin * GunMechanics.Tolerance and since <= spin + GunMechanics.SpinPrimeTtl
		end
		if not warm then
			return false, "Spin"
		end
	end
	local charge = tonumber(def.ChargeSeconds) or 0
	if charge > 0 then
		local at = st.ChargeAt
		if at == nil then
			return false, "Charge"
		end
		local since = now - at
		if since < charge * GunMechanics.Tolerance or since > charge + GunMechanics.ChargeHoldMax then
			return false, "Charge"
		end
	end
	return true, nil
end

local function inBurst(def: any, st: State, now: number): boolean
	local b = def.Burst
	if typeof(b) ~= "table" then
		return false
	end
	local count = math.max(1, math.floor(tonumber(b.Count) or 1))
	local gap = math.max(0.02, tonumber(b.Gap) or 0.1)
	return st.BurstShots > 0 and st.BurstShots < count and now - st.LastShotAt <= gap * 4
end

-- the minimum interval before this shot: Burst.Gap inside a burst, else `base` (1 / FireRate)
function GunMechanics.Interval(def: any, st: State, now: number, base: number): number
	if inBurst(def, st, now) then
		return math.max(0.02, tonumber(def.Burst.Gap) or 0.1)
	end
	return base
end

-- an accepted shot
function GunMechanics.OnShot(def: any, st: State, now: number)
	if typeof(def.Burst) == "table" then
		st.BurstShots = if inBurst(def, st, now) then st.BurstShots + 1 else 1
	end
	st.LastShotAt = now
	if (tonumber(def.ChargeSeconds) or 0) > 0 then
		st.ChargeAt = nil
	end
end

-- how many players / NPCs one hitscan shot may hit
function GunMechanics.MaxTargets(def: any): number
	return math.clamp(math.floor(tonumber(def.Pierce) or 1), 1, 5)
end

-- damage per second at full rate (tests / balance notes): Burst and Pellets included, charge time added per shot
function GunMechanics.Dps(def: any): number
	local dmg = (tonumber(def.Damage) or 0) * math.max(1, tonumber(def.Pellets) or 1)
	local base = 1 / math.max(0.1, tonumber(def.FireRate) or 1)
	local b = def.Burst
	if typeof(b) == "table" then
		local count = math.max(1, math.floor(tonumber(b.Count) or 1))
		local gap = tonumber(b.Gap) or 0.1
		return dmg * count / ((count - 1) * gap + base)
	end
	local charge = tonumber(def.ChargeSeconds) or 0
	return dmg / math.max(base, charge)
end

return GunMechanics
