# ARMY ATTACK: root cause and fix (JOB 24, claude-bud, 2026-09-29, built on v116)

**What the owner saw:** "army is good when following but when I click attack it's terrible."
**Constraint:** FOLLOW must not change. The sim numbers for the whole FOLLOW set, J23 A–J and the v115 set, are identical before and after this job.

## What happened when ATTACK was pressed (v116, traced before any change)

1. **Client.** The Army buttons (`OrdersController`) send the order "Attack". There is no target in it. `SquadOrdersService.SetOrder` sets `st.Order`, resets each unit's chase state and flashes the order billboard.
2. **`Server/Modules/ArmyController.stepArmy`.** State ATTACK ≠ FOLLOW, so it clears `LastPos` and **returns**. The steered block and `FormationController` are abandoned. The permanent `FormationSlot`s still exist but nothing uses them.
3. **`SquadOrdersService` think loop** (`OrdersConfig.ThinkInterval` 0.4 s), in `thinkUnit`:
   - `ArmyFollow.Release(unit, "Attack")` calls `SoldierController.Release`: AutoRotate goes back on and the face gyro gets full torque back.
   - `_PaceSpeed(unit, 0)` sets WalkSpeed to a flat `UnitWalkSpeed` 14, because FollowPace is not live outside FOLLOW.
   - Then `attackUnit`.
4. **Targets (`attackUnit` → `nearestHostile`).** Each soldier separately picks the hostile nearest ITSELF within `AttackAggroRange` 120. It is re-picked every think. Different soldiers chase different NPCs.
5. **Movement (every think, no reissue threshold).** `ArmyFollow.Command` → `SoldierController.Move` → `Humanoid:MoveTo`:
   - **Target beyond the fire band** (85 % of `AttackRange` 55 = 46.75): the soldier walks to its "ring" seat, `ArmyFollow.AttackPoint(..., "ring")`, radius max(8, n × 3.5 / 2π) = **8 studs round the target**.
   - **Inside the band:** MoveTo its own position, i.e. stop wherever it crossed 46.75.
   - **No clear shot:** with `UnitChaseWithoutLos` it keeps walking to the ring seat 8 studs from the enemy.
   - **Nothing in reach:** "march" rows **10 studs in FRONT of the player's LookVector**, re-issued every think, so turning the camera swings the army round in front of him.
6. **Yaw.** `faceYaw` aims the gyro at the target while AutoRotate is also on: two yaw owners.
7. **Teleport and collisions.** No PivotTo in ATTACK (`SoldierController.Reposition` runs only from Drive, which does not run). Collision groups are unchanged: soldiers ↔ soldiers and soldiers ↔ players off.
8. **Attack end.** Never on its own: the order stays "Attack". When the target dies, each soldier takes its own next nearest target, or marches in front of him. Only a new order ends it. Back in FOLLOW, `ArmyController` restarts the block from scratch (`prevState ~= "FOLLOW"` → snap).

## Root causes (measured, `tools/sim/army_attack_sim.luau` MODE "old": the v116 movement above re-implemented line for line)

1. **No formation while attacking** (`SquadOrdersService.attackUnit` + `ArmyFollow.AttackPoint "ring"`). Every soldier walks straight at its own seat 8 studs from the target and stops wherever it crosses 46.75, so they converge in a narrow cone. Measured: the closest two soldiers come **0.05–0.74 studs** apart (bodies overlapping), with 118–3386 clump ticks (a pair under 2.5 studs) per test.
2. **One target per soldier, re-picked every 0.4 s** (`attackUnit` → `nearestHostile` from the unit's own position). The army splits and swaps targets. A moving NPC means a new MoveTo every think, so they run around.
3. **"Nothing in reach" = march in front of his LookVector** (`AttackPoint "march"`). After the target dies the army runs in front of him and **never re-forms** (reform: never, in targetDies and ownerWalks). A soldier came within 0.40 studs of him.
4. **Walls: no line of sight → chase to 8 studs from the target.** This runs into the enemy group. It comes from the code (`UnitChaseWithoutLos`); the sim world is flat, so it is not measured.
5. **Flat WalkSpeed 14, MoveTo every think, and the gyro fighting AutoRotate** make it jerky on top of the above.

## The fix (`Follow3.AttackSteer = true`; false = the v116 attack above)

**ATTACK is a mode of the same steered block as FOLLOW (`ArmyController`).**
- **Advance** (`FormationController.SteerFrames`, `army.Attack`): the block steers to its own side of the target, `AttackStandoff` 36 from it, facing it, at `AttackMaxSpeed` 16. Heading inertia and the rate cap, acceleration, braking and the bubble round him all still apply.
- **Deploy.** Within `AttackDeployStuds` 8 of that spot, every slot slides into the **attack line**, `FormationController.LineOffset`:
  - `AttackLinePerRank` 6 abreast, `AttackLineSpacing` 6 apart, centre-out by the unit's permanent slot index, so nobody changes sides;
  - further ranks behind, with room for escorts;
  - the slide is blended (smoothstep), and its duration scales so no slot slides faster than `AttackSlideSpeed` 8.
  - The block's speed is capped while blending.
  - Deployed soldiers stop (InPosition) and face the target.
- **Moving target:** its motion is fed forward (capped). The line slides with it.
- **Target:** one per squad, `SquadOrdersService.pickSquadTarget` + `FormationController.PickTarget`.
  - The nearest hostile to the army's centre that this squad may hurt (`nearestHostile`'s rules), within `AttackAggroStuds` 120 and within `AttackLeashStuds` 140 of him.
  - Sticky: it switches only if another is `AttackRetargetStuds` 15 nearer, or the current one dies or leaves reach (+ `AttackKeepExtraStuds`).
  - Server-side NPC roots only. The client still sends only "Attack".
