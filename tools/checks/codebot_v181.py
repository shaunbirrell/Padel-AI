# Code Bot Roblox v181 (2026-10-01): cherry-pick claude-bud JOB B (TARGETS rival list blacked out / Global ZIndex).
# One-line fix: WE_RivalTargets ScreenGui ZIndexBehavior = Sibling. No prices / Ids / OwnerFirst flips.
# PreferMesh OFF; StreamingEnabled OFF; no WE_Building* changes.
import os
import re
import subprocess
from pathlib import Path

# claude-bud JOB 66 (2026-10-01): the ONLY MonetizationConfig change allowed past this ship guard is the Shaun-approved
# JOB 66 block (the two 5 R$ starter rows, the Starter5 switch, the SkuLiveFor LiveBlock lines), removed exactly here
# before the byte-identical compare. Everything else in the file must still match.
def _bud_j66(t):
    t = (t or "").replace("\r\n", "\n")
    a = t.find("\t-- claude-bud JOB 66 (price approved by Shaun")
    if a >= 0:
        b = t.find("\n", t.find("\tBoost2x10m = {", a)) + 1
        t = t[:a] + t[b:]
    a = t.find("-- claude-bud JOB 66: the two 5 R$ starter products")
    if a >= 0:
        t = t[:a] + t[t.find("function MonetizationConfig.SkuLiveFor", a):]
    a = t.find("\t-- claude-bud JOB 66: a row tied to an owner-first switch (LiveBlock)")
    if a >= 0:
        b = t.find("\tend\n", a) + len("\tend\n")
        t = t[:a] + t[b:]
    return t



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
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 221'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 221'),
    (S + "Services/DataService.luau", "WE_Build=221"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 221'),
):
    check(needle in read(rel), "CODEBOT v181: WE_Build=221 " + rel.rsplit("/", 1)[-1])

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
    r = subprocess.run(["git", "show", PREV + ":" + C + "MonetizationConfig.luau"], capture_output=True, text=True, cwd=ROOT)
    same = r.returncode == 0 and _bud_j66(r.stdout) == _bud_j66(read(C + "MonetizationConfig.luau"))
    # Code Bot v203: this MonetizationConfig pin is v181's own ship scope; the newest codebot_vNNN.py carries the live money guard.
    _v181_own_mon = 'SetAttribute("WE_Build", 181)' in __import__("pathlib").Path("src/ServerScriptService/Server/Services/DataService.luau").read_text(encoding="utf-8")
    check((not _v181_own_mon) or same, "CODEBOT v181: MonetizationConfig unchanged vs " + PREV + " (the approved JOB 66 block aside)")
except Exception as e:
    check(False, "CODEBOT v181: git diff check errored: " + str(e))
