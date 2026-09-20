# DESIGN WIRE GAPS v40 — FILLED (Design Bot)
**Date:** 2026-09-20 · Answers Code Bot inventory  
**Law:** Mesh dress ON visible Part kits — never hide Body. Free Models only (`IsForSale=false` / PD). Soft catalog brand names → neutral DisplayNames.

Thumbs: `/workspace/war-empire-audit/thumbs/gaps/` + `v40/` + `buildings/`

---

## P0 STRUCTURES — Hangar ≠ Warehouse ≠ Depot · Missile ≠ Watchtower

| Key | ModelAssetId | DisplayName | Notes |
|-----|-------------:|-------------|-------|
| **Hangar** | **6015472062** | Hangar | Large bay-door aircraft hangar (KEEP primary) |
| **Warehouse** | **15942568272** | Warehouse | “Hangar shed” — multi-bay industrial, **≠ Hangar** |
| **VehicleDepot** | **12208876851** | Vehicle Depot | Arched quonset / garage — **≠ Hangar/Warehouse** |
| HangarAlt | 12208876851 | — | If 6015472062 insert fails, swap Depot to 6015472062 |
| **Watchtowers** | **108525417345747** | Watchtower | KEEP tall outpost |
| **MissileDefense** | **11962508154** | Missile Battery | Mobile 4-canister launcher — **≠ Watchtower** |
| MissileDefenseAlt | **14074034450** | Mobile SAM | TEL launcher (catalog “S-300” → DisplayName Mobile SAM) |
| SpecialForcesFacility | **18798977801** | Special Forces HQ | Same mesh as Barracks OK — **camo Accent palette** only (no better free SF HQ) |
| Airfield | **0** | Airfield | COMPOSITE runway Decal `10197707775` + Hangar `6015472062` |
| BaseCeiling | **0** | — | Part-kit OK |
| DefensiveWalls | **0** | — | No segment mesh dress |

```lua
Hangar = { ModelAssetId = 6015472062, Note = "Aircraft bay hangar" },
Warehouse = { ModelAssetId = 15942568272, Note = "Hangar shed multi-bay warehouse" },
VehicleDepot = { ModelAssetId = 12208876851, Note = "Arched depot/garage" },
Watchtowers = { ModelAssetId = 108525417345747, Note = "Outpost tower" },
MissileDefense = { ModelAssetId = 11962508154, Note = "Missile Battery launcher ≠ tower" },
```

StructureVisualConfig footprints (dress on kit):
```lua
Hangar / use Airfield hangar accent: TargetFootprint = Vector3.new(40, 18, 28),
Warehouse = { MeshAssetId = 15942568272, TargetFootprint = Vector3.new(38, 16, 24) },
VehicleDepot = { MeshAssetId = 12208876851, TargetFootprint = Vector3.new(32, 14, 24) },
MissileDefense = { MeshAssetId = 11962508154, TargetFootprint = Vector3.new(14, 10, 18) }, -- launcher mass, not tower height
Watchtowers = { MeshAssetId = 108525417345747, TargetFootprint = Vector3.new(10, 34, 10) },
```

---

## P0 VEHICLES — break `26007709` · break `13195201090`

### Tank / IFV / Arty / SPAAG (was all 26007709)

| Key | ModelAssetId | DisplayName | Family |
|-----|-------------:|-------------|--------|
| LightTank | **76055078503396** | Light Tank | IFV/tank mesh |
| LightScoutTank | **76055078503396** | Scout Tank | same |
| CombatIFV | **76055078503396** | Combat IFV | same |
| AssaultIFV | **76055078503396** | Assault IFV | same |
| MediumTank | **26007709** | Medium Tank | Demote classic free tank here only |
| BattleTank / HeavyTank / SuperHeavyTank / FortressTank / RailgunCarrier | **19297043** | Battle Tank | Mammoth MBT KEEP |
| TankDestroyer / AssaultGun | **19297043** | Tank Destroyer | Mammoth silhouette OK |
| BridgeLayer / MineClearer / FlameCarrier | **76055078503396** | Engineer Track | IFV hull dress (unique ≠ MediumTank id path) |
| SPAAG | **15618784436** | AA Gun | Towed/mobile AA mesh |
| MobileSAM | **14074034450** | Mobile SAM | TEL (was tank reuse) |
| MortarCarrier / MobileArtillery / HowitzerTruck / SiegeMortar | **10286064243** | Howitzer | Field gun |
| HowitzerAlt | **8312399501** | Field Gun | Insert fallback |
| RocketArtillery | **18406068364** | Rocket Artillery | MLRS truck (catalog Katyusha → DisplayName Rocket Artillery) |
| RocketArtilleryAlt | **10355405319** | Heavy Rockets | BM-27 pack alt |

