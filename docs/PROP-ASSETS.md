# PROP-ASSETS: the Creator Store picks (Code Bot STORE-PROPS, WE_Build 132)

Owner picks from `/workspace/props/PICKS.md` (80 ids, all added to shaunie6's inventory, the place owner).
**Store props live in `src/ReplicatedStorage/Shared/Configs/StorePropsConfig.luau` and are placed by
`src/ServerScriptService/Server/Services/StorePropsService.luau`. Do not remove them** (CLAUDE.md).
To change what goes where, edit the `WorldRows` / `ZoneRows` rows there (and this file); never delete the tables.

## Load check (Open Cloud Luau on place 97112936860418, 2026-09-30 about 11:40 Dublin time)
- **80 / 80 load** with `InsertService:LoadAsset` on the live place. **None failed, none "not authorized"**, so the
  owner does not need to "Get" any of them again.
- Parts = BaseParts in the asset as loaded; Size = the world-aligned box of its visible parts (studs, X x Y x Z,
  scale 1) as the creator built it.
- **62 of 80 ids are wired** (57 in the world, 25 in the rebirth zones, some in both). 18 are not placed
  (the reason is in the row): 3 rejected (a real-tank replica, a franchise-named car, a Tool that is not a model),
  4 checkpoint pieces left alone for JOB 37 (its spec is our own Part design, no store models), and the rest over the
  part / decal budget or worse than the Part build (the plain barracks block).
- Live-world test (the real v131 map rebuilt in an Open Cloud session running this code): **213 world copies placed,
  7,978 parts (cap 9,000), 0 floating** (a ray under every copy hits ground at its pivot); 7 of the 12 roof copies
  found no free flush roof and were skipped, never forced. All 7 rebirth zones x 3 levels swapped cleanly: every store
  model's lowest visible part sits on the yard top (within 0.15 studs), no overlaps, the console lane stays clear.

## Where things go
- **World** (`WorldRows`): the JOB 31 sites (`site:<Id>`, WorldSitesConfig: Camp Viper, Dry Well, Pump Station 7,
  Kestrel Depot, Overwatch Ridge, Anvil Scrapyard, Dust Camp) and the named areas (`area:<Id>`, WorldConfig.POIs via
  MapAreas: Crossroads Town, Ruined Village, Oil Field, West Depot, East Armory, Airstrip, Radar Hill, North Ridge,
  South Port, Crash Site, the camps, Oasis, both forts, both rig shore bases). Hawk Checkpoint is left alone (JOB 37).
  A copy only lands on open level ground or pavement, never on a road (8-stud margin), never touching another part
  (2-stud margin), and at least 330 studs from every base plot centre (the plot and its rebirth annexes). A "roof"
  row sits on a town building whose visible roof is flush with its collider. An area row that finds no room inside
  may use a 90-stud band just outside the area.
- **Rebirth zones** (`ZoneRows`, JOB 33): at level 1-3 the Part complex of the zone is swapped for the store models
  (the yard and the console stay). The Elite Barracks keeps its Part barracks and gets store dressing only.
- **Budgets**: world 9,000 parts; one plot's zones 7,200; all zones on a server 16,000; one model 2,300.
  Tiny detail (< 0.2 studs) is dropped, no shadows under 8 studs, no collision under 1.2 studs, at most 2 shadowless
  lights per model. Copies are `WE_Cluster "store:<kind>"` models, so the client QualityGovernor culls small far props
  with its load / unload hysteresis and never culls a building-sized one (no pop-in on buildings).
- **Flags**: `Enabled` (kill switch), `OwnerFirst = true` (world props are placed once the owner is in the server; zone
  visuals on his plot only), `World`, `ZonesOn`; live kill: `Workspace:SetAttribute("WE_StorePropsOff", true)`.
- The CLAUDE.md store-model rules (<= 40 parts, <= 20k tris, WE_CHECK2 origin check) are **not** applied to this set:
  the owner asked for these picks to be wired, and the budgets above replace the per-model part cap. The origin
  (mesh uploader) check was not run.

## Every id

| Asset ID | Name | Category | Creator | Loads | Parts | Size (studs) | Use | Where |
|---|---|---|---|---|---|---|---|---|
| 9171585794 | destroyed tank | Tank wreck | lobo73_audas | yes | 12 | 20.3 x 13.9 x 26.3 | world | World: site:Anvil x2 @0.8; area:Crash x1 @0.8 (placed 3 in the live-world test) |
| 9014990866 | Destroyed Tank | Tank wreck | ElPelochorizo1 | yes | 2 | 45.0 x 23.9 x 21.8 | world | World: site:Anvil x1 @0.5; area:FortI x1 @0.5 (placed 2 in the live-world test) |
| 2473378608 | Destroyed tank | Tank wreck | IncursionFade | yes | 263 | 25.2 x 11.5 x 23.1 | rejected | not placed: the model inside is named "m4 sherman": a real-tank replica (CLAUDE.md: no real-world copies) |
| 14269073207 | destroyed tank mesh | Vehicle wreck (APC) | Oddsans33123 | yes | 16 | 22.9 x 22.1 x 34.2 | world | World: site:Anvil x2 @0.6; area:Crash x1 @0.6 (placed 3 in the live-world test) |
| 8453210953 | Destroyed)tanker truck (mesh) | Vehicle wreck (truck) | 908KS_RKO | yes | 2 | 59.7 x 12.2 x 21.0 | world | World: site:PumpSeven x1 @0.6; area:OilField x1 @0.6 (placed 2 in the live-world test) |
| 1650602509 | Destroyed Truck | Vehicle wreck (truck) | EpicCrossingSwords | yes | 2 | 13.8 x 9.3 x 41.4 | world | World: site:Kestrel x1 @0.8; site:Anvil x1 @0.8; area:Depot x1 @0.8; area:Crash x1 @0.8 (placed 4 in the live-world test) |
| 13989569039 | Destroyed Gaz Jeep Mesh | Vehicle wreck (jeep) | cjng0909R | yes | 6 | 12.2 x 10.8 x 23.7 | world | World: site:CampViper x1 @0.65; site:Anvil x1 @0.65 (placed 2 in the live-world test) |
| 4128315411 | Wrecked White Car (Mesh) | Vehicle wreck (car) | bearduckmonkey | yes | 2 | 6.6 x 5.2 x 14.1 | world | World: site:DryWell x1 @1.0; area:Town x2 @1.0; area:Ruins x2 @1.0 (placed 5 in the live-world test) |
| 3117530492 | Rusty Car 4 (Mesh) | Vehicle wreck (car) | bearduckmonkey | yes | 1 | 6.8 x 4.1 x 15.2 | rejected | not placed: the mesh is named "Volga (Metro 2033)": a real car + franchise rip |
| 5678434293 | Sandbag Barrier | Barriers | vx0rn | yes | 1 | 19.4 x 4.7 x 3.4 | both | World: site:CampViper x3 @1.0 (placed 3 in the live-world test) <br> Rebirth: Artillery Battery (WestStrip) L1,2,3; Bunker Complex (WestFlank) L1,2,3 |
| 5678429543 | Sandbags Corner | Barriers | vx0rn | yes | 1 | 13.2 x 4.2 x 14.8 | world | World: site:Overwatch x2 @1.0; area:FortS x2 @1.0 (placed 4 in the live-world test) |
| 11654379868 | Tank Trap | Barriers | TNMOXA8262 | yes | 1 | 7.7 x 5.9 x 7.6 | both | World: site:Anvil x6 @1.0; area:FortI x6 @1.0; area:FortS x6 @1.0 (placed 18 in the live-world test) <br> Rebirth: Bunker Complex (WestFlank) L1,2,3 |
| 1230286742 | Spiral Barbed Wire | Barriers | bigcrazycarboy | yes | 4 | 11.9 x 4.1 x 4.1 | both | World: site:Overwatch x4 @1.0; area:FortI x3 @1.0 (placed 7 in the live-world test) <br> Rebirth: Bunker Complex (WestFlank) L3 |
| 9154880131 | Hesco Barrier | Barriers | Niceforme124 | yes | 1 | 7.0 x 7.0 x 7.0 | both | World: site:Kestrel x4 @1.0; site:DustCamp x4 @1.0; area:Armory x4 @1.0 (placed 12 in the live-world test) <br> Rebirth: Artillery Battery (WestStrip) L3; Elite Barracks (EastYard) L3; Bunker Complex (WestFlank) L2,3 |
| 4128301030 | textured mesh road barrier | Barriers | bearduckmonkey | yes | 1 | 2.5 x 3.0 x 7.2 | world | World: site:Kestrel x4 @1.0; area:Depot x4 @1.0; area:Port x4 @1.0 (placed 12 in the live-world test) |
| 2190705941 | Military Crates & Ammo Resupply | Crates/supply | mrlengthly | yes | 26 | 6.3 x 4.5 x 12.7 | both | World: site:CampViper x2 @1.0; site:Kestrel x3 @1.0; area:Depot x2 @1.0; area:DuneCamp x2 @1.0 (placed 9 in the live-world test) <br> Rebirth: Artillery Battery (WestStrip) L2,3; Drone Hangar (DroneBay) L3; Elite Barracks (EastYard) L2,3 |
| 2930926216 | Military Crates | Crates/supply | XIArchangel | yes | 64 | 9.2 x 6.7 x 9.2 | world | World: site:Kestrel x2 @1.0; area:Depot x2 @1.0 (placed 4 in the live-world test) |
| 16540055496 | Military Crates | Crates/supply | Antonov_Slonovskaya | yes | 5 | 7.4 x 4.2 x 6.2 | both | World: site:Kestrel x3 @1.0; site:DustCamp x2 @1.0 (placed 5 in the live-world test) <br> Rebirth: Tank Factory (WestYard) L2,3; Drone Hangar (DroneBay) L3; Elite Barracks (EastYard) L2,3 |
| 9021582812 | PBR Oil Barrel | Crates/supply | Wabbiits | yes | 1 | 1.8 x 2.8 x 1.8 | both | World: site:CampViper x4 @1.0; site:PumpSeven x6 @1.0; area:OilField x8 @1.0; area:RigA x4 @1.0; area:RigB x4 @1.0 (placed 26 in the live-world test) <br> Rebirth: Oil Refinery (EastStrip) L1,2,3 |
| 9352751052 | Watchtower | Watchtower | Flooksies | yes | 148 | 16.0 x 37.2 x 16.0 | both | World: site:CampViper x1 @0.85; area:Quarry x1 @0.8 (placed 2 in the live-world test) <br> Rebirth: Artillery Battery (WestStrip) L3 |
| 3392535391 | Watchtower | Watchtower | oxrock | yes | 291 | 32.0 x 50.6 x 40.2 | world | World: site:Overwatch x1 @0.7 (placed 1 in the live-world test) |
| 1974692711 | WatchTower | Watchtower | urtotallyright | yes | 216 | 35.0 x 69.0 x 37.0 | world | World: area:RidgeCamp x1 @0.5 (placed 1 in the live-world test) |
| 12273282787 | Bunker ww2 | Bunker/pillbox | procheetah200 | yes | 110 | 29.0 x 9.5 x 21.8 | both | World: site:Overwatch x1 @1.0 (placed 1 in the live-world test) <br> Rebirth: Nuclear Silo (StrategicYard) L1,2; Artillery Battery (WestStrip) L1,2,3; Bunker Complex (WestFlank) L1,2,3 |
| 15797919882 | Ww1 Bunker | Bunker/pillbox | jaytlam2019abc | yes | 108 | 28.9 x 9.4 x 28.3 | both | World: site:Overwatch x1 @0.8; area:FortS x1 @0.8 (placed 2 in the live-world test) <br> Rebirth: Bunker Complex (WestFlank) L3 |
| 182529039 | Military Canvas Tent | Tents | Quenty | yes | 336 | 42.5 x 18.7 x 68.0 | unused | not placed: 336 parts: the 6-part Modern Military Tent is used instead |
| 11558767918 | Modern Military Tent | Tents | APETTR2 | yes | 6 | 48.6 x 13.2 x 29.1 | both | World: site:CampViper x1 @0.55; site:DustCamp x1 @0.5; area:RidgeCamp x1 @0.5; area:DuneCamp x1 @0.5; area:Oasis x1 @0.55 (placed 5 in the live-world test) <br> Rebirth: Elite Barracks (EastYard) L2,3 |
| 10485439002 | RGG millitary tent | Tents | Y4mist | yes | 8 | 33.8 x 12.5 x 45.0 | world | World: site:CampViper x1 @0.5; area:Quarry x1 @0.5 (placed 2 in the live-world test) |
| 8220562195 | Military medical tent | Tents | LoganPlayz907 | yes | 212 | 34.5 x 10.0 x 27.0 | world | World: site:DustCamp x1 @0.8 (placed 1 in the live-world test) |
| 11989298499 | Military Gate or Border Gate | Checkpoint/gate | RealTrey_YT | yes | 1067 | 106.3 x 20.2 x 75.3 | unused | not placed: JOB 37 builds the road checkpoint from our own Parts by spec (no store models); kept for later |
| 12125769119 | Military Boarder or Gate | Checkpoint/gate | RealTrey_YT | yes | 697 | 83.6 x 20.2 x 61.0 | unused | not placed: JOB 37 builds the road checkpoint from our own Parts by spec (no store models); kept for later |
| 9404286622 | Military Checkpoint | Checkpoint/gate | R00So_o | yes | 84 | 8.2 x 8.7 x 41.9 | unused | not placed: JOB 37 builds the road checkpoint from our own Parts by spec (no store models); kept for later |
| 8279648205 | Boom gate | Checkpoint/gate | mortixPL | yes | 13 | 12.1 x 8.6 x 2.0 | unused | not placed: JOB 37 builds the road checkpoint from our own Parts by spec (no store models); kept for later |
| 447143432 | Ruined Apartment Building | Ruined village | TevRCC | yes | 826 | 35.6 x 54.2 x 58.0 | world | World: area:Ruins x1 @0.8 (placed 1 in the live-world test) |
| 161539117 | Desert House 2 | Ruined village | SgtHamy | yes | 101 | 30.2 x 12.2 x 29.2 | world | World: site:DryWell x1 @1.0; area:Ruins x1 @1.0 (placed 2 in the live-world test) |
| 16988151510 | Ruined Building | Ruined village | jstedebilove | yes | 61 | 631.4 x 270.9 x 372.0 | world | World: site:DryWell x1 @0.1; area:Ruins x1 @0.1 (placed 2 in the live-world test) |
| 539121004 | Destroyed house | Ruined village | ImFarAway | yes | 327 | 24.2 x 11.8 x 22.9 | world | World: area:Ruins x1 @1.0 (placed 1 in the live-world test) |
| 13525922265 | Realistic Oil Pumpjack | Oil field | Unit5532 | yes | 172 | 52.0 x 41.3 x 18.0 | world | World: site:PumpSeven x1 @0.55 (placed 1 in the live-world test) |
| 395208145 | Oil Pump (Pumpjack) | Oil field | Dummiez | yes | 241 | 52.0 x 41.3 x 18.0 | world | World: area:OilField x1 @0.6 (placed 1 in the live-world test) |
| 15569446609 | Storage Tank | Oil field | Antonov_Slonovskaya | yes | 1 | 30.5 x 47.7 x 33.9 | both | World: site:PumpSeven x1 @0.4; area:OilField x3 @0.4; area:RigA x1 @0.4; area:RigB x1 @0.4 (placed 6 in the live-world test) <br> Rebirth: Oil Refinery (EastStrip) L1,2,3 |
| 15753397958 | Fuel Tank | Oil field | Antonov_Slonovskaya | yes | 4 | 6.0 x 7.1 x 12.9 | both | World: site:PumpSeven x2 @1.0; area:OilField x2 @1.0; area:Depot x1 @1.0 (placed 5 in the live-world test) <br> Rebirth: Tank Factory (WestYard) L2,3; Nuclear Silo (StrategicYard) L2,3; Oil Refinery (EastStrip) L1,2,3 |
| 9370327334 | industrial pipes w/ valve | Oil field | amb6ent | yes | 201 | 8.2 x 12.3 x 5.2 | unused | not placed: 201 parts for an 8-stud pipe cluster: poor detail per part |
| 12423243620 | Office Building | City building (enterable) | iLegend66 | yes | 1066 | 57.7 x 64.8 x 94.5 | world | World: area:Town x1 @1.0 (placed 1 in the live-world test) |
| 5201630514 | [NO SCRIPTS] Hospital Building | City building (enterable) | TheWingedGuest | yes | 406 | 68.5 x 54.4 x 48.7 | world | World: area:Town x1 @0.9 (placed 1 in the live-world test) |
| 18521807804 | Building w/ Interior | City building (enterable) | Ebigdog1 | yes | 64 | 89.0 x 26.8 x 52.1 | world | World: site:DryWell x1 @0.6 (placed 1 in the live-world test) |
| 16365964601 | Desert house | City building (enterable) | RussianAndRobloxer | yes | 317 | 52.4 x 17.0 x 26.7 | world | World: site:DryWell x1 @1.0 (placed 1 in the live-world test) |
| 14243660153 | New York City Corner Apartment Building | City building (shell) | Lihtsameelseke | yes | 2568 | 51.8 x 66.4 x 51.8 | unused | not placed: 2568 unanchored parts: over Budget.MaxPartsPerModel |
| 227190265 | BEPC Air Conditioner Unit | Rooftop props | BackupSilly10 | yes | 36 | 6.8 x 7.2 x 11.6 | world | World: area:Town x4 (roof) @1.0 (placed 1 in the live-world test) |
| 4112608919 | Water Tower 1 (Mesh) | Rooftop props | bearduckmonkey | yes | 1 | 24.8 x 101.5 x 24.9 | world | World: site:DryWell x1 @0.3; area:Town x2 (roof) @0.2 (placed 3 in the live-world test) |
| 5193302623 | Rooftop Prop 1 | Rooftop props | olhuk | yes | 18 | 6.0 x 1.7 x 6.0 | world | World: area:Town x4 (roof) @1.0 (placed 2 in the live-world test) |
| 262712273 | Satellite Dish | Rooftop props | Balefulness | yes | 63 | 49.6 x 64.0 x 51.8 | both | World: area:Town x2 (roof) @0.12; area:Radar x1 @0.6; area:Signal x1 @0.45 (placed 2 in the live-world test) <br> Rebirth: Nuclear Silo (StrategicYard) L2,3; Drone Hangar (DroneBay) L2,3 |
| 11146095708 | Street Lamp | Street props | BryanROBLOXgamer10 | yes | 4 | 12.0 x 22.0 x 2.0 | world | World: area:Town x8 @1.0; area:Port x3 @1.0 (placed 11 in the live-world test) |
| 96257169 | Trash Dumpster | Street props | TofuBytes | yes | 1 | 6.0 x 6.9 x 9.0 | world | World: site:DryWell x1 @1.0; area:Town x4 @1.0 (placed 5 in the live-world test) |
| 574054179 | 4 Wire Power Pole | Street props | JacobSMT | yes | 39 | 8.0 x 42.0 x 2.0 | world | World: site:Kestrel x1 @1.0; area:Signal x2 @1.0 (placed 3 in the live-world test) |
| 2766525411 | road barrier | Street props | SiameseMouse | yes | 33 | 3.0 x 4.2 x 9.0 | world | World: area:Town x4 @1.0; area:Port x4 @1.0 (placed 8 in the live-world test) |
| 8878478175 | factory | Tank Factory | monaliso12345 | yes | 2117 | 127.0 x 81.7 x 242.0 | zone | Rebirth: Tank Factory (WestYard) L3 |
| 2955329464 | [Free] Stalinist Factory | Tank Factory | Vestegnens | yes | 1932 | 233.0 x 165.0 x 75.4 | unused | not placed: 1932 parts, 233 x 165 studs: world budget |
| 12734850183 | Medium Warehouse | Tank Factory | CRRAANNNEEEEEEE | yes | 1711 | 73.8 x 33.5 x 104.8 | unused | not placed: 1711 parts for a plain warehouse box: poor detail per part (world budget) |
| 4784051512 | Delta - 09 Missile Silo | Nuclear Silo | Lephicent | yes | 1723 | 26.1 x 6.3 x 19.5 | zone | Rebirth: Nuclear Silo (StrategicYard) L3 |
| 7649697954 | Improved nuclear missile silo | Nuclear Silo | WillRichterian | yes | 562 | 77.2 x 102.5 x 131.2 | unused | not placed: 562 parts, 131 studs long: the Delta-09 complex is the silo pick |
| 2861271828 | Nuclear Missile | Nuclear Silo | nacker | yes | 32 | 16.0 x 24.0 x 19.0 | zone | Rebirth: Nuclear Silo (StrategicYard) L1,2,3 |
| 929752007 | QF Artillery | Artillery Battery | Aslanovich99 | yes | 123 | 5.4 x 5.2 x 13.8 | zone | Rebirth: Artillery Battery (WestStrip) L2,3 |
| 8535467243 | Artillery gun (working) | Artillery Battery | Xenofell | yes | 79 | 28.7 x 9.6 x 21.9 | world | World: area:FortS x1 @0.7 (placed 1 in the live-world test) |
| 97895120562997 | Artillery | Artillery Battery | retrogamer4590 | yes | 35 | 17.3 x 20.9 x 17.9 | both | World: area:FortI x2 @0.8 (placed 2 in the live-world test) <br> Rebirth: Artillery Battery (WestStrip) L1,2,3 |
| 9064883345 | Military Hangar | Drone Hangar | Germanyinaldi | yes | 1021 | 210.4 x 56.9 x 196.3 | unused | not placed: 1021 parts: world budget (the Airstrip uses the 29-part Military Garage) |
| 12365928579 | Military Garage | Drone Hangar | PrinzAaron | yes | 29 | 56.3 x 21.3 x 47.3 | both | World: area:Airstrip x2 @0.8 (placed 2 in the live-world test) <br> Rebirth: Tank Factory (WestYard) L1,2; Drone Hangar (DroneBay) L1,2,3 |
| 12922051897 | Detailed HeliPad (Helicopter) | Drone Hangar | JuanCool_2004 | yes | 1280 | 63.0 x 19.1 x 76.5 | unused | not placed: 1280 parts: world budget (the Airstrip uses the 29-part Military Garage) |
| 72422635987072 | Drone | Drone Hangar (drones) | xXprogameryotXx | yes | 7 | 3.7 x 0.8 x 3.2 | both | World: area:Airstrip x3 @2.0 (placed 3 in the live-world test) <br> Rebirth: Drone Hangar (DroneBay) L1,2,3 |
| 132341868819826 | Drone Molniya Handmade | Drone Hangar (drones) | IsuperDuperPro999 | yes | 45 | 8.8 x 1.8 x 8.8 | both | World: area:Airstrip x2 @1.3 (placed 2 in the live-world test) <br> Rebirth: Drone Hangar (DroneBay) L2,3 |
| 2580028799 | Recon Drone | Drone Hangar (drones) | XenoSynthesis | yes | 1 | 1.0 x 0.1 x 1.0 | rejected | not placed: it is a Tool with one flat 1x0.1x1 Handle part, not a drone model |
| 8388537872 | military base | Elite Barracks | Cenimosity | yes | 326 | 155.6 x 51.5 x 125.3 | world | World: site:DustCamp x1 @0.6 (placed 1 in the live-world test) |
| 11530941074 | army base | Elite Barracks | Surfyxek | yes | 309 | 91.5 x 30.8 x 67.8 | world | World: area:Armory x1 @0.85 (placed 1 in the live-world test) |
| 8637034739 | Military Barracks /Hostel | Elite Barracks | AviGaTro | yes | 38 | 35.3 x 14.2 x 73.0 | unused | not placed: a plain dark block: worse than our Part barracks (trim colour, 2/3/4 storeys), so the Elite Barracks keeps its Part build |
| 4669786564 | Oil Refinery | Oil Refinery | Lephicent | yes | 1230 | 36.8 x 8.2 x 28.0 | zone | Rebirth: Oil Refinery (EastStrip) L3 |
| 15362548171 | Oil Refinery Factory🏭 | Oil Refinery | avav107 | yes | 3819 | 266.2 x 55.5 x 176.4 | unused | not placed: 3819 parts: over Budget.MaxPartsPerModel |
| 7210304938 | Refinery Structure | Oil Refinery | monsterguy90 | yes | 958 | 67.5 x 103.8 x 117.7 | unused | not placed: 5704 decals: far too heavy for phones |
| 412251367 | Concrete Bunker | Bunker Complex | JOHNEY9987 | yes | 42 | 23.1 x 8.9 x 10.9 | both | World: area:FortI x1 @1.0 (placed 1 in the live-world test) <br> Rebirth: Bunker Complex (WestFlank) L2,3 |
| 6433272094 | Dune Buggy | Rebirth vehicle | Roblox | yes | 153 | 45.9 x 7.0 x 16.8 | world | World: area:Oasis x1 @1.0 (placed 1 in the live-world test) |
| 608760179 | Racing Buggy | Rebirth vehicle | sheenamoonFun | yes | 97 | 5.7 x 5.5 x 10.4 | world | World: area:Oasis x1 @1.0 (placed 1 in the live-world test) |
| 6192529467 | Military Jeep, This is for transport. | Rebirth vehicle | boogalooSaint | yes | 52 | 7.7 x 7.2 x 19.2 | world | World: site:CampViper x1 @1.0; area:Armory x1 @1.0 (placed 2 in the live-world test) |
| 4928101363 | Tank (Works) public! | Rebirth vehicle | xFavihx | yes | 157 | 17.0 x 17.2 x 45.8 | both | World: area:Armory x2 @0.42 (placed 2 in the live-world test) <br> Rebirth: Tank Factory (WestYard) L1,2,3 |

