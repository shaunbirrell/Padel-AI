# v165: the SEND siege, the breach and the stalled march (Shaun's phone reports, 2026-10-01)

Sim: `tools/sim/run_army_siege_test.py`. It runs the real ArmyPlan, ArmyRoute, ArmyController, SoldierController and
FormationController. Stand-ins mirror the real attackAimOnly rule (pinned in `tools/checks/codebot_v165.py`): a 55 x 0.85
fire band, an eye ray, the ShootGates fallback, walls a ray or a step can't cross, and a 14-stud gate (`BaseLayoutConfig.MainGateWidth`).
The sim can't run real Roblox PathfindingService or the real map, so route legs come from a wall-aware stand-in.
`--raw` with `ARMY_SRC=<tree>` runs any source tree. The before logs come from the v164 tree.

| Scenario | Before (v164 code) | After (v165) |
|---|---|---|
| SEND to a walled base, owner standing in his yard (`before-siege.log` / `after-siege-24.log`) | gate stuck at 73 %, target = the player 312 times, status `SIEGE gate 73% guns 0`, never breached | gate 100 → 0 from real shots (125 hits), breach, units file through the gate, ATM held, loot 4,321, home |
| 75 soldiers (`after-siege-75.log`) | n/a | breach, in, loot |
| March past another base whose owner stands just inside his wall, 106 studs off the route (`before-march-bystander.log` / `after-march-bystander.log`) | block pinned at (365,73) against his wall for 131 s, status `MARCHING -> Chaplin606's base 44 m` (report 3) | never stands still, reaches the siege and breaches |
| A player in the open shooting the army on the march (`after-march-aggressor.log`) | n/a | answered (killed), then the march goes on |

Root causes:
1. Siege. The siege pick took any hostile within 120 studs (players first), including a player or guard behind the
   wall. No ray could reach him, so nobody fired, and the block steered at him, into the wall.
2. After the breach the phase stayed "Siege", and the lead only moves in March, Loot or Return, so nobody walked in.
3. After the breach, the units not lined up with the 14-stud gate pressed into the wall beside it. The lead waited
   for the block centre (gap > LeadMaxGap), so the ATM was never held.
4. March. On the march the pick took any hostile player within 120 studs, and ArmyController steered the whole block
   at him. A player behind his own base wall pinned the army there while the status still said MARCHING.
