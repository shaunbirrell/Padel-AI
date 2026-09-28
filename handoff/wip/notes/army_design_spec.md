# SPEC-ARMY-FINAL: the army guards your gate, follows you out, and takes the checkpoints on your road to the Centre

**Status:** design only (judge + synthesis). No repo code was changed. Read at `main` HEAD `e506c9c` (live v83).
**Base:** SPEC-ARMY-MVP (`army/design/mvp/spec.md`), with ideas grafted from SPEC-FRONT (`army/design/fun/spec.md`) and one
re-measured placement. §J explains the verdict and names every graft.
**Not in scope:** the despawn root cause. A parallel diagnosis lane owns the root cause and its fix (§1.2). This spec
states only the lifecycle rules it depends on and the single RECOVER rule (§6.5), which the fix uses too.

**Owner request (2026-09-28, the design part, verbatim):** "They should stand like an army outside your base protecting
and only follow when you go outside the base and the attack button doesn't send them walking to take checkpoints.
There's two much dead space between the base and the centre point there needs to be more to capture along your way, you
should be able to capture checkpoints along the way and hold onto the checkpoint lots of other games do this check it out
the game I sent previously does it". From the same message: "they walk into wall" and "I went to the bank and they
didn't shoot".

**Only the mechanic is re-implemented.** The reference game is described publicly as: ATTACK takes the nearest territory,
then the next one; HOLD keeps a territory; FOLLOW follows; RETREAT goes home. Every name here (GUARD, Forward Post,
North/East/South/West Gate), every rule, number, piece of UI and line of code is our own. No asset, text or code is taken
from any game (`docs/BENCHMARK_MILITARY_TYCOON.md`, "Explicit non-goals").

**Evidence labels:**
- **[code]** read at `e506c9c` (`git show e506c9c:<file>`), paths under `src/`.
- **[measured]** geometry on the headless stand-in dump of `e506c9c`. The dump is the real `MapSetup.Run` + `MapDressing`
  Full: 4,746 parts, 2,430 of them outside the bases. The scripts are:
  - `army/design/mvp/work/mvp_geo.py`;
  - `army/design/fun/work/fun_geo.py`;
  - re-runs for this spec in `army/design/final/`: `final_geo.txt` (Forward Posts 3 and 4 at x ±24) and
    `geo_fp3_tg2.txt` (3-part / 2-part kits).

  **The stand-in is not Roblox.** It has no Humanoid physics, no terrain voxels, no PathfindingService, and no purchased
  walls, guns or pumps; those are added from their config formulas.
- **[stand-in run]** driver results from the diagnosis lane (`army/diag/root1/results.txt`).
- **[estimate]** arithmetic.
- **[Studio]** needs Roblox Studio or a phone; not claimed here.

---

## 0. For the owner (8 lines)

1. When you are in your base, your army stands in a line just outside your front gate, facing out, guarding it.
2. Walk or drive out and they follow you. Come home and they walk back to the gate. The new GUARD button sends them home at any time.
3. ATTACK now means "take the next checkpoint". They march out in a file, beat the guards, stand on the flag and take it, then move on.
4. Your road to the Centre gets 2 new checkpoints: your Forward Post (about 250 studs out) and a Town Gate. You never walk more than about 16 s without something to take.
5. A checkpoint you hold shows your colour and pays $1,000 (Forward Post) or $2,000 (Town Gate) every 90 s. You can hold 3. They reset when you leave the server.
6. Your army takes checkpoints only while you are within about 320 studs (your own Forward Post counts from your base). A rival player standing on the flag always beats an army.
7. They walk around walls and gates and catch up after a drive, and they are never deleted for being far away. At the bank they now shoot back at guards shooting you, and you can see their tracers.
8. It ships switched off, then on for your account only. Please run the phone test in §16 before everyone gets it. Whether your gate army may shoot raiders is your call (D1, off until you test it with a friend).

---

## J. Judge verdict (MVP vs FUN)

### J.1 Scores (1 = poor, 5 = best)
| Criterion | MVP | FUN | Why |
|---|---|---|---|
| Fixes exactly what the owner asked | 4 | 5 | Both cover all five asks. FUN's army marches and captures without you, the closest to the reference. MVP's army waits for you beyond 320 studs, but it takes your own Forward Post from home. Only MVP makes squad fire visible: `unitShoot` sends no FX today (`SquadOrdersService.luau:863-899`, 0 `CombatFx` hits in the file) [code] |
| Phone-first UX | 4 | 4 | MVP: one status line and a GUARD cell. FUN: chain dots, a mode word on the rail tile and a respawn button; richer, but a 300 v popover plus a new button during the respawn wait |
| Fairness (6-player server) | 3 | 3 | **MVP:** the owner leash is good. But an army contests a ring like a player, and units cannot be shot, so an army parked on your own Forward Post (leash exempt at home) blocks rivals forever. Its D1 raider rule shoots anyone within 70 of the gate (passers-by). **FUN:** a player always beats an army, and garrisons never shoot bystanders. But armies capture with no owner nearby (a weak AFK walk rule), D1 is ON by default with units that cannot be shot back (asymmetric), and armies may take the Plaza |
| CLAUDE.md budgets and rules | 5 | 3 | **MVP:** 0 collidable post parts; garrisons inside the 18 + 4 NPC cap (`OverCap`, `CombatService/init.luau:910-922`), so the phone figure budget (`RigConfig.Budget` 940 / 760, which already counts 22 NPCs) is unchanged. **FUN:** +6 garrison NPCs outside the cap force `Escort.MaxPerClient` 22 → 14 (against the owner's D14 "army on screen growing"), and it adds a collidable sandbag wall across the lane (a new "walk into wall" source) |
| Build risk and effort | 4 | 2 | **MVP:** about 1,950 lines in 4 lanes. **FUN:** adds NPC → unit damage (a new combat path), R-scaled and linked pay, AFK tracking, Deploy / forward-respawn teleports, a hook in `onCharacterAdded`, an `unitMayHit` amendment (reopens the squadfair provoke rule) and Phase B |
| Fit with existing systems | 5 | 3 | **MVP** reuses the capture tick, `CaptureStipendService`, `ObjectiveMarker`, FollowPath, `OverCap` and GateDefense. **FUN** adds a second NPC ledger outside `aliveNPCCount` and a respawn hook |
| **Total** | **25** | **20** | **MVP is the base** |

### J.2 Grafted from FUN (with the reason)
1. **A player always beats an army** on a post. An army counts only when no player is in the ring. This fixes MVP's
   unbeatable-blocker problem while units cannot be shot. **Outnumber** settles army vs army (§5.1).
2. **An army alone captures at half speed** (`ArmyRate 0.5`). Going yourself is faster, and farming is slower.
3. **Garrisons never shoot bystanders:** they target only players near the gate or players who hurt them (§5.5). The
   Town Gates sit on the main roads to the Centre.
4. **Forward Posts 3 and 4 at x ±24, not ±19.** The ring (r 16) then ends 1 stud clear of RoadX0's 7-stud carriageway,
   so passing drivers never contest it [measured `final_geo.txt`; `WorldConfig.luau:480` lane 7 + shoulder 5].
5. **Town Gate flag on the booth roof** (2-part kit, no pole). The busiest 512-stud circle drops from 492 to **488**
   [measured `geo_fp3_tg2.txt`].
6. **The WorldHygiene H3 fact** [measured by FUN]: a zone at a Town Gate would make H3 destroy 9–10 Town parts per gate,
   including the checkpoint kit. Post rows therefore carry `NoDressKeepOut`, honoured by WorldHygiene H3 and WorldDress.
7. **The bank fix ships first, alone** (stage 1, its own switch).
8. **Focus fire:** the escort also engages NPCs the owner hit in the last 6 s.
9. **HOLD on a post** spreads the army on the ring ("hold onto the checkpoint").
10. **The rail tile shows the army's mode word** (`GUARD`, `FOLLOW`, …), readable with the popover closed.
11. **The D1 raider rule is the gate guards' own** (`IsRaiderOf`: holding an ATM raid on this plot, hit this base, or
    inside the walls; never a passer-by), with damage through the gate-defense path.
