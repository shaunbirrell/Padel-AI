--!strict
--[[ Toast type colors — Success/Collect are high-contrast green (competitive P0). ]]

local NotificationConfig = {
	DefaultDuration = 4,
	MaxStacked = 4,
	Types = {
		Info = { Color = Color3.fromRGB(90, 160, 220), Fill = Color3.fromRGB(18, 28, 40) },
		-- High-contrast success (competitor "Purchase SUCCESSFUL!" readability)
		Success = { Color = Color3.fromRGB(40, 255, 120), Fill = Color3.fromRGB(8, 48, 22) },
		Collect = { Color = Color3.fromRGB(60, 255, 140), Fill = Color3.fromRGB(6, 42, 20) },
		Warn = { Color = Color3.fromRGB(255, 200, 60), Fill = Color3.fromRGB(40, 32, 10) },
		Error = { Color = Color3.fromRGB(255, 80, 80), Fill = Color3.fromRGB(48, 12, 12) },
		Reward = { Color = Color3.fromRGB(255, 210, 90), Fill = Color3.fromRGB(40, 32, 12) },
	},
}

return NotificationConfig
