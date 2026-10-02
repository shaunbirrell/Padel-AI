--!strict
--[[
	Periodic Supply Drops (loot-crate theme) — stand near crate to claim Cash.
	World spawns only; not a paid RNG loot box (see LootBoxConfig.PolicyPending).

	W3 step 2, lane F (spec w3s2 §3): a crate is 2 parts (crate + lid; no Neon ring, beacon ball or straps) and at
	most 2 exist, so the busiest 512-stud circle stays <= 500 with the bank's transients (489 static + 2 × 2 crate
	parts + up to 4 dropped bags in Phase B = 497). LifetimeSeconds 120 > SpawnIntervalSeconds 90, so a crate
	overlaps the next one for 30 s and MaxActive 2 is the real cap.
]]

local AdminConfig = require(script.Parent.AdminConfig)

local SupplyDropConfig = {
	Enabled = true,
	SpawnIntervalSeconds = 90,
	MaxActive = 2,
	LifetimeSeconds = 120,
	ClaimHoldSeconds = 2.5,
	ClaimRadius = 10,
	CashMin = 2500,
	CashMax = 12000,
	-- Prefer WE_EventSpawn pads; else scatter on open ground
	ScatterRadius = 900,
	ScatterMinDistanceFromOrigin = 120,
	CrateSize = Vector3.new(5, 4, 5),
	CrateColor = Color3.fromRGB(210, 160, 55),
	LidColor = Color3.fromRGB(180, 140, 50),
	LabelLiftStuds = 3, -- label centre above the lid

	--[[ claude-bud JOB 4.1 (2026-09-29): the parachute AIRDROP. Every IntervalSeconds (while a player it is live for is
		in the server) one crate falls from DropHeight under a canopy (FallSeconds) onto a random open spot (the same
		picker as the crates: event pads, else open ground), shows an objective marker to those players, and the FIRST
		of them to hold ClaimHoldSeconds within ClaimRadius gets Cash (server-side, EconomyService.AddCash). Gone after
		LifetimeSeconds. 3 parts while falling (crate, lid, canopy), 2 on the ground. Rollout "owner" =
		AdminConfig.IsPlaytestOwner only, "all" = everyone, anything else = off (the game as before). ]]
	Airdrop = {
		Rollout = "all", -- v101
		FirstDelaySeconds = 60,
		IntervalSeconds = 600,
		DropHeight = 160,
		FallSeconds = 12,
		LifetimeSeconds = 300,
		ClaimRadius = 12,
		ClaimHoldSeconds = 2,
		CashMin = 15000,
		CashMax = 40000,
		CanopyColor = Color3.fromRGB(96, 110, 70),
	},
}

-- claude-bud: is the airdrop live for this player (fail closed)
function SupplyDropConfig.AirdropLiveFor(userId: any): boolean
	if (require(script.Parent.MonetizationConfig) :: any).Launched("Airdrop") then
		return true -- claude-bud JOB 12: MonetizationConfig.LaunchAll
	end
	local mode = SupplyDropConfig.Airdrop.Rollout
	if mode == "all" then
		return true
	elseif mode == "owner" then
		return AdminConfig.IsPlaytestOwner(userId)
	end
	return false
end

--[[ Code Bot board-text (Shaun: "a yellow guide line leads me to every airdrop: let me turn it off"). The AIRDROP guide
	(ObjectiveMarker's GO line + its marker) can be hidden: a big "HIDE LINE" button while it shows (that airdrop stays
	hidden; a new airdrop guides again) and a Settings toggle "Airdrop guide line: ON / OFF" (saved per player in the
	NEW key profile.Settings[GuideHide.SettingKey]; no existing save key is touched; the server mirrors it as the player
	attribute GuideHide.Attr). The Shop's FREE Airdrop TRACK row still guides on purpose (an explicit tap).
	PUBLIC (RetentionConfig.Live: owner 470626172 + Studio). ]]
SupplyDropConfig.GuideHide = {
	Enabled = true,
	OwnerFirst = false, -- PUBLIC (Code Bot v215): Shaun approved the airdrop guide controls for everyone
	SettingKey = "AirdropGuideOff", -- NEW save key (profile.Settings.AirdropGuideOff = true | nil)
	Attr = "WE_AirdropGuideOff",
	Remote = "RequestAirdropGuideSetting", -- = Constants.RemoteNames.RequestAirdropGuideSetting (client -> server boolean, AirdropGuideService)
	ButtonText = "✕  HIDE LINE",
	ButtonSize = Vector2.new(220, 64), -- v (HudLayout scale; >= 44 real px on a phone)
	StackOrder = 31, -- the HUD top stack, right under the Objective row (30), above the toasts (40)
}

function SupplyDropConfig.GuideHideLiveFor(userId: any): boolean
	return (require(script.Parent.RetentionConfig) :: any).Live(SupplyDropConfig.GuideHide, userId) == true
end

return SupplyDropConfig
