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

## Vehicles (~99 — Ground 47 / Air 27 / Naval 25)

Deep unlock ladder (level + structure + cash; late units also prestige / rebirth flags).
~99 units after depth pass 3 (target band 85–100). Full table in `VehicleConfig.luau` — summary curve:

| Band | Levels | Examples | Structure |
|------|--------|----------|-----------|
| Early ground | 1–7 | Jeep, Quad, Scout, Trucks, Tanker, Dispatch | Depot L1–2 |
| Mid armor | 8–14 | APC, IFV, Light Tank, SPAAG, Amphib APC, Howitzer | Depot L3–4 |
| Late ground | 15–24 | Heavy/Battle/Fortress Tank, Rocket Arty, Railgun, SAM | Depot L4–5 + P/Rebirth |
| Air | 10–26 | Scout/Transport/Attack heli, Jets, Stealth Strike, Strategic Bomber | Helipad / Airfield |
| Naval | 5–26 | Cutter → Patrol → Gunboat → Landing → Sub → Carrier | Dock L1–5 |

**Progression curve notes**
- Cash costs ~3.5k early → ~720k legendary Fleet Carrier / Strategic Bomber.
- Structure gates: Depot / Helipad / Airfield / Dock levels 1–5 (existing BaseConfig curves).
- Prestige / rebirth gates (examples): Fortress Tank P7; Railgun Carrier EmpireElite; Stealth Strike P5; Strategic Bomber StrikeWing; Attack Sub P4; Missile Cruiser P8; Fleet Carrier EmpireFleet P15; Super Heavy / Battleship / Heavy Bomber as before.
- KitFamily (`WheeledLight` … `NavalSub`) keeps garage spawn kits scalable; no VehicleService rewrite.
- Garage: category + rarity filters; soft cooldown refresh for large lists.

**Dock** structure: costs 4.5k / 18k / 65k / 190k / 520k (VehicleDepot L2 prereq).

## Map scale (~4800)

- Ground **4800** studs; plot ring **~800**; plot pads **200**; structure gap **42**.
- Territories / oil / forts / bank / naval coast spread across larger map.
- Radar reveal **550**; billboard MaxDistance **~900**; void fallback plate **5000**.

## Prestige / Rebirth

