# MAP BUILD-OUT WIRE — Design Bot → Code Bot
**Date:** 2026-09-21 · Shaun: densify desert + warzone (Military Tycoon / War Tycoon feel)  
**Live:** v51 · Repo war-empire  
**Law:** Visual dressing only — no gameplay tags on filler. Mesh dress **ON** Part-kit clusters (MapDressing kits stay visible). Structures PreferMesh OFF unchanged. Neon = signals only.

Refs: `DESIGN_COMPETITIVE_DEEP_DIVE.md` §7 · `QUALITY_GAP_WIRE_DesignBot.md` §MapDressing · `MapDressing.luau`

Thumbs: `/workspace/war-empire-audit/thumbs/map/`

---

## LOOK — Goal
Empty sand between plots → **road rhythm + horizon silhouettes + warzone fill + chunky POI landmarks**. Capture flags/beacons stay cleanest; filler is darker/smaller.

### Material zoning
| Zone | Materials / colors | Notes |
|------|--------------------|-------|
| **Base / plot** | Concrete, Metal, Olive | Pads, walls, kits — existing COL palette |
| **Desert** | Sandstone, Wood, fabric tent | Adobe, flora, mesa |
| **Coastal** | Rust, Wood, Dock blue-gray | Pier, containers, pumpjack pipes |
| **Contested** | Sandbag, Ruin gray, ammo orange accents | Wrecks, ruined walls, HESCO |
| **Signals only** | NeonGold / NeonCyan | Flags, capture, beacons — not props |

---

## Priority
1. **P0** Empty horizon + road rhythm (asphalt, jersey, flora, mesa, palms)  
2. **P1** Warzone fill (wrecks, ruins, sandbags, crates, camo, fuel, lights)  
3. **P2** Coastal / fort landmarks (adobe, pier, ammo shed, fort, radio, bunker)

---

## P0 — Roads + horizon

| Slot | ModelAssetId / MeshId | Type | DisplayName | Source | Placement |
|------|----------------------:|------|-------------|--------|-----------|
| Asphalt road | Decal **10197707775** | Decal | Asphalt | KEEP | Thin Part strips between plots; width 12–16 studs |
| Floor chevrons | **0** Part-kit | Part | Chevrons | KEEP | White >>>> wedges on asphalt every ~40 studs at junctions |
| Jersey barrier | **82454061017921** | Model | Jersey Barrier | **NEW** | Line roads / plot exits; 1 every 18–24 studs (stagger yaw ±5°) |
| JerseyAlt | **17156953177** | Model | Jersey Barrier | NEW alt | Insert fallback |
| Concrete barrier pack | **15912051001** | Model | Road Barriers | NEW | Junction clusters (2–3) |
| HESCO | **9993540257** | Model | HESCO | NEW | Contested road shoulders (Full only) |
| Desert flora | **108556425657107** | Model | Desert Plants | KEEP | Clusters every 80–120 studs off-road |
| Cactus | **121029612** | Model | Cactus | KEEP | Accents in flora clusters |
| Palm horizon | **96059329869678** | Model | Palm | KEEP | Far ring: every 150–200 studs on map edge |
| PalmAlt | **105982075286356** | Model | Palm | KEEP | Insert fallback |
| Mesa rock | **12809476227** | Model | Desert Mesa | **NEW** | Horizon ridges — 6–10 on map rim (yaw toward center) |
| DesertRock | MeshId **6562523344** | MeshPart | Rocks | KEEP | Scatter near roads + mesa feet |

**Road rhythm rule:** Junction = 1 RoadSign kit + 1 LightPole/mesh light + 2 jersey + chevrons. Mid-segment = asphalt only + optional 1 flora cluster. Never wall-to-wall barriers.

```lua
-- VisualAssetConfig.MapDressing / WarzoneProps additions
JerseyBarrier = { ModelAssetId = 82454061017921, Note = "Concrete Jersey — road rhythm" },
JerseyBarrierAlt = { ModelAssetId = 17156953177, Note = "Jersey mesh alt" },
RoadBarriers = { ModelAssetId = 15912051001, Note = "Concrete Barriers pack" },
Hesco = { ModelAssetId = 9993540257, Note = "HESCO woodland — contested shoulder" },
DesertMesa = { ModelAssetId = 12809476227, Note = "Desert Mountain mesa horizon" },
```

---

## P1 — Warzone fill

