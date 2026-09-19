# WAR EMPIRE

**BUILD. CONQUER. DOMINATE.**

Commercial Roblox military tycoon / territory / vehicle collection game.  
Rojo-ready Luau codebase — Phase 1–7 MVP (Foundation → Monetization + polish).

## MVP status

**READY_FOR_STUDIO_PLAYTEST** — Phases 1–7 playable loop + Prestige / Clan scaffolding / Battle Pass track. Product IDs remain `0`. Validate with Rojo sync + StudioSetup; this environment cannot run Roblox Studio.

## Requirements

- [Rojo](https://rojo.space/) 7.4+ (see `aftman.toml`)
- Roblox Studio with Rojo plugin
- Enable **Studio Access to API Services** for DataStore testing (Game Settings → Security)

## Quick start

1. Open a blank Baseplate place in Roblox Studio.
2. From this folder: `rojo serve` (or `aftman install` then `rojo serve`).
3. In Studio, connect the Rojo plugin and sync.
4. Paste contents of `tools/StudioSetup.luau` into the **Command Bar** and run once.
5. Press Play. You should spawn with **$5,000**, see the HUD, follow the tutorial (or SKIP), open **Base Upgrades** (**B** or the big bottom button), then tap **BUY $price** on a row (B does **not** purchase instantly). Grey pads are markers — walk near them and press **E** (ProximityPrompt) or use **B** / **G**.
6. Optional lighting: Ambient ~(80,90,70), Brightness 2, ClockTime 14 for clearer military placeholders.

## Merging open PRs

Two feature branches may be open against `main`:

| PR | Branch | Contents |
|----|--------|----------|
| #1 | `phase-3-combat` | Phase 3 combat + Phase 4 vehicles |
| #2 / polish | `phase-5-territory` → `phase-7-polish` | Phase 5–6 + Phase 7 monetization + MVP polish |

**Recommended merge order:** merge PR #1 (`phase-3-combat`) into `main` first, then merge the Phase 5–7 PR (rebase/update if needed). Do **not** merge only one and ship — combat/vehicles and territory/progression/monetization are complementary. If both target `main`, resolve conflicts preferring the newer polish branch’s shared files (`Bootstrap`, `Constants`, `Remotes`, `README`).

## Admin UserIds

Edit `src/ReplicatedStorage/Shared/Configs/AdminConfig.luau`:

```lua
UserIds = {
  123456789, -- your UserId
},
```

Admin remotes: `RequestAdminCommand` with commands:

| Command | Args | Effect |
|---------|------|--------|
| `givecash` | number | Add Cash |
| `givegold` | number | Add Gold |
| `givexp` | number | Add XP |
| `setlevel` | number | Set level |
| `unlockall` | — | Unlock all vehicles + weapons |
| `resetbase` | — | Zero all structure levels |
| `resettutorial` | — | Restart interactive tutorial |
| `grantpass` | PassKey | Studio mock GamePass own (`VIP`, `DoubleCash`, `DoubleXP`) |
| `prestige` / `forceprestige` | — | Prestige (force sets level gate first) |
| `createclan` | name, tag? | Create clan |
| `joinclan` / `leaveclan` | clanId? | Join / leave clan |
| `bpxp` | number | Add Battle Pass XP |
| `grantpremium` | — | Grant Battle Pass Premium flag |
| `endseason` / `resumeseason` | — | Persist season end / clear end override |

## DevConfig (Studio-only)

`src/ReplicatedStorage/Shared/Configs/DevConfig.luau` — applied only when `RunService:IsStudio()`:

| Flag | Default | Purpose |
|------|---------|---------|
| `SkipTutorial` | `false` | If `true`, mark tutorial complete on load |
| `StudioBoostCash` | `false` | Boost starting Cash to `StudioBoostCashAmount` |
| `FastPassiveIncome` | `false` | Passive tick every 1s |
| `UnlockAllVehicles` / `UnlockAllWeapons` | `false` | Grant all on load |
| `VerboseLogging` | `true` | Extra Bootstrap prints |
| `MockOwnedGamePasses` | `{}` | Treat listed GamePass keys as owned when Ids are still `0` |

## Monetization product IDs

All IDs are **0** placeholders in `MonetizationConfig.luau`. Create Developer Products / Game Passes in Creator Dashboard and replace IDs before shipping.

**Security:** Currency/XP are **never** granted from client purchase confirmation. DevProducts grant only in `MarketplaceService.ProcessReceipt` (idempotent via `ProcessedReceipts`). GamePass benefits apply only after `UserOwnsGamePassAsync` (cached on join); `PromptGamePassPurchaseFinished` refreshes the cache only.

| GamePass key | Effect |
|--------------|--------|
| `VIP` | +25% Cash earnings (`CashBonusMult`) |
| `DoubleCash` | 2× Cash earnings (`CashMult`) |
| `DoubleXP` | 2× XP (`XPMult`) |
| `ExtraPlotCosmetic` | Cosmetic placeholder |

Shop UI: **P** / SHOP — prompts `PromptProductPurchase` / `PromptGamePassPurchase`.

## Security notes

- **No** `GiveCash` / `GiveXP` remotes. Currency and XP only change on the server.
- Client sends **requests** (`RequestPurchaseUpgrade`, etc.); server validates + rate-limits.
- DataService: DataStore + retries + autosave + `PlayerRemoving` + `BindToClose` + session lock + migrations.

## Project layout

See `MASTER_BUILD_SPEC.md` for the full architecture. Key paths:

- `src/ReplicatedStorage/Shared/Configs/` — all tunable configs
- `src/ServerScriptService/Server/` — Bootstrap + Services + Modules
- `src/StarterPlayer/.../Client/` — Bootstrap + Controllers (programmatic UI)
- `tools/StudioSetup.luau` — map / bases / territories / NPC / vehicle / tutorial markers
- `tools/SmokeTest.luau` — Play Solo command-bar smoke (remotes / configs / services; no currency exploits)

## Docs

- `ASSUMPTIONS.md` — engineering decisions made for this build
- `BALANCE.md` — economy / XP tuning notes
- `MASTER_BUILD_SPEC.md` — product + technical spec

## Keybinds (MVP)

| Key / UI | Action |
|----------|--------|
| **B** / Base Upgrades (big bottom button) | Opens upgrade menu — tap **BUY $price** to purchase |
| **E** near pads | ProximityPrompt: Open Base / Upgrade / Garage / capture ping |
| **G** / GARAGE | Vehicle garage (buy / spawn / despawn) |
| **M** / MISSIONS | Daily missions + login claim |
| **P** / SHOP | DevProducts + GamePasses |
| **K** / PROGRESS | Prestige + Battle Pass + Clan + Clan War declare / scoreboard |
| **A** / ARMY | Recruit / dismiss / fill-cap soldiers |
| **O** / SETTINGS | Music/SFX local toggles (wires AudioController mute) + keybind cheat-sheet |
| LMB / FIRE | Fire equipped weapon |
| **R** | Reload |

## Playtest checklist (Studio)

1. **Setup** — Rojo sync → run `tools/StudioSetup.luau` once (Edit mode) → enable API Services if testing DataStores.
2. **Smoke** — Press Play Solo, then paste `tools/SmokeTest.luau` into the **Command Bar**. Confirms Remotes (no `Give*`), Shared configs, service modules, optional `GetPlayerState`, and a **safe** admin probe only if your UserId is in `AdminConfig` (never grants currency from smoke).
3. **Join** — Spawn with ~$5,000; HUD shows Cash / Gold / Level / XP; plot assigned.
4. **Tutorial** — Steps: claim base → Command Center → income → Barracks → Jeep → outpost; **SKIP** works; gold beam/markers best-effort.
5. **Tycoon** — Open Base Upgrades (**B** / bottom button / **E** on pad), then tap **BUY $1500** on Command Center (first row); Barracks next; passive income; structures recolor. Pads are not buy buttons.
6. **Combat** — Equip StarterRifle; LMB fire; **R** reload; damage NPCs; kill rewards; death → respawn at base.
7. **Vehicles** — **G**: SPAWN Military Jeep; seat/drive placeholder; despawn / one-active rule. Empty catalog / no-owned shows `UIUtil.EmptyState` (MobileScale consistent).
8. **Territory** — Stand in capture zone; progress bar; ownership bonus; `FIRST_OUTPOST` path.
9. **Missions** — **M**: daily objectives progress; claim rewards; daily login claim. Empty list shows a friendly empty state.
10. **Shop** — **P**: list products/passes; with Id `0`, warn/notify only (no fake grants). With real Ids, ProcessReceipt / ownership only.
11. **VIP / 2x** — Set `DevConfig.MockOwnedGamePasses` or admin `grantpass VIP` / `DoubleCash` / `DoubleXP`; confirm Cash/XP multipliers on earnings (not on `devproduct` grants).
12. **Persistence** — Leave + rejoin with API Services on; Cash/upgrades restore; receipts not double-granted.
13. **Admin** — `givecash` / `resettutorial` / `unlockall` / `bpxp` / `grantpremium` / `createclan` only for `AdminConfig.UserIds`.
14. **Progression (K)** — Battle Pass claimable counts + CLAIM ALL; create/join clan; with API Services on, leave/rejoin and confirm clan roster persists.
15. **Settings (O)** — Music/SFX local-only toggles mute/unmute `AudioController` immediately + keybind cheat-sheet (B/G/M/P/K/A/O + combat). Placeholder SoundIds — swap in Studio.

## Phase notes

### Phase 3 — Combat

- Server-authoritative: `CombatService` validates weapon ownership, fire rate, magazine, range; **never trusts client damage**.
- Remotes (request-only): `RequestFire`, `RequestReload`, `RequestEquipWeapon`, `RequestPurchaseWeapon` — **no GiveWeapon**.
- NPCs: spawn from `WE_NPCSpawn` markers; capped pool; light aggro/shoot AI; rewards on kill.

### Phase 4 — Vehicles

- Garage UI (`G`): MVP vehicles from `VehicleConfig`; BUY / SPAWN / DESPAWN.
- Server validates ownership, level, structure requirements, cash, spawn cooldown.
- Placeholder chassis + `VehicleSeat` near `WE_VehicleSpawn` or base plot.

### Phase 5 — Territory

- `TerritoryService`: 7 territories; Neutral/Player/NPC/Clan/Contested.
- Stand-in-zone capture; markers `WE_Territory` + `WE_CaptureZone` via StudioSetup.
- Ownership bonuses on passive income, XP, damage, vehicle cooldown, mission cash.

### Phase 6 — Progression

- Daily objective missions + 7-day login (**M**).
- Achievements: FirstUpgrade, Cash10k, Level10.

### Phase 7 — Monetization + polish

- `ProcessReceipt` idempotent + `ProcessedReceipts`.
- GamePass ownership cached on join; VIP / 2x Cash / 2x XP hooks in `EconomyService` / `XPService`.
- Interactive `TutorialController` + `TutorialService`; notification toast polish; StudioSetup tutorial markers.


### Prestige / Clan / Battle Pass (post–Phase 7)

- **Prestige:** Level 100+; resets progression currency/levels/base; keeps vehicles/weapons/gold; +Gold; cash mult via `EconomyConfig.PrestigeCashMultiplierPerLevel`.
- **Clans:** Create/join/leave (**K**); roster persisted in DataStore `WarEmpire_Clans_v1` (name, owner, members) when Studio API Services are on; session-only fallback otherwise. `profile.ClanId` stamped onto captured territories for clan ownership checks.
- **Army:** Recruit/dismiss soldiers (**A**); barracks upgrades raise cap; server cash spend only.
- **Seasons:** Active season XP/Cash multipliers via SeasonService (DataStore-persisted end; HUD indicator).
- **Clan wars:** Declare (leader, min members, cooldown), score on captures, settle rewards + scoreboard (**K**).
- **Radar Hill:** Enemy highlight within radius while owned.
- **Battle Pass:** Dense Free/Premium tracks (L1–50) from `BattlePassConfig`; XP from gameplay; **K** panel shows claimable counts + track preview; CLAIM ALL Free/Premium (server ClaimAll). Premium via admin `grantpremium` or shop `PremiumPass` DevProduct (Id `0` → ProcessReceipt grants when live). **Never** client-granted.


### Phase 7 polish
- Module splits for Combat / Territory / Progression
- DataVersion 3 migrations (clan / BP / soldiers / prestige)
- Perf: tag cache, idle skips, client debounce
- Remote validation audit (`RemoteGuard` + RateLimit on all Request*)
- Settings panel (O) + empty states; `tools/SmokeTest.luau`
- World ProximityPrompts (`WorldPromptController`) on tagged pads; StudioSetup visual polish (Grass/Metal/Concrete, neon edges, billboards, beacons)
- First-join toast: open Base Upgrades then tap BUY (pads are markers)
