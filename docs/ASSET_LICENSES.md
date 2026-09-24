# External asset IDs: owners, terms and why each is allowed

Scope: every non-zero Creator Store ID in `src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau`, plus the
`StructureVisualConfig.Palettes.*.MeshAssetId` IDs and the IDs hard-coded in services (all of them are also config IDs).
Data: Roblox economy API `economy.roblox.com/v2/assets/<id>/details`, read 2026-09-24, and the toolbox stats in
`gap/asset_stats.json` (triangles, scripts). Nothing here was loaded in Roblox. The headless sim is not Roblox.

Owner: CFG (W1) writes this file with `VisualAssetConfig`; LOOK (W3) and W6a update it in the same commit as any ID change.

## 1. Rules

**How these IDs load.** Owner default D1 keeps Game Settings › Security › "Allow Loading Third Party Assets" **OFF**.
`AssetService:LoadAssetAsync` then loads only assets the game creator owns or has been granted. **None of the IDs below is
owned by Roblox or by the game owner**, so on live every one fails once, `VisualAssetService` caches the failure, and the
Part kit stays. An ID starts to show only if the owner clicks "Get Model" on it (or turns the setting on, which D1 rejects).

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

## 3. Remaining IDs (99) and why each is allowed

Every row: free Creator Store asset, Roblox Terms (in-Roblox use only), passes rules 1–5 in §1 unless the note says
"Watch". "Scripts" is the count inside the upload; all are stripped before use. Triangles are from the toolbox API.

### Vehicles (dress on the Part-kit chassis; physics stays the Part kit)

