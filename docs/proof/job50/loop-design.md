# JOB 50 part A: the zone runs: loop design (claude-bud, 2026-10-01)

## Before (root cause, from the code: `before.md`)
Each zone's JOB 46 kiosk was one tap:
- **Ship zones:** paid 10 min of that zone's flat income (Production L1 $18,000; a fraction of a rebirth-10 player's
  income).
- **Other zones:** opened a panel (DRILL / STRIKE / NUKE) or swept the ATM.
- **What was missing:** no skill, no goal, no time limit, no best, no status, no analytics. Nobody had a reason to walk
  back to a zone.

## Rules for every run
- **Start and validation:**
  - The kiosk (the same `WE_ZoneActivity` prompt) starts a server-timed run on the apron.
  - Only the current step carries a prompt.
  - A step counts only for the owner, inside the annex, in order, before the limit.
  - The client sends nothing about time, score or position.
- **Pay:**
  - `RunBase = max(ShipmentCash, 2 min of his passive income)`, the one formula, times 1.0-1.5 by the time left. A
    run at the limit pays 1.0; the fastest pays 1.5.
  - The first clear pays RunBase once more.
  - A fail pays nothing.
- **Cooldown:** 20 min per zone (saved), started by any end, so failing doesn't allow retry spam.
- **Status:**
  - A personal best per zone on the gateway plaque ("UNLOCKED BY <name> · REBIRTH N / <RUN> BEST m:ss").
  - All 7 zones at L3 gives ZONE COMMANDER (plaques + `WE_ZoneCommander`).
  - A bunker banner stage (1-3).
- Free for everyone. No Robux anywhere. No teleport.
- **Analytics:** `ZoneActivity` (zone, result, seconds, payout).

## Per zone

| Zone (rebirth) | Run | Goal / time | Effect on a win | Why come back |
|---|---|---|---|---|
| Tank Factory (R1) | PRODUCTION RUN | 3 crates line -> truck, 6 steps, 60 s | cash | beat the best; 20 min cooldown |
| Nuclear Silo (R2) | LAUNCH PREP | 3 consoles in order, 30 s | the warhead charge moves on by 5 min | a faster nuke |
| Artillery (R3) | RANGE PRACTICE | 6 targets in order, 45 s | missile reload -120 s | strike again sooner |
| Drone Hangar (R4) | RECON FLIGHT | instant | the nearest raidable rival marked (PIN / SEND "B:<plot>"), ATM swept | find a target |
| Elite Barracks (R5) | DRILL COURSE | 4 course points, 45 s, par 30 s | beat par: ARMY BOOST 10 min | buff before a raid |
| Oil Refinery (R6) | PRESSURE VALVES | 4 valves in a fresh order each run, 30 s | cash | the order changes |
| Bunker (R8) | HOLD THE LINE | 3 NPC attackers (CombatService, him only), 60 s | cash + a banner stage | finish the banner |

## Pay at 3 points (sim, `rebirth-zones-sim.txt`)
- **Production run, slowest .. fastest:** L1 $18,000 .. $27,000, L2 $42,000 .. $63,000, L3 $84,000 .. $126,000.
- **Zones without a flat income** (silo / artillery / bunker) pay 2 min of his own income. At $3,000/min that is
  $6,000 .. $9,000 a run, plus the effect.
- At rebirth 10 a player earning about $141k/s (Shaun's screenshot) gets RunBase = 2 min = about $17M a run (up to
  $25M fastest).
- All 7 zones every 20 min adds at most about 21 min of income per 20 min of active play. That is
  `RunRules.IncomeMinutes`, a number for Shaun to tune.

## NOT verified until Shaun tests on his phone
The prompts' reach and readability on the apron, the step markers' placement next to the JOB 46 props (Studio view
owed), the bunker wave feel.
