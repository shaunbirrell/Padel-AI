## Army despawn fix (lane FIX, merged onto 4d26673 = lane A0; ship lane army/build/fix_ship)

- **ARMY-FIX-1: Pace, lead and catch-up (round 1 retune).**
  - **Pace:** in FOLLOW a unit walks at the owner's flat speed, never below `OrdersConfig.UnitWalkSpeed` (14).
  - **Lead:** the goal is the owner's slot moved by his velocity x 0.4 s, at most `Follow.Lead.MaxStuds` 4 (round 0: 12). No lead above 40 studs/s (teleport, respawn, fast vehicle), and none on a think at under half the speed of the think before (he is stopping).
  - **Run:** a unit runs 1.5 x the owner's pace (max 28) only when its goal is more than `StartStuds` 6 PLUS the lead distance away, with a walkable line. The lead alone never starts a run, so a unit in its slot walks at his pace. A unit whose line is blocked never runs, and the escort leash walk-back never runs.
  - **Why:** round 0 (lead 12, run beyond 6) made in-slot units stop and start about 5 times a second at 24-28 studs/s. Measured on the stand-in open walk: stopped 0.8-1.1 % of ticks, 0.06-0.09 stop/move toggles per unit per second (round 0: 24 %, 4.7).
  - **Stop:** when the owner stops (or slows hard, not near a hostile), a unit whose goal is at most `MaxStuds + StopHoldStuds` (6) behind it along his facing, within 1.5 s of his last walking think, stands facing his way until he moves again. It does not turn back toward the camera, so the escort figures do not hide: 0 escort hides after the stop at owner speeds 14, 16, 18.4 and 20 (round 0: 12 at 14 and 16).
  - **Reversible:** `Follow.CatchUp.Enabled`, `Follow.Lead.Enabled` (false = e506c9c pacing).

- **ARMY-FIX-2: "Far" is 80 studs for 4 s** (spec: 150 / 5). RigAnimator stops drawing escorts beyond 100 studs, so 80 recovers a unit before it leaves the drawn range. No recover while the owner is seated above 20 studs/s. Reversible: `Recover.FollowFarStuds` / `FollowFarSeconds`.

- **ARMY-FIX-3: "Stuck"** = under 2 studs of progress toward its goal in 4 s, goal more than 4 studs away, more than 25 studs from the owner. FOLLOW only. With no walkable trail point a unit keeps the last one it had (`Follow.KeepTrailPoint`), which fixes the Barracks doorway stranding. No PathfindingService here; lane A inserts its path request before the stuck recover.

- **ARMY-FIX-4: Where a recovered unit lands (round 1).**
  - **Order:** its slot if 24+ behind or out of sight; up to `MaxTrailTries` 4 trail points 24-60 studs back and not ahead; 24 behind; back-right; back-left; the same three at `NearBehindStuds` 14 (a walled yard or street); then left and right. At most 14 tries.
  - **Apart:** every spot but the slot is moved by the unit's own slot offset (0.7 x its side offset, plus its slot depth further back). A spot within 3 studs of another landing of the same army in the last 2 s, or of one of its standing units, is skipped. No two units land on one spot.
  - **In view:** a left or right spot the owner's head can see waits (up to 10 s) for a spot behind him (`SideNeedsCover`).
  - **Clear:** ground under it (a 12-stud down ray, not water), outside every plot but his own, and both the body probe and one ray at root height reach it from his root. The root-height ray stops recovers passing under a closed gate barrier. While the owner stands inside his own plot, a spot outside it (beyond his own wall or gate) is never used.
  - **Budget:** at most 4 searches (not only moves) per owner per second. A search that finds no clear spot looks again after `MissRetrySeconds` 2 (a found spot: `CooldownSeconds` 8).
  - **Jump regroup:** a jump on foot (he appears more than `FollowPath.ResetJump` 40 studs from where he last had a root: a teleport, a respawn at his plot, a fall rescue) opens the same 10 s regroup window as the end of a fast drive, so units more than 150 studs away come back at once instead of after the 4 s far wait. Stand-in: respawn settle 3.2 s, teleports 1.5 / 1.3 s.

