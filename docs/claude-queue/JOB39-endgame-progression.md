# JOB 39: ENDGAME PROGRESSION ("always a next goal") + PLAZA INTERIORS WITH A PURPOSE

> **APPROVED by owner (Shaun) 2026-09-30.** The whole plan, with the §9 decisions recorded below. Build it exactly as
> written. §11 (EVERYTHING MUST VISIBLY AND MECHANICALLY WORK) is the bar for DONE. Written by Code Bot Roblox on 2026-09-30 from the configs at
> `phase-7-polish` a0921df (WE_Build 132/133). Analysis script: `tools/sim/endgame_curve_sim.py`
> (`python3 tools/sim/endgame_curve_sim.py` and `... --time`).

ORDER RULE (once approved): start only AFTER JOB 38 is finished and pushed. It needs JOB 38 (turret HP, SEND raids,
the Army Kills board) and JOB 35 (premium guns, for the mastery tree). One phase at a time (§10).

GIT/RULES: the same as JOB 35-38. git fetch; rebase claude/desktop-bud on the latest origin/phase-7-polish. Push only
claude/desktop-bud. Never bump WE_Build, publish, or push phase-7-polish/main. Never touch WE_Building*. PreferMesh OFF.
No fast travel (codebot_v127). No admin/owner combat immunity. Admin/owner accounts stay off every leaderboard. Ship
owner-first behind boolean flags (OwnerFirst = true + an Enabled kill switch; codebot_v101 bans "owner" strings in new
configs). OFF must equal today's game exactly. Every price lives in config. No new Robux SKU unless §9 is approved; any
Robux Id stays 0 until Shaun creates it. Phone first (44 px real taps, 14 px real text). Build guide:
docs/ROBLOX-BUILD-GUIDE.md §3 (interiors) and the §11 checklist. Real, detailed models from Parts (or already-cleared store
props); no real-world or franchise copies. Checks: tools/checks/claude_bud_job39.py + LUAU_COMPILE=$HOME/.local/bin/luau-compile
python3 tools/BuyPathStatic.py = 0 FAIL, rojo build ok.

---

## 0. WHY (the numbers today)

Owner: "I'm on my 2nd rebirth, fully maxed, earning ~$23,686/s (up to $28,493/s with a flag capture bonus) and holding
~170M. There's nothing big left to buy, so the fun is gone."

### 0.1 What one life costs and pays (from the configs)
| Piece | Cost | Kept through rebirth? | Income at max |
|---|---|---|---|
| 15 base structures x L5 (BaseConfig) | $11.16M | no (free rebirth) | payback curve (BalanceConfig.PaybackMinutes 2/3/6/12/25): ~$12,950/tick pre-mult |
| 4 war businesses x L5 (BusinessConfig) | $4.90M | no | 3,010/tick |
| **One life (base + businesses)** | **$16.07M, the same at every rebirth** | | **~$13.7k/s before multipliers** |
| 7 rebirth zones x L3 (RebirthZonesConfig) | $0.74M (R1) ... $11.7M (all 7, R8) | yes | +700 ... +3,050/tick |
| Research incl. Personal Armour (ResearchConfig) | $7.31M | yes | stats only |
| Cash vehicles (VehicleConfig CostCash) | ~$12.0M (R0-R1) ... ~$13.2M (R15) | yes | none |
| Cash guns (WeaponConfig) | $0.11M | yes | none |
| Soldiers ($500 each, cap 75 + 2/rebirth) | ~$0.04M | yes | 8/tick each |

The multipliers: x(1 + 0.10 x rebirths) x Empire Tax (home outpost +5 %, +10 % per outpost, cap +50 %) x passes (VIP
+25 %, 2x Cash) x events/codes. Pre-multiplier income barely moves with rebirths: $13.7k/s at R0 and $14.1k/s at R20. Only
the +10 %/rebirth grows it.

### 0.2 Curve per rebirth stage (model: greedy cheapest-first buying, passive + soldiers + oil; no combat, mission or stipend cash)
| Rebirths | Per-life cost | Everything once (zones, research, vehicles, guns, soldiers) | $/s at max, no passes | $/s, VIP + 2x Cash | Min to max the base, no passes | Min to max, VIP + 2x | Min to the rebirth level (rebirth_pacing_sim) |
|---|---|---|---|---|---|---|---|
| 0 | $16.07M | $19.4M | 14,407 | 36,007 | 43.3 | 17.5 | 33.6 (L40) |
| 1 | $16.07M | $20.2M | 16,013 | 40,021 | 34.4 | 13.9 | 34.1 (L44) |
| 2 | $16.07M | $20.6M | 17,472 | 43,668 | 28.8 | 11.7 | 37.4 (L48) |
| 3 | $16.07M | $22.0M | 19,013 | 47,522 | 27.5 | 11.1 | 41.5 (L52) |
| 5 | $16.07M | $25.4M | 22,064 | 55,149 | 23.3 | 9.4 | 52.9 (L60) |
| 8 | $16.07M | $29.7M | 26,645 | 66,601 | 19.4 | 7.8 | 77.2 (L72) |
| 10 | $16.07M | $31.1M | 29,618 | 74,033 | 15.8 | 6.4 | 97.6 (L80) |
| 20 | $16.07M | $32.4M | 44,524 | 111,298 | 10.5 | 4.3 | 126.8 (L90 cap) |

