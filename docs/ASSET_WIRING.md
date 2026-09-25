# Your Creator Store list: what is wired, what waits, and why

**Date:** 2026-09-25. **Your list:** 154 lines, 217 items, 151 different store ids (the list you sent on 2026-09-25).
**How it was checked:** every id was looked up on Roblox's public store and inventory pages, pictures were looked at, and
Roblox's own models were downloaded and taken apart. Nothing here was run inside Roblox yet: the "test on your phone" list
below is the real check. Store names below are for you only; players never see them.

Related pages: `docs/ASSET_LICENSES.md` (who made each id, the terms, why it is allowed) and `docs/ASSET_SHORTLIST.md`
(how assets reach the game, the Studio check script). The full decision sheet with the evidence for every row is the
lead's spec (assetwire, 2026-09-25).

| What happened | Items |
|---|---|
| Wired now: Roblox's own models, no Get Model needed | 27 |
| Your Get Model picks, waiting for the promote step | 69 |
| Kept our own build | 21 |
| Not used (wrong item, real-world copy, too heavy …) | 32 |
| Needs new game code first | 48 |
| Waits on a file another job is editing | 11 |
| Soldiers and guards: need moving (animated) figures first | 9 |

## 1. What changed and what to test on your phone

Test on your phone in landscape, at Graphics Quality 3 if you can (a mid-range Android is the real bar).

- **Guns:** equip each gun (starter rifle, assault rifle, SMG, pistol, shotgun, sniper, rocket launcher). The gun sits in
  the hand, barrel forward, at a sensible size, and the muzzle flash is at the barrel.
- **Grenade and rocket:** throw a grenade and fire a rocket. The new model shows and points along its flight.
- **Vehicles:** spawn the Utility Quad, Recon Buggy, Cargo Van, Patrol Truck and Escort Truck. The body sits on the wheels
  and faces forward, it drives with the thumbstick alone, and jump gets you out. The jeeps and the Armed 4x4 look as before.
- **Training yard:** the oil drums show, with no smoke.
- **Roads and shores:** logs, driftwood, dead trees, stumps, grass tufts and dark car wrecks are not squashed or sideways.
  Watch the frame rate near the Town and near a group of wrecks.
- **Walls level 4 and up:** note which gate gun shows. Until the first promote batch it is the machine-gun model you listed
  for the sandbag nest (you own it now, so it loads); the first batch swaps in your tripod gun pick.

After each promote batch the lead adds that batch's phone checks here.

## 2. Wired now (27)

Roblox's own models: they load with "Allow Loading Third Party Assets" OFF, so you click nothing. "Already live" rows
were wired before your list; the Synty trees, stumps, reeds and grass now really show (before, other pieces took their
slots).

| Item | What you will see | Where | Roblox asset (name, id) |
|---|---|---|---|
| Military Jeep | Roblox utility-vehicle body on the Field 4x4 (already live) | vehicles | Light Utility Vehicle, 6418221666 |
| Armed Jeep | same body, our gun kept (already live) | vehicles | Light Utility Vehicle, 6418221666 |
| Scout Car | same body (already live) | vehicles | Light Utility Vehicle, 6418221666 |
| Dispatch Car | same body (already live) | vehicles | Light Utility Vehicle, 6418221666 |
| Utility Quad | Roblox dune-buggy body | vehicles | Dune Buggy, 6433272094 |
| Recon Buggy | Roblox dune-buggy body | vehicles | Dune Buggy, 6433272094 |
| Patrol Truck | Roblox pickup body | vehicles | Pickup Truck, 6418225759 |
| Escort Truck | Roblox pickup body | vehicles | Pickup Truck, 6418225759 |
| Cargo Van | Roblox van body | vehicles | Van, 6433316269 |
| Starter Rifle | Roblox rifle model in hand | in hand | Auto Rifle, 4842207161 |
| Assault Rifle | Roblox rifle model in hand | in hand | Auto Rifle, 4842207161 |
| SMG | Roblox SMG in hand | in hand | Submachine Gun, 4842212980 |
| Pistol | Roblox pistol in hand | in hand | Pistol, 4842197274 |
| Shotgun | Roblox shotgun in hand | in hand | Shotgun, 4842215723 |
| Sniper | Roblox sniper rifle in hand | in hand | Sniper Rifle, 4842218829 |
| Rocket Launcher | Roblox launcher in hand | in hand | Rocket Launcher, 4842186817 |
| Grenade | Roblox grenade mesh in flight | grenade in flight | grenade mesh + texture, 232379763 |
| Cruise Missile | Roblox rocket mesh in flight (the rocket-launcher round) | rocket in flight | rocket mesh + texture, 94690081 |
| Crate Stack | Synty wooden crates (already live) | roads, towns | Synty Dungeon Pack: Weapons & Props, 6933790012 |
| Oil Barrel | Roblox oil drum, smoke removed | training yard | Smoking Barrel, 23153991 |
| Wreck | Synty sedan as a dark burnt wreck | roads | Synty City Pack, 6933556508 |
| Dead Tree | Synty dead tree | roads | Synty Nature Pack, 6933438443 |
| Stump | Synty stump | roads | Synty Nature Pack, 6933438443 |
| Log | Synty fallen log | roads | Synty Nature Pack, 6933438443 |
| Driftwood | Synty twig as driftwood | shores | Synty Nature Pack, 6933438443 |
| Reeds | Synty reeds | shores | Synty Nature Pack, 6933438443 |
| Dune Grass | Synty dry plant | roads | Synty Nature Pack, 6933438443 |

Cruise Missile: this is the rocket-launcher round in flight. If you meant the Missile Command strike missile, that one has
no model slot yet (tell the lead).

## 3. Get Model: done, thank you

Checked 2026-09-25 08:05 UTC on Roblox's inventory page for your account (shaunie6): **you own 147 of the 151 ids on your
list, every third-party one.** The 4 you do not own need nothing: two are Roblox meshes (232379763, 94690081) and two are
the "keep the current build" examples (4559046046 Premium Pad, 89668347 Pave Tile). Re-checked 2026-09-25 08:50 UTC
for the 43 ids that wait below: all 43 owned, and their store pages still show the same creator and a free price.

Owning a model only makes it loadable. Nothing below shows in the game until the lead promotes it with
`tools/wire-asset-ids.py` (section 9), batch by batch. "Next step" says what each one still needs.

**Base buildings (recorded only: they do not show while the buildings stay our walk-in shells, your rule 4)**

