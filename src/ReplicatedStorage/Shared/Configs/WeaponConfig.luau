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
	-- claude-bud JOB 35 (Shared/Util/GunMechanics; nil = unchanged for every existing gun; all server-authoritative)
	Burst: { Count: number, Gap: number }?, -- one trigger cycle = Count shots Gap s apart; FireRate = cycles / s
	SpinUp: number?, -- seconds of barrel spin before the first shot (a "Spin" prime starts it)
	ChargeSeconds: number?, -- seconds of charge per shot (a "Charge" prime starts it; the shot fires on release)
	Pierce: number?, -- hitscan: up to this many players / NPCs in a line
	HeadshotMult: number?, -- this gun's headshot multiplier (nil = CombatFeelConfig.HeadshotMult)
	Scope: boolean?, -- client: RMB / L2 / the SCOPE button zooms (PremiumGunsConfig.Scope)
	Premium: boolean?, -- Robux-only (PremiumGunsConfig); CostCash 0, never sold for Cash
	PassKey: string?, -- MonetizationConfig.GamePasses key that unlocks it
	-- claude-bud JOB 35: WeaponAssetLoader for an asset with no Tool (a plain Model / MeshPart)
	VisualPlain: boolean?, -- true = the asset's first Model / MeshPart is the gun (an invisible Handle is added)
	VisualGrip: { X: number, Y: number, Z: number, RX: number, RY: number, RZ: number }?, -- Handle offset from the gun body (studs / deg)
	VisualLength: number?, -- the template is scaled so its longest side is this many studs (nil = as loaded)
	VisualSpin: string?, -- a child Model whose name contains this (lower case) spins while firing (the rotary barrel)
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

--[[ claude-bud JOB 33: the 7 REBIRTH GUNS (RebirthConfig.WeaponsLive; granted by PrestigeConfig.RebirthUnlocks at R1 / 3 /
	5 / 7 / 9 / 12 / 15, only while RebirthConfig.LiveFor(player, "Weapons")). Each is a current gun's frame and model
	with a modest edge (about +10-15 % damage per second, never a new class), so a rebirth is felt but the base guns
	stay competitive. Our own made-up names. CostCash 0: never sold (the Shop lists them only once owned); UnlockLevel
	1: usable at once after the rebirth (Level 1). RebirthOnly / RequiresPrestige are display fields; the grant is the
	gate. ]]
local function rebirthGun(baseId: string, id: string, name: string, short: string, prestige: number, over: { [string]: any })
	local b = WeaponConfig.Weapons[baseId]
	local d: any = table.clone(b)
	d.Id = id
	d.DisplayName = name
	d.ShortName = short
	d.Rarity = "Legendary"
	d.UnlockLevel = 1
	d.CostCash = 0
	d.RebirthOnly = true
	d.RequiresPrestige = prestige
	for k, v in pairs(over) do
		d[k] = v
	end
	-- the weapon CATALOGUE (this config), not a player's owned-weapons table (XP 4.1 / 4.2 guard the profile's)
	local catalogue: any = WeaponConfig.Weapons
	catalogue[id] = d
end
rebirthGun("AssaultRifle", "VanguardCarbine", "Vanguard Carbine", "VANGUARD", 1, { Damage = 24, FireRate = 9.5 }) -- 198 -> 228 DPS
rebirthGun("SMG", "TempestSMG", "Tempest SMG", "TEMPEST", 3, { Damage = 15, FireRate = 14.5, MagazineSize = 36 }) -- 196 -> 218
rebirthGun("Shotgun", "WardenShotgun", "Warden Shotgun", "WARDEN", 5, { Damage = 13, FireRate = 1.3, Range = 44 }) -- 86 -> 101
rebirthGun("Sniper", "LongshotDMR", "Longshot DMR", "LONGSHOT", 7, { Damage = 58, FireRate = 1.4, MagazineSize = 8, Range = 300 }) -- a semi-auto marksman: 81 DPS
rebirthGun("Sniper", "TalonSniper", "Talon Sniper", "TALON", 9, { Damage = 95, FireRate = 0.8, Range = 440 }) -- 68 -> 76
rebirthGun("RocketLauncher", "HavocLauncher", "Havoc Launcher", "HAVOC", 12, { Damage = 165, MagazineSize = 2 }) -- +10 % per rocket, 2 in the tube
rebirthGun("StarterRifle", "SovereignRifle", "Sovereign Rifle", "SOVEREIGN", 15, { Damage = 26, FireRate = 9, Range = 140 }) -- 144 -> 234: the late-rebirth all-rounder

--[[ v69: one weapon order for Shop › WEAPONS rows and the Q/E / mobile ◀ ▶ cycle:
	UnlockLevel, then CostCash, then id. ]]
