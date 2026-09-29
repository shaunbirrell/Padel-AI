# Army follow / formation — root cause (JOB 22, 2026-09-29, claude-bud)

Symptom (live, phone + PC): the army is stable while the owner stands still. As soon as he walks or turns, soldiers
rotate or rush to new spots, cross through each other, bunch, fall behind then sprint, snap, pile on him, slide
sideways while playing run animations, and the whole army swings round on turns.

## 1. Every controller that touches a soldier (investigated before any change)

Soldier = a SquadOrdersService unit (`Workspace.WarEmpireSquads`, tag `WE_SquadUnit`, attributes
OwnerUserId / FriendlySquad / SquadSlot). Traced end to end for one unit:

| Stage | Where | What it writes | How often |
|---|---|---|---|
| spawn | `SquadOrdersService.spawnUnit` (SOS ~757) via `SyncArmy` | root CFrame at the old `unitOffset` slot, `AutoRotate = true`, `SetNetworkOwner(nil)`, BodyGyro `NPCFaceGyro` (MaxTorque Y 4e5) | on spawn / re-form |
| setup | `ArmyFollow.PrepUnit` (AF ~162) | CollisionGroup `ArmyNPCs` (not with itself, **yes with Default = players**), FallingDown / Ragdoll / PlatformStanding off, ownership kept on late rig parts | once |
| think loop | `SquadOrdersService` loop (SOS ~3336) | `updateOwnerMotion`, then `thinkUnit` per unit | every `OrdersConfig.ThinkInterval` = 0.4 s |
| FOLLOW, owner moving | `thinkUnit` → `escortUnit` (face only: gyro `faceYaw`) → `ArmyFollow.Unit` in the **same pass** | escort gyro yaw, then AF MoveTo + WalkSpeed + gyro | 0.4 s |
| FOLLOW, owner standing near a hostile | `escortUnit` alone (AF `Release`d) | MoveTo to the **old wing slots** (`unitOffset`, FollowSlots ±5.5/±10/±14.5), `AutoRotate = true` **and** gyro `faceYaw` | 0.4 s |
| slots | `ArmyFollow.plan` → `compactSeats` / `assignSeats` | stable persistent seats (no nearest re-pick), BUT Tidy `_afFlip` swaps a row pair's sides every think from the units' actual positions | 0.4 s |
| destination | `ArmyFollow.slotPoint` | `CFrame.lookAt(RAW owner root position, _afDir) * offset + RAW velocity x 0.3 s (cap 5)` | 0.4 s |
| heading | `ArmyFollow.plan` | `_afDir` = owner LookVector (or **his velocity when looking against it: walking backwards flips 180°**) turned at `TurnRateDeg 300°/s` = **120° per think**; always re-aiming while he moves | 0.4 s |
| move | `ArmyFollow.moveTo` | MoveTo when the goal moved ≥ `ReissueStuds 2` (at a run the slot moves ~6 studs per think: **every think**) | 0.4 s |
| arrive | `ArmyFollow.Unit` | only when `d ≤ 2` **and owner speed EMA < 1** and no push: never while he moves | — |
| yaw | `ArmyFollow.faceTo` + `acquire` | `AutoRotate = false`; gyro faces the goal if `d > 8`, **else the formation heading while still walking**; skipped 1.2 s after a shot (escort aims) | 0.4 s |
| speed | `ArmyFollow.setSpeed` | catch-up from the distance to the **led** slot (the lead alone counts as "behind"), cap 34–50 | 0.4 s |
| regroup / stuck | `ArmyFollow.regroup` | PivotTo (void, owner jump, far 100 s/3 s, stuck 10 s) | rare |
| base hold | `ArmyFollow.Unit` Tidy branch | PivotTo turn on arrival | once |
| HOLD / ATTACK / RETREAT / side-step | SOS `thinkUnit`, `attackUnit`, `stepMove` | ~30 direct `Humanoid:MoveTo` calls + gyro | 0.4 s (AF released first) |
| animation (client) | `RigAnimator._Step` | Walk / Idle by measured speed (not restarted; AdjustSpeed 0.6–1.4 ≈ 20 studs/s max); escort figures rigidly 7–12 studs ahead of each unit's yaw | 4 Hz |
| read-only | BaseGuards, CombatService, AimTargets, GateDefense `AnyUnitNear` | targeting only | — |

No Heartbeat / Stepped / RenderStepped loop moves units; no AlignPosition / BodyVelocity; no client moves them;
network ownership is set once (server) and nothing flips it (a `Seated` state is not disabled: a unit could sit).

## 2. Root causes (checked against the 11 questions)