| Item(s) | Id | Store name | Creator | Owned | Next step |
|---|---|---|---|---|---|
| Command Center | [43803492](https://create.roblox.com/store/asset/43803492) | Command Center | Firebrand1 | yes | your yes/no (batch P2); recorded only |
| Barracks | [8637034739](https://create.roblox.com/store/asset/8637034739) | Military Barracks /Hostel | AviGaTro | yes | recorded (batch P1i); no change on screen |
| Vehicle Depot | [4005471827](https://create.roblox.com/store/asset/4005471827) | Military garage | TamasdztYT | yes | the Studio check (batch P2); recorded only |
| Weapons Facility | [11850705638](https://create.roblox.com/store/asset/11850705638) | Armory | DISPLAYMODELS | yes | your yes/no (batch P2); recorded only |
| Helipad | [45369635](https://create.roblox.com/store/asset/45369635) | Helipad | sleitnick | yes | recorded (batch P1i); no change on screen |
| Dock | [13183571527](https://create.roblox.com/store/asset/13183571527) | boat dock | tihi2 | yes | the Studio check (batch P2); recorded only |
| Watchtowers | [52154909](https://create.roblox.com/store/asset/52154909) | guard tower | Morniratu | yes | the Studio check (batch P2); recorded only |
| Radar | [856258654](https://create.roblox.com/store/asset/856258654) | Radar Station | VexHavoc | yes | recorded (batch P1i); no change on screen |
| Missile Defense | [3461514733](https://create.roblox.com/store/asset/3461514733) | Missile Launcher | cwd30 | yes | recorded (batch P1i); no change on screen |
| Power Station | [6869290892](https://create.roblox.com/store/asset/6869290892) | Power Station | bossmanjesus101 | yes | recorded (batch P1i); no change on screen |
| Warehouse | [8076230849](https://create.roblox.com/store/asset/8076230849) | Warehouse | sydneycrosby_875 | yes | recorded (batch P1i); no change on screen |
| Special Forces Facility [WEAK] | [10112923897](https://create.roblox.com/store/asset/10112923897) | Military defense outpost. | Roseaity | yes | recorded (batch P1i); no change on screen |
| Hangar | [5343886540](https://create.roblox.com/store/asset/5343886540) | plane hangar | Hyperalis | yes | your yes/no + the Studio check (batch P2); recorded only |

**Walls (these do show: perimeter walls, level 3 and up)**

| Item(s) | Id | Store name | Creator | Owned | Next step |
|---|---|---|---|---|---|
| Defensive Walls | [6980242709](https://create.roblox.com/store/asset/6980242709) | Military Wall | SMehmetaga | yes | the Studio check (batch P2) |
| Defensive Walls L3 | [8333853928](https://create.roblox.com/store/asset/8333853928) | T WALL | steveaut | yes | the Studio check (batch P2) |

**Base props and the tutorial arrow**

| Item(s) | Id | Store name | Creator | Owned | Next step |
|---|---|---|---|---|---|
| Money Collector | [18220523228](https://create.roblox.com/store/asset/18220523228) | ATM | 0GColt | yes | first promote batch (P1): nothing else needed |
| Plot Oil Pump | [15192621369](https://create.roblox.com/store/asset/15192621369) | Oil Rig / Pumpjack | sadfiacs | yes | first promote batch (P1): nothing else needed |
| Tent | [182529039](https://create.roblox.com/store/asset/182529039) | Military Canvas Tent | Quenty | yes | first promote batch (P1): nothing else needed |
| Sandbag Line | [15271872710](https://create.roblox.com/store/asset/15271872710) | SandBag Wall | Herbie778811 | yes | first promote batch (P1): nothing else needed |
| Jersey | [2766525411](https://create.roblox.com/store/asset/2766525411) | road barrier | SiameseMouse | yes | first promote batch (P1): nothing else needed |
| Military Crate | [2930926216](https://create.roblox.com/store/asset/2930926216) | Military Crates | XIArchangel | yes | first promote batch (P1): nothing else needed |
| Fuel Cans | [112426091](https://create.roblox.com/store/asset/112426091) | Gas Can | Maximum_ADHD | yes | recorded (batch P1i); no change on screen |
| Flag Pole | [172755983](https://create.roblox.com/store/asset/172755983) | Flagpole | Quenty | yes | recorded (batch P1i); no change on screen |
| Radio Antenna | [1439808070](https://create.roblox.com/store/asset/1439808070) | Antenna | Sereinmachy | yes | recorded (batch P1i); no change on screen |
| Tutorial Arrow | [632958370](https://create.roblox.com/store/asset/632958370) | Arrow | isaacbeyo | yes | first promote batch (P1): nothing else needed |

**Gate gun**

| Item(s) | Id | Store name | Creator | Owned | Next step |
|---|---|---|---|---|---|
| Auto Gun | [114570602](https://create.roblox.com/store/asset/114570602) | Tripod Mounted Machine Gun | GuestCapone | yes | first promote batch (P1): nothing else needed |

**Vehicles (each needs the Studio check; the model is dress only, our kit still drives)**

| Item(s) | Id | Store name | Creator | Owned | Next step |
|---|---|---|---|---|---|
| Armored Truck, Supply Truck, Ammo Carrier, Troop Transport, Recovery Truck, Anti Air Truck | [8546141386](https://create.roblox.com/store/asset/8546141386) | Military Truck | LouBrawlerStars | yes | your yes/no + the Studio check (batch P3) |
| Fuel Tanker | [5318635087](https://create.roblox.com/store/asset/5318635087) | fuel truck | asp307 | yes | the Studio check (batch P3) |
| Flatbed Hauler | [8455894899](https://create.roblox.com/store/asset/8455894899) | FlatBed Truck | YourBoi_JonnyBoi | yes | the Studio check (batch P3) |
| Radar Truck | [31538715](https://create.roblox.com/store/asset/31538715) | RMAR truck radar | Armour_Fox | yes | the Studio check (batch P3) |
| APC, Infantry Carrier, Command Vehicle, Wheeled IFV, Amphibious APC | [9076240315](https://create.roblox.com/store/asset/9076240315) | APC | CorzCringe | yes | the Studio check (batch P3) |
| Combat IFV, Assault IFV, Flame Carrier | [11552687660](https://create.roblox.com/store/asset/11552687660) | Fiction IFV | spookstiy | yes | the Studio check (batch P3) |
| Missile Truck, Rocket Artillery | [3304171953](https://create.roblox.com/store/asset/3304171953) | missile truck | KlassicKanadian | yes | the Studio check (batch P3) |
| SPAAG, Mobile SAM [WEAK] | [10069416832](https://create.roblox.com/store/asset/10069416832) | anti aircraft Tank | XCX1001 | yes | the Studio check (batch P3) |
| Light Scout Heli, Utility Heli | [2474869838](https://create.roblox.com/store/asset/2474869838) | Low poly helicopter | Azarth | yes | the Studio check (batch P3) |
| Transport Heli, Heavy Lift Heli, Light Transport Heli | [2627182035](https://create.roblox.com/store/asset/2627182035) | transport helicopter | blokkere | yes | your yes/no + the Studio check (batch P3) |
| Rescue Heli, Medevac Heli | [11357157285](https://create.roblox.com/store/asset/11357157285) (your 11357398877 is the same model; one load for both) | Rescue Helicopter | KiboSprite | yes | the Studio check (batch P3) |
| Fighter Jet, Interceptor Jet, Trainer Jet, Light Fighter | [3553891209](https://create.roblox.com/store/asset/3553891209) | Fighter Jet concept | PlanesFun56 | yes | the Studio check (batch P3) |
| Recon Plane | [4954987035](https://create.roblox.com/store/asset/4954987035) | Old propeller plane | Deadex40_Extra | yes | your yes/no + the Studio check (batch P3) |
| Patrol Boat, Fast Attack Craft, Coast Cutter, Torpedo Boat | [5177695483](https://create.roblox.com/store/asset/5177695483) | Patrol Boat | pirateparty1234 | yes | the Studio check (batch P3) |
| Gunboat, Missile Boat, Mine Layer, Coastal Monitor | [15838664806](https://create.roblox.com/store/asset/15838664806) | Basic Gunboat | Confused Giants Studio (group) | yes | the Studio check (batch P3) |
| Hover Transport | [43773162](https://create.roblox.com/store/asset/43773162) | HoverCraft | Fractality | yes | the Studio check (batch P3) |
| Supply Ship | [11756438288](https://create.roblox.com/store/asset/11756438288) | Cargo Ship | Yorsiur | yes | the Studio check (batch P3) |

**No Get Model needed for Roblox's own items** (28 ids): 23153972, 23153991, 23154052, 31603741, 41324890, 56446217, 56447829, 56449028, 80566030, 94690081, 123041248, 187790284, 232379763, 4842186817, 4842197274, 4842207161, 4842212980, 4842215723, 4842218829, 6418221666, 6418225759, 6418277837, 6433272094, 6433316269, 6433323089, 6933438443, 6933556508, 6933790012.

## 4. Your yes / no (11 calls)

Reply with the number and yes or no. Nothing below changes the game until you answer and the lead promotes it.

1. Roblox's own Auto Rifle and Rocket Launcher have AK-style and RPG-style shapes (unnamed Roblox models). They are wired now because you listed them; say no and they go back to our kit guns (one-line change).
2. Military Truck 8546141386 for 6 trucks (Armored, Supply, Ammo, Troop, Recovery, Anti-Air): it reads like a US M35-style 6x6 and is more realistic than the rest of the world. Yes or no?
3. Transport helicopter 2627182035 for the transport helis: a two-rotor layout like a CH-47. Yes or no?
4. Recon Plane 4954987035 looks like a wooden toy plane (our kit may look better). Yes or no?
5. Command Center 43803492 was made for another Roblox game ("Conquerors") and is plainer than our building. Yes or no? (It only shows if buildings ever use store models.)
6. Weapons Facility 11850705638 says it is "crim inspired" and has a glowing "ARMORY 1" sign. Yes or no? (same note as 5)
7. Hangar 5343886540: its store description was removed by Roblox moderation. Yes or no? (same note as 5)
8. Guards: one Roblox soldier model (187790284) for every military guard, as your rule 9 says, or the separate guard models you listed per row?
9. Worker 893013681: its sleeve reads "ROCKPORT … DEPARTMENT OF TRANSPORTATION" and the author asks for credit. Keep it (we credit the author) or use the Roblox soldier?
10. Helicopter wreck 4533405525 looks like a Black Hawk; the cash pile 11760036257 shows US dollar bills (we would strip the bills). Yes or no for each?
11. Premium Razorfang as Roblox's red sports car (a civilian supercar in a paid military slot), and Premium Tidebreaker as a speedboat on a road trailer (origin unclear). Yes or no for each?

## 5. Studio check (for you or Grok)

Some models cannot be looked inside from outside Roblox, so before they go live someone runs the check script in Studio.
Use the script in `docs/ASSET_SHORTLIST.md` section 5, step 5 (open the live place from the Creator Dashboard, press
Run, paste the script with the list below, copy every line that starts with `WE_CHECK`). Paste the `WE_CHECK` lines back
to the lead. A model passes with `parts` 40 or less and `humanoids=0`; for vehicles the `size` tells the tool which way the
model faces.

- **Batch P2 (walls and buildings):** 52154909, 4005471827, 5343886540, 6980242709, 8333853928, 13183571527
- **Batch P3 (vehicles):** 31538715, 43773162, 2474869838, 2627182035, 3304171953, 3553891209, 4954987035, 5177695483, 5318635087, 8455894899, 8546141386, 9076240315, 10069416832, 11357157285, 11552687660, 11756438288, 15838664806

## 6. Not wired, and why

### 6.1 Not used (32)

You own several of these now; owning them does nothing until an id is wired, and these never will be.

| Item | Id | Reason |
|---|---|---|
| Training Yard | 8712482791 | wrong item: a group-training button board, not a military yard |
| Research Lab | 115528226 | wrong item: a spiky sci-fi hull listed as a vehicle |
| Empire Bank | 10153551618 | wrong item: this store 'bank' is a park bench |
| Town Block | 6418277837 | too heavy for phones: pack buildings are 130-270 studs wide, two are over 40 parts |
| Crusher | 243918123 | wrong item: a walled pit, not a crusher |
| Fountain | 56447829 | 47 parts (over the 40-part cap), and it is a well |
| Compound Wall | 3528925155 | wrong scale: a stone ring around a whole 512-stud baseplate |
| Sandbag Nest | 4923345827 | wrong item: a lone WWII-style machine gun with no sandbags |
| Revetment | 23154052 | no gain: one flat slab like our own kit; it would only use a load |
| Engineering Truck | 32520888 | cannot be checked: the only picture shows the inside of a block |
| Mine Clearer | 4128281751 | wrong item (a wheel loader) and unclear origin |
| Gunship Heli | 14652689347 | copy of a game-franchise gunship (Half-Life 2) |
| Attack Helicopter | 14652689347 | copy of a game-franchise gunship (Half-Life 2) |
| Escort Heli | 14652689347 | copy of a game-franchise gunship (Half-Life 2) |
| Night Attack Heli | 14652689347 | copy of a game-franchise gunship (Half-Life 2) |
| Premium Stormwing | 14652689347 | copy of a game-franchise gunship (Half-Life 2) |
| VTOL Transport | 10551768980 | the uploader does not claim it ('Unknown Vtol'); looks ripped |
| Cargo Plane | 4631044408 | 47 parts (over 40) and a real cargo-plane look |
| AWACS Plane | 4631044408 | 47 parts (over 40) and a real cargo-plane look |
| Tanker Plane | 4631044408 | 47 parts (over 40) and a real cargo-plane look |
| Strike Jet | 14451400891 | copy of a real jet (F-16) |
| CAS Jet | 14451400891 | copy of a real jet (F-16) |
| Strike Bomber | 12592130497 | national-style roundel on the wing; made by someone else |
| Landing Craft | 9732307513 | wrong item: a space lander |
| Assault Landing | 9732307513 | wrong item: a space lander |
| Amphib Assault | 9732307513 | wrong item: a space lander |
| River Boat | 44658425 | wrong item (a theme-park raft) and made by someone else |
| Hospital Ship | 12209928092 | red-cross emblems and a copy of a named real ship |
| Special Forces | 5551977277 | wrong item: a beret with a real regiment's badge |
| Ammo Box | 11330346120 | ripped from another game (Fallout 4), real ammo stencils |
| Plane Wreck | 469899691 | made by someone else; 12,274 tris spread wide |
| Showroom Podium | 128957600005820 | wrong item: a record player |

### 6.2 Kept our own build (21)

| Item | Id | Reason |
|---|---|---|
| Oil Rig | 1962122463 | [WEAK]; likely over 40 parts; our oil-rig kit is the gameplay platform |
| Premium Pad | 4559046046 | you said no good match: keep our build |
| Bridge Layer | 11552687660 | you said no good match: keep our build (it never borrows another tank's body) |
| Light Tank | 13049288544 | [WEAK]; a green box tank, cruder than our tank kit (7 tanks would share it) |
| Medium Tank | 13049288544 | [WEAK]; a green box tank, cruder than our tank kit (7 tanks would share it) |
| Heavy Tank | 13049288544 | [WEAK]; a green box tank, cruder than our tank kit (7 tanks would share it) |
| Battle Tank | 13049288544 | [WEAK]; a green box tank, cruder than our tank kit (7 tanks would share it) |
| Tank Destroyer | 13049288544 | [WEAK]; a green box tank, cruder than our tank kit (7 tanks would share it) |
| Assault Gun | 13049288544 | [WEAK]; a green box tank, cruder than our tank kit (7 tanks would share it) |
| Light Scout Tank | 13049288544 | [WEAK]; a green box tank, cruder than our tank kit (7 tanks would share it) |
| Premium Warlord | 93078960435881 | [WEAK]; brick-built toy tank, far over 40 parts; paid slot |
| Mortar Carrier | 8182414481 | [WEAK]; a tripod mortar with no vehicle |
| Mobile Artillery | 10745209274 | [WEAK]; a crude block gun, worse than our kit |
| Howitzer Truck | 10745209274 | [WEAK]; a crude block gun, worse than our kit |
| Siege Mortar | 10745209274 | [WEAK]; a crude block gun, worse than our kit |
| Corvette | 418143173 | [WEAK]; a plain hull with no guns; our warship kit reads better |
| Destroyer | 418143173 | [WEAK]; a plain hull with no guns; our warship kit reads better |
| Frigate | 418143173 | [WEAK]; a plain hull with no guns; our warship kit reads better |
| Carrier Escort | 418143173 | [WEAK]; a plain hull with no guns; our warship kit reads better |
| Rocket Pods | 4795009475 | [WEAK]; the asset is a whole car; our kit is the pod |
| Pave Tile | 89668347 | you said no good match: keep our build |

### 6.3 Needs new game code first (48)

**World models (37):** the world's buildings and props are built from simple parts by our own kit code. To wear
a whole store model instead, the kit code needs one new step (a follow-up job the lead calls W-OVERLAY). It also has to
fit the per-server load budget (section 8), so it would ship a few kinds at a time, most-seen first.

| Item | Id | Note |
|---|---|---|
| Runway | 163825225 | – |
| Bunker | 62623350 | 43 parts, 3 wedges must be dropped |
| Market Stall | 13958174035 | – |
| Water Tower | 4112608919 | – |
| Clock Tower | 3363415990 | – |
| Adobe House | 161539164 | – |
| Ruined House | 49387516 | – |
| Checkpoint | 172411984 | – |
| Radio Mast | 8788183000 | – |
| Gantry Crane | 3416199767 | – |
| Fuel Tank | 5205016205 | – |
| Flare Stack | 9425248992 | – |
| Radar Dome | 1315600448 | – |
| Terminal | 56446217 | Roblox's own: no Get needed |
| Ammo Shed | 9359074735 | – |
| Wire Fence | 2680065782 | – |
| Tank Trap | 11654379868 | – |
| Barbed Wire | 1230286742 | – |
| Hesco Barrier | 393895905 | – |
| Drum Group | 1182845714 | – |
| Container Stack | 11915902478 | – |
| Heli Wreck | 4533405525 | – |
| Barge Wreck | 2107703217 | – |
| Beached Hull | 2107703217 | – |
| Jetty Stub | 17659258441 | – |
| Street Lamp | 56449028 | Roblox's own: no Get needed |
| Poi Board | 399673893 | – |
| Dir Sign | 1014941563 | – |
| Road Marker | 399729455 | – |
| Bench | 23153972 | Roblox's own: no Get needed |
| Campfire | 123041248 | Roblox's own: no Get needed |
| Pipe Run | 130992089465874 | – |
| Palm | 10562894034 | – |
| Saguaro | 4896954650 | – |
| Barrel Cactus | 5074278893 | – |
| Joshua | 9986063643 | – |
| Hold Pad | 80566030 | Roblox's own: no Get needed |

**Other code first:**

| Item | Id | What is needed |
|---|---|---|
| Supply Drop Crate | 3069220296 | needs one call in SupplyDropService (drop crate dress) |
| Supply Spinner | 97392503970266 | not recommended: the spinner is a screen panel, not a world object |
| Airfield | 163825225 | not recommended: the airfield builds its own runway |
| Base Gate | 199293130 | needs one call in StructureKitBuilder (gate arch dress) |
| Town Civilian | 9436861676 | needs a town civilian spawner plus the animated-rig job |
| Nuke | 286526228 | needs a nuke-strike effect module (none exists) |
| Floodlight | 122160708 | needs a host outside the building-mesh switch, and 5 of its 6 lights removed |
| Camo Net | 13437018139 | needs a camp host (W-OVERLAY) and a BuyPathStatic pin lifted |
| Desert Rock | 6933438443 | not recommended: world rocks are terrain (0 parts) |
| Desert Mesa | 6933438443 | needs a horizon host in MapSetup (another job's file) |
| Cash Pile | 11760036257 | needs a host; the bills must be stripped (real currency art) |

### 6.4 Waiting on another job (11)

These need a change in a file that another job (streaming, part 2) is editing right now. The exact change is written down
and is made when that job lands.

| Item | Id | Waits on |
|---|---|---|
| Ammo Works | 41324890 | BusinessService (streaming2-build): business dress hook |
| Arms Crate Line | 41324890 | BusinessService (streaming2-build): business dress hook |
| Armor Plate Press | 4362642898 | BusinessService (streaming2-build): business dress hook |
| Rocket Assembly | 31603741 | BusinessService (streaming2-build): business dress hook |
| Manual Dropper | 14408455045 | ManualDropperService (streaming2-build lane C1): dropper dress hook |
| Home Outpost | 80566030 | MapSetup (streaming2-build): Home Outpost dress hook |
| Premium Razorfang | 6433323089 | VehicleConfig + VehicleService (streaming2-build): premium vehicle def |
| Premium Bastion | 16835152672 | VehicleConfig + VehicleService (streaming2-build): premium vehicle def |
| Premium Tidebreaker | 4128350737 | VehicleConfig + VehicleService (streaming2-build): premium vehicle def, then a Studio look |
| Vehicle MG | 5589684833 | VehicleService (streaming2-build): turret dress hook |
| Vehicle Cannon | 3322196012 | VehicleService (streaming2-build): turret dress hook |

### 6.5 Soldiers and guards (9)

Your rule 9 says units and guards must be moving figures, not welded statues. Today the game welds a model onto the guard,
so wiring these ids now would give statues. A follow-up job (R-RIG) keeps each model's joints, adds idle and walk
animations and keeps our hitbox for fair aiming. Your answer to call 8 decides whether every military guard uses the Roblox
soldier 187790284 (what rule 9 says) or the models listed per row.

| Item | Id | Note |
|---|---|---|
| Soldier | 187790284 | Roblox soldier (rule 9) |
| Infantry | 187790284 | Roblox soldier (rule 9) |
| Heavy Infantry | 4485938042 | Heavy Soldier [IMPROVED] by squaremini; call 8 |
| Worker | 893013681 | Construction Worker (original) by ThePotatoMash; call 8 and 9 |
| Guard | 181161444 | Soldier - Guard by kurakura; call 8 |
| Gate Guard | 76710780 | Desert Ops Recon Soldier Guard 1 by Tokivoli; call 8 |
| Oil Rig Guard | 187790284 | Roblox soldier (rule 9) |
| Fort Guard | 187790284 | Roblox soldier (rule 9) |
| Bank Guard | 1409417554 | Security guard by justjbm3; call 8 |

## 7. Imported or simplified

| Asset | What we keep | What we remove or change |
|---|---|---|
| Roblox cars (Dune Buggy, Pickup Truck, Van, and the Light Utility Vehicle already live) | the body only, scaled to our vehicle | chassis, scripts, seats and sounds; decals off; the pickup's tail-light glass is dropped (41 parts → 40) |
| Roblox guns (Weapons Kit) | the gun model plus an invisible grip | scripts, sounds and the kit's weapon system |
| Grenade and rocket | the mesh and its texture | nothing else is loaded |
| Oil drum (Roblox Smoking Barrel) | the whole drum, 4 parts | the smoke |
| Synty pieces (log, twig, sedan, and the trees, stumps, reeds, grass and crates already live) | one mesh each, recoloured to the desert palette | texture cleared; the sedan is recoloured as a burnt wreck and turned 90°, the twig is turned 90° as driftwood |
| Every store model (now and at promote) | the look | scripts, seats, joints, prompts, sounds and movers; glowing parts become plastic on pack pieces; more than 40 parts or any Humanoid → refused, our kit stays |
| Waiting picks | – | the tripod gun is 31 parts; vehicles are dress only while our kit drives; the Studio check decides the rest |

## 8. Load budget (why promotes go in batches)

Each server may try at most 48 model loads (a failed one still counts). Today's config asks for about 22 different models
on a live server (estimate from the headless census and the promote tool's count, not measured in Roblox). The promote
tool refuses a batch that would pass 40, which keeps room for retries. After the walls (P2) the vehicle batch (P3, 17
models) would bring the count to about 41, so it goes in together with a small clean-up that frees 2–3 slots (a crate
model that never loads and two effect models that never load). Guns, the gate gun and the grenade and rocket meshes do
not count against the 48.

## 9. For the lead: the promote tool

`tools/wire-asset-ids.py` (Python 3, standard library only). It never runs git and never edits StructureVisualConfig
(PreferMeshWhenAssetIdSet stays false).

```
python3 tools/wire-asset-ids.py status                 # every item: decision, live id, pending id, gate, load budget
python3 tools/wire-asset-ids.py pending                # the PendingAssetId values in the config, verified or not
python3 tools/wire-asset-ids.py check --store          # inventory + store re-check of every pending id (cached, <= 2 req/s)
python3 tools/wire-asset-ids.py promote --batch P1 --dry-run   # print the diff, write nothing
python3 tools/wire-asset-ids.py promote --batch P1             # edit, then luau-compile + BuyPathStatic (no new FAIL) or restore
python3 tools/wire-asset-ids.py promote --batch P3 --we-check we_check.txt --owner-ok 8546141386,2627182035
python3 tools/wire-asset-ids.py demote 114570602       # undo one promotion (journal: docs/asset_wiring.json)
python3 tools/wire-asset-ids.py render [--check]       # the status table at the end of this page
```

- **Batches:** P1 = 8 ids with no gate that show on live (tripod gun, tent, tutorial arrow, road barrier, crates, plot pump,
  sandbags, ATM). P1i = 10 ids recorded in fields that stay hidden (no change on screen). P2 = walls (they show) and the
  buildings that need a yes/no or the Studio check. P3 = the 17 vehicle models (Studio check, 3 need a yes/no, and the
  load-budget clean-up in the same commit).
- **What one promote writes:** `ModelAssetId = <id>` in every config line of that id (vehicles also get `Fit`, `Yaw`,
  `HideKit`, `StripDecals`), the `PendingAssetId` removed, a new `Note`; any BuyPathStatic needle that pinned the old id
  rewritten to the new id; the `docs/ASSET_LICENSES.md` §3.1 row (and a replaced id's §3 row moved to §2e when it leaves
  `src/`); this page's status table; and the undo journal `docs/asset_wiring.json`. Commit them together.
- **Refusals:** unknown keys or ids, any decision other than a waiting pick, an id with no `PendingAssetId` in the config,
  not owned, store changed (creator, type, price), a missing yes/no or Studio check, a `WE_CHECK` over 40 parts or with a
  Humanoid, a batch over the load budget, and any edit that breaks a BuyPathStatic needle it cannot rewrite.
- After a promote: run the census (cap_refused must stay 0) and add that batch's phone checks to section 1.

## 10. Status of every item (generated)

<!-- wire-asset-ids:begin (generated by tools/wire-asset-ids.py render; do not edit by hand) -->

Generated from the repo config (PreferMeshWhenAssetIdSet = false). "Owned" is the owner-account check of 2026-09-25 08:05 UTC. Live id 0 = our Part kit. "Recorded only" = a building field that never shows while the buildings stay our walk-in shells (rule 4).

| Item | Decision | Live id | Pending id | Owned | Gate |
|---|---|---|---|---|---|
| Ammo Works | waits on another job's file | – | – | Roblox (no Get) | BusinessService (streaming2-build): business dress hook |
| Arms Crate Line | waits on another job's file | – | – | Roblox (no Get) | BusinessService (streaming2-build): business dress hook |
| Armor Plate Press | waits on another job's file | – | – | yes | BusinessService (streaming2-build): business dress hook |
| Rocket Assembly | waits on another job's file | – | – | Roblox (no Get) | BusinessService (streaming2-build): business dress hook |
| Manual Dropper | waits on another job's file | – | – | yes | ManualDropperService (streaming2-build lane C1): dropper dress hook |
| Plot Oil Pump | owner pick, waits for promote | 13525922265 | 15192621369 | yes | ready, batch P1 |
| Oil Rig | kept our build | – | – | yes | [WEAK]; likely over 40 parts; our oil-rig kit is the gameplay platform |
| Money Collector | owner pick, waits for promote | 0 | 18220523228 | yes | ready, batch P1 |
| Training Yard | rejected | – | – | yes | wrong item: a group-training button board, not a military yard |
| Premium Pad | kept our build | – | – | no | you said no good match: keep our build |
| Supply Drop Crate | needs new code first | – | – | yes | needs one call in SupplyDropService (drop crate dress) |
| Supply Spinner | needs new code first | – | – | yes | not recommended: the spinner is a screen panel, not a world object |
| Command Center | owner pick, waits for promote | 0 | 43803492 | yes | your yes/no, batch P2 (recorded only) |
| Barracks | owner pick, waits for promote | 0 | 8637034739 | yes | ready, batch P1i (recorded only) |
| Vehicle Depot | owner pick, waits for promote | 12208876851 | 4005471827 | yes | Studio check, batch P2 (recorded only) |
| Weapons Facility | owner pick, waits for promote | 4120970784 | 11850705638 | yes | your yes/no, batch P2 (recorded only) |
| Helipad | owner pick, waits for promote | 14313845338 | 45369635 | yes | ready, batch P1i (recorded only) |
| Dock | owner pick, waits for promote | 17701461178 | 13183571527 | yes | Studio check, batch P2 (recorded only) |
| Airfield | needs new code first | – | – | yes | not recommended: the airfield builds its own runway |
| Runway | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Watchtowers | owner pick, waits for promote | 108525417345747 | 52154909 | yes | Studio check, batch P2 (recorded only) |
| Radar | owner pick, waits for promote | 9559610195 | 856258654 | yes | ready, batch P1i (recorded only) |
| Research Lab | rejected | – | – | yes | wrong item: a spiky sci-fi hull listed as a vehicle |
| Missile Defense | owner pick, waits for promote | 0 | 3461514733 | yes | ready, batch P1i (recorded only) |
| Power Station | owner pick, waits for promote | 14000967030 | 6869290892 | yes | ready, batch P1i (recorded only) |
| Warehouse | owner pick, waits for promote | 15942568272 | 8076230849 | yes | ready, batch P1i (recorded only) |
| Special Forces Facility | owner pick, waits for promote | 0 | 10112923897 | yes | ready, batch P1i (recorded only) |
| Empire Bank | rejected | – | – | yes | wrong item: this store 'bank' is a park bench |
| Home Outpost | waits on another job's file | – | – | Roblox (no Get) | MapSetup (streaming2-build): Home Outpost dress hook |
| Hangar | owner pick, waits for promote | 0 | 5343886540 | yes | your yes/no + Studio check, batch P2 (recorded only) |
| Bunker | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY); 43 parts, 3 wedges must be dropped |
| Tent | owner pick, waits for promote | 6883609157 | 182529039 | yes | ready, batch P1 |
| Market Stall | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Water Tower | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Clock Tower | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Adobe House | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Ruined House | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Town Block | rejected | – | – | Roblox (no Get) | too heavy for phones: pack buildings are 130-270 studs wide, two are over 40 parts |
| Checkpoint | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Radio Mast | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Gantry Crane | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Fuel Tank | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Flare Stack | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Radar Dome | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Crusher | rejected | – | – | yes | wrong item: a walled pit, not a crusher |
| Terminal | needs new code first | – | – | Roblox (no Get) | needs the world-model overlay job (W-OVERLAY) |
| Ammo Shed | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Fountain | rejected | – | – | Roblox (no Get) | 47 parts (over the 40-part cap), and it is a well |
| Defensive Walls | owner pick, waits for promote | 0 | 6980242709 | yes | Studio check, batch P2 |
| Defensive Walls L3 | owner pick, waits for promote | 0 | 8333853928 | yes | Studio check, batch P2 |
| Base Gate | needs new code first | – | – | yes | needs one call in StructureKitBuilder (gate arch dress) |
| Compound Wall | rejected | – | – | yes | wrong scale: a stone ring around a whole 512-stud baseplate |
| Wire Fence | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Sandbag Line | owner pick, waits for promote | 3525056989 | 15271872710 | yes | ready, batch P1 |
| Sandbag Nest | rejected | – | – | yes | wrong item: a lone WWII-style machine gun with no sandbags |
| Jersey | owner pick, waits for promote | 91071319 | 2766525411 | yes | ready, batch P1 |
| Revetment | rejected | – | – | Roblox (no Get) | no gain: one flat slab like our own kit; it would only use a load |
| Tank Trap | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Barbed Wire | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Hesco Barrier | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Military Jeep | wired (Roblox-owned) | 6418221666 | – | Roblox (no Get) | Roblox utility-vehicle body on the Field 4x4 (already live) |
| Armed Jeep | wired (Roblox-owned) | MilitaryJeep body | – | Roblox (no Get) | same body, our gun kept (already live) |
| Scout Car | wired (Roblox-owned) | MilitaryJeep body | – | Roblox (no Get) | same body (already live) |
| Dispatch Car | wired (Roblox-owned) | MilitaryJeep body | – | Roblox (no Get) | same body (already live) |
| Utility Quad | wired (Roblox-owned) | 6433272094 | – | Roblox (no Get) | Roblox dune-buggy body |
| Recon Buggy | wired (Roblox-owned) | 6433272094 | – | Roblox (no Get) | Roblox dune-buggy body |
| Patrol Truck | wired (Roblox-owned) | 6418225759 | – | Roblox (no Get) | Roblox pickup body |
| Escort Truck | wired (Roblox-owned) | 6418225759 | – | Roblox (no Get) | Roblox pickup body |
| Cargo Van | wired (Roblox-owned) | 6433316269 | – | Roblox (no Get) | Roblox van body |
| Premium Razorfang | waits on another job's file | – | – | Roblox (no Get) | VehicleConfig + VehicleService (streaming2-build): premium vehicle def |
| Armored Truck | owner pick, waits for promote | 0 | 8546141386 | yes | your yes/no + Studio check, batch P3 |
| Supply Truck | owner pick, waits for promote | 0 | 8546141386 | yes | your yes/no + Studio check, batch P3 |
| Ammo Carrier | owner pick, waits for promote | 0 | 8546141386 | yes | your yes/no + Studio check, batch P3 |
| Troop Transport | owner pick, waits for promote | 0 | 8546141386 | yes | your yes/no + Studio check, batch P3 |
| Recovery Truck | owner pick, waits for promote | 0 | 8546141386 | yes | your yes/no + Studio check, batch P3 |
| Anti Air Truck | owner pick, waits for promote | 0 | 8546141386 | yes | your yes/no + Studio check, batch P3 |
| Fuel Tanker | owner pick, waits for promote | 0 | 5318635087 | yes | Studio check, batch P3 |
| Engineering Truck | rejected | – | – | yes | cannot be checked: the only picture shows the inside of a block |
| Flatbed Hauler | owner pick, waits for promote | 0 | 8455894899 | yes | Studio check, batch P3 |
| Radar Truck | owner pick, waits for promote | 0 | 31538715 | yes | Studio check, batch P3 |
| Mine Clearer | rejected | – | – | yes | wrong item (a wheel loader) and unclear origin |
| Premium Bastion | waits on another job's file | – | – | yes | VehicleConfig + VehicleService (streaming2-build): premium vehicle def |
| APC | owner pick, waits for promote | 0 | 9076240315 | yes | Studio check, batch P3 |
| Infantry Carrier | owner pick, waits for promote | 0 | 9076240315 | yes | Studio check, batch P3 |
| Command Vehicle | owner pick, waits for promote | 0 | 9076240315 | yes | Studio check, batch P3 |
| Wheeled IFV | owner pick, waits for promote | 0 | 9076240315 | yes | Studio check, batch P3 |
| Amphibious APC | owner pick, waits for promote | 0 | 9076240315 | yes | Studio check, batch P3 |
| Combat IFV | owner pick, waits for promote | 0 | 11552687660 | yes | Studio check, batch P3 |
| Assault IFV | owner pick, waits for promote | 0 | 11552687660 | yes | Studio check, batch P3 |
| Flame Carrier | owner pick, waits for promote | 0 | 11552687660 | yes | Studio check, batch P3 |
| Bridge Layer | kept our build | 0 | – | yes | you said no good match: keep our build (it never borrows another tank's body) |
| Missile Truck | owner pick, waits for promote | 0 | 3304171953 | yes | Studio check, batch P3 |
| Rocket Artillery | owner pick, waits for promote | 0 | 3304171953 | yes | Studio check, batch P3 |
| Light Tank | kept our build | – | – | yes | [WEAK]; a green box tank, cruder than our tank kit (7 tanks would share it) |
| Medium Tank | kept our build | – | – | yes | [WEAK]; a green box tank, cruder than our tank kit (7 tanks would share it) |
| Heavy Tank | kept our build | – | – | yes | [WEAK]; a green box tank, cruder than our tank kit (7 tanks would share it) |
| Battle Tank | kept our build | – | – | yes | [WEAK]; a green box tank, cruder than our tank kit (7 tanks would share it) |
| Tank Destroyer | kept our build | – | – | yes | [WEAK]; a green box tank, cruder than our tank kit (7 tanks would share it) |
| Assault Gun | kept our build | – | – | yes | [WEAK]; a green box tank, cruder than our tank kit (7 tanks would share it) |
| Light Scout Tank | kept our build | – | – | yes | [WEAK]; a green box tank, cruder than our tank kit (7 tanks would share it) |
| Premium Warlord | kept our build | – | – | yes | [WEAK]; brick-built toy tank, far over 40 parts; paid slot |
| SPAAG | owner pick, waits for promote | 0 | 10069416832 | yes | Studio check, batch P3 |
| Mobile SAM | owner pick, waits for promote | 0 | 10069416832 | yes | Studio check, batch P3 |
| Mortar Carrier | kept our build | – | – | yes | [WEAK]; a tripod mortar with no vehicle |
| Mobile Artillery | kept our build | – | – | yes | [WEAK]; a crude block gun, worse than our kit |
| Howitzer Truck | kept our build | – | – | yes | [WEAK]; a crude block gun, worse than our kit |
| Siege Mortar | kept our build | – | – | yes | [WEAK]; a crude block gun, worse than our kit |
| Light Scout Heli | owner pick, waits for promote | 0 | 2474869838 | yes | Studio check, batch P3 |
| Utility Heli | owner pick, waits for promote | 0 | 2474869838 | yes | Studio check, batch P3 |
| Transport Heli | owner pick, waits for promote | 0 | 2627182035 | yes | your yes/no + Studio check, batch P3 |
| Heavy Lift Heli | owner pick, waits for promote | 0 | 2627182035 | yes | your yes/no + Studio check, batch P3 |
| Light Transport Heli | owner pick, waits for promote | 0 | 2627182035 | yes | your yes/no + Studio check, batch P3 |
| Gunship Heli | rejected | – | – | yes | copy of a game-franchise gunship (Half-Life 2) |
| Attack Helicopter | rejected | – | – | yes | copy of a game-franchise gunship (Half-Life 2) |
| Escort Heli | rejected | – | – | yes | copy of a game-franchise gunship (Half-Life 2) |
| Night Attack Heli | rejected | – | – | yes | copy of a game-franchise gunship (Half-Life 2) |
| Premium Stormwing | rejected | – | – | yes | copy of a game-franchise gunship (Half-Life 2) |
| Rescue Heli | owner pick, waits for promote | 0 | 11357157285 | yes | Studio check, batch P3 |
| Medevac Heli | owner pick, waits for promote | 0 | 11357157285 | yes | Studio check, batch P3 |
| VTOL Transport | rejected | – | – | yes | the uploader does not claim it ('Unknown Vtol'); looks ripped |
| Cargo Plane | rejected | – | – | yes | 47 parts (over 40) and a real cargo-plane look |
| AWACS Plane | rejected | – | – | yes | 47 parts (over 40) and a real cargo-plane look |
| Tanker Plane | rejected | – | – | yes | 47 parts (over 40) and a real cargo-plane look |
| Strike Jet | rejected | – | – | yes | copy of a real jet (F-16) |
| CAS Jet | rejected | – | – | yes | copy of a real jet (F-16) |
| Fighter Jet | owner pick, waits for promote | 0 | 3553891209 | yes | Studio check, batch P3 |
| Interceptor Jet | owner pick, waits for promote | 0 | 3553891209 | yes | Studio check, batch P3 |
| Trainer Jet | owner pick, waits for promote | 0 | 3553891209 | yes | Studio check, batch P3 |
| Light Fighter | owner pick, waits for promote | 0 | 3553891209 | yes | Studio check, batch P3 |
| Strike Bomber | rejected | – | – | yes | national-style roundel on the wing; made by someone else |
| Recon Plane | owner pick, waits for promote | 0 | 4954987035 | yes | your yes/no + Studio check, batch P3 |
| Patrol Boat | owner pick, waits for promote | 0 | 5177695483 | yes | Studio check, batch P3 |
| Fast Attack Craft | owner pick, waits for promote | 0 | 5177695483 | yes | Studio check, batch P3 |
| Coast Cutter | owner pick, waits for promote | 0 | 5177695483 | yes | Studio check, batch P3 |
| Torpedo Boat | owner pick, waits for promote | 0 | 5177695483 | yes | Studio check, batch P3 |
| Gunboat | owner pick, waits for promote | 0 | 15838664806 | yes | Studio check, batch P3 |
| Missile Boat | owner pick, waits for promote | 0 | 15838664806 | yes | Studio check, batch P3 |
| Mine Layer | owner pick, waits for promote | 0 | 15838664806 | yes | Studio check, batch P3 |
| Coastal Monitor | owner pick, waits for promote | 0 | 15838664806 | yes | Studio check, batch P3 |
| Landing Craft | rejected | – | – | yes | wrong item: a space lander |
| Assault Landing | rejected | – | – | yes | wrong item: a space lander |
| Amphib Assault | rejected | – | – | yes | wrong item: a space lander |
| Corvette | kept our build | – | – | yes | [WEAK]; a plain hull with no guns; our warship kit reads better |
| Destroyer | kept our build | – | – | yes | [WEAK]; a plain hull with no guns; our warship kit reads better |
| Frigate | kept our build | – | – | yes | [WEAK]; a plain hull with no guns; our warship kit reads better |
| Carrier Escort | kept our build | – | – | yes | [WEAK]; a plain hull with no guns; our warship kit reads better |
| River Boat | rejected | – | – | yes | wrong item (a theme-park raft) and made by someone else |
| Hover Transport | owner pick, waits for promote | 0 | 43773162 | yes | Studio check, batch P3 |
| Hospital Ship | rejected | – | – | yes | red-cross emblems and a copy of a named real ship |
| Supply Ship | owner pick, waits for promote | 0 | 11756438288 | yes | Studio check, batch P3 |
| Premium Tidebreaker | waits on another job's file | – | – | yes | VehicleConfig + VehicleService (streaming2-build): premium vehicle def, then a Studio look |
| Soldier | animated-rig job | – | – | Roblox (no Get) | needs the animated-rig job R-RIG (rule 9: animated rigs, not welded statues) |
| Infantry | animated-rig job | – | – | Roblox (no Get) | needs the animated-rig job R-RIG (rule 9: animated rigs, not welded statues) |
| Heavy Infantry | animated-rig job | – | – | yes | needs the animated-rig job R-RIG (rule 9: animated rigs, not welded statues) |
| Special Forces | rejected | – | – | yes | wrong item: a beret with a real regiment's badge |
| Worker | animated-rig job | – | – | yes | needs the animated-rig job R-RIG (rule 9: animated rigs, not welded statues) |
| Guard | animated-rig job | – | – | yes | needs the animated-rig job R-RIG (rule 9: animated rigs, not welded statues) |
| Gate Guard | animated-rig job | – | – | yes | needs the animated-rig job R-RIG (rule 9: animated rigs, not welded statues) |
| Oil Rig Guard | animated-rig job | – | – | Roblox (no Get) | needs the animated-rig job R-RIG (rule 9: animated rigs, not welded statues) |
| Fort Guard | animated-rig job | – | – | Roblox (no Get) | needs the animated-rig job R-RIG (rule 9: animated rigs, not welded statues) |
| Bank Guard | animated-rig job | – | – | yes | needs the animated-rig job R-RIG (rule 9: animated rigs, not welded statues) |
| Town Civilian | needs new code first | – | – | yes | needs a town civilian spawner plus the animated-rig job |
| Starter Rifle | wired (Roblox-owned) | 4842207161 (WeaponConfig) | – | Roblox (no Get) | Roblox rifle model in hand |
| Assault Rifle | wired (Roblox-owned) | 4842207161 (WeaponConfig) | – | Roblox (no Get) | Roblox rifle model in hand |
| SMG | wired (Roblox-owned) | 4842212980 (WeaponConfig) | – | Roblox (no Get) | Roblox SMG in hand |
| Pistol | wired (Roblox-owned) | 4842197274 (WeaponConfig) | – | Roblox (no Get) | Roblox pistol in hand |
| Shotgun | wired (Roblox-owned) | 4842215723 (WeaponConfig) | – | Roblox (no Get) | Roblox shotgun in hand |
| Sniper | wired (Roblox-owned) | 4842218829 (WeaponConfig) | – | Roblox (no Get) | Roblox sniper rifle in hand |
| Rocket Launcher | wired (Roblox-owned) | 4842186817 (WeaponConfig) | – | Roblox (no Get) | Roblox launcher in hand |
| Grenade | wired (Roblox-owned) | 232379763 (WeaponConfig) | – | Roblox (no Get) | Roblox grenade mesh in flight |
| Cruise Missile | wired (Roblox-owned) | 94690081 (WeaponConfig) | – | Roblox (no Get) | Roblox rocket mesh in flight (the rocket-launcher round) |
| Auto Gun | owner pick, waits for promote | 0 | 114570602 | yes | ready, batch P1 |
| Vehicle MG | waits on another job's file | – | – | yes | VehicleService (streaming2-build): turret dress hook |
| Vehicle Cannon | waits on another job's file | – | – | yes | VehicleService (streaming2-build): turret dress hook |
| Rocket Pods | kept our build | – | – | yes | [WEAK]; the asset is a whole car; our kit is the pod |
| Nuke | needs new code first | – | – | yes | needs a nuke-strike effect module (none exists) |
| Crate Stack | wired (Roblox-owned) | 6933790012 | – | Roblox (no Get) | Synty wooden crates (already live) |
| Military Crate | owner pick, waits for promote | 976333542 | 2930926216 | yes | ready, batch P1 |
| Ammo Box | rejected | – | – | yes | ripped from another game (Fallout 4), real ammo stencils |
| Oil Barrel | wired (Roblox-owned) | 23153991 | – | Roblox (no Get) | Roblox oil drum, smoke removed |
| Drum Group | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Fuel Cans | owner pick, waits for promote | 1160141839 | 112426091 | yes | ready, batch P1i (recorded only) |
| Container Stack | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Wreck | wired (Roblox-owned) | 6933556508 | – | Roblox (no Get) | Synty sedan as a dark burnt wreck |
| Plane Wreck | rejected | – | – | yes | made by someone else; 12,274 tris spread wide |
| Heli Wreck | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Barge Wreck | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Beached Hull | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Jetty Stub | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Street Lamp | needs new code first | – | – | Roblox (no Get) | needs the world-model overlay job (W-OVERLAY) |
| Floodlight | needs new code first | – | – | yes | needs a host outside the building-mesh switch, and 5 of its 6 lights removed |
| Flag Pole | owner pick, waits for promote | 1679839739 | 172755983 | yes | ready, batch P1i (recorded only) |
| Radio Antenna | owner pick, waits for promote | 19277831 | 1439808070 | yes | ready, batch P1i (recorded only) |
| Camo Net | needs new code first | – | – | yes | needs a camp host (W-OVERLAY) and a BuyPathStatic pin lifted |
| Poi Board | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Dir Sign | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Road Marker | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Bench | needs new code first | – | – | Roblox (no Get) | needs the world-model overlay job (W-OVERLAY) |
| Campfire | needs new code first | – | – | Roblox (no Get) | needs the world-model overlay job (W-OVERLAY) |
| Pipe Run | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Pave Tile | kept our build | – | – | no | you said no good match: keep our build |
| Palm | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Saguaro | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Barrel Cactus | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Joshua | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Dead Tree | wired (Roblox-owned) | 6933438443 | – | Roblox (no Get) | Synty dead tree |
| Stump | wired (Roblox-owned) | 6933438443 | – | Roblox (no Get) | Synty stump |
| Log | wired (Roblox-owned) | 6933438443 | – | Roblox (no Get) | Synty fallen log |
| Driftwood | wired (Roblox-owned) | 6933438443 | – | Roblox (no Get) | Synty twig as driftwood |
| Reeds | wired (Roblox-owned) | 6933438443 | – | Roblox (no Get) | Synty reeds |
| Dune Grass | wired (Roblox-owned) | 6933438443 | – | Roblox (no Get) | Synty dry plant |
| Desert Rock | needs new code first | – | – | Roblox (no Get) | not recommended: world rocks are terrain (0 parts) |
| Desert Mesa | needs new code first | – | – | Roblox (no Get) | needs a horizon host in MapSetup (another job's file) |
| Hold Pad | needs new code first | – | – | Roblox (no Get) | needs the world-model overlay job (W-OVERLAY) |
| Tutorial Arrow | owner pick, waits for promote | 1143305733 | 632958370 | yes | ready, batch P1 |
| Showroom Podium | rejected | – | – | yes | wrong item: a record player |
| Cash Pile | needs new code first | – | – | yes | needs a host; the bills must be stripped (real currency art) |

<!-- wire-asset-ids:end -->