Shaun's 23,686 $/s at R2 is about 1.36x the no-pass model (17,472). That fits one or two of VIP, extra Empire Tax, a
territory PassiveCashMult or an event. The capture bonus (x1.20 to 28,493) fits two more outposts of Empire Tax.

### 0.3 Where the cash sinks run out
- **The most expensive thing you can buy for Cash is Rocket Assembly L5 at $2.4M.** At 23.7k/s that is **101 s (1.7 min)**.
  Next come: Nuclear Silo L3 $2.0M (1.4 min), Bunker Complex L3 $1.5M, Special Forces Facility L5 $1.2M, Personal Armour
  L5 $1.2M, Elite Barracks L3 $1.0M, Airfield L5 $0.9M, Fleet Carrier $0.72M.
- A whole new base costs $16.07M, which is **11.3 min** at 23.7k/s. Everything in the game at R2 (one base + every
  one-time item) is about $36.6M, or **25.8 min** of Shaun's income. **170M is 4.6 times the whole catalogue.**
- The last recurring sinks are tiny: Nuke Rush $4,000 per minute of charge (≤ $240k), $500 soldiers, 15-35k bank and
  15k plaza rewards (each worth about 1 second of endgame income).
- **Rebirth itself costs nothing** (PrestigeConfig.CashFee 0), and **Gold has no sink** (RebirthConfig J13 note).
- The rebirth unlock track ends at R20, the zones end at R8, and the soldier perk ends at R20. After R8 a rebirth adds
  only a vehicle and +10 %.

### 0.4 What the admin start distorts (AdminConfig)
- `AdminPlaytestCash = 50M` is a floor on **every join**: a rejoin with less cash tops you back up to 50M. Shaun can never
  be short of money, so "time to afford" means nothing on his account. His 170M is roughly 50M + income.
- `AdminPlaytestLevel = 100` on every join: after a rebirth resets you to Level 1, a rejoin puts you back at Level 100.
  So the level pacing (L40 + 4 per rebirth, the real gate for normal players) never applies to him.
- `AdminPlaytestAllVehicles` writes every vehicle into his profile and skips the spawn gates, so the vehicle goals are gone.
- Net effect: Shaun reached "nothing to buy" in minutes. A normal player gets there later, but still gets there (below).

### 0.5 A normal player (no admin, no passes, ~30 play-XP/min)
- Life 1 (R0): rebirth level at ~34 min, base maxed at ~43 min, so they rebirth before maxing. **Goals are fine.**
- Life 2-3 (R1-R2): the base is maxed at 29-34 min and the rebirth level comes at 34-37 min. The spare time goes into
  research, vehicles and zones.
- **The one-time catalogue (~$20M) is used up around R3-R4, about 2.5-3 h into play (about 1.5 h with VIP + 2x Cash).**
- After that, every life has dead time that grows: R4 ~23 min idle (~$28M with nothing to buy), R6 ~40 min idle (~$57M),
  R7 ~49 min idle (~$76M), R10 ~82 min idle. This is where it runs dry: the level gate keeps rising (L40 + 4/rebirth) while the base keeps
  getting faster (the multiplier grows and the price stays at $16.07M).

### 0.6 What the top military tycoons do (quick research, fan wikis, "requires confirmation" where they say so)
- **Military Tycoon** (fandom wiki, Rebirths / Nuke Base / Research Center pages): the cash bonus is +0.1x per rebirth, capped
  at 5x at R40. Rebirths are unlimited, but the base stops changing at R40. There is a second base (the Nuke Base) with
  its own rebirth track (15 rebirths to unlock). **Cash-crafted nukes are the big recurring sink: Rad-Rockets $500k,
  Tactical Nukes $5M, Mega Nukes $25M.** Nuke Scientists cost $125k each and give 5 % discounts. A Research Center pays
  a reward per rebirth up to 109 rebirths. Spec-Ops quests need up to R35-40 and can be skipped with Robux.
- **War Tycoon** (fandom wiki, Rebirthing / Base pages, figures marked "Requires Confirmation"): **a rebirth costs $500,000 in
  cash**, and the base cost rises with rebirths: ~$4.2M at R0, ~$9.1M at R2, ~$30.8M at R5, ~$68.7M from R8. The unlocks
  run to R69, and R100 is a title only. Bloxed.gg: a second currency (Medals, from spins and daily challenges) buys
  **weapon attachments and camo crates**, and weekly updates add vehicles.
- The takeaways we use: (1) the rebirth cost should grow; (2) there should be a big consumable super-weapon sink;
  (3) there should be a long permanent-upgrade track per rebirth or level; (4) attachments and camos should give the second
  currency a job; (5) Robux should skip time or sell cosmetics, never be the only road to the top. We copy no names or assets.

---

## 1. DESIGN GOAL
From R2 on, a player should always have (a) a next goal 5-60 minutes of their own income away, (b) a long goal (hours),
and (c) a reason to spend again after a fight. Every sink does something you can see or feel: a bigger base, a tougher
army, stronger turrets, a better gun. Nothing is a pure number unless it is labelled (Empire Level). All of it is **Cash**
(plus Gold for cosmetics). No Robux is needed, and no new Robux SKU is part of the core (§9).

