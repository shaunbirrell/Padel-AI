# Army lane B (checkpoint posts): assumptions

Every item below can be undone. The main switch is `TerritoryConfig.Posts`. Set `Enabled = false` to get exactly
today's build (no rows, no kit, no PostService, MAP_GEN 93). Set `Live = "off"` to keep the kits in the world but
hide and ignore them for everyone.

Fix round 1 changed ARMY-B-9, -10, -11, -16, -18, -21 and -22, and added ARMY-B-25 to ARMY-B-31.
Fix round 2 changed ARMY-B-9, -17, -27 and -30, and added ARMY-B-32 to ARMY-B-37.
Fix round 3 changed ARMY-B-1, -9, -16, -26, -30, -32, -33 and -37, and added ARMY-B-38 to ARMY-B-41.

- **ARMY-B-1 Rollout.** This ships with `Posts.Enabled = true` and `Posts.Live = "owner"`. Only the owner's playtest
  account (UserId 470626172, `AdminConfig.IsPlaytestOwner`, the same pattern as `AircraftWeaponConfig.LiveFor`) can
  see, list or count on posts. Everyone else plays today's game:
  - their client removes the 26 kit parts and any Town Gate guard models (see ARMY-B-16);
  - the server never lists a post to them;
  - they and their army never count on a ring;
  - they never wake a garrison, and they cannot hurt, farm or provoke one (ARMY-B-10).

  The 26 parts, and the guards while the owner has a gate awake, still replicate to every client before that client
  removes them. Fix 3: on the server the guards are not in his way either (ARMY-B-33): his shots, his claims and NPC
  shots at him pass through the guards his client removed.
- **ARMY-B-2 Session-only.** A post is never written to `profile.Territories`. A leaver's posts go Neutral at once
  (`ReleaseOnLeave`), and nothing is re-planted on rejoin. Posts never add to:
  - Empire Tax (EconomyService also ignores post ids, as a second safeguard);
  - `MaxPersonalTerritories`, and the eviction loop never releases a post;
  - ClanWar;
  - `Stats.TerritoriesCaptured`;
  - XP or the tutorial.

  A post is never a nuke target.
- **ARMY-B-3 Pay.** Posts pay only through the existing CaptureStipendService (`def.StipendCash`): $1,000 for a
  Forward Post and $2,000 for a Town Gate, every `CaptureStipend.TickSeconds` (90 s). The reason is `capture_stipend`,
  so there is no new AddCash reason. Posts are always player-owned (`rt.ClanId = nil`), so a clan mate is never paid.
  A garrison kill by a live player pays CombatService's normal NPC reward.
- **ARMY-B-4 Missions.** Taking a post counts +1 toward the existing `CaptureTerritory` mission, at most once per post
  per player every 600 s. MissionService's own daily caps still apply.
- **ARMY-B-5 Progress carries over, as today.** If the capturer changes (player to player, or army to player),
  progress is not reset. It decays only while nobody counts. This is the same as the current tick for every other zone.
- **ARMY-B-6 Players beat armies.**
  - Two or more players on a ring: contested (frozen, decaying at `ContestedDecayMult`), and armies are ignored.
  - One player: he captures at x1.
  - An army alone: its owner captures at x0.5.
  - Two or more armies and no player: the one ahead by at least 1 unit captures after 6 s; a tie stays frozen
    (`Blocked`).
- **ARMY-B-7 When an army counts.** An army counts when all of these hold:
  - its owner is live, alive, and within 320 studs of the post (for his own Forward Post, anywhere inside his own
    320-stud plot square);
  - it has at least 2 living units;
  - those units have their root within the ring's flat radius and within 14 studs of the ring's height.

  Units come from `SquadOrdersService.UnitsOf`, a new read-only accessor. This lane has no ATTACK march (that is
  lane C). An army captures alone only when its units are already standing on a ring while the owner stays within
  320 studs (for example with a hold order). `PostService.SetArmyWake` is the hook lane C sets so an ATTACK march
  wakes a gate.
- **ARMY-B-8 Exact rings.** Posts count `def.Radius` exactly (16 / 18 studs, the visible ring, via `ExactRadius`),
  not the marker's half-diagonal that other zones use.
