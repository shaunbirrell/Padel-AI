# ARMY FOLLOW ROOT CAUSE 4: turn transitions (JOB 23, claude-bud, 2026-09-29, built on v115)

**What the owner saw on v115:**
- On direction changes the grid deforms into a crescent, compresses and fans out.
- At about 23 s several soldiers are CatchingUp at 13–17 studs while the army is compact.
- At about 24–25 s some soldiers are CatchingUp at 3.3–3.8 studs while their neighbours are Following.

**Kept from v115:**
- permanent `FormationSlot` (S01 is always Slot01);
- the debug system;
- one controller (ArmyController → FormationController → SoldierController);
- the no-despawn fixes;
- NPC↔NPC and NPC↔player collisions OFF;
- `SetNetworkOwner(nil)`;
- the `Follow3.Enabled` kill switch.

## The 15 questions: v115 as it was (measured before any change)

Measured in the v115 acceptance sim (`tools/sim/army_follow_sim.luau`: the real FormationController, SoldierController and Follow3 in the Luau CLI, mock humanoids).

| # | Question | v115 answer (file / function) |
|---|---|---|
| 1 | Desired anchor POSITION | There is no single anchor. Row r = `TrailPoint(trail, 7 + r × 4.5)`: the point that many studs of PATH behind him. It is measured from his raw root position (`t.Head`) back through crumbs, which are dropped every 1 stud from his position smoothed over 0.4 s (`FormationController.TrailStep` / `TrailPoint`). |
| 2 | Desired anchor HEADING | Per row, the trail tangent at that arc length (`Tangent`, ± 3 studs): his movement direction back there. |
| 3 | Actual position → desired | No smoothing. Each tick the row frame IS the trail point. The only smoothing is the 0.4 s lag on the crumbs. |
| 4 | Actual heading → desired | `RowFrame`: turned toward the tangent at `RowTurnDegPerSec`, only while he moves. It starts past an 8° deadband and stops within 1.5°. Past `FoldDeg` 120° the row is reversed instantly and mirrored (`RowFlip`). |
| 5 | Max angular turn rate | 100°/s per row (20° per 0.2 s tick). The fold is an instant 180° with x mirrored. |
| 6 | Anchor offset from LookVector? | **No.** LookVector is used only when a fresh trail is seeded (spawn / teleport / FOLLOW restart). Nothing reads it per tick, and `playerPos − LookVector × dist` does not exist. Measured: a stationary 90° L / 90° R / 180° turn and a spin move every slot **0.00 studs** (tests D, E). So the hypothesis that a stationary spin moves the formation is not the cause. |
| 7 | World slot | `RowFrame(row):PointToWorldSpace(Vector3.new(x × RowSide, 0, 0))`, plus the `Part()` lane opening. |
| 8 | Max slot velocity during a turn | **30.2 studs/s** on a sharp 90°, 29.8 on a 0.3 s 90°, 29.4 on a zig-zag, 30.6 with the max army: about 1.9× his 16. |
| 9 | Normal WalkSpeed | Slot pace + 0.6/stud behind (−ahead) + 0.5/stud beside. 14 + 0.9/stud when he stands. Min 8. |
| 10 | Catch-up WalkSpeed | Slot pace + **0.9**/stud (+ 0.5 beside), capped at min(40, max(pace × 1.8, 30)). |
| 11 | Catch-up ENTER | d > `CatchUpStartStuds` 6 |
| 12 | Catch-up EXIT | d < `CatchUpEndStuds` 3 |
| 13 | Speed change instant or smoothed? | **Stepped.** ±6 / −5 per 0.2 s tick, and the gain jumps 0.6 → 0.9 the moment the state flips. |
| 14 | CatchingUp targets its own slot? | Yes (its slot + its slot's lead). |
| 15 | Catch-up has its own movement loop? | No. It is the same `SoldierController.Drive` tick and the same MoveTo path. Only the gain changes. |

## Root causes (measured, not guessed)

### 1. Slots rode his trail, so their velocity was discontinuous at every corner
- **Where:** `FormationController.RowFrame` and `TrailPoint`.
- **Mechanism:** each row's point follows his path at his speed, so at a corner its velocity swings 90° inside one tick. The row also rotates at 100°/s about that point, which adds up to 8.5 × 1.75 ≈ 15 studs/s to an outer slot. Slots reached 30 studs/s.
- **Shape:** rows on different stretches of the path have different headings. That is the crescent / compress / fan-out the owner saw.

### 2. About-turn hairpin plus fold
- **Where:** `TrailPoint` and the `FoldDeg` branch of `RowFrame`.
- **Mechanism:** after he reverses, each row's point runs up his old path into the turn point and straight back. Its velocity reverses in one tick. Rows reach the hairpin one after another, and each is folded.
- **Result:** a whole rank that was in place falls behind together.
  - u180: 5 of 5 CatchingUp, 7.8 studs.
  - Max army: after row 4 folded at t = 18.2 s, all four rank-1 soldiers went from 0.1–2.6 to 8.4–10.1 studs within 0.4 s (7 of 8 CatchingUp, 11.5 studs). That is the "compact army, several CatchingUp" signature.
- **Link to the live 13–17 studs:** with a slower-responding soldier model (acceleration 40, turn 360°/s instead of 80 / 720), which is closer to live network and physics lag, the same v115 paths give 13.1 studs (walk-back), 15.4 (tight circle) and 18.5 (max army). That is the owner's 13–17 range.

### 3. Binary catch-up gain with 6 / 3 hysteresis
- **Where:** `SoldierController.Drive`.
- **Mechanism:** the gain jumps 0.6 → 0.9 at 6 studs and only drops back under 3. So two soldiers both 3.3–3.8 studs off can differ: the one that passed 6 earlier is "CatchingUp" at a higher gain, and its neighbour is "Following". That is the 24–25 s observation, and the speed step makes it worse.

### Not a cause
Player LookVector (see question 6).

## The fix (Follow3.Steer = true; false = the v115 rows exactly)

### `FormationController.SteerFrames`: the block is ONE steered body

**Position.** C, the block's centre and its pivot, steers to a point on his walked path. That point puts the block's nearest slot `FirstRowStuds` behind him, measured along the way he walks now and with the block turned as it is now. Two extra rules apply:
- the block's centre never comes within its radius + `BubbleStuds` of him;
- the point's velocity is fed forward, with `FormGain` per stud of gap, and the block aims at the point minus its own travel this tick, so it lands on the point rather than a tick ahead.

Its velocity is limited:
- `FormAccel` 24 studs/s² when speeding up or changing course, so it keeps going briefly;
- `FormBrake` 60 when slowing along its course, so it stops with him and never coasts into his new path;
- `FormMaxSpeed` 24, less |turn rate| × radius while it turns, so no slot ever moves faster than 24.

**About-turns.** When he walks back into the block (its centre ahead of him), it stops going his way and waits with its heading held, so its aisle stays on his path. Once he is past its centre, it comes round.

**Heading.** Desired = his smoothed MOVEMENT direction. It is updated only while he moves (MovingOn / MovingOff hysteresis). It never reads his look vector, so a stationary spin moves nothing.
- Angular inertia: `TurnAccelSeconds`.
- Turn-rate cap = `SlotLateralSpeed` 10 / the block's radius. The 5-unit block turns at up to about 46°/s, and a bigger army turns slower.
- An 8° deadband with a slow drift inside it.
- It pivots about its own centre, not about him.

**Slots.** Row frame = C − H × (r × RowSpacing − half depth), and slot = that frame × a constant offset. Every slot path is smooth and continuous. No slot ever jumps, and the slot indexes never change.

### `SoldierController.Drive`: one continuous speed law
- **Speed:** WalkSpeed = base + 0.9 per stud of error past a 1-stud deadzone (behind its slot: faster; ahead: slower) + 0.6 per stud beside it.
  - base = its slot's speed now, or the unit walk speed while he stands and the slot is still;
  - clamped to [base − 8, base + 14] and to MaxSpeed;
  - eased over 0.1 s.
- **Labels only:** Following / CatchingUp are labels and change nothing.
- **Destination:** always its own slot + that slot's velocity × 0.35 s. Near him the lead is shortened, not pushed sideways.
- **Re-aim:** a soldier about to reach its MoveTo point while still off its slot is re-aimed. That is still at most one MoveTo per 0.2 s tick. The cause was inner slots on a turn moving less than `ReissueStuds` per tick, which made soldiers stop and start.
- **Not done:** no higher catch-up speed, no extra MoveTo rate, no teleport or PivotTo.

### Debug (owner only, `/armydebug`)
- **Labels:** "S01 / Slot 01" over "F 2.1" / "C 8.5" / "S 0.4".
- **Formation panel** (top right, tap to fold): formation speed, turn rate, heading error, player / desired / actual heading, max slot speed, average / max slot error, catching up N / total.
- **Trails:** cyan / magenta dots for the last 1.6 s of the lowest and highest FormationSlot.
- **Spike log:** `[ArmyDebug] SPIKE` (max error > 6, or a slot faster than a soldier can run) with heading data and the waiting flag.

## Metrics: the acceptance set A–J, judged WHILE moving / turning

Set: `tools/sim/army_follow_sim.luau` with J23 = true. Thresholds are in `tools/checks/claude_bud_armyj23.py`. The four data columns are:
- **v115:** v115 with the normal soldier model;
- **JOB 23:** JOB 23 with the normal soldier model;
- **v115 slow:** v115 with the slow-soldier model;
- **JOB 23 slow:** JOB 23 with the slow-soldier model.

The normal-model columns read max slot error (studs) / mean / most CatchingUp at once / max slot speed (studs/s). The slow-model columns read max error / CatchingUp.

| Test | v115 | JOB 23 | v115 slow | JOB 23 slow |
|---|---|---|---|---|
| A straight | 3.6 / 0.5 / 0 of 5 / 16.0 | 2.6 / 1.0 / 0 of 5 / 16.4 | 3.0 / 4 | 2.2 / 0 |
| B gentle 90° (2 s) | 3.6 / 1.0 / 0 of 5 / 26.5 | 3.4 / 1.1 / 0 of 5 / 23.4 | 3.2 / 4 | 3.6 / 0 |
| C sharp 90° (0.1 s) | 6.2 / 1.3 / 1 of 5 / 30.2 | **5.2** / 1.4 / **0** of 5 / **24.0** | 8.1 / 4 | 6.8 / 1 |
| D stationary 90 L / 90 R / 90 R / 180 | slots moved 0.00 | slots moved **0.00** | – | – |
| E spin in place | slots moved 0.00 | slots moved **0.00** | – | – |
| F big circle (r 60) | 3.6 / 0.9 / 0 of 5 / 22.9 | 3.5 / 0.8 / 0 of 5 / 19.2 | 3.0 / 4 | 2.8 / 0 |
| G tight circle (r 10) | 6.1 / 2.5 / 1 of 5 / 27.0 | **4.3** / 2.0 / **0** of 5 / 25.4 | 15.4 / 4 | **6.2 / 1** |
| H zig-zag | 6.9 / 2.3 / 1 of 5 / 29.4 | **5.6** / 1.8 / **0** of 5 / 26.9 | 7.6 / 4 | 9.9 / 2 |
| I 180° walk-back | 7.8 / 1.7 / **5 of 5** / 24.1 | 7.5 / 1.6 / **1** of 5 / 24.7 | 13.1 / 5 | 11.5 / 5 |
| J max army (8 units, 12 escorts) | 11.5 / 2.1 / **7 of 8** / 30.6 | 10.6 / 1.9 / **4** of 8 / 31.8 | 18.5 / 7 | 14.0 / 7 |

- Every test in both designs: 0 slot changes, 0 teleports.
- The v115 acceptance set (its 10 tests and thresholds) still passes: FAILS 0.
  - One threshold was adjusted, with a claude-bud comment: an "orbit" tick is not counted while the steered block is deliberately waiting for him to walk back through it. That tick was 15.1 studs against a 15-stud limit, in max army.

## Edge cases and what is still open
- **Tight circle** (r 10 = 92°/s, faster than the block may turn): the block lags, and a slot comes within 3.0 studs of him. The soldier's goal is pushed out of his 5-stud clear zone, so no soldier comes nearer than 5.1.
- **About-turn** (I, J):
  - The rows he walks back into still part and step out of his lane (v115 behaviour).
  - The biggest errors left are one soldier walking round him after he has gone through the block (max army 10.6).
  - Rank-wide simultaneous catch-up is down from 7 of 8 to 4 of 8, and from 5 of 5 to 1 of 5.
- **Slow-soldier model:** the walk-back (11.5, 5 CatchingUp) and zig-zag (9.9) are still high. The phone test will show whether real humanoids behave more like the normal or the slow model.
- **After a stop:** the block finishes settling for up to about 1 s, so the standing error is 3.3–4.5 (v115 2.0–3.7).
- **The rigid block does not bend on a corner:** on a sharp turn it keeps going briefly, then arcs round behind him, and stays ≥ 7.6 studs from him.
- **Vehicles:** the block's speed cap scales with his speed (× 1.25). This is untested in the sim.
- **Cost:** per army per 0.2 s tick, three loops over at most 20 cells. No new instances on the server; debug instances exist only on the owner's client.
