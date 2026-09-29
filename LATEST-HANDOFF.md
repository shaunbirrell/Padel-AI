# v96 — 2026-09-29 ~09:15 Dublin (Code Bot, branch phase-7-polish, WE_Build 96)

**Claude: do not redo / undo these.** Code Bot merged `origin/claude/desktop-bud` tip `a063154` (83a98b9..a063154) onto phase-7-polish and published.

- **Army gate-hold fix** (`ArmyConfig.Follow2.Tidy`, owner-only): after Shaun's v95 phone test — hold BEFORE the gate (no path through, no stuck/far teleport while outside); validated hold grid (raycast + overlap; bad cells skipped outward); per-seat ATTACK march rows / target ring (no stacking). Kill switch `Follow2.Tidy.Rollout = "off"`.
- **JOB 5a Robux-only vehicles** (owner-only via `MonetizationConfig.RolloutKeys`): six Premium clones — Skylance jet, Stormwing heli, Leviathan + Tidebreaker boats, Warlord tank, Razorfang buggy. Pass Ids still **0 / TODO owner** (Garage gold ROBUX rows; owner can spawn via auto-grant). Cash purchase refused (`RobuxOnly`). Free respawn for pass owners.
- Pins: `tools/checks/claude_bud_army.py`, `claude_bud_money.py`, `claude_bud_monetization.py`, `codebot_v96.py`. PreferMesh stays OFF. WE_Building* untouched.
- **Still open on Bud:** JOB 5b+ monetisation (VIP chat tag + VIP area, Bigger Army pass, Extra Garage slot; then 5c/5d/5e + Creator Hub list). Claude tip was fresh at merge — may still be coding.
- **Publish note for Shaun:** use **"Migrate to Latest Update"** (or shut down old servers) so the army fix + Robux vehicle Garage rows appear.

**Phone tests for Shaun:**
- Army fix (8+ soldiers, owner): walk into your base — nobody crosses the gate; two neat blocks outside facing out; none inside walls/props. Walk out: rejoin wedge. ATTACK in the open: rows in front; near an enemy: ring (no stacking into 2). Kill switch `ArmyConfig.Follow2.Tidy.Rollout = "off"`.
- Robux vehicles (owner): Garage shows gold **ROBUX** rows for the six Premium vehicles; spawn via owner auto-grant (pass Ids still 0). A second account should not see the rollout. Once Creator Hub Ids are pasted, Shop/Garage prompts work for pass buyers.
- Migrate to Latest Update (or shut down old servers) before testing.

---

# v95 — 2026-09-29 ~08:50 Dublin (Code Bot, branch phase-7-polish, WE_Build 95)

**Claude: do not redo / undo these.** Code Bot merged `origin/claude/desktop-bud` tip `3355267` (aaa87f3..3355267) onto phase-7-polish and published.

- **JOB 2 army tidy** (`ArmyConfig.Follow2.Tidy`, owner-only): army holds in neat rows outside the main gate (never enters plot); fixed seats; no column-crossing on turn; 8 s no-teleport run-back after leaving base.
- **JOB 3 WorldFill** (`WorldFillConfig.Enabled`, everyone): connector roads P1/P2/P5/P6→plaza, 2 dock bridges, 6 army positions, 4 plaza posts, terrain rocks under `Workspace.WorldFill` (planned ~388 Full / ~198 Low).
- **JOB 4.1 airdrop** (`SupplyDropConfig.Airdrop`, owner-only): parachute drop every 10 min + marker; claim for cash.
- **JOB 4.2 daily streak** (`DailyRewardConfig.AutoClaim`, owner-only): auto-claim ~8 s after join + next-day toast.
- **JOB 4.3 plaza bounty** (`PlazaBountyConfig`, owner-only): timed $15k for retaking Central Plaza within 3 min.
- **JOB 4.4 Army Upgrades** (`ArmyUpgradeConfig`, owner-only): Barracks world prompt opens Research → Soldiers.
- Pins: `tools/checks/claude_bud_army.py`, `claude_bud_worldfill.py`, `claude_bud_features.py`, `codebot_v95.py`. PreferMesh stays OFF. WE_Building* untouched.
- **Still open on Bud:** JOB 5 monetisation (Claude tip was fresh at merge — may still be coding).
- **Publish note for Shaun:** use **"Migrate to Latest Update"** (or shut down old servers) so WorldFill + owner-only JOB2/4 appear.

**Phone tests for Shaun:**
- Army fix (8+ soldiers): walk into your base; nobody crosses the gate, and they file into two neat blocks outside, facing out,
  none inside walls or props. Walk out: they rejoin the wedge. Press ATTACK in the open: they spread into rows in front of you;
  near an enemy they spread round it (no stacking into 2). (from Claude Bud handoff)
- JOB 4: wait ~1 min for first airdrop (marker + toast; stand by crate 2 s). ~8 s after join: login streak toast. Capture plaza with a second account, retake within 3 min: +$15,000. At Barracks tap "Army Upgrades" → Research Soldiers.
- Map fill: drive side gates P1/P2/P5/P6 — road to plaza; sandbag/watchtower positions; west dock bridge (boats under). Check mid-phone FPS. Server log `WorldFill: quality=full parts=N skipped=M`.
- Army (owner): walk/drive into base with 8+ soldiers — they stop outside gate in two blocks facing out. Walk out: wedge without teleport. Turn in place: no crossing. Kill switch `ArmyConfig.Follow2.Tidy.Rollout = "off"`.

