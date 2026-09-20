# COMPETITIVE DEEP DIVE — WAR EMPIRE vs Military Tycoon (+ peers)

**Audience:** Shaun + Code Bot  
**Date:** 2026-09-20 (Europe/Madrid)  
**Primary competitor:** [Military Tycoon](https://www.roblox.com/games/7180042682) — place id **7180042682** (InfinityInteractive)  
**Secondary peers:** War Tycoon (oil-extractor + rebirth room unlocks); Military War Base Tycoon / Army Tycoon (simpler oil/nation loops)  
**Stance:** Inspiration only. No MT meshes, trademarks, Discord assets, or Infinity Tower branding. See `docs/BENCHMARK_MILITARY_TYCOON.md`.

**Sources (public):** MT Fandom (How to Play, ATM, Worker, Gamepasses, VIP, Oil Rigs, Rebirths); Roblox Wiki InfinityInteractive/Military_Tycoon; Deltia's Gaming / SportsRant / Glitch Free Guides; Rolimon's gamepass listing; YouTube titles/shorts (base expand, capture, bank heist, gems); War Tycoon Fandom (Cash, Oil Extractors, Rebirthing). Live play not performed this pass — treat numeric Robux prices as **observed ranges** (sales rotate).

---

## TLDR (Shaun)

Military Tycoon wins early retention with a **ceremonial, button-on-floor tycoon** whose first 10 minutes are: country → Begin Working → spam workers → touch **ATM (green screen)** → unlock more workers via weapons wall → peek at flags. Cash **must** be collected; Auto Collect / 2x Cash are the hero Robux SKUs. WAR EMPIRE already has the right *systems* (PendingCash collector, AutoCollect/2x/VIP stubs, training soldiers, stipends, prestige, ~99 vehicles) but the **feel** gaps are: (1) training cash bypasses the collector, (2) tutorial does not force “workers first,” (3) collector/walls/buildings still read as placeholders vs ATM + spawn-on-buy silhouettes, (4) first rebirth is gated at **Level 100** vs MT “finish base → rebirth,” (5) no novice forcefield / country ceremony. Fix those five before polishing mid-game content.

---

## 1. Competitor early-game minute-by-minute (0–10 min)

Composite of public guides + wiki (not a single filmed stopwatch). Assumes fresh account, 0 rebirths.

| Min | Military Tycoon (observed pattern) | WAR EMPIRE today |
|-----|------------------------------------|------------------|
| **0:00** | Country / flag picker full-screen. Spawn on **assigned** base. Novice **forcefield** until first weapons equipped. Empty plot + **ATM** (grey block, green cash screen) already present (survives rebirth). Codes board historically beside ATM. | Auto plot assign. `NationColorService` color (no picker UI). No forcefield. Spawn on plot. `WE_MoneyCollector` neon pillar + billboard. Codes only in Settings. |
| **0:20** | Buy **“Begin Working”** floor button → first Worker appears at range, starts “shooting” targets. Wiki: **$2 / sec** at 0 rebirths for that first worker path (also wiki notes ~$25 per worker *shot* with rebirth mult — treat as AFK shot economy flavor). | Tutorial: walk to glowing pad (**ClaimBase**). Starting **$5,000**, **5 soldiers** already owned; training tick already paying via `SoldierService` → **direct `AddCash`** (bypasses collector). |
| **1:00** | Spam buy next workers on floor 1 ($35 → $2k ladder). Touch ATM often. Optional: redeem codes. | Buy **Command Center L1 ($1,500)** via walk-over / BUY GUI. Passive structure income starts accruing to **PendingCash** (not spendable until collect). Tutorial step **Income** → touch collector. |
| **2–3** | Buy remaining floor-1 workers; start **Basic Weapons** wall (Glock→M16) because last ~5 workers are gated behind that wall. Forcefield drops when weapons equipped → player becomes raidable. | Buy **Barracks L1 ($2,500)**. Tutorial opens Garage (**Jeep**). Structure passive ~$60/tick with CC+Barracks (~$720/min) once collected. Recruit more soldiers optional ($500) — **not** tutorial-forced. |
| **4–6** | Worker huts / second-floor workers. First vehicle unlock buttons appear on floors. Income compounding is visible on ATM green digits. | Optional: DefensiveWalls / VehicleDepot. Compass points to nearest neutral territory. Mid-map travel on large ~4800 map can eat minutes if player leaves base early. |
| **6–8** | Drive/run to nearest **fortress flag**: clear NPC guards, stand ~**30s**, nation color on flag. Stipend every **~90s**. Oil rigs harder (AA/navy guards) — usually mid, not minute 7. | Tutorial **Outpost**: stand in `WE_CaptureZone`. Capture times 20–50s by POI; stipend tick **90s** (`CaptureStipend`). Oil Alpha/Bravo + Forts exist but are far / guarded. |
| **8–10** | Back to base: more workers, first meaningful walls/floors. Mentally planning first **full-base → rebirth**. Guides scream: workers before cosmetics/vehicles. | First 10 min feels “upgrade pads + jeep + maybe one capture.” Army/training income is invisible unless player opens Army UI. No rebirth in sight (needs **Level ≥ 100**). |

### YouTube / content signal (titles & themes)

Public titles reinforce the loop, not polish:

- “Expanding Your Base! (Roblox Military Tycoon)” — floor unlock spectacle  
- “Pro strategies on how to capture bases” — flag stipend as mid early-game  
- “Bank Vault HEIST Quest Event” — secondary cash spike content  
- “What is the best way to spend gems” — Diamonds sink awareness  
- NPC tanks/APCs/planes update videos — world threat spectacle  

**Implication for WE:** Creators film **buildings popping**, **ATM filling**, **flag flips**, and **Robux multipliers**. Our pads + PendingCash billboard must be that filmable.

---

## 2. Visual / presentation patterns

### Military Tycoon

| Element | Pattern |
|---------|---------|
| **ATM / collector** | Grey square prop; **bright green screen** with live accumulated Cash; touch to claim. Persists through rebirth. Codes historically adjacent. Auto Collect removes the touch loop. |
| **Buy UX** | Classic tycoon **floor buttons** with $ prices; purchasing **spawns** walls, floors, worker NPCs, weapon racks in place. Clear “base growing” silhouette every purchase. |
| **Workers** | Visible NPCs at firing range, continuously shooting targets — income feedback without opening a menu. |
| **Walls / gates** | Purchased segments fill perimeter; bunker hatch / floors create vertical base identity. |
| **HUD** | Cash/Diamonds prominent; rebirth / country near flag; shop for gamepasses obvious. |
| **Map** | Island + desert fortresses + **2 coastal oil rigs**; capture points read as big flags. |
| **Nation** | Country select + flag tint on captures. |

### WAR EMPIRE today

| Element | Pattern | Gap severity |
|---------|---------|--------------|
| **Money Collector** | Neon pillar + `WE_CollectorBillboard` (“MONEY COLLECTOR” / `$N pending`). Touch or AutoCollect ~2s. | Functional but **not ATM-iconic**; easy to miss on large plot. |
| **Buy UX** | Walk-over pads + bottom **BUY** ScreenGui + B menu; `WE_PriceBillboard` with `+$N/tick`. Kits spawn via `StructureKitBuilder` / `BaseService.UpdateVisuals`. | Correct systems; silhouette still **Part-kit placeholder** vs MT pop-in floors. |
| **Workers** | TrainingYard targets + static worker kits (visual only); income is a tick in `SoldierService`. | **No continuous shoot loop** as primary feedback. |
| **Walls / gates** | `SyncPerimeterWalls` at DefensiveWalls L1+ with spawn-side gate; corner towers from Watchtowers. | Good direction — must be **early and obvious** (L1 silhouette reads “base”). |
| **HUD** | Currency pill + mobile action dock (Base/Shop/Rebirth/Orders/Army/Settings). Compass to base/territory. | Strong mobile; collector pending not mirrored in HUD cash pill. |
| **Map** | ~4800 desert, oil Alpha/Bravo, Fort Ironclad/Sandhold, Empire Bank, supply drops, naval coast. | Content parity strong; travel distance can punish early capture tutorial. |

### Peer note — War Tycoon

Oil **extractors → barrels/collect** as the ATM analog; rebirth unlocks **rooms** (helis/tanks/planes). Same lesson: **physical collectable + visible producers**.

---

## 3. Progression & economy pacing

### MT income stack (public)

1. **Workers** (21 total; wiki total buy cost ≈ **$150,135**) — primary AFK engine  
2. **ATM collect** — converts accrued worker cash to spendable  
3. **Capture stipends** — fortresses + 2 oil rigs; ~every **1.5 min**  
4. **Codes / shop cash / events** (loot crates, bank heist, spinner, daily ops)  
5. **Rebirth** — **+0.1×** cash per rebirth, **cap ×5 at 40**; resets base purchases; keeps gamepasses / some event units; staged unlocks (bunker, NVG, AA, subs, turrets, RPG, bombers…)  

Guides: **workers first**, capture ASAP, rebirth often, buy **Double Cash** not cash packs.

### WE income stack (code)

1. **Structure passive** → `AccruePendingCash` → Money Collector (`reason collector` mult-exempt on claim)  
2. **Training soldiers** → `AddCash(..., "training")` **direct** (prestige/VIP/2x apply) — **skips collector**  
3. **CaptureStipendService** every 90s (`StipendCash` 4k–14k by POI)  
4. Combat / supply drops / bank raid / spinner / codes / missions  
5. **Prestige** at **Level ≥ 100**, MaxPrestige 50, **+10%/prestige**, rebirth unlock track in `PrestigeConfig`  

Starting: Cash **5k**, Gold 0, Soldiers **5**, CC L1 **$1500**, Barracks L1 **$2500**, passive tick **5s** base **$25** + per-level rates. Training: **$8 / soldier / 5s** (≥1 soldier).

### Pacing verdict

| Phase | MT | WE | Winner for “hook” |
|-------|----|----|-------------------|
| First meaningful buy | Begin Working (seconds) | CC in seconds (cash ready) | Tie / WE slightly smoother cash |
| First “I get it” moment | Worker shooting + ATM digits climbing | Pad BUY + pending billboard | **MT** (clearer fantasy) |
| Minute 10 power | Many workers + maybe 1 flag | CC+Barracks+Jeep+maybe 1 capture | **MT** (income identity) |
| First prestige/rebirth | After **completing base** (session(s), not L100) | **Level 100** wall | **MT** for loop addiction |
| Mid catalog | 100+ vehicles, bunker vertical, seasons | ~99 vehicles + forts/oil/bank | Content **parity OK** |

---

## 4. Tutorial patterns that don’t confuse

### What MT does well (even without a heavy modal tutorial)

- **One verb early:** buy workers.  
- **One object early:** ATM.  
- **Soft gating:** weapons wall unlocks more workers (teaches combat prep without leaving base).  
- **Forcefield** = “you’re safe while learning.”  
- **Country pick** = identity before systems dump.  
- Community wiki/Discord codes next to ATM reduce “where do I start?”  

### What confuses players (MT)

- Bunker hatch “broken” until outer hut workers bought.  
- Rebirth timing anxiety.  
- Leaving base for oil too early → death spiral.  

### WAR EMPIRE tutorial (`TutorialConfig` / `TutorialService`)

Steps: **ClaimBase → CommandCenter → Income (collector) → Barracks → Jeep → Outpost**.

**Strengths:** Short copy; pad CTAs; markers; SKIP; server-advanced.

**Confusion risks vs MT:**

1. Never says **“recruit / watch soldiers train”** — but training is a major cash line.  
2. **Income step** only covers structure PendingCash; player may not realize training already paid them.  
3. **Jeep before second income spike** — MT delays vehicles until workers stacked.  
4. **Outpost** on a huge map without a guaranteed nearby soft territory can stall the last step.  
5. No forcefield → first PvP death during tutorial feels like a bug.  

**Non-confusing tutorial recipe for WE:** one step = one verb + one world object; never open a second menu mid-step; keep first capture **≤150 studs** from plot; put **Recruit / Training Yard** before Garage.

---

## 5. Monetization — map to our DevProducts / GamePasses

### MT (Rolimon's / wiki / guides — prices float with sales)

| SKU (theme) | Observed role | Approx Robux (public listings) |
|-------------|---------------|--------------------------------|
| **Double Cash / x2 Cash** | Permanent cash mult; guides say **best** spend | ~299–499 (sale/list variance; one pass page showed 399) |
| **Auto Collect** | Skip ATM touch; AFK hero pass | ~249 (Rolimon's); guides also cite ~349 |
| **VIP** | Wiki: ~349 — +cash flavor, +15 HP, VIP chat tag; guides sometimes quote higher + exclusive vehicles | 349–799 depending on source/era |
| **Super Worker** | Income unit boost | ~99 |
| **2X Vehicle EXP** | Progression accel | ~1249 |
| **Season / War Pass** | Rotating battle-pass analogs | ~699 band |
| Exclusive vehicles / weapons packs | Pay-to-skip catalog | Various / often offsale rotated |
| Cash / Diamond packs | Weaker than 2x per guides | Shop |

Stacking note (wiki): Double Cash, Double HP, VIP can stack.

### WAR EMPIRE (`MonetizationConfig`) — all **Id = 0** until Creator Dashboard

| Our key | Type | Listed Robux | Maps to MT theme | Grant path |
|---------|------|--------------|------------------|------------|
| `GamePasses.AutoCollect` / `DevProducts.AutoCollect` | GP + DP entitlement | 99 | Auto Collect | Entitlement `AutoCollect` → collector auto-claim |
| `GamePasses.DoubleCash` / `DevProducts.DoubleCash` | GP + DP | 149 | Double Cash | `CashMult = 2` / entitlement |
| `GamePasses.VIP` / `DevProducts.VIPBoost` | GP + DP | 199 | VIP (+25% cash; we lack HP/tag/exclusives) | `CashBonusMult = 0.25` |
| `GamePasses.DoubleXP` | GP | 99 | Soft analog to 2X Vehicle EXP (weaker / different) | XP mult |
| `DevProducts.ExtraSoldierSlot` | DP | 79 | Super Worker / Extra Soldier | Entitlement |
| `DevProducts.InstantBarracks` | DP | 129 | Soft “skip early button” | Barracks L1 grant |
| `DevProducts.StarterBundle` | DP | 249 | Starter pack | Cash+Gold |
| Cash/Gold S/M/L packs | DP | 49–399 | Cash/Diamond packs | Flat grant (mult-exempt) |
| `DevProducts.PremiumPass` | DP | 499 | Season / War Pass | Battle Pass Premium |
| `GamePasses.ExtraPlotCosmetic` | GP | 79 | Cosmetic base theme | Cosmetic only |
| Loot boxes | — | — | Paid crates | **`LootBoxPolicyPending`** — keep off |

**Pricing posture vs MT:** Our AutoCollect/2x/VIP are **cheaper stubs** — good for launch conversion; raise toward MT bands only after live Id wiring + retention data. Prefer **permanent multipliers** over cash packs in Shop sort order (match Deltia guidance).

**Missing MT monetization themes (optional later, not copy):** exclusive pay vehicles, Super Worker NPC, Instant Rebirth, Double HP, radio/cosmetic social.

---

## 6. GAP LIST vs WAR EMPIRE (prioritized)

### P0 — retention / “feels like the genre” (do first)

| ID | Gap | Why it hurts | Evidence |
|----|-----|--------------|----------|
| **P0-1** | **Training income bypasses Money Collector** (`SoldierService` → `AddCash("training")`) while structure passive uses PendingCash | Breaks the ATM fantasy; AutoCollect feels half-baked; tutorial “Collect cash” under-teaches | ASSUMPTION #102 vs SoldierService tick |
| **P0-2** | **Tutorial order ≠ MT worker-first** (CC → collect → barracks → jeep; no Recruit/Training Yard step) | Players don’t learn the core AFK engine in minute 1 | TutorialConfig vs Deltia/wiki |
| **P0-3** | **Collector presentation weak** (neon pillar vs grey+green ATM digits; pending not on HUD cash pill; no pulse/sfx when pending high) | Collect loop not filmable / easy to ignore on 200-stud pads | ATM wiki + MoneyCollectorService billboard |
| **P0-4** | **First rebirth too late** (Level 100) vs MT “finish base → rebirth” | Loop addiction & creator “first rebirth” content missing | PrestigeConfig.MinLevelToPrestige |
| **P0-5** | **Workers not readable as income** (static kits; no shoot loop / range VFX; Army buried in dock) | MT’s “little robots shooting” is the genre logo | MapSetup TrainingYard + guides |

### P1 — strong competitive polish

| ID | Gap | Notes |
|----|-----|-------|
| **P1-1** | No novice **forcefield** / safe window until first weapon or tutorial complete | Early PvP deaths on open PvP servers |
| **P1-2** | No **country / nation picker** ceremony (only auto NationColor) | Identity moment MT opens with |
| **P1-3** | **Spawn-on-buy silhouettes** still Part-kit thin; perimeter walls not forced early in tutorial | DefensiveWalls L1 should be a tutorial beat after barracks |
| **P1-4** | Capture tutorial may be **too far** on ~4800 map | Soft “Training Outpost” ≤150 studs from each plot |
| **P1-5** | Shop does not **hero-sort** AutoCollect / 2x / VIP; all Ids=0 | Wire dashboard Ids; pin multipliers above cash packs |
| **P1-6** | VIP underpowered vs MT (no HP, tag, exclusives) | Decide WE-original VIP kit (chat tag + small HP + 1 cosmetic jeep skin) |
| **P1-7** | Codes not surfaced at collector | Settings-only; MT taught codes beside ATM |
| **P1-8** | Prestige unlock cadence not “room/bunker” spectacular | RebirthUnlocks exist — need UX fanfare + base props gated by prestige flags |

### P2 — later / nice-to-have

| ID | Gap |
|----|-----|
| **P2-1** | Floor-button tycoon path (optional hybrid) vs pads-only |
| **P2-2** | Loadout mannequin / last-loadout restore |
| **P2-3** | Super-worker style paid income unit (careful balance) |
| **P2-4** | Instant Rebirth product |
| **P2-5** | Vehicle mastery / fusion / trading (MT late systems) — out of scope for MVP parity |
| **P2-6** | War Tycoon-style oil extractor props as *extra* producers (we already have coastal oil captures) |
| **P2-7** | Creator-Store mesh density when Studio PERF allows (already hooked via VisualAssetConfig) |

### Already in good shape (don’t rewrite)

- Capture stipend + oil + forts + bank raid + supply drops + spinner + daily ops + codes  
- Prestige mult +10% + unlock track  
- AutoCollect / DoubleCash / VIP entitlement plumbing  
- ~99 vehicle ladder + naval/dock  
- Mobile dock + pad BUY + price billboards  
- Legal stance / no MT IP  

---

## 7. Implementation backlog for Code Bot

Concrete file/system targets. Inspiration-only naming.

### Sprint A — P0 economy fantasy (collector + workers)

1. **Unify AFK cash into PendingCash**  
   - `src/ServerScriptService/Server/Services/SoldierService.luau` — training tick calls `EconomyService.AccruePendingCash(..., "training")` instead of `AddCash`.  
   - Confirm `MonetizationConfig.CashMultExemptReasons.collector` still correct (mult at accrue).  
   - Update ASSUMPTIONS #102 / BALANCE.md one-liners.  
   - Optional: stipend mid-term decision — keep direct AddCash (map loot fantasy) vs also pending (stricter ATM). **Recommend:** training + structure pending; stipends/combat stay direct.

2. **Tutorial rewrite (worker-first)** — `TutorialConfig.luau`, `TutorialService.luau`, `TutorialController.luau`, MapSetup markers  
   - New order proposal: ClaimBase → **RecruitSoldiers** (or “Watch Training Yard”) → **Collect** → CommandCenter → Barracks → **Walls** → Jeep → NearbyOutpost.  
   - Add `TutorialService.Notify` hooks for Recruit + Collect pending > 0.  
   - Place `Tutorial_Outpost` beacon on a **near** neutral zone per plot ring.

3. **Collector presentation** — `MoneyCollectorService.luau`, MapSetup collector kit, HUD controller  
   - ATM-like Part kit: matte grey body + **green ScreenGui digits** (not neon-only).  
   - Pulse / PointLight when `PendingCash ≥ threshold`; collect SFX.  
   - HUD cash pill shows `Cash` + dim `+$pending` or tap-to-collect hint.  
   - Optional codes prompt Billboard near collector (redeems still Settings/`CodesService`).

4. **Training Yard feedback** — MapSetup / SoldierService / small client VFX  
   - Animate or beam-shoot from worker kits to targets on a Heartbeat/interval while soldiers > 0.  
   - Floating `+$` billboard ticks on yard (client cosmetic; server remains authoritative).

5. **Earlier first rebirth path** — `PrestigeConfig.luau`, Progression UI, BALANCE.md  
   - Options (pick one with Shaun):  
     - **A:** `MinLevelToPrestige = 25` (or 30) + require N structures at L1; or  
     - **B:** Keep L100 “Prestige” but add **`BaseRebirth`** after full L1 structure set (MT-like) with smaller mult.  
   - Ship fanfare UI + reset kit refresh (`BaseService.RefreshAllVisuals`).

### Sprint B — P1 onboarding & shop

6. **Novice protection** — CombatService / GameConfig  
   - Forcefield or `PvPEnabled` false until tutorial complete **or** first weapon equip.

7. **Nation picker** — thin UI on first join writing `NationColorId` (NationColorService already tints flags).

8. **Tutorial Walls step** — ensure `SyncPerimeterWalls` fires and is visible (`StructureKitBuilder.luau`, BaseService).

9. **Shop hero row** — Shop controller: sort AutoCollect, DoubleCash, VIPBoost first; hide loot-box row; keep Id=0 safe. Dashboard wiring checklist in `docs/PUBLISH_CHECKLIST_PHONE.md`.

10. **VIP WE-original perks** — MonetizationService + chat tag + optional +HP in CombatConfig when VIP owned.

### Sprint C — P2 spectacle

11. Prestige-gated base props (bunker hatch analog — original name e.g. **Deep Command**).  
12. Soft floor-button mode experiment on one structure row.  
13. Loadout restore stub.  
14. VisualAsset live density when not StudioSkipWorldDressing.

### Verification

- `python3 tools/BuyPathStatic.py`  
- Studio: fresh profile, SkipTutorial false — confirm PendingCash rises from **both** structures + training; collect clears; AutoCollect entitlement mock.  
- Do **not** publish Roblox from this research task.

### Non-goals (restate)

- No MT asset scrape, no Discord shout rewards, no paid loot boxes while `LootBoxPolicyPending`, no trademarked names.

---

## Appendix A — Side-by-side system map

| Theme | MT | WE system |
|-------|----|-----------|
| Collector | ATM | `MoneyCollectorService` + PendingCash |
| Workers | 21 range NPCs | `SoldierService` + TrainingYard |
| Buttons / pads | Floor buttons | Walk-over `WE_UpgradeSlot` + BUY GUI |
| Capture | Flags ~30s | TerritoryCapture + stipend 90s |
| Oil | 2 rigs | CoastalOil Alpha/Bravo |
| Forts | 3 desert | FortIronclad / FortSandhold |
| Rebirth | Finish base, +0.1× ≤40 | Prestige L100, +10%, max 50 |
| Premium currency | Diamonds | Gold |
| Auto collect | Gamepass | GP/DP `AutoCollect` |
| 2x cash | Gamepass | GP/DP `DoubleCash` |
| VIP | GP | GP/DP VIP (+25% only today) |
| Vehicles | 100+ | VehicleConfig ~99 |
| Bank / crates / spinner | Yes | BankRaid / SupplyDrop / Spinner |

## Appendix B — Peer (War Tycoon) one-pager

- Producers: **Oil Extractors** → collectable cash objects (ATM cousin).  
- Rebirth unlocks **content rooms** (heli/tank/plane gates) more than raw mult alone.  
- Gamepasses: 2x Cash, Auto Collect, Speedy Extractor.  
**Takeaway for WE:** keep oil as **contested map stipend**, but make **base producers + collector** the emotional center — don’t let open-world content outshine the plot.

---

*End of deep dive. Update this doc after live playtests with stopwatch timings.*


---

## Pass 2 — mid/late game, monetization UX, garage flow, and driveability

**Research sweep:** 2026-09-20 (Europe/Madrid). Public wiki/guide pages and Roblox Creator documentation only; no live competitor session was performed. Treat competitor prices and exact unlock numbers as snapshots, not requirements to copy.

### 8. War Tycoon: the mid/late-game pattern

War Tycoon makes the base itself the progression map, not just a cash source:

- **Base producers compound by rebirth:** the first base has multiple large oil extractors; Rebirth 2 adds bunker oil drills; Rebirth 4 adds the gas generator. These are visible rooms/props with different output and risk profiles, so the player can see why the next rebirth matters.
- **Rebirth is a content-room gate:** completing the base and paying the rebirth cost resets cash/base purchases but preserves gamepasses and operation progress. Rebirth 1 opens the Vehicle Bay; later rebirths open the bunker, hangars, helicopter/plane systems, and Tank Factory. The reward is a new verb and a new room, not only a multiplier.
- **Garage as a protected showroom:** the Vehicle Bay has an owner-only entrance/gate, a safe spawn interior, and a selector that can show owned and locked ground vehicles. The player can select/modify/view a vehicle, then drive it through the gate. Tank Garage repeats the same pattern with research, part storage, and a protected spawn.
- **Operations bridge catalog and play:** missions unlock vehicles and give the player a reason to use the new category. Open-world oil barrels and contested rigs supplement—but do not replace—the base producer loop.

**WE implication:** `VehicleDepot` should eventually be a readable room/console with a preview and a gated exit. Prestige should unlock *rooms and verbs* (for example, a Vehicle Bay, Air Wing, or Deep Command), while cash/level gates determine individual vehicles inside those rooms. Do not add 99 more catalog rows without making the room and unlock ceremony legible.

Sources: [War Tycoon Rebirthing](https://war-tycoon-roblox.fandom.com/wiki/Rebirthing), [War Tycoon Oil Extractors](https://war-tycoon-roblox.fandom.com/wiki/Oil_Extractors), [War Tycoon Vehicle Bay](https://war-tycoon-roblox.fandom.com/wiki/Vehicle_Bay), [War Tycoon Tank Garage](https://war-tycoon-roblox.fandom.com/wiki/Tank_Garage), [War Tycoon beginner guide](https://noleep.com/en/war-tycoon-roblox-beginners-guide/).

### 9. Military Tycoon: more mid/late-game detail

The public MT progression pattern is more explicit than the first-ten-minute loop suggests:

- The **Garage** is a buildable base structure for land vehicles. Helicopters use the adjacent helipad; aircraft and ships use separate airfield/dock spaces. This makes the base silhouette advertise the next catalog category before the player opens a menu.
- The **Vehicle Manager** is the UX layer: browse owned and locked vehicles, inspect stats, equip/buy skins where available, and spawn the selected vehicle. Spawn-to-driver-seat is the expected happy path; the player should not have to hunt for a seat after pressing spawn.
- **Rebirth resets purchases but preserves long-term catalog progress** (gamepass/event units remain) and unlocks increasingly strong vehicles, weapons, bunker systems, and defensive layers. Guides repeatedly recommend buying workers/income before cosmetics and vehicles, then using a guide arrow/affordability path to find the next purchasable item.
- **Oil rigs are a mid/late skill check:** guards, AA, and naval defenses make a helicopter/boat or ranged approach useful. The rig flag remains a simple, readable capture verb and the stipend creates a reason to return.
- **Late-game spectacle is spatial:** bunker access, rooftop AA, upgraded airfield, docks, vault/defense layers, and large vehicles create “my base changed” screenshots. The catalog is stronger because the room, spawn point, and unlock are visible—not because every vehicle has a unique menu treatment.

**WE implication:** show `Category`, `Speed`, `Armor`, `Seats`, `UnlockLevel`, `RequiresStructure`, and `RequiresPrestige` on every garage card. Locked cards should explain the missing room/level/prestige rather than only showing a disabled SPAWN button. A vehicle spawn should place the player at the driver seat or provide one obvious **Drive** prompt, with a clean pad exit and one-active-vehicle rule.

Sources: [MT Base](https://military-tycoon.fandom.com/wiki/Base_(Tycoon)), [MT Vehicle Manager](https://military-tycoon.fandom.com/wiki/Vehicle_Manager), [MT Rebirths](https://military-tycoon.fandom.com/wiki/Rebirths), [MT Oil Rigs](https://military-tycoon.fandom.com/wiki/Oil_Rigs), [MT rebirth guide](https://progameguides.com/roblox/how-to-rebirth-fast-in-roblox-military-tycoon/).

### 10. Monetization UX: sell reduced friction at the moment of friction

The useful competitor pattern is **one premium product per friction**, surfaced where the friction occurs:

| Friction | Competitor pattern | WE Pass-2 action |
|---|---|---|
| Returning to base to collect | MT Auto Collect; War Tycoon Auto Collect can be toggled in settings | Keep AutoCollect as the first collector CTA; show an explicit on/off state and “collects PendingCash” copy. |
| Slow compounding | MT/War Tycoon 2x Cash; guides consistently position it above cash packs | Hero-sort DoubleCash above flat Cash/Gold packs; show a simple before/after rate, not a fake scarcity timer. |
| Identity/status | MT VIP combines cash, HP/tag, and sometimes vehicle/social perks | Keep a clearly explained WE-original VIP bundle: tag + modest survivability/cosmetic, not raw PvP dominance. |
| Waiting for a base category | Vehicle passes are presented as conditional (for example, “must have access to garage area first”) | Never let a vehicle SKU imply it bypasses `VehicleDepot`/prestige structure requirements. |
| Early income gap | War Tycoon’s low-price Speedy Oil Extractor is a small producer upgrade, not a full skip | If we add a producer SKU later, make it a visible extra worker/structure with a cap; do not bypass collector or tutorial. |

**UX rules for WAR EMPIRE:** pin AutoCollect, DoubleCash, and VIP in that order; explain the benefit in one line; show purchase only after the player has seen the underlying system once; preserve Id=0 safety; keep loot boxes off while `LootBoxPolicyPending`; and log impressions → opens → purchases → seven-day retention. A garage/vehicle pass should be a later conversion after the player has used a free Jeep and understands the category.

Sources: [MT VIP](https://military-tycoon.fandom.com/wiki/VIP), [MT VIP on Rolimon's](https://www.rolimons.com/gamepass/75751464), [MT gamepasses](https://military-tycoon.fandom.com/wiki/Gamepasses), [War Tycoon gamepasses](https://war-tycoon-roblox.fandom.com/wiki/Gamepasses), [War Tycoon Speedy Oil Extractor](https://www.roblox.com/game-pass/16699457/Speedy-Oil-Extractor).

### 11. Garage flow: what to copy as a UX shape, not as IP

A competitive happy path is:

1. **Enter a readable room/pad** that says category and ownership requirement.
2. **Open a selector** with Owned first, then Available/Locked; categories and rarity are filters, not separate hidden menus.
3. **Inspect a large preview** with name, role, speed/armor/seats, next requirement, and optional skin/cosmetic slot.
4. **Buy once, then spawn once:** after purchase the card becomes OWNED and SPAWN; do not require a second confirmation for a starter vehicle.
5. **Spawn inside a safe bay/marked pad, face the exit, and auto-seat the owner.** A visible Drive prompt is the fallback for mobile/late character replication.
6. **Exit through an obvious gate, despawn from the garage or HUD, and prevent a second active vehicle.**

WE already has the useful skeleton (`G`, `E`, owned filtering, BUY → SPAWN, auto-seat, one active model, `DriverSeat`). The Pass-2 gap is presentation and physics integrity: the garage needs a real “preview/requirement/room” story, and SPAWN must produce a car that moves, steers, and looks like one vehicle rather than a seat welded to a kit.

### 12. VehicleSeat vs mesh model — why Shaun’s Jeep is still broken

**Current WE diagnosis (documentation-only; do not edit the contested `VehicleService` branch here):**

- `VehicleService` creates one `Chassis` part, a `VehicleSeat`, and wheel Parts. `addWheels()` currently makes each wheel a cylinder and attaches it to the chassis with a `WeldConstraint`; the seat is also welded to the chassis.
- `VisualAssetService` treats a Creator Store model as a **non-colliding visual overlay**: it strips seats/scripts, makes descendants massless/non-colliding, and welds them to the authoritative chassis. That is a sensible render/physics separation, but it does not supply wheel motors, suspension, steering, or vehicle input handling.
- A `VehicleSeat` exposes `ThrottleFloat`/`SteerFloat` and can detect hinges; it is not a complete car chassis. With wheels rigidly welded to the same chassis, the wheels cannot rotate relative to it. Unless a separate propulsion controller moves the chassis, pressing W only changes seat input; it does not create wheel force. This explains the “spawn/seated but jeep does not drive” symptom.
- The catalog mesh may also have the wrong pivot, scale, forward axis, or seat alignment. Because the mesh overlay is welded to the chassis and all its collisions are disabled, it can look good while hiding a bad authoritative body—or look offset while the Part kit is physically correct.

**Public Roblox patterns for a working custom-mesh vehicle:**

- **Simple VehicleSeat + joints:** keep an unanchored chassis and seat as one assembly; use hinge/motor joints for powered wheels and a separate steering joint/axis for front wheels. VehicleSeat supplies input, but the joints/scripts apply torque.
- **Constraint chassis (recommended for the Jeep):** use invisible primitive wheel colliders (cylinders or spheres) for physics, with visible mesh wheels welded to those colliders. Give each wheel matching, centered attachments; use a `CylindricalConstraint` plus spring/suspension travel, or the equivalent prismatic + hinge arrangement. Rotate the front steering attachments smoothly; do not drive by directly teleporting the whole model each frame.
- **Mesh/body separation:** keep the attractive body MeshParts massless and `CanCollide=false`; use a simple box/hull chassis and primitive wheel colliders for reliable contact. Avoid precise mesh collision for fast wheels unless there is a specific gameplay need.
- **Ownership:** when `DriverSeat.Occupant` changes, assign network ownership of the unanchored vehicle assembly to the driver for responsiveness, restore automatic ownership when empty, and validate speed/position/teleport/contact-sensitive events on the server. All rigid parts must be unanchored and connected; an anchored part prevents ownership changes.
- **Tuning:** wheel radius/attachment centers, wheel density/friction, suspension stiffness/damping, chassis center of mass, and collision groups matter more than adding extra decorative mesh. Test straight-line acceleration, reverse, full-lock steering, bumps, spawn overlap, flip/recovery, and mobile controls before dressing the other 98 vehicles.

Public patterns: [VehicleSeat API](https://create.roblox.com/docs/reference/engine/classes/VehicleSeat), [Roblox network ownership](https://create.roblox.com/docs/physics/network-ownership), [Roblox assemblies](https://create.roblox.com/docs/physics/assemblies), [Roblox meshes/collision fidelity](https://create.roblox.com/docs/parts/meshes), [Constraint Chassis community resource](https://devforum.roblox.com/t/constraint-chassis/221717), [How to Rig a Car](https://devforum.roblox.com/t/how-to-rig-a-car/523855), and [2025 constraint vehicle tutorial](https://devforum.roblox.com/t/how-to-implement-vehicle-mechanics-using-constraints/3575431).

### 13. Pass-2 P1 backlog — priority order

These are **documentation priorities only**. Keep the jeep implementation and any contested `VehicleService` edits on the existing fix branch; this commit changes this document only.

| Priority | P1 item | Definition of done / reason |
|---|---|---|
| **P1-V1** | **Make MilitaryJeep a real test vehicle** | Replace welded wheel-only behavior with a minimal constraint/scripted chassis: four primitive colliders, centered attachments, powered rear/all wheels, front steering, brake/reverse, and mobile input. W/S/A/D or thumbstick must move the chassis on terrain; no need to generalize until this passes. Highest priority because every garage/monetization promise depends on it. |
| **P1-V2** | **Separate physics contract from render contract** | `Chassis` + `VehicleSeat` + colliders are authoritative; catalog body and wheel meshes are cosmetic, non-colliding, correctly pivoted, and visibly follow the colliders. Add a per-asset forward/seat/wheel alignment check. Part-kit fallback remains spawn-safe if asset load fails. |
| **P1-V3** | **Driver ownership and server validation** | On Occupant change, give the whole unanchored assembly to the driver and return to automatic ownership when empty. Validate max speed, excessive displacement, spawn bounds, and capture/damage events server-side. Verify with one driver plus one passenger; do not rely on client-owned `Touched` for rewards/damage. |
| **P1-V4** | **Garage showroom flow** | Turn `VehicleDepot`/garage into a readable room or console: preview, Owned/Available/Locked tabs, stats, requirement copy, BUY → SPAWN, auto-seat, Drive fallback, marked exit, DESPAWN, and one-active rule. This is the War Tycoon/MT parity beat that makes the catalog feel valuable. |
| **P1-V5** | **Garage/Jeep regression harness** | Add a Studio/manual checklist or automation assertion for: spawn clear of pad; seat occupant; forward/reverse; left/right steering; stop; despawn; respawn after cooldown; mesh-load failure fallback; no flip/jitter on a small ramp; mobile control. Keep logs keyed to `VehicleId` and drive mode. |
| **P1-V6** | **Monetization placement** | Hero-sort AutoCollect → DoubleCash → VIP; show the product after the player has collected/trained once; make AutoCollect state and PendingCash copy explicit; keep vehicle offers gated behind the free garage experience and structure requirements. Record funnel events before changing prices. |
| **P1-V7** | **Prestige rooms and late-game category unlocks** | Use a WE-original Vehicle Bay/Air Wing/Deep Command room unlock at selected prestige milestones. Put the next category, operations, and preview vehicles in the room; do not make prestige only a Level-100 multiplier reset. |
| **P1-V8** | **Catalog polish after physics** | Once V1–V5 pass, add mesh/PBR/LOD, animated wheels/rotors, lights, exhaust/wake, camera preview, and vehicle-specific silhouettes. Decorative mesh cannot be the acceptance criterion for “driveable.” |

**Recommended ship sequence:** V1 → V2 → V3 → V5 → V4 → V6 → V7 → V8. Do not spend time tuning late-game vehicle stats or adding paid vehicle SKUs while the starter Jeep fails the first 30-second drive test.

### Pass-2 top five recommendations

1. **Fix the Jeep physics contract first:** VehicleSeat input plus welded wheels is not a car; use primitive colliders and real wheel joints/forces.
2. **Keep mesh visuals non-colliding and separate:** chassis/colliders drive; meshes follow, with an asset alignment contract and safe Part-kit fallback.
3. **Make the garage a showroom and a safe spawn:** preview → requirement → buy → auto-seat → obvious exit, matching both MT’s Vehicle Manager and War Tycoon’s protected Vehicle Bay pattern.
4. **Make prestige unlock rooms and verbs:** use Vehicle Bay/Air Wing/Deep Command style milestones rather than only another multiplier or another hidden catalog row.
5. **Place monetization at experienced friction:** AutoCollect, DoubleCash, then original VIP; no vehicle bypasses the free garage/structure gate, and no loot-box dependency.

### Pass-2 source notes

- Competitor facts are public wiki/guide observations and can drift with live updates; prices and exact counts are not balance commitments.
- Roblox Creator documentation confirms `VehicleSeat` input properties, assembly/root behavior, network-ownership trade-offs, and mesh collision-fidelity costs.
- Community vehicle resources consistently separate visible mesh from primitive physics wheels and use centered attachments plus constraints/scripting for steering and drive force.
- No source authorizes copying competitor meshes, names, branding, or UI art. Inspiration remains systems-level only.
