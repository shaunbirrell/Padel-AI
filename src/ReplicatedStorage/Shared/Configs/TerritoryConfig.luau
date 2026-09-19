--!strict
--[[ 7 territories with control bonuses + balance stubs ]]

export type TerritoryDef = {
	Id: string,
	DisplayName: string,
	Description: string,
	CaptureTimeSeconds: number,
	BonusType: string,
	BonusValue: number,
	Position: Vector3,
	Radius: number,
	Color: Color3,
}

local TerritoryConfig = {
	-- Balance knobs
	MaxPersonalTerritories = 3,
	ProtectionPeriodSeconds = 45, -- after capture, enemy capture rate slowed
	CaptureTickSeconds = 0.5,
	ProgressDecayPerSecond = 0.35, -- when zone empty
	ContestedProgressMult = 0, -- 0 = freeze progress + light decay while contested
	ContestedDecayMult = 0.5, -- decay rate multiplier while contested (when ContestedProgressMult <= 0)
	ProtectedCaptureMult = 0.25, -- capturing protected enemy territory is slower
	RadarRevealRadius = 350, -- studs: Radar Hill highlights enemies (scaled for larger map)
	NPCOwnerId = -1, -- sentinel "NPC faction" controller
	NeutralOwnerId = 0,

	-- OwnerType strings used by TerritoryService
	OwnerTypes = {
		Neutral = "Neutral",
		Player = "Player",
		NPC = "NPC",
		Clan = "Clan",
		Contested = "Contested",
	},

	Territories = {
		CentralPlaza = {
			Id = "CentralPlaza",
			DisplayName = "Central Plaza",
			Description = "+10% Cash from passive income while controlled.",
			CaptureTimeSeconds = 20,
			BonusType = "PassiveCashMult",
			BonusValue = 0.10,
			Position = Vector3.new(0, 1, 0),
			Radius = 55,
			Color = Color3.fromRGB(200, 200, 80),
		},
		NorthRidge = {
			Id = "NorthRidge",
			DisplayName = "North Ridge",
			Description = "+5% XP from all sources.",
			CaptureTimeSeconds = 25,
			BonusType = "XPMult",
			BonusValue = 0.05,
			Position = Vector3.new(0, 1, -720),
			Radius = 50,
			Color = Color3.fromRGB(80, 160, 220),
		},
		SouthDocks = {
			Id = "SouthDocks",
			DisplayName = "South Docks",
			Description = "+15% mission cash rewards.",
			CaptureTimeSeconds = 25,
			BonusType = "MissionCashMult",
			BonusValue = 0.15,
			Position = Vector3.new(0, 1, 720),
			Radius = 50,
			Color = Color3.fromRGB(70, 140, 180),
		},
		EastArmory = {
			Id = "EastArmory",
			DisplayName = "East Armory",
			Description = "+10% weapon damage.",
			CaptureTimeSeconds = 30,
			BonusType = "DamageMult",
			BonusValue = 0.10,
			Position = Vector3.new(720, 1, 0),
			Radius = 45,
			Color = Color3.fromRGB(200, 80, 80),
		},
		WestDepot = {
			Id = "WestDepot",
			DisplayName = "West Depot",
			Description = "Vehicle spawn cooldown -20%.",
			CaptureTimeSeconds = 30,
			BonusType = "VehicleCooldownMult",
			BonusValue = -0.20,
			Position = Vector3.new(-720, 1, 0),
			Radius = 45,
			Color = Color3.fromRGB(100, 180, 100),
		},
		OilFields = {
			Id = "OilFields",
			DisplayName = "Oil Fields",
			Description = "+50 Cash per passive tick.",
			CaptureTimeSeconds = 35,
			BonusType = "FlatPassiveCash",
			BonusValue = 50,
			Position = Vector3.new(520, 1, 520),
			Radius = 55,
			Color = Color3.fromRGB(180, 140, 60),
		},
		RadarHill = {
			Id = "RadarHill",
			DisplayName = "Radar Hill",
			Description = "Enemy radar: highlight nearby hostile players within range.",
			CaptureTimeSeconds = 40,
			BonusType = "MinimapReveal",
			BonusValue = 1,
			Position = Vector3.new(-520, 1, -520),
			Radius = 50,
			Color = Color3.fromRGB(160, 100, 200),
		},
	} :: { [string]: TerritoryDef },
}

return TerritoryConfig