The whole new catalogue is about $5.4B, roughly 60-65 h of Shaun's current income (less with passes). Its cost grows
faster than the income it adds, so it never "finishes" quickly. Every price stays below EconomyConfig.MaxCash (1e15 since Code Bot v194; was 1,000,000,000 — the $1B wallet cap bug).

---

## 2. THE SYSTEMS (exact numbers and formulas)

### 2.1 Rebirth: the base gets pricier, and rebirth unlocks go past R20
- `EndgameConfig.Rebirth.CostScalePerRebirth = 0.20`, `CostScaleMaxRebirths = 20`:
  price(structure or business, level) = Costs[level] x (1 + 0.20 x min(rebirths, 20)). **Income is unchanged.** Structure
  income stays on the UNSCALED cost (BalanceConfig.StructureIncomePerTick must read the raw Costs), and business
  IncomePerTick is unchanged.
  - One life: R2 $22.5M, R5 $32.1M, R10 $48.2M, R20+ $80.3M (War Tycoon's R8+ base is ~$68.7M).
  - The model gives these minutes to max (no passes): R1 41.3, R2 40.7, R3 44.1, R4 43.5, R5 46.7, R6 45.5, R7 46.8. That lines
    up with the rebirth level (34-68 min), so a life is a full run again instead of 20 minutes of idle waiting.
  - Applies to purchases made AFTER the flag is on. Levels already bought are never re-charged.
- No cash fee on rebirth (it would stack with the scale and feel like a tax). Keep CashFee = 0.
- New unlocks (PrestigeConfig.RebirthUnlocks rows, Kind "Flag"):
  R25 "Heavy Warhead" (§2.7), R30 "Mythic Training" (§2.4 tier 4), R35 "Bastion Crest" (a base banner cosmetic),
  R40 "Legend Parade" (the base parade ground gets a marching honour guard of 6 idle soldiers, client-only, Parts),
  R50 = the existing Supreme Commander title + statue. MaxPrestige stays 50.

### 2.2 EMPIRE LEVEL (the long track; the Command Office in the plaza, §3)
- Levels 1..30, bought in order, kept through both rebirth paths.
- Cost(L) = round(5,000,000 x 1.17^(L-1), to 100k): L1 5.0M, L2 5.8M, L3 6.8M, L4 8.0M, L5 9.4M, L6 11.0M, L8 15.0M,
  L10 20.5M, L12 28.1M, L15 45.0M, L20 98.7M, L25 216.5M, L30 474.6M. All 30 = $3.24B.
- Reward: +2 % cash per level on non-exempt reasons (its own factor in EconomyService.cashMultFor, multiplied with the
  stack), so L30 = x1.60. A cosmetic milestone every 5 levels: L5 a gold star on the base sign, L10 a gate banner,
  L15 an HQ roof flag, L20 a nameplate chevron, L25 a gold flag finial, L30 an "Empire Marshal" title suffix.
- At 23.7k/s: L1 3.5 min, L10 12 min, L15 25 min, L20 50 min, L25 1.7 h. All 30 take ~26 h of income, with its own bonus
  counted. Shaun's 170M buys L1-L12 (164M) at once, and then every level is a real goal. A normal R2 player (17.5k/s)
  reaches L10 in ~1.6 h and L20 in ~8 h.
- Shown as "EMPIRE 12" next to the rebirth rank on the base sign and the rebirth screen. It never goes on a leaderboard
  (no new board). If it ever does, admin accounts stay excluded.

### 2.3 BASE TIER (the base visibly grows; the Command Center "HQ UPGRADE" console at the player's own base)
| Tier | Name | Cost | Needs | Look (Parts, PreferMesh OFF, own design) | Effect |
|---|---|---|---|---|---|
| 1 | Fort | 10M | R2, CC L5 | HQ +1 storey with a window band, gate towers get roofs | gate HP +10 %, soldier cap +5 |
| 2 | Citadel | 25M | R3 | a comms mast with a dish on the HQ, a sandbagged roof deck | +1 AutoGun nest at the gate, gate HP +10 % |
| 3 | Stronghold | 60M | R5 | corner bastions on the wall ring (a concrete skirt + parapet) | wall/gate rebuild -10 s, soldier cap +5 |
| 4 | Bastion | 150M | R8 | a floodlit flag tower beside the HQ (1 light, no shadows) | +1 AutoGun nest, gate HP +10 % |
| 5 | Capital | 400M | R12 | a parade ground with a bronze commander statue and flag row | soldier cap +10, the "Capital" trim on the banners |
- Kept through rebirth. Time at 23.7k/s: 7 / 18 / 42 / 106 / 282 min.
- Budget: ≤ 120 parts and ≤ 2 lights per tier. A Capital base must still pass the 2,700 parts cap and the 40 lights per
  base cap. Measure with the existing per-base part counter and put the numbers in the DONE reply. If a tier would go over,
  swap in lighter pieces; never raise the cap.

### 2.4 ELITE TRAINING per soldier type (the Recruitment Office in the plaza)
- Types: the army's unit kinds (SoldierConfig.Visual.VisualKindByRole: Infantry, Heavy, SpecialForces). **Read ArmyConfig
  first.** If today's army is one kind only, add a split (every 5th soldier Heavy; every 10th Special Forces once the
  Special Forces Facility is L3+). Heavy: +20 % HP, -10 % speed. SF: +10 % damage. Keep MarchSpeed so the block stays coherent.
