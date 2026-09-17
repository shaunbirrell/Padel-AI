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
	-- Balancing stubs (hooks for later tuning / soft locks)
	MaxPersonalTerritories = 3,
	ProtectionPeriodSeconds = 45, -- after capture, progress against owner is slowed/blocked
	CaptureTickSeconds = 0.5,
	ProgressDecayPerSecond = 0.35, -- when empty / contested
	ContestedProgressMult = 0, -- no progress while contested
	ProtectedCaptureMult = 0.25, -- capturing protected enemy territory is slower
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
			Radius = 40,
			Color = Color3.fromRGB(200, 200, 80),
		},
		NorthRidge = {
			Id = "NorthRidge",
			DisplayName = "North Ridge",
			Description = "+5% XP from all sources.",
			CaptureTimeSeconds = 25,
			BonusType = "XPMult",
			BonusValue = 0.05,
			Position = Vector3.new(0, 1, -350),
			Radius = 35,
			Color = Color3.fromRGB(80, 160, 220),
		},
		SouthDocks = {
			Id = "SouthDocks",
			DisplayName = "South Docks",
			Description = "+15% mission cash rewards.",
			CaptureTimeSeconds = 25,
			BonusType = "MissionCashMult",
			BonusValue = 0.15,
			Position = Vector3.new(0, 1, 350),
			Radius = 35,
			Color = Color3.fromRGB(70, 140, 180),
		},
		EastArmory = {
			Id = "EastArmory",
			DisplayName = "East Armory",
			Description = "+10% weapon damage.",
			CaptureTimeSeconds = 30,
			BonusType = "DamageMult",
			BonusValue = 0.10,
			Position = Vector3.new(350, 1, 0),
			Radius = 30,
			Color = Color3.fromRGB(200, 80, 80),
		},
		WestDepot = {
			Id = "WestDepot",
			DisplayName = "West Depot",
			Description = "Vehicle spawn cooldown -20%.",
			CaptureTimeSeconds = 30,
			BonusType = "VehicleCooldownMult",
			BonusValue = -0.20,
			Position = Vector3.new(-350, 1, 0),
			Radius = 30,
			Color = Color3.fromRGB(100, 180, 100),
		},
		OilFields = {
			Id = "OilFields",
			DisplayName = "Oil Fields",
			Description = "+50 Cash per passive tick.",
			CaptureTimeSeconds = 35,
			BonusType = "FlatPassiveCash",
			BonusValue = 50,
			Position = Vector3.new(250, 1, 250),
			Radius = 40,
			Color = Color3.fromRGB(180, 140, 60),
		},
		RadarHill = {
			Id = "RadarHill",
			DisplayName = "Radar Hill",
			Description = "Reveal enemies on minimap (stub).",
			CaptureTimeSeconds = 40,
			BonusType = "MinimapReveal",
			BonusValue = 1,
			Position = Vector3.new(-250, 1, -250),
			Radius = 35,
			Color = Color3.fromRGB(160, 100, 200),
		},
	} :: { [string]: TerritoryDef },
}

return TerritoryConfig
