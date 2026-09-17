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

## Vehicles (MVP 8)

| Vehicle            | Rarity    | Unlock Lv |
|--------------------|-----------|-----------|
| Military Jeep      | Common    | 1         |
| Armed Jeep         | Common    | 3         |
| Armored Truck      | Uncommon  | 5         |
| APC                | Rare      | 8         |
| Light Tank         | Rare      | 12        |
| Heavy Tank         | Epic      | 15        |
| Attack Helicopter  | Epic      | 18        |
| Fighter Jet        | Legendary | 20        |

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
