# ASSUMPTIONS — WAR EMPIRE

Reversible engineering decisions made while implementing the MVP without blocking questions.

1. **Rojo mapping** — `Shared` and `Server` / `Client` trees use `$path`; `ReplicatedStorage.Remotes` is an empty Folder in the project file and is filled at runtime by `RemoteSetup` (also works if Rojo creates the folder).

2. **Base plots** — Exactly 6 plots; first free plot assigned on profile load; occupancy released on leave. `BasePlotId` remains on the profile as a preference for rejoin but occupancy is authoritative in memory.

3. **Starting upgrades** — All structures start at level **0**. Command Center is purchasable with starting $5000 (cost $1500). Barracks requires Command Center L1.

4. **Passive income** — Default tick every **5 seconds**. Base $25/tick + per-structure-level rates from `EconomyConfig`. First Barracks (~$2500) is reachable within about a minute with base income + early upgrades.

5. **Prestige cash mult** — Also applies to passive income for consistency.

6. **Session lock** — Soft lock via secondary DataStore (`WarEmpire_SessionLock_v1`); JobId + timestamp. In Studio without API services, lock/load soft-fails and uses defaults. Live servers still kick on *fresh* lock conflict (Error-style message: data loading in another server). **TTL / takeover (playtest fix):** `Constants.SessionLockTtlSeconds = 45` with heartbeat refresh every `SessionLockRefreshSeconds = 15`. If another server holds the lock but age ≥ TTL, JobId is missing/empty, or lock is ours → Clear and load (steal). Never soft-lock forever after force-quit / place update. `PlayerRemoving` / `BindToClose` always release (or force-release if stale/ours) even when profile was not fully loaded.

7. **DataStore unavailable** — Profiles still work in-memory for the session (Play Solo without API services); persistence requires API services enabled.

8. **Daily rewards** — Day key is UTC `YYYYMMDD`. Streak increments on claim; missed day resets if configured.

9. **DevConfig** — `SkipTutorial = true` only applies when `RunService:IsStudio()`.

10. **Visual upgrades** — Placeholder Parts tagged `WE_UpgradeSlot` resize/recolor on purchase; full models are Phase 3+ art.

11. **Vehicle / weapon names** — Generic military names only (no real-world brands).

12. **Monetization** — `ProcessReceipt` grants known DevProducts only (idempotent `ProcessedReceipts`). Unknown/zero IDs drain the queue without inventing grants. GamePass ownership cached on join via `UserOwnsGamePassAsync`; VIP / DoubleCash / DoubleXP multipliers apply in Economy/XP (exempt: `devproduct` / `admin`). Never grant from client confirmation or `PromptGamePassPurchaseFinished` alone.

13. **Loot boxes** — Explicitly `LootBoxPolicyPending = true`; not implemented.

14. **Level curve** — Formula `floor(100 * level^1.45)` through level 100; preview table for 1–20 in config.

15. **UI** — Fully programmatic ScreenGuis (no rbxmx) for reliable Rojo sync.

16. **BindToClose** — Best-effort save window (~few seconds); not a hard guarantee under Studio stop.

17. **ClanId / BattlePass / Achievements** — Schema fields present. Battle Pass + Clan create/join/leave are live; achievements remain config-driven one-shots.

18. **Anti-exploit** — Rate limits + strike counter; not a full physics anti-cheat.


19. **Combat damage** — Always from `WeaponConfig` (× `Pellets` for shotguns). Client may hint hit target/position; server raycasts and re-validates range/ownership/fire rate/ammo.

20. **Respawn** — After death, wait `GameConfig.RespawnTimeSeconds`, `LoadCharacter`, teleport to assigned plot `PlayerSpawn` (or plot pad + offset).

21. **NPC pool** — Runtime models tagged `WE_NPC`; MapSetup places a few placeholders on Play. Cap `CombatConfig.MaxActiveNPCs`; respawn after `NPCRespawnSeconds`.

22. **PvP** — Gated by `GameConfig.PvPEnabled`; friendly fire by `GameConfig.FriendlyFire`. First PvP engagement logs `FIRST_PVP` once per user session/account flag.


23. **Vehicle models** — Placeholder Part chassis + VehicleSeat (no MeshParts). Driving uses Roblox VehicleSeat physics as a temporary control scheme until custom chassis.

24. **One active vehicle** — Spawning despawns the previous vehicle for that player. Cooldown from `VehicleConfig.SpawnCooldownSeconds`.

25. **Vehicle unlock gates** — Level + optional base structure level (`RequiresStructure`) + cash; starter `MilitaryJeep` granted on join.

26. **Territory ownership** — Runtime world state is authoritative (not only profile.Territories). Profile mirrors personal ownership for persistence/UI. On leave, ownership remains until contested/captured by others.

27. **Territory states** — Neutral / Player / NPC / Clan / Contested. NPC seeds: EastArmory + RadarHill on server start. Clan ownership uses profile.ClanId when set. ClanService persists roster to DataStore `WarEmpire_Clans_v1` (name/owner/members); graceful session-only fallback when API services off. Soft stub rehydrate if ClanId on profile but store miss.

28. **Capture** — Proximity stand-in-zone only (CollectionService `WE_CaptureZone` preferred, else `WE_Territory`). Progress is server tick-based; `RequestCaptureTerritory` is an optional UI ping.

29. **Max personal territories** — `TerritoryConfig.MaxPersonalTerritories` (3). Capturing beyond max releases the least-protected owned territory.

30. **Protection period** — After capture, `ProtectionPeriodSeconds` slows enemy capture via `ProtectedCaptureMult`.

31. **Daily missions** — UTC day key refresh; progress tracked by ObjectiveType from combat/territory/upgrades/cash/vehicles. Claim is separate from complete.

32. **Daily login** — Handled by MissionService (moved from Bootstrap inline handler). Same UTC streak rules.

33. **Achievements** — Config-driven one-time grants checked on mission progress / level-up / upgrades / cash totals.

34. **Shop** — Client prompts Marketplace with placeholder IDs; server ProcessReceipt is idempotent and stores `ProcessedReceipts` on profile when present.

35. **Tutorial** — Steps: ClaimBase → CommandCenter → Income → Barracks → Jeep → Outpost. Server `TutorialService` advances; client shows panel + best-effort `WE_TutorialMarker` waypoints. `DevConfig.SkipTutorial` (Studio) or SKIP button completes. Default `SkipTutorial = false` for playtest.

36. **Studio mock GamePasses** — `DevConfig.MockOwnedGamePasses` or admin `grantpass` only in Studio when product Ids are still 0.


