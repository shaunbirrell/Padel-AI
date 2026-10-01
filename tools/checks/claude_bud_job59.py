# claude-bud JOB 59 (2026-10-01): free Creator Store assets pass. Part B (the sound pass) is built; parts A (rotorKit),
# C (lights / props models) and D (vault door) need the WE_CHECK2 / Studio asset pipeline (reported in LATEST-HANDOFF).
# Executed inside tools/BuyPathStatic.py (ok / bad).
import os as _j59_os
import re as _j59_re
import subprocess as _j59_sp
import sys as _j59_sys
from pathlib import Path as _J59P

if "ok" not in globals():
    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        print("FAIL " + msg)


def _j59_src(p):
    q = _J59P(p)
    return q.read_text(encoding="utf-8").replace("\r\n", "\n") if q.is_file() else ""


_SC = _j59_src("src/ReplicatedStorage/Shared/Configs/SoundConfig.luau")
_p59 = _SC.split("SoundConfig.Pass59 = {")[1].split("\n}\n")[0] if "SoundConfig.Pass59 = {" in _SC else ""
(ok if ("Enabled = true," in _p59 and "OwnerFirst = true, -- NEW-OWNER-FIRST" in _p59) else bad)("CLAUDE-BUD J59: SoundConfig.Pass59 is owner-first")
_AU = _j59_src("src/StarterPlayer/StarterPlayerScripts/Client/Modules/AudioController.luau")
(ok if ("RC.Live(P, lp.UserId)" in _AU and "for key, id in pairs(P.Overrides) do" in _AU) else bad)(
    "CLAUDE-BUD J59: the id swaps apply only while Pass59 is live for this player (OFF = today's sounds)")
_AM = _j59_src("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/AmbienceController.luau")
_AMc = "\n".join(l.split("--", 1)[0] for l in _j59_re.sub(r"--\[\[.*?\]\]", "", _AM, flags=_j59_re.S).splitlines())
(ok if ("RC.Live(SC.Pass59, player.UserId)" in _AMc and "RenderStepped" not in _AMc and "Heartbeat" not in _AMc and 'Instance.new("Sound")' not in _AMc) else bad)(
    "CLAUDE-BUD J59: the ambience is owner-first, ticks slowly (no per-frame work) and plays only through AudioController")
_BS = _j59_src("src/StarterPlayer/StarterPlayerScripts/Client/Bootstrap.client.luau")
(ok if 'safeInit("AmbienceController"' in _BS else bad)("CLAUDE-BUD J59: AmbienceController is started by the client bootstrap")
_e = dict(_j59_os.environ)
if "LUAU" not in _e and _e.get("LUAU_COMPILE"):
    _c = _e["LUAU_COMPILE"].replace("luau-compile", "luau")
    if _j59_os.path.isfile(_c):
        _e["LUAU"] = _c
if _e.get("LUAU"):
    _r = _j59_sp.run([_j59_sys.executable, "tools/sim/run_sound_pass_test.py"], capture_output=True, text=True, env=_e)
    (ok if (_r.returncode == 0 and "SOUND PASS TEST: 0 failed" in _r.stdout) else bad)(
        "CLAUDE-BUD J59: run_sound_pass_test.py (every listed id wired, 3D world sounds, loops on the SFX toggle, owner-first, night / desert logic)")
