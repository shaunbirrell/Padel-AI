# JOB 48: the LIVE FirstMinutes funnel (owed: Code Bot / Shaun paste the numbers here)

This session cannot open Creator Hub, so no live numbers are claimed. Here are the exact queries.

1. **Funnel steps.** Creator Hub > your experience > Analytics > **Funnels** > **FirstMinutes**.
   - Date range: Last 7 days. Run it twice: Platform = All, then Platform = Phone.
   - Paste the users at each step 1-11 and the drop % between steps.
   - From the build with the Hook on, steps 12-16 also appear: ArmyGrew, GoalRaidShown, RaidSent, RaidWon, NextGoal.
2. **Custom events.** Analytics > **Custom events**:
   - **GuidedStepSeconds:** the median Value, split by CustomField01 (the step).
   - **GuidedSkipped:** counts by CustomField01 (the step where they skipped).
   - **GuidedStuck:** counts by CustomField01.
   - **After the Hook ships:** SessionMilestone (counts by CustomField01 = 60 / 120 / 180 / 300 / 600) and
     FtueTimeToFight (median Value).
3. **Name the step with the biggest drop** between two steps, on Phone. That step is the first fix target. Do not guess.

| Step | Users (All) | Users (Phone) | Drop to next |
|---|---|---|---|
| 1 Spawned | | | |
| 2 FirstBuild | | | |
| 3 Collected | | | |
| 4 Recruited | | | |
| 5 FightStarted | | | |
| 6 FirstKill | | | |
| 7 Captured | | | |
| 8 Reward | | | |
| 9 NextBuilding | | | |
| 10 Offered | | | |
| 11 Bought | | | |