- **Shooting:** `SquadOrdersService.attackAimOnly` per unit per think. When the gun is ready, it shoots the squad target if it is in that unit's fire band and in sight; otherwise the nearest visible hostile in its band (`pickShot`, line of sight kept). It faces what it shoots. **It never walks:** no ring seats, no chase, no march.
- **End** (target down, out of the leash, or the order changed): the line slides back into the block. It re-forms on **its own side** of him with its heading kept (the trail is reseeded from the army's position), then follows as usual. FOLLOW ↔ ATTACK never restarts the block. Only HOLD and RETREAT do, as before.
- **Not done:** no WalkSpeed raise, no extra MoveTo, no teleport. Soldiers move only through `SoldierController.Drive`.

## Metrics (sim; 5 units with 6 escorts, or 8 units with 12 escorts in max army)

"Closest pair" is the minimum distance between any two soldiers during the attack.

| Test | v116 closest pair / clump ticks | JOB 24 closest pair / clump ticks | JOB 24 max / mean slot error deployed | JOB 24 time to deploy | JOB 24 time to reform | JOB 24 moved while deployed (studs/s) | min distance to him (v116 → JOB 24) |
|---|---|---|---|---|---|---|---|
| Stationary target | 0.23 / 418 | **3.22 / 0** | 1.66 / 1.41 | 5.6 s | 2.6 s | 0.08 | 3.19 → 5.18 |
| Moving target (8 studs/s for 10 s) | 0.26 / 624 | **4.26 / 0** | 1.98 / 0.97 | 10.3 s (settles once it stops) | 2.6 s | 0.00 | 1.38 → 4.38 |
| Target dies mid-attack | 0.05 / 497 | **2.27 / 6** | 0.80 / 0.67 | 5.9 s | **2.6 s (v116: never)** | 0.00 | 0.40 → 4.19 |
| Switch targets (A dies → B) | 0.74 / 694 | **3.22 / 0** | 1.66 / 0.96 | 5.6 s | 2.6 s | 0.44 | 3.19 → 5.18 |
| Cancel attack mid-approach | 0.23 / 118 | **3.22 / 0** | – | – | **0.57 s** | – | 3.19 → 5.18 |
| Max army (8 units) | 0.18 / 3386 | **3.05 / 0** | 1.46 / 0.63 | 6.5 s | 4.0 s | 0.10 | 1.43 → 4.78 |
| He keeps walking (east at 16) | 0.21 / 1704 | **4.17 / 0** | 1.64 / 1.20 | 5.0 s | **2.6 s after the leash (v116: never)** | 0.34 | 6.16 → 5.21 |

- Every JOB 24 test: 0 teleports, 0 slot changes, 0 path crossings (v116: up to 5), MoveTo ≤ 4.5 per soldier per second.
- In band: 70–83 % of soldier-ticks, including the approach.
- Max WalkSpeed during the attack: 23–32 studs/s.
- FOLLOW is unchanged: J23 A–J and the v115 set give the same numbers as v116.

## Kill switches
- `ArmyConfig.Follow3.AttackSteer = false`: the v116 attack (`attackUnit`), exactly.
- `Follow3.Steer = false`: v115 follow rows, and ATTACK falls back to v116, because AttackLive needs Steer.
- `Follow3.Enabled = false`: v113.

## Debug removal
- `Follow3.Debug = false`. Nobody sees markers, discs, lines, labels or the formation panel by default, including the owner.
- `/armydebug` (admin allowlist) still toggles it for a `DebugUserIds` player: the server gates `DebugFor` on the attribute plus DebugUserIds, and the client draws only while `WE_ArmyDebug` is on.
- With debug off, the server publishes no `WE_SlotPos` / `WE_ArmyPanel`, and the SPIKE and per-soldier logs stay off (they print to the console only when toggled on).

## Edge cases and what is still open
- **Walls:** the line does not chase round walls. A soldier with no line of sight holds its line cell and shoots the nearest visible hostile in its band. If the target is fully walled off, nobody fires until it moves or the player repositions. The v116 give-up / trail walk is not used in steered ATTACK.
- **Obstacles:** a line cell inside an obstacle is handled by SoldierController's stuck ladder (re-issue, path, side step), as in FOLLOW.
- **Target inside his base:** the base hold is skipped while there is a target; the gate cells return when it ends.
- **Several enemies:** the squad focuses one. Other enemies in a soldier's band are still shot when the focus is out of its band or out of sight.
- **Sim limits:** the v116 behaviour is a re-implementation (the service needs the Roblox runtime). The world is flat and targets don't shoot back. Humanoids are mocks. Not run in Studio or on a phone.
