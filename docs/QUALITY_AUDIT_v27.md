# WAR EMPIRE — Quality audit v27 → v28

**Date:** 2026-09-20 Europe/Madrid (UTC+2)  
**Live baseline:** Open Cloud **versionNumber=27** (jeep drive fixed)
**Shipped this pass:** Open Cloud **versionNumber=28**  
**Place:** `97112936860418` · Universe `10767159222`  
**Branch:** `phase-7-polish`

## Audit scope

Code-level wiring + shippable P0 polish. MonetizationConfig product/gamepass **Ids left at 0** (Creator Hub minting separate). Did not invent Creator Store IDs.

---

## 1) Bootstrap service wiring — PASS

`Bootstrap.server.luau` safeRequires + safeInits all critical services:

| Service | Wired |
|---------|-------|
| VehicleService | yes |
| GateDefenseService | yes |
| ManualDropperService | yes |
| PlotOilPumpService | yes |
| PrestigeService | yes |
| MissionService | yes |
| SquadOrdersService | yes |
| MoneyCollectorService | yes |
| MonetizationService (ProcessReceipt) | yes — `MarketplaceService.ProcessReceipt` assigned in Init |

Client: `UIController` inits Shop / Missions / Orders / HUD / WorldPrompt; dock tiles Base/Shop/Rebirth/Missions/Army/Garage/Settings.

---

## 2) ShopController — PASS (+ P0 ship)

- Catalog still **lists** all DevProducts / GamePasses when `Id=0` with subtitle `coming soon (no charge)`.
- `PromptProductPurchase` / `PromptGamePassPurchase` only when `Id ~= 0`.
- Id=0: intent remote + warn / Notify “placeholder ID” — no charge, no fake grant.
- ProcessReceipt path correct: grants only for known non-zero product Ids; unknown marked processed to drain queue.

### P0 shipped this pass

- **Cash HUD `+`** (`CashPlus`) on currency pill → opens Shop via `HUDController.BindShopOpener` ← `UIController`.
- **Pending cash line** (`PendingLabel` TextButton) also opens Shop when visible (upsell entry without confusing floor pads).

---

## 3) Premium floor pads (AutoCollect / 2x) — SKIPPED

Monetization Ids still **all 0**. Floor premium pads that Prompt on stand would toast “not configured” and confuse players. Deferred until Creator Hub Ids are wired.

**When Ids live:** add red Auto Collect / yellow 2x pads beside green buys (competitor RhGjQXJ8n6w pattern); Prompt only if Id≠0.

---

## 4) MapSetup / VehicleService — PASS (no regression found)

- MapSetup: Ground heal / ForceRebuild / void fallback / upgrade pad retag intact.
- VehicleService v27: authoritative `LinearVelocity` + same-sign hinge differential; mesh dress-only. No further shippable drive bugs found in this audit.
- Experience rename still pending in Creator Hub (`docs/LIVE_PLACE.md`: still *Untitled Experience*).

---

## 5) Remaining gaps (do not block this ship)

### Blocked on Shaun / Creator Hub

1. Rename experience → **WAR EMPIRE**; enable API Services (DataStores).
2. Mint DevProducts / GamePasses; paste Ids into `MonetizationConfig` (or `tools/wire-monetization-ids.py` once Ids known).
3. Then: floor premium pads + death-shop Prompt path lights up automatically (code already gates on Id≠0).

### P1 backlog (quality / competitor)

| Gap | Notes |
|-----|-------|
| Floor chevron polish | Exists; densify toward unpaid pads |
| Mesh kit density | Design Bot IDs; Part kits remain fallback |
| Golden pumpjack cosmetic | Needs entitlement + dress variant |
| Mega cash pack ~800 R$ | Add DevProduct stub + Id when Hub ready |
| Leaderboard Rebirths column | P1 |
| Capture zone name/flag polish | Contested +10% already live |
| Character crouch anim at stalls | T-pose note pending |

### Intentional stubs

- All `MonetizationConfig` Ids = 0  
- `BattlePassConfig.PremiumProductId = 0`  
- `LootBoxConfig.PolicyPending = true` (display locked in Shop)

---

## 6) Verification this pass

- `python3 tools/BuyPathStatic.py` — must PASS including CashPlus / BindShopOpener / Bootstrap wires  
- `rojo build` → `dist/WarEmpire-PERF.rbxlx`  
- Open Cloud Published (if this doc accompanies a ship)

## Files touched (v28 polish)

- `src/StarterPlayer/.../HUDController.luau` — CashPlus + pending→Shop  
- `src/StarterPlayer/.../UIController.luau` — BindShopOpener  
- `tools/BuyPathStatic.py` — regression checks  
- `docs/QUALITY_AUDIT_v27.md` — this file  

**MonetizationConfig Ids: unchanged.**
