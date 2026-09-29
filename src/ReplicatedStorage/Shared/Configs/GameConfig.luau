--!strict
--[[ WAR EMPIRE — Core game settings ]]

local GameConfig = {
	DisplayName = "WAR EMPIRE",
	Tagline = "BUILD. CONQUER. DOMINATE.",
	-- One base per player: must equal the place's Max Players setting (place settings, not code) and
	-- BaseConfig.MaxPlots. A player past the plot count joins with no base. BaseService warns in the server log at boot
	-- when the place allows more players than there are plots.
	MaxPlayersPerServer = 10,
	BasePlotCount = 10,
	RespawnTimeSeconds = 5,
	FriendlyFire = false,
	PvPEnabled = true,
	TutorialEnabled = true,
	DefaultWalkSpeed = 16,
	DefaultJumpPower = 50,
	SpawnInvulnerabilitySeconds = 3,
}

return GameConfig
