# WAR EMPIRE: parallel work lanes

Several Claude sessions can work at once, one per job and each in one **lane**. A lane owns a set of files, so two
sessions rarely edit the same file. Code Bot (the integrator) merges finished lane branches into `phase-7-polish`,
bumps `WE_Build`, runs the checks and publishes. **No lane session ever publishes or bumps WE_Build.**

Read `CLAUDE.md` first (rules), then this file, then the handoff docs (`LATEST-HANDOFF.md`,
`HANDOFF-TO-NEW-CODE-BOT.md`) and `MASTER_BUILD_SPEC.md`.

## 1. Lanes and owned files

Paths are under `src/`. `RS/Configs` is `ReplicatedStorage/Shared/Configs`, `Server` is `ServerScriptService/Server`
and `Client` is `StarterPlayer/StarterPlayerScripts/Client`. Anything not listed is **shared**; see section 3.

### Lane A: Vehicles, Air and Naval looks
- Configs: `RS/Configs/VehicleConfig`, `VisualAssetConfig` (vehicle, aircraft, naval and VehicleWeapons refs),
  `AircraftWeaponConfig`, `VehicleWeaponConfig`, `VehicleCombatConfig`, `PremiumVehicleConfig`, `WaterConfig`.
- Server: `Services/VehicleService`, `Services/AirWeaponService`, `Services/VisualAssetService` (vehicle and body
  fit paths only; see the note below), `Modules/AirBodyRig`, `AirOrdnance`, `VehicleHealth`, `VehicleWaterGuard`,
  `Util/WaterRule` (in RS).
- Client: `Controllers/VehicleController`, `Modules/VehicleDriveClient`, `VehicleCombatClient`, `AircraftBodyClient`,
  `AirWeaponsClient`.
- Tools and docs: `tools/wire-asset-ids.py`, `tools/WeCheck2*.luau`, `tools/parse_we_check2.py`,
  `docs/ASSET_WIRING.md`, `docs/ASSET_LICENSES.md`, `docs/asset_wiring.json`.
- Note: `VisualAssetService` also dresses buildings (lane D) and businesses (lane C). Lane A owns it; another lane
  that needs a change there makes a small, isolated commit with a NOTE (section 4).

### Lane B: Army, Squad, Combat, Bank
- Configs: `ArmyConfig`, `OrdersConfig`, `SoldierConfig`, `RigConfig`, `CombatConfig`, `CombatFairnessConfig`,
  `CombatFeelConfig`, `AimAssistConfig`, `WeaponConfig`, `BankRaidConfig`, `RaidConfig`, `GateDefenseConfig`,
  `NukeConfig`, `SupplyDropConfig`, `OpsConfig`, `TerritoryConfig`, `ClanWarConfig`.
- Server: `Services/SquadOrdersService`, `SoldierService`, `CombatService/*`, `BankRaidService`,
  `GateDefenseService`, `MissileStrikeService`, `SupplyDropService`, `OpsService/*`, `TerritoryService/*`,
  `ClanWarService`, `CaptureStipendService`, `Modules/Projectile`, `RigBuilder`, `WeaponAssetLoader`.
- Client: `Controllers/ArmyController`, `OrdersController`, `CombatController`, `BankRaidController`,
  `MissileController`, `OpsController`, `TerritoryController`, `Modules/AimTargets`, `WeaponVisuals`,
  `RigAnimator`, `OpsJobs`, `CameraFx`.
- Warning: `SquadOrdersService` and `VehicleService` (lane A) are close to Luau's 200-local limit. Put new state in
  module fields, not new top-level locals.

### Lane C: Economy, Tycoon, Build, Progression
- Configs: `EconomyConfig`, `BaseConfig`, `BaseLayoutConfig`, `BusinessConfig`, `ManualDropperConfig`,
  `PlotOilPumpConfig`, `OilRigConfig`, `ConsoleBuyConfig`, `TycoonGuideConfig`, `LevelConfig`, `XPBalanceConfig`,
  `PrestigeConfig`, `RebirthConfig`, `ResearchConfig`, `StructureVisualConfig`, `TrainingYardConfig`,
  `MissionConfig`, `DailyOpsConfig`, `DailyRewardConfig`, `AchievementConfig`, `BattlePassConfig`, `SeasonConfig`,
  `SpinnerConfig`, `LootBoxConfig`, `CodesConfig`, `ClanConfig`.
- Server: `Services/BaseService` (except the WE_Build line; see section 3), `EconomyService`, `BusinessService`,
  `ManualDropperService`, `MoneyCollectorService`, `PlotOilPumpService`, `UpgradePadService`, `XPService`,
  `PrestigeService`, `ResearchService`, `MissionService`, `BattlePassService`, `SeasonService`, `SpinnerService`,
  `CodesService`, `ClanService`, `TutorialService`, `Modules/BaseLayout`, `StructureKitBuilder`,
  `HollowBuildingBuilder`, `TrainingYardBuilder`, `Interiors/*`, `Installations/*`.
