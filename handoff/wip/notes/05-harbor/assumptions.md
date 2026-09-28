# fb4 HARBOR: assumptions (all reversible)

For ASSUMPTIONS.md. Owner request, 2026-09-28: "The default boat in the dock looks terrible, make it look like a real
boat" and "The building beside the dock same thing should look like a legit dock building".
Fix round 1 changes are marked (R1), fix round 2 changes (R2), fix round 3 changes (R3).

## H1. "The default boat" and "the building beside the dock" are the Dock structure's Part kit
- These are the 5-block parked boat and the grey shed/pier in `StructureKitBuilder` kit `"dock"` (v35/v37).
- Every plot builds the same kit at the Dock site (78, -112), Yaw 90. I checked all 6 plots, L0 to L5.
- The boats a player takes out to drive (VehicleService naval kits and their catalog bodies) are not changed by this
  lane. They are separate work. (R2) The VKIT NAVAL lane may change them in the same release, so the owner texts no
  longer say they "look the same as before".
- Revert: set `DockKitConfig.Enabled = false`. The old v35/v37 kit code is still there, unchanged, below the new branch.
  (R1) This rollback now passes BuyPathStatic as it is: the pin accepts `Enabled = true` or `Enabled = false`
  (R2: mutant M8 shows PASS 4328 / FAIL 0 with `false`). Deleting the line or setting it to anything else fails the pin.

## H2. Own Part kit, not a store model or mesh
- (R1, reworded to what was actually searched)
  - Creator Store search, creator Roblox (User 1) only: the earlier harvest (`ownervis/assets_work/search_roblox.json`,
    Model + MeshPart, 2 pages each) already covered warehouse, dock, harbor, cargo, shipping container, container,
    crate, tower and bridge. It found no Roblox-made harbour building, crane or container.
  - This lane added 17 more keywords (boat, ship, yacht, speedboat, patrol boat, tugboat, ferry, pier, harbour, port,
    marina, boathouse, crane, lighthouse, dock, harbor, warehouse), Model + MeshPart, first 100 results each
    (`work/research/roblox_harbour_search_r1.json`). The only Roblox-made boat is 50504 "Boat for Sale", a 62-triangle
    sign prop with a decal. "port" only returns portal templates.
  - Of the 113 live-pack pieces documented in the earlier harvest (`facts.json`: City, Dungeon, Nature and Goblin camp
    packs), none is a boat, pier, crane or warehouse. The only harbour-like pieces are Dungeon-pack crates.
- The owner's earlier gunboat pick, Basic Gunboat 15838664806, was not tried. The wc3 check found its MainHull (the
  boat itself) is 2,048 studs, about 146 times Roblox size, and the vehicle body fit clamps at x0.05. Using it needs a
  per-model scale floor in VisualAssetService, which belongs to the vehicle lanes. It would also hang a catalog mesh
  on a structure kit (PreferMesh stays OFF for structure kits) and add a load attempt. The wc3 decision was HOLD; it
  stays HOLD. (R2) owner_text now tells the owner that his pick stays on hold and why.
- So the kit is plain Parts: 0 new asset ids and 0 new load attempts.
- (R2) Option (c), other creators' free store boats, was not researched. Each would need full provenance checks
  (creator, scripts, texture text, insignia, owner ownership) and a new load attempt; the Part kit was chosen instead.
- Nothing in it names or copies a real vessel, brand or navy. The boat has no numbers, flags or insignia.

## H3. New kit role "Styled"
- Each piece keeps its own colour, material, size and position.
- `BaseService.applyKitVisuals` only shows a piece from its `WE_MinLevel`, and gives it collision (`WE_Collide` =
  CanCollide + CanQuery) and `WE_Shadow`.
- Each piece is built once, hidden, with the kit. A purchase creates and destroys nothing.
- All writes are compare-first, so a purchase changes only that level's parts. Measured (R1):
  - L0 to L1: 56 changes. After that: 16, 13, 7, 6.
  - The target is 60 or fewer.
- (R1) All four compare-first writes (Transparency, CanCollide, CanQuery, CastShadow) are now pinned inside the Styled
  branch. Deleting any one of them fails BuyPathStatic (mutants M12, M17, M18, M19).
- The old roles (Body, Roof, Detail, Pier and the rest) behave exactly as before.
- (R2) Unchanged by round 2 (same pieces, only heights moved): 56 / 16 / 13 / 7 / 6 on the candidate against 33 / 16 /
  16 / 16 / 17 on main; idle re-sync 0 on both.
