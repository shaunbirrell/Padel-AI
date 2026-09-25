--!strict
--[[
	Periodic Supply Drops (loot-crate theme) — stand near crate to claim Cash.
	World spawns only; not a paid RNG loot box (see LootBoxConfig.PolicyPending).

	W3 step 2, lane F (spec w3s2 §3): a crate is 2 parts (crate + lid; no Neon ring, beacon ball or straps) and at
	most 2 exist, so the busiest 512-stud circle stays <= 500 with the bank's transients (489 static + 2 × 2 crate
	parts + up to 4 dropped bags in Phase B = 497). LifetimeSeconds 120 > SpawnIntervalSeconds 90, so a crate
	overlaps the next one for 30 s and MaxActive 2 is the real cap.
]]

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
}

return SupplyDropConfig
