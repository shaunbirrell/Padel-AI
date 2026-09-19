--!strict
--[[
	14 structure types, 5 levels each.
	Barracks costs match spec: 2500, 10000, 35000, 100000, 300000.
	Other structures use similar escalating curves.
]]

export type StructureDef = {
	Id: string,
	DisplayName: string,
	Description: string,
	MaxLevel: number,
	Costs: { number }, -- Cash cost to purchase level 1..MaxLevel (index = target level)
	Currency: "Cash" | "Gold",
	Requires: { { StructureId: string, Level: number } }?,
	PassiveIncomeBonus: number?, -- extra flat cash/tick at each level (also in EconomyConfig)
}

local function costs(a: number, b: number, c: number, d: number, e: number): { number }
	return { a, b, c, d, e }
end

local BaseConfig = {
	MaxPlots = 6,
	PlotSize = Vector3.new(140, 1, 140),
	-- World positions — keep in sync with MapSetup PLOT_POSITIONS (ring ~450)
	PlotPositions = {
		Vector3.new(-450, 0.5, -225),
		Vector3.new(-450, 0.5, 225),
		Vector3.new(0, 0.5, -450),
		Vector3.new(0, 0.5, 450),
		Vector3.new(450, 0.5, -225),
		Vector3.new(450, 0.5, 225),
	} :: { Vector3 },

	Structures = {
		CommandCenter = {
			Id = "CommandCenter",
			DisplayName = "Command Center",
			Description = "HQ for your base. Unlocks further construction.",
			MaxLevel = 5,
			Costs = costs(1500, 8000, 30000, 90000, 250000),
			Currency = "Cash",
			Requires = nil,
		},
		Barracks = {
			Id = "Barracks",
			DisplayName = "Barracks",
			Description = "Train and house soldiers. Strong passive income.",
			MaxLevel = 5,
			Costs = costs(2500, 10000, 35000, 100000, 300000),
			Currency = "Cash",
			Requires = { { StructureId = "CommandCenter", Level = 1 } },
		},
		VehicleDepot = {
			Id = "VehicleDepot",
			DisplayName = "Vehicle Depot",
			Description = "Maintain and unlock ground vehicles.",
			MaxLevel = 5,
			Costs = costs(3000, 12000, 40000, 120000, 350000),
			Currency = "Cash",
			Requires = { { StructureId = "CommandCenter", Level = 1 } },
		},
		WeaponsFacility = {
			Id = "WeaponsFacility",
			DisplayName = "Weapons Facility",
			Description = "Research and unlock advanced weapons.",
			MaxLevel = 5,
			Costs = costs(2800, 11000, 38000, 110000, 320000),
			Currency = "Cash",
			Requires = { { StructureId = "CommandCenter", Level = 1 } },
		},
		Helipad = {
			Id = "Helipad",
			DisplayName = "Helipad",
			Description = "Landing pad for rotary-wing aircraft.",
			MaxLevel = 5,
			Costs = costs(5000, 20000, 70000, 200000, 500000),
			Currency = "Cash",
			Requires = { { StructureId = "VehicleDepot", Level = 2 } },
		},
		Airfield = {
			Id = "Airfield",
			DisplayName = "Airfield",
			Description = "Runway for fixed-wing fighters.",
			MaxLevel = 5,
			Costs = costs(8000, 35000, 120000, 350000, 900000),
			Currency = "Cash",
			Requires = { { StructureId = "Helipad", Level = 2 } },
		},
		DefensiveWalls = {
			Id = "DefensiveWalls",
			DisplayName = "Defensive Walls",
			Description = "Perimeter fortifications.",
			MaxLevel = 5,
			Costs = costs(2000, 9000, 32000, 95000, 280000),
			Currency = "Cash",
			Requires = { { StructureId = "CommandCenter", Level = 1 } },
		},
		Watchtowers = {
			Id = "Watchtowers",
			DisplayName = "Watchtowers",
			Description = "Elevated lookouts and light defense.",
			MaxLevel = 5,
			Costs = costs(2200, 9500, 34000, 98000, 290000),
			Currency = "Cash",
			Requires = { { StructureId = "DefensiveWalls", Level = 1 } },
		},
		Radar = {
			Id = "Radar",
			DisplayName = "Radar Station",
			Description = "Early warning and map intel.",
			MaxLevel = 5,
			Costs = costs(4000, 16000, 55000, 160000, 450000),
			Currency = "Cash",
			Requires = { { StructureId = "CommandCenter", Level = 2 } },
		},
		ResearchLab = {
			Id = "ResearchLab",
			DisplayName = "Research Lab",
			Description = "Tech bonuses and prestige prep.",
			MaxLevel = 5,
			Costs = costs(4500, 18000, 60000, 180000, 480000),
			Currency = "Cash",
			Requires = { { StructureId = "CommandCenter", Level = 2 } },
		},
		MissileDefense = {
			Id = "MissileDefense",
			DisplayName = "Missile Defense",
			Description = "Anti-air / anti-missile batteries.",
			MaxLevel = 5,
			Costs = costs(6000, 25000, 85000, 250000, 700000),
			Currency = "Cash",
			Requires = { { StructureId = "Radar", Level = 2 } },
		},
		PowerStation = {
			Id = "PowerStation",
			DisplayName = "Power Station",
			Description = "Powers advanced systems; income boost.",
			MaxLevel = 5,
			Costs = costs(3500, 14000, 48000, 140000, 400000),
			Currency = "Cash",
			Requires = { { StructureId = "CommandCenter", Level = 1 } },
		},
		Warehouse = {
			Id = "Warehouse",
			DisplayName = "Warehouse",
			Description = "Storage logistics — strongest passive income.",
			MaxLevel = 5,
			Costs = costs(3200, 13000, 45000, 130000, 380000),
			Currency = "Cash",
			Requires = { { StructureId = "CommandCenter", Level = 1 } },
		},
		SpecialForcesFacility = {
			Id = "SpecialForcesFacility",
			DisplayName = "Special Forces Facility",
			Description = "Elite units and late-game power.",
			MaxLevel = 5,
			Costs = costs(10000, 40000, 150000, 400000, 1_200_000),
			Currency = "Cash",
			Requires = { { StructureId = "Barracks", Level = 3 }, { StructureId = "ResearchLab", Level = 2 } },
		},
	} :: { [string]: StructureDef },

	-- Order for upgrade UI
	StructureOrder = {
		"CommandCenter",
		"Barracks",
		"VehicleDepot",
		"WeaponsFacility",
		"PowerStation",
		"Warehouse",
		"DefensiveWalls",
		"Watchtowers",
		"Radar",
		"ResearchLab",
		"Helipad",
		"Airfield",
		"MissileDefense",
		"SpecialForcesFacility",
	},
}

return BaseConfig
