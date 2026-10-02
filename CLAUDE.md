# WAR EMPIRE — rules for anyone working in this repo

## QUEUED JOBS (Code Bot, 2026-09-30)
> **Owner instruction (2 Oct 01:27): keep working through the queue continuously overnight. Do not stop or wait for replies. The owner will talk in the morning.**
- **JOB 70, URGENT, ship LIVE FOR EVERYONE** (`OwnerFirst=false`; the owner explicitly approved going straight live, so no owner test step). This is the next free JOB number and is the top-priority queue item.
  - **Collision:** the newly wired base props and wall dressings (sandbags, Hesco, concrete blocks, crates, pallets, barbed wire) must not be walk-through. Give every placed prop/visual segment one cheap invisible `Box`/`Block` hull: anchored, sized to the visual bounds, `CanCollide=true` for players and soldiers, with the visual mesh parts `CanCollide=false` (and no mesh collision). Do not use per-frame physics or heavy collision meshes; keep it phone-light.
  - **Walls:** every wall side (front/gate, left side, right side, and rear) must use the same new wall style selected from the central wall-upgrade config for that saved tier. Keep the progressive tier looks; never let a side silently fall back to the old/front-only style. Wall visuals are non-colliding and their cheap Box hulls/authoritative wall colliders remain solid.
  - **Acceptance:** add `tools/checks/claude_bud_job70.py` that fails closed unless it can account for every prop category/placement and every wall side, proves visual collision is off plus the Box hull is on, and proves all four wall sides resolve the same central tier style. Update `LATEST-HANDOFF.md`.
  - **Guardrails:** this queue edit is docs-only; the implementation must keep `StreamingEnabled` and `PreferMesh` OFF, never touch `WE_Building*`, preserve save keys/levels/prices, and make no owner-test step or staged rollout.
- After JOB 34 is finished and pushed, do JOB 35 then JOB 36 exactly as written in
  [`docs/claude-queue/JOB35-36-shop-and-guns.md`](docs/claude-queue/JOB35-36-shop-and-guns.md), one at a time, same
  rules. No fast travel.
- After JOB 36 is finished and pushed, do JOB 37 (real road checkpoint: detail + killable guards) exactly as written in
  [`docs/claude-queue/JOB37-checkpoint.md`](docs/claude-queue/JOB37-checkpoint.md), same rules. If any JOB 31 work is
  still unfinished, it may fold into JOB 37 (JOB 31 itself shipped in v128).
- After JOB 37 is finished and pushed, do JOB 38 (army ATTACK auto-clear nearest + SEND army to another player's base
  to breach gates / guards / turrets, raid fairness) exactly as written in
  [`docs/claude-queue/JOB38-army-attack-orders.md`](docs/claude-queue/JOB38-army-attack-orders.md), same rules. Owner-first
  flag, no teleport / PivotTo in marches, no fast travel.
- After JOB 38 is finished and pushed, do JOB 39 exactly as written in
  [`docs/claude-queue/JOB39-endgame-progression.md`](docs/claude-queue/JOB39-endgame-progression.md).
- After JOB 39 is finished and pushed, do JOB 40 exactly as written in
  [`docs/claude-queue/JOB40-guards-speed-props-like-reminder.md`](docs/claude-queue/JOB40-guards-speed-props-like-reminder.md).
  **PRIORITY (owner 2026-09-30 19:05): do part E (base owner markers: name above each base, visible from anywhere) FIRST
  within JOB 40, then A-D.** The owner wants the markers to drive attacks.
- **NEXT, TOP PRIORITY (Shaun 2026-09-30 23:19 Dublin; queued by Code Bot v153): when the job you are on right now is
  finished and pushed, do JOB 40E-FIX (base owner name tags: high in the sky, compact flag + short name, @handle only
  when close, distance scale with a clamp, fade + only the nearest 4-5, no overlapping tags, no tag without a live
  owner, YOU kept on your own base, phone test at 1024x471 with before / after screenshots, BaseMarker OwnerFirst stays
  true) exactly as written in
  [`docs/claude-queue/JOB40E-FIX-base-tags.md`](docs/claude-queue/JOB40E-FIX-base-tags.md) (`0f210ab` may already cover
  most of it: verify, finish, screenshot). THEN JOB 41 (moved to the front: it comes before every other queued job),
  then JOB 42.**
