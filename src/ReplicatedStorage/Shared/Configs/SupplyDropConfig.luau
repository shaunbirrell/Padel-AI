--!strict
--[[
	Periodic Supply Drops (loot-crate theme) — stand near crate to claim Cash.
	World spawns only; not a paid RNG loot box (see LootBoxConfig.PolicyPending).
]]

local SupplyDropConfig = {
	Enabled = true,
	SpawnIntervalSeconds = 90,
	MaxActive = 3,
	LifetimeSeconds = 75,
	ClaimHoldSeconds = 2.5,
	ClaimRadius = 10,
	CashMin = 2500,
	CashMax = 12000,
	-- Prefer WE_EventSpawn pads; else scatter on open ground
	ScatterRadius = 900,
	ScatterMinDistanceFromOrigin = 120,
	CrateSize = Vector3.new(5, 4, 5),
	CrateColor = Color3.fromRGB(210, 160, 55),
	BeaconColor = Color3.fromRGB(255, 200, 80),
}

return SupplyDropConfig
