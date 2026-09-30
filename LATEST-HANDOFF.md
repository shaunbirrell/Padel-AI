<!-- Q2-START -->
## v138 (Code Bot Roblox, 2026-09-30 ~14:58 Dublin): aircraft weapons ON for everyone (owner Shaun 14:44) — place version 136
- **WE_Build 138**. Code + dist commit `e45c7bb`; JOB 40 doc `667d004` (phase-7-polish) / `b520912` (claude/desktop-bud). Open Cloud HTTP 200 `versionNumber=136`. PreferMesh OFF; WE_Building* untouched; fast travel stays REMOVED; RolloutKeys and Robux prices unchanged.
- **The gate:** `AircraftWeaponConfig.WeaponsLive = false` (dark since the air-weapons lane / v101); `AircraftWeaponConfig.LiveFor` returned true only for `AdminConfig.IsPlaytestOwner` (UserId 470626172). That is why Shaun's jets fired. AirWeaponService refuses fire with "off" when LiveFor is false and writes the player attribute `WE_AirWeaponsLive` that shows the client fire buttons. No other owner / Studio check in the air-weapon path.
- **Flip:** `WeaponsLive = true` (one line). LiveFor now returns true for every UserId. Non-owners still need an armed aircraft by normal progression (the owner's spawn bypass for Helipad / Airfield gates is unchanged, owner only).
- **Hostility / protection (unchanged, same shared rule):** direct hits go through `CombatService.ApplyHit`. Players go through hurtPlayer -> `pvpBlock` (PvP off, spawn shield, novice shield). Army soldiers go through `ArmyHostility`. Splash goes through `ApplyRadiusDamage` -> hurtPlayer (clan allies skipped). Vehicle splash skips allies and novice-shielded owners; a shielded pilot deals no splash. Gates / guards skip allied or shielded bases (raid shield, new-player protection, novice). Firing ends the pilot's own novice shield. Admins get no bypass.
- **Checks:** `LUAU_COMPILE=$HOME/.local/bin/luau-compile python3 tools/BuyPathStatic.py` PASS=6847 FAIL=0; `tools/checks/codebot_v138.py` (all PASS); `tools/v101_gate_test.py` fails=0 (now asserts non-owner LiveFor true); rojo ok. Old "WeaponsLive stays off" pins were retired in BuyPathStatic, updated in codebot_v101, and the v137 build pins moved to v138.
- **Live probe (Open Cloud Luau, v136):** `WeaponsLive=true`, `LiveFor(12345)=true`, `LiveFor(987654321)=true`, `LiveFor(470626172)=true`; Fighter = JetCannon, JetMissiles; AttackHeli = HeliNoseGun, HeliRockets; PreferMesh=false; FastTravel=false.
- **JOB 40 part E:** the queue doc on both branches now reads "APPROVED by owner 2026-09-30: visible from anywhere on the map". The base owner marker is the one exception to the labels-within-40-studs rule.
- **Servers:** running servers keep v137. Shaun will restart / migrate them himself; Code Bot did not restart any.

## v137 (Code Bot Roblox, 2026-09-30 ~14:37 Dublin): wire premium gun passes — place version 135
- **WE_Build 137**. Wired only `MonetizationConfig.GamePasses.PG_*` `Id` fields; prices unchanged. PreferMesh OFF; WE_Building* untouched; fast travel stays REMOVED.
- **Creator Hub verification:** public `apis.roblox.com/game-passes/v1/universes/10767159222/game-passes?passView=Full&pageSize=100` lists all seven IDs, each `isForSale=true`, with prices 99 / 249 / 299 / 349 / 399 / 499 / 1299 matching config. Product-info endpoint also confirms names, sale state, and prices; no mismatch.
- **Rollout / shop:** PG_* remains outside `RolloutKeys` as the config comment directs; the existing armory and Shop WEAPONS gold-row paths use the real pass IDs. Non-owner armory cases now resolve to Buy with prices, not SOON.
- **Checks:** `LUAU_COMPILE=$HOME/.local/bin/luau-compile python3 tools/BuyPathStatic.py` PASS=6832 FAIL=0; `python3 tools/sim/run_armory_test.py` 0 failed; `tools/checks/codebot_v137.py` pins all seven IDs and prices; rojo ok. Commit `3c20551`; Open Cloud HTTP 200 `versionNumber=135`.
- **Live probe (Open Cloud Luau, v135, uid 12345 / non-owner):** all seven armory cases returned `Buy` with the configured price, not `SOON`: R$99 / 249 / 299 / 349 / 399 / 499 / 1299. Each live config Id matched the Creator Hub public API.

## v136 (Code Bot Roblox, 2026-09-30 ~14:25 Dublin): LAUNCH FOR EVERYONE (owner Shaun 14:17) + JOB 35 premium guns live — place version 134
- **WE_Build 136**. Code commit `65d4769` + dist `385deb2`. Open Cloud HTTP 200 `versionNumber=134`. PreferMesh OFF; WE_Building* untouched; fast travel stays REMOVED; no Robux price changed; admins still off leaderboards.
- **Flipped `OwnerFirst = true -> false` (Enabled kill switches kept):** `TutorialConfig.FastStart`, `EconomyConfig.OfflineEarnings`, `DailyRewardConfig.StreakCard` (+ Day7Boost), `RetentionConfig.Notifications` (JOB 29); `MapConfig` (JOB 30 map + v129 MAP-REDESIGN look, `FastTravelEnabled = false` kept); `SiteActivityConfig` (JOB 31 sites / activities / garrisons); `StorePropsConfig` (world + rebirth-zone store props; `WE_StorePropsOff` live kill kept); `PremiumGunsConfig.Live` (JOB 35 armory).
- **Events:** `EngagementConfig` weekly rotation was already live for everyone since v104 (Double Cash Weekend / Plaza War Week / Airdrop Frenzy; server-side, capped mults). Next: AIRDROP FRENZY Fri 2 Oct 01:00 Dublin. Unchanged.
- **Left gated (why):** `AircraftWeaponConfig.WeaponsLive=false` (PvP aircraft weapons, kept dark since v101, not in this launch list); `OpsConfig.Enabled=false` incl. `Director.Events` (W3 Jobs Phase B/C: unfinished, would double the bank job with BankRaid; JOB 31 sites replace it); `VisualAssetConfig.BodyRollout="owner"` (mesh hulls need WE_CHECK2); `SecurityConfig` Rollout `observe` (anti-exploit enforcement, not a feature gate); `BusinessConfig`/XP backfill (unfinished, off for everyone); `MonetizationConfig.LaunchAll=false` (every gate already "all"); owner test shortcuts (OwnerTestGrant etc.) unchanged — owner/Studio only.
- **Premium guns with pass Ids 0:** every player sees the armory; cases show SOON with the prompt disabled (server also refuses Id 0); Shop gold rows hidden. **When the 7 Creator Hub pass Ids arrive:** paste into `MonetizationConfig.GamePasses.PG_*` `Id = ...` only (prices unchanged), bump build, publish. No code change needed.
- **Checks:** BuyPathStatic PASS=6830 FAIL=0; `tools/checks/codebot_v136.py`; all `tools/sim/run_*_test.py` 0 failed (armory test now also checks everyone-live + SOON for a non-owner); owner-first pins in job29/30/31/35, v125/v128/v132/v135 superseded. Open Cloud Luau probe on v134 (uid 12345, not Studio): FastStart/Offline/Notif/StreakCard/Map/Sites/StoreProps/PremiumGuns all true, FastTravel false, armory case Soon/SOON/no prompt, EarlyRemotes WE_Build 136.
- **Servers:** running servers keep v133 — "Migrate to Latest Update" (or restart servers) so players get v136.

## v135 (Code Bot Roblox, 2026-09-30 ~13:52 Dublin): ship claude-bud JOB 35 premium guns armory — OWNER-FIRST (pass Ids still 0) — place version 133
- **WE_Build 135**. Code commits `0eba3bd`/`182aca8` (cherry-pick) + `1e6d56c` (+ dist `4e5b834`). Open Cloud HTTP 200 `versionNumber=133`. PreferMesh OFF; WE_Building* untouched; fast travel stays REMOVED.
- **Flags (per Claude handoff):** `PremiumGunsConfig.Live.Enabled = true`, `OwnerFirst = true`, `OwnerTestGrant = true`. Pass Ids (`PG_*`) stay **0** — Shop hides gold rows; armory cases show SOON / never prompt until the owner pastes Ids. **To launch for everyone:** set `OwnerFirst = false` and paste the 7 pass Ids in MonetizationConfig.
- **What ships:** 6 premium guns (Sovereign / Quake / Longshot / Havoc / Thunderhead / Tempest) + Armory Pass; GunMechanics (burst/spin/charge/pierce/headshot); Longshot scope; base armory 7 glass cases west of Supply Depot; Shop gold rows when Ids live; PremiumGunService grants on pass own.
- **Checks:** BuyPathStatic PASS=6807 FAIL=0; `claude_bud_job35` 28 pins; `run_armory_test.py` 0 failed; `codebot_v135` pins; rojo ok.
- **Phone tests (Migrate to Latest Update, as owner shaunie6):**
  1. Walk west of Supply Depot: 7 glass cases + ARMORY sign; boards SOON or OWNED (owner test grant).
  2. Tap a case: Equip the gun; hotbar shows it.
  3. Longshot: SCOPE button (above RELOAD) — zoom levels, vignette, exit on RELOAD.
  4. Havoc: hold FIRE — barrel spins, shots after ~0.5s.
  5. Tempest: hold to charge, release; 2-player pierce + PvP protection still holds (novice shield / pvp off).
  6. Non-owner join: no armory / no grants (OwnerFirst).

## claude-bud JOB 36 (2026-09-30): shop overhaul (branch `claude/desktop-bud`)
**Flags:** `ShopOverhaulConfig.Live` (`Enabled`, `OwnerFirst = true`).
- **Off:** the old shop exactly.
- **To launch:** the owner sets VIP to 349 R$ on the Creator Hub and pastes the new Ids, then Code Bot sets
  `OwnerFirst = false`.

**Ids / prices the owner must set**
- Create game passes `WarChest` (799), `SuperSoldiers` (349) and `DoubleHP` (199); all are Id 0 now, so hidden and
  never prompted.
- VIP: change the Creator Hub price 199 -> **349**. MonetizationConfig keeps `RobuxPrice = 199` and shows
  `OverhaulRobuxPrice = 349` only while live.
- Every item is listed in `docs/SHOP.md`.

**What it does (while live)**
- **Order:** FREE -> War Chest -> 2x Cash (**BEST VALUE**, gold) -> VIP -> Auto Collect -> Starter Pack -> BP Premium
  -> Bigger Army -> Super Soldiers -> Double HP -> Speed Boost -> Double XP -> armory guns -> premium vehicles -> cash
  packs -> consumables. Every pass row reads **PERMANENT**.
- **Cash packs:** grant = max(floor, minutes x the buyer's passive $/min), computed in ProcessReceipt.
  - S = max($10k, 5 min), M = max($50k, 20 min), L = max($200k, 60 min), Mega = max($2M, 180 min).
  - The lookup that may yield runs before the first mutation, then re-checks the player / profile.
  - Rows, the Mega toast, the rebirth offer and the garage "short on cash" offer show the live amount
    (`WE_PassivePerMin`, published every 10 s).
- **Duplicates:**
  - The Speed Pass and Army Expansion leave the Shop.
  - The base Speed stand (`PurchaseStands.Retarget`) and the death offer sell Speed Boost.
  - The army-wiped offer sells Bigger Army.
  - Owners keep their speed and army bonus (the reads are ownership, not the Shop).
  - Note: the speed multipliers are the current v133 ones: the Speed Pass is x1.5 and Speed Boost x2. The brief's x1.4
    is outdated.
- **VIP:** +50 % Cash (was 25 %), a daily supply crate (max($5k, 10 min of income) every 20 h, `VipSupplyAt`,
  "vip_supply" is multiplier-exempt), the lounge and the [VIP] tag as before, plus a gold chat name (`WE_VIPGold`).
  Every current VIP owner gets it.
- **War Chest** counts as owning 2x Cash + Auto Collect + VIP + Bigger Army. MonetizationService marks them owned on
  the join check and on purchase. The row hides once all four are owned.
- **Super Soldiers:** army damage and soldier HP x1.25 (`WE_PerkSuperSoldiers`; the per-player army DPS cap stays).
- **Double HP:** base MaxHealth x2 in ArmourService (`WE_PerkDoubleHP`; armour adds on top; the HUD base follows).
- **`docs/SHOP.md`:** every item with key, name, price, Id, what it grants and where it is sold.

**Checks**
- `tools/checks/claude_bud_job36.py` (25 pins).
- `tools/sim/run_shop_test.py`: the order on the real row names; pack maths with floors / NaN; the VIP crate once per
  day (real service); perks only while live; the Speed stand retarget and restore (real PurchaseStands); config Ids /
  prices; the receipt order.
- BuyPathStatic PASS=6796 FAIL=0; all sims 0 failed; rojo ok; no new LSP errors; remote audit OK.

**Not verified here:** a real Robux purchase (Roblox test purchases in Studio) and the 2-player combat check of Double
HP / Super Soldiers.

**Test ON HIS PHONE (owner)**
1. Open Shop > SUPPLY: FREE rows, then 2x Cash marked **BEST VALUE** in gold, then VIP at 349, and so on. Every pass
   row reads PERMANENT, and the Speed Pass / Army Expansion rows are gone.
2. The cash pack rows show amounts from your income (for example Cash Pack L = 60 min of your passive income, never
   under $200k). A test purchase in Studio pays that amount.
3. Walk to the Supply Depot: the Speed stand reads Speed Boost R$ 99 (a second non-owner phone's base still shows the
   Speed Pass).
4. Rejoin as VIP: "VIP supply crate: +$X" arrives once. Your chat name is gold; rejoining the same day gives no second
   crate.
5. Lose your whole army: the offer is "Army down! Bigger Army: +10 soldiers". Die with no speed owned: the offer is
   "Run faster" for Speed Boost.
## claude-bud JOB 35 (2026-09-30): premium guns armory (branch `claude/desktop-bud`)
**Flags:** `PremiumGunsConfig.Live` (`Enabled`, `OwnerFirst = true`).
- **Off:** no armory, no grants, no gold rows. The six guns stay in WeaponConfig, unowned and unsold.
- `OwnerTestGrant = true`: while live, the owner (and Studio test players) get the six guns, since the passes are Id 0.
- **To launch:** Code Bot sets `OwnerFirst = false`, and the owner pastes the pass Ids.

**Ids the owner must paste** (MonetizationConfig; all 0 = hidden in the Shop, SOON in the armory, never prompted):

| Pass | Price | Gun(s) |
|---|---|---|
| `PG_Sovereign` | 99 | Sovereign Gold Pistol |
| `PG_Quake` | 249 | Quake Grenade Launcher |
| `PG_Longshot` | 299 | Longshot Sniper |
| `PG_Havoc` | 349 | Havoc Rotary Gun |
| `PG_Thunderhead` | 399 | Thunderhead Rocket Launcher |
| `PG_Tempest` | 499 | Tempest Railgun |
| `PG_ArmoryPass` | 1299 | all six |

**What it does**
- **Guns:** six WeaponConfig guns (`Premium`, CostCash 0) on the brief's assets.

  | Gun | Mechanics | DPS at full rate |
  |---|---|---|
  | Sovereign | 30 dmg, 2-shot burst, mag 12 | 100 |
  | Quake | 70, lobbed, splash 11, drum 6 | 84 |
  | Longshot | 110, headshot x1.5, range 600, real scope | 77 |
  | Havoc | 0.6 s spin-up, 20 rps x 9, mag 150 | 180 |
  | Thunderhead | 2-rocket salvo x 170, splash 12 | 109 |
  | Tempest | 0.8 s charge, 140, hits up to 3 bodies in a line | 140 |

  All are below the best existing automatics (AR 198, Sovereign Rifle 234).
- **Grants:** owning PG_x or the Armory Pass sets `profile.Weapons[id] = true` (PremiumGunService on OnPassOwned: join
  plus confirmed purchase).
  - Cash purchase refuses premium guns ("RobuxOnly"); equip still refuses unowned guns.
- **Mechanics** (`Shared/Util/GunMechanics`, server-authoritative in `CombatService.RequestFire`):
  - a trigger-down "Prime" (Spin / Charge) is not a shot;
  - Ready / Interval / OnShot sit around the unchanged v69 schedule;
  - Pierce re-casts past each body and sends every extra hit through ApplyHit (the one PvP / protection rule);
  - per-gun HeadshotMult;
  - nil fields = every old gun unchanged (the test checks the AR still fires 9/s).
- **Loader:** `WeaponAssetLoader` accepts a plain Model / MeshPart (`VisualPlain`).
  - Every part is welded to the body, an invisible Handle is added, and the Havoc barrel gets `WE_SpinWeld`.
  - `VisualChild "*"` = a kit Tool's first Model; `VisualLength` scales the template.
  - Scripts are stripped, the 16-part cap stays, and the Part kit remains the fallback.
- **Scope** (`Modules/Scope`, Longshot only):
  - hold RMB / L2, or the phone SCOPE button above RELOAD;
  - FOV 70 -> 20 -> 12 (wheel / second tap), then off;
  - black vignette + reticle, mouse sensitivity x FOV/70, sway while moving, recoil x0.5;
  - exits on reload, death, seat, switch or holster.
- **Armory:** in every live player's base, 7 glass cases in one row west of the Supply Depot (plot X -92 .. -131,
  Z 146), plus one ARMORY sign with the row's only light.
  - Each case: plinth + gold trim + glass 0.6 + gold cap; about 30 parts per base.
  - Prompt: "Buy - R$ X", Equip once owned (the glass fades), or disabled with a SOON board while the Id is 0.
  - Boards are base labels, so the LabelGovernor shows the 3 nearest.
  - The client spins the gun template in each case within 70 studs; the 7th case cycles the six guns.
- **Shop > WEAPONS:** gold rows for the premium guns ("PERMANENT", R$ price), listed while live once the pass has an Id.

**Checks**
- `tools/checks/claude_bud_job35.py` (28 pins).
- `tools/sim/run_armory_test.py`: 74 checks.
  - mechanics; a 20 Hz held trigger per gun, on a line-for-line copy of RequestFire's schedule (the copy's lines are
    checked against the source);
  - configs / Ids / prices; CaseState; grants; owner-first;
  - placement vs the whole layout;
  - the real loader on a fake plain model (Handle, welds, spin weld, scale, 16-part cap) and a kit Tool with "*".
- BuyPathStatic PASS=6754 FAIL=0; remote audit OK; rojo ok; all sims 0 failed; no new LSP errors.

**Not verified here (needs Studio / a device)**
- The six assets' real contents: part counts, and which way each muzzle points. A plain model's grip is placed on its
  longest axis automatically. **Check each gun in the hand in Studio.** If a muzzle points backwards, set
  `VisualGrip = { X = 0, Y = 0, Z = 0, RX = 0, RY = 180, RZ = 0 }`. A model over 16 parts falls back to the Part kit
  and the server log says so.
- **The 2-player Studio combat test (owner rule):** Tempest pierce through 2 players, Havoc spin-up, the Thunderhead
  salvo splash, and PvP protection on each (novice shield / pvp off).

**Test ON HIS PHONE (owner + a second phone)**
1. Walk to the Supply Depot and look west: 7 glass cases with a gun turning in each, and the ARMORY sign. At most 3
   boards show at once; they read SOON, or OWNED for the owner (test grant).
2. Tap a case prompt (owner): "Equip" equips that gun. The hotbar shows it and the Shop > WEAPONS row is gold.
3. Longshot: tap SCOPE (above RELOAD), tap again for more zoom, a third tap exits. It also exits on RELOAD. Check the
   vignette and reticle are readable and FIRE / RELOAD stay usable.
4. Havoc: hold FIRE. The barrel spins, shots start after about half a second, and 150 rounds last.
5. Tempest: hold FIRE to charge and release to fire. It hits both of 2 players standing in a line. The second phone:
   a player with a novice shield / pvp off takes nothing.
