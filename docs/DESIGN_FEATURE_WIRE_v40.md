# DESIGN FEATURE WIRE v40 — Design Bot → Code Bot
**Date:** 2026-09-20 · **AMENDED** gap-fill (Hangar≠Warehouse≠Depot, Missile≠Tower, tank/arty/naval split, Worker≠Soldier)  
**See also:** `DESIGN_WIRE_GAPS_v40.md` (filled)  
**Law:** Part kits stay **visible**. Catalog mesh is **optional dress ON TOP** — never hide Body/Roof.

---

## AMENDMENT — P0 uniqueness (wire these)

### Structures
| Key | ModelAssetId | DisplayName |
|-----|-------------:|-------------|
| Hangar | **6015472062** | Hangar |
| Warehouse | **15942568272** | Warehouse |
| VehicleDepot | **12208876851** | Vehicle Depot |
| MissileDefense | **11962508154** | Missile Battery |
| MissileDefenseAlt | 14074034450 | Mobile SAM |
| Watchtowers | 108525417345747 | Watchtower |

### Vehicles (break 26007709 / 13195201090)
| Key | ModelAssetId | DisplayName |
|-----|-------------:|-------------|
| LightTank / CombatIFV / AssaultIFV / LightScoutTank / BridgeLayer / MineClearer / FlameCarrier | **76055078503396** | Light Tank / IFV / Engineer Track |
| MediumTank | **26007709** | Medium Tank |
| SPAAG | **15618784436** | AA Gun |
| MobileSAM | **14074034450** | Mobile SAM |
| MortarCarrier / MobileArtillery / HowitzerTruck / SiegeMortar | **10286064243** | Howitzer |
| RocketArtillery | **18406068364** | Rocket Artillery |
| Frigate / Corvette | **12794395111** | Frigate |
| Destroyer / Battleship | **2048010298** | Destroyer |
| Cruiser / MissileCruiser | **74585287273804** | Cruiser |
| LandingCraft / Carrier / FleetCarrier | **0** | Part-kit — REJECT 13195201090 |

### Characters
| Key | ModelAssetId |
|-----|-------------:|
| Soldier | 100212659702941 |
| Worker | **16134469614** (≠ Soldier) |
| SpecialForces | 123239877613650 |

```lua
-- StructureVisualConfig
Warehouse = { MeshAssetId = 15942568272, TargetFootprint = Vector3.new(38, 16, 24) },
VehicleDepot = { MeshAssetId = 12208876851, TargetFootprint = Vector3.new(32, 14, 24) },
MissileDefense = { MeshAssetId = 11962508154, TargetFootprint = Vector3.new(14, 10, 18) },
-- VisualAssetConfig.Buildings
Hangar = { ModelAssetId = 6015472062 },
Warehouse = { ModelAssetId = 15942568272 },
VehicleDepot = { ModelAssetId = 12208876851 },
MissileDefense = { ModelAssetId = 11962508154 },
-- Characters
Worker = { ModelAssetId = 16134469614, Note = "≠ Soldier" },
```

---

## LOOK — Priority order
1. HQ + Barracks + **gate prop** (not wall segments)  
2. Vehicles (break reuse families)  
3. Soldier role distinctness  
4. Bonus: pumpjack + ceiling stays Part-kit  

---

## STRUCTURES — KEEP / SWAP

