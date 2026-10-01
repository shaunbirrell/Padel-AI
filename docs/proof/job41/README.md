# JOB 41 proof

| File | What it proves | Status |
|---|---|---|
| funnel-before.md | Today's Creator Hub onboarding funnel (the root-cause input) | **Owed**: the query and table are ready; Code Bot / the owner pastes the numbers (no Creator Hub access here) |
| funnel-sim.txt | run_first_minutes_test.py: the Guided chain in order with step times, the recruit maths, the camp (200 seeded fights), capture blocked until the camp is dead, the reward once, rejoin / never-soft-lock, skip at every step, returning profiles, OFF == OLD, the FirstMinutes funnel once each in order | Done (headless luau stand-in, real TutorialConfig / TutorialService / GuidedService / ProfileSchema) |
| studio-run.md, step_<n>.png, reward_confetti.png, step_800x360.png | A fresh-profile Studio run with a stopwatch | **Owed** (needs Studio) |
| hud-harness.txt | 5 viewports, 0 overlaps with the banner + objective marker + Army popover | **Owed** (the banner is the existing tutorial chip with new 9-step texts; not re-measured) |
| recruit-pack-sim.txt, rivals-sim.txt, rate-prompt-sim.txt, rivals.md | Parts B-D | Follow with those parts |

## What the sim says (read it as a model, not a measurement)
- **Pace, from the real layout:** Command Center console → ATM 14 s walk, ATM → Home Outpost 14 s walk
  (WalkSpeed 16 × a 1.4 path factor), 4 s to read each banner, one 5 s passive tick, CaptureTimeSeconds 10.
  - The chain reaches the Reward in **~79 s**, first BUILD at 8 s.
  - That is **faster** than the brief's 3-4 min estimate. It is reported, not padded.
- **Fight:** with the brief's Recruit numbers (40 HP, 4 dmg, 1.2 shots/s, hit chance capped 0.35 / 0.2) and the
  StarterRifle (18 dmg, 8 shots/s), the model's camp dies in a median ~2 s (max 4.9 s over 200 seeds).
  - This assumes 35 % player hits and 3 soldiers at 40 %.
  - It may feel too short; `CombatConfig.NPCTypes.Recruit.Health` is the knob.
  - Worst case for the player (both Recruits hitting at the cap): he lives 29.8 s. He never died in the model.

## NOT verified until Shaun tests on his phone
- The camp NPCs' real behaviour (RigBuilder rigs, line of sight, the leash on the ring, the soldiers engaging them).
- The "ENEMY CAMP" objective marker and the gold line at each step on an 800x360 / 956x440 screen.
- The "BASE SECURED!" banner + confetti, and the coin burst.
- The FirstMinutes funnel arriving in Creator Hub (LogFunnelStepEvent only reports from live servers).