--[[ claude-bud JOB 35: the 6 PREMIUM GUNS (PremiumGunsConfig; Robux passes MonetizationConfig PG_*; the models are
	owned by the place owner and load live). Our own made-up names, generic designs. CostCash 0 + Premium: never sold
	for Cash; owning the pass (or the Armory Pass) grants them. DPS vs the base guns (AR 198, SMG 196, Sniper 68,
	Rocket 60): an edge in their role, not a new tier (tools/sim/run_armory_test.py prints the table). ]]
local function premiumGun(d: { [string]: any })
	d.Rarity = "Legendary"
	d.UnlockLevel = 1
	d.CostCash = 0
	d.Premium = true
	local catalogue: any = WeaponConfig.Weapons
	catalogue[d.Id] = d
end
premiumGun({
	Id = "SovereignPistol", DisplayName = "Sovereign Gold Pistol", ShortName = "SOVEREIGN", PassKey = "PG_Sovereign",
	Damage = 30, FireRate = 2, Burst = { Count = 2, Gap = 0.1 }, MagazineSize = 12, ReloadTime = 1.6, Range = 70, Spread = 1.5,
	Visual = "Pistol", VisualAssetId = 720567240, VisualPlain = true, VisualLength = 1.7, -- one MeshPart (place owner)
	Tracer = true, Recoil = { Kick = 1.1, Side = 0.25, Recover = 10 }, Falloff = { Start = 45, MinMult = 0.7 },
})
premiumGun({
	Id = "QuakeLauncher", DisplayName = "Quake Grenade Launcher", ShortName = "QUAKE", PassKey = "PG_Quake",
	Damage = 70, FireRate = 1.2, MagazineSize = 6, ReloadTime = 3.2, Range = 120, Spread = 1,
	Visual = "Launcher", VisualAssetId = 4842201032, VisualChild = "*", -- Roblox kit Tool (its first Model child)
	Tracer = false, Recoil = { Kick = 2.0, Side = 0.3, Recover = 7 },
	Projectile = { Speed = 90, GravityFactor = 0.35, Splash = 11, SplashMinMult = 0.3, MaxSeconds = 2.2, MeshId = 232379763, TextureId = 232379808 }, -- lobbed; Roblox grenade mesh
})
premiumGun({
	Id = "LongshotSniper", DisplayName = "Longshot Sniper", ShortName = "LONGSHOT", PassKey = "PG_Longshot",
	Damage = 110, FireRate = 0.7, MagazineSize = 5, ReloadTime = 2.8, Range = 600, Spread = 0.3, HeadshotMult = 1.5, Scope = true,
	Visual = "LongRifle", VisualAssetId = 14498314181, VisualPlain = true, VisualLength = 5, -- 6 MeshParts incl. the scope
	Tracer = true, Recoil = { Kick = 3.0, Side = 0.3, Recover = 6 },
})
premiumGun({
	Id = "HavocRotary", DisplayName = "Havoc Rotary Gun", ShortName = "HAVOC", PassKey = "PG_Havoc",
	Damage = 9, FireRate = 20, SpinUp = 0.6, MagazineSize = 150, ReloadTime = 4.5, Range = 110, Spread = 3.5,
	Visual = "Carbine", VisualAssetId = 590594953, VisualPlain = true, VisualLength = 4.2, VisualSpin = "barrel", -- gun + barrel model
	Tracer = true, Recoil = { Kick = 0.3, Side = 0.35, Recover = 16 }, Falloff = { Start = 70, MinMult = 0.6 },
})
premiumGun({
	Id = "ThunderheadLauncher", DisplayName = "Thunderhead Rocket Launcher", ShortName = "THUNDER", PassKey = "PG_Thunderhead",
	Damage = 170, FireRate = 0.35, Burst = { Count = 2, Gap = 0.25 }, MagazineSize = 2, ReloadTime = 3.5, Range = 260, Spread = 0.5,
	Visual = "Launcher", VisualAssetId = 12458308179, VisualPlain = true, VisualLength = 4.5, -- launcher + rocket MeshParts
	Tracer = false, Recoil = { Kick = 3.2, Side = 0.4, Recover = 5 },
	Projectile = { Speed = 150, GravityFactor = 0, Splash = 12, SplashMinMult = 0.3, MaxSeconds = 2, MeshId = 94690081, TextureId = 94689966 }, -- a 2-rocket salvo
})
premiumGun({
	Id = "TempestRailgun", DisplayName = "Tempest Railgun", ShortName = "RAILGUN", PassKey = "PG_Tempest",
	Damage = 140, FireRate = 1, ChargeSeconds = 0.8, Pierce = 3, MagazineSize = 5, ReloadTime = 2.6, Range = 300, Spread = 0.2,
	Visual = "LongRifle", VisualAssetId = 4842190633, VisualChild = "*", -- Roblox kit Tool (its first Model child)
	Tracer = true, Recoil = { Kick = 2.4, Side = 0.2, Recover = 7 },
})

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
