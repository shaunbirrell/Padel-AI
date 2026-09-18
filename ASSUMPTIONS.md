# ASSUMPTIONS — WAR EMPIRE

Reversible engineering decisions made while implementing the MVP without blocking questions.

1. **Rojo mapping** — `Shared` and `Server` / `Client` trees use `$path`; `ReplicatedStorage.Remotes` is an empty Folder in the project file and is filled at runtime by `RemoteSetup` (also works if Rojo creates the folder).

2. **Base plots** — Exactly 6 plots; first free plot assigned on profile load; occupancy released on leave. `BasePlotId` remains on the profile as a preference for rejoin but occupancy is authoritative in memory.

3. **Starting upgrades** — All structures start at level **0**. Command Center is purchasable with starting $5000 (cost $1500). Barracks requires Command Center L1.

4. **Passive income** — Default tick every **5 seconds**. Base $25/tick + per-structure-level rates from `EconomyConfig`. First Barracks (~$2500) is reachable within about a minute with base income + early upgrades.

5. **Prestige cash mult** — Also applies to passive income for consistency.

6. **Session lock** — Soft lock via secondary DataStore; in Studio without API services, lock/load soft-fails and uses defaults. Live servers kick on lock conflict.

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

21. **NPC pool** — Runtime models tagged `WE_NPC`; StudioSetup may place a few placeholders. Cap `CombatConfig.MaxActiveNPCs`; respawn after `NPCRespawnSeconds`.

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


37. **Prestige** — Requires Level ≥ PrestigeConfig.MinLevelToPrestige (100). Resets Cash/Level/XP/BaseUpgrades; keeps Vehicles/Weapons/Gold; grants GoldBonusOnPrestige; Cash earnings use EconomyConfig.PrestigeCashMultiplierPerLevel. Admin `forceprestige` / `prestige`.

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

50. **Client settings** — `ClientSettings` music/SFX flags are local-only (no DataStore). Settings UI (O) documents keybinds. Controllers should gate future audio with `ShouldPlayMusic` / `ShouldPlaySfx`.

51. **Studio smoke** — `tools/SmokeTest.luau` is command-bar pasteable in Play Solo. Validates remotes/configs/services; may invoke `GetPlayerState`; admin probe fires a no-op `__smoke_ping__` only when LocalPlayer is in AdminConfig — never grants cash/gold/XP.
