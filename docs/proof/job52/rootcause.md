# JOB 52: ATTACK says "No enemies near" with enemies in sight (claude-bud, 2026-10-01)

## Root cause (reproduced in the real ArmyCommand / ArmyPlan / ArmyTargets sim: `attack-range-sim.txt`)
- **The probe was too short:** ATTACK probed from him (the army beside him) with `SeekRadius` = **250** studs
  (ArmyCommand -> ArmyPlan.ProbeClear -> pickSquadTarget).
- **Where awake enemies stand:** in the wake / sleep band, 260-380 studs from the nearest player (OutpostDefender
  WakeStuds 260 / SleepStuds 380, SiteActivity 380). StreamingEnabled is off, so he sees them.
- **Reproduced, flag OFF:** an enemy 260 and 380 studs away both log `REJECTED ... NoEnemiesNear ... radius=250` and
  toast "No enemies near". That is the reported bug.
- **Why a bigger probe alone would not work:**
  - `SeekLeash` (300) dropped them again;
  - the running Clear plan re-sought and fought with `SeekLeash` 300 from him, so even a target found further out
    would be lost on the way;
  - the 3D distance from a Y = 0 centre counted height.
- **Ruled out:** a static no-NPCId figure (only CombatService NPCs are candidates); `UnitMayHitNPC` refusing grouped
  NPCs (the probe sets `probing`).

## Fix (ArmyOrdersConfig.AttackRange, owner-first)
- **One set of radii for the whole order:** SeekStuds **400**, LeashStuds 450, ChainStuds 200. They apply to the
  probe, the plan's seek, its march answer, its fight pick and its leash check. Flat distances.
- **Why 400:** it covers the 260-380 band and is one route leg (LegStuds 400), under 30 s at MarchSpeed 14.
- **The march:** the existing ArmyPlan march (route legs + lead point; no teleport, no PivotTo). The sim's general
  march checks report 0 teleports / 0 snaps.
- **Nothing within 400:** the toast reads "No enemies within 112 m. Nearest: 126 m E" (the game's m = studs x 0.28), or
  "No enemies on the map". A card offers PIN (his own objective marker) and SEND ARMY (`"N:<npcId>"`, resolved on the
  server by ArmyTargets; the client never sends a position).
- **ARMY KILLS:** kills of HIS ordered ATTACK target group count, at most 60 per owner per rolling hour.
  - **Why:** an ordered, targeted fight is real play, and the cap plus "only the ordered group" stop AFK farming.
  - `CreditSteeredAttackKills` (cash) is unchanged.

## Owed
The Studio 2-real-player test (army vs NPCs 300-380 studs out, a shielded player in the way, the PIN / SEND card at
1024x471). This desktop session cannot run Studio Team Test.
