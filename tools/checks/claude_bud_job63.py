# claude-bud JOB 63 (2026-10-01): anti-spawn-camping through the ONE protection rule (CombatService pvpBlock /
# InvulnerableUntil), owner-first by the base owner. Executed inside tools/BuyPathStatic.py (ok / bad).
import os as _j63_os
import re as _j63_re
import subprocess as _j63_sp
import sys as _j63_sys
from pathlib import Path as _J63P

if "ok" not in globals():
    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        print("FAIL " + msg)


def _j63_src(p):
    q = _J63P(p)
    return q.read_text(encoding="utf-8").replace("\r\n", "\n") if q.is_file() else ""


_RC = _j63_src("src/ReplicatedStorage/Shared/Configs/RaidConfig.luau")
_ac = _RC.split("(RaidConfig :: any).AntiCamp = {")[1].split("\n}\n")[0] if "(RaidConfig :: any).AntiCamp = {" in _RC else ""
(ok if ("Enabled = true," in _ac and "OwnerFirst = true, -- NEW-OWNER-FIRST" in _ac and "DefenderShieldSeconds = 5," in _ac and "RaiderLimitSeconds = 90," in _ac and "SameBaseCooldownSeconds = 180," in _ac) else bad)(
    "CLAUDE-BUD J63: RaidConfig.AntiCamp is owner-first: 5 s defender shield, 90 s raider limit, 3 min same-base cooldown")
_C = _j63_src("src/ServerScriptService/Server/Services/CombatService/init.luau")
_pb = _C.split("local function pvpBlock(")[1].split("\nend\n")[0] if "local function pvpBlock(" in _C else ""
(ok if ('return "camp_cooldown"' in _pb and "BlocksHurt(attacker, victim)" in _pb) else bad)(
    "CLAUDE-BUD J63: the same-base cooldown is a reason in the ONE pvpBlock (guns, units, turrets, guards, vehicles)")
(ok if ("DefenderShieldSeconds(player)" in _C and "state.InvulnerableUntil = clock() + invuln" in _C and "endCampShield(player)" in _C) else bad)(
    "CLAUDE-BUD J63: the defender shield is the one spawn protection (InvulnerableUntil) and his first shot ends it")
_S = _j63_src("src/ServerScriptService/Server/Services/AntiCampService.luau")
_Sc = "\n".join(l.split("--", 1)[0] for l in _j63_re.sub(r"--\[\[.*?\]\]", "", _S, flags=_j63_re.S).splitlines())
(ok if ("pa:LoadCharacter()" in _Sc and not _j63_re.search(r"PivotTo|Teleport|\.CFrame\s*=", _Sc)) else bad)(
    "CLAUDE-BUD J63: a raider goes home through the normal respawn (LoadCharacter), never a teleport / PivotTo")
(ok if ("RenderStepped" not in _Sc and "Heartbeat" not in _Sc and "task.wait(A.TickSeconds)" in _Sc) else bad)("CLAUDE-BUD J63: one 1 Hz loop (no per-frame work)")
_G = _j63_src("src/ServerScriptService/Server/Services/GateDefenseService.luau")
(ok if "BlocksBaseDamage(attacker, hitPart:GetAttribute(\"PlotId\"))" in _G else bad)("CLAUDE-BUD J63: a cooled raider deals the base no damage")
_RV = _j63_src("src/ServerScriptService/Server/Services/RivalService.luau")
_RVc = _j63_src("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/RivalController.luau")
(ok if ("CooldownLeft(viewer.UserId, plotId)" in _RV and "WAIT %d:%02d" in _RVc) else bad)("CLAUDE-BUD J63: the TARGETS card shows the same-base cooldown")
_BOOT = _j63_src("src/ServerScriptService/Server/Bootstrap.server.luau")
(ok if 'safeInit("AntiCampService", AntiCampService, deps)' in _BOOT else bad)("CLAUDE-BUD J63: AntiCampService is started")
_e = dict(_j63_os.environ)
if "LUAU" not in _e and _e.get("LUAU_COMPILE"):
    _c = _e["LUAU_COMPILE"].replace("luau-compile", "luau")
    if _j63_os.path.isfile(_c):
        _e["LUAU"] = _c
if _e.get("LUAU"):
    _r = _j63_sp.run([_j63_sys.executable, "tools/sim/run_anti_camp_test.py"], capture_output=True, text=True, env=_e, timeout=150)
    (ok if (_r.returncode == 0 and "ANTI CAMP TEST: 0 failed" in _r.stdout) else bad)(
        "CLAUDE-BUD J63: run_anti_camp_test.py (shield, 90 s limit, cooldown re-entry / damage / card / edge, repeat kills, owner-first)")
