--!strict
--[[ Prestige / Rebirth reset rules.
	Cash mult at runtime uses EconomyConfig.PrestigeCashMultiplierPerLevel (+10%/prestige).
	RebirthUnlocks: applied when Prestige reaches AtPrestige (stacking permanent flags + optional grants).
]]

export type RebirthUnlockDef = {
	AtPrestige: number,
	Flag: string,
	DisplayName: string,
	Kind: "Flag" | "Vehicle" | "Weapon" | "Structure",
	Id: string?, -- Vehicle/Weapon/Structure id when Kind is not Flag-only
	GrantOwned: boolean?, -- auto-grant Vehicles[Id] / Weapons[Id]
}

local PrestigeConfig = {
	MinLevelToPrestige = 100,
	MaxPrestige = 50,
	-- +10% cash earnings per prestige (stacking). Keep in sync with EconomyConfig.PrestigeCashMultiplierPerLevel.
	CashBonusPerPrestige = 0.10,
	GoldBonusOnPrestige = 50,
	ResetOnPrestige = {
		Cash = true,
		Level = true,
		XP = true,
		BaseUpgrades = true,
		KeepVehicles = true,
		KeepWeapons = true,
		KeepGold = true,
		KeepRebirthUnlocks = true,
	},
	StartingCashAfterPrestige = 10000,

	--[[
		Unlock track (shown in K panel). Flags land in profile.RebirthUnlocks.
		GrantOwned vehicles/weapons are given permanently (kept through further prestiges).
	]]
	RebirthUnlocks = {
		{
			AtPrestige = 1,
			Flag = "RebirthScout",
			DisplayName = "Scout Car (owned)",
			Kind = "Vehicle",
			Id = "ScoutCar",
			GrantOwned = true,
		},
		{
			AtPrestige = 2,
			Flag = "NavalAccess",
			DisplayName = "Naval Access + Patrol Boat",
			Kind = "Vehicle",
			Id = "PatrolBoat",
			GrantOwned = true,
		},
		{
			AtPrestige = 3,
			Flag = "SupplyLine",
			DisplayName = "Supply Truck (owned)",
			Kind = "Vehicle",
			Id = "SupplyTruck",
			GrantOwned = true,
		},
		{
			AtPrestige = 4,
			Flag = "MissileBoatGrant",
			DisplayName = "Missile Boat (owned)",
			Kind = "Vehicle",
			Id = "MissileBoat",
			GrantOwned = true,
		},
		{
			AtPrestige = 5,
			Flag = "AirLift",
			DisplayName = "Transport Heli (owned)",
			Kind = "Vehicle",
			Id = "TransportHeli",
			GrantOwned = true,
		},
		{
			AtPrestige = 7,
			Flag = "GunboatFleet",
			DisplayName = "Gunboat (owned)",
			Kind = "Vehicle",
			Id = "Gunboat",
			GrantOwned = true,
		},
		{
			AtPrestige = 8,
			Flag = "AssaultArmor",
			DisplayName = "Assault IFV (owned)",
			Kind = "Vehicle",
			Id = "AssaultIFV",
			GrantOwned = true,
		},
		{
			AtPrestige = 10,
			Flag = "EmpireElite",
			DisplayName = "Empire Elite (unlocks Super Heavy)",
			Kind = "Flag",
			Id = nil,
			GrantOwned = false,
		},
		{
			AtPrestige = 12,
			Flag = "EmpireFleet",
			DisplayName = "Empire Fleet (Battleship gate)",
			Kind = "Flag",
			Id = nil,
			GrantOwned = false,
		},
		{
			AtPrestige = 15,
			Flag = "DestroyerGrant",
			DisplayName = "Destroyer (owned)",
			Kind = "Vehicle",
			Id = "Destroyer",
			GrantOwned = true,
		},
		{
			AtPrestige = 18,
			Flag = "CruiserGrant",
			DisplayName = "Cruiser (owned)",
			Kind = "Vehicle",
			Id = "Cruiser",
			GrantOwned = true,
		},
		{
			AtPrestige = 16,
			Flag = "FrigateGrant",
			DisplayName = "Frigate (owned)",
			Kind = "Vehicle",
			Id = "Frigate",
			GrantOwned = true,
		},
		{
			AtPrestige = 20,
			Flag = "StrikeWing",
			DisplayName = "Strike Jet + Heavy Bomber gate",
			Kind = "Vehicle",
			Id = "StrikeJet",
			GrantOwned = true,
		},
	} :: { RebirthUnlockDef },
}

return PrestigeConfig
