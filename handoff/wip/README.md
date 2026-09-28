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
| 02 | capture | e506c9c | NOT shipped in v90 (Code Bot kept v90 to the priority lanes). Code, drivers and gates are done; still needs its deliverables, a review round and a 3-way merge onto the v90 HEAD. |
| 03 (+03b base) | army lane B (checkpoints/garrisons) | capture fix-1 tree (= e506c9c + 03b) | Fix-3 passed both reviewers. It needs a rebase onto the shipped capture (02) and HEAD, then gates again. A stray "fix4" attempt was scratch and was not saved. |
| 04 (+04b base) | army lane A (guard outside, follow when leaving, walk around walls) | e506c9c + old FIX + A0 (= 04b) | NOT shipped in v90. Code is written; tests T2/T3/T4/T10/T11/T12 and gates were **half-done**. It must now be rebased onto the v90 army fix (`Rollout.Fix`, `SquadOrdersService._FixLive`), not the old FIX. |
| 05 | harbor (real boat + dock building) | e506c9c | **SHIPPED in v90** for everyone (visual; kill switch `DockKitConfig.Enabled = false`). Pins are in `tools/checks/codebot_v90_harbor.py`. |
| 06 | faces (floating faces / soldier look) | e506c9c | **SHIPPED in v90** for everyone (client-only visual; `GuardHz = 0` / `LeadScreenFrac = 0` revert it). Pins are in `tools/checks/codebot_v90_faces.py`. |
| 07 | ground2 (records only: rejected ground picks) | e506c9c | NOT_READY. It depends on the VKIT ground bodies (11). The five RETIRED rows from air2 are in `notes/07-ground2/`. |
| 08 | air fix-2 (rotor scope, zoom clamp, isOwnDriveObject) | 4e07fc2 | **SHIPPED in v90**. Pins are in `tools/checks/codebot_v90_airfix2.py`. |
| 09 | VKIT framework (Part-built vehicle bodies) | e506c9c | Done. It is also contained in 10, 11 and 12. |
| 10 | VKIT air fix-1c | 4e07fc2 | Built and gated, waiting for review. It includes the framework. |
| 11 | VKIT ground fix-2 | 4e07fc2 | **Half-done**: the code was written and the gates were running. It includes the framework and the air ChaseZoom hunk. |
| 12 | VKIT naval fix-1b | e506c9c | Built and gated; deliverables were half-done. It includes the framework and the air fix-1b shared files. |

10, 11 and 12 overlap: each carries its own copy of the framework files. Merge them in the order framework, air, ground, naval,
keeping both sides' lane hunks (VehicleBodies/*.luau, VehicleBodyBuilder, VehicleConfig, VehicleDriveClient, BuyPathStatic).

`notes/<lane>/` holds each lane's phone_test.md, owner_text.md and assumptions.md; `notes/army_design_spec.md` is the army design
(lanes FIX, A0, A, B, C; D and E not built).
