# WAR EMPIRE — rules for anyone working in this repo

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
- **Names and assets:**
  - No real-world brand, vehicle, weapon or country names.
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

Commit only files that were verified together. Push to both remotes.
