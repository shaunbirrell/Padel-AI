# WAR EMPIRE — the Shop (claude-bud JOB 36, 2026-09-30)

- **Source of truth:** `src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau` for Ids and prices;
  `ShopOverhaulConfig.luau` for what the overhaul changes.
- **Id 0:** the item does not exist on the Creator Hub yet. It is hidden, never prompted, and shows SOON on stands.
  Paste the Id with `tools/wire-monetization-ids.py`.
- **Overhaul:** everything marked *overhaul* applies while `ShopOverhaulConfig.Live` is on for the player. It is
  owner-first; Code Bot sets `OwnerFirst = false` to launch. Off = the old shop.

## SUPPLY tab order (overhaul)
1. FREE rows: Daily Reward, Airdrop, Invite, Favorite.
2. War Chest.
3. 2x Cash (gold row, **BEST VALUE**).
4. VIP.
5. Auto Collect.
6. Starter Pack.
7. Battle Pass Premium.
8. Bigger Army.
9. Super Soldiers.
10. Double HP.
11. Speed Boost.
12. Double XP.
13. Armory guns.
14. Premium vehicles and Extra Garage Slot.
15. Cash packs (Mega first, **BEST OFFER**).
16. Consumables and the rest (Instant Army Refill, Plaza Airstrike, Golden Pumpjacks, the locked Supply Crate).

Every pass row reads **PERMANENT**.

## Game passes

| Key | Name | R$ | Id | Grants | Sold where |
|---|---|---|---|---|---|
| `WarChest` | War Chest | 799 | 2002640637 | Counts as owning 2x Cash + Auto Collect + VIP + Bigger Army | Shop (overhaul); hidden once all four are owned |
| `DoubleCash` | 2x Cash | 149 | 1982865711 | x2 Cash earnings | Shop (BEST VALUE), yellow Supply Depot stand, offers |
| `VIP` | VIP | 199 → **349** (overhaul) | 1985475542 | +25 % Cash. Overhaul: +50 % Cash, a daily supply crate (~10 min of income), the VIP lounge, the [VIP] chat tag and a gold chat name | Shop, VIP offer |
| `AutoCollect` | Auto Collect | 99 | 1985115501 | Empties the ATM automatically | Shop, red Supply Depot stand |
| `BiggerArmy` | Bigger Army | 249 | 2001734404 | +10 army cap (stacks with Army Expansion) | Shop, army-wiped offer (overhaul) |
| `SuperSoldiers` | Super Soldiers | 349 | 1998231741 | +25 % army damage and soldier HP (the per-player army damage cap stays) | Shop (overhaul) |
| `DoubleHP` | Double HP | 199 | 2002214665 | x2 player MaxHealth (armour adds on top) | Shop (overhaul) |
| `DoubleXP` | Double XP | 99 | 1982487698 | x2 XP | Shop |
| `ImpulseSpeed` | Speed Pass | 99 | 1998656357 | x1.5 walk speed | Old shop and the death offer. Overhaul: out of the Shop (Speed Boost sells speed); owners keep x1.5 |
| `ExtraGarageSlot` | Extra Garage Slot | 199 | 1999359549 | +1 vehicle out | Shop (gold row) |
| `PV_Razorfang` | Razorfang GT Interceptor | 199 | 2002484380 | Premium car | Shop gold row, Garage |
| `PV_Tidebreaker` | Tidebreaker Assault Boat | 299 | 1999263465 | Premium boat | Shop gold row, Garage |
| `PV_Warlord` | Warlord Siege Tank | 799 | 2001320428 | Premium tank | Shop gold row, Garage |
| `PV_Skylance` | Skylance Interceptor | 899 | 2001602422 | Premium jet | Shop gold row, Garage |
| `PV_Stormwing` | Stormwing Gunship | 999 | 2001722392 | Premium helicopter | Shop gold row, Garage |
| `PV_Leviathan` | Leviathan Dreadnought | 1199 | 2001398410 | Premium capital ship | Shop gold row, Garage |
| `PV_Bastion` | Bastion Gun Truck | 399 | **0** | Premium gun truck | Garage (hidden until the Id) |
| `PV_MotorPool` | Premium Motor Pool | 1099 | **0** | All 3 premium ground vehicles | Hidden until the Id |
| `PG_Sovereign` | Sovereign Gold Pistol | 99 | **0** | The gun | Base armory case, Shop WEAPONS gold row (JOB 35) |
| `PG_Quake` | Quake Grenade Launcher | 249 | **0** | The gun | Armory, Shop WEAPONS |
| `PG_Longshot` | Longshot Sniper | 299 | **0** | The gun | Armory, Shop WEAPONS |
| `PG_Havoc` | Havoc Rotary Gun | 349 | **0** | The gun | Armory, Shop WEAPONS |
| `PG_Thunderhead` | Thunderhead Rocket Launcher | 399 | **0** | The gun | Armory, Shop WEAPONS |
| `PG_Tempest` | Tempest Railgun | 499 | **0** | The gun | Armory, Shop WEAPONS |
| `PG_ArmoryPass` | Armory Pass | 1299 | **0** | All six guns | Armory 7th case, Shop WEAPONS |
| `ExtraPlotCosmetic` | Elite Base Theme | 79 | 1983357731 | (nothing applies it yet) | Hidden |
| `RebirthBoost` | Rebirth Boost | 199 | **0** | +15 % Cash per rebirth, 1.5x start cash | Hidden (off sale) |

