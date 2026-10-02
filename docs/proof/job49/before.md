# JOB 49: root cause before the change (claude-bud, 2026-10-01)

Evidence is the real code plus the sims (`daily-return-sim.txt`). This session has no live numbers; the queries for Code
Bot / Shaun are at the end.

## 1. Does a new player see the reasons to return in his first session?
- **Streak card:** it was auto-claimed after 8 s plus `WaitOnboarding(player, 90)`. During the Guided chain the hold
  lasts until the reward (up to 300 s), but the 90 s cap released it at 98 s, so on a slow run the card landed
  mid-chain. Its text was "Come back tomorrow for $2,000", with no time and nothing at stake. (Sim: 98 s with Calendar
  off.)
- **Welcome back:** it never shows on a first join (no LastSeen), which is correct. On a return it said "OK" with
  nothing to do.
- **Missions:** 3 Daily Ops + 3 rotating missions of any type. Nothing pointed at them on join, and a raid win never
  counted (there was no "Raid" type).
- **Not shown at all:** a time to the next reward, a reason tied to the loop (raid / recruit / build), or any message
  that missions reset.

## 2. Is anything broken?
| Case | Result |
|---|---|
| A double claim on one day | pays once (`AlreadyClaimed`) |
| The UTC-midnight edge (23:59:59 then 00:00:00) | two separate days, streak 2: correct |
| Rejoin / server hop (offline) | `PrevSeenUnix` is cleared after one payout and MinSeconds = 300 blocks spam |
| Negative / future gap | 0 |
| A missed day | hard reset to Day 1 (by design before; now grace) |
| Day 7 | a flat $20,000, worthless past the first hour |
| Offline cash raided before he collects | **possible**: the payout goes to PendingCash and `GetRaidableBalance` counts PendingCash. **Question for Shaun.** |

## 3. Creator Hub queries (owed: Code Bot / Shaun paste the numbers here)
- **Retention:** Analytics > Retention: D1 and D7, last 7 days, All + Phone.
- **Custom events (before JOB 49):** `StreakDay` (Value = the day, per day), `OfflineEarned`, the mission claims
  (MISSION_CLAIMED).
- **Custom events (after JOB 49):** StreakClaimed (CustomField01 = grace), StreakReset, OfflineCollected,
  MissionDone, MissionsAllDone, MissionReroll, and ReturnDay (Value = days since the first join, CustomField01 =
  guidedDone). ReturnDay with Value 1 is D1, split by the JOB 48 chain.
