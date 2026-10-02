# Code Bot Roblox v218 (2026-10-02): ship Claude JOB 69 A/B/C + JOB 68 owner-first.
# JOB 69 A: every rebirth zone on every plot (Rebuild.Slots via RebuildLive).
# JOB 69 B+C: how to play everywhere (Rebuild.HowTo + HowTo util + ZoneRunController).
# JOB 68: shooting range life (RangeLifeConfig OwnerFirst). JOB 64 held (Creator Hub).
# PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; no prices; OwnerFirst stays true.
from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

BUILD = 218
ROOT = Path.cwd()
C = "src/ReplicatedStorage/Shared/Configs/"
S = "src/ServerScriptService/Server/"
CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
LUAU = os.environ.get("LUAU", os.path.expanduser("~/.local/bin/luau"))


def read(rel: str) -> str:
    p = ROOT / rel
    return p.read_text(encoding="utf-8").replace("\r\n", "\n") if p.is_file() else ""


def check(cond: bool, label: str) -> None:
    tag = "CODEBOT v218: " + label
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(tag)  # type: ignore[name-defined]
    else:
        print(("PASS " if cond else "FAIL ") + tag)
        if not cond:
            raise SystemExit(1)


RZ = read(C + "RebirthZonesConfig.luau")
RL = read(C + "RangeLifeConfig.luau")
RZS = read(S + "Services/RebirthZoneService.luau")
ZRC = read(CL + "Controllers/ZoneRunController.luau")
RLC = read(CL + "Controllers/RangeLifeController.luau")
HOW = read("src/ReplicatedStorage/Shared/Util/HowTo.luau")

# ---- WE_Build 218 ----
for rel in (
    S + "Services/BaseService.luau",
    S + "Services/DataService.luau",
    S + "EarlyRemotes.server.luau",
):
    m = re.search(r'SetAttribute\("WE_Build",\s*(\d+)', read(rel))
    check(m is not None and int(m.group(1)) >= BUILD, "WE_Build >= 218 " + rel.rsplit("/", 1)[-1])
check("WE_Build=221" in read(S + "Services/DataService.luau"), "DataService profile-loaded log WE_Build=221")

# ---- Rebuild OwnerFirst + Slots + HowTo ----
rb_i = RZ.find("cfg.Rebuild = {")
check(rb_i > 0, "RebirthZonesConfig.Rebuild block exists")
rb = RZ[rb_i: RZ.find("\n}", rb_i) + 2] if rb_i > 0 else ""
# take a bounded slice
rb = RZ[rb_i: rb_i + 500]
check("OwnerFirst = false" in rb, "Rebuild.OwnerFirst = false (public since codebot_v220)")
check("Slots = true" in rb, "Rebuild.Slots = true")
check("HowTo = true" in rb, "Rebuild.HowTo = true")
check("function cfg.RebuildLive(" in RZ, "RebuildLive helper exists")
check('ZC.RebuildLive(owner, "Slots")' in RZS, "RebirthZoneService gates Slots via RebuildLive")
check('ZC.RebuildLive(uid, "HowTo")' in RZS, "RebirthZoneService gates HowTo via RebuildLive")
check("AnnexAlt" in RZ and "function RebirthZonesConfig.ResolveSlots" in RZ, "AnnexAlt + ResolveSlots present")
check('folder:SetAttribute("WE_AnnexCFrame", frame)' in RZS, "WE_AnnexCFrame stamped on zone folder")
check("RebirthZoneService._ZoneBoard" in RZS, "ZONE BOARD fallback present")
check('featurePush(player, "ZoneRunIntro"' in RZS, "ZoneRunIntro how-to card push")
check("function RebirthZoneService.RequestRun" in RZS, "RequestRun start/cancel")
check("HowTo.Live" in HOW and 'RebuildLive(userId, "HowTo")' in HOW, "HowTo.Live uses RebuildLive HowTo")
check('"ZoneRunIntro"' in ZRC and "CardLayout" in ZRC and "CancelChip" in ZRC, "ZoneRunController card + cancel + layout")
check("ObjectiveMarker" in ZRC, "ZoneRunController objective arrow")

# ---- RangeLife OwnerFirst ----
check("OwnerFirst = false" in RL and "Enabled = true" in RL, "RangeLifeConfig Enabled + OwnerFirst = false [public since codebot_v220]")
check("NearStuds = 80" in RL and "MaxPerYard = 4" in RL, "RangeLife near 80 / max 4 per yard")
check('safeInit("RangeLifeController"' in read(CL + "Bootstrap.client.luau"), "RangeLifeController bootstrapped")
for bad_n in ("Heartbeat", "RenderStepped", "Stepped", "GetDescendants", "PointLight", "FireServer", "InvokeServer"):
    check(bad_n not in RLC, "RangeLifeController has no " + bad_n)
check('GetInstanceAddedSignal("WE_Rig")' in RLC and "task.wait(period)" in RLC, "one shared WE_Rig loop")

# ---- house rules ----
svc_blob = RZS + RLC + RZ + RL
for bad_n in ("PreferMesh = true", "StreamingEnabled = true"):
    check(bad_n not in svc_blob, "no " + bad_n)
check(not re.search(r'SetAttribute\("WE_Building', RZS + RLC), "JOB69/68 never SetAttribute WE_Building*")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "PreferMesh stays OFF")

# ---- check files present ----
check(Path("tools/checks/claude_bud_job69.py").is_file(), "claude_bud_job69.py present")
check(Path("tools/checks/claude_bud_job68.py").is_file(), "claude_bud_job68.py present")
check(not Path("src/ReplicatedStorage/Shared/Configs/ReferralConfig.luau").is_file(), "JOB 64 ReferralConfig not shipped (deferred)")

# ---- sims ----
env = dict(os.environ)
if "LUAU" not in env and os.path.isfile(LUAU):
    env["LUAU"] = LUAU
if env.get("LUAU"):
    for script, needle in (
        ("tools/sim/run_zone_slots_test.py", "ZONE SLOTS TEST: 0 failed"),
        ("tools/sim/run_howto_test.py", "HOWTO TEST: 0 failed"),
        ("tools/sim/run_zone_run_layout_test.py", "ZONE RUN LAYOUT TEST: 0 failed"),
        ("tools/sim/run_range_life_test.py", "RANGE LIFE TEST: 0 failed"),
    ):
        r = subprocess.run(
            [os.environ.get("PYTHON", "python3"), script],
            capture_output=True, text=True, cwd=ROOT, env=env, timeout=150,
        )
        check(r.returncode == 0 and needle in (r.stdout or ""), Path(script).name + " 0 failed")
else:
    check(False, "LUAU binary required for v218 sims")
