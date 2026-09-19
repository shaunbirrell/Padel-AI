--!strict
--[[
	Redeemable promo codes (Cash / Gold). Server validates once per code per player.
	Sample codes only — rotate for live seasons.
]]

export type CodeReward = {
	Cash: number?,
	Gold: number?,
	DisplayName: string?,
}

local CodesConfig = {
	-- Normalize: uppercase, strip spaces
	MaxCodeLength = 32,
	Codes = {
		WARFOUNDING = {
			Cash = 15000,
			Gold = 5,
			DisplayName = "War Founding",
		},
		BUILDCONQUER = {
			Cash = 8000,
			Gold = 2,
			DisplayName = "Build & Conquer",
		},
	} :: { [string]: CodeReward },
}

return CodesConfig
