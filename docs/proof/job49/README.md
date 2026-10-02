# JOB 49: reasons to come back: proof files (claude-bud, 2026-10-01)

| File | What it proves |
|---|---|
| `before.md` | The root cause, from the real code + sims (no live numbers claimed), plus the Creator Hub queries. |
| `daily-return-sim.txt` | `tools/sim/run_daily_return_test.py`: the REAL MissionService / RetentionService / ProfileSchema / configs on a fake UTC clock. Parts A-D below; 0 failed. |

What `daily-return-sim.txt` covers:
- **A. Streak:**
  - days 1-7, then 7 -> 1;
  - a double claim pays once;
  - 23:59:59 / 00:00:00 UTC;
  - grace on (kept + SAVED, once per cycle) and off (reset);
  - two missed days reset;
  - Day 7 scaled ($900/min -> $54,000) and the floor at no income;
  - the real countdown;
  - the first card at 150 s for a held new player (98 s with Calendar off);
  - Migrate keeps the grace data.
- **B. Offline:**
  - 4 min = 0; 1 h; exactly the cap; 30 h capped;
  - a negative gap; first join;
  - the load hook twice pays once; a rejoin after 2 min = 0;
  - Premium once;
  - CapBoost off / on (test only) x2 time, Share unchanged;
  - card OFF == the JOB 29 payload;
  - the maths at 3 incomes.
- **C. Missions:**
  - 3 core missions of 3 different types on top, Daily Ops below;
  - tier-1 targets at level 5;
  - stable within the day;
  - no raid possible -> no Raid mission;
  - Raid progress counts;
  - the list + progress survive a rejoin;
  - the chest once; claims idempotent;
  - ResetHourUtc 6 rolls at 06:00;
  - a free reroll once a day; the Robux hook off = tokens do nothing; on (test only) = a token is spent;
  - the receipt grant path;
  - Core OFF == today's rotation;
  - owner-first.
- **D. One sequence (server side):**
  - Comeback + offline -> one card with both;
  - comeback only -> the card still shows;
  - sequence OFF == the old payload;
  - ReturnDay once on join;
  - owner-first.

## NOT verified until Shaun tests on his phone (and Code Bot runs Studio)
- The Studio "come back" screenshots: the Welcome back card, the calendar on day 1 / a grace day / day 7, the 3 missions
  with the countdown, and one at 800x360. This session cannot drive Studio.
- The client card QUEUE order on a real device (one at a time, never mid-fight), and the reroll / GO buttons' tap
  sizes.
- The HUD harness at the 6 viewports (`check_hud.py` is not in this repo).
- The live D1 / D7 and custom-event numbers (`before.md` lists the queries).
