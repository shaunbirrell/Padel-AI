# WAR EMPIRE

**BUILD. CONQUER. DOMINATE.**

Commercial Roblox military tycoon / territory / vehicle collection game.  
Rojo-ready Luau codebase — Phase 1–4 implemented (Foundation, Tycoon, Combat, Vehicles); later systems scaffolded.

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

Join → profile load → plot assigned → HUD shows Cash/Gold/Level/XP → buy Command Center / Barracks → passive income ticks → **combat**: equip StarterRifle, fire (LMB / mobile FIRE), reload (R), fight NPCs / PvP → kill rewards → respawn at base → data autosaves / saves on leave.

## Phase 4 — Vehicles notes

- Garage UI (`G` / GARAGE button): list MVP 8 vehicles from `VehicleConfig`, BUY / SPAWN / DESPAWN.
- Server `VehicleService` validates ownership, level, structure requirements, cash, spawn cooldown.
- Spawn creates placeholder chassis + `VehicleSeat` near `WE_VehicleSpawn` or base plot.
- Remotes: `RequestSpawnVehicle`, `RequestPurchaseVehicle`, `RequestDespawnVehicle`, `VehicleStateUpdate`.
- One active vehicle per player; despawn on leave.

## Phase 3 — Combat notes

- Server-authoritative: `CombatService` validates weapon ownership, fire rate, magazine, range; **never trusts client damage**.
- Remotes (request-only): `RequestFire`, `RequestReload`, `RequestEquipWeapon`, `RequestPurchaseWeapon` — **no GiveWeapon**.
- NPCs: spawn from `WE_NPCSpawn` markers (+ optional territory pads); capped pool; light aggro/shoot AI; rewards on kill.
- Client: `CombatController` health bar, ammo/weapon strip, mobile fire button, hit flash.
- Analytics: `FIRST_PVP`, `PLAYER_KILL`, `NPC_KILL`, `WEAPON_EQUIPPED`, `WEAPON_PURCHASED`.
- Tunables: `CombatConfig.luau` + `WeaponConfig.luau`.
