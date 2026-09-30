You are a WAR EMPIRE coder on branch claude/desktop-bud (this repo). Shaun approved this job on 2026-09-30 at 19:43 Dublin. Build it exactly as written. Every number goes in config. Do not change a default without saying why in the handoff.

Written by Code Bot Roblox on 2026-09-30 from the code at `phase-7-polish` 5141a5f (WE_Build 145, LATEST-HANDOFF v145). Every file, function and number below was read from that tree. If JOB 39, 40 or 41 moved something, follow the code and say what moved.

WHY (owner, 2026-09-30 19:43): the fixed cash packs ($10k / $50k / $200k / $2M) are either worthless or game-breaking depending on how far along a player is. JOB 36 already scales them (max(Floor, Minutes x income)), but the rows still read "Cash Pack S / M / L / Mega", so the player cannot see what he is buying. The owner wants TIME-based packs that say what they are: "buy X minutes of your cash".

ORDER RULE (strict): start JOB 42 only AFTER JOB 41 is finished and pushed. Do the parts in order (A config + server grant, B Shop UI + offers, C align the JOB 41 Recruit Pack, D docs), one at a time. For each part: finish, test, commit, then push claude/desktop-bud. If you are blocked, write it in LATEST-HANDOFF and stop. Never skip a part.

GIT/RULES: the same as JOB 35-41. Run git fetch, then rebase claude/desktop-bud on the latest origin/phase-7-polish. Push only claude/desktop-bud. Never bump WE_Build, publish, build dist/, or push phase-7-polish or main (Code Bot integrates).
- Owner-first behind boolean flags: OwnerFirst = true plus an Enabled kill switch, through RetentionConfig.Live(block, userId) (Studio or AdminConfig.IsPlaytestOwner). codebot_v101 bans "owner" strings in new configs.
- OFF must equal today's game exactly (the JOB 36 scaled S / M / L / Mega rows, offers and receipts).
- Phone first: 44 px real taps, 14 px real text, 800x360 viewport.
- Build guide: docs/ROBLOX-BUILD-GUIDE.md §7 (server authority), §8 (UI polish) and the §11 checklist. Tick it in your DONE reply.
- Checks: tools/checks/claude_bud_job42.py and `LUAU_COMPILE=$HOME/.local/bin/luau-compile python3 tools/BuyPathStatic.py` must end with 0 FAIL, rojo build must be ok, and every older claude_bud_job* / codebot_v* check still passes (update a JOB 36 / JOB 41 pin only if this job really changes that line, for example the JOB 41 "no other RobuxPrice / Id diff" pin must now allow the five Id 0 rows; say which).

== HARD RULES (from Shaun; breaking any one is a FAIL) ==
1. EXACTLY these five packs, these prices: 15 min 25 R$, 30 min 49 R$, 1 hour 89 R$, 2 hours 159 R$, 4 hours 279 R$. NO 1-day pack and NO 7-day pack (not in config, not in UI, not as Id 0 placeholders).
2. Every new product Id = 0 until Code Bot creates it in the Creator Hub. An Id 0 product never prompts and is never shown as buyable (the Shop already skips Id 0).
3. The old CashSmall / CashMedium / CashLarge / CashMega rows stay in MonetizationConfig.DevProducts with their Ids, prices and Cash unchanged. ProcessReceipt keeps granting them (a paid receipt is never dropped; the JOB 36 scaling still applies to them). They are only HIDDEN from the Shop and the offers once the time packs are live (definition in A3).
4. REUSE, do not duplicate: the income number is MonetizationService.PassivePerMin (JOB 36); the formula helper lives next to ShopOverhaulConfig.CashPackAmount; the live display reuses the ShopOverhaulService publish tick (PerMinPublishSeconds 10, the ONE loop) and ShopController's refreshPacks; the receipt goes through the existing ProcessReceipt (idempotent per PurchaseId, the v71 J2/M1 "compute everything before the first mutation" rule). No second income function, no second publish loop, no second receipt path.
5. The amount is computed on the SERVER at receipt time. The client number is display only. The income lookup (it may yield) runs BEFORE the first grant mutation, and the player + profile are re-checked after it (return NotProcessedYet if either changed), exactly like the JOB 36 block in ProcessReceipt.
6. No RobuxPrice / Id diff anywhere except the five new rows (Id 0). The JOB 41 RecruitPack row stays Id 0, 49 R$.
7. Cash only: no damage, HP, armour, army-size, raid-power or protection keys in any new row. No fake timers, no "only today".