## JOB 40 part C candidates (claude-bud, 2026-09-30): PENDING the probe
Found by a Creator Store search; **none is wired yet**. `StorePropsConfig.ReplaceRows` / `BaseRows` stay empty until
Code Bot runs `tools/probes/job40_props_probe.luau` (Open Cloud Luau on the live place) plus WE_CHECK2 and
`tools/wire-asset-ids.py`. Wire only ids that load, have <= 40 parts after the trim and pass the origin rule.
| Id | Name | Intended use |
|---|---|---|
| 856258654 | Radar Station | Radar Hill (replaces the 6-part RadarDome kit) |
| 91764409 | Radar Station | Radar Hill |
| 124247102466690 | Radar Station Military Dish Satellite | Radar Hill |
| 110033425601385 | Military Satellite Dish Radar Station | Radar Hill / North Ridge |
| 37473580 | Pre-War Radar/Radio Station | Radar Hill |
| 12972439539 | ATC tower | base helipad BaseRow |
| 10140810871 | ATC Tower | base helipad BaseRow |
| 10480494876 | ATC Tower | base airfield BaseRow |
| 1660469777 | Military Cargo HQ | base airfield BaseRow |
| 5437548774 | Radio Command | capture sites |
| 9230948087 | Sandbag Bunker | base guard post / capture sites |
| 12735882090 | Sandbags Bunker | capture sites |
| 11921729320 | Sandbag Bunker small | base BaseRow |
| 11921736228 | Sandbag Bunker medium | base BaseRow |
| 8887518461 | Firebase Sandbag Bunker | capture sites |
| 86311252190175 | Market stall | Crossroads Town |
| 388036950 | Market Stand | Crossroads Town |
| 2033520495 | Stall V2 | Crossroads Town |
| 740042082 | Market | Crossroads Town |