---

# WHERE I STOPPED — 2026-09-29 (Claude on Bud, branch claude/desktop-bud, rebased on v95 phase-7-polish)

**All jobs are done and pushed:** Robux 3 products · runway · guards · JOB 2 army (+ the v95 army fix) · JOB 3 map fill ·
JOB 4 (airdrop, daily streak, plaza bounty, army upgrades) · JOB 5 monetisation (5a–5e). Nothing is half-done.
Every new gameplay item is owner-only (Rollout "owner") behind its own flag; OFF = the old game.

**Gates on this Windows PC:**
- `python` is the Store alias; use `C:/Users/shaun/AppData/Local/Programs/Python/Python312/python.exe` with PYTHONIOENCODING=utf-8
  and a forward-slash path wrapper (4 frozen pins compare POSIX paths).
- luau-compile and luau-lsp are in the session scratchpad.
- Last run: BuyPathStatic PASS=5209 FAIL=0 (parse gate on), rojo build ok, luau-lsp no new errors.
- The headless world sim and the DataService harness are not in the repo, so they were NOT run.

## Owner must create on Creator Hub
Paste each Id with `tools/wire-monetization-ids.py`. Every item stays hidden and prompts nothing while its Id is 0. Then set
`MonetizationConfig.Rollout = "all"` (and the other owner-only Rollouts) when you're happy on your account.

| Name | Type | Suggested R$ | Config key | One line |
|---|---|---|---|---|
| Skylance Interceptor | Game pass | 899 | GamePasses.PV_Skylance | Robux-only interceptor jet, a bit faster/tougher than the best cash jet |
| Stormwing Gunship | Game pass | 999 | GamePasses.PV_Stormwing | Robux-only attack helicopter |
| Leviathan Dreadnought | Game pass | 1199 | GamePasses.PV_Leviathan | Robux-only capital ship |
| Tidebreaker Assault Boat | Game pass | 299 | GamePasses.PV_Tidebreaker | Robux-only fast attack boat |
| Warlord Siege Tank | Game pass | 799 | GamePasses.PV_Warlord | Robux-only heavy tank |
| Razorfang GT Interceptor | Game pass | 199 | GamePasses.PV_Razorfang | Robux-only fast buggy |
| Bigger Army | Game pass | 249 | GamePasses.BiggerArmy | +10 soldiers in your army, forever |
| Instant Army Refill | Developer product | 49 | DevProducts.SoldierRefill | Fill your army to its cap right now |
| Plaza Airstrike | Developer product | 79 | DevProducts.PlazaAirstrike | One airstrike on the Central Plaza (3 s warning, never lethal) |
| (not yet) Extra Garage Slot | Game pass | 199 | GamePasses.ExtraGarageSlot | DON'T create yet: a second active vehicle is not built (hidden) |

Also: set `MonetizationConfig.Retention.GroupId` to your Roblox group id (0 hides the group-reward row).
All Robux prices live in one table: `MonetizationConfig` (RobuxPrice).
Already live and unchanged: VIP, 2x Cash, Double XP, Auto Collect, Speed Pass, cash packs x4, gold packs, Battle Pass Premium,
Army Expansion, Speed Boost, Golden Pumpjacks, Commander Starter Pack, Keep-Base Rebirth.

**Open dev tasks (not done, on purpose):**
- Extra Garage Slot: needs multi-active vehicles in VehicleService.
- Ground/naval vehicle weapons: they don't exist, so the premium tanks and boats are armour/HP/speed only.
- VIP stays at +25 % cash (not cut to the requested +10 %: live buyers paid for 25 %).
- "Skip build timer" was not added: upgrades are instant.

**Phone tests for Shaun (owner account; a second account must see none of the owner-only items):**
- **Army (v95 fix):** walk into your base with 8+ soldiers. Nobody crosses the gate, and there are two neat blocks outside facing out.
  ATTACK: rows in front of you, then a ring round an enemy (no stacking).
- **5a:** the Garage shows 6 gold "ROBUX · R$" rows. Tapping one says "coming soon" until its Id is pasted. You can already spawn
  them (owner auto-grant).
- **5b:** your chat shows the [VIP] tag if you own VIP. The VIP lounge is just north of the Town: its door lets you through, and 2 s
  on the gold pad pays $5,000 (once per 15 min).
- **5c/5d (after the Ids exist):**
  - the AIRSTRIKE button near the plaza;
  - the army-refill offer after your squad is wiped;
  - the 2x Cash / cash offer after a rebirth;
  - the cash-pack offer when a vehicle is too expensive.
- **5e:** the Shop's Robux tab starts with FREE rows (Daily Reward CLAIM, Airdrop TRACK, Favorite). With Roblox Premium you get
  +$2,500 on the first join of the day.
- **Earlier jobs** (runway, guards, map fill, JOB 4): see the sections below and ASSUMPTIONS.md.

---

# v94 — 2026-09-29 ~08:20 Dublin (Code Bot, branch phase-7-polish, WE_Build 94)

