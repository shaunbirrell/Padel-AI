
## 2026-09-28 — fb4 capture lane: Central Plaza "left and rejoined and I had the circle again" / "standing on the circle it's not going through" (base e506c9c)

Owner, verbatim: "When standing on the centre one of two things happen, either when I left and rejoined the map I
automatically had the circle again which I shouldn't of standing on the circle it's not going through". His screenshot
(level 100, flag pill +15 %, at the Central Plaza flag, the zone name green) matches the stand-in: after a rejoin he held
Central Plaza (+10) and his Home Outpost (+5) without capturing anything, and standing on a zone you already hold showed
nothing at all. All tests behind these lines are headless stand-in runs, not Roblox.

- **CAP-1 Root cause 1: saved claims were re-planted on join.** EconomyConfig.OutpostIncomeBuff.PersistClaims (lane W
  F3, switched on by lane Z, "reversible") made TerritoryService.replantClaims give back every claim in
  profile.Territories on join, on the same server or a new one (Neutral and NPC-held zones), and a leaver's zones went
  Neutral only so that the next join could take them back. Now PersistClaims = false. Measured on e506c9c (stand-in):
  capture Central Plaza, leave, rejoin the same server -> his again, Empire Tax +15 without a capture; new server -> his
  again; a v83 save with 3 claims -> all 3 re-planted (Radar Hill taken off the NPCs), Empire Tax +35.
- **CAP-2 PersistClaims off alone does not fix a rejoin on the same server.** With it off, e506c9c's leave rule is the old
  soft release: a leaver keeps his zones on that server, so the join sync hands them back (measured: the candidate with
  ReleaseOnLeave = false fails the same 5 rejoin checks as e506c9c). New switch TerritoryConfig.ReleaseOnLeave = true: a
  leaver's zones go back to Neutral at once (same path as the PersistClaims / Home Outpost release, releaseOwnership
  "leave": no toast, profile untouched). Reversible: ReleaseOnLeave = false (old soft release) and / or
  PersistClaims = true (lane Z's re-plant, which always releases on leave).
- **CAP-3 Home Outposts kept as they are (F10).** A Home Outpost still goes Neutral when its owner leaves and is held
  again on every join once taken (StarterOutpostTaken), worth +5. It is owner-only, cannot be stolen and is not "the
  centre one", so it is not the complaint; after a rejoin the pill reads +5 (the Home Outpost) instead of +15. If the
  owner wants that gone too, it is TerritoryService.onPlotReady's holdStarter (a separate switch, not added here).
- **CAP-4 Old saves need no migration and nothing is wiped.** With PersistClaims off, the first sync on join
  (syncProfileOwnership, then EconomyService.SyncOutpostIncomeStacks) rewrites profile.Territories from what the player
  really holds on that server and recounts OutpostIncomeStacks, so a v83 save's claims drop out on its first join and
  the Empire Tax pill (WE_EmpireTaxPct) shows only what is held (+5 with the Home Outpost). Every other field is kept
  (real DataService harness: cash, level, clan, TerritoriesCaptured, StarterOutpostTaken). No DataVersion bump.
- **CAP-5 The leave does not rewrite the saved claims.** The leaver's zones go Neutral but profile.Territories is saved as
  it was at the leave (PlayerRemoving handler order is not guaranteed, so a write there may miss the save); the next
  join's sync drops them. Only an OLD server (v83, PersistClaims on) would re-plant them, i.e. during a rolling update
  (reviewer driver R7: a v83 server after a new-server session gives Central Plaza back, Empire Tax +15). A code scrub
  in PlayerRemoving is not reliable (DataService.UnloadProfile clears the profile before it saves). So the owner must
  publish with "Migrate to Latest Update" (or shut down all servers): phone_test step 0, owner_text and the
  integrator's publish note say so.
- **CAP-6 Root cause 2: a zone you hold was silent under you, and so was a contested one.** The capture bar showed only
  while you gained progress. Standing on your own zone (Progress stays 0) and standing in a zone with another player
  (contested, ContestedProgressMult 0, and nobody capturing yet) both showed nothing, so "it's not going through".
  New TerritoryConfig.StandingBar { Held = true, Contested = true, HeldTitle = "YOURS" }: the server's per-player payload
  (LocalCapture, Capturing stays false) names the zone the player stands in when it is not counting for them; the same
  top-stack capture bar then reads "YOURS · CENTRAL PLAZA" (full, green) or "CONTESTED · CENTRAL PLAZA" (amber, the
  zone's frozen progress). Server data only (the tick's own Inside / Standing lists); nothing is granted; the capture-start sound
  still keys on Capturing. A change of who stands in a zone is pushed at the capture cadence (0.5 s, <= 2 Hz) to the
  players who stepped in or out only (fix 2, CAP-19). Reversible: Held / Contested = false (then the C2 radar OFF log
  is identical to e506c9c apart from the new Held = false field: 280 / 280 lines, re-checked in fix round 2).
- **CAP-7 The capture itself works; its bar did not always (see CAP-16).** On e506c9c a neutral, NPC-held or another
  player's Central Plaza is captured in 20.0 s with the bar up within 0.5-1.0 s, as long as no other capture of his is
  part-done (then the bar named the other zone, CAP-16), and a player 75-99 studs out still pauses it (CAP-17); NPC-held and still protected takes 42.5 s with "PROTECTED ·"; his squad
  soldier (an NPC) never contests; the counted radius is 99 studs (the marker's half-diagonal) against a 74-stud ring,
  so anywhere on the circle counts, and so do the ~25 studs round it (see CAP-11). Level 100, admin and the novice
  shield play no part in capture.
- **CAP-8 A rejoin can be used to take a zone again.** Recapturing after a rejoin is a normal capture: toast, Empire Tax,
  Stats.TerritoriesCaptured +1, CaptureTerritory mission progress (daily-capped) and, for a player in a clan,
  ClanWarConfig.ScorePerTerritoryCapture (10) clan-war score (ClanWarService.OnTerritoryCaptured). So a solo loop
  "capture (20 s), leave, rejoin, walk back, capture" earns clan-war score about once a minute on one server. On
  e506c9c the rejoin re-planted silently, so there was no event; before lane Z (soft release, PersistClaims off)
  hopping to a fresh server gave the same fresh capture, and two players trading a zone always could. No cooldown is
  added: a same-server "released on leave" memory would not stop server hopping. If clan-war farming shows up, the
  follow-up is a config cooldown on score / stat for a zone the same UserId released within N minutes.
- **CAP-9 Lane W / Z drivers.** Their "flag off = soft release" (W8) and R15 leaver-colour (W11) checks now need
  ReleaseOnLeave = false, and lane Z's k1 driver expected PersistClaims = true: lane copies (fb4/capture/drv
  w_server_driver_cap.luau, k1_driver_cap.luau) change only those expectations. Lane Z's Z-9 risk (plot-ready before
  profile-loaded loses re-planted claims) cannot happen with PersistClaims off.
