# WAR EMPIRE — rules for anyone working in this repo

## QUEUED JOBS (Code Bot, 2026-09-30)
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
