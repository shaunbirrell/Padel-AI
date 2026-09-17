--!strict
--[[ Studio-only flags. Production ignores unless RunService:IsStudio(). ]]

local DevConfig = {
	StudioBoostCash = false,
	StudioBoostCashAmount = 100000,
	SkipTutorial = true,
	UnlockAllVehicles = false,
	UnlockAllWeapons = false,
	VerboseLogging = true,
	FastPassiveIncome = false, -- if true, tick every 1s (Studio only)
}

return DevConfig
