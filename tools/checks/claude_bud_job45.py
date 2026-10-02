# claude-bud JOB 45 (2026-10-01): the Recruit Pack gold trim (a real gold gate arch on the owner's plot).
import os as _j45_os
import re as _j45_re
import subprocess as _j45_sp
import sys as _j45_sys
from pathlib import Path as _J45P

if "ok" not in globals():
    _j45_fails = []

    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        _j45_fails.append(msg)
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _J45P(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None


def _j45(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J45: " + msg)


def _j45_src(path):
    return (read(path) or "").replace("\r\n", "\n")


_SV = "src/ServerScriptService/Server/"
_CF = "src/ReplicatedStorage/Shared/Configs/"
_RT = _j45_src(_SV + "Services/RecruitTrimService.luau")
_MC = _j45_src(_CF + "MonetizationConfig.luau")
_j45("local RecruitTrimConfig = {\n\tEnabled = true," in _j45_src(_CF + "RecruitTrimConfig.luau") and "RecruitTrim" not in _MC, "RecruitTrimConfig (kill switch; MonetizationConfig untouched)")
_j45('local ATTR = "WE_Ent_RecruitPack"' in _RT and "GetAttributeChangedSignal(ATTR)" in _RT and "MC.RecruitPackLiveFor(player.UserId)" in _RT,
     "the trim follows the EXISTING entitlement (WE_Ent_RecruitPack) and builds the moment it flips")
_RTc = "\n".join(l.split("--", 1)[0] for l in _j45_re.sub(r"--\[\[.*?\]\]", "", _RT, flags=_j45_re.S).splitlines())
_j45("p.CanCollide = false" in _RTc and "WE_Building" not in _RTc and '"WE_RecruitTrim"' in _RT and "PointLight" not in _RT and "MeshPart" not in _RT,
     "non-colliding Parts in Workspace.WE_RecruitTrim; never a WE_Building* part; no lights / meshes")
_j45("task.wait(t.SweepSeconds)" in _RT and "RecruitTrimService.SyncAll()" in _RT, "a sweep rebuilds it after join / rebirth / rebuilds and removes it when the plot is released")
_MS = _j45_src(_SV + "Services/MonetizationService.luau")
_j45('print(string.format("[RECRUIT] receipt' in _MS and '"[RECRUIT] boost "' in _MS or "[RECRUIT] boost %s" in _MS,
     "[RECRUIT] instrumentation on the receipt's cash and boost (the boost was silent inside a pcall)")
_j45("RecruitTrimService" in _j45_src(_SV + "Bootstrap.server.luau"), "Bootstrap wires RecruitTrimService")
_j45(_J45P("docs/proof/recruit-trim/REPORT.md").exists(), "the root-cause trace is written (docs/proof/recruit-trim/REPORT.md)")
_j45("RecruitPack = { Id = 3715776659," in _MC or "RecruitPack = { Id = 0," in _MC, "no Recruit Pack price / Id change in this job")

_luau = _j45_os.environ.get("LUAU")
if _luau is None and _j45_os.environ.get("LUAU_COMPILE"):
    _cand = _j45_os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    _luau = _cand if _j45_os.path.isfile(_cand) else None
if _luau:
    _r = _j45_sp.run([_j45_sys.executable, "tools/sim/run_recruit_trim_test.py"], capture_output=True, text=True, env=dict(_j45_os.environ, LUAU=_luau))
    _j45(_r.returncode == 0 and "RECRUIT TRIM TEST: 0 failed" in _r.stdout, "run_recruit_trim_test.py (purchase, rejoin, non-owner, rebirth, OFF)")
else:
    print("SKIP CLAUDE-BUD J45: Luau CLI tests (set LUAU)")
