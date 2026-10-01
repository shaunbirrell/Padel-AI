--!strict
--[[
	claude-bud JOB 20 (2026-09-29, owner: "base guards are just props; make them real defenders"): every guard number
	in one place (Server/Modules/BaseGuards, hooked into GateDefenseService's 5 Hz think loop). Live for all.
	  * Base guards: stand at their posts (idle); when a hostile player or an enemy army unit is INSIDE the plot, they
	    turn, walk / path toward it (never more than LeashStuds from the post, never out of the plot) and shoot with
	    line of sight and a hit chance; back to the post ReturnAfterSeconds after the last intruder. Never the owner,
	    his clan, his friends or anyone's army that belongs to them. HP / count grow with the Defenses research
	    (GuardArmor = HP, GuardRoster = +1 / +2 guards at ExtraPosts); die, respawn at the post after RespawnSeconds.
	  * Tower guards: one buyable slot per base corner tower (in-game Cash, Tower.BaseCost x (1 + PerRebirth x
	    rebirths)); stands on the platform, shoots hostiles OUTSIDE the walls within Tower.Range, slower and harder;
	    a gold helmet badge.
	  * Rewards: a guard / tower guard kill of a player = the owner's player kill (the server's creator tag: cash, XP,
	    MOST KILLS, the kill feed "<owner>'s Tower Guard"), at most PairMax per victim per PairWindowSeconds, never in
	    a private server. Killing an enemy guard / army unit = the smaller GuardKill / UnitKill reward (not on MOST
	    KILLS), same pair limit.
	  * Balance: damage per target per second is capped (lower for low-level / new players), at most
	    MaxShootersPerBase guards / tower guards / auto-guns fire per base at once.
]]

