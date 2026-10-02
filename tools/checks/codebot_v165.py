# Code Bot Roblox v165 (2026-10-01): owner phone reports 1 + 3 (SEND siege stood at the wall "gate 100% guns 0";
# "ARMY: MARCHING ->" but the army stood still by another base's wall / around a player).
#  1. Siege: nothing behind the standing walls is a siege target (the gate is); breach -> Phase Loot, the lead walks
#     in; the broken-gate funnel (ArmyController.Funnel) files units through the 14-stud gate both ways.
#  3. March: only a player (or his soldiers, JOB 43 "Unit") who HURT this army in the last MarchAnswerSeconds,
#     within MarchAnswerStuds and not behind a walled plot, is answered; a stuck path request is re-asked after
#     RoutingTimeoutSeconds; [ARMY MOVE] wait reasons.
# The siege sim's stand-ins mirror the strings pinned below. PreferMesh OFF; ArmyOrders / ArmyBrawl OwnerFirst kept.
from pathlib import Path
import os
import subprocess
import sys

ROOT = Path.cwd()


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def check(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


S = "src/ServerScriptService/Server/"
C = "src/ReplicatedStorage/Shared/Configs/"
for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 223'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 223'),
    (S + "Services/DataService.luau", "WE_Build=223"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 223'),
):
    check(needle in read(rel), "CODEBOT v165: WE_Build=223 " + rel.rsplit("/", 1)[-1])

SQ = read(S + "Services/SquadOrdersService.luau")
AP = read(S + "Modules/ArmyPlan.luau")
ACt = read(S + "Modules/ArmyController.luau")
GD = read(S + "Services/GateDefenseService.luau")
AOC = read(C + "ArmyOrdersConfig.luau")
for cond, label in (
    ("(OrdersConfig.AttackRange or 55) * 0.85" in SQ, "attackAimOnly fire band = AttackRange x 0.85 (the sim stand-in)"),
    ('tgt.Kind == "Player" or tgt.Kind == "Guard" or tgt.Kind == "Structure" or tgt.Kind == "Unit"' in SQ, "attackAimOnly Structure/Unit path (ShootGates fallback)"),
    ("local function behindWalls(info: any, pos: Vector3): boolean" in AP, "ArmyPlan.behindWalls"),
    ("t = nil -- Code Bot v165: behind the walls: the gate first" in AP, "siege: a target behind the standing walls is dropped"),
    ("not (shut and behindWalls(info, tu.Part.Position))" in AP, "siege: turrets behind the standing walls skipped"),
    ('plan.Funnel = gateFunnelOf(info)' in AP and 'plan.Phase = "Loot"' in AP, "breach -> Funnel + Phase Loot"),
    ("Funnel = p.Funnel" in AP and "ArmyController.Funnel(planLead.Funnel, upos, goal)" in ACt, "the broken-gate funnel reaches every unit"),
    ("st._acTarget = marchAnswer(pick, player, st, proot, centre, C.Siege.ReachStuds + 40)" in AP, "SEND march: marchAnswer only"),
    ("st._acTarget = marchAnswer(pick, player, st, proot, centre, 160)" in AP, "TRAVEL march: marchAnswer only"),
    ("cs.RecentlyHurtBy(player, t.Player, C.MarchAnswerSeconds or 10)" in AP, "marchAnswer: aggressors only"),
    ("gd.WalledPlotAt" in AP and "function GateDefenseService.WalledPlotAt(pos: Vector3): number?" in GD, "marchAnswer: never a player behind a walled plot"),
    ("RoutingTimeoutSeconds or 20" in AP and "RoutingTimeoutSeconds = 20" in AOC, "routing watchdog"),
    ("(plan :: any).RouteSeq ~= seq" in AP and "pa.RouteSeq = seq" in AP, "a re-plan supersedes a slow path request"),
    ("MarchAnswerStuds = 60" in AOC and "MarchAnswerSeconds = 10" in AOC, "ArmyOrdersConfig march answer knobs"),
    ("PadCenter = def.PadCenter" in GD, "SiegeInfo returns the walled plot"),
):
    check(cond, "CODEBOT v165: " + label)

env = os.environ.copy()
for script, label in (
    ("tools/sim/run_army_siege_test.py", "CODEBOT v165: run_army_siege_test"),
    ("tools/sim/run_army_command_test.py", "CODEBOT v165: run_army_command_test"),
    ("tools/sim/run_army_march_test.py", "CODEBOT v165: run_army_march_test"),
    ("tools/sim/run_army_orders_test.py", "CODEBOT v165: run_army_orders_test"),
):
    if not (ROOT / script).is_file():
        check(False, label + " missing")
        continue
    r = subprocess.run([sys.executable, script], cwd=str(ROOT), env=env, capture_output=True, text=True, timeout=900)
    tail = [ln for ln in (r.stdout or "").splitlines() if ln.strip()][-3:] or [((r.stderr or "")[-200:])]
    check(r.returncode == 0 and " 0 failed" in (r.stdout or ""), label + " " + (tail[-1] if tail else f"exit={r.returncode}"))