- Tiers per type, in order: Veteran 2M, Elite 8M, Legendary 30M, Mythic 100M (Mythic needs R30). 3 types x 140M = 420M.
- Effect: +8 % HP and +8 % damage per tier for that type (Mythic +32 %). This multiplies with Research Soldiers
  (BodyArmor / MarksmanTraining) but the total is clamped by ResearchConfig.MaxMult 3, and PlayerMaxDps still caps
  damage to players.
- Look: a helmet band per tier (grey, green, gold, black-gold). Simple welded parts, no store assets.
- **Recurring sink:** refilling a dead trained soldier costs $500 + a re-train fee (Veteran 5k, Elite 15k, Legendary 40k,
  Mythic 100k). A 79-man Mythic army wiped in a raid costs $7.9M to refill (5.5 min at 23.7k/s). The existing 49 R$ Instant
  Army Refill also pays the re-train fees (APPROVED, §9 b; same product, same price, same Id).
- Size and look (§11.3): the rig scale per tier is Veteran 1.05, Elite 1.10, Legendary 1.18, Mythic 1.28. It uses the
  soldier's HIGHEST tier (its type's tier). Rank insignia + colour trim per tier, and a light Mythic aura.
- This feeds JOB 38: army power (the SEND fairness ratio) and the Army Kills board both rise with training.

### 2.5 DEFENCE TREE (matters once JOB 38 raids ship; the Engineering Bureau in the plaza)
- 4 tracks x 10 levels. Cost(L) = round(1,000,000 x 1.6^(L-1), to 100k): 1.0, 1.6, 2.6, 4.1, 6.6, 10.5, 16.8, 26.8, 42.9,
  68.7M (181.6M per track, 726M all). Levels 5-6 need Base Tier 1, 7-8 Tier 2, 9 Tier 3, 10 Tier 4.
  - **Turret Plating:** AutoGun HP +15 %/level on top of JOB 38 GateDefenseConfig.AutoGunHealthByLevel.
  - **Turret Guns:** turret damage +6 %/level, stacked with Research TargetingSystems (total ≤ MaxMult 3).
  - **Gate & Walls:** gate HP +12 %/level. Rebuild time -3 s/level (GateRebuildSeconds 50 -> 20 at L10).
  - **Vault Plating:** army raid loot 5 % x (1 - 0.05 x L), so L10 = 2.5 %. The player ATM raid is 10 % x (1 - 0.03 x L),
    so L10 = 7 %. **APPROVED by Shaun 2026-09-30 (§9 f):** it overrides the JOB 38 5 % / 10 % at the Vault levels bought
    (L0 = exactly the JOB 38 numbers). Behind EndgameConfig.Parts.Defence like the other tracks.
- **After-raid sink:** a destroyed gate or turret rebuilds free after the timer, or at once for Cash = 30 s of the
  defender's passive income (min 25k) from the base Defences console. Army refill (§2.4). All raid rules stay as JOB 38
  decided them: online only, 5 %, 10-min protection, 5-min SEND cooldown, power checks.

### 2.6 VEHICLE WORKSHOP (at the player's own Vehicle Depot; vehicles do not fit in a plaza house)
- 3 classes (Ground / Air / Naval) x 5 levels. Cost(L) = 1M x 2.2^(L-1): 1.0, 2.2, 4.8, 10.6, 23.4M (42.1M per class,
  126M all).
- Per level: +6 % HP and armour, +3 % speed (L5 +30 % / +15 %). This stacks with Research EngineTuning / CompositeArmor under
  MaxMult 3. It applies to cash, granted AND premium vehicles, so the Robux vehicles keep their lead (VehicleConfig.Premium
  multipliers are unchanged).
- Look: L3 adds bolt-on armour plates (2-4 parts per kit family), L5 a gold nameplate trim.

### 2.7 SUPER-WEAPONS (the Nuclear Silo; consumable, the recurring sink)
- Tactical Warhead, $5M, R2+: fills one silo slot at once (skips the charge). The player cooldown (1800 s) and the server
  cooldown (300 s) stay, so at most 2 per hour (≤ $10M/h).
- Heavy Warhead, $25M, R25+: x1.3 radius and x1.2 damage. Holds 1. Same cooldowns. Still never within BaseClearStuds 360 of
  a base, and still under the one CombatService.ApplyRadiusDamage rule.
- Nuke Rush stays at $4,000/min.

### 2.8 HOSPITAL (the Town Hospital)
- FREE heal to full at the reception desk (not in RecentCombat; 60 s cooldown).
- Med Kit: carry up to 3, heals 50 HP over 3 s (hold to use, a phone button). Price max($25,000, 30 s of your passive income).
- Combat Medicine tree, 5 levels, +10 max HP each (100 -> 150): 2M, 5M, 12M, 30M, 75M (124M).
  Order: (100 + Medicine) x DoubleHP pass (JOB 36) -> then the Armour bonus. Hard cap 400 effective HP.
