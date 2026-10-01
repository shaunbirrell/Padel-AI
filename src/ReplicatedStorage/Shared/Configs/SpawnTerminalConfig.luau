--!strict
--[[ claude-bud JOB 56: the helipad + dock spawn terminals. One console beside each BUILT helipad / dock on the owner's
	plot. It opens the same Garage panel (VehicleController.Open) filtered to Air / Naval: the spawn is the normal
	RequestSpawnVehicle -> VehicleService.RequestSpawn with every server gate (level, structure, cooldown, combat lock,
	ownership); the terminal grants nothing and moves nobody. Owner-first by the plot owner; OFF = no terminals. ]]

local SpawnTerminalConfig = {
	Enabled = true,
	OwnerFirst = true, -- NEW-OWNER-FIRST (claude-bud JOB 56): Code Bot flips it after Shaun's phone test
	PromptRange = 10,
	Panel = "Garage", -- UIController panelOpeners key (the ONE garage)
	Terminals = {
		-- At = plot-local X / Z (BaseLayoutConfig frame), Yaw = facing (degrees), Need = the BaseUpgrades structure
		Helipad = { At = { 52, -104 }, Yaw = -90, Need = "Helipad", Tab = "Air", Action = "Spawn aircraft", Object = "Helipad", Screen = { "AIRCRAFT", "OPEN GARAGE" } },
		Dock = { At = { 88, -70 }, Yaw = 180, Need = "Dock", Tab = "Naval", Action = "Launch boat", Object = "Dock", Screen = { "BOATS", "OPEN GARAGE" } },
	},
}

return SpawnTerminalConfig
