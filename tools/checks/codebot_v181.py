# Code Bot Roblox v181 (2026-10-01): cherry-pick claude-bud JOB B (TARGETS rival list blacked out / Global ZIndex).
# One-line fix: WE_RivalTargets ScreenGui ZIndexBehavior = Sibling. No prices / Ids / OwnerFirst flips.
# PreferMesh OFF; StreamingEnabled OFF; no WE_Building* changes.
import os
import re
import subprocess
from pathlib import Path

ROOT = Path.cwd()
PREV = os.environ.get("CODEBOT_V181_PREV", "67b00aa")  # v180 live tip (place 178)
C = "src/ReplicatedStorage/Shared/Configs/"
S = "src/ServerScriptService/Server/"
CL = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/"


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8").replace("\r\n", "\n")


def check(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 189)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 189)'),
    (S + "Services/DataService.luau", "WE_Build=189"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 189)'),
):
    check(needle in read(rel), "CODEBOT v181: WE_Build=189 " + rel.rsplit("/", 1)[-1])

rc = read(CL + "RivalController.luau")
# JOB B: Sibling ordering on WE_RivalTargets (long comment between Name and the set)
check('g.Name = "WE_RivalTargets"' in rc and "g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling" in rc,
      "CODEBOT v181: WE_RivalTargets sets ZIndexBehavior Sibling")

check("PreferMesh = true" not in read(C + "VisualAssetConfig.luau"), "CODEBOT v181: PreferMesh stays OFF")
check("PreferMeshWhenAssetIdSet = false" in read(C + "StructureVisualConfig.luau"), "CODEBOT v181: PreferMeshWhenAssetIdSet false")
check('"StreamingEnabled": true' not in read("default.project.json"), "CODEBOT v181: StreamingEnabled stays OFF")

# no WE_Building* / MonetizationConfig diffs vs v180 tip
try:
    r = subprocess.run(["git", "diff", "--name-only", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
    touched = [ln for ln in (r.stdout or "").splitlines() if "WE_Building" in ln]
    check(r.returncode == 0 and not touched, "CODEBOT v181: no WE_Building* diffs vs " + PREV + ((" " + str(touched)) if touched else ""))
    r = subprocess.run(["git", "diff", "-U0", PREV, "--", C + "MonetizationConfig.luau"], capture_output=True, text=True, cwd=ROOT)
    changed = [l for l in (r.stdout or "").splitlines() if l[:1] in "+-" and not l.startswith(("+++", "---"))]
    check(r.returncode == 0 and not changed, "CODEBOT v181: MonetizationConfig unchanged vs " + PREV + ((" " + str(changed[:6])) if changed else ""))
except Exception as e:
    check(False, "CODEBOT v181: git diff check errored: " + str(e))
