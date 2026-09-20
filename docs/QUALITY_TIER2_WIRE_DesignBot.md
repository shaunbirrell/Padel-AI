# QUALITY TIER 2 WIRE — Design Bot → Code Bot
**Goal:** Unbelievable military tycoon quality (free Creator Store only)  
**Date:** 2026-09-20 · Reject neon/blocky/SWAT/brand DisplayNames  
**Builds on:** QUALITY_GAP_WIRE_DesignBot.md (cars/soldiers/ATM/map flora already shipping)

---

## LOOK — What “best” means this pass
1. **HQ interior** — desks/radios/ammo so CommandCenter isn’t a hollow mesh shell  
2. **Depot showroom density** — podium + rotator + extra display stands + floodlights  
3. **Oil spectacle** near plots — barrels + industrial props (+ pump if insert works)  
4. **Warzone landmarks** — radio tower, bunker, small fort on map (not only plot props)  
5. **UI icons** — Decals for cash/gold dock tiles (optional; Unicode still OK)

---

## ASSETS

### A) HQ interiors (`StructureDress.CommandCenter` / Barracks / ResearchLab)

| Key | Name | Type | ID | Notes |
|-----|------|------|-----|-------|
| RadioAntenna | radio antenna | Model | **19277831** | Already in WarzoneProps — clone inside HQ |
| RadioAntennaAlt | Radio Antenna | Model | **42209845** | Second unit on roof |
| AmmoBox | Ammo Box | Model | **16382915010** | Interior stacks |
| Crate | Crate/Box | Model | **53591587** | Desk-side stacks |
| MilitaryCrate | Military Crate | Model | **976333542** | |
| Lantern | Lantern | Model | **10121519149** | Interior light (strip scripts) |
| Floodlight | Floodlight | Model | **116763933** | Exterior HQ corners |
| FloodlightAlt | Floodlight | Model | **4893998573** | Depot bay |
| FloodlightTower | (mislabeled truck) | Model | **107381977457431** | Use as light tower only |
| FuelCans | Non-Laggy Fuel Cans and Oil Barrels | Model | **1160141839** | PowerStation / HQ stores |

**Missing (no free verified this pass):** dedicated command desk / map table / filing cabinet.  
**Fallback:** Part-kit gunmetal desk + SurfaceGui map texture — temporary until free desk Model found. Do **not** use flat ImageLabel as the whole prop.

### B) Vehicle depot showroom density

| Key | Name | Type | ID | Notes |
|-----|------|------|-----|-------|
| ShowroomPodium | Statue Podium | Model | **5267267960** | Primary display (already) |
| VehicleRotator | Rotating Platform | Model | **5389482912** | Under podium |
| ShowroomPedestal | sci-fi pedestal display stand | Model | **130578088310000** | 2nd/3rd locked ghost vehicle stands |
| Floodlight / FloodlightAlt | — | — | above | Bay lighting strips |
| FlagPole | Flag Pole | Model | **1679839739** | Depot entrance |
| FlagPoleHD | Highly Detailed Flag Pole | Model | **1454179642** | HQ / prestige |

Place **3 pedestals**: owned vehicle live mesh; locked = ghost clone Transparency 0.55.

### C) Oil spectacle (near-plot landmark)

| Key | Name | Type | ID | Notes |
|-----|------|------|-----|-------|
| IndustrialProps | Realistic Industrial Props Pack | Model | **103734805361054** | Primary oil/industrial kit — verify contents in Studio |
| RustyPipes | Realistic Rusty Pipes Pack | Model | **131322292868756** | Pipe runs to “derrick” |
| OilBarrel | Oil Barrel | Model | **25623924** | Cluster 6–12 at pad |
| FuelCans | — | Model | **1160141839** | |
| GasStation | Gas station | Model | **5149705639** | **Optional / heavy** (500k+ verts, scripts) — only if IndustrialProps lacks pump silhouette; StripScripts + scale down |
| Ultrapump | Ultrapump | Model | **1837698074** | Probe in Studio; drop if not oil-like |

**No dedicated free pumpjack found.** Compose spectacle: IndustrialProps + RustyPipes + OilBarrel ring + PointLight amber + slow rotate Part “walking beam” if needed.

### D) Warzone landmarks (map, not only plot)

| Key | Name | Type | ID | Placement |
|-----|------|------|-----|-----------|
| RadioTower | Radio Tower | Model | **119021509** | Map ridge / territory intel POI |
| BunkerLandmark | Destructible Movil Bunker | Model | **16659447** | Desert approach |
| SpyBunker | Spy Bunker | Model | **55228082** | Optional interior POI |
| SmallFort | Small Fort | Model | **67444725** | Mid-map landmark |
| EmergencyFort | M.N.S weapon emergency fort | Model | **35337352** | Alt fort — Studio QA (age/quality) |
| DesertPlants / Palm / Rocks | (tier-1 wire) | — | already | Keep densifying |

### E) UI button icons (optional Decals — AssetType 13)

| Slot | Name | Type | ID | Notes |
|------|------|------|-----|-------|
| IconGold | Gold coin | Decal | **8261389836** | Gold currency tile |
| IconGoldAlt | Gold Coin | Decal | **7893798103** | Alt |
| IconCash | — | — | programmatic `$` / Cash Color3 | Prefer no Robux-branded icons |
| Reject | Roblox Currency Icon / Robux Icon Gold | Decal | 10541283453 / 11560341841 | Wrong brand (Robux) |
| Reject | AK-47 decal | Decal | 13623664795 | Brand weapon name |
| IconShop / IconRifle / IconVehicle | — | — | Unicode 🪖🛒🚗 or experience-owned uploads | Safest for “best quality” brand safety |

---

## REJECT
- Neon Part kits as L1+ hero look  
- Blocky/SWAT/cartoon  
- Robux UI icons  
- AK-47 branded decals  
- GasStation unless IndustrialProps fails and Studio QA passes (too heavy)

---

## NEXT — Code Bot ship order
1. HQ interior dress (antenna, crates, ammo, lantern, fuel cans)  
2. Depot: rotator + 2 extra pedestals + floodlights + flag  
3. Near-plot oil pad: IndustrialProps + pipes + barrel ring (+ Ultrapump/GasStation only if needed)  
4. Map landmarks: RadioTower + SmallFort + Bunker  
5. Optional UI gold Decal on gold pill  
6. Ping Design on InsertService rejects  

