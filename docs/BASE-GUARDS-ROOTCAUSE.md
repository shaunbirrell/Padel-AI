# Base guards: root cause of the hostility split (claude-bud JOB 40 part A, 2026-09-30)

## What the owner saw
The guards at the rear-gate posts (Airfield / Helipad / Dock) and the sea-gate quay are statues. MapSetup's
`makeSoldierKit` builds them ANCHORED (`MapSetup.luau` rear gates ~L1525-1550, sea gate ~L1688-1706); RigBuilder marks
an anchored rig `WE_RigStatic` and RigAnimator never animates it. They never shoot.

## The rules in the code before JOB 40
| Path | File | Check |
|---|---|---|
| gate / extra / tower guards (JOB 20) | `Modules/BaseGuards.luau` `hostiles` | `friendlyPlayer` = owner OR `IsAlly` (clan) OR **`EngagementService.AreFriends`**, then `InSpawnGrace` |
| AutoGuns + the old guard think | `Services/GateDefenseService.luau` `isEnemyPlayer` | `not IsAlly(owner, p)` (clan only) + `inSpawnGrace` |
| defender damage on players | `GateDefenseService.dealDamage`, `BaseGuards.hurt` | `hum:TakeDamage` directly |
| the owner's army and his gun | `CombatService.UnitMayHitPlayer` / `ArmyHostility` / `pvpBlock` | PvP on, not self, never a clan ally, the owner not novice-shielded, the victim not spawn / novice shielded |

## Proof (the real BaseGuards code, `tools/sim/run_base_guards_test.py`, the "JOB 20" column = today's check)
| Case | JOB 20 base | The one rule (army / gun) |
|---|---|---|
| the owner | not shot | not shot |
| a clan ally | not shot | not shot |
| a FRIEND who is not in the clan | **not shot** | shot (as his army already does) |
| a stranger | shot | shot |
| a spawn-graced stranger | not shot | not shot (the grace only throttles) |
| a novice-shielded victim | not shot (via its grace check) | not shot (the rule) |
| a novice-shielded OWNER | **his base shoots** | his base fires at nobody (like his army) |
| PvP off | **the base shoots** | nobody is shot |

So the base had a private second rule: it spared friends outside the clan, and ignored PvP-off and the owner's own
novice shield. JOB 40 moves every defence (post guards, gate guards, towers via `BaseGuards.hostiles`, AutoGuns via
`isEnemyPlayer`) onto `BaseGuards.PlayerHostileOneRule` / `UnitHostileOneRule`, which call only
`CombatService.UnitMayHitPlayer`, `ArmyHostility` and `PvPBlockReason`. Hits go through `CombatService.ApplyDefenceHit`
(the same `hurtPlayer`, credited to the base owner) and `CombatService.ApplyHit` for army units.

**Behind the flag:** everything above is behind `GuardConfig.Posts` (owner-first by base owner); off = the JOB 20
checks exactly.

**Still owed:** the Studio 2-player log (Local Server, 2 clients) is still owed:
- `[BaseGuard]` / `[BaseGuardHit]` lines with /armydebug on;
- B on A's helipad;
- B kills a guard;
- B's army;
- A walks past;
- B in A's clan or novice;
- B past the leash.
