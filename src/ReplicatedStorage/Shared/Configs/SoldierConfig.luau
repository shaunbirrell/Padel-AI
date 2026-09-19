--!strict
--[[
	Army + Training Yard worker income (MT-inspired: soldiers generate cash while "training").
]]

local SoldierConfig = {
	StartingSoldiers = 5,
	MaxSoldiersBase = 50,
	SoldiersPerBarracksLevel = 5,
	RecruitCostCash = 500,
	RecruitBatchSize = 1,
	DismissRefundMult = 0.25,
	SoldierHealth = 100,
	SoldierDamage = 12,
	SoldierSpeed = 14,

	-- Training Yard passive (owned soldiers → cash each tick)
	TrainingIncome = {
		TickSeconds = 5,
		CashPerSoldierPerTick = 8, -- 5 soldiers ≈ $8/s effective over tick (40/5s)
		MinSoldiersForIncome = 1,
	},
}

return SoldierConfig