## Developer products

| Key | Name | R$ | Id | Grants | Sold where |
|---|---|---|---|---|---|
| `CashSmall` | Cash Pack S | 49 | 3713838744 | $10,000. Overhaul: max($10k, 5 min of your passive income) | Shop, garage "short on cash" offer |
| `CashMedium` | Cash Pack M | 149 | 3713838815 | $50,000. Overhaul: max($50k, 20 min) | Shop, garage offer |
| `CashLarge` | Cash Pack L | 399 | 3713838888 | $200,000. Overhaul: max($200k, 60 min) | Shop, rebirth offer, garage offer |
| `CashMega` | Cash Pack Mega | 799 | 3713838952 | $2,000,000. Overhaul: max($2M, 180 min) | Shop (BEST OFFER), Mega toast |
| `StarterBundle` | Commander Starter Pack | 149 | 3713839505 | $50,000 + Auto Collect (or +$25,000 if already owned) | Shop, Army panel, starter offer (48 h) |
| `PremiumPass` | Battle Pass Premium | 499 | 3713839151 | Battle Pass premium track | Shop, Battle Pass panel |
| `SpeedBoost` | Speed Boost | 99 | 3713839342 | x2 walk speed, one time | Shop. Overhaul: also the base Speed stand and the death offer |
| `ExtraSoldierSlot` | Army Expansion (+10) | 99 | 3713839210 | +10 army cap, one time (stacks with Bigger Army) | Army panel. Overhaul: out of the Shop; owners keep +10 |
| `SoldierRefill` | Instant Army Refill | 49 | 3715442523 | Fills the army to its cap | Shop, army-wiped offer (old path) |
| `PlazaAirstrike` | Plaza Airstrike | 79 | 3715442542 | One plaza airstrike charge | Shop |
| `GoldenPumpjack` | Golden Pumpjacks | 49 | 3714663783 | +50 % pump income | Shop, gold pad by the pumps |
| `RebirthKeepBase` | Keep-Base Rebirth | 50 | 3714663721 | Rebirth keeping every upgrade | Rebirth panel only |
| `InstantBarracks` | Instant Barracks | 129 | 3713839278 | Barracks L1 | Hidden |
| `GoldSmall` / `GoldMedium` / `GoldLarge` | Gold Packs | 49 / 149 / 349 | 3713839003 / 3713839048 / 3713839090 | Gold | Hidden |
| `Nuke` / `NukeBundle3` | Nuke / Nuke x3 | 19 / 49 | **0** | Nukes | Hidden |
| `AutoCollect` / `DoubleCash` / `VIPBoost` | (product twins of the passes) | — | **0** | — | Hidden (the passes cover them) |

## Ids and prices the owner must set
- ~~Create the three new passes~~ Done 2026-09-30 (codebot_v140, WE_Build 140): `WarChest` 2002640637 (799), `SuperSoldiers`
  1998231741 (349), `DoubleHP` 2002214665 (199). Verified on universe 10767159222, on sale, prices match. Still owner-first
  (`ShopOverhaulConfig.Live.OwnerFirst = true`) until the owner says launch.
- The six `PG_*` guns and `PG_ArmoryPass`: see JOB 35.
- **VIP:** set the pass price to **349 R$** on the Creator Hub, then launch the overhaul. The shop shows 349 only while
  the overhaul is live; Roblox always charges the Creator Hub price.
