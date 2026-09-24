--!strict
--[[
	v69 ATM raids + Command Center missile strikes — ONE balance file for both.
	Read by MoneyCollectorService (raids), MissileStrikeService (strikes), GateDefenseService (defense fixes).
	Clients do not require this file (every number they show arrives in a remote payload).

	Timers that must survive leaving / rejoining / server hopping live on the profile as os.time() values:
	  profile.Raid.ShieldUntil          victim: no raids (and no strikes) until then
	  profile.Raid.RaidCooldownUntil    thief: next raid allowed at (new key; missing → 0)
	  profile.Raid.StrikeCooldownUntil  attacker: next missile allowed at
	  profile.Raid.DefensesDownUntil    victim: GateDefense guards/AutoGuns/gate are down until then
]]

local RaidConfig = {
	Raid = {
		Enabled = true,
		StealFraction = 0.10, -- owner rule: 10% of what is in the victim's ATM
		MinVictimBalance = 100, -- ATM must hold at least this much to be robbed
		MinSteal = 1,
		HoldSeconds = 6, -- stand at the victim's ATM this long: on foot, alive, not damaged
		RadiusStuds = 10, -- horizontal distance from the ATM body (same as the collect radius)
		MaxHeightDelta = 14,
		DamageCancelHp = 0.5, -- a health drop bigger than this between two ticks cancels the hold
		ShieldSeconds = 600, -- owner rule: the victim cannot be robbed again for 10 minutes
		ThiefCooldownSeconds = 60, -- per thief, after a successful raid (any victim)
		NewPlayerProtectionSeconds = 600, -- since profile.FirstJoinUnix
		ProtectNewPlayersInStudio = false, -- Studio test servers make fresh profiles every run
		RequireOnFoot = true, -- Humanoid.SeatPart must be nil
		AllowAllies = false, -- clan-mates cannot rob each other
		TeleportStuds = 60, -- HRP moved further than this in one 0.25 s tick (on foot, same character) → teleport
		TeleportLockoutSeconds = 15,
		AutoCollectCountsRecentIncome = true, -- AutoCollect is not raid immunity (see spec §1.5)
		AutoCollectWindowSeconds = 600,
		HoldPushInterval = 0.25, -- AtmRaidStateUpdate "Holding" cadence to the thief
		AlarmPushInterval = 1.0, -- "Alarm" cadence to the victim
		BlockedPushInterval = 3, -- same "Blocked" reason is re-sent at most this often
		VictimAlarmToastCooldown = 15,
	},

	Strike = {
		Enabled = true,
		-- "the upgrade": Command Center L3 + Missile Defense L1 (Missile Defense needs Radar L2 → CC L2)
		Unlock = { CommandCenter = 3, MissileDefense = 1 } :: { [string]: number },
		Cost = 5000,
		CooldownSeconds = 600, -- attacker, after a launch (profile.Raid.StrikeCooldownUntil)
		InterceptedCooldownSeconds = 300, -- attacker cooldown when the missile was shot down
		LaunchMaxDistanceFromCC = 45, -- server check: attacker HRP (horizontal) from own Command Center site
		MissileSpeed = 220, -- studs/s → flight = clamp(distance / speed, Min, Max)
		MinFlightSeconds = 5,
		MaxFlightSeconds = 9,
		ArcHeightMin = 150,
		ArcHeightFactor = 0.35, -- arc apex = clamp(distance * factor, Min, Max) above the chord midpoint
		ArcHeightMax = 400,
		DefensesDownSeconds = 120, -- at attacker CC L3
		DownBonusPerCCLevel = 30, -- per attacker CC level above 3 → L4 150 s, L5 180 s
		PostDownImmunitySeconds = 300, -- no new strike on a base until DefensesDownUntil + this
		-- victim Missile Defense level → chance the strike is shot down
		InterceptChanceByLevel = { [0] = 0, [1] = 0.15, [2] = 0.25, [3] = 0.35, [4] = 0.45, [5] = 0.55 } :: { [number]: number },
		PenetrationPerAttackerMDLevel = 0.05, -- per attacker MD level above 1 (L5 → −0.20)
		MaxInterceptChance = 0.75,
		InterceptAtMin = 0.72, -- interceptor meets the missile at this fraction of the flight (random in [min, max])
		InterceptAtMax = 0.84,
		RefundIfTargetLeaves = true,
		RequestRate = 2, -- RequestMissileStrike, all actions (tokens/s)
		RequestBurst = 4,
		LaunchRate = 0.5, -- "Launch" additionally
		LaunchBurst = 2,
	},

	Defense = {
		-- guards stand this far INSIDE the gate line (toward PlayerSpawn). Measured on the v68 map: guns at 7.5 keep
		-- 4.35 studs off the L5 wall face (half-thickness 3.15) and clear the checkpoint boom post; guards at 10
		-- stand clear of the gun tripods and the booth / jersey barriers (spec had 8 / 7: guns 3.85 from the L5 wall)
		GuardPostInsideStuds = 10,
		AutoGunInsideStuds = 7.5,
		GateOpenRadius = 12, -- an ally within this (horizontal) of the gate centre opens the barrier
		GateOpenHeight = 12,
		GateCloseDelay = 1.0,
		LosRespectCanCollide = true, -- guard/AutoGun line of sight ignores non-collidable decor
		EngageIntrudersInsideWalls = true, -- any non-ally inside the plot walls is in aggro
		GuardHitMaxDistance = 150, -- weapon hits on guards: attacker HRP within this of the guard
		ResearchStat = "TurretDamage", -- ResearchService.GetBonus(owner, stat) × guard + AutoGun damage
		MaxResearchMult = 5,
	},

	Text = {
		-- raids (thief)
		RaidHolding = "ROBBING %s's ATM · %.1f/%ds — don't get hit!",
		RaidSuccess = "ATM RAID +$%s from %s → your ATM",
		RaidHit = "Hit! Raid interrupted — clear the defenders first",
		RaidLeft = "Left the ATM — raid cancelled",
		RaidVictimLeft = "The owner left the server",
		RaidEmptied = "The owner emptied the ATM",
		RaidDead = "You went down — raid cancelled",
		RaidHint = "Stand on %s's ATM for %ds to rob it — don't get hit",
		-- raids (victim)
		RaidAlarm = "⚠ %s is robbing your ATM!",
		RaidRobbed = "ATM RAIDED by %s −$%s · 🛡 shield %s",
		RaidDefended = "Raid on your ATM stopped",
		-- raid blocked reasons
		Blocked = {
			Disabled = "Raids are switched off",
			Ally = "Clan ally's ATM — can't rob allies",
			NoBase = "Get a base first — loot goes to your ATM",
			ThiefLoading = "Your save is still loading",
			VictimLoading = "Their save is still loading",
			Shielded = "🛡 Robbed recently — shielded %s",
			NewPlayer = "New player protection — %s",
			LowBalance = "ATM almost empty ($%s)",
			ThiefCooldown = "Raid cooldown %s",
			Seated = "Get out of the vehicle to rob the ATM",
			Teleport = "Raid blocked — moved too fast",
		} :: { [string]: string },
		-- strikes
		StrikeLocked = "Needs Command Center L%d + Missile Defense L%d",
		StrikeLaunched = "Missile away → %s · impact %ds",
		StrikeHit = "Direct hit! %s's defenses down %s — go raid!",
		StrikeIntercepted = "Intercepted by %s's Missile Defense",
		StrikeRefunded = "%s left — missile refunded",
		StrikeIncoming = "⚠ INCOMING MISSILE from %s — impact %ds",
		StrikeVictimHit = "💥 Missile hit! Defenses down %s — protect your ATM!",
		StrikeVictimIntercepted = "✓ Your Missile Defense shot down %s's missile",
		DefensesBack = "Defenses back online",
		StrikeReasons = {
			Locked = "Needs Command Center L3 + Missile Defense L1",
			NotAtCommandCenter = "Use the Missile Command terminal in your Command Center",
			NoBase = "You need a base",
			Loading = "Your save is still loading",
			Cooldown = "Reloading — %s",
			InFlight = "Your missile is still in the air",
			InsufficientCash = "Need $%s",
			Self = "That's your base",
			Ally = "Clan ally",
			TargetOffline = "Player left",
			TargetLoading = "Their save is still loading",
			NewPlayer = "New player protection — %s",
			Shielded = "🛡 Shielded %s",
			AlreadyDown = "Defenses already down %s",
			Recovering = "Defenses rebooting — %s",
			Incoming = "Another missile is inbound",
			NoDefenses = "No defenses to hit — just raid the ATM",
			Busy = "Too fast — try again",
			Disabled = "Missile strikes are switched off",
		} :: { [string]: string },
	},
}