local GuardConfig = {
	Enabled = true,


	RespawnSeconds = 45,
	LeashStuds = 60,
	ReturnAfterSeconds = 8,
	HitChanceNear = 0.8,
	HitChanceFar = 0.45,
	HitNearStuds = 20,
	PathEverySeconds = 2, -- a guard that cannot see its target asks for a path at most this often
	PathBudgetPerSecond = 6, -- server-wide
	MaxShootersPerBase = 6,
	UnitTargets = true, -- enemy army units are targets too
	UnitTag = "WE_SquadUnit",
	--[[ claude-bud JOB 40 part A (2026-09-30): REAL BASE GUARDS at every guard post inside a live plot (the rear-gate
		and sea-gate statues become armed, animated, killable guards; Modules/BaseGuards state machine IDLE / ALERT /
		ATTACK / RETURN / DEAD) and THE ONE hostility rule for every base defence (CombatService.UnitMayHitPlayer /
		ArmyHostility; hits through CombatService). Owner-first by the BASE OWNER: a plot whose owner is not live keeps
		today's statues, gate guards and turrets exactly (their old checks included). ]]
	Posts = {
		Enabled = true,
		OwnerFirst = false, -- codebot_v166 flip-all-live (owner 2026-10-01 10:31): everyone (real base guards at every base)
		StatuePatterns = { "^GateGuard_%a+[LR]$", "^GateGuard_Sea%d*$" }, -- MapSetup's rear-gate / sea-gate statues
		ModelPrefix = "BaseGuard_",
		AlertStuds = 80, -- a hostile outside the plot this close to the post (with line of sight) is noticed
		ReactionSeconds = 0.5, -- ALERT -> ATTACK
		AlertForgetSeconds = 3, -- ALERT with the target lost this long -> RETURN
		TurnDegPerSec = 360,
		FireRate = 1.2,
		Damage = 10,
		Range = 90,
		LeashStuds = 45,
		Health = 150, -- the statue's value
		RegenAfterSeconds = 5, -- HP back to full once at the post and out of combat this long
		RespawnSeconds = 45,
		RespawnRetrySeconds = 2, -- a player standing on the post delays the respawn
		RespawnClearStuds = 4,
		ProtectCollectorRadius = 40, -- tier 2 of the target pick (near the ATM)
	},


	-- Defenses research (ResearchConfig): HP multiplier and extra guards
	HealthStat = "GuardHP",
	CountStat = "GuardCount",
	MaxExtraGuards = 2,
	-- plot-local posts of the extra guards (beside the courtyard, off the gate road)
	ExtraPosts = { { X = -24, Z = 112 }, { X = 24, Z = 112 } },

	Tower = {
		Enabled = true,
		Range = 150,
		FireRate = 0.5, -- shots per second (slower than a gate guard)
		Damage = 34, -- higher than a gate guard
		HitChance = 0.6,
		Health = 260,
		BaseCost = 25000,
		PerRebirth = 0.5, -- + 50 % of BaseCost per rebirth
		MaxCost = 2000000,
		Folder = "WE_CornerTowers", -- StructureKitBuilder.SyncCornerTowers
		PlatformPrefix = "TowerPlatform",
		Slots = 4,
		PromptDistance = 12,
		BadgeColor = Color3.fromRGB(240, 190, 50),
	},

	Rewards = {
		GuardKillCash = 1500, -- a player kills an enemy base guard / tower guard
		GuardKillXP = 40,
		UnitKillCash = 600, -- your guard kills an enemy army unit
		UnitKillXP = 15,
		PairMax = 3, -- per killer -> victim pair ...
		PairWindowSeconds = 600, -- ... per 10 minutes
		NoCreditInPrivateServers = true,
	},

	DpsCap = {
		PerTarget = 30, -- damage per target per second from one base's defenders
		LowTarget = 12, -- a player below LowLevel or in his first NewPlayerSeconds
		LowLevel = 5,
		NewPlayerSeconds = 600,
	},
}

-- pure: the hire price of a tower guard for a player with `rebirths` rebirths
-- claude-bud JOB 40: the post guards + the one rule are live for this BASE OWNER
function GuardConfig.PostsLiveFor(ownerUserId: any): boolean
	return (require(script.Parent.RetentionConfig) :: any).Live((GuardConfig :: any).Posts, ownerUserId)
end

--[[ claude-bud JOB 40: the post guard state machine's decision (pure; tests call it). s = the current state,
	c = { Target: boolean (a hostile picked this tick), Since: seconds in this state, LostFor: seconds since the target
	was last seen, FromPost: studs from the post, AtPost: boolean, Dead: boolean }. Returns the next state. ]]
function GuardConfig.PostNext(s: string, c: { [string]: any }): string
	local P: any = (GuardConfig :: any).Posts
	if c.Dead then
		return "DEAD"
	end
	if s == "DEAD" then
		return "IDLE" -- a respawned guard starts idle at its post
	end
	if (tonumber(c.FromPost) or 0) > P.LeashStuds then
		return "RETURN"
	end
	if s == "IDLE" then
		return if c.Target then "ALERT" else "IDLE"
	elseif s == "ALERT" then
		if not c.Target and (tonumber(c.LostFor) or 0) >= P.AlertForgetSeconds then
			return "RETURN"
		end
		return if c.Target and (tonumber(c.Since) or 0) >= P.ReactionSeconds then "ATTACK" else "ALERT"
	elseif s == "ATTACK" then
		if not c.Target and (tonumber(c.LostFor) or 0) >= (GuardConfig :: any).ReturnAfterSeconds then
			return "RETURN"
		end
		return "ATTACK"
	elseif s == "RETURN" then
		if c.Target and (tonumber(c.FromPost) or 0) < P.LeashStuds - 5 then
			return "ALERT"
		end
		return if c.AtPost then "IDLE" else "RETURN"
	end
	return "IDLE"
end

function GuardConfig.TowerCost(rebirths: number): number
	local T = GuardConfig.Tower
	local r = math.max(0, math.floor(tonumber(rebirths) or 0))
	return math.min(T.MaxCost, math.floor(T.BaseCost * (1 + T.PerRebirth * r)))
end

-- pure: one killer -> victim pair may be rewarded (at most PairMax per PairWindowSeconds; the log is pruned here)
function GuardConfig.AllowPair(log: { [string]: { number } }, a: number, b: number, now: number): boolean
	if a == b then
		return false
	end
	local R = GuardConfig.Rewards
	local key = tostring(a) .. ">" .. tostring(b)
	local kept: { number } = {}
	for _, t in ipairs(log[key] or {}) do
		if now - t < R.PairWindowSeconds then
			table.insert(kept, t)
		end
	end
	if #kept >= R.PairMax then
		log[key] = kept
		return false
	end
	table.insert(kept, now)
	log[key] = kept
	return true
end

-- pure: how much of `amount` may land on a target that already took `taken` this second
function GuardConfig.CapDamage(taken: number, amount: number, low: boolean): number
	local cap = if low then GuardConfig.DpsCap.LowTarget else GuardConfig.DpsCap.PerTarget
	return math.max(0, math.min(amount, cap - taken))
end

return GuardConfig
