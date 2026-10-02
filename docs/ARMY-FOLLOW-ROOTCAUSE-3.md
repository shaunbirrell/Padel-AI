# ARMY FOLLOW ROOT CAUSE 3 (v115, Code Bot Roblox, 2026-09-29)

This follows up the owner's phone test of v114 (place 112). It was NOT fixed. His 9 s clip while walking and turning showed:
- **0.5 s:** the formation opens sideways.
- **1.0 s:** the army is a near-horizontal line.
- **1.5 s:** it splits into two groups, one on each side of him.
- **2.0 s:** a long diagonal "train".
- **2.5–4 s:** columns replace rows.
- **4.5–5.5 s:** an arc / U around him, with soldiers coming in from left and right (orbiting).
- **6–8 s:** once he settles, it reforms into neat rows.

His conclusion was right: **the target geometry itself was unstable while he moved or turned; walking speed was not the cause.**

## The chain, traced (the 15 points)

| # | Question | Answer (file / function) |
|---|---|---|
| 1 | Soldier creation | `SquadOrdersService.spawnUnit` builds the R6 model. It sets `OwnerUserId`/`SquadSlot` attributes, parents it to `Workspace.WarEmpireSquads`, puts every part in the `ArmyNPCs` group and calls `SetNetworkOwner(nil)` (server-owned). The spawn spot comes from `spawnCFrame`, which uses `ArmyController.SpawnOffset(slot)` (now `FormationController.SpawnOffset`: a cell in the block behind him). |
| 2 | The soldier list | `st.Units` (an array, per player, in SquadOrdersService). ArmyController builds `living` from it with `ipairs` each tick. |
| 3 | Slot ID assignment | `FormationController.Assign` is permanent. A unit keeps its index for life. A new unit takes its `SquadSlot` if free, else the lowest free index. A gone unit frees its index. It never uses distance. `pairs()` is used only to free gone units, which is order-independent. v115 publishes it as the `FormationSlot` (+ `WE_FormSlot`) attribute and WARNs on every change. |
| 4 | Offset creation | **v114:** `FormationController.SlotLocal`: odd slots LEFT, even RIGHT, `LateralStuds` 6 to his SIDE, `FrontBack` -1.5 (level with / ahead of him), one row per pair. Escorts were laid out by the client (`RigAnimator.layoutEscorts`, `WE_EscSide`) `ColSpacing` 5.5 **further out in the same row**. **v115:** `FormationController.Layout`: a block of columns across (2..ColumnsMax 4, even, from sqrt(figures)) and rows back. Escorts get their own cells in the rows directly behind their unit (same column). The local offset (column x, row) of a slot is constant. |
| 5 | World slot calculation | **v114:** `SlotWorld(anchor, lat, back)` = anchor position + heading-rotated offset. The anchor sat ON him (his position + a lead). **v115:** `RowFrame(row):PointToWorldSpace(Vector3.new(x, 0, 0))`. Each row's frame sits on his breadcrumb trail `FirstRowStuds + row × RowSpacing` of path behind him. |
| 6 | Heading source | **v114:** `FormationController.Step`: a smoothed velocity / LookVector blend, rate-limited to 100°/s around the anchor ON him. **v115:** per row, the trail tangent (his movement direction) at that row's arc length, rate-limited (`RowTurnDegPerSec` 100), deadband 8° with hysteresis, and only while he moves (`MovingOnSpeed` 3 / `MovingOffSpeed` 1.5). |
| 7 | Update rate of heading / destinations | Every `Follow3.UpdateSeconds` = 0.2 s (one `task.spawn` loop in `ArmyController.Start`). |
| 8 | How often MoveTo fires | `SoldierController.Drive` → `Move` only when the target moved > `ReissueStuds` 2.5, or `RefreshSeconds` 6 passed, or the state changed. The sim measures 2.2–5 per soldier per second (the cap is 5). |
| 9 | Pathfinding | Not used for formation moves. `SoldierController.requestPath` is the stuck fallback only (staged: reissue → path → side point → reposition). ArmyFollow's `CreatePath` is the v113 path (kill switch). |
| 10 | Does catch-up change the destination? | No. v115 catch-up only raises WalkSpeed toward the soldier's OWN slot, with hysteresis (`CatchUpStartStuds` 6 on / `CatchUpEndStuds` 3 off). It never targets the player. |
| 11 | Recovery teleports | `SoldierController.Reposition` is the only `PivotTo` on a soldier. It runs only for void / far for seconds (`FarStuds` 120) / stuck ≥ `StuckRepositionSeconds` and out of his view. v115 WARN-logs each one: unit, slot, reason, previous state, distance to slot, distance to player, jump. The v113 `recoverUnit` path (SquadOrdersService) is behind the kill switch. |
| 12 | Multiple loops | In FOLLOW there is one controller: the ArmyController 0.2 s loop. The SquadOrdersService think loop (`OrdersConfig.ThinkInterval`) only shoots and aims in Follow3 FOLLOW (`escortAimOnly`, then return). HOLD / ATTACK / RETREAT goals come from SquadOrdersService, also via SoldierController. There are no Heartbeat / Stepped / RenderStepped / TweenService uses on units. |
| 13 | Collisions | `ArmyNPCs × ArmyNPCs = false`, `ArmyNPCs × WE_PlayerChars = false` (Follow3), `ArmyNPCs × Default = true`. ArmyController re-audits groups every `AuditSeconds`. Unchanged. |
| 14 | Network ownership | `SetNetworkOwner(nil)` at spawn (server-owned physics). Unchanged. |
| 15 | Client escort figures | `RigAnimator` clones escort figures client-side (a LOD budget of MaxPerClient 22 can drop and rebuild them). Their index is stable (`escLayout[rec].Index`, set from `#e.Escorts + 1`, iterated with `ipairs`, never `pairs`). **v114** placed them in a side row (`WE_EscSide`), which were **wings**. **v115** places escort i at i × RowSpacing of path behind its unit along the unit's OWN walked path (`escTrailStep`), which matches the server's escort cells in the rows directly behind it. |

