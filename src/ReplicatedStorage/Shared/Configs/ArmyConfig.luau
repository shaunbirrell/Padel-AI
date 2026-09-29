--!strict
--[[
	ArmyConfig — the field army (SquadOrdersService units). SPEC-ARMY-FINAL §10.1. Config-first; server and client read it.

	████ army lane A0 blocks: Rollout · Escort · ShotFx · Text (+ the LiveFor / IsLive helper) ████
	████ army fix blocks (the despawn fix): Follow · Recover · Gate · Loop (+ the ThreatStandingFor helper) ████
	Other army lanes add their own self-contained blocks to this same table (lane A: Home / Guard / Hold / Path / Ui;
	lane C: March). Keep each block self-contained; this file requires only AdminConfig.

	ROLLOUT (owner 2026-09-28, integrator decision): each part is "off" | "owner" | "all".
	  "off"   = today's game (e506c9c) for everyone;
	  "owner" = only the owner's playtest account (AdminConfig.IsPlaytestOwner, UserId 470626172, the same gate as
	            AircraftWeaponConfig.LiveFor); everyone else keeps today's game;
	  "all"   = everyone.
	  Any other value counts as "off" (fail closed). The SERVER decides (ArmyConfig.LiveFor); nothing is read from a client.
	  Parts: Escort (lane A0: the bank fix, defend-when-targeted, focus fire, side-step, visible unit shots), Army (lane A:
	  guard line, follow outside, paths), March (lane C: ATTACK takes checkpoints).

	ESCORT (FOLLOW, lane A0, "I went to the bank and they didn't shoot"): for a live owner the escort's first targets are
	  the NPCs aiming at him within DefendRadius of him (CombatService.NPCsAimingAt / NPCThreat) and the NPCs he hit
	  himself in the last FocusFireSeconds within DefendRadius (focus fire; CombatService stamps the player's own hits);
	  then today's escort targets (CombatFairnessConfig.EscortEngageRadius 55 of him). While such a target exists the
	  escort leash is DefendLeash (today CombatFairnessConfig.EscortLeash 20), so units step out for a sight line. Every
	  shot keeps squadfair's rules: line of sight, the unit hit curve, unitMayHit, no kill pay on ATTACK.
	  Side-step: after SideStepAfterBlocked shot checks in a row with the target in range but out of sight, a unit
	  probes SideStepStuds to each side (at most 4 rays per probe, at most one probe per SideStepMinGap s, only while
	  blocked) and walks to the first spot that sees the target and stays inside its leash, for at most SideStepHoldSeconds.
	  NpcSnapshot is NOT a Rollout part: every army's hostile scan reads one CombatService NPC list per think pass
	  (CombatService.LiveNPCSnapshot) instead of a CollectionService:GetTagged("WE_NPC") per unit; the picks are the same
	  (a2 differential runs). false = the per-unit GetTagged scan of e506c9c.

	SHOTFX (lane A0): a unit shot (hit or miss, every order) of a live owner's army may send one WeaponFx bullet
	  (UnreliableRemoteEvent, CombatFx) with the NPC rifle look (S = 0, W = "NPC": the rig's aim pose plays too).
	  Sampled to one event per army per PerArmyMinGap s, then a per-army shooter bucket, then an army bucket of
	  PerRecipientHz (burst PerRecipientBurst) per recipient, on top of CombatFx's own recipient bucket. A missed shot's
	  tracer lands MissOffsetStuds beside the target (no random numbers: the hit roll sequence is untouched).

	TEXT: device-neutral army strings (no key names, no "click" / "tap"); lanes A and C show them.

	DESPAWN FIX (army fix; v90: Rollout.Fix, owner first):
	  • Follow  — keeping up in FOLLOW: aim at where the owner will be (Lead), walk at his pace (smoothed and stepped:
	    PaceSmooth / PaceStep / PaceJumpStuds) and run only when well behind (CatchUp), follow as at e506c9c near a
	    hostile (ThreatStuds / ThreatStandingFor); while he walks, escort units keep the formation and shoot from it
	    (EscortWalkInFormation / EscortWalkLeash).
	  • Recover — RECOVER (SPEC-ARMY-FINAL §6.5): a unit is NEVER deleted for distance, a failed walk or a wall. One that
	    is far behind, stuck, fallen or deep in another player's plot is moved (Model:PivotTo, the same unit and id) to
	    a clear spot behind its owner. The only ways a unit is removed stay the lifecycle ones: its Humanoid died, the
	    army shrank (dismiss / research), the owner left, OrdersConfig.Enabled = false.
	  • Loop    — one army's error never stops the think loop of every army (pcall + a rate-limited log line).
	  • Gate    — the owner's friendly gate barrier also opens for his own units while they FOLLOW him through it
	    (GateDefenseService.updateFriendlyGate), only while they are still on the far side of it (CrossingRule,
	    CrossClearStuds 0); never for units on his side, never for Hold / Attack / Retreat, never with him dead or away.

	v90 (Code Bot): THE DESPAWN FIX ships behind Rollout.Fix ("owner" first; everyone else keeps v85 FollowPace /
	4d26673 until it is "all"; for a Fix-live owner it replaces v85 FollowPace). Within it each block has its own kill switch (Enabled / OwnUnitsOpen /
	KeepTrailPoint / EscortWalkInFormation / CrossingRule; ThreatStuds = 0 turns the near-hostile pacing off); with all
	of them off SquadOrdersService / GateDefenseService behave as at 4d26673 (units walk at OrdersConfig.UnitWalkSpeed,
	straight to the unled slot, never moved). Numbers are measured on the headless stand-in (army/build/fix and army/build/fix_ship
	reports); Humanoid physics needs a real device.
]]

local AdminConfig = require(script.Parent.AdminConfig)

local ArmyConfig = {
	-- ── Rollout (lane A0 builds the gate; lanes A / C read it) ─────────────────────────────────────────────────────
	Rollout = {
		Escort = "owner", -- lane A0: bank fix / defend / focus fire / side-step / visible unit shots
		Army = "owner", -- lane A: guard line, follow outside, movement
		March = "owner", -- lane C: ATTACK takes checkpoints
		Fix = "owner", -- v90 (Code Bot): the army despawn fix (Follow / Recover / Gate blocks); "all" once the owner has phone-tested it
	},

	-- ── Escort (FOLLOW; SPEC-ARMY-FINAL §7.1 / §7.2) ──────────────────────────────────────────────────────────────
	Escort = {
		DefendRadius = 90, -- studs from the owner: NPCs aiming at him / hit by him this close are escort targets first
		DefendLeash = 28, -- escort leash (studs from the owner) while such a target exists (else EscortLeash 20)
		FocusFireSeconds = 6, -- an NPC the owner hit himself within this many seconds is a focus-fire target
		SideStep = true,
		SideStepAfterBlocked = 2, -- shot checks in a row with the target in range but out of sight
		SideStepStuds = { 4, 8 }, -- lateral probe distances (one ring per probe, alternating)
		SideStepMinGap = 1.5, -- seconds between two probes of one unit (<= 4 rays per probe)
		SideStepHoldSeconds = 3, -- a side-step walk ends after this (reached, a shot, or given up)
		NpcSnapshot = true, -- every army (not a Rollout part): one NPC list per think pass, no GetTagged per unit
	},

	-- ── ShotFx (every order; SPEC-ARMY-FINAL §7.1 "Visible shots") ────────────────────────────────────────────────
	ShotFx = {
		Enabled = true,
		PerArmyMinGap = 0.25, -- at most one WeaponFx event per army per this many seconds
		PerRecipientHz = 6, -- army bucket per recipient (events / s), on top of CombatFeelConfig.Fx.PerRecipientHz
		PerRecipientBurst = 2, -- 2 per think pass (armies fire together at 2.5 Hz): <= 6 in any 1 s, 5 / s steady
		MissOffsetStuds = 3, -- a miss tracer lands this far beside the target (alternating sides)
	},

	-- ── FollowPace (v85 hotfix, owner phone v84: "The army still cut off when walking"; Rollout.Army) ────────────────
	-- Root cause: FOLLOW units walked at OrdersConfig.UnitWalkSpeed 14 while the owner walks at 16 (18.4 Speed Pass,
	-- 20 Speed Boost), so every second of walking left them 2-6 studs further behind; their MoveTo goal was the slot
	-- where the player stood up to one think (0.4 s) ago; a unit that reached that stale slot stopped (MoveTo to
	-- itself) until the next think; and an escort with any hostile in range stood still to shoot while he walked on
	-- until it was EscortLeash (20) behind. The client escort figures stand 7-12 studs AHEAD of their unit, so a unit
	-- that fell behind put its figures inside the camera guard's corridor and they vanished.
	-- For a live owner (Rollout.Army) while he is on foot:
	--   * speed: WalkSpeed = max(UnitWalkSpeed, owner WalkSpeed x MatchMult); x CatchUpMult once the unit is more than
	--     CatchUpStartStuds from its (led) slot, x SprintMult beyond SprintStartStuds; never above MaxSpeed;
	--   * lead: the slot is taken from where the owner will be LeadSeconds ahead (his flat velocity), so the goal is
	--     never behind him, and a unit in its slot keeps walking while he walks (no stop-start);
	--   * moving escort: while he moves faster than MovingStuds/s the escort shoots on the move from its slot instead of
	--     standing (it still stops to fight when he stops);
	--   * last resort: a unit more than TeleportStuds from him and out of his sight line (or more than
	--     TeleportHardStuds, seen or not) is put back in its slot beside him (the recruit spawn rules: never inside a
	--     wall), at most once per TeleportCooldown s per unit. Never while he is seated (vehicles keep today's rules).
	FollowPace = {
		Enabled = true,
		MatchMult = 1.1, -- in-slot speed = owner WalkSpeed x this (a little faster so the wings keep their place)
		CatchUpStartStuds = 6,
		CatchUpMult = 1.4,
		SprintStartStuds = 20,
		SprintMult = 1.8,
		MaxSpeed = 40,
		LeadSeconds = 0.5,
		MaxLeadStuds = 12,
		MovingStuds = 3, -- owner flat speed (studs/s) that counts as walking
		TeleportStuds = 70,
		TeleportHardStuds = 140,
		TeleportCooldown = 4,
	},

	-- ── Text (device-neutral; no key names, no "click" / "tap") ──────────────────────────────────────────────────
	Text = {
		Status = {
			Guard = "GUARDING BASE",
			Follow = "FOLLOWING",
			Hold = "HOLDING",
			HoldPost = "HOLDING POST",
			March = "TO %s",
			Fight = "FIGHTING",
			Capture = "TAKING POST",
			Wait = "WAITING FOR YOU",
			Return = "RETURNING",
			HoldLine = "AT THE CENTRE",
			Clear = "FIGHTING",
		},
		Tile = { Guard = "GUARD", Follow = "FOLLOW", Attack = "ATTACK", Hold = "HOLD", Return = "RETURN" },
		MovingOut = "Army moving out",
		Waiting = "Army waiting for you",
		TakeCentre = "Take the Centre!",
		Taken = "%s taken",
		UnderAttack = "%s under attack",
		NoBase = "No base to guard",
	},

	-- ════ army fix (the despawn fix) blocks: Follow · Recover · Gate · Loop ════
	Follow = {
		-- MoveTo goals are refreshed once per think (OrdersConfig.ThinkInterval 0.4 s) and a Humanoid stops at its goal,
		-- so a follow unit aims at its slot around where the owner WILL be: his flat velocity over the last think x
		-- Seconds, at most MaxStuds. A faster jump (teleport, respawn, fast vehicle) gives no lead, and neither does a
		-- think at under DropOnSlowdown x the one before (he is stopping). When he has stopped, a unit whose goal lies
		-- just behind it (within MaxStuds + StopHoldStuds, along his facing) stands facing his way instead of turning
		-- back toward the camera. MaxStuds 4: a unit in its slot walks smoothly at his pace (measured: stopped in about
		-- 1 % of walking ticks; 12 made them stop and start 5 times a second).
		Lead = {
			Enabled = true,
			Seconds = 0.4, -- = OrdersConfig.ThinkInterval
			MaxStuds = 4,
			MaxOwnerSpeed = 40, -- studs/s; faster owner moves are jumps (no lead)
			DropOnSlowdown = 0.5,
			StopHoldStuds = 2,
			StopHoldSeconds = 1.5, -- ...only right after he stopped (a unit walking back later still does)
		},
		-- A follow unit walks at its owner's pace (never below OrdersConfig.UnitWalkSpeed, so it falls back to
		-- UnitWalkSpeed once he stands still). More than StartStuds behind (its goal further than StartStuds + the lead
		-- distance) with a walkable line to it, it runs SpeedMult x that pace, at most MaxSpeed: owner 16 / 18.4 / 20
		-- (research) -> 24 / 27.6 / 28. A unit whose line to its goal is blocked never runs (no sprinting into a wall).
		-- The spec's 18 studs/s cannot keep up with an owner at 18.4 or 20.
		CatchUp = {
			Enabled = true,
			StartStuds = 6,
			SpeedMult = 1.5,
			MaxSpeed = 28,
			-- ship: the pace comes from his speed smoothed over passes (weight PaceSmooth per 0.4 s pass) and moves only in
			-- PaceStep studs/s steps: every Humanoid.WalkSpeed write replicates to every client, and a client-owned
			-- character's replicated position jitters (stand-in, +-0.4 studs per step: 20 writes/s per army at step 0).
			PaceSmooth = 0.4,
			PaceStep = 1,
			PaceJumpStuds = 3, -- ...a change bigger than this passes at once (a start / stop / sprint: no lag, no catch-up run)
		},
		-- While a hostile the escort would pick (not a calm one, one this army may hit) is within ThreatStuds of the
		-- owner, FOLLOW units follow as at e506c9c (no lead, UnitWalkSpeed) so a fight starts from the e506c9c formation.
		-- ThreatStuds 55 = CombatFairnessConfig.EscortEngageRadius: only where the escort itself would fight (ship merge;
		-- 130 slowed the army on every approach to a camp, a checkpoint or the bank and dropped it behind the phone camera).
		--   • ThreatStandingFor live for him: only while he STANDS (below 1 stud/s); walking toward it, units keep the lead
		--     and the catch-up. Lane A0's defend-when-targeted escort (Rollout.Escort) fights the bank guards for him, so
		--     keep ThreatStandingFor equal to Rollout.Escort (both "owner" today).
		--   • Otherwise: while he stands or walks toward it (ThreatApproachOnly; walking away = the normal follow).
		-- Measured on the stand-in, merged tree (army/build/fix_ship; 4d26673 = HEAD):
		--   owner mode: bank stand 40-55 studs, all 5 guards down in 91 of 99 approaches (HEAD 91); Town walk at
		--     16 / 18.4 / 20: no soldier on the phone camera in 1/126, 2/110, 4/101 walking seconds (HEAD 121/126).
		--   everyone else: 79 of 99 (HEAD 87). The band: standing or seated about 50-55 studs from the nearest guard,
		--     one guard can stay at its post ~61 studs away, out of the 55-stud escort range, and keep firing (dense
		--     sweep 48-56 studs x 9 lines: 28 of 72 vs HEAD 41, all lost at 51-53; guard shots +19 %); a mortal player
		--     on 40-55 studs takes the same total damage (8436 vs 8448) and moving fights are equal. The fix is
		--     Rollout.Escort = "all" with ThreatStandingFor = "all". Town walk 2/126, 4/110, 5/101; a walk up to the
		--     Ridge camp 0/16, 0/14, 0/13 (HEAD 15/16, 13/14, 13/13).
		--   ThreatStuds 130 (fix round 2): everyone else 47 of 99 at the bank and 3/16 at the camp.
		-- ThreatKeepCatchUp = true drops only the lead near a hostile (not shipped). ThreatStuds = 0 = off.
		ThreatStuds = 55,
		ThreatApproachOnly = true,
		ThreatStandingFor = "owner", -- "off" | "owner" | "all": keep it equal to lane A0's Rollout.Escort
		ThreatKeepCatchUp = false,
		-- A unit on the player's trail (OrdersConfig.FollowPath) that finds no walkable trail point keeps walking to the
		-- last one it had instead of straight at its slot behind a wall (the doorway stranding). false = e506c9c.
		KeepTrailPoint = true,
		-- While the owner walks on foot (1+ studs/s, not seated), FOLLOW escort units keep the formation: they walk to
		-- their led slot (or his trail) with the catch-up run allowed, and shoot from there (the escort shot is taken
		-- first every think). They close in, stand to fight, walk back at the leash or side-step (lane A0) only while he
		-- stands. On e506c9c they stood to shoot while he walked on and trailed him at the 20-stud escort leash, behind
		-- the ~12.5-stud phone camera (the bank hall walk). false = e506c9c escort walk.
		EscortWalkInFormation = true,
		-- ...except inside EscortWalkLeash studs of him (less than the ~12.5-stud phone camera distance): there a unit
		-- keeps his pace toward its target on his line to it, at most 90 % of this out (between him and the target, as
		-- the e506c9c close-in does). 0 = formation only.
		EscortWalkLeash = 10,
	},

	Recover = {
		Enabled = true,
		-- Triggers (per unit, in FOLLOW only; Hold / Retreat / Attack keep the e506c9c behaviour):
		FollowFarStuds = 80, -- far: more than this from the owner (flat) ...
		FollowFarSeconds = 4, -- ... for this long (not while he drives faster than VehicleDeferSpeed)
		StuckSeconds = 4, -- stuck: less than ProgressStuds of progress toward its goal in this window ...
		ProgressStuds = 2,
		StuckGoalStuds = 4, -- ... while its goal is further than this (a unit at its goal is never stuck) ...
		StuckMinOwnerStuds = 25, -- ... and it is further than this from the owner
		-- fallen: its root is below this height. -8 = under the 8-stud Part ground (bottom -7.5, top 0.5) and above
		-- MapSetup's SafetyCatch floor under the map (top -26: a unit that drops through the ground stands on it at about
		-- -23, so -50 never fired). No walkable surface is below 0 (water spans 0.3..1.5; players are rescued at 0.15).
		FallY = -8,
		PlotMinOwnerStuds = 30, -- plot: more than this from the owner inside a plot square another player owns ...
		PlotSeconds = 4, -- ... for this long, while the owner has been out of that plot this long
		-- plus regroup: a vehicle stop (below VehicleStopSpeed for VehicleStopSeconds, or getting out) after a fast drive,
		-- or a jump on foot (a teleport, a respawn at his plot, a fall rescue: he appears more than FollowPath.ResetJump
		-- away), with it more than VehicleRegroupStuds away (for RegroupWindowSeconds after it; no FollowFarSeconds wait)
		VehicleDeferSpeed = 20, -- studs/s: no recover at all while the seated owner moves faster than this
		VehicleStopSpeed = 6,
		VehicleStopSeconds = 1.5,
		VehicleRegroupStuds = 150,
		RegroupWindowSeconds = 10,
		-- Where to (the first CLEAR spot, at most MaxTries tried): its slot when that is BehindStuds behind the owner's
		-- facing or out of his sight; up to MaxTrailTries of the owner's trail points at least BehindStuds from him and
		-- not ahead of him (newest first, at most TrailMaxStuds away); BehindStuds behind him along his facing, then
		-- back-right, back-left, the same three NearBehindStuds from him; then left and right (SideNeedsCover: only where his head cannot see the spot, else the
		-- unit waits up to MaxDeferSeconds for a better one). Every spot but the slot is moved by the unit's own slot
		-- offset (SpreadScale x its side offset sideways, its slot depth further back), and a spot within LandApartStuds
		-- of another landing of his army in the last LandApartSeconds (or of one of his units) is skipped: units land
		-- apart, never on one another. BehindStuds away and not ahead of him is outside a phone's landscape view (the
		-- camera is ~12 behind him), so units run in and never pop up in front of him. Clear = a ProbeDown-stud ray down
		-- hits a solid part or terrain that is not water, the spot is outside every plot but his own and not under a
		-- WE_Water surface, and the FollowPath body probe plus one ray at root height (a closed gate barrier) reach it
		-- from the owner's root. The unit stands StandHeight above the hit.
		BehindStuds = 24,
		TrailMaxStuds = 60,
		MaxTrailTries = 4,
		SpreadScale = 0.7, -- slot side offsets 5.5 / 10 / 14.5 -> 3.85 / 7 / 10.15: neighbours land >= 3 apart
		LandApartStuds = 3,
		LandApartSeconds = 2.5, -- ship: 2 s plus a margin (a landing exactly 5 thinks = 2.0 s later could slip past a float compare)
		SideNeedsCover = true,
		NearBehindStuds = 14, -- ...the three behind spots again this near (a walled yard, a street)
		MaxTries = 14, -- 4 rays each
		ProbeDown = 12,
		StandHeight = 3.2,
		-- Limits
		CooldownSeconds = 8, -- at most one recover per unit per this ...
		MinMoveStuds = 4, -- ...and a found spot within this of where the unit stands is no move (no PivotTo onto itself)
		MissRetrySeconds = 2, -- ... a search that found no clear spot looks again after this
		PerOwnerPerSecond = 4, -- at most this many recover SEARCHES per owner per second (the rest wait for the next think)
		NoPlayerWithin = 25, -- never land this close to another player ...
		MaxDeferSeconds = 10, -- ... wait up to this long for the first clear spot, then take the next one
		-- Counters: WE_ArmyRecover (number attribute on the owner's Player) + at most one server log line per owner per
		-- LogSeconds. No debug label.
		LogSeconds = 30,
		-- A unit whose root left its model without its Humanoid dying (fell out of the world) is no longer a living
		-- unit: SyncArmy re-forms it (the existing not-living path), queued at most once per owner per second and
		-- ReformPerMinute per owner per minute, and only while the owner is alive with ground under him.
		-- Recover.Enabled = false turns this off too.
		ReformRootless = true,
		ReformPerMinute = 8,
		ReformWindowSeconds = 60, -- the ReformPerMinute window
		ReformDelaySeconds = 1, -- a queued re-form runs this long after it is queued (one per owner per this)
		LandRing = 8, -- recover landings remembered per army (1-32; read once at server start)
		WaterRereadSeconds = 10, -- the WE_Water surface list is re-read at most this often, only while a recover searches
	},

	-- v91 (Code Bot, owner 2026-09-28: the army still despawned while he ran, glitched and walked into each other, and
	-- must not follow him into his base): FOLLOW movement overhaul (Server/Modules/ArmyFollow.luau). Rollout "all" |
	-- "owner" | "off" ("off" = the old v85 / v90 follow code). Wedge slots behind the owner, separation + no
	-- soldier-vs-soldier collision, straight MoveTo with throttled pathfinding only when blocked, catch-up faster than
	-- his sprint, regroup teleport (never a delete), and a wait line outside his main gate while he is in his base.
	Follow2 = {
		Enabled = true,
		Rollout = "all",
		WedgeBack = 3, -- rank k: row = ceil(k / 2), back = WedgeBack + row x RowBack, side = +-(WedgeSide + row x RowSide)
		RowBack = 3,
		WedgeSide = 2.5,
		RowSide = 2.5,
		LeadSeconds = 0.3, -- the slot leads his move by this (capped at LeadMaxStuds)
		LeadMaxStuds = 5,
		FacingTurnDeg = 35, -- standing: the wedge turns with him only past this
		TurnRateDeg = 300, -- v99: the wedge (his root CFrame facing) turns at most this many degrees per second
		SeparationStuds = 3.5,
		SeparationGain = 3,
		SeparationMaxStuds = 3, -- v99: the separation push never moves a goal further than this
		MatchMult = 1.08, -- in the slot: his pace x this (his WalkSpeed incl. Speed Pass / Boost, or his measured speed)
		CatchUpStartStuds = 5,
		CatchUpRampStuds = 10, -- v99: x MatchMult ramps smoothly to x CatchUpMult over this many studs behind
		CatchUpMult = 1.35,
		CatchUpPerStud = 0.6,
		CatchUpMaxMult = 1.8,
		CatchUpMin = 34, -- the catch-up cap is never under this (a boosted sprint is 20)
		MaxSpeed = 50,
		SpeedUpPerThink = 8, -- v99: WalkSpeed rises at most this much per think (0.4 s) ...
		SpeedDownPerThink = 6, -- ... and falls at most this much (smooth catch-up, no lurch)
		ArriveStuds = 2,
		ReissueStuds = 2, -- a MoveTo is re-sent only when the goal moved this far ...
		ReissueSeconds = 5, -- ... or this long passed (Humanoid.MoveTo times out after 8 s)
		PathCooldown = 1.5, -- one path per unit per this, only while the straight line to its slot is blocked
		PathBudgetPerSecond = 8, -- paths per server per second
		PathKeepStuds = 12, -- a path is kept while its end stays this near the slot ...
		PathKeepSeconds = 2, -- v99: ... or while it is younger than this (at a run the slot outruns PathKeepStuds)
		FarStuds = 100, -- v99 (was 70 / 1 s): emergency reposition only this far from its slot ...
		FarSeconds = 3, -- ... for this long
		BaseFarStuds = 140, -- while he is in his base (the wait line)
		-- v99 staged stuck: moved less than StuckStuds while its slot is more than StuckMinStuds away:
		StuckSeconds = 3, -- ... this long: a fresh path at once
		StuckAltSeconds = 6, -- ... this long: an alternate point StuckAltStuds beside it (+ a jump) for StuckAltHoldSeconds
		StuckAltStuds = 6,
		StuckAltHoldSeconds = 2.5,
		StuckTeleportSeconds = 10, -- ... this long: the reposition (the final fallback)
		StuckStuds = 3,
		StuckGoalStuds = 6,
		StuckMinStuds = 10,
		VoidBelowOwner = 60, -- regroup: this far under the owner, or within VoidMargin of FallenPartsDestroyHeight
		VoidMargin = 80,
		OwnerJumpSpeed = 60, -- an owner move faster than this on one think is a teleport / respawn: far units regroup at once
		JumpRegroupStuds = 40,
		VehicleDeferSpeed = 20, -- no regroup while he drives faster than this
		TeleportCooldown = 2.5,
		RegroupBehindStuds = 16, -- v99: a reposition lands on its own slot pushed this much further back (behind the camera)
		RegroupMinOwnerStuds = 6, -- v99: ... and never nearer him than this
		ThinkGapReset = 1.2, -- v99: no ArmyFollow think for this long (fight / other order / owner dead): fresh state
		FaceMoveStuds = 8, -- v99: further than this from its slot it faces where it runs, else his facing
		FaceAfterShotSeconds = 1.2, -- v99: after an escort shot the unit keeps facing its target this long
		SeatCompactSeconds = 4, -- v99: seats are renumbered only after the army size changed and held this long
		StandHeight = 3.2,
		BaseInStuds = 4, -- in his base: this far inside his plot square's edge (out again BaseOutStuds past it)
		BaseOutStuds = 2,
		BaseWaitOut = 12, -- the wait line: this far outside the plot's front edge (main gate) ...
		BaseWaitGap = 5, -- ... beside the gate lane (MainGateWidth / 2 + this), never in it ...
		BaseWaitSpacing = 4, -- ... then this apart, two staggered rows
		--[[ claude-bud (2026-09-29, owner: "the army still walks into the base, soldiers bunch up and walk over each
			other"): tidy follow, owner-only first. Off (Rollout not "owner"/"all" for him) = the v91 behaviour above.
			* Hold: his army stops once he is within HoldApproachStuds OUTSIDE his plot edge (not 4 studs inside), and
			  is released when he is HoldReleaseStuds out again. No follow goal of a unit outside his plot is ever inside
			  it (+ PlotPadStuds): it is swapped for that unit's wait spot, so nobody crosses his gate or plot edge.
			* Wait rows: both sides of the gate lane (MainGateWidth / 2 + WaitGap), PerRow per side per row, ColSpacing
			  apart, RowSpacing deep from WaitOut outside the front edge; each soldier turns to face out on arrival.
			* Fixed seats: each unit keeps its own seat number for life (the lowest free one when it joins), so a death
			  never reshuffles the rest; wedge rows are RowBack / RowSide apart (> SeparationStuds, never inside each
			  other); when he turns round, a row pair keeps its world sides (FlipHysteresisStuds) instead of crossing.
			* Leaving: no far / stuck teleport for LeaveGraceSeconds after he leaves his base (they walk back into the
			  wedge; the void rescue still runs). ]]
		Tidy = {
			Rollout = "owner",
			HoldApproachStuds = 6,
			HoldReleaseStuds = 10,
			PlotPadStuds = 2,
			WaitOut = 14,
			WaitGap = 5,
			PerRow = 4,
			ColSpacing = 4,
			RowSpacing = 4,
			RowBack = 4,
			RowSide = 3,
			FlipHysteresisStuds = 1.5,
			LeaveGraceSeconds = 8,
			-- claude-bud (owner v95 phone test fix): hold cells are raycast / overlap-checked (bad ones skipped outward),
			-- reached straight with no path and no teleport; arrival within HoldArriveStuds. ATTACK: every unit its own
			-- spot by its seat (march rows MarchPerRow x MarchSpacing, MarchAhead in front; a ring of AttackRingSpacing
			-- round the target, at least AttackRingMin), never one shared point.
			HoldArriveStuds = 1.5,
			MarchPerRow = 5,
			MarchSpacing = 3.5,
			MarchAhead = 10,
			AttackRingSpacing = 3.5,
			AttackRingMin = 8,
		},
		LogSeconds = 5,
	},

	Gate = {
		-- The owner's FOLLOW units within RaidConfig.Defense.GateOpenRadius open his friendly gate, only while he is
		-- alive within OwnerNearStuds (flat) of it, and units alone (no owner / ally player at the gate) for at most
		-- UnitHoldSeconds in a row: they pass through with him (or come home to him) and it shuts behind them; units
		-- that stand there after that keep it shut. Units on Hold / Attack / Retreat never open it.
		OwnUnitsOpen = true,
		OwnerNearStuds = 40,
		UnitHoldSeconds = 8,
		-- ...and that 8 s count starts over only once no FOLLOW unit of his has been at the gate for UnitRearmSeconds
		-- (units shuffling in and out of the circle while he idles near it never re-open it again and again)
		UnitRearmSeconds = 3,
		-- ship (crossing rule, the FIX round-3 reviewers' GATETAIL): a unit holds the gate open only while it is still on
		-- the far side of the barrier from him (its centre not more than CrossClearStuds past the barrier plane on his
		-- side). Units that are through never hold it behind him: stand-in, the owner stopping 16 studs inside with a
		-- raider tailing him 35 / 50 / 70 studs behind: the barrier stayed open 9.6 s after he passed and the raider
		-- walked in (4d26673: 1.4 s, kept out; with this rule: 1.6 s, kept out). false = the round-2 rule.
		-- CrossClearStuds 0 (ship fix round 1, GATECAMP): with 3, his rear-rank units standing in their slots against the
		-- shut barrier on HIS side counted as crossing: him standing 13-16 studs from the gate (beyond his own 12-stud
		-- GateOpenRadius) opened it for ~9 s after each turn and a raider camping at it walked in (4d26673: shut). A unit
		-- mid-crossing is covered by RaidConfig.Defense.GateCloseDelay (1 s).
		CrossingRule = true,
		CrossClearStuds = 0,
	},

	-- The FOLLOW think loop runs every army on the server in one task: an error in one owner's motion or one unit's
	-- think is caught (pcall), logged at most once per owner per ErrorLogSeconds, and the loop goes on.
	Loop = {
		ErrorLogSeconds = 30,
	},
}

-- army lane A0: the rollout value of one part, normalised ("off" for a missing part or any other value: fail closed)
function ArmyConfig.RolloutOf(part: string): string
	local r = (ArmyConfig :: any).Rollout
	local v = if typeof(r) == "table" then r[part] else nil
	if v == "owner" or v == "all" then
		return v
	end
	return "off"
end

-- army lane A0: is this rollout part live for this UserId? "all" = everyone; "owner" = the owner's playtest account only
-- (AdminConfig.IsPlaytestOwner, as AircraftWeaponConfig.LiveFor); "off" = nobody. Pure; the server evaluates it.
function ArmyConfig.LiveFor(part: string, userId: any): boolean
	local v = ArmyConfig.RolloutOf(part)
	if v == "all" then
		return true
	end
	if v == "owner" then
		return AdminConfig.IsPlaytestOwner(userId) == true
	end
	return false
end

-- army lane A0: LiveFor for a Player (false for anything that is not a Player)
function ArmyConfig.IsLive(part: string, player: any): boolean
	if typeof(player) ~= "Instance" or not (player :: Instance):IsA("Player") then
		return false
	end
	return ArmyConfig.LiveFor(part, (player :: Player).UserId)
end

-- Follow.ThreatStandingFor: is the standing-only near-hostile pacing live for this player? ("owner": the playtest
-- owner's account only, AdminConfig.IsPlaytestOwner; "all": everyone; anything else: nobody, the round-1 rule)
function ArmyConfig.ThreatStandingFor(userId: any): boolean
	local f = ArmyConfig.Follow
	local v = if typeof(f) == "table" then (f :: any).ThreatStandingFor else nil
	if v == "all" then
		return true
	end
	return v == "owner" and AdminConfig.IsPlaytestOwner(userId) == true
end

return ArmyConfig
