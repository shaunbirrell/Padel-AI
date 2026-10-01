# JOB 45: the Recruit Pack gold trim was missing (claude-bud, 2026-10-01)

## The trace (v170 code, end to end)
1. **ProcessReceipt** (`MonetizationService`, the `RecruitPack` branch):
   - **Cash:** `cashGrant = RecruitPackCashFor(userId, perMin)`. That is the Cash30m time-pack amount (30 min of income,
     floor $25,000, timed boosts left out) while TimePacks is live for him; else the JOB 41 clamp (30 min of income,
     $25,000 to $150,000). Granted with `AddCash(..., "devproduct")`.
   - **Boost:** `CodesService.GrantCashBoost(player, 30, 2)`, inside a `pcall`, so a failure was silent. It writes
     `profile.CashBoost = { Until, Mult = 2 }` and the `WE_CashBoostUntil` attribute (the HUD timer).
   - **Entitlement:** `MonetizationService.GrantEntitlement("RecruitPack")` sets `profile.Entitlements.RecruitPack`
     and the `WE_Ent_RecruitPack` attribute.
   - The receipt is saved before `PurchaseGranted` and is idempotent per PurchaseId (`markProcessed`).
2. **On join:** the profile load rehydrates every saved entitlement and calls `setEntitlementAttr`, so
   `WE_Ent_RecruitPack` is set again on every join and server.
3. **Consumers of the attribute (git grep on origin/phase-7-polish):**
   - `BaseSignService`: a "RECRUIT · " text prefix and a thicker stroke on the gate sign's BillboardGui.
   - `BaseMarkerService`: a `Recruit` flag; the marker client draws a gold stroke, but the marker hides itself inside
     60 studs of your own base.
   - `RecruitPackService`: an ownership check that stops re-offering the pack (not a visual).

## Root cause
No code ever built anything on the base geometry for the entitlement. The JOB 41 "gold base trim" was a text prefix
plus a stroke on the sign billboard, and a marker outline you cannot see at your own base. So Shaun saw no visual
change.

This was claude-bud's own JOB 41 part B implementation: the promise ("a gold base trim") was not met.
Proof: `tools/sim/run_recruit_trim_test.py`, the "BEFORE" line.

## What Shaun was granted at ~11:37 (what can and cannot be shown from here)
- The claude-bud desktop session has no DataStore / Open Cloud access, so the actual profile and receipt record of
  that purchase can NOT be read from here. Nothing is claimed about it.
- By the code, the receipt grants:
  - the cash (the Cash30m amount at his income at that moment, at least $25,000);
  - the 2x boost for 30 min, if `CodesService.GrantCashBoost` did not error (it was silent before this job);
  - the entitlement.
- From now on every Recruit Pack receipt logs `[RECRUIT] receipt <id> <name>: cash $N (...)` and
  `[RECRUIT] boost <name>: granted (until <unix>)` or `FAILED ...`.
- **Code Bot:** read Shaun's profile (Open Cloud / DataStore): `ProcessedReceipts`, the cash history around 11:37,
  `CashBoost.Until`, `Entitlements.RecruitPack`. Nothing was granted or refunded by claude-bud.

## The fix (`Services/RecruitTrimService`, `RecruitTrimConfig`)
- **What:** a GOLD GATE ARCH just inside his main gate. Two gold-clad pillars (slate plinth, gold base, fluted gold
  shaft, capital, cap, a star finial) and a gold crossbeam with a dark trim band. Under it, a dark banner with gold
  edges reading "★ RECRUIT ★" (a SurfaceGui on both faces, MaxDistance 80).
- **Build:** 29 Parts, metal / reflectance 0.25, no lights, non-colliding (it never blocks the 14-stud gate lane or the
  army). It lives in its own Workspace.WE_RecruitTrim folder, never a `WE_Building*` part.
- **When:**
  - The `WE_Ent_RecruitPack` change signal builds it the moment the receipt grants it (no rejoin).
  - A 5 s sweep rebuilds it after a join, a new server, a plot claim, a rebirth or a map rebuild, and removes it when
    the plot is released.
  - It is gated on `RecruitPackLiveFor` + the entitlement; `RecruitTrimConfig.Enabled = false` builds nothing.
- `[RECRUIT]` logs on every attribute change, build and removal.

## Owed (needs Studio / a device)
- Before / after screenshots of Shaun's base (desktop + 1024x471).
- Check the arch clears the gate guard posts / sandbags at his wall level; `RecruitTrimConfig.InsetStuds` / `PillarGap` are
  the knobs.

## Code Bot v172 (2026-10-01): shipped together with the v171 trim, placement fixed
- Shaun approved BOTH trims: v171's gold wall bands / stripes, gate-post bands and finials (BaseTierBuilder, inside
  WE_BaseTier) and this arch (Workspace.WE_RecruitTrim). Both follow `RecruitPackLiveFor` + the RecruitPack entitlement.
- The JOB 45 spot (4 studs in from the PLOT edge) was inside the front wall's body: the wall stands 1.5 in from the pad
  edge and is 3.5-6.3 studs thick (walls Lv 1-5), so the pillars (plot z 154.9-157.1) clipped it, and the 60-stud
  raycast for the ground could land on the GateArch / gatehouse and float the arch.
- Now (`RecruitTrimService.Placement`): the two GatePost parts give the gate, the WallGate_* body its thickness and
  height, the post bottoms the floor. The pillars stand `WallClearStuds` behind max(wall half + 0.8, `GateFurnitureStuds`
  2.6) (clear of the gate arch / chevron, the post roofs, the Tier 3 gatehouse, the Bastion crest and the v171 bands),
  in front of the guards (10 in); the arch is `HeightOverWall` (5) over the wall so it reads from outside and the banner
  hangs above the gate opening. The 5 s sweep rebuilds it when the walls change. No walls: the old spot, at the pad top.
- Detail: 35 parts (plinth, base, fluted shaft + collar, capital, cap, stem + star finial on the beam per pillar; beam +
  engraved band; banner on two gold rods, gold-edged on four sides). Proof: run_recruit_trim_test.py section 7
  (walls Lv 1-5 and a turned plot: no overlap, on the pad, above the wall, inside the wall, no coplanar faces).
- Still owed: an in-Studio / live look at Shaun's base (screenshots).