Rejected up front: the SN-75 radar (a real weapon system) and the Phoenix Sky Harbor / Orly control towers (real places).

### JOB 40 part C probe RESULT (Code Bot Roblox v151, 2026-09-30 ~23:00 Dublin, Open Cloud Luau on place 97112936860418)
Script: `tools/probes/job40c_codebot_probe.luau` (read-only: `InsertService:LoadAsset`, the service's strip list, count,
destroy). Raw output: `docs/job40c-probe-2026-09-30.txt`. Creators from the public economy asset-details API.
**Result: 0 of 19 pass. `ReplaceRows` / `BaseRows` stay EMPTY (no world change; the RadarDome kit and plain helipad stay).**
| Id | Creator | Load in the live place | Verdict |
|---|---|---|---|
| 856258654 | VexHavoc | loads | REJECT: 213 parts after the trim (cap 40), 119 plain blocks + 53 built-in-shape meshes, no MeshPart/file mesh (block build); its one decal 77911929 is by botor2, not the creator (origin rule) |
| 91764409 | barnslig101 | "User is not authorized to access Asset" | REJECT: does not load |
| 124247102466690 | mdq6r | not authorized | REJECT: does not load |
| 110033425601385 | mdq6r | not authorized | REJECT: does not load |
| 37473580 | Ursur3minor | not authorized | REJECT: does not load |
| 12972439539 | HV11l | not authorized | REJECT: does not load |
| 10140810871 | group "Philadelphia International Airport" | not authorized | REJECT: does not load; also a real-place copy |
| 10480494876 | SharkySailor | not authorized | REJECT: does not load |
| 1660469777 | F15player | not authorized | REJECT: does not load |
| 5437548774 | group Chill Imperium | not authorized | REJECT: does not load |
| 9230948087 | group Blox Let Loose | not authorized | REJECT: does not load |
| 12735882090 | ToffifeeTheExplorer | not authorized | REJECT: does not load |
| 11921729320 | 2h1ft3d | not authorized | REJECT: does not load |
| 11921736228 | 2h1ft3d | not authorized | REJECT: does not load |
| 8887518461 | BaconHair77893 | not authorized | REJECT: does not load |
| 86311252190175 | IAmASwedishMale | not authorized | REJECT: does not load |
| 388036950 | WoodReviewer | not authorized | REJECT: does not load |
| 2033520495 | HaizieR | not authorized | REJECT: does not load |
| 740042082 | KiratoKun | not authorized | REJECT: does not load |

