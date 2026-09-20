# Quality-gap wire — Design Bot → Code Bot
Source: RhGjQXJ8n6w gap notes + economy-verified free assets  
Priority order: car → soldiers → collector → map props  
Rule: realistic military only; reject blocky/SWAT/neon/cartoon/brand DisplayNames

## 1) Military car (drivability chassis = Code Bot)

| Slot | Asset name | Type | ID | Wire key | Notes |
|------|------------|------|-----|----------|-------|
| MilitaryJeep | Military Car Vehicle War Wheel Armored Model | Model | **125916936788670** | Vehicles.MilitaryJeep | KEEP — olive armored 4x4 + turret |
| ArmedJeep | Humvee Military Car Army Vehicle | Model | **122068883442022** | Vehicles.ArmedJeep | Tan turreted; catalog says Humvee — DisplayName stays Armed Jeep |
| Reject | Jeep (classic) | Model | 59524622 | JeepFallback | Blocky ROBLOX-logo toy |
| Reject | Military Light Truck… | Model | 107381977457431 | — | Wrong mesh (floodlight stand) |

## 2) R15 / realistic soldiers (TrainingYard / squad stalls)

| Slot | Asset name | ID | Wire key | Notes |
|------|------------|-----|----------|-------|
| Soldier | Realistic soldier StarterCharacter | **100212659702941** | Characters.Soldier | Spec-ops / gas-mask — already wired |
| Infantry | Layered clothing realistic soldier | **9104381136** | Characters.Infantry | Helmet + MOLLE — stall rifleman |
| Guard | Rigged Soldier | **16134469614** | Characters.Guard (+Fort/Bank/OilRig) | NVG balaclava |
| Heavy / swarm | Army of Soldiers (Rthro) | **14776506955** | Characters.HeavyInfantry | Pack for yard density |
| Pose | — | — | Anim | Crouch + rifle = **Animation**, not mesh. Apply crouch/aim on insert; meshes ship T/A-pose |
| Reject | Soldier Rthro official | 3924234975 | — | Plastic action-figure |
| Reject | Respawn Soldiers pack | 91299598767068 | — | Same plastic look |
| Reject | All SWAT/police NPC packs | 128233894407390 etc. | — | Toy/blocky |

## 3) Base realism — stalls / crates / lanterns / walls / collector

| Slot | Asset name | Type | ID | Wire key / structure |
|------|------------|------|-----|----------------------|
| MoneyCollector | Realistic ATM | Model | **75368157644109** | MoneyCollector — ATM face + digits billboard |
| MoneyCollector fallback | ATM | Model | 175462478 | MoneyCollectorFallback |
| SquadStall roof | Military Tent | Model | **6883609157** | Barracks / TrainingYard tarp stall (alt **3133150032**) |
| Wooden / metal crate | Crate/Box | Model | **53591587** | Stall prop stacks |
| Military crate | Military Crate | Model | **976333542** | Stall prop stacks |
| Lantern | Lantern | Model | **10121519149** | Stall light (StripScripts; soft: extracted from Verdun — mesh only) |
| Concrete walls | Grey Military Base Wall | Model | **208197704** | DefensiveWalls |
| Heavy walls | Heavy duty military wall | Model | **9703136850** | DefensiveWalls L3+ |
| Wall alt | Military Wall | Model | 6980242709 | Alt |
| Doors | — | — | Part cut / Union in wall kit | No free “wall+door” Model verified — Code Bot cut doorways in wall mesh or CSG |
| Sandbags | Realistic Sandbag | Model | 3525056989 | Stall / wall corners |

## 4) MapDressing — desert / road / arrows

| Slot | Asset name | Type | ID | MapDressing key | Notes |
|------|------------|------|-----|-----------------|-------|
| Desert flora + saguaro | Realistic Desert Plants | Model | **108556425657107** | MapDressing.DesertPlants | Includes saguaro, barrel cactus, shrubs |
| Cactus | Cactus | Model | 121029612 | MapDressing.Cactus | Accent |
| Cactus base | CactusBase2 | Model | 16354482789 | MapDressing.CactusBase | |
| Palms (prefer) | Palm Trees Realistic Tropical Island Beach Pack | Model | **96059329869678** | MapDressing.Palm | Horizon line |
| Palms (alt) | Low Poly Palm Tree… | Model | 105982075286356 | MapDressing.PalmAlt | Use only if realistic pack fails insert |
| Mesa / rocks | Low Poly Rocks Pack | **MeshPart** | **6562523344** | MapDressing.DesertRock | Type=40 MeshPart — insert via MeshPart pipeline not InsertService Model |
| Asphalt road | asphalt road texture | **Decal** | **10197707775** | MapDressing.AsphaltDecal | Paint on thin Part road strips (not a Model) |
| Floor chevron | — | Part kit | 0 | MapDressing.ChevronArrow | No free chevron Model found. **Code Bot:** Part wedges or Texture on asphalt Parts (white >>>>). Optional world arrow Models **1143305733** / **6333395014** for tutorial only — not floor paint |
| Oil spectacle | — | — | TBD | Near-base pump | No free derrick verified this pass — Part-kit pump or later curate |

## Rejects (explicit)
- Neon Part-kit cars / slab buildings as L1+ look  
- Flat ImageLabel billboards as world “props”  
- Blocky jeep 59524622, SWAT NPCs, plastic Rthro primary  
- 107381977457431 as vehicle  

## Ship order for Code Bot
1. Cars already OK — confirm live meshes on MilitaryJeep/ArmedJeep  
2. Soldiers already OK — add TrainingYard stall clones + crouch anim  
3. ATM face 75368157644109 + Collect circle  
4. Stall kit: Tent + Crate + MilitaryCrate + Lantern + Sandbags  
5. MapDressing: DesertPlants + Palm + Rocks MeshPart + Asphalt Decal strips + Part chevrons  
6. PreferMesh L1+ walls/HQ still on  

