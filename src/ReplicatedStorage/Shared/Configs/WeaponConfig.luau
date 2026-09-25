--!strict
--[[ Weapon definitions — damage/fireRate server-authoritative later ]]

-- W2 Combat Core (contracts §5.1): additive feel fields. Every field is optional; nil keeps today's behaviour.
export type RecoilDef = { Kick: number, Side: number, Recover: number } -- deg pitch / max deg yaw jitter / spring speed
export type FalloffDef = { Start: number, MinMult: number } -- server damage: full to Start, MinMult at Range
export type ProjectileDef = {
	Speed: number, -- studs/s
	GravityFactor: number, -- × Workspace.Gravity (0 = straight line)
	Splash: number, -- splash radius (studs)
	SplashMinMult: number, -- damage mult at the splash edge
	MaxSeconds: number, -- explodes here if nothing was hit
	MeshId: number?, -- 0 = Part body (asset shortlist §6.2 C4)
	TextureId: number?,
}

export type WeaponDef = {
	Id: string,
	DisplayName: string,
	ShortName: string?, -- v70: hotbar slot label (upper case, fits a 64 v slot); nil = DisplayName upper-cased
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
	-- W2 (contracts §5.1). Spread above is CLIENT-ONLY cosmetic (tracer jitter + reticle bloom); the server applies
	-- no spread in W2.
	Visual: string?, -- Part-kit gun model key (nil = "Rifle")
	VisualAssetId: number?, -- 0 / nil = Part kit; > 0 = WeaponAssetLoader template WE_WeaponTemplates["Weapon_<Id>"]
	VisualToolName: string?, -- Tool name inside the asset (nil = the first Tool)
	VisualChild: string?, -- Model child of that Tool holding the parts (nil = the Tool's own parts)
	Tracer: boolean?, -- nil = true unless Projectile
	Recoil: RecoilDef?,
	Falloff: FalloffDef?, -- nil = no damage fall-off
	Projectile: ProjectileDef?, -- set = launched as a server projectile (no hitscan, no assist)
}

local WeaponConfig = {
	Weapons = {
		StarterRifle = {
			Id = "StarterRifle",
			DisplayName = "Starter Rifle",
			ShortName = "RIFLE",
			Rarity = "Common",
			UnlockLevel = 1,
			Damage = 18,
			FireRate = 8,
			MagazineSize = 30,
			ReloadTime = 2.2,
			Range = 120,
			Spread = 2.5,
			CostCash = 0,
			Visual = "Rifle",
			VisualAssetId = 4842207161, -- Roblox Weapons Kit (owner list 2026-09-25; docs/ASSET_WIRING.md)
			VisualToolName = "AR",
			VisualChild = "AR",
			Tracer = true,
			Recoil = { Kick = 0.6, Side = 0.25, Recover = 12 },
			Falloff = { Start = 110, MinMult = 0.7 },
		},
		AssaultRifle = {
			Id = "AssaultRifle",
			DisplayName = "Assault Rifle",
			ShortName = "AR",
			Rarity = "Common",
			UnlockLevel = 3,
			Damage = 22,
			FireRate = 9,
			MagazineSize = 30,
			ReloadTime = 2.0,
			Range = 140,
			Spread = 2.0,
			CostCash = 5000,
			Visual = "Carbine",
			VisualAssetId = 4842207161, -- Roblox Weapons Kit (owner list 2026-09-25; docs/ASSET_WIRING.md)
			VisualToolName = "AR",
			VisualChild = "AR",
			Tracer = true,
			Recoil = { Kick = 0.7, Side = 0.3, Recover = 12 },
			Falloff = { Start = 110, MinMult = 0.7 },
		},
		SMG = {
			Id = "SMG",
			DisplayName = "SMG",
			ShortName = "SMG",
			Rarity = "Common",
			UnlockLevel = 4,
			Damage = 14,
			FireRate = 14,
			MagazineSize = 40,
			ReloadTime = 1.8,
			Range = 80,
			Spread = 4.0,
			CostCash = 6500,
			Visual = "SMG",
			VisualAssetId = 4842212980, -- Roblox Weapons Kit (owner list 2026-09-25; docs/ASSET_WIRING.md)
			VisualToolName = "SMG",
			VisualChild = "SMG",
			Tracer = true,
			Recoil = { Kick = 0.45, Side = 0.35, Recover = 14 },
			Falloff = { Start = 50, MinMult = 0.6 },
		},
		Pistol = {
			Id = "Pistol",
			DisplayName = "Sidearm Pistol",
			ShortName = "PISTOL",
			Rarity = "Common",
			UnlockLevel = 1,
			Damage = 20,
			FireRate = 4,
			MagazineSize = 12,
			ReloadTime = 1.5,
			Range = 60,
			Spread = 1.5,
			CostCash = 1500,
			Visual = "Pistol",
			VisualAssetId = 4842197274, -- Roblox Weapons Kit (owner list 2026-09-25; docs/ASSET_WIRING.md)
			VisualToolName = "Pistol",
			VisualChild = "Pistol",
			Tracer = true,
			Recoil = { Kick = 1.0, Side = 0.2, Recover = 10 },
			Falloff = { Start = 40, MinMult = 0.7 },
		},
		Shotgun = {
			Id = "Shotgun",
			DisplayName = "Combat Shotgun",
			ShortName = "SHOTGUN",
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
			Visual = "Shotgun",
			VisualAssetId = 4842215723, -- Roblox Weapons Kit (owner list 2026-09-25; docs/ASSET_WIRING.md)
			VisualToolName = "Shotgun",
			VisualChild = "Shotgun",
			Tracer = true,
			Recoil = { Kick = 2.2, Side = 0.5, Recover = 8 },
			Falloff = { Start = 18, MinMult = 0.4 },
		},
		Sniper = {
			Id = "Sniper",
			DisplayName = "Sniper Rifle",
			ShortName = "SNIPER",
			Rarity = "Rare",
			UnlockLevel = 10,
			Damage = 85,
			FireRate = 0.8,
			MagazineSize = 5,
			ReloadTime = 3.2,
			Range = 400,
			Spread = 0.3,
			CostCash = 25000,
			Visual = "LongRifle",
			VisualAssetId = 4842218829, -- Roblox Weapons Kit (owner list 2026-09-25; docs/ASSET_WIRING.md)
			VisualToolName = "Sniper",
			VisualChild = "Sniper",
			Tracer = true,
			Recoil = { Kick = 2.8, Side = 0.3, Recover = 6 },
		},
		RocketLauncher = {
			Id = "RocketLauncher",
			DisplayName = "Rocket Launcher",
			ShortName = "RPG",
			Rarity = "Epic",
			UnlockLevel = 14,
			Damage = 150,
			FireRate = 0.4,
			MagazineSize = 1,
			ReloadTime = 4.0,
			Range = 250,
			Spread = 0.5,
			CostCash = 50000,
			Visual = "Launcher",
			VisualAssetId = 4842186817, -- Roblox Weapons Kit (owner list 2026-09-25; docs/ASSET_WIRING.md)
			VisualToolName = "Rocket Launcher",
			VisualChild = "RocketLauncher",
			Tracer = false,
			Recoil = { Kick = 3.0, Side = 0.4, Recover = 5 },
			Projectile = { Speed = 140, GravityFactor = 0, Splash = 10, SplashMinMult = 0.3, MaxSeconds = 1.9, MeshId = 94690081, TextureId = 94689966 }, -- Roblox rocket mesh (owner list "CruiseMissile")
		},
		Grenade = {
			Id = "Grenade",
			DisplayName = "Frag Grenade",
			ShortName = "FRAG",
			Rarity = "Uncommon",
			UnlockLevel = 5,
			Damage = 60,
			FireRate = 0.5,
			MagazineSize = 1,
			ReloadTime = 1.0,
			Range = 50,
			Spread = 0,
			CostCash = 8000,
			Visual = "Grenade",
			VisualAssetId = 0,
			Tracer = false,
			Recoil = { Kick = 0.8, Side = 0.2, Recover = 8 },
			Projectile = { Speed = 80, GravityFactor = 0.3, Splash = 12, SplashMinMult = 0.25, MaxSeconds = 1.6, MeshId = 232379763, TextureId = 232379808 }, -- Roblox grenade mesh
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
