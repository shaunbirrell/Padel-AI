# claude-bud JOB 38 (2026-09-30): ARMY ATTACK ORDERS, owner-first (ArmyOrdersConfig.Live): ATTACK auto-clear, SEND to a
# base (siege / breach / army raid), RECALL, the fairness rules (DECIDED by the owner), AutoGun HP, the ARMY KILLS board.
# Static pins + the real-code test (tools/sim/run_army_orders_test.py).
import os as _j38_os
import re as _j38_re
import subprocess as _j38_sp
import sys as _j38_sys
from pathlib import Path as _J38P

if "ok" not in globals():
    _j38_fails = []

    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        _j38_fails.append(msg)
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _J38P(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None


def _j38(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J38: " + msg)


def _j38_src(path):
    return (read(path) or "").replace("\r\n", "\n")


def _j38_code(path):
    s = _j38_re.sub(r"--\[\[.*?\]\]", "", _j38_src(path), flags=_j38_re.S)
    return "\n".join(l.split("--", 1)[0] for l in s.splitlines())


_SV = "src/ServerScriptService/Server/"
_CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
_AOC = _j38_src("src/ReplicatedStorage/Shared/Configs/ArmyOrdersConfig.luau")
_AP = _j38_code(_SV + "Modules/ArmyPlan.luau")
_AR = _j38_code(_SV + "Modules/ArmyRoute.luau")
_SQ = _j38_code(_SV + "Services/SquadOrdersService.luau")
_AC = _j38_code(_SV + "Modules/ArmyController.luau")
_SC = _j38_code(_SV + "Modules/SoldierController.luau")
_GD = _j38_code(_SV + "Services/GateDefenseService.luau")
_MC = _j38_code(_SV + "Services/MoneyCollectorService.luau")
_SEC = _j38_src("src/ReplicatedStorage/Shared/Configs/SecurityConfig.luau")

# flags + the decided numbers
_j38("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = true, -- only UserId 470626172" in _AOC and "RetentionConfig.Live(ArmyOrdersConfig.Live, userId)" in _AOC,
     "one owner-first kill switch (ArmyOrdersConfig.Live)")
for _s in ("SendCooldownSeconds = 300,", "ProtectAfterSiegeSeconds = 600,", "MinPowerRatio = 0.25,", "BullyRatio = 4,", "ArmyLootMult = 0.5,",
           "RequireOwnerAlive = false,", "VictimLeftCooldownSeconds = 150,", "SeekRadius = 250,", "ChainRadius = 150,", "MaxChain = 4,",
           "SeekLeash = 300,", "MarchSpeed = 14,", "LegStuds = 400,", "RouteRetries = 3,", "SiegeMaxSeconds = 240,"):
    _j38(_s in _AOC, "the decided / specified number " + _s)
# no teleport / fast travel / forced moves in the plan path
for _name, _code in (("ArmyPlan", _AP), ("ArmyRoute", _AR)):
    _j38("PivotTo" not in _code and "TeleportService" not in _code and "Root.CFrame =" not in _code and ":MoveTo(" not in _code and "FastTravel" not in _code,
         _name + ": no PivotTo / teleport / fast travel / direct MoveTo")
_j38("local allow = not drivingFast and not walkBack and planLead == nil" in _AC and "NoReposition = planLead ~= nil," in _AC,
     "during a plan ArmyController allows no recover / reposition (AllowRecover false, NoReposition)")
_j38("if ctx.NoReposition == true then\n\t\t\tunit._scLost = true" in _SC, "a plan's unit that falls out of the world is marked LOST, never moved")
_j38("root = planLead.Root :: any" in _AC and "ArmyController.PlanLead = ArmyPlan.LeadFor" in _AP.replace("AC.PlanLead = ArmyPlan.LeadFor", "ArmyController.PlanLead = ArmyPlan.LeadFor"),
     "the SAME steered block follows the plan's lead point (FormationController.Plan unchanged)")
_j38("flatDist(plan.Lead, centre) > C.LeadMaxGap then\n\t\tplan.LeadVel = Vector3.zero" in _AP and "ArmyRoute.Advance(plan.Lead, route, plan.RouteIdx, C.MarchSpeed, dt)" in _AP,
     "the lead walks at MarchSpeed and waits for the block (no catch-up hack)")
# one hostility rule: the plan calls THE pick
_j38("local function pickSquadTarget(player: Player, st: SquadState, proot: BasePart?, planOpts: any?)" in _SQ
     and "pcall(SquadOrdersService._Plan.Think, player, st, proot, pickSquadTarget, now)" in _SQ and "local ok = pcall(pick, player, st, proot, opts)" in _AP,
     "ONE target pick (pickSquadTarget, the one hostility rule) for the ordered and the plan paths")
# remotes
_j38("RequestArmySend = { \"number\" }," in _SEC and "RequestArmySendCheck = { \"number\" }," in _SEC
     and 'require(script.Parent.RemoteGate).Check(player, "RequestArmySend", plotId)' in _AP, "RemoteGate schemas: RequestArmySend / Check carry the plot id only")
_j38('pcall(SquadOrdersService._Plan.Recall, player' not in _SQ and 'SquadOrdersService._Plan.Recall(player, if orderRaw == "Recall" then nil else orderRaw' in _SQ,
     "RECALL goes through RequestSquadOrder (a string, the existing schema)")
# raids share the rules
_j38("local function raidChecks(thief: Player, victim: Player, army: boolean)" in _MC and "return raidChecks(thief, victim, false)" in _MC
     and "return raidChecks(sender, victim, true)" in _MC and "MoneyCollectorService._MoveLoot(sender, victim, steal)" in _MC,
     "CanArmyRaid shares CanRaid's checks; the army loot uses the same money path")
# the SEND owner-away rule only for SEND; turrets
_j38("opts.OwnerAway == true" in _GD and "if not ownerAway then" in _GD, "owner-away damage only with the SEND option (every other path keeps the alive check)")
_j38("GateDefenseService._TurretHit(def, hitPart, amount, attacker)" in _GD and "AOC.TurretHP.Enabled ~= true or not AOC.LiveFor(attacker.UserId)" in _GD
     and "tu.DeadUntil = nowClock()" in _GD, "AutoGun HP through the gate damage path (players and armies), rebuild timer")
# no forced damage / fast travel
_j38(_j38_re.search(r"\.Health\s*=[^=]", _AP) is None and "TakeDamage" not in _AP, "ArmyPlan never sets Health or calls TakeDamage")
_j38("FastTravel" not in _j38_code(_CL + "Controllers/MapController.luau") and 'button(row, "SendArmy", "SEND ARMY", 150)' in _j38_src(_CL + "Controllers/MapController.luau"),
     "the map adds ONE button (SEND ARMY) and no fast travel")
# the ARMY KILLS board (addendum)
_LB = _j38_src("src/ReplicatedStorage/Shared/Configs/LeaderboardConfig.luau")
# Code Bot v156 (Shaun 2026-10-01): the board has its own switch (ArmyKillsBoardLive), live for everyone while army
# orders stay owner-first; see tools/checks/codebot_v156.py. TOP ARMY stays defined (the switch off = the old board).
_j38('Id = "ArmyKills", Title = "ARMY KILLS", Unit = "kills", AllTime = true, Weekly = true' in _LB and "LeaderboardConfig.ArmyKillsBoardLive = true" in _LB and '{ Id = "Army", Title = "TOP ARMY"' in _LB,
     "ARMY KILLS replaces TOP ARMY in the same slot (its own switch, live for everyone; new store key WE_LB2_ArmyKills)")
_j38("function EngagementService.NoteArmyKill(" in _j38_code(_SV + "Services/EngagementService.luau") and 'killCounted and killer and typeof(_info) == "table" and _info.WeaponId == "Squad"' in _j38_code(_SV + "Services/EngagementService.luau"),
     "army kills of players reuse the MOST KILLS kill rules (no self / clan / farmed pair)")

_luau = _j38_os.environ.get("LUAU")
if _luau is None and _j38_os.environ.get("LUAU_COMPILE"):
    _cand = _j38_os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    _luau = _cand if _j38_os.path.isfile(_cand) else None
if _luau:
    _r = _j38_sp.run([_j38_sys.executable, "tools/sim/run_army_orders_test.py"], capture_output=True, text=True, env=dict(_j38_os.environ, LUAU=_luau))
    _j38(_r.returncode == 0 and "ARMY ORDERS TEST: 0 failed" in _r.stdout, "run_army_orders_test.py (real rules / route / plan)")
else:
    print("SKIP CLAUDE-BUD J38: Luau CLI test (set LUAU)")