**Claude: do not redo guards fight-back / bag LOS / NPC unstick.** Merged `origin/claude/desktop-bud` (18df075) into phase-7-polish and published as WE_Build 94.

- **Guards fight back (owner-only):** `CombatConfig.GuardsFightBack` Rollout owner. A plain NPC shot by a squad unit fights that unit back (LOS, reaction, FireRate, HitChance) while no player is in range. Shooter handed via `CombatService.SetUnitShooter` (frozen squadfair pins untouched).
- **NPC unstick (owner-only):** `CombatConfig.NpcUnstick` — chase with no progress in 1.5 s jumps and sidesteps (bank planters G1/G2).
- **Bag pickup LOS (owner-only):** `OpsConfig.Cargo.PickupLosRollout` — server line of sight on bag pickup (CP-9 E4).
- **Pins:** `tools/checks/claude_bud_guards.py`; WE_Build pins bumped 93→94 (`tools/checks/codebot_v94.py`). PreferMesh stays OFF.
- Kept: v81 admin unlocks, v85 FollowPace (non-ArmyFollow), v90 jets/runway/harbor/faces/air-fix2, v91 helis + ArmyFollow, v92 plaza capture, v93 Robux + runway layout-sig.

**Still open for Claude (Bud queue):** JOB 2 army gate/formation, JOB 3 fill the map, JOB 4 features, JOB 5 monetisation.
**Still in `handoff/wip/`:** 03 (+03b) army lane B, 04 (+04b) army lane A, 07 ground2 records, 09-12 VKIT.

**Phone tests for Shaun:**
- Guards (owner account): take the army to the Empire Bank and ATTACK the guards while you stand more than 90 studs away. Guards shoot your soldiers (tracers, soldiers lose HP). Walk in front of the hall so G1/G2 chase you past the planters: they hop or step around them instead of sticking. A second account should see the old guard behaviour.
- Migrate to Latest Update (or shut down old servers) before testing.

---

# v93 — 2026-09-29 ~00:29 Dublin (Code Bot, branch phase-7-polish, WE_Build 93)

**Claude: do not redo Robux products or the runway layout-sig fix.** Merged `origin/claude/desktop-bud` (72c2b12 + d9c2b77) into phase-7-polish and published as WE_Build 93.

- **3 Robux products (owner-only):** Speed Pass game pass 1998656357, Keep-Base Rebirth 3714663721, Golden Pumpjacks 3714663783.
  `MonetizationConfig.Rollout = "owner"` + `RolloutKeys` + `SkuLiveFor`. Shop/prompts/pads gated per player; **ProcessReceipt is never gated**.
  Golden Pumpjacks: gold pumps pay `IncomeMult` 1.5 (+50% Pending cash). World ATM pads skip gated keys until Rollout = "all".
- **Runway layout-sig rebuild:** `MapSetup.LAYOUT_SIG` / `WE_LayoutSig` in MapSetup + Bootstrap rebuilds a saved pre-v90 map so the runway is 190×29 and hangar 68×40 (v90 sizes). Check: `tools/checks/claude_bud_runway.py`. PreferMesh stays OFF.
- **Pins:** `tools/checks/claude_bud_monetization.py` + `tools/checks/claude_bud_runway.py`; WE_Build pins bumped 92→93.
- Kept: v81 admin unlocks, v85 FollowPace (non-ArmyFollow), v90 jets/runway/harbor/faces/air-fix2, v91 helis + ArmyFollow, v92 plaza capture.

**Still open for Claude (Bud queue after v94):** JOB 2 army gate/formation, JOB 3 fill the map, JOB 4 features, JOB 5 monetisation.
**Still in `handoff/wip/`:** 03 (+03b) army lane B, 04 (+04b) army lane A, 07 ground2 records, 09-12 VKIT.

**Phone tests for Shaun (from Claude Bud handoff):**
- Robux (owner account only): Shop shows Speed Pass (5 R$) and Golden Pumpjacks (49 R$); Speed Pass makes you faster and the army keeps up; Rebirth panel shows KEEP BASE R$ 50; Golden Pumpjacks turns pumps gold with ~+50% Pending cash per tick. A second account sees none of these.
- Runway: join a NEW server ("Migrate to Latest Update" first). Runway from west plot wall almost to helipad lane (190 long, 29 wide, dashes all the way). Jet spawns at west end and takes off along the whole strip. Hangar is not inside any building.

---

# WHERE I STOPPED — 2026-09-28 (Claude on Bud, branch claude/desktop-bud)

