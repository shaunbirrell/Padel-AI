--!strict
--[[
	claude-bud JOB 10 (2026-09-29): the balance / progression table (one place for the numbers). Owner-only first.

	Why (tools/progression_sim.py, a base-income-only floor; the live game also has soldiers, oil, missions, drops):
	  * today the whole base costs $11.2M and earns ~$13k/min when complete: late pads take 55-140 HOURS to pay back
	    (MissileDefense L5 139 h, DefensiveWalls L5 78 h): dead purchases;
	  * the first rebirth needs level 40 (292,371 XP) but every purchase together pays ~18k XP and nothing else scales with
	    the base, so the first rebirth takes many hours of kills / missions.
	What this does for a player it is live for:
	  * PaybackMinutes: each base pad level pays its own price back in PaybackMinutes[level] minutes of passive income
	    (level 1 fastest). Every pad is worth buying, and the next pad is always minutes away;
	  * IncomeXP: Per1000 XP for every $1,000 of passive income (reason "income"; the battle pass is not fed by it), so
	    building the base IS levelling up;
	  * sim (tools/progression_sim.py, base income only): base complete ~34 min, level 40 (first rebirth) ~34 min, every
	    pad pays back within 25 min (was up to 139 h); a finished base earns ~780k/min. Target FirstRebirthMinutes.
	  * PremiumVehicleMaxEdge: the Robux-only vehicles may be at most this much stronger than their base (claude_bud_money).
	Businesses keep their own IncomePerTick table (unchanged). Rollout "owner" / "all" / off (off = today's curve).
]]

local AdminConfig = require(script.Parent.AdminConfig)
local BaseConfig = require(script.Parent.BaseConfig)
local EconomyConfig = require(script.Parent.EconomyConfig)

local BalanceConfig = {
	Rollout = "owner",
	FirstRebirthMinutes = { Min = 25, Max = 40 },
	PaybackMinutes = { 2, 3, 6, 12, 25 } :: { number },
	IncomeXP = {
		Enabled = true,
		Per1000 = 25,
		GrantAtLeast = 25, -- XP is banked and paid in lumps of at least this (fewer level-bar updates)
	},
	PremiumVehicleMaxEdge = 1.06,
	StartingCash = 10000, -- (EconomyConfig.StartingCash; listed here for the whole picture)
	-- set to true ONLY by the client that the server marked (player attribute WE_Balance2): TycoonMath's labels then use
	-- this curve. The server never sets it (it pays through BaseService per player).
	ClientCurve = false,
}

function BalanceConfig.LiveFor(userId: any): boolean
	local mode = BalanceConfig.Rollout
	if mode == "all" then
		return true
	elseif mode == "owner" then
		return AdminConfig.IsPlaytestOwner(userId)
	end
	return false
end

-- total $ per tick of a base structure at `level` under this curve (nil: not a base structure -> keep the old formula)
function BalanceConfig.StructureIncomePerTick(id: string, level: number): number?
	local def = (BaseConfig.Structures :: any)[id]
	if def == nil or typeof(def.Costs) ~= "table" then
		return nil
	end
	local tick = EconomyConfig.PassiveIncome.TickSeconds
	local total = 0
	local lvl = math.clamp(math.floor(tonumber(level) or 0), 0, def.MaxLevel or #def.Costs)
	for i = 1, lvl do
		local cost = tonumber(def.Costs[i]) or 0
		local pay = BalanceConfig.PaybackMinutes[math.min(i, #BalanceConfig.PaybackMinutes)]
		total += cost / (pay * 60 / tick)
	end
	return math.floor(total)
end

return BalanceConfig
