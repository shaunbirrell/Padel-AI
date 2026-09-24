--!strict
--[[ Weapon definitions — damage/fireRate server-authoritative later ]]

export type WeaponDef = {
	Id: string,
	DisplayName: string,
	Rarity: string,
	UnlockLevel: number,
	Damage: number,
	FireRate: number, -- shots per second
	MagazineSize: number,
	ReloadTime: number,
	Range: number,
	Spread: number,
	CostCash: number?, -- v69: > 0 = sold in Shop › WEAPONS at this server-side price; 0 / nil = not sold
	Pellets: number?, -- shotgun-style; server applies Damage * Pellets max
}

local WeaponConfig = {
	Weapons = {
		StarterRifle = {
			Id = "StarterRifle",
			DisplayName = "Starter Rifle",
			Rarity = "Common",
			UnlockLevel = 1,
			Damage = 18,
			FireRate = 8,
			MagazineSize = 30,
			ReloadTime = 2.2,
			Range = 120,
			Spread = 2.5,
			CostCash = 0,
		},
		AssaultRifle = {
			Id = "AssaultRifle",
			DisplayName = "Assault Rifle",
			Rarity = "Common",
			UnlockLevel = 3,
			Damage = 22,
			FireRate = 9,
			MagazineSize = 30,
			ReloadTime = 2.0,
			Range = 140,
			Spread = 2.0,
			CostCash = 5000,
		},
		SMG = {
			Id = "SMG",
			DisplayName = "SMG",
			Rarity = "Common",
			UnlockLevel = 4,
			Damage = 14,
			FireRate = 14,
			MagazineSize = 40,
			ReloadTime = 1.8,
			Range = 80,
			Spread = 4.0,
			CostCash = 6500,
		},
		Pistol = {
			Id = "Pistol",
			DisplayName = "Sidearm Pistol",
			Rarity = "Common",
			UnlockLevel = 1,
			Damage = 20,
			FireRate = 4,
			MagazineSize = 12,
			ReloadTime = 1.5,
			Range = 60,
			Spread = 1.5,
			CostCash = 1500,
		},
		Shotgun = {
			Id = "Shotgun",
			DisplayName = "Combat Shotgun",
			Rarity = "Uncommon",
			UnlockLevel = 6,
			Damage = 12, -- per pellet conceptually; Combat will apply pellet count
			FireRate = 1.2,
			MagazineSize = 6,
			ReloadTime = 3.0,
			Range = 40,
			Spread = 8.0,
			CostCash = 12000,
			Pellets = 6,
		},
		Sniper = {
			Id = "Sniper",
			DisplayName = "Sniper Rifle",
			Rarity = "Rare",
			UnlockLevel = 10,
			Damage = 85,
			FireRate = 0.8,
			MagazineSize = 5,
			ReloadTime = 3.2,
			Range = 400,
			Spread = 0.3,
			CostCash = 25000,
		},
		RocketLauncher = {
			Id = "RocketLauncher",
			DisplayName = "Rocket Launcher",
			Rarity = "Epic",
			UnlockLevel = 14,
			Damage = 150,
			FireRate = 0.4,
			MagazineSize = 1,
			ReloadTime = 4.0,
			Range = 250,
			Spread = 0.5,
			CostCash = 50000,
		},
		Grenade = {
			Id = "Grenade",
			DisplayName = "Frag Grenade",
			Rarity = "Uncommon",
			UnlockLevel = 5,
			Damage = 60,
			FireRate = 0.5,
			MagazineSize = 1,
			ReloadTime = 1.0,
			Range = 50,
			Spread = 0,
			CostCash = 8000,
		},
	} :: { [string]: WeaponDef },

	DefaultWeapon = "StarterRifle",
}

--[[ v69: one weapon order for Shop › WEAPONS rows and the Q/E / mobile ◀ ▶ cycle:
	UnlockLevel, then CostCash, then id. ]]
function WeaponConfig.SortedIds(): { string }
	local ids: { string } = {}
	for id in pairs(WeaponConfig.Weapons) do
		table.insert(ids, id)
	end
	table.sort(ids, function(a: string, b: string): boolean
		local da, db = WeaponConfig.Weapons[a], WeaponConfig.Weapons[b]
		if da.UnlockLevel ~= db.UnlockLevel then
			return da.UnlockLevel < db.UnlockLevel
		end
		local ca, cb = tonumber(da.CostCash) or 0, tonumber(db.CostCash) or 0
		if ca ~= cb then
			return ca < cb
		end
		return a < b
	end)
	return ids
end

--[[ v69: parse the server's owned-weapons player attribute (WE_Weapons = "Pistol,StarterRifle", written by
	CombatService) into a set of known weapon ids. The default weapon is always owned (server EnsureStarter).
	Display / input filtering only — the server re-validates every equip and purchase. ]]
function WeaponConfig.ParseOwned(raw: any): { [string]: boolean }
	local set: { [string]: boolean } = {}
	if typeof(raw) == "string" then
		for id in string.gmatch(raw, "[^,]+") do
			if WeaponConfig.Weapons[id] ~= nil then
				set[id] = true
			end
		end
	end
	set[WeaponConfig.DefaultWeapon] = true
	return set
end

return WeaponConfig