---

== A. CONFIG + SERVER GRANT ==
WHAT EXISTS TODAY (read these first):
- MonetizationConfig.DevProducts: CashSmall 3713838744 49 R$ $10,000; CashMedium 3713838815 149 R$ $50,000; CashLarge 3713838888 399 R$ $200,000; CashMega 3713838952 799 R$ $2,000,000.
- ShopOverhaulConfig (JOB 36, Live Enabled = true, OwnerFirst = false since codebot_v142): CashPacks { CashSmall Floor 10000 Minutes 5, CashMedium 50000 / 20, CashLarge 200000 / 60, CashMega 2000000 / 180 }, CashPackAmount(key, perMin) = max(Floor, floor(Minutes x perMin)) with the NaN / <= 0 / >= 1e12 guard, PerMinAttribute "WE_PassivePerMin", PerMinPublishSeconds 10.
- MonetizationService.PassivePerMin(player, profile) = BaseService.ComputePassiveIncomePerTick x EconomyService.GetCashMult(player, "passive") / TickSeconds x 60. NOTE: GetCashMult includes the TIMED profile.CashBoost (EconomyService.CashBoostMult) and the Double Cash event.
- ProcessReceipt: the JOB 36 block ("claude-bud JOB 36: a cash pack scales ...") looks up perMin, re-checks `player.Parent` and `DataService.GetProfile(player) ~= profile`, then sets cashGrant; the grant is EconomyService.AddCash(player, cashGrant, "devproduct") (multiplier-exempt).

NEW:
1. MonetizationConfig.DevProducts, five rows (Id 0, a plain Cash = the Floor so any code that reads .Cash stays sane):
   - Cash15m = { Id = 0, DisplayName = "15 Minutes of Cash", RobuxPrice = 25, Cash = 10000, Gold = 0 }
   - Cash30m = { Id = 0, DisplayName = "30 Minutes of Cash", RobuxPrice = 49, Cash = 25000, Gold = 0 }
   - Cash1h = { Id = 0, DisplayName = "1 Hour of Cash", RobuxPrice = 89, Cash = 50000, Gold = 0 }
   - Cash2h = { Id = 0, DisplayName = "2 Hours of Cash", RobuxPrice = 159, Cash = 100000, Gold = 0 }
   - Cash4h = { Id = 0, DisplayName = "4 Hours of Cash", RobuxPrice = 279, Cash = 200000, Gold = 0 }
   (Repeatable dev products, not OneTime.)
2. ShopOverhaulConfig.TimePacks (one block, next to CashPacks):
   - Enabled = true, OwnerFirst = true (the kill switch is Enabled).
   - Packs (in Shop order, biggest first): Cash4h { Minutes 240, Floor 200000, Title "4 HOURS OF CASH" }, Cash2h { 120, 100000, "2 HOURS OF CASH" }, Cash1h { 60, 50000, "1 HOUR OF CASH" }, Cash30m { 30, 25000, "30 MIN OF CASH" }, Cash15m { 15, 10000, "15 MIN OF CASH" }.
   - The Floors are the "sensible minimum for new players" (proposed; say so in the handoff). They are chosen so that both the minutes per R$ AND the floor $ per R$ rise with the price (15m 0.60 min / 400 $ per R$ -> 30m 0.61 / 510 -> 1h 0.67 / 562 -> 2h 0.75 / 629 -> 4h 0.86 / 717), so a bigger pack is always the better deal at every income level, and the 4h tag is honest. Pin this in the sim.
   - BestValueKey = "Cash4h", BestValueLabel = "BEST VALUE" (the 4h row only; the pass-row BEST VALUE on 2x Cash is unchanged).
   - ExcludeTimedBoosts = true: the pack income leaves out the TIMED multipliers (profile.CashBoost and the Double Cash event), so "4 hours of your cash" does not double while a code / Recruit Pack boost runs and the price of the pack is stable. Permanent multipliers (2x Cash pass, VIP, rebirth, etc.) stay in. Implement it as an option on the ONE income function (for example PassivePerMin(player, profile, excludeTimed: boolean?) dividing out EconomyService.CashBoostMult(profile) and the event mult), not a second function. If you find a cleaner split, say why.
   - HideOldKeys = { CashSmall = true, CashMedium = true, CashLarge = true, CashMega = true }.
   - PerMinAttribute = "WE_TimePackPerMin" (display only), published by the SAME ShopOverhaulService tick as WE_PassivePerMin, only to players the block is live for. No new loop.
   - Helpers: ShopOverhaulConfig.TimePacksLiveFor(userId) (RetentionConfig.Live(TimePacks, userId)); ShopOverhaulConfig.TimePackAmount(key, perMin) (same guard as CashPackAmount; returns nil for a key that is not a time pack; result is an integer, clamped to at most 2^53); ShopOverhaulConfig.TimePacksReady() = all five Ids ~= 0 in MonetizationConfig.
