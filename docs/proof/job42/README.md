# JOB 42 proof

| File | What it proves | Status |
|---|---|---|
| amounts-sim.txt | The five packs at income 0 .. 1,000,000 $/min (+ NaN / negative / 1e13): $ and $ per R$; the floor wins below the crossover (667 / 833 $/min), the minutes above; $ per R$, minutes per R$ and floor $ per R$ all rise with the price (BEST VALUE on 4h is honest) | Done (headless, real configs) |
| receipt-order.txt | The real ProcessReceipt: the income lookup (yielding) runs before AddCash; leave / profile swap during the yield -> nothing granted; one grant per PurchaseId; the receipt-time income wins; a running 2x boost does not change the amount; reason devproduct | Done (headless, the real MonetizationService) |
| gating-sim.txt | Not Ready (any Id 0) -> not shown; live + Ready -> shown; OFF -> not shown; the Mega slot sells Cash4h while shown; an old-pack receipt keeps the JOB 36 formula; the old four stay in config | Done (headless) |
| recruit-pack-align.txt | The Recruit Pack cash = the 30-min pack while live (incl. above the old 150k cap), the JOB 41 clamp when off; the card's $; the boost + trim still grant | Done (headless) |
| shop-render.txt | The REAL ShopController.Init: owner / uid 9, Ids 0 / Ids set. The five time rows (titles, live amounts, prices, order, BEST VALUE), the old four hidden, the + lands on 4h; OFF == OLD; phone text budgets | Done (headless; rows + text budgets, NOT a pixel-overlap measurement) |
| shop_800x360.png, shop_desktop.png, shop_newplayer.png | Studio screenshots | **Owed** (needs Studio) |

## NOT verified until Shaun tests on his phone
- A real purchase (needs the five Creator Hub Ids).
- The rows at 800x360 / 956x440 on a device.
- The live amount following the HUD income.
