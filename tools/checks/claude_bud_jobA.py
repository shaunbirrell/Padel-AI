# claude-bud JOB A (2026-10-01, P0): the Recruitment Office closed itself ~0.5 s after opening. Root cause + fix pinned
# by tools/sim/run_recruitment_office_test.py (the real EndgameConfig rule + the static open / close paths).
import os as _ja_os
import subprocess as _ja_sp
import sys as _ja_sys

if "ok" not in globals():
    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        print("FAIL " + msg)

_ja_luau = _ja_os.environ.get("LUAU")
if _ja_luau is None and _ja_os.environ.get("LUAU_COMPILE"):
    _c = _ja_os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    _ja_luau = _c if _ja_os.path.isfile(_c) else None
if _ja_luau:
    _r = _ja_sp.run([_ja_sys.executable, "tools/sim/run_recruitment_office_test.py"], capture_output=True, text=True, env=dict(_ja_os.environ, LUAU=_ja_luau))
    (ok if (_r.returncode == 0 and "RECRUITMENT OFFICE TEST (all): 0 failed" in _r.stdout) else bad)(
        "CLAUDE-BUD JA: run_recruitment_office_test.py (root cause numbers, hysteresis, one open / close path, kiosk = his own)")
else:
    print("SKIP CLAUDE-BUD JA: Luau CLI tests (set LUAU)")
