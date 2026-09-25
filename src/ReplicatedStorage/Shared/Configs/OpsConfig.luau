--!strict
--[[
	W3 step 2 Phase B — Jobs at every place ("Ops" in code, "Jobs" to players). Shared: the server (OpsService,
	lane O) and the client (OpsController / OpsJobs, lane U) both read it. Data only: it requires nothing.

	Contract: scratchpad w3s2/buildB/KB/contract.md (lane KB). Spec: scratchpad w3s2/spec_w3s2.md §4, §5 and the
	activities design (what happens at each place; the merged spec wins where they differ).

	- Everything ships OFF: Enabled = false, every Kinds[k].Enabled = false and every site Enabled = false. A site
	  runs only when all three are on, its POI is enabled in WorldConfig.POIs, and every anchor it needs resolves
	  (ActivityAnchors.Get; Optional roles may be missing). OpsService logs a disabled site once and never falls
	  back to bare sand.
	- A site is one job place: Id = "<POI>.<Site>", the same site id the WE_ActivityAnchor attachments carry.
	  Anchors maps a role key to the full anchor id "<POI>.<Site>.<Role>" (WorldConfig.Activity, POILayouts/*,
	  the checkpoint template and Town.BankAnchors).
	- Pay, cooldowns, participation and site states are decided on the SERVER only. The client shows what the
	  OpsState / OpsProgress / OpsPing payloads (types below) carry and never sends a job request: every action is
	  a server ProximityPrompt.Triggered, re-checked by OpsService (rate limit, distance, on foot, stage, cooldown).
	- Copy is device-neutral: no key names, no "tap" / "click", never a nation or country name.
	- Coexistence until the cutover (OpsService's rules, contract §4): Town.Bank runs only while
	  BankRaidConfig.Enabled == false (never two bank jobs), and the camps only while CombatConfig.FieldBootstrap ==
	  false (never two garrisons on the same WE_NPCSpawn posts).
]]

-- ── Exported types: config rows ───────────────────────────────────────────────────────────────────────────────

-- One NPC post of a site's garrison. Post names a role key of the site's Anchors (an "npc" anchor); a rig deck post
-- has At instead (a config point: the rig deck has no anchors).
export type GarrisonPost = {
	Post: string?, -- role key in the site's Anchors ("G1", "R2", "Cmdr")
	At: { X: number, Y: number, Z: number, Yaw: number }?, -- world point of the standing surface (rig deck posts)
	Type: string, -- CombatConfig.NPCTypes key
	Stance: string, -- one of Stances: "Passive" | "Aggressive" | "Post"
	Leash: number?, -- studs from Home before the NPC walks back (nil: no leash)
	Static: boolean?, -- never MoveTo (tower decks, interiors): the model gets WE_Static = true; implies Stance "Post"
	When: string?, -- one of Spawns (nil = "Open": part of the standing garrison)
}

-- A wave NPC group (uplinks, holdout): spawned At seconds after the stage starts, on the site's wave ring
export type WaveDef = { At: number, Types: { string } }

-- One stage of a job. At / AtAny name role keys of the site's Anchors.
export type StageDef = {
	Id: string, -- one of StageIds
	At: string?, -- the anchor holding the prompt / the zone centre
	AtAny: { string }?, -- several anchors, any of them (sabotage pumps, rotating caches)
	Prompt: string?, -- key in Text.Prompts (the ActionText); nil = no prompt (a zone or a timer)
	Hold: number?, -- ProximityPrompt.HoldDuration, seconds (engine hold: works with a finger)
	Dist: number?, -- ProximityPrompt.MaxActivationDistance, studs
	Seconds: number?, -- zone progress target / alarm timer / fuse
	R: number?, -- zone radius, studs (nil: the anchor's WE_ActivityR)
	Need: number?, -- Plant: charges needed (capped by the pump anchors that exist)
	Window: number?, -- Plant: every charge within this many seconds of the first
	MaxBags: number?, -- Grab: bags per run
	Decay: number?, -- Hack: progress lost per second while the ring is empty (fraction of the whole)
	EmptyFail: number?, -- Hold: an empty ring for this long fails the job
	Damage: number?, -- Fuse: server damage at the blast (the explosion itself is visual, BlastPressure 0)
	DamageR: number?, -- Fuse: blast radius, studs
}

export type SiteDef = {
	Id: string, -- "<POI>.<Site>"
	Kind: string, -- a Kinds key
	POI: string, -- a WorldConfig.POIs Id; the site is off while that POI is disabled
	Enabled: boolean, -- ships false; the integrator flips it at the cutover
	Name: string, -- the world label title (2-3 words)
	Title: string, -- the JOBS row / card title (2-3 words)
	Short: string, -- objective marker / compass label, 2-7 capitals
	Hard: boolean, -- the JOBS row difficulty word (Text.Row.Hard / Easy)
	Big: boolean, -- rotates through the Director's big slots (the bank is Big and Pinned)
	Pinned: boolean?, -- always one of the open big sites unless Cooling
	Anchors: { [string]: string }, -- role key -> full anchor id
	Optional: { string }?, -- role keys that may be missing (a Requires row not built on Quality Low)
	Target: string, -- role key: the GO / marker point and the world label's anchor
	Label: boolean, -- one stud-scaled world label at Target (MaxDistance Ui.LabelMaxDistance, never AlwaysOnTop)
	Garrison: { GarrisonPost },
	Reserve: number, -- NPC ledger slots at Full quality (spec §4): posts + reinforcements, or the wave cap
	Waves: { WaveDef }?,
	WavePosts: { string }?, -- role keys: wave spawn fallback when no clear point is found on the wave ring
	Wake: string, -- a Npc.Wake key
	ProvokeRadius: number?, -- Passive guards: an on-foot player this close to a post for CombatConfig.NPCStance.ProvokeHoldSeconds
	Stages: { StageDef },
	Lockdown: number?, -- seconds the job may stay Active before it fails / ends
	HeldSeconds: number?, -- checkpoints: how long the taker holds it
	Pay: string, -- a Rewards.Rows key
	PresentR: number?, -- participation radius around Target (default Zones.PresentR)
	PresentSeconds: number?, -- participation time during Active (default Zones.PresentSeconds)
	PresentShare: number?, -- uplinks: share of the elapsed time inside the ring instead of PresentSeconds
	NoContest: boolean?, -- the bank: enemy players in the ring do not freeze the crack
	AllowSeated: boolean?, -- rigs: players in a boat within PresentR count as present
	Rotate: { string }?, -- caches: one of these role keys is live per cycle
	RegarrisonClear: number?, -- checkpoints: re-garrison only when no player is within this many studs
}

export type KindDef = {
	Enabled: boolean, -- ships false
	Track: { string }, -- MissionService.TrackProgress objective types reported on completion (1 each)
	Carry: boolean, -- the job ends with a carried item delivered home (OpsCargo)
	CarryLabel: string?, -- the carried item's world label ("BAG" / "BOX")
	Ping: boolean, -- carriers are revealed on OpsPing every Remote.PingSeconds
	Hostile: boolean, -- the label reads HOSTILE instead of OPEN (Aggressive garrisons)
}

export type PayRow = {
	Minutes: number, -- Pay = clamp(Floor, round(Minutes x 60 x R), Cap) x Private x Diminish x Event
	Floor: number,
	Cap: number,
	XP: number,
	PlayerCd: number, -- seconds, per player per site (saved: profile.Ops.Cd[siteId])
	SiteCd: number, -- seconds Cooling after a success (checkpoints: 0, the site's HeldSeconds is the Held time instead)
	FailCd: number, -- seconds Cooling after a failed / empty run
	DimN: number, -- full pay for the first DimN runs of this row per UTC day (then Rewards.Diminish)
}

-- ── Exported types: remote payloads (server -> client only; there is no Ops client -> server remote) ─────────
-- Timers are seconds remaining (never os.time values: client clocks drift). Money is whole dollars.

-- One site in OpsState. Full snapshots carry every live site with X/Y/Z; deltas carry changed sites without X/Y/Z.
export type OpsSiteSnap = {
	Id: string, -- a Sites Id (the client reads Name / Title / Short / Kind / Hard / Big from OpsConfig.Get(Id))
	State: string, -- one of States ("Off" = the site went away; drop it)
	X: number?, -- the Target anchor's world position (Full snapshots only)
	Y: number?,
	Z: number?,
	Left: number?, -- seconds left in Active (lockdown), Cooling or Held
	Pay: number?, -- what this player would be paid now (server-computed: R, Private, Diminish, Event)
	MyCd: number?, -- seconds until this player may do this site again (nil / 0 = now)
	Guards: number?, -- live garrison count (card copy "Clear 2 guards")
	HeldBy: number?, -- Held: the taker's UserId
}
export type OpsBagSnap = { U: number, X: number, Z: number, Age: number, Site: string } -- a DROPPED bag (U = last carrier)
export type OpsCarrySnap = { Site: string, Kind: string, Value: number, Left: number, Picked: boolean }
export type OpsStatePayload = {
	V: number, -- PayloadVersion
	Full: boolean, -- true: Sites is every live site (replace the cache); false: only the changed ones
	Sites: { OpsSiteSnap },
	Home: { X: number, Z: number }?, -- Full only: this player's delivery point (own plot, else Cargo.FallbackHome)
	Carrying: OpsCarrySnap?, -- sent in EVERY payload: nil = not carrying
	Bags: { OpsBagSnap }?, -- sent in EVERY payload: dropped bags this player may pick up (at most Cargo.MaxBagsInWorld)
}
-- 4 Hz, only while this player is inside a job zone or hold; Stage nil = hide the pill
export type OpsProgressPayload = {
	Site: string,
	Stage: string?, -- one of StageIds
	Frac: number?, -- 0..1
	Blocked: string?, -- one of Blocked
	Guards: number?, -- live garrison count
	Left: number?, -- seconds left (alarm, fuse, lockdown)
	Wave: number?, -- current wave (1-based)
	Waves: number?, -- wave count
}
-- UnreliableRemoteEvent, every Remote.PingSeconds per carrier, to non-allies only (never for a novice carrier)
export type OpsPingPayload = { U: number, X: number, Z: number }

-- ── Config ────────────────────────────────────────────────────────────────────────────────────────────────────

local OpsConfig = {
	Enabled = false, -- master switch: false = OpsService.Init returns at once (no prompt, NPC, label or payload)
	PayloadVersion = 1, -- OpsStatePayload.V

	-- Vocabularies (validated by OpsConfig.Validate; types above keep them as plain strings)
	States = { "Off", "Dormant", "Open", "Active", "Cooling", "Held", "Quiet", "Closed" },
	-- Dormant = open, no player near (no NPCs); Open = garrison up; Active = staged, lockdown running;
	-- Cooling = site cooldown (shown CLOSED); Held = a checkpoint's taker holds it; Quiet = the NPC budget is short
	-- (not listed as open); Closed = a big site the Director rotated out; Off = disabled (only ever sent to drop it)
	Stances = { "Passive", "Aggressive", "Post" },
	Spawns = { "Open", "Breach", "Alarm", "Crack" }, -- GarrisonPost.When
	StageIds = { "Breach", "Start", "Crack", "Grab", "Carry", "Alarm", "Clear", "Take", "Hack", "Hold", "Plant", "Fuse", "Recover", "Open" },
	Blocked = { "UnderFire", "Enemy", "Vehicle", "Cooldown" },
	-- MissionService objective types OpsService reports (MissionService.TrackProgress(player, type, 1))
	TrackTypes = { "Heist", "Checkpoint", "Camp", "Uplink", "Delivery", "Job" },

	Kinds = {
		Vault = { Enabled = false, Track = { "Heist", "Job" }, Carry = true, CarryLabel = "BAG", Ping = true, Hostile = false },
		VaultLite = { Enabled = false, Track = { "Delivery", "Job" }, Carry = true, CarryLabel = "BAG", Ping = true, Hostile = false },
		Checkpoint = { Enabled = false, Track = { "Checkpoint", "Job" }, Carry = false, Ping = false, Hostile = false },
		Camp = { Enabled = false, Track = { "Camp", "Job" }, Carry = false, Ping = false, Hostile = true },
		Uplink = { Enabled = false, Track = { "Uplink", "Job" }, Carry = false, Ping = false, Hostile = false },
		Holdout = { Enabled = false, Track = { "Job" }, Carry = false, Ping = false, Hostile = false },
		Sabotage = { Enabled = false, Track = { "Job" }, Carry = false, Ping = false, Hostile = false },
		Cargo = { Enabled = false, Track = { "Delivery", "Job" }, Carry = true, CarryLabel = "BOX", Ping = true, Hostile = false },
		Cache = { Enabled = false, Track = { "Job" }, Carry = false, Ping = false, Hostile = false },
		Siege = { Enabled = false, Track = { "Job" }, Carry = false, Ping = false, Hostile = true },
		Rig = { Enabled = false, Track = { "Job" }, Carry = false, Ping = false, Hostile = true },
	} :: { [string]: KindDef },

	-- NPC ledger and behaviour (spec §4). The hard cap stays in CombatService (CombatConfig.MaxActiveNPCs 18 regular,
	-- + CombatConfig.SpecialOverCap for special types / OverCap event NPCs). OpsGarrison reserves at wake.
	Npc = {
		Budget = 18, -- regular slots the ledger hands out
		EventReserve = 4, -- the +4 headroom: special types (CombatConfig.SpecialNPCTypes) and OverCap event NPCs, only when the ledger is full
		MinGarrison = 2, -- fewer free slots than this: the site is Quiet
		Wake = {
			Checkpoint = { OnFoot = 150, Any = 40 }, -- a player on foot within 150, or anyone within 40 (drive-through traffic sleeps)
			Bank = { OnFoot = 200, Any = 200 },
			Default = { OnFoot = 250, Any = 250 },
		} :: { [string]: { OnFoot: number, Any: number } },
		SleepRadius = 400, -- no player within this ...
		SleepGraceSeconds = 60, -- ... for this long (and not provoked): despawn, no pay
		SpawnStaggerSeconds = 0.2,
		TopUpClearRadius = 60, -- at Open, a missing guard respawns only when no player is within this of its post ...
		TopUpDelaySeconds = 18, -- ... and never sooner than this after it died (never faster than CombatConfig.NPCRespawnSeconds: no kill farm)
		DefaultProvokeRadius = 25, -- SpawnNPC opts.ProvokeRadius when a site sets none (hold time / calm-down:
		-- CombatConfig.NPCStance, lane N, so the NPC core keeps one copy)
		RootLift = 3, -- HumanoidRootPart above the standing surface (R6: 2-stud legs + half the torso)
		StaticMinY = 2, -- an npc anchor this far above WorldConfig.Activity.FloorY is a deck / tower post (Static)
		ProbeClear = 1, -- a Probe / wave point needs this clearance from collidable parts (studs, XZ)
		ProbeSearch = 8, -- ... searched in rings up to this far before falling back to the nearest post
		WaveRing = 70, -- uplink wave points this far from the ring centre (4 compass points)
		HoldoutWaveRing = 80,
		WaveMaxAlive = 4,
		CommanderType = "CampCommander", -- CombatConfig.NPCTypes (lane N); missing -> CommanderFallback
		CommanderFallback = "HeavyInfantry",
		LeashReturnTolerance = 4, -- the leash test: back within this of Home 20 s after losing the target
	},

	-- Presence rules for holds and participation (OpsZones)
	Zones = {
		TickSeconds = 0.25, -- 4 Hz
		MaxHeightDelta = 14, -- root Y within this of the zone centre (flat XZ test otherwise)
		TeleportStuds = 60, -- root moved further than this in one tick on foot: participation reset ...
		TeleportStudsSeated = 150, -- ... or this far while seated (600 studs/s: over 2x the fastest vehicle's server speed cap) ...
		TeleportLockoutSeconds = 15, -- ... and locked out this long (RaidConfig numbers)
		UnderFireSeconds = 2, -- hurt within this: progress freezes ("UNDER FIRE")
		PresentSeconds = 15, -- participation for pay (big sites)
		PresentSecondsSmall = 10, -- checkpoints, camps, sabotage, forts, rigs
		PresentR = 60, -- participation radius when a site sets none
		ContestFreeze = true, -- a non-ally present and no ally of the starter present: progress x0 (bank exempt)
		PromptSlack = 4, -- server re-check: root within MaxActivationDistance + this (server positions)
		RateLimitKey = "ops_prompt",
		RateLimitRate = 2,
		RateLimitBurst = 4,
	},

	-- Carried items (OpsCargo). A carried bag is part of the character; a dropped one is 1 anchored part.
	Cargo = {
		DeadlineSeconds = 240, -- carry it home within this ("Bag lost" after)
		DropLifetimeSeconds = 45, -- a dropped bag lies this long
		PickupHold = 2,
		PickupDist = 12,
		PickerMult = 0.6, -- a picker who is not the grabber gets this share (fresh deadline)
		MaxHandoffs = 3, -- the 4th drop destroys it
		MaxBagsInWorld = 3, -- carried + dropped, all sites: busiest 512-stud circle 493 static + 4 crate parts + 3 bags = 500 (cap 500)
		NoviceSeconds = 600, -- carriers younger than this (FirstJoinUnix; NoviceShieldDone once it lands) are never pinged
		DeliveryPad = 12, -- delivered inside the OWN plot square: |dx|, |dz| <= PlotSize / 2 + this
		HomeTowardGate = 150, -- OpsStatePayload.Home: plot centre moved this far toward the front gate
		FallbackHome = { X = 40, Z = 170 }, -- no plot: Pool_Town (WorldConfig.Spawns.Garage)
		FallbackRadius = 30, -- no plot: delivered within this of FallbackHome
		BagSize = Vector3.new(2, 2, 1),
		AllowVehicles = true,
	},

	-- Rewards (OpsRewards, server only). R = TycoonMath.BasePassivePerTick(profile.BaseUpgrades) / TycoonMath.TickSeconds()
	-- (base passive income per second before multipliers), never read from the client.
	Rewards = {
		CashReason = "ops", -- EconomyService.AddCash reason (wallet) ...
		XPReason = "ops", -- XPService.AddXP reason
		-- ... exempt from pass multipliers once MonetizationConfig.CashMultExemptReasons has "ops" (pending edit, KB);
		-- while it does not, OpsService stays off and logs once (never pays a multiplied job)
		RequireCashExempt = true,
		PrivateMult = 0.5, -- game.PrivateServerOwnerId ~= 0: cash and XP
		Diminish = { 1, 0.5, 0.25 }, -- runs 1..DimN, DimN+1..2 DimN, then (per pay row, per UTC day)
		EventMult = 2, -- Vault Window (Phase C, bank only)
		StudioCdDivisor = 10, -- RunService:IsStudio(): every cooldown / 10
		Rows = {
			Bank = { Minutes = 10, Floor = 15000, Cap = 300000, XP = 250, PlayerCd = 900, SiteCd = 360, FailCd = 120, DimN = 3 },
			Armory = { Minutes = 7, Floor = 10000, Cap = 200000, XP = 180, PlayerCd = 600, SiteCd = 300, FailCd = 120, DimN = 6 },
			Depot = { Minutes = 6, Floor = 8000, Cap = 160000, XP = 150, PlayerCd = 600, SiteCd = 300, FailCd = 120, DimN = 6 },
			Port = { Minutes = 5, Floor = 6000, Cap = 120000, XP = 120, PlayerCd = 480, SiteCd = 240, FailCd = 120, DimN = 6 },
			Crash = { Minutes = 4, Floor = 5000, Cap = 100000, XP = 100, PlayerCd = 480, SiteCd = 240, FailCd = 120, DimN = 6 },
			Oil = { Minutes = 5, Floor = 6000, Cap = 120000, XP = 120, PlayerCd = 480, SiteCd = 300, FailCd = 120, DimN = 6 },
			Village = { Minutes = 5, Floor = 6000, Cap = 120000, XP = 140, PlayerCd = 480, SiteCd = 240, FailCd = 120, DimN = 6 },
			Uplink = { Minutes = 4, Floor = 5000, Cap = 100000, XP = 110, PlayerCd = 480, SiteCd = 240, FailCd = 120, DimN = 6 },
			Fort = { Minutes = 4, Floor = 5000, Cap = 100000, XP = 100, PlayerCd = 600, SiteCd = 480, FailCd = 120, DimN = 6 },
			Rig = { Minutes = 4, Floor = 5000, Cap = 100000, XP = 100, PlayerCd = 600, SiteCd = 480, FailCd = 120, DimN = 6 },
			Camp = { Minutes = 3, Floor = 4000, Cap = 80000, XP = 90, PlayerCd = 360, SiteCd = 300, FailCd = 120, DimN = 6 },
			Checkpoint = { Minutes = 2, Floor = 2500, Cap = 50000, XP = 60, PlayerCd = 300, SiteCd = 0, FailCd = 120, DimN = 8 }, -- Held: the site's HeldSeconds (600)
			Cache = { Minutes = 1.5, Floor = 1000, Cap = 30000, XP = 25, PlayerCd = 600, SiteCd = 0, FailCd = 0, DimN = 6 },
			SupplyRun = { Minutes = 3, Floor = 4000, Cap = 80000, XP = 80, PlayerCd = 0, SiteCd = 0, FailCd = 0, DimN = 6 }, -- Phase C
		} :: { [string]: PayRow },
	},

	-- What is open (OpsDirector). Small sites are always open unless Cooling / Held / Quiet.
	Director = {
		BigOpenMax = 3, -- the bank (Pinned) + 2 rotating big sites
		TickSeconds = 30,
		IdleRotateSeconds = 720, -- an open big site nobody entered for this long rotates out
		DistScale = 800, -- score = sum over players of 1 / (1 + d(plot, site) / DistScale) ...
		AgeWeight = 0.5, -- ... + AgeWeight x (seconds since it was last open) / AgeUnitSeconds
		AgeUnitSeconds = 600,
		OpenToastRadius = 1400, -- "<job> is open" only to players whose plot is this close ...
		OpenToastGapSeconds = 600, -- ... at most once per this per player ...
		SkipToastIfHitSeconds = 5, -- ... and never while they are being shot at
		RobbedLineGapSeconds = 60, -- the server-wide "<name> robbed the Empire Bank" line
		FirstVisitRadius = 150, -- the one-time "Rob the bank: breach the door" tip
		Events = { Enabled = false, EverySeconds = 720 }, -- Phase C (supply runs, Vault Window): off
	},

	-- Remote traffic per player: OpsState <= 2 Hz (deltas coalesced) + a Full snapshot on join and every
	-- SnapshotSeconds; OpsProgress 4 Hz only inside a zone; OpsPing 0.1 Hz per carrier. Well under 20 Hz.
	Remote = {
		SnapshotSeconds = 60,
		DeltaMinGap = 0.5,
		ProgressHz = 4,
		PingSeconds = 10,
	},

	-- Where prompts and labels live under StreamingEnabled (residual risk: a POI's ActivityHost part can be ~380
	-- studs from its anchors, so a prompt on the anchor may not be streamed in where the player stands).
	-- 1. the host part is within NearHostStuds of the anchor: parent to the anchor Attachment;
	-- 2. else the host's parent Model holds only that one BasePart (the ActivityHost cluster): set that Model's
	--    ModelStreamingMode = Persistent once (1 invisible part per POI) and parent to the anchor Attachment;
	-- 3. else: the site is off (logged once). No part is ever added for a prompt.
	Streaming = {
		NearHostStuds = 64,
		PersistHostModel = true,
	},

	-- Client sizes, in code px ("v"). HUD UIScale ~0.70, panels ~0.65: 64 v = 44.8 real px, 20 v = 14 real px
	-- under the HUD; the JOBS rows live in the Missions panel (0.65): 72 v = 46.8 px, 22 v = 14.3 px.
	-- The objective card uses HudConfig.TopStack.Objective as it is (read, never copied or edited).
	Ui = {
		Jobs = { Rows = 3, RowH = 92, TitleSize = 24, SubSize = 22, IconSize = 48, GoW = 112, GoH = 72, HeaderSize = 22 },
		Pill = { W = 360, H = 44, TextSize = 20 },
		Card = { CloseHit = 64 },
		ArriveStuds = 30, -- the marker hides this close to the target (site label + prompt pill take over)
		MarkerTimeoutSeconds = 360,
		RefreshHz = 10, -- marker / compass
		CountdownHz = 1, -- row and card timers
		LabelMaxDistance = 40, -- site world labels: stud-scaled, never AlwaysOnTop
		LabelLift = 7, -- the site label floats this far above its Target anchor (the standing surface)
		BannerColors = { -- the bank's StateBanner (and the checkpoint sign before it is Held)
			Open = Color3.fromRGB(70, 170, 90),
			Active = Color3.fromRGB(255, 176, 48),
			Closed = Color3.fromRGB(110, 110, 110),
		},
		Smoke = { Rate = 4, SizeFrom = 6, SizeTo = 10, Lifetime = 6, RiseVelocity = 8 }, -- one emitter while Active
		PingTtlSeconds = 25, -- a carrier seen on OpsPing stays a "Steal the Bag" target this long (2.5 pings)
		ForgetStuds = 400, -- after arriving, a tracked job is dropped this far from its point
	},

	-- Profile block (lane O's ProfileSchema default + sanitise; accessed as (profile :: any).Ops, no DataVersion bump)
	Profile = {
		MaxCdKeys = 32, -- Cd = { [siteId] = os.time until }: numbers only, <= now + MaxCdAhead, expired dropped
		MaxCdAhead = 86400,
		SeenMax = 1048576, -- Seen bit flags: 0 .. 2^20
		SeenBits = { Intro = 1, BankVisit = 2, CheckpointVisit = 4, BagIntro = 8 },
	},

	-- Copy (device-neutral; prompt ActionText <= 13 characters, ObjectText = the site Name)
	Text = {
		Prompts = {
			Breach = "Breach",
			StartCrack = "Start crack",
			StartSiphon = "Start siphon",
			GrabCash = "Grab cash",
			GrabCrates = "Grab crates",
			GrabFuel = "Grab fuel",
			TakeCargo = "Take cargo",
			CutAlarm = "Cut alarm",
			TakePost = "Take post",
			OpenCache = "Open cache",
			OpenCashBox = "Open cash box",
			OpenStash = "Open stash",
			StartHack = "Start hack",
			StartHoldout = "Start holdout",
			PlantCharge = "Plant charge",
			RecoverBox = "Recover box",
			PickUpBag = "Pick up bag",
		} :: { [string]: string },
		-- World label sub-line by state (no $: pay differs per player and label text replicates to everyone)
		LabelSub = {
			Dormant = "OPEN",
			Open = "OPEN",
			Hostile = "HOSTILE", -- Open at a Hostile kind
			Active = "RAID ON",
			Cooling = "CLOSED",
			Closed = "CLOSED",
			Held = "HELD",
			Quiet = "QUIET",
		} :: { [string]: string },
		Row = {
			Header = "JOBS",
			Open = "OPEN · %s · %s", -- distance, pay ("620m", "$36K")
			Active = "RAID ON",
			Closed = "CLOSED %s", -- countdown
			Mine = "YOURS IN %s", -- this player's cooldown
			Held = "HELD",
			Easy = "Easy",
			Hard = "Hard",
			Go = "GO",
			Stop = "STOP",
			StealTitle = "Steal the Bag",
			Steal = "BAG · %s", -- the steal row's sub-line (distance)
			HomeShort = "BASE", -- marker / compass label for your own delivery point
			Empty = "No jobs open · back soon", -- the JOBS header's only line when nothing is open
		},
		Pill = {
			Breach = "BREACHING",
			Crack = "CRACKING VAULT %d%%",
			Hack = "HACKING %d%%",
			Hold = "HOLDING %d%%",
			UnderFire = "UNDER FIRE · CLEAR GUARDS",
			Enemy = "ENEMY IN RING",
			Vehicle = "LEAVE VEHICLE",
			Cooldown = "COOLDOWN %s",
			Wave = "WAVE %d OF %d",
			Alarm = "CUT THE ALARM %s",
			Take = "HOLD THE BOOTH",
		},
		Card = {
			GoTo = "Go to %s · %s", -- site Name, distance (tracked, far away)
			Breach = "Breach the front door",
			Crack = "CRACK THE VAULT",
			CrackHint = "Stay in the vault room · %d guards",
			Grab = "GRAB THE CASH",
			GrabHint = "Hold at the vault",
			Carry = "GET THE BAG HOME",
			CarryHint = "%s left · you are marked",
			Clear = "Clear %d guards",
			Alarm = "CUT THE ALARM %s",
			Take = "HOLD THE BOOTH",
		},
		Toast = {
			Intro = "Jobs are on the map · see Missions",
			Open = "%s is open", -- a job Title
			BankFirst = "Rob the bank: breach the door",
			RaidStarted = "Empire Bank raid started",
			Robbed = "%s robbed the Empire Bank", -- a player's DisplayName, never a nation
			Paid = "%s +$%s", -- job Title, amount with commas
			BagLost = "Bag lost",
			BagMoving = "Bank bag on the move",
			Sealed = "Vault sealed",
			CheckpointTaken = "Checkpoint taken +$%s",
			NeedShare = "Stay in the job to earn a share", -- grab refused: present too briefly
			JobCooldown = "Job ready in %s", -- this player's cooldown (m:ss)
			HandsFull = "Get your bag home first", -- already carrying
			BagsFull = "Too many bags out", -- Cargo.MaxBagsInWorld reached
		},
	},

	Sites = {} :: { SiteDef },
}

-- ── Sites (spec §5; anchor ids: POILayouts/*, WorldConfig.Town.Anchors / BankAnchors, Activity.CheckpointAnchors) ──
local Sites = OpsConfig.Sites

local function post(p: string, t: string, stance: string, leash: number?, when: string?, static: boolean?): GarrisonPost
	return { Post = p, Type = t, Stance = stance, Leash = leash, When = when, Static = static }
end

-- Crossroads Town: the Empire Bank (anchors stamped on BankPlaza by MapSetup, lane BK; until then the site is off)
table.insert(Sites, {
	Id = "Town.Bank",
	Kind = "Vault",
	POI = "Town",
	Enabled = false,
	Name = "Empire Bank",
	Title = "Rob the Bank",
	Short = "BANK",
	Hard = true,
	Big = true,
	Pinned = true,
	Anchors = {
		Door = "Town.Bank.Door",
		Vault = "Town.Bank.Vault",
		Loot = "Town.Bank.Loot",
		G1 = "Town.Bank.G1",
		G2 = "Town.Bank.G2",
		G3 = "Town.Bank.G3",
		G4 = "Town.Bank.G4",
		G5 = "Town.Bank.G5",
		R1 = "Town.Bank.R1",
		R2 = "Town.Bank.R2",
	},
	Target = "Door",
	Label = true,
	Garrison = {
		post("G1", "BankGuard", "Passive", 30),
		post("G2", "BankGuard", "Passive", 30),
		post("G3", "BankGuard", "Passive", 30),
		post("G4", "BankGuard", "Passive", 30),
		post("G5", "BankGuard", "Post", nil, nil, true), -- inside, by the vault door
		post("R1", "BankGuard", "Aggressive", 60, "Breach"),
		post("R2", "BankGuard", "Aggressive", 60, "Breach"),
	},
	Reserve = 7,
	Wake = "Bank",
	ProvokeRadius = 8, -- walking up to read the sign or to breach does not start a fight
	Stages = {
		-- H2 bank balance (cutover prep, headless stand-in): hold 3 -> 7 s and crack ring r 8 -> 6 took a solo raider using
		-- cover from 48 % to ~30 %; 5-unit squads ~75 %, 3-unit squads ~50-65 %, and squad success relies on squad hits not
		-- provoking the guards. H2 is NOT cleared: Jobs stay OFF (ASSUMPTIONS CP-9)
		{ Id = "Breach", At = "Door", Prompt = "Breach", Hold = 7, Dist = 10 },
		{ Id = "Crack", At = "Vault", Seconds = 45, R = 6 },
		{ Id = "Grab", At = "Loot", Prompt = "GrabCash", Hold = 2, Dist = 9, MaxBags = 4 },
		{ Id = "Carry" },
	},
	Lockdown = 240,
	Pay = "Bank",
	PresentR = 28,
	PresentSeconds = 15,
	NoContest = true,
})

-- Road checkpoints (12): the template anchors on every CheckpointBooth; rig checkpoints add G3 and have no alarm
local function checkpoint(id: string, poi: string, name: string, rig: boolean)
	local a: { [string]: string } = {
		Booth = id .. ".Booth",
		Alarm = id .. ".Alarm",
		G1 = id .. ".G1",
		G2 = id .. ".G2",
		R1 = id .. ".R1",
		R2 = id .. ".R2",
	}
	local g: { GarrisonPost } = {
		post("G1", "HeavyInfantry", "Passive", 25),
		post("G2", "Infantry", "Passive", 25),
	}
	local stages: { StageDef } = {}
	if rig then
		a.G3 = id .. ".G3"
		table.insert(g, post("G3", "Infantry", "Passive", 25))
	else
		table.insert(g, post("R1", "Infantry", "Aggressive", 60, "Alarm"))
		table.insert(g, post("R2", "Infantry", "Aggressive", 60, "Alarm"))
		table.insert(stages, { Id = "Alarm", At = "Alarm", Prompt = "CutAlarm", Hold = 2, Dist = 10, Seconds = 12 })
	end
	table.insert(stages, { Id = "Clear" })
	table.insert(stages, { Id = "Take", At = "Booth", Prompt = "TakePost", Hold = 3, Dist = 10 })
	table.insert(Sites, {
		Id = id,
		Kind = "Checkpoint",
		POI = poi,
		Enabled = false,
		Name = name,
		Title = "Take Checkpoint",
		Short = "POST",
		Hard = false,
		Big = false,
		Anchors = a,
		Target = "Booth",
		Label = true,
		Garrison = g,
		Reserve = if rig then 3 else 4,
		Wake = "Checkpoint",
		ProvokeRadius = 25,
		Stages = stages,
		HeldSeconds = 600,
		Pay = "Checkpoint",
		PresentR = 60,
		PresentSeconds = 10,
		RegarrisonClear = 100,
	})
end
checkpoint("Town.CP_N", "Town", "North Checkpoint", false)
checkpoint("Town.CP_E", "Town", "East Checkpoint", false)
checkpoint("Town.CP_S", "Town", "South Checkpoint", false)
checkpoint("Town.CP_W", "Town", "West Checkpoint", false)
checkpoint("Port.CP", "Port", "Port Checkpoint", false)
checkpoint("Depot.CP_E", "Depot", "Depot East Post", false)
checkpoint("Depot.CP_W", "Depot", "Depot West Post", false)
checkpoint("Armory.CP_W", "Armory", "Armory West Post", false)
checkpoint("Armory.CP_E", "Armory", "Armory East Post", false)
checkpoint("Signal.CP", "Signal", "Signal Checkpoint", false)
checkpoint("RigA.CP", "RigA", "Rig Alpha Post", true)
checkpoint("RigB.CP", "RigB", "Rig Bravo Post", true)

-- Caches: no NPCs, no label (the prompt pill is the cue)
table.insert(Sites, {
	Id = "Town.Market",
	Kind = "Cache",
	POI = "Town",
	Enabled = false,
	Name = "Market Cash Box",
	Title = "Cash Box",
	Short = "CACHE",
	Hard = false,
	Big = false,
	Anchors = { Box = "Town.Market.Box" },
	Target = "Box",
	Label = false,
	Garrison = {},
	Reserve = 0,
	Wake = "Default",
	Stages = { { Id = "Open", At = "Box", Prompt = "OpenCashBox", Hold = 5, Dist = 8 } },
	Pay = "Cache",
})

-- South Port: customs yard heist (breach the HeistGate, crack, grab, carry home)
table.insert(Sites, {
	Id = "Port.Customs",
	Kind = "VaultLite",
	POI = "Port",
	Enabled = false,
	Name = "Customs Yard",
	Title = "Smuggler Cargo",
	Short = "CARGO",
	Hard = false,
	Big = true,
	Anchors = {
		Gate = "Port.Customs.Gate",
		Vault = "Port.Customs.Vault",
		Loot = "Port.Customs.Loot",
		G1 = "Port.Customs.G1",
		G2 = "Port.Customs.G2",
		G3 = "Port.Customs.G3",
	},
	Target = "Gate",
	Label = true,
	Garrison = {
		post("G1", "Infantry", "Passive", 30),
		post("G2", "Infantry", "Passive", 30),
		post("G3", "Infantry", "Passive", 30),
	},
	Reserve = 3,
	Wake = "Default",
	ProvokeRadius = 12,
	Stages = {
		{ Id = "Breach", At = "Gate", Prompt = "Breach", Hold = 3, Dist = 10 },
		{ Id = "Crack", At = "Vault", Seconds = 20, R = 7 },
		{ Id = "Grab", At = "Loot", Prompt = "TakeCargo", Hold = 2, Dist = 9, MaxBags = 4 },
		{ Id = "Carry" },
	},
	Lockdown = 180,
	Pay = "Port",
	PresentR = 40,
})

-- West Depot: fuel yard heist (start the siphon, crack, grab, carry home); the truck is reserved
table.insert(Sites, {
	Id = "Depot.Fuel",
	Kind = "VaultLite",
	POI = "Depot",
	Enabled = false,
	Name = "Fuel Yard",
	Title = "Depot Heist",
	Short = "FUEL",
	Hard = false,
	Big = true,
	Anchors = {
		Pump = "Depot.Fuel.Pump",
		G1 = "Depot.Fuel.G1",
		G2 = "Depot.Fuel.G2",
		G3 = "Depot.Fuel.G3",
	},
	Optional = { "G1" }, -- the watchtower post (Requires N_Watch1: Full quality only)
	Target = "Pump",
	Label = true,
	Garrison = {
		post("G1", "Infantry", "Post", nil, nil, true),
		post("G2", "Infantry", "Passive", 30),
		post("G3", "Infantry", "Passive", 30),
	},
	Reserve = 3,
	Wake = "Default",
	ProvokeRadius = 12,
	Stages = {
		{ Id = "Start", At = "Pump", Prompt = "StartSiphon", Hold = 2, Dist = 10 },
		{ Id = "Crack", At = "Pump", Seconds = 30, R = 8 },
		{ Id = "Grab", At = "Pump", Prompt = "GrabFuel", Hold = 2, Dist = 9, MaxBags = 4 },
		{ Id = "Carry" },
	},
	Lockdown = 180,
	Pay = "Depot",
	PresentR = 40,
})

-- East Armory: hangar cache (start the crack, crack with a heavy arriving, grab, carry home); the bunker is reserved
table.insert(Sites, {
	Id = "Armory.Cache",
	Kind = "VaultLite",
	POI = "Armory",
	Enabled = false,
	Name = "Arms Cache",
	Title = "Armory Vault",
	Short = "VAULT",
	Hard = true,
	Big = true,
	Anchors = {
		Vault = "Armory.Cache.Vault",
		Loot = "Armory.Cache.Loot",
		G1 = "Armory.Cache.G1",
		G2 = "Armory.Cache.G2",
		G3 = "Armory.Cache.G3",
	},
	Target = "Vault",
	Label = true,
	Garrison = {
		post("G1", "Infantry", "Passive", 30),
		post("G2", "Infantry", "Passive", 30),
		post("G3", "HeavyInfantry", "Passive", 30),
		post("G2", "HeavyInfantry", "Aggressive", 60, "Crack"), -- the heavy that arrives at the crack
	},
	Reserve = 4,
	Wake = "Default",
	ProvokeRadius = 12,
	Stages = {
		{ Id = "Start", At = "Vault", Prompt = "StartCrack", Hold = 2, Dist = 10 },
		{ Id = "Crack", At = "Vault", Seconds = 30, R = 7 },
		{ Id = "Grab", At = "Loot", Prompt = "GrabCrates", Hold = 2, Dist = 9, MaxBags = 4 },
		{ Id = "Carry" },
	},
	Lockdown = 200,
	Pay = "Armory",
	PresentR = 40,
})

-- Oil Field: sabotage the pumps (plants needed = min(3, pumps built): 2 on Low, where Pump3 / Pump4 are not built)
table.insert(Sites, {
	Id = "OilField.Pumps",
	Kind = "Sabotage",
	POI = "OilField",
	Enabled = false,
	Name = "Oil Pumps",
	Title = "Sabotage Pumps",
	Short = "PUMPS",
	Hard = false,
	Big = true,
	Anchors = {
		Pump1 = "OilField.Pumps.Pump1",
		Pump2 = "OilField.Pumps.Pump2",
		Pump3 = "OilField.Pumps.Pump3",
		Pump4 = "OilField.Pumps.Pump4",
		G1 = "OilField.Pumps.G1",
		G2 = "OilField.Pumps.G2",
		G3 = "OilField.Pumps.G3",
	},
	Optional = { "Pump3", "Pump4" }, -- Requires PJ_3 / PJ_4 (Full quality only)
	Target = "Pump1",
	Label = true,
	Garrison = {
		post("G1", "Infantry", "Passive", 40),
		post("G2", "Infantry", "Passive", 40),
		post("G3", "HeavyInfantry", "Passive", 40),
	},
	Reserve = 3,
	Wake = "Default",
	ProvokeRadius = 20,
	Stages = {
		{ Id = "Plant", AtAny = { "Pump1", "Pump2", "Pump3", "Pump4" }, Prompt = "PlantCharge", Hold = 2, Dist = 8, Need = 3, Window = 90 },
		{ Id = "Fuse", Seconds = 10, Damage = 40, DamageR = 12 },
	},
	Lockdown = 150,
	Pay = "Oil",
	PresentR = 150,
	PresentSeconds = 10,
})

-- Uplinks: hack a console and hold the ring against waves (Airstrip, Signal: 60 s; Radar: 45 s)
local UPLINK_WAVES: { WaveDef } = {
	{ At = 5, Types = { "Infantry", "Infantry" } },
	{ At = 30, Types = { "Infantry", "HeavyInfantry" } },
}
local function uplink(id: string, poi: string, name: string, title: string, posts: { string }, seconds: number)
	local a: { [string]: string } = { Console = id .. ".Console" }
	local g: { GarrisonPost } = {}
	for _, p in ipairs(posts) do
		a[p] = id .. "." .. p
		table.insert(g, post(p, "Infantry", "Passive", 40))
	end
	table.insert(Sites, {
		Id = id,
		Kind = "Uplink",
		POI = poi,
		Enabled = false,
		Name = name,
		Title = title,
		Short = "UPLINK",
		Hard = true,
		Big = true,
		Anchors = a,
		Target = "Console",
		Label = true,
		Garrison = g,
		Reserve = 4,
		Waves = UPLINK_WAVES,
		WavePosts = posts,
		Wake = "Default",
		ProvokeRadius = 15,
		Stages = {
			{ Id = "Hack", At = "Console", Prompt = "StartHack", Hold = 2, Dist = 10, Seconds = seconds, R = 14, Decay = 0.02 },
		},
		Lockdown = seconds + 120,
		Pay = "Uplink",
		PresentR = 14,
		PresentShare = 0.5,
	})
end
uplink("Airstrip.Tower", "Airstrip", "Control Tower", "Tower Uplink", { "G1", "G2" }, 60)
uplink("Signal.Relay", "Signal", "Relay Mast", "Hack Uplink", { "G1", "G2", "G3" }, 60)
uplink("Radar.Uplink", "Radar", "Radar Console", "Radar Hack", { "G1", "G2" }, 45)

-- Ruined Village: hold the square against 3 waves; the G posts are wave fallbacks, not a standing garrison
table.insert(Sites, {
	Id = "Ruins.Holdout",
	Kind = "Holdout",
	POI = "Ruins",
	Enabled = false,
	Name = "Village Square",
	Title = "Hold the Village",
	Short = "HOLD",
	Hard = true,
	Big = true,
	Anchors = {
		Ring = "Ruins.Holdout.Ring",
		G1 = "Ruins.Holdout.G1",
		G2 = "Ruins.Holdout.G2",
		G3 = "Ruins.Holdout.G3",
	},
	Target = "Ring",
	Label = true,
	Garrison = {},
	Reserve = 4,
	Waves = {
		{ At = 0, Types = { "Infantry", "Infantry" } },
		{ At = 30, Types = { "Infantry", "Infantry", "HeavyInfantry" } },
		{ At = 60, Types = { "Infantry", "Infantry", "HeavyInfantry" } },
	},
	WavePosts = { "G1", "G2", "G3" },
	Wake = "Default",
	Stages = {
		{ Id = "Hold", At = "Ring", Prompt = "StartHoldout", Hold = 2, Dist = 10, Seconds = 90, R = 30, EmptyFail = 10 },
	},
	Lockdown = 210,
	Pay = "Village",
	PresentR = 30,
})

table.insert(Sites, {
	Id = "Ruins.Caches",
	Kind = "Cache",
	POI = "Ruins",
	Enabled = false,
	Name = "Ruins Cache",
	Title = "Hidden Cache",
	Short = "CACHE",
	Hard = false,
	Big = false,
	Anchors = {
		Cache1 = "Ruins.Caches.Cache1",
		Cache2 = "Ruins.Caches.Cache2",
		Cache3 = "Ruins.Caches.Cache3",
	},
	Target = "Cache1", -- OpsService moves the target to the live cache of the cycle
	Label = false,
	Garrison = {},
	Reserve = 0,
	Wake = "Default",
	Stages = { { Id = "Open", AtAny = { "Cache1", "Cache2", "Cache3" }, Prompt = "OpenCache", Hold = 5, Dist = 8 } },
	Pay = "Cache",
	Rotate = { "Cache1", "Cache2", "Cache3" },
})

-- Crash Site: recover the black box and carry it home
table.insert(Sites, {
	Id = "Crash.BlackBox",
	Kind = "Cargo",
	POI = "Crash",
	Enabled = false,
	Name = "Black Box",
	Title = "Black Box",
	Short = "CARGO",
	Hard = false,
	Big = true,
	Anchors = {
		Recorder = "Crash.BlackBox.Recorder",
		G1 = "Crash.BlackBox.G1",
		G2 = "Crash.BlackBox.G2",
		G3 = "Crash.BlackBox.G3",
	},
	Target = "Recorder",
	Label = true,
	Garrison = {
		post("G1", "Infantry", "Aggressive", 40),
		post("G2", "Infantry", "Aggressive", 40),
		post("G3", "Infantry", "Aggressive", 40),
	},
	Reserve = 3,
	Wake = "Default",
	Stages = {
		{ Id = "Recover", At = "Recorder", Prompt = "RecoverBox", Hold = 3, Dist = 8 },
		{ Id = "Carry" },
	},
	Lockdown = 180,
	Pay = "Crash",
	PresentR = 60,
})

-- Oasis: the smuggler stash (the well is reserved)
table.insert(Sites, {
	Id = "Oasis.Stash",
	Kind = "Cache",
	POI = "Oasis",
	Enabled = false,
	Name = "Oasis Stash",
	Title = "Smuggler Stash",
	Short = "CACHE",
	Hard = false,
	Big = false,
	Anchors = { Box = "Oasis.Stash.Box" },
	Target = "Box",
	Label = false,
	Garrison = {},
	Reserve = 0,
	Wake = "Default",
	Stages = { { Id = "Open", At = "Box", Prompt = "OpenStash", Hold = 5, Dist = 8 } },
	Pay = "Cache",
})

-- Camps: clear the garrison and the commander, then open the chest. Post types follow today's field NPC mix
-- (CombatService.BootstrapNPCs deals Infantry, Infantry, HeavyInfantry over the WE_NPCSpawn anchors in order).
local function camp(id: string, poi: string, name: string, types: { string }, towerPost: string, reserve: number)
	local a: { [string]: string } = { Chest = id .. ".Chest", Cmdr = id .. ".Cmdr" }
	local g: { GarrisonPost } = {}
	for i, t in ipairs(types) do
		local p = "G" .. tostring(i)
		a[p] = id .. "." .. p
		table.insert(g, post(p, t, "Aggressive", 80))
	end
	a[towerPost] = id .. "." .. towerPost
	table.insert(g, post(towerPost, "Infantry", "Post", nil, nil, true))
	table.insert(g, post("Cmdr", "CampCommander", "Aggressive", 80))
	table.insert(Sites, {
		Id = id,
		Kind = "Camp",
		POI = poi,
		Enabled = false,
		Name = name,
		Title = "Raid Camp",
		Short = "CAMP",
		Hard = true,
		Big = false,
		Anchors = a,
		Optional = { towerPost }, -- the watchtower post (Requires Watch: Full quality only)
		Target = "Chest",
		Label = true,
		Garrison = g,
		Reserve = reserve,
		Wake = "Default",
		Stages = {
			{ Id = "Clear" },
			{ Id = "Open", At = "Chest", Prompt = "OpenCache", Hold = 2, Dist = 8 },
		},
		Pay = "Camp",
		PresentR = 120,
		PresentSeconds = 10,
	})
end
camp("Quarry.Camp", "Quarry", "Quarry Camp", { "Infantry", "Infantry", "HeavyInfantry", "Infantry" }, "G5", 6)
camp("RidgeCamp.Camp", "RidgeCamp", "Ridge Camp", { "Infantry", "HeavyInfantry", "Infantry" }, "G4", 5)
camp("DuneCamp.Camp", "DuneCamp", "Dune Camp", { "Infantry", "HeavyInfantry", "Infantry" }, "G4", 5)

-- Forts: plant a charge at the gate anchor (no gate part: the charge is the objective), clear the fort guards
local function fort(id: string, poi: string, name: string)
	local a: { [string]: string } = { Gate = id .. ".Gate" }
	local g: { GarrisonPost } = {}
	for i = 1, 4 do
		local p = "G" .. tostring(i)
		a[p] = id .. "." .. p
		table.insert(g, post(p, "FortGuard", "Aggressive", 60))
	end
	table.insert(Sites, {
		Id = id,
		Kind = "Siege",
		POI = poi,
		Enabled = false,
		Name = name,
		Title = "Breach the Fort",
		Short = "FORT",
		Hard = true,
		Big = false,
		Anchors = a,
		Target = "Gate",
		Label = true,
		Garrison = g,
		Reserve = 4,
		Wake = "Default",
		Stages = {
			{ Id = "Plant", At = "Gate", Prompt = "PlantCharge", Hold = 3, Dist = 10, Need = 1 },
			{ Id = "Fuse", Seconds = 8, Damage = 40, DamageR = 12 },
			{ Id = "Clear" },
		},
		Lockdown = 480, -- the gate stays blown this long
		Pay = "Fort",
		PresentR = 80,
		PresentSeconds = 10,
	})
end
fort("FortI.Breach", "FortI", "Ironclad Gate")
fort("FortS.Breach", "FortS", "Sandhold Gate")

-- Rigs: clear the deck guards (config posts on a ring of radius DeckR round the TerritoryConfig deck position;
-- the capture itself stays TerritoryService's). The Pier anchor is the GO point on the shore.
local DECK_R = 20
local DECK_ANGLES = { 0, 120, 240 } -- degrees, 0 = north (-Z)
local DECK_TOP = 28.05 -- MapSetup deck: 2.5 thick centred at Position.Y - 1.2
local function rig(id: string, poi: string, name: string, cx: number, cz: number)
	local g: { GarrisonPost } = {}
	for _, deg in ipairs(DECK_ANGLES) do
		local r = math.rad(deg)
		table.insert(g, {
			At = { X = cx - DECK_R * math.sin(r), Y = DECK_TOP, Z = cz - DECK_R * math.cos(r), Yaw = deg + 180 },
			Type = "OilRigGuard",
			Stance = "Aggressive",
			Leash = 25, -- never walks off the 48-stud deck
		})
	end
	table.insert(Sites, {
		Id = id,
		Kind = "Rig",
		POI = poi,
		Enabled = false,
		Name = name,
		Title = "Storm the Rig",
		Short = "RIG",
		Hard = true,
		Big = false,
		Anchors = { Pier = id .. ".Pier" },
		Target = "Pier",
		Label = false, -- the capture zone's own label covers the deck
		Garrison = g,
		Reserve = 3,
		Wake = "Default",
		Stages = { { Id = "Clear" } },
		Pay = "Rig",
		PresentR = 80,
		PresentSeconds = 10,
		AllowSeated = true,
	})
end
-- deck centres = TerritoryConfig.Territories.CoastalOilAlpha / CoastalOilBravo .Position (X, Z)
rig("RigA.Deck", "RigA", "Rig Alpha Deck", 1800, -750)
rig("RigB.Deck", "RigB", "Rig Bravo Deck", -1800, 750)

-- ── Lookups (pure; built once at require) ─────────────────────────────────────────────────────────────────────
local byId: { [string]: SiteDef } = {}
for _, s in ipairs(Sites) do
	byId[s.Id] = s
end

function OpsConfig.Get(id: string): SiteDef?
	return byId[id]
end

-- True when the master switch, the kind and the site are all on (POI / anchor liveness is OpsService's check)
function OpsConfig.SiteSwitchedOn(id: string): boolean
	local s = byId[id]
	if s == nil or OpsConfig.Enabled ~= true or s.Enabled ~= true then
		return false
	end
	local k = OpsConfig.Kinds[s.Kind]
	return k ~= nil and k.Enabled == true
end

local function inList(list: { string }, v: string): boolean
	for _, x in ipairs(list) do
		if x == v then
			return true
		end
	end
	return false
end

-- Static checks of the rows above (no world access). Returns a list of problems; empty = valid.
function OpsConfig.Validate(): { string }
	local bad: { string } = {}
	local function fail(msg: string)
		table.insert(bad, msg)
	end
	local seen: { [string]: boolean } = {}
	for _, s in ipairs(Sites) do
		local id = s.Id
		if seen[id] then
			fail(id .. ": duplicate site id")
		end
		seen[id] = true
		local poi, site = string.match(id, "^([%w_]+)%.([%w_]+)$")
		if poi == nil or site == nil then
			fail(id .. ": site id is not <POI>.<Site>")
		elseif poi ~= s.POI then
			fail(id .. ": POI " .. s.POI .. " does not match the id")
		end
		if OpsConfig.Kinds[s.Kind] == nil then
			fail(id .. ": unknown kind " .. s.Kind)
		end
		if OpsConfig.Rewards.Rows[s.Pay] == nil then
			fail(id .. ": unknown pay row " .. s.Pay)
		end
		if OpsConfig.Npc.Wake[s.Wake] == nil then
			fail(id .. ": unknown wake " .. s.Wake)
		end
		if not string.match(s.Short, "^[A-Z]+$") or #s.Short < 2 or #s.Short > 7 then
			fail(id .. ": Short must be 2-7 capitals")
		end
		for role, aid in pairs(s.Anchors) do
			if aid ~= id .. "." .. role then
				fail(id .. ": anchor " .. role .. " = " .. aid .. " is not <site>.<role>")
			end
		end
		if s.Anchors[s.Target] == nil then
			fail(id .. ": Target " .. s.Target .. " is not an anchor role")
		end
		for _, r in ipairs(s.Optional or {}) do
			if s.Anchors[r] == nil then
				fail(id .. ": Optional " .. r .. " is not an anchor role")
			end
		end
		for _, g in ipairs(s.Garrison) do
			if g.Post ~= nil and s.Anchors[g.Post] == nil then
				fail(id .. ": garrison post " .. g.Post .. " is not an anchor role")
			end
			if g.Post == nil and g.At == nil then
				fail(id .. ": garrison post with neither Post nor At")
			end
			if not inList(OpsConfig.Stances, g.Stance) then
				fail(id .. ": unknown stance " .. g.Stance)
			end
			if g.When ~= nil and not inList(OpsConfig.Spawns, g.When) then
				fail(id .. ": unknown When " .. g.When)
			end
		end
		for _, p in ipairs(s.WavePosts or {}) do
			if s.Anchors[p] == nil then
				fail(id .. ": wave post " .. p .. " is not an anchor role")
			end
		end
		for _, r in ipairs(s.Rotate or {}) do
			if s.Anchors[r] == nil then
				fail(id .. ": rotate " .. r .. " is not an anchor role")
			end
		end
		if #s.Stages == 0 then
			fail(id .. ": no stages")
		end
		for _, st in ipairs(s.Stages) do
			if not inList(OpsConfig.StageIds, st.Id) then
				fail(id .. ": unknown stage " .. st.Id)
			end
			if st.At ~= nil and s.Anchors[st.At] == nil then
				fail(id .. ": stage " .. st.Id .. " At " .. st.At .. " is not an anchor role")
			end
			for _, r in ipairs(st.AtAny or {}) do
				if s.Anchors[r] == nil then
					fail(id .. ": stage " .. st.Id .. " AtAny " .. r .. " is not an anchor role")
				end
			end
			if st.Prompt ~= nil then
				local txt = OpsConfig.Text.Prompts[st.Prompt]
				if txt == nil then
					fail(id .. ": stage " .. st.Id .. " prompt " .. st.Prompt .. " has no text")
				elseif #txt > 13 then
					fail(id .. ": prompt text " .. txt .. " is over 13 characters")
				end
				if st.At == nil and st.AtAny == nil then
					fail(id .. ": stage " .. st.Id .. " has a prompt but no anchor")
				end
			end
		end
	end
	return bad
end

return OpsConfig