- **JOB 41 note (Code Bot v153, already LIVE for everyone on phase-7-polish):** Code Bot already shipped (a) the
  first-offer timing: the first paid offer (the Commander Starter Pack, or the 99 R$ Speed Boost when the pack is not
  wanted) comes at ~2 minutes of play whatever the tutorial state (`MonetizationConfig.FirstOffer`, the
  `ClaimSoftOfferSlot` quiet window, `MonetizationService.ScheduleFirstOffer`); (b) the Starter Pack re-queue: it is
  marked `StarterBundleOffered` only when the client confirms the card SHOWED (`OfferResult` remote +
  `Server/Modules/OfferLedger`), a dropped / refused / unanswered card comes back 45 s later; (c) the analytics keys:
  ProductPrompted now gets `productKey`, plus custom `PassBought` / `OfferShown` / `OfferDropped`. JOB 41 must NOT redo
  any of these. Its part B Recruit Pack must plug into the same path (ClaimSoftOfferSlot budget, FirstOffer schedule,
  OfferLedger "shown" ack, the same analytics fields); it must not push the first offer back to 10 minutes or the
  tutorial end, and must not mark an offer at send. If part B's "only after the first capture or 10 min" rule clashes
  with the 2-minute first offer, keep the 2-minute Starter Pack and ask Shaun in LATEST-HANDOFF.
- After JOB 40E-FIX is finished and pushed, do JOB 41 (the first minutes: a guided goal chain with a real first fight and
  capture, funnel analytics, a ~49 R$ Recruit Pack offered only after the first capture or 10 min, rival TARGETS with
  SEND ARMY, and a big-win rate prompt with NO reward) exactly as written in
  [`docs/claude-queue/JOB41-first-minutes-retention.md`](docs/claude-queue/JOB41-first-minutes-retention.md). Owner-first
  flags, no fast travel, servers stay at 10 players.
- After JOB 41 is finished and pushed, do JOB 42 (TIME-based cash packs that scale with the player's income: 15 min
  25 R$, 30 min 49 R$, 1 h 89 R$, 2 h 159 R$, 4 h 279 R$, NO 1-day / 7-day; rows "4 HOURS OF CASH" + the live $ amount
  computed server-side at receipt time; BEST VALUE on 4h; floors for new players; new Ids 0 until Code Bot creates them;
  old S / M / L / Mega kept in config but hidden once the time packs are live; the JOB 41 Recruit Pack cash = the
  30-min pack amount, still 49 R$) exactly as written in
  [`docs/claude-queue/JOB42-time-cash-packs.md`](docs/claude-queue/JOB42-time-cash-packs.md). Owner-first flag with a
  kill switch, no publish.
- **QUEUED AFTER THE LAST EXISTING JOB (Shaun 2026-10-01 18:18 Dublin): JOB 59 — Free Creator Store assets pass.**
  Strict order: complete the jobs already above, then JOB 59, then JOB 60 immediately below it. All listed assets are
  already in Shaun's (shaunie6) inventory. Keep `OwnerFirst = true` for the config/phone test, add the feature's
  `tools/checks/claude_bud_job59.py` checks, update `LATEST-HANDOFF.md`, and obey the house rules: mobile-light (few
  lights/props, cap props per base, sounds 3D/proximity only, no heavy VFX), `StreamingEnabled` / `PreferMesh` off,
  never touch `WE_Building*`, no franchise models, real detail.
  - **(A) Helipad helicopter:** rebuild the helipad heli using SKYtech rotorKit `9961947424` (or rotorLite
    `12918869816`); vendor its remote self-updating module locally using local copy `96681147793573`, audit every
    script, and use no remote `require`. Fix the tilt and detached rotor. Coordinate with JOB 56 and fold this in if
    JOB 56 has not started. aeroKit `8521123488` is optional for hangar jets.
  - **(B) Sound pass:** create/use one central `SoundConfig` with night crickets `9112764546`, night ambience
    `9112835836`, harbor night `9112792684`, desert wind `9114057104`, flag flap `9114461215` / `9114576083`, radio
    chatter `9112851398` / `9125793009` near Command Center, distant artillery `9113169264` in desert, heli
    `9113417759` / `9125390124`, boats `9112750448` / `9126201834`, gate `9116875342`, raid siren `9119661640`,
    cash collect `9113728042`, UI clicks `15675059323` / `15675032796`, and Military March `1844397606` for
    menu/rebirth with cuts `1841116989` / `1845181958`. Sounds must be 3D/proximity-only where world-placed.
  - **(C) Night and base life:** fold into JOB 54 / JOB 57 where applicable. Use lights `8217816335`, `1725607094`,
    `404475960` sparingly (8k-triangle cap); Night Fog sky `1864839162`, fireflies `3347717118`, dust `615333766`,
    fire/smoke `11365590395` only on raided bases/wrecks, and VFX textures `17290956157`. Add lightweight props:
    sandbags `5678434293`, crates `2930926216`, ammo crates `2190705941` (credit the creator), border fence
    `4715423769`, metal gate fence `9083814252`, and parked Roblox pickup truck `6418225759`.
  - **(D) Vault top tier:** use Vault Door `14795516338` as the highest vault-upgrade visual, tied into JOB 53 and read
    from the central upgrade config.
  - **Available Studio plugins:** Archimedes `144938633`, F3X `144950355`, Brushtool `2268520847`, RigEdit Lite
    `1274343708`, AutoScale Lite `1496745047`, VFX Studio `135581141962270`, Tag Editor `948084095`, and GapFill
    `165687726`.
