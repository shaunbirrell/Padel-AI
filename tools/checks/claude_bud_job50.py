# claude-bud JOB 50 (2026-10-01): rebirth zones rebuild + the hotbar caption fix. Part D (hotbar) pinned here first.
import subprocess as _j50_sp
import sys as _j50_sys

if "ok" not in globals():
    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        print("FAIL " + msg)

_r = _j50_sp.run([_j50_sys.executable, "tools/sim/run_hotbar_caption_test.py"], capture_output=True, text=True)
(ok if (_r.returncode == 0 and "HOTBAR CAPTION TEST: 0 failed" in _r.stdout) else bad)(
    "CLAUDE-BUD J50 D: the hotbar caption fits its own slot (fitCaption, no 80 v box) and every weapon ShortName is distinct")
# ── part A: the zone runs ──
from pathlib import Path as _J50P
import re as _j50_re
import os as _j50_os


def _j50_src(p):
    q = _J50P(p)
    return q.read_text(encoding="utf-8").replace("\r\n", "\n") if q.is_file() else ""


_ZC = _j50_src("src/ReplicatedStorage/Shared/Configs/RebirthZonesConfig.luau")
_rb = _ZC.split("cfg.Rebuild = {")[1].split("\n}")[0] if "cfg.Rebuild = {" in _ZC else ""
(ok if ("Enabled = true," in _rb and "OwnerFirst = true, -- NEW-OWNER-FIRST" in _rb) else bad)("CLAUDE-BUD J50 A: RebirthZonesConfig.Rebuild owner-first")
_ZR = _j50_src("src/ServerScriptService/Server/Modules/ZoneRuns.luau")
_step = _ZR.split("function ZoneRuns.Step(")[1].split("\nend\n")[0] if "function ZoneRuns.Step(" in _ZR else ""
(ok if ("player.UserId ~= uid" in _step and "run.Order[run.Step] ~= markerIdx" in _step and "insideAnnex(player, run)" in _step and "run.Deadline" in _step) else bad)(
    "CLAUDE-BUD J50 A: a run step counts only for the owner, in order, inside the annex, before the limit (server-checked)")
_ZRc = "\n".join(l.split("--", 1)[0] for l in _j50_re.sub(r"--\[\[.*?\]\]", "", _ZR, flags=_j50_re.S).splitlines())
(ok if (not _j50_re.search(r"PivotTo|Teleport|\.CFrame\s*=\s*[^\n]*Character", _ZRc) and "MarketplaceService" not in _ZRc and "RobuxPrice" not in _ZRc) else bad)(
    "CLAUDE-BUD J50 A: no teleport / PivotTo, no Robux in the runs")
(ok if ("ZC.RunCash(" in _ZR and "function cfg.RunBase" in _ZC and "cfg.ShipmentCash(zoneId, level, tickSeconds)" in _ZC.split("function cfg.RunBase")[1].split("\nend\n")[0]) else bad)(
    "CLAUDE-BUD J50 A: the run pay goes through the ONE formula (RunBase = max(ShipmentCash, IncomeMinutes x his income))")
_e = dict(_j50_os.environ)
if "LUAU" not in _e and _e.get("LUAU_COMPILE"):
    _c = _e["LUAU_COMPILE"].replace("luau-compile", "luau")
    if _j50_os.path.isfile(_c):
        _e["LUAU"] = _c
if _e.get("LUAU"):
    _r2 = _j50_sp.run([_j50_sys.executable, "tools/sim/run_rebirth_stations_test.py"], capture_output=True, text=True, env=_e)
    (ok if (_r2.returncode == 0 and "REBIRTH STATIONS TEST: 0 failed" in _r2.stdout) else bad)(
        "CLAUDE-BUD J50 A: run_rebirth_stations_test.py (every run: win / fail / timeout, pay = formula, cooldown, first clear, best, effects, recon, wave, plaque)")
#@@J50ABC@@
