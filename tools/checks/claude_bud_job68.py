"""Guard for the claude-bud JOB 68 queue entry (Code Bot, 2026-10-01 22:37): the shooting-range specification is pinned.

claude-bud (2026-10-01): made BuyPathStatic-safe. BuyPathStatic execs every tools/checks script inside its own globals,
so the repo root is the working directory (not __file__), results go through ok / bad (no SystemExit), and the
commit-time "docs-only worktree" diff guard is gone (it was true for Code Bot's queue commit only and would fail on any
later src change). The JOB 68 implementation replaces this file with its real checks.
"""
from pathlib import Path as _J68P

if "ok" not in globals():
    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        print("FAIL " + msg)


_J68_CLAUDE = (_J68P("CLAUDE.md").read_text(encoding="utf-8") if _J68P("CLAUDE.md").is_file() else "")
_j67 = _J68_CLAUDE.find("- **JOB 67 —")
_j68 = _J68_CLAUDE.find("- **JOB 68 — SHOOTING RANGE LIFE")
(ok if (_j67 >= 0 and _j68 > _j67) else bad)("CLAUDE-BUD J68: the JOB 68 entry follows JOB 67 in the queue")
_blk = _J68_CLAUDE[_j68:_J68_CLAUDE.find("\n- **", _j68 + 5)] if _j68 >= 0 else ""
for _ph in ("red bullseye target boards", "3–4 shooters per range", "client-side cosmetic only", "single shared low-rate loop",
            "no per-NPC Heartbeat", "within about 80 studs", "OwnerFirst=true", "tools/checks/claude_bud_job68.py"):
    (ok if _ph in _blk else bad)("CLAUDE-BUD J68: the queue entry pins " + _ph)

# ── claude-bud JOB 68 implementation: the range soldiers fire (client cosmetic, owner-first) ─────────────────────────
import os as _j68_os
import subprocess as _j68_sp
import sys as _j68_sys

_j68_rd = lambda p: (_J68P(p).read_text(encoding="utf-8") if _J68P(p).is_file() else "")
_j68_cfg = _j68_rd("src/ReplicatedStorage/Shared/Configs/RangeLifeConfig.luau")
_j68_ctl = _j68_rd("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/RangeLifeController.luau")
_j68_snd = _j68_rd("src/ReplicatedStorage/Shared/Configs/SoundConfig.luau")
_j68_boot = _j68_rd("src/StarterPlayer/StarterPlayerScripts/Client/Bootstrap.client.luau")
(ok if ("OwnerFirst = true" in _j68_cfg and "Enabled = true" in _j68_cfg and "NearStuds = 80" in _j68_cfg and "MaxPerYard = 4" in _j68_cfg) else bad)(
    "CLAUDE-BUD J68: RangeLifeConfig Enabled + OwnerFirst = true, effects within 80 studs, <= 4 shooters per range")
(ok if ('safeInit("RangeLifeController"' in _j68_boot) else bad)("CLAUDE-BUD J68: RangeLifeController is started by the client Bootstrap")
for _ph in ("Heartbeat", "RenderStepped", "Stepped", "GetDescendants", "PointLight", "SpotLight", "SurfaceLight", "Neon", "FireServer", "InvokeServer"):
    (ok if _ph not in _j68_ctl else bad)("CLAUDE-BUD J68: RangeLifeController has no `" + _ph + "` (one shared low-rate loop, no lights, cosmetic only)")
(ok if ('GetInstanceAddedSignal("WE_Rig")' in _j68_ctl and "task.wait(period)" in _j68_ctl and _j68_ctl.count("task.spawn(") == 1) else bad)(
    "CLAUDE-BUD J68: the shooters come from the WE_Rig tag; ONE task.wait loop for every range")
(ok if ("e.Shoulder.C0 = e.BaseC0" in _j68_ctl and "Flash:Emit(1)" in _j68_ctl and "e.Puff:Emit(" in _j68_ctl and "cfg.Sounds.Reload" in _j68_ctl) else bad)(
    "CLAUDE-BUD J68: muzzle flash, dust puff + hole, reload arm dip restored after, the magazine sound")
for _k, _md in (("World.RangeShot", "MaxDistance = 80"), ("World.RangeReload", "MaxDistance = 40"), ("World.RangeHit", "MaxDistance = 40")):
    _ln = next((l for l in _j68_snd.splitlines() if ('"' + _k + '"') in l), "")
    (ok if (_md in _ln and 'Bus = "World"' in _ln) else bad)("CLAUDE-BUD J68: SoundConfig " + _k + " is 3D, short range (" + _md + ")")
_j68_e = dict(_j68_os.environ)
if "LUAU" not in _j68_e and _j68_e.get("LUAU_COMPILE"):
    _j68_c = _j68_e["LUAU_COMPILE"].replace("luau-compile", "luau")
    if _j68_os.path.isfile(_j68_c):
        _j68_e["LUAU"] = _j68_c
if _j68_e.get("LUAU"):
    _j68_r = _j68_sp.run([_j68_sys.executable, "tools/sim/run_range_life_test.py"], capture_output=True, text=True, env=_j68_e, timeout=150)
    (ok if (_j68_r.returncode == 0 and "RANGE LIFE TEST: 0 failed" in _j68_r.stdout) else bad)(
        "CLAUDE-BUD J68: run_range_life_test.py (near-only pick, 6 shots + reload loop, holes on the board face)")