- **JOB 60 — Fix error report (small job, immediately after JOB 59).** Find and fix the root causes, not symptoms, for
  the top error report: 2,233/day `Failed to load animation with sanitized ID`; 265 server sanitized-animation errors;
  340 animation-track-limit warnings; 98 mesh fetch errors; 67 AnchorPoint nil errors; and 42 sound ConnectFail.
  Add `tools/checks/claude_bud_job60.py`, keep the same `OwnerFirst = true`, mobile-light, `StreamingEnabled` /
  `PreferMesh` off, `WE_Building*` untouched and no-franchise/real-detail rules, and update `LATEST-HANDOFF.md`.
- **JOB 61: Creator Hub Economy + Funnels analytics (AnalyticsService)**
- **Store props (Code Bot STORE-PROPS, v132): DO NOT REMOVE.** The owner's Creator Store buildings / props live in
  `Shared/Configs/StorePropsConfig.luau` (placed by `Services/StorePropsService.luau`; list in
  [`docs/PROP-ASSETS.md`](docs/PROP-ASSETS.md)). They dress the JOB 31 sites / named areas and swap in as the JOB 33
  rebirth zone upgrade visuals (the Part build stays as the fallback). Do not delete the config, its rows or the
  service; do not name your own parts `Store_*`; keep new builds clear of `Workspace.WorldFill.StoreProps`. The
  service does not modify RebirthZoneBuilder / RebirthZoneService: it only reads the `Zone_<Id>` folders they build.
- **No fast travel, ever:** it was removed in v127 at the owner's request. The map is tap-to-pin only (see
  `tools/checks/codebot_v127.py`).

## 0. Start here (every session, every time)
- **Parallel sessions:** read [`LANES.md`](LANES.md) first. It says which lane your job is in, which files you own,
  the rules for shared hot files, the branch name (`claude/lane-<x>-<topic>` from the latest `phase-7-polish`), and
  how to hand back (push your branch, reply `DONE` with a summary and a test list).
- **Background:** `LATEST-HANDOFF.md`, `HANDOFF-TO-NEW-CODE-BOT.md`, `MASTER_BUILD_SPEC.md`, then the newest
  sections of `ASSUMPTIONS.md` for your area.
- **Never:** bump `WE_Build`, publish, build `dist/`, or push to `phase-7-polish` or `main`. Those are Code Bot's
  job (the integrator).
- **Flags:** new gameplay ships owner-only first (`AdminConfig.IsPlaytestOwner`, UserId 470626172, like
  `ArmyConfig.Rollout` and `AircraftWeaponConfig.LiveFor`) behind a config switch. OFF must equal the old behaviour.
