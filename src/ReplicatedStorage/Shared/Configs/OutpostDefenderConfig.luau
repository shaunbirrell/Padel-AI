--!strict
--[[
	claude-bud JOB 24 §6 (owner: "only the Bank has enemies"): NPC defenders at every capturable outpost
	(Server/Modules/OutpostDefenders). The v2 map removed the static statues and meant "live CombatService NPCs", but
	nothing ever spawned them (TerritoryConfig.GuardNPCType / GuardCount were never read).

	  * Every non-starter territory that is NOT held by a player / clan has defenders: live CombatService NPCs (the same
	    animated soldier rigs as the Bank and the camps), placed on a ring round the capture point, leashed to it, that
	    shoot back (CombatService's NPC brain: line of sight + hit chance).
	  * Tier by the outpost's worth (StipendCash): Easy / Medium / Hard (Hard uses the territory's own GuardNPCType x
	    GuardCount: Fort / Oil Rig guards).
	  * Capture cannot start while any of them is alive (TerritoryService: "Defeat the defenders first!").
	  * Awake only while a player is within WakeStuds; asleep (despawned, no reward) after nobody is within SleepStuds for
	    SleepAfterSeconds. Cleared: back RespawnSeconds after the last one fell (still not player-held). Captured: the
	    rest leave; they come back RespawnSeconds after it is neutral again.
	  * At most MaxTotal defenders on the server; kills pay the NPC type's cash + XP (CombatService) and count on MOST
	    KILLS (EngagementService.NoteDefenderKill).
	Enabled = false: no defenders anywhere (v116).
]]

local OutpostDefenderConfig = {
	Enabled = true,
	WakeStuds = 260,
	SleepStuds = 380,
	SleepAfterSeconds = 30,
	RespawnSeconds = 150,
	MaxTotal = 20, -- (CombatConfig.SpecialOverCap leaves room for these + the bank)
	CheckSeconds = 2,
	RingFraction = 0.5, -- ring radius = the territory radius x this (oil rigs: RigRingStuds, on the deck)
	RigRingStuds = 9,
	LeashExtraStuds = 25,
	-- StipendCash thresholds -> tier
	MediumFromStipend = 5000,
	HardFromStipend = 10000,
	Tiers = {
		Easy = { "Infantry", "Infantry", "Infantry" },
		Medium = { "Infantry", "HeavyInfantry", "HeavyInfantry", "Infantry" },
		-- Hard: the territory's GuardNPCType x GuardCount (else this)
		Hard = { "HeavyInfantry", "HeavyInfantry", "HeavyInfantry", "HeavyInfantry" },
	},
	-- claude-bud JOB 24 §7: enemy garrisons at the named areas that are NOT outposts (WorldConfig.POIs; the map
	-- already dresses them: Ruined Village, Desert Airstrip, Crash Site, Signal Station, Oasis). Same rules as an
	-- outpost's defenders (wake / sleep / respawn / MaxTotal / rewards / MOST KILLS); nothing to capture. Tier by
	-- distance out from the town: Easy near the middle, Hard out at the edge.
	Areas = {
		{ Id = "Crash", Name = "Crash Site", Position = Vector3.new(-540, 1, 1140), Radius = 60, Tier = "Easy" },
		{ Id = "Signal", Name = "North Ridge Signal Station", Position = Vector3.new(-95, 1, -1300), Radius = 60, Tier = "Easy" },
		{ Id = "Airstrip", Name = "Desert Airstrip", Position = Vector3.new(510, 1, -1265), Radius = 80, Tier = "Medium" },
		{ Id = "Ruins", Name = "Ruined Village", Position = Vector3.new(-540, 1, -1320), Radius = 70, Tier = "Medium" },
		{ Id = "Oasis", Name = "Oasis", Position = Vector3.new(-1300, 1, 560), Radius = 60, Tier = "Hard" },
	},
	BlockedText = "Defeat the defenders first!",
	BlockedNoteSeconds = 6,
}

return OutpostDefenderConfig
