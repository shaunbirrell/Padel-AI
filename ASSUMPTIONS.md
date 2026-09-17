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

17. **ClanId / BattlePass / Achievements** — Schema fields present; grant logic mostly stubbed for later phases.

18. **Anti-exploit** — Rate limits + strike counter; not a full physics anti-cheat.


19. **Combat damage** — Always from `WeaponConfig` (× `Pellets` for shotguns). Client may hint hit target/position; server raycasts and re-validates range/ownership/fire rate/ammo.

20. **Respawn** — After death, wait `GameConfig.RespawnTimeSeconds`, `LoadCharacter`, teleport to assigned plot `PlayerSpawn` (or plot pad + offset).

21. **NPC pool** — Runtime models tagged `WE_NPC`; StudioSetup may place a few placeholders. Cap `CombatConfig.MaxActiveNPCs`; respawn after `NPCRespawnSeconds`.

22. **PvP** — Gated by `GameConfig.PvPEnabled`; friendly fire by `GameConfig.FriendlyFire`. First PvP engagement logs `FIRST_PVP` once per user session/account flag.


23. **Vehicle models** — Placeholder Part chassis + VehicleSeat (no MeshParts). Driving uses Roblox VehicleSeat physics as a temporary control scheme until custom chassis.

24. **One active vehicle** — Spawning despawns the previous vehicle for that player. Cooldown from `VehicleConfig.SpawnCooldownSeconds`.

25. **Vehicle unlock gates** — Level + optional base structure level (`RequiresStructure`) + cash; starter `MilitaryJeep` granted on join.

26. **Territory ownership** — Runtime world state is authoritative (not only profile.Territories). Profile mirrors personal ownership for persistence/UI. On leave, ownership remains until contested/captured by others.

27. **Territory states** — Neutral / Player / NPC / Clan / Contested. NPC seeds: EastArmory + RadarHill on server start. Clan ownership uses profile.ClanId when set (ClanService still stub).

28. **Capture** — Proximity stand-in-zone only (CollectionService `WE_CaptureZone` preferred, else `WE_Territory`). Progress is server tick-based; `RequestCaptureTerritory` is an optional UI ping.

29. **Max personal territories** — `TerritoryConfig.MaxPersonalTerritories` (3). Capturing beyond max releases the least-protected owned territory.

30. **Protection period** — After capture, `ProtectionPeriodSeconds` slows enemy capture via `ProtectedCaptureMult`.

31. **Daily missions** — UTC day key refresh; progress tracked by ObjectiveType from combat/territory/upgrades/cash/vehicles. Claim is separate from complete.

32. **Daily login** — Handled by MissionService (moved from Bootstrap inline handler). Same UTC streak rules.

33. **Achievements** — Config-driven one-time grants checked on mission progress / level-up / upgrades / cash totals.

34. **Shop** — Client prompts Marketplace with placeholder IDs; server ProcessReceipt is idempotent and stores `ProcessedReceipts` on profile when present.

35. **Tutorial** — Steps: ClaimBase → CommandCenter → Income → Barracks → Jeep → Outpost. Server `TutorialService` advances; client shows panel + best-effort `WE_TutorialMarker` waypoints. `DevConfig.SkipTutorial` (Studio) or SKIP button completes. Default `SkipTutorial = false` for playtest.

36. **Studio mock GamePasses** — `DevConfig.MockOwnedGamePasses` or admin `grantpass` only in Studio when product Ids are still 0.