### Grep results (Follow chain: SoldierController, ArmyController, ArmyFollow, SquadOrdersService, FormationController, RigAnimator, ArmyDebugClient)

| Pattern | Hits |
|---|---|
| `:MoveTo(` | SoldierController.Move / Stop only (lines 90, 99) |
| `MoveToFinished` | none |
| `PivotTo(` | SoldierController.Reposition only (238). GateDefenseService 759 is a gate turret, not a soldier. |
| `CFrame =` | gyro targets only (SoldierController 153/178/189, ArmyFollow 328/908, SquadOrdersService 1294/2542). SquadOrdersService 779/790/859 are model construction in spawnUnit. |
| `Position =` | none on soldiers outside spawn |
| `SetPrimaryPartCFrame` | none |
| `AssemblyLinearVelocity` / `AssemblyAngularVelocity` | zeroed only after a Reposition (SoldierController 239/240). Read-only elsewhere (his root: ArmyController, SquadOrdersService 1031). |
| `PathfindingService` / `CreatePath` / `ComputeAsync` | SoldierController.requestPath (stuck fallback), ArmyFollow (v113) |
| `WalkToPoint` / `WalkToPart` | none |
| `TweenService` | none |
| `Heartbeat` / `Stepped` / `RenderStepped` touching units | none (0.2 s task loop) |
| `Destroy` / `Clone` | SquadOrdersService 326/911 (death / dismiss), 3092/3111 (billboards). RigAnimator 163 (client escorts). The controllers never destroy or clone. |
| `pairs()` for slot order | none. `FormationController.Assign` uses `pairs` only to free gone units. Escort figure index uses `ipairs` with a stable index. |

## ROOT CAUSES