- Field Surgeon: one revive token (carry 1). Get up where you fell within 10 s with 50 % HP. It is not travel: no position
  change. Price max($250k, 3 min of income). Not usable inside an enemy base during a JOB 38 siege.
- Army medic: out-of-combat soldiers regenerate 1 HP/s once the Medicine tree is L3+.

### 2.9 WEAPON MASTERY + ATTACHMENTS (the Armory Workshop in the plaza)
- Per gun, 5 levels: +3 % damage, +2 % fire rate, +4 % range, +6 % magazine, -5 % reload per level (all read by the
  server's shot validation, not only the client). Cost = TierBase x 2^(L-1). TierBase: shop guns 1M,
  rebirth guns 2M, JOB 35 premium guns 3M (a cash path that makes Robux guns better too). Examples: a rebirth gun L1-L5
  costs 2+4+8+16+32 = $62M. Clamped by MaxMult 3 and PlayerMaxDps. The PvP rules are unchanged.
- Attachments (one-time per gun, one per slot): Red-dot 1M (+10 % range), Grip 1.5M (-15 % spread), Extended Mag 2M (+25 %),
  Suppressor 3M (no minimap ping when firing). Our own generic names, no brand names.
- Camos (cosmetic, **the first Gold sink**): 50-250 Gold each (Olive 50, Urban 100, Tiger 150, Gold 250). Rotating ones
  go in the Black Market (§2.10).

### 2.10 LIMITED-TIME / ROTATING: the weekly Black Market (the market building, upper floor)
- Rotates every Monday 00:00 UTC (01:00 Irish time in summer). Pure function of the week number + a config pool, so
  every server shows the same stock.
- 3 Cash slots priced max(floor, N minutes of YOUR passive income), N = 20 / 45 / 90, floors 1M / 3M / 8M. There is also
  1 Gold slot (100-250 Gold).
- Cosmetic only: vehicle paints, base banner patterns, soldier beret colours, gun camos, one base trophy prop (Part-built,
  ≤ 30 parts). **Never power.** The stock and "back in N weeks" show in the panel. One of each per player.
- **No Robux item in the Black Market** (owner decision 2026-09-30). Cash and Gold only.

### 2.11 INTEL + CONTRACTS (the Intel Office in the plaza)
- 3 daily contracts from a pool (clear 2 site garrisons, capture 2 outposts, kill 10 checkpoint guards, defend a raid,
  win a SEND raid, launch a warhead). Reward each = max($50k, 8 min of your passive income). A weekly High-Value Target
  contract pays 20 min of income + 50 Gold.
- Scouting report before a SEND: $ = 1 min of your income. It shows the target's turret count and HP, guards, Defence
  levels and the fairness verdict (the JOB 38 rule, read-only). It never reveals offline players (they cannot be raided).
- "Raided by" list (last 5), for a revenge SEND under the normal cooldowns.

### 2.12 BANK HEIST TIERS (the existing Empire Bank walk-in hall)
- Today: $15-35k, which is about 1 s of endgame income. Keep that as Vault 1.
- Heist kits, bought once at the bank's side desk: Drill 2M -> Vault 2 (payout max(35k, 4 min of the raider's income),
  +3 guards, 8 s hold). Thermal Lance 8M -> Vault 3 (8 min, +5 guards, 10 s hold). Vault Cracker 25M -> Deep Vault
  (15 min, +7 guards, 14 s hold, 30-min cooldown). The guards are the existing BankGuard NPC path (LOS, hit chance).
- Also scale the plaza bounty (PlazaBountyConfig.Cash 15k -> max(15k, 3 min of income)).

---

## 3. PLAZA INTERIORS: what each building becomes
What exists (read in code):
- JOB 32 made **4 enterable PlazaHouses** (PlazaBuildingsConfig.Rows, built by WorldKits Builders.PlazaHouse; 17.6 x 17.4
  studs, 11 high, 2 floors + roof). The facade styles are **NE_E1 "cafe"** (teal awning), **SW_S1 "market"** (navy),
  **NE_N1 "hotel"** (red) and **NW_W1 "radio shop"** (orange). Inside today there are only a stair, a hatch, a few crates.
- The Town also has 2 enterable store props (StorePropsConfig WorldRows at area:Town): the **Hospital Building**
  (5201630514, 406 parts, x0.9) and the **Office Building** (12423243620, 1,066 parts).
- The **Empire Bank** walk-in hall (BankRaidConfig, BankPlaza, 220, -220).
- **There is no hospital among the JOB 32 houses.** The hospital is the Town store model. Before placing stations in it,
  check in Studio that its ground floor is walkable. If it is not, put the reception desk in the doorway / forecourt.

