# WAR EMPIRE — Live place (created 2026-09-20)

- **Experience name:** **WAR EMPIRE**
- **Place ID:** `97112936860418`
- **Universe ID:** `10767159222`
- **Play URL:** https://www.roblox.com/games/97112936860418
- **Live Published:** Open Cloud **versionNumber=41** (2026-09-20 Europe/Madrid) — DESIGN_FEATURE_WIRE_v40: BaseGate prop, vehicle uniqueness, Worker/SF, OilPumpjack, DefensiveWalls mesh=0; kits visible; KIT_GEN 27 / DressGen 28
- **API Services:** enabled (DataStores) — required for profiles/persistence; no code change in v31, confirm still on in Creator Dashboard → Security
- **Privacy:** Private (owner + friends / shared access only until set Public)
- **Devices:** Computer, Phone, Tablet enabled at create

## Product IDs (MonetizationConfig)

### GamePasses
| Key | Id | Robux |
|-----|-----|-------|
| VIP | 1985475542 | 199 |
| DoubleCash | 1982865711 | 149 |
| DoubleXP | 1982487698 | 99 |
| ExtraPlotCosmetic | 1983357731 | 79 |
| AutoCollect | 1985115501 | 99 |

### DevProducts
| Key | Id | Robux |
|-----|-----|-------|
| CashSmall | 3713838744 | 49 |
| CashMedium | 3713838815 | 149 |
| CashLarge | 3713838888 | 399 |
| CashMega (BEST OFFER) | 3713838952 | 799 |
| GoldSmall | 3713839003 | 49 |
| GoldMedium | 3713839048 | 149 |
| GoldLarge | 3713839090 | 349 |
| PremiumPass | 3713839151 | 499 |
| ExtraSoldierSlot | 3713839210 | 79 |
| InstantBarracks | 3713839278 | 129 |
| SpeedBoost | 3713839342 | 99 |
| StarterBundle | 3713839505 | 249 |
| GoldenPumpjack | 0 (pad hidden until Id) | 49 |

Duplicate DevProduct SKUs AutoCollect / DoubleCash / VIPBoost are **HideFromShop** (GamePasses cover them).

## After rename / for mobile

1. Creator Dashboard → experience → confirm name **WAR EMPIRE**.
2. Confirm **API Services** (DataStores) under Security / Configure.
3. On phone: open the Play URL while logged into the same Roblox account (`shaunie6`), or set Private → Friends if others join.

## Open Cloud republish

```bash
export ROBLOX_OPEN_CLOUD_API_KEY=...
export ROBLOX_UNIVERSE_ID=10767159222
export ROBLOX_PLACE_ID=97112936860418
./tools/publish-opencloud.sh
```