- **ARMY-FIX-5: Plots, water and other players (round 1).**
  - **Plot trigger:** a unit is moved out of another player's plot only when it is more than 30 studs from the owner, has stood in that plot for 4 s, and the owner has been out of it for 4 s. A squad at the owner's side at another plot's edge or gate is left alone (round 0 looped every 8 s).
  - **Unchanged:** never land within 25 studs of another player (wait up to 10 s), never into another plot or water, and no recover while the owner is on water.

- **ARMY-FIX-6: Vehicles and owner death.** A fast drive (above 20) that ends (a stop or getting out) opens a 10 s regroup for units more than 150 away. While the owner is dead, units hold where they stand; after respawn the far rule brings them back.

- **ARMY-FIX-7: The friendly gate opens for the owner's own units only while they follow him through it (round 1).**
  - **Rule:** units count only when:
    - the squad order is Follow;
    - the owner is alive and within `Gate.OwnerNearStuds` 40 of the gate;
    - units alone (no owner or ally player at the gate) have kept it open for at most `Gate.UnitHoldSeconds` 8 in a row. After that it stays shut while they stand there, until a player opens it or they leave.
  - **Why this cap and not "8 s after the last player":** after a respawn the owner is home and his army walks back to a closed gate with no player at it; the in-a-row cap lets them in, then shuts.
  - **Never:** Hold, Attack or Retreat units, a dead owner, or an owner who walked away.
  - **Why:** in round 0, units on Hold at the gate held the barrier open for raiders.
  - **Wiring:** `SquadOrdersService.AnyUnitNear`, called from `updateFriendlyGate`. `GateUnitSince` is new on the plot's defense record.
  - **Reversible:** `Gate.OwnUnitsOpen = false`.
  - **Ship:** a unit holds the gate only until it has crossed to his side (ARMY-FIX-25).

- **ARMY-FIX-8: A rootless ghost is re-formed.** A unit whose root left its model without dying (fell out of the world) is re-formed through SyncArmy's existing not-living cull. Its id changes; this is the only case. Round 1: only while the owner is alive with ground under him (one down ray), at most 8 per owner per minute. Reversible: `Recover.ReformRootless`.

