--!strict
--[[
	Levels 1–100 via formula.
	XP to go from level L to L+1: floor(100 * L ^ 1.45)
	Rewards granted on level-up (cash + optional gold every 5).

	Milestones: clear unlock messages + HUD next-goal text (Design/Code P0).
	ASSUMPTION: milestone UnlockText is cosmetic guidance; actual gates live in
	VehicleConfig / WeaponConfig / BaseConfig / PrestigeConfig / TerritoryConfig.
]]

export type MilestoneDef = {
	Level: number,
	Title: string,
	UnlockText: string, -- toast on level-up
	HudGoal: string, -- shown until this level is reached (as "next")
	Kind: "Weapon" | "Vehicle" | "Base" | "Territory" | "Prestige" | "Army" | "General",
}

local LevelConfig = {}

LevelConfig.MaxLevel = 100
LevelConfig.MaxLevelBeforePrestige = 100

function LevelConfig.GetXPRequiredForLevel(level: number): number
	if level < 1 then
		return 0
	end
	if level >= LevelConfig.MaxLevel then
		return math.huge
	end
	return math.floor(100 * (level ^ 1.45))
end

function LevelConfig.GetTotalXPForLevel(level: number): number
	local total = 0
	for l = 1, level - 1 do
		total += LevelConfig.GetXPRequiredForLevel(l)
	end
	return total
end

function LevelConfig.GetLevelUpReward(newLevel: number): { Cash: number, Gold: number }
	local cash = 500 + (newLevel * 150)
	local gold = if newLevel % 5 == 0 then math.floor(newLevel / 5) else 0
	return { Cash = cash, Gold = gold }
end

-- Explicit first 20 for designers / BALANCE.md
LevelConfig.Preview = {}
for i = 1, 20 do
	LevelConfig.Preview[i] = {
		Level = i,
		XPToNext = LevelConfig.GetXPRequiredForLevel(i),
		Reward = LevelConfig.GetLevelUpReward(i + 1),
	}
end

