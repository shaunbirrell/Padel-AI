# Code Bot Roblox v162 (2026-10-01): the army command bug (owner report: "Army SEND -> Crossroads Town -> GO and the army
# stays beside me on FOLLOW; ATTACK says No enemies near"). Root cause (proven, docs/proof/army-command/before-client.log):
# the Army SEND button opened the world map in its normal tap-to-pin mode; a zone card's GO set HIS pin and closed the
# map; no army remote was ever fired, the server never heard of it, FOLLOW stayed. The fix:
#  1. ONE server army state: Modules/ArmyState (Idle / Following / Holding / TravellingToBase / Attacking /
#     EngagingTarget / Capturing / Retreating / Recalling / Regrouping); ArmyState.Set is the one writer of st.Order.
#  2. Modules/ArmyCommand: every army command of a live (owner-first) player, validated, each rejection logged with
#     its reason ([SERVER ARMY] REJECTED) and pushed back; ATTACK with nothing in SeekRadius keeps the state.
#  3. Modules/ArmyTargets: "A:<area>" / "S:<site>" / "B:<plot>" resolved on the server; the destination is an approach
#     point outside the objective (roads first), never his pin.
#  4. ArmyPlan Travel / Retreat plans: the block's lead point travels (one route, not one path per soldier).
#  5. MapController ArmySend mode (OpenForArmySend): GO = SEND ARMY = RequestArmySend(target id), never a pin; the
#     normal map still pins. OrdersController lights the SERVER's state (no optimistic highlight).
#  6. Chain logs ([ARMY SEND] / [SERVER ARMY] / [ARMY STATE] / [ARMY DESTINATION] / [ARMY PATH] / [ARMY MOVE]) only
#     with WE_ArmyDebug (the owner's /armydebug) or Studio. Army Orders stay OwnerFirst.
# Runtime proof: tools/sim/run_army_command_test.py (client + server, every transition, the Crossroads scenario).
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
CL = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/"
_AS = read(S + "Modules/ArmyState.luau")
_ACMD = read(S + "Modules/ArmyCommand.luau")
_AT = read(S + "Modules/ArmyTargets.luau")
_AP = read(S + "Modules/ArmyPlan.luau")
_SQ = read(S + "Services/SquadOrdersService.luau")
_MC = read(CL + "MapController.luau")
_OC = read(CL + "OrdersController.luau")
_AOC = read(C + "ArmyOrdersConfig.luau")
_SEC = read(C + "SecurityConfig.luau")
_LOG = read("src/ReplicatedStorage/Shared/Util/ArmyLog.luau")

# build pins
for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 174)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 174)'),
    (S + "Services/DataService.luau", "WE_Build=174"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 174)'),
):
    check(needle in read(rel), "CODEBOT v162: WE_Build=174 " + rel.rsplit("/", 1)[-1])
check("OwnerFirst = false" in _AOC, "CODEBOT v162: Army Orders OwnerFirst=false (v166 flip-all-live)")
for s in ("Following", "Holding", "TravellingToBase", "Attacking", "EngagingTarget", "Retreating", "Recalling"):
    check("\t%s = true," % s in _AS, "CODEBOT v162: ArmyState has " + s)
check("st.Order = " in _AS and "st.Order = " not in _AP and "\tst.Order = order" not in _SQ,
      "CODEBOT v162: ArmyState.Set is the one writer of st.Order (ArmyPlan / SetOrder go through it)")
check("ArmyCommand.Live(player)" in _SQ and "ArmyCommand.Order(player, stL, orderRaw, source)" in _SQ,
      "CODEBOT v162: a live owner's order goes through ArmyCommand")
check("ArmyCommand.Send(player, plotId)" in _AP and 'ArmyLog.Reject(player, "SEND " .. tostring(plotId), "BadPayload")' in _AP,
      "CODEBOT v162: RequestArmySend -> ArmyCommand.Send; no silent return")
check('"NoEnemiesNear"' in _ACMD and "keep the previous state" in _ACMD, "CODEBOT v162: ATTACK with nothing near = rejected, state kept")
check('RequestArmySend = { "number|string:40" }' in _SEC, "CODEBOT v162: RequestArmySend carries a plot id or a target id")
check('"^A:' in _AT or "A:" in _AT, "CODEBOT v162: ArmyTargets resolves map areas")
check("function MapController.OpenForArmySend()" in _MC and 'if mode == "ArmySend" then' in _MC
      and "Constants.RemoteNames.RequestArmySend, tid)" in _MC, "CODEBOT v162: the map's ArmySend GO fires the army remote")
check('button(row, "SendArmy", "SEND ARMY", 150)' in _MC and "FastTravel" not in _MC, "CODEBOT v162: SEND ARMY kept, no fast travel")
check("pcall(MC.OpenForArmySend)" in _OC and "currentOrder = orderId" not in _OC and "STATE_BUTTON[payload.State]" in _OC,
      "CODEBOT v162: Army SEND opens ArmySend mode; the highlight is the server state")
check("ArmyLog.ForceOn = false" in _LOG and 'GetAttribute("WE_ArmyDebug")' in _LOG, "CODEBOT v162: chain logs gated (WE_ArmyDebug / Studio)")
for f in (_AS, _ACMD, _AT):
    check("PivotTo" not in f and ":MoveTo(" not in f, "CODEBOT v162: no teleport / direct move in the command modules")

# runtime: the full chain in the sim
if os.environ.get("SKIP_SIM") != "1":
    env = dict(os.environ)
    env.setdefault("LUAU", os.path.expanduser("~/.local/bin/luau"))
    r = subprocess.run([sys.executable, "tools/sim/run_army_command_test.py"], cwd=str(ROOT), env=env, capture_output=True, text=True, timeout=900)
    tail = (r.stdout or "").strip().splitlines()[-1:] or ["(no output)"]
    check(r.returncode == 0, "CODEBOT v162: tools/sim/run_army_command_test.py " + tail[0])
