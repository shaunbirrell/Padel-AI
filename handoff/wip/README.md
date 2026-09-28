# WIP patches (NOT built, NOT live)

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
| 01 | army-fix-ship | 4d26673 | Army despawn fix (FIX) merged onto the bank-escort commit, with the 5 open review issues closed. Fix round r1 was **half-done**: CrossClearStuds 0, FallY -8 and the cheap Lows were being edited. Still to do: re-measure (GATECAMP, UNDER, hall with guards down, T3 owner and non-owner), gates vs 4d26673, a 4e07fc2 rebuild, and review. |
| 02 | capture | e506c9c | Central Plaza capture fix-2. Code, drivers and gates were done; deliverables and the review round were not. It needs a 3-way merge onto 4e07fc2. |
| 03 (+03b base) | army lane B (checkpoints/garrisons) | capture fix-1 tree (= e506c9c + 03b) | Fix-3 passed both reviewers. It needs a rebase onto the shipped capture (02) and HEAD, then gates again. A stray "fix4" attempt was scratch and was not saved. |
| 04 (+04b base) | army lane A (guard outside, follow when leaving, walk around walls) | e506c9c + old FIX + A0 (= 04b) | Code is written; tests T2/T3/T4/T10/T11/T12 and gates were **half-done**. It must be rebased onto the shipped 01, not the old FIX. |
| 05 | harbor (real boat + dock building) | e506c9c | Fix-3 is built and gated, waiting for its review round. |
| 06 | faces (floating faces / soldier look) | e506c9c | Fix-3 is built and gated, waiting for its review round. |
| 07 | ground2 (records only: rejected ground picks) | e506c9c | NOT_READY. It depends on the VKIT ground bodies (11). The five RETIRED rows from air2 are in `notes/07-ground2/`. |
| 08 | air fix-2 (rotor scope, zoom clamp, isOwnDriveObject) | 4e07fc2 | Built and gated on HEAD, waiting for review. |
| 09 | VKIT framework (Part-built vehicle bodies) | e506c9c | Done. It is also contained in 10, 11 and 12. |
| 10 | VKIT air fix-1c | 4e07fc2 | Built and gated, waiting for review. It includes the framework. |
| 11 | VKIT ground fix-2 | 4e07fc2 | **Half-done**: the code was written and the gates were running. It includes the framework and the air ChaseZoom hunk. |
| 12 | VKIT naval fix-1b | e506c9c | Built and gated; deliverables were half-done. It includes the framework and the air fix-1b shared files. |

10, 11 and 12 overlap: each carries its own copy of the framework files. Merge them in the order framework, air, ground, naval,
keeping both sides' lane hunks (VehicleBodies/*.luau, VehicleBodyBuilder, VehicleConfig, VehicleDriveClient, BuyPathStatic).

`notes/<lane>/` holds each lane's phone_test.md, owner_text.md and assumptions.md; `notes/army_design_spec.md` is the army design
(lanes FIX, A0, A, B, C; D and E not built).
