# WAR EMPIRE asset shortlist: the hard-wire sheet for the Grok bot

**Date:** 2026-09-24. **Repo:** read at `f9985c2`; `VisualAssetConfig.luau` and `SoundConfig.luau` are a snapshot (another workflow edits them).
**Machine-readable twin:** `docs/asset_shortlist.json`.
**Owner's own list (2026-09-25):** this sheet is superseded for the owner's Creator Store list by `docs/ASSET_WIRING.md` (what is wired, what waits for `tools/wire-asset-ids.py`, and why).

**How every id here was checked.** The judge looked up 423 asset ids again today, not trusting the earlier research:
- `economy.roblox.com/v2/assets/<id>/details` for every id: Name, Creator (name, type, id, badge), AssetTypeId, IsForSale, IsPublicDomain, PriceInRobux, Created, Updated;
- for models, also `apis.roblox.com/toolbox-service/v2/assets/<id>` (USD price, script count, triangles, instance counts, votes) and `toolbox-service/v1/items/details` (Endorsed);
- store thumbnails of the key picks, looked at by eye;
- the Roblox client file list (build 0.740.0.7400927) for every `rbxasset://` path.

Raw responses are cached in the session scratchpad (`assets/cache/judge/`, 706 files). **No id in this sheet is typed from memory.** A cell that says NOT FOUND gives a search keyword instead.

What could not be checked: third-party model files need a Roblox login (HTTP 401), so their real part count, hidden text and authorship are "unverified" until the Studio check in §5. The researchers downloaded and parsed the Roblox-owned models, and those counts are quoted. Nothing here was run in Roblox.

## 0. The answer in short

Yes: below is one pick and one backup for every slot the game needs now (P0) and next (P1), with exactly what to click. Five things matter most:

1. **Fix first, no store clicks (P0).** Six UI sounds point at two engine files that no longer exist in the Roblox client (`electronicpingshort.wav`, `switch.wav`), so taps, notices, warnings, errors, "denied" and capture-start are silent. §3.5 gives licensed replacements. §3.1 clears 24 ids: a 484k-triangle soldier swarm, a 156k-triangle mesa, a 100k-triangle sandbag nest, two third-party ids that skip the security switch, and every vehicle model that copies a real vehicle (Humvee, Bradley, FMTV, MRAP, F-15, F/A-18, Mustang) or a game franchise.
2. **Roblox-owned picks need no clicks at all.** They are Roblox's own Light Utility Vehicle, Dune Buggy, Pickup and Van for the 9 light-vehicle ids, the Weapons Kit guns for the 7 gun slots, Roblox's own animations, Roblox's licensed sound library and the Synty packs. They load with "Allow Loading Third Party Assets" OFF. The cars, guns, animations and Synty pieces need a small code change first (§6).
3. **The owner presses Get Model on 14 free third-party ids** (list in §5 step 4): tents, crates, jersey barriers, pumpjack, ATM, palm, cactus, camo net, flag pole and tutorial arrows. Nothing is paid.
4. **Everything else stays our own Part kits, on purpose.** That covers tanks, helicopters, jets, ships, big trucks, sandbags, oil drums, buildings and World v2 structures. No free store model beats them on phones or on the "no real-world copies" rule.
5. **Two yes/no answers from the owner.** Roblox's kit Auto Rifle has an AK-style shape and the Rocket Launcher an RPG-style shape. They are Roblox's own unnamed models, licensed to us, but the owner's rule says "no AK-47 copies". If the answer is no, those two stay Part-kit guns.

## 1. How assets reach the game

### A. Runtime loading by id (the default, and how the game works today)

A config file holds an asset id, for example `VisualAssetConfig.WarzoneProps.Tent = { ModelAssetId = 182529039 }`. When a server starts, `VisualAssetService` loads the model:
1. It tries `InsertService:LoadAsset(id)`, then `AssetService:LoadAssetAsync(id)`.
2. It strips scripts, seats, movers, joints, prompts and sounds.
3. It welds the model onto our Part kit.

If loading fails, the failure is cached and the Part kit stays. Each server makes at most **48 load attempts**, and a failed id still uses one. With owner decision D1 the setting **Game Settings › Security › "Allow Loading Third Party Assets" stays OFF**. Roblox's docs (InsertService:LoadAsset, AssetService.AllowInsertFreeAssets) then allow only assets that are "created or owned by the game creator", "shared by the asset owner" or "owned by Roblox".