**ROOT CAUSE #1: the v114 "Flank" layout was built from wings.**
`src/ReplicatedStorage/Shared/Util/FormationController.luau` → `FormationController.SlotLocal` (v114) put every unit `LateralStuds` = 6 studs to his SIDE, alternating left/right, in rows of two, starting `FrontBack` = -1.5 (level with him). `RigAnimator.layoutEscorts` (client) then placed each unit's escorts `ColSpacing` 5.5 studs FURTHER OUT in the same row. With 5 units and 6 escorts, that is a line about 30 studs wide, split into a left and a right group with him in the gap. That is exactly "opens sideways / stretches horizontally / splits into two groups with a big gap".

**ROOT CAUSE #2: the formation heading rotated around an anchor that sat on him.**
`FormationController.Step` (v114) kept one heading for the whole formation and rotated it (at up to 100°/s) about an anchor at his position plus a lead. Every cell is anchor + R(heading) × offset. So on a turn, the outer and rear cells sweep circular arcs whose speed is (distance from him) × turn rate. At 15–25 studs out and 100°/s, that is 26–44 studs/s sideways, faster than a 14–16 WalkSpeed soldier can follow. Soldiers lag behind the sweeping cells and string out into a diagonal "train", and columns replace rows while the cells rotate under them.

**ROOT CAUSE #3: the "wheel" made units orbit him.**
`src/ServerScriptService/Server/Modules/SoldierController.luau` → `SoldierController.Drive` (v114 `ctx.Pivot` block, `WheelStepDeg` 40). When a unit's slot swung round the anchor (U-turns, sharp turns), the unit was sent round the OUTSIDE on an arc about the anchor. That arc was centred on him, which is the orbit / U with soldiers coming in from left and right at 4.5–5.5 s.

*It settles at 6–8 s because once he stops, the heading stops rotating and every cell stands still: the geometry, not the soldiers, was the problem.*

## The v115 architecture ("TrailBlock"): the FORMATION follows him, soldiers follow slots

- **Breadcrumb trail** (`FormationController.TrailStep`): crumbs every `CrumbStuds` 1 from his smoothed position (`TrailSmoothSeconds` 0.4). Nothing is added while he stands. `TrailKeepStuds` 90. A fresh trail (spawn / teleport / FOLLOW restart) runs straight back from him along his facing.
- **Rows on the trail** (`RowArc`, `RowFrame`): row r sits `FirstRowStuds` 7 + r × `RowSpacing` 4.5 of PATH behind him. Its heading is the trail tangent there (his movement direction, not his look vector), rate-limited to `RowTurnDegPerSec` 100, with a deadband of `RowDeadbandDeg` 8 and hysteresis, updated only while he moves. On a 90° turn the block walks round the corner behind him row by row. On a circle it follows the circle and does not become a ring.
- **About-turn fold** (`FoldDeg` 120): when a row's path doubles back, that row's heading is exactly reversed and its x mirrored (`RowFlip`), so every cell keeps its world spot and its side of his path. The rows then walk up his old path, turn where he turned, and follow him back. There is no 180° sweep and no side swap in front of him. Rows he walks back into part to let him through (`FormationController.Part`, column order kept). A unit standing in his walking lane steps out to its OWN side (`SoldierController.Drive` lane yield) and never crosses his path.
- **Block layout** (`Layout`, `Columns`, `ColumnX`): even columns (2..`ColumnsMax` 4) at `ColSpacing` 5 with an `AisleStuds` 7 aisle down his own path. There are no side wings. Escorts get cells in the rows directly behind their unit.
- **Constant local offsets.** Slot assignment is permanent (`Assign`, the `FormationSlot` attribute). World target = `RowFrame:PointToWorldSpace(offset)`.
- **When he stops**, heading and anchor are kept: nothing re-forms.
- **Per soldier** (`SoldierController.Drive`):
  - Pace = its OWN slot's smoothed speed. The target is the slot plus the slot's velocity × `MoveLeadSeconds` 0.25 (capped at 4).
  - Speed is signed along the row heading (behind the slot = faster, ahead = slower) plus lateral error, capped at `CatchUpMaxMult` × pace / `MaxSpeed`.
  - Catch-up has hysteresis (6 on / 3 off).
  - MoveTo fires only on a moved target (> 2.5), a state change, or every 6 s.
  - Arrival deadzone `ArriveStuds` 2.5 / `LeaveStuds` 4 while he stands.
  - The wheel is gone.
