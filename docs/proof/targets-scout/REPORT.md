# JOB 47: TARGETS card gone, scout report "did nothing", ghost label behind INTEL OFFICE (claude-bud, 2026-10-01)

Live when reported: v170 (place 168). **Code Bot v171 (place 169) published fixes for bugs 1 and 2** while JOB 47 sat in
this bud's queue. This job re-checked those two and fixed bug 3, which v171 did not touch.

## 1. TARGETS card missing: root cause proved by Code Bot v171, re-checked here
- **Cause.** v168's `crosshair()` in `RivalController` set `f.AnchorPoint = spec[5]`, but every spec has 4 fields.
  Roblox throws when a typed property is set to nil, so `build()` died right after parenting the card.
  - The card got no size, no text and no tap.
  - `refresh()` / `layout()` never ran.
- **Proof.** Code Bot's `tools/sim/rival_controller_harness.py` has a GUI stand-in that throws on nil like Roblox.
  - With the v170 source: "Unable to assign property AnchorPoint".
  - With v171: a 180x64 card under the compass.
- **Leads ruled out.**
  - **Recruit Pack.** The offer card (`WE_RecruitPack`) destroys itself on BUY, "Maybe later" and X
    (`RecruitPackController` `close()`), so it cannot keep TARGETS hidden after a purchase.
  - **R10, the Intel guide, the overlap rules.** None of them reach the card, because `build()` never finished.
- **Re-run here.** `run_codebot_v171_test` 0 failed.

## 2. Scout report "did nothing": cause and fix by Code Bot v171, re-checked here
- **Cause.** The server path worked: it charged in-game cash (1 min of income, not Robux) and stored the report. But
  the only output was:
  - a 1.8 s toast;
  - a grey INFO row, 5th in the Intel list, below the fold;
  - a report held in this server's memory only, lost on a server hop.
  The report was also built after the charge.
- **Fix (v171).**
  - The report is built BEFORE the charge; a failure means nothing is charged.
  - It is saved in `profile.Endgame.ScoutReport`.
  - A gold result card pops at once ("ScoutReport" push).
  - The report leads the Intel list with VIEW.
- **Re-run here.** `run_endgame_test` 0 failed, including the 8 "v171 scout" checks.
- **Money.** Shaun's earlier report lived only in server memory and is gone. It cost in-game cash, not Robux. No refund
  or grant was made; that is for Shaun / Code Bot to decide.

## 3. Ghost label behind the INTEL OFFICE pill: fixed here
- **What it is.** In the v170 screenshot, a flag plus "Mich_72.." shows through the translucent compass pill. That is a
  **base owner marker** (JOB 40E: AlwaysOnTop, visible to 5000 studs) of a far base.
- **Root cause.**
  - JOB 40E floats the tags high in the sky (`HeightAt`: 150 studs + 6 % of the distance), so a far base projects into
    the top screen row.
  - `BaseMarkerConfig.VisibleSet` only kept tags apart from EACH OTHER, never from the HUD.
  - A BillboardGui draws under every ScreenGui, so the name showed through the pill as a ghost.
  - Nothing in IntelGuide / the compass draws a second label (one pill, one world marker).
- **Fix.**
  - `BaseMarkerConfig.InTopBar(y, h, topPx)` (TopBarPadPx 6).
  - Each 10 Hz step, `BaseMarkerController` reads the top-bar row's bottom (`GuiService:GetGuiInset().Y` /
    `TopbarInset`, in viewport px, the same space as `WorldToViewportPoint`). Any tag whose box reaches into the row
    is hidden before `VisibleSet`.
  - Tags below the row (the sky over the play view) still show. Nothing else changed: no new per-frame work, same 10 Hz.
- **Proof.** `run_targets_scout_test` replays the screenshot geometry at 956x440, 1024x471 and 1920x1080.
  - **Before:** the old rule shows the tag.
  - **After:** it hides; a tag under the row still shows.
- **Owed.** Real before / after screenshots at 1024x471 and on desktop need Studio or the live client, which this
  session cannot run.
