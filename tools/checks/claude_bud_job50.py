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
# ── part B: the run props + annex edge ──
_DRs = _j50_src("src/ServerScriptService/Server/Modules/RebirthZoneDressing.luau")
_bp = _DRs.split("function RebirthZoneDressing.BuildRunProps")[1] if "function RebirthZoneDressing.BuildRunProps" in _DRs else ""
(ok if ("Light\")" not in _bp and "Neon" not in _bp and "WE_Building" not in _bp and "Store_" not in _bp) else bad)(
    "CLAUDE-BUD J50 B: run props + annex edge: no Light objects (JOB 46 / v173 rule), no Neon / WE_Building / Store_ names")
(ok if 'ZC.RebuildLive(player.UserId, "Visuals") and Dressing.BuildRunProps' in _j50_src("src/ServerScriptService/Server/Services/RebirthZoneService.luau") else bad)(
    "CLAUDE-BUD J50 B: the props are built only while Rebuild.Visuals is live (OFF = the JOB 46 dressing exactly)")
# ── part C: the gateway status, the card's run line, his zones on the map (tap-to-pin only) ──
_MSs = _j50_src("src/ServerScriptService/Server/Services/MapService.luau")
(ok if "Zones = zoneRows(player)" in _MSs and "RZ.MapRows" in _MSs else bad)("CLAUDE-BUD J50 C: the map snapshot carries HIS zones (RebirthZoneService.MapRows)")
_RZSs = _j50_src("src/ServerScriptService/Server/Services/RebirthZoneService.luau")
_mr = _RZSs.split("function RebirthZoneService.MapRows")[1].split("\nend\n")[0] if "function RebirthZoneService.MapRows" in _RZSs else ""
(ok if ('ZC.RebuildLive(player.UserId, "Signs")' in _mr and "kioskOf[player.UserId]" in _mr) else bad)("CLAUDE-BUD J50 C: map rows are his own kiosks only, behind Rebuild.Signs")
(ok if ("if t.Text ~= text then" in _RZSs and "ZC.RunRules.StatusRefreshSeconds" in _RZSs) else bad)("CLAUDE-BUD J50 C: the plaque status is refreshed slowly and set only when it changed")
_MCs = _j50_src("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/MapController.luau")
_zt = _MCs.split("-- 3b. claude-bud JOB 50 C")[1].split("-- 4. a named site")[0] if "-- 3b. claude-bud JOB 50 C" in _MCs else ""
(ok if ("Pin = true" in _zt and "ObjectiveMarker.ShowWith" in _zt and not _j50_re.search(r"PivotTo|Teleport|CFrame\s*=", _zt) and 'mapMode ~= "ArmySend"' in _zt) else bad)(
    "CLAUDE-BUD J50 C: tapping his zone on the map only pins it (no fast travel, Normal mode only)")
_RCs = _j50_src("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/RebirthZoneController.luau")
(ok if 'ZC.RebuildLive(player.UserId, "Signs")' in _RCs and "lines[5].Visible = runLine ~= nil" in _RCs else bad)("CLAUDE-BUD J50 C: the preview card's run line is owner-first (OFF = the 4-line card)")
#@@J50ABC@@