| Building | Becomes | NPC / station (ProximityPrompt, HoldDuration 0, 12-stud range) | Sells / does |
|---|---|---|---|
| NE_N1 (hotel) | **Command Office** | "Chief of Staff" at a map table on the ground floor; a wall board of your Empire progress upstairs | Empire Level §2.2, rebirth goals preview (read-only) |
| NE_E1 (cafe) | **Recruitment Office** | "Drill Sergeant" at a counter with lockers and a flag stand | Elite Training §2.4 |
| SW_S1 (market) | **Armory Workshop** (ground) + **Black Market** (upstairs) | "Gunsmith" at a bench with a gun rack; a "Trader" upstairs behind a crate counter | Mastery / attachments / camos §2.9; weekly stock §2.10 |
| NW_W1 (radio shop) | **Intel Office** | "Signals Officer" at a radio desk with a map wall | Contracts, HVT, scouting §2.11 |
| Hospital (store model) | **Field Hospital** | "Field Medic" at reception, 2 beds | Heal, Med Kits, revive, Medicine tree §2.8 |
| Office Building (store model) | **Engineering Bureau** | "Engineer" at a drafting table | Defence tree §2.5 |
| Empire Bank hall | **Bank + heist desk** | "Fixer" at a side desk | Heist kits §2.12 |
| Own base CC / Vehicle Depot | HQ UPGRADE / WORKSHOP consoles | the existing console style | Base Tier §2.3, Vehicle Workshop §2.6, instant rebuild §2.5 |

Interior build rules (ROBLOX-BUILD-GUIDE §3):
- Per house ≤ 40 extra parts (a desk, a chair, one hero prop, a wall board, a rug/floor inlay, a ceiling fixture).
- 1 PointLight per house (Shadows = false, Range ≤ 16).
- The floor and ceiling differ from the walls. Small furniture has CanCollide/CanQuery/CanTouch false. Walls and cover stay
  queryable. The Model is Atomic streaming.
- 4 houses x 40 = 160 parts, taken from PlazaBuildingsConfig.MaxExtraParts headroom (640; measure what is used first). If there is not
  enough room, raise that allowance only inside the world budget (3,100 hard cap) and report the count.
- NPCs are static R15 figures (no Humanoid AI, the Training Yard figure style: Parts). They are **not** damageable.
- The plaza stays contested PvP. Opening a shop panel needs "not in RecentCombat", and taking damage closes the panel.
- Each house gets a door sign board (Part + one SurfaceGui, MaxDistance ≤ 40): "COMMAND", "RECRUITS", "ARMORY",
  "INTEL", "HOSPITAL", "ENGINEERS", "BANK". It counts against the SurfaceGui budget.
- Travel: the plaza is central (bases at ~800-1,500 studs). You go by vehicle; no fast travel. The base EMPIRE panel
  shows your next goal for each station with a **tap-to-pin** waypoint to it (the existing ObjectiveMarker; the pointer
  rule: nearest valid target). The panel is read-only, and buying happens at the station, which gives the plaza a purpose.

---

## 4. CONFIGS TO ADD
- `Shared/Configs/EndgameConfig.luau`: Enabled = true, OwnerFirst = true, a Parts switch per system (Rebirth,
  EmpireLevel, BaseTier, Elite, Defence, Workshop, Warheads, Hospital, Mastery, BlackMarket, Contracts, Heist,
  RewardScaling), and every number in §2 (tables and formula constants, not code). Pure helpers: EmpireCost(L),
  EmpireMult(L), DefenceCost(L), WorkshopCost(L), MasteryCost(tierBase, L), IncomeMinutesPrice(floor, minutes, perSec),
  RebirthCostScale(p), BlackMarketStock(weekIndex).
- `Shared/Configs/PlazaServicesConfig.luau`: the station per building (row id / store prop id -> station kind, NPC
  offset, prompt text, sign text, the interior prop list and part counts).
- Additive edits only: PrestigeConfig.RebirthUnlocks (the R25-R40 rows), MonetizationConfig (nothing unless §9 is approved),
  RaidConfig / GateDefenseConfig (read the Defence multipliers through helpers; the defaults are unchanged).

## 5. DATA (profile, sanitised on load, all kept through both rebirth paths)
`profile.Endgame = { EmpireLevel = 0, BaseTier = 0, Elite = { Infantry = 0, Heavy = 0, SpecialForces = 0 },
Defence = { Plating = 0, Guns = 0, Gate = 0, Vault = 0 }, Workshop = { Ground = 0, Air = 0, Naval = 0 },
Mastery = { [weaponId] = 0..5 }, Attachments = { [weaponId] = { [slot] = true } }, Camos = { [id] = true },
Medicine = 0, MedKits = 0, Revive = 0, Warheads = { Tactical = 0, Heavy = 0 }, HeistKit = 0,
Contracts = { Day = n, Rows = {...}, WeekHVT = {...} }, BlackMarket = { Week = n, Bought = { [id] = true } } }`.
- All purchases go through one server path (EndgameService.Purchase(player, kind, id)): validate the flag, the
  requirement, the price from config and the cash, then SpendCash with reason "endgame_<kind>", save, and push the state.
  RemoteGate schema + rate limit. The client sends only the kind and id. PrestigeConfig.RebirthSummary KEEP gains
  "Empire and upgrades".
- Analytics: every spend goes through the existing analyticsEconomy sink with its reason (so we can see which sink players use).

## 6. UI (phone first)
- A station panel (one shared layout): title, current level, next-level card (cost, the effect as "+2% cash", ETA as
  "ready in 12:05" from WE_IncomePerSec via TycoonMath.FormatEta), a BUY button ≥ 64 code px, and a small "max" state.
  One panel per station, opened by the prompt, closed by damage.
- Base EMPIRE panel (from the Army / Base menu): 7 rows, each with "next goal + price + ETA", a PIN button, and the Empire
  Level ring.
