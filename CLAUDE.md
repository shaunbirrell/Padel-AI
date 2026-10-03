# WAR EMPIRE — rules for anyone working in this repo

## QUEUED JOBS (Code Bot, 2026-09-30)
- **ADMIN ABUSE PROMO IS HIDDEN UNTIL SUN 4 OCT 21:00 DUBLIN (Shaun 2026-10-02 16:13: "dont promote a pop up banner or anything for the admin abuse event until this event finishes on sunday night"; shipped by Code Bot v234).** `AdminAbuseConfig.PromoStartsAtUtc = 1791144000` (2026-10-04T20:00:00Z, the end of the DOUBLE WEEKEND) hides ALL public Admin Abuse promo (chip under TARGETS, details card, RSVP pop-up, LIVE chip) for everyone before then; it appears on its own afterwards with no publish. `DoubleWeekendController.promoHidden` skips `popupTick` while hidden (the pop-up is never marked seen early) and `DoubleEvent` ignores `RequestEventPopupSeen` for it too. **Do NOT lower / remove `PromoStartsAtUtc`, bypass `promoHidden`, or add any other Admin Abuse banner / pop-up / announcement / notification before that time** (JOB 72 extras included: any new player-facing promo must respect `AdminAbuseConfig.PromoOpen(now)`). The owner panel (AdminConfig-gated) is unaffected. Do not touch the DOUBLE WEEKEND (`EventConfig`). Check: `tools/checks/codebot_v234.py`.
- **JOB 74 — Central Plaza defenders + Plaza tax (Shaun approved 2 Oct 16:29/16:31 Dublin).**
  - **Problem:** once Plaza neutral guards are killed they don't respawn, so a captured Plaza is easy to retake. **FIRST prove root cause from code** (Plaza capture service, guard spawn/respawn, JOB 51 shared hostility, PlazaBountyConfig, Plaza Airstrike instant takeover v221).
  - **A) DEFENDERS:** when a player captures the Plaza, their own defenders deploy: soldiers mirroring their army tier, plus tanks/armoured vehicles if unlocked. Count and strength scale with owner level/upgrades/rebirth from one central config (`PlazaDefenderConfig`); high-level owners harder to beat. Mobile caps: max ~6 soldiers + 1-2 vehicles, reuse existing AI, no new Heartbeat loops. Hostile to everyone except owner and allies (shared hostility rule), respect PvP-off/novice rules. Billboard `Defended by [name] - Lv X`. Plaza lost or owner leaves -> defenders despawn; unheld -> neutral guards respawn after a few minutes (config). Works with Plaza Airstrike takeover. Toast to capturer `Your troops are defending the Plaza`.
  - **B) PLAZA TAX (real tax):** while held, 10% of every other player's passive income on the server goes to the holder (config value). Skip novice-protected players, the holder's allies, PvP-off players. Never tax dev-product cash, offline/away earnings, or the holder. One server-side point in the `EconomyService` income tick, no new loop. UI: taxed players see a clean chip `TAXED 10% BY [name] - take the Plaza!`; holder sees `PLAZA TAX +$X/s`. No overlap with TARGETS / 2x Weekend / Admin Abuse chips.
  - **Rules:** `OwnerFirst=true` (`AdminConfig.IsPlaytestOwner` + `Laumartinez26` `11718087109`; tax only runs when holder is a tester), 2-player test, `tools/checks/claude_bud_job74.py` with exact fail list, `LATEST-HANDOFF.md` update, `StreamingEnabled`/`PreferMesh` OFF, never touch `WE_Building*`, no price changes, real detailed models only.