## v134 (Code Bot Roblox, 2026-09-30 ~13:28 Dublin): 5 Roblox badges wired + badge backfill on join - place version 132
- **WE_Build 134**. Code commit `b457917` (+ dist `e2c6225`). Open Cloud HTTP 200 `versionNumber=132`. PreferMesh OFF; WE_Building* untouched; fast travel stays REMOVED. Badges only (JOB 40 guards / speed / props are Claude's, untouched).
- **Root cause (owner: every badge 0% "Impossible"):** `AchievementConfig` BadgeIds were all 0, so `AchievementService.awardBadge` returned before `AwardBadge` for every unlock.
- **Wired (badges.roblox.com: all enabled, awardingUniverse 10767159222; BadgeService:GetBadgeInfoAsync live OK):** `FirstKillNPC` = First Blood `772051421546625`; `FirstPlayerKill` = Duelist `2489884143486750`; `FirstUpgrade` (Title "First Building") = First Building `583497417329015`; `Cash10k` = War Chest `1847488248714137`; `PlayerKills10` = Hunter `2976613716370877`. The other 16 stay 0; the daily badge routine creates / wires 5 per 24 h (GMT) (`/workspace/badges/progress.json`).
- **Award path (checked, unchanged):** on unlock `Grant` spawns `awardBadge`: pcall `UserHasBadgeAsync` first (owned = skip), pcall `AwardBadge`, `Badges.Retries` 3 with backoff. New: one in-flight award per player + badge (unlock + backfill never double-call).
- **Backfill on join (`AchievementService.BackfillBadges`):** on every profile load (+4 s, after the Live Check) every achievement already in `profile.Achievements` with a non-zero BadgeId is awarded if not owned, one per `Badges.SyncGapSeconds` (1 s), whole pass pcall, once per session. No longer gated by `AchievementConfig.Live` (old MissionService-path unlocks count). Admins / the owner included (only leaderboards exclude admins).
- **Owner (shaunie6 470626172):** DataStore save has 14 achievements unlocked incl. all 5 wired (FirstKillNPC, FirstPlayerKill, FirstUpgrade, Cash10k, PlayerKills10); he owns none of the badges yet -> on his next join all 5 are awarded (~5 s after load).
- **Checks:** BuyPathStatic PASS=6763 FAIL=0 (`codebot_v134.py`: 22 pins incl. run_achievement_test); `run_achievement_test.py` 0 failed (+6 v134 backfill cases: non-Live player, owned skipped, BadgeId 0 skipped, throttle, once per session, owner). Retired: codebot_v133 WE_Build pins; BuyPathStatic / v110 / v113 WE_Build pins bumped to 134; the "BadgeId 0 everywhere" test pin now = wired id or 0. rojo ok. Live Luau on v132: the 5 ids + BackfillBadges present.
- **Phone test (Migrate to Latest Update):** rejoin WAR EMPIRE; within ~10 s Roblox shows the badge toasts (First Blood, Duelist, First Building, War Chest, Hunter); the experience page badges leave 0%.
## v133 (Code Bot Roblox, 2026-09-30 ~12:41 Dublin): owner phone bugs - armies fight players both ways, real roof hatch, town-centre facades, faster paid speed - place version 131
- **WE_Build 133**. Code commit `106f32e` (+ dist `9d53831`). Open Cloud HTTP 200 `versionNumber=131`. PreferMesh OFF; WE_Building* untouched; fast travel stays REMOVED.
- **1a. An enemy army never shot the owner.** Root cause: a player is a target only in `SquadOrdersService.pickSquadTarget`, which the think loop runs only for ATTACK; FOLLOW (the default, `OrdersConfig.DefaultOrder = "Follow"`, live-probed) / HOLD scanned WE_NPC models only. His profile was not protected (NoviceShieldDone, no clan, PvP on). Fix: `pickDefendTarget` + `defendAimOnly` (FOLLOW / HOLD, `ArmyConfig.ArmyCombat.DefendOnFollow`, reach `DefendPlayerStuds` 47 / aggressor `DefendAggressorStuds` 55) under THE shared `CombatService.UnitMayHitPlayer`; aggressors first (RecentlyHurtBy). FOLLOW keeps walking its block and only aims / fires (no walking out); HOLD stays put.
- **1b. The owner's shots did nothing to an enemy army.** Root cause (live probe on v132): `CombatService shotFilterFor` excluded the WHOLE `Workspace.WarEmpireSquads` folder, so the ray passed through the soldier and hit the wall behind; and `resolveTarget` had no kind for a squad unit (no WE_NPC tag / NPCId -> "None"). Fix: the filter (server + client `CombatController W2.shotFilter`) passes only the shooter's OWN and clan allies' soldiers; `resolveTarget` -> `"Unit"`; `ApplyHit` "Unit" = `CombatService.ArmyHostility` (PvP on / not self / not ally / owner not novice-shielded -> else a "Protected" toast) + attacker-shield rule, then CombatService deals Humanoid damage (SquadOrdersService only hands in its live-unit lookup, `SetUnitHitHandler`; squadfair "no raw TakeDamage" still holds) and `NoteArmyAggressor` so his squad fights back. Headshots count; aim assist offers enemy soldiers. Post-publish live probe: `_ResolveKind` = Unit; uid-12345 filter hits the soldier; the owner's own filter passes through. Kill switch: `ArmyCombat.PlayersHitUnits = false`.
  - **Claude (JOB 35 guns):** new guns must go through `ApplyHit` + `shotFilterFor(character, veh)`; the "Unit" kind is how a player hurts soldiers. `ApplyRadiusDamage` (blasts / nukes) still skips squad units (not changed).
- **2. Plaza ladder ended under a solid ceiling.** Root cause: the JOB 32 hatch was just the truss footprint; a climber hangs on a FACE, so his head hit the roof slab 5 studs below the top (new `tools/sim/run_hatch_test.py`, character-sized: v132 = 2 TRAP faces). Fix: 4 roof slabs round a 5.6 x 5.3 opening, the 12-stud ladder inside it, `PlazaHatchShaft` panel on its roofed face, hatch frame + railing + lid. Test: 3 faces climb all the way, 0 traps, all 4 orientations.
- **3. Speed.** Speed Boost x1.6 -> **x2** (16 -> 32, "Run 2x faster, forever"), Speed Pass x1.4 -> **x1.5** (24), `MAX_WALK_SPEED_MULT` 2 (cap 32); Follow3 soldier MaxSpeed 40 -> 46 (catch-up headroom). The default Animate already speeds the run cycle with WalkSpeed (not duplicated). **Creator Hub product descriptions may still say 40% / 60%: owner to update.**
- **4. Town-centre facades (PlazaHouse, the 4 plaza rows):** `PlazaBuildingsConfig.Styles` (cafe ochre/teal, market terracotta/navy, hotel stone/red, radio shop khaki/orange): door + window frames, glass (never collides or answers a ray), striped awnings, shop sign board, storey band + cornice + coping, quoins, plinth, balcony, planters, bench, lantern, rooftop AC / cistern / antenna. 142 parts each (was 55), `MaxExtraParts` 640. Nothing reaches > 1 stud out of the front (WorldPOI disc: road >= 30 and the plaza capture ring keep their margin). No SurfaceGui / light (the Town row caps would skip the building).
- **Checks:** BuyPathStatic PASS=6746 FAIL=0 (`codebot_v133.py`: 27 pins incl. run_hatch_test); run_plaza_test 0 failed (142 parts, disc r 12.75); run_kit_detail_test 0 failed; rojo ok. Retired pins: codebot_v126 speed x1.4/x1.6/1.75, claude_bud_job32 MaxExtraParts 240 + ladder span, BuyPathStatic W2 isHead, codebot_v132 WE_Build.
- **Phone tests (Migrate to Latest Update):**
  1. 2 players (A, B), both past the new-player shield, not in one clan. B's army on FOLLOW; A walks within ~45 studs of it: the army fires at A.
  2. A shoots B's soldiers: damage numbers / hit markers, soldiers die (they come back ~8 s later), and B's squad shoots back at A.
  3. `/armydebug` on either: Output shows `[ArmyDefend]` and `[ArmyUnitHit]` lines.
  4. Same clan / a shielded new player: never engaged; shooting a shielded player's army shows "Protected".
  5. Plaza building: climb the ladder upstairs from its open sides -> step off onto the roof. Look at the 4 facades.
  6. With Speed Boost: you run clearly faster (32); your army keeps up.
## v132 (Code Bot Roblox, 2026-09-30 ~12:05 Dublin): STORE-PROPS - Creator Store picks wired (owner-first) - place version 130
- **WE_Build 132**. Code commit `a44fdde` (+ dist `e01d856`). Open Cloud HTTP 200 `versionNumber=130`. PreferMesh OFF; WE_Building* untouched; fast travel stays REMOVED.
- **Probe (Open Cloud Luau, InsertService:LoadAsset): 80 / 80 picks load; none "not authorized".** Parts + sizes per id in `docs/PROP-ASSETS.md`.
- **Wired: 62 / 80** via NEW `Shared/Configs/StorePropsConfig.luau` (ids, categories, placement rows, budgets, flags) + NEW `Services/StorePropsService.luau` (loads each once, strips scripts/humanoids/sounds/prompts/movers/joints, anchors, CanTouch off, no shadows < 8 studs, no collision < 1.2, caps lights, bottom-centre pivot, ground-ray + overlap + road + base-clearance checks, nothing floats).
  - **World (57 ids, 213 copies, ~7,978 parts; cap 9,000):** Workspace.WorldFill.StoreProps at JOB 31 sites/areas: office 12423243620 + hospital in Crossroads Town, army base 11530941074 at the Armory, military base 8388537872 at Dust Camp, ruined apartment 447143432 in the Ruins, desert house 16365964601 at Dry Well, camp/desert dressing at Camp Viper, Pump Seven, Kestrel, Hawk, Overwatch, Anvil. All off roads and >= 330 studs from bases.
  - **Rebirth zones (25 ids):** for the plot owner at L1+ the Part clusters are swapped for store models (tank factory 8878478175, silo complex 4784051512, refinery 4669786564, etc.) on the yard, with Yard + Console kept. Any layout/budget check that fails keeps the Part build. EastYard (Elite Barracks) keeps its Part build plus dressing (the store barracks 8637034739 is a plain block).
  - **Not placed (18):** rejected 2473378608, 3117530492, 2580028799 (Tool); left for JOB 37 Checkpoint (spec uses Parts) 11989298499, 12125769119, 9404286622, 8279648205; over budget or worse than the Part build 14243660153, 12734850183, 12922051897, 15362548171, 7210304938, 2955329464, 9064883345, 7649697954, 9370327334, 182529039, 8637034739.
- **Flags:** `StorePropsConfig.Enabled` (kill switch), `OwnerFirst = true` (only when the owner is in the server / owns the plot), live kill with Workspace attribute `WE_StorePropsOff = true`. **To launch:** set `OwnerFirst = false` after the owner OKs it.
- **Claude collision:** no edits to RebirthZoneBuilder, RebirthZoneService, WorldSites, WorldKits (JOB 35-38 safe). CLAUDE.md: store props live in StorePropsConfig and must not be removed.
- **Checks:** BuyPathStatic PASS=6729 FAIL=0 (codebot_v132: 48 pins); live Open Cloud harness: 213 world copies 0 floating, 7 zones x 3 levels clean; rojo ok.
- **Phone tests (Migrate to Latest Update, as owner):**
  1. Drive to Crossroads Town: the 4-floor office and hospital stand on the ground next to the roads (not on them); Camp Viper has tents/crates/sandbags.
  2. Visit Dust Camp and the Armory: the military base / army base compounds sit flat on the sand, with nothing floating or clipping.
  3. Build or upgrade Tank Factory (West Yard): L1-2 shows the store garage and tanks, L3 the factory; the BUILD console still works; Silo / Refinery the same.
  4. FPS stays OK while you move around the map; if anything looks wrong, set `WE_StorePropsOff` on Workspace (or Enabled=false) and the Part builds return.
## v131 (Code Bot Roblox, 2026-09-30 ~11:18 Dublin): ship claude-bud JOB 33 rebirth overhaul + JOB 34 achievements — LAUNCHED FOR EVERYONE — FAST TRAVEL STILL OFF — MAP-REDESIGN KEPT — place version 129
- **WE_Build 131**. Code commit `7dd1667`. Open Cloud HTTP 200 `versionNumber=129`. PreferMesh OFF; WE_Building* untouched; admins stay off leaderboards (unchanged). Fast travel stays REMOVED (`MapConfig.FastTravelEnabled = false`). MAP-REDESIGN (v129) kept.
- **FF-merge** `origin/claude/desktop-bud` tips `f763276` (JOB 33) + `50d19b8` (JOB 34) onto phase-7-polish (was `b23f7f7` v130).
- **Launch flips (per Claude handoff "To launch"):**
  - `RebirthConfig.Live.OwnerFirst = false`; `ZonesLive = true`; `WeaponsLive = true` (rebirth zones, nukes, guns, vehicles, perks, trims, pacing, screen live for everyone).
  - `AchievementConfig.Live.OwnerFirst = false` (21 achievements + Missions ACHIEVEMENTS page + chat shout-outs live for everyone).
  - **BadgeIds stay 0** — `docs/BADGES.md` lists names/descriptions for Creator Hub; creating badges costs Robux (owner call). Server awards only non-zero ids.
- **JOB 33:** 7 rebirth annex zones (Tank Factory / Silo / Artillery / Drone Hangar / Elite Barracks / Oil Refinery / Bunker), silo nukes (shared PvP ApplyRadiusDamage, never near bases), land vehicle + gun grants, perks, rank banners/titles, richer rebirth screen, pacing MinLevelFor = 40+4/rebirth.
- **JOB 34:** 21 once-only achievements, quiet backfill, popup + reward, rate-limited TextChatService shout-outs, big banners, Missions > ACHIEVEMENTS page, ACTIVITIES header stack fix.
- **Checks:** BuyPathStatic PASS=6675 FAIL=0; claude_bud_job33/34 pins; run_rebirth_test 0 failed; run_achievement_test 0 failed; codebot_v131; rojo ok.
- **Phone tests (Migrate to Latest Update):**
  1. Rebirth at a high enough level: GAIN shows new zone + soldiers + starting cash; NEXT REBIRTHS preview; after confirm, annex yard appears outside the plot with BUILD console (not on a road).
  2. Build Tank Factory L1 at West Yard (Cash): income ticks; locked fences on later zones still read "Unlocks at Rebirth N".
  3. At R2+ with Silo: charge / rush a warhead; launch at plaza or outpost — everyone sees 10s countdown + ring; bases never targeted; shared PvP rules apply.
  4. Join: one toast "N achievements unlocked!" if backfill; Missions > ACHIEVEMENTS shows gold earned + locked progress bars; nothing overlaps at phone size.
  5. Get First Blood (kill enemy soldier): popup for you; other phone sees `[WAR EMPIRE] … drew first blood!` chat line; rejoin and kill again — no second popup/chat.
  6. MAP still tap-to-pin only (no TRAVEL); labels do not overlap.
## claude-bud JOB 34 (2026-09-30): achievements, chat shout-outs, badges (branch `claude/desktop-bud`)
**Found:** 3 server-only achievements (First Brick, War Chest, Sergeant) with a toast. There was no page, no chat line,
no badges, and no BadgeService code anywhere.

**Gating:** `AchievementConfig.Live` (`Enabled`, `OwnerFirst = true`). Off = MissionService's original 3-achievement
path, unchanged. **To launch:** Code Bot sets `OwnerFirst = false`.

**What it does** (`AchievementConfig`, `Services/AchievementService`, `Controllers/AchievementController`, the Missions
panel)
- **21 achievements**, each fires once per player:
  - saved in the existing `profile.Achievements` map;
  - unlock times in the new additive field `AchievementsAt`.
- **Progress reads counters the game already keeps:**
  - `Stats.TotalCashEarned` and validated PvP kills `LB.Kills`;
  - `Prestige` and `BaseUpgrades.CommandCenter`;
  - `Stats.TerritoriesCaptured` / `PlazaCaptures`;
  - `Soldiers`, `DailyLogin.Streak` and `Level`;
  - `NukeStats.Launched`: the counter already existed but nothing wrote it, so NukeService now increments it on launch.
  - The first NPC kill and the weekly #1 crown are events.
- **Earner:** a popup + sound + the small reward. Cash / Gold / XP are paid server-side with reason "achievement".
- **Whole server:** one styled TextChatService system line, e.g. `[WAR EMPIRE] shaunie6 just REBIRTHED for the 3rd time!`.
  - Big ones (every rebirth, $100M, Plaza capture, nuke, weekly #1) also show a short top banner for everyone except
    the earner, who has the popup.
  - Rate limited: one line per 3 s per server; a player's lines within 6 s merge into "(+N more)"; small lines drop
    past 6 queued.
- **First check of an old profile:** what he already reached is granted QUIETLY: rewards, badges and one toast
  ("7 achievements unlocked!"), with no popups or chat lines. So launching to everyone does not flood chat.
- **Badges:** `BadgeId` per achievement, all 0. **Code Bot creates them from `docs/BADGES.md`** (names, descriptions,
  icon ideas) and fills the ids.
  - The server awards only a non-zero id: `UserHasBadgeAsync` first, pcall, 3 retries.
  - They are re-synced once per session on join, so a failed award is retried.
- **Page:** Missions panel > ACHIEVEMENTS (below the daily missions). It shows earned (gold) and locked rows with
  progress bars and rewards. Opening the panel refreshes it (`RequestAchievements`, gated and rate limited).
- **Analytics:** `ACHIEVEMENT_UNLOCKED` { id, backfill } per unlock.
- **Owner / admin:** they earn and are announced like anyone. They stay off the leaderboards, so they can never be
  crowned.
- **Also fixed:** the Missions panel ACTIVITIES header (JOB 31) stacked up a copy on every refresh.

**Checks**
- `tools/checks/claude_bud_job34.py` (29 pins).
- `tools/sim/run_achievement_test.py`: 190 checks on the real service, config, ProfileSchema.Migrate and client
  format:
  - quiet backfill; each fires once;
  - popup + reward + ONE FireAllClients chat line per unlock;
  - a save + Migrate + fresh service instance fires nothing again;
  - NPC kill / crown / player-kill events; rebirth lines (5th milestone, 6th still announced, never twice);
  - rate limit merge / gap / drop;
  - badge retry and "already owned".
- BuyPathStatic PASS=6672 FAIL=0; remote audit OK; rojo ok; all sims 0 failed; no new LSP errors.

**Test ON HIS PHONE (owner + a second phone/account in the same server)**
1. Owner joins and gets one toast "N achievements unlocked! See Missions" (the backfill). The second player sees NO
   chat lines from it.
2. Owner opens Missions and scrolls down to ACHIEVEMENTS: gold earned rows, locked rows with bars (e.g. Grand Army
   12 / 50). Text is readable at phone size and nothing overlaps.
3. Owner kills an enemy soldier at an outpost or site.
   - Owner: popup "ACHIEVEMENT UNLOCKED · First Blood · +$500 +25 XP" with a sound.
   - Second player: chat shows `[WAR EMPIRE] shaunie6 drew first blood!` in colour.
4. Owner rebirths (or launches a nuke once R2 + silo are built).
   - Second player: the gold chat line AND a short banner at the top ("just REBIRTHED for the Nth time!").
   - Owner: the popup only.
5. Owner leaves and rejoins, then repeats step 3. No popup and no chat line (it fired once); the page still shows it
   earned.
6. Second player: no popup and no page (not live for him yet), but he does see the owner's chat lines.
7. Chat stays readable: several unlocks in a few seconds come out as one line "(+N more)".
## claude-bud JOB 33 (2026-09-30): rebirth overhaul (branch `claude/desktop-bud`)
**Found:** only PrestigeService (+10% cash, +50 gold, vehicle grants) ran. Zones, nukes, rebirth guns, perks, trims and
titles were config only, with no service, structures or layout. The admin commands for RebirthExpansionService /
NukeService pointed at services that did not exist.

**Gating.** Everything below goes through ONE owner-first gate: `RebirthConfig.Live`, with `OwnerFirst = true` and
per-part kill switches for Zones, Nuke, Weapons, Vehicles, Perks, Trims, Pacing and Screen.
- `ZonesLive` / `WeaponsLive` stay false (codebot_v101) and now mean "published for everyone".
- **To launch:** Code Bot sets `OwnerFirst = false` and those two to true.

**1. 7 rebirth zones** (`RebirthZonesConfig`, `RebirthZoneService`, `Modules/RebirthZoneBuilder`)
- **Placement:** the plot is full, so each zone is a 74 x 60 annex yard attached OUTSIDE the plot, on the side its name
  says:
  - West Yard / West Battery / West Flank on the west;
  - East Yard / Refinery Row on the east;
  - Strategic Yard / Drone Bay at the rear.
- **Checked once per plot:** procedural decor inside the yard is cleared; a road, POI, site or anything else blocks
  that one annex (logged, never built on top).
- **Visuals:** the curbs are in the base's trim colour.
- **Locked:** a fence and "Unlocks at Rebirth N".
- **Reached:** a yard with a BUILD console. Levels 1-3 visibly add structures (276 parts for all 7 at level 3).

| Zone | Opens at | Building | What it does (L1 / L2 / L3) |
|---|---|---|---|
| West Yard | R1 | Tank Factory | +$150 / 350 / 700 per tick |
| Strategic Yard | R2 | Nuclear Silo | 1 / 2 / 3 warheads, 60 / 45 / 30 min each |
| West Battery | R3 | Artillery Battery | missile reload -90 / 180 / 270 s, + income |
| Drone Bay | R4 | Drone Hangar | drones empty your ATM every 60 / 40 / 25 s, + income |
| East Yard | R5 | Elite Barracks (2-4 storeys) | +5 / 10 / 15 soldiers, + income |
| Refinery Row | R6 | Oil Refinery | +$250 / 600 / 1200 per tick |
| West Flank | R8 | Bunker Complex | +120 / 240 / 360 s raid shield, + income |

- **Paying:** Cash at the console ("rebirthzone_<Id>", no purchase XP). Levels are kept through rebirths. No Robux.

**2. Nuclear Silo + nukes** (`NukeService`, `NukeController`; numbers tied to NukeConfig)
- **Charging:** warheads charge over time; RUSH finishes one for $4,000 per minute left.
- **Launching:** use the silo console's NUKE prompt. Targets are the Central Plaza, an outpost or an enemy site, each at
  least 360 studs from every base. Bases are never nuked, so no base can be one-shotted.
- **Countdown:** every player gets a 10 s countdown banner, a red ring on the target and a siren. The sound id is empty
  until the owner sets `SirenSoundId`; the siren is visual only until then.
- **Blast:** one `CombatService.ApplyRadiusDamage` (radius 150, 260 at the centre down to 15%). That is the shared PvP
  rule: novice shields, spawn protection, clan allies and pvp-off are all respected, and NPCs are hit.
- **Cooldowns:** 30 min per player (saved, so a rejoin does not reset it) and 5 min per server.

**3. Vehicles**
- The order bug is fixed: Frigate R16 now comes before Cruiser R18, and the track is sorted.
- Land vehicles fill the gaps: Recon Buggy R6, Command Vehicle R9, Light Tank R11, Mortar Carrier R13, Medium Tank R14,
  Heavy Tank R17, Battle Tank R19. Every rebirth 1-20 now gives something.
- Granted vehicles are usable at once, at any level or base (`GrantedVehiclesIgnoreRunGates`).
- Rebirth-only tank skins were not done.

**4. 7 rebirth guns** (WeaponConfig; granted at R1 / 3 / 5 / 7 / 9 / 12 / 15)
- Vanguard Carbine, Tempest SMG, Warden Shotgun, Longshot DMR, Talon Sniper, Havoc Launcher, Sovereign Rifle.
- Each is a current gun's frame and model at x1.10-1.17 DPS. They are never sold and usable at level 1.

**5. Perks**
- +2 soldiers per rebirth (cap +40), on the server cap and the client mirror (`WE_RebirthArmyBonus`).
- Starting cash steps from $25k (R1) to $250k (R20).
- Gold 50 + 10 per rebirth (max 250).
- +10% cash per rebirth is kept.

**6. Visible rank**
- Two trim-coloured banners at the base gate.
- A title above the head (Veteran / Commander / General ..., MaxDistance 40).
- The base sign reads "COMMANDER R3 · LV 12 · ARMY 20".

**7. Rebirth screen**
- The GAIN column adds the new zone, the soldiers and the starting cash.
- The RESET column shows the new starting cash.
- A "NEXT REBIRTHS" preview shows the next 3.
- The celebration (Juice) runs as before; the new zone appears on rebuild.

**8. Pacing** (`tools/sim/rebirth_pacing_sim.py` on the real configs)
- Without a change, later lives got SHORTER: 33.6 min falling to 22 min by life 8.
- Now `MinLevelFor = 40 + 4 x rebirths` (cap 90). Minutes per life:

  | Life | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
  |---|---|---|---|---|---|---|---|---|---|---|
  | Minutes | 33.6 | 34.1 | 37.4 | 41.5 | 46.8 | 52.9 | 60 | 68 | 77 | 87 |

- Analytics: `rebirth_available` / `rebirth_opened` / `rebirth_confirmed`, with level and this life's play minutes.

**9. Phone performance**
- The zones' small props (tanks, drones, guns) are under QualityGovernor, so they hide far away on LOW.
- Buildings are never culled.
- About 40 parts per zone at level 3, 276 for all 7.

**Checks**
- tools/checks/claude_bud_job33.py (16 pins).
- `tools/sim/run_rebirth_test.py`, which runs the real code:
  - every zone at levels 0-3 grows, stays in its yard, and every cluster is at most 64 studs (this caught the 74-stud
    yard and fence, now split);
  - nuke charge maths; 10 targets, none near a base;
  - zone effects and upgrades (a locked zone refused, one spend per level, max 3);
  - the sorted track; every granted id exists; the pacing; the next 3; the GAIN / RESET lines;
  - gun DPS within +20%.
- All earlier sims still pass. BuyPathStatic PASS=6620 FAIL=0; remote audit OK; rojo ok; no new LSP errors.
- **Retired pins (claude-bud comment + replacement):** the XP SpendCash site pin now lists 10 sites; the new
  `rebirthzone_` and `nuke_rush` spends pay no XP.

**Needs the owner**
- `DevProducts.RebirthKeepBase` is LIVE (Id 3714663721, 50 R$, sold from the Rebirth panel). The brief said it was Id 0
  / off sale. I did not change it.
- Set `RebirthZonesConfig.Nuke.SirenSoundId`.

**Test ON HIS PHONE (owner account, R0 -> R3)**
1. At R0 (use `/setprestige` or rebirth): locked fences with "Unlocks at Rebirth N" round the base.
2. Rebirth to R1:
   - the West Yard opens;
   - start cash is $25k, with +60 gold and +2 soldiers;
   - the gate banners (Bronze) and the title "VETERAN" appear;
   - the Vanguard Carbine is in the hotbar, and the Scout Car spawns at Lv 1.
3. BUILD the Tank Factory, then UPGRADE twice: the hangar, then containers and a tank, then a chimney and a third tank.
   The income per tick goes up.
4. At R2 build the Silo, wait for or RUSH a warhead, then NUKE > LAUNCH at the Central Plaza. Everyone sees the
   countdown banner and the red ring, then the flash. Players there take damage; novice or shielded players are spared.
5. At R3 build the Artillery Battery (the missile reload shortens). The rebirth screen shows GAIN (zone, soldiers,
   cash) and NEXT REBIRTHS. Level 52 is needed for the next rebirth.
## v130 (Code Bot Roblox, 2026-09-30 ~10:48 Dublin): ship claude-bud JOB 32 enterable plaza + LosRule + army holds at door — FAST TRAVEL STILL OFF — MAP-REDESIGN KEPT — place version 128
- Cherry-picked Claude `e6a1b56` (JOB 32) onto phase-7-polish (v129 tip `937d197`). **WE_Build 130**. Code commit `14a7c72`. Open Cloud HTTP 200 `versionNumber=128`. PreferMesh OFF; WE_Building* untouched; admins stay off leaderboards (unchanged).
- **Fast travel stays REMOVED** (v127 owner request). Kept `MapConfig.FastTravelEnabled = false`; no `RequestFastTravel`, no TRAVEL button. **MAP-REDESIGN (v129) kept** — do not revert square map / MapLabelLayout / title-case pills.
- **JOB 32:** PlazaBuildingsConfig + PlazaHouse (4 enterable plaza buildings); CombatConfig.LineOfSight + Shared/Util/LosRule (one shot/sight rule); ArmyConfig.Indoors + Modules/Enterables (army holds at the door). Kill switches: PlazaBuildingsConfig.Enabled, LineOfSight.Unified as Claude wrote.
- **Pins:** `tools/checks/claude_bud_job32.py` + `tools/sim/run_plaza_test.py`; `tools/checks/codebot_v130.py` (WE_Build 130, JOB 32 files, no fast travel, PreferMesh OFF, MAP-REDESIGN kept). Retired codebot_v129 WE_Build pins; BuyPathStatic / v110 / v113 WE_Build pins bumped to 130. **BuyPathStatic PASS=6623 FAIL=0**; plaza test 0 failed; rojo ok.
- Do **not** re-add fast travel. Do **not** turn PreferMesh on. Do **not** touch WE_Building*. Do **not** revert the v129 map UI.
- **Phone tests (owner account; Migrate to Latest Update):** see JOB 32 list below (enter plaza door / ramp / ladder / roof; roof vs ground shooting; window gaps; army holds at door; phone thumbstick).

## claude-bud JOB 32 (2026-09-30): enterable Central Plaza buildings (branch `claude/desktop-bud`)
**Why:** every Crossroads Town building was a solid invisible box with Roblox-made mesh fronts, so none could be entered.

**1. Enterable buildings** (`PlazaBuildingsConfig`)
- The 4 buildings facing the plaza flag (NE_E1, SW_S1, NE_N1, NW_W1) are now the **PlazaHouse** (55 parts, same
  footprint and frame):
  - **Ground floor:** a 6 x 8 door; the windows are open gaps (no glass); crates inside for cover.
  - **Stair:** a ramp up the right wall (43.5 degrees, walkable) with a rail round the stair hole.
  - **Upper floor:** windows on every side.
  - **Roof:** a ladder (TrussPart) through a hatch, a 3.2-stud parapet (shoot over it, duck behind it) and two sandbag
    rows.
- **Budget:** the Town budget and layout are unchanged: the planner and caps count the TownHouse, and the extras come
  out of `MaxExtraParts` (240; 4 x ~51 used).
- **Kill switch:** `PlazaBuildingsConfig.Enabled = false` builds the solid TownHouse rows again.

**2. The ONE line-of-sight / shot rule** (`CombatConfig.LineOfSight`, `Shared/Util/LosRule`)
- **The rule:** a solid (CanCollide) part stops shots and blocks sight; a non-colliding part never does; water never
  does. A shot can also stop on a character's limbs (its target).
- **Who uses it:**
  - player guns, aim assist, lag-tolerance claims and splash (CombatDamage);
  - projectiles and premium vehicle guns;
  - NPCs, all 3 army sight rays, base turrets and gate / base guards (GateDefense hasLos);
  - the client shot preview.
- **Effect:** shots through window gaps and from roofs work, and nothing shoots through walls.
- **The only behaviour change:** player bullets now pass non-colliding decor, as NPCs, army and turrets already did.
- The v124 pvpBlock stays the one hostility rule.
- **Kill switch:** `Unified = false` restores each shooter's old ray settings.

**3. The army** (`ArmyConfig.Indoors`)
- While the owner is inside or on the roof of a registered building (`Modules/Enterables`), FOLLOW plans round a street
  point 10 studs out from the door, facing the building. The block forms in the street.
- The owner's speed counts as zero while he is held, so no jump / far / pace recovery fires: no teleport, snap or
  PivotTo was added, and no unit climbs the stair.

**Also fixed (JOB 31 bug found here):** WorldPOI and WorldFill measured a cluster's ACTUAL parts against their caps, so
JOB 31's detailed props inside POIs could push rows over the cap and drop them. Now:
- `WorldKits.ExtraParts(cluster)` tracks the extras;
- `Finish` reports the plain count;
- WorldPOI's budget test and WorldFill's `countParts` subtract the extras.

**Existing pins kept:**
- WorldPOI's pinned Add line is unchanged; rows are flagged with the cluster attribute `WE_Enterable`.
- squadfair's frozen line is unchanged; the rule is applied on the next line.
- Code Bot v115's Plan call is kept on the normal path.
- My own PREMIUM pin is updated.

**Checks**
- tools/checks/claude_bud_job32.py (14 pins, including the ladder span).
- `tools/sim/run_plaza_test.py`:
  - REAL WorldKits PlazaHouse: 55 parts; the door and all 6 checked windows are empty gaps; ramp slope, foot room and
    stair hole; roof hatch clear; parapet 3.2 above the roof; inside the core;
  - Enterables inside / roof / street and the door point;
  - kill switch;
  - REAL LosRule on a scripted ray world: a shot steps over a sign to the wall, hits a limb; sight passes the limb;
    params are never grown; off = the old raycast.
- All earlier sim tests still pass. BuyPathStatic PASS=6568 FAIL=0; remote audit OK; rojo ok; no new LSP errors.

**NOT done here:**
- The 2-player Studio test (I cannot run Studio): steps below.
- The optional rooftop king-of-the-hill.

**Test (2 players, Studio Start Server + 2, then phones)**
1. Walk to a plaza building facing the flag (e.g. NE_E1, east of the flag). Go in through the door, up the ramp, climb
   the ladder through the hatch to the roof.
2. **Roof vs ground:**
   - Player 1 on the roof, player 2 on the plaza. Both can shoot each other over the parapet.
   - Player 1 ducks behind the parapet: player 2's shots stop on it.
   - Nobody can shoot through a wall. Shots through the window gaps work, both ways.
3. Enemies (the plaza bank guards / an NPC / a base turret) see and shoot a player at a window or on the roof, but not
   through a wall.
4. Player 1 with an army on FOLLOW goes inside: the army lines up in the street in front of the door (it does not walk
   in or teleport). Going up to the roof: same. Coming out: it follows as normal.
5. The door and ramp work on a phone with the thumbstick; the ladder climbs by walking into it.
## v129 (Code Bot Roblox, 2026-09-30 ~10:18 Dublin): MAP-REDESIGN — the world map UI was redesigned at the owner's request — place version 127
- **Claude: the map UI was redesigned on purpose (Shaun: "labels overlap, it is not beautiful"). Do NOT revert it** to the v127/v128 right-half canvas, ALL CAPS labels, flat brown square or loose outpost diamonds. Build on it.
- **WE_Build 129**. Code commit `1b6ae52`. Open Cloud HTTP 200 `versionNumber=127`. PreferMesh OFF; WE_Building* untouched; fast travel still REMOVED; MapConfig OwnerFirst unchanged.
- **Layout:** square map left of centre (as tall as the panel) + slim info card on its right (WORLD MAP, the selected place, GO / CLEAR PIN, icon legend, zoom hint). `fitLayout()` sizes it in v from the panel.
- **Look:** sea gradient, sand land gradient + shore line, 500-stud grid, the WaterConfig.RoadEnds roads, subtle zone patches, compass rose (bottom-left), gold frame + corner brackets, dark vignette. Icons: `makeIcon()` UICorner + UIStroke circles with a white inner shape, colour by family (`MapConfig.KindGroup`: Town / Military / Industry / Wilds / Site), fixed sizes (`MapConfig.Icon`). Outposts are owner badges on their area icon. No Rotation inside the clipped map (the you-arrow hides when off the zoomed view).
- **Labels:** new pure module `Shared/Util/MapLabelLayout.luau`: title-case pills (dark semi-transparent, text stroke), placed by a collision pass (8 slots + side slides + 2 outer rings = 32 candidates, clamped in the visible window, max slide 40 v), priority `MapConfig.LabelPriority` (your base 0, towns / sites / forts 1, outposts / camps / rigs 2, depots + rig shore bases 3; `LabelRank` inside a priority). A tapped place shows its label on top (`PlaceFocus`). Short map names in `MapConfig.LabelShort` (the card keeps the full name).
- **Zoom:** 2 levels (`MapConfig.ZoomLevels` / `ZoomMaxPriority` = {2, 3}): 44 px + / - button (top-left), pinch, mouse wheel; drag pans at zoom 2; labels re-run on open, resize, zoom, pan end and when the live site / base set changes.
- **Kept:** tap-to-pin on the ONE ObjectiveMarker tracker, GO, CLEAR PIN, legend (now icons), your arrow, RequestMapLive feed unchanged (server untouched).
- **Tests:** `tools/sim/run_map_layout_test.py` runs the REAL MapLabelLayout on the REAL POIs / outposts / JOB 31 sites / 10 plots / bank (phone 470 v, small 420 v, desktop 640 v; zoom 1 + nine zoom-2 pans): **10058 checks, 0 failed** (no pill overlaps, none over an icon or control, all inside the map, title case). Phone zoom 1 shows 15 labels; every label appears in some zoom-2 view (small phone: Hawk Checkpoint is tap-only). Mock: `tools/sim/render_map_mock.py` → /workspace/map_mock.png (+ map_mock_zoom2.png). MapAreas test 0 failed. **BuyPathStatic PASS=6600 FAIL=0**; rojo ok.
- **Pins:** `tools/checks/codebot_v129.py` (WE_Build 129 + redesign + layout test + no fast travel + PreferMesh OFF). Retired: codebot_v128 WE_Build pins; claude_bud_job30 "canvas on the right" pin. BuyPathStatic / v110 / v113 WE_Build pins bumped to 129.
- **Not tested live:** the real Roblox render (fonts, UIScale, pinch) — only the offline layout + mock. Live crate / job dots are not label obstacles (they move).
- **Phone tests (owner account; Migrate to Latest Update):** (1) open MAP: square map + card, labels title case, none overlapping, Fort Sandhold / Fort Ironclad fully inside; (2) tap + (or pinch out): more labels (sites, depots) appear, drag pans, tap - to go back; (3) tap a small icon with no label: its card + a gold-outlined label appear; GO pins it on the ONE yellow tracker, CLEAR PIN removes it; tap open ground pins at once.

## v128 (Code Bot Roblox, 2026-09-30 ~09:53 Dublin): ship claude-bud JOB 31 real prop detail + 8 sites + activities — FAST TRAVEL STILL OFF — OwnerFirst — place version 126
- Cherry-picked Claude `ca9d294` (JOB 31) onto phase-7-polish (v127 tip `8b75615`). **WE_Build 128**. Code commit `ae9aa30`. Open Cloud HTTP 200 `versionNumber=126`. PreferMesh OFF; WE_Building* untouched; admins stay off leaderboards (unchanged).
- **Fast travel stays REMOVED** (v127 owner request). Kept `MapConfig.FastTravelEnabled = false`; no `RequestFastTravel`, no TRAVEL button, no MapService teleport handler. Took JOB 31 `SiteKindInfo` + site map overlays only. `codebot_v128.py` pins WE_Build 128 + no-fast-travel.
- **JOB 31 shipped OwnerFirst** (UserId 470626172 + Studio): WorldDetailConfig, WorldSitesConfig, SiteActivityConfig. Flip OwnerFirst false after Shaun signs off phone / FPS tests.
- New: WorldDetailConfig + detailed WorldKits; WorldSitesConfig + WorldSites (8 sites); SiteActivityConfig + SiteActivityService (5 activities); MissionController ACTIVITIES; MapController site zones; checks `claude_bud_job31.py` + sim tests.
- **Pins:** `tools/checks/claude_bud_job31.py` + sim tests; `tools/checks/codebot_v128.py` (WE_Build 128, no-fast-travel, PreferMesh OFF, OwnerFirst retained). Retired codebot_v127 WE_Build pins; BuyPathStatic / v110 / v113 WE_Build pins bumped to 128. **BuyPathStatic PASS=6585 FAIL=0**; kit detail 0 failed; sites 0 failed; rojo ok.
- Do **not** re-add fast travel. Do **not** turn PreferMesh on. Do **not** touch WE_Building*.
- **Phone tests (owner account; Migrate to Latest Update):** see JOB 31 list below (tank wreck detail, 8 map sites, ACTIVITIES START, sniper deck, supply cache, 2-player garrison wake, FPS note).

## claude-bud JOB 31 (2026-09-30): real detail + fill the map (branch `claude/desktop-bud`)
**1. Audit.** Every world prop outside the bases is a plain-Part WorldKits builder. The worst offenders:

| Prop | Plain build |
|---|---|
| Tank wreck | 5 boxes |
| Truck wreck | 5 |
| Field gun | 3 |
| Sandbag line | 1 block per 5 studs |
| Jersey barrier | 1 box |
| Watchtower | 8 |
| Bunker | 3 |
| Tent | 3 |

Only the car wreck, crates, the town buildings and flora have Roblox-made mesh overlays. No Code Bot asset IDs were
supplied for this job, so everything below is properly built from Parts (our own designs, no store models).

**2. Detail** (`WorldDetailConfig`; `WorldKits.Add` builds these instead of the plain kits):

| Prop | Parts | What's in it |
|---|---|---|
| Tank wreck | 21 | hull + sloped glacis, 2 tracks, 6 road wheels, 2 fenders, turret + bustle + mantlet, barrel + muzzle brake, hatch, jerry can, a thrown track link |
| Truck wreck | 15 | chassis, 5 wheels, bed, sides, fallen tailgate, cab, windscreen, hood, grille, bumper |
| Field gun | 10 | |
| Sandbags | 2 courses | lines, arcs, and the nest (which adds an MG on a tripod and an ammo box) |
| Jersey barrier | 5 | the real sloped profile |
| Watchtower | 14 | cross braces, side rails, deck sandbags |
| Bunker | 9 | concrete roof, firing slits, roof sandbags, vent; the runtime door is kept |
| Tent | 7 | ridge pole, groundsheet, crate |

- **Budget:** the planner (Footprint) and every section cap still count the plain kit, and Add returns the plain count,
  so no layout or cap moves.
- **Growth ceiling:** the extra parts come out of ONE allowance, `MaxExtraParts` = 900. When it is spent, the rest build
  plain. Live log: `[WorldDetail] detailed kits=N extra=N`; attribute `Workspace.WorldFill.WE_DetailExtra`.
- **Kill switch:** `WorldDetailConfig.Enabled = false` builds exactly the old kits.

**3. Fill the map** (`WorldSitesConfig` + `Modules/WorldSites`, built right after WorldFill)
- **8 named sites** (fictional names) between the plaza, the bases and the POIs:
  - 2 camps (Camp Viper, Dust Camp);
  - Dry Well Village (ruins + well);
  - Pump Station 7 (pumpjacks, fuel tank, pipes);
  - Kestrel Supply Depot (containers, crates, fence);
  - Hawk Checkpoint;
  - Overwatch Ridge (sniper tower, bunker);
  - Anvil Scrapyard (tank wrecks).
- **Placement:** each site stands only on clear ground: no parts inside its radius (roads, buildings and props block),
  at least 200 studs from every base, outside every named area, on dry land. Otherwise it searches rings up to 260
  studs.
- **Budget:** capped at 240 plain parts; 177 are planned.
- **On the world map:** the sites show as labelled zones with a card listing their activities.

**4. Activities + enemy patrols** (`SiteActivityConfig` + `SiteActivityService`, OwnerFirst)
- The Missions panel has a new **ACTIVITIES** section (START / GO, time left, reward):

  | Activity | What you do | Limit | Reward |
  |---|---|---|---|
  | Clear Camp Viper | kill 4 soldiers | 4 min | $6k |
  | Capture Kestrel Depot | clear 3 guards, then hold the zone 30 s | | $8k |
  | Defend the Convoy | hold Hawk Checkpoint through 3 waves; leaving for 8 s fails it | | $7k |
  | Find the Supply Cache | a crate hidden at a random site; only you can open it, close by | | $4k + 5 gold |
  | Rooftop Sniper | 5 posted targets 90-150 studs from the Overwatch tower; only kills made **on the deck** count, and an off-deck kill stands a new target up | | $7.5k |

- One activity at a time per player, with 7-10 min cooldowns. START points the GO line at the site.
- **Garrisons:** posted soldiers at the camps, the ridge and the scrapyard. They wake when an owner-first player is
  within 250, sleep beyond 380, stay leashed to the site, and respawn 3 min after being cleared. They use normal NPC
  slots, never the over-cap.
- A truly roaming patrol between sites (new AI) is NOT built: see NEXT.

**5. Phone performance**
- The detailed props and site decor are small decor, so QualityGovernor still hides them beyond 220-320 studs on the
  LOW tier.
- Buildings and structures (towers, camps, ruins, checkpoints) are never culled (the JOB 27 rule and NeverHideKinds).
- The part increase is capped: at most 240 (sites) + 900 (detail extras).
- **NOT measured:** FPS on a low-end phone profile needs a device. Studio's emulator is not a phone.

**Checks**
- tools/checks/claude_bud_job31.py (16 pins).
- `tools/sim/run_kit_detail_test.py`: runs the REAL WorldKits in the Luau CLI and checks, for every detailed kit:
  - the exact part counts;
  - Add returning the plain count;
  - road-side collidables at z >= 0 and nothing below the floor;
  - the footprint within 2.5 studs of the plain one;
  - the allowance and kill-switch fallbacks.
- `tools/sim/run_sites_test.py` (115 checks):
  - REAL WorldSites placement: all 8 sites clear of plots and areas, every cluster <= 64 across, 177 parts;
  - REAL SiteActivityService on stubs: pays once, cooldown, sniper deck rule, cache owner and distance rule, convoy
    zone fail, NPC cleanup.
- BuyPathStatic PASS=6545 FAIL=0; remote audit OK; rojo ok; no new LSP errors.

**Test ON HIS PHONE**
1. Drive to the desert tank wreck (a Fill2 tank yard, or Fort Ironclad): it reads as a tank (tracks, wheels, turret,
   barrel). Sandbags have two courses, jersey barriers are sloped, watchtowers are braced.
2. Open the map: 8 new orange-ish zones with names. Tap Camp Viper: the card says "Activity: Clear Camp Viper".
3. **Missions → ACTIVITIES → START "Clear Camp Viper"**: the GO line points there. Kill the 4 soldiers: "+$6,000".
   START again shows the cooldown.
4. **Rooftop Sniper:** climb the Overwatch tower ladder. Shoot targets from the deck (they count), then one from the
   ground: a new target stands up. 5 deck kills pays.
5. **Find the Supply Cache:** follow GO to the site and search for a green crate. Hold Open to get "+$4,000". A 2nd
   player cannot open it.
6. **2 players:** player 2 walking into Camp Viper gets shot by the garrison only after player 1 (owner) woke it (owner
   first).
7. Note FPS in the desert before and after on a mid-range phone.

## v127 (Code Bot Roblox, 2026-09-30 ~09:45 Dublin): ship claude-bud JOB 30 world map + areas + tap-to-pin — FAST TRAVEL REMOVED (owner request) — place version 125
- Merged Claude `3471f3d` (JOB 30) into phase-7-polish (v126 tip `a9e1135`). **WE_Build 127**. PreferMesh OFF; WE_Building* untouched; admins stay off leaderboards (unchanged).
- **Fast travel is REMOVED at Shaun's request.** He wants tap-to-pin only, so players can see where they want to go and then get there themselves. **Claude must NOT re-add fast travel** in any form: no TRAVEL button, no teleport remote, no hint or tutorial copy.
  - Gone: the `MapConfig.FastTravel` block (it is now `FastTravelEnabled = false`, and nothing reads it as true), `RequestFastTravel` (Constants, RemoteSetup, SecurityConfig schema), `MapService.FastTravel` with its handler, cooldown, `TravelIn` field and the StreamPrefetch / TeleportToPlot path, and the MapController TRAVEL button with its refusal copy.
  - MapService now has exactly one handler: the read-only `RequestMapLive`.
  - `tools/checks/codebot_v127.py` fails the build if any of that comes back.
- **Kept:** the full-screen map (MAP tile / M; Missions moved to N), the named areas, the live bases / outposts / bank / crates / jobs, the area card with **GO**, tap open ground to pin, and **CLEAR PIN**. The pin is the ONE yellow tracker (`ObjectiveMarker.ShowWith { Pin = true }`, clears at 15 studs).
- **OwnerFirst retained:** `MapConfig.OwnerFirst = true` (UserId 470626172 + Studio). Flip it to false after Shaun signs off the phone tests.
- Code commit `5ce5f8b` (merge of `3471f3d`). Open Cloud HTTP 200 `versionNumber=125`.
- **Pins:** claude_bud_job30.py was updated (fast-travel pins retired; FastTravelEnabled=false pinned). codebot_v127.py covers WE_Build 127 and fast travel OFF. The codebot_v126 WE_Build pins are retired, and the frozen BuyPathStatic / v110 / v113 WE_Build pins are bumped to 127. **BuyPathStatic PASS=6549 FAIL=0**; MapAreas Luau test 0 failed; rojo ok.
- **Phone tests (owner account; Migrate to Latest Update):**
  1. Tap MAP: the map fills the screen, with your arrow on your base and the town labelled. The buttons are only GO / CLEAR PIN, with **no TRAVEL anywhere**.
  2. Tap Crossroads Town: its card shows. Tap GO: the map closes and the yellow line and compass point there. Walk to it: the pin clears at about 15 studs.
  3. Tap open desert: the pin drops. Start a mission GO: the pin stays. Reopen the map and tap the pin (or CLEAR PIN): it is gone.

## v126 (Code Bot Roblox, 2026-09-30 ~09:30 Dublin): paid speed feels real — Speed Boost x1.6, Speed Pass x1.4 — place version 124
- **Owner bug:** "the Speed Boost barely makes me faster". **Live proof** (Open Cloud Luau probe, read-only): shaunie6 (470626172) owns the Speed Pass (UserOwnsGamePassAsync 1998656357 = true) AND `Entitlements.SpeedBoost = true`. SpeedMultFor takes the higher one, 1.25, so he had WalkSpeed **20** (+4 studs/s, +25%). The Speed Pass he also owns added nothing. No admin override. MonetizationService (via MoveDebug.SetWalkSpeed) is the **only** server writer of a player's WalkSpeed. No armour or gun weight slowdown exists (ArmourConfig / WeaponConfig have no speed fields). CombatConfig WalkSpeed is NPC-only. Vehicles never write it. Respawn re-applies it (CharacterAdded +0.3 s).
- **Fix:** SpeedBoost WalkSpeedMult 1.25 -> **1.6** (25.6) "Run 60% faster, forever". ImpulseSpeed 1.15 -> **1.4** (22.4) "Run 40% faster, forever". MAX_WALK_SPEED_MULT 2 -> 1.75. The paid multiplier is now applied **after** any other WalkSpeed writer (X -> X x mult, capped at 28) and re-applied on seat exit. ArmyConfig Follow.CatchUp MaxSpeed 28 -> 40 (Follow2 x1.08 / max 50 and Follow3 max 40 already cover 27.6). AntiExploit has no speed check. Prices / Ids unchanged; no new Robux items.
- **Pins:** tools/checks/codebot_v126.py. Retired the old x1.15 / x1.25 / `base * mult` pins (BuyPathStatic, codebot_v123) and the codebot_v125 WE_Build pins. Frozen pins in BuyPathStatic / v110 / v113 bumped to 126. BuyPathStatic's CatchUp MaxSpeed range is now 20..40. **BuyPathStatic PASS=6524 FAIL=0**. Code commit `fab245f`. Open Cloud HTTP 200 `versionNumber=124`.
- **Phone tests (owner account; Migrate to Latest Update):**
  1. Join and run on flat ground: clearly faster than before. /movedebug shows `ws=25.6`.
  2. Get in a jeep, get out: still 25.6. Die / respawn: still 25.6.
  3. Walk with the army in FOLLOW for 30 s: the wedge keeps up, with no teleports.
- **Also (read-only):** /workspace/war-empire-shop-audit.md, a ranked Robux shop audit. Every price or new item there needs Shaun's OK.

## claude-bud JOB 30 (2026-09-30): world map + areas + tap-to-pin (branch `claude/desktop-bud`)
Kill switches: `MapConfig.Enabled` and `MapConfig.FastTravel.Enabled`. Both ship **OwnerFirst** (UserId 470626172 +
Studio test players); Code Bot sets `OwnerFirst = false` to launch.

**Opening it**
- A **MAP** rail tile (folded-map icon) opens a full-screen Modal panel. So does **M**, when keys are preferred.
- Missions moved to **N**. The tile hint "Missions [N]" and the Settings key sheet read the same config.
- The rail is now 5 + Codes + Map. Short phones wrap it to a 2nd column (5 + 2).
- The frozen BuyPathStatic pin "exactly 6 tiles" is retired with a claude-bud comment and a 7-tile replacement.

**What it shows**
- **Always drawn:** land, sea, and the **real zones** (`Shared/Util/MapAreas`): the 18 WorldConfig.POIs, each joined to
  the outpost inside it and to its garrison tier, plus the 2 offshore rigs as their own areas. 10 main areas are
  labelled.
- **Live, every 0.5 s and only while open**, from `RequestMapLive` (MapService):
  - **Bases:** every base; yours is green "YOU"; tap a base for "<Name>'s Empire" (`BaseSignService.TitleFor`, the
    sign's own string).
  - **Outposts:** yours green, enemy red, free gold.
  - **Other markers:** the bank ($), supply crates and the airdrop (labelled), and job spots (camps, posts, uplinks,
    cargo).
  - **You and your pin:** your arrow (position + facing), and your pin.
- **Area card:** tap an area to see its kind, the outpost bonus and owner, the enemy tier and the jobs inside it.
  - **GO** pins the tapped point.
  - **TRAVEL** shows when you hold that outpost, or on your base.

**Pin**
- Tap open ground to drop a pin at once.
- The pin is the ONE objective marker: `ObjectiveMarker.ShowWith(..., { Pin = true, ArriveStuds = 15 })`, with the same
  GO line and compass as missions. There is no second Beam.
- Additive ObjectiveMarker API: while a pin is set, other Show / ShowWith calls (missions, jobs, airdrop), a plain
  Clear() and Move() are ignored. ShowWith still calls ConsoleWaypoint.Clear().
- The pin clears on arrival, by tapping it again, or with **CLEAR PIN**.

**Fast travel** (server)
- Allowed to your own base (TeleportToPlot) or to an outpost you or your clan hold.
- Refused when:
  - the outpost is contested;
  - you are in combat (the server damage lock: any health drop in the last 5 s);
  - you are seated;
  - the 120 s cooldown is still running.
- The TRAVEL button shows the cooldown. A refusal reason shows in the card.

**Performance**
- The area layer is built once and cached.
- Markers are pooled frames moved by scale.
- One loop runs at 0.5 s while open; nothing runs while closed. No workspace scans or per-frame work on the client.

**Layout (worked out by hand; the HUD harness `check_hud.py` is not in the repo)**
- The tap canvas is a right-aligned square. Its left edge is at 54% (844x390), 54% (956x440), 55% (800x360), 41%
  (1180x820) and 44% (1920x1080) of the width, so it never enters the left-40% thumbstick zone.
- The GO / TRAVEL / CLEAR PIN buttons sit in the top third of the left column: their bottom is about 74 real px on
  844x390 (the top third is 130 px).
- Buttons are TouchMinV tall (44+ real px). Text is 14+ real px.

**Bug found while testing:** `TerritoryConfig.Territories` is keyed by Id. My first draft looped over it with
`ipairs`, which returns nothing, so no outposts showed. Fixed with `pairs`; the MapAreas test covers it.

**Checks**
- tools/checks/claude_bud_job30.py (16 pins).
- `tools/sim/run_map_test.py`: runs the REAL MapAreas plus the real configs in the Luau CLI. 20 areas, 0 failures:
  - every POI placed;
  - every outpost joined exactly once;
  - the plaza is in town;
  - the rigs are their own areas;
  - tap lookup works, including open ground.
- BuyPathStatic PASS=6526 FAIL=0. rojo ok.
- No new LSP errors in my files. MoveDebug's existing v123 error shows only because MapService pulls in StreamPrefetch.
- The world sim and the DataService harness are not in the repo.

**NOT verified on a device:** tap accuracy on a real screen, and how dense the labels look.

**Test ON HIS PHONE** (2 players):
1. Tap MAP. The map fills the screen, your arrow is on your base, the town is labelled and the bases are squares.
2. Tap Crossroads Town. The card shows "City and Central Plaza · Outpost: ... · +10% Cash ...". Tap GO: the map
   closes and the gold line and compass point there. Walk up to it: the pin clears at about 15 studs.
3. Tap open desert to drop a pin. Then start a mission GO: the pin stays (the pin wins). Open the map, tap the pin (or
   CLEAR PIN): it goes.
4. Capture an outpost, open the map, tap it, then TRAVEL: you land at its edge. TRAVEL again shows the cooldown. With
   player 2 shooting you, TRAVEL says "Not while under fire".
5. Player 2 opens the map: player 1's base shows as a square. Tap it: "<P1>'s Empire". Player 2's own base is green
   "YOU".
6. On PC, M opens the map and N opens Missions.
## v125 (Code Bot Roblox, 2026-09-30 ~09:15 Dublin): ship JOB 29 retention (FastStart, offline earnings, streak tomorrow, notif opt-in) — place version 123
- Fast-forward merged Claude `8cad44d` (JOB 29) onto phase-7 tip `a5b4ae0` (v124). **WE_Build 125**. PreferMesh OFF; WE_Building* untouched. **OwnerFirst retained** (`RetentionConfig.Live` — UserId 470626172 + Studio); do not flip to everyone until Shaun signs off phone tests.
- **JOB 29 — retention (OwnerFirst)**
  - **FastStart:** new players land ~7 studs at their Command Center console with a gold arrow; first BUILD pays +$1,500 once (`StarterPayoutDone`); `WE_Onboarding` holds nation picker / streak / welcome-back until CC done or 60 s. Funnel extended to 14 `AnalyticsService.Onboard` steps + `OnboardingSeconds`.
  - **Offline earnings:** `LastSeenUnix` → 25% of live passive × seconds away, cap 8 h, +10% Premium; paid into PendingCash (ATM); card "WELCOME BACK". No payout under 5 min / first join.
  - **Streak tomorrow:** tomorrow's reward on claim toast, Missions daily row, streak card, Missions strip; 7-day strip (days 3+7 gold); Day 7 ARMY BOOST ×1.25 for 30 min.
  - **Notifications:** opt-in 25 s after tutorial or Settings → NOTIFICATIONS → Game alerts; once/session, 7-day cooldown after decline; `docs/NOTIFICATIONS.md` + DataStore `WE_NotifyState_v1`.
- **Kill switches:** `TutorialConfig.FastStart.Enabled`, `EconomyConfig.OfflineEarnings.Enabled`, `DailyRewardConfig.ShowTomorrow` / `StreakCard.Enabled`, `RetentionConfig.Notifications.Enabled`. Launch later = set `OwnerFirst = false` on those blocks.
- **Pins:** `tools/checks/claude_bud_job29.py` + `tools/checks/codebot_v125.py` (WE_Build 125, OwnerFirst=true). Retired codebot_v124 WE_Build pins; bumped BuyPathStatic / codebot_v110 / codebot_v113 frozen WE_Build pins to 125.
- **Checks:** claude_bud_job29.py PASS (31 pins; offline sim via LUAU skipped in that runner); codebot_v125.py PASS; tools/sim/run_offline_test.py 7/7 ok; BuyPathStatic **PASS=6505 FAIL=0**; rojo → dist/WarEmpire-PERF.rbxlx (+ WarEmpire.rbxlx copy). Open Cloud HTTP 200 `versionNumber=123`. Code commit `d55b769`.
- **Phone tests (owner account; Migrate to Latest Update):**
  1. Offline: play, note ATM, leave ≥2 h, rejoin → after ~6 s "WELCOME BACK +$X", ATM holds ~¼ of 2 h income.
  2. Streak: Missions shows 7-day strip + "Tomorrow" line; daily row "Day N done · Tomorrow $Y".
  3. Opt-in: Settings → NOTIFICATIONS → Game alerts: TURN ON → Roblox opt-in prompt.
  4. FastStart (fresh Studio profile): spawn at CC console + arrow; BUILD → +$1,500 burst; no picker/streak before CC; Output `[FUNNEL]` times.
  5. Second player: never sees another player's cards or arrow.
- **NEXT:** Shaun phone-tests above on owner account before flipping OwnerFirst. Claude rebase `claude/desktop-bud` onto phase-7-polish (v125 tip).

## claude-bud JOB 29 (2026-09-30): retention (branch `claude/desktop-bud`, rebased on v124)
Every part has a kill switch and ships **OwnerFirst** (UserId 470626172 + Studio test players), via
`RetentionConfig.Live(block, userId)`.
- **Why a boolean:** codebot_v101 bans `= "owner"` strings in Configs, so owner-first is a boolean.
- **To launch:** Code Bot sets `OwnerFirst = false`.
- **Kill switches:** `TutorialConfig.FastStart.Enabled`, `EconomyConfig.OfflineEarnings.Enabled`,
  `DailyRewardConfig.ShowTomorrow` / `StreakCard.Enabled`, `RetentionConfig.Notifications.Enabled`.

**1. First 60 seconds**
- **Base:** already auto-assigned and teleported on join (step 1 is instant, as before).
- **FastStart:** a new player (Command Center not bought, tutorial not done) lands 7 studs in front of HIS Command
  Center console, facing it, instead of the plot gate. A pulsing gold arrow floats over the console.
- **Starter payout:** the first BUILD ($1,500 of the $10,000 start) pays +$1,500. It is server-side, once per profile
  (`StarterPayoutDone`), reason "onboarding", with coins flying to the cash pill.
- **Onboarding hold:** `WE_Onboarding` stays on until the Command Center step is done, or 60 s. While it is on, the
  nation picker, the daily-streak card and the welcome-back card wait.
- **Welcome line:** "Welcome! Press BUILD on the gold console." (41 characters, device-neutral).
- **Timings:** these are computed from the layout, NOT measured in Studio.

  | | Walk to the first buy | First payout |
  |---|---|---|
  | Before | ~168 studs, ~10.5 s at WalkSpeed 16 | the first ATM collect, after that walk |
  | After | ~7 studs, under 1 s | the starter burst at the first BUILD, well under 30 s |

  First unlock: Barracks ($2,500) is affordable right after the Command Center, so it is inside 2-3 min.
- **Funnel:** the SAME `AnalyticsConfig.Roblox.Funnel`, extended to 14 steps, each fired at the real moment through
  `AnalyticsService.Onboard`: Joined, Spawned, BaseClaimed, FirstBuilding, CollectedCash, Recruited, Barracks,
  FirstOutpost, FirstVehicle, TutorialDone, OpenedArmy, FirstAttack, PurchasePrompt, FirstPurchase.
  - Seconds-since-join go out as the custom event `OnboardingSeconds`.
  - Studio prints `[FUNNEL] <step> t=<s>`, so a fresh-profile Studio run gives the real times.

**2. Offline earnings**
- **Save field:** `LastSeenUnix` (additive, migrated) is stamped on every save.
- **Formula:** on load, 25% x the live tick's formula (ComputePassiveIncomePerTick x the passive cash multiplier /
  TickSeconds) x seconds away, capped at 8 h, +10% for Premium.
- **Payout:** paid into PendingCash (the ATM, reason "offline", not multiplied twice).
- **No payout:** first join, a negative gap, or a gap under 5 min.
- **Card:** "WELCOME BACK / While you were away you earned +$X / ... · in your ATM".
- **Robux:** none.

**3. Streak**
- **Tomorrow everywhere:** tomorrow's reward is shown wherever the streak is: the claim toast, the Missions daily row,
  the streak card and the Missions strip.
- **Owner-first:** one card with the 7-day strip (days 3 and 7 gold, big-day coin burst) instead of two toasts.
- **Missions panel:** the strip, plus "Tomorrow: Day N reward $Y" and "Away 8 h: earn up to $Z".
- **Day 7:** an ARMY BOOST (army damage x1.25 for 30 min, no Robux).

**4. Notifications**
- **When we ask:** 25 s after the tutorial ends (finished or skipped), or from **Settings → NOTIFICATIONS → Game
  alerts: TURN ON**.
- **Limits:** never in the first 60 s, once a session, 7 days after a decline, never after an accept.
- **Code path:** one client path (`Modules/NotifOptIn`).
- **State for a sender:** DataStore `WE_NotifyState_v1`, written on leave for opted-in players only.
- **Docs:** `docs/NOTIFICATIONS.md` has the Creator Hub steps, 4 templates, and what we will and won't notify about.
  No API key is in the game.

**Checks**
- tools/checks/claude_bud_job29.py (31 pins), plus `tools/sim/run_offline_test.py`, which runs the REAL
  ComputeOffline in the Luau CLI. All 7 cases pass: first join 0, negative 0, under 5 min 0, +2 h, +20 h capped at
  8 h, Premium, no income.
- BuyPathStatic **PASS=6510 FAIL=0**.
  - On Windows Python, 4 path-separator pins fail on clean HEAD too. They pass under POSIX path strings (a scratchpad
    wrapper), as on Linux.
- rojo build ok. No new LSP errors.
- The headless world sim and the DataService harness are not in the repo, so they were NOT run.

**NOT verified on a device:** the ExperienceNotificationService prompt (Studio cannot show it), the real join
timings, and the card layouts on a phone.

**Test ON HIS PHONE** (the owner account is OwnerFirst-live):
1. **Offline earnings:** play, note your ATM, leave for at least 2 h, rejoin. After about 6 s, "WELCOME BACK +$X"
   appears and the ATM holds it. X should be about a quarter of 2 h of income.
2. **Streak:** Missions shows the 7-day strip and a "Tomorrow" line. The daily row reads "Day N done · Tomorrow $Y".
3. **Opt-in:** Settings → NOTIFICATIONS → Game alerts: TURN ON shows Roblox's opt-in prompt.
4. **FastStart** needs a fresh profile. In Studio, run Start Server + 1 player (a fresh test profile):
   - you spawn at the Command Center console with the arrow;
   - BUILD gives the +$1,500 coin burst;
   - no picker or streak card appears before the Command Center;
   - the Output shows the `[FUNNEL]` times.
5. **Second player:** a second phone joining never sees another player's cards or arrow.
## v124 (Code Bot Roblox, 2026-09-30 ~00:51 Dublin): ATTACK army now targets the enemy player beside it + ONE shared PvP rule + /armydebug [ArmyTarget] — place version 122
- **Bug (Shaun, phone, v121+):** in ATTACK the army shot the bank guards (NPCs) but never Stevie (live player) or his base guards, even with Stevie next to the army; kill feed "Stevie > shaunie6 (Starter Rifle)", army idle beside Stevie.
- **Root cause (target selection, not hostility):** `pickSquadTarget` fed NPCs, players and guards into ONE sticky nearest-first `FormationController.PickTarget`: the current target (a bank guard) is kept unless another candidate is `AttackRetargetStuds` (15) nearer the army centre. The block deploys at `AttackStandoff` 36 from the guard, so any enemy player >= ~21 studs from the army centre was never picked; the per-unit fallback shot (`pickShot`) is NPC-only. Evidence: live Open Cloud Luau run on place v121 with the real module: `PickTarget(cur=BankGuard@36, Stevie@10/20) -> Stevie`, `@25/40/60 -> BankGuard`.
- **Hostility rules ruled out (evidence):** live config v121 PvPEnabled=true, ArmyCombat Enabled/TargetPlayers/TargetGuards=true, Follow3 Rollout=all, Steer/AttackSteer=true (AttackLive true for everyone); Shaun's saved profile (DataStore via Luau exec): ClanId=nil (no ally possible), TutorialComplete=true, NoviceShieldDone=true (no owner_shielded; any army order also ends it); Stevie dealt gun damage, so he was not novice-shielded (his first shot ends it) and his spawn shield is 3 s. No admin/owner/playtest check exists in any PvP rule. HostileGuards takes every non-allied base's guards within reach (no "at base" requirement). The **idle army in the screenshot = Shaun dead** (no owner root → `_acTarget` nil, ArmyController stops), then he respawns > 140 studs (AttackLeash) away.
- **Fix:** `CombatService.pvpBlock` = THE PvP rule (pvp_off / self / owner_shielded / protected / dead), used by `hurtPlayer` (guns/melee/vehicle), `ApplyBlastDamage` and `UnitMayHitPlayer` (+ never a clan ally). `FormationController.PickTargetTiered`: tier 2 = enemy player who hurt the owner in the last `ArmyCombat.AggressorSeconds` (10), tier 1 = any other enemy player in reach, tier 0 = guards/NPCs; only the top tier is picked from, sticky rule unchanged inside it. Kill switch `ArmyCombat.PreferPlayers = false` (v123 pick). PlayerMaxDps cap, LOS, Steer/AttackSteer, never-owner/never-ally unchanged.
- **Instrumentation:** `/armydebug on` → Server log `[ArmyTarget] shaunie6 units=N npcs=N guards=N players=N pick=<Kind Name tier d> | <player>: CANDIDATE pri=N | rejected <reason> | out_of_reach | leash | dead | no_character (dCentre dOwner)` every 2 s (`ArmyCombat.TargetLogSeconds`), next to the existing `[ArmyHit]` lines (ok / miss / no_los / dps_cap / protected ...).
- **Tests:** BuyPathStatic PASS=6482 FAIL=0 (tools/checks/codebot_v124.py 21 pins + tools/sim/army_target_tiers.py = the real PickTarget(Tiered) under luau: player picked at 5–100 studs, v123 bug reproduced, 7 regressions pass); live Open Cloud Luau on v122: PickTargetTiered picks Stevie at 10–100 studs (guard only past 120 = out of aggro), SquadOrdersService + CombatService require OK, new exports present. Not tested: a real 2-player live fight (needs the phone test below). **WE_Build 124**. PreferMesh OFF; WE_Building* untouched. Code commit `2933c79`.
- **Phone test (2 players):** Migrate to Latest Update. Shaun `/armydebug on`, Stevie joins (not in Shaun's clan). 1) Shaun ATTACKs the bank guards; Stevie walks up to 20–60 studs from the army → army turns and shoots Stevie (tracers, damage numbers, Stevie drops in ~2–4 s). 2) Stevie shoots Shaun from ~60–100 studs while the army fights guards → army switches to Stevie. 3) Stevie at his own base, Shaun ATTACKs nearby → army shoots Stevie first, then his gate/tower guards. 4) Clan mates: army never shoots them. If it still fails: F9 → Server → screenshot `[ArmyTarget]` + `[ArmyHit]` lines.

## v123 (Code Bot Roblox, 2026-09-30 ~00:40 Dublin): /movedebug + soldiers never collide with players (flag-free) — place version 121
- **Bug (Shaun, phone):** stick held forward, he runs, army falls back, he stops dead (RUNNING → IDLE, no obstacle), army catches up, he can move again.
- **Root cause: NOT YET PROVEN** (needs a phone repro with /movedebug on). Static audit of the whole src tree ruled out, with file evidence:
  - no army / leash / catch-up code writes to the player (ArmyController, ArmyFollow, SoldierController, FormationController, SquadOrdersService: no WalkSpeed / Anchored / CFrame / PivotTo / ChangeState / Move on the owner — pinned in codebot_v123.py);
  - AntiExploitService has no movement / speed check at all (payload strikes only) → no rubber-banding;
  - the only server WalkSpeed write to a player is the Speed Pass (x1.15/x1.25, never lower); no combat slow; FallSafety only below Y 0.15;
  - no ContextActionService Sink on touch / thumbstick, no GetControls():Disable, no Modal / ModalEnabled; StreamingEnabled false live (GameplayPaused impossible);
  - soldiers: ArmyNPCs x WE_PlayerChars = false live (Open Cloud probe on v123), rig / kit / v120 body parts CanCollide false + re-audited into ArmyNPCs every 5 s, escorts are client copies CanCollide false.
  - Candidate still open: v116–v120 QualityGovernor re-parenting WorldKits clusters on the phone by pivot distance (JOB 27, fixed in v121) could put collision round him; the new blocker list names any such part.
- **Shipped (quiet unless toggled):** `Modules/MoveDebug` (tagged writers for Speed Pass WalkSpeed + every player PivotTo; watchers; 4 Hz sampler: [MOVEMENT OWNER LOST] / [MOVEMENT WELDED] / [MOVEMENT SOLDIER CAN COLLIDE], army distance, within 6, CatchingUp, last writers) + `Client/Modules/MoveDebugClient` ([MOVEMENT BLOCK DETECTED] = |MoveDirection| > 0.5 and speed < 1 for > 0.25 s with a full dump; [MOVEMENT INPUT LOST]; ReceiveAge; Active GUIs under the thumb; collidable blockers ahead; on-screen non-Active label) + `/movedebug [on|off]` (admin allowlist).
- **Hardening:** ArmyFollow now sets ArmyNPCs x WE_PlayerChars = false and hooks every player into WE_PlayerChars regardless of Follow2/Follow3 rollout flags (was gated); BaseGuards WE_Guards x WE_PlayerChars = false. Follow3.Steer / AttackSteer untouched. **WE_Build 123.** PreferMesh OFF; WE_Building* untouched.
- **Checks:** BuyPathStatic PASS=6465 FAIL=0; remote_audit OK; rojo → dist/WarEmpire-PERF.rbxlx (+ WarEmpire.rbxlx); Open Cloud HTTP 200 `versionNumber=121`. Code commit `3b01492`.
- **Phone steps (Shaun):** Migrate to Latest Update → join → chat `/movedebug on` (toast "Move debug ON", black label top centre) → optionally `/armydebug on` (CatchingUp counts) → run the same route, stick held, until it stops → hold the stick 2–3 s → F9 Developer Console: screenshot the **Client** log `[MOVEMENT BLOCK DETECTED]` / `[MOVEMENT INPUT LOST]` lines and the **Server** log `[MoveDebug] S` / `[MOVEMENT ...]` lines around that time → `/movedebug off`.

## v122 (Code Bot Roblox, 2026-09-30 ~00:30 Dublin): real nation flags wired — place version 120
- Wired the 7 JOB 25 flag atlases (uploaded by shaunie6 via Creator Hub as IMAGE assets) with `tools/wire-nation-flag-ids.py` into `NationFlagIds.Atlas`: Europe 117922087338795, Americas 129834397528036, Asia 114871762121221, Africa 132455042605948, MiddleEast 88221072001528, Oceania 82459247862229, Review 98381294373531. National flags only (flag-icons). **WE_Build 122**. PreferMesh OFF; WE_Building* untouched.
- All atlases non-zero → `LiveRequiresArt` lets the nation picker open by itself for everyone after this publish.
- Moderation: thumbnails API reports state `Completed` for all 7 ids at ship time (not Pending/Blocked).
- **Pins:** `tools/checks/codebot_v122.py` (WE_Build 122 + the 7 atlas ids). Retired codebot_v121 WE_Build pins; bumped BuyPathStatic / codebot_v110 / codebot_v113 frozen WE_Build pins to 122.
- **Checks:** BuyPathStatic PASS=6423 FAIL=0; rojo → dist/WarEmpire-PERF.rbxlx (+ WarEmpire.rbxlx copy); Open Cloud HTTP 200 `versionNumber=120`. Code commit `db06299`.
- **Phone tests (owner):** restart servers / Migrate to Latest Update; nation picker shows real flags (check one per region incl. Review: AF, SA, KE…); base flagpole shows your flag; a flag in each region crops to the right cell (not a neighbour). If a flag shows as colour tile, that atlas may still be in moderation.
- **Fallback:** if an atlas crop looks wrong, per-nation `Flags["IE"] = <image id>` via the same script.

## v121 (Code Bot Roblox, 2026-09-30 ~00:19 Dublin): JOB 26+27 stronger army + player armour + town cull LIVE — place version 119
- Fast-forward merged Claude `d0ea486` (JOB 26) + `bf799fe` (JOB 27) onto phase-7 tip `54f3aef` (v120). Code Bot bump commit `6ee87c8`. **WE_Build 121**. PreferMesh OFF; WE_Building* untouched.
- **JOB 26 — stronger army + buyable player armour**
  - `ArmyConfig.StrongerArmy` (kill switch `Enabled`): HP 150, damage 12, 2.2 shots/s, player cap 50 DPS; owner sees throttled NPC hit markers; denser tracers.
  - Army menu → ARMY UPGRADES: Firepower / Toughness (existing) + new **Combat Drills** (+8 % fire rate / level).
  - Army menu → MY ARMOUR (`ArmourConfig` / `ArmourService`): Light Vest → Titan (10–50 % damage cut via bonus MaxHealth); buy next tier only, inside own base, CC level gated; blue HUD armour bar; vest/helmet look (hideable); kept on death and rebirth. `CommanderArmourRobux = false` (no Robux item created).
- **JOB 27 — city buildings popping**
  - Root cause: client `QualityGovernor` pivot-point cull with one threshold (StreamingEnabled off; no server rebuild).
  - Fix: bounding-box distance; buildings by size never culled; LOAD/UNLOAD hysteresis; kill switch `QualityConfig.CullTownBuildings = true` restores old behaviour. Replay model: 0 building-seconds missing at 16–140 studs/s.
- **Pins:** `tools/checks/claude_bud_job26.py` + `claude_bud_job27.py` + `tools/checks/codebot_v121.py` (WE_Build 121, ArmourConfig/ArmourService, StrongerArmy, CullTownBuildings=false, GetBoundingBox/boxDist). Retired codebot_v120 WE_Build pins; bumped BuyPathStatic / codebot_v110 / codebot_v113 frozen WE_Build pins to 121.
- **Checks:** BuyPathStatic PASS=6409 FAIL=0; rojo → dist/WarEmpire-PERF.rbxlx (+ WarEmpire.rbxlx copy); Open Cloud HTTP 200 `versionNumber=119`.
- **Kill switches:** `ArmyConfig.StrongerArmy.Enabled = false`; `ArmourConfig.Enabled = false`; `QualityConfig.CullTownBuildings = true` (old cull back).
- **Phone tests (owner):**
  1. ATTACK an outpost — defenders fall faster; hit numbers + tracers visible; army TTK feels harder than v120.
  2. Army menu → ARMY UPGRADES → buy Combat Drills.
  3. Army menu → MY ARMOUR inside base → buy Light Vest: toast, blue bar above health, vest on avatar; outside base blocked.
  4. Die/respawn and rebirth — armour kept. Hide armour look — vest gone, blue bar stays.
  5. Run / sprint / drive fastest vehicle through town — no building / roof / wall flash-out; note phone FPS in town vs yesterday.
  6. Follow + AttackSteer + army PvP still feel like v120; Army Soldier body still looks right.
- **NEXT:** Shaun phone-tests above before claiming "fixed". Claude rebase `claude/desktop-bud` onto phase-7-polish (v121 tip).

## claude-bud JOB 27 (2026-09-30): city buildings popping in / out (branch `claude/desktop-bud`)
- **Proven root cause:** Client/Modules/QualityGovernor.cull, case B (our code removes the models).
  - **Streaming ruled out:** `StreamingEnabled` is absent from default.project.json and from the built place (class
    default false); codebot_v101 forbids turning it on.
  - **Server ruled out:** no server loop rebuilds town models (Waterways / WorldPOI only clear decor once at boot).
  - **Other client code ruled out:** no other client code re-parents or destroys world models; BusinessVisuals only
    touches plot crates.
- **Why it popped:** on every phone the governor is LOW (small screen). It took WorldKits clusters out of the client's
  world like this:
  - **#1:** a custom distance cull;
  - **#5:** measured from ONE cached pivot point, so a 300-stud building with its pivot at one end hid while you stood
    beside it;
  - **#4:** ONE threshold for hide and show;
  - **1 Hz checks:** too slow at speed;
  - **#7:** it included the city's building clusters AND rooftop props, which are separate clusters on top of
    buildings.
  - JOB 24 §8's NeverHideKinds only listed POI roles, but the city's fill buildings use kit names. So they still
    popped while running.
- **Replay** (tools/sim/quality_cull_model.py: the three versions of the rule on a city street), building-seconds
  missing within 200 studs of the player:

  | Speed | v116 | JOB 24 §8 | JOB 27 |
  |---|---|---|---|
  | 16 studs/s (run) | 101.8 | 34.2 | **0** |
  | 28 studs/s | 59.9 | 11.4 | **0** |
  | 60 studs/s | 33.5 | 0.4 | **0** |
  | 100 studs/s | 25.7 | 0 | **0** |
  | 140 studs/s | 22.3 | 0 | **0** |

  Small decoration still loads 240-330 studs ahead.
- **Fix** (one architecture, no second streaming system):
  - distance to each cluster's bounding box;
  - buildings recognised by SIZE (footprint >= 14 or height >= 10), plus NeverHideKinds, plus anything standing on a
    building, are never culled;
  - only small far decor is culled, with a LOAD / UNLOAD buffer (Tier 2: in < 220, out > 320; others: in < 480,
    out > 640);
  - one central manager at 0.4 s (0.2 s when fast) with look-ahead;
  - no Destroy / Clone; `QualityConfig.DebugLog` prints `[BUILDING DEBUG] UNLOADING|LOADING: <name> PlayerDistance
    CameraDistance Chunk Reason`.
  - Kill switch: `QualityConfig.CullTownBuildings = true` restores the old behaviour.
- **NOT verified on a device:** I cannot run Studio or a phone from here, so there is no FPS / memory before / after.
  Buildings now always render on phones, which costs a little more than before; small decor is still culled.
  - **Verify in Studio:** set DebugLog = true, Device emulator = phone landscape (low quality turns on by itself on a
    small screen), Start Server + Player. Walk, run and drive the town street. No building line should ever print,
    only small decor LOADING / UNLOADING far away.
- **Checks:** tools/checks/claude_bud_job27.py (+ the replay). The J8 / J24 §8 pins are updated. BuyPathStatic
  PASS=6405 FAIL=0; rojo ok; no new LSP errors.
- **Test ON HIS PHONE:**
  1. Run, sprint, then drive the fastest vehicle down the town street and back, with fast camera turns.
  2. No building, roof or wall may flash out.
  3. Note the phone's FPS in town (Settings → performance stats) against yesterday.
## claude-bud JOB 26 (2026-09-29): stronger army + buyable player armour (branch `claude/desktop-bud`)
- **Before:**
  - soldier HP 90 (x1.0-1.5 Body Armor), damage 8 (x1.0-1.5 Marksman Training), 1.8 shots/s, range 55 (fire band
    46.75), hit chance 96-98 % (no spread);
  - vs players: x0.6, capped at 40 DPS per victim.
- **After** (`ArmyConfig.StrongerArmy`, kill switch `Enabled`):
  - HP 150, damage 12, 2.2 shots/s; player cap 50 DPS;
  - the owner sees hit markers / damage numbers for NPC hits (at most 4/s); tracers every 0.15 s per army (the
    per-recipient caps stay).
- **Army upgrades** (Army menu → ARMY UPGRADES opens the Soldiers research track):
  - Firepower = Marksman Training, Toughness = Body Armor (both existed, not duplicated);
  - Training = NEW **Combat Drills** (+8 % fire rate per level, 5 levels, $4k → $300k).
- **Time to kill** (model, config numbers; tools/sim/army_pvp_model.py), before → after:

  | Target | Before | After |
  |---|---|---|
  | Player, no armour, 5 soldiers | 2.6 s | 1.6 s |
  | Player, no armour, 8 soldiers | 2.4 s | 1.4 s |
  | Player, top armour (-50 %), 5 soldiers | 5.3 s | 4.4 s |
  | Infantry (80 HP) | 1.1 s | 0.6 s |
  | Heavy (140 HP) | 2.0 s | 1.1 s |
  | Fort Guard (170 HP) | 2.5 s | 1.3 s |
  | Oil Rig Guard (200 HP) | 2.8 s | 1.5 s |
  | Gate guard, 140 HP | 2.0 s | 1.1 s |
  | Gate guard, 300 HP | 4.3 s | 2.3 s |

  - Army vs army: armies never target each other (not a game mechanic), so it was not measured.
- **Player armour** (`ArmourConfig`, kill switch `Enabled`; Army menu → MY ARMOUR):

  | Tier | Damage cut | Price | Needs |
  |---|---|---|---|
  | Light Vest | -10 % | $12k | Command Center L1 |
  | Combat Armour | -20 % | $45k | CC L2 |
  | Heavy Armour | -30 % | $150k | CC L3 |
  | Elite Armour | -40 % | $450k | CC L4 |
  | Titan Armour | -50 % (the cap) | $1.2M | CC L5 |

  - Bought in order, inside his own base only.
  - Effect = bonus MAX HEALTH (100 / (1 - cut)): 20 % = 125 HP. So it works against every damage source (guns,
    soldiers, guards, defenders, vehicles, missiles), whatever code hurts him.
  - HUD: a blue armour bar above the health bar (the bonus, spent first).
  - Look: a vest (every tier), plus a helmet from Heavy (simple welded parts). "Armour look" in the panel hides it; the
    stats stay.
  - Saved as the hidden PersonalArmour research level (paid through ResearchService, so the SpendCash invariant stays
    at 8 sites). Kept after death AND through rebirth (research is never reset).
  - Toast on buy: "ARMOUR EQUIPPED - you take 20% less damage."
  - **Robux suggestion (NOT created, `CommanderArmourRobux = false`):** a cosmetic "Commander Armour" skin, or the
    Titan tier early at CC L3, for about 199 R$. The owner decides.
- **Pins retired** (claude-bud notes, replaced in tools/checks/claude_bud_job26.py): the squadfair damage /
  LosCheckAt / ApplyUnitHit lines and the army A0 UnitShotFx body. The job24b model range is updated.
- **Checks:** BuyPathStatic PASS=6357 FAIL=0; rojo ok; no new LSP errors.
- **Test ON HIS PHONE:**
  1. ATTACK an outpost: defenders fall fast, you see hit numbers, and tracers are visible.
  2. Army menu → ARMY UPGRADES opens Research (Soldiers): buy Combat Drills.
  3. Army menu → MY ARMOUR inside your base: buy Light Vest. Check the toast, the blue bar above health, and the vest
     on your avatar. Try it outside the base ("Buy armour inside your base").
  4. Die and respawn: the armour is kept. Rebirth: the armour is kept.
  5. Hide the armour look: the vest goes, the blue bar stays.
## v120 (Code Bot Roblox, 2026-09-29 ~23:55 Dublin): Army Soldier body for the army + base/tower guards LIVE — place version 118
- Owner asked for this as "v119"; Claude-watch shipped v119 (JOB 24c+25, place version 117) at 23:45 while this was in flight, so it went out as **WE_Build 120**, rebased on `a05d034`.
- **Asset:** "Army Soldier" 7703684779 (@Ca_zr, free, owned by shaunie6 since 2026-09-29, so live LoadAsset works). It is an R6 Humanoid rig with 6 Motor6D (RootJoint, Neck, 2 shoulders, 2 hips) and classic 1x2x1 block limbs. The look is Shirt 1718367929 + Pants 1837155389 (image ids) + a MulticamFAST helmet (mesh 5608666819, 2103 tris at LOD0).
  - The file holds 67 parts in total, all dropped: an M4 of 26 unions, a pistol, a knife, a grenade, 8 MeshParts. The ~40.7k tris were almost all those guns.
  - It has 6 Scripts (Soldier AI, Animate, Sounds, voicelines, BloodSplat, ColorScript) and 9 RemoteEvents. Nothing suspicious: no require / getfenv / loadstring / HttpService; "KICK" is a melee TODO.
  - All 15 scripts and remotes are stripped before baking (`stripRigHazards`, whatever StripScripts says).
- **Wiring:**
  - `VisualAssetConfig.SoldierAssetId = 7703684779` / `SoldierFallbackAssetId = 187790284` (locals `SOLDIER_ASSET_ID` / `SOLDIER_FALLBACK_ID`).
  - `Characters.Squad` / `Guard` / `GateGuard` = the new rig, `Headwear = "Beret"` (the file's helmet).
  - Hostile Infantry / HeavyInfantry / Worker / Bank / OilRig / Fort guards / CampCommander keep 187790284, so enemies read differently.
  - Fallback: `rigIdOf` switches a row to FallbackAssetId once the preferred id failed for good (not authorized, permanent error, retries exhausted, or BakeTemplate refused it). Waiting hosts get it through `rigFallback` → `flushRigPending`.
- **RigBuilder:**
  - BakeTemplate now refuses files with no Humanoid or a non-R6 rig.
  - Headwear pick prefers helmet / beret / cap / hat (`RigConfig.Cloth.HeadwearPrefer`). It measures the offset from the file's own head when the file's HeadWeld holds a different hat.
  - Block-limb bodies keep their Shirt / Pants ids. `PaintCloth` paints the standard 585x559 template regions onto the limb faces as 23 `Texture`s named WE_Cloth, tinted 30 % toward the kit colours.
  - There is no Humanoid in WE_Rig (catalog rule; the hit / aim code reads a Humanoid under a limb's model).
  - Headless-verified with an Open Cloud Luau task on the live place: bake + attach give 8 rig parts, 23 cloth Textures, 6 motors, an Animator and no Humanoid. 187790284 bakes exactly as before.
- **Animation:** unchanged pipeline (RigAnimator Hold / Idle / Walk / Aim on the standard R6 joints; Follow3.Steer / AttackSteer / ArmyCombat untouched). Kit Rifle stays in the R6 grip.
- **Phone LOD (RigAnimator):**
  - Cloth bodies get the far look: kit-colour blocks with cloth and helmet hidden outside the pick (same MaxAnimated 24 / MaxMeshedStatic 8 / 22 escorts).
  - `helmetBudget` pays every meshed body first: 60 tris per cloth body, 1530 per Roblox body. It then shows helmets in pick order (own army first) only while the total stays ≤ `Budget.MaxMeshedTriangles` 85000.
  - Worst case: 54 x 60 + 38 helmets x 2103 ≈ 83k. Figures past the cap show their kit head without a helmet. Stats: `HelmetsOn` / `HelmetsOff` / `MeshedTris`.
- **Kill switches:**
  - `SOLDIER_ASSET_ID = 187790284` (whole v118 body back).
  - `RigConfig.Cloth.Enabled = false` (plain blocks).
  - `Cloth.TintAlpha` (0 = pure camo).
- **Risk to eyeball:** the Texture UV mapping (offset from each face's top-left) was not visually checked. If a limb shows the wrong patch, flip `Cloth.Enabled` off and report.
- Pins: `tools/checks/codebot_v120.py` (37 checks). Retired codebot_v119 WE_Build pins and BuyPathStatic Squad=187790284 pin. BuyPathStatic PASS=6380 FAIL=0; rojo ok.
- **Phone tests (owner):**
  1. Your army (and its escorts) walk and shoot in digital camo + FAST helmet, with no sliding and the rifle in hand.
  2. Your gate / tower guards wear the same body.
  3. Enemy NPCs still wear the old Roblox Soldier.
  4. From far away, soldiers turn into kit-colour blocks.
  5. FPS with a full army + escorts is like v119.
  6. Output shows `[VisualAssetService] rig 7703684779: stripped 15 script(s) / remote(s)` and no "rig refused".

## v119 (Code Bot Roblox, 2026-09-29): JOB 24c+25 building tips + outpost defenders + town cull + base signs LIVE — place version 117
- Merged Claude `bf3ff7b` (JOB 25: BaseSignService "<Name>'s Empire" signs + NationFlag plate) on top of `84b1667` (JOB 24c: BuildingTips / BuildingTipController / BuildingTutorialConfig + Settings TIPS; OutpostDefenders + OutpostDefenderConfig capturable outposts + 5 named enemy areas; QualityGovernor NeverHideKinds / LookAheadSeconds / hysteresis). Fast-forward from v118 tip `c73f18c` (Claude branch already on v118).
- WE_Build 119 in BaseService / DataService / EarlyRemotes (+ DataService log). PreferMesh OFF; WE_Building* untouched. NationFlagIds all still 0 — owner must upload 7 atlas PNGs (do not invent ids).
- Pins: `tools/checks/claude_bud_job24b.py` + `tools/checks/claude_bud_job25.py` + `tools/checks/codebot_v119.py` (WE_Build 119, BaseSignService/Config, OutpostDefenders/Config, BuildingTipController/TutorialConfig, Quality NeverHideKinds + LookAhead). Retired WE_Build=118 pins in codebot_v118; bumped BuyPathStatic frozen pins.
- Checks: BuyPathStatic PASS=6346 FAIL=0; rojo build ok.
- Kill switches: `BaseSignConfig.Enabled = false`; `OutpostDefenderConfig.Enabled = false`; `BuildingTutorialConfig.Enabled = false`; Settings TIPS off.
- **Phone tests (owner):** (1) join — your sign shows headshot + "<name>'s Empire" with LV · REBIRTH · ARMY; empty plot = UNCLAIMED; (2) another player's base shows theirs; (3) change flag at flagpole — sign plate follows (colour until atlases uploaded); (4) buy a new building — one "NEW: X UNLOCKED" card with OK / SHOW ME; Settings → TIPS off / show tips again; (5) walk to North Ridge — defenders shoot; capture blocked until they are down; (6) drive fastest vehicle through town — no building vanishes; (7) Follow + AttackSteer + army PvP still feel like v118.
- **OWNER STEP (not Code Bot):** upload 7 PNGs in `assets/flags/` as Images, then `tools/wire-nation-flag-ids.py` with the ids. Leaderboard flags / auto IP country / outpost flags remain owner decisions (not shipped).
- **NEXT for Claude:** rebase `claude/desktop-bud` onto phase-7-polish (v119). Await phone verdict before further sign/defender/cull work.

## claude-bud JOB 25 (2026-09-29): "<Name>'s Empire" base signs + real flags status (branch `claude/desktop-bud`)
- **What already existed (nations spec):**
  - a 200-nation roster (UN + 7), a picker with search, flag art from lipis/flag-icons (MIT) rendered into 7 atlases
    (`assets/flags/atlas_*.png`, tools/gen_nation_flags.py);
  - flags on the base ParadeFlag + HQ roof as Textures (Server/Modules/NationFlag);
  - the IP country is a badged suggestion only (`SuggestPreselect = false`);
  - `LiveRequiresArt` (the picker opens by itself only once every atlas id is set);
  - `OutpostFlags = false`;
  - a player-list "Nation" column.
- **Why players see colour blocks, not flags:** every id in `NationFlagIds.luau` is 0, because the 7 atlas images
  were never uploaded.
  - **OWNER STEP:** upload the 7 PNGs in `assets/flags/` as Images, as the account / group that owns the game. Then
    run `tools/wire-nation-flag-ids.py` with the image ids.
  - After that, flags show everywhere and the `LiveRequiresArt` gate opens by itself.
  - I cannot upload (no Roblox account access / API keys).
- **New: the base sign** (Shared/Configs/BaseSignConfig, Server/Services/BaseSignService):
  - Placement: 26 studs above each plot's gate, one per plot.
  - Content: the owner's headshot, "<DisplayName>'s Empire", "LV · REBIRTH · ARMY".
  - Flag: a flag plate dressed by NationFlag (Textures; plain green until the art is uploaded).
  - Empty plots show "UNCLAIMED BASE / walk in to claim".
  - Size and refresh: fixed 250 x 78 px, MaxDistance 220, refreshed only when something changes (5 s check).
  - `CustomEmpireNames = false`. Kill switch: `BaseSignConfig.Enabled`.
- **Picker:** the "For you" tab now lists the 59 most common countries first; search covers all 200.
- **NOT done (conflicts with CLAUDE.md nation rules; the owner must decide before I change them):**
  - flags on the leaderboards ("never a real country on … leaderboards");
  - defaulting to the detected country ("an IP-derived country is only a suggestion … never auto-applied": it stays a
    badged suggestion);
  - flags on captured outposts (`OutpostFlags = false`, the nations-spec policy caution);
  - the sign's MaxDistance 220 is above the CLAUDE.md world-label rule (MaxDistance ≤ 40), because the brief asks for
    it to be readable from the road. It is one sign per base, never AlwaysOnTop.
- **Checks:** tools/checks/claude_bud_job25.py. BuyPathStatic PASS=6333 FAIL=0; rojo ok; no new LSP errors.
- **Test ON HIS PHONE:**
  1. Join: your sign should show your headshot + "<name>'s Empire", with the level / rebirth / army line updating
     after a level-up or rebirth.
  2. Another player's base shows theirs; an empty plot shows UNCLAIMED.
  3. Change flag at the flagpole: the sign plate follows (a colour until the atlases are uploaded).
  4. Readability from the road on the phone; nothing clips into buildings.
  5. With 10 players, all signs are right after join and leave.
## claude-bud JOB 24 big pass (2026-09-29, branch `claude/desktop-bud`, on v116 2965b15): 35099a3 + 458f2ed + the JOB 24c commit
- **§1 ATTACK + §3 debug off:** commit 35099a3 (docs/ARMY-ATTACK-ROOTCAUSE.md).
- **§2 the army now hurts enemy players:**
  - Root cause (code-proven), three parts:
    - the target scan only saw CombatService NPCs;
    - `CombatService.ApplyUnitHit` refuses players by design;
    - gate guards only took hits with the attacking PLAYER in range.
  - Now (ArmyConfig.ArmyCombat, kill switch `Enabled`), targets can be players, guards and the gate:
    - players go through `CombatService.ApplyUnitPlayerHit` (PvP / clan / shields → "X is Protected" toast; kill →
      owner cash, XP, MOST KILLS);
    - guards and gates go through `GateDefenseService.ApplyUnitDamage`, range measured from the soldier;
    - a player behind the gate → the army shoots the gate.
  - Player DPS is capped at 40. There is a hit log (/armydebug).
  - Model (config numbers): 5 soldiers kill a player in ~2.6 s (94 % hits) and a guard in 2–4 s. A player behind a
    gate takes 14–55 s (breach L1–L5 first).
- **§4 live warnings:**
  - **Guard research was dead live:** stats were missing from ResearchConfig.StatIds, and flat costs were refused.
    Both fixed, so GuardArmor / GuardRoster / TowerGuards now work.
  - **Terrain never built live:** the `Terrain.Decoration` throw aborted the whole build. It is now pcall'd, and
    keep-out drops are one info line.
  - **Assets:** 8 asset ids (not authorized / over 40 parts) set to 0. The Part kits stay, and the owner may pick
    replacements.
  - **WorldPOI:** skips are now info lines. The ActivityHost is never capped out (the "anchor rows not stamped" bug:
    a POI's job prompts were missing).
  - **UpgradePadService:** waits for the map before reporting zero pads.
  - **Autosave:** skips a key written in the last 10 s (the DataStore queue warning). Purchase and leave saves always
    write.
- **§5 building cards:**
  - On the first purchase of a building (server-confirmed) you get one "NEW: X UNLOCKED" card with OK / SHOW ME
    (SHOW ME draws a beam to the console for 8 s).
  - Cards are queued and never shown while driving. They are saved in profile.SeenTutorials, which rebirth keeps.
  - Settings → TIPS turns them off or shows them again.
  - Copy is in BuildingTutorialConfig (checked against the code).
  - **Buildings that do nothing extra yet:** PowerStation, Warehouse, Radar (only a MissileDefense prerequisite),
    SpecialForcesFacility, and WeaponsFacility (only the ArmsCrateLine prerequisite). All of them earn income.
  - The first-join tutorial already has 7 steps (claim → CC → collect → recruit → Barracks → outpost → jeep), so no
    duplicate chain was added.
- **§6 outpost defenders + §7 enemy areas** (`OutpostDefenderConfig`, `Server/Modules/OutpostDefenders`):
  - Root cause: TerritoryConfig GuardNPCType / GuardCount were never read, so nothing spawned.
  - Every capturable outpost that no player holds now has CombatService defenders, and capture is blocked until they
    are dead ("Defeat the defenders first!"):
    - Easy (3 Infantry): NorthRidge, SouthDocks, EastArmory, WestDepot, CentralPlaza;
    - Medium (2 Infantry + 2 Heavy): OilFields, RadarHill;
    - Hard (4 Fort / Oil Rig guards): FortIronclad, FortSandhold, CoastalOilAlpha / Bravo.
  - Five enemy areas: Crash Site and Signal Station (easy), Airstrip and Ruined Village (medium), Oasis (hard).
  - Defenders are awake only within 260 studs of a player and sleep 30 s after nobody is within 380. They come back
    150 s after being cleared.
  - At most 20 defenders per server (CombatConfig.SpecialOverCap 4 → 24).
  - Kills pay the NPC reward and count on MOST KILLS.
  - **NOT done:** friendly guards on player-owned outposts, and the new area art (walled compound, fuel depot …).
    The map's named POIs already have ground detail and signs, but a real art pass needs Studio and screenshots.
- **§8 town buildings vanishing at speed:**
  - Root cause: the phone LOW-quality culler (Client/Modules/QualityGovernor), not streaming (StreamingEnabled is
    still OFF). It hid whole clusters beyond 180 / 420 studs at 1 Hz from the camera point.
  - Fix:
    - buildings and landmarks (block / tower / landmark / square / town / fort / checkpoint …) are never culled;
    - decor distance is measured to 1.5 s ahead of the camera;
    - checks run at 3 Hz while moving fast;
    - 40-stud hysteresis.
  - Model at 100 studs/s: decor pop-in 82 → 294 studs ahead; buildings missing 3.4 s → 0.
  - JOB 27 will add the bounding-box / buffer / Studio-log pass.
- **§9 codes:** BUDSTUDIOS ($50k + 30 min 2x), BUDSQUAD ($25k), **WAREMPIRE** ($30k + 15 min 2x Cash), **ATTACK**
  ($10k + 500 XP). One per player, `Expires` optional.
- **§10 analytics** (Roblox AnalyticsService; Creator Hub → Analytics):
  - Funnel (new players): Joined → CollectedCash → FirstBuilding → OpenedArmy → FirstAttack → FirstOutpost →
    PurchasePrompt → FirstPurchase.
  - Economy: Cash sources / sinks per reason, per minute.
  - Custom events: ShopOpened, ProductPrompted, PromptCancelled, RobuxPurchase (value = Robux), VehicleSpawned,
    MissileLaunched, NukeLaunched, CodeRedeemed, TipShown / TipClosed, ArmyAttack, SessionLength (bucket).
- **§11 crown:** a "#1 MOST KILLS this week" label under the crown, plus a one-time note per board per week. Owner /
  admin stay off boards and crowns.
- **Checks:** tools/checks/claude_bud_job24b.py (53 pins + the PvP model). Pins retired: 4 asset ids, SpecialOverCap
  4, the J8 hide line. BuyPathStatic PASS=6324 FAIL=0; rojo ok; no new LSP errors.
- **Test ON HIS PHONE:**
  1. ATTACK a player's base with a full army: the defender should die. Try a player behind the gate (the gate goes
     down first) and a shielded new player ("Protected").
  2. Buy Guard Armor / Tower Guards research: it must not be greyed out.
  3. Buy a new building: one card should appear. Try SHOW ME, then Settings → TIPS off and "show my tips".
  4. Walk to North Ridge: defenders should shoot back, and capture only starts once they are down.
  5. Drive the fastest vehicle through town: no building should vanish.
  6. Redeem WAREMPIRE and ATTACK.
  7. Take a weekly #1: the crown label should show.
  8. Next day: Creator Hub → Analytics → Funnel / Economy / Custom events should have data.
## v118 (Code Bot Roblox, 2026-09-29): JOB 24b army PvP + warnings + codes + analytics + crown LIVE — place version 116
- Merged Claude `458f2ed` (JOB 24b: ArmyConfig.ArmyCombat — army ATTACK damages enemy players / other-base gate+tower guards / gates when player behind; live warning quieting; codes WAREMPIRE + ATTACK; AnalyticsService sink; crown "#1 <BOARD> this week"). Merge commit onto phase-7-polish (v117 88b5e80) — not FF (v117 Code Bot commits were ahead of desktop-bud).
- WE_Build 118 in BaseService / DataService / EarlyRemotes (+ DataService log). PreferMesh OFF; WE_Building* untouched.
- Pins: `tools/checks/claude_bud_job24b.py` + `tools/checks/codebot_v118.py` (WE_Build 118, ArmyCombat, WAREMPIRE/ATTACK, ApplyUnitPlayerHit). Retired WE_Build=117 pins in codebot_v117; bumped v110/v113/BuyPathStatic frozen pins.
- Checks: BuyPathStatic PASS=6314 FAIL=0; rojo build ok.
- Kill switches: `ArmyConfig.ArmyCombat.Enabled = false` (army hits NPCs only, as v117); also `Follow3.AttackSteer = false`, `Follow3.Steer = false`, `Follow3.Enabled = false`.
- **Phone tests (owner):** (1) ATTACK an enemy player — soldiers damage them; you get cash / XP / kill credit; (2) ATTACK another base's gate or tower guards — they take damage and die for credit; (3) enemy player stands behind their gate — army shoots the gate; (4) shielded / clan ally / novice target — "Protected" toast, no damage spam; (5) join a fresh server — no spam of terrain / asset / ZERO-pads warnings; (6) redeem codes `WAREMPIRE` ($30k + 15 min 2x Cash) and `ATTACK` ($10k + 500 XP); (7) weekly #1 crown shows "#1 <BOARD> this week" under it; (8) Follow + AttackSteer still feel like v117 (block, line, no bunching, no debug visuals).
- **NEXT for Claude:** rebase `claude/desktop-bud` onto phase-7-polish (v118). Await phone verdict before further army combat / movement changes.

## v117 (Code Bot Roblox, 2026-09-29): JOB 24 army ATTACK AttackSteer LIVE — place version 115
- Merged Claude `35099a3` (JOB 24: Follow3.AttackSteer — ATTACK uses the same steered block + sticky squad target + line at 36 studs; Follow3.Debug=false by default). Fast-forward from 2965b15 (v116).
- WE_Build 117 in BaseService / DataService / EarlyRemotes (+ DataService log). PreferMesh OFF; WE_Building* untouched.
- Pins: `tools/checks/claude_bud_armyattack.py` + `tools/checks/codebot_v117.py` (WE_Build 117, AttackSteer, Debug=false, attackAimOnly). Retired WE_Build=116 pins in codebot_v116; bumped v110/v113/BuyPathStatic frozen pins.
- Checks: BuyPathStatic PASS=6274 FAIL=0; rojo build ok.
- Kill switches: `Follow3.AttackSteer = false` (v116 attack), `Follow3.Steer = false`, `Follow3.Enabled = false`.
- **Phone tests (owner):** (1) tap ATTACK near enemies — jog as one block, line at gun range, stand and fire, no bunching; (2) walk around while they fight — no run-through-you, line ignores camera; (3) kill target — switch next or fold back ~3s; (4) FOLLOW mid-approach — fold, no teleport; (5) max army 8 — two ranks, no overlap; (6) walk away past ~140 studs — leave fight and follow; (7) no slot markers / labels / formation panel; `/armydebug on` brings them back; (8) Follow turns/stop/180° same as v116.
- **NEXT for Claude:** rebase `claude/desktop-bud` onto phase-7-polish (v117). Await phone verdict before further army movement changes.

## claude-bud JOB 24 (2026-09-29): army ATTACK mode + debug visuals removed (branch `claude/desktop-bud`, on v116 2965b15)
- **Root cause** (`docs/ARMY-ATTACK-ROOTCAUSE.md`): on ATTACK the ArmyController let go. `SquadOrdersService.attackUnit`
  then moved each soldier on its own:
  - its own nearest enemy, re-picked every 0.4 s;
  - MoveTo every think to a ring seat 8 studs round that enemy, stopping wherever it crossed 46.75 studs;
  - no line of sight → run in to 8 studs;
  - nothing in reach → march 10 studs in front of his LOOK vector, forever.
  - Sim: soldiers overlapping (closest pair 0.05–0.74 studs), up to 5 path crossings, no reform after the target dies.
- **Fix** (`Follow3.AttackSteer = true`; false = v116):
  - ATTACK is the same steered block as FOLLOW. It advances as one unit on ONE sticky squad target, deploys into a line
    facing it at 36 studs (each soldier's cell by its permanent slot), and soldiers stand and fire.
  - SquadOrdersService only picks the target and shoots / aims, with line of sight kept.
  - When the target is down, out of the 140-stud leash, or the order changes, the line slides back into the follow
    block on its own side of him. No teleport, no WalkSpeed raise, no extra MoveTo.
  - FOLLOW is unchanged: the J23 and v115 sim numbers are identical.
- **Sim** (v116 → JOB 24, closest two soldiers during the attack):
  - stationary target 0.23 → 3.22;
  - moving target 0.26 → 4.26;
  - target dies 0.05 → 2.27 (reform never → 2.6 s);
  - switch targets 0.74 → 3.22;
  - cancel 0.23 → 3.22 (reform 0.57 s);
  - max army 0.18 → 3.05;
  - he keeps walking 0.21 → 4.17 (reform never → 2.6 s);
  - deployed slot error ≤ 2.0 studs; 0 crossings, 0 teleports.
- **Debug visuals gone:** `Follow3.Debug = false`. No markers, labels or panel for anyone, including the owner.
  `/armydebug` (admin allowlist, DebugUserIds) still turns it on for testing.
- **Checks:**
  - `tools/checks/claude_bud_armyattack.py` (87 pins + the attack sim);
  - the v115 "Debug = true" pin is retired;
  - BuyPathStatic PASS=6276 FAIL=0; rojo ok; no new LSP errors.
- **Test ON HIS PHONE:**
  1. Walk near an enemy group and tap ATTACK. The army should jog toward it as one block, then spread into a line
     facing it at gun range and stand and fire. Nobody should bunch on one point or run into the enemy.
  2. While they fight, walk around them. They must not run through you, and the line should not follow your camera.
  3. Kill the target. They should switch to the next nearby enemy smoothly, or, with none left, fold back into the
     follow block behind / beside you within about 3 s.
  4. Tap FOLLOW mid-approach. They should fold back straight away, with no teleport.
  5. Attack with the max army (8 units): two ranks, no overlap.
  6. Attack, then keep walking away. Past about 140 studs they should leave the fight and follow you.
  7. Check the screen: no slot markers, no "S01 / Slot 01" labels, no "Formation … (tap)" panel. `/armydebug on`
     brings them back.
  8. Follow as before: turns, stop, 180° walk-back. It must feel exactly like v116.
  - Kill switches: `Follow3.AttackSteer = false` (v116 attack), `Follow3.Steer = false`, `Follow3.Enabled = false`.
## v116 (Code Bot Roblox, 2026-09-29): JOB 23 army formation Steer LIVE — place version 114
- Merged Claude `46fe085` (JOB 23: one steered block Follow3.Steer / FormationController.SteerFrames). Fast-forward from a95c2a8.
- WE_Build 116 in BaseService / DataService / EarlyRemotes (+ DataService log). PreferMesh OFF; WE_Building* untouched.
- Pins: `tools/checks/claude_bud_armyj23.py` + `tools/checks/codebot_v116.py` (WE_Build 116). Retired WE_Build=115 pins in codebot_v115_army / bumped v110/v113/BuyPathStatic frozen pins.
- Checks: BuyPathStatic PASS=6185 FAIL=0; rojo build ok; armyj23 pins included.
- Kill switch: `ArmyConfig.Follow3.Steer = false` = v115 TrailBlock rows; `Follow3.Enabled = false` = v113.
- **Phone tests (owner, /armydebug, panel open):** (1) sharp 90° — grid stays a grid, no crescent, max slot err under ~6; (2) stand+spin 180° — nothing moves; (3) walk back through army — stop, aisle, arc round, no teleport / whole-row C; (4) big+tight circles — smooth cyan/magenta trails; (5) max army 8 — note `[ArmyDebug] SPIKE` if maxErr>10; (6) sudden stop after turn — settle ~1s; (7) panel under top-bar pills, 14px, tap to fold.
- **NEXT for Claude:** rebase `claude/desktop-bud` onto phase-7-polish (v116). Await phone verdict before further army movement changes.

## claude-bud JOB 23 (2026-09-29): army formation turn transitions (branch `claude/desktop-bud`, on v115 a95c2a8)
- **Root causes** (`docs/ARMY-FOLLOW-ROOTCAUSE-4.md`, the 15 answers with measured data):
  1. v115 slots rode his breadcrumb trail. At every corner their velocity swung 90° in one tick, and the rows turned
     at 100°/s, so slots reached 30 studs/s (about 1.9× his speed) and the rows made a crescent.
  2. About-turn: each row's point ran up his old path into the turn point and straight back, then folded, so a
     whole rank fell behind at once (5 of 5 or 7 of 8 CatchingUp). With slower soldier response it gives 13–18.5
     studs, which is his 13–17 at about 23 s.
  3. Catch-up gain jumped 0.6 → 0.9 at 6 studs and only dropped under 3: his "C at 3.3 next to F at 3.5".
  - His LookVector was NOT a cause: a stationary 90° / 180° turn or spin moved every slot 0.00 studs in both designs.
- **Fix** (`Follow3.Steer = true`; false = the v115 rows):
  - The block is ONE steered body (`FormationController.SteerFrames`). Its position is steered along his path, with
    accel, brake and speed caps.
  - Its heading comes from his movement only, with angular inertia. The turn-rate cap is 10 studs/s ÷ the block's
    radius, and it pivots about its own centre.
  - On an about-turn it waits, then arcs round. No slot moves faster than 24 studs/s.
  - Soldiers use one continuous WalkSpeed law toward their OWN slot. The state names are labels only. There is no new
    teleport, no higher catch-up and no extra MoveTo rate.
- **Debug** (owner, `/armydebug`):
  - labels "S01 / Slot 01" + "F 2.1";
  - a formation panel at the top right (tap to fold);
  - cyan / magenta trails for the first and last slot;
  - a `[ArmyDebug] SPIKE` console line on every spike.
- **Sim** (A–J, while turning; v115 → JOB 23; max slot error / most CatchingUp at once):
  - sharp 90°: 6.2 / 1 → 5.2 / 0;
  - tight circle: 6.1 / 1 → 4.3 / 0;
  - zig-zag: 6.9 / 1 → 5.6 / 0;
  - walk-back: 7.8 / **5 of 5** → 7.5 / 1;
  - max army: 11.5 / **7 of 8** → 10.6 / 4;
  - max slot speed: 30 → 24;
  - stationary turns and spin: 0.00;
  - 0 slot changes, 0 teleports.
- **Checks:**
  - `tools/checks/claude_bud_armyj23.py` (70 pins + the A–J sim);
  - the v115 sim passes, with the orbit tick exempted while the block waits (claude-bud comment);
  - the v114 sim passes;
  - BuyPathStatic PASS=6188 FAIL=0;
  - rojo ok; no new LSP errors;
  - the headless world sim and the DataService harness are not in the repo, so they were not run.
- **Test ON HIS PHONE** (debug on, panel open):
  1. Walk straight, then make a sharp 90° with the thumbstick. The grid should stay a grid (no crescent), no soldier
     should show "C" above ~6, and the panel's max slot error should stay under ~6.
  2. Stand still and spin the camera and your character 180°. Nothing should move (the panel reads formation 0.0).
  3. Walk, then walk straight back through your army. It should stop, let you through its aisle, then arc round
     behind you, with no teleport and no whole row lighting up "C" at once.
  4. Run a big circle and a tight circle round a base. Watch the magenta and cyan trails: they should be smooth arcs
     with no kinks.
  5. Do all of that with the max army (8 units). Check the console for `[ArmyDebug] SPIKE` lines and send any with
     maxErr > 10.
  6. Stop suddenly after a turn. The block should settle within about 1 s without overshooting past its slots.
  7. Check the panel sits under the top-bar pills at the right, is readable at 14 px, and folds with a tap.
  - Kill switches: `Follow3.Steer = false` (v115 rows) or `Follow3.Enabled = false` (v113).
## v115 (Code Bot Roblox, 2026-09-29): army follow root cause 3 LIVE, place version 113
- **What the owner saw on v114:** wings, then a split into two groups, a diagonal train, then an orbit/U, reforming only when he stopped.
- **Root causes** (`docs/ARMY-FOLLOW-ROOTCAUSE-3.md`):
  1. The v114 Flank `SlotLocal` put units 6 studs to his SIDE, and client escorts sat 5.5 studs further out (wings).
  2. The single heading rotated about an anchor ON him, so outer and rear cells swept arcs faster than soldiers can run.
  3. The SoldierController "wheel" ran units round the outside of him (the orbit).
- **New "TrailBlock" formation** (`Shared/Util/FormationController`, rewritten): a breadcrumb trail of his path, with rows on that trail 7 + r×4.5 studs of PATH behind him. Each row's heading is the trail tangent, rate-limited to 100°/s, with an 8° deadband, updated only while he moves.
  - Layout: even columns (≤4, 5 apart, with a 7-stud aisle on his path), escorts in the rows directly behind their unit.
  - About-turn fold: rows reverse in place and walk back down the old path. Rows he walks into part. Units in his lane step out to their own side.
  - Slots: permanent `FormationSlot`.
  - Wheel removed. Catch-up only toward the soldier's own slot (6/3 hysteresis).
  - Client escorts follow their unit's own path (RigAnimator escort trail; `WE_EscSide` is gone).
- **Debug** (owner only):
  - `Follow3.Debug` + `DebugUserIds {470626172}` + his `WE_ArmyDebug` attribute; `/armydebug [on|off]` toggles it.
  - Client `ArmyDebugClient`: neon slot discs, green/yellow/red lines, and "S07 / Slot 07" labels.
  - Server logs: WARN on SLOT CHANGE / LAYOUT CHANGE / REPOSITION, plus a per-soldier log every 2 s.
- **Sim:** `tools/sim/` (the real FC + SC in the Luau CLI, humanoid walkers). All 10 owner tests pass: 154 PASS / 0 FAIL. Plots are in `docs/army-sim/*.png`.
- **Checks:** `tools/checks/codebot_v115_army.py` (static + the sim). Retired the Flank/heading/WE_Build/sim pins in `codebot_v114_army.py`.
- **Build:** BuyPathStatic PASS=6119 FAIL=0; rojo ok; WE_Build 115. Commit 2be8d70. Open Cloud versionNumber=113.
- **Kill switch:** `ArmyConfig.Follow3.Enabled = false` gives v113 behaviour.
- **NEXT for Claude:** **rebase `claude/desktop-bud` onto phase-7-polish (v115)**.
  - Soldier movement still only goes through SoldierController.
  - Slots come from `FormationController.Plan`. The removed APIs (NewAnchor / Step / SlotLocal / SlotWorld / MoveLead / SideRow) must not come back.
## v114 (Code Bot Roblox, 2026-09-29) — army follow root cause 2 LIVE — place version 112
- Owner phone test of v113: despawn fixed (kept) but still slot swapping / crossing, a snap ~8-9 s in, bunching. Root cause written up in `docs/ARMY-FOLLOW-ROOTCAUSE-2.md` (separation push + mid/path target switching + escort close-in/side-step fight vs Flank seats + seat compaction; the "snap" = the face gyro getting full torque back with a stale target on arrival, amplified by the client escort files welded 7-12 studs AHEAD of each unit; Flank rows only ~4 studs apart and 3.6 from him).
- New: `Shared/Util/FormationController` (smoothed anchor, heading from movement w/ 18° deadband + hold, 100°/s cap, no flip backing up; Flank grid one row per unit 6 studs out, escorts 5.5 further out, rows 5.5 deep; PERMANENT slot assignment), `Server/Modules/SoldierController` (the ONLY Humanoid:MoveTo + the only PivotTo = emergency `Reposition`; arrival 2.5/4 hysteresis, reissue > 2.5 studs, 0.2 s tick, catch-up by WalkSpeed, snap-free gyro, staged stuck, U-turn "wheel" round the outside, never through the owner), `Server/Modules/ArmyController` (one FOLLOW controller per army, FOLLOW/HOLD/ATTACK/RETREAT; base gate hold kept, no PivotTo turn). FOLLOW escort = aim/shoot only. Client RigAnimator lays escorts along the formation row (`WE_FormYaw` / `WE_EscSide`). Collision: ArmyNPCs x ArmyNPCs / WE_PlayerChars false, x Default true, audited every 5 s.
- Kill switch: `ArmyConfig.Follow3.Enabled = false` = v113 behaviour. All tunables in `ArmyConfig.Follow3`.
- Checks: `tools/checks/codebot_v114_army.py` (static + Luau-CLI FormationController / Drive sims). Retired old PivotTo / MoveTo-count pins in claude_bud_army(follow).py, codebot_v91/v99/v113.py, BuyPathStatic recoverUnit (commented, superseded). BuyPathStatic PASS=6102 FAIL=0; rojo ok. WE_Build 114. Commit dbb9afe. Open Cloud versionNumber=112.
- NEXT for Claude: **rebase `claude/desktop-bud` onto phase-7-polish (v114)**. Any new soldier movement must go through SoldierController (Move / Stop / Reposition) — the v114 check fails on a direct Humanoid:MoveTo / PivotTo on a squad unit.
## v113 (Code Bot, 2026-09-29) — JOB 22 army follow root-cause fix LIVE — place version 111
- Merged Claude `6a8b6b2` (JOB 22: one mover ArmyFollow.Command, FormationMath smoothed anchor, stable seats, collision groups, escort same slots). `ArmyConfig.Follow2.Stable = true` (set false = old v99 path). WE_Build 113; BuyPathStatic PASS=6036 FAIL=0; rojo ok. Commit SHA 8a11d8b. Open Cloud versionNumber=111.
- Kept: v111 Grab Cash off; v112 10 plots; PreferMesh OFF; WE_Building* untouched. Pins: `tools/checks/codebot_v113.py` + `claude_bud_armyfollow.py`.
- Kill-switch: `ArmyConfig.Follow2.Stable = false` rolls back to the old follow path.
- Phone tests (from Claude): stand still (no jitter); walk straight; slow 90° turn; fast 180°; circles; sudden stop; strafe L/R + walk backwards (shift-lock) — formation must NOT flip; sprint away (speed up, no teleport); zig-zag (steady); 5 / 8 soldiers (+ escorts); fight near a bank guard then walk on; walk through a doorway / round a building; another player walks through the army (no pushing).
- NEXT for Claude: rebase `claude/desktop-bud` onto phase-7-polish (v113). Reminder: Creator Hub Max Players → 10 still pending if not done.

## v112 (Code Bot, 2026-09-29) — JOB 21 10 base plots LIVE — place version 110
- Merged Claude `7e883b1` (JOB 21: 10 plots, dock channel/gate pad/spur road each, full-server teleport) onto v111 (Grab Cash off). WE_Build 112; BuyPathStatic FAIL=0; rojo ok. Creator Hub max players -> 10.
- NEXT for Claude: JOB 22 army follow root-cause fix. Rebase onto v112.

## v111 (Code Bot, 2026-09-29) — Grab Cash plate removed — PUBLISHED place version 109
- Shaun: the $75 Grab Cash plate added nothing. `ManualDropperConfig.Enabled = false` (set true to restore). No plates are built; the tutorial Income step still advances on PassiveIncome.
- WE_Build 110 → 111; pin `tools/checks/codebot_v111.py`. BuyPathStatic FAIL=0; rojo build ok. PreferMesh OFF; WE_Building* untouched.
- NEXT for Claude: JOB 22 army follow root-cause fix (prompt given to Shaun) BEFORE JOB 21 plots. Rebase onto v111.

# WHERE I STOPPED — 2026-09-29 (Code Bot shipped v110) — JOB 20 LIVE
**Claude: rebase `claude/desktop-bud` onto phase-7-polish (v110) before new work.** Do not redo JOB 14, JOB 15, BOARDS, Flank, JOB 17, JOB 18, JOB 19, or JOB 20.
Keep v102 Codes / CashBoost, v104 Engagement (all) + Discord invite + exploit guards, v105 BUDSQUAD, v106 GameFeel all + RemoteGate observe, v107 BOARDS, v108 Flank, v109 night/WorldFill2/stands.
Jobs: [x] 12 launch readiness · [x] 13 bring players back · [x] 14 game-feel polish · [x] 15 anti-exploit sweep · [x] BOARDS · [x] army Flank · [x] 17 night lighting · [x] 18 world fill 2 · [x] 19 purchase stands · [x] 20 real base guards · [ ] 21 more plots

- PreferMesh stays OFF. WE_Building* untouched. Never bump WE_Build / publish (Code Bot only).
- Speed Pass display price is 99 R$ (owner repriced in Creator Hub).

## QUEUE 4 (claude-bud, rebased on v110: J20 shipped there)
Jobs: [x] 17 · [x] 18 · [x] 19 · [x] 20 real base guards · [x] 21 more plots (10)
- J20 SHIPPED (live for all, GuardConfig + Modules/BaseGuards): base guards hold posts, fight intruders
  (players + enemy army) inside the plot within a 60-stud leash, return after 8 s, respawn after 45 s;
  Defenses research Guard Armor / Guard Roster / Tower Guards; owner-credited kills; anti-farm; damage caps.
- J21: **FINAL PLOT COUNT = 10 → set the place's Max Players to 10** (Creator Hub place settings; no publish).
  4 new plots near the map edge (P7/P8 north, P9/P10 south), each with a dock channel into the ring canal / sea, a gate
  pad and a spur road; 12 was not possible with a dock on every plot without moving POIs. Full server -> "Server full -
  moving you to another server" + teleport. Phone tests: join as the 7th-10th player: you get a base; drive from each
  new base's gate to the road; buy the Dock on P7-P10 and sail out the channel into the canal / sea; an old save with
  plot 1-6 still loads; with 11 players the 11th is moved to another server; frame rate with 10 players on a mid phone.
- J22 ARMY FOLLOW ROOT-CAUSE FIX (docs/ARMY-FOLLOW-ROOTCAUSE.md; ArmyConfig.Follow2.Stable, false = old): one mover
  (ArmyFollow.Command), smoothed formation anchor (facing-based heading, 90 deg/s cap, 20 deg deadzone, 1.5 s about-turn
  hold, no 180 flips), stable seats (no side swaps), MoveTo only when the slot moved 2.5 studs / 0.5 s, 1.5-3 stud arrival
  deadzone, AutoRotate faces travel (gyro only at rest), no soldier-player collision, escort fights use the same slots.
  PLAYTEST (phone + PC, 2 players): stand still (no jitter); walk straight; slow 90 turn; fast 180; circles; sudden
  stop; strafe L/R and walk backwards (shift-lock): the formation must NOT flip; sprint away (they speed up, no
  teleport); zig-zag (formation steady); 5 / 8 soldiers (+ escorts for 20-50); fight near a bank guard then walk on
  (no rush to new spots); walk through a doorway / round a building; another player walks through the army (no
  pushing). If worse: ArmyConfig.Follow2.Stable = false.

<!-- Q2-END -->

# v110 — 2026-09-29 ~16:55 Dublin (Code Bot, branch phase-7-polish, WE_Build 110) — JOB 20 REAL BASE GUARDS LIVE FOR ALL

**Claude: rebase `claude/desktop-bud` onto phase-7-polish (v110) before JOB 21. Do not redo J14–J20, Flank, BOARDS.**
Merged `origin/claude/desktop-bud` tip `f5387ae` (JOB 20 real base guards) into phase-7-polish (fast-forward from eac6cf9 v109 handoff).

- **JOB 20 Base guards (live for everyone, `GuardConfig` + `Modules/BaseGuards`):** GuardConfig Enabled=true (no owner gate). GateDefenseService 5 Hz loop runs ThinkGuard / ThinkTowers. Intruders (not owner / clan / friends) and enemy army units inside the plot are fought with 60-stud leash, return after 8 s, 45 s respawn, LOS + hit chance, per-target DPS cap, ≤6 shooters/base. Defenses research: Guard Armor / Guard Roster / Tower Guards (paid via ResearchService.Purchase, rebirth-scaled). Kills credit the owner via server creator tag (cash, XP, MOST KILLS, feed "<owner>'s Tower Guard"); max 3 per victim per 10 min; none in private servers; guard/unit kills give smaller rewards.
- Kept: v104 Engagement all + guards; Discord invite; v105 BUDSQUAD; v106 GameFeel all + RemoteGate observe; v107 BOARDS; v108 Flank; v109 night + WorldFill 2 + purchase stands; Speed Pass 99 R$.
- Pins: `tools/checks/codebot_v110.py` + `claude_bud_guards.py` (JOB 20 pins). BuyPathStatic PASS=5943 FAIL=0; rojo ok. PreferMesh OFF. WE_Building* untouched.

**Phone tests (second account / alt):** alt walks into your base → guards turn, chase (never out of plot / past 60 studs), shoot; alt dies → you get the kill (toast, board, feed); you / friend / clan-mate never shot; your own army safe, alt's army shot; alt waits outside 8 s → guards walk back; buy Watchtowers, hire tower guard at corner prompt (owner-only), it shoots alt outside walls (not inside); kill a guard as alt → small reward; new/low-level alt not deleted instantly (damage cap).

**Published:** Open Cloud `versionNumber=108` (commit b9d441d). Migrate to Latest Update for real base guards.

# v109 — 2026-09-29 ~16:35 Dublin (Code Bot, branch phase-7-polish, WE_Build 109) — JOBS 17–19 LIVE FOR ALL

**Claude: rebase `claude/desktop-bud` onto phase-7-polish (v109) before JOB 20. Do not redo J17/J18/J19, Flank, BOARDS, JOB 14, or JOB 15.**
Merged `origin/claude/desktop-bud` tip `7667291` (JOB 17 night + JOB 18 WorldFill 2 + JOB 19 purchase stands) into phase-7-polish (fast-forward from ad1c5f7 Speed Pass 99 R$).

- **JOB 17 Night (live for everyone, `LightingConfig`):** moonlit night (midnight ambient ~90,95,120, Brightness floor 2.0, blue colour correction), ~50 warm night lights (town roads, plaza, Town Square, base gates/hangars, plaza flag), Neon glow only at night. Low quality halves lights.
- **JOB 18 WorldFill 2 (live for everyone, `WorldFillConfig.Fill2`):** town identities (market/port/garrison), rooftop clutter, themed patch in every empty 300-stud cell, highway power lines, dirt tracks, dune belt. Cap 7,000 Full / 2,600 Low; Tier 2 clutter hidden beyond 180 on low quality.
- **JOB 19 Purchase stands (live for everyone):** Supply Depot row of Robux purchase stands (hex steel plinth, gold trim, hologram, info board with config price, pulsing ring) + Golden Pump stand; prompt-only buying; OWNED green check. Same PromptPremiumPad path.
- Kept: v104 Engagement all + guards; Discord invite; v105 BUDSQUAD; v106 GameFeel all + RemoteGate observe; v107 BOARDS; v108 Flank; Speed Pass 99 R$.
- Pins: `tools/checks/codebot_v109.py` + `claude_bud_night.py` / `claude_bud_worldfill2.py` / `claude_bud_stands.py`. BuyPathStatic PASS=5890 FAIL=0; rojo ok. PreferMesh OFF. WE_Building* untouched.

**Phone tests:** wait for night (~8 min or /time): roads/bases/players readable, streetlights on, windows lit, runway edge glow; Graphics 1–3 fewer lights. Bomber flyover 80+ studs: no big empty squares, dunes on horizon; drive highways/town/plaza (nothing blocks); stands: walk-on does nothing, hold "Buy - R$ …" opens Roblox dialog (cancel); owned = green ✓ OWNED.

**Published:** Open Cloud `versionNumber=107` (commit cd9d421). Migrate to Latest Update for night lights, WorldFill 2, and purchase stands.

# v108 — 2026-09-29 ~15:55 Dublin (Code Bot, branch phase-7-polish, WE_Build 108) — ARMY FLANK FORMATION (place version 106)

**Claude: rebase `claude/desktop-bud` onto phase-7-polish (v108) before new work. Do not redo Flank, BOARDS, JOB 14, or JOB 15.**
Merged `origin/claude/desktop-bud` tip `66cfdd7` (army Flank formation) into phase-7-polish.

- **Army Flank (live for everyone via Follow2.Tidy):** the tidy wedge put rows behind the owner (at / behind the phone camera), so the camera guard hid them while walking. Formation = "Flank" — a file each side of the owner, last row ~8 studs back, rows on their own side lines. "Wedge" restores the old formation.
- Kept: v104 Engagement all + guards; Discord invite; v105 BUDSQUAD; v106 GameFeel all + RemoteGate observe; v107 BOARDS.
- Pins: `tools/checks/codebot_v108.py` + `claude_bud_army.py` Flank pins. PreferMesh OFF. WE_Building* untouched.

**Published:** Open Cloud `versionNumber=106`. Migrate to Latest Update for army Flank.

# v107 — 2026-09-29 ~15:35 Dublin (Code Bot, branch phase-7-polish, WE_Build 107) — BOARDS LIVE FOR ALL (place version 105)

**Claude: rebase `claude/desktop-bud` onto phase-7-polish (v107) before new work. Do not redo BOARDS, JOB 14, or JOB 15.**
Merged `origin/claude/desktop-bud` tip `0bd3c79` (Town Centre notice boards) into phase-7-polish, keeping v104
(Engagement live-all + Discord invite + exploit guards), v105 (BUDSQUAD), and v106 (GameFeel all + RemoteGate observe).

- **BOARDS (live for everyone, `LeaderboardConfig`):** 6 Town Centre notice boards on the square's south edge —
  MOST KILLS (all-time / this week), RICHEST, TOP SUPPORTERS (Robux, Settings opt-out), PLAZA CONQUEROR (weekly),
  REBIRTH KINGS, TOP ARMY; weekly #1 crown; night spotlights; gold "You:" line near a board.
  OrderedDataStore per stat (`WE_LB2_`), ISO-week weekly stores, write throttle 90 s (leave respects it too),
  shared 75 s refresh, pcall + back-off + request budget. Validated PvP kills (creator tag, no self/clan, 3/pair/10 min).
  Confirmed-only Robux on Supporters. Admin/playtest accounts stay off the boards (v104).
- **v104 exploit guards kept across the merge:** friends daily cap, comeback once-per-absence, invite friendship +
  new-player checks, admin board exclusion.
- Pins: `tools/checks/codebot_v107.py` + `claude_bud_boards.py`. BuyPathStatic PASS=5702 FAIL=0; rojo ok.
  PreferMesh OFF. WE_Building* untouched.

**Published:** Open Cloud `versionNumber=105`. Migrate to Latest Update for the Town Centre boards.


# v106 — 2026-09-29 15:05 Dublin (Code Bot, branch phase-7-polish, WE_Build 106) — JOB 14 GAME-FEEL LIVE FOR ALL + JOB 15 REMOTEGATE OBSERVE

**Claude: rebase `claude/desktop-bud` onto phase-7-polish (v106) before new work. Do not redo JOB 14 or JOB 15.**
Merged `origin/claude/desktop-bud` tip `751a86b` (JOB 14 + JOB 15 after rebase on v103) into phase-7-polish, keeping v104
(JOB 13 live-all + Discord invite + exploit guards) and v105 (BUDSQUAD).

- **JOB 14 GameFeel (live for everyone):** kill feed (2 HUD top-stack lines, PvP + vehicle kills, DisplayNames);
  vehicle damage numbers (attacker + red victim numbers, aggregated); one raid report per attack
  ("YOU WERE RAIDED -$N" / "BASE DEFENDED"); sound pass (volume bands; premium gun/missile, markers, AIRSTRIKE tap,
  event banner no longer silent). `GameFeelConfig.Rollout` = "all" for KillFeed / VehicleNumbers / RaidReport / SoundPass.
- **JOB 15 RemoteGate (observe, safe):** every client→server remote gated (rate ceiling + argument schema + sink on
  push-only). `SecurityConfig.RemoteGate.Rollout` = "observe", Others = "observe" — logs "would reject", never drops/kicks.
  RedeemCode schema kept (`string:40`) for the v102 Codes RemoteFunction. Flip Rollout to "all" after quiet observe logs.
- Kept: v104 Engagement all + invite/friends/comeback/board guards; Discord invite plain text; v105 BUDSQUAD $25k.
- Pins: `tools/checks/claude_bud_q3.py` + `tools/checks/codebot_v106.py` (+ gamefeel_test / remotegate_test / remote_audit / sound_audit).
  BuyPathStatic PASS=5651 FAIL=0; rojo build ok. PreferMesh OFF. WE_Building* untouched.
- **Published:** Open Cloud place version **104** (commit 226aa43).
- **Publish note for Shaun:** "Migrate to Latest Update" (or shut down old servers) so v106 appears.

# v105 — 2026-09-29 14:51 Dublin (Code Bot, branch phase-7-polish, WE_Build 105) — BUDSQUAD LIVE

- Added active, non-expiring `BUDSQUAD` redeem code: **Bud Studios Discord**, `$25,000`, once per player via saved `RedeemedCodes`.
- Commit `b7e3e19`; Open Cloud place version **103**. BuyPathStatic `PASS=5595 FAIL=0`; rojo build ok. PreferMesh OFF; `WE_Building*` untouched.

# v104 — 2026-09-29 ~14:50 Dublin (Code Bot, branch phase-7-polish, WE_Build 104) — JOB 13 ENGAGEMENT LIVE FOR ALL

**Claude: rebase `claude/desktop-bud` onto phase-7-polish (v104, commit 865a1e3) before JOB 14/15.** JOB 13 is now live for
every player (`EngagementConfig.Rollout` = "all" for Events / Leaderboards / Invite / Friends / Comeback). Do not redo JOB 13,
do not flip any of it back to "owner", and keep the v104 guards below (JOB 15 anti-exploit sweep should build on them).

- **Invite:** pays only when the joiner is a real Roblox friend of the inviter (`IsFriendsWithAsync`; an error pays nothing),
  a brand-new account here (`InviteNewPlayerSeconds` = 15 min since FirstJoinUnix), on a saved profile (`DataService.IsLoaded`);
  `ReferredBy` is saved right away; inviter still capped 5/day (in-server and queued).
- **Friends bonus:** max 3 friends per tick and **$30,000/day** (`FriendsDailyCap`; profile.FriendsDay / FriendsPaid, saved).
- **Leaderboards:** one write per player per 60 s (kept across leave/rejoin), unchanged scores skipped, sorted-store budget
  respected; admin / playtest accounts (50M cash floor) are never written and filtered out of the top 10.
- **Comeback:** once per absence (`profile.ComebackPaidFor`), saved profile only, saved right away.
- Engagement reward reasons (`invite_welcome`, `invite_reward`, `friends_bonus`, `comeback`) are multiplier-exempt, so the caps are exact.
- **Discord:** `SocialConfig.DiscordInvite = "https://discord.gg/tkjA2DFBmZ"`. The Codes panel shows `DiscordInviteText`
  ("Discord: discord.gg/tkjA2DFBmZ") as plain TextLabel text under the Discord line, only when PolicyService
  `AllowedExternalLinkReferences` lists Discord. Never make it clickable; the clickable link belongs in Creator Hub → Social Links.
- Pins: `tools/checks/codebot_v104.py` + `tools/engagement_gate_test.py` (runs the real EngagementService in the Luau CLI,
  52 checks). v103 owner-only pins moved (claude_bud_q3 / codebot_v101 / codebot_v102 / codebot_v103).
  BuyPathStatic PASS=5591 FAIL=0 (with LUAU set), rojo build ok. PreferMesh OFF. WE_Building* untouched.
- **Published:** Open Cloud place version **102** (commit 865a1e3).
- **Publish note for Shaun:** "Migrate to Latest Update" (or shut down old servers) so v104 appears.

# v103 — 2026-09-29 ~14:35 Dublin (Code Bot, branch phase-7-polish, WE_Build 103) — JOB 13 ENGAGEMENT (owner-only)

**Claude: rebase `claude/desktop-bud` onto phase-7-polish (v103) before JOB 14/15.** Code Bot cherry-picked JOB 13 (`36779ce`)
onto v102. Keep Codes / CashBoost; Engagement Double Cash events stack with the timed boost. Do not redo JOB 13.

- **Engagement (owner-only, `EngagementConfig.Rollout` per feature):** weekly events (Plaza War Week / Airdrop Frenzy / Double Cash Weekend)
  with HUD banner + countdown; OrderedDataStore leaderboards (richest / plaza captures / rebirths) on a Town Square board;
  invite ($10k/friend, 5/day; friend gets $2.5k once); friends-in-server $500/min (max 3); comeback after 3+ days $25k.
  Not in LaunchSafe yet — phone-test as owner, then flip Rollout per feature.
- **Cash stack:** v102 `CashBoostMult` + JOB 13 `EngagementService.CashMult` both apply on non-exempt Cash.
- Pins: `tools/checks/claude_bud_q3.py` + `tools/checks/codebot_v103.py`. BuyPathStatic PASS=5554 FAIL=0, rojo build ok. PreferMesh OFF. WE_Building* untouched.
- **Published:** Open Cloud place version **101** (commit 2619db1). BuyPathStatic PASS=5554 FAIL=0.
- **Publish note for Shaun:** "Migrate to Latest Update" (or shut down old servers) so v103 appears.


# v102 — 2026-09-29 ~15:00 Dublin (Code Bot, branch phase-7-polish, WE_Build 102) — REDEEM CODES (live for all)

**Claude: rebase `claude/desktop-bud` onto phase-7-polish (v102).** The rail now has 6 tiles (Shop · Rebirth · Army · Garage ·
Missions · **Codes**); the BuyPathStatic "5 rail tiles" pin was moved to "5 + Codes". Any timed 2x Cash you add must reuse
`profile.CashBoost` / `EconomyService.CashBoostMult` (the one timed boost), not a second system.

- **Codes (live for everyone, no owner gate):** "Codes" rail tile (gift icon) → Codes panel: text box, REDEEM, result line,
  "2x CASH BOOST ACTIVE mm:ss left" while a boost runs, and "Join Bud Studios Discord for free codes!"
  (`SocialConfig.DiscordText`; `SocialConfig.DiscordInvite = ""` is a placeholder and is never shown, so no URL in-game).
  Settings → REDEEM CODE → "ENTER A CODE" opens the same panel.
- **Server:** `CodesService` answers the `RedeemCode` RemoteFunction with Success / AlreadyUsed / Invalid / Expired
  (+ RateLimited / NotReady): 5 tries per player per minute, case and spaces ignored, letters/digits/_ only, the code is marked
  in `profile.RedeemedCodes` before anything is paid, then the profile is saved. Code Cash is multiplier-exempt (reason
  `code`), so BUDSTUDIOS pays exactly $50,000; its 30 min 2x boost multiplies every non-exempt Cash earning (income,
  collection, kills…) and stacks with VIP / 2x Cash like the other multipliers. The minutes are real time from the redeem
  (they keep running while the player is offline); a second boost code adds its minutes on top (max 24 h ahead).
- **CodesConfig moved to the server** (`src/ServerScriptService/Server/Configs/CodesConfig.luau`) so exploiters cannot read the
  list. The pre-launch samples WARFOUNDING / BUILDCONQUER are kept but `Active = false` (players see "expired").
- Pins: `tools/checks/codebot_v102.py` + `tools/codes_gate_test.py` (runs the real CodesService in the Luau CLI, 37 checks).
  PreferMesh OFF. WE_Building* untouched.
- **Published:** Open Cloud place version **100** (commit 4b658d5). BuyPathStatic PASS=5525 FAIL=0 (parse gate on), rojo build ok.
- **Publish note for Shaun:** "Migrate to Latest Update" (or shut down old servers) so v102 appears.

## How to add a new code (owner)
1. Open `src/ServerScriptService/Server/Configs/CodesConfig.luau` (the steps are also written at the top of that file).
2. Copy the BUDSTUDIOS block and change the key, e.g.:
   ```lua
   	RAID1000 = {
   		Active = true,
   		Expires = "2026-10-31", -- end of that day UTC; or "2026-10-31T18:00:00Z"; or nil = never
   		DisplayName = "1000 Raids",
   		Rewards = { Cash = 25000, Gold = 5, CashBoostMinutes = 15 }, -- any mix of Cash / Gold / CashBoostMinutes
   	},
   ```
   The key is what players type (any case; spaces ignored; letters, digits and _ only, at most 32 characters).
3. To switch a code off early: `Active = false`. Players who already redeemed it keep their reward.
4. Ask Code Bot to ship (or: `python3 tools/BuyPathStatic.py` must end FAIL=0, `rojo build -o dist/WarEmpire-PERF.rbxlx`,
   `tools/publish-opencloud.sh`), then "Migrate to Latest Update". Codes only change with a publish.

**Phone test for Shaun (any account, the second account too):**
- Tap **Codes** on the left rail (on the smallest phones it sits at the top of a 2nd column next to Shop). The panel opens
  centred; the text box, REDEEM and the ✕ are easy to hit; the Discord line shows with no link.
- Type `budstudios` → green "Redeemed! You got $50,000 + 30 min 2x Cash." Cash jumps by exactly $50,000, the panel shows
  "2x CASH BOOST ACTIVE 29:59 left", and income / collections pay double while it runs.
- REDEEM again (try `BudStudios`) → orange "You've already redeemed this code." Leave the game, rejoin → still already used;
  the boost timer keeps counting down.
- Type `hello` → red "That code doesn't exist." Type `WARFOUNDING` → orange "This code has expired."
- Tap REDEEM 6 times fast with junk → "Too many tries. Wait a minute and try again."
- Settings (gear) → REDEEM CODE → ENTER A CODE opens the same panel. Tapping outside the panel closes it.

---


# v101 — 2026-09-29 ~14:30 Dublin (Code Bot, branch phase-7-polish, WE_Build 101) — ROLLOUTS ARE NOW "all"

**Claude: rebase `claude/desktop-bud` onto phase-7-polish (v101) BEFORE any new work.** Every owner-only rollout is now
`"all"` (owner: "enable everything for ALL players now"). v101 contains your JOB 12 (`fe22e41`, cherry-picked; on rebase git
drops it as already applied — if LATEST-HANDOFF.md conflicts keep phase-7-polish's). `MonetizationConfig.LaunchAll` stays
**false** on purpose: each gate's own Rollout is "all", and the owner keeps his UserId-only test shortcuts. Do not set any
gate back to "owner"; new features may still ship owner-only first under their own new key.

- **Live for everyone:** all 13 Robux SKUs (Speed Pass, Keep-Base Rebirth, Golden Pumpjacks, 6 premium vehicles + their guns,
  Bigger Army, Extra Garage Slot, Army Refill, Plaza Airstrike), VIP perks, purchase prompts at moments, retention rows + Premium
  daily perk, airdrop, daily auto-claim, plaza bounty, army upgrades, guards fight back, NpcUnstick, bag LOS, first-minutes
  tutorial, QualityGovernor, juice, balance curve + income XP, army Escort / Army / Fix / ThreatStandingFor / Follow2 / Tidy,
  Bridge Layer wading. WorldFill was already world-wide.
- **Still off:** StreamingEnabled, OpsConfig.Enabled, RebirthConfig.ZonesLive / WeaponsLive, AircraftWeaponConfig.WeaponsLive,
  XP backfill, PreferMesh, VisualAssetConfig.BodyRollout (11 hulls need the owner's WE_CHECK2 run).
- **Id 0 hidden:** PV_Bastion / PV_MotorPool (and every Id 0 product) have no Shop row or prompt for anyone.
- Pins: `tools/checks/codebot_v101.py` (+ `tools/v101_gate_test.py`, Luau-executed gates for a non-owner account). Old
  "owner-only first" pins retired with a `# v101 ... superseded` prefix. PreferMesh OFF. WE_Building* untouched.
- **Published:** Open Cloud place version **99** (commit 56a1c5c). BuyPathStatic PASS=5471 FAIL=0 (parse gate on), rojo build ok.
- **Publish note for Shaun:** "Migrate to Latest Update" (or shut down old servers) so v101 appears.

---

# v100 — 2026-09-29 ~14:00 Dublin (Code Bot, branch phase-7-polish, WE_Build 100)

**Claude: do not redo / undo queue 2 (JOB 6–11) or PREMIUM.** Code Bot merged `origin/claude/desktop-bud` tip `3cf54f2` (ce0b5cc..3cf54f2; based on v98 `08bcdf4`) onto phase-7-polish (v99 `c32bd9a`) and published. v99 Creator Hub Ids + army/rifle fixes kept.

- **JOB 9** (owner-only cleanup): old WIP finished or removed (real-world PT-boat / failed truck picks out; naval rows back on Part kits; unfinished handoff/wip patches retired; March lane C gone).
- **JOB 10** (owner-only): `BalanceConfig` curve — pads pay back in minutes, income XP does not feed battle pass; first rebirth ~34 min (`tools/progression_sim.py`).
- **JOB 11** (owner-only): juice — purchase burst, rebirth celebration banner, AIRSTRIKE button in HUD top stack (touch-safe sizes).
- **PREMIUM** (owner-only): 6 Robux-only vehicles clearly overpowered (`VehicleConfig.Premium`); server-validated guns + homing missiles (`PremiumWeaponService` / `PremiumWeaponsClient`); mobile FIRE/MISSILE; gold trail + ROBUX badge.
- Pins: `tools/checks/claude_bud_q2.py`, `claude_bud_premium.py`, `codebot_v99.py` (army/rifle/Ids), `codebot_v100.py`. PreferMesh stays OFF. WE_Building* untouched.
- **Creator Hub Ids kept from v99:** PV_Skylance 2001602422 · PV_Stormwing 2001722392 · PV_Leviathan 2001398410 · PV_Tidebreaker 1999263465 · PV_Warlord 2001320428 · PV_Razorfang 2002484380 · BiggerArmy 2001734404 · ExtraGarageSlot 1999359549 · SoldierRefill 3715442523 · PlazaAirstrike 3715442542.
- **Publish note for Shaun:** use **"Migrate to Latest Update"** (or shut down old servers) so JOB 9–11 + PREMIUM appear.

**Phone tests for Shaun (owner account; a second account must see none of the owner-only items):**
- **Balance:** pads feel worth buying (minutes payback); first rebirth around ~30–40 min; income does not power the battle pass.
- **Juice:** buy a pad → short burst; rebirth → celebration banner in the top stack (not over controls); AIRSTRIKE button in top stack, big enough for a thumb.
- **PREMIUM vehicles:** spawn Warlord / Razorfang next to cash tank / buggy — faster, tougher, snappier. While driving: FIRE + MISSILE bottom-right (not on jump/thumbstick); get out → gone. Hold FIRE hits NPCs/alt vehicles; clan/own vehicles take no damage. Gold lock ~250 studs → MISSILE curves; hard turn can dodge; 5 s cooldown. Skylance/Stormwing air; Leviathan/Tidebreaker water. Second account sees gold trail + ROBUX badge, cannot spawn. Spawn-protect / novice shield ignored damage.
- **Regression:** army gate-hold + rifle re-tap holster still work (v99). Garage gold ROBUX rows + Hub Ids still prompt.
- Migrate to Latest Update (or shut down old servers) before testing.

---

# v99 — 2026-09-29 ~13:50 Dublin (Code Bot, branch phase-7-polish, WE_Build 99)

**Claude: rebase `claude/desktop-bud` onto phase-7-polish (v99) BEFORE you touch any army or weapon code**
(`ArmyFollow.luau`, `SquadOrdersService.luau`, `ArmyConfig.luau` Follow2, `CombatController.luau`, `CameraFx.luau`,
`WeaponVisuals.luau`, `HudConfig.luau` Hotbar). v99 is **not** a merge of your JOB 9–11 (`22032ae..2028147` are still
only on Bud, left for the normal watch). Expect small conflicts in `tools/checks/claude_bud_money.py` and
`claude_bud_q2.py`: v99 changed your "Id 0 until created" pins to the real Ids — keep the v99 Ids.

**Creator Hub Ids now wired (owner created them; `tools/wire-monetization-ids.py`; prices unchanged; RolloutKeys unchanged = owner-only):**
PV_Skylance 2001602422 (899) · PV_Stormwing 2001722392 (999) · PV_Leviathan 2001398410 (1199) · PV_Tidebreaker 1999263465 (299) ·
PV_Warlord 2001320428 (799) · PV_Razorfang 2002484380 (199) · BiggerArmy 2001734404 (249) · ExtraGarageSlot 1999359549 (199) ·
DevProducts SoldierRefill 3715442523 (49) · PlazaAirstrike 3715442542 (79). `docs/LIVE_PLACE.md` table updated.
ProcessReceipt checked (no change needed): unknown Id → NotProcessedYet; ProcessedReceipts makes it idempotent; the grant banks
`SoldierRefills` / `AirstrikeCharges` (1 per receipt), marks processed, saves, then PurchaseGranted.

**Army (Bug 1: blobs / overlaps / snap-backs / stuck, owner-only via Follow2):**
- Two controllers on one Humanoid: the escort fight and ArmyFollow both drove MoveTo; stale follow state after a fight/HOLD/
  death made the stuck timer fire at once → teleport back. Now `ArmyFollow.Release` on every hand-off and a fresh state on re-acquire.
- Two yaw owners: AutoRotate vs NPCFaceGyro. Now AutoRotate off while following, one rate-limited facing (TurnRateDeg 300).
- Shared fallback point around buildings → every unit now gets its own point toward its own slot; paths kept 12 studs / 2 s,
  no walking back to passed waypoints.
- Formation turns rate-limited (no 180° swings); seats kept on deaths (compaction only after 4 s); regroup far = 100 studs for 3 s,
  staged stuck (repath 3 s → side step + jump 6 s → reposition 10 s, behind you, out of view); vehicle speed no longer counts
  as a jump; smooth catch-up speed; collision group `ArmyNPCs` set at spawn for every order.

**Rifle (Bug 2: can't put it away):** there are no Roblox Tools; the tap on the selected hotbar slot now holsters on touch
(`HudConfig.Hotbar.TouchTapHolsters = true`), getting shot no longer re-draws it for 4 s after a holster, death holsters,
recoil is zeroed and the reload track stopped when holstered.

- Pins: `tools/checks/codebot_v99.py`. BuyPathStatic PASS=5322 FAIL=0. PreferMesh stays OFF. WE_Building* untouched.
- **Publish note for Shaun:** use **"Migrate to Latest Update"** so v99 appears.

**Phone tests for Shaun (owner account):** army with 3 and with 15+: walk, sprint, sharp turns, run in circles, round buildings,
into and out of the base, run far away, stand still (no blob, no overlap, no snap-back). Rifle: equip, re-tap to put away,
swap to another slot and back, respawn, die while holding. Buy each pass + both dev products once (refill fills the army;
airstrike charge shows / fires at the plaza); a second account must not see the owner-only items.

---

# v98 — 2026-09-29 ~13:25 Dublin (Code Bot, branch phase-7-polish, WE_Build 98)

**Claude: do not redo / undo JOB 6–8.** Code Bot merged `origin/claude/desktop-bud` tip `e791323` (fc85a35..e791323) onto phase-7-polish and published.

- **JOB 6** (owner-only): Extra Garage Slot pass (+1 parked vehicle, Id 0 TODO) + gold ROBUX Shop rows. Spawn A then B parks A with health kept; sit in parked to drive again.
- **JOB 7** (owner-only): welcome toast on first join + first-ATTACK hint (Army popover outlines ATTACK until first ATTACK) on top of the existing tutorial.
- **JOB 8** (owner-only): QualityGovernor low-quality tier for phones / low FPS (far decoration clusters hide, local shadows off, cheaper FX) + streaming audit (StreamingEnabled stays OFF).
- Pins: `tools/checks/claude_bud_q2.py`, `codebot_v98.py`. PreferMesh stays OFF. WE_Building* untouched.
- **Creator Hub Id still owner TODO** for ExtraGarageSlot and other Id=0 items (paste with `tools/wire-monetization-ids.py`). Do not create products here.
- **Still open on Bud:** JOB 9–11 (old WIP, balance, juice). Claude may still work those — do not take them over.
- **Publish note for Shaun:** use **"Migrate to Latest Update"** (or shut down old servers) so JOB 6–8 appear.

**Phone tests for Shaun (owner account; a second account must see none of the owner-only items):**
- **Extra Garage Slot:** spawn vehicle A, spawn different vehicle B — A parks with health kept; sit in parked to drive again. Gold ROBUX Shop row; Id still 0 so purchase may be coming-soon / owner auto-grant.
- **First five minutes (new profile or wiped):** welcome toast on first join; after tutorial, Army popover opens with ATTACK outlined until first ATTACK.
- **Quality:** on phone / low FPS, far decoration clusters hide, local shadows off, cheaper FX (owner-only QualityConfig).
- Migrate to Latest Update (or shut down old servers) before testing.

---


# v97 — 2026-09-29 ~09:50 Dublin (Code Bot, branch phase-7-polish, WE_Build 97)

**Claude: do not redo / undo JOB 5b–5e.** Code Bot merged `origin/claude/desktop-bud` tip `7d5837c` (230fe5b..7d5837c) onto phase-7-polish and published.

- **JOB 5b** (owner-only): Bigger Army pass (+10 cap, Id 0 TODO); VIP chat tag `[VIP]` + VIP lounge north of Town (door + $5k/15 min gold pad); Extra Garage Slot stub hidden (not built).
- **JOB 5c** (owner-only): Instant Army Refill + Plaza Airstrike dev products (Ids 0 TODO; never-lethal airstrike).
- **JOB 5d** (owner-only): purchase prompts at the right moments + limited starter window.
- **JOB 5e**: Shop FREE retention rows (daily reward, airdrop track, group reward, unrewarded favorite) + Premium daily bonus; Creator Hub Id table for owner.
- Pins: `tools/checks/claude_bud_money.py`, `claude_bud_monetization.py`, `codebot_v97.py`. PreferMesh stays OFF. WE_Building* untouched.
- **Creator Hub Id table still owner TODO** (paste with `tools/wire-monetization-ids.py`; items stay hidden while Id is 0). Do not create Extra Garage Slot yet.
- **Publish note for Shaun:** use **"Migrate to Latest Update"** (or shut down old servers) so JOB 5b–5e appear.

**Phone tests for Shaun (owner account; a second account must see none of the owner-only items):**
- **Army (prior fix):** walk into your base with 8+ soldiers. Nobody crosses the gate; two neat blocks outside facing out. ATTACK: rows then ring (no stacking).
- **5a:** Garage shows 6 gold "ROBUX · R$" rows. Tap says "coming soon" until Id pasted; owner can already spawn via auto-grant.
- **5b:** chat shows `[VIP]` if you own VIP. VIP lounge just north of the Town: door lets you through; 2 s on gold pad pays $5,000 (once per 15 min).
- **5c/5d (after Ids exist):** AIRSTRIKE button near plaza; army-refill offer after squad wiped; 2x Cash / cash offer after rebirth; cash-pack offer when a vehicle is too expensive.
- **5e:** Shop Robux tab starts with FREE rows (Daily Reward CLAIM, Airdrop TRACK, Favorite). Roblox Premium: +$2,500 on first join of the day.
- Migrate to Latest Update (or shut down old servers) before testing.

---

# v96 — 2026-09-29 ~09:15 Dublin (Code Bot, branch phase-7-polish, WE_Build 96)

**Claude: do not redo / undo these.** Code Bot merged `origin/claude/desktop-bud` tip `a063154` (83a98b9..a063154) onto phase-7-polish and published.

- **Army gate-hold fix** (`ArmyConfig.Follow2.Tidy`, owner-only): after Shaun's v95 phone test — hold BEFORE the gate (no path through, no stuck/far teleport while outside); validated hold grid (raycast + overlap; bad cells skipped outward); per-seat ATTACK march rows / target ring (no stacking). Kill switch `Follow2.Tidy.Rollout = "off"`.
- **JOB 5a Robux-only vehicles** (owner-only via `MonetizationConfig.RolloutKeys`): six Premium clones — Skylance jet, Stormwing heli, Leviathan + Tidebreaker boats, Warlord tank, Razorfang buggy. Pass Ids still **0 / TODO owner** (Garage gold ROBUX rows; owner can spawn via auto-grant). Cash purchase refused (`RobuxOnly`). Free respawn for pass owners.
- Pins: `tools/checks/claude_bud_army.py`, `claude_bud_money.py`, `claude_bud_monetization.py`, `codebot_v96.py`. PreferMesh stays OFF. WE_Building* untouched.
- **Still open on Bud:** JOB 5b+ monetisation (VIP chat tag + VIP area, Bigger Army pass, Extra Garage slot; then 5c/5d/5e + Creator Hub list). Claude tip was fresh at merge — may still be coding.
- **Publish note for Shaun:** use **"Migrate to Latest Update"** (or shut down old servers) so the army fix + Robux vehicle Garage rows appear.

**Phone tests for Shaun:**
- Army fix (8+ soldiers, owner): walk into your base — nobody crosses the gate; two neat blocks outside facing out; none inside walls/props. Walk out: rejoin wedge. ATTACK in the open: rows in front; near an enemy: ring (no stacking into 2). Kill switch `ArmyConfig.Follow2.Tidy.Rollout = "off"`.
- Robux vehicles (owner): Garage shows gold **ROBUX** rows for the six Premium vehicles; spawn via owner auto-grant (pass Ids still 0). A second account should not see the rollout. Once Creator Hub Ids are pasted, Shop/Garage prompts work for pass buyers.
- Migrate to Latest Update (or shut down old servers) before testing.

---

# v95 — 2026-09-29 ~08:50 Dublin (Code Bot, branch phase-7-polish, WE_Build 95)

**Claude: do not redo / undo these.** Code Bot merged `origin/claude/desktop-bud` tip `3355267` (aaa87f3..3355267) onto phase-7-polish and published.

- **JOB 2 army tidy** (`ArmyConfig.Follow2.Tidy`, owner-only): army holds in neat rows outside the main gate (never enters plot); fixed seats; no column-crossing on turn; 8 s no-teleport run-back after leaving base.
- **JOB 3 WorldFill** (`WorldFillConfig.Enabled`, everyone): connector roads P1/P2/P5/P6→plaza, 2 dock bridges, 6 army positions, 4 plaza posts, terrain rocks under `Workspace.WorldFill` (planned ~388 Full / ~198 Low).
- **JOB 4.1 airdrop** (`SupplyDropConfig.Airdrop`, owner-only): parachute drop every 10 min + marker; claim for cash.
- **JOB 4.2 daily streak** (`DailyRewardConfig.AutoClaim`, owner-only): auto-claim ~8 s after join + next-day toast.
- **JOB 4.3 plaza bounty** (`PlazaBountyConfig`, owner-only): timed $15k for retaking Central Plaza within 3 min.
- **JOB 4.4 Army Upgrades** (`ArmyUpgradeConfig`, owner-only): Barracks world prompt opens Research → Soldiers.
- Pins: `tools/checks/claude_bud_army.py`, `claude_bud_worldfill.py`, `claude_bud_features.py`, `codebot_v95.py`. PreferMesh stays OFF. WE_Building* untouched.
- **Still open on Bud:** JOB 5 monetisation (Claude tip was fresh at merge — may still be coding).
- **Publish note for Shaun:** use **"Migrate to Latest Update"** (or shut down old servers) so WorldFill + owner-only JOB2/4 appear.

**Phone tests for Shaun:**
- Army fix (8+ soldiers): walk into your base; nobody crosses the gate, and they file into two neat blocks outside, facing out,
  none inside walls or props. Walk out: they rejoin the wedge. Press ATTACK in the open: they spread into rows in front of you;
  near an enemy they spread round it (no stacking into 2). (from Claude Bud handoff)
- JOB 4: wait ~1 min for first airdrop (marker + toast; stand by crate 2 s). ~8 s after join: login streak toast. Capture plaza with a second account, retake within 3 min: +$15,000. At Barracks tap "Army Upgrades" → Research Soldiers.
- Map fill: drive side gates P1/P2/P5/P6 — road to plaza; sandbag/watchtower positions; west dock bridge (boats under). Check mid-phone FPS. Server log `WorldFill: quality=full parts=N skipped=M`.
- Army (owner): walk/drive into base with 8+ soldiers — they stop outside gate in two blocks facing out. Walk out: wedge without teleport. Turn in place: no crossing. Kill switch `ArmyConfig.Follow2.Tidy.Rollout = "off"`.

---

# WHERE I STOPPED — 2026-09-29 (Claude on Bud, branch claude/desktop-bud, rebased on v95 phase-7-polish)

**All jobs are done and pushed:** Robux 3 products · runway · guards · JOB 2 army (+ the v95 army fix) · JOB 3 map fill ·
JOB 4 (airdrop, daily streak, plaza bounty, army upgrades) · JOB 5 monetisation (5a–5e). Nothing is half-done.
Every new gameplay item is owner-only (Rollout "owner") behind its own flag; OFF = the old game.

**Gates on this Windows PC:**
- `python` is the Store alias; use `C:/Users/shaun/AppData/Local/Programs/Python/Python312/python.exe` with PYTHONIOENCODING=utf-8
  and a forward-slash path wrapper (4 frozen pins compare POSIX paths).
- luau-compile and luau-lsp are in the session scratchpad.
- Last run: BuyPathStatic PASS=5209 FAIL=0 (parse gate on), rojo build ok, luau-lsp no new errors.
- The headless world sim and the DataService harness are not in the repo, so they were NOT run.

## Owner must create on Creator Hub
Paste each Id with `tools/wire-monetization-ids.py`. Every item stays hidden and prompts nothing while its Id is 0. Then set
`MonetizationConfig.Rollout = "all"` (and the other owner-only Rollouts) when you're happy on your account.

| Name | Type | Suggested R$ | Config key | One line |
|---|---|---|---|---|
| Skylance Interceptor | Game pass | 899 | GamePasses.PV_Skylance | Robux-only interceptor jet, a bit faster/tougher than the best cash jet |
| Stormwing Gunship | Game pass | 999 | GamePasses.PV_Stormwing | Robux-only attack helicopter |
| Leviathan Dreadnought | Game pass | 1199 | GamePasses.PV_Leviathan | Robux-only capital ship |
| Tidebreaker Assault Boat | Game pass | 299 | GamePasses.PV_Tidebreaker | Robux-only fast attack boat |
| Warlord Siege Tank | Game pass | 799 | GamePasses.PV_Warlord | Robux-only heavy tank |
| Razorfang GT Interceptor | Game pass | 199 | GamePasses.PV_Razorfang | Robux-only fast buggy |
| Bigger Army | Game pass | 249 | GamePasses.BiggerArmy | +10 soldiers in your army, forever |
| Instant Army Refill | Developer product | 49 | DevProducts.SoldierRefill | Fill your army to its cap right now |
| Plaza Airstrike | Developer product | 79 | DevProducts.PlazaAirstrike | One airstrike on the Central Plaza (3 s warning, never lethal) |
| Extra Garage Slot | Game pass | 199 | GamePasses.ExtraGarageSlot | +1 vehicle slot: keep a second vehicle out (JOB 6) |

Also: set `MonetizationConfig.Retention.GroupId` to your Roblox group id (0 hides the group-reward row).
All Robux prices live in one table: `MonetizationConfig` (RobuxPrice).
Already live and unchanged: VIP, 2x Cash, Double XP, Auto Collect, Speed Pass, cash packs x4, gold packs, Battle Pass Premium,
Army Expansion, Speed Boost, Golden Pumpjacks, Commander Starter Pack, Keep-Base Rebirth.

**Open dev tasks (not done, on purpose):**
- Extra Garage Slot: needs multi-active vehicles in VehicleService.
- Ground/naval vehicle weapons: they don't exist, so the premium tanks and boats are armour/HP/speed only.
- VIP stays at +25 % cash (not cut to the requested +10 %: live buyers paid for 25 %).
- "Skip build timer" was not added: upgrades are instant.

**Phone tests for Shaun (owner account; a second account must see none of the owner-only items):**
- **Army (v95 fix):** walk into your base with 8+ soldiers. Nobody crosses the gate, and there are two neat blocks outside facing out.
  ATTACK: rows in front of you, then a ring round an enemy (no stacking).
- **5a:** the Garage shows 6 gold "ROBUX · R$" rows. Tapping one says "coming soon" until its Id is pasted. You can already spawn
  them (owner auto-grant).
- **5b:** your chat shows the [VIP] tag if you own VIP. The VIP lounge is just north of the Town: its door lets you through, and 2 s
  on the gold pad pays $5,000 (once per 15 min).
- **5c/5d (after the Ids exist):**
  - the AIRSTRIKE button near the plaza;
  - the army-refill offer after your squad is wiped;
  - the 2x Cash / cash offer after a rebirth;
  - the cash-pack offer when a vehicle is too expensive.
- **5e:** the Shop's Robux tab starts with FREE rows (Daily Reward CLAIM, Airdrop TRACK, Favorite). With Roblox Premium you get
  +$2,500 on the first join of the day.
- **Earlier jobs** (runway, guards, map fill, JOB 4): see the sections below and ASSUMPTIONS.md.

---

# v94 — 2026-09-29 ~08:20 Dublin (Code Bot, branch phase-7-polish, WE_Build 94)

**Claude: do not redo guards fight-back / bag LOS / NPC unstick.** Merged `origin/claude/desktop-bud` (18df075) into phase-7-polish and published as WE_Build 94.

- **Guards fight back (owner-only):** `CombatConfig.GuardsFightBack` Rollout owner. A plain NPC shot by a squad unit fights that unit back (LOS, reaction, FireRate, HitChance) while no player is in range. Shooter handed via `CombatService.SetUnitShooter` (frozen squadfair pins untouched).
- **NPC unstick (owner-only):** `CombatConfig.NpcUnstick` — chase with no progress in 1.5 s jumps and sidesteps (bank planters G1/G2).
- **Bag pickup LOS (owner-only):** `OpsConfig.Cargo.PickupLosRollout` — server line of sight on bag pickup (CP-9 E4).
- **Pins:** `tools/checks/claude_bud_guards.py`; WE_Build pins bumped 93→94 (`tools/checks/codebot_v94.py`). PreferMesh stays OFF.
- Kept: v81 admin unlocks, v85 FollowPace (non-ArmyFollow), v90 jets/runway/harbor/faces/air-fix2, v91 helis + ArmyFollow, v92 plaza capture, v93 Robux + runway layout-sig.

**Still open for Claude (Bud queue):** JOB 2 army gate/formation, JOB 3 fill the map, JOB 4 features, JOB 5 monetisation.
**Still in `handoff/wip/`:** 03 (+03b) army lane B, 04 (+04b) army lane A, 07 ground2 records, 09-12 VKIT.

**Phone tests for Shaun:**
- Guards (owner account): take the army to the Empire Bank and ATTACK the guards while you stand more than 90 studs away. Guards shoot your soldiers (tracers, soldiers lose HP). Walk in front of the hall so G1/G2 chase you past the planters: they hop or step around them instead of sticking. A second account should see the old guard behaviour.
- Migrate to Latest Update (or shut down old servers) before testing.

---

# v93 — 2026-09-29 ~00:29 Dublin (Code Bot, branch phase-7-polish, WE_Build 93)

**Claude: do not redo Robux products or the runway layout-sig fix.** Merged `origin/claude/desktop-bud` (72c2b12 + d9c2b77) into phase-7-polish and published as WE_Build 93.

- **3 Robux products (owner-only):** Speed Pass game pass 1998656357, Keep-Base Rebirth 3714663721, Golden Pumpjacks 3714663783.
  `MonetizationConfig.Rollout = "owner"` + `RolloutKeys` + `SkuLiveFor`. Shop/prompts/pads gated per player; **ProcessReceipt is never gated**.
  Golden Pumpjacks: gold pumps pay `IncomeMult` 1.5 (+50% Pending cash). World ATM pads skip gated keys until Rollout = "all".
- **Runway layout-sig rebuild:** `MapSetup.LAYOUT_SIG` / `WE_LayoutSig` in MapSetup + Bootstrap rebuilds a saved pre-v90 map so the runway is 190×29 and hangar 68×40 (v90 sizes). Check: `tools/checks/claude_bud_runway.py`. PreferMesh stays OFF.
- **Pins:** `tools/checks/claude_bud_monetization.py` + `tools/checks/claude_bud_runway.py`; WE_Build pins bumped 92→93.
- Kept: v81 admin unlocks, v85 FollowPace (non-ArmyFollow), v90 jets/runway/harbor/faces/air-fix2, v91 helis + ArmyFollow, v92 plaza capture.

**Still open for Claude (Bud queue after v94):** JOB 2 army gate/formation, JOB 3 fill the map, JOB 4 features, JOB 5 monetisation.
**Still in `handoff/wip/`:** 03 (+03b) army lane B, 04 (+04b) army lane A, 07 ground2 records, 09-12 VKIT.

**Phone tests for Shaun (from Claude Bud handoff):**
- Robux (owner account only): Shop shows Speed Pass (5 R$) and Golden Pumpjacks (49 R$); Speed Pass makes you faster and the army keeps up; Rebirth panel shows KEEP BASE R$ 50; Golden Pumpjacks turns pumps gold with ~+50% Pending cash per tick. A second account sees none of these.
- Runway: join a NEW server ("Migrate to Latest Update" first). Runway from west plot wall almost to helipad lane (190 long, 29 wide, dashes all the way). Jet spawns at west end and takes off along the whole strip. Hangar is not inside any building.

---

# WHERE I STOPPED — 2026-09-28 (Claude on Bud, branch claude/desktop-bud)

Queue (owner's order): [x] Robux 3 products · [x] runway · [x] guards (fight back, bag LOS, unstick G1/G2) · [x] new JOB 2 army
gate/formation · [x] JOB 3 fill the map · [x] JOB 4 features (supply drops, daily reward, plaza bounty, army upgrades) · [ ] JOB 5 monetisation (5a Robux vehicles DONE; next 5b passes: VIP chat tag + VIP area, Bigger Army pass, Extra Garage slot; then 5c, 5d, 5e, then the Creator Hub list).

**Done, pushed:**
- (rebased on v95 phase-7-polish) ARMY FIX after the owner's v95 test: the army holds before the gate (no path through it, no teleport),
  validated clean hold grid facing out, ATTACK gives every soldier its own spot (march rows / target ring). Kill switch `Follow2.Tidy.Rollout = "off"`.
- 5a: six Robux-only vehicles (Skylance jet, Stormwing heli, Leviathan + Tidebreaker boats, Warlord tank, Razorfang buggy),
  own passes (Ids 0: TODO owner), about +5 % over the best cash vehicle, owner-only, gold ROBUX rows in the Garage.
- Robux: Speed Pass 1998656357, Keep-Base 3714663721 and Golden Pumpjacks 3714663783, owner-only (`MonetizationConfig.Rollout = "owner"`).
- JOB 4 (each owner-only, own flag): parachute **airdrop** every 10 min with marker (`SupplyDropConfig.Airdrop`); **daily streak**
  auto-claimed on join (`DailyRewardConfig.AutoClaim`); **plaza bounty** $15k for retaking the plaza within 3 min (`PlazaBountyConfig`);
  **Army Upgrades** prompt at your Barracks, which opens the Soldiers research (`ArmyUpgradeConfig`). Check: `tools/checks/claude_bud_features.py`.
- Map fill (everyone, kill switch `WorldFillConfig.Enabled`): **planned parts Full 388 / Low 198** in `Workspace.WorldFill`
  (world total about 2,864 / 1,877 against caps 2,900 / 1,900): 4 connector roads to the plaza, 2 bridges over dock channels,
  6 army positions between the bases, 4 light plaza posts, terrain rocks. Check: `tools/checks/claude_bud_worldfill.py`.
- Army (owner-only, `ArmyConfig.Follow2.Tidy`): the army stops in neat rows outside your main gate facing out and never enters your plot;
  fixed seats in the wedge, no crossing when you turn; after you leave the base they run back into the wedge (no teleport for 8 s).
  Check: `tools/checks/claude_bud_army.py`.
- Guards (owner-only): bank/camp NPCs shoot back at squad units that shot them; chasing NPCs jump and sidestep when stuck (G1/G2 planters);
  Ops bag pickup needs line of sight. Flags: `CombatConfig.GuardsFightBack` / `NpcUnstick`, `OpsConfig.Cargo.PickupLosRollout`. Check: `tools/checks/claude_bud_guards.py`.
- Runway: a saved pre-v90 map is now rebuilt (`WE_LayoutSig` layout hash in MapSetup + Bootstrap). Check: `tools/checks/claude_bud_runway.py`.

**How to run the gates on this Windows PC:**
- `python` is the Store alias; use `C:\Users\shaun\AppData\Local\Programs\Python\Python312\python.exe`.
- BuyPathStatic needs `PYTHONIOENCODING=utf-8`, plus a wrapper that makes paths use forward slashes (4 frozen pins compare POSIX paths).
- luau-compile and luau-lsp are in the session scratchpad (not the repo). The headless world sim and the DataService harness are not in the repo, so they were not run.

**Phone tests for Shaun:**
- JOB 4: wait about 1 min after joining for the first airdrop (marker + toast; the crate falls with a canopy, stand by it 2 s for the cash).
  About 8 s after joining you get a login streak toast. Capture the plaza with a second account, then retake it with yours within 3 min: +$15,000.
  At your Barracks, tap "Army Upgrades": the Research panel opens on Soldiers.
- Map fill: drive out of the side gates (P1/P2/P5/P6). A road now runs to the main east-west road and on to the plaza. Visit the
  sandbag/watchtower positions between bases, and drive over the bridge at the west dock channel; boats pass under it. Check the frame rate
  on a mid phone. The server log line `WorldFill: quality=full parts=N skipped=M` gives the real count.
- Army: walk (then drive) into your base with 8+ soldiers. They stop outside the main gate in two neat blocks (left and right of the road),
  facing out, and none come in. Walk out: they fall in behind you in a wedge without popping or teleporting. Turn round on the spot:
  the wedge follows without soldiers running through each other. Kill switch: `ArmyConfig.Follow2.Tidy.Rollout = "off"`.
- Guards (owner account): take the army to the Empire Bank and ATTACK the guards while you stand more than 90 studs away. The guards now shoot
  your soldiers (tracers, soldiers lose HP). Walk in front of the hall so G1/G2 chase you past the planters: they hop or step around them instead of sticking.
- Robux (owner account only): Shop shows Speed Pass (5 R$) and Golden Pumpjacks (49 R$); Speed Pass makes you faster and the army keeps up;
  the Rebirth panel shows KEEP BASE R$ 50; Golden Pumpjacks turns the pumps gold with about +50% Pending cash per tick. A second account sees none of these.
- Runway: join a NEW server ("Migrate to Latest Update" first). The runway runs from the west plot wall almost to the helipad lane
  (190 long, 29 wide, dashes all the way). A jet spawns at the west end and takes off along the whole strip. The hangar is not inside any building.

---

# v92 — 2026-09-28 ~23:50 Dublin (Code Bot, branch phase-7-polish, WE_Build 92)

**Claude: do not redo / undo these.** Code Bot finished the stalled Claude-watch takeover of WIP lane **02 capture**
(`handoff/wip/02-capture_on_e506c9c.patch` on base e506c9c, 3-way merged onto phase-7-polish after v91).

- **PersistClaims = false** (`EconomyConfig.OutpostIncomeBuff`): saved outpost claims are NOT re-planted on join.
- **ReleaseOnLeave = true** (`TerritoryConfig`): a leaver's zones go Neutral at once (Home Outpost still returns on join once taken, F10).
- **StandingBar** on: CAPTURING / CONTESTED / YOURS bar. YOURS is a 5 s cue on the painted disc (`OnDisc`, `HeldSeconds=5`);
  no YOURS on top of the capture toast (`HeldAfterCapture=false`). CONTESTED follows the counted reach (blocker sees it too).
- Capturer's bar only names a zone he is counted inside this tick (CAP-16). Presence changes push to movers only (CAP-19).
- Contested pulse capped at 10 Hz. Finished Neutral contests reset to Neutral.
- **Publish note for Shaun:** use **"Migrate to Latest Update"** (or shut down old servers) so PersistClaims-on v83 servers
  do not re-plant claims during a rolling update (CAP-5 / phone_test step 0).
- Pins: `tools/checks/codebot_v92.py` + the fb4 capture block already in `tools/BuyPathStatic.py`. Assumptions appended
  from `handoff/wip/notes/02-capture/assumptions.md` (CAP-1..CAP-22).
- Kept: v81 admin unlocks, v85 FollowPace (non-ArmyFollow path), v90 jets/runway/harbor/faces/air-fix2, v91 helis + ArmyFollow.

**Still in `handoff/wip/` (not this ship):** 03 (+03b) army lane B, 04 (+04b) army lane A, 07 ground2 records, 09-12 VKIT.

---

# v91 — 2026-09-28 ~23:45 Madrid (Code Bot, branch phase-7-polish, WE_Build 91, place versions 87 + 88)

**Claude: do not redo these.**
- **Helicopters (owner's choice):** every heli key wears the attack heli 11240665977, owner-only like every heli body
  (`Rollout = "Body"`). Each key has its own colour on the body panels only (`HELI_PAINT_PARTS`: BAP 1, Body, Doors,
  Thing for Blades); glass, seats, blades, wheels and engines keep theirs. Built with `heliRef(scale, colour, cabin, note)`.
  - Transport keys get a bigger scale to fit their bigger kit (TransportHeli 0.52, HeavyLiftHeli 0.6, Medevac and LightTransport 0.48;
    the rest 0.45). Seats, after live raycasts on place v87 (the commit after the first v91 publish, place v88):
    - crew at (±4, 5.4, -30): 3.4-4.8 studs under the glass (narrow kits had 2.5 at 6.0);
    - rear pair at (±3.5, 5.0, -21) and the middle seat at (0, 5.0, -25), inside the cabin with hull on both sides.
      The old z -13 rear pair stuck out of the tail.
  - The main Blades spin through the v90 rotor lookup.
  - `BODY_LIGHT_HELI` / `BODY_TRANSPORT_HELI` are kept, unused (a one-line revert).
  - AttackHelicopter keeps its own navy (27,42,53). StealthHeli keeps near-black (20,22,26), a whole-body recolour as in v88.
  - Colours: GunshipHeli gunmetal 74,80,88 · EscortHeli slate blue 78,98,124 · NightAttackHeli dark olive 58,62,40 ·
    LightScoutHeli olive drab 100,108,68 · UtilityHeli khaki 150,138,100 · RescueHeli desert sand 190,168,122 ·
    MedevacHeli light grey 160,164,168 · TransportHeli forest green 54,78,56 · LightTransportHeli sage 118,134,112 ·
    HeavyLiftHeli earth brown 116,92,66. VTOLTransport keeps its own tilt-rotor body.
- **Army FOLLOW overhaul, live for EVERYONE** (`ArmyConfig.Follow2.Rollout = "all"`; set it to `"off"` to go back to the old follow).
  New `Server/Modules/ArmyFollow.luau`; SquadOrdersService hands it FOLLOW movement (`_AFOn`) and keeps the lifecycle
  and shooting. The v85 FollowPace and v90 Fix follow/recover are bypassed while it is on.
  - **What was wrong:** soldiers collided with each other (every HumanoidRootPart collides, all in Default). At a run they
    shoved, tripped (FallingDown/Ragdoll) and got flung. A unit flung under the map lost its root to
    FallenPartsDestroyHeight; for everyone but the owner that unit then stayed in the squad as an invisible ghost forever.
    SyncArmy only culls dead or parentless models, and the v90 re-form was owner-only. That was the "despawn".
    On top of that: no per-unit spacing, catch-up capped at 28 (or the v85 multipliers), and regroup was owner-only and slow.
  - **Now:**
    - wedge slots behind him, turned by his move direction;
    - separation steering, and CollisionGroup `WE_Squad` never collides with itself;
    - trip/ragdoll states off;
    - straight MoveTo while the slot is in sight, pathfinding only when blocked (1.5 s per unit, 8 per server per second,
      path kept while its end is within 8 studs of the slot);
    - catch-up speed = max(his WalkSpeed incl. Speed Pass/Boost, his measured speed) x 1.35 plus 0.6 per stud behind,
      capped at max(owner x 1.8, 34);
    - regroup teleport (one PivotTo to a ground-checked clear spot behind him, never a delete) when: 70 studs from its slot
      for 1 s, stuck 3 s, under the map, or right after he teleports/respawns;
    - a unit that lost its root is re-formed for everyone;
    - every removal, death, root loss and regroup is logged `[ArmyFollow] ...` (rate-limited).
  - **Own base:** while he is inside his own plot square (4 studs in; out again 2 studs past the edge), his units wait spread
    out 12-16 studs outside his main gate, beside the gate lane and never in it. They re-form behind him when he comes out.
  - **Checks:** the Open Cloud session has no physics (GetRealPhysicsFPS 0) and no built map, so the check was a
    kinematic stand-in (units walk to their WalkToPoint at their WalkSpeed). Owner sprinting at 26 for 20 s, turn, stop,
    diagonal, base, exit: 0 units lost, formation within 25 studs while running, 0 units inside the plot during the base
    phase, re-formed after the exit. Real physics and the wait line on the real map need the phone test.
- Pins: `tools/checks/codebot_v91.py`. It retires 3 frozen army-fix pins and 1 v90 pin (the cull/trim now log first, and the
  ArmyFollow branch runs before recoverUnit).

---

# v90 — 2026-09-28 ~22:30 Madrid (Code Bot, branch phase-7-polish, WE_Build 90, place version 86)

**Claude: do not redo these. Shipped from `handoff/wip/` plus the owner's answers to the questions below.**
- **01 army despawn fix**: merged onto HEAD behind the new `ArmyConfig.Rollout.Fix = "owner"`. Only shaunie6's squads use the fix
  (Follow / Recover / Gate-open blocks via `SquadOrdersService._FixLive`, `reformRootless(uid)`, and the GateDefense gate-open
  `LiveFor("Fix")`). For him it replaces v85 FollowPace (`_PaceBegin` returns false); everyone else keeps v85 / 4d26673.
  NOT done: Claude's r1 re-measure (GATECAMP, UNDER, hall with guards down, T3), because it needs the stand-in/phone. Go-live for everyone: `Rollout.Fix = "all"`.
- **05 harbour** (the dock boat and building as a Part kit): live for everyone, kill switch `DockKitConfig.Enabled = false`. Visual only, 0 new assets.
- **06 floating faces**: live for everyone (client-only visual). Switches: `Escort.Camera.GuardHz = 0` / `LeadScreenFrac = 0`.
- **08 air fix-2** (rotor `Under` scope, chase-zoom span, rotor joint not counted as a pin): live. No current ref uses `Under` yet.
- **Owner answers:**
  - **Jets:** StrikeJet, CASJet and StealthStrike (plus the StealthStrikeJet ref) now wear jet 14589101870 with the pilot inside,
    using the FighterJet layout. They stay owner-only (`Rollout = "Body"`), like the v88 bodies they replace. The v88 tables
    `BODY_STRIKE_JET` / `BODY_STEALTH_STRIKE` are kept, unused, so reverting is one line.
  - **Jet colours:** each jet has its own colour on its grey panels only (`BodyColorParts = JET_PAINT_PARTS`). The black trim
    and the glass canopy keep the approved look.
    Palette (RGB):
    - FighterJet: air-superiority grey (118,126,136)
    - InterceptorJet: navy blue-grey (64,82,108)
    - TrainerJet: desert sand (184,162,118)
    - LightFighter: olive drab (96,104,66)
    - StrikeJet: dark green (62,82,60)
    - CASJet: earth brown (126,100,72)
    - StealthStrike (and the StealthStrikeJet alias ref): charcoal (46,48,54)
    The colours on the four original jets show for everyone. The three new jet keys are owner-only.
  - **Runway:** 170 x 24 → 190 x 29. It can't be longer: the plot edge is at X -160 and the HeliApron at X 34.
  - **Hangar:** 58 x 34 → 68 x 40 (+17 %). The site moves to Z -125 and the shell scales by Width/58.
  - **Bridge Layer:** wades through water like the Amphibious APC (0.4 x speed). Server-authoritative,
    owner-only (`VehicleConfig.Drive.WaterRule.AmphibiousRollout = { BridgeLayer = "owner" }`).
- **Left in `handoff/wip/`** (the README rows give the status): 02 capture, 03 lane B, 04 lane A, 07, 09-12 VKIT. Lane C was not started.
- **Pins:** `tools/checks/codebot_v90.py`, plus Claude's lane pins moved to `codebot_v90_airfix2.py`, `codebot_v90_harbor.py` and `codebot_v90_faces.py`.

---

# WHERE I STOPPED — 2026-09-28 ~19:40 UTC (branch claude/war-empire-phase-7-toqwff)

**What I was doing:** shipping the army despawn fix (fix round r1), plus review rounds for the capture, harbor and faces fixes, and building the Part-made vehicle bodies (VKIT). The owner asked me to stop, so all workflows are stopped and nothing is scheduled.

**Finished and pushed (live-ready):**
- `af4c7d4`: ground vehicles can't drive on water.
- `4d26673`: army escorts shoot back at the bank, with tracers (owner-only rollout).
- `4e07fc2`: the owner's jet on the four jet keys, pilot inside, Ride on the Trainer.

**Left (all saved as patches in `handoff/wip/`; not built, not live; the table in `handoff/wip/README.md` gives each base and status):**
1. ~~Army despawn fix (`01`)~~: **shipped in v90, owner-only (`Rollout.Fix`)**. Still open: the r1 re-measure on a device/stand-in.
2. Plaza capture fix (`02`), then army lane B checkpoints (`03`, rebase after 02). **Still open** (not shipped in v90).
3. Army lane A, guard and follow (`04`): finish tests and rebase onto the shipped `01`. **Still open.** Lane C (ATTACK marches to checkpoints) is not started.
4. ~~Harbor boat and dock (`05`), faces (`06`) and air fix-2 (`08`)~~: **shipped in v90** (their review rounds were done by Code Bot while merging).
5. VKIT vehicle bodies (`09`–`12`): ground fix-2 and naval deliverables are half-done. ground2 records (`07`) wait on VKIT ground. **Still open.**
6. Water Lows: land spot behind walls, rider teleport prefetch, hover above 160 studs, shallow reverse. **Still open.**
7. Owner questions (**answered by the owner 2026-09-28; all done in v90 except the helicopter**):
   - Should the Strike, CAS and Stealth jets get his jet? **Yes**: they now use 14589101870 with the pilot inside (v90, owner-only like v88).
   - Is the jet's look OK? **Yes, approved**: kept.
   - Should each jet get its own colour? **Yes**: one military colour per jet key (v90; palette in the v90 note).
   - Should the runway and hangar be bigger? **Yes, slightly (15-25 %)**: runway 190 x 29, hangar 68 x 40 (v90).
   - Should the Bridge Layer be amphibious? **Yes, it should cross water**: it wades, owner-only, server-authoritative (v90).
   - New helicopter model (the uploader made every part, 35 parts or fewer)? **Yes, wanted. The owner is handling the search himself: do NOT search.** Wire it once he sends the id.

**Files:** `handoff/wip/*.patch` (12 lanes, plus 03b/04b base patches), `handoff/wip/README.md` and `handoff/wip/notes/` (phone tests, owner texts, assumptions and the army design spec).
**Owner phone test right now:** nothing new. `src/` is unchanged since 4e07fc2.

---

# LATEST HANDOFF — Code Bot Roblox replacement (20 Sep 2026 ~00:00 Madrid)

> **v89 (28 Sep 2026, Code Bot): the wc7 capital ships + airlifter are WIRED — owner-only, same system. Claude: do not redo.**
> Destroyer 6860896505 (Stud Class, 0.2) and Cruiser 6860896505 (0.22), both Yaw 180 (bow = the pointed +Z end with the
> full-depth stem; the rounded overhanging -Z end is the stern: wc7's Yaw 0 note was flipped after the side-profile
> raycasts), MissileCruiser 104820847233642 (18, BodyMaxScale 18, bow -Z), Battleship 12442299148 (2.0, bow -Z); all
> dark naval grey (58,62,68), captain inside the bridge, kit TurretF/BarrelF/TurretA moved onto the body turrets
> (BodyMounts). CargoPlane/AWACSPlane/TankerPlane now 10649792198 (4-engine airlifter, 2.1, Yaw -90, dark grey;
> replaces 17033079003). The v88 capital-ship NoFamilyFallback exclusion is gone (own bodies now). StrikeJet stays
> 3553891209. Every air / naval vehicle with a definition now wears a body for the owner. Pins: tools/checks/codebot_v89.py.

> **v88 (28 Sep 2026, Code Bot): the wc6 winners are WIRED too — owner-only, same system. Claude: do not redo this.**
> VTOLTransport 80886282228822 (both proprotors spin), AttackHelicopter/GunshipHeli/EscortHeli/NightAttackHeli
> 11240665977 (main rotor spins), StealthHeli = 11240665977 recoloured near-black (NOT 11839207737: a real Little
> Bird look-alike), StrikeJet/CASJet 3553891209 (gear omitted, texture cleared, dark), StealthStrike/StealthStrikeJet
> 7976374439, CargoPlane/AWACSPlane/TankerPlane 17033079003 at BodyScale 30, dark grey (replaces 2475398012),
> LandingCraft/AssaultLanding 12235335847 (anchor + chain omitted), HospitalShip/SupplyShip 2625253037, HoverTransport
> 3626114334. New ref fields: BodyMaxScale (cap 4..40), BodyAnchorX (carrier + amphib: the body also shifts across so
> the captain sits in the island). Still on the kit (search ongoing): Destroyer, Cruiser, MissileCruiser, Battleship —
> now NoFamilyFallback so they never inherit the LandingCraft barge. Pins: tools/checks/codebot_v88.py.

> **v87 (28 Sep 2026, Code Bot): air + naval store bodies are WIRED — owner-only. Claude: do not redo this.**
> 29 vehicles wear the owner's picks through the 4e07fc2 body system (VisualAssetConfig `BODY_*` tables + `bodyRef`,
> VisualAssetService fit, AirBodyRig), gated by `VisualAssetConfig.BodyRollout = "owner"` + per-ref `Rollout = "Body"`
> (only vehicles spawned by shaunie6 / 470626172 wear them; everyone else keeps the Part kit, no load):
> light helis 3130894523 (LightScoutHeli, UtilityHeli, RescueHeli, MedevacHeli; kit rotor spins on the mast),
> transport helis 109615982233602 (TransportHeli, LightTransportHeli, HeavyLiftHeli), bombers 14669079591
> (StrikeBomber, HeavyBomber, StrategicBomber; Bay mount under the centre), transports 2475398012 (CargoPlane,
> AWACSPlane, TankerPlane), patrol 16692908395 (PatrolBoat, FastAttackCraft, RiverBoat, CoastCutter, TorpedoBoat),
> gunboat 15838664806 at 0.027 (Gunboat, MissileBoat, MineLayer, CoastalMonitor; per-ref BodyMinScale), frigate
> 473576954 (Corvette, Frigate, CarrierEscort), carrier 7941124517 (FleetCarrier; BodyDeck plates), amphib 5545544418
> (AmphibAssault), sub 116924692473761 (SubSurfaceRunner, AttackSub; propeller spins). New ref fields: Rollout,
> BodyMinScale, BodyWaterline, BodyColor/BodyMaterial/BodyClearTexture, BodyDeck, BodyKitNoCollide, KitRotor.
> Kept on the kit (owner decision): Destroyer, Cruiser, MissileCruiser, Battleship (16675798409 rejected: real class),
> VTOLTransport (NoFamilyFallback), attack/gunship/escort/night/stealth helis, strike/CAS/stealth jets, landing craft,
> hospital/supply ships, hover transport. Pins: tools/checks/codebot_v87.py. To open to everyone later: BodyRollout = "all".


Shaun created you because the previous Code Bot Roblox chat **wedged** (messages failed to send). You replace it. Code/GitHub/laptop Studio are intact.

## Read first
1. `/workspace/war-empire/HANDOFF-TO-NEW-CODE-BOT.md` — MASTER SYSTEM INSTRUCTION + WAR EMPIRE brief
2. `/workspace/war-empire/MASTER_BUILD_SPEC.md`
3. `/workspace/war-empire/ASSUMPTIONS.md`
4. This file

Save operating rules to agent memory (profile): build don’t tutor; COMPLETED/FILES/TESTING/NEXT; local iteration; push to https://github.com/shaunbirrell/war-empire; ask only when architecture-breaking.

## Repo / branch
- Remote: https://github.com/shaunbirrell/war-empire
- Working branch: **`phase-7-polish`** (latest commit at handoff: **`b009165`** — BUY bootstrap fix)
- Earlier PRs: #1 phase-3-combat, #2 phase-5-territory, #3 phase-7-polish (may need refresh)
- Local: `/workspace/war-empire`
- Place builds: `dist/WarEmpire.rbxlx`, `dist/WarEmpire-PERF.rbxlx`
- Shaun’s laptop: `C:\Users\laura\Downloads\WarEmpire-PERF.rbxlx` (machineId `be2ced83-f720-49b1-a3c0-1100e04ffc10` — Lara’s Windows laptop used for Studio)

## What the previous bot was doing (transcript summary)

### Product progress
Phases 1–7+ heavily expanded beyond MVP:
- Foundation, tycoon, combat, vehicles, territory, missions, monetization, tutorial, battle pass, clans, seasons, soldiers, bank raids, spinner, upgrade pads, desert map restyle, bank guards AI, mobile HUD, perf cuts, void/fall safety, world prompts / BUY pads

### Critical live bug (LAST FOCUS — claimed fixed, needs Shaun confirm)
**Command Center BUY broken in Studio Play:**
1. `CombatService/init.luau` required `VisualAssetService` via wrong path (`script.Parent.Parent` → Server), crashing Bootstrap
2. Crash happened **before** remotes finished → client error `RemoteEvent missing: SpinnerStateUpdate`
3. HUDController died → WorldPromptController never inited → no BUY button

**Fix shipped in `b009165`:**
- Correct require → `script.Parent.VisualAssetService`
- `RemoteSetup.Init()` early + idempotent
- UIController `safeInit` pcall so WorldPrompt always runs
- Rebuilt rbxlx; copied to laptop Downloads as `WarEmpire-PERF.rbxlx`

**Shaun was asked to:** Stop Play → open new Downloads file → Play → stand on Command Center → expect gold BUY + walk-buy; cash $5000 → $3500. **He has not confirmed yet** (chat wedged).

### Other open work from previous todos
- Verify BUY + all dock/buttons end-to-end
- Playtest on laptop Studio until solid
- Studio/Creator assets for soldiers/guards/buildings/vehicles (in progress / cancelled stick approach)
- Overnight polish / MVP completion pass

### Git commit tip
Do **not** write `git config`. Use env:
```
export GIT_AUTHOR_NAME="Code Bot Roblox"
export GIT_AUTHOR_EMAIL="codebot@war-empire.local"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
```

### Shaun prefs
- Speed: keep chaining, local executors over Cloud Agents
- Copy rbxlx to his laptop Downloads when shipping playtest builds
- Roblox username seen in logs: `shaunie6`
- Spanish Windows path (`El sistema no puede encontrar…`) — laptop is Spanish locale

## Immediate job
1. Message Shaun: you’re the new Code Bot, online, you have the handoff.
2. Confirm `git log -1` on `phase-7-polish` is `b009165` or newer; pull if needed.
3. Ask if BUY works on the latest `WarEmpire-PERF.rbxlx`; if not, diagnose from Studio Output and fix.
4. Continue polish: buttons, playtest, assets — COMPLETED/FILES/TESTING/NEXT format.

Chief of Staff may ping you; Shaun’s chat is primary.
