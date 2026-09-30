--!strict
--[[
	claude-bud JOB 39 (2026-09-30): the plaza stations (JOB 39 §3). Which building becomes which station, where its
	NPC stands (in the building's own frame: local -Z = the door side, the ground floor top at y 0.3), the prompt,
	the door sign and the interior prop count.

	The station interiors are built on the CLIENT, only for a player EndgameConfig is live for (Part = the station's
	EndgameConfig.Parts switch). So while the job is owner-first nobody else sees a change, and nothing is added to the
	shared world budgets. The server publishes each station's frame (ReplicatedStorage.WE_PlazaStations, a CFrameValue
	per station) from the Enterables registry and checks every purchase against the same frame (EndgameConfig.Station).
	Budget per house (ROBLOX-BUILD-GUIDE §3): <= MaxParts parts, one PointLight (Shadows off, Range <= 16), one sign
	SurfaceGui (MaxDistance <= 40). run_endgame_test.py builds each station with the real client builder and counts.
]]

local PlazaServicesConfig = {
	FolderName = "WE_PlazaStations",
	MaxParts = 40,
	LightRange = 14,
	LightBrightness = 0.7,
	SignMaxDistance = 40,
	PromptRange = 12,
	Stations = {
		Command = {
			Row = "NE_N1", -- the hotel facade (red awning)
			Part = "EmpireLevel",
			Title = "COMMAND OFFICE",
			Sign = "COMMAND",
			Npc = "Chief of Staff",
			Action = "Empire Level",
			-- the NPC stands behind the map table, facing the door
			NpcAt = Vector3.new(-2.5, 0.3, 1.1),
			Parts = 39,
		},
		-- the Office Building store prop (StorePropsConfig 12423243620): its ground floor is not known to be walkable, so
		-- the Engineer works at a covered drafting stand in its forecourt (the spec's fallback). Without the prop the stand
		-- goes FallbackOffset from the Command Office house (street side).
		Engineers = {
			StoreProp = 12423243620,
			FallbackRow = "NE_N1",
			FallbackOffset = Vector3.new(16, 0, -14),
			ForecourtStuds = 7,
			Part = "Defence",
			Title = "ENGINEERING BUREAU",
			Sign = "ENGINEERS",
			Npc = "Engineer",
			Action = "Defences",
			NpcAt = Vector3.new(0, 0.3, 1.6),
			Parts = 32,
		},
		-- phase 3: the cafe facade (teal awning). A counter with lockers behind it, the Drill Sergeant, a flag stand.
		Recruits = { Row = "NE_E1", Part = "Elite", Title = "RECRUITMENT OFFICE", Sign = "RECRUITS", Npc = "Drill Sergeant", Action = "Elite Training", NpcAt = Vector3.new(-2.5, 0.3, 1.1), Parts = 37 },
		Armory = { Row = "SW_S1", Part = "Mastery", Title = "ARMORY WORKSHOP", Sign = "ARMORY", Npc = "Gunsmith", Action = "Gun Upgrades", NpcAt = Vector3.new(-2.5, 0.3, 1.1), Parts = 0 },
		Intel = { Row = "NW_W1", Part = "Contracts", Title = "INTEL OFFICE", Sign = "INTEL", Npc = "Signals Officer", Action = "Contracts", NpcAt = Vector3.new(-2.5, 0.3, 1.1), Parts = 0 },
	} :: { [string]: any },
	-- the order the base EMPIRE panel lists them in
	Order = { "Command", "Engineers", "Recruits", "Armory", "Intel" },
}

return PlazaServicesConfig
