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

## Vehicles (~19 — Ground / Air / Naval)

| Vehicle            | Cat   | Rarity    | Lv | Cost     | Structure     |
|--------------------|-------|-----------|----|----------|---------------|
| Military Jeep      | Ground| Common    | 1  | 0        | —             |
| Armed Jeep         | Ground| Common    | 3  | 8,000    | Depot L1      |
| Scout Car          | Ground| Common    | 4  | 12,000   | Depot L1      |
| Armored Truck      | Ground| Uncommon  | 5  | 20,000   | Depot L2      |
| Supply Truck       | Ground| Uncommon  | 6  | 28,000   | Depot L2      |
| Patrol Boat        | Naval | Uncommon  | 6  | 25,000   | Dock L1       |
| APC                | Ground| Rare      | 8  | 45,000   | Depot L3      |
| Infantry Carrier   | Ground| Rare      | 9  | 55,000   | Depot L3      |
| Gunboat            | Naval | Rare      | 10 | 70,000   | Dock L2       |
| Light Tank         | Ground| Rare      | 12 | 90,000   | Depot L4      |
| Landing Craft      | Naval | Rare      | 12 | 95,000   | Dock L3       |
| Medium Tank        | Ground| Epic      | 14 | 130,000  | Depot L4      |
| Transport Heli     | Air   | Rare      | 14 | 160,000  | Helipad L2    |
| Heavy Tank         | Ground| Epic      | 15 | 180,000  | Depot L5      |
| Mobile Artillery   | Ground| Epic      | 16 | 220,000  | Depot L5      |
| Destroyer          | Naval | Legendary | 17 | 280,000  | Dock L4       |
| Attack Helicopter  | Air   | Epic      | 18 | 250,000  | Helipad L3    |
| Strike Jet         | Air   | Epic      | 19 | 320,000  | Airfield L2   |
| Fighter Jet        | Air   | Legendary | 20 | 400,000  | Airfield L3   |

**Dock** structure: costs 4.5k / 18k / 65k / 190k / 520k (VehicleDepot L2 prereq).

## Prestige / Rebirth

- +**10%** cash earnings per prestige (stacking; P10 = +100%).
- Unlock track grants ScoutCar / PatrolBoat / SupplyTruck / TransportHeli / Gunboat / Destroyer / StrikeJet (and EmpireElite flag) at configured prestige tiers — see `PrestigeConfig.RebirthUnlocks`.
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