12. **ATTACK clears hostiles fighting you first** (CLEAR, today's ATTACK engine), then takes posts.
13. **No regroup within 25 studs of another player**, so nobody sees a soldier pop in beside them.
14. **Streaming check:** `default.project.json` sets no `StreamingEnabled` [code]. The owner confirms the live place's
    setting in Studio.
15. **Deferred to owner decisions or later lanes:**
    - garrisons shooting units (Lane E, dark);
    - Deploy / forward respawn (D7);
    - an army taking the Plaza (D6);
    - linked "supply line" pay (v1.1).

### J.3 Rejected
| From | What | Why |
|---|---|---|
| FUN | Garrison ledger of 6 outside the NPC cap | Needs the escort cap cut to 14 |
| FUN | 4-part Forward Post with a collidable sandbag wall across the lane | A wall on the lane the army walks |
| FUN | R-scaled pay, linked ×0.5, full-line bonus, AFK walk rule | Flat pay is predictable. The owner leash and keep-away expiry cover AFK |
| FUN | 2-wide column 4 apart | Escort figures fill a 14-stud single file, and the file fits the road shoulder |
| FUN | Gate army shooting raiders by default while units cannot be shot back | Asymmetric |
| FUN | Inner Gates ring | Busiest circle 507, over the 500 cap [measured by FUN] |
| MVP | "Within 70 of the gate" as a raider test | It shoots passers-by |
| MVP | Armies contest players | Replaced by graft 1 |
| MVP | Town Gate pole on the far shoulder | Replaced by graft 5 |

---

## 1. Scope and dependencies

### 1.1 The owner's five asks
| # | Ask | Sections |
|---|---|---|
| A1 | Stand outside the base guarding it; follow only when the owner leaves; come back when he does or on an order | §3.1, §6 |
| A2 | ATTACK sends the army to take checkpoints (march, fight the guards, stand in the ring, capture) | §3.2, §6.3 |
| A3 | Checkpoints along the way that you (and your army) take and hold | §4, §5 |
| A4 | They do not walk into walls | §8 |
| A5 | They shoot at the bank | §7.2 |

### 1.2 Dependencies (merge order matters)
1. **The despawn fix (parallel lane, owns the root cause).**
   - This spec assumes a live, owned unit is destroyed **only** when:
     - its Humanoid dies (removed 0.35 s later, re-formed 8 s later; `SquadOrdersService.luau:669-686`);
     - the army shrinks (dismiss or research loss);
     - the owner leaves the server;
     - `OrdersConfig.Enabled = false`.

     It is **never** destroyed for distance from the base, the spawn or the owner, nor for a failed `MoveTo` or path.
   - Recovery is a reposition (§6.5), never a destroy and respawn. If the fix lane ships a recovery first, it uses §6.5's
     numbers, so there is one implementation.
   - **What the stand-in shows today** [stand-in run, `army/diag/root1/results.txt`]:
     - Over 10 movement scenarios the server kept 8 of 8 original unit ids alive and parented to `WarEmpireSquads`,
       with `destroyUnit = 0`. The scenarios were: walks at 16 / 18 / 20 studs/s to 1,363 studs from the pad,
       teleports, a 60 studs/s drive, owner death, the bank, ATTACK and base. The 11th run is the catch-all control,
       which does see its own destroys.
     - Units walk at `UnitWalkSpeed` 14 [code `OrdersConfig`] against the owner's 16, so they trail by about 2 studs/s.
     - 4 to 8 of 8 units hit blocked straight `MoveTo` steps on the long walks.
     - The script's phone-camera model drew 0 of the 8 units from t ≈ 9 s of the 16 studs/s walk.

     This is **not** the verdict: the fix lane reports the root cause. It is why §6.2 adds a catch-up speed and §6.5
     keeps units near the owner.
2. **fb4 capture lane (ready):** `EconomyConfig.OutpostIncomeBuff.PersistClaims = false`,
   `TerritoryConfig.ReleaseOnLeave = true`, and `StandingBar`. Posts follow the same rule: session-only. This spec's
   TerritoryService / TerritoryConfig / TerritoryController edits go on top of that lane.
3. **Front v1 (`army/spec_army.md`)** was never built; there is no `FrontConfig` in `src` [code]. This spec replaces it
   and reuses its measured sites.
4. **Streaming:** `default.project.json` sets no `StreamingEnabled` on Workspace, and `StreamingConfig.luau:4-8` records
   the switch as the project file [code]. **The owner confirms Workspace.StreamingEnabled on the live place in Studio.**
   Nothing here reads unit or post instances on the client (§6.4, §9).

---

## 2. Why the owner sees what he sees [code at `e506c9c`]
| Symptom | Cause |
|---|---|
| The army follows you **into** the base and never guards it | There is no guard state. The default order is Follow (`OrdersConfig.luau:17`). Follow walks the FollowSlots wings beside the player wherever he goes. RETREAT walks to the plot spawn **inside** the base (`plotRetreatCFrame`, `SquadOrdersService.luau:197`). A new unit spawns beside the player (`spawnCFrame :1314`) |
| ATTACK does not take checkpoints | ATTACK means "each unit attacks the nearest hostile NPC within `AttackAggroRange` 120 of itself" (`attackUnit :1132`). With none in reach, a unit walks to 12 studs in front of the owner (`:1159`). Units never count for a capture: `TerritoryCapture.PlayersInZone` counts players only (`TerritoryCapture.luau:90-124`) |
| "Too much dead space" | Between each base and the Centre, the only zones are the owner-only Home Outpost (100.9 studs from the gate) and the Central Plaza (r 70). From the Home Outpost to the Plaza ring is **479–631 studs** with nothing to take: 30–39 s on foot [measured] |
| They walk into walls | Movement is straight `Humanoid:MoveTo`. `PathfindingService` appears nowhere in `src`. Only FOLLOW has a detour (the FollowPath trail, 12 crumbs, `OrdersConfig.FollowPath`). The escort close-in, ATTACK chase and RETREAT walk straight. The friendly gate barrier opens only for the owner or a clan-mate player within 12 (`GateDefenseService.luau:1610`), never for units |
| They did not shoot at the bank | (1) The escort engages only hostiles within `EscortEngageRadius` **55 of the player**, leashed at **20** (`CombatFairnessConfig.luau:49-50`). Bank guards have `Range` 75 and `AggroRange` 90 (`CombatConfig.luau:115-123`), so from 55 to 75 studs they shoot you and the army does nothing. (2) Units leashed 20 behind you often have no line of sight past the planters and columns. (3) **Squad shots send no visual effect** (`unitShoot :863-899` calls no `CombatFx`), so even real hits are invisible. (4) If the army had vanished (the parallel bug), nothing could shoot. Bank guards are Aggressive with no group (`BankRaidService.luau:90`), so `unitMayHit` never blocks the squad there |

---

## 3. What the player does (phone landscape first, no key names)

### 3.1 At home: GUARD
- **You are in your base** (your plot square). Your army stands in **one line of 8 outside the front gate**, 4 on each
  side of the gate lane, 11.5 studs past the wall line, facing away from the base. The client-only escort figures
  (R-RIG, `RigConfig.Escort.Offsets` 7 / 9.4 / 11.8 ahead) stand in front, so a grown army reads as a block 4 deep.
- They shoot hostile NPCs within 70 studs of the gate. Players only if the owner turns **D1** on (§7.3).
- Recruits you buy appear **on their spot in the line**.
- **You leave** (on foot or by car, through any gate): after 1 s outside, the army switches to FOLLOW (today's wings and
  escort, plus the fixes in §7).
- **You come back in:** after 2 s inside, they walk back to their line. From more than 400 studs away they regroup at the
  line instead (§6.5).
- Walking out to stand among your own line does **not** make them follow. The line is 10 studs outside the square, and
  "outside" starts at 14 (hysteresis, §6.1).

### 3.2 The Army popover and the rail tile
- **Cells:** ATTACK · HOLD · FOLLOW · **GUARD**. GUARD replaces RETREAT; an old client's "Retreat" is accepted as GUARD.
- **Under the title `ARMY 8/8`:** one status line in 20 v text (14 px real):
  - `GUARDING BASE`, `FOLLOWING`, `HOLDING`, `HOLDING POST`;
  - `TO FORWARD POST` / `TO NORTH GATE` / …;
  - `FIGHTING`, `TAKING POST`, `WAITING FOR YOU`, `RETURNING`, `AT THE CENTRE`.
- **The rail's Army tile** shows the mode in one word: `GUARD`, `FOLLOW`, `ATTACK`, `HOLD`, `RETURN`. It changes only on
  a payload.
- **FOLLOW** means automatic: follow me outside, guard the gate when I am home.
- **GUARD** means "go home now": the army returns to the gate and stays there even while you are out. The next time you
  are home, the order goes back to automatic, so your next trip out is followed.
- **HOLD** keeps today's behaviour. **New:** if the army stands on or within 30 studs of a post when you tap HOLD, it
  spreads on that post's ring and keeps it.

### 3.3 ATTACK
One tap on ATTACK in the popover (2 taps from the rail tile):
1. The server picks the target (§6.3). You get **one** GO line (the existing `ObjectiveMarker`, the one AlwaysOnTop
   marker) with a short label: `POST`, `GATE`, `CENTRE` or `BANK`. You also get one toast: `Army moving out`.
2. The army marches a fixed lane (§4.4) in a single file, 14 studs apart (escort figures fill the gaps), at 18 studs/s.
   On Town roads it keeps to the right shoulder.
3. At a **Town Gate** it lines up across the road 50 studs out and fights the gate's 2 guards, then walks into the ring.
   A **Forward Post** has no guards, so it walks straight in.
4. The capture bar you already know reads `ARMY · FORWARD POST` with its progress.
   - When the post is taken: toast `Forward Post taken`, the flag turns your colour, and the army moves on to the next
     post in your chain.
   - After your Town Gate, the army holds a line at the Centre's edge. Toast: `Take the Centre!`. The Plaza itself is
     still taken by players standing in it.
5. **You are more than 320 studs from the post:** the army stops short with `WAITING FOR YOU` (one toast) and captures
   once you come within 320.
   - Your own Forward Post counts from anywhere in your base.
   - After 120 s with you more than 400 away, it gives up and goes back to automatic.
6. **Enemies are shooting you** (a hostile NPC aiming at you within 90): ATTACK first clears them (today's ATTACK
   engine), then goes on to the post.
7. **Near the bank** (you within 150 studs of it and a guard alive): ATTACK means "clear the bank guards".

### 3.4 Posts along the way
- **Forward Post (one per base).** An open-desert ring 32 studs across with a flag pole in the middle, 189–288 studs
  from your gate. Capture: 8 s (16 s for an army alone). No guards.
- **Town Gate (one per Town road: N, E, S, W).** A ring 36 studs across, on the road at the existing Town checkpoint
  (booth, raised arm, sandbags), with the flag on the booth roof. Capture: 12 s (24 s for an army alone), once its
  2 guards are down. P1 and P2 share the West Gate; P5 and P6 share the East Gate.
- **Labels:** the stud-scaled zone label over each (`Forward Post`, `North Gate`, …), MaxDistance 40, never AlwaysOnTop.
- **Territory panel:** lists only **your** chain posts (your Forward Post, your Town Gate). Pointers always resolve to
  your own chain (CLAUDE.md "Pointers").

---

## 4. Placement [measured at `e506c9c` unless marked]

### 4.1 Map sketch (world X →, Z ↓; north = −Z = up; 1 column = 30 studs, 1 row = 60 studs; `army/design/final/map.txt`)
```
                            ###########
                            #         #
                            #    3    #          #  plot walls (320 x 320)     G  main gate
                            #         #          h  Home Outpost (existing)    F  Forward Post (new)
                            #####G#####          T  Town Gate (new zone on     C  Central Plaza (ring r 70 = o)
                                 ..                 the existing checkpoint)   B  Empire Bank
 ############                     h                   ###########              .  ATTACK march lane
 #         ##                     F                   ##
 #    1    #G..h                 ..                   G#    5
 #         ##  ..                .                 h..##
 #         ##   ..               T                ..  ##
 ############    .F              .               ..   ###########
                  ..             .      B       F.
                   ..            .             ..
                    .          oo.oo          .
                     ..T.......o C o.......T..
                    .          oo.oo          .
                  ..             .            ..
                 .F              .             ..
 ############   ..               .              F.    ###########
 #         ##  ..                T               ..   ##
 #         ##..h                 .                ..  ##
 #    2    #G                   ..                 h..G#    6
 #         ##                   F                     ##
 ############                   h                     ###########
                                ..
                            #####G#####
                            #    4    #
                            #         #
```
Each route is Gate → Home Outpost → **Forward Post** → **Town Gate** → Plaza edge.

### 4.2 The chain per base (world X, Z)
| Plot | Gate | Home Outpost (existing) | **Forward Post** (new) | **Town Gate** (new zone) | Plaza-edge hold line |
|---|---|---|---|---|---|
| P1 | (−641.5, −400) | (−548, −438) | `Post_FP1` (−454, −219) | `Post_TG_W` (−310, 0) | (−90, 0) |
| P2 | (−641.5, 400) | (−548, 362) | `Post_FP2` (−454, 181) | `Post_TG_W` (−310, 0) | (−90, 0) |
| P3 | (0, −641.5) | (38, −548) | `Post_FP3` (**24**, −454) | `Post_TG_N` (0, −310) | (0, −90) |
| P4 | (0, 641.5) | (−38, 548) | `Post_FP4` (**−24**, 454) | `Post_TG_S` (0, 310) | (0, 90) |
| P5 | (641.5, −400) | (548, −362) | `Post_FP5` (454, −181) | `Post_TG_E` (310, 0) | (90, 0) |
| P6 | (641.5, 400) | (548, 438) | `Post_FP6` (454, 219) | `Post_TG_E` (310, 0) | (90, 0) |

**Distance between capture points** (studs; at 16 studs/s on foot) [measured `final_geo.txt`]:
| Plots | Gate → Home Outpost | Home Outpost → FP | FP → Town Gate | Town Gate → Plaza ring | Longest gap |
|---|---|---|---|---|---|
| P1, P6 | 100.9 | 238 | 262 | 240 | **262 (16.4 s)** |
| P2, P5 | 100.9 | 204 | 231 | 240 | 240 (15.0 s) |
| P3, P4 | 100.9 | 95 | 146 | 240 | 240 (15.0 s) |

Before: 479–631 studs (30–39 s) with nothing to take. After: at most 262 studs (16.4 s).

**Site checks:**
- **Forward Posts:**
  - nearest collidable: 65.4 (P4, a KmPost); the others 137.1–245.0;
  - 186–195 studs from the nearest plot pad; at least 400 apart;
  - beyond every outside gate gun's reach (capped at 100, `GateDefenseConfig`);
  - 0 dressing parts inside any FP's H3 circle [measured by FUN];
  - FP3 / FP4 ring edge at |x| = 8, 1 stud outside RoadX0's 7-stud carriageway (`WorldConfig.luau:480`).
- **Town Gates:**
  - the ring sits on the road at the kit centre; nearest collidables are the kit's own sandbags at 13.4 from the road
    line;
  - the flag stands on the booth roof (§4.3);
  - `NoDressKeepOut` stops H3 from destroying the 9–10 kit and Town parts per gate [measured by FUN].

### 4.3 What a post is (0 collidable, 0 lights, 0 Neon, 0 SurfaceGuis)
| Kit | Parts | Pieces |
|---|---|---|
| **Forward Post** | **3** | **(1) `<Id>` ring:** Cylinder turned flat, 0.12 × 32 × 32, top at 0.58; SmoothPlastic, Transparency 0.55, neutral khaki (170, 150, 100), holder colour when held. **It is the capture marker** (tags `WE_Territory`; attributes TerritoryId, Radius, IsPost). CanCollide / CanQuery / CanTouch false. **(2) `<Id>_FlagPole`:** 0.4 × 14 × 0.4, Metal (55, 55, 55), CanCollide false, at the centre. **(3) `<Id>_Flag`:** 5.5 × 3.2 × 0.22 at 12.2 up, SmoothPlastic, holder colour (khaki when neutral), CanCollide false |
| **Town Gate** | **2** | **(1) ring** as above but 36 across, top at **0.62** (above the 0.575 asphalt, so it never z-fights). **(2) `<Id>_Flag`:** 5.5 × 3.2 × 0.22 standing on the booth roof, centre 9.5 up, facing arriving traffic (kit −Z). Roof centres [measured]: N (17.5, −308.4), E (308.4, 17.5), S (−17.5, 308.4), W (−308.4, −17.5); roof top 7.9 |

- **The visible ring is exactly the capture area.** Post rows set `ExactRadius = true`, so `TerritoryCapture` uses
  `def.Radius`. Today it uses `max(Radius, marker.Size.Magnitude / 2)` (`TerritoryCapture.luau:95-97`), which would make
  a 32-stud flat cylinder count to r 22.6.
- **Label:** one `WE_ZoneLabel` per post, made by MapSetup as for every zone: stud-scaled, MaxDistance 40, never
  AlwaysOnTop.
- **Flags show the banner colour only, never a nation flag**, even with `NationConfig.OutpostFlags` on. These flags are
  fought over (CLAUDE.md: never a flag as a target). Pinned.
- **One Atomic `Model` per post** (`<Id>_Zone`, streaming S4 pattern, like the zone kits in MapSetup).

### 4.4 GUARD line (plot-local studs: +Z = out of the gate, +X = right when walking out)
All slots at **local Z 170** (the L5 wall's outer face is at 161.65), facing +Z, in fill order:

| Slot | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| Local X | −30 | +30 | −36 | +36 | −42 | +42 | −48 | +48 |

[measured, 6 plots × 8 slots, with walls at L5, gun nests, pumps, garage pad, Home Outpost and the car lane added from
config] Worst body clearance is **5.6 studs**: slot 1 against the car lane from the garage pad (−62, 222) to the gate,
6.8 studs wide each side. Other clearances:
- gun nests: ≥ 10.5;
- pumps: ≥ 12.6;
- gate lane (|X| < 7): ≥ 23;
- garage pad: ≥ 42;
- Home Outpost ring: ≥ 58;
- nearest world part: ≥ 140.

Nothing is added to the world: the line is 8 positions in config.

### 4.5 March lanes (fixed waypoints; measured clear, no pathfinding on them) [measured `final_geo.txt`]
Each lane is: gate out (local 0, 172) → rally (about 24 studs past the Home Outpost toward the FP) → FP → stage (50 out
from the Town Gate on its road) → Town Gate → Plaza edge (r 78).

| Plot | Waypoints (world X, Z) | Length | At 18 studs/s | Narrowest clearance | Nearest bank guard |
|---|---|---|---|---|---|
| P1 | (−628, −400) (−538.5, −415.9) (−454, −219) (−360, 0) (−310, 0) (−78, 0) | 825 | 45.9 s | desert ≥ 44.9; road 13.4 | 353 |
| P2 | (−628, 400) (−536.9, 340.7) (−454, 181) (−360, 0) (−310, 0) (−78, 0) | 775 | 43.0 s | ≥ 44.9 / 13.4 | 353 |
| P3 | (0, −628) (33.2, −524.5) (24, −454) (0, −360) (0, −310) (0, −78) | 559 | 31.0 s | ≥ 44.9 / 13.4 | 206 |
| P4 | (0, 628) (−33.2, 524.5) (−24, 454) (0, 360) (0, 310) (0, 78) | 559 | 31.0 s | ≥ 44.9 (KmPost 59.6) / 13.4 | 354 |
| P5 | (628, −400) (536.9, −340.7) (454, −181) (360, 0) (310, 0) (78, 0) | 775 | 43.0 s | ≥ 44.9 / 13.4 | 208 |
| P6 | (628, 400) (538.5, 415.9) (454, 219) (360, 0) (310, 0) (78, 0) | 825 | 45.9 s | ≥ 31.9 / 13.4 | 210 |

- **Road legs** (stage → Town Gate → edge) run single file on the **right shoulder, 9.5 studs off the road centre line**.
  - The body edge is at 10.5: 2.9 from the kit sandbags, and clear of the 7-stud carriageway.
  - Town buildings stay ≥ 13 from road lines (`WorldConfig.luau:760`).
- **Shared Gates:** the odd plot of a pair (P1, P5) uses the right shoulder and the even plot (P2, P6) the left, so two
  armies never share one file.
- **The bank:** no lane comes within the bank guards' aggro range (90); the minimum is 206.

---

## 5. Capture and hold rules (all numbers in config, §10)

### 5.1 Who counts on a post (post rows only; every other zone is unchanged)
Posts use the existing TerritoryService tick: 0.5 s, +1 per second at ×1, decay 0.35/s, contested ×0.5, and 45 s
protection at ×0.25 (`TerritoryConfig.luau:37-42`). Presence is evaluated each tick:

- **Strong presence** is a player, exactly as today: alive, root in the ring, on foot or as the driver.
- **Weak presence** is an army. It counts when:
  - at least `ArmyMinUnits` **2** of one owner's living units have their root in the ring and within 14 studs of its
    height;
  - the owner is alive;
  - the owner is within `OwnerLeashStuds` **320** of the post. For his own Forward Post, he may instead be anywhere in
    his own plot square.

| Present | Result |
|---|---|
| 1 player (any armies ignored) | That player captures at ×1 |
| 2+ distinct players | Contested: frozen, decays ×0.5 (today) |
| 0 players, 1 army | Its owner captures at **×0.5** (`ArmyRate`) |
| 0 players, 2+ armies | **Outnumber:** after 6 s, the army with at least 1 more unit present captures at ×0.5. A tie stays frozen (`BLOCKED`) |
| Any live garrison NPC of that gate (Town Gate, `RequireClear`) | Frozen for everyone: `CLEAR THE GUARDS` |

- **A player always beats an army.** Units cannot be hurt today: NPCs target players only
  (`CombatNPC.NearestPlayer`), and the player shot filter leaves out every squad unit (`CombatService/init.luau:10-11`).
  So an army must never make a post untakeable. A holder defends against players by being there himself.
- **Home Outpost:** stays player-only (the tutorial step). The **Central Plaza** is unchanged (D6).
- **Live filter (rollout, §13):** until `Posts.Live = "all"`, only live players and their armies count on posts. Other
  players neither capture nor contest.

### 5.2 Numbers
| | Forward Post | Town Gate |
|---|---|---|
| Radius (= ring) | 16 | 18 |
| Capture time: player / army alone | 8 s / 16 s | 12 s / 24 s |
| Garrison | none (D3) | HeavyInfantry at the kit anchor `Alarm` (17.6, −2.0) and Infantry at `G1` (−14.6, 5.5), kit-local through `ActivityAnchors` `Town.CP_<x>.<Role>` (`WorldConfig.luau:1012-1019`) |
| Stipend | $1,000 / 90 s | $2,000 / 90 s |
| Empire Tax / `MaxPersonalTerritories` / ClanWar / `Stats.TerritoriesCaptured` / nuke target | none | none |

### 5.3 What holding gives
1. **Stipend**, paid by `CaptureStipendService` at its 90 s tick from the row's `StipendCash` (reason
   `capture_stipend`; the same multipliers as every stipend).
   - Posts are always owned by the **player**, never a clan.
   - The cap is `MaxHeld` **3** per player, so at most $5,000 / 90 s = 55.6 $/s: the same as holding the Plaza.
   - [estimate] A typical hold (own FP + own TG) is 33.3 $/s before multipliers: 8 % of a 1-hour free player's
     394 $/s (`army/facts.md` §4.2).
2. **Your colour** on the ring and flag (existing `updateMarkerVisual`; never a nation flag).
3. **"Under attack" warning:** one toast to the holder when anyone else starts progress on his post:
   `North Gate under attack`. At most one per post per 60 s, never while the holder is being shot.
4. **Chain progress:** ATTACK skips posts you hold.
5. **No XP.** Mission `CaptureTerritory` +1 counts at most once per post per player per 600 s.

### 5.4 How long a post stays held
- **Until someone else captures it, or:**
  - **the holder leaves the server:** Neutral at once (`ReleaseOnLeave`);
  - **the holder has not been within 600 studs of it for 600 s:** Neutral. His own Forward Post never expires while he
    is in his own base;
  - **the holder takes a 4th post:** the oldest is released.
- **Session-only:** never written to `profile.Territories`, never re-planted, and never back on rejoin (the capture
  lane's rule). No ProfileSchema change.
- **A Town Gate re-garrisons** 60 s after it goes Neutral, once no player is within 100 studs.

### 5.5 Town Gate garrisons
- **Spawn:**
  `CombatService.SpawnNPC(type, cf, { NoRespawn = true, OverCap = true, Leash = 30, Home = cf, TargetZone = { Center = gate, Radius = 60 } })`.
  - They are Aggressive with **no group**, so `unitMayHit` never blocks the army (`CombatService/init.luau:1867-1880`).
  - They are spawned 0.2 s apart.
- **Targets (new `TargetZone` opt, no bystanders):** a garrison NPC considers only:
  - players whose root is within 60 of the gate centre;
  - players who hurt any NPC of this garrison in the last 10 s.

  A driver passing on the road outside 60, or a player 80 away who never fired, is never a target. Every shot keeps
  today's line-of-sight and `HitChance` gates.
- **Wake:**
  - a player on foot within 150; or
  - an army in ATTACK whose target is this gate, with a unit within 150 and its owner within 320.

  An army waiting for its owner never starts a fight alone.
- **Ledger:** at most **4** garrison NPCs alive server-wide (2 gates awake at once).
  - `OverCap` keeps them inside the 18 + 4 cap (`CombatConfig.luau:48, 60`): 10–12 camp NPCs + 5 bank guards + 4 = at
    most 21 of 22.
  - With the ledger full, the gate stays asleep and **unguarded**: it can be taken on capture time alone (logged once).
  - While a garrison is awake, a dead camp NPC respawns only when the regular 18 has room (§14).
- **Sleep:** no player or army within 400 for 60 s and nobody hurt them in that time: despawn, no pay.
- **Kills:** a player's kills pay the normal NPC cash and XP. Army kills in ATTACK pay nothing
  (`UnitKillCreditOnAttack = false`, unchanged).
- **Jobs cutover:** if an Ops `Town.CP_*` site is enabled, that gate's post turns itself off (logged once; fail closed),
  so two garrisons never share a kit. Ops ships OFF today (`OpsConfig.luau:158`).

---

## 6. Army state machine (server, per owner, inside SquadOrdersService's existing 0.4 s think)

### 6.1 Orders (what the player taps) and modes (what the army does)
```
Order FOLLOW (default = automatic):  owner HOME -> GUARD (via RETURN) ; owner OUT -> FOLLOW
Order GUARD:                          RETURN -> GUARD ; becomes FOLLOW (automatic) at the owner's next HOME
Order HOLD:                           HOLD (today) ; on a post: HOLDPOST (ring slots)
Order ATTACK:                         CLEAR? -> target T (§6.3) -> MARCH -> [FIGHT] -> CAPTURE -> next T ... -> HOLDLINE
                                      WAIT whenever the owner is beyond the leash of the current target
Any mode, per unit:                   RECOVER when stuck or left far behind (§6.5) -- never a destroy
```
- **HOME:** the owner's root is inside his own plot square (`PlotFrame`, half 160) with 2 studs to spare, for 2 s in a
  row.
- **OUT:** the root is beyond the square by **14** for 1 s in a row. The band between 2 and 14 keeps the last value, so
  standing among your own line (local Z 170) does not flip it.
- **No plot:** a player with no plot is never HOME. Automatic means FOLLOW; GUARD is refused with the toast
  `No base to guard`.
- **Novice shield:** only explicit taps (`SetOrder`) end it, as today. Automatic switches never do.

### 6.2 Modes
| Mode | Movement | Fire |
|---|---|---|
| GUARD | To its gate slot (§4.4); within 2 studs, stand facing out | Hostile NPCs within 70 of the gate centre, with line of sight and the unit hit curve. Side-step ≤ 10 (§7.1). Players only with D1 (§7.3) |
| FOLLOW | Today's FollowSlots wings + FollowPath trail. **New:** a unit more than 30 studs from its slot runs at 18 studs/s (otherwise `UnitWalkSpeed` 14). While the owner is in a vehicle moving faster than 20 studs/s, a unit more than 150 away holds where it is (no cross-country walk into walls) until the owner stops (§6.5) | Today's escort + defend-when-targeted + focus fire + side-step (§7.1) |
| RETURN | To the gate slots through `moveUnit` (§8); more than 400 studs away: regroup (§6.5) | Shoot what is in range and in sight; no chasing |
| HOLD | Today (`SquadOrdersService.luau:1273-1286`, leash 14) | Today |
| HOLDPOST | HOLD tapped with the army centroid within 30 of a post: the 8 capture slots of that post (§6.2 CAPTURE) | Shoot what comes into range |
| CLEAR | Today's ATTACK engine on the NPCs aiming at the owner within 90, leashed 60 from the owner; ends 3 s after none remain | Today's ATTACK rules |
| MARCH | Single file along the lane, 14 apart, at 18 studs/s. A virtual leader point moves along the polyline but never more than 8 studs ahead of the last unit. Joining from off-lane uses one squad path (§8) | Hostiles within 55 and in sight; never leave the file |
| FIGHT (Town Gate) | Fan across the road at the stage point (50 out), 4 apart, facing the kit | The garrison, line of sight + unit hit curve; side-step ≤ 8 |
| CAPTURE | Into the ring: 8 slots within 8 of the centre (lateral ±2 / ±6, along ±5). At a Town Gate the laterals stay inside ±13.4, off the booth and sandbags | What comes into range |
| WAIT | FP: a line across the lane 60 short of the post. TG: the fan line. One toast `Army waiting for you` | What comes into range (no garrison wakes, §5.5) |
| HOLDLINE | 2 ranks across the arm at r 90 and r 96, lateral ±3 / ±9 | Hostiles within 55 |

### 6.3 ATTACK target (server only; the client never names a target)
At the tap (repeat taps within 2 s change nothing, `UnitRepeatOrderGraceSeconds`) and after each capture, the first rule
that applies wins:
1. **CLEAR:** a hostile NPC is aiming at the owner within 90 (`CombatService.NPCsAimingAt`) → CLEAR, then re-pick.
2. **Bank:** the owner is within 150 of `BankRaidConfig.Position` and a bank guard is alive → FIGHT the bank guards from
   a fan on Bank Street 45 studs out.
   - Nothing is captured, and the vault hold stays player-only.
   - Ends when no guard is alive, or when the owner has been more than 250 away for 20 s.
3. **A post near the owner:** a post the owner does not hold within 150 of him → that post. A post held by another
   player is valid (a steal, slowed by its 45 s protection; the holder gets the under-attack toast).
4. **The next post in the owner's chain** that he does not hold: `Post_FP<n>`, then `Post_TG_<arm>`.
5. **The whole chain is held** → HOLDLINE at the Plaza edge on his arm. Toast `Take the Centre!` once.
6. **No plot or chain** (not possible with 6 plots and `MaxPlayersPerServer = 6`) → today's ATTACK, unchanged.

### 6.4 Edge cases
| Case | Behaviour |
|---|---|
| Owner dies outside | FOLLOW units hold where they stand (today: no root, no move). On respawn he is HOME → RETURN → GUARD. An ATTACK keeps its target → WAIT → after 120 s, automatic |
| Owner leaves the server | `clearSquad` and state dropped (today's `PlayerRemoving`). His posts go Neutral (`ReleaseOnLeave`). Garrisons are unaffected |
| Owner rejoins | Fresh army on the GUARD line; no posts come back |
| Owner drives out | FOLLOW with catch-up at 18. Units more than 150 away hold while the vehicle moves faster than 20 studs/s. When he stops (below 6 studs/s for 1.5 s) or gets out, units more than 150 away regroup (§6.5). Units never ride |
| Owner drives home | HOME after 2 s → GUARD; units more than 400 away regroup at the line |
| Raid, owner away | The existing `BASE UNDER ATTACK!` alert stays the only message. Tap GUARD to bring the army home |
| Raid, owner home | GUARD fire rules; players only with D1 (§7.3). **Units never enter the plot to chase** |
| Missile strike (defenses down) | Guard units keep shooting NPCs. With D1, they hold fire at players while `GateDefenseService.IsDefensesDown(plotId)` |
| A unit dies (vehicle wreck today; Lane E later) | Re-forms 8 s later (today's `SyncArmy` delay). In GUARD / RETURN it appears on its gate slot. In MARCH / FIGHT / CAPTURE / WAIT / HOLDPOST it appears beside the rearmost living unit. Otherwise near the owner, never inside the plot square |
| Recruit / research adds units | Same placement as a re-formed unit. Dismiss drops the outermost slot (today) |
| A closed gate barrier between units and their goal | The friendly gate also opens for the **owner's own units** within `GateOpenRadius` 12 (`updateFriendlyGate`), exactly as for a clan-mate |
| Two armies on one post | Outnumber rule (§5.1). Armies cannot hurt each other (army PvP is out of scope) |
| Novice (tutorial not done) | Guards the gate from the start. The tutorial's Home Outpost step is untouched |
| Streaming on | Everything is server-side. Clients act only on payloads (`SquadOrderStateUpdate`, `TerritoryState`); the GO line uses payload coordinates; `WaitForChild` only with timeouts |

### 6.5 RECOVER: never delete, reposition (one rule, shared with the despawn fix)
- **Triggers (per unit):**
  - FOLLOW: more than **150** studs from the owner for **5 s**, while the owner is not in a vehicle moving faster than
    20 studs/s.
  - Any moving mode: no **2**-stud progress toward its goal for **3 s** → one path request (§8). Still no progress
    **6 s** after that path failed or stalled → RECOVER.
  - The root is below `FallY` −50, or inside another player's plot square.
  - A vehicle stop or exit with units more than 150 away (§6.4).
- **Action:** one `PivotTo` of the unit (no despawn, no clone, the same id) to the first **clear** point of:
  1. its slot for the current mode (gate slot, file slot, ring slot or wing slot), if that is ≥ 24 studs behind the
     owner's facing or the owner is not in view of it;
  2. the owner's trail points (`trailByUser`) at least 24 studs behind him, newest first;
  3. 24 studs behind the owner along his facing.

  A point is **clear** when a ray 12 studs down hits a non-water part or terrain, and the `bodyClear` probe from the
  owner's root reaches it (the existing FollowPath probe). Landing behind the camera line means units "run in" and
  never pop in front of the player.
- **Limits:**
  - at most 1 RECOVER per unit per **8 s**;
  - at most **4** per owner per second (staggered);
  - never within **25** studs of another player (defer ≤ 10 s, then take the next candidate point);
  - deferred while the owner is on water.

  After a RECOVER: chase and give-up state is reset, and `MoveTo` is re-issued.
- **Never** `Destroy`, never `SyncArmy` churn. A unit with no clear point stays where it is and tries again after 8 s.
- **Counters:** `WE_ArmyRecover` (number attribute on the owner's Player) for tests and the Studio explorer, and one
  rate-limited server log line per owner per 30 s. **No debug label on live.**

---

## 7. Engagement rules

### 7.1 Every unit (all modes)
- **Targets:** CombatService NPC records only (a `WE_NPC` model with an `NPCId`), as today (squadfair).
  - Line of sight plus the unit hit curve (`UnitNearHitChance` → `UnitFarHitChance`), and squadfair's `pickShot`
    (≤ 3 rays per check).
  - `unitMayHit` and `UnitKillCreditOnAttack = false` are unchanged.
- **Defend when targeted (new; fixes the bank).** In FOLLOW, these are valid escort targets, **first** in priority:
  - an NPC whose `AimTarget` is the owner (`CombatNPC.luau:314`, exposed as `CombatService.NPCsAimingAt(player)`) and
    that is within **90** of the owner;
  - an NPC the owner hit in the last **6 s** within 90 (focus fire; a per-record `LastHitBy[userId]` stamp in the
    player → NPC damage path).

  While such a target exists, the escort leash is **28** (was 20), so units step out for a sight line.
  `EscortIgnoreCalm` stays.
- **Side-step (new):** after 2 consecutive checks with nothing in sight, a unit probes 4 and 8 studs to each side (at most
  4 rays, at most once per 1.5 s). It moves to the first point that sees a target and stays within its limit (GUARD 10
  from its slot, FOLLOW 28 from the owner, FIGHT 8).
- **Visible shots (new):** a unit shot, hit or miss, may send one `CombatFx.Bullet(unitId, 0, "NPC", eye, landed, kind)`.
  - It uses the existing WeaponFx `UnreliableRemoteEvent`, with the NPC rifle look and `S = 0`, so the rig's aim pose
    plays too.
  - Sampled to **1 event per army per 0.25 s**, plus an army bucket of **6 events/s per recipient** on top of CombatFx's
    own buckets.
- **One hostile snapshot per think pass:** `nearestHostile` stops calling `CollectionService:GetTagged("WE_NPC")` per
  unit (`SquadOrdersService.luau:768`). It reads `CombatService.LiveNPCSnapshot(out)` (≤ 22 records, refilled in place,
  no allocation).

### 7.2 The bank (A5)
- **FOLLOW:** defend-when-targeted covers it. Guards shooting the owner from 55–90 studs are engaged. Units step up to 28
  from the owner and side-step around the planters and columns.
- **ATTACK:** the bank fan (§6.3 rule 2). Kills pay nothing.
- **Visibility:** tracers make the fire visible. `BankRaidConfig.GuardRespawn` is unchanged.

### 7.3 D1: the gate army shoots raiders (owner decision; `Guard.FightRaiders`, default **off**)
When on, and only in GUARD:
- **A raider of this base** is `GateDefenseService.IsRaiderOf(plotId, player)`, the gate guards' own rule exported
  (`nearestEnemy` / `inSpawnGrace`, `GateDefenseService.luau:1056-1133`). The player is:
  - not an ally (`IsAlly`), not in spawn grace, and not novice-shielded; **and**
  - (a) holding an ATM raid on this plot (`WE_RaidingPlot`), (b) has hit this base's gate, guards, guns or guard units in
    the last 10 s, or (c) is inside the plot walls (`EngageIntrudersInsideWalls`).

  **A passer-by is never a raider.**
- **Fire:**
  - range **55**, **0.8** shots/s per unit, **5** damage × the owner's `SoldierDamage` research, at most **3** units on
    one raider;
  - NPC hit rules: line of sight, `NpcNearHitChance` 0.75 → `NpcFarHitChance` 0.30, fast-target penalty, 0.5 s reaction;
  - [estimate] about 7 damage/s on a raider at 35 studs;
  - damage goes only through `GateDefenseService.DefenseHit(plotId, player, dmg, unitModel)`, which wraps `dealDamage`
    (`:1224`): its shield, grace and vehicle rules and the `BASE UNDER ATTACK` alert.
- **Fairness counterpart (required with D1):**
  - guard units carry `WE_GuardTargetable` (set only in GUARD with D1 on);
  - `CombatService.RequestFire` lets an enemy player's shots hit them (no cash or XP);
  - client aim assist treats them as hostile (`AimTargets.IsHostile`);
  - units have 90–135 HP (`UnitHealth` 90 × research), and a downed unit re-forms on its slot 8 s later.
- **Hold fire** while defenses are down (missile strike). Units never shoot a player anywhere else. SQF-9 is amended for
  this case only, and pinned.

---

## 8. Pathfinding (A4): layered, cheapest first

One helper, `moveUnit(unit, goal, mode)`, replaces the straight `MoveTo` calls in RETURN, the escort close-in, the bank
fan, CLEAR, and the FIGHT / WAIT / CAPTURE / HOLDPOST slot walks. The FOLLOW wing / trail logic and the lane marches keep
their own targets but share the stuck check.

1. **Straight** when the goal is within 6 studs, or the existing 2-ray `bodyClear` probe (knee-to-waist, ±0.9) from the
   unit to the goal is clear. Re-checked at most once per second per unit.
2. **Squad path:** reuse the squad's cached path when its goal is within 20 studs of this goal. Take the next waypoint
   within 3 studs. File units take the waypoint `rank` spacings behind the leader's.
3. **Request a path** (`ArmyPath.Request`) and meanwhile hold (FOLLOW walks the owner's trail).
4. **Stuck** (§6.5): after 3 s with no 2-stud progress, request a path. RECOVER after 6 s more with a failed or stalled
   path.

**Joining a lane (MARCH / RETURN from off-lane):**
- The join node is the lane node that minimises (straight distance + remaining lane length) and whose straight segment
  from the squad centroid is probe-clear.
- If none is clear: one squad path to the best node.

**`ArmyPath` (new server module):**
- `PathfindingService:CreatePath({ AgentRadius = 1.5, AgentHeight = 5, AgentCanJump = false, AgentCanClimb = false,
  WaypointSpacing = 6, Costs = { Water = math.huge } })`.
- `ComputeAsync` runs in `task.spawn` under `pcall`, with a 2 s timeout.
- **Cache:** one path per squad until its goal moves more than 20 studs or `path.Blocked` fires. At most 64 waypoints.
- **Budget:** **2 computes per second server-wide** (token bucket; queue ≤ 12, oldest dropped) and at most 1 per squad
  per 2 s. A dropped or failed request falls through to rule 4.
- **Never** per frame, never on the client, no `RenderStepped` / `Heartbeat`.

**Where no pathfinding is needed:** the fixed lanes (§4.5) and the gate line (open ground). Paths serve only:
- leaving a building or yard;
- getting back to a lane or the gate from somewhere odd;
- the back and sea gates;
- the Town interior;
- stuck units.

**Cost [estimate; the microprofiler must confirm, Studio]:**
- ≤ 2 `ComputeAsync` per second, off the think thread;
- probe rays ≤ 2 per unit per second (≤ 96/s at 48 units);
- side-step ≤ 4 rays per unit per 1.5 s, only while blocked;
- the NPC snapshot removes the per-unit `GetTagged` scans;
- think rate unchanged at 2.5 Hz.

---

## 9. Budgets (CLAUDE.md hard caps)
| Budget | Now (`e506c9c`) | With this spec | Cap |
|---|---|---|---|
| Parts per base at L5 | unchanged | **+0** (the gate line is config) | 2,700 |
| World parts outside bases | 2,430 [measured] | **+26** (6 FP × 3 + 4 TG × 2) → 2,456 | 3,100 hard (2,900 `WorldConfig` Full) |
| Busiest 512-stud circle, static | 471 at (160, 160) | **488** [measured `geo_fp3_tg2.txt`]; **495** with 4 supply-crate + 3 Jobs bag transients | 500 |
| Busiest 1024-stud circle | 897 | **917** | 1,200 |
| Lights / Neon / SurfaceGuis | — | +0 / +0 / +0 | 730 (40 per base) / 986 / 1,134 |
| World labels | — | +10 zone labels (stud-scaled, MaxDistance 40, never AlwaysOnTop); 1 per post; 0 new at a base | ≤ 3 per base, ≤ 5 per outpost |
| AlwaysOnTop | the ObjectiveMarker | unchanged (the ATTACK GO line **is** that marker; latest GO wins) | 1 |
| NPCs alive | 15 (10 camps + 5 bank) | ≤ 21 (+4 garrison ledger inside `OverCap`) | 18 + 4 |
| Figure parts on a phone (`RigConfig.Budget`) | 936 of 940 (22 NPCs already counted) | **unchanged**; `Escort.MaxPerClient` stays 22 | 940 |
| Moving server Humanoids, 6 players | 82 | ≤ 86 | — |
| Squad units | ≤ 8 per player | unchanged | — |
| Remote traffic per player | — | `SquadOrderStateUpdate` on change, coalesced ≤ 2 Hz; `TerritoryState` unchanged; army tracers ≤ 6/s per recipient (unreliable); ≤ 1 toast per event | ≤ 20 Hz |
| Client per-frame work | — | 0 new. The status line and tile word change on payload only. Non-live post kits are hidden through the tag's added signal (≤ 30 local writes) | no whole-tree scans; UI ≤ 10 Hz |
| Instance changes per purchase | — | 0 (a recruit creates its unit as today) | 60 target |

---

## 10. Config (config-first, `src/ReplicatedStorage/Shared/Configs`)

### 10.1 `ArmyConfig.luau` (new; requires only `AdminConfig` and `PlotFrame`)
```lua
local ArmyConfig = {
	-- Rollout per part: "off" = HEAD behaviour; "owner" = AdminConfig.IsPlaytestOwner only; "all" = everyone.
	Rollout = { Escort = "off", Army = "off", March = "off" },
	Home = { InsideMargin = 2, OutsideMargin = 14, EnterSeconds = 2, LeaveSeconds = 1 },
	Guard = {
		Enabled = true,
		SlotZ = 170, -- plot-local, out of the gate (wall line 158.5; L5 outer face 161.65)
		SlotX = { -30, 30, -36, 36, -42, 42, -48, 48 }, -- fill order; faces +Z
		ArriveStuds = 2, SideStepMax = 10, EngageRadius = 70, ReturnWalkMaxStuds = 400,
		OpenGateRadius = 12, -- own units open the friendly gate (GateDefenseService.updateFriendlyGate)
		FightRaiders = false, -- D1 (lane D)
		Raider = { Range = 55, Damage = 5, FireRate = 0.8, MaxShootersPerTarget = 3, MemorySeconds = 10,
			HoldFireWhenDefensesDown = true, Targetable = true },
	},
	Follow = { CatchUpStuds = 30, CatchUpSpeed = 18, VehicleHoldStuds = 150, VehicleHoldSpeed = 20 },
	Escort = { DefendRadius = 90, DefendLeash = 28, FocusFireSeconds = 6,
		SideStepAfterBlocked = 2, SideStepStuds = { 4, 8 }, SideStepMinGap = 1.5 },
	ShotFx = { Enabled = true, PerArmyMinGap = 0.25, PerRecipientHz = 6 },
	Hold = { PostSnapStuds = 30 },
	March = {
		Speed = 18, FightSpeed = 14, Spacing = 14, LeaderLeadMax = 8, RoadShoulder = 9.5, RoadLegsFrom = 4,
		SharedArmSide = { [1] = 1, [2] = -1, [3] = 1, [4] = 1, [5] = 1, [6] = -1 }, -- +1 right shoulder, -1 left
		WaitShortStuds = 60, FanStageStuds = 50, FanSpacing = 4,
		CaptureSlotLateral = { -6, -2, 2, 6 }, CaptureSlotAlong = { -5, 5 },
		HoldLineRadius = { 90, 96 }, HoldLineLateral = { -9, -3, 3, 9 },
		ContextRadius = 150, WaitEndSeconds = 120, WaitEndOwnerStuds = 400, NextDelay = 2,
		Clear = { Radius = 90, Leash = 60, EndSeconds = 3 },
		Bank = { Radius = 150, FanStuds = 45, GiveUpStuds = 250, GiveUpSeconds = 20 },
		Lanes = { -- world X, Z (§4.5): gate out, rally, FP, stage, Town Gate, Plaza edge
			[1] = { {-628,-400}, {-538.5,-415.9}, {-454,-219}, {-360,0}, {-310,0}, {-78,0} },
			[2] = { {-628,400}, {-536.9,340.7}, {-454,181}, {-360,0}, {-310,0}, {-78,0} },
			[3] = { {0,-628}, {33.2,-524.5}, {24,-454}, {0,-360}, {0,-310}, {0,-78} },
			[4] = { {0,628}, {-33.2,524.5}, {-24,454}, {0,360}, {0,310}, {0,78} },
			[5] = { {628,-400}, {536.9,-340.7}, {454,-181}, {360,0}, {310,0}, {78,0} },
			[6] = { {628,400}, {538.5,415.9}, {454,219}, {360,0}, {310,0}, {78,0} },
		},
	},
	Recover = { Enabled = true, FollowFarStuds = 150, FollowFarSeconds = 5, PathAfterSeconds = 3, StuckSeconds = 6,
		ProgressStuds = 2, CooldownSeconds = 8, PerOwnerPerSecond = 4, BehindStuds = 24, NoPlayerWithin = 25,
		MaxDeferSeconds = 10, VehicleDeferSpeed = 20, VehicleStopSpeed = 6, VehicleStopSeconds = 1.5,
		VehicleRegroupStuds = 150, ProbeDown = 12, FallY = -50, LogSeconds = 30 },
	Path = { Enabled = true, AgentRadius = 1.5, AgentHeight = 5, WaypointSpacing = 6, ComputesPerSecond = 2,
		QueueMax = 12, SquadMinGapSeconds = 2, GoalMovedStuds = 20, TimeoutSeconds = 2, StraightRecheckSeconds = 1,
		MaxWaypoints = 64, ReachStuds = 3 },
	Ui = { TileShowsMode = true, StatusHeight = 26, StatusSize = 20 },
	Text = { -- device-neutral; no key names, no "click" / "tap"
		Status = { Guard = "GUARDING BASE", Follow = "FOLLOWING", Hold = "HOLDING", HoldPost = "HOLDING POST",
			March = "TO %s", Fight = "FIGHTING", Capture = "TAKING POST", Wait = "WAITING FOR YOU",
			Return = "RETURNING", HoldLine = "AT THE CENTRE", Clear = "FIGHTING" },
		Tile = { Guard = "GUARD", Follow = "FOLLOW", Attack = "ATTACK", Hold = "HOLD", Return = "RETURN" },
		MovingOut = "Army moving out", Waiting = "Army waiting for you", TakeCentre = "Take the Centre!",
		Taken = "%s taken", UnderAttack = "%s under attack", NoBase = "No base to guard",
	},
}
```

### 10.2 `TerritoryConfig.Posts` (rows generated like the `Starter` loop; `IsPostDef(def)` helper)
```lua
Posts = {
	Enabled = false, -- builds the 10 rows and their kits (26 world parts)
	Live = "off", -- "off" | "owner" | "all": who counts / sees posts (others: kit hidden locally, not listed, not counted)
	MaxHeld = 3, ArmyMinUnits = 2, ArmyRate = 0.5, OwnerLeashStuds = 320, MaxHeightDelta = 14,
	OutnumberSeconds = 6, OutnumberMargin = 1,
	KeepAwayStuds = 600, KeepAwaySeconds = 600, MissionCooldownSeconds = 600, UnderAttackToastGap = 60,
	NeutralColor = Color3.fromRGB(170, 150, 100),
	Forward = { IdPrefix = "Post_FP", DisplayName = "Forward Post", Radius = 16, CaptureTimeSeconds = 8, StipendCash = 1000,
		RingTop = 0.58, PoleHeight = 14,
		Sites = { [1] = {-454,-219}, [2] = {-454,181}, [3] = {24,-454}, [4] = {-24,454}, [5] = {454,-181}, [6] = {454,219} } },
	TownGate = { IdPrefix = "Post_TG_", Radius = 18, CaptureTimeSeconds = 12, StipendCash = 2000, RequireClear = true,
		RingTop = 0.62, FlagY = 9.5,
		Garrison = { { Role = "Alarm", Type = "HeavyInfantry" }, { Role = "G1", Type = "Infantry" } },
		Ledger = 4, WakeOnFoot = 150, WakeArmy = 150, TargetZoneStuds = 60, HitBackSeconds = 10,
		SleepRadius = 400, SleepSeconds = 60, RegarrisonDelay = 60, RegarrisonClear = 100, Leash = 30, SpawnGap = 0.2,
		Sites = {
			N = { Name = "North Gate", X = 0, Z = -310, FlagX = 17.5, FlagZ = -308.4, Kit = "Town.CP_N" },
			E = { Name = "East Gate", X = 310, Z = 0, FlagX = 308.4, FlagZ = 17.5, Kit = "Town.CP_E" },
			S = { Name = "South Gate", X = 0, Z = 310, FlagX = -17.5, FlagZ = 308.4, Kit = "Town.CP_S" },
			W = { Name = "West Gate", X = -310, Z = 0, FlagX = -308.4, FlagZ = -17.5, Kit = "Town.CP_W" },
		} },
	Chain = { [1] = "W", [2] = "W", [3] = "N", [4] = "S", [5] = "E", [6] = "E" }, -- plot -> Town Gate arm
},
```
Each generated row carries:
- `IsPost = true`, `PostKind = "Forward" | "TownGate"`, and `PlotId` (FP only);
- `BonusType = "Post"`, `BonusValue = 0`, `StipendCash`;
- `ExactRadius = true`, `ArmyCounts = true`, `NoDressKeepOut = true`.

### 10.3 Changes to existing configs
- **`OrdersConfig`:**
  - `Orders.Guard = true`, `OrderLabels.Guard = "GUARDING"`; `Retreat` is kept as an alias of Guard;
  - `Walkie.SizeTouch = UDim2.fromOffset(216, 272)` (was 244), `PanelMaxHeight = 290` (was 260). At 800 × 360 real px
    the HUD is 514 v tall, so it fits (T10).
- **`CombatFairnessConfig`:** no number changes (the escort keys stay; the new numbers live in `ArmyConfig.Escort`).
- **`NukeConfig.IsTerritoryTargetable`:** false for `IsPost` rows (as for Home Outposts, `NukeConfig.luau:266-270`).
- **`WorldHygiene` H3 and `WorldDress` capture circles:** skip `NoDressKeepOut` rows, so the census is identical apart
  from the 26 post parts.

---

## 11. Files and build lanes (parallel where marked)

| Lane | Needs | File | Change |
|---|---|---|---|
| **A0 Escort and bank** (A5) | despawn fix merged | `Shared/Configs/ArmyConfig.luau` (new) | `Rollout`, `Escort`, `ShotFx`, `Text` |
| A0 | | `Server/Services/SquadOrdersService.luau` | Defend-when-targeted + focus fire + `DefendLeash` in the escort pick; side-step; shot FX sampler; per-pass NPC snapshot replacing the per-unit `GetTagged` |
| A0 | | `Server/Services/CombatService/init.luau` | `NPCsAimingAt(player)`, `LiveNPCSnapshot(out)` (no allocation), `UnitShotFx(unitId, origin, landed, kind)` wrapping `CombatFx.Bullet`, `LastHitBy` stamp in the player → NPC damage path |
| **A Guard and movement** (A1, A4) | A0 | `ArmyConfig.luau` | `Home`, `Guard`, `Follow`, `Hold`, `Recover`, `Path`, `Ui` |
| A | | `Server/Modules/ArmyGuard.luau` (new, pure, ≈ 60 lines) | Gate slot CFrames via `PlotFrame`; `OwnerHome(plotId, pos, margin)` |
| A | | `Server/Modules/ArmyPath.luau` (new, ≈ 180 lines) | Budget queue, compute, cache, `Blocked`, waypoint helper, join-node pick |
| A | | `SquadOrdersService.luau` | Guard order + Retreat alias; HOME / OUT hysteresis; GUARD / RETURN / HOLDPOST; `moveUnit` + stuck check; RECOVER (§6.5, or the fix lane's copy); spawn on the gate slot; catch-up speed; vehicle hold; payload `Mode`, `Status`, `Target` |
| A | | `Server/Services/GateDefenseService.luau` | `updateFriendlyGate`: the owner's own units within 12 open it |
| A | | `Client/Controllers/OrdersController.luau`, the rail tile owner (`UIController` / `HUDController`) | GUARD cell (RETREAT for non-live), status line, tile mode word, cycle Attack → Hold → Follow → Guard, ObjectiveMarker `ShowWith` on an ATTACK `Target` |
| A | | `Shared/Configs/OrdersConfig.luau`, `Shared/Types.luau` | §10.3; payload fields |
| **B Posts** (A3), parallel with A0 / A | capture lane merged | `Shared/Configs/TerritoryConfig.luau` | `Posts` block, generated rows, `IsPostDef` |
| B | | `Server/Modules/MapSetup.luau` | 3-part FP kit, 2-part TG kit (flag on the booth roof), Atomic model, `WE_PostKit` tag |
| B | | `Server/Services/TerritoryService/TerritoryCapture.luau` | `ExactRadius`; strong / weak presence, `ArmyRate`, outnumber, `RequireClear` freeze; army provider `SetArmyPresence(fn)`; live filter |
| B | | `Server/Services/TerritoryService/init.luau` | Posts excluded from `syncProfileOwnership` / Empire Tax / `MaxPersonalTerritories` / ClanWar / `Stats.TerritoriesCaptured`; player-only ownership; `MaxHeld` + oldest release; keep-away expiry; mission cooldown; under-attack toast; `LocalCapture.ByArmy`; live filter in the payload |
| B | | `Server/Services/TerritoryService/TerritoryRadar.luau` | `ShownTo` hides posts from non-live viewers |
| B | | `Server/Services/PostService.luau` (new, ≈ 300 lines) | Chain; army presence provider (reads `SquadOrdersService.UnitsOf(userId)`); garrisons (wake, ledger, sleep, re-garrison, Ops fail-closed) |
| B | | `CombatService/init.luau`, `CombatService/CombatNPC.luau` | `SpawnNPC` opt `TargetZone`; target pick filtered to the zone + hit-back list |
| B | | `Server/Modules/WorldDress.luau`, `WorldHygiene.luau` | Skip `NoDressKeepOut` rows |
| B | | `Shared/Configs/NukeConfig.luau`, `Server/Services/EconomyService.luau` | Skip posts (Empire Tax belt-and-braces, next to `isStarterId`) |
| B | | `Client/Controllers/TerritoryController.luau` | Own chain posts only; `ARMY · <NAME>` title when `ByArmy`; hide `WE_PostKit` kits locally for non-live viewers |
| B | | `Server/Bootstrap.server.luau` | `safeInit("PostService")` after TerritoryService, CombatService and SquadOrdersService (after `DataService.Init`) |
| **C ATTACK march** (A2) | A + B | `SquadOrdersService.luau` | CLEAR / MARCH / FIGHT / CAPTURE / WAIT / HOLDLINE / bank fan; toasts; target provider injected by PostService (no require cycle) |
| C | | `PostService.luau` | `NextTarget(player)`; fan, capture and hold-line slot geometry |
| **D Gate army vs raiders** (D1, dark) | A | `GateDefenseService.luau` | `IsRaiderOf(plotId, player)`, `DefenseHit(plotId, player, dmg, source)`, `GuardUnitShot` |
| D | | `CombatService/init.luau` | `RequestFire` may hit enemy `WE_GuardTargetable` units (no pay) |
| D | | `Client/Modules/AimTargets.luau` | `WE_GuardTargetable` enemy units count as hostile |
| **E Garrison fire at units** (v1.1, dark; D8) | C | `CombatNPC.luau`, `SquadOrdersService.luau` | Garrison may target army units attacking its gate (LOS + `HitChance`); `ApplyArmyHit(unitId, dmg)`; flag `Posts.TownGate.Garrison.HitsUnits = false` |
| all | | `tools/BuyPathStatic.py`, `ASSUMPTIONS.md` | Pins (§15), ARMY-1..10 |

**Order:**
- the despawn fix → **A0** → **A**;
- **B** in parallel from the capture lane's base;
- **C** after A and B; **D** after A; **E** after C.

**Size [estimate]:** A0 ≈ 250 lines, A ≈ 600, B ≈ 650, C ≈ 450, D ≈ 250, E ≈ 250. About 5–6 builder-days plus review.
One integrator merges SquadOrdersService (touched by the fix, A0, A, C, E).

---

## 12. Tests (CLAUDE.md §3 gates on every changed file, plus these; **pass criteria in bold**)
| # | Test | How (headless stand-in unless marked) | Pass |
|---|---|---|---|
| T0 | Gates | `luau-compile --binary` per changed file; `luau-lsp analyze` vs HEAD with the sourcemap; `LUAU_COMPILE=… BuyPathStatic.py`; headless world sim; DataService harness | **0 parse errors, 0 new lsp errors, BPS 0 failures, every world step ok, DS all pass** |
| T1 | World geometry | `final_geo.py` / `fun_geo.py` as a world-sim driver on a new dump with posts on: 6 plots × walls L0 / L2 / L5 with **real** GateDefense nests and PlotOilPump pumps; sites, lanes, fans, slots; census; H3 report | **+26 parts, 0 collidable; census identical apart from those 26; H3 destroys 0 parts; busiest 512 circle ≤ 488 static (≤ 495 with crates and bags); gate slots ≥ 3 body clearance (5.6 today); lanes: desert ≥ 30, road ≥ 13, 0 blocked samples; FP3 / FP4 ring edge ≥ 1 off the carriageway; every TG garrison post seen from every fan slot** |
| T2 | State machine | Real SquadOrdersService + BaseService plot pads (squadfair walker, `squadfair/w4/run_drv.sh`) | **HOME → GUARD ≤ 2.5 s; OUT → FOLLOW ≤ 1.5 s; standing at local Z 170 keeps GUARD; GUARD order while out → RETURN → GUARD → automatic at the next HOME; HOLD unchanged; HOLDPOST on a post; Retreat alias; recruits on gate slots; automatic switches never end the novice shield** |
| T3 | **The owner's 500-stud test** | Full army (8 units), the diagnosis lane's destroy / reparent catch-all left on: walk 600 studs out of the gate through the Town (doorways, market lane) into open desert; drive 700 at 60 studs/s; die; teleport; repeat with `Rollout.Army = "all"` | **On the SERVER, every sample: 8 of the original 8 ids alive and parented to `Workspace.WarEmpireSquads`; `destroyUnit` only on PlayerRemoving; 0 RECOVERs while the vehicle moves faster than 20 studs/s; 0 recovers into another plot, water or within 25 of another player; after the owner stops, every unit within 150 of him in ≤ 10 s** |
| T4 | Walls | Walker model with real geometry: FOLLOW through the Town, RETURN from the rear and sea gates, bank fan, TG fan (stub `ArmyPath` with a 4-stud walk grid on the stand-in) | **Wall contact (goal > 6 away, progress < 0.5 in 1 s) ≤ 1 s per unit per 100 studs walked; 0 RECOVERs on the fixed lanes; paths ≤ 2/s server-wide** |
| T5 | Bank | Bank prelude with real geometry (`ownerfb/bank/runbw.sh`, `drv/body_window.luau`): owner walks to the bank in FOLLOW and stops 70 from a guard | **First unit shot at a guard aiming at the owner in ≤ 3 s; > 0 unit hits in 20 s; ≥ 1 WeaponFx per 0.5 s per army while firing, ≤ 6/s per recipient; ATTACK kills pay $0; focus fire engages an NPC the owner hit at 85** |
| T6 | Posts | Real TerritoryService + CaptureStipendService + PostService | **Army alone: 16 s FP with the owner at 300 (yes), 340 (no), in his base for his own FP (yes); a rival player on an army-held ring captures at ×1 (army ignored); outnumber after 6 s, tie frozen; TG `RequireClear`; `MaxHeld` 3 releases the oldest; `ReleaseOnLeave`; no re-plant on rejoin; Empire Tax and `MaxPersonalTerritories` unchanged; stipend $1,000 / $2,000 per 90 s, reason `capture_stipend`, player-owned only; mission +1 ≤ once per 600 s; under-attack toast ≤ 1 per 60 s; keep-away expiry at 600 s** |
| T7 | Garrisons | 6 owners ATTACK at once; a driver passes each awake gate at 40 studs/s on the road; a player snipes from 80 | **≤ 4 garrison NPCs alive; alive NPCs ≤ 22; a full ledger leaves a gate capturable; the passing driver is never targeted (0 shot rolls outside 60); the sniper is targeted within 10 s of hitting one; an enabled Ops `Town.CP_*` site turns that post off (logged once)** |
| T8 | ATTACK flow | P1, P3, P5 owners | **Target order CLEAR → FP → TG → hold line; WAIT at > 320 with 1 toast; 120 s → automatic; bank context at 150; repeat tap in 2 s changes nothing; the GO line points at the payload target, never a fixed marker; P1 / P2 files on opposite shoulders at the West Gate** |
| T9 | D1 (flag on) | Raider (ATM hold), gate attacker, intruder, ally, novice, spawn-grace player, passer-by 40 from the gate, defenses down | **Only the raider, attacker and intruder are shot; ≤ 3 shooters; hit ratio within ±5 % of the NPC curve over 600 shots; hold fire while defenses are down; a raider can down a guard unit, which re-forms on its slot in 8 s; damage only via `DefenseHit`** |
| T10 | HUD | `check_hud.py --viewports phone,owner,desktop` + 800×360 + 1180×820, with data: the popover (GUARD cell, status line), the tile word, the capture bar `ARMY · NORTH GATE`, the GO line, toasts | **Tap targets ≥ 64 v, text ≥ 20 v; nothing tappable in the left 40 % × lower ⅔ except the rail; nothing within 16 px of jump; one message at a time; no key names on touch** |
| T11 | Load | 6 owners, 48 units, 4 garrison NPCs, 10 min of mixed orders | **Server ops per think within 1.2× HEAD; remotes ≤ 20 Hz per player; 0 per-frame allocations in OrdersController / TerritoryController; no `GetTagged` / `GetDescendants` per unit per think** |
| T12 | Off switches | All `Rollout` parts `"off"`, `Posts.Enabled = false`; then `"owner"` with a second, non-owner player | **Byte-identical HEAD behaviour and census with everything off; with `"owner"`, the non-owner's army and HUD are HEAD's and he neither sees nor counts on posts** |
| T13 | Lane E (flag on) | Garrison vs an attacking army | **Garrison shots at units need LOS + `HitChance`; units re-form in 8 s beside the rearmost unit; 0 shots at units not attacking that gate** |

**Needs Studio or a phone (not claimed by any test above):**
- Humanoid physics in the gate line and the road-shoulder file.
- PathfindingService results on the Town meshes (`MeshCollide = true`), and its cost in the microprofiler.
- Server heartbeat with 86 Humanoids.
- Frame time on a mid-range Android at Graphics Quality 3 with 6 armies.
- The look of the gate line, posts and tracers from the phone camera.
- Readability at 956 × 440.
- The live place's `Workspace.StreamingEnabled`.

---

## 13. Rollout (flags, order, rollback)
| Stage | Flags | Who sees what | Owner phone test |
|---|---|---|---|
| 0 (ships dark) | All `Rollout` `"off"`, `Posts.Enabled = false`, `FightRaiders = false`, `HitsUnits = false` | HEAD behaviour for everyone (T12) | — |
| 1 (bank fix) | `Rollout.Escort = "owner"`, then `"all"` | Escorts shoot back, with tracers | §16 step 1 |
| 2 (guard + movement) | `Rollout.Army = "owner"`, then `"all"` | Gate line, follow outside, RECOVER, paths, GUARD cell | §16 steps 2–5 |
| 3 (posts + ATTACK) | `Posts.Enabled = true`, `Posts.Live = "owner"`, `Rollout.March = "owner"`, then both `"all"` | 26 parts built for everyone; non-live clients hide the kits locally and the server neither lists nor counts posts for them | §16 steps 6–9 |
| 4 (D1) | `Guard.FightRaiders = true` | Gate army vs raiders | §16 step 10 (with a friend) |
| 5 (Lane E) | `Garrison.HitsUnits = true` | Garrisons fight back at units | after v1 is stable |

**Prerequisites:** the despawn fix before stage 2; the capture lane before stage 3.

**Rollback:** set the part back to `"off"` / `false`. `Posts.Enabled = false` removes the rows and the 26 parts at the
next server start. Nothing is saved to profiles: no DataStore change and no migration.

---

## 14. Risks
| Risk | Mitigation |
|---|---|
| RECOVER looks like "despawning" (the owner's complaint) | Only after 150 studs for 5 s, or stuck 6 s after a failed path. Never while the owner drives fast, never within 25 of another player. Lands ≥ 24 behind the owner (behind the camera) and runs in, staggered 4/s. At most 1 per unit per 8 s. Counted in `WE_ArmyRecover` |
| The despawn cause turns out to be client-side (camera LOD / streaming) and not server-side | The diagnosis lane owns it. This spec's catch-up (18 vs 16) and RECOVER keep units within the escort / LOD range either way. T3 checks server truth; the phone test checks what is drawn |
| Units stall in the Town or at the gate barrier (real physics) | Fixed measured lanes; the friendly gate opens for own units; squad paths; RECOVER last; Studio check |
| PathfindingService cost or quality on mesh buildings | 2 computes/s; the straight probe first; the lanes need none; microprofiler before stage 2 goes `"all"` |
| Busiest 512 circle at 488 (495 with transients) | T1 pin; any future part in the (160, 160) circle must free one first |
| Garrisons crowd out camp respawns (they use the +4 headroom above 18) | Ledger 4; sleep after 60 s; logged. Camps refill as soon as garrisons sleep |
| Fights are easy in v1 (garrisons cannot hurt units) | They still shoot players in their zone; Lane E adds fire at units behind a flag |
| AFK stipends | Owner leash 320 for army captures; keep-away expiry 10 min; session-only; small stipends (≤ 55.6 $/s); players beat armies |
| Town Gate on a road: passing drivers contest the ring | As for every zone today; a car crosses the 36-stud ring in under 1 s (one tick). Garrisons ignore them (`TargetZone`) |
| A neighbour griefs your Forward Post | 189–288 studs from your gate (outside the gate guns); the under-attack toast (≤ 1 / 60 s); ATTACK retakes it |
| Merge conflicts: SquadOrdersService (fix, A0, A, C, E), Territory files (capture lane, B) | Strict order (§11); one integrator |
| Jobs cutover reuses the +4 headroom and the Town CP kits | Posts fail closed per kit when an Ops `Town.CP_*` site is on; the ledger moves to `OpsGarrison` at the cutover (a checklist item) |
| D1 changes PvP (8 more shooters at a gate) | Off by default; the gate guards' own raider rule; ≤ 3 per target; NPC hit curve; own base only; hold fire when defenses are down; units become targets |

---

## 15. Owner decisions, pins, assumptions

| # | Question | Default |
|---|---|---|
| D1 | May your gate army shoot raiders at your base (and be shot back)? | **Off** until you test it with a friend |
| D2 | Stipends: Forward Post $1,000 and Town Gate $2,000 per 90 s, max 3 held? | Yes |
| D3 | Guards at Forward Posts too? | No (Town Gates only) |
| D4 | Your army takes posts only while you are within 320 studs (your own Forward Post from your base)? | Yes |
| D5 | After a capture, ATTACK goes on to the next post (FP → Gate → Centre edge)? | Yes |
| D6 | May an army take the Central Plaza on its own (at half speed)? | No |
| D7 | Deploy to a held post and respawn at the front? | Later (v1.1) |
| D8 | Town Gate guards shoot back at your soldiers (Lane E)? | Later, behind a flag |

**BuyPathStatic pins (each shown failing on a mutant):**
- `ArmyConfig.Rollout` all `"off"`; `Guard.FightRaiders = false`; `Posts.Enabled = false`; `HitsUnits = false`.
- `Guard.SlotZ = 170` and the 8 `SlotX` values; `OutsideMargin = 14`.
- Kits: FP 3 parts, TG 2 parts, 0 collidable; `ExactRadius` on post rows.
- `MaxHeld = 3`, `OwnerLeashStuds = 320`, `ArmyRate = 0.5`; players beat armies in `TerritoryCapture`.
- Posts are excluded from `syncProfileOwnership`, Empire Tax, `MaxPersonalTerritories`, ClanWar and nuke targets; no
  `dressOutpostFlag` / nation flag on posts.
- `UnitKillCreditOnAttack = false` untouched; `ApplyUnitHit` still refuses players; D1 damage only via
  `GateDefenseService.DefenseHit`.
- `ArmyPath` has no `RenderStepped` / `Heartbeat`; `moveUnit`, `ArmyPath` and RECOVER never call `Destroy`.
- `RequestSquadOrder` payload is a string only; no client-named target; no GiveCash / GiveXP remote; no new AddCash
  reason.
- `Escort.MaxPerClient = 22` unchanged; existing SquadOrdersService pins unchanged.

**ASSUMPTIONS.md (ARMY-1..10):**
1. automatic FOLLOW / GUARD with hysteresis 2 / 14;
2. a GUARD order goes back to automatic at the next HOME;
3. posts are session-only, with no tax and no persistence;
4. owner leash 320;
5. a player beats an army; army alone ×0.5; outnumber between armies;
6. the TG flag stands on the booth roof and FP3 / FP4 sit at x ±24;
7. an `OverCap` garrison ledger of 4 with `TargetZone` 60;
8. D1 off;
9. RECOVER replaces every destroy-on-distance;
10. the rollout parts `"off"` / `"owner"` / `"all"`.

---

## 16. The owner's phone test (landscape; your phone, then a mid-range Android at Graphics Quality 3)
1. **Bank (stage 1).** Walk to the Empire Bank with your army and stop where the guards start shooting you.
   - Your soldiers shoot back within a few seconds, you see their tracers, and they step out from behind the planters.
2. **Home.** Spawn in your base and walk to the front gate.
   - Up to 8 soldiers stand in a line outside, 4 each side of the road, facing out, with extra figures in front.
   - Nothing blocks the gate lane or the car path to your garage pad.
   - The Army tile reads `GUARD`.
   - Walk out and stand among them: they stay.
3. **Leave.** Walk further out.
   - About a second later they follow you, beside you and not between you and the camera. The tile reads `FOLLOW`.
   - Walk back in: after 2 s they return to their line.
4. **Drive.** Take the car from your garage pad and drive 500+ studs through the Town into the desert, then stop.
   - Within about 10 s they are all back behind you. None pops up in front of you, none is missing, and the popover
     reads `ARMY 8/8 · FOLLOWING`. Screenshot it.
5. **GUARD.** Out in the desert, open the Army popover and tap GUARD.
   - They walk (or, from far away, regroup) back to your gate line, and the status reads `GUARDING BASE`.
6. **ATTACK from home.** At home, tap ATTACK.
   - One GO line to your Forward Post. The army files out, and the bar reads `ARMY · FORWARD POST`.
   - After about 16 s the flag turns your colour, and you get one toast.
7. **Waiting.** Stay home.
   - The army walks on toward your Town Gate and stops short with `WAITING FOR YOU` (one toast).
8. **Town Gate.** Drive there.
   - The 2 gate guards wake. Your army lines up across the road, fights, and takes the ring.
   - Then it walks down the road edge in single file (not into the booth or sandbags) to the Centre's edge:
     `Take the Centre!`.
   - Drive past another awake gate on the road: its guards do not shoot you.
9. **Hold.** Tap HOLD at a post, and the army spreads round the flag.
   - With a friend: your friend stands on your Forward Post and takes it in 8 s even with your army there. You get
     `Forward Post under attack` once.
   - Leave and rejoin: your posts are neutral again.
10. **(Only if you say yes to D1)** Your friend (not in your clan) attacks your gate while you are home.
    - Your line shoots him with tracers, and he can shoot your soldiers down (they come back on their spots).
    - They never shoot him while he just drives past, when he is your clan-mate, or right after he spawned.

Tell us if any soldier disappears, walks into a wall for more than a moment, blocks a car, stands inside a building, or
if anything stutters on the Android.

---

## Appendix: reproducible numbers
- **Dump:** `bash $S/assetwire/integ/run1.sh mvpdump <git archive e506c9c> army/design/mvp/work/dump_drv.luau` →
  `assetwire/integ/runs/mvpdump/out.txt` (4,746 parts, 3 steps ok). FUN's copy: `army/design/fun/work/dump.txt`.
- **Lanes, slots and the MVP 3-part circle budget with FP3 / FP4 at ±24:**
  `python3 army/design/final/final_geo.py assetwire/integ/runs/mvpdump/out.txt` → `army/design/final/final_geo.txt`.
  Key lines:
  - lanes 825 / 775 / 559;
  - desert ≥ 31.9, road 13.4;
  - worst guard-slot body clearance 5.6;
  - FP3 / FP4 clear 137.1 / 65.4.
- **Circle budget with the final kits:**
  `FP_KIT=3 TG_KIT=2 python3 army/design/fun/work/fun_geo.py army/design/fun/work/dump.txt` →
  `army/design/final/geo_fp3_tg2.txt`:
  - `R512 busiest now (160, 160) = 471 ; with the kits (160, 160) = 488 (cap 500)`;
  - `R1024 … = 917`;
  - `Parts outside the bases: now 2430; + FP 18 + TG 8 = 2456`;
  - H3 dressing inside each TG circle: 9 / 9 / 10 / 10 `POI_Town` parts.
- **Booth roofs** (flag positions) from the dump rows `POI_Town.CP_<x>.BoothRoof`.
- **Map sketch:** `python3 army/design/final/map.py` → `army/design/final/map.txt`.
- **Stand-in lifecycle evidence:** `army/diag/root1/results.txt` (10 movement scenarios + 1 catch-all control; the
  diagnosis lane's verdict is pending).
