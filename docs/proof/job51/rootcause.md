# JOB 51: Central Plaza guards vs Laumartinez26: root cause (claude-bud, 2026-10-01)

**Status:** one mechanism is reproduced in the real NPC brain and fixed. The live proof of what happened on Shaun's
server is **owed**: it needs the `/guarddebug` logs from a real 2-player session. This desktop session cannot run
Studio Team Test.

## Who guards the plaza
The `OutpostDefenders` Medium tier (Infantry, HeavyInfantry, HeavyInfantry, Infantry) spawns on a 35-stud ring round
(0, 1, 0):
- GroupId "Outpost.CentralPlaza", Leash 95;
- **no TargetFilter**;
- no owner-first gate on waking or targeting (checked in OutpostDefenderConfig / OutpostDefenders).

## "The guards didn't shoot her": the mechanism (reproduced, `plaza-guards-sim.txt`)
- **The pick ignores protection:** `CombatNPC.NearestPlayer` picked the nearest living player with **no protection
  rule**.
- **The shots then all miss:** `engage()` rolls "miss" against a target with `InvulnerableUntil` in the future, which
  covers the 3 s spawn shield and the F6 novice shield (math.huge). It never switches target.
- **The plaza makes this likely:** the circle is also the emergency / plot-less spawn (`EmergencySpawn` at (0, 5, 0),
  `noPlotDropCFrame` at (0, ~, 40)), so a new player under the novice shield often stands at the centre.
- **Measured** (old brain, a novice-shielded player at the centre, her at the plaza edge 80 studs south): 60 s of
  fighting, **Laumartinez26 hits = 0**, and **340 guaranteed misses** fired at the shielded player.
- **Counter-case, stated honestly:** when she is nearer to even one guard, that guard shoots her in the old brain too
  (10 hits). This mechanism explains "never shot" only when a protected player is nearer to every guard. Otherwise the
  guards simply shot whoever was nearest (Witorlox / esmeekatsavat). That is the existing distance rule, not a bug.

## "She could not damage them": no code-level blocker found
- `hurtNPC` has no hostility gate for player -> NPC.
- Only `CombatService.SpawnNPC` tags `WE_NPC`, and every such model has an `NPCId`. So no "no-id figure" in code can
  eat a shot. (A Studio-placed tag in the place file is not ruled out; the live `[NpcHit]` lines will show it.)
- NPCs carry no ForceField, so the client's `AimTargets.IsHostile` does not skip them.
- **Remaining possibilities**, to be read from the live logs:
  - a claim refusal (`[CombatService] claimed target refused ... npc <id>: <reason>`, always printed);
  - the plaza becoming Held mid-fight (`OutpostDefenders.sleep()` despawns the guards);
  - her shots not reaching the server (`[NpcHit]` lines missing).

## Ruled out in code
- The JOB 40 base guards are already OwnerFirst = false.
- The bank / checkpoint guards are not at the circle.
- `RivalService`'s "shielded" list never reaches NPC targeting.
- There is no plaza safe zone in code (the spawn shield is the normal 3 s).

## The fix (SharedHostility, owner-first)
- **One rule:** `Server/Modules/Hostility` (ProtectedReason / NpcMayTarget / MayHurt), bound by CombatService with
  the existing reasons (no copy).
- **Used everywhere:** EVERY NPC target pick goes through it, and `CheckpointGuardService.Protected` calls it.
- **Result:** a guard skips a shielded player and shoots the nearest one it may hurt. With the rule on, the same
  scene gives her 10 real hits through the same hit roll.

## Spawn finding
A fresh spawn at the circle centre with all four guards awake dies after **5.9 s**, which is ~2.9 s of exposure after
the 3 s shield. The emergency / plot-less spawn is inside the defenders' aggro (ring 35 + AggroRange 90). Moving the
spawn or the ring needs a Studio check of clear ground, so it is NOT moved blind here.

## How to get the live proof (2 real players)
1. Both players in the same server. On the owner, type `/guarddebug on`.
2. Stand in the circle as in the screenshot. The server output then shows:
   - `[GuardTarget] npc=... cands={Laumartinez26 d=.. ok; esmeekatsavat d=.. shielded:novice; ...} -> <target>`;
   - `[GuardShot] ... hit / miss:invulnerable / miss:roll`;
   - for her shots, `[NpcHit] Laumartinez26 how=Exact|Claim|Assist|Miss claimNpc=... dealt=true|false`.
3. Paste those lines here.
