# VKIT AIR lane, fix round 1c: assumptions to add to ASSUMPTIONS.md

All numbers come from the headless stand-in, which is not Roblox. The owner still has to check them on his phone.

Every item can be undone:
- **Bodies:** edit `Configs/VehicleBodies/Air.luau` (the lane's `tools/gen_air.py` regenerates it). `VehicleBodies.Enabled = false` switches every body off. The kill-switch dump then matches main in every part (2582 parts).
- **Camera:** `VehicleConfig.Drive.ChaseZoom.Enabled = false`.
- **Spawn spots:** `VehicleConfig.Drive.Spawn.RotorSlab.Enabled = false` brings back the fix 1b spot box. The plane runway start is HEAD's AIR2 rule.
- **Splash:** `CombatFeelConfig.Splash.IgnorePartBodies = false`.

## Unchanged since fix 1b (numbers re-measured on the fix 1c tree)

**1. Shots hit the drawn aircraft.**
- Every non-rotor body part is a Hit part: `CanQuery = true`, not collidable, massless. Builder step 4c takes the kit's hidden plain parts out of the hit set.
- The kit's collidable chassis, gear and skids still take hits.
- Spinning blades, hubs and spinners never take hits.
- On the ray grid, the hit area is **2.95 × main's** (fix 1b: 2.84). Phantom hits are 0.4 %, and 99.3 % of rays at the drawn outline register a hit.
- **Owner decision:** if aircraft die too fast, raise Air HP in `VehicleConfig`, or set `Hit = false` on the wings.

**2. Pilots sit on the centre line, never ahead of v83's kit seat.**
- `vka_com.py`: the weight couple / MaxTorque is at or under main's on 27 of 27 aircraft, for every occupancy × 9 attitudes.
- Absolute trim is Roblox physics. Phone step 6 checks it.

**3. Seated limbs stay inside.** `vk_seatcheck.py` SKIN rule: 77 of 77 seats pass at normal height and with a 0.5-taller avatar.

**4. Aircraft camera caps apply to Part bodies only.** `Drive.ChaseZoom.PartBodyOnly` covers this.

**5. Passenger camera.** 50 of 50 passenger cameras sit outside the body.

**6. Designs are generic.**
- There are no real type names, insignia, flags, roundels or unit numbers.
- Colours are flat Roblox materials, with no textures or decals.
- The Medevac has a red stripe and no cross.

**7. Framework id regex.** This is the ground lane's exact one-line BuyPathStatic text, which `tools/apply_bps.py` asserts.

## New or changed in fix 1c

**8. Helicopters spawn on the helipad deck again (review Medium, option a).**
- New `Drive.Spawn.RotorSlab = { Enabled = true, Modes = { Heli = true }, Margin = 0.5 }`.
- For a helicopter with a main rotor, the spot box has two parts: the hull, from the ground up to the hull top, and a thin slab for the rotor disc from `RotorLow − 0.5` up.
- The disc may therefore pass over the ops hut, fuel tank or windsock, while the hull and the disc must each stay clear. That is how a real helipad works.
- The builder writes `WE_VisualHullHalfWidth / HullHalfLength / HullTop / RotorLow` from the main-rotor (Axis Y) groups. `footprintOf` reads them.
- **6-plot world driver, candidate vs main:** 72 of 78 helicopter spawns are on the same spot as main. The other 6 are the VTOL Transport, which takes deck spot 2, 12.2 studs from main's spot, on all 6 plots. All 162 aircraft spawns are "ok" on both.
- Fix 1b had moved 11 helicopters 32.2 studs, onto the apron.

**9. Planes start with the drawn tail on the runway.**
- `choosePlane` uses HEAD's AIR2 text word for word: `inset = max(RunwayInset, VisHalfZ + 1)`, `spacing = 2 × halfZ + 6`.
- All 84 plane spawns (14 × 6 plots) start 5 to 16 studs further along the runway than main. In fix 1b this was 17 to 28 studs, with the tail past the runway end.

**10. A helicopter spawned with no plot lands beside the land pad, not on it.**
- The Scout's drawn tail would overlap the gate-pad sign (the VScale R2.1 decor-aware check), so the chooser takes the next free spot.
- Source is still `VehicleSpawn`, and the aircraft is `Landed` on clear ground.
- This is the only remaining vehicle-suite difference: `t_server` and `t_server_patched` score 289/290 against main's 290/290 (270 vs 271 unpatched).
- A plot is assigned on join, so this case is rare. It is reversible with `RotorSlab.Enabled = false`, which does not bring the pad back either.

**11. Splash line of sight ignores the drawn shells (review Low).**
- `CombatFeelConfig.Splash.IgnorePartBodies = true`: `ApplyRadiusDamage` adds every spawned vehicle's `WE_PartBody` model to the splash line-of-sight ignore list.
- The kit's collidable parts still block, as on v83.
- **Stand-in driver `vka_splash`:** with the flag on, the shell is left out and the kit is not. With the flag off, the shell blocks as before. Main fails the new check because it has no shells.
- **Still true:** a direct shot at a player standing inside a parked plane's drawn shell hits the shell, and the vehicle takes the damage. This is the same "what you see is what you hit" rule as item 1. Phone step 7 checks the splash.

**12. Seat tops sit on the kit (review Low).**
- Passenger and driver seats were raised:
  - HeavyLift passengers 3.8, driver 3.7;
  - Tilt-rotor passengers 3.6;
  - Gunship driver 3.1.
- `vka_seatkit.py`: 0 of 77 seat tops sit below a collidable kit top. Main has 8 of 77, and fix 1b had 13.
- A pin allows at most 0.1 under the kit top.

**13. Every aircraft has its own airframe (review Medium: the Night Attack was a recolour).**
- **Night Attack Helicopter** has its own family:
  - a mast-top radar dome over a 5-blade rotor;
  - a twin-ball night sensor on the nose;
  - 3 rocket rails per stub wing;
  - endplate fins on the stab;
  - near-black colours.
- Other redesigns:
  - **Rescue:** round cabin with a glass front.
  - **Medevac:** ducted tail fan and fin cap.
  - **Light Transport:** T-tail and blue-grey.
  - **Escort:** 6.0-wide cabin with pods on the skids.
  - **Utility:** 9-wide cabin, fuel tanks and a 2-blade rotor.
  - **Stealth Heli:** V-tail.
  - **Transport:** H-tail.
- A pin checks that every aircraft has its own family (27 families for 27 aircraft).

**14. Silhouette rule (review Low).**
- `tools/vka_sil.py` fails a pair when the colours are within ΔE 30 and either:
  - all three raw IoUs are ≥ 0.85, or
  - the scale-free rear (chase-view) IoU is ≥ 0.80 (area-normalised and centroid-aligned, so size and a mast ball cannot game it), or
  - the 2-pixel-tolerant rear match is ≥ 0.95.
- Result: 0 FAIL over 351 pairs.
- Attack vs Night Attack is now rear(norm) 0.61 and ΔE 25.2 (fix 1b: raw rear 0.74, ΔE 14.4).
- The closest same-colour pair is Transport vs Escort (both olive): rear(norm) 0.78, match 0.94, ΔE 13.9. It is under the thresholds but close.
- This is a lane check, not a BuyPathStatic pin, because it is too slow for the static gate.

**15. The bombers read as bombers (review Medium and Low).**
- The **Strategic Bomber** is a layered flying wing, 30.5 long × 34 span × 9 high:
  - a 41° swept wing with a W sawtooth trailing edge;
  - two thinner blended layers;
  - a crew blister with a glass front;
  - engine humps with slit exhausts;
  - a wide shallow belly with sloped sides over the kit chassis.
  - There are no vertical box walls on the centre body.
- The **Heavy Bomber** is 40.3 × 34.8:
  - a glazed pointed nose;
  - a low wing swept 25° with 4 twin-engine pods;
  - a tall conventional fin and a low tailplane;
  - a tail turret and a dark bomb-bay belly;
  - dark grey-green, no longer the Cargo Plane's layout.

**16. Sizes (review Low).**
- The `Air.luau` SIZE RULE header now gives the measured bands:
  - scout 28;
  - mid helicopters 31-36;
  - transport, stealth and heavy-lift helicopters 38-39;
  - tilt-rotor 26 × 37;
  - jets 28-40 long × 20-31 span. The header does not name the recon prop plane (25.6 long × 32 span); that is a comment-only gap, left out so the gated file stays as tested;
  - flying wing 30.5; heavy bomber 40; swing-wing 42;
  - cargo, radar and tanker 41-44.
- The Cargo (42.2), AWACS (41.2) and Tanker (44.2) are stretched, with length-to-span about 1.2.
- A pin requires at least 40 long for every transport and at least 30 for every bomber.
- **Owner decision:** the real types are about 1.5 × bigger. The span cap of 34 comes from the runway, which sits 18.8 from the inner wall. Bigger heavies need a wider runway, or wings that clip the wall.

**17. On-screen size (review Low).**
- With today's cap (1, 14, 22, 44, Heli +8) at 956 × 440, aircraft are 0.97 to 1.96 × as wide as their v83 kit (median 1.23).
- 4 are cut off at the bottom (LightFighter, CargoPlane, InterceptorJet, VTOL). The narrowest is the Light Transport Heli at 0.97.
- **Owner option:** the reviewer's table (Plane LengthMul 0.85, Add 10; Heli Add 5) gives at least 1.23 × for all 27 (median 1.66), but 23 are then cut off at the bottom. It is left as an owner choice after phone step 5, and it is config only.

**18. Exits are unchanged on this tree.**
- Aircraft use Roblox's jump-out. The stand-in "gets out beside the body" check fails for every aircraft, the same on main and candidate (162 of 162).
- **On the HEAD 4e07fc2 merge:** HEAD's AIR2 `ExitSpot.BodyModes {Plane}` keys on `WE_VisualHalfLength`, which Part bodies set too. So Part-body planes get AIR2's exit beside the wing: 84 of 84 plane exits pass the "beside the body" check on the merged tree.
- Helicopters are unchanged. We recommend keeping this.

**19. Name-list check.**
- The flight driver's nose/tail name lists gained `Searchlight`, `BombBayFwd`, `FinTop` and `BombBayAft`, with a reason for each in the driver.
- The nose-axis check (C) and a reversed body still fail independently.

**20. ASSUMPTIONS.md is not edited in the candidate tree.** This file is for the integrator to merge.