- **ARMY-B-9 Garrison ledger and the NPC cap (changed in fix 1 and fix 2).** At most 4 garrison NPCs are alive
  server-wide (`TownGate.Ledger`). They spawn with `OverCap`. Fix 2: only a **garrison** spawn counts garrison NPCs.
  Every other spawn (regular camp NPCs against the 18, bank / oil rig / fort guards and OverCap event NPCs against
  18 + 4) has its cap lifted by the number of garrison NPCs alive (`aliveGarrisonCount`), so it sees exactly HEAD's
  numbers while a garrison is awake: a camp NPC or bank guard that dies still comes back on time, and the specials'
  +4 headroom (CombatConfig: "so bank always gets guards") is intact. A garrison spawn itself counts every NPC against
  18 + 4. With no garrison alive every check is byte-identical to HEAD. Lane N's pinned cap line is unchanged. The
  total stays at 22 today (13 camp + 5 bank + 4 garrison, Jobs OFF); see ARMY-B-37 for the Jobs-on worst case. When
  the ledger is full, a woken gate stays unguarded and can be captured on time alone; this is logged once per gate
  (spec §5.5, unchanged; see ARMY-B-27). Fix 2: if CombatService refuses every guard of a wake at its cap, the refusal
  is logged once and the gate goes back to "armed" (never a silent "cleared") and retries every
  `TownGate.CapRetrySeconds` (5 s) while a live player or army is near; the guards come as soon as a slot frees. While
  it has no guard alive the gate is capturable, the same as a full ledger. Fix 3: while the Ops master switch is on
  (`OpsConfig.Enabled`, Jobs / events) the ledger is `TownGate.LedgerJobsOn` = 2 (ARMY-B-37), and a guard CombatService
  no longer runs leaves the ledger on the next tick (ARMY-B-40).
- **ARMY-B-10 Who a garrison shoots, and who can fight it (changed in fix 1).**
  - It shoots players on foot within 60 studs of the gate who are live for posts.
  - It also shoots players who hurt one of that garrison in the last 10 s. This is the hit-back list, stamped
    server-side in `hurtNPC` from the attacker the server already resolved, never from a client id.

  A seated player (a driver on the road or parked on the ring) is never picked unless he hits them. Shots from the
  player's squad units do not add him to the hit-back list. Every shot still goes through today's line-of-sight and
  hit-chance checks. Fix 1 adds `zoneBars`: a player whom the garrison's `TargetZone.Eligible` filter rejects (not
  live for posts) cannot hurt it. For such a player:
  - his hits do nothing: no damage, no hit-back stamp, no kill pay;
  - his squad may not hit it (`unitMayHit`, so `UnitMayHitNPC` is false and his squad does not aim at it);
  - server aim assist never snaps his shot to it.

  With `Live = "all"` everyone is eligible, which is the spec's behaviour.
- **ARMY-B-11 Garrison life cycle (changed in fix 1).**
  - **Wake:**
    - any live player within `WakeStuds` 150, **on foot or seated** (renamed from `WakeOnFoot`). A driver who parks on
      the ring can no longer take the gate without clearing the guards. They still never shoot him while he stays
      seated, and they appear while he is still about 150 studs out, not next to him when he steps out;
    - an army that counts in the ring (the capture tick's own rule: 2 or more units in the ring, owner live, alive and
      within 320 studs), so an army cannot take a gate unguarded either. An army waiting outside the ring never wakes
      a gate;
    - the lane C hook.

    The spec's §5.5 wake is "a player on foot within 150". This is a deliberate deviation, to close the two bypasses.
  - **Guards:** while one lives, `RequireClear` freezes the ring for everyone, and the bar reads
    "CLEAR GUARDS · NAME".
  - **Sleep:** after 60 s with no live player or army within 400 studs and no hits, they despawn silently (no pay).
  - **Cleared:** when all are dead, the gate can be taken. It re-arms 60 s after it is Neutral again, once nobody is
    within 100 studs.
  - **Held:** a held gate never has a garrison.
  - Leash is 30 studs; spawns are 0.2 s apart.
  - They stand at the Town kit's activity anchors: `Town.CP_<arm>.Alarm` (HeavyInfantry, by the booth) and `.G1`
    (Infantry, across the road by the sandbags). `G2` is unused.
