# claude-bud JOB B (2026-10-01, P0): the TARGETS list was blacked out (Global ZIndex ordering painted the panel over its
# own rows). Pinned by tools/sim/run_targets_list_test.py.
import os as _jb_os
import subprocess as _jb_sp
import sys as _jb_sys

if "ok" not in globals():
    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        print("FAIL " + msg)

_jb_env = dict(_jb_os.environ)
if "LUAU" not in _jb_env and _jb_env.get("LUAU_COMPILE"):
    _c = _jb_env["LUAU_COMPILE"].replace("luau-compile", "luau")
    if _jb_os.path.isfile(_c):
        _jb_env["LUAU"] = _c
_r = _jb_sp.run([_jb_sys.executable, "tools/sim/run_targets_list_test.py"], capture_output=True, text=True, env=_jb_env)
(ok if (_r.returncode == 0 and "TARGETS LIST TEST: 0 failed" in _r.stdout) else bad)(
    "CLAUDE-BUD JB: run_targets_list_test.py (Sibling ordering: the rows / SEND ARMY / VIEW draw above the list panel)")
