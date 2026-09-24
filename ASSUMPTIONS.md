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

## 2026-09-20 — Design Wire Gaps fill v42 (live v42 — Open Cloud Published versionNumber=42)

184. **Structures uniqueness** — Hangar KEEP `6015472062`. Warehouse → `15942568272`. VehicleDepot → `12208876851`. MissileDefense → `11962508154` (footprint `14×10×18`, ≠ Watchtower `108525417345747`). DefensiveWalls MeshAssetId=0 + BaseGate GateArch-only unchanged.
185. **Vehicles uniqueness** — LightTank/IFV/EngineerTrack/Scout KEEP/extend `76055078503396`. MediumTank only `26007709`. SPAAG `15618784436`. MobileSAM `14074034450`. Howitzer family `10286064243`. RocketArtillery `18406068364`. Frigate/Corvette/CarrierEscort `12794395111`. Destroyer/Battleship `2048010298`. Cruiser/MissileCruiser `74585287273804`. LandingCraft/Carrier/FleetCarrier stay **0** (REJECT `13195201090`). Capital keys already existed in VisualAssetConfig — ModelAssetId set only; VehicleService spawn path unchanged.
186. **Soldiers** — Worker KEEP `16134469614` ≠ Soldier `100212659702941`.
187. **Safety no-regress** — hideKitBody remains no-op; KIT_GEN stays **27**; BuildingDressGen / VAS DRESS_GEN **29**; Jeep WE_GroundDrive + monetization IDs untouched; billboards ≤160.
188. BuyPathStatic PASS; InsertService-risk NEW IDs (ping Design Bot on reject): `15942568272`, `12208876851`, `11962508154`, `15618784436`, `14074034450`, `10286064243`, `18406068364`, `12794395111`, `2048010298`, `74585287273804`. Alts: MissileDefenseAlt `14074034450`, HowitzerAlt `8312399501`, RocketArtilleryAlt `10355405319`.



## 2026-09-20 — P0 visibility hotfix v43 (live v43 — Open Cloud Published versionNumber=43)

Shaun playtest (admin $50M, many L5 MAX chips, flat grey plot, glowing pads, tiny grey boxes, no HQ/Barracks/walls):

189. **Buildings ROOT CAUSE** — Kits spawn at `Transparency=1` until `applyKitVisuals` solidifies; PreferMesh `InsertService` ran synchronously and could race/skip solidify perception on soft-rejoin; KIT_GEN stayed **27** across v41/v42 so Attribute gating skipped rebuild of stale MapSetup-sized / incomplete kits. hideKitBody already no-op since v39 — mesh dress was never allowed to ghost kits, but Part kits still never became solid silhouettes on live.
190. **Walls ROOT CAUSE** — `SyncPerimeterWalls` Part walls are authoritative (mesh=0), but `ReleasePlot`→`ClearPlotExtras` wipes perimeter and soft-rejoin could miss rebuild when pad/slot discovery lagged; BaseGate GateArch dress is deferred+pcall (not the abort). No vertical walls despite DefensiveWalls L≥1.
191. **Fix** — KIT_GEN **28** force rebuild; EnsureKit always asserts Body (generic Body+Roof fallback); applyKitVisuals coerces level, Body assert, **defers** PreferMesh so InsertService never blocks kit solidify; re-assert Body/Roof after mesh; RefreshAllVisuals walls-first + retries 0/0.5/1/2/3s; findUpgradeSlots `tonumber(PlotId)`; SyncPerimeterWalls rebuilds when `WE_PerimeterGen < KIT_GEN` or empty; depot Roof sized to Body; hideKitBody remains no-op; no new Design mesh IDs; Orders/jeep/monetization untouched.
192. BuyPathStatic PASS (EnsureKit Body path; SyncPerimeterWalls no early-return on mesh fail; hideKitBody no-op).

## 2026-09-20 — P0 visibility hard-fix v44 (live v44 — Open Cloud Published versionNumber=44)

Shaun playtest (admin $50M, LVL2, many pads, Orders OK): flat TAN wall blocks on ground, MissileDefense pad empty, mostly empty base, one small grey neon box.

193. **ROOT CAUSE — flat walls** — `SyncPerimeterWalls` wall Size/CFrame left short/wrong-axis segments that read as slabs on the pad; KIT_GEN 28 did not force a tall rebuild. **Fix:** KIT_GEN **29**, height `math.max(12, 10+lv*2.5)` (L1≥12, L5≥20), Y = padTop+height/2, Size Y = height, orphan Wall* destroy + Y assert.
194. **ROOT CAUSE — empty pads** — Part kits spawned at `Transparency=1` until `applyKitVisuals`; PreferMesh InsertService + VAS host fade (`Transparency=math.max(...,0.55–0.7)`) left ghost/missing silhouettes when mesh failed. **Fix:** kitPart Body/Roof spawn at SolidTransparency; EnsureKit solidifies immediately; `PreferMeshWhenAssetIdSet=false`; VAS `keepKitSolid` + never raise structure host Transparency; NuclearRehydrateKits on join; RefreshAllVisuals walls-first at 0/0.35/1/2/4s.
195. MissileDefense dedicated launcher Body+Roof kit (not watchtower). No new Design mesh IDs.
196. BuyPathStatic PASS (KIT_GEN≥29, PreferMesh off, wall height≥12, EnsureKit solid path).

## 2026-09-20 — v44b tall-wall restore (Open Cloud versionNumber=45)

Shaun: previously fully-bought walls went HIGH; now only short tan slabs.
197. **Wall height** — `height = math.max(12, 7.5 + lv * 2.8)` (L5≈21.5); Size `(len, height, thick)` with height on **Y**; y=padTop+height/2.
198. **KIT_GEN 30** + rebuild if any Wall* Size.Y < 12 (flat slabs never kept).
199. DefensiveWalls pad kit Body raised 8→16 studs so pad sample is not a ground slab.
200. PreferMesh structures still OFF; Part kits solid at EnsureKit unchanged.

## 2026-09-21 — v45 PlotId tonumber + map race + tall walls (Open Cloud versionNumber=46)

Shaun still saw missing buildings + ankle-height tan wall slabs on live v45.
201. **ROOT CAUSE A — PlotId == without tonumber** — `StructureKitBuilder.findPlotPad` compared `inst:GetAttribute("PlotId") == plotId` (no tonumber) while `findUpgradeSlots` correctly used tonumber. Stringy/mismatched PlotId → SyncPerimeterWalls printed skip and returned; Shaun only saw short DefensiveWalls **pad-sample** kit / MapDressing sandbags, NOT tall WE_PerimeterWalls. **Fix:** always `tonumber(GetAttribute("PlotId")) == tonumber(plotId)` in findPlotPad; tag PlotPad with WE_BasePlot if missing.
202. **ROOT CAUSE B — map heal race** — Bootstrap PlayerAdded could destroy/rebuild WarEmpireSetup AFTER BaseService RefreshAllVisuals → kits/walls wiped on new pads. **Fix:** `BaseService.RefreshAllOnlinePlayers()` + Bootstrap `afterMapRebuild` hook after every heal/rebuild path; rehydrate at 0 / 0.5 / 2 / 5s.
203. **Force perimeter** — KIT_GEN **31**; height `math.max(18, 10+lv*4)` (L5≥30); bright olive + neon top cap; always ClearAllChildren+rebuild level≥1; shortWall if Size.Y<18.
204. **Buildings always visible** — PreferMesh OFF; EnsureKit Body min 14×10×14 (non-flat); MissileDefense Body 18×12×18; Body/Roof Transparency=0 CanCollide Body; empty-slot PlotN StructureId scan; NuclearRehydrateKits iterates BaseConfig.Structures keys.
205. **WE_OwnedLevel** — sync from profile in UpdateVisuals; clear to 0 on ClearPlotExtras (unowned pads).
206. No new Design meshes. Visibility only.

## 2026-09-21 — Restore SyncPerimeterWalls from v36 / 0b0e95f (Open Cloud versionNumber=47)

Shaun: walls still missing / not tall — pull known-good walls from commit **0b0e95f** (Ship v36, last era walls went HIGH when fully bought), before PreferMesh/empty-base chaos.

**Restore (surgical):**
- Replaced `findPlotPad`, `FindPlotFolder`, `SyncPerimeterWalls` in `StructureKitBuilder.luau` with v36 bodies from `0b0e95f`.
- Surgical only: `tonumber(inst:GetAttribute("PlotId")) == tonumber(plotId)` in findPlotPad; always ClearAllChildren rebuild (no mustRebuild early-return); no BaseGate/DressGen gate dress; `KIT_GEN = 32` + `WE_PerimeterGen` stamp; height `7.5 + lv * 2.8` (L5 ≈ 21.5).
- BaseService still calls `SyncPerimeterWalls(plotId, tonumber(profile.BaseUpgrades.DefensiveWalls) or 0)` on RefreshAllVisuals / join — unchanged.
- PreferMeshWhenAssetIdSet stays false. Vehicle drive / monetization untouched.

## 2026-09-21 — Force wipe + walls on buy (live v48 — Open Cloud Published versionNumber=48)

Shaun: Open Cloud DataStore wipe returned 403. Need ALL progress deleted so he can buy everything fresh; walls must appear when DefensiveWalls is purchased.

207. **ForceWipeUserIds** — `AdminConfig.ForceWipeUserIds = { 470626172 }`. `DataService.LoadProfile` BEFORE GetAsync: if userId listed → pcall `RemoveAsync(player_USERID)`, skip raw load, `CreateDefault()`, warn `[DataService] FORCE WIPE applied for`. Still `applyAdminPlaytestCash` ($50M). Does **not** auto-max BaseUpgrades. Remove UserId from ForceWipeUserIds in a later publish after the one wipe+buy session (list membership wipes every join while present).
208. **wipeprofile admin** — `AdminService` command: `RemovePersistedProfile` + `ClearInMemoryProfile` (so PlayerRemoving cannot re-save) + SessionLock.Release + Kick `"Progress wiped — please rejoin"`. Listed in `AdminConfig.Commands`.
209. **Walls on BUY** — `BaseService.UpdateVisuals` DefensiveWalls → `SyncPerimeterWalls(plotId, wallsLv)` with loud print; level 0 clears stale short walls. v36 geometry (`height = 7.5 + lv * 2.8`), KIT_GEN 32, PreferMesh OFF unchanged.
210. BuyPathStatic PASS; Open Cloud Published **versionNumber=48**.

## 2026-09-21 — Force wipe done-key one-shot (live v49 — Open Cloud Published versionNumber=49)

211. **force_wipe_done one-shot** — Before wipe, `GetAsync(force_wipe_done_USERID)`; if truthy skip wipe (normal load). On wipe: RemoveAsync player key → CreateDefault → applyAdminPlaytestCash → `SetAsync(force_wipe_done_USERID, { unix, v=1 })`. ForceWipeUserIds stays allowlist. Admin `clearwipedone` RemoveAsync done key. Walls/PreferMesh unchanged. BuyPathStatic asserts force_wipe_done. Open Cloud **versionNumber=49**.



## 2026-09-21 — Cash desync / ATM collect / compact BUY (live v50)

212. **NEED with HUD $5k root causes** — (a) HUD hardcoded `$5,000` placeholder before sync looked like real Cash; (b) `WorldPromptController` never bootstrapped via `GetPlayerState`, so local `cash` stayed `0` after missed join `EconomyUpdate` → NEED / soft-fail toast while server Cash was fine; (c) AdminPlaytestCash needed tonumber + immediate Save after wipe. Fixes: WE_Cash/WE_Gold/WE_PendingCash attributes on pushEconomy; WorldPrompt+HUD+Base attribute listeners + GetPlayerState retry; AdminPlaytestCash log + deferred Save; join re-push economy at 0.5/2/5s; get_state rate 6/16.

213. **ATM collect** — `BasePlotId == nil` routed touch to AtmRaid (no-op) instead of Collect; CollectCircle not in body AABB. Fixes: own/unowned → Collect, raid only when another living owner; `nearCollector` 10-stud radius; `WE_CollectPrompt` ProximityPrompt; empty-pending toast.

214. **BUY / price UI too big** — ScreenGui BUY was 420×88 + MobileScale; MapSetup Cost label overflowed chip. v50: BUY 300×58, chips 118×40 / maxW 120, MapSetup labels fit.

## 2026-09-21 — P0 v51 admin playtest cash floor (shaunie6 $0 on join)

213. **AdminPlaytestCash every-join floor (not wipe-only)** — Root cause: `force_wipe_done_<userId>` one-shot can leave a persisted `$0` profile if an earlier wipe/save raced before AdminPlaytestCash stuck; Shaun then rejoined broke forever because top-up was assumed wipe-path-only. **Fix:** keep idempotent `Cash < AdminPlaytestCash → raise` on **every** `LoadProfile` for `AdminConfig.UserIds` (470626172); `tonumber` both sides of UserId match; pcall + re-assert after `OnProfileLoaded`; export `DataService.EnsureAdminPlaytestCash`; `EconomyService.Push` + BaseService join delays + `CharacterAdded` re-ensure then push so `WE_Cash` / `EconomyUpdate` / `GetPlayerState` never stick at 0 for admins. Does **not** auto-max BaseUpgrades. PreferMesh OFF / KIT_GEN 32 / walls-on-DefensiveWalls-buy / ATM collect unchanged.
214. **StartingCash = 10000** — Fresh non-admin joins get $10k (was $5k) so Command Center ($1500) + early pads stay buyable if schema/migrate ever yields a thin wallet. Admin floor remains `AdminPlaytestCash` 50_000_000.

## 2026-09-21 — P0 v53 admin cash still $0 for shaunie6 after v51/v52

215. **Root cause (evidence)** — Source+dist already had AdminPlaytestCash every-join floor (DataService.applyAdminPlaytestCash / EnsureAdminPlaytestCash; EconomyService.Push; BaseService join delays + CharacterAdded). Live v52 rbxlx contained those strings. Shaun UserId **470626172** is numeric in AdminConfig.UserIds. Persisted `$0` after `force_wipe_done` still reported on join ⇒ either (a) sticky pre-v51 server, or (b) allowlist/diagnostic gap (no always-on matched log; **no client/chat wiring** for `givecash` — RequestAdminCommand had zero FireServer callers). Not a Cash-vs-Money field rename; ProfileSchema field is `Cash`. Wipe order already wipe→CreateDefault→AdminPlaytestCash.
216. **v53 fix** — Hardcode `uid == 470626172` in DataService.isAdminUserId + AdminService.IsAdmin; always log `[AdminCash] userId=… before=… after=… matched=…` on LoadProfile; Ensure mirrors WE_Cash for admins; AdminService server `Player.Chatted` `/cash`|/givecash` (no arg) forces Cash=`AdminPlaytestCash` 50_000_000 + Push; StartingCash stays 10000; no BaseUpgrades auto-max; PreferMesh OFF / KIT_GEN 32. Open Cloud **versionNumber=53**.

## 2026-09-21 — P0 v54 universal StartingCash join floor (nobody joins at $0)

217. **Root cause** — Persisted Cash=0 after force_wipe: Migrate/GetAsync keeps Cash=0; CreateDefault StartingCash only on *new* profiles. AdminPlaytestCash alone left shaunie6 broke in live (race / Push miss / HUD stuck). Product rule: nobody should join at $0. `/cash` via Player.Chatted is unreliable under TextChatService — not a product fix.
218. **v54 fix** — `applyStartingCashFloor` / `EnsureStartingCashFloor`: after Migrate/CreateDefault, if Cash < StartingCash → set Cash=StartingCash, dirty, log `[StartCash] userId=… 0 → start`. Then AdminPlaytestCash 50M for admins (hardcode 470626172). StartingCash **25000**. Economy Push always WE_Cash + EconomyUpdate for every player; CharacterAdded + 0.5/2/5s re-push. TextChatCommand + MessageReceived `/cash`|/givecash` backup (keep Chatted). `WE_Build=54`. PreferMesh OFF / KIT_GEN 32 / walls-on-buy / no BaseUpgrades auto-max. Open Cloud **versionNumber=54**.

## 2026-09-21 — v55 RESTORE cash + kits (stop flooring)

219. **Stop layering floors** — v48–v54 ForceWipe / force_wipe_done / EnsureStartingCashFloor / EnsureAdminPlaytestCash left shaunie6 at $0 on live. **Restore**: simple DataService LoadProfile (CreateDefault Cash=`StartingCash`); EconomyService.Push = pushEconomy only; AdminPlaytestCash = `if userId==470626172 then Cash=max(Cash,50e6)` on LoadProfile only.
220. **DataStore key bump** — `Constants.DataStoreName = "WarEmpire_PlayerData_v2"` (was `_v1`). Intentional: fresh join → CreateDefault with StartingCash=10000; kills stuck $0 v1 saves. Session lock store unchanged.
221. **Walls/buildings** — PreferMesh OFF; KIT_GEN 32; SyncPerimeterWalls from v36 (`0b0e95f`, height `7.5+lv*2.8`); walls on DefensiveWalls buy; EnsureKit on buy/join. Jeep drivability + map densify kept.
222. **WE_Build=55** — Open Cloud publish after rojo build + BuyPathStatic PASS.

