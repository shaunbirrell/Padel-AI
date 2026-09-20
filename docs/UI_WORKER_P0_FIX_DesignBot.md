# P0 FIX — Overlapping UI + Blocky Workers (Shaun screenshot)
**Date:** 2026-09-20 · Design Bot  
**Shot issues:** Radar Lv5 board stacked on COLLECT ATM; +$/tick + WORKER tags unreadable; brown block workers (Part kit).

---

## LOOK

### World billboards (must not stack)
Priority when camera is near multiple adornee (highest wins, others hide or shrink):

| Priority | Billboard | StudsOffset Y | MaxDistance | AlwaysOnTop |
|---------:|-----------|---------------|-------------|-------------|
| 1 | COLLECT / ATM (`WE_CollectBillboard` or similar) | **6.5** | 28 | true only if nearest |
| 2 | Structure BUY / Lv MAX (`WE_PriceBillboard`) | **5.2** | 48 | **false** if ATM within 12 studs |
| 3 | Training `+$/tick` (`WE_TrainingEarnBillboard`) | **3.2** above yard pad (not worker head) | 22 | false |
| 4 | WORKER nametag | **2.4** above head | 18 | **false** |

**Rules**
1. **One primary AlwaysOnTop** per screen region — never ATM + Radar + earn pop all AlwaysOnTop.
2. When player within **12 studs** of MoneyCollector: hide or fade structure price billboards (Transparency 1 / Enabled false).
3. WORKER label: small muted text (`Muted` Color3), font size ≤14, no yellow scream; rename to **“TRAINING”** or omit name and use rank pip only.
4. `+$N` earn pop: short lifetime (0.6s), rise then destroy; **do not** leave persistent center float.
5. Dock (Base/Shop/…): gunmetal circles `Constants.Colors.Gunmetal`, olive Accent on selected, GoldBright 1px stroke — **not** rainbow candy icons. Prefer Unicode 🏗🛒🔁📋🪖🚗⚙️ or Decal gold coin `8261389836` for Gold only.
6. Cash pill: READY / Collect CTA must **not** overlap cash text — put READY as separate chip left of pill or under pending line.

### Workers = real Creator Store addons
Live `VisualAssetConfig.Characters` already has realistic IDs, but screenshot shows **Part-kit placeholder** (brown camo boxes). Mesh insert is failing or never called on TrainingYard workers.

---

## ASSETS

| Role | VisualKind | ModelAssetId | Catalog | Action |
|------|------------|-------------:|---------|--------|
| Worker (TrainingYard) | **Infantry** (change from Soldier) | **9104381136** | Layered clothing realistic soldier | Camo/helmet reads as “Roblox military addon” |
| Soldier default | Soldier | **100212659702941** | Realistic soldier StarterCharacter | Keep |
| Guard* | Guard | **16134469614** | Rigged Soldier | Keep |
| Heavy | HeavyInfantry | **14776506955** | Army of Soldiers pack | Keep for density |

**Config edits**
```lua
-- SoldierConfig.Visual.VisualKindByRole
Worker = "Infantry", -- was "Soldier"

-- VisualAssetConfig.Characters add explicit:
Worker = { ModelAssetId = 9104381136, Note = "TrainingYard worker — realistic layered soldier" },
```

**Reject as worker look:** Part-kit camo boxes; plastic Rthro 3924234975; Respawn pack; SWAT.

---

## NOTES — Code Bot implement checklist
1. **SoldierService / MapSetup:** On every Worker spawn, call `VisualAssetService` character dress with `Infantry`/`Worker` ID; if insert fails, retry once then olive **R15** dummy — never brown brick rifleman.
2. **StudioSkipWorldDressing:** If true, workers stay Part kit — force dress for characters even when world dress skipped, OR document StudioForceDress for NPCs.
3. **WorldPromptController:** `AlwaysOnTop = false` on price boards; ATM proximity hides price boards; lower WORKER tag distance/offset.
4. **SoldierService earn billboard:** Parent to TrainingYard pad part, not each worker head; kill persistent center stack.
5. **HUD dock:** restyle per LOOK (gunmetal + accent); fix READY vs cash overlap.
6. StripScripts on soldier inserts; scale ~1.0; crouch anim optional at stalls.

---

## NEXT
Ship this P0 before more map props. Design Bot: if Infantry `9104381136` fails InsertService, fallback Worker → `16134469614` (still realistic), never Part bricks.