| Slot | ModelAssetId | DisplayName | Source | Placement |
|------|-------------:|-------------|--------|-----------|
| Tank wreck | **9171585794** | Wrecked Tank | **NEW** | Mid-warzone + approach (1 per major road quadrant) |
| Ruined building | **8176692221** | Ruined Building | **NEW** | Contested mid-map — 3–5 total; keep 25 stud clear of capture flags |
| Ruined wall | **104053043839965** | Ruined Wall | NEW | Along ruined building + trench lines |
| Destroyed house | **84897059586684** | Ruined House | NEW soft | Alt ruin silhouette |
| Fuel tanks | **111066366655290** | Fuel Tanks | **NEW** | Fuel depot kits + roadside (DisplayName Fuel Tanks; ignore catalog language) |
| Ammo shed | **2652344972** | Ammo Shed | **NEW** | Dress `kitAmmoShed` hosts |
| Vehicle shed | **82560800252069** | Supply Shed | NEW | Far depot accents |
| Camo net | **13668977092** | Camo Net | **NEW** | Over crate stacks / vehicle DISPLAY silhouettes |
| Ghillie net | **13437018139** | Camo Net Alt | NEW | Insert fallback |
| Portable light | **9701862157** | Light Tower | **NEW** | Outposts + night approach (emit PointLight on Full) |
| Street lamp | **123546710527428** | Street Lamp | NEW | Road furniture alt to Part-kit light pole |
| StreetLampAlt | **8180880144** | Street Lamp | NEW | Fallback |
| Sandbag | **3525056989** | Sandbag | KEEP | Lines + plot ring |
| SandbagBarrier / Wall | 12651656400 / 25733125 | — | KEEP | |
| ConcreteBarrier | **91071319** | Barrier | KEEP | Mix with Jersey |
| Crate / MilitaryCrate / AmmoBox | 53591587 / 976333542 / 16382915010 | — | KEEP | Stacks of 2–4 |
| OilBarrel / FuelCans | 25623924 / 1160141839 | — | KEEP | Fuel + wreck sites |
| Tent / TentAlt | 6883609157 / 3133150032 | — | KEEP | Camps |
| BarbedWire | **1291725699** | Wire | KEEP | Fence lines |
| FloodlightTower | **107381977457431** | Floodlight | KEEP | Depots |
| Military Crates pack | **16540055496** | Crate Pack | NEW | Dense crate variety |
| Ammo tent | **69308813** | Ammo Tent | NEW | Camp accent |

**Fill density (MapDressing.Dress):**
| Quality | Mid-warzone clusters | Plot-ring props | Wreck sites |
|---------|---------------------:|----------------:|------------:|
| **Low** | ~40% of Full | 8 / plot | 2 total |
| **Full** | prior dense + mesh overlays | 10–12 / plot | 4 total |

Keep **20–30 stud** clear approach around flags, collectors, garage exits, vehicle spawn pads.

```lua
TankWreck = { ModelAssetId = 9171585794, Note = "Destroyed tank warzone fill" },
RuinedBuilding = { ModelAssetId = 8176692221, Note = "Destroyed Building landmark fill" },
RuinedWall = { ModelAssetId = 104053043839965, Note = "Mossy ruined wall" },
FuelTanks = { ModelAssetId = 111066366655290, Note = "Fuel Tanks — DisplayName Fuel Tanks" },
AmmoShed = { ModelAssetId = 2652344972, Note = "Military ammo/supplies shed" },
SupplyShed = { ModelAssetId = 82560800252069, Note = "Vehicle/supply shed" },
CamoNet = { ModelAssetId = 13668977092, Note = "Camouflage Netting — FIX legacy CamoNet alias" },
CamoNetAlt = { ModelAssetId = 13437018139, Note = "Ghillie Net" },
PortableLightTower = { ModelAssetId = 9701862157, Note = "Military portable light tower" },
StreetLamp = { ModelAssetId = 123546710527428, Note = "StreetLamp_A road furniture" },
```

**Fix:** `WarzoneProps.CamoNet` currently aliases AmmoBox `16382915010` — retarget to **13668977092**.

---

## P2 — Landmarks / coastal / fort

