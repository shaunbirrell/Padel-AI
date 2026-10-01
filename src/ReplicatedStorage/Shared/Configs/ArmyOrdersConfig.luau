--!strict
--[[
	claude-bud JOB 38 (2026-09-30): ARMY ATTACK ORDERS (docs/claude-queue/JOB38-army-attack-orders.md). Every number here;
	the fairness rules (Fairness) are DECIDED by the owner (2026-09-30), defaults unchanged.
	  1. ATTACK = auto-clear: seek the nearest hostile group within SeekRadius of the owner, march there as the SAME steered
	     block (the formation follows the plan's lead point instead of the owner), fight until the group is gone, chain to
	     the next within ChainRadius (MaxChain per order), then return and fold into FOLLOW.
	  2. SEND: the army walks to another online player's base (no teleport, no fast travel), sieges it in Siege.Priority
	     order, breaches the gate through the existing gate path, holds the ATM (Raid.HoldSeconds, not hit) and loots
	     StealFraction x ArmyLootMult into the sender's ATM, then walks home.
	  3. Fairness (server-side, at the request and during the plan): shield, new player / novice shield, online only, the
	     sender cooldown, the victim's army protection, allies never, no PvP-off server, the power verdict.
	  4. Turret HP (AutoGuns can be shot down, then rebuild) behind TurretHP.Enabled; players and armies alike.
	  5. The ARMY KILLS board replaces TOP ARMY once this is live for everyone.
	Kill switch: Live (RetentionConfig.Live rule: OwnerFirst = UserId 470626172 + Studio). Off / not live for the owner =
	today's Follow / Attack / Hold / Retreat exactly (the JOB 24 attack, leash 140), no SEND, no new UI, turrets without HP.
]]

local ArmyOrdersConfig = {
	Live = {
		Enabled = true,
		OwnerFirst = false, -- codebot_v166 flip-all-live (owner 2026-10-01 10:31): everyone
	},

	-- 1. ATTACK auto-clear
	SeekRadius = 250, -- studs from the owner for the first target group
	ChainRadius = 150, -- studs from the army for the next group
	MaxChain = 4, -- target groups per ATTACK order
	SeekLeash = 300, -- the owner leash while auto-clearing (was AttackLeashStuds 140); beyond it: finish, then return
	ArriveStuds = 40, -- the block centre this close to the target group: FIGHT (the AttackStandoff deploy takes over)
	ReturnDoneStuds = 25, -- back within this of the owner: the plan ends, FOLLOW
	FightGiveUpSeconds = 60, -- a fight with no damage dealt / no progress for this long: the group counts as out of reach

	-- the march (the lead point the block follows; the formation standard is Follow3's)
	MarchSpeed = 14, -- studs/s: the lead point's speed (the block slows for its slowest soldier)
	LeadMaxGap = 18, -- the lead point waits while the block centre is this far behind it
	RepathSeconds = 2, -- at most one re-plan per army per this many seconds
	LegStuds = 400, -- the route is planned in legs of at most this length
	RouteRetries = 3, -- failed plans before "No route" (the army holds; no teleport fallback)
	PathBudgetPerSecond = 2, -- route computes per second, server-wide (PathfindingService)
	StuckSeconds = 6, -- the lead point without block progress this long: re-plan the leg
	RoutingTimeoutSeconds = 20, -- v165: a path request still outstanding this long is asked again (the march never hangs)
	MarchAnswerStuds = 60, -- v165: on the march only a player who hurt him / his soldiers, within this of the block, is answered
	MarchAnswerSeconds = 10, -- ... in the last this many seconds (CombatService.RecentlyHurtBy)
	LostStuds = 90, -- a unit this far from the block for LostSeconds is marked LOST (reported, never moved)
	LostSeconds = 15,

	-- Code Bot (army command bug, 2026-10-01): the ONE command path (Server/Modules/ArmyCommand + ArmyState)
	-- SEND to a map area / site (ArmyTargets "A:<id>" / "S:<id>"): the block walks to the target's APPROACH POINT
	-- (Approach[id] when set, else ApproachExtraStuds outside the objective where a road enters it), clears the hostiles
	-- within EngageExtraStuds of the objective (EngagingTarget), then HOLDS there. Capture stays the player's
	-- (TerritoryCapture counts players only): the army clears the defenders and guards the spot.
	Travel = {
		ApproachExtraStuds = 30, -- the approach ring: this far outside the objective's radius (Central Plaza: 70 + 30)
		AreaRadiusCap = 80, -- an area without an outpost: its objective radius is at most this
		EngageExtraStuds = 60, -- arrived: hostiles within objective radius + this are fought
		ClearHoldSeconds = 2, -- no hostile left for this long: the area is clear, the army holds
		EngageMaxSeconds = 120, -- a fight at the target with no end for this long: the army holds anyway
	},
	Approach = {} :: { [string]: { Vector3 } }, -- per-target approach points ("A:Town" = { Vector3.new(0, 1, 100) }); empty = computed
	RecallFarStuds = 60, -- FOLLOW / RECALL with the army this far from him: it marches back as a block first (Recalling)
	RetreatPlanStuds = 120, -- RETREAT with the army this far from home: it marches home as a block first
	-- ATTACK (DECIDED by Code Bot, owner bug 2026-10-01): seek the nearest valid hostile within SeekRadius of the ARMY
	-- (of him while it is beside him); none = "No enemies near" and the army stays in its previous state (no broken
	-- ATTACK). The radius is NOT raised (the owner's list: "bigger detection radius" is a fake fix).

	--[[ claude-bud JOB 52 (2026-10-01, Shaun: "ATTACK says No enemies near while enemies are clearly visible"): ATTACK AT
		RANGE. ROOT CAUSE (tools/sim/run_attack_range_test.py): the probe reach was SeekRadius 250 from him, but awake enemies
		stand where the wake / sleep bands keep them (OutpostDefender WakeStuds 260 / SleepStuds 380, SiteActivity 380), so
		the ones he could see were 260-380 studs out; and even a bigger reach alone would not hold: SeekLeash 300 cut
		them again, and the running plan re-sought / fought with SeekLeash 300 from him (it dropped the target it marched to).
		Live: ONE set of radii for the whole order (the probe, the plan's seek, its march answer, its fight pick, the leash
		check): SeekStuds 400 (one route leg, LegStuds 400, under 30 s at MarchSpeed 14), LeashStuds 450, ChainStuds 200;
		flat distances. Nothing within SeekStuds: the toast says the distance + direction to the nearest valid enemy and
		offers PIN / SEND ("N:<npcId>" through ArmyTargets; the client never sends a position). Kills of the ordered target
		group count on ARMY KILLS, at most KillCreditPerHour per owner (no AFK farm). OFF == OLD (250 / 300 / 150). ]]
	AttackRange = {
		Enabled = true,
		OwnerFirst = true, -- NEW-OWNER-FIRST (claude-bud JOB 52): Code Bot flips it after Shaun's 2-player phone test
		SeekStuds = 400,
		LeashStuds = 450,
		ChainStuds = 200,
		NearestScanStuds = 2500, -- "Nearest: 620 m NE": how far the nothing-in-range scan looks
		KillCreditPerHour = 60, -- ordered-ATTACK army kills of hostile combat NPCs credited per owner per rolling hour
		Text = {
			NoneInRange = "No enemies within %d m. Nearest: %d m %s",
			NoneAtAll = "No enemies on the map",
		},
	},

	-- 2. SEND
	Send = {
		RequireOwnerAlive = false, -- DECIDED: the army keeps attacking while the sender is dead but in the server
		StandoffStuds = 34, -- the siege position outside the gate
		SiegeMaxSeconds = 240,
		AtmHoldStuds = 10, -- the lead unit within this of the victim's ATM holds it (RaidConfig.Raid.RadiusStuds)
	},
	Siege = {
		Priority = { "Turret", "Guard", "Gate", "InsideGuard", "Atm" } :: { string },
		ReachStuds = 120, -- structures / guards within this of the army centre are siege targets
	},
	ArmyLootMult = 0.5, -- DECIDED: an army raid takes StealFraction x 0.5 (5 % of the ATM)

	-- 3. Fairness (DECIDED 2026-09-30)
	Fairness = {
		SendCooldownSeconds = 300, -- per sender, after any SEND that reached a siege
		VictimLeftCooldownSeconds = 150, -- the victim left mid-march / mid-siege: half
		ProtectAfterSiegeSeconds = 600, -- per victim base, after any army raid (looted or not)
		MinPowerRatio = 0.25, -- ArmyPower < this x DefencePower: "Too weak" (blocked)
		BullyRatio = 4, -- ArmyPower > this x DefencePower: loot x BullyLootMult
		BullyLootMult = 0.5,
		RiskyRatio = 1, -- below this (and above MinPowerRatio): "risky"
	},

	-- 4. Turret HP
	TurretHP = {
		Enabled = true,
		HealthByLevel = { 400, 550, 700 }, -- walls level 4, 5, 6+ (AutoGuns exist from walls level 4)
		RebuildSeconds = 90,
	},

	-- 5. ARMY KILLS board: the NPC types whose army kills count (plus base / tower guards and players, credited elsewhere)
	ArmyKillNpcTypes = { CheckpointGuard = true, BankGuard = true } :: { [string]: boolean },

	-- the status line / HUD strip / debug
	StatusSeconds = 1, -- the SquadOrderStateUpdate plan status, at most this often
	DefenderMarkerSeconds = 2, -- the defender's red map marker updates
	DebugLogSeconds = 2, -- [ArmyPlan] / [ArmyRoute] / [ArmyMarch] / [ArmySiege] lines, per owner (ArmyController.DebugFor)
	Text = {
		Seeking = "SEEKING",
		Marching = "MARCHING -> %s %d m",
		Fighting = "FIGHTING %d left",
		Cleared = "CLEARED %d",
		Returning = "RETURNING",
		Sieging = "SIEGE %s",
		Looting = "LOOTING %d s",
		NoRoute = "No route to %s",
		Left = "Army left for %s",
		Arrived = "Arrived at %s",
		Breached = "Gate breached!",
		Looted = "Looted $%s",
		NoLoot = "Gate breached, no loot (%s)",
		Wiped = "Army wiped out",
		Home = "Army home",
		Incoming = "⚠ %s's ARMY is marching on your base, ETA %s",
		NothingNear = "No enemies near",
		Travelling = "TRAVELLING -> %s %d m", -- Code Bot (army command bug): a SEND to an area / site
		Engaging = "ENGAGING at %s",
		HoldingAt = "HOLDING %s",
		Sent = "Army sent to %s",
		AreaClear = "%s clear: your army holds it",
		CaptureHint = "%s clear: your army holds it. Stand in the zone to capture",
		Retreating = "RETREATING home",
	},
}

local RetentionConfig = require(script.Parent.RetentionConfig)

function ArmyOrdersConfig.LiveFor(userId: any): boolean
	return RetentionConfig.Live(ArmyOrdersConfig.Live, userId)
end

-- live for every player (the ARMY KILLS board swap waits for this)
function ArmyOrdersConfig.LiveForAll(): boolean
	local L = ArmyOrdersConfig.Live
	return L.Enabled == true and L.OwnerFirst ~= true
end

-- the loot fraction of the ATM for an army raid (bully = far stronger army)
function ArmyOrdersConfig.LootFraction(stealFraction: number, bully: boolean): number
	local f = stealFraction * ArmyOrdersConfig.ArmyLootMult
	if bully then
		f *= ArmyOrdersConfig.Fairness.BullyLootMult
	end
	return f
end

-- the AutoGun HP for a walls level (0 = no HP: AutoGuns only from walls level 4)
function ArmyOrdersConfig.TurretHealth(wallsLevel: number): number
	local list = ArmyOrdersConfig.TurretHP.HealthByLevel
	local i = math.floor(wallsLevel) - 3
	if i < 1 then
		return 0
	end
	return list[math.min(i, #list)]
end

-- claude-bud JOB 52: the ATTACK radii for this owner: (seek, leash, chain) studs. AttackRange live: its numbers (seek
-- clamped 300-500, leash >= seek); else the old SeekRadius / SeekLeash / ChainRadius exactly.
function ArmyOrdersConfig.AttackRadii(userId: any): (number, number, number)
	local A: any = (ArmyOrdersConfig :: any).AttackRange
	local live = typeof(A) == "table" and (require(script.Parent.RetentionConfig) :: any).Live(A, userId)
	if not live then
		return ArmyOrdersConfig.SeekRadius, ArmyOrdersConfig.SeekLeash, ArmyOrdersConfig.ChainRadius
	end
	local seek = math.clamp(tonumber(A.SeekStuds) or 400, 300, 500)
	return seek, math.max(seek, tonumber(A.LeashStuds) or seek + 50), math.max(50, tonumber(A.ChainStuds) or 200)
end

function ArmyOrdersConfig.AttackRangeLive(userId: any): boolean
	local A: any = (ArmyOrdersConfig :: any).AttackRange
	return typeof(A) == "table" and (require(script.Parent.RetentionConfig) :: any).Live(A, userId)
end

-- the compass word for a flat direction (dx, dz) in world space (-Z = north, as the map / compass draw it)
function ArmyOrdersConfig.Compass8(dx: number, dz: number): string
	local a = math.deg(math.atan2(dx, -dz)) % 360
	local names = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
	return names[(math.floor((a + 22.5) / 45) % 8) + 1]
end

return ArmyOrdersConfig
