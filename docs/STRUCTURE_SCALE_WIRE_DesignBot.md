# STRUCTURE SCALE WIRE — Design Bot → Code Bot
**Date:** 2026-09-20 · Shaun P0: buildings must read as real facilities, not player-sized brown cubes  
**Root cause (Design read):** Upgrade-slot Part kits stay visible; catalog dress either fails OR uses wrong/tiny models (e.g. Airfield `12370174722` is a blockout). Fix = better ModelAssetIds + **scale mesh to TargetFootprint**, not host plinth size.

Reject: crate-sized props as buildings, neon slabs, blockout “Airport Model” as the airfield.

---

## LOOK — Scale law
Plot ≈ **80×80**. Structures must dominate a chunk of the plot.

| StructureId | Must read as | TargetFootprint (X×Z×Y studs) | Min height |
|-------------|--------------|-------------------------------|------------|
| CommandCenter | HQ compound / multi-bldg base | **36×28×16** | 14 |
| Barracks | long troop housing | **28×16×12** | 10 |
| VehicleDepot | large maintenance bay | **32×24×14** | 12 |
| WeaponsFacility | armory / 3-story facility | **28×18×18** | 16 |
| Warehouse | big logistics bay | **36×22×14** | 12 |
| Hangar | aircraft shed (Airfield accent) | **40×28×18** | 16 |
| Helipad | marked pad (+ small hut OK) | **22×22×3** pad | 1.5 |
| Airfield | **runway strip + hangar** | Runway **70×10×1** + Hangar footprint | hangar 16 |
| Watchtowers | tall tower | **10×10×32** | 28 |
| RadarStation / Radar | dish on plinth | **14×14×18** | 14 |
| ResearchLab | lab building | **22×16×12** | 10 |
| Dock | pier / containers along water | **40×16×8** | 6 |
| Bunker | hardened emplacement | **16×12×8** | 6 |
| PowerStation | plant / generators | **28×20×16** | 14 |
| DefensiveWalls | perimeter segments | segment **24×3×8** | 7 |
| MissileDefense | tower / battery | **12×12×22** | 18 |
| SpecialForcesFacility | elite barracks | **26×16×14** | 12 |

**Code Bot scale rule:** After `LoadAsset`, `model:ScaleTo(factor)` so `GetExtentsSize()` ≈ TargetFootprint (uniform scale from max-axis fit). **Never** set MeshPart.Size = hostPart.Size for buildings. Host plinth stays buy-collision only; hide Body kit Transparency ≥ 0.85 when mesh attaches.

---

## ASSETS — ModelAssetIds (free, IsForSale=false, type 10)

| StructureId | ModelAssetId | Catalog name | Verdict | Notes |
|-------------|-------------:|--------------|---------|-------|
| CommandCenter | **138331074285379** | Military Base | KEEP | Compound w/ fence — scale to 36×28 |
| Barracks | **18798977801** | Military Barracks | REPLACE was 9424782 | Prefer modern barracks over 2009 classic |
| BarracksAlt | 9424782 | Barracks | fallback | Classic |
| VehicleDepot | **6015472062** | Hangar | REPLACE was 12120702 | Large bay door hangar = depot silhouette |
| WeaponsFacility | **4120970784** | Military Barracks, 3 Story's | KEEP | Tall armory-like; scale height ≥16 |
| Warehouse | **6015472062** | Hangar | REPLACE was 66269964 | Same large bay family OR keep 66269964 only if scaled ≥36×22 — thumb of 66269964 was tiny-cube in situ |
| WarehouseAlt | 12120702 | Warehouse | fallback | Scale hard |
| Hangar | **6015472062** | Hangar | KEEP / primary | Best large free hangar found |
| HangarReject | 46981739 | Plane Hangar | **REJECT** | Tiny classic stud hangar |
| HangarReject2 | 30501822 | Air Plane Hanger | QA in Studio — likely weak |
| Helipad | **14313845338** | Airport | KEEP for pad markings | Plus Part circle H; scale pad 22×22 |
| Airfield | **COMPOSITE** | — | **REPLACE** 12370174722 | **REJECT** blockout airport. Build: Asphalt Decal runway `10197707775` on Part 70×10 + Hangar model `6015472062` |
| AirfieldReject | 12370174722 | ### - Airport Model | **REJECT** | Gray Part boxes + toy trees |
| Watchtowers | **108525417345747** | Sniper Tower Military Base Outpost | REPLACE primary | Taller military outpost; alt **3330023556** wood tower if insert fails |
| Radar / RadarStation | **9559610195** | Radar Dish W/Base | KEEP | Scale dish tall; not crate |
| ResearchLab | **17725725** | Research Lab | KEEP | Scale ≥22×16 |
| Dock | **17701461178** | Shipping Containers | KEEP as **dock dress** | Add Part pier under; don’t leave single container as whole Dock |
| Bunker | **16659447** | Destructible Movil Bunker | KEEP | Scale 16×12×8 |
| PowerStation | **14000967030** | Coal power plant | KEEP | Large industrial — scale 28×20 |
| SpecialForcesFacility | **18798977801** | Military Barracks | KEEP | Distinct from Barracks via camo accents |
| DefensiveWalls | 208197704 / L3 9703136850 | Military walls | KEEP | Segment scale |
| MissileDefense | **108525417345747** | Outpost tower | KEEP | |

### Wire snippet (VisualAssetConfig.Buildings)
```lua
Barracks = { ModelAssetId = 18798977801, Note = "Military Barracks — scale TargetFootprint" },
VehicleDepot = { ModelAssetId = 6015472062, Note = "Hangar bay as depot" },
Warehouse = { ModelAssetId = 6015472062, Note = "Large bay warehouse silhouette" },
Hangar = { ModelAssetId = 6015472062, Note = "Airfield hangar" },
Airfield = { ModelAssetId = 0, Note = "COMPOSITE: runway Part+Decal 10197707775 + Hangar 6015472062" },
Watchtowers = { ModelAssetId = 108525417345747, Note = "Military sniper/outpost tower" },
-- StructureVisualConfig.TargetFootprint = { Airfield = Vector3.new(70,1,10), ... }
```

---

## Billboards (still unreadable — reinforce UI_WORKER_P0)
Structure **name** boards (Warehouse / Airfield / …) are stacking with Season / Supply Drop / ATM / WORKER.

1. **Disable persistent structure name BillboardGuis** — rely on BUY price board only when looking at pad.  
2. Or single `WE_FocusLabel`: only the nearest structure within 20 studs shows name.  
3. Season banner: top center only; MaxDistance N/A (ScreenGui); never world-stacked on pads.  
4. Supply Drop / ATM: keep ATM priority from UI_WORKER_P0; Supply Drop MaxDistance 30, StudsOffset Y=8.

---

## NEXT — Code Bot
1. Add `TargetFootprint` + `ScaleTo` on building attach (critical).  
2. Swap Barracks / Depot / Warehouse / Watchtowers / Airfield composite IDs above.  
3. Reject Airfield 12370174722 + tiny Plane Hangar 46981739.  
4. Kill structure-name billboard spam.  
5. Republish; StudioForceDress to verify mesh sizes in-plot.

Design Bot: if Hangar `6015472062` fails insert, next candidates `12208876851` (QA) — still prefer ScaleTo over plinth squash.