```lua
LightTank = { ModelAssetId = 76055078503396, Note = "v40 Light Tank/IFV" },
CombatIFV = { ModelAssetId = 76055078503396, Note = "v40 Combat IFV" },
AssaultIFV = { ModelAssetId = 76055078503396, Note = "v40 Assault IFV" },
LightScoutTank = { ModelAssetId = 76055078503396, Note = "v40 Scout Tank" },
BridgeLayer = { ModelAssetId = 76055078503396, Note = "Engineer Track" },
MineClearer = { ModelAssetId = 76055078503396, Note = "Engineer Track" },
FlameCarrier = { ModelAssetId = 76055078503396, Note = "Engineer Track" },
MediumTank = { ModelAssetId = 26007709, Note = "Classic free tank — Medium only" },
SPAAG = { ModelAssetId = 15618784436, Note = "AA Gun" },
MobileSAM = { ModelAssetId = 14074034450, Note = "Mobile SAM TEL" },
MortarCarrier = { ModelAssetId = 10286064243, Note = "Howitzer" },
MobileArtillery = { ModelAssetId = 10286064243, Note = "Howitzer" },
HowitzerTruck = { ModelAssetId = 10286064243, Note = "Howitzer" },
SiegeMortar = { ModelAssetId = 10286064243, Note = "Howitzer" },
RocketArtillery = { ModelAssetId = 18406068364, Note = "Rocket Artillery MLRS" },
```

### Capital naval (was all 13195201090)

| Key | ModelAssetId | DisplayName | Notes |
|-----|-------------:|-------------|-------|
| PatrolBoat / Gunboat / CoastCutter / RiverBoat | **557152593** | Patrol Boat | From feature wire |
| FastAttackCraft / TorpedoBoat | **16692908395** | Attack Boat | PT boat |
| LandingCraft / AssaultLanding / AmphibAssault | **0** | Landing Craft | **Part-kit barge** + container dress `17701461178` — REJECT template |
| HoverTransport / HospitalShip / SupplyShip | **0** | — | Part-kit hull |
| Frigate / Corvette / CarrierEscort | **12794395111** | Frigate | Multipurpose Frigate |
| Destroyer | **2048010298** | Destroyer | Capital destroyer mesh |
| Cruiser / MissileCruiser | **74585287273804** | Cruiser | Destroyer/cruiser w/ seaplane deck |
| Battleship | **2048010298** | Battleship | Scale up Destroyer until better BB |
| AircraftCarrier / FleetCarrier | **0** | Carrier | **Part-kit flight deck** — no strong free carrier |

```lua
PatrolBoat = { ModelAssetId = 557152593, Note = "Navy Patrol Boat" },
FastAttackCraft = { ModelAssetId = 16692908395, Note = "Attack Boat" },
LandingCraft = { ModelAssetId = 0, Note = "Part-kit — REJECT 13195201090" },
AssaultLanding = { ModelAssetId = 0, Note = "Part-kit barge" },
Frigate = { ModelAssetId = 12794395111, Note = "Multipurpose Frigate" },
Corvette = { ModelAssetId = 12794395111, Note = "Frigate scaled" },
Destroyer = { ModelAssetId = 2048010298, Note = "Destroyer" },
Cruiser = { ModelAssetId = 74585287273804, Note = "Cruiser" },
MissileCruiser = { ModelAssetId = 74585287273804, Note = "Cruiser" },
Battleship = { ModelAssetId = 2048010298, Note = "Destroyer scaled capital" },
AircraftCarrier = { ModelAssetId = 0, Note = "Part-kit carrier deck" },
FleetCarrier = { ModelAssetId = 0, Note = "Part-kit carrier deck" },
-- Nuke all remaining 13195201090 refs
```

### Trucks (P1 from feature wire — reinforce)
`100684175` Cargo Truck · `81802040484766` Logistics · `4128346779` Army Truck · keep `105503568352704` PatrolTruck — break `28912351`.

---

## P0 CHARACTERS — Worker ≠ Soldier

| Key | ModelAssetId | DisplayName | Notes |
|-----|-------------:|-------------|-------|
| Soldier | **100212659702941** | Soldier | Spec-ops KEEP |
| Infantry | **9104381136** | Infantry | KEEP |
| **Worker** | **16134469614** | Worker | Rigged Soldier NVG — **≠ Soldier** |
| WorkerFallback | **9104381136** | — | If Worker insert fails |
| HeavyInfantry | **14776506955** | Heavy Infantry | KEEP |
| Guard* / GateGuard | **16134469614** | Guard | Same mesh as Worker OK (role tags differ) |
| SpecialForces | **123239877613650** | Special Forces | Camo GI |
| SpecialForcesAlt | **4851009700** | Marksman | Fallback |

```lua
Soldier = { ModelAssetId = 100212659702941, Note = "Spec-ops Soldier" },
Worker = { ModelAssetId = 16134469614, Note = "v40 Worker ≠ Soldier" },
SpecialForces = { ModelAssetId = 123239877613650, Note = "SF camo" },
```

---

## REJECT (gap-fill)

| Id | Why |
|----|-----|
| `26007709` on LightTank/IFV/arty/SPAAG | Weak classic — MediumTank only |
| `13195201090` | Build-a-Boat template — not naval |
| `6015472062` on Warehouse+Depot+Hangar together | Split — Hangar only (or HangarAlt) |
| `108525417345747` on MissileDefense | Tower ≠ launcher |
| `12120702` | Glass office — not warehouse |
| `12630605935` | Civilian “Airplane Hangar” text |
| Nation-branded gates / plastic Rthro / SWAT | Standing orders |

---

## NEXT
Wire Luau rows above into VisualAssetConfig + StructureVisualConfig. Ping Design Bot on InsertService rejects (alts listed).
