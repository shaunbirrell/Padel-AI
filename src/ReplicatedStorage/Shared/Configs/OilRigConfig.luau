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
	CaptureRadius = 42,
	-- Positions (offshore on ~2600 map)
	Rigs = {
		{
			Id = "CoastalOilAlpha",
			DisplayName = "Coastal Oil Alpha",
			Position = Vector3.new(980, 1, -420),
			Color = Color3.fromRGB(190, 145, 45),
		},
		{
			Id = "CoastalOilBravo",
			DisplayName = "Coastal Oil Bravo",
			Position = Vector3.new(-980, 1, 420),
			Color = Color3.fromRGB(170, 125, 40),
		},
	},
}

return OilRigConfig