- First prestige at **Level ≥ 40** (`MinLevelToPrestige`; was 100 — reversible, ASSUMPTIONS #108).
- Training + structure passive → **PendingCash** (Money Collector / AutoCollect).
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

Capture times 20–50s (Home Outpost 10 s). Max personal territories: **6** (`TerritoryConfig.MaxPersonalTerritories`). Protection: **45s**.

### Empire Tax (owner's 11 features, F3 / F10)

Config: `EconomyConfig.OutpostIncomeBuff`, `TerritoryConfig.Starter`. Server only (`EconomyService.EmpireTaxPct`); the HUD chip only shows `WE_EmpireTaxPct`.

| Source | Empire Tax | Notes |
|--------|-----------|-------|
| Each captured outpost you hold | **+10%** | One stack per zone; the Home Outpost is never a stack and never counts toward the zone cap (`MaxPersonalTerritories = 6`). |
| Your own Home Outpost | **+5%** | One per plot, about 100 studs out of your gate; only you can take it (10 s); no guards, no stipend, never stolen, evicted or nuked. |
| Total cap | **+50%** | `MaxStacks 5 × 10%`. |

- Applies to every cash reason that is not exempt (`MonetizationConfig.CashMultExemptReasons` plus EconomyService's never-multiplied list): passive and business income, training, missions, stipends. Exempt: the ATM `collector` (already multiplied when it accrued), `plot_oil`, Robux, admin, refunds, rebirth, battle pass, codes, spinner, supply drops, bank raid, clan war, the manual drop and ATM raids.
- Multiplies with prestige (+10% per rebirth), VIP / 2x Cash and the season.
- Persists across servers (`PersistClaims = true`): saved claims are re-planted on join onto Neutral or NPC-held zones, dropped when another online player holds the zone, released when you leave. Losing a zone drops the %.
- Rebirth keeps Empire Tax (outposts are not reset).

## Daily missions (Phase 6)

See `MissionConfig.DailyMissions` — Kill NPC ×10, Capture ×1, Upgrade ×2, Earn $8k, Spawn vehicle, Kill players ×3 (L5+).


## Phase 7 polish notes (early-game)

- Starting $5,000 covers Command Center ($1,500) with runway for Barracks ($2,500).
- Soldier recruit $500 each; barracks levels raise army cap (base 50 + 5/level) — intentional mid sink without blocking tycoon loop.
- Season XP×1.1 / Cash×1.05 while active; multipliers clear when season ends (persisted).
- Clan war win $25k + gold + score bonus; participation $2.5k + 2G; declare cooldown 300s after settle.
- Radar Hill: real client Highlight on nearby enemies (not a stub description).
- Do not radical-retune structure curves without playtest; prefer EconomyConfig / SoldierConfig / ClanWarConfig knobs.

## War businesses (v72, proposal pending owner sign-off)

Config: `BusinessConfig` (numbers, kit, visuals), `TycoonGuideConfig` (next-buy pick, copy), `Shared/Util/TycoonMath` (the one formula for what is paid and what is shown). Both `Enabled` flags stay **false** until integration; while off nothing below exists in game and the economy is exactly as before v72.

- Four production lines on your own plot, bought and upgraded only at their own kiosk (console-only buying, same purchase path as every structure; levels save in `profile.BaseUpgrades`).
- Income is part of the normal passive tick: every 5 s into the ATM (reason `passive`), so prestige, territory, season, VIP and outpost multipliers apply and ATM raids take 10% as usual. No new money path and no remote.
- Rebirth resets businesses like any structure.

| Business | Short | Requires | Cost L1–L5 | Income per tick L1–L5 (×1, total) |
|---|---|---|---|---|
| Ammo Works | AMMO | — | 600 / 2,000 / 6,000 / 18,000 / 55,000 | 16 / 36 / 70 / 125 / 200 |
| Arms Crate Line | ARMS | Ammo Works 1 + Weapons Facility 1 | 2,000 / 6,500 / 19,000 / 57,000 / 170,000 | 40 / 85 / 160 / 280 / 450 |
| Armor Plate Press | ARMOR | Command Center 2 + Arms Crate Line 2 | 8,000 / 25,000 / 75,000 / 220,000 / 650,000 | 120 / 220 / 360 / 580 / 860 |
| Rocket Assembly | ROCKETS | Command Center 3 + Armor Plate Press 2 | 30,000 / 90,000 / 270,000 / 800,000 / 2,400,000 | 260 / 440 / 700 / 1,050 / 1,500 |

What a level adds, as shown in game at the ×1.05 season (floored) and its payback:

| Business | L1 | L2 | L3 | L4 | L5 |
|---|---|---|---|---|---|
| Ammo Works | +$3.3/s, 3.0 min | +$4.2/s, 7.9 min | +$7.1/s, 14 min | +$11/s, 26 min | +$15/s, 58 min |
| Arms Crate Line | +$8.4/s, 4.0 min | +$9.4/s, 11.5 min | +$15/s, 20 min | +$25/s, 38 min | +$35/s, 79 min |
| Armor Plate Press | +$25/s, 5.3 min | +$21/s, 20 min | +$29/s, 43 min | +$46/s, 79 min | +$58/s, 184 min |
| Rocket Assembly | +$54/s, 9.2 min | +$37/s, 40 min | +$54/s, 82 min | +$73/s, 181 min | +$94/s, 423 min |

- **Weapons Facility** now gates the Arms Crate Line (description "Arms storage. Unlocks the Arms Crate Line.").
- **Tutorial step 6** is the Ammo Works buy (was Barracks); Barracks is the last entry of the guide's opening.
- **Armor Plate Press income** is 1.2× the v72 spec draft (100 / 180 / 300 / 480 / 720): with the 34% soldier-share rule the guided run earned 274 $/s at 30 min, under the 280–380 target. Revert = those five numbers in `BusinessConfig`.

### Next-buy guide (`TycoonGuideConfig`)

- The server picks one next buy per player and stamps it as `WE_NextBuy` (the pick is advice; the server re-checks every buy).
- Opening: Command Center 1, Ammo Works 1, Weapons Facility 1, Arms Crate Line 1, Barracks 1 (the first one still open wins).
- After that the lowest score wins: seconds until affordable (wallet + ATM) + cost ÷ ((income gain + unlock value) per second). A challenger must score below 0.75× the current pick; re-pick every 15 s and after a buy, an army change, plot ready and profile load.
- Soldiers ($500, +8 per tick each) are offered only while training income is below 34% of total base income.
- Shown rates are floored (one decimal below $10/s, whole dollars above), so the game never over-promises.

### Headless economy sim (Python model of the config numbers, not Roblox; start $10,000 and 5 soldiers, ×1.05 season, walking at 16 studs/s)

| Run | $/s at 10 / 30 / 60 min | Longest wait, buys done by 10:00 |
|---|---|---|
| C: guided, consoles only | 60 / 177 / 346 | 141 s (Arms Crate Line L2 at 6:58) |
| D: guided + soldiers (no share rule, as the prototype sim) | 144 / 353 / 531 | 63 s |
| D: guided + soldiers with the 34% share rule (as shipped) | 79 / 295 / 531 | 115 s |

With the spec-draft Armor numbers, run D gave 344 / 533 (no share rule) and 274 / 472 (share rule) $/s at 30 / 60 min. Run C's 141 s wait comes before the Armor Press unlocks, so Armor or Rocket numbers cannot change it; it is open for the owner and lead.
