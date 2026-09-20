# Monetization gap — competitor RhGjQXJ8n6w vs WAR EMPIRE

**Date:** 2026-09-20 · Live WE ~v26  
**Source:** playthrough clips 0–8 / 8–16 / 16–20 / 20–28 (watching) + stills

## Competitor patterns (observed)

| Moment | Offer | Price signal | Trigger |
|--------|-------|--------------|---------|
| Early pads | Premium colored pads (yellow Speed, red Auto/2x) among green buys | cheap–mid Robux | Always visible on base floor |
| Cash HUD `+` | Soft currency / Robux shop | — | Persistent |
| After swarm loss | 2x Money gamepass | ~240 R$ | Frustration / death |
| Mid expand | Fast Speed | ~2 R$ micro | Impulse |
| Mid expand | Golden Pumpjack | ~24 R$ | Cosmetic+income flex |
| Late grind | Mega Pack ~$10M cash | ~800 R$ | Pay-to-skip last % to rebirth |
| Rebirth | Soft fee in cash | in-game $ | Prestige gate |

## WAR EMPIRE today (MonetizationConfig)

**Stubs Id=0 (need Creator Dashboard):** VIP 199, 2x Cash 149, Double XP 99, Auto Collect 99, Elite theme 79, Cash S/M/L 49/149/399, Gold packs, Battle Pass 499, Extra Soldier, Instant Barracks, SpeedBoost death offer.

**Live systems that monetize well once IDs exist:** MoneyCollector AutoCollect, DeathShopOffer, Shop dock, PendingCash loop.

## P0 ship (after Dashboard IDs)

1. Create live DevProducts/GamePasses matching stubs; wire Ids in MonetizationConfig  
2. Floor **premium pads** (red Auto Collect / yellow Speed) next to green buys — competitor pattern  
3. Cash pack **Mega** tier (~800 R$ / large cash) for late rebuild slog  
4. Death / lose-fight prompt already exists — ensure Shop shows 2x + Speed with real PromptProductPurchase  

## P1

5. Golden oil pump cosmetic entitlement (PlotOilPump dress variant)  
6. Starter bundle (cash + AutoCollect)  
7. Rebirth skip / keep-more bundle  
8. Leaderboard Robux gift / VIP tag  

## Blocked on Shaun

- Rename experience + API Services  
- Create products in Creator Hub → paste Ids (or Open Cloud catalog)



## Video finish 2026-09-20 (clips 3–8 + 20–28)

### Competitor SKU map (observed)
| SKU | Pad R$ | Shop R$ | Placement |
|-----|--------|---------|-----------|
| Auto Collect | 39 | 32 | ATM path + shop |
| 2x Money | 299 | — | ATM cluster |
| Speed Boost | 2 | — | ATM cluster (impulse micro) |
| Golden Pumpjack | 29 | — | ATM cluster |
| Mega Pack $10M | — | 800 | Shop hero “Best Offer!” |
| Reaper squad | — | 1200 | Top of Barracks menu (P2W) |
| Rebirth | soft $ | — | UI: “Keep all your Robux Items!” |

### WE status (v27) — already live systems
- Gate guards / HMG, ATM 10% raid, contested outposts, Orders walkie, Missions dock, BaseCeiling, real-scale kits, jeep LV+hinge fix
- MonetizationConfig stubs Id=0 — **blocked on Creator Hub mint** then wire

### Ship next (business)
1. Wire live product IDs → Shop prompts charge Robux
2. Premium pads at MoneyCollector (AutoCollect / DoubleCash / SpeedBoost / optional GoldenPump)
3. Shop hero Mega cash pack
4. Rebirth confirm: “Keep all Robux purchases”
5. Optional: premium squad slot in Army UI (later)