- (R3) 57 / 16 / 13 / 7 / 6 (the L1 step shows one more part, the split bulwark, H19); main 33 / 16 / 16 / 16 / 17; idle
  re-sync 0 on both.
- (R3) Transparency is a float32 property, so the Styled branch now compares it with a tolerance
  (`math.abs(child.Transparency - tr) > 1e-3`). Today every piece is 0 or 1, so nothing changes; a future 0.3 piece is no
  longer rewritten on every sync. The pin requires the tolerance form (mutant M51 fails).

## H4. The quay shows at L0
- The quay is a paved apron from the Dock gate lane to the basin kerb, with 4 bollards and an edge line.
- Like the basin and its kerb, it counts as base infrastructure, so an unbought Dock already has a walkable quay.
- It is 1 colliding part, top 0.4 studs above the pad, ending at the kerb.
- Everything else shows from L1 (warehouse and boat) up to L5.
- Revert: set `MinLevel = 1` on those 6 rows.

## H5. The moored boat and the warehouse are solid
- The warehouse, roof, hull, wheelhouse, gangway, crane pedestal, tower, containers and launch hull have collision and
  can be queried.
- The gangway is solid, so a player should be able to walk up it onto the boat's aft deck. This needs a device check;
  the stand-in does not simulate walking.
- A driven boat's land probe treats the moored hull like the kerb, as land. Driven boats spawn at kit z 34 or more
  (R1: checked on all 6 plots, 150/150 naval spawns clear by at least 1 stud, lane to the sea gate clear).
- Every colliding piece stays at kit z 33.5 or less. (R1) No piece of any kind (decor included) reaches past kit z
  33.5 any more, and a pin checks it.
- Decor pieces (rails, lines, lamps, windows) have CanCollide, CanQuery and CanTouch off.
- (R3) Because the moored hull is land to a driven boat's shore probe, a boat driven at it slows and stops about its
  half length + 3 studs short, as at the quay edge; it never touches it. Phone step 7 now says so (it said "bump it").
- (R3) The warehouse, roof, gables, crane pedestal, tower and containers are solid and queryable, so the normal Roblox
  camera moves in close when one of them comes between the camera and the avatar (the Town lane made the same choice).
  Phone step 5 now says so (it said the camera "should not jump").
- (R3) UpgradePadService's pad re-harden sweep no longer switches these pieces' CanQuery off (H17).

## H6. Hidden hosts kept for EnsureKit
- `EnsureKit` needs a `Body` (largest side 8 studs or more) and a `WE_DressHost*` child on the Dock, or it rebuilds the
  kit every pass.
- The kit keeps a Body (a concrete core at the warehouse footprint) and a hidden `WE_DressHost_ParkedBoat`.
- (R1, comment corrected) From L1 the Body sits inside the warehouse block, so it is hidden. At L0, before the
  warehouse shows, it is the Dock's usual translucent footprint ghost, like every unbought structure's Body. Main's
  v35 dock shows a 24 x 1.4 x 16 ghost at L0 too.
- The host has no `WE_DressVehicle`, so no catalog boat is ever hung on it. `census_all` attempts are unchanged (54).

## H7. The warehouse chimney is named "Roof"
- `BaseService` hangs every structure's L5 smoke plume (`WE_MaxSmoke`) on the kit child named `Roof`. The old dock had one.
- The harbour's only `Roof` is a small brick chimney (MinLevel 5, decor), so the Dock keeps its L5 smoke like main does.
- A BuyPathStatic pin guards this.

## H8. A released plot's kit stays as main leaves it
- Nothing changes in plot release or rejoin logic.
- A rejoin rebuild (`NuclearRehydrateKits`) re-creates the Dock kit along with every structure, as it does on main.
  (R1) That is 406 creates plus destroys for the whole plot, against 280 on main. It is not a purchase.
  (R3) 408 with the split bulwark.
- A saved Dock jumping from L0 to L5 in one sync is 90 changes (main 34). It is not a purchase either. (R3) 91.

## H9. Materials: real Enum.Material names only
- An earlier draft used `Enum.Material.CorrugatedPlate`, which does not exist. The headless stand-in accepted it; Roblox
  would error when the config is required. luau-lsp caught it.
- All such pieces now use `Metal`.
- A BuyPathStatic rule fails any piece material that is not a real Enum.Material name. (R1) The list now holds every
  real name, Neon included, so a Neon piece is reported once, by the no-Neon rule, and not also as "unknown".

