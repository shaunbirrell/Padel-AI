# VKIT NAVAL lane, fix round 1b: assumptions (for the integrator to merge into ASSUMPTIONS.md)

Every item can be reversed in config:

- `Configs/VehicleBodies/Naval.luau`: regenerate it with the lane's `tools/gen_naval.py <tree>`.
- `VehicleConfig.Drive` (ChaseZoom / ExitSpot / Ride / Spawn).
- The framework kill switch `VehicleBodies.Enabled = false`. Every boat is v83's kit again, with v83's camera, exit and prompts. `nworld_off` shows this (649 / 1, the same as main).

Round 0's list is kept in `round0/assumptions.md` and is superseded by this one.

1. **Real scale, compressed to fit the base dock.** Every design is drawn in final studs around the 5.2-stud avatar. Measured drawn lengths (`results/dims.txt`), with v83's kits for comparison:

   | Group | Ships | Length (studs) | v83 kits |
   |---|---|---|---|
   | Small craft | River Boat, Coast Cutter, Torpedo Boat, Fast Attack Craft, Patrol Boat | 20.2 to 26.0 | 9.8 to 12.2 |
   | Gunboat class | Gunboat, Missile Boat, Coastal Monitor, Mine Layer | 30.0 to 32.2 | 15.0 to 16.5 |
   | Landing and support | Landing Craft, Hover Transport, Assault Landing, Supply Ship, Hospital Ship, Amphib Assault Ship | 32.7 to 52.6 | 18.3 to 22.7 |
   | Submarines | Sub Surface Runner, Attack Sub | 33.6 and 39.6 | 19.0 and 20.9 |
   | Warships | Corvette to Battleship | 40.4 to 65.0 | 21.4 to 44.2 |
   | Fleet Carrier | | 66.5 | 48.5 |

   Dock limits:
   - The basin is 50 x 70.
   - The sea gate is 40 wide, and its lintel is 28.4 over the water.
   - BuyPathStatic N3 caps a body at 67 long, 18 wide and 26 tall. The tallest body here is 20.4.

   Real capital ships are longer, so they are drawn shorter.

2. **Walkable decks (Solid).** The hull topsides, the bow and the foredeck (on a submarine, the casing and the stern planes) are `Solid`: they collide and are hit.
   - VehicleBodyBuilder step 4d turns off the kit's other collidable blocks. It never touches the Chassis.
   - A rider who jumps out, or walks the deck, stands on the drawn deck: 116 of 116 deck probes pass (main: 114).
   - Every Solid part is at or over Y 0.2, so the ride height is still the kit's (N7).

3. **The shore stop is measured to the Solid hull.** Solid parts count in the footprint (`WE_HalfLength` / `WE_HalfWidth`).
   - Anything drawn past them stays within ShoreMargin − 1 = 2 studs of `WE_HalfLength`, for example a raked stem tip, a gun barrel or a sub's bow dome (N12). The stop fires HalfLength + 3 ahead, before a drawn tip reaches land.
   - `WE_HalfLength` is the larger of the bow and stern ends. This is the same rule the shore probe uses, so no per-end rule was added.
   - Every ship's Solid half length + 3 is inside the sea gate's 40-stud opening radius (N8).

4. **Hit = what you see.** Every visible part is `Hit` (N6), and the kit's hidden plain parts leave the hit set (step 4c, from the AIR lane's fix 1b).
   - A spinning radar bar or propeller is never Hit, because the server's copy does not turn.

5. **Riders sit inside.**
   - Every surface helmsman has a roof 4.15 to 5 studs over his seat top (N4).
   - Passengers sit in a deckhouse, a gun tub, a troop well or a sunken cockpit, never on a roof.
   - Riders side by side sit at least 3.4 apart across the ship, or staggered at least 1.2 along it (N13).
   - The seat checker passes 116 of 116 seats, also with an avatar 0.5 taller (main: 0 of 116).

