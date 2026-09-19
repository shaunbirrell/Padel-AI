--!strict
--[[
	Free Supply Spinner — claim Cash/Gold every N hours (Settings / HUD).
	Fixed reward table (server picks index); not a paid loot box.
]]

local SpinnerConfig = {
	Enabled = true,
	CooldownSeconds = 4 * 3600, -- 4 hours
	DisplayName = "Supply Spinner",
	-- Weighted outcomes: Weight relative; server rolls once
	Rewards = {
		{ Id = "cash_small", DisplayName = "Cash Cache", Weight = 40, Cash = 5000, Gold = 0 },
		{ Id = "cash_med", DisplayName = "Cash Haul", Weight = 25, Cash = 12000, Gold = 0 },
		{ Id = "cash_big", DisplayName = "Cash Jackpot", Weight = 10, Cash = 25000, Gold = 0 },
		{ Id = "gold_small", DisplayName = "Gold Dust", Weight = 15, Cash = 2000, Gold = 2 },
		{ Id = "gold_med", DisplayName = "Gold Bar", Weight = 8, Cash = 5000, Gold = 5 },
		{ Id = "mixed", DisplayName = "Mixed Supply", Weight = 2, Cash = 15000, Gold = 8 },
	},
}

return SpinnerConfig