## H10. Part budget
- (R1) +63 parts per base at L5: 87 kit parts against the old 24. That is 2,547 → 2,610 on all 6 plots, under the
  2,700 hard cap (90 parts of headroom) but above the 2,000 target.
- (R3) +64 per base: 88 kit parts (86 pieces + the hidden Body and boat host); the split bulwark (H19) is the extra part.
  Census on all 6 plots, L1 to L5: 1,643 / 1,815 / 2,290 / 2,519 / 2,611 (main 1,579 / 1,751 / 2,226 / 2,455 / 2,547).
  Headroom to the 2,700 cap at L5: 89.
- Lights, Neon, SurfaceGuis and billboards are unchanged: no light, no Neon, no GUI and no text in the kit.
- If the phone-performance pass needs the parts back, these decor pieces can go first with no gameplay effect
  (13 parts):
  - lamp posts and heads (4)
  - mooring lines (2)
  - bow rails (2)
  - fenders (3)
  - boat stem and rubbing strake (2)
- The integrator should re-run `census_all` on the merged tree: other lanes also add parts per base.

## H11. (R1) The crane stands at the sea-gate end of the quay
- Round 0 hung the crane's jib, cable and hook over the open basin (kit z 37.5, hook 8 studs up), where driven boats
  sail through them (decor, so no collision, but visible clipping).
- The crane now stands at kit x 22 (was 18). Its jib is luffed up over the launch's berth: tip at kit z 29.4, 20.6
  studs up; the hook hangs 15.4 studs up. Nothing is past kit z 33.5.
- Moving it to x 22 also freed the quay lane in front of the warehouse, so a car called there fits again (H13).
- Two pins guard this: no piece of any kind past kit z 33.5, and the crane's hanging parts over water stay 14+ studs up.

## H12. (R1) Boat side profile
- From side-on the round-0 hull read as a flat box. Two decor parts were added:
  - a black raked forefoot wedge under the bow overhang (the black waterline band sweeps up toward the bow)
  - a black rubbing strake round the hull just under the deck edge (a sheer line along the flat side and stern)
- The bow rails now rise 0.35 studs toward the bow (no new parts).
- The L1 level-up shows 46 parts (56 changes), still under the 60 target. (R3) 47 parts, 57 changes.

## H13. (R1) Land vehicles called at the quay
- The owner at home never gets a car at the quay: the garage flow uses the base's vehicle pad (12/12 on main and on
  the candidate).
- A visitor from another base who calls a car while standing on the quay uses VehicleService's "in front of the
  player" path. On all 6 plots, 4 facings, jeep and truck (48 calls): every car lands on dry ground, clear of every
  dock solid, on both trees.
- The new buildings take quay space, so fewer of those calls land at the dock: 36 of 48 on the candidate, 42 of 48 on
  main. The 6 that differ are the truck facing the sea-gate end: the crane pedestal (L2) and the control tower (L3)
  leave no truck-sized spot there, so VehicleService puts the truck on the nearest vehicle pad, as it always does when
  no spot in front of the player is free. The jeep in the same spot still lands at the quay. VehicleService is not
  changed.
- The driver now also covers the case where a jeep facing the warehouse landed, on main, where the warehouse now
  stands. On the candidate it lands beside the warehouse's gable end instead.
- (R3) Kept as is (re-measured: 36 of 48 on the candidate, 42 of 48 on main, every car on dry ground and clear of every
  dock solid). Freeing a truck-sized spot at the sea-gate end would mean moving the crane or the tower back into the
  quay lane in front of the warehouse, which round 1 cleared on purpose. It only affects visitors calling a truck there;
  the owner's own calls always use his vehicle pad.

## H14. (R2) Low props rest on what is under them
- Round 1 set the height of every low prop as if it stood on the quay (top +0.4). Six props stand landward of the quay
  (kit z < 4), on the bare pad, so they floated 0.4 studs up: the lower cargo crate, both fuel drums, both ground
  containers and the gable-end warehouse door (reviewer finding). The stacked crate and the stacked container sat on
  the lower ones, so they were 0.4 too high with them.
- Round 2 lowers them by 0.4 (crate 1.6 -> 1.2 and stacked 3.8 -> 3.4, drums 1.5 -> 1.1, containers 3 -> 2.6 and stacked
  8.2 -> 7.8, gable door 3 -> 2.6). No part count change.
