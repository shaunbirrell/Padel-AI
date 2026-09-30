You are a WAR EMPIRE coder on branch claude/desktop-bud (this repo). Shaun approved this job on 2026-09-30 at 19:03 Dublin, with a change to part C at 19:05 (smaller servers dropped: servers stay at 10 players). Build it exactly as written. Every number goes in config. Do not change a default without saying why in the handoff.

Written by Code Bot Roblox on 2026-09-30 from the code at `phase-7-polish` af3a858 (WE_Build 145, LATEST-HANDOFF v145). Every file, function and number below was read from that tree. If JOB 39 or JOB 40 moved something, follow the code and say what moved.

WHY (the owner's numbers, 2026-09-30): the ad brings about 2.3k clicks and about 740 visits. Average playtime is about 4 min, D1 retention is about 0%, the rating is 40%, and there are 0 Robux sales. The public API shows 880 visits and 15 favourites. New players leave in the first minutes, before they see the fun (army, fights, captures, raids). This job makes the first 3-4 minutes a guided, winning run. It adds one fair paid offer at the right moment, gives players a reason to fight each other, and asks happy players to rate the game.

ORDER RULE (strict): start JOB 41 only AFTER JOB 40 is finished and pushed. Do the 4 parts in order (A first minutes, B starter pack, C rival bases, D rate prompt link), one at a time. For each part: finish, test, commit, then push claude/desktop-bud. If you are blocked, write it in LATEST-HANDOFF and stop. Never skip a part.

GIT/RULES: the same as JOB 35-40. Run git fetch, then rebase claude/desktop-bud on the latest origin/phase-7-polish. Push only claude/desktop-bud. Never bump WE_Build, publish, build dist/, or push phase-7-polish or main (Code Bot integrates).
- Ship new gameplay owner-first behind boolean flags: OwnerFirst = true plus an Enabled kill switch, through RetentionConfig.Live(block, userId) (the JOB 29 helper: Studio or AdminConfig.IsPlaytestOwner). codebot_v101 bans "owner" strings in new configs.
- OFF must equal today's game exactly.
- Phone first: 44 px real taps, 14 px real text, 800x360 viewport.
- Build guide: docs/ROBLOX-BUILD-GUIDE.md §7 (server authority, NPC state machine), §8 (UI polish: tokens, no overlaps, one modal at a time, reserved zones) and the §11 checklist. Tick the checklist in your DONE reply.
- Checks: tools/checks/claude_bud_job41.py and `LUAU_COMPILE=$HOME/.local/bin/luau-compile python3 tools/BuyPathStatic.py` must end with 0 FAIL, and rojo build must be ok.

== HARD RULES (from Shaun; breaking any one is a FAIL) ==
1. No fast travel, ever (MapConfig.FastTravelEnabled = false, codebot_v127/v128). The world map stays tap-to-pin only. Nothing in this job moves a player or a soldier by teleport, PivotTo or snap. The only exception is the existing JOB 29 FastStart spawn (BaseService.TeleportToPlot -> RetentionService.FastStartCFrame, the join spawn itself), which stays exactly as it is.
2. REUSE, do not duplicate. The guide line is the existing gold/yellow tracker: ConsoleWaypoint (ConsoleBuyConfig.Waypoint, BeamColor 240,214,110) for base consoles and the ATM, and ObjectiveMarker (the one AlwaysOnTop objective marker plus the "WE_ObjectiveBeam" GO line) for world targets. The steps are the existing TutorialService / TutorialConfig steps. Banners, confetti and bursts are Client/Modules/Juice (JuiceConfig: Burst, Rebirth banner + Confetti 26). Funnel logging is Server/Services/AnalyticsService (AnalyticsConfig.Roblox). The timed cash boost is the ONE profile.CashBoost (CodesService.GrantCashBoost / EconomyService.CashBoostMult). The paid-offer budget is MonetizationService.ClaimSoftOfferSlot. Do not add a second tutorial, beam, banner, funnel, boost or offer system.
3. OwnerFirst = true on every new block. OFF == OLD.
4. The free game must be great on its own. Nothing in the guided run needs Robux. No Robux prompt appears before the part B gate. No "pay to skip" and no fake timers. The starter pack is not pay-to-win (no damage, HP, armour, army-size or raid-power stat).
5. ONE hostility rule, the same as JOB 40: CombatService.UnitMayHitPlayer / CombatService.ArmyHostility. The guided fight's NPCs use the normal CombatService NPC path (SpawnNPC / CombatNPC brain: LOS, hit chance, DpsCap). Shots are real on both sides: the player's gun and his army really hit them, and they really shoot back. There are no scripted kills.
6. No reward of any kind for liking, favouriting or rating (part D, same as JOB 40 part D).
7. Robux: the ONLY new SKU is the part B Starter Pack, with Id = 0 until Shaun OKs the price on Creator Hub. No other RobuxPrice or Id line changes.
8. Admin / owner accounts stay off every leaderboard (unchanged).
9. Prove the root cause before any fix: a log, probe or test that shows today's behaviour goes in the handoff.

---

== A. THE GUIDED FIRST 3-4 MINUTES (new players, 0 buildings) ==
Owner: "New players need a clear goal chain, a big fast win inside a minute, and to see their base grow."

WHAT EXISTS TODAY (read these first):
- TutorialConfig.Steps (OrderVersion 3, the owner's order while TerritoryConfig.Starter.Enabled): ClaimBase -> CommandCenter (PadBuy) -> Income (ATM) -> RecruitSoldiers (OpenArmy) -> Barracks (PadBuy) -> Outpost (Capture) -> Jeep (Garage).
  - Saved as profile.TutorialStep with TutorialOrderVersion, migrated by MigrateLegacyStep / SavedOrders / CarryDoneIds.
  - The Skip is a touch-size two-tap Skip ("STEP:TutorialSkipped").
- TutorialConfig.FastStart (JOB 29, live for everyone since codebot_v136). The new player lands StandStuds 7 in front of his own Command Center console. The first BUILD pays StarterPayout 1500 ("Starter bonus!", a coin burst to the cash pill). While WE_Onboarding is on (HoldPopupsUntilStep 3, HoldMaxSeconds 60), nothing covers the screen. RetentionController draws the FastStart pulsing arrow.
- TutorialConfig.FirstMinutes (JOB 7): a welcome line, and the first ATTACK hint once the tutorial is done (profile.FirstAttackDone).
- The Home Outpost (TerritoryConfig.Starter, F10): Starter_P<n> at plot-local X 38, Z 252 (about 100 studs out of the main gate). Radius 20, CaptureTimeSeconds 10, OwnerOnly. TODAY IT HAS NO ENEMIES: OutpostDefenders skips starter rows (OutpostDefenderConfig: "every non-starter territory"). So today's "Capture outpost" step is standing in a ring, not a fight.
- Analytics (JOB 24 §10 + JOB 29):
  - AnalyticsConfig.Roblox.Funnel is logged with LogOnboardingFunnelStepEvent for new players only (FunnelNewPlayerSeconds 900, once per profile via profile.AnalyticsFunnel). Its rows are Joined, Spawned, BaseClaimed, FirstBuilding, CollectedCash, Recruited, Barracks, FirstOutpost, FirstVehicle, TutorialDone, OpenedArmy, FirstAttack, PurchasePrompt, FirstPurchase.
  - AnalyticsService.Onboard(player, step) logs the custom event OnboardingSeconds (Value = seconds, Field = step).
  - ROOT CAUSE FIRST: pull what the Creator Hub funnel shows today (Analytics > Funnels > Onboarding, last 7 days). Write the step-by-step drop-off in docs/proof/job41/funnel-before.md. If you cannot open Creator Hub, write the query and ask Code Bot to paste the numbers. Say where most players leave. Do not guess.

NEW CONFIG: TutorialConfig.Guided (extend TutorialConfig; do not make a second tutorial config). Enabled = true, OwnerFirst = true. Live via RetentionConfig.Live. It applies only to a NEW player: TutorialComplete ~= true, the Command Center not bought, 0 buildings. A returning player never sees it.

1. THE GOAL CHAIN (a new OrderVersion 4, used only while Guided is live; versions 2 and 3 stay as they are and MigrateLegacyStep maps them). The steps are ClaimBase (auto) -> CommandCenter -> Income -> RecruitSoldiers -> FirstFight -> Outpost -> Reward. Barracks and Jeep move to AFTER Reward, as the next goals (the same steps, the same markers).
   Each step has ONE short banner (Title <= 18 characters, Hint <= 42 characters, no key names, never "click") and the yellow tracker on its target:
   a. BUILD your Command Center (ConsoleWaypoint to the console; FastStart already stands him there). The big fast win comes here, INSIDE ~60 s of the join: the BUILD lands with the Juice Burst ring, the StarterPayout 1500 coin burst and a "+$1,500" float. The Command Center model grows in with its normal build-in. Target: first BUILD <= 20 s after spawn (pin it in the sim).
   b. COLLECT cash at the ATM (ConsoleWaypoint to the ATM). Make sure there is cash to collect: PendingCash must be > 0 when the step starts. If the passive tick has not paid yet, the step waits with the line on the ATM. Never pay it twice.
   c. RECRUIT your army (the Army button outlined, the existing RecruitSoldiers step). He must be able to afford 3 soldiers with the $10,000 start + 1500 minus the Command Center. Prove the maths in the sim. If he cannot, the Guided config pays a one-time "GuidedRecruitCash" (reason "onboarding") to cover the gap exactly, not more.
   d. FIRST FIGHT at the Home Outpost (ObjectiveMarker ShowWith on Starter_P<n>, label "ENEMY CAMP"). This is the new part: while the step is live, a small "Training Camp" is at HIS Home Outpost.
      - Guided.Camp: Npc = { "Recruit", "Recruit" } (a new, weak CombatConfig NPC type "Recruit": Health 40, Damage 4, FireRate 1.2, Range 50, HitChance near/far at most 0.35 / 0.2, XP and cash from CombatService as usual). They stand on 2 sandbag posts on the Starter ring.
      - They spawn through the normal CombatService.SpawnNPC / OutpostDefenders path: an animated RigBuilder rig, leashed, LOS and hit-chance brain, the DpsCap LowTarget 12 for new players. He can never die to them in under 20 s with 3 soldiers. Prove it in the sim.
      - They are hostile only to THIS player and his army. Other players never see them fight, and they never target anyone else (under the one rule: they belong to the environment, and their target list is filtered to the owner of Starter_P<n>).
      - The army (FOLLOW) and his own gun shoot them with REAL shots. The first ATTACK hint (FirstMinutes.AttackHintText) shows here, not after the tutorial.
      - Capture cannot start while they live (TerritoryService's existing "Defeat the defenders first!" check, extended to starter rows only while the camp is up).
      - They spawn once per profile (profile.Guided.CampDone). A death, respawn or rejoin mid-step re-spawns them at full health, at most 3 times, then the step is auto-completed with a friendly line (never a soft-lock).
   e. CAPTURE it (the existing Outpost step: Starter ring, 10 s).
   f. REWARD: a banner "BASE SECURED!" plus the Juice confetti (reuse the Rebirth banner + Confetti path with its own text, JuiceConfig.Guided = { BannerSeconds 3, Confetti 26 }), a coin burst, and a one-time GuidedRewardCash (config, start at 2500, reason "onboarding") that is enough for the next building right away. Then the next goal shows (the Barracks, with the gold line), so the chain never ends on a blank screen.
   Target for the whole chain: 3-4 minutes for a new player on a phone. The sim must show the median step times.
2. VISIBLE BASE GROWTH: every step that buys or earns something shows it in the world, not only in the HUD: the build-in, the coin burst to the cash pill, the soldiers stepping out beside him, the Home Outpost flag changing to his nation flag. No new world labels (CLAUDE.md world-label rules). The existing objective marker is the only AlwaysOnTop label.
3. SKIP FOR RETURNING PLAYERS:
   - A profile with TutorialComplete, any building, or FirstJoinUnix older than Guided.NewPlayerSeconds (900) never enters Guided.
   - The existing two-tap Skip stays, and it clears the camp NPCs at once.
   - A player who rejoins mid-chain resumes at his saved step (the same TutorialStep save).
4. ONE MESSAGE AT A TIME (build guide §8):
   - The banner sits in the HUD's top stack, never under the thumbstick (left 40 % x lower 2/3), the jump / fire buttons or the top-bar pills.
   - The WE_Onboarding hold (FastStart) extends to the whole Guided chain: no daily-streak card, nation picker, promo, rate prompt or Robux offer until Reward (or Skip, or Guided.HoldMaxSeconds 300).
   - Run the HUD harness at 844x390, 956x440, 800x360, 1180x820 and 1920x1080 with the banner + objective marker + Army popover showing at once: 0 overlaps.
5. MEASURE THE FUNNEL (Creator Hub):
   - Keep the existing onboarding funnel as it is: Roblox allows one onboarding funnel per experience, and changing its order would break the history.
   - Add a SEPARATE Roblox funnel for the guided run: AnalyticsService:LogFunnelStepEvent(player, "FirstMinutes", funnelSessionId, stepIndex, stepName). There is one funnel session per profile (the saved Guided.SessionId), with the steps in this order: 1 Spawned, 2 FirstBuild, 3 Collected, 4 Recruited, 5 FightStarted, 6 FirstKill, 7 Captured, 8 Reward, 9 NextBuilding. Each step is logged once per profile.
   - Custom event "GuidedStepSeconds" (Value = seconds since spawn, Field step = the same step names), through AnalyticsService's existing custom path and its per-minute budget. Also "GuidedSkipped" (Field step = where he skipped), and "GuidedStuck" when a step passes Guided.StuckSeconds (90) (Field step).
   - Add the rows to AnalyticsConfig.Roblox (a new Funnels.FirstMinutes block + the Custom rows). Name the dashboards to open in the handoff (Analytics > Funnels > FirstMinutes, Analytics > Custom events > GuidedStepSeconds).
   - Studio: print the same lines under RetentionConfig.Funnel.PrintInStudio so the sim and the Studio test can read them.
6. OFF == OLD: with Guided.Enabled = false, or for a player it is not live for, OrderVersion 3, no camp, no new banner and no new events, exactly as today.

TESTS (part A):
- tools/checks/claude_bud_job41.py pins these:
  - the Guided flags (Enabled, OwnerFirst = true);
  - OrderVersion 4 appears only behind Guided;
  - the camp spawns through CombatService (no hum:TakeDamage, no "Health =" writes in the new code);
  - no PivotTo / SetPrimaryPartCFrame / TeleportToPlot in the new code (FastStart unchanged);
  - the funnel names match AnalyticsConfig;
  - MapConfig.FastTravelEnabled = false is unchanged.
- tools/sim/run_first_minutes_test.py (the real TutorialService / RetentionService / camp logic under luau with stubs and a fake clock) covers:
  - a new player's full chain in order, with the time for each step (first BUILD <= 20 s, whole chain 180-240 s at the scripted pace);
  - the recruit maths;
  - the camp: 2 Recruits killed by the player + 3 soldiers with real hit rolls, and the player never dies in the seeded runs;
  - capture blocked until the camp is dead;
  - the reward paid once;
  - the rejoin resume;
  - Skip at every step (the camp is cleared, "GuidedSkipped" is logged);
  - a returning profile never enters Guided;
  - OFF == OLD (OrderVersion 3, no camp);
  - every funnel step logged once, in order, with a time.
  Save its output as docs/proof/job41/funnel-sim.txt.
- STUDIO TEST (a fresh profile, Test > Play at 844x390): play the chain start to finish with the stopwatch. Paste the Studio funnel lines and the time for each step into docs/proof/job41/studio-run.md, with screenshots of each step's banner and tracker at docs/proof/job41/step_<n>.png. Add one screenshot of the reward confetti and one at 800x360.

---

== B. STARTER PACK (~49 R$, offered at the right moment, never before) ==
WHAT EXISTS TODAY (read these first):
- MonetizationConfig.DevProducts.StarterBundle "Commander Starter Pack": Id 3713839505, 149 R$, $50,000 + Auto Collect (permanent), OneTime, StarterFallbackCash 25000.
  - TODAY it is offered 3 s after the tutorial ends (TutorialService StarterBundleOffer.AfterTutorialSeconds, or 8 s after load when the tutorial is done), through MonetizationService.TrySoftOfferStarterBundle.
  - The offer is sent once per profile (StarterBundleOffered), inside Placement.StarterLimitedHours 48 and the soft-offer slot.
  - With Guided that could land at about minute 4. That is BEFORE the owner's rule, so it moves (below).
- CashSmall is 49 R$ for $10,000. It is the value bar: the new pack must clearly beat it.
- The ONE timed boost: profile.CashBoost via CodesService.GrantCashBoost(player, minutes, mult), with CodesConfig.CashBoostMult 2, CashBoostMaxMinutes 1440, WE_CashBoostUntil, and EconomyService.CashBoostMult on every non-exempt earning.
- Income: BaseService.ComputePassiveIncomePerTick(profile, player) x BaseService.IncomeMult(player).

NEW: MonetizationConfig.DevProducts.RecruitPack (a Developer Product, OneTime).
- Id = 0 until Shaun OKs the price when Code Bot makes the Creator Hub item. RobuxPrice = 49 (proposed; needs the owner's OK). DisplayName "Recruit Pack".
- The Shop skips an Id 0 product as it already does. The gate and the grant are fully testable in Studio with the admin grant path.
- The config block MonetizationConfig.RecruitPackOffer has Enabled = true and OwnerFirst = true.
1. CONTENTS (good value, NOT pay-to-win; all numbers in config):
   - Cash scaled to income: Cash = clamp(RecruitPack.IncomeMinutes 30 x his income per minute at purchase time, MinCash 25000, MaxCash 150000). It must always be at least 2.5x CashSmall's $10,000. It is computed on the server inside ProcessReceipt, and the receipt text shows the real number.
   - A temporary 2x cash boost: CodesService.GrantCashBoost(player, BoostMinutes 30, 2). This is the one boost path; it stacks the same way codes do, capped at CashBoostMaxMinutes. It is shown with the existing WE_CashBoostUntil HUD timer.
   - A cosmetic: a gold "RECRUIT" trim on his base sign (BaseSignService) and on his JOB 40 base owner marker. It is an entitlement WE_Ent_RecruitPack, saved, with no stat. Use only existing art and Part colour: no new uploads, no real-world insignia.
   - Nothing that changes damage, HP, armour, army size, raid power or protection. Pin this in the check (no Damage / Health / Army / Raid keys in the product row).
   - Relation to the 149 R$ Commander Starter Pack: they are separate SKUs, and both stay buyable in the Shop. Only ONE starter offer ever pops up per profile. While RecruitPackOffer is live, the RecruitPack offer takes the StarterBundle's pop-up slot (the StarterBundle row stays in the Shop, unchanged). Say this in ASSUMPTIONS.
2. WHEN (server decides; the client only shows it):
   - Offered ONCE per profile (profile.RecruitPackOffered), at the FIRST of these two moments: his first capture (the part A Reward step, or any first TERRITORY_CAPTURED), or 10 min (OfferAfterPlaySeconds 600) of total play (Stats.PlayTimeSeconds).
   - Never before either of those. Never during the Guided hold, combat (CombatQuietSeconds 20: no damage dealt or taken; not seated in a vehicle under fire), a purchase prompt, the rebirth screen, the rate prompt or another modal.
   - It goes through MonetizationService.ClaimSoftOfferSlot (the existing budget). If the slot is busy, it waits and retries every 30 s in that session.
   - For players it is live for, the old "3 s after the tutorial" StarterBundle pop-up does NOT fire. That is the fix for the "before 10 min" rule; show the proof log.
3. UI (phone first, build guide §8):
   - One card, not a full-screen modal, that slides in at the HUD top-right stack. Title "Recruit Pack". Three lines with icons: "$<N> Cash" (the real number for him right now), "2x Cash for 30 min", "Gold base trim". Then the price button "49 R$" (from config, never typed), "Maybe later" and an X.
   - 44 px real taps, 14 px real text. It fits 800x360 without covering the thumbstick zone or the fire / jump buttons. Theme tokens. No fake timer and no "only today" (the only real window is Placement.StarterLimitedHours, if you show it).
   - It auto-hides after 20 s. Later the pack stays in the Shop's Robux tab (top row until bought, then OWNED).
4. TELEMETRY: the existing ProductPrompted / PromptCancelled / RobuxPurchase custom events with productKey "RecruitPack", plus "RecruitPackOffered" (Field trigger = "capture" | "playtime"). Add them to the FirstMinutes funnel as the optional steps 10 Offered and 11 Bought.
5. HANDOFF NOTE (word for word in LATEST-HANDOFF): "Creator Hub: create the Developer Product 'Recruit Pack' at 49 R$ ONLY after Shaun OKs the price; then paste its Id into MonetizationConfig.DevProducts.RecruitPack.Id (Code Bot). Until then Id = 0 and the offer never prompts."

TESTS (part B): tools/sim/run_recruit_pack_test.py (the real MonetizationService gate + grant with a fake clock and stub receipts) covers:
- no offer at 9:59 of play without a capture; an offer at the first capture (3 min); an offer at 10:00 without a capture;
- only once per profile (a save + Migrate + new session keeps it off);
- never in combat, in the Guided hold or while another modal is open;
- Id 0 never prompts;
- the grant is idempotent per receipt (PurchaseId);
- the cash formula at 3 income levels (clamped);
- the boost goes through GrantCashBoost;
- the cosmetic entitlement is saved;
- the old StarterBundle 3-s pop-up is suppressed while the offer is live and fires as before when it is off (OFF == OLD).
claude_bud_job41.py pins: RecruitPack Id 0 + RobuxPrice 49, no other RobuxPrice / Id diff, no stat keys in the row, and the offer gated on capture-or-600 s.

---

== C. MORE PvP INCENTIVE: RIVAL BASES WORTH RAIDING (owner change 19:05; replaces "smaller servers") ==
Owner: "Surface nearby rival bases worth raiding (name, army size, loot estimate) with a SEND ARMY shortcut." Servers stay at 10 players: the live place has maxPlayers 10 (public API, checked 2026-09-30 ~19:10 Dublin), BaseConfig.MaxPlots 10, GameConfig.MaxPlayersPerServer 10. Do NOT change any of these, and add no Creator Hub note about server size.

WHAT EXISTS TODAY (reuse, do not duplicate):
- JOB 38 SEND ARMY: the world map's base card (MapController, sendBtn "SEND ARMY" / "BLOCKED"). RequestArmySendCheck(plotId) returns the verdict (FeaturePush "ArmySendVerdict"). The fairness rules live in Modules/ArmySendRules (self, offline, no base, ally, PvP off, shield, new player, novice shield, protection, cooldown, one active SEND, no soldiers, too weak; the power text "Your army 820 vs defences 1,240: risky"; the bully flag = half loot). ArmyPlan runs March / Siege / Loot / Return.
- Loot: MoneyCollectorService.GetRaidableBalance(victim) (PendingCash + recent auto income, capped by Cash) x ArmyOrdersConfig.LootFraction(StealFraction, bully) (ArmyLootMult 0.5).
- Live bases: MapService live.Bases (P, N, Mine). JOB 40 part E adds the base owner markers (name, flag, rank) above every base. They are the "who is out there" signal, and this part builds on them.
- NO fast travel: the shortcut sends the ARMY, which walks (ArmyPlan). The player is never moved.

NEW CONFIG: Shared/Configs/RivalConfig.luau (or a Rivals block in ArmyOrdersConfig; pick one and say which). Enabled = true, OwnerFirst = true, RefreshSeconds 10, MaxShown 3, MinLootToShow 1000, LootBuckets (for example "$1k+", "$10k+", "$100k+", "$1M+").
1. SERVER picks the targets (the client never computes loot):
   - For each viewer, list the other occupied bases that ArmySendRules would ALLOW right now (the same verdict function, the same facts; no second rule). Sort them by the loot estimate, then by distance from his base. Keep the top MaxShown.
   - Each row: plot id, DisplayName, army size (live soldier count, rounded), defence power, the power verdict text ("even", "risky", "easy", from ArmySendRules), the loot estimate as a BUCKET (never the exact balance: privacy and no exploit), and the distance.
   - Publish it on the existing MapService payload or one FeaturePush "RivalTargets" every RefreshSeconds, only to players it is live for. There is no per-frame remote and no new per-player loop beyond one shared 10 s tick.
   - Bases that are blocked (shielded, allied, new player, too strong) are simply not listed. The map card still shows the reason if he opens them.
2. UI (phone first):
   - A compact "TARGETS" pill in the HUD (next to the Army button, outside the reserved zones) with a count badge. It shows only when at least one target exists, the Guided chain is done, and he has soldiers.
   - A tap opens a small list: one row per target with the name, "Army 12", "Loot $10k+" and the verdict chip. It has two buttons: SEND ARMY (calls the same JOB 38 send path; the server re-checks) and VIEW (opens the world map on that base card; tap-to-pin only, no travel).
   - 44 px taps, 14 px text, theme tokens, one panel at a time.
   - Optional (only if it stays small): a one-line toast when a new rich target appears, at most once per 5 min, never in combat, never during the Guided hold.
3. FAIRNESS: every JOB 38 fairness rule stays the gate: new-player protection, novice shield, protection after a raid, cooldown, bully = half loot. The list never shows a player who cannot be sent at. Admins show like anyone (no leaderboard effect).
4. TELEMETRY: "RivalListOpened", "RivalSendTapped" (Field verdict) and "RivalRaidWon". PvP rate = sends per session, in the handoff.
5. OFF == OLD: no pill and no push. The map SEND ARMY is unchanged.

TESTS (part C): tools/sim/run_rival_targets_test.py:
- the list equals the set ArmySendRules allows (a table of 8 cases: shielded, ally, new player, too strong, cooldown, one active, allowed-rich, allowed-poor);
- the sort order; MaxShown; the loot buckets (never the exact number);
- the refresh is one tick for all players;
- SEND from the list uses the same path as the map (a spy on the JOB 38 handler).
Also a 2-player Studio test (Local Server, 2 clients): B sees A in TARGETS with the right bucket, taps SEND ARMY, and the army walks (no teleport) and raids. With A shielded, A is gone from B's list. Paste the logs into docs/proof/job41/rivals.md.

---

== D. "ENJOYING WAR EMPIRE? 👍" AFTER A BIG WIN (ONE system with JOB 40 part D, NO reward) ==
JOB 40 part D builds the like reminder (Shared/Configs/RatePromptConfig.luau + RatePromptService + its controller: PlaySecondsBeforeShow 900, MinGapSeconds 3 days, CombatQuietSeconds 20, once per session, profile.RatePrompt { LastShownUnix, Shows, Never }, and the card "Enjoying WAR EMPIRE?" / "Tap 👍 on the game page. It really helps!" / ⭐ Favorite / Maybe later / Don't show again). DO NOT build a second prompt. Extend that one:
1. New TRIGGERS in RatePromptConfig.Triggers: FirstCapture (the part A Reward, or the first TERRITORY_CAPTURED) and RaidWin (the first successful raid: a JOB 38 SEND that looted, or an in-person ATM raid). Each is a one-time trigger per profile (RatePrompt.Triggered[<name>] = true). It shows the card EARLY (before PlaySecondsBeforeShow) once, with all of JOB 40's other rules unchanged: the 3-day gap, combat quiet, once per session, Never, one modal at a time, and never during the Guided hold.
2. Order with part B: at the first capture, the rate card waits until the Recruit Pack card is closed or has timed out, plus 20 s (never two cards at once). If both are due, the Recruit Pack goes first; the rate card may slip to the next big win or the 15-min rule.
3. NO REWARD, no "like for ...", and nothing that claims or checks a like (there is no API). The only events are rate_prompt_shown { trigger } and rate_prompt_answer { answer }.
4. If JOB 40 part D is not on origin when you get here, STOP part D and say so in LATEST-HANDOFF. Do not build it here.
TESTS (part D): extend tools/sim/run_rate_prompt_test.py: the FirstCapture trigger shows it early once; RaidWin the same; never both in one session; the 3-day gap and Never still win; it waits for the Recruit Pack card; no economy / inventory / XP call (the JOB 40 pin still passes).

---

== ACCEPTANCE (all parts) ==
- A: a fresh profile plays the guided chain in 3-4 min, with a big win inside ~60 s (the first BUILD + payout) and a real fight at the Home Outpost (real shots both ways); the reward confetti shows; Skip and returning players work; the FirstMinutes funnel and GuidedStepSeconds show in the Studio log with the right step order and times.
- B: the Recruit Pack is offered once, only after the first capture or 10 min; the old 3-s starter pop-up no longer fires for live players; Id 0 never prompts; it is good value and not pay-to-win.
- C: TARGETS lists only raidable rivals (the ArmySendRules verdict) with the name, army size and loot bucket; SEND ARMY from it marches the army (no teleport); servers unchanged at 10.
- D: one rate card system; the big-win triggers show it once; no reward anywhere.
- Every part: OFF == OLD, BuyPathStatic 0 FAIL, rojo build ok, the §11 checklist ticked, no WE_Building* diff, PreferMesh OFF, no fast travel, and no RobuxPrice / Id diff except the new RecruitPack row (Id 0, 49).

== PROOF (required; docs/proof/job41/) ==
- funnel-before.md (today's Creator Hub funnel, or the query for Code Bot)
- funnel-sim.txt (the run_first_minutes_test.py output: steps, times, PASS / FAIL)
- recruit-pack-sim.txt, rivals-sim.txt, rate-prompt-sim.txt (the other sims)
- studio-run.md + step_<n>.png, reward_confetti.png, step_800x360.png (the fresh-profile run)
- rivals.md (the 2-player log)
- hud-harness.txt (5 viewports, 0 overlaps with the banner, objective marker, Recruit Pack card, TARGETS list and rate card)
- README.md: what each file proves and what is NOT verified until Shaun tests on his phone.

== HANDOFF + REPORT FORMAT ==
Update LATEST-HANDOFF.md with a "claude-bud JOB 41" section at the top. It needs: the flags and how to launch them (which OwnerFirst to flip), the root-cause proof (today's funnel drop-off), the step times, the B5 Creator Hub note, the dashboards to open, and these phone tests (not device-verified until Shaun tests):
 1. With a fresh test account on the phone: BUILD the Command Center in the first ~20 s, see the payout and the base grow, collect, recruit, fight the 2 camp soldiers at the Home Outpost (they shoot back), capture it, and see "BASE SECURED!" with confetti, all in about 3-4 min with the yellow line on every step.
 2. With the owner account (returning): no guided chain; Skip works on the test account at any step.
 3. The Recruit Pack card appears only at the first capture (or at 10 min), once; the Shop shows it; the price button reads 49 R$ (Id 0: no prompt until Creator Hub).
 4. TARGETS shows a rival with his name, army size and loot; SEND ARMY walks the army there; a shielded player is not listed.
 5. After the first capture or a raid win, "Enjoying WAR EMPIRE?" shows once (after the Recruit Pack card), with no reward.

Reply to Code Bot in exactly this format:
COMPLETED: <each part A-D: done / partly done / blocked, one line each, with the reason for anything not done>
FILES: <every file added or changed, one per line, with a few words on why>
TESTING: <every check / sim / Studio test run with its result (PASS=.. FAIL=..), the logs, the screenshot paths, and what is NOT verified until Shaun tests on his phone>
NEXT: <what Code Bot must do (flip flags, create the Recruit Pack product after the owner's price OK, paste the Id), open questions for Shaun, and known risks>
