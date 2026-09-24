--!strict
--[[ W2 Combat Core (contracts §2.4): server-side combat feel numbers.

	HeadshotMult   exact server ray on a part named "Head" (players, NPCs); never claim / assist / splash.
	Fx             WeaponFx fan-out (UnreliableRemoteEvent): recipients within RadiusStuds of the shot's origin or
	               end point; per-shooter bucket for bullets (PerShooterHz / Burst), per-recipient bucket for
	               everything. Over a cap the event is dropped, never queued.
	Projectile     server kinematic stepper for WeaponConfig weapons with a Projectile def (RocketLauncher, Grenade).
	Splash         CombatService.ApplyRadiusDamage defaults (line of sight from the blast point to each torso).
	Drawn          RequestSetDrawn remote rate limit and the character attribute it writes.
	ShieldAttribute / DamageNumbersAttribute   replicated attributes (client bubble, damage numbers).
	BlastSourceSeconds  nuke §15.2: a death within this of a blast hit is a "blast death" (quiet kill).
	AimStatsLogSeconds  one aim-resolution summary log line per this many seconds (when the counts changed). ]]

local CombatFeelConfig = {
	HeadshotMult = 1.5, -- exact server ray on a part named "Head" (players, NPCs); never claim / assist / splash
	Fx = {
		Remote = "WeaponFx",
		RadiusStuds = 250,
		PerShooterHz = 20,
		PerShooterBurst = 4,
		PerRecipientHz = 60,
		PerRecipientBurst = 20,
		NpcShots = true,
		NpcMissOffset = { Min = 2, Max = 4 },
	},
	Projectile = { StepHz = 20, MaxLivePerPlayer = 3, MaxLiveServer = 24, SpawnForwardStuds = 1 },
	Splash = {
		RequireLos = true,
		LosLiftStuds = 1,
		DefaultMinMult = 0.25,
		ExcludeClanAllies = true, -- W2 CC-1 addition: an attacker's splash never hurts clan mates (assumption A-CC1-3)
	},
	Drawn = { RemoteRate = 2, RemoteBurst = 4, Attribute = "WE_GunOut" },
	ShieldAttribute = "WE_ShieldUntil", -- character attr: Workspace:GetServerTimeNow() + spawn-invulnerable seconds
	DamageNumbersAttribute = "WE_ShowDamageNumbers", -- player attr from profile.Settings.ShowDamageNumbers (nil = on)
	BlastSourceSeconds = 3, -- nuke §15.2: a death within this of a blast hit is a "blast death"
	AimStatsLogSeconds = 300,
}

return CombatFeelConfig