| Slot | ModelAssetId | DisplayName | Source | Placement |
|------|-------------:|-------------|--------|-----------|
| Adobe house | **9136197032** | Desert House | **NEW** | Dress `kitAdobeBuilding` / outpost adobe |
| Boat pier | **11138299907** | Pier | **NEW** | Coastal accents (Low: 2, Full: 4–5) |
| PierAlt | **125493544802645** | Pier Ramp | NEW | Curved ramp pier |
| Dock kit | **3023220773** | Dock | NEW | Coastal cluster |
| WW2 bridge/checkpoint | **867696371** | Checkpoint Bridge | NEW | Mid-road landmark (1–2) |
| RadioTower | **119021509** | Radio Tower | KEEP | Ridge POIs |
| Bunker | **16659447** | Bunker | KEEP | Approaches |
| SpyBunker | **55228082** | Spy Bunker | KEEP | Optional |
| SmallFort | **67444725** | Small Fort | KEEP | Mid-map fort silhouette |
| OilPumpjack | **13525922265** | Oil Pumpjack | KEEP | Coastal oil approach |
| OilPumpjackAlt | **15192621369** | — | KEEP | |
| IndustrialPack / RustyPipes | 103734805361054 / 131322292868756 | — | KEEP | Oil spectacle |
| Flag / FlagPoleHD | 1679839739 / 1454179642 | Flag | KEEP | Capture — tallest, cleanest |

**POI composition (per capture/outpost):**
1. Hero silhouette (fort / adobe / bunker / pumpjack) facing approach yaw  
2. One approach marker (flag or light tower)  
3. Filler darker/smaller outside 25-stud flag radius  

```lua
DesertHouse = { ModelAssetId = 9136197032, Note = "Adobe desert house" },
Pier = { ModelAssetId = 11138299907, Note = "Boat Dock pier accent" },
PierAlt = { ModelAssetId = 125493544802645, Note = "Wooden Pier curved ramp" },
CheckpointBridge = { ModelAssetId = 867696371, Note = "WW2 bridge checkpoint landmark" },
```

---

## MapDressing.luau wiring notes (Code Bot)

1. After Part-kit builders (`kitFuelDepot`, `kitAmmoShed`, `kitCheckpoint`, …), optionally `TryAttach` mesh overlays from keys above (StripScripts).  
2. **P0 ship first:** asphalt Decal strips + Jersey + DesertMesa + existing Palm/DesertPlants/Rocks.  
3. **P1:** TankWreck + RuinedBuilding + FuelTanks + CamoNet fix + PortableLightTower.  
4. **P2:** DesertHouse + Pier + CheckpointBridge.  
5. Tag all dressing `WE_MapDress` only — no buy/capture tags.  
6. Decorative vehicles: muted `DISPLAY` plate; never look spawnable.  
7. Low quality: drop HESCO, half wrecks, half pier, skip PointLights on portable towers.

### Suggested cluster coords (extend existing Dress lists)
Reuse current checkpoint/outpost positions in `MapDressing.Dress`. Add:
- Mesa rim: `(±2200, 2, ±1800)`, `(0, 4, ±2400)` approx — snap to terrain  
- Wreck sites: `(-350,0.5,-450)` already · add `(400,0.5,500)`, `(-800,0.5,300)`, `(900,0.5,-700)` Full  
- Fuel spectacle: near oil Alpha/Bravo approach — pumpjack + FuelTanks + RustyPipes  

---

## Performance
| Tier | Rule |
|------|------|
| Low | ~60–70% fewer clusters (existing); mesh overlays only on hero kits + P0 road/horizon |
| Full | All P0–P2; CastShadow false on filler Parts; PointLight only on PortableLightTower + Floodlight |
| Mobile | Prefer MeshPart rocks + few Models; no vignette/map packs |

---

## REJECT
| Id / pattern | Why |
|--------------|-----|
| Fallout / zombies / vignette packs | Off-theme clutter |
| Nation-flag fuel tank marketing spam as DisplayName | Use DisplayName **Fuel Tanks** only |
| Skybox “mesa” results | Not Models |
| CamoNet → AmmoBox alias | Wrong — fix to real net |
| Neon props | Signals only |
| Ultrapump `1837698074` | Prior REJECT |
| Filling 20 stud capture clear zone | Hides beacons |

---

## P0 ID list (ship first)
```
AsphaltDecal MeshId 10197707775
JerseyBarrier 82454061017921 (alt 17156953177)
DesertMesa 12809476227
DesertPlants 108556425657107
Palm 96059329869678
DesertRock MeshId 6562523344
+ Part-kit chevrons + existing RoadSign/LightPole kits
```

## NEXT
1. Code Bot: MapDressing P0 asphalt + jersey + mesa + flora densify → live.  
2. Then P1 wreck/ruin/fuel/camo/light.  
3. Ping Design Bot on InsertService rejects (alts listed).
