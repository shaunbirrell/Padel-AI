# JOB A: the Recruitment Office closes by itself ~0.5 s after opening (P0) (claude-bud, 2026-10-01)

## The whole flow (before)
1. **Interaction:** the DRILL kiosk on his own Elite Barracks zone, a ProximityPrompt "WE_ZoneActivity" (10 studs).
   It was added in JOB 46 by `RebirthZoneService.addActivityPrompt`.
2. **Open request:** the server's `Triggered` (only for the plot owner) runs `RebirthZoneService.Activity` (drill),
   which sends `FeaturePush "ZoneOpen" { Panel = "Recruits" }`.
3. **Client:** `RebirthZoneController` (ZoneOpen) calls `EndgameController.OpenStation("Recruits")`, which calls
   `setListOpen("Recruits")`. The panel is shown.
4. **THE CLOSE:** `EndgameController.luau`, `setListOpen`, the `task.spawn` loop. After `task.wait(0.5)` it computed
   `(HumanoidRootPart.Position - stationPoint("Recruits")).Magnitude > EndgameConfig.Station.CloseRange` and called
   `setListOpen(nil)`.
   - **Why it fired:** `stationPoint("Recruits")` is the **plaza** Recruitment Office NPC (NE_E1 in Crossroads), not
     the kiosk he pressed.
   - **The numbers:** from every plot, the nearest possible kiosk spot is at least **531 studs** from the plaza
     office (`sim.txt`), against a CloseRange of 22. So the first 0.5 s tick closed it **every time**, while he stood
     still. That matches the report exactly.
5. **A second bug on the same path:** `EndgameService.AtStation(player, "Recruits")` also only accepted the plaza NPC
   (BuyRange 16). A buy from the kiosk would have been refused ("Go to the Command Office in the plaza") even with the
   panel open.

**Ruled out:**
- **PromptHidden / TriggerEnded / TouchEnded:** no listener on these prompts.
- **A double trigger:** the kiosk prompt is server-side with one `Triggered` connection, owner-checked; ZoneOpen is
  handled once (RebirthZoneController).
- **Duplicate connections on respawn:** the hooks are per Humanoid.
- **Another player's base:** the kiosk prompt only fires for the plot owner.
- **The plaza path:** prompt 12 < close 22, consistent.

## The fix
- **One way in and one way out:** `EndgameController.OpenRecruitmentOffice(source, point)` and
  `CloseRecruitmentOffice(reason)`, logging `warn("[RECRUITMENT OPEN]", source, os.clock())` and
  `warn("[RECRUITMENT CLOSE] Reason:", reason, os.clock())`.
  - The plaza prompt (`OpenStation("Recruits")`) opens through it with the NPC point.
  - The kiosk opens through it with **the kiosk's own point**, which the server now sends in ZoneOpen.
  - A second open while it is open only re-points the anchor (no second loop).
- **Walk-away, with hysteresis:** measured from the HumanoidRootPart to the point it was **opened from**. It opens
  inside the prompt (10 / 12 studs) and closes only past `EndgameConfig.Station.RecruitCloseRange = 17`
  (`EndgameConfig.RecruitShouldClose`).
- **The only close reasons:** X, WalkAway, Death, OtherMenu (another major panel opening).
  - The prompt hiding / being disabled cannot close it (nothing listens).
  - A damage scratch no longer closes it. The server's HurtLock still blocks buying while hurt.
- **Server:** `RebirthZoneService.KioskPoint(player, "drill")` (his own kiosk, keyed by UserId).
  `EndgameService.AtStation(player, "Recruits")` accepts being within BuyRange of it.

## Tests
- `tools/sim/run_recruitment_office_test.py`, 0 failed (`sim.txt`):
  - the root-cause distances per plot;
  - the hysteresis band;
  - 10 opens in a row beside the kiosk, 10 s each: no close;
  - a small walk keeps it open; a real walk-away closes it once, at 18 studs;
  - the static checks (one open / close path, the logs, the reasons, no prompt-hide close, his own kiosk, the
    server buy check).
- **NOT verified until a real device:** the open / close with a finger, and the `[RECRUITMENT ...]` lines in the
  live console.