37. **Prestige / Rebirth** — Requires Level ≥ PrestigeConfig.MinLevelToPrestige (**40**, was 100 — reversible; see #108). Resets Cash/Level/XP/BaseUpgrades; keeps Vehicles/Weapons/Gold/RebirthUnlocks; grants GoldBonusOnPrestige; **+10% cash earnings per prestige** (stacking) via EconomyConfig.PrestigeCashMultiplierPerLevel. `DoRebirth` aliases `DoPrestige`. RebirthUnlocks track grants flags + optional vehicles. Admin `forceprestige` / `prestige`.

38. **Battle Pass** — SeasonId from SeasonConfig; XP mirrored from XPService.AddXP; dense Free/Premium tracks (levels 1–50) in BattlePassConfig. Claim UX: CLAIM ALL (level 0 → ClaimAll) + track preview with claimable counts. Premium only via admin `grantpremium` or Monetization ProcessReceipt for `DevProducts.PremiumPass` (Id=0 placeholder; GrantsBattlePassPremium). Never client-granted.

39. **Clan roster** — Create/Join/Leave remotes; MaxMembers 20; DataStore-backed clan records when API services enabled; profile.ClanId always mirrors membership. Territory capture stamps runtime.ClanId from profile.ClanId for same-clan ownership checks.

40. **Soldiers / Army** — SoldierService recruits/dismisses with cash; cap = MaxSoldiersBase + BarracksLevel * SoldiersPerBarracksLevel. Remotes RequestRecruitSoldiers / RequestDismissSoldiers rate-limited. Army UI (A / ARMY).
41. **SeasonService** — CurrentSeasonId + XPBonusMult/CashBonusMult applied server-side in XPService/EconomyService. End override persisted in DataStore `WarEmpire_Season_v1` (key `season_state_v1`) with Studio in-memory fallback. Admin `endseason` / `resumeseason`. Bonuses clear to 1× when inactive. HUD shows season indicator via `SeasonStateUpdate`.
42. **Clan wars** — Leader-only declare; MinClanMembersToDeclare; DeclareCooldownSeconds after settle; richer win/participation/score rewards; scoreboard top-N pushed on `ClanWarStateUpdate`. Progression panel declare UX. Product IDs stay 0.
43. **Loot boxes** — LootBoxConfig.PolicyPending=true; shop shows locked row only; no grant/ProcessReceipt path.
44. **Radar Hill** — Owning MinimapReveal territory enables client enemy Highlight within RadarRevealRadius (not description-only). Contested zones use ContestedProgressMult (0 = freeze + ContestedDecayMult decay).
45. **UI** — Shared `Util/UIUtil` attaches consistent MobileScale across HUD / panels; dark military Constants.Colors.

46. **Module splits (Phase 7 polish)** — `CombatService`, `TerritoryService`, and `ProgressionController` are Rojo folders with `init.luau` façades plus cohesive helpers (`CombatDamage` / `CombatNPC` / `CombatWeaponLogic`; `TerritoryCapture` / `TerritoryOwnership` / `TerritoryRadar`; `ProgressionUI` / `ProgressionBattlePass`). Bootstrap / UIController still require the same public ModuleScripts.

47. **DataVersion 3** — `Constants.CURRENT_DATA_VERSION = 3`. Idempotent migration fills missing `Prestige`, `Soldiers`, `ClanId`, `BattlePass` (+ nested claim maps), territory/achievement tables, and kill/death/territory stats for older saves. Safe when DataStore is off (defaults + migrate on load).

48. **Perf pass** — CollectionService tag lists cached (~2s TTL) in combat; NPC think uses squared distance and skips when no NPCs; territory pushes skip when idle; clan-war settle poll skips empty war table; client HUD/territory/progression redraws are debounced/coalesced. Game rules unchanged.


49. **RemoteGuard** — Server `Modules/RemoteGuard` centralizes id-string length checks, finite int clamps, and RequireProfile for client→server Request* handlers. Shop remotes (`RequestPurchaseDevProduct` / `RequestPurchaseGamePass`) are intent-only (analytics + Id=0 warn); grants remain ProcessReceipt / GamePass ownership only. Admin grants clamp to 1e9 and require profile + AdminConfig. No Give* remotes (RemoteSetup strips them).

50. **Client settings + audio** — `ClientSettings` music/SFX flags are local-only / session-scoped (no DataStore; economy untouched). Settings UI (O) toggles call `ClientSettings` which notifies listeners; `Modules/AudioController` mutes/restores MusicVolume/SFXVolume immediately (0 or restore). Menu ambient Sound uses **placeholder empty SoundId** (muted-ready, no upload); UI click / notification SFX use built-in `rbxasset://sounds/…` paths. **Replace SoundIds in Studio** with licensed / Creator Store audio. NotificationController + Settings / Garage button activates call `PlayNotification` / `PlayClick` when SFX enabled.

51. **Studio smoke** — `tools/SmokeTest.luau` is command-bar pasteable in Play Solo. Validates remotes/configs/services; may invoke `GetPlayerState`; admin probe fires a no-op `__smoke_ping__` only when LocalPlayer is in AdminConfig — never grants cash/gold/XP.

52. **Garage empty states** — `VehicleController` uses `UIUtil.EmptyState` when the vehicle catalog is empty or the player owns nothing yet (clear copy + BUY hint). Screen uses `UIUtil.PrepareScreen` / MobileScale consistent with Army/Shop/Missions.

53. **World prompts + walk-over buy** — `WorldPromptController` attaches ProximityPrompts only for non-buy actions (`WE_BasePlot` Open Base, `WE_VehicleSpawn` Open Garage, capture ping, tutorial). **Upgrade pads (`WE_UpgradeSlot`) use walk-over auto-buy**: Touched + Heartbeat HRP overlap → `RequestPurchaseUpgrade` once per enter with ~1.75s debounce + in-flight guard. Leaving the pad clears overlap so re-enter can buy again after debounce. Server validates cash/prereqs/max; `NotificationService` toasts success/fail. Never grants on client. Only the player's assigned `PlotId` pads purchase (other plots toast "Not your base"). Capture remain stand-in-zone authoritative.

54. **Base upgrade UX** — Primary buy: walk onto pads (mobile-friendly, no hold). Alternate: **B** / Base Upgrades menu → **BUY $price** / **UP $price** (touch ≥44px). Price `WE_PriceBillboard` on every slot shows Name / Lv X→Y / $cost (or MAX / prereq hint); refreshes throttled on BaseStateUpdate / EconomyUpdate. Session-once toasts explain walk-to-buy.

55. **MapSetup auto-build** — `Modules/MapSetup.luau` builds the world (structure kits, territories, pads, NPCs, tutorial beacons, lighting, price billboards). Bootstrap runs it when `Workspace.WarEmpireSetup` is missing (Play / server start) — no command-bar paste (Studio truncates long pastes). Safe re-run clears `WarEmpireSetup`. Admin `resetmap` (Studio) or delete folder + Play to regenerate. `tools/StudioSetup.luau` is a short note only.

55b. **Map scale** — Ground ~4800×4800 studs; 6 base plots on ring radius ~800 with ~200-stud pads; upgrade pads on a 4-col grid with ~42-stud gaps. Territories out to ~1300–1450; coastal oil ~1800; forts ~1450. Vehicle garage pads on ring ~650 (×10); NPC ~550; Event ~500; naval pads along south water band (~z 1580–1720). `BaseConfig.PlotPositions` / `TerritoryConfig` / `OilRigConfig` / void fallback (~5000) stay in sync. FogStart/End ~800/4400; billboard MaxDistance ~900; RadarRevealRadius 550. Respawn/teleport use tagged `PlayerSpawn` on each plot.

56. **Structure level visuals** — `BaseService.UpdateVisuals` / `applyKitVisuals` **ensures** Part kits via `StructureKitBuilder.EnsureKit` (rebuilds bare plinths), then scales `WE_KitRole` children by level. L0 = faint placeholder; L1+ = solid built silhouette (spawn-on-buy). Catalog overlay optional via VisualAssetService after L1.

57. **Vehicle kits** — `VehicleService.buildVehicleModel` dispatches on `VehicleDef.KitFamily` (WheeledLight/Truck/APC, TrackedIFV/MBT/SPAAG/Artillery, Heli*, Jet*, Naval*). `KitScale` + id accents differentiate within a family. VehicleSeat remains driveable. No MeshIds.

58. **Walk-over edge cases** — Respawn / CharacterRemoving clears overlap + pending. Seated in VehicleSeat/Seat skips pad buys (driving over pads). Overlap keyed by `plotId|structureId` so multi-plot / multi-part touches don't collide. Plot reassignment clears overlap. Standing on a pad retries after debounce (failed cash / sequential upgrades); MAX toast throttled. Touched/Prompt connections disconnect on AncestryChanged / tag remove (no leak). Billboard refresh throttled (~0.35s).

59. **Vehicle drive modes** — Ground kits use Roblox VehicleSeat (Torque/MaxSpeed from def). Heli/Jet set `WE_DriveMode=AirPlaceholder` and a server Heartbeat LinearVelocity/AngularVelocity hover+throttle/steer loop while occupied; despawn disconnects the loop and Destroy()s the full kit model.

60. **Base kit refresh** — `RefreshAllVisuals` ensures+applies kits for every `BaseConfig.Structures` id from profile (rehydrate on join with 0s/1s/3s retries). Admin `resetbase` and prestige also refresh. Slot lookup: CollectionService tag + Bases attribute fallback.

61. **Compass HUD** — Client `CompassController` shows direction + distance to assigned base plot and nearest unowned/neutral territory (camera-relative N/NE/…). Lightweight; no minimap mesh.

62. **Day/night** — MapSetup installs Sky + Atmosphere and a cancelable `WE_DayNightMarker` loop (~20 min full day). Night cools ambient/fog; day stays readable on large map. `resetmap` destroys the marker to stop prior loops.

63. **Territory ownership visuals** — `updateMarkerVisual` raises/sizes flags, PointLight, ring thickness, billboard `[OWNED/CONTESTED/HOSTILE NPC/NEUTRAL]` text by owner state.

64. **Onboarding toast** — Session-once after join: `Walk to glowing pads to buy · B/G menus` then a follow-up for prices / B / G / E.

65. **Void-fall (large map)** — Continuous Ground ≥6400×8 (top ~Y=0.5) + invisible SafetyCatch 8000 at Y=-40 + edge berms + MountainRing (~48 ridge segments, heights 40–120). Coastal oil decks have stepped ramps to ground. `FallSafetyService` teleports to plot spawn if HRP Y < -30. Bootstrap soft-heals Ground size/CanCollide/SafetyCatch/mountains or rebuilds. Emergency void fallback baseplate ~7000.

66. **Training Yard / worker income** — Owned soldiers generate pending cash each `SoldierConfig.TrainingIncome` tick (`CashPerSoldierPerTick`) via `AccruePendingCash(..., "training")` → Money Collector / AutoCollect (not direct AddCash). MapSetup TrainingYard targets + worker beams + `+$/tick` billboard. HUD + Army UI show training income/sec. Prestige/VIP/2x apply at accrue.

67. **Coastal oil platforms** — `CoastalOilAlpha` / `CoastalOilBravo` in TerritoryConfig + MapSetup (elevated deck, legs, derrick, OilRigGuard NPCs). Higher CaptureTime, FlatPassiveCash, and StipendCash than land territories. No MT trademark names.

68. **Capture stipends** — `CaptureStipendService` pays owned territories/oil every `TerritoryConfig.CaptureStipend.TickSeconds` (default 90s). Oil uses `OilRigCash` / per-def `StipendCash`. Separate from structure passive tick.

69. **Codes** — `CodesService` redeems config codes once per player (`RedeemedCodes` on profile). Sample: WARFOUNDING, BUILDCONQUER. Settings panel TextBox → `RequestRedeemCode`. Flat grants (`code` cash-mult exempt).

70. **Daily Ops** — `DailyOpsConfig` three gold-forward ops (capture / kill NPC / recruit) prepended into MissionService daily list. Claim via existing mission claim path (`resolveMissionDef`).

71. **Nation color** — `NationColorService` assigns roster color on join (stable from UserId if unset). Captured flags tint via `NationColorService.GetColor` in TerritoryService visuals. Profile `NationColorId`.

72. **DataVersion 4** — Migrates `NationColorId` + `RedeemedCodes`. Product IDs remain 0. MapSetup auto-on-Play + void-fall + ~2600 map unchanged.

73. **Benchmark doc** — `docs/BENCHMARK_MILITARY_TYCOON.md` summarizes public MT loop (place 7180042682 / fandom / guides) for InfinityInteractive-style systems under WAR EMPIRE naming only.

74. **Supply drops** — `SupplyDropService` spawns crates periodically (prefer `WE_EventSpawn`, else scatter). Stand in radius for ClaimHoldSeconds → Cash. MaxActive + Lifetime. Reason `supply_drop` cash-mult exempt.

75. **Empire Bank raid** — MapSetup builds Empire Bank vault (`WE_BankVault`) + BankGuard placeholders. `BankRaidService` stand-to-raid hold + per-player cooldown. Reason `bank_raid` exempt. Stub (no vault HP / lockpick tree yet).

76. **Supply Spinner** — Free reward every `SpinnerConfig.CooldownSeconds` (4h). Weighted Cash/Gold table; `RequestClaimSpinner` rate-limited. Profile `LastSpinnerClaimUnix`. HUD + Settings buttons. Reason `spinner` exempt. Not a paid loot box.

77. **Fortresses** — `FortIronclad` / `FortSandhold` in TerritoryConfig + MapSetup (walls/keep + FortGuard). Higher StipendCash (~10k). MaxPersonalTerritories raised to 6.

78. **DataVersion 5** — Migrates `LastSpinnerClaimUnix`. Group/Discord shout intentionally skipped. MapSetup auto-on-Play + void-fall preserved (map now ~4800).

79. **Naval vehicles + Dock** — `VehicleConfig` Category Ground/Air/Naval. `Dock` (VehicleDepot L2) gates naval ladder through Battleship. MapSetup coastal water band + `WE_NavalSpawn` pads (also `WE_VehicleSpawn`). VehicleService prefers naval pads; KitFamily Part kits; MeshAssetId hooks reserved. SubSurfaceRunner is a surface stub (no dive physics yet).

80. **Expanded vehicle roster** — ~99 vehicles (47 Ground / 27 Air / 25 Naval). `KitFamily` on each def drives VehicleService builders (at ~100 ceiling). Garage filters category + rarity; soft cooldown refresh. Late units use RequiresPrestige / RequiresRebirthFlag. BALANCE.md summarizes curve.

81. **Rebirth cash stack** — AddCash / AccruePendingCash order: base → prestige (1+P×0.10) → VIP/DoubleCash → season. Exempt reasons skip VIP/season only. Structure passive + training → PendingCash; capture stipend / combat / packs stay direct AddCash.

82. **DataVersion 6** — Migrates `RebirthUnlocks` table. Product IDs remain 0. No MT trademarks/assets.

83. **Map expansion ~4800** — Second scale-up after ~2600 toward Military Tycoon–feel footprint. Plot ring 800, pads 200, STRUCT_GAP 42. POIs/oil/forts/bank/supply/naval spread. Bootstrap `WE_VoidFallback` baseplate 5000×5000. Delete `WarEmpireSetup` or admin `resetmap` to regenerate.

84. **Vehicle depth ladder** — Depth pass 3 reached ~99 (85–100 band) via config-only KitFamily adds. Product IDs remain 0. No real brands / no MT names.

85. **Visual kits v2** — Part-based quality pass (no Creator Store meshes unless MeshAssetId already hooked as 0). VehicleService KitFamily: lights/exhaust/hubs; heli rotor disc neon; naval wake strips. CombatService + MapSetup infantry: helmet/vest/legs/rifle. Structure kits richer (doors/windows); GhostTransparency 0.32; readable price billboards. World props: oil crane/rim, fort towers, bank columns, supply straps, training workers. Garage category/rarity chips; Army/Shop gunmetal+gold chrome. Product IDs remain 0. Play only; `resetmap` for new MapSetup kits.

86. **Desert atmosphere (phase-7 polish)** — Bright midday desert lighting (ClockTime ~12.5, warm Ambient, low haze Atmosphere, sandy Ground Material.Sand). MountainRing restyled as terracotta/sienna mesas + buttes (flat caps, striations) keeping CanCollide continuous floor / SafetyCatch / FallSafety from #65. DesertFlora Part kits (cacti/palms/joshua) around rim + sparse mid-map. MapDressing camps/outposts gain adobe buildings, rich canvas tents, wooden watchtowers + flags, campfires. Soldier kits: desert camo + shemagh + clearer rifle. Mobile HUD: currency pill bottom-left + large color-coded action dock (Shop/Rebirth/Orders/Army/Settings, ≥64px). Inspiration-only — no copied meshes/UI/branding.



87. **Pad BUY ScreenGui (mobile)** — Walk-over auto-buy kept as backup. While standing on own-plot `WE_UpgradeSlot`, `WorldPromptController` shows a large bottom gold **BUY {name} · $cost** ScreenGui (≥72px, Activated/touch) firing the same `RequestPurchaseUpgrade` path + toast + Output. Hidden on leave / wrong plot / MAX / prereq. Billboard subtitle: "Stand or tap BUY".

88. **Force Ground rebuild every Play** — Soft-heal alone left void holes in stale `WarEmpireSetup`. Bootstrap now soft-heals then **always** `MapSetup.ForceRebuildGround` (delete+recreate `Map.Ground` + `SafetyCatch`, ≥6400×8, CanCollide=true) and prints size/CanCollide. `PadSupports` collide shelves fill air gaps under elevated pads (deco CanCollide=false never counts as floor). `FallSafetyService` teleports if Y < -2. **`resetmap` remains mandatory** when dead-space persists — stale setup keeps old holes outside Ground.

89. **Studio laptop PERF pass** — `DevConfig.StudioSkipWorldDressing=true` skips `MapDressing` entirely in Studio (set `WarEmpireSetup.ForceDress=true` or `StudioForceDress=true` + `resetmap` to opt in). `WorldDressQuality="Low"` cuts clusters ~60–70% when dressing runs. `StudioSparseFlora=true` + sparse DesertFlora (~6 rim / 2 mid / 2 plot). `MountainRingSegments=14` (was 24); fewer strata/caps/foothills; 4 cardinal buttes (no diagonal / no butte caps). All deco `CastShadow=false`. Dressing deferred: `task.wait()` past first frame then stagger. Output prints PERF note. **Delete `WarEmpireSetup` or `resetmap` required** to drop stale dense dressing from older Play sessions.

90. **Income UX +$/tick** — Pad `WE_PriceBillboard` + pad BUY ScreenGui + Base menu BUY show `+$N/tick` from `EconomyConfig.PassiveIncome.PerLevelRates` (per structure level). Client WorldPromptController refreshes on Base/Economy updates.

91. **Mobile dock Base tile** — HUD MobileActionBar includes BASE (opens BaseController) ahead of Shop/Rebirth/Orders/Army/Settings. All tiles use Activated + dockPress Output/toast.

92. **Soldier / BankGuard visuals** — MapSetup `makeSoldierKit` + CombatService SpawnNPC use R6-ish 2×2×1 torso / ±1.5 arms / ±0.5 legs; Humanoid nameplate OFF; single `NPCLabel` Billboard. BankGuards spawn via BankRaidService → CombatService.SpawnNPC (retry if zero).

93. **VisualAssetConfig / InsertService** — Free Creator Store Model IDs (Jeep 59524622, tank 26007709, UH-60 9337454, Panzer 1379706428, Military meshes pack 28912351, official Soldier 3924234975). `VisualAssetService` LoadAsset + strip scripts + weld non-colliding visual under Part kits. **Skipped in Studio when StudioSkipWorldDressing** (8GB PERF); enable via StudioForceDress or live. Part kits always authoritative. Never paid/MT assets.

94. **Phone publish checklist** — `docs/PUBLISH_CHECKLIST_PHONE.md`. Ship artifact `dist/WarEmpire-PERF.rbxlx`.

95. **BUY edge polish** — Pad BUY shows NEED $ when unaffordable; BOUGHT flash on BaseStateUpdate level-up while standing on pad. Server Success/Warn toasts unchanged.

96. **VisualAsset catalog expand (jet/naval/buildings/desert)** — Free Get Model IDs: jets (4865838 / 28574422 P-38 / 297267045 USAF free), naval (15786579439 Boat / 13195201090 Build-a-Boat template), buildings (138331074285379 Military Base HQ, 9424782 Barracks, 16659447 bunker), desert props (121029612 Cactus, 16354482789 CactusBase2, 108556425657107 Desert Plants). `TryAttachBuildingVisual` / `TryAttachPropVisual` weld non-colliding overlays; MapSetup + sparse DesertFlora hook. Still skipped when `StudioSkipWorldDressing`. Part kits authoritative. Never paid/MT.

97. **Button Activated pass** — Shop / Progression (Rebirth) / Settings / Missions / BP claim rows / HUD spinner use `Activated` + `EnsureMinTouch` (≥44–48px). Phone-scale panels for Shop/Rebirth/Settings/Missions. Pad BUY + dock already Activated.

98. **BuyPathVerify deepen + spawn reliability** — `tools/BuyPathVerify.luau` checks Army/Garage remotes, forbids Give* remotes, asserts Monetization/BattlePass product Ids stay `0`, `LootBoxPolicyPending`, `StudioSkipWorldDressing=true`, pad tag counts, GUI presence. `docs/LIVE_PLAYTEST_AUTOMATION.md` documents Studio harness + Output markers. VehicleService spawn: safer pad lift, pcall build, PrimaryPart/DriverSeat validation, rate-limit toast, SPAWN Ok logging. Army: CharacterAdded + delayed SoldierStateUpdate re-push; client hydrates via GetPlayerState if state missed; FILL CAP empty-slot Warn; EnsureMinTouch. Garage client spawn debounce 0.85s. Shop rows show **STUB** while Id=0. Product IDs remain 0. Keep StudioSkipWorldDressing.


95. **StudioBuySmoke client mirror (overnight)** — `StudioSmokeLog` RemoteEvent + `StudioSmokeClient` FireAllClients echo; no HttpService/%TEMP% file writes. Full vehicle roster free-ID aliases in `VisualAssetConfig` (Part kits remain fallback). Garage added to mobile dock. FallSafety rescues at Y<0. CopyFromBox: `docs/COPYFROMBOX.md`.

99. **VisualAsset catalog depth (overnight)** — Helipad/Airfield/Dock filled (Airport 14313845338 / Airport Model 12370174722 / Shipping Containers 17701461178). Hangar + Warehouse classic free (12120702 / 66269964). Bunker alias 16659447. Character variety: Infantry/HeavyInfantry/Guard/BankGuard/OilRigGuard/FortGuard free Get Model IDs (official Soldier + Respawn Soldiers + SWAT/Police AI packs). Missing vehicle IDs Cruiser/MissileCruiser/FleetCarrier/StrategicBomber aliased. CombatService attaches by NPC `tid`. MapDressing hangars try Hangar overlay. MaxLoadAttempts 48. All economy-verified IsForSale=false Price=nil. AssetId=0 means skip. Part kits authoritative. StudioSkipWorldDressing still skips inserts on 8GB Studio.

100. **BankGuard MoveTo fix + BUY RemoteGuard** — CombatService BodyGyro yaw-only (`MaxTorque Y`) + HipHeight/AutoRotate; CombatNPC.Think faces via gyro only (no Root.CFrame teleport) so BankGuard/Infantry MoveTo+shoot works. BaseService RequestPurchaseUpgrade remote adds RequireProfile + IsIdString before PurchaseUpgrade. CLI: `python3 tools/BuyPathStatic.py` (30 checks). StudioSkipWorldDressing stays true.

101. **BankRaid HUD + remotes patience** — `BankRaidService` FireClient payload now includes `HoldProgress` / `HoldNeed` / `InVault` / `UnderFire` / `Enabled` (+ existing cooldown/cash hints) and pushes ~every 0.25s while the player is in vault radius (or when progress resets). Client `BankRaidController` listens via Shared `Remotes` helper and shows a mobile-friendly bottom gunmetal/gold progress bar: "Raiding Empire Bank…" / "UNDER FIRE — clear guards" / "Cooldown Xm". Server creates/updates `WE_BankRaidStatus` BillboardGui on the tagged vault Part. Shared `Remotes.luau` waits patiently (poll/warn up to ~180s) for RemoteEvents — map load can exceed 10s; never hard-assert after 10s. `RemoteSetup.Init` returns Folder and is idempotent (`_initialized` only gates the ready print; remotes are always ensured, never creates Give* remotes). CombatService/TerritoryService require `script.Parent.Parent.Modules.RemoteGuard` (folder ModuleScripts under Server/Modules). CLI: `python3 tools/BuyPathStatic.py` (35 checks).

102. **Money Collector (PendingCash)** — Structure passive **and training** income accrue to `profile.PendingCash` via `EconomyService.AccruePendingCash` (prestige/VIP/2x/season mult at accrue). Cash is **not** spendable until touch plot `WE_MoneyCollector` (ATM-like grey body + green digit screen) or **AutoCollect** (~2s auto-claim). `CollectPendingCash` grants with reason `collector` (mult-exempt). Billboard + HUD pill show pending. DataVersion **7**. Combat / stipends / shop packs stay direct `AddCash`.

103. **Robux add-ons (Ids=0 stubs)** — `MonetizationConfig.DevProducts`: AutoCollect (99 R$), DoubleCash/2x Money (149 R$), ExtraSoldierSlot (79), InstantBarracks (129), VIPBoost (199), StarterBundle (249) + existing cash/gold/BP packs. `GamePasses.AutoCollect` (99). ProcessReceipt grants `GrantEntitlement` flags on `profile.Entitlements` (and InstantBarracks → Barracks L1). Shop UI shows **DisplayName + Robux price** (not STUB); Id=0 still no Marketplace charge. Server-authoritative only.

104. **Pad toast debounce** — `NotificationService.NotifyThrottled` (~0.85s default). UpgradePadService fails (Not enough cash / prerequisite) throttle ~0.75–1.1s per err+structure while camping. WorldPromptController client soft-fails ~0.9s. Prevents stacked toast spam on BUY pads.

105. **Void walls + drivability** — Ground 7200 + SafetyCatch 10000 + invisible VoidWall* perimeter + edge berms; FallSafety Y<0.15. Vehicles: massless wheels, higher Torque/TurnSpeed, SetNetworkOwner + auto-Sit DriverSeat on garage SPAWN. Live MapDressing quality **Full**; Studio still skips dressing (PERF). Plot-local sandbags/crates/camo always built.

106. **Structure kit spawn + DefensiveWalls perimeter** — Buying any structure (CommandCenter, Barracks, DefensiveWalls, …) must spawn/update visible Part kits on the plot — not profile level alone. `Modules/StructureKitBuilder.luau` builds pad kits; `SyncPerimeterWalls` builds a collide wall ring around `PlotPad` at DefensiveWalls L1+ with a ~10-stud walkable gate facing PlayerSpawn (per-plot axis; GateArch CanCollide=false); `SyncCornerTowers` for Watchtowers L1+. MapSetup kit children start Transparency=1 until BaseService applies. Assumption: Part kits are authoritative (no copyrighted meshes required); placeholders/billboards stay; perimeter walls are plot-scale extras beyond the pad-local wall segment kit.

107. **AdminPlaytestCash (shaunie6 only)** — `AdminConfig.UserIds` includes `470626172` (shaunie6). On profile load, if that UserId's `Cash` is below `AdminConfig.AdminPlaytestCash` (50_000_000), DataService raises Cash to that amount (server-authoritative, marks dirty). Not a global economy change — other players unchanged. Admin remote commands remain gated by the same UserIds list.

108. **MinLevelToPrestige = 40 (P0 competitive)** — Lowered from 100 for faster first rebirth feel vs Military Tycoon. **Reversible:** set `PrestigeConfig.MinLevelToPrestige` back to 100 (or 25) if early prestige breaks economy. Cash mult still +10%/prestige; MaxPrestige 50; AdminPlaytestCash 50M for shaunie6 unchanged. No structure-gate required this round.

109. **Tutorial worker-first (P0)** — Steps: ClaimBase → CommandCenter → **RecruitSoldiers** → Income (collector) → Barracks → Jeep → Outpost. SKIP kept. Army CTA opens ArmyController. Recruit advances on `SoldierService.Recruit` → `TutorialService.Notify("RecruitSoldiers")`.

110. **Brand mesh pack (Design Bot)** — VisualAssetConfig: MilitaryJeep/ArmedJeep/Scout/Recon/Dispatch/Quad → **125916936788670** (fallback JeepFallback **59524622**); Mammoth MBT **19297043**; gunships **295607934**; transport heli **9753309**; light heli **5935419**; Strike/CAS **5507592781**; bomber/cargo/AWACS **3319732457**; trucks **105503568352704** / **107381977457431**; APC **17835143223**. StructureVisualConfig MeshAssetIds wired per Design list. WarzoneProps IDs catalogued. Characters: Soldier 100212659702941; Infantry 9104381136; Heavy 14776506955; Guards 16134469614; CharacterAlt disabled (rejected plastic/Respawn). StripScripts=true; Part kit if load fails. Jeep Part kit olive Metal (no neon green accents) until mesh loads. Drive: auto-Sit retries + WE_DrivePrompt on DriverSeat; garage pad still Open Garage.

## Jeep drive (2026-09-20 live v10)

- **Root cause:** Modern Roblox `VehicleSeat` Torque/MaxSpeed does **not** propel welded Massless wheel kits — Sit/mesh could succeed while the jeep stayed a static prop.
- **Fix:** Authoritative Part chassis + `HingeConstraint` Motor wheels (`WE_DriveHinge`) driven from `VehicleSeat` Throttle/Steer; scripted `LinearVelocity` fallback if no hinges. Catalog mesh (`125916936788670`) is dress-only (CanCollide false, Massless, constraints stripped). Physics wheels hidden when mesh attaches.


## Design competitive pass P0/P1 (2026-09-20 live v12 — map parse hotfix)

**HOTFIX v12 (2026-09-20):** v11 `MapSetup` failed to parse (`neonBeam` table closed with `end)` instead of `}`), so Bootstrap installed the green void-fallback plate — no PlotPad / upgrade pads. Also fixed `VisualAssetService` invalid `(glow :: PointLight).X =` cast-assignments (parse abort). ATM mesh attach is pcall-wrapped (Part kit always remains). PlayerAdded rebuilds if pads missing. Open Cloud Published **versionNumber=12**.


- **ATM:** prefer `75368157644109` (fallback `175462478`, alts `90362241548850` / `76846072091295` / `35409899`); lime PointLight landmark + COLLECT billboard; `MoneyBagFX` `38451313` + sparkles `4221608224` (StripScripts).
- **CashCrate** alt `16803204916` on supply drops.
- **WarzoneProps** key labels fixed (IDs unchanged): Sandbag / SandbagBarrier / SandbagWall / ConcreteBarrier / Crate / MilitaryCrate / AmmoBox / OilBarrel / BarbedWire / Tent / RadioAntenna / Floodlight (+ Flag).
- **VehicleDepot showroom:** Part-kit PlateDark podium + GoldBright ring + rarity billboard; catalog podium `5267267960` / pedestal `130578088310000` / rotator `5389482912`; slow rotate.
- **Upgrade pops:** L2 light/trim, L4 sandbag ring, L5 flag `1679839739` + floodlight + roof smoke.
- **Tutorial:** NeonAccent beam; path collector→CC→Depot; arrow `1143305733` (alt `6333395014`) on first 3 pads; beam asset attr `88687072714005`.
- **HUD:** margin≥16, panel α≤0.15, touch≥56, dock≤8, GoldBright currency stroke, TextOnDark on level panel.
- **Jeep** ModelAssetId stays `125916936788670` (HingeConstraint drive from cb31f57).


## Design visual overhaul + levels (2026-09-20 live v13)

**Design P0 wire (REJECT):** JeepFallback `59524622`; SWAT/police IDs; blocky soldiers `115637567537381`/`23231587`; `107381977457431` as **vehicle** (rehomed to FloodlightTower **prop**); neon Part jeep as primary look.

**WIRE:**
- Jeep family → `125916936788670` dress-only (hinge chassis kept)
- PatrolTruck / SupplyTruck / ArmoredTruck → `105503568352704`
- APC / InfantryCarrier / WheeledIFV / CommandVehicle → `17835143223`
- Soldier/Infantry/Heavy/Guards → `91299598767068` primary; `CharacterAlt` `3924234975` only if primary fails
- PreferMeshMinLevel=1 for all structure MeshAssetIds
- ATM `75368157644109`; ShowroomPodium `5267267960` + Rotator `5389482912`; FloodlightTower `107381977457431`; Flag `1679839739` L5
- Warzone densify 8–12/plot (MapDressing + always-on MapSetup PlotWarzone Part kits, pcall)

**Levels/progression:** `LevelConfig.Milestones` + `GetHudGoal` / `GetUnlockMessage`; XPService toasts; HUD GoalLabel. Prestige objective at L40; territory goals in milestone copy. Soft guidance only — hard gates remain in Vehicle/Weapon/Base/Prestige configs.

**ASSUMPTION:** Catalog mesh scale clamped 0.85–1.2 via VehicleVisualScale; StripScripts; pads never vanish (pcall inserts).

## Design Bot soldier/jeep upgrade (2026-09-20)
- Rejected primary: `3924234975` (plastic Rthro), `91299598767068` (Respawn pack).
- Soldier `100212659702941`, Infantry `9104381136`, Guards `16134469614`, HeavyInfantry `14776506955`.
- MilitaryJeep keeps `125916936788670`; ArmedJeep `122068883442022` (DisplayName Armed Jeep).
- CharacterAlt disabled (`0`) — no plastic fallback.

## Quality leap P0 (2026-09-20 — QUALITY_GAP_RhGjQXJ8n6w)

111. **Plot floor chevrons** — `MapSetup.paintPlotFloorChevrons` paints permanent white `>>>>` Neon arrows on each plot floor: PlayerSpawn → CommandCenter → Barracks → Depot → Weapons (first 5 pads). Visual-only (`PlotFloorChevrons` folder). Complements tutorial beam; does not gate buys.

112. **Asphalt road dashes** — Yellow Neon centerline dashes on plot-ring asphalt roads (RoadDashZ/X). Void walls + SafetyCatch unchanged.

113. **Toast UX** — `NotificationConfig` Success/Collect high-contrast green Fill + bright stroke. Client `NotificationController` punchy GothamBold for Success/Collect. Pad/menu buys toast **"Purchase SUCCESSFUL! …"**. Collect uses type `Collect`. Can't-afford debounced via `NotifyThrottled` (UpgradePad ~0.75–1.1s; BaseService remote ~0.9s).

114. **Soldier visual path** — `SoldierConfig.Visual` R15-ready keys (`Rig`, `VisualKindByRole`, `VisualPlaceholder`, `ModelAssetIdOverride=0`, empty `AccessoryIds` TODO). Catalog IDs only in `VisualAssetConfig.Characters` (Design Bot wire). Part-kit military placeholder when mesh fails / StudioSkipWorldDressing.

115. **Design Bot IDs (supersede)** — Soldier `100212659702941`; Infantry `9104381136`; HeavyInfantry `14776506955`; Guard family `16134469614`. REJECT primary `3924234975` / `91299598767068`. MilitaryJeep `125916936788670`; ArmedJeep `122068883442022`. CharacterAlt `0`.

116. **Levels/prestige** — Milestones + HUD GoalLabel (existing); `MinLevelToPrestige=40`; structure unlock gates remain in `BaseConfig.Requires`.

**Open Cloud live v15 (2026-09-20 Europe/Madrid):** Quality leap P0 + Design Bot soldier/ArmedJeep wire. Place `97112936860418` Published versionNumber=15.

## Design Bot quality-gap spawn wire (2026-09-20 live v16)

**Open Cloud live v16 (2026-09-20 Europe/Madrid):** Place `97112936860418` Published versionNumber=**16**.

- **VisualAssetConfig adds:** `DesertProps.Palm` / `PalmAlt`, `DesertRock` (MeshId pipeline), `MapDressing.AsphaltDecal`, `WarzoneProps.Lantern` / `TentAlt`, `Buildings.DefensiveWallsL3` = 9703136850
- **TrainingYard SquadStalls:** 2–3 kits per plot — Tent + crate stacks + sandbags + Lantern + Infantry (`9104381136`) via `TryAttachPropVisual` / `TryAttachCharacterVisual`. Crouch anim deferred (T-pose OK; `WE_PoseNote=TPose_CrouchAnimPending`)
- **CollectCircle** lime disc at MoneyCollector; ATM still `75368157644109`
- **Floor chevrons** unchanged (v15); asphalt Decal on RoadX/Z strips; DesertFlora densifies Palm/DesertPlants/Cactus/DesertRock
- **DefensiveWalls L3+** prefer heavy mesh `9703136850` (L1 keeps `208197704`); PreferMesh L1+ stays; StripScripts on inserts
- **No regression:** MilitaryJeep / ArmedJeep / Soldier IDs; PlotFloorChevrons; toast contrast

**InsertService risks:** Palm pack / DesertRock MeshPart / heavy wall may fail if third-party inserts disabled — Part kits remain. MeshPart AssetType 40 uses MeshId pipeline (not LoadAsset Model).

## P0 UI + Worker mesh fix (2026-09-20)

Shaun screenshot: stacked billboards + brown Part-kit workers.

- **Workers:** `VisualKindByRole.Worker="Infantry"`; `Characters.Worker=9104381136`; `TryAttachCharacterVisual` **force-inserts even when StudioSkipWorldDressing**; fallback `WorkerFallback/Guard=16134469614` — never leave brown bricks.
- **Billboards:** price `AlwaysOnTop=false`; ATM `WE_CollectBillboard` AlwaysOnTop+MaxDist 28; hide price boards within 12 studs of MoneyCollector; training `+$/tick` on YardPad MaxDist 22 offset Y=3.2; WORKER→TRAINING tags MaxDist 18 offset Y=2.4 muted.
- **HUD:** READY chip above cash pill (no overlap); dock tiles gunmetal + gold 1px stroke + olive icons.

**Open Cloud live v18 (2026-09-20 Europe/Madrid):** Place `97112936860418` Published versionNumber=**18** (P0 UI+Worker).

## 2026-09-20 — Squad Orders walkie (competitor P0)
92. **Squad Orders** — When `Soldiers > 0` (or Army panel open), client shows a compact walkie Orders panel (Follow / Attack / Hold / Retreat). Server `SquadOrdersService` is authoritative: rate-limited `RequestSquadOrder`, field units derived from `SoldierService` count (capped), AI extends Combat MoveTo patterns. Not a second army economy — recruit/dismiss stay in SoldierService. Config: `OrdersConfig`. Remotes: `RequestSquadOrder`, `SquadOrderStateUpdate`. HUD dock / WorldPrompt / TrainingYard billboards untouched.

## 2026-09-20 — Design Bot QUALITY TIER 2 (live v19)
93. **HQ interior** — CommandCenter DressHost props (RadioAntenna×2, AmmoBox, Crate, MilitaryCrate, Lantern, Floodlight, FuelCans) + gunmetal Part desk (`WE_CommandDesk`) with SurfaceGui map fallback.
94. **Depot showroom densify** — podium+rotator + ShowroomPedestalHost2/3 (ghost 0.55) + FlagPole + dual floodlights; `TryAttachShowroomVisual` densify no longer dead-after-return.
95. **Oil spectacle** — MapSetup `OilSpectacle` pads: IndustrialPack 103734805361054 + RustyPipes 131322292868756 + OilBarrel ring; Ultrapump REJECT.
96. **Landmarks** — RadioTower 119021509, SmallFort 67444725, Bunker 16659447 on map hosts (`WarzoneLandmarks`).
97. **MapDressing deferred** — Palm/PalmAlt, DesertRock MeshPart, AsphaltDecal, TrainingYard Tent stalls already wired (v16–v18); EnsureKit rebuilds kits missing dress hosts.

**Open Cloud live v19 (2026-09-20 Europe/Madrid):** Place `97112936860418` Published versionNumber=**19** (QUALITY TIER 2).


## 2026-09-20 — Squad Orders walkie (minimal ship → live v20)
98. **Squad Orders** — Minimal walkie (Follow/Attack/Hold/Retreat) when soldiers>0 or Army open. Server `SquadOrdersService` authoritative + rate-limited `RequestSquadOrder`; field units derive from `SoldierService` (capped). Remotes: `RequestSquadOrder`, `SquadOrderStateUpdate`. Config: `OrdersConfig`. HUD dock ORDERS remains MissionController. No edits to StructureKitBuilder / ManualDropper / WorldPrompt / TrainingYard billboards.

## 2026-09-20 — PvP economy P0: contested outposts + ATM raid (live v22+)
99. **Contested outposts** — `OutpostIncomeStacks` recount from `profile.Territories` via `EconomyService.SyncOutpostIncomeStacks` on capture/loss/profile load. Capturing a zone owned by another player steals that stack contribution. Toasts: `Outpost lost` / `Outpost secured +10% Income`. OwnerUserId already on zone runtime + marker attributes.
100. **ATM raid** — Enemy touching another player's `WE_MoneyCollector` steals 10% of victim `PendingCash` → thief `PendingCash` (`TransferPendingCash`, no remult). 60s cooldown per thief→victim (`EconomyConfig.AtmRaid.AtmRaidCooldownSeconds`). Distance + RateLimit. Own collect / ManualDropper / GrantOutpost path preserved.

## 2026-09-20 — Gate defense door guards + HMG nests (live v23)
101. **GateDefense** — When `DefensiveWalls ≥ 1`, `GateDefenseService` spawns 2 GateGuards (`Characters.GateGuard` / Guard `16134469614`) at GatePost flanks (±6, Design Bot). Patrol along gate; server MoveTo + rifle/SMG damage vs enemy players (not owner, not same nation). Aggro also covers `ProtectCollectorRadius` around plot MoneyCollector (ATM raid deterrent). Walls L4–L5 = Design L1 AutoGuns (`4923345827` Machine Gun Nest, StripScripts + ScaleTo ~5.5 stud) + sandbag nest `8980890767` + sandbags `3525056989`. Part-kit HMG fallback only if insert fails. Elevated tower IDs (`71964514000054` / `10354803684`) NOT used on door flanks. Reads GatePost CFrames only — no StructureKitBuilder / ScaleTo / AtmRaid edits. Config: `GateDefenseConfig`. Recreate from walls level on join.

## 2026-09-20 — Siegeable gates + near-plot oil + death shop (live v24)

102. **Siegeable gates** — `GateDefenseConfig.GateMaxHealthByWallsLevel` + `GateDefenseService` spawns collide `GateBarrier` leaves across GatePost opening (HP billboard). Enemy weapon hits validated server-side (`CombatService` → `ApplyDamage`). On 0 HP: CanCollide false + rubble tint + owner toast "Gate breached!"; auto-rebuild after `GateRebuildSeconds` OR owner ProximityPrompt repair (`GateRepairCashCost`) OR walls re-upgrade SyncPlot. Guards/AutoGuns keep shooting. Does **not** edit StructureKitBuilder ScaleTo / AtmRaid.
103. **Near-plot oil pumps** — `PlotOilPumpService` auto-spawns 1–2 pumpjacks outside walls toward warzone when DefensiveWalls ≥ 2. Accrues PendingCash (`plot_oil`). Floating $+ billboard. Part kit + IndustrialPack dress. OilRig Alpha/Bravo untouched.
104. **Death shop offer (P1 light)** — On PvP death, server Notify + `DeathShopOffer` remote; ShopController opens shop and prompts DoubleCash/SpeedBoost only if DevProduct Id ≠ 0 (stubs Id=0).

## 2026-09-20 — Base Ceiling anti-heli roof + polish (live v25)
105. **Base Ceiling** — Unlocks at `DefensiveWalls ≥ L3`. `StructureKitBuilder.SyncBaseCeiling` builds `WE_BaseCeiling` gunmetal/olive translucent collide roof over plot core (ATM + main buildings). Gate-front spawn road left open (`GATE_FRONT_OPEN`). Sync on join / UpdateVisuals from walls level. Part-kit authoritative; `VisualAssetConfig.Buildings.BaseCeiling` AssetId=0 (no invented paid IDs). Roof helipad Part-kit H pad + optional existing Helipad mesh dress (`14313845338`).
106. **OutpostIncomeStacks survive prestige** — PrestigeService does not clear `OutpostIncomeStacks` or `Territories`; re-calls `SyncOutpostIncomeStacks` after rebirth. PrestigeConfig RebirthUnlocks unchanged.
107. **HUD rebirth progress** — Goal line shows `Rebirth Lv/Min (pct%)` until MinLevelToPrestige (40), then READY.
108. **Capture zone billboards** — MapSetup TERRITORIES use DisplayName + larger MaxDistance for clarity.

## 2026-09-20 — Roof barracks + Missions dock + rebirth fee (live v26)
109. **Roof barracks slots** — On `WE_BaseCeiling` (walls L3+), SyncBaseCeiling places 1 (L3–4) or 2 (L5) small Barracks-style Part-kit pads on the roof, offset from RoofHelipad; optional Barracks mesh dress (`18798977801`). Gate-front stay open (no seal).
110. **Missions HUD dock** — Dock tile `MISSIONS` (gunmetal) opens existing `MissionController` (MissionConfig daily list). Replaces mislabeled ORDERS dock entry; squad Orders walkie unchanged (auto-shows with soldiers).
111. **Rebirth fee clarity** — `PrestigeConfig.CashFee` (default 0) + `BuildFeeSummary`; PrestigeState pushes `FeeSummary` / `BaseCompletionPercent` (owned structures / max). Confirm copy + CanPrestige join toast show fee/reset/keeps. MinLevel 40 + RebirthUnlocks + OutpostIncomeStacks keep unchanged.

## 2026-09-20 — Jeep drivability fix (live v27 — Open Cloud Published versionNumber=27)

112. **MilitaryJeep / ArmedJeep undrivable on live** — Verified root cause (not hunch):
    1. `startGroundDrive` set `h.AngularVelocity = -spin * WE_WheelSide`, so under pure throttle left/right hinges **counter-rotated and canceled**.
    2. When any `WE_DriveHinge` existed, `LinearVelocity.MaxForce` was forced to **0**, removing the scripted backup — jeep sat as a static prop after Sit.
    3. Physics wheels were Z-rotated 90° (cylinder stood on end); axle no longer along body X.
    **Fix:** Authoritative `LinearVelocity` + `AngularVelocity` always on (MaxForce/MaxTorque kept). Hinge motors use **same throttle sign both sides** + steer differential. Cylinder wheels identity-oriented (axle = local X = body X). Mesh `125916936788670` remains dress-only (StripScripts / no collide). `SetNetworkOwner(player)` + auto-Sit + `WE_DrivePrompt` unchanged. ArmedJeep shares `WheeledLight` kit.

## 2026-09-20 — Quality audit polish (live v28 — Open Cloud Published versionNumber=28)

113. **Cash HUD `+` → Shop** — Competitor pattern: `CashPlus` on currency pill + pending-cash line open Shop via `HUDController.BindShopOpener` (UIController). Shop still lists Id=0 stubs as coming soon; PromptProductPurchase only when Id≠0. MonetizationConfig Ids unchanged.
114. **Premium floor pads deferred** — AutoCollect/2x pads skipped while all Monetization Ids=0 (would confuse). Documented in `docs/QUALITY_AUDIT_v27.md`.
115. **Bootstrap audit** — Vehicle / GateDefense / ManualDropper / PlotOilPump / Prestige / Missions / Orders / MoneyCollector / Monetization ProcessReceipt all wired. Experience rename still pending (`LIVE_PLACE.md`).

## 2026-09-20 — Monetization live + video-feel polish (live v29 — Open Cloud Published versionNumber=29)

- MonetizationConfig live GamePass/DevProduct Ids; HideFromShop duplicate AutoCollect/DoubleCash/VIPBoost DevProducts
- MapSetup ATM-cluster premium pads (AutoCollect / 2x Cash / SpeedBoost / GoldenPumpjack) + PremiumPadService → PromptPremiumPad
- Shop CashMega ★ BEST OFFER hero first among cash; PromptPremiumPad client prompts real Robux
- Rebirth confirm: prominent `★ Keep all your Robux Items!` banner (Entitlements survive prestige)
- Orders hotkeys: 1–4 = Attack/Hold/Follow/Retreat when walkie open or Radio equipped; T cycles
- Contested capture billboard: `⚠ CONTESTED` badge + progress% + enemy present
- BaseCeiling SyncBaseCeiling: thicker plate + beams/joists/braces (not flat slab)
- PlotOilPump GoldenPumpjack entitlement gold dress (Id=0 stub pad)
- docs/LIVE_PLACE.md product table; experience WAR EMPIRE; API Services noted
- BuyPathStatic PASS=273; no-regress jeep LV / GateDefense / AtmRaid

## 2026-09-20 — Death shop toast + producer polish (live v30 — Open Cloud Published versionNumber=30)

- **Death shop offers** — PvP death → mobile toast (`DeathShopToast`) with live DoubleCash GamePass + SpeedBoost DevProduct buttons; server+client debounce; PromptGamePassPurchase / PromptProductPurchase only on tap
- **GoldenPumpjack** — Id=0 → MapSetup `premiumOfferIdLive` hides GoldenPump pad; ProcessReceipt/GrantEntitlement + PlotOilPump SyncPlot ready when Id pasted
- **Floating $** — Oil pumps show `+$N/tick` billboard + `WE_OilCashPop` on accrue; TrainingYard existing earn billboard/pop kept
- **Floor chevrons** — PlotFloorChevrons extend to ATM/premium cluster
- **Army UI** — ★ COMMANDER PACK (StarterBundle) + ExtraSoldierSlot Robux rows above free recruits
- **Mobile Orders** — larger SizeTouch walkie + MinTouchPx 52
- **Shop** — Id=0 DevProducts skipped (HideFromShop duplicates AutoCollect/DoubleCash/VIPBoost/GoldenPumpjack)
- ExtraSoldierSlot +1 cap; SpeedBoost 1.25× WalkSpeed on grant/respawn
- BuyPathStatic PASS; no-regress jeep LV / GateDefense / AtmRaid / PremiumPad / Monetization Ids


## 2026-09-20 — Onboarding + overlay polish (live v31 — Open Cloud Published versionNumber=31)

- **Tutorial first-2-min** — Reordered: Claim → MoneyCollector → ClickDropper → CommandCenter buy → Recruit → Barracks → Jeep → Outpost. ManualDropper fires `TutorialService.Notify("ManualDrop")`. MapSetup `Tutorial_Dropper` marker.
- **Supply Drop / Season** — SupplyDrop BillboardGui `AlwaysOnTop=false` + MaxDistance 90; WorldPrompt hides supply labels near pads; SeasonLabel lighter/ZIndex 2 + still hides near pads.
- **Capture toast** — Single clear `{Zone} secured — +10% Income` when outpost income stack increases (no double Captured spam).
- **Jeep WASD tip** — One-shot `Press WASD to drive` after VehicleSeat Occupant (session).
- **VIP / AutoCollect OWNED** — VIP premium pad added; GamePass pads show OWNED via client `UserOwnsGamePassAsync` + LocalTransparencyModifier; server toast "OWNED".
- **DataStore/API** — Documented only (`docs/LIVE_PLACE.md`); API Services remain enabled.
- BuyPathStatic PASS; no-regress jeep LV / GateDefense / AtmRaid / PremiumPad / Monetization Ids.

## 2026-09-20 — VIP mult + StarterBundle offer + capture flag polish (live v32 — Open Cloud Published versionNumber=32)

116. **VIP CashBonusMult** — Confirmed `MonetizationService.GetCashMultiplier` applies GamePass VIP `CashBonusMult` (+0.25 additive) when owned (GamePass cache or Entitlement); `EconomyService` stacks it on AccruePendingCash / AddCash (non-exempt). VIP premium pad OWNED path unchanged.
117. **StarterBundle first-join offer** — Once per profile (`StarterBundleOffered`). Server delays ~8s after load; if cash ≤ 12k or newish profile and not owned, fires `StarterBundleOffer` + soft Notify. Client toast → `PromptProductPurchase` StarterBundle Id live (3713839505). Never auto-prompts Marketplace.
118. **Capture zone floating flag** — TerritoryService syncs `_FlagStripe` to flag; nation-color AlwaysOnTop diamond billboard (`WE_FlagBillboard`) when owned/contested via NationColorService color.
119. **Manual dropper green $** — Larger AlwaysOnTop `+$N` pop + `CashPopGlow` stroke (competitor-style).
120. **Garage ArmedJeep** — Lists with DisplayName "Armed Jeep" + ARMED chip; same `WheeledLight` kit + `startGroundDrive` as MilitaryJeep.
121. BuyPathStatic PASS; no-regress jeep LV / GateDefense / AtmRaid / PremiumPad / Monetization Ids / Tutorial.

## 2026-09-20 — Quality pack: names, kits, gates, ATM raid UX (live v33 — Open Cloud Published versionNumber=33)

122. **Structure name readability** — WorldPrompt BUY boards: AlwaysOnTop within MaxDistance 56, larger 300×132 high-contrast board, UPPERCASE gold titles + TextStroke; `ensurePadNameSurface` now applied every refresh (SurfaceGui on pad top).
123. **Airfield / Warehouse / Watchtowers** — StructureKit KIT_GEN/BuildingDressGen **22**; taller tower 10×28 + deck/ladder; runway chevrons + larger hangar; warehouse bay + crates; corner towers taller. Mesh IDs unchanged (Design Bot).
124. **Gate guards polish** — Clear rifle props (stock/mag/barrel/sight) + larger AlwaysOnTop GATE GUARD + WeaponLabel billboard. AutoGuns / SyncPlot / ApplyDamage unchanged.
125. **ATM raid UX** — Explicit 10% / 1m toasts; cooldown Notify + `AtmRaidStateUpdate` → ShopController AtmRaidHud chip.
126. **Capture steal clarity** — Steal vs secure toasts (`ToastStealGain` / `ToastStolenFromYou`); loser gets zone-named Outpost lost toast.
127. **Monetization soft touch** — One-shot AutoCollect GamePass soft offer after first manual ATM collect (`AutoCollectOffered`); existing Id 1985115501 only.
128. **Map dressing** — `dressPlotPadSandbags` berms + mini-chevrons near first 6 BUY pads + ATM.
129. BuyPathStatic PASS; no-regress jeep LV / GateDefense / AtmRaid / PremiumPad / Monetization Ids / Tutorial.

## 2026-09-20 — Competitor-feel legitimacy pack (live v34 — Open Cloud Published versionNumber=34)

130. **HQ / Barracks / WeaponsFacility kits** — KIT_GEN / BuildingDressGen **23**. CommandCenter compound wings + entry; Barracks bunk windows + sandbag berm; WeaponsFacility 3-story armory + gun racks + dress hosts. Mesh IDs unchanged (Design Bot VisualAssetConfig).
131. **Soldier variety** — Worker ModelAssetId → Soldier mesh `100212659702941` (distinct from Infantry `9104381136`); stalls cycle Infantry / HeavyInfantry / Guard; Part helmet/vest/accent dress by role when mesh fails.
132. **Garage vehicle labels** — World billboard DisplayName + Sit/WASD tip; garage rows show drive tip + DisplayName. MilitaryJeep WE_GroundDrive LV+hinge unchanged.
133. **Rebirth / Missions polish** — HUD goal shows Fee: none · +10%/P · keep Robux; FeeSummary leads with Base % + "+10% cash forever".
134. **Monetization soft touch** — One-shot DoubleCash GamePass soft offer after ATM collect ≥ $2500 once AutoCollect already teased/owned (`DoubleCashOffered`); existing Id 1982865711 only.
135. **Capture zone chip** — Non-contested capturing shows OwnerChip `CAPTURING · N%` + owner was-state; contested billboard kept.
136. **Mobile UX** — Orders walkie SizeTouch 268×236, MinTouchPx 56, raised above dock. Shop/Orders touch targets remain large.
137. BuyPathStatic PASS; no-regress jeep LV / GateDefense / AtmRaid / PremiumPad / Monetization Ids / Tutorial / VIP OWNED.

## 2026-09-20 — Legitimacy / late-game presence pack (live v35 — Open Cloud Published versionNumber=35)

138. **SpecialForcesFacility densify** — KIT_GEN / BuildingDressGen **24**. Proper `special` kit: dark ops hall + annex wings + watch post + training range targets + dress hosts (was generic cube fallback).
139. **Helipad / Dock densify** — Helipad ~28 stud pad + circle markings + 4 floodlights + windsock + ops hut; Dock longer pier + bollards + crane + warehouse shed + tire fenders. TrainingYard remains MapSetup (not a BaseConfig structure key). Readable DisplayNames unchanged (Helipad / Naval Dock / Special Forces Facility).
140. **Map landmarks** — `Landmarks_v35`: wrecked jeep/truck cluster + scorch + crates/drums/sandbags; extra bunker silhouette; Full quality adds radio tower + second bunker.
141. **Gate AutoGuns visual** — Part-kit HMG tripod + shield + long barrel + neon muzzle; always-on `WE_TurretMarker` ring + AUTO GUN billboard even when catalog mesh loads.
142. **VIP soft offer** — One-shot toast for GamePass VIP Id **1985475542** after level ≥10 or first structure L3 (`VIPOffered`); existing Id only; not spammy.
143. **Oil pump spectacle** — PlotOilPump walking beam + HorseHead bob together (faster amp); $+$/tick billboards unchanged.
144. **Death / shop continuity** — DeathShopToast kept; Open Shop · Cash Mega opens shop with CashMega row highlight.
145. BuyPathStatic PASS; no-regress jeep LV / GateDefense / AtmRaid / PremiumPad / Monetization Ids / Tutorial / VIP OWNED / v33–v34 kits.

## 2026-09-20 — Warzone density + late vehicle/presence pack (live v36 — Open Cloud Published versionNumber=36)

146. **LightTank / TrackedMBT drive** — Tracked kits use hinged road wheels + same `startGroundDrive` LV+HingeMotor path as MilitaryJeep; slower cruise/steer (`isTracked`); DisplayName tip `TRACKED · Sit · WASD (slow)`. Mesh dress via existing VisualAssetConfig Ids (LightTank 26007709). Jeep LV+HingeMotor unchanged.
147. **ArmedJeep combat cue** — Sit tip `ARMED · Sit · WASD` + `WE_ArmedCue` billboard + brief `WE_MuzzleFlash` PointLight on Occupant (no fire logic yet).
148. **Warzone MapDressing density** — `RoadWarzone_v36`: crater/sandbag/chevron clusters on roads between plots (Full denser; Low modest). Landmarks_v35 kept.
149. **Defensive Walls upgrade visual** — Thicker/taller by level; military GateArch + GateChevron + GATE · L# sign.
150. **Watchtower shooters** — 1–2 static sniper silhouette Parts on corner tower decks (`WE_TowerShooter` + SNIPER billboard). GateDefense combat path unchanged.
151. **SpeedBoost soft offer** — One-shot toast for DevProduct Id **3713839342** after first jeep sit or walk-speed moment (`SpeedBoostOffered`); existing Id only.
152. **HUD cash contrast** — Bright mint Cash/Pending + dark TextStroke; darker currency pill (not yellow/gold readability).
153. BuyPathStatic PASS; no-regress jeep LV / GateDefense / AtmRaid / PremiumPad / Monetization Ids / Tutorial / VIP OWNED / v33–v35 kits/landmarks.

## 2026-09-20 — Air/naval presence + midgame polish (live v37 — Open Cloud Published versionNumber=37)

154. **Helipad parked aircraft** — KIT_GEN / BuildingDressGen **25**. When Helipad L1+, Part-kit parked TransportHeli silhouette + `WE_DressHost_ParkedHeli` mesh dress (`VisualAssetConfig.Vehicles.TransportHeli` 9753309) via `TryAttachParkedPresence`. Static only (not flyable).
155. **Dock parked boat** — Naval Dock L1+ Part-kit PatrolBoat silhouette + `WE_DressHost_ParkedBoat` mesh (`PatrolBoat` 15786579439). Static only.
156. **Airfield runway markings** — Centerline dashes + threshold chevrons + taxi amber edge lights on Part kit (composite dress unchanged).
157. **Missions dock polish** — DailyUpgrade/Recruit Target=1 (first ~5 min); order Upgrade→Recruit→Spawn first; progress chip + clearer ★ reward copy.
158. **Level-up celebration** — XPUpdate `LevelUp=true` → HUD high-contrast banner + PlayNotification SFX; server Success toast `★ LEVEL N!`.
159. **CashMega soft offer** — One-shot toast for DevProduct Id **3713838952** after pending collect ≥ $15k OR death path if not offered (`CashMegaOffered`); existing Id only.
160. **Garage empty state** — Clear "buy Vehicle Depot / unlock Military Jeep" guidance when nothing owned.
161. BuyPathStatic PASS; no-regress jeep LV+HingeMotor / GateDefense / AtmRaid / PremiumPad / Monetization Ids / Tutorial / VIP OWNED / v33–v36 kits/landmarks.

## 2026-09-20 — Combat feel + prestige/monetization polish (live v38 — Open Cloud Published versionNumber=38)

162. **Gate defense feedback** — When GateGuards/AutoGuns hit an enemy player, owner gets throttled `DEF HIT · Name (−N HP)` toast. Gate HP=0 billboard/toast clear **BREACHED** (repair/rebuild path unchanged).
163. **ATM raid defender alert** — Victim toast `ATM RAIDED −10% by {thief} (−$N)` + `AtmRaidStateUpdate.ThiefName` for red HUD chip.
164. **Capture zone combat** — Contested stores ContesterA/B; world flag + capture bar pulse between both nation colors; secure toast `★ SECURED …`.
165. **Prestige near CTA** — `NearPrestigeLevels=2`; soft toast + HUD banner “Keep all Robux Items · press K” when Level ≥ Min−2.
166. **Soft offer anti-spam** — `SoftOfferSessionCooldownSeconds=60` + `ClaimSoftOfferSlot` shared across StarterBundle/VIP/SpeedBoost/CashMega/AutoCollect/DoubleCash (Offered flags still one-shot).
167. **Soldier Orders feel** — On order, nearest squad unit billboard flashes FOLLOWING / HOLDING / ATTACKING / RETREATING (~2.8s).
168. **Warehouse crates** — KIT_GEN 26 densifies Warehouse interior with Crate Part props + dress hosts (L1+ via EnsureKit).
169. BuyPathStatic PASS; no-regress jeep LV+HingeMotor / GateDefense / AtmRaid / PremiumPad / Monetization Ids / Tutorial / VIP OWNED / v33–v37 kits/soft offers/parked presence.

## 2026-09-20 — P0 live hotfix v39 (billboards / walls / building kits)

Shaun playtest screenshots (flat grey pad, giant AIRFIELD/RADAR/HELIPAD/HQ/BARRACKS black tabs, crates/sandbags only, no hangars/walls):

169. **Giant structure name boards** — Root: v33 `PRICE_BILLBOARD_SIZE` 300×132 + `AlwaysOnTop=true` + owned MAX still full boards. Fix: chip `160×52` (owned `120×32`), `AlwaysOnTop=false`, StudsOffset Y~5.5, MaxDistance 42; owned strips pad SurfaceGui wash.
170. **Missing buildings** — Root: `VisualAssetService.hideKitBody` set Body/Roof Transparency≥0.92 after catalog mesh attach; meshes often invisible/mis-scaled → empty pads with neon Accent rings + sandbag pops only. Also Body `bodyScale=1+lv*0.55` buried kits without LocalOffset re-place. Fix: hideKitBody no-op (Part kits stay solid); bottom-anchored `placeKitPart`; bodyScale `1+lv*0.12`; Warehouse `Crate` role handled; KIT_GEN/BuildingDressGen **27**.
171. **Missing DefensiveWalls perimeter** — SyncPerimeterWalls hardened (warn if no pad); removed L3+ catalog dress on Wall* segments (Part walls authoritative); `WE_PerimeterGen` attr; still called from UpdateVisuals + RefreshAllVisuals.
172. **Orders panel** — SizeTouch `200×176` (was 268×236).

Do not regress: WE_GroundDrive, monetization IDs, AtmRaid, GateDefense, Tutorial.

## 2026-09-20 — Orders/UI polish + design gaps (live v40 — Open Cloud Published versionNumber=40)

173. **Orders walkie** — SizeTouch `200×168`, `PanelMaxWidth=220` / `PanelMaxHeight=190` UISizeConstraint, `MobileScaleMax=0.85` (no PrepareScreen 1.1 blow-up). MinTouchPx 56 + hotkeys 1–4/T unchanged.
174. **WorldPrompt chips** — `PRICE_CHIP_MAX_W=160` + `clampChipSize` defensive clamp (sizes already 160×52 / owned 120×32).
175. **Design gaps** — `docs/DESIGN_WIRE_GAPS_v40.md` lists ModelAssetId=0 + reused vehicle/structure/soldier IDs for Design Bot. No kit / hideKitBody / KIT_GEN / Jeep / monetization changes.

## 2026-09-20 — Design Feature Wire v41 (live v41 — Open Cloud Published versionNumber=41)

176. **Structures KEEP** — HQ/Barracks/Depot/Warehouse/Hangar/Weapons/Helipad/Dock/Watchtowers/Radar/Power/Research/MissileDefense/Bunker mesh IDs unchanged from live. Airfield composite MeshAssetId=0. BaseCeiling Part-kit only.
177. **DefensiveWalls = 0** — `StructureVisualConfig` + `VisualAssetConfig.Buildings` MeshAssetId / L3 / ModelAssetId all **0**. No Wall* segment catalog dress (v39 safety). Part-kit perimeter only.
178. **BaseGate prop** — `VisualAssetConfig.Buildings.BaseGate = 85138026` (DisplayName **Base Gate**). `SyncPerimeterWalls` dresses **GateArch** only via `TryAttachBuildingVisual` + StripScripts. Nation arches rejected. KIT_GEN stays **27** (no wall wipe); BuildingDressGen / VAS DRESS_GEN **28**.
179. **Vehicles uniqueness** — LightTank/CombatIFV/AssaultIFV → `76055078503396`; cargo trucks → `100684175`; logistics → `81802040484766`; TroopTransport → `4128346779`; PatrolBoat/Gunboat/CoastCutter → `557152593`; FastAttack/Torpedo → `16692908395`; LandingCraft + capital ships → **0** (REJECT `13195201090`). MediumTank soft-keep `26007709`. Jeep WE_GroundDrive untouched.
180. **Soldiers** — Worker → `16134469614` (VisualKind Worker); SpecialForces → `123239877613650` (+ Alt `4851009700`); Infantry/Heavy/Guard KEEP.
181. **OilPumpjack** — `IndustrialProps.OilPumpjack = 13525922265` (+ Alt); `PlotOilPumpConfig.VisualPropKey = "OilPumpjack"`.
182. **Safety no-regress** — hideKitBody remains no-op; placeKitPart bottom-anchored; monetization IDs untouched; billboards ≤160.
183. BuyPathStatic PASS; InsertService-risk IDs (ping Design Bot on reject): `76055078503396`, `81802040484766`, `123239877613650`, `16692908395`, `13525922265`, `4128346779`, `100684175`, `85138026`.