## 2026-09-21 — Own the cash v60 (Open Cloud Published versionNumber=60)

Root cause v59 still `$…`: `HUDController.luau` / `WorldPromptController.luau` / `NotificationController.luau` called blocking `Remotes.GetEvent` (unbounded WaitForChild on Rojo empty `Remotes` folder) **before** leaderstats/attr wiring. UIController also inited Notification before HUD. Nuclear fix: `WE_Remotes` server-only, EarlyRemotes seeds leaderstats+AdminPlaytestCash sync, BindEvent for HUD, 0.5s fallback.



## 216. v61 Command Center BUY after v60 cash fix (2026-09-21)

**Symptom:** HUD showed $50M (v60 leaderstats OK) but BUY spam showed optimistic "Buying Command Center…" with no cash deduct / no spawn.

**Root cause:** WorldPrompt `onBuyPressed` toasted before `Remotes.GetEvent(...):FireServer` — GetEvent still unbounded-waits on WE_Remotes (same class of hang v60 fixed for HUD). Plus UpgradePad silent NoProfile if spatial fired before DataService.Init; Bootstrap had DataService after UpgradePad.

**Fix:** `Remotes.FireServer` (TryGet ≤3s); toast only after fire; EnsureProfile on pad + PurchaseUpgrade; DataService before UpgradePad; WE_Build=61.

## 2026-09-21 — v62 Command Center BUY cash desync + purchase remote hook (Open Cloud Published versionNumber=62)

**Root cause (v61 toast showed, cash stayed $50M):**
1. `EarlyRemotes.server.luau` seeded `leaderstats.Cash` + `WE_Cash` = AdminPlaytestCash ($50M) for HUD **before** DataService profile was authoritative.
2. `EconomyService.SpendCash` (file:line) only read `profile.Cash` — if still `StartingCash` (10000) or desynced, returned `InsufficientCash`.
3. Client `WorldPromptController.tryPurchase` showed "Buying Command Center…" **after** `Remotes.FireServer` returned true (remote existed) — independent of server success. Server `Notification` fail toast could miss if BindEvent lagged → endless Buying spam, cash unchanged, no CC.

**Fix (WE_Build=62):**
- `EconomyService.ReconcileSpendableCash` lifts `profile.Cash` to max(profile, WE_Cash, leaderstats) before spend (server-authored only).
- `RemoteSetup.ensurePurchaseHook` wires `OnServerEvent` on `WE_Remotes.RequestPurchaseUpgrade` at create-time; `BaseService` registers via `SetPurchaseUpgradeHandler` (same instance client fires).
- New `PurchaseResult` remote — server always FireClient Ok/Err; client clears pending + shows reason (5s timeout).
- `NoPlot` gate with clear toast; `UpgradePadService` server `WE_ServerBuyPrompt` ProximityPrompt backup.
- BuyPathStatic: remote name equality + simulate reconcile+SpendCash CommandCenter 10k→50M→49998500. Open Cloud **versionNumber=62**.

## 2026-09-21 — v63 BUY timeout nuclear fix (Open Cloud Published versionNumber=63)

**Symptom (v62 live):** Client toast `Buy timed out — try again (or use E on pad)` ×3; cash stuck $50,000,000; Command Center not bought. Goal still "Claim base + BUY Command Center". Place `97112936860418`.

**Root cause:** `BaseService.luau` buy handler `DataService.WaitForProfile(player, 5)` (was ~line 997) yielded up to 5s before `firePurchaseResult`. Client `WorldPromptController` timed out at exactly 5s waiting for `PurchaseResult` — so ack never arrived even when remote FireServer returned true. Secondary risks: `_purchaseHooked` sticky on destroyed RemoteEvent; `EnsureProfile` WaitForProfile(20); AssignPlot/NoPlot without live force plot 1; UpgradePad zero-tag miss; PurchaseResult-only client ack.

**Fix (WE_Build=63):**
- Buy handler: pcall + `WaitForProfile≤0.25s` + instant `EnsureProfile`; **always** set `WE_BuyAck/Ok/Err/Structure/Cash` + FireClient `PurchaseResult` in finally.
- Client: `GetAttributeChangedSignal("WE_BuyAck")` primary ack; PurchaseResult secondary; timeout only if attribute never advances.
- `AssignPlot` / `PurchaseUpgrade` / UpgradePad: force `BasePlotId=1` on live (not Studio-only); shaunie6 (`470626172`) cash floor 50M every buy.
- RemoteSetup: re-hook if RequestPurchaseUpgrade instance destroyed/replaced.
- UpgradePad: Workspace StructureId sweep if attached==0; standing auto-buy every ~1s; AckBuyResult path.
- BuyPathStatic: attribute-ack + CommandCenter 50M→49998500. Open Cloud **versionNumber=63**.

## 2026-09-22 — v64 Command Center BUY ServerError harden (Open Cloud Published versionNumber=64)

**Symptom (v63 live):** Shaun toast `Buy failed — server error, try again` / attr `Buy failed: ServerError`; cash stuck exactly $50,000,000; goal still Claim base + BUY Command Center; E ProximityPrompt visible. Place `97112936860418`.

**Root (pre-spend / SpendCash throw → pcall maps ServerError, cash unchanged):**
Likeliest sites before deduct: `profile.BaseUpgrades[structureId]` or `meetsRequirements` when `BaseUpgrades` nil; `if EconomyService.ReconcileSpendableCash` / `RateLimitService.Allow` when service nil; or SpendCash throw before deduct. Post-spend `Stats.UpgradesPurchased += 1` / PushState / UpdateVisuals throws would leave cash down — Shaun still at 50M ⇒ prefer pre-spend. Exact live err string was masked as `ServerError`.

**Fix (WE_Build=64):**
- PurchaseUpgrade: ensure BaseUpgrades + Stats tables; pcall AssignPlot; force BasePlotId=1; nil-safe RateLimit/EconomyService; pcall SpendCash; set level + MarkDirty; **return Ok**; THEN pcall analytics/missions/PushState/UpdateVisuals/bindable (never fail buy after spend).
- SpendCash: outer pcall → false,"SpendFailed" on throw; Reconcile also pcall'd.
- handlePurchaseRemote: stamp `WE_BuyErr` = truncated real `tostring(errCall)` (re-stamp after ack so not overwritten by "ServerError").
- UpgradePad: ensure BaseUpgrades/Stats; pcall PurchaseUpgrade; stamp WE_BuyErr on throw.
- ProfileSchema.Migrate: always ensure BaseUpgrades + Stats.
- BuyPathStatic: simulate Stats=nil / BasePlotId=nil / Reconcile → 50M→49998500 PASS. Open Cloud **versionNumber=64**.

## 2026-09-22 — v65 DataService nil GetProfile fix (Open Cloud Published versionNumber=65)

**Symptom (v64 live):** Shaun screenshot `Buy failed: ServerScriptService.Server.Services.BaseService:655: attempt to index nil with 'GetProfile'`; toast `Buy failed — server error, try again`; cash stuck $50,000,000; goal still Claim base + BUY Command Center. Place `97112936860418`.

**Root cause:** module-local `DataService` inside BaseService was **nil** when PurchaseUpgrade ran `DataService.GetProfile(player)`. Bootstrap inited BaseService/Economy before DataService.Init; deps.DataService could be missing if safeRequire failed.

**Fix (WE_Build=65):**
1. Bootstrap: `DataService.Init()` FIRST (before Economy/Base/UpgradePad); assert `deps.DataService ~= nil`; warn if safeRequire failed.
2. BaseService: `getDataService()` with `require(script.Parent.DataService)` fallback; PurchaseUpgrade returns `NoDataService` if still nil; Init asserts deps.DataService + EconomyService.
3. EconomyService + UpgradePadService: same getDataService guard (SpendCash never throws index-nil GetProfile).
4. Keep v64 hardenings (BaseUpgrades/Stats, Reconcile, attr ack, real WE_BuyErr).
5. BuyPathStatic: nil→require fallback simulate CommandCenter 50M→49998500 PASS. Open Cloud **versionNumber=65**.


## 2026-09-24 — v66 real root cause + walk-in Command Center

**Root cause of v50–v65 buy failures (supersedes the v65 note above):** `ProfileSchema.luau` (since v50) and `EconomyService.luau` (since v22) did not *parse* — a line starting with `(` right after a call is a Luau "ambiguous syntax" error. `DataService` requires ProfileSchema at top level, so it never loaded; the v65 `assert(deps.DataService)` then aborted the whole server Bootstrap. `PremiumPadService` (v29) and `TerritoryService` (v38) also failed to parse. Fixed in v66; Bootstrap now warns instead of asserting. `tools/BuyPathStatic.py` gained a real parse gate (`luau-compile` over every `.luau`) because its text checks all passed on the broken tree. Shaun confirmed cash/BUY works after the fix.

**Walk-in buildings (`Modules/HollowBuildingBuilder`, config `StructureVisualConfig.HollowBuildings`):**
1. Command Center is a real building (doorway, glass windows, lit interior) instead of a solid box. L2 comms annex + mast + floodlights; L3 second storey + interior stairs; L4 roof ladder (TrussPart) through a hatch + dish; L5 helipad marking, gold trim, taller flag.
2. The building stands **behind** its pad and the doorway is shifted sideways (nearest door edge 10.2 studs from pad centre vs the 8-stud walk-over hit box), so going inside never buys the next level.
3. The kit `Body` is now just the foundation slab, so existing invariants (Body exists, solid at L1+) hold; `applyKitVisuals` skips Body rescale and level-up "pops" for walk-in kits; the Model is rebuilt only when the level changes; plot release removes it.
4. Walls/floors keep `CanQuery = true` so weapon raycasts and camera occlusion treat the building as solid.
5. Other structures keep their Part kits until they get a `HollowBuildings` entry.
6. `KIT_GEN` 32 → 33 so stale kits rebuild; BuyPathStatic checks KIT_GEN ≥ 32 instead of the exact text.

## 2026-09-24 — v67 base look (military palette, no neon floors, no dark ceiling, quieter labels)

Measured by running the real MapSetup + BaseService + wall/ceiling code headless and rendering plot 1 at L5.
1. **Palette:** all structure palettes are one scheme (sand concrete / olive / dark metal) with a muted per-type Accent used only on small details. The v45 "bright olive / lime neon cap" walls were a visibility workaround from when services were not loading.
2. **Foundations:** the kit `Accent` footprint plate is concrete (`StructureVisualConfig.FoundationColor`) at 1x size. It was a Neon plate in the accent colour scaled to 1.4x the footprint at L5 — the purple (Special Forces), green, blue and red glowing floors.
3. **Walls:** concrete with a concrete cap and a razor-wire line; gate stripe is painted hazard yellow; gate sign range 50.
4. **Anti-heli ceiling:** kept as gameplay (helicopters collide) but it is an invisible plate at `AntiAirCeilingHeight` (48) above the plot floor with `CanQuery = false`. The visible translucent slab, trims, posts, beams and rooftop pads are gone (dark "warehouse" look, and the roof cut through two-storey buildings).
5. **Plot floor:** light concrete with a painted olive kerb and yellow chevrons (`StructureVisualConfig.BaseLook`); the "BASE n · Walk pads to BUY" label is removed.
6. **World labels in bases:** `Modules/WorldLabelPolicy` + `Configs/WorldLabelConfig` turn AlwaysOnTop off and cap MaxDistance at 45 for every BillboardGui anchored inside a plot (labels outside plots untouched). Label sizes/layouts are not changed. ATM card title is "ATM · WALK IN TO COLLECT"; Training Yard label shortened.
7. Robux offer pads and the ATM collect ring keep their bright colours on purpose (purchase / collect affordances).

## 2026-09-24 — v67 save integrity (DataService ran live for the first time in v66)

Found by the buy-path audit (5 of 6 auditors independently) and confirmed by reading the code:
the v58–v65 "instant profile" handed out a default, merged ~15 saved fields into it later and saved the
result, so every rejoin dropped entitlements/receipts/codes/battle pass/clan/daily/spinner/territories,
leaving before the read finished (or a failed GetAsync, or autosave first) wrote the default over the save,
and cash was lifted to StartingCash on every join.
1. `DataService.LoadProfile` reads the save first; `GetProfile` is nil until then (callers already treat nil as "still loading"). No partial merge.
2. `loaded[userId]` marks a profile as read from the store (or a confirmed new player). `SaveProfile`, autosave, leave and `BindToClose` only ever write loaded profiles.
3. GetAsync failure → the player can keep playing on a session-only profile that is never saved, with an on-screen warning.
4. `EnsureProfile` never invents a profile; it waits briefly for, or starts, the real load.
5. Leave clears the in-memory profile before its save; a same-server rejoin waits for that save before reading.
6. No StartingCash floor on join (new players still start with StartingCash). Admin playtest cash for 470626172 unchanged.
7. `EconomyService.ReconcileSpendableCash` no longer raises profile cash to HUD display values (it re-syncs the display to the profile).
8. `MonetizationService.ProcessReceipt` returns NotProcessedYet until the profile is loaded, and saves the grant before PurchaseGranted.
9. Pad BUY and B-menu BUY were wired to both Activated and MouseButton1Click (two purchases per click); now Activated only + 0.35 s tap debounce, and the server drops an identical request inside 0.3 s.
Verified with a behavioural harness (simulated clock + fake DataStore) running the real DataService/MonetizationService: 24/24 scenarios pass.

## 2026-09-24 — v68 bigger open base: walk-in buildings, consoles, guarded rear gates

Owner asked for: every building a real walk-in building with clickables inside, the airstrip etc. outside behind purchasable guarded gates, a bigger plot, and no roof.
1. **Layout is config:** `Configs/BaseLayoutConfig` (one place for sites, yaw, consoles, kiosks, roads, inner wall, gates); `Modules/BaseLayout` turns it into world CFrames. `Enabled = false` restores the old grid of pads.
2. **Plot 200 → 320.** Plot centres are unchanged (800 ring). Whole-map scan in the headless sim: nothing outside a plot intrudes into one. Spawn pads now slide along their ring to stay 40 studs outside plots (`PLOT_SPAWN_CLEARANCE`) — this also fixes NPCSpawns4, which sat inside plot 4 even at 200. `BaseConfig.PlotSize` follows the layout, and the oil pumps step out along diagonals far enough to clear the square plot (at 320 they would have landed inside the Warehouse).
3. **No roof:** the invisible anti-helicopter ceiling is off (`StructureVisualConfig.AntiAirCeilingEnabled = false`), so helicopters can fly over bases. Set it back to true to restore the v67 barrier.
4. **Main compound (front):** Command Center at the head of a parade ground; Barracks / Armory / Special Forces on the west row and Vehicle Depot / Warehouse / Research Lab on the east row, all walk-in buildings facing the central road. Power Station, Radar and Missile Defense stand in the rear of the compound; Walls and Watchtowers keep their perimeter behaviour (`SyncPerimeterWalls` unchanged).
5. **Rear zone:** an inner wall at Z = -60 with one gate each for Airfield (runway + hangar), Helipad and Dock (water basin). "Purchasable guarded gates" is implemented as: each gate is locked and guarded until the structure behind it is bought (L1+), then slides open (`StructureKitBuilder.SyncRearGates`). Its kiosk stands in front of the gate so it can be bought from the compound. Guards are decoration, not combat NPCs.
6. **Consoles, not pads:** every structure is bought/upgraded at a console — inside the building by the door for walk-ins, a kiosk for outdoor installations. Prompt (hold 0.35 s) or the BUY chip only; walking over a console never buys (server Touched + spatial loop and the client walk-over path all skip `WE_Console` parts).
7. **Interiors:** `HollowBuildingBuilder` builds the shell for the 7 walk-in structures; each has an interior module `Modules/Interiors/<Name>.luau` (`function(ictx, api)`). Item terminals carry `WE_OpenPanel` on their ProximityPrompt and the client (`UIController`) opens the matching existing panel: Base, Shop, Rebirth, Missions, Army, Garage, Settings. No new UI was added — the Armory's weapons counter opens the Shop because there is no separate weapons panel yet.
8. Interiors are verified by a headless checker (walls/windows/lights not clipped, doorway/console/stairs clear, every terminal reachable on foot from the door, allowed panels only, ≥ 2 terminals per building) at every level 1–5.
9. **Outdoor installations** (`StructureVisualConfig.Installations` + `Modules/Installations/*.luau`): Power Station (fenced substation yard, generator hall, transformers, pylon, solar), Radar (control hut, lattice tower, dish that spins client-side, radome at L5), Missile Defense (sandbag berm, canister launchers, fire-control truck), Watchtower (braced timber tower with ladder, sandbagged deck, searchlight), gate Checkpoint for Defensive Walls (booth, raised boom, jersey barriers, razor wire, tank traps), and the Airfield hangar (walk-in hangar with jets, a Garage terminal, control tower, fuel truck) behind the runway on a new apron road. They replace the plain box kits and grow with level. The runway itself is layout ground, so the old kit runway strip is gone. The Helipad and Dock keep their existing kits.
10. **Kiosk fix:** the Walls and Watchtowers kiosks sat inside their own kits (a 26-tall wall sample and a 45-tall tower), so the prompt and BUY chip could not be reached. They now stand 12 studs in front. A world-sim check confirms that all 90 consoles on 6 plots are clear and have room to stand.
11. **Corner towers** (Watchtowers level, `SyncCornerTowers`) are guard towers — concrete shaft, glazed cabin, roof, outward searchlight, red beacon — instead of solid 7–10 stud pillars. Part names and `WE_CornerTower` / `WE_TowerShooter` attributes are unchanged.
12. `WE_Build` = 68; `KIT_GEN` 34 so kits built by older code rebuild.

