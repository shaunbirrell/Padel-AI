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
		-- phase 4: the market facade (navy awning), ground floor: a gun bench, a wall rack, the Gunsmith
		Armory = { Row = "SW_S1", Part = "Mastery", Title = "ARMORY WORKSHOP", Sign = "ARMORY", Npc = "Gunsmith", Action = "Gun Upgrades", NpcAt = Vector3.new(-2.5, 0.3, 1.1), Parts = 39 },
		-- phase 4: the Town Hospital store prop (5201630514): a field-hospital stand in its forecourt (reception desk, 2
		-- stretcher beds, an IV stand); a white plus on green (no red-cross emblem). No prop: beside the radio shop house.
		Hospital = {
			StoreProp = 5201630514,
			FallbackRow = "NW_W1",
			FallbackOffset = Vector3.new(16, 0, -14),
			ForecourtStuds = 7,
			Part = "Hospital",
			Title = "FIELD HOSPITAL",
			Sign = "HOSPITAL",
			Npc = "Field Medic",
			Action = "Medic",
			NpcAt = Vector3.new(0, 0.3, 1.6),
			Parts = 37,
		},
		-- phase 5: the radio-shop facade (orange awning): a radio desk, a map wall, the Signals Officer
		Intel = { Row = "NW_W1", Part = "Contracts", Title = "INTEL OFFICE", Sign = "INTEL", Npc = "Signals Officer", Action = "Intel", NpcAt = Vector3.new(-2.5, 0.3, 1.1), Parts = 37 },
		-- phase 5: the market's UPPER floor (SW_S1): the Trader behind a crate counter facing the stair; no door sign
		-- (the ARMORY sign is the building's), a small board instead
		BlackMarket = { Row = "SW_S1", Part = "BlackMarket", Title = "BLACK MARKET", Sign = "BLACK MARKET", Npc = "Trader", Action = "Black Market", NpcAt = Vector3.new(0.5, 11.4, -6), Parts = 23, Upstairs = true },
		-- phase 5: the Fixer's side desk inside the Empire Bank hall (x 208..232, z -236..-214, floor top 1.6), against
		-- the east wall, facing the hall (WorldAt + Face: the frame's -Z looks along Face)
		Heist = {
			WorldAt = Vector3.new(229.6, 1.6, -218.5),
			Face = Vector3.new(-1, 0, 0),
			Part = "Heist",
			Title = "THE FIXER",
			Sign = "HEIST",
			Npc = "Fixer",
			Action = "Heist kits",
			NpcAt = Vector3.new(0, 0, 1.4),
			Parts = 24,
		},
	} :: { [string]: any },
	-- the order the base EMPIRE panel lists them in
	Order = { "Command", "Engineers", "Recruits", "Armory", "Hospital", "Intel", "BlackMarket", "Heist" },
}

return PlazaServicesConfig
