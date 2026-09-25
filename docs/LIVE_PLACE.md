# WAR EMPIRE — Live place (created 2026-09-20)

- **Experience name:** **WAR EMPIRE**
- **Place ID:** `97112936860418`
- **Universe ID:** `10767159222`
- **Play URL:** https://www.roblox.com/games/97112936860418
- **Live Published:** Open Cloud **versionNumber=63** (2026-09-21 Europe/Madrid) — **v61 BUY PATH**: `Remotes.FireServer` (≤3s TryGet, no unbounded WaitForChild); WorldPrompt/BaseController toast "Buying…" only after FireServer; EnsureProfile on pad+PurchaseUpgrade; DataService Init before UpgradePad; `WE_Build=63`.
- **API Services:** enabled (DataStores) — required for profiles/persistence; no code change in v31, confirm still on in Creator Dashboard → Security
- **Privacy:** **Public** since 2026-09-24 17:54 UTC (develop API: privacyType Public, audiences Editors + Public). Under current Roblox rules, Private means only users with Edit permission can play.
- **Age / access:** rated "Mild, Ages 16+". Until the game passes Roblox's Kids/Select review, only age-checked players 16+ and the owner's Trusted Friends can join (create.roblox.com/docs/production/publishing/kids-and-select, checked 2026-09-23).
- **Devices:** Computer, Phone, Tablet enabled at create

## Product IDs (MonetizationConfig)

Source of truth: `src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau` (this table was re-read from it on
2026-09-25, owner's 11 features batch B). An Id of 0 means the product does not exist on the Creator Dashboard yet:
nothing prompts, no pad is built and the Shop row stays hidden until the Id is pasted
(`tools/wire-monetization-ids.py`). "Shop" says where the item is sold; "hidden" = `HideFromShop`.

### GamePasses
| Key | Name | Id | Robux | Shop |
|-----|------|-----|-------|------|
| VIP | VIP | 1985475542 | 199 | Shop row (no ATM pad) |
| DoubleCash | 2x Cash | 1982865711 | 149 | Shop + yellow ATM pad |
| DoubleXP | Double XP | 1982487698 | 99 | Shop |
| ExtraPlotCosmetic | Elite Base Theme | 1983357731 | 79 | hidden |
| AutoCollect | Auto Collect | 1985115501 | 99 | Shop + red ATM pad |
| ImpulseSpeed | Speed Pass | 0 (new, F8) | 5 | cyan ATM pad + one death offer per session, once the Id is live |
| PV_Razorfang | Razorfang GT Interceptor | 0 | 199 | hidden |
| PV_Bastion | Bastion Gun Truck | 0 | 399 | hidden |
| PV_Warlord | Warlord Siege Tank | 0 | 799 | hidden |
| PV_MotorPool | Premium Motor Pool | 0 | 1099 | hidden |
| PV_Stormwing | Stormwing Gunship | 0 | 999 | hidden |
| PV_Tidebreaker | Tidebreaker Assault Boat | 0 | 299 | hidden |
| RebirthBoost | Rebirth Boost | 0 | 199 | hidden |

### DevProducts
| Key | Name | Id | Robux | Shop |
|-----|------|-----|-------|------|
| CashSmall | Cash Pack S | 3713838744 | 49 | Shop |
| CashMedium | Cash Pack M | 3713838815 | 149 | Shop |
| CashLarge | Cash Pack L | 3713838888 | 399 | Shop |
| CashMega | Cash Pack Mega (BEST OFFER) | 3713838952 | 799 | Shop, first row |
| GoldSmall | Gold Pack S | 3713839003 | 49 | hidden |
| GoldMedium | Gold Pack M | 3713839048 | 149 | hidden |
| GoldLarge | Gold Pack L | 3713839090 | 349 | hidden |
| PremiumPass | Battle Pass Premium | 3713839151 | 499 | Shop |
| AutoCollect | Auto Collect | 0 | 99 | hidden (the GamePass covers it) |
| DoubleCash | 2x Money | 0 | 149 | hidden (the GamePass covers it) |
| ExtraSoldierSlot | Army Expansion (+10) | 3713839210 | 99 | Shop |
| InstantBarracks | Instant Barracks | 3713839278 | 129 | hidden |
| VIPBoost | VIP Boost | 0 | 199 | hidden (the GamePass covers it) |
| SpeedBoost | Speed Boost | 3713839342 | 99 | Shop; the cyan ATM pad sells it while ImpulseSpeed is 0 |
| GoldenPumpjack | Golden Pumpjacks | 0 (F9) | 49 | Shop row + one gold pad by the pumps, once the Id is live |
| StarterBundle | Commander Starter Pack | 3713839505 | 149 | Shop + one offer after the tutorial |
| Nuke | Nuke | 0 | 19 | hidden |
| NukeBundle3 | Nuke x3 | 0 | 49 | hidden |
| RebirthKeepBase | Keep-Base Rebirth | 0 (new, F7) | 50 | Rebirth panel only (SoldFrom), never the Shop list |

### New items to create (owner's 11 features)
| Type | Name | Price | Description | Config key |
|------|------|-------|-------------|------------|
| Game Pass | Speed Pass | 5 R$ | Run 15% faster, forever. | `GamePasses.ImpulseSpeed` |
| Developer Product | Keep-Base Rebirth | 50 R$ | Rebirth and keep every base building and level. | `DevProducts.RebirthKeepBase` |
| Developer Product | Golden Pumpjacks | 49 R$ | Gold-dress every oil pump on your base. Pumps come with Walls Lv 2. | `DevProducts.GoldenPumpjack` |

Paste `RebirthKeepBase` only after the double prestige multiplier fix (batch B part 1, B1) is live. Write `ids.json`
(`{"GamePasses":{"ImpulseSpeed":ID},"DevProducts":{"RebirthKeepBase":ID,"GoldenPumpjack":ID}}`), run
`python3 tools/wire-monetization-ids.py ids.json --dry-run`, then without `--dry-run`, run the CLAUDE.md §3 gates,
commit, publish, then Migrate to Latest Update.

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

## Live place status
Open Cloud Published **versionNumber=62** (place 97112936860418) — v62 BUY cash reconcile + purchase hook. WE_Build=63.

Open Cloud Published **versionNumber=63** (place 97112936860418) — v63 BUY attribute-ack + no WaitForProfile>0.25s. WE_Build=63.

Open Cloud Published **versionNumber=64** (place 97112936860418) — v64 BUY harden: nil Stats/BaseUpgrades safe, post-spend pcall visuals, SpendCash never-throw, WE_BuyErr=real err. WE_Build=64.

Open Cloud Published **versionNumber=65** (place 97112936860418) — v65 DataService-first Init + getDataService require fallback (fixes nil GetProfile on BUY). WE_Build=65.