3. "LIVE" for the Shop swap = TimePacksLiveFor(userId) AND TimePacksReady(). Until Code Bot pastes all five Ids, a live player still sees the old JOB 36 rows (never an empty cash section). In Studio (Ids 0) the new rows render with the price button disabled ("SOON") so the layout can be tested, and the grant is tested through the admin grant path / the sim.
4. ProcessReceipt: extend the JOB 36 block, do not add a second one. If productKey is a TimePacks key: perMin = PassivePerMin(player, profile, ExcludeTimedBoosts), then the same re-check (player.Parent, same profile) -> NotProcessedYet, then cashGrant = TimePackAmount(key, perMin). This runs for ANY receipt of a time pack Id, live flag or not (a paid receipt is always granted the real amount). Grant with AddCash "devproduct" (exempt, so it is never multiplied again). The receipt / toast text shows the real granted number ("+$1,234,567 (4 hours of cash)").
5. Telemetry: the existing ProductPrompted / PromptCancelled / RobuxPurchase events with productKey Cash15m..Cash4h, plus a field PerMinBucket (a bucket, not the exact income) on RobuxPurchase so the owner can see who buys which size.

TESTS (part A): tools/sim/run_time_packs_test.py (the real ShopOverhaulConfig + MonetizationConfig + the real MonetizationService receipt code with stubs, like run_shop_test.py):
- AMOUNT SIM: a table of the five packs at income 0, 100, 500, 1,000, 5,000, 25,000, 100,000 and 1,000,000 $/min (plus NaN, negative and 1e13 -> the floor). Print $ and $ per R$ for each cell; assert the floor wins at low income, the minutes win above the crossover (Floor / Minutes = 667 $/min for 15m, 833 for 30m and 1h and 2h and 4h), and that $ per R$ rises with the price in every row. Save the output to docs/proof/job42/amounts-sim.txt.
- RECEIPT ORDER: a stub PassivePerMin that yields and records the call order: the income lookup happens BEFORE AddCash / any profile write; a player who leaves during the yield -> NotProcessedYet, nothing granted; a profile swap during the yield -> NotProcessedYet; the same PurchaseId twice -> granted once; the amount uses the income AT RECEIPT time (change the stub income between "prompt" and "receipt": the grant follows the receipt-time income, not the shown number); a time boost running (CashBoost 2x) does not change the amount with ExcludeTimedBoosts = true; the grant reason is "devproduct" (not multiplied again). Save to docs/proof/job42/receipt-order.txt.
- GATING: TimePacks OFF -> the Shop, offers and receipts equal today (the old JOB 36 rows, the old amounts); live but not Ready -> old rows; live and Ready -> the five new rows, the old four hidden; an old-pack receipt is still granted by the JOB 36 formula while the time packs are live; Id 0 never prompts.

---

