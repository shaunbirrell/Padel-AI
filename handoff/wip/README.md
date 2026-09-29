# WIP patches (NOT built, NOT live, except the rows marked SHIPPED in v90)

Saved 2026-09-28 ~19:40 UTC when the owner said "stop and push everything".
Nothing here is wired into the Rojo project; `src/` on this branch is still HEAD 4e07fc2.
Each patch applies cleanly (`git apply --check`) to the base named in its file name, and every changed
`.luau` file in it passes `luau-compile --binary`. Patches whose status below is "half-done" have NOT had
their gates re-run in the saved state.

Apply one: `git worktree add --detach /tmp/w <base>` then `cd /tmp/w && git apply <repo>/handoff/wip/<patch>`.
Then 3-way merge onto the current HEAD (`git merge-file`), insert the lane's BuyPathStatic block once above
`parse_gate()`, append `notes/<lane>/assumptions.md` to ASSUMPTIONS.md, and run the CLAUDE.md §3 gates.

| # | Patch | Base | Status |
|---|---|---|---|
| 01 | army-fix-ship | 4d26673 | **SHIPPED in v90** (Code Bot), owner-only behind `ArmyConfig.Rollout.Fix = "owner"`, merged 3-way onto phase-7-polish. Still open: the r1 re-measure (GATECAMP, UNDER, hall with guards down, T3 owner and non-owner) on a stand-in or device. The patch is kept for reference only. |
| 02 | capture | e506c9c | **SHIPPED in v92** (Code Bot). PersistClaims=false, ReleaseOnLeave=true, StandingBar as Claude wrote. 3-way merge onto phase-7-polish HEAD db5d310; BuyPathStatic pins in tools/BuyPathStatic.py + tools/checks/codebot_v92.py. Phone test: notes/02-capture/phone_test.md (publish with Migrate to Latest Update). |

10, 11 and 12 overlap: each carries its own copy of the framework files. Merge them in the order framework, air, ground, naval,
keeping both sides' lane hunks (VehicleBodies/*.luau, VehicleBodyBuilder, VehicleConfig, VehicleDriveClient, BuyPathStatic).

`notes/<lane>/` holds each lane's phone_test.md, owner_text.md and assumptions.md; `notes/army_design_spec.md` is the army design
(lanes FIX, A0, A, B, C; D and E not built).

## Retired 2026-09-29 (claude-bud JOB 9: "finish or remove cleanly, no half-built stuff")
Removed from this folder; they are still in git history at commit e791323 (`git show e791323:handoff/wip/<file>`).
| # | Patch | Why retired |
|---|---|---|
| 03 / 03b | army lane B (checkpoints / garrisons) | 48 commits stale, needs a rebase onto the shipped capture and the army fix; lane C, which consumes it, was never built |
| 04 / 04b | army lane A (guard outside, follow, walk around walls) | tests and gates half-done, based on the old FIX; the live army (v90 Fix + Follow2 / Tidy) covers guard-outside and formation |
| 07 | ground2 records | NOT_READY, depended on 11; its intent (reject the held truck picks) is applied by hand in VisualAssetConfig |
| 09-12 | VKIT Part-built vehicle bodies (framework, air, ground, naval) | 45-48 commits stale, not owner-gated, +661 parts over main; 11 half-done, 12's deliverables half-done |
`ArmyConfig.Rollout.March` (lane C's never-read flag) and its lane-C-only Text entries are removed from src.
