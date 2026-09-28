## 2026-09-28 — The owner's replacement picture, air rows (jets + rescue helicopters): picks staged, old picks retired, body framework in place but unused (air lane)

_Appended with the air lane's fix round 1 replay (on main 4e07fc2): these AIR-1 to AIR-16 records (the lane's rounds 0
and 1, when the body framework AirBodyRig / AircraftBodyClient was written) were not carried by 4e07fc2, which holds the
framework and AIR2's section above. Entries marked Superseded were overtaken by AIR2 and AIR-17 to AIR-22._

- **AIR-1 Staged as PendingAssetId (never loaded), not promoted.** (Superseded 2026-09-28 by AIR2-2 / AIR2-9 and AIR-17:
  the owner's raw lines arrived; the jet is promoted, the helicopter pick is rejected.) The owner's check on live v83
  (his bot's summary in fb4/OWNER_LIVE_CHECK_v83.md; the raw lines were not attached) chose 14589101870 "Basic Fighter
  jet" (Alecose1) for FighterJet / InterceptorJet / TrainerJet / LightFighter and 9120014090 "Medical Helicopter"
  (TripleTripleTwinTips) for RescueHeli / MedevacHeli. He owns all six ids (inventory API, 2026-09-28). The model files
  cannot be read from here (assetdelivery answers 401 without a Roblox login; 3D thumbnails 403), and the R2.3 body path
  needs every part's box (BodyScale, BodySeats, the cockpit / cabin seats, the nose tip and wing-tip points, the rotor
  parts). A promote without them would put the pilot on top of the body. So both ids wait on HOLD for the raw WE_CHECK2
  lines (or one run of tools/WeCheck2_Replacements.luau: the ground and air ids together). Reversible: the six rows keep
  ModelAssetId = 0, exactly like main. This is NOT the owner's replacement yet: on his phone nothing changes until the
  promote (fix round 1 re-checked the blocker on 2026-09-28 07:04Z: assetdelivery 401 "Authentication required", 3D
  thumbnails 403; no credential is used or sought).
- **AIR-2 The jet pick's outline is close to a well-known real single-engine fighter.** It has no name, markings,
  roundels or text in the store pictures (zoom crops in fb4/air/out/brand), the uploader calls it his own first Blender
  model, it has 0 scripts and 0 decals. That is allowed by the owner's rule (no real names, insignia or markings), and it
  is flagged here so he can decide otherwise. Backup 15024427757 and third 16967628140: not used (107 and 254 parts in his
  check, over the 40-part cap).
- **AIR-3 The rescue helicopter keeps the owner's pick; no usable fallback.** (Superseded by AIR2-9 and AIR-17: the pick
  fails the origin check and neither backup passes; the Part kit stays and the owner is asked for a new pick.) His bot's
  backup is 10077899617 (22 parts, olive, "omit the rocket pods and guns"); it is not used: its own store text says it
  is another version of someone else's model, and it carries rocket pods and guns. The check script still measures it,
  and the owner is told, so he can overrule. The picture's backup 1577255368 was rejected by his bot (a copy of a real
  helicopter) and is no longer checked. The pick has 48 parts; his bot says trim to <= 35, so 13+ parts go by name
  (registry OMIT_TARGET 35), and it has a floating "Medical Helicopter" name sign (the owner's bot: strip it).
- **AIR-4 Registry: the old rows become REJECT history, new rows `<Key>V2` hold the picks (batch P5).** REGISTRY keys
  are unique and the pinned wc3 texts for 3553891209 (OWNER_YES, HOLD, YAW_HINT) and the RescueHeli / MedevacHeli REJECT
  rows stay byte-identical. STUDIO_DONE records the owner's v83 part counts (8, 48); YAW_HINT 180 for both (his summary:
  front along +Z; the game's front is -Z). The helicopter rows are 'STUDIO OMIT'; fix round 1 made the tool count them
  after OmitParts (AIR-14). The status table and `status` show a rejected row's pending column as "–" when a newer row
  waits in the same ref; `status` lists only holds of ids still waiting (3553891209 is shown as a replaced pick) and
  `reject` skips a ref that already waits for a newer pick.
- **AIR-5 The store-aircraft body framework is inert until a ref uses it.** New AssetRef fields BodyAnchor, BodyFloor,
  BodyMounts, RotorParts, ChaseCamera (VisualAssetConfig), tunables in VisualAssetConfig.AirBody, server module
  Server/Modules/AirBodyRig, client module Client/Modules/AircraftBodyClient. No live ref sets any field, so the server
  path returns at once. Stand-in proof (not Roblox): all 86 vehicles build byte-identical on main and candidate (with the
  real jeep-pack files), the 27 aircraft Part kits are identical (647 lines), jeep look 200/200.
- **AIR-6 BodyAnchor moves the body along the kit only (Z), and helicopters should not use it.** Moving the body so the
  cockpit seat lands on the kit seat keeps physics, drive and HUD unchanged. For a helicopter it grows the parking
  footprint (radius 19.9 -> 26.9 with the mock body) and the helipad spots refuse it (it parks at the vehicle spawn), so
  the helicopter refs stay centred and the seats are clamped inside the cabin by BodySeatKitInset.
- **AIR-7 BodyMounts puts a kit weapon mount's FRONT FACE on the body point.** AirWeaponService starts a shot at the mount
  part's front face (+ MuzzleForward), so the muzzle lands on the nose tip / wing rail at every kit scale. Only
  non-colliding, non-seat, non-chassis kit parts move.
- **AIR-8 StripSigns for every store vehicle body.** A store body's BillboardGui / SurfaceGui always goes, its Decal /
  Texture only with StripDecals, for whole models AND pack pieces (fix round 1: a piece loses its decals when the pack is
  split, but not its GUIs, and the trimmed helicopter must be a piece, AIR-14). Nothing live changes: the live
  whole-model refs (Recon Plane, APC) carry none (wc3 check lines: 0), and the live jeep / buggy / van / pickup packs
  keep their only GUIs ("ButtonGuiPrototype") inside LocalScripts, which the loader strips first (stand-in: the
  86-vehicle dump with the real pack files is byte-identical to main). Before this, StripDecals was silently ignored
  for whole-model vehicle refs.
- **AIR-9 Rotors turn on the client only, by a tag contract.** The server gives each RotorParts part a Motor6D named
  WE_RotorJoint (tag WE_RotorJoint, attribute WE_RotorRps); the client sets Motor6D.Transform from 24 precomputed angles
  at up to 30 Hz, only for the 6 nearest aircraft within 400 studs, and only while the driver seat is taken
  (WE_DriverUserId). Nothing is replicated per frame. The VKIT lane (vehicle bodies v2) also spins rotors: the
  integrator keeps ONE loop; the tag + attribute contract lets either side's joints join this loop.
- **AIR-10 Seated chase camera.** (Margin 18 since AIR2-7; fix round 2 keeps the min ChaseCameraSpan under the max,
  AIR-19.) While the local player sits in a vehicle that carries WE_CamMinZoom, their CameraMinZoomDistance becomes
  min(WE_CamMinZoom, their CameraMaxZoomDistance) (WE_CamMinZoom = the seat's reach to the body's far end + 6, capped at
  60); their own value comes back on leaving the seat, death or respawn. Assumed: Roblox's default camera applies a live
  change of CameraMinZoomDistance (real-device check after a promote).
- **AIR-11 Load budget (stand-in census, not Roblox).** Now: unchanged (census_all 54 of 64 attempts, capRefused 0;
  census_fail BOOT 41 / PLOT 43 / LATER 50, capRefused 0 through LATER, 16 in PREFER / UPPER as on main). With both
  picks promoted the way they now must be (fix round 1 projection on a scratch copy: the jet as a whole model, the
  helicopter as a ChildName pack piece + OmitParts): census_all 56 of 64, capRefused 0; the helicopter pack is asked at
  BOOT (every configured pack is; BOOT 15 -> 16 ids), the jet first in LATER; census_fail BOOT 41 / PLOT 43 / LATER 51
  attempts, capRefused 0 through LATER, PREFER / UPPER 5 / 17 (main 4 / 16). (Round 0's whole-model projection had both
  ids in LATER; a 48-part whole model would be refused at load, AIR-14.)
- **AIR-12 Recorded only:** VisualAssetConfig has both StealthStrikeJet (no VehicleConfig key: a dead ref) and
  StealthStrike (the real key). Not in this lane's families; left as is.
- **AIR-13 (fix round 1) One owner check script, committed: tools/WeCheck2_Replacements.luau.** (Fix round 2: the owner
  is no longer asked to run it or to resend lines; his raw log is in. The file stays as the ground lane's shared file.)
  It replaces the lane-only WeCheck_Air.luau and the ground lane's WeCheck2_G1.luau. The file is byte-identical to the
  ground lane's fix-round-1 file (md5 88057bb1612b31e65cd2828dbc77fabc: its open ground ids 1578555399, 14423269703 and
  this lane's air id lines 14589101870, 9120014090, 10077899617 verbatim), so the two lanes add the same file. If the
  ground lane changes it again, take the ground version: the air lines are the same. The owner is asked for the raw
  lines of his v83 run first; the script is only the fallback.
- **AIR-14 (fix round 1) A trimmed store body must be a pack piece.** VisualAssetService counts a whole model's parts at
  load (loadModel: > MaxPartsPerModel is refused) before any OmitParts; OmitParts trims before the count only when a pack
  is split into ChildName pieces (extractPiece). Stand-in proof (air_body section E, main and candidate alike): a 48-part
  whole model + OmitParts is refused, the same 48 parts as a ChildName piece + OmitParts load with 8. So the helicopter
  promote writes ChildName = its inner model's name + OmitParts. wire-asset-ids.py promote now: an OMIT pick over 40
  needs ChildName on every target and the id's complete WE_CHECK2 part lines in the --we-check file; the parts the
  loader keeps (no x=1) minus the OmitParts names must be <= 40 and <= OMIT_TARGET (35 for 9120014090, the owner's bot).
- **AIR-15 (fix round 1) Phone cap for one vehicle body: VisualAssetConfig.VehicleBodyMaxTriangles = 20000** (Creator
  Store triangle count, whole model; a pack counts in full, so it errs high). A tool gate only (a script cannot read a
  mesh's triangle count); promote refuses a vehicle body above it unless --heavy-ok ID / HEAVY_OK (the lead's call), and
  then the owner's phone test carries a frame-rate step with two or more in view at Graphics Quality 3 / a mid-range
  Android. The jet pick (11,460) passes; the helicopter pick (65,837) needs that call. Live bodies are far under it
  (Recon Plane 738, APC 3,314). Reversible: one config number; 0 or deleting the line removes the gate.
- **AIR-16 (fix round 1) Not claimed as the owner's fix.** (Superseded by AIR2-13 and AIR-21.) The owner text says
  plainly that nothing changes in the game yet and why; the change note for this commit must not say the jet / rescue
  helicopter replacements are done.


## 2026-09-28 — Air fix round 2 (replayed on main 4e07fc2): all six air ids decided from the owner's raw lines, rotors scoped by parent, seated zoom span (air lane)

- **AIR-17 Per-id decisions (all six from his raw v83 log, fb4 wc4_all_raw.txt, `parse_we_check2.py --strict`: 0
  problems; creators from Roblox's public economy API, 2026-09-28, no credential).** Jet: PICK 14589101870 passes (8
  loader parts, 0 scripts / decals / Humanoids, all 8 meshes uploaded by the seller 11 minutes before the model) and is
  live on the four fighter keys (AIR2-2). BACKUP 15024427757: 107 loader parts (cap 40), 8 scripts, 4 tools, meshes by
  other creators too (FatFitFut; a Roblox missile mesh). 3rd 16967628140: 254 loader parts, 13 scripts, meshes by two
  other creators. Rescue helicopter: PICK 9120014090 fails the origin check (AIR2-9, re-queried here: the same 14 mesh
  and paint ids, all by JaimeEsP, 2020-03-02/03). BACKUP 1577255368: 53 loader parts (cap 40), 20 scripts, 5 SurfaceGuis
  and 5 BillboardGuis, and its inner model is named after a real maker's helicopter (the check's MODEL line); his bot
  also rejected it as a copy of a real helicopter. 3rd 10077899617: a Humanoid (HumanoidRootPart, Head, Torso; hum=1: a
  catalog body must have none), 8 scripts ("Helicopter AI"), weapon parts named after real weapons, meshes and paint
  from four other creators (one paint image is named after a real helicopter type), and its store text says it is
  another version of someone else's model. So no helicopter passes: RescueHeli / MedevacHeli keep the Part kit and the
  owner is asked for a new pick (made by its uploader, <= 35 parts, no weapons). Reversible: config Notes + registry rows.
- **AIR-18 RotorParts.Under: rotor parts scoped by their parent Model; a part is never jointed twice.** Store helicopters
  often name every rotor piece alike (9120014090: "MeshPart" for the 6 main-rotor pieces under Rotors/Rotor1 and the
  tail rotor under Rotor2, "Spinner" for both hubs). AirRotor.Under = an ancestor Model name: only parts inside such a
  Model spin, each such Model is its own rotor with its own Hub (looked up inside it) or average centre; a part that
  already carries a WE_RotorJoint is skipped by later specs. Stand-in (air body driver F, a proxy of 9120014090 built
  from his P lines with its real names and parents, BodyScale 0.7): Under = Rotor1 / Rotor2 gives 7 joints (6 + 1),
  one per part, main blades 0.05 studs off the mast, the tilted mast pieces 0.32, the tail rotor 0.00 off its own hub,
  axes up / across. Fix round 1 gave 14 joints (two per part), the blades 1.05 and the tail rotor 17.2 studs off
  (orbiting the helicopter). Without Under the tail rotor still orbits the main hub (16.7): shared names need Under. No
  live ref sets RotorParts, so nothing live changes.
- **AIR-19 Seated zoom span (AirBody.ChaseCameraSpan = 8).** Another lane (vehicle bodies v2) lowers
  CameraMaxZoomDistance while driving a big body (its cap, clamped at or above the current min). With this lane's raised
  min the two could pin min = max, and pinch zoom would do nothing on a phone. The seated min is now max(own min,
  min(WE_CamMinZoom, max - span)) and is re-checked whenever the max changes while seated; leaving the seat, or dying in
  it (D-z5), drops the watch before the own min comes back. Stand-in (driver D: the mock helicopter, WE_CamMinZoom 41.9;
  the other lane's formula simulated with a cap of 31.9): cap after seating: min 33.9 / max 41.9; cap before seating:
  min 23.9 / max 31.9; leaving in either order restores 0.5 / 128 (fix round 1: min = max in both orders). Merge note:
  keep ONE owner of the seated aircraft camera if both lanes land. That lane's latest client also raises a PASSENGER's
  CameraMinZoomDistance (its passenger zoom, saved and restored by that module). With this module doing the same for the
  same seat, whichever saves second saves the other's raised value as the player's own and may restore it last, so a
  phone player could stay zoomed far out after standing up (stand-in D-z6, that lane's formula simulated on the
  helicopter proxy: 2 of the 4 sit / stand orders leave the minimum at 41.9 or 47.9 instead of 0.5). So when that lane
  lands, one module owns the seated minimum (fold WE_CamMinZoom into its zoom rule with its cap >= WE_CamMinZoom + span,
  and drop this module's chase camera), then re-run sit / stand / die / respawn for a driver and a passenger (the
  player's own 0.5 / 128 back each time). Main 4e07fc2 has no other writer of either property; the span keeps pinch zoom
  working until then.
- **AIR-20 Helipad room for a real-size helicopter (a record for the next pick).** A proxy at the owner's pick's real
  size (50.2 x 17 x 54.6, rotor disc 50; the round-1 mock was 32 x 9.4 x 39.7) parks on his helipad up to BodyScale 0.9
  (footprint radius 24.6); at 1.0 (radius 27.3) the helipad spots refuse it and it starts at the vehicle spawn. So a
  new helicopter pick of that size needs BodyScale <= 0.9 (or larger helipad spots). Helicopter refs stay centred
  (AIR-6).
- **AIR-21 One air candidate, rebased on main 4e07fc2 (fix round 1 replay).** AIR2's final tree (its fix round 2) is
  in main as 4e07fc2, so this lane's remaining change is a small delta on top of it (out/air_over_4e07fc2.patch: the
  rotor scope, the zoom span, the rotor-joint diagnostic, their pins and these records). The e506c9c candidate is
  AIR2's final lane tree plus the same delta, for the gates against e506c9c. Commit the delta on main; nothing of AIR2
  is applied twice. The change note may say the owner's jet is in; it must not say the rescue helicopter replacement
  is done (AIR2-13).
- **AIR-22 A rotor joint is not a "pin".** VehicleService's NO-DRIVE diagnostic (countPins) no longer counts
  WE_RotorJoint motors (diagnostic text only; no behaviour change).