| StructureId | ModelAssetId | DisplayName | Category | Why military-legit | Scale / kit notes |
|-------------|-------------:|-------------|---------|--------------------|-------------------|
| CommandCenter | **138331074285379** | Command Center | Buildings | Military Base compound — best free HQ | KEEP. TargetFootprint `36×16×28`. Dress **on** hq kit; do not Transparency Body. Alt none. |
| Barracks | **18798977801** | Barracks | Buildings | Corrugated troop housing, door+steps | KEEP. Footprint `28×12×16`. |
| SpecialForcesFacility | **18798977801** | Special Forces HQ | Buildings | Same mesh; **camo Accent** palette so distinct from Barracks | KEEP mesh; visual via palette only. |
| VehicleDepot | **6015472062** | Vehicle Depot | Buildings | Large bay hangar silhouette | KEEP. `32×14×24`. Alt hangar `12208876851` if insert fails. |
| Warehouse | **6015472062** | Warehouse | Buildings | Same bay family | KEEP. `38×16×24`. |
| Hangar | **6015472062** | Hangar | Buildings | Best free large hangar | KEEP. Airfield accent. REJECT tiny `46981739`. |
| WeaponsFacility | **4120970784** | Armory | Buildings | Tall 3-story barracks = armory mass | KEEP. Height ≥16. |
| Helipad | **14313845338** | Helipad | Buildings | Pad markings | KEEP. Flat `28×4×28` + Part H circle. Kit pad must stay visible. |
| Airfield | **0** COMPOSITE | Airfield | Buildings | Runway + hangar | KEEP composite: asphalt Decal `10197707775` on Part `72×1×14` + Hangar `6015472062`. REJECT `12370174722`. |
| Watchtowers | **108525417345747** | Watchtower | Buildings | Tall military outpost | KEEP. `10×34×10`. Alt `3330023556`. |
| Radar | **9559610195** | Radar Station | Buildings | Dish on base | KEEP. `14×18×14`. |
| PowerStation | **14000967030** | Power Plant | Buildings | Coal plant mass | KEEP. `28×16×20`. |
| ResearchLab | **17725725** | Research Lab | Buildings | Lab building | KEEP. `22×12×16`. |
| Dock | **17701461178** | Dock | Buildings | Shipping containers as **dock dress** | KEEP dress only — Part pier kit stays visible underneath. `44×10×28`. |
| MissileDefense | **108525417345747** | Missile Battery | Buildings | Outpost tower reuse | KEEP. |
| Bunker | **16659447** | Bunker | Buildings | Hardened emplacement | KEEP. |
| DefensiveWalls | **0** | Perimeter Wall | Buildings | **No segment mesh dress** (v39) | **SET MeshAssetId=0** (and L3=0). Part-kit walls only. |
| GateArch / BaseGate | **85138026** | Base Gate | Gate prop | Olive posts + lattice gate — military checkpoint | **NEW** gate prop only (not wall segment). Scale ~`16×12×4`. Strip scripts. DisplayName **Base Gate** (catalog “USM Gate”). |
| GateArchReject | 11399477618 / 10339789720 | — | — | Nation-branded arches (PH / VN text) | **REJECT** |
| TrainingStall | **6883609157** | Training Stall | Props | Tent / tarp stall (quality-gap) | KEEP + lantern `10121519149`. Soften WORKER tags per UI_WORKER_P0. |
| BaseCeiling | **0** | Base Ceiling | Anti-heli | No strong free roof Model | **KEEP Part-kit** gunmetal translucent plates. REJECT civilian hangar with blue “Airplane Hangar” text `12630605935` as ceiling. |

### StructureVisualConfig Luau rows (copy-paste)
```lua
-- KIT_GEN 27: PreferMeshWhenAssetIdSet dresses ON kit; never hide Body
CommandCenter = { MeshAssetId = 138331074285379, TargetFootprint = Vector3.new(36, 16, 28) },
Barracks = { MeshAssetId = 18798977801, TargetFootprint = Vector3.new(28, 12, 16) },
VehicleDepot = { MeshAssetId = 6015472062, TargetFootprint = Vector3.new(32, 14, 24) },
WeaponsFacility = { MeshAssetId = 4120970784, TargetFootprint = Vector3.new(28, 18, 18) },
Helipad = { MeshAssetId = 14313845338, TargetFootprint = Vector3.new(28, 4, 28) },
Dock = { MeshAssetId = 17701461178, TargetFootprint = Vector3.new(44, 10, 28) },
Airfield = { MeshAssetId = 0, TargetFootprint = Vector3.new(72, 1, 14) }, -- composite
DefensiveWalls = { MeshAssetId = 0, MeshAssetIdL3 = 0, TargetFootprint = Vector3.new(24, 8, 3) }, -- NO wall segment dress
Watchtowers = { MeshAssetId = 108525417345747, TargetFootprint = Vector3.new(10, 34, 10) },
Radar = { MeshAssetId = 9559610195, TargetFootprint = Vector3.new(14, 18, 14) },
PowerStation = { MeshAssetId = 14000967030, TargetFootprint = Vector3.new(28, 16, 20) },
Warehouse = { MeshAssetId = 6015472062, TargetFootprint = Vector3.new(38, 16, 24) },
SpecialForcesFacility = { MeshAssetId = 18798977801, TargetFootprint = Vector3.new(32, 16, 20) },
```

### VisualAssetConfig.Buildings extras
```lua
Hangar = { ModelAssetId = 6015472062, Note = "Hangar primary; alt 12208876851" },
HangarAlt = { ModelAssetId = 12208876851, Note = "Hangar insert fallback" },
BaseGate = { ModelAssetId = 85138026, Note = "Gate arch prop ONLY — DisplayName Base Gate" },
BaseCeiling = { ModelAssetId = 0, Note = "Part-kit anti-heli roof — no free dedicated Model" },
DefensiveWalls = { ModelAssetId = 0, Note = "v40: no Wall* segment catalog dress" },
DefensiveWallsL3 = { ModelAssetId = 0, Note = "v40: Part-kit heavy walls" },
```