-- "m:ss" for countdowns (0 → "0:00")
function RaidConfig.FormatTime(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- Chance (0..MaxInterceptChance) that a strike from an attacker with Missile Defense `attackerMd` is shot down
-- by a victim with Missile Defense `victimMd`.
function RaidConfig.InterceptChance(victimMd: number, attackerMd: number): number
	local s = RaidConfig.Strike
	local lv = math.clamp(math.floor(victimMd), 0, 5)
	local base = s.InterceptChanceByLevel[lv] or 0
	local pen = math.max(0, math.floor(attackerMd) - 1) * s.PenetrationPerAttackerMDLevel
	return math.clamp(base - pen, 0, s.MaxInterceptChance)
end

-- Seconds a hit keeps the target's defenses down, from the attacker's Command Center level.
function RaidConfig.DownSeconds(attackerCc: number): number
	local s = RaidConfig.Strike
	local above = math.max(0, math.floor(attackerCc) - s.Unlock.CommandCenter)
	return s.DefensesDownSeconds + above * s.DownBonusPerCCLevel
end

function RaidConfig.FlightSeconds(distance: number): number
	local s = RaidConfig.Strike
	return math.clamp(distance / s.MissileSpeed, s.MinFlightSeconds, s.MaxFlightSeconds)
end

function RaidConfig.ArcHeight(distance: number): number
	local s = RaidConfig.Strike
	return math.clamp(distance * s.ArcHeightFactor, s.ArcHeightMin, s.ArcHeightMax)
end

return RaidConfig