- **Kill switch:** `Follow3.Enabled = false` (or `Rollout` not "all"/"owner") returns to the v113 ArmyFollow path. The no-despawn guarantees of v113/v114 are unchanged (the controllers never Destroy or Clone).

## Instrumentation (owner-only, toggleable)

- `ArmyConfig.Follow3.Debug = true`, `DebugUserIds = {470626172}`. At join, the owner's `WE_ArmyDebug` player attribute defaults to true. **`/armydebug`** (admin allowlist; also `/armydebug on|off`) toggles it.
- **Server** (ArmyController, only while debug is on for that player):
  - per unit `WE_SlotPos` (its world slot, when it moved > 0.5) and `WE_MoveState`
  - a per-soldier log line every `DebugLogSeconds` 2: id, slot, row, position, target, distance, distance to player, WalkSpeed, mode, time since its last MoveTo, catch-up, recovery stage, pathfinding, stuck timer
- **Always logged:**
  - WARN on every slot change: `SLOT CHANGE unit old -> new reason` (roster change / death / removal); first assignments are printed
  - WARN on every layout change: `LAYOUT CHANGE cols x rows`
  - WARN on every reposition (PivotTo): `REPOSITION unit slot reason prevState distToSlot distToPlayer jump`
- **Client** (`Client/Modules/ArmyDebugClient`, created locally, so only he sees it), 5 Hz:
  - a neon disc (anchored, CanCollide / CanQuery / CanTouch off) at each of HIS units' current slot
  - a thin line from soldier to slot: green ≤ 2.5 studs, yellow ≤ 6, red beyond
  - a label over the soldier: `S07 / Slot 07` plus the move state and distance to its slot
  - everything is destroyed when debug turns off
  - escort cells have no separate markers (escorts are client figures that follow their unit's path)

## Acceptance simulation (`tools/sim/`)

`tools/sim/army_follow_sim.luau` runs the REAL `FormationController` and `SoldierController` sources with the live `ArmyConfig.Follow3` values in the Luau CLI. It models:
- the whole chain: trail, rows, cells, lead, SoldierController.Drive, MoveTo
- humanoid walkers: velocity toward the MoveTo point at WalkSpeed, 80 studs/s² accel limit, facing turn 720°/s, never overshooting

The player walks at 16 studs/s and soldiers start at WalkSpeed 14. It runs 10 owner tests: straight 30 s, 90° left, 90° right, circle r20, figure-eight r18, rapid left/right, 180° turn (0.15 s reversal), stop, repeated start/stop, and max army (8 units + 12 escorts = 20 figures, from OrdersConfig.MaxFieldUnits 5 + 3 research and RigConfig.Escort MaxPerArmy 12). Metrics are measured per tick for slots AND soldiers. Thresholds are in the sim and fail the build (`tools/checks/codebot_v115_army.py`):

- **Slots and teleports:** slot changes = 0; teleports = 0.
- **Formation RMS error** (soldier position in its row frame vs its offset):
  - mean while moving: ≤ 2.5 (≤ 3.25 for startStop / rapidLR, where every start or reversal costs one 0.2 s tick plus acceleration of lag; ≤ 3.5 for u180 / maxArmy)
  - worst tick: ≤ 6 (12 for the about-turns)
  - settled at the end: ≤ 3
- **Rows:**
  - no rank wider than 1.5× its design width
  - rank order kept across and along the block (rankViol = 0). On the about-turns, a unit stepping out of his lane for 1 s is counted separately (rankYield); that count must be 0 on every other test.
  - no two soldier paths cross
- **Distance from him:**
  - min soldier-to-player ≥ 3 (≥ 2 on the about-turns, where the rows pass back down his old path by design)
  - every slot ≥ FirstRow - 1.5 from him
  - no slot in front of him off his path (orbit = 0)
  - no slot ahead of him during turns (not applicable to the about-turns)
- **Speeds and rates:**
  - max slot speed ≤ 0.8 × MaxSpeed (slots never outrun a soldier)
  - MoveTo ≤ 5 per soldier per second
  - rows turn ≤ 100°/s

Results (v115 shipped values, 154 PASS / 0 FAIL):

| test | slotChanges | teleports | rmsMean | rmsMax | finalRms | widthRatio | rankViol | rankYield | crossings | minOwner | minOwnerSlot | orbit | maxSlotSpeed | movesPerSec | maxRowTurn | result |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| straight | 0 | 0 | 0.52 | 4.46 | 1 | 1 | 0 | 0 | 0 | 7.11 | 7.83 | 0 | 16 | 5 | 0 | PASS |
| left90 | 0 | 0 | 1.39 | 4.46 | 0.84 | 1.03 | 0 | 0 | 0 | 4.54 | 6.75 | 0 | 29.8 | 3.87 | 100 | PASS |
| right90 | 0 | 0 | 1.33 | 4.46 | 0.9 | 1.03 | 0 | 0 | 0 | 4.54 | 6.75 | 0 | 29.8 | 3.9 | 100 | PASS |
| circle | 0 | 0 | 1.66 | 4.46 | 1.39 | 1.04 | 0 | 0 | 0 | 5.56 | 7.26 | 0 | 26.7 | 3.82 | 77 | PASS |
| figure8 | 0 | 0 | 2.14 | 4.46 | 1.3 | 1.04 | 0 | 0 | 0 | 5.35 | 7.33 | 0 | 25.7 | 4.01 | 81 | PASS |
| rapidLR | 0 | 0 | 2.71 | 4.46 | 1.62 | 1.02 | 0 | 0 | 0 | 4.73 | 6.91 | 0 | 29.4 | 3.25 | 100 | PASS |
| u180 | 0 | 0 | 1.67 | 6.57 | 2.52 | 1.03 | 0 | 0 | 0 | 2.45 | 2.65 | 0 | 24.1 | 3.97 | 100 | PASS |
| stop | 0 | 0 | 1.37 | 4.46 | 2.27 | 1 | 0 | 0 | 0 | 5.97 | 7.83 | 0 | 16 | 2.21 | 0 | PASS |
| startStop | 0 | 0 | 3.04 | 4.96 | 0.68 | 1 | 0 | 0 | 0 | 5.24 | 7.83 | 0 | 16 | 3.08 | 0 | PASS |
| maxArmy | 0 | 0 | 2.34 | 7.05 | 2.99 | 1.17 | 0 | 2 | 0 | 2.92 | 2.14 | 0 | 30.6 | 3.86 | 100 | PASS |

PASS lines: 154 FAIL lines: 0

- The worst-tick RMS of 4.46 in every test is the first tick after the 1 s start-up (soldiers spawned from the start grid join their trail cells).
- u180 and maxArmy are the weakest cases: an about-turn right after a curve brings a soldier to about 2.5–2.9 studs of him as the rows pass back down his old path. Earlier tunings (TrailSmoothSeconds 0.5) got as close as 0.5 studs in maxArmy, so this case is sensitive to tuning.

**Plots** (top-down, player path, slot traces, soldier traces, snapshots): `/workspace/army-sim/circle.png`, `figure8.png`, `u180.png`, `left90.png`, `maxArmy.png`. Regenerate with `/workspace/army-sim/venv/bin/python tools/sim/plot_army_sim.py /workspace/army-sim`.

## Not verified / limits

- The sim is not Roblox physics. It has no collisions, terrain, stairs, doors, network latency, humanoid stepping or real Pathfinding. A Roblox-accurate headless run is not possible here (no Studio / RCC on the box).
- ArmyController itself was smoke-run in the Luau CLI with mocked Roblox services (slots published, debug on/off, death → SLOT CHANGE warn). The client overlay (ArmyDebugClient) and the escort trail (RigAnimator) compile and pass static checks, but were not run.
- Because the block is now behind him, the camera guard may hide more rear escort figures on a phone (the camera looks over the rows).
