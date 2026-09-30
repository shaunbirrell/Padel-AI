# JOB 40E-FIX: base owner name tags (top priority, Shaun 2026-09-30 23:19 Dublin)

Queued by Code Bot Roblox on 2026-09-30 (v153). Do this RIGHT AFTER the job you are on now is finished and pushed,
and BEFORE JOB 41. Same git rules as JOB 35-41: rebase `claude/desktop-bud` on the latest `origin/phase-7-polish`,
push only `claude/desktop-bud`, never bump WE_Build / build dist / publish (Code Bot integrates).

NOTE: `claude/desktop-bud` already has `0f210ab` "claude-bud JOB 40E fix: base owner tags slim ... OwnerFirst kept"
(pushed 2026-09-30, not yet integrated by Code Bot). If that commit already meets EVERY point below, do not rebuild it:
check each point against the code, fix what is missing, add the owed phone screenshots, and say "JOB 40E-FIX done" in
LATEST-HANDOFF with the list ticked.

## The problem (Shaun, from his phone)
The JOB 40 part E base owner name tags are too big, sit too low, block the map view on phones, and some empty grey
tags show.

## The spec
1. HIGH IN THE SKY: raise the tags high above the bases, into the sky (well above every building, the army and the
   skyline as seen from the plaza), so they never sit across the view of the map.
2. COMPACT: a small flag + the short name only. The @handle (and any rank chip) shows ONLY when the viewer is close.
   No big box, no rebirth title in the far view.
3. SCALE BY DISTANCE WITH A CLAMP: a near tag may be a little bigger than a far one, inside a fixed min / max (a far
   tag is never bigger than a near one, never bigger than the max on a phone).
4. FADE + CAP: fade tags in / out by distance and draw only the nearest 4-5 rival tags at once.
5. NO OVERLAP: two tags never overlap on screen (the farther one hides).
6. NO EMPTY TAGS: hide the tag of any base with no live owner (no grey "OPEN BASE", no "?", no nameless pill).
7. YOU: keep "YOU" on your own base (it fades out at your own gate where the v123 base sign takes over).
8. PHONE TEST: test at phone size 1024x471 (plus 800x360 as usual) with BEFORE / AFTER screenshots (the plaza looking
   out + a base road), saved in `docs/screens/job40/` (e.g. `tags_before_1024x471.png`, `tags_after_1024x471.png`).
9. FLAG: `BaseMarkerConfig.Live` OwnerFirst STAYS true (Code Bot pins it in `tools/checks/codebot_v153.py`).

## Tests
`tools/sim/run_base_marker_test.py` 0 failed (height / angle, clamp, fade, cap 4-5, no overlap, no empty tag, YOU),
`tools/checks/claude_bud_job40.py` pins updated with replacements (never just deleted), and
`LUAU_COMPILE=$HOME/.local/bin/luau-compile python3 tools/BuyPathStatic.py` 0 FAIL; rojo build ok.