## 2026-09-24 — v68 audit batch 2 + owner feedback (lights, lines, labels, auto-collect)

1. **No plot hijack:** a 7th+ player on a 6-plot server gets no plot (`WE_NoPlot` attribute, "NoPlot" reply) instead of being forced onto plot 1, where their refresh redrew and their leave wiped the real owner's base (BaseService, UpgradePadService, PremiumPadService). A buy with no plot yet still claims a free one on the spot. The place's Max Players should be set to 6 in Studio Game Settings (not code).
2. **Anti-exploit:** fast taps on Recruit/Dismiss/Spin/Rebirth no longer earn strikes (they get a throttled "slow down" toast); strikes decay one per 30 s; camera-origin/ray-length shot mismatches are logged, not counted. 10 real strikes still kick.
3. **Economy:** prestige multiplier never applies to refunds, dev products, admin grants, collector, ATM raid, dropper. The unused RequestStartMission remote is disabled by config and each timed mission pays once per UTC day. Manual dropper income is capped by per-player minute/hour budgets (auto-clickers earned ~$216k/h).
4. **Join:** gate guards, AutoGuns and oil pumps spawn when the owner's plot is built from the loaded save (plot-ready hook), not on fixed timers; TutorialService is never called before Init; L5 BUY replies without waiting on InsertService; the tutorial CC/Barracks step no longer asks for an extra level.
5. **Weapons:** the Shop has a WEAPONS tab (buy/equip via the existing server-validated remotes); weapon cycling skips unowned weapons; one-time dev products show OWNED; the unimplemented Elite Base Theme pass is not sold in the Shop; the locked Supply Crate row shows LOCKED.
6. **Owner feedback:** building lights run through `StructureVisualConfig.BuildingLights` (35 % brightness, 16-stud range, non-neon fittings); the always-on neon guide beams across the base are removed (the tutorial shows one thin guide to the current step); field units have no "SQUAD" tag (`OrdersConfig.ShowUnitLabels`); AutoCollect collects silently.

## 2026-09-24 — v69 batch-2 leftovers (saves, receipts, passes, clans)

1. **Session lock:** Release/ForceRelease really free the lock (they wrote nothing before); a joining server waits up to 12 s for the previous server's final save before loading; a server that gave up waiting re-takes a free/stale lock on its next refresh. Still advisory (warn, never kick), as before.
2. **Receipts:** the "already processed" session cache is set only after a successful save, so a failed save is retried instead of being acknowledged; receipts wait up to 25 s for the profile (the load can wait on the lock). Battle Pass Premium receipts wait for BattlePassService and return NotProcessedYet rather than throwing.
3. **Game passes:** ownership refreshes merge (a failed check never turns an owned pass off) and retry; a pass bought mid-session is granted only after `UserOwnsGamePassAsync` confirms it (the purchase-finished event can be spoofed by exploiters). Owned passes/one-time entitlements are mirrored as `WE_Ent_<key>` attributes for the Shop's OWNED state.
4. **Instant Barracks** refreshes the base like a cash purchase. **Premium pads** on another player's (or an unowned) plot do nothing.
5. **Clans:** ids are random (`clan_` + 12 hex) and created write-once; a clan war needs a defender online and a 0–0 war pays nothing. Known limit: roster edits still overwrite the whole clan record, so simultaneous edits from two servers can race.

## 2026-09-24 — v69 base raids + Command Center missile strikes

Owner: "steal 10% of whatever they have in their atm … cool down period of 10 mins" and "from command centre … direct missiles at players/bases when you have the upgrade to take down their defenses". Numbers live in `Configs/RaidConfig.luau`.
1. **Raid = a 6-second hold at the victim's ATM, inside their base**, on foot, alive and not taking damage (server-side; no raid remote). Steal = floor(10 %) of the ATM balance into the thief's ATM (no multipliers). Victim then has a **10-minute shield** (`profile.Raid.ShieldUntil`, survives rejoin/server hop); thief waits 60 s. No raiding your own base, clan-mates, unloaded saves, players in their first 10 minutes, or ATMs under $100. AutoCollect owners are raidable on their last 10 min of auto-collected income, capped at the cash they still hold.
2. **Defenses really defend now:** gate guards and AutoGuns stand inside the walls and see the ATM (they could not before), guards can be shot and respawn one at a time, the gate barrier opens for the owner and clan-mates (it used to lock the owner out), allies = owner + same clan (was a random nation colour).
3. **Missile strikes:** unlocked at Command Center L3 + Missile Defense L1; launched from the new "Missile Command" terminal in the Command Center (you must be at your CC); $5,000; 10-minute cooldown (5 if intercepted). The target's Missile Defense level gives 15–55 % interception. A hit takes the target's guards, AutoGuns and gate barrier down for 120 s (+30 s per attacker CC level above 3), then they reboot with 5 minutes of strike immunity. No strikes on shielded, down, rebooting or undefended bases. **Missiles never damage players.** Refund if the target leaves.
4. Client: Missiles panel (targets, walls/turrets/intercept, shield timers, STRIKE→CONFIRM), missile arcs + explosion for everyone, siren + red edge + "INCOMING MISSILE" for the victim; raid progress/alarm chip (ShopController) until the HUD redesign moves it to the top-centre stack.

## 2026-09-24 — v69 Research Lab upgrades

Owner: "Inside the research department you should be able to upgrade soldiers, guns, weapons etc." Tree in `Configs/ResearchConfig.luau`, server `ResearchService` (`GetBonus(player, statId)` contract), panel `ResearchController` (opened from Research Lab terminals, one per track from Lab L3).
1. **4 tracks, 10 upgrades, instant Cash purchases:** Weapons (damage +4 %/lvl, fire rate +3 %, magazine +8 %, reload speed +6 %), Soldiers (squad health +10 %, squad damage +10 %, +1 field unit ×3), Vehicles (speed +4 %, armor +8 %), Defenses (gate guard + AutoGun damage +8 %). Level L needs Research Lab ≥ L (Squad Expansion 2/4/5); Soldiers/Vehicles/Defenses also need Barracks / Vehicle Depot / Defensive Walls L1. Full tree ≈ $4.05M.
2. **Research is permanent** — Rebirth does not reset it (buying new levels needs the Lab again).
3. **Fairness caps:** research never turns a non-lethal shot into a one-shot (capped at 99); weapon swapping can no longer skip a slow gun's cooldown; the Buy button stays busy until the server answers (no double-charge on lag).
4. **Engine Tuning and Composite Armor show "SOON"** until the vehicles work lands (Engine Tuning needs the vehicle speed hook; Composite Armor needs a vehicle damage system) — we never sell an upgrade that does nothing.
5. Research Lab interior (benches, server racks, prototype stand, clean room, offices upstairs) and Warehouse interior (quartermaster → Shop Supply tab, logistics → Missions, racking, forklift).

