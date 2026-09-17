--!strict
--[[ Studio-only flags. Production ignores unless RunService:IsStudio().

	Test / playtest helpers (Studio):
	- SkipTutorial = true  → profile.TutorialComplete on load (no tutorial UI)
	- StudioBoostCash      → set Cash to StudioBoostCashAmount on load
	- FastPassiveIncome    → passive tick every 1s instead of EconomyConfig tick
	- UnlockAllVehicles / UnlockAllWeapons → grant all on load
	- VerboseLogging       → extra Bootstrap prints

	Admin remotes (AdminConfig.UserIds only), via RequestAdminCommand:
	  givecash <n>, givegold <n>, givexp <n>, setlevel <n>, unlockall, resetbase,
	  resettutorial, grantpass <PassKey>, prestige/forceprestige, createclan/joinclan/leaveclan, bpxp, grantpremium
]]

local DevConfig = {
	StudioBoostCash = false,
	StudioBoostCashAmount = 100000,
	-- false so interactive tutorial can be playtested; set true to skip in Studio
	SkipTutorial = false,
	UnlockAllVehicles = false,
	UnlockAllWeapons = false,
	VerboseLogging = true,
	FastPassiveIncome = false, -- if true, tick every 1s (Studio only)
	-- Studio-only: treat listed GamePass keys as owned when product Id is still 0
	MockOwnedGamePasses = {
		-- VIP = true,
		-- DoubleCash = true,
		-- DoubleXP = true,
	} :: { [string]: boolean },
}

return DevConfig
