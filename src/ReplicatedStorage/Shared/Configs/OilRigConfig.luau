--!strict
--[[
	Coastal oil platform POIs — harder guards, higher capture stipends.
	Wired into TerritoryConfig Ids CoastalOilAlpha / CoastalOilBravo.
]]

local OilRigConfig = {
	PlatformHeight = 28,
	DeckSize = Vector3.new(48, 2.5, 48),
	LegCount = 4,
	GuardNPCType = "OilRigGuard",
	GuardCount = 4,
	CaptureRadius = 48,
	-- Positions (offshore on ~4800 map)
	Rigs = {
		{
			Id = "CoastalOilAlpha",
			DisplayName = "Coastal Oil Alpha",
			Position = Vector3.new(1800, 1, -750),
			Color = Color3.fromRGB(190, 145, 45),
		},
		{
			Id = "CoastalOilBravo",
			DisplayName = "Coastal Oil Bravo",
			Position = Vector3.new(-1800, 1, 750),
			Color = Color3.fromRGB(170, 125, 40),
		},
	},
}

return OilRigConfig
