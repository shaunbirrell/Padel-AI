# WAR EMPIRE — Live place (created 2026-09-20)

- **Experience name:** **WAR EMPIRE**
- **Place ID:** `97112936860418`
- **Universe ID:** `10767159222`
- **Play URL:** https://www.roblox.com/games/97112936860418
- **Current live (Code Bot):** Open Cloud **versionNumber=137** (2026-09-30 Europe/Dublin) — **v139 JOB 36 shop overhaul** owner-first (`ShopOverhaulConfig.OwnerFirst=true`; WarChest/SuperSoldiers/DoubleHP Id 0). `WE_Build=139`. PreferMesh OFF; fast travel REMOVED.
- **Live Published:** Open Cloud **versionNumber=63** (2026-09-21 Europe/Madrid) — **v61 BUY PATH**: `Remotes.FireServer` (≤3s TryGet, no unbounded WaitForChild); WorldPrompt/BaseController toast "Buying…" only after FireServer; EnsureProfile on pad+PurchaseUpgrade; DataService Init before UpgradePad; `WE_Build=63`.
- **API Services:** enabled (DataStores) — required for profiles/persistence; no code change in v31, confirm still on in Creator Dashboard → Security
- **Privacy:** **Public** since 2026-09-24 17:54 UTC (develop API: privacyType Public, audiences Editors + Public). Under current Roblox rules, Private means only users with Edit permission can play.
- **Age / access:** rated "Mild, Ages 16+". Until the game passes Roblox's Kids/Select review, only age-checked players 16+ and the owner's Trusted Friends can join (create.roblox.com/docs/production/publishing/kids-and-select, checked 2026-09-23).
- **Devices:** Computer, Phone, Tablet enabled at create

## Server size

- **Max Players = 10** — claude-bud JOB 21 (2026-09-29): the map now has 10 base plots (`BaseConfig.MaxPlots = 10`,
  `GameConfig.MaxPlayersPerServer = 10`). **The owner must set the place's Max Players to 10** (it was 6: public API
  `games.roblox.com/v1/games?universeIds=10767159222` → `"maxPlayers":6`, checked 2026-09-27 15:37 UTC). One base per
  player; a player who still finds no free plot is told "Server full" and moved to another server (BaseService).
- Re-check the live value any time: `curl -sS "https://games.roblox.com/v1/games?universeIds=10767159222"`, field
  `maxPlayers`.
- It is a place setting (Max Players), not code: changing it needs no publish, and it is undone the same way. A change
  applies to new servers only; servers already running keep their old size until they close.
- When the place allows more players than there are plots, each new server logs one warning at boot:
  `[BaseService] Server size: this place's Max Players is ...`. Server log only; players never see it.
- 8 to 12 players per server needs more plots first (plot positions and pads). Then change Max Players,
  `BaseConfig.MaxPlots` and both `GameConfig` numbers together, and recheck the server-wide caps that every player
  shares (for example `CombatConfig.MaxActiveNPCs = 18`).

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
| ImpulseSpeed | Speed Pass | 1998656357 | 5 | Shop + death offer; owner-only while `MonetizationConfig.Rollout = "owner"` |
| PV_Razorfang | Razorfang GT Interceptor | 2002484380 | 199 | hidden |
| PV_Bastion | Bastion Gun Truck | 0 | 399 | hidden |
| PV_Warlord | Warlord Siege Tank | 2001320428 | 799 | hidden |
| PV_MotorPool | Premium Motor Pool | 0 | 1099 | hidden |
| PV_Stormwing | Stormwing Gunship | 2001722392 | 999 | hidden |
| PV_Tidebreaker | Tidebreaker Assault Boat | 1999263465 | 299 | hidden |
| PV_Skylance | Skylance Interceptor | 2001602422 | 899 | Garage (Robux-only jet, owner-only first; Id wired v99) |
| PV_Leviathan | Leviathan Dreadnought | 2001398410 | 1199 | Garage (Robux-only capital ship, owner-only first; Id wired v99) |
| BiggerArmy | Bigger Army | 2001734404 | 249 | Shop (+10 army cap; owner-only first; Id wired v99) |
| ExtraGarageSlot | Extra Garage Slot | 1999359549 | 199 | Shop gold ROBUX row (+1 vehicle slot; owner-only first; Id wired v99) |
| RebirthBoost | Rebirth Boost | 0 | 199 | hidden |
| WarChest | War Chest | 0 | 799 | Shop (JOB 36 overhaul, owner-first): counts as 2x Cash + Auto Collect + VIP + Bigger Army |
| SuperSoldiers | Super Soldiers | 0 | 349 | Shop (JOB 36 overhaul): +25% army damage and soldier HP |
| DoubleHP | Double HP | 0 | 199 | Shop (JOB 36 overhaul): x2 max health |
| PG_Sovereign | Sovereign Gold Pistol | 2002154652 | 99 | Base armory case + Shop WEAPONS gold row (claude-bud JOB 35; live v137) |
| PG_Quake | Quake Grenade Launcher | 2003492417 | 249 | Base armory case + Shop WEAPONS gold row (claude-bud JOB 35; live v137) |
| PG_Longshot | Longshot Sniper | 2003180431 | 299 | Base armory case + Shop WEAPONS gold row (claude-bud JOB 35; live v137) |
| PG_Havoc | Havoc Rotary Gun | 2002250646 | 349 | Base armory case + Shop WEAPONS gold row (claude-bud JOB 35; live v137) |
| PG_Thunderhead | Thunderhead Rocket Launcher | 1999305818 | 399 | Base armory case + Shop WEAPONS gold row (claude-bud JOB 35; live v137) |
| PG_Tempest | Tempest Railgun | 2002682646 | 499 | Base armory case + Shop WEAPONS gold row (claude-bud JOB 35; live v137) |
| PG_ArmoryPass | Armory Pass | 2002868467 | 1299 | Base armory 7th case + Shop WEAPONS (all six guns; claude-bud JOB 35; live v137) |

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
| GoldenPumpjack | Golden Pumpjacks | 3714663783 | 49 | Shop row + one gold pad by the pumps (+50% pump income); owner-only while Rollout = "owner" |
| StarterBundle | Commander Starter Pack | 3713839505 | 149 | Shop + one offer after the tutorial |
| Nuke | Nuke | 0 | 19 | hidden |
| NukeBundle3 | Nuke x3 | 0 | 49 | hidden |
| SoldierRefill | Instant Army Refill | 3715442523 | 49 | Shop / army prompt (owner-only first; Id wired v99) |
| PlazaAirstrike | Plaza Airstrike | 3715442542 | 79 | Shop / plaza button (owner-only first; Id wired v99) |
| RebirthKeepBase | Keep-Base Rebirth | 3714663721 | 50 | Rebirth panel only (SoldFrom), never the Shop list; owner-only while Rollout = "owner" |

### New items (owner's 11 features) — created 2026-09-28, Ids wired (claude-bud)
| Type | Name | Price | Description | Config key |
|------|------|-------|-------------|------------|
| Game Pass | Speed Pass | 5 R$ | Run 15% faster, forever. | `GamePasses.ImpulseSpeed` |
| Developer Product | Keep-Base Rebirth | 50 R$ | Rebirth and keep every base building and level. | `DevProducts.RebirthKeepBase` |
| Developer Product | Golden Pumpjacks | 49 R$ | Gold pumpjacks: +50% pump income. | `DevProducts.GoldenPumpjack` |

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
