# DESIGN COMPETITIVE DEEP DIVE — WAR EMPIRE

**Scope:** design and presentation only. This is not an economy-systems spec and does not change prices, payout rules, combat balance, or vehicle physics.

**Research date:** 2026-09-20 (Europe/Madrid)

**Primary reference:** [Military Tycoon](https://www.roblox.com/games/7180042682/Military-Tycoon), place ID **7180042682**, InfinityInteractive.

**Peers:** [War Tycoon](https://war-tycoon-roblox.fandom.com/wiki/Base), plus public Roblox military-tycoon guides and gameplay videos.

**Related internal research:** [`docs/COMPETITIVE_DEEP_DIVE.md`](COMPETITIVE_DEEP_DIVE.md) Pass 1 + Pass 2 and [`docs/BENCHMARK_MILITARY_TYCOON.md`](BENCHMARK_MILITARY_TYCOON.md).

**Legal/product stance:** Inspiration is limited to observable presentation patterns. Do not copy competitor meshes, logos, trademarks, UI art, flags, names, or branded landmarks. Use WAR EMPIRE silhouettes, palettes, icons, and motion language.

---

## Executive read

The strongest competitor advantage is not polygon count. It is **visual causality**: the player buys one object and immediately sees a worker, room, wall, vehicle bay, flag, or light appear in the world. Military Tycoon makes the first minutes legible with a small set of high-contrast anchors: a button, a visibly active worker, a green-screen ATM, and a large flag. War Tycoon extends the same language into rooms: oil extractors, garages, hangars, bunkers, and rebirth-gated spaces advertise what the next session unlocks.

WAR EMPIRE already has the right presentation skeleton (`StructureKitBuilder`, `VisualAssetConfig`, `MapDressing`, `HUDController`, and the `MoneyCollectorService` billboard). The remaining work is hierarchy and authored identity:

1. Make the collector an unmistakable **ATM-like hero prop**, with a physical screen, readable digits, and a visible pending state both in-world and in the HUD.
2. Make every bought structure read as a **distinct military silhouette** from the player spawn and from the road, not as a colored box on a plinth.
3. Treat the garage as a **showroom and ceremony** (preview, requirement, owned state, spawn pad, exit), while keeping the existing Jeep/`VehicleService` fixer isolated from this design pass.
4. Reduce HUD competition: cash/pending, level, current objective, and the next action should win over secondary chips.
5. Turn tutorial markers, buy pads, captures, and collection into one consistent visual guidance language.

### Evidence limits

This is a public-source desk review, not a live competitor session. Wiki pages and guides can describe current or historical states, and YouTube footage can reflect a specific update. Treat exact dimensions, timings, colors, and counts as design signals rather than requirements. No competitor asset was imported or reused.

---

## 1. What the public references show

### Military Tycoon (place 7180042682)

The Roblox listing frames the promise as: build a military base, unlock 100+ vehicles, train an army, raid players, and capture fortresses, oil rigs, and key locations. Public wiki/guide descriptions and videos consistently reinforce these visual beats:

- A base begins as an **empty plot with a recognizable ATM/collector** and purchase points.
- Classic floor buttons are close to the thing they will create. The purchase is spatial: walls, floors, worker NPCs, weapon racks, and rooms appear where the player expects them.
- Workers stand at a range and visibly shoot targets. The tiny loop is a strong visual explanation of “this base is working.”
- The base grows vertically and horizontally: garage, adjacent helipad, airfield, dock, bunker, walls, roof defenses, and interior rooms produce a changing skyline.
- Flags and capture zones are large, simple, and readable at distance. A captured point changes nation color, giving the world a before/after state.
- The collector’s **dark body + bright green screen/digits** is a stronger icon than a generic neon pillar. It is visible from the base path and tells the player what to touch.
- Public update footage shows large POI anchors: runway/airfield, outpost, oil rig, city bank, control panel, NPC vehicles, and a flag changing color after capture. The lesson is spatial legibility, not a request to reproduce any named landmark.

### War Tycoon

Public War Tycoon pages describe a base organized around oil extractors, walls, bunkers, missile bays, docks, plane/helicopter hangars, and rebirth-gated rooms. The relevant presentation patterns are:

- Producers are **large physical props** (extractors, drills, generators), not only a number in a menu.
- Rebirths reveal a new room or verb: Vehicle Bay, Tank Garage, hangar, bunker, research, or an aircraft category. Unlocking space is more legible than receiving only a multiplier.
- The Vehicle Bay/Tank Garage shape is a protected showroom: enter a readable room, browse owned/locked vehicles, preview the choice, spawn inside a marked bay, then leave through an obvious gate.
- Oil drums/barrels and world objectives are physical, colored objects that can be spotted while driving.
- Map beacons and capture points are useful because they preserve a clean destination hierarchy on a large map.

### Similar Roblox military tycoons and public video signal

Across the references, the repeatable presentation grammar is:

- **One anchor per verb:** ATM/collector for collect, button/pad for buy, flag for capture, garage for spawn, runway/dock for category.
- **One strong color per state:** green = available/healthy/cash, gold = reward/ownership, blue = friendly/captured/air, orange/red = hazard/locked/contested.
- **Large silhouettes before detail:** a player recognizes a hangar roof, tower, wall ring, or tank before reading a label.
- **Short feedback loops:** purchase flash, screen digit change, flag color change, capture ring, muzzle flash, dust puff, door/light activation.
- **Creator-readable moments:** “base got bigger,” “cash screen filled,” “flag turned blue,” “new vehicle came out of the bay.”

---

## 2. Design comparison: competitor patterns vs WAR EMPIRE

| Surface | Military Tycoon / War Tycoon pattern | WAR EMPIRE today | Design direction |
|---|---|---|---|
| Building silhouette | A purchased room/worker/wall changes the skyline immediately | `StructureKitBuilder` has distinct kits, but many remain primitive and small on a large plot | Design each structure around a 3-second recognition silhouette and a visible “growth delta” |
| Vehicle look | Category-specific silhouettes; vehicle space is part of the base fantasy | `VisualAssetConfig` has free-asset overlays and family fallbacks; kit fallback remains useful | Use a consistent WE asset contract: recognizable body, accent stripe, category icon, preview camera, safe fallback |
| Garage UX | Protected showroom/manager; owned, available, locked states; category room | Existing garage skeleton (`G`, `E`, owned filtering, BUY → SPAWN, auto-seat) | Design the room, card hierarchy, requirement copy, spawn pad, exit, and despawn states; do not touch contested physics work here |
| ATM/collector | Dark/grey prop with green cash screen and live accumulated amount | `MoneyCollectorService` already creates `WE_CollectorBillboard` and can sync `CollectorScreen` | Make the physical collector readable from spawn; use screen, glow, pulse, digits, and a compact HUD mirror |
| HUD | Cash/diamonds and rebirth/country are prominent; secondary features are discoverable | Strong level/XP, cash/gold pill, pending label, passive hint, spinner, and mobile action bar | Protect contrast and safe zones; pending and current objective outrank spinner/season/secondary actions |
| Map dressing | Island/desert POIs, flags, oil rigs, city/bank, runway, bunker, road landmarks | `MapDressing` provides checkpoints, outposts, hangars, camps, depots, radio, docks, signs, lights, bunkers, and warzone fill | Add a landmark rhythm and approach silhouettes; avoid clutter that competes with capture/route beacons |
| Tutorial guidance | Country/identity, one first verb, safe base, worker → ATM, then weapon/flag path | Markers and short steps exist; current pass is ClaimBase → CC → Income → Barracks → Jeep → Outpost | Put an authored marker, camera-facing sign, pad highlight, and reward reaction on every step; train/collect before travel |
| Buy VFX | Button-to-object spawn is the reward; base visibly changes | BUY GUI and kits are functional, visual feedback is light | Add affordance, confirmation, construction flash, dust/electric accent, and “new silhouette” camera beat |
| Collect VFX | Green digits, repeated touch ritual, cash visibly accumulates | Touch/auto collect and notification work; billboard refreshes | Animate digits, cash particles, screen state, ring pulse, audio, and HUD pending-to-cash transition |

---

## 3. Building silhouettes and base growth

### What works in the references

A base reads as a military base through a few large profiles, not through many small props:

- **Command:** a compact HQ with roof device, mast/antenna, entrance, and a distinct front face.
- **Barracks/training:** a long low building with repeated windows, door, flag/yard, and visible personnel activity.
- **Vehicle depot/garage:** a wide opening, high roof, apron, safety stripe, overhead sign, and a vehicle-shaped void.
- **Hangar/airfield:** a roof large enough to imply a real aircraft, runway markings, edge lights, and a clear approach axis.
- **Dock:** waterline, pier, bollards/crates, category sign, and an open spawn lane.
- **Defense:** wall ring plus gate, corner towers, roof emplacements, lights, and a visible route into the base.
- **Bunker/deep command:** low mass, reinforced door, slit window, vent, antenna, and a different material language from surface buildings.

Military Tycoon’s “buy → spawn” drama is effective because each purchase occupies a known footprint and adds one of these profiles. War Tycoon’s room gates are effective because the profile tells the player what the room is before a menu is opened.

### WAR EMPIRE silhouette rules

1. **Read at thumbnail scale.** At a distance of roughly 100–150 studs, each L1 structure must be distinguishable by height, roofline, opening, or vertical accent—not only by color.
2. **Keep one signature shape.** Do not add random antennae to every kit. HQ = mast, barracks = windows/awning, depot = tall door, lab = dish/glass, hangar = roof/door, dock = pier/crane.
3. **Use a restrained material stack.** Concrete/olive metal for mass, a darker roof or door for depth, one gold/blue/green functional accent. Neon is a state/readability cue, not the whole building.
4. **Make L0 useful.** A locked plinth can show a low-contrast ghost outline or sign; L1 should replace it with a solid, shadow-casting silhouette and a short purchase flash.
5. **Build outward before upward.** Early players should see a larger defended footprint, gate, and training activity before a tall late-game tower hides the base.
6. **Use a “hero face.”** Orient each kit’s door/sign/bright accent toward the expected approach and camera; avoid a beautiful side facing away from the player spawn.
7. **Make level changes cumulative.** L2 can add roof equipment, lights, sandbags, or a second bay; L3 can add a room/wing. Do not swap the whole silhouette so the player loses ownership continuity.

### Concrete implementation targets

- `StructureKitBuilder.luau`: add/iterate signature roles (`Door`, `Roof`, `Mast`, `BayOpening`, `WindowBand`, `Sign`, `Light`, `Crate`, `Sandbag`) and make L1/L2/L3 deltas intentional. Preserve the existing authoritative fallback behavior.
- `StructureVisualConfig.luau`: document a per-structure `HeroFace`, `PrimarySilhouette`, `AccentColor`, `L1Delta`, `L2Delta`, `L3Delta`, and optional overlay asset key. This is a design contract, not a new economy gate.
- `VisualAssetConfig.luau`: keep free-asset IDs and family fallbacks, but add presentation metadata (category, expected facing, preview scale, camera offset, seat/door alignment note). Never depend on an inserted model for basic readability.
- Base presentation: when `DefensiveWalls` reaches L1, show the wall ring and gate as a deliberate ceremony. The ring should frame the collector and command center rather than obscure them.

---

## 4. Vehicle look and garage UX

### Vehicle look: borrow the category grammar, not the assets

Military Tycoon’s large catalog works visually because vehicles are grouped into obvious families: jeep/truck, tank/APC, helicopter, jet, and ship. War Tycoon’s garage rooms reinforce that grouping. WAR EMPIRE can use the same readability without copying any mesh:

- **Wheeled:** four-wheel stance, visible cabin/bed, front grille/light bar, olive body, yellow/gold WE stripe.
- **Tracked:** wide low hull, turret/barrel, tread blocks, darker mass, red/orange weapon-state indicator only when active.
- **Helicopter:** rotor disk, tail boom, landing skids, blue/cyan navigation lights.
- **Jet/plane:** long nose, wings, tail, runway-facing display angle, white/gold markings.
- **Naval:** long waterline profile, bridge block, mast, wake/port lights, dock-facing display orientation.

The player should recognize the category before reading the name. A family fallback can be visually honest (“light wheeled” rather than pretending to be a unique super-heavy), while catalog identity comes from color bands, silhouette changes, and a WE-original designation plate.

### Garage UX shape

Use the existing conceptual flow from Pass 2:

1. **Approach:** a visible bay/door says `VEHICLE DEPOT` and shows a category icon. The free Jeep is on a marked display pad or silhouette frame.
2. **Browse:** a selector shows **OWNED** first, then **AVAILABLE**, then **LOCKED**. Category tabs are visible; avoid hidden menus.
3. **Preview:** large vehicle image/viewport, name, role, speed/armor/seats, one requirement line, and a simple WE designation. Do not bury the requirement in a tooltip.
4. **Buy then spawn:** after a purchase, the card changes to `OWNED / SPAWN`. Starter vehicle has no redundant second confirmation.
5. **Spawn:** a lit pad faces the exit, with a clear `DRIVE` prompt if auto-seat replication is late. Show a one-active-vehicle message in the same style as the garage UI.
6. **Leave/despawn:** the gate and road are visually obvious. `DESPAWN` is available from the garage and HUD; do not make the player hunt for the vehicle manager.
7. **Late categories:** prestige or structure-gated rooms should open with a small ceremony (door light, sign, preview stand, short banner), not merely a newly enabled row.

### Explicit boundary for this document

The existing Jeep/`VehicleService` fix is a separate engineering concern. This design pass must not edit or replace the contested physics implementation, start a VehicleService fight, or claim that a mesh overlay makes a vehicle driveable. Design Bot can author showroom art, preview framing, signs, icons, and state transitions around the existing vehicle contract. Code Bot can wire presentation hooks once the fixer branch supplies a working vehicle. No Roblox publish is part of this task.

### File hints

- `VisualAssetConfig.luau`: asset metadata, family fallback, facing/scale/preview notes.
- `StructureKitBuilder.luau`: depot/hangar/dock silhouette, display pad, category sign, door and lighting roles.
- `HUDController.luau`: garage open/close, active vehicle, despawn and Drive fallback affordances if not already exposed by the existing controller.
- Do not modify `VehicleService.luau` in this docs task.

---

## 5. ATM / collector visual language

### Competitive lesson

A collector succeeds when a new player can answer three questions without opening a menu:

1. **What is this?** A recognizable machine with a screen and a cash icon.
2. **Is there cash now?** Live digits, green screen state, glow, and a mild pulse.
3. **What do I do?** `TOUCH TO COLLECT` / `COLLECT` prompt, plus an audible and visual response.

The dark body + green screen observed in Military Tycoon is a good genre reference, but WAR EMPIRE should use its own proportions and insignia. Do not make a generic neon pillar carry all three jobs.

### WAR EMPIRE collector treatment

- Use a squat grey/olive kiosk or armored terminal: body, top cap, service panel, screen recess, feet, and a visible WE emblem.
- Keep the green screen as the functional focal point. `CollectorScreen` should be an actual screen surface with enough contrast to read from the approach path.
- `WE_CollectorBillboard` can remain the distance-readable layer, but use it as a sign above the prop, not as a substitute for the prop. Prefer `ATM · TOUCH TO COLLECT`, live `$N`, and a small pending icon.
- At zero pending: dark screen, low glow, no repeated “reward” animation. At positive pending: readable digits, gentle green glow, slow breathing light. At a threshold: brief ring/pulse, not a distracting alarm.
- On collect: digits count down or snap with a short easing animation, a small upward cash burst, a ring flash at the feet, a compact `+$N COLLECTED` response, and a single short sound. Respect mobile and low-quality settings.
- On AutoCollect: do not remove the prop. Keep the prop as a world landmark, show `AUTO COLLECT ON` in a small state plate, and use a restrained periodic pulse so it does not look broken.
- Match the HUD: the cash pill shows spendable Cash, with a dim secondary `+$pending` line and a tap/route hint only when relevant. This is presentation of the existing state, not a change to collection rules.

### Code/design split

- Code Bot: `MoneyCollectorService.luau` hooks for state thresholds, screen/billboard refresh, collect success, AutoCollect state, and client VFX events; keep server authority and existing touch behavior.
- Design Bot: collector mesh/part kit, screen layout, icon, green-state palette, digit typography, ring/pulse, cash burst, sound direction, and low-quality fallback.
- `HUDController.luau`: pending hierarchy and transition treatment; avoid adding another permanent pill.

---

## 6. HUD density, contrast, and mobile readability

### Reference pattern

Competitor HUDs are dense because the genre has cash, premium currency, rebirth/prestige, vehicles, weapons, capture state, map destinations, and shop offers. Density only works when the player can tell **what is actionable now**. The best references keep the cash/identity anchor persistent and let other systems appear as contextual panels, markers, or chips.

### Current WAR EMPIRE strengths

`HUDController` already provides a top-left level/XP panel, bottom-left currency pill, pending label, passive hint, spinner chip, season slot, and a bottom-right mobile action dock. This is a good base for a dark, high-contrast military UI.

### Recommended hierarchy

| Rank | Always or contextually visible | Treatment |
|---|---|---|
| 1 | Cash + pending | Largest persistent currency treatment; gold/green contrast on dark panel |
| 2 | Current tutorial/objective | One short verb, distance/arrow, and progress state; hide when complete |
| 3 | Level/XP or prestige | Compact top-left card; never compete with the current verb |
| 4 | Nearby capture/collector/garage prompt | World-space marker and contextual mobile action |
| 5 | Gold, spinner, season, shop | Chips/dock entries; bright only when ready or explicitly opened |

### Contrast rules

- Background panels: near-black blue/green (`#121820` family) with 8–20% transparency; avoid translucent text over bright sand.
- Primary cash: warm gold/cream; pending: green; objective: blue/white; danger/locked: orange/red. Use icon + text, not color alone.
- Keep text sizes and touch targets within the existing `UIUtil` mobile scale and minimum touch rules. The dock can be dense, but each tile needs one verb and one icon.
- Use a dark scrim behind modal panels. Never let a world billboard, spinner, or season label visually outrank an active tutorial arrow.
- Maintain safe zones for Roblox top bar, thumb reach, and small aspect ratios. Validate at 16:9 desktop, tall phone, and narrow phone.
- Avoid flashing/neon everywhere. Reserve animation and saturation for state changes: affordable, pending, ready, contested, collected.

### File hints

- `HUDController.luau`: reorder hierarchy, add pending-to-cash transition, objective slot, and contextual prompts without expanding the permanent footprint.
- `UIUtil` and `Constants.Colors`: centralize contrast, stroke, corner, and minimum-touch decisions rather than hand-tuning each panel.
- Existing `pendingLabel` and `passiveLabel` should be one composed “income status” treatment, not two competing messages.

---

## 7. Map dressing and route readability

### What references do well

Military Tycoon’s desert/island language is effective because POIs are chunky and spaced: fortress walls, flags, oil rigs, roads, city structures, docks, and airfield/runway. War Tycoon adds garages, extractors, hangars, bunkers, and visible perimeter defenses. The map has enough dressing to feel like a war zone, but major gameplay anchors remain larger and cleaner than the filler.

Public video footage reinforces the value of visual landmarks: a runway/airfield is readable from approach, a small outpost has a simple flag/capture story, oil rigs are coastal silhouettes, and an urban bank/tower cluster gives the city a distinct destination. These are composition lessons only; WAR EMPIRE must keep its own POI identities.

### WAR EMPIRE today

`MapDressing.luau` already covers a useful desert vocabulary: checkpoints, outposts, hangars, fuel depots, ammo sheds, radio towers, camps, docks, ruined walls, sandbag lines, wire fences, vehicles, oil drums, crates, lights, adobe buildings, tents, runways, bunkers, signs, and a warzone fill. Low/Full quality and shadow suppression are important for mobile/performance.

### Dressing rules

1. **Landmark cadence:** every long route should pass a readable sign, light pole, ridge, checkpoint, camp, or silhouette. Do not place identical clusters at fixed intervals.
2. **POI hierarchy:** capture flag/zone and objective marker are always the cleanest visual. Filler must be darker, smaller, and less saturated.
3. **Approach composition:** show a POI’s hero silhouette from the likely road/compass approach. Rotate the tower, flag, runway, or gate toward the player path.
4. **Use negative space:** leave a clean 20–30 stud approach around flags, collectors, garage exits, and vehicle spawn pads. Clutter is visual collision.
5. **Material zoning:** base = concrete/metal/olive; desert settlement = sandstone/wood/fabric; coastal = dark blue/wood/rust; contested combat = sandbag/ruin/ammo orange. Keep neon for signals.
6. **Show the route, not every prop:** one sign at a junction plus one distant silhouette beats six unlabeled crates.
7. **Capture state should own the skyline:** a tall flag, banner, ring, beacon, or smoke column can advertise neutral/contested/friendly without adding HUD density.
8. **Quality tiers preserve composition:** Low removes duplicate clusters and shadows, not the one sign/flag/hero silhouette that makes a POI navigable.
9. **Roadside vehicle silhouettes are set dressing only:** never let a decorative vehicle be mistaken for an available spawn. Use a muted `DISPLAY` plate or a visible stand.

### File hints

- `MapDressing.luau`: create landmark families and approach rotations; tag only visual dressing, and preserve the stated “no gameplay tags” contract.
- `VisualAssetConfig.luau`: optional free prop overlays only after the Part-kit silhouette is readable.
- Map setup/POI modules: give each objective a `HeroColor`, `ApproachYaw`, `SilhouetteHeight`, and `MarkerAnchor` design field where practical.

---

## 8. Tutorial visual guidance

### The lesson from Military Tycoon

The early experience teaches with objects, not a lecture: choose identity, see the safe base, buy a worker, watch the worker shoot, touch the ATM, then expand toward weapons and capture. The world itself is the tutorial. War Tycoon similarly makes the first extractor, ATM-like collection, green buy buttons, and visible base rooms explain the loop.

### Recommended WAR EMPIRE presentation sequence

Keep the systems sequence aligned with Pass 1’s worker-first conclusion, but express every step through one world object and one dominant verb:

1. **Claim base:** camera/arrow lands on the plot, pad glows, `CLAIM BASE` appears once.
2. **Recruit / watch training:** point to a Training Yard soldier/target; show a short muzzle flash/beam and a `TRAINING` state. Do not require a deep Army menu to understand the beat.
3. **Collect:** camera/arrow points to the physical collector; its screen is green and the billboard says `TOUCH TO COLLECT`.
4. **Command Center:** pad and building share the same gold affordance; purchase flash reveals the HQ signature mast/door.
5. **Barracks:** point to the long barracks silhouette and its active yard; show a short “base grows” camera nudge.
6. **Walls/gate:** show the perimeter ring and gate as a defensive milestone. Keep the opening clear and route the arrow through it.
7. **Jeep/garage:** point to the showroom pad and exit, not a distant abstract menu. A display silhouette should explain ground vehicles before the player spawns one.
8. **Nearby outpost:** select a deliberately close neutral POI with a tall flag and clean route. The marker, flag, world beacon, and HUD objective should agree on one direction.

### Guidance visual contract

- **Available:** gold/green ring, soft breathing, one floating icon.
- **Selected/current:** blue-white beam or arrow, slightly faster pulse, short label.
- **Completed:** brief checkmark/ribbon and then fade; do not leave permanent clutter.
- **Locked:** muted grey with one explicit requirement; no red alarm unless it is a danger state.
- **Contested/danger:** orange/red edge pulse, warning icon, and a short sound; preserve objective legibility.
- **World-space labels:** short uppercase noun/verb, max two lines, distance-capped, never AlwaysOnTop for every prop.

### File hints

- `TutorialConfig.luau` / `TutorialService.luau`: event names and order can follow the worker-first recipe; this document does not change payouts.
- Tutorial client controller/marker setup: one arrow, one highlight, one prompt; remove prior marker when the step changes.
- `HUDController.luau`: mirror only the current objective and progress, not the whole tutorial script.
- Map setup: place a nearby training outpost/capture beacon per plot ring; do not force the first-time player to cross the full ~4800-stud map.

---

## 9. Buy and collect VFX language

### Buy feedback

The purchase should feel like construction, not a UI transaction:

1. Pad changes from affordable to selected on approach.
2. `BUY` panel confirms the object name and one-line result.
3. A short gold/blue construction sweep travels around the footprint.
4. Dust/steam/electric accent is brief and category-specific (dust for concrete, sparks for metal, canvas snap for tents, water glint for dock).
5. The silhouette fades or assembles in 0.25–0.5 seconds; avoid a long wait that blocks the player.
6. A small `BUILT` badge and sound confirm; the pad becomes a quiet owned marker.
7. If a free visual overlay loads later, it should ease in without replacing the authoritative Part-kit or moving the interaction point.

### Collect feedback

- **Pending tick:** tiny screen-digit change / soft glow, no world explosion every tick.
- **Approaching with pending:** collector ring has a slightly stronger pulse and the prompt becomes explicit.
- **Collect success:** screen count clears, green-to-gold flash, 3–6 small cash motes rise, `+$N` floats toward the HUD, short confirmation sound.
- **Empty collector:** no error spam; one muted “nothing ready” state if the player deliberately interacts.
- **AutoCollect:** periodically update the HUD/pending state and use a subtle remote spark at the collector, not a fake touch loop.
- **Low quality/mobile:** swap particles for a ring tween and icon pop; never remove the screen/digits or success confirmation.

### Consistency rules

- Use one easing family for buy/collect (`OutQuad` for movement, `OutBack` only for small icon pops).
- VFX duration should be under one second for common actions; capture/major unlocks may use a longer banner.
- VFX must originate at the object and finish at the relevant UI anchor so the player learns the relationship.
- Keep screen, sound, and color accessible: use shape/icon/text in addition to color.
- Never use explosions, camera shake, or full-screen flashes for routine cash collection.

### File hints

- Code Bot: `MoneyCollectorService.luau` and existing client remotes for server-authoritative success/state hooks; `StructureKitBuilder`/BaseService hook after successful purchase; keep all VFX cosmetic.
- Design Bot: `ReplicatedStorage`-side VFX modules/assets, screen states, particle/ring presets, sounds, and iconography.
- `HUDController.luau`: cash flight target, pending transition, and objective affordance.

---

## 10. Prioritized DESIGN backlog

This backlog is intentionally presentation-focused. **P0/P1/P2 are design priorities, not economy or vehicle-physics priorities.** Code Bot owns safe wiring and state hooks; Design Bot owns authored visual assets, motion, icons, typography, and composition. Do not edit `VehicleService.luau` for this document.

### P0 — make the first ten minutes visually self-explanatory

| ID | Owner | Deliverable / acceptance test | Concrete file hints |
|---|---|---|---|
| **P0-D1 Collector hero pass** | Design Bot + Code Bot | From spawn, the collector reads as a physical cash machine: grey/olive body, green `CollectorScreen`, WE mark, screen digits, `TOUCH TO COLLECT`, positive/empty/AutoCollect states. A new player can identify it without opening a menu. | `MoneyCollectorService.luau`, collector kit in MapSetup/base setup, `HUDController.luau`, `VisualAssetConfig.luau` only if a free prop overlay is used |
| **P0-D2 Pending/cash feedback** | Code Bot + Design Bot | Pending state is mirrored in the currency pill; collect produces a compact `+$N` flight/ring/digit/audio response; empty state is quiet; low-quality mode keeps the state readable. No payout rule changes. | `MoneyCollectorService.luau`, `HUDController.luau`, client VFX/notification controller, shared `Constants.Colors`/UI utilities |
| **P0-D3 Signature building silhouettes** | Design Bot | HQ, Barracks, VehicleDepot, DefensiveWalls, TrainingYard, and collector are distinct at 100–150 studs. L1 purchase visibly changes the skyline; L2/L3 add authored deltas, not arbitrary neon blocks. | `StructureKitBuilder.luau`, `StructureVisualConfig.luau`, base visual refresh path, optional `VisualAssetConfig.luau` overlays |
| **P0-D4 Worker/tutorial visual path** | Code Bot + Design Bot | First-time player sees a soldier/target training beat, then a clear collector route, then HQ/Barracks/wall/garage/outpost. One active arrow/highlight/verb per step; no distant first capture dead-end. | `TutorialConfig.luau`, `TutorialService.luau`, tutorial client controller, `HUDController.luau`, MapSetup near-outpost marker |
| **P0-D5 Buy-to-world ceremony** | Design Bot + Code Bot | Every first-page purchase has an affordable state, pad highlight, 0.25–0.5s build sweep, category-appropriate dust/spark, completion badge, and a new silhouette. The visual overlay never blocks the fallback kit. | `StructureKitBuilder.luau`, BaseService visual refresh hook, upgrade pad/buy controller, client VFX presets |

**P0 definition of done:** a 60-second capture/playback from a fresh profile shows: claim → training activity → collector digits → collect response → HQ/Barracks silhouette → wall/gate. No frame depends on a copied competitor asset, and no `VehicleService` changes are required.

### P1 — readable mid-game presentation and mobile hierarchy

| ID | Owner | Deliverable / acceptance test | Concrete file hints |
|---|---|---|---|
| **P1-D1 Garage showroom skin** | Design Bot + Code Bot | VehicleDepot has a real room/door/sign, display pad, owned/available/locked card hierarchy, preview camera, requirement copy, BUY → SPAWN state, obvious exit/despawn. Use a static display if the driveable vehicle is not ready. | `StructureKitBuilder.luau`, `VisualAssetConfig.luau`, garage UI/controller, `HUDController.luau`; no `VehicleService.luau` changes in this design pass |
| **P1-D2 Vehicle family art contract** | Design Bot | Jeep/truck, tracked, helicopter, jet, and naval silhouettes are recognizable and WE-original; each has facing, scale, category stripe, display plate, and safe Part-kit fallback. | `VisualAssetConfig.luau`, `StructureKitBuilder.luau`, vehicle preview assets |
| **P1-D3 HUD contrast and density pass** | Code Bot + Design Bot | Test desktop/tall phone/narrow phone. Cash/pending and current objective always win; spinner/season/shop are secondary; no overlap with Roblox inset or mobile action dock. | `HUDController.luau`, `UIUtil`, `Constants.Colors`, action dock/controller |
| **P1-D4 POI landmark composition** | Design Bot | Each outpost, fort, coastal oil approach, bank, dock, and airfield has one hero silhouette, one approach-facing marker, and a clear 20–30 stud objective zone. Filler never hides the flag/beacon. | `MapDressing.luau`, POI/map setup modules, `VisualAssetConfig.luau` optional overlays |
| **P1-D5 Capture/route state visuals** | Code Bot + Design Bot | Neutral/contested/friendly states use consistent flag/banner/ring/beacon motion; world marker, compass, and HUD objective share one color/state vocabulary. | capture client controller, `HUDController.luau`, MapSetup POI markers, shared color config |
| **P1-D6 Quality-tier composition** | Code Bot + Design Bot | Low quality removes duplicate dressing/particles/shadows but preserves collector, flag, signs, route lights, garage entrance, and hero silhouettes. | `MapDressing.luau`, `VisualAssetConfig.luau`, client VFX quality gate, DevConfig |

### P2 — spectacle and long-term authored identity

| ID | Owner | Deliverable / acceptance test | Concrete file hints |
|---|---|---|---|
| **P2-D1 Prestige room ceremonies** | Design Bot + Code Bot | Selected prestige milestones reveal a WE-original room/verb with door lighting, banner, preview stand, and before/after camera beat. Presentation only; progression rules remain in their own spec. | prestige UI/service hooks, `StructureKitBuilder.luau`, `VisualAssetConfig.luau`, `HUDController.luau` |
| **P2-D2 Weather/time/color grade** | Design Bot | Optional restrained sky, haze, dust, and night lighting distinguish base/coast/warzone while preserving contrast and mobile performance. | lighting/map presentation module, `MapDressing.luau`, shared palette config |
| **P2-D3 Dynamic worker/yard animation** | Code Bot + Design Bot | Worker kits or free character overlays animate target practice, muzzle flashes, target hits, and occasional idle beats without server-side visual spam. | TrainingYard setup, SoldierService cosmetic hooks, client VFX/animation controller, `VisualAssetConfig.luau` |
| **P2-D4 Collection/buy sound set** | Design Bot | Original short sound families for purchase, collector-ready, collect, capture, garage spawn, locked, and prestige unlock; settings/quality mute path verified. | sound asset registry, VFX/audio controller, `HUDController.luau` hooks |
| **P2-D5 Creator-readable showcase pass** | Design Bot | A screenshot/recording from spawn, garage, first capture, and full base communicates WAR EMPIRE identity in three seconds each; no competitor branding or copied composition. | curated map/camera spots, `MapDressing.luau`, structure/vehicle presentation assets |

---

## 11. Verification checklist (design-only)

### Fresh-player capture

- [ ] Spawn camera sees the plot’s HQ/collector/training silhouette.
- [ ] The active tutorial has exactly one dominant verb and one destination.
- [ ] The first training activity is visible without opening Army UI.
- [ ] Collector screen and billboard agree on `$pending` and state.
- [ ] Collect response reaches both the world object and HUD cash anchor.
- [ ] First HQ, Barracks, wall/gate, and garage buys produce visible silhouettes.
- [ ] First capture marker, flag, route sign, compass, and HUD objective point in the same direction.

### Presentation regression

- [ ] No free asset is required for basic building/vehicle/collector readability.
- [ ] `StudioSkipWorldDressing` still leaves the core plot silhouettes and objective markers usable.
- [ ] Low quality removes noise, not the collector screen, flag, route sign, or garage entrance.
- [ ] HUD is readable at desktop, tall phone, and narrow phone sizes.
- [ ] Locked cards say why they are locked; disabled buttons do not look like missing UI.
- [ ] Decorative vehicles are clearly labeled/display-only unless they are a real spawn.
- [ ] The design work does not edit `VehicleService.luau`, publish Roblox, or import competitor assets.

### Source notes

- [Military Tycoon Roblox listing](https://www.roblox.com/games/7180042682/Military-Tycoon) — public promise of base building, 100+ vehicles, army training, raids, fortresses/oil rigs/key locations.
- [Military Tycoon Base (Tycoon)](https://military-tycoon.fandom.com/wiki/Base_(Tycoon)) — public descriptions of main base, garage, dock, airfield, bunker, ATM, and expanding base structures. Fandom may block automated fetches; the page was used as a public search result reference.
- [Military Tycoon How to Play](https://military-tycoon.fandom.com/wiki/How_to_Play) — worker, capture, loot crate, operations, and progression themes.
- [Military Tycoon public gameplay update video](https://www.youtube.com/watch?v=bXloRY5rzsI) — visible/declared themes of outposts, flag color change, airfield/runway, oil rig, city POIs, control panel, and NPC vehicles; update-specific observations only.
- [War Tycoon Base](https://war-tycoon-roblox.fandom.com/wiki/Base) — public descriptions of base sections, walls, docks, hangars, bunkers, and visible unlock structure.
- [War Tycoon Oil Extractors](https://war-tycoon-roblox.fandom.com/wiki/Oil_Extractors) — physical producer/collector presentation pattern.
- [War Tycoon Vehicle Bay](https://war-tycoon-roblox.fandom.com/wiki/Vehicle_Bay) and [Tank Garage](https://war-tycoon-roblox.fandom.com/wiki/Tank_Garage) — showroom/room UX patterns; public pages may be access restricted.
- [War Tycoon controls guide](https://noleep.com/en/war-tycoon-control-guide-tips-for-pc-and-mobile/) — interaction, mobile controls, vehicles, and map/collectable discoverability.

*End of design deep dive. Update after an in-Studio fresh-profile capture and mobile screenshot pass.*
