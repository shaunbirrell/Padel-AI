<!-- GROUND2 lane: the G2 section appended to ASSUMPTIONS.md (exact copy; append once after the G1 section).
     Fix round 1: G2-1 and G2-6 extended, G2-12 added.
     Fix round 2: G2-2 names no game franchise; G2-5 has no bare owner override (proof of origin + a fresh origin check);
     G2-10 (script comments say RETIRED); G2-12 conditional on an approved VKIT GROUND + MERGEDCHECK PASS. -->
### G2 (ground lane, 2026-09-28): the owner's raw WE_CHECK2 lines for the truck and Fuel Tanker picks
- **G2-1 The raw log is three runs, and only the last has a DONE line.** Run 1 asked 12 ids and printed 6, run 2 asked
  the other 6 and printed 4, run 3 asked the last 2 and ended with `DONE ids=2 ok=2`. Every id has its own END line with
  the right line count, so no id is cut. tools/parse_we_check2.py now reads several runs (a stopped run is accepted when
  the next run asks for as many ids as it did not finish: a count check, because ENV carries ids=N and no id list; an id
  printed twice with an END each, or a total that differs from run 1's ids=N, is still flagged; an id cut half-way keeps
  its re-run; all runs must share creator, place, server and studio). `--strict` gives 12 ids, 0 problems. Reversible:
  the single-run path is unchanged. The ENV lines report place version 79 (`ver=` is game.PlaceVersion); the owner calls
  the release v83. The model checks do not depend on it.
- **G2-2 Fuel Tanker 1578555399: REJECT (origin).** The economy API gives the creator of all 24 mesh ids in its P lines
  as AnathielSage (user 20637947, uploaded 2018-01-21 to 2018-03-24); the model's seller is infantryd (2018-04-03).
  The recipe's rule (every mesh= / tex= creator must be the model's own uploader) fails for 24 of 24. AnathielSage's own
  store models are game-franchise items and real-vehicle replicas, so the original is not
  usable either. The Part kit stays; the owner is asked for another tanker.
- **G2-3 The "14.4-stud width" is a rotated box.** All 24 parts and the pivot carry r=0,-72.38,0. In the pivot frame the
  tanker is 23.01 long x 9.10 tall x 7.79 wide (MODEL bbs); the world box 14.38 x 24.29 is that box turned 72.38 deg
  (23.01 cos 72.38 + 7.79 sin 72.38 = 14.39). Its front (one front axle, the windscreen and cab parts) is the pivot's +X,
  (0.30, 0, 0.95) in check axes: "front +Z" holds only to 17.6 deg. Our fit (fitBodyToKit) measures the world box and
  turns it by ref.Yaw, so the recipe's Yaw 180 would have left it 17.6 deg skew and 14.4 wide on the 8.1-wide kit; a
  hand-set Yaw 162.38 (promote --yaw takes whole degrees) would have been needed. Recorded for the next pick; moot now.
- **G2-4 Tanker backup 17497975440: REJECT (origin).** Its 27 trailer meshes are by Duck_Blox (2021), its cab body and
  glass mesh + paint by crabbyninja (2018, "flatnose_truck"), and its mud-flap decal 7682142977 by Preauri; the seller is
  caleb244567 (2024). 3284598659 stays rejected (a copy of a real army tanker; its main model is named after it).
- **G2-5 Truck backup 14423269703: REJECT (a replica of a real army truck with game-studio texture naming; origin
  unproven).** It passes the creator check: its one mesh (14423211200) and paint (14423260267) were uploaded by the
  seller I_Homeless, and the paint (thumbnails API, 700 px, crops in out/brand) shows no text, badge, star, unit code or
  face. It is rejected for another reason: the paint's asset name names a real army truck model (the name is kept out of
  repo text; it is in the G2 lane evidence), so the model is a replica of that truck, and the name follows a game
  studio's texture scheme (T_<material>_<model>_DIF), not a hobbyist's: the paint looks taken from another game. The
  mesh render (thumbnails API) matches that truck. The owner's own bot rejected 3284598659 and 1577255368 as copies of
  real vehicles; this is the same class. With the uploader's pattern (3 uploads in one weekend, one a photo-textured head
  of a real celebrity) its origin cannot be shown, and CLAUDE.md forbids copying another game's assets. **Not reversible
  by a yes alone** (fix round 2): it can come back only with proof of origin (the uploader's own source files, or a
  licence that allows it) AND a fresh origin check run just before the promote (economy API creator of every mesh= /
  tex= id, thumbnails for text, badges, stars, unit codes, faces). Until then RETIRED keeps it out and promote refuses
  it, whatever OWNER_YES or --owner-ok says (pinned). Kept for that case only: BodyScale ~0.5 (25 x 10.8 x 10.1), front
  +Z per the owner's bot (not verifiable from one part line), 8,492 tris.
