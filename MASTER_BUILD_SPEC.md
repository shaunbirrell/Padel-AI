# WAR EMPIRE — Roblox MVP Build Spec

**Tagline:** BUILD. CONQUER. DOMINATE.

Commercial Roblox multiplayer military tycoon / PvP / territory-control / vehicle-collection game.

## Goal for this cloud agent run

Build a **Rojo-ready Luau project** for Roblox Studio that implements **Phase 1 (Foundation) fully** and **Phase 2 (Tycoon) fully**, with stub/scaffold modules and configs for later MVP phases so the architecture is expandable without rewrites.

Deliver a playable foundation: player joins → gets profile + base plot assignment → sees Cash/Gold/XP/Level HUD → can purchase base upgrades (server-validated) → earns passive income → data autosaves.

Then continue as far as reasonable into Phase 3–6 scaffolding (configs + service stubs + secure remotes) without blocking on unfinished 3D art.

## Tech stack

- Luau modules (`.luau` or `.lua` as Rojo expects)
- Rojo project (`default.project.json`) mapping to Roblox services
- Wally optional; prefer zero external deps unless clearly helpful
- NO pseudo-code: write real production Luau
- Server-authoritative everything for currency, XP, upgrades, ownership

## Folder architecture (Rojo)

```
src/
  ReplicatedStorage/
    Shared/
      Configs/
        GameConfig.luau
        EconomyConfig.luau
        BaseConfig.luau
        WeaponConfig.luau
        VehicleConfig.luau
        SoldierConfig.luau
        MissionConfig.luau
        LevelConfig.luau
        PrestigeConfig.luau
        TerritoryConfig.luau
        SeasonConfig.luau
        MonetizationConfig.luau
        AchievementConfig.luau
        DailyRewardConfig.luau
        BattlePassConfig.luau
        NotificationConfig.luau
        AnalyticsConfig.luau
        AdminConfig.luau
        DevConfig.luau
      Constants.luau
      Types.luau
      Remotes.luau  -- or create remotes folder via bootstrap
    Remotes/  -- created at runtime by Remotes bootstrap if needed
  ServerScriptService/
    Server/
      Bootstrap.server.luau
      Services/
        DataService.luau
        EconomyService.luau
        BaseService.luau
        XPService.luau
        CombatService.luau
        VehicleService.luau
        TerritoryService.luau
        MissionService.luau
        PrestigeService.luau
        ClanService.luau
        MonetizationService.luau
        AnalyticsService.luau
        NotificationService.luau
        AntiExploitService.luau
        AdminService.luau
        RateLimitService.luau
      Modules/
        ProfileSchema.luau
        RemoteSetup.luau
        SessionLock.luau
  StarterPlayer/
    StarterPlayerScripts/
      Client/
        Bootstrap.client.luau
        Controllers/
          UIController.luau
          HUDController.luau
          BaseController.luau
          CombatController.luau
          VehicleController.luau
          TutorialController.luau
          NotificationController.luau
  StarterGui/
    -- Prefer creating ScreenGuis in code OR include rbxmx if needed;
    -- Prefer programmatic UI in controllers for MVP reliability
```

Also include:
- `README.md` — how to open with Rojo / Studio, product ID placeholders, admin UserIds
- `aftman.toml` or note Rojo version if useful
- Studio command-bar / bootstrap script that creates Workspace folders: Map, Bases (6 plots), Territories (7), VehicleSpawns, NPCSpawns, EventSpawns if Rojo can't create Parts easily — provide `tools/StudioSetup.luau` pasteable into Studio command bar to create placeholder map + base plots + territory markers

## Starting player profile (server defaults)

- Cash: 5000
- Gold: 0
- Level: 1
- XP: 0
- Prestige: 0
- Soldiers: 5
- Vehicles owned: `MilitaryJeep`
- Weapons owned: `StarterRifle`
- Territories: {}
- Base upgrades: all level 0 except perhaps CommandCenter unlocked after tutorial build
- TutorialStep / TutorialComplete
- DailyLogin streak fields
- Settings, stats, achievements, battlePass stubs
- ClanId: nil
- DataVersion for migrations

## Phase 1 — MUST IMPLEMENT (complete, working)

1. **Project structure** as above with Rojo `default.project.json`
2. **ProfileSchema** + **DataService**
   - DataStoreService with pcall, retries, autosave interval, PlayerRemoving, BindToClose
   - Session protection (simple session token / load lock pattern)
   - Data versioning + migration hook
   - Never trust client for save payload
3. **EconomyService**
   - Server-only AddCash/SpendCash/AddGold/SpendGold
   - Validation, insufficient funds errors
   - Fire client updates via secure remotes (server pushes state; client never sets currency)
4. **Base assignment**
   - 6 base plots conceptually; assign first free plot on join; release on leave
   - Placeholder plot positions in config + StudioSetup script creates Parts tagged with CollectionService