- **JOB 73 — MAP REDESIGN WITH INTENT — ON HOLD - DO NOT START. Shaun wants a bigger master plan first; wait for Code Bot to replace this job. (Shaun 2026-10-02 16:11 Dublin: "a big improvement of design, features etc, everything needs to be done with intent"; queued by Code Bot, docs only). Full audit, research and plan: [`docs/claude-queue/JOB73-map-redesign.md`](docs/claude-queue/JOB73-map-redesign.md). JOB 72 is reserved for the Admin Abuse panel extras Shaun may paste himself; do not reuse 72.**
  - **Goal:** every area has a purpose (why go, what you do, reward), one nameable landmark, and a route; PvP hotspots that pull the 10 bases into fights; no dead scenery. Plots stay exactly where they are.
  - **Phase A (biggest visual + intent wins):** one central `MapPurposeConfig` row per area (Purpose/Do/Reward/Landmark/Routes/HowTo, read by the world map card); tall real-model landmarks visible from every base + junction signposts with distance; Terrain relief (real Radar Hill, Sniper Ridge, a wadi vehicle loop, rock spines to break open sightlines; 0 parts, plot pads/roads flat); Central Plaza Command HQ capture with 3+ entrances + roof route, Bank tied into Bank Street; merge/rename duplicate places (5 camps, 2 villages, 2 depots, the "Ridge" names); swap the Part-built WorldDetail kits for owned real models with Box hulls; fixed named Drop Zones between neighbouring bases instead of random airdrop/crate spots (same caps and cash); a light `AreaDwell` analytics event.
  - **Phase B (PvP + routes):** a Forward Outpost between each pair of neighbouring bases (reuse the JOB 31 sites), deliberate chokepoints with a second route each, road hierarchy (ring highway + spokes, dirt tracks, foot paths), air routes (Airstrip + fort/port helipads, AA at forts), naval routes with boat-only rewards, and carry-home oil convoys that show on the map (EconomyService, no new multipliers).
  - **Phase C (reasons to travel far):** star-tiered threat areas (forts, Quarry, Crash Site) with one light boss each, Freighter salvage (boat/heli), Oasis PvP-off resupply stop, Airstrip flight course, single-flare night variants; then cut anything still under ~1 % of AreaDwell time.
  - **Rules:** one phase at a time, A then B then C, each phone-tested by Shaun. Real detailed models only (owned Synty / Creator Store / paid packs, WE_CHECK2 + origin rule; no block-part props, no rips, no real-world replicas). Mobile first, readable at 1024x471, nothing overlapping; light (world part/light budgets, <= 2 shadowless lights per model, capped NPCs, no heavy VFX, no new Heartbeat loops). `StreamingEnabled` and `PreferMesh` OFF; never touch `WE_Building*`. No fast travel (tap-to-pin only). How-to-play card (JOB 69 format) for every new activity. `OwnerFirst = true` (`MapPurposeConfig.Rollout`, OFF = today's map). No price changes, no new Robux products. Add `tools/checks/claude_bud_job73.py` (fail list in the doc, section 3.5), bump nothing yourself, and update `LATEST-HANDOFF.md` with a phone test list.
  - **Assets (Code Bot research 2026-10-02, nothing bought):** [`docs/claude-queue/JOB73-assets.md`](docs/claude-queue/JOB73-assets.md) (+ `.csv`): per area the owned models to reuse, 122 new free Creator Store picks (WE_CHECK2 origin check PENDING until Shaun does Get Model), 11 paid options needing Shaun's OK, rejects/re-uploads, and the gaps (fort, enterable Command HQ, flare stack). Use only ids from that file; run WE_CHECK2 + `tools/wire-asset-ids.py` before wiring.
- **JOB 77 — REBIRTH REWARDS ACTUALLY WORK (R1–R50) + Commander Statue (Shaun 2026-10-03; queued by Code Bot, docs only). QUEUED NEXT, after the jobs above (JOB 73 stays ON HOLD).** Full paste-ready brief, statue pick and thumbnails: [`docs/claude-queue/JOB77-rebirth-rewards.md`](docs/claude-queue/JOB77-rebirth-rewards.md).
  - **A. Audit R1–50** with `tools/checks/claude_bud_job77.py`: +10% cash per rebirth (+15% Boost) on EVERY earned income (passive, ATM, offline, kills, crates, oil, jobs, zone runs, missions, Plaza, bosses), never on dev-product cash or raid / nuke / Plaza-tax transfers; Gold 50+10/rebirth max 250; StartingCash steps; +2 soldiers (cap +40); zones R1–R8 on all 10 plots; vehicle / gun grants R1–R20; titles; every `RebirthConfig.Dressing` key must have a reader. Multiplier table R1/4/5/10/20/50; no cap without Shaun's OK.
  - **B. Commander Statue:** **USE `85904106700178` napoleon** (rip check PASS 2026-10-03: 1 MeshPart, mesh by its creator maxilou1234, no scripts, 19,997 tris); fallback `5352418094` Russian Statue (PASS). `4565808728` Horse Statue FAILED (foreign mesh/textures/sounds, 53 parts): do not use. Owned by shaunie6; wire via `tools/wire-asset-ids.py`. R50: on the parade ground, visible to all, anchored, no collisions/touch/query, Sounds stripped, `ScaleTo` ~16–18 studs, nameplate, Part fallback. Also replace the BaseTierBuilder T5 Capital block statue (one statue max per base). Owner `/statuetest`.
  - **C.** R10 roof Empire Beacon, R25 join fireworks (light, capped), R5/10/20 badge rows (BadgeId 0: list name/description for Code Bot, don't create), cosmetic-only R21–24.
  - **D. Labels (everyone):** garage Super Heavy P5→R10, Battleship P10→R12, Heavy Bomber P8→R20, Strategic Bomber P10→R20 (derive from the gate field); LevelConfig L40 "PRESTIGE UNLOCKED" only at the next rebirth's real level; fee text "Cash → $10000, +50 Gold" from `StartingCash` / `GoldBonus`.
  - **Rules:** `RebirthConfig.Rewards.OwnerFirst = true` (OFF = today exactly); no price changes, `MonetizationConfig` byte-identical, no new / renamed save keys; `StreamingEnabled` / `PreferMesh` OFF; never touch `WE_Building*`; mobile-first, no new Heartbeat loops; BuyPathStatic 0 FAIL; update `LATEST-HANDOFF.md` with the phone test list.
- **JOB 78 — Raid refill exploit + one-time Recruit packs + idempotent receipts (Shaun approved 2026-10-03; queued by Code Bot, docs only). QUEUED after JOB 77. BUG FIXES: these go PUBLIC (no OwnerFirst).**
  - **First prove each root cause from code (file:line)** before changing anything; fix the root, not the symptom.
  - **(1) Mid-raid refill exploit:** while the base is under attack (the same raid / under-attack state the raid code already uses), the server refuses wall level buys, Base Tier buys, the $750 gate repair and the HQ instant rebuild. Check it server-side in each handler, not just the UI. No charge and no partial grant on a refused buy. Show a clear `Can't repair during a raid` toast (mobile-readable, rate-limited) and grey out or relabel the buttons while the raid lasts. Everything works again as soon as the raid ends.
  - **(2) Recruit packs are one-time on the server:** the 5 R$ Starter Recruit pack and the 49 R$ Recruit Pack (`RecruitPack` 3715776659) can each be granted in full only once per player, enforced in ProcessReceipt, not just by hiding the button. A repeat purchase (for example from an old or open prompt) grants a smaller fallback, about 10 minutes of the player's current income through the existing time-pack income maths (one config value), shows a short notice and still returns `PurchaseGranted`. Never fail or hang the receipt. No price changes, `MonetizationConfig` prices and ids unchanged. Reuse any existing "bought" save field; if none exists, add it under the existing profile table, with no renamed keys.
  - **(3) Double grant on a retried receipt:** make ProcessReceipt idempotent for every developer product. Persist the `PurchaseId` as granted in the player's save (a bounded recent-receipts list in the existing profile, saved or committed) BEFORE returning `PurchaseGranted`. A `PurchaseId` that's already recorded returns `PurchaseGranted` without granting again. If the save can't be written, return `NotProcessedYet`, so Roblox retries with nothing granted twice. Covers Cash packs, time packs, the Recruit packs, the Mega Tank loan and all other products.
  - **Rules:** add `tools/checks/claude_bud_job78.py` (raid gate in all 4 handlers, one-time packs plus fallback, PurchaseId recorded before PurchaseGranted, duplicate skip, NotProcessedYet on save failure). Add a sim that replays the same receipt twice and buys each Recruit pack twice. Keep `tools/BuyPathStatic` at 0 FAIL and update `LATEST-HANDOFF.md` with a phone test list. No save-key renames, no price changes, `StreamingEnabled` / `PreferMesh` OFF, never touch `WE_Building*`.
- JOB 66 Speed Trial / 1 R$ Speed Boost - **DONE, REWORKED by Code Bot in v227 (Shaun 2 Oct 10:57/10:58). DO NOT rebuild the ring / timed-run version.** It is now a PLAIN 1 R$ PURCHASE (ProductId 3715953404, OwnerFirst=false), not a game: buying gives the Speed Pass walk speed for 5 min (`SpeedTrialConfig.TrialSeconds = 300`), a HUD chip "SPEED 4:59", and at the end a pop-up offering the full Speed Pass (GamePasses.ImpulseSpeed, existing pass prompt, BUY / NO THANKS). ONE TIME ONLY per player ever (`profile.SpeedTrial.Used`; the row hides, a stray receipt is acknowledged, grants nothing, is logged); shaunie6 470626172 + Laumartinez26 11718087109 may re-buy to re-test (extends). No ring course, no How to play card (`IsActivity = false`: the JOB 69 how-to rule does not apply), no START/CANCEL, no cash prize. Hidden for Speed Pass / Speed Boost owners except those two. Checks: `tools/checks/codebot_v227.py`, `tools/sim/run_speed_trial_test.py`.
> **Owner instruction (2 Oct 01:27): keep working through the queue continuously overnight. Do not stop or wait for replies. The owner will talk in the morning.**
- **JOB 70 (collision + wall style) — SHIPPED LIVE in v217 / place 215.** Do not rebuild. Prop Box hulls + one wall style per tier on every side.
- **JOB 71 — ADMIN ABUSE live event (TOP PRIORITY for Claude; Shaun approved 2026-10-02 11:10 Dublin). DEADLINE: built, tested and published by Thu 8 Oct 2026.** Same spec as on `claude/desktop-bud` (there still labelled JOB 70 — treat as JOB 71 here). Full detail below in the long JOB 71 entry; summary: owner-only Admin Abuse panel via MessagingService (Cash Rain, Airstrike Storm, Free Tank Drop, 2x Cash 10 min, Low Gravity, Speed for all, Giant Boss, Announcement), public countdown + LIVE banner + RSVP pop-up; `AdminAbuseConfig.EventId` = `9167160688932684354`.
- **JOB 67 — ASSET UPGRADE REMAINDER: IN PROGRESS / PARTIAL (Code Bot).** Batches 1–3 shipped (walls/base props v208; desert houses + Synty wrecks v214). Still open: rebirth-zone buildings (depends on JOB 69 slots, shipping owner-first in v218), drivable Synty bodies, Sketchfab/CGTrader. OwnerFirst stays true on Walls/BaseProps until the big flip.
- **JOB 68 — SHOOTING RANGE LIFE (real soldiers firing real guns).** The owner wants the army/base shooting range (the area with the red bullseye target boards) to show actual soldier NPCs in proper military uniforms, holding detailed rifle models (reuse existing owned weapon/soldier assets or the JOB 67 packs, with no block guns) and standing in firing positions facing the targets. They should fire on a loop: a muzzle flash, a short shot sound, a small hit puff/decal on the target, and an occasional reload animation. Keep it mobile-light: at most 3–4 shooters per range, client-side cosmetic only, a single shared low-rate loop (no per-NPC Heartbeat), effects only when a player is within about 80 studs, no PointLights spam and no heavy VFX. Use existing animation assets if owned. Rules: `OwnerFirst=true`; `StreamingEnabled` and `PreferMesh` OFF; never touch `WE_Building*`; no price changes; add `tools/checks/claude_bud_job68.py` and update `LATEST-HANDOFF.md`. Goes public together with the big flip after JOB 67. **SHIPPED owner-first in v218** (`RangeLifeConfig.OwnerFirst = true`).
- **JOB 69 — EVERY PLOT GETS ALL REBIRTH ZONES + HOW TO PLAY.** `OwnerFirst` behind `RebirthZonesConfig.Rebuild` (`OFF` = today's behaviour). Part A: AnnexAlt + ResolveSlots so every plot gets all 7 zones (incl. Nuclear Silo); Part B+C: how-to-play cards before zone runs / missions / jobs + on-run tracker. **SHIPPED owner-first in v218** (`Rebuild.Slots` / `Rebuild.HowTo` via `Rebuild.OwnerFirst = true`).
- After JOB 34 is finished and pushed, do JOB 35 then JOB 36 exactly as written in
  [`docs/claude-queue/JOB35-36-shop-and-guns.md`](docs/claude-queue/JOB35-36-shop-and-guns.md), one at a time, same
  rules. No fast travel.
- After JOB 36 is finished and pushed, do JOB 37 (real road checkpoint: detail + killable guards) exactly as written in
  [`docs/claude-queue/JOB37-checkpoint.md`](docs/claude-queue/JOB37-checkpoint.md), same rules. If any JOB 31 work is
  still unfinished, it may fold into JOB 37 (JOB 31 itself shipped in v128).
- After JOB 37 is finished and pushed, do JOB 38 (army ATTACK auto-clear nearest + SEND army to another player's base
  to breach gates / guards / turrets, raid fairness) exactly as written in
  [`docs/claude-queue/JOB38-army-attack-orders.md`](docs/claude-queue/JOB38-army-attack-orders.md), same rules. Owner-first
  flag, no teleport / PivotTo in marches, no fast travel.
- After JOB 38 is finished and pushed, do JOB 39 exactly as written in
  [`docs/claude-queue/JOB39-endgame-progression.md`](docs/claude-queue/JOB39-endgame-progression.md).
- After JOB 39 is finished and pushed, do JOB 40 exactly as written in
  [`docs/claude-queue/JOB40-guards-speed-props-like-reminder.md`](docs/claude-queue/JOB40-guards-speed-props-like-reminder.md).
  **PRIORITY (owner 2026-09-30 19:05): do part E (base owner markers: name above each base, visible from anywhere) FIRST
  within JOB 40, then A-D.** The owner wants the markers to drive attacks.
- **NEXT, TOP PRIORITY (Shaun 2026-09-30 23:19 Dublin; queued by Code Bot v153): when the job you are on right now is
  finished and pushed, do JOB 40E-FIX (base owner name tags: high in the sky, compact flag + short name, @handle only
  when close, distance scale with a clamp, fade + only the nearest 4-5, no overlapping tags, no tag without a live
  owner, YOU kept on your own base, phone test at 1024x471 with before / after screenshots, BaseMarker OwnerFirst stays
  true) exactly as written in
  [`docs/claude-queue/JOB40E-FIX-base-tags.md`](docs/claude-queue/JOB40E-FIX-base-tags.md) (`0f210ab` may already cover
  most of it: verify, finish, screenshot). THEN JOB 41 (moved to the front: it comes before every other queued job),
  then JOB 42.**
- **JOB 41 note (Code Bot v153, already LIVE for everyone on phase-7-polish):** Code Bot already shipped (a) the
  first-offer timing: the first paid offer (the Commander Starter Pack, or the 99 R$ Speed Boost when the pack is not
  wanted) comes at ~2 minutes of play whatever the tutorial state (`MonetizationConfig.FirstOffer`, the
  `ClaimSoftOfferSlot` quiet window, `MonetizationService.ScheduleFirstOffer`); (b) the Starter Pack re-queue: it is
  marked `StarterBundleOffered` only when the client confirms the card SHOWED (`OfferResult` remote +
  `Server/Modules/OfferLedger`), a dropped / refused / unanswered card comes back 45 s later; (c) the analytics keys:
  ProductPrompted now gets `productKey`, plus custom `PassBought` / `OfferShown` / `OfferDropped`. JOB 41 must NOT redo
  any of these. Its part B Recruit Pack must plug into the same path (ClaimSoftOfferSlot budget, FirstOffer schedule,
  OfferLedger "shown" ack, the same analytics fields); it must not push the first offer back to 10 minutes or the
  tutorial end, and must not mark an offer at send. If part B's "only after the first capture or 10 min" rule clashes
  with the 2-minute first offer, keep the 2-minute Starter Pack and ask Shaun in LATEST-HANDOFF.
- After JOB 40E-FIX is finished and pushed, do JOB 41 (the first minutes: a guided goal chain with a real first fight and
  capture, funnel analytics, a ~49 R$ Recruit Pack offered only after the first capture or 10 min, rival TARGETS with
  SEND ARMY, and a big-win rate prompt with NO reward) exactly as written in
  [`docs/claude-queue/JOB41-first-minutes-retention.md`](docs/claude-queue/JOB41-first-minutes-retention.md). Owner-first
  flags, no fast travel, servers stay at 10 players.
- After JOB 41 is finished and pushed, do JOB 42 (TIME-based cash packs that scale with the player's income: 15 min
  25 R$, 30 min 49 R$, 1 h 89 R$, 2 h 159 R$, 4 h 279 R$, NO 1-day / 7-day; rows "4 HOURS OF CASH" + the live $ amount
  computed server-side at receipt time; BEST VALUE on 4h; floors for new players; new Ids 0 until Code Bot creates them;
  old S / M / L / Mega kept in config but hidden once the time packs are live; the JOB 41 Recruit Pack cash = the
  30-min pack amount, still 49 R$) exactly as written in
  [`docs/claude-queue/JOB42-time-cash-packs.md`](docs/claude-queue/JOB42-time-cash-packs.md). Owner-first flag with a
  kill switch, no publish.
- **QUEUED AFTER THE LAST EXISTING JOB (Shaun 2026-10-01 18:18 Dublin): JOB 59 — Free Creator Store assets pass.**
  Strict order: complete the jobs already above, then JOB 59, then JOB 60 immediately below it. All listed assets are
  already in Shaun's (shaunie6) inventory. Keep `OwnerFirst = true` for the config/phone test, add the feature's
  `tools/checks/claude_bud_job59.py` checks, update `LATEST-HANDOFF.md`, and obey the house rules: mobile-light (few
  lights/props, cap props per base, sounds 3D/proximity only, no heavy VFX), `StreamingEnabled` / `PreferMesh` off,
  never touch `WE_Building*`, no franchise models, real detail.
  - **(A) Helipad helicopter:** rebuild the helipad heli using SKYtech rotorKit `9961947424` (or rotorLite
    `12918869816`); vendor its remote self-updating module locally using local copy `96681147793573`, audit every
    script, and use no remote `require`. Fix the tilt and detached rotor. Coordinate with JOB 56 and fold this in if
    JOB 56 has not started. aeroKit `8521123488` is optional for hangar jets.
  - **(B) Sound pass:** create/use one central `SoundConfig` with night crickets `9112764546`, night ambience
    `9112835836`, harbor night `9112792684`, desert wind `9114057104`, flag flap `9114461215` / `9114576083`, radio
    chatter `9112851398` / `9125793009` near Command Center, distant artillery `9113169264` in desert, heli
    `9113417759` / `9125390124`, boats `9112750448` / `9126201834`, gate `9116875342`, raid siren `9119661640`,
    cash collect `9113728042`, UI clicks `15675059323` / `15675032796`, and Military March `1844397606` for
    menu/rebirth with cuts `1841116989` / `1845181958`. Sounds must be 3D/proximity-only where world-placed.
  - **(C) Night and base life:** fold into JOB 54 / JOB 57 where applicable. Use lights `8217816335`, `1725607094`,
    `404475960` sparingly (8k-triangle cap); Night Fog sky `1864839162`, fireflies `3347717118`, dust `615333766`,
    fire/smoke `11365590395` only on raided bases/wrecks, and VFX textures `17290956157`. Add lightweight props:
    sandbags `5678434293`, crates `2930926216`, ammo crates `2190705941` (credit the creator), border fence
    `4715423769`, metal gate fence `9083814252`, and parked Roblox pickup truck `6418225759`.
  - **(D) Vault top tier:** use Vault Door `14795516338` as the highest vault-upgrade visual, tied into JOB 53 and read
    from the central upgrade config.
  - **Available Studio plugins:** Archimedes `144938633`, F3X `144950355`, Brushtool `2268520847`, RigEdit Lite
    `1274343708`, AutoScale Lite `1496745047`, VFX Studio `135581141962270`, Tag Editor `948084095`, and GapFill
    `165687726`.
- **JOB 60 — Fix error report (small job, immediately after JOB 59).** Find and fix the root causes, not symptoms, for
  the top error report: 2,233/day `Failed to load animation with sanitized ID`; 265 server sanitized-animation errors;
  340 animation-track-limit warnings; 98 mesh fetch errors; 67 AnchorPoint nil errors; and 42 sound ConnectFail.
  Add `tools/checks/claude_bud_job60.py`, keep the same `OwnerFirst = true`, mobile-light, `StreamingEnabled` /
  `PreferMesh` off, `WE_Building*` untouched and no-franchise/real-detail rules, and update `LATEST-HANDOFF.md`.
- **JOB 61: Creator Hub Economy + Funnels analytics (AnalyticsService)**
- **Store props (Code Bot STORE-PROPS, v132): DO NOT REMOVE.** The owner's Creator Store buildings / props live in
  `Shared/Configs/StorePropsConfig.luau` (placed by `Services/StorePropsService.luau`; list in
  [`docs/PROP-ASSETS.md`](docs/PROP-ASSETS.md)). They dress the JOB 31 sites / named areas and swap in as the JOB 33
  rebirth zone upgrade visuals (the Part build stays as the fallback). Do not delete the config, its rows or the
  service; do not name your own parts `Store_*`; keep new builds clear of `Workspace.WorldFill.StoreProps`. The
  service does not modify RebirthZoneBuilder / RebirthZoneService: it only reads the `Zone_<Id>` folders they build.
- **JOB 71 — ADMIN ABUSE live event, Sat 10 Oct 2026 20:00–20:30 Dublin (Shaun approved 2026-10-02 11:10 Dublin; queued by Code Bot, docs only). DEADLINE: built, tested and published by Thu 8 Oct 2026.**
  - **Config:** one central `Shared/Configs/AdminAbuseConfig.luau`: `Id = "AdminAbuse1"`, `Name = "ADMIN ABUSE"`, `StartUnix = 1791658800` (Sat 10 Oct 2026 19:00 UTC = 20:00 Dublin), `EndUnix = 1791660600` (19:30 UTC = 20:30 Dublin), `OwnerUserId = 470626172`, `EventId = "9167160688932684354"`, `PopupTitle = "ADMIN ABUSE: LIVE CHAOS!"`, `PopupWhen = "Sat 8pm – 8:30pm (Irish time)"`, `PopupPerks = "Cash rain · Airstrikes · Free tanks · Giant boss"`, `ChipText = "ADMIN ABUSE"`, plus every action's duration / amount / cooldown below. Nothing hard-coded outside the config.
  - **Owner panel (ADMIN-ONLY FOREVER, never a public flag):** an `ADMIN ABUSE` panel opened from the existing admin tools, gated server-side by `AdminConfig` (owner 470626172) on every remote call, not just client UI. Big mobile buttons (min 56 px, 2 columns, safe area, clear of thumbstick / fire buttons, nothing overlapping at 1024×471): **CASH RAIN**, **AIRSTRIKE STORM**, **FREE TANK DROP**, **2x CASH 10 MIN**, **LOW GRAVITY 5 MIN**, **SPEED FOR ALL 5 MIN**, **GIANT BOSS**, **ANNOUNCE** (text box, filtered with `TextService:FilterStringAsync` / broadcast filtering), and **STOP ALL**. Each button shows its own cooldown / active timer.
  - **All servers:** the panel's server handler validates, then publishes on one `MessagingService` topic (`WE_AdminAbuse`, payload `{action, args, sentAt, nonce}`, under the 1 KB limit); every server (including the sender's) subscribes and applies it locally; dedupe by nonce; ignore messages older than ~30 s; rate-limit per action. Server-authoritative everywhere; clients only render.
  - **Actions:**
    1. **Cash Rain:** cash crates drop across the map (cap ~30 crates per server, anchored light parts / existing crate model, auto-despawn ~60 s); touch/prompt collects a config amount once per crate per player, paid through the normal EconomyService path.
    2. **Airstrike Storm:** reuse the existing airstrike VFX/path; harmless to buildings and bases (no structure / ATM / wall damage), small player damage, **never kills** (clamp health to ≥ 1), respects spawn protection (JOB 63) and safe zones.
    3. **Free Tank Drop:** every player gets a free temporary tank for 10 min via the existing vehicle spawner; despawns at expiry or on leave; never saved, never counts as owned.
    4. **2x Cash 10 min:** a temporary server cash multiplier through `EconomyService.cashMultFor`. Must NOT stack with Double Weekend or other event multipliers (take the max, not the product) and must not double raid/nuke transfers (JOB 65 rule).
    5. **Low Gravity 5 min:** `Workspace.Gravity` to a config value, restored exactly at the end / on STOP ALL.
    6. **Speed for all 5 min:** temporary WalkSpeed via the existing MoveDebug / SpeedTrial path, restored at the end; never lowers a pass owner's speed.
    7. **Giant Boss:** ONE large detailed NPC per server (real model, not block parts) everyone fights; big shared reward to all who dealt damage (config amount, paid once), health scales with player count, despawns after ~5 min if not killed; shows a health bar.
    8. **Announcement:** filtered text shown to every player on every server as a big centred banner for ~6 s.
  - **Public UI:** (a) a server-wide **ADMIN ABUSE LIVE** banner/chip for everyone between StartUnix and EndUnix (and whenever the owner presses any action); (b) a **countdown chip** under TARGETS for everyone from 24 h before the start ("ADMIN ABUSE · in 5h 12m", tap = details card); (c) a **once-per-player RSVP pop-up** exactly like the Double Weekend one (`DoubleWeekendController` / `EventConfig.EventId`, `profile.EventPopupSeen[Id]`, skipped when `GetEventRsvpStatusAsync` says Going, `PromptRsvpToEventAsync` on the **NOTIFY ME** button, never over tutorial / onboarding / other panels). Reuse that code: generalise it to read a list of events rather than duplicating it. The chip and pop-up are PUBLIC (no OwnerFirst); the panel stays owner-only; the actions only ever run when the owner triggers them.
  - **Performance:** light only: no heavy VFX, few NPCs (1 boss), capped crates, no new per-frame Heartbeat loops (1 Hz timers), sounds 3D/proximity only.
  - **Rules / checks:** `StreamingEnabled` / `PreferMesh` OFF; never touch `WE_Building*`; no price changes; no new Robux products; no save keys besides the popup-seen entry; everything temporary is restored on STOP ALL / end / server close. Add `tools/checks/claude_bud_job71.py` (panel gated server-side by AdminConfig, MessagingService topic + nonce dedupe, Airstrike Storm cannot kill or damage buildings, 2x Cash does not stack with DoubleEvent, gravity/speed restore, crate cap, Start/End unix = 20:00/20:30 Dublin, EventId is a string), a Studio 2-server/2-player test of every action, `tools/BuyPathStatic.py` 0 FAIL, bump `WE_Build`, and update `LATEST-HANDOFF.md` with a phone-test list for Shaun (open panel, press each button, check a second server receives it).
- **No fast travel, ever:** it was removed in v127 at the owner's request. The map is tap-to-pin only (see
  `tools/checks/codebot_v127.py`).

## 0. Start here (every session, every time)
- **Parallel sessions:** read [`LANES.md`](LANES.md) first. It says which lane your job is in, which files you own,
  the rules for shared hot files, the branch name (`claude/lane-<x>-<topic>` from the latest `phase-7-polish`), and
  how to hand back (push your branch, reply `DONE` with a summary and a test list).
- **Background:** `LATEST-HANDOFF.md`, `HANDOFF-TO-NEW-CODE-BOT.md`, `MASTER_BUILD_SPEC.md`, then the newest
  sections of `ASSUMPTIONS.md` for your area.
- **Never:** bump `WE_Build`, publish, build `dist/`, or push to `phase-7-polish` or `main`. Those are Code Bot's
  job (the integrator).
- **Flags:** new gameplay ships owner-only first (`AdminConfig.IsPlaytestOwner`, UserId 470626172, like
  `ArmyConfig.Rollout` and `AircraftWeaponConfig.LiveFor`) behind a config switch. OFF must equal the old behaviour.
- **Store models (Creator Store assets):**
  - A model is used only after it passes the owner's `WE_CHECK2` check (`tools/WeCheck2*.luau` via Open Cloud;
    see `docs/ASSET_WIRING.md`).
  - Origin rule: every mesh and texture must be uploaded by the model's creator (or by Roblox).
  - At most 40 parts after trimming, no scripts (strip them), at most 20,000 triangles for phones.
  - No real-world or franchise copies (no F-16, B-2, Apache, Black Hawk, named real ships, other games' assets).
  - It goes through `tools/wire-asset-ids.py` (PENDING, then promote or REJECT) and is attributed in
    `docs/ASSET_LICENSES.md`.
- **BuyPathStatic:** add your pins to `tools/checks/lane_<x>.py`, never to the body of `tools/BuyPathStatic.py`.
- **Definition of done:**
  - the parse gate is clean on changed files;
  - `python3 tools/BuyPathStatic.py` ends `FAIL=0`, with your new pins;
  - `rojo build` succeeds;
  - the feature's own tests pass (no invented results);
  - the change is behind an owner-only flag if it is gameplay;
  - an `ASSUMPTIONS.md` section is appended;
  - the branch is merged with the latest `phase-7-polish` and pushed;
  - the `DONE` reply lists what the owner must test **on his phone**.


Roblox military tycoon/PvP. Luau (`--!strict`) + Rojo. Build: `rojo build -o dist/WarEmpire-PERF.rbxlx`.
The owner publishes this branch to the live game, so every push must be tested.

## 1. Mobile first (about 80% of players are on phones)
Design, build and verify for a **phone in landscape first**, PC second. Anything that only works well on PC is unfinished.

- **Screens to check:** 844×390, 956×440 (the owner's phone), 800×360 (small phone), 1180×820 (tablet), then 1280×720 and 1920×1080.
- **Touch:**
  - Every action has a touch control; no feature may be keyboard-only (exit vehicle, lift/descend, reload, weapon switch, orders, garage, prompts).
  - Tap targets are **≥ 44 px real** (48+ preferred).
  - Nothing important sits under the Roblox thumbstick (bottom-left), the jump button (bottom-right) or the top-bar pills.
  - Hold prompts must work with a finger.
  - No hover-only UI.
- **Readability:**
  - Text is ≥ 14 px real at phone scale, high contrast, with short labels (2–3 words).
  - One message at a time; no screen-covering pop-ups during combat or driving.
  - World billboards stay small and must never cover the HUD.
- **Performance (phones overheat and drop frames long before PCs):**
  - Keep part counts inside the budgets in the specs.
  - Few lights, `Shadows = false` on small lights, no neon floods.
  - No per-frame `GetDescendants` / allocations in `RenderStepped`/`Heartbeat`.
  - Throttle loops (≤ 10 Hz for UI refresh); cap particles.
  - Use `UnreliableRemoteEvent` for effects; keep remote traffic ≤ 20 Hz per player.
  - Code must be safe under StreamingEnabled: never assume a workspace part exists on the client, and never `WaitForChild` without a timeout.
- **Game feel on touch:**
  - Controls must be forgiving: aim help on touch, generous prompt ranges, and vehicles that drive with the thumbstick alone.
  - Auto-collect and auto-actions are preferred over precise taps.
- **Real px, not code px:**
  - Phone HUDs run under UIScale ≈ 0.70 and panels under ≈ 0.65.
  - So 44 px real means ≥ 64 in code (≥ 68 under 0.65), and 14 px text means ≥ 20 in code.
  - Size helpers take **real px**.
- **Reserved zones:**
  - Nothing tappable in the left 40 % × lower ⅔ of the safe area, except one edge rail.
  - Nothing within 16 px of the jump button.
  - Jump is the only touch exit, so it is never covered.
  - Airborne exits need a hold.
- **Copy by device:**
  - Never name a key or say "click" in text a phone player can see (toasts, billboards, tutorial).
  - Key hints appear only when `PreferredInput` is keyboard or gamepad.
  - Detect the device with `PreferredInput`, not `TouchEnabled`.
- **World labels:**
  - Stud-scaled, 14–20 px text, `MaxDistance` ≤ 40.
  - At most 3 on screen at a base and 5 at an outpost.
  - `AlwaysOnTop` only for the one active objective marker.
  - No debug labels on live.
  - The one documented exception (owner-approved 2026-09-30, JOB 40 part E): the **base owner marker** (one per
    occupied base, `BaseMarkerConfig`: name, flag, rank, `MaxDistance` 5000, `AlwaysOnTop`, hidden inside 60 studs).
    Nothing else gets this.
- **Pointers:** anything that points a player somewhere (tutorial beam, waypoint, GO line) resolves to **their own** plot or the nearest valid target, never a fixed world marker.
- **Combat fairness:**
  - The server never trusts a target id sent by the client.
  - Assisted hits need line of sight and follow the aim-assist config.
  - NPC shots need line of sight and a hit chance.
- **Travel:** any core-loop trip over 30 s on foot needs a shortcut (sprint, vehicle or recall).
- **Budgets:** these are hard caps and must not grow. The target is reached by the phone-performance pass.

  | Budget | Hard cap | Target |
  |---|---|---|
  | Parts per base at L5 | 2,700 | 2,000 |
  | World parts outside bases | 3,100 | 2,000 |
  | Lights | 730 total, 40 per base | 300 total |
  | SurfaceGuis | 1,134, each `MaxDistance` ≤ 80 | 400 |
  | Neon parts | 986 | 300 |
  | Instance changes per purchase | — | 60 |
  | Catalog models | ≤ 40 parts each, no Humanoid, templates in ServerStorage | — |
  | Client per-frame work | no whole-tree scans | — |
  | UI refresh rate | 10 Hz | — |

- **Test like a phone:**
  - Performance claims use the live dressing level.
  - Confirm them on a mid-range Android or at Graphics Quality 3. The owner's top-end iPhone is not the bar.
- **Verification:**
  - Run the HUD harness at phone viewports (`check_hud.py --viewports phone,owner,desktop`), plus 800×360 and 1180×820, including panels with data.
  - Every change note says what the owner must test **on his phone**.

## 2. Hard rules
- **Server authority:**
  - Cash, XP, upgrades and ownership are decided on the server.
  - There are NO `GiveCash`/`GiveXP` remotes. Clients request; the server validates and rate-limits.
- **Config first:** tunables live in `src/ReplicatedStorage/Shared/Configs`.
- **Remotes:** never `WaitForChild` forever on the remotes folder; use the `Shared/Remotes` helpers.
- **Data:**
  - `DataService.Init()` runs before any service that calls `GetProfile`, and `GetProfile` is nil until the real save has loaded.
  - Never wipe production DataStores.
  - Never change the Place or Universe IDs.
- **Purchases:**
  - Grants happen only in `ProcessReceipt` (save before `PurchaseGranted`), or through pass ownership checked with `UserOwnsGamePassAsync`.
  - New product Ids stay 0 until the owner creates the product.
- **Admin cash:** keep `AdminPlaytestCash` for UserId 470626172 only. Never grant it to anyone else.
- **Structures:**
  - `PreferMesh` stays OFF for structure kits.
  - Perimeter walls spawn on the DefensiveWalls purchase (`SyncPerimeterWalls`). Do not break this.
- **Build guide:** every build job (buildings, props, vehicles, interiors, POIs, lighting, NPC or UI polish) follows [`docs/ROBLOX-BUILD-GUIDE.md`](docs/ROBLOX-BUILD-GUIDE.md) and ticks its §11 detail checklist in the DONE reply.
- **Names and assets:**
  - No real-world brand, vehicle or weapon names. Real countries appear only as a player's own cosmetic nation, chosen by the player from `NationConfig` (current national flag + short name, owner-approved list, ISO 3166 ids). Never: historical, regime, separatist, extremist or party flags; military insignia; a real country on NPCs, map places, vehicles, factions or leaderboards; a nation name in any kill, strike, nuke, raid or capture message; nation-vs-nation rules, bonuses or matchmaking; a flag shown damaged, burning, on the ground, beside strike effects or as a target. Flags in the world are Textures/Decals, never SurfaceGuis. Players never draw flags or type nation names. An IP-derived country is only a suggestion to that player: never auto-applied, shown to others, stored or logged.
  - Never copy another game's assets or code. Re-implement mechanics and use only Roblox-official or permissively licensed parts, with attribution.
- **Luau gotcha:** a line that starts with `(` right after another statement needs a `;` in front of it.
- **Ambiguity:** make a reversible assumption, record it in `ASSUMPTIONS.md`, and keep going.
- **Tests:** never invent test results. The headless stand-in is not Roblox; say what still needs a real device.

## 3. Checks before any commit
- Parse gate: `luau-compile --binary` on every changed file.
- Type check (`luau-lsp analyze` with the sourcemap): no new errors compared with HEAD.
- `LUAU_COMPILE=… python3 tools/BuyPathStatic.py`: 0 failures.
- Headless world sim: every step ok.
- `DataService` harness: all pass.
- Plus the feature's own tests.

Commit only files that were verified together. Lane sessions push only their own `claude/lane-*` branch (LANES.md §6); Code Bot pushes `phase-7-polish` and the Padel-AI mirror.
