# WAR EMPIRE — Live place (created 2026-09-20)

- **Experience name:** **WAR EMPIRE**
- **Place ID:** `97112936860418`
- **Universe ID:** `10767159222`
- **Play URL:** https://www.roblox.com/games/97112936860418
- **Live Published:** Open Cloud **versionNumber=58** (2026-09-21 Europe/Madrid) — **INSTANT PROFILE / CASH-FIRST HUD**: DataService.LoadProfile CreateDefault+AdminPlaytestCash+stamp WE_Cash/WE_Gold/WE_Build=58 + fireProfileLoaded **before** any DataStore/session-lock yield (background GetAsync merge with math.max Cash; never Kick on lock); HUD/WorldPrompt connect EconomyUpdate+WE_Cash+leaderstats+poll **before** other remotes that WaitForChild-block; BaseService OnProfileLoaded `EconomyService.Push` first line; dense Push kept; no fake StartingCash HUD (`$…` until real attr/remote/leaderstats); StartingCash=10000; AdminPlaytestCash 50M for 470626172; DataStore **`WarEmpire_PlayerData_v2`**; PreferMesh OFF / KIT_GEN 32; `WE_Build=58`.
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