- **ARMY-B-12 Ops fail-closed.** While `OpsConfig.SiteSwitchedOn("Town.CP_<arm>")` is true, that post is "off": no
  garrison and nobody counts. This is logged once. Two garrisons therefore never share one kit.
- **ARMY-B-13 Kits.**
  - A Forward Post has 3 parts: a flat ring (which is also the capture marker, top at 0.58), a 14-stud pole, and a
    5.5 x 3.2 flag.
  - A Town Gate has 2 parts: the ring (top 0.62) and a flag standing on the checkpoint booth roof, turned to face
    arriving traffic.
  - All parts are CanCollide, CanQuery and CanTouch false. There are no lights, Neon, SurfaceGuis, decals or
    textures, so never a nation flag.
  - Each kit is one Atomic model tagged `WE_PostKit`.
  - Each post has one stud-scaled `WE_ZoneLabel` (MaxDistance 40, never AlwaysOnTop).
  - The flag shows only the holder's banner colour. Posts get no diamond `WE_FlagBillboard`.
- **ARMY-B-14 Dressing and budgets.** Post rows are `NoDressKeepOut`: WorldDress keeps its dressing around them, and
  WorldHygiene H3 does not treat them as clear zones. The world census is unchanged apart from +26 parts outside
  bases. Lights, Neon and SurfaceGuis are unchanged.
- **ARMY-B-15 MAP_GEN.** MAP_GEN goes up by 20 only while `Posts.Enabled` (93 to 113), so a baked map without the kits
  gets rebuilt.
- **ARMY-B-16 Client hiding (changed in fix 1).** A viewer who is not live removes every `WE_PostKit` model and every
  Town Gate guard model (`Posts.TownGate.GuardTag` = `WE_PostGuard`, which PostService puts on each garrison model)
  locally. This covers the models present at Init and any that stream in or spawn later, through the tag signal and a
  `task.defer` Destroy. The server side matches it: the guards' tracers never reach him (fix 2, ARMY-B-32), and the
  server's rays for him skip the guards (fix 3, ARMY-B-33). The T12 client check also shows that no guard part is left
  in his workspace.
- **ARMY-B-17 Territory list (changed in fix 2).** A viewer's list shows his own chain (his plot's Forward Post plus
  the Town Gate on his road, `Posts.Chain`) and any other post he holds, so a post that keep-away can take from him is
  one he can see. While his plot is unknown, it shows only posts he holds. The server sends all 10 posts to
  a live viewer. The header count ("2/14") includes the listed chain posts.
- **ARMY-B-18 MaxHeld and keep-away (changed in fix 1).**
  - A 4th capture silently releases the holder's oldest post (by HeldSince).
  - A holder who has not been within 600 studs of a post for 600 s loses it.
  - Fix 1: his own chain, both his Forward Post and his Town Gate (`TerritoryConfig.PostChain(his plot)`), never
    expires while he is inside his own plot. A base's far corner is 634-652 studs from its Town Gate, so an upgrade
    session at home used to drop the Gate. Another chain's Gate is not exempt. This is more generous than spec §5.4,
    which exempts only the Forward Post.
  - He gets a "<name> lost" toast when someone takes a post from him or when it expires. There is no toast for
    MaxHeld releases or on leave.
- **ARMY-B-19 Under-attack toast.** The holder gets a toast at most once per post per 60 s, and never while he lost
  health in the last 3 s. Toasts use short texts from config: "%s taken", "%s lost", "%s under attack". They name no
  key and no nation.
- **ARMY-B-20 Capture bar.**
  - "ARMY · NAME" while his army is capturing (`LocalCapture.ByArmy`). An army entry never overrides his own capture.
  - "CLEAR GUARDS · NAME" (amber) while he stands on a guarded gate, on foot or seated.
  - Otherwise the capture lane's titles (CAPTURING / CONTESTED / YOURS; YOURS is the capture lane's 5 s cue).
- **ARMY-B-21 Tutorial (changed in fix 1).** No tutorial step, pointer or objective marker points at posts. This is
  now enforced: both Outpost resolvers in TutorialController (`nearestOutpost` and the streaming `outpostFromConfig`)
  skip `TerritoryConfig.IsPostDef` rows, for every viewer. Taking a post fires no tutorial event, so a beam on a post
  could never finish the step anyway.
