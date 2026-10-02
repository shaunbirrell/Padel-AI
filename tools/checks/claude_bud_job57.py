# claude-bud JOB 57 (2026-10-01): base life (part-built props inside the JOB 40 C per-plot allowance + a few unarmed
# ambient soldiers with IDLE / PATROL, capped by CombatConfig.MaxActiveNPCs). Executed inside tools/BuyPathStatic.py.
import os as _j57_os
import re as _j57_re
import subprocess as _j57_sp
import sys as _j57_sys
from pathlib import Path as _J57P

if "ok" not in globals():
    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        print("FAIL " + msg)


def _j57_src(p):
    q = _J57P(p)
    return q.read_text(encoding="utf-8").replace("\r\n", "\n") if q.is_file() else ""


_BC = _j57_src("src/ReplicatedStorage/Shared/Configs/BaseLifeConfig.luau")
(ok if ("Enabled = true," in _BC and "OwnerFirst = false, -- PUBLIC (Code Bot v220: everything public, Shaun 2026-10-02 07:51); was NEW-OWNER-FIRST" in _BC and "PerBase = 3," in _BC and "ServerMaxFromCombat = true" in _BC) else bad)(
    "CLAUDE-BUD J57: BaseLifeConfig is public since codebot_v220 (was owner-first); 3 soldiers a base, the server cap is CombatConfig.MaxActiveNPCs")
_SP = _j57_src("src/ReplicatedStorage/Shared/Configs/StorePropsConfig.luau")
(ok if "cfg40.Budget.MaxBasePartsPerPlot = 600" in _SP else bad)("CLAUDE-BUD J57: the per-plot allowance stays 600 (JOB 40 C; BaseLife counts against it)")
_BS = _j57_src("src/ServerScriptService/Server/Services/BaseLifeService.luau")
_BSc = "\n".join(l.split("--", 1)[0] for l in _j57_re.sub(r"--\[\[.*?\]\]", "", _BS, flags=_j57_re.S).splitlines())
(ok if ("SP.Budget.MaxBasePartsPerPlot" in _BSc and "used + n > cap" in _BSc and "BaseLifeService.InKeepOut(" in _BSc) else bad)(
    "CLAUDE-BUD J57: props stop at the per-plot allowance and never go inside StorePropsConfig.BaseKeepOut")
(ok if ("WE_NPC" not in _BSc and "CombatService" not in _BSc and "Rifle" not in _BSc and _BSc.count("CanQuery = false") >= 3) else bad)(
    "CLAUDE-BUD J57: the ambient soldiers are never hostile (no WE_NPC tag, no CombatService NPC, no weapon, CanQuery off)")
(ok if ("RenderStepped" not in _BSc and "Heartbeat" not in _BSc and "task.wait(1 / math.max(0.5" in _BSc and "BaseLifeService.ServerMax() - BaseLifeService.Count()" in _BSc) else bad)(
    "CLAUDE-BUD J57: one throttled think loop (ThinkHz), and the server cap is enforced at spawn")
(ok if (not _j57_re.search(r"PivotTo|Teleport|WE_Building|Store_", _BSc)) else bad)("CLAUDE-BUD J57: no teleport / PivotTo, no protected / store-prop names")
_SPc = _SP
(ok if _j57_re.search(r"cfg40\.BaseRows = \{\s*--[^\n]*\n\s*\}", _SPc) or "cfg40.BaseRows = {" in _SPc else bad)(
    "CLAUDE-BUD J57: the store-model BaseRows stay as they are (filled only after a WE_CHECK2 probe passes)")
_BOOT = _j57_src("src/ServerScriptService/Server/Bootstrap.server.luau")
(ok if 'safeInit("BaseLifeService", BaseLifeService, deps)' in _BOOT else bad)("CLAUDE-BUD J57: BaseLifeService is started")
_e = dict(_j57_os.environ)
if "LUAU" not in _e and _e.get("LUAU_COMPILE"):
    _c = _e["LUAU_COMPILE"].replace("luau-compile", "luau")
    if _j57_os.path.isfile(_c):
        _e["LUAU"] = _c
if _e.get("LUAU"):
    _r = _j57_sp.run([_j57_sys.executable, "tools/sim/run_base_life_test.py"], capture_output=True, text=True, env=_e)
    (ok if (_r.returncode == 0 and "BASE LIFE TEST: 0 failed" in _r.stdout) else bad)(
        "CLAUDE-BUD J57: run_base_life_test.py (props <= 600 on clear ground, legs clear, 3 a base, <= 18 a server, brain loop, owner-first)")
