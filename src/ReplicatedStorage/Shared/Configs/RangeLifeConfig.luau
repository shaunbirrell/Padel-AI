--!strict
--[[ claude-bud JOB 68: SHOOTING RANGE LIFE. The Training Yard's firing-line soldiers (TrainingYardConfig.Figures,
	YardShooter1..3: R-RIG statues of Roblox's Soldier holding the rifle forward) shoot their lane's bullseye board on a
	loop. CLIENT-SIDE COSMETIC ONLY (Client/Controllers/RangeLifeController): nothing replicates, no damage, no remote.

	  * ONE shared low-rate loop (TickHz) for every range; no per-NPC Heartbeat / RenderStepped, no tree scans (the
	    shooters come from the CollectionService "WE_Rig" tag; the active set is picked every ScanSeconds).
	  * Effects only within NearStuds of the player: at most MaxPerYard shooters per range, MaxYards ranges, MaxActive in
	    all. A shot = a muzzle flash (1 particle, no light), a short 3D shot sound, a small dust puff + a bullet hole on
	    the board (a pool of HolesPerShooter, reused). Every ShotsPerMag shots the soldier reloads: the rifle arm dips
	    ReloadDeg for ReloadSeconds (local Right Shoulder C0, restored after) with the magazine sound.
	  * OwnerFirst: live for the viewer (the owner first; OFF = today's still statues). ]]

return {
	Enabled = true,
	OwnerFirst = false, -- PUBLIC (Code Bot v220: everything public, Shaun 2026-10-02 07:51); was NEW-OWNER-FIRST (claude-bud JOB 68): goes public with the big flip after JOB 67

	NearStuds = 80, -- effects only when the player is within this of a shooter
	MaxPerYard = 4, -- the brief: at most 3-4 shooters per range (the yard has 3)
	MaxYards = 2, -- the nearest ranges only
	MaxActive = 8,
	TickHz = 4, -- the one shared loop
	ScanSeconds = 1.5, -- the active set is re-picked this often

	ShotGapMin = 1.1, -- seconds between one soldier's shots (random in [min, max]; the soldiers are staggered)
	ShotGapMax = 2.6,
	ShotsPerMag = 6, -- then a reload
	ReloadSeconds = 2.2,
	ReloadDeg = -38, -- the rifle arm dips this many degrees while reloading (0 = no dip, sound only)

	MuzzleForward = 1.7, -- studs from the rifle's centre toward the target: the flash point
	FlashSize = 1.1,
	FlashSeconds = 0.06,
	PuffCount = 4, -- dust particles per hit
	HolesPerShooter = 4, -- bullet holes on a board (pooled, reused oldest first)
	HoleSize = 0.2,
	HitSpread = 0.9, -- studs from the bull a hit may land (inside the red ring, radius 1.3)

	Sounds = { Fire = "World.RangeShot", Reload = "World.RangeReload", Hit = "World.RangeHit" }, -- SoundConfig keys (3D, short range)
	ShooterPattern = "^YardShooter(%d+)$", -- the host model name of a firing-line soldier; the number = its lane
	TargetPrefix = "TrainingTarget", -- + lane: the board it shoots (TrainingYardConfig pieces)
}