- **G2-6 The six truck keys stay REJECT 9803446425** (the owner's primary pick) with the reason extended to the backup;
  244269478 stays rejected (116 parts; built by another user). The raw lines add one fact: 9803446425's 7 meshes were
  uploaded by a third user in 2017 and its 2 paints (named after a real army truck) by a fourth user in 2016, so neither
  9803446425 (2022) nor the older upload 3981575567 (2019) is the original. No store truck goes in (G2-12).
- **G2-7 RETIRED table in tools/wire-asset-ids.py** lists every ground id that must never come back, with why:
  1578555399, 17497975440, 3284598659, 14423269703, 9803446425, 3981575567, 244269478, 8546141386, 5318635087.
  resolve_ids refuses a retired id even if a row or batch names it again (the HOLD lines for 1578555399 and 14423269703
  are gone: nothing is waiting). OWNER_YES / YAW_HINT keep their 8546141386 history (they act only through a row).
- **G2-8 Duplicate search, mesh level:** 18 toolbox MeshPart queries (1,150 distinct MeshParts) found no other MeshPart
  using any of the three candidates' mesh or texture ids; the G1 model-level search (8,992 models) found no exact
  triangle/vertex match for 1578555399 or 14423269703. Neither result helps them: the rejections rest on the creator
  records and the paint name.
- **G2-9 Nothing goes live, so no BodyScale / BodySeats / Yaw / KeepVisible / DriveAtComX / ASSET_LICENSES row** is
  written. The measured kit facts for the next pick (stand-in dump of main's Part kits): all seven keys share the
  WheeledTruck kit, 11.0-12.1 long x 7.5-8.1 wide, seats on the cab roof (seat tops 2.65-3.04 over the chassis centre,
  cab top 2.60-2.86). On that Part kit the rider sits on the roof; the look is answered by the VKIT GROUND Part bodies,
  not by a store pick (G2-12).
- **G2-10 tools/WeCheck2_Replacements.luau keeps its ids; only its comments change** (fix round 2): the header no longer
  says the picks are open, and the two ground id lines say RETIRED in G2, kept only for re-checks. The ids stay (the G1
  pins pin the id lines' start, and re-running the read-only script is harmless). The air lanes' copy is the G1 file
  unchanged, so a merge takes G2's copy.
- **G2-11 The mock renders are built from the raw P lines with boxes, not mesh files:** assetdelivery answers 401 and the
  3-D thumbnail API 403 without a login, so no .mesh file of these ids could be read. The mesh look comes from the
  thumbnails API's 2-D mesh render (out/renders).
- **G2-12 The owner's complaint for these seven keys can only be answered by VKIT GROUND, not by a store pick; G2 ships
  only together with an approved VKIT GROUND.** G2 records rejections only, so alone it changes nothing on screen
  (PendingAssetId is never read at runtime). The VKIT GROUND lane builds a Part body for all seven keys
  (Configs/VehicleBodies/Ground.luau; VehicleBodyBuilder builds it only when no store body went on, and G2 leaves these
  keys with none). Fix round 2: fb4/ground2/out/tools/merged_check.sh checks a merged stand-in tree (NOT Roblox) and now
  also fails on floating parts (every visible body part in a touching chain to Frame / CabShell, a cargo deck at most
  0.10 over the frame), on a truck more than 10 % narrower on a phone screen while driving than on main (VehicleCamera
  3 x the assembly radius, capped by VehicleConfig.Drive.ChaseZoom when it lists Car), and on a driver who no longer
  lands on his own side. VKIT GROUND round 0 fails all three (decks 1.40 over the frame and the whole tank loose on the
  tanker; 0.60-0.74 x main's on-screen width; 5 drivers land behind). The VKIT fix-1 snapshot (its files as of
  2026-09-28 09:37) passes seats 28/28 (default and +0.5 avatar), a roof over every head, decks on the frame, on-screen
  width 0.91-1.07 x main (its ChaseZoom Car cap), exits 25/25 clear and multi-rider 504/0, and still fails: 2-5 parts
  per key off the body (mirrors 0.15-0.17, a side fuel tank 0.35, the recovery underlift 0.70, the Armored Truck's gun
  0.80-1.30 over its ring) and 5 drivers landing behind the truck (Armored, Ammo, Recovery, Fuel Tanker, and the Escort
  Truck that G2 does not touch). The Supply Truck and the Ammo Carrier keep one cab and deck (side outline overlap
  0.85, rear 0.99; fix 1 gave the Ammo Carrier ammo boxes and a small crane). These go to VKIT GROUND as numbers
  (fb4/ground2/out/handoff_vkit_ground.md); this lane does not edit VKIT's files. The complaint counts as fixed only
  when merged_check.sh prints MERGEDCHECK PASS on the final merged tree and the owner's phone test agrees. This lane
  does not build a second cab: the WheeledTruck kit's seats and parts are code in VehicleService.kitWheeledTruck
  (shared by 15 keys), the file the VKIT framework also changes, and a second cab for the same seven keys would overlap
  VKIT GROUND. Reversible: if VKIT GROUND does not ship, use the fallback texts in fb4/ground2/out/if_no_vkit and the
  cab becomes this lane's next round (config-first); a store pick that passes the origin check still replaces the
  built body.