- Client: `Controllers/BaseController`, `ProgressionController/*`, `ResearchController`, `MissionController`,
  `TutorialController`, `Modules/BusinessVisuals`, `ProductionFx`, `ProducerLabels`, `NextPadChevrons`,
  `RebirthConfirm`, `ProgressPill`, `ConsoleWaypoint`, `WorldSpinners`, `Util/TycoonMath` and `Util/ConsoleLocator`
  (in RS).

### Lane D: World, Map, Town, POIs
- Configs: `WorldConfig`, `WorldDressConfig`, `WorldLabelConfig`, `StreamingConfig`, `SoundConfig`.
- Server: `Modules/MapSetup`, `MapDressing`, `WorldDress`, `WorldKits`, `WorldPOI`, `POILayouts/*`, `WorldTerrain`,
  `Waterways`, `WorldBounds`, `WorldAtmosphere`, `WorldHygiene`, `WorldLabelPolicy`, `DesertFlora`,
  `ActivityAnchors`, `StreamPrefetch`, `Services/FallSafetyService`.
- Client: `Modules/LabelGovernor`, `ObjectiveMarker`, `AudioController`, `AudioHooks`, `Controllers/CompassController`,
  `Util/WorldLabel` (in RS).

### Lane E: UI, HUD, Client shell
- Configs: `HudConfig`, `NotificationConfig`, `TutorialConfig` (copy and layout only).
- Client: `Bootstrap.client`, `Controllers/UIController`, `HUDController`, `NotificationController`,
  `PromptController`, `WorldPromptController`, `SettingsController`, `NationController`, `Modules/HudLayout`,
  `HudIcons`, `PanelShell`, `ClientSettings`, `StudioSmokeClient`, `Util/UIUtil` (in RS).
- Server: `Services/NotificationService`, `NationColorService`, `Modules/NationFlag`; configs `NationConfig`,
  `NationColorConfig`, `NationFlagIds`, `Util/NationTexture`.
- Tools: HUD harness scripts, `tools/gen_nation_flags.py`, `tools/wire-nation-flag-ids.py`.

### Lane F: Monetisation
- Configs: `MonetizationConfig`, `AnalyticsConfig`.
- Server: `Services/MonetizationService`, `PremiumPadService`, `AnalyticsService`.
- Client: `Controllers/ShopController`.
- Tools and docs: `tools/wire-monetization-ids.py`, `docs/MONETIZATION_*`.
- Rule: grants happen only in `ProcessReceipt` (save before `PurchaseGranted`) or through `UserOwnsGamePassAsync`. An
  Id stays 0 until the owner gives the real one.

### Lane legacy: `claude/war-empire-phase-7-toqwff`
The original single Claude session keeps working as before, but it follows sections 3 and 4 too. It has no file
ownership of its own: when it touches a lane's files it rebases on `phase-7-polish` first and says so in the
commit message. New work goes to a lane branch.

### Code Bot only (the integrator)
`WE_Build` (all four sites), `tools/publish-opencloud.sh`, `dist/*`, `default.project.json`, `aftman.toml`,
`selene.toml`, `roblox.yml`, the legacy body of `tools/BuyPathStatic.py` (everything above its LANE CHECK FILES
block), `tools/merge-lanes.sh`, and the Padel-AI `war-empire-handoff` mirror.

## 2. Branches
- Name: `claude/lane-<a|b|c|d|e|f>-<topic>`, e.g. `claude/lane-b-guards-fight-back`.
- Always branch from the latest `origin/phase-7-polish`. Before you finish, merge (or rebase onto) the newest
  `phase-7-polish` again and re-run the checks.
- Make small, single-purpose commits, with messages like `feat(lane-b): ...` or `fix(lane-a): ...`.
- **Never** bump `WE_Build`, publish, force-push `phase-7-polish`, or push to `phase-7-polish` or `main`.
- Editing a file outside your lane: keep the change minimal, put it in its own commit, and write in that commit's
  message `NOTE: touches lane <x> file <path> because <reason>`.
- One job per session. A second job gets its own branch.

## 3. Shared hot files and their rules

