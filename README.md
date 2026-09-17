# WAR EMPIRE

**BUILD. CONQUER. DOMINATE.**

Commercial Roblox military tycoon / territory / vehicle collection game.  
Rojo-ready Luau codebase — Phase 1 (Foundation) + Phase 2 (Tycoon) implemented; later systems scaffolded.

## Requirements

- [Rojo](https://rojo.space/) 7.4+ (see `aftman.toml`)
- Roblox Studio with Rojo plugin
- Enable **Studio Access to API Services** for DataStore testing (Game Settings → Security)

## Quick start

1. Open a blank Baseplate place in Roblox Studio.
2. From this folder: `rojo serve` (or `aftman install` then `rojo serve`).
3. In Studio, connect the Rojo plugin and sync.
4. Paste contents of `tools/StudioSetup.luau` into the **Command Bar** and run once.
5. Press Play. You should spawn with **$5,000**, see the HUD, open **Base Upgrades** (or press **B**), buy structures, and earn passive income.

## Admin UserIds

Edit `src/ReplicatedStorage/Shared/Configs/AdminConfig.luau`:

```lua
UserIds = {
  123456789, -- your UserId
},
```

Admin remotes: `RequestAdminCommand` with commands `givecash`, `givegold`, `givexp`, `setlevel`, `unlockall`, `resetbase`.

## Monetization product IDs

All IDs are **0** placeholders in `MonetizationConfig.luau`. Create Developer Products / Game Passes in Creator Dashboard and replace IDs before shipping.

## Security notes

- **No** `GiveCash` / `GiveXP` remotes. Currency and XP only change on the server.
- Client sends **requests** (`RequestPurchaseUpgrade`, etc.); server validates + rate-limits.
- DataService: DataStore + retries + autosave + `PlayerRemoving` + `BindToClose` + session lock + migrations.

## Project layout

See `MASTER_BUILD_SPEC.md` for the full architecture. Key paths:

- `src/ReplicatedStorage/Shared/Configs/` — all tunable configs
- `src/ServerScriptService/Server/` — Bootstrap + Services + Modules
- `src/StarterPlayer/.../Client/` — Bootstrap + Controllers (programmatic UI)
- `tools/StudioSetup.luau` — map / bases / territories placeholders

## Docs

- `ASSUMPTIONS.md` — engineering decisions made for this build
- `BALANCE.md` — economy / XP tuning notes
- `MASTER_BUILD_SPEC.md` — product + technical spec

## Play loop (MVP)

Join → profile load → plot assigned → HUD shows Cash/Gold/Level/XP → buy Command Center / Barracks → passive income ticks → data autosaves / saves on leave.
