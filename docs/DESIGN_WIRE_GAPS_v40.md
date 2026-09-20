# DESIGN WIRE GAPS — v40 inventory
**Date:** 2026-09-20 · Code Bot (for Design Bot fill)  
**Source:** `VisualAssetConfig.luau`, `StructureVisualConfig.luau`, `SoldierConfig.luau`  
**Live baseline:** v39 (3a515a8). Do **not** invent paid / MT-branded IDs. Part kits remain fallback.

---

## 1. ModelAssetId = 0 (needs Design Bot fill or confirmed Part-kit-only)

| Area | Key | Status | Note |
|------|-----|--------|------|
| Buildings | `Airfield` | **0** | COMPOSITE runway + Hangar `6015472062`; REJECT `12370174722` |
| Buildings | `BaseCeiling` | **0** | Part-kit translucent roof — no free dedicated roof Model (OK if intentional) |
| StructureVisual | `Airfield.MeshAssetId` | **0** | Matches Buildings.Airfield |
| Characters | `CharacterAlt` | **0** | DISABLED — Design rejected plastic Rthro alts (keep 0) |
| SoldierConfig | `Visual.ModelAssetIdOverride` | **0** | Intentional — use `VisualAssetConfig.Characters` |
| DesertProps | `DesertRock` | Model **0**, MeshId `6562523344` | MeshPart pipeline (OK) |
| MapDressing | `AsphaltDecal` | Model **0**, MeshId `10197707775` | Decal Texture (OK) |
| MapDressing | `ChevronArrow` | **0** | Part-kit floor chevrons (OK) |

**No vehicle keys are currently `ModelAssetId=0`.** Gaps are reuse density, not missing IDs.

---

## 2. Vehicles — heavy ID reuse (prefer distinct free Models)

| Shared ModelAssetId | Keys using it | Priority |
|--------------------:|---------------|----------|
| `26007709` | LightTank, MediumTank, CombatIFV, AssaultIFV, BridgeLayer, MineClearer, FlameCarrier, SPAAG, MobileSAM, MortarCarrier, MobileArtillery, RocketArtillery, HowitzerTruck, SiegeMortar, LightScoutTank | **P0** split tank / IFV / arty / SPAAG |
| `13195201090` | LandingCraft + all capital/landing/hospital/supply + Cruiser/MissileCruiser/FleetCarrier | **P0** capital ships vs landing craft |
| `28912351` | `_FallbackWheeled` + FuelTanker, EngineeringTruck, FlatbedHauler, AmmoCarrier, MissileTruck, AntiAirTruck, RadarTruck, CargoVan, TroopTransport, RecoveryTruck, EscortTruck | **P1** specialty trucks |
| `15786579439` | PatrolBoat family + subs (surface stub) | **P1** gunboat vs sub silhouette |
| `19297043` | BattleTank, HeavyTank, SuperHeavyTank, TankDestroyer, AssaultGun, FortressTank, RailgunCarrier | **P1** MBT tiers |
| `4865838` | FighterJet, InterceptorJet, TrainerJet, ReconPlane, LightFighter (+ fallback) | **P1** trainer/recon distinct |
| `3319732457` | StrikeBomber, CargoPlane, AWACSPlane, TankerPlane, HeavyBomber, StrategicBomber | **P1** AWACS/tanker/bomber |
| `125916936788670` | MilitaryJeep, UtilityQuad, ScoutCar, ReconBuggy, DispatchCar | **P2** (Jeep WE_GroundDrive untouched) |
| `295607934` | AttackHelicopter, NightAttackHeli, GunshipHeli, StealthHeli, EscortHeli | **P2** |
| `5935419` | LightTransportHeli, LightScoutHeli, RescueHeli, UtilityHeli, MedevacHeli | **P2** |
| `17835143223` | APC, InfantryCarrier, CommandVehicle, WheeledIFV, AmphibiousAPC | **P2** |
| `5507592781` | StrikeJet, CASJet, StealthStrikeJet, StealthStrike | **P2** |
| `9753309` | TransportHeli, HeavyLiftHeli, VTOLTransport | **P2** |
| `105503568352704` | PatrolTruck, ArmoredTruck, SupplyTruck | **P2** |

**Unique / OK:** ArmedJeep `122068883442022` (keep). APC prefer IDs already set.

---

## 3. Structures / Buildings — reuse

| Shared ID | VisualAssetConfig.Buildings | StructureVisualConfig.MeshAssetId | Ask |
|----------:|-----------------------------|-----------------------------------|-----|
| `6015472062` | VehicleDepot, Warehouse, Hangar | VehicleDepot, Warehouse | Distinct hangar / warehouse / depot |
| `18798977801` | Barracks, SpecialForcesFacility | Barracks, SpecialForcesFacility | Distinct SF facility |
| `108525417345747` | Watchtowers, MissileDefense | Watchtowers, MissileDefense | Distinct missile battery |

**Filled OK:** CommandCenter, WeaponsFacility, Helipad, Dock, DefensiveWalls (+ L3), Radar, ResearchLab, PowerStation, Bunker, Hangar primary.

---

## 4. Soldiers / Characters

| Key | ModelAssetId | Gap |
|-----|-------------:|-----|
| Soldier | `100212659702941` | OK |
| Infantry | `9104381136` | OK |
| Worker | `100212659702941` | **Same as Soldier** — Design wanted distinct vs Infantry; consider Infantry/`9104381136` or new worker mesh |
| WorkerFallback | `16134469614` | OK fallback |
| HeavyInfantry | `14776506955` | OK |
| Guard / BankGuard / OilRigGuard / FortGuard / GateGuard | `16134469614` | **All identical** — optional variety (NVG vs balaclava packs) |
| CharacterAlt | `0` | Keep disabled |
| SoldierConfig `AccessoryIds` | `{}` | TODO Design Bot accessories |
| SoldierConfig roles | — | No GateGuard in `VisualKindByRole` (Gate uses VisualAssetConfig.GateDefense.Guard) |

---

## 5. Design Bot fill order (suggested)

1. **P0 vehicles:** tank/IFV/arty split from `26007709`; capital naval ≠ `13195201090` landing template.  
2. **P0 structures:** Hangar ≠ Warehouse ≠ Depot; MissileDefense ≠ Watchtower.  
3. **P1:** Worker distinct from Soldier; Guard family 1–2 alts; jet/heli/truck specialty IDs.  
4. Confirm Airfield composite + BaseCeiling stay `0` (Part-kit) **or** supply free Models.

**Constraints for Code Bot (do not regress):** hideKitBody no-op; no StructureKitBuilder densify; no KIT_GEN change; no Body bury-scale; no billboard enlarge; no Wall* perimeter mesh dress; Jeep `WE_GroundDrive` + monetization IDs untouched.

---

## 6. Out of scope this doc
GateDefense / WarzoneProps / IndustrialProps / Landmarks / ATM — already have non-zero IDs (audit separately if inserts fail in Studio).
