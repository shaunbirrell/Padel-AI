--!strict
--[[
	Code Bot v102: redeem codes (server only — ServerScriptService, so a client can never read the list).

	HOW TO ADD A CODE (owner):
	  1. Copy the BUDSTUDIOS block below, give it a new key (the code players type). Keys are case-insensitive and
	     spaces are ignored: "budstudios", "BudStudios" and " BUD STUDIOS " all match BUDSTUDIOS. Letters, digits
	     and _ only, at most MaxCodeLength characters.
	  2. Rewards (any mix; leave out what you don't want):
	       Cash = 50000               Cash, paid exactly (never multiplied by VIP / 2x Cash / rebirth)
	       Gold = 5                   Gold
	       CashBoostMinutes = 30      a timed 2x Cash boost (real minutes from the redeem; redeeming another boost
	                                  code while one runs adds the minutes on top)
	  3. Active = true to switch it on, false to switch it off (players then see "This code has expired").
	  4. Expires = "2026-12-31" (the code stops at the END of that day, UTC) or "2026-12-31T18:00:00Z"
	     (an exact UTC time), or nil for no expiry.
	  5. Build + publish. Each player can redeem each code once; it is saved in their profile (RedeemedCodes).
]]

export type CodeRewards = {
	Cash: number?,
	Gold: number?,
	CashBoostMinutes: number?,
}

export type CodeDef = {
	Active: boolean,
	Expires: string?,
	DisplayName: string?,
	Rewards: CodeRewards,
}

local CodesConfig = {
	MaxCodeLength = 32,
	-- the timed boost from CashBoostMinutes multiplies Cash earnings by this (stacks with the passes like any
	-- other multiplier; EconomyService applies it through CodesService.GetCashBoostMult)
	CashBoostMult = 2,
	-- the longest a stacked boost can run from now (minutes), so repeated codes cannot bank days of 2x
	CashBoostMaxMinutes = 24 * 60,
	-- RedeemCode RemoteFunction rate limit: at most this many tries per player per minute
	TriesPerMinute = 5,

	Codes = {
		-- launch code (Code Bot v102)
		BUDSTUDIOS = {
			Active = true,
			Expires = nil,
			DisplayName = "Bud Studios",
			Rewards = { Cash = 50000, CashBoostMinutes = 30 },
		},
		BUDSQUAD = {
			Active = true,
			Expires = nil,
			DisplayName = "Bud Studios Discord",
			Rewards = { Cash = 25000 },
		},
		-- pre-launch sample codes, retired for launch (flip Active = true to bring one back)
		WARFOUNDING = {
			Active = false,
			Expires = nil,
			DisplayName = "War Founding",
			Rewards = { Cash = 15000, Gold = 5 },
		},
		BUILDCONQUER = {
			Active = false,
			Expires = nil,
			DisplayName = "Build & Conquer",
			Rewards = { Cash = 8000, Gold = 2 },
		},
	} :: { [string]: CodeDef },
}

return CodesConfig
