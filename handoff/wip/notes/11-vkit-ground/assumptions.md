# VKIT GROUND lane, fix round 1 (replay): assumptions (reversible; merge into ASSUMPTIONS.md)

Candidate: `vkit/ground/cand3` = git archive of main **HEAD 4e07fc2** + the VKIT framework candidate + this lane
(3-way merged; HEAD moved e506c9c -> af4c7d4 -> 4d26673 -> 4e07fc2 while the lane ran). The same lane delta on the live
v83 base is `vkit/ground/cand_e5` (e506c9c): its 47-vehicle spawn dump is byte-identical to cand3's. Round 0 is archived
in `out/round0/` (tree `vkit/ground/cand_r0`); the unreturned first fix draft is archived in `out/round1_draft/`
(tree `vkit/ground/cand2`, 4d26673). Every item can be undone in config: `Configs/VehicleBodies/Ground.luau` (data),
`VehicleConfig.Drive.ChaseZoom`, `VehicleCombatConfig.Splash`, `VehicleConfig.Drive.Stability.DriveAtComXFamilies`,
or every body at once with `VehicleBodies.Enabled = false`. All numbers are from the headless stand-in, NOT Roblox.

## VG-1 Scale (visible body box; the avatar is 5.2 studs, 1 stud is about 0.35 m)
Realistic size, capped by the home-pad spawn box (half length <= 14.4, half width <= 6.5; BuyPathStatic G3).
Lengths: quad 11.3, buggy 13.1, staff car 14.8, 4x4 16.4-17, pickups / van 20-22, trucks 20.4-26.5, MRAP 21.1, 8x8
APCs 21-25.8, tracked IFVs 19.2-26.6, tanks 16.6 (Light Scout) to 27.3 (Fortress), casemates 21.8-24.2, anti-air
18.9-19.8, artillery 16.1-24.5. Widths 7.5-11.6; 18 bodies are wider than the 10-stud gate (VG-4).

## VG-2 Where the rider sits
Closed cab: hips in the lower shell, head under the roof. Open seat: low, the tub side at the waist. Hatch: the roof at
chest height, head and shoulders out. vk_seatcheck on the no-store build: 167/167 PASS at the normal avatar and
167/167 at +0.5 studs, 0 clamped (rules: hips in, head not through a thin part, HEAD_IN_THICK, HATCH torso >= 3/4
for the Tracked* / WheeledAPC families except the open-bay crews, limbs clear, feet on a floor). With the store bodies
loaded: 144/23 and 148/19, FAIL list identical to main's (all R2.3 store-body seats).

## VG-3 Hit volume = the drawn body
`Types.PartSpec.Hit`: a Hit part is CanQuery true (still CanCollide / CanTouch false, massless). Every drawn Ground
part is Hit except see-through glass (a shot through a window reaches the rider behind it). Builder step 4c: a Hit body
drops the kit's hidden plain boxes from the hit set. Ray grid (0.3 studs, side / front / top) on the no-store build:
opaque rays register 100.0 % on all 47, phantom hits at most 4.4 % (tolerance 5 %). Splash
(`VehicleCombatConfig.Splash.VisualBox = true`) measures to the WE_Visual* box; it also applies to the R2.3 store
bodies. Pre-existing, not this lane: the 9 store-body vehicles register 4 % of opaque rays and take up to 18.1 %
phantom hits, identical on main (their MeshParts are not queryable). Flagged for the store-body owner.

## VG-4 The body overhangs the kit; the kit is what bumps
The body never collides, so the kit's box is what stops at a wall, gate post or vehicle. Past the kit at each end:
median 5.50 studs, max 8.93 (Tank Destroyer); per side max 1.55 (Scout Car). Full per-vehicle table:
`out/results/lane_checks/overhang.md`. 18 bodies are wider than the 10-stud gate, by up to 0.8 a side (Fortress Tank
11.6, whose kit is 11.0 already). The friendly gate opens before the visible nose on all 47 (vs2_gate 48/0; the
nearest nose is 2.16 studs before the gate line, Railgun Carrier; main 3.90). Disclosed in owner_text.md; phone_test
steps 10-11 check walls, vehicles and the gate.