6. **Submarines are surfaced.** Each has:
   - a round pressure hull with a ball bow;
   - a stepped tail down to the waterline;
   - a tall rudder and stern planes;
   - a sail with fairwater planes.

   Crew positions:
   - On both subs, the helmsman and a lookout sit in the sail. The rim is 2.4 over their seat top, so only their heads show.
   - Sub Surface Runner: two crew sit low in the hull under open hatches, with head and shoulders out.
   - Attack Sub: two crew sit fully inside a low missile deck, whose roof is 4.48 over their seat tops (N5).

7. **Boat chase camera.** The cap is `Drive.ChaseZoom.Modes.Boat` = 1.7 / 0 / 14 / 60. It is the closest straight-line cap that keeps every ship's whole deck on a 956 x 440 phone screen.
   - 19 of 25 ships are 0.94 to 1.64 x their v83 on-screen width.
   - Gunboat, Coastal Monitor, Mine Layer and Missile Boat are 0.53 to 0.67 x.
   - The two submarines are 0.40 and 0.41 x.
   - Those 6 are long and thin now, where v83's kits were wide blocks. Even at their own closest deck-in-frame zoom they would reach only about 0.5 to 0.8 x.
   - A small-craft branch would crop their bow and stern, so the owner is asked instead (phone test step 3).
   - The numbers come from a headless camera model of Roblox's VehicleCamera. They still need a real phone.

8. **Quay exit and Ride prompt for boats that wear a body.** `Drive.ExitSpot.BodyModes` and `Drive.Ride.BodyModes` list `Boat` (N10).
   - A driver who leaves at the quay steps onto the dry quay (116 of 116; main: 0 of 25).
   - Mid-basin, with no dry spot in reach, he stays on the deck and is never put in the water (25 of 25).
   - Friends on the quay board through the Ride prompt (91 of 91).

9. **The Drive prompt reaches the driver's own exit spot.** Its range is max(v83's range, `_DrivePromptExitReach`): the flat distance from the driver seat to its ExitSpot second ring + `DrivePromptExitPad` 4.
   - 17 ships keep v83's range.
   - 8 ships get a longer one. The Fleet Carrier, whose helm is 5 studs to starboard in its island, gets 23 (was 14).
   - After a quay exit, the prompt reached and re-seated the driver on both quays for all 25 ships: 50 of 50 (`NDSUM`).
   - Not covered: a driver who walks round to the far end of a long ship. He walks back to the side to get in.

10. **Open-family passengers under a roof** (not changed this round; noted for a follow-up). `VehicleCombatConfig.SeatFire.OpenFamilies` lets passengers of NavalPatrol / NavalGun / NavalLanding boats fire from their seat.
    - The fix 1 seating puts them inside cabins. The shot filter leaves the shooter's own vehicle out, so their shots leave through the roof, as they did through v83's kits.
    - If the owner dislikes that, the fix is config only: move those families out of `OpenFamilies`, or seat two crew in open tubs. It was not changed here because it is a combat rule, not a body rule.

11. **Radar and propellers turn only while someone drives.** They use the framework's `VehicleBodySpin`:
    - radar bars: 30 to 36 rpm, 2 blades;
    - the Hover Transport's two ducted propellers: 200 rpm, each inside a duct with a rudder behind it.

    The Coast Cutter carries a small tender on a davit.

12. **Generic designs only.**
    - No real ship, class, navy or yard names.
    - No hull numbers, flags, emblems, insignia or unit markings. The hospital ship has a plain green band and no cross. Landing circles are the only markings.
    - No Neon, no lights, no text, no GUIs.
    - Every body has at most 40 parts (19 to 40; results/budget.txt).

13. **The harbor lane owns the dock and its display boats.** With the harbor candidate's two moored display boats present, 113 naval world checks fail where the driver moors against them (see merge_notes.md). Without the display boats, all 1023 checks pass. The fix belongs to the harbor lane (berth side) or to the test's choice of quay.

14. **The multi-line `V(` id regex** (BuyPathStatic line 8369) is byte-identical in the AIR, GROUND and NAVAL candidates. The integrator keeps one copy.