---

## VEHICLES — break reuse (P1)

| Role | ModelAssetId | DisplayName | Why | Notes |
|------|-------------:|-------------|-----|-------|
| MilitaryJeep | **125916936788670** | Military Jeep | Olive 4×4 + MG — P0 winner | KEEP |
| ArmedJeep | **122068883442022** | Armed Jeep | Tan turreted | KEEP; soft catalog Humvee — DisplayName Armed Jeep |
| LightTank | **76055078503396** | Light Tank | Realistic desert IFV/tank mesh | **REPLACE** weak `26007709` |
| CombatIFV / AssaultIFV | **76055078503396** | Combat IFV | Same family OK once | Was tank reuse |
| MediumTank | **26007709** | Medium Tank | Keep classic until better MBT mesh | Soft keep; prefer Mammoth for heavy |
| HeavyTank+ | **19297043** | Battle Tank | Mammoth MBT | KEEP |
| PatrolTruck / ArmoredTruck / SupplyTruck | **105503568352704** | Patrol Truck | Army truck PBR | KEEP primary truck |
| FuelTanker / FlatbedHauler / EngineeringTruck | **100684175** | Cargo Truck | Olive 6×6 cargo bed — distinct from PatrolTruck | **REPLACE** `28912351` pack reuse. Soft catalog “Stalwart M35” → DisplayName **Cargo Truck** |
| TroopTransport alt | **4128346779** | Army Truck | Mesh truck/utility | Unique vs Jeep family |
| AmmoCarrier / MissileTruck / RadarTruck | **81802040484766** | Logistics Truck | PBR army truck variant | Break `28912351` |
| APC / InfantryCarrier | **17835143223** | APC | Prefer APC | KEEP |
| PatrolBoat / Gunboat / CoastCutter | **557152593** | Patrol Boat | Grey navy patrol w/ turrets | **REPLACE** `15786579439` reuse |
| FastAttackCraft / TorpedoBoat | **16692908395** | Attack Boat | WW2 PT boat silhouette | **NEW** unique naval |
| LandingCraft / AssaultLanding | **0** Part-kit OR **557152593** scaled | Landing Craft | No strong free LCM found | **REJECT** Build-a-Boat template `13195201090` as capital ships. Use Part-kit barge + containers `17701461178` dress, or scaled Patrol Boat stub. |
| Capital ships (Destroyer/Carrier/…) | **0** | — | — | Keep Part-kit hulls until free capital meshes; stop `13195201090` spam |
| TransportHeli / parked heli | **9753309** / **5935419** | Transport Heli / Utility Heli | Classic free helis | KEEP parked dress |
| AttackHelicopter | **295607934** | Attack Heli | Gunship | KEEP |
| FighterJet | **4865838** | Fighter Jet | Classic free | KEEP |
| StrikeJet | **5507592781** | Strike Jet | CAS | KEEP |
| Bomber family | **3319732457** | Bomber | Cargo/AWACS family | KEEP |

### VisualAssetConfig.Vehicles Luau rows
```lua
LightTank = { ModelAssetId = 76055078503396, Note = "v40 IFV/tank mesh — DisplayName Light Tank" },
CombatIFV = { ModelAssetId = 76055078503396, Note = "v40 Combat IFV" },
AssaultIFV = { ModelAssetId = 76055078503396, Note = "v40 Assault IFV" },
FuelTanker = { ModelAssetId = 100684175, Note = "Cargo Truck olive 6x6 — not 28912351" },
FlatbedHauler = { ModelAssetId = 100684175, Note = "Cargo Truck" },
EngineeringTruck = { ModelAssetId = 100684175, Note = "Cargo Truck" },
AmmoCarrier = { ModelAssetId = 81802040484766, Note = "Logistics Truck PBR" },
MissileTruck = { ModelAssetId = 81802040484766, Note = "Logistics Truck PBR" },
RadarTruck = { ModelAssetId = 81802040484766, Note = "Logistics Truck PBR" },
TroopTransport = { ModelAssetId = 4128346779, Note = "Army Truck mesh unique" },
PatrolBoat = { ModelAssetId = 557152593, Note = "Navy Patrol Boat" },
Gunboat = { ModelAssetId = 557152593, Note = "Navy Patrol Boat" },
FastAttackCraft = { ModelAssetId = 16692908395, Note = "Attack Boat PT" },
TorpedoBoat = { ModelAssetId = 16692908395, Note = "Attack Boat PT" },
LandingCraft = { ModelAssetId = 0, Note = "Part-kit barge — REJECT 13195201090 template" },
-- Capital naval: ModelAssetId = 0 until free capital mesh
```

