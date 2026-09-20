--!strict
--[[
	Army + Training Yard worker income (MT-inspired: soldiers generate cash while "training").
	Visual: R15-ready config keys; catalog IDs live in VisualAssetConfig.Characters.
	If ModelAssetId missing/0 → military Part-kit placeholder (MapSetup.makeSoldierKit / CombatService).
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

	--[[
		R15-ready visual path (Design Bot / Code P0).
		VisualKind maps → VisualAssetConfig.Characters[kind].
		VisualPlaceholder = Part-kit camo soldier when catalog ID is 0 / insert fails.
		Do NOT invent Creator Store IDs here — leave slots; wire in VisualAssetConfig only.
	]]
	Visual = {
		Rig = "R15", -- preferred attach target; Part kit remains R6-ish fallback proportions
		VisualKindDefault = "Soldier",
		VisualKindByRole = {
			Worker = "Worker", -- v41: VisualAssetConfig.Characters.Worker 16134469614
			Infantry = "Infantry",
			Heavy = "HeavyInfantry",
			Guard = "Guard",
			BankGuard = "BankGuard",
			OilRigGuard = "OilRigGuard",
			FortGuard = "FortGuard",
			SpecialForces = "SpecialForces", -- v41 SF unit VisualKind
		},
		-- Placeholder palette when mesh missing (olive drab / desert camo)
		VisualPlaceholder = {
			Enabled = true,
			BodyColor = Color3.fromRGB(70, 85, 55),
			AccentColor = Color3.fromRGB(180, 220, 120),
			Helmet = true,
			Rifle = true,
			Note = "MapSetup.makeSoldierKit + CombatService Part kit until Design Bot mesh loads",
		},
		-- Optional future slots (TODO — no invented IDs)
		ModelAssetIdOverride = 0, -- 0 = use VisualAssetConfig.Characters
		AccessoryIds = {} :: { number }, -- TODO Design Bot
	},
}

return SoldierConfig