- **CAP-10 BuyPathStatic.** Lane Z's pin `PersistClaims = true` becomes `PersistClaims = false` (the one changed
  line); the fb4 block (28 checks) pins both switches together, the re-plant guard, the leave release, the standing bar
  (never Capturing, never a grant, server lists only: Inside for CONTESTED, Standing for YOURS), the client titles, the
  capture-start sound, the fix round 1 rules (disc limit + oil-rig exemption, Standing in the signature, unchanged
  capture reach, the YOURS cue, the 10 Hz pulse, the Contested reset) and the fix round 2 rules (the capturer's bar only
  for a zone he is counted inside, lower Id first; the join order syncProfileOwnership -> syncEmpireTax -> push; a
  presence change pushed to the movers only; no YOURS cue on top of the capture toast). 28 mutants (fb4/capture/
  mutate.py), all caught; 24 of the 28 checks fail on e506c9c, the other 4 (re-plant guard, capture-start sound,
  capture reach, join recount order) are caught by mutants M1, M2, M15 and M21 / M28.

Fix round 1 (reviewers of the first candidate):

- **CAP-11 The standing bar follows the visible disc; capture reach is unchanged.** TerritoryCapture counts a player
  out to the marker's half-diagonal (99 studs at Central Plaza) but the painted disc (<Id>_Ring) has radius Radius + 4
  (74), so the YOURS / CONTESTED bar stayed up about 25 studs past the edge he sees (reviewer R1). New
  TerritoryConfig.StandingBar.OnDisc = true: the server names the standing zone only to players whose root is on the
  disc (radius read once from the ring part; DiscPad 4 when the ring is missing). The capture / contest reach itself is
  NOT shrunk: fort walls sit at 1.35 x Radius (74 studs for a 55 fort, beyond its 59-stud ring), boats take South Docks
  and the rigs from the water, and a smaller reach makes capture less forgiving on a phone. So CAPTURING can still
  start a few steps before the disc (phone_test step 3 says so), and a rival standing 75-99 studs out still blocks a
  capture without seeing a bar himself (as on e506c9c; fixed in round 2, CAP-17). Oil rigs keep the counted reach for
  the bar (their ring is capped at the 46-stud deck). Reversible: OnDisc = false. Fix round 2: OnDisc now limits YOURS
  only; CONTESTED follows the counted reach like CAPTURING (CAP-17).
- **CAP-12 YOURS is a 5-second cue.** StandingBar.HeldSeconds = 5: YOURS shows when he steps onto his own disc (or a
  contest there ends; since fix round 2 not the moment his own capture finishes, CAP-18) and hides after 5 s until he steps off the disc and back on (client timer,
  no extra server push). It no longer sits in the top stack while he drives across his circle or past his Home
  Outpost, so no Home-Outpost-only switch was added. CONTESTED stays while the contest lasts. Reversible:
  HeldSeconds = 0 (shown the whole time he stands there). phone_test step 11 asks the owner which he prefers.