- Evidence: a support scan of the plot-1 L5 dump (work/support_scan.py: every visible Dock part, is there a surface within
  0.06 under its bottom) goes from 32 to 26 parts without one; the 6 removed are exactly those props. The 26 left are
  mounted or hanging by design (windows, glass bands, lintel, vent, radar bars, lamp heads, crane jib / hook /
  counterweight, gun barrel, life ring, rub strake, mooring lines, launch parts floating on the water).
- A BuyPathStatic rule now checks every low block piece (bottom under +1, not a beam, not the QuayDeck): its centre on
  the quay -> bottom at the QuayDeck top (+0.4); landward of the quay -> bottom at 0 (both +-0.02). 21 pieces checked.
- Revert: the Y values in out/round0/round1 DockKitConfig (work/r1_snapshot).

## H15. (R2) The moored boat's wheelhouse is at player scale
- Round 1's wheelhouse was 3 studs tall over the deck, so a 5-stud avatar standing aboard (phone step 3) had the cabin
  roof at chest height and the boat read as a toy.
- Round 2 makes it 6 tall (deck +2.4 to +8.4) with the same footprint, a taller window band at +6.3 to +7.8 (eye line),
  the roof on top (+8.55) and the mast, radar bar and mast light 3 studs higher. The life ring moves up 0.6 to chest
  height. No new parts.
- The crane jib (kit x 21 to 22) is not over the boat (x -10 to 13). No spawn, lane or exit result changed (harbor_boats
  output identical to round 1). Rider exits beside the moored boat are not driven by a test: reading
  VehicleService._ExitSpot (down-ray from the wheel line + 2.5, a 5.2-tall stand box), a spot over the wheelhouse is
  refused by the stand box, as it was over the 3-tall wheelhouse, so the change should not add exit spots. Device check.
- A BuyPathStatic rule checks it: wheelhouse on the hull's deck line, >= 5.5 tall, window band >= 3.5 over the deck,
  roof on the wheelhouse, mast on the roof.
- Revert: Size.Y 3 / Pos.Y 3.9 and the four rows above it back to round 1 (the pin must then be relaxed).

## H16. (R2) Wider pin coverage
- The reviewer showed 7 mutants that wreck the harbour but still passed BuyPathStatic. Round 2 adds 13 pins, each
  shown failing on a mutant (work/mutants_r2.log, M23 to M43):
  - inside styledPart (function-scoped, because kitPart has its own `p.Parent = plinth`): the lift onto the pad top,
    both beam ends lifted, the block CFrame with its rotation, the WE_MinLevel / WE_Collide / WE_Shadow /
    WE_BaseTransparency attributes, `p.Parent = plinth`;
  - buildStyledDockKit loops over cfg.Pieces with styledPart;
  - the table's `Name = "` count equals the one-line rows the rules read (a multi-line row no longer skips them);
  - the load-bearing pieces collide: QuayDeck, WarehouseBlock, BoatBoot, BoatHull, BoatForecastle, BoatWheelhouse,
    Gangway;
  - H14 (nothing floats) and H15 (wheelhouse scale).
- Pin count: 36 in the block (was 23). Main + block: 4292 PASS / 23 FAIL; candidate 4328 / 0.
- (R3) 41 checks in the block (5 new, 1 changed; H17 to H20). Main + block: 4292 PASS / 26 FAIL (every harbour check fails
  on main: 24 code pins, the Enabled line and "DockKitConfig.Pieces rows not found", which stands for all the row rules);
  candidate 4333 / 0. work/mutants_r3.log re-runs all 58 mutants (M1 to M56 plus M8b and M8c) on the round-3
  candidate: each fails its pin (PASS 4333 -> FAIL 1 to 3), except M8, the documented rollback, which passes 4333 / 0.

## H17. (R3) The pad re-harden sweep leaves the harbour's solid pieces queryable
- `UpgradePadService.hardenPad` runs on every already-attached upgrade slot (its +1 s sweep after Init, the zero-pad
  rescans and a slot re-tag) and set `CanQuery = false` on every BasePart under the pad. On main every kit part is
  CanQuery false anyway. The harbour's 27 solid pieces need CanQuery true (vehicle spawn clearance, the boat shore
  probe, the camera), so a sweep that landed after the Dock kit was built switched them off until the next Dock
  UpdateVisuals (reviewer finding).
- The fix is one condition in hardenPad: a part with `WE_KitRole == "Styled"` is skipped (it is built CanTouch false and
  BaseService owns its CanCollide / CanQuery). This makes UpgradePadService.luau the lane's fifth file.
