--!strict
--[[
	ArmyConfig — the field army (SquadOrdersService units). SPEC-ARMY-FINAL §10.1. Config-first; server and client read it.

	████ army lane A0 blocks: Rollout · Escort · ShotFx · Text (+ the LiveFor / IsLive helper) ████
	████ army fix blocks (the despawn fix): Follow · Recover · Gate · Loop (+ the ThreatStandingFor helper) ████
	Other army lanes add their own self-contained blocks to this same table (lane A: Home / Guard / Hold / Path / Ui;
	claude-bud J9: lane C "March" was never built and is retired; ATTACK formations are Follow2.Tidy). Keep each block
	self-contained; this file requires only AdminConfig.

	ROLLOUT (owner 2026-09-28, integrator decision): each part is "off" | "owner" | "all".
	  "off"   = today's game (e506c9c) for everyone;
	  "owner" = only the owner's playtest account (AdminConfig.IsPlaytestOwner, UserId 470626172, the same gate as
	            AircraftWeaponConfig.LiveFor); everyone else keeps today's game;
	  "all"   = everyone.
	  Any other value counts as "off" (fail closed). The SERVER decides (ArmyConfig.LiveFor); nothing is read from a client.
	  Parts: Escort (lane A0: the bank fix, defend-when-targeted, focus fire, side-step, visible unit shots), Army (lane A:
	  guard line, follow outside, paths), Fix (v90 despawn fix).

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
		Escort = "all", -- v101 (was "owner") -- lane A0: bank fix / defend / focus fire / side-step / visible unit shots
		Army = "all", -- v101 (was "owner") -- lane A: guard line, follow outside, movement
		Fix = "all", -- v101 (was "owner") -- v90 (Code Bot): the army despawn fix (Follow / Recover / Gate blocks); "all" once the owner has phone-tested it
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
			Fight = "FIGHTING",
			Wait = "WAITING FOR YOU",
			Return = "RETURNING",
			Clear = "FIGHTING",
		},
		Tile = { Guard = "GUARD", Follow = "FOLLOW", Attack = "ATTACK", Hold = "HOLD", Return = "RETURN" },
		MovingOut = "Army moving out",
		Waiting = "Army waiting for you",
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
			MaxSpeed = 40, -- v126: was 28; the Speed Boost owner walks 25.6 (x1.6), 25.6 x 1.5 = 38.4
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
		ThreatStandingFor = "all", -- v101 (equal to Rollout.Escort) -- "off" | "owner" | "all": keep it equal to lane A0's Rollout.Escort
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
		-- claude-bud JOB 22 (docs/ARMY-FOLLOW-ROOTCAUSE.md): the stable formation controller (Shared/Util/FormationMath).
		-- false = the v99 controller exactly. Every threshold below is tunable without code.
		Stable = true,
		AnchorPosLagSeconds = 0.25, -- the formation anchor follows him with this lag (no raw-pose jumps)
		AnchorVelSmoothSeconds = 0.5, -- his velocity is smoothed over this
		AnchorLeadSeconds = 0.4, -- the slots lead his SMOOTHED velocity by this ...
		AnchorLeadMaxStuds = 4, -- ... capped
		HeadingMoveSpeed = 3, -- smoothed speed above which the heading follows his movement
		HeadingTurnDegPerSec = 90, -- the formation turns at most this fast
		HeadingDeadzoneDeg = 20, -- turns smaller than this are ignored while moving
		ReverseDeg = 120, -- a direction change past this (walking back / a hard strafe) ...
		ReverseHoldSeconds = 1.5, -- ... turns the formation only after holding this long (never a 180 flip)
		StandAlignDeg = 60, -- standing: re-aim to his facing only past this ...
		StandAlignSeconds = 1.2, -- ... held this long
		ArriveDeadzoneStuds = 1.5, -- InPosition within this of its slot ...
		LeaveDeadzoneStuds = 3, -- ... and stays InPosition until this far (hysteresis: no jitter at rest)
		MoveReissueStuds = 2.5, -- a new MoveTo only when the target moved this far ...
		MoveRefreshSeconds = 0.5, -- ... or this long passed
		MovingOnSpeed = 2.5, -- he counts as moving (escort vs follow) above this ...
		MovingOffSpeed = 1.2, -- ... until he drops under this (hysteresis)
		OwnerClearStuds = 3.5, -- soldiers keep this far from him (separation includes the owner)
		CollideWithPlayers = false, -- soldiers never push or block players (they still collide with the world)
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
		CatchUpMin = 34, -- the catch-up cap is never under this (v126: Speed Pass 22.4, Speed Boost 25.6; x1.8 = 46 -> MaxSpeed 50)
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
			Rollout = "all", -- v101
			-- claude-bud (owner: "still glitchy and despawns when walking"): "Flank" = a file on each side of him, all in
			-- front of the phone camera (row k: FlankFront + (k-1) x FlankRowBack studs back, negative = ahead; FlankSide +
			-- (k-1) x FlankRowSide out). "Wedge" = the old formation behind him (RowBack / RowSide below).
			Formation = "Flank",
			FlankFront = -1,
			FlankRowBack = 3,
			FlankSide = 3.5,
			FlankRowSide = 2.6,
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

	--[[ v114 (Code Bot Roblox, owner phone test of v113; docs/ARMY-FOLLOW-ROOTCAUSE-2.md): ONE authoritative FOLLOW
		controller per army (Server/Modules/ArmyController + SoldierController + Shared/Util/FormationController).
		Enabled = false (or Rollout not "all" / "owner" for him) = the v113 behaviour exactly (Follow2 above).
		Permanent slots, a clean Flank grid (one row per unit, its escorts further out in the row), a smoothed anchor, a
		rate-limited heading with deadband + hysteresis, MoveTo only every UpdateSeconds and only when the goal moved,
		arrival deadzone with hysteresis, catch-up by WalkSpeed, staged stuck recovery, reposition (PivotTo) only as the
		emergency fallback. In FOLLOW the escort code only shoots / aims (no MoveTo). ]]
	Follow3 = {
		Enabled = true,
		Rollout = "all", -- "all" | "owner" | anything else = off (v113)
		UpdateSeconds = 0.2, -- the controller tick (MoveTo is never sent more often than this)
		-- v115 (docs/ARMY-FOLLOW-ROOTCAUSE-3.md): a BLOCK BEHIND him on his breadcrumb trail (FormationController)
		Formation = "TrailBlock",
		VelSmoothSeconds = 0.3, -- his velocity is smoothed over this (moving / standing only)
		MovingOnSpeed = 3, -- he counts as moving above this smoothed speed ...
		MovingOffSpeed = 1.5, -- ... until he drops under this (rows only turn while he moves)
		TrailSmoothSeconds = 0.4, -- crumbs are dropped from his position smoothed this much (joystick zig-zags soften)
		CrumbStuds = 1, -- a crumb every this many studs he travels (none while he stands)
		TrailKeepStuds = 90, -- path kept (the oldest crumb's direction runs on straight back past it)
		TangentStuds = 3, -- a row faces his path's direction measured over +- this many studs at its arc
		FirstRowStuds = 7, -- the front row sits this far behind him ALONG HIS PATH ...
		RowSpacing = 4.5, -- ... each next row this much further back along it
		ColSpacing = 5, -- columns this far apart (an even count) ...
		AisleStuds = 7, -- ... except the two inner ones: this far apart, a lane down his own trail (an about-turn)
		ColumnsMax = 4, -- columns = ceil(sqrt(units + escorts)) rounded up to even, 2..this
		RowTurnDegPerSec = 100, -- a row turns at most this fast ...
		RowDeadbandDeg = 8, -- ... only once its path direction is this far off (stops within 1.5 deg), only while he moves
		FoldDeg = 120, -- past this (his path doubled back: an about-turn) a row reverses in place, sides mirrored
		SlotVelBlend = 0.5, -- a slot's velocity (its MoveTo lead and pace) is smoothed by this per tick
		OwnerClearStuds = 5, -- a goal is never nearer him than this ...
		OwnerAheadSeconds = 1, -- ... nor in his walking lane (this much of his travel ahead, LaneHalfStuds each side;
		OwnerAheadMaxStuds = 16, -- ... at most this long): on an about-turn the units on his old path step aside ...
		YieldSpeed = 24, -- ... at least this fast
		LaneHalfStuds = 3.5, -- (= AisleStuds / 2: a unit in his lane steps out to the aisle's edge, not into the next column)
		PartMaxStuds = 5, -- a row he walks back into parts: each half steps out (column order kept) by at most this ...
		PartRampStuds = 12, -- ... ramped in over this much of his approach beyond his lane
		EscortTrail = true, -- clients draw each unit's escorts on the unit's OWN path behind it (RigAnimator), RowSpacing apart
		-- JOB 23 (claude-bud, docs/ARMY-FOLLOW-ROOTCAUSE-4.md): the block is ONE steered body (FormationController.SteerFrames)
		-- instead of rows riding his trail (their slots turned his corners / hairpins at full speed). Steer = false: v115 rows.
		Steer = true,
		FormGain = 3.2, -- its centre closes the gap to its steering point (on his path, behind him) at this per second ...
		FormAccel = 24, -- ... its velocity speeding up / changing course at most this much per second (it keeps going briefly) ...
		FormBrake = 60, -- ... slowing down at most this much (he stops: it stops with him; no coasting into his new path) ...
		FormMaxSpeed = 24, -- ... never faster than this (or FormSpeedMult x his speed in a vehicle), less |turn rate| x radius
		FormSpeedMult = 1.25,
		TurnSlowFactor = 1, -- (while turning it travels that much slower: no slot ever moves faster than FormMaxSpeed)
		BubbleStuds = 3, -- its centre steers no nearer him than its radius + this (no slot swings into him on a corner)
		WaitAheadStuds = 0, -- he walks back into it (its centre this far ahead of him along his walk): it waits, holding its heading
		SteerHeadingPath = false, -- its heading steers to his movement direction NOW (true: his path's direction at the block)
		SlotLateralSpeed = 10, -- turning moves any slot sideways at most this fast: turn rate cap = this / the block's radius
		TurnGain = 2.5, -- turn rate asked per radian of heading error (its heading = his MOVEMENT direction only) ...
		TurnAccelSeconds = 0.4, -- ... reached over this (angular inertia); starts past RowDeadbandDeg, ends within 1.5 deg
		SettleTurnPerSec = 0.8, -- inside RowDeadbandDeg it drifts onto his heading this fast (no standing tilt, no jitter)
		SteerLeadSeconds = 0.35, -- a soldier walks toward its slot + its slot's velocity x this (capped) ...
		SteerLeadMaxStuds = 6, -- ... and is re-aimed when it nears that point off its slot (no stop-start inside a turn)
		SpeedDeadzoneStuds = 1, -- soldier WalkSpeed = its slot's speed + SpeedGain per stud of error past this ...
		SpeedGain = 0.9,
		SpeedLatGain = 0.6, -- ... + this per stud beside it (behind: faster, ahead: slower), one continuous law ...
		SpeedMaxBonus = 14, -- ... at most this over its slot's speed ...
		SpeedMaxSlow = 8, -- ... at most this under it ...
		SpeedSmoothSeconds = 0.1, -- ... eased toward it over this (no step at a state change: the states are labels only)
		-- JOB 24 (claude-bud, docs/ARMY-ATTACK-ROOTCAUSE.md): ATTACK = the same steered block (ArmyController), ONE sticky
		-- squad target (SquadOrdersService pickSquadTarget; units only shoot / aim). AttackSteer = false: the v116 attack.
		AttackSteer = true,
		AttackStandoff = 36, -- the block's centre stops this far from the target on its own side, facing it (fire band 46.75)
		AttackMaxSpeed = 16, -- it advances (and slides into / out of the line) no faster than this
		AttackFeedMax = 12, -- a moving target's velocity is fed forward up to this
		AttackDeployStuds = 8, -- within this of its spot it deploys into the line (folds back past twice this) ...
		AttackDeploySeconds = 1.2, -- ... over at least this, longer when a slot must slide further than AttackSlideSpeed allows
		AttackSlideSpeed = 8,
		AttackLinePerRank = 6, -- the line: this many abreast per rank (centre-out by permanent slot: nobody changes sides) ...
		AttackLineSpacing = 6, -- ... this far apart; the next rank behind with room for its escorts
		AttackAggroStuds = 120, -- the squad target: a hostile within this of the army's centre (OrdersConfig.AttackAggroRange) ...
		AttackKeepExtraStuds = 20, -- ... the current one kept out to this much further ...
		AttackRetargetStuds = 15, -- ... unless another one is this much nearer ...
		AttackLeashStuds = 140, -- ... and never one further than this from him (past it the army follows him again)
		SpikeErrStuds = 6, -- debug: a soldier this far from its slot, or a slot faster than a soldier can run, is logged
		DebugPanelSeconds = 0.5, -- debug: the owner's formation panel refresh
		-- v115 debug (owner-visible, toggleable): slot markers + labels on his client, per-soldier logs on the server.
		-- Debug = false: nothing at all. Default on for DebugUserIds; anyone listed toggles it with /armydebug.
		Debug = false, -- JOB 24: no debug visuals for anyone by default (true = on by default for DebugUserIds)
		DebugUserIds = { 470626172 }, -- only these can turn it on (/armydebug, admin allowlist)
		DebugLogSeconds = 2, -- the per-soldier state line, per army, this often
		DebugPublishStuds = 0.5, -- WE_SlotPos (the marker) is rewritten only when the slot moved this far
		-- soldier (SoldierController)
		ArriveStuds = 2.5, -- in its slot within this (he stands) ...
		LeaveStuds = 4, -- ... and stays there until this far (hysteresis)
		ReissueStuds = 2.5, -- a new MoveTo only when the goal moved this far ...
		RefreshSeconds = 6, -- ... or this long passed (Humanoid.MoveTo gives up after 8 s)
		MoveLeadSeconds = 0.25, -- while he moves a unit walks toward its slot + ITS SLOT's smoothed velocity x this ...
		MoveLeadMaxStuds = 4, -- ... capped (it never reaches the goal and stops mid-walk)
		CatchUpStartStuds = 6, -- catching up past this far from its OWN slot ...
		CatchUpEndStuds = 3, -- ... until back within this (hysteresis)
		TrimPerStud = 0.6, -- in step: WalkSpeed = its slot's pace + this per stud behind its slot (- ahead of it) ...
		LateralPerStud = 0.5, -- ... + this per stud beside it
		CatchUpPerStud = 0.9, -- catching up: WalkSpeed = its slot's pace + this per stud from its slot ...
		CatchUpMaxMult = 1.8, -- ... capped at max(his pace x this, CatchUpMin), never over MaxSpeed
		CatchUpMin = 30,
		MaxSpeed = 40,
		MinSpeed = 8,
		SpeedUpPerTick = 6, -- WalkSpeed changes at most this much per tick up ...
		SpeedDownPerTick = 5, -- ... and down
		FaceTurnDegPerSec = 240, -- in its slot the unit turns to the heading at most this fast (no gyro snap)
		FaceAfterShotSeconds = 1.2, -- after a shot it keeps its aim this long
		-- stuck (progress < StuckProgressStuds while its goal is beyond the deadzone)
		StuckProgressStuds = 1,
		StuckReissueSeconds = 2.5, -- 1) re-issue MoveTo (+ a jump)
		StuckPathSeconds = 5, -- 2) a path (waypoints)
		StuckAltSeconds = 7.5, -- 3) a reachable point beside it for StuckAltHoldSeconds
		StuckAltStuds = 6,
		StuckAltHoldSeconds = 2,
		StuckRepositionSeconds = 10, -- 4) reposition, only this far from its slot and out of his view
		StuckRepositionMinStuds = 20,
		BlockedPathTicks = 2, -- the straight line to its goal blocked this many ticks in a row: a path
		PathMinStuds = 8,
		PathKeepSeconds = 2.5,
		PathKeepStuds = 10,
		PathCooldown = 1.5,
		PathBudgetPerSecond = 8,
		-- emergency reposition (SoldierController.Reposition, the only PivotTo)
		FarStuds = 120, -- this far from its slot ...
		FarSeconds = 4, -- ... this long
		VoidBelowOwner = 60,
		VoidMargin = 80,
		OwnerJumpSpeed = 80, -- he moved faster than this on foot in one tick: a teleport / respawn (anchor snaps)
		VehicleDeferSpeed = 20, -- no reposition while he drives faster than this
		RepositionBehindStuds = 16, -- the spot: its slot pushed this far back (behind the phone camera) ...
		RepositionMinOwnerStuds = 8, -- ... never nearer him than this
		RepositionCooldown = 5,
		AuditSeconds = 5, -- collision groups re-checked on every unit part this often
		YawPublishDeg = 3, -- WE_FormYaw (its row's heading) is written only when it moved this much
		LogSeconds = 5,
	},
	-- claude-bud JOB 24 §2 (docs/ARMY-ATTACK-ROOTCAUSE.md): an ATTACKING army (Follow3.AttackSteer) also fights enemy
	-- PLAYERS and base defenders, server-side: the squad target may be an enemy player (CombatService.UnitMayHitPlayer:
	-- PvP, clan ally, spawn / novice shields -> "Protected"), a gate / tower guard of a base that is not his or an ally's,
	-- or a CombatService NPC; a soldier with no line of sight to a player standing behind a gate shoots the gate. Kills
	-- are credited to the army owner (players: cash, XP, MOST KILLS; NPCs: as his own kills; guards: the JOB 20 guard
	-- reward). Enabled = false: the army hits NPCs only, as v116.
	-- claude-bud JOB 26 (owner: "the attack works but they should be stronger"): the soldier's base numbers (Enabled =
	-- false: OrdersConfig AttackDamage 8 / AttackFireRate 1.8 / UnitHealth 90 and ArmyCombat.PlayerMaxDps, as v118).
	-- Research scales them: Marksman Training (SoldierDamage) = Firepower, Combat Drills (SoldierFireRate) = Training,
	-- Body Armor (SoldierHealth) = Toughness.
	StrongerArmy = {
		Enabled = true,
		Damage = 12, -- per hit (x research), x ArmyCombat.PlayerDamageMult on players
		FireRate = 2.2, -- shots per second per soldier (x research)
		Health = 150, -- soldier max HP (x research)
		PlayerMaxDps = 50, -- per victim per army (a full army kills an unarmoured player in ~2 s, a Titan one in ~4 s)
		NpcHitMarkersPerSecond = 4, -- the owner sees a hit marker / damage number for his army's NPC hits, this often at most
		TracerMinGap = 0.15, -- ArmyConfig.ShotFx.PerArmyMinGap while on (more visible tracers; the per-recipient cap stays)
	},
	ArmyCombat = {
		Enabled = true,
		TargetPlayers = true,
		TargetGuards = true,
		ShootGates = true,
		PlayerDamageMult = 0.6, -- x OrdersConfig.AttackDamage (research-scaled) per soldier hit on a player
		PlayerMaxDps = 40, -- per victim per army: a full army never deletes a player instantly (time to kill >= 2.5 s)
		GuardDamageMult = 1,
		GateDamageMult = 1,
		CreditSteeredAttackKills = true, -- NPC kills by a steered ATTACK pay the owner (the 140-stud leash keeps him near)
		ProtectedNoteSeconds = 8, -- "X is protected" to the attacker at most this often per victim
		HitLogSeconds = 5, -- debug (/armydebug): the per-kind hit / miss / blocked counts, this often
		-- v124 (Code Bot, phone bug "my ATTACK army shot the bank guards but never the player killing me beside it"):
		-- the squad target's priority tiers (FormationController.PickTargetTiered). PreferPlayers: an enemy player
		-- (CombatService.UnitMayHitPlayer: THE shared PvP rule + never a clan ally) in reach outranks every guard / NPC,
		-- so a sticky NPC target no longer hides him; false = the v123 nearest-first pick. AggressorSeconds: one who hurt
		-- the owner within this outranks every other player (0 = off).
		PreferPlayers = true,
		AggressorSeconds = 10,
		TargetLogSeconds = 2, -- debug (/armydebug): the [ArmyTarget] per-candidate verdict line, this often per army
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