Queue (owner's order): [x] Robux 3 products · [x] runway · [x] guards (fight back, bag LOS, unstick G1/G2) · [x] new JOB 2 army
gate/formation · [x] JOB 3 fill the map · [x] JOB 4 features (supply drops, daily reward, plaza bounty, army upgrades) · [ ] JOB 5 monetisation (5a Robux vehicles DONE; next 5b passes: VIP chat tag + VIP area, Bigger Army pass, Extra Garage slot; then 5c, 5d, 5e, then the Creator Hub list).

**Done, pushed:**
- (rebased on v95 phase-7-polish) ARMY FIX after the owner's v95 test: the army holds before the gate (no path through it, no teleport),
  validated clean hold grid facing out, ATTACK gives every soldier its own spot (march rows / target ring). Kill switch `Follow2.Tidy.Rollout = "off"`.
- 5a: six Robux-only vehicles (Skylance jet, Stormwing heli, Leviathan + Tidebreaker boats, Warlord tank, Razorfang buggy),
  own passes (Ids 0: TODO owner), about +5 % over the best cash vehicle, owner-only, gold ROBUX rows in the Garage.
- Robux: Speed Pass 1998656357, Keep-Base 3714663721 and Golden Pumpjacks 3714663783, owner-only (`MonetizationConfig.Rollout = "owner"`).
- JOB 4 (each owner-only, own flag): parachute **airdrop** every 10 min with marker (`SupplyDropConfig.Airdrop`); **daily streak**
  auto-claimed on join (`DailyRewardConfig.AutoClaim`); **plaza bounty** $15k for retaking the plaza within 3 min (`PlazaBountyConfig`);
  **Army Upgrades** prompt at your Barracks, which opens the Soldiers research (`ArmyUpgradeConfig`). Check: `tools/checks/claude_bud_features.py`.
- Map fill (everyone, kill switch `WorldFillConfig.Enabled`): **planned parts Full 388 / Low 198** in `Workspace.WorldFill`
  (world total about 2,864 / 1,877 against caps 2,900 / 1,900): 4 connector roads to the plaza, 2 bridges over dock channels,
  6 army positions between the bases, 4 light plaza posts, terrain rocks. Check: `tools/checks/claude_bud_worldfill.py`.
- Army (owner-only, `ArmyConfig.Follow2.Tidy`): the army stops in neat rows outside your main gate facing out and never enters your plot;
  fixed seats in the wedge, no crossing when you turn; after you leave the base they run back into the wedge (no teleport for 8 s).
  Check: `tools/checks/claude_bud_army.py`.
- Guards (owner-only): bank/camp NPCs shoot back at squad units that shot them; chasing NPCs jump and sidestep when stuck (G1/G2 planters);
  Ops bag pickup needs line of sight. Flags: `CombatConfig.GuardsFightBack` / `NpcUnstick`, `OpsConfig.Cargo.PickupLosRollout`. Check: `tools/checks/claude_bud_guards.py`.
- Runway: a saved pre-v90 map is now rebuilt (`WE_LayoutSig` layout hash in MapSetup + Bootstrap). Check: `tools/checks/claude_bud_runway.py`.

**How to run the gates on this Windows PC:**
- `python` is the Store alias; use `C:\Users\shaun\AppData\Local\Programs\Python\Python312\python.exe`.
- BuyPathStatic needs `PYTHONIOENCODING=utf-8`, plus a wrapper that makes paths use forward slashes (4 frozen pins compare POSIX paths).
- luau-compile and luau-lsp are in the session scratchpad (not the repo). The headless world sim and the DataService harness are not in the repo, so they were not run.

**Phone tests for Shaun:**
- JOB 4: wait about 1 min after joining for the first airdrop (marker + toast; the crate falls with a canopy, stand by it 2 s for the cash).
  About 8 s after joining you get a login streak toast. Capture the plaza with a second account, then retake it with yours within 3 min: +$15,000.
  At your Barracks, tap "Army Upgrades": the Research panel opens on Soldiers.
- Map fill: drive out of the side gates (P1/P2/P5/P6). A road now runs to the main east-west road and on to the plaza. Visit the
  sandbag/watchtower positions between bases, and drive over the bridge at the west dock channel; boats pass under it. Check the frame rate
  on a mid phone. The server log line `WorldFill: quality=full parts=N skipped=M` gives the real count.
- Army: walk (then drive) into your base with 8+ soldiers. They stop outside the main gate in two neat blocks (left and right of the road),
  facing out, and none come in. Walk out: they fall in behind you in a wedge without popping or teleporting. Turn round on the spot:
  the wedge follows without soldiers running through each other. Kill switch: `ArmyConfig.Follow2.Tidy.Rollout = "off"`.
- Guards (owner account): take the army to the Empire Bank and ATTACK the guards while you stand more than 90 studs away. The guards now shoot
  your soldiers (tracers, soldiers lose HP). Walk in front of the hall so G1/G2 chase you past the planters: they hop or step around them instead of sticking.
- Robux (owner account only): Shop shows Speed Pass (5 R$) and Golden Pumpjacks (49 R$); Speed Pass makes you faster and the army keeps up;
  the Rebirth panel shows KEEP BASE R$ 50; Golden Pumpjacks turns the pumps gold with about +50% Pending cash per tick. A second account sees none of these.
- Runway: join a NEW server ("Migrate to Latest Update" first). The runway runs from the west plot wall almost to the helipad lane
  (190 long, 29 wide, dashes all the way). A jet spawns at the west end and takes off along the whole strip. The hangar is not inside any building.

---

# v92 — 2026-09-28 ~23:50 Dublin (Code Bot, branch phase-7-polish, WE_Build 92)

**Claude: do not redo / undo these.** Code Bot finished the stalled Claude-watch takeover of WIP lane **02 capture**
(`handoff/wip/02-capture_on_e506c9c.patch` on base e506c9c, 3-way merged onto phase-7-polish after v91).

- **PersistClaims = false** (`EconomyConfig.OutpostIncomeBuff`): saved outpost claims are NOT re-planted on join.
- **ReleaseOnLeave = true** (`TerritoryConfig`): a leaver's zones go Neutral at once (Home Outpost still returns on join once taken, F10).
- **StandingBar** on: CAPTURING / CONTESTED / YOURS bar. YOURS is a 5 s cue on the painted disc (`OnDisc`, `HeldSeconds=5`);
  no YOURS on top of the capture toast (`HeldAfterCapture=false`). CONTESTED follows the counted reach (blocker sees it too).
- Capturer's bar only names a zone he is counted inside this tick (CAP-16). Presence changes push to movers only (CAP-19).
- Contested pulse capped at 10 Hz. Finished Neutral contests reset to Neutral.
- **Publish note for Shaun:** use **"Migrate to Latest Update"** (or shut down old servers) so PersistClaims-on v83 servers
  do not re-plant claims during a rolling update (CAP-5 / phone_test step 0).
- Pins: `tools/checks/codebot_v92.py` + the fb4 capture block already in `tools/BuyPathStatic.py`. Assumptions appended
  from `handoff/wip/notes/02-capture/assumptions.md` (CAP-1..CAP-22).
- Kept: v81 admin unlocks, v85 FollowPace (non-ArmyFollow path), v90 jets/runway/harbor/faces/air-fix2, v91 helis + ArmyFollow.

**Still in `handoff/wip/` (not this ship):** 03 (+03b) army lane B, 04 (+04b) army lane A, 07 ground2 records, 09-12 VKIT.

---

# v91 — 2026-09-28 ~23:45 Madrid (Code Bot, branch phase-7-polish, WE_Build 91, place versions 87 + 88)

**Claude: do not redo these.**
- **Helicopters (owner's choice):** every heli key wears the attack heli 11240665977, owner-only like every heli body
  (`Rollout = "Body"`). Each key has its own colour on the body panels only (`HELI_PAINT_PARTS`: BAP 1, Body, Doors,
  Thing for Blades); glass, seats, blades, wheels and engines keep theirs. Built with `heliRef(scale, colour, cabin, note)`.
  - Transport keys get a bigger scale to fit their bigger kit (TransportHeli 0.52, HeavyLiftHeli 0.6, Medevac and LightTransport 0.48;
    the rest 0.45). Seats, after live raycasts on place v87 (the commit after the first v91 publish, place v88):
    - crew at (±4, 5.4, -30): 3.4-4.8 studs under the glass (narrow kits had 2.5 at 6.0);
    - rear pair at (±3.5, 5.0, -21) and the middle seat at (0, 5.0, -25), inside the cabin with hull on both sides.
      The old z -13 rear pair stuck out of the tail.
  - The main Blades spin through the v90 rotor lookup.
  - `BODY_LIGHT_HELI` / `BODY_TRANSPORT_HELI` are kept, unused (a one-line revert).
  - AttackHelicopter keeps its own navy (27,42,53). StealthHeli keeps near-black (20,22,26), a whole-body recolour as in v88.
  - Colours: GunshipHeli gunmetal 74,80,88 · EscortHeli slate blue 78,98,124 · NightAttackHeli dark olive 58,62,40 ·
    LightScoutHeli olive drab 100,108,68 · UtilityHeli khaki 150,138,100 · RescueHeli desert sand 190,168,122 ·
    MedevacHeli light grey 160,164,168 · TransportHeli forest green 54,78,56 · LightTransportHeli sage 118,134,112 ·
    HeavyLiftHeli earth brown 116,92,66. VTOLTransport keeps its own tilt-rotor body.
- **Army FOLLOW overhaul, live for EVERYONE** (`ArmyConfig.Follow2.Rollout = "all"`; set it to `"off"` to go back to the old follow).
  New `Server/Modules/ArmyFollow.luau`; SquadOrdersService hands it FOLLOW movement (`_AFOn`) and keeps the lifecycle
  and shooting. The v85 FollowPace and v90 Fix follow/recover are bypassed while it is on.
  - **What was wrong:** soldiers collided with each other (every HumanoidRootPart collides, all in Default). At a run they
    shoved, tripped (FallingDown/Ragdoll) and got flung. A unit flung under the map lost its root to
    FallenPartsDestroyHeight; for everyone but the owner that unit then stayed in the squad as an invisible ghost forever.
    SyncArmy only culls dead or parentless models, and the v90 re-form was owner-only. That was the "despawn".
    On top of that: no per-unit spacing, catch-up capped at 28 (or the v85 multipliers), and regroup was owner-only and slow.
  - **Now:**
    - wedge slots behind him, turned by his move direction;
    - separation steering, and CollisionGroup `WE_Squad` never collides with itself;
    - trip/ragdoll states off;
    - straight MoveTo while the slot is in sight, pathfinding only when blocked (1.5 s per unit, 8 per server per second,
      path kept while its end is within 8 studs of the slot);
    - catch-up speed = max(his WalkSpeed incl. Speed Pass/Boost, his measured speed) x 1.35 plus 0.6 per stud behind,
      capped at max(owner x 1.8, 34);
    - regroup teleport (one PivotTo to a ground-checked clear spot behind him, never a delete) when: 70 studs from its slot
      for 1 s, stuck 3 s, under the map, or right after he teleports/respawns;
    - a unit that lost its root is re-formed for everyone;
    - every removal, death, root loss and regroup is logged `[ArmyFollow] ...` (rate-limited).
  - **Own base:** while he is inside his own plot square (4 studs in; out again 2 studs past the edge), his units wait spread
    out 12-16 studs outside his main gate, beside the gate lane and never in it. They re-form behind him when he comes out.
  - **Checks:** the Open Cloud session has no physics (GetRealPhysicsFPS 0) and no built map, so the check was a
    kinematic stand-in (units walk to their WalkToPoint at their WalkSpeed). Owner sprinting at 26 for 20 s, turn, stop,
    diagonal, base, exit: 0 units lost, formation within 25 studs while running, 0 units inside the plot during the base
    phase, re-formed after the exit. Real physics and the wait line on the real map need the phone test.
- Pins: `tools/checks/codebot_v91.py`. It retires 3 frozen army-fix pins and 1 v90 pin (the cull/trim now log first, and the
  ArmyFollow branch runs before recoverUnit).

---

# v90 — 2026-09-28 ~22:30 Madrid (Code Bot, branch phase-7-polish, WE_Build 90, place version 86)

**Claude: do not redo these. Shipped from `handoff/wip/` plus the owner's answers to the questions below.**
- **01 army despawn fix**: merged onto HEAD behind the new `ArmyConfig.Rollout.Fix = "owner"`. Only shaunie6's squads use the fix
  (Follow / Recover / Gate-open blocks via `SquadOrdersService._FixLive`, `reformRootless(uid)`, and the GateDefense gate-open
  `LiveFor("Fix")`). For him it replaces v85 FollowPace (`_PaceBegin` returns false); everyone else keeps v85 / 4d26673.
  NOT done: Claude's r1 re-measure (GATECAMP, UNDER, hall with guards down, T3), because it needs the stand-in/phone. Go-live for everyone: `Rollout.Fix = "all"`.
- **05 harbour** (the dock boat and building as a Part kit): live for everyone, kill switch `DockKitConfig.Enabled = false`. Visual only, 0 new assets.
- **06 floating faces**: live for everyone (client-only visual). Switches: `Escort.Camera.GuardHz = 0` / `LeadScreenFrac = 0`.
- **08 air fix-2** (rotor `Under` scope, chase-zoom span, rotor joint not counted as a pin): live. No current ref uses `Under` yet.
- **Owner answers:**
  - **Jets:** StrikeJet, CASJet and StealthStrike (plus the StealthStrikeJet ref) now wear jet 14589101870 with the pilot inside,
    using the FighterJet layout. They stay owner-only (`Rollout = "Body"`), like the v88 bodies they replace. The v88 tables
    `BODY_STRIKE_JET` / `BODY_STEALTH_STRIKE` are kept, unused, so reverting is one line.
  - **Jet colours:** each jet has its own colour on its grey panels only (`BodyColorParts = JET_PAINT_PARTS`). The black trim
    and the glass canopy keep the approved look.
    Palette (RGB):
    - FighterJet: air-superiority grey (118,126,136)
    - InterceptorJet: navy blue-grey (64,82,108)
    - TrainerJet: desert sand (184,162,118)
    - LightFighter: olive drab (96,104,66)
    - StrikeJet: dark green (62,82,60)
    - CASJet: earth brown (126,100,72)
    - StealthStrike (and the StealthStrikeJet alias ref): charcoal (46,48,54)
    The colours on the four original jets show for everyone. The three new jet keys are owner-only.
  - **Runway:** 170 x 24 → 190 x 29. It can't be longer: the plot edge is at X -160 and the HeliApron at X 34.
  - **Hangar:** 58 x 34 → 68 x 40 (+17 %). The site moves to Z -125 and the shell scales by Width/58.
  - **Bridge Layer:** wades through water like the Amphibious APC (0.4 x speed). Server-authoritative,
    owner-only (`VehicleConfig.Drive.WaterRule.AmphibiousRollout = { BridgeLayer = "owner" }`).
- **Left in `handoff/wip/`** (the README rows give the status): 02 capture, 03 lane B, 04 lane A, 07, 09-12 VKIT. Lane C was not started.
- **Pins:** `tools/checks/codebot_v90.py`, plus Claude's lane pins moved to `codebot_v90_airfix2.py`, `codebot_v90_harbor.py` and `codebot_v90_faces.py`.

---

# WHERE I STOPPED — 2026-09-28 ~19:40 UTC (branch claude/war-empire-phase-7-toqwff)

**What I was doing:** shipping the army despawn fix (fix round r1), plus review rounds for the capture, harbor and faces fixes, and building the Part-made vehicle bodies (VKIT). The owner asked me to stop, so all workflows are stopped and nothing is scheduled.

**Finished and pushed (live-ready):**
- `af4c7d4`: ground vehicles can't drive on water.
- `4d26673`: army escorts shoot back at the bank, with tracers (owner-only rollout).
- `4e07fc2`: the owner's jet on the four jet keys, pilot inside, Ride on the Trainer.

**Left (all saved as patches in `handoff/wip/`; not built, not live; the table in `handoff/wip/README.md` gives each base and status):**
1. ~~Army despawn fix (`01`)~~: **shipped in v90, owner-only (`Rollout.Fix`)**. Still open: the r1 re-measure on a device/stand-in.
2. Plaza capture fix (`02`), then army lane B checkpoints (`03`, rebase after 02). **Still open** (not shipped in v90).
3. Army lane A, guard and follow (`04`): finish tests and rebase onto the shipped `01`. **Still open.** Lane C (ATTACK marches to checkpoints) is not started.
4. ~~Harbor boat and dock (`05`), faces (`06`) and air fix-2 (`08`)~~: **shipped in v90** (their review rounds were done by Code Bot while merging).
5. VKIT vehicle bodies (`09`–`12`): ground fix-2 and naval deliverables are half-done. ground2 records (`07`) wait on VKIT ground. **Still open.**
6. Water Lows: land spot behind walls, rider teleport prefetch, hover above 160 studs, shallow reverse. **Still open.**
7. Owner questions (**answered by the owner 2026-09-28; all done in v90 except the helicopter**):
   - Should the Strike, CAS and Stealth jets get his jet? **Yes**: they now use 14589101870 with the pilot inside (v90, owner-only like v88).
   - Is the jet's look OK? **Yes, approved**: kept.
   - Should each jet get its own colour? **Yes**: one military colour per jet key (v90; palette in the v90 note).
   - Should the runway and hangar be bigger? **Yes, slightly (15-25 %)**: runway 190 x 29, hangar 68 x 40 (v90).
   - Should the Bridge Layer be amphibious? **Yes, it should cross water**: it wades, owner-only, server-authoritative (v90).
   - New helicopter model (the uploader made every part, 35 parts or fewer)? **Yes, wanted. The owner is handling the search himself: do NOT search.** Wire it once he sends the id.

**Files:** `handoff/wip/*.patch` (12 lanes, plus 03b/04b base patches), `handoff/wip/README.md` and `handoff/wip/notes/` (phone tests, owner texts, assumptions and the army design spec).
**Owner phone test right now:** nothing new. `src/` is unchanged since 4e07fc2.

---

# LATEST HANDOFF — Code Bot Roblox replacement (20 Sep 2026 ~00:00 Madrid)

> **v89 (28 Sep 2026, Code Bot): the wc7 capital ships + airlifter are WIRED — owner-only, same system. Claude: do not redo.**
> Destroyer 6860896505 (Stud Class, 0.2) and Cruiser 6860896505 (0.22), both Yaw 180 (bow = the pointed +Z end with the
> full-depth stem; the rounded overhanging -Z end is the stern: wc7's Yaw 0 note was flipped after the side-profile
> raycasts), MissileCruiser 104820847233642 (18, BodyMaxScale 18, bow -Z), Battleship 12442299148 (2.0, bow -Z); all
> dark naval grey (58,62,68), captain inside the bridge, kit TurretF/BarrelF/TurretA moved onto the body turrets
> (BodyMounts). CargoPlane/AWACSPlane/TankerPlane now 10649792198 (4-engine airlifter, 2.1, Yaw -90, dark grey;
> replaces 17033079003). The v88 capital-ship NoFamilyFallback exclusion is gone (own bodies now). StrikeJet stays
> 3553891209. Every air / naval vehicle with a definition now wears a body for the owner. Pins: tools/checks/codebot_v89.py.

> **v88 (28 Sep 2026, Code Bot): the wc6 winners are WIRED too — owner-only, same system. Claude: do not redo this.**
> VTOLTransport 80886282228822 (both proprotors spin), AttackHelicopter/GunshipHeli/EscortHeli/NightAttackHeli
> 11240665977 (main rotor spins), StealthHeli = 11240665977 recoloured near-black (NOT 11839207737: a real Little
> Bird look-alike), StrikeJet/CASJet 3553891209 (gear omitted, texture cleared, dark), StealthStrike/StealthStrikeJet
> 7976374439, CargoPlane/AWACSPlane/TankerPlane 17033079003 at BodyScale 30, dark grey (replaces 2475398012),
> LandingCraft/AssaultLanding 12235335847 (anchor + chain omitted), HospitalShip/SupplyShip 2625253037, HoverTransport
> 3626114334. New ref fields: BodyMaxScale (cap 4..40), BodyAnchorX (carrier + amphib: the body also shifts across so
> the captain sits in the island). Still on the kit (search ongoing): Destroyer, Cruiser, MissileCruiser, Battleship —
> now NoFamilyFallback so they never inherit the LandingCraft barge. Pins: tools/checks/codebot_v88.py.

> **v87 (28 Sep 2026, Code Bot): air + naval store bodies are WIRED — owner-only. Claude: do not redo this.**
> 29 vehicles wear the owner's picks through the 4e07fc2 body system (VisualAssetConfig `BODY_*` tables + `bodyRef`,
> VisualAssetService fit, AirBodyRig), gated by `VisualAssetConfig.BodyRollout = "owner"` + per-ref `Rollout = "Body"`
> (only vehicles spawned by shaunie6 / 470626172 wear them; everyone else keeps the Part kit, no load):
> light helis 3130894523 (LightScoutHeli, UtilityHeli, RescueHeli, MedevacHeli; kit rotor spins on the mast),
> transport helis 109615982233602 (TransportHeli, LightTransportHeli, HeavyLiftHeli), bombers 14669079591
> (StrikeBomber, HeavyBomber, StrategicBomber; Bay mount under the centre), transports 2475398012 (CargoPlane,
> AWACSPlane, TankerPlane), patrol 16692908395 (PatrolBoat, FastAttackCraft, RiverBoat, CoastCutter, TorpedoBoat),
> gunboat 15838664806 at 0.027 (Gunboat, MissileBoat, MineLayer, CoastalMonitor; per-ref BodyMinScale), frigate
> 473576954 (Corvette, Frigate, CarrierEscort), carrier 7941124517 (FleetCarrier; BodyDeck plates), amphib 5545544418
> (AmphibAssault), sub 116924692473761 (SubSurfaceRunner, AttackSub; propeller spins). New ref fields: Rollout,
> BodyMinScale, BodyWaterline, BodyColor/BodyMaterial/BodyClearTexture, BodyDeck, BodyKitNoCollide, KitRotor.
> Kept on the kit (owner decision): Destroyer, Cruiser, MissileCruiser, Battleship (16675798409 rejected: real class),
> VTOLTransport (NoFamilyFallback), attack/gunship/escort/night/stealth helis, strike/CAS/stealth jets, landing craft,
> hospital/supply ships, hover transport. Pins: tools/checks/codebot_v87.py. To open to everyone later: BodyRollout = "all".


Shaun created you because the previous Code Bot Roblox chat **wedged** (messages failed to send). You replace it. Code/GitHub/laptop Studio are intact.

## Read first
1. `/workspace/war-empire/HANDOFF-TO-NEW-CODE-BOT.md` — MASTER SYSTEM INSTRUCTION + WAR EMPIRE brief
2. `/workspace/war-empire/MASTER_BUILD_SPEC.md`
3. `/workspace/war-empire/ASSUMPTIONS.md`
4. This file

Save operating rules to agent memory (profile): build don’t tutor; COMPLETED/FILES/TESTING/NEXT; local iteration; push to https://github.com/shaunbirrell/war-empire; ask only when architecture-breaking.

## Repo / branch
- Remote: https://github.com/shaunbirrell/war-empire
- Working branch: **`phase-7-polish`** (latest commit at handoff: **`b009165`** — BUY bootstrap fix)
- Earlier PRs: #1 phase-3-combat, #2 phase-5-territory, #3 phase-7-polish (may need refresh)
- Local: `/workspace/war-empire`
- Place builds: `dist/WarEmpire.rbxlx`, `dist/WarEmpire-PERF.rbxlx`
- Shaun’s laptop: `C:\Users\laura\Downloads\WarEmpire-PERF.rbxlx` (machineId `be2ced83-f720-49b1-a3c0-1100e04ffc10` — Lara’s Windows laptop used for Studio)

## What the previous bot was doing (transcript summary)

### Product progress
Phases 1–7+ heavily expanded beyond MVP:
- Foundation, tycoon, combat, vehicles, territory, missions, monetization, tutorial, battle pass, clans, seasons, soldiers, bank raids, spinner, upgrade pads, desert map restyle, bank guards AI, mobile HUD, perf cuts, void/fall safety, world prompts / BUY pads

### Critical live bug (LAST FOCUS — claimed fixed, needs Shaun confirm)
**Command Center BUY broken in Studio Play:**
1. `CombatService/init.luau` required `VisualAssetService` via wrong path (`script.Parent.Parent` → Server), crashing Bootstrap
2. Crash happened **before** remotes finished → client error `RemoteEvent missing: SpinnerStateUpdate`
3. HUDController died → WorldPromptController never inited → no BUY button

**Fix shipped in `b009165`:**
- Correct require → `script.Parent.VisualAssetService`
- `RemoteSetup.Init()` early + idempotent
- UIController `safeInit` pcall so WorldPrompt always runs
- Rebuilt rbxlx; copied to laptop Downloads as `WarEmpire-PERF.rbxlx`

**Shaun was asked to:** Stop Play → open new Downloads file → Play → stand on Command Center → expect gold BUY + walk-buy; cash $5000 → $3500. **He has not confirmed yet** (chat wedged).

### Other open work from previous todos
- Verify BUY + all dock/buttons end-to-end
- Playtest on laptop Studio until solid
- Studio/Creator assets for soldiers/guards/buildings/vehicles (in progress / cancelled stick approach)
- Overnight polish / MVP completion pass

### Git commit tip
Do **not** write `git config`. Use env:
```
export GIT_AUTHOR_NAME="Code Bot Roblox"
export GIT_AUTHOR_EMAIL="codebot@war-empire.local"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
```

### Shaun prefs
- Speed: keep chaining, local executors over Cloud Agents
- Copy rbxlx to his laptop Downloads when shipping playtest builds
- Roblox username seen in logs: `shaunie6`
- Spanish Windows path (`El sistema no puede encontrar…`) — laptop is Spanish locale

## Immediate job
1. Message Shaun: you’re the new Code Bot, online, you have the handoff.
2. Confirm `git log -1` on `phase-7-polish` is `b009165` or newer; pull if needed.
3. Ask if BUY works on the latest `WarEmpire-PERF.rbxlx`; if not, diagnose from Studio Output and fix.
4. Continue polish: buttons, playtest, assets — COMPLETED/FILES/TESTING/NEXT format.

Chief of Staff may ping you; Shaun’s chat is primary.