- The rebirth screen shows the next scaled base price ("Next base: $22.5M").
- Check it at 844x390, 956x440, 800x360, 1180x820, 1280x720 and 1920x1080 (check_hud.py with data).

## 7. TESTS
- `tools/sim/endgame_curve_sim.py` (this draft) + a new `tools/sim/run_endgame_test.py`. It asserts:
  - every price is < MaxCash;
  - EmpireCost is strictly rising and EmpireMult(30) = 1.60;
  - at 23.7k/s every next goal is 3-300 min away from R2 onward;
  - with CostScale 0.20 the minutes to max (no passes) for R1-R7 fall within ±25 % of the rebirth-level minutes;
  - the effective-HP cap is 400;
  - every stat stays ≤ MaxMult 3;
  - the loot floor is 2.5 %.
- `tools/checks/claude_bud_job39.py` pins:
  - the flags, and OFF = old (no Endgame reads when Enabled = false);
  - the one purchase path, with no client-sent price;
  - RemoteGate schemas;
  - no FastTravel / PivotTo in new code;
  - no Robux path to Empire Level;
  - no Humanoid.Health writes except the Hospital heal (server, with the combat check);
  - admin excluded from any board;
  - no WE_Building* edits; PreferMesh untouched;
  - the plaza interior part counts.
- Studio (Local Server, 2 clients): buy each station's first level, rebirth (both paths) and confirm everything is kept,
  run a SEND raid against Defence L3 and confirm the loot and turret HP, refill a trained army, run a Heist Vault 2.

## 8. ACCEPTANCE
- A: On R2 with 170M (owner account), Empire Level buys L1-L12, and L13 shows "ready in ~20 min".
- B: A fresh R0 test account never sees the new stations' buy buttons until they are live (OFF == old).
- C: Base Tier 1-5 visibly change the base from 100+ studs away, and the parts/lights counts stay under the caps
  (numbers in DONE).
- D: A raid against a Defence-upgraded base: the turrets take longer to kill, a Vault-plated ATM loses less (only if §9 f
  is approved), and the instant rebuild charges 30 s of income.
- E: Every plaza building has an NPC, a sign, a light and a working panel, and the panel closes on damage.
- F: Black Market stock matches across 2 servers in the same week and changes on Monday 00:00 UTC.
- G: Rebirth cost scale: R3 base price = 1.6x the L-table, and income per tick is unchanged vs today for the same levels.
- H: every §11 proof item for the phase is done and listed (logs + screenshots). Without it the phase is NOT DONE.
- DONE reply: what Shaun tests ON HIS PHONE (the station prompt + panel at 800x360, the BUY/ETA text, PIN to a station,
  the Med Kit button, the Base Tier look).

## 9. ROBUX: OWNER DECISIONS (Shaun, 2026-09-30; all APPROVED as listed)
- a) **No new Robux SKU.** Empire Level, Base Tier, Elite, Defence, Workshop, Mastery, Medicine, Warheads and Heist kits are
  Cash (or Gold for camos) and are **never sold for Robux**. No MonetizationConfig price or Id changes in this job.
- b) **Instant Army Refill (49 R$, existing product) also pays the elite re-train fees** (§2.4). The price and Id are unchanged.
  The ProcessReceipt grant refills the soldiers at their trained tiers with no fee (save before PurchaseGranted).
- c) **Keep-Base Rebirth stays 50 R$**, even though it now saves $22-80M per rebirth under the cost scale.
- d) **Cash Packs (JOB 36, income-scaled) may be spent on Empire Level.** It is ordinary cash, with no special block.
- e) **No weekly Black Market Robux item.** It is dropped.
- f) **Vault Plating is APPROVED:** army raid loot goes from 5 % down to a 2.5 % floor at L10, and the ATM raid from 10 % down to 7 % at L10 (§2.5).

## 10. PHASES (one at a time, each flag-gated and shippable alone)
1. The Rebirth cost scale + Empire Level + the Command Office (the fastest fix for "nothing to buy").
2. Base Tier + the Defence tree + the Engineering Bureau + instant rebuild (after JOB 38).
3. Elite Training + the Recruitment Office + refill fees.
4. The Hospital + the Armory Workshop (Mastery, attachments, camos) + the Vehicle Workshop.
5. Warheads, Heist tiers, Intel contracts, Black Market, reward scaling.

## 11. EVERYTHING MUST VISIBLY AND MECHANICALLY WORK (hard rule, owner 2026-09-30)
A phase is DONE only when every item below that it touches is PROVEN, not when the code runs. Proof = the logged numbers,
plus screenshots or Studio captures listed in the DONE reply (file paths committed under docs/proof/job39/). A missing
proof means NOT DONE. Say so in LATEST-HANDOFF and stop; do not mark it done.

