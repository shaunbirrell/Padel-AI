--!strict
--[[
	Empire Bank raid — high-value contested vault with NPC guards + per-player cooldown (saved on the profile).

	W3 step 2, lane F ("bank findable", spec w3s2 §6 Phase A):
	- Guards stand on FIXED posts, never a ring round the vault (the ring put 2 of 5 inside the building).
	  BankRaidService reads the geometry's "Town.Bank" npc anchors (roles G1..Gn, WE_ActivityAnchor; MapSetup stamps
	  them on BankPlaza with the walk-in hall, lane BK) and falls back to GuardPosts below if they are missing.
	- Only a raider ON FOOT holds the vault (seated → "LEAVE VEHICLE" on the HUD, no progress, no pay).
	- The cooldown is saved as profile.Raid.BankCooldownUntil (os.time seconds; sanitised by BankRaidService).
	- The vault label reads "Empire Bank" + one state line: OPEN · rob the vault / RAID ON (everyone) and
	  CLOSED 4m (only the player who is on cooldown; drawn by BankRaidController on that client).
]]

export type GuardPost = {
	X: number,
	Y: number, -- world Y of the standing surface (the plaza top is 1.6, the ground 0.5)
	Z: number,
	Yaw: number?, -- degrees, 0 faces north (-Z), 180 faces south (+Z, down Bank Street)
}

local BankRaidConfig = {
	Enabled = true,
	BankId = "EmpireBank",
	DisplayName = "Empire Bank",
	Position = Vector3.new(220, 1, -220),
	VaultRadius = 12,
	RaidHoldSeconds = 6, -- v71: 8 → 6 (task #20 bank retune; guard stats in CombatConfig.NPCTypes.BankGuard)
	CooldownSeconds = 300, -- 5 min per player after a successful raid (saved: profile.Raid.BankCooldownUntil)
	CashMin = 15000,
	CashMax = 35000,
	GuardNPCType = "BankGuard",
	GuardCount = 5, -- at most this many fallback posts are used (the anchor posts are all used)
	-- The bank zone radius round Position: the WorldDress keep-out (WorldDress: this + BankExtra) and the novice
	-- shield's "engaging the bank" test (CombatService). Guards no longer spawn on a ring.
	GuardRingRadius = 18,
	-- Anchor site / role pattern read by BankRaidService (spec w3s2 §5: Town.Bank.G1..G5 on BankPlaza)
	AnchorSite = "Town.Bank",
	GuardRolePattern = "^G%d+$",
	-- HumanoidRootPart height above the standing surface (R6: 2-stud legs + half the 2-stud torso)
	GuardRootLift = 3,
	-- Fallback posts (lane BK): the same five posts as the Town.Bank G1..G5 anchors MapSetup stamps on BankPlaza (G1 / G2
	-- behind the planters, G3 / G4 beside the columns, G5 inside the hall by the vault door). Used only while no
	-- "Town.Bank" G anchors exist.
	GuardPosts = {
		{ X = 206, Y = 1.6, Z = -209.5, Yaw = 180 },
		{ X = 234, Y = 1.6, Z = -209.5, Yaw = 180 },
		{ X = 210.5, Y = 1.6, Z = -210.5, Yaw = 180 },
		{ X = 229.5, Y = 1.6, Z = -210.5, Yaw = 180 },
		{ X = 227, Y = 1.6, Z = -231, Yaw = 180 },
	} :: { GuardPost },
	NotifyOnRaid = true,
	-- v71: the hold freezes only while the raider was hit within this many seconds (was: any health below 95 %)
	UnderFireSeconds = 2,
	-- One-time tip the first time a player comes this close to Position (saved: profile.Raid.BankSeen)
	FirstVisitRadius = 150,
	FirstVisitSkipIfHitSeconds = 5, -- not while the player is being shot at; retried on a later tick
	-- The painted EMPIRE BANK sign on the bank's "BankSign" part (WorldKits.Sign, inside the world sign budget);
	-- painted only when that part has no SurfaceGui yet, on the face turned most toward SignFacing (the street side)
	Sign = {
		PartName = "BankSign",
		Text = "EMPIRE BANK",
		Facing = Vector3.new(0, 0, 1),
	},
	-- Copy seen by every device (no key names, no "tap" / "click")
	Text = {
		FirstVisit = "Empire Bank: stand on the vault to loot",
		Reward = "Bank job +$%s", -- %s = cash with commas
	},
	-- vault label (Shared/Util/WorldLabel): stud-scaled, never AlwaysOnTop, MaxDistance <= 40 (spec §5)
	Label = {
		Name = "WE_BankRaidStatus",
		StateAttribute = "WE_BankState", -- "open" | "raid" (the public state; the client reads it back)
		Title = "Empire Bank",
		OpenSub = "OPEN · rob the vault",
		OpenColor = Color3.fromRGB(120, 230, 130),
		RaidingSub = "RAID ON",
		RaidingColor = Color3.fromRGB(255, 176, 48),
		ClosedSub = "CLOSED %dm", -- %d = whole minutes left, rounded up (this player's own cooldown)
		ClosedColor = Color3.fromRGB(190, 190, 190),
		Color = Color3.fromRGB(255, 220, 120),
		HeightStuds = 8, -- above the vault pad centre (clear of a standing raider's head)
		MaxDistance = 40,
	},
}

return BankRaidConfig
