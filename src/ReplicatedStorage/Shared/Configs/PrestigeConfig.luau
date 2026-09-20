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
	-- P0 competitive: earlier first rebirth feel (was 100). Reversible — bump back if economy too fast.
	-- See ASSUMPTIONS #108. AdminPlaytestCash 50M unchanged.
	MinLevelToPrestige = 40,
	MaxPrestige = 50,
	-- +10% cash earnings per prestige (stacking). Keep in sync with EconomyConfig.PrestigeCashMultiplierPerLevel.
	CashBonusPerPrestige = 0.10,
	GoldBonusOnPrestige = 50,
	-- Upfront cash fee to prestige (0 = none). Cash still resets to StartingCashAfterPrestige when ResetOnPrestige.Cash.
	CashFee = 0,
	ResetOnPrestige = {
		Cash = true,
		Level = true,
		XP = true,
		BaseUpgrades = true,
		KeepVehicles = true,
		KeepWeapons = true,
		KeepGold = true,
		KeepRebirthUnlocks = true,
		-- KeepTerritories / KeepOutpostIncomeStacks: implicit (fields never cleared in PrestigeService)
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

--[[ Build player-facing fee / confirm copy from config (client + server toasts). ]]
function PrestigeConfig.BuildFeeSummary(opts: { BaseCompletionPercent: number? }?): string
	local fee = tonumber(PrestigeConfig.CashFee) or 0
	local startCash = tonumber(PrestigeConfig.StartingCashAfterPrestige) or 0
	local gold = tonumber(PrestigeConfig.GoldBonusOnPrestige) or 0
	local feePart = if fee > 0 then string.format("Fee $%s", tostring(fee)) else "Fee: none"
	local parts = {
		feePart,
		string.format("Cash → $%s after", tostring(startCash)),
		string.format("+%d Gold", gold),
		"resets Level/XP/Base",
		"keeps Robux items + vehicles/weapons/gold/unlocks/outposts",
	}
	local pct = opts and tonumber(opts.BaseCompletionPercent)
	if pct ~= nil then
		table.insert(parts, string.format("Base %d%%", math.floor(pct)))
	end
	return table.concat(parts, " · ")
end

return PrestigeConfig
