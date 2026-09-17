--!strict

local NotificationConfig = {
	DefaultDuration = 4,
	MaxStacked = 4,
	Types = {
		Info = { Color = Color3.fromRGB(90, 160, 220) },
		Success = { Color = Color3.fromRGB(80, 200, 120) },
		Warn = { Color = Color3.fromRGB(230, 190, 60) },
		Error = { Color = Color3.fromRGB(200, 70, 70) },
		Reward = { Color = Color3.fromRGB(200, 160, 80) },
	},
}

return NotificationConfig
