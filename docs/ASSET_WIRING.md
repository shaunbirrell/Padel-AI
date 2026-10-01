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
| Wired now: Roblox's own models, no Get Model needed | 31 |
| Your Get Model picks, waiting for the promote step | 43 |
| Kept our own build | 21 |
| Not used (wrong item, real-world copy, too heavy …) | 58 |
| Needs new game code first | 48 |
| Waits on a file another job is editing | 3 |
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
- **Walls level 4 and up:** the gate gun is your tripod gun pick 114570602 since the hooks batch below (our Part-built gun
  if it fails to load). The machine-gun model you listed for the sandbag nest is not used (it looks like a real WWII gun).

After each promote batch the lead adds that batch's phone checks here.

**First promote batch (2026-09-25, 7 of your picks):** each one shows your model, or our Part build if it fails to load.
- **Money Collector:** the ATM model sits on its pad at the right size; tapping it still collects.
- **Plot oil pumps:** your pumpjack model on every pump, not floating or sunk; golden pumps still turn gold.
- **Sandbag lines, road barriers, military crates, tents** (base yards, outposts, the Town): upright, on the ground, not
  giant or tiny. Road barriers also stand in for traffic cones and crates for pallets.
- **Tutorial arrow:** a new player's arrow points at the next step and is not sideways.

