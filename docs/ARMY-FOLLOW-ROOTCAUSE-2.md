# Army follow / formation — root cause 2 (v114, 2026-09-29, Code Bot Roblox)

Owner phone test of v113 (place version 111): the despawn / reappear bug is gone (units persist — kept), but soldiers
still swap targets, cross / weave, run sideways, bunch, walk through / around him and constantly correct, and ~8-9 s
into the recording the crowd round him suddenly "clicks" into a clean formation. Everything below was read from the
v113 code (commit 8a11d8b) BEFORE any change. Line numbers are v113.

Files: `AF` = `src/ServerScriptService/Server/Modules/ArmyFollow.luau`, `SOS` =
`src/ServerScriptService/Server/Services/SquadOrdersService.luau`, `FM` = `src/ReplicatedStorage/Shared/Util/FormationMath.luau`,
`RA` = `src/StarterPlayer/StarterPlayerScripts/Client/Modules/RigAnimator.luau`, `RC` = `.../Configs/RigConfig.luau`,
`AC` = `.../Configs/ArmyConfig.luau`.

## 1. Slot swapping / crossing / weaving (symptom 1)

Seats themselves are persistent in v113 (`AF.assignSeats` 452-478 never uses distance), but the POINT each unit walks to
is rebuilt every 0.4 s think from several inputs that change independently of the seat, so the target jumps around:

| # | Where | What moves the target |
|---|---|---|
| a | `AF.Unit` 1040-1067 | **Separation push** from the neighbours' *current* positions (SeparationStuds 3.5, gain 3, up to 3 studs) is added to the slot every think. Flank neighbours sit ~3.6-4 studs apart (see 3), so the push is almost always on: every unit's goal wobbles with where its neighbours happen to be → weaving, constant correction. |
| b | `AF.Unit` 1053-1060 | **Owner push** (OwnerClearStuds 3.5) — row 1 Flank seats are 3.6 studs from him, the anchor lags him, so the push toggles on/off each think. |
| c | `AF.Unit` 1205-1239 | Target switches between **the slot, a path waypoint, and a "mid" point half-way to the owner** depending on one 1.2-stud-high ray (`clearLine`) per think → a unit swaps between 3 different targets as props cross the ray. |
| d | `AF.Unit` 1006-1026 | Stuck stage 2 "alternate point" 6 studs sideways (+ jump) for 2.5 s — sideways runs across the formation. |
| e | `AF.compactSeats` 621-650 | 4 s (`SeatCompactSeconds`) after any size change **every unit above the hole is renumbered** (seat i → i-1 …): several units change side/row at once and cross. |
| f | `SOS.thinkUnit` 2652-2670 + `SOS.escortUnit` 1738-1773 | Owner standing near a hostile: escort fight takes the unit (`Release(unit,"Combat")`): **close in toward the hostile** (goal = on the line to it, ≤ 90 % leash, 1762-1769 — every unit's goal lands on the same line = bunch), or a **side-step** (`stepMove` 1636-1652). The instant he moves (`OwnerMoving` hysteresis) ArmyFollow re-acquires and they all rush back to Flank seats. Two controllers, two targets per unit. |
| g | `FM.Step` 56-112 | Heading = his FACING at 90°/s with a 20° deadzone. OK in itself, but every heading change moves the outer seats several studs sideways, and with (a)-(c) on top the unit re-aims constantly. |

## 2. The snap ~8-9 s in (symptom 2)

No per-frame CFrame writes exist in normal follow. The snap is a **yaw snap amplified by the client escort files**, plus
three rarer hard corrections:

1. **Gyro torque restore with a stale target** — `AF.setYawMode(unit,false)` 218-233 on arrival (`AF.Unit` 1129-1136)
   gives the NPCFaceGyro its full torque back (MaxTorque Y 4e5, P 5000) while its CFrame target is whatever it last
   was (spawn yaw / an escort aim / an old heading), then `faceTo` 886-903 writes the formation heading in the same
   think. Every unit that arrives whips round to the heading in ~0.1-0.2 s. `AF.Release` 309-326 does the same on
   every order / combat change.
2. **The escort figures make that look like the whole army snapping**: `RA.buildEscort` 260-325 welds up to 3
   client-only copies of each unit rigidly **7 / 9.4 / 11.8 studs AHEAD of the unit in the unit's own frame**
   (`RC.Escort.Offsets` 94, RootJoint C0 303). While units run to their seats they face travel (AutoRotate), so their
   files point in every direction — the "crowd around him", figures "moving through" him and across the formation.
   When he stops (~8-9 s into the clip) the units arrive, the gyros snap them to the heading and every 12-stud file
   swings into line at once = "suddenly correct into clean formation". Same whenever a unit turns: its file sweeps
   through its neighbours and through the player.
3. Hard PivotTo corrections still in the follow path: `AF.regroup` 847-872 — void (967), **owner-jump > 40 studs**
   (978, `OwnerJumpSpeed` 60 from one 0.4 s sample), far 100 studs / 3 s (983-991), **stuck 10 s** (1002-1005; units
   crowded round him whose seat is > 10 studs away and not progressing hit this at ~10 s). `AF.Unit` 1117 Tidy base
   hold **PivotTo turn** on arrival at a gate cell.
4. Stand/move boundary: see 1f (escort fight target vs Flank seat) — a mass rush that looks like a correction.

## 3. Bunching (symptom 3)

`AC.Follow2.Tidy` Flank (392-395, `AF.slotPoint` 795-798): row k at back = −1 + 3(k−1) (row 1 is **1 stud AHEAD** of
him), side ±(3.5 + 2.6(k−1)). Row 1 is 3.6 studs from the owner; consecutive rows on a side are only
√(2.6²+3²) ≈ 4.0 studs apart — inside `SeparationStuds` 3.5 + body width, so the push of 1a never settles. Plus the
escort files of row k+1 (7-11.8 ahead) land on row k's files. Nothing guaranteed ≥ 5 studs from him.

## 4. Collision (symptom 4)

v113 already has `ArmyNPCs`/`ArmyNPCs` = false and `ArmyNPCs`/`WE_PlayerChars` = false (`AF.ensureGroup` 176-195), but
the player group is only created and hooked when `Follow2.Stable` is on, and late rig parts rely on one
`DescendantAdded` hook; nothing audits that every part really carries the group. OK in practice; hardened in v114.

## 5-8. Rotation / anchor / reissue / facing

* Heading follows facing (fine on phone) but turns start at 20° with no hold time; the stand realign turns at the full
  rate after 1.2 s (FM 96-111).
* Anchor = lerp(raw root, 0.25 s) + smoothed velocity × 0.4 s lead (FM 56-67, 115-126) — acceptable, kept in spirit.
* `FM.ReissueDue` 145-152: MoveTo re-sent every `MoveRefreshSeconds` 0.5 s even if the goal did not move, and the
  think is 0.4 s (SOS 3340) — coarse; goal moves ~8 studs per think at a sprint (target lurches).
* Arrival 1.5 / leave 3 (FM 129-142) is fine but a separation push (1a) keeps pushing units out of it.
* Facing: moving = AutoRotate (good); arrival = gyro snap (2.1).

## 9. Destroy / Clone

Only `SOS.destroyUnit` via `SyncArmy` (died / model gone / root lost / trim when soldiers < units, 2964-2990) and
`clearSquad` (order disabled / player leaves). No formation, path, direction, order or speed code destroys or clones a
unit. Kept as is.

## 11-12. Controllers touching a soldier (v113)

MoveTo: `AF.Command` (the only `Humanoid:MoveTo`) called from AF follow + ~30 SOS sites (escort, side-step, HOLD,
ATTACK, RETREAT, recover). PivotTo: `AF.regroup`, `AF.Unit` base hold, `SOS.recoverUnit` 2525 and
`SOS._PaceRecover` 2902 (legacy v85/v90 paths, not reached while Follow2 is live). Root CFrame: `SOS.spawnUnit` 774
(creation only). Yaw: `SOS.faceYaw` (gyro target) from escort / attack / retreat, `AF.faceTo`, `AF.setYawMode`,
`AF.Release`. WalkSpeed: `AF.setSpeed`, `SOS.setSpeed`, `SOS.followSpeed`, `SOS._PaceSpeed`. Two systems position the
same NPC in FOLLOW: AF follow and the SOS escort fight (1f).

## v114 fix (ArmyConfig.Follow3, kill switch `Follow3.Enabled = false` → exact v113 behaviour)

* `Shared/Util/FormationController.luau` (pure, Luau-CLI tested): smoothed anchor (exponential follow of his position
  + capped smoothed lead), heading from his movement direction (his facing when he backs up / strafes) with a 18°
  deadband + hold time and a 100°/s cap, a clean Flank grid (one row per unit: unit 6 studs out, its escorts 5.5 studs
  further out in the same row, rows 5.5 deep), PERMANENT slot assignment (fill holes only).
* `Server/Modules/SoldierController.luau`: the ONLY place that calls `Humanoid:MoveTo`, writes WalkSpeed / AutoRotate /
  the face gyro for a FOLLOW soldier, and the only PivotTo (`Reposition`, emergency only: void, > 120 studs for 4 s,
  stuck 10 s far and behind him). Arrival 2.5 / leave 4 studs, reissue only when the goal moved > 2.5 studs, staged stuck
  (re-issue → path → side point → reposition), catch-up by WalkSpeed, snap-free yaw (gyro target starts at the
  current yaw and turns ≤ 240°/s).
* `Server/Modules/ArmyController.luau`: one FOLLOW controller per army at 0.2 s (state FOLLOW/HOLD/ATTACK/RETREAT =
  the order; only FOLLOW issues follow goals, other orders keep their SOS code routed through SoldierController). In
  FOLLOW the escort code only shoots/aims (no MoveTo, no side-step, no close-in). Base hold kept (gate cells) without
  the PivotTo turn. Publishes `WE_FormYaw` / `WE_EscSide` so the client lays each unit's escorts out in the formation
  frame (no swinging files).
* U-turns: a unit whose slot has swung more than `WheelStepDeg` (40°) round the anchor runs round the OUTSIDE (a point
  40° further round at the larger radius) instead of cutting through the army and past the owner; a straight line that
  would pass within `OwnerClearStuds` of him goes round him first.

## Checks (tools/checks/codebot_v114_army.py, run by BuyPathStatic and standalone)

Static: MoveTo only in SoldierController (Move / Stop), the one PivotTo = `SoldierController.Reposition`, no root CFrame /
velocity writes in ArmyFollow / ArmyController / FormationController / SquadOrdersService (spawn excluded), collision pairs,
assignment without distance, no `_afFlip` / compaction in Follow3, FOLLOW escort aim-only, Follow3 keys + ranges.
Luau CLI: FormationController over 130 owner steps (walk, sprint turn, stop, about-turn, ±10° zig-zag, backing up,
circle) with a death + recruit: survivors keep their index, recruit fills the hole, cells ≥ 5.5 apart, ≥ 6.2 from
the anchor, turn ≤ 20° per 0.2 s tick, no flip, zig-zag / backing up do not rotate it. Drive sim (8 mock soldiers, 20 Hz
physics, 24 s): 0 PivotTo, ≤ 3 MoveTo / unit / s, settle ≤ 3.1 studs from own slot, ≥ 4 studs apart marching, ≥ 1.8
through the U-turn, ≥ 4.4 from him, 0 MoveTo at rest.