- Evidence (drv/harbor_pad.luau, 6 plots, Dock L5, then UpgradePadService.Init and its +1 s sweep): round 2 went from
  CanQuery 27 of 27 to 0 of 27 after the sweep; round 3 stays at 27 of 27 after the sweep, after the next sync and after
  a slot re-tag. (In the stand-in the re-tag step does not re-run hardenPad on round 2 either, so only the +1 s sweep is
  evidence.) A pin checks the condition; mutants M52 (main's hardenPad) and M53 (wrong role) fail it.
- Merge: no other fb4 or VKIT lane's candidate tree changes UpgradePadService.luau, BaseService.luau or
  StructureKitBuilder.luau (checked against every lane tree on disk).
- Revert: drop `and child:GetAttribute("WE_KitRole") ~= "Styled"`; the pieces then get CanQuery back only at the next
  Dock UpdateVisuals.

## H18. (R3) The showroom spin loop no longer walks every kit part on every server frame
- `BaseService.ensureShowroomSpin` ran on every server Heartbeat: `GetChildren()` of every upgrade slot plinth, then
  `IsA` and `GetAttribute` on each child, to find the few spinning showroom displays. The Dock plinth now holds 88 kit
  parts instead of 24, so the harbour made that per-frame scan bigger (reviewer finding; CLAUDE.md: no whole-tree scans
  or allocations per frame).
- Now the loop re-scans the slots twice a second and, each frame, only turns the displays it found (still 22 deg/s and
  only while shown, Transparency < 0.5). A newly built display starts turning up to 0.5 s later.
- Measured (drv/harbor_pad.luau, 6 plots owned, 114 slots, 180 Heartbeats fired by hand):
  - main: 654 children visited per Heartbeat, 180 scans in 3 s (about 39,000 visits a second at 60 Hz);
  - round 2: 1,032 per Heartbeat (about 62,000 a second);
  - round 3: 1,038 per scan, 6 scans in 3 s (about 2,100 visits a second).
  - A probe display turned 66 degrees in 3 s on both main and round 3.
- Two pins check the throttle and the per-frame loop; mutants M54 (main's loop), M55 (scan every frame) and M56
  (hidden displays turn too) fail them.
- Revert: main's ensureShowroomSpin body (out/round0/round2 has no copy; take it from e506c9c).

## H19. (R3) The boarding ramp is clear
- Round 2's aft fender (kit x -7) stood about 0.3 studs proud through the gangway's walking surface, and the ramp ran
  under the quay-side bulwark (decor, so an avatar's legs passed through it) (reviewer finding).
- The aft fender moves to kit x -5.5 (fenders now at -5.5, -1 and 4.5). The quay-side bulwark is split into two pieces
  (x -10 to -8.6 and -6.4 to 3), leaving a 2.2-stud boarding gap where the gangway comes aboard. That is 1 more part
  (86 pieces, 88 kit parts per base).
- A new rule checks the gangway's walk space: over its walking surface, its width, from 0.05 to 5 studs up, nothing
  pokes through except what the ramp rests on (quay, hull, boot-top, strake, deck). Mutants M48 (round-2 fender), M49
  (round-2 bulwark) and M50 (the whole round-2 config) fail it.
- Still for the device check: the ramp meets the hull side about 0.2 studs below the hull top (+2.2 against +2.4; the
  deck top is +2.52), a small lip an avatar steps over (phone step 3).

## H20. (R3) Solid pieces stay off the land lanes
- A new rule: every solid (Collide) piece stays inside kit x -48 to 34 (the QuayDeck's span: the Dock gate lane is at
  x <= -48; the sea-gate guard (38, 20), the sandbag berm (38, 2) and the sea-gate lane land are at x >= 35) and at
  kit z >= -20 (the helipad is at z <= -24). 27 solid pieces pass.
- Mutants fail it: M44 a crate at the sea-gate guard spot (the reviewer's mA), M45 a crate toward the helipad, M46 a
  crate in the Dock gate lane, M47 the solid gangway moved onto the sea-gate lane land.

## H21. (R3) Checked with the VKIT NAVAL candidate as it is now
- harbor_boats on a copy of the VKIT NAVAL lane's current candidate plus this lane's four .luau files: 564 pass / 0 fail,
  150 of 150 naval spawns in their own basin, clear of every dock solid, with a clear lane to the sea gate; visitor
  cars 36 of 48 at the dock (the same as this lane alone). The naval lane is still in progress, so the integrator
  re-runs drv/harbor_boats.luau on the final merged tree.