- **ARMY-B-22 Other lanes' switches (changed in fix 1).**
  - `Posts.TownGate.Garrison.HitsUnits = false` now exists in this lane's TerritoryConfig, at the spec's path
    (spec Lane E, D8: garrisons never shoot squad units). It is pinned false.
  - `FightRaiders` belongs to `ArmyConfig.Guard` (spec D1, lane D, not built). Lane FIX's and lane A0's ArmyConfig
    files do not define it. The pin therefore accepts "absent or false" in whichever ArmyConfig is present.
  - A second pin fails if either key is `true` anywhere in `src/` (comment-stripped).
- **ARMY-B-23 T7 driver.** Lane C's ATTACK is simulated with `PostService.SetArmyWake(true)` plus the 6 owners on
  foot about 110 studs out on their road. The driver sets `Posts.Live = "all"` so all 6 owners are live; shipping
  stays "owner". Scenario F switches to "owner" and joins the owner's playtest id for the live-filter checks. The
  player's own shots in T7 use exact aim through `CombatService.RequestFire`.
- **ARMY-B-24 Lane test copies.** Two lane Z/capture drivers (`k1_driver_cap`, `k1_driver_z`) count "the 11 existing
  territories". The post rows raise that count to 21, so the lane copies (`drv/k1_driver_*_b.luau`) skip IsPost rows.
  They are otherwise unchanged. The originals run unchanged and identical to base with `Posts.Enabled = false`.
- **ARMY-B-25 Rebased on the capture lane's fix 1 (new).**
  - The base is now `fb4/capture/cand` after its fix round 1: `StandingBar.OnDisc` / `HeldSeconds`, the pulse
    throttle, and Contested going back to Neutral.
  - `tickPost` sets `rt.Standing = rt.Inside`. The capture lane's standing bar now reads `Standing`, and a post's
    counted ring is its visible disc (`ExactRadius`). YOURS on a post is therefore the same 5 s cue as on every zone.
  - The capture lane's `applyCapture` needle `(localCap.Capturing or standingShown(localCap))` is kept verbatim;
    `Guarded` is OR-ed around it.
- **ARMY-B-26 CombatNPC target pick unchanged (kept in fix 3).** The reviewers' clean-up (skip `NearestPlayer` for a
  TargetZone NPC, raised again as a Low in round 3) was not done. The three lines it would reorder are pinned verbatim
  by squadfair v3 in main's BuyPathStatic ("a stance NPC targets the nearest player, as on HEAD", `tools/BuyPathStatic.py`
  line 6784 of main), so the change would break a HEAD pin owned by another lane. The extra scan costs 1 player loop per
  garrison NPC per think (0.35 s), 4 NPCs at most; garrisons have no GroupId, so the discarded result never touches
  `LastContact`.
- **ARMY-B-27 A full ledger leaves a gate capturable (kept, spec §5.5).**
  - With 2 gates awake, the other 2 can be taken on time alone. The Town core is within `SleepRadius` 400 of every
    gate, so a player there can keep the ledger full.
  - Guards also cannot hurt squad units (`HitsUnits = false`), so an army can clear them at no risk.
  - Both are accepted for v1 (spec §14 "fights are easy in v1") while only the owner is live.
  - Before `Live = "all"`, revisit: freeze a gate whose garrison cannot spawn, give garrisons a GroupId so the
    owner-in-reach rule applies, and let a unit hit add its owner to the hit-back list.
  - Fix 2 headroom arithmetic: today 13 camp + 5 bank + 4 garrison = 22 = 18 + SpecialOverCap, so a garrison wake is
    refused only when other OverCap NPCs exist (Ops events, Jobs OFF today). Such a refusal is now logged and retried
    (ARMY-B-9) instead of silently clearing the gate.
- **ARMY-B-28 AFK holding (new, Info).** One spot near a plot-1 gate is within 600 studs of FP1, FP2 and the West Gate
  and pays $4,000 per 90 s indefinitely. This is still less than HEAD's personal zones. Before `Live = "all"`,
  consider an activity check for post stipends or a lower `KeepAwayStuds`.
