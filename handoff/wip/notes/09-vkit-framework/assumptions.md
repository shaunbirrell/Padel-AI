# VKIT framework: assumptions (for the integrator to merge into ASSUMPTIONS.md)

Every item is reversible. Most are reversed by one config line in `Configs/VehicleBodies`.

1. **Opt-in per vehicle.** Only AntiAirTruck, StrikeJet and Gunboat get Part bodies in this lane. `KitFamilies` is
   empty in all three class modules; a BuyPathStatic pin keeps it empty until a class lane maps a family on purpose.
   Reverse: remove the `Vehicles` entry, or set `Enabled = false` on it.
2. **Store body first.** A Creator Store body that attaches at spawn always wins, and the Part body is the fallback.
   A store body that finishes loading after the spawn replaces the Part body on the next spawn only. There is no live
   swap: swapping bodies under a seated player was judged riskier than one spawn of the fallback look.
3. **Hitbox stays the kit.** Body parts have `CanQuery = false`, so shots, rays, collisions and spawn clearance use
   the hidden kit volume exactly as today. The visible body is larger than the hitbox, as the R2.3 store bodies are.
   Reverse (per part): a future `Query` flag. None is added now.
4. **Size.** The Part bodies are drawn at Roblox vehicle size, not kit size. The truck is 22.3 long, the jet 40.2 long
   with a 26.2 span, and the gunboat 28.1 long. This is calibrated on the store bodies the owner accepted (the Roblox
   4x4 17.6, pickup / van 26.2-26.6). The scale table in api.md §8 is a proposal for the class lanes, not a rule.
5. **Seats inside the kit box.** Seats move into the body, but stay 0.25 inside the kit's collidable box (the R2.3
   BodySeatKitInset rule). The exemplars' seat positions were chosen so that none is clamped.
6. **Label height.** Label = body top + 1 + 0.4 × (top − 4.5), the R2.3 store-body rule. Parts thinner than 0.5 studs
   as built (antennas, masts, gun barrels, fins) do not count. The Gunboat sets `LabelHeight = 12.8` so its nameplate
   sits just over the mast lamp.
7. **Kit visuals removed, physics kept.** Plain kit visual parts are destroyed before the model is parented, so there
   is no double part cost. Chassis, collidable parts, physics wheels, weapon mount parts and seats stay, hidden.
   Weapon mount parts stay because AirWeaponService / VehicleWeapons look them up by name.
8. **Weapons dress.** The store turret dress (VisualAssetConfig.VehicleWeapons) is skipped on a Part-body vehicle,
   because the body draws its own guns. The kit mount parts stay for the weapon logic.
9. **Bomb release point.** The StrikeJet drops bombs from its body's bay point: chassis frame (0, −0.20, 3.45), 1.55
   over the ground line, under the fuselage. Main drops them from 0.5 below the ground line, under the kit chassis.
   This only matters while flying. The airweapons unit (99/0) uses its own fake kit and is unchanged.
10. **Rotor spin is client-only and powered-only.** Rotors turn only while the vehicle's `WE_DriverUserId` is set,
    within 300 studs of the camera, at most 12 at once, re-chosen 4 times a second. Nothing replicates. With
    `Spin.Enabled = false`, nothing turns.
11. **Plane / boat exits unchanged.** They remain Roblox's own jump-out, as on main (the server exit spot is used for
    cars only). With a body, a pilot who jumps out lands on the hidden kit chassis inside the visible fuselage, and
    can walk out. A proposed follow-up is to extend `_PlaceExit` to stopped planes and boats. That is not done here
    (VehicleService exit logic is outside this lane).
12. **ASSUMPTIONS.md not edited in the candidate tree.** This file is for the integrator to merge, per the lane rule
    that the integrator commits.
13. **99 vehicles.** VehicleConfig has 99 vehicles at e506c9c, not 86. Every ON/OFF check covers all 99.
14. **Generic designs.** The designs are a cab-over 6x6 anti-air truck, a delta-wing single-seat strike jet and a
    wheelhouse gunboat. They have no real names, insignia, flags, roundels or national markings. A BuyPathStatic pin
    refuses part names containing flag / insignia / roundel / emblem / decal / logo / marking.