| File(s) | Rule |
|---|---|
| `WE_Build` sites: `Services/BaseService.luau` (~l.1812), `Services/DataService.luau` (~l.211 and the log line ~l.351), `EarlyRemotes.server.luau` (~l.70), and the WE_Build asserts in `tools/BuyPathStatic.py` | **Code Bot only**, bumped once per publish. Lanes never touch them. `WE_Building*` attributes are unrelated; leave them alone. |
| Publishing (`tools/publish-opencloud.sh`, `dist/*.rbxlx`) | **Code Bot only.** |
| `RS/Configs/GameConfig.luau`, `DevConfig.luau`, `AdminConfig.luau`, `Constants.luau`, `Types.luau` | Additive only (new keys at the end of the relevant table), in one small isolated commit with a NOTE. Never rename or remove a key. Keep the admin unlocks for UserId 470626172. |
| `Server/Modules/RemoteSetup.luau`, `EarlyRemotes.server.luau`, `RS/Remotes.luau`, `Modules/RemoteGuard.luau` | A new remote is one small isolated commit: one line in the remote list plus its rate limit. Never rename or remove a remote, and never add `Give*` remotes. |
| `Services/DataService.luau`, `Modules/ProfileSchema.luau`, `SessionLock.luau` | Schema changes are **additive only**: a new field with a default in `CreateDefault` plus a `Migrate` backfill, in one small isolated commit. Never rename, retype or delete a field. Never wipe DataStores. |
| `Server/Bootstrap.server.luau` (service init order) | One line per new service, in its own commit. Never reorder existing services (`DataService.Init` runs first). |
| `Services/AdminService`, `AntiExploitService`, `RateLimitService` | Additive only, isolated commit with a NOTE. |
| `tools/BuyPathStatic.py` | Frozen legacy body. Each lane appends its pins to **`tools/checks/lane_<x>.py`** only (run automatically before the parse gate). The full run must end with `FAIL=0`. |
| `ASSUMPTIONS.md` | Append only, with one dated section per job under a heading like `## 2026-09-28 — lane B: guards fight back`. Never edit older sections. Conflicts here are resolved by keeping both sides. |
| `CLAUDE.md`, `LANES.md`, `MASTER_BUILD_SPEC.md`, handoff docs | Code Bot or the owner. Propose changes in your DONE reply. |
| `RS/Configs/VisualAssetConfig.luau` | Lane A owns the vehicle, air and naval refs. Lanes C and D may add or change their own building and business refs in isolated commits with a NOTE. |

## 4. Feature flags and rollout
- New gameplay ships **owner-only first**: gate it on `AdminConfig.IsPlaytestOwner(userId)` (UserId 470626172), the
  way `ArmyConfig.Rollout` and `AircraftWeaponConfig.LiveFor` do. Give each feature a `Live` or `Enabled` config
  switch. Everyone gets it only after the owner has tested it on his phone and said yes, and Code Bot flips it.
- A flag set to OFF must behave exactly like the code before the change.

## 5. Checks every lane runs before DONE
1. `luau-compile --binary` on every changed `.luau` file (parse gate).
2. `python3 tools/BuyPathStatic.py` ends with `Done PASS=<n> FAIL=0`. New pins go in `tools/checks/lane_<x>.py`,
   and each pin must FAIL without your change.
3. `rojo build default.project.json -o /tmp/we.rbxlx` succeeds.
4. The feature's own tests (headless where possible). Never invent results; say what still needs a real phone.

## 6. Handing back
1. Push your branch to the same remote you cloned from (see section 8). Never push to `phase-7-polish`.
2. Reply **`DONE`** with:
   - the branch and head commit;
   - a summary: what changed and why, plus the files touched, with any out-of-lane file flagged;
   - the tests you ran, with the exact `BuyPathStatic` Done line and the parse and rojo result;
   - what the owner must test on his phone, step by step;
   - any flag or rollout state (owner-only / off / live);
   - anything left open.

## 7. Merge order (Code Bot)
`tools/merge-lanes.sh` lists every `claude/*` branch with new commits and dry-run merges each into `phase-7-polish`
to report conflicts. The default order:
1. isolated shared-file commits (remotes, schema, config keys);
2. lane F (monetisation), then lane C (economy), then lane B (army and combat), then lane A (vehicles and looks),
   then lane D (world), then lane E (UI) last, because UI reads everything else;
3. lane legacy whenever it is ready.
After each merge Code Bot runs BuyPathStatic (FAIL=0), and when a batch is complete it bumps `WE_Build`, builds and
publishes. Conflicts are resolved by Code Bot; a lane branch with conflicts is asked to merge `phase-7-polish` again.

## 8. Where sessions clone and push
Claude sessions clone **`shaunbirrell/Padel-AI`**, branch **`war-empire-handoff`**. It is a mirror of
`phase-7-polish` that Code Bot fast-forwards after every merge. Sessions push their `claude/lane-*` branch to the
same repo. Code Bot fetches `claude/*` from both `shaunbirrell/Padel-AI` and `shaunbirrell/war-empire` (the
legacy branch exists on both), so a session with push access to `shaunbirrell/war-empire` may push there too.
Pick one remote per branch.

## 9. Known conflict magnets
- Lane F vs BuyPathStatic: the frozen body still pins `ImpulseSpeed Id = 0` and `RebirthKeepBase Id = 0` (K1 labels). Wiring the real Ids will FAIL those pins. The lane reports them in DONE; Code Bot moves or retires them when merging.
- VisualAssetConfig and VisualAssetService sit across A, C and D: prefer Additive, isolated commits with a NOTE.
- SquadOrdersService (B) and VehicleService (A) are near the 200-local limit: use module fields.
- ASSUMPTIONS.md: append only. Conflicts are resolved by keeping both sides.
