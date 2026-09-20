# GATE DEFENSE WIRE — Design Bot → Code Bot
**Date:** 2026-09-20 · Shaun: 2 guards patrol gate → upgrade to automatic guns, shoot enemy players in range  
**Service:** `GateDefenseService` (Code Bot) · Design owns free ModelAssetIds + placement look only

Standing orders: military-realistic free Models (`AssetTypeId=10`, `IsForSale=false` / PD). Strip all Toolbox scripts on insert. Combat logic stays server-side.

---

## LOOK — Upgrade silhouette

| Level | Read as | Visual |
|-------|---------|--------|
| **L0** | Manpower gate | 2 Guards flanking door, sandbag dress, rifles (character mesh only) |
| **L1** | Auto guns | Same sandbags + **tripod HMG** each flank (no NPC seated required) |
| **L2** (optional later) | Elevated hardpoint | Compact tower+mounted gun **or** keep L1 + taller sandbag nest |

Gate flanks must stay **compact** (footprint ≤ ~8 studs). Do **not** park full Watchtower models on the door as L1 — those belong on Watchtowers structure.

---

## ASSETS

### Guards (L0+)
| Role | ModelAssetId | Catalog | Free | Verdict |
|------|-------------:|---------|------|---------|
| GateGuard / Guard | **16134469614** | Rigged Soldier (NVG/balaclava) | PD | **PRIMARY** — same as VisualAssetConfig.Guard |
| Alt silhouette | 9104381136 | Infantry | PD | Soft alt if Guard insert fails |
| Alt heavy | 14776506955 | HeavyInfantry | PD | Optional L2 “fort gate” look |
| Reject | SWAT / police NPC packs, Respawn plastic `91299598767068` as primary | — | — | Standing order |

**Poses:** Catalog Model is T-pose / idle mesh — Code Bot drives patrol via Humanoid:MoveTo between left/right gate waypoints. No better free “rifle-ready pose pack” found that beats `16134469614` mesh quality. Optional: Tool weld a free rifle Mesh if you already have one in Weapons config; Design does not require a second character Model for pose.

### Automatic guns (L1+)
| Role | ModelAssetId | Catalog | Free | Verdict |
|------|-------------:|---------|------|---------|
| **GateAutoGun** | **4923345827** | Machine Gun Nest | PD / Sale=false | **WINNER** — realistic tripod HMG mesh, compact, military |
| GateAutoGunAlt | 71964514000054 | Military Tower with Mounted Gun Prop | PD | **L2 only** — tall tower+twin gun; has scripts (strip); too tall for door flanks |
| GateAutoGunAlt2 | 10354803684 | Military turret | PD | Same family as tower+roof gun — L2 / corner hardpoint only |
| SandbagNest | **8980890767** | 88th machine gun nest | PD | Circular sandbag ring — dress under/around HMG |
| Sandbags | **3525056989** | Realistic Sandbag | PD | Scatter 2–4 bags at gate posts (already quality-gap min set) |
| SandbagsAlt | 401611044 | Realistic Sandbags | PD | Fallback pile |

### Reject (do not wire)
| Id | Why |
|----|-----|
| 124413214638260 | Blocky Part-kit nest |
| 8278069620 | Concrete block + toy bags |
| 56655624 | Neon-green sensor Part kit + crest decals |
| 81904531124311 / 113285568317438 / 44890775 / 35583702 | Part-kit / stud / green slab turrets |
| 8163827722 | Sci-fi cable sentry |
| Classic “Sentry Gun” TF2 clones (28691128, 150525466, …) | Toy / IP-adjacent |
| Vehicle+turret packs | Not gate props |

### FX (optional, already in presentation set)
- Muzzle / spark: `4221608224` Sparkles  
- Tracer beam (subtle): `88687072714005` — keep short MaxDistance, gunmetal not neon  

---

## Placement notes (GateDefenseService)

Assume gate PrimaryPart at plot front center, facing **out** (+Z or whatever BaseService uses — match existing gate hinge).

```
GateGuard_L  = gate.CFrame * CFrame.new(-6, 0, 2)   -- left flank, slightly forward
GateGuard_R  = gate.CFrame * CFrame.new( 6, 0, 2)
Patrol_L_A/B = ±4 stud along gate line (Humanoid MoveTo loop ~4–6s)
GateAutoGun_L = gate.CFrame * CFrame.new(-7, 0, 1) * CFrame.Angles(0, math.rad(15), 0)
GateAutoGun_R = gate.CFrame * CFrame.new( 7, 0, 1) * CFrame.Angles(0, math.rad(-15), 0)
```

- After `LoadAsset`: strip Scripts/LocalScripts; `ScaleTo` so HMG extents ≈ **4–6 stud** longest axis (don’t squash to plinth).  
- Sandbag nest `8980890767`: scale ~**8 stud** diameter under each gun or one nest centered behind gate.  
- L0: show Guards, hide AutoGuns. L1: show AutoGuns (+ keep Guards if design wants “manned nest”, else despawn Guards).  
- Aim yaw: Code Bot rotates AutoGun PrimaryPart / named `Barrel` toward nearest enemy in range — Design only needs a clear forward barrel axis on `4923345827`.

### Part-kit fallback (only if InsertService rejects 4923345827)
Gunmetal `Part` base 2×0.4×2 + `CylinderHandleAdornment` or Cylinder barrel 0.3×3 + dark seat wedge; Material Metal, Color3 ~ (0.25,0.27,0.28). Prefer catalog mesh.

---

## VisualAssetConfig snippet
```lua
GateDefense = {
  Guard = { ModelAssetId = 16134469614, Note = "Rigged Soldier — gate patrol" },
  AutoGun = { ModelAssetId = 4923345827, Note = "Machine Gun Nest tripod HMG" },
  AutoGunElevated = { ModelAssetId = 71964514000054, Note = "L2 tower+gun — strip scripts" },
  SandbagNest = { ModelAssetId = 8980890767, Note = "Circular sandbag ring" },
  Sandbags = { ModelAssetId = 3525056989, Note = "Realistic Sandbag scatter" },
}
```

---

## NEXT
1. Wire L0 Guards + L1 AutoGun IDs above; strip scripts.  
2. Sandbag dress optional but high polish.  
3. Ping Design Bot on InsertService rejects — next mesh candidates available.  
4. Do not use Watchtower structure ID as gate gun.
