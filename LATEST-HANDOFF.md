## v246 PUBLISHED (Code Bot Roblox, 2026-10-02 20:46 Dublin): Open Cloud place version **244**. Cherry-pick Claude JOB 75 + JOB 76

**COMPLETED**
- **JOB 75 Scout Helicopter flight** (`VehicleConfig.HeliFlight`, OwnerFirst=true for Shaun + Laumartinez26 `11718087109`): centre-of-mass drive for Heli/Plane (server on seat change + client refresh); camera-relative touch stick; smaller tilts; real SPD; gentle landing; ground skid; righting. OFF for everyone else = old flight. Files: VehicleConfig, VehicleService, VehicleDriveClient; checks/sim `claude_bud_job75` / `run_heli_flight_test`.
- **JOB 76 ADMIN ABUSE WARLORD finish** (verify + finish v242; public effect on already-public Warlord): HP = max(MinHealth=30000, BaseHealth=0 + HealthPerPlayer=5000 × players); heavy weapon Damage=20 FireRate=1.5 Range=110 AggroRange=140 XPReward=500; NPC CashReward=0; `WorldBossService.StopTest()`; `AdminAbuseService.StopAll` calls it. **Kept live v243–v245**: PlazaSpots / MaxGroundY 8 / Leash 110 / AutoEverySeconds 1200 / PinLabel WARLORD + MegaTank EventVehicles.
- WE_Build **246**. PreferMesh OFF. No WE_Building* touch. Publish **without** forced restart (players get it on next join / Shaun migrates).

**PHONE TEST (Shaun / Lau — NEW server after migrate or fresh join)**
1. **Heli (owner-first)**: enter a Scout Helicopter on phone — hover should stay level (not nose-down), SPD shows real speed, stick flies camera-relative, ▲/▼ height, gentle land. Non-owner players still get the old flight until OwnerFirst flipped.
2. **Warlord**: Admin Abuse → GIANT BOSS — Plaza spawn, HP ~30k (1p) / ~50k (10p), heavy gun, chaos banner, 500K + Boss Slayer to helpers. STOP ALL clears Warlord **and** WORLD BOSS TEST (not the live DW window bosses). Auto WARLORD every 20 min in the Double Weekend window still runs.

**TESTING**: BuyPathStatic PASS=10029 FAIL=0; claude_bud_job75/76 all PASS; codebot_v246 13/13 PASS; heli/warlord/admin_abuse sims 0 failed. codeCommit=`063b2c3` place=244 build=246

---

## v245 — Code Bot (2 Oct 2026 20:24 IST) — place version 243, code 6c5a259

- **DOUBLE WEEKEND auto WARLORD**: `AdminAbuseConfig.Actions.Boss.AutoEverySeconds = 1200`. AdminAbuseService.Init starts one task.wait loop (`autoBossLoop`): slots = EventConfig.StartUnix + k x 1200 until EndUnix (21:00, 21:20, ... Dublin; 144 slots, last Sun 20:40); a slot is due for 60 s (`DueAutoBossSlot`), `AutoBoss()` runs `start.Boss` on THIS server only (never MessagingService), sets the 300 s running timer (despawn), no LIVE chip / cooldown; skipped while a boss lives or the server is empty. Same Plaza spot, chaos banner, 500K world_boss, Boss Slayer badge. A server started mid-window waits for the next slot.
- BuyPathStatic PASS=9998 FAIL=0. Slot math simulated in Luau (144 spawns, wake-late safe). Not tested in-game. No restart.

## v244 — Code Bot (2 Oct 2026 20:20 IST) — place version 242, code 4f56f8a

Shaun phone test 20:03 (his server was pre-v242: 'GIANT BOSS WAIT 3:36' = the old cooldown; v242+ has Cooldown 0 server-side and ButtonText returns the bare label for Boss).
- **Boss invisible**: the bosses used the animated R6 rig, scaled after SpawnNPC parented them; client RigAnimator caches limb mesh scales at add() and writes them back on near/far swaps, and a rig attached after its template loads lands 1x on the 4x root (normal-size soldier inside a transparent giant root). SpawnNPC could also refuse it at the NPC cap silently. Fix: `Modules/BossLook.luau` (Part kit NoVisual, ScaleTo, PivotTo onto the ground, Highlight DepthMode AlwaysOnTop, PointLight, name plate MaxDistance 1500), `opts.Boss` skips the NPC cap, WARLORD pin refreshes every 1 s. Same for the Double Weekend bosses.
- **Airstrike invisible**: CombatFx.Explode = weapon-sized puff on the unreliable WeaponFx lane, one strike near one random player. Fix: FeaturePush `AdminAbuseStrike` {P,W,R} to all within VisibleStuds 600; AdminAbuseController draws red circle (WarnSeconds 1.6), falling lit missile, local visual Explosion (pressure 0, no joint breaks) + fireball + light + CameraFx.Blast; each wave hits near up to PerWave 8 players; damage lands with the missile (STOP ALL cancels). Announce banner on start.
- **Crates**: the trigger was a fixed 5-stud box inside the crate's solid J67Hull → no Touched. Now wraps the crate bounds +4, 4 Hz server walk-up check (GrabStuds 4), pcall'd AddCash (un-claimed on refusal), "already grabbed" note, crate hidden for the grabber (FeaturePush `AdminAbuseCrateTaken`).
- **"Defeat the defenders first!"**: OutpostDefenders.Blocking counted every living neutral guard incl. unreachable ones (roof / past leash / under map); holder only spared via PlazaDefenders. Now only reachable guards block (ReachMarginStuds 15 / ReachYStuds 30; unreachable despawned), note says "(N left)", the territory's holder is never blocked.
- Guard check updates: codebot_v241 accepts BossLook scaling; sim mock AddCash returns (true, n) like the real one. BuyPathStatic PASS=9989 FAIL=0. Not tested in-game. No restart.

## v243 — Code Bot (2 Oct 2026 19:48 IST) — place version 241, code 85634f3

- **FREE MEGA TANK** (Admin Abuse TankDrop): `VehicleConfig.EventVehicles.MegaTank` (TrackedMBT kit Scale 1.45, ~1.5x the 0.95 Light Tank; never in Vehicles = no shop / garage / save; VehicleService getDef falls back). Wears the real Synty tank `SM_Veh_Tank_USA_01` (pack 119390702773907, Fit Kit) via VisualAssetConfig (lines tagged `-- v243`; codebot_v211 / v219 PreferMesh guards now skip `-- v243` lines like `-- v230`). FIRE button = `MegaTankMissile` on the existing AirWeapon missile path (220 dmg, splash 10, 4-mag / 6 s reload, 25° arc around the hull nose, muzzle = kit Barrel). 600 s loan. Ordnance caps unchanged.
- **WARLORD at the Central Plaza**: `AdminAbuseConfig.Actions.Boss.PlazaSpots` / MaxGroundY 8 / Leash 110; `AdminAbuseService.PlazaSpot()` ground-ray (never a building / roof / StructureId); fallback (0,1,0). Banner + pin point there. Empty servers skip.
- **Every army fights the bosses**: both boss kinds carry model attribute `WE_Boss`. `CombatService.unitMayHit` returns true for a WE_Boss (no UnitProvokeNeedsOwner owner-near rule — that was why only the owner's army engaged); `escortPickLive` treats a WE_Boss within `ArmyConfig.Escort.BossEngageStuds` (110) as a defend target for every player; hurtNPC stamps the army owner on a WE_Boss's LastHitBy, so army damage pays the 500K + Boss Slayer badge (WorldBossService.PayHelpers and the Admin Abuse boss death both read LastHitBy). BuyPathStatic army A0 / army-fix structural checks updated to the new lines.
- BuyPathStatic PASS=9972 FAIL=0; admin abuse sim 0 failed. Not tested in-game. Old servers need migrating (Shaun does it).

## v242 PUBLISHED (Code Bot Roblox, 2026-10-02 19:32 Dublin): Open Cloud place version **240**. BOSS SLAYER badge + ADMIN ABUSE WARLORD = world-boss deal

- **Badge** `1033687066360587` (Boss Slayer): `WorldBossConfig.BossBadgeId` (DW world bosses) and `AdminAbuseConfig.Actions.Boss.BadgeId` (WARLORD). BadgeService in pcall, UserHasBadgeAsync first (skip if owned), every helper.
- **ADMIN ABUSE WARLORD** (`AdminAbuseConfig.Actions.Boss`): Scale 3 -> **4**; HP 4,000 + 1,500/player -> **25,000 + 5,000/player** (1 player 30k, 5 -> 50k, 10 -> 75k); reward $25,000 supply_drop -> **$500,000 flat, reason world_boss** (NEVER_MULTIPLIED, never 2x) to every player who hit it; **Cooldown 300 -> 0** and the panel shows no countdown on GIANT BOSS (a new press replaces the live Warlord on each server); lifetime still 300 s.
- **Announcement** (config `AnnounceText`): "⚠️ THE ADMIN IS HERE AND HE'S CAUSING CHAOS! A WARLORD has spawned. Help take him down for 500K CASH + BOSS SLAYER BADGE!" to every player on each server (FeaturePush "WorldBoss", big banner 9 s, TAP TO TRACK = pin); death banner too. AA boss bar is a button (tap = pin, `WE_AABossPos` follows him while fought). DW world-boss spawn banner also tap = pin now.
- **Every server**: GIANT BOSS is a normal published action (MessagingService topic WE_AdminAbuse): each server spawns its OWN Warlord near one of its players, its own banner, pays its own helpers. STOP ALL is published too and clears them everywhere. (WORLD BOSS TEST stays this-server-only.) Servers still on v240/v241 receive the press but run their old Warlord code (v240/241: 3x, ~10k HP, $25k, no banner, 300 s cooldown).
- Note: comment wording in WorldBossConfig no longer says "WE_Building" (codebot_v151-154/v209 diff guards).

**TESTING**: BuyPathStatic PASS=9954 FAIL=0; run_admin_abuse_test 0 failed; codebot_v242 13/13 PASS. WE_Build 242, **no restart**. Public servers at publish: 6 / 29 players, all pre-v241.

codeCommit=`b483e69` place=240 build=242

---

## v241 PUBLISHED (Code Bot Roblox, 2026-10-02 19:19 Dublin): Open Cloud place version **239**. DOUBLE WEEKEND WORLD BOSSES (Shaun: "at 9pm when the 2x goes live can we spawn bosses around the servers")

**NEW**: `WorldBossConfig` (the one config) + `Server/Services/WorldBossService` + `Client/Controllers/WorldBossController`.
- **When**: only inside `EventConfig` StartUnix..EndUnix (Fri 2 Oct 21:00 → Sun 4 Oct 21:00 Dublin); no time of its own. Each server: `task.delay` to the start (or 4 s after boot inside the window), despawn at the end. No per-frame loop.
- **Boss**: giant **WARLORD** = CombatService NPC `HeavyInfantry` (the real soldier rig + shared NPC brain) scaled x3 (same as the ADMIN ABUSE giant boss), 20 dmg x 1.5/s, range 110, aggro 140, leash 90. HP = 15,000 + 2,000 x players on server (cap 45,000).
- **Spots (1 alive each, 10 min respawn after kill)**: Camp Viper (-470,-600), Anvil Scrapyard (1230,470), Dry Well Village (470,700); >=175 studs from every plot pad, >=420 from captures, far from the spawn town (codebot_v241 proves it).
- **Reward**: exactly **$500,000 to EVERY player who hit him** (his own shots, rec.LastHitBy; squad-unit-only hits don't count), reason `world_boss` (EconomyService NEVER_MULTIPLIED: never 2x). NPC kill cash 0; killer gets 500 XP. **Badge**: `WorldBossConfig.BadgeId = 0` (skipped) — set it when Shaun sends the id.
- **Client**: How-to-play card first time a boss is live per session (what / 3 steps / "REWARD: 500K CASH + BADGE for everyone who helps", TRACK BOSS / GOT IT); boss bar for the nearest boss at y=94 (tap = ObjectiveMarker pin, no teleport); banner on spawn/death via FeaturePush "WorldBoss".
- **Owner preview**: `/boss` in chat (Shaun via AdminConfig.IsPlaytestOwner, Laumartinez26 11718087109) or ADMIN ABUSE panel **WORLD BOSS TEST** (LocalOnly: this server only, never MessagingService). `/boss clear` removes them. Preview bosses pay like real ones and keep respawning on that server until `/boss clear` or a new server.
- AdminAbuse layout sim updated to 12 controls.

**TESTING**: BuyPathStatic PASS=9941 FAIL=0; codebot_v241 all PASS; rojo build OK. WE_Build 241, **no restart**. At publish: 6 public servers / 32 players, all started before the publish -> they run v240 and will NOT spawn bosses at 21:00 unless they close / are migrated.

codeCommit=`cfee53f` place=239 build=241

---

## v240 PUBLISHED (Code Bot Roblox, 2026-10-02 18:59 Dublin): Open Cloud place version **238**. Plaza defender tanks toned down further (Shaun, after v239)

**CONFIG ONLY** (`PlazaDefenderConfig`): `VehicleDamageMult` 0.75 → **0.4**, `VehicleFireRate` 0.65 → **0.45**/s, `VehicleHealthMult` 2.5 → **1.75**. Range 95 / aggro 120, soldiers, caps 6 + 2, tax unchanged; still public.

| Tank (tier) | HP v239 → v240 | dmg/shot | shots/s | raw DPS | hits to kill 100 HP |
|---|---|---|---|---|---|
| Power 160+ | 1,000 → 700 | 23 → 12 | 0.65 → 0.45 | 15 → 5.4 | 5 → 9 |
| Power 100-159 | 850 → 595 | 20 → 11 | 0.65 → 0.45 | 13 → 4.9 | 5 → 10 |
| Power 50-99 | 700 → 490 | 18 → 10 | 0.65 → 0.45 | 12 → 4.5 | 6 → 10 |
(v236 original top tier: 1,200 HP / 45 dmg / 1.0/s / 45 DPS / 3 hits.)

**TESTING**: BuyPathStatic PASS=9920 FAIL=0; plaza sim 0 failed; codebot_v240 all PASS (codebot_v239 top-tier floor loosened to >= 500 HP / 8-30 dmg). WE_Build 240, no restart.

**PHONE TEST (NEW server):** 1) Shaun holds with tanks; Lau attacks: a tank takes ~9 hits (~20 s alone) to kill her. 2) Lau + rifle + a few soldiers kill a 700 HP tank in ~5 s.

codeCommit=`1e14cd5` place=238 build=240

---

## v239 PUBLISHED (Code Bot Roblox, 2026-10-02 18:56 Dublin): Open Cloud place version **237**. Plaza defender TANK nerf (Shaun phone test: "a little too powerful")

**CONFIG ONLY** (`PlazaDefenderConfig`): `VehicleDamageMult` 1.5 → **0.75** (−50 %/shot), `VehicleFireRate` 1.0 → **0.65**/s (−35 %), `VehicleHealthMult` 3 → **2.5**. Range 95 / aggro 120 unchanged (gunner = CombatConfig OilRigGuard 200 HP / 20 dmg). Soldiers, caps (6 + 2), tax unchanged; still public.

| Tank (tier) | HP before → after | dmg/shot before → after | shots/s | raw DPS |
|---|---|---|---|---|
| Power 160+ (x2 HP, x1.5 dmg) | 1,200 → 1,000 | 45 → 23 | 1.0 → 0.65 | 45 → 15 |
| Power 100-159 (x1.7, x1.35) | 1,020 → 850 | 41 → 20 | 1.0 → 0.65 | 41 → 13 |
| Power 50-99 (x1.4, x1.2) | 840 → 700 | 36 → 18 | 1.0 → 0.65 | 36 → 12 |
NPC hit chance 75 % ≤ 20 studs → 30 % at 95. Player 100 HP: 3 tank hits before, 5-6 now. Compare: top-tier defender soldier 300 HP / 18 dmg / 2.2/s (~40 DPS); Assault Rifle 22 × 9/s (198 DPS); a squad soldier 150 HP / 12 dmg / 2.2/s.

**TESTING**: BuyPathStatic PASS=9913 FAIL=0; plaza sim 0 failed; codebot_v239 all PASS. WE_Build 239, no restart.

**PHONE TEST (NEW server):** 1) Shaun holds the Plaza with tanks; Lau (or a mid-level account + a few soldiers) attacks: tanks hurt but take ~5 hits to kill her. 2) She can kill a tank with a rifle + squad in roughly 8-10 s of focused fire.

codeCommit=`1df5db7` place=237 build=239

---

## v238 PUBLISHED (Code Bot Roblox, 2026-10-02 ~18:55 Dublin): Open Cloud place version **236**. JOB 74 is PUBLIC (Shaun: "turn on for everyone")

**CHANGE**: `PlazaDefenderConfig.OwnerFirst` true → **false**. This is the one gate (`LiveFor` / `TaxLiveFor`), used by `PlazaDefenders.Step` (defenders + tax holder attribute) and `EconomyService.plazaTax`. Now every PLAYER holder of the Central Plaza gets:
- defenders (v235/v236): his army-look soldiers + up to 2 real Synty tanks he owns. Caps unchanged at 6 soldiers + 2 tanks, redeploy 90 s, despawn on loss/leave.
- the 10% PLAZA TAX on other players' passive income (only passive; never Robux/offline; never the holder, his clan allies, novice-shielded players, or with PvP off).
- the v237 chip + Central Plaza Tax info card (payer and holder).
Unchanged: neutral guards / normal capture (OutpostDefenders: asleep while held, back 150 s after unheld). Clan holds have no Holder UserId, so no defenders or tax (same as before). Tester list kept, so flipping back to true restores owner-only.

**PERF**: no new loops (server 2 s step, client chip 1 Hz only while showing). Tax is a few table ops per passive tick. Sim proves 20 takeovers in a row never leave more than 6+2 alive.

**FILES**: PlazaDefenderConfig.luau; checks codebot_v235/v236/v237 + claude_bud_job74 J74-01 now assert the gate line `OwnerFirst = false`; sim tests public holder (Rando) defenders/tax/loss, gate-when-flipped-back, 20-takeover cap; tools/checks/codebot_v238.py; WE_Build pins → 238.

**TESTING**: BuyPathStatic PASS=9900 FAIL=0; plaza sim 0 failed; codebot_v238 all PASS.

**PHONE TEST (NEW server, no restart):** 1) a non-tester account (or Lau) captures the Plaza → their soldiers deploy, others see PLAZA TAX 10% / → name chip. 2) Someone else kills them and captures → old defenders vanish, new holder's deploy; leave it empty → red neutral guards return ~2.5 min later.

codeCommit=`ac8378f` place=236 build=238

---

## v237 PUBLISHED (Code Bot Roblox, 2026-10-02 ~18:55 Dublin): Open Cloud place version **235**. Plaza tax chip says WHY + tap info card (owner-first kept)

**WHY**: Shaun's phone test — Lau's chip read "TAXED 10% BY Shaun birrell" with no reason.
**WHERE THE CHIP IS MADE (proven)**: `Client/Controllers/PlazaTaxController.luau` `ensureGui()` → ScreenGui `WE_PlazaTaxChip` > `Chip`; texts from `PlazaDefenderConfig.Tax`; placed by `PlazaTaxController.Rect` under RivalConfig.Layout's TARGETS pill, one row below every visible `WE_DoubleWeekend` / `WE_AdminAbuseChip` event chip. Bootstrap wires it (`safeInit("PlazaTaxController"`).

**CHANGE**
- Chip is now a 48 px, 3-line TextButton (fits the 142 px TARGETS column on an 800 px phone, no truncated name): payer `PLAZA TAX 10%` / `→ <holder>` / `TAP FOR INFO` (red edge). Holder: `PLAZA TAX +$X/s` / `10% from N players` / `TAP FOR INFO` (gold edge; N = players whose WE_PlazaTaxedBy is him). % always from `Tax.Rate`.
- Tap → "Central Plaza Tax" card (HudLayout panel `PlazaTaxInfo`, one panel at a time, raises Modal; tap outside or big red CLOSE closes): payer body "<holder> controls the Central Plaza, so 10% of your passive income goes to them. Capture the Plaza to stop paying and collect tax from everyone else." + blue **SHOW ME THE PLAZA** = the world map's manual pin (`ObjectiveMarker.ShowWith{Pin=true}`, label PLAZA, at TerritoryConfig CentralPlaza, arrives at 40 studs). No teleport. Holder body: "You control the Central Plaza, so you collect 10% of every other player's passive income (N paying now). Keep holding the Plaza to keep earning." (CLOSE only).
- Server unchanged. OwnerFirst still true (Shaun + Laumartinez26). PreferMesh OFF, StreamingEnabled untouched, no WE_Building*, no prices.

**FILES**: PlazaTaxController.luau, PlazaDefenderConfig.luau (Tax texts), tools/sim/run_plaza_defenders_test.py (+ card texts), tools/checks/claude_bud_job74.py (J74-14 text), tools/checks/codebot_v237.py, WE_Build pins → 237.

**TESTING**: BuyPathStatic PASS=9886 FAIL=0; codebot_v237 all PASS; plaza sim 0 failed; J74-14/16 PASS.

**PHONE TEST (Shaun + Laumartinez26, NEW server — no restart):**
1. Shaun captures the Plaza. Lau's chip (under TARGETS / 2x WEEKEND) reads PLAZA TAX 10% / → Shaun's name / TAP FOR INFO; Shaun's reads PLAZA TAX +$X/s / 10% from 1 player.
2. Lau taps the chip → card explains the tax; SHOW ME THE PLAZA closes it and a PLAZA pin + line appears; CLOSE / tap outside closes.

codeCommit=`98dbc91` budMerge=`9396f82` place=235 build=237

---

## v236 PUBLISHED (Code Bot Roblox, 2026-10-02 18:12 Dublin): Open Cloud place version **234**. JOB 74 Plaza defender fixes after Shaun's 17:54 phone test (owner-first kept)

**ROOT CAUSES (proven from code)**
1. Black block tank: `PlazaDefenders.BuildArmour` used `VehicleService._BuildVehicleModel` (procedural Part kit; every tank body in VisualAssetConfig is ModelAssetId 0), anchored as a dark box with an OilRigGuard gunner on top. → Now a REAL tank from Shaun's owned, audited Synty Polygon Military Vehicles pack (119390702773907, `Job67DressConfig.Packs.Synty`, 0 scripts) via new `Job67DressService.PackModel`; `PlazaDefenders.MountTank` makes the tank part of a Static CombatService NPC (invisible `TankHull` collider), so it shoots with the normal server NPC AI (VehicleFireRate 1.0, damage x1.5, HP x3). Map in `PlazaDefenderConfig.ArmourModels`.
2. "Red guards respawn while I hold it": those were Shaun's OWN defenders — Infantry/HeavyInfantry/FortGuard NPC types with the hostile red kit colour (RigBuilder tints from it), redeploying every 90s. Real neutral guards already sleep while `Held`; v236 also never wakes them while `PlazaDefenders.HasHolder`.
3. Not his army: defenders now use `SquadOrdersService.ArmyDefenderLook` (Squad rig 7703684779, `OrdersConfig.UnitColor`, Elite dress + beret, StrongerArmy × research × elite stats; side-effect free) via new SpawnNPC opts `VisualKind`/`KitColor`/`NoVisual`. Named "<Name>'s Soldier" / "<Name>'s Tank".
4. Holder told "Defeat the defenders first!": `TerritoryService.playersInZone` noted EVERY player in the zone while defenders stood. Now holder/allies are kept (`OutpostDefenders.FriendlyTo` → `PlazaDefenders.FriendlyTo`), only others are blocked/noted. Cap was already 6 soldiers + 2 armour; the camo crowd in the screenshot was his army squad.

**FILES**: CombatService/init.luau, SquadOrdersService.luau, Job67DressService.luau, Modules/PlazaDefenders.luau, Modules/OutpostDefenders.luau, TerritoryService/init.luau, PlazaDefenderConfig.luau, tools/checks/claude_bud_job74.py (J74-03), tools/sim/run_plaza_defenders_test.py, tools/checks/codebot_v236.py, WE_Build pins → 236.

**TESTING**: BuyPathStatic PASS=9868 FAIL=0; codebot_v236 32 PASS; claude_bud_job74 J74-01..17 PASS; plaza sim 0 failed.

**PHONE TEST (Shaun + Laumartinez26, NEW server — no restart):**
1. Shaun captures the Plaza → up to 6 soldiers in his camo army look + up to 2 Synty tanks (if he owns tanks), no red guards. Shaun gets NO "Defeat the defenders first!".
2. Laura walks in → soldiers and tanks shoot her; she is blocked until all are dead.
3. Kill them all → they redeploy ~90s later while Shaun holds. Red neutral guards never appear while he holds.
4. Shaun leaves / loses it → defenders gone; neutral guards back ~150s after it is unheld.
Notes: tanks are static (face outward, turret doesn't rotate); first deploy may pause briefly while the Synty pack loads.

codeCommit=`e8f5086` place=234 build=236

---

## v235 PUBLISHED (Code Bot Roblox, 2026-10-02 17:22 Dublin): Open Cloud place version **233**. JOB 74 Central Plaza DEFENDERS + PLAZA TAX (owner-first)

**COMPLETED**
- Cherry-picked Claude `b8b22dd` (JOB 74) onto `phase-7-polish`; WE_Build **235**; published place version **233** (HTTP 200). No server restart.
- Owner-first only: `PlazaDefenderConfig.OwnerFirst=true` for Shaun (`AdminConfig.IsPlaytestOwner`) + Laumartinez26 (11718087109). Everyone else unchanged.
- A) PlazaDefenders (driven by OutpostDefenders' existing 2s step): holder roster from POWER, ≤6 soldiers + ≤2 crewed armour (owned only), CombatService TargetFilter + HitFilter, blocks capture while alive, redeploy 90s, despawn on loss/leave, neutral guards back after 150s, billboard + toast.
- B) PLAZA TAX: 10% of other players' *passive* income to holder's ATM as never-multiplied `plaza_tax`. Skips holder/allies/novice/PvP-off/non-tester holder. Client chips under TARGETS.
- PreferMesh OFF; WE_Building* untouched; no price/Id/save-key changes. Deferred JOB64/62/DW-proof still unmerged.

**FILES**
- `src/ReplicatedStorage/Shared/Configs/PlazaDefenderConfig.luau` (new)
- `src/ServerScriptService/Server/Modules/PlazaDefenders.luau` (new)
- `src/ServerScriptService/Server/Modules/OutpostDefenders.luau` (hook)
- `src/ServerScriptService/Server/Services/CombatService/init.luau` (HitFilter)
- `src/ServerScriptService/Server/Services/EconomyService.luau` (plaza_tax)
- `src/ServerScriptService/Server/Services/TerritoryService/init.luau` (Holder pass)
- `src/StarterPlayer/.../Client/Controllers/PlazaTaxController.luau` (new) + Bootstrap wire
- `tools/checks/claude_bud_job74.py`, `tools/sim/run_plaza_defenders_test.py`, `tools/checks/codebot_v235.py`
- WE_Build pins: BaseService / DataService / EarlyRemotes → 235

**TESTING**
- `claude_bud_job74.py` J74-01..17 PASS (with LUAU_COMPILE)
- `run_plaza_defenders_test.py` 0 failed
- `BuyPathStatic` PASS=9836 FAIL=0
- `codebot_v235.py` all PASS

**PHONE TEST (Shaun + Laumartinez26, 2 phones, same server — rejoin for v235):**
1. Shaun captures Central Plaza → toast "Your troops are defending the Plaza"; within ~2s defenders (+ armour if owned) + "Defended by … · Lv X" billboard.
2. Laura walks in → defenders shoot her; capture blocked ("Defeat the defenders first!") until all dead. Shaun cannot hurt his own defenders.
3. Kill them all → capture opens; they redeploy ~90s later if Shaun still holds.
4. Laura takes Plaza (or Plaza Airstrike) → Shaun's defenders vanish; hers deploy.
5. Tax: while Shaun holds, Laura sees "TAXED 10% BY … · take the Plaza!"; Shaun sees "PLAZA TAX +$X/s"; ATM grows by 10% of her passive. Dev-product / offline never taxed.
6. Shaun leaves → defenders + chips gone; neutral guards back ~2.5 min later.

**NEXT**
- Keep OwnerFirst until Shaun OKs public. JOB 73 map redesign still on hold. JOB 72 Admin Abuse extras parked on `wip/job72-admin-extras`. Deferred: JOB64 (Creator Hub), JOB62 (WE_NOTIFY_KEY), DW-proof (needs JOB64).

codeCommit=`d80d20f` cherry=`e2d9986`/`b8b22dd` place=233 build=235

---

## v234 PUBLISHED (Code Bot Roblox, 2026-10-02 16:18 Dublin): Open Cloud place version **232**. ADMIN ABUSE PROMO HIDDEN UNTIL SUN 4 OCT 21:00 DUBLIN
- **Source:** Code Bot `eeef33b` on phase-7-polish; bud merge `69bc2f9` + CLAUDE.md note `ed07e73`. WE_Build **234**. PreferMesh OFF; StreamingEnabled OFF; `WE_Building*` untouched; no price / Id change. Servers NOT restarted (new servers get it).
- **WHAT (Shaun 16:13: "dont promote a pop up banner or anything for the admin abuse event until this event finishes on sunday night"):** `AdminAbuseConfig.PromoStartsAtUtc = 1791144000` (2026-10-04T20:00:00Z = Sun 21:00 Dublin, the DOUBLE WEEKEND end) + `AdminAbuseConfig.PromoOpen(now)`. `DoubleWeekendController.promoHidden(cfg, t)`: for a config with PromoStartsAtUtc (only Admin Abuse) `refresh` hides the chip (countdown AND LIVE), closes any card, and returns BEFORE `popupTick` (pop-up never shown, never marked seen); chip tap ignored. The 1 s loop keeps running, so the chip + one-time RSVP pop-up appear on their own at 21:00 Sun with no publish. `DoubleEvent` ignores `RequestEventPopupSeen` for a config whose promo is not open. EventConfig (DOUBLE WEEKEND) has no PromoStartsAtUtc: unchanged. Owner panel (AdminConfig) unchanged; an owner-pressed ANNOUNCE / action still shows its own effect on every server (that is the owner's choice), but no LIVE chip before Sun 21:00.
- **OLD SERVERS:** players on servers started before this publish keep build 233's ADMIN ABUSE chip + pop-up (and the pop-up gets marked seen there) until they rejoin a new server. Not restarted per Shaun.
- **FILES:** `AdminAbuseConfig.luau`, `DoubleWeekendController.luau`, `DoubleEvent.luau`, `tools/checks/codebot_v234.py`, WE_Build pins 233 → 234, `dist/WarEmpire-PERF.rbxlx` (= `dist/WarEmpire.rbxlx`). Bud `CLAUDE.md`: do not re-enable promo early.
- **TESTING:** BuyPathStatic **PASS=9797 FAIL=0**; codebot_v234 17/17 PASS; codebot_v233 all PASS; admin abuse sims 0 failed; event_double_weekend_verify TOTAL FAIL=0.
- **Publish:** HTTP 200, versionNumber **232**, universe 10767159222 / place 97112936860418. **Servers NOT restarted**.
- **NEXT:** JOB64 / JOB62 / DW-proof still held on bud. JOB 72 extras: any player-facing promo must respect `AdminAbuseConfig.PromoOpen`.

## v233 PUBLISHED (Code Bot Roblox, 2026-10-02 15:56 Dublin): Open Cloud place version **231**. JOB 71 ADMIN ABUSE live event (owner panel + public chip/popup)
- **Source:** Cherry-pick Claude `6c92430` onto phase-7-polish as `d9dde7b` (conflicts resolved: Bootstrap took AdminAbuseService only — ReferralService / JOB 64 held; codebot_v211 keep SupplyDropConfig + DoubleWeekendController exceptions, not EngagementService; job61_pins stayed deleted on live). Code Bot `15ece70` WE_Build **233** + `codebot_v233.py`. PreferMesh OFF; StreamingEnabled OFF; `WE_Building*` untouched; no price / Id change. Servers NOT restarted (new servers get it).
- **WHAT:** ADMIN ABUSE live event Sat 10 Oct 2026 20:00–20:30 Dublin (`StartUnix` 1791658800 → `EndUnix` 1791660600). `AdminAbuseConfig` (EventId string `9167160688932684354`, Topic `WE_AdminAbuse`, OwnerFirst=false for public chip/popup). `AdminAbuseService`: RequestAdminAbuse gated on the SERVER by `AdminConfig.IsPlaytestOwner` (+ RemoteGate + rate limit + cooldown); ANNOUNCE filtered for broadcast; one MessagingService topic publishes `{action, args, sentAt, nonce}` (< 900 B); every server applies (nonce once, > 30 s ignored; failed publish applies locally). Actions: CASH RAIN, AIRSTRIKE STORM (visual only, MinHealth 1, no building damage), FREE TANK (loan via SpawnEventVehicle, never saved), 2x CASH (max with Double Weekend, earned only), LOW GRAVITY, SPEED FOR ALL, GIANT BOSS, ANNOUNCE, STOP ALL. Client `AdminAbuseController`: owner panel (Settings > ADMIN), public announce banner + boss bar. `DoubleWeekendController` multi-event chip/details/RSVP for ADMIN ABUSE.
- **GATE:** Owner panel = AdminConfig forever (no public flag). Public chip / pop-up = OwnerFirst=false as Claude shipped.
- **FILES:** `AdminAbuseConfig.luau`, `AdminAbuseService.luau`, `AdminAbuseController.luau`, `DoubleEvent.luau`, `DoubleWeekendController.luau`, `SettingsController.luau`, `EconomyService.luau`, `VehicleService.luau`, Bootstrap/RemoteSetup/Constants/SecurityConfig, `tools/checks/claude_bud_job71.py`, `tools/checks/codebot_v233.py`, sims `run_admin_abuse_test.py` / `run_admin_abuse_layout_test.py`, WE_Build pins 232 → 233, `dist/WarEmpire-PERF.rbxlx` (= `dist/WarEmpire.rbxlx`).
- **TESTING:** BuyPathStatic **PASS=9780 FAIL=0**; claude_bud_job71 0 failed; codebot_v233 all PASS; admin abuse sims 0 failed. Phone: Settings shows WE_Build 233 → Settings > ADMIN > ADMIN ABUSE PANEL (owner) → CASH RAIN / ANNOUNCE; non-owner sees ADMIN ABUSE chip under TARGETS (countdown) + once-per-player RSVP pop-up.
- **Publish:** HTTP 200, versionNumber **231**, universe 10767159222 / place 97112936860418. **Servers NOT restarted**.
- **NEXT:** JOB64 (Creator Hub) / JOB62 (WE_NOTIFY_KEY) / DW-proof still held on bud. Double Weekend 2x starts 21:00 tonight if already wired. Admin Abuse event itself is Sat 10 Oct 20:00–20:30 Dublin.

## v232 PUBLISHED (Code Bot Roblox, 2026-10-02 15:50 Dublin): Open Cloud place version **230**. MAP-WIDE NUKE (OWNER-FIRST)
- **Source:** Code Bot `ca1d265` + wording fix `b54a921` on phase-7-polish; bud merges `3c6cee2` + `17376a6` (on top of Claude's JOB 71 `6c92430`, no conflict except the codebot_v220 allow-list, both kept). WE_Build **232**. PreferMesh OFF; StreamingEnabled OFF; `WE_Building*` untouched; no price / Id change. Servers NOT restarted (new servers get it).
- **WHAT (Shaun 15:32: map-wide nuke, "Take 25% of each base's ATM"):** silo panel gets a big **MAP-WIDE NUKE** button (only for LiveFor players) -> How-it-works card (RequestNuke `mwprev` -> `NukeMapWidePreview` { Ok, Why, Bases, Skipped, Take, Pct, CooldownLeft }) -> LAUNCH (`mwlaunch`). `NukeService.MapWideLaunch`: one warhead, the SAME 30-min player + 5-min server cooldown + one-nuke-in-the-air lock, the existing 10 s `NukeIncoming` to everyone (MapWide = true, no ground ring), nothing moves before detonation; then every rival base is re-checked and hit through `MoneyCollectorService.NukeRaid(attacker, victim, text, 0.25)` (1:1 transfer, never multiplied, sets the raid shield). Skips: own base, raid shield / new player / low ATM (CanArmyRaid), spawn / novice protection, allies, PvP off, admins, JOB 63 camp cooldown. Victim card `NukeMapWideHit` ("YOU WERE NUKED BY X / LOST -$Y"), launcher `NukeMapWideSummary`, ONE MapWide `NukeBlast` flash. Nothing hit at detonation = warhead + player cooldown refunded. `NukeService.AdminResetCooldowns` added (admin `nukecd`: server cooldown only).
- **OLD NUKE UNCHANGED** for everyone not in LiveFor: same panel, same launch, same JOB 65 TARGETS -> NUKE raid (NukeRaid fraction nil = full ATM).
- **GATE:** `NukeMapWideConfig.OwnerFirst = true` (shaunie6 via `AdminConfig.IsPlaytestOwner` + Laumartinez26 11718087109). **Go public:** set `OwnerFirst = false` in `src/ReplicatedStorage/Shared/Configs/NukeMapWideConfig.luau` (and drop it from the v220/v230 owner-first allow-lists).
- **FILES:** `NukeMapWideConfig.luau` (new), `NukeService.luau`, `MoneyCollectorService.luau` (NukeRaid fraction), `NukeController.luau`, `tools/sim/run_nuke_mapwide_test.py` (real NukeService, all ok), `tools/checks/codebot_v232.py`, v220/v230 allow-lists, WE_Build pins 231 -> 232.
- **TESTING:** current flow re-proved first (`run_nuke_raid_test.py` 0 failed). BuyPathStatic **PASS=9722 FAIL=0** (bud merge PASS=9793 FAIL=0). Needs Shaun's phone test with at least one rival with ATM cash on the server: silo -> NUKE -> MAP-WIDE NUKE -> LAUNCH.

## v231 PUBLISHED (Code Bot Roblox, 2026-10-02 15:20 Dublin): Open Cloud place version **229**. GO LAUNCH YOUR NUKE prompt + silo arrow (OWNER-FIRST)
- **Source:** Code Bot `d870315` on phase-7-polish; bud merge `6eb71d5`. WE_Build **231**. PreferMesh OFF; StreamingEnabled OFF; `WE_Building*` untouched; no price / Id change. Servers NOT restarted (new servers get it).
- **WHAT (Shaun 15:09: "Yes do the go to launch the Nuke"):** after a WON Strategic Yard LAUNCH PREP run (`RebirthZonesConfig.Runs.StrategicYard`, Effect `nukecharge`) `ZoneRuns.finish` -> `deps.OnNukePrepWon` -> `RebirthZoneService.NukeGoLaunch` pushes FeaturePush `NukeGoLaunch` { X, Y, Z, Ready, ChargeLeft, CooldownLeft, Seconds } aimed at HIS `WE_SiloPrompt` part (annex console, else zone board). `NukeController` shows one top-stack card (Order.Objective: stacks under alerts / above toasts, no overlap) with big text **GO LAUNCH YOUR NUKE** / "Go to your silo and tap NUKE", or **NUKE READY IN m:ss** ("Warhead charging" / "Silo cooling down") counting down at 1 Hz, plus the ONE ObjectiveMarker arrow "NUKE SILO". Cleared when the silo panel opens (NukePanel), on the card's X, or after 120 s. No new per-frame loop. New read-only `NukeService.SiloStatus`.
- **GATE:** `NukeGoLaunchConfig.OwnerFirst = true` (shaunie6 via `AdminConfig.IsPlaytestOwner` + Laumartinez26 11718087109). **Go public:** set `OwnerFirst = false` in `src/ReplicatedStorage/Shared/Configs/NukeGoLaunchConfig.luau` (and drop it from the v220/v230 owner-first allow-lists + flip the codebot_v231 pin).
- **FILES:** `NukeGoLaunchConfig.luau` (new), `ZoneRuns.luau`, `RebirthZoneService.luau`, `NukeService.luau`, `NukeController.luau`, `tools/checks/codebot_v231.py`, v220/v230 allow-lists, WE_Build pins 230 -> 231.
- **TESTING:** BuyPathStatic **PASS=9689 FAIL=0** (bud merge PASS=9760 FAIL=0); luau unit run of `NukeGoLaunchConfig.LiveFor` / `.Text`. Needs Shaun's phone test: finish Launch Prep -> card + arrow -> walk to silo -> tap NUKE (card + arrow go).

## v230 PUBLISHED (Code Bot Roblox, 2026-10-02 13:38 Dublin): Open Cloud place version **228**. Public flip (Shaun 13:27: "turn everything on for everyone apart from the 2x weekend")
- **Source:** Code Bot `160df42` on phase-7-polish; bud merge `24cf1c5`. WE_Build **230**. PreferMesh OFF; StreamingEnabled OFF; `WE_Building*` untouched; no price / Id change. Servers NOT restarted (new servers get it; Migrate to Latest Update if wanted).
- **NOW PUBLIC:** `Job67DressConfig.ZoneBuildings` (rebirth-zone desert houses, v222), `EndgameConfig.TierText` (turret Mk I-V + wall looks, v223), `SyntyVehicleConfig` (Armored Truck / Armed 4x4 / Scout Car Synty bodies, v223), `VisualAssetConfig.BodyRollout = "all"` (helicopter / bomber / airlifter / VTOL / ship / sub / strike-jet store bodies, incl. hangar/dock showpieces).
- **LICENCE CHECK (WE_CHECK2L, Open Cloud Luau Execution on place v227, read-only + economy/inventory APIs):** all 15 body models (14669079591, 473576954, 7941124517, 5545544418, 116924692473761, 80886282228822, 11240665977, 10649792198, 12235335847, 2625253037, 3626114334, 6860896505, 104820847233642, 12442299148, 14589101870) are free public-domain Creator Store models and owned by shaunie6; every inner mesh/texture uploaded by the same seller, EXCEPT 5545544418.
- **HELD OWNER-ONLY:** AmphibAssault body 5545544418 (new per-ref `BodyRolloutHold = "owner"`, honoured in `VisualAssetService.BodyAllowed`): its inner decal 385251431 "HMS Queen Elizabeth II Aircraft Carrier Badge" is another creator's upload (AdamAlHaddad, real-world navy badge). Fix later: swap the body or confirm decal is stripped and Shaun OKs.
- **STILL OWNER-ONLY BY DESIGN:** `EventConfig.OwnerFirst` (Double Weekend preview before 21:00; window untouched), admin tools (AdminConfig). Unshipped bud features JOB 62/64/DW-proof remain deferred (not on phase-7).
- **FILES:** 3 OwnerFirst flips, VisualAssetConfig + VisualAssetService (BodyRolloutHold), `tools/checks/codebot_v230.py`, pins updated (v87/v101/v166/v220/v222/v223, claude_bud_zone_buildings/tier_looks/synty_vehicles; v211/v219 byte pins skip BodyRollout/v230 lines), `claude_bud_job70` accepts the eebb65f "SHIPPED LIVE in v217" line (was failing since eebb65f), WE_Build 229 → 230.
- **TESTING:** BuyPathStatic **PASS=9661 FAIL=0**.

## v229 PUBLISHED (Code Bot Roblox, 2026-10-02 Dublin): Open Cloud place version **227**. 5 free achievement badges wired (batch 3)
- **Source:** Code Bot `5aac316` on phase-7-polish. WE_Build **229**. PreferMesh OFF; StreamingEnabled OFF; `WE_Building*` untouched; no price / Id change. Servers NOT restarted.
- **COMPLETED:** Wired Creator Hub free badges (universe 10767159222, verified enabled) into `AchievementConfig` BadgeId fields:
  1. PlazaCaptured → Plaza Conqueror **2523539979778536**
  2. PlayerKills100 → Warlord **1556267397534009**
  3. Rebirth1 → Reborn **1710789554032852**
  4. Army50 → Grand Army **3674428280965305**
  5. FirstNuke → Doomsday **3290435300593576**
  Prior 10 wired ids (v134 + v170) unchanged. Exactly **6** BadgeId=0 remain: Cash100M, Rebirth5, Rebirth10, Rebirth20, Streak7, WeeklyCrown (next daily free batch). Award / join backfill path unchanged (`AchievementService`).
- **FILES:** `AchievementConfig.luau`, `tools/checks/codebot_v229.py`, zeros pins in `codebot_v134` / `codebot_v170` + `tools/sim/run_achievement_test.py`, WE_Build pins 228 → 229 (src + tools/checks + BuyPathStatic), `dist/WarEmpire-PERF.rbxlx` (= `dist/WarEmpire.rbxlx`).
- **TESTING:** BuyPathStatic **PASS=9645 FAIL=0**; codebot_v229 all PASS; codebot_v134 / v170 / run_achievement_test PASS.
- **Publish:** HTTP 200, versionNumber **227**, universe 10767159222 / place 97112936860418. **Servers NOT restarted** (new servers get WE_Build 229; join backfill awards already-unlocked badges).
- **NEXT:** daily free badge routine for the remaining 6 (max 5/day GMT). JOB64/62 still held.


## v228 PUBLISHED (Code Bot Roblox, 2026-10-02 Dublin): Open Cloud place version **226**. Error / warning spam fixes, PUBLIC, no gameplay change
- **Source:** Code Bot `f4807ef` on phase-7-polish. WE_Build **228**. PreferMesh OFF; StreamingEnabled OFF; `WE_Building*` untouched; no price / Id change. Servers NOT restarted.
- **COMPLETED:**
  1. `AnalyticsService.flush`: `LogEconomyEvent` argument 6 (transactionType) is now a **string** (`txTypeName(r.TxType)` → the `Enum.AnalyticsEconomyTransactionType` item's `.Name`, fallback the raw string / "Gameplay"). It was an EnumItem via `enumValue(...)`: Roblox warned on every row (~41.7k/day) and dropped the event, so **economy analytics have been empty since WE_Build 183**; they should start filling from this build. flowType (argument 2) stays the `Enum.AnalyticsEconomyFlowType` item.
  2. `ArmyController` (server): `[ArmyDebug] SLOT CHANGE ... -> none reason=death/removed` warn now behind `ArmyController.DebugFor(player)` (counter `Stats.SlotChanges` still counts).
  3. `ArmyController` (server): `[ArmyDebug] LAYOUT CHANGE` warn now behind `debugOn` (set earlier in the same step).
  4. `VehicleService.onDriverChanged`: a non-owner in the driver seat is ejected in `task.defer`, only if `seat.Occupant == occupant` still (same as the passenger seat code): stops "set the parent of SeatWeld to NULL" warnings. Owner path unchanged.
- **FILES:** `AnalyticsService.luau`, `Modules/ArmyController.luau`, `VehicleService.luau`, `tools/checks/codebot_v228.py`, WE_Build pins 227 → 228 (src + tools/checks + BuyPathStatic), `dist/WarEmpire-PERF.rbxlx` (= `dist/WarEmpire.rbxlx`).
- **TESTING:** BuyPathStatic **PASS=9617 FAIL=0**; codebot_v228 13/13 PASS (incl. "argument 6 is a string").
- **Publish:** HTTP 200, versionNumber **226**, universe 10767159222 / place 97112936860418. **Servers NOT restarted** (new servers get WE_Build 228).
- **Watch:** Creator Hub error report over the next day: the LogEconomyEvent warning, ArmyDebug SLOT/LAYOUT CHANGE and SeatWeld NULL lines should drop off on WE_Build 228 servers; Creator Hub Economy analytics should start showing Sources/Sinks.
- **NEXT:** none; JOB64/62 still held.


## v227 PUBLISHED (Code Bot Roblox, 2026-10-02 Dublin): Open Cloud place version **225**. Speed Trial = a plain 1 R$ purchase, ONE TIME ONLY (Shaun 10:57 + 10:58)
- **Source:** Code Bot `ee0e624` on phase-7-polish. WE_Build **227**. PreferMesh OFF; StreamingEnabled OFF; `WE_Building*` untouched; no price / Id change (1 R$, 3715953404). Servers NOT restarted.
- **SHAUN:** "I don't want the speed trial to be a game. I want it to be a purchase just so people can trial being faster for a few minutes to encourage them to buy the full pass", then: one time only per player, ever; he and Laumartinez26 may re-test.
- **COMPLETED:**
  - `SpeedTrialConfig`: ring course / TimeLimit / Reward / HowTo removed. `TrialSeconds = 300`, `UpsellPassKey = "ImpulseSpeed"` (Speed Pass, 99 R$, x1.75 with SpeedV2), `OneTimeOnly = true`, `IsActivity = false`, `ShopRowSub = "Try Speed Pass for 5 min"`, `RepeatAllowedFor` (= AlwaysShowFor: AdminConfig owner 470626172 + 11718087109), `MayGrant`, `NewUntil`, `ChipText`.
  - `SpeedTrialService` rewritten: `GrantTrial` (ProcessReceipt, same ledger, saved before ack) sets `SpeedTrial.Used = true`, `Grants += 1`, `Until = max(Until, now) + 300`; a used non-tester's receipt is acknowledged, grants nothing, logged `SPEED_TRIAL_REPEAT_REFUSED`. `AfterGrant` / `OnProfileLoaded` apply the Speed Pass speed (`MonetizationConfig.SpeedMultOf(ImpulseSpeed)`) via MoveDebug, re-applied on respawn, restored at the end; never written for a Speed Pass / Speed Boost owner. Attributes `WE_SpeedTrialUntil`, `WE_SpeedTrialUsed`. Rejoin inside the window resumes. `RequestSpeedTrial` remote is still registered but unused.
  - `ProfileSchema`: `SpeedTrial = { Used, Until, Grants }` (old Entries / Runs > 0 count as Used).
  - `ShopController`: the row prompts the 1 R$ product directly (no How to play card); hidden once used or for Speed Pass / Speed Boost owners, always shown for the two testers; still sorted right after FREE rows. End pop-up `WE_SpeedTrialUpsell` (SPEED TRIAL OVER, Speed Pass · 99 R$, BUY = existing `promptGamePass`, NO THANKS; 56 px buttons) when the trial ends in-session.
  - `HUDController`: `SpeedTrialChip` "SPEED 4:59" (same look as the 2x chip, 1 Hz only while running).
- **FILES:** `SpeedTrialConfig.luau`, `SpeedTrialService.luau`, `MonetizationService.luau`, `ProfileSchema.luau`, `ShopController.luau`, `HUDController.luau`, `tools/sim/run_speed_trial_test.py`, `tools/checks/codebot_v227.py`, older speed trial checks updated (claude_bud_job66_speed_trial, codebot_v224/225/226), WE_Build pins 226 → 227, CLAUDE.md JOB 66 entry, `dist/WarEmpire-PERF.rbxlx` (= `dist/WarEmpire.rbxlx`).
- **TESTING:** BuyPathStatic **PASS=9604 FAIL=0**; speed trial sim 0 failed; codebot_v227.
- **Publish:** HTTP 200, versionNumber **225**, universe 10767159222 / place 97112936860418. **Servers NOT restarted** (join a new server for WE_Build 227; a private server must be shut down first).
- **Phone test:** new server → Settings shows build 227 → Shop → SUPPLY · R$ → "Speed Trial · Try Speed Pass for 5 min" (1 R$, under the FREE rows) → tap → Roblox 1 R$ prompt → buy → "SPEED 5:00" chip counts down → at 0:00 the SPEED TRIAL OVER card (BUY / NO THANKS). Normal players: the row disappears after one use.
- **Creator Hub:** the 1 R$ product description still describes the old run; suggested new text: "Try Speed Pass speed for 5 minutes. One time only."
- **NEXT:** none; JOB64/62 still held. Claude: do NOT rebuild the ring run.


## v226 PUBLISHED (Code Bot Roblox, 2026-10-02 10:47 Dublin): Open Cloud place version **224**. Speed Trial row right after the FREE rows in SUPPLY · R$
- **Source:** Code Bot `054d62c` on phase-7-polish. WE_Build **226**. PreferMesh OFF; StreamingEnabled OFF; `WE_Building*` untouched; no price / Id change (1 R$, 3715953404). Servers NOT restarted.
- **PROVEN CAUSE (two parts):**
  1. **Sort bug (code, v224 + v225):** `ShopController` builds the Speed Trial row (key `sp_speedtrial`) into the SUPPLY · R$ list (`addRow` → `buildRow(list, ...)`, between FREE Airdrop and FREE Invite). The v206/v207 price sort `applyPriceOrder` → `rowRobuxPrice(rowKey)` looks the key up in `MonetizationConfig.DevProducts` / `GamePasses`; `sp_speedtrial` is in neither (the product lives in `SpeedTrialConfig`, MonetizationService marks its synthetic def `HideFromShop`), so it got `SORT_NO_PRICE` → tier 2 (no-price rows: Favorite, locked Supply Crate) → the very **bottom** of the list, under every paid row. Not a different tab, not a catalog / LivePrices filter (its button text is hard-coded "1 R$").
  2. **Old server (timing):** Shaun tested ~10:41 in his **private (VIP) server**; v225 published 10:42 (place 223). A Roblox server, private included, keeps the place version it started on until it shuts down (no restart was done), so that server ran v224 or older. In v224 the row is also hidden for a Speed Pass / Speed Boost owner (the OwnerAlwaysShow override only arrived in v225). Older than v224 (before 10:25): no Speed Trial at all.
  - **Private-server code paths:** none in the shop / Speed Trial path. `PrivateServerId` / `PrivateServerOwnerId` are only read by `BaseGuards`, `OpsRewards` and `CheckpointGuardService` (reward multipliers / guards); `ShopController`, `SpeedTrialConfig`, `SpeedTrialService`, `MonetizationConfig`, `AdminConfig` never branch on them.
- **FIX:** `rowRobuxPrice` prices `sp_speedtrial` from `SpeedTrialConfig.RobuxPrice` (1) → tier 1, cheapest paid row → right after the FREE rows for everyone who gets the row. Row gate unchanged (`AlwaysShowFor`: shaunie6 470626172 via AdminConfig + Laumartinez26 11718087109; others hidden only if they own Speed Pass / Speed Boost). Same `buildRow` as every row → mobile layout unchanged.
- **FILES:** `ShopController.luau`, `tools/checks/codebot_v226.py`, WE_Build pins 225 → 226 (src + tools/checks), `dist/WarEmpire-PERF.rbxlx` (= `dist/WarEmpire.rbxlx`).
- **TESTING:** BuyPathStatic **PASS=9586 FAIL=0**; codebot_v226 (row in Supply list, priced from SpeedTrialConfig, sort sim FREE → Speed Trial → 5 R$ ...).
- **Publish:** HTTP 200, versionNumber **224**, universe 10767159222 / place 97112936860418. **Servers NOT restarted.**
- **Phone test (Shaun / Laumartinez26):** the private server must be a NEW one: leave, then in the game page Servers → your private server → (⋯) / Configure → **Shut Down** (or wait until it is empty a few minutes), then join again → Shop → SUPPLY · R$: FREE Airdrop, FREE Invite, then **Speed Trial · 1 R$**, then the 5 R$ rows.
- **NEXT:** none for this; JOB64/62 still held.


## v225 PUBLISHED (Code Bot Roblox, 2026-10-02 10:42 Dublin): Open Cloud place version **223**. Speed Trial OwnerAlwaysShow (owner + tester always see the row)
- **Source:** Code Bot `3746e9b` on phase-7-polish. WE_Build **225**. PreferMesh OFF; StreamingEnabled OFF; `WE_Building*` untouched; no price / Id change (1 R$, 3715953404). Servers NOT restarted.
- **COMPLETED:** `SpeedTrialConfig.OwnerAlwaysShow = true` + `AlwaysShowUserIds = { 11718087109 }` (Laumartinez26, tester) + `SpeedTrialConfig.AlwaysShowFor(userId)` (AdminConfig `IsPlaytestOwner` / `UserIds` allowlist → shaunie6 470626172). `ShopController` shows the Speed Trial row for them even when they own Speed Pass / Speed Boost; everyone else unchanged (hidden for those owners). The run itself was never server-gated; a speed owner keeps their own faster speed (trial boost never overwrites it). Tester NOT added to AdminConfig (no admin commands).
- **FILES:** `SpeedTrialConfig.luau`, `ShopController.luau`, `tools/checks/codebot_v225.py`, WE_Build pins 224 → 225, `dist/WarEmpire-PERF.rbxlx` (= `dist/WarEmpire.rbxlx`).
- **TESTING:** BuyPathStatic **PASS=9570 FAIL=0**; speed trial sim 0 failed; codebot_v225.
- **Publish:** HTTP 200, versionNumber **223**, universe 10767159222 / place 97112936860418. **Servers NOT restarted** (join a new server for WE_Build 225).
- **Phone test (Shaun / Laumartinez26, new server, WE_Build 225):** Shop → Speed Trial row now visible despite Speed Boost → How to play → 1 R$ START → 6 rings → cash. CANCEL ends the run. A non-admin account with Speed Boost still sees no row.
- **NEXT:** none for this; JOB64/62 still held.


## v224 PUBLISHED (Code Bot Roblox, 2026-10-02 10:25 Dublin): Open Cloud place version **222**. JOB 66 Speed Trial PUBLIC + honest shop text (Shaun items 5+6)
- **Source:** cherry-pick `d1a07d3` + `e697106` (claude/desktop-bud) → phase-7-polish. WE_Build **224**. PreferMesh OFF; StreamingEnabled OFF; `WE_Building*` untouched; no unapproved price change. Servers NOT restarted.
- **COMPLETED:**
  - **Item 5 / JOB 66 Speed Trial (PUBLIC):** `SpeedTrialConfig.OwnerFirst = false` (Shaun approved). Creator Hub developer product **Speed Trial** Id **3715953404** at **1 R$** (managed pricing OFF, on sale). Shop row + How-to-play card + ProcessReceipt entry grant + 6-checkpoint road sprint + x1.6 for 5 min + cash prize as `devproduct`. JOB64 Referral NOT shipped.
  - **Item 6 honest shop text:** VIP / VIP overhaul / 2x Cash / 2x Offline Cash Descriptions say exactly what they do. Names/prices/Ids unchanged.
- **HELD:** JOB 64 Referral (Creator Hub), JOB 62 notifications (`WE_NOTIFY_KEY`). DOUBLE WEEKEND proof checks stay on bud only.
- **FILES:** `SpeedTrialConfig.luau`, `SpeedTrialService.luau`, `MonetizationService.luau`, `ShopController.luau`, `ZoneRunController.luau`, `MonetizationConfig.luau`, `tools/checks/claude_bud_job66_speed_trial.py`, `tools/checks/claude_bud_shop_text.py`, `tools/checks/codebot_v224.py`, `tools/sim/run_speed_trial_test.py`, WE_Build pins 223 → 224, `dist/WarEmpire-PERF.rbxlx` (= `dist/WarEmpire.rbxlx`).
- **TESTING:** BuyPathStatic **PASS=9555 FAIL=0**; speed trial sim + shop text + codebot_v224.
- **Publish:** HTTP 200, versionNumber **222**, universe 10767159222 / place 97112936860418. **Servers NOT restarted** (join a new server for WE_Build 224).
- **Phone test (Shaun, new server, WE_Build 224):** (1) Shop → Speed Trial → How to play → 1 R$ START → run 6 rings → cash + speed. (2) CANCEL works. (3) Speed Pass / Speed Boost owners: no Speed Trial row. (4) Shop VIP / 2x Cash / 2x Offline Cash text matches the honest lines and fits one phone row.
- **NEXT:** watch Speed Trial purchases; Creator Hub purchase-prompt descriptions for VIP / 2x Cash / 2x Offline Cash may want the same wording.


## JOB 66 SPEED TRIAL / 1 R$ SPEED BOOST — PRIORITY QUEUED then SHIPPED (Code Bot Roblox, 2026-10-02): ship PUBLIC
- **Approval:** Shaun approved `OwnerFirst=false` and going straight live. The product price is 1 R$.
- **Queue (docs-only record):** create the 1 R$ product in Creator Hub; config `ProductId` placeholder until filled; `claude_bud_job66_speed_trial.py`; BuyPathStatic **FAIL=0**. This queue change was docs-only before implementation.
- **Shipped v224:** ProductId **3715953404** wired; PUBLIC.


## v223 PUBLISHED (Code Bot Roblox, 2026-10-02 09:47 Dublin): Open Cloud place version **221**. Turret+wall looks ONE config + drivable Synty vehicles OWNER-FIRST (Shaun items 3+4)
- **Source:** cherry-pick `958cb67` + `60a9ded` (claude/desktop-bud) → phase-7-polish. WE_Build **223**. PreferMesh OFF; StreamingEnabled OFF; `WE_Building*` untouched; no price / Id / save-key / level change. Servers NOT restarted.
- **COMPLETED (owner-first):**
  - **Item 3:** `EndgameConfig.Defence.TurretTiers` is the one turret tier table (Mk I–Mk V / AutoGunT1–5). Guns upgrade text + base console wall row name the look (`EndgameConfig.TierText`, OwnerFirst = true). Save keys / levels / prices untouched.
  - **Item 4:** `SyntyVehicleConfig` (OwnerFirst = true) dresses ArmoredTruck / ArmedJeep / ScoutCar with Shaun's Synty pack 119390702773907 via `VisualAssetService.TryAttachSyntyVehicleVisual`. Part-kit chassis still drives; tanks stay on kits. Missed piece name → today's body.
- **HELD:** JOB 64 Referral (Creator Hub), JOB 62 notifications (WE_NOTIFY_KEY). DOUBLE WEEKEND proof checks stay on bud only.
- **FILES:** `EndgameConfig.luau`, `EndgameService.luau`, `GateDefenseService.luau`, `BaseController.luau`, `SyntyVehicleConfig.luau`, `VehicleService.luau`, `VisualAssetService.luau`, `tools/checks/claude_bud_tier_looks.py`, `tools/checks/claude_bud_synty_vehicles.py`, `tools/checks/codebot_v223.py`, WE_Build pins 222 → 223, `dist/WarEmpire-PERF.rbxlx` (= `dist/WarEmpire.rbxlx`).
- **TESTING:** BuyPathStatic **PASS=9489 FAIL=0**; `claude_bud_tier_looks.py` + `claude_bud_synty_vehicles.py` + `codebot_v223.py`.
- **Publish:** HTTP 200, versionNumber **221**, universe 10767159222 / place 97112936860418. **Servers NOT restarted** (join a new server for WE_Build 223).
- **Phone test (Shaun, new server, WE_Build 223, owner-only):** (1) Engineering Bureau: Turret Guns row names the Mk. (2) Base console: Defensive Walls row says next wall look. (3) Upgrade Turret Guns past L1/L4/L7/L10: gun model gets bigger. (4) Spawn Armored Truck, Armed 4x4, Scout Car — each wears Synty body (or today's body if name miss); drive with thumbstick as before.
- **NEXT:** flip `TierText.OwnerFirst` and `SyntyVehicleConfig.OwnerFirst` to false after phone OK. Studio owed on Synty: confirm intact piece names + yaw/seat height if body looks wrong.

## v222 PUBLISHED (Code Bot Roblox, 2026-10-02 09:20 Dublin): Open Cloud place version **220**. Rebirth-zone buildings OWNER-FIRST (Shaun item 2)
- **Source:** cherry-pick `43380f0` (claude/desktop-bud) → phase-7-polish. WE_Build **222**. PreferMesh OFF; StreamingEnabled OFF; `WE_Building*` untouched; no price / Id / save-key change. Servers NOT restarted.
- **COMPLETED:** each rebirth zone's MAIN block building becomes a free desert house on every plot still showing the Part build (`Job67DressConfig.ZoneBuildings`, `OwnerFirst = true`, NEW-OWNER-FIRST by the base owner). `Job67DressService.DressZone` runs from `RebirthZoneService` after the Part build, off-thread. Store-model zones left alone. 7 houses = 1,151 parts ≤ MaxPartsPerPlot 1300. Packs: Prinz 10055885754 / CAG 9939040273 / Imp 15654066038.
- **HELD:** JOB 64 Referral (Creator Hub), JOB 62 notifications (WE_NOTIFY_KEY). DOUBLE WEEKEND proof checks stay on bud only (no event code change).
- **FILES:** `Job67DressConfig.luau`, `Job67DressService.luau`, `RebirthZoneService.luau`, `tools/checks/claude_bud_zone_buildings.py`, `tools/checks/codebot_v222.py`, WE_Build pins 221 → 222, `dist/WarEmpire-PERF.rbxlx` (= `dist/WarEmpire.rbxlx`).
- **TESTING:** BuyPathStatic **PASS=9456 FAIL=0**; `claude_bud_zone_buildings.py` + `codebot_v222.py`.
- **Publish:** HTTP 200, versionNumber **220**, universe 10767159222 / place 97112936860418. **Servers NOT restarted** (join a new server for WE_Build 222).
- **Phone test (Shaun, new server, WE_Build 222, owner-only):** visit your rebirth zones — each main building is a detailed desert house; walk into a house (solid); kiosks/consoles/runs still work. Non-owner plots keep the old blocks.
- **NEXT:** flip `ZoneBuildings.OwnerFirst` to false after phone OK.

## v221 PUBLISHED (Code Bot Roblox, 2026-10-02 08:18 Dublin): Open Cloud place version 219. Plaza Airstrike now ALSO takes the Central Plaza (PUBLIC)
- **Commits:** code+dist+checks `2bda0e8` on phase-7-polish (from v220 `f351945`). WE_Build **221**. PreferMesh OFF; StreamingEnabled OFF; `WE_Building*` untouched; no price / product Id / save-key change. Servers NOT restarted.
- **Shaun (07:54):** the Plaza Airstrike developer product (Id 3715442542) should also give the buyer an instant takeover of the Central Plaza. Price NOT changed.
- **How capture works (proven before the change):** owner is per player (`rt.OwnerUserId`, OwnerType Player; the buyer's `ClanId` rides along) in `TerritoryService`. Normal capture = `tickTerritory` proximity progress (20 s for the Plaza, blocked while `OutpostDefenders` guards stand) -> `awardCapture(capturer, rt)`. `awardCapture` releases the previous owner (`releaseOwnership(..., "captured")`: his "lost" toast, Empire Tax recount), sets owner + `ProtectedUntil`, `Stats.TerritoriesCaptured` / `Stats.PlazaCaptures` (Plaza leaderboard), `PlazaBounty.OnCaptured`, Empire Tax toast, analytics, missions, Intel contract, tutorial hooks, marker/flag. The Plaza guards (`OutpostDefenders`) leave while the zone is Held and come back `RespawnSeconds` after it is neutral again (they do not change sides; that is the existing rule, unchanged). JOB 51 SharedHostility (who guards may shoot) is untouched.
- **Change:** receipt banks the charge (CounterGrants.GrantAirstrikes, saved) -> `MonetizationService.OnGranted("PlazaAirstrike")` -> `PlazaAirstrike.FireFromPurchase(player)` spends it at once from anywhere (paid: no range / cooldown refusal), warns, lands the same strike `WarnSeconds` later (non-lethal, never the buyer), then `TerritoryService.InstantCapture(player, "CentralPlaza")` = the SAME `awardCapture` + `PushAll`, and every player sees **"AIRSTRIKE! <name> took the Plaza"**. Already the holder: the strike still lands, buyer sees "AIRSTRIKE! You still hold the Plaza", others "AIRSTRIKE! <name> holds the Plaza", no second capture / bounty / leaderboard bump. Re-capture rules unchanged (normal protection period, others can take it back). An older banked charge spent with the AIRSTRIKE button also takes the Plaza. Server only: no remote reaches `InstantCapture`. Switch: `MonetizationConfig.PlazaAirstrikeTakeover` (Enabled = true, OwnerFirst = false; Enabled = false = old strike-only banked charge).
- **Shop text:** in-game Description now "Airstrike + instant Plaza takeover". **TODO (Shaun, Creator Hub):** update the Plaza Airstrike developer product's own description (shown in the Roblox purchase prompt) to mention the instant Plaza takeover. Note: config fallback price is 79 R$ (audited v156); the Shop shows the live Creator Hub price - nothing changed here.
- **FILES:** `MonetizationConfig.luau`, `PlazaAirstrike.luau`, `MonetizationService.luau`, `TerritoryService/init.luau`, `tools/checks/codebot_v221.py`, `tools/sim/run_plaza_airstrike_takeover_test.py`, scoped pins in `codebot_v167/v207/v219/v220.py`, WE_Build pins 220 -> 221, `dist/WarEmpire-PERF.rbxlx` (= `dist/WarEmpire.rbxlx`).
- **TESTING:** `LUAU_COMPILE=$HOME/.local/bin/luau-compile python3 tools/BuyPathStatic.py` -> **PASS=9413 FAIL=0**; `codebot_v221.py` 29 PASS; sim (real TerritoryService + PlazaAirstrike) 24/24 ok. rojo build OK.
- **Publish:** HTTP 200, versionNumber **219**, universe 10767159222 / place 97112936860418. **Servers NOT restarted** (join a new server for WE_Build 221).
- **Phone test (Shaun + a second player, new server):** (1) second player stands on the Central Plaza and captures it. (2) You, anywhere on the map: Shop -> Plaza Airstrike -> buy. (3) "AIRSTRIKE incoming", ~3 s later the second player takes damage (not killed), everyone sees "AIRSTRIKE! <you> took the Plaza", the flag/map shows you as owner, the guards leave, second player gets the "lost" toast. (4) Buy again while holding: strike lands, "You still hold the Plaza". (5) Second player stands on the Plaza: he can capture it back as normal.

## v220 PUBLISHED (Code Bot Roblox, 2026-10-02 08:11 Dublin): Open Cloud place version 218. EVERYTHING PUBLIC — every owner-first feature gate OFF (OwnerFirst = false)
- **Approval:** Shaun, 2026-10-02 07:51 Dublin: "turn everything that only I have on for everyone". One release.
- **Commits:** `64335c8` on phase-7-polish (from v219 `259dfc1`); bud merge `10d939a` into claude/desktop-bud. WE_Build **220**. src diff = OwnerFirst + WE_Build lines only. PreferMesh OFF; StreamingEnabled OFF; `WE_Building*` untouched; no price / Id / save-key change. Servers NOT restarted (~30 players on; new servers / rejoin get WE_Build 220).
- **NOW PUBLIC (23 flips):** JOB 50 + 69 `RebirthZonesConfig.Rebuild` (zone runs, plaques, signs, visuals, every rebirth zone on every plot `Slots`, how-to-play `HowTo`); JOB 51 `CombatConfig.SharedHostility`; JOB 52 `ArmyOrdersConfig.AttackRange`; JOB 53 `EndgameConfig.DefenceVisuals`; JOB 54 `LightingConfig.Night2`; JOB 55 `EndgameConfig.DefenceFix`; JOB 56 `SpawnTerminalConfig` + `VisualAssetConfig.AirRotorDisc`; JOB 57 `BaseLifeConfig`; JOB 58 `HangarDockConfig`; JOB 59 B `SoundConfig.Pass59`; JOB 63 `RaidConfig.AntiCamp`; JOB 65 `RebirthZonesConfig.NukeRaid`; JOB 67 `Job67DressConfig` (top + Walls / BaseProps / Buildings / Wrecks) + `VisualAssetConfig.Job67` turret tiers; JOB 68 `RangeLifeConfig`; v216 `HudConfig.Hotbar.AutoDrawGuard`; v219 `GateDefenseConfig.TurretHull` + `VehicleConfig.HeliRotorRing`. JOB 41 (Guided, RecruitPackOffer, RivalConfig, RatePromptConfig) was already public since v166.
- **LEFT OWNER / ADMIN-ONLY (why):** `EventConfig.OwnerFirst` (Double Weekend owner PREVIEW before StartUnix 21:00 Dublin tonight; the real window is for everyone; opening 2x early for all = economy change); admin tools `AdminConfig.UserIds` / `AdminService.IsAdmin` (admin commands, /zonereport, /armydebug ...); test-cash `AdminPlaytestCash` + BaseService 50M floor; `OwnerRebirthGrant`; playtest all-vehicles + spawn-gate bypass; `PremiumGunsConfig.OwnerTestGrant` / `GarageSlot.OwnerTest` (free paid items for testing); `ArmyConfig` DebugUserIds, `VehicleConfig` diag UserIds; leaderboard exclusion of admins. **`VisualAssetConfig.BodyRollout = "owner"`** stays: store helicopter / bomber / ship hulls without a WE_CHECK2 / licence record (licence hold, not admin) — flip to "all" only after Shaun runs WE_CHECK2 on them. Held, not owner-gated: JOB 64 Referral (Creator Hub), JOB 62 notifications (WE_NOTIFY_KEY).
- **Checks:** owner-first pins in `claude_bud_job50`–`job68` and `codebot_v183`–`v219` now pin the public value; 12 sims (`run_base_guards`, `rebirth_stations`, `plaza_guards`, `defence_visuals`, `night_lights`, `spawn_terminals`, `hangar_dock`, `sound_pass`, `anti_camp`, `nuke_raid`, `range_life`, `howto`) assert the shipped OwnerFirst = false, then still prove the owner-first path with it forced true. New `tools/checks/codebot_v220.py`: no `OwnerFirst = true` gate left in src except EventConfig preview, all 23 flips tagged, only BodyRollout stays "owner", owner UserId literal only in admin/test/diag files, src diff only OwnerFirst/WE_Build, no WE_Building*/price lines, PreferMesh OFF.
- **TESTING:** `LUAU_COMPILE=$HOME/.local/bin/luau-compile python3 tools/BuyPathStatic.py` → **PASS=9384 FAIL=0**; `codebot_v220.py` 39 PASS; rojo build OK (`dist/WarEmpire-PERF.rbxlx` = `dist/WarEmpire.rbxlx`).
- **Publish:** HTTP 200, versionNumber **218**, universe 10767159222 / place 97112936860418. No restart.
- **NEXT:** watch error reports from public load (Job67 dressing, base life NPCs, night lights, sound pass now on every base); kill switch per feature = set that block's OwnerFirst back to true or Enabled = false. BodyRollout after WE_CHECK2.

## v219 PUBLISHED (Code Bot Roblox, 2026-10-02 08:00 Dublin): Open Cloud place version 217. Shaun's phone bugs on WE_Build 218, OWNER-FIRST: solid turrets, all 7 zones on EVERY plot, no yellow heli rotor ring
- **Base:** phase-7-polish `21d8801` (v218 handoff). WE_Build **219**. PreferMesh OFF; StreamingEnabled OFF; `WE_Building*` untouched; no price / Id / save-key / level change; no new Heartbeat / RenderStepped. Servers NOT restarted.
- **Bug 1, turrets walk-through (proven):** `GateDefenseService.spawnAutoGun` sets EVERY BasePart of the gun, nest and sandbags `CanCollide = false` (catalog / Minigun-pack loop, nest, sandbags; `partKitAutoGun` the same) and nothing solid was ever added. Fix: `GateDefenseConfig.TurretHull` (OwnerFirst) + `GateDefenseService._AddTurretHull`: one invisible anchored Block per AutoGun (ground to gun top, 2.6..6 stud square on the aim part), CanCollide on, CanQuery off (LOS / shots / ground rays ignore it, turrets still fire), CanTouch off, never welded. `spawnAutoGun(slot, at, folder, tier, ownerUserId)`.
- **Bug 2, zones missing on some plots (proven):** JOB 69's sim world left out what the live `checkSlotAt` sees: `WorldConfig.POIs` kits (`WE_Cluster "poi:*"`, not in `ClearableSources`), `WorldFillConfig.Roads` gate spurs + Bridges, gate aprons, garage pads, NPC / event anchors, the Bank. With the full world the 24 v218 `AnnexAlt` rows leave 7 gaps: P7 EastYard / EastStrip, P8 EastStrip, P10 WestStrip / WestFlank / EastYard / EastStrip; no slot = a tiny board for reached zones and NOTHING for locked ones. Fix: +60 AnnexAlt rows (the 24 kept first), negative slot verdicts retried on the next Refresh (`retryBlocked`, no loop), vehicles / unanchored parts never block (`transient`), a locked zone with no slot gets its ZONE BOARD ("Unlocks at Rebirth N"). New full-world sim `tools/sim/run_zone_slots_allplots_test.py`: plots 1..10 all 7/7, no overlaps; replays the v218 gaps.
- **Bug 3, yellow ring round the heli rotor (proven):** `VehicleService.addRotorDisc` (kitHeli) builds a Neon cylinder "RotorDisc" (0.55 transparent, rotor x 0.96) in the rarity accent: YELLOW on Uncommon / Epic / Premium helis (Rescue, Utility, Gunship, Attack, HeavyLift, NightAttack, VTOL, Stormwing), blue on Rare, red on Stealth. Store-body helis hide it (`hideKitUnder`), Part-kit helis show it. No Highlight / SelectionBox on vehicles. Fix: `VehicleConfig.HeliRotorRing` (OwnerFirst by the vehicle owner) skips the disc; RotorHub / RotorA / RotorB + the AirBodyRig spin untouched. All 14 helis go through the one kitHeli.
- **FILES:** `GateDefenseConfig.luau`, `GateDefenseService.luau`, `RebirthZonesConfig.luau`, `RebirthZoneService.luau`, `VehicleConfig.luau`, `VehicleService.luau`, `tools/checks/codebot_v219.py`, `tools/sim/run_zone_slots_allplots_test.py`, pins (claude_bud_job67 / codebot_v199 spawnAutoGun needle + ownerUserId), WE_Build pins, `dist/WarEmpire-PERF.rbxlx` (= `dist/WarEmpire.rbxlx`).
- **Publish:** HTTP 200, versionNumber **217**, universe 10767159222 / place 97112936860418, code commit `5893d26`. **Servers NOT restarted** (join a new server for WE_Build 219).
- **TESTING:** `LUAU_COMPILE=$HOME/.local/bin/luau-compile python3 tools/BuyPathStatic.py` → **PASS=9345 FAIL=0**; `codebot_v219.py` 41 PASS; both zone sims 0 failed.
- **Phone test (Shaun, new server, WE_Build 219, owner-only):** (1) walk into each turret at your gate: you stop; turrets still turn and fire. (2) `/zonereport` + walk your plot: all 7 zones incl. Nuclear Silo; locked ones show a fence / "Unlocks at Rebirth N". (3) rejoin for a different plot (ideally 7, 8 or 10): all 7 again. (4) spawn + enter a yellow-accent heli (Attack / Gunship / Rescue): no yellow ring, rotor still spins.
- **NEXT:** flip `TurretHull` / `HeliRotorRing` / `Rebuild.OwnerFirst` to false only after Shaun OK.

## v218 PUBLISHED (Code Bot Roblox, 2026-10-02 03:14 Dublin): Open Cloud place version 216. JOB 69 A/B/C + JOB 68 OWNER-FIRST takeover ship
- **Commits:** cherry-pick `4123e4a` → `db3583e` (JOB 69 A), `2ba1ea6` → `cb3801f` (JOB 69 B+C), `a1b2e92` → `ba2744f` (JOB 68) + code+dist+checks `f0ecaac` on phase-7-polish (from v217 `611cfbe` / `bd0744a`). WE_Build **218**. PreferMesh OFF; StreamingEnabled OFF; `WE_Building*` untouched; no price / Id / save-key / level change. Servers NOT restarted.
- **COMPLETED (owner-first, Claude quiet 115m+ takeover):**
  - **JOB 69 A:** every plot gets all 7 rebirth zones (incl. Nuclear Silo). `RebirthZonesConfig.AnnexAlt` + pure `ResolveSlots`; `RebirthZoneService` apron-checked cached `slotFrame`, stamps `WE_AnnexCFrame`, ZONE BOARD when no slot, admin `/zonereport`. Gated `ZC.RebuildLive(owner, "Slots")` with `Rebuild.OwnerFirst = true`.
  - **JOB 69 B+C:** how-to-play everywhere. Shared `Util/HowTo`, zone-run intro card + tracker / CANCEL / TRAIN (`ZoneRunController`), mission/activity/job HowTo cards. Gated `RebuildLive(..., "HowTo")` / `HowTo.Live`.
  - **JOB 68:** shooting range life — client cosmetic `RangeLifeController` (one shared low-rate loop, WE_Rig tag, near 80 studs, max 4/yard), `RangeLifeConfig.OwnerFirst = true`. OFF = still statues.
- **HELD:** JOB 64 Referral Rewards (`bbb39ce`) — needs Creator Hub form / setup; not cherry-picked. Still deferred on bud.
- **Do NOT re-merge JOB 70** — already live as v217 / place 215.
- **FILES:** `RebirthZonesConfig.luau`, `RebirthZoneService.luau`, `StorePropsService.luau`, `AdminService.luau`, `HowTo.luau`, `ZoneRunController.luau`, `ZoneRuns.luau`, `MissionController.luau`, `RangeLifeConfig.luau`, `RangeLifeController.luau`, `SoundConfig.luau`, DailyOps/Mission/Ops/SiteActivity/Security configs, `tools/checks/claude_bud_job69.py`, `tools/checks/claude_bud_job68.py`, `tools/checks/codebot_v218.py`, sims `run_zone_slots_test` / `run_howto_test` / `run_zone_run_layout_test` / `run_range_life_test`, WE_Build pins, `CLAUDE.md` JOB 67/68/69 pins, `dist/WarEmpire-PERF.rbxlx` (= `dist/WarEmpire.rbxlx`).
- **TESTING:** `LUAU_COMPILE=$HOME/.local/bin/luau-compile python3 tools/BuyPathStatic.py` → **PASS=9304 FAIL=0**; `tools/checks/codebot_v218.py` all PASS (OwnerFirst true for Rebuild + RangeLife; sims 0 failed). rojo build OK.
- **Publish:** HTTP 200, versionNumber **216**, universe 10767159222 / place 97112936860418. **Servers NOT restarted** (join a new server / rejoin for WE_Build 218).
- **Phone test (Shaun, new server, WE_Build 218, owner-only):** (1) walk every rebirth zone on your plot — all 7 present (incl. Nuclear Silo); non-owner plots may still show gaps. (2) tap a zone kiosk: how-to card with What / Steps / time / reward + START + CANCEL; during a run see timer, step counter, arrow. (3) at Training Yard within ~80 studs: shooters fire, flash, hit puff, reload; walk away → effects stop. (4) a non-owner account must NOT see slots/how-to/range-life.
- **NEXT:** flip `Rebuild.OwnerFirst` / `RangeLifeConfig.OwnerFirst` to false only after Shaun OK; JOB 64 still deferred; JOB 67 Walls/BaseProps stay owner-first until the big flip.

## v217 PUBLISHED (Code Bot Roblox, 2026-10-02 02:23 Dublin): Open Cloud place version 215. JOB 70 LIVE FOR EVERYONE — no walk-through dressing + one wall style on every side
- **Commits:** cherry-pick `bdf096b` → `4e9e5a7` + code+dist+checks `bd0744a` on phase-7-polish (from v216 `70e7244` / `fb50415`). WE_Build **217**. PreferMesh OFF; StreamingEnabled OFF; `WE_Building*` untouched; no price / Id / save-key / level change. Servers NOT restarted.
- **COMPLETED (JOB 70, Shaun approved OwnerFirst=false straight live):** every JOB 67 dressed prop / wall segment gets one invisible Box hull (`Job67DressService.createHull` via `Place` + `FitLine`): anchored Block, sized to the visual bounds, CanCollide + CanQuery on, CanTouch off; visual meshes stay CanCollide off. `Job67DressConfig.PropCollision` (OwnerFirst = false) categorises Sandbag / Hesco / Concrete / Crate / Pallet / BarbedWire / Misc. Walls: `WallStyleFor` + `Tiers[n].WallStyle` dress front/gate, left, right and rear the same way (L1 Sandbag Line, L2 Sandbag Wall, L3 Hesco Line, L4 Hesco Wall, L5 Hesco Fortress); HescoPlan stretch up to 2.6 so the whole ring fits MaxHesco 14. JOB 67 `Walls` / `BaseProps` blocks stay OwnerFirst (Shaun's base only until the big flip).
- **FILES:** `Job67DressConfig.luau`, `Job67DressService.luau`, `tools/checks/claude_bud_job70.py`, `tools/sim/run_job70_test.py`, `tools/checks/codebot_v217.py`, WE_Build pins (BaseService / DataService / EarlyRemotes / BuyPathStatic), `ASSUMPTIONS.md` JOB 70, CLAUDE.md JOB 70 queue needles, `dist/WarEmpire-PERF.rbxlx` (= `dist/WarEmpire.rbxlx`).
- **TESTING:** `python3 tools/sim/run_job70_test.py` → **0 failed**; `LUAU_COMPILE=$HOME/.local/bin/luau-compile python3 tools/BuyPathStatic.py` → **PASS=9225 FAIL=0**; `tools/checks/codebot_v217.py` PASS (PropCollision public, createHull/Place/FitLine, WallStyleFor L1–L5 all faces, WE_Build 217). rojo build OK.
- **Publish:** HTTP 200, versionNumber **215**, universe 10767159222 / place 97112936860418. **Servers NOT restarted** (join a new server / rejoin for WE_Build 217).
- **Phone test (Shaun, new server, WE_Build 217):** (1) at your base walk into sandbag lines, gate stacks, barbed wire, concrete blocks, crates, pallets and drums — you stop at each. (2) The gate road stays open. (3) All four wall sides (front, left, right, rear) show the same wall look for your wall level.
- **NEXT:** keep JOB 67 Walls/BaseProps owner-first until the big flip; deferred unmerged on bud: JOB 69 A/B/C (`4123e4a`/`2ba1ea6`), JOB 68 (`a1b2e92`), JOB 64 if still ahead. Do not restart servers.

## JOB 70 QUEUED (Code Bot Roblox, 2026-10-02 01:27 Dublin): URGENT collision + consistent wall dress — docs-only
- **Approval:** Shaun explicitly approved `OwnerFirst=false` and shipping LIVE FOR EVERYONE. No owner phone test or staged rollout is owed for this job.
- **Collision contract:** every newly wired base prop/wall visual (sandbags, Hesco, concrete blocks, crates, pallets, barbed wire) gets one invisible cheap Box/Block hull per placed visual segment. The hull is anchored and `CanCollide=true` for players and soldiers; visual mesh descendants are `CanCollide=false`. No heavy mesh collision or per-frame work.
- **Wall contract:** front/gate, left, right and rear wall sides all resolve the same new wall style from the central wall-upgrade config at the saved tier, while retaining progressive tier looks. Visuals stay non-colliding; hulls/authoritative wall colliders stay solid.
- **Checks:** add `tools/checks/claude_bud_job70.py` to account for every prop placement and all four wall sides, then update this handoff after implementation.
- **This commit:** queue/check documentation only; no Roblox/game code, place build, `WE_Building*`, `StreamingEnabled`, `PreferMesh`, save key, level, price, or rollout change.

## v216 PUBLISHED (Code Bot Roblox, 2026-10-02 01:52 Dublin): Open Cloud place version 214. Army fights no longer auto-draw the far-away owner's gun / stop him walking (OWNER-FIRST)
- **Commits:** code+dist+checks `fb50415` on phase-7-polish (from v215 `1c6b294`); bud merge `c5081e9` into claude/desktop-bud. WE_Build **216**. PreferMesh OFF; StreamingEnabled OFF; `WE_Building*` untouched; no price / Id / save-key change; no new Heartbeat / RenderStepped. Servers NOT restarted.
- **Shaun's bug (phone):** his army attacks another base, he stays away; each time his soldiers shoot, his own gun comes out and he stops walking; holster -> again.
- **Proven chain:** the ONLY automatic draw in the client is `CombatController.onDamaged()` (v215 file lines 646-658: `if HB.AutoDrawOnDamage and not drawn ... then setDrawn(true)`), fired by ANY health drop (CombatStateUpdate, line 1260-1261; Humanoid.HealthChanged, 2366-2367) or a "Damaged" feedback (1293-1294), with NO check of where the damage came from or whether anyone hostile is near. Drawing turns on the shoulder camera (`syncFeel` -> `CameraFx.SetCombatMode`: AutoRotate off) = the "stops walking". Every other `setDrawn(true)` is the player's own input (hotbar / keys / touch FIRE). The owner's own army hits only send him Hit / Kill markers (`onHitFeedback` -> markCombat + marker, never a draw). Side bug found on the way: for army / defence hits the victim's `Damaged.From` was the ARMY OWNER's character position (CombatService `hurtPlayer`, line 748), not the shooter. NOT proven: which exact health drop reached Shaun far from the fight - every server path that hurts a player is range-gated near the victim, so it is most likely real fire near him (e.g. enemy soldiers / defences answering him as the aggressor, `NoteArmyAggressor`) or a drop the client could not attribute. The guard below makes the draw need evidence either way.
- **Fix (`HudConfig.Hotbar.AutoDrawGuard = { Enabled = true, OwnerFirst = true, NearStuds = 160, ConfirmSeconds = 0.6 }`, `RetentionConfig.Live`):** a gun / blast Damaged still draws; an army / defence Damaged (`Unit = true`) draws only if its shooter is within 160 studs or unknown; a bare health drop with no Damaged within 0.6 s draws only if another player, a soldier that is not his, or a WarEmpireNPCs NPC is within 160 studs (one `task.delay` + one scan per drop, never a loop). Edge flash + RecentCombat still on every drop. Server: `ApplyUnitPlayerHit(..., fromPos)` (SquadOrdersService passes `unit.Root.Position`) and `ApplyDefenceHit(..., kind, fromPos)` (optional); `hurtPlayer` sends From = that shooter (nil = unknown) + `Unit = true` while live for the victim. The shared hostility rule (`UnitMayHitPlayer` / Hostility) still gates both hits, unchanged. Flag off = v215 behaviour.
- **Checks:** `LUAU_COMPILE=$HOME/.local/bin/luau-compile python3 tools/BuyPathStatic.py` **PASS=9113 FAIL=0** on phase-7-polish; claude/desktop-bud PASS=9218 FAIL=10, the same 10 FAILs as bud before the merge (JOB 61 CLAUDE.md, JOB 70 hull/wall pins, v102 CodesConfig; not this lane). New `tools/checks/codebot_v216.py` (27 asserts incl. a Luau sim of the draw decision table). Pins: claude_bud_job24b ApplyUnitPlayerHit needle (+FromPos); WE_Build pins 215 -> 216. rojo -> `dist/WarEmpire-PERF.rbxlx`, copied to `dist/WarEmpire.rbxlx`.
- **Publish:** HTTP 200, versionNumber **214**, universe 10767159222 / place 97112936860418. **Servers NOT restarted** (join a new server for WE_Build 216).
- **Phone test (Shaun + a second player, new server):** (1) send your army to attack their base, walk around far away (other side of the map): the gun stays holstered and you keep walking while the army fights. (2) Holster / walk for a minute: it never comes back out. (3) Have the second player shoot you: the gun auto-draws. (4) Your own FIRE button still draws and shoots.
- **Next:** if Shaun is happy, flip `HudConfig.Hotbar.AutoDrawGuard.OwnerFirst = false`.

## v215 PUBLISHED (Code Bot Roblox, 2026-10-02 01:44 Dublin): Open Cloud place version 213. Supply Depot boards + AIRDROP guide controls PUBLIC
- **Commits:** code+dist+checks `19e7790` on `phase-7-polish` lineage; bud merge `ad785c0` on `claude/desktop-bud`. WE_Build **215**. PreferMesh OFF; StreamingEnabled OFF; `WE_Building*` untouched; no price / Id / save-key change. Servers NOT restarted.
- **Public rollout:** `MonetizationConfig.PremiumPads.BigSign.OwnerFirst = false` gives every viewer the larger Supply Depot board text. `SupplyDropConfig.GuideHide.OwnerFirst = false` gives every player the `✕ HIDE LINE` button and Settings toggle. The server `AirdropGuideService` now accepts `profile.Settings.AirdropGuideOff` for non-owners through the same public gate; airdrop gameplay / claim / cash are unchanged.
- **Checks:** `LUAU_COMPILE=$HOME/.local/bin/luau-compile python3 tools/BuyPathStatic.py` **PASS=9084 FAIL=0**; `tools/checks/codebot_v212.py` PASS; new `tools/checks/codebot_v215.py` proves a non-owner is live for both gates and the server setting path; rojo build -> `dist/WarEmpire-PERF.rbxlx`, copied byte-identically to `dist/WarEmpire.rbxlx`.
- **Publish:** HTTP 200, versionNumber **213**, universe 10767159222 / place 97112936860418. **Servers NOT restarted.**

## v214 PUBLISHED (Code Bot Roblox, 2026-10-02 01:24 Dublin): Open Cloud place version 212. JOB 67 batches 2 + 3: detailed desert buildings + Synty vehicle wrecks at the outlying places (OWNER-FIRST)
- **Commits:** code+dist+checks `4e512ec` on phase-7-polish (from v213 `ba38cc1`); bud merge `293fb68` + CLAUDE.md JOB 67 progress `076d021` on claude/desktop-bud. WE_Build **214**. PreferMesh OFF; StreamingEnabled OFF; `WE_Building*` untouched; no price / Id / save-key / level change; POILayouts / WorldPOI byte-identical. Servers NOT restarted.
- **Batch 2 (`Job67DressConfig.Buildings`):** 10 Part TownBlock kits replaced by free Creator Store houses (10055885754 PrinzAaron x3 models, 9939040273 CAG, 15654066038 ImParadoxial, 16365964601): Port E_Office / E_Block2, Depot N_Barracks / S_Garrison, Armory N_Barracks, Airstrip S_Ops, Signal W_Block, Ruins R_2 / R_8, OilField Shack_S. 1,832 parts total, 0 scripts / lights / emitters (stripped), anchored, only parts >= 4 studs collide, shadows only >= 8 studs. Kit parts go invisible + non-colliding (state saved, ClearWorld restores). All POI anchors stay >= MinClear (harness `tools/probes/j67_b2_harness.py`). Town houses, rebirth zones (JOB 69 in progress), heist / landmark / gutted cache kits NOT touched.
- **Batch 3 (`Job67DressConfig.Wrecks`):** Synty Polygon Military Vehicles 119390702773907 destroyed meshes (1 MeshPart each) over 14 POI Part wrecks (Airstrip, FortI, FortS, Depot x2, OilField, Ruins x2, Crash x2, Quarry x2, RidgeCamp, DuneCamp heli); Collide = "Kit" so the old Part wreck stays the invisible collider (cover / NPC posts unchanged). Fix: pack models scaled relative to their own scale (Synty ships at 2).
- **Owner gate:** a world block dresses once a player it is live for (Shaun) is in the server; checked live on place 212: Live(owner)=true, Live(other)=false.
- **Checks:** BuyPathStatic **PASS=9066 FAIL=0** (bud PASS=9115 FAIL=0 after listing the new ids in CLAUDE.md); new `tools/checks/codebot_v214.py` (83 asserts).
- **Not shipped (blockers):** Sketchfab picks need a signed-in download; CGTrader B04 needs Blender decimation; drivable Synty bodies need per-vehicle seat calibration.

## v213 PUBLISHED (Code Bot Roblox, 2026-10-02 01:20 Dublin): Open Cloud place version 211. Golden Pumpjacks +15% base-income boost LIVE FOR EVERYONE
- **Commits:** code+dist+checks `041e776` on phase-7-polish (from v212 `e4e9a55`); bud merge `4c69fae` into claude/desktop-bud. WE_Build **213**. PreferMesh OFF; StreamingEnabled OFF; `WE_Building*` untouched; no price / Id / save-key change. Servers NOT restarted.
- **Public flip:** the one config line `MonetizationConfig.GoldenBoost.OwnerFirst = false`. Existing `Entitlements.GoldenPumpjack` buyers now get +15% on all steady base income (`passive` / `training` / `plot_oil`); non-owners see the same public Golden Pumpjacks row / description. The Shop display stays live from `WE_IncomePerSec`, including the `+$N/s` gain (example: $2,105/s -> `+$316/s`).
- **Checks:** `LUAU_COMPILE=$HOME/.local/bin/luau-compile python3 tools/BuyPathStatic.py` **PASS=8983 FAIL=0**; `tools/checks/codebot_v210.py` public expectations PASS; new `tools/checks/codebot_v213.py` explicitly asserts the non-owner is live, receives the +15% multiplier, and sees the `+$N/s` display. rojo build -> `dist/WarEmpire-PERF.rbxlx`, copied to `dist/WarEmpire.rbxlx`.
- **Publish:** HTTP 200, versionNumber **211**, universe 10767159222 / place 97112936860418. **Servers NOT restarted.**

## v212 PUBLISHED (Code Bot Roblox, 2026-10-02 01:15 Dublin): Open Cloud place version 210. Supply Depot board text big on phones + AIRDROP guide line can be hidden (both NEW-OWNER-FIRST)
- **Commits:** code+dist+checks `9d8fc55` on phase-7-polish (from v211 `9f11ee5`); bud merge into claude/desktop-bud (+ this handoff). WE_Build 212. PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; no price / Id change; existing save keys untouched (one NEW key, below).
- **Boards (Shaun: "the writing on the upgrade / pass boards is far too small on my phone"):** the Supply Depot stand signs (`Server/Modules/PurchaseStands.BuildSign`, SurfaceGui `WE_PremiumBillboard`, unchanged on the server) are re-laid out on the viewer's client by new `Client/Modules/StandSignBig` (started from FeatureController) with the pure `Shared/Util/StandSignLayout.Big`, only while `MonetizationConfig.BigSignLiveFor` (`PremiumPads.BigSign`: `Enabled = true`, `OwnerFirst = true`). Panel 6.4 x 3.4 -> **7.0 x 4.2 studs**, grows UP only (posts / hologram untouched; W <= Depot.Step - 5, neighbours never overlap), 60 px/stud. Bold GothamBlack name (Max 66 / Min 34 px), ONE GothamBold effect line (Max 54 / Min 34), price / OWNED pill (Max 64 / Min 38). Effect text = new `MonetizationConfig.EffectFor` (speed from `SpeedText` short; else the new `Effect` field: AutoCollect "Auto-collects cash", DoubleCash "2x cash, forever"; else the Shop Description). Golden Pump stand (no PadSlot) NOT touched (v210 lane). Event-only (tag + OfferKey signals), no Heartbeat / loop.
  - Measured (Montserrat metrics, studs of text height): title Auto Collect / Speed Boost 0.60 -> 0.72, 2x Cash 0.97 -> 1.10, Speed Pass 0.65 -> 0.78; effect 0.30-0.45 ("Your ATM cash is collected for you", "Run 2.5x faster, forever") -> 0.62-0.78 ("Auto-collects cash", "Run 2.5x faster"); price 0.73 -> 1.07, OWNED 0.58 -> 0.73.
- **Airdrop guide line (Shaun):** `SupplyDropConfig.GuideHide` (`Enabled`, `OwnerFirst = true`). FeatureController: a big "✕  HIDE LINE" button (220 x 64 v, HUD top stack order 31, touch target asserted) while the AIRDROP line shows; tap = `ObjectiveMarker.Clear()` (Beam + attachments + marker destroyed) and that airdrop never re-guides automatically; a new airdrop guides again. Settings > AIRDROPS "Airdrop guide line: ON / OFF" (OFF also clears a showing line) saved in the NEW key `profile.Settings.AirdropGuideOff` (true | nil) by new `Server/Services/AirdropGuideService` (remote `RequestAirdropGuideSetting`: RemoteGate boolean schema, rate limit 1/s, refused unless live), mirrored as `WE_AirdropGuideOff`. The Shop FREE Airdrop TRACK row still guides on an explicit tap.
- **Checks:** BuyPathStatic **PASS=8951 FAIL=0**; `tools/checks/codebot_v212.py` (78 PASS: runs the real layout + EffectFor in Luau; every title / effect / price / OWNED fits at >= its MinTextSize with 8 % headroom, no box overlaps, all inside the edge; owner-first; no hard-coded text in the client; PurchaseStands byte-identical; prices + Ids identical; Luau sim of the hide logic: HIDE removes the beam, same airdrop stays hidden, new one guides, Settings OFF = none, non-owner unchanged). Scoped pins: codebot_v194 / v195 ignore only the new Constants remote-name line; v207 counts the BigSign OwnerFirst as a separate later flag; v211's SupplyDropConfig byte-identical pin is v211-scope.
- **Publish:** HTTP 200, versionNumber **210**, universe 10767159222 / place 97112936860418. **Servers NOT restarted** (new servers / rejoin get WE_Build 212).
- **Phone test (Shaun, new server, WE_Build 212):** (1) walk to your base Supply Depot and stop ~10-15 studs from the three stands: each board shows a big name, one short yellow effect line and a big R$ / ✓ OWNED pill, nothing cut off or overlapping. (2) Wait for "Airdrop incoming!": tap the big "✕ HIDE LINE" button under the top bar: the yellow line and AIRDROP marker vanish and stay gone for that drop; then Settings > AIRDROPS > "Airdrop guide line: OFF" and the next airdrop shows no line.
- **Next:** if Shaun is happy, flip `PremiumPads.BigSign.OwnerFirst` and `SupplyDropConfig.GuideHide.OwnerFirst` to false.

## v211 PUBLISHED (Code Bot Roblox, 2026-10-02 01:09 Dublin): Open Cloud place version 209. "AIRDROP FRENZY · 2d 23h left" top banner HIDDEN for everyone (display only)
- **Commits:** code+dist+checks `c6b710c` on phase-7-polish (from v210 `08d3f8f`); bud merge `af43697` into claude/desktop-bud (+ this handoff). WE_Build 211. PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; save keys unchanged (Base/Data/EarlyRemotes diff = the WE_Build number only).
- **What it was:** `WE_EventBanner` (Client/Modules/EngagementClient `start()`), the claude-bud JOB 13 weekly event rotation (`EngagementConfig.Events`, `Rollout.Events = "all"`; EngagementService sets `WE_Engagement` on join). Week n runs Events[n % 3]: DOUBLE CASH WEEKEND / PLAZA WAR WEEK / AIRDROP FRENZY. This weekend (Fri 2 Oct 01:00 – Mon 5 Oct 01:00 Dublin) = AIRDROP FRENZY.
- **Change:** new `EngagementConfig.ShowEventBanner = false`; the client returns before building the banner. `true` = the banner as before (all three rotation events). Leaderboards still start (before the switch).
- **Gameplay NOT changed (reported, kept as asked):** AIRDROP FRENZY sets `AirdropIntervalSeconds = 180` -> airdrops every 3 min on its weekend instead of `SupplyDropConfig.Airdrop.IntervalSeconds = 600` (EngagementService). Still live, just no banner. The other rotation effects (2x cash on DOUBLE CASH WEEKEND, 2x plaza bounty on PLAZA WAR WEEK) also keep running without a banner. Normal airdrops and the DOUBLE WEEKEND "2x WEEKEND" chip (EventConfig / DoubleWeekendController) untouched (byte-identical).
- **Checks:** BuyPathStatic **PASS=8873 FAIL=0**; `tools/checks/codebot_v211.py` (switch off, client gate before the banner, EngagementConfig identical to v210 outside the switch block, EngagementService / SupplyDropConfig / SupplyDropService / EventConfig / DoubleWeekendController byte-identical, Luau sim of the real config: AirdropFrenzy live now with 180 s, 2d 23h left); `tools/engagement_gate_test.py` PASS=52 FAIL=0. rojo build -> dist/WarEmpire-PERF.rbxlx copied to dist/WarEmpire.rbxlx (identical). WE_Build pins 210 -> 211.
- **Publish:** HTTP 200, versionNumber **209**, universe 10767159222 / place 97112936860418. **Servers NOT restarted** (players lose the banner on next join / new server).

## v210 PUBLISHED (Code Bot Roblox, 2026-10-02 01:04 Dublin): Open Cloud place version 208. Golden Pumpjacks fixed: +15% of ALL base income (OWNER-FIRST)
- **Commits:** code+dist+checks `bf62507` on phase-7-polish (fast-forward from v209 `7ee7fce`, which also brings v209 onto phase-7-polish); bud merge into claude/desktop-bud (+ this handoff). WE_Build **210**. PreferMesh OFF; StreamingEnabled OFF; `WE_Building*` untouched; no price / Id / save-key change. Servers NOT restarted.
- **Root cause (Shaun: girlfriend Laumartinez26 bought it, $2,105/s -> $2,107/s):** `DevProducts.GoldenPumpjack` (49 R$, `IncomeMult = 1.5`, "Gold oil pumps that earn 50% more, forever") only fed `PlotOilPumpService`'s pump tick: `cash * (n - golden) + floor(cash * 1.5) * golden` with `PlotOilPumpConfig.CashPerTick = 18` per 5 s, 2 pumps, and `plot_oil` is in `CashMultExemptReasons` (no prestige / VIP / 2x). Pumps = $7.20/s of any base; gold = +$1.80/s per pump, +$3.60/s max. True to the words, worthless in practice.
- **New effect (`MonetizationConfig.GoldenBoost`, THE config):** `Enabled = true`, `OwnerFirst = true` (NEW-OWNER-FIRST), `IncomePct = 15`, `Reasons = passive / training / plot_oil` (= `TycoonGuideConfig.SteadyIncomeReasons`, exactly what `WE_IncomePerSec` sums). `EconomyService.cashMultFor` multiplies those grants x1.15 for anyone with `Entitlements.GoldenPumpjack` while live (outside the exempt branch, so oil too); `PlotOilPumpService` drops the legacy per-pump x1.5 while live. Gold pumps stay gold. Permanent. Example: $2,105/s -> about $2,421/s (+$316/s).
- **Shop:** Golden Pumpjacks row = "+15% income forever · +$316/s" (live from `GoldenBoostGainPerSec(WE_IncomePerSec)`, `TycoonMath.ShortCash` K/M/B/T, updates while the Shop is open); owned = "+15% income active · +$N/s". Purchase stand / DescFor = "+15% on all your base income, forever". 11 s after buying: toast "Golden Pumpjacks ON: income now $X/s (+$N/s)" from the real `WE_IncomePerSec`. The Roblox purchase sheet itself still shows the Creator Hub product description (not editable from code).
- **Non-owners (incl. existing buyers):** legacy effect and text, unchanged, until `GoldenBoost.OwnerFirst = false`. The flip needs no migration: existing owners (her saved `Entitlements.GoldenPumpjack`) get +15% the moment it is public.
- **Checks:** BuyPathStatic **PASS=8850 FAIL=0**; `tools/checks/codebot_v210.py` (31 pins: config/effect/display agree, Reasons == SteadyIncomeReasons, Description from IncomePct, no LiveBlock, prices identical to `7ee7fce`, save keys, Luau sim of the real MonetizationConfig + TycoonMath: shown gain == real gain on 4 income profiles, "+$316/s" at $2,105/s, phone width). `run_shop_render_test` loads the real TycoonMath; v167 / v207 pins exclude the new block; `run_codebot_v168_test` HVT check fixed for days whose daily row has the HVT's Kind (it failed from 01:00 Dublin on 7ee7fce; test only).
- **Other weak / unclear income products (NOT changed):** 2x Offline Cash (149 R$: doubles the cap 2 h -> 4 h, not the rate; nothing extra if offline < 2 h); VIP ("+50% cash" via the overhaul, legacy text "+25% cash on everything you earn"; skips every CashMultExemptReasons source: oil, jobs, supply drops, bank raid, clan war, offline...); 2x Cash ("Double your cash income", same exemptions); Golden Pumpjacks legacy for non-owners (+$3.60/s max; the pump label still says $18 while a gold pump pays $27).
- **Phone test (Shaun):** new server (WE_Build 210) -> Shop SUPPLY · R$: Golden Pumpjacks row reads "+15% income forever · +$N/s" where N ~= 15% of your cash-pill $/s; buy it (49 R$) -> within ~11 s a toast "income now $X/s (+$N/s)" and the cash pill $/s is ~15% higher; reopen the Shop -> row OWNED "+15% income active". Then flip `GoldenBoost.OwnerFirst = false` for everyone.

## v209 PUBLISHED (Code Bot Roblox, 2026-10-02 00:54 Dublin): Starter5 public offer delay 300 -> 120 seconds
- **Commits:** code/checks/dist `61a7fb5` on `codebot/starter5-120`; merged into `claude/desktop-bud` as `5928a0b` (+ bud marker `1b965f4`). WE_Build **209**; Open Cloud place version **207**. PreferMesh OFF; StreamingEnabled OFF; `WE_Building*` untouched; no price or product Id changes. Servers were not restarted.
- **Change:** `MonetizationConfig.Starter5.OfferAfterPlaySeconds = 120`; `OwnerFirst = false` remains public and `Starter5Offered` remains once per player. The two products remain 5 R$: StarterRecruit5 `3715888533`, Boost2x10m `3715888566`.
- **Timing reality:** total saved play time reaches 120 s and `ClaimSoftOfferSlot`'s 120 s quiet window expires at the same point, so an eligible player normally sees the card at about **120–125 s** (the 5 s RecruitPackService tick), not 240 s. Guided tutorial `HoldMaxSeconds = 300` can defer the first send to about **300–305 s** if onboarding is still active; it was intentionally not changed. The client `ClientWaitMaxSeconds = 90` is a wait cap while driving/dead/recently in combat/modal, not an added join delay; a persistently blocked card is dropped and retried by the existing 30 s server retry path. No other timing system was changed.
- **Laumartinez26 investigation:** public Roblox username lookup gives UserId **11718087109**. Presence reported online but returned no place/universe/server id; Open Cloud DataStore inspection returned **403** because the key lacks `universe-datastores.objects:read`, so her saved `Starter5Offered` / entitlement cannot be read from here. In source, `RecruitPackService.Decide` (lines 61–87) blocks only not-live, Id 0, `Starter5Offered`, StarterRecruit5 entitlement, pending card/tries, too early, onboarding, recent combat, or seated; another product (including the 49 R$ Recruit Pack) does **not** exclude her. The flag is set only after the client confirms `shown` (lines 227–255), not on purchase.
- **Shop screenshot diagnosis:** v207's `ShopController.applyPriceOrder` (lines 1246–1288) puts FREE rows first, then paid rows by price, then Favorite/locked no-price rows. `run_shop_render_test.py` proves this for uid 9 (non-owner, 0 failures) and shows both 5 R$ rows immediately under FREE. The screenshot order (Favorite / Recruit Pack 49 / War Chest 799 / 2x Cash 149, no 5 R$ rows) therefore cannot be a v207 client; it indicates an older/stale server or client. No shop bug was found to fix. Join a new server / migrate to latest update; existing servers were not restarted.
- **Checks:** `LUAU_COMPILE=$HOME/.local/bin/luau-compile python3 tools/BuyPathStatic.py` -> **PASS=8819 FAIL=0**; `tools/checks/codebot_v209.py` -> 0 failed; `run_starter5_test.py` -> 0 failed; `run_shop_render_test.py` -> all six owner/non-owner runs 0 failed. rojo artifacts `dist/WarEmpire-PERF.rbxlx` and `dist/WarEmpire.rbxlx` are identical (7,843,676 bytes).
- **Publish:** HTTP 200, versionNumber **207**, universe 10767159222 / place 97112936860418. Do not restart servers.

## v208 PUBLISHED (Code Bot Roblox, 2026-10-02 00:38 Dublin): Open Cloud place version 206. JOB 67 remainder BATCH 1 = walls + base props from Shaun's owned packs (OWNER-FIRST)
- **Commits:** code+dist+checks `e3e498c` on phase-7-polish (from v207 `f0f5f9e`); bud merge `8838bc6` into claude/desktop-bud (+ this handoff). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; save keys unchanged (Base/Data/EarlyRemotes diff = the WE_Build number only); no price change. JOB 67 remainder stays "IN PROGRESS by Code Bot" (batches 2 town/outpost/rebirth buildings + 3 Synty vehicles to come).
- **One config:** `Shared/Configs/Job67DressConfig` (Enabled / OwnerFirst master + `Walls` and `BaseProps` blocks, each Enabled + OwnerFirst = true; the owner = the BASE owner, so only Shaun's base wears it, everyone who visits sees it). Server: `Services/Job67DressService` (packs loaded once per server via InsertService, scripts / lights / sounds / effects / prompts / guis / humanoids / joints stripped, clones Anchored + CanCollide / CanQuery / CanTouch off, CastShadow off except Hesco, RenderFidelity Automatic as shipped: not writable at runtime, probe `tools/probes/j67_fidelity_write.luau`).
- **Walls (wall tier = saved DefensiveWalls level, decoration only, the Part walls stay the colliders):** L1 Sandbag Line (gate sandbag runs, 14 parts) -> L2 Sandbag Wall (gate + sides + corner stacks, 48) -> L3 Hesco Gate (6 Hesco PBR on the gate face + sides sandbags + wire, 44 parts, ~103k tris) -> L4 Hesco Wall (12 Hesco gate + sides, rear sandbags, wire, blockades, 40 parts, ~207k tris) -> L5 Hesco Fortress (12 Hesco + 6 gate stacks, 6 wire, 4 blockades, trench nests on the 4 corners, 46 parts, ~207k tris). The Part wall segments behind a Hesco run go transparent (still collide). Hesco = 17,247 tris each, capped (MaxHesco 6/12/14).
- **Base props (tier = sum of saved structure levels; 1/10/22/38/55):** Military Supplies + Trench Sandbags + Textured Crates clusters at the BaseLife spots: 31 / 67 / 98 / 134 / 140 pieces (MaxPieces 140, 1 MeshPart each). They replace the BaseLife Part kits CrateStack / DrumGroup / SandbagNest / SandbagLine / ContainerStack and hide that base's PlotWarzone Part props (restored if switched off). Rebuilt on plot ready and on every upgrade.
- **Switch back:** `Job67DressConfig.Enabled = false` (all), or `Walls.Enabled` / `BaseProps.Enabled`; public = `OwnerFirst = false` with the big flip.
- **Checks:** BuyPathStatic **PASS=8826 FAIL=0**; `tools/checks/codebot_v208.py` (owner-first pins, the 4 pack ids in config + ASSET_LICENSES + wire-asset-ids DRESS-LIVE rows, strip list, no collide/query/touch, no lights / per-frame work, SyncPerimeterWalls -> DressWalls deferred, BaseLife kit skip, Bootstrap init, MonetizationConfig / BaseConfig byte-identical to f0f5f9e, DataService only the WE_Build number, Luau config sim: tiers rise L1..L5, Hesco budget <= 250k). `_XP_HANDONS` pin for the read-only LevelSum(prof.BaseUpgrades). Open Cloud Luau harness (`tools/probes/j67_b1_harness.py`, real service source, place 205): every tier built with 0 lights / 0 scripts / 0 colliders; live place 206: modules present, Live(owner)=true, Live(uid 9)=false. Audit: `docs/we_check2_job67_b1.txt`. (bud: FAIL=2 pre-existing / Claude WIP: JOB69 HowTo, codebot_v202 ExperienceNotify ship-only pin.)
- **Publish:** HTTP 200, versionNumber **206**, universe 10767159222 / place 97112936860418. **Servers NOT restarted** (new servers run WE_Build 208; restart = Creator Hub "Migrate to Latest Update", the key lacks universe:write).
- **Phone test (owner):** join a NEW server (WE_Build 208). At your base: walls show sandbags (L1-2) or the concrete Hesco blocks (L3+) on the gate face; upgrade DefensiveWalls -> the dressing rebuilds a tier up within ~1 s. Crates / sandbag nests / drums around the base grow with base upgrades; the old grey Part crate stacks and the warzone Part props on your plot are gone. Walk through the gate and along the walls: collisions = the same as before. A second (non-owner) account's base keeps the old look.

## v207 PUBLISHED (Code Bot Roblox, 2026-10-02 00:33 Dublin): Open Cloud place version 205. Supply R$ tab FREE rows back on TOP + the two 5 R$ offers PUBLIC (LIVE FOR EVERYONE)
- **Commits:** code+dist+checks `3b92f61` on phase-7-polish (from v206 `b37361c`); bud merge `202ad15` into claude/desktop-bud (+ this handoff). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; save keys unchanged (Base/Data/EarlyRemotes diff = the WE_Build number only).
- **1. Order (Shaun approved):** `ShopController.applyPriceOrder` now sorts by tier first: FREE rows (`fr_*` keys except `fr_favorite`: FREE · Daily Reward, FREE · Airdrop, FREE · Invite friends; FREE · Join our group too once a GroupId is set) on TOP in build order -> paid rows by `MonetizationConfig` RobuxPrice ascending (v206 sort, OWNED after unowned at the same price) -> no-price rows (Favorite WAR EMPIRE, Supply Crate (locked)) at the bottom.
- **Top of shop now (non-owner, shipped config):** FREE · Daily Reward · FREE · Airdrop · FREE · Invite friends · 2x Income 10 min 5 · Recruit Starter Pack 5 · 15 MIN OF CASH 25 · Recruit Pack 49 · 30 MIN OF CASH 49 · Golden Pumpjacks 49 · Instant Army Refill 49 · Plaza Airstrike 79 · 1 HOUR OF CASH 89 · ... · Armory Pass 1299 · Favorite WAR EMPIRE · Supply Crate (locked).
- **2. Public:** `MonetizationConfig.Starter5.OwnerFirst` true -> **false** (the one line; StarterRecruit5 "Recruit Starter Pack" 3715888533 + Boost2x10m "2x Income 10 min" 3715888566 follow it via LiveBlock = "Starter5"). Delay stays **300 s**; the 5 R$ card stays once per player (`profile.Starter5Offered`); Recruit Starter Pack still OneTime. No other OwnerFirst flag, no price / Id changed. Note: with Starter5 live for everyone, the 300 s 5 R$ card replaces the old 10-min Recruit Pack (49 R$) pop-up for every player (same as the owner had since v204); the Recruit Pack row stays in the shop.
- **Checks:** BuyPathStatic **PASS=8791 FAIL=0**; `tools/checks/codebot_v207.py` (tier sort static, ShopController identical to v206 outside the tier lines, every RobuxPrice identical to `b95305c`, MonetizationConfig diff = the Starter5 OwnerFirst line only, only 1 OwnerFirst line changed in src, Luau sims: FREE rows top / ascending / no-price last for owner + uid 9, uid 9 sees both 5 R$ rows right under FREE, uid 9 gets the 300 s card once); owner-only Starter5 pins in codebot_v202 / v204 / v206 / claude_bud_job66 scoped to builds <= 206; `run_starter5_test` 0 failed; `run_recruit_pack_test` 0 failed. rojo build -> dist/WarEmpire-PERF.rbxlx copied to dist/WarEmpire.rbxlx (identical). (bud: codebot_v202 "ExperienceNotify NOT shipped" FAIL is pre-existing on bud, ship-only pin.)
- **Publish:** HTTP 200, versionNumber **205**, universe 10767159222 / place 97112936860418, 00:33 Dublin. **Servers NOT restarted** (players get WE_Build 207 on next join / new server; restart needs Creator Hub "Migrate to Latest Update", the key lacks universe:write).
- **Phone test:** new server, non-owner account: Shop > SUPPLY · R$ top = the three FREE rows, then 2x Income 10 min 5 R$ + Recruit Starter Pack 5 R$; after ~5 min of play the "5 R$ ONE-TIME OFFER" card, once.

## v206 PUBLISHED (Code Bot Roblox, 2026-10-02 ~00:20 Dublin): Open Cloud place version 204. Supply Depot 'SUPPLY · R$' tab cheapest first + Starter5 pop-up back to 300 s
- **Commits:** code+dist+checks `b95305c` on phase-7-polish (from v205 `bf0cc52`); bud merge `e841e20` into claude/desktop-bud (+ this handoff). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; save keys unchanged (DataService diff = the WE_Build number only).
- **Change (display order only, owner-approved):** `ShopController.applyPriceOrder` re-numbers every SUPPLY row's LayoutOrder by `MonetizationConfig` RobuxPrice ascending (pass rows `Pass_<key>` -> GamePasses, others -> DevProducts). Rows with no Robux price (FREE Daily Reward / Airdrop / Invite, Favorite WAR EMPIRE, locked Supply Crate) go to the bottom (the FREE rows were at the top before). Same price: unowned first, OWNED one-time product / pass after (re-sorted on every OWNED refresh), then the old build (JOB 36 overhaul) order. No price / Id / prompt / rollout change; the Starter5 rows are still only built where `Starter5LiveFor` (owner-only). The cash "+" still scrolls to 4 HOURS OF CASH (rowCanvasY follows LayoutOrder).
- **Order now (owner, shipped config):** 2x Income 10 min 5 · Recruit Starter Pack 5 · 15 MIN OF CASH 25 · Recruit Pack 49 · 30 MIN OF CASH 49 · Golden Pumpjacks 49 · Instant Army Refill 49 · Plaza Airstrike 79 · 1 HOUR OF CASH 89 · Auto Collect 99 · Speed Boost 99 · Double XP 99 · Sovereign Gold Pistol 99 · 2x Cash 149 · 2x Offline Cash 149 · 2 HOURS OF CASH 159 · VIP 199 · Double HP 199 · Razorfang GT 199 · Extra Garage Slot 199 · Commander Starter Bundle 249 · Bigger Army 249 · Quake GL 249 · 4 HOURS OF CASH 279 · Longshot 299 · Tidebreaker 299 · Super Soldiers 349 · Havoc 349 · Thunderhead 399 · Battle Pass Premium 499 · Tempest 499 · War Chest 799 · Warlord 799 · Skylance 899 · Stormwing 999 · Leviathan 1199 · Armory Pass 1299 · then FREE Daily / Airdrop / Invite, Favorite WAR EMPIRE, Supply Crate (locked). Non-owners: the same without the two 5 R$ rows (15 MIN OF CASH first).
- **Starter5:** `MonetizationConfig.Starter5.OfferAfterPlaySeconds` 60 -> **300** (Shaun's phone test passed). OwnerFirst still true.
- **Checks:** BuyPathStatic **PASS=8762 FAIL=0**; `tools/checks/codebot_v206.py` (sort static, ShopController identical to v205 outside the sort block, every RobuxPrice identical to `fe6792b`, MonetizationConfig diff = the delay line only, ShopOverhaulConfig / LivePrices / MonetizationService / RecruitPackService / EconomyConfig / ProfileSchema byte-identical, Luau sim of the real Shop: ascending in all 6 runs, owner's top two = the 5 R$ rows, no 5 R$ row for uid 9, 300 s). Scoped: 60 s pins in codebot_v202 / codebot_v204 / claude_bud_job66 -> builds 204-205 only (live = 300); run_starter5_test expects 300; run_shop_render_test time rows cheapest first + a new ascending-order assertion. WE_Build 205 -> 206.
- **Publish:** HTTP 200, versionNumber **204**, universe 10767159222 / place 97112936860418. **Servers NOT restarted** (as asked; players get WE_Build 206 on next join / new server).
- **Phone test:** new server, Shop > SUPPLY · R$: owner sees "2x Income 10 min 5 R$" + "Recruit Starter Pack 5 R$" at the top (Recruit Starter Pack below 2x Income once OWNED), FREE rows / Favorite at the bottom.

## v205 PUBLISHED (Code Bot Roblox, 2026-10-02 ~00:09 Dublin): Open Cloud place version 203. DOUBLE WEEKEND notification ON for everyone (display only)
- **Commits:** code+dist+checks `fe6792b` on phase-7-polish (from v204 `52b601b`); bud merge `03a277a` into claude/desktop-bud (+ this handoff). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; save keys unchanged (DataService diff = the WE_Build number only).
- **What was gated:** the "2x WEEKEND · 2d 21h" chip under TARGETS (`DoubleWeekendController`) only showed when `EventConfig.ActiveFor` was true = the real window (Fri 2 Oct 21:00 – Sun 4 Oct 21:00 Dublin) OR the owner preview (`OwnerFirst = true` + `/eventpreview`, owner 470626172 only; the preview also turns his real 2x on early). Non-owners only had the one-time pre-start pop-up (DOUBLE WEEKEND / Fri 9pm – Sun 9pm / NOTIFY ME), which was already public; the chip was owner-only until the start.
- **Change (display only):** new `EventConfig.ChipPublic = true` -> every player sees the chip before the start as a countdown TO the start ("2x WEEKEND · in 20h 51m"; tap = details card "starts in ..."; the "(OWNER PREVIEW)" tag only when the preview is really on for him). Once the window opens it becomes the usual "2x WEEKEND · 1d 23h" (ends in) for everyone; nothing after EndUnix. Not "ends in" before the start for players, because their 2x is not on yet (it would claim a live 2x). StartUnix / EndUnix / XP / Cash / Kill mults / reasons / OwnerFirst / ActiveFor / `Server/Modules/DoubleEvent` byte-identical.
- **Checks:** BuyPathStatic **PASS=8736 FAIL=0**; `tools/checks/codebot_v205.py` (EventConfig identical to v204 outside the ChipPublic block, DoubleEvent byte-identical, no server file reads ChipPublic, Luau sim of the chip: player before start "in 20h 6m", owner preview "2d 20h", in-window live, hidden after end, player 2x still NOT active before the start); `tools/sim/event_double_weekend_verify.py` **TOTAL FAIL=0** (196 PASS). codebot_v201's EventConfig byte-identical pin now allows only the v205 ChipPublic block. WE_Build 204 -> 205.
- **Publish:** HTTP 200, versionNumber **203**, universe 10767159222 / place 97112936860418.
- **Restart: NOT done.** Open Cloud `POST /cloud/v2/universes/10767159222:restartServers` -> **403 "The required scope <universe:write> is missing"** (the repo key only has universe-places:write + luau-execution). Needs the browser: Creator Hub > War Empire > (⋯) **Migrate to Latest Update** — or add universe:write to the key. At 00:09 Dublin 7 players were in 2 public servers (4 + 1 listed). New servers already run WE_Build 205.
- **Phone test:** new server: a non-owner account sees "2x WEEKEND · in …h …m" under TARGETS; tap -> "starts in …". Owner with the preview sees "2x WEEKEND · 2d …h" as before.

## v204 PUBLISHED (Code Bot Roblox, 2026-10-02 ~00:05 Dublin): Open Cloud place version 202. JOB 66 5 R$ starter products get their Creator Hub Ids (OwnerFirst kept) + 60 s test pop-up
- **Commits:** code+dist+checks `b82cee1` on phase-7-polish (from v203 `71d63ff`); bud merge `83cbe11` into claude/desktop-bud (+ this handoff). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; save keys unchanged (DataService diff = the WE_Build number only).
- **Ids (Creator Hub, Shaun approved, 5 R$ each, regional / managed pricing OFF; created in the browser: the repo Open Cloud key has no developer-product scope, 403):** `DevProducts.StarterRecruit5` "Recruit Starter Pack" **3715888533**; `DevProducts.Boost2x10m` "2x Income 10 min" **3715888566**. Shop rows now visible to the owner only (`Starter5.OwnerFirst = true`).
- **Pop-up delay = ONE value:** `MonetizationConfig.Starter5.OfferAfterPlaySeconds = 60` (phone test). **LIVE VALUE IS 300**: set it back with that one line before OwnerFirst goes off. It counts total saved play time (`profile.Stats.PlayTimeSeconds`), so Shaun's profile is already past it: the card comes on his first quiet moment after joining (not onboarding / in combat / seated, soft-offer slot free). Shown once ever (`Starter5Offered`).
- **Checks:** BuyPathStatic **PASS=8708 FAIL=0**; `tools/checks/codebot_v204.py` (both Ids + 5 R$, OwnerFirst true, delay 60 with the live-300 comment, MonetizationConfig vs v203 = only those 3 lines, Economy / Offline / Retention / MonetizationService / RecruitPackService / ProfileSchema byte-identical, PreferMesh / Streaming OFF, no WE_Building*); `tools/sim/run_starter5_test.py` 0 failed (reads the delay); `run_recruit_pack_test.py` 0 failed (pins Starter5 Id 0 for the Recruit Pack path). Older pins moved: claude_bud_job66 + codebot_v202 Id 0 / 300 -> filled Ids / 60; codebot_v180 SKU guard allows the two Ids at 5 R$; codebot_v203 diff/scope pins scoped to WE_Build 203. WE_Build 203 -> 204.
- **Publish:** HTTP 200, versionNumber **202**, universe 10767159222 / place 97112936860418. Servers NOT restarted (players get it on next join).
- **Phone test (owner):** rejoin a NEW server, confirm WE_Build=204; within about a minute the "5 R$ ONE-TIME OFFER" card -> buy (5 R$) -> +3 soldiers + starter cash, Shop row OWNED; Shop "2x Income 10 min" (5 R$) -> green "2x m:ss" chip ~10:00; buy again -> timer extends ~+10 min. A non-owner account sees neither row nor card.
- **Next:** after the test, `OfferAfterPlaySeconds` 60 -> 300 (one line), then OwnerFirst -> false when Shaun OKs.

## v203 PUBLISHED (Code Bot Roblox, 2026-10-01 ~23:59 Dublin): Open Cloud place version 201. "2x Offline Cash" pass DESCRIPTION only (Shaun approved)
- **Commits:** code+dist+checks `0814f1a` on phase-7-polish (from v202 `fdc6c20`); bud merge into claude/desktop-bud (+ this handoff). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; save keys unchanged (DataService diff = the WE_Build number only).
- **Change:** `MonetizationConfig.GamePasses.OfflineCap2x.Description` "Offline cash builds for 16 h instead of 8 h" -> **"Offline cash for 4 hours instead of 2 hours"** (the rule since v201: free = 2 h x 10 % of income, pass owners 4 h via `OfflineConfig.PassCapMult = 2`, unchanged). Kept <= 44 chars: the shop row shows "PERMANENT · " + Description and `run_shop_render_test.py` caps a phone row sub at 56 chars (the long sentence was 85 -> FAIL). Id 2002664894, name "2x Offline Cash", **149 R$ unchanged**. No other shop text said 16 h / 8 h (Missions "Away N h" + Welcome back read OfflineConfig/server hours).
- **Checks:** BuyPathStatic **PASS=8692 FAIL=0**; `tools/checks/codebot_v203.py` (new text, Id / name / 149 R$, vs v202 only that Description line + its comment changed, OfflineConfig 7200 / 0.10 / PassCapMult 2 byte-identical, PreferMesh / Streaming OFF, no WE_Building*). The older byte-identical MonetizationConfig pins (codebot_v181-v202) are now scoped to their own build (WE_Build == N); v202's DataService pin likewise. WE_Build 202 -> 203 pins.
- **Publish:** HTTP 200, versionNumber **201**, universe 10767159222 / place 97112936860418. Servers NOT restarted.
- **Creator Hub (NOT updated):** Open Cloud `PATCH /game-passes/v1/universes/10767159222/game-passes/2002664894` -> **403 "Scope not authorized"** (the repo key has no game-pass:read/write). Live Roblox text still "Doubles how much offline cash your base can store while you're away. Permanent."; price verified **149 R$**, for sale. Needs the browser (Creator Hub > War Empire > Monetization > Passes > 2x Offline Cash > Description only): "Earn offline cash for up to 4 hours instead of 2 hours while you're away. Permanent." — or add game-pass:write to the key.
- **Phone test:** new server, Shop > SUPPLY passes: 2x Offline Cash row reads "PERMANENT · Offline cash for 4 hours instead of 2 hours", 149 R$ / OWNED.

## v202 PUBLISHED (Code Bot Roblox, 2026-10-01 ~23:52 Dublin): Open Cloud place version 200. claude-bud JOB 66 two 5 R$ starter products OwnerFirst
- **Commits:** cherry-pick `63c3870` → `1af6905` (JOB 66; docs-only JOB 69 `c96aa20` skipped — CLAUDE.md / handoff conflicts); code+dist+checks `f14a4db` on phase-7-polish (from v201 `84c50bb`). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; MonetizationConfig identical outside the exact Shaun-approved JOB 66 block; save keys unchanged except new sanitised `Starter5Offered` (ProfileSchema; no wipe).
- **JOB 66 NEW-OWNER-FIRST (`MonetizationConfig.Starter5`):**
  - **Recruit Starter Pack** (`DevProducts.StarterRecruit5`): 5 R$ one-time — 3 soldiers via `SoldierService.GrantFree` + ~2.5 min income cash as `devproduct` (never multiplied). Id **0** until Creator Hub products are created (managed pricing OFF).
  - **2x Income 10 min** (`DevProducts.Boost2x10m`): 5 R$ repeatable via `CodesService.GrantCashBoost` / central `CashBoostMult`. HUD `BoostChip` "2x m:ss" (1 Hz only while active).
  - **5 R$ ONE-TIME OFFER** at 5 min play through the RecruitPack offer path (`Starter5Offered` flag; others keep the 49 R$ Recruit Pack at 10 min).
  - `SkuLiveFor` LiveBlock = Starter5 (Shop + purchase intent owner-only until flipped).
- **Held / not this ship:** JOB 62 ExperienceNotify stays on bud only (needs `WE_NOTIFY_KEY`). JOB 67 walls / rebirth-zone buildings / props / Synty vehicles still owed. JOB 68 / JOB 69 still on Claude queue.
- **Checks:** BuyPathStatic **PASS=8669 FAIL=0**; `tools/checks/codebot_v202.py` PASS; `claude_bud_job66.py` PASS; `tools/sim/run_starter5_test.py` **0 failed**. PreferMesh OFF; StreamingEnabled OFF. Money guards (v180–v201) allow only the exact JOB 66 block.
- **Publish:** HTTP 200, versionNumber **200**, universe 10767159222 / place 97112936860418. Servers NOT restarted (players get WE_Build 202 on next join).
- **Phone tests (Shaun — owner only; rejoin / new server for WE_Build 202):**
  1. Until Creator Hub products exist (Id still 0): Shop rows stay hidden; the 5-min offer will not prompt a real purchase. Confirm `WE_Build=202` and that the BoostChip code path is live (owner-only Starter5).
  2. After Code Bot / Shaun creates the two 5 R$ products and fills the Ids (managed pricing OFF): play ~5 min → "5 R$ ONE-TIME OFFER" card → buy → +3 soldiers + starter cash; Shop row = OWNED.
  3. Buy "2x Income 10 min" → green "2x m:ss" chip; buy again → timer extends. Non-owner players must not see either product / offer.
- **Code Bot NEXT:** create the two developer products at 5 R$ each, turn OFF managed pricing, put Ids in `StarterRecruit5.Id` / `Boost2x10m.Id`. Then a real purchase test on phone.
- **Still owed:** JOB 67 remainder (walls/props/vehicles/rebirth buildings), JOB 68 shooting range, JOB 69 rebirth zones docs/impl, held JOB 62 (`WE_NOTIFY_KEY`), OwnerFirst flips after phone OK. Do NOT reopen JOB 44.

## v201 PUBLISHED (Code Bot Roblox, 2026-10-01 ~23:45 Dublin): Open Cloud place version 199. Offline "Away" cash = Shaun's rule (2 h x 10 %, everyone) + 7-day strip overlap fix
- **Commits:** code+dist+checks `49821c7` on phase-7-polish (from v200 `7a47209`); bud-skip for the v201 ship-only pins `f2e541a`; bud merge `34792f7` (+ this handoff). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; MonetizationConfig byte-identical; no price changes; save keys unchanged (DataService diff = the WE_Build number only). LIVE FOR EVERYONE (not OwnerFirst; Shaun ordered it).
- **Bug 1 root cause:** `EconomyConfig.OfflineEarnings` had `Share = 0.25`, `CapSeconds = 8 * 3600`, `PremiumBonus = 0.10` and `CapBoost.CapMult = 2` (the 2x Offline Cash pass -> 16 h); `RetentionService.ComputeOffline` / `offlineCapCash` paid perSec x min(away, cap) x 0.25 (x1.1 Premium). Shaun (pass + Premium, ~$173.6k/s non-event passive) saw "Away 16 h: earn up to $2,749,794,426".
- **Fix:** new `Shared/Configs/OfflineConfig.luau` = THE one place: `MaxSeconds = 7200`, `Rate = 0.10`, `PassCapMult = 2`, `PremiumBonus = 0`; `OfflineConfig.Earnings(away, perSec, cap?, mult?) = floor(min(away, cap) x perSec x Rate)`. RetentionService (grant, capSecondsFor, OfflineCapCash for the Missions line, NotifyState), MissionController (Away line fallback), RetentionController (Welcome back "(capped at N h)" / "(N h max)", Premium tag only if PremiumBonus > 0) all read it. EconomyConfig.OfflineEarnings keeps only switches. Double Weekend unchanged: offline NOT in `EventConfig.ExtraCashReasons`; the v185 in-window `DoubleEvent.OfflineFactor` stays as before.
  - $349,376/s away 16 h: OLD $2,515,507,200 (8 h x 25 %; $5,031,014,400 with the pass) -> NEW **$251,550,720** (2 h x 10 %; $503,101,440 with the pass = 4 h).
  - **Judgement call:** the paid "2x Offline Cash" pass (2002664894, 149 R$) still doubles the cap TIME (2 h -> 4 h) so buyers keep what they paid for; set `OfflineConfig.PassCapMult = 1` for a hard 2 h for everyone. Its description ("16 h instead of 8 h") in MonetizationConfig + the Creator Hub is now stale (left untouched: no Robux/MonetizationConfig changes) -> needs "4 h instead of 2 h" when Shaun OKs.
- **Bug 2 root cause:** `Client/Modules/StreakStrip.luau` had its own k-only `ShortCash` ("$624953.3k") and `bottom.TextScaled = false` on fixed-width tiles (56 px) without clipping, so D7 spilled over D6. D7's value = `DailyRewardConfig.Day7Scale.IncomeMinutes = 60` min of income.
- **Fix:** tiles use the shared `TycoonMath.ShortCash(n, true)` (now K/M/B/T: "$2.7B", "$1.2T"); labels TextScaled + UITextSizeConstraint (max = panel text size, min 6), no wrap; tiles share the strip width (`1/days` scale) with ClipsDescendants; the Missions strip takes the row width (UISizeConstraint = natural width). D7 = one full offline cap: `IncomeMinutes = OfflineConfig.MaxSeconds x Rate / 60` = 12 min (was 60): Shaun's D7 ~$625M -> ~$125M ("$125M").
- **Checks:** BuyPathStatic **PASS=8639 FAIL=0**; `tools/checks/codebot_v201.py` (formula executed in Luau: $1M/2 h -> $100k; 349,376/s x 16 h -> 251,550,720; D7 = MaxSeconds x Rate / 60; strip uses the formatter + TextScaled + clip); `run_offline_test.py` / `run_daily_return_test.py` 0 failed (now read OfflineConfig). Retired pins (8 h / 0.25 / CapMult 2 / EconomyConfig byte-identical) in claude_bud_job29/49, codebot_v176/v180/v195, codebot_v200 scope pins (v200-only). On claude/desktop-bud BuyPathStatic shows 5 pre-existing FAILs from Claude's unshipped work (J61 CLAUDE.md, JOB69 zones/HowTo, v199 ExperienceNotify/Monetization) — not v201.
- **Publish:** HTTP 200, versionNumber **199**, universe 10767159222 / place 97112936860418. Servers NOT restarted (players get WE_Build 201 on next join).
- **Phone tests (Shaun — new server for WE_Build 201):**
  1. Missions panel: "Away 4 h: earn up to $~250,000,000" (you own the pass; 2 h x 10 % without it) instead of $2.7B.
  2. 7-day row: D1..D7 labels sit inside their tiles, D7★ shows "$125M" (not "$624953.3k"), no overlap in portrait.
  3. Leave >= 2 h, rejoin: Welcome back card = about 10 % of 2 h (4 h with the pass) of income, "(capped at 4 h)".
- **Next:** Shaun to decide the pass (keep 4 h or PassCapMult 1) + update its description. Same owed items as v200.

## v200 PUBLISHED (Code Bot Roblox, 2026-10-01 ~23:34 Dublin): Open Cloud place version 198. JOB 67(1) turret tiers PROMOTED (Minigun Turret Pack, OwnerFirst)
- **Commits:** code+dist+checks `8572c7a` on phase-7-polish (from v199 `8a77631`). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; MonetizationConfig byte-identical to v199; no price changes; save keys unchanged (DataService diff = the WE_Build number only).
- **WE_CHECK2 done headlessly** (Open Cloud Luau Execution on the live place v197, the same path as WE_CHECK / JOB 40C; no Studio): `docs/we_check2_minigun_v200.txt` (tools/WeCheck2.luau with IDS = {109072907337393}) + `docs/we_check2_minigun_v200_pieces.txt` (`tools/probes/v200_minigun_pieces.luau`, `tools/probes/v200_minigun_tier_fit.luau`).
  - Pack = Folder "Minigun Turret Pack by Hoshizora_N1" with 10 Models `minigun_l01`..`minigun_l10`, **4 MeshParts each** (Base > TurretYaw > GunPitch > BarrelRotation; 40 total, loader=40), **1 Script `README`** (stripped by the loader), 0 Humanoids / seats / sounds / decals / FX. All 40 meshes + the one texture 84073200037307 uploaded by the seller Hoshizora_N1 (economy API).
  - **Triangles:** Creator Store says **26,380 for the whole pack** (10 levels, 47,224 verts). Per-piece triangles cannot be read headlessly: `AssetService:CreateEditableMeshAsync` -> "no permission to load asset" (meshes not forkable) and asset delivery is 403. The 5 pieces used are a subset of the 26,380 (one gun ≈ 2.6k average); a single piece could only pass 20k if the other nine summed under 6,380. **Phone frame-rate check at Guns L10 (T5) carries this** (same rule as VehicleBodyMaxTriangles: "a script cannot read a mesh's triangle count").
- **Tier map:** T1 = `minigun_l01` (Guns 0), T2 = `minigun_l03` (Guns 1-3), T3 = `minigun_l05` (4-6), T4 = `minigun_l08` (7-9), T5 = `minigun_l10` (10). `Yaw = 180` (every pack part faces -Z, barrels on +Z). Size grows per tier: `LongAxisStuds` 5.5 / 5.8 / 6.1 / 6.5 / 7.0 -> on-site 5.0x2.6x5.5, 5.4x2.8x5.8, 5.8x3.3x6.1, 6.3x3.5x6.5, 6.9x3.9x7.0 (live fit probe; barrel ahead on -Z for all five).
- **Code (GateDefenseService, tier path only; today's AutoGun / nests / bags unchanged):**
  - `AimHitbox = true` tier refs: `prepareAimTemplate` adds one invisible `WE_AimHitbox` Part over the piece (front -Z after the Yaw, CanCollide/CanTouch false, CanQuery true) as the aim part + Turret HP hitbox (Yaw 180 left no part facing -Z, which used to mean "refused").
  - `scaleModelLongAxis(..., relative)`: the pack pieces carry `GetScale()` ≈ 0.0195 (L10 0.0364) from their import; an absolute `ScaleTo` would blow them up ~50x (probe saw 255 studs). Tier pieces now scale from their own scale.
- **Promote:** `tools/wire-asset-ids.py promote MinigunTurretPack --we-check docs/we_check2_minigun_v200.txt --offline --got` (the store gate only accepts FREE assets; this pack is PAID, so the inventory API check (OWNED) + the live LoadAsset stand in). STORE record added; `docs/ASSET_LICENSES.md` row; ASSET_WIRING status = promoted (live); journal in `docs/asset_wiring.json` (demote works).
- **Checks:** BuyPathStatic **PASS=8597 FAIL=0**; `tools/checks/codebot_v200.py` PASS; `claude_bud_job67.py` pin now expects the promoted refs; `codebot_v199.py` accepts PENDING or promoted; `tools/sim/run_turret_tier_test.py` **0 failed** (now asserts Lvl 1/3/5/8/10, Yaw 180, AimHitbox, rising LongAxisStuds). WE_Build 199 -> 200 pins. Post-publish probe on place v198: the 5 refs read promoted, Job67 OwnerFirst=true, StreamingEnabled=false.
- **Publish:** HTTP 200, versionNumber **198**, universe 10767159222 / place 97112936860418. Servers NOT restarted (rejoin / new server for WE_Build 200).
- **Phone tests (Shaun, owner-only while Job67 OwnerFirst):**
  1. New server: your gate turrets are the Minigun pack (Guns level -> tier above), barrel pointing out and turning onto targets; other players' bases keep today's tripod gun.
  2. Buy a Turret Guns level across 0 -> 1, 3 -> 4, 6 -> 7, 9 -> 10: the turret gets bigger / more detailed each tier (after the base re-syncs).
  3. Shoot a turret (Turret HP): hits count on the turret body; it smokes when down and comes back.
  4. Frame rate at Guns 10 with the gate in view (Graphics 3 / mid Android) — the triangle check the script could not do.
- **Next:** flip Job67 public after the phone test. JOB 67 walls / rebirth-zone buildings / props / Synty vehicles still owed. JOB 62 ExperienceNotify still held (needs WE_NOTIFY_KEY). Same owed OwnerFirst flips as v199.

## v199 PUBLISHED (Code Bot Roblox, 2026-10-01 ~23:15 Dublin): Open Cloud place version 197. claude-bud JOB 67(1) turret tiers OwnerFirst (assets PENDING)
- **Commits:** cherry-pick `6d359be` → `65b84ea` (JOB 67 turret tiers); code+dist+checks `87f88b9` on phase-7-polish (from v198 `42c143a`). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; MonetizationConfig byte-identical to v198 `22befca`; no price changes; save keys unchanged.
- **JOB 67(1) NEW-OWNER-FIRST (`VisualAssetConfig.Job67`):** GateDefense.AutoGunT1..T5 for Shaun's paid Minigun Turret Pack `109072907337393` (all `ModelAssetId = 0`, `PendingAssetId = 109072907337393` until WE_CHECK2 + promote). `TurretTierFor` maps Turret Guns 0..10 → T1..T5 (thresholds 1/4/7/10). `GateDefenseService` pack-piece loader + same 40-part / no-Humanoid refusal — **today's gun stays** until a tier's ModelAssetId is promoted. wire-asset-ids registry row `MinigunTurretPack` PENDING-GET.
- **Held / not this ship:** JOB 62 ExperienceNotify (`00a76af`) stays on bud only (needs Creator Hub `WE_NOTIFY_KEY`). JOB 67 walls / rebirth-zone buildings / props / Synty vehicles still owed. JOB 66 (5 R$ products) next on Claude queue.
- **Checks:** BuyPathStatic **PASS=8519 FAIL=0**; `tools/checks/codebot_v199.py` PASS; `claude_bud_job67.py` PASS; `tools/sim/run_turret_tier_test.py` **0 failed**.
- **Publish:** HTTP 200, versionNumber **197**, universe 10767159222 / place 97112936860418. Servers NOT restarted (players get it on next join; old servers keep pre-v199 turrets).
- **Phone tests (Shaun — rejoin / new server for WE_Build 199; owner-only while OwnerFirst):**
  1. Turrets still look like **today's gun** (expected — Pending until WE_CHECK2 promote)
  2. Job67 flag is owner-only (other players unchanged)
  3. Upgrade Turret Guns levels still buy / save as before (save keys unchanged)
- **Code Bot NEXT (Studio — not phone):** (1) Run WE_CHECK2 on `109072907337393`. (2) Fill each AutoGunT1..T5 `ChildName` with pack model names for Lvl 1/3/5/8/10 (≤40 parts, ≤20k tris). (3) `python3 tools/wire-asset-ids.py promote MinigunTurretPack --we-check <file>`. Then turrets change look by tier for the owner.
- **Still owed flips:** AntiCamp, HangarDock, Pass59, DefenceFix, SpawnTerminal, AirRotorDisc, BaseLife, DefenceVisuals, Night2, SharedHostility, AttackRange, Rebuild, NukeRaid (JOB 50–59/63/65). Do NOT reopen JOB 44.

## v198 PUBLISHED (Code Bot Roblox, 2026-10-01 ~23:09 Dublin): Open Cloud place version 196. DOUBLE WEEKEND reward toasts show the cash actually credited (display only)
- **Commits:** code+dist+checks `22befca` on phase-7-polish (from v197 `a2543ba`). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; MonetizationConfig byte-identical to v197; no price changes; save keys unchanged; grants unchanged (same AddCash / AccruePendingCash call, same base, same reason; cashMultFor / DoubleEvent untouched).
- **Bug:** in the window the wallet got 2x (EventConfig.ExtraCashReasons via DoubleEvent.ExtraCashMult, and DoubleEvent.CashMult on the non-exempt stack) but the toasts printed the base amount.
- **Fix:** `EconomyService.AddCash` now returns `(ok, credited)` (credited = applyCashMult's grant; one-value callers unchanged). New display-only helpers `EconomyService.ToastAmount(base, ok, credited)`, `ToastTag(player, reason)` (" · 2x" = `EventConfig.ToastTag` while the DOUBLE WEEKEND doubles that reason for him) and `EventCashMult(player, reason)` (the event part of cashMultFor). Toasts now show the credited amount (+ " · 2x" when the event doubled it): supply drop / airdrop; bank job (`bank_raid`; a heist-kit `bank_raid_kit` payout is never tagged); clan war VICTORY / participation; jobs (ops pay, checkpoint, bag delivery: `OpsRewards.Grant` returns `(ok, credited)`, totals / best bag / listeners keep the job pay); daily mission, 3-mission chest, timed missions; daily reward Day N (tomorrow's preview stays the table value); plaza bounty; capture stipend (dropped client-side anyway); rebirth zone shipments. PvP / NPC / vehicle kill "(+$N)" floats show the credited amount (was base x KillCount, which missed the 2x pass / prestige); no tag there because the client Reroute patterns end at "$N)". Oil pump label: server publishes `WE_OilMult` (player attribute, display only) from PlotOilPumpService; ProducerLabels shows CashPerTick x WE_OilMult and "every 5s · 2x".
- **Not changed (not event-doubled):** premium daily / group reward / VIP lounge toasts still print the table amount (EventConfig.CashExemptReasons; only the 2x pass multiplies them). Engagement / codes / battle pass are multiplier-exempt (exact already). Supply crate world label still shows the base $ (shared billboard).
- **Checks:** BuyPathStatic **PASS=8552 FAIL=0**; `tools/checks/codebot_v198.py` PASS (static pins + luau behaviour of ToastAmount / ToastTag + runs the sim); `tools/sim/event_double_weekend_verify.py` **196 PASS / TOTAL FAIL=0**. Pins updated: BuyPathStatic bank / supply toast pins read the credited `shown .. tag`; WE_Build 197 -> 198 pins. Sims run_daily_return / achievement / plaza_guards / sites / rebirth_stations / nuke_raid / first_minutes / endgame / base_guards, gamefeel / launch_gate / engagement_gate / v101_gate: 0 failed.
- **Publish:** HTTP 200, versionNumber **196**, universe 10767159222 / place 97112936860418. Servers NOT restarted (players get it on next join; old servers keep v197 toasts).
- **Phone tests (Shaun — new server for WE_Build 198; owner preview before Fri 21:00 while OwnerFirst, /eventpreview on):** claim a supply drop -> "Supply drop +$<2x> · 2x"; a job pays "<Job> +$<2x> · 2x"; a daily mission toast shows the doubled $ + 2x; an oil pump label reads "+$36 / every 5s · 2x"; /eventpreview off -> base amounts, no tag.

## v197 PUBLISHED (Code Bot Roblox, 2026-10-01 ~22:53 Dublin): Open Cloud place version 195. DOUBLE WEEKEND payout fixes (for EVERYONE)
- **Commits:** code+dist+checks `38af895` on phase-7-polish (from v196 `4b98295`). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; MonetizationConfig byte-identical to v196; no price changes; save keys unchanged.
- **Bug 1 (proven, 145 PASS / 3 FAIL before):** `MonetizationService.PassivePerMin(excludeTimed)` divided out the code CashBoost and the weekly EngagementService event but NOT the DOUBLE WEEKEND, so in the window Robux time packs + Recruit Pack paid 2x and income-scaled core missions / mission chest / Day 7 / zone runs applied the event twice (4x). **Fix:** the excludeTimed branch also divides `Modules/DoubleEvent.CashMult(player, "passive")` out. Legacy cash packs (OfferMoment CashLarge amount + the CashPacks receipt) now pass excludeTimed=true too.
- **Extra scope (owner-approved):** `EventConfig.ExtraCashReasons` = plot_oil (oil pumps, at AccruePendingCash; collect is "collector", never multiplied), ops (jobs), supply_drop (drops + airdrops), bank_raid (no kit), clan_war_win / clan_war_participate. `EconomyService.cashMultFor`'s exempt branch applies `DoubleEvent.ExtraCashMult` (CashMult only, in the window only) for those; the 2x pass / prestige / tax still skip them. A heist-kit bank payout (minutes of WE_IncomePerSec, already doubled) now pays as `bank_raid_kit` (NEVER_MULTIPLIED; analytics raid_loot). Codes, battle pass, onboarding, invite/friends/comeback, spinner, clicker dropper, devproduct, admin, refunds: never doubled. Note: supply drop / bank raid / clan war toasts still show the base amount (wallet gets 2x in the window).
- **Checks:** BuyPathStatic **PASS=8515 FAIL=0**; `tools/checks/codebot_v197.py` (static pins + runs the sim); `tools/sim/event_double_weekend_verify.py` **196 PASS / 0 FAIL** (real EventConfig + DoubleEvent under a fake clock; codes/battle pass asserted NOT doubled). Pins updated: codebot_v185 "no event hook in MonetizationService" narrowed to the PassivePerMin divide; run_shop_test.py receipt-order pin reads `PassivePerMin(player, profile, true)`.
- **Publish:** HTTP 200, versionNumber **195**, universe 10767159222 / place 97112936860418. Servers NOT restarted (players get it on next join; servers started before 22:53 keep v196 behaviour).
- **Phone tests (Shaun — new server for WE_Build 197; owner preview before Fri 21:00 while OwnerFirst):** 4h time pack shows the same $ with /eventpreview on and off; a core mission pays 2x (not 4x) with preview on; an oil pump ATM fills 2x; a job pays 2x; a code reward is unchanged.

## v196 PUBLISHED (Code Bot Roblox, 2026-10-01 ~22:44 Dublin): Open Cloud place version 194. claude-bud JOB 65 NukeRaid OwnerFirst (nuke instant raid)
- **Commits:** cherry-pick `e099ea9` → `a0b4cbf` (JOB 65 NukeRaid); code+dist+checks `7fd72f1` on phase-7-polish (from v195 `c55da52`). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; MonetizationConfig byte-identical to v195 `1b8d5fa`.
- **JOB 65 (NEW-OWNER-FIRST by ATTACKER):** `RebirthZonesConfig.NukeRaid` — TARGETS **NUKE** button → server preview (`RequestNuke "rpreview"`) shows name / base level / EXACT raidable ATM; LAUNCH (`rlaunch`) spends warhead + 30 min cooldown (`NukeLastLaunch`, existing keys), then `MoneyCollectorService.NukeRaid` moves FULL ATM 1:1 via `_MoveLoot` + `EconomyService.PendingToCash` (no Double Weekend / VIP / boost on a transfer). Fairness: raid rules + ONE protection rule + never admin + JOB 63 same-base cooldown. MissileStrikeFx + light NukeBlast (Vfx switch). Victim gets shield, raid report, `NUKE_RAID` analytics, BaseRaided hook.
- **Held:** JOB 62 ExperienceNotify (`00a76af`) stays on bud until Creator Hub secret `WE_NOTIFY_KEY` + Shaun opt-in.
- **Checks:** BuyPathStatic **PASS=8443 FAIL=0**; `tools/checks/codebot_v196.py`; `claude_bud_job65.py`; `tools/sim/run_nuke_raid_test.py` 0 failed. PreferMesh OFF; StreamingEnabled OFF.
- **Publish:** HTTP 200, versionNumber **194**, universe 10767159222 / place 97112936860418. Servers NOT restarted (players get it on next join).
- **Phone tests (Shaun — rejoin / new server for WE_Build 196; owner-only while OwnerFirst):**
  1. Have Nuclear Silo built + a ready warhead; TARGETS shows **NUKE** on a valid rival
  2. Tap NUKE → preview card shows their name, base level, and exact ATM $; CANCEL closes
  3. LAUNCH → you get that ATM as Cash; they get raid shield + report; silo cooldown ~30 min on the button
  4. Blocked targets (shield / new / admin / ally / camp cooldown / own base) show why; no warhead spent
  5. Only you (attacker OwnerFirst) until flipped
- **Still owed:** After phone OK flip `RebirthZonesConfig.NukeRaid` OwnerFirst. Still owed flips: AntiCamp, HangarDock, Pass59, DefenceFix, SpawnTerminal, AirRotorDisc, BaseLife, DefenceVisuals, Night2, SharedHostility, AttackRange, Rebuild (JOB 50–59/63). JOB 62 held for WE_NOTIFY_KEY. JOB 64 referrals next on Claude queue. Do NOT reopen JOB 44.

## v195 PUBLISHED (Code Bot Roblox, 2026-10-01 ~22:38 Dublin): Open Cloud place version 193. Cash pill 3 decimals above $1B (display only)
- **Commit:** code+dist+checks `1b8d5fa` on phase-7-polish (from v194 `be8074d`); bud merge `18e5869`. PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; EconomyConfig / EconomyService / MonetizationConfig / Constants / LeaderboardConfig byte-identical to v194 `c288e7a`; no price changes; save keys unchanged.
- **Why:** owner report "HUD still 1.00B with +$174,688/s" after v194. Full src audit found NO remaining $1B cap (only MaxCash=1e15 clamps in EconomyService 418/446/470/476/756; owner floors are 50M floors via math.max; ProfileSchema Migrate only floors Cash; leaderstats IntValue is int64; AdminService 1e9 limits are per-command grant sizes, not wallet caps). Cause = HUDController formatCash `%.2f` B (1.00B covers $1.000B-$1.005B, ~29-57 s of growth at $174k/s) + passive income lands in PendingCash (ATM) until collected / AutoCollect + servers started before 22:31 still run v193 (MaxCash 1e9, wallet pinned at exactly 1,000,000,000 and old collect deletes overflow).
- **Fix:** `HudConfig.CashPill.AbbreviateDecimalsBig = 3`; formatCash uses 3 decimals for B/T ("1.003B", "2.500T"), M/K keep 2.
- **Checks:** BuyPathStatic **PASS=8469 FAIL=0**; `tools/checks/codebot_v195.py` PASS. rojo build -> dist/WarEmpire-PERF.rbxlx copied to dist/WarEmpire.rbxlx.
- **Publish:** HTTP 200, versionNumber **193** (Open Cloud place updateTime 2026-10-01T21:38:39Z = 22:38:39 Dublin). Servers NOT restarted.

## v194 PUBLISHED (Code Bot Roblox, 2026-10-01 ~22:31 Dublin): Open Cloud place version 192. $1B cash cap bug fix (for EVERYONE, not OwnerFirst)
- **Commit:** code+dist+checks `c288e7a` on phase-7-polish (from v193 `decf639`). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; MonetizationConfig byte-identical to v193 `a42fc12`; no price changes; save keys unchanged.
- **Root cause (proven at 2b8d1c4):** `EconomyConfig.MaxCash = 1_000_000_000`; AddCash clamped the wallet but still added the full grant to `Stats.TotalCashEarned`; AccruePendingCash capped PendingCash at 1B; CollectPendingCash zeroed PendingCash BEFORE clamping, so everything over $1B was deleted on collect.
- **Fix:** `MaxCash = 1e15` (same ceiling as ProfileSchema / XP / Prestige counters). CollectPendingCash credits `min(pending, MaxCash - Cash)` and leaves the remainder in PendingCash (analytics origins reported pro-rata on a partial collect; returns the credited amount). AddCash / CollectPendingCash add only the actually-credited amount to TotalCashEarned. "T" (trillion) step added to `short()` in EngagementClient, EndgameController, EndgameService (HUD cash pill already had T). JOB39 doc / proof "MaxCash 1,000,000,000" mentions annotated.
- **Checks:** BuyPathStatic **PASS=8447 FAIL=0**; `tools/checks/codebot_v194.py` PASS (MaxCash==1e15, collect remainder logic + model cases, TotalCashEarned credited-only, T formatters, no OwnerFirst gate, MonetizationConfig/save keys unchanged, PreferMesh/StreamingEnabled OFF); `tools/sim/run_endgame_test.py` 0 failed. rojo build → dist/WarEmpire-PERF.rbxlx copied to dist/WarEmpire.rbxlx (identical).
- **Publish:** HTTP 200, versionNumber **192**, universe 10767159222 / place 97112936860418. Servers NOT restarted (players get it on next join).
- **Phone test (Shaun — new server for WE_Build 194):** a wallet past $1B keeps growing on collect; if a wallet ever hits the cap, the ATM keeps the leftover instead of wiping it; big numbers show "T".
- **Note:** cash already lost to the old cap before v194 is not restored (no record of the deleted overflow).

## v193 PUBLISHED (Code Bot Roblox, 2026-10-01 ~22:22 Dublin): Open Cloud place version 191. claude-bud JOB 63 AntiCamp OwnerFirst (anti-spawn-camping)
- **Commits:** cherry-pick `ef384eb` → `5a28190` (JOB 63 AntiCamp; JOB 62 ExperienceNotify intentionally NOT included); code+dist+checks `a42fc12` on phase-7-polish (from v192 `2b8d1c4`). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; MonetizationConfig byte-identical to v192 `a38b1af`.
- **JOB 63 (NEW-OWNER-FIRST):** `RaidConfig.AntiCamp` — AntiCampService through the ONE protection rule (CombatService `pvpBlock` / `InvulnerableUntil`): 5 s defender shield at own base (ends on first shot), 90 s raider limit / loot taken / 3 kills in 60 s → normal respawn home (`LoadCharacter`) with notice, 3 min same-base cooldown (`camp_cooldown`, no base damage, TARGETS WAIT, edge toast). Keyed by base owner.
- **Held:** JOB 62 ExperienceNotify (`00a76af`) stays on bud until Creator Hub secret `WE_NOTIFY_KEY` exists + Shaun opt-in.
- **Checks:** BuyPathStatic **PASS=8373 FAIL=0**; `tools/checks/codebot_v193.py`; `claude_bud_job63.py`. PreferMesh OFF; StreamingEnabled OFF.
- **Publish:** HTTP 200, versionNumber **191**, universe 10767159222 / place 97112936860418. Servers NOT restarted (players get it on next join).
- **Phone tests (Shaun — rejoin / new server for WE_Build 193; owner only while OwnerFirst):**
  1. Alt stands in your base 90 s → respawns home with notice
  2. Alt walks back → sent home again; TARGETS shows WAIT
  3. You die and respawn → ~5 s shield bubble that drops when you fire
  4. Only plot owner while OwnerFirst
- **Still owed:** After phone OK flip `RaidConfig.AntiCamp` OwnerFirst. Still owed flips: HangarDock, Pass59, DefenceFix, SpawnTerminal, AirRotorDisc, BaseLife, DefenceVisuals, Night2, SharedHostility, AttackRange, Rebuild (JOB 50–59). JOB 62 ready on bud — NOT shipped. JOB 64 referrals next on Claude queue; JOB 65/66 queued as docs. Do NOT reopen JOB 44. Studio 2-player AntiCamp proof still owed (Claude noted).

## v192 PUBLISHED (Code Bot Roblox, 2026-10-01 ~22:15 Dublin): Open Cloud place version 190. DOUBLE WEEKEND banner -> one-time pop-up + live chip (owner feedback: "banner stuck on screen, ugly and blocking")
- **Commit:** code+dist+checks `a38b1af` on phase-7-polish (from v191 `67a5bfa`). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; MonetizationConfig byte-identical to v191 `a6fa8eb`; no price changes. Event window / Id / EventId / multipliers unchanged.
- **Removed:** the v185 top-centre banner (DoubleWeekendController no longer uses RegisterTopStack).
- **Pop-up (before Fri 2 Oct 21:00 Dublin only):** centred card, 56 px NOTIFY ME / NO THANKS. "DOUBLE WEEKEND · Fri 9pm – Sun 9pm (Irish time) · 2x XP · 2x Cash · 2x Kills · Get notified when it starts?". NOTIFY ME = `SocialService:PromptRsvpToEventAsync(EventId)` in a pcall. Once per player per `EventConfig.Id`: new profile field `EventPopupSeen = { [Id] = unix }` (ProfileSchema sanitised; no key renamed), replicated as player attr `WE_EventPopupSeen` on profile load; saved the moment it shows via new remote `RequestEventPopupSeen` (RemoteGate schema string:32, id must equal EventConfig.Id, rate-limited; wired in RetentionService.Init -> DoubleEvent.InitPopup). Skipped if `GetEventRsvpStatusAsync` = Going. Shows 6 s after spawn and after the screen has been free 2 s: no Tutorial / Modal / Dead / Driving / RecentCombat flag, no `WE_Onboarding` hold, no Rate prompt / Recruit Pack / building tip / rebirth / raid / scout card on screen (no modal queue exists, so it waits behind them). Registered as HudLayout panel `DoubleWeekendPopup` while open.
- **Live chip (window, or owner preview):** under the TARGETS card (RivalConfig.Layout x/width, +6 px, 30 px tall, text 12–15 px): "2x WEEKEND · 1d 4h". Tap = details card (LIVE NOW · ends in …, OK). Hidden while a panel / tutorial / Recruit Pack card is up or dead. Nothing before the start (except owner preview), nothing after EndUnix. 1024x471: chip x 836–1016, screen y 136–166 — clear of the top bar (<58), top-centre stack (ends x 829), left rail, hotbar, CombatTouch/jump reserve (y ≥ 249).
- **Owner:** `/eventpreview [on|off]` unchanged. NEW `/eventpopup` = show the pop-up now (tagged OWNER TEST, not saved). `/eventpopup reset` = clear his saved seen flag (the real first-time flow runs again before the start).
- **Checks:** BuyPathStatic **PASS=8396 FAIL=0**; `tools/checks/codebot_v192.py` (codebot_v185 banner-top-stack pin retired). One 1 s loop, no Heartbeat.
- **Publish:** HTTP 200, versionNumber **190**, universe 10767159222 / place 97112936860418. Servers NOT restarted (new servers / rejoin get WE_Build 192).
- **Note:** the old banner's `BannerText` / `BannerLeadSeconds` / `BannerState` stay in EventConfig (unused by the client now; kept for the v185 pins).

## v191 PUBLISHED (Code Bot Roblox, 2026-10-01 ~21:52 Dublin): Open Cloud place version 189. claude-bud JOB 58 HangarDock + JOB 59 Pass59 sounds OwnerFirst (+ JOB 60 audit docs/checks)
- **Commits:** cherry-pick `01de0c6` → `88d0925` (JOB 58 HangarDock), `0c92212` → `974a4d1` (JOB 59 Pass59 sounds), `43284a9` → `0b48e42` (JOB 60 error-report audit docs/checks); code+dist+checks `a6fa8eb` on phase-7-polish (from v190 `530e2ff`). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; MonetizationConfig byte-identical to v190 `8397dc7`.
- **JOB 58 (NEW-OWNER-FIRST):** `HangarDockConfig` — VisualAssetService.CloneDisplayBody + HangarDockDisplayService: FighterJet / ReconPlane in hangar slots, first allowed boat (LandingCraft) at dock; Part pieces hidden only under a placed body; Part build kept as fallback.
- **JOB 59 B (NEW-OWNER-FIRST):** `SoundConfig.Pass59` — new SoundConfig keys (night crickets/ambience/harbor, flag flap, radio chatter, distant artillery, gate, boat, march cut, click) + owner-only id swaps (heli, boat, raid siren, UI click) via AmbienceController (1 Hz, 3D, through AudioController). A/C/D still blocked on asset pipeline (not shipped).
- **JOB 60:** docs + `tools/checks/claude_bud_job60.py` only (AnchorPoint / LoadAnimation pins). No gameplay. Remainder blocked on Creator Hub CSV text.
- **Checks:** BuyPathStatic **PASS=8306 FAIL=0**; `tools/checks/codebot_v191.py`; `claude_bud_job58.py`; `claude_bud_job59.py`; `claude_bud_job60.py`. PreferMesh OFF; StreamingEnabled OFF.
- **Publish:** HTTP 200, versionNumber **189**, universe 10767159222 / place 97112936860418. Servers NOT restarted.
- **Phone tests (Shaun — rejoin / new server for WE_Build 191; owner only while OwnerFirst):**
  1. JOB 58: hangar shows real jet(s) not blocks; dock shows landing craft; Airfield L4 → two aircraft.
  2. JOB 59: night crickets/harbor by dock; radio by Command Center; plaza flag flap; desert distant boom; gate sound; new heli/boat engines.
  3. Only plot owner while OwnerFirst.
- **Still owed:** After phone OK flip HangarDock + Pass59 OwnerFirst. Still owed flips: DefenceFix, SpawnTerminal, AirRotorDisc, BaseLife, DefenceVisuals, Night2, SharedHostility, AttackRange, Rebuild (JOB 50/51/52/53/54/55/56/57). Do NOT reopen JOB 44. JOB 60 ask: export Creator Hub error CSV into `docs/proof/errors/` and re-queue. Remaining queue: JOB 59 A/C/D (asset pipeline), 62–64.

## v190 PUBLISHED (Code Bot Roblox, 2026-10-01 ~21:17 Dublin): Open Cloud place version 188. claude-bud JOB 55 DefenceFix + JOB 56 SpawnTerminals/Rotor + JOB 57 BaseLife OwnerFirst
- **Commits:** cherry-pick `3362e25` → `73cfc59` (JOB 55 DefenceFix), `5e46977` → `29f7d53` (JOB 56 SpawnTerminals + AirRotorDisc), `8a90340` → `db90add` (JOB 57 BaseLife); code+dist+checks `8397dc7` on phase-7-polish (from v189 `2c6212f`). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; MonetizationConfig byte-identical to v189.
- **JOB 55 (NEW-OWNER-FIRST):** `EndgameConfig.DefenceFix` — Plating needs Walls L4 (row + refusal), Vault shows both cuts, Turret Guns arms gate/tower guards, Gate & Walls → Gate Armour (no wall HP), BaseGuards 0.12 → Defence.GatePct, mid-raid Defence buy refreshes in place (KeepDamage, no full repair) with [DefenseUpgrade] logs.
- **JOB 56 (NEW-OWNER-FIRST):** `SpawnTerminalConfig` + `VisualAssetConfig.AirRotorDisc` — helipad/dock SpawnTerminalService (WE_PanelPrompt → Garage Air/Naval; RequestSpawn gates unchanged) + AirBodyRig._DiscFit rotor disc; [RotorRig] tilt/offset logs.
- **JOB 57 (NEW-OWNER-FIRST):** `BaseLifeConfig` — BaseLifeService 11 part-built WorldKits props per owned plot (600 allowance + keep-out) + 3 unarmed ambient soldiers IDLE/PATROL at 2 Hz, never hostile, CanQuery off, server cap = CombatConfig.MaxActiveNPCs 18.
- **Checks:** BuyPathStatic **PASS=8264 FAIL=0**; `tools/checks/codebot_v190.py`; `claude_bud_job55.py`; `claude_bud_job56.py`; `claude_bud_job57.py`. PreferMesh OFF; StreamingEnabled OFF.
- **Publish:** HTTP 200, versionNumber **188**, universe 10767159222 / place 97112936860418. Servers NOT restarted.
- **Phone tests (Shaun — rejoin / new server for WE_Build 190; owner only while OwnerFirst):**
  1. JOB 55: Engineering Bureau — Turret Plating says Needs Walls L4 when walls <4; Vault shows both cuts; mid-raid Gate buy keeps damage (bar doesn't jump to full).
  2. JOB 56: Helipad console "Spawn aircraft" opens Garage AIR; dock "Launch boat" opens NAVAL; spawn attack heli and note [RotorRig] F9 log.
  3. JOB 57: Base has tents/crates/drums/sandbags + 3 soldiers idle/patrol; shooting them does nothing (CanQuery off); frame rate OK.
  4. Only plot owner while OwnerFirst.
- **Still owed:** After phone OK flip DefenceFix + SpawnTerminal + AirRotorDisc + BaseLife OwnerFirst. Still owed flips: DefenceVisuals, Night2, SharedHostility, AttackRange, Rebuild (JOB 50/51/52/53/54). Do NOT reopen JOB 44. Remaining queue: JOB 58 hangar/dock rebuild, then 59, 60, 62–64. Claude may still be coding JOB 58 on bud.

## v189 PUBLISHED (Code Bot Roblox, 2026-10-01 ~20:45 Dublin): Open Cloud place version 187. claude-bud JOB 53 Defence visuals + JOB 54 night lighting OwnerFirst
- **Commits:** cherry-pick `cce3479` → `aa8adc4` (JOB 53 DefenceVisuals), `9894eb8` → `275f0e3` (JOB 54 Night2); code+dist+checks `6740398` on phase-7-polish (from v188 `c0d7123`). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; MonetizationConfig byte-identical to v188.
- **JOB 53 (NEW-OWNER-FIRST):** `EndgameConfig.DefenceVisuals` — turret plating/ammo, gate bands-plates-braces-beam + tier leaf look, vault plating by tier L1/4/7/10 from SAVED levels in syncPlotNow; gate damage states 60%/30%/breached; new-look purchase toast via `DefenceVisuals` module.
- **JOB 54 (NEW-OWNER-FIRST):** `LightingConfig.Night2` — NightLights.SyncPlot per owned plot (helipad + dock floods, lit gate sign, red beacon mast, pad/bollard/runway glow), 7 lights/base, 101/120 budget, low-quality halving; client night exposure 0 → 0.35.
- **Checks:** BuyPathStatic **PASS=8258 FAIL=0**; `tools/checks/codebot_v189.py`; `claude_bud_job53.py`; `claude_bud_job54.py`. PreferMesh OFF; StreamingEnabled OFF.
- **Publish:** HTTP 200, versionNumber **187**, universe 10767159222 / place 97112936860418. Servers NOT restarted.
- **Phone tests (Shaun — rejoin / new server for WE_Build 189; owner only while OwnerFirst):**
  1. Defence tiers visible on turrets/gates/vault from saved levels (JOB 53).
  2. Gate damage states at 60%/30%/breached.
  3. Purchase toast when buying into a new visual tier.
  4. Night: base lights (helipad/dock/gate sign/beacon etc.), exposure bump; light budget respected (JOB 54).
  5. Only plot owner sees while OwnerFirst.
- **Still owed:** flip DefenceVisuals.OwnerFirst + Night2.OwnerFirst after phone OK; JOB 51/52 still OwnerFirst; queued 55–58, 59, 60, 62–64. JOB 44 DONE — do not reopen.

## v188 PUBLISHED (Code Bot Roblox, 2026-10-01 ~20:15 Dublin): Open Cloud place version 186. claude-bud JOB 50 B+C Visuals+Signs OwnerFirst
- **Commits:** cherry-pick `a360cec` → `51bd222` (JOB 50 B Visuals props), `302807e` → `078c624` (JOB 50 C Signs plaque/card/map/toast); code+dist+checks `8756ab5` on phase-7-polish (from v187 `3c2719e`). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; MonetizationConfig byte-identical to v187.
- **JOB 50 B (NEW-OWNER-FIRST):** `RebirthZonesConfig.Rebuild.Visuals` — themed run props (truck/conveyor, consoles, targets, gates, valves, sandbag nests) + berm/apron edge via `RebirthZoneDressing.BuildRunProps` (parts only, no Light/Neon/WE_Building).
- **JOB 50 C (NEW-OWNER-FIRST):** `RebirthZonesConfig.Rebuild.Signs` — gateway plaque RUN READY / IN PROGRESS / NEXT RUN n MIN (30 s refresh); preview `RunLine` (<= 42 chars); map zone dots (tap = card + pin, no fast travel); one ready toast.
- **Checks:** BuyPathStatic **PASS=8169 FAIL=0**; `tools/checks/codebot_v188.py`; `claude_bud_job50.py` parts A+B+C+D. PreferMesh OFF; StreamingEnabled OFF.
- **Publish:** HTTP 200, versionNumber **186**, universe 10767159222 / place 97112936860418. Servers NOT restarted.
- **Phone tests (Shaun — rejoin / new server for WE_Build 188; owner only while OwnerFirst):**
  1. Built rebirth zone: themed run props + berm/apron visible (Visuals).
  2. Gateway plaque shows RUN READY / IN PROGRESS / NEXT RUN n MIN; refreshes without per-second churn.
  3. Upgrade prompt card has gold Run: … line, not cut off at phone widths.
  4. Map: HIS zone dots; tap = card + pin only (no fast travel).
  5. After cooldown: one ready toast.
- **Still owed:** flip Rebuild.OwnerFirst (and Visuals/Signs with it) after phone OK; flip AttackRange + SharedHostility after phone; JOB 51/52 still OwnerFirst; queued 53–58, 59, 60, 62, 63, 64. JOB 44 DONE — do not reopen.

## v187 PUBLISHED (Code Bot Roblox, 2026-10-01 ~19:52 Dublin): Open Cloud place version 185. claude-bud JOB 50 A ZoneRuns OwnerFirst
- **Commits:** cherry-pick `2566954` → `65b53c8` (JOB 50 A ZoneRuns); code+dist+checks `3a0ab44` on phase-7-polish (from v186 `12bcd18`). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; MonetizationConfig byte-identical to v186.
- **JOB 50 A (NEW-OWNER-FIRST):** `RebirthZonesConfig.Rebuild.OwnerFirst = true` — zone runs behind existing kiosks (Modules/ZoneRuns): production / launch prep / range practice / recon flight / drill course / pressure valves / hold the line. Server-validated steps; RunBase = max(ShipmentCash, 2 min income) × speed; first clear + cooldown + best; gateway plaques; ZONE COMMANDER; ZoneActivity analytics. Enabled=false = JOB 46 one-tap activities.
- **Checks:** BuyPathStatic **PASS=8138 FAIL=0**; `tools/checks/codebot_v187.py`; `claude_bud_job50.py` parts A+D. PreferMesh OFF; StreamingEnabled OFF.
- **Publish:** HTTP 200, versionNumber **185**, universe 10767159222 / place 97112936860418. Servers NOT restarted.
- **Phone tests (Shaun — rejoin / new server for WE_Build 187; owner only while OwnerFirst):**
  1. At a rebuilt rebirth zone kiosk: start the zone run; complete steps in order inside the annex; get cash / effect.
  2. Fail / timeout / leave annex: no pay; cooldown still starts.
  3. Recon flight marks a raidable rival with PIN/SEND; drill course under par grants ARMY BOOST.
  4. Hotbar captions (JOB 50 D, already in v186) still non-overlapping.
- **Still owed:** flip Rebuild.OwnerFirst after phone OK; JOB 50 B/C still on bud if not done; flip AttackRange + SharedHostility after phone; queued 53–58, 59, 60, 62, 63, 64. JOB 44 DONE — do not reopen.

## v186 PUBLISHED (Code Bot Roblox, 2026-10-01 ~19:49 Dublin): Open Cloud place version 184. claude-bud JOB 50 D hotbar weapon labels overlap
- **Commits:** cherry-pick `a502699` → `901696b` (JOB 50 D); code+dist+checks `1e2ac24` on phase-7-polish (from v185 `5508896`). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; MonetizationConfig byte-identical to v185 `5508896`.
- **JOB 50 D:** hotbar captions stay inside their own slot (`fitCaption`, CaptionMinTextPx floor); distinct rebirth ShortNames DMR / HAVOC RL / SOV RIFLE (pass guns keep LONGSHOT / HAVOC / SOVEREIGN). No Id / pass / price change. Always-on UI fix (no new OwnerFirst gate).
- **Checks:** BuyPathStatic **PASS=8120 FAIL=0**; `tools/checks/codebot_v186.py`; `claude_bud_job50.py`; `run_hotbar_caption_test.py` 0 failed.
- **Publish:** HTTP 200, versionNumber **184**, universe 10767159222 / place 97112936860418. Servers NOT restarted: Migrate to Latest Update when convenient.
- **Phone tests (Shaun — rejoin / new server for WE_Build 186):**
  1. Equip 4 weapons on the phone hotbar: each caption sits inside its own slot and never overlaps the neighbour.
  2. Rebirth DMR vs pass LONGSHOT, HAVOC RL vs HAVOC, SOV RIFLE vs SOVEREIGN read as distinct labels.
- **Still owed:** JOB 50 A/B/C rebirth zones rebuild still on bud; flip AttackRange.OwnerFirst (JOB 52) + SharedHostility.OwnerFirst (JOB 51) after phone OK; queued 53–58, 59, 60, 62, 63, 64. JOB 44 DONE — do not reopen.

## v185 PUBLISHED (Code Bot Roblox, 2026-10-01 ~19:43 Dublin): Open Cloud place version 183. DOUBLE WEEKEND event (time-gated)
- **Commit:** `5508896` on phase-7-polish (from v184 `36b0f31`). WE_Build 185. PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; MonetizationConfig byte-identical (no price change).
- **Config:** `Shared/Configs/EventConfig.luau` `Id="DoubleWeekend1"`, `StartUnix=1790971200` (Fri 2 Oct 2026 20:00 UTC = 21:00 Dublin), `EndUnix=1791144000` (Sun 4 Oct 2026 20:00 UTC = 21:00 Dublin), `XPMult=2`, `CashMult=2`, `KillMult=2`, `OwnerFirst=true` (NEW-OWNER-FIRST), `EventId="5990901055452480269"` (Creator Hub event for NOTIFY ME).
- **OwnerFirst gates ONLY the preview before StartUnix** (Shaun 470626172 sees it live early). Inside the window it is live for EVERYONE regardless of OwnerFirst; after EndUnix off for everyone. Owner chat `/eventpreview on|off` toggles the preview per server (not saved).
- **Checks:** BuyPathStatic **PASS=8146 FAIL=0**; `tools/checks/codebot_v185.py` 39 PASS.
- **Servers NOT restarted.** Old (v184) servers have NO event code: a Migrate to Latest Update before Fri 21:00 Dublin is advised if old servers are still up.
- **Next:** when Shaun says so, flip `EventConfig.OwnerFirst` true -> false (ends the preview only). After Sun 21:00 the event is inert; remove or reuse the config for the next event.

## v184 PUBLISHED (Code Bot Roblox, 2026-10-01 ~19:27 Dublin): Open Cloud place version 182. claude-bud JOB 52 ARMY ATTACK at range OwnerFirst
- **Commits:** cherry-pick `98a9bc2` → `bdd3c32` (JOB 52 AttackRange), `df004e9` → `5726ce1` (pin credit check); code+dist+checks `cc922b8` on phase-7-polish (from `744c18f`). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; MonetizationConfig byte-identical to v183 `744c18f`.
- **JOB 52 (NEW-OWNER-FIRST):** `ArmyOrdersConfig.AttackRange.OwnerFirst = true` — one set of radii for the whole ATTACK order (seek 400 / leash 450 / chain 200), flat distances, existing march; nothing in range → distance + direction card with PIN / SEND ARMY (`N:<npcId>` server-resolved); ARMY KILLS for ordered target group, capped 60/h. Enabled=false is the old 250/300/150.
- **Checks:** BuyPathStatic **PASS=8107 FAIL=0**; `tools/checks/codebot_v184.py`; `claude_bud_job52.py`; run_army_command_test 0 failed. PreferMesh OFF; StreamingEnabled OFF.
- **Publish:** HTTP 200, versionNumber **182**, universe 10767159222 / place 97112936860418. Servers NOT restarted: Migrate to Latest Update when convenient.
- **Phone tests (Shaun — rejoin / new server for WE_Build 184):**
  1. Army out, enemies visible ~300 m away: ATTACK. Army marches in formation and fights; ARMY KILLS go up.
  2. Nothing within range: card shows distance + direction; PIN marks it; SEND ARMY takes army there.
  3. Shielded/new player nearby never attacked (JOB 51 rule).
- **Still owed:** flip AttackRange.OwnerFirst after phone OK; JOB 51 SharedHostility still OwnerFirst (phone with Laumartinez26); JOB 50 rebirth zones on bud; queued 53–58, 59, 60, 62, 63, 64. JOB 44 Shaun said DONE 18:58 Dublin — do not reopen.

## v183 PUBLISHED (Code Bot Roblox, 2026-10-01 ~18:55 Dublin): Open Cloud place version 181. claude-bud JOB 51 SharedHostility OwnerFirst + JOB 61 Creator Hub analytics
- **Commits:** cherry-pick `b8c2af5` → `07bb90a` (JOB 51), `1373c74` → `fb88365` (JOB 61); code+dist+checks `3df4db5` on phase-7-polish (from `4952138`). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; MonetizationConfig byte-identical to v182 `4952138`.
- **JOB 51 (NEW-OWNER-FIRST):** `CombatConfig.SharedHostility.OwnerFirst = true` — `Server/Modules/Hostility` bound by CombatService; every NPC target pick uses it; CheckpointGuardService.Protected calls it; `/guarddebug` + `[GuardTarget]`/`[GuardShot]`/`[NpcHit]`. Enabled=false is the old brain. Live 2-player proof owed.
- **JOB 61:** AnalyticsService batched Cash/Gold economy + 8-step first-session onboarding funnel + Shop/Rebirth funnel session IDs + daily mission / return / notification custom events. No Heartbeat work. Admin exclusion + PII sanitization.
- **Checks:** BuyPathStatic **PASS=8043 FAIL=0**; `tools/checks/codebot_v183.py`; `claude_bud_job51.py`; `claude_bud_job61.py`. PreferMesh OFF; StreamingEnabled OFF.
- **Publish:** HTTP 200, versionNumber **181**, universe 10767159222 / place 97112936860418. Servers NOT restarted: Migrate to Latest Update when convenient.
- **Phone tests (Shaun — JOB 51 needs Laumartinez26 in the same server; owner types `/guarddebug on`):**
  1. Both in the plaza circle: guards shoot both of you; nobody shielded soaks the shots forever.
  2. Both can damage and kill a guard.
  3. Respawn at the plaza: shield ends normally; note how fast guards kill you.
- **Still owed:** flip SharedHostility.OwnerFirst after phone OK; JOB 44 Studio 2-player siege/march; JOB 52 / 50 / 59 / 60 / 62 queued; spawn-out-of-plaza-aggro question for Shaun.

## JOB 61 (Code Bot Roblox, 2026-10-01 18:36 Dublin): Creator Hub Economy + Funnels analytics
- Added the server-only `AnalyticsService` path and one central `Shared/Configs/AnalyticsConfig.luau`: batched Cash/Gold economy events with normalized item SKUs, ending balances, allowed transaction types, admin exclusion, and PII sanitization.
- Added the eight-step first-session onboarding funnel (once per saved player), server-created Shop/Rebirth funnel session IDs, daily mission / return sequence / notification custom events, and a delayed five-minute step with no Heartbeat work.
- Added `tools/checks/claude_bud_job61.py`. House rules remain unchanged: StreamingEnabled/PreferMesh off, `WE_Building*` untouched, no price changes.
- Files: `AnalyticsService.luau`, `AnalyticsConfig.luau`, `EconomyService.luau`, `MissionService.luau`, `RetentionService.luau`, `ShopController.luau`, and the JOB 61 check.

<!-- Q2-START -->
## claude-bud JOB 75 Scout Helicopter flight fix (2026-10-02) (branch `claude/desktop-bud`)
Owner-first: `VehicleConfig.HeliFlight` (`OwnerFirst = true`, NEW-OWNER-FIRST tag), live per VEHICLE OWNER for Shaun +
Laumartinez26 (11718087109). Anyone else flies the old way exactly. Check: `tools/checks/claude_bud_job75.py` (J75-01..08).
Sim: `tools/sim/run_heli_flight_test.py` (22 ok).

**ROOT CAUSE (from the code):**
1. **Tilt at a hover.**
   - Every heli key wears the attack-heli body 11240665977 (`VisualAssetConfig.heliRef`). It moves DriverSeat /
     PassengerSeat1 to the cockpit: body seats (∓4, 5.4, -30) × BodyScale 0.45 = 1.8 studs to the side and 13.5 studs
     forward of the chassis centre.
   - The seats and the riders keep their mass. But `WE_DriveLV`, which holds the heli up (its Y axis is on in a
     hover), pushes at `WE_DriveAttach` = the chassis centre (`createMovers`, CFrame.new()).
   - So gravity on the rider × 13.5 studs is a steady nose-down torque (and × 1.8 a roll torque). That is about the
     size of `WE_DriveAO.MaxTorque` (mass × |Chassis.Size|² × TorqueScale 3). The `AlignOrientation` (non-rigid) can't
     cancel it, so the heli hangs nose-down / sideways.
   - Cars already drive at their centre of mass (`_Ballast` / `_DriveAttachX`); aircraft never did. Fitted plane
     bodies move their seats the same way.
2. **"SPD 0".** The HUD showed the COMMANDED speed (`st.Fwd` / `st.Side`), which is 0 until the stick is pushed, not
   the real speed.
3. **Steering on a phone.** The default Roblox thumbstick is invisible until touched. In a heli its X yawed and its Y
   throttled, with no hint that the stick flies at all; strafe was keyboard-only (Z/X).
4. **Hard landings.** The old law descends at the full 20 studs/s right down to the ground, so ground hits bounce.

**FIX (live owners):**
- **Centre of mass.** The server marks a live owner's Heli / Plane (`WE_ComDrive`, + `WE_HeliFlight`) and moves
  `WE_DriveAttach` to `AssemblyCenterOfMass` on every seat change (`VehicleService._AirCom`). The driving client
  refreshes it every 0.5 s. The lift now adds no torque: a level hover.
- **Touch.** The stick flies camera-relative: push = fly where the camera looks, sideways = strafe. The nose turns
  toward the camera while the stick is pushed; a centred stick hovers and the camera looks around freely. ▲/▼ is
  height. Pure `Laws.HeliCameraInput`. New hint "Stick: fly · camera: turn · ▲▼ height · hold EXIT to leave".
- **Smaller tilts.** Nose-down at full speed is 9° (was 14); strafe roll 7° (was 12); turn bank is now about 5.6°
  (was about 9.6°).
- **SPD** = the real ground speed.
- **Ground handling.**
  - Gentle landing: descent is capped at 3 + 1.2 × height studs/s near the ground (5.4 at 2 studs).
  - At 2.5 studs and not climbing, speed is capped at a 10 studs/s skid, so it never ploughs in or flings.
  - Tilted past ~60°, it eases itself level (the car flip-recovery's limited spin).
- **EXIT:** unchanged (hold EXIT in the air; the jump lock rules). An empty heli sinks at IdleSink to the ground, as
  before.
- **Other aircraft:**
  - every heli key shares this controller;
  - planes (bomber / jet store bodies) only get the centre-of-mass fix: their law is untouched (sim: Plane
    ComDrive, no Flight).
- **Layout:** ▲/▼ + EXIT keep their layout. The sim checks they sit clear of the top strip (the compass), the
  thumbstick zone and the aircraft FIRE buttons at 844x390, 956x440, 800x360, 1024x471 and 1180x820. There is no
  bottom minimap: the map is the full-screen one opened by tap.

**PHONE RETEST (Shaun / Laumartinez26):**
1. Spawn the Scout Helicopter at the helipad and press ▲. It should rise LEVEL (no nose-down, no lean) and hover level
   when you let go. Also try with a passenger.
2. Push the stick up: it flies where the camera looks and SPD shows real numbers. Swing the camera left while pushing:
   the nose follows with a slight bank. Push the stick sideways: it strafes. Let go: it slows and hovers.
3. Hold ▼ from high up: a fast descent that slows near the ground and touches down gently ("LANDED"). Skim the ground
   fast: it skids slowly, no bounce or fling. Fly into a building: it stops, no flip.
4. Hold EXIT in the air and on the ground: it works. ▲/▼ never cover the attack heli's FIRE buttons.
5. Fly a jet / bomber: it flies as before (level, no new lean).

## claude-bud JOB 76 ADMIN ABUSE WARLORD server-wide boss (2026-10-02; verify + finish Code Bot v242) (branch `claude/desktop-bud`)
Check: `tools/checks/claude_bud_job76.py` (J76-01..10). Sims: `tools/sim/run_warlord_test.py` (13 ok) +
`run_admin_abuse_test.py`.

**ALREADY WORKING (v241 / v242, verified in code + sim):**
- **Every server:** GIANT BOSS / WARLORD is a normal published action. One MessagingService message reaches every
  server, each server applies it once (nonce), and STOP ALL despawns it everywhere.
- **Announcement:** `AdminAbuseConfig.Actions.Boss.AnnounceText` ("⚠️ THE ADMIN IS HERE AND HE'S CAUSING CHAOS! ...")
  goes to every player as the world-boss banner with "TAP TO TRACK" (a pin, no teleport). The boss bar is tap-to-pin
  and reads ReplicatedStorage attributes, so late joiners see the live bar and a cleared one when he's gone.
- **The boss:** a ×4 HeavyInfantry soldier rig.
- **Reward:** a flat $500,000 as `world_boss` (EconomyService NEVER_MULTIPLIED, so never 2x) to every player in
  `rec.LastHitBy`, once each. Plus the Boss Slayer badge 1033687066360587 (pcall, skipped if owned).
- **No cooldown:** Cooldown 0 on the server and in the panel; a new press replaces the live one.
- **Timer:** alive after 300 s → despawned by the 1 Hz timer, bar + pin cleared. Server close → STOP ALL.
- **The panel** stays owner-only (AdminConfig in Request).
- **Double Weekend world bosses:** 500K `world_boss` + the same badge, how-to card (CardTitle / CardSteps / TRACK),
  spawn / down banners, start at `EventConfig.StartUnix` (21:00 Fri 2 Oct Dublin) via task.delay and stop at EndUnix.
- **Cost of all ~10 servers at once:** one message and one NPC per server; the bar refresh is at most 4 Hz.

**FIXED:**
- **HP** = max(30,000, 5,000 × players) as Shaun asked: 30k up to 6 players, 50k on a full 10. It was 25k + 5k ×
  players = 75k on a full server, which is about 5 minutes against the 300 s timer.
- **Heavy weapon:** 20 damage / 1.5 shots a second / 110 studs / 140 aggro (the world-boss numbers). It had the plain
  HeavyInfantry gun (16 / 1.6 / 85).
- **Double pay:** NPC kill cash is now 0, so the killer gets the same flat 500K as everyone else. Before, he also got
  the +$90 NPC kill cash.
- **STOP ALL** now also clears the owner's WORLD BOSS TEST (`WorldBossService.StopTest`). The live Double Weekend
  bosses are never removed; inside the window they come back after RespawnSeconds, the same as `/boss clear`.
- **Pins:** `codebot_v242.py` and `run_admin_abuse_test.py` HP pins accept the new formula.
- **Note:** the rig's gun is the soldier rig's own rifle scaled ×4. No new weapon model was added (it would need
  WE_CHECK2).

**PHONE RETEST (two servers):**
1. Open the Admin Abuse panel and press GIANT BOSS.
2. On both servers: the red banner "THE ADMIN IS HERE..." with TAP TO TRACK (it pins him), plus the WARLORD bar.
3. Press it again at once: no WAIT. The old one is replaced.
4. Fight him: about 30k HP with few players, 50k on a full server. Every hitter gets +$500,000 (not doubled during the
   Double Weekend), and the Boss Slayer badge on the first kill.
5. STOP ALL: the Warlord and any WORLD BOSS TEST bosses are gone on every server, and the bar clears. Rejoin: no stale
   bar.

## claude-bud JOB 74 Central Plaza DEFENDERS + PLAZA TAX (2026-10-02; done before JOB 73) (branch `claude/desktop-bud`)
All of it is behind `Shared/Configs/PlazaDefenderConfig.luau` (`OwnerFirst = true`, tagged NEW-OWNER-FIRST): it only
runs while the HOLDER is Shaun (`AdminConfig.IsPlaytestOwner`) or Laumartinez26 (11718087109). Any other holder gets
today's behaviour exactly. Check: `tools/checks/claude_bud_job74.py` (exact fail list J74-01..17).
Sim: `tools/sim/run_plaza_defenders_test.py` (39 ok).

**ROOT CAUSE (proven from the code).** The neutral guards respawn fine while the Plaza is neutral. A HELD Plaza has none,
by design:
- `Server/Modules/OutpostDefenders.luau` `step()`, its held branch (lines 208-214 before this job): when a row is `Held`, `sleep(site)` despawns every
  defender and sets `ClearedAt = now` on every pass. `Held` = `OwnerType == Player or Clan` (TerritoryService
  `Init` -> `Territories()`, ~line 1531).
- A capture never passes through Neutral. `awardCapture` (TerritoryService ~1018-1030) calls
  `releaseOwnership(rt, "captured")` and sets the new owner in the same call, so the "neutral again" branch
  (`HeldBefore` -> `ClearedAt`, then `RespawnSeconds` 150 s) never runs between two holders. The v221 Plaza Airstrike
  (`TerritoryService.InstantCapture`) runs the same `awardCapture`; its own comment says "defenders stand down because
  the zone is held".
- So `OutpostDefenders.Blocking("CentralPlaza")` is false the whole time anyone holds it. `playersInZone` lets any lone
  player count, and they flip it in `CaptureTimeSeconds` (x `ProtectedCaptureMult` during protection). The neutral
  guards only come back after the holder leaves the server (`releaseOwnership(.., "leave")`) and 150 s pass with
  someone within WakeStuds.
- JOB 51 SharedHostility and PlazaBountyConfig are not the cause: they decide WHO the guards shoot and the retake pay,
  not whether a held Plaza has guards.

**A) Defenders** (`Server/Modules/PlazaDefenders.luau`; no loop of its own, driven by OutpostDefenders' existing 2 s step):
- While a tester holds the Plaza, his defenders stand on the guard ring. They are ordinary CombatService NPCs: same
  rigs, line of sight, hit chance and kill rewards.
- Roster from POWER = Level + rebirths x 10 + army / 5. Five tiers run from 3 Infantry (x1 health / damage) up to
  6 Fort / Heavy (x2 health, x1.5 damage).
- Caps: at most 6 soldiers and 2 armour.
- Armour appears only when he OWNS one of `VehicleIds`: a parked display of his best owned armour (the game's own
  vehicle model, anchored, with no seat / joints / scripts and one Box hull) plus a Static heavy gunner on top. The
  armour goes when its crew dies.
- Hostility: `TargetFilter` = `CombatService.UnitMayHitPlayer(holder, p)` (never him, his clan allies, PvP off, a
  novice or a spawn shield), plus the JOB 51 `NpcMayTarget` pick.
- New generic NPC option `HitFilter` (CombatService `hurtNPC` + `UnitMayHitNPC`): he, his allies and their squads
  cannot hurt his defenders.
- While any of them is alive, the capture is blocked ("Defeat the defenders first!"). Killed ones return 90 s
  (`RedeploySeconds`) after the last falls, while he still holds it. Asleep when nobody is near (the same Wake / Sleep
  rule as the neutral guards).
- Takeover (a normal capture or the Plaza Airstrike), loss, or the holder leaving: his defenders despawn in the same
  pass. Unheld again: the neutral guards return after `NeutralRespawnSeconds` (150).
- Billboard "Defended by NAME · Lv X" (MaxDistance 120, not AlwaysOnTop). One toast to him: "Your troops are defending
  the Plaza".

**B) PLAZA TAX** (EconomyService `plazaTax`, ONE call in `AccruePendingCash`, on reason "passive" only):
- 10 % of every other player's passive grant (after their own multipliers) goes to the holder's ATM as `plaza_tax`.
  That reason is in NEVER_MULTIPLIED: never doubled, never taxed again.
- Never taxed: the holder himself, his clan allies, a novice-shielded player, a server with PvP off, a non-tester
  holder, and dev-product / offline / any other reason.
- The holder is published as ReplicatedStorage `WE_PlazaTaxHolder` (OutpostDefenders' step).
- Chips (`Client/PlazaTaxController`, a label, not a button): "TAXED 10% BY NAME · take the Plaza!" (red edge) /
  "PLAZA TAX +$X/s" (gold edge). They sit in the event-chip column under the TARGETS pill, one row below any visible
  DOUBLE WEEKEND / ADMIN ABUSE chip, so nothing overlaps (sim at 1024x471, 956x440, 844x390, 800x360, 1180x820).
- A 1 Hz placement loop runs only while a chip shows.

**Gate notes:**
- The pre-existing FAILs at HEAD were scoped:
  - `claude_bud_job61.py` now also accepts Code Bot's "JOB 61: SHIPPED in v183 — ..." CLAUDE.md line.
  - `codebot_v233.py` "ReferralService not on live" now also passes while ReferralConfig is still owner-first: the
    held JOB 64 wiring on desktop-bud, blocked on Creator Hub.
- JOB 72 (Admin Abuse extras, for next week) is parked, not lost: local branch `wip/job72-admin-extras` + a stash. It
  resumes after this push.

**PHONE TEST (Shaun + Laumartinez26, 2 phones, same server):**
1. Shaun captures the Central Plaza. Toast "Your troops are defending the Plaza". Within ~2 s, 6 defenders (+ up to 2
   crewed tanks if he owns a tank) and the "Defended by shaunie6 · Lv 100" billboard appear.
2. Laumartinez26 walks in: the defenders shoot her; the capture bar stays blocked ("Defeat the defenders first!") until
   they are all dead. Shaun shooting his own defenders does nothing.
3. Kill them all: the capture opens; they come back about 90 s later if Shaun still holds it.
4. Laumartinez26 takes the Plaza: Shaun's defenders vanish at once; hers (4 soldiers, Lv 24) deploy. Repeat with the
   Plaza Airstrike: the same swap.
5. Tax: while Shaun holds it, Laumartinez26 sees "TAXED 10% BY shaunie6 · take the Plaza!" under TARGETS (below the
   2x Weekend / Admin Abuse chips if they show) and Shaun sees "PLAZA TAX +$X/s". His ATM grows by 10 % of her
   passive income. Buying cash (dev product) or offline earnings: never taxed.
6. Shaun leaves the server: his defenders and both chips go; the neutral guards are back about 2.5 min later.

## claude-bud JOB 71 ADMIN ABUSE live event (2026-10-02; Sat 10 Oct 20:00–20:30 Dublin; deadline Thu 8 Oct) (branch `claude/desktop-bud`)
Labelled JOB 71 as in Code Bot's handoff / commits (this branch's CLAUDE.md still says "JOB 70"). Its check is
`tools/checks/claude_bud_job71.py`; `claude_bud_job70.py` stays the shipped JOB 70 collision / walls check.

**Config:** `Shared/Configs/AdminAbuseConfig.luau`.
- `Id "AdminAbuse1"`, Start 1791658800 / End 1791660600 (20:00 / 20:30 Dublin), `EventId "9167160688932684354"` (a
  string).
- Pop-up title / when / perks / chip text as specified.
- Every action's seconds, cooldown and amount. Nothing is hard-coded elsewhere.

**Owner panel (ADMIN-ONLY FOREVER):** Settings > ADMIN > **ADMIN ABUSE PANEL**, owner only (`Client/AdminAbuseController`).
- Two columns of 56 px buttons: ANNOUNCE (+ text box), CASH RAIN, AIRSTRIKE STORM, FREE TANK DROP, 2x CASH 10 MIN,
  LOW GRAVITY 5 MIN, SPEED FOR ALL 5 MIN, GIANT BOSS, STOP ALL, CLOSE.
- Each button shows "ON m:ss" / "WAIT m:ss".
- At 1024×471 the card sits right of the thumbstick zone and left of the jump column, with nothing overlapping (layout
  sim).
- Every press is re-checked on the server: `AdminConfig.IsPlaytestOwner` first, then RemoteGate schema + rate limit,
  then the action's cooldown.

**All servers** (`Server/Services/AdminAbuseService`):
- One `MessagingService` topic, `WE_AdminAbuse`, payload `{action, args, sentAt, nonce}`, under 900 bytes.
- Every server, the sender's included, applies it from its subscription. A nonce is applied once; a message older
  than 30 s is ignored.
- If the publish fails (Studio or an outage), the action applies on the sender's server.
- ANNOUNCE text is filtered for broadcast on the sender's server; only the filtered text travels.

**Actions:**
- **Cash Rain:** up to 30 crates near the players (the audited pack crate + its Box hull). A touch or tap pays $2,500
  once per crate per player (an EconomyService grant). The crates are gone after 60 s.
- **Airstrike Storm:** 14 blasts over 20 s near players (the WeaponFx explosion visual, no Explosion instance). Small
  damage that never kills (health floor 1); protected players are skipped; never a building, wall, gate or ATM.
- **Free Tank Drop:** every player gets a LightTank for 10 min through the normal spawn path. A one-call loan skips
  ownership / level / base / cooldown and is never written to the profile. It despawns at expiry, on leave, or on
  STOP ALL.
- **2x Cash 10 min:** `EconomyService.cashMultFor` uses `max(DOUBLE WEEKEND, 2x)`, never a product, on the
  earned-cash branch only. Raid / nuke transfers, codes and Robux are untouched.
- **Low Gravity 5 min:** Workspace.Gravity 60, with the old value restored exactly.
- **Speed for all 5 min:** x1.75 through the tagged setter. Respawns and joiners get it too. A pass owner is never
  touched, and only the players it sped up are restored.
- **Giant Boss:** one HeavyInfantry Soldier-rig NPC scaled x3, named "WARLORD".
  - HP = 4,000 + 1,500 per player.
  - Public boss health bar.
  - Gone after 5 min.
  - $25,000 once to everyone who hit it.
- **Announcement:** a big centred banner on every player's screen on every server, for 6 s.
- **STOP ALL:** ends every effect. It also runs at server close.

**Public UI** (no OwnerFirst): the DOUBLE WEEKEND chip / details card / once-per-player RSVP pop-up code
(`DoubleWeekendController`) now runs for a list of events (`run(cfg, slot)`).
- ADMIN ABUSE gets a countdown chip under TARGETS from 24 h before ("ADMIN ABUSE · in 5h 12m"; tap = details).
- "ADMIN ABUSE LIVE · 12m" shows in the window and while any owner action runs.
- The RSVP pop-up is skipped when you are already Going. NOTIFY ME = `PromptRsvpToEventAsync`.
- `DoubleEvent` saves each event's seen flag in `profile.EventPopupSeen[Id]` (no new save key).

**Proof:**
- `tools/sim/run_admin_abuse_test.py` (the REAL service with fakes):
  - a non-owner is refused (nothing published); the owner's press is published once; cooldown;
  - nonce applied once; a stale message ignored; a failed publish applies locally;
  - gravity set / restored by STOP ALL and by its timer; 2x on / off;
  - speed 28 then restored (pass owner untouched);
  - airstrike 10 hp -> 1, protected and out-of-radius untouched;
  - 99 crates asked -> 30, and a crate pays once;
  - tanks for every player (LightTank, 600 s);
  - boss HP scaling, a reward once to each of 2 hitters, and nothing on a second death;
  - only the filtered announcement travels, and the banner reaches every player.
- `tools/sim/run_admin_abuse_layout_test.py`: 1024×471 has 56 px controls, no overlap, out of the thumbstick / jump
  zones.
- `tools/checks/claude_bud_job71.py`: every brief proof + both sims.

**Code Bot:**
- Bump `WE_Build` (lanes never do).
- Run the Studio 2-server / 2-player test of every action (MessagingService needs a real published game or a Team Test
  for cross-server).
- Publish by Thu 8 Oct.

**Test ON HIS PHONE (two servers):**
1. Settings > ADMIN > ADMIN ABUSE PANEL opens; the buttons are big and nothing overlaps.
2. Press each button and check a friend on a SECOND server sees it:
   - crates you can grab once each;
   - blasts that hurt but never kill;
   - a free tank for 10 min;
   - 2x cash;
   - floaty gravity;
   - fast running;
   - the WARLORD with a health bar (its kill pays everyone who hit it);
   - your typed announcement.
3. STOP ALL ends everything at once.
4. Any player sees the ADMIN ABUSE chip under TARGETS and the one-time pop-up with NOTIFY ME.

## claude-bud HONEST SHOP TEXT (2026-10-02, Shaun item 6) (branch `claude/desktop-bud`)
**Proven from code:** the VIP and 2x Cash multipliers apply to income, training, kills, missions, dailies, achievements,
level-ups and bounties. They do NOT apply to jobs (ops), supply drops, oil pumps, ATM / bank raids, offline cash, codes
or Robux (`MonetizationConfig.CashMultExemptReasons`).

**Text changes** (in-game Shop / boards only; names, prices and Ids unchanged):

| Item | Was | Now |
|---|---|---|
| VIP | "+25% cash on everything you earn" | "+25% income, kill & mission cash" |
| VIP (Shop overhaul, the live +50%) | "+50% cash, a daily cash crate and VIP lounge" | "+50% income & kill cash, daily crate, lounge" |
| 2x Cash | "Double your cash income" | "2x income, kills & mission cash, forever" |
| 2x Offline Cash | "Offline cash for 4 hours instead of 2 hours" | "Offline cash builds 4 h, not 2 h (same rate)" |

The 2x Offline Cash pass doubles the cap TIME (2 h -> 4 h), never the 10 % rate.

**Already right:** Golden Pumpjacks. The Shop line is `GoldenBoost.Description` "+15% on all your base income, forever"
while GoldenBoost is live (public since v213). The old "earn 50% more" literal only shows if that block is switched off,
and a check pins it as the legacy text.

**Proof:** `tools/checks/claude_bud_shop_text.py`.
- Each number is read back from its config: VIP CashBonusMult 0.25, ShopOverhaul 0.5, DoubleCash 2, OfflineConfig
  2 h x 2, Golden IncomePct 15.
- Each named / unnamed reason class matches the exempt list.
- Every text is <= 44 chars (the phone row).

codebot_v203's exact-text pin is scoped to its own build; the <= 44 rule and the 4 h / 2 h facts are checked always.

**Code Bot:** the Creator Hub (Roblox purchase prompt) descriptions for VIP / 2x Cash / 2x Offline Cash may want the
same wording.

**Test ON HIS PHONE:** Shop -> SUPPLY · R$: the VIP, 2x Cash and 2x Offline Cash rows read as above and fit on one line.

## claude-bud JOB 66 SPEED TRIAL (2026-10-02, Shaun item 5) (branch `claude/desktop-bud`)
**Rollout:** PUBLIC (`SpeedTrialConfig.OwnerFirst = false`: Shaun approved going straight live).
**CODE BOT: create the 1 R$ developer product "Speed Trial" in Creator Hub and paste its id into
`SpeedTrialConfig.ProductId`.** Until then the Shop row stays hidden (ProductId 0 is never sold or owned).

**Built:**
- **Shop row** "Speed Trial · Timed sprint · cash prize + 5 min speed":
  - hidden for Speed Pass / Speed Boost owners;
  - opens the **How to play** card (what, 3 steps, time limit, reward, big START / CANCEL; the shared phone-safe card);
  - START uses a saved entry, or opens Roblox's 1 R$ prompt.
- **ProcessReceipt** (MonetizationService -> SpeedTrialService):
  - +1 saved entry on the same ProcessedReceipts ledger, saved before the ack (idempotent);
  - then the run starts at once and spends it;
  - an entry left by a disconnect waits for the next START (no second charge).
- **The run** (`SpeedTrialService`, one 4 Hz loop only while a run is on):
  - 6 rings 110 studs apart along the nearest main road from where you stand, heading inward; only one ring shows at a
    time;
  - the shared top pill "SPEED TRIAL 2/6 · 0:41" (timer + step counter), a CANCEL chip, and the ONE objective arrow to
    the next ring;
  - the limit is 55 s plus the walk to the first ring.
- **Speed:** x1.6 walk speed for 5 min (travel only), below the Speed Pass (x1.75), through the one tagged WalkSpeed
  setter; re-applied on respawn and restored after. A Speed Pass owner gets no extra.
- **Prize:** finish in time for 3 min of your income ($1,500-$60,000), paid as a purchase grant (never doubled) + your
  best time saved. Out of time or cancel = no prize; the boost stays.
- **Save:** one new sanitised key, `profile.SpeedTrial` (Entries / Runs / Best).

**Proof:**
- `tools/sim/run_speed_trial_test.py` (the real config + service with fakes):
  - course;
  - entry required and spent;
  - boost x1.6 via the setter;
  - pill fields;
  - 6 rings, then the prize paid once as devproduct and the best time saved;
  - timeout and cancel pay nothing;
  - a Speed Pass owner is not touched.
- `tools/checks/claude_bud_job66_speed_trial.py`: Code Bot's docs pins + implementation pins + the sim.

**Test ON HIS PHONE (once the product id is in):**
1. Shop -> Speed Trial: the How to play card appears.
2. 1 R$ START buys; the run starts.
3. Follow the arrow through 6 rings before the clock ends: "+$..." and your best time.
4. CANCEL ends it.
5. You run faster for 5 min.

## claude-bud DRIVABLE SYNTY VEHICLES (2026-10-02, Shaun item 4) (branch `claude/desktop-bud`)
**Flag:** `Shared/Configs/SyntyVehicleConfig` (NEW-OWNER-FIRST, by the vehicle owner). OFF = today's bodies.

**Built:** Shaun's paid Synty Polygon Military Vehicles pack (119390702773907, already audited: 0 scripts) now dresses
the drivable wheeled vehicles:

| Vehicle | First candidate | Note |
|---|---|---|
| ArmoredTruck | `SM_Veh_Truck_01` | |
| ArmedJeep | `SM_Veh_Pickup_Technical_01` | keeps its own gun visible |
| ScoutCar | `SM_Veh_SUV_01` | |

- **Dress-only,** through the existing store-body path (`VisualAssetService.TryAttachVehicleVisual`, Fit = Kit): the
  Part-kit chassis still drives (same thumbstick controls, same light hinge physics, same seats), and the body never
  collides.
- `VisualAssetService.SyntyRef` tries each vehicle's candidate names in order and uses the first the pack really holds.
  The pack splitter extracts the candidates via `pieceRefsFor`.
- None found = today's body exactly; each missing name is logged once.
- Tanks stay on their Part kits: you declined low-poly tanks earlier, and a hull would hide the kit turret.
- VisualAssetConfig is untouched (byte-pinned).

**Proof:** `tools/checks/claude_bud_synty_vehicles.py` (config, wiring, fallback, no tanks, the real config's refs in
Luau).

**Owed (Studio):**
- The intact piece names: only the `_Destroyed` names are on record, and the intact ones are inferred from them. Code
  Bot's `/zonereport`-style pack probe can list the real ones; add any to `Candidates`.
- Yaw 180 (front direction) and seat height.

**Test ON HIS PHONE:** spawn the Armored Truck, the Armed 4x4 and the Scout Car. Each wears the Synty body (or today's
body if the name did not match). Drive with the thumbstick as before.

## claude-bud TURRET + WALL LOOKS ON ONE CONFIG (2026-10-02, Shaun item 3) (branch `claude/desktop-bud`)
**What was there:**
- Turrets already had 5 looks: the Minigun pack Lvl 1 / 3 / 5 / 8 / 10, by Turret Guns level 0 | 1-3 | 4-6 | 7-9 | 10.
- Walls already had 5 looks: L1 Sandbag Line -> L5 Hesco Fortress, on every side since JOB 70.

**The gap (proven):** three separate tables decided the turret tier, and nothing tied them together.
- `VisualAssetConfig.Job67.TurretTierAt` (the gun model).
- `EndgameConfig.DefenceVisuals.TierAt` (the extra turret / gate / vault parts).
- The gameplay `Defence.GunsPct`.
- The upgrade text never said which look a level gives.

**Built:**
- **One table, `EndgameConfig.Defence.TurretTiers`** (At / Names Mk I-Mk V / Keys AutoGunT1-5).
  - `EndgameConfig.TurretTier` / `TurretTierName`, the gun model pick in GateDefenseService (`TurretTier` + the
    central Keys) and `DefenceVisualTier` all read it.
  - VisualAssetConfig is byte-pinned (codebot_v211 / v219), so it is untouched: its `Job67.TurretTierAt` / `TurretTierKeys`
    and `DefenceVisuals.TierAt` stay as mirrors, and the check asserts they equal the central table.
- **Text** (`EndgameConfig.TierText`, NEW-OWNER-FIRST):
  - The Engineering Bureau Guns row says e.g. "+42% turret + guard dmg · Mk IV gun".
  - The base console's Defensive Walls row says "Next look: Hesco Line" (from `Job67DressConfig.Walls.Tiers`, the same
    saved level the walls are built from).
  - OFF = today's text.
- Save keys, levels and prices are untouched (no BaseConfig / MonetizationConfig edit).

**Proof:** `tools/checks/claude_bud_tier_looks.py`, on the real configs in Luau.
- For Guns L0-10, the gameplay tier = look tier = model key = visual-parts tier.
- The mirrors equal the central table.
- Each tier is a bigger, higher Minigun level than the last.
- Damage rises every level.
- The text names the Mk, and is today's text when off.
- Walls L1-5 each have a distinct look on every face.

**Test ON HIS PHONE:**
1. Engineering Bureau: the Turret Guns row names the gun Mk you get.
2. Base console: the Defensive Walls row says the next wall look.
3. Upgrade Turret Guns past L1 / L4 / L7 / L10: the gun model gets bigger each time.

## claude-bud REBIRTH-ZONE BUILDINGS (2026-10-02, Shaun item 2) (branch `claude/desktop-bud`)
**Flag:** `Job67DressConfig.ZoneBuildings` (`OwnerFirst = true`, tagged NEW-OWNER-FIRST; by the base owner). OFF =
today's zones exactly.

**Root cause (from config):**
- The store-model zone swap (`StorePropsConfig.ZoneRows`) costs ~6.9k parts per fully upgraded plot.
- It stops at `Budget.MaxZoneServerParts = 16,000`, i.e. about 2 plots; every other plot index keeps the block build.
- EastYard always keeps its Part barracks (`ZoneKeepParts`).

**Built:**
- On every zone still showing its block build, the zone's MAIN block building becomes a detailed free desert house
  (`Job67DressService.DressZone`, called by RebirthZoneService right after the Part build, off its thread):

  | Zone | Block building replaced | House |
  |---|---|---|
  | WestYard | hangar | Prinz 2 |
  | StrategicYard | bunker | CAG camp |
  | WestStrip | bunker | Prinz 1 |
  | DroneBay | hangar | Prinz 3 |
  | EastYard | barracks | Imp |
  | EastStrip | a fuel tank | CAG control house |
  | WestFlank | bunker | Prinz 1 |

  Packs: Prinz = Desert Houses 10055885754, CAG = 9939040273, Imp = 15654066038.
- **Fit:** `Cfg.ZoneFit` fits the house into the block's footprint (scale 0.55–1.25), on the yard, facing the base.
- **Collision:** the house's big parts collide (the audited, stripped Buildings template), and the block cluster is
  removed. The zone folder rebuilds on every level change, so turning the flag off brings the block back.
- **No clash with store models:** a zone already wearing store models is left alone; if the store swap lands later it
  replaces the house too.
- **Budget:** all 7 houses = 1,151 parts, under `MaxPartsPerPlot 1300`.

**Proof:** `tools/checks/claude_bud_zone_buildings.py`.
- Every one of the 7 rows replaces a block the Part build really makes at level 1 at that spot (parsed from
  RebirthZoneBuilder).
- Every model comes from the three requested packs.
- The part budget holds.
- DressZone rules: skip store zones, owner-first, budget, remove the block, colliding template, never `WE_Building*`.
- The REAL ZoneFit is run in Luau.

**Also:** codebot_v220's "no OwnerFirst = true left" guard skips lines tagged `NEW-OWNER-FIRST (claude-bud` (a feature
added after v220 starts owner-first by the house rule) plus the two blocked jobs (JOB 62 / JOB 64 configs).

**Owed (Studio / phone):** the house scale and facing in each zone, and doors reachable.

**Test ON HIS PHONE:** visit your rebirth zones. Each one's main building is now a detailed desert house (hangars,
bunkers, the barracks and one refinery tank replaced). Walk into a house: it is solid. The kiosks, consoles and runs
still work.

## claude-bud JOB 68 (2026-10-02): SHOOTING RANGE LIFE (branch `claude/desktop-bud`)
**Flag:** `Shared/Configs/RangeLifeConfig` Enabled + `OwnerFirst = true` (live for the viewing owner). OFF = today's
still statues.

**Built (client-side cosmetic only; nothing replicates, no remote, no damage):**
- New `Client/Controllers/RangeLifeController`. Every base's Training Yard firing-line soldiers (`YardShooter1..3`:
  the existing R-RIG statues of Roblox's Soldier with the rifle forward, no new models) fire at their lane's red
  bullseye board on a loop. Each shot:
  - a muzzle flash (1 particle, no light);
  - a short 3D rifle sound;
  - a sand-impact tick;
  - a small dust puff;
  - a bullet hole on the board face (4 per board, pooled).
- Every 6 shots the soldier reloads: the rifle arm dips 38° for 2.2 s (a local Right Shoulder C0, restored after),
  with the magazine sound. Statues are anchored, so a track never loads; this is the honest "reload animation" for a
  base statue.
- Mobile-light:
  - one shared 4 Hz `task.wait` loop for every range; no per-NPC Heartbeat, no tree scans (shooters come from the
    `WE_Rig` tag);
  - effects only for shooters within 80 studs: the nearest 2 ranges, at most 4 per range, 8 total;
  - shots 1.1–2.6 s apart.
- Sound keys (SoundConfig): `World.RangeShot` (max 80 studs), `World.RangeReload` / `World.RangeHit` (40). They reuse
  the live rifle / magazine / sand-impact files, so no new asset ids.

**Proof:**
- `tools/sim/run_range_life_test.py`:
  - near-only pick (2 ranges × 3, nothing when far);
  - 6 shots then a reload, every time;
  - shots ≥ 1.1 s apart;
  - reload ≥ 2.2 s;
  - holes on the board face toward the shooter, inside the red ring.
- `tools/checks/claude_bud_job68.py`: config, Bootstrap, no Heartbeat / RenderStepped / GetDescendants / lights /
  remotes, one loop, the 3 sound keys 3D and short-range.

**Owed (Studio / phone):** the flash position at the real rifle muzzle, the reload dip angle on the Soldier body, and
the sound levels.

**Test ON HIS PHONE:** walk to your Training Yard. The 3 soldiers at the firing line shoot their targets, you see
flashes and holes appear on the boards, and now and then one lowers his rifle to reload. Walk 80+ studs away: it
stops. Frame rate stays steady.

## claude-bud JOB 69 parts B + C (2026-10-02): HOW TO PLAY EVERYWHERE (branch `claude/desktop-bud`)
**Flag:** `RebirthZonesConfig.Rebuild.HowTo` (owner-first via Rebuild). OFF = today's kiosks / rows / instant START
exactly.

**B: zone runs (mobile-first):**
- Tapping a kiosk (`START`, `<RUN TITLE> · N s`) shows the **how-to card** instead of starting the run.
  - The server sends FeaturePush `ZoneRunIntro`: title, one-line goal, 3 steps, reward, time, cooldown, run in progress.
  - The full card shows until the first clear (`profile.ZoneFirstClear`; no new save key), then the compact card.
- START / CANCEL go through the new `RequestZoneRun("start"|"cancel", zoneId)` (RemoteGate schema + RateLimit
  `zone_run` 1 per 2 s). The server decides; CANCEL ends the run with no reward and **no cooldown**.
- Tracker: `ZoneRuns.showStep` now sends Title / Label / Pos. The new `ZoneRunController` shows the progress pill
  `DRILL COURSE 2/4 · 0:23`, a CANCEL chip and the ONE `ObjectiveMarker` arrow on the current pad (1 Hz countdown).
- Wording:
  - Shuffle steps read `VALVE 2 OF 4`.
  - "Finish your current run first" becomes `<TITLE> in progress · m:ss left`.
- Elite Training is back: a second `TRAIN` prompt on the Elite Barracks kiosk.
- Card layout is phone-safe (`ZoneRunController.CardLayout`):
  - scaled by screen height; buttons are 44+ px real;
  - right of the thumbstick zone (x > 40 %), left of the jump / fire column, below the top bar.

**C: explanations everywhere:**
- All 48 registered rows carry an inline `HowTo = { What, Steps, TimeLimit, Reward }`: zone runs, site activities,
  daily ops, missions and jobs. `tools/checks/claude_bud_job69.py` fails on any row without one.
- One shared lookup, `Shared/Util/HowTo.luau` (Find / Line / Card / Live), built once.
- Missions panel (when live):
  - mission, activity and job rows show the one-line "what to do";
  - activity START and job GO open the same how-to card first;
  - the card's START / GO sends the same request as before, and the server still decides.

**Proof:**
- `tools/sim/run_zone_run_layout_test.py`: 1024×471, 956×440, 844×390, 800×360, 1180×820, full and compact, 0 failed.
- `tools/sim/run_howto_test.py`: the real configs; owner-first verified (another player gets the old rows).
- `run_rebirth_stations_test.py` section 8: intro / start / cancel / busy text / TRAIN / tracker push, 0 failed.

**Owed (Studio / phone):** the card's look on a real phone, the arrow on each pad, and the TRAIN prompt offset beside
START.

**Test ON HIS PHONE:**
1. At a rebirth-zone kiosk, tap START: the how-to card appears. START begins the run; the top pill counts down, and an
   arrow points to each pad.
2. During a run, tap CANCEL on the pill: the run ends, and you can start it again at once.
3. Elite Barracks: a TRAIN prompt opens Elite Training.
4. Open Missions: every row says what to do. ACTIVITIES START and JOBS GO show the how-to card first.

## claude-bud JOB 69 part A (2026-10-02): EVERY REBIRTH ZONE ON EVERY PLOT (branch `claude/desktop-bud`)
**Flag:** `RebirthZonesConfig.Rebuild.Slots` (inside Rebuild: owner-first by the PLOT OWNER). OFF = today's placement
exactly.

**Root cause (reproduced):** each zone had one fixed annex slot per plot. Roads, the land edge, dock channels and
other plots blocked 29 of the 70 plot × zone pairs:
- P1–P6 lose Artillery + Refinery;
- P3 / P4 / P9 / P10 lose the Nuclear Silo;
- P7 loses both east zones;
- P8 loses all 3 west zones;
- P9 / P10 keep only 2 zones.

**Built:**
- **`RebirthZonesConfig.AnnexAlt`:** the brief's 24 fallback slots (±218, then ±290 / ±360 at Z 100 / 10 / -80 /
  190), plus `SlotGap 6`, `SlotApron 26`, `SlotOrder` (the Silo first) and `BoardSpots`.
- **One pure resolver, `RebirthZonesConfig.ResolveSlots(isFree, alts)`:** own slot first, then the fallbacks in
  order, skipping any that overlap a zone already placed on that plot.
- **RebirthZoneService:** `slotFrame` (cached per plot) replaces `annexFrame` everywhere (build, kiosk / run start,
  apron). With fallbacks on, a slot also needs its front apron.
  - `WE_AnnexCFrame` is stamped on each `Zone_<Id>` folder, and the store-prop dresser reads it.
  - A zone with no slot at all gets a **ZONE BOARD** console in the base carrying its buy / upgrade prompts.
  - One warning per blocked zone.
- **Admin `/zonereport`:** every plot × zone (own slot / fallback (x,z) / BLOCKED) in Output, plus the blocked count.

**Proof:** `tools/sim/run_zone_slots_test.py` runs the REAL resolver over all 10 plots × 7 zones against the map
geometry from config (land edge, 6 roads ±12, every plot pad, every dock channel, public water, sites, outposts).
- With fallbacks: **70 / 70 placed, 0 blocked, no overlaps.** The Silo is on every plot.
- Without (OFF): today's 29 gaps.
- Wired into `tools/checks/claude_bud_job69.py`.

**Owed (Studio):**
- `/zonereport` on the live map (the real part overlap test also sees decor the config does not).
- A look at the fallback zones (e.g. P10's at X ±360).

**Not yet (next):** JOB 69 parts B (zone-run how-to card / tracker / cancel / TRAIN) and C (how-to text for all 48
registered activities, missions and jobs). The `JOB69 HowTo` check fails until C lands; it is the only failing check.

**Test ON HIS PHONE:**
1. Rejoin on a plot that was missing zones (e.g. P9 / P10): every rebirth zone you have unlocked now stands around
   your base, the Nuclear Silo included.
2. Type `/zonereport`: 0 blocked.

## claude-bud JOB 66 (2026-10-01): THE TWO 5 R$ STARTER PRODUCTS (branch `claude/desktop-bud`)
**Flag:** `MonetizationConfig.Starter5` (owner-first, NEW-OWNER-FIRST). OFF = today.

**Built:**
- **A) Recruit Starter Pack** (`DevProducts.StarterRecruit5`): 5 R$, ONE-TIME (entitlement `StarterRecruit5`; the Shop
  row flips to OWNED).
  - 3 soldiers join at once through `SoldierService.GrantFree` (within the army cap).
  - Starter cash = 2.5 min of his income (min $750, max $20,000; `Starter5Cash`), paid as `devproduct`, so never
    multiplied.
  - **How it relates to RecruitPackOffer:** the 49 R$ Recruit Pack (cash + 30-min 2x + gold trim, no soldiers) is
    unchanged. The 5 R$ offer reuses its offer machinery (`RecruitPackService`: the soft-offer slot budget, onboarding
    / combat / seated guards, the client card with its shown / dropped ack). For a player Starter5 is live for, his
    one-time card is the "5 R$ ONE-TIME OFFER" at 5 min of play, with its own saved flag `Starter5Offered`. Everyone
    else gets the 49 R$ card at 10 min exactly as before.
- **B) 10-Minute 2x Income Boost** (`DevProducts.Boost2x10m`): 5 R$, repeatable. It uses the ONE boost path
  (`CodesService.GrantCashBoost`, x2, extends a running boost) and the central `cashMultFor`
  (`EconomyService.CashBoostMult`). Robux grants are never multiplied (`devproduct` is exempt).
  - A small HUD chip "2x m:ss" (`BoostChip` in the top strip, the same row-fit rules as the other chips) shows while
    the boost runs, ticking 1 Hz only then.
- **Both:** in the Shop (Id 0 rows stay hidden until created) and gated by `SkuLiveFor` through the row's `LiveBlock`
  (owner-first for the Shop and the purchase intent). Granted in `ProcessReceipt` with the existing idempotent pattern
  (before `markProcessed` / the save).

**Guards touched (please keep when you ship):**
- **v180-v196:** each pins MonetizationConfig byte-identical to its own previous tip. They now strip ONLY the exact
  JOB 66 block (`_bud_j66`) before comparing; v180 allows only the two 5 R$ rows. Proven: with RecruitPack set to
  50 R$ they still FAIL.
- **v196 (like v193):** the "JOB 62 not shipped" pin also accepts the bud branch while JOB 62 stays owner-first.
- **`claude_bud_job68.py`:** Code Bot's docs-only queue guard made BuyPathStatic-safe (root = cwd, no SystemExit, no
  worktree-diff guard).

**Code Bot must do (I have no Open Cloud key here):**
1. Create the 2 developer products at 5 R$ each: "Recruit Starter Pack" and "2x Income 10 min".
2. Turn OFF managed / dynamic pricing on both.
3. Put the ids in `DevProducts.StarterRecruit5.Id` / `Boost2x10m.Id`.

Until then nothing can be bought or offered (Id 0 never prompts).

**Tests:**
- `tools/sim/run_starter5_test.py`:
  - rows: 5 R$, Id 0, one-time pack with 3 soldiers + cash, repeatable 10-min boost, no pay-to-win keys;
  - cash sizing;
  - owner-first SKU;
  - the owner's card at 5:01 (not at 4:50) with its own flag, never again;
  - another player: no 5 R$ card, the Recruit Pack at 10:01 unchanged.
- `run_recruit_pack_test.py` JOB 66 section (the REAL ProcessReceipt): Starter Pack = +3 soldiers via GrantFree + $1,000
  devproduct cash at $400/min + the one-time entitlement, a re-delivered receipt grants nothing; the 10-min boost goes
  through GrantCashBoost (10 min, x2), and 2 buys = 2 grants.
- `tools/checks/claude_bud_job66.py`.
- **Owed:** a real purchase test once the ids exist (Studio or live, as Shaun).

**Test ON HIS PHONE (after the ids are in):**
1. Play 5 min: the "5 R$ ONE-TIME OFFER" card (3 soldiers + $X). Buy: +3 soldiers and +$X.
2. The Shop row then shows OWNED.
3. Buy "2x Income 10 min": a green "2x 9:59" chip. Buy again: the timer extends.

## claude-bud JOB 67 sub-part 1 (2026-10-01): TURRET TIERS WIRED, PENDING THE ASSET CHECK (branch `claude/desktop-bud`)
**Flag:** `VisualAssetConfig.Job67` (owner-first by the base owner, NEW-OWNER-FIRST).

**Built:**
- **Tier refs:** `VisualAssetConfig.GateDefense.AutoGunT1..T5` for Shaun's paid Minigun Turret Pack `109072907337393`
  (pack levels 1 / 3 / 5 / 8 / 10). All are `ModelAssetId = 0, PendingAssetId = 109072907337393` until promoted.
- **Tier rule:** from the owner's saved Turret Guns level (`VisualAssetConfig.TurretTierFor`): 0 = T1, 1-3 = T2,
  4-6 = T3, 7-9 = T4, 10 = T5.
- **Code:** `GateDefenseService.spawnAutoGun` takes the tier.
  - A new `loadCatalogPiece` inserts the pack once, strips its script, clones the named level out and applies the same
    40-part / no-Humanoid refusal.
  - A tier with no promoted model keeps today's gun exactly.
- **Wire tool:** a registry row in `tools/wire-asset-ids.py` (`MinigunTurretPack`, PENDING-GET, Studio check, batch
  P1). The `docs/ASSET_WIRING.md` table is regenerated.

**Code Bot must do (Studio):**
1. Run WE_CHECK2 on `109072907337393`.
2. Fill in each tier ref's `ChildName` with the pack's model name for Lvl 1 / 3 / 5 / 8 / 10 (each piece <= 40 parts,
   <= 20k tris).
3. `python3 tools/wire-asset-ids.py promote MinigunTurretPack --we-check <file>`.

The turrets then change look by tier for the owner.

**Tests:** `tools/sim/run_turret_tier_test.py` (level -> tier 0..10; all 5 refs PENDING) and
`tools/checks/claude_bud_job67.py`.

**Next:** walls, rebirth-zone buildings, props and the Synty vehicles (same PENDING path). On hold: Shaun asked to do
JOB 66 (the 5 R$ products) first.

## claude-bud JOB 65 (2026-10-01): NUKE INSTANT RAID (branch `claude/desktop-bud`)
**Flag:** `RebirthZonesConfig.NukeRaid` (owner-first by the ATTACKER, NEW-OWNER-FIRST): only Shaun until his phone test.

**Built on the live nuke + raid systems (nothing rewritten):**
- **Unlock:** the existing rebirth silo (NukeService `siloLevel` ≥ 1: StrategicYard, Rebirth 2, built).
- **Targeting:**
  - TARGETS rows get a **NUKE** button when the server says he can nuke (row field `Nuke`).
  - It opens a server preview (`RequestNuke "rpreview" <plotId>`): FeaturePush `NukeRaidPreview` with the name, base
    level and the EXACT cash, i.e. the victim's full raidable ATM from `MoneyCollectorService.GetRaidableBalance`, the
    same number the launch moves.
  - The card is 420 x 268, with CANCEL 170 x 64 and LAUNCH 190 x 64. A blocked target shows why; a cooldown shows m:ss
    on the button.
- **Launch:** `RequestNuke "rlaunch"` → `NukeService.RaidLaunch`.
  - It re-runs every check on the server, takes one warhead (`NukeSilo`) and the cooldown (`NukeLastLaunch`, saved:
    existing keys only) BEFORE the money moves, then calls `MoneyCollectorService.NukeRaid`.
  - `NukeRaid` uses the raid checks plus the raid money path: `_MoveLoot` moves the victim's ATM to the attacker's
    ATM 1:1, then the new `EconomyService.PendingToCash` moves exactly that amount into his Cash. No multiplier
    anywhere, so **no Double Weekend on a transfer**.
  - The victim gets the raid shield, the raid report, `NUKE_RAID` analytics and the BaseRaided notification (JOB 62).
  - If nothing moved (a last-moment race), the warhead and cooldown come back.
- **VFX:** the existing MissileStrikeFx packet (procedural missile + small explosion, culled / capped on phones) flies
  from his base to the target's gate in 6 s, plus the light NukeBlast flash. `NukeRaid.Vfx` turns it off.
- **Fairness:** the raid rules (shield, new player, low balance, allies via CanArmyRaid), the ONE protection rule
  (`CombatService.ProtectedReason`: spawn / novice), never an admin (AdminService.IsAdmin), the JOB 63 same-base
  cooldown, never his own base. Each one is a switch in `NukeRaid.Targets`.
- **Cooldown:** 30 min (`NukeRaid.CooldownSeconds`), sharing the silo's saved `NukeLastLaunch`.
- **Logs:** `[NukeRaid] uid=.. -> victim=.. plot=.. preview=.. moved=..`

**Tests:**
- `tools/sim/run_nuke_raid_test.py` (the real NukeService):
  - the preview shows name / level / the full ATM; launch stolen == preview; the target's ATM = 0; no x2;
  - 1 warhead spent + cooldown saved; the VFX packet;
  - cooldown refused + the time on the card;
  - shield / new / protected / ally / admin / JOB 63 cooldown / own base refused with nothing moved;
  - no warhead / no silo; race refund; allowed after the cooldown; owner-first.
- `tools/checks/claude_bud_job65.py` pins that the real money path never multiplies (TransferPendingCash +
  PendingToCash) and that NukeRaid uses the raid path.
- **Owed: the 2-real-player Studio test the brief asks for** (preview = stolen, target ATM 0, shield blocks, cooldown).
  Studio cannot be run from this session.

**Test ON HIS PHONE (with an alt that has cash in its ATM, Shaun with the silo built + a warhead):**
1. Open TARGETS and tap NUKE on the alt: the card shows its name, level and $X. LAUNCH.
2. A missile hits its base. You get +$X, and its ATM shows 0.
3. Tap NUKE again: the button shows the 30:00 countdown.
4. On a shielded alt: "Shielded after a raid", LOCKED.

## claude-bud JOB 63 (2026-10-01): ANTI-SPAWN-CAMPING (branch `claude/desktop-bud`)
**Flag:** `RaidConfig.AntiCamp` (owner-first by the BASE OWNER, NEW-OWNER-FIRST). OFF = today.

**Built (`Services/AntiCampService` + hooks), all through the ONE protection rule:** CombatService `pvpBlock` /
`state.InvulnerableUntil`, which every player gun, army unit, turret, base guard and vehicle hit already passes.
- **Defender shield:** a respawn at his own base gets 5 s of the normal spawn protection (was 3 s), shown by the
  existing spawn bubble (`WE_ShieldUntil`). His first shot (RequestFire) ends it.
- **Raider limit:** 90 s inside another player's base sends him back to his own base through the normal respawn
  (`Player:LoadCharacter`, so CombatService spawns him at home; no teleport), with a short notice. The same happens
  3 s after his raid takes the loot, and after 3 kills of the same defender inside 60 s.
- **Same-base cooldown, 3 min:**
  - stepping back in sends him home again;
  - he can't hurt the owner (pvpBlock reason `camp_cooldown`) or the base (`GateDefenseService.applyDamageFrom`);
  - the TARGETS card row shows `WAIT m:ss`;
  - near the base edge he gets one throttled toast "Base cooldown m:ss".
- **Logs:** `[AntiCamp] uid=.. plot=.. back to base (time|loot|kills|cooldown), cooldown 180 s`.

**Tests:**
- `tools/sim/run_anti_camp_test.py`: shield 5 s owner-only; 89 s nothing / 90 s home; cooldown re-entry, no hurt /
  no base damage, edge toast once; after the cooldown allowed; 3rd kill in 60 s home; a non-live owner's base
  untouched.
- `tools/checks/claude_bud_job63.py`.
- **Owed (the brief asks for it before calling it fixed): the 2-player Studio test.** Studio cannot be run from
  this session.

**Test ON HIS PHONE (with an alt raiding Shaun's base):**
1. The alt stands in your base for 90 s: it respawns at its own base, with a notice.
2. It walks back: sent home again; its TARGETS card shows WAIT.
3. You die and respawn: about 5 s of shield bubble that drops when you fire.

## claude-bud JOB 60 (2026-10-01): ERROR REPORT: AUDITED; MOSTLY BLOCKED ON THE CSV TEXT (branch `claude/desktop-bud`)
**What I could prove from the code (pinned in `tools/checks/claude_bud_job60.py`):**
- **AnchorPoint nil (67):** the root cause was the TARGETS crosshair reading `spec[5]` (nil), already fixed in v171
  (`RivalController`: `spec[4]`). Every other non-literal `AnchorPoint` source (CombatController `AM.Anchor` /
  `TC.Fire.Anchor` / `TC.Reload.Anchor`, MissileController `e.Anchor`) is defined. The check fails on any new unknown
  source. If the next report still shows it, its script line names the new spot.
- **Animation-track limit (340):** the game's own tracks cannot pile up.
  - There are only 2 `LoadAnimation` paths: WeaponVisuals caches one track per (Animator, id), and RigAnimator loads
    only when a figure has none and destroys on stop.
  - So the warnings come from an Animator the game doesn't drive (most likely a player character's default Animate
    or emote tracks, or a store model's own script). **Needed:** the warning's Animator path from the CSV.
- **Sanitized-ID animations (2,233 client / 265 server):** the v148 `AvatarMoodGuard` swaps known-bad dynamic-head
  moods. The new counts mean other ids or paths are still loading, and I can't name them without the report's asset
  ids.
  - The guard's own server-side `GetAnimationClipAsync` probe of an unknown id may itself be what logs the server
    copies (one per new id per server).
  - **Needed:** the top asset ids in the "sanitized ID" rows (client and server).
- **Mesh fetch (98) / sound ConnectFail (42):** both need the asset ids from the CSV. ConnectFail is a network
  failure on a sound download. v147 already spread the join-time sound loads; the JOB 59 sounds load lazily (only
  when played).

**Ask for Shaun / Code Bot:** export the Creator Hub error report CSV (Analytics → Errors → the top 6 rows, with the
full message + script + asset id) into `docs/proof/errors/` and re-queue JOB 60. Each one can then be fixed at its
source. No symptom patch was made (house rule).

## claude-bud JOB 59 (2026-10-01): FREE ASSETS PASS: (B) SOUNDS BUILT; (A) / (C) / (D) NEED THE ASSET PIPELINE (branch `claude/desktop-bud`)
**Flag:** `SoundConfig.Pass59` (owner-first, NEW-OWNER-FIRST).

**(B) Sound pass, built:** it extends the existing SoundConfig + AudioController (no second audio system).
- **New keys:** night crickets 9112764546, night ambience 9112835836, harbor night 9112792684, flag flap
  9114461215 / 9114576083, radio chatter 9112851398 / 9125793009, distant artillery 9113169264, gate 9116875342,
  boat 9126201834, the march cut 1845181958, the alternative click 15675032796.
- **Already wired before:** desert wind 9114057104, heli 9113417759, cash 9113728042, Military March 1844397606 /
  1841116989.
- **Owner-only id swaps** (`Pass59.Overrides`, applied in `AudioController.Init`; OFF = today's sounds): heli
  9125390124, boat 9112750448, raid siren 9119661640, UI click 15675059323.
- **`Client/Controllers/AmbienceController`** (1 Hz, owner-first, everything through AudioController so the SFX toggle,
  distance skip and voice caps apply):
  - the "Night" loop: crickets on land, the harbor bed near his dock basin, nothing by day;
  - radio chatter by HIS Command Center (3D, 45 studs);
  - the plaza flag flap (3D, 50 studs);
  - distant artillery only out in the desert ring (rare, quiet);
  - his own gate's open / close sound (3D at the gate).
- **Tests:** `tools/sim/run_sound_pass_test.py` (every listed id wired, world sounds 3D <= 60 studs, loops on the SFX
  toggle, owner-first, night / desert logic). Check: `tools/checks/claude_bud_job59.py`.

**Blocked: needs Code Bot / Studio (WE_CHECK2 + the asset pipeline: insert, origin check, part / triangle trim, script
audit):**
- **(A)** Helipad heli on SKYtech rotorKit 9961947424 / rotorLite 12918869816 (local copy 96681147793573), with the
  scripts vendored and audited. JOB 56 already fixed the tilt / detached rotor in our own rig (`[RotorRig]` logs).
- **(C)** Lights 8217816335 / 1725607094 / 404475960; Night Fog sky 1864839162; fireflies 3347717118; dust 615333766;
  fire / smoke 11365590395; VFX textures 17290956157; props (sandbags 5678434293, crates 2930926216, ammo
  2190705941, fences 4715423769 / 9083814252, pickup 6418225759). The JOB 57 BaseLife part props + the JOB 54 night
  lights cover the look until these pass.
  - Note: pickup 6418225759 is already a live vehicle body (PatrolTruck), so Code Bot can add it to
    `HangarDockConfig` / BaseLife as a parked display with no new probe.
- **(D)** Vault Door 14795516338 as the Vault T4 visual. The slot is `DefenceVisuals.Vault` tier 4; swap it in once
  it passes.

**Test ON HIS PHONE:**
1. At night: crickets on your base, the harbor sound by your dock.
2. By your Command Center: radio chatter.
3. At the plaza flag: flapping.
4. Out in the desert: a distant boom now and then.
5. Your gate opening: the gate sound.
6. A heli / boat: the new engine sounds.

## claude-bud JOB 58 (2026-10-01): HANGAR + DOCK WITH REAL AIRCRAFT / BOATS (branch `claude/desktop-bud`)
**Flag:** `HangarDockConfig` (owner-first by the PLOT OWNER, NEW-OWNER-FIRST).

**Before:** the hangar's parked jets were 12-part block mock-ups (Installations/Airfield, 1 jet; 2 at L4) and the
dock's boat was a 29-part Part build. The VAS parked-presence path never runs (`PreferMeshWhenAssetIdSet = false`),
and its PatrolBoat id is 0.

**Built:**
- **`VisualAssetService.CloneDisplayBody(vehicleId, owner, fitLength)`:** the vehicle's approved body as a static
  display. It uses the house template (scripts / seats / sounds / movers stripped), with every part anchored and no
  collide / query / touch. `BodyAllowed` applies exactly as for a driven body. It is fitted to a length and stays
  within the 40-part cap.
- **`Services/HangarDockDisplayService`:** each Part jet slot gets the store body (slot 1 FighterJet, slot 2 ReconPlane;
  both live refs, so every player sees them), facing the doors on the floor. The dock gets the first allowed boat body
  (LandingCraft, an owner-only body today, so only the owner's dock shows it), bow to the sea gate, keel in the water.
- **Fallback:** only when a body is placed do the Part pieces under it hide (Transparency 1, no collide / query,
  re-hidden if a level look re-shows them). No body (not loaded / not allowed / Studio without dressing) = the Part
  build stays exactly.
- **Lifecycle:** rebuilt on plot-ready and on an Airfield / Dock upgrade (after the Part build). Display models are
  in `Workspace.WE_HangarDock.Plot<N>`. Logs `[HangarDock] plot=.. placed=[..]`.
- **Asset rules:** no new asset ids (reuses vehicle bodies already wired and live), no franchise models. Fewer parts
  than before (an 8-mesh jet replaces 12 parts).

**Not done here:** a live boat body for everyone. Every boat ref is id 0 or owner-only, so non-owner docks keep the
Part boat until Code Bot approves a boat body (`BodyRollout` / a WE_CHECK2-passed boat).

**Tests:**
- `tools/sim/run_hangar_dock_test.py`: frames (the nose to the doors, floor / waterline, body Yaw); 2 jets + the boat
  placed and 9 Part pieces hidden; a far piece kept; resync puts them back; no body = nothing hidden; owner-first.
- `tools/checks/claude_bud_job58.py`.
- **Owed:** the Studio look (scale / position of the jet body inside the hangar).

**Test ON HIS PHONE:**
1. Walk into your hangar: real jet(s) instead of block jets.
2. At the dock: a real landing craft at the quay.
3. Upgrade the Airfield to L4: two aircraft.

## claude-bud JOB 57 (2026-10-01): BASE LIFE (branch `claude/desktop-bud`)
**Flag:** `BaseLifeConfig` (owner-first by the PLOT OWNER, NEW-OWNER-FIRST). OFF = today's base.

**Built:** `Services/BaseLifeService` + `Configs/BaseLifeConfig`. Built on plot-ready (claim / rejoin / restart) into
`Workspace.WE_BaseLife.Plot<N>`, and cleared when the owner leaves.
- **Props:** 11 part-built WorldKits rows on clear ground (34 parts a base):
  - a west camp (tent, ammo crates, drums);
  - a depot yard (tent, crates, drums);
  - a sandbag nest + ammo by the Command Center;
  - a container stack in the rear yard;
  - sandbag lines on both side edges.
  - They count against the ONE per-plot allowance `StorePropsConfig.Budget.MaxBasePartsPerPlot` (600, JOB 40 C) and
    never go inside `BaseKeepOut`.
  - The store-model `BaseRows` stay EMPTY: no candidate passed WE_CHECK2. When one does, Code Bot adds it there and
    it shares the same 600.
- **Soldiers:** 3 unarmed ambient soldiers a base (the gate guard's body without the rifle, plus the house R6 look),
  each on its own patrol loop.
  - States: IDLE 4-9 s, then PATROL to the next point (arrive or a 14 s timeout), round the loop. One server loop at
    2 Hz for all of them; no per-frame work.
  - Never hostile: not CombatService NPCs, no WE_NPC tag, CanQuery off (shots pass through), no weapon.
  - Server cap = `CombatConfig.MaxActiveNPCs` (18): with 10 owned plots, only the first 6 bases get soldiers.

**Tests:**
- `tools/sim/run_base_life_test.py`:
  - every prop row clear of roads / structure sites / kiosks / keep-out;
  - 34 parts <= 600;
  - every patrol leg clear;
  - 3 a base, 18 a server with 10 plots;
  - CanQuery off / no rifle / Humanoid;
  - the brain (idle → walk → arrive → idle → next point);
  - owner-first; clear.
- `tools/checks/claude_bud_job57.py`.
- **Owed:** a Studio look. The prop spots and routes come from a conservative grid search of `BaseLayoutConfig`; any
  that clip a real building are tuned in `BaseLifeConfig`.

**Test ON HIS PHONE:**
1. Your base has tents / crates / drums / sandbags, and 3 soldiers walking and stopping.
2. Shoot one: the shots pass through, nothing happens.
3. The frame rate at your base is the same as before.

## claude-bud JOB 56 (2026-10-01): HELIPAD + DOCK SPAWN TERMINALS, ROTOR FIX (branch `claude/desktop-bud`)
**Flags:** `SpawnTerminalConfig` and `VisualAssetConfig.AirRotorDisc` (both owner-first, NEW-OWNER-FIRST).

**Terminals:** new `Services/SpawnTerminalService` + `Configs/SpawnTerminalConfig`.
- **What:** a console beside each BUILT helipad ("Spawn aircraft") and dock ("Launch boat") on the owner's plot.
- **Contract:** the house terminal prompt (`WE_PanelPrompt`, `WE_OpenPanel = Garage`, `WE_OpenTab = Air / Naval`).
  UIController opens `VehicleController.Open(tab)`, so it is the ONE Garage, filtered.
- **Spawning:** the normal `RequestSpawnVehicle` → `VehicleService.RequestSpawn`, with every server gate. At home a
  heli lands on the helipad spots and a boat goes into the dock basin (`chooseHeli` / `chooseBoat`, unchanged).
- **Safety:** the terminal grants, spawns and moves nothing.
- **Lifecycle:** built on plot-ready (claim / rejoin / restart) and on a Helipad / Dock upgrade; cleared when the
  owner leaves.
- **Positions:** config (`Terminals.Helipad.At` 52,-104, `Dock.At` 88,-70, plot-local). A Studio look is owed; tune
  them there.
- **Normal account:** a non-owner still meets every RequestSpawn gate (level / structure / prestige / cooldown /
  combat lock). Only the owner skips them (VS ~4867). The live check with a normal account is owed: a level-
  appropriate alt with Helipad L2+ opens the terminal and spawns the Transport Heli, and gets "Needs Helipad Lx" on a
  locked one.

**Rotor (11240665977, AirBodyRig ~252-276):**
- **Root cause from the code:** `rigRotor` spun every rotor about the CHASSIS Y axis through the Hub part's box centre
  ("Thing for Blades"). A blade disc tilted against the chassis wobbles ("tilted rotor"); a hub box that is not on
  the blades' centre makes them orbit ("detached rotor").
- **Fix:** the joint now uses the blades' own disc (`AirBodyRig._DiscFit`):
  - the normal is the thinnest box axis of the biggest blade part, signed like the configured axis, used only when
    it is clearly flat and within 25 deg;
  - the centre is the blade mesh's own centre.
- **Evidence still owed:** the model isn't in the repo (it loads at runtime), so every rotor now logs
  `[RotorRig] <model> <hub> parts=.. tilt=..deg hubOffset=..studs fixed=..`. The first live spawn shows which cause it
  was (tilt and / or offset).
- **No change to the AttackHelicopter config row** (the codebot_v88 pin stays).

**Not done, and why:** the brief asks to vendor SKYtech rotorKit `9961947424` (local copy `96681147793573`) with its
scripts audited. Downloading and vendoring a Creator Store model's scripts needs the WE_CHECK2 / asset pipeline in
Studio (origin check, script strip / audit), which this session cannot run. That is left to Code Bot / JOB 59 (A). The
fix above is our own rig, needs no third-party code, and does not block it.

**Tests:**
- `tools/sim/run_spawn_terminals_test.py`: wanted from the saved structures; the prompt contract, finger-friendly
  range, no Neon / lights, phone copy; owner-first; clear; rotor disc fit (6 deg tilt, 0.4 studs off, unchanged when
  aligned, kept for chunky / wild cases, a tail rotor).
- `tools/checks/claude_bud_job56.py`.

**Test ON HIS PHONE:**
1. With Helipad built, walk to the console by the pad and tap "Spawn aircraft": the Garage opens on AIR. Spawn a heli:
   it sits on the pad.
2. Same for the dock ("Launch boat" opens NAVAL).
3. Spawn the attack heli and watch the rotor. Then send Code Bot the `[RotorRig]` line from the server log (F9).

## claude-bud JOB 55 (2026-10-01): HONEST DEFENCE TEXT + EXPLOIT FIXES (branch `claude/desktop-bud`)
**Flag:** `EndgameConfig.DefenceFix` (owner-first by the BASE OWNER, NEW-OWNER-FIRST). OFF = the old rules and text.

**Fixed (each from the code):**
- **Turret Plating vs Walls L4:** turrets exist only from Walls L4 (`GateDefenseConfig.AutoGunMinWallsLevel`), so
  Plating bought before that did nothing. The row now says "Needs Walls L4 (turrets)" and the purchase is refused
  with the same text (`NextDefence(profile, track, uid)`, used by both the row and the buy).
- **Vault text:** now shows both cuts: "-30% ATM, -50% army raid loot" (it only showed the ATM cut).
- **Turret Guns:** the post guards had it, but the gate guards (BaseGuards ~:614) and tower guards (~:924) used
  Research only. Both now use `BaseGuards.GuardDamageMult` (= PostDamageMult: research x Guns, cap 3). The text says
  "turret + guard dmg".
- **Wall HP:** "Gate & Walls" promised walls, but walls have no HP anywhere. The track is shown as "Gate Armour":
  "+X% gate + guard HP, -Y s rebuild" (the gate guards' HP really does come from it).
- **The 0.12:** BaseGuards `AfterSpawnPost` now reads `EndgameConfig.Defence.GatePct / 100` (12, so the same number,
  typed once).
- **Mid-raid repair exploit:** a Defence buy ran a full `GateDefenseService.SyncPlot`, rebuilding a breached /
  damaged gate (and dead turrets) at full HP mid-raid. It now calls `GateDefenseService.RefreshDefence(plotId)`:
  - new max HP, with the damage kept (`EndgameConfig.KeepDamage`: 400/1000 -> 520/1120, not 1120);
  - breached stays breached, a dead turret stays dead;
  - the JOB 53 look is re-dressed and the damage stage re-applied;
  - logs `[DefenseUpgrade] plot=.. gate a/b -> c/d breached=.. turrets=[..] (in place, no repair)`.
  - A Base Tier buy still uses the full resync (not in this job's list; it can heal the gate mid-raid too, so flagged
    for Code Bot).

**Tests:**
- `run_endgame_test` [DefFix]:
  - Walls L3 refusal + the row text;
  - 30 in-place refreshes, 0 extra SyncPlots;
  - the honest rows: "Gate Armour | +60% turret + guard dmg | +120% gate + guard HP, -30 s rebuild | -30% ATM, -50%
    army raid loot".
- `run_base_guards_test` §4: guards x2.40 for the owner (fix live), x1.50 for another owner; post HP reads GatePct.
- `run_defence_visuals_test` §5: KeepDamage.
- `tools/checks/claude_bud_job55.py`.
- **Owed:** a live 2-player test (B raids A, A buys Gate & Walls at the Engineering Bureau mid-raid, and A's gate
  keeps its damage).

**Test ON HIS PHONE:**
1. Engineering Bureau with Walls below L4: the Turret Plating row says "Needs Walls L4 (turrets)".
2. Read the Vault row: both cuts.
3. Have an alt damage your gate, buy a Gate level: the bar keeps the damage (it doesn't jump to full).

## claude-bud JOB 54 (2026-10-01): NIGHT LIGHTING ON THE BASES (branch `claude/desktop-bud`)
**Flag:** `LightingConfig.Night2` (owner-first by the PLOT OWNER, NEW-OWNER-FIRST).

**Before:** at night a base had 2 gate floods, 1 hangar flood and runway edge glow. The helipad, dock, sign and the
base from the air were dark, and nothing set the exposure.

**Built (it extends the JOB 17 `NightLights` module, not a second system):** `NightLights.SyncPlot(plotId, owner,
gateCf)`, called from `GateDefenseService.syncPlotNow` (claim / rejoin / restart) and cleared in `clearDefense` (owner
leaves). Each owned plot gets:
- **Lights:** a helipad flood + 4 green pad-corner glows, a dock flood + 4 bollard lamps on the basin edge, a lamp
  bar + SpotLight on the gate sign, and a red beacon mast (glow head + one small light) at the rear corner.
- **Runway thresholds:** green at the start, red at the end (glow only).
- **Budget:** 4 more lights per base (7 in total, cap 40). 10 owned plots + the town = 101 of `MaxLights` 120. The
  shared counter refuses past it.
- **Light rules:** every light goes through `addLight` (Shadows off, off until the night flip, tagged, every second
  one `WE_LowOff`).
- **Low-quality halving kept:** `QualityGovernor` now also catches night lights added after low mode turned on (a late
  claim).
- **No churn:** the same owner + gate is never rebuilt (walls / Defence purchases resync the plot).
- **Exposure:** the client `NightExposureController` (owner-first) eases `Lighting.ExposureCompensation` from 0 by
  day (today's look) to 0.35 at night, through dusk / dawn, every 2 s, writing only on change. The server never
  writes it.

**Tests:**
- `tools/sim/run_night_lights_test.py`: per base 7, total 101 / 120, 50 / 101 halved, owner-first, no churn, clear,
  rebuild, the glow counts, exposure at noon / night / dusk.
- `tools/checks/claude_bud_job54.py`.
- **Owed:** a Studio night look, and exact flood placements against the real helipad / dock kits. The positions are
  config (`LightingConfig.Night2.Helipad / Dock.At`), so tune them there.

**Test ON HIS PHONE at night (wait for dusk, or `/time` if there is an admin clock):**
1. The helipad, dock and gate sign are lit; a red beacon shows from the air; green / red runway ends.
2. With Graphics Quality low, about half the lamps stay off.
3. The night is a touch brighter than before.

## claude-bud JOB 53 (2026-10-01): DEFENCE UPGRADES YOU CAN SEE (branch `claude/desktop-bud`)
**Flag:** `EndgameConfig.DefenceVisuals` (owner-first, NEW-OWNER-FIRST).

**Root cause:** the Defence levels (Engineering Bureau: Turret Plating / Turret Guns / Gate & Walls / Vault Plating,
saved in `profile.Endgame.Defence`) changed numbers only. Nothing on the base read them (BaseTierBuilder looks at the
Base Tier only), so a $68.7M L10 looked the same as L0.

**Built:** `Server/Modules/DefenceVisuals`.
- **Tiers:** visual tier by level is L1-3 = 1, L4-6 = 2, L7-9 = 3, L10 = 4. The numbers stay EXACTLY
  `EndgameConfig.Defence` (no balance change).

| Track | T1 | T2 | T3 | T4 |
|---|---|---|---|---|
| Plating | side plates on every turret nest | front shield | dark steel + hazard band | gold-edged caps |
| Guns | ammo crates | shell rack | heavy ammo box + rounds | belt feed |
| Gate | steel bands (both faces) | corner plates | braces | a gold top beam |
| Vault | brackets round the money collector | side plates | cage | armour cap |

- **Gate leaves:** they also change colour / material by tier (DiamondPlate from T2). A rebuilt gate returns to its
  tier look; with no attribute it is the old look exactly.
- **Gate damage states:** <= 60 % HP: dents + scorch. <= 30 %: the bands sag + one capped smoke emitter. Breached:
  the reinforcement is gone. Repaired / rebuilt: clean again. They hang off the one HP funnel (`updateGateBillboard`),
  and only a stage change touches anything.
- **Applied in `GateDefenseService.syncPlotNow`** from the SAVED levels (`EndgameService.DefenceLevelFor`), so a
  purchase (it already resyncs), rejoin, server restart or rebuild always shows the right tier. Log:
  `[DefenceVisuals] plot=.. owner=.. Plating=.. Guns=.. Gate=.. Vault=.. parts=..`
- **Purchase feedback:** buying into a new tier adds "New on your base: turret front shields" (etc.) to the toast.
- **Budget:** plain Parts only (anchored, no collide / query / touch, so they never block shots, raycasts or walking),
  no Neon, no lights, no labels. A full L10 base with 4 nests adds 104 instances (cap 2,700).

**Not in this job (JOB 55):** a mid-raid Defence purchase still runs the full SyncPlot (the gate goes back to full
HP), and the BaseGuards 0.12 is still there.

**Tests:**
- `tools/sim/run_defence_visuals_test.py`: tiers, every piece at every tier, the L10 budget, OFF, and the damage stages
  0-1-2-0-3-0.
- `run_endgame_test` [DefLook]: the L4 toast.
- `tools/checks/claude_bud_job53.py`.
- **Owed:** the live 2-player check (B sees A's tier on A's base; A's raid on B shows B's damage states) and Studio
  screenshots.

**Test ON HIS PHONE:**
1. Buy one Defence level that crosses a tier (L1 / L4 / L7 / L10): the toast names the new look.
2. Fly home: plates / crates / gate bands / vault plating are there.
3. Rejoin: still there.
4. Have an alt shoot your gate to below 60 % / 30 %: dents, then smoke. Breach it, let it rebuild: clean, with the
   tier look back.

## claude-bud JOB 50 part C (2026-10-01): REBIRTH ZONES: SIGNS, CARD, MAP (branch `claude/desktop-bud`)
**Flag:** `RebirthZonesConfig.Rebuild.Signs` (owner-first with Rebuild). With it OFF, the JOB 46 / 50 A versions are
unchanged.

**What changed:**
- **Gateway plaque:** gets a 4th line: `RUN READY` / `RUN IN PROGRESS` / `NEXT RUN n MIN`.
  - The server refreshes it every `RunRules.StatusRefreshSeconds` (30 s) and sets the text only when it changed.
  - It shows minutes, not m:ss, so there is no per-second replication.
  - Locked zones keep the JOB 46 sign (`<NAME> · <gain>` / `Unlocks at Rebirth N`).
- **Preview card:** gets a 5th line naming the run, its time limit and what a win gives (`RebirthZonesConfig.RunLine`,
  for example "Run: RANGE PRACTICE · 45 s · reload -120 s"). Every line is <= 42 characters (tested), so it fits at
  20 px.
- **Map:** shows HIS built zones as small unlabelled dots (green = ready, gold = cooling down), from `MapService.Live`
  `Zones` → `RebirthZoneService.MapRows`.
  - Tapping a dot shows its name and status and sets the normal pin on its kiosk.
  - Nothing moves him (no fast travel). ArmySend mode ignores them.
- **Ready toast:** one toast when a run comes off cooldown ("RANGE PRACTICE ready: ARTILLERY BATTERY";
  `RunRules.ReadyToast`).

**Test ON HIS PHONE (1024x471 or 956x440):**
1. Walk to a built zone: the plaque by the gate shows the run state.
2. Stand at the upgrade prompt: the card has the gold "Run: ..." line, not cut off.
3. Open the map: your zone dots are there. Tap one: the card and the gold line to it.
4. Wait out a 20 min cooldown: one "ready" toast.

## claude-bud JOB 50 part B (2026-10-01): REBIRTH ZONES: THE RUN PROPS + A FINISHED EDGE (branch `claude/desktop-bud`)
**Flag:** `RebirthZonesConfig.Rebuild.Visuals` (owner-first with Rebuild).

**Built (RebirthZoneDressing.BuildRunProps):** each run's steps now stand on real props.

| Zone | Props |
|---|---|
| Factory | conveyor + crates; a part-built flatbed truck |
| Silo | 3 arming consoles |
| Artillery | 6 target stands |
| Barracks | start / finish gates |
| Refinery | 4 valve stations |
| Bunker | sandbag nests |

Every annex also gets a low berm on three sides, painted apron lines and a part-only lamp post. No Light objects: the JOB 46 / v173 dressing rule; night lights are JOB 54.

**Budget:** 6-30 parts per zone (about 130 per plot in total, well under MaxPlotParts 7200); no Lights; no Neon, no WE_Building* / Store_* names, nothing inside the yard (the store models stay as they are).

**Not done here, and why:** re-roofing or swapping the store models in the yards (the "open-roof office block") needs
probe-verified Creator Store assets and a visual check in Studio.
- **Ask for Code Bot:** pick a closed-roof replacement for `Military Garage` 12365928579 in the WestYard / DroneBay
  ZoneRows, or put WestYard in `ZoneKeepParts` so its Part build stays.

**Test ON HIS PHONE:** each built zone shows its run props (crates and truck, consoles, targets, gates, valves,
sandbags), a berm round the annex and a lamp post at the gate.

## claude-bud JOB 50 part A (2026-10-01): REBIRTH ZONES: A REAL REASON TO GO (THE ZONE RUNS) (branch `claude/desktop-bud`)
**Flag to flip:** `RebirthZonesConfig.Rebuild.OwnerFirst = true -> false` (NEW-OWNER-FIRST). OFF = the JOB 46 one-tap
activities exactly.

**Root cause (docs/proof/job50/before.md):** every zone activity was one tap for 10 min of that zone's flat income
(or just opened a panel), with no skill, goal, best, status or analytics.

**Built (Modules/ZoneRuns.luau, driven by the existing WE_ZoneActivity kiosk; loop-design.md):**
- **The runs:**

  | Zone | Run | Effect on a win |
  |---|---|---|
  | Tank Factory | PRODUCTION RUN (crates -> truck, 60 s) | cash |
  | Silo | LAUNCH PREP (3 consoles, 30 s) | warhead charge -5 min |
  | Artillery | RANGE PRACTICE (6 targets, 45 s) | missile reload -120 s |
  | Drone Hangar | RECON FLIGHT (instant) | nearest raidable rival marked with PIN / SEND + ATM swept |
  | Elite Barracks | DRILL COURSE (45 s) | beat par 30 s = ARMY BOOST 10 min |
  | Refinery | PRESSURE VALVES (shuffled order, 30 s) | cash |
  | Bunker | HOLD THE LINE (3 CombatService NPCs, him only, 60 s) | cash + banner stage |

- **Validation:** every step is server-checked (owner, in order, inside the annex, before the limit).
- **Pay:** `RunBase = max(ShipmentCash, 2 min of his income)` x 1.0-1.5 by speed; the first clear pays once more.
- **Cooldown:** 20 min per zone (saved), started by any end.
- **Status:**
  - A personal best on a new gateway plaque ("UNLOCKED BY <name> · REBIRTH N / <RUN> BEST").
  - ZONE COMMANDER when all 7 zones are at L3.
- **Analytics:** `ZoneActivity` (zone, result, seconds, payout).
- **Saves:** new profile fields ZoneRunAt / ZoneBest / ZoneFirstClear / BunkerBanner / ZoneCommander, sanitised in
  ProfileSchema.
- Free for everyone; no Robux; no teleport.

**Number for Shaun:** `RunRules.IncomeMinutes = 2`. At his rebirth-10 income a run is about $17M (fastest about $25M).
All 7 zones every 20 min adds at most about 21 min of income per 20 min of active play.

**Checks:** run_rebirth_stations_test (+ section 5: every run) 0 failed; claude_bud_job50 A pins.

**Owed:** Studio shots of the step markers next to the JOB 46 props. Parts B (visual detail) and C (signs / pins)
follow.

**Test ON HIS PHONE:** at each zone's kiosk start the run, follow the gold step markers / prompts, and finish inside the
time. The pay toast shows the time + NEW BEST, and the plaque shows the best.

## claude-bud JOB 50 part D (2026-10-01): HOTBAR WEAPON LABELS OVERLAP (branch `claude/desktop-bud`)
**Root cause (from the source + HudConfig; docs/proof/job50/hotbar-caption.txt):**
- Each slot's `WeaponName` box was slot + Gap + 4 = **80 v in a 64 v slot**: 8 v into each 12 v gap, so neighbouring
  boxes overlapped by 4 v.
- `TextScaled` stretched an 8-letter name ("LONGSHOT") across the whole box.
- Duplicate captions:
  - LongshotDMR (rebirth gun) / LongshotSniper (pass gun) were both "LONGSHOT";
  - HavocLauncher / HavocRotary were both "HAVOC";
  - SovereignRifle / SovereignPistol were both "SOVEREIGN".
- The captions in the screenshot sit in our numbered slots, so this is our hotbar, not the CoreGui Backpack.

**Fix:**
- The caption box stays inside its slot (slot - 4, 16 v clear of the neighbour's).
- `fitCaption` picks the biggest TextSize that fits (NameSize down to CaptionMinTextPx 12 real px), then "…".
- Distinct ShortNames for the rebirth guns: "DMR", "HAVOC RL", "SOV RIFLE". The pass guns keep theirs; no Id / pass /
  price change.

**Test ON HIS PHONE:** with 4 weapons the captions sit inside their own slots and never touch; DMR vs LONGSHOT read
distinct.

## claude-bud JOB 52 (2026-10-01): ARMY ATTACK AT RANGE ("No enemies near" with enemies in sight) (branch `claude/desktop-bud`)
**Flag to flip:** `ArmyOrdersConfig.AttackRange.OwnerFirst = true -> false` (NEW-OWNER-FIRST). Enabled = false is the
old 250 / 300 / 150 exactly.

**Root cause (reproduced; docs/proof/job52/):**
- The ATTACK probe was `SeekRadius` 250 from him, while awake enemies stand 260-380 studs out (the wake / sleep bands).
  Flag OFF, an enemy at 260 / 380 gives `REJECTED NoEnemiesNear radius=250`, the reported bug.
- `SeekLeash` 300 and the running plan's re-seek / fight leash (300 from him) would have dropped a farther target even
  with a bigger probe.
- **Ruled out:** static figures; grouped-NPC refusal (`probing` is set).

**Fix:**
- One set of radii for the whole order (seek 400 / leash 450 / chain 200), flat distances, the existing march (no
  teleport).
- Nothing within range: "No enemies within X m. Nearest: Y m NE" plus a PIN / SEND ARMY card (`"N:<npcId>"`,
  resolved on the server).
- ARMY KILLS counts HIS ordered ATTACK target group, at most 60 per owner per rolling hour (no AFK farm).

**Files:**
- Configs: ArmyOrdersConfig.
- Server: ArmyPlan, ArmyCommand, ArmyTargets, CombatService (NPCInfoOf), SquadOrdersService (flat pick),
  EngagementService (credit).
- Client: Controllers/ArmyNearestController (+ Bootstrap).
- Tests: tools/sim/run_army_command_test.py (OFF / ON / 450 / height scenarios), tools/checks/claude_bud_job52.py.

**Checks:** run_army_command_test 0 failed; BuyPathStatic FAIL=0. **The Studio 2-player test is owed.**

**Test ON HIS PHONE:**
1. Army out, enemies visible ~300 m away: ATTACK. The army marches in formation and fights; ARMY KILLS go up.
2. Nothing within range: the card shows the distance + direction. PIN marks it; SEND ARMY takes the army there.
3. A shielded / new player nearby is never attacked (JOB 51 rule).

## claude-bud JOB 51 (2026-10-01, P0): CENTRAL PLAZA GUARDS: ONE SHARED HOSTILITY RULE (branch `claude/desktop-bud`)
**Flag to flip:** `CombatConfig.SharedHostility.OwnerFirst = true -> false` (NEW-OWNER-FIRST). Enabled = false is the
old brain exactly.

**Root cause (docs/proof/job51/rootcause.md, plaza-guards-sim.txt):**
- **Reproduced in the real CombatNPC brain:** every NPC picked the nearest player with no protection rule, then fired
  guaranteed misses at a spawn- or novice-shielded target for ever.
  - The plaza circle is also the emergency / plot-less spawn, so a shielded new player often stands at the centre.
  - Measured: 60 s, **Laumartinez26 hits 0, 340 misses at the shielded player**.
  - Counter-case: nearer to any guard, she was shot in the old brain too, so this explains "never shot" only in that
    geometry.
- **"She can't damage them":** no code-level blocker found. hurtNPC has no gate, every WE_NPC has an NPCId, NPCs have
  no ForceField. The live `[NpcHit]` / claim-refusal lines are needed.
- **The live 2-player proof is OWED:** `/guarddebug on` prints `[GuardTarget]` / `[GuardShot]` / `[NpcHit]`.

**Fix:**
- `Server/Modules/Hostility` (ProtectedReason / NpcMayTarget / MayHurt), bound by CombatService with the existing
  reasons (no copy). Every NPC target pick uses it, and `CheckpointGuardService.Protected` calls it.
- The same rule answers for guns / vehicle / unit / turret / base guard / NPC (cases table in the sim).

**Safe zone:** NO. The code treats the plaza as a capturable outpost with hostile defenders; the only protection is
the normal 3 s spawn shield.

**Spawn finding (not changed):** a fresh spawn at the centre dies in ~5.9 s (~2.9 s after the shield) with 4 guards
awake. **Question for Shaun / Code Bot:** move the emergency / plot-less spawn out of the defenders' aggro
(> 125 studs from the centre) after a Studio check of clear ground?

**Files:** Modules/Hostility.luau (new), CombatService/init.luau, CombatService/CombatNPC.luau,
CheckpointGuardService.luau, AdminService.luau (/guarddebug), CombatConfig.luau, tools/sim/run_plaza_guards_test.py,
tools/checks/claude_bud_job51.py, docs/proof/job51/.

**Test ON HIS PHONE (with Laumartinez26 in the same server; owner types /guarddebug on):**
1. Both in the plaza circle: the guards shoot both of you, and nobody shielded soaks the shots.
2. Both can damage and kill a guard.
3. Respawn at the plaza: the shield ends normally. Note how fast the guards kill you.
## v182 PUBLISHED (Code Bot Roblox, 2026-10-01 ~18:40 Dublin): Open Cloud place version 180. Core daily missions + return sequence live for everyone (Shaun approved)
- **Commits:** code+dist+checks `00e9a6b` + check scope `432c34c` on phase-7-polish (from `9529c70`); bud merge `ff7c0c8` into `claude/desktop-bud`.
- **Flips:** `MissionConfig.Core.OwnerFirst` true → false; `RetentionConfig.ReturnSequence.OwnerFirst` true → false. The Mission Reroll dev product (3715836569, 19 R$) already had `Core.Reroll.Robux.OwnerFirst = false` (v180), so the paid reroll opens with Core. Nothing else changed: MonetizationConfig byte-identical to v181 `9529c70`, no Id / price line, no other OwnerFirst. PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched.
- **Checks:** BuyPathStatic **PASS=8076 FAIL=0**; new `tools/checks/codebot_v182.py` (both flags false, reroll wired 3715836569 / 19 R$, all 54 SKUs unchanged vs `9529c70`, only MissionConfig + RetentionConfig changed in Configs). `claude_bud_job49.py` now pins the live state; `codebot_v179.py` / `codebot_v180.py` check the owner-first flags against their own ship commits (`75bd8b4` / `719f957`). `run_daily_return_test.py`: a non-owner gets the 3 core missions + free / 19 R$ reroll and a ReturnDay; the owner-first rule is still proved with OwnerFirst = true (restored). WE_Build 182 in every pin.
- **Publish:** HTTP 200, versionNumber **180**, universe 10767159222 / place 97112936860418. Servers NOT restarted (~25+ players): Migrate to Latest Update when convenient.
- **Phone tests (Shaun, any account that is not the owner is best):** rejoin (new server, WE_Build 182) → MISSIONS shows 3 core missions on top + 1 free reroll, then the 19 R$ reroll; a returning join shows Welcome back → streak → "3 new missions today" one at a time.
- **Still owed:** JOB 44 Studio 2-player siege/march; JOB 51 (Claude pushed `b8c2af5` on bud, not shipped) / 50 / 52; JOB 59/60 docs-only on bud.

## v181 PUBLISHED (Code Bot Roblox, 2026-10-01 ~18:25 Dublin): Open Cloud place version 179. claude-bud JOB B TARGETS rival list blacked out (ZIndex Sibling)
- **Cherry-pick:** `c628c8b` (JOB B) → `0b198b5` onto phase-7 `67b00aa` (v180 tip). Code+dist+checks on this ship. PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; MonetizationConfig unchanged (no price / Id change).
- **JOB B (P0):** TARGETS rival list looked almost black / unclickable. Root cause: `WE_RivalTargets` ScreenGui used default Global ZIndex ordering, so the list panel (ZIndex 3, 97% opaque) painted over its own ZIndex-1 rows / SEND ARMY / VIEW. Fix: `g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling` (one line). No colours / sizes changed.
- **Checks:** BuyPathStatic **PASS=8016 FAIL=0**; `tools/checks/codebot_v181.py`; `claude_bud_jobB.py`; `run_targets_list_test.py` 0 failed. PreferMesh OFF; StreamingEnabled OFF.
- **Publish:** HTTP 200, versionNumber **179**, universe 10767159222 / place 97112936860418. Servers NOT restarted: Migrate to Latest Update when convenient.
- **Phone tests (owed — Shaun, needs a 2nd player online):** open TARGETS — rival name, Lv / Army, EVEN, SEND ARMY and VIEW are bright; both buttons respond to a tap.
- **Still owed:** flip MissionConfig.Core.OwnerFirst + RetentionConfig.ReturnSequence.OwnerFirst after phone OK; JOB 44 Studio 2-player siege/march; JOB 51 / 50 / 52 queued.

## claude-bud JOB B (2026-10-01, P0): TARGETS RIVAL LIST BLACKED OUT (branch `claude/desktop-bud`)
**Root cause (from the source; docs/proof/targets-list/sim.txt):**
- RivalController's ScreenGui `WE_RivalTargets` never set `ZIndexBehavior`, so it rendered with **Global** ordering.
  Every other HUD gui here sets Sibling (HudLayout.ApplyScreen too).
- The list Frame is ZIndex 3 with a 97 %-opaque near-black background, and every row / label / EVEN chip / SEND ARMY
  / VIEW inside it is the default ZIndex 1.
- Under Global the panel's background was painted OVER its own rows, so they showed at ~3 %, and the top object
  under a finger was the panel.

**Fix:** `g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling`, one line at the cause. The children draw above the panel,
and the open list still covers the card (3 > 1). No colours / sizes changed.

**Checks:** run_targets_list_test 0 failed (model + static + Code Bot's rival_controller_harness);
claude_bud_jobB; BuyPathStatic FAIL=0. **The 2-player check is owed** (needs a second player online).

**Test ON HIS PHONE (with a 2nd player):** open TARGETS. The rival's name, Lv / Army, EVEN, SEND ARMY and VIEW are
bright, and both buttons respond to a tap.

## v180 PUBLISHED (Code Bot Roblox, 2026-10-01 18:10 Dublin): Open Cloud place version 178. Two monetization items wired (Shaun approved + created): 2x Offline Cash game pass + Mission Reroll dev product
- **Commits:** code+dist+checks `719f957` on `codebot/v180-monetization` (FF into phase-7-polish from `5e9649b`); bud merge `d6347d9` into `claude/desktop-bud`. PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; no other price / Id changed (codebot_v180 compares all 56 SKUs vs `5e9649b`).
- **2x Offline Cash (Game Pass 2002664894, 149 R$):** the code expected `OfflineCap2x` as a **Developer Product** (DevProducts stub, `GrantEntitlement`). Moved to `MonetizationConfig.GamePasses.OfflineCap2x` (stub removed), so the generic pass path owns it: UserOwnsGamePassAsync on join + PromptGamePassPurchaseFinished → UserOwnsGamePassAsync confirm, `WE_Ent_OfflineCap2x` display flag. `EconomyConfig.OfflineEarnings.CapBoost` Enabled=true, OwnerFirst=false (everyone): cap time 8 h → 16 h, Share unchanged. RetentionService reads the server pass cache (new `MonetizationService.OwnsCached` / `OwnsGamePassNow`; the join payout asks Roblox once if the join check is still running). Sold in the Shop SUPPLY pass rows ("Pass: 2x Offline Cash", OWNED once bought); Welcome back card shows "(capped at 16 h)" for owners.
- **Mission Reroll (Dev Product 3715836569, 19 R$):** `DevProducts.MissionReroll` Id + RobuxPrice 19 (HideFromShop, `SoldFrom = "Missions"`); `MissionConfig.Core.Reroll.Robux` Enabled=true, OwnerFirst=false. ProcessReceipt grants ONE `MissionRerollTokens` per receipt (hasProcessed/markProcessed idempotent, saved before PurchaseGranted, failed grant = NotProcessedYet). New purchase surface: on an open core mission row, once the free daily reroll is used and no token is left, a green "↻ R$19" button (server-decided `CanBuyReroll`) prompts the product; after the receipt the token arrives and the client fires the server-checked reroll once.
- **Reachability:** the paid reroll is **NOT reachable by non-owners** yet: `MissionConfig.Core.OwnerFirst = true` (left as is) hides the core missions (and so every reroll button) from everyone but the owner. It goes live for all with the Core flip. ReturnSequence.OwnerFirst also left true.
- **Checks:** BuyPathStatic **PASS=8046 FAIL=0**; new `tools/checks/codebot_v180.py` (36 checks); updated `claude_bud_job49.py`, `run_daily_return_test.py` (pass owner / non-owner 16 h, reroll buy button, tokens), `launch_audit.py` (Missions panel / reroll token), codebot_v156/v167 diffs + v176–v179 snapshot checks pinned to their own ship commits; docs/LIVE_PLACE.md rows.
- **Publish:** HTTP 200, versionNumber **178**, universe 10767159222 / place 97112936860418. Servers NOT restarted: receipts for 3715836569 reaching an old server are not acked (Roblox retries) until Migrate to Latest Update.
- **Phone tests (owed — Shaun):** (1) Shop SUPPLY: "Pass: 2x Offline Cash" 149 R$ → buy → OWNED. (2) Leave >8 h, rejoin: Welcome back says capped at 16 h and pays 16 h. (3) Missions: use the free reroll, then the "↻ R$19" button → buy → that mission rerolls once; a second buy = one more reroll.
- **Still owed:** flip MissionConfig.Core.OwnerFirst + RetentionConfig.ReturnSequence.OwnerFirst after phone OK; JOB 44 Studio 2-player siege/march; JOB 51 / 50 / 52 queued. Note: claude-bud JOB B (`c628c8b`, TARGETS ZIndex) cherry-picked in v181.
## v179 PUBLISHED (Code Bot Roblox, 2026-10-01 17:45 Dublin): Open Cloud place version 177. claude-bud JOB 49 D return sequence + JOB A recruitment office P0 (owner-first)
- **Cherry-pick:** `d5737ca` (JOB 49 D) → `27c8083`; `8681c07` (JOB A) → `2499ae8` onto phase-7 `c8db098` (v178 tip). Code+dist+checks: `75bd8b4` on `codebot/v179-job49d-jobA` (FF into phase-7-polish). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; no price / Id change.
- **JOB 49 D (NEW-OWNER-FIRST):** `RetentionConfig.ReturnSequence.OwnerFirst = true` — one client card queue: Welcome back → streak → "3 new missions" toast + Missions pulse; Comeback cash folded into Welcome back; ReturnDay analytics on join; AnalyticsConfig rows for every JOB 49 event. Never during onboarding hold / combat.
- **JOB A (P0):** Recruitment Office closed ~0.5s after DRILL kiosk open — walk-away measured to plaza not kiosk. Fix: OpenRecruitmentOffice/CloseRecruitmentOffice with open-from anchor + hysteresis (close past RecruitCloseRange 17); server AtStation accepts own kiosk; plaza path unchanged.
- **Still owner-first (flip after phone OK):** MissionConfig.Core (JOB 49 C) + RetentionConfig.ReturnSequence (JOB 49 D).
- **Untouched:** CapBoost Enabled=false; OfflineCap2x / MissionReroll Id 0; Grace/Day7Scale/Calendar/Card stay OwnerFirst=false (v177); all prices / product Ids.
- **Checks:** BuyPathStatic **PASS=7969 FAIL=0**; new `tools/checks/codebot_v179.py`; `claude_bud_job49.py` part D; `claude_bud_jobA.py`; `run_daily_return_test.py` 0 failed (A–D); `run_recruitment_office_test.py` 0 failed. PreferMesh OFF; StreamingEnabled OFF.
- **Publish:** HTTP 200, versionNumber **177**, universe 10767159222 / place 97112936860418. Servers NOT restarted: Migrate to Latest Update when convenient.
- **Phone tests (owed — Shaun):**
  - **JOB A:** (1) Press DRILL at Elite Barracks once: stays open until X; repeat 10 times. (2) Walk a few steps: stays open; walk ~18+ studs: closes. (3) Buy an upgrade from it: works. (4) Plaza Recruitment Office still opens/closes as before.
  - **JOB 49 D:** (1) Day 1: streak card + calendar with Next in... (2) Next day: Welcome back (Collect $X) first, then Day 2, then "3 new missions" toast — one at a time. (3) Skip one day: streak kept showing SAVED. (4) 3 missions reset at time shown on Missions panel.
- **Questions for Shaun (from Claude):** (1) Offline ATM raidable before collect? (2) Hide Daily Ops below 3 core? (3) Prices for OfflineCap2x / MissionReroll?
- **Still owed:** JOB 44 Studio 2-player siege/march. JOB 51 P0 plaza guards queued front after current. JOB 50 / JOB 52 queued.
## v178 PUBLISHED (Code Bot Roblox, 2026-10-01 17:15 Dublin): Open Cloud place version 176. claude-bud JOB 49 C core daily missions + free reroll (owner-first NEW-OWNER-FIRST)
- **Cherry-pick:** `4fdf273` → `cada04c` onto phase-7 `de2bc56` (v177 tip). Code+dist+checks: `c978f41` on `codebot/v178-job49c` (FF into phase-7-polish). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; no price / Id change. MissionReroll stays Id 0 + Robux Enabled=false; CapBoost / OfflineCap2x untouched.
- **JOB 49 C (NEW-OWNER-FIRST):** `MissionConfig.Core.OwnerFirst = true` — 3 core daily missions (Raid / Recruit / Build / WinFights, 3 different types, saved per day, level-tier targets, Raid only when a raid is possible), Raid ObjectiveType from the two raid-win hooks, income-scaled rewards + all-3 chest once, ResetHourUtc + real countdown, client GO (TARGETS / Army / next console), 1 free reroll/day (RequestMissionReroll) + DISABLED Robux reroll grant.
- **Untouched:** CapBoost Enabled=false; OfflineCap2x / MissionReroll Id 0; Grace/Day7Scale/Calendar/Card stay OwnerFirst=false (v177); TutorialConfig.Guided.Hook.OwnerFirst=false; all prices / product Ids.
- **Checks:** BuyPathStatic **PASS=7982 FAIL=0**; new `tools/checks/codebot_v178.py`; `claude_bud_job49.py` part C pins; `run_daily_return_test.py` 0 failed (part C). PreferMesh OFF; StreamingEnabled OFF.
- **Publish:** HTTP 200, versionNumber **176**, universe 10767159222 / place 97112936860418. Servers NOT restarted: Migrate to Latest Update when convenient.
- **Phone tests (owed — Shaun):** (1) Missions shows "TODAY'S 3 MISSIONS · new in Xh Ym" with 3 different types; each GO goes to the right place. (2) Reroll once; second reroll refused. (3) Finish all 3; chest pays once. (4) After shown reset time, 3 new missions. Also: CapBoost/OfflineCap2x/MissionReroll Id 0 still off. After phone OK: flip MissionConfig.Core.OwnerFirst true→false. **Question for Shaun:** should Daily Ops below the 3 core missions be hidden?
- **Still owed:** JOB 44 Studio 2-player siege/march still owed.

## claude-bud JOB A (2026-10-01, P0): RECRUITMENT OFFICE CLOSED ITSELF ~0.5 s AFTER OPENING (branch `claude/desktop-bud`)
**Root cause (proved; docs/proof/recruitment-office/REPORT.md + sim.txt):**
- The DRILL kiosk on his Elite Barracks zone (JOB 46) opens the Recruitment Office panel.
- `EndgameController.setListOpen`'s 0.5 s loop measured his distance to the **plaza** office (`stationPoint`), not
  the kiosk he pressed.
- From any plot that is >= 531 studs against CloseRange 22, so the first tick closed it every time.
- The server's `AtStation("Recruits")` was plaza-only too, so kiosk buys were refused.

**Fix:**
- One `OpenRecruitmentOffice(source, point)` / `CloseRecruitmentOffice(reason)` pair with the `[RECRUITMENT OPEN]` /
  `[RECRUITMENT CLOSE] Reason:` warns.
- The walk-away close is measured from the point it was opened from, with hysteresis: open at 10-12 studs, close past
  17 (`EndgameConfig.Station.RecruitCloseRange`).
- It closes only on X / WalkAway / Death / OtherMenu; the prompt hiding never closes it; a scratch no longer closes it.
- The server accepts his own kiosk (`RebirthZoneService.KioskPoint`) for buys.
- No delay / debounce / teleport; the plaza path behaves as before.

**Checks:** run_recruitment_office_test 0 failed; claude_bud_jobA pin; BuyPathStatic FAIL=0.

**Test ON HIS PHONE:**
1. Press DRILL at your Elite Barracks once: it stays open until X. Repeat 10 times.
2. Walk a few steps: it stays open. Walk away (~18+ studs): it closes.
3. Buy an upgrade from it: it works.
4. The plaza Recruitment Office still opens and closes as before.

## claude-bud JOB 49 part D (2026-10-01): ONE RETURN SEQUENCE + ANALYTICS (JOB 49 COMPLETE) (branch `claude/desktop-bud`)
**Flags to flip:**
- `RetentionConfig.ReturnSequence.OwnerFirst = true -> false` (NEW-OWNER-FIRST).
- Also still owner-first: `MissionConfig.Core` (part C). A + B were flipped live by Code Bot in v177.

**Root cause:**
- The Welcome back card (6 s + hold) and the streak card (8 s + hold) ran on their own timers and could stack.
- The Comeback cash was a third toast.
- Nothing pointed at the new missions.
- Details: docs/proof/job49/before.md.

**Built:**
- **One queue on the client (RetentionController):** cards show one at a time in priority order: Welcome back -> the
  streak card -> "3 new missions today: open MISSIONS" (one toast + the Missions button pulses, once per session when
  3 fresh core missions are up).
  - Each card waits while the onboarding hold is on (the Guided chain) and while he is in combat / driving / in a
    panel.
- **Comeback cash:** EngagementConfig Comeback (still paid by EngagementService, once per absence) folds into the
  Welcome back card ("+ Comeback $25,000") instead of its own toast. With no offline pay, the card shows the comeback
  alone.
- **ReturnDay {days since the first join, guidedDone}:** logged once per session on join, so D1 ties to the JOB 48
  chain.
- **AnalyticsConfig rows:** StreakClaimed, StreakReset, OfflineCollected, MissionDone, MissionsAllDone, MissionReroll,
  ReturnDay.

**JOB 49 maths at 3 income levels** (Day 7 = max($20k, 60 min); missions = max(floor, 10 min); chest = max($10k,
20 min); offline cap 8 h x 0.25):

| Income | Day 7 | Each mission | Chest | Full offline |
|---|---|---|---|---|
| $60/min | $20,000 | $2-4k (floor) | $10,000 | $7,200 |
| $1,000/min | $60,000 | $10,000 | $20,000 | $120,000 |
| $20,000/min | $1.2M | $200,000 | $400,000 | $2.4M |

**Questions for Shaun:**
1. Offline cash in the ATM can be raided before he collects it. Keep it raidable?
2. Hide the Daily Ops below the 3 core missions?
3. Prices for OfflineCap2x / MissionReroll. Both are Id 0 with no price, so they are never sold until you approve.

**Checks:**
- run_daily_return_test A-D, all 0 failed (docs/proof/job49/daily-return-sim.txt); claude_bud_job49 pins.
- BuyPathStatic FAIL=0; rojo ok; no new LSP errors; remote_audit OK.

**Owed:** the Studio "come back" screenshots, the HUD harness (`check_hud.py` is not in this repo), the live D1 / D7
numbers.

**Test ON HIS PHONE:**
1. Day 1: the streak card + calendar with "Next in ...".
2. The next day: Welcome back (Collect $X) first, then Day 2, then the "3 new missions" toast. One at a time.
3. Skip one day: the streak is kept and shows SAVED.
4. The 3 missions reset at the time the Missions panel shows.

## claude-bud JOB 49 part C (2026-10-01): 3 CORE DAILY MISSIONS + RAID + REROLL (branch `claude/desktop-bud`)
**Flags to flip:**
- `MissionConfig.Core.OwnerFirst = true -> false` (NEW-OWNER-FIRST).
- `Core.Reroll.Robux` stays **Enabled = false** (DevProducts.MissionReroll Id 0, no price) until Shaun approves one.

**Root cause:** the old daily list is 3 Daily Ops + 3 rotating missions of any type, and two problems follow:
- nothing ties them to the core loop;
- a raid win never reached TrackProgress (there was no "Raid" type).
The rewards were flat ($1,500-$5,000), which is worthless after the first hour.

**Built (extends MissionConfig / MissionService; the Daily Ops stay as they are, below):**
- **The 3 core missions:**
  - **Picks:** 3 missions of 3 different loop types (Raid / Recruit / Build / WinFights), picked once per day per
    player (seeded like today, saved in DailyMissions.Core: never reshuffles).
  - **Raid:** offered only when RivalService has an allowed base for him; otherwise another type replaces it.
  - **Targets by level tier** (<= 10 / <= 40 / above): Raid 1/1/2, Recruit 3/5/10, Build 1/2/3, Win fights 5/10/20.
    All 3 fit one session.
  - **"Raid" ObjectiveType:** reported from the SAME two raid-win hooks (the ArmyPlan SEND loot, the
    MoneyCollectorService ATM raid).
- **Rewards:**
  - Each mission pays max(its floor, 10 min of his income).
  - All 3 claimed: a chest once a day, max($10,000, 20 min of income) + 3 Gold.
  - The claim stays server-side and idempotent.
- **Reset:** at `Core.ResetHourUtc` (0 = today). The Missions panel header shows the REAL time to the reset from the
  server's clock.
- **GO:** Raid opens the TARGETS list; Recruit opens the Army panel; Build draws the gold line to his cheapest next
  console (the server picks it); WinFights uses the existing Hostiles marker.
- **Reroll:**
  - 1 free a day (saved), with a "↻" button (48 px) on each open core row. The new remote RequestMissionReroll takes
    the mission id only (SecurityConfig schema).
  - A reroll never pays, and the new mission is another type at the same tier.
  - The Robux reroll grant exists in ProcessReceipt (GrantsMissionReroll -> a token) but is never sold while Id 0.
- **Analytics:** MissionDone {type}, MissionsAllDone, MissionReroll {free/robux}.

**Question for Shaun:** should the Daily Ops below the 3 core missions be hidden? They are kept for now.

**Checks:**
- run_daily_return_test part C (24 checks) 0 failed.
- remote_audit OK; BuyPathStatic FAIL=0.

**Test ON HIS PHONE:**
1. Missions shows "TODAY'S 3 MISSIONS · new in Xh Ym" with 3 different types. Each GO goes to the right place.
2. Reroll once: the second reroll is refused.
3. Finish all 3: the chest pays once.
4. After the shown time, 3 new missions.
## v177 PUBLISHED (Code Bot Roblox, 2026-10-01 17:03 Dublin): Open Cloud place version 175. claude-bud JOB 49 A+B flipped to EVERYONE (Shaun approved)
- **Commit:** `2ed90ae` (code + dist + checks) pushed to phase-7-polish (FF from `008c529`). Bud merge `205f2d6` into claude/desktop-bud. PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; no price / Id change.
- **Flip:** `DailyRewardConfig.Grace` / `.Day7Scale` / `.Calendar` + `EconomyConfig.OfflineEarnings.Card` OwnerFirst true→false (live for all players).
- **Untouched:** `OfflineEarnings.CapBoost` Enabled=false; `MonetizationConfig.DevProducts.OfflineCap2x` / `MissionReroll` Id 0 + no price; all prices / product Ids; `TutorialConfig.Guided.Hook.OwnerFirst = false`.
- **Checks:** BuyPathStatic **PASS=7954 FAIL=0**; new `tools/checks/codebot_v177.py`; `claude_bud_job49.py` + `codebot_v176.py` now assert OwnerFirst=false; `run_daily_return_test.py` 0 failed (now proves grace live for a non-owner, owner-first rule still proved with OwnerFirst=true); `run_offline_test.py` 0 failed.
- **Publish:** HTTP 200, versionNumber **175**, universe 10767159222 / place 97112936860418. Servers NOT restarted (~25 players live): Migrate to Latest Update when convenient.
- **Still owed:** JOB 49 part C (missions / MissionReroll) not started on Claude; JOB 44 Studio 2-player siege/march still owed.
## v176 PUBLISHED (Code Bot Roblox, 2026-10-01 16:54 Dublin): Open Cloud place version 174. claude-bud JOB 49 A+B daily streak grace + welcome-back collect card (owner-first)
- **Cherry-pick:** `d4672cd` → `32720f8` (JOB 49 A) + `febd2a8` → `2d695b1` (JOB 49 B) onto phase-7 `f1e5707`. Code+dist+checks: `574b455` on `codebot/v176-job49` (FF into phase-7-polish). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; no price / Id change. OfflineCap2x / MissionReroll stay Id 0 + CapBoost Enabled=false.
- **JOB 49 A (NEW-OWNER-FIRST):** `DailyRewardConfig.Grace` / `.Day7Scale` / `.Calendar` OwnerFirst=true — 1 missed day per 7-day cycle (SAVED), Day 7 = max(table, 60 min income), real UTC countdown on card + Missions panel, first card after Guided reward or 150 s.
- **JOB 49 B (NEW-OWNER-FIRST):** `EconomyConfig.OfflineEarnings.Card` OwnerFirst=true — Welcome back! Collect $X (real amount, time away, 8 h cap); COLLECT gold line to ATM. CapBoost disabled.
- **Hook:** stays `TutorialConfig.Guided.Hook.OwnerFirst = false` (v175 Shaun-approved).
- **Checks:** BuyPathStatic **PASS=7936 FAIL=0**; `tools/checks/claude_bud_job49.py` + `codebot_v176.py`; `run_daily_return_test.py` 0 failed.
- **Publish:** HTTP 200, versionNumber **174**, universe 10767159222 / place 97112936860418. Servers not restarted (Migrate to Latest Update as needed).
- **Phone tests (owed — Shaun):** (1) Daily streak Day 1 card + calendar countdown; miss one day → SAVED; Day 7 scales with income. (2) Offline leave 1h+, rejoin → WELCOME BACK Collect $X with time away; COLLECT draws gold line to ATM. (3) CapBoost / OfflineCap2x still off / Id 0. After phone OK: flip Grace/Day7Scale/Calendar/Card OwnerFirst true→false.
- **Still owed:** JOB 49 part C (missions / MissionReroll) not started on Claude; JOB 44 Studio 2-player siege/march still owed.
## v175 PUBLISHED (Code Bot Roblox, 2026-10-01 16:30 Dublin): Open Cloud place version 173. TOP SUPPORTERS hardening + purchase stand signs + Hook for everyone
- **Commit:** `c5df335` (code + dist + checks) on `codebot/v174-supporters-pads` (rebased on phase-7-polish `d4f776d`; NOT pushed to phase-7-polish: that push needs Shaun's OK). Bud merge `65cae04` (with JOB 49 A; BuyPathStatic on the merged tree PASS=7901 FAIL=0). PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; no price / Id change.
- **TOP SUPPORTERS (Laumartinez26, UserId 11718087109, Speed Boost 99 R$ at 15:55):** the ProcessReceipt -> RobuxSpent -> WE_LB2_Supporters -> board path is proven end to end in `tools/sim/run_codebot_v175_test.py` (REAL MonetizationService + EngagementService, budget-enforcing DataStore stand-in). Live cause NOT proven (Open Cloud key has no DataStore read scope). Likely: an older server build (90 s throttled writer) + she left, read latency, or an unacked receipt (Roblox re-delivers it on her next join). Hardening: budgetOk asks OrderedList / OrderedWrite first (legacy types documented as returning 0), round-robin reads (ReadSeconds 90), join backfill from saved RobuxSpent, THIS WEEK tab (Supporters_W = RobuxSpent - LB.SupWBase), pass credit once (all-time only), `[SUPPORTERS]` server log lines, friends payout under pcall. Watch the server log for `[SUPPORTERS] write` when she rejoins.
- **Stand signs:** the camera-facing BillboardGuis (overlapping 12 studs apart) are replaced by ONE physical dark panel per stand (SurfaceGui `WE_PremiumBillboard`, 6.4 x 3.4 studs, gold edge, icon disc, NAME, one benefit line, gold R$ price chip; edge turns green when owned) on two gold posts, facing the plot inside. The SUPPLY DEPOT board now faces inside too, raised to 11 studs over the stand signs. Armory sign untouched.
- **Hook:** `TutorialConfig.Guided.Hook.OwnerFirst = false` (Shaun approved): JOB 48's first 2 minutes for every new player. Checks updated (claude_bud_job48, codebot_v174, run_first_minutes_test).
- **Checks:** BuyPathStatic **PASS=7894 FAIL=0**; `tools/checks/codebot_v175.py`; CODEBOT V175 TEST 0 failed; FIRST MINUTES TEST 0 failed.
- **Publish:** HTTP 200, versionNumber **173**. Servers NOT restarted: Migrate to Latest Update needed.
- **Phone tests (Shaun):** depot stand signs readable / not overlapping from the courtyard; Laumartinez26 on TOP SUPPORTERS (ALL-TIME + THIS WEEK) after she joins a v175 server; new account sees the hook chain.
## v174 PUBLISHED (Code Bot Roblox, 2026-10-01 16:16 Dublin): Open Cloud place version 172. claude-bud JOB 48 first 2 minutes hook (owner-first)
- **Cherry-pick:** `62e1d1e` → phase-7 `99fa30a` (JOB 48 TutorialConfig.Guided.Hook). Code+dist+checks: `33972a1`. PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; no price / Id change.
- **Hook (OwnerFirst = true, NEW-OWNER-FIRST):** OrderVersion 5 = v4 + RAID A RIVAL BASE (JOB 38 verdicts / TARGETS outline / real FastRaidBonus $2k) or Clear-hostiles fallback + Open Missions; +2 free soldiers via SoldierService.GrantFree at Reward; FirstMinutes funnel steps 12-16 + SessionMilestone / FtueTimeToFight. Do NOT flip OwnerFirst until phone OK.
- **Checks:** BuyPathStatic **PASS=7877 FAIL=0**; `tools/checks/codebot_v174.py` + `claude_bud_job48.py`; `run_first_minutes_test.py` 0 failed (67 checks). codebot_v166 skips NEW-OWNER-FIRST lines.
- **Publish:** HTTP 200, versionNumber **172**, universe 10767159222 / place 97112936860418. Servers not restarted (Migrate to Latest Update as needed).
- **Phone tests (owed — Shaun):** (1) fresh test account ~2 min: first fight won, army grows +2 at BASE SECURED!, gold line on every step. (2) raid goal "Raid a rival base" with TARGETS outlined + SEND ARMY, or "Clear hostiles" on empty server. (3) owner returning account never sees the chain (REPLAY GUIDED in Settings > ADMIN for test mode). After phone OK: flip `TutorialConfig.Guided.Hook.OwnerFirst = true -> false`.
- **Still owed / not this ship:** JOB 44 Studio 2-player siege/march still owed (skipped per Shaun for queue progress). JOB 49 (reasons to come back) not started.
## claude-bud JOB 49 part B (2026-10-01): OFFLINE EARNINGS + "WELCOME BACK! COLLECT $X" (branch `claude/desktop-bud`)
**Flags to flip:**
- `EconomyConfig.OfflineEarnings.Card.OwnerFirst = true -> false` (NEW-OWNER-FIRST).
- `OfflineEarnings.CapBoost` stays **Enabled = false** until Shaun approves a price.

**Root cause:** the offline payout itself is sound (sim: 4 min = 0, rejoin spam pays once, negative gap = 0, Premium
once). The weak points:
- the card said "OK" and gave the player nothing to do;
- the Missions panel hard-coded "Away 8 h";
- **offline cash lands in PendingCash, which `MoneyCollectorService.GetRaidableBalance` counts.** A rival can raid it
  between his join and his walk to the ATM (raids need the victim online, which he is after a join).

**Built (extends RetentionService / the JOB 29 card):**
- **The card:** "WELCOME BACK! Your base earned while you were away" with the real server amount, the time away and
  "(capped at 8 h)". COLLECT draws the gold ConsoleWaypoint line to HIS ATM (walk up to collect).
  - **Why the waypoint, not a server claim:** the money is already in the ATM, so it adds no new claim path and no
    double pay.
- **The cap:** `CapSeconds` is **kept at 8 h** (inside Shaun's 8-12 h range). Share 0.25 is kept. Maths at 8 h x 0.25:

  | Income | 1 h away | Full 8 h |
  |---|---|---|
  | $60/min | $900 | $7,200 |
  | $1,000/min | $15,000 | $120,000 |
  | $20,000/min | $300,000 | $2.4M |

- **Sidegrade hook (DISABLED):**
  - `OfflineCap2x`: `DevProducts.OfflineCap2x` = Id 0, no RobuxPrice, HideFromShop, GrantEntitlement "OfflineCap2x".
  - With `CapBoost` live + that entitlement the cap TIME is x2. It never touches Share or any stat.
- **Also added:** `DevProducts.MissionReroll` (Id 0, no price) for part C. `RetentionService.OfflineCapSeconds` feeds
  the Missions panel's real "Away N h".
- **Pins:** codebot_v167's "MonetizationConfig diff = only the six Ids" now skips those two Id-0 rows (a claude-bud
  comment explains why); claude_bud_job49 pins the rows.
- **Analytics:** OfflineCollected {cash, capped}.

**Question for Shaun:** offline cash sitting in the ATM can be raided before he collects it. Should it stay raidable
(today's rule), or be safe until his first collect? Not changed.

**Checks:**
- run_daily_return_test part B (cases + exploits + CapBoost off/on + card OFF == OLD) 0 failed.
- run_offline_test +3 cases.
- BuyPathStatic FAIL=0.

**Test ON HIS PHONE:** leave for 1 h+, rejoin. The card shows "Collect $X" with the time away, and COLLECT draws the
gold line to the ATM.

## claude-bud JOB 49 part A (2026-10-01): DAILY STREAK: GRACE, INCOME-SCALED DAY 7, REAL COUNTDOWN (branch `claude/desktop-bud`)
**Flags to flip:** `DailyRewardConfig.Grace` / `.Day7Scale` / `.Calendar` OwnerFirst = true -> false (each tagged
NEW-OWNER-FIRST). Enabled = false == today's streak (pinned).

**Root cause (sim, real code):**
- A missed UTC day hard-reset the streak.
- Day 7 was a flat $20,000 (nothing at mid / late game).
- The card said "Come back tomorrow" with no time.
- A new player's first card came after an 8 s delay + a 90 s hold cap, so mid-chain on a slow run.
- No D1 numbers are claimed here (see JOB 49 D for the Creator Hub queries).

**Built (extends ClaimDailyLogin / StreakStrip, no second system):**
- **Grace:** one missed day per 7-day cycle keeps the streak (DailyLogin.Cycle / GraceUsedCycle / GraceDay, sanitised in
  ProfileSchema). The strip shows SAVED on that day; a 2nd miss or a 2-day gap resets.
- **Day 7:** max(the table $20,000, 60 min x his income per minute), on the server
  (MonetizationService.PassivePerMin, the time-pack formula, timed boosts excluded). At $900/min it pays $54,000.
- **The countdown:** the strip carries ServerNow + NextClaimUnix (the next 00:00 UTC). The card and the Missions panel
  show "Next in 5h 12m". There is no countdown when Calendar is off.
- **First session:** the first card waits for the Guided hold (it ends at the chain's reward), at the latest 150 s of
  play. The client still waits out combat / driving / panels.
- **Analytics:** StreakClaimed {day, grace}, StreakReset {lastDay}.

**Checks:**
- run_daily_return_test part A, 19 checks, 0 failed (docs/proof/job49/daily-return-sim.txt).
- BuyPathStatic FAIL=0; claude_bud_job29's literal "WaitOnboarding(player, 90)" pin is retired with a replacement.

**Test ON HIS PHONE:**
- Day 1 card + calendar with "Next in ...".
- The next day: Day 2.
- Skip one day: the streak is kept and the day shows SAVED.

## claude-bud JOB 48 (2026-10-01): THE FIRST 2 MINUTES HOOK (branch `claude/desktop-bud`)
JOB 44's Studio run was skipped on Shaun's word ("start all the jobs forget studio run").

**Flags to flip (after the phone test):**
- `TutorialConfig.Guided.Hook.OwnerFirst = true -> false`.
- Kill switch: `Hook.Enabled = false`, which gives today's v4 chain exactly (pinned).
- The line is tagged `NEW-OWNER-FIRST`. codebot_v166's "no OwnerFirst = true left" pin now skips lines carrying that
  tag, and its flip of every older block is still pinned.

**Root cause (model; no live numbers here).** The real TutorialService / GuidedService at a pace derived from the real
layout:
- the v4 chain already wins the first fight at 64 s and reaches the Reward at 79 s;
- what it lacked was army growth after the fight, and a fighting goal after the Reward. It went straight to "build the
  Barracks", then the 4x4, then ended;
- `docs/proof/job48/funnel-live.md` has the exact Creator Hub queries. Code Bot / Shaun paste the live FirstMinutes /
  GuidedStepSeconds numbers there; that is the only proof of WHICH step loses people.

**Built (reuse, not a new tutorial).** OrderVersion 5 (SavedOrders[5]) = v4 + `RaidRival` after the Reward + `Missions`
last:
- **Why a saved order, not post-chain goals:** the chip, gold tracker, skip, resume and funnel hooks all work per step
  already. v4 saves migrate to 5 (and back when the Hook is off) through the existing MigrateLegacyStep.
- **Reward:** + `Hook.RewardSoldiers` 2 free soldiers via the new `SoldierService.GrantFree`. It writes the same state
  Recruit writes, clamped to the army cap, with no cash and no Robux. Sim: army 3 -> 5. The Army tile pulses and a
  burst rings at his feet on every +1 (Juice, Hook-live only).
- **RAID A RIVAL BASE:**
  - It uses `RivalService.Candidates` (the JOB 38 verdict, ArmySendRules).
  - The TARGETS card gets a gold outline, and the chip's TARGETS button opens the list.
  - SEND ARMY (the JOB 38 path) logs RaidSent; the loot logs RaidWon (ArmyPlan, plus an in-person ATM raid).
  - The REAL fast-raid bonus: `Hook.FastRaidBonus` $2,000 once, if the raid is won within 300 s of the Reward. The
    card shows "RAID · m:ss" only while that bonus is > 0.
- **Fallback (no rival allowed):** the chip reads "Clear hostiles". 2 hostile NPC kills by him finish it; after 180 s
  the chain moves on anyway, so it never soft-locks. It is re-checked every 15 s.
- **Then:** Barracks -> 4x4 -> Open Missions (the panel open or a mission claim finishes it).
- **Funnel:**
  - FirstMinutes steps 1-11 are untouched; 12 ArmyGrew, 13 GoalRaidShown, 14 RaidSent, 15 RaidWon (or
    GoalFallbackWon), 16 NextGoal are appended to the same funnel and session.
  - **Why appended:** it avoids a second funnel against the per-experience funnel limit, and changing 1-11 would break
    their history. Verify the step limit in the Roblox AnalyticsService docs.
  - Custom events: `SessionMilestone {sec}` (60/120/180/300/600, once each per session) and `FtueTimeToFight`.
  - Studio prints `[FUNNEL] FirstMinutes <n> <step>`.
- **Dashboards to open:** Analytics > Funnels > FirstMinutes (Phone), and Custom events > SessionMilestone (the
  3-minute wall), FtueTimeToFight, GoalFallback, GuidedStepSeconds.

**A Robux card inside the first minutes: YES, by code.**
- `MonetizationConfig.FirstOffer.AtPlaySeconds = 120`, and `ClaimSoftOfferSlot` lets it through whatever the tutorial
  state.
- At the derived pace the raid goal is up from about 82 s, so the Commander Starter Pack lands during the raid goal.
  Before this job it landed during the Barracks build.
- **NOT changed (Shaun's call):** keep it at 120 s, or hold it until RaidWon / the end of the goal.

**Checks:**
- run_first_minutes_test 67 checks, 0 failed (docs/proof/job48/funnel-sim.txt); claude_bud_job48 pins.
- BuyPathStatic FAIL=0; all sims; rojo ok; no new LSP errors; remote_audit OK.
- run_codebot_v163_test now proves the v4 replay with the Hook off; the owner's replay on order 5 is pinned in
  run_first_minutes_test.

**Owed:**
- the Studio stopwatch runs before / after at 844x390 + 800x360, and step screenshots;
- the HUD harness at 6 viewports (`check_hud.py` is not in this repo);
- the live funnel numbers.

**Test ON HIS PHONE:**
1. **Fresh test account:** a soldier, the first fight won, and the army growing (+2 at "BASE SECURED!") in about
   2 minutes, with the gold line on every step.
2. **The raid goal:** "Raid a rival base" shows with the TARGETS card outlined, and SEND ARMY walks the army there. On
   an empty server it reads "Clear hostiles" instead.
3. **The owner account (returning):** never sees the chain (REPLAY GUIDED in Settings > ADMIN shows it in test mode).

## claude-bud JOB 44 (2026-10-01 ~15:20): ONE-CLICK STUDIO TEST READY, STILL BLOCKED ON THE RUN (branch `claude/desktop-bud`)
- **Tried from this session:** Roblox Studio is installed. Launching a local server from the command line
  (`RobloxStudioBeta.exe -task StartServer -localPlaceFile ...`) gives "Cannot open place file for reading", and
  "Test > Clients and Servers" needs a click in the Studio window, which this session cannot make. So the 2-player
  run itself is still owed. **JOB 48 / 49 are NOT started** (the queue rule: blocked = write it here and stop).
- **New: a test-only driver**, so the run is one click and needs no manual steps:
  - **What it is:** tools/studio/J44Driver.server.luau, a Script that exists only in the test place.
    tools/studio/build_j44_place.py builds `build/j44/J44Test.rbxl` = the normal game + that Script. It is gitignored
    and never in default.project.json or live.
  - **What it drives:** the real code (the army units are server-owned, so the march / siege is decided on the
    server).
    - **Fixture:** Player2 gets DefensiveWalls (a gate, guards and turrets); Player1's army is filled to its cap;
      WE_ArmyDebug is on.
    - **A:** `ArmyCommand.Send(Player1, Player2's plot)`. Every second it logs the phase, gate HP, block centre and
      distance; a STALL line appears when the block moves < 3 studs in 20 s while marching. Checks: reached the gate,
      gate HP fell, breach, Loot, walked out, no stall.
    - **B1:** SEND to Crossroads: reached, no stall.
    - **B3:** the TEST PLAYER is moved to his rear runway / airfield (the army is never moved); the army follows;
      SEND far away: no stall leaving the base.
  - **Output:** a final `[J44] REPORT` block in the server output, PASS / FAIL from the live state only.
- **To run (Shaun):**
  1. `python tools/studio/build_j44_place.py` (rojo on PATH, or set ROJO=...).
  2. Open `build/j44/J44Test.rbxl` in Studio.
  3. Test > Clients and Servers: Local Server, 2 players, Start.
  4. Wait about 8-10 min.
  5. Paste the server output's `[J44]` lines back to claude-bud. Any FAIL / STALL line is the root-cause lead to fix.

## claude-bud QUEUE STOP (2026-10-01 ~13:50): JOB 48 + JOB 49 held behind JOB 44 (branch `claude/desktop-bud`)
- The queue (Code Bot 914c1aa) says: JOB 44 first, then JOB 48, then JOB 49. "If one is blocked, write it in
  LATEST-HANDOFF and stop."
- **JOB 44 is blocked.** It needs a real 2-player Roblox Studio session (SEND reaches the gate, fires, breaches, files
  in, loots, walks out; marches with no stalls), and this desktop session cannot run Studio or a second client. The
  test script is in docs/proof/army-siege/JOB44-STUDIO-TEST.md; the section below has the details.
- **So I have stopped:** JOB 48 (first 2 minutes) and JOB 49 (reasons to come back) are NOT started.
- **To unblock (Shaun / Code Bot), either:**
  - run the JOB 44 Studio test and post the result (log + what stalled);
  - or say "skip JOB 44 for now, start JOB 48", and I start JOB 48 at once.

## v173 PUBLISHED (Code Bot Roblox, 2026-10-01 13:25 Dublin): Open Cloud place version 171. claude-bud JOB 46 + JOB 47
- **Published** `dist/WarEmpire-PERF.rbxlx` (WE_Build **173**), HTTP 200 `{"versionNumber":171}`. Servers NOT restarted (new servers get it; Migrate to Latest Update / rejoin a fresh server). Code + dist commit `83f3b0d` on phase-7-polish; cherry-picked JOB 46 `5af86a1` + JOB 47 `dd8415d` from `origin/claude/desktop-bud`.
- **JOB 46 — rebirth stations (5af86a1):** zone prompt preview card (name, level step, price, exact gains from `RebirthZonesConfig.CardFor` / `Gains`, what you can do) + richer locked signs; themed apron dressing (`RebirthZoneDressing`: gateway with name/level, props) and a server-side activity kiosk per zone (ship / sweep / drill / strike / nuke). Client `RebirthZoneController` wired in Bootstrap. No teleport / fast travel. Dressing never touches WE_Building*, no Neon, no lights.
- **JOB 47 — ghost label behind INTEL OFFICE (dd8415d):** far base owner tags that project into the top-bar HUD row now hide via `BaseMarkerConfig.InTopBar` + `TopBarPadPx` before `VisibleSet` (uses live `GuiService` inset / TopbarInset). Root cause: tags float high (`HeightAt`), so a far base projected into the translucent compass / LV / cash pills.
- **RecruitTrimService:** kept Code Bot v172 gate-post placement (arch from real GatePost parts, no raycast float). Only Claude's comment reword applied (`protected base building part`) so older BuyPathStatic pins stay green. Did NOT take JOB 46's older RecruitTrimService body (would have regressed the arch).
- **Checks:** BuyPathStatic **PASS=7848 FAIL=0**; PreferMesh OFF; StreamingEnabled OFF; new `tools/checks/codebot_v173.py` + `claude_bud_job46.py` + `claude_bud_job47.py`; `run_rebirth_stations_test.py` 0 failed; `run_targets_scout_test.py` 0 failed. No price / Id change; WE_Building* untouched; OwnerFirst flags untouched.
- **Phone tests (owed):** (1) walk a rebirth zone prompt → preview card shows name / level / price / gains / what you can do; locked zones show richer signs; apron gateway + activity kiosk present on a built zone. (2) look past INTEL OFFICE / compass at a far rival base tag — the owner name must NOT ghost through the top-bar pills. (3) Recruit Pack arch still clear of the wall at your walls level (v172 placement).
- **Still owed / not this ship:** JOB 44 still Studio-blocked (2-player hostility/protection). Servers not restarted.

## v172 PUBLISHED (Code Bot Roblox, 2026-10-01 12:59 Dublin): Open Cloud place version 170. BOTH Recruit Pack base trims
- **Published** `dist/WarEmpire-PERF.rbxlx` (WE_Build **172**), HTTP 200 `{"versionNumber":170}`. Servers NOT restarted (new servers get it; rejoin a fresh server / restart needed for live servers). Code + dist commit `299d052` on phase-7-polish; bud merge `57b0a5e`.
- **Shaun approved keeping both trims.** v171's gold wall bands + pinstripes, gate post bands and finials (BaseTierBuilder, inside WE_BaseTier, any tier) stay; claude-bud **JOB 45**'s gold gate arch with the "★ RECRUIT ★" banner (`RecruitTrimService` + `RecruitTrimConfig`, `64dd380`, Workspace.WE_RecruitTrim) is now in phase-7-polish too, with JOB 45's `[RECRUIT]` receipt / boost logs in MonetizationService. Nothing else from bud was taken (JOB 46 `5af86a1`, the run_achievement_test edit and the SquadOrders duplicate require stay bud-only).
- **Arch placement fixed (Code Bot):** JOB 45 stood the pillars 4 studs in from the PLOT edge = inside the front wall body (the wall is 1.5 in from the pad edge and 3.5-6.3 thick) at every walls level, and raycast the ground from 60 studs up, which could land on the GateArch / gatehouse lintel and float the arch. `RecruitTrimService.Placement` now reads the real gate (the two GatePost parts in WE_PerimeterWalls, the WallGate_* thickness / height, the post bottoms): pillars stand 1 stud behind max(wall half + 0.8, 2.6) (clear of the gate arch / chevron, post roofs, Tier 3 gatehouse, Bastion crest and the v171 bands) and in front of the gate guards (10 in); height = max(18, wall + 5) so it rises over the wall and the banner hangs above the gate opening; the 5 s sweep rebuilds it when the walls level changes. No walls: the old front-edge spot at the pad top. 35 non-colliding Metal / Slate / Fabric parts (no lights, meshes, Neon, WE_Building*).
- **Queue (bud CLAUDE.md):** JOB 45 marked DONE via v172; JOB 47 marked DONE / SUPERSEDED by v171 (do not start). JOB 46 is Claude's (pushed `5af86a1`, not in polish).
- **Checks:** BuyPathStatic PASS=7808 FAIL=0 (bud after merge PASS=7816 FAIL=0); new `tools/checks/codebot_v172.py` (44 checks: both trims present + wired, placement, no collision, no price change, PreferMesh / StreamingEnabled OFF); `run_recruit_trim_test` 0 failed incl. new section 7 (walls Lv 1-5 + a turned plot: no overlap with wall / v171 bands / posts / gatehouse / guards / lane, on the pad, above the wall, inside its face, no coplanar faces); recruit_pack, endgame, codebot_v171 0 failed.
- **Phone test:** fresh server, your base: gold bands on the walls / posts AND a gold arch with the RECRUIT banner just inside the main gate, standing clear of the wall, its finials above the wall line. Still owed: a Studio / live screenshot of the arch at your walls level.

## v171 PUBLISHED (Code Bot Roblox, 2026-10-01 12:33 Dublin): Open Cloud place version 169. Three live bugs (Shaun 12:08, R10)
- **Published** `dist/WarEmpire-PERF.rbxlx` (WE_Build **171**), HTTP 200 `{"versionNumber":169}`. Servers NOT restarted (new servers get it; rejoin a fresh server). Code + dist commit `2cacf57` on phase-7-polish; bud merge `aca0415`.
- **1. TARGETS card gone. Cause (proved):** v168's `crosshair()` in `RivalController` set `f.AnchorPoint = spec[5]`, but every spec has 4 fields, so it was nil. Roblox throws on a nil typed property, so `build()` (in task.spawn) died right after parenting the card: no Size/Position, no text, no tap, `refresh()`/`layout()` never ran, so nothing was visible. It was broken since v168 for everyone; not caused by the Intel guide, the R10 grant or the overlap logic. **Fix:** `spec[4]`; the card is sized/placed from `RivalConfig.Layout` before any decoration; the icon runs in a pcall. Proof: `tools/sim/rival_controller_harness.py` (GUI stand-in that throws on nil like Roblox): the v170 source → "Unable to assign property AnchorPoint", w/h -1, no title, 0 taps; v171 → 180x64 at (836,8), TARGETS / "No target now", 1 tap, push fills it.
- **2. Scout report "did nothing". Cause:** the server path worked (charged 1 min of income, stored the report), but its only output was a 1.8 s toast and a grey INFO row 5th in the Intel list (under 3 contracts + HVT, below the fold), held only in this server's memory (lost on a server move; Shaun was hopping servers). The report was also built after SpendCash, so a failure there would keep the cash with no result. No runtime error reproduced. **Fix:** `EndgameService.BuildScoutReport` runs BEFORE the charge (failure → "Scouting failed, try again (nothing charged)"); the report is saved in `profile.Endgame.ScoutReport` (ProfileSchema drops malformed ones); a FeaturePush "ScoutReport" opens a gold result card (tier, gate HP, turrets/guards, defences, your army's verdict, age) with GOT IT; the report leads the Intel list with VIEW (reopens the card, never a purchase). His earlier paid report was in server memory only and is gone; no refund code was added (the purchase did deliver a report, just badly shown).
- **3. Recruit Pack gold trim. Cause:** the "gold trim" never existed as base geometry: only a "RECRUIT · " prefix + thicker (already gold) stroke on the base sign title and a marker pill stroke. **Fix:** `BaseTierBuilder` RecruitTrim folder (any tier): a polished gold Metal band under every perimeter wall body's concrete cap + a deep-gold pinstripe, a gold band on each gate post, gold finials (bare post: ball; Tier 1+ post roofs: their finial turns gold). Non-colliding, no ray, no Neon. Built by `EndgameService.SyncBaseTier` from the SAVED `profile.Entitlements.RecruitPack` while `RecruitPackLiveFor` (persists on rejoin, 5 s sweep), and at once on the `WE_Ent_RecruitPack` attribute change; the receipt also refreshes the base sign. **Grant confirmed from code:** cash = `RecruitPackCashFor` = Cash30m time-pack amount (max $25k, 30 × income/min, timed boosts excluded), entitlement saved + attribute, `CodesService.GrantCashBoost(player, 30, 2)`.
- **Overlap with claude-bud JOB 45 (pushed to bud 12:28, found at merge):** bud independently added `RecruitTrimService` (a gold gate ARCH with a RECRUIT banner in Workspace.WE_RecruitTrim). On bud both now exist (arch + my wall/post trim); the published build (phase-7-polish) has only the v171 trim. Owner/bud to decide whether to keep both. At merge I pinned `run_recruit_trim_test`'s "before" grep to `d38c766` (it grepped the moving origin/phase-7-polish and failed once v171 landed) and reworded one RecruitTrimService comment (WE_Building* text tripped the v151-v154 pins). bud's queued **JOB 47 (TARGETS card + scout report) is done by v171**.
- **Also:** `run_achievement_test` had not been updated for the v170 badges (8 FAIL in BuyPathStatic); fixed (bud's equivalent fix kept at merge). `codebot_v157` early-return pin follows the new `and not recruit`.
- **Checks:** BuyPathStatic PASS=7755 FAIL=0 (bud after merge PASS=7764 FAIL=0); new `tools/checks/codebot_v171.py`, `tools/sim/run_codebot_v171_test.py` 0 failed; 13 new v171 checks in `run_endgame_test` 0 failed; recruit_pack, rival_targets, v163/v168/v169, shop_render, achievement, base_marker, blackmarket_public, rebirth, time_packs, first_offer 0 failed. No flag / price change; PreferMesh OFF; no WE_Building*.
- **Phone tests:** fresh server: TARGETS card top-right under the compass; Intel Office scout → result card pops, VIEW at the top of the Intel list, survives a rejoin; your base walls show gold bands under the caps + gold gate posts within ~5 s of joining.

## v170 PUBLISHED (Code Bot Roblox, 2026-10-01 11:36 Dublin): Open Cloud place version 168. Wire 5 free achievement badges (batch 2)
- **Published** `dist/WarEmpire-PERF.rbxlx` (WE_Build **170**), HTTP 200 `{"versionNumber":168}`. Servers NOT restarted. Code commit `798416a` + dist `e4bcfca` on phase-7-polish.
- **Badges (Creator Hub, universe 10767159222, free daily quota, already created/enabled):** wired into `AchievementConfig` only (no new badges paid for):
  - Cash100k / Six Figures → `3066564903295841`
  - FirstOutpost / Outpost Taken → `3933837527405364`
  - Level10 / Sergeant → `2735659013414286`
  - Cash1M / Millionaire → `3464730701383868`
  - CommandCenterMax / High Command → `2700577206257761`
- **11 BadgeId=0 remain** for the daily free routine: PlazaCaptured, PlayerKills100, Rebirth1, Army50, FirstNuke, Cash100M, Rebirth5, Rebirth10, Rebirth20, Streak7, WeeklyCrown.
- Award / join backfill unchanged (`AchievementService.BackfillBadges`). Players who already unlocked these get the badge on next join.
- **Checks:** BuyPathStatic PASS=7702 FAIL=0; `tools/checks/codebot_v170.py` (WE_Build=170 + 5 new BadgeIds + 11 zeros + PreferMesh OFF + FastTravelEnabled=false); `codebot_v134` zero-count updated 16→11 (original 5 ids still pinned). PreferMesh / StreamingEnabled OFF; 10 players; no WE_Building*; OwnerFirst flags untouched; no price changes.
- **Phone tests:** join on a v170 server; if you already have Six Figures / Outpost Taken / Sergeant / Millionaire / High Command unlocked, the Roblox badge should appear (inventory / badge page). New unlocks award immediately.

## v169 PUBLISHED (Code Bot Roblox, 2026-10-01 11:15 Dublin): Open Cloud place version 167. One-time owner rebirth grant (R10)
- **Shaun:** doesn't want to type /setrebirth. **Published** `dist/WarEmpire-PERF.rbxlx` (WE_Build **169**), HTTP 200 `{"versionNumber":167}`. Servers NOT restarted. Code commit `a6f160a` on phase-7-polish; claude/desktop-bud merge `e396dde`.
- `AdminConfig.OwnerRebirthGrant = { UserId = 470626172, Rebirths = 10, Key = "rebirth10-2026-10-01" }`. On his next profile load (PrestigeService OnProfileLoaded, deferred) `PrestigeService.ApplyOwnerRebirthGrant` -> `AdminSetRebirth(player, 10)`: the exact /setrebirth path (cash / items kept, unlocks + zones + endgame + pushes refreshed, saved). It writes `profile.AdminGrants["rebirth10-2026-10-01"] = { At, From, Applied }` first, so it never re-applies (after a further rebirth or a lowered count). Already >= 10: nothing changes (marker only). Needs the UserId in AdminConfig.UserIds; nil = off; a new Key = a new one-time grant. Owner stays board-excluded (isBoardExcluded). Log line: `[AdminRebirth] shaunie6 grant rebirth10-2026-10-01: R<n> -> R10 (one time)`.
- **Note:** a server already running old code will not apply it; he needs to join a server on v169 (Migrate to Latest Update or a new server).
- **Checks:** BuyPathStatic PASS=7719 FAIL=0; `tools/checks/codebot_v169.py`; `tools/sim/run_codebot_v169_test.py` 0 failed (plus the v168 sections). PreferMesh / StreamingEnabled OFF; 10 players; no WE_Building*; no price changes.

## v168 PUBLISHED (Code Bot Roblox, 2026-10-01 11:09 Dublin): Open Cloud place version 166. TARGETS card, /setrebirth, sign overlap fix, Intel Office guidance
- **Published:** `dist/WarEmpire-PERF.rbxlx` (WE_Build **168**) via `tools/publish-opencloud.sh`, HTTP 200 `{"versionNumber":166}`. Servers NOT restarted (use Migrate to Latest Update). Code commit `c863688` on phase-7-polish; claude/desktop-bud merge `8f83d31`.
- **1. TARGETS card (RivalConfig.Pill / Layout / PillLines / RowLines, RivalController):** a 64 px opaque card top-right under the compass / BASE row (1024x471: 180 px wide, x 836..1016, y 66..130 real px), 2 px stroke, crosshair icon (30 px; an 18 px icon in the title row on narrower phones), "TARGETS" + red count badge, then the server's suggested rival (rows[1]) name and "500m · $100k+"; with none: "No target now" + a short reason (ShortWhy: "You're alone", "Recruit soldiers", ...), gold accent. Tap opens "RIVAL TARGETS": per row name + "Lv N", "Army N" + verdict chip, "$X loot · distance", SEND ARMY (the JOB 38 RequestArmySend remote) + VIEW (map). On short screens the list slides up over the card (X closes). Visibility rules from v163 kept. No fast travel. RivalService rows now carry Level.
- **2. `/setrebirth N` (owner / AdminConfig only, the same AdminService allowlist as /replaytutorial and /armydebug; also gear -> ADMIN -> [-] REBIRTH N [+] SET REBIRTH, default 10):** `PrestigeService.AdminSetRebirth` sets `profile.Prestige` = N (0..50), re-applies the RebirthUnlocks (grants vehicles/guns at <= N; flags above N cleared, items kept), `EndgameService.AdminSyncRebirth` (endgame unlock flags, base tier, cost-scale attributes, signs), RebirthZoneService.Refresh, outpost income stacks, the Economy / XP / Base / rebirth-state pushes, then MarkDirty + SaveProfile. Cash, level, XP, gold, upgrades, vehicles, weapons untouched; no gold / analytics. Admins stay off every board (isBoardExcluded). **Shaun: type `/setrebirth 10` in chat (or use the Settings button).**
- **3. Sign overlap:** the locked rebirth-zone sign BillboardGui (`WE_ZoneLockedSign`, "EAST YARD / Unlocks at Rebirth 5") is tagged `WE_ObjectiveYield`; ObjectiveMarker hides only its world LABEL (AIRDROP / BASE / INTEL OFFICE) while its on-screen box overlaps a tagged sign within the sign's 40-stud range (6 px pad, hysteresis). The GO beam and the compass pill stay.
- **4. Intel Office guidance:** while a daily contract (today) or the weekly HVT is done but unclaimed, EndgameService sets the player attribute `WE_IntelGuide` = the Intel Office point (set with the "Contract done" / new "Weekly target done" toast and on the 5 s sweep; cleared on claim). Client `IntelGuide` drives the existing ObjectiveMarker (yellow compass pill "INTEL OFFICE 1.2km" + world marker) when the tracker is free; clears on claim, on arrival (10 studs, re-shows past 40) or after 30 min.
- **Checks:** BuyPathStatic PASS=7709 FAIL=0. New `tools/checks/codebot_v168.py` + `tools/sim/run_codebot_v168_test.py` (targets geometry on 1024x471 / 956x440 / 844x390 / 800x360, setrebirth, overlap, intel) all 0 failed; rival_targets, codebot_v163, endgame, rebirth, base_marker sims 0 failed. v163 pill-geometry pins retired (superseded by v168). PreferMesh / StreamingEnabled OFF; 10 players; no WE_Building*; no price changes.
- **Phone tests:** TARGETS card readable and not overlapping compass / ammo / MED KIT; tap -> rows + SEND ARMY; `/setrebirth 10` -> Rebirth panel shows 10, zones R<=10 unlock, cash unchanged, survives rejoin; finish a contract -> the pill reads INTEL OFFICE and leads to the office, clears after claiming; AIRDROP label no longer drawn over the EAST YARD sign.

## v167 PUBLISHED (Code Bot Roblox, 2026-10-01 11:05 Dublin): Open Cloud place version 165. TIME PACK + RECRUIT PACK IDS: the time packs are in the Shop and the Recruit Pack is offerable
- **Products:** Shaun approved the prices on 2026-10-01. The six developer products were created on the Creator Hub (universe 10767159222). The Open Cloud key has no developer-product scope (HTTP 403 "Scope not authorized"), so they were made in the browser. Ids: Cash15m **3715776339** (25 R$), Cash30m **3715776410** (49), Cash1h **3715776466** (89), Cash2h **3715776582** (159), Cash4h **3715776616** (279), RecruitPack **3715776659** (49).
- **Published:** `dist/WarEmpire-PERF.rbxlx` (WE_Build **167**) via `tools/publish-opencloud.sh`, HTTP 200 `{"versionNumber":165}`. Servers have NOT been restarted (use Migrate to Latest Update).
- **Commits:** phase-7-polish `1d98d02` (source, checks and dist); claude/desktop-bud merge `d02e4d4`; plus this handoff.
- **Effect:** all five time-pack Ids are set, so `ShopOverhaulConfig.TimePacksReady()` is true. The 4h..15m time rows replace the old four cash rows in the Shop for everyone; the cash "+" and the Mega toast now sell Cash4h. The RecruitPack Id is set, so `MonetizationConfig.RecruitPackTakesStarterSlot` is true: the Recruit Pack is offered (first capture or 10 min) and takes the Starter Pack first-offer slot.
- **Unchanged:** no flag edits (TimePacks and RecruitPackOffer were already live since v166); no price change and no other product Id change (codebot_v167 pins that the MonetizationConfig diff vs v166 is only these six Id values). PreferMesh OFF, 10 players.
- **Checks:** BuyPathStatic PASS=7696 FAIL=0. New `tools/checks/codebot_v167.py` (WE_Build, six nonzero exact Ids, distinct, diff-only-Ids, plus 4 sims). The "Id 0" pins in claude_bud_job41/42 and codebot_v156/v158/v160/v161 now pin the shipped Ids. The sims prove the shipped config and still exercise the Id-0 paths explicitly: run_time_packs_test (Ready + shown to everyone), run_recruit_pack_test (shipped Id: takes the Starter slot, offered to a non-owner at the first capture), run_shop_render_test (new "real" mode: time rows for the owner and for uid 9), run_first_offer_test (Starter Pack path with Recruit Pack Id 0). All report 0 failed.
- **Phone tests:** the Shop shows 4 HOURS OF CASH (BEST VALUE, 279 R$) down to 15 MIN OF CASH (25 R$) where the old Cash Pack S..Mega rows were. A new profile gets the Recruit Pack card after its first capture. Do a test buy of 15 MIN OF CASH to confirm the receipt grants max(floor, 15 x income).

## v166 PUBLISHED (Code Bot Roblox, 2026-10-01 10:47 Dublin): Open Cloud place version 164. FLIP-ALL-LIVE: every owner-first feature is live for everyone
- **Shaun 10:31:** "Turn everything on for everyone please, obviously the speed update just when someone pays for the speed boost."
- **Published:** `dist/WarEmpire-PERF.rbxlx` (WE_Build **166**) via `tools/publish-opencloud.sh`, HTTP 200 `{"versionNumber":164}`. Servers have NOT been restarted (use Migrate to Latest Update).
- **Commits:** phase-7-polish `ec524bf` (source, checks and dist); claude/desktop-bud merge `c434a13`; plus this handoff.
- **Flipped to `OwnerFirst = false` (Enabled kill switches kept):** `TutorialConfig.Guided`, `GuardConfig.Posts` (real base guards at every base), `ShopOverhaulConfig.TimePacks`, `StorePropsConfig` and `cfg40.JOB40`, `MonetizationConfig.RecruitPackOffer`, `RivalConfig`, `RatePromptConfig`, `EndgameConfig.Live` (every endgame part), `ArmyConfig.ArmyBrawl`, `ArmyOrdersConfig.Live` (so `LiveForAll()` is now true), `MonetizationConfig.SpeedV2`. No `OwnerFirst = true` field is left in Shared/Configs.
- **SpeedV2:** it only changes the multiplier of the two speed SKUs: Speed Pass x1.5 -> x1.75 (28 studs/s) and Speed Boost x2 -> x2.5 (40 studs/s). Owning both gives x2.5. The cap is 2.5. The speed itself is applied only through `MonetizationService.SpeedMultFor`, which returns the highest multiplier among the speed SKUs the player OWNS (the game pass, or the product's entitlement). With none owned it returns 1 and WalkSpeed is never written. So only payers run faster. No extra gate was needed. This is proved on the real MonetizationService in `run_recruit_pack_test`: no SKU = x1, Speed Boost = x2.5, Speed Pass = x1.75, both = x2.5. The Shop text now reads "Run 2.5x faster" / "Run 75% faster" for everyone. Prices and Ids are unchanged.
- **Fix found while flipping:** while the Recruit Pack was live for a player, the old Starter Pack first offer (and its Speed Boost fallback) were suppressed, even with Recruit Pack Id 0. Flipping it to everyone would have silently stopped the Starter Pack pop-up for all players. Fixed with the new `MonetizationConfig.RecruitPackTakesStarterSlot(userId)`, which requires live AND Id ~= 0; MonetizationService uses it in both places. Until the Creator Hub Id is set, the Starter Pack offer runs exactly as before.
- **Product Ids in this build:** time packs Cash15m/30m/1h/2h/4h Id **0** and Recruit Pack Id **0**. The Creator Hub worker had not shipped yet, and no Code Bot job was mid-flight. So the time packs stay hidden (`TimePacksReady` false, old cash rows shown) and the Recruit Pack is never offered, until a build carries the Ids.
- **Unchanged:** admins and the owner stay off every board (`isBoardExcluded`); 10 players; StreamingEnabled and PreferMesh OFF; no WE_Building* edits; no fast travel; no price changes. `VisualAssetConfig.BodyRollout` stays "owner" (11 store hulls have no licence record, codebot_v101; it is not an OwnerFirst flag).
- **Note:** v155 had reset `StorePropsConfig.OwnerFirst` from false back to true with no stated reason. v166 sets it false again, with the world props budget unchanged (MaxWorldParts 9000).
- **Checks:** BuyPathStatic PASS=7671 FAIL=0. New `tools/checks/codebot_v166.py` (58 pins + 12 sims). Every `tools/sim/run_*` run reports 0 failed: army orders, command, march, siege and brawl; recruit pack; time packs; first offer; first minutes; rival; rate prompt; endgame; black market; base guards; speed; shop. Owner-first pins in claude_bud_job38-43 and codebot_v132/v143-v165 are superseded. The sims still prove the owner-first rule with OwnerFirst pinned true, and then prove the launch for a non-owner.
- **Phone tests (use a NON-owner account if possible):** a new profile gets the Guided chain with the camp; rear/sea-gate guards are armed at every base; the TARGETS pill and SEND ARMY work; the EMPIRE stations work (every part); army ATTACK/SEND/RECALL works and soldiers fight enemy soldiers; without a speed purchase you run at the default 16; with the Speed Boost you run at 40; the "Enjoying WAR EMPIRE?" card appears after 15 min of play.

## v165 (Code Bot Roblox, 2026-10-01 ~10:05 IST): place version 163. Commit 3f27240 on phase-7-polish, bud merge 767e9c0
Shaun's three phone reports:
- **Report 2** (SEND to Crossroads: ATTACK lit + "RETURNING", gold PIN line): the servers were still on old code (pre-v162). No code change; needs a **server restart**.
- **Report 1** (SEND siege "gate 100% guns 0", the army against the wall away from the gate):
  - Cause: the siege target was the owner standing behind his wall, which no ray can reach, so there were no shots and the block steered into the wall. "guns" counted the victim's turrets.
  - Also: after a breach the phase stayed Siege (the lead never walked in), and units beside the 14-stud gate pressed into the wall.
  - Fix: nothing behind the standing walls is a siege target (the gate is). On breach the phase becomes Loot, and a funnel files units through the gate (`ArmyController.Funnel`). The status now reads "gate N% · firing N · enemy guns N", plus `[ARMY SIEGE]` logs.
- **Report 3** ("MARCHING" but standing still by a base wall or around a player):
  - Cause: on the march any hostile player within 120 studs became the target, so the block steered at a player in his own yard behind a wall.
  - Fix: on the march only an aggressor is answered (a player, or his JOB 43 soldiers, who hurt this army in the last 10 s, within 60 studs, not inside a walled plot: `GateDefenseService.WalledPlotAt`). Added a routing watchdog (re-plans when a path request is outstanding 20 s) and `[ARMY MOVE]` wait-reason logs.
- Proof: `docs/proof/army-siege/REPORT.md` (before/after logs).
- Tests: `tools/sim/run_army_siege_test.py` and `tools/checks/codebot_v165.py`. BuyPathStatic PASS=7613 FAIL=0.
- The servers have NOT been restarted.

## v164 PUBLISHED (Code Bot Roblox, 2026-10-01 09:46 Dublin): Open Cloud place version 162 — JOB 42 part C + JOB 43 owner-first
- **Published** `dist/WarEmpire-PERF.rbxlx` (WE_Build **164**) via `tools/publish-opencloud.sh` -> HTTP 200 `{"versionNumber":162}`. Servers NOT restarted (Migrate to Latest Update / rejoin). Code commit `49f1df1`.
- **Cherry-pick:** Claude `7808f30` JOB 42 C (Recruit Pack cash = Cash30m while TimePacks live) + Claude `77b4172` JOB 43 (army vs army brawl); JOB 42 D docs (SHOP.md + proof README). SquadOrdersService conflict with v162 resolved by keeping **both** ArmyState/ArmyCommand and ArmyBrawl.
- **Flags left OwnerFirst=true (do NOT flip without Shaun):**
  - `ArmyConfig.ArmyBrawl` Enabled + OwnerFirst=true (soldier-vs-soldier only for owner until flipped).
  - Still: `ShopOverhaulConfig.TimePacks` OwnerFirst=true (Ids=0); `TutorialConfig.Guided` OwnerFirst=true; `MonetizationConfig.RecruitPackOffer` OwnerFirst=true (Id=0); `RivalConfig` OwnerFirst=true; `RatePromptConfig` OwnerFirst=true; `ArmyOrdersConfig` OwnerFirst stays true.
- **JOB 42 C:** while TimePacks is live for the player, Recruit Pack cash = `ShopOverhaulConfig.TimePackAmount("Cash30m", perMin)` via `CashFromTimePack` / `RecruitPackCashFor` (same income lookup + re-check; card shows the same $). OFF = the JOB 41 clamp. 49 R$ / Id 0 / 2x boost / gold trim unchanged.
- **JOB 43:** root cause proven — `nearestHostile` skipped OwnerUserId models so enemy soldiers never became candidates. Fix: `Modules/ArmyBrawl.Candidates` under `CombatService.ArmyHostility`; ATTACK/SEND + FOLLOW/HOLD picks add "Unit"; `CombatService.ApplyUnitUnitHit` re-checks per shot; kills -> ARMY KILLS + 10 XP (pair-capped). Board already live (v156).
- **PreferMesh stays OFF.** No WE_Building* touch. Servers stay at 10. No fast travel. **No Creator Hub products created.**
- **Checks:** BuyPathStatic PASS=7556 FAIL=0; codebot_v164 PASS; run_recruit_pack_test 0 failed; run_army_brawl_test 0 failed; rojo build deterministic (both dist copies identical).
- **Owed / NEXT:** Creator Hub five time-pack Ids (still); 2-player Studio test for JOB 43 (soldier-vs-soldier, fight continues after player dies, clan mates untouched). Do NOT flip OwnerFirst flags.

**Phone tests for Shaun (owner account):**
1. Shop / Recruit Pack card: while TimePacks is live for you, the Recruit Pack "$N Cash" matches the 30 MIN OF CASH row (Ids still 0 = SOON layout only until Creator Hub).
2. With a friend NOT in your clan: walk armies together — your soldiers shoot his SOLDIERS too; after he dies the fight continues until one army is wiped / out of range; ARMY KILLS board counts soldier kills (owner/admin never listed).
3. Clan mate's army is never attacked.
4. Non-owner still: no TimePacks shop swap, no ArmyBrawl (OwnerFirst). PreferMesh OFF.

## claude-bud JOB 43 (2026-10-01): ARMY VS ARMY BRAWL + ARMY KILLS BOARD (merged into v164)
**Flag:** `ArmyConfig.ArmyBrawl` (`Enabled`, `OwnerFirst = true`). OFF = today.
**To launch:** `OwnerFirst = false`.
See v164 PUBLISHED above for root cause, fix, checks, and phone tests.

## claude-bud JOB 42 PART C (2026-10-01): THE RECRUIT PACK CASH = THE 30-MIN PACK (merged into v164)
See v164 PUBLISHED above. Parts A+B already live owner-first (v161); part D docs shipped with v164.

## v163 PUBLISHED (Code Bot Roblox, 2026-10-01 09:37 Dublin): Open Cloud place version 161 — TARGETS always visible, owner Guided replay (test mode), TOP SUPPORTERS credits every purchase
- **Published** `dist/WarEmpire-PERF.rbxlx` (WE_Build **163**) via `tools/publish-opencloud.sh` -> HTTP 200 `{"versionNumber":161}`. Servers NOT restarted (Migrate to Latest Update / rejoin). Code commit `05f52f9` (worktree `/workspace/wt-tgs`, branch `codebot/targets-guided-supporters`); bud merge `b00006f`.
- **1. TARGETS (JOB 41 C, RivalConfig OwnerFirst=true kept):** the pill is top-right, under the top-bar row (the compass chip), Right 16 / Top 64 real px under the topbar inset (1024x471 phone: x 880..1008, y 122..170). It was **hidden whenever the server listed 0 targets**, i.e. unless another player was in the server AND past new-player protection (10 min since first join, + novice shield) AND not shielded / just-raided / a clan ally AND had >= $10k in the ATM (10% steal >= MinLootToShow $1,000; bully targets need $20k) AND beatable (army power >= 0.25x defences), while Shaun had soldiers, no SEND out / cooldown, and was not in the Guided hold. Distance only sorts. So he almost never saw it. **Now** the pill always shows for a live player (dimmed, no badge, when empty); tapping it opens "No targets right now — rivals appear when other players have cash to raid" + one server reason (alone / recruit soldiers / everyone protected / nobody has $10k+ / defences too strong / army out or resting / finish the guided minutes). It hides only while another full-screen panel is open (Modal), while dead, and while the Recruit Pack card slides into the same corner. Desktop caveat: Roblox's own player list (top-right, Tab) can cover it when expanded.
- **2. Guided replay (owner / admin only, server-authoritative, test mode):** chat `/replaytutorial` (alias `/replayguided`, hidden from autocomplete) or **Settings (gear) > ADMIN > REPLAY GUIDED TUTORIAL (test)** (row only for AdminConfig.UserIds; server re-checks AdminService.IsAdmin). `TutorialService.ReplayGuided` snapshots TutorialComplete/Step/OrderVersion/DoneAhead/Guided into `profile.GuidedReplay`, plays the Guided order (v4) from step 1: ClaimBase (auto) -> Command Center skipped (owned) -> Income -> Recruit -> **FIRST FIGHT (fresh 2-Recruit camp)** -> Outpost skipped (already taken) -> REWARD banner -> Barracks skipped -> Jeep. **No cash** (no top-up, no reward cash), **no funnel / GUIDED_* / onboarding analytics**. The end, SKIP, or the next profile load restores the snapshot exactly. No onboarding pop-up hold during a replay. Refused while a replay runs or while a real tutorial is unfinished.
- **3. TOP SUPPORTERS root cause:** dev products WERE recorded (ProcessReceipt -> recordPurchase adds CurrencySpent to Monetization.RobuxSpent before the save/ack), but the board only got the new value through the **throttled writer** (once per 90 s per player; the v107 leave flush also respects the throttle, and DataService.UnloadProfile clears the profile at the start of PlayerRemoving, so the flush can find no profile). A buyer who left within ~90 s of the previous periodic write was never written until a later session; plus up to 75 s for the shared read. Game passes bought outside the in-game prompt (website/store page), or whose ~37 s in-game ownership confirm ran out / who left first, were **never added** to RobuxSpent. Not the cause: dev products not counted (they are), a minimum (none, > 0), the buyer excluded (only AdminConfig.UserIds = Shaun). **Fix:** EngagementService listens to MonetizationService.OnGranted (saved dev-product grants) and OnPassOwned; writes TOP SUPPORTERS at once (no throttle; the value only moves with a paid, saved purchase); the leave flush always writes a changed supporter value (cached value when the profile is gone); a pass owned on Roblox but never counted is credited once at PriceInRobux (ledger `profile.LB.PassCredit`; a legacy profile with Purchases > #ProcessedReceipts is recorded without credit — never double counted). Admin/owner never written; opt-out kept; Studio never credits.
- **Was the 09:00 Cash Pack S recorded?** Could NOT verify: the Open Cloud key in the env (the publish key) lacks DataStore scopes (HTTP 403 `universe-datastores.objects:list`, `universe.ordered-data-store.scope.entry:read`). No buyer UserId known, so **no backfill was written and nothing was faked**. If the receipt was granted, his profile already holds RobuxSpent 49 and he is written to TOP SUPPORTERS on his next join to a v163 server (first periodic write, ~5 s), visible on every server within ~75 s. If the receipt was never acknowledged, Roblox re-delivers it on his next join and it is credited at once. To check now: give the key `universe-datastores.objects:read` + `universe.ordered-data-store.scope.entry:read` (WarEmpire_PlayerData_v2 / WE_LB2_Supporters), or look up the buyer in Creator Hub > Sales.
- **Checks:** BuyPathStatic PASS=7558 FAIL=0 (incl. codebot_v163, which runs `tools/sim/run_codebot_v163_test.py`: TARGETS 9 + REPLAY 14 + SUPPORTERS 13 checks); run_first_minutes / run_rival_targets / run_recruit_pack / run_rate_prompt / run_army_command / engagement_gate 0 failed. Army files untouched. **PreferMesh OFF**, no WE_Building* touch, no OwnerFirst flipped.

**Phone tests for Shaun (owner account):**
1. Top-right under the compass: **TARGETS** pill (dim). Tap: the list says "No targets right now — ..." and why. With a friend (10+ min old account, $10k+ in ATM, you with soldiers): pill turns bright with a red count, rows with SEND ARMY / VIEW.
2. Chat `/replaytutorial` (or gear > ADMIN > REPLAY GUIDED TUTORIAL): Income -> recruit -> camp fight at your Home Outpost -> BASE SECURED banner -> 4x4. Cash only changes by what you spend. At the end: "Guided replay finished (test mode). Your progress is unchanged." SKIP also ends it.
3. TOP SUPPORTERS board (Town Centre): a test purchase by a non-admin account appears within ~75 s even if they leave right away.

## v162 PUBLISHED (Code Bot Roblox, 2026-10-01 09:24 Dublin): Open Cloud place version 160 — ARMY COMMAND BUG FIX (owner report: SEND -> Crossroads -> GO, army stays; ATTACK "No enemies near")
- **Published** `dist/WarEmpire-PERF.rbxlx` (WE_Build **162**) via `tools/publish-opencloud.sh` -> HTTP 200 `{"versionNumber":160}`. Servers NOT restarted (Migrate to Latest Update / rejoin).
- **Root cause (proven, `docs/proof/army-command/before-client.log`, real client code in the sim):** Army SEND opened the ordinary tap-to-pin world map; a zone card's GO pinned a waypoint for HIM (the "PIN 678m") and closed the map; **no army remote was fired**, the server never heard it, FOLLOW stayed. The server's RequestArmySend also took plot ids only and returned silently on anything else. ATTACK with nothing within 250 studs finished into FOLLOW (a HOLD army ended up following) and the client lit ATTACK optimistically.
- **Fix (one path, server-authoritative):** `Modules/ArmyState` (Idle/Following/Holding/TravellingToBase/Attacking/EngagingTarget/Capturing/Retreating/Recalling/Regrouping; `ArmyState.Set` is the one writer of `st.Order`, cancels the old plan); `Modules/ArmyCommand` (every live owner command validated, every rejection warns `[SERVER ARMY] REJECTED ... reason=`); `Modules/ArmyTargets` (`A:<area>` / `S:<site>` / `B:<plot>` resolved on the server; destination = an approach point outside the objective where a road enters, never his pin / the centre); ArmyPlan Travel + Retreat plans (the block's ONE lead point routes, soldiers keep formation slots); `MapController.OpenForArmySend()` = ArmySend mode (GO reads SEND ARMY and fires `RequestArmySend(target id)`, never pins; normal map still pins); OrdersController highlight = the server's `State` (no optimistic light); the map shows an ARMY marker from `WE_ArmyDest`, separate from his pin.
- **ATTACK decided:** probe the one target pick within SeekRadius 250 of the army (of him while the army is beside him). A target -> Attacking (an auto-clear; started away from him it holds where it ends). None -> "No enemies near", **state unchanged** (FOLLOW stays FOLLOW, a travelling army keeps travelling).
- **Arrival at a zone:** Engaging (defenders within the outpost radius + 60) -> clear for 2 s (or 120 s cap) -> **Holding** at the approach, toast "capture" hint. The army does not capture by itself (capture stays the player's plaza mechanic).
- **Logs:** `[ARMY SEND] / [SERVER ARMY] / [ARMY STATE] / [ARMY DESTINATION] / [ARMY PATH] / [ARMY MOVE]` only with `WE_ArmyDebug` (owner's /armydebug, default on for ArmyConfig DebugUserIds) or Studio; rejections always warn (rate-limited 2 s). Army Orders stay **OwnerFirst**. Rival TARGETS SEND ARMY (JOB 41 C) and revenge SEND still send a plot id -> same validated path.
- **Checks:** BuyPathStatic PASS=7533 FAIL=0; codebot_v162 PASS (runs `tools/sim/run_army_command_test.py`: 33/33); run_army_orders_test / run_army_march_test / run_rival_targets_test 0 failed. Pins superseded: claude_bud_job38.py:74 (schema now `number|string:40`), BuyPathStatic squadfair v3 (reset moved to ArmyState OnChange).
- **PreferMesh stays OFF.** No WE_Building* touch. No fast travel. Commits: `2a0e0b4` (instrumentation), `185524d` + `bf3f47a` (fix), `1bb7929` (v162 + dist); bud merge `9b1af3a`.

**Phone tests for Shaun (owner account):**
1. FOLLOW lit -> ARMY -> SEND -> map says "ARMY SEND"; tap Crossroads Town -> button reads **SEND ARMY** -> press: map closes, **no new PIN**, SEND lights, strip "Marching to Crossroads Town"; stand still: the block walks away to the town's west/east/north/south entrance (whichever is nearest), engages, then HOLDS there.
2. During the march: FOLLOW/RECALL brings it back (Recalling -> Following), HOLD stops it where it is, ATTACK with no enemy near says "No enemies near" and keeps marching.
3. ATTACK beside you with nothing around: "No enemies near", FOLLOW stays lit.
4. /armydebug on -> F9 console shows the [ARMY ...] chain; check the real PathfindingService route into the plaza and the approach-point ground height.
5. 75 soldiers: the column stays together on turns (sim: every soldier within 3.7 studs of its slot), frame rate OK on phone.

## v161 PUBLISHED (Code Bot Roblox, 2026-10-01 09:17 Dublin): Open Cloud place version 159 — JOB 42 A+B owner-first (time cash packs config/grant + Shop/offers)
- **Published** `dist/WarEmpire-PERF.rbxlx` (WE_Build **161**) via `tools/publish-opencloud.sh` -> HTTP 200 `{"versionNumber":159}`. Servers NOT restarted (Migrate to Latest Update / rejoin).
- **Cherry-pick:** Claude `82da83b` JOB 42 A (config+grant) -> `7a486b3`; Claude `8145a91` JOB 42 B (Shop+offers) -> `093c2a8`; then WE_Build 161 + checks + dist (publish commit `75ac966`).
- **Flags left OwnerFirst=true (do NOT flip without Shaun):**
  - `ShopOverhaulConfig.TimePacks` Enabled + OwnerFirst=true; all five `DevProducts` Cash15m/Cash30m/Cash1h/Cash2h/Cash4h **Id = 0** at 25/49/89/159/279 R$. Old packs still shown until TimePacksReady (all five Ids).
  - Still from v158–v160: `TutorialConfig.Guided` OwnerFirst=true; `MonetizationConfig.RecruitPackOffer` OwnerFirst=true (`RecruitPack.Id = 0`); `RivalConfig` OwnerFirst=true; `RatePromptConfig` OwnerFirst=true.
- **PreferMesh stays OFF.** No WE_Building* touch. Servers stay at 10. No fast travel. **No Creator Hub products created in this run.**
- **Checks:** BuyPathStatic PASS=7507 FAIL=0; claude_bud_job42 PASS (A+B); codebot_v161 PASS; run_time_packs_test 0 failed; rojo build deterministic (both dist copies identical).
- **Creator Hub (Code Bot):** create five Developer Products: '15 Minutes of Cash' 25 R$, '30 Minutes of Cash' 49 R$, '1 Hour of Cash' 89 R$, '2 Hours of Cash' 159 R$, '4 Hours of Cash' 279 R$ (description: 'Instantly get cash equal to <N> of your current income.'). Paste the Ids into MonetizationConfig.DevProducts Cash15m / Cash30m / Cash1h / Cash2h / Cash4h. The Shop keeps the old packs until all five Ids are in. Do NOT create a 1-day or 7-day pack.
- **JOB 42 A+B shipped owner-first.** NEXT: JOB 42 C/D if Claude pushes them; else JOB 43 part 1 (army-vs-army brawl). Do NOT flip TimePacks/Guided/RecruitPackOffer/Rival/RatePrompt OwnerFirst; do not create Creator Hub products until Shaun OKs after phone tests.

**Phone tests for Shaun (owner-first — use owner / Studio playtest account):**
1. Owner Shop: five time pack rows (4h → 15m) with **SOON** while Ids are 0; layout readable; **BEST VALUE** on the 4h row. Amounts show floor + "(minimum)" until income passes it.
2. Cash pill **+** scrolls to / highlights the 4h row (Studio preview path with Ids 0).
3. Non-owner (e.g. uid 9) still sees the **old** four cash packs (TimePacks OwnerFirst). PreferMesh OFF.
4. A+B+C+D from JOB 41 still owner-first as v158–v160 (Guided; Recruit Pack Id 0; TARGETS; rate card). Real purchase of time packs needs Creator Hub Ids first.

## claude-bud JOB 42 PART B (2026-10-01): TIME CASH PACKS IN THE SHOP + OFFERS (branch `claude/desktop-bud`)
Only while SHOWN (TimePacksLiveFor AND all five Ids set); otherwise the Shop and offers are exactly today's.
- **Rows:** five rows in the cash place (ShopOverhaulConfig.Order 4h .. 15m), order 4h, 2h, 1h, 30m, 15m.
  - Each shows the config title "4 HOURS OF CASH", the live "$N" (WE_TimePackPerMin; the floor + "(minimum)" until
    income passes it, never $0) and the real price button.
  - "BEST VALUE · " on the 4h row (the 2x Cash row's tag style). The old four rows are hidden; their Ids stay.
  - Studio with the Ids still 0: the rows render with "SOON" so the layout can be checked.
- **The cash pill +:** scrolls to / highlights the 4h row.
- **Offers (same slots, same budget):**
  - the Mega toast sells Cash4h ("4 HOURS OF CASH: $N");
  - the rebirth "Fresh start boost" sells Cash1h;
  - the garage "Short on cash" offers the smallest time pack whose live amount covers the gap, else Cash4h with its
    REAL amount.
- **Checks:**
  - run_shop_render_test now runs 4 builds (docs/proof/job42/shop-render.txt): owner / uid 9, Ids 0 / Ids set. The
    owner with the Ids sees exactly the five rows (titles, amounts, prices, order, BEST VALUE) with the old four hidden;
    uid 9 sees the old rows; the + lands on 4h.
  - run_time_packs_test: the Mega slot sells Cash4h while shown, CashMega otherwise.
  - claude_bud_job42 part B pins; BuyPathStatic PASS=7504 FAIL=0; all sims 0 failed; rojo ok; no new LSP errors.
- **Owed:** the Studio screenshots (shop_800x360.png, shop_desktop.png, shop_newplayer.png). The render harness checks
  rows and phone text budgets; it does not measure pixel overlaps at 5 viewports.

## claude-bud JOB 42 PART A (2026-10-01): TIME CASH PACKS, CONFIG + SERVER GRANT (branch `claude/desktop-bud`)
- **Products:** MonetizationConfig.DevProducts Cash15m / Cash30m / Cash1h / Cash2h / Cash4h at 25 / 49 / 89 / 159 /
  279 R$. All Id 0, repeatable, Cash = the floor. No 1-day / 7-day pack.
- **Config:** ShopOverhaulConfig.TimePacks (Enabled, OwnerFirst = true): Minutes 15 / 30 / 60 / 120 / 240, Floors 10k /
  25k / 50k / 100k / 200k (PROPOSED minimums for new players), BEST VALUE on Cash4h, ExcludeTimedBoosts, HideOldKeys
  (the old four), WE_TimePackPerMin.
- **Helpers:** TimePacksLiveFor, TimePackAmount (guarded, integer, <= 2^53), TimePacksReady (all five Ids), TimePacksShown
  (live AND ready), PerMinBucket.
- **Grant (ProcessReceipt, inside the JOB 36 path):** for ANY time-pack receipt:
  - perMin = PassivePerMin(player, profile, excludeTimed = true). This is the ONE income function with a new option that
    divides out profile.CashBoost and the Double Cash event.
  - Then the player + profile re-check (else NotProcessedYet), then max(Floor, Minutes x perMin) via AddCash
    "devproduct" (exempt).
  - The toast reads "+$N (4 hours of cash)". RobuxPurchase gets perMinBucket (CustomField02; AnalyticsService custom()
    gained an optional Field2).
- **Display:** WE_TimePackPerMin comes from the same ShopOverhaulService tick, only for players it is live for.
- **Pins:** codebot_v156's "no product Id changed since v155" replacement now also leaves out the five new Id-0 rows;
  docs/LIVE_PLACE.md lists them.
- **Checks:** run_time_packs_test 0 failed (docs/proof/job42/amounts-sim.txt, receipt-order.txt, gating-sim.txt);
  claude_bud_job42 part A pins; BuyPathStatic PASS=7499 FAIL=0; all sims 0 failed; rojo ok; no new LSP errors.
## v160 PUBLISHED (Code Bot Roblox, 2026-10-01 09:02 Dublin): Open Cloud place version 158 — JOB 41 part D owner-first (big-win rate card FirstCapture/RaidWin)
- **Published** `dist/WarEmpire-PERF.rbxlx` (WE_Build **160**) via `tools/publish-opencloud.sh` -> HTTP 200 `{"versionNumber":158}`. Servers NOT restarted (Migrate to Latest Update / rejoin).
- **Cherry-pick:** Claude `d383948` JOB 41 D big-win rate card -> `8caa2f3`; then WE_Build 160 + checks + dist (this publish commit `37b94b0`).
- **Flags left OwnerFirst=true (do NOT flip without Shaun):**
  - `RatePromptConfig` Enabled + OwnerFirst=true (same JOB 40 D system; FirstCapture / RaidWin one-time triggers; no second rate system; no reward; Recruit Pack card goes first).
  - Still from v158/v159: `TutorialConfig.Guided` OwnerFirst=true; `MonetizationConfig.RecruitPackOffer` OwnerFirst=true (`DevProducts.RecruitPack.Id = 0`); `RivalConfig` OwnerFirst=true.
- **PreferMesh stays OFF.** No WE_Building* touch. Servers stay at 10. No fast travel. No Creator Hub products created.
- **Checks:** BuyPathStatic PASS=7493 FAIL=0; claude_bud_job41 PASS (A+B+C+D); codebot_v160 PASS; run_rate_prompt_test 0 failed; rojo build deterministic (both dist copies identical).
- **JOB 41 fully shipped owner-first (A+B+C+D).** NEXT queue: JOB 43 part 1 (army-vs-army brawl; Army Kills board already live) then JOB 42 (time-based cash packs). Do NOT flip Guided/RecruitPackOffer/Rival/RatePrompt OwnerFirst; Recruit Pack Id=0 until Shaun OKs 49 R$ + Creator Hub Id.

**Phone tests for Shaun (owner-first — use owner / Studio playtest account):**
1. After first capture OR a raid win that looted (SEND loot or in-person ATM raid): "Enjoying WAR EMPIRE?" shows once (no reward / no like-for-gift). If Recruit Pack card is due from the same capture, pack goes first; rate card waits.
2. Never two cards at once; FirstCapture / RaidWin each once per profile; 3-day gap / combat quiet / once-per-session / Never still apply.
3. A+B+C still owner-first as v158 place 156 / v159 place 157 (Guided chain; Recruit Pack Id 0 does not prompt; TARGETS + SEND ARMY walks). PreferMesh OFF.

## v159 PUBLISHED (Code Bot Roblox, 2026-10-01 08:55 Dublin): Open Cloud place version 157 — JOB 41 part C owner-first (Rival TARGETS + SEND ARMY)
- **Published** `dist/WarEmpire-PERF.rbxlx` (WE_Build **159**) via `tools/publish-opencloud.sh` -> HTTP 200 `{"versionNumber":157}`. Servers NOT restarted (Migrate to Latest Update / rejoin).
- **Cherry-pick:** Claude `aeefda1` JOB 41 C Rival TARGETS -> `4ca755e`; then WE_Build 159 + checks + dist.
- **Flags left OwnerFirst=true (do NOT flip without Shaun):**
  - `RivalConfig` Enabled + OwnerFirst=true (TARGETS pill + list; SEND ARMY = JOB 38 RequestArmySend, army walks; VIEW = map card, no travel).
  - Still from v158: `TutorialConfig.Guided` OwnerFirst=true; `MonetizationConfig.RecruitPackOffer` OwnerFirst=true; `DevProducts.RecruitPack.Id = 0`.
- **PreferMesh stays OFF.** No WE_Building* touch. Servers stay at 10. No fast travel.
- **Checks:** BuyPathStatic PASS=7487 FAIL=0; claude_bud_job41 PASS (A+B+C); codebot_v159 PASS; run_rival_targets_test 0 failed; rojo build deterministic (both dist copies identical).

**Phone tests for Shaun (owner-first — use owner / Studio playtest account; need another player online, not clan, past new-player protection, with ATM cash):**
1. TARGETS pill top-right with a count; tap → name, army size, loot bucket ($1k+ / $10k+ / …), verdict chip.
2. SEND ARMY: army walks to their base and raids (no teleport). VIEW opens the map card on that base (tap-to-pin only).
3. Shielded / new / protected / ally players never appear in the list.
4. A+B still owner-first as v158 (Guided chain + Recruit Pack Id 0 does not prompt). PreferMesh OFF.

## claude-bud JOB 42 PART A (2026-10-01): TIME CASH PACKS, CONFIG + SERVER GRANT (branch `claude/desktop-bud`)
- **Products:** MonetizationConfig.DevProducts Cash15m / Cash30m / Cash1h / Cash2h / Cash4h at 25 / 49 / 89 / 159 /
  279 R$. All Id 0, repeatable, Cash = the floor. No 1-day / 7-day pack.
- **Config:** ShopOverhaulConfig.TimePacks (Enabled, OwnerFirst = true): Minutes 15 / 30 / 60 / 120 / 240, Floors 10k /
  25k / 50k / 100k / 200k (PROPOSED minimums for new players), BEST VALUE on Cash4h, ExcludeTimedBoosts, HideOldKeys
  (the old four), WE_TimePackPerMin.
- **Helpers:** TimePacksLiveFor, TimePackAmount (guarded, integer, <= 2^53), TimePacksReady (all five Ids), TimePacksShown
  (live AND ready), PerMinBucket.
- **Grant (ProcessReceipt, inside the JOB 36 path):** for ANY time-pack receipt:
  - perMin = PassivePerMin(player, profile, excludeTimed = true). This is the ONE income function with a new option that
    divides out profile.CashBoost and the Double Cash event.
  - Then the player + profile re-check (else NotProcessedYet), then max(Floor, Minutes x perMin) via AddCash
    "devproduct" (exempt).
  - The toast reads "+$N (4 hours of cash)". RobuxPurchase gets perMinBucket (CustomField02; AnalyticsService custom()
    gained an optional Field2).
- **Display:** WE_TimePackPerMin comes from the same ShopOverhaulService tick, only for players it is live for.
- **Pins:** codebot_v156's "no product Id changed since v155" replacement now also leaves out the five new Id-0 rows;
  docs/LIVE_PLACE.md lists them.
- **Checks:** run_time_packs_test 0 failed (docs/proof/job42/amounts-sim.txt, receipt-order.txt, gating-sim.txt);
  claude_bud_job42 part A pins; BuyPathStatic PASS=7499 FAIL=0; all sims 0 failed; rojo ok; no new LSP errors.

## claude-bud JOB 41 (2026-10-01): SUMMARY (parts A-D pushed; the details are in the part sections below)
**Flags to launch (each owner-first, OFF = today):** `TutorialConfig.Guided`, `MonetizationConfig.RecruitPackOffer`
(after the product exists), `RivalConfig`, `RatePromptConfig` (JOB 40 D + the JOB 41 D triggers).

**Root cause (owed):** the Creator Hub funnel numbers (docs/proof/job41/funnel-before.md has the query). The code fact:
today's Home Outpost step has no enemies (OutpostDefenders skips starter rows).

**Step times (sim, derived pace):** first BUILD 8 s, collect 31, recruit 45, camp cleared 64, captured 76, Reward 79,
Barracks 112. That is FASTER than the brief's 3-4 min (reported, not padded).

**Creator Hub note (B5):** Creator Hub: create the Developer Product 'Recruit Pack' at 49 R$ ONLY after Shaun OKs the
price; then paste its Id into MonetizationConfig.DevProducts.RecruitPack.Id (Code Bot). Until then Id = 0 and the offer
never prompts.

**Dashboards:** Analytics > Funnels > FirstMinutes; Analytics > Custom events > GuidedStepSeconds / GuidedSkipped /
GuidedStuck / RecruitPackOffered / RivalListOpened / RivalSendTapped / RivalRaidWon / rate_prompt_shown /
rate_prompt_answer.

**Phone tests (not device-verified until Shaun tests):**
1. With a fresh test account: BUILD the Command Center in the first ~20 s, see the payout and the base grow, collect,
   recruit, fight the 2 camp soldiers at the Home Outpost (they shoot back), capture it, and see "BASE SECURED!" with
   confetti, with the yellow line on every step.
2. With the owner account (returning): no guided chain. Skip works on the test account at any step.
3. The Recruit Pack card appears only at the first capture (or at 10 min), once. The Shop shows it; the price button
   reads 49 R$ (Id 0: no prompt until Creator Hub).
4. TARGETS shows a rival with his name, army size and loot; SEND ARMY walks the army there; a shielded player is not
   listed.
5. After the first capture or a raid win, "Enjoying WAR EMPIRE?" shows once (after the Recruit Pack card), with no
   reward.

## claude-bud JOB 41 PART D (2026-10-01): THE BIG-WIN RATE CARD (ONE system with JOB 40 D, NO reward)
- **New triggers:** RatePromptConfig.Triggers FirstCapture (TerritoryService: the Guided reward capture or any first
  territory) and RaidWin (ArmyPlan: a SEND that looted; MoneyCollectorService._RaidDone: an in-person ATM raid with
  loot).
  - Each is one-time per profile: RatePrompt.Triggered[<name>] is set when the card SHOWED for it (saved;
    ProfileSchema repairs it).
  - Each shows the card early once. Every JOB 40 rule still holds: the 3-day gap, combat quiet, once per session,
    Never, the hold.
- **Never two cards:** while the Recruit Pack card is out or closed < 20 s ago (RecruitPackService.CardBlocks), the rate
  card waits.
  - If the pack is still due from the same capture (RecruitPackService.Pending), the pack goes first; the rate card
    waits at most 180 s, then may show or slip to the next win / the 15-min rule.
- **No reward, no "like for ...":** nothing checks a like. The only events are still rate_prompt_shown / answer.
- **Checks:** run_rate_prompt_test 0 failed (now 44 checks; docs/proof/job41/rate-prompt-sim.txt); claude_bud_job41
  part D pins; BuyPathStatic PASS=7490 FAIL=0; all sims 0 failed; rojo ok; remote audit OK; no new LSP errors.

## claude-bud JOB 41 PART C (2026-10-01): RIVAL TARGETS + SEND ARMY (branch `claude/desktop-bud`)
**Flag:** `RivalConfig` (`Enabled`, `OwnerFirst = true`; a new config, not an ArmyOrdersConfig block). OFF / not live =
no pill and no push; the map SEND ARMY is unchanged. **To launch:** `OwnerFirst = false`. Servers stay at 10 players
(no change, no Creator Hub note).

**Server (Services/RivalService):** ONE shared 10 s tick.
- For each live viewer, the other occupied bases whose JOB 38 SEND verdict is Ok right now (ArmyPlan.CheckSend =
  ArmySendRules on the same facts; no second rule). Shielded / ally / new player / novice / protected / too strong /
  cooldown / one active SEND / no soldiers are simply not listed.
- The loot estimate = GetRaidableBalance x LootFraction(StealFraction, bully). It is sent as a BUCKET only
  ($1k+ / $10k+ / $100k+ / $1M+), never the number.
- Sorted by loot then distance; the top 3. Nothing during the Guided / onboarding hold.

**Client (Controllers/RivalController):**
- A "TARGETS" pill with a count badge, top-right under the top-bar pills. It shows only while >= 1 target is listed.
  The Army button is a left-rail tile in the thumbstick band, so the pill is not next to it (ASSUMPTIONS).
- The list (one panel at a time): name · Army 12 · Loot $10k+ + the verdict chip (easy / even / risky).
  - SEND ARMY = the same JOB 38 RequestArmySend remote as the map (the server re-checks; the army walks).
  - VIEW = MapController.OpenBase (the map on that base card; tap-to-pin, no travel).

**Telemetry:** RivalListOpened, RivalSendTapped { verdict }, RivalRaidWon (a SEND from the list that looted; ArmyPlan
calls RivalService.OnRaidWon). **PvP rate = RivalSendTapped per session** (Analytics > Custom events).

**Checks:** run_rival_targets_test 0 failed (docs/proof/job41/rivals-sim.txt): the 8-case table against the real
ArmySendRules, sort, cap, buckets, one tick, hold, telemetry, the same SEND remote. claude_bud_job41 part C pins;
BuyPathStatic PASS=7484 FAIL=0; all sims 0 failed; rojo ok; remote audit OK; no new LSP errors.

**Owed:** the 2-player Studio test (docs/proof/job41/rivals.md): B sees A in TARGETS, SEND ARMY walks and raids; a
shielded A is gone from B's list.

**Test ON HIS PHONE:** with another player online (not your clan, past the new-player protection, with cash in their
ATM):
1. TARGETS appears top-right with a count; tap it and their name, army size and a loot bucket show.
2. SEND ARMY: your army walks there (no teleport) and raids.
3. A shielded / new player is never listed.

## v158 PUBLISHED (Code Bot Roblox, 2026-10-01 08:48 Dublin): Open Cloud place version 156 — JOB 41 A+B owner-first (Guided first minutes + Recruit Pack Id 0)
- **Published** `dist/WarEmpire-PERF.rbxlx` (WE_Build **158**) via `tools/publish-opencloud.sh` -> HTTP 200 `{"versionNumber":156}`. Servers NOT restarted (Migrate to Latest Update / rejoin).
- **Cherry-picks:** Claude `a1c927b` JOB 41 A Guided -> `c5dda45`; Claude `22f81e3` JOB 41 B Recruit Pack -> `b11d8c5`; then `094c816` WE_Build 158 + checks + dist.
- **Flags left OwnerFirst=true (do NOT flip without Shaun):**
  - `TutorialConfig.Guided` Enabled + OwnerFirst=true (OrderVersion 4 guided chain + GuidedService training camp).
  - `MonetizationConfig.RecruitPackOffer` Enabled + OwnerFirst=true; `DevProducts.RecruitPack.Id = 0` (no Creator Hub product yet; 49 R$ proposed).
- **PreferMesh stays OFF.** No WE_Building* touch. No Creator Hub products created.
- **Checks:** BuyPathStatic PASS=7481 FAIL=0; claude_bud_job41 PASS; codebot_v158 PASS; rojo build deterministic (both dist copies identical).
- **JOB 41 part C** cherry-picked onto polish (this commit); publish as WE_Build 159 next. **Still owed by Claude:** JOB 41 part D (rate-prompt big-win link). Then JOB 43 part 1 then JOB 42.

**Phone tests for Shaun (owner-first — use owner / Studio playtest account; Recruit Pack will not prompt until Id is set):**
1. Fresh test account: BUILD Command Center in ~20 s + payout; collect; recruit; fight 2 camp Recruits at Home Outpost (they shoot back); capture; "BASE SECURED!" confetti + $2,500; Barracks goal. Skip works. Returning owner account: no guided chain.
2. Recruit Pack: with Id 0 the card must NOT prompt a purchase. After Creator Hub Id is pasted and OwnerFirst flipped: card once at first capture or ~10 min play; buy grants income-scaled cash + 2x boost + gold RECRUIT trim; no second offer; Shop shows OWNED.
3. PreferMesh OFF / no building kit change expected.

## claude-bud JOB 41 PART B (2026-10-01): RECRUIT PACK, 49 R$ PROPOSED, ID 0 (branch `claude/desktop-bud`)
**Flag:** `MonetizationConfig.RecruitPackOffer` (`Enabled`, `OwnerFirst = true`). **To launch:** Code Bot sets
`OwnerFirst = false` after the product exists.

**The product:** `MonetizationConfig.DevProducts.RecruitPack` = Id 0, 49 R$, one time. It gives:
- **Cash** = 30 min of his income, clamped $25,000..$150,000 (always >= 2.5x the 49 R$ Cash Pack S), computed in
  ProcessReceipt at purchase time;
- **a 2x cash boost for 30 min** through CodesService.GrantCashBoost (the one boost path; the WE_CashBoostUntil HUD
  timer shows it);
- **a gold "RECRUIT" trim** on his base sign ("RECRUIT ·" + a thicker gold stroke) and his base owner marker (a gold
  stroke). It is the entitlement WE_Ent_RecruitPack, with no stat.
- **Not pay-to-win:** no damage / HP / armour / army / raid / protection key (pinned).

**When (Services/RecruitPackService, server):**
- Once per profile (RecruitPackOffered, marked when the client confirms the card SHOWED), at the FIRST of: his first
  capture (TerritoryService awardCapture -> OnCapture), or 600 s of total play (profile.Stats.PlayTimeSeconds, which is
  now counted; it was never incremented before).
- Never: with Id 0, owned, during the Guided / onboarding hold, within 20 s of damage taken, seated, or while the card
  is out.
- It goes through ClaimSoftOfferSlot (the existing budget, incl. the v153 120 s quiet window). A busy slot or a
  "dropped" card retries 30 s later; a dropped card refunds the slot, like the Starter Pack.

**The old Starter pop-up:** for players it is live for, TrySoftOfferStarterBundle and ScheduleFirstOffer (and its
Speed Boost fallback) do NOT fire. The StarterBundle row stays in the Shop. Proof: run_recruit_pack_test "live: the old
pop-up does NOT fire / not live: fires as before".

**Card (Controllers/RecruitPackController):** top-right, 300 px, "Recruit Pack" + "$<N> Cash" (his real number) /
"2x Cash for 30 min" / "Gold base trim", the price button (the server's live price), "Maybe later", X. It hides after
20 s; no timer and no "only today".

**Shop:** the row sits on top (ShopOverhaulConfig.Order) once its Id is set (Id 0 rows are not listed).

**Telemetry:** the existing ProductPrompted / PromptCancelled / RobuxPurchase (productKey RecruitPack, source
recruit_offer) + RecruitPackOffered { trigger }; the FirstMinutes funnel steps 10 Offered / 11 Bought.

**Creator Hub (required note):** Creator Hub: create the Developer Product 'Recruit Pack' at 49 R$ ONLY after Shaun OKs
the price; then paste its Id into MonetizationConfig.DevProducts.RecruitPack.Id (Code Bot). Until then Id = 0 and the
offer never prompts.

**Pins / checks:**
- codebot_v156's "no product Id changed since v155" is retired + replaced (the new RecruitPack row aside).
- docs/LIVE_PLACE.md has the RecruitPack row.
- run_recruit_pack_test 0 failed (docs/proof/job41/recruit-pack-sim.txt); claude_bud_job41 part B pins.
- BuyPathStatic PASS=7478 FAIL=0; all sims 0 failed; rojo ok; remote audit OK; no new LSP errors (one pre-existing
  LocalShadow moved lines).

**Test ON HIS PHONE** (after the Id is set):
1. The Recruit Pack card appears once: at your first capture or after 10 min of play, never mid-fight. The price button
   reads 49 R$.
2. Buy it: the cash lands (the amount on the card), the 2x boost timer shows, and your base sign / marker get the gold
   trim.
3. Rejoin: no card again; the Shop shows it OWNED at the top.

## claude-bud JOB 41 PART A (2026-10-01): THE GUIDED FIRST MINUTES (branch `claude/desktop-bud`)
**Flag:** `TutorialConfig.Guided` (`Enabled`, `OwnerFirst = true`, through RetentionConfig.Live). OFF / not live =
today's OrderVersion 3, no camp, no new banner, no new events. **To launch:** Code Bot sets `OwnerFirst = false`.

**Who gets it:** only a NEW player: tutorial not done, no building, first join < 900 s ago. He is stamped
OrderVersion 4. A Guided save migrates back to 3 like any other order if the switch goes off.

**The chain (OrderVersion 4, TutorialConfig.GuidedSteps):** Command Center -> Collect -> Recruit -> **Clear the camp**
-> Capture outpost -> **Base secured!** -> Barracks -> 4x4.
- The first win: FastStart's BUILD + the $1,500 payout, unchanged.
- Recruit: a one-time top-up covers exactly the gap to 3 soldiers. It is $0 with today's numbers: $10,000 + $1,500 -
  $1,500 = $10,000 >= 3 x $500.
- FIRST FIGHT (Services/GuidedService):
  - 2 "Recruit" NPCs (a new weak CombatConfig type: 40 HP, 4 dmg, 1.2 shots/s, hit chance capped 0.35 / 0.2) at HIS
    Home Outpost, spawned through CombatService.SpawnNPC (NoRespawn, leashed to the ring, a TargetFilter so they only
    shoot him), with 2 sandbag parts.
  - Real shots both ways (the normal NPC brain). Capture of his Home Outpost is blocked while one lives
    (TerritoryService guidedBlocking, starter rows only).
  - The first ATTACK hint shows here. The "ENEMY CAMP" objective marker sits on his outpost.
  - A death or a rejoin brings the camp back at full health, at most 3 times; then the step completes with a friendly
    line (never a soft-lock).
- REWARD: $2,500 once (reason "onboarding"), "BASE SECURED!" banner + confetti (the Juice Rebirth path, JuiceConfig
  .Guided) + the coin burst. Then the Barracks goal with the gold line.
- The WE_Onboarding hold now lasts until the Reward (max 300 s) for Guided profiles: no streak card, nation picker,
  promo, rate card or offer during the chain.
- Skip: works at every step; it clears the camp at once and logs GuidedSkipped { step }.

**Funnel (Creator Hub):**
- A SEPARATE funnel, **Analytics > Funnels > FirstMinutes** (LogFunnelStepEvent, one session per profile): 1 Spawned,
  2 FirstBuild, 3 Collected, 4 Recruited, 5 FightStarted, 6 FirstKill, 7 Captured, 8 Reward, 9 NextBuilding.
- **Analytics > Custom events > GuidedStepSeconds** (Field step), plus GuidedSkipped and GuidedStuck (> 90 s on a step).
- The old Onboarding funnel is untouched. Studio prints `[FUNNEL] FirstMinutes ...` lines.

**Root cause input (owed):** docs/proof/job41/funnel-before.md has the Creator Hub query + an empty table. I cannot
open Creator Hub; please paste the numbers.

**Findings (reported, not hidden):**
- **Faster than the target:** the sim's pace is derived from the real layout (console -> ATM -> Home Outpost walks,
  banner reading, one passive tick, the capture time). It reaches the Reward in **~79 s**, much FASTER than the
  brief's 3-4 min estimate.
- **The fight is very short:** with the brief's Recruit numbers the modelled camp dies in a median ~2 s (StarterRifle
  18 x 8/s). A real new phone player misses more. If it feels like no fight, raise
  `CombatConfig.NPCTypes.Recruit.Health`.
- **Other players:** they cannot be TARGETED by the camp, but they can still see it and shoot it (server NPCs are
  shared).

**Checks:**
- run_first_minutes_test 0 failed (docs/proof/job41/funnel-sim.txt); claude_bud_job41 part A pins.
- The BPS F6 "active step" pin is retired and replaced (per-profile step list).
- BuyPathStatic PASS=7298 FAIL=0; all sims 0 failed; rojo ok; remote audit OK; no new LSP errors (LSP caught a wrong
  require path in TerritoryService, fixed).

**Owed:** the Studio fresh-profile run with screenshots, and the HUD harness with the camp marker.

**Test ON HIS PHONE** (a fresh test account; the owner account is not a new player):
1. Join: BUILD the Command Center in the first ~20 s and see the payout. Then collect at the ATM and recruit.
2. Follow the line to "ENEMY CAMP" at your Home Outpost: 2 enemies shoot back, and you and your soldiers kill them.
3. Capture the outpost: "BASE SECURED!" with confetti and +$2,500, then the Barracks goal shows.
4. Skip at any step works. With the owner account (returning) there is no guided chain.

## v157 PUBLISHED (Code Bot Roblox, 2026-10-01 00:45 Dublin): Open Cloud place version 155 — the weekly Black Market live for everyone
- **Published** `dist/WarEmpire-PERF.rbxlx` (WE_Build **157**) via `tools/publish-opencloud.sh` -> HTTP 200 `{"versionNumber":155}`. Servers NOT restarted (Migrate to Latest Update / rejoin).
- **Commits:** phase-7-polish `867befd` (source, checks, dist); claude/desktop-bud merge `7fd3d8a` (temp worktree); this handoff.
- **Gate:** new `EndgameConfig.PublicParts = { BlackMarket = true }`. `LiveFor(uid, part)` = Parts[part] AND (public part + Live.Enabled, OR the owner-first rule). `Live.OwnerFirst` stays **true**: every other Endgame part (Empire, Rebirth scale, Tier, Defence, Elite, Hospital, Mastery/Armory, Workshop, Warheads, Heist, Contracts/Intel, RewardScaling) is still owner-only. Kill switch: Parts.BlackMarket=false or Live.Enabled=false = off for everyone. `AnyLiveFor` now asks LiveFor per part, so every player gets WE_EndgameLive, the EMPIRE button (lists only the Black Market + PIN) and the stall.
- **Camo apply path:** `EndgameConfig.CamoLiveFor` = Mastery OR BlackMarket. CamoFor / EquipCamo work without the Armory, but only for the Black Market camos (Urban, Tiger, Gold); buying at the Armory stays Mastery-only. A bought market camo goes on the owned gun in your hand; the Black Market list has PUT ON / TAKE OFF rows for it.
- **Banners:** bought banners now show on the gate posts below Tier 4 (`MarketBanners`, 4 parts); SyncBaseTier builds the look for a banner alone. Berets (soldiers) and paint (vehicles) already needed no other part. Trophy cannon works at tier 0 (unchanged).
- **Stall:** SW_S1 (navy-awning market building, south-west row of the plaza) upper floor; the stall adds its own BLACK MARKET door sign while the Armory downstairs is not live for you (24 parts).
- **Checks:** BuyPathStatic PASS=7460 FAIL=0; codebot_v157 (41 pins) PASS; new `tools/sim/run_blackmarket_public_test.py` 0 failed (non-owner: Black Market only, all 18 other purchase kinds refused, Cash via SpendCash, Gold via SpendGold, camo/beret/banner apply); run_endgame_test 0 failed (station sign count accounts for the v157 sign).

## v156 PUBLISHED (Code Bot Roblox, 2026-10-01 00:29 Dublin): Open Cloud place version 154 — real Robux prices + plain Shop text + ARMY KILLS board, live for everyone
- **Published** `dist/WarEmpire-PERF.rbxlx` (WE_Build **156**) via `tools/publish-opencloud.sh` -> HTTP 200 `{"versionNumber":154}`. Servers NOT restarted (Migrate to Latest Update / rejoin).
- **Commits:** phase-7-polish `e289e76` (source, checks and dist); claude/desktop-bud merge `3beaae7`; this handoff.
- **Prices:** new `Shared/Util/LivePrices` (server GetProductInfo cache -> RS attributes `WE_Px_*` / `WE_PxN_*`, refresh 10 min). The Shop, Supply Depot, stands and every offer card (including the ~2 min Starter offer) show the Roblox price and name; the config is the fallback only. Mismatches found (config vs Roblox): StarterBundle 149 "Commander Starter Pack" vs **249 "Commander Starter Bundle"**; ExtraSoldierSlot 99 "Army Expansion (+10)" vs **79 "Extra Soldier Slot"**. Fallbacks now match Roblox. No Creator Hub price changed. All game passes matched.
- **Owner action (Creator Hub text, stale):** Starter Bundle description says "25,000 cash + 25 gold" (game grants $50,000 + Auto Collect); Extra Soldier Slot says "+1 soldier capacity" (game grants +10).
- **Descriptions:** every Robux item rewritten in plain player language (no "ProcessReceipt only"), max 56 characters per row sub (render test at 1024x471).
- **ARMY KILLS:** `LeaderboardConfig.ArmyKillsBoardLive = true` swaps TOP ARMY for ARMY KILLS for everyone (was gated on ArmyOrdersConfig.LiveForAll, and NoteArmyKill on AOC.LiveFor = owner only, who is excluded, so it never scored). ArmyOrders OwnerFirst stays true. Normal follow/defend army kills count (guards, base/tower guards, enemy players). Army-vs-army kills are not possible yet: **JOB 43 part 2 (the board) is DONE by v156; JOB 43 part 1 (army-vs-army brawl) still open.** Boards start empty.
- **Flags unchanged:** Endgame, ArmyOrders, GuardConfig.Posts, SpeedV2 OwnerFirst=true; BaseMarker false.
- **Checks:** BuyPathStatic PASS=7419 FAIL=0; codebot_v156 PASS; run_shop_render_test 0 failed (both uids); run_armory_test 0 failed.
- **Phone tests:** open SUPPLY · R$: "Commander Starter Bundle 249 R$" matches the Roblox prompt; Battle Pass Premium row reads "Unlock premium rewards on every Battle Pass tier"; plaza board says ARMY KILLS.

## v155 PUBLISHED (Code Bot Roblox, 2026-10-01 00:12 Dublin): Open Cloud place version 153 — JOB 40E base owner name tags live for everyone
- **Published** `dist/WarEmpire-PERF.rbxlx` (WE_Build **155**) via `tools/publish-opencloud.sh` -> HTTP 200 `{"versionNumber":153}`. Servers NOT restarted (Migrate to Latest Update / rejoin).
- **Flag:** `BaseMarkerConfig.Live.OwnerFirst = false` (everyone). Endgame, ArmyOrders, GuardConfig.Posts, SpeedV2 and StorePropsConfig OwnerFirst remain true.
- **Build pins:** BaseService, DataService (attribute + profile log), and EarlyRemotes all report WE_Build=155.
- **Checks:** BuyPathStatic PASS=7352 FAIL=0; codebot_v155 passes; rojo build completed and the two dist artifacts were copied identically.
- **Commits:** phase-7-polish `635aef7` (source, checks and dist); claude/desktop-bud merge `440bbd9`.
- **Queue NEXT:** JOB 41 then JOB 42. Do not restart servers.

## v154 PUBLISHED (Code Bot Roblox, 2026-09-30 23:47 Dublin): Open Cloud place version 152 — JOB 40E FIX slim high base-owner tags (owner-first)
- **Published** `dist/WarEmpire-PERF.rbxlx` (WE_Build **154**) via `tools/publish-opencloud.sh` -> HTTP 200 `{"versionNumber":152}`. Servers NOT restarted (Migrate to Latest Update / rejoin).
- **Cherry-pick only** (not a bud-branch merge): `0f210ab` JOB 40E fix -> `d071c03` on phase-7. Kept phase-7 v153 sales-fix / WE_Build work intact.
- **Commits (phase-7-polish):** `d071c03` cherry-pick, `cb6cc3f` WE_Build 154 + `tools/checks/codebot_v154.py`, `69c650b` dist rebuild; this handoff.
- **What ships (OwnerFirst kept true — do NOT flip without owner ask):**
  - **High in the sky:** `HeightAt(dist)` = 150 studs + 6% of viewer distance (cap 260). Far tags sit above the horizon, not across the bases / army.
  - **Slim text-sized pill:** 24 px tall, 14 px name, names cut at 96 px; flag + short name; `@handle` / short `R<n>` only inside 300 studs. No rebirth title ("VETERAN" gone).
  - **Scale 1.0 far .. 1.2 near** (clamped). Fade in 60-90 studs (v123 sign takes over at the gate), fade out 1,800-2,400 studs.
  - **Max 5 rival tags** (nearest) + own "YOU". Overlapping screen boxes: farther tag hides.
  - **Never empty / grey:** `ShowOpenBases = false`; `HasTag` requires a live owner and a name.
- **Flag:** `BaseMarkerConfig.Live` Enabled + **OwnerFirst = true** (unchanged). SpeedV2 / Guards / Endgame / RatePrompt / JOB40 props OwnerFirst stay true. PreferMesh OFF; WE_Building* untouched; VIP 199; fast travel removed.
- **Checks:** BuyPathStatic PASS=7311 FAIL=0; codebot_v154 PASS; run_base_marker_test 0 failed; claude_bud_job40 part E PASS; rojo deterministic (2 builds identical).
- **Owed (§11):** before / after phone-size screenshots (1024x471, plaza looking out + a base road at night) still need Studio / a device.
- **Queue NEXT:** JOB 41 (first-minutes retention) then JOB 42 (time-based cash packs). JOB 40E-FIX is done by this ship — do not redo. v153 sales fixes (first offer ~2 min, Starter shown-ack, analytics productKey) stay live for everyone.
- **Phone tests (Migrate to Latest Update, as shaunie6):**
  1. From the plaza, look out: tags are small pills high in the sky, not across the bases or the army.
  2. No grey or empty tags anywhere; at most 5 rival tags at once and none on top of each other.
  3. Walk up to a rival base: its tag grows a little and shows @handle / R<n>. At your own gate "YOU" fades out and your base sign shows.

## v153 PUBLISHED (Code Bot Roblox, 2026-09-30 23:39 Dublin): Open Cloud place version 151 — SALES FIXES, live for EVERYONE (Shaun approved: "ship the sales fixes and move JOB 41 to the front")
- **Why:** ~1,100 ad visits, 0 sales, 2.8-minute sessions, almost nobody saw an offer.
- **Published** `dist/WarEmpire-PERF.rbxlx` (WE_Build **153**) via `tools/publish-opencloud.sh` -> HTTP 200 `{"versionNumber":151}`. Servers NOT restarted (Migrate to Latest Update / rejoin).
- **Commits (phase-7-polish):** `65e0921` queue docs (JOB 40E-FIX + JOB 41 to the front), `ac9b77d` code + WE_Build 153 + `tools/checks/codebot_v153.py` + `tools/sim/run_first_offer_test.py`, `bf9cc8d` dist rebuild; this handoff. Bud merge `e7335e4`.
- **Root causes (proven in `tools/sim/run_first_offer_test.py`, scenario OLD, on the real MonetizationService):**
  1. *Timing:* `ClaimSoftOfferSlot` refused every soft offer until `TutorialComplete` (or `SoftOfferQuietMaxSeconds` 900 s), and `TutorialService` only scheduled the Starter Pack after the 7-step tutorial. With 2.8-minute sessions almost nobody reached it. The client added `FirstAfterJoinSeconds` 90 and held offers while the tutorial card was up.
  2. *Starter Pack lost for good:* `TrySoftOfferStarterBundle` set `profile.StarterBundleOffered = true` (saved) the moment it FIRED the remote. It fired 3 s after the tutorial, usually in the 4x4 (the last step), and the client held it (Driving) and dropped it after `DropAfterQueuedSeconds` 60 with no reply to the server. The saved flag then blocked it forever.
  3. *Analytics:* `AnalyticsConfig.Roblox.Custom.SHOP_PROMPT` reads `Field = "productKey"` but `MonetizationService` logged `{ key = ... }`, so the custom ProductPrompted field was always empty. `PASS_OWNED` had no custom mapping.
- **Changes:**
  1. `MonetizationConfig.FirstOffer` (Enabled, AtPlaySeconds 120, SeatedWaitSeconds 30, AckTimeoutSeconds 100, RequeueSeconds 45, MaxSendsPerSession 4, FallbackKeys { "SpeedBoost" }). Quiet window = the first 120 s of the session whatever the tutorial state. `MonetizationService.ScheduleFirstOffer` (TutorialService calls it at load for every player and at the tutorial end): the Starter Pack at ~120 s; when the pack is not wanted (owned / window over / already shown), the 99 R$ Speed Boost once. Client: a First offer is not held for the tutorial card or a drawn gun and skips the 90 s join wait; it still waits out active combat (RecentCombat), a modal, death, an alert and driving. The D8 budget (240 s apart, 3 a session, both server and client) is unchanged.
  2. `Server/Modules/OfferLedger` + the (already created, unused) `OfferResult` remote (RemoteGate schema `{ "string:32", "string:12", "number?" }`, rate 2/s). The Starter payload carries `AckId`; ShopController answers "shown" (NotificationController `OnShown`, when the pill is really visible), "dropped" (expired / throttled / evicted) or "refused". Only "shown" sets `StarterBundleOffered`. A drop / refusal / no answer in 100 s refunds the soft-offer slot and re-queues 45 s later (max 4 sends a session; after that it waits for the next session, still unmarked).
  3. SHOP_PROMPT (DevProduct and GamePass) now also sends `productKey`; PASS_OWNED sends `productKey`; new custom events `PassBought` (value = price), `OfferShown`, `OfferDropped`.
- **Unchanged:** every price, pass, product and Id; owner-first flags (BaseMarker, SpeedV2, Endgame, Guards, RatePrompt, JOB40 props); premium stays sidegrade; owner accounts still cannot buy their own passes.
- **Checks:** BuyPathStatic PASS=7314 FAIL=0 (bud merge 7315 / 0); codebot_v153 PASS; run_first_offer_test 0 failed (OLD proof + 7 scenarios); run_shop_test, remotegate_test, remote_audit, run_speed_test OK; rojo ok.
- **Owed:** no Studio on the Code Bot box, so no in-engine screenshot of the offer pill with the tutorial card (TopStack stacks Objective 72 v -> Toasts -> Offer 56 v; ~210 px of 471 at 1024x471, clear of the side rails and the bottom-right buttons, by layout maths).
- **Queue:** CLAUDE.md + docs/claude-queue on both branches: JOB 40E-FIX (new, `docs/claude-queue/JOB40E-FIX-base-tags.md`) right after Claude's current job, then JOB 41 at the front, then JOB 42; note that JOB 41 must not redo the v153 work. Claude's `0f210ab` (JOB 40E fix, owner-first) is on desktop-bud and NOT in v153.
- **How Shaun checks (a NEW account, e.g. Ami's, Migrate to Latest Update first):** join, do NOT finish the tutorial; at ~2:00 the gold "Jumpstart your base" Commander Starter Pack pill shows (even with the tutorial card up). Start shooting before 2:00: it waits until a few seconds after the fight. Get in the 4x4 at ~1:50 and keep driving: nothing while driving; after you get out it comes back (within ~45 s of the drop). Creator Hub > Analytics > Custom events: OfferShown / OfferDropped / ProductPrompted (field = the product key) / PassBought.
## v152 PUBLISHED (Code Bot Roblox, 2026-09-30 23:21 Dublin): Open Cloud place version 150 — JOB 40C market stalls (owner-first) + JOB 40D rate reminder (owner-first)
- **Published** `dist/WarEmpire-PERF.rbxlx` (WE_Build **152**) via `tools/publish-opencloud.sh` -> HTTP 200 `{"versionNumber":150}`. Servers NOT restarted (Migrate to Latest Update / rejoin).
- **Cherry-pick only:** `57201e8` JOB 40 part D -> `2205590` (RatePromptConfig Enabled + OwnerFirst=true).
- **Commits (phase-7-polish):** `b2ae749` WE_Build 152 + `tools/checks/codebot_v152.py` + stall rows + re-probe docs, `5fd8d2c` dist rebuild; this handoff. Bud merge `8354bce`.
- **JOB 40C re-probe** (after the owner's Get Model; `docs/job40c-probe2-2026-09-30.txt`, table in `docs/PROP-ASSETS.md`): 18 of 19 load (10140810871 still not authorized; rejected anyway, a real airport's group). **1 passes: 86311252190175 Market stall** (1 textured MeshPart, mesh + texture by its creator IAmASwedishMale, no scripts). Every radar / tower / bunker failed: over 40 parts, a block build, third-party meshes / textures, or (12735882090) an M60 gun + 22 scripts.
- **Wired:** 2 ReplaceRows: the stall (Scale 5, 8.2 x 10 x 5.1 studs) replaces the Part stalls NW_Stall_1 / NW_Stall_2 in the Crossroads Town market lane. Dry run on the live place (`tools/probes/job40c_stall_dryrun.luau`): 7 kit parts hidden each, bottom = kit base, 0 overlaps, same facing. BaseRows stay EMPTY; Radar Hill dome unchanged.
- **Owner-first:** `StorePropsConfig.JOB40` OwnerFirst=true. Once the owner is in a server, the two stalls change for everyone in that server (ReplaceRows are shared world). v152 fix: the swap now waits for the owner (0.2 Hz, once), so it also happens if he joins after someone else.
- **§11 screenshots NOT taken:** no Studio on the Code Bot box and Open Cloud Luau cannot render. Owed (Studio or the phone).
- **Checks:** BuyPathStatic PASS=7287 FAIL=0; codebot_v152 PASS; run_rate_prompt_test 0 failed; rojo deterministic.
- **Live state kept:** GuardConfig.Posts, SpeedV2, Endgame, BaseMarker, ArmyOrders, RatePrompt OwnerFirst=true; ShopOverhaul + CheckpointGuard OwnerFirst=false; STORE-PROPS world rows launched; VIP 199; PreferMesh OFF; WE_Building* untouched.
- **Phone tests (Migrate to Latest Update, as shaunie6):**
  1. Crossroads Town, NW market lane (north-west of the plaza, near the water tower): the two front stalls are now blue/red awning stalls with fruit baskets, standing on the paving, not floating or sunk, fronts facing the lane; the two stalls behind them stay as before.
  2. Walk up to and around the new stalls: no invisible wall where the old stall was; you can walk up to the counter.
  3. Frame rate in the Town feels the same.
  4. Radar Hill and your helipad look exactly as before.
  5. Play 15 min (or rebirth): the "Enjoying WAR EMPIRE?" card shows once, gives nothing; "Don't show again" + rejoin: it never comes back.

## v151 PUBLISHED (Code Bot Roblox, 2026-09-30 23:00 Dublin): Open Cloud place version 149 — JOB 40 part C store-props PLUMBING (rows empty: probe 0/19)
- **Published** `dist/WarEmpire-PERF.rbxlx` (WE_Build **151**) via `tools/publish-opencloud.sh` -> HTTP 200 `{"versionNumber":149}`. Servers NOT restarted (Migrate to Latest Update / rejoin).
- **Cherry-pick only** (not a bud-branch merge): `a46a46a` JOB 40 part C -> `7a626d9` on phase-7. JOB 40 part D (`57201e8`, rate reminder) landed on bud mid-ship and is **NOT** in v151 (next ship).
- **Commits (phase-7-polish):** `2e437c4` WE_Build 151 + `tools/checks/codebot_v151.py` + probe result, `c2471da` dist rebuild; this handoff. Bud merge `1ca3494` (phase-7 into claude/desktop-bud, temp worktree).
- **Load probe (Open Cloud Luau on the live place, `tools/probes/job40c_codebot_probe.luau`, raw `docs/job40c-probe-2026-09-30.txt`, table in `docs/PROP-ASSETS.md`): 0 of 19 pass.**
  - 18 ids: `User is not authorized to access Asset` (free public models, but not Roblox's / not in shaunie6's inventory, so the live place cannot load them).
  - 856258654 Radar Station (VexHavoc) loads but fails: 213 parts after the trim (cap 40), a plain block build (119 blocks, no mesh files) and its decal 77911929 is by another user (origin rule).
  - 10140810871 is also by the group "Philadelphia International Airport" (real place) — reject even if it loads later.
  - No Roblox-made radar / sandbag / stall / tower model found on the Creator Store.
- **So `StorePropsConfig.ReplaceRows` / `BaseRows` stay EMPTY:** the code ships as no-op plumbing; the RadarDome kit, helipads and Crossroads Town look exactly as v150. `StorePropsConfig.JOB40` Enabled + **OwnerFirst=true** kept.
- **To unblock:** the owner "Gets" the wanted candidates on the Creator Store as shaunie6 (or picks Roblox-made / own models), then Code Bot re-runs the probe and wires only passers.
- **Live state kept:** GuardConfig.Posts + SpeedV2 + Endgame + BaseMarker + ArmyOrders OwnerFirst=true; ShopOverhaul + CheckpointGuard OwnerFirst=false; STORE-PROPS world rows launched (v136); VIP 199; PreferMesh OFF; WE_Building* untouched; fast travel removed.
- **Checks:** BuyPathStatic PASS=7262 FAIL=0 (phase-7), PASS=7270 FAIL=0 (merged bud); codebot_v151 PASS; rojo deterministic (2 builds identical).
- **Phone tests (Migrate to Latest Update, as shaunie6):**
  1. Radar Hill: the same block radar dome as before, nothing missing, nothing floating.
  2. Your base helipad / runway / dock: unchanged and clear; frame rate as before.
  3. Quick regression: base guards shoot a non-clan intruder; Speed Boost still 40 ("Run 2.5x faster").

## v150 PUBLISHED (Code Bot Roblox, 2026-09-30 22:48 Dublin): Open Cloud place version 148 — JOB 40 parts A+B base guards + SpeedV2 OWNER-FIRST
- **Published** `dist/WarEmpire-PERF.rbxlx` (WE_Build **150**) via `tools/publish-opencloud.sh` -> HTTP 200 `{"versionNumber":148}`. Servers NOT restarted (Migrate to Latest Update / rejoin).
- **Cherry-picks only** (not a bud-branch merge): `cc14b0e` JOB 40 part A real base guards + one hostility rule, `d8a2f62` JOB 40 part B Speed Pass x1.75 / Speed Boost x2.5 (SpeedV2). On phase-7 as `e3117bf` / `f8b6145`.
- **Commits (phase-7-polish):** `4565e9b` WE_Build 150 + `tools/checks/codebot_v150.py`, `b1d9ebc` dist rebuild; this handoff.
- **What ships (owner-first):**
  - **JOB 40A guards:** live `BaseGuard_*` at every gate/helipad/dock/sea post (statues parked); IDLE/ALERT/ATTACK/RETURN/DEAD; one hostility rule (`UnitMayHitPlayer` / `ArmyHostility` + `ApplyDefenceHit`) for post/gate/tower guards and AutoGuns; FRIENDS outside clan are hostile to the base; OwnerFirst by BASE OWNER.
  - **JOB 40B SpeedV2:** Speed Pass x1.75 (WalkSpeed 28, "Run 75% faster"), Speed Boost x2.5 (40, "Run 2.5x faster"); one `SpeedText` / `DescFor` helper for stands / Shop / death card / toast; army Follow caps raised for a 40 runner; MaxWalkSpeedMult 2.5. Stale "40%" text was a pre-v133 live server, not current source.
- **Flags:** `GuardConfig.Posts` Enabled + OwnerFirst=true; `MonetizationConfig.SpeedV2` Enabled + OwnerFirst=true. Endgame + BaseMarker OwnerFirst stay true. **Do NOT set OwnerFirst=false until Studio §11 / 2-player proof + owner ask.**
- **Live state kept:** ArmyOrders OwnerFirst=true; ShopOverhaul + CheckpointGuard OwnerFirst=false; VIP 199; pass Ids unchanged; RPG hold 3972151362; WeaponsLive=true; FastTravel removed; PreferMesh OFF; WE_Building* untouched.
- **Checks:** BuyPathStatic PASS=7216 FAIL=0; codebot_v150 PASS; run_base_guards_test 0 failed; run_speed_test 0 failed; rojo deterministic (2 builds identical).
- **Creator Hub (Code Bot / owner):** update Speed Pass (1998656357) and Speed Boost (3713839342) descriptions to 'Run 75% faster, forever' and 'Run 2.5x faster, forever'. Prices unchanged.
- **Needs a decision (reported, not blocking ship):** army sim S40 turn worst-after-3s 7.49 (>6) and hairpin 10.72 (within v115 about-turn 12); formation turn at 40 may need tuning or a spec relaxation.
- **Servers:** not restarted. Owner: "Migrate to Latest Update" (or rejoin a fresh server) to get v150 / place 148.
- **Phone tests (Migrate to Latest Update, as shaunie6):**
  1. As B (another player, not in A's clan), walk onto A's helipad apron: guards turn, aim and shoot. Kill one: respawns at post after 45 s. As A past your own guards: no shots. Clan-mate: the same. B runs out past 45 studs: guard walks back.
  2. With Speed Boost: you run at 40. Army stays together on a straight, corner and U-turn (no teleports). Speed pad / Shop / death card read "Run 75% faster" / "Run 2.5x faster".
- **Next:** Studio 2-player proof for base-guard hostility (docs/BASE-GUARDS-ROOTCAUSE.md §6) still owed; do NOT flip Posts / SpeedV2 / Endgame / BaseMarker OwnerFirst=false until owner asks. JOBs 41/42 still queued. Claude desktop-bud tip was `6b0fe34` (~22:33 Dublin); not a takeover.
## claude-bud JOB 40E FIX (2026-09-30): BASE OWNER TAGS SMALLER, HIGHER, NEVER EMPTY (branch `claude/desktop-bud`)
**Flag unchanged:** `BaseMarkerConfig.Live` OwnerFirst = true.

**Root cause** (from the owner's phone screenshots + the v149 code):
- **Too big:** a fixed 150-230 px box (never smaller than 150 px, about a fifth of a phone screen).
- **Too low:** HeightStuds 70 over the plot centre, which from 1,000 studs is ~3.7 deg above eye level, right across
  the skyline.
- **Grey empty tags:** ShowOpenBases = true drew grey "OPEN BASE" tags, and a base whose name had not arrived showed
  "?".
- **"VETERAN" in the view:** the rank chip printed the rebirth title.

**Now:**
- **High in the sky:** HeightAt(dist) = 150 studs + 6 % of the viewer distance (cap 260). 1,000 studs away = 210
  studs = 11.6 deg up.
- **A slim pill sized to its text:** a small flag + the short name, 24 px tall, 14 px real text, names cut at 96 px.
  The widest tag is ~160 px near; a typical one is ~110 px. The @handle and a short "R3" show only inside 300 studs.
  No rebirth title.
- **Scale:** 1.0 far .. 1.2 near (clamped; a far tag is never bigger than a near one). Fade in past 60-90 studs
  (the v123 sign takes over at your gate), fade out past 1,800-2,400 studs.
- **At most 5 rival tags** (the nearest) + your own "YOU". Two tags never overlap on screen: the farther one hides.
- **No tag without a live owner and a name:** never grey, never empty.

**Checks:** run_base_marker_test 0 failed (fade, height / angle, scale, width, no-empty, cap, no-overlap);
claude_bud_job40 part E pins (the "HeightStuds = 70" pin retired with a replacement); BuyPathStatic PASS=7268 FAIL=0;
all sims 0 failed; rojo ok; no new LSP errors.

**Owed (§11):** the before / after phone-size screenshots (1024x471, the plaza looking out + a base road at night)
need Studio / a device; I cannot take Roblox screenshots from here.

**Test ON HIS PHONE**
1. From the plaza, look out: tags are small pills high in the sky, not across the bases or the army.
2. No grey or empty tags anywhere; at most 5 rival tags at once and none on top of each other.
3. Walk up to a rival base: its tag grows a little and shows @handle / R<n>. At your own gate "YOU" fades out and
   your base sign shows.

## claude-bud JOB 40 PART D (2026-09-30): "ENJOYING WAR EMPIRE?" REMINDER, NO REWARD (branch `claude/desktop-bud`)
**Flag:** `RatePromptConfig` (`Enabled`, `OwnerFirst = true`). OFF / not live = nothing shows; the Shop favourite row is
unchanged. **To launch:** Code Bot sets `OwnerFirst = false`.
- **Server decides** (Services/RatePromptService, one 0.2 Hz loop for everyone):
  - live, profile loaded, tutorial done, onboarding hold off;
  - never after "Don't show again" (profile.RatePrompt.Never, across servers);
  - once per session, not in the first minute, 3 days since the last show, 20 s without damage taken;
  - then 900 s of total play (RatePrompt.PlaySeconds) OR a trigger: every rebirth (PrestigeService) or a
    big-banner achievement (AchievementService.Shout big), 8 s after the moment.
- **Client** (Controllers/RatePromptController): a small card top-centre (<= 420 px, 48 px buttons, 15 px+ text).
  - It waits for a free screen (not driving / dead / in combat / a panel open) for up to 90 s.
  - It slides in and hides after 20 s.
  - Buttons: ⭐ Favorite (the Shop's PromptSetFavorite call), Maybe later, Don't show again, X.
- **Remote:** RequestRatePromptAnswer (RemoteGate "string:8", 2 / min; the enum later | never | favorite | timeout is
  checked in the service). The show goes out as FeaturePush "RatePrompt" (no new server->client remote).
- **Saved:** profile.RatePrompt = { LastShownUnix, Shows, Never, PlaySeconds } (ProfileSchema.Migrate repairs it;
  missing = defaults).
- **Telemetry:** rate_prompt_shown { trigger }, rate_prompt_answer { answer } only.
- **No reward:** no cash / gold / XP / items / badges (pinned); no reward words in the text; nothing checks a like.
- **Checks:** run_rate_prompt_test 0 failed (31 checks, real service + real Migrate); claude_bud_job40 part D pins;
  BuyPathStatic PASS=7224 FAIL=0; all sims 0 failed; rojo ok; remote audit OK.
- **Not verified in Studio yet:** the card at 800x360 / 956x440, the favourite prompt (Roblox shows it only live).

**Test ON HIS PHONE**
1. After 15 min of play (or ~8 s after a rebirth) the "Enjoying WAR EMPIRE?" card appears once, at the top, not over
   the stick or the fire / jump buttons.
2. Tap "Don't show again", rejoin: it never comes back.
3. ⭐ Favorite opens the Roblox favourite prompt; nothing is given.

## claude-bud JOB 40 PART C (2026-09-30): STORE PROPS AT LANDMARKS AND BASES (branch `claude/desktop-bud`)
**Flag:** `StorePropsConfig.JOB40` (`Enabled`, `OwnerFirst = true`), on top of the STORE-PROPS switches. OFF = today.
- **ReplaceRows:** a store model replaces a WorldKits landmark (e.g. the 6-part RadarDome at Radar Hill). The kit parts
  are hidden only AFTER the copy placed; the copy's bottom sits on the kit's base; the live kill restores every kit
  exactly (transparency, collide, query). Owner-first: runs once a player it is live for is in the server.
- **BaseRows:** per-plot dressing for a LIVE owner by base-upgrade level; 600 parts per plot cap; never inside
  `BaseKeepOut` (helipad spots, runway, basin, apron lane). A 0.1 Hz poll re-dresses a plot on a claim.
- **Both lists are EMPTY.** I cannot run the Open Cloud load probe (no API key, and none goes in the game).
  19 candidates are in `StorePropsConfig.Candidates` and `docs/PROP-ASSETS.md`.
- **Code Bot:** run `tools/probes/job40_props_probe.luau` on the live place, then WE_CHECK2 + wire-asset-ids, then add
  the passing ids as rows. Until then nothing changes in the world.
- **Owed:** the §11 before / after screenshots (need the wired rows + Studio).
- **Checks:** claude_bud_job40 part C pins; BuyPathStatic FAIL=0; sims 0 failed; rojo ok; audit OK.

**Test ON HIS PHONE** (after Code Bot wires rows): Radar Hill shows the store radar, not the block dome, and nothing
floats; your base helipad / runway stay clear; frame rate at your base is unchanged.

## claude-bud JOB 40 PART B (2026-09-30): SPEED HIGHER, WITH TEXT THAT CAN'T GO STALE (branch `claude/desktop-bud`)
**Flags:** `MonetizationConfig.SpeedV2` (`Enabled`, `OwnerFirst = true`).
- **Live:** Speed Pass x1.75 (WalkSpeed 28, "Run 75% faster"), Speed Boost x2.5 (40, "Run 2.5x faster"), both = the
  higher (40). Cap `MonetizationConfig.MaxWalkSpeedMult` 2.5 (was the local MAX_WALK_SPEED_MULT 2.0).
- **Off:** x1.5 / x2 and the same texts as today.
- **To launch:** Code Bot sets `OwnerFirst = false`.
- Robux prices and Ids are unchanged.

**Root cause of "Run 40% faster"**
- It is not in the v133+ source.
- The Creator Hub pass description (product-info API, fetched 2026-09-30) is "Run faster everywhere in WAR EMPIRE.":
  not 40 %, so it is not the purchase prompt.
- git history: `Description = "Run 40% faster, forever"` was the Speed Pass text from v126 (fab245f, x1.4) until v133
  (106f32e).
- So the owner was on a server still running pre-v133 code (running servers are not restarted on publish).

**One source for the text**
- `MonetizationConfig.SpeedText(mult, forever)` + `SpeedMultOf(def, userId)` + `DescFor(def, userId)`.
- Both Descriptions are set from the helper. The stands (PurchaseStands.OfferInfo), the Shop pass / product rows, the
  Speed Boost toast and the death card all read DescFor / SpeedText.
- grep: no typed speed string outside the helper (pinned).

**The army keeps up (ArmyConfig):** Follow3.MaxSpeed 46 -> 58, Follow.Lead.MaxOwnerSpeed 40 -> 48,
Follow.CatchUp.MaxSpeed 40 -> 60, Follow2 MaxSpeed 50 -> 58. SpeedUp / Down 6 / 5 and CatchUpMin 30 are kept.
- **Sim:** tools/sim/army_follow_sim.luau has a new S40 set (a 40-stud/s owner; the REAL FormationController /
  SoldierController / Follow3). Old caps -> new caps:
  - **straight:** mean error 4.40 -> 3.07, worst after 3 s 5.67 (<= the spec's 6).
  - **90-degree turn:** 7.34 -> 3.46, worst after 3 s **7.49 (over 6)**.
  - **hairpin:** 10.95 -> 3.92, worst after 3 s **10.72** (v115's about-turn allowance is 12), and one soldier passes
    **0.23 studs** from the owner on the hairpin.
  - Always: 0 teleports / PivotTo, every slot <= the soldier top speed (50.1 <= 58), every scenario settles (final
    error <= 1.2).
  - The default army sim still passes (FAILS 0).
- **Needs a decision:** the turn / hairpin numbers are reported, not hidden. The formation controller's turn behaviour
  at 40 needs tuning or a spec relaxation (owner / Code Bot decision).
- **Recover / march:** Recover.FollowFarStuds 80 is not reached on these runs (0 recovers). JOB 38 marches have no
  owner pace (unaffected).

**Retired pins** (JOB 40 comments + replacements):
- codebot_v133 speed literals / cap / MaxSpeed 46;
- codebot_v126 CatchUp MaxSpeed 40 and Follow2 MaxSpeed 50;
- BPS "+%d%% forever" death card and the CatchUp range 20..40 -> 20..60;
- codebot_v145 / v146 whole-file MonetizationConfig guards -> "no Robux price / Id line changed".

**Checks:** run_speed_test (helper texts, off / live values, cap, prices / Ids, the 40 sim); claude_bud_job40 part B
pins; BuyPathStatic PASS=7183 FAIL=0; all sims 0 failed; rojo ok; audit OK; no new LSP errors.

**Creator Hub (required note):** Creator Hub: the Speed Pass (1998656357) and Speed Boost (3713839342) descriptions must
be updated to 'Run 75% faster, forever' and 'Run 2.5x faster, forever'. Code Bot does this on Creator Hub (not
Claude). Prices unchanged.

**Test ON HIS PHONE**
1. With the Speed Boost: you run at 40. Your army block stays together behind you on a straight, a corner and a
   U-turn: no teleports (watch the U-turn).
2. The Speed pad, the Shop and the death card read "Run 75% faster" / "Run 2.5x faster".
## claude-bud JOB 40 PART A (2026-09-30): REAL BASE GUARDS + THE ONE HOSTILITY RULE (branch `claude/desktop-bud`)
**Flags:** `GuardConfig.Posts` (`Enabled`, `OwnerFirst = true`, by the BASE OWNER).
- **Off / not live owner:** today's statues, gate guards, towers and AutoGuns exactly, with their JOB 20 checks.
- **To launch:** Code Bot sets `OwnerFirst = false`.
- **v134 audit:** v134's PostGuards / GuardMayHitPlayer never shipped (not on phase-7-polish), so this is the only copy.

**Posts (MapSetup statues, plot-local)**
- The rear-gate pairs `GateGuard_AirfieldL/R` (inner wall X -100), `GateGuard_HelipadL/R` (X 40, the HeliApron) and
  `GateGuard_DockL/R` (X 92), each at the gate +-(half + 3.6), Z = the inner wall -60 + 2.4.
- The sea-gate quay `GateGuard_Sea*`.
- For a live owner they are parked in ServerStorage.WE_ParkedStatues and replaced by live `BaseGuard_<post>` guards: the
  gate guards' unanchored Humanoid + rig (GateDefenseService.spawnGuardModel), never WE_RigStatic. The statues are put
  back when the plot's defences clear.
- **Tower guards:** still anchored on their platforms (not converted); their TARGETING now uses the one rule.

**Brain:** BaseGuards.ThinkPost, a state machine (GuardConfig.PostNext decides) ticked from the existing 5 Hz loop.
- IDLE -> ALERT (a hostile in the plot, or within 80 of the post with line of sight) -> ATTACK after 0.5 s.
- ATTACK: 1.2 shots / s, 10 dmg (x Research TurretDamage x JOB 39 Turret Guns, capped at 3), range 90; line of sight
  and the hit chance on every shot. It moves only to regain sight, never past the 45-stud leash or out of the plot.
- -> RETURN after 8 s quiet or past the leash (walks / paths back, no teleport). IDLE at the post regens HP after 5 s.
- DEAD -> the existing respawn after 45 s at the post (retried every 2 s while a player stands on it).
- **HP:** 150 x Research GuardHP x JOB 39 Gate & Walls (+12 % / level), capped at x3.
- **Target order:** the raider of this plot, then near the ATM, then the nearest; players before units.
- **Logs:** `[BaseGuard]` / `[BaseGuardHit]` under /armydebug.

**The one rule** (root cause proof in `docs/BASE-GUARDS-ROOTCAUSE.md` + `tools/sim/run_base_guards_test.py`)
- The JOB 20 base spared a FRIEND outside the clan, and still shot with PvP off and while its owner was novice-shielded.
- For a live owner, every defence uses `CombatService.UnitMayHitPlayer` / `ArmyHostility` (+ `PvPBlockReason` so a
  shielded owner fires at nobody): post, gate and tower guards through BaseGuards.hostiles, AutoGuns through
  isEnemyPlayer.
- **Hit paths:** player hits go through the new `CombatService.ApplyDefenceHit` (the same hurtPlayer; credited to the
  base owner; kind "BaseGuard" / "AutoGun", so not an army kill); army units through `CombatService.ApplyHit`. No
  TakeDamage on the live path.
- **Attackers:** they need `ArmyHostility(attacker, owner)`; a shielded owner's base answers "Protected".
- **Friends:** the FRIENDS exemption is gone for live bases. Friends who are not in your clan are hostile to your base,
  as they already are to your army.
- **Pins:** GateDefenseService still never holds CombatService (the join hotfix pin): it goes through BaseGuards.
  Retired pin (claude-bud comment + replacement): claude_bud_guards "spawn grace respected".

**Checks**
- run_base_guards_test (state transitions, the hostility table old vs one rule, caps, pair limit);
  claude_bud_job40 part A pins.
- BuyPathStatic PASS=7178 FAIL=0; all sims 0 failed; rojo ok; remote audit OK; no new LSP errors.

**Not verified (Studio 2-player, rule 6):** the 6 scenarios with logs both ways (docs/BASE-GUARDS-ROOTCAUSE.md lists
them).

**Test ON HIS PHONE**
1. As B (another player, not in A's clan), walk onto A's helipad apron: the guards turn, aim and shoot. Kill one: it
   respawns at its post after 45 s.
2. As A walk past your own guards: no shots. A clan-mate: the same.
3. B runs out past 45 studs from a post: the guard stops and walks back.

## v149 PUBLISHED (Code Bot Roblox, 2026-09-30 22:18 Dublin): Open Cloud place version 147 — JOB 39 phases 3–5 + JOB 40E base markers OWNER-FIRST
- **Published** `dist/WarEmpire-PERF.rbxlx` (WE_Build **149**) via `tools/publish-opencloud.sh` -> HTTP 200 `{"versionNumber":147}`. Servers NOT restarted (Migrate to Latest Update / rejoin).
- **Cherry-picks only** (not a bud-branch merge — JOB 38 already on phase-7): `1cd39a6` Elite Training, `e31c2a0` Field Hospital + Armory/Vehicle Workshop, `658dec1` warheads/heist/Intel/Black Market/R25-R40, `5d5e59f` base owner markers. On phase-7 as `2513e75` / `88be9d9` / `aecdb42` / `a71d326`.
- **Commits (phase-7-polish):** `cf813b5` WE_Build 149 + `tools/checks/codebot_v149.py`, `4ae1cb4` dist rebuild; this handoff.
- **What ships (owner-first):**
  - **Phase 3 Elite:** Heavy / SF split, Veteran→Mythic tiers (HP+dmg through `_UnitDmg`), Recruitment Office (NE_E1 cafe), re-train fees, Instant Army Refill free re-trains, ScaleTo + insignia + Mythic aura, formation spacing.
  - **Phase 4:** Field Hospital (heal / Med Kits / Combat Medicine / Field Surgeon / army medic) + Armory Workshop (server mastery + attachments, Gold camos) + Vehicle Workshop (HP / speed / plates).
  - **Phase 5:** Tactical/Heavy warheads, heist kits + the Fixer, Intel Office (contracts / HVT / scout / raided-by), weekly Black Market (cosmetics), plaza bounty scales with income, R25–R40 unlocks.
  - **JOB 40E markers:** name / @username / nation flag / rebirth rank above every occupied base (AlwaysOnTop world-label exception); fade near base; compact far/overlap; OPEN BASE; owner-first by viewer.
- **Flags:** `EndgameConfig.Live` Enabled + `OwnerFirst=true`; Parts Elite/Hospital/Mastery/Workshop/Warheads/Heist/Contracts/BlackMarket/RewardScaling = true. `BaseMarkerConfig.Live` OwnerFirst=true. **Do NOT set OwnerFirst=false until Studio §11 proof + owner ask.**
- **Live state kept:** ArmyOrders OwnerFirst=true; ShopOverhaul + CheckpointGuard OwnerFirst=false; VIP 199; pass Ids; RPG hold 3972151362; WeaponsLive=true; FastTravel removed; PreferMesh OFF; WE_Building* untouched.
- **Checks:** BuyPathStatic PASS=7173 FAIL=0; claude_bud_job39 PASS; claude_bud_job40 PASS; run_endgame_test 0 failed; run_base_marker_test 0 failed; army orders/march 0 failed; codebot_v149 PASS; rojo deterministic (2 builds identical).
- **Servers:** not restarted. Owner: "Migrate to Latest Update" (or rejoin a fresh server) to get v149 / place 147.
- **Phone tests (Migrate to Latest Update, as shaunie6):**
  1. Plaza teal-awning cafe RECRUITS: Elite Training → buy Infantry Veteran → soldiers grow a little, grey band + 1 chevron; keep buying; walk/turn (no teleport). Lose a trained soldier → re-train fee or RE-TRAIN; Instant Army Refill restores trained.
  2. Navy-awning ARMORY: Gun Upgrades mastery + red-dot; Tiger camo (Gold); Hospital FREE HEAL / Med Kits / Field Surgeon GET UP; Vehicle Depot Workshop → Air L3 plates on jet.
  3. HQ console TACTICAL WARHEAD (R25 Heavy); Empire Bank THE FIXER Drill raid; orange INTEL contracts + SCOUT + RAIDED BY SEND; market Trader paint/banner/beret; plaza bounty = minutes of income.
  4. Far side of the map: every occupied base shows flag/name/@/rank; near a base the marker fades (sign takes over); own base YOU in green; leave → OPEN BASE within 5 s.
- **Next:** Studio §11 proof still owed; do NOT flip Endgame / BaseMarker OwnerFirst=false until owner asks. JOBs 41/42 still queued. Claude desktop-bud tip was `5d5e59f` (~21:59 Dublin); not a takeover.

## v148 PUBLISHED (Code Bot Roblox, 2026-09-30 21:44 Dublin): Open Cloud place version 146 — avatar mood animation errors + tower guard nil
- **Published** `dist/WarEmpire-PERF.rbxlx` (WE_Build **148**) via `tools/publish-opencloud.sh` -> HTTP 200 `{"versionNumber":146}`. Servers NOT restarted (Migrate to Latest Update / rejoin).
- **Commits (phase-7-polish):** `9dd4117` code + `tools/checks/codebot_v148.py`, `fcf7085` dist rebuild; this handoff. Merged into `claude/desktop-bud` as `62a117c` (clean, on top of Claude's `55a0e73`; BuyPathStatic on the merge 7155/0).
- **"Failed to load animation with sanitized ID" (1,878 client + 277 server) — root cause:** NOT game assets (0 hits in repo, dist, loaded models). They are PLAYER AVATAR dynamic-head moods (`Character.Animate.mood`). Roblox's own face bundles ship mood assets whose Animation points at animations uploaded by user 8923762 (roseycakes), not Roblox / not the game owner: The Winning Smile (bundle 957, mood 11163856931 -> 104666063103723), Shiny Teeth (265345, 15554865414 -> 122193759333439), Silly Fun (299652, 15938951885 -> 121132383996019), Woman Face (948, 10725638029 -> 96806611330323); 114302219876492 "Smile_Mood" same uploader. All 5 fail AnimationClipProvider in this place (live Luau); Roblox default mood 14366558676 (creator Roblox) loads.
- **Fix:** new `Server/AvatarMoodGuard.server.luau` (+ `RigConfig.AvatarMood`): swaps a player's Animate.mood to 14366558676 before it replicates when the id is known-bad or fails the place's own AnimationClipProvider check (one check per id per server, no log); ids that load are put back. Walk/run/idle/emotes, soldiers and army rigs untouched. Live-tested on synthetic R15 characters (bad -> fallback, good -> restored, late Animate, later change). Real-player effect to confirm in the next error report.
- **"value of type nil cannot be converted to a number" (134 + 53 + 48) — root cause:** `BaseGuards.spawnTower` built `stats = { GuardHealth, GuardDamage }` with no `GuardWalkSpeed`, so `GateDefenseService.spawnGuardModel` did `humanoid.WalkSpeed = nil` (line 541/542 in V122..V141). Engine warns and uses 0; the guard still spawned. Fix: tower stats pass `GuardWalkSpeed = 0` (root anchored on the platform); spawnGuardModel falls back to the Humanoid default for any missing number. Live place 146: tower guard spawns with MaxHealth 260 / WalkSpeed 0, 0 warnings.
- **Checks:** BuyPathStatic PASS=7142 FAIL=0; codebot_v148 PASS; army orders / army sim / army march / checkpoint guards 0 failed. PreferMesh OFF; WE_Building* untouched; prices/passes/shop/ads/server size 10 unchanged; RPG hold 3972151362 unchanged.

## v147 PUBLISHED (Code Bot Roblox, 2026-09-30 ~21:35 Dublin): Open Cloud place version 145 — live error fixes + phone pad-loop cost
- **Published** `dist/WarEmpire-PERF.rbxlx` (WE_Build **147**) via `tools/publish-opencloud.sh` -> HTTP 200 `{"versionNumber":145}`. Servers NOT restarted (Migrate to Latest Update / rejoin for v147).
- **Commits (phase-7-polish):** `81cacef` code + `tools/checks/codebot_v147.py`, `ccb05ee` dist rebuild; this handoff. Merged into `claude/desktop-bud` as `cb8d6e1` (Endgame / job39 files kept bud side = phase 3; phase-7 copies were identical to bud 9e15f27). Endgame phase 3 (`1cd39a6`) is on bud only, NOT in this ship.
- **Fixes (proven live):**
  - DataStore queue: `writeProfile(releaseLock)` no longer does SessionLock.Refresh+Release back-to-back on `lock_<id>`; Refresh skips if this server wrote the key <7 s ago (heartbeat 15 s and autosave 60 s aligned every minute). TTL 45 s still covers.
  - ArmyDebug spam: SLOT ASSIGN / SLOT CHANGE / REPOSITION logs only when `WE_ArmyDebug` is on. Movement unchanged.
  - LoadAsset "not authorized": only live sources were the L5 upgrade pop Flag 1679839739 + Floodlight 116763933 (plus silent GateDefense Sandbags 3525056989) -> set to 0 (Part kit already shown, no visual change). Full list of 54 non-authorised IDs in source (mostly PreferMesh-gated/unused) in `/workspace/v146probe/unauth_refs.txt`.
  - Sound HTTP 429: AudioController created ~20 Sounds at join (14 downloads of 7 files). Now each distinct id is warmed once, 4 s after join, 0.35 s apart (`SoundConfig.Mix.WarmDelaySeconds / WarmGapSeconds`).
  - Phone per-frame: WorldPromptController overlap loop scanned all 150 pads each Heartbeat -> bounding-sphere skip + cached keys (leave events still fire).
- **Not fixed / unproven (need error text from Creator Hub CSV):** animation load failures (all 7 code anim ids are Roblox-owned and load in the live place; likely throttle), nil-to-number (134), mesh/PBR transient failures. Max-player/base-plot warnings came from pre-10-cap servers.
- **FPS census (server world):** ~13k parts, 124 lights (no shadows), 1,840 Textures, 237 SurfaceGuis, 100 Humanoids, StreamingEnabled OFF. Rendering/part count is the likely main phone cost; streaming is an owner decision, not changed.
- **Checks:** BuyPathStatic PASS=7122 FAIL=0 (bud merge 7129/0); codebot_v147 PASS; sound_audit OK; army orders/sim 0 fails. PreferMesh OFF; WE_Building* untouched; prices/passes/shop/ads/server size 10 unchanged.

## v146 PUBLISHED (Code Bot Roblox, 2026-09-30 21:18 Dublin): Open Cloud place version 144 — JOB 39 phase 2 Base Tier + Defence OWNER-FIRST
- **Published** `dist/WarEmpire-PERF.rbxlx` (WE_Build **146**) via `tools/publish-opencloud.sh` -> HTTP 200 `{"versionNumber":144}`. Cherry-pick only of `9e15f27` (not a bud-branch merge — bud was behind on the JOB 38 army fix). Owner-first so Shaun can phone-test; §11 Studio proof still owed before `OwnerFirst=false`.
- **What ships (owner-first):** Base Tier 1..5 (Fort..Capital, real Part builds, nests, soldiers, gate HP) + Defence tree (Plating / Guns / Gate / Vault) + Engineering Bureau stand + instant rebuild. `EndgameConfig.Parts.BaseTier` + `Defence` = true; `Live.OwnerFirst` still true.
- **Commits:** `b558b7e` cherry-pick of `9e15f27`, `b97bbfb` WE_Build 146 + `tools/checks/codebot_v146.py`, `b72863c` dist rebuild; this handoff.
- **Checks:** BuyPathStatic PASS=7104 FAIL=0; claude_bud_job39 PASS; run_endgame_test 0 failed; codebot_v146 PASS; rojo deterministic (2 builds identical). PreferMesh OFF; WE_Building* untouched.
- **Live state kept:** Endgame OwnerFirst=true; ArmyOrders OwnerFirst=true; ShopOverhaul + CheckpointGuard OwnerFirst=false; VIP 199; pass Ids; RPG hold; WeaponsLive=true; FastTravel removed; PreferMesh OFF. JOB 38 army routes-start-at-block (v145) still on phase-7.
- **Servers:** not restarted. Owner: "Migrate to Latest Update" (or rejoin a fresh server) to get v146 / place 144.
- **Phone tests (Migrate to Latest Update, as shaunie6):** see PHASE 2 section below (HQ Upgrade → Fort..Capital look; ENGINEERS Defences; rebuild after breach; EMPIRE rows + PIN).
- **Next:** Studio §11 proof still owed; do NOT set Endgame OwnerFirst=false until owner asks. Claude already pushed phase 3 tip `1cd39a6` on desktop-bud (Elite Training) — not in this ship; Code Bot can cherry-pick next. JOBs 40–42 still queued.

## claude-bud JOB 40 PART E (2026-09-30, PRIORITY): BASE OWNER MARKERS, visible from anywhere (branch `claude/desktop-bud`)
**Flags:** `BaseMarkerConfig.Live` (`Enabled`, `OwnerFirst = true`, by VIEWER).
- **Off / not live for the viewer:** no marker; the v123 base sign and the map are unchanged.
- **To launch:** Code Bot sets `OwnerFirst = false`.

**Server (`Services/BaseMarkerService`)**
- It publishes data only: one Configuration per plot under ReplicatedStorage.WE_BaseMarkers, streaming-safe.
- Fields: Owner, Name, User, Nation (the flag the owner shows, from the plot's NationFlag view; neutral / hidden = none),
  Prestige, Clan tag, ClanId, Pos (the plot centre).
- Written only on change: on a claim (BaseService.OnPlotReady), a leave (+1 s), and a 5 s sweep (rebirths, nation picks,
  clan changes). Nothing per frame.

**Client (`Controllers/BaseMarkerController`)**
- **Marker:** one BillboardGui per plot on a local anchor 70 studs over the plot centre. AlwaysOnTop, MaxDistance 5000:
  the ONE documented exception, now written in CLAUDE.md's world-label bullet and ASSUMPTIONS.
- **Pill:** the nation flag (NationTexture atlas cell; an army-green chip without one), DisplayName ([CLAN] prefix),
  @username, and the gold rank chip ("COMMANDER R3"; hidden at R0).
- **Tints:** own base green + "YOU"; a clan-mate's base blue; OPEN BASE grey and smaller at 60 %.
- **10 Hz step for all markers:** hidden inside 60 studs, fading to full at 90 (the v123 sign takes over at the gate);
  size MaxPx 230x58 near -> MinPx 150x42 far.
- **Compact form** (flag + rank): past 1,800 studs, or the farther of two markers within 90 px on screen.
- **Not done:** the optional map-icon change (part E.4). The map is untouched.

**Checks**
- `tools/sim/run_base_marker_test.py` (13 checks): fade / size / rank / compact rule; owned / open / left plots; a
  hidden or neutral nation shows no flag; the clan tag.
- `tools/checks/claude_bud_job40.py` (part E pins, incl. AlwaysOnTop only in the documented files).
- BuyPathStatic PASS=7166 FAIL=0.

**Risk (owner decision):** CLAUDE.md's nation rules forbid a flag shown "as a target". The marker shows the owner's own
cosmetic flag over his base, and JOB 41 part C turns the markers into raid TARGETS. If that counts, the flag should be
dropped from markers used as targets (the name + rank stay).

**Not verified (Studio / phone):**
- the 2-player screenshots (far corner and 100 studs, 800x360 and 1920x1080);
- the fade at the gate with the v123 sign;
- a leave -> OPEN BASE within 5 s.

**Test ON HIS PHONE**
1. From the far side of the map: every occupied base shows a marker (flag, name, @username, rank), readable on the
   phone.
2. Walk to a base: the marker fades out near the gate and the base sign shows. Your own base reads YOU in green.
3. When the other player leaves, his base reads OPEN BASE within 5 s; when he rejoins and claims, his marker is back.
   He picks a flag or rebirths: it updates within 5 s.
## claude-bud JOB 39 PHASE 5 (2026-09-30): WARHEADS + HEIST KITS + INTEL OFFICE + BLACK MARKET + reward scaling + R25-R40 unlocks (branch `claude/desktop-bud`)
Owner-first (`EndgameConfig.Parts.Warheads / Heist / Contracts / BlackMarket / RewardScaling` = true): every JOB 39 part
is now on for the owner. Off / not live: the silo, bank, bounty, raid and army code behave exactly as before (each hook
returns the old numbers).

**1. Warheads** (the HQ console list: HQ UPGRADE panel)
- **Tactical Warhead** $5M (R2+): loads one silo slot now (NukeService.FillSlot; the cooldowns stay).
- **Heavy Warhead** $25M (the R25 unlock): holds 1. The next launch hits x1.3 radius and x1.2 damage through the ONE
  ApplyRadiusDamage call. BaseClearStuds, the player cooldown (1800 s) and the server cooldown (300 s) are unchanged.

**2. Heist kits** (the Fixer's side desk in the Empire Bank hall, a world anchor at 229.6, -218.5)
- Drill 2M / Thermal Lance 8M / Vault Cracker 25M.
- The bank's own raid loop (BankRaidService) reads the raider's best kit: hold 8 / 10 / 14 s, payout max($35k, 4 / 8 /
  15 min of income), +3 / 5 / 7 BankGuard reinforcements (the existing NPC path: LOS + hit chance; cleared after
  120 s), and a 30-min cooldown for the Deep Vault.
- **Pay reason:** "bank_raid" is already exempt, so the income-sized payout is not multiplied again.

**3. Intel Office** (NW_W1, the orange-awning radio shop; 37 parts, 1 lamp, the INTEL sign)
- **3 daily contracts:** a pure function of UserId + UTC day, drawn from garrison / outposts / checkpoint guards / defend
  a raid / win a SEND / launch a warhead. Each is fed from the game's own hook. CLAIM at the office pays max($50k, 8 min
  of income).
- **The weekly High-Value Target:** 20 min of income + 50 Gold. Reward reason "endgame_reward" (added to
  EconomyService's NEVER_MULTIPLIED: already income-sized).
- **SCOUT:** any ONLINE base, 1 min of income. The report: tier, turrets, guards, gate HP, and the JOB 38 SEND verdict.
- **RAIDED BY:** the last 5 raiders (in-person ATM raids and army raids), with SEND = the JOB 38 SEND remote. The server
  re-checks every fairness rule.

**4. Black Market** (SW_S1 upstairs, the Trader at a crate counter; 23 parts, an unlit lantern, a board)
- **Stock:** 3 Cash slots at max($1M / $3M / $8M, 20 / 45 / 90 min of income) + 1 Gold slot (100-250). It is a pure
  function of the week (the same on every server), and turns over Monday 00:00 UTC.
- **COSMETIC ONLY:**
  - vehicle paints (the spawn recolours the biggest body parts);
  - banner colours (the Base Tier banners);
  - beret colours (your soldiers; a textured hat is tinted);
  - camos (join the Armory's camos);
  - a Part-built trophy cannon on your parade ground.
- One of each. PUT ON / TAKE OFF rows. **No Robux item.**

**5. Reward scaling**
- The plaza bounty becomes max($15k, 3 min of income). It is scaled through the bounty's `mult`, with the cash
  multiplier divided back out; the pinned grant line is unchanged.

**6. Rebirth unlocks R25-R40** (the endgame's own track in EndgameConfig.RebirthUnlocks)
- They are granted by the 5 s sweep while live. The shared PrestigeConfig track is untouched, so non-live players see
  today's rebirth screen.
- R25 Heavy Warhead, R30 Mythic Training.
- R35 Bastion Crest: a gold crest over his gate.
- R40 Legend Parade: 6 static honour-guard figures lining his parade road. They are client-only and built within 300
  studs.

**Checks**
- run_endgame_test (+ phase 5): contracts per day / week, unlocks, both warheads, all 3 kits, the bounty scale, the
  market (stock, income price, Gold slot, one of each, the item takes effect), claims (not done / paid once / HVT
  Gold), raided-by 5, scouting (online only), the 3 new stations built and counted, the crest + trophy, every list.
- BuyPathStatic PASS=7136 FAIL=0; all 16 sims 0 failed; rojo ok; remote audit OK; no new LSP errors (the pre-existing
  FormationController / ArmyController / HudConfig / Remotes ones show because their dependents changed; HEAD has
  them).

**JOB 39 status:** phases 1-5 are all built and pushed, owner-first. The §11 Studio proof list (per CONTINUE-NOW.md, not
blocking) is still owed:
- Base Tier screenshots per tier from 100+ studs + the per-base part / light counts;
- the 2-player Elite TTK log;
- the gun range test in Studio;
- the Defence loot tests;
- each station on an 800x360 phone.

**Test ON HIS PHONE**
1. At your HQ console: TACTICAL WARHEAD (a silo slot fills), and once you reach R25, HEAVY WARHEAD: the next nuke ring
   is visibly bigger.
2. The Empire Bank: THE FIXER at a desk by the east wall. Buy the Drill, raid the vault: 8 s hold, 3 extra guards run
   in, a much bigger payout.
3. The orange radio shop: INTEL. 3 contracts + the weekly target; finish one and CLAIM. SCOUT the second phone's base.
   After being raided, the RAIDED BY row: SEND sends your army.
4. The market upstairs: the Trader. Buy a paint / banner / beret: your next vehicle, your base banners or your soldiers'
   berets change colour.
5. Capture the plaza: the bounty is now a few minutes of your income.
## claude-bud JOB 39 PHASE 4 (2026-09-30): FIELD HOSPITAL + ARMORY WORKSHOP (mastery / attachments / camos) + VEHICLE WORKSHOP (branch `claude/desktop-bud`)
Owner-first (`EndgameConfig.Parts.Hospital / Mastery / Workshop` = true). Off / not live: the WeaponConfig row itself,
no max-HP bonus, vehicle x1, no stations.

**1. Armory Workshop (SW_S1, the navy-awning market, ground floor; 39 parts, 1 lamp, the ARMORY sign)**
- **Mastery L1-5 per owned gun:** +3 % damage, +2 % fire rate, +4 % range, +6 % magazine, -5 % reload a level.
  - Price: shop 1M x 2^(L-1), rebirth guns 2M, Robux guns 3M.
- **Attachments** for the gun in your hand: Red-dot +10 % range 1M, Grip -15 % spread 1.5M, Extended Mag +25 % 2M.
  - The Suppressor is listed but NOT sold: nothing pings the map when a player fires, so it would do nothing (see
    ASSUMPTIONS).
- **Server numbers:** CombatService uses ONE per-player gun row (`CombatService._GunDef` ->
  `EndgameService.PlayerGunDef`, cached, applied once) for the fire-rate check, the range / hit slop, damage (damageFor),
  magazine (magSize) and reload. The client paces / reaches / reloads with the same multipliers (WE_GunMods).
- **`[GunTest]` (headless):**
  - AR at L0 = the WeaponConfig numbers.
  - AR at L5: dmg 25.3, rps 9.9, range 168, mag 39, reload 1.50.
  - AR at L5 + Red-dot range 182, + Grip spread x0.85, + Extended Mag mag 47.
  - A 150-stud shot is past the AR's old range (140) and inside L5 + Red-dot.
- **Camos (the first Gold sink):** Olive 50 / Urban 100 / Tiger 150 / Gold 250 Gold.
  - Buy once, put on / take off per gun for free.
  - The server sets the character's WE_GunCamo with the drawn gun; every client recolours the built gun (WeaponVisuals,
    template or kit, local and remote).

**2. Field Hospital (the Hospital store prop's forecourt: a canvas stand; 37 parts, 1 lamp, the HOSPITAL sign)**
- The sign is a white plus on green: no red-cross emblem.
- FREE HEAL to full (not within 6 s of damage, every 60 s).
- MED KIT (carry 3, max($25k, 30 s of income)). A MED KIT button on the right edge while hurt: HOLD 0.6 s, +50 HP over
  3 s.
- COMBAT MEDICINE L1-5 (2 / 5 / 12 / 30 / 75M): +10 max HP a level on the base, before Double HP and armour, hard cap
  400 (ArmourService). From L3 the army medic: soldiers not hurt for a sweep regain 1 HP / s.
- FIELD SURGEON (carry 1, max($250k, 3 min)): after a death a GET UP (10) button. It puts the new body back on the spot
  you fell with half HP. Not inside an enemy plot.
  - This is the endgame code's ONLY PivotTo, pinned. It is not travel: the same place, within 10 s.

**3. Vehicle Workshop (a "Workshop" prompt on your own Vehicle Depot console)**
- Ground / Air / Naval x L1-5 ($1.0M ... $23.4M): +6 % HP (VehicleHealth HPMult) and +3 % speed (the drive
  attributes) a level. It applies on the next spawn.
- L3 bolts armour plates (+ bolt rails) on both flanks; L5 adds a gold nameplate on the nose.
- Premium vehicles take it on top of their own multipliers (the Robux lead is kept).

**Checks**
- run_endgame_test (+ phase 4): GunStats, every purchase (ownership, the station, the Suppressor refusal, the Gold camo
  with no Cash), the cached per-player gun row, WE_GunMods, Workshop + look, Hospital (Medicine / Med Kit / revive
  prices, token kept on a failed revive), both stations built and counted.
- **Pins:** the new stat paths, the 4 Health-write sites, the one revive PivotTo.
- BuyPathStatic PASS=7093 FAIL=0; all 16 sims 0 failed; rojo ok; remote audit OK.
- **LSP:** no new errors. HudConfig / Remotes show 3 pre-existing ones because CombatController is now in the changed
  set; HEAD has the same 3.

**Test ON HIS PHONE**
1. Plaza, the navy-awning market: the ARMORY sign, the Gunsmith at a bench, a wall rack. Tap "Gun Upgrades": your guns'
   MASTERY rows, then the attachments and camos for the gun in your hand. Buy AR mastery + Red-dot and shoot a target a
   bit past the old range: it hits.
2. Buy the Tiger camo (150 Gold): your gun turns tiger-striped for you and the second phone; PUT ON / TAKE OFF.
3. The Hospital: the green HOSPITAL stand. FREE HEAL when hurt; buy 2 Med Kits; in a fight HOLD the MED KIT button on the
   right. Buy the Field Surgeon, die, tap GET UP: you stand where you fell with half HP.
4. At your Vehicle Depot console: "Workshop" -> Air L3. Spawn a jet: armour plates on its flanks, more HP on the bar.
## claude-bud JOB 39 PHASE 3 (2026-09-30): ELITE TRAINING + Recruitment Office + re-train fees (branch `claude/desktop-bud`)
Owner-first (`EndgameConfig.Parts.Elite` = true). Off / not live: `UnitElite` returns nil, so today's soldier exactly.

**1. Soldier types (§2.4)**
- The field army was one kind. Now every 5th slot is **Heavy** (+20 % HP, shoulder pads) and every 10th is **Special
  Forces** (+10 % damage) once the SF Facility is L3+.
- MarchSpeed and walk speed are unchanged (the block stays coherent; the spec's -10 % Heavy speed is not applied, see
  ASSUMPTIONS).

**2. Training (the Recruitment Office in NE_E1, the cafe)**
- **Price:** per type, Veteran 2M / Elite 8M / Legendary 30M / Mythic 100M (Mythic needs R30). +8 % HP and damage per
  tier.
- **Where it applies:**
  - on the server at spawn: Humanoid MaxHealth / Health, research x elite capped at MaxMult 3;
  - at BOTH unit damage sites through the one path: `SquadOrdersService._UnitDmg` = SoldierDamage research x the unit's
    WE_EliteDmg, capped. PlayerMaxDps is still applied downstream by CombatService;
  - in the JOB 38 army power (SEND verdict).
  - A buy re-applies to the living soldiers in place (HP ratio kept, no move).
- **Look:** a helmet trim band (grey / green / gold / black-gold), 1-3 gold chevrons on the left arm (Mythic: a star
  plate).
- **Size:** Model:ScaleTo 1.05 / 1.10 / 1.18 / 1.28, with HipHeight set to 2 x scale. The rig's Motor6Ds scale with it,
  so the client RigAnimator keeps animating.
- **Aura:** Mythic gets a client-only gold ParticleEmitter (Rate 3, LightEmission 0.3), only at Graphics Quality >= 4
  (automatic quality: keyboard devices only).
- **Formation:** ArmyController scales RowSpacing / ColSpacing / AisleStuds / FirstRowStuds by the largest soldier
  scale in the block. Nothing else in the steering changed (no PivotTo, no snap).

**3. Re-train fees (the recurring sink)**
- A trained soldier that dies owes its tier's fee on the respawn: 5k / 15k / 40k / 100k, paid automatically through the
  one purchase path ("endgame_retrain").
- Short of cash: it comes back UNTRAINED (plain look, base stats) and the Recruitment Office shows "RE-TRAIN n
  SOLDIER(S) $x".
- The existing 49 R$ **Instant Army Refill** (same product / price / Id, APPROVED §9 b): in SoldierService.ConsumeRefills
  after the receipt is saved, every soldier is re-trained free (untrained ones now, the dead ones on their respawn:
  profile.Endgame.FreeRetrains).
- The respawn itself stays free, as today (soldiers are not lost on death in this game): the "$500" part of §2.4 does
  not apply.

**Checks**
- run_endgame_test (+ phase 3): the tier maths, the type split, every purchase, the auto fee / untrained / RE-TRAIN /
  refill flow, the look (chevrons / star / pads / scale / hip height), the Recruitment Office build (37 parts, 1 light,
  1 sign), static pins on both damage sites + the formation spacing.
- `[EliteTest] tier=0..4 maxHP x1.00..x1.32 dmg x1.00..x1.32 TTK 100 %..76 %` (headless arithmetic; the §11.2 Studio
  2-player TTK log is owed).
- **Retired pin** (claude-bud comment + replacement): claude_bud_job26's exact unit-hit line. It is now the same
  ApplyUnitHit call with `_UnitDmg`.
- BuyPathStatic PASS=7087 FAIL=0; all 16 sims 0 failed; rojo ok; no new LSP errors; remote audit OK.

**Test ON HIS PHONE**
1. Plaza, the teal-awning cafe: the RECRUITS sign, the Drill Sergeant behind a counter with lockers. Tap "Elite
   Training": 3 rows (Infantry / Heavy / Special Forces). Buy Infantry Veteran.
2. Your soldiers grow a little, get a grey helmet band and 1 chevron. Keep buying: green / gold bands, 2-3 chevrons,
   bigger soldiers, the block spacing widens. Walk and turn: nobody pops or teleports.
3. Lose a trained soldier in a fight: on its respawn "Re-trained a soldier: -$5K". With no cash it comes back plain;
   RE-TRAIN at the office.
4. Buy the Instant Army Refill: every soldier is back trained with no fee.
## claude-bud JOB 39 PHASE 2 (2026-09-30): BASE TIER + DEFENCE TREE + Engineering Bureau + instant rebuild (branch `claude/desktop-bud`)
Owner-first (`EndgameConfig.Parts.BaseTier` / `Defence` now true; `Live.OwnerFirst` still true). Per CONTINUE-NOW.md the
§11 Studio proof is owed later, not blocking. Off / not live: every gate / turret / loot / soldier number is the old one
(run_endgame_test checks each with Live.Enabled = false).

**1. BASE TIER 1..5 (§2.3)**
- **Where:** bought at the HQ console, a client "HQ Upgrade" prompt (F on PC) on the player's own Command Center console.
  The HQ panel also has REBUILD DEFENCES NOW.
- **Price and requirements:** Fort 10M (R2 + CC L5), Citadel 25M (R3), Stronghold 60M (R5), Bastion 150M (R8),
  Capital 400M (R12). Kept through rebirth.
- **Effects:** gate HP +10 % (T1 / T2 / T4); soldiers +5 / +5 / +10 (T1 / T3 / T5, SoldierService cap); rebuild -10 s
  (T3); +1 real AutoGun nest at the gate at T2 and T4 (GateDefenseService.GunSlots: real turrets, the same shot rules).
- **Look (Modules/BaseTierBuilder, server-built, everyone sees it; rebuilt on tier / CC level / walls change, removed
  when the owner leaves):**
  - T1: roofs on the real gate posts + a new HQ storey with a window band.
  - T2: a lattice comms mast + dish on it, a sandbagged roof deck, ammo at nest 1.
  - T3: 4 corner bastions on the wall ring + a gatehouse (piers, lintel, crest) clear of the opening.
  - T4: a floodlit flag tower beside the HQ (1 SpotLight, no shadows), ammo at nest 2, banners on the gate roofs.
  - T5: a marble kerb round the parade ground, a bronze commander statue, 4 banners with the gold Capital trim.
- **Parts added per tier (the real builder, the headless count):** 26 / 29 / 54 / 27 / 37 = **173 at Capital**, 1 light.
  The live per-base total (cap 2,700, 40 lights) still has to be measured in Studio.

**2. DEFENCE TREE (§2.5; bought at the Engineering Bureau)**
- **Price:** 4 tracks x 10 levels, $1.0M ... $68.7M a level. L5-6 need T1, L7-8 T2, L9 T3, L10 T4.
- **Plating:** AutoGun HP +15 % / level (on the JOB 38 TurretHealth).
- **Guns:** turret damage +6 % / level, x the research bonus, capped at MaxMult 3.
- **Gate & Walls:** gate HP +12 % / level, rebuild -3 s / level (never under 10 s).
- **Vault (APPROVED §9 f):** army raid 5 % -> 2.5 % at L10, ATM raid 10 % -> 7 % (MoneyCollectorService.VaultMult).
- **After a buy:** the gate defences resync at once (GateDefenseService.SyncPlot).
- **Headless numbers:** `[DefTest] gate=10 tier=5 gateHP x2.50`, `rebuild=10 s`, `plating=10 autogunHP x2.50`,
  `guns=10 turretDmg research 1.5 -> x2.40`; `[LootTest] vault=10 army 2.5 % atm 7 %`, `vault=5 3.75 % / 8.5 %`,
  `vault=0 = 5 % / 10 %`.

**3. The Engineering Bureau**
- **Where:** a covered drafting stand in the Office Building's forecourt (store prop 12423243620). It stands 7 studs out
  of the face nearest the plaza, because the prop's ground floor is not known to be walkable (the spec's fallback).
- **No prop:** without the prop (StoreProps not placed) the stand goes beside the Command Office house.
- **Build:** client-only for live players, 32 parts, 1 lamp, the ENGINEERS sign on the canopy valance.
- **Prompt:** "Defences" opens the list panel: 4 rows with level, now / next effect, price + ETA, BUY / LOCKED / MAX.

**4. Instant rebuild**
- At the HQ console, while the gate is breached or a gun is shot down: max($25,000, 30 s of income).
- It calls GateDefenseService.InstantRebuild (the same rebuild as the timer).

**5. Plumbing**
- **One spend call:** EndgameService.Purchase now has ONE SpendCash: `"endgame_" .. key` (empire / tier / defence /
  rebuild; non-paying).
- **XP pin:** the entry is now the prefix `endgame_` (still 11 sites).
- **Retired Code Bot pin** (claude-bud comment + replacement): codebot_v145 "no config changed since v144 tip". It is now
  "MonetizationConfig / WeaponConfig / RebirthConfig untouched since v144 tip", the configs it protected.
- **EMPIRE panel:** HQ UPGRADE and ENGINEERING BUREAU rows with their cheapest next goal + PIN.

**Checks:** BuyPathStatic PASS=7080 FAIL=0; all 16 sims 0 failed (run_endgame_test now covers phase 2: every purchase,
every effect, OFF, the stand, the 5 tier builds); rojo ok; no new LSP errors; remote audit OK.

**Test ON HIS PHONE**
1. At your base, walk to the Command Center console: a second prompt "HQ Upgrade". Tap it: BASE TIER 1: FORT, $10M, BUY.
   Buy it: roofs appear on the gate posts and a new storey on the HQ roof. Check the look from 100+ studs out.
2. Keep buying to Capital (with the rebirths): mast + sandbags, corner bastions, the gatehouse, the flag tower
   (floodlight at night), the statue and banners. Tier 2 and 4: a new AutoGun at the gate.
3. Plaza, the Office Building: the ENGINEERS stand. Tap "Defences": 4 rows. Buy Gate & Walls: the gate bar's max HP rises.
4. Let a friend breach your gate: at the HQ console, REBUILD DEFENCES NOW for 30 s of income, and the gate is back.
5. EMPIRE (Base panel): HQ UPGRADE and ENGINEERING BUREAU rows with PIN.
## v145 PUBLISHED (Code Bot Roblox, 2026-09-30 19:01 Dublin): Open Cloud place version 143 — JOB 38 army SEND / ATTACK fix
- **Owner report:** "Sending my army to a location they don't go and attack" (phone). SEND buttons + map pick worked; the army never left.
- **Root cause (evidence):** `ArmyPlan.StartSend` / `StartClear` built the plan with `Lead` = the OWNER's root and `setDest` planned the route from `plan.Lead`. With the owner inside his walled base the army holds outside the gate, and his gate barrier (`GateDefenseService.spawnGateBarriers`, CanCollide) blocks pathfinding out -> `ArmyPlan._NoRoute` -> "No route to X's base" + HOLD about a second after "Army left". Live Open Cloud probe (place 142, synthetic walls): inside plot -> outside, gate closed = NoPath, gate open = Success; real `ArmyRoute.Plan` from inside base = `no_route`, from the army spot = 130 waypoints.
- **Contributing:** (1) `ArmyRoute.Legs` 400-stud legs whose end lands inside another walled plot failed the whole route; (2) `advance()` held the lead within LeadMaxGap (18) of the block centre while the formation sits FirstRow + HalfDepth behind by design -> deep blocks crawled / stalled; (3) stuck re-plan snapped the lead onto the centre -> block walked backwards.
- **Fix** (`dcefd00` on `codebot/army-orders-fix`, cherry-picked as `6ac6162`): routes start at the army block (`plan.Squad` centre); virtual lead placed `ArmyController.Standoff(st)` along the route (`ArmyRoute.PointAlong`); gap measured past the standoff; stuck re-plan from the block; RETURN goes to his gate spot while he is inside his plot (+ one gate retry on no_route); failed middle leg retries the rest as one path. No teleport / PivotTo / snapping / catch-up speed; one hostility rule unchanged.
- **Checks:** BuyPathStatic PASS=7081 FAIL=0; new `tools/sim/run_army_march_test.py` (real ArmyPlan/ArmyRoute/ArmyController/Formation/Soldier code, 6 scenarios) 0 failed (v144 code: 5/6 fail); run_army_orders_test 0 failed; claude_bud_job38 PASS; `tools/checks/codebot_v145.py` 22 PASS.
- **Commits:** `6ac6162` fix, `eb9130a` WE_Build 145 + checks, `07419b9` dist rebuild; published `{"versionNumber":143}`.
- **Live state kept:** ArmyOrders OwnerFirst=true; ShopOverhaul + CheckpointGuard OwnerFirst=false; Endgame OwnerFirst=true; VIP 199; pass Ids; RPG hold 3972151362; WeaponsLive=true; FastTravel removed; PreferMesh OFF; WE_Building* untouched. Servers not restarted (owner: Migrate to Latest Update / fresh server).
- **Phone tests owed:** SEND from inside his base; SEND from outside to a far base; ATTACK from his base; RECALL while in his base (army should come to his gate); big army + escorts stay in formation on real terrain; first route compute ~1 s hold then departs.

## v144 PUBLISHED (Code Bot Roblox, 2026-09-30 17:20 Dublin): Open Cloud place version 142 — JOB 39 phase 1 endgame OWNER-FIRST
- **Published** `dist/WarEmpire-PERF.rbxlx` (WE_Build 144) via `tools/publish-opencloud.sh` -> HTTP 200 `{"versionNumber":142}`. Owner asked to keep merging + pushing; JOB 39 is owner-first so publishing lets him phone-test. The §11 Studio proof is still owed before `OwnerFirst=false`.
- **dist rebuild:** dist was stale (built at v143 `b91f409`); fresh `rojo build` of HEAD `dc2eb4e` (deterministic, 2 builds identical) copied to `dist/WarEmpire.rbxlx` + `dist/WarEmpire-PERF.rbxlx`, commit `ea758ec`.
- **Pre-publish checks:** WE_Build pins 144 (EarlyRemotes, BaseService, DataService x2); `EndgameConfig.Live` Enabled + OwnerFirst=true (Parts: Rebirth + EmpireLevel only). v142/v143 state intact: ShopOverhaul + CheckpointGuard OwnerFirst=false, VIP 199, pass Ids unchanged (MonetizationConfig untouched since v143), RPG hold 3972151362, ArmyOrders OwnerFirst=true, WeaponsLive=true, FastTravelEnabled=false, PreferMeshWhenAssetIdSet=false, WE_Building* untouched. BuyPathStatic PASS=7063 FAIL=0.
- **Live probe (Open Cloud Luau, place v142, IsStudio=false):** Endgame AnyLiveFor / LiveFor(Rebirth, EmpireLevel) = true for 470626172, false for 12345 and 987654321; BaseTier false for all; Shop/CG OwnerFirst=false; ArmyOrders OwnerFirst=true; RebirthCostScale(5)=2; EndgameService present.
- **Servers:** not restarted. Owner: "Migrate to Latest Update" (or rejoin a fresh server) to get v144; phone tests as in the v144 section below.
- **Next:** Studio §11 proof, then owner ask to set `EndgameConfig.Live.OwnerFirst = false` + publish. JOBs 39 phases 2–5 + JOB 40 still queued.

## v144 (Code Bot Roblox, 2026-09-30 ~17:15 Dublin): merge claude-bud JOB 39 phase 1 endgame — OWNER-FIRST — NOT published
- **WE_Build 144**. Cherry-pick `cd47047` from `origin/claude/desktop-bud` as `d06064b` onto phase-7-polish (v143 tip `83eeb88`) + Code Bot bump commit. **NOT published** to Open Cloud (handoff STATUS: CODE COMPLETE, NOT DONE under JOB 39 §11 until Studio proof / captures in `docs/proof/job39/`).
- **Flags:** `EndgameConfig.Live` Enabled + `OwnerFirst = true` (owner 470626172 + Studio only). **Do NOT set OwnerFirst=false until Studio §11 proof + owner ask.** PreferMesh OFF; WE_Building* untouched.
- **What merges (owner-first):** rebirth price scale (Costs × (1 + 0.20 × min(rebirths, 20))); EMPIRE LEVEL 0..30 (+2% cash/level); Command Office client-only interior in NE_N1 + station panel + Base EMPIRE button/PIN.
- **Live state kept:** ArmyOrdersConfig OwnerFirst=true; ShopOverhaul + CheckpointGuard OwnerFirst=false; VIP OverhaulRobuxPrice 199; PreferMesh OFF; FastTravel removed; WE_Building* untouched; place stays at Open Cloud v141 / last publish WE_Build 143.
- **Checks:** BuyPathStatic PASS=7063 FAIL=0; claude_bud_job39 PASS (22 + Luau SKIP); run_endgame_test 0 failed; codebot_v144 PASS; rojo ok.
- **Phone tests (when published / Migrate to Latest Update, as shaunie6):**
  1. Drive to the plaza, walk into the red-awning hotel: the COMMAND sign over the door, the Chief of Staff behind the map table. Tap "Empire Level": the panel shows EMPIRE 0, the next card $5,000,000, BUY.
  2. BUY: "EMPIRE 1! +2% cash", and the cash pill $/s rises by about 2 %. Buy up to L12 with the 170M.
  3. Take a hit in the plaza with the panel open: it closes. Walk out the door: it closes.
  4. Open the Base panel: the gold EMPIRE button. Tap it: the ring shows your level and the Command Office row. Tap PIN: the gold line leads back to the plaza.
  5. Look at a console on your base (after a rebirth): the price is 1.2x per rebirth, and the Base panel shows the same price. Open Rebirth: "Empire and upgrades" under KEEP, "Next base $..." under RESET.
- **Servers:** unchanged (no publish). Running servers stay on v143 / place 141.
- **Next:** Studio §11 proof still owed (Shaun / Studio on his machine). Then owner ask to set `EndgameConfig.Live.OwnerFirst = false` + publish. JOBs 39 phases 2–5 + JOB 40 still queued on desktop-bud docs (not started).

## claude-bud JOB 39 PHASE 1 (2026-09-30): rebirth price scale + EMPIRE LEVEL + Command Office (branch `claude/desktop-bud`)
**STATUS: CODE COMPLETE, NOT DONE under JOB 39 §11.** The §11 item 6 Studio proof (screenshots / captures in
`docs/proof/job39/`) needs Roblox Studio, which this session cannot run. The headless proof is
`docs/proof/job39/phase1-headless.md` (it lists the captures still owed). Per §11 I stopped here: phases 2-5 and
JOB 40 are NOT started.

**Flags:** `EndgameConfig.Live` (`Enabled`, `OwnerFirst = true`) + `EndgameConfig.Parts` (phase 1: `Rebirth`,
`EmpireLevel` on; the other 11 off).
- **Off / not live:** today's game exactly. Raw BaseConfig prices, no Empire factor in cashMultFor, no station, no
  EMPIRE button, and nothing reads `profile.Endgame` (run_endgame_test proves the profile is never touched).
- **To launch:** Code Bot sets `OwnerFirst = false` after the Studio proof.

**1. Rebirth price scale (§2.1)**
- `BaseService.PurchaseUpgrade` charges `EndgameService.ScaledCost` = Costs[L] x (1 + 0.20 x min(rebirths, 20)) for
  the 15 structures + 4 businesses.
- Rebirth-zone structures (bought by RebirthZoneService) and Gold rows are never scaled. Income is unchanged
  (BalanceConfig reads the raw Costs). Levels already bought are never re-charged.
- One life: $16.07M (R0) -> $22.5M (R2) -> $80.3M (R20+). `WE_BaseCostScale` tells the console chip and the Base panel
  the same price.
- The rebirth modal: KEEP "Empire and upgrades", RESET "Next base $25.7M" (free path only).

**2. EMPIRE LEVEL (§2.2)**
- `profile.Endgame.EmpireLevel` 0..30, kept through both rebirth paths.
- Cost(L) = round(5M x 1.17^(L-1), to 100k), halves to even, matching the spec table (L2 5.8M ... L30 474.6M; all 30 =
  $3.24B).
- +2 % cash per level: its own factor in the non-exempt stack (L30 = x1.60).
- The base sign shows "· EMPIRE 12" (★ from L5; "· EMPIRE MARSHAL" in the title at L30).

**3. The Command Office (§3)**
- **Where:** in NE_N1 (the red-awning plaza hotel), built on the CLIENT only for live players (nobody else sees a part).
- **What:** a map table, the "Chief of Staff" (static Parts, no Humanoid, not damageable), a flag stand (a plain command
  banner), a cabinet, one ceiling PointLight (no shadows, range 14), the Empire board upstairs (6 milestone plaques turn
  gold) and the door sign "COMMAND" (one SurfaceGui, MaxDistance 40). 39 parts.
- **Prompt:** "Empire Level" (HoldDuration 0, 12 studs) opens the station panel: EMPIRE n, "+x% cash", the next card
  with price and "ready in 12:05", BUY (64 v), the next milestone and the next rebirth's base price.
- **Closing:** damage closes the panel, and so does walking 22 studs away.
- **Server rules:** within 16 studs of the NPC, not hurt in the last 6 s, the price from config, SpendCash
  "endgame_empire".
- **Base panel:** a new EMPIRE button (live only) opens the EMPIRE panel: the Empire ring, each live station's next
  goal + price + ETA, and PIN (the one map pin, no fast travel).

**Checks**
- `tools/checks/claude_bud_job39.py` (25 pins).
- `tools/sim/run_endgame_test.py`: 69 checks on the real config / service / client builder / rebirth summary, plus
  the pacing sims.
- BuyPathStatic FAIL=0; all 15 sims 0 failed; rojo ok; no new LSP errors; remote audit OK.
- **Updated pin** (claude-bud comment + replacement): the XP SpendCash call-site pin, 10 -> 11 sites. + `endgame_empire`
  in EndgameService.Purchase; non-paying: it is not on XPService.OnSpend's list.

**Owner decisions needed**
- **Pacing:** the spec's 0.20 scale gives R1-R6 within the §7 +/-25 % of the rebirth-level minutes, but **R7 is -31 %**
  (max the base 46.8 min vs the rebirth level 68.3 min, tools/sim/endgame_curve_sim.py `cost_scale`). Built at 0.20 as
  approved; the test prints it as a NOTE.
- **Purchase XP:** purchase XP is sqrt(price), so a scaled buy pays ~sqrt(scale) more build XP (R3: x1.26). The XP pin
  requires SpendCash to get the price actually paid.

**Not verified here (Shaun / Code Bot must):**
- the §11 captures above;
- the station panel and the EMPIRE panel at the 6 viewports (HUD harness);
- the NPC / table placement inside the real NE_N1 (the frame from Enterables);
- one real purchase in Studio.

**Test ON HIS PHONE**
1. Drive to the plaza, walk into the red-awning hotel: the COMMAND sign over the door, the Chief of Staff behind the
   map table. Tap "Empire Level": the panel shows EMPIRE 0, the next card $5,000,000, BUY.
2. BUY: "EMPIRE 1! +2% cash", and the cash pill $/s rises by about 2 %. Buy up to L12 with the 170M.
3. Take a hit in the plaza with the panel open: it closes. Walk out the door: it closes.
4. Open the Base panel: the gold EMPIRE button. Tap it: the ring shows your level and the Command Office row. Tap PIN:
   the gold line leads back to the plaza.
5. Look at a console on your base (after a rebirth): the price is 1.2x per rebirth, and the Base panel shows the same
   price. Open Rebirth: "Empire and upgrades" under KEEP, "Next base $..." under RESET.

## v143 (Code Bot Roblox, 2026-09-30 ~16:45 Dublin): ship claude-bud JOB 38 army ATTACK/SEND/RECALL + ARMY KILLS — OWNER-FIRST — place version 141
- **WE_Build 143**. Cherry-pick `0150edf` from `origin/claude/desktop-bud` as `2003433` onto phase-7-polish (v142 tip `e113293`) + code/dist `b91f409`. Open Cloud HTTP 200 `versionNumber=141`.
- **Flags:** `ArmyOrdersConfig.Live` Enabled + `OwnerFirst = true` (owner 470626172 + Studio only), as Claude shipped. **Do NOT set OwnerFirst=false until Shaun phone-tests and asks.** That later flip also swaps TOP ARMY → ARMY KILLS for everyone.
- **Live state kept (v142):** `ShopOverhaulConfig.Live.OwnerFirst = false`; `CheckpointGuardConfig.Live.OwnerFirst = false`; VIP `OverhaulRobuxPrice = 199` (Creator Hub 199; owner has NOT approved 349); guard keep-out 130; Depot.CP_E / Armory.CP_W plain; pass Ids (WarChest / SuperSoldiers / DoubleHP / PG_*); RPG hold 3972151362; SpawnNPC regular-cap fix; WeaponsLive=true; FastTravel removed; PreferMesh OFF; WE_Building* untouched.
- **What ships (while live for owner):** ATTACK = auto-clear (seek→march→fight→chain→return, leash 300, no PivotTo/teleport during plan); SEND ARMY from map card (verdict, defender ETA + red marker, siege turrets→guards→gate→ATM, 5%/2.5% ArmyRaid loot); RECALL marches home; fairness a–g (online-only, 5 min SEND cooldown, 10 min protect, too-weak block, bully loot half); AutoGun HP; ARMY KILLS board (replaces TOP ARMY only when LiveForAll).
- **Checks:** BuyPathStatic PASS=7030 FAIL=0; claude_bud_job38 PASS (33 incl. Luau CLI); run_army_orders_test 0 failed; codebot_v143 PASS; rojo ok.
- **Phone tests (Migrate to Latest Update, as shaunie6):**
  1. Open the walkie: a third row SEND / RECALL at the same 44 px cells and a status line. Press ATTACK near a camp: status SEEKING → MARCHING → FIGHTING → CLEARED → RETURNING; the block walks there and back in formation (no pops, no teleports).
  2. RECALL mid-march: the army turns and walks back.
  3. Second phone: open the map, tap the owner's base (SEND ARMY + "Your army X vs defences Y"). Or from the owner's phone tap the second player's base → SEND ARMY. Second phone gets the ETA warning and the red ENEMY ARMY marker.
  4. Watch the siege: turrets smoke/offline → guards → gate breach toast → ATM hold → "Looted $N" (5 %). Army walks home.
  5. Try SEND again at once: "Army resting 4:5x". Same base from another account: "Just raided: protected 9:xx".
- **Still pending:** Studio 2-player acceptance A–F; march look while turning; walkie at 5 viewports; live PathfindingService routes; confirm AutoGuns still ignore army units.
- **Servers:** running servers keep v142 / place 140. Shaun restarts / Migrate to Latest Update himself; Code Bot does not restart servers.
- **Next:** owner phone-test; when happy, ask Code Bot to set `ArmyOrdersConfig.Live.OwnerFirst = false`. JOBs 39–40 still queued on desktop-bud docs (not started).

## v142 (Code Bot Roblox, 2026-09-30 ~16:38 Dublin): JOB 36 shop overhaul + JOB 37 checkpoint guards LIVE FOR EVERYONE (owner 16:24) — place version 140
- **WE_Build 142**. Code + dist commit `52d0905`. Open Cloud HTTP 200 `versionNumber=140`. Nothing from `origin/claude/desktop-bud` merged (its new JOB 38 `0150edf` / `128ff9d` is NOT shipped).
- **Flags:** `ShopOverhaulConfig.Live.OwnerFirst = false`; `CheckpointGuardConfig.Live.OwnerFirst = false` (guards, cleared bonus, map rows, and the daily "Checkpoint" objective through `LiveForAll()`). Kill switches (`Enabled`) kept.
- **VIP price:** the Creator Hub stays **199** (owner has NOT approved 349). `MonetizationConfig.GamePasses.VIP.OverhaulRobuxPrice` 349 → **199** (the one display value), so the Shop shows "199 R$". No other price changed (codebot_v142 diffs every RobuxPrice against v141). The overhaul VIP perks (+50 % cash, daily crate, gold name) now come with the 199 pass. **To charge 349 later:** owner sets 349 on the Creator Hub first, then Code Bot sets OverhaulRobuxPrice = 349.
- **Checkpoint keep-out (from the positions in code):** 6 detailed checkpoints get guards, the first 6 Checkpoint kits WorldPOI builds (POIs order). Before v142 these were Town CP_N/E/S/W + **Depot.CP_E + Depot.CP_W**. **Depot.CP_E (-1127, 0) sits ~53 studs from the Pool_Depot vehicle spawn pad (-1180, 34)**, and Armory.CP_W, the next in line, is ~53 from Pool_Armory. Both now build plain (row `NoDetail = true`; WorldPOI honours it), so the guarded six are **Town CP_N/E/S/W, Depot.CP_W (-1483, 0), Armory.CP_E (1483, 0)**. Nearest: Town CP_S ~150 from Pool_Town, Town ~330 from a plot edge, Depot.CP_W / Armory.CP_E ~305 from their pools. Hawk Checkpoint (WorldSites, 0, -480) is plain, but it is ~127 from the P3 gate pad.
- **Runtime guard:** `CheckpointGuardService` builds keep-out zones at boot: plot pads (edge), the plot gate vehicle pads, the vehicle pools, and the emergency spawn (0, 0). Any booth within `CheckpointGuardConfig.KeepOutStuds` (130) gets no guards, logged `[CheckpointGuardService] CP_x_z: no guards (...)`. So a refused-detail shuffle can never put guards next to a base / spawn.
- **Protection rule:** the guards' TargetFilter now also refuses players under the spawn or novice shield (`CombatService.IsSpawnInvulnerable` / `IsNoviceShielded`), on top of CombatNPC's existing InvulnerableUntil hit skip. This applies to everyone.
- **Live state kept:** pass Ids (WarChest 2002640637, SuperSoldiers 1998231741, DoubleHP 2002214665), RPG hold 3972151362, SpawnNPC cap fix, WeaponsLive=true, PG_* Ids, FastTravel removed, PreferMesh OFF, WE_Building* untouched.
- **Checks:** BuyPathStatic PASS=6976 FAIL=0. run_shop_test 0 failed. run_shop_render_test 0 failed for both uids (uid 9 now sees War Chest / Super Soldiers / Double HP; the VIP row reads "199 R$ · PERMANENT"; the cash "+" scrolls to Cash Pack Mega). run_checkpoint_guards_test 0 failed (new: everyone targeted, shields refused, keep-out from the real plot / pool positions). run_sites_test, run_kit_detail_test and every run_*_test 0 failed. claude_bud_job36 25 PASS; claude_bud_job37 18 PASS; codebot_v142 27 PASS; rojo ok. The owner-first / 349 pins in job36/37 and v139/v140/v141 were superseded.
- **Live probe (Open Cloud Luau, place v140):** Shop.LiveFor and CG.LiveFor are true for 12345, 987654321 and 470626172; LiveForAll=true; KeepOutStuds=130; VIP 199/199; pass Ids and prices as above; SkuLive(12345, WarChest)=true; WeaponsLive=true, FastTravel=false, PreferMesh=false. BuildKeepZones = 25 zones. Keep-out: Town ×4, Depot.CP_W and Armory.CP_E clear; Depot.CP_E = Pool_Depot@53, Armory.CP_W = Pool_Armory@53, Hawk = Gate_P3@127.
- **Phone tests (Migrate to Latest Update):** (1) Second phone (not shaunie6): the Shop shows War Chest first, VIP at 199 R$, PERMANENT rows, and the cash "+" reaches the cash packs. (2) That phone drives to a Town checkpoint: guards shoot it, but never while it is spawn- or novice-shielded. (3) West Depot east checkpoint (by the motor pool) is the plain kit with no guards; the west one has guards. (4) Clear a checkpoint: the "Checkpoint cleared" toast; the map shows CLEAR m:ss; a daily Checkpoint objective may appear.
- **Servers:** running servers keep v141. Shaun will restart / migrate them himself; Code Bot did not restart any.

## v141 (Code Bot Roblox, 2026-09-30 ~16:35 Dublin): ship claude-bud JOB 37 real road checkpoint + killable guards — OWNER-FIRST — place version 139
- **WE_Build 141**. Cherry-pick `332bd64` from `origin/claude/desktop-bud` as `2ba6d52` (only LATEST-HANDOFF.md conflicted; both sections kept) + code/dist `f1250cd`. Open Cloud HTTP 200 `versionNumber=139`. Earlier desktop-bud SHAs (4c2b10a / 4ec656d / 1d09cce) not re-merged.
- **Live state kept:** v140 pass Ids (WarChest 2002640637, SuperSoldiers 1998231741, DoubleHP 2002214665), RPG hold 3972151362, SpawnNPC regular-cap fix, shop cash-row scroll fix, WeaponsLive=true, PG_* Ids, FastTravel removed, PreferMesh OFF, WE_Building* untouched. All pinned in `tools/checks/codebot_v141.py`.
- **Flags:** `CheckpointGuardConfig.Live` Enabled + `OwnerFirst = true` (owner 470626172 + Studio only), as Claude shipped. `WorldDetailConfig.Kits.Checkpoint` on: the detailed 99-part kit is built for everyone (world is shared); guards / rewards / map rows / GO only for the owner.
- **Hostility review:** guards shoot through the shared CombatNPC path (line of sight, hit chance, `InvulnerableUntil` = spawn shield + novice shield, ForceField, vehicle redirect); guard service never writes Health. No ally rule applies (world NPCs, hostile to all). Concerns: (1) non-owner players are ignored by guards but can still shoot them and collect the per-kill $150 + 45 XP (the cleared bonus is live-only), so near the owner they farm free kills while owner-first; (2) no safe-zone / base keep-out on guards beyond checkpoint placement (aggro 80, leash 50 from post) — confirm no detailed checkpoint is within ~130 studs of a plot or spawn; (3) guards share checkpoints with the JOB 31 activity anchors, so check a site activity and guards on the same booth do not stack; (4) not device-verified; the 2-player Studio combat test is still owed.
- **Checks:** BuyPathStatic PASS=6953 FAIL=0; claude_bud_job37 18 PASS (with LUAU); run_checkpoint_guards_test 0 failed; run_kit_detail_test 0 failed; run_shop_test + render 0 failed (both uids); codebot_rpg_hold PASS; run_sites_test 0 failed; claude_bud_job31 PASS; codebot_v141 20 PASS; rojo ok.
- **Phone tests (Migrate to Latest Update, as shaunie6):** (1) Walk to a desert road checkpoint at night: booth, boom gate, sandbags, tower searchlight sweeping; check FPS. (2) The 5 guards (one on the tower) shoot with real hits / misses; cover works; spawn / novice shield respected; a second non-owner phone is ignored. (3) Kill all 5: cash + XP per kill, then one "Checkpoint cleared +$X +250 XP". (4) Wait 3 min nearby: they respawn on their posts, never on you; map shows "CLEAR m:ss" meanwhile. (5) Map shows guarded checkpoints red; tap to pin (no fast travel).
- **Servers:** running servers keep v140. Shaun will restart / migrate them himself; Code Bot did not restart any.

## v140 (Code Bot Roblox, 2026-09-30 ~15:55 Dublin): JOB 36 pass Ids wired (still OWNER-FIRST) + 2 owner bug fixes + RPG hold fix — place version 138
- **WE_Build 140**. Commits: `5f5b356` (cherry-pick of `6c770b4` from `origin/codebot/rpg-fix`: launcher Hold 3972164452 → 3972151362 RifleHold, docs, `tools/checks/codebot_rpg_hold.py`) + code/dist `53daf5f`. Open Cloud HTTP 200 `versionNumber=138`. PreferMesh OFF; WE_Building* untouched; fast travel stays REMOVED; aircraft weapons stay live; PG_* Ids unchanged.
- **Pass Ids:** `WarChest` 2002640637 (799), `SuperSoldiers` 1998231741 (349), `DoubleHP` 2002214665 (199). Verified: `apis.roblox.com/game-passes/v1/universes/10767159222/game-passes?passView=Full` lists all three, `isForSale=true`, prices match; product-info agrees (creator shaunie6). `ShopOverhaulConfig.OwnerFirst = true` kept. VIP still 199 (overhaul 349); no price changed. docs/SHOP.md + docs/LIVE_PLACE.md updated.
- **Bug "cash packs gone from the Shop":** the rows were built (proved by `tools/sim/run_shop_render_test.py`, which runs the real ShopController.Init), but the JOB 36 order puts them after ~30 pass rows (~2100 px down for the owner) and the cash "+" (OpenCashPacks) still scrolled the list to the TOP ("CashMega is first"). Fix: it scrolls to the Cash Pack Mega row (rows carry `WE_RowH`). The pre-fix controller fails the new test (CanvasPosition 0). run_shop_test now runs the render test (owner + non-owner).
- **Bug "Too many enemies around; try soon" on START:** that text is SiteActivityService `AreaBusy`. It fires when `CombatService.SpawnNPC` returns nil. Nothing counted enemies near the player. SpawnNPC checked the regular cap (18) against the TOTAL alive count, and that count included OverCap outpost defenders (up to 20, awake within 260 studs of a player) and bank guards. The field pool is 12, so a few awake defenders near the base blocked every regular spawn. Fix: Regular vs cap, Total vs cap + SpecialOverCap (the documented NPCCounts contract). Activity NPCs keep normal slots (JOB 31 rule). New copy: "The battlefield is full right now; try again soon".
- **Bug "floating green box by the gate": NOT fixed.** Not reproduced from code. StoreProps world rows keep 330 studs from plots and are raycast-grounded; zone rows sit on the yard slab. The nearest match by look is the ATM Part kit (dark CollectorBody, neon green screen, green ATMGlow) at Courtyard.Collector (-42, 118), about 37 studs from the gate checkpoint (-18, 146), but its build is unchanged since v70 and grounded. Need: in Studio/live, select the prop and read its name / `WE_StoreProp` attribute, or send a screenshot with position.
- **Checks:** BuyPathStatic PASS=6909 FAIL=0; run_shop_test 0 failed + render 0 failed (both uids); claude_bud_job36 25 PASS; run_sites_test 0 failed; codebot_v140 + codebot_rpg_hold PASS; rojo ok.
- **Phone tests (Migrate to Latest Update, as shaunie6):** (1) Shop shows War Chest / Super Soldiers / Double HP rows with real Buy prompts. (2) Cash "+" opens the Shop at Cash Pack Mega. (3) START a mission near base: it starts. (4) RPG hold no longer sweeps up/down. (5) A non-owner still sees the old shop.
- **Servers:** running servers keep v139. Shaun will restart / migrate them himself; Code Bot did not restart any.

## v139 (Code Bot Roblox, 2026-09-30 ~15:23 Dublin): ship claude-bud JOB 36 shop overhaul — OWNER-FIRST (WarChest/SuperSoldiers/DoubleHP Id 0) — place version 137
- **WE_Build 139**. Cherry-pick `1d09cce` (`db7899b` on phase-7-polish) from `origin/claude/desktop-bud` + code/dist `2f721fc`. Open Cloud HTTP 200 `versionNumber=137`. PreferMesh OFF; WE_Building* untouched; fast travel stays REMOVED; aircraft weapons stay live (v138); premium guns stay live (v136/v137 Ids).
- **Flags (per Claude handoff):** `ShopOverhaulConfig.Live.Enabled = true`, `OwnerFirst = true` (owner UserId 470626172 + Studio only). New passes `WarChest` / `SuperSoldiers` / `DoubleHP` stay **Id 0** — hidden, never prompted. **To launch for everyone:** owner creates those three passes + sets VIP Creator Hub price 199→349, pastes Ids, then Code Bot sets `OwnerFirst = false`.
- **What ships (while live for owner):** Shop order FREE → War Chest → 2x Cash (**BEST VALUE**) → VIP 349 → …; every pass row **PERMANENT**; cash packs scale with passive income; Speed stand / death offer = Speed Boost; army-wiped = Bigger Army; VIP +50% cash + daily crate + gold name; War Chest implies 2x+Auto+VIP+BiggerArmy; Super Soldiers x1.25 army; Double HP x2 MaxHealth. Full list in `docs/SHOP.md`.
- **Checks:** `LUAU_COMPILE=$HOME/.local/bin/luau-compile python3 tools/BuyPathStatic.py` PASS=6889 FAIL=0; `tools/checks/claude_bud_job36.py`; `tools/sim/run_shop_test.py` 0 failed; `tools/checks/codebot_v139.py`; rojo ok.
- **Phone tests (Migrate to Latest Update, as owner shaunie6):**
  1. Open Shop > SUPPLY: FREE rows, then 2x Cash marked **BEST VALUE** in gold, then VIP at 349, and so on. Every pass row reads PERMANENT; Speed Pass / Army Expansion rows are gone.
  2. Cash pack rows show amounts from your income (e.g. Cash Pack L = 60 min of passive, never under $200k).
  3. Supply Depot Speed stand reads Speed Boost R$ 99 (a second non-owner phone's base still shows the Speed Pass).
  4. Rejoin as VIP: "VIP supply crate: +$X" once; chat name gold; same-day rejoin = no second crate.
  5. Lose your whole army: offer is "Army down! Bigger Army". Die with no speed owned: "Run faster" for Speed Boost.
  6. Non-owner join: old shop exactly (OwnerFirst).
- **Servers:** running servers keep v138. Shaun will restart / migrate them himself; Code Bot did not restart any.

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

## claude-bud JOB 38 (2026-09-30): army ATTACK auto-clear + SEND ARMY + ARMY KILLS (branch `claude/desktop-bud`)
**Flags:** `ArmyOrdersConfig.Live` (`Enabled`, `OwnerFirst = true`).
- **Off / not live:** today's Follow / Attack / Hold / Retreat exactly (the JOB 24 attack, leash 140), no SEND UI, no
  walkie row, turret HP only matters to live attackers.
- **To launch:** Code Bot sets `OwnerFirst = false`. That also swaps TOP ARMY -> ARMY KILLS.

**How it moves (the formation standard)**
- `Modules/ArmyPlan` owns a LEAD POINT that walks an `ArmyRoute` path (PathfindingService legs <= 400 studs, 3 retries,
  a 2 / s budget) at MarchSpeed 14.
- `ArmyController` steers the SAME block after that lead instead of the owner: the same FormationController.Plan,
  heading rate and slot caps, even while the owner is dead.
- The lead WAITS while the block is > 18 studs behind (the block goes at its slowest soldier).
- During a plan: AllowRecover = false, NoReposition = true. No PivotTo, Reposition or teleport; a unit that cannot
  follow is marked LOST and reported (`[ArmyRoute]`).

**1. ATTACK (live owner) = auto-clear**
- Seek the nearest hostile group within 250 of the owner, through THE target pick (`pickSquadTarget` with plan
  overrides: one hostility rule).
- March; fight until the group (CombatService GroupId) is gone / out of reach (60 s without progress) / non-hostile.
- Chain to the next within 150 (max 4). Then RETURN and fold into FOLLOW.
- Leash 300 while auto-clearing. An enemy player shooting the army on the way is answered.
- Grouped NPCs may be engaged away from the owner only during his ordered auto-clear (CombatService.SetUnitPlanCheck).
- Status: SEEKING / MARCHING -> X 180 m / FIGHTING 3 left / CLEARED n / RETURNING.

**2. SEND (the map card of another player's base)**
- **Verdict:** SEND ARMY shows the server verdict (`RequestArmySendCheck` -> "Your army 820 vs defences 1,240: risky"),
  and `RequestArmySend { plotId }` re-checks everything.
- **March:** the army walks there; the owner stays put. The defender gets "⚠ <Name>'s ARMY is marching on your base,
  ETA m:ss" at once, plus a red ENEMY ARMY marker on his map (the 2 s feed).
- **Siege, in order:**
  - turrets (new HP: 400 / 550 / 700 by walls level 4 / 5 / 6+, rebuilt after 90 s);
  - gate / tower guards;
  - the gate (the existing breachGate: toast, 50 s rebuild);
  - inside guards;
  - the ATM.
  - A defending player is always first. Every hit goes through the existing paths (attackAimOnly / unitShootAt ->
    GateDefenseService.ApplyUnitDamage / CombatService).
  - A dead sender's army keeps going (OwnerAway, SEND only) while he is in the server; he leaves = disbanded as before.
  - No refill at the owner while a SEND is out.
- **Loot:** the lead unit holds the ATM 6 s. A hit restarts the hold (the DamageCancelHp rule).
  - `MoneyCollectorService.ArmyRaid`: CanArmyRaid (= CanRaid's checks minus the thief-character ones) and the same money
    path (`_MoveLoot`) into the sender's ATM, at 5 % (2.5 % bully).
  - The victim's shield starts exactly as for a player raid.
- **No loot:** a shield / low balance at the breach -> "Gate breached, no loot (...)".
- **End:** looted / wiped / RECALL / 240 s -> RETURN on foot.

**3. Fairness (DECIDED by Shaun, 2026-09-30)**
- a) Raids are online only; never raid an offline base ("Player left").
- b) An army raid loots 5 % (ArmyLootMult 0.5).
- c) The defender always gets the ETA warning and the red map marker.
- d) The army keeps attacking while the sender is dead, as long as he is in the server; it disbands when he leaves.
- e) SEND is blocked when the army is too weak (< 0.25 x defences); the loot is halved when it is far stronger (> 4 x).
- f) A 5-minute SEND cooldown per sender (`profile.Raid.ArmySendCooldownUntil`, from the siege; 150 s if the victim
  left).
- g) 10 minutes of protection for a base after any army raid (`profile.Raid.ArmyProtectUntil`).
- Plus: the shield, the new-player 600 s and the novice shield block a SEND; allies never; no SEND with PvP off; one
  active SEND.

**4. Orders UI**
- **Walkie** (live): a third row SEND / RECALL (64 v cells, 44.8 px real), keys 5 / 6, and a status line under the grid.
  While the walkie is shut, a small "ARMY: ..." strip sits in the top stack.
- **SEND** opens the world map ("Tap an enemy base").
- **RECALL** marches the army back (no teleport).
- **Debug** (`/armydebug`): `[ArmyPlan] [ArmyRoute] [ArmyMarch] [ArmySiege] [ArmyFair]`, plus `[ArmyTarget]` as before.

**5. ARMY KILLS (addendum)**
- Counts army kills: players killed by army fire (MOST KILLS' kill rules: no self / clan / farmed pair), checkpoint and
  bank guards (ByUnit), and base guards (weapon "Squad").
- New store key `WE_LB2_ArmyKills` (+ weekly). ALL-TIME and THIS WEEK tabs, the TOP ARMY slot and frame, admin
  excluded.
- It replaces TOP ARMY only when `ArmyOrdersConfig.LiveForAll()`.

**Checks**
- `tools/checks/claude_bud_job38.py` (33 pins).
- `tools/sim/run_army_orders_test.py`: 57 checks. Every fairness reason; the loot 5 / 2.5 %; route legs / retries /
  no-route; the lead <= MarchSpeed and waits; seek -> march -> fight -> chain -> return -> FOLLOW; RECALL; send march;
  cooldown / protection on the profiles; siege priority; the defending player first; the breach with a dead sender;
  the ATM hold restarted by a hit; victim left -> 150 s; wiped; bully kept; no PivotTo / teleport / forced damage.
- BuyPathStatic PASS=6947 FAIL=0; all 13 sims 0 failed; rojo ok; no new LSP errors; remote audit OK.
- **Retired pin** (claude-bud comment + replacement): the XP SpendCash site for "atm_raid_loss" moved from
  completeRaid to its shared helper `MoneyCollectorService._MoveLoot` (same one non-paying call).

**Not verified here (Shaun / Code Bot must):**
- the Studio 2-player acceptance A-F;
- the march look while turning ([ArmyMarch] shows no PivotTo);
- the walkie row at the 5 viewports (HUD harness);
- the real PathfindingService routes on the live map;
- AutoGuns do not target army units (as before): they fight players only.

**Test ON HIS PHONE**
1. Open the walkie: a third row SEND / RECALL at the same 44 px cells and a status line. Press ATTACK near a camp: the
   status goes SEEKING -> MARCHING -> FIGHTING -> CLEARED -> RETURNING, and the block walks there and back in formation
   (no pops, no teleports).
2. RECALL mid-march: the army turns and walks back.
3. Second phone: open the map, tap the owner's base (SEND ARMY + "Your army X vs defences Y"). Or, from the owner's
   phone, tap the second player's base -> SEND ARMY. The second phone gets the ETA warning and sees the red ENEMY ARMY
   marker.
4. Watch the siege: turrets smoke and go offline, then guards, then the gate breaches (toast), then the ATM hold and
   "Looted $N" (5 %). The army walks home.
5. Try SEND again at once: "Army resting 4:5x". Try the same base from another account: "Just raided: protected 9:xx".
## claude-bud JOB 37 (2026-09-30): real road checkpoint + killable guards (branch `claude/desktop-bud`)
**Flags**
- **Detail:** `WorldDetailConfig.Kits.Checkpoint`. False builds today's 8-part kit exactly. The world is built once for
  everyone.
- **Guards:** `CheckpointGuardConfig.Live` (`Enabled`, `OwnerFirst = true`). Off / not live = no guards, no rewards,
  no map or mission change.

**1. The kit** (`WorldKits Detail.Checkpoint`): **99 parts** (plain 8, so +91 extra each).
- **Booth:** plinth, framed windows on 3 sides (glass 0.4 + mullion + sill), door with frame + handle, roof with
  fascia, AC unit, a door lamp head. `CheckpointBooth` keeps its name / size / place. It is solid, so no interior is
  modelled.
- **Boom gate:** cabinet, hinge, counterweight, raised arm in 6 red / white bands (never collides), rest post on the
  far shoulder.
- **2-course sandbag L and U** firing positions.
- **The JOB 31 braced watchtower** with a searchlight.
- **4 jersey barriers** as a staggered chicane on the shoulders.
- **A razor-wire fence** (posts, 2 wires, 2 coils).
- **2 floodlight poles** (lamp heads, no light).
- **A flag:** our own olive cloth with a gold diamond, not a real flag.
- **STOP / HALT - SHOW PASS / CHECKPOINT boards** (3 SurfaceGuis via the world sign budget), a speed disc and a
  warning triangle.
- **Supplies:** 3 crates + strap, 2 ammo boxes on a field table, a jerry can.
- **Road lane:** every part is >= 13.2 studs from the road line (WorldPOI road gaps); span 53 x 33 (<= 64).

**Lights: ONE per checkpoint**, the tower searchlight: SpotLight, Shadows off, night only (WE_NightLight), range 18,
brightness 0.8.
- The world light cap is `WorldConfig.Lights.MaxWorld` 24, and hygiene deletes extras.
- The brief's booth PointLight and 2 floodlight SpotLights would have taken the whole world budget, so the floodlights
  and booth lamp are lamp-coloured heads (never Neon).
- The client sweeps the searchlight (`CheckpointController`, within 250 studs; one RenderStepped loop only while one is
  near).

**Part budget**
- `MaxExtraParts` 900 -> **1446 (+546)**. The +546 is the checkpoint's own share (`KitCaps.Checkpoint`), so the JOB 31
  kits keep exactly their 900.
- 546 = 6 detailed checkpoints; the others (about 14 in the world) build plain. Guards only live at detailed ones.
- WorldPOI: a detailed street cluster refused (neighbour disc, row light / sign caps) is rebuilt PLAIN once and its
  detail refunded (`WorldKits.RefundDetail`), so a checkpoint is never dropped because of its detail. Log:
  `[WorldDetail] <poi> <cluster> refused detailed (...): rebuilt plain`.
- Per-checkpoint log: `[WorldDetail] Checkpoint extra=91 (share N / 546)`.

**2. Guards** (`CheckpointGuardService`, `CheckpointGuardConfig`)
- **Posts:** 5 per detailed checkpoint (Attachments `WE_GuardPost1..5` on the booth; #5 on the tower deck, a Static
  post).
- **NPC type** `CheckpointGuard` (140 HP, 9 dmg, 1.1/s, range 70, aggro 80); the bank guards' R6 rig + RigAnimator.
- **Combat:** CombatService.SpawnNPC (GroupId `CP.<id>`, NoRespawn, Home, Leash = 30 + 20). CombatNPC's line of sight +
  hit chance + real shots, the protections and caps; no Health writes / TakeDamage / immunity.
- **Target filter:** a new `TargetFilter` spawn option. CombatNPC picks the nearest player the filter accepts (nil =
  unchanged), so guards ignore players the switch is not live for.
- **Wake / sleep:** a live player within 220 studs wakes the group; nobody live within 340 despawns it (no NPC slot).
  **NPC slots:** not a SpecialNPCType; they use the regular 18-slot pool (never the +4 bank / fort / rig headroom). A
  full pool spawns fewer.
- **Rewards:**
  - per kill: the NPC type's $150 + 45 XP (CombatService, like every NPC);
  - "Checkpoint cleared" when the last guard dies: 250 XP + max($2,500, 2 min of passive income) capped at $25,000
    (half in private servers). It goes to every live player who hurt a guard in the last 30 s or killed one (army kills
    count), once per cycle, and not again within 300 s. One toast.
  - Mission objective "Checkpoint" +1; analytics checkpoint_guard_kill / checkpoint_cleared.
- **Respawn:** as a group 180 s after the last death, only near a live player, never while a player stands on a post.
- **Map / GO:** the world map shows each checkpoint as hostile (red) or "CLEAR m:ss" (live players only). The mission
  GO "Checkpoint" points at the checkpoints with guards up (tap-to-pin tracker, no fast travel). The daily objective is
  only offered once the switch is live for everyone (the mission offer is global).

**Checks**
- `tools/checks/claude_bud_job37.py` (19 pins).
- `run_kit_detail_test.py`: 99 parts, lane clear, span, arm never collides, booth kept, 5 posts, one light Shadows off,
  small parts no shadow, off = plain 8.
- `run_checkpoint_guards_test.py`: 30 checks (site, wake only for live, spawn opts, target filter, credit / cleared
  once / non-live and stale contributors unpaid, 180 s respawn, not on a player, cooldown, sleep, map / GO, config).
- BuyPathStatic PASS=6897 FAIL=0; all sims 0 failed; rojo ok; no new LSP errors; remote audit OK.
- **Retired pins** (claude-bud comments + replacements in claude_bud_job37.py): BPS W3s2 K "kits add no spot lights"
  (now: exactly one SpotLight, the searchlight); claude_bud_job31 MaxExtraParts 900 + the single-allowance test.

**Build guide §11**
- **Done:**
  - silhouette broken (tower, roof, AC);
  - plinth / ground contact;
  - trims and frames;
  - 2-3 tones;
  - materials fit;
  - scale reference (booth > avatar);
  - storytelling (supplies, fence, flag);
  - PreferMesh untouched, no WE_Building*, nothing real-world;
  - the flag is fictional Parts;
  - no fast travel;
  - behind flags;
  - small parts CastShadow false;
  - decor non-colliding;
  - cover (sandbags, jerseys, booth, walls) CanQuery on;
  - one glass pane per window;
  - light / sign caps;
  - no per-frame scans;
  - server-validated combat;
  - NPCs on the shared state machine.
- **Not done here:** greybox playtest, a phone walk-round, day / dusk / night check, Graphics Quality 3 FPS, the
  5-viewport HUD harness (no new UI beyond map labels).

**Test ON HIS PHONE**
1. Walk up to a desert checkpoint at night: the floodlight heads, the searchlight sweeping from the tower. Check FPS.
2. Get shot by the guards: real hits and misses, taking cover works, a novice shield / spawn shield is respected. A
   second non-owner phone standing there is ignored by them.
3. Kill all 5 (one is on the tower deck): cash + XP per kill, then ONE "Checkpoint cleared +$X +250 XP".
4. Wait 3 min nearby: the guards respawn on their posts, never on you. The map shows "CLEAR m:ss" in the meantime.
5. Open the map: checkpoints show red while guarded. Tap one to pin it (no fast travel). The mission GO for a
   Checkpoint objective appears only after the everyone-launch.

Not device-verified; the 2-player Studio combat test is still owed.
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