5. **Secure Remotes**
   - NO GiveCash / GiveXP remotes
   - Request pattern: client requests action (e.g. PurchaseUpgrade), server validates and applies
   - RateLimitService on remotes
6. **Configs** for economy, game, base (upgrade trees with costs for Command Center, Barracks, Vehicle Depot, Weapons Facility, Helipad, Airfield, Defensive Walls, Watchtowers, Radar, Research Lab, Missile Defense, Power Station, Warehouse, Special Forces Facility — at least 5 levels each with escalating costs matching the spec style)
7. **HUD** (programmatic ScreenGui)
   - Top left: Level + XP bar
   - Top right: Cash + Gold
   - Dark military theme (black/charcoal/gunmetal/white)
   - Responsive scale (UIScale / Scale constraints) for mobile
8. **AnalyticsService** abstraction with events: PLAYER_JOIN, FIRST_UPGRADE, etc. — fire to print/log for MVP; structure so a real backend can plug in later. Do not fabricate metrics.
9. **DevConfig / Test mode**
   - Studio-only flags: boost cash, skip tutorial, unlock vehicles, etc.
   - Separate from production (check RunService:IsStudio())
10. **AdminService** — UserId allowlist in AdminConfig; server-only commands

## Phase 2 — MUST IMPLEMENT

1. BaseService: purchase upgrades with EconomyService, persist levels, fire visual update events
2. Passive income tick based on base upgrades + config rates
3. Visual placeholders: when upgrade level changes, resize/recolor placeholder Parts in the player's base plot (StudioSetup creates upgrade slot Parts)
4. Client BaseController: upgrade menu UI listing structures/levels/costs, purchase button → remote request

## Phase 3–7 — Scaffold thoroughly

- Full **WeaponConfig** (Assault rifle, SMG, Sniper, Shotgun, Rocket launcher, Pistol, Grenade + StarterRifle) with damage, fireRate, mag, reload, range, spread, rarity, level
- Full **VehicleConfig** MVP 8 vehicles with rarities and unlock levels as specified:
  1. Military Jeep — Common — L1
  2. Armed Jeep — Common — L3
  3. Armored Truck — Uncommon — L5
  4. APC — Rare — L8
  5. Light Tank — Rare — L12
  6. Heavy Tank — Epic — L15
  7. Attack Helicopter — Epic — L18
  8. Fighter Jet — Legendary — L20
- LevelConfig: at least 20 levels with XP thresholds + rewards (extend table to 100 levels with formula if needed)
- TerritoryConfig: 7 territories with bonuses from spec
- MissionConfig, DailyRewardConfig (7-day), MonetizationConfig (GamePasses + DevProducts with placeholder IDs = 0), AchievementConfig
- Service stubs with clear TODO and public API signatures for Combat, Vehicle, Territory, Mission, Prestige, Clan, Monetization (receipt handler skeleton with ProcessReceipt pattern)
- AntiExploitService basics (rate limits, sanity checks)

## Economy balance (document in EconomyConfig comments or BALANCE.md)

First 10 minutes fast; later slower. Example Barracks costs from spec. Starting cash 5000. Passive income should allow first meaningful upgrade within ~1 minute.

## Security rules (non-negotiable)

- Client untrusted
- Server validates purchases, currency, upgrades, ownership
- Rate limiting on remotes
- Marketplace receipt granting server-authoritative and idempotent (skeleton OK)

## Deliverables checklist

- [ ] Rojo project builds / maps correctly
- [ ] All Phase 1+2 Luau modules present and require-able
- [ ] README with setup steps (Rojo serve, Studio plugin, paste StudioSetup, set admin UserIds, product IDs)
- [ ] StudioSetup command-bar script for map/base/territory placeholders
- [ ] No Give* remotes
- [ ] DataService saves on leave + autosave + BindToClose
- [ ] HUD updates from server state pushes
- [ ] Luau type annotations where helpful (`--!strict` on core modules if practical)

## Success criteria

A developer can:
1. Clone / open the Origin repo
2. Run Rojo into a blank place
3. Paste StudioSetup once
4. Play in Studio: spawn with $5000, see HUD, buy Command Center / Barracks, watch cash tick up, leave and rejoin with data restored (Studio DataStore API services enabled)

## Do NOT

- Ask the user clarifying questions for minor details — make reversible engineering assumptions and document them in ASSUMPTIONS.md
- Stop after Phase 1 instructions — implement Phase 1+2 code completely
- Use copyrighted real-world vehicle brand names
- Implement loot boxes with random rewards beyond a transparent stub marked policy-pending
- Fabricate that Studio playtests ran if they cannot run in the cloud VM — mark TESTING as static analysis / require graph checks / luau syntax review

## Report back

When done, summarize:
COMPLETED / FILES (key paths) / TESTING (what actually verified) / NEXT (Phase 3 recommendations)