All 19 are free public models, but none is owned by Roblox or by shaunie6, and the 18 that fail are not in the place
owner's inventory, so the live place cannot load them. To try them again the owner must "Get" each one on the Creator
Store with shaunie6 (then re-run the probe). A Creator Store search for Roblox-made radar / sandbag / stall / tower
models found none.

### JOB 40 part C RE-PROBE (Code Bot Roblox v152, 2026-09-30 ~23:15 Dublin, after the owner's Get Model on 17 ids)
Same script (`tools/probes/job40c_codebot_probe.luau`), raw output `docs/job40c-probe2-2026-09-30.txt`. Now **18 of 19
load** (10140810871 still not authorized and rejected anyway: a real airport's group). Rules: <= 40 parts after the
trim, real mesh detail (not a block build), every mesh / texture by the model's creator, no real-world / franchise copy,
scripts stripped. **1 passes: 86311252190175 Market stall.**
| Id | Loads | Parts (trim) | Detail | Origin | Verdict |
|---|---|---|---|---|---|
| 856258654 Radar Station | yes | 213 | 119 blocks, built-in shapes | decal 77911929 by botor2 | REJECT (parts, block build, origin) |
| 91764409 Radar Station | yes | 44 | 41 blocks, no mesh | own decal | REJECT (parts, block build) |
| 124247102466690 Radar Station Military Dish | yes | 213 | a re-upload of 856258654 + 2 scripts | decal by botor2 | REJECT (copy, parts, origin) |
| 110033425601385 Military Satellite Dish | yes | 1 | 1 MeshPart | mesh + texture by holder_thatswhyim, not mdq6r | REJECT (origin) |
| 37473580 Pre-War Radar | yes | 26 | block build on a grass baseplate | - | REJECT (block build) |
| 12972439539 ATC tower | yes | 114 | unions + 3D text | texture 42420590 by EpikYummeh, mesh by XAXA | REJECT (parts, origin) |
| 10480494876 ATC Tower | yes | 2993 | blocks | - | REJECT (parts, block build) |
| 1660469777 Military Cargo HQ | yes | 38 | 26 unions + 12 blocks (plain box, thumbnail) | - | REJECT (block build) |
| 5437548774 Radio Command | yes | 830 | blocks | - | REJECT (parts) |
| 9230948087 Sandbag Bunker | yes | 100 | 99 MeshParts | - | REJECT (parts > 40) |
| 12735882090 Sandbags Bunker | yes | 112 | contains an "M60" gun, 22 scripts, a SpawnLocation | mesh 467359376 by ChIoroplast | REJECT (real weapon, parts, scripts) |
| 11921729320 / 11921736228 Sandbag Bunker small / medium | yes | 320 / 1200 | one Roblox sandbag mesh per bag | texture 139076290 by Enrxq | REJECT (parts, origin) |
| 8887518461 Firebase Sandbag Bunker | yes | 175 | 1050 textures | - | REJECT (parts) |
| **86311252190175 Market stall** | **yes** | **1** | **1 textured MeshPart (awning, baskets of fruit)** | **mesh 115301117023765 + texture 125481352272554 by IAmASwedishMale (the creator)** | **PASS** |
| 388036950 / 740042082 Market Stand / Market | yes | 109 / 110 | parts + built-in shapes | mesh / texture by Roblox (ok) | REJECT (parts) |
| 2033520495 Stall V2 | yes | 66 | 29 unions + 29 blocks | textures by ZacAttackk | REJECT (parts, origin) |

**Wired (owner-first `StorePropsConfig.JOB40`):** two ReplaceRows, the market stall at Scale 5 (8.2 x 10.0 x 5.1 studs)
in place of the Part stalls NW_Stall_1 (-81, -166.4) and NW_Stall_2 (-80, -182.6) in the Crossroads Town market lane
(the kit's counter is the anchor). Dry run on the live place (`tools/probes/job40c_stall_dryrun.luau`, the Town built by
WorldPOI.Build, the service's steps): 7 kit parts hidden per stall, the copy's bottom = the kit base (0.50), 0 overlaps,
the copy faces the same way as the kit. No radar / tower / bunker passed: Radar Hill and BaseRows stay as today.