| Who made the asset | Loads with the switch OFF? | What the owner / Grok must click |
|---|---|---|
| **Roblox** (creator "Roblox", User 1): the cars, Weapons Kit, Synty packs, animations | Yes ("owned by Roblox") | Nothing |
| **Roblox Resources** group 3529469 (models) | Not guaranteed: it is a group, not the Roblox account | Treat as Get Model (only used here as backups) |
| **Any other creator** (free Creator Store model) | Only once the game creator owns it | **Get Model**, logged in as the account that owns the experience (below) |
| **ProSoundEffects / APMOfficial** audio (Roblox's licensed library) | Plays by id in any experience | Nothing (listen before wiring) |
| **Animations** | Only Roblox-owned or owner-owned animations play | Nothing: this sheet lists only Roblox-owned ones |
| **Images and meshes set by id** (a texture, a SpecialMesh) | Not blocked by the switch | Nothing: this sheet uses only engine files and Roblox-owned or Roblox Resources images |
| **Engine files** `rbxasset://…` | Only if the file ships in the client | Nothing: every path here was found in the client file list |

**The Get Model click, exactly:**
1. Log in on roblox.com as the account that owns WAR EMPIRE: the same account that publishes it.
2. Open `https://create.roblox.com/store/asset/<id>`.
3. Check that the page shows the store name and creator from this sheet and says **Free**. If a price shows, stop.
4. Press **Get Model**. It may also read "Get" or "Add to Inventory".
5. The button changes to show you own it. It now appears in Studio › Toolbox › Inventory.

**If the experience belongs to a group,** a Get Model on a personal account does not count, because the game creator is the group. Then use only the Roblox-owned picks and the Part kits, or bake (B). Step 1 of §5 finds this out.

### B. Baking into the repo (a fallback, not the default)

Baking means:
1. Insert the model in Studio.
2. Delete its scripts.
3. Right-click › **Save to File…** as `.rbxmx`.
4. Commit the file under `assets/` so the game ships the model inside the place, and nothing has to load at runtime.

**A Rojo build does not keep anything inserted by hand in Studio.** `rojo build -o dist/WarEmpire-PERF.rbxlx` writes a fresh place from `default.project.json`. That file maps only `ReplicatedStorage.Shared`, `ServerScriptService.Server`, `StarterPlayerScripts.Client`, two Workspace/HttpService properties and nothing else: there is no `assets` folder and no `ServerStorage` entry. A model dropped into the place in Studio is gone after the next build and publish. It survives only if its `.rbxmx` is in the repo and mapped.

Proposed follow-up for the lead (not done, `default.project.json` untouched):

```
assets/
  models/   <Key>.rbxmx     -> ServerStorage.WE_AssetTemplates   (world and vehicle dress; CLAUDE.md wants templates in ServerStorage)
  weapons/  <Key>.rbxmx     -> ReplicatedStorage.WE_WeaponTemplates (clients need gun models)
```

```json
"ServerStorage": {
  "$className": "ServerStorage",
  "WE_AssetTemplates": { "$path": "assets/models" }
},
```
and inside the existing `"ReplicatedStorage"` block: `"WE_WeaponTemplates": { "$path": "assets/weapons" }`. `VisualAssetService` would then look for `ServerStorage.WE_AssetTemplates[<Key>]` before calling LoadAsset.

**Licence blocker (checked today):** `origin` = github.com/shaunbirrell/Padel-AI is **public**, while `warempire` is private, and CLAUDE.md says to push to both. A `.rbxmx` of a store model in a public repo is a copy handed out outside Roblox. The Creator Store Terms ("for use on the Services") and Roblox's Limited Use License do not allow that, and neither does the Synty grant ("anything you want to create on Roblox"). **So: do not bake until the lead makes Padel-AI private or stops pushing `assets/` to it.** Until then use runtime loading only.

Bake only when:
- the experience is group-owned and a third-party pick is wanted; or
- a model needs a hand edit that code cannot make, such as removing a painted sign.

Never bake a Roblox-owned pick just because you can: it already loads.

### Rules for anyone wiring ids (Grok included)

1. Never turn "Allow Loading Third Party Assets" on. Never buy anything.
2. Wire only ids from this sheet. Never type an id from memory or from a search result.
3. Wire a third-party id only after the owner's Get Model **and** a `WE_CHECK OK` line from the Studio check (§5). A failed id still burns one of the 48 load attempts per server.
4. No real-world names, insignia, flags or brand text on any model. Look at all sides in Studio.
5. Config is changed in the repo, never in Studio, because a Rojo build overwrites Studio edits. Every new id gets a row in `docs/ASSET_LICENSES.md` in the same commit.
6. Store titles never appear in the game: some audio titles name real products.

## 2. Legend

- **P0 / P1 / P2:** now / next / later.
- **Grok action · Wire** (last column):
  - `NONE`: nothing to click; include the id in the Studio check. `GET`: the owner account presses Get Model. `PREVIEW`: listen in Studio first.
  - `NOW`: a config edit alone makes it show once the id loads. `CODE`: the lead's code change (§6) must land first. `OWNER`: the owner's yes/no comes first.
- **Creator:** `(U id)` = user account, `(G id)` = group, `badge` = Roblox verified badge. ProSoundEffects is User 7462895450, APMOfficial is User 7462718749.
- **Verified** (every id on 2026-09-24): `E` = economy details (name, creator, type, price, dates), `T` = toolbox v2 (`scr` = scripts, tris, votes), `V1` = toolbox v1 (Endorsed). `parsed` = the researchers downloaded and read the file. Audio lengths were measured by the audio researcher.
- **Licence** codes:
  - `RBX`: Roblox-owned (creator Roblox, User 1).
  - `RBX-LUL`: Roblox-owned kit under Roblox's Limited Use License. Roblox-only; keep the attribution in `docs/ASSET_LICENSES.md`.
  - `RBX-S`: Roblox-owned Synty pack. Roblox staff post (DevForum 1283755): "completely free to use in anything you want to create on Roblox".
  - `RR`: image from the Roblox Resources group 3529469 (Roblox's official group).
  - `PSE` / `APM`: Roblox's licensed sound library (Pro Sound Effects / APM Music). Free inside Roblox experiences, **not in YouTube or TikTok promos**.
  - `ENG`: an engine file that ships with every client.
  - `E`: free third-party model that Roblox has Endorsed (Creator Store Terms: use on Roblox).
  - `CS`: free third-party model (Creator Store Terms: use on Roblox).
  - `AP`: `CS` plus the author's written permission, quoted in the row. Credit the author.

## 3. The picks

### 3.1 Clear now (config only, no store clicks)

Set each key to the value shown. With "Allow Loading Third Party Assets" OFF these ids load only if the owner once pressed Get Model on them, so for most players nothing changes on screen; clearing them removes real-world copies and phone-killers, and frees load attempts for the Roblox-owned picks. `StructureVisualConfig.Palettes.MissileDefense.MeshAssetId` was already set to 0 in commit 7474a7c (checked).

| P | Keys | Id today | Store name (creator) | Why | Set to |
|---|---|---|---|---|---|
| P0 | `Characters.HeavyInfantry` | 14776506955 | Army of Soldiers (Rthro) (takinuptoomuchspace) | 484,133 tris, 840 scripts, a whole swarm pack welded onto every 3rd field NPC | 0 |
| P0 | `MapDressing.DesertMesa, Landmarks.DesertMesa` | 12809476227 | Desert Mountain (falterize) | 156,326 tris for one horizon prop; World v2 uses Terrain | 0 |
| P0 | `DesertProps.DesertRock, MapDressing.DesertRock (MeshId)` | 6562523344 | Low Poly Rocks Pack (GYPLA6) | third-party MeshPart (type 40) applied straight by id, so it skips the Third-Party switch | MeshId = 0 |
| P0 | `GateDefense.SandbagNest` | 8980890767 | 88th machine gun nest (ValentiusSenatus) | 100,126 tris on every gate | 0 (Part kit) |
| P0 | `Vehicles.MilitaryJeep, UtilityQuad, ScoutCar, ReconBuggy, DispatchCar` | 125916936788670 | Military Car Vehicle War Wheel Armored Model (BlitzxbCyberl36) | copy of a real 4x4 (Humvee look), 98,067 tris, 13 scripts, 2026 keyword title | 0 (Roblox LUV after code, §3.2) |
| P0 | `Vehicles.LightTank, CombatIFV, AssaultIFV, BridgeLayer, MineClearer, FlameCarrier, LightScoutTank` | 76055078503396 | Tank Military Vehicle War Machine Roleplay Combat (wimundefined0) | copy of a real IFV (Bradley look); the same model is re-uploaded by several accounts | 0 |
| P0 | `Vehicles.PatrolTruck, ArmoredTruck, SupplyTruck` | 105503568352704 | Army Truck Military Vehicle Transport Mesh PBR (Bella29_0Ghost591530) | copy of a real army truck (FMTV look), 34,358 tris, 24 scripts | 0 |
| P0 | `Vehicles.AmmoCarrier, MissileTruck, RadarTruck` | 81802040484766 | Army Truck Military Vehicle Transport Mesh Pbr (Rocket1h202) | same mesh as 105503568352704 from another 2026 account, 20 scripts | 0 |
| P0 | `Vehicles.TroopTransport` | 4128346779 | Army Truck (Mesh) (bearduckmonkey) | copy of a real 4x4 (Humvee look) | 0 |
| P0 | `Vehicles.APC, InfantryCarrier, CommandVehicle, WheeledIFV, AmphibiousAPC` | 17835143223 | APC (2Varu) | copy of a real MRAP, 119,089 tris, 14 scripts | 0 |
| P0 | `Vehicles._FallbackJet, FighterJet, InterceptorJet, TrainerJet, ReconPlane, LightFighter` | 4865838 | fighter jet (stinkyturkey) | copy of a real fighter (F-15 look), 6 scripts | 0 |
| P0 | `Vehicles.StrikeJet, CASJet, StealthStrikeJet, StealthStrike` | 5507592781 | fighter jet model (no script) (berkobero) | copy of a real fighter (F/A-18 look), 26,924 tris | 0 |
| P0 | `Vehicles.StrikeBomber, CargoPlane, AWACSPlane, TankerPlane, HeavyBomber, StrategicBomber` | 3319732457 | war plane (the_epicpokemon) | WW2 fighter (Mustang look) used even for the cargo plane, 34,432 tris | 0 |
| P0 | `Vehicles.AttackHelicopter, NightAttackHeli, GunshipHeli, StealthHeli, EscortHeli` | 295607934 | Attack Helicopter (12904) | looks like a vehicle from a game franchise (Halo 'Hornet'), 10 scripts | 0 |
| P1 | `Vehicles.Corvette, Frigate, CarrierEscort` | 12794395111 | Multipurpose Frigate (teunboy3) | 263,332 tris, 93 MeshParts | 0 |
| P1 | `Vehicles.TransportHeli, HeavyLiftHeli, VTOLTransport` | 9753309 | Elite Force Gunship (pieman711) | 2009 build, 15 scripts, odd look | 0 |
| P1 | `Vehicles.LightTransportHeli, LightScoutHeli, RescueHeli, UtilityHeli, MedevacHeli` | 5935419 | gunship (liger0223) | 2008 build, 7 scripts, 17,858 tris | 0 |
| P1 | `Vehicles.MediumTank` | 26007709 | free tank (august999) | crude 2010 brick build, 2 scripts | 0 |
| P1 | `Vehicles._FallbackWheeled, AntiAirTruck, CargoVan, RecoveryTruck, EscortTruck` | 28912351 | Military Vehicle Meshes (Catmando) | tiny 2010 meshes | 0 (CargoVan/EscortTruck get Roblox cars after code) |
| P1 | `Vehicles.SPAAG` | 15618784436 | AA gun (itsJambles) | a towed AA gun used as a tracked vehicle | 0 |
| P1 | `Vehicles.MortarCarrier, MobileArtillery, HowitzerTruck, SiegeMortar` | 10286064243 | Howitzer (ParanoidType) | a towed howitzer used as a self-propelled vehicle | 0 |
| P1 | `Vehicles._FallbackNaval, RiverBoat, MissileBoat, MineLayer, CoastalMonitor, SubSurfaceRunner, AttackSub` | 15786579439 | Boat (BRicey763) | a rowboat, 1 script | 0 |
| P1 | `Vehicles.PatrolBoat, CoastCutter, Gunboat` | 557152593 | Navy Patrol Boat (Zolteks) | 20,240 tris (over the 12k boat budget) | 0 |
| P1 | `MapDressing.AsphaltDecal (MeshId)` | 10197707775 | asphalt road texture (ZePurpleCat) | third-party Decal applied by id; the roads already use Material Asphalt | MeshId = 0 |

Also P0 in `SoundConfig`: six keys point at two engine files that are not in the current client (see §3.5, first six rows).

### 3.2 Vehicles

Roblox's own cars are the only clean store vehicles. They are Roblox-owned, Endorsed and free, and they load with no clicks. The researchers downloaded and parsed all four; the judge re-read their top-level variant names today.

**Do not wire them until code change C1 (§6) lands.** Each file holds 3–4 colour variants, each with a physics `Chassis`, at about twice our kit size. Today's loader would weld all of them, stacked, at full size. The config lines to paste after C1 are in §6.


| P | Slot | What | Asset ID | Store name | Creator | Type | Free | Verified | Licence | Mobile note | Backup ID | Grok · Wire |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| P0 | `Vehicles.MilitaryJeep, ScoutCar, DispatchCar, ArmedJeep (+ KitFamilyFallback.WheeledLight)` | Light 4x4 body; ArmedJeep keeps our Part-kit gun<br>child: `Light Utility Vehicle (green camo)` | **6418221666** | Light Utility Vehicle | Roblox (U 1, badge) | Model | Yes | E+T+V1: 16 scr, 41,647 tris, 291/9 votes, Endorsed, 2021-02-19, parsed | RBX | Weld only the `Body` sub-model: 39 MeshParts, ~10.4k tris; scale ~0.5 to the 8.5-stud kit; drop Chassis/Scripts/Effects | 6433272094 (`Dune Buggy (beige)`) | NONE · CODE |
| P1 | `Vehicles.ReconBuggy, UtilityQuad` | Buggy / quad body<br>child: `Dune Buggy (beige)` | **6433272094** | Dune Buggy | Roblox (U 1, badge) | Model | Yes | E+T+V1: 12 scr, 43,753 tris, 194/6 votes, Endorsed, 2021-02-23, parsed | RBX | Body: 23 MeshParts, ~14.6k tris, no Decals (over the proposed 12k; fine at 1-2 on screen) | 6418221666 (`Light Utility Vehicle (white camo)`) | NONE · CODE |
| P1 | `Vehicles.PatrolTruck, EscortTruck` | Light truck / technical<br>child: `Pickup Truck (bronze)` | **6418225759** | Pickup Truck | Roblox (U 1, badge) | Model | Yes | E+T+V1: 12 scr, 50,516 tris, 186/14 votes, Endorsed, 2021-02-19, parsed | RBX | Body: 41 MeshParts, ~16.8k tris; skip the 2 door-mirror meshes to reach 39 parts | 6418221666 (`Light Utility Vehicle (green camo)`) | NONE · CODE |
| P1 | `Vehicles.CargoVan` | Van<br>child: `Van (white)` | **6433316269** | Van | Roblox (U 1, badge) | Model | Yes | E+T+V1: 12 scr, 30,544 tris, 192/8 votes, Endorsed, 2021-02-23, parsed | RBX | Body: 26 MeshParts, ~10.2k tris, no Decals | 6418225759 (`Pickup Truck (bronze)`) | NONE · CODE |

**Every other vehicle family keeps our Part kit (decision).** Reason: Roblox publishes no tank, helicopter, plane or boat. The free third-party ones are crude Part builds of about the same quality as our kits, with 0 votes, unknown part counts (their files need a login) and often over the 40-part cap; they would also lose our team paint roles. If the owner still wants to try one, the last column is the single best candidate found (verified today); it needs Get Model and a Studio check (<= 40 parts, no insignia) before the lead wires it.

| Family (VehicleConfig ids) | Decision | Optional trial id (store name, creator, tris, scripts) | Its backup |
|---|---|---|---|
| WheeledTruck, except the 3 Roblox-car keys (ArmoredTruck, SupplyTruck, FuelTanker, EngineeringTruck, MissileTruck, AntiAirTruck, FlatbedHauler, AmmoCarrier, RadarTruck, TroopTransport, RecoveryTruck) | Part kit (keep) | 4003497610 (Truck Military, Developer_Dinosaur, 1,184 tris, 0 scripts) | 9610961269 (Military Troop Truck) |
| WheeledAPC (APC, InfantryCarrier, CommandVehicle, WheeledIFV, AmphibiousAPC) | Part kit (keep) | 917876972 (Armoured Vehicle [MODEL][CAR][DRIVALBE], MrTankas, 4,226 tris, 0 scripts) | 17194892633 (APC) |
| TrackedIFV (CombatIFV, AssaultIFV, BridgeLayer, MineClearer, FlameCarrier) | Part kit (keep) | NOT FOUND (none clean) | - |
| TrackedMBT (LightTank, MediumTank, BattleTank, HeavyTank, TankDestroyer, AssaultGun, LightScoutTank, SuperHeavyTank, FortressTank) | Part kit (keep) | NOT FOUND (none clean) | - |
| TrackedSPAAG (SPAAG, MobileSAM) | Part kit (keep) | 104943756684666 (Light AA Tank, mohd0719, 8,728 tris, 0 scripts) | - |
| TrackedArtillery (MortarCarrier, MobileArtillery, RocketArtillery, HowitzerTruck, SiegeMortar, RailgunCarrier) | Part kit (keep) | NOT FOUND (none clean) | - |
| HeliLight + HeliTransport (LightScoutHeli, RescueHeli, UtilityHeli, TransportHeli, HeavyLiftHeli, LightTransportHeli, MedevacHeli, VTOLTransport) | Part kit (keep) | 12056249019 (Helicopter, Cleverpanda999, 2,864 tris, 0 scripts) | 9182541662 (Attack helicopter [PROP2]) |
| HeliAttack (GunshipHeli, AttackHelicopter, EscortHeli, NightAttackHeli, StealthHeli) | Part kit (keep) | NOT FOUND (none clean) | - |
| JetFighter + JetStrike (FighterJet, InterceptorJet, TrainerJet, ReconPlane, LightFighter, StrikeJet, CASJet, StealthStrike) | Part kit (keep) | 3553891209 (Fighter Jet concept, PlanesFun56, 3,032 tris, 0 scripts) | 16195404708 (Fighter Jet) |
| JetBomber (StrikeBomber, HeavyBomber, StrategicBomber) | Part kit (keep) | NOT FOUND (none clean) | - |
| JetTransport (CargoPlane, AWACSPlane, TankerPlane) | Part kit (keep) | 4513675629 (Cargo plane, notorious_adb, 1,324 tris, 0 scripts) | - |
| NavalPatrol + NavalGun (PatrolBoat, FastAttackCraft, RiverBoat, CoastCutter, TorpedoBoat, Gunboat, MissileBoat, MineLayer, CoastalMonitor) | Part kit (keep) | 294684042 (Boat, MrGreystone, 1,578 tris, 0 scripts) | - |
| NavalLanding (LandingCraft, AssaultLanding, HoverTransport, HospitalShip, SupplyShip, AmphibAssault) | Part kit (keep) | 4713159177 (landing craft set, DiSdo0daGraPh_XD, 2,088 tris, 0 scripts) | 12767797942 (sea landing craft) |
| NavalCapital + NavalSub (Corvette, Destroyer, Frigate, CarrierEscort, Cruiser, Battleship, MissileCruiser, FleetCarrier, SubSurfaceRunner, AttackSub) | Part kit (keep) | NOT FOUND (none clean) | - |

### 3.3 Guns, grenade and rocket

There is no gun model in the game today, so these need code change C4 (§6) first.

**Roblox's Weapons Kit guns** are uploaded by the Roblox account itself (User 1): Endorsed, free, created 2020-04-01. They load with no clicks. Each item holds 3 colour-variant Tools. The judge's picks:
- The visual is `Tool[ToolName].Model[child]`; 6 scripts per item get stripped.
- **Drop the kit's own Sounds.** They are owned by a user and a group, not Roblox; use the §3.5 sounds instead.

**Look-alike call (judge):**
- **Auto Rifle** (AK-style silhouette) and **Rocket Launcher** (RPG-style tube): `OWNER` yes/no. If no, they keep Part-kit models.
- **Pistol, SMG, Shotgun and Sniper:** accepted. They are generic enough, and they are Roblox's own unnamed models licensed to us.


| P | Slot | What | Asset ID | Store name | Creator | Type | Free | Verified | Licence | Mobile note | Backup ID | Grok · Wire |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| P0 | `WeaponConfig StarterRifle` | Rifle in hand (grey variant)<br>child: `Tool "AR2" > Model "AR"` | **4842207161** | Auto Rifle | Roblox (U 1, badge) | Model | Yes | E+T+V1: 6 scr, 5,511 tris, 870/130 votes, Endorsed, 2020-04-01, parsed | RBX-LUL | ~1.8k tris per gun | 96131146947811 | NONE · OWNER+CODE |
| P0 | `WeaponConfig AssaultRifle` | Rifle in hand (dark variant)<br>child: `Tool "AR3" > Model "AR"` | **4842207161** | Auto Rifle | Roblox (U 1, badge) | Model | Yes | E+T+V1: 6 scr, 5,511 tris, 870/130 votes, Endorsed, 2020-04-01, parsed | RBX-LUL | ~1.8k tris | 96131146947811 | NONE · OWNER+CODE |
| P0 | `WeaponConfig Pistol` | Sidearm<br>child: `Tool "Pistol3" > Model "Pistol" (tan)` | **4842197274** | Pistol | Roblox (U 1, badge) | Model | Yes | E+T+V1: 6 scr, 4,410 tris, 1640/360 votes, Endorsed, 2020-04-01, parsed | RBX-LUL | ~1.5k tris | 118912302094201 | NONE · CODE |
| P0 | `WeaponConfig SMG` | SMG<br>child: `Tool "SMG2" > Model "SMG" (tan)` | **4842212980** | Submachine Gun | Roblox (U 1, badge) | Model | Yes | E+T+V1: 6 scr, 4,614 tris, 1720/280 votes, Endorsed, 2020-04-01, parsed | RBX-LUL | ~1.5k tris | 119916677125479 | NONE · CODE |
| P0 | `WeaponConfig Shotgun` | Pump shotgun<br>child: `Tool "Shotgun2" > Model "Shotgun" (tan)` | **4842215723** | Shotgun | Roblox (U 1, badge) | Model | Yes | E+T+V1: 6 scr, 5,946 tris, 656/144 votes, Endorsed, 2020-04-01, parsed | RBX-LUL | ~2.0k tris | 104068096273092 | NONE · CODE |
| P0 | `WeaponConfig Sniper` | Bolt-action rifle<br>child: `Tool "Sniper2" > Model "Sniper" (olive)` | **4842218829** | Sniper Rifle | Roblox (U 1, badge) | Model | Yes | E+T+V1: 6 scr, 6,246 tris, 770/230 votes, Endorsed, 2020-04-01, parsed | RBX-LUL | ~2.1k tris | 83137776064772 | NONE · CODE |
| P0 | `WeaponConfig RocketLauncher` | Shoulder launcher (also HeavyInfantry)<br>child: `Tool "Rocket Launcher" > Model "RocketLauncher"` | **4842186817** | Rocket Launcher | Roblox (U 1, badge) | Model | Yes | E+T+V1: 6 scr, 3,930 tris, 546/154 votes, Endorsed, 2020-04-01, parsed | RBX-LUL | ~1.3k tris | 123935881517645 | NONE · OWNER+CODE |
| P1 | `WeaponConfig Grenade (new AssetRef MeshId+TextureId)` | Frag grenade in hand and in flight: a Part + SpecialMesh<br>child: `texture 232379808` | **232379763** | MESH_ArmyGuy_Grenade | Roblox (U 1, badge) | Mesh | n/a | E: 2015-03-31, mesh read | RBX | 1,350 tris; 1-4 in flight | 4842201032 | NONE · CODE |
| P1 | `Rocket in flight (new key Weapons.RocketProjectile)` | Rocket projectile: Part + SpecialMesh<br>child: `texture 94689966` | **94690081** | MESH_BattleGameRocketLauncherAmmo | Roblox (U 1, badge) | Mesh | n/a | E: 2012-10-09, mesh read | RBX | 336 tris | 4842186817 | NONE · CODE |

Backup ids for the six guns are the identical copies published by the Roblox Resources group on 2026-07-06; they are group-owned, so they need Get Model and are only for the case where a 4842… id fails the Studio check.

### 3.4 Animations

Only animations owned by Roblox or by the game owner play in the game. Every id below is type Animation, creator Roblox (User 1), re-checked today.

They need code first: the player weapon-animation controller (roadmap W2) and the `SoldierRig` (W6a). Ids today go into a new `SoldierAnims` config table.


| P | Slot | Use | Asset ID | Store name | Backup ID (name) |
|---|---|---|---|---|---|
| P0 | `Player.RifleHold` | idle holding a rifle (kit) | **3972151362** | RifleHold | 3972164452 (NewRifleAim) |
| P0 | `Player.RifleReload` | reload, used for every gun | **3972131105** | RifleReload | none |
| P1 | `Player.RifleAimDownSights` | aim down the sights | **3972157449** | NewRifleADS | 4713633512 (Soldier Assault Rifle Aim) |
| P1 | `Player.PistolHold` | one-hand hold (stand-in) | **507768375** | R15Tool | 3972164452 (NewRifleAim) |
| P1 | `Player.LauncherHold` | shoulder aim (stand-in) | **3972164452** | NewRifleAim | 3972157449 (NewRifleADS) |
| P1 | `Player.GrenadeThrow` | overhand swing (stand-in) | **522635514** | R15 Sword Slash | 522638767 (R15 Sword Lunge) |
| P1 | `NPC.Idle` | idle | **507766388** | R15Idle | 2510196951 (Rthro Idle1 Animation) |
| P1 | `NPC.Walk` | walk | **507777826** | R15Walk | 2510202577 (Rthro Walk Animation) |
| P1 | `NPC.Run` | run | **507767714** | R15Run | 2510198475 (Rthro Run Animation) |
| P1 | `NPC.Aim` | rifle aim (NPC kit) | **4713633512** | Soldier Assault Rifle Aim | 3972164452 (NewRifleAim) |
| P1 | `NPC.Fire` | rifle fire (NPC kit) | **4713811763** | Soldier Assault Rifle Fire | none |
| P2 | `NPC.Sit` | vehicle seats, benches | **2506281703** | SitV2 | none |
| P2 | `NPC.Salute` | salute (face tracks ignored on non-dynamic heads) | **10714389988** | Salute Face | 507770239 (R15Wave) |
| P1 | `NPC.Crouch (training-yard T-pose fix)` | NOT FOUND | - | - | owner authors it in the Animation Editor (or ragdoll); search: "crouch" |
| P2 | `NPC.Die / Player.Death` | NOT FOUND | - | - | owner authors it in the Animation Editor (or ragdoll); search: "death animation r15  (use a ragdoll instead)" |

### 3.5 Sounds (`SoundConfig.Sounds`)

Every id below is an Audio asset owned by ProSoundEffects (User 7462895450), APMOfficial (User 7462718749) or Roblox (User 1). It is free, has no scripts, and needs no Get.
- "existing" keys already play through `AudioController`/`AudioHooks`, so a config edit is enough (`NOW`).
- "new" keys need a caller in code (`CODE`).
- Lengths come from the audio researcher, who decoded each file; the judge re-checked owner and type today.
- **Listen before wiring** (Studio › Toolbox › Creator Store › Audio › search the id). Nobody has listened yet.

**First six rows (P0):** `rbxasset://sounds/electronicpingshort.wav` and `rbxasset://sounds/switch.wav` are **absent** from the Roblox client file list, build 0.740.0.7400927. The judge fetched it and searched it today. The client's `content/sounds` folder holds only 11 files. So these six keys are almost certainly silent now. `MissileController.luau:73` uses the same missing file.


| P | Key | Kind · note | Asset ID | Store name | Lic | Length | Backup ID | Wire |
|---|---|---|---|---|---|---|---|---|
| P0 | `UI.Click` | fix · replaces the missing built-in ping; 0.14 s | **9119717523** | Switch Click On Or Off Toggle Button 2 (SFX) | PSE | 0.23 s | 9119717529 | NOW |
| P0 | `UI.Notify` | fix · replaces the missing built-in switch.wav | **9113880475** | Computer Keyboard Beep 3 (SFX) | PSE | 0.29 s | 9116731065 | NOW |
| P0 | `Toast.Warn` | fix · Pitch 0.8 | **9116731065** | Metallic Beeps Quick Tones 6 (SFX) | PSE | 1.12 s | 9113880475 | NOW |
| P0 | `Toast.Error` | fix · MaxSeconds 0.5 | **9113652301** | Buzz Click Sci Fi Alert 2 (SFX) | PSE | 1.23 s | 9113085665 | NOW |
| P0 | `UI.Denied` | fix · MaxSeconds 0.4 | **9113085665** | Alarm Buzzer 3 (SFX) | PSE | 0.98 s | 9113652301 | NOW |
| P0 | `Capture.Start` | fix · radio sweep, 2.0 s | **9118009787** | Radar Static Sweeping Signal 7 (SFX) | PSE | 2.39 s | 9116731065 | NOW |
| P0 | `Weapon.StarterRifle.Fire` | new · 3D, MaxSeconds 0.9, one crack + echo | **9113188870** | Assault Rifle 2 (SFX) | PSE | 2.57 s | 9113188670 | CODE |
| P0 | `Weapon.AssaultRifle.Fire` | new · 3D, MaxSeconds 0.9 | **9113188876** | Assault Rifle 4 (SFX) | PSE | 2.35 s | 9113198012 | CODE |
| P0 | `Weapon.SMG.Fire` | new · 3D, MaxSeconds 0.18, Pitch 1.12-1.2 | **9113029219** | 9 Mm Gun Firing 5 (SFX) | PSE | 1.42 s | 9116335273 | CODE |
| P0 | `Weapon.Pistol.Fire` | new · 3D, MaxSeconds 1.0 | **9117400889** | Pistol Single Shots 8 (SFX) | PSE | 2.67 s | 9117402631 | CODE |
| P0 | `Weapon.Shotgun.Fire` | new · 3D, MaxSeconds 1.2; preview (may hold 2 blasts) | **9112912936** | 12 Gauge Shotgun 101 (SFX) | PSE | 2.77 s | 9112912106 | CODE |
| P0 | `Weapon.Sniper.Fire` | new · 3D, MaxDistance 400 | **9118173988** | Rifle Single Shots 3 (SFX) | PSE | 3.07 s | 9118173739 | CODE |
| P0 | `Weapon.RocketLauncher.Fire` | new · 3D, MaxSeconds 1.5; also heli rocket pods | **9118592471** | Rocket Flare Out 9 (SFX) | PSE | 2.33 s | 9118591402 | CODE |
| P0 | `Weapon.Reload.Rifle` | new · mag out 0.05 s, mag in 0.84 s | **9113104509** | Ammo Magazine 3 (SFX) | PSE | 1.27 s | 9113104358 | CODE |
| P0 | `Weapon.Empty` | new · dry-fire click, MaxSeconds 0.25 | **9117396530** | Pistol Handling 1 (SFX) | PSE | 0.82 s | 9119717523 | CODE |
| P0 | `Hit.Confirm` | new · 2D, Pitch 1.4, cooldown 0.06 | **9119717529** | Switch Click On Or Off Toggle Button 1 (SFX) | PSE | 0.23 s | 9120149994 | CODE |
| P0 | `Hit.Kill` | new · 2D ding, 0.9 s (judge pick; preview) | **9126073001** | Synth Sparkle Tone High Pitch Bell Tone Ding (SFX) | PSE | 1.16 s | 9120149994 | CODE |
| P0 | `Explosion.Small` | new · grenade, rocket, cannon hit; MaxDistance 400 | **9114086583** | Dirt Explosion 4 (SFX) | PSE | 1.87 s | 9116973611 | CODE |
| P0 | `Explosion.Large` | new · missile strike, building destroyed; one roar | **9114554567** | Gas Fire Explosion 3 (SFX) | PSE | 4.03 s | 9114362389 | CODE |
| P1 | `Level.Up` | swap · fanfare instead of the shared coin jingle | **1845411858** | Top Prize | APM | 4.81 s | 9041815872 | NOW |
| P1 | `Capture.Secured` | swap · MaxSeconds 5.4 | **1836473422** | Victory Fanfare Sting | APM | 9.98 s | 1844259840 | NOW |
| P1 | `Capture.Lost` | swap · MaxSeconds 5 + 0.5 s fade | **1848015457** | Accepting Defeat StingA | APM | 11.19 s | 9040342348 | NOW |
| P1 | `Alarm.Raid` | swap · MaxSeconds 3 | **9113089565** | Alarm Tone 2 Tone Fast High Low Switching 2 (SFX) | PSE | 17.5 s | 9118805749 | NOW |
| P1 | `Alarm.Base` | swap · klaxon | **9119663309** | Submarine Alarm Klaxon 4 (SFX) | PSE | 2.33 s | 9119662238 | NOW |
| P1 | `Music.Combat` | swap · drum bed instead of a second march; loop 1.15-59.4 s | **1841476670** | Drums of Combat a | APM | 61.9 s | 1841116989 | NOW |
| P1 | `Amb.Surf` | swap · 33 s rolling waves instead of one 8.4 s wave | **9120621776** | Waves Rolling 2 (SFX) | PSE | 33.13 s | 9119677305 | NOW |
| P1 | `Engine.Heavy` | swap; preview · tracked; Pitch 0.7-1.1; has small air hisses | **9112768762** | Diesel Train 1 (SFX) | PSE | 27.01 s | 6417179625 | NOW |
| P1 | `Engine.Heli` | swap; preview · a real loop (0.25-24.9 s) instead of a take-off one-shot | **9114502655** | Flutter Drone Constant 1 (SFX) | PSE | 25.05 s | 9113417759 | NOW |
| P1 | `Engine.Jet` | swap · jet whine instead of a car loop; loop 0.9-33.6 s | **9116930984** | Mini Jet Car 1 (SFX) | PSE | 34.77 s | 9116930986 | NOW |
| P1 | `Engine.Naval` | swap · bow wash; loop 0-36 s | **9112750448** | Bow Wash Slow Trolling Speed 1 (SFX) | PSE | 36.01 s | 9112780932 | NOW |
| P1 | `Engine.Truck` | new · trucks and APCs (the old Engine.Heavy file) | **6417179625** | Sedan_Loop_Low | RBX | 7.09 s | 6417138409 | CODE |
| P1 | `Vehicle.Start` | new · 2D, driver only | **6417189222** | Veh Sedan Police Car Startup 01 | RBX | 2.78 s | 6414492911 | CODE |
| P1 | `Vehicle.MG.Fire` | new · vehicle MGs, MaxSeconds 0.6 | **9116335315** | Machine Gun 5 (SFX) | PSE | 2.36 s | 9116335036 | CODE |
| P1 | `Vehicle.HMG.Fire` | new · RoofHMG, JeepHMG; Pitch 1.1 | **9118174271** | Rifle Single Shots 7 (SFX) | PSE | 3.7 s | 9118174270 | CODE |
| P1 | `Vehicle.Cannon.Fire` | new · Pitch 0.75-0.85 | **9117893507** | Pressure Blast 25 (SFX) | PSE | 0.99 s | 9116973350 | CODE |
| P1 | `Weapon.Grenade.Throw` | new · pin pull | **9114659833** | Grenade Pull Pin 2 (SFX) | PSE | 0.33 s | 9114659662 | CODE |
| P1 | `Weapon.Reload.Pistol` | new | **9113104176** | Ammo Magazine 1 (SFX) | PSE | 1.28 s | 9113104337 | CODE |
| P1 | `Weapon.Reload.Shotgun` | new · pump; also after each blast | **9112913564** | 12 Gauge Shotgun 9 (SFX) | PSE | 0.58 s | 9112910701 | CODE |
| P1 | `Weapon.Reload.Launcher` | new | **9118594324** | Rockets Handle 6 (SFX) | PSE | 0.96 s | 9118594086 | CODE |
| P1 | `Weapon.Equip` | new · 2D, local player | **9114702107** | Gun Grab Hard 1 (SFX) | PSE | 1.33 s | 9114701864 | CODE |
| P1 | `Impact.Ground` | new · sand; most hits on this map | **9118768193** | Sand Impacts 5 (SFX) | PSE | 0.69 s | 9118768256 | CODE |
| P1 | `Impact.Metal` | new · bullet on a vehicle | **9119915230** | Tank Impact 1 (SFX) | PSE | 1.32 s | 9118168962 | CODE |
| P1 | `Player.Hurt` | new · low volume | **9113524237** | Body Impact 2 (SFX) | PSE | 0.53 s | 9113487543 | CODE |
| P1 | `Base.BuildComplete` | new · at the structure | **9125672726** | Metal Impact Sledge Hammer Hits On 5 Ft I- B (SFX) | PSE | 1.26 s | 9114756916 | CODE |
| P1 | `Hit.Headshot` | reuse Hit.Confirm at Pitch 1.8 (no separate file) | - | - | - | - | - | - |
| P1 | `Player.Death` | reuse Explosion.Distant low, or none; search 'death stinger' | - | - | - | - | - | - |
| P1 | `Vehicle.Repair` | NOT FOUND - search 'ratchet wrench' (Creator Store > Audio, creator ProSoundEffects) | - | - | - | - | - | - |
| P1 | `Missile.Launch` | reuse Weapon.RocketLauncher.Fire at Pitch 0.7 | - | - | - | - | - | - |
| P1 | `Event.PlaneFlyover` | reuse Jet.Flyby; search 'propeller plane pass by' for a prop plane | - | - | - | - | - | - |
| P1 | `Event.CrateLand` | NOT FOUND - search 'wooden crate drop' | - | - | - | - | - | - |

**Keep as they are (already in SoundConfig, re-verified):** `Alarm.Missile` 9113073742 "Air Raid Siren Old Fashioned 1 (SFX)" (backup 9113073796); `Toast.Success / Toast.Reward / Cash.Collect` 9113849492 "Coins Or Keys Jingle 6 (SFX)" (backup 9126073001); `Cash.Purchase` 9113728042 "Cash Register 1 (SFX)" (backup 9113728049); `Music.Base` 1844397606 "Military March" (backup 1847070557); `Amb.Wind` 9114057104 "Desert Wind Whistley Light Gusts 1 (SFX)" (backup 9114057128); `Engine.Ground` 6417138409 "Sedan_Loop_Mid" (backup 9112787430).

**P2 keys (same checks passed; full rows in the JSON):** `Weapon.Grenade.Bounce` 9114659492 (backup 9114659519); `Weapon.Reload.Sniper` 9116357348 (backup 9116357355); `Impact.Structure` 9113632382 (backup 9113632248); `Impact.Water` 9119479010 (backup `rbxasset://sounds/impact_water.mp3`); `Bullet.Flyby` 9118168273 (backup 9113634361); `Vehicle.Stop` 6417192842 (backup 6417198859); `Vehicle.Rocket.Flyby` 9126009936 (backup 9126009951); `Missile.Incoming` 9117089870 (backup 9117089818); `Explosion.Vehicle` 9114361597 (backup 9114361404); `Explosion.Nuke (NukeConfig.Audio)` 9125934722 (backup 9114224354); `Explosion.Distant` 9114362625 (backup 9113169432); `Engine.HeliStart` 9113417759 (backup 9113417552); `Jet.Flyby` 9114888034 (backup 9114888141); `Event.SupplyChute` 9117235033 (backup 9117234408); `Event.Start (stinger)` 9043545266 (backup 136549606529536); `Flag.Flap` 9114461561 (backup 9113716929); `Amb.Battle` 9113169264 (backup 9113169259); `Amb.OilRig` 9112839504 (backup 9112838465); `Amb.Harbor` 9112773041 (backup 9112790194); `Weapon.Casing` 9114312801 (backup 9114312855).

### 3.6 Effects (VFX textures)

No model ids are needed here. Every primary is an engine texture that ships in every client, or an image owned by Roblox or by the Roblox Resources group; those are used by id and need no Get. The Weapons Kit's own effect images belong to users, so the judge replaced them as backups.

Phone rules:
- use `Emit(n)` bursts only;
- at most 16 tracers from a pool;
- no casings or bullet holes on touch devices;
- only the local player's vehicle makes dust or wake.

The code is the planned WeaponFx relay.


| P | Slot | Primary | Store name (creator, type, created) | Lic | Backup | Note |
|---|---|---|---|---|---|---|
| P0 | `Vfx.MuzzleFlash` | `…/particles/sparkles_main.dds` | engine file (in client 0.740) | ENG | `…/particles/fire_main.dds` | 8-point star 128 px; Emit(1) |
| P0 | `Vfx.Tracer (Beam texture)` | **17581858560** | Images/spark_mb (Roblox Resources (G 3529469, badge), Image, 2024-05-23) | RR | Beam with no texture (LightEmission 1) | 256x64 PNG, 1 KB; pool max 16 |
| P0 | `Vfx.Impact.Dust (sand hit)` | `…/particles/smoke_main.dds` | engine file (in client 0.740) | ENG | 16830667309 | tint sand; Emit(6) |
| P0 | `Vfx.Explosion.Fireball` | `…/explosion.png` | engine file (in client 0.740) | ENG | `…/particles/explosion01_core_main.dds` |  |
| P0 | `Vfx.Explosion.Shockwave` | `…/particles/explosion01_shockwave_main.dds` | engine file (in client 0.740) | ENG | 16811365086 |  |
| P0 | `Vfx.RocketTrail` | `…/particles/fire_main.dds` | engine file (in client 0.740) | ENG | `…/particles/smoke_main.dds` | fire + smoke, same as the kit rocket |
| P1 | `Vfx.Impact.Spark (metal hit)` | `…/particles/fire_sparks_main.dds` | engine file (in client 0.740) | ENG | 17082061238 |  |
| P1 | `Vfx.Explosion.Flash` | `…/particles/explosion01_implosion_main.dds` | engine file (in client 0.740) | ENG | `…/glow.png` |  |
| P1 | `Vfx.Smoke (wreck)` | `…/particles/smoke_main.dds` | engine file (in client 0.740) | ENG | 16830673704 |  |
| P1 | `Vfx.Fire (wreck)` | `…/particles/fire_main.dds` | engine file (in client 0.740) | ENG | 17581858560 |  |
| P1 | `Vfx.Dust (wheels)` | `…/particles/smoke_main.dds` | engine file (in client 0.740) | ENG | 16808075391 | local vehicle only on phones |
| P1 | `Vfx.Splash` | **16829556885** | Images/splash_med_dense (1) (Roblox Resources (G 3529469, badge), Image, 2024-03-22) | RR | 16808075391 | 512 px, 168 KB |
| P1 | `Vfx.BulletHole` | `…/whiteCircle.png` | engine file (in client 0.740) | ENG | none (skip on phones) | dark-tinted Decal, 4 s life, pooled |
| P2 | `Vfx.SplashRing` | **16811365086** | Images/water_splash_ring (3) (Roblox Resources (G 3529469, badge), Image, 2024-03-20) | RR | `…/particles/explosion01_shockwave_main.dds` |  |
| P2 | `Vfx.Wake` | **4787437624** | Sprite-WaterFoam (Roblox (U 1, badge), Image, 2020-03-16) | RBX | 16808804567 | 512x1024, 445 KB; local boat only |
| P2 | `Vfx.Debris` | **17082061238** | Images/debris (1) (Roblox Resources (G 3529469, badge), Image, 2024-04-09) | RR | `…/particles/fire_sparks_main.dds` | 1024 px, 545 KB: use the backup on phones |
| P2 | `Vfx.Scorch` | `…/particles/explosion01_smoke_main.dds` | engine file (in client 0.740) | ENG | `…/whiteCircle.png` |  |
| P2 | `MoneyBagFX / VfxSparkles (collect burst)` | `…/particles/sparkles_main.dds` | engine file (in client 0.740) | ENG | 4221608224 | particle burst in code; 4221608224 needs GET |

`…/` = `rbxasset://textures/`.

### 3.7 Base and plot props (keys the game already calls)

These keys already have callers (MapSetup, GateDefenseService, PlotOilPumpService, BaseService, MoneyCollectorService and others).
- A third-party pick shows **once the owner has pressed Get Model and the config line is set** (`NOW`).
- A Synty (Roblox-owned) pick needs code change C1 (`CODE`).
- Nothing scales props today (finding F6), so the Studio check prints each model's size. The lead fits scale in C1.


| P | Slot | What | Asset ID | Store name | Creator | Type | Free | Verified | Licence | Mobile note | Backup ID | Grok · Wire |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| P1 | `WarzoneProps.Tent` | Training-yard squad tent | **182529039** | Military Canvas Tent | Quenty (U 4397833, badge) | Model | Yes | E+T+V1: 0 scr, 3,908 tris, 2610/390 votes, Endorsed, 2014-10-15 | E | 3,908 tris, Part-built: Studio check <= 40 parts | 10154832053 | GET · NOW |
| P1 | `WarzoneProps.TentAlt` | Tent fallback | **10154832053** | Army tent | YourFellowProto (U 776309125) | Model | Yes | E+T+V1: 0 scr, 920 tris, 10/0 votes, 2022-07-08 | CS | 920 tris | - | GET · NOW |
| P1 | `WarzoneProps.Crate (+ alias Drum)` | Wooden supply crate<br>child: `Meshes/PolygonDungeon_Props_SM_Prop_Crate_Wood_04` | **6933790012** | Synty Dungeon Pack: Weapons & Props | Roblox (U 1, badge) | Model | Yes | E+T+V1: 0 scr, 141,121 tris, 282/18 votes, Endorsed, 2021-06-10, piece 598 tris | RBX-S | 1 MeshPart, 598 tris | 182451181 | NONE · CODE |
| P1 | `WarzoneProps.MilitaryCrate (+ alias Pallet)` | Olive supply box | **976333542** | Military Crate | sam_youwell (U 48259852) | Model | Yes | E+T+V1: 0 scr, 1,196 tris, 65/5 votes, 2017-08-12 | CS | 1,196 tris, 65/5 votes (current id: keep) | 2930926216 | GET · NOW |
| P1 | `WarzoneProps.Sandbag, GateDefense.Sandbags, GateDefense.SandbagNest` | Sandbag walls and gate MG nest | Part kit (keep) | - | - | - | - | - | - | store sandbags are 5.5k-7.5k tris per piece; our Part-kit bags are a few parts | 5678434293 | NONE · NOW |
| P1 | `WarzoneProps.OilBarrel (+ IndustrialProps.OilBarrel, alias Fence)` | Steel drum | Part kit (keep) | - | - | - | - | - | - | a 1-part cylinder is as good as any store drum and costs no load | 23153991 | NONE · NOW |
| P1 | `WarzoneProps.JerseyBarrier, WarzoneProps.ConcreteBarrier, MapDressing.JerseyBarrier` | Concrete road barrier | **2766525411** | road barrier | SiameseMouse (U 795584330) | Model | Yes | E+T+V1: 0 scr, 368 tris, 665/35 votes, 2019-01-20 | CS | 368 tris, 665/35 votes | 4165296048 | GET · NOW |
| P1 | `WarzoneProps.JerseyBarrierAlt, MapDressing.JerseyBarrierAlt` | Barrier fallback | **4165296048** | Concrete Barrier Mesh | usercontent0 (U 244620904) | Model | Yes | E+T+V1: 0 scr, 408 tris, 18/2 votes, 2019-10-19 | CS | 1 MeshPart, 408 tris | - | GET · NOW |
| P1 | `IndustrialProps.OilPumpjack (PlotOilPumpConfig key)` | Plot oil pump | **15192621369** | Oil Rig / Pumpjack | sadfiacs (U 1607785544) | Model | Yes | E+T+V1: 0 scr, 1,398 tris, 2023-10-28 | CS | 1,398 tris, 0 scripts | Part kit | GET · NOW |
| P1 | `MoneyCollectorFallback (ATM)` | Cash machine at the base | **175462478** | ATM | Famlica (U 3033770) | Model | Yes | E+T+V1: 0 scr, 94 tris, 2014-08-31 | AP | 94 tris, 0 scripts; author: 'just give me some credit' (credit Famlica) | Part kit | GET · NOW |
| P1 | `CashCrate` | Supply-drop cash crate | Part kit (keep) | - | - | - | - | - | - | clear 16803204916 (a part of another creator's tycoon kit, 4 scripts) | 182451181 | NONE · NOW |
| P1 | `DesertProps.Palm, MapDressing.Palm` | Date palm | **10562894034** | Palm Tree (Realistic) | Natalie_Clabo (U 95773772, badge) | Model | Yes | E+T+V1: 0 scr, 316 tris, 279/21 votes, 2022-08-12 | CS | 1 palm, 3 MeshParts, 316 tris, 279/21 votes | 5517265199 | GET · NOW |
| P1 | `DesertProps.PalmAlt, MapDressing.PalmAlt` | Palm fallback<br>child: `pick a palm by Size (all 9 children are named 'MeshPart')` | **5517265199** | Low Poly Desert Pack | iucag (U 76135100) | Model | Yes | E+T+V1: 0 scr, 6,917 tris, 9/1 votes, 2020-08-07 | AP | pack of 9 MeshParts, 6,917 tris | - | GET · CODE |
| P1 | `DesertProps.Cactus, DesertProps.CactusBase, MapDressing.Cactus` | Saguaro cactus | **5074211161** | Low-Poly Cactus | Exp_p (U 70054066) | Model | Yes | E+T+V1: 0 scr, 250 tris, 8/2 votes, 2020-05-23 | CS | 1 MeshPart, 250 tris | 5517265199 | GET · NOW |
| P1 | `DesertProps.DesertPlants, MapDressing.DesertPlants` | Dry desert bush<br>child: `Meshes/PolygonNature_Plant_Bush_03` | **6933438443** | Synty Nature Pack | Roblox (U 1, badge) | Model | Yes | E+T+V1: 0 scr, 108,816 tris, 768/32 votes, Endorsed, 2021-06-09, piece 100 tris | RBX-S | 1 MeshPart, 100 tris; recolour dry olive | 5003870763 | NONE · CODE |
| P2 | `WarzoneProps.CamoNet` | Camo net over a gun pit (bases only) | **13437018139** | Ghillie Net | Crank_theTank (U 1033859378) | Model | Yes | E+T+V1: 0 scr, 6,652 tris, 2023-05-14 | CS | 1 MeshPart, 6,652 tris: at most 1 per base | Part kit | GET · NOW |
| P2 | `WarzoneProps.Flag, WarzoneProps.FlagPole, UpgradeFlag` | Bare flag pole (our own colour cloth) | **1679839739** | Flag Pole | HerrDirektorZach (U 155340865) | Model | Yes | E+T+V1: 0 scr, 792 tris, 2018-04-28 | CS | 792 tris; pole only, no national flag | Part kit | GET · NOW |
| P2 | `WarzoneProps.Floodlight` | Base floodlight | Part kit (keep) | - | - | - | - | - | - | clear 116763933 (no thumbnail, 1 script, brings its own light) | 4893998573 | NONE · NOW |
| P2 | `TutorialArrow / TutorialArrowAlt` | Tutorial arrow | **1143305733** | Blinking Tutorial Arrow | MajorMent (U 427326013) | Model | Yes | E+T+V1: 2 scr, 40 tris, 2017-10-30 | CS | 40 tris; 2 scripts are stripped | 6333395014 | GET · NOW |

### 3.8 World v2 props (only where a store mesh saves parts)

The World v2 spec builds man-made props from our own Part kits and every rock from Terrain, so this list is short. Every row is one MeshPart taken from a **Roblox-owned Synty pack**: one pack load serves every row from that pack. Nothing needs Get.

These rows need the WorldPOI/WorldKits builders and C1. Proposed keys go in a new `VisualAssetConfig.DesertKit` table. Child names contain "/", so the lead must use `pack:FindFirstChild(ChildName, true)` and never split the name on "/". Clearing `TextureID` and setting `Color` gives the flat desert palette.


| Pack id | Store name | Creator | Type | Free | Verified | Licence |
|---|---|---|---|---|---|---|
| **6933438443** | Synty Nature Pack | Roblox (U 1, badge) | Model | Yes | E+T+V1: 0 scr, 108,816 tris, 768/32 votes, Endorsed, 2021-06-09 | RBX-S |
| **6933556508** | Synty City Pack | Roblox (U 1, badge) | Model | Yes | E+T+V1: 0 scr, 256,709 tris, 960/40 votes, Endorsed, 2021-06-09 | RBX-S |
| **6933790012** | Synty Dungeon Pack: Weapons & Props | Roblox (U 1, badge) | Model | Yes | E+T+V1: 0 scr, 141,121 tris, 282/18 votes, Endorsed, 2021-06-10 | RBX-S |

| P | Prop (World v2 kit) | Pack | Child name | Piece tris, size (studs) | Backup (pack · child · tris) | Grok |
|---|---|---|---|---|---|---|
| P1 | Dead tree (nested inside Meshes/Leaves_Tree_Dead_02: take only this branch mesh) | 6933438443 | `branches_tree_dead02` | 212, 2.5x12.1x3.3 | 6933438443 · `PolygonNature_Tree_Pine_Dead_01` · 310 | NONE · CODE |
| P1 | Stump | 6933438443 | `PolygonNature_Tree_Stump_03` | 222, 4.0x6.8x3.8 | 6933438443 · `PolygonNature_Tree_Stump_01` · 114 | NONE · CODE |
| P1 | Fallen log | 6933438443 | `PolygonNature_Tree_Log_02` | 288, 2.8x3.5x11.7 | 6933438443 · `PolygonNature_Tree_Stump_01` · 114 | NONE · CODE |
| P1 | Crate stack (World v2 yards) (same piece as WarzoneProps.Crate) | 6933790012 | `PolygonDungeon_Props_SM_Prop_Crate_Wood_04` | 598, 3.7x3.7x3.7 | 6933556508 · `PolygonCity_Props_SM_Prop_Pallet_01` · 228 | NONE · CODE |
| P1 | Burnt car wreck (clear TextureID, Color (45,42,40), CorrodedMetal; <= 6 per 512-stud circle) | 6933556508 | `PolygonCity_Props_SM_Veh_Car_Sedan_01` | 5524, 7.6x5.3x18.0 | 6933556508 · `PolygonCity_Props_SM_Veh_Car_Small_01` · 5674 | NONE · CODE |
| P1 | Van / truck wreck (same treatment) | 6933556508 | `PolygonCity_Props_SM_Veh_Car_Van_01` | 5665, 8.6x7.1x17.6 | 6933556508 · `PolygonCity_Props_SM_Veh_Car_Medium_01` · 6578 | NONE · CODE |
| P2 | Rubble / pebbles (CanCollide false) | 6933438443 | `PolygonNature_Terrain_Rubble_Pebbles_01` | 168, 6.3x0.9x6.3 | 6933438443 · `PolygonNature_Terrain_DustPile_Long_01` · 64 | NONE · CODE |
| P2 | Distant mesa (only if Terrain is not enough) (scale x3-4; replaces the 156k-tri mesa) | 6933438443 | `PolygonNature_Terrain_Mountain_02` | 819, 95.5x54.1x95.5 | 6933438443 · `PolygonNature_Terrain_Mountain_03` · 913 | NONE · CODE |
| P2 | Oasis reeds | 6933438443 | `PolygonNature_Plant_Reeds_01` | 135, 2.0x3.3x1.9 | 6933438443 · `PolygonNature_Plant_Reeds_02` · 168 | NONE · CODE |
| P2 | Oasis broad-leaf bush | 6933438443 | `PolygonNature_Plant_PalmBush_01` | 400, 5.5x6.0x3.6 | 6933438443 · `PolygonNature_Plant_07` · 522 | NONE · CODE |
| P2 | Dune grass (scale x4-6) | 6933438443 | `PolygonNature_Plant_Grass_04` | 330, 0.7x0.6x0.3 | 6933438443 · `PolygonNature_Plant_Grass_02` · 238 | NONE · CODE |
| P2 | Town bench | 6933556508 | `PolygonCity_Props_SM_Prop_ParkBench_01` | 552, 7.2x3.6x2.2 | 6933556508 · `PolygonCity_Props_SM_Prop_PicnicTable_01` · 322 | NONE · CODE |
| P2 | Skip / bin | 6933556508 | `PolygonCity_Props_SM_Prop_Skip_02` | 1352, 8.4x6.4x4.6 | 6933556508 · `PolygonCity_Props_SM_Prop_Trashbin_02` · 244 | NONE · CODE |

All child names start with `Meshes/` (dropped above for width); pass the full name, e.g. `Meshes/PolygonNature_Tree_Stump_03`.

### 3.9 Soldiers and NPC looks

**No store id is recommended for soldiers.** `TryAttachCharacterVisual` removes the Humanoid and joints and welds the model rigidly, so any character id becomes a sliding statue: the owner's complaint. The fix is the planned `SoldierRig` (W6a), which needs no id:
- **Body:** the engine's R15 body from `Players:CreateHumanoidModelFromDescription(HumanoidDescription.new(), R15)`.
- **Gear and colour:** our Part-kit helmet and vest, colours from `SoldierConfig`.
- **Guns and animations:** the §3.3 guns and the §3.4 animations.

| P | Keys | Decision | Why |
|---|---|---|---|
| P0 | `Characters.HeavyInfantry` | 0 now (§3.1) | 484k tris, 840 scripts |
| P1 | `Characters.Soldier`, `Infantry`, `Worker`, `WorkerFallback`, `Guard`, `BankGuard`, `OilRigGuard`, `FortGuard`, `GateGuard`, `GateDefense.Guard` | Set all to 0 in the same commit as the SoldierRig. **Before that:** clear them now only if Grok's live log (§5 step 3) shows `LoadAsset failed` for 100212659702941, 9104381136 and 16134469614, which means no visual change. | 20k–50k tris each against a proposed 6k budget, and they are statues. 16134469614 is listed as a "SWAT soldier", which is a Design P0 reject. |
| P1 | `Characters.SpecialForces`, `CharacterAlt` | keep 0 | Roblox's NPC-kit soldier 3924234975 is a Design P0 reject ("plastic Rthro") and wears green woodland camo |
| P2 | `SoldierConfig.Visual` (new `Pants` field) | optional: 144076760 "Dark Green Jeans" (Roblox, classic Pants, free, OpenUse) | 0 triangles, texture only |


## 4. Do not use

Every id below was looked up today (name and creator as the store shows them). Never wire them. The ids in §3.1 are also on this list; they are not repeated here.

- **Paid:** 119390702773907 "Polygon Military Vehicles" (syntystudio): USD 19.99 (Synty 'Polygon Military Vehicles'); the no-paid rule; 130520448048005 "Lowpoly Army Tanks" (FreeflowStore): USD 2.99.
- **Real-world copy:** 160023719 "Destroyed M4 Sherman" (Jetspeedzz135): named after a real tank; 2473378608 "Destroyed tank" (IncursionFade): same mesh as 160023719; 1207356899 "T-72 Wreck" (ph_enix): named after a real tank.
- **Insignia:** 6779447564 "ABM-54 [ Desert color ]" (aomsen568): white-star national insignia on the hull; 9484605836 "Bomber jet [ Mini ]" (aomsen568): national-style roundel, real bomber outline.
- **Real-world name:** 12613778138 "Warship (USS REDGIO)" (Acelord5050): real navy prefix in the title; 9701862157 "MILITARY PORTABLE LIGHT TOWER" (declan1954): listing: 'used by the american military', 2 scripts; 53591587 "Crate/Box" (griflay): listing text names a real place; 24-tri box (Crate today).
- **Franchise:** 473593782 "Combine APC" (ORV_HanSooyoung): listing: 'APC from HL2' (Half-Life 2); 16694653632 "Hydra Jet" (MateoVc921031L): 'Hydra' franchise vehicle name.
- **Another game:** 7408294148 "Tower Defense Simulator Level # Military Base" (FadingSolstice): taken from Tower Defense Simulator; 10885110806 "TDS Classic Railgun Tank" (TheUltraGuest777): listing: 'from tds kit'; 6253727046 "Background Plane Crash" (XtremGameMaster): listing says it comes from Left 4 Dead.
- **Brand:** 9154880131 "Hesco Barrier" (Niceforme124): 'Hesco' is a trademark; 490315393 "Hesco Barrier" (Zimk): 'Hesco' is a trademark.
- **Brand / design:** 59524622 "Jeep" (Roblox): Roblox 'Jeep': brand word + ROBLOX logo decal; Design P0 reject.
- **Design reject:** 16134469614 "Rigged Soldier" (Gioele_e): listing: 'low poly SWAT soldier' (SWAT is a Design P0 reject); 50,580 tris; 3924234975 "Soldier (Rthro)" (Roblox): Roblox NPC-kit soldier: 'plastic Rthro' Design P0 reject in VisualAssetConfig; green woodland camo.
- **Keyword spam:** 107381977457431 "🪖 Military Light Truck Car Vehicle Army War RP" (XxEpic_IcexX2024): 2026 emoji keyword listing (a truck) used as a floodlight tower; 108525417345747 "🗼 Sniper Tower Military Base Outpost Watchtower" (LightZrCyberGrKing16): 2026 emoji keyword listing, 1 script; 96059329869678 "Palm Trees Realistic Tropical Island Beach Pack" (BellaLion62438): 2026 keyword pack, no mesh summary; 105982075286356 "🌴 Low Poly Palm Tree Coconut Summer Tree isla" (LaylaDawn2564): 2026 emoji listing, 1 script; 76846072091295 "💰 Cash Collector Coins Money Pick Up Simple" (Nora_Hunt3r74): 2026 emoji listing, no mesh summary.
- **Keyword spam / scripts:** 90362241548850 "Tycoon Collector (no Scripts) Factory Money" (RobloxVibeModels): 2026 tycoon collector, 2 scripts; 82560800252069 "Military Vehicle Shed Army Base Bunker Barrack " (4x4basspeep): 2026 listing with a 'Trending Tags' block, 9 scripts, 45k tris.
- **Provenance:** 38451313 "Money Bag" (Copyright): uploader account is named 'Copyright'.
- **Provenance / scripts:** 16803204916 "Cash Crate For Zednov's Tycoon Kit" (asteriiez): made for another creator's tycoon kit, 4 scripts; 8180880144 "Modified Street light [Light version]" (AloysiousCatindoy): 'credits to the original owners', 8 scripts, 24k tris.
- **Scripts:** 35409899 "Tycoon Money Collector(ANCHOR IT!)" (ok3y11): tycoon collector, 5 scripts ('DO NOT EDIT ANY SCRIPTS').
- **Re-upload:** 12651656400 "Sandbag Barrier" (Aheadit): copy of vx0rn's 5678434293.
- **Real-world theme:** 867696371 "Bridge and checkpoint ww2" (Illinois_Lawz): 'ww2' bridge checkpoint.
- **Phone budget:** 6015472062 "Hangar" (afterrburner): 45,887 tris hangar (hard-coded in VisualAssetService); 138331074285379 "Military Base" (VenomStar40066): 232,800 tris (Buildings.CommandCenter; keep the building flag OFF); 18798977801 "Military Barracks" (VoidableCircuit): 336,948 tris (Buildings.Barracks); 12208876851 "hangar" (Eduardowolfalpha2): 202,920 tris (Buildings.VehicleDepot); 4120970784 "Military Barracks, 3 Story's" (ItsJustT_NY): 213,994 tris (Buildings.WeaponsFacility); 16382915010 "Ammo Box" (ajh2k21): 21,472 tris for an ammo box.
- **Phone budget / scripts:** 3133150032 "Military Tent" (MrKotikXD): 38,324 tris, 9 scripts (TentAlt today).
- **40-part cap:** 2652344972 "Military ammo/supplies shed" (F3rwrd): 117 MeshParts; 17701461178 "Shipping Containers" (VGVC2): 126 MeshParts.
- **Not Roblox-owned audio:** 3806349898 "weapon_AR_Firing" (DarthfuzzyX): Weapons Kit rifle shot, owned by a user; do not rely on it; 3821787597 "weapon_AR_Charging_0.2" (DarthfuzzyX): Weapons Kit reload, owned by a user; 1489924400 "Bullet hit" (Corvobyte): Weapons Kit bullet hit, owned by a user; 3963015379 "weapon_RocketLauncher_Explosion_FadeOut_0.2" (Reference Games): Weapons Kit rocket blast, owned by a group.
- **Bad audio:** 9113177810 "Assault Rifle 5 (SFX)" (ProSoundEffects): 'Assault Rifle 5' holds 2-3 shots, so every shot is a double tap.
- **Not Roblox-owned image:** 872910628 "Colored Muzzle Flash" (Guest90260): user image inside the Weapons Kit; 3867967806 "Images/Bullet Tracer Down" (SlartibartfastFjords): user image inside the Weapons Kit; 2463944225 "Images/plasma1" (0xBAADF00D): user image inside the Weapons Kit; 2078626 "bullet_hole_linda_kim_u" (Are92): 2008 user image; 53875997 "scorch" (DarkShadow6): 2011 user image.
- **Unsupported:** 47637 "Rocket Launcher" (Roblox): Roblox 2007 launcher: 'no longer supported', 4 scripts.
- **Off-theme:** 4842190633 "Railgun" (Roblox): sci-fi railgun.
- **Old rig:** 187790284 "Soldier" (Roblox): 2014 R6 soldier; carries a real-world rifle mesh 72012671.

Also never use: anything with a price on its store page; listings with emoji or keyword strings in the title; listings that say "not mine", "credits to" or "from game X", or that name a real vehicle, weapon, unit, country or brand; the Weapons Kit `WeaponsSystem` scripts (its server trusts the client's hit list).

## 5. Step list for Grok (do these in order; report back in the template at the end)

Grok does store clicks, Studio checks and a report. **Grok does not edit repo files or the place.** The lead wires the config (§6) because the repo has pre-commit checks and other workflows are editing the same config files. If the owner wants Grok to write the config lines anyway: only the lines in §6.1, on a branch, as a pull request, after the report is complete.

1. **Who owns the experience.** Creator Dashboard (create.roblox.com/dashboard/creations) › WAR EMPIRE: note whether the owner is a user or a group. Report `OWNER: user <name>` or `OWNER: group <name>`. If it is a group, skip step 4 and say so.
2. **The switch.** Open the place in Studio (from the Creator Dashboard, "Edit in Studio", not a local file) › Home › Game Settings › Security. Confirm "Allow Loading Third Party Assets" is **OFF**. Do not change it. Report `SWITCH: OFF`.
3. **What loads today.** Join the live game on a PC and press F9 › **Server** tab. Type `VisualAssetService` in the filter. Copy every line that contains `Cached catalog model` and every line that contains `LoadAsset failed`, and report them as two lists. Also type `Failed to load` in the filter and copy those lines.
4. **Get Model on the needed ids.** Do this logged in on roblox.com as the account that owns the experience. For each id below, follow the "Get Model click" in §1.A. Before clicking, check that the page shows the same store name and creator as below and **Free**. If anything differs or a price shows, do not click; report `SKIP <id> <what differs>`. Otherwise report `GOT <id>`.

   | Id | Store name | Creator |
   |---|---|---|
   | 182529039 | Military Canvas Tent | Quenty |
   | 10154832053 | Army tent | YourFellowProto |
   | 976333542 | Military Crate | sam_youwell |
   | 2766525411 | road barrier | SiameseMouse |
   | 4165296048 | Concrete Barrier Mesh | usercontent0 |
   | 15192621369 | Oil Rig / Pumpjack | sadfiacs |
   | 175462478 | ATM | Famlica |
   | 10562894034 | Palm Tree (Realistic) | Natalie_Clabo |
   | 5074211161 | Low-Poly Cactus | Exp_p |
   | 13437018139 | Ghillie Net | Crank_theTank |
   | 1679839739 | Flag Pole | HerrDirektorZach |
   | 1143305733 | Blinking Tutorial Arrow | MajorMent |
   | 6333395014 | Arrow pointing down | DyingInisde |

   Also get 182451181 "Wooden Crate" (Quenty): it is the crate used until code change C1 lands.
   - **Only if a primary fails in step 5:** 2930926216 "Military Crates" (XIArchangel), 5517265199 "Low Poly Desert Pack" (iucag), 5003870763 "Low-Poly Bush" (Exp_p).
   - **Only if the owner asks:**
     - 5678434293 "Sandbag Barrier" (vx0rn) and 5678429543 "Sandbags Corner" (vx0rn);
     - 4893998573 "Floodlight" (VladimirDeliyUA);
     - 4221608224 "Sparkles Effect" (favmuva);
     - the vehicle trial ids in §3.2.
   - **Never Get the Roblox-owned ids.** They need nothing.

5. **Studio model check.** Open the live place from the Creator Dashboard. Press **Run** (F8, not Play), so the command bar runs on the server. Paste the block below into the command bar with **list A** and press Enter; then paste it again with **list B**. Copy every line that starts with `WE_CHECK`, plus any red error lines. Press Stop.
   - **List A** (Roblox-owned; each should be OK with no Get): `6418221666, 6433272094, 6418225759, 6433316269, 4842207161, 4842197274, 4842212980, 4842215723, 4842218829, 4842186817, 6933438443, 6933556508, 6933790012, 23153991`
   - **List B** (after step 4): `182529039, 10154832053, 976333542, 182451181, 2766525411, 4165296048, 15192621369, 175462478, 10562894034, 5074211161, 13437018139, 1679839739, 1143305733, 6333395014`

   ```lua
   local ids = {6418221666, 6433272094} -- replace with list A or list B
   local IS, AS = game:GetService("InsertService"), game:GetService("AssetService")
   for _, id in ipairs(ids) do
   	local ok, m = pcall(IS.LoadAsset, IS, id)
   	local via = "InsertService"
   	if not ok then
   		local ok2, m2 = pcall(AS.LoadAssetAsync, AS, id)
   		if ok2 then ok, m, via = true, m2, "AssetService" else m = tostring(m) .. " / " .. tostring(m2) end
   	end
   	if ok and typeof(m) == "Instance" then
   		local n = { parts = 0, mesh = 0, scripts = 0, tools = 0, lights = 0, fx = 0, sounds = 0, humanoids = 0, decals = 0 }
   		for _, d in ipairs(m:GetDescendants()) do
   			if d:IsA("BasePart") then n.parts += 1 end
   			if d:IsA("MeshPart") then n.mesh += 1 end
   			if d:IsA("LuaSourceContainer") then n.scripts += 1 end
   			if d:IsA("Tool") then n.tools += 1 end
   			if d:IsA("Light") then n.lights += 1 end
   			if d:IsA("ParticleEmitter") or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") then n.fx += 1 end
   			if d:IsA("Sound") then n.sounds += 1 end
   			if d:IsA("Humanoid") then n.humanoids += 1 end
   			if d:IsA("Decal") or d:IsA("Texture") then n.decals += 1 end
   		end
   		local kids = {}
   		for i, k in ipairs(m:GetChildren()) do
   			if i <= 6 then table.insert(kids, k.Name) end
   		end
   		local okS, s = pcall(m.GetExtentsSize, m)
   		if not okS then s = Vector3.zero end
   		print(string.format("WE_CHECK OK %d via=%s kids=[%s] parts=%d meshparts=%d scripts=%d tools=%d lights=%d fx=%d sounds=%d humanoids=%d decals=%d size=%.1fx%.1fx%.1f",
   			id, via, table.concat(kids, "|"), n.parts, n.mesh, n.scripts, n.tools, n.lights, n.fx, n.sounds, n.humanoids, n.decals, s.X, s.Y, s.Z))
   		m:Destroy()
   	else
   		print(string.format("WE_CHECK FAIL %d %s", id, tostring(m)))
   	end
   end
   print("WE_CHECK DONE")
   ```

   Nothing is parented to the workspace, so no script inside a model runs. For each list-B model, `parts` must be **40 or less**; if it is more, report it and the lead will not wire it. A Studio `OK` is a strong sign but not final proof: the live server log after publishing (step 9) is.

6. **Studio sound, image and mesh check** (Edit mode is fine). Paste the block and copy every `WE_CONTENT` line. The two `rbxasset://sounds/…wav` lines are expected to say Failure: that confirms the silent-UI finding.

   ```lua
   local list = {
   	"rbxasset://sounds/electronicpingshort.wav", "rbxasset://sounds/switch.wav", "rbxasset://sounds/impact_water.mp3",
   	"rbxassetid://9119717523", "rbxassetid://9113880475", "rbxassetid://9116731065", "rbxassetid://9113652301",
   	"rbxassetid://9113085665", "rbxassetid://9118009787", "rbxassetid://9113188870", "rbxassetid://9113188876",
   	"rbxassetid://9113029219", "rbxassetid://9117400889", "rbxassetid://9112912936", "rbxassetid://9118173988",
   	"rbxassetid://9118592471", "rbxassetid://9113104509", "rbxassetid://9117396530", "rbxassetid://9119717529",
   	"rbxassetid://9126073001", "rbxassetid://9114086583", "rbxassetid://9114554567", "rbxassetid://1845411858",
   	"rbxassetid://1836473422", "rbxassetid://1848015457", "rbxassetid://9113089565", "rbxassetid://9119663309",
   	"rbxassetid://1841476670", "rbxassetid://9120621776", "rbxassetid://9112768762", "rbxassetid://9114502655",
   	"rbxassetid://9116930984", "rbxassetid://9112750448",
   	"rbxassetid://232379763", "rbxassetid://232379808", "rbxassetid://94690081", "rbxassetid://94689966",
   	"rbxassetid://17581858560", "rbxassetid://16829556885", "rbxassetid://16811365086", "rbxassetid://4787437624",
   }
   game:GetService("ContentProvider"):PreloadAsync(list, function(id, status)
   	print("WE_CONTENT", status.Name, id)
   end)
   print("WE_CONTENT DONE")
   ```

   Then **listen** to the P0 sounds and the "(preview)" sounds in Studio › Toolbox › Creator Store › Audio (paste the id). Report one line per key: `LISTEN <key> OK` or `LISTEN <key> BAD <why>`. Watch especially for 9112912936 (might hold two blasts), 9114502655 (does it sound like a rotor?), 9112768762 and 9126073001.

7. **Studio animation check.** Press **Run** (F8), paste the block and copy every `WE_ANIM` line plus any "Failed to load animation" lines. Press Stop.

   ```lua
   local ids = {3972151362, 3972131105, 3972157449, 507768375, 3972164452, 522635514, 507766388, 507777826, 507767714, 4713633512, 4713811763, 2506281703, 10714389988}
   local rig = game:GetService("Players"):CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
   rig.Parent = workspace
   local hum = rig:FindFirstChildOfClass("Humanoid")
   local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
   for _, id in ipairs(ids) do
   	local a = Instance.new("Animation")
   	a.AnimationId = "rbxassetid://" .. id
   	local ok, tr = pcall(animator.LoadAnimation, animator, a)
   	local t0 = os.clock()
   	while ok and tr.Length == 0 and os.clock() - t0 < 6 do task.wait(0.1) end
   	print(string.format("WE_ANIM %s %d length=%.2f", (ok and tr.Length > 0) and "OK" or "FAIL", id, ok and tr.Length or 0))
   end
   rig:Destroy()
   print("WE_ANIM DONE")
   ```

8. **Look check** for each model you got in step 4. Use a **new empty Baseplate place**, not the game place. Insert each one from Toolbox › Inventory and turn the camera all the way round it. Report one line per id: `LOOK <id> insignia=Y/N flag=Y/N text=Y/N real_copy=Y/N note=<short>`. Delete the model afterwards and close that place without publishing.
9. **After the lead publishes the change** (§6): repeat step 3 on the live game and report the new `Cached catalog model` / `LoadAsset failed` lines. This is the final proof that the ids load.

**Report template (paste exactly, fill every line):**

```
WAR EMPIRE ASSET CHECK <date> by Grok
OWNER: user <name> | group <name>
SWITCH: OFF
LIVE_LOADED: <ids from "Cached catalog model" lines>
LIVE_FAILED: <ids from "LoadAsset failed" lines>
LIVE_OTHER_ERRORS: <"Failed to load" lines, or none>
GOT: <id> <id> ...
SKIP: <id> <reason> (or none)
<all WE_CHECK lines, list A then list B>
<all WE_CONTENT lines>
<all WE_ANIM lines>
LISTEN <key> OK|BAD <why>   (one per key)
LOOK <id> insignia=N flag=N text=N real_copy=N note=...   (one per got id)
OWNER_ANSWER rifle_ak_look=YES|NO launcher_rpg_look=YES|NO
```

## 6. What the lead wires once Grok reports

### 6.1 Config only (one commit; merge after the other workflow's `VisualAssetConfig` / `SoundConfig` edits land)

1. **§3.1 clears.** Set every listed key to 0 or `MeshId = 0`. Every clear is safe even before Grok reports: the Part kit takes over.
2. **SoundConfig P0 (six Ids).** Also delete the now unused `ENG_PING` / `ENG_SWITCH` locals.
   - `["UI.Click"].Id = 9119717523`
   - `["UI.Notify"].Id = 9113880475`
   - `["Toast.Warn"].Id = 9116731065` (Pitch 0.8)
   - `["Toast.Error"].Id = 9113652301` (MaxSeconds 0.5)
   - `["UI.Denied"].Id = 9113085665` (MaxSeconds 0.4)
   - `["Capture.Start"].Id = 9118009787`
3. **SoundConfig P1 swaps**, after `LISTEN … OK`:
   - `Level.Up` 1845411858
   - `Capture.Secured` 1836473422 (MaxSeconds 5.4)
   - `Capture.Lost` 1848015457 (MaxSeconds 5)
   - `Alarm.Raid` 9113089565 (MaxSeconds 3)
   - `Alarm.Base` 9119663309
   - `Music.Combat` 1841476670
   - `Amb.Surf` 9120621776
   - `Engine.Heavy` 9112768762
   - `Engine.Heli` 9114502655
   - `Engine.Jet` 9116930984
   - `Engine.Naval` 9112750448
4. **Props.** Wire each one only if the report shows `GOT <id>` and a `WE_CHECK OK` with parts ≤ 40 and a clean `LOOK`:

```lua
-- WarzoneProps
Tent = { ModelAssetId = 182529039 } :: AssetRef,
TentAlt = { ModelAssetId = 10154832053 } :: AssetRef,
Crate = { ModelAssetId = 182451181 } :: AssetRef,
Drum = { ModelAssetId = 182451181 } :: AssetRef,
MilitaryCrate = { ModelAssetId = 976333542 } :: AssetRef, -- unchanged id
JerseyBarrier = { ModelAssetId = 2766525411 } :: AssetRef,
JerseyBarrierAlt = { ModelAssetId = 4165296048 } :: AssetRef,
ConcreteBarrier = { ModelAssetId = 2766525411 } :: AssetRef,
Sandbag = { ModelAssetId = 0 } :: AssetRef,
Sandbags = { ModelAssetId = 0 } :: AssetRef,
OilBarrel = { ModelAssetId = 0 } :: AssetRef,
Fence = { ModelAssetId = 0 } :: AssetRef,
CamoNet = { ModelAssetId = 13437018139 } :: AssetRef,
CamoNetAlt = { ModelAssetId = 0 } :: AssetRef,
Floodlight = { ModelAssetId = 0 } :: AssetRef,
Lamp = { ModelAssetId = 0 } :: AssetRef,
FloodlightTower = { ModelAssetId = 0 } :: AssetRef,
-- GateDefense
SandbagNest = { ModelAssetId = 0 } :: AssetRef,
Sandbags = { ModelAssetId = 0 } :: AssetRef,
AutoGun = { ModelAssetId = 0 } :: AssetRef,
AutoGunElevatedAlt = { ModelAssetId = 0 } :: AssetRef,
-- top level
MoneyCollectorFallback = { ModelAssetId = 175462478 } :: AssetRef, -- unchanged id
MoneyCollectorAlts = {},
CashCrate = { ModelAssetId = 0 } :: AssetRef,
MoneyBagFX = { ModelAssetId = 0 } :: AssetRef,
FloodlightTower = { ModelAssetId = 0 } :: AssetRef,
-- DesertProps (and the same values in the MapDressing aliases)
Palm = { ModelAssetId = 10562894034 } :: AssetRef,
PalmAlt = { ModelAssetId = 0 } :: AssetRef,
Cactus = { ModelAssetId = 5074211161 } :: AssetRef,
CactusBase = { ModelAssetId = 5074211161 } :: AssetRef,
-- IndustrialProps
OilPumpjack = { ModelAssetId = 15192621369 } :: AssetRef,
OilPumpjackAlt = { ModelAssetId = 0 } :: AssetRef,
OilBarrel = { ModelAssetId = 0 } :: AssetRef,
```

5. **Hygiene.** Set to 0 every id from §4 that is still in `VisualAssetConfig` or `StructureVisualConfig`. The building ids behind the OFF building flag can wait, but they must never be switched on.
6. **Licences.** Add rows to `docs/ASSET_LICENSES.md` for every id wired: owner, terms, date checked. Credit Famlica (ATM) and, if used, iucag (5517265199). Add the Weapons Kit / Limited Use License notice and the Synty grant.

### 6.2 Code (in this order)

- **C1. `VisualAssetService` AssetRef options, about 30 lines.** Unlocks the 4 Roblox cars (P0), the Synty props and World v2.
  - **New fields:** `ChildName` (find with `FindFirstChild(name, true)`, keep only that child, destroy the rest), `SubModel` (e.g. `"Body"`), `SkipNames` (the Pickup's 2 mirror meshes), `TargetLength` or `Scale` (vehicles are about 2× kit size), `Color` and `ClearTexture`.
  - **Load each pack once** and cache the chosen children.
  - **Keep templates in ServerStorage**, not `ReplicatedStorage.WE_VisualAssetTemplates` (CLAUDE.md; finding F9).
  - **Vehicle config after C1:**

```lua
MilitaryJeep = { ModelAssetId = 6418221666, ChildName = "Light Utility Vehicle (green camo)", SubModel = "Body" } :: AssetRef,
ScoutCar     = { ModelAssetId = 6418221666, ChildName = "Light Utility Vehicle (green camo)", SubModel = "Body" } :: AssetRef,
DispatchCar  = { ModelAssetId = 6418221666, ChildName = "Light Utility Vehicle (green camo)", SubModel = "Body" } :: AssetRef,
ArmedJeep    = { ModelAssetId = 6418221666, ChildName = "Light Utility Vehicle (green camo)", SubModel = "Body" } :: AssetRef,
ReconBuggy   = { ModelAssetId = 6433272094, ChildName = "Dune Buggy (beige)", SubModel = "Body" } :: AssetRef,
UtilityQuad  = { ModelAssetId = 6433272094, ChildName = "Dune Buggy (beige)", SubModel = "Body" } :: AssetRef,
PatrolTruck  = { ModelAssetId = 6418225759, ChildName = "Pickup Truck (bronze)", SubModel = "Body" } :: AssetRef,
EscortTruck  = { ModelAssetId = 6418225759, ChildName = "Pickup Truck (bronze)", SubModel = "Body" } :: AssetRef,
CargoVan     = { ModelAssetId = 6433316269, ChildName = "Van (white)", SubModel = "Body" } :: AssetRef,
```

  `KitFamilyFallback.WheeledLight` already points at `MilitaryJeep`. Every other family falls to 0 and the Part kit, so finding F16 no longer matters.
  - **Also after C1:**
    - `WarzoneProps.Crate` / `Drum` = `{ ModelAssetId = 6933790012, ChildName = "Meshes/PolygonDungeon_Props_SM_Prop_Crate_Wood_04" }`
    - `DesertProps.DesertPlants` = `{ ModelAssetId = 6933438443, ChildName = "Meshes/PolygonNature_Plant_Bush_03", Color = Color3.fromRGB(120, 118, 70) }`
    - `PalmAlt` = 5517265199, with pick-by-size.
- **C2. Strip gaps (finding F8).** Also strip `Light`, `ParticleEmitter`, `Fire`, `Smoke`, `Sparkles`, `Beam` and `Trail` from dress models, with an opt-out flag for effect keys. This unlocks the Roblox barrel 23153991, which carries a Smoke, as the OilBarrel backup.
- **C3. Remove hard-coded ids.** Replace each with a config key or 0:
  - `GateDefenseService.luau:572` (4923345827) and `:632` (fallback 3525056989);
  - `VisualAssetService.luau:624` (hangar 6015472062);
  - `MissileController.luau:73` `SIREN_ID`, the missing engine file: use `Alarm.Missile` or remove it.

  Also route GateDefenseService's own loader through `VisualAssetService`, so it counts against the 48-attempt budget (finding F10).
- **C4. Guns** (`WeaponVisuals.luau`, `WeaponConfig.Weapons[id].VisualAsset`, a new `VisualAssetConfig.Weapons` table or a separate `WeaponVisualConfig`).
  - **Loader:** `LoadAsset(id)` › `Tool[ToolName]` › its Model child. Destroy scripts **and the kit's Sounds**. Keep Attachments, Beams, WeldConstraints and the bolt Motor6D.
  - **Templates** go in ReplicatedStorage, with `CastShadow = false`. The grenade and rocket are a Part plus a SpecialMesh, so add `TextureId` to AssetRef.

```lua
Weapons = {
	StarterRifle   = { ModelAssetId = 4842207161, ToolName = "AR2", Child = "AR", BackupId = 96131146947811 },      -- OWNER yes/no (AK look)
	AssaultRifle   = { ModelAssetId = 4842207161, ToolName = "AR3", Child = "AR", BackupId = 96131146947811 },      -- OWNER yes/no (AK look)
	Pistol         = { ModelAssetId = 4842197274, ToolName = "Pistol3", Child = "Pistol", BackupId = 118912302094201 },
	SMG            = { ModelAssetId = 4842212980, ToolName = "SMG2", Child = "SMG", BackupId = 119916677125479 },
	Shotgun        = { ModelAssetId = 4842215723, ToolName = "Shotgun2", Child = "Shotgun", BackupId = 104068096273092 },
	Sniper         = { ModelAssetId = 4842218829, ToolName = "Sniper2", Child = "Sniper", BackupId = 83137776064772 },
	RocketLauncher = { ModelAssetId = 4842186817, ToolName = "Rocket Launcher", Child = "RocketLauncher", BackupId = 123935881517645 }, -- OWNER yes/no (RPG look)
	Grenade        = { ModelAssetId = 0, MeshId = 232379763, TextureId = 232379808 },
	RocketProjectile = { ModelAssetId = 0, MeshId = 94690081, TextureId = 94689966 },
},
```

- **C5. Combat audio.** Add the new §3.5 keys and their call sites through the planned WeaponFx relay (server to other players, `UnreliableRemoteEvent`). Add optional `LoopStart` / `LoopEnd` fields that set `Sound.LoopRegion`, using the loop times in §3.5.
- **C6. Animations.** A `SoldierAnims` table with the §3.4 ids, a player weapon-animation controller (W2) and the `SoldierRig` (W6a). In the same commit, set every `Characters.*` key to 0 (§3.9).
- **C7. World v2 `DesertKit`.** Rows from §3.8, once WorldPOI/WorldKits exist.
- **C8. Load budget (finding F7).** After the clears, fewer than 30 distinct model ids with live callers remain. Keep `MaxLoadAttempts = 48`, and clear any id the live log reports as failed.
- **C9. Baking** (§1.B): only after the repo-privacy decision.

## 7. What was verified, and what was not

**Verified on 2026-09-24 (by the judge):**
- Economy details for 423 ids.
- Toolbox v2 facts for 220 models, and the Endorsed flag for every model.
- Store thumbnails of the vehicles, guns, NPC-kit soldier and 30 props.
- The variant names inside the 4 Roblox cars and 3 kit guns, read from the researchers' downloads.
- The Synty child names, which exist in the parsed packs.
- The client file list 0.740.0.7400927 for every `rbxasset://` path.
- The public/private status of the two GitHub remotes.
- The Roblox docs text for InsertService:LoadAsset and AssetService.AllowInsertFreeAssets.
- The current repo state: `MissileDefense` MeshAssetId is already 0, and the id-to-key map covers all 99 ids in `VisualAssetConfig`.

**Not verified:**
- **Third-party contents:** real part count, hidden text and authorship. The files need a login. Steps 5 and 8 cover this.
- **How it looks and runs:** whether the scaled Roblox cars look right on our kits, and the frame rate on a mid-range Android phone (Graphics Quality 3).
- **Sound quality:** nobody has listened to any sound yet (step 6).
- **Server-side animation loading:** whether `AnimationTrack.Length` fills in on a Studio Run-mode server for the animation check. If every line says FAIL with no "Failed to load animation" error, the check itself is at fault, not the ids.
- **Live loading:** whether every Roblox-owned id loads on the live server. The docs say it does; step 9 proves it.
- **Nothing was run in Roblox.**

Nation flags come only from `assets/flags` (flag-icons, MIT, rendered by `tools/gen_nation_flags.py`); never wire a flag model or decal from the Creator Store.
