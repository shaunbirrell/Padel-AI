# External asset IDs: owners, terms and why each is allowed

Scope: every non-zero Creator Store ID in `src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau`, plus the
`StructureVisualConfig.Palettes.*.MeshAssetId` IDs and the IDs hard-coded in services (all of them are also config IDs).
Data: Roblox economy API `economy.roblox.com/v2/assets/<id>/details`, read 2026-09-24, and the toolbox stats in
`gap/asset_stats.json` (triangles, scripts). Nothing here was loaded in Roblox. The headless sim is not Roblox.

Owner: CFG (W1) writes this file with `VisualAssetConfig`; LOOK (W3) and W6a update it in the same commit as any ID change;
`tools/wire-asset-ids.py` adds the §3.1 row of every owner pick it promotes (docs/ASSET_WIRING.md).
Last update: owner asset list (assetwire), 2026-09-25 — Roblox-owned picks wired (§3.0: Dune Buggy, Pickup Truck, Van,
Smoking Barrel, the six Weapons Kit guns, the grenade and rocket meshes, and the Synty log, twig and sedan pieces), the three
heavy building models cleared by owner rule 5 (§2d), the owner-picks table added (§3.1, empty until a promote) and the
ownership facts of 2026-09-25 (§1). Before that: W3 LOOK, 2026-09-24 — Roblox-owned packs wired (§3.0), 19 third-party
world-dressing IDs dropped (§2c), and the 24 IDs cleared in 859dedc moved out of §3 (§2b).

## 1. Rules

**How these IDs load.** Owner default D1 keeps Game Settings › Security › "Allow Loading Third Party Assets" **OFF**.
`AssetService:LoadAssetAsync` then loads only assets that Roblox owns (§3.0) or that the game's owner owns or was granted.
WAR EMPIRE belongs to the user shaunie6 (UserId 470626172, games API 2026-09-25), so a third-party ID starts to show once
that account clicks "Get Model" on it (turning the setting on is rejected by D1). Inventory API checks
(`inventory.roblox.com/v1/users/470626172/items/Asset/<id>`, every call HTTP 200):
- 2026-09-25 08:02–08:05 UTC: the owner owns 147 of the 151 ids on his own list (docs/ASSET_WIRING.md), every third-party
  one. Two of them were live config ids and so loaded on live once owned: `GateDefense.AutoGun` 4923345827 (set to 0 =
  Part-built gate gun in the asset-wiring commit, 2026-09-25: MG 34-like, no part cap on that loader) and
  `IndustrialProps.OilPumpjackAlt` 15192621369 (§3, capped loader, kept). The other owner picks wait in `PendingAssetId`, which no loader reads,
  until `tools/wire-asset-ids.py` promotes them (§3.1).
- 2026-09-25 08:39 UTC: none of the other 51 third-party ids in `VisualAssetConfig` / `StructureVisualConfig` is owned, so on
  live each of them fails once, `VisualAssetService` caches the failure, and the Part kit stays.

**Terms for a free Creator Store asset.** The uploader keeps the copyright and grants Roblox a licence that Roblox may
sublicense "to other Users and Creators" (Roblox Terms of Use, Creator Terms, "Roblox License to UGC"). The Creator Store
Terms say assets are published and obtained "for use on the Services" and in Roblox Studio. So: **use inside Roblox
experiences only**. The uploader promises the upload follows the Community Rules and copyright rules; if the uploader did
not have the rights, that promise does not protect us. That is why provenance is part of the test below.

**Why a remaining ID is allowed** (all of these hold for every row in §3 unless the row says otherwise):
1. It is free on the Creator Store today (`IsPublicDomain = true`, not for sale).
2. The listing names no real-world or franchise design: no real vehicle, ship, weapon, unit, brand or country.
3. The listing does not say it is someone else's work or comes from another game.
4. We use it only as optional, non-colliding dress inside Roblox. `VisualAssetService` strips every script, mover, joint,
   seat, prompt and sound before use, and the Part kit stays authoritative for gameplay.
5. We never show its listing name to players; display names come from our own configs.

**Dropped** (W1 CFG, roadmap §1.4 and §2.2 item 5): any ID that fails 1, 2 or 3. Its key stays with `ModelAssetId = 0`, so
the code falls back to the Part kit (vehicles first try their `KitFamilyFallback` body). Keys are kept because callers and
saves use them.

**Adding an ID** needs all of 1–5, plus: no brand or national text on the model (check in Studio), a triangle count that fits
the phone budget, and a row in §3 in the same commit. Prefer Roblox-owned packs (roadmap §4: Synty, Light Utility Vehicle,
Weapons Kit), which load without "Get Model".

## 2. Dropped in W1 CFG (22 IDs)