- **ARMY-FIX-9: e506c9c pacing near a hostile, only inside the escort's own engage range (ship: ThreatStuds 55).**
  - **Rule:** while a hostile the escort would pick (not calm, one this army may hit) is within `Follow.ThreatStuds` 55 of the owner (= `CombatFairnessConfig.EscortEngageRadius`), FOLLOW units use e506c9c pacing (no lead, UnitWalkSpeed). It is found in the same one NPC scan as the escort pick (lane A0's `escortPickLive` for a live owner, `nearestHostile` for everyone else); the escort target and its list are unchanged.
  - **Owner (`Follow.ThreatStandingFor = "owner"`):** only while he stands. Everyone else: while he stands or walks toward it (`ThreatApproachOnly`).
  - **Why 55 and not 130 (fix round 2):** 130 slowed the army to 14 on every approach to a camp, a checkpoint or the bank, so it fell behind the phone camera. Stand-in, default mode, a walk up to the Ridge camp at 16 / 18.4 / 20: no soldier on the phone camera in 0/16, 0/14, 0/13 walking seconds (130: 3/16; HEAD 4d26673: 15/16, 13/14, 13/13). BuyPathStatic pins ThreatStuds in [30, 55] and at most the engage radius.
  - **Reversible:** `ThreatStuds = 0` turns it off; 130 is the fix round-2 value.
- **ARMY-FIX-10: The not-living cull and the trim are pinned whole**, so a distance condition cannot be slipped into them. `queueReform` is called only for a rootless unit. `SyncArmy` is called only from SetOrder, ApplyResearch, Init hooks, the Died handler and queueReform.

- **ARMY-FIX-11: The recover probe forgets a player who left.** On PlayerRemoving it drops its references to his Player, character and vehicle.

- **ARMY-FIX-12: Counting on the phone.** The owner sees about 20 figures (8 server units + 12 client escorts, RigConfig MaxPerArmy), not 8. The escort figures show only within about 90 studs. The phone test counts figures against a number taken at the start.

- **ARMY-FIX-13: The owner-only lanes change what the owner sees later.** `Rollout.Army` / `Rollout.March` are "owner" in ArmyConfig, but no code reads them in this build (lanes A and C are not merged). When lane A lands, his own army guards outside his gate (spec §3.1); its merged texts say so. This lane's phone_test and owner_text describe only what this build does.
- **ARMY-FIX-14: The stand-in is not Roblox.** Its raycast registers a hit when a ray starts inside a part, it has no unit-to-unit collision, and it has no terrain. "Never lands in a wall" and "no pile-up" need the phone test (steps 6-7).

- **ARMY-FIX-15: The standing-only pacing stays owner-only, with lane A0's escort (`Follow.ThreatStandingFor = "owner"`), measured on the merged tree.**
  - **Values:** "off" | "owner" | "all". "owner" = `AdminConfig.IsPlaytestOwner` (UserId 470626172), the same gate as `Rollout.Escort`. `ArmyConfig.ThreatStandingFor(userId)` evaluates it.
  - **Owner mode, final merged tree, stand-in (99-approach bank sweep: stand 40-55 studs from the guards, 11 approach variants each):** "owner" all 5 guards down in 91/99 (HEAD 4d26673: 91/99, the same approaches), guard shots at the standing owner 2004 (HEAD 2338); Town walk at 16 / 18.4 / 20: no soldier on the phone camera in 1/126, 2/110, 4/101 walking seconds. "off" (the approach rule for him too, measured before the gate crossing rule and the pace smoothing): 91/99, 2109 shots, 3/126, 3/110, 5/101. "owner" is at least as good on both, so it ships.
  - **BANKSTAND (owner mode):** at 50 studs 125 unit hits, 0 guards left, 13 guard shots at him (HEAD 125 / 0 / 31); at 72 studs 100 / 1 left / 12 shots (HEAD 100 / 1 / 15).
  - **Everyone else (standing-only for all, "all", measured too):** 75/99 at the bank against 79/99 for the approach rule, so non-owners keep the approach rule (ARMY-FIX-23).
  - **Keep equal:** keep `ThreatStandingFor` equal to `Rollout.Escort`. When A0 goes "all", set this to "all" and re-run the bank sweep.
  - **Reversible:** "off" = the approach rule for everyone; "all" = the standing rule for everyone.
- **ARMY-FIX-16: The friendly gate's 8 s unit hold re-arms only after the units were away 3 s (`Gate.UnitRearmSeconds`).**
  - Units shuffling across the 12-stud circle while the owner idles near the gate never re-open it again and again.
  - Normal use is unchanged: GATE 8/8 out and 8/8 back in at 16 and 20.

- **ARMY-FIX-17: One army's error never stops every army.**
  - The think loop pcalls `updateOwnerMotion` and each `thinkUnit`.
  - A caught error is warned at most once per owner per `Loop.ErrorLogSeconds` 30, and the loop goes on.
  - Behaviour without errors is unchanged.

- **ARMY-FIX-18: Config first, one kill switch.**
  - `Recover.Enabled = false` now also turns off the rootless re-form (`ReformRootless`).
  - The landing ring, the WE_Water re-read period, the re-form delay and the re-form window moved into `ArmyConfig.Recover` (`LandRing` 8, `WaterRereadSeconds` 10, `ReformDelaySeconds` 1, `ReformWindowSeconds` 60). The values are unchanged.

- **ARMY-FIX-19: A unit held after the owner stopped keeps standing with no walkable-line probe.**
  - Its slot is still just behind it, so it needs no rays per think while he stands.
  - Without this, a walk-then-stand cost 13.9 rays per pass (2.3x e506c9c at BANKSTAND72). With it, the worst scenario is 1.10x.

- **ARMY-FIX-20: The owner texts describe the merged build.**
  - Lane A0 is live for the owner in the same build: his soldiers shoot back at NPCs that shoot at him within 90 studs, and he sees their shots (tracers). The texts say so and never promise it "in a later part".
  - Step 3 counts figures honestly: 8 soldiers on the server plus up to 12 escort figures his phone draws near them (about 20), compared with the count at the start.
  - The gate step walks about 25 steps past the gate: the owner himself opens his gate within `RaidConfig.Defense.GateOpenRadius` 12, so standing 10 steps inside keeps it open by design.
  - No key names and no "click" in any text.
- **ARMY-FIX-21: While the owner walks, escort units keep the formation (`Follow.EscortWalkInFormation`, `Follow.EscortWalkLeash` 10).**
  - **Rule:** in FOLLOW, with the owner on foot at 1+ studs/s, an escort unit takes its shot first (as before), then walks with the formation: beyond `EscortWalkLeash` 10 studs of him it goes back to its led slot or his trail (followMove, catch-up run allowed); inside it, it keeps his pace toward its target on his line to it, at most 9 studs out. No stand-to-fight, no side-step walk and no side-step probe (rays) while he walks. While he stands, the escort is exactly lane A0's / e506c9c's.
  - **Why:** the reviewers' bank-hall gap. The escort leash (20, A0 defend 28) is longer than the ~12.5-stud phone camera distance, so units that stopped to shoot trailed behind the camera for about 10 s in the hall (owner mode 10/126 zero-figure walking seconds, all in the hall). Leash 10 < 12.5.
  - **Measured (stand-in, final merged tree):** owner mode Town walk 1/126, 2/110, 4/101 (HEAD 4d26673: 121/126 at 16); bank-hall legs 7-9: 1/6, 0/5, 1/5 seconds, at the vault turnaround with the units off to the side of the camera, not behind it (reviewer's fix-lane rerun: 10 hall seconds at 16); the bank sweep unchanged for him (91/99 = HEAD).
  - **Reversible:** `EscortWalkInFormation = false` (e506c9c / A0 escort walk); `EscortWalkLeash = 0` (formation only).
- **ARMY-FIX-22: Merge with lane A0 (4d26673).**
  - A0's `escortPickLive` does the ThreatStuds scan with the same filters (the ThreatStuds nearest hostile, then A0's defend / engage picks inside DefendRadius).
  - A0's side-step early return resets the despawn fix's follow state (`followSpeed(st, unit, 0, false)`; `unit.Goal = nil`), so a side-stepping unit never runs at the catch-up pace and its stuck window starts over.
  - The one GetTagged is A0's `hostileScan` (one NPC list per pass).
  - A0's own BuyPathStatic pin on escortUnit is updated for the two merged lines (`and not walkForm`; the side-step reset); nothing else in A0's pins changed.
  - A recover spot within `Recover.MinMoveStuds` 4 of where the unit already stands is no move (no PivotTo onto itself); the stuck window starts over.
  - `Recover.LandApartSeconds` 2 -> 2.5: on the stand-in a respawn regroup landed a unit 2.3 studs from another landing exactly 2.0 s (5 thinks) later; the half-think margin keeps "no two landings within 3 studs within 2 s" true.
- **ARMY-FIX-23: Non-owner players: the phone view wins over the old bank luck.**
  - **Rule for them:** ThreatStuds 55, the approach rule, the walking formation (21). No defend-when-targeted (A0 stays owner-only).
  - **Measured (stand-in, default mode, final merged tree):** Town walk 2/126, 4/110, 5/101 zero-figure walking seconds (<= 10 %; fix round 2: 14/126, 12/110, 13/101; HEAD 4d26673: 121/126 at 16); Ridge camp approach 0/16, 0/14, 0/13 (HEAD 15/16, 13/14, 13/13).
  - **Price:** bank stand 40-55 studs (final merged tree), all 5 guards down in 79/99 approaches against HEAD's 87/99: 9 approaches lost at the 52-stud stop (1/11 vs 10/11), where one guard stays at its post 61 studs away, outside the 55-stud escort range, and 1 won at 40 studs (10/11 vs 9/11). Guard shots at the standing player go down (1883 vs 2169). HEAD's kills there came from units trailing behind the camera that drew the guards off their posts.
  - **Tried and not shipped:** ThreatStuds 130 (47/99), 60 (60/99), standing-only for all (75/99), no walking formation while engaged (46/99).
  - **Fix for them:** lane A0's escort (`Rollout.Escort = "all"`), which gives the owner 91/99.
- **ARMY-FIX-24: The ship lane's numbers come from the headless stand-in, not Roblox.** The owner's phone test (phone_test.md) is the real check: the bank hall walk, the gate, stopping in the open.
- **ARMY-FIX-25: The gate crossing rule (`Gate.CrossingRule`, `Gate.CrossClearStuds` 3).**
  - **Rule:** a FOLLOW unit near the gate holds it open only until it is more than 3 studs past the barrier on the owner's side. Units that are through never keep it open behind him. GateDefenseService passes the barrier's facing (`GateCf.LookVector`); without it the ARMY-FIX-7 rule applies unchanged.
  - **Why:** the FIX round-3 reviewers' GATETAIL: the owner walks home and stops 16 studs inside; his units stood by the gate on his side and kept it open 9.6 s after he passed, so a raider tailing him 35, 50 or 70 studs behind walked in (4d26673: shut 1.4 s after him, raider kept out).
  - **Measured (stand-in, owner and default mode):** the barrier was last open 1.6 s after he passed; a raider 35 / 50 / 70 studs behind was kept out (4d26673 the same). A raider 20 studs behind gets in on 4d26673 too (the owner's own 12-stud opening radius). GATE out 8/8 and back in 8/8 at 16 and 20; GATEFIDGET (owner 18-30 studs inside for 72 s): barrier open 0.0 s; HOLDGATE / GATEX / GATEHOLD / RETREATGATE: barrier open 0 s with his units there, raiders kept out.
  - **Reversible:** `CrossingRule = false` (the ARMY-FIX-7 rule).
- **ARMY-FIX-26: The follow pace is smoothed and stepped (`Follow.CatchUp.PaceSmooth` 0.4, `PaceStep` 1, `PaceJumpStuds` 3).**
  - **Rule:** each 0.4 s pass the pace is his flat speed smoothed with weight 0.4. A change bigger than 3 studs/s (a start, a stop, a sprint) passes at once, and below 1 stud/s it drops at once. Units' WalkSpeed changes only when that pace has moved 1 stud/s or more.
  - **Why:** every Humanoid.WalkSpeed write replicates to every client. The reviewers' OPENJIT: 0.4 studs of position jitter on a client-owned character rewrote WalkSpeed 19.6-20 times a second per army. Smoothing without the jump rule lagged behind a real start and made catch-up runs (open ground at 20: 92 of 145 on-camera unit-samples above the walk animation's speed; with it 7 of 163).
  - **Measured (stand-in):** OPENJIT 1.9 WalkSpeed writes per second per army at 16 and 3.5 at 20. 4d26673 writes none: its units always walk at 14 and fall behind.
  - **Reversible:** `PaceSmooth = 1` and `PaceStep = 0` (the raw pace every pass).
- **ARMY-FIX-27: Known Lows, not fixed in this lane.**
  - **SLIDE:** a catch-up run goes up to 1.5x his pace (at most 28), faster than the walk animation's natural 20.4 (14.5 x 1.4). Stand-in, units on the phone camera while he walks, unit-samples above 20.4: Town walk 24/441, 20/449, 33/429 at 16 / 18.4 / 20 (owner mode; default mode 18/497, 23/470, 29/389), open ground at 20: 7/163. 4d26673 shows 0 because its units are off the camera. The fix is a run animation or a speed cap in the client animator (RigAnimator), which this lane does not touch. Phone step 4 checks for sliding feet.
  - **DRIVESLOW:** at town speed (30 studs/s) one unit-tick fell inside the moving car's body box (the stand-in has no unit-to-car collision). 4d26673: 0, because its units were 94 studs behind. Phone step 5 checks it.
  - **Non-owner bank:** ARMY-FIX-23.
