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
