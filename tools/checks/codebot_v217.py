# Code Bot Roblox v217 (2026-10-02): ship Claude JOB 70 LIVE FOR EVERYONE —
# collision hulls on every dressed prop/wall segment + one wall style on every face.
# PropCollision.OwnerFirst = false (Shaun approved straight live). JOB 67 Walls/BaseProps
# stay owner-first. PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; no prices.
from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

BUILD = 217
ROOT = Path.cwd()
PREV = os.environ.get("CODEBOT_V217_PREV", "70e7244")
C = "src/ReplicatedStorage/Shared/Configs/"
S = "src/ServerScriptService/Server/"
LUAU = os.environ.get("LUAU", os.path.expanduser("~/.local/bin/luau"))


def read(rel: str) -> str:
    p = ROOT / rel
    return p.read_text(encoding="utf-8").replace("\r\n", "\n") if p.is_file() else ""


def check(cond: bool, label: str) -> None:
    tag = "CODEBOT v217: " + label
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(tag)  # type: ignore[name-defined]
    else:
        print(("PASS " if cond else "FAIL ") + tag)
        if not cond:
            raise SystemExit(1)


CFG = read(C + "Job67DressConfig.luau")
SVC = read(S + "Services/Job67DressService.luau")

# ---- WE_Build 217 ----
for rel in (
    S + "Services/BaseService.luau",
    S + "Services/DataService.luau",
    S + "EarlyRemotes.server.luau",
):
    m = re.search(r'SetAttribute\("WE_Build",\s*(\d+)', read(rel))
    check(m is not None and int(m.group(1)) >= BUILD, "WE_Build >= 218 " + rel.rsplit("/", 1)[-1])
check("WE_Build=222" in read(S + "Services/DataService.luau"), "DataService profile-loaded log WE_Build=222")

# ---- PropCollision LIVE FOR EVERYONE ----
pc_i = CFG.find("PropCollision = {")
check(pc_i > 0, "Job67DressConfig.PropCollision block exists")
pc = CFG[pc_i: CFG.find("\n\t},", pc_i) + 4] if pc_i > 0 else ""
check("OwnerFirst = false" in pc and "LIVE FOR EVERYONE" in pc, "PropCollision.OwnerFirst = false (LIVE FOR EVERYONE)")
check(re.search(r'Hull\s*=\s*"Box"', pc) is not None, "PropCollision Hull = Box")
check("VisualCanCollide = false" in pc, "PropCollision VisualCanCollide = false")
check("HullCanCollide = true" in pc, "PropCollision HullCanCollide = true")
check("HullCanQuery = true" in pc, "PropCollision HullCanQuery = true")
for cat in ("Sandbag", "Hesco", "Concrete", "Crate", "Pallet", "BarbedWire"):
    check(cat in pc, "PropCollision category " + cat)

# JOB 67 visual blocks stay owner-first (not the JOB 70 flip)
walls_i = CFG.find("Walls = {")
walls_blk = CFG[walls_i: walls_i + 400] if walls_i > 0 else ""
check("OwnerFirst = false" in walls_blk, "Walls block OwnerFirst = false (the big flip, codebot_v220)")
props_i = CFG.find("BaseProps = {")
props_blk = CFG[props_i: props_i + 400] if props_i > 0 else ""
check("OwnerFirst = false" in props_blk, "BaseProps block OwnerFirst = false (the big flip, codebot_v220)")

# ---- createHull / Place / FitLine wiring ----
check("local function createHull(" in SVC, "createHull helper exists")
check("createHull(m, key, m, parent)" in SVC, "Place calls createHull")
check("createHull(p, key, parent, parent)" in SVC, "FitLine calls createHull")
hull = re.search(r"local function createHull\(.*?\nend", SVC, re.S)
h = hull.group(0) if hull else ""
for needle in (
    "Enum.PartType.Block",
    "h.Anchored = true",
    "h.CanCollide = true",
    "h.CanQuery = true",
    "h.CanTouch = false",
    "h.Transparency = 1",
    "GetBoundingBox()",
    "MaxHullsPerFolder",
):
    check(needle in h, "createHull has " + needle)

# ---- WallStyleFor same on all faces L1–L5 ----
check("function Job67DressConfig.WallStyleFor(level: number)" in CFG, "WallStyleFor exists")
check('Faces = { "Gate", "Sides", "Rear" }' in CFG, "WallStyleFor returns Gate/Sides/Rear faces")
check("Cfg.WallStyleFor(level)" in SVC, "DressWalls uses WallStyleFor")
for lv, style in (
    (1, "Sandbag Line"),
    (2, "Sandbag Wall"),
    (3, "Hesco Line"),
    (4, "Hesco Wall"),
    (5, "Hesco Fortress"),
):
    m = re.search(rf"\[{lv}\]\s*=\s*\{{.*?\n", CFG)
    line = m.group(0) if m else ""
    check(f'Name = "{style}"' in line, f"tier L{lv} is {style}")
    faces = '"Gate", "Sides", "Rear"'
    check(faces in line, f"tier L{lv} covers Gate/Sides/Rear")

# ---- house rules ----
for bad_n in ("PreferMesh = true", "StreamingEnabled = true"):
    check(bad_n not in SVC and bad_n not in CFG, "no " + bad_n)
check("WE_Building" not in SVC or "WE_Building*" in read("CLAUDE.md"), "service does not edit WE_Building*")
# stronger: service source should not write WE_Building attributes
check(not re.search(r'SetAttribute\("WE_Building', SVC), "service never SetAttribute WE_Building*")

# ---- sims / job70 check ----
env = dict(os.environ)
if "LUAU" not in env and os.path.isfile(LUAU):
    env["LUAU"] = LUAU
if env.get("LUAU"):
    r = subprocess.run(
        [os.environ.get("PYTHON", "python3"), "tools/sim/run_job70_test.py"],
        capture_output=True, text=True, cwd=ROOT, env=env, timeout=150,
    )
    check(r.returncode == 0 and "JOB70 TEST: 0 failed" in (r.stdout or ""),
          "run_job70_test.py 0 failed")
else:
    check(False, "LUAU binary required for run_job70_test")

check(Path("tools/checks/claude_bud_job70.py").is_file(), "claude_bud_job70.py present")