== B. SHOP UI + OFFERS (phone first) ==
WHAT EXISTS TODAY: ShopController cashOrder { "CashMega", "CashLarge", "CashMedium", "CashSmall" } with the Mega hero row "★ BEST OFFER"; the live amounts via cashPackAmount + refreshPacks on WE_PassivePerMin; ShopOverhaulConfig.Order places ^ShopRow_CashMega$ .. ^ShopRow_CashSmall$; OpenCashPacks() / highlightCashMegaRow (the cash pill's +); the offers that sell a cash pack: MonetizationService.TrySoftOfferCashMega (Mega toast after a big collect / death), the Placement AfterRebirth "Fresh start boost" (CashLarge), and VehicleController's "Short on cash for <vehicle>" (fp_garage_cash, the first pack whose amount >= need).

NEW (only while LIVE as in A3; otherwise nothing changes):
1. Rows: one row per time pack, order 4h, 2h, 1h, 30m, 15m, in the cash-pack place of ShopOverhaulConfig.Order (add ^ShopRow_Cash4h$ .. ^ShopRow_Cash15m$ patterns there; the old four patterns stay for OFF). Each row: the title in caps "4 HOURS OF CASH" (from config), under it the live amount "$1,234,567" (TimePackAmount with WE_TimePackPerMin, commas), and the price button "279 R$" from config (never typed). The 4h row carries the "BEST VALUE" tag (reuse the existing tag style from the 2x Cash row). While the floor is what he gets, the amount line may add "(minimum)" so a new player is not confused; no other extra text.
2. The live amount refreshes on the attribute change (the same refreshPacks hook) and never flickers to $0 (use the floor until the first publish).
3. The old four rows are hidden (HideOldKeys). Their Ids stay in config.
4. Offers (same slots, same budget, just the product swapped): the Mega toast sells Cash4h (title "4 HOURS OF CASH: $<N>"); the rebirth "Fresh start boost" sells Cash1h; the garage "Short on cash" picks the SMALLEST time pack whose live amount >= need (else Cash4h); OpenCashPacks highlights the Cash4h row. OFF or not Ready -> the old products exactly.
5. 44 px taps, 14 px text, theme tokens, no overlaps at 800x360 (run the existing Shop render harness: tools/sim/run_shop_render_test.py, extended for the new rows; 0 overlaps, 0 clipped text at 5 viewports).
6. Studio screenshots: docs/proof/job42/shop_800x360.png and shop_desktop.png (new rows, BEST VALUE on 4h, a live amount), plus one at a new-player income (the floors).

---

== C. ALIGN JOB 41 PART B (the Recruit Pack) ==
JOB 41 part B set the Recruit Pack cash to clamp(IncomeMinutes 30 x income per min, MinCash 25000, MaxCash 150000). Owner 19:43: the Recruit Pack cash component = the 30-min pack amount, still 49 R$.
1. While TimePacks is live for the player: RecruitPack cash = ShopOverhaulConfig.TimePackAmount("Cash30m", perMin) computed in ProcessReceipt with the same income lookup and re-check (A4). This drops the 150,000 cap and keeps the 25,000 minimum (= the Cash30m Floor). Put it in config as RecruitPack.CashFromTimePack = "Cash30m" (no second formula). The Recruit Pack card line "$<N> Cash" shows the same live number as the 30 MIN OF CASH row.
2. The rest of the Recruit Pack is unchanged: RobuxPrice 49, Id 0 until Shaun OKs it, the 2x 30-min boost through CodesService.GrantCashBoost, the gold RECRUIT trim, the one-time gate (first capture or 600 s). So it stays clearly better than buying Cash30m alone (same cash + the boost + the trim, same 49 R$). Say this in ASSUMPTIONS.
3. TimePacks OFF -> the JOB 41 formula exactly (OFF == OLD).
4. If JOB 41 part B is not on origin when you get here, STOP part C and say so in LATEST-HANDOFF.
TESTS (part C): extend tools/sim/run_recruit_pack_test.py: at 4 income levels the Recruit Pack cash == TimePackAmount("Cash30m") (live) and == the JOB 41 clamp (off); the boost and trim still grant; still Id 0 / 49 R$.

---

== D. DOCS ==
1. docs/SHOP.md: add the five time packs to the product table (key, name, price, Id 0 until created, "N minutes of your income, min $X", where sold), mark the old four "hidden from the Shop while the time packs are live (receipts still granted)", update the Shop order list (the cash section is now 4h .. 15m, BEST VALUE on 4h) and the Recruit Pack line (cash = the 30-min pack).
2. ASSUMPTIONS.md: the floors, ExcludeTimedBoosts, the Ready rule (all five Ids), the Recruit Pack alignment.
3. LATEST-HANDOFF.md, a "claude-bud JOB 42" section at the top, with this Creator Hub note word for word: "Creator Hub (Code Bot): create five Developer Products: '15 Minutes of Cash' 25 R$, '30 Minutes of Cash' 49 R$, '1 Hour of Cash' 89 R$, '2 Hours of Cash' 159 R$, '4 Hours of Cash' 279 R$ (description: 'Instantly get cash equal to <N> of your current income.'). Paste the Ids into MonetizationConfig.DevProducts Cash15m / Cash30m / Cash1h / Cash2h / Cash4h. The Shop keeps the old packs until all five Ids are in. Do NOT create a 1-day or 7-day pack."

== CHECK: tools/checks/claude_bud_job42.py pins ==
- the five rows with Id 0 and prices 25 / 49 / 89 / 159 / 279; no pack with 1440 / 10080 Minutes and no "1d", "24h", "7d", "Day" or "Week" in any DevProducts cash key / DisplayName or TimePacks key / Title (the existing "daily VIP crate" text is not a pack and is out of scope);
- no other RobuxPrice / Id diff (the old four unchanged, RecruitPack Id 0 / 49);
- TimePacks Enabled = true, OwnerFirst = true; BestValueKey "Cash4h";
- ProcessReceipt: the time-pack income lookup sits before the first AddCash and is followed by the player + profile re-check;
- no stat keys (Damage / Health / Armour / Army / Raid / Protect) in the new rows;
- the Shop hides the old four only behind TimePacksLiveFor + TimePacksReady.

== ACCEPTANCE ==
- A live player with all five Ids sees exactly five cash rows "15 MIN OF CASH" .. "4 HOURS OF CASH" with his live $ amount, BEST VALUE on 4h, prices 25 / 49 / 89 / 159 / 279 R$; the old four are gone from the Shop and the offers.
- Buying grants the receipt-time amount (server), once per PurchaseId, never multiplied again.
- A new player gets the floor ($10k .. $200k).
- OFF, or Ids still 0: today's Shop exactly. Old-pack receipts still granted.
- The Recruit Pack cash == the 30-min pack amount while live.
- 0 FAIL on claude_bud_job42.py and BuyPathStatic, rojo build ok, §11 ticked, no WE_Build diff, no publish.

== PROOF (required; docs/proof/job42/) ==
- amounts-sim.txt (the amount table at every income level, $ per R$, PASS / FAIL)
- receipt-order.txt (the call-order log and the leave / swap / duplicate / receipt-time / boost cases, PASS / FAIL)
- gating-sim.txt, recruit-pack-align.txt, shop-render.txt (5 viewports, 0 overlaps)
- shop_800x360.png, shop_desktop.png, shop_newplayer.png
- README.md: what each file proves and what is NOT verified until Shaun tests on his phone (the real purchase needs the Creator Hub Ids).

== HANDOFF + REPORT FORMAT ==
Phone tests for Shaun (not device-verified until he tests): 1. On the owner account, open the Shop: five time rows, BEST VALUE on 4h, the $ amounts match about N minutes of the income shown on the HUD. 2. Buy 15 MIN OF CASH (25 R$): the cash goes up by the shown amount (± the last 10 s of income change). 3. The cash pill + opens the Shop on the 4h row. 4. A test account (not owner) still sees the old packs until the flag is flipped. 5. The Recruit Pack card shows the same $ as 30 MIN OF CASH.

Reply to Code Bot in exactly this format:
COMPLETED: <each part A-D: done / partly done / blocked, one line each, with the reason for anything not done>
FILES: <every file added or changed, one per line, with a few words on why>
TESTING: <every check / sim / Studio test with its result (PASS=.. FAIL=..), the logs, the screenshot paths, and what is NOT verified until Shaun tests on his phone>
NEXT: <what Code Bot must do (create the five products, paste the Ids, flip OwnerFirst after the owner's phone test), open questions for Shaun (the floors, whether to cap the 4h amount), and known risks>