1. **(1, 7, 8) The destination is rebuilt every think from the raw owner pose.** `slotPoint` = raw root position +
   a raw-velocity lead (up to 5 studs) + a heading that turns 120° per think and re-aims on every move. Every course
   change moves every slot by several studs (outer Flank slots sit 9–11 studs out, up to 6 ahead), and MoveTo is
   re-sent to the new spot every think. → rotating / rushing to new spots, the whole army swinging on turns.
2. **(7) Walking backwards / strafing flips the formation.** `want = velocity` when he looks against his motion:
   a 180° flip in 0.6 s; front and back rows trade places. → crossing, bunching.
3. **(2) Row sides swap mid-turn.** Tidy `_afFlip` re-decides each row pair's left / right from where the units stand
   against the rotating heading. → slot swapping, crossing.
4. **(11, 10) Facing ≠ travel.** With AutoRotate off, the gyro holds the formation heading (or the escort's aim)
   while MoveTo walks the unit sideways / backwards; the client plays the forward Walk. → sliding sideways with run
   animations. The 8-stud face-goal threshold toggles and snaps the yaw.
5. **(5) Friendly collision.** `ArmyNPCs` collides with `Default` = players; separation ignores the owner; Flank slots
   sit beside and ahead of him. → soldiers piling on / pushing him.
6. **(4) Two formations, two yaw owners.** Near a hostile while he stands, `escortUnit` walks units to the OLD wing
   slots with AutoRotate + gyro; the moment he moves, ArmyFollow re-acquires and every unit rushes to a different Flank
   slot. The move / stand switch is raw `OwnerSpeed >= 2` (no hysteresis): jitter flips it. → snap / rush.
7. **(8, 9) No arrival deadzone while moving, no stop hold.** Units never "arrive" while he moves; catch-up is measured
   to the led slot; when he stops the lead vanishes and the slot jumps back up to 5 studs. → fall behind then sprint,
   overshoot and back up. (Teleport is NOT the normal catch-up: only void / owner jump / 100 studs for 3 s / 10 s stuck.)
8. **(6) Network ownership is fine** (server, set once). **(3) No per-frame CFrame writes** in normal follow.

Multiple systems fighting: **yes**, in two places — escort gyro yaw vs ArmyFollow in the same pass while moving, and
escort (old slots, AutoRotate + gyro) vs ArmyFollow (Flank) across the stand / move boundary.

## 3. The fix (JOB 22) — see the commit text and `tools/checks/claude_bud_armyfollow.py`

- ONE mover: `ArmyFollow.Command(unit, goal, state)` is the only place that calls `Humanoid:MoveTo` on a soldier;
  SquadOrdersService's HOLD / ATTACK / RETREAT / escort paths call it with their state. Each unit carries one
  `MoveState` (InPosition / Following / CatchingUp / StuckRecovery / Combat / Hold / Attack / Retreat / BaseHold);
  only the current state's code moves it.
- Smoothed formation anchor (`Shared/Util/FormationMath`, `ArmyConfig.Follow2.Stable`): position follows the owner
  with a small lag, a smoothed-velocity lead (capped), heading from his FACING (a walking character faces its travel;
  backing up / strafing with shift-lock keeps his facing, so the formation never flips), turned at a capped rate,
  turns under a deadzone ignored, an about-turn only after a hold time and then at the capped rate, never 180° at
  once. Slot = anchor × fixed seat offset. `_afFlip` off.
- Persistent seats (kept) — sides never swap; re-seated only when the army size changes.
- MoveTo only when the target moved > `MoveReissueStuds` or every `MoveRefreshSeconds`; arrival deadzone with
  hysteresis; InPosition issues nothing.
- Catch-up by WalkSpeed (to the un-led slot); teleport only for void / owner jump / extreme far / last-resort stuck,
  behind the formation.
- Yaw: moving → AutoRotate faces travel, gyro torque 0 (the escort's aim cannot fight it); InPosition → gyro faces the
  formation heading once. Escort standing fights use the SAME formation slot (`ArmyFollow.HomePoint`), the move / stand
  switch has hysteresis.
- Collision: soldiers never collide with each other or with players (`WE_PlayerChars` group), still with the world;
  base guards never with each other. `Seated` disabled on soldiers.
- Client: the Walk animation plays up to the catch-up speed (no foot sliding at a sprint).

## 4. Remaining edge cases

- Escort figures are rigid copies 7–12 studs ahead of each unit (RigConfig.Escort.Offsets): a unit turning to walk to
  its slot swings its escorts. Less visible now (units face travel and turn less), not removed.
- Spawn still places a new unit at the old wing slot; it walks to its Flank seat (once).
- In a vehicle the anchor snaps to the vehicle (no lag) and the old seated rules apply.
