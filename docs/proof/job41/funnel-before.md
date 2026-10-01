# JOB 41 part A: the onboarding funnel BEFORE the Guided chain (root cause input)

**Status: the numbers are NOT in yet.** I (claude-bud) cannot open Creator Hub from this session, so nothing below is
guessed. Code Bot / the owner: please paste the numbers into the table.

## Where to look
- Creator Hub → WAR EMPIRE → **Analytics → Funnels → Onboarding**, last 7 days (all platforms, then Phone only).
- Custom events: **Analytics → Custom events → OnboardingSeconds** (Field `step`), last 7 days. This gives the median
  seconds from join to each step (JOB 29).

## The rows (AnalyticsConfig.Roblox.Funnel, in order)
| # | Step | Users | % of Joined | Drop from previous |
|---|---|---|---|---|
| 1 | Joined | | 100 % | |
| 2 | Spawned | | | |
| 3 | BaseClaimed | | | |
| 4 | FirstBuilding | | | |
| 5 | CollectedCash | | | |
| 6 | Recruited | | | |
| 7 | Barracks | | | |
| 8 | FirstOutpost | | | |
| 9 | FirstVehicle | | | |
| 10 | TutorialDone | | | |
| 11 | OpenedArmy | | | |
| 12 | FirstAttack | | | |
| 13 | PurchasePrompt | | | |
| 14 | FirstPurchase | | | |

**Where most players leave:** _(fill in: the step with the biggest drop)_.

## What we already know (code facts, not funnel numbers)
- The old step "Capture outpost" (the Home Outpost) had **no enemies**: OutpostDefenders skips starter rows
  (TerritoryService/init.luau, `if not rt.Def.IsStarter`). The first "fight" was standing in a ring.
- The old chain had the Barracks before any action. With the Guided chain the first fight comes right after
  recruiting.
- The owner's numbers (2026-09-30): ~740 visits, ~4 min average play, ~0 % D1, 40 % rating.

## After the Guided chain ships
Compare with **Analytics → Funnels → FirstMinutes** (steps 1 Spawned … 9 NextBuilding, optional 10 Offered,
11 Bought) and **Custom events → GuidedStepSeconds / GuidedSkipped / GuidedStuck**.