---

## SOLDIERS — distinct roles

| Role | ModelAssetId | DisplayName | Why |
|------|-------------:|-------------|-----|
| Soldier | **100212659702941** | Soldier | Spec-ops / gas-mask — KEEP |
| Infantry | **9104381136** | Infantry | Helmet+MOLLE — KEEP |
| Worker | **16134469614** | Worker | NVG/balaclava — **distinct from Infantry** (was same as Soldier) |
| WorkerFallback | **9104381136** | — | If Guard insert fails |
| HeavyInfantry | **14776506955** | Heavy Infantry | KEEP |
| Guard / GateGuard / Fort* | **16134469614** | Guard | KEEP |
| SpecialForces | **123239877613650** | Special Forces | Camo plate-carrier GI — **NEW** |
| SpecialForcesAlt | **4851009700** | Marksman | Sniper beret — SF variant / insert fallback |

```lua
Worker = { ModelAssetId = 16134469614, Note = "v40 distinct Worker (Rigged Soldier)" },
SpecialForces = { ModelAssetId = 123239877613650, Note = "Army Soldier Camo — SF" },
SpecialForcesAlt = { ModelAssetId = 4851009700, Note = "Sniper Soldier fallback" },
```

Map `SoldierConfig.VisualKind.SpecialForces = "SpecialForces"` when SF unit ships.

---

## BONUS — Oil / ceiling

| Asset | ModelAssetId | DisplayName | Notes |
|-------|-------------:|-------------|-------|
| OilPumpjack | **13525922265** | Oil Pumpjack | Realistic nodding donkey — **REPLACE** weak IndustrialPack silhouette |
| OilPumpjackAlt | **15192621369** | Oil Pumpjack | Alt if insert fails |
| GoldenPumpjack | **13525922265** + gold recolor | Golden Pumpjack | Same mesh; Accent/Color3 gold on counterweights — no better free “golden” mesh |
| BaseCeiling | **0** | — | Part-kit only |

```lua
OilPumpjack = { ModelAssetId = 13525922265, Note = "Realistic Oil Pumpjack" },
OilPumpjackAlt = { ModelAssetId = 15192621369, Note = "Oil Rig / Pumpjack alt" },
```

---

## GATE DEFENSE (already live v23 — reinforce)
- Guard `16134469614` · AutoGun `4923345827` · Sandbags `3525056989` · Nest `8980890767`  
- Pair with **BaseGate** `85138026` at plot entrance  

---

## REJECT (explicit)

| Id / pattern | Why |
|--------------|-----|
| hideKitBody / Body Transparency ≥0.85 after dress | Empty-base bug — **forbidden** |
| MeshPart.Size = host plinth | Squashes dress — use ScaleTo TargetFootprint |
| DefensiveWalls MeshAssetId ≠ 0 | No Wall* segment dress |
| `12370174722` Airfield | Blockout Part boxes |
| `46981739` Plane Hangar | Tiny classic |
| `13195201090` Build-a-Boat template | Not naval — stop capital reuse |
| `28912351` as every truck | Mesh pack reuse — break with Cargo/Logistics IDs |
| `26007709` as LightTank primary | Weak Part-kit tank — demote to Medium only |
| `11399477618` / `10339789720` gates | Nation text branding |
| `12855228201` Yogyakarta arch | Civilian / off-theme |
| `12630605935` Airplane Hangar | Blue civilian text — not ceiling |
| `274040769` / `2608948785` tanks | Blocky Part-kit junk |
| `8002205857` voxel boat | Toy/voxel |
| TF2/SCP/neon sentries, SWAT/police NPCs, plastic Rthro `3924234975`, Respawn pack `91299598767068` as primary | Standing orders |
| Giant AlwaysOnTop structure name billboards | Keep UI_WORKER_P0 priority |

---

## NEXT — Code Bot
1. Wire BaseGate `85138026` + zero out DefensiveWalls segment meshes.  
2. Vehicle uniqueness rows (LightTank / Cargo Truck / Patrol Boat / Attack Boat / LandingCraft=0).  
3. Worker + SpecialForces character rows.  
4. OilPumpjack `13525922265`.  
5. Republish; StudioForceDress — confirm kits still visible under dress.  
6. Ping Design Bot on InsertService rejects.