## VG-5 Chase camera: the VKIT air lane's ChaseZoom + a Car mode
`VehicleConfig.Drive.ChaseZoom` is the air lane's block verbatim (Heli / Plane, PartBodyOnly, PassengerModes) with
`Modes.Car = { LengthMul = 0.8, Add = 12, Min = 16, Max = 28 }` added; VehicleDriveClient is the air lane's hunk
verbatim (byte-identical on the e506c9c base), so the integrator takes one version. While the local player drives a
Car-mode vehicle with WE_VisualHalfLength, CameraMaxZoomDistance is capped at clamp(halfLength x 0.8 + 12, 16, 28)
(never raised); leaving the seat restores it. Car is in neither PartBodyOnly (a store body gets the same cap: the
Cargo Van's camera comes from 37.8 to 20.0 studs) nor PassengerModes (a Car passenger keeps his own closest zoom).
- Phone 956 x 440, Roblox VehicleCamera model: every one of the 47 Part bodies is at least as wide on screen as main
  (x1.02 min, x1.27 median, x2.26 max); without the cap x0.53-1.11. The seated avatar is smaller than on main (driver
  x0.55-x1.8, median x0.76). Tall bodies lose part of their height under the bottom edge: median 1 %, over 15 % on
  3 (Radar Truck, Recovery Truck, Siege Mortar; max 32 %).
- vkg_client: 155 passed / 0 failed on the candidate (cap on sit for all 47, restored on exit, never raised, Car
  passengers keep their zoom limit and closest zoom, the air numbers with a Part body unchanged); main 95/0.

## VG-6 Store bodies first; the Part body is the fallback
Store bodies (VisualAssetConfig.Vehicles) win when they load: the 9 LUV / buggy / van / pickup vehicles show 0
Part-body parts, as on main. The APC family's store file does not load in the stand-in, so its Part bodies were the
ones tested. On HEAD 4e07fc2 the truck family (Fuel Tanker, Armored Truck, Supply Truck, Ammo Carrier, Anti-Air Truck,
Troop Transport, Recovery Truck) still has ModelAssetId 0 (the owner's pick 8546141386 is pending), so live they show
the Part body; if a truck store model is promoted later it wins and the Part body becomes its fallback. The phone
test uses vehicles no store lane touches; the Anti-Air Truck step accepts either look.

## VG-7 Drive point under the centre of mass
`DriveAtComXFamilies` gains WheeledTruck and WheeledAPC (post-literal lines at the end of VehicleConfig, so R2.3's
exact-line pin on `{ WheeledLight = true }` still holds). vsr_phys YAWC on the candidate: 0 % in every wheeled case
(main 20 % driver-only, 5 % / 13 % with passengers, from the store bodies' seats). This config applies with the bodies
off too: the kill-switch dump equals main except DriveAttach X on Ammo Carrier, Cargo Van, Engineering Truck, Escort
Truck and Patrol Truck. Tracked kits drive at x = 0, so every tracked body seats its DriverSeat on the centre line
(BuyPathStatic G7): tracked yaw driver 1 % (main 1 %), driver + P1 17 % (main 19 %), all seats 12 % (main 12 %). Kit
mass unchanged on all 47; min SSF 1.45 (main 1.45), min tip 55.4 degrees (main 55.3); 14 vehicles lose at most 0.04
SSF. t_stability: 47/47 ok on both trees (min SSF 1.28, main 1.27).

## VG-8 Labels
The nameplate / HP bar (WE_LabelY) is over every seated head + 0.5 and over the centre-column body top on all 47
(normal and +0.5 avatar; main passes 10 of 47 on the same check). BuyPathStatic G5.

## VG-9 Look
Every tracked body has road wheels, idler, sprocket and a grey-brown belt; the five big tanks have their own turret
shapes and colour schemes; paints are lifted for night; Flame Carrier, Troop Transport, Rocket Artillery and the
fallback bodies of Dispatch Car, Utility Quad and Infantry Carrier are redrawn (round 1 draft). This replay adds:
the Scout Car fallback body gets a rear window over a low back panel, and the Cargo Van fallback body's window row
runs past its rear seat (VG-13). G2: inside a family every two bodies differ by >= 8 studs^2 of shape or colour from
the side and from behind (min 8.4, ArmedJeep / MilitaryJeep rear). Generic designs only; the only glow is the
Railgun Carrier's two emissive strips (0.3 x 0.3 x 1.2).

## VG-10 Budgets
Body parts per vehicle <= 40 (average 36, total 1,693 on the no-store build); 0 lights / GUIs / decals added (the
ArmedJeep "ARMED" billboard is the kit's own, as on main). A spawned vehicle is at most 56 BaseParts / 139
instances (Assault IFV). 47-vehicle census: main 1,682 parts; candidate 2,343 without store bodies. Vehicles exist only while
spawned: not part of the base or world budgets.

## VG-11 BuyPathStatic
One framework block (with the id-regex fix `V\(\s*"`, out/bps_framework_fix.diff; integrator: take it once, the air
and naval lanes need it too) and one ground block (out/bps_block.txt, G1-G8), each directly above main's final
parse_gate(). Every ground pin fails on main + the block (12 FAIL) and on a mutant (20 mutants, each FAILs its pin).

## VG-12 Gate exceptions (integrator decision)
1. vs23_jeep_look (R2.3) reads 197/200: its K4 expects "a failed store body keeps the kit's own seats"; this lane
   replaces that fallback by the Part body. Lane variant vs23_jeep_look_vk (K4-vkit: the Part body goes on, no
   collide / massless / welded, opaque Hit parts may be CanQuery (VG-3), a see-through part never is, at least one Hit
   part): 201/201 on the candidate, 200/201 on main (its one FAIL is K4-vkit "no Part body").
2. The W2 suite t_vh_server reads 114/115 (plain and fit): VH10 expects every seat's WE_Exposed /
   WE_CanFireFromSeat to follow SeatFire.OpenFamilies exactly; VG-13 makes 7 seats enclosed. Lane variant
   (out/tools/drv/t_vh_server_vk*.luau: VH10 accepts Blueprint.EnclosedSeats when a Part body is on): 115/115 plain
   and fit on both trees.

## VG-13 Riders who may shoot are as open as they shoot (new in the replay)
The server's shot filter leaves the shooter's own vehicle out, so a rider's shots pass through his own Part body,
while an enemy's shot at him stops on it (the body is the hit volume, VG-3). For the seats that may fire
(VehicleCombatConfig.SeatFire.OpenFamilies: the 4x4s, cars and trucks; drivers too) the lane measures, from the seated
head, 72 lines out (24 bearings x -8 / 0 / +8 degrees, 12 studs) and how many end on the rider's own opaque body:
- `Blueprint.EnclosedSeats` (Types, Resolve, Validate; builder step 5b): a seat the body closes in is marked
  WE_Exposed = false and WE_CanFireFromSeat = false after VehicleHealth.ApplySeatAttributes, the ENCLOSED seat the
  combat code already knows from the APC / tracked families (no firing out, NPC shots go to the vehicle, aim assist
  skips him, player shots hit the body). Listed: the Troop Transport's three bed seats under the canvas (79-88 % of
  the lines out end on the canvas) and the Armored Truck's four cab seats behind armoured glass (51-56 %). Its roof
  gunner and every other rider keep their family rule.
- Scout Car fallback: rear window (the rear rider went from 43 % to 3 %, 11 % for a 0.5-taller avatar). Cargo Van
  fallback: longer window row (the rear seat 46 % -> 38 %).
- Result: 67 fire-capable open-family seats, max 37.5 % (44.4 % for a 0.5-taller avatar), median 18 %; 7 enclosed.
  The rest of the one-way cover is the cab's back wall (a cab rider can still fire backwards through it): disclosed.
- Pinned by BuyPathStatic G8 (box extents, < 50 %) and the lane tool vkg_encl.py (exact geometry); the dump shows the
  attributes as built by the real VehicleHealth + builder. With `VehicleBodies.Enabled = false` or a store body the
  seats keep the family rule (as v83). Gameplay change: riders in those 7 seats can no longer fire (v83 let every
  truck rider fire); stated in owner_text.md.

## VG-14 Stand-in limits (NOT Roblox)
Renders, physics (vsr_phys), exits, gates, seats, rays and the camera model are headless measurements. Unchecked on
a real device: frame rate and heat at Graphics Quality 3 on a mid-range Android; the chase-camera size and pinch
limit on the owner's phone; hit registration and splash against Part bodies in live combat; the enclosed seats in
live fights; the APC store body loading live; the drive feel with the new drive points; bodies sinking into walls,
vehicles and gate posts; colours at night.