| Asset ID | Creator Store name | Uploader | Reason | Keys now 0 | Fallback |
|---|---|---|---|---|---|
| [103734805361054](https://create.roblox.com/store/asset/103734805361054) | Realistic Industrial Props Pack | Hyper_verse (User) | Paid (USD 2.99) | `IndustrialProps.IndustrialPack` | Part kit host |
| [108556425657107](https://create.roblox.com/store/asset/108556425657107) | Realistic Desert Plants | 2XQUISITE_DESIGNS (User) | Paid (USD 3.99) | `DesertProps.DesertPlants`, `MapDressing.DesertPlants` | Part kit host |
| [125493544802645](https://create.roblox.com/store/asset/125493544802645) | Wooden Pier and Dock - Curved Ramp | CrimzDevs (User) | Paid (USD 7.99) | `Landmarks.PierAlt` | Part kit host |
| [131322292868756](https://create.roblox.com/store/asset/131322292868756) | Realistic Rusty Pipes Pack | Hyper_verse (User) | Paid (USD 2.99) | `IndustrialProps.RustyPipes` | Part kit host |
| [75368157644109](https://create.roblox.com/store/asset/75368157644109) | Realistic ATM | Benomatrixf (User) | Paid (USD 2.99) | `MoneyCollector` | `MoneyCollectorFallback` 175462478 → alts → Part kit |
| [122068883442022](https://create.roblox.com/store/asset/122068883442022) | Humvee Military Car Army Vehicle | 4oysp (User) | Real-world vehicle ("Humvee") | `Vehicles.ArmedJeep` | WheeledLight → `MilitaryJeep` body (125916936788670), else Part kit |
| [14074034450](https://create.roblox.com/store/asset/14074034450) | S-300 | slavaukraina432 (User) | Real-world system ("S-300") | `Vehicles.MobileSAM` | TrackedSPAAG → `LightTank` body (76055078503396), else Part kit |
| [18406068364](https://create.roblox.com/store/asset/18406068364) | Bm-13n Katyusha | ProFanMax_1022 (User) | Real-world system ("BM-13 Katyusha") | `Vehicles.RocketArtillery` | TrackedArtillery → `LightTank` body (76055078503396), else Part kit |
| [100684175](https://create.roblox.com/store/asset/100684175) | Stalwart M35 Cargo Truck (American Olive) | PandaWithNoName (User) | Real-world truck ("M35", "American") | `Vehicles.FuelTanker`, `Vehicles.EngineeringTruck`, `Vehicles.FlatbedHauler` | WheeledTruck → `_FallbackWheeled` body (28912351), else Part kit |
| [11962508154](https://create.roblox.com/store/asset/11962508154) | High Mobility Missile Launcher | Jestazuk_0101 (User) | Real-world system ("High Mobility … Launcher", HIMARS-type) | `Buildings.MissileDefense` | ⚠ `StructureVisualConfig.Palettes.MissileDefense.MeshAssetId` still holds this ID (§4), then Part kit |
| [2048010298](https://create.roblox.com/store/asset/2048010298) | RM Camicia Nera destroyer | creepercatchanel (User) | Real-world ship ("Camicia Nera", Italian destroyer) | `Vehicles.Destroyer`, `Vehicles.Battleship` | NavalCapital → `LandingCraft` = 0 → Part kit |
| [74585287273804](https://create.roblox.com/store/asset/74585287273804) | ORS Thebe (DD-20) | R0B0XINB0Y_23 (User) | Real-world or franchise ship ("ORS Thebe (DD-20)") | `Vehicles.Cruiser`, `Vehicles.MissileCruiser` | NavalCapital → `LandingCraft` = 0 → Part kit |
| [19297043](https://create.roblox.com/store/asset/19297043) | RHC Mammoth Tank (regen added) | TDFall (User) | Franchise design ("Mammoth Tank", Command & Conquer) | `Vehicles.BattleTank`, `Vehicles.HeavyTank`, `Vehicles.SuperHeavyTank`, `Vehicles.TankDestroyer`, `Vehicles.AssaultGun`, `Vehicles.FortressTank`, `Vehicles.RailgunCarrier` | TrackedMBT → `BattleTank` = 0 → Part kit; `RailgunCarrier`: TrackedArtillery → `LightTank` body (76055078503396) |
| [123239877613650](https://create.roblox.com/store/asset/123239877613650) | Army Soldier Camo Gun Hat Boot Vet US GI RP NPC | taskproccesssing (User) | Real-world unit and country ("US GI") | `Characters.SpecialForces` | `CharacterAlt` = 0 → Part kit |
| [16692908395](https://create.roblox.com/store/asset/16692908395) | WW2 PT boat | Max1212542 (User) | Real-world design ("WW2 PT boat") | `Vehicles.FastAttackCraft`, `Vehicles.TorpedoBoat` | NavalPatrol → `_FallbackNaval` body (15786579439), else Part kit |
| [4851009700](https://create.roblox.com/store/asset/4851009700) | Sniper Soldier | Destroyer4162 (User) | Real-world weapon (listing: soldier "with … an awp") | `Characters.SpecialForcesAlt` | Unused key |
| [111066366655290](https://create.roblox.com/store/asset/111066366655290) | Russian Fuel Tanks Model | Lunaron90 (User) | Country name ("Russian"); keyword-spam listing | `WarzoneProps.FuelTanks` | Part kit host |
| [9993540257](https://create.roblox.com/store/asset/9993540257) | HESCO Barrier Woodland | GTHunter3D (User) | Brand name ("HESCO" is a trademark) | `WarzoneProps.Hesco`, `MapDressing.Hesco` | Part kit host |
| [10121519149](https://create.roblox.com/store/asset/10121519149) | Lantern | withered_chic (User) | Another game's asset (listing: "EXTRACT FROM VERDUN") | `WarzoneProps.Lantern` | Part kit host |
| [121029612](https://create.roblox.com/store/asset/121029612) | Cactus | nycholaos (User) | Not the uploader's work (listing: "made by somebodyelse") | `DesertProps.Cactus`, `MapDressing.Cactus` | Part kit host |
| [71964514000054](https://create.roblox.com/store/asset/71964514000054) | Military Tower with Mounted Gun Prop | F_lashAce (User) | Not the uploader's work (listing: "MADE BY @REWQ"); same mesh as the 2022 upload 10354803684 | `GateDefense.AutoGunElevated` | Unused key |
| [16659447](https://create.roblox.com/store/asset/16659447) | Destructible Movil Bunker Of Battle | ivo3000 (User) | No longer on the Creator Store (toolbox 404, `IsPublicDomain = false`) | `Buildings.Bunker`, `Landmarks.Bunker` | Part kit (no StructureVisualConfig mesh) |

Rows 1–5 are the paid IDs and rows 6–14 the real-world and franchise designs named in `gap/reusable_parts.md` §3. Rows 15–22
were found by the same test on the full listing text in this pass.

### 2b. Cleared in commit 859dedc (asset shortlist §3.1, 24 IDs)

Heavy, real-world copies or franchise looks. Every key is now 0 (the light 4x4s use the Roblox LUV body, §3.0).

| Asset ID | Creator Store name | Uploader | Reason | Keys now 0 | Fallback |
|---|---|---|---|---|---|
| [14776506955](https://create.roblox.com/store/asset/14776506955) | Army of Soldiers (Rthro) | takinuptoomuchspace (User) | 484,133 triangles, 840 scripts (a whole soldier swarm on every 3rd NPC) | `Characters.HeavyInfantry` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [12809476227](https://create.roblox.com/store/asset/12809476227) | Desert Mountain | falterize (User) | 156,326 triangles for one horizon prop; World v2 uses Terrain | `MapDressing.DesertMesa`, `Landmarks.DesertMesa` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [6562523344](https://create.roblox.com/store/asset/6562523344) | Low Poly Rocks Pack | GYPLA6 (User) | third-party MeshPart applied by MeshId, which skips the third-party switch | `DesertProps.DesertRock`, `MapDressing.DesertRock` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [8980890767](https://create.roblox.com/store/asset/8980890767) | 88th machine gun nest | ValentiusSenatus (User) | 100,126 triangles on every gate | `GateDefense.SandbagNest` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [125916936788670](https://create.roblox.com/store/asset/125916936788670) | Military Car Vehicle War Wheel Armored Model | BlitzxbCyberl36 (User) | copy of a real 4x4 (Humvee look), 98,067 triangles, 13 scripts, 2026 keyword title | `Vehicles.MilitaryJeep`, `Vehicles.UtilityQuad`, `Vehicles.ScoutCar`, `Vehicles.ReconBuggy`, `Vehicles.DispatchCar` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [76055078503396](https://create.roblox.com/store/asset/76055078503396) | Tank Military Vehicle War Machine Roleplay Combat | wimundefined0 (User) | copy of a real IFV (Bradley look); the same model is re-uploaded by several accounts | `Vehicles.LightTank`, `Vehicles.CombatIFV`, `Vehicles.AssaultIFV`, `Vehicles.BridgeLayer`, `Vehicles.MineClearer`, `Vehicles.FlameCarrier`, `Vehicles.LightScoutTank` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [105503568352704](https://create.roblox.com/store/asset/105503568352704) | Army Truck Military Vehicle Transport Mesh PBR | Bella29_0Ghost591530 (User) | copy of a real army truck (FMTV look), 34,358 triangles, 24 scripts | `Vehicles.PatrolTruck`, `Vehicles.ArmoredTruck`, `Vehicles.SupplyTruck` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [81802040484766](https://create.roblox.com/store/asset/81802040484766) | Army Truck Military Vehicle Transport Mesh Pbr | Rocket1h202 (User) | same mesh as 105503568352704 from another 2026 account, 20 scripts | `Vehicles.AmmoCarrier`, `Vehicles.MissileTruck`, `Vehicles.RadarTruck` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [4128346779](https://create.roblox.com/store/asset/4128346779) | Army Truck (Mesh) | bearduckmonkey (User) | copy of a real 4x4 (Humvee look) | `Vehicles.TroopTransport` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [17835143223](https://create.roblox.com/store/asset/17835143223) | APC | 2Varu (User) | copy of a real MRAP, 119,089 triangles, 14 scripts | `Vehicles.APC`, `Vehicles.InfantryCarrier`, `Vehicles.CommandVehicle`, `Vehicles.WheeledIFV`, `Vehicles.AmphibiousAPC` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [4865838](https://create.roblox.com/store/asset/4865838) | fighter jet | stinkyturkey (User) | copy of a real fighter (F-15 look), 6 scripts | `Vehicles._FallbackJet`, `Vehicles.FighterJet`, `Vehicles.InterceptorJet`, `Vehicles.TrainerJet`, `Vehicles.ReconPlane`, `Vehicles.LightFighter` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [5507592781](https://create.roblox.com/store/asset/5507592781) | fighter jet model (no script) | berkobero (User) | copy of a real fighter (F/A-18 look), 26,924 triangles | `Vehicles.StrikeJet`, `Vehicles.CASJet`, `Vehicles.StealthStrikeJet`, `Vehicles.StealthStrike` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [3319732457](https://create.roblox.com/store/asset/3319732457) | war plane | the_epicpokemon (User) | WW2 fighter (Mustang look) used even for the cargo plane, 34,432 triangles | `Vehicles.StrikeBomber`, `Vehicles.CargoPlane`, `Vehicles.AWACSPlane`, `Vehicles.TankerPlane`, `Vehicles.HeavyBomber`, `Vehicles.StrategicBomber` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [295607934](https://create.roblox.com/store/asset/295607934) | Attack Helicopter | 12904 (User) | looks like a vehicle from a game franchise, 10 scripts | `Vehicles.AttackHelicopter`, `Vehicles.NightAttackHeli`, `Vehicles.GunshipHeli`, `Vehicles.StealthHeli`, `Vehicles.EscortHeli` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [12794395111](https://create.roblox.com/store/asset/12794395111) | Multipurpose Frigate | teunboy3 (User) | 263,332 triangles, 93 MeshParts | `Vehicles.Corvette`, `Vehicles.Frigate`, `Vehicles.CarrierEscort` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [9753309](https://create.roblox.com/store/asset/9753309) | Elite Force Gunship | pieman711 (User) | 2009 build, 15 scripts | `Vehicles.TransportHeli`, `Vehicles.HeavyLiftHeli`, `Vehicles.VTOLTransport` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [5935419](https://create.roblox.com/store/asset/5935419) | gunship | liger0223 (User) | 2008 build, 7 scripts, 17,858 triangles | `Vehicles.LightTransportHeli`, `Vehicles.LightScoutHeli`, `Vehicles.RescueHeli`, `Vehicles.UtilityHeli`, `Vehicles.MedevacHeli` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [26007709](https://create.roblox.com/store/asset/26007709) | free tank | august999 (User) | crude 2010 brick build, 2 scripts | `Vehicles.MediumTank` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [28912351](https://create.roblox.com/store/asset/28912351) | Military Vehicle Meshes | Catmando (User) | tiny 2010 meshes | `Vehicles._FallbackWheeled`, `Vehicles.AntiAirTruck`, `Vehicles.CargoVan`, `Vehicles.RecoveryTruck`, `Vehicles.EscortTruck` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [15618784436](https://create.roblox.com/store/asset/15618784436) | AA gun | itsJambles (User) | a towed AA gun used as a tracked vehicle | `Vehicles.SPAAG` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [10286064243](https://create.roblox.com/store/asset/10286064243) | Howitzer | ParanoidType (User) | a towed howitzer used as a self-propelled vehicle | `Vehicles.MortarCarrier`, `Vehicles.MobileArtillery`, `Vehicles.HowitzerTruck`, `Vehicles.SiegeMortar` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [15786579439](https://create.roblox.com/store/asset/15786579439) | Boat | BRicey763 (User) | a rowboat, 1 script | `Vehicles._FallbackNaval`, `Vehicles.RiverBoat`, `Vehicles.MissileBoat`, `Vehicles.MineLayer`, `Vehicles.CoastalMonitor`, `Vehicles.SubSurfaceRunner`, `Vehicles.AttackSub` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [557152593](https://create.roblox.com/store/asset/557152593) | Navy Patrol Boat | Zolteks (User) | 20,240 triangles (over the 12k boat budget) | `Vehicles.PatrolBoat`, `Vehicles.CoastCutter`, `Vehicles.Gunboat` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [10197707775](https://create.roblox.com/store/asset/10197707775) | asphalt road texture | ZePurpleCat (User) | third-party Decal applied by id; the roads already use Material Asphalt | `MapDressing.AsphaltDecal` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |

### 2c. Dropped in W3 LOOK (19 IDs)

Third-party world-dressing hosts (spec §4.5: "No third-party Creator Store models") with no caller after the W3 rewrite,
plus the Dockside ammo shed (over the 40-part cap). `DesertProps.Palm` 96059329869678 stays as dead config (no caller;
the literal is pinned by BuyPathStatic).

| Asset ID | Creator Store name | Uploader | Reason | Keys now 0 | Fallback |
|---|---|---|---|---|---|
| [2652344972](https://create.roblox.com/store/asset/2652344972) | Military ammo/supplies shed | F3rwrd (User) | 117 MeshParts, over the 40-part cap (shortlist §4); Dockside keeps its Part-kit shed | `WarzoneProps.AmmoShed` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [13668977092](https://create.roblox.com/store/asset/13668977092) | Camouflage Netting | AntiSocial_Lasagna (User) | world-dressing host with no caller after the W3 rewrite | `WarzoneProps.CamoNet` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [13437018139](https://create.roblox.com/store/asset/13437018139) | Ghillie Net | Crank_theTank (User) | world-dressing host with no caller after the W3 rewrite | `WarzoneProps.CamoNetAlt` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [82454061017921](https://create.roblox.com/store/asset/82454061017921) | Concrete Jersey Barrier | 0WowlionPro (User) | world-dressing host; WorldKits `Jersey` is our Part kit | `WarzoneProps.JerseyBarrier`, `MapDressing.JerseyBarrier` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [17156953177](https://create.roblox.com/store/asset/17156953177) | ConcreteBarrierMesh | ek3170 (User) | world-dressing host with no caller | `WarzoneProps.JerseyBarrierAlt`, `MapDressing.JerseyBarrierAlt` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [9701862157](https://create.roblox.com/store/asset/9701862157) | MILITARY PORTABLE LIGHT TOWER | declan1954 (User) | shortlist §4: listing text names a real-world military; no caller | `WarzoneProps.PortableLightTower` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [15912051001](https://create.roblox.com/store/asset/15912051001) | Concrete Barriers | s1ix6 (User) | world-dressing host with no caller | `WarzoneProps.RoadBarriers` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [8176692221](https://create.roblox.com/store/asset/8176692221) | Destroyed Building | SURPRlSE0 (User) | world-dressing host with no caller | `WarzoneProps.RuinedBuilding` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [104053043839965](https://create.roblox.com/store/asset/104053043839965) | Old brick wall (Mossy or smth) | Guest_62246 (User) | world-dressing host with no caller | `WarzoneProps.RuinedWall` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [123546710527428](https://create.roblox.com/store/asset/123546710527428) | StreetLamp_A | chiroxli (User) | world-dressing host; WorldKits `StreetLamp` is our Part kit | `WarzoneProps.StreetLamp` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [8180880144](https://create.roblox.com/store/asset/8180880144) | Modified Street light [Light version] | AloysiousCatindoy (User) | shortlist §4 provenance ("credits to the original owners"), 8 scripts; no caller | `WarzoneProps.StreetLampAlt` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [82560800252069](https://create.roblox.com/store/asset/82560800252069) | Military Vehicle Shed Army Base Bunker Barrack | 4x4basspeep (User) | shortlist §4 keyword-spam listing, 9 scripts; no caller | `WarzoneProps.SupplyShed` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [9171585794](https://create.roblox.com/store/asset/9171585794) | destroyed tank | lobo73_audas (User) | world-dressing host with no caller (WorldKits `Wreck`) | `WarzoneProps.TankWreck` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [16354482789](https://create.roblox.com/store/asset/16354482789) | CactusBase2 | creepersaur (User) | world-dressing host with no caller | `DesertProps.CactusBase` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [105982075286356](https://create.roblox.com/store/asset/105982075286356) | Low Poly Palm Tree Coconut Summer Tree isla | LaylaDawn2564 (User) | shortlist §4 keyword-spam listing, 1 script; no caller | `DesertProps.PalmAlt`, `MapDressing.PalmAlt` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [867696371](https://create.roblox.com/store/asset/867696371) | Bridge and checkpoint ww2 | Illinois_Lawz (User) | shortlist §4 real-world theme ("ww2"); WorldKits `Checkpoint` v2 | `Landmarks.CheckpointBridge` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [9136197032](https://create.roblox.com/store/asset/9136197032) | Desert house | stabok61 (User) | world landmark with no caller (WorldKits `AdobeHouse`) | `Landmarks.DesertHouse` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [11138299907](https://create.roblox.com/store/asset/11138299907) | Boat Dock | v6cvk (User) | world landmark with no caller | `Landmarks.Pier` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |
| [55228082](https://create.roblox.com/store/asset/55228082) | Spy Bunker | Azraekan (User) | world landmark with no caller | `Landmarks.SpyBunker` | Part kit (vehicles: KitFamilyFallback body, else Part kit) |

### 2d. Cleared by owner rule 5 (2026-09-25, owner asset list)

The owner's rule 5 replaces the three heaviest building models. None of them loaded at runtime (PreferMesh is off and the
structure consoles return before any building dress), so nothing on screen changes. BuyPathStatic now forbids all three in
`VisualAssetConfig`, `StructureVisualConfig` and `VisualAssetService`.

| Asset ID | Creator Store name | Uploader | Reason | Keys now 0 | Fallback |
|---|---|---|---|---|---|
| [138331074285379](https://create.roblox.com/store/asset/138331074285379) | Military Base | VenomStar40066 (User) | Owner rule 5: 232,800 triangles | `Buildings.CommandCenter`, `StructureVisualConfig.CommandCenter` | Part-kit shell; the owner's pick 43803492 waits in `PendingAssetId` |
| [18798977801](https://create.roblox.com/store/asset/18798977801) | Military Barracks | VoidableCircuit (User) | Owner rule 5: 336,948 triangles | `Buildings.Barracks`, `Buildings.SpecialForcesFacility`, `StructureVisualConfig.Barracks`, `StructureVisualConfig.SpecialForcesFacility` | Part-kit shells; the owner's picks 8637034739 and 10112923897 wait in `PendingAssetId` |
| [6015472062](https://create.roblox.com/store/asset/6015472062) | Hangar | afterrburner (User) | Owner rule 5: 45,887 triangles | `Buildings.Hangar`; the Airfield composite in `VisualAssetService` reads `Buildings.Hangar` instead of a hard-coded id | Part shed; the owner's pick 5343886540 waits in `PendingAssetId` |

### 2e. Replaced by owner picks (moved here by `tools/wire-asset-ids.py`)

When a promoted owner pick replaces an id that then appears nowhere under `src/`, the tool moves that id's §3 row here and
notes the pick. Empty until the first promote.

| Asset ID | Creator Store name | Uploader | Type | Updated | Triangles | Scripts | Used by | Notes |
|---|---|---|---|---|---|---|---|---|
<!-- wire-asset-ids:replaced:end -->

## 3.0 Roblox-owned IDs (W3 LOOK; load with the third-party switch OFF)

Creator **Roblox (User 1, verified badge)** for every row, read from the public economy API on **2026-09-24** (no login):
`GET https://economy.roblox.com/v2/assets/<id>/details` → `"Creator":{"Id":1,"Name":"Roblox","CreatorType":"User",...,"HasVerifiedBadge":true}`,
`"IsForSale":false`, `"IsPublicDomain":true` (free); these are the fields that matter from each raw response (the W3
LOOK lane keeps the full responses with its test evidence). Roblox's docs for `InsertService:LoadAsset` / `AssetService` allow assets "owned by Roblox" with
"Allow Loading Third Party Assets" OFF, so the owner clicks nothing.

| Asset ID | Store name | Creator | Type | Updated | What we take | Used by | Evidence |
|---|---|---|---|---|---|---|---|
| [6418221666](https://create.roblox.com/store/asset/6418221666) | Light Utility Vehicle | Roblox (User 1) | Model | 2023-11-03 | Child `Light Utility Vehicle (green camo)` › `Body` only: 39 MeshParts. Its Chassis, 16 scripts, seats, remotes and sounds are destroyed at load; the 41 camo Decals are stripped (the camo images are uploaded by user Orlando777, 715494, not Roblox, and cost draw calls). Neon lights become SmoothPlastic | `Vehicles.MilitaryJeep` and through `KitFamilyFallback.WheeledLight` the other light 4x4s (`ArmedJeep`, `ScoutCar`, `DispatchCar`; since 2026-09-25 the Utility Quad and Recon Buggy wear the Dune Buggy below). The Part kit still drives; the Armed 4x4 keeps its Part turret | [economy API](https://economy.roblox.com/v2/assets/6418221666/details) |
| [6933438443](https://create.roblox.com/store/asset/6933438443) | Synty Nature Pack | Roblox (User 1) | Model | 2021-06-10 | One MeshPart per kit, texture cleared, recoloured: `Meshes/PolygonNature_Tree_Pine_Dead_01`, `…_Tree_Stump_01`, `…_Plant_Reeds_01`, `…_Plant_01`, and since 2026-09-25 `…_Tree_Log_01` (fallen log) and `…_Tree_Twig_02` (driftwood, turned 90°) | `DesertKit.DeadTree`, `Stump`, `Reeds`, `DuneGrass`, `Log`, `Driftwood` (WorldKits mesh overlays) | [economy API](https://economy.roblox.com/v2/assets/6933438443/details) |
| [6933790012](https://create.roblox.com/store/asset/6933790012) | Synty Dungeon Pack: Weapons & Props | Roblox (User 1) | Model | 2021-06-10 | `Meshes/PolygonDungeon_Props_SM_Prop_Crate_Wood_04` | `DesertKit.CrateWood` | [economy API](https://economy.roblox.com/v2/assets/6933790012/details) |
| [6933556508](https://create.roblox.com/store/asset/6933556508) | Synty City Pack | Roblox (User 1) | Model | 2021-06-10 | `Meshes/PolygonCity_Props_SM_Veh_Car_Sedan_01` only (since 2026-09-25): texture cleared, recoloured CorrodedMetal as a burnt wreck, turned 90° onto the kit's long axis; 5,524 tris, at most 6 per 512-stud circle. The bench, van and skip pieces stay unwired (they do not fit the WorldKits boxes) | `DesertKit.CarWreck` (`Bench`, `VanWreck`, `Skip` stay 0) | [economy API](https://economy.roblox.com/v2/assets/6933556508/details) |
| [6433272094](https://create.roblox.com/store/asset/6433272094) | Dune Buggy | Roblox (User 1) | Model | 2021-02-24 | Child `Dune Buggy (beige)` › `Body` only: 23 MeshParts, no decals (13,625 tris). Chassis, 12 scripts, seats and sounds are destroyed at load; fitted to the kit chassis | `Vehicles.UtilityQuad`, `Vehicles.ReconBuggy` (dress only; the Part kit drives) | [economy API](https://economy.roblox.com/v2/assets/6433272094/details) |
| [6418225759](https://create.roblox.com/store/asset/6418225759) | Pickup Truck | Roblox (User 1) | Model | 2023-11-03 | Child `Pickup Truck (bronze)` › `Body`: 41 MeshParts, minus the overlapping `light_tail_glass` (`OmitParts`) = 40, the cap (15,746 tris); decals stripped; fitted to the kit chassis | `Vehicles.PatrolTruck`, `Vehicles.EscortTruck` (dress only) | [economy API](https://economy.roblox.com/v2/assets/6418225759/details) |
| [6433316269](https://create.roblox.com/store/asset/6433316269) | Van | Roblox (User 1) | Model | 2021-02-24 | Child `Van (white)` › `Body`: 26 MeshParts, no decals (8,390 tris); fitted to the kit chassis | `Vehicles.CargoVan` (dress only) | [economy API](https://economy.roblox.com/v2/assets/6433316269/details) |
| [23153991](https://create.roblox.com/store/asset/23153991) | Smoking Barrel | Roblox (User 1) | Model | 2010-03-01 | The whole model: 4 CylinderMesh parts (384 tris). Its Smoke is removed when the template is prepared (`StripEffectsAssetIds`) | `WarzoneProps.OilBarrel` (training-yard drums; replaces the third-party 25623924 there) | [economy API](https://economy.roblox.com/v2/assets/23153991/details) |
| [4842207161](https://create.roblox.com/store/asset/4842207161) | Auto Rifle | Roblox (User 1) | Model | 2023-06-15 | Tool `AR` › Model `AR` plus the Tool's `Handle` made invisible (the grip). The kit's WeaponsSystem scripts (6) and its Sounds are never copied; loads through `WeaponAssetLoader` (outside the 48 load attempts) | `WeaponConfig` StarterRifle, AssaultRifle | [economy API](https://economy.roblox.com/v2/assets/4842207161/details) |
| [4842212980](https://create.roblox.com/store/asset/4842212980) | Submachine Gun | Roblox (User 1) | Model | 2023-06-15 | Tool `SMG` › Model `SMG` + invisible `Handle`, as above | `WeaponConfig` SMG | [economy API](https://economy.roblox.com/v2/assets/4842212980/details) |
| [4842197274](https://create.roblox.com/store/asset/4842197274) | Pistol | Roblox (User 1) | Model | 2023-06-15 | Tool `Pistol` › Model `Pistol` + invisible `Handle`, as above | `WeaponConfig` Pistol | [economy API](https://economy.roblox.com/v2/assets/4842197274/details) |
| [4842215723](https://create.roblox.com/store/asset/4842215723) | Shotgun | Roblox (User 1) | Model | 2023-06-15 | Tool `Shotgun` › Model `Shotgun` + invisible `Handle`, as above | `WeaponConfig` Shotgun | [economy API](https://economy.roblox.com/v2/assets/4842215723/details) |
| [4842218829](https://create.roblox.com/store/asset/4842218829) | Sniper Rifle | Roblox (User 1) | Model | 2023-06-15 | Tool `Sniper` › Model `Sniper` + invisible `Handle`, as above | `WeaponConfig` Sniper | [economy API](https://economy.roblox.com/v2/assets/4842218829/details) |
| [4842186817](https://create.roblox.com/store/asset/4842186817) | Rocket Launcher | Roblox (User 1) | Model | 2023-06-15 | Tool `Rocket Launcher` › Model `RocketLauncher` + invisible `Handle`, as above | `WeaponConfig` RocketLauncher | [economy API](https://economy.roblox.com/v2/assets/4842186817/details) |
| [232379763](https://create.roblox.com/store/asset/232379763) | MESH_ArmyGuy_Grenade, with texture [232379808](https://create.roblox.com/store/asset/232379808) TX_ArmyGuy_Grenade_v2 | Roblox (User 1) | Mesh + Image | 2015-03-31 | `MeshId` / `TextureId` of the client grenade's SpecialMesh (1,350 faces); no LoadAsset, no model | `WeaponConfig.Weapons.Grenade.Projectile` | [economy API](https://economy.roblox.com/v2/assets/232379763/details), [texture](https://economy.roblox.com/v2/assets/232379808/details) |
| [94690081](https://create.roblox.com/store/asset/94690081) | MESH_BattleGameRocketLauncherAmmo, with texture [94689966](https://create.roblox.com/store/asset/94689966) TX_BattleGameRocketLauncher | Roblox (User 1) | Mesh + Image | 2012-10-09 | `MeshId` / `TextureId` of the rocket in flight (336 faces); no LoadAsset, no model | `WeaponConfig.Weapons.RocketLauncher.Projectile` | [economy API](https://economy.roblox.com/v2/assets/94690081/details), [texture](https://economy.roblox.com/v2/assets/94689966/details) |

**Terms.**
- Synty packs: Roblox's DevForum announcement "Free Synty Asset Packs Released in the Marketplace" (topic 1283755,
  2021-06-10, re-read 2026-09-24): *"These assets are completely free to use in anything you want to create on Roblox!"*
  Use on Roblox only.
- Light Utility Vehicle: made and published by Roblox, free, Creator Store terms (use on Roblox). We use its body mesh as
  dress under our own vehicle names ("Field 4x4" …); its scripts trust the client and are never used (roadmap §1.4).
- Dune Buggy, Pickup Truck and Van (2026-09-25): the same terms and the same use as the Light Utility Vehicle (Body only,
  under our own vehicle names). Their inner mesh uploaders were not re-checked; we never reference inner ids.
- Weapons Kit guns (4842…, 2026-09-25): made and published by Roblox (User 1), Endorsed, free. Licence code `RBX-LUL`
  (docs/ASSET_SHORTLIST.md §2: a Roblox-owned kit under Roblox's Limited Use License): use inside Roblox only, and keep this
  attribution: **gun models from Roblox's Weapons Kit (Roblox)**. We use the visual Model and the Tool's Handle only; the
  kit's WeaponsSystem scripts and its Sounds (owned by a user and a group, not Roblox) are never copied. The Auto Rifle and
  Rocket Launcher shapes are generic AK- and RPG-pattern looks on unnamed Roblox models; the owner listed both himself
  (ASSUMPTIONS: owner yes; one-line revert `VisualAssetId = 0`).
- Grenade and rocket meshes and textures (2026-09-25): Roblox-owned content ids (economy API: creator Roblox, not for sale),
  set by id on a client SpecialMesh; never loaded as a model.
- Smoking Barrel (2026-09-25): a free Roblox-owned model; used whole (4 parts) with its smoke removed.
- The meshes and textures inside these models were uploaded by the accounts that built them for Roblox (checked on the
  economy API: oggo732, 1114780684, for the LUV and Nature meshes; Klaugrana001, 1453730866, for the City and Dungeon
  meshes and the pack textures). We never reference those inner ids in config; they arrive inside the Roblox-owned model
  through `InsertService`.

**Rules the loader enforces** (`VisualAssetService`, W3 LOOK): each pack is inserted once and split into the configured
pieces (`ChildName`, found with `FindFirstChild(name, true)`, never split on "/"); the rest is destroyed; every template is
<= 40 parts (`MaxPartsPerModel`) with no Humanoid or it is refused; templates live in `ServerStorage`; a failed load is
cached and the Part kit stays.

## 3.1 Owner picks (third-party, promoted by `tools/wire-asset-ids.py`)

The owner listed his own Creator Store picks on 2026-09-25 (docs/ASSET_WIRING.md). A third-party pick first waits in
`PendingAssetId`, which no loader reads. `tools/wire-asset-ids.py promote` moves it into `ModelAssetId` only when it is in
the owner's inventory, the store still shows the same creator and a free price, the owner said yes where the row needs it,
and a Studio `WE_CHECK` showed at most 40 parts and no Humanoid where the row needs it. In the same commit it appends the
row below. Rules 1–5 of §1 hold for every row; scripts are stripped at load. Empty until the first promote.

| Asset ID | Creator Store name | Uploader | Type | Verified (UTC) | Triangles | Scripts | Used by | Notes |
|---|---|---|---|---|---|---|---|---|
<!-- wire-asset-ids:owner-picks:end -->

## 3. Remaining third-party IDs (53) and why each is allowed

Every row: free Creator Store asset, Roblox Terms (in-Roblox use only), passes rules 1–5 in §1 unless the note says
"Watch". "Scripts" is the count inside the upload; all are stripped before use. Triangles are from the toolbox API.

### Vehicles (dress on the Part-kit chassis; physics stays the Part kit)

None. Every third-party vehicle id was cleared (§2, §2b); the light 4x4s, the quad, buggy, pickups and van use the
Roblox-owned bodies in §3.0 and every other family keeps its Part kit. The owner's vehicle picks wait in `PendingAssetId`
(never loaded) until they are promoted (§3.1).

### Characters (dress on Part-kit NPCs)

| Asset ID | Creator Store name | Uploader | Type | Updated | Triangles | Scripts | Used by | Notes |
|---|---|---|---|---|---|---|---|---|
| [9104381136](https://create.roblox.com/store/asset/9104381136) | Layered clothing realistic soldier | paquinhos (User) | Model | 2022-03-14 | 29,703 | 0 | `Characters.Infantry`, `Characters.WorkerFallback` | Uploader assembled Marketplace clothing and accessories made by others ("no need to credit"). Pinned Infantry/Worker fallback; W6a replaces with Roblox rigs |
| [100212659702941](https://create.roblox.com/store/asset/100212659702941) | Realistic soldier StarterCharacter | HeitorGameplayBr009 (User) | Model | 2025-08-10 | 20,000 | 2 | `Characters.Soldier` |  |
| [16134469614](https://create.roblox.com/store/asset/16134469614) | Rigged Soldier | Gioele_e (User) | Model | 2024-01-27 | 50,580 | 0 | `Characters.Worker`, `Characters.Guard`, `Characters.BankGuard`, `Characters.OilRigGuard`, `Characters.FortGuard`, `Characters.GateGuard`, `GateDefense.Guard` |  |

### Buildings (dress on structure plinths; PreferMesh stays OFF)

| Asset ID | Creator Store name | Uploader | Type | Updated | Triangles | Scripts | Used by | Notes |
|---|---|---|---|---|---|---|---|---|
| [85138026](https://create.roblox.com/store/asset/85138026) | USM Gate Please Favorte! | FearlessIantheKiller (User) | Model | 2012-07-01 | 5,876 | 9 | `Buildings.BaseGate` | Watch: "USM" in the title. Check in Studio for national insignia before the owner Gets it |
| [17701461178](https://create.roblox.com/store/asset/17701461178) | Shipping Containers | VGVC2 (User) | Model | 2024-06-02 | 6,176 | 0 | `Buildings.Dock`, `StructureVisualConfig.Dock` | Watch: check the doors for real shipping-line logos before the owner Gets it |
| [14313845338](https://create.roblox.com/store/asset/14313845338) | Airport | DeadGamerTuPanaPro (User) | Model | 2023-08-04 | 4,778 | 0 | `Buildings.Helipad`, `StructureVisualConfig.Helipad` |  |
| [14000967030](https://create.roblox.com/store/asset/14000967030) | Coal power plant | Steveli76 (User) | Model | 2023-07-08 | 27,560 | 0 | `Buildings.PowerStation`, `StructureVisualConfig.PowerStation` |  |
| [9559610195](https://create.roblox.com/store/asset/9559610195) | Radar Dish W/Base | ThugulusPrime (User) | Model | 2022-05-06 | 18,700 | 2 | `Buildings.Radar`, `StructureVisualConfig.Radar` |  |
| [17725725](https://create.roblox.com/store/asset/17725725) | Research Lab | Ezmo1999 (User) | Model | 2009-11-06 | 5,848 | 0 | `Buildings.ResearchLab`, `StructureVisualConfig.ResearchLab` |  |
| [12208876851](https://create.roblox.com/store/asset/12208876851) | hangar | Eduardowolfalpha2 (User) | Model | 2023-01-20 | 202,920 | 0 | `Buildings.VehicleDepot`, `Buildings.HangarAlt`, `StructureVisualConfig.VehicleDepot` | 202,920 triangles: W3 phase-out (phone budget) |
| [15942568272](https://create.roblox.com/store/asset/15942568272) | Hangar shed | MAX_FLINN (User) | Model | 2024-01-11 | 30,056 | 4 | `Buildings.Warehouse`, `StructureVisualConfig.Warehouse` |  |
| [108525417345747](https://create.roblox.com/store/asset/108525417345747) | Sniper Tower Military Base Outpost Watchtower | LightZrCyberGrKing16 (User) | Model | 2026-04-22 | 1,438 | 1 | `Buildings.Watchtowers`, `StructureVisualConfig.Watchtowers` |  |
| [4120970784](https://create.roblox.com/store/asset/4120970784) | Military Barracks, 3 Story's | ItsJustT_NY (User) | Model | 2019-10-14 | 213,994 | 0 | `Buildings.WeaponsFacility`, `StructureVisualConfig.WeaponsFacility` | 213,994 triangles: W3 phase-out (phone budget) |

### Gate defense

| Asset ID | Creator Store name | Uploader | Type | Updated | Triangles | Scripts | Used by | Notes |
|---|---|---|---|---|---|---|---|---|
| [4923345827](https://create.roblox.com/store/asset/4923345827) | Machine Gun Nest | Byrdknight (User) | Model | 2020-04-20 | 4,999 | 0 | `GateDefenseService default` only (config AutoGun = 0 since 2026-09-25) | Watch: the game owner owns it since 2026-09-25 (inventory API 08:05 UTC), it loaded on live on the gate AutoGuns at walls level 4+ until the config was set to 0 the same day (GateDefenseService's own loader: no part cap, outside the 48); GateDefenseService still names it as a default and that line is deferred to after streaming2-build. The owner's pick 114570602 replaces it at promote batch P1; a WWII MG 34-like silhouette, so the owner rejected it for the sandbag nest |
| [10354803684](https://create.roblox.com/store/asset/10354803684) | Military turret | gtddgc8 (User) | Model | 2022-07-25 | 14,754 | 5 | `GateDefense.AutoGunElevatedAlt` | The 2022 original of the 2026 re-upload 71964514000054 (dropped) |
| [3525056989](https://create.roblox.com/store/asset/3525056989) | Realistic Sandbag | 0TacoMillitary0 (User) | Model | 2019-07-24 | 1,868 | 0 | `GateDefense.Sandbags`, `WarzoneProps.Sandbag`, `WarzoneProps.Sandbags`, `GateDefenseService default` |  |

### Collector, effects, showroom, tutorial

| Asset ID | Creator Store name | Uploader | Type | Updated | Triangles | Scripts | Used by | Notes |
|---|---|---|---|---|---|---|---|---|
| [16803204916](https://create.roblox.com/store/asset/16803204916) | Cash Crate For Zednov's Tycoon Kit | asteriiez (User) | Model | 2024-03-20 | 12 | 4 | `CashCrate` | Made by the uploader for the public Zednov tycoon kit (not another game's asset) |
| [107381977457431](https://create.roblox.com/store/asset/107381977457431) | Military Light Truck Car Vehicle Army War RP | XxEpic_IcexX2024 (User) | Model | 2026-02-04 | — | 0 | `FloodlightTower`, `WarzoneProps.FloodlightTower` | Watch: listing title is a military light truck but the key is a floodlight-tower prop (content mismatch, W3) |
| [38451313](https://create.roblox.com/store/asset/38451313) | Money Bag | Copyright (User) | Model | 2010-11-06 | 128 | 1 | `MoneyBagFX` | Uploader account is literally named "Copyright"; 2010 free model |
| [90362241548850](https://create.roblox.com/store/asset/90362241548850) | Tycoon Collector (no Scripts) Factory Money | RobloxVibeModels (User) | Model | 2026-02-15 | 290 | 2 | `MoneyCollectorAlts[]` |  |
| [76846072091295](https://create.roblox.com/store/asset/76846072091295) | Cash Collector Coins Money Pick Up Simple | Nora_Hunt3r74 (User) | Model | 2026-03-29 | — | 0 | `MoneyCollectorAlts[]` |  |
| [35409899](https://create.roblox.com/store/asset/35409899) | Tycoon Money Collector(ANCHOR IT!) | ok3y11 (User) | Model | 2010-09-19 | 60 | 5 | `MoneyCollectorAlts[]` | Listing: "all stuff is maked by ok3y11": credited here; scripts stripped |
| [175462478](https://create.roblox.com/store/asset/175462478) | ATM | Famlica (User) | Model | 2014-08-31 | 94 | 0 | `MoneyCollectorFallback` | Author asks for credit ("just give me some credit"): credited here |
| [130578088310000](https://create.roblox.com/store/asset/130578088310000) | sci-fi pedestal display stand platform showcase | XxDriftAlphaSkaterxX (User) | Model | 2026-03-25 | 5,936 | 1 | `ShowroomPedestal` |  |
| [5267267960](https://create.roblox.com/store/asset/5267267960) | Statue Podium | Trevor C. Fan Group! (Group) | Model | 2020-07-01 | 192 | 0 | `ShowroomPodium` |  |
| [5389482912](https://create.roblox.com/store/asset/5389482912) | Rotating Platform | Ender17143 (User) | Model | 2020-07-20 | 24 | 1 | `ShowroomRotator` |  |
| [1143305733](https://create.roblox.com/store/asset/1143305733) | Blinking Tutorial Arrow | MajorMent (User) | Model | 2017-10-30 | 40 | 2 | `TutorialArrow` | Listing: "By MajorMent": credited here |
| [6333395014](https://create.roblox.com/store/asset/6333395014) | Arrow pointing down | DyingInisde (User) | Model | 2021-02-01 | 32 | 0 | `TutorialArrowAlt` |  |
| [88687072714005](https://create.roblox.com/store/asset/88687072714005) | Laser Beam Effect | eazypro29 (User) | Model | 2025-06-16 | 0 | 0 | `TutorialBeam` |  |
| [1679839739](https://create.roblox.com/store/asset/1679839739) | Flag Pole | HerrDirektorZach (User) | Model | 2018-04-28 | 792 | 0 | `UpgradeFlag`, `WarzoneProps.Flag`, `WarzoneProps.FlagPole` |  |
| [4221608224](https://create.roblox.com/store/asset/4221608224) | Sparkles Effect | favmuva (User) | Model | 2019-10-26 | 0 | 0 | `VfxSparkles` |  |

### Warzone props

| Asset ID | Creator Store name | Uploader | Type | Updated | Triangles | Scripts | Used by | Notes |
|---|---|---|---|---|---|---|---|---|
| [16382915010](https://create.roblox.com/store/asset/16382915010) | Ammo Box | ajh2k21 (User) | Model | 2024-02-15 | 21,472 | 0 | `WarzoneProps.AmmoBox` |  |
| [1291725699](https://create.roblox.com/store/asset/1291725699) | [FREE] Barbed Wire Fence | CentralCityLaw (User) | Model | 2018-01-01 | 312 | 1 | `WarzoneProps.BarbedWire` |  |
| [91071319](https://create.roblox.com/store/asset/91071319) | Concrete Barrier | HabaneroDude (User) | Model | 2016-08-27 | 868 | 0 | `WarzoneProps.ConcreteBarrier`, `WarzoneProps.Cone` |  |
| [53591587](https://create.roblox.com/store/asset/53591587) | Crate/Box | griflay (User) | Model | 2011-06-10 | 24 | 0 | `WarzoneProps.Crate`, `WarzoneProps.Drum` | "Area 51" in the listing is a place name, not a design |
| [1454179642](https://create.roblox.com/store/asset/1454179642) | [Highly Detailed] Flag Pole | Owl4110 (User) | Model | 2018-02-24 | 912 | 0 | `WarzoneProps.FlagPoleHD` |  |
| [116763933](https://create.roblox.com/store/asset/116763933) | Floodlight | ChillyRaptor (User) | Model | 2013-05-24 | 204 | 1 | `WarzoneProps.Floodlight`, `WarzoneProps.Lamp` |  |
| [4893998573](https://create.roblox.com/store/asset/4893998573) | Floodlight | VladimirDeliyUA (User) | Model | 2020-04-13 | 2,074 | 0 | `WarzoneProps.FloodlightAlt` |  |
| [1160141839](https://create.roblox.com/store/asset/1160141839) | Non-Laggy Fuel Cans and Oil Barrels | WOLFENCHAN (Group) | Model | 2017-11-07 | 7,350 | 0 | `WarzoneProps.FuelCans`, `IndustrialProps.FuelCans` |  |
| [976333542](https://create.roblox.com/store/asset/976333542) | Military Crate | sam_youwell (User) | Model | 2017-08-13 | 1,196 | 0 | `WarzoneProps.MilitaryCrate`, `WarzoneProps.Pallet` |  |
| [16540055496](https://create.roblox.com/store/asset/16540055496) | Military Crates | Antonov_Slonovskaya (User) | Model | 2024-02-27 | 8,254 | 0 | `WarzoneProps.MilitaryCratePack` |  |
| [25623924](https://create.roblox.com/store/asset/25623924) | Oil Barrel | raldude1 (User) | Model | 2010-04-15 | 480 | 0 | `WarzoneProps.Fence`, `IndustrialProps.OilBarrel` | Since 2026-09-25 `WarzoneProps.OilBarrel` is the Roblox Smoking Barrel 23153991 (§3.0) |
| [19277831](https://create.roblox.com/store/asset/19277831) | radio antenna | ak74dd (User) | Model | 2009-12-15 | 652 | 0 | `WarzoneProps.RadioAntenna`, `WarzoneProps.Radio` |  |
| [42209845](https://create.roblox.com/store/asset/42209845) | Radio Antenna | MrTw0fer (User) | Model | 2010-12-16 | 360 | 0 | `WarzoneProps.RadioAntennaAlt` |  |
| [12651656400](https://create.roblox.com/store/asset/12651656400) | Sandbag Barrier | Aheadit (User) | Model | 2023-03-01 | 7,493 | 0 | `WarzoneProps.SandbagBarrier` |  |
| [25733125](https://create.roblox.com/store/asset/25733125) | Sandbag wall | SpecialOp (User) | Model | 2010-04-17 | 3,624 | 0 | `WarzoneProps.SandbagWall`, `WarzoneProps.Barrier` |  |
| [6883609157](https://create.roblox.com/store/asset/6883609157) | Military Tent | ForestFireTree1 (User) | Model | 2023-11-29 | 9,932 | 0 | `WarzoneProps.Tent` |  |
| [3133150032](https://create.roblox.com/store/asset/3133150032) | Military Tent | MrKotikXD (User) | Model | 2022-01-22 | 38,324 | 9 | `WarzoneProps.TentAlt` |  |

### Desert props

| Asset ID | Creator Store name | Uploader | Type | Updated | Triangles | Scripts | Used by | Notes |
|---|---|---|---|---|---|---|---|---|
| [96059329869678](https://create.roblox.com/store/asset/96059329869678) | Palm Trees Realistic Tropical Island Beach Pack | BellaLion62438 (User) | Model | 2026-02-05 | — | 0 | `DesertProps.Palm`, `MapDressing.Palm` |  |

### Map dressing aliases

| Asset ID | Creator Store name | Uploader | Type | Updated | Triangles | Scripts | Used by | Notes |
|---|---|---|---|---|---|---|---|---|

### Industrial props

| Asset ID | Creator Store name | Uploader | Type | Updated | Triangles | Scripts | Used by | Notes |
|---|---|---|---|---|---|---|---|---|
| [13525922265](https://create.roblox.com/store/asset/13525922265) | Realistic Oil Pumpjack | Unit5532 (User) | Model | 2023-05-23 | 11,318 | 0 | `IndustrialProps.OilPumpjack` |  |
| [15192621369](https://create.roblox.com/store/asset/15192621369) | Oil Rig / Pumpjack | sadfiacs (User) | Model | 2023-11-03 | 1,398 | 0 | `IndustrialProps.OilPumpjackAlt` | Listing: "Mesh Inspiration: Karcist" (inspiration only). Owned by the game owner since 2026-09-25 (08:05 UTC), so it loads on live when the primary 13525922265 (not owned) fails; the owner's pick for the plot pump (promote batch P1 moves it to `OilPumpjack`) |

### Landmarks

| Asset ID | Creator Store name | Uploader | Type | Updated | Triangles | Scripts | Used by | Notes |
|---|---|---|---|---|---|---|---|---|
| [119021509](https://create.roblox.com/store/asset/119021509) | Radio Tower | George256 (User) | Model | 2013-06-14 | 22,836 | 0 | `Landmarks.RadioTower` |  |
| [67444725](https://create.roblox.com/store/asset/67444725) | Small Fort | ballygoat (User) | Model | 2011-12-11 | 72 | 0 | `Landmarks.SmallFort` |  |

## 4. Follow-ups outside `VisualAssetConfig` (not CFG's files)

1. **`StructureVisualConfig.luau` line 152**: `MeshAssetId = 11962508154` (MissileDefense). `ResolveBuildingAssetId` falls
   back to this field when `VisualAssetConfig.Buildings.MissileDefense` is 0, so the HIMARS-type launcher still resolves for
   MissileDefense plinths until it is set to `MeshAssetId = 0`. BuyPathStatic pins `MeshAssetId = 11962508154` for that file;
   whoever edits it re-pins to the new text.
2. ~~`VisualAssetService.luau`: a comment named the paid ATM ID~~ Done in W3 LOOK (the comment now reads "MoneyCollector (0
   since W1) → MoneyCollectorFallback 175462478 → alts → Part kit"). Item 1 is also done: `StructureVisualConfig` MissileDefense
   `MeshAssetId = 0`.
3. **Watch rows** in §3: the two army trucks went in 859dedc and the modified street light in W3 LOOK (§2b, §2c). Shipping
   Containers 17701461178 (126 MeshParts) is now refused at load by the 40-part cap. USM Gate 85138026 and the
   floodlight-tower mismatch 107381977457431 stay (BuyPathStatic pins them); the next LOOK step replaces them.
4. **`THIRD_PARTY_NOTICES.md`** (roadmap §4) exists since W2 and points here for the `VisualAssetConfig` model / mesh IDs:
   the Synty grant and the LUV terms are in §3.0. The credits requested by uploaders of the IDs above are in the notes of §3.

## 5. Other external IDs in `src/` (listed elsewhere)

- `Shared/Configs/SoundConfig.luau`: sound IDs owned by SND (W1). Roblox licensed library and Roblox-owned engine loops
  (D4): in-game only, never in YouTube or TikTok promos. SND documents them there.
- `Shared/Configs/MonetizationConfig.luau`: game-pass and developer-product IDs of our own experience, not third-party assets.
- `rbxasset://` paths (`textures/face.png`, `sounds/electronicpingshort.wav`, `textures/particles/smoke_main.dds`): content
  shipped with the Roblox client.

## 6. What the owner must test on his phone

W3 LOOK (Roblox-owned, loads with the switch OFF; the headless stand-in is not Roblox and cannot load assets):
1. Spawn the Field 4x4 (and the Armed 4x4): it wears Roblox's dark-green utility-vehicle body, sits on the ground with its
   wheels, drives exactly as before, and the Armed 4x4 still shows its gun. The driver sits on the roof line, as on the old
   kit (the seat height belongs to VehicleService).
2. In Crossroads Town and along the roads: some crates, stumps, dead trees, reeds and dry plants use smoother Synty shapes
   (at most 40 per server); nothing floats, nothing has text on it.
3. Developer Console (F9) after a publish: `Split pack 6418221666`, `Split pack 6933438443`, `Split pack 6933790012` and no
   `LoadAsset failed` line for these three IDs. A failed load only means the Part kits stay.
4. Studio: Game Settings › Security › "Allow Loading Third Party Assets" stays OFF.

Owner asset list (2026-09-25): what to test on the phone for the Roblox-owned picks and for each promote batch is in
docs/ASSET_WIRING.md §1.

Nation flags are not Creator Store assets: they are our own renders of MIT-licensed flag-icons SVGs (`assets/flags/LICENSE-flag-icons.txt`, THIRD_PARTY_NOTICES.md section 6).
