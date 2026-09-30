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
		OwnerFirst = true, -- only UserId 470626172 (+ Studio test players) until Code Bot sets false = everyone
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
	LostStuds = 90, -- a unit this far from the block for LostSeconds is marked LOST (reported, never moved)
	LostSeconds = 15,

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

return ArmyOrdersConfig
