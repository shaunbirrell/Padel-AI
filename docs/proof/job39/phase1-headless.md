# JOB 39 phase 1 proof: HEADLESS ONLY (claude-bud, 2026-09-30)

**Status: NOT DONE under JOB 39 §11.** Everything below is from the Luau CLI stand-in (`tools/sim/run_endgame_test.py`)
and plain arithmetic of the real config. It is NOT Roblox. The §11 item 6 Studio proof is still owed:

- [ ] WE_IncomePerSec on the HUD before / after buying Empire L1, L5 and L10 (screenshot each, owner account).
- [ ] Inside NE_N1 (the red-awning hotel on the plaza): the Chief of Staff, the prompt, the open Command Office panel at
      800x360, and one logged `[Station] Command empire ok L=<n> ...` line from the server output.
- [ ] The base EMPIRE panel with the PIN row, and the gold line to the Command Office after PIN.

Put the captures in this folder (docs/proof/job39/), named `p1-income-L1.png`, `p1-command-800x360.png`, etc.

## Expected income change (the real EmpireMult on Shaun's 23,686 $/s)
```
[EmpireTest] empire=0 mult=1.00 perSec=23,686 (+0%)
[EmpireTest] empire=1 mult=1.02 perSec=24,160 (+2%)
[EmpireTest] empire=5 mult=1.10 perSec=26,055 (+10%)
[EmpireTest] empire=10 mult=1.20 perSec=28,423 (+20%)
```
The factor multiplies every non-exempt grant (EconomyService.cashMultFor), so WE_IncomePerSec (the steady grants /
TickSeconds) moves by the same %.

## run_endgame_test.py output
```
ok    EmpireCost(1) = $5.0M (spec 5.0M)
ok    EmpireCost(2) = $5.8M (spec 5.8M)
ok    EmpireCost(3) = $6.8M (spec 6.8M)
ok    EmpireCost(4) = $8.0M (spec 8.0M)
ok    EmpireCost(5) = $9.4M (spec 9.4M)
ok    EmpireCost(6) = $11.0M (spec 11.0M)
ok    EmpireCost(8) = $15.0M (spec 15.0M)
ok    EmpireCost(10) = $20.5M (spec 20.5M)
ok    EmpireCost(12) = $28.1M (spec 28.1M)
ok    EmpireCost(15) = $45.0M (spec 45.0M)
ok    EmpireCost(20) = $98.7M (spec 98.7M)
ok    EmpireCost(25) = $216.5M (spec 216.5M)
ok    EmpireCost(30) = $474.6M (spec 474.6M)
ok    EmpireCost strictly rising
ok    no Empire level 0 / 31 for sale
ok    all 30 Empire levels = $3.24B (spec $3.24B)
ok    EmpireMult: L30 = 1.60, clamped, NaN-safe
ok    every one of 79 endgame prices is > 0 and < MaxCash 1000000000
ok    Defence L10 $68.7M, Workshop L5 $23.4M, rebirth gun Mastery L5 $32M
ok    rebirth scale: R0 1x, R3 1.6x, capped at R20 (5x)
ok    one life (15 structures + 4 businesses to max) = $16.07M (spec $16.07M)
ok    R2 life $22.5M, R20 life $80.3M (spec 22.5 / 80.3)
ok    rebirth-zone structures (Tank Factory, Nuclear Silo) are never scaled
ok    a base structure scales; scale 1 / unknown id = raw
ok    every endgame stat at its max stays <= MaxMult 3
ok    effective-HP hard cap 400
ok    Vault L10: army loot 2.5 % floor, ATM raid 7 %
ok    Black Market: the same week = the same stock, the next week changes
ok    3 different Cash items a week
ok    a week turns over at Monday 00:00 UTC
ok    income-minutes price: max(floor, N min x $/s), NaN-safe
ok    170M buys Empire L1-L12 (spec L12)
ok    then L13 is ready in 15.3 min (spec ~20)
ok    every next Empire goal from L13 is 3-300 min of income away (the longest 211 min)
[WAR EMPIRE] EndgameService Init
ok    not live (owner-first): refused, nothing spent
ok    away from the Command Office: refused (Go to the Command Office in the plaza)
ok    hurt 2 s ago: refused (the plaza is contested)
[Station] Command empire ok L=1 price=5000000 mult=1.02
ok    buy: $5.0M spent as endgame_empire, EMPIRE 1 saved (EMPIRE 1!  +2% cash)
ok    attributes: WE_EmpireLevel 1, WE_EndgameLive, WE_BaseCostScale 1.6 (R3)
ok    short of cash: refused, level unchanged (Need $5.8M)
ok    Empire 30: maxed
ok    an unknown kind is refused
ok    ScaledCost: the owner at R3 pays 1.6x, another player the raw price
ok    EmpireMultFor: owner L10 = 1.20, not live = 1
ok    State: level, next cost, the next rebirth base, the Command Office point
ok    Live.Enabled = false: factor 1, raw price, the profile is never read
ok    Live.Enabled = false: no purchase
ok    the EmpireLevel part off: no factor, no purchase
ok    the station light: no shadows, range 14
ok    the door sign MaxDistance 40
ok    the Command Office = 39 parts (config 39, cap 40)
ok    one light, one sign, no Neon, no Humanoid (not damageable)
ok    nothing answers a ray; only the table top collides
ok    the Chief of Staff's head anchors the prompt
ok    phase 1 builds only the Command Office
ok    without the endgame ctx the summary is the old one (Cash back to $10,000 / Level 1 and XP 0 / Base buildings (10 built) / War businesses)
ok    live: KEEP Empire and upgrades, RESET Next base $25.7M (R3)
ok    keep-base rebirth: no next base price (the base is kept)
ENDGAME TEST: 0 failed
ok    R1: max the base in 41.3 min vs the rebirth level in 34.1 min (+21 %)
ok    R2: max the base in 40.7 min vs the rebirth level in 37.4 min (+9 %)
ok    R3: max the base in 44.1 min vs the rebirth level in 41.5 min (+6 %)
ok    R4: max the base in 43.5 min vs the rebirth level in 46.8 min (-7 %)
ok    R5: max the base in 46.7 min vs the rebirth level in 52.9 min (-12 %)
ok    R6: max the base in 45.5 min vs the rebirth level in 60.0 min (-24 %)
NOTE  R7: max the base in 46.8 min vs the rebirth level in 68.3 min (-31 %)  <- outside the spec's 25 %: owner decision, see ASSUMPTIONS JOB 39
ok    structure income reads the raw Costs (BalanceConfig never sees the scale)
ok    PrestigeService never clears profile.Endgame (kept on both paths)
ok    no Robux path to the endgame (MonetizationService never grants it)
ok    no PivotTo / fast travel / teleport in the new code
ok    no Health writes in the new code
```