**Hooks batch (2026-09-25: the items that waited on another job's files):** each shows the model, or our Part build if
it fails to load. One check per line:
- Gate gun (walls 4+): tripod feet on the ground, barrel out of the gate.
- A second player (not in your clan) walks in: the gun turns barrel-first and shoots.
- The gun keeps turning for 30 seconds: it stays level, never tilts.
- Ammo Works / Arms Crate Line: the belt is a striped conveyor.
- Crates still ride the belt to the bin.
- Upgrade a belt business to level 5: still one belt, nothing floating.
- Rocket Assembly: a rocket lies on the roof, with no fire or smoke.
- Home Outpost (100 studs out of the gate): a round grey pad lies flat.
- Stand on the outpost pad: capture still works.
- The outpost flag and name label look as before.
- Graphics Quality 3: buy Ammo Works; the belt swaps with no gap.
- Walls 5, Graphics Quality 3: both gate guns turning at an enemy cause no stutter.
- Dropper plates and vehicle guns look as before (no change yet).

**Your model check (2026-09-25):** nothing new shows on screen. 12 of the 15 picks with more than 40 parts keep our
build, the Dock pick is recorded only (docks stay our Part build), and every other pick still waits (section 5).
- **Dock:** buy and upgrade the Dock at its kiosk. It still builds our Part dock, with no gap or floating piece.

**Your second check (2026-09-27, live place version 75):** two of your picks go live: the Recon Plane at Roblox size,
and the APC (with its 4 variants) at about half Roblox size, about as big as the Escort Truck. Each shows your model,
or our Part build if it fails to load. One check per line:
- Recon Plane (Airfield 1): an old wooden propeller plane, nose and propeller forward.
- Sit in it: the top of your head shows over the plane's body, just behind the wing.
- Parked, it stands on our small dark wheels (the model has none), about 1 stud off the runway.
- Take off, fly and land: it flies nose first and never sideways.
- APC (Vehicle Depot 3; also Infantry Carrier, Command Vehicle, Wheeled IFV, Amphibious APC): a green wedge APC,
  white lights at the front.
- Sit in the APC: you are hidden inside it. No head pokes through the roof, and no arm or foot shows through the
  sides or under it.
- A friend holds Ride and gets in; each of you jumps out and lands beside it.
- Drive the APC through your own gate at full stick: the barrier opens in time.
- Only if 2 friends own an APC, Infantry Carrier or Command Vehicle: each of you parks one by your garage, and the
  frame rate feels the same. (One player can have only one car out at a time, so this needs 3 players.)
- Fuel Tanker and Rescue / Medevac Heli: they look as before (those picks cannot be trimmed, section 5).

**Your raw v83 lines (2026-09-28): your jet goes live; the rescue helicopter cannot.** The Fighter Jet, Interceptor Jet,
Trainer Jet and Light Fighter show your pick 14589101870 at 2.5 times its size (about 44 studs long), or our Part jet if
it fails to load. One check per line:
- Airfield 3: a black and grey jet, nose forward, about 9 of you long, standing on three black wheels on grey legs.
- Sit in it: you are inside, hidden under the canopy. Nothing of you shows on top.
- Stay seated while a friend walks all the way round it and looks from the side and from low down by the nose, then
  sends you a screenshot: nothing of you shows.
- The camera sits behind the whole jet, not inside the tail.
- Park and jump out: you land on the ground beside a wing tip, not on top of the jet or inside it.
- Walk into it: only the middle of the jet is solid; you can walk through the wings and the tail.
- Take off: the tail never goes into the runway. Fly low and turn: no wing tip goes into the ground.
- Fly and land: it flies nose first and never sideways.
- Fire the gun: the shots start at the nose. Fire a missile: it leaves a wing tip.
- A friend shoots your parked jet in the tail and in a wing tip: it takes damage both times.
- Trainer Jet: your friend walks up to it, holds Ride and sits behind you. Get out and walk round it: nothing of your
  friend shows.
- Strike Jet, Close Air Support Jet and Stealth Strike: they keep our small jet (your pick replaced the old fighter
  pick, which never covered them). Say if they should wear your jet too.
- Rescue and Medevac Heli: they look as before (section 5).

## 2. Wired now (31)

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
| Ammo Works | Roblox conveyor belt as the line's belt (hooks batch) | your base (businesses) | Conveyor Belt, 41324890 |
| Arms Crate Line | the same conveyor belt (hooks batch) | your base (businesses) | Conveyor Belt, 41324890 |
| Rocket Assembly | Roblox rocket on the roof, fire and smoke removed (hooks batch) | your base (businesses) | Rocket, 31603741 |
| Home Outpost | Roblox capture pad on the outpost ring, its see-through beam dropped (hooks batch) | your Home Outpost | Capture Points, 80566030 |

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
| Vehicle Depot | [4005471827](https://create.roblox.com/store/asset/4005471827) | Military garage | TamasdztYT | yes | not used: 113 parts in your check (over 40) |
| Weapons Facility | [11850705638](https://create.roblox.com/store/asset/11850705638) | Armory | DISPLAYMODELS | yes | your yes/no (batch P2); recorded only |
| Helipad | [45369635](https://create.roblox.com/store/asset/45369635) | Helipad | sleitnick | yes | recorded (batch P1i); no change on screen |
| Dock | [13183571527](https://create.roblox.com/store/asset/13183571527) | boat dock | tihi2 | yes | recorded (2 parts in your check); no change on screen |
| Watchtowers | [52154909](https://create.roblox.com/store/asset/52154909) | guard tower | Morniratu | yes | not used: 135 parts in your check (over 40) |
| Radar | [856258654](https://create.roblox.com/store/asset/856258654) | Radar Station | VexHavoc | yes | recorded (batch P1i); no change on screen |
| Missile Defense | [3461514733](https://create.roblox.com/store/asset/3461514733) | Missile Launcher | cwd30 | yes | recorded (batch P1i); no change on screen |
| Power Station | [6869290892](https://create.roblox.com/store/asset/6869290892) | Power Station | bossmanjesus101 | yes | recorded (batch P1i); no change on screen |
| Warehouse | [8076230849](https://create.roblox.com/store/asset/8076230849) | Warehouse | sydneycrosby_875 | yes | recorded (batch P1i); no change on screen |
| Special Forces Facility [WEAK] | [10112923897](https://create.roblox.com/store/asset/10112923897) | Military defense outpost. | Roseaity | yes | recorded (batch P1i); no change on screen |
| Hangar | [5343886540](https://create.roblox.com/store/asset/5343886540) | plane hangar | Hyperalis | yes | not used: 871 parts in your check (over 40) |

**Walls (these do show: perimeter walls, level 3 and up)**

| Item(s) | Id | Store name | Creator | Owned | Next step |
|---|---|---|---|---|---|
| Defensive Walls | [6980242709](https://create.roblox.com/store/asset/6980242709) | Military Wall | SMehmetaga | yes | passed your check (20 parts); waits on a code fix (it would sit inside our wall), then the second check |
| Defensive Walls L3 | [8333853928](https://create.roblox.com/store/asset/8333853928) | T WALL | steveaut | yes | not used: 46 parts in your check (over 40) |

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
| Auto Gun | [114570602](https://create.roblox.com/store/asset/114570602) | Tripod Mounted Machine Gun | GuestCapone | yes | promoted in the hooks batch (its loader now refuses > 40 parts or a Humanoid; turned 90 degrees so the barrel leads) |

**Business press, dropper and vehicle guns (hooks batch P4: your first check is done, 2026-09-27; each waits on the P4 second check)**

| Item(s) | Id | Store name | Creator | Owned | Next step |
|---|---|---|---|---|---|
| Armor Plate Press | [4362642898](https://create.roblox.com/store/asset/4362642898) | Metal Factory (Press) | Ghosttony503 | yes | your check: 28 parts, 3 smoke effects. 28 parts cannot take over the 3 kit parts a press may replace, so the P4 second check names its parts: one piece of it, or new code |
| Manual Dropper | [14408455045](https://create.roblox.com/store/asset/14408455045) | Tycoon Dropper | tinghang77 | yes | your check: 14 parts. The P4 second check shows its glowing trim and how it stands; then it goes in after the dropper job |
| Vehicle MG | [5589684833](https://create.roblox.com/store/asset/5589684833) | Mounted Machine Gun | ifyouaremethaniamyou | yes | your check: 1 part, 4.5 long. The P4 second check shows which end is the barrel |
| Vehicle Cannon | [3322196012](https://create.roblox.com/store/asset/3322196012) | Tank Turret | Nierse217 | yes | your check: 1 part, 13.6 tall and 3.6 wide. The P4 second check shows which way the barrel points |

**Vehicles (your check is done; the model is dress only, our kit still drives)**

| Item(s) | Id | Store name | Creator | Owned | Next step |
|---|---|---|---|---|---|
| Armored Truck, Supply Truck, Ammo Carrier, Troop Transport, Recovery Truck, Anti Air Truck | [8546141386](https://create.roblox.com/store/asset/8546141386) | Military Truck | LouBrawlerStars | yes | your yes is on record (call 2); held, not usable as it is: its paint carries military unit markings, and its shape and paint were uploaded by another user (Karcist), not by the seller. Keep our truck, or pick another? (section 5) |
| Fuel Tanker | [5318635087](https://create.roblox.com/store/asset/5318635087) | fuel truck | asp307 | yes | not used: 55 parts, every one named "Part", so none can be left out by name (second check) |
| Flatbed Hauler | [8455894899](https://create.roblox.com/store/asset/8455894899) | FlatBed Truck | YourBoi_JonnyBoi | yes | 11 small parts can go (40 left), but its cab would sit ahead of our kit's nose: waits on a longer kit |
| Radar Truck | [31538715](https://create.roblox.com/store/asset/31538715) | RMAR truck radar | Armour_Fox | yes | not used: 93 parts in your check (over 40) |
| APC, Infantry Carrier, Command Vehicle, Wheeled IFV, Amphibious APC | [9076240315](https://create.roblox.com/store/asset/9076240315) | APC | CorzCringe | yes | promoted 2026-09-27: front at -Z, 0.55 of Roblox size, seats inside the hull (section 1) |
| Combat IFV, Assault IFV, Flame Carrier | [11552687660](https://create.roblox.com/store/asset/11552687660) | Fiction IFV | spookstiy | yes | not used: 321 parts in your check (over 40) |
| Missile Truck, Rocket Artillery | [3304171953](https://create.roblox.com/store/asset/3304171953) | missile truck | KlassicKanadian | yes | not used: 219 parts in your check (over 40) |
| SPAAG, Mobile SAM [WEAK] | [10069416832](https://create.roblox.com/store/asset/10069416832) | anti aircraft Tank | XCX1001 | yes | not used: 301 parts in your check (over 40) |
| Light Scout Heli, Utility Heli | [2474869838](https://create.roblox.com/store/asset/2474869838) | Low poly helicopter | Azarth | yes | second check: nose at -Z (from its thumbnail camera, not 90 degrees); one mesh with no seats, so a look first |
| Transport Heli, Heavy Lift Heli, Light Transport Heli | [2627182035](https://create.roblox.com/store/asset/2627182035) | transport helicopter | blokkere | yes | not used: 109 parts in your check (over 40) |
| Rescue Heli, Medevac Heli | [11357157285](https://create.roblox.com/store/asset/11357157285) (your 11357398877 is the same model; one load for both) | Rescue Helicopter | KiboSprite | yes | not used: 78 parts, named only "Part" and "Wedge", so no trim keeps the body (second check); your new pick 9120014090 is not used either: another creator made its rotor meshes (section 5) |
| Fighter Jet, Interceptor Jet, Trainer Jet, Light Fighter | [3553891209](https://create.roblox.com/store/asset/3553891209) | Fighter Jet concept | PlanesFun56 | yes | not used: you picked another (2026-09-28); its paint is another artist's signed drawing of a real aircraft concept. Your new pick 14589101870 is live (section 5) |
| Recon Plane | [4954987035](https://create.roblox.com/store/asset/4954987035) | Old propeller plane | Deadex40_Extra | yes | promoted 2026-09-27 (your yes, call 4): nose at -X (Yaw -90), Roblox size (section 1) |
| Patrol Boat, Fast Attack Craft, Coast Cutter, Torpedo Boat | [5177695483](https://create.roblox.com/store/asset/5177695483) | Patrol Boat | pirateparty1234 | yes | not used: 114 parts in your check (over 40) |
| Gunboat, Missile Boat, Mine Layer, Coastal Monitor | [15838664806](https://create.roblox.com/store/asset/15838664806) | Basic Gunboat | Confused Giants Studio (group) | yes | second check: the 2,048-stud part is the hull itself (MainHull); the game cannot shrink it that far yet (a code change) |
| Hover Transport | [43773162](https://create.roblox.com/store/asset/43773162) | HoverCraft | Fractality | yes | not used: 211 parts in your check (over 40) |
| Supply Ship | [11756438288](https://create.roblox.com/store/asset/11756438288) | Cargo Ship | Yorsiur | yes | not used: 174 parts in your check (over 40) |

**No Get Model needed for Roblox's own items** (28 ids): 23153972, 23153991, 23154052, 31603741, 41324890, 56446217, 56447829, 56449028, 80566030, 94690081, 123041248, 187790284, 232379763, 4842186817, 4842197274, 4842207161, 4842212980, 4842215723, 4842218829, 6418221666, 6418225759, 6418277837, 6433272094, 6433316269, 6433323089, 6933438443, 6933556508, 6933790012.

## 4. Your yes / no (12 calls; 3 and 7 are no longer needed)

Reply with the number and yes or no. Nothing below changes the game until you answer and the lead promotes it.

1. Roblox's own Auto Rifle and Rocket Launcher have AK-style and RPG-style shapes (unnamed Roblox models). They are wired now because you listed them; say no and they go back to our kit guns (one-line change).
2. Military Truck 8546141386 for 6 trucks (Armored, Supply, Ammo, Troop, Recovery, Anti-Air): it reads like a US M35-style 6x6 and is more realistic than the rest of the world. Yes or no?
   **Answered 2026-09-27: yes.** Held, not usable as it is: its paint carries military unit markings, and its shape
   and paint were uploaded by another user (Karcist), not by the store seller (section 5). Keep our truck, or pick another?
3. ~~Transport helicopter 2627182035 for the transport helis: a two-rotor layout like a CH-47. Yes or no?~~ No longer needed: your check found 109 parts (over 40), so it is not used.
4. Recon Plane 4954987035 looks like a wooden toy plane (our kit may look better). Yes or no?
   **Answered 2026-09-27: yes.** Promoted (section 1).
5. Command Center 43803492 was made for another Roblox game ("Conquerors") and is plainer than our building. Yes or no? (It only shows if buildings ever use store models.)
6. Weapons Facility 11850705638 says it is "crim inspired" and has a glowing "ARMORY 1" sign. Yes or no? (same note as 5)
7. ~~Hangar 5343886540: its store description was removed by Roblox moderation. Yes or no? (same note as 5)~~ No longer needed: your check found 871 parts (over 40), so it is not used.
8. Guards: one Roblox soldier model (187790284) for every military guard, as your rule 9 says, or the separate guard models you listed per row?
9. Worker 893013681: its sleeve reads "ROCKPORT … DEPARTMENT OF TRANSPORTATION" and the author asks for credit. Keep it (we credit the author) or use the Roblox soldier?
10. Helicopter wreck 4533405525 looks like a Black Hawk; the cash pile 11760036257 shows US dollar bills (we would strip the bills). Yes or no for each?
11. Premium Razorfang as Roblox's red sports car (a civilian supercar in a paid military slot), and Premium Tidebreaker as a speedboat on a road trailer (origin unclear). Yes or no for each?
12. **Store models: load them while the game runs (A), or bake them into the place after every publish (B)?** You
    asked about baking. Both are allowed; only model files in our public GitHub repo, or re-uploading someone else's
    model, are not. The fighter jet 3553891209 waits on this answer; nothing else in this change loads a new model.
    - **A. Load by id while the game runs.** Your 7 first-batch picks and the tripod gate gun already work this way,
      with our Part build if a load fails. Roblox lets a game load a model that the game's creator owns. That is you,
      you own all 24, and your check ran on a real Roblox server of this place, so live servers should load them the
      same way. The one-line `WE_LIVE` check (section 5) shows it on a live server in about 2 minutes. Cost: one load
      per model on each server (inside the 64-load budget, section 8); nothing to redo after a publish.
    - **B. Bake after every publish.** A script run through Open Cloud Luau Execution (the way you ran your check)
      loads the models into the place's ServerStorage and saves the place (`SavePlaceAsync`). Everything stays inside
      Roblox. **What the save holds:** Roblox's Open Cloud docs say a Luau Execution task runs against one place version,
      with no physics, and the place's own server and local scripts do not run. So `SavePlaceAsync` from the bake saves
      the published place plus the models the bake adds; nothing our start-up scripts build goes into it. Gains: servers
      that start after a bake load no store models while the game runs (a quicker start, no load budget used, no failed
      loads). Costs:
      - **A place setting that lets scripts overwrite the place.** Creator Hub › the place › **Permissions** ›
        "Allow place to be updated using Save Place API" must be on. While it is on, any server script in the live
        game can save over the place. It is not "Allow Loading Third Party Assets", which stays **OFF**.
      - Your publish bot must run it after **every** publish, on the version it just published: a publish replaces the
        place, so the baked models are gone until the bake runs again, and a bake of an older version would save that
        older version over the new one. Servers that start before the bake finishes still load by id (the A way). Each
        bake adds a place version, and a Team Create session in Studio blocks it.
      - Our loader needs a code change to use the baked copies first. The live place then differs from the build our
        tests check, and our tests cannot see the baked models.
      - We would prove it on a separate test place (the setting, the save, the loader change) before the live one.
    - **Our recommendation: A.** Switch to **B** only if `WE_LIVE` ever shows a `FAIL` on a live server, and only after
      the bake is proven on a test place. Reply A or B.
    - **Answered 2026-09-27: A** (keep loading by id). The fighter jet no longer waits on this call, and your "jet look
      OK" is on record; it now waits on your decision about its paint (section 5).

## 5. Studio check (for you or Grok)

Some models cannot be looked inside from outside Roblox, so before they go live someone runs the check script in Studio.
Use the script in `docs/ASSET_SHORTLIST.md` section 5, step 5 (open the live place from the Creator Dashboard, press
Run, paste the script with the list below, copy every line that starts with `WE_CHECK`). Paste the `WE_CHECK` lines back
to the lead. A model passes with `parts` 40 or less and `humanoids=0`; for vehicles the `size` tells the tool which way the
model faces.

- **Batch P4 (business press, dropper, vehicle guns):** 3322196012, 4362642898 (also name the see-through bounds box
  part), 5589684833, 14408455045
- **Batch P2 (walls and buildings):** 52154909, 4005471827, 5343886540, 6980242709, 8333853928, 13183571527
- **Batch P3 (vehicles):** 31538715, 43773162, 2474869838, 2627182035, 3304171953, 3553891209, 4954987035, 5177695483, 5318635087, 8455894899, 8546141386, 9076240315, 10069416832, 11357157285, 11552687660, 11756438288, 15838664806

**Done for batches P2 and P3, 2026-09-25: thank you.** (Batch P4: done 2026-09-27, 4 of 4 loaded, all at 28 parts or fewer.) You ran it through Open Cloud Luau
Execution in the live place (version 75) as your own account, and all 24 models loaded. What it showed:
- **15 have more than 40 parts. These 12 are not used** (section 6.1): 52154909, 4005471827, 5343886540, 8333853928,
  31538715, 43773162, 2627182035, 3304171953, 5177695483, 10069416832, 11552687660, 11756438288. Those items keep our
  build. The guard tower 52154909 also has 19 scripts and 20 fire and smoke effects; our loader removes scripts, but
  135 parts would still be over 40.
- **Dock 13183571527 (2 parts) is recorded.** It shows only if buildings ever use store models (your rule 4), so nothing
  changes on screen.
- **Passed, but not live yet** (the stand-in notes below come from our test build, not from Roblox):
  - Fighter jet 3553891209 (25 parts): waits on your call 12. Its wing layout looks like a real fighter family (it has
    no markings); say so if you would rather keep our kit jet.
  - Defensive walls 6980242709 (20 parts): the only place the game uses it (walls level 3 and up) shrinks it and then
    leaves it inside our wall, where nobody sees it. It needs a code fix in the model loader first, then the second check.
  - Light helicopters 2474869838 (1 part): the second check shows which way its nose points.
  - APC 9076240315 (12 parts): in our test build the driver sits above its roof, so it needs a seat fix and the second check.
  - Gunboat 15838664806 (3 parts, 2,048 studs long): we cannot tell yet whether the long part is the boat or water;
    the second check shows it. The game also cannot shrink a model that much yet (a code change).
  - Military truck 8546141386 and recon plane 4954987035: your yes/no (calls 2 and 4) and the second check.
- **The other 3 are close:** fuel truck 5318635087 (55 parts), flatbed 8455894899 (53) and rescue helicopter 11357157285 (78).
  Our loader can leave out small parts by name, so the second check lists their parts. The lead then decides which
  small parts go (never wheels, rotors or the hull), or keeps our build.

**Next checks** (you can run both yourself; send back every line they print):
1. **`WE_LIVE`** (for call 12): join the live game, open the Developer Console (F9, or type `/console` in chat), switch
   to **Server**, paste the one line from `docs/ASSET_SHORTLIST.md` section 5, step 5c into the command bar and wait for
   `WE_LIVE DONE`. 19 `WE_LIVE OK` lines mean live servers load these models. It adds nothing to the game.
2. **Second check** (`WE_CHECK2`, step 5b): run the script `tools/WeCheck2.luau` the same way as your first check
   (Open Cloud Luau Execution on the live place). It looks at the 11 models above that still wait, deletes its copies
   and changes nothing in the game. Send back every line that starts with `WE_CHECK2` (the last one says `DONE`).

**Second check done, 2026-09-27: thank you** (Open Cloud, live place version 75, 11 of 11 loaded; `tools/parse_we_check2.py
--strict`: 0 problems). What it showed (the stand-in notes come from models rebuilt from your lines, not from Roblox):
- **Recon plane 4954987035: promoted.** Nose at -X (its propeller and ball nose; fin and tail plane at +X), so Yaw -90.
  Its fuselage is a round Part 3.88 across in a box 11.26 tall: our loader fitted the box, which would have floated the
  plane about 3.7 studs; it now fits what Roblox draws (a small VisualAssetService change, only round Parts are affected).
- **APC 9076240315: promoted.** Front at -Z (white lights, grey plate), Yaw 0. One hull mesh with no seats, so the seats
  are placed by eye inside it. The hull's box top is its cupola; the flat roof is lower, where the cupola's blue band
  starts (10.12 of 12.43). At 0.55 of Roblox size a seated head is 0.66 under that roof and the feet stay inside the
  hull (your phone check).
- **Fighter jet 3553891209: held, your decision.** Its paint (texture 3553780601) is another artist's signed three-view
  drawing of a real aircraft concept, with the concept's name on it. Our rules keep real-world names and other people's
  artwork out. Keep our jet, or pick another?
- **Military truck 8546141386: held, not usable as it is.** Its paint (texture 7853120648, from Roblox's own picture of
  it) carries stencilled military unit codes on both bumpers and a shield emblem with an animal on the cab door; our rules
  keep military markings out. Its shape (mesh 7853120516) and paint were uploaded by the user Karcist; the seller
  LouBrawlerStars republished them without credit. Its long cab-forward body would also put the driver behind the cab.
  Keep our truck, or pick another?
- **Light helicopter 2474869838: a look first.** Its thumbnail camera, which the check reported, shows the skids along Z
  with the tail at +Z: the nose is at -Z (Yaw 0), not 90. It is one mesh with no seats, so the cabin seats would be
  placed by eye.
- **Flatbed 8455894899: trim found, held.** Leaving out FrontForceField, VehicleSeatBack, ExhaustPipe, the four brake
  lights, the two headlights and both bumpers keeps 40 parts (checked with our loader on the rebuilt model). But at
  full size its cab sits 7.8 studs ahead of the body centre, past our 10.45-stud kit's nose, where the car-size job keeps
  no seat, so the driver would sit behind the cab. The grille decal (58264306, Roblox's "Car Grill2") shows the
  Roblox R logo and is dropped with the other decals.
- **Fuel tanker 5318635087 and rescue heli 11357157285: not used.** Every part is named "Part" (tanker) or "Part" /
  "Wedge" (heli), so no part can be left out by name without losing the body.
- **Gunboat 15838664806: held.** The 2,048-stud part is MainHull, the boat itself (the whole model is built about 146x
  Roblox size); leaving it out leaves no boat. Our fit cannot shrink below x0.05 yet (a code change). Its gun sits at +X
  and its radio mast at -X, so the bow may be +X, not -X as the store picture suggested: a look first.
- **Walls 6980242709: held** (three MilitaryWall1 pieces along Z, 20 parts): still waits on the wall-fit fix.
- **Dock 13183571527:** its texture 319943163 is a plain nailed-wood image ("Wood_Nailed"), no logo. Still recorded only.

**P4 second check (next):** the lead sends you `WeCheck2_P4.luau`, a copy of `tools/WeCheck2.luau` with only the 4 P4
ids. Run it the same way and send back every `WE_CHECK2` line. It names the press's parts (its see-through box), and
shows which way the two guns point and the dropper's glowing trim.

**Your replacement picks, air (picture one, 2026-09-28): your raw v83 lines arrived; the jet goes live.** Thank you:
your lines gave every part's box, so nothing was guessed. Every mesh and paint id in them was looked up on Roblox's store
(who uploaded it).

| Item | Your pick | Your bot's backup | Also in your picture | Result |
|---|---|---|---|---|
| Fighter Jet, Interceptor Jet, Trainer Jet, Light Fighter | [14589101870](https://create.roblox.com/store/asset/14589101870) Basic Fighter jet (Alecose1) | none under 40 parts | [15024427757](https://create.roblox.com/store/asset/15024427757) Jet Fighter and [16967628140](https://create.roblox.com/store/asset/16967628140) Oceaniet Stealth Fighter (BSPMC2271): not used, 107 and 254 parts in your check (over 40) | **Live (promoted 2026-09-28).** 8 parts, all 8 meshes uploaded by the seller himself, no paint images, no scripts, 11,460 triangles (under the 20,000 phone cap). Nose along +Z in your lines, so it is turned to face forward. At 2.5 times its size: 44 long, 29 wide, 12 tall, on drawn landing gear. The pilot sits inside, under the canopy; the gun fires from the nose and missiles leave the wing-tip missiles; shots hit the whole jet you see. Its outline is close to a well-known real single-engine fighter. We turned down an earlier Strike Jet pick (14451400891) as a copy of a real jet; that one was a detailed, painted replica, while this one is a plain low-poly black jet with no names, marks or paint. Say if you would rather not use it |
| Rescue Heli, Medevac Heli | [9120014090](https://create.roblox.com/store/asset/9120014090) Medical Helicopter (TripleTripleTwinTips) | [10077899617](https://create.roblox.com/store/asset/10077899617) War's Helicopter (SarahNeedle_mouse): cannot be used either: none of its 13 mesh and paint files were uploaded by the seller (four other creators made them), and its store text says it is another version of someone else's model | [1577255368](https://create.roblox.com/store/asset/1577255368) Search and rescue helicopter (KiloOfficial): your bot rejected it (a copy of a real helicopter) | **Not used.** All 7 of its rotor parts use meshes and paint uploaded by another creator (JaimeEsP, March 2020), five months before the seller's account was made, and that creator never put them on the store. So the model is not the seller's own work (the same rule that dropped the truck). It was also heavy for phones (65,837 triangles, over 3 times the cap). Our helicopter stays. **We need a new pick from you:** a helicopter made by its uploader, 35 parts or fewer |

The old jet 3553891209 and the old rescue helicopter 11357157285 are dropped for good; neither was ever shown in the
game. Your bot's backup 10077899617 and the picture's 1577255368 stay unused: both fail the same rule. The Strike Jet,
Close Air Support Jet and Stealth Strike keep our small jet: your jet pick took the old fighter pick's place, and that
pick never covered them. Say if they should wear your jet too.

## 6. Not wired, and why

### 6.1 Not used (58)

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
| Watchtowers | 52154909 | 135 parts in your check (over 40), with 19 scripts and 20 fire / smoke effects; removing those would not fix the part count |
| Vehicle Depot | 4005471827 | 113 parts in your check (over 40) and 12 lights |
| Hangar | 5343886540 | 871 parts in your check (over 40) |
| Defensive Walls L3 | 8333853928 | 46 parts in your check (over 40); wall models cannot leave parts out |
| Radar Truck | 31538715 | 93 parts in your check (over 40) |
| Combat IFV | 11552687660 | 321 parts in your check (over 40) |
| Assault IFV | 11552687660 | 321 parts in your check (over 40) |
| Flame Carrier | 11552687660 | 321 parts in your check (over 40) |
| Missile Truck | 3304171953 | 219 parts in your check (over 40) |
| Rocket Artillery | 3304171953 | 219 parts in your check (over 40) |
| SPAAG | 10069416832 | 301 parts in your check (over 40) |
| Mobile SAM | 10069416832 | 301 parts in your check (over 40) |
| Transport Heli | 2627182035 | 109 parts in your check (over 40) |
| Heavy Lift Heli | 2627182035 | 109 parts in your check (over 40) |
| Light Transport Heli | 2627182035 | 109 parts in your check (over 40) |
| Patrol Boat | 5177695483 | 114 parts in your check (over 40), and only 7 studs long |
| Fast Attack Craft | 5177695483 | 114 parts in your check (over 40), and only 7 studs long |
| Coast Cutter | 5177695483 | 114 parts in your check (over 40), and only 7 studs long |
| Torpedo Boat | 5177695483 | 114 parts in your check (over 40), and only 7 studs long |
| Hover Transport | 43773162 | 211 parts in your check (over 40) |
| Supply Ship | 11756438288 | 174 parts in your check (over 40) |
| Fuel Tanker | 5318635087 | 55 parts in your check (over 40); all named "Part", so none can be left out |
| Rescue Heli | 11357157285 | 78 parts in your check (over 40); only "Part" and "Wedge" names, no trim keeps the body |
| Medevac Heli | 11357157285 | the same model as the Rescue Heli (78 parts) |
| Rescue Heli (new pick) | 9120014090 | origin: its rotor meshes and their paint were uploaded by another creator, before the seller's account existed |
| Medevac Heli (new pick) | 9120014090 | the same model as the Rescue Heli pick |

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

### 6.4 Waiting on another job (3)

These need a change in a file that another job is editing. The exact change is written down and is made when that job
lands. (The business lines, the Home Outposts, the dropper and the vehicle guns got their hooks on 2026-09-25: see
sections 2 and 3.)

| Item | Id | Waits on |
|---|---|---|
| Premium Razorfang | 6433323089 | VehicleConfig + VehicleService: premium vehicle def (your yes / no, call 11) |
| Premium Bastion | 16835152672 | VehicleConfig + VehicleService: premium vehicle def |
| Premium Tidebreaker | 4128350737 | VehicleConfig + VehicleService: premium vehicle def, then a Studio look |

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
| Conveyor belt (Roblox) | the one belt part and its stripes, stretched to our belt | its script and settings; it stands in for our belt part, so the business part count stays 16 |
| Rocket (Roblox) | the rocket mesh part, laid on the roof and scaled to our rocket body | the fire, the smoke and the empty effects part; it stands in for our rocket body part |
| Capture Points (Roblox) | the round pad, 4 parts, flat on the outpost ring | its 2 scripts and settings; the see-through beam part and the hidden highlight part are dropped; the ring, flag and label stay ours |
| Tripod gun (your pick 114570602) | the whole gun, 31 parts, turned 90 degrees so the barrel leads, tripod feet on the ground; one anchored aim part, the rest welded to it, so a turn moves one part | its 62 build-tool setting values (no scripts in it); more than 40 parts or a Humanoid would be refused. Our marker ring and the sandbags sit on the ground too |
| Synty pieces (log, twig, sedan, and the trees, stumps, reeds, grass and crates already live) | one mesh each, recoloured to the desert palette | texture cleared; the sedan is recoloured as a burnt wreck and turned 90°, the twig is turned 90° as driftwood |
| Every store model (now and at promote) | the look | scripts, seats, joints, prompts, sounds and movers; glowing parts become plastic on pack pieces; more than 40 parts or any Humanoid → refused, our kit stays |
| Waiting picks | – | vehicles and vehicle guns are dress only while our kit drives; the press must fit the business part budget; the Studio check decides the rest |

## 8. Load budget (why promotes go in batches)

Each server may try at most 64 model loads (48 before the hooks batch; a failed one still counts). Retries of failed
loads stop at 40, so the last 24 are kept for first loads after boot (your base, vehicles, guards, effects, vehicle guns)
even while Roblox's asset service is down. Today's config asks for about 25 different models on a healthy server (22
before the hooks batch: the conveyor belt, rocket and capture pad added 3), and in a full outage 8 models are first asked
after boot (estimates from the headless census and the promote tool's count, not measured in Roblox).

The promote tool refuses a batch that would pass 56 models on a healthy server, or that would ask for more than 24 models
after boot in an outage (every fallback in a chain counts there). Your check took 8 of the 17 vehicle models and the
level-3 wall out (over 40 parts). The tool's count on a copy of the config with each remaining batch promoted: P4
(press, dropper, two vehicle guns) adds 4 (25 → 29 healthy, 8 → 12 after boot), the P2 wall adds 1, and the 9 vehicle
models left in P3 add 9 (the fighter jet on its own: 1). All of them together: 39 of 56, and 22 of the 24 after-boot
loads, so the tool would take every batch. **The census holds one fewer after boot.** In the headless census of that
copy (the press set up the way its promote requires, with `ReplacesRoles` and `OmitParts`, so it loads with the plot) a
healthy server asks for 39 models, as the tool counts. In a full outage boot uses 43 of the 64 attempts (retries stop at
40, but boot's own first loads run on), which leaves 21 for first loads after boot, not 24, and the census refuses 1
live load (the warzone floodlight, in the LATER phase). P4 and P3 without the wall (21) fill it exactly, with none
refused. So **before the last of the three batches** (the one that brings the count to 22) the lead frees at least one
slot, or raises the reserve on purpose (for example 65 / 25, retries still stopping at 40) after a census_fail run shows
no refused load. The planned clean-up (a crate model that never loads and two effect models that never load, config
only) is the first way: its two effect models (MoneyBagFX, VfxSparkles) set to 0 alone bring the tool's count to 20 and
leave the census one attempt spare. Any batch that takes the after-boot count past 21 needs a census_fail run first (the
tool may admit up to 3 more late loads than the census holds, ASSUMPTIONS AW-L4). Guns, the gate gun and the grenade
and rocket meshes do not count against the 64.

**After the second check (wc3, 2026-09-27).** The recon plane and the APC add 2 models (25 → 27 on a healthy server, 8 → 10
first asked after boot in an outage). In the headless census a full outage now uses 51 of the 64 attempts by the end of
the LATER phase (49 before), none refused. The fuel tanker and the rescue heli are out (2 models fewer), so with every pick that still
waits promoted (the recon plane and the APC, the four P4 models, the wall, the jet, truck, heli, gunboat and flatbed) the
tool counts 37 of 56 and 19 of the 24 after-boot loads, and the census of that copy uses 58 of the 64 attempts in a full
outage by the end of LATER, none refused (33 models on a healthy server). Every batch left fits; nothing has to be freed
first. (Headless census and the tool's count, not measured in Roblox.)

## 9. For the lead: the promote tool

`tools/wire-asset-ids.py` (Python 3, standard library only). It never runs git and never edits StructureVisualConfig
(PreferMeshWhenAssetIdSet stays false).

```
python3 tools/wire-asset-ids.py status                 # every item: decision, live id, pending id, gate, load budget
python3 tools/wire-asset-ids.py pending                # the PendingAssetId values in the config, verified or not
python3 tools/wire-asset-ids.py check --store          # inventory + store re-check of every pending id (cached, <= 2 req/s)
python3 tools/wire-asset-ids.py promote --batch P1 --dry-run   # print the diff, write nothing
python3 tools/wire-asset-ids.py promote --batch P1             # edit, then luau-compile + BuyPathStatic (no new FAIL) or restore
python3 tools/wire-asset-ids.py promote --batch P3 --we-check we_check.txt --owner-ok 8546141386,4954987035
python3 tools/wire-asset-ids.py demote 182529039       # undo one promotion (journal: docs/asset_wiring.json)
python3 tools/wire-asset-ids.py reject --all --we-check we_check.txt   # REJECT rows the check refused: PendingAssetId out
python3 tools/wire-asset-ids.py render [--check]       # the status table at the end of this page
```

- **Undo the tripod gun (114570602):** `demote 114570602` on its own is refused, because the hooks batch added
  `Yaw = 90, ` to its config line. Steps:
  1. In `VisualAssetConfig.GateDefense.AutoGun` delete `Yaw = 90, ` (the line then matches the promote journal).
  2. In `tools/BuyPathStatic.py` (hooks block) delete the pin `AutoGun = { ModelAssetId = 114570602, Yaw = 90,`, the
     provenance pin `part names credit co-builders sk3let0n …`, and `"114570602"` from the `_hk_id` licence-row tuple.
  3. Run `python3 tools/wire-asset-ids.py demote 114570602` (it restores the pending line, the id pin and the licence row).
  4. By hand: the 3-line Yaw comment above the AutoGun ref, the gate-gun lines in sections 1 and 7, and ASSUMPTIONS AW-H3,
     AW-H4 and AW-H13. The GateDefense loader rules, grounding and welds stay (they also serve the Part-built gun).
- **Undo another hooks-batch item (config only, plus the BuyPathStatic hooks-block line that pins it):**
  - a business line: `Businesses.<Id>.ModelAssetId = 0` and delete its pin (`AmmoWorks = { ModelAssetId = 41324890, …`,
    `ArmsCrateLine = { ModelAssetId = 41324890, …` or `RocketAssembly = { ModelAssetId = 31603741, …`);
  - the Home Outpost pad: `Landmarks.HomeOutpost.ModelAssetId = 0` and delete the pin `HomeOutpost = { ModelAssetId =
    80566030, …`;
  - the load budget back to 48 / 12: the two fix57 pins and the `(= 56)` pin (hooks/bps_inplace.txt lists the old text).
  ASSUMPTIONS AW-H14 has the full list.

- **Batches:** P1 = 8 ids with no gate that show on live (tripod gun, tent, tutorial arrow, road barrier, crates, plot pump,
  sandbags, ATM; the tripod gun went live in the hooks batch). P4 = the hooks batch picks (press, dropper, vehicle MG,
  vehicle cannon): Studio check each; the press also needs `OmitParts` in its config ref first (flag OMIT) and its
  `ReplacesRoles` set so it fits the business part budget; a vehicle gun's `Yaw` is set by hand (the tool sets Yaw only
  on vehicle bodies). P1i = 10 ids recorded in fields that stay hidden (no change on screen). P2 = walls (they show) and the
  buildings that need a yes/no or the Studio check. P3 = the vehicle models: 9 of the 17 are left after the owner's check
  (2 need a yes/no), every one of them on `HOLD` (section 5). Whichever of P2, P3 and P4 goes in last needs one load
  slot freed first (section 8).
- **What one promote writes:** `ModelAssetId = <id>` in every config line of that id (vehicles also get `Fit`, `Yaw`,
  `HideKit`, `StripDecals`), the `PendingAssetId` removed, a new `Note`; any BuyPathStatic needle that pinned the old id
  rewritten to the new id; the `docs/ASSET_LICENSES.md` §3.1 row (and a replaced id's §3 row moved to §2e when it leaves
  `src/`); this page's status table; and the undo journal `docs/asset_wiring.json`. Commit them together.
- **Refusals:** unknown keys or ids, any decision other than a waiting pick, an id with no `PendingAssetId` in the config,
  not owned, store changed (creator, type, price), a missing yes/no or Studio check, a `WE_CHECK` over 40 parts or with a
  Humanoid, a batch over the load budget (healthy: MaxLoadAttempts - 8; outage: LoadRetryReserve after boot), a
  business ref whose `ReplacesRoles` span kit MinLevels, name a colliding or unknown kit role, or put the Belt on a fit
  other than `Fit = "Box"`, and any edit that breaks a BuyPathStatic needle it cannot rewrite.
- After a promote: run the census, fail mode included (cap_refused must stay 0), and add that batch's phone checks to
  section 1.
- **Refused by the check** (over 40 parts or a Humanoid): set the key's registry row to `REJECT` with the `WE_CHECK`
  numbers as its reason (keep its config targets), then run `reject`. It removes the `PendingAssetId` from each config
  line of that id, keeps `ModelAssetId` (so every BuyPathStatic prefix pin holds), rewrites the `Note` and refreshes the
  status table. It refuses a row whose `WE_CHECK` line passes or is a load `FAIL`. Undo is `git revert`.
- **Check record, holds and yaw:** below the registry, `STUDIO_DONE` holds the part counts of the owner's check of
  2026-09-25 (Open Cloud, live place version 75), so the status table stops asking for it. `HOLD` names what still blocks
  a pick the check did not settle (the second check, a code fix, call 12): promote refuses an id on `HOLD` (after the OMIT
  gate); delete its line in the same commit as its promote. `YAW_HINT` is each held vehicle's yaw read from its store
  picture (jet 90, light helicopters 90, APC 0, truck 180, recon plane -90, gunboat -90): promote uses it when `--yaw`
  is not given, because the automatic size rule gets 4 of these 6 wrong. The second check can correct it (`--yaw`).
  After the second check (wc3, 2026-09-27): the light helicopters are 0 (their ThumbnailCamera), `STUDIO_DONE` also
  holds the P4 first check (2026-09-27), `OWNER_YES` records the owner's yes to the truck, the recon plane and the jet
  (promote takes it in place of `--owner-ok`), and `HOLD` names the new blockers: the jet's paint and the truck's paint
  and provenance (owner decisions), the flatbed's cab past the kit nose, the gunboat's scale floor, the P4 second check, and nothing for the recon plane and the APC (promoted).
- **The walls pick 6980242709** passed the check but stays on `HOLD`: `StructureKitBuilder` (walls level 3+) is its only
  caller, and `VisualAssetService.weldScaledBuilding` scales the Z-long model into the X-long 24 x 8 x 3 wall footprint
  and then re-pivots it to the wall centre (`weldCloneToPrimary` without `keepPlace`), so it sits inside the wall. The
  fix (keepPlace plus a yaw for walls) goes into `VisualAssetService` first; then the second check, then the promote.
- **Undo the Dock record (13183571527):** delete the wc2 pin `Dock = { ModelAssetId = 13183571527, …` in
  `tools/BuyPathStatic.py`, then `demote 13183571527` (it restores the Dock line, the licence rows and the journal), and
  delete the sentence "The Dock row (13183571527) is recorded only …" in docs/ASSET_LICENSES.md §3.1 (the tool does not
  write it).

## 10. Status of every item (generated)

<!-- wire-asset-ids:begin (generated by tools/wire-asset-ids.py render; do not edit by hand) -->

Generated from the repo config (PreferMeshWhenAssetIdSet = false). "Owned" is the owner-account check of 2026-09-25 08:05 UTC. Live id 0 = our Part kit. "Recorded only" = a building field that never shows while the buildings stay our walk-in shells (rule 4).

| Item | Decision | Live id | Pending id | Owned | Gate |
|---|---|---|---|---|---|
| Minigun Turret Pack | owner pick, waits for promote | 109072907337393 | – | yes | promoted (live) |
| J67 Hesco PBR | wired in Job67DressConfig (Code Bot JOB 67, owner-first) | 116015230898207 (Job67DressConfig) | – | yes | PAID (shaunie6); 1 MeshPart, 17,247 tris, 0 scripts; wall tiers L3-L5 (Code Bot JOB 67… |
| J67 Trench Sandbags | wired in Job67DressConfig (Code Bot JOB 67, owner-first) | 71112106874796 (Job67DressConfig) | – | yes | PAID (shaunie6); 26 MeshParts, 149,263 tris (pack), 0 scripts; corner nests + base prop… |
| J67 Military Supplies | wired in Job67DressConfig (Code Bot JOB 67, owner-first) | 70726960831586 (Job67DressConfig) | – | yes | PAID (shaunie6); 204 MeshParts, store tris not published, 0 scripts; wall sandbag runs… |
| J67 Textured Crates | wired in Job67DressConfig (Code Bot JOB 67, owner-first) | 87282634781307 (Job67DressConfig) | – | yes | PAID (shaunie6); 25 MeshParts, 10,914 tris (pack), 0 scripts; base prop crates (Code Bo… |
| Ammo Works | wired (Roblox-owned) | 41324890 | – | Roblox (no Get) | Roblox Conveyor Belt as the Ammo Works belt (takes the kit belt's place) |
| Arms Crate Line | wired (Roblox-owned) | 41324890 | – | Roblox (no Get) | Roblox Conveyor Belt as the Arms Crate Line belt (same load as Ammo Works) |
| Armor Plate Press | owner pick, waits for promote | 0 | 4362642898 | yes | check passed (28 parts); OmitParts + the P4 second check (part names: its bounds box, and one piece for the Signature role; 28 parts > 3 roles), batch P4 |
| Rocket Assembly | wired (Roblox-owned) | 31603741 | – | Roblox (no Get) | Roblox Rocket as the rocket body, Fire + Smoke removed |
| Manual Dropper | owner pick, waits for promote | 0 | 14408455045 | yes | check passed (14 parts); the P4 second check (neon parts, upright pose) + the droppers lane (v1b reads its WE_CatalogProp), batch P4 |
| Plot Oil Pump | owner pick, waits for promote | 0 | 15192621369 (not in config) | yes | not in config yet |
| Oil Rig | kept our build | – | – | yes | [WEAK]; likely over 40 parts; our oil-rig kit is the gameplay platform |
| Money Collector | owner pick, waits for promote | 0 | 18220523228 (not in config) | yes | not in config yet |
| Training Yard | rejected | – | – | yes | wrong item: a group-training button board, not a military yard |
| Premium Pad | kept our build | – | – | no | you said no good match: keep our build |
| Supply Drop Crate | needs new code first | – | – | yes | needs one call in SupplyDropService (drop crate dress) |
| Supply Spinner | needs new code first | – | – | yes | not recommended: the spinner is a screen panel, not a world object |
| Command Center | owner pick, waits for promote | 0 | 43803492 | yes | your yes/no, batch P2 (recorded only) |
| Barracks | owner pick, waits for promote | 0 | 8637034739 | yes | ready, batch P1i (recorded only) |
| Vehicle Depot | rejected | 12208876851 | – | yes | owner check (Open Cloud, v75): 113 parts (cap 40), 12 lights |
| Weapons Facility | owner pick, waits for promote | 4120970784 | 11850705638 | yes | your yes/no, batch P2 (recorded only) |
| Helipad | owner pick, waits for promote | 14313845338 | 45369635 | yes | ready, batch P1i (recorded only) |
| Dock | owner pick, waits for promote | 13183571527 | – | yes | promoted (recorded only) |
| Airfield | needs new code first | – | – | yes | not recommended: the airfield builds its own runway |
| Runway | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Watchtowers | rejected | 108525417345747 | – | yes | owner check (Open Cloud, v75): 135 parts (cap 40), 19 scripts, 20 fire/smoke effects |
| Radar | owner pick, waits for promote | 9559610195 | 856258654 | yes | ready, batch P1i (recorded only) |
| Research Lab | rejected | – | – | yes | wrong item: a spiky sci-fi hull listed as a vehicle |
| Missile Defense | owner pick, waits for promote | 0 | 3461514733 | yes | ready, batch P1i (recorded only) |
| Power Station | owner pick, waits for promote | 14000967030 | 6869290892 | yes | ready, batch P1i (recorded only) |
| Warehouse | owner pick, waits for promote | 15942568272 | 8076230849 | yes | ready, batch P1i (recorded only) |
| Special Forces Facility | owner pick, waits for promote | 0 | 10112923897 | yes | ready, batch P1i (recorded only) |
| Empire Bank | rejected | – | – | yes | wrong item: this store 'bank' is a park bench |
| Home Outpost | wired (Roblox-owned) | 80566030 | – | Roblox (no Get) | Roblox Capture Points pad at each Home Outpost (its beam and highlight parts dropped) |
| Hangar | rejected | 0 | – | yes | owner check (Open Cloud, v75): 871 parts (cap 40), 4 lights |
| Bunker | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY); 43 parts, 3 wedges must be dropped |
| Tent | owner pick, waits for promote | 182529039 | – | yes | promoted (live) |
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
| Defensive Walls | owner pick, waits for promote | 0 | 6980242709 | yes | check passed (20 parts); a VisualAssetService wall-fit fix, then the second check, batch P2 |
| Defensive Walls L3 | rejected | 0 | – | yes | owner check (Open Cloud, v75): 46 parts (cap 40); wall models cannot leave parts out |
| Base Gate | needs new code first | – | – | yes | needs one call in StructureKitBuilder (gate arch dress) |
| Compound Wall | rejected | – | – | yes | wrong scale: a stone ring around a whole 512-stud baseplate |
| Wire Fence | needs new code first | – | – | yes | needs the world-model overlay job (W-OVERLAY) |
| Sandbag Line | owner pick, waits for promote | 15271872710 | – | yes | promoted (live) |
| Sandbag Nest | rejected | – | – | yes | wrong item: a lone WWII-style machine gun with no sandbags |
| Jersey | owner pick, waits for promote | 2766525411 | – | yes | promoted (live) |
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
| Armored Truck | owner pick, waits for promote | 0 | 8546141386 (not in config) | yes | not in config yet |
| Supply Truck | owner pick, waits for promote | 0 | 8546141386 (not in config) | yes | not in config yet |
| Ammo Carrier | owner pick, waits for promote | 0 | 8546141386 (not in config) | yes | not in config yet |
| Troop Transport | owner pick, waits for promote | 0 | 8546141386 (not in config) | yes | not in config yet |
| Recovery Truck | owner pick, waits for promote | 0 | 8546141386 (not in config) | yes | not in config yet |
| Anti Air Truck | owner pick, waits for promote | 0 | 8546141386 (not in config) | yes | not in config yet |
| Fuel Tanker | rejected | 0 | – | yes | owner check (Open Cloud, v75): 55 parts (cap 40); second check: all 55 are named "Part"… |
| Engineering Truck | rejected | – | – | yes | cannot be checked: the only picture shows the inside of a block |
| Flatbed Hauler | owner pick, waits for promote | 0 | 8455894899 (not in config) | yes | not in config yet |
| Radar Truck | rejected | 0 | – | yes | owner check (Open Cloud, v75): 93 parts (cap 40) |
| Mine Clearer | rejected | – | – | yes | wrong item (a wheel loader) and unclear origin |
| Premium Bastion | waits on another job's file | – | – | yes | VehicleConfig + VehicleService (streaming2-build): premium vehicle def |
| APC | owner pick, waits for promote | 9076240315 | – | yes | promoted (live) |
| Infantry Carrier | owner pick, waits for promote | 9076240315 | – | yes | promoted (live) |
| Command Vehicle | owner pick, waits for promote | 9076240315 | – | yes | promoted (live) |
| Wheeled IFV | owner pick, waits for promote | 9076240315 | – | yes | promoted (live) |
| Amphibious APC | owner pick, waits for promote | 9076240315 | – | yes | promoted (live) |
| Combat IFV | rejected | 0 | – | yes | owner check (Open Cloud, v75): 321 parts (cap 40) |
| Assault IFV | rejected | 0 | – | yes | owner check (Open Cloud, v75): 321 parts (cap 40) |
| Flame Carrier | rejected | 0 | – | yes | owner check (Open Cloud, v75): 321 parts (cap 40) |
| Bridge Layer | kept our build | 0 | – | yes | you said no good match: keep our build (it never borrows another tank's body) |
| Missile Truck | rejected | 0 | – | yes | owner check (Open Cloud, v75): 219 parts (cap 40) |
| Rocket Artillery | rejected | 0 | – | yes | owner check (Open Cloud, v75): 219 parts (cap 40) |
| Light Tank | kept our build | – | – | yes | [WEAK]; a green box tank, cruder than our tank kit (7 tanks would share it) |
| Medium Tank | kept our build | – | – | yes | [WEAK]; a green box tank, cruder than our tank kit (7 tanks would share it) |
| Heavy Tank | kept our build | – | – | yes | [WEAK]; a green box tank, cruder than our tank kit (7 tanks would share it) |
| Battle Tank | kept our build | – | – | yes | [WEAK]; a green box tank, cruder than our tank kit (7 tanks would share it) |
| Tank Destroyer | kept our build | – | – | yes | [WEAK]; a green box tank, cruder than our tank kit (7 tanks would share it) |
| Assault Gun | kept our build | – | – | yes | [WEAK]; a green box tank, cruder than our tank kit (7 tanks would share it) |
| Light Scout Tank | kept our build | – | – | yes | [WEAK]; a green box tank, cruder than our tank kit (7 tanks would share it) |
| Premium Warlord | kept our build | – | – | yes | [WEAK]; brick-built toy tank, far over 40 parts; paid slot |
| SPAAG | rejected | 0 | – | yes | owner check (Open Cloud, v75): 301 parts (cap 40) |
| Mobile SAM | rejected | 0 | – | yes | owner check (Open Cloud, v75): 301 parts (cap 40) |
| Mortar Carrier | kept our build | – | – | yes | [WEAK]; a tripod mortar with no vehicle |
| Mobile Artillery | kept our build | – | – | yes | [WEAK]; a crude block gun, worse than our kit |
| Howitzer Truck | kept our build | – | – | yes | [WEAK]; a crude block gun, worse than our kit |
| Siege Mortar | kept our build | – | – | yes | [WEAK]; a crude block gun, worse than our kit |
| Light Scout Heli | owner pick, waits for promote | – | 2474869838 (not in config) | yes | not in config yet |
| Utility Heli | owner pick, waits for promote | – | 2474869838 (not in config) | yes | not in config yet |
| Transport Heli | rejected | – | – | yes | owner check (Open Cloud, v75): 109 parts (cap 40) |
| Heavy Lift Heli | rejected | – | – | yes | owner check (Open Cloud, v75): 109 parts (cap 40) |
| Light Transport Heli | rejected | – | – | yes | owner check (Open Cloud, v75): 109 parts (cap 40) |
| Gunship Heli | rejected | – | – | yes | copy of a game-franchise gunship (Half-Life 2) |
| Attack Helicopter | rejected | – | – | yes | copy of a game-franchise gunship (Half-Life 2) |
| Escort Heli | rejected | – | – | yes | copy of a game-franchise gunship (Half-Life 2) |
| Night Attack Heli | rejected | – | – | yes | copy of a game-franchise gunship (Half-Life 2) |
| Premium Stormwing | rejected | – | – | yes | copy of a game-franchise gunship (Half-Life 2) |
| Rescue Heli | rejected | – | – | yes | owner check (Open Cloud, v75): 78 parts (cap 40); second check: only "Part" (49) and "W… |
| Rescue Heli V2 | rejected | – | – | yes | your replacement pick (2026-09-28), not used: the origin check failed. Its 7 rotor Mesh… |
| Medevac Heli | rejected | – | – | yes | owner check (Open Cloud, v75): 78 parts (cap 40); same model as the Rescue Heli pick 11… |
| Medevac Heli V2 | rejected | – | – | yes | your replacement pick (2026-09-28), not used: the origin check failed. Its 7 rotor Mesh… |
| VTOL Transport | rejected | – | – | yes | the uploader does not claim it ('Unknown Vtol'); looks ripped |
| Cargo Plane | rejected | – | – | yes | 47 parts (over 40) and a real cargo-plane look |
| AWACS Plane | rejected | – | – | yes | 47 parts (over 40) and a real cargo-plane look |
| Tanker Plane | rejected | – | – | yes | 47 parts (over 40) and a real cargo-plane look |
| Strike Jet | rejected | – | – | yes | copy of a real jet (F-16) |
| CAS Jet | rejected | – | – | yes | copy of a real jet (F-16) |
| Fighter Jet | rejected | 14589101870 | – | yes | replaced by your pick 14589101870 (2026-09-28); its paint was another artist's drawing |
| Fighter Jet V2 | owner pick, waits for promote | 14589101870 | – | yes | promoted (live) |
| Interceptor Jet | rejected | 14589101870 | – | yes | replaced by your pick 14589101870 (2026-09-28); its paint was another artist's drawing |
| Interceptor Jet V2 | owner pick, waits for promote | 14589101870 | – | yes | promoted (live) |
| Trainer Jet | rejected | 14589101870 | – | yes | replaced by your pick 14589101870 (2026-09-28); its paint was another artist's drawing |
| Trainer Jet V2 | owner pick, waits for promote | 14589101870 | – | yes | promoted (live) |
| Light Fighter | rejected | 14589101870 | – | yes | replaced by your pick 14589101870 (2026-09-28); its paint was another artist's drawing |
| Light Fighter V2 | owner pick, waits for promote | 14589101870 | – | yes | promoted (live) |
| Strike Bomber | rejected | – | – | yes | national-style roundel on the wing; made by someone else |
| Recon Plane | owner pick, waits for promote | 4954987035 | – | yes | promoted (live) |
| Patrol Boat | rejected | 0 | – | yes | owner check (Open Cloud, v75): 114 parts (cap 40), and only 7 studs long |
| Fast Attack Craft | rejected | 0 | – | yes | owner check (Open Cloud, v75): 114 parts (cap 40), and only 7 studs long |
| Coast Cutter | rejected | 0 | – | yes | owner check (Open Cloud, v75): 114 parts (cap 40), and only 7 studs long |
| Torpedo Boat | rejected | 0 | – | yes | owner check (Open Cloud, v75): 114 parts (cap 40), and only 7 studs long |
| Gunboat | owner pick, waits for promote | 0 | 15838664806 (not in config) | yes | not in config yet |
| Missile Boat | owner pick, waits for promote | 0 | 15838664806 (not in config) | yes | not in config yet |
| Mine Layer | owner pick, waits for promote | 0 | 15838664806 (not in config) | yes | not in config yet |
| Coastal Monitor | owner pick, waits for promote | 0 | 15838664806 (not in config) | yes | not in config yet |
| Landing Craft | rejected | – | – | yes | wrong item: a space lander |
| Assault Landing | rejected | – | – | yes | wrong item: a space lander |
| Amphib Assault | rejected | – | – | yes | wrong item: a space lander |
| Corvette | kept our build | – | – | yes | [WEAK]; a plain hull with no guns; our warship kit reads better |
| Destroyer | kept our build | – | – | yes | [WEAK]; a plain hull with no guns; our warship kit reads better |
| Frigate | kept our build | – | – | yes | [WEAK]; a plain hull with no guns; our warship kit reads better |
| Carrier Escort | kept our build | – | – | yes | [WEAK]; a plain hull with no guns; our warship kit reads better |
| River Boat | rejected | – | – | yes | wrong item (a theme-park raft) and made by someone else |
| Hover Transport | rejected | – | – | yes | owner check (Open Cloud, v75): 211 parts (cap 40) |
| Hospital Ship | rejected | – | – | yes | red-cross emblems and a copy of a named real ship |
| Supply Ship | rejected | – | – | yes | owner check (Open Cloud, v75): 174 parts (cap 40) |
| Premium Tidebreaker | waits on another job's file | – | – | yes | VehicleConfig + VehicleService (streaming2-build): premium vehicle def, then a Studio look |
| Soldier | wired (Roblox-owned) | 187790284 | – | Roblox (no Get) | Roblox Soldier, animated rig (R-RIG); camo cap; the look every unknown soldier kind fal… |
| Infantry | wired (Roblox-owned) | 187790284 | – | Roblox (no Get) | Roblox Soldier, animated rig (R-RIG), in the kit colours and kit helmet |
| Squad | wired (Roblox-owned) | 0 (expected 187790284) | – | Roblox (no Get) | Roblox Soldier, animated rig (R-RIG), camo cap: friendly squad units (the army escorts… |
| Heavy Infantry | rejected | – | – | yes | #8 default (R-RIG): the Roblox Soldier rig 187790284 dresses this kind; a Shirt / Pants… |
| Special Forces | rejected | – | – | yes | wrong item: a beret with a real regiment's badge |
| Worker | rejected | – | – | yes | #8 default (R-RIG): the Roblox Soldier rig 187790284 dresses this kind; a Shirt / Pants… |
| Guard | rejected | – | – | yes | #8 default (R-RIG): the Roblox Soldier rig 187790284 dresses this kind; a Shirt / Pants… |
| Gate Guard | rejected | – | – | yes | #8 default (R-RIG): the Roblox Soldier rig 187790284 dresses this kind; a Shirt / Pants… |
| Oil Rig Guard | wired (Roblox-owned) | 187790284 | – | Roblox (no Get) | Roblox Soldier, animated rig (R-RIG), in the kit colours and kit helmet |
| Fort Guard | wired (Roblox-owned) | 187790284 | – | Roblox (no Get) | Roblox Soldier, animated rig (R-RIG), in the kit colours and kit helmet |
| Bank Guard | rejected | – | – | yes | #8 default (R-RIG): the Roblox Soldier rig 187790284 dresses this kind; a Shirt / Pants… |
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
| Auto Gun | owner pick, waits for promote | 114570602 | – | yes | promoted (live) |
| Vehicle MG | owner pick, waits for promote | 0 | 5589684833 | yes | check passed (1 part); the P4 second check (which end is the barrel) + a FitScale look on the Roblox-size 4x4, batch P4 |
| Vehicle Cannon | owner pick, waits for promote | 0 | 3322196012 | yes | check passed (1 part); the P4 second check (which way the barrel points; a gun's Yaw is set by hand), batch P4 |
| Rocket Pods | kept our build | – | – | yes | [WEAK]; the asset is a whole car; our kit is the pod |
| Nuke | needs new code first | – | – | yes | needs a nuke-strike effect module (none exists) |
| Crate Stack | wired (Roblox-owned) | 6933790012 | – | Roblox (no Get) | Synty wooden crates (already live) |
| Military Crate | owner pick, waits for promote | 2930926216 | – | yes | promoted (live) |
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
| Flag Pole | owner pick, waits for promote | 0 | 172755983 | yes | ready, batch P1i (recorded only) |
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
| Tutorial Arrow | owner pick, waits for promote | 632958370 | – | yes | promoted (live) |
| Showroom Podium | rejected | – | – | yes | wrong item: a record player |
| Cash Pile | needs new code first | – | – | yes | needs a host; the bills must be stripped (real currency art) |

<!-- wire-asset-ids:end -->