- **Store models (Creator Store assets):**
  - A model is used only after it passes the owner's `WE_CHECK2` check (`tools/WeCheck2*.luau` via Open Cloud;
    see `docs/ASSET_WIRING.md`).
  - Origin rule: every mesh and texture must be uploaded by the model's creator (or by Roblox).
  - At most 40 parts after trimming, no scripts (strip them), at most 20,000 triangles for phones.
  - No real-world or franchise copies (no F-16, B-2, Apache, Black Hawk, named real ships, other games' assets).
  - It goes through `tools/wire-asset-ids.py` (PENDING, then promote or REJECT) and is attributed in
    `docs/ASSET_LICENSES.md`.
- **BuyPathStatic:** add your pins to `tools/checks/lane_<x>.py`, never to the body of `tools/BuyPathStatic.py`.
- **Definition of done:**
  - the parse gate is clean on changed files;
  - `python3 tools/BuyPathStatic.py` ends `FAIL=0`, with your new pins;
  - `rojo build` succeeds;
  - the feature's own tests pass (no invented results);
  - the change is behind an owner-only flag if it is gameplay;
  - an `ASSUMPTIONS.md` section is appended;
  - the branch is merged with the latest `phase-7-polish` and pushed;
  - the `DONE` reply lists what the owner must test **on his phone**.


Roblox military tycoon/PvP. Luau (`--!strict`) + Rojo. Build: `rojo build -o dist/WarEmpire-PERF.rbxlx`.
The owner publishes this branch to the live game, so every push must be tested.

## 1. Mobile first (about 80% of players are on phones)
Design, build and verify for a **phone in landscape first**, PC second. Anything that only works well on PC is unfinished.

- **Screens to check:** 844×390, 956×440 (the owner's phone), 800×360 (small phone), 1180×820 (tablet), then 1280×720 and 1920×1080.
- **Touch:**
  - Every action has a touch control; no feature may be keyboard-only (exit vehicle, lift/descend, reload, weapon switch, orders, garage, prompts).
  - Tap targets are **≥ 44 px real** (48+ preferred).
  - Nothing important sits under the Roblox thumbstick (bottom-left), the jump button (bottom-right) or the top-bar pills.
  - Hold prompts must work with a finger.
  - No hover-only UI.
- **Readability:**
  - Text is ≥ 14 px real at phone scale, high contrast, with short labels (2–3 words).
  - One message at a time; no screen-covering pop-ups during combat or driving.
  - World billboards stay small and must never cover the HUD.
- **Performance (phones overheat and drop frames long before PCs):**
  - Keep part counts inside the budgets in the specs.
  - Few lights, `Shadows = false` on small lights, no neon floods.
  - No per-frame `GetDescendants` / allocations in `RenderStepped`/`Heartbeat`.
  - Throttle loops (≤ 10 Hz for UI refresh); cap particles.
  - Use `UnreliableRemoteEvent` for effects; keep remote traffic ≤ 20 Hz per player.
  - Code must be safe under StreamingEnabled: never assume a workspace part exists on the client, and never `WaitForChild` without a timeout.
- **Game feel on touch:**
  - Controls must be forgiving: aim help on touch, generous prompt ranges, and vehicles that drive with the thumbstick alone.
  - Auto-collect and auto-actions are preferred over precise taps.
- **Real px, not code px:**
  - Phone HUDs run under UIScale ≈ 0.70 and panels under ≈ 0.65.
  - So 44 px real means ≥ 64 in code (≥ 68 under 0.65), and 14 px text means ≥ 20 in code.
  - Size helpers take **real px**.
- **Reserved zones:**
  - Nothing tappable in the left 40 % × lower ⅔ of the safe area, except one edge rail.
  - Nothing within 16 px of the jump button.
  - Jump is the only touch exit, so it is never covered.
  - Airborne exits need a hold.
- **Copy by device:**
  - Never name a key or say "click" in text a phone player can see (toasts, billboards, tutorial).
  - Key hints appear only when `PreferredInput` is keyboard or gamepad.
  - Detect the device with `PreferredInput`, not `TouchEnabled`.
- **World labels:**
  - Stud-scaled, 14–20 px text, `MaxDistance` ≤ 40.
  - At most 3 on screen at a base and 5 at an outpost.
  - `AlwaysOnTop` only for the one active objective marker.
  - No debug labels on live.
  - The one documented exception (owner-approved 2026-09-30, JOB 40 part E): the **base owner marker** (one per
    occupied base, `BaseMarkerConfig`: name, flag, rank, `MaxDistance` 5000, `AlwaysOnTop`, hidden inside 60 studs).
    Nothing else gets this.
- **Pointers:** anything that points a player somewhere (tutorial beam, waypoint, GO line) resolves to **their own** plot or the nearest valid target, never a fixed world marker.
- **Combat fairness:**
  - The server never trusts a target id sent by the client.
  - Assisted hits need line of sight and follow the aim-assist config.
  - NPC shots need line of sight and a hit chance.
- **Travel:** any core-loop trip over 30 s on foot needs a shortcut (sprint, vehicle or recall).
- **Budgets:** these are hard caps and must not grow. The target is reached by the phone-performance pass.

  | Budget | Hard cap | Target |
  |---|---|---|
  | Parts per base at L5 | 2,700 | 2,000 |
  | World parts outside bases | 3,100 | 2,000 |
  | Lights | 730 total, 40 per base | 300 total |
  | SurfaceGuis | 1,134, each `MaxDistance` ≤ 80 | 400 |
  | Neon parts | 986 | 300 |
  | Instance changes per purchase | — | 60 |
  | Catalog models | ≤ 40 parts each, no Humanoid, templates in ServerStorage | — |
  | Client per-frame work | no whole-tree scans | — |
  | UI refresh rate | 10 Hz | — |

- **Test like a phone:**
  - Performance claims use the live dressing level.
  - Confirm them on a mid-range Android or at Graphics Quality 3. The owner's top-end iPhone is not the bar.
- **Verification:**
  - Run the HUD harness at phone viewports (`check_hud.py --viewports phone,owner,desktop`), plus 800×360 and 1180×820, including panels with data.
  - Every change note says what the owner must test **on his phone**.

## 2. Hard rules
- **Server authority:**
  - Cash, XP, upgrades and ownership are decided on the server.
  - There are NO `GiveCash`/`GiveXP` remotes. Clients request; the server validates and rate-limits.
- **Config first:** tunables live in `src/ReplicatedStorage/Shared/Configs`.
- **Remotes:** never `WaitForChild` forever on the remotes folder; use the `Shared/Remotes` helpers.
- **Data:**
  - `DataService.Init()` runs before any service that calls `GetProfile`, and `GetProfile` is nil until the real save has loaded.
  - Never wipe production DataStores.
  - Never change the Place or Universe IDs.
- **Purchases:**
  - Grants happen only in `ProcessReceipt` (save before `PurchaseGranted`), or through pass ownership checked with `UserOwnsGamePassAsync`.
  - New product Ids stay 0 until the owner creates the product.
- **Admin cash:** keep `AdminPlaytestCash` for UserId 470626172 only. Never grant it to anyone else.
- **Structures:**
  - `PreferMesh` stays OFF for structure kits.
  - Perimeter walls spawn on the DefensiveWalls purchase (`SyncPerimeterWalls`). Do not break this.
- **Build guide:** every build job (buildings, props, vehicles, interiors, POIs, lighting, NPC or UI polish) follows [`docs/ROBLOX-BUILD-GUIDE.md`](docs/ROBLOX-BUILD-GUIDE.md) and ticks its §11 detail checklist in the DONE reply.
- **Names and assets:**
  - No real-world brand, vehicle or weapon names. Real countries appear only as a player's own cosmetic nation, chosen by the player from `NationConfig` (current national flag + short name, owner-approved list, ISO 3166 ids). Never: historical, regime, separatist, extremist or party flags; military insignia; a real country on NPCs, map places, vehicles, factions or leaderboards; a nation name in any kill, strike, nuke, raid or capture message; nation-vs-nation rules, bonuses or matchmaking; a flag shown damaged, burning, on the ground, beside strike effects or as a target. Flags in the world are Textures/Decals, never SurfaceGuis. Players never draw flags or type nation names. An IP-derived country is only a suggestion to that player: never auto-applied, shown to others, stored or logged.
  - Never copy another game's assets or code. Re-implement mechanics and use only Roblox-official or permissively licensed parts, with attribution.
- **Luau gotcha:** a line that starts with `(` right after another statement needs a `;` in front of it.
- **Ambiguity:** make a reversible assumption, record it in `ASSUMPTIONS.md`, and keep going.
- **Tests:** never invent test results. The headless stand-in is not Roblox; say what still needs a real device.

## 3. Checks before any commit
- Parse gate: `luau-compile --binary` on every changed file.
- Type check (`luau-lsp analyze` with the sourcemap): no new errors compared with HEAD.
- `LUAU_COMPILE=… python3 tools/BuyPathStatic.py`: 0 failures.
- Headless world sim: every step ok.
- `DataService` harness: all pass.
- Plus the feature's own tests.

Commit only files that were verified together. Lane sessions push only their own `claude/lane-*` branch (LANES.md §6); Code Bot pushes `phase-7-polish` and the Padel-AI mirror.