1. **Base Tiers visibly grow the base (Fort -> Capital).**
   - Each tier adds real, detailed builds in the world, following docs/ROBLOX-BUILD-GUIDE.md (§2 silhouette / layered parts /
     bevels / material variation, §11 checklist):
     - bigger or extra walls (thicker wall ring, parapets, corner bastions);
     - taller or extra towers;
     - a heavier gate (a frame, a lintel, a gatehouse at T3+);
     - extra and heavier turrets (T2 and T4 nests with sandbag rings and ammo boxes);
     - flags (more, and taller, masts per tier).
   - **No block models:** no single-box "tower" or "wall"; every piece is layered.
   - Proof: one screenshot per tier (T0 to T5) from the same camera spot 100+ studs out, and one close-up per tier. The
     per-base part and light counts are logged per tier and stay under the 2,700 parts and 40 lights caps.
2. **Elite training really changes soldiers on the server.**
   - Veteran / Elite / Legendary / Mythic raise the soldier Humanoid MaxHealth (and Health on spawn/refill) and the soldier
     damage on the server, through the shared hostility rule (CombatService.UnitMayHitPlayer / UnitMayHitNPC) and the
     existing damage path (the attackAimOnly shots, the research multipliers, the MaxMult 3 clamp, PlayerMaxDps).
   - There is no second damage path and no client-set stat.
   - Proof: a 2-player Studio test (Local Server, 2 clients). Log `[EliteTest] tier=<t> maxHP=<n> dmg=<n> TTK_vs_player=<s>
     TTK_vs_unit=<s>` for untrained vs each tier: the same target, the same range, averaged over ≥ 5 kills. The TTK must drop
     with every tier.
3. **Trained soldiers are visibly bigger, with a tier look, and still animated.**
   - The rig scale per tier is Veteran 1.05, Elite 1.10, Legendary 1.18, Mythic 1.28, done properly: Model:ScaleTo on the
     soldier model or HumanoidDescription body scales, with the hip height and animations still correct. A Mythic soldier is
     visibly bigger than a regular army soldier.
   - Tier look:
     - rank insignia (a shoulder or helmet plate: 1 / 2 / 3 chevrons, then a star for Mythic);
     - colour trim (grey, green, gold, black-gold);
     - a Mythic aura: one light ParticleEmitter (Rate ≤ 4, LightEmission ≤ 0.3, no lights, off at Graphics Quality ≤ 3, capped
       by the existing particle budget).
   - The rigs keep walking and shooting animations, and FOLLOW / HOLD / ATTACK / SEND formations still work. **Formation
     spacing scales with the soldier size** (slot spacing x the largest scale in the block). There is no teleport, PivotTo
     or snap; the existing formation standard applies (JOB 38).
   - Proof: a screenshot of a mixed block (regular / Veteran / Mythic) standing and walking, plus a short capture or
     /armydebug `[ArmyMarch]` log showing PivotTo=0 while the scaled block turns.
4. **Gun upgrades and attachments change the real server numbers.**
   - Mastery levels and attachments change the SERVER damage, fire rate, range, magazine and reload that the shot
     validation uses.
   - Proof: log `[GunTest] weapon=<id> mastery=<L> att=<list> dmg=<n> rps=<n> range=<n> mag=<n> reload=<s>` for L0 and L5
     (+ each attachment), plus a range test that a shot past the old range fails at L0 and hits at L5 + Red-dot.
   - Camos are visibly applied to the equipped gun model (first person and third person): one screenshot per camo.
5. **Defence upgrades change turrets, gates and loot.**
   - Turret Plating raises the AutoGun HP, Turret Guns raise the turret damage, and Gate & Walls raise the gate HP and
     shorten its rebuild.
   - Vault Plating lowers the loot:
     - army raid 5 % -> 2.5 % at L10;
     - ATM raid 10 % -> 7 % at L10.
   - Proof: logs `[DefTest] plating=<L> autogunHP=<n> guns=<L> turretDmg=<n> gate=<L> gateHP=<n> rebuild=<s>` at L0 and L10.
     Also 2-player raid tests (a SEND raid and an ATM raid) at Vault L0, L5 and L10 with the loot logged:
     `[LootTest] vault=<L> pending=<n> looted=<n> pct=<x>`.
6. **Empire Level raises income, and every plaza station works.**
   - Proof: WE_IncomePerSec before and after buying Empire L1, L5 and L10 (the $/s change logged and shown on the HUD
     screenshot: +2 % per level).
   - Each plaza building has a working NPC / station:
     - Command Office;
     - Recruitment Office;
     - Armory Workshop + Black Market;
     - Intel Office;
     - Field Hospital;
     - Engineering Bureau;
     - Bank heist desk.
   - For each one the proof is a screenshot inside the building showing the NPC, the prompt, the open panel on a phone
     viewport (800x360), and one completed purchase or action logged (`[Station] <kind> <action> ok`).

## 12. SOURCES (research for §0.6; fan wikis, figures unverified where marked)
- Military Tycoon wiki: https://military-tycoon.fandom.com/wiki/Rebirths ,
  https://military-tycoon.fandom.com/wiki/Nuke_Base , https://military-tycoon.fandom.com/wiki/Research_Center ,
  https://military-tycoon.fandom.com/wiki/Spec-Ops_Quests
- War Tycoon wiki: https://war-tycoon-roblox.fandom.com/wiki/Rebirthing , https://war-tycoon-roblox.fandom.com/wiki/Base
  (base cost figures marked "Requires Confirmation" on the wiki)
- Bloxed.gg War Tycoon overview (Medals for attachments / camos): https://bloxed.gg/games/war-tycoon
