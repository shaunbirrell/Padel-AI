# BALANCE — WAR EMPIRE MVP

## Goals

- First **10 minutes** feel fast and rewarding.
- First meaningful upgrade within ~**1 minute**.
- Mid/late game slows via escalating structure costs.

## Starting economy

| Stat   | Value |
|--------|-------|
| Cash   | 5,000 |
| Gold   | 0     |
| Level  | 1     |
| Soldiers | 5   |

## Passive income

- Tick: **5 seconds**
- Base: **$25 / tick** (~$300 / min with no buildings)
- Plus per structure level (examples): Barracks +20, Warehouse +25, Command Center +15

With Command Center L1 + Barracks L1 ≈ $25 + $15 + $20 = **$60 / tick** (~$720 / min).

## Barracks costs (spec)

| Level | Cost    |
|-------|---------|
| 1     | 2,500   |
| 2     | 10,000  |
| 3     | 35,000  |
| 4     | 100,000 |
| 5     | 300,000 |

Other structures use similar curves (see `BaseConfig.luau`). Command Center L1 is **$1,500** so players can buy it immediately from starting cash.

## XP

- To advance from level L: `floor(100 * L^1.45)`
- Level-up reward: `$500 + 150*newLevel` cash; gold every 5 levels

## Vehicles (~67 — Ground 34 / Air 17 / Naval 16)

Deep unlock ladder (level + structure + cash; late units also prestige / rebirth flags).
~67 units after depth pass 2 (toward 80–100). Full table in `VehicleConfig.luau` — summary curve:

| Band | Levels | Examples | Structure |
|------|--------|----------|-----------|
| Early ground | 1–7 | Jeep, Quad, Scout, Trucks, Tanker | Depot L1–2 |
| Mid armor | 8–13 | APC, IFV, Light Tank, SPAAG, Mortar | Depot L3–4 |
| Late ground | 14–22 | Medium/Heavy/Battle Tank, Rocket Arty, Super Heavy | Depot L4–5 + P/Rebirth |
| Air | 10–25 | Scout/Transport/Attack heli, Jets, Bombers | Helipad / Airfield |
| Naval | 6–25 | Patrol → Gunboat → Landing → Destroyer → Battleship | Dock L1–5 |

**Progression curve notes**
- Cash costs ~3.5k early → ~650k legendary capital ships / bombers.
- Structure gates: Depot / Helipad / Airfield / Dock levels 1–5 (existing BaseConfig curves).
- Rebirth gates: Super Heavy (EmpireElite P10), Battleship (EmpireFleet P12), Heavy Bomber (StrikeWing P20). Cruiser needs Prestige ≥2.
- KitFamily (`WheeledLight` … `NavalSub`) lets roster grow toward 100 without VehicleService rewrite.
- Garage: category + rarity filters; soft cooldown refresh for large lists.

**Dock** structure: costs 4.5k / 18k / 65k / 190k / 520k (VehicleDepot L2 prereq).

## Map scale (~4800)

- Ground **4800** studs; plot ring **~800**; plot pads **200**; structure gap **42**.
- Territories / oil / forts / bank / naval coast spread across larger map.
- Radar reveal **550**; billboard MaxDistance **~900**; void fallback plate **5000**.

## Prestige / Rebirth

- +**10%** cash earnings per prestige (stacking; P10 = +100%).
- Unlock track: ScoutCar / PatrolBoat / SupplyTruck / MissileBoat / TransportHeli / Gunboat / AssaultIFV / EmpireElite / EmpireFleet / Destroyer / Cruiser / StrikeJet(+HeavyBomber gate) — see `PrestigeConfig.RebirthUnlocks`.
- Cash stack: prestige → VIP/DoubleCash → season (exempt reasons skip VIP/season).

## Tuning knobs

Edit `EconomyConfig`, `BaseConfig`, `LevelConfig` — keep combat/vehicle numbers in their configs. Document live changes here after playtests.


## Combat (Phase 3)

| Source | Cash | XP |
|--------|------|-----|
| Player kill | 150 | 40 |
| NPC Infantry | 50 | 15 |
| NPC Heavy Infantry | 90 | 28 |

Player max health: **100**. Spawn invuln: **3s**. Tune in `CombatConfig` / `WeaponConfig`.

## Territory (Phase 5)

| Territory | Bonus |
|-----------|-------|
| Central Plaza | +10% passive cash |
| North Ridge | +5% XP |
| South Docks | +15% mission cash |
| East Armory | +10% damage |
| West Depot | −20% vehicle spawn cooldown |
| Oil Fields | +$50 / passive tick |
| Radar Hill | Minimap reveal (stub) |

Capture times 20–40s. Max personal territories: **3**. Protection: **45s**.

## Daily missions (Phase 6)

See `MissionConfig.DailyMissions` — Kill NPC ×10, Capture ×1, Upgrade ×2, Earn $8k, Spawn vehicle, Kill players ×3 (L5+).


## Phase 7 polish notes (early-game)

- Starting $5,000 covers Command Center ($1,500) with runway for Barracks ($2,500).
- Soldier recruit $500 each; barracks levels raise army cap (base 50 + 5/level) — intentional mid sink without blocking tycoon loop.
- Season XP×1.1 / Cash×1.05 while active; multipliers clear when season ends (persisted).
- Clan war win $25k + gold + score bonus; participation $2.5k + 2G; declare cooldown 300s after settle.
- Radar Hill: real client Highlight on nearby enemies (not a stub description).
- Do not radical-retune structure curves without playtest; prefer EconomyConfig / SoldierConfig / ClanWarConfig knobs.
