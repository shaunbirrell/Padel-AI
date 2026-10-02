--!strict
--[[
	claude-bud JOB 24 §5: "NEW BUILDING" cards (Server/Services/BuildingTips + Client/Controllers/BuildingTipController).
	When a building is first bought (the server's BaseUpgradeChanged: level 0 -> 1) its owner gets ONE dark card:
	"NEW: <NAME> UNLOCKED" + these lines, OK and SHOW ME (a beam to the building's console for ShowSeconds). Once per
	building per player (profile.SeenTutorials, kept through rebirth); Settings -> TIPS turns them off and can show them
	again. Copy: what the building REALLY does today (checked against the code, JOB 24 audit), simple words, no key
	names (phones), each line under ~12 words.
	Buildings that only earn cash today say so (PowerStation, Warehouse, Radar, SpecialForcesFacility; WeaponsFacility
	beyond the Arms Crate Line) - flagged in LATEST-HANDOFF as "does nothing extra yet".
]]

export type Tip = { Lines: { string } }

local BuildingTutorialConfig = {
	Enabled = true,
	ShowSeconds = 8,
	Tips = {
		CommandCenter = { Lines = { "Your HQ! Level it up to unlock new buildings.", "Level 3 + Missile Defense: launch missiles from its terminal." } },
		Barracks = { Lines = { "Each level lets you lead 5 more soldiers.", "Recruit soldiers at its terminal, then open Army." } },
		VehicleDepot = { Lines = { "Unlocks ground vehicles!", "Open the garage here to spawn a jeep." } },
		WeaponsFacility = { Lines = { "Earns cash and unlocks the Arms Crate Line.", "Buy guns at its terminal." } },
		PowerStation = { Lines = { "Earns cash for you every minute." } },
		Warehouse = { Lines = { "Earns cash for you every minute.", "Its terminal opens the shop and missions." } },
		DefensiveWalls = { Lines = { "Walls and gate guards now protect your base.", "Higher levels add a stronger gate and gun nests." } },
		Watchtowers = { Lines = { "Corner towers guard your base.", "Hire a tower guard at each tower." } },
		Radar = { Lines = { "Earns cash. Level 2 unlocks Missile Defense." } },
		ResearchLab = { Lines = { "Make weapons, soldiers, vehicles and defenses stronger.", "Start research at its terminals." } },
		Helipad = { Lines = { "Unlocks helicopters!", "Spawn one from the garage." } },
		Dock = { Lines = { "Unlocks boats!", "Spawn one from the garage and sail out." } },
		Airfield = { Lines = { "Unlocks planes!", "Open the hangar to take off." } },
		MissileDefense = { Lines = { "Shoots down enemy missiles.", "With Command Center level 3 you can launch missiles too." } },
		SpecialForcesFacility = { Lines = { "Earns cash for you every minute.", "Its terminal opens missions and your army." } },
		AmmoWorks = { Lines = { "A war business! It earns cash into your ATM.", "Collect it at your ATM." } },
		ArmsCrateLine = { Lines = { "A war business! It earns cash into your ATM.", "Collect it at your ATM." } },
		ArmorPlatePress = { Lines = { "A war business! It earns cash into your ATM.", "Collect it at your ATM." } },
		RocketAssembly = { Lines = { "A war business! It earns cash into your ATM.", "Collect it at your ATM." } },
	} :: { [string]: Tip },
}

return BuildingTutorialConfig
