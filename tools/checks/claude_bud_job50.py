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
#@@J50ABC@@