--[[
	Ordered milestones. GetNextMilestone(level) returns the first with Level > current.
	Prestige objective: reach PrestigeConfig.MinLevelToPrestige (40) then rebirth.
	Territory objective: capture Central Plaza / any POI (soft goal, not hard gate).
]]
LevelConfig.Milestones = {
	{
		Level = 1,
		Title = "Recruit",
		UnlockText = "Welcome, Commander — claim your base, buy Command Center, recruit soldiers.",
		HudGoal = "GOAL: Claim base → BUY Command Center → Recruit soldiers",
		Kind = "Army",
	},
	{
		Level = 2,
		Title = "Motor Pool",
		UnlockText = "LVL 2 — Utility Quad / Dispatch Car unlock in Garage.",
		HudGoal = "GOAL: Reach L2 · unlock Utility Quad",
		Kind = "Vehicle",
	},
	{
		Level = 3,
		Title = "Assault Rifle",
		UnlockText = "LVL 3 — Assault Rifle unlocked. Buy or equip from combat loadout.",
		HudGoal = "GOAL: Reach L3 · unlock Assault Rifle",
		Kind = "Weapon",
	},
	{
		Level = 4,
		Title = "Scout",
		UnlockText = "LVL 4 — Scout Car + SMG unlock.",
		HudGoal = "GOAL: Reach L4 · Scout Car / SMG",
		Kind = "Vehicle",
	},
	{
		Level = 5,
		Title = "Patrol",
		UnlockText = "LVL 5 — Patrol Truck unlock. Capture Central Plaza for +10% passive cash.",
		HudGoal = "GOAL: Reach L5 · Patrol Truck · capture Central Plaza",
		Kind = "Territory",
	},
	{
		Level = 6,
		Title = "Shotgun + Supply",
		UnlockText = "LVL 6 — Combat Shotgun + Supply Truck unlock.",
		HudGoal = "GOAL: Reach L6 · Shotgun / Supply Truck",
		Kind = "Weapon",
	},
	{
		Level = 8,
		Title = "APC Gate",
		UnlockText = "LVL 8 — APC unlock. Fortify with Defensive Walls when cash allows.",
		HudGoal = "GOAL: Reach L8 · unlock APC",
		Kind = "Vehicle",
	},
	{
		Level = 10,
		Title = "IFV + Sniper",
		UnlockText = "LVL 10 — Combat IFV + Sniper path open. Hold 2 territories for stipends.",
		HudGoal = "GOAL: Reach L10 · IFV · hold 2 territories",
		Kind = "Territory",
	},
	{
		Level = 12,
		Title = "Light Armor",
		UnlockText = "LVL 12 — Light Tank unlock. Push oil rigs for big stipends.",
		HudGoal = "GOAL: Reach L12 · Light Tank · contest an oil rig",
		Kind = "Vehicle",
	},
	{
		Level = 15,
		Title = "Heavy Push",
		UnlockText = "LVL 15 — Heavy Tank / Assault IFV band. Build Helipad for air ops.",
		HudGoal = "GOAL: Reach L15 · Heavy armor · Helipad L1",
		Kind = "Base",
	},
	{
		Level = 20,
		Title = "Air Superiority",
		UnlockText = "LVL 20 — Fighter / CAS jet band. Dominate air + naval docks.",
		HudGoal = "GOAL: Reach L20 · jets · Dock L1",
		Kind = "Vehicle",
	},
	{
		Level = 25,
		Title = "Empire Mid",
		UnlockText = "LVL 25 — Mid-game empire. Max Barracks, stack territory stipends.",
		HudGoal = "GOAL: Reach L25 · Barracks L3+ · 3 territories",
		Kind = "Army",
	},
	{
		Level = 30,
		Title = "War Machine",
		UnlockText = "LVL 30 — Capital vehicles band. Prep Research Lab / Special Forces.",
		HudGoal = "GOAL: Reach L30 · Research Lab · 4 territories",
		Kind = "Base",
	},
	{
		Level = 40,
		Title = "Prestige Ready",
		UnlockText = "LVL 40 — PRESTIGE UNLOCKED. Rebirth for +10% cash forever (K panel).",
		HudGoal = "GOAL: L40 reached — open K · Do Prestige / Rebirth (+10% cash)",
		Kind = "Prestige",
	},
	{
		Level = 50,
		Title = "Veteran",
		UnlockText = "LVL 50 — Veteran commander. Push prestige track unlocks.",
		HudGoal = "GOAL: Prestige again · climb rebirth unlock track",
		Kind = "Prestige",
	},
	{
		Level = 75,
		Title = "High Command",
		UnlockText = "LVL 75 — High Command. Max structures, hold forts + oil.",
		HudGoal = "GOAL: Max key structures · hold fortress + oil",
		Kind = "Territory",
	},
	{
		Level = 100,
		Title = "Max Level",
		UnlockText = "LVL 100 — MAX. Prestige to reset level and stack cash mult.",
		HudGoal = "GOAL: Prestige at max · stack +10% cash / rebirth",
		Kind = "Prestige",
	},
} :: { MilestoneDef }

function LevelConfig.GetMilestoneAt(level: number): MilestoneDef?
	local best: MilestoneDef? = nil
	for _, m in ipairs(LevelConfig.Milestones) do
		if m.Level == level then
			return m
		end
		if m.Level < level then
			best = m
		end
	end
	return best
end

function LevelConfig.GetNextMilestone(level: number): MilestoneDef?
	for _, m in ipairs(LevelConfig.Milestones) do
		if m.Level > level then
			return m
		end
	end
	-- At/above last milestone — prestige objective
	return LevelConfig.Milestones[#LevelConfig.Milestones]
end

function LevelConfig.GetHudGoal(level: number): string
	local nxt = LevelConfig.GetNextMilestone(level)
	if not nxt then
		return "GOAL: Prestige for +10% cash · dominate territories"
	end
	if nxt.Level <= level then
		return nxt.HudGoal
	end
	return nxt.HudGoal
end

function LevelConfig.GetUnlockMessage(newLevel: number): string?
	for _, m in ipairs(LevelConfig.Milestones) do
		if m.Level == newLevel then
			return m.UnlockText
		end
	end
	-- Generic every 5 levels
	if newLevel % 5 == 0 then
		return string.format("LVL %d — rank up! Check Garage / Weapons for new unlocks.", newLevel)
	end
	return nil
end

return LevelConfig