- **CAP-13 The contested pulse is written at most 10 Hz.** The v38 Heartbeat pulse wrote Fill.BackgroundColor3 (one
  Color3 Lerp) every frame; the standing CONTESTED bar would have widened that. Now it steps every PULSE_STEP (0.1 s):
  8 writes per second at 60 fps in the stand-in (60 on e506c9c), for the capturer's bar too.
- **CAP-14 A finished contest on a Neutral zone goes back to Neutral.** Pre-existing on e506c9c: a Neutral zone that
  two players contested kept OwnerType "Contested" after they left (marker attribute too), and the tutorial's outpost
  pointer ranks "Contested" zones last. tickTerritory now resets Contested -> Neutral when the zone empties or one
  player is left. NPC and player zones never take OwnerType Contested, so they are untouched. Capture speed unchanged.
- **CAP-15 Two players on one circle always block each other, friends included.** ContestedProgressMult = 0 and no clan
  exception (e506c9c design, unchanged): if the owner and his sister stand on a Neutral circle together, it shows
  CONTESTED and nobody gains until one steps off. owner_text says so; a clan-mates-share switch is a possible
  follow-up if he asks.

Fix round 2 (second review of the fix-1 build; stand-in tests: fb4/capture/drv/cap_driver.luau section S9 and
ds_territories.luau T3):

- **CAP-16 The capture bar could name a different zone (pre-existing on e506c9c).** buildPayloadForPlayer marked any zone
  with CapturingUserId = him and Progress > 0 as Capturing, whether or not he stood there, and CapturingUserId is kept
  until the progress decays to 0 (0.35 / s: up to ~57 s). So after a part-done North Ridge or West Depot, the bar on
  Central Plaza said "CAPTURING NORTH RIDGE 46%" counting down in 20 / 20 samples while Central Plaza was really being
  taken (e506c9c and fix 1), and his own / contested Central Plaza showed the other zone instead of YOURS / CONTESTED.
  This is a real "standing on the circle it's not going through" case. Fix: the Capturing branch needs the player in
  the zone's last-tick Inside list (countedIn(rt, player), TerritoryCapture's reach) and takes the lower Id when two of
  his captures overlap, so it never depends on table order. Side effect: walking out of the counted reach mid-capture
  hides the bar within ~1 s (the progress still decays as before). Not behind a switch: it is a bug fix.
- **CAP-17 CONTESTED goes to every player the capture counts, the blocker too.** A second player 75-99 studs from the
  centre (off the painted circle, on the plaza streets) pauses a capture (unchanged contest reach). Fix 1 showed
  CONTESTED only to players on the disc, so the capturer saw CONTESTED and the blocker saw nothing. Now standingZoneOf
  takes CONTESTED from the Inside list (counted reach) and YOURS from the Standing list (disc). phone_test step 8 says
  that a player just outside the circle also pauses it and sees CONTESTED. Shrinking the contest reach to the disc was
  not chosen: fort walls sit outside their disc and boats contest oil rigs and South Docks from the water.
- **CAP-18 No YOURS cue on top of the capture toast.** When his own capture finishes on the disc, the next payload names
  the zone as Held; fix 1 showed "YOURS · CENTRAL PLAZA" for 5 s beside the server's "Outpost taken  Empire Tax +15%"
  toast (two messages saying the same). The client now spends the cue when the payload before was capturing the same
  zone: only the toast shows; YOURS shows the next time he steps onto the disc. New switch
  TerritoryConfig.StandingBar.HeldAfterCapture = false (true = the fix-1 behaviour). HUD harness snapshot "taken":
  only the toast, at 7 viewports.
- **CAP-19 A change of who stands in a zone is pushed to the movers only.** Fix 1 turned every step in / out into a full
  push to every player (a far bystander got 40 payloads a minute instead of 30 while one player walked on and off the
  plaza every 1.5 s). Now the capture loop collects the players who were or are in that zone's Inside list and
  PushPlayer()s them (unless a full push went out that tick). Measured: bystander 30 / min (as e506c9c), the walker
  60 / min (<= 2 Hz). Nobody else's payload changes on a pure presence change (list entries change only with progress,
  owner or contest, which still push to all, as on e506c9c).
- **CAP-20 The join recount of Empire Tax is pinned.** A v83 save with claims and no Home Outpost taken depends only on
  OnProfileLoaded's syncEmpireTax(player) (after syncProfileOwnership) to drop its saved stacks: 0 after join (e506c9c:
  30, re-planted; the candidate without the call: 30). New BPS rule + mutants M21 / M28, ds_territories T3 (3 checks)
  and cap_driver S9 (g).
- **CAP-21 Lane W driver W9.** Its contested-colour checks fake a contest with both players far away; with CAP-16 the
  capturer must be counted inside, so the lane copy (fb4/capture/drv/w_server_driver_cap.luau) sets rt.Inside =
  { A, B } in that setup (a real contest always has both inside). The unmodified S4 copy fails those 2 checks.
- **CAP-22 Home Outpost question.** The Home Outpost still comes back on every join once taken (CAP-3, F10). It is the
  same "had it again" pattern for a different zone, so phone_test step 11 asks the owner whether it should be free
  after a rejoin too; a switch is added only if he says yes.
