# JOB 48: the first 2 minutes hook: proof files (claude-bud, 2026-10-01)

| File | What it proves |
|---|---|
| `sim-before.txt` | The v4 Guided chain BEFORE this job, run by the real TutorialService / GuidedService at a pace derived from the real layout (walk at WalkSpeed 16 × 1.4, 4 s to read each banner, the seeded fight median, the real capture time). |
| `funnel-sim.txt` | After this job: `run_first_minutes_test.py`, 67 checks, 0 failed. See the list below. |
| `funnel-live.md` | The Creator Hub queries for the LIVE funnel. The numbers are owed by Code Bot / Shaun. |
| `studio-before.md` | Why the Studio stopwatch runs are owed, and what the sim stands in for until then. |

`funnel-sim.txt` covers:
- **Hook OFF:** today's v4 chain exactly, step for step (sections 1-10 run with the Hook off).
- **Hook ON:** OrderVersion 5 with 11 steps.
- **The reward:** RewardSoldiers 3 -> 5, clamped at the cap (cap 4: 3 -> 4; cap 3: no change).
- **The raid goal:** RAID A RIVAL BASE, then RaidSent, then RaidWon, then the Barracks.
- **The fast-raid bonus:** paid once, only inside 300 s. With the bonus at 0 there is no countdown.
- **The fallback** (no rival allowed): the chip changes to "Clear hostiles". Two kills by HIM give GoalFallbackWon; the
  180 s timeout moves the chain on; the re-check switches back to the raid when a rival appears.
- **The end of the chain:** Barracks -> 4x4 -> Open Missions.
- **Save migration:** v4 -> 5 (past the reward / mid-fight) and 5 -> 4 (Hook off).
- **Funnel:** steps 1-9 unchanged, plus 12-16 once each.
- **Analytics:** FtueTimeToFight once; SessionMilestone at 60/120/180/300/600 s only where the Hook is live.
- **Owner-first:** another player stays on v4. The owner's REPLAY GUIDED plays order 5.

## Before / after (derived pace, seconds from spawn; NOT a stopwatch measurement)
| Step | Before (v4) | After (Hook) |
|---|---|---|
| First BUILD | 8 | 8 |
| Collected | 31 | 31 |
| Recruited (3 soldiers) | 45 | 45 |
| First fight won (camp cleared) | 64 | 64 (FtueTimeToFight) |
| Captured | 76 | 76 |
| Reward + army growth | 79 (no growth) | 79, army 3 -> 5 (+2 free soldiers) |
| Next goal | Barracks at 82 (a build, no fight) | RAID A RIVAL BASE at 82 (or "Clear hostiles") |

**Root cause (from the model):** the chain's opening is already inside 2:00. What it lacked:
1. any army growth after the fight;
2. a goal after the reward that keeps the fighting going. The chain went straight to "build the Barracks" and then
   ended.
The live 3-minute sessions / 0 % D1 need the live funnel to say WHICH step loses people (`funnel-live.md`). This job
does not claim that number.

## NOT verified until Shaun tests on his phone (and Code Bot runs Studio)
- The fresh-profile Studio stopwatch runs at 844x390 / 800x360 (`studio-after.md`) and the screenshots `step_<n>.png`.
- The HUD harness at the six viewports with the banner, ObjectiveMarker, Army popover and TARGETS card all on screen.
  `check_hud.py` is not in this repo, so `hud-harness.txt` is owed.
- That the camp NPCs engage, the soldiers follow, and the TARGETS outline / countdown reads well on a phone.
- **The 2-minute Robux offer lands inside the new raid goal.** `MonetizationService.ClaimSoftOfferSlot` lets
  `FirstOffer` through at 120 s whatever the tutorial state, and the raid goal is up from about 82 s. Not changed; it
  is Shaun's call (see LATEST-HANDOFF).