## 2026-09-24 — v70 drivable cars, helicopters, planes and boats
- **Who simulates.** The driver's client runs the vehicle physics (`Client/Modules/VehicleDriveClient.luau`) by writing to two server-made movers (`WE_DriveLV`, `WE_DriveAO`). The server checks it 5 times a second: speed cap (plus a 1 s window, so small per-sample slack can't add up), altitude cap, teleports, map bounds, and boats must be over `WE_Water`. On a violation it takes ownership back, snaps the vehicle to its last valid spot for 1.5 s and hands it back; 3 violations in 60 s recalls the vehicle. Assumption: server-side physics would add 100–250 ms of input lag on phones, and the client already owned vehicle physics before v70, so this keeps security the same or better.
- **Fallback.** If the client module never says Hello within 2.5 s, the server drives **cars and boats** itself from the seat's throttle/steer. Aircraft have no fallback (they need lift/pitch input); the pilot gets a "rejoin" notice.
- **Cars can turn.** Wheel friction is now 0.2 (`VehicleConfig.Drive.Modes.Car.WheelFriction`); grip comes from the drive law. The old friction 2.0 was stronger than the steering force.
- **Exiting.** F exits helicopters and planes on PC (Space is climb). A dead driver's held throttle is ignored.
- **Boats** spawn only at naval pads over water; they never fall back to land pads. They will scrape the shallow sea floor (surface is 0.2 studs above the ground) until the waterways pass deepens the water.
- **Helicopters** spawn facing the base (heading π). If the deck spot is taken they use (+8, +8), then the apron, before a distant pad.
- **Garage.** Locked rows say why ("Lv 10", "Depot L2", "Rebirth") instead of showing BUY; rows update in place during the 15 s cooldown instead of being rebuilt every second.
- **Map props.** The plot-ring "densify" props (sandbags, crates, bunkers at radius 55–91 from each plot centre) were placed for the old 200-stud plots and now landed inside the 320 base, including on runways (one of 168 simulated take-offs hit a sandbag). They are skipped inside the base footprint + 12 studs; the waterways pass can re-home them outside.
- **Needs an on-device check (the headless sim can't prove these):** client-written mover values move the vehicle; `SetNetworkOwner(nil)` works with a seated character; binding Space stops the seat jump on PC; the camera follows aircraft well enough.
- **Engine Tuning research is on.** `ResearchConfig.Upgrades.EngineTuning.Enabled = true`: +4% top speed per level (max +20%, clamped by `Drive.MaxResearchSpeedBonus`), applied at spawn and to a vehicle that is already out. Composite Armor stays off until vehicles have a health pool (planned with the premium vehicles build).

## 2026-09-24 — v71 money phase 0 (leak fixes, plumbing, receipt safety)
- **Owner defaults applied (money plan §2.7; the owner can overrule any):** Starter Pack v2 149 R$ ($50k + Auto Collect), Army Expansion +10 for 99 R$ (retroactive), premium prices 199/399/799 + bundle 1,099, free drivers keep firing their rifle, gunner seats for owner + clan-mates, a nuke on a base gives a 5-min fallout shield and never opens it for raiding, at most 3 offer pop-ups per session ≥ 4 min apart. Only the config/plumbing for these shipped here; nothing new is sold yet.
- **Stopped selling dead items:** Gold S/M/L and Instant Barracks are hidden in the Shop (`HideFromShop = true`, live Ids kept, receipts still grant). Gold has no use in the game yet. The PvP death toast no longer offers 2x Cash (`DeathShopOffers = {}`).
- **Receipt safety (J2):** a receipt for a product Id this server does not know is **not** acknowledged (Roblox retries it) instead of taking the Robux and granting nothing. A per-receipt lock stops the same PurchaseId being processed twice at once on one server. After every publish that pastes new Ids, run **Migrate to Latest Update**.
- **Plumbing only:** 16 new remotes (none has a server handler yet, so none can grant anything), profile fields for nukes/silo/premium camo/trials/rebirth/offers/purchase stats (default-filled and sanitised on load, kept through Rebirth, no DataVersion bump), 30 analytics events, admin money commands (allowlist anywhere, anyone only in Studio; cash commands stay allowlist-only; AdminPlaytestCash untouched), and five new configs (Nuke, Rebirth, VehicleCombat, VehicleWeapon, PremiumVehicle) with every product Id 0.
- **Wire tool** (`tools/wire-monetization-ids.py`) now refuses unknown keys, overwriting a live Id without `--force`, and an Id another product already uses.
- **Bootstrap** registration of the future services (NukeService etc.) waits until the waterways build lands (it is editing Bootstrap).

## 2026-09-24 — Mobile first (owner direction)
- The owner: "Everything needs to be geared towards mobile big time as that's where 80% of players play." This is now rule 1 in `CLAUDE.md`, which every agent working in the repo reads. It sets the target screens, touch rules (every action has a touch control, ≥ 44 px targets, thumb zones), readability, performance budgets, StreamingEnabled safety and phone verification. Any feature that only works well on PC counts as unfinished.

## 2026-09-24 — v70 waterways live: water ring, bases face the centre, sea gates, naval outposts
- **Bases now face the map centre** (`BaseLayoutConfig.FaceMapCentre = true`). Every base keeps its exact layout; the whole plot turns (P1/P2 yaw 90, P3 0, P4 180, P5/P6 −90), so the Dock, Airfield and Helipad sit at the back facing the water. This is the only layout where all 6 docks reach open water with no road crossings. **Rollback:** set it to false; the map-gen stamp (`MapSetup.MAP_GEN` 71 when turned, 70 when not) makes Bootstrap rebuild a stale saved map either way.
- **Water:** 36 `WE_Water` parts form a ring canal at x = ±1800 and z = −1800 joined to the southern sea, with one water level (top y 1.5). Each Dock has a harbour basin and a 40-wide channel out of the rear wall. The oil rigs sit in lagoons on the ring. Roads stop 8 studs short of the water at jersey barriers, with 3 new boat landings.
- **No void:** the 7200-wide Ground, roads, berms and safety plates are split into tiles under Roblox's 2048-stud part limit (done unconditionally; G0 was never run). No part in the world is over 2048 now.
- **Sea gate:** buying the Dock arms a sea gate in the rear wall. It opens only while a boat driven by the owner or a clan-mate is within **40 studs** (`WaterConfig.SeaGate.OpenRadius`, the design's 60 was lowered so a boat idling at the basin spawn (46.5 studs) does not hold it open for enemies on foot), and closes 2 s after. Driverless boats, people on foot, enemies and jeeps never open it. One guard per gate.
- **Capture:** the two coastal oil rigs are naval outposts (a boat driver in range or a player on the deck). **Only the driver of any vehicle counts** toward capturing or contesting; passengers no longer do (`TerritoryConfig.VehiclePassengersCount = false`).
- **Boats:** spawn in their own basin facing the gate. A basin or gate channel counts as water only for its owner's boats. The boat land probe starts at +6 so the rig decks don't block the canal.
- **Missile strikes, heli/plane/car spawns** now use plot-local coordinates through the plot frame, so they work on turned bases.
- **Known limits:** gate leaves jump open instead of sliding; clan-mates' boats open the gate but are pulled back out of the basin by the owner-only water rule; naval pads no longer carry `WE_VehicleSpawn` (so there is no "Open Garage" prompt at them; the rail Garage and G still work). Needs the owner's phone: gate feel, boat handling, frame rate with +235 parts.

## 2026-09-24 — v70 HUD "clean screen" (phone first)
- **Layout:** left icon rail (replaces the 7-tile bottom-right bar that sat under the jump button), a TopStrip in the Roblox top bar (level chip, Settings gear, shield chip, compass), a cash pill with +/− cash floats, one top-centre stack (missile alert, capture/raid progress, objective chip, toasts). Removed from the screen: season banner, BASE UPGRADES button, spin, passive/gold/pending lines, always-open Orders panel (now an Army popover, key Y, never auto-shown), dock labels.
- **Owner decisions applied:** Settings is a gear in the TopStrip; there is **no Base tile** (the owner does not want base buying on the home screen; the overview stays reachable from the Command Center map table); players **spawn holstered** and auto-draw when damaged (`HudConfig.Hotbar.DrawnOnSpawn`); Army hotkey Y.
- **Toasts:** at most 2 visible, de-duplicated, collect messages become cash floats, per-hit "DEF HIT" becomes one "BASE UNDER ATTACK" per 60 s. The server still sends the old messages until the world/server agent (F) lands; the client reroutes them (`HudConfig.Toast.Reroute`/`Drop`).
- **Offers:** the 7 upsell cards are now one offer toast: at most 3 per session, ≥ 240 s apart, first ≥ 90 s after join, never during combat, driving, panels, tutorial or death.
- **Combat HUD:** FIRE/RELOAD only while drawn and inside the bottom-right reserve; hidden while driving so the vehicle controls own it; reticle at the true screen centre (bullets now land on the crosshair).
- **Prompts:** custom pill style set on the client; if PromptController fails, every prompt falls back to Roblox's Default style.
- **Robustness:** every client controller now loads and starts inside its own pcall (`Bootstrap.client`), so a combat failure can no longer take the garage/driving down.
- **Still to do (mobile plan merge gate + agent F):** 14 px minimum text (today 11), bigger Skip/close hits, held prompt pills released on TouchEnded, no holster on re-tap for touch, cash "+" out of the thumbstick zone, no KEYBOARD section/WASD copy on phones, world labels/neon clean-up and server message routing.

## 2026-09-24 — v70 server fairness (mobile plan P0-7, P0-6, P1-2, P1-4)
- **No trusted client targets:** a shot that names a target (`TargetUserId`/`TargetNpcId`) only damages it if the target is alive, in front of the ray, in range, within `CombatFairnessConfig.MissTolerance` sideways of the ray, and a server ray reaches its torso first (walls, terrain, vehicles and other players block). NaN/inf directions and origins are refused. This closes the "hit anyone within range through walls" exploit.
- **MissTolerance = 5 studs (not the plan's 4):** measured with 12 realistic aim points, a phone on ~250 ms cellular lag lands 10/12 on a walking target at 60–100 studs with 5 studs vs 4/12 with 4. Line of sight is still required. Proper lag compensation (position history) comes with the Combat Core wave.
- **New thieves:** you cannot start an ATM raid until you have finished or skipped the tutorial and are past your first 10 minutes (mirrors the victim protection). Refusal text names no keys.
- **NPCs:** shots need line of sight; hit chance 75 % at ≤ 20 studs falling to 30 % at max range, −15 % vs targets faster than 10 studs/s; 0.5 s reaction delay. Five bank guards drop from 200 to 130 dps. **The bank is still unwinnable** (guards respawn in 18 s); it needs a separate bank retune.
- **Squad:** FOLLOW is now an escort (engages hostiles within 55 studs of you, never more than 20 studs away). Escort kills pay you 50 % cash + XP ("Squad: X down"). ATTACK-order kills pay nothing (`UnitKillCreditOnAttack = false`) because an idle owner could farm $9k/10 min from the bank.

## 2026-09-24 — v70 jeep drive fix (live: "the jeep doesn't drive")
- **Root cause could not be pinned to one layer** (network ownership, something pinning the car, or phone input — none modelled by the headless stand-in), but v70 turned any one failure into a permanent, silent parking brake. The fix removes every known hazard and adds a server-verified failover:
  - ownership is set and checked on the chassis **and every wheel**; wheels get NoCollisionConstraints to their own chassis;
  - catalog "dress" models are stripped of every mover, joint, constraint and script before they are welded on;
  - the client reads the thumbstick directly if the seat reports no throttle, and streams its input (≤ 15/s) to the server;
  - **watchdog:** if you push for ~1.5 s and the vehicle has not moved, the server takes the physics and drives it from your input stream (server driving has one round-trip of lag, only in that failure case);
  - passenger seats eject anything that is not a player (squad soldiers brought a turn-blocking BodyGyro);
  - the speed pill shows real speed; the owner (UserId 470626172) sees a one-line NO-DRIVE diagnostic naming the failing layer when he pushes and nothing moves.
- **Mobile items:** above 8 studs in a helicopter/plane the jump button is disabled and exiting needs a 0.5 s hold on the EXIT pill (gamepad B also exits); the big "Armed Jeep · Sit · WASD" billboards and "Press WASD" toasts are gone — the owner sees a small nameplate over his own vehicle only (≤ 40 studs, never through walls); away from your base SPAWN puts the vehicle in front of you (never in water, across a wall or indoors) and SPAWN is refused for 5 s after taking damage.
- **Auto-sit:** 30 studs away from home; up to 520 studs inside your own plot so Garage → SPAWN still seats you at base (`VehicleConfig.Drive.Spawn.AutoSitHomeRadius`).
- **Needs the phone:** whether it now drives with the thumbstick alone; if not, screenshot the NO-DRIVE line.

## 2026-09-24 — v70 phone polish + console-only buying
- **Console-only buying (owner request):** a base structure is bought or upgraded only at its **own console/kiosk on your own plot**. The server checks the character is within an 18-stud horizontal / ±10-stud vertical cylinder of that console (lag slack for a phone walking at Speed Boost). Refusals (far away, another plot, upstairs, seated, dead) get one toast "Go to your <Structure> console to buy it" and no cash moves. `ConsoleBuyConfig.Enabled = false` is the rollback. The Base overview (Command Center map table, tutorial) lists levels/costs/locks with a **GO** button that draws a gold line to the console — it never buys. StudioBuySmoke stands at the console instead of bypassing the rule.
- **Tutorial targets resolve to your own plot** (collector, dropper, spawn), the outpost to the nearest uncontested zone — the old markers sent players on plots 2-6 to Plot 1. Tutorial copy is device-neutral.
- **Phone rules applied:** text ≥ 14 px on every phone size (one documented exception: hotbar weapon names may shrink to 12 px); tutorial Skip and offer ✕ are 64 v; held prompts release when the finger lifts or slides off; the cash "+" is a chip in the top bar (out of the thumbstick zone; `CashPill.PlusOnPill` restores it); key hints (Settings controls sheet, garage "WASD", Army "(B)", "press K") only when `PreferredInput` is keyboard/gamepad; FIRE sits 16 px above the jump button; re-tapping the drawn weapon no longer holsters on touch (hold 0.5 s), and while holstered a dimmed FIRE draws and shoots when a hostile is in range; holding the Army tile 0.5 s cycles the squad order and the Army popover no longer hides FIRE.
- **Still open (other files):** Shop "press 1-4", PrestigeService "press K", MoneyCollector "click the dropper" and the dropper label "CLICK · $" (agent F / next copy pass); Territory dropdown text; hotbar slot 1 edges into the thumbstick zone with 4 weapons.

## 2026-09-24 — W1 early: road clean-up, first sound pass, asset licence clean-up, World v2 modules (unhooked)
- **Roads:** `Waterways.CullDressing` also removes decoration blocking the roads: collidable parts within 12 studs of a road centre line (whole kit folder when ≤ 64 studs), visible clutter within 8 studs of the lane, and parts they were carrying. Road ends, bases, territories and spawns are exempt (`WaterConfig.RoadCull`). Full dressing: 136 → 10 blockers; the 10 left are MapSetup parts (capture slabs, 2 garage pads, an NPC pad + statue, the radio-tower host) handled in W1's hook step.
- **Sound:** `SoundConfig` (25 keys, licence-cleared ids: Roblox-owned, Pro Sound Effects, APM), `AudioController.Play` with pools, ≤ 12 concurrent 3D sounds and per-key cooldowns, a music layer and a desert-wind/surf ambience, and `AudioHooks`, which only listens to existing remotes/HUD signals (purchase, collect, capture, raid alarm, missile siren, level up, engine loop pitched by vehicle speed). Nothing plays on the server. Music is on by default; the licensed sounds are for in-game use only (not promo videos).
- **Assets:** 22 catalog models that were paid or copies of real-world/franchise vehicles are removed (`VisualAssetConfig` id 0 → Part kit), plus the real-world launcher mesh on the Missile Defense structure. `docs/ASSET_LICENSES.md` lists every remaining external id and why it is allowed. Keep "Allow Loading Third Party Assets" OFF.
- **World v2 Phase 1 modules** (`WorldConfig`, `WorldTerrain`, `WorldBounds`, `WorldAtmosphere`, `WorldHygiene`) are committed but **not hooked in** — nothing changes in game until the hook step after agent F. Known: the first terrain build clears hand-painted terrain; haze preset V2 (revert `WorldConfig.Atmosphere.Preset = "Classic"`); the air wall has no roof until the aircraft turn-back lands.

## 2026-09-24 — v70 F world labels: the shared helper (step 1)
- **One helper for every floating label:** `Shared/Util/WorldLabel.luau` (`Create`, `Surface`, `SetText`, `SetOwner`, `SetRole`, `StartOwnerFilter`). Plain outlined FredokaOne text, no card, box sized in studs, **fixed** 14-20 px text (never TextScaled, the PP lane's cost item), `AlwaysOnTop = false`, `LightInfluence = 0`, range ≤ 40 studs (painted signs ≤ 80).
- **Owner-only labels stay server labels** (no per-player PlayerGui copies): attribute `WE_LabelOwner = UserId` + tag `WE_OwnerLabel`; each client hides other players' labels locally (`WorldLabel.StartOwnerFilter`, started by WorldPromptController). It is cosmetic: the text still reaches every client.
- **AlwaysOnTop only by role:** `WE_LabelRole = "objective" | "contested"` (`WorldLabelConfig.AlwaysOnTopRoles`). Keeping it to one objective at a time is the caller's job.
- **WorldLabelPolicy now also runs outside the plots** (`ApplyOutsidePlots`, rollback = false): every server BillboardGui in Workspace loses AlwaysOnTop (unless its role allows it) and is capped at 40 studs, measured from its Adornee or first positioned ancestor. In-plot cap 45 → 40. Until each service moves to the helper, labels that were far-reading (territory flag diamonds 150-180, the bank 220, NPC cards 90, supply drops 90) now show within 40 studs only and never through walls; TerritoryService rewrites the flag range on each refresh, and the policy clamps it back.

## 2026-09-24 — v70 F world labels: in-plot labels, neon and lights (step 2)
- **Light budget per base (hard cap 40 at L5; was 120, now 34 in the headless census):** every fitting part stays; only these lose their PointLight: ceiling fittings other than the one nearest each floor's centre (one light per floor), entry lamps, terminal lamps (the Neon lamp stays: interactive cue), red warning beacons (`WARNING_BEACONS` in HollowBuildingBuilder: the mast beacon and the tower / pylon beacon balls are gone or unlit), every second repeat of the same fitting inside one interior / installation module (`BuildingLights.LightEveryOther = false` turns that off), the stall lanterns and the premium pads. Interiors may now read darker at night: tune `StructureVisualConfig.BuildingLights.BrightnessScale` on a device before adding lights back.
- **Neon only where something emits light:** kit trims / stripes / antennas, flag tips, bullseyes, the spawn pad, the collect rings, NVG lenses and the legacy kits are SmoothPlastic; console buttons, terminal lamps, rack LEDs, the forklift beacon, the ATM screen, the premium pads and lamp balls (kit role `Window`) keep Neon. The 4 road dashes per base that run under the plot pad are world roads (WORLD-A).
- **SurfaceGuis draw near-only:** every SurfaceGui in my files now has `MaxDistance` (interior screens / stencils 40, building and gate signs 80; there was none before). To keep the SurfaceGui total under the 1,134 cap after adding painted signs (perimeter gate sign, 3 stall signs), the Armory's freestanding shelving and upper pallet are stencilled on one face (−9 at L4+). All-L5 total: 1,134 → 1,104.
- **Premium pad tags stay billboards** (`WE_PremiumBillboard`, "Auto Collect" / "R$", 20-stud range so none show while you stand at the ATM). Owner-only needs the plot owner: left to BaseService / ShopController (`WorldLabel.SetOwner` on plot assign, or hide pads of other plots on the client).
- **Removed server-side:** the console price cards (the client draws the owner's own tag), the ATM "COLLECT" card, TRAINING worker tags, the training earn board, the TRAINING YARD title, the train beams, rear-gate guard / stall NPC labels (stalls get a painted board), the SNIPER cues, the plot beacon, the tutorial marker debug labels. SoldierService still recreates the earn board on each training tick (its file, hand-off); the client keeps hiding it.
- **Outside the plots (label text only; WORLD-A rebuilds these pads):** garage / naval pad tags read "Garage" / "Naval" (no key names), NPC / event spawn debug labels removed.
- **Terminal prompts** (`WE_PanelPrompt`, building terminals, officer's desk, CC map table): MaxActivationDistance 8 → 12 (mobile P1-19).


## 2026-09-24 — v70 F services: labels, server message routing, bank retune (step 3)
- **Service labels use `WorldLabel`:** bank vault "Empire Bank" / "RAID IN PROGRESS"; supply drop "Supply Drop" / "$8,500"; territory zone label = zone name only in the owner colour (capture % and "contested" live on the HUD capture bar); flag diamond 28 px, through walls only while contested (`SetRole`); gate HP = one thin bar over the gate, shown only while damaged, breached, struck or raided. Owner-only: the dropper "$15" tag (hidden on unowned plots), the "+$15" dropper pop, the training and oil "+$N" pops (made only while the owner is within 28 studs), the squad-order flash. Removed: the floating ATM card (the ATM screen now has a status line: shield / being robbed / auto-collect / walk in), gate-guard and auto-gun name cards, the oil "+$/tick" card, the training earn board, the dead per-unit SQUAD tag branch.
- **Neon / lights in my files:** auto-gun marker ring and muzzle, territory flags and the oil IncomePad are no longer Neon (IncomePad removed); the dropper plate lost its PointLight. The paid GoldenPumpjack dress keeps its gold Neon (a bought look; revisit with the owner). TerritoryService writes only the owner colour to the capture marker and ring (World v2 owns their material / transparency / size).
- **Server message routing (spec §4.2):** collects are `Collect` + `Amount` (float only; walking over the ATM is silent for AutoCollect owners); ATM raid thief = Success line + "+$" float, victim = Error line + red "-$" float; capture stipend silent (`TerritoryConfig.CaptureStipend.NotifyOnPayout = false`); no "Squad: X" per order; "BASE UNDER ATTACK!" (Warn → the client's Alert slot, new `HudConfig.Toast.Reroute` rule) at most once per plot per 60 s instead of a toast every 1.2 s; no upsell companion lines; purchase failure Warns only for NoProfile / RateLimited / a full server (the client words the rest); no "Capturing X..." toast; the near-rebirth nudge once per session at L38 and once at L39; no key names or "click" in any server line. `NotificationService.Notify` gained an optional 5th `amount` argument.
- **Bank retune (task #20):** HEAD's 5 guards (28 dmg × 2.2/s, range 90, aggro 130) out-shot any player + squad, and the vault hold froze for anyone below 95 % health (no regen reaches that inside the 18 s respawn), so nobody could loot. Now `CombatConfig.NPCTypes.BankGuard` = 200 HP, 12 dmg, 1.3/s, range 75, aggro 90; `BankRaidConfig.RaidHoldSeconds` 8 → 6; the hold freezes only if you were hit in the last `UnderFireSeconds` (2). Headless end-to-end sim with the real BankRaidService, 7 seeds: a lone player in the open dies 7/7; player + 5-unit squad on ATTACK behind cover loots 7/7 (24-27 s). Guard respawn stays the global 18 s (a per-type `RespawnSeconds` needs a 2-line CombatService change — handed to Combat Core). Payout ($15-35K, 5 min cooldown) unchanged; owner may want to revisit it now the bank is winnable.
- **Bank retune (task #20):** hold time 6 s, the hold freezes only while the raider was hit recently (`BankRaidConfig.UnderFireSeconds`), guard tuning in BankRaidConfig/CombatConfig. Headless: player + squad on Attack behind cover wins 12/12 seeds; a lone player behind cover 0/12; a lone player in the open wins about 1 in 20 (guards miss). Adding a 6th guard (`GuardCount = 6`) removes the lone-player wins but costs an NPC slot under the live cap (MaxActiveNPCs 18 + 4 special) — left at 5.

## 2026-09-24 — W1 JEEP-2: brand-free vehicle names, airspace limit, prompts while seated
- **Names:** "Military Jeep" → "Field 4x4", "Armed Jeep" → "Armed 4x4", "Jeep HMG" → "4x4 HMG", tutorial "Spawn 4x4", depot board "4X4-02 READY". Internal ids (`MilitaryJeep`, `ArmedJeep`, `JeepHMG`, `Tutorial_Jeep`) are unchanged so saves, ownership and premium entitlements keep working. The Level 40 line says "Open Rebirth" (no K).
- **Airspace:** helicopters and planes turn back before the World v2 air box (`WorldConfig.Bounds.Air`) and level off at about 350 studs, with a red "Restricted airspace — turning back" line. The air box is live now, before the canyon walls are hooked, so the outer desert beyond ±2050 is no-fly: an aircraft out there is steered back in (never dragged on the ground; `AirBox.PushFrac` 0.5), and the server validator only flags aircraft still moving outward past box + 60 (`ValidatorOutwardSpeed` 8) or beyond ±3560. Rollback: `VehicleConfig.Drive.AirBox.Enabled = false`. Consider raising `WorldConfig.Bounds.Air.MaxY` to ~380-400 once the canyon buttes (320-340 tall) are live.
- **Prompts while seated:** every prompt outside the vehicle is hidden (range set to 0 locally, not `Enabled`) while you sit in any vehicle seat and restored on exit/death/respawn; console BUY works again when you step out.
- **Layout:** on touch the SPD pill and hint sit in the top stack under the capture bar (no overlap 800×360-1920×1080); on keyboard the pill uses the ammo slot.

## 2026-09-24 — Owner playtest chat commands /level and /xp
- The owner asked for enough XP to buy the helicopter. Admins on `AdminConfig.UserIds` (only 470626172) can type **`/level <n>`** (no number = 25, which unlocks every helicopter) or **`/xp <n>`** (no number = 10,000) in chat. Server-side, allowlist-checked, logged as ADMIN_COMMAND; not a remote and never available to other players. A chat line that arrives through more than one chat path within 1 s runs once. Buying a helicopter still needs the Helipad (Lv 1+) bought at its console and the cash (AdminPlaytestCash covers that).

## 2026-09-24 — Asset shortlist (for the owner's Grok bot) + clear-now ids
- `docs/ASSET_SHORTLIST.md` (+ `docs/asset_shortlist.json`) is the hard-wire sheet: one pick + one backup per slot, every id re-verified live against the Roblox store on 2026-09-24 (creator, type, free, contents where visible), the "do not use" list, a numbered step list for the Grok bot (store clicks + Studio checks + a report; Grok does not edit the repo) and what the lead wires afterwards.
- **Cleared now (§3.1):** 24 catalog ids set to 0 in `VisualAssetConfig` (the Part kits show instead): a 484k-triangle soldier swarm pack, a 156k-triangle mesa, a 100k-triangle sandbag nest, two third-party mesh/decal ids that bypass the third-party switch, and every vehicle model copying a real vehicle (Humvee/Bradley/FMTV/MRAP/F-15/F-18/Mustang look) or a game franchise.
- **Pending owner answers:** Roblox's own Weapons Kit Auto Rifle looks AK-like and its Rocket Launcher RPG-like. Default until the owner says yes: our own Part-kit guns.
- **Do not bake store models into the Padel-AI repo** (it is public); runtime loading by id is the default path.
- **Still to do after W2:** six UI/alert sounds in `SoundConfig` point at engine files no longer in the Roblox client (silent taps/notices); §3.5 has licensed replacements.

## 2026-09-24 — World v2 W1 hook (WORLD-A): canyon edge on, dead world props gone
- **Switched on:** `WorldAtmosphere.Apply`, `WorldBounds.Build` and `WorldTerrain.Build` (background task) are called from `MapSetup`, each behind one `FindFirstChild` + `pcall` guard: if a module is missing or errors, the map still builds and the old lighting block runs as the fallback. `WorldHygiene.Enforce` runs after the dressing / flora cull. `MAP_GEN` is 81/80 (odd = FaceMapCentre), so servers rebuild maps stamped 70/71.
- **Deleted:** the Part mountain ring, the fill patches, the 20 guard statues (no service read `GuardNPCType`), the oil spectacle, the warzone landmarks and every territory beacon. Outside the bases: parts 2,726 → 2,022 (Low 1,670 → 1,101), Neon 481 → 0, world BillboardGuis 71 → 16 (all ≤ 40 studs), static Humanoids 20 → 0.
- **Spawns come from `WorldConfig.Spawns`:** 10 garage pads with a painted "Garage" board, gate pads in plot coordinates facing away from each base, invisible NPC / event anchors (tags and folder names unchanged). Hostile NPCs now start at the Quarry, Ridge and Dune corner camps plus 4 territory points, not the old ring near the centre, so NPC kill trips are longer.
- **Naval pontoons carry no painted name** (decision): the text would have used 12 more SurfaceGuis, over the World v2 sign budget, and boats spawn from the Garage menu, so nobody has to find a pontoon. Restoring it is one `WorldLabel.Surface` call on the trim part.
- **Radio tower at the Oil Field yard moved 30 studs** so supply crates at the OilYard event anchor land on the ground, not through the mast.
- **Left for later:** TerritoryService's flag `WE_OwnerLight` (Range 28, up to Brightness 3.2, untagged) is the one world light-policy failure; flag poles stand (non-colliding) in the lane at the 5 road capture points; aircraft can touch the 400-tall ground wall before the air-box turn-back completes (pick: air box = wall box, or wall height ~170). All three need TerritoryService / WorldConfig changes outside this step.
- **Needs the engine:** Terrain can't be tested headless (build time budget ≤ 5 s, memory, cliff climbability, look of the Atmosphere haze; revert is `WorldConfig.Atmosphere.Preset = "Classic"`). The first terrain build clears any hand-painted terrain in the place.

## 2026-09-24 — Money M1: receipt core + quick wins
- **Starter Pack v2** (same product Id 3713839505): 149 R$, $50,000 + Auto Collect for good, one time, no Gold. A buyer who already owns Auto Collect gets $25,000 more Cash instead (`StarterFallbackCash`). If a second Starter receipt ever arrives (only by getting round the client's one-time guard), it is still granted, since Roblox has taken the Robux: +$75k.
- **Army Expansion (+10)** (same Id 3713839210): 99 R$, army cap +10, kept through Rebirth. It is a yes/no entitlement, so it never stacks, and old buyers of the +1 slot get +10 too.
- **Goodwill (owner decision D2):** players who bought the old Starter get Auto Collect once, outside `ProcessReceipt`, on a fully loaded profile only, flagged `Entitlements.StarterGoodwillV2`, with a thank-you toast.
- **Offers:** none while the tutorial is unfinished; the Starter card is sent 3 s after the tutorial ends (8 s after load when already done) and the HUD still holds offers until 90 s after join. No Speed Boost pop-up on spawn or on sitting in a vehicle, and no Cash Mega pop-up after a death. The server also caps offers at 3 per session, 240 s apart (`SoftOfferSessionMax`, `SoftOfferSessionCooldownSeconds`). The server and HUD budgets can drift, so a server-sent offer can be refused by the HUD and its one-time flag is still spent; the M3 Offer Director fixes that.
- **"Army full" chip:** detected on the client from the latest `SoldierStateUpdate` (the server refuses with `AtCap`; there is no refusal remote). The chip replaces the Army Expansion button in place so nothing moves.
- **No double charge:** the new Army, Commander Pack and Battle Pass UNLOCK buttons treat a product bought this session as owned as soon as `PromptProductPurchaseFinished` fires, like the Shop does.
- **New keys with Id 0** (Nuke, Nuke x3, 6 premium-vehicle passes, Rebirth Boost) are hidden with a `Feature` tag until their feature ships; the wire tool keeps them hidden when an Id is pasted.
- **Dashboard gap:** after this publish the game shows 149 / 99 R$ while Roblox still charges 249 / 79 R$ until the owner changes the two prices. Do the Dashboard change straight after publishing.

## 2026-09-24 — Join hotfix (owner's sister stuck loading)
- **Diagnosis:** no game code blocks or holds a joining player (two-player headless sim, 9 runs: save loads, plot 2, can move, no kick). The likely causes were Roblox-side: the game was Private until 17:54 UTC (Private = Edit-permission users only), and it is rated "Mild, Ages 16+", so until it passes Roblox's Kids/Select review only age-checked players 16+ and the owner's Trusted Friends can join. The non-streamed world is about 1–3 MB (headless estimate): a slow load on a weak phone, not an endless one. `docs/LIVE_PLACE.md` is corrected.
- **Store-model templates live in ServerStorage** (`WE_VisualAssetTemplates`), not ReplicatedStorage, so joiners no longer download templates nobody on the client reads; clones are still made on the server. One line in `ensureFolder()` reverses it.
- **Gate guards give a spawn grace:** guards and AutoGuns ignore a player whose save has not loaded (such a player cannot fire or raid) and, for `GateDefenseConfig.SpawnGraceSeconds` (4), a player who just spawned or whose save just loaded, since a new player's random first spawn can be someone's gate pad. The grace ends early when the player holds an ATM raid or hits the gate or a guard.
- **Left for Combat Core / streaming:** with more players than the 6 plots, a plotless respawn stays on a random gate pad (`CombatService.TeleportToBase` needs a plot); it gets the 4 s grace but cannot attack or raid under it. StreamingEnabled (faster joins, less phone memory) is the next step once Combat Core is committed.


## 2026-09-24 — W2 Combat Core (CC-1 server combat, CC-2 vehicle HP, CC-3 client feel, verifier)

## W2 CC-1 (server combat) — assumptions

- **A-CC1-1 Claim decides.** A validated P0-7 claim ends the shot's resolution even when the damage is then refused (PvP off, spawn shield). The assist never runs after a validated claim ("first rule that decides wins").
- **A-CC1-2 Assist depth.** When the exact ray hit scenery, the assist's `maxAlong` is that distance + `ClaimBeyondHitStuds` (3), whatever `ClaimAfterSceneryHit` says. With no hit, it is the assist range `min(weapon Range, 150)`.
- **A-CC1-3 Splash spares clan mates.** `CombatFeelConfig.Splash.ExcludeClanAllies = true` is a CC-1 additive field (the W2 task asked splash to respect allies). A direct bullet hit on a clan mate still lands as it does today; there is no clan friendly-fire rule yet.
- **A-CC1-4 Gate hit marker.** When `GateDefenseService.ApplyDamage` accepts a hit, the attacker now gets a `CombatHitFeedback` "Hit" (`TargetKind = "Gate"`). Gates take no fall-off. Before W2, gate hits sent no marker.
- **A-CC1-5 NPC miss tracer.** A missed NPC shot sends WeaponFx with `K = "M"` and `P` = the target's torso plus a random 2–4 stud horizontal offset. There is no extra raycast to find the scenery.
- **A-CC1-6 Shooter leaves.** A player's live projectiles are removed when they leave (`Projectile.ForgetOwner`). They have no impact and send no "X"; the client drops the visual at T + 0.5 s. A projectile that lands after its shooter's `Player.Parent` is nil deals no damage.
- **A-CC1-7 Blast centre.** The explosion centre is the hit point pushed 0.5 studs out along the surface normal, so the splash line of sight starts outside the surface. With no hit, it is the point at MaxSeconds.
- **A-CC1-8 Shield attribute.** `WE_ShieldUntil` is written only when the combat state exists at CharacterAdded. That is the same condition under which the server sets `InvulnerableUntil`. If `GetServerTimeNow` fails, `os.time()` is the base.
- **A-CC1-9 Own vehicle is always out of the ray.** A seated player's vehicle (any model tagged `WE_Vehicle`, registered or not) is always in the shooter's Exclude filter. The seat-fire refusal rules apply only to registered vehicles, as §1.2 says.
- **A-CC1-10 Where death attributes live.** `WE_LastWeapon`, `WE_BlastSource` and `WE_BlastAt` are Humanoid attributes. `WE_BlastAt` uses `os.clock()`, so it is server-local.
- **A-CC1-11 Immediate `Died` fix.** `Died` can fire inside `TakeDamage` (Immediate signal mode, and the headless sim). While the damage is applied, the NPC record carries `KillCtx`, so its Died handler pays quiet (blast) and splash kills correctly: no toast, or no per-NPC kill marker.
- **A-CC1-12 Mouse cone vs body size.** The KeyboardAndMouse class (1.0 stud, 1.5°) is narrower than a 2-stud torso, so for mouse players the assist only matters at the body edges. The headless "outside" offset for that class is at least 1.1 studs, so the exact ray misses the torso.
- **A-CC1-13 Seat check order.** Driver (`VehicleSeat` or `WE_SeatRole == "Driver"`) → mount (`WE_MountId`) → passenger with `WE_CanFireFromSeat` → refuse, in the order of contract §1.2.
- **A-CC1-14 Assist cost cap.** Per shot, at most 8 in-cone candidates are kept and at most 3 line-of-sight rays are cast, smallest lateral first. Players get a cone pre-check before the seat and clan lookups.
- **A-CC1-15 Feedback send.** `hitFeedback` now wraps `FireClient` in pcall, so a player who has just left never breaks a shot.
- **A-CC1-16 Aim stats log.** One summary line (`[CombatService] aim: ...`) is printed lazily on the first shot after each 300 s window (`AimStatsLogSeconds`). It needs no extra thread.
- **A-CC1-17 Asset loader clone.** `WeaponAssetLoader` clones the asset's Tool children (or the `VisualChild` model's children) into `Weapon_<Id>` and sets `PrimaryPart = Handle` when a Handle exists. Today it does nothing, because every `VisualAssetId` is 0.

## W2 CC-2 (vehicle health) — reversible assumptions

- **Own-plot regen test.** "Inside the owner's plot" uses the plot pad tagged `WE_BasePlot` with `PlotId == profile.BasePlotId`. The Chassis must be on the pad's rectangle, margin 0. The pad's CFrame carries the plot yaw, and `VehicleService.insidePlot` uses the same test. The plot pad stands in for the "BaseLayout plot frame".
- **Raid shield.** premium §3.5 mentions a raid-shield protection. It is not implemented, for two reasons: no service exposes `IsShielded(userId)`, and contracts §4.1 leaves it out of `IsProtected`. Add it to `VehicleHealth.IsProtected` once that API exists.
- **What `IsProtected` blocks:**
  - It returns true for an unregistered model.
  - It also blocks an attacker who sits in a trial vehicle (`VehicleCombatConfig.Trial.DealsVehicleDamage = false`).
- **`WeaponMult` default.** The default comes from `InfantryWeapons[WeaponId]` only when that row's class is the class being applied. Example: an explicit `Class = "NPC"` hit that carries `WeaponId = "RocketLauncher"` is not doubled. An explicit `WeaponMult` always wins.
- **Radius distance.** Distance is measured to the Chassis box (0 inside it), not to the whole model's bounding box. This is cheaper, and the Chassis is the hull.
- **Nuke core-destroy switch.** The Nuke class destroys outright inside `CoreRadius` only when both flags are on: `VehicleCombatConfig.DamageClasses.Nuke.CoreDestroys` and `NukeConfig.Vehicles.CoreDestroys`. Setting `NukeConfig.Vehicles.CoreDestroys = false` turns it off.
- **`Repair(model, pct)`.** `pct` is a fraction from 0 to 1. A value above 1 is read as a percent (50 means 50 %).
- **Rounding.**
  - MaxHP is rounded to 3 decimals, so that `WE_MaxHP` (ceil) does not read 281 for 280.
  - `RepairingFor` reports `ceil(left − 1e-6)` seconds, with a minimum of 1.
- **Bounty toast.** The toast reads "<DisplayName> down (+$N)", the same shape as an NPC kill. The HUD therefore reroutes it to a cash float, with no lane line during combat. The XP is paid but not shown in the text.
- **Owner notice.** When the teardown runs after `DebrisSeconds`, the owner gets "<DisplayName> destroyed" as a Warn toast for 4 s, through `destroyVehicle`'s message.
- **Wreck physics.** On wreck, LinearVelocity and AlignOrientation are switched off (`Enabled = false`), not just zeroed. An airborne or floating wreck therefore falls or sinks under gravity. The server takes network ownership.
- **Occupant damage fallback.** Occupant damage goes through `CombatService.ApplyHit` (with `WeaponId = "VehicleWreck"`) when that function exists. It falls back to `Humanoid:TakeDamage(35)` when `ApplyHit` is missing or errors. Squad units never ride today (F8 ejects NPCs from passenger seats), so the squad path is only for M6 mounted units.
- **HUD bar colour.** The occupant HUD bar fill is "armor cyan" (90, 196, 235), not green. On touch it sits right under the green capture bar, and two green bars read as duplicates. Below 25 % it flashes red.
- **HUD bar placement.** The HUD bar decides "touch" with the same test as the SPD pill in VehicleDriveClient (`TouchEnabled` or `PreferredInput == Touch`). That keeps the bar and the pill in the same layout: the stack on touch, bottom-right on desktop.
- **Over-bars.**
  - Height is `WE_LabelY − 0.75` studs, just under the owner nameplate.
  - Three BillboardGuis are pooled in PlayerGui, with `Adornee = Chassis`.
  - The "own parked vehicle below MaxHP" bar is shown only to its owner.
  - A heal never re-arms the 5 s window.
- **Wreck burst.**
  - It uses the default ParticleEmitter texture; no new `rbxasset://` path is set.
  - It emits 24 particles from one pooled Attachment under Terrain.
  - A vehicle that streams in already wrecked gets no burst.

## W2 CC-3 (client feel) — assumptions (reversible; the verifier appends these to ASSUMPTIONS.md)

- **A-CC3-1 (test re-pin, audio).** `w1/snd/t_audio.luau` check 0a keeps a licence allowlist of every SoundConfig id. The
  21 new combat ids (docs/ASSET_SHORTLIST.md §3.5, all owned by ProSoundEffects, User 7462895450) are not on it, so the
  unmodified suite reads 148/149. `w2/cc3/t_audio_w2.luau` is the same file with only those 21 ids added to 0a's list:
  149/149. The W1 file itself is unchanged. BuyPathStatic re-pins: 0.
- **A-CC3-2 (sounds).** Values nobody has listened to yet: volumes 0.35–0.8; priorities Kill 4 > Headshot 3 > Confirm /
  Hurt 2 > shots 1 (rocket 2, explosions 3–4). Sniper has no MaxSeconds (the shortlist gives none). Reload / Empty / Equip
  are World-bus 3D sounds at the local character (contract table), MaxDistance 60. `Hit.Headshot` = the `Hit.Confirm`
  file at pitch 1.8.
- **A-CC3-3 (recoil spring).** The vendored RbxUtil Spring is a critically damped `TweenService:SmoothDamp` spring (no
  Speed / Damper). SmoothTime = 2 / `WeaponConfig.Recoil.Recover` (`CombatCamera.RecoilSpring.Speed` only when Recover is
  missing); `RecoilSpring.Damper` is unused. The impulse is sized so the peak kick equals `Recoil.Kick` degrees (x 0.5 on
  touch); `Side` is a random yaw in ±Side. If `SmoothDamp` is missing on a client, a hand-rolled critically damped spring
  with the same maths runs instead.
- **A-CC3-4 (allies).** The client does not know clans (no attribute in W2): the camera aim help may slow over an ally.
  The server assist excludes allies, so no ally is ever hit by assist.
- **A-CC3-5 (local fire ray).** The local ray now starts at the head-projected Origin and runs for the weapon Range +
  `CombatConfig.HitPositionSlopStuds` (was: from the camera, 500 studs). It is the same line the server's exact ray uses,
  so tracers end where the server hits, and a far miss no longer reports a HitPosition out of range (`fire_hitpos_oor`
  soft strikes). `TargetUserId` / `TargetNpcId` hints now name only targets inside weapon range.
- **A-CC3-6 (local shot schedule).** The 20 Hz send loop is unchanged (the server clamps). Local flash / tracer / recoil /
  casing / bloom follow the server's GCRA fire schedule (FireRate x research WeaponFireRate) and a predicted magazine
  (reset by every CombatStateUpdate), so a slow gun held at 20 Hz shows its own fire rate.
- **A-CC3-7 (damage numbers).** Spawned 26 px right / 30 px above the hit point's screen position (never on the
  crosshair), then rise 24 px and fade over 0.8 s. At most 4 labels; the oldest is reused.
- **A-CC3-8 (target bar).** Stays visible during a reload (only the reticle hides): it is small, under the crosshair, and
  times out 2.5 s after the last hit. Hidden while holstered, driving, dead or in a panel.
- **A-CC3-9 (haptics).** `HapticService:SetMotor` on `Touch`, then `Gamepad1`, only when `IsVibrationSupported` and
  `IsMotorSupported` say yes; 80 ms pulses, at most about 8 per second. On a phone without motor support nothing happens
  (device-only check).
- **A-CC3-10 (RequestSetDrawn).** Sends the "shown" state (drawn AND alive AND allowed to shoot from this seat), so other
  players never see a gun on a driver or in an enclosed seat. Leading edge at once, trailing edge after 0.5 s (≤ 2/s).
- **A-CC3-11 (gun grip).** Guns use the Roblox Tool default grip (barrel along the RightGripAttachment's -Z, top along +Y).
  `HudConfig.CombatFx.Grip = { RotationDeg, OffsetStuds }` (zero) is a device-tuning knob if the hold animation needs it.
- **A-CC3-12 (passenger seats).** On a seat with `WE_CanFireFromSeat` the whole combat HUD (hotbar, FIRE, RELOAD, ammo,
  reticle, health) shows and the 1-4 / Q keys work. The pinned auto-draw-on-damage line still uses `seatedNow()`, so
  nobody auto-draws in any seat. A driver never gets combat input in W2.
- **A-CC3-13 (FX parts lifetime).** Pooled FX parts park at (0, 10000, 0); each part pool is destroyed after 20 s without
  use, so every FX part is gone within 25 s of the last shot. Explosions use 3 (touch 2) pooled attachments with
  emitters (0 parts), outside the Impacts cap.
- **A-CC3-14 (remote launch sound).** Another player's rocket / grenade launch ("L") plays its fire key at O; the shooter
  hears his own from LocalShot.
- **A-CC3-15 (casings).** Desktop only; a 0.35 s tween to 2.6 studs below the ejection port (no physics), parked after 2 s.
- **A-CC3-16 (HUD harness).** `check_hud.py` creates every RemoteName as a RemoteEvent, so in those runs WeaponVisuals
  does not bind WeaponFx (it polls 120 s, then warns once). The CC-3 driver replaces it with an UnreliableRemoteEvent,
  as RemoteSetup does on live (CC-1's UNRELIABLE list).
- **A-CC3-17 (shake units).** Shake output x 1 stud (position) and x (8°, 8°, 4°) (rotation): BlastAmplitude 0.6 ≈
  ±0.15 stud / ±1.2° point blank, fading linearly to 0 at radius x MaxRadiusMult; touch 0.3. Hit pulse = HitAmplitude x
  clamp(damage / 25, 0.5, 1.5), halved on touch.
- **A-CC3-18 (shoulder camera).** Like the Weapons Kit ShoulderCamera, the root yaw is written directly (only when the
  camera yaw moved > 1°). AutoRotate is restored to the Roblox default (true) on release.
- **A-CC3-19 (Trove).** Vendored per the contract but not used by the W2 code yet (nothing needed a clean-up bag).
- **A-CC3-20 (drag-to-aim hit test).** TouchStarted compares `InputObject.Position` with FIRE's `AbsolutePosition` /
  `AbsoluteSize` (the same GUI-inset space in Roblox) ± `FireSlopPx`, and ignores touches another button already took
  (`gameProcessed`: RELOAD, the jump button, panels). Device check: holding FIRE and dragging turns the camera.
- **A-CC3-21 (out of scope, flagged).** The shortlist found `rbxasset://sounds/electronicpingshort.wav` / `switch.wav`
  missing from the client, so `UI.Click`, `UI.Notify`, `Toast.Warn` / `Toast.Error`, `UI.Denied` and `Capture.Start` are
  probably silent. Fixing those is the asset workflow's config commit (shortlist §6.1), not CC-3.
- **A-CC3-22 (aim step).** CameraFx binds its per-frame step only while recoil is in flight, the shoulder camera is on, or
  aim help is on (touch / gamepad, drawn). A drawn PC gun with no recoil runs nothing per frame.

## W2 verifier — assumptions and fixes

- **A-V-1 Origin behind a wall.** `RequestFire` keeps the P0-7 rule (Origin within `MaxOriginDeltaStuds` 12 of the root, else strike + snap). An accepted Origin that is not visible from the head (a ray from the head, `RespectCanCollide = true`, shot filter excluded) is now snapped to the head with no strike. It stops shooting through a wall with a forged Origin up to 12 studs out, and rockets spawned inside a base. Legit W2 clients send the point on the camera ray nearest the head, so they are almost never snapped. Revert: delete the `else` branch after the desync check.
- **A-V-2 Enclosed drivers.** J10 (drivers keep their rifle) now applies to driver seats with `WE_Exposed ~= false` only. An enclosed driver seat (APC, tank, heli, jet) is refused, like an enclosed passenger. Before W2, the driver's own hull blocked these shots, and the W2 client never sends driver fire, so only a modified client notices. Revert: drop `and seat:GetAttribute("WE_Exposed") ~= false` in `seatFireRule`.
- **A-V-3 No heal by respawn.** SPAWN is refused with the existing "InCombat" reason for `SpawnCfg.DamageLockSeconds` (5 s) after any live vehicle of that owner took damage. Without it, a vehicle at 10 % HP could be swapped for a full-HP copy in place, either by SPAWN on the same id or by Despawn and then SPAWN, whenever the 15 s spawn cooldown had passed. A destroying hit clears the lock, because the repair timer covers wrecks. State: `VehicleHealth.HitLockLeft(userId, seconds)`.
- **A-V-4 Rocket first ray.** `Projectile.Launch` takes an optional `From` (the shot origin). The first step's ray starts there, not at the spawn point 1 stud ahead. Before, a player whose head was within about 1 stud of a wall fired straight through it with an honest client.
- **A-V-5 NPC FX buckets.** `destroyNPC` calls `CombatFx.Forget(rec.Id)`, because NPC ids never repeat and the per-shooter bucket table grew for the life of the server.
- **A-V-6 Left as contracted.** `VehicleHealth.ApplyRadiusDamage` has no line of sight. A rocket that hits a wall still damages a vehicle within the radius behind it (headless: a 4x4 1–5 studs behind a 1-stud wall is destroyed). Humanoid splash does check line of sight. Nukes and missiles need the no-LOS behaviour, so any change is an owner decision (option: a `RequireLos` flag in `RadiusOpts` for the infantry rocket only).
- **A-V-7 ASSUMPTIONS.md.** The verifier was limited to builder-owned files, so this combined block (CC-1 + CC-2 + CC-3 + verifier) is written to `scratchpad/w2/verify/ASSUMPTIONS_append.md` for the committer to append.

## 2026-09-24 — HUD scale fix (sister's phone: rail cut off, cash pill over "Garage")
- On the sister's Android (about 932x430 GUI units) the left rail and cash pill were drawn about 1.29x too big: the WarEmpireHUD UIScale stayed at 0.90 (the fallback `HudLayout.Scale()` uses before the camera reports a viewport) instead of 0.70. HudLayout and UIUtil tracked their UIScales, topbar areas and visibility bindings in weak-keyed tables; in Roblox a weak table keyed by an Instance can lose the entry once no Lua code holds that Instance, even while it is still on screen, so the later viewport update never reached the scale.
- Fix: strong tables, pruned when a scale or frame leaves its gui (layout change) or a bound object is destroyed; and `HudLayout.Scale()` returns the phone scale (0.70) on touch devices until the viewport is known, then the viewport watcher corrects it (tablets move up to their own scale).


## 2026-09-24 — W3 step 1: kit catalogue, Crossroads Town, travel dressing, H1 Enforce, Roblox-owned look

### contracts (from scratchpad/w3/contracts/assumptions.md)
- **W3 disabled POIs stay reserved.** Travel dressing (rhythm, junctions, shore, scatter) keeps out of all 18 POI footprints + 30 studs, built or not (`WorldDressConfig.Keepout.POIMargin`), and the emptiness metric counts the reserved footprints as occupied, as `world_v2_model.py` does. Enabling a POI later never moves the travel dressing. Revert: skip `Enabled = false` POIs in `WorldDress.Blocked`.
- **W3 shore features stay in Quality Low.** The spec gives Low rules for POIs (60 %), rhythm (every other) and scatter (none) only. Revert: `WorldDressConfig.Quality.Low.ShoreEvery = 2`.
- **W3 pure-Luau PRNG.** `WorldKits.Rng` (xorshift32 on bit32) replaces `Random.new` in all W3 build code, so the headless sim renders exactly the live layout (the sim's `Random` is a different LCG). Revert: swap the implementation; the sim layout then differs from live (rules still hold).
- **W3 world signs.** The world SurfaceGui budget (`WorldConfig.Budgets.SurfaceGuis` = 12, inside the CLAUDE.md 1,134 cap) is spent as 10 garage signs + 1 Crossroads Town board. Junction direction posts and checkpoint boards are painted arrow / stripe parts with no text in step 1. The lead re-plans the 12 before the other 17 POIs.
- **W3 H1 Enforce knob.** H1 Enforce is switched in `WorldConfig.Hygiene.OrphanMode` (B1's file, per the contract), not by a second knob in the travel-dressing config. BPS pin `OrphanMode = "Report",` is retired for `OrphanMode = "Enforce",`.
- **W3 Terrain-only clusters** (roadside rock outcrops, scatter rock clusters and boulder fields) create no instance: 0 parts, 0 instances. They are counted in the build summaries, the occupancy and `WorldKits.TerrainLog()`.
- **W3 WorldKits.Finish refuses a cluster wider than 64 studs** (H10) or with 0 parts, instead of letting WorldHygiene report it later.
- **W3 no MAP_GEN bump** unless MapSetup itself changes: the dressing is rebuilt by every `MapSetup.Run`, and the live place is a Rojo build without a baked map.
- **W3 mesh overlays replace, never add.** A Roblox-owned Synty mesh (VisualAssetService.CloneKitMesh) replaces the fallback part (natural 1-part kits) or all visual parts but one invisible Box collider (solid kits). Part budgets are measured in the sim, which has no InsertService, so the Part kits are the upper bound.
- **W3 cluster Models use `ModelStreamingMode = Atomic`**, so a building never streams in half-built. Harmless while StreamingEnabled is off (today).

### B1 (from scratchpad/w3/B1/assumptions.md)
- **W3 Town layout is data.** The Town is 46 cluster rows plus 6 terrain rubble / scorch groups in `WorldConfig.Town`. My layout source is `w3/B1/town_layout.py`.
  - The water tower is at (-118, -175). It closes a market street that runs west off the north arm (4 tarp stalls with crates).
  - The clock tower stands on the south-east plaza corner at (100, 100).
  - There is one building on each of the other three plaza corners, facing the flag, plus 1–2 frontage buildings per road arm.
  - The houses on the Empire Bank side frame the bank.
  - The Town Square arena is 4 paving tiles round the TownSquare anchor, with a dry fountain 30 north of the anchor and benches.
  - Plan: Full 213 parts. Low (Tier 1) 116 = 54.5 %.
  - Reversible: edit or remove rows. Nothing in code depends on a row.
- **W3 Town board faces the west approach.** RoadZ0 carries plots 1, 2, 5 and 6; RoadX0 carries plots 3 and 4. So the one painted "CROSSROADS" board (the Town's only SurfaceGui) stands on the west approach at (-292, -22). Reversible: move the `Board` row.
- **W3 flat paving may lie over an event anchor.** Flat marking clusters (every part top <= 0.75, no collision; only PaveTile in step 1):
  - accept an `anchor:Event_…` result from `WorldDress.Blocked`, because the supply crate lands on the paving;
  - are not added to the occupancy (the Town footprint is reserved anyway).
  - PaveTile stays non-colliding (contract §2.3). SupplyDropService's downward ray therefore passes through the tile, and the crate sits on the ground 0.12 below the paving top.
  - Reversible: make PaveTile collide, and drop the anchor exception.
- **W3 mesh overlay modes: never more parts.** The contract's "collider + mesh" rule adds a part for 1-part solid units (a single crate, a bench), so B1 uses three modes:
  - **skin** (CrateStack crates, Bench): a SpecialMesh inside the Part, using the MeshId, TextureID and MeshSize read from `CloneKitMesh`. Net 0 parts, box collision kept.
  - **each** (natural kits): each part is replaced by a MeshPart. Net 0.
  - **collider** (Wreck "car" only, the only variant with a CarWreck mesh): the largest part becomes the invisible box collider, and 1 mesh is added. Net 2 − n.
  Overlays are deferred and capped by `WorldConfig.Kits.MeshOverlays` (40 per server). Town kits queue first.
  Reversible: set `Kit.Mesh = false`, or change a kit's mode in `queueMesh`.
  Mesh orientation (Synty pieces assumed Y-up, aligned with the kit frame) needs a Studio check once LOOK wires ids.
- **W3 kit sizes are measured.** `WorldKits.Specs[*].Size` is the measured AABB of the default build. The unit test checks it to ±0.25.
  - New `WorldKits.Footprint(kit, opts)` returns the exact pivot-relative extents: `X0` / `X1` / `Z0` / `Z1` / `Top`, plus `CollideZ0` and `VisibleZ0`.
  - Road-side kits keep every collidable part at local z >= 0 (the back half): Wreck, DrumGroup, CrateStack, SandbagLine, SandbagNest, Jersey, RoadMarker, DirSign, SandbagArc.
  - Wreck long axis is local X (parked along the road).
  - JettyStub, BargeWreck and BeachedHull have their pivot at the landward end, with the hull reaching toward -Z (the water).
  - Checkpoint pivot is on the road centre line.
- **W3 catalogue additions (B1's file).**
  - New kit `CompoundWall`: a 3-tall adobe wall (cover), 1 part per 16 studs, up to 4.
  - New `AdobeHouse` variants `"wide"` (18-wide row house) and `"shop"` (cloth awning instead of the second window). Still 5 parts each.
  - Both give more street frontage for the same part cost.
  - Reversible: drop the rows that use them.
- **W3 Town shadows.** Only building bodies, stall back walls and tarps, shop awnings, the tower tank / deck / roof, the clock shaft / head, the ruin walls and the fountain rim cast shadows: 34 casters (cap 60, H9 >= 8 only). Roofs, legs, counters and walls do not. Reversible: the `shadow` argument in each builder.
- **W3 Terrain rubble is Tier 1.** It costs 0 parts, so Low keeps it. `WorldKits.Rock` keeps every prim within the group's outer radius (`opts.Radius`, default `WorldConfig.Kits.Rock[kind].Radius`), and callers test `WorldDress.Blocked` with that same radius.
- **W3 `WorldKits.Discard(cluster)`.** New helper to destroy a built-but-rejected cluster, so its pending sign and overlays are dropped.
- **W3 the world sign budget counts every SurfaceGui outside the bases.** It counts those under `WarEmpireSetup` (except `Bases`) plus the signs in clusters that are still open. `Sign` returns nil at `WorldConfig.Budgets.SurfaceGuis` (12). Step 1 uses 11: 10 garage signs + the Town board.
- **W3 checkpoint barriers dropped.** The v1 jersey barriers ahead of each checkpoint (8 parts) went to frontage buildings in v3. Reversible: add `Jersey` rows on the shoulders at ±15 (13.9 off the line).

### B2 (from scratchpad/w3/B2/assumptions.md)
- **W3 WorldDress never yields (`WorldDressConfig.Budgets.YieldEvery = 0`).** The contract planned `task.wait()` every 25 clusters, "returning at once" on the sim's main thread. In the Luau CLI the driver's main chunk is itself yieldable, so the sim's `task.wait` really yields and the run dies ("thread yielded unexpectedly"). WorldTerrain avoids this the same way (its drivers pass `YieldEvery = 0`). The whole travel build is 0.07–0.11 s of CPU in the sim (budget 1.0 s), inside MapSetup's deferred dressing thread, and the old coordinate-list dressing never yielded either. Revert: set `YieldEvery = 25` on live if the owner ever sees a start-up hitch; the drivers must then run the dressing in a coroutine.
- **W3 Quality Low keeps rhythm clusters 1, 4, 5, 8, 9, … of each road (`Rhythm.LowPattern`).** The contract wording was "the 1st, 3rd, 5th …", but sides flip on every accepted cluster, so the odd ones would all sit on the same side of the road (and fail the verifier's alternating-sides rule). The pattern keeps exactly half, sides still alternate, and Low stays a strict subset of Full: every Low build places the same spots with the same kits, then drops the other half. Revert: `LowPattern = { true, false }`.
- **W3 scatter target tuned to 310 (EmptyRadius 155, MaxClusters 56).** The spec says "stop when the largest empty circle is ≤ 340"; `world_v2_model.py` actually runs `scatter(target_diam = 320)` (49 clusters, final measure 340 at cell 20). With our stricter keep-outs and the Town's own clusters, 340 stopped at 24 clusters (far100 16.9 %, fails V10) and 320 at 40 (one below the verifier's 41–57 band). 310 gives 46 clusters, 104 parts, far100 12.0 %, largest empty circle 322 at cell 20 (live flag state). With FaceMapCentre off (rollback: no dock channels, more dry land) the fill would reach 60, so MaxClusters = 56 (model 49 + 15 %) caps it: 56 clusters, 117 parts, far100 13.6 %, largest 322. Revert: `Scatter.TargetLargestEmpty` / `EmptyRadius` / `MaxClusters`.
- **W3 road-side clusters are re-centred and pushed, never trusted from the spec sizes.** WorldKits pivots road-side kits at their front edge (collidables at z ≥ 0), so each composed cluster is centred on its spot, then its real parts are measured: collidable parts ≥ 13 and visible parts ≥ 9 from every road centre line. A cluster too close is pushed out along its road (never past offset 34) or dropped. Terrain rock outcrops need their whole reach (12) ≥ 13 from the line, so they sit 25–34 out. Revert: none needed (it only makes placement stricter).
- **W3 every travel cluster is also checked with the WorldHygiene H3 zones on its real part AABBs** (captures, aprons, garage pads + 16, plot pads + 4, pier corridors, water + 6), on top of the contract's disc test. So Waterways.CullDressing and WorldHygiene.Enforce remove 0 parts of Rhythm / Junctions / Shore / Scatter (verified: 0). Revert: none needed.
- **W3 in-water kits (jetty stub, barge wreck, beached hull) step into the water only as far as `Shore.InWaterMax` (10) and only into `Ring_*` / `Sea_*` rects** (`Shore.InWaterRects`): never a dock channel, lagoon, harbour, slip or plot water. The recorded occupancy disc stays on the bank line (so the ring / zone rules on the disc hold); the stepped kit is tested separately with `Blocked(AllowWater, SkipRing)` at its real centre and radius. The Bay's beached hull therefore lies on the sea bank about 45 studs seaward of the Bay line. Revert: `InWaterMax = 0` keeps every hull on dry land.
- **W3 land shore features step to the water's edge (`Shore.ToWater`, `LandEdgeGap = 7.5`).** The spec places canal features "28 studs in from the water"; a revetment, reeds or driftwood 28 studs inland reads as litter on the sand. The occupancy disc (and so every zone rule and the verifier's geometry) stays on the 28-stud bank line; the kit moves seaward until its nearest part is 7.5 from the water (WorldHygiene H3 needs > 6). Their Terrain rock groups move with them and are tested with every keep-out except the ring box (inset 20 from the canal), since the water + 6 rule is the boundary there. Dune grass stays on the Bay line (dunes sit behind the beach). Revert: `ToWater = {}`.
- **W3 the travel dressing casts no shadows.** WorldKits requests CastShadow on big parts (≥ 8: barge hull, truck bed, dead tree); WorldDress clears it on every travel cluster (contracts §2.2: 0 casters outside the POIs; phones). Revert: delete the loop in `compose`.
- **W3 junction kits face a world-aligned corner.** The arrow post faces the junction centre, one jersey barrier lines each shoulder (≥ 17 from both centre lines), the sandbag arc sits behind, a Terrain boulder group (reach 7) behind that. The contract's "stack of 2 jerseys" is read as a pair on the corner, since kit pivots are yaw-only on the floor (no vertical stacking). The first free corner of (+,+), (−,+), (+,−), (−,−) is used. Revert: change the recipe in `buildJunctions`.
- **W3 shore / bay kinds rotate over accepted spots across all three canal lines (one rotation), and the Bay has its own**, as in `world_v2_model.py canal_bank()`. Shore features all stay in Quality Low (contracts ruling). Revert: `Quality.Low.ShoreEvery`.
- **W3 Terrain rock budget is reserved at each group's maximum** (`Terrain.Rocks[*].MaxPrims`) whether Full keeps it or Low drops it, so Low and Full make the same acceptance decisions; actual prims are 218 (Full, flag on) / 252 (flag off) for B2 against the 400 cap. Revert: none needed.
- **W3 DesertFlora builds nothing in step 1** (contracts §5.3): the two lone mid-map saguaros were H1 orphans and the flora now comes from the road rhythm and the scatter. `DesertFlora.Kits`, the folder, the cull and Enforce stay; the third-party Palm / Cactus / DesertRock overlay loop is gone. Revert: restore `midSpots` (they would be destroyed by H1 Enforce anyway).
- **W3 MapDressing keeps only the Dockside quay kit and the kits it uses** (crate stack, oil drums, light pole, ammo shed, fuel depot, vehicle silhouette, sandbag line). Its ammo-shed / fuel-tank catalog hosts stay (LOOK's call, contracts §8.4). The legacy Dockside sandbag line on RoadX0 is still culled by Waterways (12 parts, as at HEAD); it goes with the Port POI step. Revert: none (the deleted sections are in git history).
- **W3 WorldHygiene H1 stand-alone rule.** A natural unit whose instance carries `WE_Elements` ≥ `Hygiene.MinNatural` (3) and whose parts come in ≥ 2 sizes (largest dimensions ≥ 20 % apart) is anchored; the NaturalLink grouping stays. Report adds per-anchor-class counts (`Census.Anchor_poi / road / junction / water / natural / none`, informational). WorldHygiene's module-level `WaitForChild` calls (no timeout) became direct indexing, like every other W3 server module. Revert: drop `standsAlone` (then scatter clusters are H1 orphans and Enforce destroys them).

### LOOK (from scratchpad/w3/LOOK/assumptions.md)
- **W3 LOOK LUV body on the light 4x4 family.** Only `Vehicles.MilitaryJeep` is wired (6418221666, Roblox, User 1). ArmedJeep,
  ScoutCar, ReconBuggy, UtilityQuad and DispatchCar stay `ModelAssetId = 0` and get the body through
  `KitFamilyFallback.WheeledLight` (the BuyPathStatic pin `ArmedJeep = { ModelAssetId = 0` stays true). Revert:
  `MilitaryJeep.ModelAssetId = 0` (every light 4x4 back to the Part kit).
- **W3 LOOK body fit.** The body is scaled uniformly to the kit chassis length (jeep 8.5: scale 0.483, body 3.95 wide x
  3.83 tall), tyre bottoms on the physics-wheel bottoms, centred on the chassis, front to the kit front (-Z). The collision
  box stays the Part kit (about 0.9 studs wider than the visible body on each side). The driver sits on the roof line, as
  on the old kit (the seat offset belongs to VehicleService). Revert: `Fit = nil` (old pivot-onto-chassis dress).
- **W3 LOOK kit hidden under the body.** With `HideKit`, every Part-kit part except `KeepVisible` (GunMount, Barrel) gets
  Transparency 1; physics, seats, hit boxes and names are unchanged. The 5 largest body panels cast the car's shadow
  (`FitShadowShare` 0.5 of the chassis length; default when the key is absent). Revert: `HideKit = false`.
- **W3 LOOK camo decals stripped.** The LUV green camo uses 41 Decals whose images are owned by a user account
  (Orlando777, 715494), not Roblox; they are stripped (`StripDecals`), so the body is the plain dark green (39, 70, 45) of
  its paint parts, and the two Neon lamp parts become SmoothPlastic. Revert: `StripDecals = false`.
- **W3 LOOK utility quad / recon buggy.** They get the same LUV body at their smaller kit length (a smaller 4x4), as the
  roadmap says. The shortlist's Roblox Dune Buggy (6433272094) would fit them better; not wired (not verified in this step).
- **W3 LOOK DesertKit pieces chosen by fit, not by the shortlist.** WorldKits stretches a piece into the fallback part's
  box, so a key is wired only when the piece's per-axis stretch ratio is <= 2.2: DeadTree = Tree_Pine_Dead_01 (2.11;
  shortlist pick 2.75), Stump = Tree_Stump_01 (1.47; shortlist pick 2.73), Reeds = Plant_Reeds_01 (1.11), DuneGrass =
  Plant_01 (1.22; shortlist Grass_04 is 4.35), CrateWood = Crate_Wood_04 (1.00). Revert: change `ChildName`.
- **W3 LOOK keys left at 0 (ChildName filled in).** `Log` (WorldKits uses the key for FallenLog, Z-long, AND Driftwood,
  X-long: 20x squash), `Bench` (kit box is the seat only; 2.52), `CarWreck` (kit lies along X, the sedan along Z), and the
  optional `VanWreck`, `Pebbles`, `Skip` (no caller). Each is a one-number change once WorldKits fits it.
- **W3 LOOK flat palette.** Every DesertKit piece has `ClearTexture` and a colour from `WorldConfig.Kits.Palette`, so no
  City-pack atlas text can show and the pieces match our Part kits. Revert: `ClearTexture = false`.
- **W3 LOOK 40-part cap at load.** `MaxPartsPerModel = 40` (CLAUDE.md catalog budget) refuses any whole-model template or
  pack piece with more BaseParts after stripping; a Humanoid is stripped (`STRIP_CLASSES`) and the template is refused if one
  is left. Third-party ids that exceed it (e.g. Shipping Containers 17701461178, 126 MeshParts) now stay Part kit even if the
  owner presses Get Model. Revert: raise `MaxPartsPerModel`.
- **W3 LOOK packs split once.** A pack id (any configured ref with `ChildName`) is inserted once; every configured piece
  becomes its own template in `ServerStorage.WE_VisualAssetTemplates`; the rest of the pack is destroyed. A piece added to
  config later needs a new server. Revert: none needed (config-driven).
- **W3 LOOK one insert per id.** While an id is being inserted, other callers wait for it (yield) instead of inserting it
  again, so the ~40 deferred WorldKits overlays cost 1 load attempt per pack. A caller in a non-yieldable context gets nil
  (Part kit).
- **W3 LOOK vehicle pack preload.** `VisualAssetService.Init` inserts the vehicle body pack once in a deferred task (not
  in Studio when inserts are skipped), so the first 4x4 spawn does not wait on InsertService.
- **W3 LOOK third-party world-dressing hosts dropped (19 ids → 0).** The 15 contract keys plus AmmoShed (117 MeshParts,
  over the cap), StreetLamp, StreetLampAlt, SupplyShed, RoadBarriers, CheckpointBridge, SpyBunker, DesertHouse and Pier:
  none has a caller after the W3 rewrite (checked by grep), so there is no runtime change beyond the Dockside ammo shed's
  invisible host staying empty. `DesertProps.Palm` 96059329869678 stays as dead config because BuyPathStatic pins the
  literal; `MapDressing.Palm` (its alias) is 0. Revert: restore the ids (docs/ASSET_LICENSES.md §2c keeps them).
- **W3 LOOK docs/ASSET_LICENSES.md reconciled.** The 24 ids cleared in 859dedc were still listed as "remaining"; they are
  now in §2b, the W3 drops in §2c, the Roblox-owned ids in §3.0. The file lists exactly the live config ids (56 third-party
  + 3 Roblox-owned, + the verified-but-unwired City pack).

### Integration verifier
- **W3 contract pin on `WorldPOI.Build`.** B1 typed `occ` through a local alias (`type Occupancy = WorldDress.Occupancy`), so the pinned signature is `function WorldPOI.Build(dressing: Instance, quality: string, occ: Occupancy?): Summary`. The type is identical. Revert: none needed.
- **W3 BuyPathStatic retirements.** Lines 235, 586, 587, 617, 618, 619, 642, 678, 1430 (MapDressing coordinate-list sections deleted) and 1734 (`OrphanMode = "Report",`) are retired; their replacement pins are in the W3 block. The needles `WreckScorch`, `RoadCrater` and `RoadChevron` get no replacement (the names stay hygiene marking prefixes).
- **W3 old jeep suite.** `w2/cc2/t_jeep_server_k2pin.luau` (K2) expects the stub asset shape, not the real Roblox LUV pack. `w3/LOOK/t_jeep_server_look.luau` with `fakes.luau` replaces it (131/131).

## 2026-09-24 — Crossroads Town v2 (denser, taller; owner found step 1 too sparse)
## W3 Town v2 (densify): assumptions (reversible; append to ASSUMPTIONS.md)

- **Town budget is set by the 512-stud circle, not by taste.** Everything outside the Town inside the busiest 512 circle
  (centre about (128, 128)) is 121 parts: 73 world parts plus the 48 skyline parts that count in every circle. So the Town
  can hold at most 379 parts before a 512 circle passes 500. `POIs.Town.Budget` goes from 220 to 370 (the build uses 368),
  which leaves the busiest circle at 488 (grid 128) or 489 (grid 16). To undo: lower `Budget`. Rows past the cap are skipped
  with a warning, never placed.
- **Town lights go from 6 to 8.** The 6 street lamps stay. 2 wall lanterns are added: 1 part plus 1 PointLight each, on the
  NW plaza block (facing the flag) and the first east-arm block. They share the street lamps' light policy through
  `nightLamp`: Brightness 0.6, Range 16, no shadows, tagged `WE_NightLight`, night only. There are now 13 world lights,
  under the cap of 24. Low keeps all 8.
- **The 30-stud road rule is unchanged.** Frontage blocks still use a disc: the AABB half-diagonal, 30 + 0.6 off each
  road centre line. That puts shop fronts 33–39 studs from the centre line, so the verge is about 26–32 studs wide. The rule
  was not changed to a per-box test because the verifier's W3-zones and TOWN-clusters checks use the disc. If the owner
  wants narrower streets, a box rule would bring the fronts to 30.
- **The parked burnt truck and a jersey barricade are street clusters.** They are tested part by part, like checkpoints and
  lamps: every collidable part is at least 13 from the line and every visible part at least 9. `SE_Wreck` moved from
  (250, 52) onto the east-arm verge at (232, 14.5). The barricade is on the north-arm verge at the plaza corner. W3-road
  still counts 0 collidables within 12 of a road line.
- **`RadioMast` is built now.** It was a step-2 kit whose spec size was 10 × 90 × 10. It is now step 1, "Town+POI", 5
  parts and 6 × 90 × 6: a plinth, 2 tapering sections, a red painted tip (never Neon) and a relay dish. The Signal Station
  can reuse it later. The kit unit test's `KIT-step2 RadioMast` check is replaced by the normal step-1 kit checks.
- **New kit `TownBlock`.** It has 1–6 storeys at 7 studs each.
  - **Parts:** 1 solid body (cover, H4), 1 parapet slab, 1 inset window strip per upper storey per face, a door or a
    shopfront (rolled shutter plus cloth awning), and rooftop tanks, a hut, a mast or a dish.
  - **Variants:** `damaged` (the top storey's +X half is blown off and a fallen slab lies on the roof) and `gutted` (a
    burnt-out shell).
  - **Tower blocks:** blocks with 5 or more storeys use Concrete in a light-concrete colour automatically.
  - **Shadows:** one shadow caster per block, so the Town has 56 casters (cap 60).
  - **Options:** new optional `KitOpts` / `KitPlace` fields `Width`, `Depth`, `Storeys`, `Roof`, `Lantern`. Existing kits
    and their APIs are unchanged.
  - **Footprint cache:** the key now includes these fields.
- **`AdobeHouse` and `RuinedHouse` are no longer placed in the Town.** `TownBlock` replaces them, with terrain rubble by
  the damaged and gutted blocks. Both kits stay in the catalogue, unchanged.
- **Moves and removals:**
  - Landmarks:
    - The clock tower moved 4.5 studs toward the plaza, to (95.5, 95.5). That is the least clearance its disc needs from
      r 124.
    - The water tower moved 8 west, to (−126, −175), so it closes the new market lane.
  - Market lane:
    - The 4 stalls now stand in the lane between 2 lane blocks.
    - The separate crate stack is gone; the stalls carry crates.
  - Town Square:
    - One bench pair was dropped.
  - Unchanged: the checkpoints (r 310), the board, the square tiles, the fountain and the motor pool jerseys.
- **The SW plaza corner stays open toward the Town Square**, so the flag looks across to the fountain and the radio mast.
  A 2-part sandbag arc marks the corner.
- **Low keeps Tier 1 only: 215 parts, which is 58 % of 368 (cap 220).** Tier 1 holds the first block of each road arm,
  the plaza blocks, the 4 landmarks, the south lane block, 2 stalls, the square's south block, the checkpoints, lamps,
  board, tiles, fountain and the wreck.
- **Terrain rubble:** 9 groups by the damaged and gutted blocks, giving 25 prims in the Town (cap 40, unchanged).
- **Driver expectations updated where the design changed on purpose.**
  - W3 acceptance (`S/w3/densify/drivers/w3_driver.luau`):
    - `W3-town-budget` reads `POIs.Town.Budget` and fails above 370.
    - `W3-town-lights` reads `POIs.Town.Lights` and fails above 8.
    - `W3-town-signs` reads `POIs.Town.Signs` and fails above 1.
  - Town driver (`S/w3/densify/drivers/b1_driver.luau`): `TOWN-lights` expects 8, not 6.
  - Kit unit test (`S/w3/densify/drivers/kits_driver.luau`): 38 new `TownBlock` and `RadioMast` checks.
  - Run unchanged, the step-1 drivers fail only those 3 checks: W3-town-budget, W3-town-lights and TOWN-lights.
- **Renders only:** the renderer draws thin façade parts (window strips, doors, shutters) over the wall they sit on.
  Before this, a painter sorted by centroid could hide them behind their own wall. This affects the pictures only.

### Verifier additions (adversarial pass)
- **The sum of the POI budgets is now 1,770, against the §7.1 plan of 1,700 or less.** At HEAD it was 1,620. Only the Town
  is enabled today, so nothing is over a cap at runtime (1,444 parts outside the bases, cap 2,900). Before the other 17
  POIs are built, their budgets must drop by 70 in total, or the lead must re-baseline §7.1. Town v2 is the reason for the
  change, and the lead accepted Town growth of about 150–170. To undo: lower `POIs.Town.Budget`.
- **The sum of the POI light caps is now 25, up from 23.** Non-POI world lights are 5 today (13 − 8), so with every POI
  at its cap the world would plan 30 lights against the cap of 24. HEAD was already over, at 28. The next POI lane must cut
  its light caps.
- **Two floating details were fixed in `TownBlock`.**
  - `RoofDish` sat 0.62 studs above the roof. It now sits on it: its centre is at `roofY + 1.3`, with a tilted half-height
    of 1.28.
  - `LampLantern` stood 0.15 studs off the wall. It now touches the wall at `fz - 0.4`, reaching 0.8 in front.
  - Neither fix changes a part count, a Footprint extent that the layout uses, or a pin.

## 2026-09-24 — Rollover fix (owner: "The quad falls over when driving super easy")
## Rollover fix (owner report 2026-09-24: "The quad falls over when driving super easy") — assumptions

Reversible assumptions for ASSUMPTIONS.md (all tunables live in `VehicleConfig.Drive.Stability` and
`VehicleConfig.Drive.Modes.Car`; one-line reverts are given).

1. **Rider mass for sizing = 14 (R15 at density 0.7), sitting 1.3 studs above the seat's top face.** Used only to
   size the ballast, to place the drive point at the centre of mass and to size the upright assist. The real rider joins
   the chassis assembly through the SeatWeld. Sensitivity was measured for riders of 10, 14 and 20 (Rthro). With a
   20-mass rider the quad's static stability factor is 1.55 and it tips at 57°; at HEAD it was 0.80 and 39°.
2. **Ballast = 1.0 x (kit + rider) for light 4x4s and the quad, and 0.4 x for trucks and APCs. Tracked, air and naval
   get none.** The mover force (`WE_DriveLV`) and torque (`WE_DriveAO`) scale with mass, so acceleration, top speed and
   turning feel stay the same. The heavier car pushes harder in car-vs-car and car-vs-player collisions: a light 4x4
   goes from 77 to 154 mass, and trucks go up x1.4. Revert: `Families = {}`.
3. **Ballast sits at `BallastHeight = 0.5`, halfway between the tyres' ground line and the axles.** This is below the
   chassis. It is invisible, has no collision, query or touch, and is welded to the Chassis. It is not physically
   plausible, but it is invisible, and it lowers the centre of mass more for the same mass.
4. **The drive point (`WE_DriveAttach`) moves to the nominal centre of mass** (`DriveAtCoM = true`), so the drive's
   cornering and braking force produces no roll or pitch moment. `WE_DriveAO` shares the attachment, and its torque
   does not depend on where the attachment sits. Revert: `DriveAtCoM = false`.
5. **`WE_UprightAO` is a roll/pitch-only AlignOrientation.** It tops `WE_DriveAO` up to `UprightFrac` (0.75 for light
   vehicles, 0.6 for trucks and APCs) x weight x min(half track, half wheelbase). That total stays below gravity's own
   righting moment, so the assist cannot lift wheels on slopes or ramps and cannot right a car that is lying on its
   side. Assumption: `AlignType.PrimaryAxisParallel` aligns the attachment's X axis in the same direction as the goal's
   X axis (world up); `PrimaryAxisOnly = true` is also set. This needs a device.
6. **Wider track by vehicle id: UtilityQuad x1.2 (3.60 → 4.32 studs), ReconBuggy x1.1, DispatchCar x1.1.** The physics
   wheels are hidden under the fitted Light Utility Vehicle body, so the change does not show. The Part kit shows the
   wheels further out, which reads as a quad. Revert: `TrackScale = {}`.
7. **Speed-sensitive steering: the turn rate is capped at `MaxLatAccel / speed`, with `MaxLatAccel` = 120 studs/s²
   (0.61 g).** Nothing changes below 50 studs/s. At the quad's top speed of 58 the turn rate is 2.07 rad/s instead of
   2.4. At 87 (1.5x research) it is 1.38. Tracked vehicles never reach the cap.
8. **No traction and no steering while flipped (UpY < `FlipUpY` = 0.5, tilted past 60°).** The commanded speed brakes
   to 0 at the class's `Brake` rate. At HEAD, a car on its side with the stick held was driven along the ground at up to
   60 studs/s. This matches the "SPD 45" in the owner's screenshot.
9. **Flip recovery replaces the old 0.5 s x 15 studs/s hop** (the hop moved the car up to 7.5 studs up plus its
   horizontal speed). The recovery starts after 1.5 s on its side or roof below 3 studs/s:
   - It holds X/Z still, lifts at 6 studs/s to 2.5 studs, levels the car at 2.5 rad/s through `WE_DriveAO`, then lowers
     it at 6 studs/s until it touches down.
   - It gives up after 2.5 s, or once it has moved more than 5 studs from the start.
   - It waits 4 s between tries, allows at most 5 starts per minute, and never starts while another player (not a rider
     of this car) is within 4 studs of the car's footprint.
   - The same law runs on the driver's client, in server drive, and for an empty car (the server idle law).
   - The per-minute count resets when the driver exits and sits again. This is harmless: a try lifts 2.5 studs at most
     and never moves the car horizontally, and the server validator is unchanged.
10. **The owner standing next to his own empty, flipped car blocks the idle recovery** (he counts as "another player"
    until he sits in it). If he sits back in, the client law rights it with him aboard. If he steps about 4 studs away,
    the server rights it. Alternative, if the owner prefers: exclude the owner in the idle case.
11. **The two existing checks that pinned the old hop now fail by design and have patched copies:**
    - `water/build/v/t_server.luau (h)`: "hop at 2.0 s, Vy 15"
    - `jeep2/suites/t_client_jeep.luau 1h`: "0.5 s hop Vy 15"
    The patched copies (`rollover/patched/`) check righting at 1.5 s with Vy 6 and X/Z at 0. The suite owners should
    adopt them.
12. **The catalog vehicle dress (W3 LOOK Light Utility Vehicle body) was checked, not changed.**
    `VisualAssetService.weldCloneToPrimary` makes every clone part CanCollide, CanQuery and CanTouch false and Massless
    true. The existing K2 test confirms it, and a pin is proposed. It adds no mass and no collision width. No
    VisualAssetService edit was needed.

13. **(Verifier) The watchdog ignores a flipped car.** Without traction a car on its side does not move, and the
    righting lifts it straight up. A driver who sat into a flipped car and held the stick therefore tripped the
    "nomove" watchdog after 1.2 s (server check) or the client's Stuck report after 1.5 s. That forced server drive,
    and after righting it was counted toward `SessionTrips` (2 trips = every later ground sit starts in server drive).
    Now the server watchdog does not count "pushing" while UpY < `FlipUpY` or for `RecoverMaxSeconds` (2.5 s) after the
    last flipped sample, and the client does not run its Stuck clock while flipped or righting. An upright car that is
    pinned still trips exactly as before (tested). Revert: remove the two blocks marked "rollover fix" in
    `watchdogStep` / `watchClient`.

## 2026-09-25 — v72 war businesses + next-buy guide (shipped with both flags OFF)
## v72 Tycoon Guide and War Businesses (merged from lanes K, A, B1, B2, C + integration; all reversible)

### Flags and scope
- `BusinessConfig.Enabled` and `TycoonGuideConfig.Enabled` ship **false**. With both off, server, world, census, HUD and every suite match HEAD (measured). Flip both together, only after Lane D (MapSetup + StructureVisualConfig, `build/integ/laneD.diff`) lands; then also flip the two `Enabled = false` pins to `Enabled = true`.
- Server gating: business world code (SyncBusiness / SyncPlot / ClearPlot) runs only with BusinessConfig on; BusinessService.Init connects nothing (no re-pick loop, no WE_NextBuy / WE_AtmPos) with the guide off. WE_PassiveTick only with businesses on; WE_IncomeMult with either flag; WE_IncomePerSec and the "+$/s" toast suffix only with the guide on.
- Client gating: every new B1 / B2 branch checks the guide flag (F3 BUY-lane shift and F5 Plot-1 arrow hide included); BusinessVisuals follows BusinessConfig only.

### Economy (owner sign-off pending)
- Business numbers and requirements are a proposal, tuned in BusinessConfig (table in BALANCE.md). Arms Crate Line requires Ammo Works L1 + Weapons Facility L1.
- Armor Plate Press IncomePerTick is 1.2x the spec draft ({120,220,360,580,860}) so guided run D with the 34 % soldier rule reaches 295 $/s at 30 min (spec 274). Revert = those five numbers.
- OPEN: guided run C's longest wait in the first 10 min is 141 s (target <= 120 s; Arms Crate Line L2 at 6:58). Armor/Rocket numbers cannot fix it (it happens before the Armor Press unlocks). Lead/owner decides.
- Soldiers are offered by the pick only while the config-computed training share is < 0.34.
- Displayed $/s = TycoonMath.PerSecText: step gain x WE_IncomeMult / 5, floored (one decimal below $10/s, whole dollars above; oil unscaled). It can under-read for prestiged players (double-prestige bug out of scope). A "+$N" pop can read $1 high at prestige >= 1 (WE_IncomeMult rounded to 0.01, pay floors twice).
- WE_IncomePerSec = last passive + training + plot_oil grants / 5; a reason drops out after 2 missed ticks. In Studio with FastPassiveIncome it over-reads ~5x (live unaffected).
- Passive formula moved to TycoonMath.BasePassivePerTick: identical for valid saves; junk saved levels are clamped.

### Tutorial and guide
- Tutorial step 6 is Ammo Works only while BusinessConfig.Enabled (Barracks moves into the guide Opening); flags off it stays the Barracks buy. No Tutorial_Business marker part: GO resolves through PadStructureId to your own kiosk; the beam re-aims every 2 s until the kiosk streams in.
- Guide chip shows only after the tutorial, only inside your own plot; hidden on Tutorial, Modal, Driving, Dead, RecentCombat, AtConsole. The pick is advice only; the server re-checks every buy. Hide = 300 s or until the next successful purchase ack.
- Auto-guide: 12 s idle (<= 2 studs moved per 1 Hz sample) with the chip on screen, > 20 studs from the target, Build/Collect only, once per pick.
- The Command Center L1 unlock text ("6 new buildings") never fits the chip hint at 20 v in the harness; it is dropped per spec.
- Base panel: businesses after the 15 buildings under a WAR BUSINESSES header; gold outline + NEXT badge on the pick; flags off keeps HEAD's "+N/t" rows via string.format.

### Buy surfaces
- BUY 300x72 v on touch (336x58 v on desktop with the guide on, incl. the key cap shown only for keyboard/gamepad PreferredInput, never in Collect). Two 20 v lines, never scaled below 20 v; line 1 falls back to the short name, then no name.
- The thumb-zone lane shift (TycoonMath.ActionLaneShiftV; Lane 0 owns HudLayout) applies on touch only.
- Earn (red) tap still sends the buy request (server answers InsufficientCash); only Collect (amber) sends nothing and draws the line to your own ATM.
- Console tag: owner-only, stud-scaled, fixed 16/15 px text, never AlwaysOnTop; ranges 18 (build) / 14 (upgrade) / 40 (the NEXT pick). Business kiosks have no SurfaceGui and no Neon; visitors see an unnamed kiosk.
- Cash pill "+$N/s" suffix: green 20 v, not tappable, <= 2 Hz, hidden at 0, behind PillIncome; uses commas from $1,000/s (TycoonMath.RateText has none). It sits in the bottom-left zone under the owner's v70 decision.
- ConsoleTag / BuyLane / auto-guide / Hide / pill keys live in TycoonGuideConfig, not HudConfig. ShortNames (<= 10 chars) for the 15 buildings live there too.

### World and budget
- Business sites plot-local (-30,100), (-66,100), (34,60), (70,60), Yaw 180, kiosks 10 studs toward the gate; built only on owned plots. Rebirth and admin resetbase reset businesses to L0.
- Lane D: FloorChevrons = false (static arrows removed), StaticSoldierDetail = false (static soldier kit 9 parts, -84 per base), gate signs inset by InnerWall.SignInsetStuds x PixelsPerStud (80 px) with text capped at 64 px. StairStyle = "Steps"; ramps are a reserve cut only (nothing reads the key yet).

### Client visuals
- Up to 3 crates per own line within 80 studs (1 at saved Graphics Quality 1-3; Automatic counts as full), pooled, moved by one BulkMoveTo at <= 20 Hz; other players' lines never animate.
- "+$N" pop (floor(IncomePerTick x WE_IncomeMult)) on each WE_PassiveTick, at most 2 per tick, within 28 studs of the character, 1.2 s, billboard MaxDistance 40. The server now stamps WE_IncomeMult before WE_PassiveTick so the pop uses the current multiplier.

### Tests
- The flags-ON gate uses the kiosk-aware drivers build/A/gate_driver_biz.luau and tut_driver_biz.luau; the originals (polish/C/gate_driver, tut_driver) fail on a flags-ON tree by design (no kiosks before a plot is owned / MapSetup-only world). Switch worldhook/verify/run_all.sh to them at the flip.