| Asset ID | Creator Store name | Uploader | Type | Updated | Triangles | Scripts | Used by | Notes |
|---|---|---|---|---|---|---|---|---|
| [17835143223](https://create.roblox.com/store/asset/17835143223) | APC | 2Varu (User) | Model | 2024-06-12 | 119,089 | 14 | `Vehicles.APC`, `Vehicles.InfantryCarrier`, `Vehicles.CommandVehicle`, `Vehicles.WheeledIFV`, `Vehicles.AmphibiousAPC` | 119,089 triangles: W3 phase-out (phone budget) |
| [81802040484766](https://create.roblox.com/store/asset/81802040484766) | Army Truck Military Vehicle Transport Mesh Pbr | Rocket1h202 (User) | Model | 2026-02-17 | 34,358 | 20 | `Vehicles.AmmoCarrier`, `Vehicles.MissileTruck`, `Vehicles.RadarTruck` | Watch: identical mesh to 105503568352704 (see there). W3 LOOK replaces both |
| [295607934](https://create.roblox.com/store/asset/295607934) | Attack Helicopter | 12904 (User) | Model | 2015-09-14 | 13,418 | 10 | `Vehicles.AttackHelicopter`, `Vehicles.NightAttackHeli`, `Vehicles.GunshipHeli`, `Vehicles.StealthHeli`, `Vehicles.EscortHeli` | Uploader credits the Turbo Fusion Plane Kit: credited here |
| [12794395111](https://create.roblox.com/store/asset/12794395111) | Multipurpose Frigate | teunboy3 (User) | Model | 2023-03-15 | 263,332 | 1 | `Vehicles.Corvette`, `Vehicles.Frigate`, `Vehicles.CarrierEscort` | 263,332 triangles: W3 phase-out (phone budget) |
| [76055078503396](https://create.roblox.com/store/asset/76055078503396) | Tank Military Vehicle War Machine Roleplay Combat | wimundefined0 (User) | Model | 2026-02-15 | 7,318 | 2 | `Vehicles.LightTank`, `Vehicles.CombatIFV`, `Vehicles.AssaultIFV`, `Vehicles.BridgeLayer`, `Vehicles.MineClearer`, `Vehicles.FlameCarrier`, `Vehicles.LightScoutTank` | Also the family body for the dropped `MobileSAM`, `RocketArtillery` and `RailgunCarrier` entries |
| [5935419](https://create.roblox.com/store/asset/5935419) | gunship | liger0223 (User) | Model | 2008-11-30 | 17,858 | 7 | `Vehicles.LightTransportHeli`, `Vehicles.LightScoutHeli`, `Vehicles.RescueHeli`, `Vehicles.UtilityHeli`, `Vehicles.MedevacHeli` |  |
| [26007709](https://create.roblox.com/store/asset/26007709) | free tank | august999 (User) | Model | 2010-04-22 | 2,414 | 2 | `Vehicles.MediumTank` |  |
| [125916936788670](https://create.roblox.com/store/asset/125916936788670) | Military Car Vehicle War Wheel Armored Model | BlitzxbCyberl36 (User) | Model | 2026-05-04 | 98,067 | 13 | `Vehicles.MilitaryJeep`, `Vehicles.UtilityQuad`, `Vehicles.ScoutCar`, `Vehicles.ReconBuggy`, `Vehicles.DispatchCar` | 98,067 triangles, 13 scripts, 2026 keyword-titled upload. Now also the WheeledLight family body for `ArmedJeep` (no turret). W3 LOOK swaps the light 4x4s to the Roblox Light Utility Vehicle |
| [10286064243](https://create.roblox.com/store/asset/10286064243) | Howitzer | ParanoidType (User) | Model | 2022-07-19 | 3,632 | 0 | `Vehicles.MortarCarrier`, `Vehicles.MobileArtillery`, `Vehicles.HowitzerTruck`, `Vehicles.SiegeMortar` |  |
| [557152593](https://create.roblox.com/store/asset/557152593) | Navy Patrol Boat | Zolteks (User) | Model | 2016-12-08 | 20,240 | 0 | `Vehicles.PatrolBoat`, `Vehicles.CoastCutter`, `Vehicles.Gunboat` |  |
| [105503568352704](https://create.roblox.com/store/asset/105503568352704) | Army Truck Military Vehicle Transport Mesh PBR | Bella29_0Ghost591530 (User) | Model | 2026-02-04 | 34,358 | 24 | `Vehicles.PatrolTruck`, `Vehicles.ArmoredTruck`, `Vehicles.SupplyTruck` | Watch: identical mesh (34,358 triangles) to 81802040484766 from another 2026 account; one is a re-upload. W3 LOOK replaces both |
| [15618784436](https://create.roblox.com/store/asset/15618784436) | AA gun | itsJambles (User) | Model | 2023-12-12 | 3,988 | 0 | `Vehicles.SPAAG` |  |
| [3319732457](https://create.roblox.com/store/asset/3319732457) | war plane | the_epicpokemon (User) | Model | 2019-06-16 | 34,432 | 0 | `Vehicles.StrikeBomber`, `Vehicles.CargoPlane`, `Vehicles.AWACSPlane`, `Vehicles.TankerPlane`, `Vehicles.HeavyBomber`, `Vehicles.StrategicBomber` |  |
| [5507592781](https://create.roblox.com/store/asset/5507592781) | fighter jet model (no script) | berkobero (User) | Model | 2023-03-31 | 26,924 | 0 | `Vehicles.StrikeJet`, `Vehicles.CASJet`, `Vehicles.StealthStrikeJet`, `Vehicles.StealthStrike` |  |
| [9753309](https://create.roblox.com/store/asset/9753309) | Elite Force Gunship | pieman711 (User) | Model | 2009-04-11 | 4,052 | 15 | `Vehicles.TransportHeli`, `Vehicles.HeavyLiftHeli`, `Vehicles.VTOLTransport` | Listing: built on "Trooperc's Aberaxas Platform"; 15 scripts stripped |
| [4128346779](https://create.roblox.com/store/asset/4128346779) | Army Truck (Mesh) | bearduckmonkey (User) | Model | 2019-10-15 | 4,699 | 0 | `Vehicles.TroopTransport` |  |
| [4865838](https://create.roblox.com/store/asset/4865838) | fighter jet | stinkyturkey (User) | Model | 2008-10-13 | 15,710 | 6 | `Vehicles._FallbackJet`, `Vehicles.FighterJet`, `Vehicles.InterceptorJet`, `Vehicles.TrainerJet`, `Vehicles.ReconPlane`, `Vehicles.LightFighter` |  |
| [15786579439](https://create.roblox.com/store/asset/15786579439) | Boat | BRicey763 (User) | Model | 2023-12-28 | 772 | 1 | `Vehicles._FallbackNaval`, `Vehicles.RiverBoat`, `Vehicles.MissileBoat`, `Vehicles.MineLayer`, `Vehicles.CoastalMonitor`, `Vehicles.SubSurfaceRunner`, `Vehicles.AttackSub` | Also the family body for the dropped `FastAttackCraft` and `TorpedoBoat` entries |
| [28912351](https://create.roblox.com/store/asset/28912351) | Military Vehicle Meshes | Catmando (User) | Model | 2010-06-15 | 1,452 | 0 | `Vehicles._FallbackWheeled`, `Vehicles.AntiAirTruck`, `Vehicles.CargoVan`, `Vehicles.RecoveryTruck`, `Vehicles.EscortTruck` | Listing: "Free to use!". Also the family body for the dropped `FuelTanker`, `EngineeringTruck` and `FlatbedHauler` entries |

### Characters (dress on Part-kit NPCs)

| Asset ID | Creator Store name | Uploader | Type | Updated | Triangles | Scripts | Used by | Notes |
|---|---|---|---|---|---|---|---|---|
| [14776506955](https://create.roblox.com/store/asset/14776506955) | Army of Soldiers (Rthro) | takinuptoomuchspace (User) | Model | 2023-09-14 | 484,133 | 840 | `Characters.HeavyInfantry` | Uploader: "i used roblox's model" (Rthro). 484k triangles, 840 scripts: W3 phase-out (phone budget) |
| [9104381136](https://create.roblox.com/store/asset/9104381136) | Layered clothing realistic soldier | paquinhos (User) | Model | 2022-03-14 | 29,703 | 0 | `Characters.Infantry`, `Characters.WorkerFallback` | Uploader assembled Marketplace clothing and accessories made by others ("no need to credit"). Pinned Infantry/Worker fallback; W6a replaces with Roblox rigs |
| [100212659702941](https://create.roblox.com/store/asset/100212659702941) | Realistic soldier StarterCharacter | HeitorGameplayBr009 (User) | Model | 2025-08-10 | 20,000 | 2 | `Characters.Soldier` |  |
| [16134469614](https://create.roblox.com/store/asset/16134469614) | Rigged Soldier | Gioele_e (User) | Model | 2024-01-27 | 50,580 | 0 | `Characters.Worker`, `Characters.Guard`, `Characters.BankGuard`, `Characters.OilRigGuard`, `Characters.FortGuard`, `Characters.GateGuard`, `GateDefense.Guard` |  |

### Buildings (dress on structure plinths; PreferMesh stays OFF)

| Asset ID | Creator Store name | Uploader | Type | Updated | Triangles | Scripts | Used by | Notes |
|---|---|---|---|---|---|---|---|---|
| [18798977801](https://create.roblox.com/store/asset/18798977801) | Military Barracks | VoidableCircuit (User) | Model | 2024-08-04 | 336,948 | 0 | `Buildings.Barracks`, `Buildings.SpecialForcesFacility`, `StructureVisualConfig.Barracks`, `StructureVisualConfig.SpecialForcesFacility` | 336,948 triangles: W3 phase-out (phone budget) |
| [85138026](https://create.roblox.com/store/asset/85138026) | USM Gate Please Favorte! | FearlessIantheKiller (User) | Model | 2012-07-01 | 5,876 | 9 | `Buildings.BaseGate` | Watch: "USM" in the title. Check in Studio for national insignia before the owner Gets it |
| [138331074285379](https://create.roblox.com/store/asset/138331074285379) | Military Base | VenomStar40066 (User) | Model | 2026-02-14 | 232,800 | 1 | `Buildings.CommandCenter`, `StructureVisualConfig.CommandCenter` | 232,800 triangles: W3 phase-out (phone budget) |
| [17701461178](https://create.roblox.com/store/asset/17701461178) | Shipping Containers | VGVC2 (User) | Model | 2024-06-02 | 6,176 | 0 | `Buildings.Dock`, `StructureVisualConfig.Dock` | Watch: check the doors for real shipping-line logos before the owner Gets it |
| [6015472062](https://create.roblox.com/store/asset/6015472062) | Hangar | afterrburner (User) | Model | 2020-11-28 | 45,887 | 0 | `Buildings.Hangar`, `VisualAssetService (Airfield composite hangar)` |  |
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
| [4923345827](https://create.roblox.com/store/asset/4923345827) | Machine Gun Nest | Byrdknight (User) | Model | 2020-04-20 | 4,999 | 0 | `GateDefense.AutoGun`, `GateDefenseService default` |  |
| [10354803684](https://create.roblox.com/store/asset/10354803684) | Military turret | gtddgc8 (User) | Model | 2022-07-25 | 14,754 | 5 | `GateDefense.AutoGunElevatedAlt` | The 2022 original of the 2026 re-upload 71964514000054 (dropped) |
| [8980890767](https://create.roblox.com/store/asset/8980890767) | 88th machine gun nest | ValentiusSenatus (User) | Model | 2022-03-01 | 100,126 | 0 | `GateDefense.SandbagNest` | 100,126 triangles: W3 phase-out (phone budget) |
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
| [2652344972](https://create.roblox.com/store/asset/2652344972) | Military ammo/supplies shed | F3rwrd (User) | Model | 2018-12-15 | 13,982 | 0 | `WarzoneProps.AmmoShed` |  |
| [1291725699](https://create.roblox.com/store/asset/1291725699) | [FREE] Barbed Wire Fence | CentralCityLaw (User) | Model | 2018-01-01 | 312 | 1 | `WarzoneProps.BarbedWire` |  |
| [13668977092](https://create.roblox.com/store/asset/13668977092) | Camouflage Netting | AntiSocial_Lasagna (User) | Model | 2023-06-06 | 7,540 | 0 | `WarzoneProps.CamoNet` |  |
| [13437018139](https://create.roblox.com/store/asset/13437018139) | Ghillie Net | Crank_theTank (User) | Model | 2023-05-14 | 6,652 | 0 | `WarzoneProps.CamoNetAlt` |  |
| [91071319](https://create.roblox.com/store/asset/91071319) | Concrete Barrier | HabaneroDude (User) | Model | 2016-08-27 | 868 | 0 | `WarzoneProps.ConcreteBarrier`, `WarzoneProps.Cone` |  |
| [53591587](https://create.roblox.com/store/asset/53591587) | Crate/Box | griflay (User) | Model | 2011-06-10 | 24 | 0 | `WarzoneProps.Crate`, `WarzoneProps.Drum` | "Area 51" in the listing is a place name, not a design |
| [1454179642](https://create.roblox.com/store/asset/1454179642) | [Highly Detailed] Flag Pole | Owl4110 (User) | Model | 2018-02-24 | 912 | 0 | `WarzoneProps.FlagPoleHD` |  |
| [116763933](https://create.roblox.com/store/asset/116763933) | Floodlight | ChillyRaptor (User) | Model | 2013-05-24 | 204 | 1 | `WarzoneProps.Floodlight`, `WarzoneProps.Lamp` |  |
| [4893998573](https://create.roblox.com/store/asset/4893998573) | Floodlight | VladimirDeliyUA (User) | Model | 2020-04-13 | 2,074 | 0 | `WarzoneProps.FloodlightAlt` |  |
| [1160141839](https://create.roblox.com/store/asset/1160141839) | Non-Laggy Fuel Cans and Oil Barrels | WOLFENCHAN (Group) | Model | 2017-11-07 | 7,350 | 0 | `WarzoneProps.FuelCans`, `IndustrialProps.FuelCans` |  |
| [82454061017921](https://create.roblox.com/store/asset/82454061017921) | Concrete Jersey Barrier | 0WowlionPro (User) | Model | 2026-08-04 | 412 | 0 | `WarzoneProps.JerseyBarrier`, `MapDressing.JerseyBarrier` | "Jersey barrier" is the generic name of the barrier type |
| [17156953177](https://create.roblox.com/store/asset/17156953177) | ConcreteBarrierMesh | ek3170 (User) | Model | 2024-04-15 | 308 | 0 | `WarzoneProps.JerseyBarrierAlt`, `MapDressing.JerseyBarrierAlt` |  |
| [976333542](https://create.roblox.com/store/asset/976333542) | Military Crate | sam_youwell (User) | Model | 2017-08-13 | 1,196 | 0 | `WarzoneProps.MilitaryCrate`, `WarzoneProps.Pallet` |  |
| [16540055496](https://create.roblox.com/store/asset/16540055496) | Military Crates | Antonov_Slonovskaya (User) | Model | 2024-02-27 | 8,254 | 0 | `WarzoneProps.MilitaryCratePack` |  |
| [25623924](https://create.roblox.com/store/asset/25623924) | Oil Barrel | raldude1 (User) | Model | 2010-04-15 | 480 | 0 | `WarzoneProps.OilBarrel`, `WarzoneProps.Fence`, `IndustrialProps.OilBarrel` |  |
| [9701862157](https://create.roblox.com/store/asset/9701862157) | MILITARY PORTABLE LIGHT TOWER | declan1954 (User) | Model | 2022-05-22 | 1,208 | 2 | `WarzoneProps.PortableLightTower` |  |
| [19277831](https://create.roblox.com/store/asset/19277831) | radio antenna | ak74dd (User) | Model | 2009-12-15 | 652 | 0 | `WarzoneProps.RadioAntenna`, `WarzoneProps.Radio` |  |
| [42209845](https://create.roblox.com/store/asset/42209845) | Radio Antenna | MrTw0fer (User) | Model | 2010-12-16 | 360 | 0 | `WarzoneProps.RadioAntennaAlt` |  |
| [15912051001](https://create.roblox.com/store/asset/15912051001) | Concrete Barriers | s1ix6 (User) | Model | 2024-01-07 | 9,248 | 0 | `WarzoneProps.RoadBarriers` |  |
| [8176692221](https://create.roblox.com/store/asset/8176692221) | Destroyed Building | SURPRlSE0 (User) | Model | 2021-12-04 | 15,156 | 2 | `WarzoneProps.RuinedBuilding` |  |
| [104053043839965](https://create.roblox.com/store/asset/104053043839965) | Old brick wall (Mossy or smth) | Guest_62246 (User) | Model | 2025-01-06 | 20,000 | 0 | `WarzoneProps.RuinedWall` |  |
| [12651656400](https://create.roblox.com/store/asset/12651656400) | Sandbag Barrier | Aheadit (User) | Model | 2023-03-01 | 7,493 | 0 | `WarzoneProps.SandbagBarrier` |  |
| [25733125](https://create.roblox.com/store/asset/25733125) | Sandbag wall | SpecialOp (User) | Model | 2010-04-17 | 3,624 | 0 | `WarzoneProps.SandbagWall`, `WarzoneProps.Barrier` |  |
| [123546710527428](https://create.roblox.com/store/asset/123546710527428) | StreetLamp_A | chiroxli (User) | Model | 2026-03-29 | 1,860 | 0 | `WarzoneProps.StreetLamp` |  |
| [8180880144](https://create.roblox.com/store/asset/8180880144) | Modified Street light [Light version] | AloysiousCatindoy (User) | Model | 2021-12-05 | 24,338 | 8 | `WarzoneProps.StreetLampAlt` | Derivative; uploader credits "the original owners … James": credited here. Watch (W3) |
| [82560800252069](https://create.roblox.com/store/asset/82560800252069) | Military Vehicle Shed Army Base Bunker Barrack | 4x4basspeep (User) | Model | 2026-04-30 | 45,717 | 9 | `WarzoneProps.SupplyShed` | Watch: listing uses the same keyword-spam block as the dropped 111066366655290 (re-upload pattern). W3 |
| [9171585794](https://create.roblox.com/store/asset/9171585794) | destroyed tank | lobo73_audas (User) | Model | 2022-03-22 | 9,012 | 0 | `WarzoneProps.TankWreck` |  |
| [6883609157](https://create.roblox.com/store/asset/6883609157) | Military Tent | ForestFireTree1 (User) | Model | 2023-11-29 | 9,932 | 0 | `WarzoneProps.Tent` |  |
| [3133150032](https://create.roblox.com/store/asset/3133150032) | Military Tent | MrKotikXD (User) | Model | 2022-01-22 | 38,324 | 9 | `WarzoneProps.TentAlt` |  |

### Desert props

| Asset ID | Creator Store name | Uploader | Type | Updated | Triangles | Scripts | Used by | Notes |
|---|---|---|---|---|---|---|---|---|
| [16354482789](https://create.roblox.com/store/asset/16354482789) | CactusBase2 | creepersaur (User) | Model | 2024-02-22 | — | 0 | `DesertProps.CactusBase` |  |
| [6562523344](https://create.roblox.com/store/asset/6562523344) | Low Poly Rocks Pack | GYPLA6 (User) | MeshPart | 2024-03-02 | — | — | `DesertProps.DesertRock`, `MapDressing.DesertRock` | Loaded as MeshPart.MeshId (not LoadAssetAsync); works only if the mesh is Open Use |
| [96059329869678](https://create.roblox.com/store/asset/96059329869678) | Palm Trees Realistic Tropical Island Beach Pack | BellaLion62438 (User) | Model | 2026-02-05 | — | 0 | `DesertProps.Palm`, `MapDressing.Palm` |  |
| [105982075286356](https://create.roblox.com/store/asset/105982075286356) | Low Poly Palm Tree Coconut Summer Tree isla | LaylaDawn2564 (User) | Model | 2026-02-11 | 3,229 | 1 | `DesertProps.PalmAlt`, `MapDressing.PalmAlt` |  |

### Map dressing aliases

| Asset ID | Creator Store name | Uploader | Type | Updated | Triangles | Scripts | Used by | Notes |
|---|---|---|---|---|---|---|---|---|
| [10197707775](https://create.roblox.com/store/asset/10197707775) | asphalt road texture | ZePurpleCat (User) | Image (decal) | 2023-08-05 | — | — | `MapDressing.AsphaltDecal` | Road texture set as Decal.Texture (not LoadAssetAsync) |
| [12809476227](https://create.roblox.com/store/asset/12809476227) | Desert Mountain | falterize (User) | Model | 2023-03-17 | 156,326 | 0 | `MapDressing.DesertMesa`, `Landmarks.DesertMesa` | 156,326 triangles: W3 phase-out (phone budget) |

### Industrial props

| Asset ID | Creator Store name | Uploader | Type | Updated | Triangles | Scripts | Used by | Notes |
|---|---|---|---|---|---|---|---|---|
| [13525922265](https://create.roblox.com/store/asset/13525922265) | Realistic Oil Pumpjack | Unit5532 (User) | Model | 2023-05-23 | 11,318 | 0 | `IndustrialProps.OilPumpjack` |  |
| [15192621369](https://create.roblox.com/store/asset/15192621369) | Oil Rig / Pumpjack | sadfiacs (User) | Model | 2023-11-03 | 1,398 | 0 | `IndustrialProps.OilPumpjackAlt` | Listing: "Mesh Inspiration: Karcist" (inspiration only) |

### Landmarks

| Asset ID | Creator Store name | Uploader | Type | Updated | Triangles | Scripts | Used by | Notes |
|---|---|---|---|---|---|---|---|---|
| [867696371](https://create.roblox.com/store/asset/867696371) | Bridge and checkpoint ww2 | Illinois_Lawz (User) | Model | 2017-06-15 | — | 0 | `Landmarks.CheckpointBridge` |  |
| [9136197032](https://create.roblox.com/store/asset/9136197032) | Desert house | stabok61 (User) | Model | 2022-03-18 | 2,568 | 0 | `Landmarks.DesertHouse` |  |
| [11138299907](https://create.roblox.com/store/asset/11138299907) | Boat Dock | v6cvk (User) | Model | 2022-10-01 | 840 | 0 | `Landmarks.Pier` |  |
| [119021509](https://create.roblox.com/store/asset/119021509) | Radio Tower | George256 (User) | Model | 2013-06-14 | 22,836 | 0 | `Landmarks.RadioTower` |  |
| [67444725](https://create.roblox.com/store/asset/67444725) | Small Fort | ballygoat (User) | Model | 2011-12-11 | 72 | 0 | `Landmarks.SmallFort` |  |
| [55228082](https://create.roblox.com/store/asset/55228082) | Spy Bunker | Azraekan (User) | Model | 2011-07-01 | 2,962 | 0 | `Landmarks.SpyBunker` |  |

## 4. Follow-ups outside `VisualAssetConfig` (not CFG's files)

1. **`StructureVisualConfig.luau` line 152**: `MeshAssetId = 11962508154` (MissileDefense). `ResolveBuildingAssetId` falls
   back to this field when `VisualAssetConfig.Buildings.MissileDefense` is 0, so the HIMARS-type launcher still resolves for
   MissileDefense plinths until it is set to `MeshAssetId = 0`. BuyPathStatic pins `MeshAssetId = 11962508154` for that file;
   whoever edits it re-pins to the new text.
2. **`VisualAssetService.luau` line 936**: a comment still names the paid ATM ID 75368157644109 ("Prefer Design Bot hero …").
   No runtime effect. Next writer of that file (JEEP-1, then LOOK) rewrites it as "MoneyCollector (0 in W1) → 175462478 → alts".
3. **Watch rows** in §3 (USM Gate, Shipping Containers, the floodlight-tower mismatch, the two identical army trucks, the
   modified street light) go to LOOK in W3, which phases out the remaining third-party IDs for Roblox-owned packs.
4. **`THIRD_PARTY_NOTICES.md`** (roadmap §4) is for parts we adopt (Weapons Kit, Synty, LUV, the desert pack, MIT code). It
   lands with the first adopted part. The credits requested by uploaders of the IDs above are in the notes of §3.

## 5. Other external IDs in `src/` (listed elsewhere)

- `Shared/Configs/SoundConfig.luau`: sound IDs owned by SND (W1). Roblox licensed library and Roblox-owned engine loops
  (D4): in-game only, never in YouTube or TikTok promos. SND documents them there.
- `Shared/Configs/MonetizationConfig.luau`: game-pass and developer-product IDs of our own experience, not third-party assets.
- `rbxasset://` paths (`textures/face.png`, `sounds/electronicpingshort.wav`, `textures/particles/smoke_main.dds`): content
  shipped with the Roblox client.

## 6. What the owner must test on his phone

Nothing changes on screen while "Allow Loading Third Party Assets" stays OFF: the headless world build with Full dressing
at L5 gave the same 7,941 parts and 802 GUIs before and after, asked for none of the §2 IDs, and logged 9 fewer
failed-load warnings. The headless stand-in is not Roblox. On the phone: nothing to see. In Studio, check Game Settings ›
Security: the setting is OFF. After publishing, the live Developer Console (F9) should show no `LoadAsset failed` line
for an ID in §2, except 11962508154 on a MissileDefense plinth until §4 item 1 lands.