- **ARMY-B-29 No `out/report.md` (new).** The lane report is the builder's final message (the orchestrator's
  structured `report` field). The subagent rules forbid writing report files, and the reviewers accepted "keep the
  message as the report".
- **ARMY-B-30 Deliverable texts (new).**
  - `phone_test.md` uses landmarks instead of stud distances.
  - The army step (fix 2): walk to the flag in the middle of the ring, wait about 3 s until the soldiers stand around
    you, tap HOLD, walk about 20 steps back out and wait. HOLD pins each unit where it stands (today's HOLD; lane B
    adds no HOLDPOST), and a player who stays on the ring 8 s takes the post himself. See ARMY-B-36.
  - Step 8 says "about six car lengths" (outside the 60-stud target zone, inside the 150-stud wake ring); step 7
    says the guards keep shooting for up to 10 s if he shot one; step 10 says only his own chain is exempt in base.
  - Fix 3, step 9 (reviewer's wording): stop just outside the ring until the soldiers gather, walk with them to the
    flag, tap HOLD straight away, walk out; when the post is his, tap FOLLOW (HOLD holds the whole squad). This is the
    measured W = 0, D = 0 case of ARMY-B-36 (5 units count, taken), and he no longer stands on the ring for 3 s first,
    so the army's part is not half done by him. owner_text says "then tap FOLLOW".
  - Fix 3, step 13: his friend walks and drives through the booth and shoots at him across one of his guards; nothing
    stops the friend and the shots land.
  - The Forward Post is described as "about a third of the way to the Centre".
- **ARMY-B-31 Scope (new, Info).** This lane only adds the checkpoints the owner asked for ("more to capture along
  your way ... hold onto the checkpoint"). The rest of his message belongs to other lanes:
  - despawns and walls: lane FIX;
  - stand outside the base, and the bank fight: lane A;
  - ATTACK marching to take checkpoints: lane C.

  Until lane C is merged, an army takes a post only when placed with HOLD.
- **ARMY-B-32 Garrison tracers go to live players only (new in fix 2).** `CombatFx.Bullet` takes an optional recipient
  filter (`allow`; nil for every caller but a garrison, so the fan-out is byte-identical elsewhere). The NPC fx
  closure passes the record's `FxAllow` (`not zoneBars(rec, plr)`, one closure per garrison NPC made at spawn; fix 3,
  it used to be made per shot) for a garrison, and a deny-all filter if one is ever missing, so a player who is not live (his client removes the guard
  models) never gets tracers or sounds from invisible shooters. Measured: non-live 56 -> 0 garrison WeaponFx in 20 s,
  the owner still 56. This touches `CombatService/CombatFx.luau` (a file no other listed lane changes).
- **ARMY-B-33 Hidden guards are not in a non-live player's way on the server either (fixed in fix 3; was deferred).**
  The round-3 fairness review showed that in the shipping state (`Live = "owner"`) a non-live player's shots and the
  NPC shots at him stopped on guards his client had removed. CombatService now keeps every garrison record from
  `SpawnNPC` until `destroyNPC` (`zoneRecs`, its corpse included, 4 at most). `addHiddenBodies(list, player)` appends the
  models of the guards whose zone bars that player (`zoneBars`: not live) to a ray exclude list. It adds nothing for a
  live player (the owner still hits his guards and they still cover him) and nothing while no garrison exists, so
  every ray is exactly HEAD's then. It is used by:
  - the shot's exclude list in `RequestFire` (the exact ray, a projectile launched with it, the aim-assist sight line);
  - `validateClaim`: when the pinned claim ray (`{ shooter }`, main's P0-7 pin kept verbatim) is blocked, it is cast
    once more without his hidden guards, so a guard he cannot see never blocks his claim;
  - CombatNPC `npcHasLos` (binding `hiddenBodies`): an NPC's shot at a non-live player is not blocked by a guard he
    cannot see.

  Not changed, because they already skip every NPC body: squad unit sight lines (`UnitLosIgnoreNPCBodies = true`) and
  blast sight lines (`ApplyRadiusDamage` ignores `WarEmpireNPCs`). Both are pinned, so flipping either fails
  BuyPathStatic with the reason. The shot-origin wall check (main's W2 pin, kept verbatim) still uses the plain filter.
  A guard within 12 studs of his muzzle can only snap his shot's start to his head, and the ray from there passes
  through the guard.

  Movement: the guards are server-simulated (`root:SetNetworkOwner(nil)` in SpawnNPC, pinned). A non-live player's
  character and the car he drives are simulated on his own client, where the guard models no longer exist (T12 client:
  0 guard parts left in his workspace), so nothing stops or bumps him. What remains is on the server only: his body can
  nudge a guard, which the owner sees as an ordinary bump. There is no collision group. The game has none, player
  characters are in Default, and a group that ignores characters while standing on Default ground would mean
  regrouping every character, which is a global change the stand-in cannot verify. Phone step 13 checks it on a
  device.

  Residuals, all rare, cosmetic and owner-only today:
  - VehicleService's exit clearance rays and boxes can see a guard beside a non-live driver's door, so he steps out on
    the other side;
  - squad follow-path probes (`SquadOrdersService.buildProbe`, one per pass for all squads) can make a non-live owner's
    soldiers side-step a guard;
  - AirWeaponService rays: aircraft weapons are also owner-only (`AircraftWeaponConfig.LiveFor`, the same account). If
    `WeaponsLive` is switched on while `Posts.Live` stays "owner", add `addHiddenBodies` to that filter first;
  - base gate turrets (`GateDefenseService.hasLos`) reach 125 studs, and every Town Gate is far outside that from any
    plot gate.

  T12G (new driver, real CombatService, PostService and TerritoryService on the bank prelude): 17/0 on the candidate;
  7/10 on the round-2 tree.
- **ARMY-B-34 No carry-over while guards stand (new in fix 2).** With `RequireClear`, a Town Gate's capture progress
  and capturer are reset to 0 every tick its guards are alive (spec §5.5 "clear the guards first"), so the bar reads
  CLEAR GUARDS, never a shrinking CAPTURING. This narrows ARMY-B-5 for guarded gates only; armies tied on a post still
  decay as in a contest.
- **ARMY-B-35 Mission stamps (new in fix 2).** Post mission cooldown stamps (`"<userId>|<postId>"`) older than
  `MissionCooldownSeconds` are dropped whenever a player leaves. A rejoin inside the cooldown keeps its stamp, so
  leaving and rejoining cannot farm the +1.
- **ARMY-B-36 HOLD on a post, measured with the real squad code (new in fix 2).** The stand-in run uses the real
  SquadOrdersService (this tree's follow code, straight-line walker), UnitsOf, PostService and PostPresence, no stub:
  5 soldiers, the owner stops D studs from the Forward Post centre, waits W s, taps HOLD, walks 30 studs out.
  - W = 0 (HOLD straight away): D = 0: 5 count, taken; D = 6: 4 count, taken; D = 13: 0 count, never taken.
  - W = 3: D = 0 / 6 / 13: 5 count and taken every time.
  - So the phone step says "walk to the flag, wait about 3 s, then HOLD". On a real phone units lag more (the
    diagnosis measured 0/8 in slot on the live follow code), which the phone test checks. Lane A's HOLDPOST ring
    slots (spec §3.2) would remove the dependence on where units happen to stand; the integrator should confirm lane A
    builds it before `Posts.Live` goes past the owner.
- **ARMY-B-37 NPC total when Jobs / events are on (changed in fix 3).** Non-garrison spawns never count garrison NPCs
  (ARMY-B-9), so camp and bank respawns see HEAD's numbers. The price is that other NPCs can fill the specials' +4 while
  garrisons are awake. Fix 3 bounds it. While the Ops master switch is on (`OpsConfig.Enabled`: Jobs and events), the
  ledger is `TownGate.LedgerJobsOn` = 2 instead of 4. That is one guarded gate at a time; a second woken gate stays
  unguarded, and this is logged once.
  - The worst case is 18 + 4 + 2 = 24 NPCs with Ops on (T7X K: 13 + 11 incl. 4 events + 2 garrison = 24; round 2 gave 26).
  - With Ops off (live today) it stays at 22 (13 camp + 5 bank + 4 garrison).
  - It is pinned in BuyPathStatic: Ledger <= SpecialOverCap, LedgerJobsOn = 2, 18 + 4 + 2 <= 24.
  - The other option, counting garrisons for OverCap event spawns only, was not taken. In this tree no code but
    PostService spawns with `OverCap`, and Ops garrison sites use the special types (EventReserve), which that option
    would not bound. It would also let the owner's garrison refuse other players' event NPCs.
- **ARMY-B-38 Forward Post names (new in fix 3).** The 6 Forward Posts are named for their side of the map (Names in
  `Posts.Forward`): Northwest (plot 1), Southwest (2), North (3), South (4), Northeast (5) and Southeast Post (6). These
  are compass words only, <= 16 characters and distinct. The road's Gate shares the word (North Post, then North Gate).
  Two held posts never read the same in the list, the bar or the "taken / lost / under attack" toasts. The longest bar,
  "CAPTURING NORTHWEST POST" (24 characters), is shorter than "CLEAR GUARDS · NORTH GATE" (25). `Forward.DisplayName`
  "Forward Post" stays as the fallback. The spec's name list said "Forward Post"; this is reversible by deleting
  `Names`.
- **ARMY-B-39 A claim naming a hidden guard is refused (new in fix 3).** When a non-live player's fire request names a
  garrison NPC his client hides (`TargetNpcId`, which only a doctored client can send), CombatService refuses it
  ("hidden guard") before the claim checks. It used to resolve as a 0-damage claim with a tracer to the guard.
- **ARMY-B-40 Stale garrison ids (new in fix 3).** Each tick of an awake gate drops an id from the ledger when its
  CombatService record is dead (`Alive == false`) or its model was removed outside CombatService (then the record is
  despawned too). It acts only on that evidence, so test fakes without those fields are untouched. A `DespawnNPC` from
  anywhere, which fires no OnNPCDeath, used to leave the gate frozen on "guards" with nobody there. T12G shows it: on
  the round-2 tree the ledger kept 2 ids after both guards were despawned.
- **ARMY-B-41 Integration notes (new in fix 3).**
  - The base is still the capture lane's fix-1 candidate, re-derived by reversing the round-2 `lane_b.diff` on the
    candidate. Its md5s match out/base.txt. `lane_b.diff` (18 files, 66 hunks, +2111/-26 by `git apply --numstat`)
    applies to it with 0 failed hunks and reproduces the candidate 18/18.
  - main 4d26673 (af4c7d4 water rule; 4d26673 escorts shoot back at the bank; lane A0's army-bucket args in
    `CombatFx.fanOut`) plus the capture fix-1 files: only `CombatFx.luau` hunk 1 fails. `merge_4d26673_CombatFx.diff`
    is the hand merge (`fanOut` gains `allow` as a 5th parameter, `Bullet` passes `nil, nil, allow`). The fx pin now
    accepts both call shapes. Probe tree (4d26673 + capture fix-1 files + lane diff + that merge): parse ok;
    BuyPathStatic 4448/1, the 1 being the capture lane's own Z `PersistClaims` pin, which needs the capture lane's
    BuyPathStatic hunk and is not lane B's; T12G 17/0, T7X 15/0, T7 26/0.
  - The capture lane's fix-2 candidate (fb4/capture/cand now): only `TerritoryService/init.luau` hunk 7 fails
    (`buildPayloadForPlayer`, the bar pick). Capture fix 2 shows the bar only for a zone the player is counted
    inside; lane B's ARMY bar is for a post his army takes while he stands outside (phone step 9). The merged
    condition, with the capture pin relaxed by one alternative, is in `merge_capturefix2_TerritoryService.txt`, and
    the probe run on it is in results/integration: BuyPathStatic 4413/0, the capture lane's cap_driver 71/0 (as on
    its own candidate), T6 client 77/0 (ARMY bar with the owner 300 studs away), T12G 17/0, T7X 15/0, T7 26/0,
    T12 client other 8/0 and owner 9/1. The one is the T12 tail's 10 s control: capture fix 2 drops YOURS after his
    own capture (its CAP-18), so the check must move to 5 s (10/0 there on both trees). If the capture lane keeps
    its rule unchanged, the army still takes the post and the "taken" toast still comes, but no ARMY bar shows
    while he is outside, and phone step 9 must then say so.
