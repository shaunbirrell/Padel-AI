--!strict
--[[ claude-bud JOB 58: the hangar + dock showpieces. The hangar's Part jet mock-ups (Installations/Airfield: 12 parts
	each) and the dock's Part patrol boat (DockKitConfig L1: 29 parts) give way to REAL approved store bodies
	(VisualAssetService.CloneDisplayBody: the same templates and BodyAllowed rule as driven vehicles; no new asset
	ids, no franchise models). A body that cannot load or is not allowed leaves the Part build exactly as it is.
	Owner-first by the plot owner. ]]

local HangarDockConfig = {
	Enabled = true,
	OwnerFirst = true, -- NEW-OWNER-FIRST (claude-bud JOB 58): Code Bot flips it after Shaun's phone test
	Hangar = {
		Anchor = "JetFuselage", -- one per parked jet slot (L1-3: 1, L4+: 2)
		Bodies = { "FighterJet", "ReconPlane" }, -- slot 1, slot 2 (live refs: every player sees them)
		FitLength = 16, -- studs, nose to tail: the Part jet is 15 + its nose
		FloorDrop = 2.4, -- the Part jet's centre is this far over the hangar floor
		Hide = { "JetFuselage", "JetNose", "JetCanopy", "JetWing", "JetTailplane", "JetFin", "JetExhaust", "JetGear", "JetRoundel" },
		HideRadius = 10, -- only Part-jet pieces this close to a placed body go
	},
	Dock = {
		Anchor = "BoatHull",
		Bodies = { "LandingCraft", "PatrolBoat" }, -- the first one with an allowed body (owner-only bodies today)
		FitLength = 20,
		Sink = 0.6, -- the keel this far under the boot-top's bottom (sits in the water)
		Hide = { "BoatBoot", "BoatHull", "BoatForecastle", "BoatBow", "BoatStem", "BoatStrake", "BoatDeck", "BoatBulwark", "BoatWheelhouse",
			"BoatBridgeGlass", "BoatWheelhouseRoof", "BoatMast", "BoatRadarBar", "BoatMastLight", "BoatBowRail", "BoatGunMount",
			"BoatGunBarrel", "BoatExhaust", "BoatLifeRing", "BoatFender" },
		HideRadius = 16,
	},
	ResyncDelay = 1.5, -- after a level change, the Part build is rebuilt first
}

return HangarDockConfig
